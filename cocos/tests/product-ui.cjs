const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),errors=[];
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const context=await browser.newContext({viewport:{width:1100,height:820}}),p=await context.newPage();
  p.on('pageerror',e=>errors.push(e.message));
  await p.addInitScript(()=>{if(!localStorage.getItem('startx.progress.v1'))localStorage.setItem('startx.test-mode','false')});
  const state=()=>p.evaluate(()=>window.__STARTX_SAMPLE__());
  const settled=()=>p.waitForFunction(()=>{const s=window.__STARTX_SAMPLE__?.();return s?.ready&&!s.menuBackdrop.capturing&&s.motions.every(m=>!m.kind)});
  const action=async key=>{const s=await state(),b=s.controls[key]||s.catalog.controls[key];assert(b,key);await p.mouse.click(b.x+b.width/2,b.y+b.height/2);await settled()};
  const center=c=>({x:c.bounds.x+c.bounds.width/2,y:c.bounds.y+c.bounds.height/2});
  await p.goto('http://127.0.0.1:4173/?review=1');await settled();await action('Title:Restart');
  await p.evaluate(()=>{
   const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),m=c.model;
   for(const card of [...m.cards])if(card.id!=='founder')m.remove(card);m.packs=[];m.timerStarted=false;
   m.move(m.cards[0].uid,-650,-420);m.spawn('p3_account',-320,-420).stored=30;
   for(const [id,x,y] of [['p4_order',0,60],['p4_quality',340,60],['p4_quality',680,60],['p4_change',-340,60],['p4_receivable',0,-420],['p4_referral',340,-420]])m.spawn(id,x,y);
   c.syncViews();c.fitBoard();
  });await settled();
  const visible=await p.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);return c.model.cards.filter(x=>x.id.startsWith('p4_')).every(x=>c.views.get(x.uid).view.node.activeInHierarchy&&!!c.views.get(x.uid).view.artwork?.texture)});assert(visible,'All generated card faces load');
  assert(await p.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),order=c.model.cards.find(x=>x.id==='p4_order');return c.views.get(order.uid).view.status.actualFontSize>=17}),'Order timer remains legible');
  await p.screenshot({path:path.join(root,'output/playwright/product-cards.png')});
  let s=await state(),order=s.cards.find(x=>x.id==='p4_order'),o=center(order);await p.mouse.click(o.x,o.y);
  await p.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p4_order'&&c.orderNumber===1));
  const delivered=new Set();
  for(let i=0;i<2;i++){
   s=await state();const card=s.cards.find(c=>c.id==='p4_quality'&&!delivered.has(c.uid));delivered.add(card.uid);const product=center(card);o=center(s.cards.find(c=>c.id==='p4_order'));
   await p.mouse.move(product.x,product.y);await p.mouse.down();await p.mouse.move(o.x,o.y,{steps:15});await p.mouse.up();await settled();
  }
  await p.waitForFunction(()=>!window.__STARTX_SAMPLE__().cards.some(c=>c.id==='p4_order'));await settled();s=await state();assert.equal(s.cash,54);assert(s.tasks.includes('p4_first_order'));
  await p.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),m=c.model;const order=m.spawn('p4_order',0,60);m.acceptOrder(order);c.syncViews();c.saveProgress()});await settled();
  s=await state();const remaining=s.cards.find(c=>c.id==='p4_order').deadline;
  await p.reload();await settled();await action('Title:Continue');s=await state();const resumed=s.cards.find(c=>c.id==='p4_order');assert(resumed&&resumed.orderNumber===2);assert(Math.abs(resumed.deadline-remaining)<8);assert.equal(s.cash,54);
  await action('Settings');await action('Row:Open:catalog');s=await state();assert(s.catalog.active);assert(s.catalog.cards.filter(c=>c.id.startsWith('p4_')).length>=5);
  await p.screenshot({path:path.join(root,'output/playwright/product-catalog.png')});
  assert.deepEqual(errors,[]);const report={passed:true,checks:['Five new generated faces render on the board','Pointer tap accepts an order; dragging two products pays exactly $24 and completes its task','Refresh restores the active second order, remaining time and $30 account plus $24 cash','New unlocked cards appear in the blurred catalog'],errors};
  fs.writeFileSync(path.join(root,'review/product-ui-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
