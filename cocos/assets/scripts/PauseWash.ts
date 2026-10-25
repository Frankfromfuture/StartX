import { Color, Graphics, Mask, Node, UITransform, Vec3 } from 'cc';
import type { CardView } from './CardView';

/** A 30% white wash above the board; pack faces are cut out of the stencil. */
export class PauseWash {
    readonly node: Node;
    private mask: Mask;
    private holes: Graphics;
    private fill: Graphics;
    constructor(parent: Node) {
        this.node = new Node('PauseWash'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform);
        this.mask = this.node.addComponent(Mask); this.mask.type = Mask.Type.GRAPHICS_STENCIL; this.mask.inverted = true;
        this.holes = this.mask.subComp as Graphics;
        const panel = new Node('Fade'); panel.layer = parent.layer; this.node.addChild(panel); panel.addComponent(UITransform);
        this.fill = panel.addComponent(Graphics); this.node.active = false;
    }
    layout(width: number, height: number) {
        this.node.getComponent(UITransform)!.setContentSize(width, height);
        this.fill.node.getComponent(UITransform)!.setContentSize(width, height);
        this.fill.clear(); this.fill.fillColor = new Color(255, 255, 255, 77);
        this.fill.rect(-width / 2, -height / 2, width, height); this.fill.fill();
    }
    update(paused: boolean, packs: CardView[]) {
        this.node.active = paused; if (!paused) return;
        this.node.setSiblingIndex(this.node.parent!.children.length - 1);
        this.holes.clear(); this.mask.enabled = packs.length > 0;
        const local = this.node.getComponent(UITransform)!;
        for (const pack of packs) {
            const face = pack.frontNode.getComponent(UITransform)!, w = face.width / 2, h = face.height / 2;
            [[-w, -h], [w, -h], [w, h], [-w, h]].forEach(([x, y], i) => {
                const p = local.convertToNodeSpaceAR(face.convertToWorldSpaceAR(new Vec3(x, y)));
                if (!i) this.holes.moveTo(p.x, p.y); else this.holes.lineTo(p.x, p.y);
            }); this.holes.close(); this.holes.fill();
        }
    }
}
