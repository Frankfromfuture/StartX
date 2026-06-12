extends Node

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const ARROW_Y := 0.052
const CARD_TOP_Y := 0.05 + 0.05 / 3.0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var founder = main.spawn_card("founder", Vector2(420, 360))
	var neighborhood = main.spawn_card("p1_neighborhood", Vector2(520, 360))
	var production_sid: int = main._merge(founder.stack_id, neighborhood.stack_id)
	var survey = main.spawn_card("p1_survey", Vector2(800, 360))

	var source = main._supply_source_anchor(production_sid)
	assert(main._stack_accepts_supply_outputs(source.stack_id, survey.stack_id))
	main._set_supply_chain(source, survey)
	main._update_supply_arrow_mesh()

	var arrow_mesh: MeshInstance3D = main.supply_arrow_mesh
	assert(arrow_mesh != null)
	assert(arrow_mesh.get_parent() == main.city_bg.world_card_root())
	assert(arrow_mesh.mesh != null)

	var arrays := arrow_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert(not vertices.is_empty())
	for vertex in vertices:
		assert(vertex.y >= ARROW_Y - 0.0001)
		assert(vertex.y < CARD_TOP_Y)

	print("SupplyLayerAudit: %d arrow vertices below card top y=%.4f" % [
		vertices.size(),
		CARD_TOP_Y,
	])
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit()
