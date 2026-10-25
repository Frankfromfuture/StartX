import { Color, Font, Graphics, Label, Node, UIOpacity, UITransform, Vec2, Vec3 } from 'cc';
import { viewShadowOffset } from './ViewShadow';

interface SpeechArea { left: number; right: number; top: number; bottom: number; scale: number; landscape?: boolean; fontSize?: number; }
type TailDirection = 'down' | 'left' | 'right';
const WELCOME = '来和我开启一场冒险吧～';
const MILESTONE = '恭喜我们又前进了一步！';

/** A screen-sized paper speech bubble anchored to the founder's card. */
export class FounderSpeech {
    readonly node: Node;
    private art: Graphics;
    private shadow: Node;
    private shadowArt: Graphics;
    private shadowShift = new Vec2();
    private shadowOrigin = new Vec3();
    private opacity: UIOpacity;
    private message: Label;
    private age = 0;
    private duration = 0;
    private queued = false;
    private shape = '';
    private text = '';
    private textLayout = '';
    private width = 0;
    private height = 0;
    private entrance = 0;
    private origin = new Vec3();
    private destination = new Vec3();
    private tailDirection: TailDirection = 'down';

    constructor(private parent: Node, font: Font, private projectWorld = (point: Vec3) => point) {
        this.node = new Node('FounderSpeech'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform);
        this.shadow = new Node('Shadow'); this.shadow.layer = parent.layer; this.node.addChild(this.shadow); this.shadow.addComponent(UITransform);
        this.shadowArt = this.shadow.addComponent(Graphics);
        const paper = new Node('Paper'); paper.layer = parent.layer; this.node.addChild(paper); paper.addComponent(UITransform);
        this.art = paper.addComponent(Graphics); this.opacity = this.node.addComponent(UIOpacity);
        const n = new Node('Message'); n.layer = parent.layer; this.node.addChild(n); n.addComponent(UITransform);
        this.message = n.addComponent(Label); this.message.font = font; this.message.fontSize = 18; this.message.lineHeight = 24;
        this.message.color = new Color(48, 42, 39); this.message.horizontalAlign = Label.HorizontalAlign.CENTER;
        this.message.verticalAlign = Label.VerticalAlign.CENTER;
        this.node.active = false;
    }

    welcome() { this.queued = false; this.present(WELCOME, 6.5); }
    celebrate() {
        if (this.text === WELCOME && this.age < this.duration) this.queued = true;
        else if (this.text !== MILESTONE || this.age >= this.duration) this.present(MILESTONE, 5);
    }
    private present(text: string, duration: number) {
        this.text = text; this.message.string = text; this.age = 0; this.duration = duration;
    }
    contains(point: Vec2) {
        if (!this.node.active) return false;
        const p = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(point.x, point.y));
        return p.x >= -this.width / 2 - (this.tailDirection === 'left' ? 25 : 4) &&
            p.x <= this.width / 2 + (this.tailDirection === 'right' ? 25 : 10) &&
            p.y >= -this.height / 2 - (this.tailDirection === 'down' ? 25 : 4) && p.y <= this.height / 2 + 4;
    }
    dismiss() { this.age = this.duration; this.queued = false; this.node.active = false; }
    private sizeText(maxWidth: number) {
        const key = [this.text, maxWidth].join('|'); if (key === this.textLayout) return;
        this.textLayout = key;
        const label = this.message, transform = label.node.getComponent(UITransform)!;
        label.overflow = Label.Overflow.NONE; label.enableWrapText = false; label.updateRenderData(true);
        this.width = Math.max(76, Math.min(maxWidth, Math.ceil(transform.width) + 28));
        label.overflow = Label.Overflow.RESIZE_HEIGHT; label.enableWrapText = true;
        transform.setContentSize(this.width - 28, 24); label.updateRenderData(true);
        this.height = Math.max(46, Math.ceil(transform.height) + 20);
        this.node.getComponent(UITransform)!.setContentSize(this.width, this.height);
    }

    tick(dt: number, founder: Node | undefined, visible: boolean, area: SpeechArea) {
        this.node.active = !!founder && visible && (this.age < this.duration || this.queued);
        if (!this.node.active || !founder) return;
        this.age += Math.min(dt, .1);
        if (this.age >= this.duration) {
            if (this.queued) { this.queued = false; this.present(MILESTONE, 5); }
            else { this.node.active = false; return; }
        }
        const root = this.parent.getComponent(UITransform)!, face = founder.getComponent(UITransform)!;
        const corners = [[-.5, -.5], [-.5, .5], [.5, -.5], [.5, .5]].map(([x, y]) =>
            root.convertToNodeSpaceAR(this.projectWorld(face.convertToWorldSpaceAR(new Vec3(x * face.width, y * face.height)))));
        const sx = corners.reduce((sum, p) => sum + p.x, 0) / corners.length, high = Math.max(...corners.map(p => p.y)), low = Math.min(...corners.map(p => p.y));
        const cardLeft = Math.min(...corners.map(p => p.x)), cardRight = Math.max(...corners.map(p => p.x));
        const s = area.fontSize !== undefined ? area.fontSize / 18 : area.scale * (area.landscape ? .75 : 1), gap = 24 * s;
        const rightSpace = area.right - cardRight - gap - 8 * s, leftSpace = cardLeft - area.left - gap - 8 * s;
        const beside = !!area.landscape && area.top - high < ((this.height || 46) + 32) * s && Math.max(rightSpace, leftSpace) > 120 * s;
        const maxWidth = Math.min(beside ? 260 : 340, (beside ? Math.max(rightSpace, leftSpace) : area.right - area.left) / s - 16);
        this.sizeText(area.landscape ? Math.floor(maxWidth / 8) * 8 : maxWidth);
        const { width, height } = this;
        const halfW = width * s / 2, halfH = height * s / 2;
        const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
        let x = clamp(sx, area.left + halfW + 8 * s, area.right - halfW - 8 * s);
        let y = clamp(high + halfH + gap,
            area.bottom + halfH + 26 * s, area.top - halfH - 8 * s);
        this.tailDirection = 'down';
        if (beside) {
            const right = rightSpace >= leftSpace;
            x = right ? cardRight + gap + halfW : cardLeft - gap - halfW;
            y = clamp((high + low) / 2, area.bottom + halfH + 8 * s, area.top - halfH - 8 * s);
            this.tailDirection = right ? 'left' : 'right';
        }
        const tailLimit = Math.max(0, (beside ? height / 2 - 22 : width / 2 - 36));
        const tailOffset = beside ? ((high + low) / 2 - y) / s * (this.tailDirection === 'left' ? -1 : 1) : (sx - x) / s;
        const tail = Math.round(clamp(tailOffset, -tailLimit, tailLimit) / 2) * 2;
        const key = [width, height, tail, this.tailDirection].join('|');
        if (key !== this.shape) {
            this.shape = key; this.paint(width, height, tail, this.tailDirection);
        }
        // Grow above the card, with only a small upward drift into the resting position.
        this.origin.set(x, y - 8 * s, 0);
        this.destination.set(x, y, 0); this.entrance = Math.min(1, this.age / .46);
        const travel = 1 - Math.pow(1 - this.entrance, 3), pop = .06 + .94 * travel;
        this.node.setPosition(this.origin.x + (x - this.origin.x) * travel, this.origin.y + (y - this.origin.y) * travel);
        this.node.setScale(s * pop, s * pop, 1);
        viewShadowOffset(this.node, this.shadowOrigin, 4.2, this.shadowShift);
        this.shadow.setPosition(this.shadowShift.x, this.shadowShift.y, 0);
        this.opacity.opacity = Math.round(255 * Math.min(1, this.age / .09, (this.duration - this.age) / .35));
    }

    private paint(width: number, height: number, tail: number, direction: TailDirection) {
        const sideways = direction !== 'down', shapeW = sideways ? height : width, shapeH = sideways ? width : height;
        let g = this.shadowArt;
        const l = -shapeW / 2, r = shapeW / 2, b = -shapeH / 2, t = shapeH / 2, radius = 14;
        let seed = 2166136261;
        for (const c of this.text + width + ':' + height) seed = Math.imul(seed ^ c.charCodeAt(0), 16777619);
        const random = () => { seed += 0x6d2b79f5; let n = Math.imul(seed ^ seed >>> 15, 1 | seed); n ^= n + Math.imul(n ^ n >>> 7, 61 | n); return ((n ^ n >>> 14) >>> 0) / 4294967296; };
        const points: Vec2[] = [new Vec2(l + radius, t)];
        const line = (x: number, y: number) => {
            const from = points[points.length - 1], count = Math.max(1, Math.ceil(Math.hypot(x - from.x, y - from.y) / 1.7));
            for (let i = 1; i <= count; i++) points.push(new Vec2(from.x + (x - from.x) * i / count, from.y + (y - from.y) * i / count));
        };
        const arc = (cx: number, cy: number, a: number) => {
            for (let i = 1; i <= 12; i++) { const angle = a - i * Math.PI / 24; points.push(new Vec2(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius)); }
        };
        line(r - radius, t); arc(r - radius, t - radius, Math.PI / 2);
        line(r, b + radius); arc(r - radius, b + radius, 0);
        const tailBase = sideways ? 8 : 12;
        line(tail + tailBase, b); line(tail + 1, b - 17); line(tail - tailBase, b);
        line(l + radius, b); arc(l + radius, b + radius, -Math.PI / 2);
        line(l, t - radius); arc(l + radius, t - radius, Math.PI);
        points.pop();
        if (sideways) for (const p of points) { const x = p.x, y = p.y; p.set(direction === 'left' ? y : -y, direction === 'left' ? -x : x); }
        const phase = random() * Math.PI * 2;
        const marks = points.map((p, i) => {
            const before = points[(i + points.length - 1) % points.length], after = points[(i + 1) % points.length];
            const length = Math.hypot(after.x - before.x, after.y - before.y) || 1;
            const nx = -(after.y - before.y) / length, ny = (after.x - before.x) / length;
            const wobble = Math.sin(i * .21 + phase) * .36 + (random() - .5) * .38;
            return { x: p.x + nx * wobble, y: p.y + ny * wobble, nx, ny, half: 3.2 * (.40 + random() * .20 + .05 * Math.sin(i * .37 + phase)) };
        });
        const edge = (sign: number) => marks.map(p => new Vec2(p.x + p.nx * p.half * sign, p.y + p.ny * p.half * sign));
        const polygon = (path: Vec2[], color: Color) => {
            g.fillColor = color; path.forEach((p, i) => i ? g.lineTo(p.x, p.y) : g.moveTo(p.x, p.y)); g.close(); g.fill();
        };
        // Keep the shadow's outline calm; wax texture belongs inside the rubbed area.
        const shadow = points.map((p, i) => {
            const spread = 2.1 + Math.sin(i * .07 + phase) * .12, normal = marks[i];
            return new Vec2(p.x + normal.nx * spread, p.y + normal.ny * spread);
        });
        const inShadow = (x: number, y: number) => {
            let inside = false;
            for (let i = 0, j = shadow.length - 1; i < shadow.length; j = i++) {
                const a = shadow[i], z = shadow[j];
                if ((a.y > y) !== (z.y > y) && x < (z.x - a.x) * (y - a.y) / (z.y - a.y) + a.x) inside = !inside;
            }
            return inside;
        };
        g.clear(); g.lineJoin = Graphics.LineJoin.ROUND;
        polygon(shadow, new Color(59, 56, 59, 96));
        // Broad translucent rubs and fine paper scratches, without a jagged perimeter.
        for (let pass = 0; pass < 2; pass++) {
            g.strokeColor = pass ? new Color(244, 236, 217, 34) : new Color(65, 61, 66, 26);
            g.lineWidth = pass ? .45 : 1.4;
            for (let i = 0; i < width * height / 44; i++) {
                const x = -width / 2 + random() * (width + 7), y = -height / 2 - 22 + random() * (height + 24), length = pass ? 2 + random() * 4 : 6 + random() * 7;
                if (inShadow(x, y) && inShadow(x + length, y + 1.5)) { g.moveTo(x, y); g.lineTo(x + length, y + 1.5); }
            }
            g.stroke();
        }
        g = this.art; g.clear(); g.lineJoin = Graphics.LineJoin.ROUND;
        polygon(edge(1), new Color(20, 20, 20));
        polygon(edge(-1), new Color(255, 248, 229));
        // The same uneven width, paper flecks and fine side strokes as the card rims.
        for (let pass = 0; pass < 3; pass++) {
            g.fillColor = new Color(255, 247, 227, 32 + pass * 28);
            for (const p of marks) {
                const across = (random() * 2 - 1) * p.half * .85;
                g.rect(p.x + p.nx * across + (random() - .5) * .8, p.y + p.ny * across + (random() - .5) * .8, .16 + random() * .44, .12 + random() * .32);
            }
            g.fill();
        }
        g.lineWidth = .3; g.strokeColor = new Color(20, 20, 20, 77);
        for (const sign of [-1, 1]) {
            marks.forEach((p, i) => { const d = sign * (p.half + random() * .38), x = p.x + p.nx * d, y = p.y + p.ny * d; if (i) g.lineTo(x, y); else g.moveTo(x, y); });
            g.close(); g.stroke();
        }
    }

    snapshot() { return { visible: this.node.active, text: this.text, queued: this.queued, age: this.age, width: this.width, height: this.height,
        entrance: this.entrance, tailDirection: this.tailDirection, shadow: { x: this.shadowShift.x, y: this.shadowShift.y },
        origin: { x: this.origin.x, y: this.origin.y }, destination: { x: this.destination.x, y: this.destination.y } }; }
}
