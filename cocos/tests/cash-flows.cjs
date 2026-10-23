const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),ts=require('typescript');
const root=path.resolve(__dirname,'..'),data=JSON.parse(fs.readFileSync(path.join(root,'assets/content/catalog.json')));
const code=ts.transpileModule(fs.readFileSync(path.join(root,'assets/scripts/GameModel.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2017}}).outputText;
const exportsModel={};vm.runInNewContext(code,{exports:exportsModel,Math,Set});
const create=()=>new exportsModel.GameModel(data,()=>.5);
const audible=m=>{const cash=m.cards.filter(c=>c.id==='cash');assert(cash.length);for(const c of cash)assert.equal(m.appearances.get(c.uid).landSound,'cash_down');};
const pack=create();pack.openPack(pack.packs[0].uid);pack.openPack(pack.packs[0].uid);audible(pack);assert.equal(pack.cash,5);
const withdrawal=create(),account=withdrawal.spawn('p3_account',500,0);account.stored=5;withdrawal.withdraw(account);audible(withdrawal);assert.equal(withdrawal.cash,5);
const sale=create(),product=sale.spawn('p1_rawprod',400,0);sale.sell(product.sid);audible(sale);assert.equal(sale.cash,data.cards.p1_rawprod.value);
const production=create(),recipe=data.recipes.find(r=>r.id==='p1_cash_raw_youth');
let base;for(const input of recipe.inputs)for(let i=0;i<input.count;i++){const c=production.spawn(input.id,600,0);if(base)production.merge(c.sid,base.sid);else base=c;}
production.complete(production.stack(base.sid),{recipe,target:base});audible(production);assert.equal(production.cash,4);
const month=create();month.packs=[];month.spawn('p1_office',0,0);month.spawn('p2_sales_specialist',400,0);
const cash=month.spawn('cash',-400,0),bank=month.spawn('p3_account',-400,-300);bank.stored=5;
month.monthTime=.01;month.update(.1);assert.equal(month.month,2);assert.equal(month.cash,2);assert.equal(bank.stored,2);assert.equal(month.cashSpends.length,4);
assert.equal(month.card(cash.uid),undefined);assert.equal(month.cashSpends[0].uid,cash.uid);assert.equal(month.cashSpends.filter(f=>f.uid===undefined).length,3);
for(const flight of month.cashSpends.slice(1)){const origin=month.position(bank);assert.equal(flight.from.x,origin.x);assert.equal(flight.from.y,origin.y);}
assert.equal(new Set(month.cashSpends.map(f=>f.targetUid)).size,2);
assert.equal(month.cashSpends[3].delay,.05*3);
month.cashSpends.length=0;month.monthTime=.01;month.update(.1);assert(month.gameOver);assert.equal(month.cash,2);assert.equal(bank.stored,2);assert.equal(month.cashSpends.length,0);
const testMonth=new exportsModel.GameModel(data,()=>.5,true),testAccount=testMonth.cards.find(c=>c.id==='p3_account');
testMonth.packs=[];testMonth.spawn('p1_office',0,0);testMonth.spawn('p2_sales_specialist',400,0);
const accountOrigin=testMonth.position(testAccount),salaryTargets=testMonth.cards.filter(c=>data.cards[c.id].salary>0);
testMonth.monthTime=.01;testMonth.update(.1);assert.equal(testMonth.month,2);assert.equal(testAccount.stored,46);assert.equal(testMonth.cash,46);
assert.equal(testMonth.cards.filter(c=>c.id==='cash').length,0);assert.equal(testMonth.cashSpends.length,4);
for(const flight of testMonth.cashSpends){assert.equal(flight.uid,undefined);assert.equal(flight.from.x,accountOrigin.x);assert.equal(flight.from.y,accountOrigin.y);const target=salaryTargets.find(c=>c.uid===flight.targetUid);assert(target);const to=testMonth.position(target);assert.equal(flight.to.x,to.x);assert.equal(flight.to.y,to.y);}
const partial=create();partial.packs=[];partial.spawn('p1_office',0,0);partial.spawn('p2_sales_specialist',400,0);
const partialAccount=partial.spawn('p3_account',-400,-300);partialAccount.stored=3;const partialCash=partial.spawn('cash',-400,0);
partial.monthTime=.01;partial.update(.1);assert.equal(partial.month,2);assert.equal(partial.cash,0);assert.equal(partialAccount.stored,0);
assert.equal(partial.cashSpends.length,4);assert.equal(partial.cashSpends[0].uid,partialCash.uid);assert(partial.cashSpends.slice(1).every(f=>f.uid===undefined));
const failed=create();failed.packs=[];failed.spawn('p1_office',0,0);failed.monthTime=.01;failed.update(.1);assert(failed.gameOver);assert.equal(failed.cashSpends.length,0);
const report={passed:true,checks:['Pack, production, sale and withdrawal cash all request the same sound','Month settlement spends loose cash first, then stored cash; account payment flights originate at the account','Test account pays monthly payroll directly from its position to salary cards without withdrawing loose cash','Mixed cash sources cover payroll exactly; insufficient total cash creates no deductions or payment flights']};
fs.writeFileSync(path.join(root,'review/cash-flows-verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
