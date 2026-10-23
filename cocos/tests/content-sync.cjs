const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { zipSync, strToU8 } = require('fflate');
const { syncContent } = require('../tools/sync-content.cjs');
const { readWorkbook, catalogFromSheets } = require('../tools/workbook.cjs');
const { colors, functionText } = require('../tools/render-cards.cjs');
const root = path.resolve(__dirname, '..'), hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const escape = value => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
function workbook(sheets, file) {
    const files = {}, names = Object.keys(sheets);
    files['xl/workbook.xml'] = strToU8(`<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${names.map((name, i) => `<sheet name="${name}" sheetId="${i + 1}" r:id="r${i}"/>`).join('')}</sheets></workbook>`);
    files['xl/_rels/workbook.xml.rels'] = strToU8(`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${names.map((name, i) => `<Relationship Id="r${i}" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}</Relationships>`);
    const column = i => i < 26 ? String.fromCharCode(65 + i) : column(Math.floor(i / 26) - 1) + column(i % 26);
    names.forEach((name, i) => {
        const keys = Object.keys(sheets[name][0]), rows = [keys, ...sheets[name].map(r => keys.map(k => r[k]))];
        files[`xl/worksheets/sheet${i + 1}.xml`] = strToU8(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${rows.map((row, r) => `<row r="${r + 1}">${row.map((v, c) => `<c r="${column(c)}${r + 1}" t="inlineStr"><is><t>${escape(v)}</t></is></c>`).join('')}</row>`).join('')}</sheetData></worksheet>`);
    });
    fs.writeFileSync(file, zipSync(files));
}
(async () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'startx-data-')), checks = [];
    try {
        const config = Object.fromEntries(['balance', 'research', 'idea_pools'].map(k => [k === 'idea_pools' ? 'ideaPools' : k, JSON.parse(fs.readFileSync(path.join(root, 'data', k + '.json')))]));
        const sheets = readWorkbook(path.join(root, 'data/startx_data.xlsx')), baseline = catalogFromSheets(sheets, config);
        for (const [id, card] of Object.entries(baseline.cards)) { card.bodyColor = colors(id, card).body.slice(1); card.functionText = functionText(id, card, baseline); }
        assert.deepEqual(baseline, JSON.parse(fs.readFileSync(path.join(root, 'assets/content/catalog.json'))));
        checks.push('Existing prefixed/shared-string workbook produces the complete current catalog without rule changes');
        fs.cpSync(path.join(root, 'data'), path.join(temp, 'data'), { recursive: true });
        fs.mkdirSync(path.join(temp, 'assets/sample/art'), { recursive: true });
        fs.copyFileSync(path.join(root, 'assets/sample/art/founder-face.png.meta'), path.join(temp, 'assets/sample/art/founder-face.png.meta'));
        const shared = global.SharedArrayBuffer;
        try { global.SharedArrayBuffer = undefined; await syncContent({ root: temp }); }
        finally { global.SharedArrayBuffer = shared; }
        checks.push('Card and SVG rendering work in Creator build sandbox without SharedArrayBuffer');
        const face = path.join(temp, 'assets/content/faces/founder.png'), pack = path.join(temp, 'assets/content/packs/garage_pack.png');
        const before = { face: hash(face), pack: hash(pack), uuid: JSON.parse(fs.readFileSync(face + '.meta')).uuid };
        sheets.cards.find(c => c.id === 'founder').name = '测试创始人'; sheets.cards.find(c => c.id === 'founder').capacity = '9';
        sheets.cards.push({ ...sheets.cards.find(c => c.id === 'founder'), id: 'sync_test_card', name: '构建测试新卡', salary: '2' });
        const originalArt = fs.readdirSync(path.join(temp, 'data/art/cards')).find(n => /^founder\.(png|svg)$/.test(n));
        fs.copyFileSync(path.join(temp, 'data/art/cards', originalArt), path.join(temp, 'data/art/cards/sync_test_card' + path.extname(originalArt)));
        sheets.packs.find(p => p.id === 'garage_pack').name = '测试卡包'; sheets.packs.find(p => p.id === 'garage_pack').price = '7';
        sheets.recipes[0].output1Count = '2'; sheets.tasks[0].title = '构建同步测试';
        workbook(sheets, path.join(temp, 'data/startx_data.xlsx')); await syncContent({ root: temp });
        const changed = JSON.parse(fs.readFileSync(path.join(temp, 'assets/content/catalog.json')));
        assert.equal(changed.cards.founder.name, '测试创始人'); assert.equal(changed.cards.founder.capacity, 9);
        assert.equal(changed.packs.garage_pack.price, 7); assert.equal(changed.recipes[0].outputs[0].count, 2); assert.equal(changed.tasks[0].title, '构建同步测试');
        assert.notEqual(hash(face), before.face); assert.notEqual(hash(pack), before.pack);
        assert.equal(JSON.parse(fs.readFileSync(face + '.meta')).uuid, before.uuid);
        assert(fs.readFileSync(face).equals(fs.readFileSync(path.join(temp, 'assets/sample/art/founder-face.png'))));
        for (const group of ['faces', 'icons']) assert(fs.existsSync(path.join(temp, 'assets/content', group, 'sync_test_card.png.meta')));
        checks.push('Editing name, capacity, recipe yield, pack price/name and task updates JSON, card faces, wrapper and founder prefab; adding a card generates PNG and stable Cocos metadata');
        const mtime = fs.statSync(face).mtimeMs, cached = await syncContent({ root: temp });
        assert.equal(cached.changed.length, 0); assert.equal(fs.statSync(face).mtimeMs, mtime);
        checks.push('Unchanged builds reuse generated resources without rewriting them');
        const validHash = hash(path.join(temp, 'assets/content/catalog.json'));
        sheets.recipes[0].input1 = 'missing_card'; workbook(sheets, path.join(temp, 'data/startx_data.xlsx'));
        await assert.rejects(syncContent({ root: temp }), /不存在的卡牌/);
        assert.equal(hash(path.join(temp, 'assets/content/catalog.json')), validHash);
        checks.push('Invalid Excel reference stops synchronization before replacing valid generated assets');
        const report = { passed: true, checks };
        fs.writeFileSync(path.join(root, 'review/content-sync-verification.json'), JSON.stringify(report, null, 2) + '\n');
        console.log(JSON.stringify(report, null, 2));
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
