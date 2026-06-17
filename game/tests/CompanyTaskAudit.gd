extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state = root.get_node("GameState")
	game_state.dev_mode = false
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	assert(main.task_panel != null)
	assert(main._founder_on_board() != null)
	assert(main.loose_packs.size() == 1)
	assert(main.loose_packs[0].contents.size() == 5)
	assert(not main.loose_packs[0].contents.has("founder"))
	assert(main.loose_packs[0].contents.count("cash") == 2)
	main._toggle_company_tasks()
	assert(main.task_panel.visible)
	assert(not main.recipe_panel.visible)
	main._toggle_recipe_book()
	assert(main.recipe_panel.visible)
	assert(not main.task_panel.visible)

	assert(main._cash_card_count() == 0)
	for row in main.pack_buttons:
		var expected_unlocked := String(row["id"]) == "garage_pack"
		assert(not row["btn"].disabled == expected_unlocked)

	game_state.unlock_pack_from_task("Developemnt_pack")
	main._refresh_packs()
	for row in main.pack_buttons:
		if String(row["id"]) == "Developemnt_pack":
			assert(row["btn"].disabled)

	var cash_before_dev: int = main._cash_card_count()
	main._on_dev_mode_toggled(true)
	assert(main._cash_card_count() == cash_before_dev + 50)
	for row in main.pack_buttons:
		assert(not row["btn"].disabled)

	print("CompanyTaskAudit: PASS")
	main.queue_free()
	await process_frame
	quit()
