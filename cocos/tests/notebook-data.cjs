const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),ts=require('typescript'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json')));
function moduleOf(name){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts',name+'.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText,{exports,Set,Map,Math,require:()=>({})});return exports;}
const {GameModel}=moduleOf('GameModel'),{businessGroups}=moduleOf('Notebook'),m=new GameModel(data,()=>.5),plain=value=>JSON.parse(JSON.stringify(value));
let groups=businessGroups(m);assert.deepEqual(plain(groups.map(g=>[g.stage,g.title,g.total,g.known.length,g.unknown])),[[0,'阶段「车库」',9,0,9],[1,'阶段「验证」',12,0,12],[2,'阶段「产品」',1,0,1]]);
m.models.add('p1_cash_raw_youth');m.models.add('p1_recruit_youth');groups=businessGroups(m);assert.deepEqual(plain(groups[0].known.map(r=>r.id)),['p1_cash_raw_youth','p1_recruit_youth']);
const recipe=data.recipes.find(r=>r.packId==='Developemnt_pack');m.packs.push({uid:999,id:'Developemnt_pack',contents:['bm_'+recipe.id],x:0,y:0,opened:false});
groups=businessGroups(m);assert.equal(groups[1].known[0].id,recipe.id);assert.equal(groups[1].known[0].formula,recipe.formula);assert(!m.models.has(recipe.id));
assert.equal(groups.reduce((n,g)=>n+g.known.length+g.unknown,0),22);
const report={passed:true,checks:['Original Godot stage groups and all 22 placeholder counts','Known recipes follow first-seen order','Business-model card inside an unopened pack is already visible','Formula strings are the original DataLoader export']};
fs.writeFileSync(path.join(root,'review/notebook-data-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
