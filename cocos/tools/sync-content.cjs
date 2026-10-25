const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { readWorkbook, catalogFromSheets } = require('./workbook.cjs');
const { renderer, colors, functionText } = require('./render-cards.cjs');
const PROJECT = path.resolve(__dirname, '..');
const NS = Buffer.from('8930c3958eab48d38b6c1b3f1fd8f43c', 'hex');
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const encode = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
const allFiles = root => fs.readdirSync(root, { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? allFiles(path.join(root, entry.name)) : [path.join(root, entry.name)]).sort();
function uuid(name) {
    const b = crypto.createHash('sha1').update(NS).update(name).digest().subarray(0, 16); b[6] = (b[6] & 15) | 80; b[8] = (b[8] & 63) | 128;
    const h = b.toString('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
function imageMeta(root, file, buffer) {
    const template = json(path.join(root, 'assets/sample/art/founder-face.png.meta'));
    const previous = path.join(root, file + '.meta');
    const id = fs.existsSync(previous) ? json(previous).uuid : uuid(file);
    const width = buffer.readUInt32BE(16), height = buffer.readUInt32BE(20);
    template.uuid = id; template.userData.redirect = id + '@6c48a';
    for (const [key, meta] of Object.entries(template.subMetas)) {
        meta.uuid = id + '@' + key; meta.displayName = path.basename(file, '.png');
        meta.userData.imageUuidOrDatabaseUri = id + (key === 'f9941' ? '@6c48a' : '');
        if (key === 'f9941') {
            Object.assign(meta.userData, { width, height, rawWidth: width, rawHeight: height, trimType: 'none', trimX: 0, trimY: 0, offsetX: 0, offsetY: 0, packable: false });
            delete meta.userData.vertices;
        }
    }
    return encode(template);
}
function writeChanged(root, file, buffer, changed) {
    const target = path.join(root, file);
    if (fs.existsSync(target) && fs.readFileSync(target).equals(buffer)) return;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target + '.tmp', buffer); fs.renameSync(target + '.tmp', target); changed.push(file);
}
async function syncContent({ root = PROJECT, source = path.join(root, 'data'), force = false } = {}) {
    const workbook = path.join(source, 'startx_data.xlsx');
    if (!fs.existsSync(workbook)) throw Error('缺少数据源：' + workbook);
    const cachePath = path.join(root, 'temp/content-sync.json');
    let cache; try { cache = json(cachePath); } catch { /* First build. */ }
    const inputs = [...allFiles(source), __filename, path.join(__dirname, 'workbook.cjs'), path.join(__dirname, 'render-cards.cjs')];
    const fingerprint = digest(inputs.map(file => path.relative(source, file) + ':' + digest(fs.readFileSync(file))).join('\n'));
    if (!force && cache?.fingerprint === fingerprint && Object.entries(cache.outputs).every(([name, hash]) => fs.existsSync(path.join(root, name)) && digest(fs.readFileSync(path.join(root, name))) === hash
        && (!name.endsWith('.png') || fs.existsSync(path.join(root, name + '.meta'))))) {
        console.log('[StartX data] Excel、卡面和图标已同步。'); return { ...cache.counts, changed: [] };
    }
    const config = Object.fromEntries(['balance', 'idea_pools'].map(name => [name === 'idea_pools' ? 'ideaPools' : name, json(path.join(source, name + '.json'))]));
    const data = catalogFromSheets(readWorkbook(workbook), config), render = await renderer(source), output = new Map();
    for (const [id, card] of Object.entries(data.cards)) {
        card.bodyColor = colors(id, card).body.slice(1); card.functionText = functionText(id, card, data);
        const face = await render.card(id, card);
        output.set('assets/content/faces/' + id + '.png', render.png(face));
        output.set('assets/content/icons/' + id + '.png', await render.icon(id, card));
        if (id === 'founder') output.set('assets/sample/art/founder-face.png', render.png(face));
        if (card.maxUses >= 0) for (let n = 0; n <= card.maxUses; n++) {
            output.set(`assets/content/patches/${id}-${n}.png`, render.png(await render.card(id, card, n), 1024, 244, [0, 0, 1024, 244]));
        }
        if (id === 'p3_account') for (let n = 0; n <= 50; n++) {
            output.set(`assets/content/patches/account-${n}.png`, render.png(await render.card(id, card, undefined, n), 300, 324, [0, 700, 300, 324]));
        }
    }
    for (const [id, pack] of Object.entries(data.packs)) {
        output.set('assets/content/packs/' + id + '.png', render.png(await render.pack(id, pack)));
        output.set('assets/content/pack-icons/' + id + '.png', await render.icon(id, null, true));
    }
    output.set('assets/content/packs/flash_pack.png', render.png(await render.pack('flash_pack', { name: '奖励礼包' })));
    const garage = data.packs.garage_pack || data.packs[data.packOrder[0]], countMax = Math.max(9, ...Object.values(data.packs).map(p => p.maxCards + 1));
    output.set('assets/content/ui/pack-back.png', render.png(await render.pack('garage_pack', garage, 0, true)));
    for (let n = 1; n <= countMax; n++) output.set(`assets/content/patches/pack-${n}.png`, render.png(await render.pack('garage_pack', garage, n), 210, 210, [790, 32, 210, 210]));
    output.set('assets/content/catalog.json', encode(data));
    output.set('assets/sample/data/founder.json', encode({ id: 'founder', name: data.cards.founder.name,
        description: data.cards.founder.flavor || '', salary: data.cards.founder.salary, capacity: data.cards.founder.capacity,
        usesLeft: data.cards.founder.maxUses ?? -1, faceSource: 'tools/render-cards.cjs', materialSource: 'Cocos FounderFoil' }));
    // Keep the complete source font so newly edited Chinese names also work in native UI labels.
    output.set('assets/sample/art/StartXSans.ttf', fs.readFileSync(path.join(source, 'fonts/SmileySans-Oblique.ttf')));
    const changed = [], directories = ['faces', 'icons', 'packs', 'pack-icons', 'patches'];
    for (const name of directories) {
        const file = 'assets/content/' + name + '.meta';
        if (!fs.existsSync(path.join(root, file))) output.set(file, encode({ ver: '1.2.0', importer: 'directory', imported: true, uuid: uuid(file.slice(0, -5)), files: [], subMetas: {}, userData: {} }));
    }
    for (const [file, buffer] of [...output]) if (file.endsWith('.png')) output.set(file + '.meta', imageMeta(root, file, buffer));
    for (const [file, buffer] of output) writeChanged(root, file, buffer, changed);
    for (const name of directories) {
        const dir = path.join(root, 'assets/content', name);
        for (const file of fs.readdirSync(dir)) if (/\.png(?:\.meta)?$/.test(file) && !output.has('assets/content/' + name + '/' + file)) {
            fs.unlinkSync(path.join(dir, file)); changed.push('assets/content/' + name + '/' + file);
        }
    }
    // Creator normalizes .meta files during import; that must not invalidate otherwise identical generated art.
    const outputs = Object.fromEntries([...output.keys()].filter(file => !file.endsWith('.meta')).map(file => [file, digest(fs.readFileSync(path.join(root, file)))]));
    const counts = { cards: Object.keys(data.cards).length, recipes: data.recipes.length, packs: data.packOrder.length, tasks: data.tasks.length };
    fs.mkdirSync(path.dirname(cachePath), { recursive: true }); fs.writeFileSync(cachePath, encode({ fingerprint, outputs, counts }));
    console.log(`[StartX data] 已同步 Excel：${counts.cards} 张卡牌、${counts.recipes} 条配方、${counts.packs} 种卡包、${counts.tasks} 项任务；更新 ${changed.length} 个文件。`);
    return { ...counts, changed };
}
module.exports = { syncContent };
if (require.main === module) syncContent({ force: process.argv.includes('--force') }).catch(error => { console.error('[StartX data]', error.message); process.exitCode = 1; });
