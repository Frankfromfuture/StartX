const {chromium}=require('playwright'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],results=[];
 try{
  for(const mobile of process.env.HUD_VIEW === 'portrait' ? [true] : [false,true]){
   const name=mobile?'portrait':'desktop',viewport=mobile?{width:390,height:844}:{width:1440,height:900};
   const ctx=await browser.newContext({viewport,hasTouch:mobile,isMobile:mobile,deviceScaleFactor:mobile?2:1}),page=await ctx.newPage();
   page.on('pageerror',e=>errors.push(e.message));page.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});
   await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
   const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
   const click=async p=>{if(mobile)await page.touchscreen.tap(p.x,p.y);else await page.mouse.click(p.x,p.y);await page.waitForTimeout(120);};
   const action=async key=>{const r=(await state()).controls[key];assert(r,'Missing control '+key);await click(center(r));};
   const drag=async(p,q)=>{
    if(mobile){const cdp=await ctx.newCDPSession(page);await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...p,id:1}]});
     for(let i=1;i<=10;i++)await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:p.x+(q.x-p.x)*i/10,y:p.y+(q.y-p.y)*i/10,id:1}]});
     await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await cdp.detach();
    }else{await page.mouse.move(p.x,p.y);await page.mouse.down();await page.mouse.move(q.x,q.y,{steps:10});await page.mouse.up();}
    await page.waitForTimeout(120);
   };
   let s=await state();assert(s.hint.includes('公司的地板光亮如新'));assert(s.taskReminder==='完成 创业啦 啦！');
   assert(!s.controls.Pack);assert(s.controls.Tasks.y>viewport.height*.7);assert(s.controls['TopPack:garage_pack'].y<viewport.height*.3);
   for(const key of ['Tasks','Book','Details','ZoomOut','ZoomIn','Reset','TopPack:garage_pack']){assert(s.controls[key].width>=44,key);assert(s.controls[key].height>=44,key);}
   await click(center(s.card));s=await state();assert.equal(s.modal,'none');assert.equal(s.hint,'「创始人 · 员工　月薪 $0　产能 5」');
   await action('Details');assert.equal((await state()).modal,'detail');await action('Close');
   await click({x:20,y:viewport.height*.54});assert((await state()).hint.includes('公司的地板光亮如新'));
   await action('Tasks');s=await state();assert(s.taskDrawer);assert(s.taskText.some(t=>t.startsWith('主任务 ')));assert(s.taskText.some(t=>t.startsWith('支线任务 ')));
   await action('TaskFold:主任务/创业啦');assert(!(await state()).taskText.includes('☐ 打开车库创业包'));await action('TaskFold:主任务/创业啦');
   await page.screenshot({path:path.join(root,'review',name+'-tasks.png')});
   if(mobile){const p=center((await state()).controls['TaskFold:主任务/创业啦']);await drag({x:p.x,y:p.y+170},{x:p.x,y:p.y+20});}
   else{const p=center((await state()).controls['TaskFold:主任务/创业啦']);await page.mouse.move(p.x,p.y+100);await page.mouse.wheel(0,450);await page.waitForTimeout(150);}
   assert((await state()).taskOffset>0,'Task list scroll');await action('TaskClose');assert(!(await state()).taskDrawer);
   if(mobile){s=await state();const p=center(s.controls['TopPack:garage_pack']);await drag({x:viewport.width-40,y:p.y},{x:60,y:p.y});s=await state();assert(s.packOffset<0);assert.equal(s.packs.length,1,'Shelf swipe must not buy');}
   s=await state();await click(center(s.packs[0].bounds));
   await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskReminder==='完成 打开车库创业包 啦！',null,{timeout:8000});
   s=await state();assert(s.tasks.includes('main_open_garage'));assert(s.controls.Tasks);assert.equal(s.cards.length,2);
   await page.screenshot({path:path.join(root,'review',name+'-task-reminder.png')});
   for(let i=0;i<3;i++){await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);s=await state();await click(center(s.packs[0].bounds));}
   await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);s=await state();assert.equal(s.cash,5);assert.equal(s.cards.length,9);
   if(!mobile){await action('TopPack:garage_pack');s=await state();assert.equal(s.cash,2);assert.equal(s.packs.length,1);await action('Reset');
    s=await state();const p=center(s.cards.find(c=>c.id==='founder').bounds),q=center(s.cards.find(c=>c.id==='p1_neighborhood').bounds);await drag(p,q);
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p1_youth'),null,{timeout:10000});
   }else{const before=s.zoom;await action('ZoomIn');assert((await state()).zoom>before);await action('Reset');}
   await page.screenshot({path:path.join(root,'review',name+'.png')});
   results.push(name+': original pack covers, task groups/folding/scroll, task completion reminder, card/floor hints, '+(mobile?'touch shelf swipe and zoom':'pack purchase and production regression'));
   await ctx.close();
  }
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(root,'review/original-hud-verification.json'),JSON.stringify({passed:true,results,errors},null,2));console.log(JSON.stringify({passed:true,results,errors},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
