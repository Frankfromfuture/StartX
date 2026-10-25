import { _decorator, Color, Component, Graphics, UITransform } from 'cc';
const { ccclass, property, executeInEditMode, requireComponent } = _decorator;
export const FILE_TAB_RADIUS = .26;
export const DIMMED_BACKGROUND_COLOR = new Color(16, 19, 25, 190);

type StrokePoint = { x: number; y: number };
/** Stable wax marks: irregular pressure and fine overlapping strokes, without animated noise. */
export function crayonStroke(g: Graphics, path: StrokePoint[], color: Color, width: number) {
    if (path.length < 2) return;
    const points: StrokePoint[] = [path[0]];
    for (let i = 1; i < path.length; i++) {
        const a = path[i - 1], b = path[i], count = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y) / Math.max(1.5, width)));
        for (let j = 1; j <= count; j++) points.push({ x: a.x + (b.x - a.x) * j / count, y: a.y + (b.y - a.y) * j / count });
    }
    g.lineCap = Graphics.LineCap.ROUND; g.lineJoin = Graphics.LineJoin.ROUND;
    for (let pass = 0; pass < 3; pass++) {
        g.lineWidth = width * (pass ? .30 : .78);
        g.strokeColor = new Color(color.r, color.g, color.b, Math.round(color.a * (pass ? .62 : .95)));
        points.forEach((p, i) => {
            const a = points[Math.max(0, i - 1)], b = points[Math.min(points.length - 1, i + 1)], length = Math.hypot(b.x - a.x, b.y - a.y) || 1;
            const rub = width * (Math.sin(i * 1.73 + pass * 2.1) * .12 + Math.sin(i * .27 + pass) * .15 + (pass - 1) * .22);
            const x = p.x - (b.y - a.y) / length * rub, y = p.y + (b.x - a.x) / length * rub;
            if (i) g.lineTo(x, y); else g.moveTo(x, y);
        });
        g.stroke();
    }
}

/** Editable rounded panel. Geometry follows its UITransform in editor and runtime. */
@ccclass('Surface')
@executeInEditMode
@requireComponent(Graphics)
export class Surface extends Component {
    @property(Color) fill = new Color(250, 247, 239, 255);
    @property(Color) stroke = new Color(53, 59, 54, 255);
    @property radius = 20;
    @property lineWidth = 0;
    @property dots = false;
    @property dotSpacing = 36;
    @property dotRadius = 1.2;
    @property grid = false;
    @property fileTab = false;
    @property openLeft = false;
    @property crayon = false;
    @property gridSpacing = 72;
    @property(Color) gridAlternate = new Color(237, 232, 218, 255);
    @property(Color) gridLine = new Color(210, 203, 186, 130);
    private gridZoom = 1;
    private gridX = 0;
    private gridY = 0;
    private edgeGaps: [number, number][] | null = null;

    setEdgeGaps(gaps: [number, number][]) { this.edgeGaps = gaps; this.paint(); }

    setGridTransform(zoom: number, x: number, y: number) {
        this.gridZoom = zoom; this.gridX = x; this.gridY = y; this.paint();
    }

    onLoad() { this.paint(); }
    onEnable() { this.node.on('size-changed', this.paint, this); this.paint(); }
    onDisable() { this.node.off('size-changed', this.paint, this); }
    onValidate() { this.paint(); }

    paint() {
        const t = this.getComponent(UITransform);
        const g = this.getComponent(Graphics);
        if (!t || !g) return;
        g.clear();
        const w = t.width, h = t.height, inset = this.lineWidth / 2;
        g.fillColor = this.fill;
        if (this.crayon && this.lineWidth) { this.paintCrayon(g, w, h); return; }
        if (this.fileTab) {
            // Brizo's 10px crown + 8px concave shoulders, rotated into a vertical tab.
            // Cubic quarter circles meet the straight edges with matching tangents.
            const left = -w / 2 + inset, right = w / 2 - inset, bottom = -h / 2 + inset, top = h / 2 - inset;
            const shoulder = w * .20, radius = w * FILE_TAB_RADIUS, k = .55228475;
            const outline = () => {
            g.moveTo(left, top);
            g.bezierCurveTo(left, top - shoulder * k, left + shoulder * (1 - k), top - shoulder, left + shoulder, top - shoulder);
            g.lineTo(right - radius, top - shoulder);
            g.bezierCurveTo(right - radius * (1 - k), top - shoulder, right, top - shoulder - radius * (1 - k), right, top - shoulder - radius);
            g.lineTo(right, bottom + shoulder + radius);
            g.bezierCurveTo(right, bottom + shoulder + radius * (1 - k), right - radius * (1 - k), bottom + shoulder, right - radius, bottom + shoulder);
            g.lineTo(left + shoulder, bottom + shoulder);
            g.bezierCurveTo(left + shoulder * (1 - k), bottom + shoulder, left, bottom + shoulder * k, left, bottom);
            };
            outline(); g.close(); g.fill();
            if (this.openLeft && this.lineWidth) {
                // Cover the shared seam, including any inactive tab border underneath it.
                g.rect(left - inset, bottom, this.lineWidth, top - bottom); g.fill();
            }
            if (this.lineWidth) {
                outline(); if (!this.openLeft) g.close();
                g.lineWidth = this.lineWidth; g.strokeColor = this.stroke; g.stroke();
            }
            return;
        } else if (this.openLeft || this.edgeGaps !== null) {
            const left = -w / 2 + (this.openLeft ? 0 : inset), right = w / 2 - inset, bottom = -h / 2 + inset, top = h / 2 - inset;
            const r = Math.min(this.radius, (right - left) / 2, (top - bottom) / 2), k = .55228475;
            g.roundRect(left - r, bottom, right - left + r, top - bottom, r); g.fill();
            if (this.lineWidth) {
                g.lineWidth = this.lineWidth; g.strokeColor = this.stroke;
                g.moveTo(left, bottom); g.lineTo(right - r, bottom);
                g.bezierCurveTo(right - r * (1 - k), bottom, right, bottom + r * (1 - k), right, bottom + r);
                let y = bottom + r;
                for (const [from, to] of (this.edgeGaps || []).slice().sort((a, b) => a[0] - b[0])) {
                    const a = Math.max(y, Math.min(top - r, from)), b = Math.max(a, Math.min(top - r, to));
                    g.lineTo(right, a); g.moveTo(right, b); y = b;
                }
                g.lineTo(right, top - r);
                g.bezierCurveTo(right, top - r * (1 - k), right - r * (1 - k), top, right - r, top);
                g.lineTo(left, top); if (!this.openLeft) g.lineTo(left, bottom); g.stroke();
            }
            return;
        } else g.roundRect(-w / 2 + inset, -h / 2 + inset, w - this.lineWidth, h - this.lineWidth, this.radius);
        g.fill();
        if (this.lineWidth) { g.lineWidth = this.lineWidth; g.strokeColor = this.stroke; g.stroke(); }
        if (this.grid) this.paintGrid(g, w, h);
        if (this.dots) {
            g.fillColor = new Color(139, 137, 117, 40);
            const step = Math.max(4, this.dotSpacing * this.gridZoom);
            const wrap = (v: number) => ((v % step) + step) % step;
            const startX = -w / 2 + wrap(this.gridX + w / 2);
            const startY = -h / 2 + wrap(this.gridY + h / 2);
            for (let x = startX; x <= w / 2; x += step)
                for (let y = startY; y <= h / 2; y += step) { g.circle(x, y, this.dotRadius * this.gridZoom); g.fill(); }
        }
    }

    private paintCrayon(g: Graphics, w: number, h: number) {
        const inset = this.lineWidth, left = -w / 2 + inset, right = w / 2 - inset, bottom = -h / 2 + inset, top = h / 2 - inset;
        const points: StrokePoint[] = [], step = Math.max(1.5, this.lineWidth);
        const move = (x: number, y: number) => points.push({ x, y });
        const line = (x: number, y: number) => {
            const a = points[points.length - 1], count = Math.max(1, Math.ceil(Math.hypot(x - a.x, y - a.y) / step));
            for (let i = 1; i <= count; i++) move(a.x + (x - a.x) * i / count, a.y + (y - a.y) * i / count);
        };
        const curve = (x1: number, y1: number, x2: number, y2: number, x: number, y: number) => {
            const a = points[points.length - 1];
            for (let i = 1; i <= 12; i++) { const t = i / 12, u = 1 - t; move(u ** 3 * a.x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x, u ** 3 * a.y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y); }
        };
        const k = .55228475;
        if (this.fileTab) {
            const shoulder = w * .20, radius = w * FILE_TAB_RADIUS;
            move(left, top); curve(left, top - shoulder * k, left + shoulder * (1 - k), top - shoulder, left + shoulder, top - shoulder);
            line(right - radius, top - shoulder); curve(right - radius * (1 - k), top - shoulder, right, top - shoulder - radius * (1 - k), right, top - shoulder - radius);
            line(right, bottom + shoulder + radius); curve(right, bottom + shoulder + radius * (1 - k), right - radius * (1 - k), bottom + shoulder, right - radius, bottom + shoulder);
            line(left + shoulder, bottom + shoulder); curve(left + shoulder * (1 - k), bottom + shoulder, left, bottom + shoulder * k, left, bottom);
        } else {
            const r = Math.min(this.radius, (right - left) / 2, (top - bottom) / 2);
            move(left, top - r); curve(left, top - r * (1 - k), left + r * (1 - k), top, left + r, top);
            line(right - r, top); curve(right - r * (1 - k), top, right, top - r * (1 - k), right, top - r);
            line(right, bottom + r); curve(right, bottom + r * (1 - k), right - r * (1 - k), bottom, right - r, bottom);
            line(left + r, bottom); curve(left + r * (1 - k), bottom, left, bottom + r * (1 - k), left, bottom + r);
        }
        line(points[0].x, points[0].y);
        points.forEach((p, i) => i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)); g.close(); g.fill();
        if (this.fileTab && this.openLeft) { g.rect(left - inset, bottom, inset * 2, top - bottom); g.fill(); }
        let stroke: StrokePoint[] = [points[0]];
        for (let i = 1; i < points.length; i++) {
            const a = points[i - 1], b = points[i], y = (a.y + b.y) / 2;
            const gap = this.openLeft && Math.abs(a.x - left) < .01 && Math.abs(b.x - left) < .01 ||
                Math.abs(a.x - right) < .01 && Math.abs(b.x - right) < .01 && this.edgeGaps?.some(([from, to]) => y > from && y < to);
            if (gap) { crayonStroke(g, stroke, this.stroke, this.lineWidth); stroke = [b]; } else stroke.push(b);
        }
        crayonStroke(g, stroke, this.stroke, this.lineWidth);
    }

    private paintGrid(g: Graphics, w: number, h: number) {
        const step = Math.max(8, this.gridSpacing * this.gridZoom);
        const stepY = step;
        const left = -w / 2, bottom = -h / 2;
        const firstCol = Math.floor((left - this.gridX) / step);
        const firstRow = Math.floor((bottom - this.gridY) / stepY);
        const startX = this.gridX + firstCol * step;
        const startY = this.gridY + firstRow * stepY;
        g.fillColor = this.gridAlternate;
        // World cell indices preserve the light/dark order across negative coordinates.
        for (let x = startX, col = firstCol; x < w / 2; x += step, col++) {
            for (let y = startY, row = firstRow; y < h / 2; y += stepY, row++) {
                if ((col + row) % 2 === 0) continue;
                const x0 = Math.max(left, x), y0 = Math.max(bottom, y);
                g.rect(x0, y0, Math.min(w / 2, x + step) - x0, Math.min(h / 2, y + stepY) - y0);
                g.fill();
            }
        }
        g.strokeColor = this.gridLine;
        g.lineWidth = Math.max(1, this.gridZoom * 4);
        for (let x = startX + step; x < w / 2; x += step) { g.moveTo(x, bottom); g.lineTo(x, h / 2); }
        for (let y = startY + stepY; y < h / 2; y += stepY) { g.moveTo(left, y); g.lineTo(w / 2, y); }
        g.stroke();
    }
}
