import { Color, Graphics, Mask, Node, UITransform } from 'cc';

/** A static, soft circular opening in the board fog, moved with the founder. */
export class NightShiftOverlay {
    readonly node: Node;
    readonly innerRadius = 220;
    readonly outerRadius = 380;
    private light: Node;
    private art: Graphics;
    private key = '';
    private center = { x: 0, y: 0 };
    constructor(parent: Node) {
        this.node = new Node('NightShiftOverlay'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform);
        this.node.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
        this.light = new Node('FounderLight'); this.light.layer = parent.layer; this.node.addChild(this.light);
        this.light.addComponent(UITransform); this.art = this.light.addComponent(Graphics);
    }
    configure(size: number, pitch: number, color: Color) {
        this.node.getComponent(UITransform)!.setContentSize(size, size);
        this.light.setScale(1, 1 / pitch, 1);
        const key = [size, color.r, color.g, color.b, color.a].join('|');
        if (key === this.key) return; this.key = key;
        const g = this.art, segments = 96, bands = 96;
        g.clear();
        const ring = (inner: number, outer: number, opacity: number) => {
            if (!opacity) return;
            g.fillColor = new Color(color.r, color.g, color.b, opacity);
            for (let i = 0; i < segments; i++) {
                const a = i * Math.PI * 2 / segments, b = (i + 1) * Math.PI * 2 / segments;
                g.moveTo(Math.cos(a) * inner, Math.sin(a) * inner);
                g.lineTo(Math.cos(a) * outer, Math.sin(a) * outer);
                g.lineTo(Math.cos(b) * outer, Math.sin(b) * outer);
                g.lineTo(Math.cos(b) * inner, Math.sin(b) * inner); g.close();
            }
            g.fill();
        };
        ring(this.outerRadius, size * 2, color.a);
        for (let i = 0; i < bands; i++) {
            const t = (i + .5) / bands, step = (this.outerRadius - this.innerRadius) / bands;
            ring(this.innerRadius + i * step, this.innerRadius + (i + 1) * step, Math.round(color.a * t * t * (3 - 2 * t)));
        }
    }
    follow(x: number, y: number) { this.center = { x, y }; this.light.setPosition(x, y, 0); }
    snapshot() { return { enabled: this.node.active, center: this.center, innerRadius: this.innerRadius, outerRadius: this.outerRadius }; }
}
