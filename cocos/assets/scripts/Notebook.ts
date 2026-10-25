import { GameModel, Recipe } from './GameModel';

const STAGES = ['车库', '验证', '产品', '获客', '规模', '融资', '上市'];
export interface BusinessGroup { stage: number; title: string; total: number; known: Recipe[]; unknown: number; }

/** Mirrors Board.gd::_business_models_by_stage / _known_business_models.
 * A business-model card still inside a loose pack is already known in Godot.
 */
export function businessGroups(model: GameModel): BusinessGroup[] {
    const data = model.data;
    const stageOf = (recipe: Recipe) => {
        if (data.packs[recipe.packId]) return data.packs[recipe.packId].stage;
        const ids = recipe.inputs.map(i => i.id).concat(recipe.outputs.map(o => o.id));
        const stages = data.packOrder.filter(id => data.packs[id].slots.some(slot => slot.some(o => ids.includes(o.id)))).map(id => data.packs[id].stage);
        return stages.length ? Math.min(...stages) : 0;
    };
    const physicallyKnown = new Set<string>();
    for (const id of model.cards.map(c => c.id).concat(model.packs.reduce((ids, p) => ids.concat(p.contents), [] as string[]))) {
        if (data.recipes.some(r => r.id === id)) physicallyKnown.add(id);
        const def = data.cards[id]; if (!def) continue;
        for (const rid of [def.recipeId, def.businessModelId, def.unlocksRecipeId]) if (rid) physicallyKnown.add(rid);
    }
    const groups = new Map<number, Recipe[]>();
    for (const recipe of data.recipes) { const stage = stageOf(recipe); if (!groups.has(stage)) groups.set(stage, []); groups.get(stage)!.push(recipe); }
    return Array.from(groups.entries()).sort(([a], [b]) => a - b).map(([stage, recipes]) => {
        const known = Array.from(model.models).map(id => recipes.find(r => r.id === id)).filter((r): r is Recipe => !!r);
        for (const recipe of recipes) if (physicallyKnown.has(recipe.id) && !known.includes(recipe)) known.push(recipe);
        return { stage, title: `阶段「${data.stages?.[stage]?.name || STAGES[Math.max(0, Math.min(6, stage))]}」`, total: recipes.length, known, unknown: recipes.length - known.length };
    });
}
