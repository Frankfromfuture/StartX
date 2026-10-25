import { _decorator, assetManager, AssetManager, Canvas, Component, EffectAsset, instantiate, JsonAsset, Label, Mask, Node, Prefab, screen, UITransform, UIOpacity, Vec2, Vec3, Color, Sprite, SpriteFrame, Font, Graphics, sys, game, Game } from 'cc';
import { CardView, cardStyle } from './CardView';
import { BoardView } from './BoardView';
import { InputRouter, InputTarget } from './InputRouter';
import { Icon } from './Icon';
import { PauseWash } from './PauseWash';
import { ConnectorRoute, ConnectorRect, shortestSupplyRoute, roundSupplyRoute, supplyPathLength, supplyPathAt,
    SUPPLY_LINE_WIDTH, SUPPLY_ARROW_LENGTH, SUPPLY_ARROW_HALF_WIDTH, SUPPLY_CORNER_RADIUS } from './SupplyConnector';
import { canSetDisplayOrientation, fixedUiUnit, getDisplayOrientation, HINT_SCREEN_SIZE, LayoutMetrics, measureLayout, setDisplayOrientation } from './Layout';
import { Surface } from './Surface';
import { GameModel, Catalog, CardState, CashSpend, CARD_OFFSET, DEFAULT_HINT, quoteFlavor } from './GameModel';
import { OriginalHud } from './OriginalHud';
import { OriginalAudio } from './OriginalAudio';
import { BattleView } from './BattleView';
import { TitleScreen } from './TitleScreen';
import { CardInspector } from './CardInspector';
import { CardCatalog } from './CardCatalog';
import { MenuBackdrop } from './MenuBackdrop';
import { FounderSpeech } from './FounderSpeech';
import { PROGRESS_KEY, readProgress, SavedGame, SavedView } from './ProgressSave';
const { ccclass } = _decorator;
const MENU_SCALE = .8;
type Modal = 'none' | 'detail' | 'inspect' | 'packs' | 'book' | 'catalog' | 'recipes' | 'tasks' | 'settings' | 'home';
interface Entry { title: string; text?: string; action?: string; muted?: boolean; }
interface ViewState { view: CardView; patch: string; packCount?: number; badges?: string; }

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
    private hintCardUid = 0;
    private hintNoticeVersion = -1;
    private hintCenterY = 0;
    private hintHeight = 0;
    private pauseIconKind = '';
    private pauseWash!: PauseWash;
    private layoutReady = false;
    private selectedPack = 0;
    private catalogId = '';
    private supplyStep: 'none' | 'subject' | 'target' = 'none';
    private supplyAnchor = 0;
    private supplyCandidate = 0;
    private supplyDirection: 'upstream' | 'downstream' | null = null;
    private supplyMessage = '';
    private supplyClock = 0;
    private supplyFrames = new Map<number, Graphics>();
    private supplyTransit: { source: number; target: number; id: string; progress: number; x: number; y: number }[] = [];
    private linkBirths = new Map<string, number>();
    private supplyRoutes: ConnectorRoute[] = [];
    private pressedAction = '';
    private pressedCard = 0;
    private pressedPack = 0;
    private heldBadge = 0;
    private heldBadgeSprite: Sprite | null = null;
    private heldBadgePoint = new Vec2();
    private dragging = false;
    private dragOffset = new Vec2();
    private dragPoint = new Vec2();
    private dragPointer = new Vec2();
    private sellReady = false;
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
    private founderSpeech!: FounderSpeech;
    private spokenMilestones = new Set<string>();
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
        if (typeof window !== 'undefined') { window.addEventListener('pagehide', this.flushProgress); window.addEventListener('beforeunload', this.flushProgress); window.addEventListener('resize', this.layoutWindow); }
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
            this.board.enablePlayerPerspective(this.node.getComponent(Canvas)!);
            this.board.setSurroundings(await this.loadFrame('board/city-surroundings-v2'));
            const lines = this.makeNode('SupplyLines', boardNode, 1, 1); this.lineArt = lines.addComponent(Graphics);
            const match = this.makeNode('InteractionHint', boardNode, 312, 312); this.matchArt = match.addComponent(Graphics); match.active = false;
            this.pauseWash = new PauseWash(this.viewport);
            this.hud = instantiate(hud); this.node.addChild(this.hud); this.font = this.label('Status/Stage/Value').font!;
            this.battleView = new BattleView(this.board, this.font, damageFont, this.loadFrame('ui/battle-bubble-comic'));
            this.controls.set('Book', this.find('Toolbar/Book'));
            for (const a of ['Close', 'Back', 'Prev', 'Next']) this.controls.set(a, this.find('Panel/' + a));
            this.controls.set('Settings', this.find('Status/Settings')); this.controls.set('SupplyChain', this.find('SupplyChain')); this.controls.set('SellZone', this.find('SellZone'));
            const pause = this.makeNode('PauseControl', this.hud, 64, 64); this.controls.set('Pause', pause);
            const pauseIcon = this.makeNode('Icon', pause, 64, 64); pauseIcon.addComponent(Icon).kind = 'Pause';
            const attributes = this.text(this.hud, 'HintAttributes', '', 640, 40, 0, 0, 26, 'F7F7F3').getComponent(Label)!;
            attributes.horizontalAlign = Label.HorizontalAlign.CENTER; attributes.enableWrapText = false;
            for (const name of ['Stage', 'Month', 'Supply', 'Space', 'Cash']) this.controls.set('StatusInfo:' + name, this.find('Status/' + name));
            this.originalHud = new OriginalHud(this.hud, this.model, this.font, this.controls, path => this.loadFrame(path));
            this.founderSpeech = new FounderSpeech(this.hud, this.font, point => this.board.projectWorld(point));
            this.spokenMilestones = new Set(this.model.completed);
            const titleNames = ['city', 'logo'];
            const titleFrames: Record<string, SpriteFrame> = {};
            await Promise.all(titleNames.map(async name => { titleFrames[name] = await this.loadFrame('title/' + (name === 'city' ? 'office-window' : name)); }));
            const settingsIcon = this.find('Status/Settings/Icon');
            const settingsLogo = settingsIcon.getComponent(Sprite)!; settingsLogo.sizeMode = Sprite.SizeMode.CUSTOM;
            settingsLogo.spriteFrame = titleFrames.logo; settingsLogo.trim = true;
            this.titleScreen = new TitleScreen(this.node, this.font, titleFrames, this.controls);
            this.titleScreen.node.setSiblingIndex(this.hud.getSiblingIndex());
            const [backFrame, packBackFrame, lineEffect] = await Promise.all([this.loadFrame('ui/card-back'), this.loadFrame('ui/pack-back'),
                new Promise<EffectAsset>((resolve, reject) => content.load('ui/WhiteLine', EffectAsset, (e, f) => e ? reject(e) : resolve(f)))]);
            this.cardCatalog = new CardCatalog(this.node, this.font, backFrame, path => this.loadFrame(path), e => { this.lastError = String(e); console.error('[StartX] Catalog', e); });
            this.menuBackdrop = new MenuBackdrop(this.hud, ['Panel', 'Scrim', 'Toolbar', 'TaskDrawer'].map(name => this.find(name)));
            this.cardInspector = new CardInspector(this.node, this.font, this.cardPrefab, backFrame, packBackFrame, lineEffect, path => this.loadFrame(path));
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
            view.configure(frame, d?.bodyColor || '141414', pack ? 'pack' : cardStyle(id, d?.type));
            if (d?.type === 'badge') view.setBadgeToken(true);
            node.setScale(1, 1, 1);
            const appearance = this.model.appearances.get(uid); this.model.appearances.delete(uid);
            if (appearance) {
                view.appear(appearance, () => { if (appearance.landSound && this.model.card(uid)) this.audio.play(appearance.landSound); });
            }
        } catch (e) { this.lastError = String(e); console.error('[StartX] Card asset', id, e); this.model.say('卡面加载失败，请刷新重试', 'hint'); }
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
            v.view.node.active = uid !== this.heldBadge;
            const position = this.model.position(c);
            v.view.setCombat(this.model.battlePose(uid));
            v.view.setBattle(this.model.isCombatant(c.sid));
            if (!(this.dragging && this.movingIds().includes(uid))) { v.view.node.setPosition(position.x, position.y); v.view.node.setSiblingIndex(z++); }
            if (c.uses >= 0) this.patch(v, c.id + '-' + c.uses, 'uses');
            else if (c.id === 'p3_account') this.patch(v, 'account-' + c.stored, 'account');
            const work = workbars.get(uid); v.view.setProgress(work?.ratio || 0, work?.active || false);
            v.view.setStatus(this.model.cardStatus(c), c.deadline !== undefined && c.deadline <= 30, this.font);
            const positions = this.model.badgePositionsFor(c), badges = JSON.stringify([c.badges || [], positions]);
            if (v.badges !== badges) {
                v.badges = badges;
                Promise.all((c.badges || []).map(id => this.loadFrame('faces/' + id))).then(frames => {
                    if (v.view.isValid && v.badges === badges) v.view.setYarnBadges(frames, c.badges?.length || 0, this.model.employeeCapacity(c), this.font, positions);
                }).catch(e => { this.lastError = String(e); console.error('[StartX] Yarn badges', e); });
            }
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
        this.supplyClock += dt;
        if (this.supplyStep !== 'none' && this.supplyAnchor && !this.model.card(this.supplyAnchor)) this.cancelSupply();
        this.titleScreen.tick(dt);
        this.cardInspector.tick(dt);
        this.model.update(Math.min(dt, .1)); this.syncViews();
        this.updatePausePresentation();
        const bottomBar = this.find('BottomBar');
        this.battleView.update(this.model, this.model.paused ? 0 : Math.min(dt, .1), this.board.planeArea({
            left: -this.metrics.width / 2 + 40, right: this.metrics.width / 2 - 24, top: this.boardTop - 24,
            bottom: bottomBar.position.y + bottomBar.getComponent(UITransform)!.height / 2 + 80,
        }));
        this.updateCornerFeedback(dt);
        this.updateDropHint(dt);
        this.originalHud.tick(dt, this.modal === 'none' && !this.atTitle);
        let milestone = false;
        for (const id of this.model.completed) if (!this.spokenMilestones.has(id)) { this.spokenMilestones.add(id); milestone = true; }
        if (this.model.operationNotice) {
            const message = this.model.operationNotice; this.model.operationNotice = '';
            if (!this.atTitle) this.founderSpeech.speak(message);
        }
        if (milestone && !this.atTitle) this.founderSpeech.celebrate();
        const founder = this.model.cards.find(c => c.id === 'founder');
        this.founderSpeech.tick(dt, founder ? this.views.get(founder.uid)?.view.frontNode : undefined,
            this.modal === 'none' && !this.atTitle && !this.originalHud.open, {
                left: -this.metrics.width / 2 + 12 * this.metrics.scale, right: this.metrics.width / 2 - 12 * this.metrics.scale,
                top: this.metrics.width > this.metrics.height ? this.find('Status').position.y - this.find('Status').getComponent(UITransform)!.height / 2 - 4 * this.metrics.scale : this.boardTop - 56 * this.metrics.scale,
                bottom: bottomBar.position.y + bottomBar.getComponent(UITransform)!.height / 2 + 12 * this.metrics.scale,
                scale: this.metrics.scale, landscape: this.metrics.width > this.metrics.height,
                fontSize: HINT_SCREEN_SIZE * this.metrics.scale,
            });
        this.saveAge += dt; if (this.saveAge >= .75) { this.saveAge = 0; this.saveProgress(); }
        this.label('Status/Cash/Value').string = this.model.payroll + '/' + this.model.cash;
        this.label('Status/Month/Value').string = '第' + this.model.month + '月';
        this.label('Status/Stage/Value').string = `阶段「${this.model.paused ? '已暂停' : this.model.stageName}」`;
        this.label('Status/Supply/Value').string = String(this.model.links.length);
        this.label('Status/Space/Value').string = this.model.count + '/' + this.model.capacity;
        this.label('Status/Space/Value').color = this.model.count > this.model.capacity ? new Color(255, 176, 170) : new Color(247, 247, 247);
        this.layoutStatus();
        const progress = this.find('Status/Progress'), slot = this.find('Status/ProgressSlot'), width = slot.getComponent(UITransform)!.width;
        const ratio = Math.max(0, this.model.monthTime / (this.model.data.balance.month_seconds || 180));
        progress.getComponent(UITransform)!.setContentSize(Math.max(1, width * ratio), slot.getComponent(UITransform)!.height);
        progress.setPosition(slot.position.x - width * (1 - ratio) / 2, slot.position.y);
        this.find('Hint').active = !this.atTitle;
        if (this.atTitle) this.find('TaskReminder').active = false;
        this.updateHint();
    }
    private get gameplayPaused() { return this.plainMenu || ['inspect', 'catalog'].includes(this.modal) ? this.menuPauseBefore : this.model.paused; }
    private updatePausePresentation() {
        const paused = this.gameplayPaused, kind = paused ? 'Resume' : 'Pause';
        if (kind !== this.pauseIconKind) {
            this.pauseIconKind = kind; const icon = this.find('PauseControl/Icon').getComponent(Icon)!; icon.kind = kind; icon.paint();
        }
        this.audio.setPaused(paused && !this.atTitle);
        const packs = this.model.packs.map(p => this.views.get(p.uid)?.view).filter((v): v is CardView => !!v?.isValid && v.node.activeInHierarchy);
        this.pauseWash.update(paused && !this.atTitle, packs);
    }
    private updateHint() {
        const battle = this.model.battle, hint = this.label('Hint'), attributes = this.label('HintAttributes');
        const card = !battle && this.supplyStep === 'none' && this.hintNoticeVersion === this.model.noticeVersion ? this.model.card(this.hintCardUid) : undefined;
        const properties = card ? this.model.cardHint(card).replace(/^「|」$/g, '') : '';
        attributes.string = card && properties !== this.model.def(card).name ? properties : '';
        const landscape = this.metrics.width > this.metrics.height;
        const notice = this.model.noticeKind === 'operation' && !this.model.gameOver ? DEFAULT_HINT : this.model.notice;
        attributes.node.active = !this.atTitle && !landscape && !!attributes.string;
        hint.string = card ? quoteFlavor(this.model.def(card).flavor) : battle ? `商战  对手资金 ${Math.max(0, battle.enemyHp).toFixed(1)} · 我方资金 ${Math.max(0, battle.playerHp).toFixed(1)}` :
            notice.startsWith('「') ? notice : `「${notice}」`;
        if (landscape && attributes.string) hint.string = attributes.string + (hint.string ? '　' + hint.string : '');
        const split = !landscape && !!attributes.string, rowHeight = hint.lineHeight, rowOffset = rowHeight * .625;
        this.position('HintAttributes', 0, this.hintCenterY + rowOffset);
        this.position('Hint', 0, this.hintCenterY - (split ? rowOffset : 0));
        hint.node.getComponent(UITransform)!.setContentSize(attributes.node.getComponent(UITransform)!.width, split ? rowHeight : this.hintHeight);
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
            Stage: ['创业阶段', '完成经营里程碑并达到对应月份后进入下一阶段。卡包使用同一套阶段与发展里程碑条件解锁。'],
            Month: ['月份', '显示当前月份。获得办公室后开始计时，顶部进度条走完时结算工资。'],
            Supply: ['供应链', '显示已连接的供应链数量。点左下角供应链按钮选择主体，再点另一组牌堆，自动识别上下游并完成连接。'],
            Space: ['空间', '前一项是占用空间的卡牌数量，后一项是空间上限。散装现金不占空间；月末超出上限时需要清理卡牌。'],
            Cash: ['现金', '前一项是本月工资，后一项是可用现金总额（含账户），也是商战 HP。工资、消费和商战受击均先扣散装现金，再扣账户。'],
        };
        const entry = info[name]; if (!entry) return;
        const { width: w, scale } = this.metrics;
        const font = HINT_SCREEN_SIZE * scale;
        const boxScale = font / 15, width = Math.min(320 * boxScale, w - 24 * scale);
        const padding = 14 * boxScale, titleH = font * 1.5;
        if (!this.statusHelp) {
            this.statusHelp = this.makeNode('StatusHelp', this.hud, width, 1);
            const surface = this.statusHelp.addComponent(Surface);
            surface.fill = new Color(255, 247, 232); surface.stroke = new Color(117, 111, 99);
            this.text(this.statusHelp, 'Title', '', width, titleH, 0, 0).getComponent(Label)!.isBold = true;
            this.text(this.statusHelp, 'Text', '', width, 1, 0, 0);
        }
        const box = this.statusHelp; box.active = true; box.setSiblingIndex(this.hud.children.length - 1);
        const body = box.getChildByName('Text')!.getComponent(Label)!;
        body.fontSize = font; body.lineHeight = 22 * boxScale;
        body.overflow = Label.Overflow.RESIZE_HEIGHT; body.string = entry[1];
        body.node.getComponent(UITransform)!.setContentSize(width - padding * 2, 1);
        body.updateRenderData(true);
        const bodyH = body.node.getComponent(UITransform)!.height, height = padding * 2 + titleH + bodyH;
        box.getComponent(UITransform)!.setContentSize(width, height);
        const title = box.getChildByName('Title')!.getComponent(Label)!;
        title.string = entry[0]; title.fontSize = font; title.lineHeight = titleH;
        title.node.getComponent(UITransform)!.setContentSize(width - padding * 2, titleH);
        title.node.setPosition(0, height / 2 - padding - titleH / 2);
        body.node.setPosition(0, height / 2 - padding - titleH - bodyH / 2);
        const anchor = this.find('Status/' + name), status = this.find('Status');
        const x = status.position.x + anchor.position.x, edge = w / 2 - width / 2 - 12 * scale;
        box.setPosition(Math.max(-edge, Math.min(edge, x)), status.position.y + anchor.position.y - anchor.getComponent(UITransform)!.height / 2 - 8 * scale - height / 2);
        const surface = box.getComponent(Surface)!; surface.radius = 10 * boxScale; surface.lineWidth = boxScale; surface.paint();
        this.statusHelpKey = name;
    }
    private layoutStatus() {
        const { width: w, height: h, top, wide, nearSquare, scale } = this.metrics;
        const unit = fixedUiUnit(scale);
        const margin = 8 * scale, rightMargin = 6 * scale;
        const progressH = Math.max(3 * unit, 3 * scale), rowH = Math.max(34 * scale, 44 * unit);
        const y = h / 2 - (wide ? 0 : top) - progressH - rowH / 2 - 2 * unit - this.find('Status').position.y;
        const settingsSize = 58 * scale, settingsX = w / 2 - rightMargin - settingsSize / 2;
        const names = ['Stage', 'Month', 'Supply', 'Space', 'Cash'];
        const key = [w, h, scale, wide, nearSquare, top, ...names.map(name => this.label('Status/' + name + '/Value').string)].join(':');
        if (key === this.statusLayoutKey) return;
        this.statusLayoutKey = key;
        this.position('Status/Settings', settingsX, y, 64 * scale, 44 * scale);
        this.position('Status/Settings/Icon', 0, 0, settingsSize, settingsSize / 3.25);
        const icon = 28 * unit, font = 24 * unit;
        const gap = 3 * scale, groupGapMin = 3 * scale;
        const left = -w / 2 + margin, right = settingsX - settingsSize / 2 - 6 * scale;
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
        const previousScale = this.inputScale, previousPosition = this.board.node.position;
        const previousView: SavedView | null = this.layoutReady ? { zoom: this.board.zoom / previousScale, pitch: this.board.pitch,
            centerX: -previousPosition.x / this.board.zoom, centerY: -previousPosition.y / (this.board.zoom * this.board.pitch) } : null;
        this.hideStatusInfo();
        this.router?.cancel(); this.metrics = measureLayout();
        const { width: w, height: h, top: measuredTop, bottom: measuredBottom, wide, nearSquare, scale } = this.metrics; this.inputScale = scale;
        this.model.setViewport(w, h);
        const top = wide ? 0 : measuredTop, bottom = wide ? 0 : measuredBottom;
        this.node.getComponent(UITransform)!.setContentSize(w, h); this.backdrop.getComponent(UITransform)!.setContentSize(w, h);
        const unit = fixedUiUnit(scale), margin = 22 * unit;
        const topY = h / 2 - top, progressH = Math.max(3 * unit, 3 * scale);
        const rowH = Math.max(34 * scale, 44 * unit), statusH = rowH + progressH + 4 * unit;
        this.position('Status', 0, h / 2 - (statusH + top) / 2, w, statusH + top);
        this.statusLayoutKey = ''; this.layoutStatus();
        this.position('Status/ProgressSlot', 0, h / 2 - progressH / 2 - this.find('Status').position.y, w, progressH);
        const progressSize = this.find('Status/ProgressSlot').getComponent(UITransform)!.contentSize;
        this.find('Status/Progress').getComponent(UITransform)!.setContentSize(progressSize);
        const landscape = w > h;
        const footerH = landscape ? statusH + top - bottom : 1.6 * Math.max(68 * unit, 36 * scale);
        const footerY = -h / 2 + bottom + footerH / 2;
        this.hintCenterY = footerY; this.hintHeight = footerH;
        this.position('BottomBar', 0, -h / 2 + (bottom + footerH) / 2, w, bottom + footerH);
        for (const name of ['Hint', 'TaskReminder']) {
            this.position(name, 0, footerY, w - margin * 2, footerH);
            const label = this.label(name); label.fontSize = 26 * unit;
            label.lineHeight = label.fontSize * 1.2; label.verticalAlign = Label.VerticalAlign.CENTER;
        }
        const hintAttributes = this.label('HintAttributes');
        this.position('HintAttributes', 0, footerY, w - margin * 2, this.label('Hint').lineHeight);
        hintAttributes.fontSize = this.label('Hint').fontSize; hintAttributes.lineHeight = this.label('Hint').lineHeight;
        this.label('Hint').cacheMode = Label.CacheMode.NONE;
        this.label('Hint').overflow = Label.Overflow.SHRINK;
        this.label('Hint').enableWrapText = false;
        this.position('Toolbar', 0, 0, w, h);
        const cornerTarget = Math.max(80 * unit, 64 * scale), cornerArt = Math.max(80 * unit, 60 * scale) * .9;
        this.cornerIconScale = cornerArt / 64 * .8;
        const iconY = (size: number) => -h / 2 + bottom + footerH + size / 2 + 2 * scale;
        for (const [name, direction] of [['SupplyChain', -1], ['SellZone', 1]] as const) {
            this.position(name, direction * (w / 2 - margin - cornerTarget / 2), iconY(cornerArt * .8 * .8), cornerTarget, cornerTarget);
            this.position(name + '/Icon', 0, 0, 64, 64);
            this.find(name + '/Icon').setScale(this.cornerIconScale * .8, this.cornerIconScale * .8, 1);
            this.find(name + '/Feedback').setScale(cornerTarget / 64, cornerTarget / 64, 1);
        }
        this.position('PauseControl', 0, iconY(cornerArt * .8 * .9), cornerTarget, cornerTarget);
        this.find('PauseControl/Icon').setScale(this.cornerIconScale * .9, this.cornerIconScale * .9, 1);
        const stripH = 72 * scale, stripTop = topY - statusH - (landscape ? 10 * unit : 12 * unit);
        const stripW = w - margin * 2;
        this.boardTop = landscape ? stripTop - 12 * scale : stripTop - stripH - 20;
        this.originalHud.layout(w, h, stripTop - stripH / 2, stripH, stripW, scale, landscape, unit);
        const hint = this.label('Hint'), reminder = this.label('TaskReminder'), reminderH = hint.lineHeight * 2.2;
        this.position('TaskReminder', 0, stripTop - stripH - 10 * scale - reminderH / 2, w - margin * 2, reminderH);
        reminder.font = hint.font; reminder.fontSize = hint.fontSize; reminder.lineHeight = hint.lineHeight;
        reminder.horizontalAlign = hint.horizontalAlign; reminder.color = new Color(58, 53, 47);
        this.viewport.getComponent(UITransform)!.setContentSize(w, h);
        this.pauseWash.layout(w, h);
        this.board.configure(w, h, { left: -w / 2 + this.find('Toolbar/Book').getComponent(UITransform)!.width + 24 * scale,
            right: w / 2 - 24 * scale, top: this.boardTop - 36 * scale, bottom: -h / 2 + bottom + footerH + 24 * scale });
        if (previousView && previousScale !== scale) this.restoreBoard(previousView);
        this.layoutReady = true;
        this.position('Scrim', 0, 0, w, h);
        this.titleScreen.layout(this.metrics);
        this.cardCatalog.layout(this.metrics);
        this.cardInspector.layout(this.metrics);
        this.menuBackdrop.layout(this.metrics);
        this.layoutPanel();
        this.syncMenuBackdrop();
    }
    private layoutWindow = () => this.layout();
    private layoutPanel() {
        const { width: w, height: h, wide, scale } = this.metrics;
        const top = wide ? 0 : this.metrics.top, bottom = wide ? 0 : this.metrics.bottom;
        const unit = fixedUiUnit(scale), target = Math.max(52.8 * unit, 44 * scale);
        this.panelW = wide ? 500 : w - 32;
        this.panelH = Math.min(wide ? 820 : 1080, h - top - bottom - 36);
        const pw = this.panelW, ph = this.panelH;
        this.position('Panel', wide ? w / 2 - pw / 2 - 20 : 0, wide ? (bottom - top) / 2 : -h / 2 + bottom + ph / 2 + 8, pw, ph);
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
        panelSurface.fill.a = plain ? 0 : 255; panelSurface.lineWidth = plain ? 0 : 2;
        panelSurface.radius = 26; panelSurface.paint();
        const scrim = this.find('Scrim').getComponent(Surface)!; scrim.fill.a = 0; scrim.paint();
        for (const name of ['Eyebrow', 'Title', 'Close', 'Rule', 'Back', 'Page']) this.find('Panel/' + name).active = !plain;
        this.label('Panel/Title').fontSize = 38 * unit;
        this.label('Panel/Eyebrow').fontSize = 18 * unit;
        this.label('Panel/Page').fontSize = 20 * unit;
        this.label('Panel/Back/Text').fontSize = 24 * unit;
        for (const name of ['Title', 'Eyebrow', 'Page', 'Back/Text']) {
            const label = this.label('Panel/' + name); label.lineHeight = label.fontSize * 1.5;
        }
        if (plain) {
            const rows = this.menuRows, availableHeight = h - top - bottom - 56 * scale;
            const rowHeight = Math.min(52 * scale, (availableHeight - (rows - 1) * 10 * scale) / rows) * MENU_SCALE;
            const height = rows * rowHeight + (rows - 1) * 10 * scale * MENU_SCALE;
            this.panelW = Math.min(320 * scale, w - 48 * scale) * .7 * MENU_SCALE; this.panelH = height;
            this.position('Panel', 0, (bottom - top) / 2, this.panelW, height);
            this.position('Panel/Content', 0, 0, this.panelW, height);
        }
        if (this.modal !== 'none') this.renderPanel();
    }
    private get plainMenu() { return ['book', 'settings', 'home'].includes(this.modal); }
    private get menuRows() { return this.modal === 'settings' ? 5 + (canSetDisplayOrientation() ? 1 : 0) : this.entries().length; }
    private show(modal: Modal, resetPage = true) {
        if (modal !== 'none') this.cancelSupply();
        this.releaseMenuPress();
        this.hideStatusInfo();
        if (modal !== 'none') { this.originalHud.close(); this.originalHud.closePacks(); }
        const previous = this.modal;
        const wasPlain = this.plainMenu || ['inspect', 'catalog'].includes(this.modal), nextPlain = ['book', 'settings', 'home', 'inspect', 'catalog'].includes(modal);
        if (!wasPlain && nextPlain) { this.menuPauseBefore = this.model.paused; this.model.paused = true; }
        if (wasPlain && !nextPlain) this.model.paused = this.menuPauseBefore;
        this.modal = modal; if (resetPage) this.page = 0;
        this.find('Panel').active = !['none', 'home', 'inspect', 'catalog'].includes(modal); this.find('Scrim').active = !['none', 'home', 'inspect', 'catalog'].includes(modal);
        this.cardInspector.node.active = modal === 'inspect';
        this.find('PauseControl').active = modal === 'none' && !this.atTitle;
        this.find('Toolbar').active = modal === 'none' && !this.atTitle;
        this.titleScreen.show(this.atTitle, modal === 'home', this.hasStarted);
        this.viewport.active = !this.atTitle;
        for (const name of ['Status', 'PackStrip', 'BottomBar', 'Hint', 'TaskReminder', 'SupplyChain', 'SellZone']) this.find(name).active = !this.atTitle;
        this.originalHud.setVisible(!this.atTitle);
        this.layoutPanel();
        if (modal === 'catalog') {
            if (previous !== 'inspect') this.cardCatalog.open(this.model, this.metrics);
            else this.cardCatalog.node.active = true;
        } else if (!(modal === 'inspect' && this.inspectorReturn === 'catalog')) this.cardCatalog.hide();
        this.syncMenuBackdrop();
    }
    private syncMenuBackdrop() {
        const menu = !['none', 'home', 'inspect', 'catalog'].includes(this.modal);
        if (menu || this.modal === 'none' && this.originalHud.open) this.menuBackdrop.show();
        else this.menuBackdrop.hide();
    }
    private entries(): Entry[] {
        const m = this.model, d = m.data;
        switch (this.modal) {
            case 'book': return [
                { title: '继续', action: 'Continue' }, { title: '重新开始', action: 'Restart' },
                { title: '图鉴', action: 'Open:catalog' },
                { title: '设置', action: 'OpenSettings' }, { title: '回到主菜单', action: 'Home' },
            ];
            case 'home': return [{ title: '开始游戏', action: 'Restart' }, { title: '继续游戏', action: 'Continue' }, { title: '设置', action: 'OpenSettings' }];
            case 'packs': return d.packOrder.map(id => ({ title: d.packs[id].name + `  $${d.packs[id].price}`, text: m.packUnlocked(id) ? `${d.packs[id].minCards}–${d.packs[id].maxCards} 张 · 点击购买卡包` : m.packRequirement(id), action: 'Buy:' + id, muted: !m.packUnlocked(id) }));
            case 'recipes': return d.recipes.map(r => ({ title: m.models.has(r.id) ? r.name : '尚未发现的商业模式', text: m.models.has(r.id) ? r.formula + (r.worker_tags.length ? '\n需要员工参与' : '') : `在${d.packs[r.packId]?.name || ''}中寻找，或亲自叠牌发现`, muted: !m.models.has(r.id) }));
            case 'tasks': return d.tasks.map(t => ({ title: (m.completed.has(t.id) ? '✓ ' : '') + t.title,
                text: t.content + (m.completed.has(t.id) ? ' · 已完成' : ` (${m.counters[t.triggerType + '|' + t.targetId] || 0}/${t.targetCount})`) }));
            default: return [];
        }
    }
    private renderPanel() {
        const content = this.find('Panel/Content'); content.children.slice().forEach(n => n.destroy());
        for (const action of Array.from(this.controls.keys())) if (action.startsWith('Row:')) this.controls.delete(action);
        if (this.modal === 'home' || this.modal === 'inspect' || this.modal === 'catalog') return;
        if (this.plainMenu) { this.renderMenu(content); return; }
        const titles: Record<string, string> = { book: '设置', packs: '抽取卡包', catalog: '卡牌图鉴', recipes: '商业模式', tasks: '发展里程碑', detail: '卡牌详情' };
        this.label('Panel/Title').string = titles[this.modal] || '';
        this.label('Panel/Eyebrow').string = 'STARTX';
        const { width, height } = content.getComponent(UITransform)!.contentSize;
        if (this.modal === 'detail') { this.renderDetail(content, width, height); this.pageCount = 1; }
        else {
            const rowSize = 132;
            const rows = this.entries(), perPage = Math.max(3, Math.floor(height / rowSize)); this.pageCount = Math.max(1, Math.ceil(rows.length / perPage));
            this.page = Math.max(0, Math.min(this.pageCount - 1, this.page));
            rows.slice(this.page * perPage, (this.page + 1) * perPage).forEach((r, i) => {
                const rowHeight = Math.min(128, height / perPage), y = height / 2 - rowHeight * (i + .5);
                this.row(content, r, width, rowHeight - 10, y);
            });
        }
        this.find('Panel/Prev').active = this.pageCount > 1; this.find('Panel/Next').active = this.pageCount > 1;
        this.label('Panel/Page').string = this.pageCount > 1 ? `${this.page + 1} / ${this.pageCount}` : '';
        this.label('Panel/Back/Text').string = this.modal === 'book' || this.modal === 'detail' || this.modal === 'packs' ? '回到棋盘' : '返回手册';
    }
    private menuButton(parent: Node, text: string, action: string, width: number, height: number, x: number, y: number, font = 23) {
        const scale = this.inputScale * MENU_SCALE, node = this.makeNode('Option', parent, width, height); node.setPosition(x, y);
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
        const scale = this.inputScale * MENU_SCALE, width = this.panelW, height = this.panelH, gap = 10 * scale;
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
            if (canSetDisplayOrientation()) this.menuButton(content, getDisplayOrientation() === 'landscape' ? '横屏模式' : '竖屏模式', 'ToggleOrientation', width, rowH, 0, y(4));
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
            const unit = fixedUiUnit(this.inputScale), padding = Math.max(10 * unit, 7 * this.inputScale);
            const titleFont = Math.max(22 * unit, 15 * this.inputScale), bodyFont = Math.max(18 * unit, 12 * this.inputScale), titleH = titleFont * 1.4;
            bg.radius = 8; bg.fill.a = entry.muted ? 90 : 145; bg.paint();
            this.text(node, 'Title', entry.title, width - padding * 2, titleH, 0, height / 2 - padding - titleH / 2, titleFont, entry.muted ? '777E70' : '344637');
            if (entry.text) {
                const bodyH = height - padding * 2 - titleH - 2 * this.inputScale;
                const text = this.text(node, 'Text', entry.text, width - padding * 2, bodyH, 0, -height / 2 + padding + bodyH / 2, bodyFont, entry.muted ? '777E70' : '69765D');
                text.getComponent(Label)!.verticalAlign = Label.VerticalAlign.TOP;
            }
        } else {
            const unit = fixedUiUnit(this.inputScale);
            this.text(node, 'Title', entry.title, width - 32, entry.text ? 38 : height - 12, 0, entry.text ? height / 2 - 28 : 0, 25 * unit, entry.muted ? '929889' : '344637');
            if (entry.text) this.text(node, 'Text', entry.text, width - 32, height - 45, 0, -20, 20 * unit, entry.muted ? '929889' : '69765D');
        }
        if (entry.action) this.controls.set('Row:' + entry.action, node);
    }
    private renderDetail(parent: Node, width: number, height: number) {
        const m = this.model, c = this.catalogId ? undefined : m.card(this.selected);
        const id = this.catalogId || c?.id, d = id ? m.data.cards[id] : undefined;
        if (!d || !id) { this.text(parent, 'Missing', '这张卡牌已被消耗。', width, 100, 0, 0); return; }
        this.label('Panel/Title').string = d.name;
        const types: Record<string, string> = { employee: '员工', tool: '工具', customer: '客户', product: '产品', resource: '资源', facility: '设施', cash: '现金', rival: '对手', business_model: '商业模式', order: '订单', event: '客户事件', receivable: '应收尾款' };
        this.label('Panel/Eyebrow').string = 'STARTX  /  ' + types[d.type];
        const faceSize = Math.min(200, height * .28), imageY = height / 2 - faceSize / 2;
        const actionHeight = Math.max(82, 44 * this.inputScale), stateHeight = 64, gap = 16;
        const card = instantiate(this.cardPrefab); parent.addChild(card); card.setPosition(0, imageY); card.setScale(faceSize / 280, faceSize / 280, 1);
        const view = card.getComponent(CardView)!;
        this.loadFrame('faces/' + id).then(frame => { if (!card.isValid) return; view.configure(frame, d.bodyColor, cardStyle(id, d.type));
            if (c?.uses != null && c.uses >= 0) this.loadFrame('patches/' + id + '-' + c.uses).then(f => { if (view.isValid) view.setPatch(f, 'uses'); });
            else if (c?.id === 'p3_account') this.loadFrame('patches/account-' + c.stored).then(f => { if (view.isValid) view.setPatch(f, 'account'); });
        }).catch(e => { this.lastError = String(e); });
        const description = c ? m.description(c) : [d.functionText, quoteFlavor(d.flavor)].filter(Boolean).join('\n\n');
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
            if (this.heldBadge) return this.cardInspector.containsFace(p) ? 'InspectPlaceBadge' : 'ExitWithBadge';
            if (this.hit(this.cardInspector.closeNode, p)) return 'InspectClose';
            const badge = !this.catalogId && this.inspectorReturn === 'none' ? this.cardInspector.badgeAt(p) : -1;
            if (badge >= 0) return 'InspectBadge:' + badge;
            const icon = this.cardInspector.iconAt(p); if (icon) return 'InspectCard:' + icon;
            return this.cardInspector.containsDetails(p) ? 'InspectDetails' : this.cardInspector.contains(p) ? 'InspectFlip' : 'InspectClose';
        }
        if (this.modal === 'catalog') return this.cardCatalog.actionAt(p);
        if (this.modal === 'none') {
            if (this.statusHelp?.active && this.hit(this.statusHelp, p)) return 'StatusHelpClose';
            const action = this.originalHud.actionAt(p); if (action) return action;
        }
        for (const [action, n] of Array.from(this.controls.entries()).reverse()) {
            if (action === 'PackTab' && this.hit(this.find('Status'), p)) continue;
            if (action === 'FlashPack' || action.startsWith('TopPack:') || action.startsWith('TaskFold:') || action.startsWith('TaskItem:') || action === 'TaskClose') continue;
            if (this.modal === 'none' && (action.startsWith('Row:') || ['Close', 'Back', 'Prev', 'Next'].includes(action))) continue;
            if (this.modal !== 'none' && ['Book', 'Tasks', 'Settings', 'SupplyChain', 'SellZone', 'Pause', 'PackTab'].includes(action)) continue;
            if (this.modal !== 'none' && action.startsWith('StatusInfo:')) continue;
            if (this.hit(n, p)) return action;
        }
        if (this.modal !== 'none') return this.hit(this.find('Panel'), p) ? 'Noop' : 'Dismiss';
        // Fixed status and information bars never pan the board.
        if (this.hit(this.find('Status'), p) || this.hit(this.find('BottomBar'), p)) return 'Noop';
        return '';
    }
    private topAt(p: Vec2, excluded: number[] = []) {
        const world = this.board.pointerWorld(p);
        const uid = Array.from(this.views.entries()).filter(([id, v]) => !excluded.includes(id) && v.view.node.scale.x > 0 && v.view.contains(world))
            .sort((a, b) => b[1].view.node.getSiblingIndex() - a[1].view.node.getSiblingIndex())[0]?.[0] || 0;
        return uid;
    }
    private worldPoint(p: Vec2) { return this.board.node.getComponent(UITransform)!.convertToNodeSpaceAR(this.board.pointerWorld(p)); }
    private moveHeldBadge(p: Vec2) {
        this.heldBadgePoint.set(p);
        if (!this.heldBadgeSprite) return;
        const node = this.heldBadgeSprite.node, local = this.node.getComponent(UITransform)!.convertToNodeSpaceAR(new Vec3(p.x, p.y));
        node.setPosition(local.x, local.y); node.getComponent(UITransform)!.setContentSize(60 * this.inputScale, 60 * this.inputScale);
        node.setSiblingIndex(this.node.children.length - 1);
    }
    private carryBadge(uid: number, p: Vec2) {
        const badge = this.model.card(uid); if (!badge) return;
        this.heldBadge = uid;
        if (!this.heldBadgeSprite) {
            const node = this.makeNode('HeldBadge', this.node, 60, 60);
            this.heldBadgeSprite = node.addComponent(Sprite); this.heldBadgeSprite.sizeMode = Sprite.SizeMode.CUSTOM;
        }
        const sprite = this.heldBadgeSprite; sprite.spriteFrame = null; sprite.node.active = true;
        this.loadFrame('faces/' + badge.id).then(frame => { if (this.heldBadge === uid && sprite.isValid) sprite.spriteFrame = frame; });
        this.moveHeldBadge(p);
    }
    private releaseHeldBadge() {
        this.heldBadge = 0; if (this.heldBadgeSprite) this.heldBadgeSprite.node.active = false;
    }
    private placeHeldBadge(p: Vec2) {
        const badge = this.model.card(this.heldBadge); if (!badge) { this.releaseHeldBadge(); return; }
        if (this.actionAt(p) || !this.hit(this.viewport, p)) return;
        const target = this.model.card(this.topAt(p, [badge.uid]));
        if (target) {
            const world = this.board.pointerWorld(p);
            const position = this.views.get(target.uid)!.view.badgePositionAt(new Vec2(world.x, world.y));
            if (!this.model.attachBadge(badge, target, position)) { this.model.say('毛线徽章只能贴在员工卡上'); return; }
        } else {
            const point = this.worldPoint(p); this.model.move(badge.uid, point.x, point.y);
        }
        this.releaseHeldBadge(); this.syncViews(); this.saveProgress();
    }
    press(p: Vec2): 'card' | 'board' | 'ui' {
        this.releaseMenuPress();
        if (this.modal === 'none') this.originalHud.dismissPacksAt(p);
        if (this.atTitle) this.titleScreen.pointer(p);
        this.audio.prime();
        if (this.heldBadge) {
            this.moveHeldBadge(p); this.pressedCard = this.pressedPack = 0;
            this.pressedAction = this.modal === 'inspect' ? this.actionAt(p) : 'PlaceHeldBadge'; return 'ui';
        }
        if (this.founderSpeech.contains(p)) { this.pressedAction = 'FounderSpeech'; this.pressedCard = this.pressedPack = 0; return 'ui'; }
        this.founderSpeech.dismiss();
        if (this.modal === 'inspect') { this.cardInspector.begin(p); this.pressedAction = this.actionAt(p); this.pressedCard = this.pressedPack = 0; return 'ui'; }
        if (this.modal === 'catalog') this.cardCatalog.begin(p); else this.originalHud.begin(p);
        this.dragPointer.set(p);
        this.pressedAction = this.actionAt(p); this.pressedCard = 0; this.pressedPack = 0;
        if (!this.pressedAction.startsWith('StatusInfo:') && this.statusHelp?.active && !this.hit(this.statusHelp, p)) this.hideStatusInfo();
        if (this.plainMenu && this.pressedAction.startsWith('Row:') || this.pressedAction.startsWith('Title:') || this.pressedAction === 'Settings') this.pressMenuButton(this.controls.get(this.pressedAction));
        if (this.pressedAction) return 'ui';
        const uid = this.topAt(p), c = this.model.card(uid), pack = this.model.packs.find(v => v.uid === uid);
        if (c && (this.model.isCombatant(c.sid) || this.model.isPassive(c))) return 'ui';
        if (c || pack) {
            this.pressedCard = c?.uid || 0; this.pressedPack = pack?.uid || 0;
            const start = c ? this.model.position(c) : pack!, local = this.worldPoint(p);
            this.dragPoint.set(start.x, start.y); this.dragOffset.set(local.x - start.x, local.y - start.y); return 'card';
        }
        return 'board';
    }
    tap(p: Vec2, kind: string) {
        this.releaseMenuPress();
        if (this.heldBadge && this.modal === 'none') { this.moveHeldBadge(p); this.placeHeldBadge(p); return; }
        if (this.modal === 'inspect' && (this.heldBadge || this.pressedAction.startsWith('InspectBadge:'))) this.heldBadgePoint.set(p);
        if (kind === 'card') {
            if (this.pressedPack) { const initial = this.model.packs.find(p => p.uid === this.pressedPack)?.id === 'garage_pack' && this.model.month === 1; this.model.openPack(this.pressedPack); this.syncViews(); if (initial && !this.model.packs.length) this.fitBoard(); return; }
            if (this.supplyStep !== 'none') { this.chooseSupply(this.pressedCard); return; }
            this.selected = this.pressedCard; this.selectedPack = 0; this.catalogId = '';
            const card = this.model.card(this.selected);
            if (card) { this.model.say(this.model.cardHint(card), 'hint'); if (card.id === 'p3_account') this.model.withdraw(card); else if (this.model.def(card).type === 'order') this.model.acceptOrder(card); this.hintCardUid = card.uid; this.hintNoticeVersion = this.model.noticeVersion; } this.saveProgress(); return;
        }
        if (kind === 'board') { this.cancelSupply(); this.selected = 0; this.hintCardUid = 0; this.originalHud.close(); this.syncMenuBackdrop(); this.model.say(DEFAULT_HINT, 'hint'); return; }
        const action = this.actionAt(p); if (action && action === this.pressedAction) this.perform(action.replace(/^(Row|Title):/, ''));
    }
    private perform(action: string) {
        const [verb, arg] = action.split(':'); const c = this.model.card(this.selected);
        const entering = verb === 'Restart' || verb === 'Continue' && this.atTitle;
        if (entering) { this.menuPauseBefore = false; this.model.paused = false; }
        switch (verb) {
            case 'StatusInfo': this.showStatusInfo(arg); break;
            case 'StatusHelpClose': this.hideStatusInfo(); break;
            case 'PackTab': this.originalHud.togglePacks(); break;
            case 'CatalogClose': this.show(this.catalogReturn); break;
            case 'CatalogSort': this.cardCatalog.setSort(arg); break;
            case 'CatalogCard': {
                const frame = this.cardCatalog.frame(arg); if (!frame || !this.model.drawn.has(arg)) break;
                const d = this.model.def(arg); this.catalogId = arg; this.inspectorReturn = 'catalog'; this.show('inspect');
                this.cardInspector.presentFrame(frame, d.bodyColor, cardStyle(arg, d.type),
                    d.functionText || '与其他卡牌叠放，发现商业模式', d.flavor || ''); this.cardInspector.setReference(this.model, arg); break;
            }
            case 'Tasks': this.originalHud.toggle(); break;
            case 'TaskFold': this.originalHud.fold(arg); break;
            case 'TaskItem': { const text = this.originalHud.infoFor(arg); this.originalHud.showInfo(arg); if (text) this.model.say(text, 'hint'); break; }
            case 'TaskHelpClose': this.originalHud.hideInfo(); break;
            case 'FlashPack': {
                const source = this.controls.get('FlashPack')!.worldPosition;
                const from = this.worldPoint(new Vec2(source.x, source.y));
                const screen = this.viewport.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(0, -60));
                const center = this.worldPoint(new Vec2(screen.x, screen.y));
                this.model.openFlashPack(center.x, center.y, from); break;
            }
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
            case 'SupplyChain': this.toggleSupply(); break;
            case 'SellZone': this.model.say('将卡牌拖到这里回收，员工可免费解雇'); break;
            case 'Pack': this.show('packs'); break;
            case 'Details': this.catalogId = ''; if (!this.model.card(this.selected)) this.selected = this.model.cards[0]?.uid || 0; this.show('detail'); break;
            case 'InspectClose': if (!this.cardInspector.goBack()) { this.show(this.inspectorReturn, false); this.inspectorReturn = 'none'; } break;
            case 'InspectBadge': {
                if (!c || this.heldBadge) break;
                const badge = this.model.detachBadge(c, Number(arg)); if (!badge) break;
                this.cardInspector.removeBadge(Number(arg), this.model.employeeCapacity(c), this.model.description(c).split('\n\n')[0]);
                this.carryBadge(badge.uid, this.heldBadgePoint); this.syncViews(); break;
            }
            case 'InspectPlaceBadge': {
                const badge = this.model.card(this.heldBadge), frame = this.heldBadgeSprite?.spriteFrame;
                if (!c || !badge || !frame) break;
                const position = this.cardInspector.badgePositionAt(this.heldBadgePoint);
                if (!this.model.attachBadge(badge, c, position)) break;
                this.cardInspector.addBadge(frame, position, this.model.employeeCapacity(c), this.model.description(c).split('\n\n')[0]);
                this.releaseHeldBadge(); this.syncViews(); break;
            }
            case 'ExitWithBadge': this.show('none', false); this.inspectorReturn = 'none'; break;
            case 'InspectCard': void this.cardInspector.openCard(this.model, arg); break;
            case 'InspectFlip': this.cardInspector.flip(); break;
            case 'Close': case 'Dismiss': if (this.modal === 'settings') this.show(this.settingsReturn); else if (this.modal !== 'home') this.show('none'); break;
            case 'Back': this.show(['catalog', 'recipes', 'tasks'].includes(this.modal) ? 'book' : 'none'); break;
            case 'Prev': this.page = Math.max(0, this.page - 1); this.renderPanel(); break;
            case 'Next': this.page = Math.min(this.pageCount - 1, this.page + 1); this.renderPanel(); break;
            case 'Reset': this.fitBoard(); this.show('none'); break;
            case 'Buy': {
                const source = this.controls.get('Row:' + action) || this.controls.get('TopPack:' + arg)!;
                if (this.buyPackAt(arg, source, -40)) this.show('none'); else this.renderPanel(); break;
            }
            case 'Card': this.catalogId = arg; this.show('detail'); break;
            case 'Sell': if (c) this.model.sell(c.sid); this.show('none'); break;
            case 'Withdraw': if (c) this.model.withdraw(c); this.show('none'); break;
            case 'Unlink': if (c) this.model.disconnect(c.uid); this.show('none'); break;
            case 'Unpack': this.model.openPack(this.selectedPack); this.show('none'); break;
            case 'Pause': { const paused = !this.gameplayPaused; this.menuPauseBefore = paused; this.model.paused = paused; this.show('none'); this.updatePausePresentation(); break; }
            case 'Continue': this.hasStarted = true; this.atTitle = false; this.show('none'); break;
            case 'OpenSettings': this.settingsReturn = this.atTitle ? 'home' : 'book'; this.show('settings'); break;
            case 'SettingsBack': this.show(this.settingsReturn); break;
            case 'ToggleOrientation':
                setDisplayOrientation(getDisplayOrientation() === 'landscape' ? 'portrait' : 'landscape');
                this.layout(); break;
            case 'NightShift':
                this.nightShift = !this.nightShift;
                try { sys.localStorage.setItem('startx.night-shift', String(this.nightShift)); } catch { /* The current session still applies. */ }
                this.renderPanel(); break;
            case 'Volume': this.audio.adjustVolume(arg.startsWith('sfx') ? 'sfx' : 'music', arg.endsWith('Up') ? .1 : -.1); this.renderPanel(); break;
            case 'TestMode':
                this.testMode = !this.testMode; this.model.testMode = this.testMode;
                try { sys.localStorage.setItem('startx.test-mode', String(this.testMode)); } catch { /* The current session still applies. */ }
                this.model.say(this.testMode ? '测试模式已开启：全部卡包解锁，新开局获得余额 50 的账户' : '测试模式已关闭：新开局恢复原版现金与卡包规则', 'hint');
                this.renderPanel(); break;
            case 'Home': this.atTitle = true; this.show('home'); break;
            case 'Restart':
                this.hasStarted = true;
                for (const view of this.board.node.getComponentsInChildren(CardView)) view.node.destroy();
                this.views.clear(); this.cashFlights.clear(); this.battleView.reset();
                this.releaseHeldBadge(); this.hintCardUid = 0; this.hintNoticeVersion = -1; this.atTitle = false; this.model = new GameModel(this.model.data, Math.random, this.testMode); this.originalHud.reset(this.model); this.selected = this.model.cards[0].uid; this.board.reset(); this.show('none'); this.frameOpening(); break;
        }
        this.syncViews();
        if (entering) { this.spokenMilestones = new Set(this.model.completed); this.founderSpeech.welcome(); }
        this.syncMenuBackdrop();
        this.saveProgress();
    }
    hold(_p: Vec2) {
        const held = this.model.card(this.pressedCard); if (held && this.model.isPassive(held)) return;
        const source = this.views.get(this.pressedCard || this.pressedPack)?.view; if (!source) return;
        this.inspectorReturn = 'none';
        this.selected = this.pressedCard; this.selectedPack = this.pressedPack; this.catalogId = '';
        this.show('inspect');
        const card = this.model.card(this.selected);
        if (card) {
            const d = this.model.def(card), dynamic = card.uses >= 0 || card.id === 'p3_account' || !!card.badges?.length || !!this.model.cardStatus(card);
            const functionText = dynamic ? this.model.description(card).split('\n\n')[0] : d.functionText || (d.type === 'cash' ? '用于购买卡包、支付工资' : '与其他卡牌叠放，发现商业模式');
            this.cardInspector.present(source, d.bodyColor, cardStyle(card.id, d.type), functionText, d.flavor || '');
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
    private cancelSupply() {
        this.supplyStep = 'none'; this.supplyAnchor = this.supplyCandidate = 0; this.supplyDirection = null; this.supplyMessage = '';
        for (const frame of this.supplyFrames.values()) frame.node.destroy(); this.supplyFrames.clear();
    }
    private toggleSupply() {
        if (this.model.battle) { this.model.say('商战结束后再连接供应链'); return; }
        if (this.supplyStep !== 'none') { this.cancelSupply(); return; }
        this.originalHud.close(); this.syncMenuBackdrop(); this.hideStatusInfo();
        this.supplyStep = 'subject'; this.supplyMessage = '选择供应链主体 · 点击一张卡牌或牌堆';
        this.model.say(this.supplyMessage);
    }
    private chooseSupply(uid: number) {
        const card = this.model.card(uid); if (!card || !this.model.canSupply(card)) return;
        if (this.supplyStep === 'subject') {
            this.supplyAnchor = this.model.stack(card.sid)!.cards[0]; this.selected = uid;
            this.supplyStep = 'target'; this.supplyMessage = '选择另一张卡牌或牌堆 · 自动识别上游或下游'; this.model.say(this.supplyMessage); return;
        }
        const anchor = this.model.card(this.supplyAnchor); if (!anchor) { this.cancelSupply(); return; }
        if (card.sid === anchor.sid) { this.supplyMessage = '请选择主体之外的另一组牌堆'; this.model.say(this.supplyMessage); return; }
        const candidate = this.model.stack(card.sid)!.cards[0], direction = this.model.supplyDirection(this.supplyAnchor, candidate);
        if (!direction) { this.supplyMessage = '这组牌堆暂时无法衔接 · 请另选上游或下游'; this.model.say(this.supplyMessage); return; }
        this.supplyCandidate = candidate; this.supplyDirection = direction; this.finishSupply();
    }
    private finishSupply() {
        const anchor = this.model.card(this.supplyAnchor), candidate = this.model.card(this.supplyCandidate);
        if (!anchor || !candidate || !this.supplyDirection) { this.cancelSupply(); return; }
        const upstream = this.supplyDirection === 'upstream', source = upstream ? candidate : anchor, target = upstream ? anchor : candidate;
        const message = `完成供应链${upstream ? '上' : '下'}游组建`;
        if (!this.model.connect(source.uid, target.uid, message)) { this.supplyMessage = this.model.notice + ' · 可另选牌堆'; return; }
        this.linkBirths.set(source.sid + ':' + target.sid, this.supplyClock);
        this.audio.play('aha'); this.selected = candidate.uid;
        this.cancelSupply(); this.syncViews(); this.saveProgress();
    }
    private clearDropHint() { this.matchTarget = 0; this.matchArt.node.active = false; this.matchArt.clear(); }
    private updateDropHint(dt: number) {
        let target = 0;
        if (this.dragging && this.pressedCard && this.modal === 'none' && !this.hit(this.find('SellZone'), this.dragPointer)) {
            const center = this.board.projectWorld(this.board.node.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(this.dragPoint.x, this.dragPoint.y)));
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
        this.find('SupplyChain/Feedback').active = this.supplyStep !== 'none';
    }
    dragStart() {
        const c = this.model.card(this.pressedCard); if (c && (this.model.isCombatant(c.sid) || this.model.isPassive(c))) return;
        this.cancelSupply();
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
                const world = this.board.node.getComponent(UITransform)!.convertToWorldSpaceAR(new Vec3(this.dragPoint.x, this.dragPoint.y));
                const center = this.board.projectWorld(world);
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
                } else this.model.move(this.pressedCard, this.dragPoint.x, this.dragPoint.y, target, this.views.get(target)?.view.badgePositionAt(new Vec2(world.x, world.y)));
                this.selected = this.pressedCard; this.catalogId = '';
                this.hintCardUid = this.pressedCard; this.hintNoticeVersion = this.model.noticeVersion;
            }
        }
        this.dragging = false; this.sellReady = false; this.find('SellZone/Feedback').active = false;
        this.clearDropHint();
        this.model.heldStack = -1; this.syncViews();
        this.saveProgress();
    }
    pan(delta: Vec2, point?: Vec2) {
        if (this.modal !== 'none' || this.model.battle || this.battleView.restoring) return;
        const current = point || new Vec2(this.metrics.width / 2, this.metrics.height / 2);
        const to = this.board.pointerOnPlane(current), from = this.board.pointerOnPlane(new Vec2(current.x - delta.x, current.y - delta.y));
        this.board.pan(new Vec2(to.x - from.x, to.y - from.y));
    }
    uiDrag(delta: Vec2) { this.releaseMenuPress(); if (this.heldBadge) this.moveHeldBadge(new Vec2(this.heldBadgePoint.x + delta.x, this.heldBadgePoint.y + delta.y)); else if (this.modal === 'inspect' && (this.pressedAction === 'InspectDetails' || this.pressedAction.startsWith('InspectCard:'))) this.cardInspector.dragDetails(delta); else if (this.modal === 'inspect' && this.pressedAction === 'InspectFlip') this.cardInspector.drag(delta); else if (this.modal === 'catalog') this.cardCatalog.drag(delta); else if (this.modal === 'none') this.originalHud.drag(delta); }
    uiDragThreshold() { return (this.modal === 'inspect' ? 2 : this.originalHud.isPackGesture ? 3 : 8) * this.inputScale; }
    uiEnd(cancelled: boolean) { this.releaseMenuPress(); if (this.modal === 'catalog') this.cardCatalog.end(); else if (this.modal === 'inspect') this.cardInspector.end(); else this.originalHud.end(cancelled); }
    hover(p: Vec2) { if (this.heldBadge) this.moveHeldBadge(p); else if (this.atTitle) this.titleScreen.pointer(p); else if (this.modal === 'none') this.originalHud.hover(p); }
    uiScroll(p: Vec2, delta: number, horizontal = 0) { return this.modal === 'inspect' ? this.cardInspector.wheel(p, delta) : this.modal === 'catalog' ? this.cardCatalog.wheel(p, delta) : this.modal === 'none' && this.originalHud.wheel(p, delta, horizontal); }
    zoom(factor: number, p: Vec2) { if (this.model.battle || this.battleView.restoring) return; const local = this.board.pointerOnPlane(p); this.board.setZoom(this.board.zoom * factor, new Vec2(local.x, local.y)); }
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
        const area = this.board.planeArea({ left: usableLeft, right: usableRight, bottom: usableBottom, top: usableTop });
        const zoom = Math.min(1, (area.right - area.left) / (maxX - minX), (area.top - area.bottom) / (maxY - minY));
        this.board.reset(); this.board.setZoom(zoom);
        this.board.pan(new Vec2((area.left + area.right) / 2 - (minX + maxX) / 2 * this.board.zoom, (area.top + area.bottom) / 2 - (minY + maxY) / 2 * this.board.zoom));
    }
    private drawLinks() {
        const g = this.lineArt; g.clear(); g.lineCap = Graphics.LineCap.ROUND; g.lineJoin = Graphics.LineJoin.ROUND;
        this.supplyRoutes = [];
        this.supplyTransit = [];
        const moving = new Set(this.dragging ? this.movingIds() : []);
        const rectangle = (sid: number): ConnectorRect => {
            const stack = this.model.stack(sid)!, base = stack.cards[0], p = this.views.get(base)?.view.node.position || stack;
            const count = stack.cards.filter(uid => moving.has(uid) === moving.has(base)).length;
            const height = Math.max(0, count - 1) * this.model.stackOffset(sid);
            return { left: p.x - 150, right: p.x + 150, bottom: p.y - 150 - height, top: p.y + 150 };
        };
        const draw = (from: ConnectorRect, to: ConnectorRect, preview = false, reveal = 1) => {
            const route = shortestSupplyRoute(from, to);
            if (!preview) this.supplyRoutes.push(route);
            if (!route.points.length) return;
            const points = roundSupplyRoute(route), length = supplyPathLength(points);
            const travel = length * reveal, tip = supplyPathAt(points, travel);
            g.lineWidth = preview ? 7 : SUPPLY_LINE_WIDTH; g.strokeColor = new Color(38, 42, 34, preview ? 110 : 215); g.fillColor = g.strokeColor;
            if (preview) for (let d = this.supplyClock * 44 % 25; d < travel; d += 25) {
                const from = supplyPathAt(points, d), to = supplyPathAt(points, Math.min(travel, d + 14));
                g.moveTo(from.x, from.y); g.lineTo(to.x, to.y);
            } else {
                g.moveTo(points[0].x, points[0].y);
                for (let d = 4; d < travel; d += 4) {
                    const p = supplyPathAt(points, d), wobble = Math.sin(d * .36) * .45;
                    g.lineTo(p.x - p.ny * wobble, p.y + p.nx * wobble);
                }
                g.lineTo(tip.x, tip.y);
            }
            g.stroke();
            if (travel > SUPPLY_ARROW_LENGTH) {
                g.moveTo(tip.x, tip.y);
                g.lineTo(tip.x - tip.nx * SUPPLY_ARROW_LENGTH - tip.ny * SUPPLY_ARROW_HALF_WIDTH, tip.y - tip.ny * SUPPLY_ARROW_LENGTH + tip.nx * SUPPLY_ARROW_HALF_WIDTH);
                g.lineTo(tip.x - tip.nx * SUPPLY_ARROW_LENGTH + tip.ny * SUPPLY_ARROW_HALF_WIDTH, tip.y - tip.ny * SUPPLY_ARROW_LENGTH - tip.nx * SUPPLY_ARROW_HALF_WIDTH);
                g.close(); g.fill();
            }
        };
        for (const l of this.model.links) {
            const a = this.model.card(l.source), b = this.model.card(l.target); if (!a || !b || a.sid === b.sid) continue;
            const reveal = Math.min(1, (this.supplyClock - (this.linkBirths.get(a.sid + ':' + b.sid) ?? -1)) / .3);
            draw(rectangle(a.sid), rectangle(b.sid), false, reveal);
        }
        for (const d of this.model.deliveries) {
            const source = this.model.card(d.source), target = this.model.card(d.target);
            const savedRect = (p: typeof d.from): ConnectorRect => ({ left: p.x - 150, right: p.x + 150, top: p.y + 150, bottom: p.y - 150 - p.height });
            const from = source ? rectangle(source.sid) : savedRect(d.from), to = target ? rectangle(target.sid) : savedRect(d.to);
            const connected = source && target && this.model.links.some(l => this.model.card(l.source)?.sid === source.sid && this.model.card(l.target)?.sid === target.sid);
            if (!connected) draw(from, to);
            const points = roundSupplyRoute(shortestSupplyRoute(from, to)); if (!points.length) continue;
            const progress = Math.min(1, d.elapsed / d.duration), p = supplyPathAt(points, supplyPathLength(points) * progress);
            this.supplyTransit.push({ source: d.source, target: d.target, id: d.id, progress, x: p.x, y: p.y });
        }
        const anchor = this.model.card(this.supplyAnchor), candidate = this.model.card(this.supplyCandidate);
        if (anchor && candidate && this.supplyDirection) draw(rectangle(this.supplyDirection === 'upstream' ? candidate.sid : anchor.sid), rectangle(this.supplyDirection === 'upstream' ? anchor.sid : candidate.sid), true);
        const frames = new Set<number>();
        if (this.modal === 'none' && !this.dragging) for (const card of [anchor, candidate]) if (card) {
            const base = this.model.stack(card.sid)!.cards[0], view = this.views.get(base)?.view; if (!view) continue; frames.add(base);
            let frame = this.supplyFrames.get(base);
            if (!frame) { const node = this.makeNode('SupplyPreview-' + base, this.board.node, 320, 320); frame = node.addComponent(Graphics); this.supplyFrames.set(base, frame); }
            const p = this.model.position(this.model.card(base)!); frame.node.setPosition(p.x, p.y - this.model.stackHeight(card.sid) / 2);
            frame.node.setSiblingIndex(this.board.node.children.length - 1); view.drawDropHint(frame, this.supplyClock, this.model.stackHeight(card.sid));
        }
        for (const [uid, frame] of this.supplyFrames) if (!frames.has(uid)) { frame.node.destroy(); this.supplyFrames.delete(uid); }
        g.fillColor = new Color(0, 0, 0, 255);
        for (const dot of this.supplyTransit) { g.circle(dot.x, dot.y, 11); g.fill(); }
    }
    private snapshot() {
        const bounds = (n: Node) => {
            const t = n.getComponent(UITransform)!, s = this.metrics.scale;
            const corners = [[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y]) => this.board.projectWorld(t.convertToWorldSpaceAR(new Vec3((x - .5) * t.width, (y - .5) * t.height))));
            const minX = Math.min(...corners.map(p => p.x)), maxX = Math.max(...corners.map(p => p.x)), minY = Math.min(...corners.map(p => p.y)), maxY = Math.max(...corners.map(p => p.y));
            return { x: minX / s, y: (this.metrics.height - maxY) / s, width: (maxX - minX) / s, height: (maxY - minY) / s };
        };
        const m = this.model, founder = m.cards.find(c => c.id === 'founder'), founderView = founder && this.views.get(founder.uid)?.view;
        const basis = (node: Node) => {
            const t = node.getComponent(UITransform)!, project = (x: number, y: number) => this.board.projectWorld(t.convertToWorldSpaceAR(new Vec3(x, y)));
            const o = project(0, 0), x = project(168, 0), y = project(0, 168);
            return { x: { x: x.x - o.x, y: x.y - o.y }, y: { x: y.x - o.x, y: y.y - o.y } };
        };
        return { ready: this.ready && this.pending === 0 && this.originalHud.pending === 0 && this.cardCatalog.pending === 0 && this.cardInspector.pending === 0 && !this.menuBackdrop.snapshot().capturing, error: this.lastError, modal: this.modal, zoom: this.board.zoom, wide: this.metrics.wide, nearSquare: this.metrics.nearSquare, nightShift: this.nightShift,
            page: this.page, pageCount: this.pageCount, card: founderView ? bounds(founderView.node) : null, position: founder ? m.position(founder) : null,
            cards: m.cards.map(c => ({ ...c, name: m.def(c).name, effectiveCapacity: m.employeeCapacity(c), position: m.position(c), bounds: this.views.has(c.uid) ? bounds(this.views.get(c.uid)!.view.node) : null,
                faceBounds: this.views.has(c.uid) ? bounds(this.views.get(c.uid)!.view.frontNode) : null })),
            packs: m.packs.map(p => ({ ...p, bounds: this.views.has(p.uid) ? bounds(this.views.get(p.uid)!.view.node) : null,
                faceBounds: this.views.has(p.uid) ? bounds(this.views.get(p.uid)!.view.frontNode) : null })),
            battle: m.battle ? { ...m.battle, rect: m.battleRect } : null, battlePresentation: this.battleView.snapshot(),
            cash: m.cash, month: m.month, paused: this.gameplayPaused, pauseWash: { active: this.pauseWash.node.active, strength: .3 }, testMode: m.testMode, titleScreen: this.titleScreen.snapshot(), inspector: { ...this.cardInspector.snapshot(), bounds: bounds(this.cardInspector.cardNode), close: bounds(this.cardInspector.closeNode), detailsBounds: bounds(this.cardInspector.detailsNode) }, models: Array.from(m.models), tasks: Array.from(m.completed), notice: m.notice, links: m.links,
            supply: { step: this.supplyStep, subject: this.supplyAnchor, candidate: this.supplyCandidate, direction: this.supplyDirection, message: this.supplyMessage,
                markers: [], deliveries: this.model.deliveries, transit: this.supplyTransit, frames: Array.from(this.supplyFrames.keys()), toast: '',
                connector: { lineWidth: SUPPLY_LINE_WIDTH, arrowLength: SUPPLY_ARROW_LENGTH, cornerRadius: SUPPLY_CORNER_RADIUS, routes: this.supplyRoutes } },
            hint: this.label('Hint').string, hintAttributes: this.label('HintAttributes').string, taskReminder: this.label('TaskReminder').string, taskDrawer: this.originalHud.open, drawerMode: this.originalHud.mode, pitch: this.board.pitch,
            founderSpeech: { ...this.founderSpeech.snapshot(), bounds: bounds(this.founderSpeech.node) },
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
                    const cover = this.controls.get('TopPack:' + id)!.getChildByName('Cover')!, label = cover.getChildByPath('Price/Text')!.getComponent(Label)!;
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
        if (typeof window !== 'undefined') { window.removeEventListener('pagehide', this.flushProgress); window.removeEventListener('beforeunload', this.flushProgress); window.removeEventListener('resize', this.layoutWindow); }
        if (typeof document !== 'undefined') document.removeEventListener('visibilitychange', this.visibilityChanged);
        this.menuBackdrop?.destroy();
        this.cardCatalog?.destroy();
        this.cardInspector?.destroy();
        screen.off('window-resize', this.layout, this); if (typeof document !== 'undefined') document.removeEventListener('contextmenu', this.preventContext);
        if (typeof globalThis !== 'undefined') delete (globalThis as unknown as { __STARTX_SAMPLE__?: () => unknown }).__STARTX_SAMPLE__;
    }
}
