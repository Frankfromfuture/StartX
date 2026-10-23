import { Graphics, Mask, Node } from 'cc';

/** Clip artwork to the same rounded square as the original card frame. */
export function roundCard(node: Node, size: number) {
    let mask = node.getComponent(Mask);
    if (!mask) { mask = node.addComponent(Mask); mask.type = Mask.Type.GRAPHICS_STENCIL; }
    const graphics = mask.subComp as Graphics || node.getComponent(Graphics) || node.addComponent(Graphics);
    graphics.clear(); graphics.roundRect(-size / 2, -size / 2, size, size, size * .05); graphics.fill();
}
