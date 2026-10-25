import { Color, Font, Graphics, Label, LabelOutline, Node, Sprite, SpriteFrame, UITransform, Vec2, Vec3 } from 'cc';
import { LayoutMetrics } from './Layout';
import { Surface } from './Surface';
import { viewShadowOffset } from './ViewShadow';

const ink = '281A26', cream = 'FFF4D7', gold = 'FFD54A';
const color = (hex: string) => Color.fromHEX(new Color(), '#' + hex);

/** Office-window title screen with responsive controls and hand-drawn button edges. */
export class TitleScreen {
    readonly node: Node;
    private background: Node;
    private content: Node;
    private heading: Node;
    private subtitle: Node;
    private start: Node;
    private resume: Node;
    private catalog: Node;
    private settings: Node;
    private canContinue = false;
    private metrics?: LayoutMetrics;
    private elapsed = 0;
    private width = 1440;
    private height = 900;
    private pointerX = 0;
    private pointerY = 0;
    private parallaxX = 0;
    private parallaxY = 0;
    private portrait = false;
    private reducedMotion = typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

    constructor(parent: Node, private font: Font, frames: Record<string, SpriteFrame>, controls: Map<string, Node>) {
        this.node = this.make('TitleScreen', parent, 1440, 900);
        this.background = this.make('CityBackground', this.node, 1440, 900);
        this.sprite(this.background, frames.city);
        this.content = this.make('TitleContent', this.node, 1440, 900);
        this.heading = this.make('OriginalLogo', this.content, 990, 300);
        this.sprite(this.heading, frames.logo);
        this.subtitle = this.label('GameType', this.content, '商战互动卡牌游戏', 650, 70, 36, cream);
        const subtitleOutline = this.subtitle.addComponent(LabelOutline); subtitleOutline.color = color(ink); subtitleOutline.width = 3;
        this.start = this.button('Start', '开始创业  →', gold);
        this.resume = this.button('Continue', '继续创业  →', gold);
        this.catalog = this.button('Catalog', '图鉴', cream);
        this.settings = this.button('Settings', '设置', cream);
        controls.set('Title:Restart', this.start); controls.set('Title:Continue', this.resume); controls.set('Title:OpenSettings', this.settings);
        controls.set('Title:Open:catalog', this.catalog);
        this.node.active = false;
    }
    private make(name: string, parent: Node, w: number, h: number) {
        const node = new Node(name); node.layer = parent.layer; parent.addChild(node);
        node.addComponent(UITransform).setContentSize(w, h); return node;
    }
    private sprite(node: Node, frame: SpriteFrame) {
        const sprite = node.addComponent(Sprite); sprite.spriteFrame = frame; sprite.sizeMode = Sprite.SizeMode.CUSTOM; sprite.trim = true;
    }
    private fit(node: Node, width: number, height: number) {
        const size = node.getComponent(Sprite)!.spriteFrame!.rect;
        const scale = Math.min(width / size.width, height / size.height);
        node.getComponent(UITransform)!.setContentSize(size.width * scale, size.height * scale);
    }
    private label(name: string, parent: Node, text: string, w: number, h: number, size: number, hex: string, font = this.font) {
        const node = this.make(name, parent, w, h), label = node.addComponent(Label);
        label.font = font; label.string = text; label.fontSize = size; label.lineHeight = size * 1.2;
        label.color = color(hex); label.horizontalAlign = Label.HorizontalAlign.CENTER; label.verticalAlign = Label.VerticalAlign.CENTER;
        label.overflow = Label.Overflow.SHRINK; label.enableWrapText = false;
        node.getComponent(UITransform)!.setContentSize(w, h); return node;
    }
    private button(name: string, text: string, hex: string) {
        const node = this.make(name, this.content, 350, 76);
        const shadow = this.make('Shadow', node, 350, 76); shadow.addComponent(Graphics);
        this.paintShadow(shadow, 350, 76);
        const plate = this.make('Plate', node, 350, 76), surface = plate.addComponent(Surface);
        surface.fill = color(hex); surface.stroke = color(ink); surface.lineWidth = 4; surface.radius = 24; surface.crayon = true; surface.paint();
        this.label('Text', node, text, 326, 62, 32, ink); return node;
    }
    private resizeButton(node: Node, w: number, h: number, font: number) {
        node.getComponent(UITransform)!.setContentSize(w, h);
        const plate = node.getChildByName('Plate')!; plate.getComponent(UITransform)!.setContentSize(w, h);
        const surface = plate.getComponent(Surface)!; surface.radius = h * .28; surface.lineWidth = Math.max(3, h * .05); surface.paint();
        const shadow = node.getChildByName('Shadow')!; shadow.getComponent(UITransform)!.setContentSize(w, h);
        this.paintShadow(shadow, w, h);
        const label = node.getChildByName('Text')!.getComponent(Label)!; label.fontSize = font; label.lineHeight = font * 1.2;
        label.node.getComponent(UITransform)!.setContentSize(w - 24, h - 8);
    }
    private paintShadow(node: Node, w: number, h: number) {
        const g = node.getComponent(Graphics)!; g.clear();
        const unit = Math.max(.6, h / 66), radius = h * .28;
        // A quiet rounded perimeter with translucent gray wax rubbed inside it.
        for (let pass = 2; pass >= 0; pass--) {
            const spread = (pass + 1) * unit;
            g.fillColor = new Color(168, 171, 176, pass ? 13 : 35);
            g.roundRect(-w / 2 - spread, -h / 2 - spread, w + spread * 2, h + spread * 2, radius + spread); g.fill();
        }
        let seed = Math.round(w * 97 + h * 131);
        const random = () => { seed = Math.imul(seed, 1664525) + 1013904223 | 0; return (seed >>> 0) / 4294967296; };
        const inside = (x: number, y: number) => {
            const dx = Math.max(0, Math.abs(x) - (w / 2 - radius)), dy = Math.max(0, Math.abs(y) - (h / 2 - radius));
            return dx * dx + dy * dy <= radius * radius;
        };
        g.lineCap = Graphics.LineCap.ROUND;
        for (let pass = 0; pass < 2; pass++) {
            g.strokeColor = pass ? new Color(248, 248, 246, 48) : new Color(137, 141, 147, 36);
            g.lineWidth = (pass ? .65 : 1.8) * unit;
            for (let i = 0; i < w * h / (65 * unit * unit); i++) {
                const x = (random() - .5) * w, y = (random() - .5) * h;
                const length = (pass ? 2 + random() * 5 : 5 + random() * 10) * unit;
                if (inside(x, y) && inside(x + length, y + unit)) { g.moveTo(x, y); g.lineTo(x + length, y + unit); }
            }
            g.stroke();
        }
    }
    show(active: boolean, home: boolean, canContinue: boolean) {
        if (active && !this.node.active) { this.elapsed = 0; this.pointerX = this.pointerY = this.parallaxX = this.parallaxY = 0; }
        this.canContinue = canContinue;
        this.node.active = active; this.content.active = home; this.resume.active = canContinue;
        if (active && home && this.metrics) this.layoutButtons(this.metrics);
        if (active) this.tick(0);
    }
    private layoutButtons(metrics: LayoutMetrics) {
        const { width: w, height: h, scale, top, bottom } = metrics;
        const buttonW = Math.min(350 * scale, w * (this.portrait ? .78 : .29)) * .7;
        let primaryY = -h * .1, fit = Math.min(1, Math.max(1, h * .4 - bottom - 16 * scale) / ((this.canContinue ? 161 : 99) * scale));
        if (!this.portrait) {
            const subtitleBottom = this.subtitle.position.y - this.subtitle.getComponent(UITransform)!.height / 2;
            const lower = -h / 2 + bottom + 16 * scale;
            fit = Math.min(fit, Math.max(.1, (subtitleBottom - 8 * scale - lower) / ((this.canContinue ? 194 : 132) * scale)));
            primaryY = Math.max(lower + (this.canContinue ? 161 : 99) * scale * fit, Math.min(primaryY, subtitleBottom - (8 + 33 * fit) * scale));
        }
        const primary = this.canContinue ? this.resume : this.start;
        this.start.getChildByName('Text')!.getComponent(Label)!.string = this.canContinue ? '开始创业' : '开始创业  →';
        this.start.getChildByName('Plate')!.getComponent(Surface)!.fill = color(this.canContinue ? cream : gold);
        this.resizeButton(primary, buttonW, 66 * scale * fit, 29 * scale * fit); primary.setPosition(0, primaryY);
        if (this.canContinue) {
            this.resizeButton(this.start, buttonW * .84, 48 * scale * fit, 20 * scale * fit);
            this.start.setPosition(0, primaryY - 75 * scale * fit);
        }
        this.resizeButton(this.catalog, buttonW * .84, 48 * scale * fit, 20 * scale * fit);
        this.catalog.setPosition(0, primaryY - (this.canContinue ? 137 : 75) * scale * fit);
        this.resizeButton(this.settings, 84 * scale * .7, 44 * scale, 20 * scale); this.settings.setPosition(w / 2 - (this.portrait ? 65 : 38) * scale, h / 2 - top - 36 * scale);
        this.content.getComponentsInChildren(Graphics).forEach(graphics => graphics.model?.updateWorldBound());
    }
    layout(metrics: LayoutMetrics) {
        this.metrics = metrics;
        const { width: w, height: h, scale, top, bottom } = metrics;
        this.width = w; this.height = h; this.portrait = w <= h;
        this.node.getComponent(UITransform)!.setContentSize(w, h);
        const frame = this.background.getComponent(Sprite)!.spriteFrame!, ratio = frame.originalSize.width / frame.originalSize.height;
        const bw = Math.max(w, h * ratio), bh = bw / ratio;
        this.background.getComponent(UITransform)!.setContentSize(bw * 1.035, bh * 1.035);
        const subtitle = this.subtitle.getComponent(Label)!;
        subtitle.fontSize = (this.portrait ? 26 : 18) * scale; subtitle.lineHeight = subtitle.fontSize * 1.2;
        this.subtitle.getComponent(UITransform)!.setContentSize(Math.min(w * .84, 650 * scale), subtitle.lineHeight);
        this.subtitle.getComponent(LabelOutline)!.width = 3 * scale;
        const buttonH = 66 * scale;
        const logoY = h * .2, startY = -h * .1, gap = (this.portrait ? 16 : 8) * scale;
        // Keep the 30% and 60% centers fixed; leave room for the subtitle on short screens.
        const logoMaxH = Math.min(h * .28, Math.max((this.portrait ? 1 : 40 * scale), 2 * (logoY - startY - buttonH / 2 - subtitle.lineHeight - gap * 2)));
        this.fit(this.heading, this.portrait ? w * .94 : Math.min(w * .65, h * 1.08), logoMaxH);
        const logo = this.heading.getComponent(UITransform)!;
        let headingY = logoY;
        if (!this.portrait) {
            const enlarge = Math.min(2, (w - 32 * scale) / logo.width, h * .55 / logo.height);
            logo.setContentSize(logo.width * enlarge, logo.height * enlarge);
            const topMargin = logo.width / 2 > w / 2 - 74 * scale ? 66 * scale : 8 * scale;
            headingY = h / 2 - top - topMargin - logo.height / 2;
        }
        this.heading.setPosition(0, headingY);
        this.subtitle.setPosition(0, headingY - logo.height / 2 - gap - subtitle.lineHeight / 2);
        this.layoutButtons(metrics);
        this.tick(0);
    }
    pointer(point: Vec2) {
        const p = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(point.x, point.y));
        this.pointerX = Math.max(-1, Math.min(1, p.x / (this.width / 2))); this.pointerY = Math.max(-1, Math.min(1, p.y / (this.height / 2)));
    }
    tick(dt: number) {
        if (!this.node.active) return;
        for (const button of [this.start, this.resume, this.catalog, this.settings]) {
            if (!button.activeInHierarchy) continue;
            const offset = viewShadowOffset(button, new Vec3(), 5);
            button.getChildByName('Shadow')!.setPosition(offset.x, offset.y);
        }
        this.elapsed += Math.min(dt, .05);
        const response = Math.min(1, dt * 4); this.parallaxX += (this.pointerX - this.parallaxX) * response; this.parallaxY += (this.pointerY - this.parallaxY) * response;
        this.background.setPosition(this.reducedMotion ? 0 : -this.parallaxX * 6, this.reducedMotion ? 0 : -this.parallaxY * 6);
    }
    snapshot() { return { active: this.node.active, home: this.content.active, portrait: this.portrait, elapsed: this.elapsed, reducedMotion: this.reducedMotion,
        pieces: [] }; }
}
