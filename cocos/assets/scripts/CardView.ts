import { _decorator, Component, Material, Node, Sprite, SpriteFrame, UITransform, UIOpacity, Vec2, Vec3, Vec4, Color, Graphics, Quat } from 'cc';
import { CardFrameVolume } from './CardFrameVolume';
import type { Appearance } from './GameModel';
import { BOARD_HALF } from './GameModel';
const { ccclass } = _decorator;

export const BATTLE_CARD_Y = -36;

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
    get rainbowFrame() { return this.holographic; }
    setInspectionMode(active: boolean) { this.inspecting = active; this.frameVolume.node.active = !active && !this.pack; this.shadow.active = !active; }
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
    private front!: Sprite;
    private patch!: Sprite;
    private progress!: Graphics;
    private lifted = false;
    private tilt = 0;
    private lift = 0;
    private angle = 0;
    private size = 280;
    private foil: Material | null = null;
    private holographic = false;
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
        if (frame) this.front.spriteFrame = frame;
        this.size = style === 'pack' ? 336 : 280;
        this.pack = style === 'pack';
        this.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.front.node.getComponent(UITransform)!.setContentSize(this.size, this.size);
        const thickness = this.face.getChildByName('Thickness')!;
        thickness.active = false;
        this.frameVolume.node.active = !this.inspecting && !this.pack;
        this.frameVolume.paint(this.size, this.size * .028, 0, 0, style === 'foil', true);
        this.shadow.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.front.customMaterial = this.inspecting || style === 'foil' || style === 'glass' ? this.originalMaterial : null;
        this.holographic = style === 'foil';
        this.foil = this.inspecting || style === 'foil' || style === 'glass' ? this.front.getMaterialInstance(0) : null;
        this.foil?.setProperty('foilAndProjection', new Vec4(.15, 2, style === 'glass' ? 1 : style === 'foil' ? 0 : 2, 0));
        this.foil?.setProperty('inspectionLight', this.inspecting ? this.light : new Vec4(0, 0, 0, 1));
        if (this.inspecting && !this.patchLighting) this.patchLighting = this.createInspectionMaterial();
        this.patch.customMaterial = this.inspecting ? this.patchLighting : null;
        if (this.patch.spriteFrame) this.setPatch(this.patch.spriteFrame, this.patchKind);
    }
    setPatch(frame: SpriteFrame | null, kind: 'uses' | 'account' | 'pack') {
        this.patchKind = kind; this.patch.node.active = !!frame; if (!frame) return;
        this.patch.spriteFrame = frame;
        const [x, y, w, h] = kind === 'uses' ? [0, 0, 1024, 244] : kind === 'account' ? [0, 700, 300, 324] : [790, 32, 210, 210];
        const ratio = this.size / 1024;
        this.patch.node.getComponent(UITransform)!.setContentSize(w * ratio, h * ratio);
        this.patch.node.setPosition((x + w / 2 - 512) * ratio, (512 - y - h / 2) * ratio);
    }
    setProgress(ratio: number, active: boolean) {
        ratio = Math.round(Math.max(0, Math.min(1, ratio)) * 100) / 100;
        const key = ratio + (active ? 2 : 0); if (key === this.lastRatio) return; this.lastRatio = key;
        const g = this.progress; g.node.active = ratio > 0; g.clear(); if (ratio <= 0) return;
        g.fillColor = new Color(42, 40, 36); g.roundRect(-140, -18, 280, 36, 4); g.fill();
        g.fillColor = new Color(189, 186, 177); g.roundRect(-138, -16, 276 * Math.max(.02, ratio), 32, 3); g.fill();
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
    contains(world: Vec2) {
        // Flying cards must not intercept the next tap on the pack beneath them.
        if (this.retireTime >= 0 || this.appearance || this.spending || this.glide) return false;
        const local = this.front.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(world.x, world.y));
        return Math.abs(local.x) <= this.size / 2 && Math.abs(local.y) <= this.size / 2;
    }
    update(dt: number) {
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
            sx = sy = 1; rotation = 0;
            const fade = Math.max(0, Math.min(1, (time - .4) / .35));
            this.node.getComponent(UIOpacity)!.opacity = 255 * (1 - fade) * (1 - fade);
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
        this.shadow.setPosition(x + 10 + this.lift * .25, y - 13 - this.lift * .4, 0);
        this.shadow.setScale((1 + this.lift / 240) * sx * this.battleScale, (1 + this.lift / 240) * sy * this.battleScale, 1);
        // The board represents camera pitch with Y scale; detail cards remain square.
        const worldScale = this.node.worldScale;
        const pitch = worldScale.y / Math.max(.001, worldScale.x);
        const viewTilt = this.holographic ? (1 - pitch) * 2.2 : 0;
        if (!this.inspecting && !this.pack) this.frameVolume.paint(this.size, this.size * .028, viewTilt * 20, this.angle, this.holographic, true);
        this.foilView.set(this.angle * Math.PI / 180 + this.inspectionAngles.x, this.lift / 360 + viewTilt + this.inspectionAngles.y, this.holographic ? .32 : .22, .12);
        this.foil?.setProperty('viewAndStrength', this.foilView);
    }
}
