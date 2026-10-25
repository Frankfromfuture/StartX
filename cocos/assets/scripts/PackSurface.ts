import { Camera, Canvas, Material, Node, Rect, Size, Sprite, SpriteFrame, UITransform, Vec2, Vec3 } from 'cc';
import { CardFrameVolume, FrameProjection, PACK_PROFILE_STOPS, packThickness } from './CardFrameVolume';

/** Five textured planes follow the wrapper's flat body, sloping shoulders and thin seals. */
export class PackSurface {
    readonly node: Node;
    private strips: { node: Node; sprite: Sprite; frame: SpriteFrame }[] = [];
    private frame: SpriteFrame | null = null;
    private size = 0;
    private depthScale = 1;
    private camera: Camera | null = null;
    private eye = new Vec3();
    private planeEye = new Vec3();
    private projection: FrameProjection = { key: '', eye: this.eye, project: point => this.project(point) };
    constructor(private source: Sprite, private volume?: CardFrameVolume) {
        this.node = new Node('PouchSurface'); this.node.layer = source.node.layer; source.node.addChild(this.node);
        this.node.setSiblingIndex(0); this.node.addComponent(UITransform);
        for (let parent: Node | null = source.node; parent; parent = parent.parent) {
            const canvas = parent.getComponent(Canvas);
            if (canvas?.cameraComponent) { this.camera = canvas.cameraComponent; break; }
        }
        source.node.on(Node.EventType.NODE_DESTROYED, this.dispose, this);
    }
    configure(frame: SpriteFrame | null, size: number, active = true) {
        this.node.active = active; this.source.enabled = !active;
        if (!active || !frame || frame === this.frame && size === this.size) return;
        this.dispose(); this.frame = frame; this.size = size;
        this.node.getComponent(UITransform)!.setContentSize(size, size);
        for (let i = 0; i < PACK_PROFILE_STOPS.length - 1; i++) {
            const a = PACK_PROFILE_STOPS[i], b = PACK_PROFILE_STOPS[i + 1];
            const y0 = a * size, y1 = b * size, z0 = packThickness(size, y0) / 2, z1 = packThickness(size, y1) / 2;
            const slice = new SpriteFrame(); slice.texture = frame.texture;
            slice.rect = new Rect(frame.rect.x, frame.rect.y + (.5 - b) * frame.rect.height, frame.rect.width, (b - a) * frame.rect.height);
            slice.originalSize = new Size(slice.rect.width, slice.rect.height); slice.offset = new Vec2(); slice.packable = false;
            const node = new Node('Band-' + i); node.layer = this.node.layer; this.node.addChild(node);
            node.addComponent(UITransform).setContentSize(size, Math.hypot(y1 - y0, z1 - z0));
            node.setPosition(0, (y0 + y1) / 2, (z0 + z1) / 2);
            node.setRotationFromEuler(Math.atan2(z1 - z0, y1 - y0) * 180 / Math.PI, 0, 0);
            const sprite = node.addComponent(Sprite); sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.trim = false; sprite.spriteFrame = slice;
            this.strips.push({ node, sprite, frame: slice });
        }
        this.depthScale = NaN; this.update();
    }
    setMaterial(material: Material | null) { for (const strip of this.strips) strip.sprite.customMaterial = material; }
    private project(point: Vec3) {
        const world = this.source.node.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(point.x, point.y, point.z * this.depthScale));
        const p = this.volume!.node.getComponent(UITransform)!.convertToNodeSpaceAR(world);
        const ratio = this.planeEye.z / (this.planeEye.z - p.z);
        return new Vec3(this.planeEye.x + (p.x - this.planeEye.x) * ratio, this.planeEye.y + (p.y - this.planeEye.y) * ratio, 0);
    }
    update() {
        if (!this.node.activeInHierarchy) return;
        const scale = this.source.node.worldScale, depthScale = Math.abs(scale.x / Math.max(.0001, scale.z));
        if (Math.abs(depthScale - this.depthScale) > .00001 || !Number.isFinite(this.depthScale)) {
            this.depthScale = depthScale;
            this.strips.forEach((strip, index) => {
                const y0 = PACK_PROFILE_STOPS[index] * this.size, y1 = PACK_PROFILE_STOPS[index + 1] * this.size;
                const z0 = packThickness(this.size, y0) * depthScale / 2, z1 = packThickness(this.size, y1) * depthScale / 2;
                strip.node.getComponent(UITransform)!.setContentSize(this.size, Math.hypot(y1 - y0, z1 - z0));
                strip.node.setPosition(0, (y0 + y1) / 2, (z0 + z1) / 2);
                strip.node.setRotationFromEuler(Math.atan2(z1 - z0, y1 - y0) * 180 / Math.PI, 0, 0);
            });
        }
        const world = this.camera?.node.worldPosition;
        if (world) this.source.node.getComponent(UITransform)!.convertToNodeSpaceAR(world, this.eye);
        for (const strip of this.strips) {
            strip.sprite.color = this.source.color;
            const angle = strip.node.eulerAngles.x * Math.PI / 180, p = strip.node.position;
            strip.node.active = !world || -(this.eye.y - p.y) * Math.sin(angle) + (this.eye.z - p.z) * Math.cos(angle) > 0;
        }
        if (!this.volume || !world) return;
        this.volume.node.getComponent(UITransform)!.convertToNodeSpaceAR(world, this.planeEye);
        this.projection.key = [this.eye.x, this.eye.y, this.eye.z, this.depthScale].map(n => n.toFixed(3)).join('|');
        this.volume.paintPack(this.size, 0, 0, false, false, this.projection);
    }
    private dispose() {
        for (const strip of this.strips) { if (strip.node.isValid) strip.node.destroy(); strip.frame.destroy(); }
        this.strips = [];
    }
}
