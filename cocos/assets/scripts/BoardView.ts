import { _decorator, Camera, Canvas, Color, Component, Graphics, Node, Sprite, SpriteFrame, Vec2, Vec3, UITransform } from 'cc';
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
    private playerPlane: Node | null = null;
    private camera: Camera | null = null;
    private eyeDistance = 1000;
    private readonly playerTilt = 15;
    private planeBounds = { left: -360, right: 360, bottom: -500, top: 500 };
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
    enablePlayerPerspective(canvas: Canvas) {
        canvas.alignCanvasWithScreen = false;
        this.camera = canvas.cameraComponent!;
        this.camera.projection = Camera.ProjectionType.PERSPECTIVE;
        this.camera.fovAxis = Camera.FOVAxis.VERTICAL;
        this.camera.fov = 36; this.camera.near = .1; this.camera.far = 50000;
        const plane = new Node('PlayerPerspective'); plane.layer = this.node.layer;
        this.node.parent!.addChild(plane); plane.addComponent(UITransform);
        plane.setRotationFromEuler(-this.playerTilt, 0, 0);
        plane.addChild(this.node); this.playerPlane = plane;
    }
    /** Project world geometry onto the same z=0 UI plane used by pointer events. */
    projectWorld(point: Vec3) {
        if (!this.playerPlane) return point;
        const center = this.playerPlane.worldPosition, scale = this.eyeDistance / (this.eyeDistance - point.z);
        return new Vec3(center.x + (point.x - center.x) * scale, center.y + (point.y - center.y) * scale, 0);
    }
    /** Intersect the pointer's camera ray with the tilted table. */
    pointerWorld(point: Vec2) {
        if (!this.playerPlane) return new Vec3(point.x, point.y);
        const center = this.playerPlane.worldPosition, dy = point.y - center.y;
        const ratio = this.eyeDistance / (this.eyeDistance - dy * Math.tan(this.playerTilt * Math.PI / 180));
        return new Vec3(center.x + (point.x - center.x) * ratio, center.y + dy * ratio, this.eyeDistance * (1 - ratio));
    }
    pointerOnPlane(point: Vec2) {
        const parent = this.playerPlane || this.node.parent!;
        return parent.getComponent(UITransform)!.convertToNodeSpaceAR(this.pointerWorld(point));
    }
    planeArea(area: { left: number; right: number; bottom: number; top: number }) {
        const center = this.playerPlane?.worldPosition || this.node.parent!.worldPosition;
        const corners: Vec3[] = [];
        for (const y of [area.bottom, area.top]) for (const x of [area.left, area.right]) corners.push(this.pointerOnPlane(new Vec2(center.x + x, center.y + y)));
        return { left: Math.min(...corners.map(p => p.x)), right: Math.max(...corners.map(p => p.x)),
            bottom: Math.min(...corners.map(p => p.y)), top: Math.max(...corners.map(p => p.y)) };
    }
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
        return Math.max((this.planeBounds.right - this.planeBounds.left + 4) / size,
            (this.planeBounds.top - this.planeBounds.bottom + 4) / (size * this.pitch));
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
        if (this.camera && this.playerPlane) {
            this.eyeDistance = h / (2 * Math.tan(this.camera.fov * Math.PI / 360));
            const center = this.playerPlane.worldPosition;
            this.camera.node.setWorldPosition(center.x, center.y, this.eyeDistance);
        }
        this.planeBounds = this.planeArea({ left: -w / 2, right: w / 2, bottom: -h / 2, top: h / 2 });
        this.overviewArea = this.planeArea(area);
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
        const bounds = this.planeBounds;
        this.node.setPosition(this.clampCameraAxis(p.x, size * this.zoom, bounds.left, bounds.right),
            this.clampCameraAxis(p.y + cityY, size * this.zoom * this.pitch, bounds.bottom, bounds.top) - cityY, p.z);
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
    private clampCameraAxis(value: number, imageHalf: number, low: number, high: number) {
        // Keep a small overlap at the image boundary to avoid a raster seam.
        return Math.max(high - imageHalf + 2, Math.min(low + imageHalf - 2, value));
    }
    snapshot() {
        const table = this.node.getChildByName('Table')!, size = table.getComponent(UITransform)!;
        return { cells: this.gridCells, spacing: table.getComponent(Surface)!.gridSpacing, width: size.width, height: size.height,
            cityLoaded: !!this.city, cityWidth: this.boardSize * 2, cityHeight: this.boardSize * 2,
            imagePixels: this.city?.getComponent(Sprite)!.spriteFrame?.originalSize,
            table: { x: table.position.x, y: table.position.y, borderWidth: table.getComponent(Surface)!.lineWidth },
            minimumZoom: this.minimumZoom, overviewArea: this.overviewArea,
            perspective: { tilt: this.playerTilt, fov: this.camera?.fov, eyeDistance: this.eyeDistance },
            tint: this.shade?.getComponent(Surface)!.fill, tintParent: this.shade?.parent?.name,
            edgeFade: { width: table.getComponent(Surface)!.gridSpacing, bands: 128, active: !!this.edgeFade, parent: this.edgeFade?.node.parent?.name },
            nightShift: this.night?.snapshot() || { enabled: false },
            cameraLimitedToCity: true };
    }
}
