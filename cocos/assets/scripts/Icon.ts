import { _decorator, Component, Graphics, Color } from 'cc';
const { ccclass, property } = _decorator;
/** Resolution-independent HUD icons, so every platform displays the same controls. */
@ccclass('Icon')
export class Icon extends Component {
    @property kind = 'info';
    onLoad() { this.paint(); }
    paint() {
        const g = (this.getComponent(Graphics) || this.addComponent(Graphics))!; g.clear(); g.lineWidth = 3;
        if (['Pause', 'Resume', 'Recycle', 'PackStack', 'SupplyUpstream', 'SupplyDownstream', 'SupplyNode'].includes(this.kind)) { this.crayon(g); return; }
        g.strokeColor = new Color(55, 75, 59); g.fillColor = g.strokeColor;
        const line = (x: number, y: number, a: number, b: number) => { g.moveTo(x, y); g.lineTo(a, b); g.stroke(); };
        const box = (x: number, y: number, w: number, h: number) => { g.roundRect(x, y, w, h, 3); g.stroke(); };
        switch (this.kind) {
            case 'ZoomOut': case 'ZoomIn': line(-13, 0, 13, 0); if (this.kind === 'ZoomIn') line(0, -13, 0, 13); break;
            case 'Reset': g.arc(0, 0, 15, .5, 5.5, true); g.stroke(); line(14, 9, 15, -2); line(15, -2, 4, 1); break;
            case 'Book': box(-19, -15, 38, 31); line(0, -15, 0, 16); line(-14, 8, -5, 8); line(5, 8, 14, 8); line(-14, 1, -5, 1); line(5, 1, 14, 1); break;
            case 'Pack': box(-17, -17, 31, 37); box(-9, -23, 31, 37); line(-2, -3, 15, -3); line(6, -11, 6, 5); break;
            case 'Close': line(-9, -9, 9, 9); line(-9, 9, 9, -9); break;
            case 'Prev': line(7, -10, -5, 0); line(-5, 0, 7, 10); break;
            case 'Next': line(-7, -10, 5, 0); line(5, 0, -7, 10); break;
            default: g.circle(0, 0, 16); g.stroke(); g.circle(0, 8, 1.8); g.fill(); line(0, 1, 0, -10);
        }
    }
    private crayon(g: Graphics) {
        g.lineJoin = Graphics.LineJoin.ROUND; g.lineCap = Graphics.LineCap.ROUND;
        const ink = new Color(28, 28, 25), paper = new Color(249, 243, 224);
        const stroke = (points: number[][], closed = false, width = 3.7) => {
            const path = closed ? points.concat([points[0]]) : points;
            for (let pass = 0; pass < 2; pass++) {
                g.lineWidth = pass ? 1.1 : width; g.strokeColor = pass ? new Color(28, 28, 25, 100) : ink;
                path.forEach(([x, y], i) => {
                    if (!i) { g.moveTo(x, y); return; }
                    const [a, b] = path[i - 1], length = Math.hypot(x - a, y - b) || 1, count = Math.ceil(length / 3);
                    for (let j = 1; j <= count; j++) {
                        const t = j / count, wobble = j === count ? 0 : Math.sin(i * 8.3 + j * 2.7 + pass) * .43;
                        g.lineTo(a + (x - a) * t - (y - b) / length * wobble + pass * .4,
                            b + (y - b) * t + (x - a) / length * wobble - pass * .35);
                    }
                }); g.stroke();
            }
        };
        const polygon = (points: number[][], color = paper) => {
            g.fillColor = color; g.moveTo(points[0][0], points[0][1]); points.slice(1).forEach(([x, y]) => g.lineTo(x, y));
            g.close(); g.fill(); stroke(points, true);
        };
        if (this.kind === 'Pause') {
            for (const x of [-15, 5]) polygon([[x, -22], [x + 10, -22], [x + 10, 22], [x, 22]], new Color(238, 193, 79));
        } else if (this.kind === 'Resume') {
            polygon([[-14, -23], [22, 0], [-14, 23]], new Color(174, 192, 157));
        } else if (this.kind === 'PackStack') {
            polygon([[-25, 19], [-20, 22], [-15, 19], [-10, 22], [-5, 19], [1, 22], [10, 18], [9, -18], [-24, -19]], new Color(126, 145, 191));
            polygon([[-14, 16], [-8, 19], [-2, 16], [4, 19], [10, 16], [16, 19], [23, 16], [24, -22],
                [18, -19], [12, -22], [6, -19], [0, -22], [-6, -19], [-13, -22]], new Color(91, 65, 119));
            polygon([[4, 10], [7, 3], [15, 2], [9, -3], [10, -11], [4, -7], [-3, -11], [-2, -3], [-8, 2], [0, 3]], new Color(238, 193, 79));
        } else if (this.kind === 'Recycle') {
            for (let k = 0; k < 3; k++) {
                const start = (k * 120 + 8) * Math.PI / 180, end = start + 82 * Math.PI / 180;
                const at = (a: number, r: number) => [Math.cos(a) * r, Math.sin(a) * r];
                const points = Array.from({ length: 7 }, (_, i) => at(start + (end - start) * i / 6, 23));
                points.push(at(end, 28), at(end + .43, 19), at(end, 10), at(end, 15));
                for (let i = 6; i >= 0; i--) points.push(at(start + (end - start) * i / 6, 15));
                polygon(points, new Color(174, 192, 157));
            }
        } else if (this.kind === 'SupplyNode') {
            // The header truck's silhouette, with colored wax fills beneath the dark crayon outline.
            const cargo = new Color(126, 145, 191), cab = new Color(231, 150, 81);
            const glass = new Color(195, 221, 230), tire = new Color(76, 74, 70), hub = new Color(246, 227, 185);
            polygon([[-26, 15], [-22, 19], [-5, 22], [10, 18], [10, -5], [-26, -1]], cargo);
            stroke([[-22, 18], [-8, 15], [10, 18]], false, 2.5);
            stroke([[-8, 15], [-8, -4]], false, 3);
            polygon([[-29, -1], [-10, -4], [-10, 11], [11, 15], [27, 12], [28, 8], [7, 5], [11, -6],
                [28, -4], [30, -7], [30, -20], [12, -23], [-29, -16]], cab);
            polygon([[7, 4], [23, 7], [25, -3], [11, -6]], glass);
            stroke([[-3, 11], [5, 10], [23, 12]], false, 2);
            stroke([[11, -6], [12, -23]], false, 3);
            for (const [cx, cy, rx, ry] of [[-23, -15, 5, 7], [0, -20, 6, 7]]) {
                polygon(Array.from({ length: 25 }, (_, i) => {
                    const a = i * Math.PI / 12;
                    return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
                }), tire);
                g.fillColor = hub; g.circle(cx, cy, rx * .42); g.fill();
            }
        } else {
            const upstream = this.kind === 'SupplyUpstream', sign = upstream ? 1 : -1;
            const box = (x: number, y: number, r: number, fill = paper) => polygon([[x-r,y-r],[x+r,y-r],[x+r,y+r],[x-r,y+r]], fill);
            box(sign * 17, 0, 8, new Color(238, 210, 142));
            for (const y of [-16, 16]) {
                box(-sign * 18, y, 5.7);
                const a = [-sign * 10, y], b = [sign * 5, 0];
                stroke(upstream ? [a, b] : [b, a], false, 3.5);
                const tip = upstream ? b : a, from = upstream ? a : b, dx = tip[0]-from[0], dy = tip[1]-from[1], length = Math.hypot(dx,dy);
                stroke([[tip[0]-dx/length*6-dy/length*4,tip[1]-dy/length*6+dx/length*4],tip,
                    [tip[0]-dx/length*6+dy/length*4,tip[1]-dy/length*6-dx/length*4]], false, 3);
            }
        }
    }
}
