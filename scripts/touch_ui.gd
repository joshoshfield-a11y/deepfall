# touch_ui.gd — twin-stick touch controls for Android (harmless on desktop:
# mouse input never produces InputEventScreenTouch, so desktop paths are untouched).
#
# Left stick (fixed, bottom-left): x = move left/right (analog, via the same
# player.touch_move the old ◀/▶ buttons used), push up past 0.6 = jump via the
# same player.touch_jump the JUMP button uses, so coyote time, jump buffer
# and double jump all still apply — relax the stick above -0.35, then push up
# again, and the rising edge fires the second jump.
# Right stick (fixed, bottom-right): push past 0.5 magnitude = mine the block
# in the stick direction (8-way, dominant components) via main._mine_at with
# the same 0.25s mine_cooldown the old MINE button used; releasing stops.
# With the sword equipped the right stick swings instead (main gates it).
# JUMP (Phase 10): dedicated button above ATK — same touch_jump flag as
# stick-up, so coyote / buffer / double jump are identical; stick-up jump
# stays working as a secondary path. Drop-through: hold the left stick
# down + tap JUMP (same as S+Space on desktop).
# TORCH is the one kept button (top-right of the right stick): a joystick has
# no natural torch action, so place/pickup stays a small button, stated plainly.
# Old ◀ ▶ MINE buttons are gone entirely.
# Hotbar (Phase 10, Terraria-style): bottom-centre row above CRAFT — pickaxe
# / sword / torch slots. TOOL cycles pickaxe ↔ sword; tapping a slot selects
# it directly (torch slot places a torch). Selected slot is full-bright.
# Dead zone 0.25, so resting thumbs do not drift the player. Sticks sit at the
# bottom corners, 160px across, and never cover the screen centre or the HUD.
extends CanvasLayer

const RADIUS := 70.0
const DEAD := 0.25
const JUMP_THRESH := 0.6
const JUMP_RELEASE := 0.35
const MINE_THRESH := 0.5
const DIR_THRESH := 0.35
const CAPTURE_DIST := 110.0

var player: Node2D = null
var main_node: Node = null
var _left_id := -1
var _right_id := -1
var _left_vec := Vector2.ZERO
var _right_vec := Vector2.ZERO
var _left_visual: StickVisual = null
var _right_visual: StickVisual = null
var _left_center := Vector2(140.0, 580.0)
var _right_center := Vector2(1140.0, 580.0)
# Phase 10: JUMP + TOOL buttons and the hotbar slots (kept as refs so
# main can refresh the selected-slot highlight after a tool change).
var _jump_b: Button = null
var _tool_b: Button = null
var _slot_pick: Button = null
var _slot_sword: Button = null
var _slot_torch: Button = null

class StickVisual extends Control:
	var knob := Vector2.ZERO
	func _draw() -> void:
		draw_circle(Vector2(80, 80), 70, Color(1, 1, 1, 0.22))
		draw_arc(Vector2(80, 80), 70, 0, TAU, 32, Color(1, 1, 1, 0.45), 3.0)
		draw_circle(Vector2(80, 80) + knob, 30, Color(1, 1, 1, 0.60))

func _ready() -> void:
	main_node = get_parent()
	player = main_node.get_node("Player")
	_left_visual = _make_stick(_left_center)
	_right_visual = _make_stick(_right_center)
	var b := Button.new()
	b.text = "TORCH"
	b.custom_minimum_size = Vector2(80, 80)
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.offset_left = -210
	b.offset_top = -320
	b.offset_right = -130
	b.offset_bottom = -240
	b.modulate = Color(1, 1, 1, 0.65)
	b.button_down.connect(_torch_down)
	add_child(b)
	# ATK button (Phase 5): bottom-right, left of the right stick
	# (stick spans x 1070-1210, TORCH sits above it at x 1070-1150).
	# ATK at x 960-1040, y 550-630: overlaps neither.
	var atk := Button.new()
	atk.text = "ATK"
	atk.custom_minimum_size = Vector2(80, 80)
	atk.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	atk.offset_left = -320
	atk.offset_top = -170
	atk.offset_right = -240
	atk.offset_bottom = -90
	atk.modulate = Color(1, 1, 1, 0.65)
	atk.button_down.connect(_atk_down)
	add_child(atk)
	# CRAFT button (Phase 7): bottom-centre, x 560-720, y 640-720.
	# Twin sticks span x 60-220 and x 1060-1220 (y 500-660), ATK is
	# x 960-1040 y 550-630, TORCH is above the right stick, SAVE/NEW
	# are top-right — the bottom-centre button overlaps none of them.
	# It toggles the crafting panel (same as C on desktop); the panel
	# itself has the PLACE buttons, so touch placing goes through it.
	var craft_b := Button.new()
	craft_b.text = "CRAFT"
	craft_b.custom_minimum_size = Vector2(160, 80)
	craft_b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	craft_b.offset_left = -80
	craft_b.offset_top = -80
	craft_b.offset_right = 80
	craft_b.offset_bottom = 0
	craft_b.modulate = Color(1, 1, 1, 0.65)
	craft_b.button_down.connect(_craft_down)
	add_child(craft_b)
	# SAVE / NEW buttons (Phase 6): top-right, below the HUD text.
	# SAVE writes user://deepfall_save.json (same as F5); NEW clears
	# the save and regenerates a clean run (same as F9). Neither
	# touches the twin sticks, ATK, or TORCH.
	var save_b := Button.new()
	save_b.text = "SAVE"
	save_b.custom_minimum_size = Vector2(80, 80)
	save_b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	save_b.offset_left = -230
	save_b.offset_top = 70
	save_b.offset_right = -150
	save_b.offset_bottom = 150
	save_b.modulate = Color(1, 1, 1, 0.65)
	save_b.button_down.connect(_save_down)
	add_child(save_b)
	var new_b := Button.new()
	new_b.text = "NEW"
	new_b.custom_minimum_size = Vector2(80, 80)
	new_b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	new_b.offset_left = -140
	new_b.offset_top = 70
	new_b.offset_right = -60
	new_b.offset_bottom = 150
	new_b.modulate = Color(1, 1, 1, 0.65)
	new_b.button_down.connect(_new_down)
	add_child(new_b)
	# JUMP button (Phase 10): bottom-right, directly ABOVE ATK
	# (ATK x 960-1040 y 550-630, right stick x 1060-1220 y 500-660,
	# TORCH x 1070-1150 y 400-480). JUMP at x 960-1040, y 450-530
	# overlaps none of them. Same touch_jump flag as stick-up.
	_jump_b = Button.new()
	_jump_b.name = "JumpButton"
	_jump_b.text = "JUMP"
	_jump_b.custom_minimum_size = Vector2(80, 80)
	_jump_b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_jump_b.offset_left = -320
	_jump_b.offset_top = -270
	_jump_b.offset_right = -240
	_jump_b.offset_bottom = -190
	_jump_b.modulate = Color(1, 1, 1, 0.65)
	_jump_b.button_down.connect(_jump_down)
	_jump_b.button_up.connect(_jump_up)
	add_child(_jump_b)
	# TOOL button (Phase 10): cycles pickaxe ↔ sword. Bottom-centre,
	# left of the hotbar: x 480-548, y 580-628. Left stick ends x 220,
	# CRAFT is y 640-720 — no overlap.
	_tool_b = Button.new()
	_tool_b.name = "ToolButton"
	_tool_b.text = "TOOL"
	_tool_b.custom_minimum_size = Vector2(68, 48)
	_tool_b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tool_b.offset_left = -160
	_tool_b.offset_top = -140
	_tool_b.offset_right = -92
	_tool_b.offset_bottom = -92
	_tool_b.modulate = Color(1, 1, 1, 0.65)
	_tool_b.button_down.connect(_tool_down)
	add_child(_tool_b)
	# Hotbar (Phase 10, Terraria-style): three 48px slots, y 580-628,
	# directly above CRAFT (y 640-720), same x range. Icons are staged
	# item art copied into assets/items/ (never moved out of staging).
	_slot_pick = _make_slot("PickSlot", -80, "res://assets/items/hotbar_pickaxe.png", _slot_pick_down)
	_slot_sword = _make_slot("SwordSlot", -24, "res://assets/items/hotbar_sword.png", _slot_sword_down)
	_slot_torch = _make_slot("TorchSlot", 32, "res://assets/items/hotbar_torch.png", _slot_torch_down)
	_refresh_hotbar()

func _make_slot(slot_name: String, off_left: int, icon_path: String, cb: Callable) -> Button:
	var s := Button.new()
	s.name = slot_name
	s.custom_minimum_size = Vector2(48, 48)
	s.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	s.offset_left = off_left
	s.offset_top = -140
	s.offset_right = off_left + 48
	s.offset_bottom = -92
	s.icon = load(icon_path)
	s.expand_icon = true
	s.modulate = Color(1, 1, 1, 0.65)
	s.button_down.connect(cb)
	add_child(s)
	return s

func _refresh_hotbar() -> void:
	# Phase 10: selected tool slot full-bright, the other dimmed.
	# Torch is not a tool — its slot is never "selected".
	if main_node == null or _slot_pick == null:
		return
	var t: String = String(main_node.get("tool"))
	_slot_pick.modulate = Color(1, 1, 1, 1.0) if t == "pickaxe" else Color(0.55, 0.55, 0.55, 0.7)
	_slot_sword.modulate = Color(1, 1, 1, 1.0) if t == "sword" else Color(0.55, 0.55, 0.55, 0.7)

func _make_stick(center: Vector2) -> StickVisual:
	var s := StickVisual.new()
	s.custom_minimum_size = Vector2(160, 160)
	s.position = center - Vector2(80, 80)
	add_child(s)
	return s

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _left_id < 0 and event.position.distance_to(_left_center) <= CAPTURE_DIST:
				_left_id = event.index
				_update_left(event.position)
			elif _right_id < 0 and event.position.distance_to(_right_center) <= CAPTURE_DIST:
				_right_id = event.index
				_update_right(event.position)
		else:
			if event.index == _left_id:
				_left_id = -1
				_left_vec = Vector2.ZERO
				_left_visual.knob = Vector2.ZERO
				_left_visual.queue_redraw()
				player.touch_move = 0.0
				player.touch_jump = false
				player.touch_crouch = false
				player.touch_drop = false
			elif event.index == _right_id:
				_right_id = -1
				_right_vec = Vector2.ZERO
				_right_visual.knob = Vector2.ZERO
				_right_visual.queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _left_id:
			_update_left(event.position)
		elif event.index == _right_id:
			_update_right(event.position)

func _update_left(pos: Vector2) -> void:
	var v := (pos - _left_center) / RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_left_vec = v
	_left_visual.knob = v * RADIUS
	_left_visual.queue_redraw()
	player.touch_move = 0.0 if absf(v.x) < DEAD else v.x
	# Jump is an edge, not a hold: push up past threshold = true, relax
	# above -0.35 = false, so a second up-flick is a second rising edge
	# and fires the double jump through the existing player logic.
	if v.y < -JUMP_THRESH:
		player.touch_jump = true
	elif v.y > -JUMP_RELEASE:
		player.touch_jump = false
	# Phase 9: push DOWN past 0.6 = crouch while held on the ground;
	# down + an up-flick jump on a one-way platform = drop through it
	# (same as S / Down + jump on desktop, in player.gd).
	player.touch_crouch = v.y > 0.6
	player.touch_drop = v.y > 0.6

func _update_right(pos: Vector2) -> void:
	var v := (pos - _right_center) / RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_right_vec = v
	_right_visual.knob = v * RADIUS
	_right_visual.queue_redraw()

func _process(_delta: float) -> void:
	if _right_id >= 0 and _right_vec.length() > MINE_THRESH and main_node.mine_cooldown <= 0.0:
		var dx := 0 if absf(_right_vec.x) < DIR_THRESH else (1 if _right_vec.x > 0.0 else -1)
		var dy := 0 if absf(_right_vec.y) < DIR_THRESH else (1 if _right_vec.y > 0.0 else -1)
		if dx != 0 or dy != 0:
			main_node.mine_cooldown = 0.25
			# Phase 10: via_stick=true — with the sword this swings
			# instead of mining; with the pickaxe it mines as before.
			main_node.call("_mine_at", player.cell() + Vector2i(dx, dy), true)

func _jump_down() -> void:
	# Phase 10: same touch_jump flag as stick-up — coyote / buffer /
	# double jump are identical; the player logic reads the rising edge.
	if player != null:
		player.touch_jump = true

func _jump_up() -> void:
	if player != null:
		player.touch_jump = false

func _tool_down() -> void:
	if main_node != null and main_node.has_method("cycle_tool"):
		main_node.call("cycle_tool")

func _slot_pick_down() -> void:
	if main_node != null and main_node.has_method("set_tool"):
		main_node.call("set_tool", "pickaxe")

func _slot_sword_down() -> void:
	if main_node != null and main_node.has_method("set_tool"):
		main_node.call("set_tool", "sword")

func _slot_torch_down() -> void:
	_torch_down()

func _torch_down() -> void:
	if main_node.mine_cooldown <= 0.0:
		main_node.mine_cooldown = 0.25
		main_node.call("_place_torch")

func _atk_down() -> void:
	if player != null and player.has_method("try_attack"):
		player.call("try_attack")

func _craft_down() -> void:
	if main_node != null and main_node.has_method("_toggle_craft_panel"):
		main_node.call("_toggle_craft_panel")

func _save_down() -> void:
	if main_node != null and main_node.has_method("save_game"):
		main_node.call("save_game", "manual")

func _new_down() -> void:
	if main_node != null and main_node.has_method("new_run"):
		main_node.call("new_run")
