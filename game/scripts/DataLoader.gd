extends Node
## Autoload: loads all JSON data files into dictionaries at startup.

var cards: Dictionary = {}
var recipes: Array = []
var packs: Dictionary = {}
var balance: Dictionary = {}
var research: Dictionary = {}
var idea_pools: Dictionary = {}

const XlsxReader = preload("res://scripts/XlsxReader.gd")
const XLSX_PATH := "res://data/startx_data.xlsx"

func _ready() -> void:
	# 卡牌 / 配方 / 卡包：以 Excel 表为唯一数据源（启动时实时读取）
	_load_workbook()
	# 其余非卡牌配置仍走 JSON
	balance = _load("res://data/balance.json")
	research = _load("res://data/research.json")
	idea_pools = _load("res://data/idea_pools.json")

# ---------------------------------------------------------------- Excel 数据源
func _load_workbook() -> void:
	var sheets := XlsxReader.read(XLSX_PATH)
	if sheets.is_empty() or not sheets.has("cards"):
		push_error("DataLoader: 读取 %s 失败，卡牌数据为空" % XLSX_PATH)
		return
	cards = _parse_cards(_rows_as_dicts(sheets.get("cards", [])))
	recipes = _parse_recipes(_rows_as_dicts(sheets.get("recipes", [])))
	_add_business_model_cards()
	packs = _parse_packs(_rows_as_dicts(sheets.get("packs", [])))
	_validate_workbook_data()
	print("DataLoader: 从 Excel 载入 %d 卡 / %d 配方 / %d 卡包" % [cards.size(), recipes.size(), packs.size()])

# 用表头行把每行转成 { 列名: 字符串值 }
func _rows_as_dicts(rows: Array) -> Array:
	var out: Array = []
	if rows.size() < 2:
		return out
	var head: Array = rows[0]
	for r in range(1, rows.size()):
		var row: Array = rows[r]
		# 跳过 id 为空的行（空行 / 注释行）
		if row.is_empty() or String(row[0]).strip_edges() == "":
			continue
		var d := {}
		for c in range(head.size()):
			var key := String(head[c]).strip_edges()
			if key == "":
				continue
			d[key] = String(row[c]) if c < row.size() else ""
		out.append(d)
	return out

func _split_list(s: String) -> Array:
	var out: Array = []
	for part in s.split(",", false):
		var p := part.strip_edges()
		if p != "":
			out.append(p)
	return out

func _parse_cards(rows: Array) -> Dictionary:
	var out := {}
	for d in rows:
		var id := String(d.get("id", "")).strip_edges()
		if id == "":
			continue
		if out.has(id):
			push_error("DataLoader: cards 表存在重复 id：%s" % id)
			continue
		var c := {
			"name": String(d.get("name", id)),
			"type": String(d.get("type", "tool")),
			"workTags": _split_list(String(d.get("workTags", ""))),
			"salary": String(d.get("salary", "0")).to_int(),
			"capacity": String(d.get("capacity", "0")).to_int(),
			"spaceCapacity": String(d.get("spaceCapacity", "0")).to_int(),
			"value": String(d.get("value", "0")).to_int(),
			"cost": String(d.get("cost", "0")).to_int(),
		}
		var mu := String(d.get("maxUses", "")).strip_edges()
		if mu != "":
			# 支持区间写法 "3-5"：每次生成时在 [min,max] 随机取剩余次数
			if "-" in mu:
				var parts := mu.split("-")
				c["maxUsesMin"] = String(parts[0]).strip_edges().to_int()
				c["maxUsesMax"] = String(parts[1]).strip_edges().to_int()
				c["maxUses"] = c["maxUsesMax"]
			else:
				c["maxUses"] = mu.to_int()
		var hp := String(d.get("hp", "")).strip_edges()
		if hp != "":
			c["hp"] = hp.to_int()
		var atk := String(d.get("attack", "")).strip_edges()
		if atk != "":
			c["attack"] = atk.to_int()
		var wr := String(d.get("workRequired", "")).strip_edges()
		if wr != "":
			c["workRequired"] = wr.to_int()
		var fl := String(d.get("flavor", "")).strip_edges()
		if fl != "":
			c["flavor"] = fl
		for key in ["recipeId", "businessModelId", "unlocksRecipeId"]:
			var ref := String(d.get(key, "")).strip_edges()
			if ref != "":
				c[key] = ref
		out[id] = c
	return out

func _parse_recipes(rows: Array) -> Array:
	var out: Array = []
	var seen := {}
	for d in rows:
		var id := String(d.get("id", "")).strip_edges()
		if id == "":
			continue
		if seen.has(id):
			push_error("DataLoader: recipes 表存在重复 id：%s" % id)
			continue
		seen[id] = true
		var r := {
			"id": id,
			"name": String(d.get("name", id)),
			"worker_tags": _split_list(String(d.get("worker_tags", ""))),
			"inputs": _parse_inputs(d),
			"outputs": _parse_outputs(d),
		}
		var gate := String(d.get("requiredIdeaId", "")).strip_edges()
		if gate != "":
			r["requiredIdeaId"] = gate
		var zone := String(d.get("output_zone", "")).strip_edges()
		if zone != "":
			r["output_zone"] = zone
		var pack_id := String(d.get("packId", "")).strip_edges()
		if pack_id != "":
			r["packId"] = pack_id
		out.append(r)
	return out

func _validate_workbook_data() -> void:
	for recipe in recipes:
		var recipe_id := String(recipe.get("id", ""))
		var inputs: Array = recipe.get("inputs", [])
		var outputs: Array = recipe.get("outputs", [])
		if inputs.is_empty():
			push_error("DataLoader: 配方 %s 没有输入" % recipe_id)
		if outputs.is_empty():
			push_error("DataLoader: 配方 %s 没有产出" % recipe_id)
		for entry in inputs:
			_validate_card_reference(recipe_id, "输入", entry)
		for entry in outputs:
			_validate_card_reference(recipe_id, "产出", entry)
			var output_id := String(entry.get("id", ""))
			if output_id != "" and int(cards.get(output_id, {}).get("workRequired", 0)) <= 0:
				push_error("DataLoader: 配方 %s 的产出卡 %s 未填写 workRequired" % [recipe_id, output_id])
	for pack_id in packs:
		var pack: Dictionary = packs[pack_id]
		var min_cards := int(pack.get("minCards", 0))
		var max_cards := int(pack.get("maxCards", 0))
		if min_cards < 0 or max_cards < min_cards:
			push_error("DataLoader: 卡包 %s 的卡牌数量范围无效：%d-%d" % [pack_id, min_cards, max_cards])
		for slot in pack.get("slots", []):
			for option in slot:
				_validate_card_reference(String(pack_id), "卡包", option)
				if int(option.get("w", 0)) <= 0:
					push_error("DataLoader: 卡包 %s 中 %s 的权重必须大于 0" % [pack_id, option.get("id", "")])

func _validate_card_reference(owner_id: String, label: String, entry: Dictionary) -> void:
	var card_id := String(entry.get("id", "")).strip_edges()
	if card_id == "":
		push_error("DataLoader: %s 的%s卡牌 id 为空" % [owner_id, label])
	elif not cards.has(card_id):
		push_error("DataLoader: %s 的%s引用了不存在的卡牌：%s" % [owner_id, label, card_id])
	if int(entry.get("count", 1)) <= 0:
		push_error("DataLoader: %s 的%s数量必须大于 0：%s" % [owner_id, label, card_id])

func _parse_inputs(d: Dictionary) -> Array:
	if String(d.get("input1", "")).strip_edges() == "":
		return _parse_io(String(d.get("inputs", "")), true)
	var out: Array = []
	for i in range(1, 6):
		var cid := String(d.get("input%d" % i, "")).strip_edges()
		if cid == "":
			continue
		var entry := {"id": cid}
		var count := String(d.get("input%dCount" % i, "")).strip_edges()
		entry["count"] = count.to_int() if count != "" else 1
		var consume := String(d.get("input%dConsume" % i, "")).strip_edges().to_lower()
		entry["consume"] = consume == "true" or consume == "1" or consume == "yes"
		out.append(entry)
	return out

func _parse_outputs(d: Dictionary) -> Array:
	if String(d.get("output1", "")).strip_edges() == "":
		return _parse_io(String(d.get("outputs", "")), false)
	var out: Array = []
	for i in range(1, 6):
		var cid := String(d.get("output%d" % i, "")).strip_edges()
		if cid == "":
			continue
		var count := String(d.get("output%dCount" % i, "")).strip_edges()
		out.append({
			"id": cid,
			"count": count.to_int() if count != "" else 1,
		})
	return out

# inputs:  "id:count:consume" 用 | 连接；outputs: "id:count" 用 | 连接
func _parse_io(s: String, is_input: bool) -> Array:
	var out: Array = []
	for item in s.split("|", false):
		var parts := item.strip_edges().split(":")
		if parts.size() < 1 or String(parts[0]).strip_edges() == "":
			continue
		var entry := {"id": String(parts[0]).strip_edges()}
		entry["count"] = String(parts[1]).to_int() if parts.size() > 1 else 1
		if is_input:
			entry["consume"] = parts.size() > 2 and String(parts[2]).strip_edges().to_lower() == "true"
		out.append(entry)
	return out

func _parse_packs(rows: Array) -> Dictionary:
	var out := {}
	for d in rows:
		var id := String(d.get("id", "")).strip_edges()
		if id == "":
			continue
		if out.has(id):
			push_error("DataLoader: packs 表存在重复 id：%s" % id)
			continue
		out[id] = {
			"name": String(d.get("name", id)),
			"stage": String(d.get("stage", "0")).to_int(),
			"price": String(d.get("price", "0")).to_int(),
			"minCards": String(d.get("minCards", "0")).to_int(),
			"maxCards": String(d.get("maxCards", "0")).to_int(),
			"slots": _parse_pack_slots(d),
		}
	return out

func _add_business_model_cards() -> void:
	for recipe in recipes:
		var rid := String(recipe.get("id", ""))
		if rid == "":
			continue
		var cid := business_model_card_id(rid)
		cards[cid] = {
			"name": String(recipe.get("name", rid)),
			"type": "business_model",
			"recipeId": rid,
			"salary": 0,
			"capacity": 0,
			"value": 1,
			"cost": 0,
		}

func _parse_pack_slots(d: Dictionary) -> Array:
	if String(d.get("slot1Card1", "")).strip_edges() == "":
		return _parse_slots(String(d.get("slots", "")))
	var out: Array = []
	for s in range(1, 6):
		var slot: Array = []
		for o in range(1, 5):
			var cid := String(d.get("slot%dCard%d" % [s, o], "")).strip_edges()
			if cid == "":
				continue
			var weight := String(d.get("slot%dProb%d" % [s, o], "")).strip_edges()
			slot.append({
				"id": cid,
				"w": weight.to_int() if weight != "" else 0,
			})
		if not slot.is_empty():
			out.append(slot)
	return out

# slots:  slot = "id:w,id:w"；slots 用 | 连接
func _parse_slots(s: String) -> Array:
	var out: Array = []
	for slot_str in s.split("|", false):
		var slot: Array = []
		for opt in slot_str.split(",", false):
			var parts := opt.strip_edges().split(":")
			if String(parts[0]).strip_edges() == "":
				continue
			slot.append({
				"id": String(parts[0]).strip_edges(),
				"w": String(parts[1]).to_int() if parts.size() > 1 else 0,
			})
		if not slot.is_empty():
			out.append(slot)
	return out

func _load(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open " + path)
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		push_error("JSON parse failed: " + path)
		return {}
	return parsed

func card_def(id: String) -> Dictionary:
	return cards.get(id, {})

func card_name(id: String) -> String:
	return String(card_def(id).get("name", id))

func card_type(id: String) -> String:
	return String(card_def(id).get("type", "tool"))

func business_model_card_id(recipe_id: String) -> String:
	return "bm_" + recipe_id

func business_model_recipe_id(card_id: String) -> String:
	var d := card_def(card_id)
	return String(d.get("recipeId", ""))

func recipe_by_id(recipe_id: String) -> Dictionary:
	for recipe in recipes:
		if String(recipe.get("id", "")) == recipe_id:
			return recipe
	return {}

func recipe_formula_text(recipe_id: String) -> String:
	var recipe := recipe_by_id(recipe_id)
	if recipe.is_empty():
		return ""
	var parts: Array = []
	for inp in recipe.get("inputs", []):
		parts.append(_io_label(inp))
	var outs: Array = []
	for outp in recipe.get("outputs", []):
		if String(outp.get("id", "")) == "cash" or outp.has("cash"):
			var count := int(outp.get("cash", outp.get("count", 1)))
			outs.append("现金*%d" % count)
		elif outp.has("id"):
			outs.append(_io_label(outp))
	var formula := _join_text(parts, "+")
	if not outs.is_empty():
		formula += " → " + _join_text(outs, "+")
	return formula

func _io_label(entry: Dictionary) -> String:
	var id := String(entry.get("id", ""))
	var s := card_name(id)
	var count := int(entry.get("count", 1))
	s += "*%d" % count
	return s

func _join_text(parts: Array, sep: String) -> String:
	var out := ""
	for i in parts.size():
		if i > 0:
			out += sep
		out += String(parts[i])
	return out
