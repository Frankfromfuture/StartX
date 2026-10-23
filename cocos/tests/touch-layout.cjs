// Focused touch regression for the Cocos HUD. Desktop was checked against the reference.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],checks=[];
 const ctx=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:2,isMobile:true,hasTouch:true}),page=await ctx.newPage();
 const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
 page.on('pageerror',e=>errors.push(e.message));
 page.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});
 try{
  await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
  const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
  const tap=async key=>{const r=(await state()).controls[key];assert(r,key);const p=center(r);await page.touchscreen.tap(p.x,p.y);};
  let s=await state();
  for(const key of ['Book','Tasks','ViewFront','ViewBack','ZoomIn','ZoomOut','Settings','ResearchPanel','SellZone']){const r=s.controls[key];assert(r.width>=43.99&&r.height>=43.99,key);}
  assert(s.controls.Tasks.y>650);assert(s.controls.ZoomOut.x>300);assert(s.controls.ViewFront.y<s.controls.ZoomIn.y);assert(s.controls.ResearchPanel.y<200);
  checks.push('Original folder tabs, right vertical view/zoom controls, research/cart and gear; all targets at least 44 CSS px');
  await tap('Tasks');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskDrawer);s=await state();assert.equal(s.drawerMode,'tasks');
  await tap('TaskFold:主任务/创业啦');await page.waitForFunction(()=>!window.__STARTX_SAMPLE__().taskText.includes('☐ 打开车库创业包'));
  await page.screenshot({path:path.join(root,'review/touch-layout-portrait-tasks.png')});await tap('TaskClose');
  await tap('Book');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskDrawer&&window.__STARTX_SAMPLE__().drawerMode==='recipes');await tap('TaskClose');
  checks.push('Touch opens task/business notebooks and folds original task groups');
  const zoom=(await state()).zoom;await tap('ZoomIn');await page.waitForFunction(z=>window.__STARTX_SAMPLE__().zoom>z,zoom);await tap('ZoomOut');
  await tap('ViewFront');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().pitch<1);await tap('ViewBack');
  await tap('ResearchPanel');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().modal==='research');await tap('Close');
  await tap('Settings');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().modal==='book');await tap('Close');
  checks.push('Touch controls change view/zoom and open research/options');
  s=await state();let p=center(s.card);await page.touchscreen.tap(p.x,p.y);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().hint.includes('创始人 · 员工'));
  await page.touchscreen.tap(15,500);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().hint.includes('公司的地板光亮如新'));
  await page.screenshot({path:path.join(root,'review/touch-layout-portrait.png')});
  checks.push('Card and board taps show original text in the dark bottom strip');
  s=await state();p=center(s.packs[0].bounds);await page.touchscreen.tap(p.x,p.y);
  await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskReminder==='完成 打开车库创业包 啦！');
  assert((await state()).tasks.includes('main_open_garage'));
  await page.screenshot({path:path.join(root,'review/touch-layout-portrait-reminder.png')});
  checks.push('Opening the original pack updates task progress and shows completion text');
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'review/touch-layout-touch.json'),JSON.stringify({passed:true,checks,errors},null,2));console.log(JSON.stringify({passed:true,checks,errors},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
