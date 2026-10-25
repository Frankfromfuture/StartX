import { Color, EffectAsset, Font, instantiate, Label, Mask, Material, Node, Prefab, Sprite, SpriteFrame, UITransform, Vec2, Vec3, Vec4 } from 'cc';
import { CardView, cardStyle } from './CardView';
import { CardFrameVolume, PACK_DEPTH_RATIO } from './CardFrameVolume';
import { INSPECTOR_CONTENT_SCALE, INSPECTOR_SCREEN_SIZE, LayoutMetrics } from './Layout';
import { DIMMED_BACKGROUND_COLOR, Surface } from './Surface';
import { Catalog, GameModel, quoteFlavor, Recipe } from './GameModel';
import { roundCard } from './RoundedCard';

type CardStyle = 'plain' | 'foil' | 'glass' | 'pack';
interface PreviewContent { frame: SpriteFrame | null; bodyColor: string; style: CardStyle; functionText: string; description: string; pack: boolean; }
interface CardReference { id: string; data: Catalog; packs: string[]; recipes: Recipe[]; }
interface PreviewHistory { content: PreviewContent; reference: CardReference | null; patch: CardView['numberPatch']; yarn: CardView['yarnDecorations']; offset: number; yaw: number; pitch: number; }

/** A modal card turntable, separate from the board and its card animations. */
export class CardInspector {
    readonly node: Node;
    readonly cardNode: Node;
    readonly closeNode: Node;
    readonly detailsNode: Node;
    pending = 0;
    private shade: Node;
    private front: CardView;
    private back: Node;
    private frameVolume: CardFrameVolume;
    private backMaterial: Material | null;
    private functionLabel: Label;
    private descriptionLabel: Label;
    private detailsContent: Node;
    private referenceNode: Node;
    private reference: CardReference | null = null;
    private iconFrames = new Map<string, Promise<SpriteFrame>>();
    private iconButtons: { id: string; node: Node }[] = [];
    private lineMaterial: Material;
    private packLineMaterial: Material;
    private current: PreviewContent | null = null;
    private history: PreviewHistory[] = [];
    private navigationRequest = 0;
    private navigating = false;
    private referenceGeneration = 0;
    private detailsOffset = 0;
    private detailsMaximum = 0;
    private detailsDragging = false;
    private metrics!: LayoutMetrics;
    private scale = 1;
    private size = 280;
    private yaw = 0;
    private pitch = 0;
    private targetYaw = 0;
    private targetPitch = 0;
    private backVisible = false;

    constructor(parent: Node, private font: Font, prefab: Prefab, backFrame: SpriteFrame, lineEffect: EffectAsset, private loadFrame: (path: string) => Promise<SpriteFrame>) {
        this.lineMaterial = new Material(); this.lineMaterial.initialize({ effectAsset: lineEffect });
        this.packLineMaterial = new Material(); this.packLineMaterial.initialize({ effectAsset: lineEffect });
        this.packLineMaterial.setProperty('lineMode', new Vec4(1, 0, 0, 0));
        this.node = this.make('CardInspector', parent, 720, 1280);
        this.shade = this.make('DimmedBackground', this.node, 720, 1280);
        const shade = this.shade.addComponent(Surface); shade.fill = DIMMED_BACKGROUND_COLOR.clone(); shade.radius = 0; shade.paint();
        this.cardNode = this.make('Turntable', this.node, 280, 280);
        this.frameVolume = new CardFrameVolume(this.node);
        this.frameVolume.node.setSiblingIndex(this.cardNode.getSiblingIndex() - 1);
        const card = instantiate(prefab); card.name = 'EnlargedCard'; this.cardNode.addChild(card); this.front = card.getComponent(CardView)!;
        this.front.setInspectionMode(true);
        this.back = this.make('CardBack', this.cardNode, 280, 280);
        const back = this.make('Artwork', this.back, 280, 280).addComponent(Sprite); back.spriteFrame = backFrame; back.sizeMode = Sprite.SizeMode.CUSTOM;
        this.backMaterial = this.front.createInspectionMaterial(); back.customMaterial = this.backMaterial;
        this.back.setRotationFromEuler(0, 180, 0); this.back.active = false;
        this.detailsNode = this.make('DetailsViewport', this.node, 680, 600); this.detailsNode.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
        this.detailsContent = this.make('Content', this.detailsNode, 680, 600);
        this.referenceNode = this.make('CardReference', this.detailsContent, 680, 600);
        this.functionLabel = this.text('Function', font, 26, new Color(255, 242, 204));
        this.descriptionLabel = this.text('Description', font, 21, new Color(245, 245, 243));
        this.functionLabel.enableWrapText = false;
        this.closeNode = this.text('Close', font, 36, new Color(255, 255, 255), this.node).node;
        this.closeNode.getComponent(Label)!.string = '×';
        this.node.active = false;
    }
    private make(name: string, parent: Node, width: number, height: number) {
        const node = new Node(name); node.layer = parent.layer; parent.addChild(node);
        node.addComponent(UITransform).setContentSize(width, height); return node;
    }
    private text(name: string, font: Font, size: number, color: Color, parent = this.detailsContent) {
        const node = this.make(name, parent, 640, 80), label = node.addComponent(Label);
        label.font = font; label.fontSize = size; label.lineHeight = size * 1.4; label.color = color;
        label.horizontalAlign = Label.HorizontalAlign.CENTER; label.verticalAlign = Label.VerticalAlign.CENTER;
        label.overflow = Label.Overflow.SHRINK; label.enableWrapText = true; return label;
    }
    present(source: CardView, bodyColor: string, style: 'plain' | 'foil' | 'glass' | 'pack', functionText: string, description: string) {
        this.presentFrame(source.artwork, bodyColor, style, functionText, description, source.pack);
        const patch = source.numberPatch; this.front.setPatch(patch.frame, patch.kind);
        if (source.isBadgeToken) this.front.setBadgeToken(true);
        const yarn = source.yarnDecorations;
        if (yarn) this.front.setYarnBadges(yarn.frames, yarn.bonus, yarn.capacity, this.font, yarn.positions);
    }
    presentFrame(frame: SpriteFrame | null, bodyColor: string, style: CardStyle, functionText: string, description: string, pack = false, keepHistory = false) {
        if (!keepHistory) this.history = [];
        this.navigationRequest++; this.current = { frame, bodyColor, style, functionText, description, pack };
        this.front.configure(frame, bodyColor, style); this.front.setPatch(null, 'uses');
        if (frame?.name.startsWith('badge_')) this.front.setBadgeToken(true);
        this.front.setYarnBadges([], 0, 0, this.font);
        this.functionLabel.string = functionText; this.descriptionLabel.string = pack ? description : quoteFlavor(description);
        this.yaw = this.targetYaw = -10; this.pitch = this.targetPitch = -8;
        this.front.node.setScale(this.size / (pack ? 336 : 280), this.size / (pack ? 336 : 280), 1);
        this.reference = null; this.detailsOffset = 0; this.layoutDetails();
        this.tick(0);
    }
    setReference(model: GameModel, id: string) {
        const data = model.data;
        const recipes = data.recipes.filter(r => r.outputs.some(o => o.id === id || id === 'cash' && o.cash != null));
        this.reference = { id, data, packs: model.cardPacks(id), recipes }; this.detailsOffset = 0; this.layoutDetails();
    }
    async openCard(model: GameModel, id: string) {
        if (this.navigating || !this.current || !model.data.cards[id] || this.reference?.id === id) return;
        const saved: PreviewHistory = { content: this.current, reference: this.reference, patch: this.front.numberPatch, yarn: this.front.yarnDecorations,
            offset: this.detailsOffset, yaw: this.yaw, pitch: this.pitch };
        const request = ++this.navigationRequest; this.navigating = true; this.pending++;
        try {
            const frame = await this.loadFrame('faces/' + id);
            if (!this.node.activeInHierarchy || request !== this.navigationRequest) return;
            const d = model.def(id); this.history.push(saved);
            this.presentFrame(frame, d.bodyColor, cardStyle(id, d.type),
                d.functionText || '与其他卡牌叠放，发现商业模式', d.flavor || '', false, true);
            this.setReference(model, id);
        } catch (e) { console.error('[StartX] Recipe preview', e); }
        finally { this.navigating = false; this.pending--; }
    }
    goBack() {
        const saved = this.history.pop(); if (!saved) { this.navigationRequest++; return false; }
        const c = saved.content;
        this.presentFrame(c.frame, c.bodyColor, c.style, c.functionText, c.description, c.pack, true);
        this.front.setPatch(saved.patch.frame, saved.patch.kind);
        if (saved.yarn) this.front.setYarnBadges(saved.yarn.frames, saved.yarn.bonus, saved.yarn.capacity, this.font, saved.yarn.positions);
        this.reference = saved.reference; this.detailsOffset = saved.offset; this.layoutDetails();
        this.yaw = this.targetYaw = saved.yaw; this.pitch = this.targetPitch = saved.pitch; this.tick(0); return true;
    }
    private icon(id: string, pack = false) {
        const key = (pack ? 'pack:' : 'card:') + id;
        let icon = this.iconFrames.get(key);
        if (!icon) {
            icon = this.loadFrame((pack ? 'pack-icons/' : 'icons/') + id);
            this.iconFrames.set(key, icon);
        }
        return icon;
    }
    private layoutDetails() {
        if (!this.metrics) return;
        const s = this.scale, view = this.detailsNode.getComponent(UITransform)!, width = view.width - 16 * s;
        let y = view.height / 2 - 4 * s;
        const generation = ++this.referenceGeneration;
        this.iconButtons = [];
        this.referenceNode.children.slice().forEach(n => { n.active = false; n.destroy(); });
        this.functionLabel.node.setPosition(0, y - 22 * s); this.functionLabel.node.getComponent(UITransform)!.setContentSize(width, 44 * s);
        y -= 48 * s;
        this.descriptionLabel.node.active = !!this.descriptionLabel.string;
        if (this.descriptionLabel.string) {
            this.descriptionLabel.overflow = Label.Overflow.RESIZE_HEIGHT;
            this.descriptionLabel.node.getComponent(UITransform)!.setContentSize(width, 1); this.descriptionLabel.updateRenderData(true);
            const height = this.descriptionLabel.node.getComponent(UITransform)!.height;
            this.descriptionLabel.node.setPosition(0, y - height / 2); y -= height + 12 * s;
        }
        const ref = this.reference;
        if (ref) {
            const heading = (name: string, value: string) => {
                const label = this.text(name, this.font, 18 * s, Color.WHITE.clone(), this.referenceNode); label.string = value;
                label.node.getComponent(UITransform)!.setContentSize(width, 28 * s); label.node.setPosition(0, y - 14 * s); y -= 38 * s;
            };
            if (ref.recipes.length) heading('RecipeHeading', '产出配方：');
            for (const recipe of ref.recipes) {
                type Term = { id: string; count: number; name?: string };
                const inputs: Term[] = recipe.inputs.map(i => ({ id: i.id, count: i.count }));
                if (recipe.worker_tags.includes('any')) inputs.unshift({ id: 'founder', count: 1, name: '任意员工' });
                const outputs: Term[] = recipe.outputs.map(o => ({ id: o.cash != null ? 'cash' : o.id, count: o.cash ?? o.count }));
                const tokens: (Term | string)[] = [];
                inputs.forEach((t, i) => { if (i) tokens.push('+'); tokens.push(t); }); tokens.push('→');
                outputs.forEach((t, i) => { if (i) tokens.push('+'); tokens.push(t); });
                const total = tokens.reduce<number>((sum, t) => sum + (typeof t === 'string' ? 18 : 64), 0), fit = Math.min(1, (width - 18 * s) / (total * s)), u = s * fit;
                let x = -total * u / 2;
                for (const t of tokens) {
                    if (typeof t === 'string') {
                        const l = this.text('Operator', this.font, 20 * u, Color.WHITE.clone(), this.referenceNode); l.string = t;
                        l.node.getComponent(UITransform)!.setContentSize(18 * u, 44 * u); l.node.setPosition(x + 9 * u, y - 22 * u); x += 18 * u; continue;
                    }
                    const iconNode = this.make('RecipeIcon-' + t.id, this.referenceNode, 40 * u, 40 * u); iconNode.setPosition(x + 23 * u, y - 22 * u);
                    this.iconButtons.push({ id: t.id, node: iconNode });
                    const sprite = iconNode.addComponent(Sprite); sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.customMaterial = this.lineMaterial; this.pending++;
                    this.icon(t.id).then(frame => { if (iconNode.isValid && generation === this.referenceGeneration) sprite.spriteFrame = frame; })
                        .catch(e => console.error('[StartX] Recipe icon', e)).then(() => this.pending--);
                    const amount = this.text('Amount', this.font, 14 * u, Color.WHITE.clone(), this.referenceNode); amount.string = '×' + t.count;
                    amount.node.getComponent(UITransform)!.setContentSize(24 * u, 32 * u); amount.node.setPosition(x + 53 * u, y - 22 * u);
                    const name = this.text('Ingredient', this.font, 11 * u, new Color(236, 235, 228), this.referenceNode); name.string = t.name || ref.data.cards[t.id].name;
                    name.node.getComponent(UITransform)!.setContentSize(64 * u, 20 * u); name.node.setPosition(x + 23 * u, y - 55 * u); x += 64 * u;
                }
                y -= 70 * u + 8 * s;
            }
            if (ref.packs.length) {
                if (ref.recipes.length) y -= 12 * s;
                heading('PackHeading', '可从以下卡包抽到：');
                const columns = Math.max(1, Math.min(ref.packs.length, 5, Math.floor(width / (100 * s))));
                const gap = 12 * s, cellW = Math.min(132 * s, (width - (columns - 1) * gap) / columns), rowW = columns * cellW + (columns - 1) * gap;
                ref.packs.forEach((id, index) => {
                    const x = -rowW / 2 + cellW / 2 + index % columns * (cellW + gap), rowY = y - Math.floor(index / columns) * 92 * s;
                    const n = this.make('PackIcon-' + id, this.referenceNode, 40 * s, 40 * s); n.setPosition(x, rowY - 22 * s);
                    const sprite = n.addComponent(Sprite); sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.trim = false; sprite.customMaterial = this.packLineMaterial; this.pending++;
                    this.icon(id, true).then(frame => {
                        if (!n.isValid || generation !== this.referenceGeneration) return;
                        const original = frame.originalSize, fit = 40 * s / Math.max(original.width, original.height);
                        n.getComponent(UITransform)!.setContentSize(original.width * fit, original.height * fit); sprite.spriteFrame = frame;
                    })
                        .catch(e => console.error('[StartX] Pack icon', e)).then(() => this.pending--);
                    const label = this.text('PackName-' + id, this.font, 14 * s, Color.WHITE.clone(), this.referenceNode); label.string = ref.data.packs[id].name;
                    label.lineHeight = 18 * s; label.node.getComponent(UITransform)!.setContentSize(cellW - 8 * s, 36 * s); label.node.setPosition(x, rowY - 64 * s);
                });
                y -= Math.ceil(ref.packs.length / columns) * 92 * s;
            }
        }
        this.detailsMaximum = Math.max(0, view.height / 2 - y + 8 * s - view.height); this.scrollDetails(0);
    }
    layout(metrics: LayoutMetrics) {
        const { width: w, height: h, top, bottom } = metrics, scale = metrics.scale * INSPECTOR_CONTENT_SCALE;
        this.scale = scale; this.metrics = metrics;
        this.node.getComponent(UITransform)!.setContentSize(w, h);
        this.shade.getComponent(UITransform)!.setContentSize(w, h);
        this.size = INSPECTOR_SCREEN_SIZE * metrics.scale;
        this.cardNode.getComponent(UITransform)!.setContentSize(this.size, this.size);
        const landscape = w > h, columnGap = 40 * metrics.scale;
        const detailsW = Math.min(350 * scale, w - this.size - columnGap - 64 * metrics.scale);
        this.cardNode.setPosition(landscape ? -(detailsW + columnGap) / 2 : 0, landscape ? (bottom - top) / 2 : h * .2);
        this.frameVolume.node.setPosition(this.cardNode.position);
        this.front.node.setPosition(0, 0, this.size * .035 / 2);
        this.back.setPosition(0, 0, -this.size * .035 / 2);
        const faceScale = this.size / (this.front.pack ? 336 : 280); this.front.node.setScale(faceScale, faceScale, 1);
        this.back.getComponent(UITransform)!.setContentSize(this.size, this.size);
        this.back.getChildByName('Artwork')!.getComponent(UITransform)!.setContentSize(this.size, this.size); roundCard(this.back, this.size);
        const detailsTop = this.cardNode.position.y - this.size / 2 - 10 * scale, detailsBottom = -h / 2 + bottom + 20 * scale;
        this.detailsNode.getComponent(UITransform)!.setContentSize(landscape ? detailsW : Math.min(w - 40 * scale, 350 * scale),
            landscape ? Math.max(40 * scale, h - top - bottom - 64 * metrics.scale) : Math.max(40 * scale, detailsTop - detailsBottom));
        this.detailsNode.setPosition(landscape ? (this.size + columnGap) / 2 : 0, landscape ? (bottom - top) / 2 : (detailsTop + detailsBottom) / 2);
        this.functionLabel.fontSize = 26 * scale; this.functionLabel.lineHeight = 36 * scale;
        this.descriptionLabel.fontSize = 21 * scale; this.descriptionLabel.lineHeight = 29 * scale;
        this.closeNode.setPosition(w / 2 - 36 * scale, h / 2 - top - 36 * scale);
        const closeTarget = Math.max(44 * metrics.scale, 52 * scale);
        this.closeNode.getComponent(UITransform)!.setContentSize(closeTarget, closeTarget);
        const close = this.closeNode.getComponent(Label)!; close.fontSize = 36 * scale; close.lineHeight = 48 * scale;
        this.layoutDetails();
    }
    contains(point: Vec2) {
        const p = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(point.x, point.y));
        return Math.abs(p.x - this.cardNode.position.x) <= this.size * .64 && Math.abs(p.y - this.cardNode.position.y) <= this.size * .64;
    }
    containsDetails(point: Vec2) {
        const p = this.detailsNode.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(point.x, point.y)), t = this.detailsNode.getComponent(UITransform)!;
        return Math.abs(p.x) <= t.width / 2 && Math.abs(p.y) <= t.height / 2;
    }
    badgeAt(point: Vec2) { return !this.backVisible && !this.history.length ? this.front.badgeAt(point) : -1; }
    containsFace(point: Vec2) { return this.front.containsFace(point); }
    badgePositionAt(point: Vec2) { return this.front.badgePositionAt(point); }
    addBadge(frame: SpriteFrame, position: { x: number; y: number }, capacity: number, functionText: string) {
        const yarn = this.front.yarnDecorations;
        this.front.setYarnBadges((yarn?.frames || []).concat(frame), (yarn?.bonus || 0) + 1, capacity, this.font, (yarn?.positions || []).concat(position));
        this.functionLabel.string = functionText; if (this.current) this.current.functionText = functionText;
    }
    removeBadge(index: number, capacity: number, functionText: string) {
        const yarn = this.front.yarnDecorations; if (!yarn) return;
        this.front.setYarnBadges(yarn.frames.filter((_, i) => i !== index), yarn.bonus - 1, capacity, this.font, yarn.positions.filter((_, i) => i !== index));
        this.functionLabel.string = functionText; if (this.current) this.current.functionText = functionText;
    }
    iconAt(point: Vec2) {
        if (!this.containsDetails(point)) return '';
        return this.iconButtons.find(({ node }) => {
            const t = node.getComponent(UITransform)!, p = t.convertToNodeSpaceAR(new Vec3(point.x, point.y));
            return node.activeInHierarchy && Math.abs(p.x) <= t.width / 2 && Math.abs(p.y) <= t.height / 2;
        })?.id || '';
    }
    begin(point: Vec2) { this.detailsDragging = this.containsDetails(point); }
    dragDetails(delta: Vec2) { if (this.detailsDragging) this.scrollDetails(delta.y); }
    end() { this.detailsDragging = false; }
    wheel(point: Vec2, delta: number) { if (!this.containsDetails(point)) return false; this.scrollDetails(-delta * .2 * this.scale); return true; }
    private scrollDetails(delta: number) { this.detailsOffset = Math.max(0, Math.min(this.detailsMaximum, this.detailsOffset + delta)); this.detailsContent.setPosition(0, this.detailsOffset); }
    drag(delta: Vec2) {
        this.targetYaw -= delta.x / this.metrics.scale * .75;
        this.targetPitch = Math.max(-40, Math.min(40, this.targetPitch + delta.y / this.metrics.scale * .42));
    }
    flip() { this.targetYaw += 180; }
    tick(dt: number) {
        if (!this.node.active) return;
        const response = dt ? 1 - Math.exp(-18 * Math.min(dt, .05)) : 1;
        this.yaw += (this.targetYaw - this.yaw) * response; this.pitch += (this.targetPitch - this.pitch) * response;
        this.cardNode.setRotationFromEuler(this.pitch, this.yaw, 0);
        this.backVisible = Math.cos(this.yaw * Math.PI / 180) * Math.cos(this.pitch * Math.PI / 180) < 0;
        this.front.node.active = !this.backVisible; this.back.active = this.backVisible;
        this.front.setInspectionAngles(this.pitch, this.yaw);
        this.backMaterial?.setProperty('inspectionLight', this.front.inspectionLighting);
        if (this.current?.pack) this.frameVolume.paintPack(this.size, this.pitch, this.yaw, false);
        else this.frameVolume.paint(this.size, this.size * .035, this.pitch, this.yaw, this.front.frameColor);
    }
    snapshot() { return { active: this.node.active, yaw: this.yaw, pitch: this.pitch, back: this.backVisible,
        size: this.size, depth: this.size * (this.current?.pack ? PACK_DEPTH_RATIO : .035), frame: this.frameVolume.snapshot(), lighting: !!this.backMaterial,
        functionText: this.functionLabel.string, description: this.descriptionLabel.string, shadeAlpha: DIMMED_BACKGROUND_COLOR.a, pending: this.pending,
        reference: this.reference ? { id: this.reference.id, packs: this.reference.packs, recipes: this.reference.recipes.map(r => r.id), icons: this.referenceNode.children.filter(n => n.name.startsWith('RecipeIcon-')).length } : null,
        detailsOffset: this.detailsOffset, detailsMaximum: this.detailsMaximum, roundedBack: !!this.back.getComponent(Mask), historyDepth: this.history.length,
        iconButtons: this.iconButtons.map(({ id, node }) => {
            const t = node.getComponent(UITransform)!, p = t.convertToWorldSpaceAR(new Vec3(-t.width / 2, t.height / 2));
            return { id, x: p.x / this.metrics.scale, y: (this.metrics.height - p.y) / this.metrics.scale, width: t.width / this.metrics.scale, height: t.height / this.metrics.scale };
        }) }; }
    destroy() { this.navigationRequest++; this.history = []; this.lineMaterial.destroy(); this.packLineMaterial.destroy(); }
}
