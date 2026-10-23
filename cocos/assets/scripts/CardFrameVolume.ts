import { Color, Graphics, Node, Quat, UITransform, Vec3 } from 'cc';

/** The card's existing rim extruded between its front and back planes. */
export class CardFrameVolume {
    readonly node: Node;
    private art: Graphics;
    private key = '';
    private rotation = new Quat();
    private sides = 0;
    private depth = 0;
    private rainbow = false;
    constructor(parent: Node) {
        this.node = new Node('FrameThickness'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform).setContentSize(280, 280); this.art = this.node.addComponent(Graphics);
        this.node.setSiblingIndex(0);
    }
    paint(size: number, depth: number, pitch: number, yaw: number, rainbow: boolean, board = false) {
        const key = [size, depth, Math.round(pitch * 2), Math.round(yaw * 2), rainbow, board].join('|');
        if (key === this.key) return; this.key = key; this.depth = depth; this.rainbow = rainbow; this.sides = 0;
        const points: Vec3[] = [], half = size / 2, radius = size * .052;
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
        for (let i = 0; i < points.length; i++) {
            const j = (i + 1) % points.length, a = points[i], b = points[j];
            const normal = new Vec3(b.y - a.y, a.x - b.x, 0).normalize();
            const rotated = Vec3.transformQuat(new Vec3(), normal, this.rotation);
            if (board ? normal.x * .40 - normal.y <= .001 : rotated.z <= .001) continue;
            this.sides++;
            const light = .62 + .38 * Math.max(0, -rotated.x * .35 + rotated.y * .55 + rotated.z * .76);
            const u = (a.x + b.x) / (2 * size) + .5, v = .5 - (a.y + b.y) / (2 * size);
            const phase = (u * .55 + v * .30 + yaw / 360 * .45) * Math.PI * 2;
            const mix = .5 + .5 * Math.sin(phase);
            const rgb = rainbow ? [191 * (1 - mix) + 92 * mix, 112 * (1 - mix) + 240 * mix, 255] : [27, 25, 31];
            g.fillColor = new Color(Math.round(rgb[0] * light), Math.round(rgb[1] * light), Math.round(rgb[2] * light));
            g.moveTo(front[i].x, front[i].y); g.lineTo(back[i].x, back[i].y); g.lineTo(back[j].x, back[j].y); g.lineTo(front[j].x, front[j].y); g.close(); g.fill();
            // A narrow bevel catches light along the same rim, never across the artwork.
            g.lineWidth = Math.max(.6, size / 360); g.strokeColor = rainbow ? new Color(240, 251, 255, 110) : new Color(112, 114, 122, 85);
            g.moveTo(front[i].x, front[i].y); g.lineTo(front[j].x, front[j].y); g.stroke();
        }
    }
    snapshot() { return { depth: this.depth, sides: this.sides, rainbow: this.rainbow }; }
}
