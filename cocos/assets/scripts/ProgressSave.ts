import { Catalog, GameModel, GameProgress } from './GameModel';

export const PROGRESS_KEY = 'startx.progress.v1';
export interface SavedView { zoom: number; pitch: number; centerX: number; centerY: number; }
export interface SavedGame { version: 1; model: GameProgress; view: SavedView; }
export function readProgress(data: Catalog, raw: string | null): { model: GameModel; view: SavedView } | null {
    if (!raw) return null;
    try {
        const save = JSON.parse(raw) as SavedGame, v = save.view;
        if (save.version !== 1 || !v || ![v.zoom, v.pitch, v.centerX, v.centerY].every(Number.isFinite) || v.zoom <= 0 || v.pitch < .76 || v.pitch > 1.12) return null;
        const model = GameModel.fromProgress(data, save.model); return model ? { model, view: v } : null;
    } catch { return null; }
}
