# StartX

StartX is a Godot-based Stacklands-like business management card game prototype. The game turns startup operations into a tactile card table: employees, cash, leads, requirements, products, contracts, revenue, facilities, research ideas, and departments all exist as draggable cards.

The player starts with a tiny company and grows it by dragging cards onto one another, discovering recipes, buying booster packs, unlocking research, managing monthly pressure, and pushing valuation through multiple company stages.

The project is currently a playable prototype focused on validating the core interaction loop and the business-simulation card grammar.

## Concept

StartX asks a simple design question:

> Can the messy process of building a startup be represented as a Stacklands-like card system?

Instead of villagers, berries, wood, and houses, StartX uses company resources:

- Employees become production power.
- Market leads become opportunities.
- Requirements become PRDs, prototypes, products, and contracts.
- Cash becomes both a global inventory and a physical card.
- Research points unlock new recipes and systems.
- Departments become automated production engines.

The result is a compact management sandbox where the player is constantly deciding what to build, what to sell, what to research, and how much burn rate the company can survive.

## Current Gameplay Loop

The main loop is:

1. Use employees on resource nodes or facilities.
2. Produce leads, requirements, training, research, and other resources.
3. Combine cards according to unlocked recipes.
4. Convert work into products, contracts, revenue, and cash.
5. Spend cash on booster packs or company growth.
6. Accumulate research points and unlock ideas.
7. Increase valuation and advance company stages.
8. Survive monthly payroll and operational pressure.

The prototype is built around fast, readable card interactions rather than menus. Most actions happen by physically moving cards on the board.

## Features

### Free Canvas Board

The play area is split into two large zones:

- **Office side**: internal work such as research, administration, organization, and production.
- **Market side**: external-facing work such as leads, sales, opportunities, contracts, and revenue.

The board supports:

- Mouse wheel zoom.
- Left-button panning on empty canvas space.
- Large board-space regions beyond the initial visible viewport.
- View clamping so the camera cannot drift infinitely away.
- Perspective-style projection for cards and board bands.

### Card Interaction

Cards are draggable, stackable, and selectable.

Implemented interaction details:

- Click to pick up a card stack.
- Move the mouse to carry cards.
- Click or drag-release to drop.
- Right click to cancel and place at the current location.
- Stacked cards use a spring-follow effect, so lower cards lag slightly behind.
- Newly generated cards appear with a smooth pop-out animation.
- Cards have selected highlights and contextual hint text.

### Square Card UI

Cards are drawn procedurally in `Card.gd`.

Current card presentation:

- Square `180 x 180` cards.
- Huawei HarmonyOS Sans SC font.
- Category-colored title bars.
- Programmatic emblem drawings.
- Salary and capacity badges.
- Remaining-use count shown as dark text in the title area.
- Work progress bars above active work-target cards.
- Subtle gloss and selected-state treatment.

### Bank and Cash

The top UI includes a fixed **Bank** area.

Bank behavior:

- Clicking the bank withdraws one unit of global cash and spawns one `cash` card.
- Dragging sellable cards to the bank converts them into global cash.
- The bank is fixed in the UI and does not scale with the free canvas.

This gives cash two roles:

- A global company treasury value.
- A physical board resource card used in recipes and interactions.

### Monthly Pressure

The game runs on monthly cycles.

The top bar includes:

- Company stage.
- Current month.
- Morale.
- Research points.
- Global cash, burn, and valuation.
- A black/gray/white progress bar showing the remaining month time.

At month end, payroll and company pressure are applied.

### Recipes

Recipes define how cards combine into outputs.

Examples of recipe-style logic:

- Employee + resource node -> production output.
- Resource + facility + employee -> higher-value resource.
- Same-level employees + training -> upgraded employee.
- Inputs may be consumed or preserved depending on the recipe.

Recipes are data-driven and live in:

```text
game/data/recipes.json
```

### Research and Ideas

Research points, ideas, and stages are part of the progression system.

Research-related systems:

- `research_bench` can generate RP with employees.
- Research nodes are configured in `research.json`.
- Idea pools are configured by stage.
- New recipes or features can be gated behind ideas.
- The research panel is implemented in `ResearchGraph.gd`.

### Booster Packs

Booster packs are configured in:

```text
game/data/packs.json
```

Packs can define:

- Stage requirements.
- Price.
- Minimum and maximum card count.
- Weighted card slots.

When purchased, a pack appears on the board and can be opened to emit cards with smooth animation.

### Departments

Employee stacks can be folded into departments.

Department behavior:

- Pure employee stacks of sufficient size can form a department.
- Department specialty is inferred from employee tags.
- Departments can produce resources over time.
- Departments act as automation engines for later-stage company growth.

## Controls

| Input | Action |
| --- | --- |
| Left click card | Pick up / drop card |
| Left drag on empty canvas | Pan board view |
| Mouse wheel | Zoom board view |
| Right click | Cancel drag / place carried cards |
| Click Bank | Withdraw one cash card |
| Drag card to Bank | Sell card stack if sellable |
| Research button | Toggle research panel |
| Recipe Book button | Toggle recipe book |

## Project Structure

```text
.
├── game/
│   ├── project.godot
│   ├── scenes/
│   │   └── Main.tscn
│   ├── scripts/
│   │   ├── Board.gd
│   │   ├── Card.gd
│   │   ├── DataLoader.gd
│   │   ├── GameState.gd
│   │   ├── PackCard.gd
│   │   └── ResearchGraph.gd
│   ├── data/
│   │   ├── balance.json
│   │   ├── cards.json
│   │   ├── idea_pools.json
│   │   ├── packs.json
│   │   ├── recipes.json
│   │   └── research.json
│   └── fonts/
│       └── HarmonyOS_Sans_SC_Regular.ttf
├── BOOSTER_PACKS.md
├── ORG_STRUCTURE.md
├── RECIPE_BOOK.md
├── RESEARCH_TREE.md
└── Stacklands_like_Enterprise_Resource_Management_GDD_CN.pdf
```

## Important Scripts

### `Board.gd`

Main gameplay controller.

Responsibilities:

- Board drawing.
- Camera zoom and pan.
- Card spawning and layout.
- Drag/drop behavior.
- Stack merging.
- Recipe evaluation.
- Production completion.
- Pack opening.
- Bank interaction.
- Department creation and output.
- Month settlement.
- HUD and panels.

### `Card.gd`

Procedural card renderer and card-level state.

Responsibilities:

- Card shape and visual style.
- Title, badges, and remaining-use display.
- Card emblem drawing.
- Selection highlight.
- Work progress bar.
- Point containment for picking.

### `GameState.gd`

Global run state.

Tracks:

- Cash.
- Morale.
- Month.
- Stage.
- Research points.
- Valuation.
- Unlocked ideas.
- Discovered recipes.
- Random generator state.

### `DataLoader.gd`

Loads JSON data files and exposes card, recipe, pack, balance, research, and idea-pool definitions.

### `ResearchGraph.gd`

Draws and manages the research panel.

### `PackCard.gd`

Draws loose booster packs on the board and stores pack contents.

## Data Files

### `cards.json`

Defines card data.

Common fields:

- `name`: Display name.
- `type`: Card type such as `employee`, `resource`, `resource_node`, or `facility`.
- `workTags`: Employee work roles.
- `salary`: Monthly payroll impact.
- `capacity`: Production power.
- `sell`: Bank sell value.
- `maxUses`: Remaining-use count for resource nodes.

### `recipes.json`

Defines production and combination recipes.

Recipe fields include:

- `id`
- `name`
- `requiredIdeaId`
- `worker_tags`
- `inputs`
- `duration`
- `outputs`
- `output_zone`

### `packs.json`

Defines booster pack content and economy.

Pack fields include:

- `stage`
- `price`
- `minCards`
- `maxCards`
- `slots`

### `research.json`

Defines research nodes and idea unlocks.

### `idea_pools.json`

Defines which ideas can appear during each company stage.

### `balance.json`

Defines global balance values, such as:

- Starting cash.
- Month duration.
- Emergency timers.
- Discovery rewards.
- Starting cards.

## Requirements

- Godot `4.6.2`
- Desktop environment capable of running Godot projects

The project is configured with:

```text
viewport_width = 1920
viewport_height = 1080
stretch/mode = canvas_items
```

## Running the Game

1. Install Godot `4.6.2`.
2. Open `game/project.godot`.
3. Run the main scene:

```text
res://scenes/Main.tscn
```

## Headless Smoke Test

On the current development machine, the project can be smoke-tested with:

```bash
"/Users/frankfan/Applications/Godot.app/Contents/MacOS/Godot" --headless --path game --quit-after 1
```

Adjust the Godot executable path for your system.

## Development Notes

The project favors fast iteration:

- Add new cards in `cards.json`.
- Add new recipes in `recipes.json`.
- Add new packs in `packs.json`.
- Gate recipes and systems through `research.json`.
- Tune pacing in `balance.json`.

Most gameplay expansion can happen in data files before touching GDScript.

## Current Status

Implemented:

- Core drag/stack/drop card interaction.
- Office and market free-canvas regions.
- Camera zoom and panning.
- Bank and cash-card interaction.
- Monthly timer and payroll pressure.
- Data-driven recipes.
- Data-driven booster packs.
- Data-driven research and idea pools.
- Recipe book panel.
- Research panel.
- Employee roles and upgrades.
- Department folding and automation.
- Procedural card rendering.
- Smooth card generation animation.

In progress / future work:

- Save and load.
- Stronger tutorial flow.
- More readable onboarding hints.
- Risk and crisis systems.
- More stage-specific events.
- More card art polish.
- More complete balancing.
- Export builds.

## Design Direction

StartX is not trying to be a spreadsheet simulator. It uses business vocabulary, but the interaction goal is physical and playful: move cards, discover combinations, and watch a company emerge from small operational loops.

The ideal finished version should feel like:

- A startup toybox.
- A compact business roguelite.
- A card-based operations sim.
- A playful management system with real strategic pressure.

## License

No license has been added yet. Add one before distributing or accepting external contributions.
