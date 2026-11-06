# player.gd — DEEPFALL side-view platformer hero (Phase 11 physics pass).
#
# Grid collision against foreground blocks (solid = t != 0 and t != 7;
# 7 = one-way platform landed on only from above) PLUS solid collision
# with physics props (crates / barrels / pots, see phys_prop.gd): the
# hero stands on them and pushes the pushable ones while on the ground.
#
# Phase 11 movement model (was: velocity snapped to input every frame,
# which silently cancelled all knockback):
#   * acceleration / friction on the ground, softer air control
#   * variable jump height (release JUMP early = shorter hop), apex
#     hang while JUMP is held, heavier gravity when falling
#   * coyote 0.12 s, jump buffer 0.12 s, double jump (kept)
#   * real knockback: hits launch the hero up and away; control is
#     reduced for 0.25 s so the impulse actually plays out
#   * skills: DASH (burst + i-frames, one air dash per airtime) and
#     SLAM (in air: dive; landing sends a shockwave that knocks enemies
#     back and breaks / launches props)
#   * aim vector (right stick / mouse) drives swing direction and the
#     rig's arm, and the camera leans slightly toward it
# Visuals: the Terraria-style pixel paper-doll (hero_rig.gd). The legacy
# frame sets are still loaded for the older self-tests, but hidden.
extends Node2D

const TILE := 64
const SPEED := 270.0
const JUMP_VEL := -640.0
const GRAVITY := 1800.0
const FALL_MULT := 1.3
const APEX_MULT := 0.55
const JUMP_CUT := 0.45
const COYOTE := 0.12
const BUFFER := 0.12
const ACCEL_GROUND := 2600.0
const ACCEL_AIR := 1600.0
const FRICTION := 3000.0
const MAX_FALL := 1150.0
const DASH_SPEED := 760.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 0.75
const SLAM_SPEED := 1300.0
const SLAM_COOLDOWN := 1.4
const SWING_TIME := 0.38

const CLASS_DATA := {
	"tech": {"name": "Tech Soldier", "max_hp": 100, "melee": 15,
		"speed": 1.0, "ranged": false,
		"counts": {"idle": 9, "walk": 9, "shoot": 5, "walkcycle": 4,
			"fall": 3, "melee": 4, "reload": 0, "thruster": 6,
			"dying": 6, "crouch": 4, "climb": 0, "swim": 0}},
	"red": {"name": "Red Soldier", "max_hp": 120, "melee": 20,
		"speed": 0.9, "ranged": false,
		"counts": {"idle": 9, "walk": 9, "shoot": 5, "walkcycle": 4,
			"fall": 0, "melee": 4, "reload": 4, "thruster": 6,
			"dying": 6, "crouch": 4, "climb": 4, "swim": 3}},
	"mage": {"name": "Hooded Mage", "max_hp": 80, "melee": 10,
		"speed": 1.0, "ranged": true,
		"counts": {"idle": 7, "walk": 7, "shoot": 5, "walkcycle": 4,
			"fall": 0, "melee": 4, "reload": 7, "thruster": 5,
			"dying": 5, "crouch": 4, "climb": 4, "swim": 4}},
}
const HERO_RIG := preload("res://scripts/hero_rig.gd")

var class_id := "tech"
var class_display_name := "Tech Soldier"
var melee_dmg := 15
var speed_mult := 1.0
var ranged := false

var fg: Array = []
var main_node: Node = null
var vel := Vector2.ZERO
var facing := 1
var coyote_timer := 0.0
var buffer_timer := 0.0
var jumps_left := 2
var on_ground := false
var half_w := 14.0
var half_h := 40.0
var _prev_jump := false
var touch_move := 0.0
var touch_jump := false
var touch_crouch := false
var touch_drop := false
# Phase 11: aim (unit vector, world space). aiming = right stick held.
var aim := Vector2(1, 0)
var aiming := false
var _drop_timer := 0.0
var _dying_timer := 0.0
var _double_jumped := false
var _crouching := false
var _jump_cut_done := false
var _kb_timer := 0.0
var dash_timer := 0.0
var dash_cooldown := 0.0
var _air_dash_used := false
var slam_active := false
var slam_cooldown := 0.0
var _dust_timer := 0.0
var _fall_peak := 0.0
var max_hp := 100
var hp := 100
var attack_cooldown := 0.0
var attack_timer := 0.0
var hurt_timer := 0.0
var dead := false
var _attack_struck := false
var _swing_aim := Vector2(1, 0)
var _anim_melee: Array = []
var _anim_reload: Array = []
var _anim_thruster: Array = []
var _anim_dying: Array = []
var _anim_crouch: Array = []
var _anim_climb: Array = []
var _anim_swim: Array = []
var _anim_idle: Array = []
var _anim_walk: Array = []
var _anim_walkcycle: Array = []
var _anim_fall: Array = []
var _anim_shoot: Array = []
var _anim_time := 0.0
var _shoot_timer := 0.0
var _land_timer := 0.0
var _was_airborne := false
var tool := "pickaxe"
var _strike_dmg := 5
var _stretch_timer := 0.0
var rig: Node2D = null
var _light: PointLight2D = null
var _cam_look := Vector2.ZERO
@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	_sprite.visible = false
	z_index = 3
	rig = HERO_RIG.new()
	rig.name = "Rig"
	add_child(rig)
	# Soft personal light so the hero always reads against dark rock.
	_light = PointLight2D.new()
	var gt := GradientTexture2D.new()
	gt.width = 256; gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	_light.texture = gt
	_light.texture_scale = 1.6
	_light.energy = 0.55
	_light.color = Color(1.0, 0.85, 0.65)
	_light.position = Vector2(0, -10)
	add_child(_light)
	set_class("tech")

func set_class(id: String) -> void:
	if not CLASS_DATA.has(id):
		id = "tech"
	var cd: Dictionary = CLASS_DATA[id]
	class_id = id
	class_display_name = String(cd["name"])
	max_hp = int(cd["max_hp"])
	melee_dmg = int(cd["melee"])
	speed_mult = float(cd["speed"])
	ranged = bool(cd["ranged"])
	var counts: Dictionary = cd["counts"]
	var base := "res://assets/player_anim/"
	if id != "tech":
		base = "res://assets/player_anim/%s/" % id
	for set_name in ["idle", "walk", "shoot", "walkcycle", "fall", "melee",
			"reload", "thruster", "dying", "crouch", "climb", "swim"]:
		var arr: Array = get("_anim_" + set_name)
		arr.clear()
		for i in range(int(counts.get(set_name, 0))):
			arr.append(load(base + "%s_%d.png" % [set_name, i]))
	_anim_time = 0.0
	_shoot_timer = 0.0
	_land_timer = 0.0
	_stretch_timer = 0.0
	attack_timer = 0.0
	attack_cooldown = 0.0
	if not dead:
		hp = max_hp
	_sprite.texture = _anim_idle[0]
	if rig != null:
		rig.call("set_class", id)
		rig.call("set_tool", tool)
	print("DEEPFALL_CLASS_SET id=%s name=%s hp=%d melee=%d speed=%.2f ranged=%s" % [
		class_id, class_display_name, max_hp, melee_dmg, speed_mult, str(ranged)])

func set_tool(t: String) -> void:
	tool = "sword" if t == "sword" else "pickaxe"
	if rig != null:
		rig.call("set_tool", tool)

func set_aim(v: Vector2, held: bool) -> void:
	aiming = held
	if v.length() > 0.05:
		aim = v.normalized()
		if held and absf(aim.x) > 0.15:
			facing = 1 if aim.x > 0.0 else -1

func trigger_melee() -> void:
	# Mining swing (no damage call) toward the current aim.
	if dead:
		return
	_swing_aim = aim if aiming else Vector2(facing, 0)
	attack_timer = SWING_TIME
	_attack_struck = true
	_sfx("swing", 0.15, -6.0)

func trigger_shoot() -> void:
	_shoot_timer = 0.3

func is_dead() -> bool:
	return dead

func try_attack() -> void:
	try_attack_dir(aim if aiming else Vector2(facing, 0))

func try_attack_dir(dir: Vector2) -> void:
	if dead or attack_cooldown > 0.0:
		return
	if dir.length() < 0.05:
		dir = Vector2(facing, 0)
	dir = dir.normalized()
	if absf(dir.x) > 0.15:
		facing = 1 if dir.x > 0.0 else -1
	_swing_aim = dir
	if ranged and tool == "sword":
		_shoot_timer = 0.3
		attack_timer = SWING_TIME * 0.6
		_attack_struck = true
		attack_cooldown = 0.45
		_sfx("dash", 0.1, -4.0)
		if main_node != null and main_node.has_method("spawn_orb"):
			main_node.call("spawn_orb", position, facing, dir)
		return
	_strike_dmg = melee_dmg if tool == "sword" else 5
	_sfx("swing", 0.12)
	attack_timer = SWING_TIME
	attack_cooldown = 0.42 if tool == "sword" else 0.5
	_attack_struck = false

func try_dash() -> void:
	if dead or dash_cooldown > 0.0 or dash_timer > 0.0:
		return
	if not on_ground and _air_dash_used:
		return
	var dir := float(facing)
	if absf(touch_move) > 0.2:
		dir = signf(touch_move)
	facing = int(dir)
	dash_timer = DASH_TIME
	dash_cooldown = DASH_COOLDOWN
	if not on_ground:
		_air_dash_used = true
	vel = Vector2(dir * DASH_SPEED, 0.0)
	hurt_timer = maxf(hurt_timer, DASH_TIME + 0.05)
	_sfx("dash")
	_fx_burst(position + Vector2(0, half_h - 4), Color(0.8, 0.8, 0.85), 10, 180.0)

func try_slam() -> void:
	if dead or slam_cooldown > 0.0 or slam_active:
		return
	slam_cooldown = SLAM_COOLDOWN
	if on_ground:
		# grounded: hop then dive, so the slam always has an impact
		vel.y = -420.0
		on_ground = false
	slam_active = true
	dash_timer = 0.0
	_sfx("dash", 0.05, -3.0)

func take_hit(dmg: int, from_x: float) -> void:
	if dead or hurt_timer > 0.0:
		return
	hp -= dmg
	hurt_timer = 0.6
	var dir := 1.0 if position.x >= from_x else -1.0
	vel.x = dir * 380.0
	vel.y = -300.0
	on_ground = false
	_kb_timer = 0.25
	dash_timer = 0.0
	slam_active = false
	if main_node != null:
		var fx: Node = main_node.get("fx")
		if fx != null:
			fx.shake(9.0)
			fx.hitstop(0.06)
			fx.sfx("hurt")
			fx.rumble(90)
			fx.float_text(position + Vector2(0, -56), "-%d" % dmg, Color(1, 0.35, 0.3), true)
			fx.burst(position, Color(0.9, 0.15, 0.2), 10, 260.0)
	if hp <= 0:
		hp = 0
		dead = true
		if not _anim_dying.is_empty():
			_dying_timer = float(_anim_dying.size()) / 6.0
		if main_node != null and main_node.has_method("player_died"):
			main_node.call("player_died")

func respawn_at(spawn_pos: Vector2) -> void:
	position = spawn_pos
	vel = Vector2.ZERO
	hp = max_hp
	dead = false
	hurt_timer = 0.0
	attack_timer = 0.0
	attack_cooldown = 0.0
	_dying_timer = 0.0
	_double_jumped = false
	_crouching = false
	_drop_timer = 0.0
	_kb_timer = 0.0
	dash_timer = 0.0
	slam_active = false
	_sprite.visible = false

func _sfx(n: String, pv := 0.08, db := 0.0) -> void:
	if main_node != null and main_node.get("fx") != null:
		main_node.fx.sfx(n, pv, db)

func _fx_burst(pos: Vector2, col: Color, n: int, spd: float) -> void:
	if main_node == null:
		return
	var fx: Node = main_node.get("fx")
	if fx != null:
		fx.burst(pos, col, n, spd, 900.0, 5.0, 0.45, 0.9)

func _physics_process(delta: float) -> void:
	if dead:
		if _dying_timer > 0.0:
			_dying_timer = max(0.0, _dying_timer - delta)
		_animate(delta, 0.0)
		return
	attack_cooldown = max(0.0, attack_cooldown - delta)
	hurt_timer = max(0.0, hurt_timer - delta)
	_drop_timer = max(0.0, _drop_timer - delta)
	_kb_timer = max(0.0, _kb_timer - delta)
	dash_cooldown = max(0.0, dash_cooldown - delta)
	slam_cooldown = max(0.0, slam_cooldown - delta)
	if attack_timer > 0.0:
		if not _attack_struck and attack_timer <= SWING_TIME * 0.55:
			_attack_struck = true
			if main_node != null and main_node.has_method("player_attack_hit"):
				main_node.call("player_attack_hit", position, facing, _strike_dmg, _swing_aim)
		attack_timer = max(0.0, attack_timer - delta)
	if Input.is_key_pressed(KEY_J):
		try_attack()
	var move := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move += 1.0
	if touch_move != 0.0:
		move = touch_move
	_crouching = on_ground and (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or touch_crouch)
	if move != 0.0 and not aiming and attack_timer <= 0.0 and _kb_timer <= 0.0:
		facing = 1 if move > 0.0 else -1
	var target := move * SPEED * speed_mult * (0.5 if _crouching else 1.0)
	var jump_down := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or touch_jump
	if dash_timer > 0.0:
		dash_timer = max(0.0, dash_timer - delta)
		vel.y = 0.0
		if int(dash_timer * 60.0) % 2 == 0:
			_fx_burst(position, Color(0.75, 0.85, 1.0), 2, 60.0)
		if dash_timer <= 0.0:
			vel.x *= 0.45
	elif slam_active:
		vel.x = move_toward(vel.x, 0.0, FRICTION * delta)
		if vel.y < -60.0:
			vel.y += GRAVITY * 2.0 * delta
		else:
			vel.y = SLAM_SPEED
	else:
		var accel := ACCEL_GROUND if on_ground else ACCEL_AIR
		if _kb_timer > 0.0:
			accel *= 0.2
		if move != 0.0:
			vel.x = move_toward(vel.x, target, accel * delta)
		else:
			vel.x = move_toward(vel.x, 0.0, (FRICTION if on_ground else ACCEL_AIR * 0.6) * (0.25 if _kb_timer > 0.0 else 1.0) * delta)
		var g := GRAVITY
		if vel.y > 0.0:
			g *= FALL_MULT
		elif jump_down and absf(vel.y) < 120.0:
			g *= APEX_MULT
		vel.y += g * delta
		if not jump_down and vel.y < -200.0 and not _jump_cut_done and _kb_timer <= 0.0:
			vel.y *= JUMP_CUT
			_jump_cut_done = true
	if vel.y > MAX_FALL and not slam_active:
		vel.y = MAX_FALL
	if (jump_down and not _prev_jump) or Input.is_action_just_pressed("ui_accept"):
		buffer_timer = BUFFER
	else:
		buffer_timer = max(0.0, buffer_timer - delta)
	_prev_jump = jump_down
	if on_ground:
		coyote_timer = COYOTE
		jumps_left = 2
		_double_jumped = false
		_air_dash_used = false
	else:
		coyote_timer = max(0.0, coyote_timer - delta)
	var drop_down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or touch_drop
	if buffer_timer > 0.0 and drop_down and on_ground and _standing_on_platform():
		buffer_timer = 0.0
		coyote_timer = 0.0
		_drop_timer = 0.25
		on_ground = false
		position.y += 4.0
		vel.y = 60.0
	elif buffer_timer > 0.0 and not slam_active and (on_ground or coyote_timer > 0.0 or jumps_left > 0):
		if on_ground or coyote_timer > 0.0:
			jumps_left = 1
			_fx_burst(position + Vector2(0, half_h - 4), Color(0.7, 0.66, 0.6), 8, 160.0)
		else:
			jumps_left -= 1
			_double_jumped = true
			_fx_burst(position + Vector2(0, half_h - 4), Color(0.6, 0.9, 1.0), 12, 220.0)
		vel.y = JUMP_VEL
		_sfx("jump", 0.05, 0.0 if not _double_jumped else 2.0)
		dash_timer = 0.0
		buffer_timer = 0.0
		coyote_timer = 0.0
		on_ground = false
		_jump_cut_done = false
		_stretch_timer = 0.12
	var was_ground := on_ground
	var fall_speed := vel.y
	_move_axis(delta, true)
	_move_axis(delta, false)
	if on_ground and not was_ground and _was_airborne:
		_land_timer = 0.13
		_jump_cut_done = false
		_sfx("land", 0.1, -6.0 if fall_speed < 650.0 else 0.0)
		if fall_speed > 650.0 or slam_active:
			_fx_burst(position + Vector2(0, half_h - 4), Color(0.72, 0.68, 0.62), 14 if slam_active else 8, 240.0)
		if slam_active:
			slam_active = false
			if main_node != null and main_node.has_method("slam_impact"):
				main_node.call("slam_impact", position + Vector2(0, half_h))
	if on_ground and absf(vel.x) > 160.0:
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.16
			_fx_burst(position + Vector2(-facing * 10, half_h - 2), Color(0.62, 0.58, 0.52), 2, 70.0)
	_was_airborne = not on_ground
	_animate(delta, move)

func _animate(delta: float, move: float) -> void:
	_anim_time += delta
	_shoot_timer = max(0.0, _shoot_timer - delta)
	_land_timer = max(0.0, _land_timer - delta)
	_stretch_timer = max(0.0, _stretch_timer - delta)
	if rig == null:
		return
	rig.facing = facing
	var swing := -1.0
	if attack_timer > 0.0:
		swing = clampf(1.0 - attack_timer / SWING_TIME, 0.0, 1.0)
	rig.call("animate", {
		"delta": delta, "vel": vel, "on_ground": on_ground, "move": move,
		"crouch": _crouching, "swing": swing,
		"aim": _swing_aim if attack_timer > 0.0 else aim, "aiming": aiming,
		"dash": dash_timer > 0.0 or slam_active, "hurt": hurt_timer > 0.0 and dash_timer <= 0.0,
		"dead": dead, "land": _land_timer, "stretch": _stretch_timer,
		"speed_max": SPEED * speed_mult})
	var cam: Camera2D = get_node_or_null("Camera2D")
	if cam != null:
		var look := Vector2(facing * 40.0, clampf(vel.y * 0.04, -20.0, 40.0))
		if aiming:
			look += aim * 60.0
		var shake := Vector2.ZERO
		if main_node != null and main_node.get("fx") != null:
			shake = main_node.fx.shake_vec
		_cam_look = _cam_look.lerp(look, 1.0 - exp(-4.0 * delta))
		cam.offset = _cam_look + shake

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true
	var t: int = fg[cy][cx]
	return t != 0 and t != 7

func _platform(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	return fg[cy][cx] == 7

func _standing_on_platform() -> bool:
	var cx := int(floor(position.x / TILE))
	var cy := int(floor((position.y + half_h + 1.0) / TILE))
	return _platform(cx, cy)

func _props() -> Array:
	if main_node == null:
		return []
	var p = main_node.get("phys_props")
	return p if p is Array else []

func _my_rect() -> Rect2:
	return Rect2(position - Vector2(half_w, half_h), Vector2(half_w * 2.0, half_h * 2.0))

func _move_axis(delta: float, x_axis: bool) -> void:
	if x_axis:
		var dx := vel.x * delta
		position.x += dx
		var top := int(floor((position.y - half_h) / TILE))
		var bot := int(floor((position.y + half_h - 1) / TILE))
		if vel.x > 0:
			var cx := int(floor((position.x + half_w) / TILE))
			for cy in range(top, bot + 1):
				if _solid(cx, cy):
					position.x = cx * TILE - half_w - 0.01
					vel.x = 0.0
					break
		elif vel.x < 0:
			var cx := int(floor((position.x - half_w) / TILE))
			for cy in range(top, bot + 1):
				if _solid(cx, cy):
					position.x = (cx + 1) * TILE + half_w + 0.01
					vel.x = 0.0
					break
		# props: push the pushable ones (when grounded), then resolve
		for pr in _props():
			if not is_instance_valid(pr) or pr.broken:
				continue
			var r: Rect2 = pr.rect()
			var me := _my_rect()
			if not me.intersects(r) or me.end.y <= r.position.y + 6.0:
				continue
			if dx > 0.0 and position.x < r.get_center().x:
				var overlap := me.end.x - r.position.x
				if on_ground:
					pr.push(overlap * 0.85)
				r = pr.rect()
				position.x = minf(position.x, r.position.x - half_w - 0.01)
				vel.x = minf(vel.x, 150.0 * speed_mult) if on_ground else 0.0
			elif dx < 0.0 and position.x > r.get_center().x:
				var overlap2 := r.end.x - me.position.x
				if on_ground:
					pr.push(-overlap2 * 0.85)
				r = pr.rect()
				position.x = maxf(position.x, r.end.x + half_w + 0.01)
				vel.x = maxf(vel.x, -150.0 * speed_mult) if on_ground else 0.0
	else:
		var prev_feet := position.y + half_h
		var prev_head := position.y - half_h
		position.y += vel.y * delta
		var left := int(floor((position.x - half_w + 1) / TILE))
		var right := int(floor((position.x + half_w - 1) / TILE))
		on_ground = false
		if vel.y > 0:
			var cy := int(floor((position.y + half_h) / TILE))
			for cx in range(left, right + 1):
				if _solid(cx, cy) or (_drop_timer <= 0.0 and _platform(cx, cy) and prev_feet <= cy * TILE + 1):
					position.y = cy * TILE - half_h - 0.01
					vel.y = 0.0
					on_ground = true
					break
		elif vel.y < 0:
			var cy := int(floor((position.y - half_h) / TILE))
			for cx in range(left, right + 1):
				if _solid(cx, cy):
					position.y = (cy + 1) * TILE + half_h + 0.01
					vel.y = 0.0
					break
		for pr in _props():
			if not is_instance_valid(pr) or pr.broken:
				continue
			var r: Rect2 = pr.rect()
			if not _my_rect().intersects(r):
				continue
			if vel.y >= 0.0 and prev_feet <= r.position.y + 2.0:
				position.y = r.position.y - half_h - 0.01
				vel.y = 0.0
				on_ground = true
			elif vel.y < 0.0 and prev_head >= r.end.y - 2.0:
				position.y = r.end.y + half_h + 0.01
				vel.y = 0.0

func cell() -> Vector2i:
	return Vector2i(int(floor(position.x / TILE)), int(floor(position.y / TILE)))
