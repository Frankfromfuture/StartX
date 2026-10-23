const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),center=r=>({x:r.x+r.width/2,y:r.y+r.height/2});
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),errors=[],checks=[];
 try{
  for(const mobile of [false,true]){
   const viewport=mobile?{width:390,height:844}:{width:1440,height:900},name=mobile?'portrait':'desktop';
   const ctx=await browser.newContext({viewport,isMobile:mobile,hasTouch:mobile,deviceScaleFactor:mobile?2:1}),page=await ctx.newPage();
   page.on('pageerror',e=>errors.push(e.message));page.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text());});
   await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForFunction(()=>window.__STARTX_SAMPLE__?.().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
   const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());
   const click=async r=>{const p=center(r);if(mobile)await page.touchscreen.tap(p.x,p.y);else await page.mouse.click(p.x,p.y);};
   let s=await state();const hud=s.hudLayout,track=hud.monthTrack;
   assert(Math.abs(track.x)<.1&&Math.abs(track.y)<.1);assert(Math.abs(track.width-viewport.width)<.1);assert(track.height<=4);
   const rowY=center(hud.stats[0].bounds).y;
   assert(hud.status.height<=42&&hud.footer.height<=38,'Slim header and footer');
   assert(Math.abs(rowY-(track.height+hud.status.height)/2)<.1,'Status content vertically centered below month track');
   for(const stat of hud.stats){assert(Math.abs(center(stat.bounds).y-rowY)<.1);assert(stat.bounds.x>=0&&stat.bounds.x+stat.bounds.width<=viewport.width);if(stat.text)assert(Math.abs(center(stat.text).y-rowY)<.1);}
   for(const text of hud.footerText){assert.equal(text.verticalAlign,1);assert(Math.abs(center(text.bounds).y-center(hud.footer).y)<.1);assert(text.lineHeight<=text.bounds.height);}
   for(const tab of hud.tabs){assert(tab.bounds.width<=34);assert(tab.font<=17);assert(s.controls[tab.name].width>=44);}
   const tabCenter=(center(hud.tabs[0].bounds).y+center(hud.tabs[1].bounds).y)/2;
   assert(Math.abs(tabCenter-viewport.height/2)<.1,'Tabs centered on screen');
   const overlap=hud.tabs[0].bounds.y+hud.tabs[0].bounds.height-hud.tabs[1].bounds.y;
   assert(overlap>hud.tabs[0].bounds.width*.4+3,'Rounded shoulders visibly overlap');
   const gear=hud.stats.find(v=>v.name==='Settings').bounds;
   assert(viewport.width-gear.x-gear.width<(mobile?10:20),'Settings shifted toward right edge');
   for(const pack of hud.packPrices){
    assert.equal(pack.hasBackground,false,'Price has no background');
    assert(/^\$\d+$/.test(pack.price));assert(pack.label.x>=pack.cover.x&&pack.label.y>=pack.cover.y);
    assert(pack.label.x+pack.label.width<=pack.cover.x+pack.cover.width);assert(pack.label.y+pack.label.height<pack.cover.y+pack.cover.height/2);
   }
   await page.screenshot({path:path.join(root,'review/compact-hud-'+name+'.png')});
   await click(s.controls.Tasks);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().drawerProgress===1);s=await state();assert.equal(s.drawerMode,'tasks');
   assert(Math.abs(center(s.drawer).y-viewport.height/2)<.1);assert(s.drawer.width<=viewport.width/3+.1);
   assert(s.hudLayout.tabs.find(t=>t.name==='Tasks').order>s.hudLayout.tabs.find(t=>t.name==='Book').order);
   await click(s.controls.Book);s=await state();assert.equal(s.drawerMode,'recipes');
   assert(s.hudLayout.tabs.find(t=>t.name==='Book').order>s.hudLayout.tabs.find(t=>t.name==='Tasks').order);
   await page.screenshot({path:path.join(root,'review/cash-layout-'+name+'.png')});
   await click(s.controls.Book);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().drawerProgress===0);
   if(!mobile){
    for(let i=0;i<4;i++){s=await state();await click(s.packs[0].bounds);await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));}
    s=await state();assert.equal(s.audio.events.filter(e=>e.type==='started'&&e.name==='cash_down').length,5,'Each cash released from pack plays the same sound');
    const founder=s.cards.find(c=>c.id==='founder'),resource=s.cards.find(c=>c.id==='p1_neighborhood');
    const drag=async(a,b)=>{await page.mouse.move(a.x,a.y);await page.mouse.down();await page.mouse.move(b.x,b.y,{steps:12});await page.mouse.up();};
    // Reverse the usual stacking order: the worker is the base, the resource owns progress.
    await drag(center(resource.bounds),center(founder.bounds));
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().workbars.length===1&&window.__STARTX_SAMPLE__().cards.some(c=>c.elapsed>0));
    s=await state();let bar=s.workbars[0];assert.equal(bar.anchor,founder.uid);assert(s.cards.find(c=>c.uid===resource.uid).elapsed>0);
    const validate=b=>{assert(Math.abs(b.bounds.width/b.card.width-1)<.01);assert(Math.abs(b.bounds.height/b.card.height-36/280)<.01);assert(Math.abs(center(b.bounds).x-center(b.card).x)<2);assert(b.bounds.y+b.bounds.height<b.card.y);};
    validate(bar);const base=s.cards.find(c=>c.uid===founder.uid).bounds;
    const start={x:base.x+base.width/2,y:base.y+base.height*.06},before=s.cards.find(c=>c.uid===resource.uid).elapsed;
    await drag(start,{x:start.x+75,y:start.y+40});
    await page.waitForFunction(()=>{const s=window.__STARTX_SAMPLE__(),b=s.workbars[0];return b&&Math.abs((b.bounds.x+b.bounds.width/2)-(b.card.x+b.card.width/2))<.2;});
    s=await state();bar=s.workbars[0];validate(bar);assert.equal(bar.anchor,founder.uid);assert(s.cards.find(c=>c.uid===resource.uid).elapsed>=before);
    assert(Math.abs(center(bar.card).x-center(founder.bounds).x-75)<2);
    await page.screenshot({path:path.join(root,'review/compact-hud-production.png')});
    // Use the running scene's real model to reach settlement without waiting three minutes.
    const payment=await page.evaluate(()=>{
     const sample=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),m=sample.model;
     m.cards.filter(c=>c.id==='cash').slice(1).forEach(c=>m.remove(c));
     const account=m.spawn('p3_account',-450,-150);account.stored=10;
     const employee=m.spawn('p2_sales_specialist',400,-150);
     sample.syncViews();return {cash:m.cash,payroll:m.payroll,month:m.month,account:account.uid,targets:m.cards.filter(c=>m.def(c).salary>0).map(c=>c.uid)};
    });
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().ready&&window.__STARTX_SAMPLE__().motions.every(m=>!m.kind));
    const sounds=(await state()).audio.events.filter(e=>e.type==='started'&&e.name==='cash_down').length;
    await page.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);c.model.monthTime=.001;});
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cashFlights.length>0);
    s=await state();assert.equal(s.month,payment.month+1);assert.equal(s.cash,payment.cash-payment.payroll);assert.equal(s.cashFlights.length,payment.payroll);
    assert(s.cashFlights.some(f=>f.uid===undefined),'Stored cash creates visual cash');
    assert.deepEqual([...new Set(s.cashFlights.map(f=>f.targetUid))].sort(),payment.targets.sort());
    for(const f of s.cashFlights){assert.equal(f.kind,'spend');assert(Math.abs(f.scale-1)<.001);}
    await page.waitForFunction(()=>{const s=window.__STARTX_SAMPLE__();return s.cashFlights.length&&s.cashFlights.every(f=>f.time-f.delay>.4);});
    s=await state();for(const f of s.cashFlights){const target=s.cards.find(c=>c.uid===f.targetUid);assert(Math.hypot(center(f.bounds).x-center(target.bounds).x,center(f.bounds).y-center(target.bounds).y)<2);assert(f.opacity<255);}
    await page.screenshot({path:path.join(root,'review/cash-settlement.png')});
    await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cashFlights.length===0);
    s=await state();assert.equal(s.audio.events.filter(e=>e.type==='started'&&e.name==='cash_down').length,sounds+payment.payroll);
    checks.push('Desktop: each pack cash plays cash_down; monthly loose and stored cash fly at full size to salaried cards, fade and deduct once; production bar matches card width with doubled height; centered overlapping drawer tabs put active tab on top');
   }else checks.push('Portrait touch: centered drawer and overlapping tabs, active tab in front, drawer width at most one third, settings moved right and original slim bars retained');
   await ctx.close();
  }
  assert.deepEqual(errors,[]);const report={passed:true,checks,errors};fs.writeFileSync(path.join(root,'review/compact-hud-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
