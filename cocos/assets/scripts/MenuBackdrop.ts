import { Camera, director, Director, EffectAsset, Graphics, Material, Node, RenderTexture, Sprite, SpriteFrame, UIOpacity, UITransform, Vec4 } from 'cc';
import { LayoutMetrics } from './Layout';

/** The same frozen, translucent Gaussian background as the card catalog. */
export class MenuBackdrop {
    readonly node: Node;
    private texture = new RenderTexture();
    private frame = new SpriteFrame();
    private material: Material;
    private camera: Camera | null = null;
    private previousTarget: RenderTexture | null = null;
    private hidden: { opacity: UIOpacity; value: number }[] = [];
    private wanted = false;
    private metrics!: LayoutMetrics;
    private recapture = false;
    private finish = () => {
        const camera = this.camera;
        if (camera?.isValid) camera.targetTexture = this.previousTarget;
        this.camera = null;
        for (const { opacity, value } of this.hidden) if (opacity.isValid) {
            opacity.opacity = value;
            opacity.node.getComponentsInChildren(Graphics).forEach(graphics => graphics.model?.updateWorldBound());
        }
        this.hidden = [];
        this.node.active = this.wanted;
        if (this.wanted && this.recapture && camera?.isValid) { this.recapture = false; this.capture(camera); }
    };

    constructor(parent: Node, effect: EffectAsset, private foreground: Node[]) {
        this.node = new Node('MenuBackdrop'); this.node.layer = parent.layer; parent.addChild(this.node);
        this.node.addComponent(UITransform);
        this.texture.initialize({ width: 16, height: 16 }); this.frame.texture = this.texture; this.frame.flipUVY = true;
        this.material = new Material(); this.material.initialize({ effectAsset: effect });
        const sprite = this.node.addComponent(Sprite); sprite.spriteFrame = this.frame; sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.customMaterial = this.material;
        this.node.active = false;
    }
    layout(metrics: LayoutMetrics) {
        this.metrics = metrics;
        const { width, height, scale } = metrics;
        this.node.getComponent(UITransform)!.setContentSize(width, height);
        this.material.setProperty('blurStep', new Vec4(6 * scale / width, 6 * scale / height, .94, .42));
    }
    show(camera: Camera, refresh = false) {
        const first = !this.wanted; this.wanted = true;
        if (first || refresh) this.capture(camera);
    }
    cancelCapture() {
        this.recapture = false;
        if (!this.camera) return;
        director.off(Director.EVENT_AFTER_DRAW, this.finish); this.finish();
    }
    hide() { this.wanted = false; this.cancelCapture(); this.node.active = false; }
    private capture(camera: Camera) {
        if (this.camera) { this.recapture = true; return; }
        this.node.active = false;
        const { width, height, scale } = this.metrics, ratio = Math.min(1, 768 / Math.max(width / scale, height / scale));
        this.texture.resize(Math.max(1, Math.round(width / scale * ratio)), Math.max(1, Math.round(height / scale * ratio)));
        this.frame.reset({ texture: this.texture }, true); this.frame.flipUVY = true;
        this.hidden = this.foreground.map(node => {
            const opacity = node.getComponent(UIOpacity) || node.addComponent(UIOpacity), value = opacity.opacity;
            opacity.opacity = 0; return { opacity, value };
        });
        this.camera = camera; this.previousTarget = camera.targetTexture; camera.targetTexture = this.texture;
        director.once(Director.EVENT_AFTER_DRAW, this.finish);
    }
    snapshot() { return { active: this.node.activeInHierarchy, capturing: !!this.camera, requested: this.wanted }; }
    destroy() {
        this.wanted = false; director.off(Director.EVENT_AFTER_DRAW, this.finish); this.finish();
        this.frame.destroy(); this.texture.destroy(); this.material.destroy();
    }
}
