export interface ConnectorPoint { x: number; y: number; }
export interface ConnectorRect { left: number; right: number; bottom: number; top: number; }
export interface ConnectorRoute { points: ConnectorPoint[]; length: number; }
export const SUPPLY_LINE_WIDTH = 10;
export const SUPPLY_ARROW_LENGTH = 36;
export const SUPPLY_ARROW_HALF_WIDTH = 16;
export const SUPPLY_CORNER_RADIUS = 28;

/** Shortest orthogonal route between the four edge midpoints, outside both cards. */
export function shortestSupplyRoute(a: ConnectorRect, b: ConnectorRect): ConnectorRoute {
    const anchors = (r: ConnectorRect) => {
        const x = (r.left + r.right) / 2, y = (r.bottom + r.top) / 2;
        return [{ x: r.right, y, nx: 1, ny: 0 }, { x: r.left, y, nx: -1, ny: 0 },
            { x, y: r.top, nx: 0, ny: 1 }, { x, y: r.bottom, nx: 0, ny: -1 }];
    };
    const crosses = (p: ConnectorPoint, q: ConnectorPoint, r: ConnectorRect) => p.x === q.x
        ? p.x > r.left && p.x < r.right && Math.max(p.y, q.y) > r.bottom && Math.min(p.y, q.y) < r.top
        : p.y > r.bottom && p.y < r.top && Math.max(p.x, q.x) > r.left && Math.min(p.x, q.x) < r.right;
    let best: ConnectorRoute = { points: [], length: Infinity };
    for (const s of anchors(a)) for (const t of anchors(b)) {
        const x = (s.x + t.x) / 2, y = (s.y + t.y) / 2;
        const candidates = [
            [s, { x: t.x, y: s.y }, t], [s, { x: s.x, y: t.y }, t],
            [s, { x, y: s.y }, { x, y: t.y }, t], [s, { x: s.x, y }, { x: t.x, y }, t],
        ];
        for (const candidate of candidates) {
            const points: ConnectorPoint[] = [];
            for (const p of candidate) {
                const last = points[points.length - 1];
                if (last && last.x === p.x && last.y === p.y) continue;
                points.push({ x: p.x, y: p.y });
            }
            if (points.length < 2) continue;
            const first = points[1], last = points[points.length - 2];
            if ((first.x - s.x) * s.nx + (first.y - s.y) * s.ny <= 0
                || (last.x - t.x) * t.nx + (last.y - t.y) * t.ny <= 0) continue;
            if (points.some((p, i) => i && (crosses(points[i - 1], p, a) || crosses(points[i - 1], p, b)))) continue;
            const length = supplyPathLength(points);
            if (length < best.length || length === best.length && points.length < best.points.length) best = { points, length };
        }
    }
    return Number.isFinite(best.length) ? best : { points: [], length: 0 };
}

export function roundSupplyRoute(route: ConnectorRoute, radius = SUPPLY_CORNER_RADIUS): ConnectorPoint[] {
    if (route.points.length < 3) return route.points;
    const points = [route.points[0]];
    for (let j = 1; j < route.points.length - 1; j++) {
        const a = route.points[j - 1], corner = route.points[j], b = route.points[j + 1];
        const first = Math.hypot(corner.x - a.x, corner.y - a.y), last = Math.hypot(b.x - corner.x, b.y - corner.y);
        const r = Math.min(radius, first / 2, last / 2);
        const before = { x: corner.x + (a.x - corner.x) / first * r, y: corner.y + (a.y - corner.y) / first * r };
        const after = { x: corner.x + (b.x - corner.x) / last * r, y: corner.y + (b.y - corner.y) / last * r };
        points.push(before);
        for (let i = 1; i <= 10; i++) {
            const t = i / 10, u = 1 - t;
            points.push({ x: u * u * before.x + 2 * u * t * corner.x + t * t * after.x,
                y: u * u * before.y + 2 * u * t * corner.y + t * t * after.y });
        }
    }
    points.push(route.points[route.points.length - 1]); return points;
}

export function supplyPathLength(points: ConnectorPoint[]) {
    return points.reduce((sum, point, i) => i ? sum + Math.hypot(point.x - points[i - 1].x, point.y - points[i - 1].y) : 0, 0);
}

export function supplyPathAt(points: ConnectorPoint[], distance: number) {
    let remaining = Math.max(0, distance);
    for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i], length = Math.hypot(b.x - a.x, b.y - a.y); if (!length) continue;
        if (remaining <= length || i === points.length - 1) {
            const t = Math.min(1, remaining / length);
            return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, nx: (b.x - a.x) / length, ny: (b.y - a.y) / length };
        }
        remaining -= length;
    }
    return { ...points[0], nx: 0, ny: 0 };
}
