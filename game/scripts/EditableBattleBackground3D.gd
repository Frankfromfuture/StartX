@tool
extends Node3D

const DECORATION_LEAN_DEG := 60.0
const BACKGROUND_ASSET_DIR := "res://assets/backgrounds/root_background_assets"
const BACKGROUND_SEED := 20260617
const BUILDING_COUNT := 10
const SWAY_STRENGTH_GRASS := Vector2(0.006, 0.013)
const SWAY_STRENGTH_BUSH := Vector2(0.007, 0.015)
const SWAY_STRENGTH_TREE := Vector2(0.012, 0.026)
const SWAY_STRENGTH_MULTIPLIER := 4.5
const SWAY_SPEED := Vector2(0.38, 0.72)
const SWAY_TOP_ALPHA := 0.35
const BACKGROUND_FADE_ALPHA := 0.7

@onready var camera: Camera3D = $Camera3D
@onready var decorations: Node3D = $OutsideDecorations3D
@onready var active_canvas: MeshInstance3D = $ActiveCanvasWhiteboard

var _sway_shader: Shader = null
var _soft_shadow_material: ShaderMaterial = null
var _visible_bottom_cache := {}

func _ready() -> void:
	if decorations != null and decorations.get_child_count() > 0:
		_prepare_existing_decorations()
	elif Engine.is_editor_hint():
		return
	else:
		_rebuild_decorations()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_pin_decoration_bottoms()
		_sync_decoration_shadows()
		return
	_update_decoration_angles()
	_pin_decoration_bottoms()
	_sync_decoration_shadows()

func _rebuild_decorations() -> void:
	if decorations == null:
		return
	if decorations.get_child_count() > 0:
		_prepare_existing_decorations()
		return
	for child in decorations.get_children():
		child.free()
	for data in _decoration_layout():
		_add_decoration(data)
	_update_decoration_angles()

func _prepare_existing_decorations() -> void:
	if decorations == null:
		return
	for child in decorations.get_children():
		_mark_editor_owned(child)
		_prepare_existing_decoration_visuals(child)
	if Engine.is_editor_hint():
		_pin_decoration_bottoms()
		_sync_decoration_shadows()
		return
	_update_decoration_angles()
	_pin_decoration_bottoms()
	_sync_decoration_shadows()

func _prepare_existing_decoration_visuals(node: Node) -> void:
	var sprite := node as Sprite3D
	if sprite == null:
		return
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	sprite.modulate = Color(1, 1, 1, BACKGROUND_FADE_ALPHA)
	sprite.transparency = 1.0 - BACKGROUND_FADE_ALPHA
	if _is_sway_decoration(sprite.name) and sprite.texture != null:
		var material := sprite.material_override as ShaderMaterial
		var strength := 0.012
		var speed := 0.55
		var phase := 0.0
		if material != null:
			strength = float(material.get_shader_parameter("sway_strength")) / SWAY_STRENGTH_MULTIPLIER
			speed = float(material.get_shader_parameter("sway_speed"))
			phase = float(material.get_shader_parameter("sway_phase"))
		sprite.material_override = _sway_material(sprite.texture, strength, speed, phase)

func _add_decoration(data: Dictionary) -> void:
	var tex := load(String(data["path"])) as Texture2D
	if tex == null:
		push_warning("Editable background decoration missing texture: %s" % String(data["path"]))
		return
	var sprite := Sprite3D.new()
	sprite.name = String(data["name"])
	sprite.texture = tex
	sprite.pixel_size = float(data.get("pixel", 0.002)) * _pixel_multiplier(String(data["path"]))
	sprite.modulate = Color(1, 1, 1, BACKGROUND_FADE_ALPHA)
	sprite.transparency = 1.0 - BACKGROUND_FADE_ALPHA
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	sprite.position = data["pos"]
	_pin_sprite_bottom_to_canvas(sprite)
	if bool(data.get("sway", false)):
		sprite.material_override = _sway_material(
			tex,
			float(data.get("sway_strength", 0.01)),
			float(data.get("sway_speed", 0.5)),
			float(data.get("sway_phase", 0.0))
		)
	decorations.add_child(sprite)
	_mark_editor_owned(sprite)

func _mark_editor_owned(node: Node) -> void:
	node.set_meta("startx_generated_background_asset", true)
	if not Engine.is_editor_hint():
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		scene_root = self
	node.owner = scene_root

func _sway_material(tex: Texture2D, strength: float, speed: float, phase: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _get_sway_shader()
	material.set_shader_parameter("albedo_tex", tex)
	material.set_shader_parameter("sway_strength", strength * SWAY_STRENGTH_MULTIPLIER)
	material.set_shader_parameter("sway_speed", speed)
	material.set_shader_parameter("sway_phase", phase)
	material.set_shader_parameter("top_alpha", SWAY_TOP_ALPHA)
	material.set_shader_parameter("fade_alpha", BACKGROUND_FADE_ALPHA)
	return material

func _get_sway_shader() -> Shader:
	if _sway_shader != null:
		return _sway_shader
	_sway_shader = Shader.new()
	_sway_shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D albedo_tex : source_color;
uniform float sway_strength = 0.01;
uniform float sway_speed = 0.5;
uniform float sway_phase = 0.0;
uniform float top_alpha = 0.35;
uniform float fade_alpha = 0.7;

void vertex() {
	float top_weight = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.8);
	float gust = sin(TIME * sway_speed + sway_phase) + 0.35 * sin(TIME * sway_speed * 1.73 + sway_phase * 0.61);
	VERTEX.x += gust * sway_strength * top_weight;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float top_fade = smoothstep(0.28, 1.0, 1.0 - UV.y);
	ALBEDO = tex.rgb;
	ALPHA = tex.a * mix(1.0, top_alpha, top_fade) * fade_alpha;
}
"""
	return _sway_shader

func _is_sway_decoration(node_name: String) -> bool:
	return node_name.begins_with("Grass") or node_name.begins_with("Tree") or node_name.begins_with("Bush")

func _decoration_layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = BACKGROUND_SEED
	var buildings := _assets_with_prefix("building")
	var grasses := _assets_with_prefix("grass")
	var trees := _assets_with_prefix("tree")
	var bushes := _assets_with_prefix("bush")
	var elements := _assets_with_prefix("element")
	var layout := []

	var building_row := _repeat_assets_to_count(buildings, BUILDING_COUNT)
	_shuffle_with_rng(building_row, rng)
	for i in building_row.size():
		var t := 0.0 if BUILDING_COUNT <= 1 else float(i) / float(BUILDING_COUNT - 1)
		layout.append({
			"name": "Building%02d" % (i + 1),
			"path": building_row[i],
			"pos": Vector3(lerpf(-7.45, 7.45, t) + rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-4.25, -3.58)),
			"pixel": rng.randf_range(0.0043, 0.0052),
		})

	var side_assets := bushes + elements
	_shuffle_with_rng(side_assets, rng)
	for i in side_assets.size():
		var left_side := i % 2 == 0
		layout.append({
			"name": "SideElement%02d" % (i + 1),
			"path": side_assets[i],
			"pos": Vector3(rng.randf_range(-8.0, -5.35) if left_side else rng.randf_range(5.35, 8.0), 0.0, rng.randf_range(-2.35, 3.85)),
			"pixel": rng.randf_range(0.0021, 0.0032),
		})

	var lower_clusters := [
		Vector2(-6.3, 2.35),
		Vector2(-3.2, 3.8),
		Vector2(0.1, 3.15),
		Vector2(3.1, 3.75),
		Vector2(6.2, 2.45),
	]
	_append_clustered_assets(layout, grasses, rng, "Grass", 44, lower_clusters, Vector2(0.00135, 0.0019), Vector2(1.45, 0.75))
	_append_clustered_assets(layout, trees, rng, "Tree", 28, lower_clusters, Vector2(0.0019, 0.00265), Vector2(1.15, 0.8))
	_append_clustered_assets(layout, bushes, rng, "Bush", 14, lower_clusters, Vector2(0.0017, 0.00225), Vector2(1.25, 0.7))
	return layout

func _assets_with_prefix(prefix: String) -> Array:
	var paths := []
	var dir := DirAccess.open(BACKGROUND_ASSET_DIR)
	if dir == null:
		push_warning("Editable background asset folder missing: %s" % BACKGROUND_ASSET_DIR)
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var extension := file_name.get_extension().to_lower()
		if not dir.current_is_dir() and extension in ["png", "jpg", "jpeg", "webp"]:
			var basename := file_name.get_basename().to_lower()
			if basename.begins_with(prefix):
				paths.append("%s/%s" % [BACKGROUND_ASSET_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths

func _repeat_assets_to_count(source: Array, count: int) -> Array:
	var result := []
	if source.is_empty() or count <= 0:
		return result
	for i in count:
		result.append(source[i % source.size()])
	return result

func _shuffle_with_rng(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp

func _append_clustered_assets(layout: Array, assets: Array, rng: RandomNumberGenerator, label: String, count: int, centers: Array, pixel_range: Vector2, spread: Vector2) -> void:
	if assets.is_empty() or centers.is_empty():
		return
	for i in count:
		var center: Vector2 = centers[rng.randi_range(0, centers.size() - 1)]
		var data := {
			"name": "%s%02d" % [label, i + 1],
			"path": assets[i % assets.size()],
			"pos": Vector3(
				clampf(center.x + rng.randf_range(-spread.x, spread.x), -8.1, 8.1),
				0.0,
				clampf(center.y + rng.randf_range(-spread.y, spread.y), 1.25, 4.45)
			),
			"pixel": rng.randf_range(pixel_range.x, pixel_range.y),
		}
		if label == "Grass" or label == "Bush" or label == "Tree":
			var strength_range := SWAY_STRENGTH_TREE
			if label == "Grass":
				strength_range = SWAY_STRENGTH_GRASS
			elif label == "Bush":
				strength_range = SWAY_STRENGTH_BUSH
			data["sway"] = true
			data["sway_strength"] = rng.randf_range(strength_range.x, strength_range.y)
			data["sway_speed"] = rng.randf_range(SWAY_SPEED.x, SWAY_SPEED.y)
			data["sway_phase"] = rng.randf_range(0.0, TAU)
		layout.append(data)

func _pixel_multiplier(path: String) -> float:
	var file_name := path.get_file().to_lower()
	if file_name.begins_with("tree"):
		return 2.0
	match file_name:
		"element7.png":
			return 0.8
		"element1.png":
			return 0.6
		"building5.png":
			return 2.0
		_:
			return 1.0

func _canvas_surface_y() -> float:
	return active_canvas.position.y if active_canvas != null else 0.0

func _pin_decoration_bottoms() -> void:
	if decorations == null:
		return
	for child in decorations.get_children():
		var sprite := child as Sprite3D
		if sprite == null:
			continue
		_pin_sprite_bottom_to_canvas(sprite)

func _pin_sprite_bottom_to_canvas(sprite: Sprite3D) -> void:
	if sprite.texture == null:
		return
	var bottom_local_y := _visible_bottom_local_y(sprite)
	var rotation_cos := absf(cos(sprite.rotation.x))
	var pinned_y := _canvas_surface_y() - bottom_local_y * rotation_cos
	if absf(sprite.position.y - pinned_y) > 0.0001:
		sprite.position.y = pinned_y

func _update_decoration_angles() -> void:
	if decorations == null:
		return
	for child in decorations.get_children():
		var sprite := child as Sprite3D
		if sprite == null:
			continue
		sprite.rotation_degrees = Vector3(-DECORATION_LEAN_DEG, 0.0, 0.0)

func _sync_decoration_shadows() -> void:
	_sync_shadow_group(get_node_or_null("OutsideDecorations3D") as Node3D, "DecorationShadows3D")
	_sync_shadow_group(get_node_or_null("CanvasDecorations3D") as Node3D, "CanvasDecorationShadows3D")
	_sync_shadow_group(get_node_or_null("ForegroundDecorations3D") as Node3D, "ForegroundDecorationShadows3D")

func _sync_shadow_group(source_root: Node3D, shadow_root_name: String) -> void:
	if source_root == null:
		return
	var disable_real_shadow := source_root.name == "CanvasDecorations3D" \
		or source_root.name == "ForegroundDecorations3D"
	var shadow_root := _ensure_shadow_root(shadow_root_name)
	var wanted := {}
	for child in source_root.get_children():
		var sprite := child as Sprite3D
		if sprite == null or sprite.texture == null:
			continue
		if disable_real_shadow:
			sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow_name := "Shadow_%s" % sprite.name
		wanted[shadow_name] = true
		var shadow := shadow_root.get_node_or_null(shadow_name) as MeshInstance3D
		if shadow == null:
			shadow = MeshInstance3D.new()
			shadow.name = shadow_name
			shadow.mesh = PlaneMesh.new()
			shadow.material_override = _get_soft_shadow_material()
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shadow.set_meta("startx_generated_soft_shadow", true)
			shadow_root.add_child(shadow)
			_mark_editor_owned(shadow)
		_update_shadow_for_sprite(shadow, sprite)
	for child in shadow_root.get_children():
		if child.has_meta("startx_generated_soft_shadow") and not wanted.has(child.name):
			child.queue_free()

func _ensure_shadow_root(root_name: String) -> Node3D:
	var root := get_node_or_null(root_name) as Node3D
	if root != null:
		return root
	root = Node3D.new()
	root.name = root_name
	add_child(root)
	_mark_editor_owned(root)
	return root

func _update_shadow_for_sprite(shadow: MeshInstance3D, sprite: Sprite3D) -> void:
	var tex := sprite.texture
	if tex == null:
		return
	var visual_w := float(tex.get_width()) * sprite.pixel_size * absf(sprite.scale.x)
	var visual_h := float(tex.get_height()) * sprite.pixel_size * absf(sprite.scale.y)
	var width := maxf(visual_w * _shadow_width_factor(sprite.name), 0.22)
	var depth := maxf(visual_h * _shadow_depth_factor(sprite.name), 0.08)
	var sprite_pos := shadow.get_parent_node_3d().to_local(sprite.global_transform.origin)
	var basis := Basis().scaled(Vector3(width, 1.0, depth))
	shadow.transform = Transform3D(basis, Vector3(sprite_pos.x + 0.1, _canvas_surface_y() + 0.012, sprite_pos.z + 0.13))
	shadow.material_override = _get_soft_shadow_material()
	shadow.visible = sprite.visible

func _shadow_width_factor(node_name: String) -> float:
	if node_name.begins_with("Tree"):
		return 0.58
	if node_name.begins_with("Grass"):
		return 0.78
	if node_name.begins_with("Bush"):
		return 0.74
	if node_name.begins_with("Building"):
		return 0.55
	return 0.62

func _shadow_depth_factor(node_name: String) -> float:
	if node_name.begins_with("Tree"):
		return 0.14
	if node_name.begins_with("Grass"):
		return 0.16
	if node_name.begins_with("Bush"):
		return 0.18
	if node_name.begins_with("Building"):
		return 0.13
	return 0.16

func _get_soft_shadow_material() -> ShaderMaterial:
	if _soft_shadow_material != null:
		return _soft_shadow_material
	_soft_shadow_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 shadow_color : source_color = vec4(0.33, 0.33, 0.33, 0.26);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float feather = smoothstep(1.0, 0.08, dot(p, p));
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * feather;
}
"""
	_soft_shadow_material.shader = shader
	_soft_shadow_material.set_shader_parameter("shadow_color", Color(0.33, 0.33, 0.33, 0.26 * BACKGROUND_FADE_ALPHA))
	return _soft_shadow_material

func _visible_bottom_local_y(sprite: Sprite3D) -> float:
	var texture: Texture2D = sprite.texture
	if texture == null:
		return 0.0
	var height: int = texture.get_height()
	if height <= 0:
		return 0.0
	var bottom_row: int = _visible_bottom_row(texture)
	var transparent_rows_below: int = maxi(0, height - 1 - bottom_row)
	var texture_height: float = float(height) * sprite.pixel_size * absf(sprite.scale.y)
	var transparent_height_below: float = float(transparent_rows_below) * sprite.pixel_size * absf(sprite.scale.y)
	return -texture_height * 0.5 + transparent_height_below

func _visible_bottom_row(texture: Texture2D) -> int:
	var cache_key: String = texture.resource_path
	if cache_key == "":
		cache_key = str(texture.get_instance_id())
	if _visible_bottom_cache.has(cache_key):
		return int(_visible_bottom_cache[cache_key])
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_visible_bottom_cache[cache_key] = texture.get_height() - 1
		return int(_visible_bottom_cache[cache_key])
	if image.is_compressed():
		var err: int = image.decompress()
		if err != OK:
			_visible_bottom_cache[cache_key] = texture.get_height() - 1
			return int(_visible_bottom_cache[cache_key])
	var width: int = image.get_width()
	var height: int = image.get_height()
	var bottom_row: int = height - 1
	for y in range(height - 1, -1, -1):
		for x in width:
			if image.get_pixel(x, y).a > 0.02:
				bottom_row = y
				_visible_bottom_cache[cache_key] = bottom_row
				return bottom_row
	_visible_bottom_cache[cache_key] = height - 1
	return int(_visible_bottom_cache[cache_key])
