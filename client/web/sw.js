// Blackoff service worker: keeps the game files on the phone between visits.
// Every engine and data file has a content hash in its name (tools/hash_web_build.py),
// so a cached file is always valid, and a new build only downloads the files
// whose names changed. index.html, config.js and manifest.json always come
// from the network (they are tiny and point at the current files).
const BUILD = '__BLACKOFF_BUILD__';
const CACHE = 'blackoff-files';
const HASHED = /\.[0-9a-f]{12}\.(js|wasm|pck)$/;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const res = await fetch('manifest.json', { cache: 'no-store' });
    const manifest = await res.json();
    const cache = await caches.open(CACHE);
    const wanted = manifest.files.map((f) => new URL(f, self.registration.scope).href);
    for (const url of wanted) {
      if (await cache.match(url)) continue; // already kept from an earlier build
      try {
        await cache.add(new Request(url, { cache: 'force-cache' })); // the page just downloaded it: usually a cache hit
      } catch (e) { /* offline or a missing file: the page fetches it itself next time */ }
    }
    // keep only the current build's files
    for (const req of await cache.keys()) {
      if (!wanted.includes(req.url)) await cache.delete(req);
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (!HASHED.test(url.pathname) && !/\.png$/.test(url.pathname)) return; // html, config, manifest, ws: network
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(event.request, { ignoreSearch: true });
    if (hit) return hit;
    const res = await fetch(event.request);
    if (res.ok && HASHED.test(url.pathname)) cache.put(event.request, res.clone()).catch(() => {});
    return res;
  })());
});

self.addEventListener('message', (event) => {
  if (event.data === 'build') event.source.postMessage({ build: BUILD });
});
