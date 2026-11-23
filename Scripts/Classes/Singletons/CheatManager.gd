extends CanvasLayer
## 金手指面板（autoload 单例：CheatManager）
##
## 设计要点：
## - UI 全部代码构建，不碰任何 .tscn。
## - 鸭子类型：不写 `Player` 类型标注，避免 autoload 与 `class_name Player` 形成编译期循环依赖。
## - 自带紧凑 Theme + 打包的中文字体（游戏自带像素字体没有中文）。
## - 战斗类开关持久化到 user://cheats.cfg；自动跑/慢速不持久化。
##
## Player.gd 挂点：
##   _physics_process() -> CheatManager.tick_player(self)
##   damage()           -> 无敌模式下直接 return
##   calculate_jump_height() -> 乘以 CheatManager.jump_multiplier

const SPEED_MULTIPLIER := 2.0
const MAX_LIVES := 99
const FONT_BASE := 13
const TOGGLE_W := 108
const TOGGLE_H := 32
const PANEL_W := 268
const CFG_PATH := "user://cheats.cfg"
const LEVELS_VISITED_LEN := 52
const BOO_LEVELS_LEN := 8
const WORLDS_PER_CAMPAIGN := {"SMB1": 8, "SMBLL": 13, "SMBS": 8, "SMBANN": 8}
const LEVELS_PER_WORLD := 4
const SLOW_TIME_SCALE := 0.5
const FONT_PATH := "res://Scripts/Classes/Singletons/CheatFont.otf"

var jump_multiplier := 2.0

# --- 持久化开关 ---
var god_mode := false
var inf_lives := false
var freeze_time := false
var super_jump := false
var fast_run := false
var star_mode := false
var noclip := false
var freeze_enemies := false

# --- 不持久化 ---
var auto_run := false
var slow_motion := false

var _player = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _toggle: Button = null
var _theme: Theme = null
var _unlock_btn: Button = null
var _scale_btn: Button = null
var _unlock_armed := false
var _ui := 1.0
var _cfg := ConfigFile.new()
var _enemy_tick := 0.0
var _waypoint = null
var _waypoint_tag := ""

# 拖动
var _dragging := false
var _drag_moved := 0.0
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cfg()
	_install_cjk_fallback()
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


## 由 Player._physics_process 每帧调用
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


# ------------------------------------------------------------------ 动作

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
		p.can_hurt = true


# ---- 存点 / 回点 ----

func set_waypoint() -> void:
	var p = _current_player()
	if p == null:
		return
	_waypoint = p.global_position
	_waypoint_tag = _level_tag()


func goto_waypoint() -> void:
	var p = _current_player()
	if p == null or _waypoint == null:
		return
	if _waypoint_tag != _level_tag():
		return
	p.teleport_player(_waypoint)


func _level_tag() -> String:
	return str(Global.current_campaign) + "/" + str(Global.world_num) + "-" + str(Global.level_num)


# ---- 自动跑 ----

func set_auto_run(on: bool) -> void:
	auto_run = on
	if on:
		Input.action_press("move_right_0")
		Input.action_press("run_0")
	else:
		Input.action_release("move_right_0")
		Input.action_release("run_0")


# ---- 慢速 ----

func set_slow_motion(on: bool) -> void:
	slow_motion = on
	Engine.time_scale = SLOW_TIME_SCALE if on else 1.0
	if _scale_btn != null:
		_scale_btn.text = "速度：慢速" if on else "速度：正常"


# ---- 跳关 ----

func warp_level(delta_world: int, delta_level: int) -> void:
	if Global.current_game_mode != Global.GameMode.CAMPAIGN:
		return
	var world_max: int = int(WORLDS_PER_CAMPAIGN.get(str(Global.current_campaign), 8))
	var w: int = clampi(int(Global.world_num) + delta_world, 1, world_max)
	var l: int = clampi(int(Global.level_num) + delta_level, 1, LEVELS_PER_WORLD)
	var path: String = "res://Scenes/Levels/" + str(Global.current_campaign) + "/World" + str(w) + "/" + str(w) + "-" + str(l) + ".tscn"
	if not ResourceLoader.exists(path):
		return
	Global.world_num = w
	Global.level_num = l
	LevelTransition.level_to_transition_to = path
	Level.first_load = true
	Checkpoint.passed_checkpoints.clear()
	SaveManager.write_save()
	get_tree().paused = false
	Global.transition_to_scene("res://Scenes/Levels/LevelTransition.tscn")


# ---- 全关卡解锁 ----

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


# ---------------------------------------------------------- 按钮拖动

func _on_toggle_down() -> void:
	_dragging = true
	_drag_moved = 0.0
	_drag_offset = _toggle.position - get_viewport().get_mouse_position()


func _on_toggle_up() -> void:
	_dragging = false
	if _drag_moved < 12.0 * _ui:
		_on_toggle_pressed()


func _input(event) -> void:
	if not _dragging or _toggle == null:
		return
	var dragging_now := false
	if event is InputEventScreenDrag:
		dragging_now = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		dragging_now = true
	if not dragging_now:
		return
	var vs := get_viewport().get_visible_rect().size
	var target: Vector2 = get_viewport().get_mouse_position() + _drag_offset
	target.x = clampf(target.x, 0.0, maxf(0.0, vs.x - _toggle.size.x))
	target.y = clampf(target.y, 0.0, maxf(0.0, vs.y - _toggle.size.y))
	_drag_moved += (target - _toggle.position).length()
	_toggle.position = target
	if _panel != null:
		_panel.position = Vector2(target.x, target.y + _toggle.size.y + 6 * _ui)


# ---------------------------------------------------------------------- UI

## 把游戏主题里所有字体项换成打包的中文字体，并设置 ThemeDB 兜底字体。
## 注意：绝不能对游戏自带的位图字体设置 FontFile.fallbacks —— 那会让位图字体丢字形，
## 整个界面变成「十六进制方框」。只能整体替换主题里的字体资源。
func _install_cjk_fallback() -> void:
	var cjk = load(FONT_PATH)
	if not (cjk is Font):
		return
	ThemeDB.fallback_font = cjk
	var path = ProjectSettings.get_setting("gui/theme/custom", "")
	if not (path is String) or path == "":
		return
	var th = load(path)
	if th is Theme:
		_replace_theme_fonts(th, cjk)


func _replace_theme_fonts(th: Theme, cjk: Font) -> void:
	var replaced := false
	for prop in th.get_property_list():
		var n: String = str(prop.get("name", ""))
		if n.find("/fonts/") == -1:
			continue
		th.set(n, cjk)
		replaced = true
	if not replaced:
		th.default_font = cjk


func _fs(x: int) -> int:
	return int(max(9.0, float(x) * _ui))


func _build_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_ui = clampf(vs.y / 1080.0, 0.6, 1.4)
	_theme = Theme.new()
	_theme.default_font_size = _fs(FONT_BASE)
	var f = load(FONT_PATH)
	if f is Font:
		_theme.default_font = f

	var root := Control.new()
	root.name = "CheatRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_toggle = Button.new()
	_toggle.name = "CheatToggle"
	_toggle.text = "金手指"
	_toggle.theme = _theme
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.position = Vector2(4, 4) * _ui
	_toggle.custom_minimum_size = Vector2(TOGGLE_W, TOGGLE_H) * _ui
	_toggle.size = Vector2(TOGGLE_W, TOGGLE_H) * _ui
	_toggle.modulate = Color(1, 1, 1, 0.72)
	_toggle.button_down.connect(_on_toggle_down)
	_toggle.button_up.connect(_on_toggle_up)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.name = "CheatPanel"
	_panel.theme = _theme
	_panel.visible = false
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.03, 0.03, 0.05, 0.95)
	panel_bg.set_corner_radius_all(int(5 * _ui))
	panel_bg.set_border_width_all(maxi(1, int(1 * _ui)))
	panel_bg.border_color = Color(0.75, 0.75, 0.8, 0.9)
	_panel.add_theme_stylebox_override("panel", panel_bg)
	_panel.position = Vector2(4, TOGGLE_H + 8) * _ui
	root.add_child(_panel)

	_scroll = ScrollContainer.new()
	var scroll: ScrollContainer = _scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 10
	scroll.get_v_scroll_bar().custom_minimum_size = Vector2(_fs(9), 0)
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
	title.text = "金手指"
	title.theme = _theme
	vb.add_child(title)

	var nav := HBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", _fs(2))
	vb.add_child(nav)
	nav.add_child(_make_button("上一页", func() -> void: _page(-1)))
	nav.add_child(_make_button("下一页", func() -> void: _page(1)))
	nav.add_child(_make_button("关闭", func() -> void: _panel.visible = false))
	_sep(vb)

	# --- 持久化开关 ---
	vb.add_child(_make_check("无敌模式", god_mode, func(on: bool) -> void: _set_flag("god_mode", on)))
	vb.add_child(_make_check("无限命", inf_lives, func(on: bool) -> void: _set_flag("inf_lives", on)))
	vb.add_child(_make_check("冻结时间", freeze_time, func(on: bool) -> void: _on_freeze_toggled(on)))
	vb.add_child(_make_check("无敌星", star_mode, func(on: bool) -> void: _set_flag("star_mode", on)))
	vb.add_child(_make_check("超级跳", super_jump, func(on: bool) -> void: _set_flag("super_jump", on)))
	vb.add_child(_make_check("加速跑", fast_run, func(on: bool) -> void: _set_flag("fast_run", on)))
	vb.add_child(_make_check("穿墙", noclip, func(on: bool) -> void: _on_noclip_toggled(on)))
	vb.add_child(_make_check("冻结敌人", freeze_enemies, func(on: bool) -> void: _on_freeze_enemies_toggled(on)))
	_sep(vb)

	# --- 临时开关 ---
	vb.add_child(_make_check("自动跑", auto_run, func(on: bool) -> void: set_auto_run(on)))
	_scale_btn = _make_button("速度：正常", func() -> void: set_slow_motion(not slow_motion))
	vb.add_child(_scale_btn)
	_sep(vb)

	# --- 一次性动作 ---
	vb.add_child(_make_button("变火焰", func() -> void: set_power("Fire")))
	vb.add_child(_make_button("变大", func() -> void: set_power("Big")))
	vb.add_child(_make_button("锤子", func() -> void: give_hammer()))
	vb.add_child(_make_button("+99 金币", func() -> void: give_coins()))
	vb.add_child(_make_button("+100 时间", func() -> void: add_time()))
	vb.add_child(_make_button("清空敌人", func() -> void: kill_all_enemies()))
	_sep(vb)

	# --- 传送 / 跳关 ---
	vb.add_child(_make_button("存点", func() -> void: set_waypoint()))
	vb.add_child(_make_button("回点", func() -> void: goto_waypoint()))
	vb.add_child(_make_button("上一世界", func() -> void: warp_level(-1, 0)))
	vb.add_child(_make_button("下一世界", func() -> void: warp_level(1, 0)))
	vb.add_child(_make_button("上一关", func() -> void: warp_level(0, -1)))
	vb.add_child(_make_button("下一关", func() -> void: warp_level(0, 1)))
	_sep(vb)

	_unlock_btn = _make_button("解锁全部关卡", func() -> void: _on_unlock_pressed())
	vb.add_child(_unlock_btn)


func _page(dir: int) -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical += dir * int(maxf(48.0, _scroll.size.y * 0.8))


func _sep(vb: VBoxContainer) -> void:
	var s := HSeparator.new()
	s.theme = _theme
	vb.add_child(s)


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
		_apply_enemy_freeze()


func _on_unlock_pressed() -> void:
	if _unlock_btn == null:
		return
	if not _unlock_armed:
		_unlock_armed = true
		_unlock_btn.text = "再点一次确认"
		await get_tree().create_timer(3.0, true).timeout
		if _unlock_armed:
			_unlock_armed = false
			_unlock_btn.text = "解锁全部关卡"
		return
	_unlock_armed = false
	unlock_all_levels()
	_unlock_btn.text = "已解锁全部关卡"
	await get_tree().create_timer(2.0, true).timeout
	if _unlock_btn != null:
		_unlock_btn.text = "解锁全部关卡"


func _on_toggle_pressed() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	_toggle.modulate = Color(1, 1, 1, 1.0) if _panel.visible else Color(1, 1, 1, 0.72)
