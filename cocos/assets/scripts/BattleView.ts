import { Color, Font, Graphics, Label, Node, Sprite, SpriteFrame, UITransform, UIOpacity } from 'cc';
import { BoardView } from './BoardView';
import { GameModel } from './GameModel';
import { BATTLE_BUBBLE_OUTLINE } from './BattleBubbleOutline';
import { BATTLE_CARD_Y } from './CardView';

interface PlayArea { left: number; right: number; top: number; bottom: number; }
interface Popup { node: Node; ink: Graphics; time: number; y: number; }

/** Board.gd's arena, floating hit bubbles and reversible battle camera. */
export class BattleView {
    private root: Node;
    private art: Graphics;
    private left: Label;
    private right: Label;
    private popups: Popup[] = [];
    private id = 0;
    private clock = 0;
    private shownEnemy = 0;
    private shownPlayer = 0;
    private focusKey = '';
    private saved: { zoom: number; x: number; y: number } | null = null;
    private fadeTime = 0;
    get restoring() { return !this.id && this.saved !== null; }
    constructor(private board: BoardView, private font: Font, private damageFont: Font, private bubble: Promise<SpriteFrame>) {
        this.root = this.node('BattleArena', board.node, 1120, 656); this.root.setSiblingIndex(2);
        this.root.addComponent(UIOpacity);
        this.art = this.root.addComponent(Graphics);
        this.left = this.label('RivalFunds'); this.right = this.label('PlayerFunds');
        this.right.horizontalAlign = Label.HorizontalAlign.RIGHT;
        this.root.active = false;
    }
    private node(name: string, parent: Node, width: number, height: number) {
        const node = new Node(name); node.layer = parent.layer; parent.addChild(node);
        node.addComponent(UITransform).setContentSize(width, height); return node;
    }
    private label(name: string) {
        const node = this.node(name, this.root, 340, 120), label = node.addComponent(Label);
        node.getComponent(UITransform)!.setAnchorPoint(name === 'PlayerFunds' ? 1 : 0, 1);
        label.font = this.damageFont; label.useSystemFont = false; label.fontSize = 64; label.lineHeight = 60;
        label.color = new Color(43, 41, 38); label.horizontalAlign = Label.HorizontalAlign.LEFT;
        label.verticalAlign = Label.VerticalAlign.CENTER; label.overflow = Label.Overflow.SHRINK; label.enableWrapText = false;
        node.getComponent(UITransform)!.setContentSize(340, 120); return label;
    }
    reset() {
        this.id = 0; this.saved = null; this.focusKey = ''; this.root.active = false;
        for (const p of this.popups) p.node.destroy(); this.popups.length = 0;
    }
    update(model: GameModel, dt: number, area: PlayArea) {
        const b = model.battle, rect = model.battleRect;
        if (b && rect) {
            if (this.id !== b.id) {
                // A second encounter during the return keeps the original pre-battle view.
                this.saved = this.saved || { zoom: this.board.zoom, x: this.board.node.position.x, y: this.board.node.position.y };
                this.id = b.id; this.focusKey = ''; this.shownEnemy = b.enemyHp; this.shownPlayer = b.playerHp;
            }
            const key = [rect.x, rect.y, rect.height, area.left, area.right, area.top, area.bottom].join(':');
            if (key !== this.focusKey) {
                this.focusKey = key;
                const zoom = Math.max(.3, Math.min(this.saved!.zoom * 1.5, (area.right - area.left) / (rect.width + 64), (area.top - area.bottom) / (rect.height + 64)));
                this.board.animateTo(zoom, (area.left + area.right) / 2 - rect.x * zoom, (area.top + area.bottom) / 2 - rect.y * zoom * this.board.pitch, .6);
            }
            this.root.active = true; this.root.setPosition(rect.x, rect.y); this.root.setSiblingIndex(2);
            this.root.getComponent(UIOpacity)!.opacity = 255;
            this.root.getComponent(UITransform)!.setContentSize(rect.width, rect.height);
            this.clock += dt;
            const blend = 1 - Math.exp(-10 * dt);
            this.shownEnemy += (b.enemyHp - this.shownEnemy) * blend; this.shownPlayer += (b.playerHp - this.shownPlayer) * blend;
            this.left.string = `HP: $${Math.max(0, this.shownEnemy).toFixed(1)}\nATK: ${model.battleAttack('rival')}`;
            this.right.string = `HP: $${Math.max(0, this.shownPlayer).toFixed(1)}\nATK: ${model.battleAttack('player')}`;
            // Anchor the outside top corners: font and label size cannot alter margins.
            const top = rect.height / 2 - 72;
            this.left.node.setPosition(-rect.width / 2 + 80, top);
            this.right.node.setPosition(rect.width / 2 - 80, top);
            this.drawFrame(rect.width, rect.height);
        } else {
            if (this.id) {
                this.id = 0; this.focusKey = ''; this.fadeTime = 0;
                if (this.saved) this.board.animateTo(this.saved.zoom, this.saved.x, this.saved.y, .85);
            }
            if (this.saved) {
                this.fadeTime += dt;
                this.root.getComponent(UIOpacity)!.opacity = 255 * Math.max(0, 1 - this.fadeTime / .28);
                if (this.fadeTime >= .28) this.root.active = false;
                if (!this.board.moving) { this.saved = null; this.root.active = false; }
            }
        }
        for (const hit of model.battleHits.splice(0)) {
            const card = model.card(hit.uid); if (!card) continue;
            const position = model.position(card);
            // Launch the whole bubble from the victim's center, then rise above its title.
            this.popup(position.x, position.y + BATTLE_CARD_Y, hit.amount);
        }
        for (const popup of this.popups.slice()) {
            popup.time += dt; const t = popup.time;
            const grow = Math.min(1, t / .42), scale = 1 + 2.70158 * Math.pow(grow - 1, 3) + 1.70158 * Math.pow(grow - 1, 2);
            const launch = 268 * (1 - Math.pow(1 - Math.min(1, t / .55), 3));
            // Keep the late drift beneath the lowered statistics band.
            const drift = 6 * Math.sin(Math.min(1, Math.max(0, t - .55) / .75) * Math.PI / 2);
            popup.node.setScale(scale, scale, 1); popup.node.setPosition(popup.node.position.x, popup.y + launch + drift);
            const opacity = Math.round(255 * Math.max(0, 1 - Math.max(0, t - .9) / .4));
            popup.node.getComponent(UIOpacity)!.opacity = opacity;
            // Creator 3.8 Graphics stores stroke alpha in its mesh, outside UIOpacity's sprite path.
            if (popup.ink.strokeColor.a !== opacity) this.drawBubbleOutline(popup.ink, opacity);
            popup.node.setSiblingIndex(999999);
            if (t >= 1.3) { popup.node.destroy(); this.popups.splice(this.popups.indexOf(popup), 1); }
        }
    }
    private popup(x: number, y: number, amount: number) {
        const width = 280, height = width * 992 / 1586, outline = 2.6;
        const node = this.node('BattleDamage', this.board.node, width + outline * 2, height + outline * 2); node.setPosition(x, y); node.setScale(0, 0, 1); node.addComponent(UIOpacity);
        // Trace only the outer ink edge; a filled black copy would darken the paper as it fades.
        const edge = this.node('ComicBubbleOutline', node, width, height), ink = edge.addComponent(Graphics);
        ink.lineWidth = outline * 2; ink.lineJoin = Graphics.LineJoin.ROUND; this.drawBubbleOutline(ink, 255);
        const art = this.node('ComicBattleBubble', node, width, height), sprite = art.addComponent(Sprite); sprite.sizeMode = Sprite.SizeMode.CUSTOM;
        void this.bubble.then(frame => { if (sprite.isValid) sprite.spriteFrame = frame; });
        const text = this.node('Damage', node, 176, 104), label = text.addComponent(Label);
        label.font = this.damageFont; label.useSystemFont = false; label.fontSize = 82; label.lineHeight = 102;
        label.overflow = Label.Overflow.SHRINK; label.enableWrapText = false;
        label.color = new Color(138, 31, 31); label.string = '-' + amount.toFixed(0);
        label.horizontalAlign = Label.HorizontalAlign.CENTER; label.verticalAlign = Label.VerticalAlign.CENTER;
        text.getComponent(UITransform)!.setContentSize(176, 104);
        this.popups.push({ node, ink, time: 0, y });
    }
    private drawBubbleOutline(ink: Graphics, opacity: number) {
        const { width, height } = ink.node.getComponent(UITransform)!;
        ink.clear(); ink.strokeColor = new Color(0, 0, 0, opacity);
        for (let i = 0; i < BATTLE_BUBBLE_OUTLINE.length; i++) {
            const [px, py] = BATTLE_BUBBLE_OUTLINE[i];
            if (i) ink.lineTo(px * width, py * height); else ink.moveTo(px * width, py * height);
        }
        ink.close(); ink.stroke();
    }
    private drawFrame(width: number, height: number) {
        const g = this.art, radius = 28, x = width / 2, y = height / 2;
        g.clear(); g.fillColor = new Color(240, 61, 61, 25); g.roundRect(-x, -y, width, height, radius); g.fill();
        const points: { x: number; y: number }[] = [];
        const corners = [[x - radius, y - radius, 0], [x - radius, -y + radius, -Math.PI / 2], [-x + radius, -y + radius, -Math.PI], [-x + radius, y - radius, -Math.PI * 1.5]];
        for (const [cx, cy, start] of corners) for (let i = 0; i <= 8; i++) { const a = start + Math.PI / 2 - i / 8 * Math.PI / 2; points.push({ x: cx + Math.cos(a) * radius, y: cy + Math.sin(a) * radius }); }
        points.push(points[0]);
        g.lineCap = Graphics.LineCap.ROUND;
        for (const depth of [true, false]) {
            g.lineWidth = 9; g.strokeColor = depth ? new Color(143, 47, 53, 150) : new Color(239, 106, 106);
            let phase = this.clock * 90 % 44;
            for (let i = 1; i < points.length; i++) {
                const a = points[i - 1], b = points[i], length = Math.hypot(b.x - a.x, b.y - a.y);
                for (let p = -phase; p < length; p += 44) {
                    const from = Math.max(0, p), to = Math.min(length, p + 26); if (to <= from) continue;
                    const ox = depth ? 5 : 0, oy = depth ? -6 : 0;
                    g.moveTo(a.x + (b.x - a.x) * from / length + ox, a.y + (b.y - a.y) * from / length + oy);
                    g.lineTo(a.x + (b.x - a.x) * to / length + ox, a.y + (b.y - a.y) * to / length + oy);
                }
                phase = (phase + length) % 44;
            }
            g.stroke();
        }
    }
    snapshot() { return { active: this.root.active, battleId: this.id, cameraMoving: this.board.moving, restoring: this.restoring, savedView: this.saved, hp: [this.shownEnemy, this.shownPlayer], popups: this.popups.map(p => ({ time: p.time, x: p.node.position.x, y: p.node.position.y })) }; }
}
