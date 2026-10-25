const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true}),page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 try {
  await page.goto('http://127.0.0.1:4173/?review=1');await page.waitForLoadState('networkidle');
  const settled=()=>page.waitForFunction(()=>{const s=window.__STARTX_SAMPLE__?.();return s?.ready&&s.motions.every(m=>!m.kind)});
  const state=()=>page.evaluate(()=>window.__STARTX_SAMPLE__());await settled();
  await page.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews);c.perform('Restart');c.founderSpeech.dismiss();const m=c.model;m.paused=true;m.packs=[];const f=m.cards.find(c=>c.id==='founder');m.stack(f.sid).x=0;m.stack(f.sid).y=0;
   for(const x of [...m.cards])if(x!==f)m.remove(x);
   m.spawn('badge_entrepreneur',-370,0);m.spawn('p1_office',370,0);m.spawn('badge_veteran',-370,-370);m.spawn('rival1',370,-370);
   c.syncViews();c.fitBoard();});await settled();
  let s=await state();const center=c=>({x:c.bounds.x+c.bounds.width/2,y:c.bounds.y+c.bounds.height/2});
  const drag=async(source,target)=>{await page.mouse.move(source.x,source.y);await page.mouse.down();await page.mouse.move(target.x,target.y,{steps:12});await page.mouse.up();};
  const badge=s.cards.find(c=>c.id==='badge_entrepreneur'),founder=s.cards.find(c=>c.id==='founder');assert(badge.bounds.width<founder.bounds.width*.5);
  await drag(center(badge),center(founder));
  await page.waitForFunction(()=>window.__STARTX_SAMPLE__().cards.find(c=>c.id==='founder').badges?.length===1);
  await page.waitForFunction(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),f=c.model.cards.find(c=>c.id==='founder');return !!c.views.get(f.uid).view.frontNode.parent.getChildByName('YarnBadges')});
  s=await state();assert(!s.cards.some(c=>c.uid===badge.uid));assert.equal(s.cards.find(c=>c.id==='founder').effectiveCapacity,6);
  const visual=await page.evaluate(()=>{const c=window.cc.director.getScene().getComponentsInChildren(window.cc.Component).find(c=>c.model&&c.syncViews),f=c.model.cards.find(c=>c.id==='founder'),face=c.views.get(f.uid).view.frontNode.parent;return{badges:face.getChildByName('YarnBadges').children.length,capacity:face.getChildByName('EmployeeCapacity').getChildByName('Value').getComponent('cc.Label').string}});
  assert.deepEqual(visual,{badges:1,capacity:'6'});
  const other=s.cards.find(c=>c.id==='badge_veteran'),office=s.cards.find(c=>c.id==='p1_office');await drag(center(other),center(office));s=await state();assert(s.cards.some(c=>c.uid===other.uid));assert(!s.cards.find(c=>c.uid===office.uid).badges);
  const rival=s.cards.find(c=>c.id==='rival1'),rivalBefore={...rival.position};
  await page.mouse.click(center(rival).x,center(rival).y);s=await state();assert.equal(s.modal,'none');
  await page.mouse.move(center(rival).x,center(rival).y);await page.mouse.down();await page.waitForTimeout(550);await page.mouse.up();assert.equal((await state()).modal,'none');
  await drag(center(rival),center(s.cards.find(c=>c.id==='founder')));s=await state();assert.deepEqual(s.cards.find(c=>c.id==='rival1').position,rivalBefore);assert(!s.battle);
  await page.mouse.click(center(rival).x,center(rival).y,{button:'right'});assert.equal((await state()).modal,'none');
  await page.screenshot({path:root+'/review/screenshots/yarn-badges-game.png'});
  assert.deepEqual(errors,[]);const report={passed:true,visual,checks:['Real mouse drag attaches a small transparent yarn sprite and updates the printed capacity','Dropping onto a facility preserves the badge','Click, long press, right click and drag do not interact with rivals'],errors};
  fs.writeFileSync(root+'/review/yarn-badges-ui-verification.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
