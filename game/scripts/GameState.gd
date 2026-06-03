extends Node
## Autoload: global run state (cash, month, discoveries, rng).

signal cash_changed(new_value: int, delta: int)
signal month_changed(new_month: int)
signal recipe_discovered(recipe_id: String)
signal idea_unlocked(idea_id: String)
signal stage_changed(new_stage: int)

# 7 档渐进阶段：每阶段绑定卡包解锁 / idea 跳出池 / 研发项（见 packs.json、research.json）
const STAGE_NAMES := ["车库", "验证", "产品", "获客", "规模", "融资", "上市"]
const STAGE_THRESHOLDS := [0, 40, 100, 220, 450, 900, 1800]   # valuation needed for each stage

var cash: int = 0
var month: int = 1
var discovered: Dictionary = {}      # recipe_id -> true
var rp: float = 0.0                  # research points
var unlocked_ideas: Dictionary = {}  # idea_id -> true
var total_revenue: int = 0           # cumulative recognised revenue
var valuation: int = 0
var stage: int = 0
var monthly_expense: int = 0
var rng := RandomNumberGenerator.new()

func reset() -> void:
	rng.randomize()
	cash = int(DataLoader.balance.get("start_cash", 5))
	month = 1
	discovered.clear()
	rp = 0.0
	unlocked_ideas.clear()
	total_revenue = 0
	valuation = 0
	stage = 0
	monthly_expense = 0

func add_revenue(n: int) -> void:
	total_revenue += n

func set_valuation(v: int) -> void:
	valuation = v
	var ns := 0
	for i in STAGE_THRESHOLDS.size():
		if v >= STAGE_THRESHOLDS[i]:
			ns = i
	if ns != stage:
		stage = ns
		stage_changed.emit(stage)

func stage_name() -> String:
	return STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.size() - 1)]

func add_rp(amount: float) -> void:
	rp += amount

func can_unlock(idea_id: String) -> bool:
	var node: Dictionary = DataLoader.research.get(idea_id, {})
	if node.is_empty() or unlocked_ideas.has(idea_id):
		return false
	if stage < int(node.get("stage", 0)):
		return false
	if rp < float(node.get("cost", 0)):
		return false
	for pre in node.get("prereq", []):
		if not unlocked_ideas.has(pre):
			return false
	return true

func unlock_idea(idea_id: String) -> bool:
	if not can_unlock(idea_id):
		return false
	rp -= float(DataLoader.research[idea_id].get("cost", 0))
	unlocked_ideas[idea_id] = true
	idea_unlocked.emit(idea_id)
	return true

func unlock_idea_free(idea_id: String) -> bool:
	var node: Dictionary = DataLoader.research.get(idea_id, {})
	if node.is_empty() or unlocked_ideas.has(idea_id):
		return false
	unlocked_ideas[idea_id] = true
	idea_unlocked.emit(idea_id)
	return true

func idea_done(idea_id: String) -> bool:
	return unlocked_ideas.has(idea_id)

func add_cash(delta: int) -> void:
	cash += delta
	cash_changed.emit(cash, delta)

func spend_cash(amount: int) -> bool:
	if cash < amount:
		return false
	add_cash(-amount)
	return true

func advance_month() -> void:
	month += 1
	month_changed.emit(month)

func discover(recipe_id: String) -> bool:
	## Returns true if this is the FIRST time the recipe is completed.
	if discovered.has(recipe_id):
		return false
	discovered[recipe_id] = true
	recipe_discovered.emit(recipe_id)
	return true
