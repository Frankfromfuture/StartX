// Focused camera regression after multi-card overview/reset replaced single-card reset.
const {chromium}=require('playwright'), assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
 const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
 page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
  const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
  const action=async key=>{const r=(await state()).controls[key],p=center(r);await page.mouse.click(p.x,p.y);};
  let s=await state(),start=s.position;const initialPan=s.pan;
  for(let i=0;i<4;i++){await page.mouse.move(160,380);await page.mouse.down();await page.mouse.move(660,400,{steps:5});await page.mouse.up();}
  s=await state();assert(Math.abs(s.pan.x-initialPan.x-2000)<2);assert.deepEqual(s.position,start);
  const zoomBefore=(await state()).zoom;await page.mouse.wheel(0,-150);await page.waitForTimeout(100);assert((await state()).zoom>zoomBefore);
  const before=await state();await page.setViewportSize({width:1100,height:760});await page.waitForTimeout(150);s=await state();assert.deepEqual(s.pan,before.pan);
  await action('Settings');await action('Row:Reset');let p;s=await state();assert.deepEqual(s.position,start);assert(s.card.x>=0&&s.card.x+s.card.width<=1100);
  await action('Settings');await action('Row:Details');await page.waitForTimeout(250);assert.equal((await state()).modal,'detail');
  await page.screenshot({path:path.join(root,'review/desktop-detail.png')});
  p=center((await state()).controls.Close);await page.mouse.click(p.x,p.y);
  await page.screenshot({path:path.join(root,'review/opening-desktop.png')});
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(150);s=await state();p=center(s.controls['TopPack:Developemnt_pack']);await page.mouse.click(p.x,p.y);await page.waitForTimeout(150);
  await page.screenshot({path:path.join(root,'review/portrait-packs.png')});
  assert((await state()).hint.includes('完成 8 项任务'));assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(root,'review/infinite-canvas.json'),JSON.stringify({passed:true,results:['Pan beyond former boundaries; zoom and resize preserve world positions; overview reset returns cards to view','Corrected dynamic labels: desktop detail and portrait pack list screenshots'],errors},null,2));
  console.log('PASS: camera regression and corrected detail/pack-list screenshots');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
