extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data_loader = root.get_node_or_null("DataLoader")
	assert(data_loader != null, "DataLoader 自动加载失败")
	var pack: Dictionary = data_loader.packs.get("Developemnt_pack", {})
	assert(not pack.is_empty(), "第二卡包不存在")
	assert(int(pack.get("minCards", 0)) == 3, "第二卡包最少应开出 3 张")
	assert(int(pack.get("maxCards", 0)) == 3, "第二卡包最多应开出 3 张")
	assert((pack.get("slots", []) as Array).size() == 3, "第二卡包应有 3 个抽卡槽")
	var has_workstation := false
	var has_advanced_specialist := false
	for slot in pack.get("slots", []):
		for option in slot:
			if String(option.get("id", "")) == "p2_orderly_workstation":
				has_workstation = true
			if String(option.get("id", "")) in [
				"p2_sales_specialist", "p2_product_specialist", "p2_admin_specialist"
			]:
				has_advanced_specialist = true
	assert(not has_workstation, "井井有条的工位应鼓励玩家生产，不应直接抽到")
	assert(not has_advanced_specialist, "各专员应鼓励玩家生产，不应直接抽到")

	var law_firm: Dictionary = data_loader.card_def("p2_law_firm")
	assert(String(law_firm.get("type", "")) == "resource", "律师事务所应归类为 resource")
	assert(int(law_firm.get("maxUsesMin", 0)) == 3, "律师事务所最少使用次数应为 3")
	assert(int(law_firm.get("maxUsesMax", 0)) == 5, "律师事务所最多使用次数应为 5")
	assert(String(data_loader.card_def("cash").get("type", "")) == "cash", "现金应归类为 cash")
	var document_def: Dictionary = data_loader.card_def("p2_document")
	assert(String(document_def.get("type", "")) == "tool", "文书应为 tool")
	assert(int(document_def.get("value", -1)) == 0, "文书价值应为 0")
	assert(int(data_loader.card_def("p2_contract").get("value", -1)) == 0, "合同价值应为 0")
	assert(int(data_loader.card_def("p1_office").get("spaceCapacity", 0)) == 30, "创始人办公桌空间容量应为 30")
	assert(int(data_loader.card_def("p2_orderly_workstation").get("spaceCapacity", 0)) == 5, "井井有条的工位空间容量应为 5")

	for id in ["p1_survey", "p1_marketing"]:
		var card: Dictionary = data_loader.card_def(id)
		assert(String(card.get("type", "")) == "tool", "%s 应为一次性工具" % id)
		assert(int(card.get("value", 0)) == 1, "%s 价值应为 1" % id)

	for id in ["p2_sales_specialist", "p2_product_specialist", "p2_admin_specialist"]:
		var specialist: Dictionary = data_loader.card_def(id)
		assert(int(specialist.get("capacity", 0)) == 3, "%s 产能应为 3" % id)
		assert(int(specialist.get("salary", 0)) == 2, "%s 工资应为 2" % id)

	var scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var pack_landing: Vector2 = scene._pack_landing_below("Developemnt_pack")
	var pack_screen_center: Vector2 = scene._project(
		pack_landing + Vector2(scene.PACK_W, scene.PACK_H) * 0.5
	)
	assert(
		pack_screen_center.distance_to(scene._screen_center()) <= 240.0,
		"新卡包应落在玩家当前画面中心附近"
	)

	var document_count_before := 0
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_document":
			document_count_before += 1
	var drafting_office = scene.spawn_card("p1_office", Vector2(430, 300))
	var drafting_employee = scene.spawn_card("p1_intern", Vector2(430, 300))
	var drafting_sid: int = scene._merge(drafting_employee.stack_id, drafting_office.stack_id)
	assert(scene.productions.has(drafting_sid), "任意员工 + 办公室没有开始文书配方")
	assert(
		String(scene.productions[drafting_sid]["recipe"].get("id", "")) == "p2_make_document",
		"任意员工 + 办公室应匹配起草文书配方"
	)
	scene._complete_production(drafting_sid)
	await process_frame
	await process_frame
	var document_count_after := 0
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_document":
			document_count_after += 1
	assert(document_count_after > document_count_before, "办公室与员工没有产出文书")
	assert(is_instance_valid(drafting_office), "办公室不应被消耗")
	assert(is_instance_valid(drafting_employee), "员工不应被消耗")

	var contract_count_before := 0
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_contract":
			contract_count_before += 1
	var contract_document = scene.spawn_card("p2_document", Vector2(470, 315))
	var law_office = scene.spawn_card("p2_law_firm", Vector2(470, 315))
	law_office.uses_left = 3
	var contract_sid: int = scene._merge(contract_document.stack_id, law_office.stack_id)
	assert(scene._production_speed(contract_sid) == 1.0, "无产能时生产速度下限应为 1")
	assert(scene.productions.has(contract_sid), "文书 + 律师事务所没有开始合同配方")
	assert(
		String(scene.productions[contract_sid]["recipe"].get("id", "")) == "p2_make_contract",
		"文书 + 律师事务所应匹配起草合同配方"
	)
	var contract_work_required := float(data_loader.card_def("p2_contract").get("workRequired", 0))
	assert(contract_work_required > 0.0, "合同应填写工作量")
	assert(
		scene._recipe_work_required(scene.productions[contract_sid]["recipe"]) == contract_work_required,
		"合同配方应读取合同卡的工作量"
	)
	assert(
		scene._production_duration(contract_sid, scene.productions[contract_sid]["recipe"]) == contract_work_required,
		"零产能时合同生产时间应等于合同工作量"
	)
	scene._complete_production(contract_sid)
	await process_frame
	await process_frame
	var contract_count_after := 0
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_contract":
			contract_count_after += 1
	assert(contract_count_after > contract_count_before, "文书与律师事务所没有产出合同")
	assert(not scene.all_cards.has(contract_document), "起草合同应消耗文书")
	assert(is_instance_valid(law_office), "律师事务所不应被消耗")
	assert(law_office.uses_left == 2, "律师事务所应扣除 1 次使用次数")

	var bottom_employee = scene.spawn_card("p2_grad", Vector2(500, 330))
	var top_employee = scene.spawn_card("p2_sales_specialist", Vector2(500, 330))
	var employee_stack: int = scene._merge(top_employee.stack_id, bottom_employee.stack_id)
	var capacity_tool = scene.spawn_card("p2_admin_management", Vector2(500, 330))
	employee_stack = scene._merge(capacity_tool.stack_id, employee_stack)
	var capacity_product = scene.spawn_card("p1_package", Vector2(500, 330))
	employee_stack = scene._merge(capacity_product.stack_id, employee_stack)
	assert(
		scene._stack_capacity(employee_stack) == 5,
		"生产产能应为最底层员工 2 + 工具价值 1 + 产品价值 2"
	)
	assert(scene._production_speed(employee_stack) == 5.0, "产能 5 的生产速度应为 5")
	var upper_employee = scene.spawn_card("p2_sales_specialist", Vector2(500, 330))
	employee_stack = scene._merge(upper_employee.stack_id, employee_stack)
	var upper_tool = scene.spawn_card("p2_product_course", Vector2(500, 330))
	employee_stack = scene._merge(upper_tool.stack_id, employee_stack)
	var upper_product = scene.spawn_card("p1_rawprod", Vector2(500, 330))
	employee_stack = scene._merge(upper_product.stack_id, employee_stack)
	assert(
		scene._stack_capacity(employee_stack) == 5,
		"同类型只应计算最下面一张：上层员工、工具与产品不增加产能"
	)

	var tool_only = scene.spawn_card("p2_product_course", Vector2(580, 330))
	var product_only = scene.spawn_card("p1_rawprod", Vector2(580, 330))
	var non_employee_stack: int = scene._merge(product_only.stack_id, tool_only.stack_id)
	assert(scene._stack_capacity(non_employee_stack) == 3, "无员工时应只计算工具与产品价值产能")


	for pack_id in ["garage_pack", "Developemnt_pack"]:
		for i in 20:
			var business_card_id: String = scene._pick_business_model_card(pack_id, [])
			assert(business_card_id != "", "%s 应有可抽取的商业模式" % pack_id)
			assert(
				scene._business_model_pack_id(business_card_id) == pack_id,
				"%s 抽到了其它卡包的商业模式 %s" % [pack_id, business_card_id]
			)
	assert(scene.BUSINESS_MODEL_CHANCE == 0.50, "商业模式出现概率应为 50%")
	var wrong_business_card: String = data_loader.business_model_card_id("p2_make_document")
	assert(
		not scene._sanitize_pack_contents("garage_pack", [wrong_business_card]).has(wrong_business_card),
		"错误归属的商业模式不应进入卡包"
	)

	var contract = scene.spawn_card("p2_contract", Vector2(700, 420))
	var intern = scene.spawn_card("p1_intern", Vector2(700, 420))
	var grad_sid: int = scene._merge(contract.stack_id, intern.stack_id)
	assert(scene.productions.has(grad_sid), "合同 + 实习生没有开始毕业生配方")
	assert(String(scene.productions[grad_sid]["recipe"].get("id", "")) == "p2_train_grad")
	scene._complete_production(grad_sid)
	await process_frame
	await process_frame

	var grad = null
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_grad":
			grad = card
			break
	assert(grad != null, "毕业生没有产出")

	var specialist_count_before := 0
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_sales_specialist":
			specialist_count_before += 1
	var course = scene.spawn_card("p2_sales_course", grad.position)
	var specialist_sid: int = scene._merge(grad.stack_id, course.stack_id)
	assert(scene.productions.has(specialist_sid), "毕业生 + 销售技巧课程没有开始专员配方")
	assert(String(scene.productions[specialist_sid]["recipe"].get("id", "")) == "p2_train_sales_specialist")
	var expected_specialists: int = scene._output_mult(scene._stack_capacity(specialist_sid))
	scene._complete_production(specialist_sid)
	await process_frame
	await process_frame

	var specialist_count := 0
	var sales_specialist = null
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p2_sales_specialist":
			specialist_count += 1
			sales_specialist = card
	assert(
		specialist_count - specialist_count_before == expected_specialists,
		"销售专员新增数量应为 %d，实际为 %d" % [
			expected_specialists, specialist_count - specialist_count_before
		]
	)

	var neighborhood = scene.spawn_card("p1_neighborhood", sales_specialist.position)
	neighborhood.uses_left = 3
	var customer_sid: int = scene._merge(sales_specialist.stack_id, neighborhood.stack_id)
	assert(scene.productions.has(customer_sid), "销售专员 + 居住小区没有开始靠谱客户配方")
	assert(String(scene.productions[customer_sid]["recipe"].get("id", "")) == "p2_specialist_make_customer")
	scene._complete_production(customer_sid)
	await process_frame
	await process_frame
	assert(neighborhood.uses_left == 2, "居住小区应扣除 1 次使用次数")
	assert(is_instance_valid(sales_specialist), "销售专员不应被消耗")

	var product_specialist = scene.spawn_card("p2_product_specialist", Vector2(900, 420))
	var wholesale = scene.spawn_card("p1_wholesale", Vector2(900, 420))
	wholesale.uses_left = 3
	var recipe_cash = scene.spawn_card("cash", Vector2(1100, 420))
	scene.spawn_card("cash", Vector2(1160, 420))
	assert(
		scene._would_interact(product_specialist.stack_id, wholesale.stack_id),
		"三元素配方中，任意两个已有元素应显示交互提示"
	)
	assert(
		scene._would_interact(product_specialist.stack_id, recipe_cash.stack_id),
		"点击产品专员时，配方所需现金应显示交互提示"
	)
	var product_recipe: Dictionary = {}
	for candidate in data_loader.recipes:
		if String(candidate.get("id", "")) == "p2_specialist_package_product":
			product_recipe = candidate
			break
	assert(not product_recipe.is_empty(), "产品专员配方不存在")
	assert(
		scene._recipe_matches(
			product_recipe,
			{"p2_product_specialist": 1, "p1_wholesale": 1, "cash": 1},
			[wholesale, product_specialist, recipe_cash]
		),
		"产品专员 + 批发市场 + 现金应满足配方输入"
	)
	var product_sid: int = scene._merge(product_specialist.stack_id, wholesale.stack_id)
	assert(not scene.productions.has(product_sid), "三元素配方缺少现金时不应提前开工")
	product_sid = scene._merge(recipe_cash.stack_id, product_sid)
	assert(scene.productions.has(product_sid), "产品专员 + 批发市场 + 现金没有开始带包装产品配方")
	assert(String(scene.productions[product_sid]["recipe"].get("id", "")) == "p2_specialist_package_product")
	scene._complete_production(product_sid)
	await create_timer(1.0).timeout
	assert(wholesale.uses_left == 2, "批发市场应扣除 1 次使用次数")
	assert(is_instance_valid(product_specialist), "产品专员不应被消耗")

	var customer_count := 0
	var package_count := 0
	for card in scene.all_cards:
		if not is_instance_valid(card):
			continue
		if card.card_id == "p1_customer":
			customer_count += 1
		elif card.card_id == "p1_package":
			package_count += 1
	assert(customer_count >= 1, "销售专员配方没有产出靠谱客户")
	assert(package_count >= 1, "产品专员配方没有产出带包装粗糙产品")

	var base_capacity: int = scene._business_card_capacity()
	assert(base_capacity == 30, "场上一个创始人办公桌时空间上限应为 30，实际为 %d" % base_capacity)
	var office = scene.spawn_card("p1_office", Vector2(1050, 520))
	var admin_management = scene.spawn_card("p2_admin_management", Vector2(1050, 520))
	var workstation_cash = scene.spawn_card("cash", Vector2(1050, 520))
	assert(
		scene._would_interact(office.stack_id, admin_management.stack_id),
		"三元素工位配方中，办公桌与行政管理应显示交互提示"
	)
	assert(
		scene._would_interact(admin_management.stack_id, workstation_cash.stack_id),
		"三元素工位配方中，行政管理与现金应显示交互提示"
	)
	var workstation_sid: int = scene._merge(office.stack_id, admin_management.stack_id)
	assert(not scene.productions.has(workstation_sid), "工位配方缺少现金时不应提前开工")
	workstation_sid = scene._merge(workstation_cash.stack_id, workstation_sid)
	assert(scene.productions.has(workstation_sid), "办公室 + 行政管理 + 现金没有开始工位配方")
	assert(String(scene.productions[workstation_sid]["recipe"].get("id", "")) == "p2_build_orderly_workstation")
	scene._complete_production(workstation_sid)
	await process_frame
	await process_frame
	assert(is_instance_valid(office), "办公室不应被消耗")
	assert(scene._business_card_capacity() == 65, "两个办公桌与一个工位的空间上限应为 65")

	var regular_fire = scene.spawn_card("p2_grad", Vector2(800, 560))
	var cash_before_regular_fire: int = scene._cash_card_count()
	assert(scene._can_fire_stack(regular_fire.stack_id), "平时也应允许将员工拖到出售栏解雇")
	assert(
		scene._sell_stack(regular_fire.stack_id, Vector2(900, 500), Vector2(900, 500)),
		"员工拖到出售栏应成功解雇"
	)
	assert(not is_instance_valid(regular_fire) or not scene.all_cards.has(regular_fire), "被解雇员工应从场上删除")
	assert(scene._cash_card_count() == cash_before_regular_fire, "解雇员工不应产生现金")

	while scene._business_card_count() <= scene._business_card_capacity():
		scene.spawn_card("p1_youth", Vector2(600, 600))
	for i in 20:
		scene.spawn_card("cash", Vector2(1200, 600))
	var month_before_cleanup: int = scene.get_node("/root/GameState").month
	scene._settle_month()
	assert(scene.capacity_cleanup_pending, "超容月末应进入清理状态")
	assert(scene.get_node("/root/GameState").month == month_before_cleanup, "超容时不应进入下个月")

	var sellable = null
	for card in scene.all_cards:
		if is_instance_valid(card) and card.card_id == "p1_youth" and scene.stacks[card.stack_id].size() == 1:
			sellable = card
			break
	assert(sellable != null, "未找到可出售的价值卡")
	scene._sell_stack(sellable.stack_id, Vector2(900, 500), Vector2(900, 500))
	await process_frame
	assert(not scene.capacity_cleanup_pending, "容量合规后应结束清理状态")
	assert(scene.get_node("/root/GameState").month == month_before_cleanup + 1, "清理完成后应进入下个月")

	var fired_employee = scene.spawn_card("p2_grad", Vector2(750, 650))
	while scene._business_card_count() <= scene._business_card_capacity():
		scene.spawn_card("p1_youth", Vector2(650, 650))
	var cash_before_fire: int = scene._cash_card_count()
	var month_before_fire: int = scene.get_node("/root/GameState").month
	scene._settle_month()
	assert(scene.capacity_cleanup_pending, "第二次超容应进入清理状态")
	assert(scene._can_fire_stack(fired_employee.stack_id), "清理状态应允许解雇员工")
	scene._sell_stack(fired_employee.stack_id, Vector2(900, 500), Vector2(900, 500))
	assert(scene._cash_card_count() <= cash_before_fire, "免费解雇不应产出现金")
	while scene.capacity_cleanup_pending:
		var extra_sellable = null
		for card in scene.all_cards:
			if is_instance_valid(card) and int(card.cdef.get("value", 0)) > 0 \
					and not scene.is_person(card) and scene.stacks[card.stack_id].size() == 1:
				extra_sellable = card
				break
		assert(extra_sellable != null, "清理状态缺少可出售卡")
		scene._sell_stack(extra_sellable.stack_id, Vector2(900, 500), Vector2(900, 500))
	assert(scene.get_node("/root/GameState").month == month_before_fire + 1, "解雇并清理后应进入下个月")

	print("Pack2Audit: PASS")
	scene.queue_free()
	await process_frame
	await process_frame
	quit()
