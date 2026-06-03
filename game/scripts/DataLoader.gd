extends Node
## Autoload: loads all JSON data files into dictionaries at startup.

var cards: Dictionary = {}
var recipes: Array = []
var packs: Dictionary = {}
var balance: Dictionary = {}
var research: Dictionary = {}
var idea_pools: Dictionary = {}

func _ready() -> void:
	cards = _load("res://data/cards.json")
	recipes = _load("res://data/recipes.json")
	packs = _load("res://data/packs.json")
	balance = _load("res://data/balance.json")
	research = _load("res://data/research.json")
	idea_pools = _load("res://data/idea_pools.json")

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
	return String(card_def(id).get("type", "resource"))
