extends CanvasLayer
## 金手指 / Cheat panel  (autoload singleton: CheatManager)
##
## Design notes:
## - Whole UI built in code; no .tscn edits at all.
## - Duck typed on purpose: no `Player` type hints anywhere, so the autoload
##   never creates a compile-time dependency cycle with `class_name Player`.
## - Own compact Theme: the game's bitmap theme makes every row huge.
## - UPPERCASE labels only: the project's bitmap font has no lowercase glyphs.
## - Toggle state persisted to user://cheats.cfg (survives app restarts).
##
## Player.gd hooks:
##   _physics_process() -> CheatManager.tick_player(self)
##   damage()           -> early return when CheatManager.god_mode
##   calculate_jump_height() -> multiplied by CheatManager.jump_multiplier

const SPEED_MULTIPLIER := 2.0
const MAX_LIVES := 99
const FONT_BASE := 12
const TOGGLE_W := 96
const TOGGLE_H := 30
const PANEL_W := 240
const CFG_PATH := "user://cheats.cfg"
const LEVELS_VISITED_LEN := 52      # SaveManager.SAVE_TEMPLATE["LevelsVisited"] 的长度
const BOO_LEVELS_LEN := 8

var jump_multiplier := 2.0

var god_mode := false          # 免疫伤害
var inf_lives := false         # 无限命
var freeze_time := false       # 时间冻结
var super_jump := false        # 超级跳
var fast_run := false          # 加速跑
var star_mode := false         # 无敌星常驻
var noclip := false            # 穿墙
var freeze_enemies := false    # 敌人冻结

var _player = null
var _panel: PanelContainer = null
var _toggle: Button = null
var _theme: Theme = null
var _unlock_btn: Button = null
var _unlock_armed := false
var _ui := 1.0
var _cfg := ConfigFile.new()
var _enemy_tick := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cfg()
	_build_ui()


func _process(delta: float) -> void:
	if freeze_time:
		Global.can_time_tick = false
	if inf_lives and Global.lives < MAX_LIVES:
		Global.lives = MAX_LIVES
	if star_mode and is_instance_valid(_player):
		var st = _player.get_node_or_null("StarTimer")
		if st != null and st.is_stopped():
			st.start()
		_player.is_invincible = true
	if freeze_enemies:
		_enemy_tick -= delta
		if _enemy_tick <= 0.0:
			_enemy_tick = 0.25
			_apply_enemy_freeze()


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
	if noclip and not p.has_meta("cheat_noclip_applied"):
		p.set_meta("cheat_noclip_applied", true)
		set_noclip(true)


func _current_player():
	if is_instance_valid(_player):
		return _player
	for n in get_tree().root.find_children("*", "CharacterBody2D", true, false):
		if n.has_method("get_power_up"):
			_player = n
			return n
	return null


func _enemy_nodes() -> Array:
	var out: Array = []
	if not is_instance_valid(Global.current_level):
		return out
	for n in Global.current_level.find_children("*", "", true, false):
		if n.has_method("damage_player") and n.has_method("die") and not n.is_queued_for_deletion():
			out.append(n)
	return out


# ------------------------------------------------------------------ actions

func give_coins() -> void:
	Global.coins = 99


func add_time() -> void:
	Global.time += 100


func set_power(power_name: String) -> void:
	var p = _current_player()
	if p != null:
		p.get_power_up(power_name)


func give_hammer() -> void:
	var p = _current_player()
	if p != null:
		p.hammer_get()


func kill_all_enemies() -> void:
	for n in _enemy_nodes():
		n.die()


func _apply_enemy_freeze() -> void:
	for n in _enemy_nodes():
		n.set_physics_process(not freeze_enemies)
		n.set_process(not freeze_enemies)


func set_noclip(on: bool) -> void:
	noclip = on
	var p = _current_player()
	if p == null:
		return
	var sm = p.state_machine
	if sm == null:
		return
	if on:
		var cur = sm.state
		if cur == null or String(cur.name) in ["Normal", "NoClip"]:
			sm.transition_to("NoClip")
	elif sm.is_state("NoClip"):
		sm.transition_to("Normal")
		p.can_hurt = true   # NoClip.exit() 里上游把 can_hurt 写成 false


## 解锁全部关卡：直接改存档 JSON 的 LevelsVisited / ClearedBooLevels。
func unlock_all_levels() -> void:
	var campaign: String = Global.current_campaign
	var path: String = Global.config_path.path_join("saves/" + campaign + ".sav")
	var data = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			data = JSON.parse_string(f.get_as_text())
			f.close()
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	var visited := "1".repeat(LEVELS_VISITED_LEN)
	data["LevelsVisited"] = visited
	data["ClearedBooLevels"] = "1".repeat(BOO_LEVELS_LEN)
	SaveManager.visited_levels = visited
	SaveManager.write_save_to_file(data, path)
	Global.log_comment("CheatManager: all levels unlocked")


# --------------------------------------------------------------- 持久化

const _BOOL_KEYS := [
	"god_mode", "inf_lives", "freeze_time", "super_jump",
	"fast_run", "star_mode", "noclip", "freeze_enemies",
]


func _load_cfg() -> void:
	if _cfg.load(CFG_PATH) != OK:
		return
	god_mode = bool(_cfg.get_value("cheats", "god_mode", false))
	inf_lives = bool(_cfg.get_value("cheats", "inf_lives", false))
	freeze_time = bool(_cfg.get_value("cheats", "freeze_time", false))
	super_jump = bool(_cfg.get_value("cheats", "super_jump", false))
	fast_run = bool(_cfg.get_value("cheats", "fast_run", false))
	star_mode = bool(_cfg.get_value("cheats", "star_mode", false))
	noclip = bool(_cfg.get_value("cheats", "noclip", false))
	freeze_enemies = bool(_cfg.get_value("cheats", "freeze_enemies", false))


func _save_cfg() -> void:
	for k in _BOOL_KEYS:
		_cfg.set_value("cheats", k, bool(get(k)))
	_cfg.save(CFG_PATH)


func _set_flag(key: String, on: bool) -> void:
	set(key, on)
	_save_cfg()


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
	scroll.custom_minimum_size = Vector2(PANEL_W * _ui, minf(vs.y * 0.72, 620 * _ui))
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

	var title := Label.new()
	title.text = "CHEATS"
	title.theme = _theme
	vb.add_child(title)
	vb.add_child(_make_button("CLOSE", func() -> void: _panel.visible = false))

	# ---- 开关 ----
	vb.add_child(_make_check("GOD MODE", god_mode, func(on: bool) -> void: _set_flag("god_mode", on)))
	vb.add_child(_make_check("INF LIVES", inf_lives, func(on: bool) -> void: _set_flag("inf_lives", on)))
	vb.add_child(_make_check("FREEZE TIME", freeze_time, func(on: bool) -> void: _on_freeze_toggled(on)))
	vb.add_child(_make_check("SUPER JUMP", super_jump, func(on: bool) -> void: _set_flag("super_jump", on)))
	vb.add_child(_make_check("FAST RUN", fast_run, func(on: bool) -> void: _set_flag("fast_run", on)))
	vb.add_child(_make_check("STAR ALWAYS", star_mode, func(on: bool) -> void: _set_flag("star_mode", on)))
	vb.add_child(_make_check("NOCLIP", noclip, func(on: bool) -> void: _on_noclip_toggled(on)))
	vb.add_child(_make_check("FREEZE ENEMIES", freeze_enemies, func(on: bool) -> void: _on_freeze_enemies_toggled(on)))

	# ---- 一次性动作 ----
	vb.add_child(_make_button("POWER FIRE", func() -> void: set_power("Fire")))
	vb.add_child(_make_button("POWER BIG", func() -> void: set_power("Big")))
	vb.add_child(_make_button("HAMMER", func() -> void: give_hammer()))
	vb.add_child(_make_button("+99 COINS", func() -> void: give_coins()))
	vb.add_child(_make_button("+100 TIME", func() -> void: add_time()))
	vb.add_child(_make_button("KILL ALL ENEMIES", func() -> void: kill_all_enemies()))

	_unlock_btn = _make_button("UNLOCK ALL LEVELS", func() -> void: _on_unlock_pressed())
	vb.add_child(_unlock_btn)


func _make_check(text: String, value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.theme = _theme
	c.focus_mode = Control.FOCUS_NONE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.set_pressed_no_signal(value)
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
	_save_cfg()
	if not on:
		Global.can_time_tick = true


func _on_noclip_toggled(on: bool) -> void:
	_set_flag("noclip", on)
	set_noclip(on)


func _on_freeze_enemies_toggled(on: bool) -> void:
	_set_flag("freeze_enemies", on)
	if not on:
		_apply_enemy_freeze()   # 解冻：把所有敌人进程恢复


func _on_unlock_pressed() -> void:
	if _unlock_btn == null:
		return
	if not _unlock_armed:
		_unlock_armed = true
		_unlock_btn.text = "TAP AGAIN TO CONFIRM"
		await get_tree().create_timer(3.0).timeout
		if _unlock_armed:
			_unlock_armed = false
			_unlock_btn.text = "UNLOCK ALL LEVELS"
		return
	_unlock_armed = false
	unlock_all_levels()
	_unlock_btn.text = "LEVELS OPENED"
	await get_tree().create_timer(2.0).timeout
	if _unlock_btn != null:
		_unlock_btn.text = "UNLOCK ALL LEVELS"


func _on_toggle_pressed() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	_toggle.modulate = Color(1, 1, 1, 1.0) if _panel.visible else Color(1, 1, 1, 0.72)
