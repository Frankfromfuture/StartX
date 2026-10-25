import { Color, Font, Graphics, Label, Mask, Node, Sprite, SpriteFrame, UIOpacity, UITransform, Vec2, Vec3 } from 'cc';
import { GameModel } from './GameModel';
import { FILE_TAB_RADIUS, Surface } from './Surface';
import { businessGroups } from './Notebook';
import { PACK_SCREEN_SIZE } from './Layout';
import { Icon } from './Icon';
import { CardFrameVolume } from './CardFrameVolume';
import { viewShadowOffset } from './ViewShadow';

/** The original pack covers and task notebook, fixed to the screen above the board. */
export class OriginalHud {
    open = false;
    mode: 'tasks' | 'recipes' = 'tasks';
    pending = 0;
    packOffset = 0;
    taskOffset = 0;
    reveal = 0;
    helpText = '';
    private helpKey = '';
    private helpPinned = false;
    private rowHelp = new Map<string, { node: Node; text: string }>();
    private packWidth = 0;
    private packStep = 1;
    private packMinimum = 0;
    private packInset = 0;
    private packFade = 1;
    private packVelocity = 0;
    private packHeld = false;
    private packSnap: number | null = 0;
    private packLastMove = 0;
    private packWheelUntil = 0;
    private packOpacity = new Map<string, UIOpacity>();
    private tabShadows = new Map<string, Node>();
    private taskHeight = 0;
    private scale = 1;
    private stamp = '';
    private collapsed = new Set<string>();
    private reminderTime = 0;
    private labels = new Map<string, Label>();
    private packImages = new Map<string, Sprite>();
    private flashImage: Sprite;
    private flashOpacity: UIOpacity;
    private flashStars: { node: Node; opacity: UIOpacity; age: number; duration: number }[] = [];
    private packViewport: Node;
    private packContent: Node;
    private taskViewport: Node;
    private taskContent: Node;
    private scrollArea = '';
    private drawerWidth = 0;
    private drawerY = 0;
    private screenWidth = 0;
    private tabWidth = 0;
    private tabHeight = 0;
    private tabOffsets = [0, 0];
    private tabGap = 0;
    private landscape = false;
    private packsOpen = false;
    private packReveal = 1;
    private packStripY = 0;
    private packStripHeight = 0;
    private visible = true;
    private packTab: Node;
    private stripOpacity: UIOpacity;
    private contentFont = 22;
    private measureLabel: Label;
    private measuredWidths = new Map<string, number>();
    constructor(private root: Node, private model: GameModel, private font: Font,
        private controls: Map<string, Node>, private frame: (path: string) => Promise<SpriteFrame>) {
        const strip = this.get('PackStrip');
        this.stripOpacity = strip.getComponent(UIOpacity) || strip.addComponent(UIOpacity);
        strip.setSiblingIndex(this.get('Status').getSiblingIndex());
        this.packTab = this.node('PackTab', root, 64, 64);
        const packIcon = this.node('Icon', this.packTab, 64, 64).addComponent(Icon); packIcon.kind = 'PackStack'; packIcon.paint();
        this.controls.set('PackTab', this.packTab); this.packTab.active = false;
        this.packViewport = this.node('PackViewport', strip, 1, 1);
        this.packViewport.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
        this.packContent = this.node('Covers', this.packViewport, 1, 1);
        const flash = this.node('FlashPack', strip, 112, 112);
        this.flashOpacity = flash.addComponent(UIOpacity);
        new CardFrameVolume(flash).paintPack(112);
        this.flashImage = this.node('Cover', flash, 112, 112).addComponent(Sprite); this.flashImage.sizeMode = Sprite.SizeMode.CUSTOM;
        this.controls.set('FlashPack', flash); this.pending++;
        this.frame('packs/flash_pack').then(f => {
            if (flash.isValid) { this.flashImage.spriteFrame = f; flash.getComponent(UITransform)!.setContentSize(112, 112); }
        }).catch(e => console.error('[StartX] Flash pack', e)).then(() => this.pending--);
        for (let i = 0; i < 3; i++) {
            const node = this.node('Star-' + i, flash, 8, 8), art = node.addComponent(Graphics);
            art.fillColor = new Color(250, 242, 223);
            for (let point = 0; point < 10; point++) {
                const angle = Math.PI / 2 + point * Math.PI / 5, radius = point % 2 ? 1.6 : 4;
                const x = Math.cos(angle) * radius, y = Math.sin(angle) * radius;
                if (point === 0) art.moveTo(x, y); else art.lineTo(x, y);
            }
            art.close(); art.fill();
            const star = { node, opacity: node.addComponent(UIOpacity), age: 0, duration: 1 };
            this.flashStars.push(star); this.resetFlashStar(star); star.age = star.duration * i / 3;
        }
        this.get('TaskReminder').addComponent(UIOpacity).opacity = 0;
        for (const name of ['Book', 'Tasks']) {
            const shadow = this.node(name + 'Shadow', this.get('Toolbar'), 44, 184);
            shadow.addComponent(Graphics);
            const surface = shadow.addComponent(Surface); surface.fileTab = true; surface.openLeft = true;
            surface.lineWidth = 0; surface.fill = new Color(55, 46, 30, 30); surface.paint();
            this.tabShadows.set(name, shadow);
        }
        this.taskViewport = this.get('TaskDrawer/Viewport'); this.taskViewport.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
        this.taskContent = this.node('Tasks', this.taskViewport, 1, 1);
        this.measureLabel = this.text(this.root, 'TextMeasure', '', 1, 1, 0, 0, 22);
        this.measureLabel.overflow = Label.Overflow.NONE;
        this.measureLabel.enableWrapText = false;
        this.measureLabel.node.active = false;
        this.controls.set('Tasks', this.get('Toolbar/Tasks'));
        for (const id of model.data.packOrder) {
            const item = this.node('Pack-' + id, this.packContent, 112, 112);
            this.packOpacity.set(id, item.addComponent(UIOpacity));
            new CardFrameVolume(item).paintPack(112);
            const cover = this.node('Cover', item, 112, 112);
            const sprite = cover.addComponent(Sprite); sprite.sizeMode = Sprite.SizeMode.CUSTOM;
            this.packImages.set(id, sprite); this.pending++;
            this.frame('packs/' + id).then(f => { if (cover.isValid) { sprite.spriteFrame = f; cover.getComponent(UITransform)!.setContentSize(112, 112); } })
                .catch(e => console.error('[StartX] Pack shelf', e)).then(() => this.pending--);
            const badge = this.node('Price', cover, 40, 22); badge.setPosition(-26, 36);
            this.labels.set(id, this.text(badge, 'Text', '$' + model.data.packs[id].price, 36, 20, 0, 0, 18));
            this.labels.get(id)!.color = Color.WHITE.clone();
            this.controls.set('TopPack:' + id, item);
        }
        this.get('TaskDrawer').active = false;
        this.get('TaskDrawer/Help').active = false;
    }
    private get(path: string) { return this.root.getChildByPath(path)!; }
    private node(name: string, parent: Node, w: number, h: number) {
        const n = new Node(name); n.layer = this.root.layer; parent.addChild(n); n.addComponent(UITransform).setContentSize(w, h); return n;
    }
    private text(parent: Node, name: string, value: string, w: number, h: number, x: number, y: number, size: number) {
        const n = this.node(name, parent, w, h); n.setPosition(x, y);
        const l = n.addComponent(Label); l.font = this.font; l.useSystemFont = false; l.string = value; l.fontSize = size; l.lineHeight = size * 1.35;
        l.color = new Color(47, 42, 37); l.overflow = Label.Overflow.SHRINK; l.enableWrapText = true;
        l.horizontalAlign = Label.HorizontalAlign.LEFT; l.verticalAlign = Label.VerticalAlign.CENTER;
        n.getComponent(UITransform)!.setContentSize(w, h); return l;
    }
    layout(w: number, stripY: number, stripH: number, stripWidth: number, drawerBottom: number, scale: number, landscape: boolean, unit: number, nearSquare = false) {
        this.scale = scale;
        if (this.landscape !== landscape) { this.packsOpen = false; this.packReveal = landscape ? 0 : 1; }
        this.landscape = landscape; this.packStripY = stripY; this.packStripHeight = stripH;
        this.packTab.getComponent(UITransform)!.setContentSize(64 * scale, 44 * scale);
        const status = this.get('Status'), statusBottom = status.position.y - status.getComponent(UITransform)!.height / 2;
        this.packTab.setPosition(0, landscape ? statusBottom - (34.56 / 2 + 2) * scale : stripY);
        this.packTab.getChildByName('Icon')!.setScale(34.56 * scale / 64, 34.56 * scale / 64, 1);
        const strip = this.get('PackStrip'), index = -this.packOffset / this.packStep;
        strip.setPosition(0, stripY); strip.getComponent(UITransform)!.setContentSize(w, stripH);
        this.packInset = Math.max(16 * unit, 8 * scale); this.packFade = Math.max(10 * unit, 6 * scale);
        const sw = Math.min(stripWidth, w - 2 * (this.packInset + this.packFade));
        const itemSize = PACK_SCREEN_SIZE * scale, step = itemSize + 14 * unit;
        const visible = Math.max(1, Math.min(this.model.data.packOrder.length, Math.floor((sw + 14 * unit + .01) / step) - 1));
        const span = (visible + 1) * step - 14 * unit, flashX = -span / 2 + itemSize / 2;
        const flash = this.controls.get('FlashPack')!; flash.setPosition(flashX, 0); flash.setScale(itemSize / 112, itemSize / 112, 1);
        const left = flashX + itemSize / 2 + 7 * unit, right = w / 2, center = (left + right) / 2;
        this.packViewport.setPosition(center, 0); this.packViewport.getComponent(UITransform)!.setContentSize(right - left, stripH);
        this.packStep = step; this.packMinimum = -(this.model.data.packOrder.length - visible) * step;
        this.packWidth = step * this.model.data.packOrder.length - 14 * unit;
        this.model.data.packOrder.forEach((id, i) => {
            const n = this.controls.get('TopPack:' + id)!; n.setScale(itemSize / 112, itemSize / 112, 1);
            n.setPosition(flashX + (i + 1) * step - center, 0);
        });
        this.packOffset = -Math.round(index) * step; this.packVelocity = 0; this.packSnap = null;
        this.scrollPacks(0);
        const drawer = this.get('TaskDrawer'), dw = Math.min(440 * unit, w / 3);
        const previousHeight = Math.max(220, Math.min(900 * unit, 2 * Math.min(stripY - stripH / 2 - 20, -drawerBottom)));
        const drawerTop = stripY + stripH / 2 - 12 * scale;
        const dh = landscape ? Math.max(160 * scale, drawerTop - drawerBottom) : Math.max(220, Math.min(previousHeight + 48 * scale, 2 * Math.min(drawerTop, -drawerBottom + 8 * scale)));
        this.screenWidth = w; this.drawerWidth = dw; this.drawerY = landscape ? (drawerTop + drawerBottom) / 2 : 0;
        this.tabWidth = landscape ? 40 * scale : Math.max(44 * unit, 32 * scale); this.tabHeight = landscape ? 84 * scale : Math.max(184 * unit, 126 * scale);
        this.tabGap = landscape ? -24 * scale : -(this.tabWidth * .4 + 12 * scale);
        const taskTabHeight = this.tabHeight + (landscape ? 0 : Math.max(24 * unit, 16 * scale));
        this.tabOffsets = [(taskTabHeight + this.tabGap) / 2, -(this.tabHeight + this.tabGap) / 2];
        this.contentFont = Math.max(22 * unit, 13 * scale);
        drawer.getComponent(UITransform)!.setContentSize(dw, dh);
        const drawerSurface = drawer.getComponent(Surface)!;
        drawerSurface.openLeft = false; drawerSurface.lineWidth = Math.max(2 * scale, 2 * unit);
        drawerSurface.radius = this.tabWidth * FILE_TAB_RADIUS;
        for (const name of ['Book', 'Tasks']) {
            const tab = this.get('Toolbar/' + name), text = this.get('Toolbar/' + name + '/Text');
            const tabHeight = name === 'Tasks' ? taskTabHeight : this.tabHeight;
            tab.getComponent(UITransform)!.setContentSize(this.tabWidth, tabHeight);
            tab.getComponent(Surface)!.lineWidth = Math.max(2 * scale, 2 * unit); tab.getComponent(Surface)!.paint();
            const shadow = this.tabShadows.get(name)!;
            shadow.getComponent(UITransform)!.setContentSize(this.tabWidth + 2 * scale, tabHeight + 2 * scale);
            shadow.getComponent(Surface)!.paint();
            text.setPosition(landscape ? 0 : this.tabWidth * .05, 0);
            text.getComponent(UITransform)!.setContentSize(landscape ? this.tabWidth - 4 * scale : this.tabWidth - 10 * unit, landscape ? 36 * scale : tabHeight - this.tabWidth * .7);
            const label = text.getComponent(Label)!; label.fontSize = landscape ? 12 * scale : this.contentFont; label.lineHeight = label.fontSize * 1.35;
            label.string = name === 'Book' ? (landscape ? '商业\n模式' : '商\n业\n模\n式') : (landscape ? '发展\n里程碑' : '发\n展\n里\n程\n碑');
            label.enableWrapText = !landscape; label.horizontalAlign = landscape ? Label.HorizontalAlign.LEFT : Label.HorizontalAlign.CENTER;
            if (landscape) label.lineHeight = label.fontSize * 1.2;
        }
        const padding = Math.max(12 * unit, 6 * scale), titleHeight = this.contentFont * 1.8;
        const header = titleHeight + padding * 2 + this.contentFont * 1.4, titleWidth = dw - padding * 2;
        this.get('TaskDrawer/Title').setPosition(0, dh / 2 - titleHeight / 2 - padding);
        this.get('TaskDrawer/Title').getComponent(UITransform)!.setContentSize(titleWidth, titleHeight);
        this.get('TaskDrawer/Title').getComponent(Label)!.fontSize = this.contentFont + 2 * unit;
        this.get('TaskDrawer/Count').setPosition(0, dh / 2 - titleHeight - padding - this.contentFont * .7);
        this.get('TaskDrawer/Count').getComponent(UITransform)!.setContentSize(dw - padding * 2, this.contentFont * 1.4);
        this.get('TaskDrawer/Count').getComponent(Label)!.fontSize = this.contentFont * .85;
        this.taskViewport.setPosition(0, -header / 2); this.taskViewport.getComponent(UITransform)!.setContentSize(dw - padding * 2, dh - header - padding * 2);
        this.placeDrawer(); this.paintTabs(); this.renderTasks(); this.placePacks(0);
    }
    setVisible(visible: boolean) { this.visible = visible; this.placePacks(0); }
    togglePacks() { if (this.landscape) { this.packsOpen = !this.packsOpen; if (this.packsOpen) this.close(); } }
    closePacks() { this.packsOpen = false; }
    dismissPacksAt(point: Vec2) { if (this.landscape && this.packsOpen && !this.hit(this.packTab, point) && !this.hit(this.get('PackStrip'), point)) this.closePacks(); }
    private placePacks(dt: number) {
        const target = !this.landscape || this.packsOpen ? 1 : 0;
        this.packReveal += (target - this.packReveal) * Math.min(1, dt * 24);
        if (Math.abs(target - this.packReveal) < .005) this.packReveal = target;
        const strip = this.get('PackStrip'); strip.active = this.visible && this.packReveal > 0;
        strip.setPosition(0, this.packStripY);
        this.stripOpacity.opacity = Math.round(255 * this.packReveal);
        this.packTab.active = this.visible && this.landscape && !this.packsOpen && this.packReveal === 0;
    }
    private placeDrawer() {
        const edge = -this.screenWidth / 2 + this.drawerWidth * this.reveal;
        this.get('TaskDrawer').setPosition(edge - this.drawerWidth / 2, this.drawerY);
        this.get('TaskDrawer').active = this.open || this.reveal > .001;
        const border = this.get('TaskDrawer').getComponent(Surface)!.lineWidth;
        ['Book', 'Tasks'].forEach((name, i) => {
            const x = edge - border + this.tabWidth / 2, y = this.drawerY + this.tabOffsets[i];
            this.get('Toolbar/' + name).setPosition(x, y);
            const offset = viewShadowOffset(this.get('Toolbar'), new Vec3(x, y), 4 * this.scale);
            this.tabShadows.get(name)!.setPosition(x + offset.x, y + offset.y);
        });
    }
    private paintTabs() {
        ['Book', 'Tasks'].forEach((name, i) => {
            const active = this.open && this.mode === (i ? 'tasks' : 'recipes'), surface = this.get('Toolbar/' + name).getComponent(Surface)!;
            surface.openLeft = active;
            surface.fill = Color.fromHEX(new Color(), active ? '#FAF1DF' : i ? '#DFE5D6' : '#E8E1D1'); surface.paint();
        });
        const active = this.mode === 'recipes' ? 'Book' : 'Tasks', inactive = active === 'Book' ? 'Tasks' : 'Book';
        const tab = this.get('Toolbar/' + active), half = tab.getComponent(UITransform)!.height / 2;
        const inset = tab.getComponent(Surface)!.lineWidth / 2, y = this.tabOffsets[active === 'Book' ? 0 : 1];
        this.get('TaskDrawer').getComponent(Surface)!.setEdgeGaps(this.open ? [[y - half + inset, y + half - inset]] : []);
        for (const name of [inactive, active]) {
            this.tabShadows.get(name)!.setSiblingIndex(this.get('Toolbar').children.length - 1);
            this.get('Toolbar/' + name).setSiblingIndex(this.get('Toolbar').children.length - 1);
        }
    }
    toggle(mode: 'tasks' | 'recipes' = 'tasks') { this.closePacks(); this.open = !this.open || this.mode !== mode; this.mode = mode; this.taskOffset = 0; this.paintTabs(); if (this.open) this.renderTasks(); this.placeDrawer(); }
    close() { this.open = false; this.hideInfo(); this.paintTabs(); }
    reset(model: GameModel) { this.close(); this.model = model; this.stamp = ''; this.dismissReminder(); this.taskOffset = 0; this.collapsed.clear(); }
    fold(key: string) { this.collapsed.has(key) ? this.collapsed.delete(key) : this.collapsed.add(key); this.renderTasks(); }
    private resetFlashStar(star: typeof this.flashStars[number]) {
        // Reposition only between flashes, keeping the tiny stars inside the wrapper and above its caption.
        for (let attempt = 0; attempt < 12; attempt++) {
            star.node.setPosition(-40 + Math.random() * 80, -22 + Math.random() * 64);
            if (this.flashStars.every(other => other === star || Vec3.distance(other.node.position, star.node.position) >= 16)) break;
        }
        star.node.angle = -18 + Math.random() * 36;
        star.age = 0; star.duration = 1.2 + Math.random() * .9; star.opacity.opacity = 0;
    }
    private tickFlashStars(dt: number) {
        if (!this.flashImage.node.activeInHierarchy) return;
        for (const star of this.flashStars) {
            star.age += dt;
            if (star.age >= star.duration) this.resetFlashStar(star);
            const phase = Math.min(1, star.age / (star.duration * .7)), brightness = Math.pow(Math.sin(phase * Math.PI), 2);
            star.opacity.opacity = Math.round(235 * brightness);
            const size = .65 + .35 * brightness; star.node.setScale(size, size, 1);
        }
    }
    tick(dt: number, showReminders = true) {
        this.placePacks(Math.min(dt, .05));
        this.tickPacks(Math.min(dt, .05));
        this.tickFlashStars(Math.min(dt, .05));
        const active = this.model.flashPackCharges > 0;
        this.flashImage.color = active ? Color.WHITE.clone() : new Color(100, 100, 100);
        this.flashOpacity.opacity = active ? 255 : 115;
        const target = this.open ? 1 : 0;
        this.reveal += (target - this.reveal) * Math.min(1, dt * 20);
        if (Math.abs(target - this.reveal) < .001) this.reveal = target;
        this.placeDrawer();
        const stamp = Array.from(this.model.completed).join(',') + '|' + businessGroups(this.model).map(g => g.known.map(r => r.id).join(',')).join('|') + '|' + this.model.testMode;
        if (stamp !== this.stamp) {
            this.stamp = stamp;
            for (const id of this.model.data.packOrder) {
                const unlocked = this.model.packUnlocked(id);
                this.labels.get(id)!.string = '$' + this.model.data.packs[id].price;
                this.packImages.get(id)!.color = unlocked ? Color.WHITE.clone() : new Color(130, 130, 130, 190);
            }
            if (this.open) this.renderTasks();
        }
        const node = this.get('TaskReminder');
        if (!showReminders) { node.active = false; return; }
        this.reminderTime = Math.max(0, this.reminderTime - dt);
        const reminder = node.getComponent(Label)!;
        if (!this.reminderTime) {
            const next = this.model.taskNotices.shift(); reminder.string = next || '';
            if (next) this.reminderTime = 4;
        }
        node.active = !!reminder.string;
        node.getComponent(UIOpacity)!.opacity = Math.round(255 * Math.min(1, this.reminderTime / .45));
    }
    dismissReminder() { this.reminderTime = 0; const node = this.get('TaskReminder'); node.getComponent(Label)!.string = ''; node.active = false; node.getComponent(UIOpacity)!.opacity = 0; }
    private textWidth(value: string, font: number) {
        const key = `${font}:${value}`, cached = this.measuredWidths.get(key);
        if (cached !== undefined) return cached;
        this.measureLabel.node.active = true;
        this.measureLabel.string = value; this.measureLabel.fontSize = font; this.measureLabel.lineHeight = font * 1.35;
        this.measureLabel.updateRenderData(true);
        const width = this.measureLabel.node.getComponent(UITransform)!.width;
        this.measureLabel.node.active = false;
        this.measuredWidths.set(key, width); return width;
    }
    private wrap(value: string, width: number, font: number) {
        const lines: string[] = []; let line = '', length = 0;
        for (const char of Array.from(value)) {
            const advance = char === '\n' ? 0 : this.textWidth(char, font);
            if (char === '\n' || length + advance > width && line) { lines.push(line); line = ''; length = 0; }
            if (char !== '\n') { line += char; length += advance; }
        }
        lines.push(line); return lines;
    }
    private renderTasks() {
        this.hideInfo(); this.rowHelp.clear();
        this.taskContent.children.slice().forEach(n => n.destroy());
        for (const key of Array.from(this.controls.keys())) if (key.startsWith('TaskFold:') || key.startsWith('TaskItem:')) this.controls.delete(key);
        const size = this.taskViewport.getComponent(UITransform)!, width = size.width, font = this.contentFont;
        const leftInset = font / 4, textWidth = width - leftInset;
        let y = size.height / 2;
        const row = (name: string, value: string, color: string, action = '', explanation = '', done = false) => {
            const lines = this.wrap(value, textWidth, font), height = Math.max(font * 1.65, lines.length * font * 1.35 + 10);
            const label = this.text(this.taskContent, name, lines.join('\n'), textWidth, height, leftInset / 2, y - height / 2, font);
            label.enableWrapText = false; label.color = Color.fromHEX(new Color(), '#' + color);
            if (done) {
                lines.forEach((line, index) => {
                    const skip = index === 0 ? this.textWidth('☑ ', font) : 0;
                    const length = Math.min(textWidth, this.textWidth(line, font)) - skip;
                    const ly = (lines.length - 1) * font * 1.35 / 2 - index * font * 1.35 + font * .12;
                    const strike = this.node('CompletionStrike', label.node, Math.max(0, length), 1.3);
                    strike.setPosition(-textWidth / 2 + skip + length / 2, ly);
                    // Surface repaints on enable, including when rows are built in a closed drawer.
                    const surface = strike.addComponent(Surface); surface.fill = label.color; surface.radius = 0; surface.paint();
                });
            }
            if (action) { this.controls.set(action, label.node); if (explanation) this.rowHelp.set(action, { node: label.node, text: explanation }); }
            y -= height; return label;
        };
        const separator = (color: string) => {
            const n = this.node('Separator', this.taskContent, width, 2); n.setPosition(0, y - 4);
            const g = n.addComponent(Graphics); g.strokeColor = Color.fromHEX(new Color(), '#' + color); g.lineWidth = 1.5;
            g.moveTo(-width / 2, 0); g.lineTo(width / 2, 0); g.stroke(); y -= 14;
        };
        this.get('TaskDrawer/Title').getComponent(Label)!.string = this.mode === 'tasks' ? '发展里程碑' : '商业模式';
        if (this.mode === 'recipes') {
            const groups = businessGroups(this.model), knownCount = groups.reduce((sum, group) => sum + group.known.length, 0);
            this.get('TaskDrawer/Count').getComponent(Label)!.string = `已解锁 ${knownCount} / ${this.model.data.recipes.length}`;
            groups.forEach((group, index) => {
                row('Stage', group.title, '3A352F').isBold = true;
                row('StageCount', `已解锁 商业模式：${group.known.length}/${group.total}`, '5B5145');
                for (const recipe of group.known) row('Recipe', '• ' + recipe.name, '2F2A25', 'TaskItem:recipe-' + recipe.id, recipe.formula);
                for (let i = 0; i < group.unknown; i++) row('Unknown', '• ？？', '777067');
                if (index < groups.length - 1) separator('B9AD9C');
            });
        } else {
            this.get('TaskDrawer/Count').getComponent(Label)!.string = `${this.model.completed.size} / ${this.model.data.tasks.length} 已完成`;
            for (const section of ['主任务', '支线任务']) {
                const tasks = this.model.data.tasks.filter(t => t.section === section);
                row('Section', `${section} ${tasks.filter(t => this.model.completed.has(t.id)).length}/${tasks.length}`, '3A352F').isBold = true;
                separator('9D9386');
                for (const group of Array.from(new Set(tasks.map(t => t.group)))) {
                    y -= font * .35;
                    const key = section + '/' + group, folded = this.collapsed.has(key);
                    row('Group', `${folded ? '▸' : '▾'} ${group}`, '3A352F', 'TaskFold:' + key).isBold = true;
                    if (folded) continue;
                    for (const task of tasks.filter(t => t.group === group)) {
                        const done = this.model.completed.has(task.id);
                        row('Task', `${done ? '☑' : '☐'} ${task.title}`, '3A352F', 'TaskItem:' + task.id, task.content, done);
                    }
                }
                y -= font * .35;
            }
        }
        this.taskHeight = size.height / 2 - y; this.scrollTasks(0);
    }
    hideInfo() { this.helpText = ''; this.helpKey = ''; this.helpPinned = false; this.get('TaskDrawer/Help').active = false; }
    infoFor(key: string) { return this.rowHelp.get(key.startsWith('TaskItem:') ? key : 'TaskItem:' + key)?.text || ''; }
    showInfo(key: string, pinned = true) {
        const fullKey = key.startsWith('TaskItem:') ? key : 'TaskItem:' + key, entry = this.rowHelp.get(fullKey);
        if (!entry || !this.open || !pinned && this.helpPinned) return;
        if (pinned && this.helpPinned && this.helpKey === fullKey) { this.hideInfo(); return; }
        const box = this.get('TaskDrawer/Help'), drawer = this.get('TaskDrawer'), size = drawer.getComponent(UITransform)!;
        const padding = Math.max(10, 5 * this.scale), font = this.contentFont, width = size.width - padding * 2;
        const lines = this.wrap(entry.text, width - padding * 2, font), height = Math.min(size.height - padding * 2, lines.length * font * 1.35 + padding * 2);
        box.getComponent(UITransform)!.setContentSize(width, height);
        const label = this.get('TaskDrawer/Help/Text').getComponent(Label)!;
        label.fontSize = font; label.lineHeight = font * 1.35; label.enableWrapText = false; label.string = lines.join('\n');
        label.node.getComponent(UITransform)!.setContentSize(width - padding * 2, height - padding * 2);
        const p = drawer.getComponent(UITransform)!.convertToNodeSpaceAR(entry.node.getWorldPosition());
        const rowHeight = entry.node.getComponent(UITransform)!.height, minY = -size.height / 2 + padding + height / 2, maxY = size.height / 2 - padding - height / 2;
        let y = p.y - rowHeight / 2 - padding - height / 2;
        if (y < minY) y = p.y + rowHeight / 2 + padding + height / 2;
        box.setPosition(0, Math.max(minY, Math.min(maxY, y))); box.active = true;
        this.helpText = entry.text; this.helpKey = fullKey; this.helpPinned = pinned;
    }
    hover(p: Vec2) {
        if (!this.open) return;
        const action = this.actionAt(p);
        if (action?.startsWith('TaskItem:')) this.showInfo(action, false);
        else if (!this.helpPinned && !this.hit(this.get('TaskDrawer/Help'), p)) this.hideInfo();
    }
    private hit(n: Node, p: Vec2) {
        if (!n.activeInHierarchy) return false;
        const t = n.getComponent(UITransform)!, v = t.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        return Math.abs(v.x) <= t.width / 2 && Math.abs(v.y) <= t.height / 2;
    }
    private hitTab(n: Node, p: Vec2) {
        const t = n.getComponent(UITransform)!, v = t.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        return n.activeInHierarchy && v.x >= -t.width / 2 && v.x <= -t.width / 2 + Math.max(t.width, 44 * this.scale) && Math.abs(v.y) <= t.height / 2;
    }
    actionAt(p: Vec2): string | null {
        // Resolve overlapping tab hits in their actual front-to-back paint order.
        for (const name of ['Book', 'Tasks'].sort((a, b) => this.get('Toolbar/' + b).getSiblingIndex() - this.get('Toolbar/' + a).getSiblingIndex())) if (this.hitTab(this.get('Toolbar/' + name), p)) return name;
        const drawer = this.get('TaskDrawer');
        if (this.open && this.hit(this.get('TaskDrawer/Help'), p)) return 'TaskHelpClose';
        if (this.reveal > .001 && this.hit(drawer, p)) {
            if (this.hit(this.taskViewport, p)) for (const [key, n] of this.controls) {
                if ((key.startsWith('TaskFold:') || key.startsWith('TaskItem:')) && this.hit(n, p)) return key;
            }
            return 'TaskNoop';
        }
        if (this.hit(this.get('PackStrip'), p)) {
            if (this.hit(this.controls.get('FlashPack')!, p)) return 'FlashPack';
            if (!this.hit(this.packViewport, p)) return 'PackNoop';
            for (const id of this.model.data.packOrder) if (this.packOpacity.get(id)!.opacity >= 180 && this.hit(this.controls.get('TopPack:' + id)!, p)) return 'TopPack:' + id;
            return 'PackNoop';
        }
        return null;
    }
    private areaAt(p: Vec2) { return this.open && this.hit(this.taskViewport, p) ? 'task' : this.hit(this.packViewport, p) ? 'pack' : ''; }
    get isPackGesture() { return this.scrollArea === 'pack'; }
    begin(p: Vec2) {
        this.scrollArea = this.areaAt(p);
        if (this.isPackGesture) {
            this.packHeld = true; this.packVelocity = 0; this.packSnap = null; this.packWheelUntil = 0; this.packLastMove = Date.now();
        }
    }
    drag(delta: Vec2) {
        this.hideInfo();
        if (this.scrollArea === 'task') this.scrollTasks(delta.y);
        if (this.isPackGesture) {
            const now = Date.now(), elapsed = Math.max(1 / 120, (now - this.packLastMove) / 1000);
            const speed = Math.max(-this.packStep * 12, Math.min(this.packStep * 12, delta.x / elapsed));
            this.packVelocity = this.packVelocity * .25 + speed * .75; this.packLastMove = now;
            this.scrollPacks(delta.x);
        }
    }
    end(cancelled: boolean) {
        if (this.isPackGesture) {
            this.packHeld = false;
            if (cancelled || Date.now() - this.packLastMove > 90) this.packVelocity = 0;
            if (Math.abs(this.packVelocity) < 30 * this.scale) this.packSnap = this.nearestPack();
        }
        this.scrollArea = '';
    }
    wheel(p: Vec2, delta: number, horizontal = 0) {
        const area = this.areaAt(p); if (!area) return false; this.hideInfo();
        if (area === 'task') this.scrollTasks(-delta * .35 * this.scale);
        else {
            this.packHeld = false; this.packVelocity = 0; this.packSnap = null; this.packWheelUntil = Date.now() + 100;
            // Cocos scales native wheel deltas by five; keep trackpad travel one to one.
            this.scrollPacks((horizontal ? -horizontal * .2 : delta * .24) * this.scale);
        }
        return true;
    }
    private scrollTasks(delta: number) {
        this.taskOffset = Math.max(0, Math.min(Math.max(0, this.taskHeight - this.taskViewport.getComponent(UITransform)!.height), this.taskOffset + delta));
        this.taskContent.setPosition(0, this.taskOffset);
    }
    private scrollPacks(delta: number) {
        this.packOffset = Math.max(this.packMinimum, Math.min(0, this.packOffset + delta));
        this.packContent.setPosition(this.packOffset, 0);
        const half = this.packViewport.getComponent(UITransform)!.width / 2;
        for (const id of this.model.data.packOrder) {
            const item = this.controls.get('TopPack:' + id)!, width = item.getComponent(UITransform)!.width * item.scale.x;
            const distance = Math.abs(item.position.x + this.packOffset);
            const overlap = half + width / 2 - distance;
            const center = item.position.x + this.packOffset;
            const clearance = Math.min(half - width / 2 + center + this.packFade, half - this.packInset - width / 2 - center);
            const opacity = overlap > 0 ? Math.round(128 + 127 * Math.max(0, Math.min(1, clearance / this.packFade))) : 0;
            this.packOpacity.get(id)!.opacity = opacity; item.active = opacity > 0;
        }
    }
    private nearestPack() { return Math.max(this.packMinimum, Math.min(0, Math.round(this.packOffset / this.packStep) * this.packStep)); }
    private tickPacks(dt: number) {
        if (this.packHeld || Date.now() < this.packWheelUntil) return;
        if (this.packSnap === null && Math.abs(this.packVelocity) > 30 * this.scale) {
            const before = this.packOffset; this.scrollPacks(this.packVelocity * dt);
            this.packVelocity *= Math.exp(-7 * dt);
            if (Math.abs(this.packOffset - before) < .01) this.packVelocity = 0;
            return;
        }
        if (this.packSnap === null) this.packSnap = this.nearestPack();
        const distance = this.packSnap - this.packOffset;
        if (Math.abs(distance) < .1) { if (distance) this.scrollPacks(distance); this.packVelocity = 0; return; }
        this.scrollPacks(distance * (1 - Math.exp(-22 * dt)));
    }
    visibleControls() {
        const clip = this.taskViewport.getComponent(UITransform)!;
        return Array.from(this.controls.entries()).filter(([key, n]) => {
            if (key.startsWith('TaskFold:') || key.startsWith('TaskItem:')) return this.open && Math.abs(n.position.y + this.taskOffset) < clip.height / 2 - n.getComponent(UITransform)!.height / 2;
            if (key.startsWith('TopPack:')) return n.activeInHierarchy && this.packOpacity.get(key.slice(8))!.opacity >= 180;
            return true;
        });
    }
}
