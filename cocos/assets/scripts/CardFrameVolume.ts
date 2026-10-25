import { Color, Graphics, Node, Quat, UITransform, Vec3 } from 'cc';

export const PACK_DEPTH_RATIO = .10;
const PACK_SEAL_RATIO = .22;

function packOutline(size: number) {
    const outline: Vec3[] = [], add = (x: number, y: number) => outline.push(new Vec3((x / 238 - .5) * size, (.5 - y / 238) * size));
    for (let i = 0; i <= 11; i++) add(16 + 206 * i / 11, i % 2 ? 0 : 7);
    for (const t of [.05, .15, .85, .95, 1]) add(238 - (t >= .15 && t <= .85 ? 8 : 16), 7 + 224 * t);
    for (let i = 0; i <= 11; i++) add(222 - 206 * i / 11, i % 2 ? 238 : 231);
    for (const t of [1, .95, .85, .15, .05]) add(t >= .15 && t <= .85 ? 8 : 16, 7 + 224 * t);
    outline.reverse();
    const points: Vec3[] = [];
    for (let i = 0; i < outline.length; i++) {
        const a = outline[i], b = outline[(i + 1) % outline.length];
        const segments = Math.max(1, Math.ceil(Vec3.distance(a, b) / (size / 24)));
        for (let step = 0; step < segments; step++) points.push(Vec3.lerp(new Vec3(), a, b, step / segments));
    }
    return points;
}

function packThickness(size: number, y: number) {
    return size * PACK_DEPTH_RATIO * (PACK_SEAL_RATIO + (1 - PACK_SEAL_RATIO) * Math.pow(Math.max(0, Math.cos(y / size * Math.PI)), 1.2));
}

/** One filled silhouette follows the same wrapper and thickness as the visible pack. */
export function paintPackShadow(g: Graphics, size: number, color: Color) {
    const points = packOutline(size);
    g.clear(); g.fillColor = color;
    for (let i = 0; i < points.length; i++) {
        const a = points[i], b = points[(i + 1) % points.length];
        const back = (b.y - a.y) * .64 + (b.x - a.x) * .38 > 0;
        const da = back ? packThickness(size, a.y) : 0, db = back ? packThickness(size, b.y) : 0;
        const x = a.x + da * .64, y = a.y - da * .38;
        if (i === 0) g.moveTo(x, y); else g.lineTo(x, y);
        g.lineTo(b.x + db * .64, b.y - db * .38);
    }
    g.close(); g.fill();
}

/** The card's existing rim extruded between its front and back planes. */
export class CardFrameVolume {
    readonly node: Node;
    private art: Graphics;
    private key = '';
    private rotation = new Quat();
    private sides = 0;
    private depth = 0;
    private color = '#141414';
    private pouch = false;
    constructor(parent: Node) {
        this.node = new Node('FrameThickness'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform).setContentSize(280, 280); this.art = this.node.addComponent(Graphics);
        this.node.setSiblingIndex(0);
    }
    paint(size: number, depth: number, pitch: number, yaw: number, frameColor: string, board = false) {
        const key = [size, depth, Math.round(pitch * 2), Math.round(yaw * 2), frameColor, board].join('|');
        if (key === this.key) return; this.key = key; this.depth = depth; this.color = frameColor; this.sides = 0; this.pouch = false;
        const solid = frameColor === 'rainbow' ? null : Color.fromHEX(new Color(), frameColor);
        const colorAt = (u: number, v: number) => {
            if (solid) return solid;
            const phase = (u * .55 + v * .30 + yaw / 360 * .45) * Math.PI * 2;
            const blend = .5 + .5 * Math.sin(phase), pink = .28 * (.5 + .5 * Math.cos(phase + 1.2));
            return new Color(Math.round((191 * (1 - blend) + 92 * blend) * (1 - pink) + 255 * pink),
                Math.round((112 * (1 - blend) + 240 * blend) * (1 - pink) + 143 * pink), Math.round(255 * (1 - pink) + 224 * pink));
        };
        const points: Vec3[] = [], half = size * .486, radius = size * .044;
        const corners = [[half - radius, half - radius], [-half + radius, half - radius], [-half + radius, -half + radius], [half - radius, -half + radius]];
        corners.forEach(([x, y], corner) => {
            for (let step = 0; step <= 5; step++) {
                const a = (corner * 90 + step * 18) * Math.PI / 180;
                points.push(new Vec3(x + Math.cos(a) * radius, y + Math.sin(a) * radius, 0));
            }
        });
        Quat.fromEuler(this.rotation, pitch, yaw, 0);
        const project = (p: Vec3, back: boolean) => {
            if (board) return new Vec3(p.x + (back ? depth * .40 : 0), p.y - (back ? depth : 0), 0);
            return Vec3.transformQuat(new Vec3(), new Vec3(p.x, p.y, (back ? -1 : 1) * depth / 2), this.rotation);
        };
        const front = points.map(p => project(p, false)), back = points.map(p => project(p, true)), g = this.art;
        this.node.getComponent(UITransform)!.setContentSize(size + depth * 2, size + depth * 2); g.clear();
        // The solid core sits beneath the crayon rim and closes the artwork's transparent margin.
        g.fillColor = colorAt(.5, .5); g.moveTo(front[0].x, front[0].y);
        for (const p of front.slice(1)) g.lineTo(p.x, p.y);
        g.close(); g.fill();
        for (let i = 0; i < points.length; i++) {
            const j = (i + 1) % points.length, a = points[i], b = points[j];
            const normal = new Vec3(b.y - a.y, a.x - b.x, 0).normalize();
            const rotated = Vec3.transformQuat(new Vec3(), normal, this.rotation);
            if (board ? normal.x * .40 - normal.y <= .001 : rotated.z <= .001) continue;
            this.sides++;
            const color = colorAt((a.x + b.x) / (2 * size) + .5, .5 - (a.y + b.y) / (2 * size));
            g.fillColor = color;
            g.moveTo(front[i].x, front[i].y); g.lineTo(back[i].x, back[i].y); g.lineTo(back[j].x, back[j].y); g.lineTo(front[j].x, front[j].y); g.close(); g.fill();
            g.lineWidth = Math.max(.6, size / 360); g.strokeColor = color;
            g.moveTo(front[i].x, front[i].y); g.lineTo(front[j].x, front[j].y); g.stroke();
        }
    }
    paintPack(size: number, pitch = 0, yaw = 0, board = true, purple = false) {
        const depth = size * PACK_DEPTH_RATIO;
        const key = ['pouch', size, Math.round(pitch * 2), Math.round(yaw * 2), board, purple].join('|');
        if (key === this.key) return;
        this.key = key; this.depth = depth; this.color = purple ? '#332044' : '#252629'; this.sides = 0; this.pouch = true;
        Quat.fromEuler(this.rotation, pitch, yaw, 0);
        const points = packOutline(size);
        const project = (p: Vec3, fraction: number) => {
            const d = packThickness(size, p.y) * fraction;
            return board ? new Vec3(p.x + d * .64, p.y - d * .38) : Vec3.transformQuat(new Vec3(), new Vec3(p.x, p.y, -d), this.rotation);
        };
        const front = points.map(p => project(p, 0)), back = points.map(p => project(p, 1)), g = this.art;
        this.node.getComponent(UITransform)!.setContentSize(size + depth * 2, size + depth * 2); g.clear();
        g.lineJoin = Graphics.LineJoin.MITER; g.lineCap = Graphics.LineCap.BUTT;
        for (let i = 0; i < points.length; i++) {
            const j = (i + 1) % points.length, a = points[i], b = points[j];
            const normal = new Vec3(b.y - a.y, a.x - b.x).normalize();
            const rotated = Vec3.transformQuat(new Vec3(), normal, this.rotation);
            if (board ? normal.x * .64 - normal.y * .38 <= .001 : rotated.z <= .001) continue;
            this.sides++;
            // A folded foil gusset follows the same tapered thickness as the body.
            for (let band = 0; band < 4; band++) {
                const u = band / 4, v = (band + 1) / 4;
                const p = project(a, u), q = project(a, v), r = project(b, v), s = project(b, u);
                const light = [1.06, 1.24, .78, .94][band] * (.83 + .17 * Math.abs(normal.x));
                const wrinkle = 1 + .07 * Math.sin((a.y + b.y) / size * 63);
                g.fillColor = new Color(Math.round((purple ? 53 : 42) * light * wrinkle), Math.round((purple ? 33 : 43) * light * wrinkle), Math.round((purple ? 70 : 46) * light * wrinkle));
                g.moveTo(p.x, p.y); g.lineTo(q.x, q.y); g.lineTo(r.x, r.y); g.lineTo(s.x, s.y); g.close(); g.fill();
            }
            g.lineWidth = size * .003; g.strokeColor = purple ? new Color(99, 75, 119) : new Color(92, 93, 97);
            g.moveTo(back[i].x, back[i].y); g.lineTo(back[j].x, back[j].y); g.stroke();
            const foldA = project(a, .5), foldB = project(b, .5);
            g.lineWidth = size * .002; g.strokeColor = new Color(15, 15, 19, 150);
            g.moveTo(foldA.x, foldA.y); g.lineTo(foldB.x, foldB.y); g.stroke();
            // Close the front edge beneath the existing printed white outline.
            g.lineWidth = size * .002; g.strokeColor = new Color(34, 34, 37);
            g.moveTo(front[i].x, front[i].y); g.lineTo(front[j].x, front[j].y); g.stroke();
        }
    }
    snapshot() { return { depth: this.depth, sides: this.sides, rainbow: this.color === 'rainbow', color: this.color,
        shape: this.pouch ? 'pouch' : 'card', ...(this.pouch ? { sealDepth: this.depth * PACK_SEAL_RATIO, middleDepth: this.depth } : {}) }; }
}
