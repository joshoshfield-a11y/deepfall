# touch_ui.gd — DEEPFALL Phase 11 mobile controls.
#
# FLOATING twin sticks (they appear wherever the thumb lands):
#   * left half of the screen  -> MOVE stick. x = analog run, push
#     down = crouch / drop through platforms (with JUMP), a strong
#     up-flick also jumps (so you can jump while the right thumb aims).
#     If the thumb drags past the ring, the stick base follows it.
#   * right half of the screen -> AIM stick: attack / mine in whatever
#     direction it is pulled (full 360°, reach ~3 blocks). Holding it
#     repeats; a quick tap attacks straight ahead.
# Buttons (all fully multi-touch, handled here by touch index — the old
# Godot Buttons only received the FIRST finger through mouse emulation,
# which is why JUMP / ATK failed while a stick was held):
#   JUMP (big, bottom-right), DASH and SLAM skills (with cooldown rings),
#   TOOL swap, hotbar (pickaxe / sword / torch / lantern / bench with
#   counts; tap a tool to equip, tap a placeable to place it), and
#   CRAFT / SAVE / NEW (NEW asks for a second tap) top-right.
# Phase 12 control settings (MENU button): stick size, button size,
# opacity, sound volume, vibration, left-handed (mirrored) layout and a
# drag-to-move layout editor. Saved to user://deepfall_settings.json.
extends CanvasLayer

const SETTINGS_PATH := "user://deepfall_settings.json"
const DEFAULT_SETTINGS := {"stick_scale": 1.0, "button_scale": 1.0, "opacity": 0.85,
	"volume": 0.8, "music": 0.6, "vibration": true, "left_handed": false, "offsets": {}}

const RADIUS := 72.0
const DEAD := 0.18
const AIM_THRESH := 0.3
const TAP_TIME := 0.22

var player: Node2D = null
var main_node: Node = null
var _overlay: Control = null
var _buttons: Array = []
var _touches: Dictionary = {}
var _move_base := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _move_active := false
var _aim_base := Vector2.ZERO
var _aim_pos := Vector2.ZERO
var _aim_active := false
var _jump_btn_held := false
var _stick_jump := false
var touch_used := false
var _new_confirm := 0.0
var _vs := Vector2(1280, 720)
var _btn_new: TBtn = null
var _slot_pick: TBtn = null
var _slot_sword: TBtn = null
var _slot_torch: TBtn = null
var _slot_lantern: TBtn = null
var _slot_bench: TBtn = null
var _btn_dash: TBtn = null
var _btn_slam: TBtn = null
var _btn_jump: TBtn = null
var settings: Dictionary = {}
var _stick_r := RADIUS
var _editing := false
var _drag: Dictionary = {}
var _defaults: Dictionary = {}
var _settings_panel: PanelContainer = null
var _edit_bar: Control = null
var _sliders: Dictionary = {}
var _checks: Dictionary = {}

class TBtn extends Control:
	var label := ""
	var round_btn := true
	var radius := 40.0
	var held := false
	var selected := false
	var cooldown := 0.0
	var count := -1
	var icon: Texture2D = null
	var accent := Color(1.0, 0.8, 0.4)
	var on_press: Callable
	var on_release: Callable
	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		if round_btn:
			return p.distance_to(position + size * 0.5) <= radius + 10.0
		return Rect2(position - Vector2(6, 6), size + Vector2(12, 12)).has_point(p)
	func _draw() -> void:
		var c := size * 0.5
		var bg := Color(0.06, 0.07, 0.1, 0.55 if not held else 0.8)
		var rim := Color(1, 1, 1, 0.35)
		if selected:
			rim = accent
		if held:
			rim = Color(1, 1, 1, 0.9)
		if round_btn:
			draw_circle(c, radius, bg)
			draw_arc(c, radius, 0, TAU, 40, rim, 3.0, true)
			if cooldown > 0.0:
				draw_arc(c, radius - 6, -PI / 2, -PI / 2 + TAU * cooldown, 40, Color(1, 1, 1, 0.5), 6.0, true)
		else:
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.border_color = rim
			sb.set_border_width_all(3 if selected else 2)
			sb.set_corner_radius_all(10)
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var font := ThemeDB.fallback_font
		if icon != null:
			var isz := minf(size.x, size.y) * 0.72
			draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
				Color(1, 1, 1, 1) if (selected or not round_btn) else Color(1, 1, 1, 0.85))
		if label != "":
			var fs := 18 if round_btn and radius > 50 else 14
			var y := c.y + fs * 0.35
			if icon != null:
				y = size.y - 6
				fs = 12
			draw_string_outline(font, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(1, 1, 1, 0.95))
		if count >= 0:
			var t := str(count)
			draw_string_outline(font, Vector2(size.x - 26, 18), t, HORIZONTAL_ALIGNMENT_RIGHT, 22, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(font, Vector2(size.x - 26, 18), t, HORIZONTAL_ALIGNMENT_RIGHT, 22, 14, Color(1, 0.95, 0.75) if count > 0 else Color(1, 0.5, 0.5))

class Overlay extends Control:
	var ui: Node = null
	func _draw() -> void:
		if ui == null:
			return
		ui.call("_draw_sticks", self)

func _ready() -> void:
	main_node = get_parent()
	player = main_node.get_node("Player")
	_overlay = Overlay.new()
	_overlay.ui = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_btn_jump = _make_btn("JUMP", true, 64.0, _jump_down, _jump_up)
	_btn_dash = _make_btn("DASH", true, 42.0, func(): player.call("try_dash"), Callable())
	_btn_slam = _make_btn("SLAM", true, 42.0, func(): player.call("try_slam"), Callable())
	var tool_b := _make_btn("SWAP", true, 36.0, _tool_down, Callable())
	tool_b.name = "ToolButton"
	_slot_pick = _make_slot("res://assets/items/hotbar_pickaxe.png", "1", func(): _set_tool("pickaxe"))
	_slot_sword = _make_slot("res://assets/items/hotbar_sword.png", "2", func(): _set_tool("sword"))
	_slot_torch = _make_slot("res://assets/items/hotbar_torch.png", "3", _torch_down)
	_slot_lantern = _make_slot("res://assets/items/lantern-64.png", "4", func(): main_node.call("_place_lantern"))
	_slot_bench = _make_slot("res://assets/hero/props/workbench.png", "5", func(): main_node.call("_place_workbench"))
	var craft_b := _make_btn("CRAFT", false, 0.0, _craft_down, Callable())
	craft_b.name = "CraftButton"
	var save_b := _make_btn("SAVE", false, 0.0, _save_down, Callable())
	save_b.name = "SaveButton"
	_btn_new = _make_btn("NEW", false, 0.0, _new_down, Callable())
	_btn_new.name = "NewButton"
	_btn_jump.name = "JumpButton"
	_btn_dash.name = "DashButton"
	_btn_slam.name = "SlamButton"
	_btn_jump.accent = Color(0.5, 0.9, 1.0)
	var slot_names := ["SlotPickaxe", "SlotSword", "SlotTorch", "SlotLantern", "SlotBench"]
	var slot_nodes := [_slot_pick, _slot_sword, _slot_torch, _slot_lantern, _slot_bench]
	for i in range(slot_names.size()):
		(slot_nodes[i] as TBtn).name = slot_names[i]
	var menu_b := _make_btn("MENU", false, 0.0, _open_settings, Callable())
	menu_b.name = "MenuButton"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_build_settings_panel()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_hotbar()

func _make_btn(text: String, rnd: bool, r: float, press: Callable, release: Callable) -> TBtn:
	var b := TBtn.new()
	b.label = text
	b.round_btn = rnd
	b.radius = r
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.on_press = press
	b.on_release = release
	if rnd:
		b.size = Vector2(r * 2.0, r * 2.0)
	else:
		b.size = Vector2(88, 46)
	b.set_meta("base_r", r)
	b.set_meta("base_size", b.size)
	add_child(b)
	_buttons.append(b)
	return b

func _make_slot(icon_path: String, key: String, press: Callable) -> TBtn:
	var b := _make_btn(key, false, 0.0, press, Callable())
	b.icon = load(icon_path)
	b.size = Vector2(64, 64)
	b.set_meta("base_size", b.size)
	return b

func _layout() -> void:
	_vs = get_viewport().get_visible_rect().size
	var W := _vs.x
	var H := _vs.y
	var bs: float = float(settings.get("button_scale", 1.0))
	_stick_r = RADIUS * float(settings.get("stick_scale", 1.0))
	for bb in _buttons:
		var tb: TBtn = bb
		if tb.round_btn:
			tb.radius = float(tb.get_meta("base_r")) * bs
			tb.size = Vector2(tb.radius * 2.0, tb.radius * 2.0)
		else:
			tb.size = (tb.get_meta("base_size") as Vector2) * clampf(bs, 0.8, 1.25)
	var lh: bool = bool(settings.get("left_handed", false))
	var mx := -1.0 if lh else 1.0
	var j := Vector2(104 * bs if lh else W - 104 * bs, H - 104 * bs)
	_place_round(_btn_jump, j)
	_place_round(_btn_dash, j + Vector2(-158 * mx, 22) * bs)
	_place_round(_btn_slam, j + Vector2(-118 * mx, -112) * bs)
	_place_round(get_node("ToolButton") as TBtn, j + Vector2(-8 * mx, -150) * bs)
	# hotbar: top centre, Terraria-style
	var slots := [_slot_pick, _slot_sword, _slot_torch, _slot_lantern, _slot_bench]
	var sw: float = (slots[0] as TBtn).size.x
	var total := slots.size() * sw + (slots.size() - 1) * 8
	var rw: float = (get_node("CraftButton") as TBtn).size.x + 8
	var right_btns := ["MenuButton", "CraftButton", "SaveButton", "NewButton"]
	# centred, but never under the right-hand menu buttons (wide buttons
	# / narrow screens) and never over the hearts on the left
	var right_start := W - right_btns.size() * rw - 4
	var x0 := clampf(minf((W - total) * 0.5, right_start - total - 12), 250.0, W)
	for i in range(slots.size()):
		(slots[i] as TBtn).position = Vector2(x0 + i * (sw + 8), 12)
	for i in range(right_btns.size()):
		(get_node(right_btns[i]) as TBtn).position = Vector2(W - (right_btns.size() - i) * rw - 4, 12)
	# remember the computed defaults, then apply the player's custom moves
	var offs: Dictionary = settings.get("offsets", {})
	var op: float = float(settings.get("opacity", 0.85))
	for bb in _buttons:
		var tb2: TBtn = bb
		_defaults[tb2.name] = tb2.position
		if offs.has(String(tb2.name)):
			var o = offs[String(tb2.name)]
			tb2.position += Vector2(float(o[0]), float(o[1]))
		tb2.position = tb2.position.clamp(Vector2.ZERO, _vs - tb2.size)
		tb2.modulate = Color(1, 1, 1, op)
		tb2.queue_redraw()
	_overlay.size = _vs
	if _settings_panel != null:
		_settings_panel.position = (_vs - _settings_panel.size) * 0.5

func _place_round(b: TBtn, center: Vector2) -> void:
	b.position = center - Vector2(b.radius, b.radius)

func _refresh_hotbar() -> void:
	if main_node == null or _slot_pick == null:
		return
	var t: String = String(main_node.get("tool"))
	_slot_pick.selected = t == "pickaxe"
	_slot_sword.selected = t == "sword"
	for b in _buttons:
		(b as TBtn).queue_redraw()

func _blocked(p: Vector2) -> bool:
	# Touches meant for the class-select screen, craft or settings panel.
	if _settings_panel != null and _settings_panel.visible:
		return true
	if bool(main_node.get("_card_open")):
		return true
	if bool(main_node.get("_selecting")):
		return true
	var cp: Control = main_node.get("_craft_panel")
	if cp != null and cp.visible and cp.get_global_rect().has_point(p):
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_used = true
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position)

func _touch_down(idx: int, p: Vector2) -> void:
	if _editing:
		for i in range(_buttons.size() - 1, -1, -1):
			var eb: TBtn = _buttons[i]
			if eb.hit(p) and eb.name != "MenuButton":
				_drag[idx] = {"btn": eb, "off": eb.position - p}
				eb.held = true
				eb.queue_redraw()
				return
		return
	if _blocked(p) or player == null:
		return
	for i in range(_buttons.size() - 1, -1, -1):
		var b: TBtn = _buttons[i]
		if b.hit(p):
			b.held = true
			b.queue_redraw()
			_touches[idx] = {"kind": "btn", "btn": b}
			if b.on_press.is_valid():
				b.on_press.call()
			return
	if p.y < 90.0:
		return  # top strip is HUD / hotbar
	var left_side: bool = p.x < _vs.x * 0.5
	if bool(settings.get("left_handed", false)):
		left_side = not left_side
	if left_side:
		if _move_active:
			return
		_move_active = true
		_move_base = p
		_move_pos = p
		_touches[idx] = {"kind": "move"}
		_update_move()
	else:
		if _aim_active:
			return
		_aim_active = true
		_aim_base = p
		_aim_pos = p
		_touches[idx] = {"kind": "aim", "t": Time.get_ticks_msec(), "acted": false}

func _touch_drag(idx: int, p: Vector2) -> void:
	if _drag.has(idx):
		var db: TBtn = _drag[idx]["btn"]
		db.position = (p + (_drag[idx]["off"] as Vector2)).clamp(Vector2.ZERO, _vs - db.size)
		return
	if not _touches.has(idx):
		return
	var k: String = _touches[idx]["kind"]
	if k == "move":
		_move_pos = p
		var d := _move_pos - _move_base
		if d.length() > _stick_r:
			_move_base = _move_pos - d.normalized() * _stick_r
		_update_move()
	elif k == "aim":
		_aim_pos = p
		var d2 := _aim_pos - _aim_base
		if d2.length() > _stick_r * 1.2:
			_aim_base = _aim_pos - d2.normalized() * _stick_r * 1.2

func _touch_up(idx: int, _p: Vector2) -> void:
	if _drag.has(idx):
		var ub: TBtn = _drag[idx]["btn"]
		_drag.erase(idx)
		ub.held = false
		ub.queue_redraw()
		var offs: Dictionary = settings.get("offsets", {})
		var off: Vector2 = ub.position - (_defaults.get(ub.name, ub.position) as Vector2)
		offs[String(ub.name)] = [off.x, off.y]
		settings["offsets"] = offs
		_save_settings()
		return
	if not _touches.has(idx):
		return
	var t: Dictionary = _touches[idx]
	_touches.erase(idx)
	match String(t["kind"]):
		"btn":
			var b: TBtn = t["btn"]
			b.held = false
			b.queue_redraw()
			if b.on_release.is_valid():
				b.on_release.call()
		"move":
			_move_active = false
			player.touch_move = 0.0
			player.touch_crouch = false
			player.touch_drop = false
			_stick_jump = false
			_apply_jump()
		"aim":
			_aim_active = false
			var quick: bool = Time.get_ticks_msec() - int(t["t"]) < int(TAP_TIME * 1000.0)
			if quick and not bool(t["acted"]):
				main_node.call("aim_action", Vector2(player.facing, 0), true)
			player.call("set_aim", player.aim, false)

func _update_move() -> void:
	var v := (_move_pos - _move_base) / _stick_r
	if v.length() > 1.0:
		v = v.normalized()
	var ax := absf(v.x)
	player.touch_move = 0.0 if ax < DEAD else signf(v.x) * clampf((ax - DEAD) / 0.6, 0.0, 1.0)
	var vertical := absf(v.y) > absf(v.x) * 1.1
	player.touch_crouch = vertical and v.y > 0.6
	player.touch_drop = player.touch_crouch
	if vertical and v.y < -0.72:
		_stick_jump = true
	elif v.y > -0.4:
		_stick_jump = false
	_apply_jump()

func _apply_jump() -> void:
	player.touch_jump = _jump_btn_held or _stick_jump

func _process(delta: float) -> void:
	_new_confirm = maxf(0.0, _new_confirm - delta)
	if _btn_new != null:
		var want := "SURE?" if _new_confirm > 0.0 else "NEW"
		if _btn_new.label != want:
			_btn_new.label = want
			_btn_new.queue_redraw()
	var sel: bool = bool(main_node.get("_selecting"))
	for b in _buttons:
		(b as TBtn).visible = not sel and not bool(main_node.get("_card_open")) and not (_settings_panel != null and _settings_panel.visible)
	if _aim_active and player != null:
		var v := (_aim_pos - _aim_base) / _stick_r
		if v.length() > AIM_THRESH:
			player.call("set_aim", v, true)
			main_node.call("aim_action", v.normalized(), true)
			for k in _touches.keys():
				if String(_touches[k]["kind"]) == "aim":
					_touches[k]["acted"] = true
	# skill cooldown rings + hotbar counts
	if player != null:
		_btn_dash.cooldown = float(player.get("dash_cooldown")) / 0.75
		_btn_slam.cooldown = float(player.get("slam_cooldown")) / 1.4
	var inv: Dictionary = main_node.get("inv")
	_slot_torch.count = int(main_node.get("torches_held"))
	_slot_lantern.count = int(inv.get("lantern", 0))
	_slot_bench.count = int(inv.get("workbench", 0))
	for b in [_btn_dash, _btn_slam, _slot_torch, _slot_lantern, _slot_bench]:
		(b as TBtn).queue_redraw()
	_overlay.queue_redraw()

func _draw_sticks(c: Control) -> void:
	if bool(main_node.get("_selecting")) or (_settings_panel != null and _settings_panel.visible):
		return
	var op: float = float(settings.get("opacity", 0.85))
	var hint := Color(1, 1, 1, 0.10 * op)
	var lh: bool = bool(settings.get("left_handed", false))
	var move_hint := Vector2(_vs.x - 150 if lh else 150, _vs.y - 150)
	var aim_hint := Vector2(_vs.x * (0.38 if lh else 0.62), _vs.y - 200)
	if _move_active:
		_draw_stick(c, _move_base, _move_pos, Color(0.55, 0.85, 1.0), op)
	elif touch_used or _editing:
		c.draw_arc(move_hint, _stick_r, 0, TAU, 40, hint, 2.0, true)
	if _aim_active:
		_draw_stick(c, _aim_base, _aim_pos, Color(1.0, 0.7, 0.35), op)
	elif touch_used or _editing:
		c.draw_arc(aim_hint, _stick_r, 0, TAU, 40, hint, 2.0, true)

func _draw_stick(c: Control, base: Vector2, pos: Vector2, col: Color, op: float) -> void:
	var d := pos - base
	if d.length() > _stick_r:
		d = d.normalized() * _stick_r
	var kr := _stick_r * 0.42
	c.draw_circle(base, _stick_r, Color(0, 0, 0, 0.25 * op))
	c.draw_arc(base, _stick_r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.6 * op), 3.0, true)
	c.draw_circle(base + d, kr, Color(col.r, col.g, col.b, 0.55 * op))
	c.draw_arc(base + d, kr, 0, TAU, 32, Color(1, 1, 1, 0.8 * op), 2.0, true)

func _jump_down() -> void:
	_jump_btn_held = true
	_apply_jump()

func _jump_up() -> void:
	_jump_btn_held = false
	_apply_jump()

func _set_tool(t: String) -> void:
	if main_node.has_method("set_tool"):
		main_node.call("set_tool", t)

func _tool_down() -> void:
	if main_node.has_method("cycle_tool"):
		main_node.call("cycle_tool")

func _torch_down() -> void:
	if main_node.mine_cooldown <= 0.0:
		main_node.mine_cooldown = 0.25
		main_node.call("_place_torch")

func _craft_down() -> void:
	main_node.call("_toggle_craft_panel")

func _save_down() -> void:
	main_node.call("save_game", "manual")
	main_node.call("log_event", "Game saved")

func _new_down() -> void:
	if _new_confirm > 0.0:
		_new_confirm = 0.0
		main_node.call("new_run")
	else:
		_new_confirm = 2.0
		main_node.call("log_event", "Tap NEW again to start a fresh run")


# --- Phase 12: control settings ---

func _load_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			for k in d.keys():
				settings[k] = d[k]
	_apply_feel_settings()

func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings))
	f.close()

func _apply_feel_settings() -> void:
	var fxn: Node = main_node.get("fx")
	if fxn != null:
		fxn.set("volume", float(settings.get("volume", 0.8)))
		fxn.set("vibration", bool(settings.get("vibration", true)))
		fxn.set("music", float(settings.get("music", 0.6)))

func _build_settings_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.visible = false
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	sb.border_color = Color(1.0, 0.8, 0.4, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_settings_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "CONTROLS & FEEL"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_add_slider(vb, "stick_scale", "Stick size", 0.7, 1.5)
	_add_slider(vb, "button_scale", "Button size", 0.7, 1.4)
	_add_slider(vb, "opacity", "Button opacity", 0.25, 1.0)
	_add_slider(vb, "volume", "Sound volume", 0.0, 1.0)
	_add_slider(vb, "music", "Cave ambience", 0.0, 1.0)
	_add_check(vb, "vibration", "Vibration on hits")
	_add_check(vb, "left_handed", "Left-handed (swap sides)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for spec in [["MOVE BUTTONS", _start_edit], ["RESET", _reset_settings], ["CLOSE", _close_settings]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.name = "Settings" + String(spec[0]).replace(" ", "")
		b.custom_minimum_size = Vector2(160, 56)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(spec[1])
		row.add_child(b)
	# edit-layout banner
	var bar := HBoxContainer.new()
	bar.name = "EditBar"
	bar.visible = false
	bar.add_theme_constant_override("separation", 12)
	var lab := Label.new()
	lab.text = "Drag any button to move it"
	lab.add_theme_font_size_override("font_size", 20)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lab.add_theme_constant_override("outline_size", 6)
	bar.add_child(lab)
	var done := Button.new()
	done.name = "EditDone"
	done.text = "DONE"
	done.custom_minimum_size = Vector2(140, 56)
	done.add_theme_font_size_override("font_size", 20)
	done.pressed.connect(_end_edit)
	bar.add_child(done)
	add_child(bar)
	_edit_bar = bar

func _add_slider(vb: VBoxContainer, key: String, text: String, lo: float, hi: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size = Vector2(190, 0)
	lab.add_theme_font_size_override("font_size", 18)
	row.add_child(lab)
	var sl := HSlider.new()
	sl.name = "Slider_" + key
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.custom_minimum_size = Vector2(300, 44)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value = float(settings.get(key, 1.0))
	sl.value_changed.connect(func(v: float): _on_setting(key, v))
	row.add_child(sl)
	_sliders[key] = sl

func _add_check(vb: VBoxContainer, key: String, text: String) -> void:
	var cb := CheckButton.new()
	cb.name = "Check_" + key
	cb.text = text
	cb.add_theme_font_size_override("font_size", 18)
	cb.custom_minimum_size = Vector2(0, 44)
	cb.button_pressed = bool(settings.get(key, false))
	cb.toggled.connect(func(on: bool): _on_setting(key, on))
	vb.add_child(cb)
	_checks[key] = cb

func _on_setting(key: String, v) -> void:
	settings[key] = v
	if key == "left_handed":
		settings["offsets"] = {}  # custom moves were made for the other side
	_apply_feel_settings()
	_layout()
	_save_settings()
	var fxn: Node = main_node.get("fx")
	if key == "volume" and fxn != null:
		fxn.call("sfx", "pickup")
	if key == "vibration" and bool(v) and fxn != null:
		fxn.call("rumble", 60)

func _open_settings() -> void:
	_release_all()
	_settings_panel.visible = true
	_settings_panel.reset_size()
	_settings_panel.position = (_vs - _settings_panel.size) * 0.5
	get_tree().paused = true

func _close_settings() -> void:
	_settings_panel.visible = false
	get_tree().paused = false

func _start_edit() -> void:
	_settings_panel.visible = false
	_editing = true
	_edit_bar.visible = true
	_edit_bar.reset_size()
	_edit_bar.position = Vector2((_vs.x - _edit_bar.size.x) * 0.5, _vs.y * 0.42)
	for b in _buttons:
		(b as TBtn).visible = true

func _end_edit() -> void:
	_editing = false
	_drag.clear()
	_edit_bar.visible = false
	_save_settings()
	_settings_panel.visible = true

func _reset_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	for k in _sliders.keys():
		(_sliders[k] as HSlider).set_value_no_signal(float(settings[k]))
	for k in _checks.keys():
		(_checks[k] as CheckButton).set_pressed_no_signal(bool(settings[k]))
	_apply_feel_settings()
	_layout()
	_save_settings()

func _release_all() -> void:
	for idx in _touches.keys():
		_touch_up(idx, Vector2.ZERO)
	_touches.clear()
