# hero_rig.gd — DEEPFALL Phase 11 Terraria-style paper-doll hero.
#
# The hero is assembled from tiny pixel-art parts (assets/hero/<class>/,
# built by build_pixel_hero.py) and animated procedurally every frame:
# run cycle, idle breathing, jump / fall / land poses, crouch, dash lean,
# and tool swings that follow the AIM direction (right stick / mouse).
# The rig works in ART PIXELS (scale 3): feet at y = +13 art px, which
# is +40 px in the world = the player's half_h. Positions are rounded to
# whole art pixels so the character stays crisp pixel art.
# A verlet cape / scarf trails behind the hero (real spring physics).
extends Node2D

const PX := 3.0
const SWING_BACK := 1.9
const SWING_FWD := 1.3

var _back_leg: Node2D
var _front_leg: Node2D
var _back_arm: Node2D
var _front_arm: Node2D
var _torso: Sprite2D
var _head: Node2D
var _tool: Sprite2D
var _parts: Array = []
var _cape: Line2D
var _trail: Line2D
var _cape_pts: Array = []
var _cape_prev: Array = []
var _trail_pts: Array = []
var _phase := 0.0
var _time := 0.0
var _tool_name := "pickaxe"
var _class_id := "tech"
var facing := 1

func _ready() -> void:
	_cape = Line2D.new()
	_cape.top_level = true
	_cape.width = PX * 2.0
	_cape.joint_mode = Line2D.LINE_JOINT_ROUND
	_cape.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_cape.end_cap_mode = Line2D.LINE_CAP_ROUND
	var wc := Curve.new()
	wc.add_point(Vector2(0, 1.0))
	wc.add_point(Vector2(1, 0.45))
	_cape.width_curve = wc
	add_child(_cape)
	_back_arm = _limb("arm", Vector2(-1, -2), Vector2(-2, -1), true)
	_back_leg = _limb("leg", Vector2(-1, 4), Vector2(-2, 0), true)
	_torso = Sprite2D.new()
	_torso.centered = false
	add_child(_torso)
	_front_leg = _limb("leg", Vector2(1, 4), Vector2(-2, 0), false)
	_head = Node2D.new()
	add_child(_head)
	var hs := Sprite2D.new()
	hs.name = "S"
	hs.centered = false
	hs.position = Vector2(-5, -10)
	_head.add_child(hs)
	_front_arm = _limb("arm", Vector2(1, -2), Vector2(-2, -1), false)
	_tool = Sprite2D.new()
	_tool.centered = false
	_tool.position = Vector2(0, 7)
	_front_arm.add_child(_tool)
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = 16.0
	var tc := Curve.new()
	tc.add_point(Vector2(0, 0.1))
	tc.add_point(Vector2(1, 1.0))
	_trail.width_curve = tc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(0.85, 0.95, 1.0, 0.55))
	_trail.gradient = g
	add_child(_trail)
	scale = Vector2(PX, PX)

func _limb(part: String, pivot: Vector2, off: Vector2, back: bool) -> Node2D:
	var n := Node2D.new()
	n.position = pivot
	var s := Sprite2D.new()
	s.name = "S"
	s.centered = false
	s.position = off
	if back:
		s.modulate = Color(0.62, 0.62, 0.7, 1)
	n.set_meta("part", part)
	n.add_child(s)
	add_child(n)
	return n

func set_class(id: String) -> void:
	_class_id = id
	var base := "res://assets/hero/%s/" % id
	for limb in [_back_arm, _front_arm]:
		(limb.get_node("S") as Sprite2D).texture = load(base + "arm.png")
	for limb in [_back_leg, _front_leg]:
		(limb.get_node("S") as Sprite2D).texture = load(base + "leg.png")
	_torso.texture = load(base + "torso.png")
	(_head.get_node("S") as Sprite2D).texture = load(base + "head.png")
	var cape_col := {"tech": Color(0.24, 0.78, 0.9), "red": Color(0.75, 0.12, 0.14), "mage": Color(0.3, 0.22, 0.6)}
	_cape.default_color = cape_col.get(id, Color(0.5, 0.5, 0.5))
	_cape_pts.clear()
	_cape_prev.clear()
	set_tool(_tool_name)

func set_tool(t: String) -> void:
	_tool_name = t
	var tex_name := "pickaxe"
	if t == "sword":
		tex_name = "staff" if _class_id == "mage" else "sword"
	var tex: Texture2D = load("res://assets/hero/tools/%s.png" % tex_name)
	_tool.texture = tex
	_tool.offset = Vector2(-floor(tex.get_width() / 2.0), -tex.get_height() + 1)

func _arm_angle_for(aim_local: Vector2) -> float:
	# arm sprite hangs along +y; rotation r points it along (-sin r, cos r)
	return atan2(-aim_local.x, aim_local.y)

# st keys: on_ground, vel, move, crouch, swing (0..1 or -1), aim (world),
# dash, hurt, dead, land, stretch, delta, speed_max
func animate(st: Dictionary) -> void:
	var delta: float = st["delta"]
	_time += delta
	var vel: Vector2 = st["vel"]
	var on_ground: bool = st["on_ground"]
	var swing: float = st["swing"]
	var aim: Vector2 = st["aim"]
	var aim_local := Vector2(aim.x * facing, aim.y)
	var speed_ratio: float = clampf(absf(vel.x) / maxf(1.0, float(st["speed_max"])), 0.0, 1.5)
	var bl := 0.0; var fl := 0.0; var ba := 0.0; var fa := 0.0
	var body_y := 0.0
	var head_y := 0.0
	var lean := 0.0
	if bool(st["dead"]):
		visible = false
		_cape.visible = false
		_trail.visible = false
		return
	visible = true
	_cape.visible = true
	if bool(st["dash"]):
		bl = 0.9; fl = -0.5; ba = 1.2; fa = 1.0
		lean = 0.18
	elif not on_ground:
		if vel.y < 0.0:
			fl = -0.75; bl = 0.35
			fa = -2.5; ba = 0.7
		else:
			var flail := sin(_time * 18.0) * 0.25
			fl = -0.25 + flail * 0.5; bl = 0.3 - flail * 0.5
			fa = -2.2 + flail; ba = -2.0 - flail
	elif bool(st["crouch"]):
		fl = -0.9; bl = 0.7; fa = -0.3; ba = 0.3
		body_y = 3.0
	elif speed_ratio > 0.08:
		_phase += delta * (7.0 + 7.0 * speed_ratio)
		var s := sin(_phase)
		fl = -s * 0.75 * minf(1.0, speed_ratio + 0.3)
		bl = s * 0.75 * minf(1.0, speed_ratio + 0.3)
		fa = s * 0.7
		ba = -s * 0.7
		body_y = -roundf(absf(cos(_phase)))
		lean = 0.06 * speed_ratio
	else:
		_phase = 0.0
		var br := sin(_time * 2.4)
		body_y = 0.0 if br < 0.3 else -1.0
		head_y = body_y
		fa = 0.08 + br * 0.04
		ba = -0.08 - br * 0.04
	if float(st["land"]) > 0.0:
		body_y = 2.0
		fl = -0.6; bl = 0.6
	# Tool pose: swinging follows the aim; otherwise the tool rests
	# angled forward in the front hand (and the aiming arm points at
	# the aim while the stick is held, Terraria-style).
	var tool_rot := PI * 0.75
	if swing >= 0.0:
		var base := _arm_angle_for(aim_local)
		var e := 1.0 - pow(1.0 - swing, 3.0)
		if swing < 0.18:
			fa = base - SWING_BACK * (swing / 0.18)
		else:
			fa = base - SWING_BACK + (SWING_BACK + SWING_FWD) * e
		tool_rot = PI
		ba = fa * 0.3
	elif bool(st["aiming"]):
		fa = _arm_angle_for(aim_local)
		tool_rot = PI * 0.85
	_back_leg.rotation = bl
	_front_leg.rotation = fl
	_back_arm.rotation = ba
	_front_arm.rotation = fa
	_tool.rotation = tool_rot
	_tool.visible = true
	_torso.position = Vector2(-5, -4 + body_y)
	_head.position = Vector2(0, -3 + body_y + minf(0.0, head_y))
	_front_arm.position = Vector2(1, -2 + body_y)
	_back_arm.position = Vector2(-1, -2 + body_y)
	rotation = lean * facing
	# squash / stretch (land / jump takeoff) on top of the pixel scale
	var sx := PX
	var sy := PX
	if float(st["land"]) > 0.0:
		sx = PX * 1.1; sy = PX * 0.88
	elif float(st["stretch"]) > 0.0:
		sx = PX * 0.9; sy = PX * 1.1
	scale = Vector2(sx * facing, sy)
	var hurt: bool = st["hurt"]
	modulate = Color(2.2, 1.0, 1.0, 1.0) if hurt and int(_time * 20.0) % 2 == 0 else Color(1, 1, 1, 1)
	_update_cape(delta, vel)
	_update_trail(swing)

func _update_cape(delta: float, vel: Vector2) -> void:
	# Verlet rope: 6 points, anchor at the neck, gravity + wind from
	# the hero's own motion, fixed segment length, pixel-snapped.
	var anchor: Vector2 = to_global(Vector2(-2, -3))
	var n := 6
	var seg := 7.0
	if _cape_pts.size() != n:
		_cape_pts.clear(); _cape_prev.clear()
		for i in range(n):
			var p := anchor + Vector2(-facing * seg * i, 0)
			_cape_pts.append(p); _cape_prev.append(p)
	var g := Vector2(-vel.x * 0.9, 900.0 - vel.y * 0.3)
	for i in range(1, n):
		var p: Vector2 = _cape_pts[i]
		var v: Vector2 = (p - _cape_prev[i]) * 0.9
		_cape_prev[i] = p
		_cape_pts[i] = p + v + g * delta * delta
	_cape_pts[0] = anchor
	_cape_prev[0] = anchor
	for _it in range(3):
		for i in range(1, n):
			var a: Vector2 = _cape_pts[i - 1]
			var b: Vector2 = _cape_pts[i]
			var d := b - a
			var l := d.length()
			if l > 0.001:
				_cape_pts[i] = a + d * (seg / l)
	var line := PackedVector2Array()
	for p in _cape_pts:
		line.append(((p as Vector2) / PX).round() * PX)
	_cape.points = line

func _update_trail(swing: float) -> void:
	if swing >= 0.12 and swing < 0.95:
		var tip_local := _front_arm.position + Vector2(0, 7).rotated(_front_arm.rotation) + Vector2(0, 14).rotated(_front_arm.rotation)
		_trail_pts.append(to_global(tip_local))
		if _trail_pts.size() > 7:
			_trail_pts.pop_front()
	elif not _trail_pts.is_empty():
		_trail_pts.pop_front()
	_trail.visible = _trail_pts.size() >= 2
	_trail.points = PackedVector2Array(_trail_pts)
	var col := Color(0.85, 0.95, 1.0, 0.75)
	if _tool_name == "sword" and _class_id == "mage":
		col = Color(0.5, 1.0, 0.85, 0.7)
	elif _tool_name == "pickaxe":
		col = Color(1.0, 0.92, 0.7, 0.45)
	_trail.gradient.set_color(1, col)

func tool_tip_global() -> Vector2:
	return to_global(_front_arm.position + Vector2(0, 21).rotated(_front_arm.rotation))
