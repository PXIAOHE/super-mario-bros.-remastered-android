extends CanvasLayer
## 金手指 / Cheat panel
## Registered as an autoload singleton named CheatManager in project.godot.
## Builds its whole UI in code so no scene files need editing.
## Player.gd calls tick_player() every physics frame and damage() checks god_mode.
## Deliberately duck-typed: no static reference to the Player class, so there is
## no autoload <-> class_name dependency cycle at compile time.

const SPEED_MULTIPLIER := 2.0
const MAX_LIVES := 99
const FONT_BASE := 14
const TOGGLE_W := 104
const TOGGLE_H := 34

var jump_multiplier := 2.0     # 超级跳倍率

var god_mode := false          # 免疫伤害（不掉状态、不死亡）
var inf_lives := false         # 无限命
var freeze_time := false       # 时间冻结
var super_jump := false        # 超级跳
var fast_run := false          # 加速跑
var star_mode := false         # 无敌星常驻

var _player = null
var _panel: PanelContainer = null
var _toggle: Button = null
var _ui := 1.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(_delta: float) -> void:
	if freeze_time:
		Global.can_time_tick = false
	if inf_lives and Global.lives < MAX_LIVES:
		Global.lives = MAX_LIVES
	if star_mode and is_instance_valid(_player):
		_player.is_invincible = true


## Called from Player._physics_process() every physics frame.
func tick_player(p) -> void:
	if not is_instance_valid(p):
		return
	_player = p
	if not p.has_meta("cheat_base_speeds"):
		p.set_meta("cheat_base_speeds", {"walk": p.WALK_SPEED, "run": p.RUN_SPEED})
	var base: Dictionary = p.get_meta("cheat_base_speeds")
	var mult := SPEED_MULTIPLIER if fast_run else 1.0
	p.WALK_SPEED = float(base["walk"]) * mult
	p.RUN_SPEED = float(base["run"]) * mult


func _current_player():
	if is_instance_valid(_player):
		return _player
	for n in get_tree().root.find_children("*", "CharacterBody2D", true, false):
		if n.has_method("get_power_up"):
			_player = n
			return n
	return null


# ------------------------------------------------------------------ actions

func give_coins() -> void:
	Global.coins = 99


func set_power(power_name: String) -> void:
	var p = _current_player()
	if p != null:
		p.get_power_up(power_name)


# ---------------------------------------------------------------------- UI

func _fs(x: int) -> int:
	return int(max(10.0, float(x) * _ui))


func _build_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_ui = clampf(vs.y / 720.0, 0.75, 2.5)

	var root := Control.new()
	root.name = "CheatRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_toggle = Button.new()
	_toggle.name = "CheatToggle"
	_toggle.text = "CHEAT"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_font_size_override("font_size", _fs(FONT_BASE))
	_toggle.position = Vector2(6, 6) * _ui
	_toggle.size = Vector2(TOGGLE_W, TOGGLE_H) * _ui
	_toggle.modulate = Color(1, 1, 1, 0.72)
	_toggle.pressed.connect(_on_toggle_pressed)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.name = "CheatPanel"
	_panel.visible = false
	_panel.position = Vector2(6, TOGGLE_H + 12) * _ui
	root.add_child(_panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, _fs(8))
	_panel.add_child(pad)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _fs(2))
	pad.add_child(vb)

	var title := Label.new()
	title.text = "CHEATS"
	title.add_theme_font_size_override("font_size", _fs(FONT_BASE + 2))
	vb.add_child(title)

	vb.add_child(_make_check("GOD - no damage", func(on: bool) -> void: god_mode = on))
	vb.add_child(_make_check("INF LIVES", func(on: bool) -> void: inf_lives = on))
	vb.add_child(_make_check("FREEZE TIME", func(on: bool) -> void: _on_freeze_toggled(on)))
	vb.add_child(_make_check("SUPER JUMP x2", func(on: bool) -> void: super_jump = on))
	vb.add_child(_make_check("FAST RUN x2", func(on: bool) -> void: fast_run = on))
	vb.add_child(_make_check("STAR - always", func(on: bool) -> void: star_mode = on))

	vb.add_child(_make_button("+99 COINS", func() -> void: give_coins()))
	vb.add_child(_make_button("POWER: FIRE", func() -> void: set_power("Fire")))
	vb.add_child(_make_button("POWER: BIG", func() -> void: set_power("Big")))
	vb.add_child(_make_button("CLOSE", func() -> void: _panel.visible = false))


func _make_check(text: String, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", _fs(FONT_BASE))
	c.toggled.connect(cb)
	return c


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", _fs(FONT_BASE))
	b.pressed.connect(cb)
	return b


func _on_freeze_toggled(on: bool) -> void:
	freeze_time = on
	if not on:
		Global.can_time_tick = true


func _on_toggle_pressed() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	_toggle.modulate = Color(1, 1, 1, 1.0) if _panel.visible else Color(1, 1, 1, 0.72)
