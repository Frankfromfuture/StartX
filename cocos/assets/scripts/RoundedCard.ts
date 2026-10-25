import { Graphics, Mask, Node } from 'cc';

/** Clip artwork to the same rounded square as the original card frame. */
export function roundCard(node: Node, size: number, inset = 0, radius = size * .05) {
    let mask = node.getComponent(Mask);
    if (!mask) { mask = node.addComponent(Mask); mask.type = Mask.Type.GRAPHICS_STENCIL; }
    const graphics = mask.subComp as Graphics || node.getComponent(Graphics) || node.addComponent(Graphics);
    graphics.clear(); graphics.roundRect(-size / 2 + inset, -size / 2 + inset, size - inset * 2, size - inset * 2, radius); graphics.fill();
}
