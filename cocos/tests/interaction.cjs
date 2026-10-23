const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const url = process.env.SAMPLE_URL || 'http://127.0.0.1:4173/?review=1';
const center = r => ({ x: r.x + r.width / 2, y: r.y + r.height / 2 });
const closeTo = (a, b, tolerance = 2) => Math.abs(a - b) < tolerance;

(async () => {
  const browser = await chromium.launch({ channel: process.env.BROWSER_CHANNEL || 'chrome', headless: true });
  const errors = [], engineWarnings = [], results = [];
  async function create(options) {
    const ctx = await browser.newContext(options);
    const page = await ctx.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() !== 'error') return;
      const text = message.text();
      // Creator 3.8.8's web touch adapter calls preventDefault without checking
      // cancelable. Chromium reports this during synthetic pinch / cancellation.
      if (/^Ignored attempt to cancel a touch(start|cancel) event with cancelable=false, for example because scrolling is in progress and cannot be interrupted\.$/.test(text)) engineWarnings.push(text);
      else errors.push(text);
    });
    await page.goto(url); await page.waitForLoadState('networkidle');
    await page.waitForFunction(() => window.__STARTX_SAMPLE__?.().ready, null, { timeout: 20000 });
    return { ctx, page, state: () => page.evaluate(() => window.__STARTX_SAMPLE__()) };
  }
  try {
    fs.mkdirSync(path.join(root, 'review'), { recursive: true });
    const mobile = await create({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
    const { page, state } = mobile;
    const cdp = await mobile.ctx.newCDPSession(page);
    const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points.map((p, i) => ({ ...p, id: i, radiusX: 4, radiusY: 4, force: 1 })) });
    async function tapAction(name) { const s = await state(); const p = center(s.controls[name]); await page.touchscreen.tap(p.x, p.y); await page.waitForTimeout(80); }
    let s = await state(); assert.equal(s.wide, false);
    for (const r of Object.values(s.controls)) assert.ok(r.width >= 44 && r.height >= 44, 'Touch target below 44 CSS pixels');
    let p = center(s.card); await page.touchscreen.tap(p.x, p.y);
    await page.waitForFunction(() => window.__STARTX_SAMPLE__().modal === 'detail');
    await tapAction('Back');
    s = await state(); p = center(s.card);
    await touch('touchStart', [p]); await page.waitForTimeout(550);
    await touch('touchEnd', []);
    assert.equal((await state()).modal, 'menu');
    await tapAction('MenuReset');
    s = await state(); p = center(s.card);
    await touch('touchStart', [p]);
    for (let i = 1; i <= 6; i++) { await touch('touchMove', [{ x: p.x + i * 7, y: p.y - i * 5 }]); await page.waitForTimeout(20); }
    await touch('touchEnd', []);
    s = await state(); assert.ok(s.position.x > 40 && s.position.y > 20); assert.equal(s.modal, 'none');
    await tapAction('ZoomIn'); assert.ok((await state()).zoom > 1);
    await tapAction('ZoomOut'); assert.ok(closeTo((await state()).zoom, 1, 0.01));
    // Pinch on blank board; the remaining finger must not become an accidental card drag.
    s = await state();
    const y = s.viewport.y + s.viewport.height * 0.72;
    await touch('touchStart', [{ x: 120, y }, { x: 270, y }]);
    await touch('touchMove', [{ x: 95, y }, { x: 295, y }]);
    await touch('touchEnd', []);
    assert.ok((await state()).zoom > 1.2);
    await tapAction('Reset');
    s = await state(); assert.ok(closeTo(s.position.x, 0) && closeTo(s.position.y, 0)); assert.equal(s.zoom, 1);
    // An interrupted drag restores the last committed card position.
    p = center(s.card); await touch('touchStart', [p]);
    await touch('touchMove', [{ x: p.x + 38, y: p.y + 25 }]);
    await touch('touchCancel', []); s = await state();
    assert.ok(closeTo(s.position.x, 0) && closeTo(s.position.y, 0)); assert.equal(s.modal, 'none');
    await page.waitForTimeout(180);
    await page.screenshot({ path: path.join(root, 'review/portrait.png') });
    results.push('390×844 touch: detail, long press, drag, zoom buttons, pinch, reset, touch cancellation');
    await mobile.ctx.close();

    const desktop = await create({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
    const dp = desktop.page, ds = desktop.state;
    async function clickAction(name) { const t = center((await ds()).controls[name]); await dp.mouse.click(t.x, t.y); await dp.waitForTimeout(80); }
    s = await ds(); assert.equal(s.wide, true); p = center(s.card);
    await dp.mouse.move(p.x, p.y); await dp.mouse.down(); await dp.mouse.move(p.x + 95, p.y - 40, { steps: 10 }); await dp.mouse.up();
    s = await ds(); assert.ok(s.position.x > 70); assert.equal(s.modal, 'none');
    p = center(s.card); await dp.mouse.click(p.x, p.y, { button: 'right' });
    assert.equal((await ds()).modal, 'menu'); await clickAction('MenuDetails'); assert.equal((await ds()).modal, 'detail'); await clickAction('Close');
    await dp.mouse.move(700, 450); await dp.mouse.wheel(0, -150); await dp.waitForTimeout(100); assert.ok((await ds()).zoom > 1);
    await clickAction('Reset');
    s = await ds(); const empty = { x: s.viewport.x + 220, y: s.viewport.y + s.viewport.height / 2 };
    await dp.mouse.move(empty.x, empty.y); await dp.mouse.down(); await dp.mouse.move(empty.x + 45, empty.y + 25, { steps: 6 }); await dp.mouse.up();
    assert.ok((await ds()).pan.x > 20); await clickAction('Reset');
    await dp.setViewportSize({ width: 1100, height: 760 });
    await dp.waitForTimeout(200); s = await ds(); assert.equal(s.wide, true); assert.ok(closeTo(s.position.x, 0));
    p = center(s.card); await dp.mouse.click(p.x, p.y); assert.equal((await ds()).modal, 'detail');
    await dp.screenshot({ path: path.join(root, 'review/desktop.png') });
    results.push('1440×900 → 1100×760 mouse: drag, context menu, wheel, pan, reset, resize and side panel');
    await desktop.ctx.close();
    assert.deepEqual(errors, [], 'Unexpected browser errors');
    fs.writeFileSync(path.join(root, 'review/verification.json'), JSON.stringify({ passed: true, results, errors, engineWarnings }, null, 2));
    console.log(JSON.stringify({ passed: true, results, errors, engineWarnings }, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
