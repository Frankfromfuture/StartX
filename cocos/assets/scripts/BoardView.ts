import { _decorator, Color, Component, Graphics, Node, Sprite, SpriteFrame, Vec2, UITransform } from 'cc';
import { Surface } from './Surface';
import { BOARD_CELLS } from './GameModel';
import { NightShiftOverlay } from './NightShiftOverlay';
const { ccclass } = _decorator;

@ccclass('BoardView')
export class BoardView extends Component {
    readonly gridCells = BOARD_CELLS;
    frameWidth = 720;
    frameHeight = 1000;
    zoom = 1;
    pitch = 1;
    private city: Node | null = null;
    private shade: Node | null = null;
    private edgeFade: Graphics | null = null;
    private edgeKey = '';
    private night: NightShiftOverlay | null = null;
    private lightTarget: Node | null = null;
    private boardSize = 0;
    private overviewArea = { left: -360, right: 360, bottom: -500, top: 500 };
    private movement: { fromX: number; fromY: number; fromZoom: number; x: number; y: number; zoom: number; time: number; duration: number } | null = null;
    get moving() { return !!this.movement; }
    setNightShift(enabled: boolean, founder: Node | null) {
        this.lightTarget = founder;
        if (enabled && !this.night) this.night = new NightShiftOverlay(this.node.getChildByName('Table')!);
        if (this.night) {
            this.night.node.active = enabled;
            if (enabled) this.night.configure(this.boardSize, this.pitch, this.shade!.getComponent(Surface)!.fill);
        }
        if (this.edgeFade) this.edgeFade.node.active = !enabled;
    }
    lateUpdate() {
        if (!this.night?.node.active || !this.lightTarget?.isValid) return;
        const point = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(this.lightTarget.worldPosition);
        this.night.follow(point.x, point.y);
    }
    get minimumZoom() {
        const size = this.boardSize * 2 || 10080;
        return Math.max((this.frameWidth + 4) / size, (this.frameHeight + 4) / (size * this.pitch));
    }
    setSurroundings(frame: SpriteFrame) {
        this.city = new Node('CitySurroundings');
        this.node.addChild(this.city); this.city.setSiblingIndex(0);
        this.city.addComponent(UITransform);
        const sprite = this.city.addComponent(Sprite);
        sprite.spriteFrame = frame; sprite.sizeMode = Sprite.SizeMode.CUSTOM;
        this.shade = new Node('BackgroundTint');
        this.city.addChild(this.shade);
        this.shade.addComponent(UITransform);
        const tint = this.shade.addComponent(Surface);
        tint.radius = 0; tint.fill = new Color(62, 66, 74, 158); tint.paint();
        const edge = new Node('BoardEdgeFade');
        this.node.getChildByName('Table')!.addChild(edge); edge.addComponent(UITransform);
        this.edgeFade = edge.addComponent(Graphics);
        this.refreshGrid();
    }
    animateTo(zoom: number, x: number, y: number, duration: number) {
        this.movement = { fromX: this.node.position.x, fromY: this.node.position.y, fromZoom: this.zoom, x, y, zoom: Math.max(this.minimumZoom, Math.min(2.4, zoom)), time: 0, duration };
    }
    update(dt: number) {
        const m = this.movement; if (!m) return;
        const t = Math.min(1, (m.time += Math.min(dt, .05)) / m.duration);
        const ease = t * t * t * (t * (t * 6 - 15) + 10);
        this.zoom = m.fromZoom + (m.zoom - m.fromZoom) * ease;
        this.node.setScale(this.zoom, this.zoom * this.pitch, 1);
        this.node.setPosition(m.fromX + (m.x - m.fromX) * ease, m.fromY + (m.y - m.fromY) * ease);
        this.refreshGrid(); if (t === 1) this.movement = null;
    }
    setPitch(value: number) { this.pitch = Math.max(.76, Math.min(1.12, value)); this.node.setScale(this.zoom, this.zoom * this.pitch, 1); this.refreshGrid(); }
    configure(w: number, h: number, area = { left: -w / 2, right: w / 2, bottom: -h / 2, top: h / 2 }) {
        this.frameWidth = w; this.frameHeight = h;
        this.overviewArea = area;
        this.refreshGrid();
    }
    pan(delta: Vec2) {
        this.movement = null;
        this.node.setPosition(this.node.position.x + delta.x, this.node.position.y + delta.y, 0);
        this.refreshGrid();
    }
    setZoom(next: number, anchor = new Vec2()) {
        this.movement = null;
        const z = Math.max(this.minimumZoom, Math.min(2.4, next));
        const ratio = z / this.zoom;
        const pos = this.node.position;
        this.node.setPosition(anchor.x - (anchor.x - pos.x) * ratio, anchor.y - (anchor.y - pos.y) * ratio, 0);
        this.zoom = z; this.node.setScale(z, z * this.pitch, 1); this.refreshGrid();
    }
    reset() {
        this.movement = null;
        this.zoom = 1; this.pitch = 1; this.node.setScale(1, 1, 1); this.node.setPosition(0, 0, 0); this.refreshGrid();
    }
    private refreshGrid() {
        const table = this.node.getChildByName('Table')!;
        const surface = table.getComponent(Surface)!;
        const size = surface.gridSpacing * this.gridCells;
        if (size !== this.boardSize) {
            this.boardSize = size;
            table.setScale(1, 1, 1); table.setPosition(0, 0, 0);
            surface.radius = 0; surface.lineWidth = 0;
            table.getComponent(UITransform)!.setContentSize(size, size);
            surface.setGridTransform(1, 0, 0);
        }
        this.paintEdgeFade(size, surface.gridSpacing);
        // The image's central quarter is covered by the live grid. Both layers
        // stay in board space so their boundary never slides during camera motion.
        if (this.city) {
            this.city.getComponent(UITransform)!.setContentSize(size * 2, size * 2);
            this.city.setPosition(0, -size * .04, 0);
        }
        if (this.zoom < this.minimumZoom) { this.zoom = this.minimumZoom; this.node.setScale(this.zoom, this.zoom * this.pitch, 1); }
        const p = this.node.position;
        const cityY = (this.city?.position.y || 0) * this.zoom * this.pitch;
        // The widest view stops at cover, and every pan keeps the image behind
        // the entire viewport with a small overlap at its edges.
        this.node.setPosition(this.clampCameraAxis(p.x, size * this.zoom, this.frameWidth / 2),
            this.clampCameraAxis(p.y + cityY, size * this.zoom * this.pitch, this.frameHeight / 2) - cityY, p.z);
        if (this.shade) {
            this.shade.setPosition(0, 0, 0);
            this.shade.getComponent(UITransform)!.setContentSize(size * 2, size * 2);
        }
    }
    private paintEdgeFade(size: number, width: number) {
        if (!this.edgeFade || !this.shade) return;
        const color = this.shade.getComponent(Surface)!.fill;
        const key = [size, width, color.r, color.g, color.b, color.a].join('|');
        if (key === this.edgeKey) return;
        this.edgeKey = key;
        const g = this.edgeFade, bands = 128, step = width / bands;
        g.node.getComponent(UITransform)!.setContentSize(size, size); g.clear();
        // Nested, non-overlapping rings keep corners at the same opacity as the
        // adjoining edges. The first cell fades smoothly into the unmasked board.
        for (let i = 0; i < bands; i++) {
            const t = (i + .5) / bands, opacity = Math.round(color.a * (1 - t * t * (3 - 2 * t)));
            if (!opacity) continue;
            const inset = i * step, x = -size / 2 + inset, y = x, span = size - inset * 2;
            g.fillColor = new Color(color.r, color.g, color.b, opacity);
            g.rect(x, y, span, step); g.rect(x, y + span - step, span, step);
            g.rect(x, y + step, step, span - step * 2); g.rect(x + span - step, y + step, step, span - step * 2);
            g.fill();
        }
    }
    private clampCameraAxis(value: number, imageHalf: number, viewportHalf: number) {
        // Keep a small overlap at the image boundary to avoid a raster seam.
        const limit = Math.max(0, imageHalf - viewportHalf - 2);
        return Math.max(-limit, Math.min(limit, value));
    }
    snapshot() {
        const table = this.node.getChildByName('Table')!, size = table.getComponent(UITransform)!;
        return { cells: this.gridCells, spacing: table.getComponent(Surface)!.gridSpacing, width: size.width, height: size.height,
            cityLoaded: !!this.city, cityWidth: this.boardSize * 2, cityHeight: this.boardSize * 2,
            imagePixels: this.city?.getComponent(Sprite)!.spriteFrame?.originalSize,
            table: { x: table.position.x, y: table.position.y, borderWidth: table.getComponent(Surface)!.lineWidth },
            minimumZoom: this.minimumZoom, overviewArea: this.overviewArea, tint: this.shade?.getComponent(Surface)!.fill, tintParent: this.shade?.parent?.name,
            edgeFade: { width: table.getComponent(Surface)!.gridSpacing, bands: 128, active: !!this.edgeFade, parent: this.edgeFade?.node.parent?.name },
            nightShift: this.night?.snapshot() || { enabled: false },
            cameraLimitedToCity: true };
    }
}
