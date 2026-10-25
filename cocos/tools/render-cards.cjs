const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage, GlobalFonts } = require('@napi-rs/canvas');
const INK = '#141414', PAPER = '#f7f2e8';
const palette = (body, accent) => ({ head: accent, body, ring: accent });
const PALETTES = {
    coral: palette('#f4b9aa', '#f69d88'),
    red: palette('#d75c5c', '#ea7878'),
    lavender: palette('#b09af6', '#9e87e8'),
    blue: palette('#667db6', '#7e91bf'),
    cream: palette('#f6f0db', '#f1e3ad'),
    blueGray: palette('#667081', '#99a0ab'),
    gold: palette('#f6da96', '#efc14f'),
    orange: palette('#e79651', '#f3a765'),
    brown: palette('#926746', '#a98263'),
    green: palette('#acda82', '#6b9249'),
    purple: palette('#b566b7', '#c682c8'),
};
const CARD_PALETTES = { facility: 'blueGray', employee: 'coral', customer: 'cream', resource: 'blue', product: 'orange', tool: 'brown', badge: 'brown', risk: 'red', rival: 'red', idea: 'lavender', department: 'coral', business_model: 'lavender', order: 'green', event: 'purple', receivable: 'gold', cash: 'gold' };
const rgb = color => color.replace('#', '').match(/../g).map(n => parseInt(n, 16));
function colors(id, card) {
    return PALETTES[id === 'founder' ? 'coral' : ['cash', 'p3_account', 'revenue'].includes(id) ? 'gold' : CARD_PALETTES[card.type] || 'cream'];
}
// Seed by card id so number patches and the full face share exactly the same pencil marks.
function cardRandom(id) {
    let seed = 2166136261;
    for (const char of id) seed = Math.imul(seed ^ char.charCodeAt(0), 16777619);
    return () => { seed += 0x6d2b79f5; let n = Math.imul(seed ^ seed >>> 15, 1 | seed); n ^= n + Math.imul(n ^ n >>> 7, 61 | n); return ((n ^ n >>> 14) >>> 0) / 4294967296; };
}
function crayonStroke(ctx, points, random, width, closed = false) {
    const phase = random() * Math.PI * 2;
    const marks = points.map(([x, y], i) => {
        const prev = points[closed ? (i + points.length - 1) % points.length : Math.max(0, i - 1)];
        const next = points[closed ? (i + 1) % points.length : Math.min(points.length - 1, i + 1)];
        const length = Math.hypot(next[0] - prev[0], next[1] - prev[1]) || 1;
        const nx = -(next[1] - prev[1]) / length, ny = (next[0] - prev[0]) / length;
        const wobble = Math.sin(i * .21 + phase) * .36 + (random() - .5) * .38;
        return { x: x + nx * wobble, y: y + ny * wobble, nx, ny, half: width * (.40 + random() * .20 + .05 * Math.sin(i * .37 + phase)) };
    });
    const edge = sign => marks.map(p => [p.x + p.nx * p.half * sign, p.y + p.ny * p.half * sign]);
    ctx.save();
    if (closed) {
        ctx.beginPath();
        for (const points of [edge(1), edge(-1)]) {
            points.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)); ctx.closePath();
        }
        ctx.fillStyle = INK; ctx.fill('evenodd'); ctx.clip('evenodd');
    } else {
        polygon(ctx, [...edge(1), ...edge(-1).reverse()], INK); ctx.clip();
    }
    // Broken, translucent flecks expose the paper grain inside the wax stroke.
    for (const p of marks) for (let i = 0; i < 4; i++) {
        const across = (random() * 2 - 1) * p.half;
        ctx.fillStyle = `rgba(255,247,227,${.10 + random() * .30})`;
        ctx.fillRect(p.x + p.nx * across + (random() - .5) * 1.8, p.y + p.ny * across + (random() - .5) * 1.8, .16 + random() * .44, .12 + random() * .32);
    }
    ctx.restore();
    ctx.save(); ctx.strokeStyle = INK; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    // Light side strokes leave an uneven edge without turning the outline into a zigzag.
    for (const sign of [-1, 1]) {
        ctx.beginPath(); marks.forEach((p, i) => {
            const offset = sign * (p.half + random() * .38);
            const x = p.x + p.nx * offset, y = p.y + p.ny * offset;
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        });
        if (closed) ctx.closePath();
        ctx.lineWidth = .30; ctx.globalAlpha = .30; ctx.stroke();
    }
    ctx.restore();
}
function crayonFrame(ctx, id) {
    const random = cardRandom(id), outline = [], radius = 6;
    const corners = [[170, 10, -Math.PI / 2], [170, 170, 0], [10, 170, Math.PI / 2], [10, 10, Math.PI]];
    for (let c = 0; c < corners.length; c++) {
        const [x, y, angle] = corners[c];
        for (let i = 0; i <= 7; i++) { const a = angle + i * Math.PI / 14; outline.push([x + Math.cos(a) * radius, y + Math.sin(a) * radius]); }
        const end = outline[outline.length - 1], next = corners[(c + 1) % corners.length];
        const start = [next[0] + Math.cos(next[2]) * radius, next[1] + Math.sin(next[2]) * radius];
        const steps = Math.ceil(Math.hypot(start[0] - end[0], start[1] - end[1]) / 1.6);
        for (let i = 1; i < steps; i++) outline.push([end[0] + (start[0] - end[0]) * i / steps, end[1] + (start[1] - end[1]) * i / steps]);
    }
    crayonStroke(ctx, outline, random, 4.4, true);
    crayonStroke(ctx, Array.from({ length: 109 }, (_, i) => [4.5 + i * 171 / 108, 40.5]), random, 3.15);
}
function functionText(id, card, data) {
    if (card.functionText) return card.functionText;
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
        if (def.type === 'badge') { ctx.drawImage(await art(id, def), 0, 0, 1024, 1024); return canvas; }
        ctx.scale(1024 / 180, 1024 / 180);
        ctx.save(); ctx.beginPath(); ctx.roundRect(3.5, 3.5, 173, 173, 6.5); ctx.clip();
        ctx.fillStyle = body; ctx.fillRect(0, 0, 180, 180);
        ctx.fillStyle = head; ctx.fillRect(0, 0, 180, 40.5);
        circle(ctx, 90, 105, 45.36, ring);
        ctx.restore();
        ctx.drawImage(await art(id, def), 90 - 49.68, 105 - 49.68, 99.36, 99.36);
        const titleColor = rgb(head).reduce((s, n, i) => s + n / 255 * [.2126, .7152, .0722][i], 0) < .48 ? PAPER : INK;
        label(ctx, def.type === 'business_model' ? '商业模式' + (def.name.endsWith('（临）') ? '（临）' : '') : def.name, 12, 23, uses >= 0 ? 133 : 156, 21, titleColor);
        if (uses >= 0) label(ctx, uses, 166, 23, 26, 21, titleColor, 'right');
        if (id === 'p3_account') badge(ctx, 'star', 28, 151, stored);
        else if (def.salary > 0) badge(ctx, 'cost', 28, 151, def.salary);
        else if (['tool', 'customer', 'product'].includes(def.type) && def.value > 0) badge(ctx, 'star', 28, 151, def.value);
        if (def.capacity > 0 && !['tool', 'product'].includes(def.type)) badge(ctx, 'gear', 150, 151, def.capacity);
        crayonFrame(ctx, id);
        return canvas;
    };
    const pack = async (id, def, count = 0, backOnly = false) => {
        const canvas = createCanvas(1024, 1024), ctx = canvas.getContext('2d'); ctx.scale(1024 / 238, 1024 / 238);
        const points = [], ts = [.05, .15, .85, .95, 1], inset = t => t >= .15 && t <= .85 ? 8 : 16;
        for (let i = 0; i <= 11; i++) points.push([16 + 206 * i / 11, i % 2 ? 0 : 7]);
        for (const t of ts) points.push([238 - inset(t), 7 + 224 * t]);
        for (let i = 0; i <= 11; i++) points.push([222 - 206 * i / 11, i % 2 ? 238 : 231]);
        for (const t of [...ts].reverse()) points.push([inset(t), 7 + 224 * t]);
        polygon(ctx, points, INK); ctx.save(); ctx.clip(); ctx.drawImage(texture, 0, 0, 238, 238);
        ctx.restore();
        polygon(ctx, [[16, 15], [104.72, 15], [52.36, 223], [6.4, 223]], '#ffffff12');
        polygon(ctx, [[123.76, 13], [152.32, 13], [99.96, 225], [71.4, 225]], '#ffffff0d');
        polygon(ctx, points); ctx.strokeStyle = '#f2f2f2'; ctx.lineWidth = 3; ctx.stroke();
        if (backOnly) return canvas;
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
