import { _decorator, assetManager, AssetManager, Canvas, Component, EffectAsset, instantiate, JsonAsset, Label, Mask, Node, Prefab, screen, UITransform, UIOpacity, Vec2, Vec3, Color, SpriteFrame, Font, Graphics, sys, game, Game } from 'cc';
import { CardView } from './CardView';
import { BoardView } from './BoardView';
import { InputRouter, InputTarget } from './InputRouter';
import { LayoutMetrics, measureLayout } from './Layout';
import { Surface } from './Surface';
import { GameModel, Catalog, CardState, CashSpend, CARD_OFFSET, DEFAULT_HINT } from './GameModel';
import { OriginalHud } from './OriginalHud';
import { OriginalAudio } from './OriginalAudio';
import { BattleView } from './BattleView';
import { TitleScreen } from './TitleScreen';
import { CardInspector } from './CardInspector';
import { CardCatalog } from './CardCatalog';
import { MenuBackdrop } from './MenuBackdrop';
import { PROGRESS_KEY, readProgress, SavedGame, SavedView } from './ProgressSave';
const { ccclass } = _decorator;
type Modal = 'none' | 'detail' | 'inspect' | 'packs' | 'book' | 'catalog' | 'recipes' | 'tasks' | 'research' | 'settings' | 'home';
interface Entry { title: string; text?: string; action?: string; muted?: boolean; }
interface ViewState { view: CardView; patch: string; packCount?: number; }

@ccclass('Sample')
export class Sample extends Component implements InputTarget {
    inputScale = 1;
    private viewport!: Node;
    private board!: BoardView;
    private backdrop!: Node;
    private hud!: Node;
    private router!: InputRouter;
    private metrics!: LayoutMetrics;
    private model!: GameModel;
    private cardPrefab!: Prefab;
    private content!: AssetManager.Bundle;
    private views = new Map<number, ViewState>();
    private cashFlights = new Map<CardView, CashSpend>();
    private frames = new Map<string, Promise<SpriteFrame>>();
    private pending = 0;
    private modal: Modal = 'none';
    private menuPauseBefore = false;
    private atTitle = true;
    private hasStarted = false;
    private titleScreen!: TitleScreen;
    private cardInspector!: CardInspector;
    private cardCatalog!: CardCatalog;
    private menuBackdrop!: MenuBackdrop;
    private inspectorReturn: 'none' | 'catalog' = 'none';
    private catalogReturn: 'book' | 'home' = 'book';
    private settingsReturn: 'book' | 'home' = 'book';
    private testMode = true;
    private nightShift = false;
    private menuPressed: { node: Node; scale: Vec3; surface: Surface | null; fill: Color | null } | null = null;
    private saveAge = 0;
    private savedProgress = '';
    private restoredView: SavedView | null = null;
    private saveWarning = false;
    private flushProgress = () => { this.router?.cancel(); this.saveProgress(); };
    private visibilityChanged = () => { if (document.hidden) this.flushProgress(); };
    private page = 0;
    private pageCount = 1;
    private selected = 0;
    private selectedPack = 0;
    private catalogId = '';
    private linkSource = 0;
    private pressedAction = '';
    private pressedCard = 0;
    private pressedPack = 0;
    private dragging = false;
    private dragOffset = new Vec2();
    private dragPoint = new Vec2();
    private dragPointer = new Vec2();
    private sellReady = false;
    private researchPulse = 1;
    private cornerIconScale = 1;
    private controls = new Map<string, Node>();
    private loading!: Node;
    private ready = false;
    private lastError = '';
    private font!: Font;
    private panelW = 600;
    private panelH = 900;
    private lineArt!: Graphics;
    private matchArt!: Graphics;
    private matchTarget = 0;
    private matchClock = 0;
    private originalHud!: OriginalHud;
    private audio!: OriginalAudio;
    private battleView!: BattleView;
    private boardTop = 0;
    private statusLayoutKey = '';
    private statusHelp: Node | null = null;
    private statusHelpKey = '';
    private preventContext = (e: Event) => e.preventDefault();

    onLoad() {
        try { this.testMode = sys.localStorage.getItem('startx.test-mode') !== 'false'; } catch { /* Default testing on. */ }
        try { this.nightShift = sys.localStorage.getItem('startx.night-shift') === 'true'; } catch { /* Default night mode off. */ }
        this.metrics = measureLayout(); this.loading = this.makeNode('Loading', this.node, 640, 160);
        const label = this.loading.addComponent(Label); label.string = ''; label.fontSize = 28; label.color = new Color(55, 66, 57);
        this.loading.on(Node.EventType.TOUCH_END, () => { if (this.lastError) void this.loadSample(); });
        if (typeof document !== 'undefined') { document.addEventListener('contextmenu', this.preventContext); document.addEventListener('visibilitychange', this.visibilityChanged); }
        if (typeof window !== 'undefined') { window.addEventListener('pagehide', this.flushProgress); window.addEventListener('beforeunload', this.flushProgress); }
        game.on(Game.EVENT_HIDE, this.flushProgress, this);
        screen.on('window-resize', this.layout, this); void this.loadSample();
    }
    private bundle(name: string) { return new Promise<AssetManager.Bundle>((resolve, reject) => assetManager.loadBundle(name, (e, b) => e ? reject(e) : resolve(b))); }
    private async loadSample() {
        this.lastError = '';
        try {
            const [sample, content] = await Promise.all([this.bundle('sample'), this.bundle('content')]); this.content = content;
            const prefab = (name: string) => new Promise<Prefab>((resolve, reject) => sample.load('prefabs/' + name, Prefab, (e, p) => e ? reject(e) : resolve(p)));
            const [background, founder, hud, data, damageFont] = await Promise.all([prefab('Background'), prefab('FounderCard'), prefab('Hud'),
                new Promise<JsonAsset>((resolve, reject) => content.load('catalog', JsonAsset, (e, d) => e ? reject(e) : resolve(d))),
                new Promise<Font>((resolve, reject) => content.load('fonts/LilitaOne-Regular', Font, (e, f) => e ? reject(e) : resolve(f)))]);
            this.cardPrefab = founder;
            let raw: string | null = null; try { raw = sys.localStorage.getItem(PROGRESS_KEY); } catch { /* A fresh game remains available. */ }
            const restored = readProgress(data.json as Catalog, raw);
            this.model = restored?.model || new GameModel(data.json as Catalog, Math.random, this.testMode);
            this.hasStarted = !!restored; this.restoredView = restored?.view || null; this.savedProgress = restored ? raw! : '';
            if (restored) this.testMode = this.model.testMode;
            this.audio = this.node.addComponent(OriginalAudio); await this.audio.preload(content);
            this.backdrop = this.makeNode('Backdrop', this.node, 720, 1280);
            const fill = this.backdrop.addComponent(Surface); fill.fill = new Color(64, 68, 76); fill.radius = 0; fill.paint();
            this.viewport = this.makeNode('BoardViewport', this.node, 720, 1000); this.viewport.addComponent(Mask).type = Mask.Type.GRAPHICS_RECT;
            const boardNode = instantiate(background); this.viewport.addChild(boardNode); this.board = boardNode.getComponent(BoardView)!;
            this.board.setSurroundings(await this.loadFrame('board/city-surroundings-v2'));
            const lines = this.makeNode('SupplyLines', boardNode, 1, 1); this.lineArt = lines.addComponent(Graphics);
            const match = this.makeNode('InteractionHint', boardNode, 312, 312); this.matchArt = match.addComponent(Graphics); match.active = false;
            this.hud = instantiate(hud); this.node.addChild(this.hud); this.font = this.label('Status/Stage/Value').font!;
            this.battleView = new BattleView(this.board, this.font, damageFont, this.loadFrame('ui/battle-bubble-comic'));
            this.controls.set('Book', this.find('Toolbar/Book'));
            for (const a of ['Close', 'Back', 'Prev', 'Next']) this.controls.set(a, this.find('Panel/' + a));
            this.controls.set('Settings', this.find('Status/Settings')); this.controls.set('ResearchPanel', this.find('Research')); this.controls.set('SellZone', this.find('SellZone'));
            for (const name of ['Stage', 'Month', 'Supply', 'Space', 'Cash']) this.controls.set('StatusInfo:' + name, this.find('Status/' + name));
            this.originalHud = new OriginalHud(this.hud, this.model, this.font, this.controls, path => this.loadFrame(path));
            const titleNames = ['city', 'founder', 'rival', 'logo', 'star', 'coins'];
            const titleFrames: Record<string, SpriteFrame> = {};
            await Promise.all(titleNames.map(async name => { titleFrames[name] = await this.loadFrame('title/' + name); }));
            this.titleScreen = new TitleScreen(this.node, this.font, titleFrames, this.controls);
            this.titleScreen.node.setSiblingIndex(this.hud.getSiblingIndex());
            const [backFrame, catalogEffect, lineEffect] = await Promise.all([this.loadFrame('ui/card-back'),
                new Promise<EffectAsset>((resolve, reject) => content.load('ui/CatalogBlur', EffectAsset, (e, f) => e ? reject(e) : resolve(f))),
                new Promise<EffectAsset>((resolve, reject) => content.load('ui/WhiteLine', EffectAsset, (e, f) => e ? reject(e) : resolve(f)))]);
            this.cardCatalog = new CardCatalog(this.node, this.font, backFrame, catalogEffect, path => this.loadFrame(path), e => { this.lastError = String(e); console.error('[StartX] Catalog', e); });
            this.menuBackdrop = new MenuBackdrop(this.hud, catalogEffect, ['Panel', 'Scrim', 'Toolbar', 'TaskDrawer'].map(name => this.find(name)));
            this.menuBackdrop.node.setSiblingIndex(this.find('TaskDrawer').getSiblingIndex());
            this.find('Toolbar').setSiblingIndex(this.find('TaskDrawer').getSiblingIndex());
            this.cardInspector = new CardInspector(this.node, this.font, this.cardPrefab, backFrame, lineEffect, path => this.loadFrame(path));
            this.router = this.node.addComponent(InputRouter); this.router.target = this;
            this.ready = true; this.loading.active = false; this.selected = this.model.cards[0].uid;
            this.layout();
            if (this.restoredView) this.restoreBoard(this.restoredView); else this.frameOpening();
            this.show('home'); this.syncViews();
            if (typeof document !== 'undefined') document.getElementById('startx-loading')?.remove();
            if (typeof location !== 'undefined' && /(?:\?|&)review=1(?:&|$)/.test(location.search)) {
                (globalThis as unknown as { __STARTX_SAMPLE__?: () => unknown }).__STARTX_SAMPLE__ = () => this.snapshot();
            }
        } catch (e) {
            if (typeof document !== 'undefined') document.getElementById('startx-loading')?.remove();
            this.lastError = String(e); console.error('[StartX] Load failed', e); this.loading.getComponent(Label)!.string = '桌面加载失败\n点击重试';
        }
    }
    private loadFrame(path: string) {
        let task = this.frames.get(path);
        if (!task) { task = new Promise<SpriteFrame>((resolve, reject) => this.content.load(path + '/spriteFrame', SpriteFrame, (e, f) => e ? reject(e) : resolve(f))); this.frames.set(path, task); }
        return task;
    }
    private restoreBoard(view: SavedView) {
        this.board.reset(); this.board.setPitch(view.pitch); this.board.setZoom(view.zoom * this.inputScale);
        const p = this.board.node.position;
        this.board.pan(new Vec2(-view.centerX * this.board.zoom - p.x, -view.centerY * this.board.zoom * this.board.pitch - p.y));
    }
    private saveProgress() {
        if (!this.ready || !this.hasStarted || this.dragging) return;
        const paused = this.plainMenu || ['inspect', 'catalog'].includes(this.modal) ? this.menuPauseBefore : this.model.paused;
        const p = this.board.node.position;
        const save: SavedGame = { version: 1, model: this.model.saveProgress(paused), view: { zoom: this.board.zoom / this.inputScale,
            pitch: this.board.pitch, centerX: -p.x / this.board.zoom, centerY: -p.y / (this.board.zoom * this.board.pitch) } };
        const serialized = JSON.stringify(save);
        if (serialized === this.savedProgress) return;
        try { sys.localStorage.setItem(PROGRESS_KEY, serialized); this.savedProgress = serialized; this.saveWarning = false; }
        catch (e) { if (!this.saveWarning) console.warn('[StartX] Progress save failed', e); this.saveWarning = true; }
    }
    private async createView(uid: number, id: string, pack = false) {
        const node = instantiate(this.cardPrefab); node.name = (pack ? 'Pack-' : 'Card-') + id; this.board.node.addChild(node);
        const view = node.getComponent(CardView)!; this.views.set(uid, { view, patch: '' }); this.pending++;
        // Hide the shared prefab until its own original face is available.
        node.setScale(0, 0, 1);
        try {
            const frame = id === 'founder' && !pack ? null : await this.loadFrame((pack ? 'packs/' : 'faces/') + id);
            if (!node.isValid) return;
            const d = this.model.data.cards[id];
            view.configure(frame, d?.bodyColor || '141414', pack ? 'pack' : id === 'founder' ? 'foil' : id === 'cash' || d.type === 'business_model' ? 'glass' : 'plain');
            node.setScale(1, 1, 1);
            const appearance = this.model.appearances.get(uid); this.model.appearances.delete(uid);
            if (appearance) {
                view.appear(appearance, () => { if (appearance.landSound && this.model.card(uid)) this.audio.play(appearance.landSound); });
            }
        } catch (e) { this.lastError = String(e); console.error('[StartX] Card asset', id, e); this.model.say('卡面加载失败，请刷新重试'); }
        finally { this.pending--; }
    }
    private patch(v: ViewState, path: string, kind: 'uses' | 'account' | 'pack') {
        if (path === v.patch) return; v.patch = path;
        if (!path) { v.view.setPatch(null, kind); return; }
        this.loadFrame('patches/' + path).then(frame => { if (v.view.isValid && v.patch === path) v.view.setPatch(frame, kind); })
            .catch(e => { this.lastError = String(e); console.error('[StartX] Number patch', e); });
    }
    private flyCash(view: CardView, motion: CashSpend) {
        this.cashFlights.set(view, motion); view.node.setPosition(motion.from.x, motion.from.y);
        this.placeCashBelowTarget(view, motion);
        view.spend(() => {
            const target = this.model.card(motion.targetUid);
            return target ? this.model.position(target) : motion.to;
        }, motion.delay, () => this.audio.play('cash_down'), () => { this.cashFlights.delete(view); view.node.destroy(); });
    }
    private placeCashBelowTarget(view: CardView, payment: CashSpend) {
        const target = this.views.get(payment.targetUid)?.view.node, index = target?.getSiblingIndex() ?? 2;
        view.node.setSiblingIndex(Math.max(0, index - (view.node.getSiblingIndex() < index ? 1 : 0)));
    }
    private async accountCash(motion: CashSpend) {
        const node = instantiate(this.cardPrefab); node.name = 'CashPayment'; node.setScale(0, 0, 1); this.board.node.addChild(node); this.pending++;
        const model = this.model;
        try {
            const frame = await this.loadFrame('faces/cash'); if (!node.isValid) return;
            if (model !== this.model) { node.destroy(); return; }
            const view = node.getComponent(CardView)!; view.configure(frame, this.model.def('cash').bodyColor, 'glass');
            node.setScale(1, 1, 1); this.flyCash(view, motion);
        } catch (e) { node.destroy(); this.lastError = String(e); console.error('[StartX] Cash payment', e); }
        finally { this.pending--; }
    }
    private syncViews() {
        // CardView.onLoad runs only on an active board; create its views when play starts.
        if (this.atTitle) return;
        // City, table, then battle and cards: moving cards must never push the opaque table above them.
        this.board.node.getChildByName('Table')!.setSiblingIndex(1);
        for (const sound of this.model.soundCues.splice(0)) this.audio.play(sound);
        const cashSpends = this.model.cashSpends.splice(0), spending = new Map(cashSpends.filter(m => m.uid !== undefined).map(m => [m.uid!, m]));
        const live = new Set(this.model.cards.map(c => c.uid).concat(this.model.packs.map(p => p.uid)));
        for (const [uid, v] of Array.from(this.views.entries())) if (!live.has(uid)) {
            this.views.delete(uid);
            const payment = spending.get(uid);
            if (payment && v.view.node.scale.x > 0) { this.flyCash(v.view, payment); spending.delete(uid); }
            else if (v.view.pack || this.model.defeated.delete(uid)) v.view.dissolve(() => v.view.node.destroy()); else v.view.node.destroy();
        }
        for (const motion of cashSpends) if (motion.uid === undefined || spending.has(motion.uid)) void this.accountCash(motion);
        for (const c of this.model.cards) if (!this.views.has(c.uid)) void this.createView(c.uid, c.id);
        for (const p of this.model.packs) if (!this.views.has(p.uid)) void this.createView(p.uid, p.id, true);
        for (const [uid, from] of this.model.displacements) {
            const card = this.model.card(uid), view = this.views.get(uid)?.view;
            if (card && view) {
                const start = view.isSliding ? this.board.node.getComponent(UITransform)!.convertToNodeSpaceAR(view.frontNode.worldPosition) : from;
                const to = this.model.position(card); view.node.setPosition(to.x, to.y); view.slideFrom(start.x, start.y);
            }
            this.model.displacements.delete(uid);
        }
        const workbars = new Map<number, { ratio: number; active: boolean }>();
        for (const s of this.model.stacks) {
            const p = this.model.production(s.sid);
            const target = p?.target || this.model.members(s.sid).find(c => c.workRequired > 0 && c.elapsed > 0);
            // Keep progress on its original production target; draw once above the stack's base card.
            if (target && target.workRequired) workbars.set(s.cards[0], { ratio: target.elapsed / target.workRequired, active: !!p });
        }
        let z = 4;
        for (const s of this.model.stacks) for (const uid of s.cards) {
            const c = this.model.card(uid)!, v = this.views.get(uid); if (!v) continue;
            const position = this.model.position(c);
            v.view.setCombat(this.model.battlePose(uid));
            v.view.setBattle(this.model.isCombatant(c.sid));
            if (!(this.dragging && this.movingIds().includes(uid))) { v.view.node.setPosition(position.x, position.y); v.view.node.setSiblingIndex(z++); }
            if (c.uses >= 0) this.patch(v, c.id + '-' + c.uses, 'uses');
            else if (c.id === 'p3_account') this.patch(v, 'account-' + c.stored, 'account');
            const work = workbars.get(uid); v.view.setProgress(work?.ratio || 0, work?.active || false);
        }
        for (const p of this.model.packs) {
            const v = this.views.get(p.uid); if (!v) continue;
            if (!(this.dragging && this.pressedPack === p.uid)) v.view.node.setPosition(p.x, p.y);
            if (v.packCount !== undefined && p.contents.length < v.packCount) v.view.pulse();
            v.packCount = p.contents.length;
            v.view.node.setSiblingIndex(z++); this.patch(v, 'pack-' + p.contents.length, 'pack');
        }
        let bottom = 3;
        for (const s of this.model.stacks) for (const uid of s.cards) {
            const view = this.views.get(uid)?.view; if (view?.isSliding) view.node.setSiblingIndex(bottom++);
        }
        for (const v of this.views.values()) if (v.view.isAppearing) v.view.node.setSiblingIndex(z++);
        const attacker = this.model.battle && this.model.card(this.model.battle.attacker);
        if (attacker) {
            for (const member of this.model.members(attacker.sid)) this.views.get(member.uid)?.view.node.setSiblingIndex(z++);
            this.views.get(attacker.uid)?.view.node.setSiblingIndex(z++);
        }
        for (const hit of this.model.battleHits) this.views.get(hit.uid)?.view.hit();
        if (this.dragging) this.movingIds().forEach(uid => this.views.get(uid)?.view.node.setSiblingIndex(z++));
        for (const [view, payment] of this.cashFlights) this.placeCashBelowTarget(view, payment);
        const founder = this.model.cards.find(c => c.id === 'founder');
        this.board.setNightShift(this.nightShift, founder ? this.views.get(founder.uid)?.view.frontNode || null : null);
        this.drawLinks();
    }
    update(dt: number) {
        if (!this.ready) return;
        this.titleScreen.tick(dt);
        this.cardInspector.tick(dt);
        this.model.update(Math.min(dt, .1)); this.syncViews();
        const bottomBar = this.find('BottomBar');
        this.battleView.update(this.model, this.model.paused ? 0 : Math.min(dt, .1), {
            left: -this.metrics.width / 2 + 40, right: this.metrics.width / 2 - 24, top: this.boardTop - 24,
            bottom: bottomBar.position.y + bottomBar.getComponent(UITransform)!.height / 2 + 80,
        });
        this.updateCornerFeedback(dt);
        this.updateDropHint(dt);
        this.originalHud.tick(dt, this.modal === 'none' && !this.atTitle);
        this.saveAge += dt; if (this.saveAge >= .75) { this.saveAge = 0; this.saveProgress(); }
        this.label('Status/Cash/Value').string = this.model.payroll + '/' + this.model.cash;
        this.label('Status/Month/Value').string = '第' + this.model.month + '月';
        const stagePack = this.model.data.packOrder.find(id => this.model.data.packs[id].stage === this.model.stage);
        this.label('Status/Stage/Value').string = `阶段「${this.model.paused ? '已暂停' : stagePack ? this.model.data.packs[stagePack].name.replace(/包$/, '') : this.model.stageName}」`;
        this.label('Status/Supply/Value').string = this.model.links.length + '/' + this.model.supplyLimit;
        this.label('Status/Space/Value').string = this.model.count + '/' + this.model.capacity;
        this.label('Status/Space/Value').color = this.model.count > this.model.capacity ? new Color(255, 176, 170) : new Color(247, 247, 247);
        this.layoutStatus();
        const progress = this.find('Status/Progress'), slot = this.find('Status/ProgressSlot'), width = slot.getComponent(UITransform)!.width;
        const ratio = Math.max(0, this.model.monthTime / (this.model.data.balance.month_seconds || 180));
        progress.getComponent(UITransform)!.setContentSize(Math.max(1, width * ratio), slot.getComponent(UITransform)!.height);
        progress.setPosition(slot.position.x - width * (1 - ratio) / 2, slot.position.y);
        this.find('Hint').active = !this.atTitle;
        if (this.atTitle) this.find('TaskReminder').active = false;
        const battle = this.model.battle;
        this.label('Hint').string = battle ? `商战  对手资金 ${Math.max(0, battle.enemyHp).toFixed(1)} · 我方资金 ${Math.max(0, battle.playerHp).toFixed(1)}` :
            this.linkSource ? '点击目标牌堆连接供应链 · 点击空白处取消' : this.model.notice.startsWith('「') ? this.model.notice : `「${this.model.notice}」`;
    }
    private makeNode(name: string, parent: Node, w: number, h: number) {
        const n = new Node(name); n.layer = this.node.layer; parent.addChild(n); n.addComponent(UITransform).setContentSize(w, h); return n;
    }
    private text(parent: Node, name: string, value: string, w: number, h: number, x: number, y: number, size = 24, color = '52634D') {
        const n = this.makeNode(name, parent, w, h); n.setPosition(x, y); const l = n.addComponent(Label);
        l.font = this.font; l.useSystemFont = false; l.fontSize = size; l.lineHeight = size * 1.45; l.string = value;
        l.color = Color.fromHEX(new Color(), '#' + color); l.horizontalAlign = Label.HorizontalAlign.LEFT; l.verticalAlign = Label.VerticalAlign.CENTER;
        l.overflow = Label.Overflow.SHRINK; l.enableWrapText = true;
        // Label initialization may resize its UITransform; apply the authored box last.
        n.getComponent(UITransform)!.setContentSize(w, h); return n;
    }
    private find(path: string) { return this.hud.getChildByPath(path)!; }
    private label(path: string) { return this.find(path).getComponent(Label)!; }
    private position(path: string, x: number, y: number, w?: number, h?: number) {
        const n = this.find(path); n.setPosition(x, y); if (w !== undefined && h !== undefined) n.getComponent(UITransform)!.setContentSize(w, h);
    }
    private hideStatusInfo() {
        if (this.statusHelp) this.statusHelp.active = false;
        this.statusHelpKey = '';
    }
    private showStatusInfo(name: string) {
        if (this.statusHelpKey === name) { this.hideStatusInfo(); return; }
        const info: Record<string, [string, string]> = {
            Stage: ['创业阶段', '显示当前创业阶段，随公司估值提升而变化。完成公司任务可解锁更多卡包。'],
            Month: ['月份', '显示当前月份。获得办公室后开始计时，顶部进度条走完时结算工资。'],
            Supply: ['供应链', '前一项是已连接的供应链数量，后一项是连接上限。连接后，产出会自动送入目标牌堆。'],
            Space: ['空间', '前一项是占用空间的卡牌数量，后一项是空间上限。散装现金不占空间；月末超出上限时需要清理卡牌。'],
            Cash: ['现金', '前一项是本月工资，后一项是可用现金总额（含账户）。月末先扣散装现金，再扣账户现金。'],
        };
        const entry = info[name]; if (!entry) return;
        const { width: w, scale } = this.metrics, width = Math.min(320 * scale, w - 24 * scale);
        const padding = 14 * scale, titleH = 25 * scale;
        if (!this.statusHelp) {
            this.statusHelp = this.makeNode('StatusHelp', this.hud, width, 1);
            const surface = this.statusHelp.addComponent(Surface);
            surface.fill = new Color(255, 247, 232); surface.stroke = new Color(117, 111, 99);
            this.text(this.statusHelp, 'Title', '', width, titleH, 0, 0).getComponent(Label)!.isBold = true;
            this.text(this.statusHelp, 'Text', '', width, 1, 0, 0);
        }
        const box = this.statusHelp; box.active = true; box.setSiblingIndex(this.hud.children.length - 1);
        const body = box.getChildByName('Text')!.getComponent(Label)!;
        body.fontSize = 15 * scale; body.lineHeight = 22 * scale;
        body.overflow = Label.Overflow.RESIZE_HEIGHT; body.string = entry[1];
        body.node.getComponent(UITransform)!.setContentSize(width - padding * 2, 1);
        body.updateRenderData(true);
        const bodyH = body.node.getComponent(UITransform)!.height, height = padding * 2 + titleH + bodyH;
        box.getComponent(UITransform)!.setContentSize(width, height);
        const title = box.getChildByName('Title')!.getComponent(Label)!;
        title.string = entry[0]; title.fontSize = 18 * scale; title.lineHeight = titleH;
        title.node.getComponent(UITransform)!.setContentSize(width - padding * 2, titleH);
        title.node.setPosition(0, height / 2 - padding - titleH / 2);
        body.node.setPosition(0, height / 2 - padding - titleH - bodyH / 2);
        const anchor = this.find('Status/' + name), status = this.find('Status');
        const x = status.position.x + anchor.position.x, edge = w / 2 - width / 2 - 12 * scale;
        box.setPosition(Math.max(-edge, Math.min(edge, x)), status.position.y + anchor.position.y - anchor.getComponent(UITransform)!.height / 2 - 8 * scale - height / 2);
        const surface = box.getComponent(Surface)!; surface.radius = 10 * scale; surface.lineWidth = scale; surface.paint();
        this.statusHelpKey = name;
    }
    private layoutStatus() {
        const { width: w, height: h, top, wide, nearSquare, scale } = this.metrics;
        const unit = nearSquare ? .75 * scale : wide ? w / 1920 : 1;
        const margin = wide ? 30 * unit : 22, rightMargin = Math.max(8 * scale, margin - 12 * unit);
        const progressH = Math.max(3 * unit, 3 * scale), rowH = Math.max(34 * scale, 44 * unit);
        const y = h / 2 - (wide ? 0 : top) - progressH - rowH / 2 - 2 * unit - this.find('Status').position.y;
        const settingsX = w / 2 - rightMargin - 24 * scale + (wide ? 16 * unit : 6 * scale);
        const names = ['Stage', 'Month', 'Supply', 'Space', 'Cash'];
        const key = [w, h, scale, wide, nearSquare, top, ...names.map(name => this.label('Status/' + name + '/Value').string)].join(':');
        if (key === this.statusLayoutKey) return;
        this.statusLayoutKey = key;
        const settingsSize = wide ? 34 * unit : 32;
        this.position('Status/Settings', settingsX, y, 48 * scale, 44 * scale);
        this.position('Status/Settings/Icon', 0, 0, settingsSize, settingsSize);
        const icon = wide ? 32 * unit : 28, font = wide ? 26 * unit : 24;
        const gap = 4 * scale, groupGapMin = 6 * scale;
        const left = -w / 2 + margin, right = settingsX - settingsSize / 2;
        const groups = names.map(name => {
            const label = this.label('Status/' + name + '/Value');
            label.fontSize = font; label.lineHeight = font * 1.2;
            label.enableWrapText = false; label.overflow = Label.Overflow.NONE;
            label.updateRenderData(true);
            return { name, label, textWidth: label.node.getComponent(UITransform)!.width + scale };
        });
        const contentWidth = groups.reduce((sum, group) => sum + icon + group.textWidth, 0);
        // Only group gaps absorb spare space; keep the icon-to-value gap fixed in screen pixels.
        const fit = Math.min(1, (right - left - groups.length * gap - groups.length * groupGapMin) / contentWidth);
        const groupGap = (right - left - contentWidth * fit - groups.length * gap) / groups.length;
        let x = left;
        for (const { name, label, textWidth } of groups) {
            const iconSize = icon * fit, textSize = textWidth * fit, width = iconSize + gap + textSize;
            this.position('Status/' + name, x + width / 2, y, width, rowH);
            this.position('Status/' + name + '/Icon', -width / 2 + iconSize / 2, 0, iconSize, iconSize);
            label.fontSize = font * fit; label.lineHeight = label.fontSize * 1.2;
            label.overflow = Label.Overflow.CLAMP;
            label.horizontalAlign = Label.HorizontalAlign.LEFT; label.verticalAlign = Label.VerticalAlign.CENTER;
            this.position('Status/' + name + '/Value', -width / 2 + iconSize + gap + textSize / 2, 0, textSize, rowH);
            x += width + groupGap;
        }
    }
    private layout() {
        if (!this.ready) return;
        this.menuBackdrop.cancelCapture(); this.cardCatalog.cancelCapture();
        this.hideStatusInfo();
        this.router?.cancel(); this.metrics = measureLayout();
        const { width: w, height: h, top: measuredTop, bottom: measuredBottom, wide, nearSquare, scale } = this.metrics; this.inputScale = scale;
        this.model.setViewport(w, h);
        const top = wide ? 0 : measuredTop, bottom = wide ? 0 : measuredBottom;
        this.node.getComponent(UITransform)!.setContentSize(w, h); this.backdrop.getComponent(UITransform)!.setContentSize(w, h);
        const unit = nearSquare ? .75 * scale : wide ? w / 1920 : 1, margin = wide ? 30 * unit : 22;
        const topY = h / 2 - top, progressH = Math.max(3 * unit, 3 * scale);
        const rowH = Math.max(34 * scale, 44 * unit), statusH = rowH + progressH + 4 * unit;
        this.position('Status', 0, h / 2 - (statusH + top) / 2, w, statusH + top);
        this.statusLayoutKey = ''; this.layoutStatus();
        this.position('Status/ProgressSlot', 0, h / 2 - progressH / 2 - this.find('Status').position.y, w, progressH);
        const progressSize = this.find('Status/ProgressSlot').getComponent(UITransform)!.contentSize;
        this.find('Status/Progress').getComponent(UITransform)!.setContentSize(progressSize);
        const footerH = wide ? Math.max(44 * unit, 30 * scale) : Math.max(68, 36 * scale);
        const footerY = -h / 2 + bottom + footerH / 2;
        this.position('BottomBar', 0, -h / 2 + (bottom + footerH) / 2, w, bottom + footerH);
        for (const name of ['Hint', 'TaskReminder']) {
            this.position(name, 0, footerY, w - margin * 2, footerH);
            const label = this.label(name); label.fontSize = wide ? 29 * unit : 26;
            label.lineHeight = label.fontSize * 1.2; label.verticalAlign = Label.VerticalAlign.CENTER;
        }
        this.position('Toolbar', 0, 0, w, h);
        const cornerTarget = Math.max(80 * unit, 64 * scale), cornerArt = Math.max(80 * unit, 60 * scale) * .9;
        this.cornerIconScale = cornerArt / 64;
        for (const [name, direction] of [['Research', -1], ['SellZone', 1]] as const) {
            this.position(name, direction * (w / 2 - margin - cornerTarget / 2), -h / 2 + bottom + footerH + 12 * scale + cornerTarget / 2, cornerTarget, cornerTarget);
            this.position(name + '/Icon', 0, 0, 64, 64);
            this.find(name + '/Icon').setScale(this.cornerIconScale, this.cornerIconScale, 1);
            this.find(name + '/Feedback').setScale(cornerTarget / 64, cornerTarget / 64, 1);
        }
        const stripH = wide ? 112 * unit : Math.max(128, 72 * scale), stripTop = topY - statusH - 12 * unit;
        const stripW = w - margin * 2;
        this.boardTop = stripTop - stripH - 20;
        this.originalHud.layout(w, stripTop - stripH / 2, stripH, stripW, -h / 2 + bottom + footerH + 16 * unit, scale, wide, unit, nearSquare);
        const hint = this.label('Hint'), reminder = this.label('TaskReminder'), reminderH = hint.lineHeight * 2.2;
        this.position('TaskReminder', 0, stripTop - stripH - 10 * scale - reminderH / 2, w - margin * 2, reminderH);
        reminder.font = hint.font; reminder.fontSize = hint.fontSize; reminder.lineHeight = hint.lineHeight;
        reminder.horizontalAlign = hint.horizontalAlign; reminder.color = new Color(58, 53, 47);
        this.viewport.getComponent(UITransform)!.setContentSize(w, h);
        this.board.configure(w, h, { left: -w / 2 + this.find('Toolbar/Book').getComponent(UITransform)!.width + 24 * scale,
            right: w / 2 - 24 * scale, top: this.boardTop - 36 * scale, bottom: -h / 2 + bottom + footerH + 24 * scale });
        this.position('Scrim', 0, 0, w, h);
        this.titleScreen.layout(this.metrics);
        this.cardCatalog.layout(this.metrics);
        this.cardInspector.layout(this.metrics);
        this.menuBackdrop.layout(this.metrics);
        this.layoutPanel();
        if (this.modal === 'catalog') this.cardCatalog.capture(this.node.getComponent(Canvas)!.cameraComponent!);
        this.syncMenuBackdrop(true);
    }
    private layoutPanel() {
        const { width: w, height: h, wide, scale } = this.metrics;
        const top = wide ? 0 : this.metrics.top, bottom = wide ? 0 : this.metrics.bottom;
        const unit = wide ? w / 1920 : 1, target = Math.max(52.8 * unit, 44 * scale), research = this.modal === 'research';
        this.panelW = research ? wide ? Math.min(680 * unit, w - 48 * scale) : w - 48 : wide ? 500 : w - 32;
        this.panelH = research ? Math.min(wide ? 700 * unit : 900, h - top - bottom - 72 * scale) : Math.min(wide ? 820 : 1080, h - top - bottom - 36);
        const pw = this.panelW, ph = this.panelH;
        this.position('Panel', research ? 0 : wide ? w / 2 - pw / 2 - 20 : 0, research ? 0 : wide ? (bottom - top) / 2 : -h / 2 + bottom + ph / 2 + 8, pw, ph);
        this.position('Panel/Eyebrow', -pw / 2 + 170, ph / 2 - 36, 280, 30);
        this.position('Panel/Title', -30, ph / 2 - 91, pw - 100, 64);
        this.position('Panel/Close', pw / 2 - 54, ph / 2 - 48, target, target);
        this.position('Panel/Rule', 0, ph / 2 - 140, pw - 48, 2);
        this.position('Panel/Content', 0, -8, pw - 48, ph - 300);
        this.position('Panel/Back', 0, -ph / 2 + 60, pw - target * 2 - 72, target);
        this.position('Panel/Prev', -pw / 2 + 58, -ph / 2 + 60, target, target);
        this.position('Panel/Next', pw / 2 - 58, -ph / 2 + 60, target, target);
        this.position('Panel/Page', 0, -ph / 2 + 120, 200, 32);
        const plain = this.plainMenu, panelSurface = this.find('Panel').getComponent(Surface)!;
        panelSurface.fill.a = plain ? 0 : research ? 212 : 255; panelSurface.lineWidth = plain ? 0 : 2;
        panelSurface.radius = research ? Math.max(14 * unit, 10 * scale) : 26; panelSurface.paint();
        const scrim = this.find('Scrim').getComponent(Surface)!; scrim.fill.a = 0; scrim.paint();
        for (const name of ['Eyebrow', 'Title', 'Close', 'Rule', 'Back', 'Page']) this.find('Panel/' + name).active = !plain;
        this.label('Panel/Title').fontSize = research ? Math.max(30 * unit, 20 * scale) : 38;
        this.label('Panel/Eyebrow').fontSize = research ? Math.max(16 * unit, 11 * scale) : 18;
        this.label('Panel/Page').fontSize = research ? Math.max(16 * unit, 11 * scale) : 20;
        this.label('Panel/Back/Text').fontSize = research ? Math.max(22 * unit, 13 * scale) : 24;
        for (const name of ['Title', 'Eyebrow', 'Page', 'Back/Text']) {
            const label = this.label('Panel/' + name); label.lineHeight = label.fontSize * (research ? 1.2 : 1.5);
        }
        if (research) {
            const padding = Math.max(18 * unit, 12 * scale), header = Math.max(110 * unit, 74 * scale), footer = Math.max(98 * unit, 70 * scale);
            this.position('Panel/Eyebrow', -target / 2, ph / 2 - padding - 10 * scale, pw - padding * 2 - target, 20 * scale);
            this.position('Panel/Title', -target / 2, ph / 2 - padding - 37 * scale, pw - padding * 2 - target, 36 * scale);
            this.position('Panel/Close', pw / 2 - padding - target / 2, ph / 2 - padding - target / 2, target, target);
            this.position('Panel/Rule', 0, ph / 2 - header + 6 * scale, pw - padding * 2, 1);
            this.position('Panel/Content', 0, (footer - header) / 2, pw - padding * 2, ph - header - footer);
            this.position('Panel/Back', 0, -ph / 2 + padding + target / 2, pw - target * 2 - padding * 4, target);
            this.position('Panel/Prev', -pw / 2 + padding + target / 2, -ph / 2 + padding + target / 2, target, target);
            this.position('Panel/Next', pw / 2 - padding - target / 2, -ph / 2 + padding + target / 2, target, target);
            this.position('Panel/Page', 0, -ph / 2 + footer - 9 * scale, 200, 16 * scale);
        }
        if (plain) {
            const rows = this.menuRows, availableHeight = h - top - bottom - 56 * scale;
            const rowHeight = Math.min(52 * scale, (availableHeight - 50 * scale) / 6);
            const height = rows * rowHeight + (rows - 1) * 10 * scale;
            this.panelW = Math.min(320 * scale, w - 48 * scale) * .7; this.panelH = height;
            this.position('Panel', 0, (bottom - top) / 2, this.panelW, height);
            this.position('Panel/Content', 0, 0, this.panelW, height);
        }
        if (this.modal !== 'none') this.renderPanel();
    }
    private get plainMenu() { return ['book', 'settings', 'home'].includes(this.modal); }
    private get fullscreenAvailable() { return typeof document !== 'undefined' && !!document.fullscreenEnabled; }
    private get menuRows() { return this.modal === 'settings' ? 5 + (this.fullscreenAvailable ? 1 : 0) : this.entries().length; }
    private show(modal: Modal, resetPage = true) {
        // A new overlay must not capture through another overlay's temporary camera target.
        this.menuBackdrop.cancelCapture(); this.cardCatalog.cancelCapture();
        this.releaseMenuPress();
        this.hideStatusInfo();
        if (modal !== 'none') this.originalHud.close();
        const previous = this.modal;
        const wasPlain = this.plainMenu || ['inspect', 'catalog'].includes(this.modal), nextPlain = ['book', 'settings', 'home', 'inspect', 'catalog'].includes(modal);
        if (!wasPlain && nextPlain) { this.menuPauseBefore = this.model.paused; this.model.paused = true; }
        if (wasPlain && !nextPlain) this.model.paused = this.menuPauseBefore;
        this.modal = modal; if (resetPage) this.page = 0;
        this.find('Panel').active = !['none', 'home', 'inspect', 'catalog'].includes(modal); this.find('Scrim').active = !['none', 'home', 'inspect', 'catalog'].includes(modal);
        this.cardInspector.node.active = modal === 'inspect';
        this.find('Toolbar').active = modal === 'none' && !this.atTitle;
        this.titleScreen.show(this.atTitle, modal === 'home', this.hasStarted);
        this.viewport.active = !this.atTitle;
        for (const name of ['Status', 'PackStrip', 'BottomBar', 'Hint', 'TaskReminder', 'Research', 'SellZone']) this.find(name).active = !this.atTitle;
        this.layoutPanel();
        if (modal === 'catalog') {
            if (previous !== 'inspect') { this.cardCatalog.open(this.model, this.metrics); this.cardCatalog.capture(this.node.getComponent(Canvas)!.cameraComponent!); }
            else this.cardCatalog.node.active = true;
        } else if (!(modal === 'inspect' && this.inspectorReturn === 'catalog')) this.cardCatalog.hide();
        this.syncMenuBackdrop();
    }
    private syncMenuBackdrop(refresh = false) {
        const menu = !['none', 'home', 'inspect', 'catalog'].includes(this.modal);
        if (menu || this.modal === 'none' && this.originalHud.open) this.menuBackdrop.show(this.node.getComponent(Canvas)!.cameraComponent!, refresh);
        else this.menuBackdrop.hide();
    }
    private entries(): Entry[] {
        const m = this.model, d = m.data;
        switch (this.modal) {
            case 'book': return [
                { title: '继续', action: 'Continue' }, { title: '重新开始', action: 'Restart' },
                { title: '图鉴', action: 'Open:catalog' }, { title: '商业模式', action: 'MenuRecipes' },
                { title: '设置', action: 'OpenSettings' }, { title: '回到主菜单', action: 'Home' },
            ];
            case 'home': return [{ title: '开始游戏', action: 'Restart' }, { title: '继续游戏', action: 'Continue' }, { title: '设置', action: 'OpenSettings' }];
            case 'packs': return d.packOrder.map(id => ({ title: d.packs[id].name + `  $${d.packs[id].price}`, text: m.packUnlocked(id) ? `${d.packs[id].minCards}–${d.packs[id].maxCards} 张 · 点击购买卡包` : m.packRequirement(id), action: 'Buy:' + id, muted: !m.packUnlocked(id) }));
            case 'recipes': return d.recipes.map(r => ({ title: m.models.has(r.id) ? r.name : '尚未发现的商业模式', text: m.models.has(r.id) ? r.formula + (r.worker_tags.length ? '\n需要员工参与' : '') : `在${d.packs[r.packId]?.name || ''}中寻找，或亲自叠牌发现`, muted: !m.models.has(r.id) }));
            case 'tasks': return d.tasks.map(t => ({ title: (m.completed.has(t.id) ? '✓ ' : '') + t.title,
                text: t.content + (m.completed.has(t.id) ? ' · 已完成' : ` (${m.counters[t.triggerType + '|' + t.targetId] || 0}/${t.targetCount})`) }));
            case 'research': return Object.keys(d.research).sort((a, b) => d.research[a].stage - d.research[b].stage).map(id => {
                const r = d.research[id], done = m.ideas.has(id), prereq = r.prereq.map(k => d.research[k]?.name).join('、');
                return { title: (done ? '✓ ' : '') + r.name + ` · ${r.cost} RP`, text: r.desc + (!done ? `\n${['车库', '验证', '产品', '获客', '规模', '融资', '上市'][r.stage]}阶段` + (prereq ? ' · 前置：' + prereq : '') : ''), action: 'Research:' + id, muted: !m.canResearch(id) && !done };
            });
            default: return [];
        }
    }
    private renderPanel() {
        const content = this.find('Panel/Content'); content.children.slice().forEach(n => n.destroy());
        for (const action of Array.from(this.controls.keys())) if (action.startsWith('Row:')) this.controls.delete(action);
        if (this.modal === 'home' || this.modal === 'inspect' || this.modal === 'catalog') return;
        if (this.plainMenu) { this.renderMenu(content); return; }
        const titles: Record<string, string> = { book: '设置', packs: '抽取卡包', catalog: '卡牌图鉴', recipes: '商业模式', tasks: '公司任务', research: '研发', detail: '卡牌详情' };
        this.label('Panel/Title').string = titles[this.modal] || '';
        this.label('Panel/Eyebrow').string = this.modal === 'research' ? `STARTX  /  ${this.model.rp.toFixed(0)} RP` : 'STARTX';
        const { width, height } = content.getComponent(UITransform)!.contentSize;
        if (this.modal === 'detail') { this.renderDetail(content, width, height); this.pageCount = 1; }
        else {
            const research = this.modal === 'research', unit = this.metrics.wide ? this.metrics.width / 1920 : 1;
            const rowSize = research ? Math.max(116 * unit, 80 * this.inputScale) : 132;
            const rows = this.entries(), perPage = Math.max(research ? 1 : 3, Math.floor(height / rowSize)); this.pageCount = Math.max(1, Math.ceil(rows.length / perPage));
            this.page = Math.max(0, Math.min(this.pageCount - 1, this.page));
            rows.slice(this.page * perPage, (this.page + 1) * perPage).forEach((r, i) => {
                const rowHeight = Math.min(research ? rowSize : 128, height / perPage), y = height / 2 - rowHeight * (i + .5);
                this.row(content, r, width, rowHeight - (research ? 5 * this.inputScale : 10), y, research);
            });
        }
        this.find('Panel/Prev').active = this.pageCount > 1; this.find('Panel/Next').active = this.pageCount > 1;
        this.label('Panel/Page').string = this.pageCount > 1 ? `${this.page + 1} / ${this.pageCount}` : '';
        this.label('Panel/Back/Text').string = this.modal === 'book' || this.modal === 'detail' || this.modal === 'packs' ? '回到棋盘' : '返回手册';
    }
    private menuButton(parent: Node, text: string, action: string, width: number, height: number, x: number, y: number, font = 23) {
        const scale = this.inputScale, node = this.makeNode('Option', parent, width, height); node.setPosition(x, y);
        const border = node.addComponent(Surface); border.fill = new Color(252, 248, 238); border.stroke = Color.BLACK.clone();
        border.lineWidth = 4 * scale; border.radius = 3 * scale; border.paint();
        const inner = this.makeNode('InnerRule', node, width - 14 * scale, height - 14 * scale), rule = inner.addComponent(Surface);
        rule.fill.a = 0; rule.stroke = Color.BLACK.clone(); rule.lineWidth = .8 * scale; rule.radius = 1 * scale; rule.paint();
        this.text(node, 'Text', text, width - 20 * scale, height - 12 * scale, 0, 0, font * scale, '171614').getComponent(Label)!.horizontalAlign = Label.HorizontalAlign.CENTER;
        this.controls.set('Row:' + action, node); return node;
    }
    private renderMenu(content: Node) {
        this.pageCount = 1;
        for (const name of ['Prev', 'Next']) this.find('Panel/' + name).active = false;
        const scale = this.inputScale, width = this.panelW, height = this.panelH, gap = 10 * scale;
        const rows = this.menuRows;
        const rowH = (height - gap * (rows - 1)) / rows;
        const y = (i: number) => height / 2 - rowH / 2 - i * (rowH + gap);
        if (this.modal !== 'settings') this.entries().forEach((entry, i) => this.menuButton(content, entry.title, entry.action!, width, rowH, 0, y(i)));
        else {
            for (const [i, kind, label, value] of [[0, 'sfx', '音效音量', this.audio.sfxVolume], [1, 'music', '音乐音量', this.audio.musicVolume]] as const) {
                const side = 44 * scale, sideX = width / 2 + 6 * scale + side / 2;
                this.menuButton(content, '−', 'Volume:' + kind + 'Down', side, rowH, -sideX, y(i));
                this.menuButton(content, label + '  ' + Math.round(value * 100) + '%', 'Noop', width, rowH, 0, y(i));
                this.menuButton(content, '+', 'Volume:' + kind + 'Up', side, rowH, sideX, y(i));
            }
            this.menuButton(content, '测试模式：' + (this.testMode ? '开启' : '关闭'), 'TestMode', width, rowH, 0, y(2));
            this.menuButton(content, '深夜加班模式：' + (this.nightShift ? '开启' : '关闭'), 'NightShift', width, rowH, 0, y(3));
            if (this.fullscreenAvailable) this.menuButton(content, document.fullscreenElement ? '退出全屏' : '全屏', 'Fullscreen', width, rowH, 0, y(4));
            this.menuButton(content, '返回', 'SettingsBack', width, rowH, 0, y(rows - 1));
        }
    }
    private releaseMenuPress() {
        const pressed = this.menuPressed;
        if (pressed?.node.isValid) pressed.node.setScale(pressed.scale);
        if (pressed?.surface?.isValid && pressed.fill) { pressed.surface.fill = pressed.fill; pressed.surface.paint(); }
        this.menuPressed = null;
    }
    private pressMenuButton(node: Node | undefined) {
        if (!node) return;
        const surface = node.getComponent(Surface) || node.getChildByName('Plate')?.getComponent(Surface) || null;
        this.menuPressed = { node, surface, scale: node.scale.clone(), fill: surface?.fill.clone() || null };
        node.setScale(node.scale.x * .94, node.scale.y * .94, node.scale.z);
        if (surface) { const c = surface.fill; surface.fill = new Color(Math.round(c.r * .88), Math.round(c.g * .88), Math.round(c.b * .88), c.a); surface.paint(); }
    }
    private row(parent: Node, entry: Entry, width: number, height: number, y: number, compact = false) {
        const node = this.makeNode('Row', parent, width, height); node.setPosition(0, y);
        const bg = node.addComponent(Surface); bg.radius = 14; bg.fill = Color.fromHEX(new Color(), entry.muted ? '#EEEDE4' : '#EBEEDF'); bg.paint();
        if (compact) {
            const unit = this.metrics.wide ? this.metrics.width / 1920 : 1, padding = Math.max(10 * unit, 7 * this.inputScale);
            const titleFont = Math.max(22 * unit, 15 * this.inputScale), bodyFont = Math.max(18 * unit, 12 * this.inputScale), titleH = titleFont * 1.4;
            bg.radius = 8; bg.fill.a = entry.muted ? 90 : 145; bg.paint();
            this.text(node, 'Title', entry.title, width - padding * 2, titleH, 0, height / 2 - padding - titleH / 2, titleFont, entry.muted ? '777E70' : '344637');
            if (entry.text) {
                const bodyH = height - padding * 2 - titleH - 2 * this.inputScale;
                const text = this.text(node, 'Text', entry.text, width - padding * 2, bodyH, 0, -height / 2 + padding + bodyH / 2, bodyFont, entry.muted ? '777E70' : '69765D');
                text.getComponent(Label)!.verticalAlign = Label.VerticalAlign.TOP;
            }
        } else {
            this.text(node, 'Title', entry.title, width - 32, entry.text ? 38 : height - 12, 0, entry.text ? height / 2 - 28 : 0, 25, entry.muted ? '929889' : '344637');
            if (entry.text) this.text(node, 'Text', entry.text, width - 32, height - 45, 0, -20, 20, entry.muted ? '929889' : '69765D');
        }
        if (entry.action) this.controls.set('Row:' + entry.action, node);
    }
    private renderDetail(parent: Node, width: number, height: number) {
        const m = this.model, c = this.catalogId ? undefined : m.card(this.selected);
        const id = this.catalogId || c?.id, d = id ? m.data.cards[id] : undefined;
        if (!d || !id) { this.text(parent, 'Missing', '这张卡牌已被消耗。', width, 100, 0, 0); return; }
        this.label('Panel/Title').string = d.name;
        const types: Record<string, string> = { employee: '员工', tool: '工具', customer: '客户', product: '产品', resource: '资源', facility: '设施', cash: '现金', rival: '对手', business_model: '商业模式' };
        this.label('Panel/Eyebrow').string = 'STARTX  /  ' + types[d.type];
        const faceSize = Math.min(200, height * .28), imageY = height / 2 - faceSize / 2;
        const actionHeight = Math.max(82, 44 * this.inputScale), stateHeight = 64, gap = 16;
        const card = instantiate(this.cardPrefab); parent.addChild(card); card.setPosition(0, imageY); card.setScale(faceSize / 280, faceSize / 280, 1);
        const view = card.getComponent(CardView)!;
        this.loadFrame('faces/' + id).then(frame => { if (!card.isValid) return; view.configure(frame, d.bodyColor, id === 'founder' ? 'foil' : id === 'cash' || d.type === 'business_model' ? 'glass' : 'plain');
            if (c?.uses != null && c.uses >= 0) this.loadFrame('patches/' + id + '-' + c.uses).then(f => { if (view.isValid) view.setPatch(f, 'uses'); });
            else if (c?.id === 'p3_account') this.loadFrame('patches/account-' + c.stored).then(f => { if (view.isValid) view.setPatch(f, 'account'); });
        }).catch(e => { this.lastError = String(e); });
        const description = c ? m.description(c) : [d.functionText, d.flavor].filter(Boolean).join('\n\n');
        const descH = Math.min(240, height - faceSize - actionHeight - stateHeight - gap * 3);
        const descY = height / 2 - faceSize - gap - descH / 2;
        this.text(parent, 'Description', description, width - 16, descH, 0, descY, 23);
        if (c) {
            const p = m.production(c.sid), arr = m.members(c.sid);
            const state = p ? `${p.recipe.name} · 产能 ${m.stackCapacity(c.sid)}\n${p.recipe.formula}` : c.elapsed > 0 ? '生产已暂停，进度保留在这张卡上。' : arr.length > 1 ? `这组牌堆有 ${arr.length} 张卡牌。拖动露出的标题可拆开。` : '拖动卡牌与其他卡牌叠放，可发现商业模式。';
            this.text(parent, 'State', state, width - 16, stateHeight, 0, descY - descH / 2 - gap - stateHeight / 2, 20);
        }
    }
    private hit(n: Node, p: Vec2) {
        if (!n.activeInHierarchy) return false;
        const t = n.getComponent(UITransform)!, v = t.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        return v.x >= -t.width / 2 && v.x <= t.width / 2 && v.y >= -t.height / 2 && v.y <= t.height / 2;
    }
    private actionAt(p: Vec2) {
        if (this.modal === 'inspect') {
            if (this.hit(this.cardInspector.closeNode, p)) return 'InspectClose';
            const icon = this.cardInspector.iconAt(p); if (icon) return 'InspectCard:' + icon;
            return this.cardInspector.containsDetails(p) ? 'InspectDetails' : this.cardInspector.contains(p) ? 'InspectFlip' : 'InspectClose';
        }
        if (this.modal === 'catalog') return this.cardCatalog.actionAt(p);
        if (this.modal === 'none') {
            if (this.statusHelp?.active && this.hit(this.statusHelp, p)) return 'StatusHelpClose';
            const action = this.originalHud.actionAt(p); if (action) return action;
        }
        for (const [action, n] of Array.from(this.controls.entries()).reverse()) {
            if (action.startsWith('TopPack:') || action.startsWith('TaskFold:') || action.startsWith('TaskItem:') || action === 'TaskClose') continue;
            if (this.modal === 'none' && (action.startsWith('Row:') || ['Close', 'Back', 'Prev', 'Next'].includes(action))) continue;
            if (this.modal !== 'none' && ['Book', 'Tasks', 'Settings', 'ResearchPanel', 'SellZone'].includes(action)) continue;
            if (this.modal !== 'none' && action.startsWith('StatusInfo:')) continue;
            if (this.hit(n, p)) return action;
        }
        if (this.modal !== 'none') return this.hit(this.find('Panel'), p) ? 'Noop' : 'Dismiss';
        // Fixed status and information bars never pan the board.
        if (this.hit(this.find('Status'), p) || this.hit(this.find('BottomBar'), p)) return 'Noop';
        return '';
    }
    private topAt(p: Vec2, excluded: number[] = []) {
        const uid = Array.from(this.views.entries()).filter(([id, v]) => !excluded.includes(id) && v.view.node.scale.x > 0 && v.view.contains(p))
            .sort((a, b) => b[1].view.node.getSiblingIndex() - a[1].view.node.getSiblingIndex())[0]?.[0] || 0;
        return uid;
    }
    private worldPoint(p: Vec2) { return this.board.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(p.x, p.y)); }
    press(p: Vec2): 'card' | 'board' | 'ui' {
        this.releaseMenuPress();
        if (this.atTitle) this.titleScreen.pointer(p);
        this.audio.prime();
        if (this.modal === 'inspect') { this.cardInspector.begin(p); this.pressedAction = this.actionAt(p); this.pressedCard = this.pressedPack = 0; return 'ui'; }
        if (this.modal === 'catalog') this.cardCatalog.begin(p); else this.originalHud.begin(p);
        this.dragPointer.set(p);
        this.pressedAction = this.actionAt(p); this.pressedCard = 0; this.pressedPack = 0;
        if (!this.pressedAction.startsWith('StatusInfo:') && this.statusHelp?.active && !this.hit(this.statusHelp, p)) this.hideStatusInfo();
        if (this.plainMenu && this.pressedAction.startsWith('Row:') || this.pressedAction.startsWith('Title:') || this.pressedAction === 'Settings') this.pressMenuButton(this.controls.get(this.pressedAction));
        if (this.pressedAction === 'ResearchPanel') this.researchPulse = 0;
        if (this.pressedAction) return 'ui';
        const uid = this.topAt(p), c = this.model.card(uid), pack = this.model.packs.find(v => v.uid === uid);
        if (c && this.model.isCombatant(c.sid)) return 'ui';
        if (c || pack) {
            this.pressedCard = c?.uid || 0; this.pressedPack = pack?.uid || 0;
            const start = c ? this.model.position(c) : pack!, local = this.worldPoint(p);
            this.dragPoint.set(start.x, start.y); this.dragOffset.set(local.x - start.x, local.y - start.y); return 'card';
        }
        return 'board';
    }
    tap(p: Vec2, kind: string) {
        this.releaseMenuPress();
        if (kind === 'card') {
            if (this.pressedPack) { const initial = this.model.packs.find(p => p.uid === this.pressedPack)?.id === 'garage_pack' && this.model.month === 1; this.model.openPack(this.pressedPack); this.syncViews(); if (initial && !this.model.packs.length) this.fitBoard(); return; }
            if (this.linkSource) { this.model.connect(this.linkSource, this.pressedCard); this.linkSource = 0; return; }
            this.selected = this.pressedCard; this.selectedPack = 0; this.catalogId = '';
            const card = this.model.card(this.selected);
            if (card) { this.model.say(this.model.cardHint(card)); if (card.id === 'p3_account') this.model.withdraw(card); } this.saveProgress(); return;
        }
        if (kind === 'board') { this.linkSource = 0; this.selected = 0; this.originalHud.close(); this.syncMenuBackdrop(); this.model.say(DEFAULT_HINT); return; }
        const action = this.actionAt(p); if (action && action === this.pressedAction) this.perform(action.replace(/^(Row|Title):/, ''));
    }
    private perform(action: string) {
        const [verb, arg] = action.split(':'); const c = this.model.card(this.selected);
        switch (verb) {
            case 'StatusInfo': this.showStatusInfo(arg); break;
            case 'StatusHelpClose': this.hideStatusInfo(); break;
            case 'CatalogClose': this.show(this.catalogReturn); break;
            case 'CatalogSort': this.cardCatalog.setSort(arg); break;
            case 'CatalogCard': {
                const frame = this.cardCatalog.frame(arg); if (!frame || !this.model.drawn.has(arg)) break;
                const d = this.model.def(arg); this.catalogId = arg; this.inspectorReturn = 'catalog'; this.show('inspect');
                this.cardInspector.presentFrame(frame, d.bodyColor, arg === 'founder' ? 'foil' : arg === 'cash' || d.type === 'business_model' ? 'glass' : 'plain',
                    d.functionText || '与其他卡牌叠放，发现商业模式', d.flavor || ''); this.cardInspector.setReference(this.model, arg); break;
            }
            case 'Tasks': this.originalHud.toggle(); break;
            case 'TaskFold': this.originalHud.fold(arg); break;
            case 'TaskItem': { const text = this.originalHud.infoFor(arg); this.originalHud.showInfo(arg); if (text) this.model.say(text); break; }
            case 'TaskHelpClose': this.originalHud.hideInfo(); break;
            case 'TopPack': {
                if (!this.model.packUnlocked(arg)) { this.model.say(this.model.packRequirement(arg)); break; }
                this.originalHud.close();
                this.buyPackAt(arg, this.controls.get(action)!, -60); break;
            }
            case 'Open':
                if (arg === 'catalog') this.catalogReturn = this.atTitle ? 'home' : 'book';
                if (arg === 'tasks') { this.show('none'); this.originalHud.toggle(); } else this.show(arg as Modal); break;
            case 'Book': this.originalHud.toggle('recipes'); break;
            case 'Settings': this.show('book'); break;
            case 'ResearchPanel': this.show('research'); break;
            case 'SellZone': this.model.say('将卡牌拖到这里出售，员工可免费解雇'); break;
            case 'Pack': this.show('packs'); break;
            case 'Details': this.catalogId = ''; if (!this.model.card(this.selected)) this.selected = this.model.cards[0]?.uid || 0; this.show('detail'); break;
            case 'InspectClose': if (!this.cardInspector.goBack()) { this.show(this.inspectorReturn, false); this.inspectorReturn = 'none'; } break;
            case 'InspectCard': void this.cardInspector.openCard(this.model, arg); break;
            case 'InspectFlip': this.cardInspector.flip(); break;
            case 'Close': case 'Dismiss': if (this.modal === 'settings') this.show(this.settingsReturn); else if (this.modal !== 'home') this.show('none'); break;
            case 'Back': this.show(['catalog', 'recipes', 'tasks', 'research'].includes(this.modal) ? 'book' : 'none'); break;
            case 'Prev': this.page = Math.max(0, this.page - 1); this.renderPanel(); break;
            case 'Next': this.page = Math.min(this.pageCount - 1, this.page + 1); this.renderPanel(); break;
            case 'Reset': this.fitBoard(); this.show('none'); break;
            case 'Buy': {
                const source = this.controls.get('Row:' + action) || this.controls.get('TopPack:' + arg)!;
                if (this.buyPackAt(arg, source, -40)) this.show('none'); else this.renderPanel(); break;
            }
            case 'Card': this.catalogId = arg; this.show('detail'); break;
            case 'Research': this.model.research(arg); this.renderPanel(); break;
            case 'Sell': if (c) this.model.sell(c.sid); this.show('none'); break;
            case 'Withdraw': if (c) this.model.withdraw(c); this.show('none'); break;
            case 'Link': if (c) this.linkSource = c.uid; this.show('none'); break;
            case 'Unlink': if (c) this.model.disconnect(c.uid); this.show('none'); break;
            case 'Unpack': this.model.openPack(this.selectedPack); this.show('none'); break;
            case 'Pause': this.model.paused = !this.model.paused; this.show('none'); break;
            case 'Continue': this.hasStarted = true; this.atTitle = false; this.show('none'); break;
            case 'MenuRecipes': this.show('none'); this.originalHud.toggle('recipes'); break;
            case 'OpenSettings': this.settingsReturn = this.atTitle ? 'home' : 'book'; this.show('settings'); break;
            case 'SettingsBack': this.show(this.settingsReturn); break;
            case 'NightShift':
                this.nightShift = !this.nightShift;
                try { sys.localStorage.setItem('startx.night-shift', String(this.nightShift)); } catch { /* The current session still applies. */ }
                this.renderPanel(); break;
            case 'Volume': this.audio.adjustVolume(arg.startsWith('sfx') ? 'sfx' : 'music', arg.endsWith('Up') ? .1 : -.1); this.renderPanel(); break;
            case 'TestMode':
                this.testMode = !this.testMode; this.model.testMode = this.testMode;
                try { sys.localStorage.setItem('startx.test-mode', String(this.testMode)); } catch { /* The current session still applies. */ }
                this.model.say(this.testMode ? '测试模式已开启：全部卡包解锁，新开局获得余额 50 的账户' : '测试模式已关闭：新开局恢复原版现金与卡包规则');
                this.renderPanel(); break;
            case 'Fullscreen': {
                const task = document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen();
                void task.then(() => this.layoutPanel()).catch(() => this.model.say('请使用浏览器的全屏按钮')); break;
            }
            case 'Home': this.atTitle = true; this.show('home'); break;
            case 'Restart':
                this.hasStarted = true;
                for (const view of this.board.node.getComponentsInChildren(CardView)) view.node.destroy();
                this.views.clear(); this.cashFlights.clear(); this.battleView.reset();
                this.atTitle = false; this.model = new GameModel(this.model.data, Math.random, this.testMode); this.originalHud.reset(this.model); this.selected = this.model.cards[0].uid; this.board.reset(); this.show('none'); this.frameOpening(); break;
        }
        this.syncViews();
        this.syncMenuBackdrop(verb === 'NightShift');
        this.saveProgress();
    }
    hold(_p: Vec2) {
        const source = this.views.get(this.pressedCard || this.pressedPack)?.view; if (!source) return;
        this.inspectorReturn = 'none';
        this.selected = this.pressedCard; this.selectedPack = this.pressedPack; this.catalogId = '';
        this.show('inspect');
        const card = this.model.card(this.selected);
        if (card) {
            const d = this.model.def(card), dynamic = card.uses >= 0 || card.id === 'p3_account';
            const functionText = dynamic ? this.model.description(card).split('\n\n')[0] : d.functionText || (d.type === 'cash' ? '用于购买卡包、支付工资' : '与其他卡牌叠放，发现商业模式');
            this.cardInspector.present(source, d.bodyColor, card.id === 'founder' ? 'foil' : card.id === 'cash' || d.type === 'business_model' ? 'glass' : 'plain', functionText, d.flavor || '');
            this.cardInspector.setReference(this.model, card.id);
        } else {
            const pack = this.model.packs.find(p => p.uid === this.selectedPack); if (!pack) { this.show('none'); return; }
            const d = this.model.data.packs[pack.id];
            this.cardInspector.present(source, '141414', 'pack', `卡包 · ${d.minCards}–${d.maxCards} 张卡牌`, '单击卡包，逐张取出卡牌。');
        }
    }
    holdMove(_p: Vec2, delta: Vec2) { if (this.modal === 'inspect') this.cardInspector.drag(delta); }
    context(p: Vec2) { if (!this.canZoom(p)) return; if (this.press(p) === 'card') this.hold(p); }
    private movingIds() {
        if (this.pressedPack) return [this.pressedPack];
        const c = this.model.card(this.pressedCard); if (!c) return [];
        const s = this.model.stack(c.sid)!; return s.cards.slice(s.cards.indexOf(c.uid));
    }
    private buyPackAt(id: string, source: Node, screenY: number) {
        const transform = source.getComponent(UITransform)!, world = transform.convertToWorldSpaceAR(new Vec3());
        const edge = transform.convertToWorldSpaceAR(new Vec3(Math.min(transform.width, transform.height) / 2, 0));
        const from = this.worldPoint(new Vec2(world.x, world.y)), side = this.worldPoint(new Vec2(edge.x, edge.y));
        const screen = this.viewport.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(0, screenY));
        const center = this.worldPoint(new Vec2(screen.x, screen.y)), previous = this.model.packs.length;
        this.model.buyPack(id, center.x, center.y, { x: from.x, y: from.y, startScale: Math.hypot(side.x - from.x, side.y - from.y) * 2 / 336 });
        return this.model.packs.length > previous;
    }
    private canSellDragged() {
        if (this.pressedPack) return false;
        return this.model.canSellCards(this.movingIds().map(uid => this.model.card(uid)).filter((c): c is CardState => !!c));
    }
    private clearDropHint() { this.matchTarget = 0; this.matchArt.node.active = false; this.matchArt.clear(); }
    private updateDropHint(dt: number) {
        let target = 0;
        if (this.dragging && this.pressedCard && this.modal === 'none' && !this.hit(this.find('SellZone'), this.dragPointer)) {
            const center = this.board.node.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(this.dragPoint.x, this.dragPoint.y));
            const candidate = this.topAt(new Vec2(center.x, center.y), this.movingIds());
            const source = this.model.card(this.pressedCard)!, card = this.model.card(candidate);
            const sameCards = card && this.movingIds().concat(this.model.stack(card.sid)!.cards).every(uid => this.model.card(uid)?.id === source.id);
            if (!sameCards && this.model.canInteract(this.pressedCard, candidate)) target = candidate;
        }
        if (!target) { if (this.matchTarget) this.clearDropHint(); return; }
        const moving = new Set(this.movingIds()), members = this.model.members(this.model.card(target)!.sid).filter(c => !moving.has(c.uid));
        const base = members[0], stackHeight = this.model.stackHeight(base.sid);
        if (base.uid !== this.matchTarget) this.matchClock = 0;
        this.matchTarget = base.uid; this.matchClock += dt; this.matchArt.node.active = true;
        const position = this.model.position(base); this.matchArt.node.setPosition(position.x, position.y - stackHeight / 2);
        this.matchArt.node.setSiblingIndex(999999);
        this.movingIds().forEach(uid => this.views.get(uid)?.view.node.setSiblingIndex(999999));
        this.views.get(base.uid)!.view.drawDropHint(this.matchArt, this.matchClock, stackHeight);
    }
    private updateCornerFeedback(dt: number) {
        this.sellReady = this.dragging && this.modal === 'none' && this.canSellDragged() && this.hit(this.find('SellZone'), this.dragPointer);
        this.find('SellZone/Feedback').active = this.sellReady;
        this.researchPulse = Math.min(1, this.researchPulse + dt);
        const pulse = this.researchPulse < .24 ? Math.sin(this.researchPulse / .24 * Math.PI) : 0;
        this.find('Research/Feedback').active = this.modal === 'research' || pulse > 0;
        this.find('Research/Icon').setScale(this.cornerIconScale * (1 - .1 * pulse), this.cornerIconScale * (1 - .1 * pulse), 1);
    }
    dragStart() {
        const c = this.model.card(this.pressedCard); if (c && this.model.isCombatant(c.sid)) return;
        this.dragging = true; this.model.heldStack = c?.sid || -1;
        this.movingIds().forEach(uid => this.views.get(uid)?.view.setHeld(true));
        if (c) this.audio.play('grab');
    }
    drag(p: Vec2, delta: Vec2) {
        if (!this.dragging) return;
        this.dragPointer.set(p);
        const local = this.worldPoint(p); this.dragPoint.set(local.x - this.dragOffset.x, local.y - this.dragOffset.y);
        const bounded = this.model.constrainPoint(this.dragPoint.x, this.dragPoint.y, this.movingIds().length, !!this.pressedPack, true);
        this.dragPoint.set(bounded.x, bounded.y);
        this.movingIds().forEach((uid, i) => { const v = this.views.get(uid)?.view; if (v) { v.node.setPosition(this.dragPoint.x, this.dragPoint.y - i * (this.model.card(uid) ? this.model.stackOffset(this.model.card(uid)!.sid) : CARD_OFFSET)); v.setDragDelta(delta.x / this.inputScale); v.node.setSiblingIndex(99999); } });
    }
    dragEnd(cancelled: boolean) {
        if (!this.dragging) return;
        const ids = this.movingIds(); ids.forEach(uid => this.views.get(uid)?.view.setHeld(false));
        const bottom = this.model.card(ids[0]); if (bottom) this.audio.play(this.model.dropSound(bottom.id));
        if (!cancelled) {
            if (this.pressedPack) { const p = this.model.packs.find(v => v.uid === this.pressedPack); if (p) Object.assign(p, this.model.constrainPoint(this.dragPoint.x, this.dragPoint.y, 1, true)); }
            else {
                const center = this.board.node.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(this.dragPoint.x, this.dragPoint.y));
                const target = this.topAt(new Vec2(center.x, center.y), ids);
                if (this.hit(this.find('SellZone'), this.dragPointer)) {
                    if (this.canSellDragged()) {
                        this.model.move(this.pressedCard, this.dragPoint.x, this.dragPoint.y);
                        const dropped = this.model.card(this.pressedCard);
                        if (dropped) {
                            const icon = this.find('SellZone').getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3());
                            this.model.sell(dropped.sid, this.worldPoint(new Vec2(icon.x, icon.y)));
                        }
                    } else this.model.say('这组卡牌当前无法出售');
                } else this.model.move(this.pressedCard, this.dragPoint.x, this.dragPoint.y, target);
                this.selected = this.pressedCard; this.catalogId = '';
            }
        }
        this.dragging = false; this.sellReady = false; this.find('SellZone/Feedback').active = false;
        this.clearDropHint();
        this.model.heldStack = -1; this.syncViews();
        this.saveProgress();
    }
    pan(delta: Vec2) { if (this.modal === 'none' && !this.model.battle && !this.battleView.restoring) this.board.pan(delta); }
    uiDrag(delta: Vec2) { this.releaseMenuPress(); if (this.modal === 'inspect' && (this.pressedAction === 'InspectDetails' || this.pressedAction.startsWith('InspectCard:'))) this.cardInspector.dragDetails(delta); else if (this.modal === 'inspect' && this.pressedAction === 'InspectFlip') this.cardInspector.drag(delta); else if (this.modal === 'catalog') this.cardCatalog.drag(delta); else if (this.modal === 'none') this.originalHud.drag(delta); }
    uiDragThreshold() { return (this.modal === 'inspect' ? 2 : this.originalHud.isPackGesture ? 3 : 8) * this.inputScale; }
    uiEnd(cancelled: boolean) { this.releaseMenuPress(); if (this.modal === 'catalog') this.cardCatalog.end(); else if (this.modal === 'inspect') this.cardInspector.end(); else this.originalHud.end(cancelled); }
    hover(p: Vec2) { if (this.atTitle) this.titleScreen.pointer(p); else if (this.modal === 'none') this.originalHud.hover(p); }
    uiScroll(p: Vec2, delta: number, horizontal = 0) { return this.modal === 'inspect' ? this.cardInspector.wheel(p, delta) : this.modal === 'catalog' ? this.cardCatalog.wheel(p, delta) : this.modal === 'none' && this.originalHud.wheel(p, delta, horizontal); }
    zoom(factor: number, p: Vec2) { if (this.model.battle || this.battleView.restoring) return; const local = this.viewport.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(p.x, p.y)); this.board.setZoom(this.board.zoom * factor, new Vec2(local.x, local.y)); }
    canZoom(p: Vec2) { return this.ready && this.modal === 'none' && !this.model.battle && !this.battleView.restoring && !this.actionAt(p) && this.hit(this.viewport, p); }
    private frameOpening() {
        const founder = this.model.cards[0], stack = this.model.stack(founder.sid)!; stack.x = 0; stack.y = 0;
        for (const funds of this.model.stacks.filter(s => this.model.members(s.sid).every(c => c.id === 'cash' || c.id === 'p3_account'))) { funds.x = 340; funds.y = -340; }
        this.model.packs[0].x = 460; this.model.packs[0].y = 0;
        if (this.metrics.wide) { this.board.reset(); this.board.setZoom(this.metrics.width / 1920 * .82); } else this.fitBoard();
    }
    private fitBoard() {
        const points = this.model.cards.filter(c => c.id !== 'cash').map(c => this.model.position(c)).concat(this.model.packs.map(p => ({ x: p.x, y: p.y })));
        if (!points.length) { this.board.reset(); return; }
        const { width, height, top, bottom, wide } = this.metrics;
        const minX = Math.min(...points.map(p => p.x)) - 180, maxX = Math.max(...points.map(p => p.x)) + 180;
        const minY = Math.min(...points.map(p => p.y)) - 180, maxY = Math.max(...points.map(p => p.y)) + 180;
        const bar = this.find('BottomBar');
        const usableTop = this.boardTop, usableBottom = bar.position.y + bar.getComponent(UITransform)!.height / 2 + 52;
        const usableLeft = -width / 2 + this.find('Toolbar/Book').getComponent(UITransform)!.width + 32, usableRight = width / 2 - 64;
        const zoom = Math.min(1, (usableRight - usableLeft) / (maxX - minX), (usableTop - usableBottom) / (maxY - minY));
        this.board.reset(); this.board.setZoom(zoom);
        this.board.pan(new Vec2((usableLeft + usableRight) / 2 - (minX + maxX) / 2 * this.board.zoom, (usableTop + usableBottom) / 2 - (minY + maxY) / 2 * this.board.zoom));
    }
    private drawLinks() {
        const g = this.lineArt; g.clear(); g.lineWidth = 4; g.strokeColor = new Color(93, 124, 76, 180); g.fillColor = g.strokeColor;
        for (const l of this.model.links) {
            const a = this.model.card(l.source), b = this.model.card(l.target); if (!a || !b || a.sid === b.sid) continue;
            const p = this.model.position(a), q = this.model.position(b), dx = q.x - p.x, dy = q.y - p.y, length = Math.hypot(dx, dy) || 1;
            const tx = q.x - dx / length * 150, ty = q.y - dy / length * 150;
            g.moveTo(p.x, p.y); g.lineTo(tx, ty); g.stroke();
            g.moveTo(tx, ty); g.lineTo(tx - dx / length * 18 - dy / length * 8, ty - dy / length * 18 + dx / length * 8);
            g.lineTo(tx - dx / length * 18 + dy / length * 8, ty - dy / length * 18 - dx / length * 8); g.close(); g.fill();
        }
    }
    private snapshot() {
        const bounds = (n: Node) => {
            const t = n.getComponent(UITransform)!, s = this.metrics.scale;
            const corners = [[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y]) => t.convertToWorldSpaceAR(new Vec3((x - .5) * t.width, (y - .5) * t.height)));
            const minX = Math.min(...corners.map(p => p.x)), maxX = Math.max(...corners.map(p => p.x)), minY = Math.min(...corners.map(p => p.y)), maxY = Math.max(...corners.map(p => p.y));
            return { x: minX / s, y: (this.metrics.height - maxY) / s, width: (maxX - minX) / s, height: (maxY - minY) / s };
        };
        const m = this.model, founder = m.cards.find(c => c.id === 'founder'), founderView = founder && this.views.get(founder.uid)?.view;
        const basis = (node: Node) => {
            const t = node.getComponent(UITransform)!, o = t.convertToWorldSpaceAR(new Vec3()), x = t.convertToWorldSpaceAR(new Vec3(168, 0)), y = t.convertToWorldSpaceAR(new Vec3(0, 168));
            return { x: { x: x.x - o.x, y: x.y - o.y }, y: { x: y.x - o.x, y: y.y - o.y } };
        };
        return { ready: this.ready && this.pending === 0 && this.originalHud.pending === 0 && this.cardCatalog.pending === 0 && this.cardInspector.pending === 0 && !this.menuBackdrop.snapshot().capturing, error: this.lastError, modal: this.modal, zoom: this.board.zoom, wide: this.metrics.wide, nearSquare: this.metrics.nearSquare, nightShift: this.nightShift,
            page: this.page, pageCount: this.pageCount, card: founderView ? bounds(founderView.node) : null, position: founder ? m.position(founder) : null,
            cards: m.cards.map(c => ({ ...c, name: m.def(c).name, position: m.position(c), bounds: this.views.has(c.uid) ? bounds(this.views.get(c.uid)!.view.node) : null,
                faceBounds: this.views.has(c.uid) ? bounds(this.views.get(c.uid)!.view.frontNode) : null })),
            packs: m.packs.map(p => ({ ...p, bounds: this.views.has(p.uid) ? bounds(this.views.get(p.uid)!.view.node) : null,
                faceBounds: this.views.has(p.uid) ? bounds(this.views.get(p.uid)!.view.frontNode) : null })),
            battle: m.battle ? { ...m.battle, rect: m.battleRect } : null, battlePresentation: this.battleView.snapshot(),
            cash: m.cash, month: m.month, testMode: m.testMode, titleScreen: this.titleScreen.snapshot(), inspector: { ...this.cardInspector.snapshot(), bounds: bounds(this.cardInspector.cardNode), close: bounds(this.cardInspector.closeNode), detailsBounds: bounds(this.cardInspector.detailsNode) }, models: Array.from(m.models), tasks: Array.from(m.completed), rp: m.rp, notice: m.notice, links: m.links,
            hint: this.label('Hint').string, taskReminder: this.label('TaskReminder').string, taskDrawer: this.originalHud.open, drawerMode: this.originalHud.mode, pitch: this.board.pitch,
            drawer: bounds(this.find('TaskDrawer')), drawerProgress: this.originalHud.reveal,
            helpText: this.originalHud.helpText, help: this.originalHud.helpText ? bounds(this.find('TaskDrawer/Help')) : null,
            motions: Array.from(this.views.entries()).map(([uid, v]) => ({ uid, ...v.view.motionSnapshot() })),
            cashFlights: Array.from(this.cashFlights.entries()).map(([view, motion]) => ({ ...motion, ...view.motionSnapshot(), bounds: bounds(view.frontNode), layer: view.node.getSiblingIndex(), targetLayer: this.views.get(motion.targetUid)?.view.node.getSiblingIndex(), opacity: view.node.getComponent(UIOpacity)!.opacity })),
            audio: this.audio.snapshot(),
            catalog: this.cardCatalog.snapshot(),
            menuBackdrop: this.menuBackdrop.snapshot(),
            statusHelp: { key: this.statusHelpKey, active: !!this.statusHelp?.activeInHierarchy, bounds: this.statusHelp ? bounds(this.statusHelp) : null,
                text: this.statusHelp?.activeInHierarchy ? this.statusHelp.getComponentsInChildren(Label).map(l => l.string).join('\n') : '' },
            workbars: Array.from(this.views.entries()).filter(([, v]) => v.view.progressNode.activeInHierarchy).map(([uid, v]) => ({
                anchor: uid, sid: m.card(uid)?.sid, bounds: bounds(v.view.progressNode), card: bounds(v.view.frontNode) })),
            hudLayout: {
                monthTrack: bounds(this.find('Status/ProgressSlot')),
                status: bounds(this.find('Status')), footer: bounds(this.find('BottomBar')),
                taskReminder: { bounds: bounds(this.find('TaskReminder')), font: this.label('TaskReminder').fontSize / this.inputScale,
                    opacity: this.find('TaskReminder').getComponent(UIOpacity)!.opacity, active: this.find('TaskReminder').activeInHierarchy },
                footerText: ['Hint'].map(name => ({ name, bounds: bounds(this.find(name)), verticalAlign: this.label(name).verticalAlign,
                    lineHeight: this.label(name).lineHeight / this.metrics.scale })),
                stats: ['Stage', 'Month', 'Supply', 'Space', 'Cash', 'Settings'].map(name => ({ name, bounds: bounds(this.find('Status/' + name)),
                    icon: bounds(this.find('Status/' + name + '/Icon')),
                    text: name === 'Settings' ? null : bounds(this.find('Status/' + name + '/Value')) })),
                tabs: ['Book', 'Tasks'].map(name => ({ name, bounds: bounds(this.find('Toolbar/' + name)), order: this.find('Toolbar/' + name).getSiblingIndex(),
                    font: this.label('Toolbar/' + name + '/Text').fontSize / this.metrics.scale })),
                packPrices: m.data.packOrder.map(id => {
                    const cover = this.find('PackStrip/Covers/Pack-' + id + '/Cover'), label = cover.getChildByPath('Price/Text')!.getComponent(Label)!;
                    return { id, price: label.string, cover: bounds(cover), label: bounds(label.node),
                        hasBackground: !!cover.getChildByName('Price')!.getComponent(Surface) };
                })
            },
            departures: this.board.node.getComponentsInChildren(CardView).map(v => v.motionSnapshot()).filter(m => m.kind === 'dissolve'),
            gridPlane: basis(this.board.node.getChildByName('Table')!), cardPlane: founderView ? basis(founderView.node) : null,
            taskText: this.find('TaskDrawer').getComponentsInChildren(Label).filter(l => l.node.activeInHierarchy).map(l => l.string), taskOffset: this.originalHud.taskOffset, packOffset: this.originalHud.packOffset,
            pan: { x: this.board.node.position.x, y: this.board.node.position.y },
            boardBackground: { ...this.board.snapshot(), cityBounds: bounds(this.board.node.getChildByName('CitySurroundings')!),
                boardBounds: bounds(this.board.node.getChildByName('Table')!), tintBounds: bounds(this.board.node.getChildByPath('CitySurroundings/BackgroundTint')!) }, viewport: bounds(this.viewport),
            panelText: this.modal === 'none' ? [] : this.find('Panel').getComponentsInChildren(Label).map(l => l.string),
            controls: this.originalHud.visibleControls().filter(([, n]) => n.isValid && n.activeInHierarchy).reduce((out, [a, n]) => {
                const box = bounds(n); if (a === 'Book' || a === 'Tasks') box.width = Math.max(box.width, 44);
                out[a] = box; return out;
            }, {} as Record<string, ReturnType<typeof bounds>>) };
    }
    onDestroy() {
        this.flushProgress(); game.off(Game.EVENT_HIDE, this.flushProgress, this);
        if (typeof window !== 'undefined') { window.removeEventListener('pagehide', this.flushProgress); window.removeEventListener('beforeunload', this.flushProgress); }
        if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', this.visibilityChanged);
        this.menuBackdrop?.destroy();
        this.cardCatalog?.destroy();
        this.cardInspector?.destroy();
        screen.off('window-resize', this.layout, this); if (typeof document !== 'undefined') document.removeEventListener('contextmenu', this.preventContext);
        if (typeof globalThis !== 'undefined') delete (globalThis as unknown as { __STARTX_SAMPLE__?: () => unknown }).__STARTX_SAMPLE__;
    }
}
