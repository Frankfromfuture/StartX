import { _decorator, Component, Material, Node, Sprite, SpriteFrame, UITransform, UIOpacity, Vec2, Vec3, Vec4, Color, Graphics, Quat, Label, Font } from 'cc';
import { CardFrameVolume, packThickness, paintPackShadow } from './CardFrameVolume';
import { PackSurface } from './PackSurface';
import { Surface } from './Surface';
import type { Appearance } from './GameModel';
import { BADGE_SIZE, BadgePosition, BOARD_HALF, safeBadgePosition } from './GameModel';
import { viewShadowOffset } from './ViewShadow';
const { ccclass } = _decorator;

export const BATTLE_CARD_Y = -36;

export function cardStyle(id: string, type = ''): 'plain' | 'foil' | 'glass' {
    if (id === 'founder') return 'foil';
    return id === 'cash' || id === 'p3_account' || type === 'cash' || type === 'receivable' || type === 'business_model' ? 'glass' : 'plain';
}

@ccclass('CardView')
export class CardView extends Component {
    pack = false;
    private appearance: Appearance | null = null;
    private landed: (() => void) | null = null;
    private motionTime = 0;
    private initialAngle = 0;
    private pulseTime = 1;
    private retireTime = -1;
    private retired: (() => void) | null = null;
    private smoke: Node | null = null;
    private spending: { target: () => { x: number; y: number }; delay: number; started: (() => void) | null; done: () => void } | null = null;
    private combat: { x: number; y: number; lift: number } | null = null;
    private battleScale = 1;
    private battleScaleFrom = 1;
    private battleScaleTarget = 1;
    private battleScaleTime = 1;
    private hitTime = 1;
    private inspectionAngles = new Vec2();
    private inspecting = false;
    private frameVolume!: CardFrameVolume;
    private packSurface: PackSurface | null = null;
    private patchLighting: Material | null = null;
    private light = new Vec4(0, 0, 0, 1);
    private lightRotation = new Quat();
    private glide: { x: number; y: number; time: number } | null = null;
    get isAppearing() { return !!this.appearance; }
    get isSliding() { return !!this.glide; }
    get progressNode() { return this.progress.node; }
    get frontNode() { return this.front.node; }
    get artwork() { return this.front.spriteFrame; }
    get numberPatch() { return { frame: this.patch.node.active ? this.patch.spriteFrame : null, kind: this.patchKind }; }
    get inspectionLighting() { return this.light; }
    get frameColor() { return this.holographic ? 'rainbow' : '#141414'; }
    setInspectionMode(active: boolean) { this.inspecting = active; this.frameVolume.node.active = !active && !this.pack && !this.badgeToken; this.shadow.active = !active && !this.badgeToken; }
    setPackPatchVisible(visible: boolean) { if (this.pack) this.patch.node.active = visible && !!this.patch.spriteFrame; }
    createInspectionMaterial() {
        if (!this.originalMaterial) return null;
        const material = new Material(); material.copy(this.originalMaterial);
        material.setProperty('foilAndProjection', new Vec4(0, 2, 2, 0)); return material;
    }
    setInspectionAngles(pitch: number, yaw: number) {
        this.inspectionAngles.set(yaw * Math.PI / 180, pitch * Math.PI / 180);
        Quat.fromEuler(this.lightRotation, pitch, yaw, 0);
        const normal = Vec3.transformQuat(new Vec3(), new Vec3(0, 0, 1), this.lightRotation), side = normal.z < 0 ? -1 : 1;
        this.light.set(1, normal.x * side, normal.y * side, normal.z * side);
        this.foil?.setProperty('inspectionLight', this.light); this.patchLighting?.setProperty('inspectionLight', this.light);
    }
    private face!: Node;
    private shadow!: Node;
    private shadowShift = new Vec2();
    private shadowAnchor = new Vec3();
    private front!: Sprite;
    private patch!: Sprite;
    private progress!: Graphics;
    private status: Label | null = null;
    private statusBack: Graphics | null = null;
    private statusKey = '';
    private lifted = false;
    private tilt = 0;
    private lift = 0;
    private angle = 0;
    private size = 280;
    private badgeToken = false;
    private yarnRoot: Node | null = null;
    private yarnCapacity: Node | null = null;
    private yarnData: { frames: SpriteFrame[]; bonus: number; capacity: number; font: Font; positions: BadgePosition[] } | null = null;
    get isBadgeToken() { return this.badgeToken; }
    get yarnDecorations() { return this.yarnData; }
    private foil: Material | null = null;
    private holographic = false;
    private glass = false;
    private glossPhase = 0;
    private originalMaterial: Material | null = null;
    private foilView = new Vec4(0, 0, 0.22, 0.12);
    private lastRatio = -1;
    private patchKind: 'uses' | 'account' | 'pack' = 'uses';
    onLoad() {
        this.face = this.node.getChildByName('Face')!; this.shadow = this.node.getChildByName('Shadow')!;
        this.front = this.face.getChildByName('Front')!.getComponent(Sprite)!;
        this.originalMaterial = this.front.customMaterial;
        this.frameVolume = new CardFrameVolume(this.face);
        const patch = new Node('OriginalNumberPatch'); patch.layer = this.node.layer; this.face.addChild(patch);
        patch.addComponent(UITransform); this.patch = patch.addComponent(Sprite); this.patch.sizeMode = Sprite.SizeMode.CUSTOM; patch.active = false;
        const progress = new Node('ProductionProgress'); progress.layer = this.node.layer; this.face.addChild(progress);
        progress.addComponent(UITransform).setContentSize(280, 36); progress.setPosition(0, 164); progress.active = false;
        this.progress = progress.addComponent(Graphics);
    }
    configure(frame: SpriteFrame | null, color: string, style: 'plain' | 'foil' | 'glass' | 'pack') {
        this.badgeToken = false;
        if (frame) this.front.spriteFrame = frame;
        this.size = style === 'pack' ? 336 : 280;
        this.pack = style === 'pack';
        this.holographic = style === 'foil';
        this.glass = style === 'glass';
        const artName = this.front.spriteFrame?.name;
        const enhancedGloss = this.glass && (artName === 'cash' || artName === 'p3_account') ? 1 : 0;
        this.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.front.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        const thickness = this.face.getChildByName('Thickness')!;
        thickness.active = false;
        this.frameVolume.node.active = !this.inspecting;
        if (this.pack) this.frameVolume.paintPack(this.size);
        else this.frameVolume.paint(this.size, this.size * .028, 0, 0, this.frameColor, true);
        const shadowSurface = this.shadow.getComponent(Surface)!;
        shadowSurface.enabled = !this.pack;
        this.shadow.getComponent(UITransform)!.setContentSize(this.size, this.size);
        if (this.pack) paintPackShadow(this.shadow.getComponent(Graphics)!, this.size, shadowSurface.fill);
        this.shadow.active = !this.inspecting;
        this.front.customMaterial = this.inspecting || style === 'foil' || style === 'glass' ? this.originalMaterial : null;
        this.foil = this.inspecting || style === 'foil' || style === 'glass' ? this.front.getMaterialInstance(0) : null;
        this.foil?.setProperty('foilAndProjection', new Vec4(.15, 2, style === 'glass' ? 1 : style === 'foil' ? 0 : 2, enhancedGloss));
        this.foil?.setProperty('inspectionLight', this.inspecting ? this.light : new Vec4(0, 0, 0, 1));
        if ((this.inspecting || this.glass) && !this.patchLighting) this.patchLighting = this.createInspectionMaterial();
        this.patchLighting?.setProperty('foilAndProjection', new Vec4(0, 2, this.glass ? 1 : 2, enhancedGloss));
        this.patchLighting?.setProperty('inspectionLight', this.inspecting ? this.light : new Vec4(0, 0, 0, 1));
        this.patch.customMaterial = this.inspecting || this.glass ? this.patchLighting : null;
        if (this.patch.spriteFrame) this.setPatch(this.patch.spriteFrame, this.patchKind);
        if (this.pack && !this.packSurface) this.packSurface = new PackSurface(this.front, this.frameVolume);
        this.packSurface?.configure(this.front.spriteFrame, this.size, this.pack);
        this.packSurface?.setMaterial(this.foil || this.front.customMaterial);
    }
    setBadgeToken(active: boolean) {
        this.badgeToken = active;
        if (!active) return;
        this.size = this.inspecting ? 280 : 108;
        this.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.front.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.frameVolume.node.active = false; this.shadow.active = false;
    }
    private pointOnFace(point: Vec2): BadgePosition {
        const t = this.front.node.getComponent(UITransform)!, o = t.convertToWorldSpaceAR(new Vec3());
        const right = t.convertToWorldSpaceAR(new Vec3(1, 0)), up = t.convertToWorldSpaceAR(new Vec3(0, 1));
        const ax = right.x - o.x, ay = right.y - o.y, bx = up.x - o.x, by = up.y - o.y;
        const dx = point.x - o.x, dy = point.y - o.y, det = ax * by - ay * bx;
        return Math.abs(det) > .000001 ? { x: (dx * by - dy * bx) / det, y: (dy * ax - dx * ay) / det } : { x: 0, y: 0 };
    }
    badgePositionAt(point: Vec2): BadgePosition { return safeBadgePosition(this.pointOnFace(point)); }
    containsFace(point: Vec2) { const p = this.pointOnFace(point); return Math.abs(p.x) <= this.size / 2 && Math.abs(p.y) <= this.size / 2; }
    badgeAt(point: Vec2) {
        if (!this.yarnRoot?.activeInHierarchy) return -1;
        const p = this.pointOnFace(point);
        for (let i = this.yarnRoot.children.length - 1; i >= 0; i--) {
            const node = this.yarnRoot.children[i], t = node.getComponent(UITransform)!;
            if (Math.abs(p.x - node.position.x) <= t.width / 2 && Math.abs(p.y - node.position.y) <= t.height / 2) return i;
        }
        return -1;
    }
    setYarnBadges(frames: SpriteFrame[], bonus: number, capacity: number, font: Font, positions: BadgePosition[] = []) {
        this.yarnData = { frames, bonus, capacity, font, positions };
        this.yarnRoot?.destroy(); this.yarnCapacity?.destroy(); this.yarnRoot = this.yarnCapacity = null;
        if (!bonus) return;
        const root = this.yarnRoot = new Node('YarnBadges'); root.layer = this.node.layer; this.face.addChild(root);
        const make = (name: string, parent: Node, x: number, y: number, w: number, h: number) => {
            const node = new Node(name); node.layer = this.node.layer; parent.addChild(node);
            node.setPosition(x, y); node.addComponent(UITransform).setContentSize(w, h); return node;
        };
        frames.forEach((frame, i) => {
            const p = safeBadgePosition(positions[i] || { x: -76 + i % 3 * 76, y: 12 - Math.floor(i / 3) * 18 });
            const n = make('Badge-' + i, root, p.x, p.y, BADGE_SIZE, BADGE_SIZE);
            const s = n.addComponent(Sprite); s.sizeMode = Sprite.SizeMode.CUSTOM; s.spriteFrame = frame;
        });
        const text = (node: Node, value: string, size: number, color: Color) => {
            const label = node.addComponent(Label); label.font = font; label.useSystemFont = false; label.string = value;
            label.fontSize = size; label.lineHeight = size + 4; label.color = color;
            label.horizontalAlign = Label.HorizontalAlign.CENTER; label.verticalAlign = Label.VerticalAlign.CENTER;
        };
        const capacityNode = this.yarnCapacity = make('EmployeeCapacity', this.face, 93.33, -94.89, 52, 38);
        const ink = capacityNode.addComponent(Graphics); ink.fillColor = new Color(0, 0, 0); ink.circle(0, 0, 18); ink.fill();
        text(make('Value', capacityNode, 0, 0, 50, 38), String(capacity), 26, Color.WHITE.clone());
    }
    setPatch(frame: SpriteFrame | null, kind: 'uses' | 'account' | 'pack') {
        this.patchKind = kind; this.patch.node.active = !!frame; if (!frame) return;
        this.patch.spriteFrame = frame;
        const [x, y, w, h] = kind === 'uses' ? [0, 0, 1024, 244] : kind === 'account' ? [0, 700, 300, 324] : [790, 32, 210, 210];
        const ratio = this.size / 1024;
        this.patchLighting?.setProperty('cardUVRect', new Vec4(x / 1024, y / 1024, w / 1024, h / 1024));
        this.patch.node.getComponent(UITransform)!.setContentSize(w * ratio, h * ratio);
        this.patch.node.setPosition((x + w / 2 - 512) * ratio, (512 - y - h / 2) * ratio);
        if (kind === 'pack') this.patch.node.setPosition(this.patch.node.position.x, this.patch.node.position.y, packThickness(this.size, this.patch.node.position.y) / 2);
    }
    setProgress(ratio: number, active: boolean) {
        ratio = Math.round(Math.max(0, Math.min(1, ratio)) * 100) / 100;
        const key = ratio + (active ? 2 : 0); if (key === this.lastRatio) return; this.lastRatio = key;
        const g = this.progress; g.node.active = ratio > 0; g.clear(); if (ratio <= 0) return;
        g.fillColor = new Color(42, 40, 36); g.roundRect(-140, -18, 280, 36, 4); g.fill();
        g.fillColor = new Color(189, 186, 177); g.roundRect(-138, -16, 276 * Math.max(.02, ratio), 32, 3); g.fill();
    }
    setStatus(text: string, urgent: boolean, font: Font) {
        const key = text + urgent; if (key === this.statusKey) return; this.statusKey = key;
        if (!text && !this.status) return;
        if (!this.status) {
            const back = new Node('CardStatus'); back.layer = this.node.layer; this.face.addChild(back); back.setPosition(0, -109);
            back.addComponent(UITransform).setContentSize(250, 36); this.statusBack = back.addComponent(Graphics);
            const n = new Node('Text'); n.layer = this.node.layer; back.addChild(n); n.addComponent(UITransform).setContentSize(242, 36);
            const label = this.status = n.addComponent(Label); label.font = font; label.useSystemFont = false;
            label.fontSize = 19; label.lineHeight = 24; label.horizontalAlign = Label.HorizontalAlign.CENTER;
            label.verticalAlign = Label.VerticalAlign.CENTER; label.overflow = Label.Overflow.SHRINK; label.enableWrapText = false;
            // Label initialization resizes the box; restore it after applying the font and overflow.
            n.getComponent(UITransform)!.setContentSize(242, 36);
        }
        this.statusBack!.node.active = !!text; this.status.string = text;
        const g = this.statusBack!; g.clear(); g.fillColor = urgent ? new Color(134, 45, 38, 245) : new Color(28, 29, 29, 235);
        g.roundRect(-125, -18, 250, 36, 5); g.fill(); this.status.color = new Color(255, 248, 227);
    }
    appear(motion: Appearance, landed?: () => void) {
        this.appearance = motion; this.motionTime = 0;
        this.landed = landed || null;
        this.initialAngle = motion.slide ? 0 : (Math.random() * 2 - 1) * (motion.kind === 'cash' ? .22 : motion.kind === 'fly' ? .05 : .06) * 180 / Math.PI;
        this.update(0);
    }
    pulse() { this.pulseTime = 0; }
    setCombat(pose: { x: number; y: number; lift: number } | null) {
        this.combat = pose;
        if (pose) { this.appearance = null; this.landed = null; this.glide = null; }
    }
    setBattle(active: boolean) {
        const target = active ? 1.22 : 1;
        if (target === this.battleScaleTarget) return;
        this.battleScaleFrom = this.battleScale; this.battleScaleTarget = target; this.battleScaleTime = 0;
    }
    hit() { this.hitTime = 0; }
    slideFrom(x: number, y: number) { this.glide = { x, y, time: 0 }; this.update(0); }
    drawDropHint(g: Graphics, clock: number, stackHeight = 0) {
        const halfX = this.size * this.battleScale / 2 + 12, halfY = (this.size * this.battleScale + stackHeight) / 2 + 12, radius = 22;
        const lengths = [2 * (halfX - radius), 2 * (halfY - radius), 2 * (halfX - radius), 2 * (halfY - radius)];
        const arc = Math.PI * radius / 2, perimeter = lengths.reduce((sum, length) => sum + length + arc, 0);
        g.node.getComponent(UITransform)!.setContentSize(halfX * 2 + 10, halfY * 2 + 10);
        const point = (distance: number) => {
            let section = 0, d = distance;
            while (section < 3 && d > lengths[section] + arc) { d -= lengths[section] + arc; section++; }
            let x = 0, y = 0;
            if (d <= lengths[section]) {
                if (section === 0) { x = -halfX + radius + d; y = halfY; }
                else if (section === 1) { x = halfX; y = halfY - radius - d; }
                else if (section === 2) { x = halfX - radius - d; y = -halfY; }
                else { x = -halfX; y = -halfY + radius + d; }
            } else {
                const angle = Math.PI / 2 - section * Math.PI / 2 - (d - lengths[section]) / radius;
                x = (section < 2 ? halfX - radius : -halfX + radius) + Math.cos(angle) * radius;
                y = (section === 0 || section === 3 ? halfY - radius : -halfY + radius) + Math.sin(angle) * radius;
            }
            return new Vec3(x, y);
        };
        const paths: Vec3[][] = [], phase = clock * 80 % 38;
        for (let start = phase - 38; start < perimeter; start += 38) {
            const from = Math.max(0, start), to = Math.min(perimeter, start + 22); if (to <= from) continue;
            const path = [point(from)]; for (let d = from + 4; d < to; d += 4) path.push(point(d)); path.push(point(to)); paths.push(path);
        }
        g.clear(); g.lineCap = Graphics.LineCap.ROUND; g.lineJoin = Graphics.LineJoin.ROUND;
        g.lineWidth = 10; g.strokeColor = Color.BLACK;
        for (const path of paths) { g.moveTo(path[0].x, path[0].y); for (const p of path.slice(1)) g.lineTo(p.x, p.y); }
        g.stroke();
    }
    spend(target: () => { x: number; y: number }, delay: number, started: () => void, done: () => void) {
        this.appearance = null; this.landed = null; this.motionTime = 0;
        this.spending = { target, delay, started, done };
        this.lifted = false; this.lift = this.angle = this.tilt = 0; this.progress.node.active = false;
        if (!this.node.getComponent(UIOpacity)) this.node.addComponent(UIOpacity);
        this.update(0);
    }
    dissolve(done: () => void) {
        this.appearance = null; this.retireTime = 0; this.retired = done;
        this.combat = null; this.glide = null; this.spending = null;
        if (!this.node.getComponent(UIOpacity)) this.node.addComponent(UIOpacity);
        this.smoke = new Node('PackSmoke'); this.smoke.layer = this.node.layer; this.node.addChild(this.smoke);
        this.smoke.addComponent(UITransform); const g = this.smoke.addComponent(Graphics); g.fillColor = new Color(121, 115, 105, 35);
        for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; g.circle(Math.cos(a) * 44, Math.sin(a) * 32, 28 + i % 3 * 7); g.fill(); }
    }
    motionSnapshot() { return { kind: this.combat ? 'attack' : this.spending ? 'spend' : this.glide ? 'slide' : this.appearance?.kind || (this.retireTime >= 0 ? 'dissolve' : ''), time: this.glide?.time ?? this.motionTime, delay: this.spending?.delay || this.appearance?.delay || 0, scale: this.face.scale.x, offset: { x: this.face.position.x, y: this.face.position.y }, pulse: this.pulseTime < .22 }; }
    setHeld(held: boolean) { this.lifted = held; if (held) { this.appearance = null; this.landed = null; this.glide = null; } if (!held) this.tilt = 0; }
    setDragDelta(dx: number) { this.tilt = Math.max(-5, Math.min(5, -dx * 0.22)); }
    contains(world: Vec2 | Vec3) {
        // Flying cards must not intercept the next tap on the pack beneath them.
        if (this.retireTime >= 0 || this.appearance || this.spending || this.glide) return false;
        const local = this.front.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(world.x, world.y, 'z' in world ? world.z : 0));
        return Math.abs(local.x) <= this.size / 2 && Math.abs(local.y) <= this.size / 2;
    }
    update(dt: number) {
        if (this.glass) this.glossPhase = (this.glossPhase + Math.min(dt, .05) * .08) % 1;
        const back = (t: number) => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2);
        let x = 0, y = 0, sx = 1, sy = 1, rotation = 0;
        if (this.appearance) {
            this.motionTime += Math.min(dt, .05);
            const a = this.appearance, time = Math.max(0, this.motionTime - a.delay);
            const duration = a.kind === 'fly' ? .43 : a.kind === 'cash' || a.kind === 'pack' ? .42 : .36;
            const t = Math.min(1, time / duration);
            const travel = a.slide ? 1 - Math.pow(1 - t, 3) : a.kind === 'fly' ? Math.sin(t * Math.PI / 2) : a.kind === 'pack' ? 1 - Math.pow(1 - t, 4) : back(t);
            x = (a.x - this.node.position.x) * (1 - travel); y = (a.y - this.node.position.y) * (1 - travel);
            const scaleTime = Math.min(1, time / (a.kind === 'cash' ? .34 : duration));
            const grow = a.slide || a.kind === 'fly' ? 1 - Math.pow(1 - scaleTime, 3) : back(scaleTime), start = a.startScale ?? (a.slide ? .8 : a.kind === 'pack' ? .82 : a.kind === 'cash' ? .16 : .18);
            sx = sy = start + (1 - start) * grow;
            rotation = a.kind === 'pack' ? 0 : this.initialAngle * (1 - Math.min(1, time / (a.kind === 'fly' ? .37 : a.kind === 'cash' ? .32 : .30)));
            if (t === 1) { this.appearance = null; const landed = this.landed; this.landed = null; landed?.(); }
        }
        if (this.pulseTime < .22) {
            this.pulseTime += dt; const t = this.pulseTime < .08 ? Math.pow(this.pulseTime / .08, 2) : 1 - back(Math.min(1, (this.pulseTime - .08) / .14));
            sx *= 1 + .14 * t; sy *= 1 - .14 * t;
        }
        if (this.retireTime >= 0) {
            this.retireTime += dt; const t = Math.min(1, this.retireTime / .32);
            sx = sy = 1 - (2.70158 * t * t * t - 1.70158 * t * t); y = 22 * t; rotation = -20 * t;
            this.node.getComponent(UIOpacity)!.opacity = 255 * (1 - Math.min(1, this.retireTime / .34));
            this.smoke?.setScale(1 + t * 1.8, 1 + t * 1.8, 1);
            if (this.retireTime >= .34) { const done = this.retired; this.retired = null; done?.(); return; }
        }
        if (this.spending) {
            this.motionTime += Math.min(dt, .05);
            const motion = this.spending, time = this.motionTime - motion.delay;
            if (time >= 0 && motion.started) { const started = motion.started; motion.started = null; started(); }
            const t = Math.max(0, Math.min(1, time / .4)), travel = 1 - (1 - t) * (1 - t), target = motion.target();
            x = (target.x - this.node.position.x) * travel; y = (target.y - this.node.position.y) * travel;
            const shrink = Math.max(0, Math.min(1, (time - .4) / .35));
            sx = sy = 1 - shrink * shrink * (3 - 2 * shrink); rotation = 0;
            this.node.getComponent(UIOpacity)!.opacity = 255;
            if (time >= .75) { this.spending = null; motion.done(); return; }
        }
        if (this.glide) {
            this.glide.time += Math.min(dt, .05);
            const t = Math.min(1, this.glide.time / .3), remaining = Math.pow(1 - t, 3);
            x += (this.glide.x - this.node.position.x) * remaining; y += (this.glide.y - this.node.position.y) * remaining;
            if (t === 1) this.glide = null;
        }
        if (this.combat) {
            x += this.combat.x; y += this.combat.y + this.combat.lift;
            sx *= 1 + this.combat.lift / 750; sy *= 1 + this.combat.lift / 750;
        }
        if (this.hitTime < .24) { this.hitTime += dt; x += Math.sin(this.hitTime * 80) * 9 * Math.max(0, 1 - this.hitTime / .24); }
        this.battleScaleTime += Math.min(dt, .05);
        const sizeTime = Math.min(1, this.battleScaleTime / (this.battleScaleTarget > 1 ? .3 : .85));
        const sizeEase = sizeTime * sizeTime * sizeTime * (sizeTime * (sizeTime * 6 - 15) + 10);
        this.battleScale = this.battleScaleFrom + (this.battleScaleTarget - this.battleScaleFrom) * sizeEase;
        y += BATTLE_CARD_Y * (this.battleScale - 1) / .22;
        const blend = 1 - Math.exp(-18 * Math.min(dt, 0.05));
        this.lift += ((this.lifted ? 18 : 0) - this.lift) * blend;
        this.angle += (this.tilt - this.angle) * blend;
        this.face.setPosition(x, y + this.lift, 0); this.face.angle = this.angle + rotation;
        const scale = (1 + this.lift / 600) * this.battleScale; this.face.setScale(scale * sx, scale * sy, 1);
        if (!this.inspecting && !this.glide) {
            const angle = this.face.angle * Math.PI / 180, cos = Math.abs(Math.cos(angle)), sin = Math.abs(Math.sin(angle));
            const halfX = this.size / 2 * (cos * Math.abs(scale * sx) + sin * Math.abs(scale * sy)) + this.size * .028;
            const halfY = this.size / 2 * (sin * Math.abs(scale * sx) + cos * Math.abs(scale * sy)) + this.size * .028;
            const limitX = BOARD_HALF - halfX, limitY = BOARD_HALF - halfY, p = this.node.position, face = this.face.position;
            this.face.setPosition(Math.max(-limitX, Math.min(limitX, p.x + face.x)) - p.x,
                Math.max(-limitY, Math.min(limitY, p.y + face.y)) - p.y, 0);
        }
        this.shadowAnchor.set(this.face.position.x, this.face.position.y - this.lift, 0);
        viewShadowOffset(this.node, this.shadowAnchor, 14 + this.lift * .8 + Math.max(0, this.combat?.lift || 0) * .4, this.shadowShift);
        this.shadow.setPosition(this.shadowAnchor.x + this.shadowShift.x, this.shadowAnchor.y + this.shadowShift.y, 0);
        this.shadow.angle = this.face.angle;
        this.shadow.setScale((1 + this.lift / 240) * sx * this.battleScale, (1 + this.lift / 240) * sy * this.battleScale, 1);
        // The board represents camera pitch with Y scale; detail cards remain square.
        const worldScale = this.node.worldScale;
        const pitch = worldScale.y / Math.max(.001, worldScale.x);
        const viewTilt = this.holographic ? (1 - pitch) * 2.2 : 0;
        if (!this.inspecting && !this.badgeToken) {
            if (!this.pack) this.frameVolume.paint(this.size, this.size * .028, viewTilt * 20, this.angle, this.frameColor, true);
        }
        if (this.pack) this.packSurface?.update();
        if (this.pack && this.patch.node.active) {
            const p = this.patch.node.position, scale = this.face.worldScale;
            this.patch.node.setPosition(p.x, p.y, packThickness(this.size, p.y) / 2 * Math.abs(scale.x / Math.max(.0001, scale.z)));
        }
        this.foilView.set(this.angle * Math.PI / 180 + this.inspectionAngles.x, this.lift / 360 + viewTilt + this.inspectionAngles.y, this.holographic ? .32 : .22, this.glass ? this.glossPhase : .12);
        this.foil?.setProperty('viewAndStrength', this.foilView);
        if (this.glass && this.patch.node.active) this.patchLighting?.setProperty('viewAndStrength', this.foilView);
    }
}
