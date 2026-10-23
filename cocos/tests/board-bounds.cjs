const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict'), ts = require('typescript');
const root = path.resolve(__dirname, '..'), exportsModel = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'assets/scripts/GameModel.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2017 }
}).outputText, { exports: exportsModel, Math, Set });
const { GameModel, BOARD_HALF } = exportsModel, data = JSON.parse(fs.readFileSync(path.join(root, 'assets/content/catalog.json')));
const model = () => new GameModel(data, () => .5, true);
const inside = m => {
    for (const c of m.cards) {
        const p = m.position(c);
        assert(Math.abs(p.x) + 152 <= BOARD_HALF + .001, 'Card left/right edge');
        assert(Math.abs(p.y) + 152 <= BOARD_HALF + .001, 'Card top/bottom edge');
    }
    for (const p of m.packs) {
        assert(Math.abs(p.x) + 180 <= BOARD_HALF + .001, 'Pack left/right edge');
        assert(Math.abs(p.y) + 180 <= BOARD_HALF + .001, 'Pack top/bottom edge');
    }
};
const m = model(), founder = m.cards[0];
for (const x of [-1e6, 1e6]) for (const y of [-1e6, 1e6]) { m.move(founder.uid, x, y); inside(m); }
let first;
for (let i = 0; i < 50; i++) { const c = m.spawn('cash', 1e6, -1e6); if (first) m.merge(c.sid, first.sid); else first = c; inside(m); }
assert.equal(m.stackOffset(first.sid), 48);
m.move(first.uid, 1e6, -1e6); inside(m);
const part = m.members(first.sid)[25]; m.move(part.uid, -1e6, 1e6); inside(m);
for (let i = 0; i < 80; i++) { const c = m.spawn('cash', 0, -1e6); m.merge(c.sid, first.sid); }
m.move(first.uid, 1e6, -1e6); inside(m);
assert(m.stacks.every(s => m.stackOffset(s.sid) === 48), 'No stack spacing compression');
assert(m.displacements.size > 0, 'Out-of-bounds stack schedules a smooth group correction');
const g = model();
g.output('cash', 12, BOARD_HALF - 140, -BOARD_HALF + 140); inside(g);
g.buyPack('garage_pack', 1e6, -1e6); inside(g);
const pack = g.packs[g.packs.length - 1];
while (g.packs.some(p => p.uid === pack.uid)) { g.openPack(pack.uid); inside(g); }
const stack = g.stack(g.cards[0].sid); g.moveStack(stack, -1e6, 1e6);
for (let i = 0; i < 20; i++) { g.updateStackMotions(.03); inside(g); }
const result = { passed: true, checks: ['Four-edge card moves', 'All stacks retain 48 spacing and slide inward', 'Split, merge and overflowing stacks stay inside',
    'Production, pack placement and unpacking stay inside', 'Automatic movement and overshoot stay inside'] };
fs.writeFileSync(path.join(root, 'review/board-bounds-verification.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(result));
