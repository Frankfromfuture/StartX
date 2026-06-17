extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var game_state = root.get_node("GameState")
	var data_loader = root.get_node("DataLoader")
	game_state.stage = 2

	var rival: Dictionary = data_loader.card_def("rival2")
	assert(String(rival.get("name", "")) == "金牌销售员")
	assert(int(rival.get("capacity", 0)) == 4)

	var large_neighborhood: Dictionary = data_loader.card_def("p3_large_neighborhood")
	var wholesale_city: Dictionary = data_loader.card_def("p3_wholesale_city")
	var bank: Dictionary = data_loader.card_def("p3_bank")
	var account_def: Dictionary = data_loader.card_def("p3_account")
	assert(String(large_neighborhood.get("type", "")) == "resource")
	assert(String(wholesale_city.get("type", "")) == "resource")
	assert(not large_neighborhood.has("maxUses"))
	assert(not wholesale_city.has("maxUses"))
	assert(String(bank.get("type", "")) == "resource")
	assert(String(account_def.get("type", "")) == "tool")

	var channel_pack: Dictionary = data_loader.packs.get("channel_pack", {})
	assert(int(channel_pack.get("stage", -1)) == 2)
	assert(int(channel_pack.get("minCards", 0)) == 3)
	assert(int(channel_pack.get("maxCards", 0)) == 3)

	var build_large: Dictionary = {}
	var build_wholesale: Dictionary = {}
	var open_account: Dictionary = {}
	for recipe in data_loader.recipes:
		if recipe.get("id") == "p3_build_large_neighborhood":
			build_large = recipe
		elif recipe.get("id") == "p3_build_wholesale_city":
			build_wholesale = recipe
		elif recipe.get("id") == "p3_open_account":
			open_account = recipe
	assert(not build_large.is_empty())
	assert(not build_wholesale.is_empty())
	assert(not open_account.is_empty())
	assert(open_account.get("worker_tags", []).has("any"))
	assert(build_large.get("worker_tags", []).has("any"))
	assert(build_wholesale.get("worker_tags", []).has("any"))

	assert(main._can_start_limited_location_recipe(build_large, false))
	var large_card = main.spawn_card("p3_large_neighborhood", Vector2(500, 360))
	assert(large_card.uses_left == -1)
	assert(not main._can_start_limited_location_recipe(build_large, false))
	assert(main._can_start_limited_location_recipe(build_wholesale, false))

	var founder = main._founder_on_board()
	if founder == null:
		founder = main.spawn_card("founder", Vector2(760, 360))
	assert(main._would_interact(large_card.stack_id, founder.stack_id))

	var account = main.spawn_card("p3_account", Vector2(900, 360))
	var cash_before: int = main._cash_card_count()
	var cash_sid := -1
	for i in 55:
		var cash = main.spawn_card("cash", Vector2(900, 360))
		cash_sid = cash.stack_id if cash_sid < 0 else main._merge(cash.stack_id, cash_sid)
	assert(main._deposit_cash_into_account(cash_sid, account))
	assert(account.stored_cash == 50)
	assert(main.stacks.has(cash_sid))
	assert(main.stacks[cash_sid].size() == 5)
	main._withdraw_account_cash(account)
	assert(account.stored_cash == 45)
	assert(main._cash_card_count() == cash_before + 10)
	main._sync_cash_state()
	assert(game_state.cash == main._cash_card_count() + 45)
	var field_cash_before_spend: int = main._cash_card_count()
	assert(main._spend_cash_cards(field_cash_before_spend + 3, account))
	assert(main._cash_card_count() == 0)
	assert(account.stored_cash == 42)
	assert(game_state.cash == 42)

	var first_pack: Array = main._sanitize_pack_contents("channel_pack", ["p3_bank", "p3_bank"])
	assert(first_pack.count("p3_bank") == 1)
	main.spawn_card("p3_bank", Vector2(1050, 360))
	var blocked_pack: Array = main._sanitize_pack_contents("channel_pack", ["p3_bank"])
	assert(blocked_pack.is_empty())

	print("Pack3Audit: PASS")
	main.queue_free()
	await process_frame
	quit()
