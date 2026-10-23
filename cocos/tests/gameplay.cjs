const { chromium } = require('playwright');
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..'), center = r => ({ x:r.x+r.width/2, y:r.y+r.height/2 });
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],warnings=[],results=[];
 const create=async options=>{
  const ctx=await browser.newContext(options),page=await ctx.newPage();
  page.on('pageerror',e=>errors.push(e.message)); page.on('console',e=>{if(e.type()==='error'){if(/^Ignored attempt to cancel a touch(start|cancel) event with cancelable=false/.test(e.text()))warnings.push(e.text());else errors.push(e.text());}});
  await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready,null,{timeout:30000});
  const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
  const ready=async()=>{await page.waitForTimeout(150);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);};
  const action=async name=>{if(['Details','Reset'].includes(name)){await action('Settings');await action('Row:'+name);return;}if(name==='Book')name='Settings';const s=await state();assert(s.controls[name],'Missing '+name);const p=center(s.controls[name]);await page.mouse.click(p.x,p.y);await ready();};
  const drag=async(uid,target)=>{const s=await state(),p=center(s.cards.find(c=>c.uid===uid).bounds),q=typeof target==='number'?center(s.cards.find(c=>c.uid===target).bounds):target;await page.mouse.move(p.x,p.y);await page.mouse.down();await page.mouse.move(q.x,q.y,{steps:14});await page.mouse.up();await ready();};
  return{ctx,page,state,ready,action,drag};
 };
 try{
  const d=await create({viewport:{width:1440,height:900},deviceScaleFactor:1}),{page,state,action,drag,ready}=d;
  let s=await state();assert.equal(s.cards.length,1);assert.equal(s.packs.length,1);assert.equal(s.cash,0);assert.equal(s.error,'');
  fs.writeFileSync(path.join(root,'review/opening-state.json'),JSON.stringify(s,null,2));await page.screenshot({path:path.join(root,'review/opening-desktop.png')});
  let p=center(s.card);await page.mouse.click(p.x,p.y);await ready();s=await state();assert.equal(s.modal,'none');await action('Details');s=await state();assert(s.panelText.join('\n').includes('不用给钱，啥都能干。'));await action('Back');
  for(let i=0;i<4;i++){s=await state();p=center(s.packs[0].bounds);await page.mouse.click(p.x,p.y);await ready();}
  s=await state();assert.equal(s.packs.length,0);assert.equal(s.cash,5);assert.equal(s.cards.length,9);
  const founder=s.cards.find(c=>c.id==='founder').uid,neighborhood=s.cards.find(c=>c.id==='p1_neighborhood').uid;
  await drag(founder,neighborhood);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p1_youth'),null,{timeout:12000});
  s=await state();assert(s.models.includes('p1_recruit_youth'));assert(s.rp>=12);
  await drag(founder,s.cards.find(c=>c.id==='p1_wholesale').uid);s=await state();await drag(s.cards.filter(c=>c.id==='cash').at(-1).uid,founder);
  await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p1_rawprod'),null,{timeout:12000});
  await action('Reset');s=await state();await drag(s.cards.find(c=>c.id==='p1_rawprod').uid,s.cards.find(c=>c.id==='p1_youth').uid);
  await page.waitForFunction(()=>window.__STARTX_SAMPLE__().models.includes('p1_cash_raw_youth'),null,{timeout:10000});
  s=await state();assert.equal(s.cash,8);await action('TopPack:garage_pack');s=await state();assert.equal(s.cash,5);assert.equal(s.packs.length,1);assert.equal(s.modal,'none');
  await action('Reset');await page.screenshot({path:path.join(root,'review/desktop.png')});
  await action('Book');await action('Row:Open:recipes');assert((await state()).panelText.some(t=>t.includes('居住小区*1')));await action('Close');
  await page.setViewportSize({width:1100,height:760});await ready();s=await state();p=center(s.cards.find(c=>c.id==='founder').bounds);await page.mouse.click(p.x,p.y,{button:'right'});await ready();assert.equal((await state()).modal,'menu');await action('Row:MenuDetails');assert.equal((await state()).modal,'detail');await page.screenshot({path:path.join(root,'review/desktop-detail.png')});
  results.push('Desktop: original opening, four unpack taps, resource production, stack split, product/customer sale, paid pack, recipe book and resized context menu');await d.ctx.close();
  const t=await create({viewport:{width:390,height:844},hasTouch:true,isMobile:true,deviceScaleFactor:2}),tp=t.page,ts=t.state,cdp=await t.ctx.newCDPSession(tp);
  const touch=async(type,points)=>cdp.send('Input.dispatchTouchEvent',{type,touchPoints:points.map((p,id)=>({...p,id,radiusX:4,radiusY:4,force:1}))});
  const tap=async name=>{const q=center((await ts()).controls[name]);await tp.touchscreen.tap(q.x,q.y);await t.ready();};
  s=await ts();for(const[name,r]of Object.entries(s.controls))assert(r.width>=44&&r.height>=44,name+' target size');assert(s.controls.Tasks.x<55);assert(s.controls.ZoomOut.y>700);
  p=center(s.card);await touch('touchStart',[p]);await tp.waitForTimeout(550);await touch('touchEnd',[]);await t.ready();assert.equal((await ts()).modal,'menu');await tap('Row:MenuDetails');assert((await ts()).panelText.join('\n').includes('产能 5/5'));await tap('Back');
  s=await ts();p=center(s.card);const before=s.position;await touch('touchStart',[p]);await touch('touchMove',[{x:p.x-20,y:p.y+60}]);await touch('touchCancel',[]);await t.ready();assert.deepEqual((await ts()).position,before);
  await touch('touchStart',[p]);await touch('touchMove',[{x:p.x-20,y:p.y+60}]);await touch('touchEnd',[]);await t.ready();s=await ts();assert.notEqual(s.position.y,before.y);assert.equal(s.modal,'none');
  await tap('ZoomIn');const zi=(await ts()).zoom;await tap('ZoomOut');assert((await ts()).zoom<zi);
  await touch('touchStart',[{x:105,y:650},{x:270,y:650}]);await touch('touchMove',[{x:80,y:650},{x:295,y:650}]);await touch('touchEnd',[]);await t.ready();assert((await ts()).zoom>zi/1.15);await tap('Reset');
  for(let i=0;i<4;i++){s=await ts();p=center(s.packs[0].bounds);await tp.touchscreen.tap(p.x,p.y);await t.ready();}
  s=await ts();assert.equal(s.cash,5);assert.equal(s.cards.length,9);await tp.screenshot({path:path.join(root,'review/portrait.png')});await tap('Tasks');assert((await ts()).taskDrawer);await tp.screenshot({path:path.join(root,'review/portrait-packs.png')});
  results.push('390×844 touch: 44px controls, long press/details, cancelled and committed drags, pinch, icon zoom/reset, original pack opening and task progress drawer');await t.ctx.close();
  assert.deepEqual(errors,[]);const report={passed:true,results,errors,engineWarnings:warnings};fs.writeFileSync(path.join(root,'review/gameplay-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }catch(e){console.error('Browser errors',errors.slice(0,10));throw e;}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
