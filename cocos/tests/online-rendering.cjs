const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),base=process.env.STARTX_TEST_URL||'http://127.0.0.1:4173/',checks=[],errors=[];
const android='Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  for(const [name,viewport] of [['square',{width:694,height:640}],['portrait',{width:390,height:844}]].filter(([name])=>!process.env.STARTX_TEST_LAYOUT||process.env.STARTX_TEST_LAYOUT===name)){
   const ctx=await browser.newContext({viewport,isMobile:true,hasTouch:true,deviceScaleFactor:3,userAgent:android}),p=await ctx.newPage();
   p.on('pageerror',e=>errors.push(e.message));p.on('console',e=>{if(e.type()==='error'&&!e.text().startsWith('Ignored attempt to cancel a touch'))errors.push(e.text())});
   const state=()=>p.evaluate(()=>window.__STARTX_SAMPLE__());
   const settled=()=>p.waitForFunction(()=>{const s=window.__STARTX_SAMPLE__?.();return s?.ready&&!s.catalog.capturing&&s.motions.every(m=>!m.kind)});
   const inspect=fn=>p.evaluate(fn);
   const cameraRestored=()=>inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);return c.node.getComponents(window.cc.Component).find(x=>x.cameraComponent).cameraComponent.targetTexture===null});
   const action=async key=>{const s=await state(),b=s.controls[key]||s.catalog.controls[key];assert(b,'Missing '+key);await p.touchscreen.tap(b.x+b.width/2,b.y+b.height/2);await settled()};
   const screenshot=kind=>p.screenshot({path:path.join(root,'output/playwright/render-fixed-'+kind+'-'+name+'.png')});
   await p.goto(base+'?review=1');await settled();await action('Title:Restart');
   await action('Settings');await action('Row:Open:catalog');
   let s=await state();assert(s.catalog.active);assert(s.catalog.viewport.y<190&&s.catalog.viewport.height>viewport.height*.5,'No phantom mobile safe area');
   assert(s.catalog.cards.every(c=>Math.abs(c.bounds.width-112)<.1),'Fixed catalog card size');await screenshot('catalog');
   // Competing captures previously restored another overlay's texture instead of the screen.
   await inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);c.perform('CatalogClose');c.perform('Settings');c.perform('Open:catalog')});
   await settled();assert(await cameraRestored(),'Rapid overlay transitions restore screen target');
   if(name==='portrait'){
    await p.setViewportSize({width:390,height:640});await p.waitForFunction(()=>Math.abs(window.__STARTX_SAMPLE__().viewport.height-640)<.1);await settled();s=await state();
    assert(s.catalog.viewport.y<190&&s.catalog.viewport.height>400,'Browser toolbar resize keeps catalog usable');
   }
   await action('CatalogClose');await action('Row:Continue');
   s=await state();const count=s.cards.length,b=s.packs[0].bounds;
   await p.touchscreen.tap(b.x+b.width/2,b.y+b.height/2);await settled();s=await state();assert(s.cards.length>count,'Pack releases card');
   const card=s.cards.find(c=>c.id==='p1_office');assert(card);
   const rendered=await p.evaluate(uid=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),v=c.views.get(uid).view;return v.node.activeInHierarchy&&v.node.scale.x>0&&!!v.artwork?.texture},card.uid);
   assert(rendered&&card.bounds.x+card.bounds.width>0&&card.bounds.y+card.bounds.height>0&&card.bounds.x<s.viewport.width&&card.bounds.y<s.viewport.height,'Drawn face is loaded and inside viewport');await screenshot('draw');
   const sliding=await inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);for(const {view} of c.views.values())view.slideFrom(-200,0);c.syncViews();const table=c.board.node.getChildByName('Table').getSiblingIndex();return [...c.views.values()].every(s=>s.view.isSliding&&s.view.node.getSiblingIndex()>table)});
   assert(sliding,'Simultaneous sliding cards stay above the table');await settled();
   await inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),m=c.model;m.paused=true;const r=m.spawn('rival1',-280,0);r.funds=100;m.startBattle(r,m.cards.find(c=>c.id==='founder'),true);c.syncViews()});
   await settled();await p.waitForFunction(()=>{const b=window.__STARTX_SAMPLE__().battlePresentation;return b.active&&!b.cameraMoving});
   s=await state();assert(s.battlePresentation.hp.every(h=>h>0));const funds=s.battle.playerHp;
   await inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);c.model.paused=false});
   await p.waitForFunction(value=>window.__STARTX_SAMPLE__().battle?.playerHp<value,funds);
   const arena=await inspect(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),v=c.battleView;c.model.paused=true;return{active:v.root.activeInHierarchy,hp:[v.left.string,v.right.string],aboveTable:v.root.getSiblingIndex()>c.board.node.getChildByName('Table').getSiblingIndex(),cardsAboveTable:[...c.views.values()].every(s=>s.view.node.getSiblingIndex()>c.board.node.getChildByName('Table').getSiblingIndex())}});
   assert(await cameraRestored());assert(arena.active&&arena.aboveTable&&arena.cardsAboveTable&&arena.hp.every(t=>t.startsWith('HP: $')),'Arena and all cards render above the opaque table');await screenshot('battle');
   checks.push({viewport:name,catalogAligned:true,drawnCard:card.id,battleVisible:arena.active,hpBefore:funds,hpAfter:(await state()).battle.playerHp,cameraRestored:true});await ctx.close();
  }
  assert.deepEqual(errors,[]);const report={passed:true,url:base,checks,errors};fs.writeFileSync(path.join(root,'review/online-rendering-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
