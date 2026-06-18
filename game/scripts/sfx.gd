extends Node
## 全局音效。menu.ogg 自动挂到所有按钮（菜单/战斗 UI 等）；其余由游戏逻辑显式调用。

const FILES := {
	"menu": preload("res://assets/sounds/menu.ogg"),                              # 所有按钮点击
	"grab": preload("res://assets/sounds/grab card.ogg"),                         # 拿起卡
	"human_down": preload("res://assets/sounds/human down.ogg"),                  # 人类牌放下
	"down": preload("res://assets/sounds/down.ogg"),                              # 创始人/员工/客户牌放下
	"resource_down": preload("res://assets/sounds/facility and resource down.ogg"), # 资源/设施等放下
	"cash_down": preload("res://assets/sounds/cash down.ogg"),                    # 现金牌放下
	"unpack": preload("res://assets/sounds/unpack.ogg"),                          # 拆包
	"battle_start": preload("res://assets/sounds/battlestart.ogg"),               # 战斗开始
	"battle_end": preload("res://assets/sounds/battleend.ogg"),                   # 战斗结束
	"aha": preload("res://assets/sounds/aha.ogg"),                                # 创始人灵感气泡
	"founder": preload("res://assets/sounds/founder.ogg"),                        # 创始人落地
	"hit": preload("res://assets/sounds/hit.ogg"),                                # 战斗伤害数字
}

var _streams: Dictionary = {}
var _players: Array = []
var _i: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停/战斗时也能出声
	for k in FILES:
		var s = FILES[k]
		if s != null:
			_streams[k] = s
	for _n in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = Settings.sfx_volume_db()
		add_child(p)
		_players.append(p)
	Settings.sfx_volume_changed.connect(_on_sfx_volume_changed)
	# 自动给「现在及以后」出现的所有按钮接上点击音效
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons(get_tree().root)

func play(sfx_name: String, volume_ratio: float = 1.0) -> void:
	if not _streams.has(sfx_name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_i]
	_i = (_i + 1) % _players.size()
	p.stream = _streams[sfx_name]
	var base_vol := Settings.sfx_volume_db()
	if volume_ratio <= 0.0:
		p.volume_db = -80.0
	elif volume_ratio < 1.0:
		p.volume_db = base_vol + 20.0 * (log(volume_ratio) / log(10.0))
	else:
		p.volume_db = base_vol
	p.play()

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_on_button_pressed):
		n.pressed.connect(_on_button_pressed)

func _hook_buttons(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_on_button_pressed):
		n.pressed.connect(_on_button_pressed)
	for c in n.get_children():
		_hook_buttons(c)

func _on_button_pressed() -> void:
	play("menu")

func _on_sfx_volume_changed(_value: float) -> void:
	var volume_db := Settings.sfx_volume_db()
	for p in _players:
		p.volume_db = volume_db
