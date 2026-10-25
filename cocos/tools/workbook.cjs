const fs = require('node:fs');
const path = require('node:path');
const { unzipSync, strFromU8 } = require('fflate');
const { XMLParser } = require('fast-xml-parser');

const list = value => value == null ? [] : Array.isArray(value) ? value : [value];
const text = value => typeof value === 'object' && value !== null
    ? list(value.t).map(text).join('') + list(value.r).map(text).join('') + (value['#text'] ?? '') : String(value ?? '');

/** OOXML reader accepts namespace prefixes, shared/rich strings, inline strings and cached formulas. */
function readWorkbook(file) {
    const zip = unzipSync(fs.readFileSync(file)), parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@', removeNSPrefix: true, parseTagValue: false, trimValues: false });
    const xml = name => {
        if (!zip[name]) throw Error(`Excel 缺少文件：${name}`);
        return parser.parse(strFromU8(zip[name]));
    };
    const shared = zip['xl/sharedStrings.xml'] ? list(xml('xl/sharedStrings.xml').sst.si).map(text) : [];
    const relationships = Object.fromEntries(list(xml('xl/_rels/workbook.xml.rels').Relationships.Relationship).map(r => [r['@Id'], r['@Target']]));
    const sheets = {};
    for (const sheet of list(xml('xl/workbook.xml').workbook.sheets.sheet)) {
        const target = relationships[sheet['@id']], name = sheet['@name'];
        if (!target) throw Error(`Excel 工作表链接无效：${name}`);
        const location = target.startsWith('/') ? target.slice(1) : path.posix.normalize('xl/' + target);
        const rows = list(xml(location).worksheet.sheetData?.row).map(row => {
            const values = [];
            for (const cell of list(row.c)) {
                const column = String(cell['@r']).match(/^[A-Z]+/)?.[0];
                if (!column) throw Error(`Excel 单元格地址无效：${cell['@r']}`);
                const index = [...column].reduce((v, c) => v * 26 + c.charCodeAt(0) - 64, 0) - 1;
                if (cell['@t'] === 'e') throw Error(`${name}!${cell['@r']}：Excel 公式错误 ${cell.v}`);
                if (cell.f != null && cell.v == null) throw Error(`${name}!${cell['@r']}：请在 Excel 中重新计算公式并保存`);
                values[index] = cell['@t'] === 's' ? shared[Number(cell.v)] : cell['@t'] === 'inlineStr' ? text(cell.is) : text(cell.v);
            }
            return values;
        });
        const header = rows.shift()?.map(v => String(v).trim()) || [];
        if (header[0] !== 'id') throw Error(`Excel 工作表 ${name} 第一列必须为 id`);
        const seen = new Set();
        sheets[name] = rows.filter(row => String(row[0] ?? '').trim()).map(row => {
            const entry = Object.fromEntries(header.flatMap((key, i) => key ? [[key, String(row[i] ?? '').trim()]] : []));
            if (!/^[A-Za-z0-9_-]+$/.test(entry.id) || seen.has(entry.id)) throw Error(`${name} 表 id 重复或格式无效：${entry.id}`);
            seen.add(entry.id); return entry;
        });
    }
    for (const name of ['cards', 'recipes', 'packs', 'tasks']) if (!sheets[name]?.length) throw Error(`Excel 工作表 ${name} 为空或不存在`);
    return sheets;
}

function number(value, label, fallback = 0) {
    if (value === '' || value == null) return fallback;
    const n = Number(value);
    if (!Number.isFinite(n) || !Number.isInteger(n)) throw Error(`${label} 必须为整数：${value}`);
    return n;
}
const integer = (row, key, fallback = 0) => number(row[key], row.id + '.' + key, fallback);
const tags = value => String(value || '').split(',').map(s => s.trim()).filter(Boolean);
const truth = value => ['true', '1', 'yes'].includes(String(value || '').toLowerCase());

function io(row, input) {
    const prefix = input ? 'input' : 'output';
    if (row[prefix + '1']) return Array.from({ length: 5 }, (_, j) => j + 1).filter(j => row[prefix + j]).map(j => ({
        id: row[prefix + j], count: integer(row, prefix + j + 'Count', 1), ...(input ? { consume: truth(row[prefix + j + 'Consume']) } : {}),
    }));
    return String(row[input ? 'inputs' : 'outputs'] || '').split('|').filter(Boolean).map(item => {
        const [id, count, consume] = item.trim().split(':');
        return { id: id.trim(), count: number(count, row.id + '.' + prefix, 1), ...(input ? { consume: truth(consume) } : {}) };
    });
}

function catalogFromSheets(sheets, config) {
    const cards = {}, recipes = [], packs = {};
    for (const row of sheets.cards) {
        const card = { name: row.name || row.id, type: row.type || 'tool', workTags: tags(row.workTags) };
        for (const key of ['salary', 'capacity', 'spaceCapacity', 'value', 'cost']) card[key] = integer(row, key);
        for (const key of ['hp', 'attack', 'workRequired', 'funds', 'deadlineSeconds', 'firstDeadlineSeconds', 'expiryPenalty']) if (row[key]) card[key] = integer(row, key);
        if (row.maxUses) {
            const range = row.maxUses.match(/^(\d+)\s*-\s*(\d+)$/);
            if (range) { card.maxUsesMin = Number(range[1]); card.maxUsesMax = Number(range[2]); card.maxUses = card.maxUsesMax; }
            else card.maxUses = integer(row, 'maxUses');
            if (card.maxUses < 0 || (range && card.maxUsesMin > card.maxUsesMax)) throw Error(`${row.id}.maxUses 范围无效`);
        }
        for (const key of ['flavor', 'recipeId', 'businessModelId', 'unlocksRecipeId', 'functionText']) if (row[key]) card[key] = row[key];
        cards[row.id] = card;
    }
    for (const row of sheets.recipes) {
        const recipe = { id: row.id, name: row.name || row.id, worker_tags: tags(row.worker_tags), inputs: io(row, true), outputs: io(row, false) };
        for (const key of ['output_zone', 'packId', 'effect']) if (row[key]) recipe[key] = row[key];
        if (row.workRequired) recipe.workRequired = integer(row, 'workRequired');
        recipes.push(recipe);
        cards['bm_' + row.id] = { name: recipe.name, type: 'business_model', recipeId: row.id, salary: 0, capacity: 0, value: 1, cost: 0 };
    }
    for (const row of sheets.packs) {
        let slots;
        if (row.slot1Card1) slots = Array.from({ length: 5 }, (_, s) => Array.from({ length: 5 }, (_, o) => {
            const key = `slot${s + 1}Card${o + 1}`;
            return row[key] ? { id: row[key], w: integer(row, `slot${s + 1}Prob${o + 1}`) } : null;
        }).filter(Boolean)).filter(s => s.length);
        else slots = String(row.slots || '').split('|').filter(Boolean).map(s => s.split(',').filter(Boolean).map(v => {
            const [id, weight] = v.trim().split(':'); return { id: id.trim(), w: number(weight, row.id + '.weight') };
        }));
        packs[row.id] = { name: row.name || row.id, stage: integer(row, 'stage'), price: integer(row, 'price'), minCards: integer(row, 'minCards'), maxCards: integer(row, 'maxCards'), slots,
            requiredTasks: tags(row.requiredTasks), starterCards: tags(row.starterCards) };
    }
    const tasks = sheets.tasks.map(row => ({ id: row.id, section: row.section || '主任务', group: row.group || '其他', title: row.title || row.id,
        content: row.content || '', triggerType: row.triggerType || '', targetId: row.targetId || '', targetCount: Math.max(1, integer(row, 'targetCount', 1)), unlockPack: row.unlockPack || '', order: integer(row, 'order') })).sort((a, b) => a.order - b.order);
    const reference = (owner, entry) => {
        if (!cards[entry.id]) throw Error(`${owner} 引用了不存在的卡牌：${entry.id}`);
        if (entry.count != null && entry.count <= 0) throw Error(`${owner} 的卡牌数量必须大于 0`);
    };
    for (const r of recipes) {
        if (r.effect && !['deliver_order', 'accept_change', 'decline_change', 'collect_payment', 'resolve_referral'].includes(r.effect)) throw Error(`配方 ${r.id} 的 effect 无效：${r.effect}`);
        if (r.workRequired != null && r.workRequired < 0) throw Error(`配方 ${r.id} 的 workRequired 必须为非负数，0 表示沿用产出卡的工作量`);
        if (!r.inputs.length || (!r.outputs.length && r.effect !== 'decline_change')) throw Error(`配方 ${r.id} 必须填写输入和产出`);
        [...r.inputs, ...r.outputs].forEach(e => reference(r.id, e));
        if (r.packId && !packs[r.packId]) throw Error(`配方 ${r.id} 的卡包不存在：${r.packId}`);
        for (const o of r.outputs) if (!(cards[o.id].workRequired > 0)) throw Error(`配方 ${r.id} 的产出 ${o.id} 缺少 workRequired`);
        const label = entries => entries.map(e => `${cards[e.id].name}*${e.count}`).join('+');
        r.formula = label(r.inputs) + ' → ' + (r.outputs.length ? label(r.outputs) : '取消加单，合同保留');
    }
    for (const [id, pack] of Object.entries(packs)) {
        if (pack.minCards < 0 || pack.maxCards < pack.minCards) throw Error(`卡包 ${id} 数量范围无效`);
        for (const slot of pack.slots) for (const option of slot) { reference(id, option); if (option.w <= 0) throw Error(`卡包 ${id} 的抽取权重必须大于 0`); }
        pack.starterCards.forEach(card => reference(id, { id: card }));
        for (const task of pack.requiredTasks) if (!tasks.some(t => t.id === task)) throw Error(`卡包 ${id} 的任务不存在：${task}`);
    }
    for (const task of tasks) if (task.unlockPack && !packs[task.unlockPack]) throw Error(`任务 ${task.id} 解锁了不存在的卡包：${task.unlockPack}`);
    for (const id of ['founder', 'cash', 'p3_account']) if (!cards[id]) throw Error(`缺少游戏基础卡牌：${id}`);
    const stages = (sheets.stages || []).map(row => ({ id: row.id, name: row.name, requiredTasks: tags(row.requiredTasks), minMonth: integer(row, 'minMonth', 1), minRevenue: integer(row, 'minRevenue') }));
    for (const stage of stages) for (const task of stage.requiredTasks) if (!tasks.some(t => t.id === task)) throw Error(`阶段 ${stage.id} 的任务不存在：${task}`);
    const events = (sheets.events || []).map(row => ({ id: row.id, name: row.name, cardId: row.cardId, trigger: row.trigger,
        duration: integer(row, 'duration'), extendSeconds: integer(row, 'extendSeconds'), deferredCash: integer(row, 'deferredCash'), message: row.message }));
    for (const event of events) {
        reference(event.id, { id: event.cardId });
        if (!['accepted', 'delivered'].includes(event.trigger) || event.duration <= 0 || event.deferredCash < 0 || event.extendSeconds < 0) throw Error(`客户事件 ${event.id} 配置无效`);
    }
    for (const [id, card] of Object.entries(cards)) if (card.type === 'order' && (!(card.deadlineSeconds > 0) || !(card.firstDeadlineSeconds > 0) || !(card.expiryPenalty >= 0))) throw Error(`订单 ${id} 的时限或逾期扣款无效`);
    return { cards, recipes, packs, packOrder: Object.keys(packs), tasks, stages, events, ...config, source: 'data/startx_data.xlsx; tools/sync-content.cjs' };
}

module.exports = { readWorkbook, catalogFromSheets };
