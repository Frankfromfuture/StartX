/** Game rules consume the catalog generated from data/startx_data.xlsx at build time.
 * Positions stay within the finite board; this module has no Cocos dependency.
 */
export interface CardDef {
    name: string; type: string; workTags: string[]; salary: number; capacity: number;
    spaceCapacity: number; value: number; cost: number; workRequired?: number;
    maxUses?: number; maxUsesMin?: number; maxUsesMax?: number; flavor?: string;
    functionText: string; bodyColor: string; recipeId?: string; businessModelId?: string; unlocksRecipeId?: string; funds?: number;
    deadlineSeconds?: number; firstDeadlineSeconds?: number; expiryPenalty?: number;
}
export function quoteFlavor(value?: string) { return value ? '「' + value.replace(/^「|」$/g, '') + '」' : ''; }
export interface Recipe { id: string; name: string; formula: string; packId: string; worker_tags: string[]; effect?: string; workRequired?: number;
    inputs: { id: string; count: number; consume: boolean }[]; outputs: { id: string; count: number; cash?: number }[]; }
export interface PackDef { name: string; price: number; stage: number; minCards: number; maxCards: number; slots: { id: string; w: number }[][]; requiredTasks?: string[]; starterCards?: string[]; }
export interface StageDef { id: string; name: string; requiredTasks: string[]; minMonth: number; minRevenue: number; }
export interface CustomerEvent { id: string; name: string; cardId: string; trigger: string; duration: number; extendSeconds: number; deferredCash: number; message: string; }
export interface TaskDef { id: string; title: string; content: string; section: string; group: string; triggerType: string; targetId: string; targetCount: number; unlockPack: string; }
export interface Catalog { cards: Record<string, CardDef>; recipes: Recipe[]; packs: Record<string, PackDef>; packOrder: string[]; tasks: TaskDef[];
    balance: Record<string, number>; stages?: StageDef[]; events?: CustomerEvent[]; }
export interface BadgePosition { x: number; y: number; }
export const BADGE_SIZE = 70;
/** Coordinates on the 280px face; leave room for the full badge and both number circles. */
export function safeBadgePosition(point: BadgePosition): BadgePosition {
    const x = Math.max(-98, Math.min(98, point.x)), y = Math.max(-98, Math.min(38, point.y));
    if (y < -22 && Math.abs(x) > 22) {
        const side = x < 0 ? -22 : 22;
        return Math.abs(side - x) < -22 - y ? { x: side, y } : { x, y: -22 };
    }
    return { x, y };
}
export interface CardState { uid: number; id: string; sid: number; uses: number; stored: number; elapsed: number; workRequired: number; funds: number;
    deadline?: number; orderNumber?: number; customerEvent?: string; relatedOrder?: number; dueCash?: number; badges?: string[]; badgePositions?: BadgePosition[]; }
export interface Stack { sid: number; cards: number[]; x: number; y: number; }
export interface PackState { uid: number; id: string; contents: string[]; x: number; y: number; opened: boolean; }
export type SoundName = 'grab' | 'founder' | 'down' | 'resource_down' | 'cash_down' | 'unpack' | 'aha' | 'battle_start' | 'battle_end' | 'hit';
export interface Appearance { kind: 'pop' | 'fly' | 'cash' | 'pack'; x: number; y: number; delay: number; landSound?: SoundName; slide?: boolean; startScale?: number; }
export interface CashSpend { uid?: number; from: { x: number; y: number }; to: { x: number; y: number }; targetUid: number; delay: number; }
export interface Production { recipe: Recipe; target: CardState; }
export interface SupplyEndpoint { x: number; y: number; height: number; }
export interface SupplyDelivery { source: number; target: number; id: string; count: number; elapsed: number; duration: number;
    from: SupplyEndpoint; to: SupplyEndpoint; }
export interface Battle {
    id: number; rival: number; employee: number; enemyHp: number; playerHp: number; damage: number;
    rivalTurn: boolean; timer: number; phase: 'entry' | 'outward' | 'return' | 'member-gap' | 'interval';
    center: { x: number; y: number }; attackers: number[]; attacker: number; target: number;
    cashSettled?: boolean;
}
export interface BattleHit { uid: number; amount: number; rivalAttacking: boolean; }
interface StackMotion { x: number; y: number; toX: number; toY: number; time: number; duration: number; }
const STAGES = ['车库', '验证', '产品', '获客', '规模', '融资', '上市'];
const LIMITED = ['p3_large_neighborhood', 'p3_wholesale_city'];
const ALIASES: Record<string, string> = { p3_large_neighborhood: 'p1_neighborhood', p3_wholesale_city: 'p1_wholesale' };
export const CARD_OFFSET = 48;
export const BOARD_CELLS = 30;
export const BOARD_CELL_SIZE = 168;
export const BOARD_HALF = BOARD_CELLS * BOARD_CELL_SIZE / 2;
export const DEFAULT_HINT = '「公司的地板光亮如新，有可能是创始人晚上擦的」';
const PROGRESS_FIELDS = ['cards', 'stacks', 'packs', 'links', 'deliveries', 'counters', 'month', 'monthTime', 'timerStarted', 'revenue',
    'cleanup', 'gameOver', 'paused', 'battle', 'notice', 'noticeVersion', 'revision', 'testMode', 'taskNotices'] as const;
const PROGRESS_SETS = ['discovered', 'models', 'drawn', 'completed', 'unlocked'] as const;
export interface GameProgress {
    version: 1;
    state: Pick<GameModel, typeof PROGRESS_FIELDS[number]>;
    sets: Record<typeof PROGRESS_SETS[number], string[]>;
    sequence: number; maxSpace: number; rivalClock: number;
}

export class GameModel {
    cards: CardState[] = [];
    stacks: Stack[] = [];
    packs: PackState[] = [];
    links: { source: number; target: number }[] = [];
    deliveries: SupplyDelivery[] = [];
    discovered = new Set<string>();
    models = new Set<string>();
    drawn = new Set<string>();
    completed = new Set<string>();
    taskNotices: string[] = [];
    appearances = new Map<number, Appearance>();
    cashSpends: CashSpend[] = [];
    displacements = new Map<number, { x: number; y: number }>();
    soundCues: SoundName[] = [];
    battleHits: BattleHit[] = [];
    defeated = new Set<number>();
    private stackMotions = new Map<number, StackMotion>();
    unlocked = new Set<string>(['garage_pack']);
    counters: Record<string, number> = {};
    month = 1; monthTime: number; timerStarted = false; revenue = 0;
    cleanup = false; gameOver = false; paused = false; heldStack = -1;
    battle: Battle | null = null;
    notice = DEFAULT_HINT; noticeVersion = 0; revision = 0;
    noticeKind: 'hint' | 'operation' = 'hint';
    operationNotice = '';
    private sequence = 1;
    private maxSpace = 0;
    private rivalClock = 0;
    private viewportRatio = 1;
    constructor(public data: Catalog, private random: () => number = Math.random, public testMode = false) {
        this.monthTime = data.balance.month_seconds || 180;
        this.spawn('founder', -180, 60);
        this.packs.push({ uid: this.sequence++, id: 'garage_pack', x: 160, y: 60, opened: false,
            contents: ['p1_office', 'cash', 'cash', 'cash', 'cash', 'cash', 'p1_neighborhood', 'p1_wholesale'] });
        if (testMode) this.seedTestAccount();
        this.event('game_start');
        this.soundCues.length = 0;
    }
    private seedTestAccount() {
        const founder = this.position(this.cards[0]);
        this.spawn('p3_account', founder.x + 340, founder.y - 340).stored = 50;
    }
    saveProgress(paused = this.paused): GameProgress {
        const state = {} as GameProgress['state'], sets = {} as GameProgress['sets'];
        for (const key of PROGRESS_FIELDS) Object.assign(state, { [key]: this[key] });
        for (const key of PROGRESS_SETS) sets[key] = Array.from(this[key]);
        state.paused = paused;
        state.stacks = this.stacks.map(s => { const motion = this.stackMotions.get(s.sid); return { ...s, x: motion?.toX ?? s.x, y: motion?.toY ?? s.y }; });
        return JSON.parse(JSON.stringify({ version: 1, state, sets, sequence: this.sequence, maxSpace: this.maxSpace, rivalClock: this.rivalClock }));
    }
    static fromProgress(data: Catalog, value: unknown, random = Math.random): GameModel | null {
        try {
            const p = value as GameProgress, s = p.state;
            const nonnegative = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n) && n >= 0;
            const id = (n: unknown): n is number => nonnegative(n) && Number.isSafeInteger(n) && n > 0;
            const point = (v: { x: number; y: number }) => Number.isFinite(v.x) && Number.isFinite(v.y);
            if (p.version !== 1 || !s || !p.sets || !id(p.sequence) || !nonnegative(p.maxSpace) || !nonnegative(p.rivalClock)) return null;
            if (!Array.isArray(s.cards) || !Array.isArray(s.stacks) || !Array.isArray(s.packs) || !Array.isArray(s.links)) return null;
            if (!s.cards.every(c => id(c.uid) && id(c.sid) && !!data.cards[c.id] && nonnegative(c.stored) && nonnegative(c.elapsed)
                && nonnegative(c.workRequired) && nonnegative(c.funds) && Number.isInteger(c.uses) && c.uses >= -1
                && [c.deadline, c.orderNumber, c.relatedOrder, c.dueCash].every(v => v === undefined || nonnegative(v))
                && (c.customerEvent === undefined || !!data.events?.some(e => e.id === c.customerEvent))
                && (c.badges === undefined || data.cards[c.id].type === 'employee' && Array.isArray(c.badges)
                    && c.badges.every(badge => data.cards[badge]?.type === 'badge'))
                && (c.badgePositions === undefined || Array.isArray(c.badgePositions) && c.badgePositions.length === c.badges?.length
                    && c.badgePositions.every(p => !!p && point(p))))) return null;
            const cards = new Map(s.cards.map(c => [c.uid, c])), stackIds = new Set(s.stacks.map(v => v.sid)), members = new Set<number>();
            if (cards.size !== s.cards.length || stackIds.size !== s.stacks.length) return null;
            for (const stack of s.stacks) {
                if (!id(stack.sid) || !point(stack) || !Array.isArray(stack.cards) || !stack.cards.length) return null;
                for (const uid of stack.cards) { if (!cards.has(uid) || cards.get(uid)!.sid !== stack.sid || members.has(uid)) return null; members.add(uid); }
            }
            if (members.size !== cards.size || !s.packs.every(v => id(v.uid) && !!data.packs[v.id] && point(v) && typeof v.opened === 'boolean'
                && Array.isArray(v.contents) && v.contents.every(c => !!data.cards[c]))) return null;
            const identities = s.cards.map(c => c.uid).concat(s.stacks.map(v => v.sid), s.packs.map(v => v.uid));
            if (new Set(identities).size !== identities.length || p.sequence <= Math.max(0, ...identities)) return null;
            if (!s.links.every(v => cards.has(v.source) && cards.has(v.target))) return null;
            if (s.deliveries !== undefined && (!Array.isArray(s.deliveries) || !s.deliveries.every(d => d && id(d.source) && id(d.target)
                && !!data.cards[d.id] && id(d.count) && nonnegative(d.elapsed) && nonnegative(d.duration) && d.duration > 0 && d.elapsed <= d.duration
                && d.from && point(d.from) && nonnegative(d.from.height) && d.to && point(d.to) && nonnegative(d.to.height)))) return null;
            if (!PROGRESS_SETS.every(key => Array.isArray(p.sets[key]) && p.sets[key].every(v => typeof v === 'string'))) return null;
            if (!['month', 'monthTime', 'revenue', 'noticeVersion', 'revision'].every(key => nonnegative(s[key as keyof typeof s]))) return null;
            if (!['timerStarted', 'cleanup', 'gameOver', 'paused', 'testMode'].every(key => typeof s[key as keyof typeof s] === 'boolean')) return null;
            if (typeof s.notice !== 'string' || !s.counters || Array.isArray(s.counters) || !Object.values(s.counters).every(nonnegative)
                || !Array.isArray(s.taskNotices) || !s.taskNotices.every(v => typeof v === 'string')) return null;
            const b = s.battle;
            if (b && (!id(b.id) || p.sequence <= b.id || !cards.has(b.rival) || !cards.has(b.employee) || b.attacker !== 0 && !cards.has(b.attacker) || b.target !== 0 && !cards.has(b.target)
                || !point(b.center) || !Array.isArray(b.attackers) || !b.attackers.every(uid => cards.has(uid)) || !nonnegative(b.timer)
                || !nonnegative(b.enemyHp) || !nonnegative(b.playerHp) || !nonnegative(b.damage) || typeof b.rivalTurn !== 'boolean'
                || !['entry', 'outward', 'return', 'member-gap', 'interval'].includes(b.phase))) return null;
            if (b !== null && !b) return null;
            const copy = JSON.parse(JSON.stringify(p)) as GameProgress, model = new GameModel(data, random, s.testMode);
            for (const key of PROGRESS_FIELDS) Object.assign(model, { [key]: copy.state[key] });
            model.deliveries = copy.state.deliveries || [];
            for (const key of PROGRESS_SETS) model[key] = new Set(copy.sets[key]);
            model.sequence = copy.sequence; model.maxSpace = copy.maxSpace; model.rivalClock = copy.rivalClock;
            model.appearances.clear(); model.displacements.clear(); model.soundCues = []; model.cashSpends = []; model.battleHits = [];
            // Old saves used a separate battle HP snapshot. Cash is now the sole player HP ledger.
            if (model.battle) {
                if (!model.battle.cashSettled) model.spend(Math.min(model.cash, Math.floor(model.battle.damage)));
                model.battle.cashSettled = true; model.battle.playerHp = model.cash;
                model.cashSpends = [];
            }
            for (const stack of model.stacks) model.constrainStack(stack);
            model.normalizeLinks();
            return model;
        } catch { return null; }
    }
    def(c: CardState | string) { return this.data.cards[typeof c === 'string' ? c : c.id]; }
    employeeCapacity(c: CardState) { return this.def(c).capacity + (this.def(c).type === 'employee' ? c.badges?.length || 0 : 0); }
    isPassive(c: CardState) { return this.members(c.sid).some(member => this.def(member).type === 'rival'); }
    badgePositionsFor(employee: CardState) {
        return (employee.badges || []).map((_, i) => safeBadgePosition(employee.badgePositions?.[i] || { x: -76 + i % 3 * 76, y: 12 - Math.floor(i / 3) * 18 }));
    }
    attachBadge(badge: CardState, employee: CardState, position: BadgePosition = { x: 0, y: 0 }) {
        if (!this.card(badge.uid) || !this.card(employee.uid) || this.def(badge).type !== 'badge'
            || this.def(employee).type !== 'employee' || this.isCombatant(employee.sid) || this.isPassive(employee)
            || this.members(badge.sid).length !== 1) return false;
        employee.badgePositions = this.badgePositionsFor(employee).concat(safeBadgePosition(position));
        employee.badges = (employee.badges || []).concat(badge.id);
        this.remove(badge); this.soundCues.push('aha');
        this.say(`${this.def(employee).name}贴上${this.def(badge).name}，产能 +1（现为 ${this.employeeCapacity(employee)}）`);
        return true;
    }
    detachBadge(employee: CardState, index: number) {
        if (!this.card(employee.uid) || this.def(employee).type !== 'employee' || this.isCombatant(employee.sid)
            || this.isPassive(employee) || !Number.isInteger(index) || !employee.badges?.[index]) return;
        const positions = this.badgePositionsFor(employee), id = employee.badges[index], origin = this.position(employee);
        const point = this.freePoint(origin.x, origin.y, true), badge = this.spawn(id, point.x, point.y);
        employee.badges.splice(index, 1); positions.splice(index, 1); employee.badgePositions = positions;
        this.soundCues.push('grab'); this.say('已取下' + this.def(badge).name); this.revision++;
        return badge;
    }
    setViewport(width: number, height: number) {
        if (Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0) this.viewportRatio = height / width;
    }
    get verticalFlightChance() { const ratio = this.viewportRatio * this.viewportRatio; return Math.max(.2, Math.min(.8, ratio / (1 + ratio))); }
    dropSound(id: string): SoundName { return id === 'cash' ? 'cash_down' : id === 'founder' ? 'founder' : ['employee', 'customer'].includes(this.def(id).type) ? 'down' : 'resource_down'; }
    card(uid: number) { return this.cards.find(c => c.uid === uid); }
    stack(sid: number) { return this.stacks.find(s => s.sid === sid); }
    members(sid: number) { return (this.stack(sid)?.cards || []).map(uid => this.card(uid)!).filter(Boolean); }
    stackOffset(_sid: number) { return CARD_OFFSET; }
    constrainPoint(x: number, y: number, count = 1, pack = false, held = false) {
        const margin = (pack ? 168 : 140) + (held ? 40 : 12), limit = BOARD_HALF - margin;
        const bottom = -limit + Math.max(0, count - 1) * CARD_OFFSET;
        return { x: Math.max(-limit, Math.min(limit, x)), y: Math.max(bottom, Math.min(limit, y)) };
    }
    private constrainStack(s: Stack, animate = false) {
        const point = this.constrainPoint(s.x, s.y, s.cards.length);
        if (animate && (point.x !== s.x || point.y !== s.y))
            s.cards.forEach((uid, i) => { if (!this.displacements.has(uid)) this.displacements.set(uid, { x: s.x, y: s.y - i * CARD_OFFSET }); });
        Object.assign(s, point);
    }
    stackHeight(sid: number) { return Math.max(0, (this.stack(sid)?.cards.length || 1) - 1) * this.stackOffset(sid); }
    position(c: CardState) { const s = this.stack(c.sid)!; return { x: s.x, y: s.y - s.cards.indexOf(c.uid) * this.stackOffset(s.sid) }; }
    say(text: string, kind: 'hint' | 'operation' = 'operation') {
        this.notice = text; this.noticeVersion++; this.noticeKind = kind;
        if (kind === 'operation') this.operationNotice = text;
    }
    get cash() { return this.cards.reduce((n, c) => n + (c.id === 'cash' ? 1 : c.stored), 0); }
    get capacity() { return this.cards.reduce((n, c) => n + this.def(c).spaceCapacity, 0); }
    get count() { return this.cards.filter(c => c.id !== 'cash').length; }
    get payroll() { return this.cards.reduce((n, c) => n + this.def(c).salary, 0); }
    get valuation() {
        const raw = this.cash + this.revenue * 3 + this.cards.filter(c => this.def(c).type === 'employee').length * 10;
        return Math.floor(raw);
    }
    get stage() {
        let reached = 0;
        for (const [i, stage] of (this.data.stages || []).entries()) {
            if (this.month < stage.minMonth || this.revenue < stage.minRevenue || !stage.requiredTasks.every(t => this.completed.has(t))) break;
            reached = i;
        }
        return reached;
    }
    get stageName() { return this.data.stages?.[this.stage]?.name || STAGES[this.stage]; }
    get supplyLimit() { return this.stage >= 2 ? Math.max(1, this.stage - 1) : 0; }
    integer(min: number, max: number) { return min + Math.floor(this.random() * (max - min + 1)); }
    spawn(id: string, x: number, y: number): CardState {
        if (id === 'founder' && this.cards.some(c => c.id === id)) return this.cards.find(c => c.id === id)!;
        const d = this.def(id); if (!d) throw new Error('Unknown original card: ' + id);
        ({ x, y } = this.constrainPoint(x, y));
        const uid = this.sequence++, sid = this.sequence++;
        const c: CardState = { uid, id, sid, stored: 0, elapsed: 0, workRequired: 0, funds: d.funds ?? d.capacity * 3,
            uses: d.maxUsesMin != null ? this.integer(d.maxUsesMin, d.maxUsesMax!) : d.maxUses ?? -1 };
        this.cards.push(c); this.stacks.push({ sid, cards: [uid], x, y }); this.drawn.add(id);
        this.appearances.set(uid, { kind: 'pop', x, y: y - 24, delay: 0, landSound: id === 'cash' ? 'cash_down' : undefined });
        if (id === 'p1_office' && !this.timerStarted) { this.timerStarted = true; this.monthTime = this.data.balance.month_seconds || 180; }
        if (this.battle) this.battle.playerHp = this.cash;
        this.revision++; return c;
    }
    remove(c: CardState) {
        this.appearances.delete(c.uid);
        this.displacements.delete(c.uid);
        const s = this.stack(c.sid); if (s) s.cards = s.cards.filter(id => id !== c.uid);
        this.cards = this.cards.filter(v => v !== c); this.stacks = this.stacks.filter(v => v.cards.length);
        this.links = this.links.filter(l => l.source !== c.uid && l.target !== c.uid); this.revision++;
    }
    private freePoint(x: number, y: number, upperLeft = false, count = 1) {
        for (let radius = 1; radius <= 20; radius++) {
            const offsets = upperLeft ? [[-radius, radius], [-radius, radius + 1], [-radius - 1, radius], [-radius, radius * 2], [-radius * 2, radius]] : [[-radius, -1], [0, -radius], [-radius, 0], [radius, -1], [radius, 0], [0, radius], [-radius, radius], [radius, radius]];
            for (const [dx, dy] of offsets) {
                const p = this.constrainPoint(x + dx * 322, y + dy * 340, count);
                if (this.stacks.every(s => Math.abs(s.x - p.x) > 295 || Math.abs(s.y - p.y) > 300 + this.stackHeight(s.sid))
                    && this.packs.every(s => Math.abs(s.x - p.x) > 320 || Math.abs(s.y - p.y) > 330)) return p;
            }
        }
        return this.constrainPoint(x + (upperLeft ? -1 : 1) * this.sequence * 24, y + (upperLeft ? 700 : -700), count);
    }
    private flightPoint(x: number, y: number) {
        // Choose the bearing once, then search outwards without changing its probability.
        const vertical = this.random() < this.verticalFlightChance, sign = this.random() < .5 ? -1 : 1, drift = (this.random() * 2 - 1) * .4;
        const dx = vertical ? drift : sign, dy = vertical ? sign : drift;
        for (let radius = 1; radius <= 40; radius++) {
            const p = this.constrainPoint(x + dx * 322 * radius, y + dy * 340 * radius);
            if (this.stacks.every(s => Math.abs(s.x - p.x) > 295 || Math.abs(s.y - p.y) > 300 + this.stackHeight(s.sid))
                && this.packs.every(s => Math.abs(s.x - p.x) > 320 || Math.abs(s.y - p.y) > 330)) return p;
        }
        return this.freePoint(x, y);
    }
    merge(from: number, to: number) {
        const a = this.stack(from), b = this.stack(to); if (!a || !b || a === b) return to;
        if (this.members(from).concat(this.members(to)).some(c => ['rival', 'badge'].includes(this.def(c).type))) return from;
        const cards = b.cards.concat(a.cards), maxCards = Math.floor((BOARD_HALF * 2 - 360) / CARD_OFFSET) + 1;
        const sid = this.sequence++; const merged = { sid, cards: cards.slice(0, maxCards), x: b.x, y: b.y };
        this.constrainStack(merged, true);
        this.stacks = this.stacks.filter(s => s !== a && s !== b); this.stacks.push(merged);
        merged.cards.forEach(uid => { this.card(uid)!.sid = sid; });
        if (cards.length > maxCards) {
            const rest = cards.slice(maxCards), point = this.freePoint(b.x, b.y, false, rest.length);
            const overflow = { sid: this.sequence++, cards: rest, x: point.x, y: point.y };
            this.stacks.push(overflow); rest.forEach(uid => { this.card(uid)!.sid = overflow.sid; });
        }
        const order = this.members(sid).find(c => this.def(c).type === 'order' && !c.orderNumber);
        if (order && this.members(sid).some(c => this.def(c).type === 'product')) this.acceptOrder(order);
        this.normalizeLinks();
        this.revision++; return sid;
    }
    move(uid: number, x: number, y: number, targetUid?: number, badgePosition?: BadgePosition) {
        const c = this.card(uid); if (!c || this.isCombatant(c.sid) || this.isPassive(c)) return;
        const droppedOn = targetUid ? this.card(targetUid) : undefined;
        if (droppedOn && this.isPassive(droppedOn)) return;
        if (this.def(c).type === 'badge' && droppedOn && droppedOn.uid !== uid) {
            const origin = this.position(droppedOn);
            if (!this.attachBadge(c, droppedOn, badgePosition || { x: x - origin.x, y: y - origin.y })) this.say('毛线徽章只能贴在员工卡上');
            return;
        }
        if (droppedOn && this.def(droppedOn).type === 'badge') return;
        this.stackMotions.delete(c.sid);
        let s = this.stack(c.sid)!; const index = s.cards.indexOf(uid);
        if (index > 0) {
            const part = s.cards.splice(index), sid = this.sequence++;
            this.constrainStack(s);
            s = { sid, cards: part, x, y }; this.stacks.push(s); part.forEach(id => { this.card(id)!.sid = sid; });
        } else { s.x = x; s.y = y; }
        this.constrainStack(s, true);
        const target = targetUid ? this.card(targetUid) : undefined;
        if (target && target.sid !== s.sid) {
            if (this.battle && target.sid === this.card(this.battle.employee)?.sid && this.members(s.sid).every(v => this.def(v).type === 'employee')) this.merge(s.sid, target.sid);
            else if (this.canInteractCards(this.members(s.sid), this.members(target.sid))) {
                const account = this.members(target.sid).find(v => v.id === 'p3_account');
                if (account && this.members(s.sid).every(v => v.id === 'cash')) {
                    const amount = Math.min(50 - account.stored, s.cards.length);
                    if (amount > 0) this.members(s.sid).slice(-amount).forEach(v => this.remove(v));
                    account.stored += amount; this.say(`存入 ${amount} 个现金，账户余额 ${account.stored}/50`);
                    if (this.stack(s.sid)) this.stack(s.sid)!.x += 300;
                } else this.merge(s.sid, target.sid);
            } else {
                // Original non-interacting stacks separate on drop.
                const b = this.stack(target.sid)!;
                if (this.isCombatant(b.sid)) { this.pushOutsideBattle(s); this.revision++; return; }
                for (const member of this.members(b.sid)) this.displacements.set(member.uid, this.position(member));
                const p = this.freePoint(b.x, b.y, false, b.cards.length); b.x = p.x; b.y = p.y;
            }
        }
        if (this.battle && !this.isCombatant(s.sid) && this.stack(s.sid)) this.pushOutsideBattle(s);
        if (this.stack(s.sid)) this.constrainStack(s, true);
        this.revision++;
    }
    private countId(id: string) { return ALIASES[id] || id; }
    private counts(arr: CardState[]) { const n: Record<string, number> = {}; arr.forEach(c => { const id = this.countId(c.id); n[id] = (n[id] || 0) + 1; }); return n; }
    matches(r: Recipe, arr: CardState[]) {
        const counts = this.counts(arr); if (r.inputs.some(i => (counts[i.id] || 0) < i.count)) return false;
        const reserved: Record<string, number> = {};
        r.inputs.filter(i => i.consume && this.def(i.id).type === 'employee').forEach(i => { reserved[i.id] = (reserved[i.id] || 0) + i.count; });
        const workers = arr.filter(c => { if (this.def(c).type !== 'employee') return false; if (reserved[c.id] > 0) { reserved[c.id]--; return false; } return true; });
        return !r.worker_tags.length || r.worker_tags.some(t => t === 'any' ? workers.length > 0 : workers.some(c => this.def(c).workTags.includes(t)));
    }
    private partial(arr: CardState[]) {
        const counts = this.counts(arr);
        return this.data.recipes.some(r => {
            const needs: Record<string, number> = {}; r.inputs.forEach(i => { needs[i.id] = (needs[i.id] || 0) + i.count; });
            return Object.keys(counts).length > 0 && Object.keys(counts).every(id => needs[id] != null ? (this.def(id).type === 'order' ? 1 : counts[id]) <= needs[id] :
                arr.some(c => c.id === id && this.def(c).type === 'employee' && r.worker_tags.some(t => t === 'any' || this.def(c).workTags.includes(t))));
        });
    }
    interacts(a: CardState[], b: CardState[]) {
        const arr = a.concat(b); if (!arr.length) return false;
        if (arr.some(c => ['rival', 'badge'].includes(this.def(c).type))) return false;
        if (a.every(c => c.id === 'cash') && b.some(c => c.id === 'p3_account') || b.every(c => c.id === 'cash') && a.some(c => c.id === 'p3_account')) return true;
        if (arr.every(c => this.def(c).type === 'employee')) return true;
        if (arr.every(c => c.id === arr[0].id && !['employee', 'department', 'risk', 'idea'].includes(this.def(c).type))) return true;
        return this.partial(arr) || this.data.recipes.some(r => this.matches(r, arr));
    }
    canInteract(uid: number, targetUid: number) {
        const source = this.card(uid), target = this.card(targetUid); if (!source || !target) return false;
        if (this.isPassive(source) || this.isPassive(target)) return false;
        if (this.def(source).type === 'badge') return source.uid !== target.uid && this.members(source.sid).length === 1
            && this.def(target).type === 'employee' && !this.isCombatant(target.sid);
        const moving = this.members(source.sid).slice(this.stack(source.sid)!.cards.indexOf(uid)), ids = new Set(moving.map(c => c.uid));
        return this.canInteractCards(moving, this.members(target.sid).filter(c => !ids.has(c.uid)));
    }
    private canInteractCards(a: CardState[], b: CardState[]) {
        if (!a.length || !b.length || a.some(c => this.isCombatant(c.sid))) return false;
        if (a.concat(b).some(c => this.def(c).type === 'rival')) return false;
        if (this.battle && b[0].sid === this.card(this.battle.employee)?.sid && a.every(c => this.def(c).type === 'employee')) return true;
        if (this.isCombatant(b[0].sid) || !this.interacts(a, b)) return false;
        const account = b.find(c => c.id === 'p3_account');
        return !(account && a.every(c => c.id === 'cash') && account.stored >= 50);
    }
    production(sid: number): Production | undefined {
        if (sid === this.heldStack || this.isCombatant(sid)) return;
        const arr = this.members(sid); if (!arr.length) return;
        const recipe = this.data.recipes.find(r => this.matches(r, arr));
        if (!recipe || recipe.outputs.some(o => LIMITED.includes(o.id) && this.cards.filter(c => c.id === o.id).length >= this.supplyLimit)) return;
        if (recipe.effect === 'deliver_order' && !arr.some(c => this.def(c).type === 'order' && c.orderNumber && (c.deadline || 0) > 0)) return;
        const target = (recipe.effect === 'deliver_order' ? arr.find(c => this.def(c).type === 'order' && c.orderNumber) : undefined)
            || arr.find(c => c.id === recipe.inputs[0]?.id) || arr.find(c => this.def(c).type !== 'employee') || arr[0];
        return { recipe, target };
    }
    stackCapacity(sid: number) {
        const seen = new Set<string>(); let cap = 0;
        for (const c of this.members(sid)) { const d = this.def(c); if (!['employee', 'tool', 'product'].includes(d.type) || seen.has(d.type)) continue;
            seen.add(d.type); cap += d.type === 'employee' ? this.employeeCapacity(c) : d.value; }
        return cap;
    }
    speed(sid: number) { return Math.max(1, this.stackCapacity(sid)); }
    required(r: Recipe) { return r.workRequired || r.outputs.map(o => this.def(o.id)?.workRequired || 0).find(n => n > 0) || 1; }
    cashOutput(_r: Recipe, amount: number) { return amount; }
    private output(id: string, amount: number, x: number, y: number, target?: CardState, slide = false) {
        if (!amount) return;
        let p = slide ? this.freePoint(x, y, true) : this.flightPoint(x, y);
        let same = slide ? undefined : this.cards.find(c => c.id === id && Math.hypot(this.position(c).x - p.x, this.position(c).y - p.y) < 560);
        for (let i = 0; i < amount; i++) {
            // Keep every sale cash destination above the icon, including a large sale.
            if (slide && same && this.members(same.sid).length >= 5) { same = undefined; p = this.freePoint(x, y, true); }
            const made = this.spawn(id, p.x, p.y);
            this.appearances.set(made.uid, { kind: id === 'cash' ? 'cash' : 'pop', x, y, delay: i * .05,
                landSound: this.dropSound(id), slide });
            if (target && this.card(target.uid) && this.acceptsOutput(id, target.sid)) this.merge(made.sid, target.sid);
            else if (same && this.card(same.uid)) this.merge(made.sid, same.sid);
            else same = made;
        }
    }
    private complete(s: Stack, p: Production) {
        const r = p.recipe, arr = this.members(s.sid), founder = arr.some(c => c.id === 'founder');
        const order = r.effect === 'deliver_order' ? arr.find(c => this.def(c).type === 'order' && c.orderNumber) : undefined;
        const eventCard = arr.find(c => c.customerEvent && this.def(c).type !== 'order');
        const customerEvent = this.data.events?.find(e => e.id === (order?.customerEvent || eventCard?.customerEvent));
        // Every recipe yield comes from Excel. Capacity changes time, never secretly duplicates products.
        const deferred = order && customerEvent?.deferredCash ? Math.min(customerEvent.deferredCash, r.outputs.filter(o => o.id === 'cash').reduce((n, o) => n + o.count, 0)) : 0;
        const targets = this.links.filter(l => this.card(l.source)?.sid === s.sid).map(l => this.card(l.target)).filter((c): c is CardState => !!c);
        const source = s.cards[0], from = { x: s.x, y: s.y, height: this.stackHeight(s.sid) };
        const deliver = (id: string, count: number, target?: CardState) => {
            if (!count) return;
            if (target) {
                const stack = this.stack(target.sid)!, to = { x: stack.x, y: stack.y, height: this.stackHeight(stack.sid) };
                this.deliveries.push({ source, target: target.uid, id, count, elapsed: 0,
                    duration: Math.max(.5, Math.min(1.6, (Math.abs(from.x - to.x) + Math.abs(from.y - to.y)) / 1000)), from, to });
            } else {
                this.output(id, count, s.x, s.y);
                if (id === 'cash') this.revenue += count; else this.event('card_produced', id, count);
            }
        };
        for (const input of r.inputs) if (input.consume && input.id !== 'p3_bank') {
            const used = order?.id === input.id ? [order] : arr.filter(c => c.id === input.id).slice(0, input.count);
            used.forEach(c => this.remove(c));
        }
        let routed = false;
        for (const o of r.outputs) {
            const target = targets.find(c => !this.isCombatant(c.sid) && this.acceptsOutput(o.id, c.sid));
            if (target) routed = true;
            if (o.id === 'cash' || o.cash != null) {
                const n = r.effect === 'collect_payment' && eventCard?.dueCash !== undefined ? eventCard.dueCash : this.cashOutput(r, o.cash ?? o.count) - deferred;
                deliver('cash', n, target);
            } else deliver(o.id, o.count, target);
        }
        if (routed) this.event('supply_production');
        for (const i of r.inputs) if (!i.consume && i.id !== 'p3_bank') {
            const node = this.members(s.sid).find(c => c.id === i.id && c.uses >= 0);
            if (node && --node.uses <= 0) { this.say(this.def(node).name + ' 已耗尽'); this.remove(node); }
        }
        this.models.add(r.id);
        if (!this.discovered.has(r.id)) { this.discovered.add(r.id); this.say(`新发现：${r.name}`); }
        this.event('recipe_complete', r.id); if (founder) this.event('founder_recipe', r.id);
        if (order) {
            this.event('order_completed');
            for (const extra of this.cards.filter(c => c.relatedOrder === order.uid && c.id === 'p4_change')) this.remove(extra);
            if (customerEvent?.trigger === 'delivered') this.createCustomerEvent(customerEvent, order, s.x, s.y, deferred);
            else this.say(`按期交付！收到 $${r.outputs.filter(o => o.id === 'cash').reduce((n, o) => n + o.count, 0)}`);
        } else if (eventCard) {
            if (r.effect === 'accept_change') {
                const original = this.card(eventCard.relatedOrder || 0);
                if (original?.deadline !== undefined) original.deadline += customerEvent?.extendSeconds || 0;
                this.say(`加单完成，额外收到 $${r.outputs.filter(o => o.id === 'cash').reduce((n, o) => n + o.count, 0)}，原订单延长 ${customerEvent?.extendSeconds || 0} 秒`);
            } else if (r.effect === 'decline_change') this.say('合同摊开，客户收回了“就改一点点”。原订单照常。');
            else if (r.effect === 'collect_payment') this.say(`尾款 $${eventCard.dueCash ?? r.outputs.find(o => o.id === 'cash')?.count ?? 0} 已到账，流程终于走到了。`);
            else if (r.effect === 'resolve_referral') this.say('老客户带来了新订单，准备好再点击接单。');
            this.event('customer_event_resolved', eventCard.customerEvent || '');
        }
        this.checkProductionState();
        p.target.elapsed = 0; p.target.workRequired = 0; this.revision++;
    }
    private checkProductionState() {
        if (['p2_sales_specialist', 'p2_product_specialist', 'p2_admin_specialist'].every(id => this.cards.some(c => c.id === id))) this.event('card_state', 'specialists_all');
        if (this.capacity > this.maxSpace) { this.maxSpace = this.capacity; this.event('space_increased'); }
    }
    private updateDeliveries(dt: number) {
        this.deliveries = this.deliveries.filter(d => {
            d.elapsed = Math.min(d.duration, d.elapsed + dt);
            const target = this.card(d.target);
            if (d.elapsed < d.duration || target && this.isCombatant(target.sid)) return true;
            const point = target ? this.position(target) : d.to;
            this.output(d.id, d.count, point.x, point.y, target);
            if (d.id === 'cash') this.revenue += d.count; else this.event('card_produced', d.id, d.count);
            this.checkProductionState(); this.revision++; return false;
        });
    }
    update(dt: number) {
        if (this.paused || this.gameOver) return;
        if (this.cleanup) { if (this.count <= this.capacity) this.finishMonth(); return; }
        this.updateStackMotions(dt);
        this.updateRivals(dt);
        this.updateBattle(dt);
        if (this.gameOver) return;
        this.updateDeliveries(dt);
        for (const s of this.stacks.slice()) {
            const p = this.production(s.sid); if (!p) continue;
            p.target.workRequired = this.required(p.recipe); p.target.elapsed += dt * this.speed(s.sid);
            if (p.target.elapsed >= p.target.workRequired) this.complete(s, p);
        }
        this.updateCustomerCards(dt);
        if (this.timerStarted) { this.monthTime -= dt; if (this.monthTime <= 0) {
            this.monthTime = 0;
            if (this.count > this.capacity) { this.cleanup = true; this.say(`空间超出 ${this.count - this.capacity} 张，请出售卡牌或解雇员工后结算`); }
            else this.finishMonth();
        } }
        if (this.battle) this.battle.playerHp = this.cash;
    }
    private orderTerms(card: CardState) {
        const recipe = this.data.recipes.find(r => r.effect === 'deliver_order' && r.inputs.some(i => i.id === card.id));
        const goods = recipe?.inputs.filter(i => this.def(i.id).type === 'product') || [];
        return { count: goods.reduce((n, i) => n + i.count, 0),
            label: goods.map(i => `${this.def(i.id).name}×${i.count}`).join('＋'),
            cash: recipe?.outputs.filter(o => o.id === 'cash').reduce((n, o) => n + o.count, 0) || 0 };
    }
    acceptOrder(card: CardState) {
        if (this.def(card).type !== 'order' || card.orderNumber || this.gameOver || this.cleanup) return false;
        if (this.cards.some(c => this.def(c).type === 'order' && c.orderNumber)) { this.say('先交付手头这一单，再接下一单。'); return false; }
        this.event('order_accepted'); card.orderNumber = this.counters['order_accepted|'];
        card.deadline = card.orderNumber === 1 ? this.def(card).firstDeadlineSeconds || 180 : this.def(card).deadlineSeconds || 120;
        const events = this.data.events || [], e = card.orderNumber > 1 ? events[(card.orderNumber - 2) % events.length] : undefined;
        if (e) card.customerEvent = e.id;
        const terms = this.orderTerms(card);
        this.say(`已接单：${Math.ceil(card.deadline)} 秒内交付${terms.label}，回款 $${terms.cash}${card.orderNumber === 1 ? '；首单逾期免罚' : '；逾期扣 $' + (this.def(card).expiryPenalty || 0)}`);
        if (e?.trigger === 'accepted') { const pos = this.position(card); this.createCustomerEvent(e, card, pos.x, pos.y); }
        this.revision++; return true;
    }
    private createCustomerEvent(event: CustomerEvent, order: CardState, x: number, y: number, dueCash = 0) {
        const point = this.flightPoint(x, y), c = this.spawn(event.cardId, point.x, point.y);
        c.customerEvent = event.id; c.relatedOrder = order.uid; c.deadline = event.duration;
        if (dueCash) c.dueCash = dueCash;
        this.say(event.message); this.event('customer_event_seen', event.id);
    }
    private updateCustomerCards(dt: number) {
        for (const c of this.cards.slice()) {
            if (!this.card(c.uid) || c.deadline === undefined) continue;
            c.deadline = Math.max(0, c.deadline - dt);
            if (c.deadline > 1e-6) continue;
            const point = this.position(c), isOrder = this.def(c).type === 'order';
            if (isOrder) {
                const penalty = c.orderNumber === 1 ? 0 : Math.min(this.cash, this.def(c).expiryPenalty || 0);
                this.spend(penalty); this.event('order_failed');
                for (const extra of this.cards.filter(e => e.relatedOrder === c.uid && e.id === 'p4_change')) this.remove(extra);
                this.say(penalty ? `订单超时，赔付 $${penalty}；产品保留，可以继续零售。` : '首单超时，本次免罚；产品保留，准备好再接单。');
            } else if (c.dueCash !== undefined) {
                this.output('cash', c.dueCash, point.x, point.y); this.revenue += c.dueCash;
                this.event('customer_event_resolved', c.customerEvent || ''); this.say(`尾款 $${c.dueCash} 已自动到账。`);
            } else this.say(c.id === 'p4_change' ? '客户收回了加单，原订单继续。' : '朋友等不及先走了，下次早点接待。');
            this.remove(c);
        }
    }
    cardStatus(c: CardState) {
        if (this.def(c).type === 'order') { const terms = this.orderTerms(c); return c.orderNumber ? `交货 ${Math.ceil(c.deadline || 0)}s · ${terms.count} 件` : `点击接单 · ${terms.count} 件 / $${terms.cash}`; }
        if (c.deadline !== undefined) return `${c.id === 'p4_receivable' ? '回款' : c.id === 'p4_change' ? '加单' : '接待'} ${Math.ceil(c.deadline)}s`;
        return '';
    }
    private finishMonth() {
        this.cleanup = false;
        if (!this.spend(this.payroll, this.cards.filter(c => this.def(c).salary > 0))) { this.gameOver = true; this.say(`现金不足以支付本月工资 $${this.payroll}，资金链断裂`); return; }
        this.month++; this.monthTime = this.data.balance.month_seconds || 180; this.say(`进入第 ${this.month} 月`);
    }
    spend(amount: number, targets: CardState[] = []) {
        if (!Number.isSafeInteger(amount) || amount < 0) return false;
        if (amount > this.cash) return false;
        let index = 0;
        const animate = (from: { x: number; y: number }, uid?: number) => {
            if (!targets.length) return;
            const target = targets[index % targets.length];
            this.cashSpends.push({ uid, from, to: this.position(target), targetUid: target.uid, delay: .05 * index++ });
        };
        const loose = this.cards.filter(c => c.id === 'cash').sort((a, b) => this.stack(b.sid)!.cards.indexOf(b.uid) - this.stack(a.sid)!.cards.indexOf(a.uid));
        const accounts = this.cards.filter(c => c.stored > 0);
        for (const c of loose.concat(accounts)) {
            if (amount <= 0) break;
            if (c.id === 'cash') { animate(this.position(c), c.uid); this.remove(c); amount--; }
            else {
                const n = Math.min(amount, c.stored); c.stored -= n; amount -= n;
                for (let i = 0; i < n; i++) animate(this.position(c));
            }
        }
        if (this.battle) this.battle.playerHp = this.cash;
        this.revision++; return true;
    }
    withdraw(c: CardState) { const n = Math.min(5, c.stored); c.stored -= n; const p = this.position(c); this.output('cash', n, p.x, p.y); this.say(n ? `取出 ${n} 个现金，余额 ${c.stored}/50` : '账户中没有现金'); }
    canSell(sid: number) {
        return this.canSellCards(this.members(sid));
    }
    canSellCards(arr: CardState[]) {
        if (!arr.length || arr.some(c => this.isCombatant(c.sid) || this.isPassive(c))) return false;
        if (arr.every(c => this.def(c).type === 'order' && !c.orderNumber)) return true;
        if (arr.some(c => c.orderNumber || c.customerEvent)) return false;
        if (arr.every(c => c.id !== 'founder' && this.def(c).type === 'employee')) return true;
        if (arr.every(c => c.id === 'p2_document')) return true;
        if (this.cleanup) return arr.every(c => this.def(c).type !== 'employee' && (this.def(c).value > 0 || c.id === 'p2_document'));
        return arr.every(c => !['facility', 'employee', 'resource'].includes(this.def(c).type)) && arr.reduce((n, c) => n + this.def(c).value, 0) > 0;
    }
    sell(sid: number, origin?: { x: number; y: number }) {
        if (!this.canSell(sid)) { this.say('这组卡牌当前无法出售'); return; }
        const s = this.stack(sid)!, arr = this.members(sid), firing = arr.every(c => this.def(c).type === 'employee');
        const value = arr.reduce((n, c) => n + (c.id === 'p2_document' ? 0 : this.def(c).value), 0); arr.forEach(c => this.remove(c));
        if (!firing) { if (value > 0) this.output('cash', value, origin?.x ?? s.x, origin?.y ?? s.y, undefined, !!origin); this.event('card_sold'); }
        this.say(firing ? `已免费解雇 ${arr.length} 名员工` : value > 0 ? `出售获得 $${value}` : arr.every(c => c.id === 'p2_document') ? '已回收文书（无现金收益）' : '已回收');
    }
    event(trigger: string, target = '', amount = 1) {
        const key = trigger + '|' + target; this.counters[key] = trigger === 'supply_nodes' ? Math.max(this.counters[key] || 0, amount) : (this.counters[key] || 0) + amount;
        if (target) this.counters[trigger + '|'] = (this.counters[trigger + '|'] || 0) + amount;
        for (const t of this.data.tasks) if (!this.completed.has(t.id) && t.triggerType === trigger && (!t.targetId || t.targetId === target)
            && (this.counters[trigger + '|' + t.targetId] || 0) >= t.targetCount) {
            this.completed.add(t.id); if (t.unlockPack) this.unlocked.add(t.unlockPack);
            this.taskNotices.push(`已完成 ${t.title}！`);
            this.soundCues.push('aha');
        }
    }
    packUnlocked(id: string) { const p = this.data.packs[id]; return !!p && (this.testMode || this.stage >= p.stage && (p.requiredTasks || []).every(t => this.completed.has(t))); }
    get flashPackCharges() { return this.data.packOrder.filter(id => this.packUnlocked(id) && !this.counters['flash_pack_claimed|' + id]).length; }
    openFlashPack(x: number, y: number, from = { x, y }) {
        if (this.gameOver || this.cleanup) return;
        const source = this.data.packOrder.find(id => this.packUnlocked(id) && !this.counters['flash_pack_claimed|' + id]);
        if (!source) { this.say('解锁下一个卡包，即可激活奖励礼包'); return; }
        const badges = Object.keys(this.data.cards).filter(id => this.data.cards[id].type === 'badge');
        if (!badges.length) return;
        const id = badges[this.integer(0, badges.length - 1)], point = this.freePoint(x, y, true);
        const card = this.spawn(id, point.x, point.y);
        this.counters['flash_pack_claimed|' + source] = 1;
        this.appearances.set(card.uid, { kind: 'fly', x: from.x, y: from.y, delay: 0, slide: true });
        this.soundCues.push('unpack'); this.say('获得' + this.def(card).name); this.revision++;
        return card;
    }
    packRequirement(id: string) {
        const p = this.data.packs[id]; if (!p) return '';
        const stages = (this.data.stages || []).slice(0, p.stage + 1);
        const tasks = Array.from(new Set(stages.reduce((all, s) => all.concat(s.requiredTasks), [] as string[]).concat(p.requiredTasks || []))).filter(t => !this.completed.has(t));
        const conditions = tasks.map(id => this.data.tasks.find(t => t.id === id)?.title || id);
        const month = Math.max(1, ...stages.map(s => s.minMonth)), revenue = Math.max(0, ...stages.map(s => s.minRevenue));
        if (this.month < month) conditions.push(`第 ${month} 月`);
        if (this.revenue < revenue) conditions.push(`累计回款 $${revenue}（${this.revenue}/${revenue}）`);
        return conditions.length ? '需要：' + conditions.join('、') : '已解锁';
    }
    private optionIds(id: string) { return Array.from(new Set((this.data.packs[id]?.slots || []).reduce((a, s) => a.concat(s.map(o => o.id)), [] as string[]))); }
    private basic(id: string) { return id !== 'founder' && !['business_model', 'rival'].includes(this.def(id).type) && !this.data.recipes.some(r => r.outputs.some(o => o.id === id)); }
    private reserved(id: string, picked: string[] = []) { return this.cards.filter(c => c.id === id).length + this.packs.reduce((n, p) => n + p.contents.filter(c => c === id).length, 0) + picked.filter(c => c === id).length; }
    private eligible(id: string, pack: string, picked: string[]) {
        const d = this.def(id); if (!d) return false;
        if (id === 'founder' && (pack !== 'garage_pack' || this.reserved(id, picked))) return false;
        if (id === 'p3_bank' && this.reserved(id, picked)) return false;
        if (LIMITED.includes(id) && this.reserved(id, picked) >= this.supplyLimit) return false;
        if (d.type === 'facility' && this.reserved(id, picked)) return false;
        if (d.type === 'business_model') { const rid = id.replace(/^bm_/, ''); return !this.models.has(rid) && !this.reserved(id, picked) && this.data.recipes.find(r => r.id === rid)?.packId === pack; }
        return true;
    }
    cardPacks(id: string) {
        if (id === 'founder') return [];
        if (this.def(id).type === 'business_model') return this.data.packOrder.filter(pack => this.data.recipes.some(r => 'bm_' + r.id === id && r.packId === pack));
        return this.data.packOrder.filter(pack => this.optionIds(pack).concat(this.data.packs[pack].starterCards || []).includes(id));
    }
    generatePack(id: string) {
        const pack = this.data.packs[id], picked: string[] = [], target = this.integer(pack.minCards, pack.maxCards);
        if (!(this.counters['pack_bought|' + id] > 0)) for (const card of pack.starterCards || []) {
            if (this.eligible(card, id, picked)) picked.push(card);
        }
        for (let n = picked.length; n < target; n++) {
            const slot = pack.slots[n % pack.slots.length] || [];
            let options = slot.filter(o => this.eligible(o.id, id, picked));
            if (!options.length) options = pack.slots.reduce((all, s) => all.concat(s), []).filter(o => this.eligible(o.id, id, picked));
            let draw = this.integer(1, options.reduce((v, o) => v + o.w, 0) || 1);
            for (const option of options) { draw -= option.w; if (draw <= 0) { picked.push(option.id); break; } }
        }
        if (this.random() < .5) {
            const models = this.data.recipes.filter(r => r.packId === id).map(r => 'bm_' + r.id).filter(c => this.eligible(c, id, picked));
            if (models.length) picked.push(models[this.integer(0, models.length - 1)]);
        }
        return picked;
    }
    private packPoint(x: number, y: number) {
        ({ x, y } = this.constrainPoint(x, y, 1, true));
        const occupied = this.cards.map(c => ({ ...this.position(c), half: 140 })).concat(this.packs.map(p => ({ x: p.x, y: p.y, half: 168 })));
        const clear = (px: number, py: number) => occupied.every(p => Math.abs(px - p.x) >= 168 + p.half + 16 || Math.abs(py - p.y) >= 168 + p.half + 16);
        if (clear(x, y)) return { x, y };
        // Search the finite board, then keep a crowded-board fallback in bounds.
        for (let radius = 1; radius <= Math.ceil(BOARD_HALF * 2 / 352); radius++) {
            const offsets: { x: number; y: number }[] = [];
            for (let i = -radius; i <= radius; i++) {
                offsets.push({ x: i, y: -radius }, { x: i, y: radius });
                if (Math.abs(i) < radius) offsets.push({ x: -radius, y: i }, { x: radius, y: i });
            }
            offsets.sort((a, b) => a.x * a.x + a.y * a.y - b.x * b.x - b.y * b.y || a.y - b.y);
            for (const offset of offsets) {
                const point = this.constrainPoint(x + offset.x * 352, y + offset.y * 352, 1, true);
                if (clear(point.x, point.y)) return point;
            }
        }
        return { x, y };
    }
    buyPack(id: string, x: number, y: number, from: { x: number; y: number; startScale?: number } = { x, y }) {
        if (this.gameOver || this.cleanup) return;
        const d = this.data.packs[id]; if (!this.packUnlocked(id)) { this.say(this.packRequirement(id)); return; }
        if (this.cash < d.price) { this.say(`购买${d.name}需要 $${d.price}`); return; }
        const contents = this.generatePack(id); if (!contents.length) { this.say('当前卡包没有可抽取的卡牌'); return; }
        this.spend(d.price); this.event('pack_bought', id); const uid = this.sequence++, point = this.packPoint(x, y);
        this.packs.push({ uid, id, x: point.x, y: point.y, contents, opened: false });
        this.appearances.set(uid, { kind: 'pack', x: from.x, y: from.y, delay: 0, slide: true, startScale: from.startScale });
        this.say('点击新卡包，逐张拆开'); this.revision++;
    }
    openPack(uid: number) {
        if (this.gameOver || this.cleanup) return;
        const p = this.packs.find(p => p.uid === uid); if (!p) return;
        if (!p.opened) { p.opened = true; this.event('pack_opened', p.id); }
        this.soundCues.push('unpack');
        let cashCount = 0; for (const id of p.contents) { if (id !== 'cash') break; cashCount++; }
        if (p.id === 'garage_pack' && cashCount >= 5) {
            p.contents.splice(0, cashCount); const before = new Set(this.cards.map(c => c.uid));
            this.output('cash', cashCount, p.x, p.y);
            this.cards.filter(c => !before.has(c.uid)).forEach((c, i) => this.appearances.set(c.uid, { kind: 'cash', x: p.x, y: p.y, delay: .075 * i, landSound: 'cash_down' }));
        }
        else {
            let id = p.contents.shift();
            while (id && (id === 'founder' && this.cards.some(c => c.id === id) || id.startsWith('bm_') && this.models.has(id.slice(3)))) id = p.contents.shift();
            if (id) {
                if (id.startsWith('bm_')) this.models.add(id.slice(3));
                const pos = this.flightPoint(p.x, p.y); const c = this.spawn(id, pos.x, pos.y);
                this.appearances.set(c.uid, { kind: 'fly', x: p.x, y: p.y, delay: 0,
                    landSound: id === 'cash' || id === 'founder' || ['employee', 'customer'].includes(this.def(id).type) ? this.dropSound(id) : undefined });
                this.event('card_drawn', id); this.say('获得：' + this.def(c).name);
            }
        }
        if (!p.contents.length) this.packs = this.packs.filter(v => v !== p); this.revision++;
    }
    acceptsOutput(id: string, sid: number) {
        const arr = this.members(sid); if (!arr.length) return false;
        const counts = this.counts(arr); counts[id] = (counts[id] || 0) + 1;
        if (arr.every(c => c.id === id) && !['employee', 'department', 'risk', 'idea'].includes(this.def(id).type)) return true;
        return this.data.recipes.some(r => {
            if (!r.inputs.some(i => this.countId(i.id) === this.countId(id)) && !(this.def(id).type === 'employee'
                && r.worker_tags.some(t => t === 'any' || this.def(id).workTags.includes(t)))) return false;
            const needs: Record<string, number> = {}; r.inputs.forEach(i => { needs[i.id] = (needs[i.id] || 0) + i.count; });
            if (Object.keys(counts).every(k => needs[k] != null && counts[k] <= needs[k])) return true;
            if (r.inputs.some(i => (counts[i.id] || 0) < i.count)) return false;
            const workers = arr.filter(c => this.def(c).type === 'employee').map(c => this.def(c));
            if (this.def(id).type === 'employee') workers.push(this.def(id));
            return !r.worker_tags.length || r.worker_tags.some(t => t === 'any' ? workers.length > 0 : workers.some(d => d.workTags.includes(t)));
        });
    }
    canSupply(c: CardState) { return !this.isPassive(c) && !this.isCombatant(c.sid) && !['badge', 'business_model', 'idea', 'risk'].includes(this.def(c).type); }
    private supplyOutputs(sid: number) {
        const active = this.production(sid); if (active) return active.recipe.outputs.map(o => o.id);
        const arr = this.members(sid), counts = this.counts(arr);
        return this.data.recipes.filter(r => {
            const needs: Record<string, number> = {}; r.inputs.forEach(i => { needs[i.id] = (needs[i.id] || 0) + i.count; });
            return arr.length > 0 && arr.every(c => needs[this.countId(c.id)] ? counts[this.countId(c.id)] <= needs[this.countId(c.id)] :
                this.def(c).type === 'employee' && r.worker_tags.some(t => t === 'any' || this.def(c).workTags.includes(t)));
        }).reduce((ids, r) => ids.concat(r.outputs.map(o => o.id)), [] as string[]);
    }
    canConnect(sourceUid: number, targetUid: number) {
        const source = this.card(sourceUid), target = this.card(targetUid);
        return !!source && !!target && source.sid !== target.sid && this.canSupply(source) && this.canSupply(target)
            && this.supplyOutputs(source.sid).some(id => this.acceptsOutput(id, target.sid));
    }
    supplyDirection(subjectUid: number, otherUid: number): 'upstream' | 'downstream' | null {
        const downstream = this.canConnect(subjectUid, otherUid), upstream = this.canConnect(otherUid, subjectUid);
        if (!downstream && !upstream) return null;
        if (upstream && !downstream) return 'upstream';
        const subject = this.card(subjectUid)!, other = this.card(otherUid)!;
        return upstream && this.production(other.sid) && !this.production(subject.sid) ? 'upstream' : 'downstream';
    }
    private normalizeLinks() {
        const seen = new Set<string>();
        this.links = this.links.filter(l => {
            const a = this.card(l.source), b = this.card(l.target); if (!a || !b || a.sid === b.sid || this.isPassive(a) || this.isPassive(b)) return false;
            const key = a.sid + ':' + b.sid; if (seen.has(key)) return false; seen.add(key); return true;
        });
    }
    connect(sourceUid: number, targetUid: number, message = '供应链已连接，产出将自动送入目标牌堆') {
        if (!this.canConnect(sourceUid, targetUid)) { this.say('这两组牌堆的产出与需求暂时接不上'); return false; }
        const source = this.card(sourceUid)!, target = this.card(targetUid)!;
        if (this.links.some(l => this.card(l.source)?.sid === source.sid && this.card(l.target)?.sid === target.sid)) { this.say('这条供应链已经连接'); return false; }
        this.links.push({ source: this.stack(source.sid)!.cards[0], target: this.stack(target.sid)!.cards[0] }); this.event('supply_chain_created');
        this.event('supply_nodes', '', new Set(this.links.reduce((a, l) => a.concat(l.source, l.target), [] as number[])).size);
        this.say(message); this.revision++; return true;
    }
    disconnect(uid: number) { const sid = this.card(uid)?.sid; this.links = this.links.filter(l => this.card(l.source)?.sid !== sid); this.say('供应链已解除'); this.revision++; }
    isCombatant(sid: number) { return !!this.battle && [this.card(this.battle.rival)?.sid, this.card(this.battle.employee)?.sid].includes(sid); }
    private moveStack(s: Stack, x: number, y: number, duration = .3) {
        ({ x, y } = this.constrainPoint(x, y, s.cards.length));
        this.stackMotions.set(s.sid, { x: s.x, y: s.y, toX: x, toY: y, time: 0, duration });
    }
    private updateStackMotions(dt: number) {
        for (const [sid, motion] of this.stackMotions) {
            const s = this.stack(sid); if (!s || sid === this.heldStack) { this.stackMotions.delete(sid); continue; }
            const t = Math.min(1, (motion.time += dt) / motion.duration);
            const ease = 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2);
            s.x = motion.x + (motion.toX - motion.x) * ease; s.y = motion.y + (motion.toY - motion.y) * ease;
            this.constrainStack(s);
            if (t === 1) this.stackMotions.delete(sid);
        }
    }
    private updateRivals(dt: number) {
        if (this.battle || this.heldStack !== -1) return;
        this.rivalClock += dt;
        const founder = this.cards.find(c => c.id === 'founder');
        if (this.rivalClock >= 3 && founder) {
            this.rivalClock %= 3; const target = this.position(founder);
            for (const c of this.cards.filter(c => this.def(c).type === 'rival')) {
                const s = this.stack(c.sid)!; if (s.cards.length !== 1 || Math.hypot(target.x - s.x, target.y - s.y) < 140) continue;
                const angle = Math.atan2(target.y - s.y, target.x - s.x) + (this.random() * 3.2 - 1.6);
                this.moveStack(s, s.x + Math.cos(angle) * 140, s.y + Math.sin(angle) * 140, .32);
            }
        }
        for (const r of this.cards.filter(c => this.def(c).type === 'rival' && this.members(c.sid).length === 1)) {
            const p = this.position(r);
            const e = this.cards.find(c => this.def(c).type === 'employee' && Math.abs(this.position(c).x - p.x) < 280 * .92 && Math.abs(this.position(c).y - p.y) < 280 * .92);
            if (e) { this.startBattle(r, e, true); break; }
        }
    }
    get battleRect() {
        const b = this.battle, employee = b && this.card(b.employee);
        if (!b || !employee) return null;
        const extra = Math.max(0, this.members(employee.sid).filter(c => this.def(c).type === 'employee').length - 1) * CARD_OFFSET;
        return { x: b.center.x, y: b.center.y + 142 - extra / 2, width: 1120, height: 776 + extra };
    }
    battleAttack(side: 'rival' | 'player') {
        const b = this.battle; if (!b) return 0;
        const c = this.card(side === 'rival' ? b.rival : b.employee); if (!c) return 0;
        return side === 'rival' ? this.def(c).capacity : this.members(c.sid).filter(m => this.def(m).type === 'employee').reduce((n, m) => n + this.employeeCapacity(m), 0);
    }
    private pushOutsideBattle(s: Stack) {
        const r = this.battleRect; if (!r) return;
        const bottom = s.y - this.stackHeight(s.sid), left = r.x - r.width / 2, right = r.x + r.width / 2, low = r.y - r.height / 2, top = r.y + r.height / 2;
        if (s.x + 140 <= left || s.x - 140 >= right || s.y + 140 <= low || bottom - 140 >= top) return;
        const candidates = [{ x: left - 168, y: s.y }, { x: right + 168, y: s.y }, { x: s.x, y: low - 168 }, { x: s.x, y: top + 168 + this.stackHeight(s.sid) }];
        candidates.sort((a, b) => Math.hypot(a.x - s.x, a.y - s.y) - Math.hypot(b.x - s.x, b.y - s.y));
        this.moveStack(s, candidates[0].x, candidates[0].y);
    }
    private startBattle(rival: CardState, employee: CardState, rivalFirst: boolean) {
        if (this.battle) return;
        const s = this.stack(employee.sid)!, rs = this.stack(rival.sid)!, center = { x: s.x, y: s.y };
        this.battle = { id: this.sequence++, rival: rival.uid, employee: employee.uid, enemyHp: rival.funds, playerHp: this.cash, damage: 0,
            rivalTurn: rivalFirst, timer: 1.5, phase: 'entry', center, attackers: [], attacker: 0, target: 0, cashSettled: true };
        this.moveStack(rs, center.x - 280, center.y); this.moveStack(s, center.x + 280, center.y);
        for (const other of this.stacks) if (other !== s && other !== rs) this.pushOutsideBattle(other);
        this.soundCues.push('battle_start'); this.say('商战开始！');
    }
    private beginBattleTurn() {
        const b = this.battle; if (!b) return;
        const rival = this.card(b.rival), employee = this.card(b.employee); if (!rival || !employee) { this.endBattle(); return; }
        // Snapshot once per turn: reinforcements attack from the following player turn.
        b.attackers = b.rivalTurn ? [rival.uid] : this.members(employee.sid).filter(c => this.def(c).type === 'employee').map(c => c.uid);
        this.nextBattleAttacker();
    }
    private nextBattleAttacker() {
        const b = this.battle; if (!b) return;
        let uid = b.attackers.shift(); while (uid && !this.card(uid)) uid = b.attackers.shift();
        if (!uid || b.enemyHp <= 0 || b.playerHp <= 0) { this.finishBattleTurn(); return; }
        const defender = this.card(b.rivalTurn ? b.employee : b.rival);
        if (!defender) { this.endBattle(); return; }
        b.attacker = uid; b.target = this.stack(defender.sid)!.cards.slice(-1)[0]; b.phase = 'outward'; b.timer = .48;
    }
    battlePose(uid: number) {
        const b = this.battle; if (!b || b.attacker !== uid || !['outward', 'return'].includes(b.phase)) return null;
        const card = this.card(uid), target = this.card(b.target); if (!card || !target) return null;
        const from = this.position(card), to = this.position(target), t = Math.max(0, Math.min(1, 1 - b.timer / .48));
        const ease = (1 - Math.cos(t * Math.PI)) / 2, travel = b.phase === 'outward' ? ease : 1 - ease;
        return { x: (to.x - from.x) * travel, y: (to.y - from.y) * travel, lift: Math.sin(ease * Math.PI) * 88 + travel * 8 };
    }
    private updateBattle(dt: number) {
        const b = this.battle; if (!b) return;
        b.playerHp = this.cash;
        if (b.playerHp <= 0) { this.finishBattleTurn(); return; }
        if (!this.card(b.rival) || !this.card(b.employee)) { this.endBattle(); return; }
        b.timer -= dt; if (b.timer > 1e-6) return;
        if (b.phase === 'entry' || b.phase === 'interval') { this.beginBattleTurn(); return; }
        if (b.phase === 'outward') {
            const attacker = this.card(b.attacker); if (!attacker) { this.finishBattleTurn(); return; }
            const power = Math.max(1, Math.round(this.employeeCapacity(attacker) * (.7 + this.random() * .6)));
            if (b.rivalTurn) {
                const loss = Math.min(this.cash, power); this.spend(loss, [this.card(b.employee)!]);
                b.playerHp = this.cash; b.damage += loss;
            }
            else { b.enemyHp = Math.max(0, b.enemyHp - power); this.card(b.rival)!.funds = Math.ceil(b.enemyHp); }
            this.battleHits.push({ uid: b.target, amount: power, rivalAttacking: b.rivalTurn }); this.soundCues.push('hit');
            b.phase = 'return'; b.timer = .48;
        } else if (b.phase === 'return' && !b.rivalTurn) { b.phase = 'member-gap'; b.timer = .12; b.attacker = 0; }
        else if (b.phase === 'member-gap') this.nextBattleAttacker();
        else this.finishBattleTurn();
    }
    private finishBattleTurn() {
        const b = this.battle; if (!b) return; b.attacker = 0;
        if (b.enemyHp <= 0 || b.playerHp <= 0) {
            const rival = this.card(b.rival), employee = this.card(b.employee);
            const team = employee ? this.members(employee.sid).filter(c => this.def(c).type === 'employee').length : 0;
            // Damage has already been paid from loose cash, then accounts, on each hit.
            if (b.enemyHp <= 0 && rival) {
                this.defeated.add(rival.uid); this.remove(rival); this.event('rival_defeated');
                if (team >= 2) this.event('team_rival_defeated'); this.say('击退了 ' + this.def(rival).name + '！');
            } else if (employee) { this.defeated.add(employee.uid); this.remove(employee); if (employee.id === 'founder') this.gameOver = true; this.say(this.def(employee).name + ' 被击败了…'); }
            this.endBattle();
        } else { b.phase = 'interval'; b.timer = 1; b.rivalTurn = !b.rivalTurn; }
    }
    private endBattle() { if (this.battle) this.soundCues.push('battle_end'); this.battle = null; }
    cardHint(c: CardState) {
        const d = this.def(c), name = d.name;
        if (this.cardStatus(c)) return `${name} · ${this.cardStatus(c)} · ${d.functionText}`;
        switch (d.type) {
            case 'employee': return `「${name} · 员工　月薪 $${d.salary}　产能 ${this.employeeCapacity(c)}」`;
            case 'badge': return `「${name} · 拖到员工卡上，产能 +1」`;
            case 'resource': return `「${name} · 资源　${c.uses >= 0 ? `剩余 ${c.uses} 次` : '可无限使用'}」`;
            case 'tool': case 'customer': case 'product': return `「${name} · ${{tool: '工具', customer: '客户', product: '产品'}[d.type]}　价值 $${d.value}」`;
            case 'cash': return `「${name} · 现金」`;
            case 'facility': return `「${name} · 设施」`;
            case 'business_model': return `「${name} · 商业模式　${this.data.recipes.find(r => r.id === d.recipeId)?.formula || ''}」`;
            default: return `「${name}」`;
        }
    }
    description(c: CardState) {
        const d = this.def(c);
        let text = d.functionText;
        if (d.type === 'employee' && c.badges?.length) text = `产能 ${this.employeeCapacity(c)}（徽章 +${c.badges.length}）、工资 $${d.salary}`;
        if (c.uses >= 0) text = `次数 ${c.uses}/${d.maxUses}`;
        if (c.id === 'p3_account') text = `账户余额 $${c.stored}/50、点击取出最多 5 个现金`;
        if (this.cardStatus(c)) text = this.cardStatus(c) + '\n' + d.functionText;
        return [text, quoteFlavor(d.flavor)].filter(Boolean).join('\n\n');
    }
}
