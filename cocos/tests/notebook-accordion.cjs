const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),checks=[],errors=[];
 try{
  for(const viewport of [{width:390,height:844},{width:640,height:360}]){
   const context=await browser.newContext({viewport,deviceScaleFactor:1}),page=await context.newPage();
   page.on('pageerror',e=>errors.push(e.message));
   await page.goto('http://127.0.0.1:4173/?review=notebook-accordion');
   await page.waitForFunction(()=>{const c=window.cc?.director.getScene()?.getComponentsInChildren(cc.Component).find(c=>c.model&&c.syncViews);return c?.ready&&!c.pending&&!c.originalHud.pending;});
   await page.evaluate(()=>{window.c=cc.director.getScene().getComponentsInChildren(cc.Component).find(c=>c.model&&c.syncViews);c.perform('Restart');c.founderSpeech.dismiss();});
   const point=async key=>page.evaluate(key=>{const n=key==='Viewport'?c.find('TaskDrawer/Viewport'):c.controls.get(key),cam=c.node.getComponent('cc.Canvas').cameraComponent,canvas=document.getElementById('GameCanvas'),r=canvas.getBoundingClientRect(),p=cam.worldToScreen(n.getComponent('cc.UITransform').convertToWorldSpaceAR(new cc.Vec3()));return{x:r.left+p.x/canvas.width*r.width,y:r.top+(canvas.height-p.y)/canvas.height*r.height};},key);
   const action=async key=>{const p=await point(key);await page.mouse.click(p.x,p.y);};
   const settled=async open=>page.waitForFunction(open=>c.originalHud.reveal===(open?1:0),open);
   const state=()=>page.evaluate(()=>{const h=c.originalHud,d=c.find('TaskDrawer'),t=d.getComponent('cc.UITransform'),s=c.inputScale,palette=d.getComponent('Surface'),rows=h.taskContent.children.filter(n=>n.activeInHierarchy&&!n._destroying);return{mode:h.mode,margins:{left:(d.position.x-t.width/2+c.metrics.width/2)/s,top:(c.metrics.height/2-d.position.y-t.height/2)/s,bottom:(d.position.y-t.height/2+c.metrics.height/2)/s},width:t.width/s,height:t.height/s,color:[palette.fill.r,palette.fill.g,palette.fill.b],crayon:palette.crayon,tabCrayon:['Book','Tasks'].every(k=>c.find('Toolbar/'+k).getComponent('Surface').crayon),rowHeight:h.taskHeight/s,offset:h.taskOffset/s,scrollbar:h.taskScrollbar.active,viewportHeight:h.taskViewport.getComponent('cc.UITransform').height/s,folds:Array.from(h.collapsed),rows:rows.map(n=>({name:n.name,text:n.getComponentInChildren('cc.Label')?.string,fill:n.getComponent('Surface')?[n.getComponent('Surface').fill.r,n.getComponent('Surface').fill.g,n.getComponent('Surface').fill.b]:null})),error:c.lastError,backdrop:c.menuBackdrop.snapshot()};});
   await action('Book');await settled(true);const business=await state();
   for(const gap of Object.values(business.margins))assert(Math.abs(gap-2)<.01,'2px edge gap');
   assert(business.width<=viewport.width/3+.01);assert.deepEqual(business.color,[255,249,229]);assert(business.crayon&&business.tabCrayon);assert.equal(business.backdrop.shadeAlpha,190);
   await action('TaskFold:recipes/0');await page.waitForFunction(()=>c.originalHud.collapsed.has('recipes/0'));const folded=await state();assert(folded.rowHeight<business.rowHeight);await action('TaskFold:recipes/0');
   await page.screenshot({path:path.join(root,'review/screenshots/notebook-accordion-'+viewport.width+'-business.png')});
   await action('Tasks');await settled(true);const milestones=await state();assert.deepEqual(milestones.color,[244,248,233]);assert(milestones.rows.some(r=>r.name==='Section'&&r.fill.join(',')==='173,196,147'));assert(milestones.rows.some(r=>r.name==='Group'&&r.fill.join(',')==='217,230,200'));assert(milestones.rows.some(r=>r.name==='Task'&&r.text==='创业啦'));
   await action('TaskFold:主任务/创业啦');await page.waitForFunction(()=>c.originalHud.collapsed.has('主任务/创业啦'));assert((await state()).rowHeight<milestones.rowHeight);await action('TaskFold:主任务/创业啦');
   if(viewport.width===390){await action('TaskItem:main_start');await page.waitForFunction(()=>!!c.originalHud.helpText);await page.evaluate(()=>c.originalHud.hideInfo());const p=await point('Viewport');await page.mouse.move(p.x,p.y);await page.mouse.wheel(0,400);await page.waitForFunction(()=>c.originalHud.taskOffset>0);assert((await state()).scrollbar);}
   await page.screenshot({path:path.join(root,'review/screenshots/notebook-accordion-'+viewport.width+'-milestones.png')});
   const end=await state();assert.equal(end.error,'');await action('Tasks');await settled(false);assert(!await page.evaluate(()=>c.menuBackdrop.node.activeInHierarchy));
   checks.push({viewport,margins:business.margins,business:{base:business.color,folds:true},milestones:{base:milestones.color,folds:true,scroll:viewport.width===390?end.offset:null},crayon:true,backdropAlpha:190});await context.close();
  }
  assert.deepEqual(errors,[]);const report={passed:true,checks,errors};fs.writeFileSync(path.join(root,'review/notebook-accordion-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
