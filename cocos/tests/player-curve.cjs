// Scripted ordinary-mode players. No injected cards, cash, unlocks or skipped game time.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json'))),api={};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts/GameModel.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText,{exports:api,Math,Set,Map});
function play(seed,delay){
 let rng=seed,time=0,position=0,minCash=Infinity,actions=0;const milestones=[];
 const random=()=>{rng=(rng*1664525+1013904223)>>>0;return rng/4294967296;},m=new api.GameModel(data,random,false);
 const point=()=>({x:-2000+(position++%12)*340,y:1600-Math.floor(position/12)%9*340});
 const advance=seconds=>{
  for(let i=0;i<seconds;i+=.1){const dt=Math.min(.1,seconds-i);m.update(dt);time+=dt;m.appearances.clear();m.cashSpends=[];m.soundCues=[];
   if(m.gameOver)throw Error('cashflow failed at month '+m.month+' / '+Math.round(time)+'s');
   if(m.cleanup)throw Error('board capacity exceeded');if(time>1800)throw Error('time budget exceeded');}
  minCash=Math.min(minCash,m.cash);
 };
 const action=()=>{actions++;advance(delay);};
 const find=id=>m.cards.find(c=>c.id===id)||m.cards.find(c=>c.id===({p1_neighborhood:'p3_large_neighborhood',p1_wholesale:'p3_wholesale_city'}[id]));
 const isolate=c=>{const s=m.stack(c.sid),i=s.cards.indexOf(c.uid);if(i+1<s.cards.length){const p=point();m.move(s.cards[i+1],p.x,p.y);}const p=point();m.move(c.uid,p.x,p.y);};
 const mark=name=>milestones.push({name,seconds:Math.round(time),month:m.month,cash:m.cash,payroll:m.payroll});
 const run=(id,retry=0)=>{
  const r=data.recipes.find(r=>r.id===id),picked=[],before=m.counters['recipe_complete|'+id]||0;
  for(const input of r.inputs)for(let j=0;j<input.count;j++){
   const c=m.cards.find(c=>!picked.includes(c)&&(c.id===input.id||c.id===({p1_neighborhood:'p3_large_neighborhood',p1_wholesale:'p3_wholesale_city'}[input.id])));
   if(!c)throw Error('missing '+input.id+' for '+id);picked.push(c);
  }
  if(r.worker_tags.length){const founder=find('founder');if(!founder)throw Error('no founder');picked.push(founder);}
  picked.forEach(isolate);
  const first=picked[0],p=m.position(first);for(const c of picked.slice(1)){m.move(c.uid,p.x,p.y,first.uid);action();}
  for(let wait=0;wait<120&&(m.counters['recipe_complete|'+id]||0)===before;wait+=.1){
   // Wages can spend a loose cash card while the player is assembling a recipe.
   if(picked.some(c=>c.id==='cash'&&!m.card(c.uid))&&retry<2&&m.cash>0)return run(id,retry+1);
   advance(.1);
  }
  if((m.counters['recipe_complete|'+id]||0)===before)throw Error('recipe stalled '+id+' / '+m.notice+' / '+JSON.stringify(picked.map(c=>({id:c.id,sid:c.sid,exists:!!m.card(c.uid),stack:m.members(c.sid).map(x=>x.id),recipe:m.production(c.sid)?.recipe.id}))));
  for(const c of picked)if(m.card(c.uid)&&data.cards[c.id].type==='employee')isolate(c);
  action();
 };
 const buy=id=>{
  if(!m.packUnlocked(id))throw Error('locked '+id+': '+m.packRequirement(id));
  if(m.cash<data.packs[id].price)throw Error('cannot afford '+id);
  const before=m.packs.length,p=point();m.buyPack(id,p.x,p.y);if(m.packs.length===before)throw Error('pack not purchased '+id);action();
  const pack=m.packs[m.packs.length-1];while(m.packs.some(p=>p.uid===pack.uid)){m.openPack(pack.uid);action();}
 };
 const resource=id=>{for(let i=0;i<5&&!find(id);i++){if(m.cash<3)throw Error('resource deadlock '+id);buy('garage_pack');}if(!find(id))throw Error('resource not found '+id);};
 const sellOne=()=>{
  if(!find('p1_youth')){resource('p1_neighborhood');run('p1_recruit_youth');}
  if(!find('p1_package')&&!find('p1_rawprod')){resource('p1_wholesale');run(find('p2_product_specialist')?'p2_specialist_package_product':'p1_make_rawprod');}
  run(find('p1_package')?'p1_cash_pkg_youth':'p1_cash_raw_youth');
 };
 const earn=amount=>{for(let n=0;m.cash<amount&&n<30;n++)sellOne();if(m.cash<amount)throw Error('unable to earn buffer');};
 const quality=()=>{if(!find('p1_package'))run('p2_specialist_package_product');run('p4_upgrade');};
 try {
  while(m.packs.length){m.openPack(m.packs[0].uid);action();}mark('opening');
  run('p1_make_rawprod');run('p1_recruit_youth');run('p1_cash_raw_youth');mark('first_sale');
  buy('garage_pack');run('p1_recruit_intern');earn(5+m.payroll+2);buy('Developemnt_pack');run('p2_train_grad');run('p2_train_product_specialist');mark('product_specialist');
  earn(6+m.payroll+2);buy('channel_pack');run('p2_make_document');run('p2_make_contract');run('p3_open_account');mark('account');run('p2_make_document');run('p2_make_contract');
  earn(8+m.payroll+4);while(m.month<2){sellOne();}mark('product_unlocked');
  for(let i=0;i<4;i++){
   if(!m.cards.some(c=>c.id==='p4_order'&&!c.orderNumber)){earn(8+m.payroll+4);buy('product_pack');}
   quality();const order=m.cards.find(c=>c.id==='p4_order'&&!c.orderNumber);m.acceptOrder(order);action();
   if(find('p4_change'))run('p4_decline_change');
   quality();run('p4_deliver');
   if(find('p4_receivable'))run('p4_collect');
   if(find('p4_referral'))run('p4_referral_order');
   mark('order_'+(i+1));
  }
  return {seed,delay,passed:true,seconds:Math.round(time),cash:m.cash,minCash,payroll:m.payroll,actions,missedOrders:m.counters['order_failed|']||0,orders:m.counters['order_completed|']||0,events:['change','receivable','referral'].filter(id=>m.counters['customer_event_resolved|'+id]>0),milestones};
 } catch(error){return{seed,delay,passed:false,error:error.message,seconds:Math.round(time),cash:m.cash,month:m.month,notice:m.notice,milestones};}
}
const runs=[];for(const delay of [1.5,4,7])for(const seed of [19,73,241,997])runs.push(play(seed,delay));
const report={kind:'scripted ordinary-mode players',note:'Actions use real opening cards, pack costs, recipe time and monthly wages; 1.5/4/7 seconds between actions. This is balance simulation, not human usability evidence.',passed:runs.every(r=>r.passed),runs};
fs.writeFileSync(path.join(root,'review/player-curve.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({passed:report.passed,runs:runs.map(({milestones,...r})=>r)},null,2));
process.exitCode=report.passed?0:1;
