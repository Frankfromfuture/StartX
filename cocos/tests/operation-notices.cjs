const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict'), ts = require('typescript');
const root = path.resolve(__dirname, '..'), exportsModel = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'assets/scripts/GameModel.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2017 } }).outputText, { exports: exportsModel, Math, Set, Map });
const { GameModel } = exportsModel, data = JSON.parse(fs.readFileSync(path.join(root, 'assets/content/catalog.json')));
for (const cleanup of [false, true]) {
    const m = new GameModel(data, () => .5), doc = m.spawn('p2_document', 500, 400), before = m.cash;
    m.cleanup = cleanup; assert(m.canSell(doc.sid)); m.sell(doc.sid);
    assert(!m.card(doc.uid)); assert.equal(m.cash, before); assert.equal(m.cards.filter(c => c.id === 'cash').length, 0);
    assert.equal(m.noticeKind, 'operation'); assert.equal(m.operationNotice, '已回收文书（无现金收益）');
}
const m = new GameModel(data, () => .5), product = m.spawn('p1_rawprod', 500, 400), value = m.def(product).value;
m.sell(product.sid); assert.equal(m.cash, value); assert.equal(m.operationNotice, `出售获得 $${value}`);
m.operationNotice = ''; m.say(m.cardHint(m.cards.find(c => c.id === 'founder')), 'hint'); assert.equal(m.operationNotice, ''); assert.equal(m.noticeKind, 'hint');
const milestone = data.tasks.find(t => !m.completed.has(t.id));
m.event(milestone.triggerType, milestone.targetId, milestone.targetCount); assert(m.completed.has(milestone.id)); assert(m.taskNotices.some(t => t.includes(milestone.title))); assert.equal(m.operationNotice, '');
m.say('完成供应链下游组建'); const saved = m.saveProgress();
assert(!('operationNotice' in saved.state)); assert(!('noticeKind' in saved.state));
const restored = GameModel.fromProgress(data, saved, () => .5); assert(restored); assert.equal(restored.operationNotice, '');
console.log('Passed: free document recycling, paid-product regression, operation/hint/milestone separation, no replay of saved speech.');
