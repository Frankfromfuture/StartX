import { Color, Font, Graphics, Label, Node, UITransform } from 'cc';
import { MonthSettlement } from './GameModel';
import { crayonStroke, DIMMED_BACKGROUND_COLOR } from './Surface';

/** Screen-space month confirmation; its hand-drawn outline stays still between layout changes. */
export class MonthEndPanel {
    readonly node: Node;
    readonly panel: Node;
    readonly button: Node;
    private shade: Graphics;
    private outline: Graphics;
    private buttonOutline: Graphics;
    private title: Label;
    private message: Label;
    private buttonText: Label;
    private seed = Math.random() * 100;
    private key = '';
    constructor(parent: Node, font: Font) {
        const node = (name: string, owner: Node) => {
            const n = new Node(name); n.layer = parent.layer; owner.addChild(n); n.addComponent(UITransform); return n;
        };
        const label = (name: string, owner: Node) => {
            const n = node(name, owner), l = n.addComponent(Label); l.font = font; l.color = new Color(27, 25, 23);
            l.horizontalAlign = Label.HorizontalAlign.CENTER; l.verticalAlign = Label.VerticalAlign.CENTER;
            l.enableWrapText = false; return l;
        };
        this.node = node('MonthEndOverlay', parent); this.shade = this.node.addComponent(Graphics);
        this.panel = node('MonthEndPanel', this.node); this.outline = this.panel.addComponent(Graphics);
        this.title = label('Title', this.panel); this.message = label('Message', this.panel);
        this.button = node('Confirm', this.panel); this.buttonOutline = this.button.addComponent(Graphics);
        this.buttonText = label('Text', this.button); this.node.active = false;
    }
    private frame(g: Graphics, w: number, h: number, scale: number, seed: number) {
        const corners = [{ x: -w / 2, y: -h / 2 }, { x: w / 2, y: -h / 2 }, { x: w / 2, y: h / 2 }, { x: -w / 2, y: h / 2 }];
        const points: { x: number; y: number }[] = [];
        for (let edge = 0; edge < 4; edge++) {
            const a = corners[edge], b = corners[(edge + 1) % 4];
            for (let step = 0; step < 12; step++) {
                const t = step / 12, jitter = Math.sin(seed + edge * 7 + step * 2.7) * 1.3 * scale;
                points.push({ x: a.x + (b.x - a.x) * t + (edge % 2 ? jitter : 0), y: a.y + (b.y - a.y) * t + (edge % 2 ? 0 : jitter) });
            }
        }
        points.push(points[0]); g.clear(); g.fillColor = new Color(31, 29, 27, 35);
        g.roundRect(-w / 2 + 3 * scale, -h / 2 - 4 * scale, w, h, 3 * scale); g.fill();
        points.forEach((p, i) => i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)); g.close();
        g.fillColor = new Color(252, 248, 238); g.fill(); crayonStroke(g, points, new Color(28, 26, 24), 2.3 * scale, new Color(252, 248, 238));
    }
    render(phase: MonthSettlement['phase'] | null, month: number, width: number, height: number, scale: number) {
        this.node.active = phase !== null && phase !== 'paying';
        if (!this.node.active) { this.key = ''; return; }
        this.node.setSiblingIndex(this.node.parent!.children.length - 1);
        const key = [phase, month, width, height, scale].join(':'); if (key === this.key) return; this.key = key;
        const failed = phase === 'failed', w = Math.min(276 * scale, width - 32 * scale), h = (failed ? 166 : 142) * scale;
        this.node.getComponent(UITransform)!.setContentSize(width, height);
        this.panel.getComponent(UITransform)!.setContentSize(w, h);
        this.shade.clear(); this.shade.fillColor = DIMMED_BACKGROUND_COLOR; this.shade.rect(-width / 2, -height / 2, width, height); this.shade.fill();
        this.frame(this.outline, w, h, scale, this.seed);
        const place = (l: Label, text: string, y: number, font: number, boxWidth: number) => {
            l.string = text; l.fontSize = font * scale; l.lineHeight = font * 1.4 * scale;
            l.node.setPosition(0, y * scale); l.node.getComponent(UITransform)!.setContentSize(boxWidth, font * 1.8 * scale);
        };
        place(this.title, failed ? 'Game Over' : phase === 'ready' ? `开始第 ${month + 1} 月` : `第 ${month} 月结束`, failed ? 45 : 27, 20, w - 24 * scale);
        place(this.message, failed ? '创业失败，加油再来！' : '', 8, 13, w - 24 * scale);
        this.button.setPosition(0, (failed ? -43 : -30) * scale);
        const bw = Math.min(206 * scale, w - 36 * scale), bh = 38 * scale;
        this.button.getComponent(UITransform)!.setContentSize(bw, bh); this.frame(this.buttonOutline, bw, bh, scale, this.seed + 13);
        place(this.buttonText, phase === 'confirm' ? '发工资及付租金' : '确认', 0, 14, bw - 12 * scale);
    }
    snapshot() { return { visible: this.node.activeInHierarchy, title: this.title.string, message: this.message.string, button: this.buttonText.string }; }
}
