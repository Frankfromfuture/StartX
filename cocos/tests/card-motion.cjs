const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),ts=require('typescript');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json')));
const code=ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts/GameModel.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText;
const api={};vm.runInNewContext(code,{exports:api,Math,Set});
let seed=15485863;const random=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;};
const model=()=>new api.GameModel(data,random),distributions=[];
for(const [name,width,height] of [['portrait',390,844],['landscape',1440,900]])for(const source of ['pack','production']){
 let vertical=0,positive=0;const bearings=new Set();
 for(let i=0;i<1000;i++){
  const m=model();m.setViewport(width,height);let born,origin;
  if(source==='pack'){
   const pack=m.packs[0];origin={x:pack.x,y:pack.y};m.openPack(pack.uid);born=m.cards.find(c=>c.id==='p1_office');
  }else{
   m.packs=[];const worker=m.cards[0],resource=m.spawn('p1_neighborhood',500,0);m.merge(worker.sid,resource.sid);
   const p=m.production(resource.sid);assert(p);origin={x:m.stack(resource.sid).x,y:m.stack(resource.sid).y};m.complete(m.stack(resource.sid),p);born=m.cards.find(c=>c.id==='p1_youth');
  }
  assert(born);const position=m.position(born),dx=position.x-origin.x,dy=position.y-origin.y;
  if(Math.abs(dy)>Math.abs(dx))vertical++;if((Math.abs(dy)>Math.abs(dx)?dy:dx)>0)positive++;
  bearings.add(Math.atan2(dy,dx).toFixed(3));
 }
 const fraction=vertical/1000;assert(name==='portrait'?fraction>.73&&fraction<.87:fraction>.21&&fraction<.36);
 assert(positive>420&&positive<580,'Both signs remain random');assert(bearings.size>300,'Bearings have random lateral variation');
 distributions.push({viewport:name,source,verticalFraction:fraction,horizontalFraction:1-fraction,samples:1000});
}
const resized=model();resized.setViewport(390,844);const portrait=resized.verticalFlightChance;resized.setViewport(1440,900);assert(resized.verticalFlightChance<portrait);
const compatible=model(),resource=compatible.spawn('p1_neighborhood',500,0),founder=compatible.cards[0];
assert(compatible.canInteract(founder.uid,resource.uid));compatible.move(founder.uid,500,0,resource.uid);assert.equal(founder.sid,resource.sid);
const incompatible=model(),office=incompatible.spawn('p1_office',500,0),raw=incompatible.spawn('p1_rawprod',-500,0),before=incompatible.position(office);
assert.equal(incompatible.canInteract(raw.uid,office.uid),false);incompatible.move(raw.uid,500,0,office.uid);
assert.notEqual(raw.sid,office.sid);assert.deepEqual(incompatible.displacements.get(office.uid),before);assert(!incompatible.displacements.has(raw.uid));assert(Math.hypot(incompatible.position(office).x-before.x,incompatible.position(office).y-before.y)>100);
const bank=model(),account=bank.spawn('p3_account',500,0),cash=bank.spawn('cash',-500,0);account.stored=50;
assert.equal(bank.canInteract(cash.uid,account.uid),false);bank.move(cash.uid,500,0,account.uid);assert.equal(bank.cash,51);assert.equal(account.stored,50);
const sale=model();sale.setViewport(390,844);const product=sale.spawn('p1_package',600,-600),origin={x:600,y:-600};sale.sell(product.sid,origin);
assert(sale.cards.filter(c=>c.id==='cash').every(c=>{const p=sale.position(c);return p.x<origin.x&&p.y>origin.y&&sale.appearances.get(c.uid).slide;}));
const report={passed:true,distributions,checks:['Viewport weights apply to real pack openings and production, with random signs and angles','Resize updates weights immediately','Matching hints and drops agree; incompatible targets retain their slide origin','Full accounts preserve cash and sale cash still exits upper-left']};
fs.writeFileSync(path.join(root,'review/card-motion-rules.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
