const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json'))),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],checks=[];
 try{
  for(const mobile of [false,true]){
   const name=mobile?'portrait':'desktop',viewport=mobile?{width:390,height:844}:{width:1440,height:900};
   const ctx=await browser.newContext({viewport,hasTouch:mobile,isMobile:mobile,deviceScaleFactor:mobile?2:1}),page=await ctx.newPage();
   page.on('pageerror',e=>errors.push(e.message));page.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});
   await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready);
   const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
   const click=async p=>mobile?page.touchscreen.tap(p.x,p.y):page.mouse.click(p.x,p.y);
   const action=async key=>{const r=(await state()).controls[key];assert(r,'Missing '+key);await click(center(r));};
   const settle=async()=>page.waitForFunction(()=>window.__STARTX_SAMPLE__().drawerProgress===1);
   const text=s=>s.taskText.map(t=>t.replace(/\n/g,''));
   const helpInside=s=>{assert(s.help);assert(s.help.x>=s.drawer.x-.1);assert(s.help.x+s.help.width<=s.drawer.x+s.drawer.width+.1);assert(s.help.width<=viewport.width/3+.1);};
   let s=await state();assert(s.controls.Book.y+s.controls.Book.height>s.controls.Tasks.y,'Tabs should overlap slightly');
   await action('Book');await settle();s=await state();
   for(const heading of ['阶段「车库」','阶段「验证」','阶段「产品」'])assert(text(s).includes(heading));
   for(const total of [9,12,1])assert(text(s).includes('已解锁 商业模式：0/'+total));
   assert.equal(s.taskText.filter(t=>t==='• ？？').length,22);assert(s.drawer.width<=viewport.width/3+.1);
   await page.screenshot({path:path.join(root,'review/notebook-'+name+'-recipes.png')});
   await action('Tasks');s=await state();assert(text(s).includes('主任务 1/9'));assert(text(s).includes('支线任务 0/23'));assert(text(s).includes('☑ 创业啦'));
   for(const group of new Set(data.tasks.map(t=>t.group)))assert(text(s).some(t=>t==='▾ '+group),group);
   const original=data.tasks.find(t=>t.id==='main_start').content;
   if(mobile)await action('TaskItem:main_start');else{const r=s.controls['TaskItem:main_start'];await page.mouse.move(r.x+r.width/2,r.y+r.height/2);}
   await page.waitForFunction(t=>window.__STARTX_SAMPLE__().helpText===t,original);s=await state();helpInside(s);
   await page.screenshot({path:path.join(root,'review/notebook-'+name+'-task-description.png')});
   if(mobile)await click(center(s.help));else{await page.mouse.move(viewport.width-150,450);await page.waitForFunction(()=>!window.__STARTX_SAMPLE__().helpText);}
   await action('TaskFold:主任务/创业啦');await page.waitForFunction(()=>!window.__STARTX_SAMPLE__().taskText.includes('☐ 打开车库创业包'));await action('TaskFold:主任务/创业啦');
   assert(!s.controls.TaskClose,'Drawer has no close button');
   const taskHeight=s.controls['TaskItem:main_start'].height;
   await action('Book');await settle();s=await state();
   assert(s.taskText.includes('• ？？'));await action('Tasks');await settle();
   assert(taskHeight<44,'Compact notebook task rows');
   await action('Tasks');await page.waitForFunction(()=>window.__STARTX_SAMPLE__().drawerProgress===0);
   if(!mobile){
    for(let i=0;i<4;i++){
     await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);s=await state();await click(center(s.packs[0].bounds));
     if(i===0){
      await page.waitForFunction(()=>window.__STARTX_SAMPLE__().motions.some(m=>m.kind==='fly'&&m.scale<1));
      await page.screenshot({path:path.join(root,'review/notebook-pack-flight.png')});
     }
     if(i===1){
      await page.waitForFunction(()=>window.__STARTX_SAMPLE__().motions.filter(m=>m.kind==='cash').length===5);
      const cash=(await state()).motions.filter(m=>m.kind==='cash');assert.deepEqual(cash.map(m=>m.delay),[0,.075,.15,.22499999999999998,.3]);
     }
     if(i===3)await page.waitForFunction(()=>window.__STARTX_SAMPLE__().departures.length===1);
    }
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready);s=await state();const founder=center(s.cards.find(c=>c.id==='founder').bounds),resource=center(s.cards.find(c=>c.id==='p1_neighborhood').bounds);
    await page.mouse.move(founder.x,founder.y);await page.mouse.down();await page.mouse.move(resource.x,resource.y,{steps:14});await page.mouse.up();
    await action('Book');await settle();
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().taskText.some(t=>t.replace(/\n/g,'')==='已解锁 商业模式：1/9'),null,{timeout:12000});
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().motions.some(m=>m.kind==='pop'&&m.scale<1));
    s=await state();const recipe=data.recipes.find(r=>r.id==='p1_recruit_youth');assert(text(s).includes('• '+recipe.name));assert.equal(s.taskText.filter(t=>t==='• ？？').length,21);
    const r=s.controls['TaskItem:recipe-'+recipe.id];await page.mouse.move(r.x+r.width/2,r.y+r.height/2);await page.waitForFunction(t=>window.__STARTX_SAMPLE__().helpText===t,recipe.formula);
    s=await state();helpInside(s);await page.screenshot({path:path.join(root,'review/notebook-desktop-recipes.png')});
    await action('Tasks');s=await state();assert(text(s).includes('☑ 打开车库创业包'));assert(text(s).includes('☑ 初次找客户'));
    await page.screenshot({path:path.join(root,'review/notebook-desktop-tasks.png')});
    checks.push('Desktop: compact notebook rows, no close button, original groups/status/descriptions, pack flight and staggered cash, empty pack dissolve, production pop and live recipe discovery');
   }else{
    await action('Tasks');await settle();await page.screenshot({path:path.join(root,'review/notebook-portrait-tasks.png')});
    checks.push('Portrait touch: overlap switching, Godot groups/counts/status and tap descriptions constrained within one third width');
   }
   await ctx.close();
  }
  assert.deepEqual(errors,[]);const report={passed:true,checks,errors};fs.writeFileSync(path.join(root,'review/notebook-ui-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
