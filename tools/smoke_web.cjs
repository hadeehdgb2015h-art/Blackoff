// Headless browser smoke test for a web build.
//   node tools/smoke_web.cjs <dir> [screenshot.png] [query] [seconds]
// e.g. query "?autostart=1&bot=1" plays solo practice with the test bot.
// SMOKE_CACHE=1 loads twice and checks the second visit downloads no big file;
// SMOKE_CACHE_NEXT=<dir2> serves dir2 (a newer build) on the second visit and
// checks only the files whose names changed are downloaded;
// SMOKE_URL=http://host/ tests a deployed site instead of serving <dir>;
// SMOKE_TG_INITDATA=<signed initData> makes the page look like a Telegram Mini App.
// SMOKE_VOICE=1 gives Chromium a fake microphone (a tone, then silence, looping)
// and checks that voice frames are sent and that frames from others are played
// (pair it with ?voice=1 and server/tools/voiceBot.ts on the same server).
// Serves <dir> on a random port, opens it in Chromium (landscape phone viewport,
// touch enabled), waits for the engine to start and fails on page errors.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

let dir = path.resolve(process.argv[2] || 'build/web');
const shot = process.argv[3];
const query = process.argv[4] || '';
const seconds = Number(process.argv[5] || 3);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.txt': 'text/plain', '.json': 'application/json' };

const served = {};  // path -> times sent (the cache test reads it)
const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const file = p.endsWith('/') ? path.join(p, 'index.html') : p;
  if (!file.startsWith(dir) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  served[path.basename(file)] = (served[path.basename(file)] || 0) + 1;
  // like the deployed nginx: hashed files immutable, the rest revalidated
  const immutable = /\.[0-9a-f]{12}\.(js|wasm|pck)$/.test(file);
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream',
    'cache-control': immutable ? 'public, max-age=31536000, immutable' : 'no-cache' });
  fs.createReadStream(file).pipe(res);
});

// Multi-touch: hold the move stick forward, drag-aim on the right, then hold
// FIRE, all with real touch events. Verifies movement, aiming and firing.
async function touchScenario(page) {
  const cdp = await page.context().newCDPSession(page);
  const vp = page.viewportSize();
  const k = vp.height / 720;                  // canvas_items stretch, 720 base height
  const vw = vp.width / k;                    // virtual width
  const fire = { x: (vw - 155) * k, y: (720 - 165) * k };
  const stick = { x: 150 * k, y: (720 - 160) * k };
  const aim = { x: vp.width * 0.62, y: vp.height * 0.35 };
  const state = () => page.evaluate(() => window.__blackoff && { ...window.__blackoff });
  const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points });
  // the menu shows a loading curtain before the game scene: wait for the game
  await page.waitForFunction(() => window.__blackoff, null, { timeout: 60000 }).catch(() => {});
  const before = await state();
  if (!before) throw new Error('no debug state (is ?debug=1 set?)');
  await touch('touchStart', [{ x: stick.x, y: stick.y, id: 1 }]);
  for (let i = 1; i <= 10; i++) {
    await touch('touchMove', [{ x: stick.x, y: stick.y - 8 * i, id: 1 }]);
    await page.waitForTimeout(30);
  }
  await touch('touchStart', [{ x: stick.x, y: stick.y - 80, id: 1 }, { x: aim.x, y: aim.y, id: 2 }]);
  for (let i = 1; i <= 8; i++) {
    await touch('touchMove', [{ x: stick.x, y: stick.y - 80, id: 1 }, { x: aim.x + 10 * i, y: aim.y, id: 2 }]);
    await page.waitForTimeout(40);
  }
  await touch('touchEnd', [{ x: stick.x, y: stick.y - 80, id: 1 }]);
  await page.waitForTimeout(1500);
  const moved = await state();
  await touch('touchStart', [{ x: fire.x, y: fire.y, id: 3 }]);
  await page.waitForTimeout(150);
  await touch('touchEnd', []);
  await page.waitForTimeout(1200);
  const after = await state();
  const dist = Math.hypot(moved.x - before.x, moved.z - before.z);
  console.log(`touch: moved ${dist.toFixed(2)} m, yaw ${before.yaw.toFixed(2)} -> ${moved.yaw.toFixed(2)}, shots ${before.shots} -> ${after.shots}`);
  if (dist < 0.3) throw new Error('move stick did not move the player');
  if (Math.abs(moved.yaw - before.yaw) < 0.05) throw new Error('aim drag did not turn the camera');
  if (after.shots <= before.shots) throw new Error('fire button did not fire');
}

// A WAV for Chromium's fake microphone: 1.5 s of a 440 Hz tone, 0.5 s of silence (looped by Chromium).
function fakeMicWav() {
  const rate = 48000, secs = 2, n = rate * secs;
  const pcm = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) {
    const v = i < rate * 1.5 ? Math.round(0.4 * 32767 * Math.sin((2 * Math.PI * 440 * i) / rate)) : 0;
    pcm.writeInt16LE(v, i * 2);
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  const file = path.join(require('os').tmpdir(), 'blackoff-fake-mic.wav');
  fs.writeFileSync(file, Buffer.concat([h, pcm]));
  return file;
}

(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = process.env.SMOKE_URL || `http://127.0.0.1:${server.address().port}/`;
  const voiceWav = process.env.SMOKE_VOICE === '1' ? fakeMicWav() : null;
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      ...(voiceWav ? ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--use-file-for-fake-audio-capture=' + voiceWav,
        '--autoplay-policy=no-user-gesture-required'] : []),
      // a plain-HTTP rehearsal site must count as a secure context, as HTTPS would
      ...(process.env.SMOKE_URL ? ['--unsafely-treat-insecure-origin-as-secure=' + new URL(process.env.SMOKE_URL).origin] : [])],
  });
  const scale = Number(process.env.SMOKE_DPR || 2);
  const page = await browser.newPage({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: scale });
  const errors = [];
  const logs = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { logs.push(`[${m.type()}] ${m.text()}`); if (m.type() === 'error') errors.push(m.text()); });
  // Telegram SDK is irrelevant here; abort it so the test does not depend on telegram.org.
  await page.route('https://telegram.org/**', (r) => r.abort());
  if (process.env.SMOKE_TG_INITDATA) {
    await page.addInitScript((initData) => {
      window.Telegram = { WebApp: {
        initData, platform: 'smoke', version: '6.0', ready() {}, expand() {},
        isVersionAtLeast() { return false; }, HapticFeedback: { impactOccurred() {} },
        // like a phone in Telegram's fullscreen: its buttons on top, a gesture bar on the right
        safeAreaInset: { top: 0, right: 24, bottom: 0, left: 0 },
        contentSafeAreaInset: { top: 56, right: 0, bottom: 0, left: 0 },
      } };
    }, process.env.SMOKE_TG_INITDATA);
  }
  await page.goto(url + query);
  try {
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 90000 });
    await page.waitForTimeout(seconds * 1000);
  } catch (e) {
    errors.push('engine did not start: ' + e.message);
  }
  const ignorable = (e) => /telegram\.org|ERR_FAILED|Failed to load resource/.test(e);
  if (process.env.SMOKE_TOUCH === '1' && errors.filter((e) => !ignorable(e)).length === 0) {
    try { await touchScenario(page); } catch (e) { errors.push('touch scenario: ' + e.message); }
  }
  // Software GL in CI can run far below real time: give the expected line extra time.
  for (let i = 0; i < 120 && process.env.SMOKE_EXPECT && !logs.join('\n').includes(process.env.SMOKE_EXPECT); i++) {
    await page.waitForTimeout(500);
  }
  if (process.env.SMOKE_EXPECT && !logs.join('\n').includes(process.env.SMOKE_EXPECT)) {
    errors.push('expected log line not found: ' + process.env.SMOKE_EXPECT);
  }
  if (process.env.SMOKE_CACHE === '1') {
    try {
      // first visit: the service worker installs and keeps the hashed files
      await page.waitForFunction(() => navigator.serviceWorker.controller || navigator.serviceWorker.getRegistration().then((r) => r && r.active), null, { timeout: 60000 });
      await page.waitForTimeout(1500);
      const before = JSON.parse(JSON.stringify(served));
      let expected = [];
      if (process.env.SMOKE_CACHE_NEXT) {   // a newer build: only files with new names may be fetched
        const old = fs.readdirSync(dir);
        dir = path.resolve(process.env.SMOKE_CACHE_NEXT);
        expected = fs.readdirSync(dir).filter((f) => /\.(wasm|pck)$/.test(f) && !old.includes(f));
      }
      await page.goto(url + query);
      await page.waitForFunction(() => window.BLACKOFF_LOAD, null, { timeout: 120000 });
      const load = await page.evaluate(() => window.BLACKOFF_LOAD);
      const again = Object.keys(served).filter((f) => /\.(wasm|pck)$/.test(f) && served[f] > (before[f] || 0));
      logs.push('[cache] second visit: ' + JSON.stringify(load) + ' big files fetched from the server: ' + JSON.stringify(again) + ' expected: ' + JSON.stringify(expected));
      if (again.sort().join() !== expected.sort().join()) errors.push('second visit downloaded ' + JSON.stringify(again) + ', expected ' + JSON.stringify(expected));
      if (!(await page.evaluate(() => !!navigator.serviceWorker.controller))) errors.push('page not controlled by the service worker');
    } catch (e) { errors.push('cache scenario: ' + e.message); }
  }
  if (voiceWav) {
    try {
      // the game turned the mic on (?voice=1): frames must have been encoded and sent,
      // and whatever the voice bot said must have been decoded and scheduled for playback
      let st = {};
      for (let i = 0; i < 60; i++) {
        st = JSON.parse(await page.evaluate(() => window.BlackoffVoice ? window.BlackoffVoice.status() : '{}'));
        if (st.sent > 0 && st.played > 0) break;
        await page.waitForTimeout(500);
      }
      logs.push('[voice] ' + JSON.stringify(st));
      if (st.mic !== 'on') errors.push('microphone not on: ' + JSON.stringify(st));
      if (!(st.sent > 0)) errors.push('no voice frames sent: ' + JSON.stringify(st));
      if (!(st.played > 0)) errors.push('no voice frames played: ' + JSON.stringify(st));
    } catch (e) { errors.push('voice scenario: ' + e.message); }
  }
  if (shot) await page.screenshot({ path: shot, timeout: 180000 });  // software GL can take a while per frame
  await browser.close();
  server.close();
  console.log(logs.slice(-25).join('\n'));
  if (/SCRIPT ERROR|USER ERROR/.test(logs.join('\n'))) errors.push('engine reported script errors');
  const real = errors.filter((e) => !ignorable(e));
  if (real.length) { console.error('SMOKE FAIL:\n' + real.join('\n')); process.exit(1); }
  console.log('SMOKE OK');
})().catch((e) => { console.error(e); process.exit(1); });
