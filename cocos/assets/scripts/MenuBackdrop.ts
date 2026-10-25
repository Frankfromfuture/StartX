import { Node, UITransform } from 'cc';
import { LayoutMetrics } from './Layout';
import { DIMMED_BACKGROUND_COLOR, Surface } from './Surface';

/** The same translucent shade used by card details, behind the open menu or tabs. */
export class MenuBackdrop {
    readonly node: Node;

    constructor(parent: Node, private foreground: Node[]) {
        this.node = new Node('MenuBackdrop'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform);
        const shade = this.node.addComponent(Surface); shade.fill = DIMMED_BACKGROUND_COLOR.clone(); shade.radius = 0; shade.paint();
        this.node.active = false;
    }
    layout({ width, height }: LayoutMetrics) {
        this.node.getComponent(UITransform)!.setContentSize(width, height);
    }
    show() {
        const parent = this.node.parent!;
        this.node.setSiblingIndex(parent.children.length - 1);
        for (const node of this.foreground) node.setSiblingIndex(parent.children.length - 1);
        this.node.active = true;
    }
    hide() { this.node.active = false; }
    snapshot() { return { active: this.node.activeInHierarchy, capturing: false, requested: this.node.active, shadeAlpha: DIMMED_BACKGROUND_COLOR.a }; }
    destroy() { this.node.destroy(); }
}
