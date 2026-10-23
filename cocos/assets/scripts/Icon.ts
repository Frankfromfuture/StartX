import { _decorator, Component, Graphics, Color } from 'cc';
const { ccclass, property } = _decorator;
/** Resolution-independent HUD icons, so every platform displays the same controls. */
@ccclass('Icon')
export class Icon extends Component {
    @property kind = 'info';
    onLoad() { this.paint(); }
    paint() {
        const g = (this.getComponent(Graphics) || this.addComponent(Graphics))!; g.clear(); g.lineWidth = 3;
        g.strokeColor = new Color(55, 75, 59); g.fillColor = g.strokeColor;
        const line = (x: number, y: number, a: number, b: number) => { g.moveTo(x, y); g.lineTo(a, b); g.stroke(); };
        const box = (x: number, y: number, w: number, h: number) => { g.roundRect(x, y, w, h, 3); g.stroke(); };
        switch (this.kind) {
            case 'Research': this.research(g, line); break;
            case 'Sell': this.sell(g, line); break;
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
    private research(g: Graphics, line: (x: number, y: number, a: number, b: number) => void) {
        g.lineWidth = 2; g.lineJoin = Graphics.LineJoin.ROUND; g.lineCap = Graphics.LineCap.ROUND;
        g.strokeColor = new Color(57, 80, 83); g.fillColor = new Color(249, 243, 224);
        // Open pages, a separate page edge and the fold keep the small silhouette readable.
        g.moveTo(0, -12); g.bezierCurveTo(-7, -7, -15, -5, -24, -8); g.lineTo(-24, -24);
        g.bezierCurveTo(-14, -21, -7, -22, 0, -27); g.bezierCurveTo(7, -22, 14, -21, 24, -24);
        g.lineTo(24, -8); g.bezierCurveTo(15, -5, 7, -7, 0, -12); g.close(); g.fill(); g.stroke();
        line(0, -15, 0, -27); line(-18, -13, -7, -16); line(-18, -18, -7, -21);
        line(7, -16, 18, -13); line(7, -21, 18, -18);
        g.moveTo(-25, -27); g.bezierCurveTo(-14, -24, -7, -25, 0, -30); g.bezierCurveTo(7, -25, 14, -24, 25, -27); g.stroke();
        g.fillColor = new Color(238, 211, 144);
        g.moveTo(-5, -3); g.bezierCurveTo(-5, 1, -12, 2, -12, 10); g.bezierCurveTo(-12, 17, -7, 22, 0, 22);
        g.bezierCurveTo(7, 22, 12, 17, 12, 10); g.bezierCurveTo(12, 2, 5, 1, 5, -3); g.close(); g.fill(); g.stroke();
        line(-4, -6, 4, -6); line(-3, -9, 3, -9); line(0, -3, 0, 4);
        line(0, 4, -4, 9); line(0, 4, 4, 9);
        line(-19, 10, -24, 10); line(19, 10, 24, 10); line(-15, 22, -19, 26);
        line(15, 22, 19, 26); line(0, 28, 0, 33);
        g.lineWidth = 1.5; g.strokeColor = new Color(255, 251, 230);
        g.moveTo(-7, 11); g.bezierCurveTo(-7, 15, -4, 18, 0, 18); g.stroke();
    }
    private sell(g: Graphics, line: (x: number, y: number, a: number, b: number) => void) {
        g.lineWidth = 2; g.lineJoin = Graphics.LineJoin.ROUND; g.lineCap = Graphics.LineCap.ROUND;
        g.strokeColor = new Color(99, 80, 49); g.fillColor = new Color(239, 223, 187);
        // A parcel sits in an open wire basket; the button itself has no filled surface.
        g.moveTo(-14, 8); g.lineTo(-10, 23); g.lineTo(5, 29); g.lineTo(18, 22); g.lineTo(16, 8); g.close(); g.fill(); g.stroke();
        line(-10, 23, 3, 17); line(3, 17, 18, 22); line(3, 17, 3, 7);
        g.lineWidth = 1.3; line(-4, 26, 9, 20); line(9, 20, 9, 15);
        g.lineWidth = 2.3; g.fillColor = new Color(249, 243, 224, 210);
        g.moveTo(-19, 10); g.lineTo(25, 10); g.lineTo(20, -10); g.lineTo(-12, -10); g.close(); g.fill(); g.stroke();
        g.moveTo(-28, 20); g.lineTo(-22, 20); g.lineTo(-12, -14);
        g.quadraticCurveTo(-11, -18, -7, -18); g.lineTo(21, -18); g.stroke();
        g.lineWidth = 1.5; line(-9, 5, -6, -5); line(2, 5, 3, -5); line(14, 5, 12, -5); line(-14, -1, 22, -1);
        g.lineWidth = 2; g.fillColor = new Color(249, 243, 224);
        for (const x of [-7, 17]) { g.circle(x, -25, 3.5); g.fill(); g.stroke(); }
    }
}
