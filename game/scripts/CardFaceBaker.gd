extends Node
class_name CardFaceBaker
## 把现有 Card/PackCard 的 _draw（2D 像素美术）烘焙成贴图，供 3D 网格做 albedo。

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const FACE := 1024                # 烘焙分辨率（卡面 180×180 → 放大到 1024）

var _cache: Dictionary = {}       # key -> Texture2D

func _ready() -> void:
	pass

func key_for(card) -> String:
	return "%s|%d|%d|%d|%s" % [
		card.card_id, card.uses_left,
		int(card.cdef.get("capacity", 0)), int(card.cdef.get("salary", 0)),
		card._card_name()]

# 返回该卡的烘焙贴图（已缓存即同步返回；否则烘一次，需 await）
func bake(card) -> Texture2D:
	var k := key_for(card)
	if _cache.has(k):
		return _cache[k]
	# 每次烘焙使用独立 Viewport。共享 Viewport 时，并发生成的卡牌会叠在一起，
	# 导致先请求的卡错误捕获到后请求卡牌的画面。
	var vp := _new_bake_viewport()
	var src = CardScript.new()
	src.setup(card.card_id)
	src.uses_left = card.uses_left
	# Card 本地尺寸 180×180 → 缩放铺满 FACE
	var holder := Node2D.new()
	holder.scale = Vector2(float(FACE) / 180.0, float(FACE) / 180.0)
	holder.add_child(src)
	vp.add_child(holder)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	vp.queue_free()
	_cache[k] = tex
	return tex

# 烘焙卡包封面（同一卡包的实际内容可能不同，缓存键必须包含内容）
func bake_pack(pack_id: String, pack_name: String, contents: Array) -> Texture2D:
	var content_ids := PackedStringArray()
	for id in contents:
		content_ids.append(String(id))
	var k := "pack:%s|%s" % [pack_id, ",".join(content_ids)]
	if _cache.has(k):
		return _cache[k]
	var vp := _new_bake_viewport()
	var src = PackCardScript.new()
	src.setup(pack_id, pack_name, contents)
	var holder := Node2D.new()
	holder.scale = Vector2(float(FACE) / PackCardScript.W, float(FACE) / PackCardScript.H)
	holder.add_child(src)
	vp.add_child(holder)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	vp.queue_free()
	_cache[k] = tex
	return tex

func _new_bake_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(FACE, FACE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.disable_3d = true
	add_child(vp)
	return vp
