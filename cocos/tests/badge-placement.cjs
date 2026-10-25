const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),ts=require('typescript');
const api={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('assets/scripts/GameModel.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText,{exports:api,Math,Set,Map});
const data=JSON.parse(fs.readFileSync('assets/content/catalog.json')),m=new api.GameModel(data,()=>.5),first=m.cards[0],second=m.spawn('p1_intern',800,0);
const plain=v=>JSON.parse(JSON.stringify(v)),safe=p=>{
 assert(p.x-35>=-136&&p.x+35<=136&&p.y-35>=-136&&p.y+35<=76,'The whole badge stays inside the card and below its title');
 for(const [left,right] of [[-130,-60],[60,130]])assert(p.x+35<=left||p.x-35>=right||p.y-35>=-60||p.y+35<=-130,'The badge avoids both bottom number areas');
};
for(const point of [{x:45,y:15},{x:-200,y:200},{x:-95,y:-95},{x:95,y:-95},{x:0,y:-200}]){
 const badge=m.spawn('badge_entrepreneur',1200,0);assert(m.attachBadge(badge,first,point));const at=first.badgePositions.at(-1);safe(at);
 if(point.x===45)assert.deepEqual(plain(at),point,'Legal drop locations are preserved');
}
const capacity=m.employeeCapacity(first),count=first.badges.length,removed=m.detachBadge(first,1);
assert(removed);assert.equal(first.badges.length,count-1);assert.equal(m.employeeCapacity(first),capacity-1);assert.equal(first.badgePositions.length,first.badges.length);
const snapshot=m.saveProgress(),restored=api.GameModel.fromProgress(data,snapshot);assert(restored);assert.deepEqual(plain(restored.card(first.uid).badgePositions),plain(first.badgePositions));assert(restored.card(removed.uid),'A detached badge remains a real saved token');
assert(m.attachBadge(removed,second,{x:-43,y:3}));assert.equal(m.employeeCapacity(second),data.cards.p1_intern.capacity+1);assert(!m.card(removed.uid));assert.deepEqual(plain(second.badgePositions),[{x:-43,y:3}]);
assert.equal(m.detachBadge(first,99),undefined);assert.equal(m.detachBadge(first,-1),undefined);
const old=m.saveProgress();old.state.cards.forEach(c=>delete c.badgePositions);const migrated=api.GameModel.fromProgress(data,old);assert(migrated);migrated.badgePositionsFor(migrated.card(first.uid)).forEach(safe);
const broken=m.saveProgress();broken.state.cards.find(c=>c.uid===first.uid).badgePositions[0].x=null;assert.equal(api.GameModel.fromProgress(data,broken),null);
console.log('Badge placement passed: exact legal drops, full containment, title and both number exclusions, detach/reapply capacity, persistent positions, detached-token recovery and legacy saves.');
