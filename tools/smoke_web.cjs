// Headless browser smoke test for a web build.
//   node tools/smoke_web.cjs <dir> [screenshot.png] [query] [seconds]
// e.g. query "?autostart=1&bot=1" plays solo practice with the test bot.
// SMOKE_URL=http://host/ tests a deployed site instead of serving <dir>;
// SMOKE_TG_INITDATA=<signed initData> makes the page look like a Telegram Mini App.
// Serves <dir> on a random port, opens it in Chromium (landscape phone viewport,
// touch enabled), waits for the engine to start and fails on page errors.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = path.resolve(process.argv[2] || 'build/web');
const shot = process.argv[3];
const query = process.argv[4] || '';
const seconds = Number(process.argv[5] || 3);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.txt': 'text/plain' };

const server = http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  const file = p.endsWith('/') ? path.join(p, 'index.html') : p;
  if (!file.startsWith(dir) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
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

(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = process.env.SMOKE_URL || `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
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
  if (shot) await page.screenshot({ path: shot, timeout: 180000 });  // software GL can take a while per frame
  await browser.close();
  server.close();
  console.log(logs.slice(-25).join('\n'));
  if (/SCRIPT ERROR|USER ERROR/.test(logs.join('\n'))) errors.push('engine reported script errors');
  const real = errors.filter((e) => !ignorable(e));
  if (real.length) { console.error('SMOKE FAIL:\n' + real.join('\n')); process.exit(1); }
  console.log('SMOKE OK');
})().catch((e) => { console.error(e); process.exit(1); });
