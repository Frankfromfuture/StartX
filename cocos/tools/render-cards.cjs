const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage, GlobalFonts } = require('@napi-rs/canvas');
const INK = '#141414', PAPER = '#f7f2e8';
const HEADERS = { facility: '35383a', employee: 'a96f72', customer: '506f61', resource: '8d9290', product: 'c58a5c', tool: '536b7a', risk: 'd99a90', rival: '75383a', idea: '2a2622', department: 'c2b6d6', business_model: '4c3478' };
const rgb = color => color.replace('#', '').match(/../g).map(n => parseInt(n, 16));
const mix = (color, white) => '#' + rgb(color).map(n => Math.round(n + (255 - n) * white).toString(16).padStart(2, '0')).join('');
const darken = (color, amount) => '#' + rgb(color).map(n => Math.round(n * (1 - amount)).toString(16).padStart(2, '0')).join('');
function colors(id, card) {
    const head = '#' + ({ founder: 'ff9999', cash: 'c8910f', p3_account: '705515', revenue: 'ecd590' }[id] || HEADERS[card.type] || 'd8d2c4');
    const body = id === 'founder' ? '#ffe5e5' : id === 'p3_account' ? '#8a6a24' : card.type === 'business_model' ? '#6b4ca0' : mix(head, .28);
    const ring = id === 'founder' ? '#fff2f2' : id === 'p3_account' ? '#ad914c' : card.type === 'business_model' ? '#8f75bd' : mix(head, .48);
    return { head, body, ring };
}
function functionText(id, card, data) {
    const c = card.capacity || 0, salary = card.salary || 0, value = card.value || 0;
    if (id === 'p2_orderly_workstation') return `价值 $${value}、空间容量 +${card.spaceCapacity || 0}`;
    if (id === 'p3_account') return '账户余额 $0/50、点击取出最多 5 个现金';
    if (['employee', 'department'].includes(card.type)) return `产能 ${c}/${c}、工资 $${salary}`;
    if (card.type === 'rival') return `产能 ${c}、资金 ${card.funds ?? c * 3}/${card.funds ?? c * 3}`;
    if (['tool', 'customer', 'product'].includes(card.type)) return `价值 $${value}` + (card.cost > 0 ? `、成本 $${card.cost}` : '');
    if (card.type === 'resource') return card.maxUses >= 0 ? `次数 ${card.maxUses}/${card.maxUses}` : '无限次';
    if (card.type === 'facility') return card.spaceCapacity > 0 ? `空间容量 +${card.spaceCapacity}` : '';
    if (card.type === 'business_model') return data.recipes.find(r => r.id === card.recipeId)?.formula || '';
    return '';
}
function circle(ctx, x, y, r, fill) { ctx.fillStyle = fill; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); }
function polygon(ctx, points, fill) { ctx.beginPath(); points.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)); ctx.closePath(); if (fill) { ctx.fillStyle = fill; ctx.fill(); } }
function label(ctx, value, x, y, width, size, color, align = 'left') {
    ctx.save(); ctx.font = `${size}px StartX`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = 'alphabetic';
    const m = ctx.measureText(String(value)), fit = Math.min(1, width / Math.max(m.width, 1));
    ctx.translate(x, y); ctx.scale(fit, 1);
    const baseline = (m.actualBoundingBoxAscent - m.actualBoundingBoxDescent) / 2;
    ctx.fillText(String(value), 0, baseline); ctx.fillText(String(value), .4, baseline); ctx.restore();
}

async function renderer(source) {
    if (!GlobalFonts.registerFromPath(path.join(source, 'fonts/SmileySans-Oblique.ttf'), 'StartX')) throw Error('无法加载随项目提供的中文字体');
    const images = new Map();
    // Local bytes also work inside Creator's build sandbox, which omits SharedArrayBuffer.
    const image = async file => { if (!images.has(file)) images.set(file, await loadImage(fs.readFileSync(file))); return images.get(file); };
    const artPath = (kind, id) => ['.png', '.svg'].map(ext => path.join(source, 'art', kind, id + ext)).find(file => fs.existsSync(file));
    const badges = Object.fromEntries(await Promise.all(['cost', 'star', 'gear'].map(async n => [n, await image(path.join(source, 'art/ui', n + '.svg'))])));
    const texture = await image(path.join(source, 'art/packtexture.png'));
    const art = async (id, card, pack = false) => {
        const file = artPath(pack ? 'packs' : 'cards', card?.type === 'business_model' ? 'business_model' : id);
        if (!file) throw Error(`缺少${pack ? '卡包' : '卡牌'}插画：data/art/${pack ? 'packs' : 'cards'}/${id}.png 或 .svg`);
        return image(file);
    };
    const badge = (ctx, name, x, y, value) => { ctx.drawImage(badges[name], x - 18, y - 18, 36, 36); label(ctx, value, x, y, 32, 17, '#ffffff', 'center'); };
    const card = async (id, def, uses = def.maxUses ?? -1, stored = 0) => {
        const canvas = createCanvas(1024, 1024), ctx = canvas.getContext('2d'), { head, body, ring } = colors(id, def);
        ctx.scale(1024 / 180, 1024 / 180);
        ctx.fillStyle = INK; ctx.beginPath(); ctx.roundRect(0, 0, 180, 180, 9); ctx.fill();
        ctx.fillStyle = body; ctx.fillRect(8, 8, 164, 164);
        ctx.fillStyle = mix(body, .3); ctx.fillRect(12.05, 8, 155.9, 4); ctx.fillRect(8, 12.05, 4, 155.9);
        ctx.fillStyle = darken(body, .22); ctx.fillRect(12.05, 168, 155.9, 4); ctx.fillRect(168, 12.05, 4, 155.9);
        ctx.fillStyle = head; ctx.fillRect(8, 8, 164, 30); ctx.fillStyle = INK; ctx.fillRect(8, 38, 164, 5);
        circle(ctx, 90, 105, 45.36, ring);
        ctx.drawImage(await art(id, def), 90 - 49.68, 105 - 49.68, 99.36, 99.36);
        const titleColor = rgb(head).reduce((s, n, i) => s + n / 255 * [.2126, .7152, .0722][i], 0) < .48 ? PAPER : INK;
        label(ctx, def.type === 'business_model' ? '商业模式' : def.name, 12, 23, uses >= 0 ? 133 : 156, 21, titleColor);
        if (uses >= 0) label(ctx, uses, 166, 23, 26, 21, titleColor, 'right');
        if (id === 'p3_account') badge(ctx, 'star', 28, 151, stored);
        else if (def.salary > 0) badge(ctx, 'cost', 28, 151, def.salary);
        else if (['tool', 'customer', 'product'].includes(def.type) && def.value > 0) badge(ctx, 'star', 28, 151, def.value);
        if (def.capacity > 0 && !['tool', 'product'].includes(def.type)) badge(ctx, 'gear', 150, 151, def.capacity);
        if (id === 'cash') {
            const gloss = ctx.createLinearGradient(8, 43, 172, 172); gloss.addColorStop(0, '#f2d8786b'); gloss.addColorStop(1, '#80520870');
            ctx.fillStyle = gloss; ctx.fillRect(8, 43, 164, 129);
            const shine = ctx.createLinearGradient(0, 43, 0, 82); shine.addColorStop(0, '#ffffff66'); shine.addColorStop(1, '#ffffff00');
            ctx.fillStyle = shine; ctx.fillRect(8, 43, 164, 39);
        }
        return canvas;
    };
    const pack = async (id, def, count = 0) => {
        const canvas = createCanvas(1024, 1024), ctx = canvas.getContext('2d'); ctx.scale(1024 / 238, 1024 / 238);
        const points = [], ts = [.05, .15, .85, .95, 1], inset = t => t >= .15 && t <= .85 ? 8 : 16;
        for (let i = 0; i <= 11; i++) points.push([16 + 206 * i / 11, i % 2 ? 0 : 7]);
        for (const t of ts) points.push([238 - inset(t), 7 + 224 * t]);
        for (let i = 0; i <= 11; i++) points.push([222 - 206 * i / 11, i % 2 ? 238 : 231]);
        for (const t of [...ts].reverse()) points.push([inset(t), 7 + 224 * t]);
        polygon(ctx, points, INK); ctx.save(); ctx.clip(); ctx.drawImage(texture, 0, 0, 238, 238); ctx.restore();
        polygon(ctx, [[16, 15], [104.72, 15], [52.36, 223], [6.4, 223]], '#ffffff12');
        polygon(ctx, [[123.76, 13], [152.32, 13], [99.96, 225], [71.4, 225]], '#ffffff0d');
        polygon(ctx, points); ctx.strokeStyle = '#f2f2f2'; ctx.lineWidth = 3; ctx.stroke();
        ctx.drawImage(await art(id, null, true), (238 - 132.48) / 2, 99 - 132.48 / 2, 132.48, 132.48);
        ctx.strokeStyle = '#ffffff59'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(34, 174); ctx.lineTo(204, 174); ctx.stroke();
        // The font's alphabetic baseline is retained for the foil wrapper's caption.
        const name = def.name.endsWith('包') ? def.name : def.name + '包'; label(ctx, name, 119, 199, 206, 26, '#f2f2f2', 'center');
        if (count) { circle(ctx, 208, 30, 19, INK); ctx.strokeStyle = '#f2f2f2'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(208, 30, 19, 0, Math.PI * 2); ctx.stroke(); label(ctx, '×' + count, 208, 30, 38, 22, '#f2f2f2', 'center'); }
        return canvas;
    };
    const png = (canvas, width = 512, height = width, crop) => {
        const out = createCanvas(width, height), ctx = out.getContext('2d');
        if (crop) ctx.drawImage(canvas, ...crop, 0, 0, width, height); else ctx.drawImage(canvas, 0, 0, width, height);
        return out.toBuffer('image/png');
    };
    const icon = async (id, def, isPack = false) => {
        const src = await art(id, def, isPack), ratio = 256 / Math.max(src.width, src.height), canvas = createCanvas(Math.max(1, Math.round(src.width * ratio)), Math.max(1, Math.round(src.height * ratio)));
        canvas.getContext('2d').drawImage(src, 0, 0, canvas.width, canvas.height); return canvas.toBuffer('image/png');
    };
    return { card, pack, png, icon };
}

module.exports = { renderer, colors, functionText };
