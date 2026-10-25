const { chromium } = require('playwright'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '..');
const sample = `window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c => c.model && c.syncViews)`;
(async () => {
 const browser = await chromium.launch({ channel: 'chrome', headless: true }), checks = [], errors = [];
 try {
  for (const scenario of [
   { name: 'landscape', width: 1280, height: 800, zoom: .42, reload: false },
   { name: 'portrait', width: 390, height: 844, zoom: .58, reload: false },
   { name: 'reload', width: 1280, height: 800, zoom: .51, reload: true },
  ].filter(scenario => !process.argv.includes('--no-reload') || !scenario.reload)) {
   const context = await browser.newContext({ viewport: { width: scenario.width, height: scenario.height } }), page = await context.newPage();
   page.on('pageerror', e => errors.push(e.message));
   const state = () => page.evaluate(() => window.__STARTX_SAMPLE__());
   const click = b => page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
   const camera = () => page.evaluate(`(() => { const s = ${sample}, b = s.board, p = b.node.position; return { zoom: b.zoom / s.inputScale, pitch: b.pitch, centerX: -p.x / b.zoom, centerY: -p.y / (b.zoom * b.pitch), moving: b.moving }; })()`);
   await page.goto('http://127.0.0.1:4173/?review=1'); await page.waitForLoadState('networkidle'); await page.waitForFunction(() => window.__STARTX_SAMPLE__?.().ready);
   await click((await state()).controls['Title:Restart']);
   const before = await page.evaluate(`(() => { const s = ${sample}, m = s.model; m.packs = []; m.cards.find(c => c.id === 'p3_account').stored = ${scenario.name === 'landscape' ? 3 : 4};
    ${scenario.name === 'landscape' ? "m.spawn('cash', -100, -200);" : ''}
    m.spawn('p1_office', -350, 80); m.spawn('p2_sales_specialist', 480, -130); s.syncViews();
    s.restoreBoard({ zoom: ${scenario.zoom}, pitch: 1, centerX: 130, centerY: -95 }); s.saveProgress(); return JSON.parse(localStorage.getItem('startx.progress.v1')).view; })()`);
   await page.waitForFunction(() => window.__STARTX_SAMPLE__().ready && window.__STARTX_SAMPLE__().motions.every(m => !m.kind));
   await page.keyboard.type('uu', { delay: 60 }); await page.waitForFunction(() => window.__STARTX_SAMPLE__().monthEnd.visible);
   await page.evaluate(() => {
    window.__cashShrinkSamples = [];
    const collect = () => {
     const state = window.__STARTX_SAMPLE__();
     for (const flight of state.cashFlights) window.__cashShrinkSamples.push({
      source: flight.uid === undefined ? 'account' : 'loose', time: flight.time - flight.delay,
      scale: flight.scale, offset: flight.offset, from: flight.from,
      target: state.cards.find(c => c.uid === flight.targetUid).position,
     });
     if (state.monthSettlement?.phase !== 'ready') requestAnimationFrame(collect);
    };
    requestAnimationFrame(collect);
   });
   await click((await state()).monthEnd.buttonBounds);
   await page.waitForFunction(() => window.__STARTX_SAMPLE__().cashFlights.length > 0);
   let s = await state(), view = await camera(), first = s.cashFlights[0].targetUid;
   assert(Math.abs(view.zoom - 180 / 280) < .0001, scenario.name + ': fixed zoom'); assert(view.zoom > before.zoom);
   const verifyTarget = state => {
    const target = state.cards.find(c => c.uid === state.cashFlights[0].targetUid).faceBounds;
    assert(Math.abs(target.width - 180) < 8, scenario.name + ': fixed on-screen card size ' + target.width);
    assert(Math.abs(target.x + target.width / 2 - scenario.width / 2) < 4);
    assert(Math.abs(target.y + target.height / 2 - scenario.height / 2) < 12);
   };
   verifyTarget(s);
   assert.deepEqual(await page.evaluate(() => JSON.parse(localStorage.getItem('startx.progress.v1')).view), before, 'Original camera persisted during payment');
   if (scenario.reload) {
    await page.reload(); await page.waitForFunction(() => window.__STARTX_SAMPLE__?.().ready);
    await click((await state()).controls['Title:Continue']);
   }
   await page.waitForFunction(first => window.__STARTX_SAMPLE__().cashFlights.some(f => f.targetUid !== first), first);
   s = await state(); verifyTarget(s); assert(Math.abs((await camera()).zoom - view.zoom) < .0001, 'Both recipients use the same zoom');
   if (scenario.name === 'landscape') await page.screenshot({ path: path.join(root, 'review/screenshots/month-payment-closeup.png') });
   await page.waitForFunction(() => { const s = window.__STARTX_SAMPLE__(); return s.monthSettlement?.phase === 'ready' && s.monthEnd.visible; });
   if (!scenario.reload) {
    const samples = await page.evaluate(() => window.__cashShrinkSamples);
    for (const source of scenario.name === 'landscape' ? ['loose', 'account'] : ['account']) {
     const sourceSamples = samples.filter(s => s.source === source);
     assert(sourceSamples.some(s => s.time > .1 && s.time < .35 && Math.abs(s.scale - 1) < .001), source + ': full size in flight');
     const arrived = sourceSamples.filter(s => s.time > .43 && s.time < .7);
     assert(arrived.some(s => s.scale < .3), source + ': visibly shrinks at target');
     for (const s of arrived) {
      assert(s.scale < 1 && s.scale >= 0);
      assert(Math.hypot(s.from.x + s.offset.x - s.target.x, s.from.y + s.offset.y - s.target.y) < .001, source + ': shrink centered at target');
     }
    }
    assert.equal((await state()).cashFlights.length, 0, 'Consumed cash removed');
   }
   view = await camera(); assert(!view.moving);
   for (const key of ['zoom', 'pitch', 'centerX', 'centerY']) assert(Math.abs(view[key] - before[key]) < .0001, `${scenario.name}: restored ${key}`);
   s = await state(); assert.equal(s.cash, 0); assert.equal(s.month, 1);
   if (scenario.name === 'landscape') await page.screenshot({ path: path.join(root, 'review/screenshots/month-camera-restored.png') });
   await click(s.monthEnd.buttonBounds); assert.equal((await state()).month, 2);
   checks.push({ scenario: scenario.name, paymentCardPixels: 180, restored: before, passed: true }); await context.close();
  }
  assert.deepEqual(errors, []); const report = { passed: true, checks, errors }; fs.writeFileSync(path.join(root, 'review/month-camera-verification.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report, null, 2));
 } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
