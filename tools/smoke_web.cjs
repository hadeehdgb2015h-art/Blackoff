// Headless browser smoke test for a web build.
//   node tools/smoke_web.cjs <dir> [screenshot.png]
// Serves <dir> on a random port, opens it in Chromium (landscape phone viewport,
// touch enabled), waits for the engine to start and fails on page errors.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = path.resolve(process.argv[2] || 'build/web');
const shot = process.argv[3];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.txt': 'text/plain' };

const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const file = p.endsWith('/') ? path.join(p, 'index.html') : p;
  if (!file.startsWith(dir) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  const errors = [];
  const logs = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { logs.push(`[${m.type()}] ${m.text()}`); if (m.type() === 'error') errors.push(m.text()); });
  // Telegram SDK is irrelevant here; abort it so the test does not depend on telegram.org.
  await page.route('https://telegram.org/**', (r) => r.abort());
  await page.goto(url);
  try {
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 90000 });
    await page.waitForTimeout(3000);
  } catch (e) {
    errors.push('engine did not start: ' + e.message);
  }
  if (shot) await page.screenshot({ path: shot });
  await browser.close();
  server.close();
  console.log(logs.slice(-15).join('\n'));
  const real = errors.filter((e) => !/telegram\.org|ERR_FAILED|Failed to load resource/.test(e));
  if (real.length) { console.error('SMOKE FAIL:\n' + real.join('\n')); process.exit(1); }
  console.log('SMOKE OK');
})().catch((e) => { console.error(e); process.exit(1); });
