import { _decorator, Component, input, Input, EventTouch, EventMouse, game, Game, Vec2 } from 'cc';
const { ccclass } = _decorator;

export interface InputTarget {
    inputScale: number;
    press(point: Vec2): 'card' | 'board' | 'ui';
    tap(point: Vec2, kind: string): void;
    hold(point: Vec2): void;
    holdMove?(point: Vec2, delta: Vec2): void;
    dragStart(): void;
    drag(point: Vec2, delta: Vec2): void;
    dragEnd(cancelled: boolean): void;
    pan(delta: Vec2): void;
    zoom(factor: number, point: Vec2): void;
    context(point: Vec2): void;
    canZoom(point: Vec2): boolean;
    uiDrag?(delta: Vec2): void;
    uiScroll?(point: Vec2, delta: number, horizontal?: number): boolean;
    uiDragThreshold?(): number;
    uiEnd?(cancelled: boolean): void;
    hover?(point: Vec2): void;
}

/** Cocos simulates touch for left mouse input; only right click / wheel are separate. */
@ccclass('InputRouter')
export class InputRouter extends Component {
    target!: InputTarget;
    private touches = new Map<number, Vec2>();
    private primary: number | null = null;
    private origin = new Vec2();
    private last = new Vec2();
    private kind = '';
    private elapsed = 0;
    private moved = false;
    private held = false;
    private pinching = false;
    private pinchDistance = 0;
    private pinchCenter = new Vec2();
    private zoomAllowed = false;
    private blurHandler = () => this.cancel();

    onEnable() {
        input.on(Input.EventType.TOUCH_START, this.startTouch, this);
        input.on(Input.EventType.TOUCH_MOVE, this.moveTouch, this);
        input.on(Input.EventType.TOUCH_END, this.endTouch, this);
        input.on(Input.EventType.TOUCH_CANCEL, this.cancel, this);
        input.on(Input.EventType.MOUSE_DOWN, this.mouseDown, this);
        input.on(Input.EventType.MOUSE_MOVE, this.mouseMove, this);
        input.on(Input.EventType.MOUSE_WHEEL, this.wheel, this);
        game.on(Game.EVENT_HIDE, this.cancel, this);
        if (typeof window !== 'undefined') window.addEventListener('blur', this.blurHandler);
    }
    onDisable() {
        input.off(Input.EventType.TOUCH_START, this.startTouch, this);
        input.off(Input.EventType.TOUCH_MOVE, this.moveTouch, this);
        input.off(Input.EventType.TOUCH_END, this.endTouch, this);
        input.off(Input.EventType.TOUCH_CANCEL, this.cancel, this);
        input.off(Input.EventType.MOUSE_DOWN, this.mouseDown, this);
        input.off(Input.EventType.MOUSE_MOVE, this.mouseMove, this);
        input.off(Input.EventType.MOUSE_WHEEL, this.wheel, this);
        game.off(Game.EVENT_HIDE, this.cancel, this);
        if (typeof window !== 'undefined') window.removeEventListener('blur', this.blurHandler);
        this.cancel();
    }
    update(dt: number) {
        if (this.primary === null || this.moved || this.held || this.pinching || this.kind !== 'card') return;
        this.elapsed += dt;
        if (this.elapsed >= 0.45) { this.held = true; this.target.hold(this.last); }
    }
    private startTouch(e: EventTouch) {
        if (!this.target) return;
        const id = e.getID(); if (id == null) return;
        const p = e.getUILocation(); this.touches.set(id, p.clone());
        if (this.touches.size > 1) {
            if (!this.pinching) {
                if (this.moved && this.kind === 'card') this.target.dragEnd(true);
                if (this.kind === 'ui') this.target.uiEnd?.(true);
                this.pinching = true; this.held = true;
                const [a, b] = Array.from(this.touches.values());
                this.pinchDistance = Vec2.distance(a, b);
                this.pinchCenter.set((a.x + b.x) / 2, (a.y + b.y) / 2);
                this.zoomAllowed = this.kind !== 'ui' && this.target.canZoom(a) && this.target.canZoom(b);
            }
            return;
        }
        this.primary = id; this.origin.set(p); this.last.set(p);
        this.elapsed = 0; this.moved = false; this.held = false; this.pinching = false;
        this.kind = this.target.press(p);
    }
    private moveTouch(e: EventTouch) {
        const id = e.getID(); if (id == null || !this.touches.has(id)) return;
        const p = e.getUILocation(); this.touches.set(id, p.clone());
        if (this.pinching) {
            if (this.touches.size >= 2 && this.zoomAllowed) {
                const [a, b] = Array.from(this.touches.values());
                const distance = Vec2.distance(a, b);
                const center = new Vec2((a.x + b.x) / 2, (a.y + b.y) / 2);
                if (this.pinchDistance > 1) this.target.zoom(distance / this.pinchDistance, center);
                this.target.pan(new Vec2(center.x - this.pinchCenter.x, center.y - this.pinchCenter.y));
                this.pinchDistance = distance; this.pinchCenter.set(center);
            }
            return;
        }
        if (id !== this.primary) return;
        const delta = new Vec2(p.x - this.last.x, p.y - this.last.y);
        if (this.held) { this.target.holdMove?.(p, delta); this.last.set(p); return; }
        const threshold = this.kind === 'ui' ? this.target.uiDragThreshold?.() ?? 8 * this.target.inputScale : 8 * this.target.inputScale;
        if (!this.moved && Vec2.distance(this.origin, p) > threshold) {
            this.moved = true;
            if (this.kind === 'card') this.target.dragStart();
            // Retain the UI distance travelled before crossing the drag threshold.
            if (this.kind === 'ui') delta.set(p.x - this.origin.x, p.y - this.origin.y);
        }
        if (this.moved) {
            if (this.kind === 'card') this.target.drag(p, delta);
            else if (this.kind === 'board') this.target.pan(delta);
            else if (this.kind === 'ui') this.target.uiDrag?.(delta);
        }
        this.last.set(p);
    }
    private endTouch(e: EventTouch) {
        const id = e.getID(); if (id == null || !this.touches.has(id)) return;
        this.touches.delete(id);
        if (this.pinching) { if (this.touches.size === 0) this.clear(); return; }
        if (id === this.primary) {
            if (this.moved && this.kind === 'card') this.target.dragEnd(false);
            else if (!this.moved && !this.held) this.target.tap(e.getUILocation(), this.kind);
            if (this.kind === 'ui') this.target.uiEnd?.(false);
            this.clear();
        }
    }
    private mouseDown(e: EventMouse) { if (e.getButton() === EventMouse.BUTTON_RIGHT && this.target) { this.cancel(); this.target.context(e.getUILocation()); } }
    private mouseMove(e: EventMouse) { if (this.primary === null && !this.touches.size) this.target?.hover?.(e.getUILocation()); }
    private wheel(e: EventMouse) {
        if (this.target?.uiScroll?.(e.getUILocation(), e.getScrollY(), e.getScrollX())) return;
        if (this.target?.canZoom(e.getUILocation())) this.target.zoom(Math.exp(e.getScrollY() * 0.001), e.getUILocation());
    }
    cancel() {
        if (this.moved && this.kind === 'card' && this.target && !this.pinching) this.target.dragEnd(true);
        if (this.kind === 'ui') this.target?.uiEnd?.(true);
        this.clear();
    }
    private clear() { this.touches.clear(); this.primary = null; this.kind = ''; this.moved = false; this.held = false; this.pinching = false; }
}
