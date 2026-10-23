import { Camera, Color, director, Director, EffectAsset, Font, Graphics, Label, Mask, Material, Node, RenderTexture, Sprite, SpriteFrame, UITransform, Vec2, Vec3, Vec4 } from 'cc';
import { GameModel } from './GameModel';
import { LayoutMetrics } from './Layout';
import { Surface } from './Surface';
import { roundCard } from './RoundedCard';

type Sort = 'rarity' | 'type' | 'name';
interface Cell { id: string; node: Node; sprite: Sprite; unlocked: boolean; }

/** A clipped collection of original card faces; undiscovered cards only load the shared back. */
export class CardCatalog {
    readonly node: Node;
    pending = 0;
    private background: Node;
    private viewport: Node;
    private content: Node;
    private title: Label;
    private count: Label;
    private close: Node;
    private buttons = new Map<Sort, Node>();
    private cells: Cell[] = [];
    private frames = new Map<string, SpriteFrame>();
    private model!: GameModel;
    private metrics!: LayoutMetrics;
    private sort: Sort = 'rarity';
    private offset = 0;
    private maximum = 0;
    private columns = 1;
    private dragging = false;
    private generation = 0;
    private opened = false;
    private texture = new RenderTexture();
    private capturedFrame = new SpriteFrame();
    private blur: Material;
    private captureCamera: Camera | null = null;
    private previousTarget: RenderTexture | null = null;
    private finishCapture = () => {
        if (this.captureCamera?.isValid) this.captureCamera.targetTexture = this.previousTarget;
        this.captureCamera = null;
        if (this.opened) {
            this.node.active = true;
            // Capture hides the overlay for a frame, so transform change flags may expire before its graphics render.
            this.node.getComponentsInChildren(Graphics).forEach(graphics => graphics.model?.updateWorldBound());
        }
    };

    constructor(parent: Node, private font: Font, private back: SpriteFrame, effect: EffectAsset,
        private loadFrame: (path: string) => Promise<SpriteFrame>, private reportError: (error: unknown) => void) {
        this.node = this.make('CardCatalog', parent, 720, 1280);
        this.background = this.make('BlurredBackground', this.node, 720, 1280);
        this.texture.initialize({ width: 16, height: 16 });
        this.capturedFrame.texture = this.texture; this.capturedFrame.flipUVY = true;
        const sprite = this.background.addComponent(Sprite); sprite.spriteFrame = this.capturedFrame; sprite.sizeMode = Sprite.SizeMode.CUSTOM;
        this.blur = new Material(); this.blur.initialize({ effectAsset: effect }); sprite.customMaterial = this.blur;
        this.title = this.text('Title', this.node, '卡牌图鉴', 26);
        this.count = this.text('UnlockedCount', this.node, '', 18);
        this.close = this.text('Close', this.node, '×', 34).node;
        this.close.getComponent(Label)!.horizontalAlign = Label.HorizontalAlign.CENTER;
        for (const [key, text] of [['rarity', '稀有度'], ['type', '类型'], ['name', '名称']] as const) {
            const n = this.make('Sort-' + key, this.node, 100, 40);
            const surface = n.addComponent(Surface); surface.stroke = new Color(31, 28, 25);
            const label = this.text('Text', n, text, 18); label.color = new Color(31, 28, 25); label.horizontalAlign = Label.HorizontalAlign.CENTER;
            this.buttons.set(key, n);
        }
        this.viewport = this.make('GridViewport', this.node, 680, 1000); this.viewport.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
        this.content = this.make('Cards', this.viewport, 680, 1000);
        this.node.active = false;
    }
    private make(name: string, parent: Node, width: number, height: number) {
        const n = new Node(name); n.layer = parent.layer; parent.addChild(n); n.addComponent(UITransform).setContentSize(width, height); return n;
    }
    private text(name: string, parent: Node, value: string, font: number) {
        const n = this.make(name, parent, 300, 40), l = n.addComponent(Label);
        l.font = this.font; l.fontSize = font; l.lineHeight = font * 1.3; l.string = value;
        l.color = new Color(255, 247, 228); l.verticalAlign = Label.VerticalAlign.CENTER;
        l.horizontalAlign = Label.HorizontalAlign.LEFT; l.enableWrapText = false; l.overflow = Label.Overflow.SHRINK; return l;
    }
    open(model: GameModel, metrics: LayoutMetrics) {
        this.model = model; this.opened = true; this.offset = 0;
        this.rebuild(); this.layout(metrics);
    }
    cancelCapture() {
        if (!this.captureCamera) return;
        director.off(Director.EVENT_AFTER_DRAW, this.finishCapture); this.finishCapture();
    }
    hide() { this.opened = false; this.cancelCapture(); this.node.active = false; this.dragging = false; }
    capture(camera: Camera) {
        if (this.captureCamera) return;
        this.node.active = false;
        const { width, height, scale } = this.metrics, ratio = Math.min(1, 768 / Math.max(width / scale, height / scale));
        this.texture.resize(Math.max(1, Math.round(width / scale * ratio)), Math.max(1, Math.round(height / scale * ratio)));
        this.capturedFrame.reset({ texture: this.texture }, true); this.capturedFrame.flipUVY = true;
        this.captureCamera = camera; this.previousTarget = camera.targetTexture;
        camera.targetTexture = this.texture;
        director.once(Director.EVENT_AFTER_DRAW, this.finishCapture);
    }
    layout(metrics: LayoutMetrics) {
        this.metrics = metrics;
        const { width: w, height: h, scale: s, top, bottom } = metrics;
        const margin = Math.max(32 * s, Math.min(w, h) * .08), width = w - margin * 2, headerH = 108 * s;
        this.node.getComponent(UITransform)!.setContentSize(w, h); this.background.getComponent(UITransform)!.setContentSize(w, h);
        this.blur.setProperty('blurStep', new Vec4(6 * s / w, 6 * s / h, .94, .42));
        const topY = h / 2 - top - margin;
        this.title.node.setPosition(-width / 2, topY - 18 * s);
        this.title.fontSize = 26 * s; this.title.lineHeight = 34 * s;
        this.title.node.getComponent(UITransform)!.setContentSize(width, 36 * s); this.title.node.getComponent(UITransform)!.setAnchorPoint(0, .5);
        this.count.fontSize = 18 * s; this.count.lineHeight = 24 * s;
        this.count.node.getComponent(UITransform)!.setContentSize(Math.min(200 * s, width * .54), 28 * s);
        this.count.node.getComponent(UITransform)!.setAnchorPoint(1, .5); this.count.horizontalAlign = Label.HorizontalAlign.RIGHT;
        this.count.node.setPosition(width / 2 - 42 * s, topY - 18 * s);
        this.close.getComponent(UITransform)!.setContentSize(40 * s, 40 * s); this.close.setPosition(width / 2 - 15 * s, topY - 18 * s);
        const close = this.close.getComponent(Label)!; close.fontSize = 34 * s; close.lineHeight = 40 * s;
        const buttonGap = 10 * s, buttonW = Math.min(140 * s, (width - buttonGap * 2) / 3), rowW = buttonW * 3 + buttonGap * 2;
        let i = 0;
        for (const [key, n] of this.buttons) {
            n.setPosition(-rowW / 2 + buttonW / 2 + i++ * (buttonW + buttonGap), topY - 72 * s);
            n.getComponent(UITransform)!.setContentSize(buttonW, 40 * s);
            const surface = n.getComponent(Surface)!; surface.fill = key === this.sort ? new Color(255, 213, 74) : new Color(252, 248, 238);
            surface.lineWidth = 2 * s; surface.radius = 5 * s; surface.paint();
            const label = n.getChildByName('Text')!.getComponent(Label)!; label.fontSize = 18 * s; label.lineHeight = 24 * s;
            label.node.getComponent(UITransform)!.setContentSize(buttonW - 12 * s, 34 * s);
        }
        const viewH = Math.max(1, h - top - bottom - margin * 2 - headerH);
        this.viewport.getComponent(UITransform)!.setContentSize(width, viewH); this.viewport.setPosition(0, topY - headerH - viewH / 2);
        const gap = 20 * s, size = 280 * .4 * s;
        this.columns = Math.max(1, Math.floor((width + gap) / (size + gap)));
        const gridW = this.columns * size + (this.columns - 1) * gap;
        this.cells.forEach((c, index) => {
            c.node.getComponent(UITransform)!.setContentSize(size, size);
            c.sprite.node.getComponent(UITransform)!.setContentSize(size, size); roundCard(c.node, size);
            c.node.setPosition(-gridW / 2 + size / 2 + index % this.columns * (size + gap), viewH / 2 - size / 2 - Math.floor(index / this.columns) * (size + gap));
        });
        const rows = Math.ceil(this.cells.length / this.columns);
        this.maximum = Math.max(0, rows * (size + gap) - gap - viewH); this.scroll(0);
    }
    private rarity(id: string) {
        if (id === 'founder') return 100;
        let stage = Infinity, chance = 0;
        this.model.data.packOrder.forEach((pack, index) => {
            for (const slot of this.model.data.packs[pack].slots) {
                const option = slot.find(o => o.id === id); if (!option || index > stage) continue;
                if (index < stage) { stage = index; chance = 0; }
                chance = Math.max(chance, option.w / slot.reduce((sum, o) => sum + o.w, 0));
            }
        });
        if (!Number.isFinite(stage)) {
            const recipe = this.model.data.recipes.find(r => 'bm_' + r.id === id || r.outputs.some(o => o.id === id));
            stage = recipe ? Math.max(0, this.model.data.packOrder.indexOf(recipe.packId)) : 0;
        }
        return stage + (1 - chance) * .9;
    }
    private rebuild() {
        const generation = ++this.generation, data = this.model.data, types = ['employee', 'facility', 'resource', 'tool', 'customer', 'product', 'cash', 'business_model', 'rival'];
        this.cells.forEach(c => { c.node.active = false; c.node.destroy(); });
        const ids = Object.keys(data.cards).sort((a, b) => {
            const lockedOrder = Number(this.model.drawn.has(b)) - Number(this.model.drawn.has(a));
            if (lockedOrder) return lockedOrder;
            const order = this.sort === 'rarity' ? this.rarity(b) - this.rarity(a) : this.sort === 'type' ? types.indexOf(data.cards[a].type) - types.indexOf(data.cards[b].type) : 0;
            return order || data.cards[a].name.localeCompare(data.cards[b].name, 'zh-Hans-CN') || a.localeCompare(b);
        });
        this.count.string = `已解锁 ${ids.filter(id => this.model.drawn.has(id)).length} / ${ids.length}`;
        this.cells = ids.map(id => {
            const node = this.make('Card-' + id, this.content, 140, 140), image = this.make('Artwork', node, 140, 140), sprite = image.addComponent(Sprite), unlocked = this.model.drawn.has(id);
            sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.spriteFrame = this.back;
            if (unlocked) {
                const cached = this.frames.get(id);
                if (cached) sprite.spriteFrame = cached;
                else {
                    this.pending++;
                    this.loadFrame('faces/' + id).then(frame => {
                        this.frames.set(id, frame);
                        if (node.isValid && generation === this.generation) sprite.spriteFrame = frame;
                    }).catch(this.reportError).then(() => this.pending--);
                }
            }
            return { id, node, sprite, unlocked };
        });
    }
    setSort(sort: string) {
        if (!['rarity', 'type', 'name'].includes(sort) || sort === this.sort) return;
        this.sort = sort as Sort; this.offset = 0; this.rebuild(); this.layout(this.metrics);
    }
    frame(id: string) { return this.model.drawn.has(id) ? this.frames.get(id) : undefined; }
    private hit(n: Node, p: Vec2) {
        const t = n.getComponent(UITransform)!, v = t.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        return n.activeInHierarchy && Math.abs(v.x) <= t.width / 2 && Math.abs(v.y) <= t.height / 2;
    }
    actionAt(p: Vec2) {
        if (!this.node.activeInHierarchy) return 'Noop';
        if (this.hit(this.close, p)) return 'CatalogClose';
        for (const [sort, n] of this.buttons) if (this.hit(n, p)) return 'CatalogSort:' + sort;
        if (this.hit(this.viewport, p)) {
            const c = this.cells.find(c => this.hit(c.node, p));
            return c?.unlocked && this.frame(c.id) ? 'CatalogCard:' + c.id : 'Noop';
        }
        const local = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        const size = this.viewport.getComponent(UITransform)!;
        return Math.abs(local.x) > size.width / 2 || local.y < this.viewport.position.y - size.height / 2 ? 'CatalogClose' : 'Noop';
    }
    begin(p: Vec2) { this.dragging = this.hit(this.viewport, p); }
    drag(delta: Vec2) { if (this.dragging) this.scroll(delta.y); }
    end() { this.dragging = false; }
    wheel(p: Vec2, delta: number) { if (!this.hit(this.viewport, p)) return false; this.scroll(-delta * .2 * this.metrics.scale); return true; }
    private scroll(delta: number) { this.offset = Math.max(0, Math.min(this.maximum, this.offset + delta)); this.content.setPosition(0, this.offset); }
    snapshot() {
        const bounds = (n: Node) => {
            const t = n.getComponent(UITransform)!, a = t.convertToWorldSpaceAR(new Vec3(-t.width * t.anchorX, -t.height * t.anchorY));
            return { x: a.x / this.metrics.scale, y: (this.metrics.height - a.y - t.height) / this.metrics.scale, width: t.width / this.metrics.scale, height: t.height / this.metrics.scale };
        };
        return { active: this.node.activeInHierarchy, pending: this.pending, sort: this.sort, offset: this.offset, maximum: this.maximum, columns: this.columns,
            unlocked: this.model ? this.cells.filter(c => c.unlocked).length : 0, total: this.cells.length, blurred: !!this.blur, capturing: !!this.captureCamera,
            viewport: this.metrics ? bounds(this.viewport) : null,
            controls: this.metrics ? [['CatalogClose', this.close] as const, ...Array.from(this.buttons, ([s, n]) => ['CatalogSort:' + s, n] as const)]
                .reduce((out, [key, n]) => { out[key] = bounds(n); return out; }, {} as Record<string, ReturnType<typeof bounds>>) : {},
            cards: this.metrics ? this.cells.map(c => ({ id: c.id, unlocked: c.unlocked, face: c.sprite.spriteFrame !== this.back, rounded: !!c.node.getComponent(Mask), bounds: bounds(c.node) })) : [] };
    }
    destroy() {
        director.off(Director.EVENT_AFTER_DRAW, this.finishCapture); this.opened = false; this.finishCapture();
        this.capturedFrame.destroy(); this.texture.destroy(); this.blur.destroy();
    }
}
