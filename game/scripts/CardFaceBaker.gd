extends Node
class_name CardFaceBaker
## 把现有 Card 的 _draw（2D 像素美术）烘焙成贴图，供 3D 卡牌网格做 albedo。
## 复用 Card.gd 全部美术，按视觉态缓存，每种卡面只烘一次。

const CardScript = preload("res://scripts/Card.gd")
const PackCardScript = preload("res://scripts/PackCard.gd")
const FACE := 256                 # 烘焙分辨率（卡面 180×180 → 放大到 256）

var _cache: Dictionary = {}       # key -> Texture2D
var _vp: SubViewport

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(FACE, FACE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.disable_3d = true
	add_child(_vp)

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
	var src = CardScript.new()
	src.setup(card.card_id)
	src.uses_left = card.uses_left
	# Card 本地尺寸 180×180 → 缩放铺满 FACE
	var holder := Node2D.new()
	holder.scale = Vector2(float(FACE) / 180.0, float(FACE) / 180.0)
	holder.add_child(src)
	_vp.add_child(holder)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	holder.queue_free()
	_cache[k] = tex
	return tex

# 烘焙卡包封面（按 pack_id 缓存）
func bake_pack(pack_id: String, pack_name: String, contents: Array) -> Texture2D:
	var k := "pack:" + pack_id
	if _cache.has(k):
		return _cache[k]
	var src = PackCardScript.new()
	src.setup(pack_id, pack_name, contents)
	var holder := Node2D.new()
	holder.scale = Vector2(float(FACE) / PackCardScript.W, float(FACE) / PackCardScript.H)
	holder.add_child(src)
	_vp.add_child(holder)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	holder.queue_free()
	_cache[k] = tex
	return tex
