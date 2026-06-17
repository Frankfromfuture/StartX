extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state = root.get_node("GameState")
	var data_loader = root.get_node("DataLoader")
	game_state.dev_mode = false
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	assert(data_loader.tasks.size() == 32)
	assert(game_state.completed_tasks.has("main_start"))
	assert(main.task_list.text.contains("主任务 1/9"))
	assert(main.task_list.text.contains("支线任务 0/23"))

	main._task_event("pack_opened", "garage_pack")
	assert(game_state.completed_tasks.has("main_open_garage"))
	assert(game_state.task_unlocked_packs.has("Developemnt_pack"))

	main._task_event("rival_defeated")
	main._task_event("rival_defeated")
	assert(game_state.completed_tasks.has("battle_one"))
	assert(not game_state.completed_tasks.has("battle_three"))
	main._task_event("rival_defeated")
	assert(game_state.completed_tasks.has("battle_three"))

	main._task_event("supply_nodes", "", 4)
	assert(game_state.completed_tasks.has("supply_beginner"))
	assert(game_state.completed_tasks.has("supply_expert"))
	assert(not game_state.completed_tasks.has("supply_master"))

	main._on_task_meta_clicked("主任务/创业啦")
	assert(bool(main.task_collapsed.get("主任务/创业啦", false)))
	assert(main.task_list.text.contains("创业啦  ▸"))

	print("TaskSystemAudit: PASS")
	main.queue_free()
	await process_frame
	quit()
