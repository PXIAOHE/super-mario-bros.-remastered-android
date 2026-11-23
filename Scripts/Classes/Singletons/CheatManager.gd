extends CanvasLayer
## 金手指 / Cheat panel
## Registered as an autoload singleton named CheatManager in project.godot.
## Builds its whole UI in code so no scene files need editing.
## Player.gd calls tick_player() every physics frame and damage() checks god_mode.
## Deliberately duck-typed: no static reference to the Player class, so there is
## no autoload <-> class_name dependency cycle at compile time.
##
## UI notes:
## - The game ships a chunky bitmap theme, so this panel gets its own compact
##   Theme (default font size only) to keep every row small.
## - Labels are UPPERCASE only: the project's bitmap font has no lowercase glyphs.

const SPEED_MULTIPLIER := 2.0
const MAX_LIVES := 99
const FONT_BASE := 12
const TOGGLE_W := 96
const TOGGLE_H := 30
const PANEL_W := 230

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
var _theme: Theme = null
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
	return int(max(9.0, float(x) * _ui))


func _build_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_ui = clampf(vs.y / 1080.0, 0.6, 1.4)
	_theme = Theme.new()
	_theme.default_font_size = _fs(FONT_BASE)

	var root := Control.new()
	root.name = "CheatRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_toggle = Button.new()
	_toggle.name = "CheatToggle"
	_toggle.text = "CHEAT"
	_toggle.theme = _theme
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.position = Vector2(4, 4) * _ui
	_toggle.custom_minimum_size = Vector2(TOGGLE_W, TOGGLE_H) * _ui
	_toggle.size = Vector2(TOGGLE_W, TOGGLE_H) * _ui
	_toggle.modulate = Color(1, 1, 1, 0.72)
	_toggle.pressed.connect(_on_toggle_pressed)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.name = "CheatPanel"
	_panel.theme = _theme
	_panel.visible = false
	_panel.position = Vector2(4, TOGGLE_H + 8) * _ui
	root.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(PANEL_W * _ui, minf(vs.y * 0.72, 560 * _ui))
	_panel.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, _fs(6))
	scroll.add_child(pad)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", _fs(1))
	pad.add_child(vb)

	vb.add_child(_make_label("CHEATS"))
	vb.add_child(_make_button("CLOSE", func() -> void: _panel.visible = false))
	vb.add_child(_make_check("GOD MODE", func(on: bool) -> void: god_mode = on))
	vb.add_child(_make_check("INF LIVES", func(on: bool) -> void: inf_lives = on))
	vb.add_child(_make_check("FREEZE TIME", func(on: bool) -> void: _on_freeze_toggled(on)))
	vb.add_child(_make_check("SUPER JUMP", func(on: bool) -> void: super_jump = on))
	vb.add_child(_make_check("FAST RUN", func(on: bool) -> void: fast_run = on))
	vb.add_child(_make_check("STAR ALWAYS", func(on: bool) -> void: star_mode = on))
	vb.add_child(_make_button("+99 COINS", func() -> void: give_coins()))
	vb.add_child(_make_button("POWER FIRE", func() -> void: set_power("Fire")))
	vb.add_child(_make_button("POWER BIG", func() -> void: set_power("Big")))


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = _theme
	return l


func _make_check(text: String, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.theme = _theme
	c.focus_mode = Control.FOCUS_NONE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.toggled.connect(cb)
	return c


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = _theme
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
