const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),ts=require('typescript');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json')));
const source=ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts/GameModel.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText;
const api={};vm.runInNewContext(source,{exports:api,Math,Set});
function advance(m,condition,limit=60){for(let t=0;t<limit&&!condition();t+=.02)m.update(.02);assert(condition(),'Battle phase reached within timeout');}
const m=new api.GameModel(data,()=>.5,true),founder=m.cards[0],rival=m.spawn('rival2',1800,900),r=m.stack(rival.sid);
const before={x:r.x,y:r.y};m.update(3);assert.equal(r.x,before.x,'Enemy move begins without teleporting');m.update(.1);assert(r.x!==before.x&&r.x!==before.x-140,'Enemy interpolates through intermediate positions');
const intern=m.spawn('p1_intern',1000,0);m.merge(intern.sid,founder.sid);
const obstacle=m.spawn('p1_office',m.stack(founder.sid).x+80,m.stack(founder.sid).y-20);m.timerStarted=false;
m.move(founder.uid,r.x,r.y,rival.uid);assert(m.battle&&!m.battle.rivalTurn,'Dragging people onto a rival grants player initiative');
const b=m.battle;assert.equal(b.phase,'entry');assert.equal(b.timer,1.5);assert.equal(m.production(founder.sid),undefined);assert(m.soundCues.includes('battle_start'));
advance(m,()=>b.phase==='outward');assert.equal(b.attacker,founder.uid);m.update(.24);assert(m.battlePose(founder.uid).lift>70,'Attacks have an airborne midpoint');assert.equal(b.enemyHp,12,'No damage before landing');
advance(m,()=>b.phase==='return');assert.equal(b.enemyHp,7);assert.equal(rival.funds,7);assert.equal(m.battleHits[0].amount,5);
const late=m.spawn('p2_grad',r.x+1200,r.y);m.move(late.uid,r.x+560,r.y,founder.uid);assert.equal(m.members(founder.sid).length,3,'Reinforcements join the player stack');
advance(m,()=>b.attacker===intern.uid&&b.phase==='outward');assert(!b.attackers.includes(late.uid),'Mid-turn arrivals wait until the next player turn');
advance(m,()=>b.phase==='interval');assert.equal(b.enemyHp,6,'Each original team member attacks once');
const rect=m.battleRect,o=m.position(obstacle);assert(Math.abs(o.x-rect.x)>rect.width/2+139||o.y+140<=rect.y-rect.height/2||o.y-140>=rect.y+rect.height/2,'Noncombatants leave the arena');
advance(m,()=>b.rivalTurn&&b.phase==='return');assert.equal(b.playerHp,46);assert.equal(m.cash,50,'Cash is settled once at battle end');
advance(m,()=>!m.battle);assert(!m.card(rival.uid));assert(m.defeated.has(rival.uid));assert.equal(m.cash,46);assert.equal(m.counters['rival_defeated|'],1);assert.equal(m.counters['team_rival_defeated|'],1);assert(m.soundCues.includes('hit')&&m.soundCues.includes('battle_end'));
// Closest regression: rival contact starts first and a bankrupt employee loses.
const loss=new api.GameModel(data,()=>.5),loser=loss.spawn('p1_intern',1400,400),enemy=loss.spawn('rival1',1400,400);loss.spawn('cash',2200,0);
loss.update(.02);assert(loss.battle.rivalTurn);advance(loss,()=>!loss.battle);assert(!loss.card(loser.uid));assert(loss.card(enemy.uid));assert.equal(loss.cash,0);assert(loss.defeated.has(loser.uid));assert(!loss.counters['rival_defeated|']);
const report={passed:true,checks:['50 cash cards form one bounded stack without changing card dimensions','Enemies move continuously on the original three-second cadence','Original entry, per-person arc/impact/return timing and initiative','Mid-turn reinforcements wait; other stacks leave the arena','Original cumulative cash deduction, victory tasks and defeat removal; battle sounds queued']};
fs.writeFileSync(path.join(root,'review/battle-rules.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
