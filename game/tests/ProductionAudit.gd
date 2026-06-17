extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var founder = scene._founder_on_board()
	if founder == null:
		founder = scene.spawn_card("founder", Vector2(500, 400))
	var neighborhood = scene.spawn_card("p1_neighborhood", Vector2(500, 400))
	var production_sid: int = scene._merge(founder.stack_id, neighborhood.stack_id)
	assert(scene.productions.has(production_sid), "居住小区配方没有开始生产")

	var recipe: Dictionary = scene.productions[production_sid]["recipe"]
	assert(String(recipe.get("id", "")) == "p1_recruit_youth", "匹配到了错误配方")
	assert(String(recipe["outputs"][0].get("id", "")) == "p1_youth", "配方产出不是小区青年")

	var target = scene.productions[production_sid]["target"]
	target.work_elapsed = scene._recipe_work_required(recipe)
	scene._complete_production(production_sid)
	await process_frame
	await process_frame

	var youth_count := 0
	var neighborhood_count := 0
	for card in scene.all_cards:
		if not is_instance_valid(card):
			continue
		if card.card_id == "p1_youth":
			youth_count += 1
		elif card.card_id == "p1_neighborhood":
			neighborhood_count += 1

	assert(youth_count == 1, "生产后应新增 1 张小区青年，实际为 %d" % youth_count)
	assert(neighborhood_count == 1, "居住小区不应被复制或消耗，实际为 %d" % neighborhood_count)
	print("ProductionAudit: PASS - p1_neighborhood -> p1_youth")
	scene.queue_free()
	await process_frame
	await process_frame
	quit()
