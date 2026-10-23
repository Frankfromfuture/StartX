const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),results=[],errors=[];
 try{
  for(const mobile of [false,true]){
   const name=mobile?'portrait':'desktop',viewport=mobile?{width:390,height:844}:{width:1440,height:900};
   const ctx=await browser.newContext({viewport,deviceScaleFactor:mobile?2:1,isMobile:mobile,hasTouch:mobile}),page=await ctx.newPage();
   page.on('pageerror',e=>errors.push(e.message));page.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});
   await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
   const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
   const action=async key=>{const r=(await state()).controls[key];assert(r,key);const p=center(r);if(mobile)await page.touchscreen.tap(p.x,p.y);else await page.mouse.click(p.x,p.y);};
   const settled=async open=>page.waitForFunction(v=>window.__STARTX_SAMPLE__().drawerProgress===v,open?1:0);
   const plane=s=>{for(const axis of ['x','y'])for(const component of ['x','y'])assert(Math.abs(s.gridPlane[axis][component]-s.cardPlane[axis][component])<.01,'Grid/card '+axis+component);};
   const cdp=mobile?await ctx.newCDPSession(page):null;
   const drag=async(p,q)=>{
    if(mobile){await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...p,id:1}]});for(let i=1;i<=12;i++)await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:p.x+(q.x-p.x)*i/12,y:p.y+(q.y-p.y)*i/12,id:1}]});await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});}
    else{await page.mouse.move(p.x,p.y);await page.mouse.down();await page.mouse.move(q.x,q.y,{steps:12});await page.mouse.up();}
   };
   let s=await state();const originalPosition=s.position,originalPan=s.pan;
   for(const key of ['Book','Tasks']){const r=s.controls[key];assert(r.height>r.width*2);assert(r.width>=43.99);assert(Math.abs(r.x)<1);}
   await page.screenshot({path:path.join(root,'review/file-tabs-'+name+'-closed.png')});
   await action('Book');await settled(true);s=await state();assert.equal(s.drawerMode,'recipes');assert(s.drawer.width<=viewport.width/3+.01);assert(Math.abs(s.drawer.x)<1);assert(Math.abs(s.controls.Book.x-s.drawer.width)<1);
   assert.deepEqual(s.position,originalPosition);assert.deepEqual(s.pan,originalPan);
   await action('Tasks');await settled(true);s=await state();assert.equal(s.drawerMode,'tasks');assert(s.drawer.width<=viewport.width/3+.01);assert(s.taskText.includes('公司任务'));
   await page.screenshot({path:path.join(root,'review/file-tabs-'+name+'.png')});
   await action('TaskFold:主任务/创业啦');await page.waitForFunction(()=>!window.__STARTX_SAMPLE__().taskText.includes('☐ 打开车库创业包'));await action('TaskFold:主任务/创业啦');
   s=await state();const group=center(s.controls['TaskFold:主任务/创业啦']);
   if(mobile)await drag({x:group.x,y:group.y+140},{x:group.x,y:group.y+30});
   else{await page.mouse.move(group.x,group.y+100);await page.mouse.wheel(0,320);}
   await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskOffset>0);assert.deepEqual((await state()).pan,originalPan);
   await action('Tasks');await settled(false);assert(!(await state()).taskDrawer);
   for(let i=0;i<3;i++)await action('ViewFront');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().pitch<.9);
   s=await state();plane(s);assert(Math.abs(s.card.height/s.card.width-s.pitch)<.002);
   const beforeZoom=s.zoom;await action('ZoomIn');await page.waitForFunction(z=>window.__STARTX_SAMPLE__().zoom>z,beforeZoom);s=await state();plane(s);
   if(mobile){
    await drag({x:240,y:650},{x:260,y:700});await page.waitForFunction(p=>window.__STARTX_SAMPLE__().pan.y!==p,originalPan.y);
    s=await state();plane(s);assert.deepEqual(s.position,originalPosition);
    const p=center(s.card),q={x:p.x+30,y:p.y+40},expected={x:s.position.x+30/(s.card.width/280),y:s.position.y-40/(s.card.height/280)};
    await drag(p,q);await page.waitForFunction(p=>Math.abs(window.__STARTX_SAMPLE__().position.y-p)>1,originalPosition.y);
    s=await state();assert(Math.abs(s.position.x-expected.x)<2);assert(Math.abs(s.position.y-expected.y)<2);plane(s);
   }else{
    const before=s.pan;for(let i=0;i<4;i++)await drag({x:380,y:710},{x:1080,y:740});
    s=await state();assert(Math.abs(s.pan.x-before.x-2800)<2);assert.deepEqual(s.position,originalPosition);plane(s);
    await page.screenshot({path:path.join(root,'review/file-tabs-desktop-infinite.png')});
   }
   results.push({viewport,mobile,drawerWidth:mobile?viewport.width/3:440*viewport.width/1920,checks:['Vertical file tabs, left slide-out, switch/retract, maximum one third width','Task group folding and scrolling stay inside the drawer','Shared card/grid plane at tilted view, after zoom and pan',mobile?'Touch picking and dropping at the same tilted angle':'Infinite canvas pan of 2800 pixels preserves card world positions']});
   await ctx.close();
  }
  assert.deepEqual(errors,[]);const report={passed:true,results,errors};fs.writeFileSync(path.join(root,'review/file-tabs-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
