const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('typescript');
const root = path.resolve(__dirname, '..'), cache = new Map();
function load(name) {
 if (cache.has(name)) return cache.get(name);
 const exports = {}; cache.set(name, exports);
 const code = ts.transpileModule(fs.readFileSync(path.join(root, 'assets/scripts', name + '.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2017 } }).outputText;
 vm.runInNewContext(code, { exports, require: id => load(id.replace('./', '')), Math, Set, Map }); return exports;
}
const { GameModel } = load('GameModel'), { readProgress } = load('ProgressSave');
const data = JSON.parse(fs.readFileSync(path.join(root, 'assets/content/catalog.json'))), clone = v => JSON.parse(JSON.stringify(v));
const m = new GameModel(data, () => .5, true), account = m.cards.find(c => c.id === 'p3_account');
m.withdraw(account); m.move(m.cards[0].uid, -620, 430); m.packs[0].x = 800; m.packs[0].y = -500; m.openPack(m.packs[0].uid);
m.models.add(data.recipes[0].id); m.discovered.add(data.recipes[0].id); m.ideas.add(Object.keys(data.research)[0]); m.completed.add(data.tasks[0].id); m.unlocked.add('Developemnt_pack');
m.month = 4; m.monthTime = 73.25; m.rp = 126; m.revenue = 48; m.paused = true;
const saved = clone(m.saveProgress(false)), restored = GameModel.fromProgress(data, saved, () => .5);
assert(restored); assert.deepEqual(clone(restored.saveProgress()), saved); assert.equal(restored.cards.find(c => c.id === 'p3_account').stored, 45);
assert.equal(restored.heldStack, -1); assert.equal(restored.appearances.size, 0); assert.equal(restored.paused, false);
const spawned = restored.spawn('cash', 0, 0); assert(spawned.uid >= saved.sequence); assert.equal(new Set(restored.cards.map(c => c.uid)).size, restored.cards.length);
const p = new GameModel(data, () => .5, true), resource = p.spawn('p1_neighborhood', 700, 500);
p.merge(p.cards[0].sid, resource.sid); for (let i = 0; i < 10; i++) p.update(.1);
assert(resource.elapsed > 0); const resumed = GameModel.fromProgress(data, p.saveProgress(), () => .5); assert(resumed);
for (let i = 0; i < 60; i++) { p.update(.1); resumed.update(.1); }
assert.deepEqual(clone(resumed.saveProgress()), clone(p.saveProgress()));
const battle = new GameModel(data, () => .5, true), rival = battle.spawn(Object.keys(data.cards).find(id => data.cards[id].type === 'rival'), 600, 0);
battle.startBattle(rival, battle.cards[0], false);
assert(GameModel.fromProgress(data, battle.saveProgress(), () => .5), 'Battle entry with no active attacker remains resumable');
const view = { zoom: .6, pitch: .9, centerX: -200, centerY: 140 }, raw = JSON.stringify({ version: 1, model: saved, view });
assert.deepEqual(clone(readProgress(data, raw).view), view); assert.equal(readProgress(data, '{broken'), null);
for (const mutate of [s => s.version = 99, s => s.state.cards[0].stored = -1, s => s.state.stacks[0].cards.push(99999), s => s.state.cards[0].id = 'missing', s => s.sequence = 1]) {
 const broken = clone(saved); mutate(broken); assert.equal(GameModel.fromProgress(data, broken), null);
}
assert.equal(readProgress(data, JSON.stringify({ version: 1, model: saved, view: { ...view, zoom: null } })), null);
console.log('Progress passed: full state round trip, account/pack/layout, production continuation, unique IDs, pause restoration, invalid-save fallback.');
