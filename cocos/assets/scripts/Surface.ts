import { _decorator, Color, Component, Graphics, UITransform } from 'cc';
const { ccclass, property, executeInEditMode, requireComponent } = _decorator;

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
    @property gridSpacing = 72;
    @property(Color) gridAlternate = new Color(237, 232, 218, 255);
    @property(Color) gridLine = new Color(210, 203, 186, 130);
    private gridZoom = 1;
    private gridX = 0;
    private gridY = 0;
    private edgeGaps: [number, number][] = [];

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
        if (this.fileTab) {
            // Brizo's 10px crown + 8px concave shoulders, rotated into a vertical tab.
            // Cubic quarter circles meet the straight edges with matching tangents.
            const left = -w / 2 + inset, right = w / 2 - inset, bottom = -h / 2 + inset, top = h / 2 - inset;
            const shoulder = w * .20, radius = w * .26, k = .55228475;
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
            if (this.lineWidth) {
                outline(); if (!this.openLeft) g.close();
                g.lineWidth = this.lineWidth; g.strokeColor = this.stroke; g.stroke();
            }
            return;
        } else if (this.openLeft) {
            const left = -w / 2, right = w / 2 - inset, bottom = -h / 2 + inset, top = h / 2 - inset, r = this.radius;
            g.roundRect(left - r, bottom, w + r - inset, h - this.lineWidth, r); g.fill();
            if (this.lineWidth) {
                g.lineWidth = this.lineWidth; g.strokeColor = this.stroke;
                g.moveTo(left, bottom); g.lineTo(right - r, bottom); g.quadraticCurveTo(right, bottom, right, bottom + r);
                let y = bottom + r;
                for (const [from, to] of this.edgeGaps.slice().sort((a, b) => a[0] - b[0])) {
                    const a = Math.max(y, Math.min(top - r, from)), b = Math.max(a, Math.min(top - r, to));
                    g.lineTo(right, a); g.moveTo(right, b); y = b;
                }
                g.lineTo(right, top - r); g.quadraticCurveTo(right, top, right - r, top); g.lineTo(left, top); g.stroke();
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
