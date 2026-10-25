const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const out = path.resolve(__dirname, '../review');
const center = b => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
(async () => {
 const browser = await chromium.launch({ channel: 'chrome', headless: true });
 const errors = [], checks = [];
 try {
  for (const failure of [false, true]) {
   const viewport = failure ? { width: 390, height: 844 } : { width: 1280, height: 800 };
   const context = await browser.newContext({ viewport });
   const page = await context.newPage(); page.on('pageerror', e => errors.push(e.message));
   const state = () => page.evaluate(() => window.__STARTX_SAMPLE__());
   const click = async b => { const p = center(b); await page.mouse.click(p.x, p.y); };
   await page.goto('http://127.0.0.1:4173/?review=1'); await page.waitForLoadState('networkidle');
   await page.waitForFunction(() => window.__STARTX_SAMPLE__?.().ready);
   let s = await state(); await click(s.controls['Title:Restart']);
   const setup = await page.evaluate(failure => {
    const sample = window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c => c.model && c.syncViews), m = sample.model;
    m.packs = []; const account = m.cards.find(c => c.id === 'p3_account'); account.stored = failure ? 1 : 3;
    const office = m.spawn('p1_office', -400, 100), employee = m.spawn('p2_sales_specialist', 450, -100);
    if (!failure) m.spawn('cash', -100, -250);
    sample.syncViews(); return { office: office.uid, employee: employee.uid, account: account.uid, cash: m.cash, payroll: m.payroll };
   }, failure);
   await page.waitForFunction(() => window.__STARTX_SAMPLE__().ready && window.__STARTX_SAMPLE__().motions.every(m => !m.kind));
   if (failure) await page.evaluate(() => {
    const c = window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c => c.model && c.syncViews); c.model.monthTime = .01;
   });
   else { await page.keyboard.type('uu', { delay: 60 }); }
   await page.waitForFunction(() => window.__STARTX_SAMPLE__().monthSettlement?.phase === 'confirm').catch(async e => { console.log(await page.evaluate(() => { const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews); return { title:c.atTitle, modal:c.modal, key:c.lastMonthKey, time:c.model.monthTime, phase:c.model.monthSettlement, errors:c.lastError }; }), errors); await page.screenshot({path:'/tmp/startx-month-failure.png'}); throw e; });
   s = await state(); assert.equal(s.monthEnd.title, '第 1 月结束'); assert.equal(s.monthEnd.button, '发工资及付租金'); assert.equal(s.cash, setup.cash);
   const box = center(s.monthEnd.panelBounds); assert(Math.abs(box.x - viewport.width / 2) < 2 && Math.abs(box.y - viewport.height / 2) < 2);
   await page.mouse.click(viewport.width - 15, viewport.height / 2); assert.equal((await state()).monthSettlement.phase, 'confirm');
   await page.screenshot({ path: path.join(out, 'screenshots/month-end-' + (failure ? 'portrait' : 'landscape') + '.png') });
   await click(s.monthEnd.buttonBounds);
   if (failure) {
    await page.waitForFunction(() => window.__STARTX_SAMPLE__().monthSettlement?.phase === 'failed');
    s = await state(); assert(s.gameOver); assert.equal(s.cash, setup.cash); assert.equal(s.cashFlights.length, 0);
    assert.equal(s.monthEnd.title, 'Game Over'); assert.equal(s.monthEnd.message, '创业失败，加油再来！');
    await page.screenshot({ path: path.join(out, 'screenshots/month-end-failure.png') });
    await click(s.monthEnd.buttonBounds);
    assert.equal(await page.evaluate(() => localStorage.getItem('startx.progress.v1')), null);
    assert((await state()).titleScreen.active); checks.push('Portrait: natural month expiry, failure with no partial deduction, confirmation returns to title and removes failed save');
   } else {
    await page.waitForFunction(() => window.__STARTX_SAMPLE__().cashFlights.length > 0);
    s = await state(); assert.equal(s.month, 1); assert.equal(s.cash, 2); assert.equal(s.monthEnd.visible, false);
    assert(s.cashFlights.every(f => f.targetUid === setup.office)); assert(s.cashFlights.some(f => f.uid !== undefined)); assert(s.cashFlights.some(f => f.uid === undefined));
    const office = center(s.cards.find(c => c.uid === setup.office).faceBounds);
    assert(Math.abs(office.x - viewport.width / 2) < 4 && Math.abs(office.y - viewport.height / 2) < 12, JSON.stringify(office));
    await page.screenshot({ path: path.join(out, 'screenshots/month-end-office-payment.png') });
    await page.reload(); await page.waitForFunction(() => window.__STARTX_SAMPLE__?.().ready);
    s = await state(); assert.equal(s.cash, 2); await click(s.controls['Title:Continue']);
    await page.waitForFunction(uid => window.__STARTX_SAMPLE__().cashFlights.some(f => f.targetUid === uid), setup.employee);
    s = await state(); assert(s.cashFlights.every(f => f.targetUid === setup.employee)); assert.equal(s.cash, 0);
    const employee = center(s.cards.find(c => c.uid === setup.employee).faceBounds);
    assert(Math.abs(employee.x - viewport.width / 2) < 4 && Math.abs(employee.y - viewport.height / 2) < 12, JSON.stringify(employee));
    await page.waitForFunction(() => window.__STARTX_SAMPLE__().monthSettlement?.phase === 'ready' && window.__STARTX_SAMPLE__().monthEnd.visible);
    s = await state(); assert.equal(s.month, 1); assert.equal(s.monthEnd.title, '开始第 2 月'); assert.equal(s.cashFlights.length, 0);
    await page.screenshot({ path: path.join(out, 'screenshots/month-end-ready.png') });
    await click(s.monthEnd.buttonBounds); s = await state(); assert.equal(s.month, 2); assert.equal(s.monthSettlement, null); assert(s.monthTime > 170);
    checks.push('Landscape: uu confirmation, centered crayon panel, cash/account flights to centered office then employee, reload during payment without double debit, explicit next-month confirmation');
   }
   await context.close();
  }
  assert.deepEqual(errors, []); const report = { passed: true, checks, errors }; fs.writeFileSync(path.join(out, 'month-end-verification.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report, null, 2));
 } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
