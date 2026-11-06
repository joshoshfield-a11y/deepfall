# player.gd — side-view platformer, grid collision against foreground blocks.
# Coyote time 0.12s, jump buffer 0.12s, double jump. Platforms are one-way:
# collision only when falling and the player's feet were above the platform.
extends Node2D

const TILE := 64
const SPEED := 260.0
const JUMP_VEL := -620.0
const GRAVITY := 1800.0
const COYOTE := 0.12
const BUFFER := 0.12

# Phase 8: three starting classes (the user's pick — tech soldier, hooded
# mage, red soldier). The skeleton hero is a SEPARATE/unlockable hero, NOT
# a fourth starting class, and is not selectable here.
# Per-class frame counts (assets/player_anim/<class>/, MANIFEST.json):
# tech loads from the flat assets/player_anim/ root (Phases 2-4 layout);
# red/mage load from their own subfolders. Sets with count 0 are not
# loaded. No fall/land frames exist for red or mage: airborne reuses
# thruster frame 0 and landing reuses the lowest crouch frame (real
# frames of that character, documented in the README) — distinct
# fall/land poses are still missing for red/mage.
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
# Phase 9: touch down = crouch while held on the ground; down + jump on a
# one-way platform = drop through it (same as S / Down + jump on desktop).
var touch_crouch := false
var touch_drop := false
var _drop_timer := 0.0
var _dying_timer := 0.0
var _double_jumped := false
var _crouching := false
# Phase 5 combat: HP, melee (J / touch ATK), hurt invulnerability, death.
# Melee is J ONLY on desktop — left-click stays mining (main._input).
var max_hp := 100
var hp := 100
var attack_cooldown := 0.0
var attack_timer := 0.0
var hurt_timer := 0.0
var dead := false
var _attack_struck := false
var _anim_melee: Array = []
var _anim_reload: Array = []
var _anim_thruster: Array = []
var _anim_dying: Array = []
var _anim_crouch: Array = []
var _anim_climb: Array = []
var _anim_swim: Array = []
# Phase 2 animation: frames sliced from the staged tech-soldier strips,
# bottom-centre on a common 128x195 canvas (see build_assets.py).
# Phase 4: walkcycle/fall wired from atlas-art/sliced/tech-walk-cycle and
# tech-fall-land, normalised to a common 256x195 canvas at the same 0.5
# scale (feet still land at +40px). Fall uses frames 0-2 ONLY: frame 3 of
# the source sheet is a front-facing standing pose, not a land pose.
var _anim_idle: Array = []
var _anim_walk: Array = []
var _anim_walkcycle: Array = []
var _anim_fall: Array = []
var _anim_shoot: Array = []
var _anim_time := 0.0
var _anim_state := "idle"
var _shoot_timer := 0.0
var _land_timer := 0.0
var _was_airborne := false
# Phase 10: equipped tool ("pickaxe" mines, weak 5-dmg attack; "sword"
# = class melee, cannot mine). Both owned from the start; main owns the
# authoritative copy and pushes it here via set_tool().
var tool := "pickaxe"
var _strike_dmg := 5
# Phase 10 procedural fluidity: walk cycle phase (frame units, 8 fps),
# jump-takeoff stretch timer, rim-glow sprite, melee slash arc.
var _walk_phase := 0.0
var _stretch_timer := 0.0
var _rim: Sprite2D = null
var _slash: Polygon2D = null
@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# Phase 10 rim: a slightly larger warm copy of the sprite drawn
	# BEHIND it (z -1) so the dark soldier reads against dark rock.
	# Visual only — collision is grid data, untouched.
	_rim = Sprite2D.new()
	_rim.z_index = -1
	_rim.modulate = Color(1.0, 0.78, 0.42, 0.5)
	add_child(_rim)
	# Phase 10 slash arc: a sector that sweeps with the melee swing so
	# the slash reads ATTACHED to the character instead of detached.
	_slash = Polygon2D.new()
	var pts := PackedVector2Array([Vector2.ZERO])
	var radius := 78.0
	for deg in range(-75, 76, 15):
		var a := deg_to_rad(float(deg))
		pts.append(Vector2(cos(a), sin(a)) * radius)
	_slash.polygon = pts
	_slash.color = Color(0.65, 0.85, 1.0, 0.85)
	_slash.position = Vector2(0, -20)
	_slash.visible = false
	add_child(_slash)
	set_class("tech")

func set_class(id: String) -> void:
	# (Re)loads every animation set for the class and applies its stats.
	# Main calls this on class pick, on save load, and on new run.
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
	_anim_idle.clear()
	_anim_walk.clear()
	_anim_shoot.clear()
	_anim_walkcycle.clear()
	_anim_fall.clear()
	_anim_melee.clear()
	_anim_reload.clear()
	_anim_thruster.clear()
	_anim_dying.clear()
	_anim_crouch.clear()
	_anim_climb.clear()
	_anim_swim.clear()
	for set_name in ["idle", "walk", "shoot", "walkcycle", "fall", "melee",
			"reload", "thruster", "dying", "crouch", "climb", "swim"]:
		var arr: Array = get("_anim_" + set_name)
		for i in range(int(counts.get(set_name, 0))):
			arr.append(load(base + "%s_%d.png" % [set_name, i]))
	_anim_time = 0.0
	_shoot_timer = 0.0
	_land_timer = 0.0
	_walk_phase = 0.0
	_stretch_timer = 0.0
	attack_timer = 0.0
	attack_cooldown = 0.0
	if not dead:
		hp = max_hp
	_sprite.position = Vector2(0, -8.75)  # feet at +40px (half_h) with 195px canvas at 0.5 scale
	_sprite.flip_h = false  # Phase 10: facing is done by scale.x (smooth flip), not flip_h
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.texture = _anim_idle[0]
	if _rim != null:
		_rim.texture = _anim_idle[0]
		_rim.position = _sprite.position
		_rim.scale = _sprite.scale * 1.07
		_rim.visible = not dead
	if _slash != null:
		_slash.visible = false
	print("DEEPFALL_CLASS_SET id=%s name=%s hp=%d melee=%d speed=%.2f ranged=%s" % [
		class_id, class_display_name, max_hp, melee_dmg, speed_mult, str(ranged)])

func set_tool(t: String) -> void:
	# Phase 10: main owns the tool state; this just mirrors it here.
	tool = "sword" if t == "sword" else "pickaxe"

func trigger_melee() -> void:
	# Phase 10: plays the melee swing frames WITHOUT a strike — used
	# for mining swings (pickaxe mining plays melee, not shoot).
	if dead:
		return
	attack_timer = 0.55
	_attack_struck = true  # no damage call: mining is not an attack

func trigger_shoot() -> void:
	_shoot_timer = 0.5  # 5 frames at 10 fps

func is_dead() -> bool:
	return dead

func try_attack() -> void:
	# Public for the touch ATK button; desktop J calls this too.
	# Phase 10: damage depends on the equipped tool. Sword = class
	# melee (15/20/10) or the mage orb; pickaxe = weak 5-dmg swing.
	if dead or attack_cooldown > 0.0:
		return
	if ranged and tool == "sword":
		# Hooded mage: fires a short-range orb bolt (12 dmg, ~320px range)
		# instead of swinging. Same J / ATK input and 0.55s cooldown as
		# melee; the shoot animation plays. No new damage type system.
		_shoot_timer = 0.5
		attack_cooldown = 0.55
		if main_node != null and main_node.has_method("spawn_orb"):
			main_node.call("spawn_orb", position, facing)
		return
	_strike_dmg = melee_dmg if tool == "sword" else 5
	attack_timer = 0.55  # 4 frames at ~8 fps
	attack_cooldown = 0.55
	_attack_struck = false

func take_hit(dmg: int, from_x: float) -> void:
	if dead or hurt_timer > 0.0:
		return
	hp -= dmg
	hurt_timer = 0.5  # 0.5s invulnerability after a hit
	vel.x = 220.0 if position.x >= from_x else -220.0
	if on_ground:
		vel.y = -150.0
	if hp <= 0:
		hp = 0
		dead = true
		if _rim != null:
			_rim.visible = false
		if _slash != null:
			_slash.visible = false
		# Phase 9: dying now PLAYS instead of instantly hiding the sprite —
		# the dying set (6 fps) runs for its full length, then the sprite
		# hides. Main's 1.2 s respawn timer outlasts every dying set
		# (tech 6f = 1.0 s, red 6f = 1.0 s, mage 5f = 0.83 s).
		if _anim_dying.is_empty():
			_sprite.visible = false
		else:
			_dying_timer = float(_anim_dying.size()) / 6.0
			_anim_time = 0.0
			_sprite.texture = _anim_dying[0]
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
	_sprite.visible = true
	_sprite.modulate = Color(1, 1, 1, 1)
	if _rim != null:
		_rim.visible = true
	if _slash != null:
		_slash.visible = false

func _physics_process(delta: float) -> void:
	if dead:
		# Phase 9: dying animation plays out (see take_hit); the sprite
		# hides only when the set finishes. Main respawns after 1.2 s.
		if _dying_timer > 0.0:
			_dying_timer = max(0.0, _dying_timer - delta)
			_anim_time += delta
			var total: float = float(_anim_dying.size()) / 6.0
			var idx: int = mini(int((total - _dying_timer) * 6.0), _anim_dying.size() - 1)
			_sprite.texture = _anim_dying[idx]
			_sprite.flip_h = facing < 0
			if _dying_timer <= 0.0:
				_sprite.visible = false
		return
	attack_cooldown = max(0.0, attack_cooldown - delta)
	hurt_timer = max(0.0, hurt_timer - delta)
	_drop_timer = max(0.0, _drop_timer - delta)
	# Melee strike moment: attack_timer crossing ~0.3s remaining (frame 2).
	if attack_timer > 0.0:
		if not _attack_struck and attack_timer <= 0.3:
			_attack_struck = true
			if main_node != null and main_node.has_method("player_attack_hit"):
				main_node.call("player_attack_hit", position, facing, _strike_dmg)
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
	# Phase 9: crouch = hold S / Down (desktop) or push the left stick down
	# (touch) while on the ground. Visual only for the collision box, but
	# movement is halved while crouched. Drop-through (below) takes
	# priority when jump is pressed at the same time.
	_crouching = on_ground and (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or touch_crouch)
	if move != 0.0:
		facing = 1 if move > 0.0 else -1
	vel.x = move * SPEED * speed_mult * (0.5 if _crouching else 1.0)
	vel.y += GRAVITY * delta
	if vel.y > 1200.0:
		vel.y = 1200.0
	var jump_down := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or touch_jump
	if (jump_down and not _prev_jump) or Input.is_action_just_pressed("ui_accept"):
		buffer_timer = BUFFER
	else:
		buffer_timer = max(0.0, buffer_timer - delta)
	_prev_jump = jump_down
	if on_ground:
		coyote_timer = COYOTE
		jumps_left = 2
		_double_jumped = false
	else:
		coyote_timer = max(0.0, coyote_timer - delta)
	# Phase 9: drop through a one-way platform — S / Down + jump (desktop)
	# or left-stick-down + jump (touch), while standing on a platform only.
	# Solid ground is unaffected: that input jumps normally there.
	var drop_down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or touch_drop
	if buffer_timer > 0.0 and drop_down and on_ground and _standing_on_platform():
		buffer_timer = 0.0
		coyote_timer = 0.0
		_drop_timer = 0.25
		on_ground = false
		position.y += 4.0
		vel.y = 60.0
	elif buffer_timer > 0.0 and (on_ground or coyote_timer > 0.0 or jumps_left > 0):
		# first jump from ground/coyote, second jump in air (double jump)
		if on_ground or coyote_timer > 0.0:
			jumps_left = 1
		else:
			jumps_left -= 1
			_double_jumped = true
		vel.y = JUMP_VEL
		buffer_timer = 0.0
		coyote_timer = 0.0
		on_ground = false
		_stretch_timer = 0.12  # Phase 10: stretch on jump takeoff
	var was_ground := on_ground
	_move_axis(delta, true)   # X
	_move_axis(delta, false)  # Y
	if on_ground and not was_ground and _was_airborne:
		_land_timer = 0.15  # squash on landing; does not interrupt movement
	_was_airborne = not on_ground
	_update_animation(delta, move)

func _update_animation(delta: float, move: float) -> void:
	_anim_time += delta
	_shoot_timer = max(0.0, _shoot_timer - delta)
	_land_timer = max(0.0, _land_timer - delta)
	var frames: Array
	var fps := 4.0
	if attack_timer > 0.0:
		# Melee overrides walk/idle/shoot while the swing plays.
		# Same 0.5 scale / -8.75 offset as idle/walk: the melee canvas
		# is also 195px tall, so it reads at the same size.
		frames = _anim_melee; fps = 8.0
	elif _shoot_timer > 0.0:
		frames = _anim_shoot; fps = 10.0
	elif _land_timer > 0.0:
		# Land: the LOWEST crouch frame, consistently for all three classes.
		# Tech has real fall frames, so its lowest fall frame is the land
		# pose; red/mage have no fall frames, so their lowest crouch frame
		# (last index of the set) is the land pose instead.
		frames = [_anim_fall[_anim_fall.size() - 1]] if not _anim_fall.is_empty() else [_anim_crouch[_anim_crouch.size() - 1]]; fps = 1.0
	elif _crouching and not _anim_crouch.is_empty():
		# Phase 9: hold-down crouch while on the ground (S / Down, or the
		# left stick pushed down on touch). Loops at 4 fps.
		frames = _anim_crouch; fps = 4.0
	elif not on_ground:
		# Phase 9: thruster plays while airborne AFTER the double jump
		# (all three classes have a thruster set now). Before the double
		# jump, the old air poses still apply.
		if _double_jumped and not _anim_thruster.is_empty():
			frames = _anim_thruster; fps = 8.0
		elif not _anim_fall.is_empty():
			frames = [_anim_fall[1]] if vel.y > 0.0 else [_anim_fall[0]]; fps = 1.0
		else:
			frames = [_anim_thruster[0]]; fps = 1.0
	elif move != 0.0:
		frames = _anim_walkcycle; fps = 8.0
	else:
		frames = _anim_idle; fps = 4.0
	# Phase 10 fluidity: the walk cycle is 4 frames at 8 fps, but the
	# contact/lunge frames hold longer than the passing frames
	# (durations 1.3 / 0.7 / 1.3 / 0.7 frame-units) so the stride reads
	# weighted instead of metronomic, and a small vertical bob tied to
	# the step cycle (±3 px, peaking on the passing frames) smooths the
	# motion. No new frames are faked — this is playback shaping only.
	var walking := move != 0.0 and on_ground and attack_timer <= 0.0 and _shoot_timer <= 0.0
	var idx := 0
	if frames == _anim_walkcycle and walking:
		_walk_phase = fmod(_walk_phase + delta * 8.0, 4.0)
		if _walk_phase < 1.3:
			idx = 0
		elif _walk_phase < 2.0:
			idx = 1
		elif _walk_phase < 3.3:
			idx = 2
		else:
			idx = 3
	else:
		idx = int(_anim_time * fps) % frames.size()
		if not walking:
			_walk_phase = 0.0
	if attack_timer > 0.0:
		idx = min(int((0.55 - attack_timer) * 8.0), frames.size() - 1)
	elif _shoot_timer > 0.0:
		idx = min(int((0.5 - _shoot_timer) * 10.0), frames.size() - 1)
	_sprite.texture = frames[idx]
	# Hurt flicker: red-ish modulate during invulnerability, restored after.
	if hurt_timer > 0.0:
		_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	else:
		_sprite.modulate = Color(1, 1, 1, 1)
	# Phase 10 scale: land squash (0.15 s), jump-takeoff stretch
	# (0.12 s), idle breathing (2% at 2.2 rad/s). Feet stay anchored:
	# the sprite origin is its centre and position.y is only moved by
	# the walk bob, which is 0 on the contact frames.
	_stretch_timer = max(0.0, _stretch_timer - delta)
	var sx := 0.5
	var sy := 0.5
	if _land_timer > 0.0:
		sx = 0.55
		sy = 0.42
	elif _stretch_timer > 0.0:
		sx = 0.46
		sy = 0.54
	elif frames == _anim_idle:
		sy = 0.5 * (1.0 + 0.02 * sin(_anim_time * 2.2))
	# Smooth facing flip: scale.x lerps across 0 instead of snapping
	# (flip_h is never used in the alive path). ~14/s reaches the new
	# facing in ~0.1 s — a quick turn, not a freeze.
	_sprite.scale.x = lerpf(_sprite.scale.x, float(facing) * sx, minf(1.0, 14.0 * delta))
	_sprite.scale.y = sy
	# Walk bob: 0 on contact frames (phase 0/2), -3 px on passing
	# frames (phase 1/3). Idle keeps the base -8.75 offset exactly.
	if walking:
		_sprite.position.y = -8.75 - 3.0 * absf(sin(_walk_phase * PI / 2.0))
	else:
		_sprite.position.y = -8.75
	# Phase 10 rim: mirrors the sprite (same texture, 7% larger, warm,
	# semi-transparent) so the dark figure reads on dark rock.
	if _rim != null:
		_rim.texture = _sprite.texture
		_rim.scale = _sprite.scale * 1.07
		_rim.position = _sprite.position
		_rim.visible = not dead
	# Phase 10 slash arc: sweeps -65°..+65° with the swing and fades,
	# so the blue slash reads attached to the character. Only during a
	# melee swing (attack_timer); the mage orb path never sets it.
	if _slash != null:
		if attack_timer > 0.0:
			var prog := (0.55 - attack_timer) / 0.55
			_slash.visible = true
			_slash.rotation = lerpf(-1.15, 1.15, prog)
			_slash.scale = Vector2(float(facing), 1.0)
			_slash.position = Vector2(float(facing) * 8.0, -20.0)
			_slash.color = Color(0.65, 0.85, 1.0, 0.85 * (1.0 - 0.6 * prog))
		else:
			_slash.visible = false
	# camera lookahead: ~1 tile in facing direction, smoothed by Camera2D
	var cam: Camera2D = get_node_or_null("Camera2D")
	if cam != null:
		cam.offset = cam.offset.lerp(Vector2(facing * 32.0, 0.0), 1.0 - exp(-5.0 * delta))

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true  # world border is solid
	var t: int = fg[cy][cx]
	return t != 0 and t != 7

func _platform(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	return fg[cy][cx] == 7

func _standing_on_platform() -> bool:
	# True when the cell directly under the player's feet is a one-way
	# platform (id 7) and not solid ground. Used for drop-through.
	var cx := int(floor(position.x / TILE))
	var cy := int(floor((position.y + half_h + 1.0) / TILE))
	return _platform(cx, cy)

func _move_axis(delta: float, x_axis: bool) -> void:
	if x_axis:
		position.x += vel.x * delta
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
	else:
		var prev_feet := position.y + half_h
		position.y += vel.y * delta
		var left := int(floor((position.x - half_w + 1) / TILE))
		var right := int(floor((position.x + half_w - 1) / TILE))
		on_ground = false
		if vel.y > 0:
			var cy := int(floor((position.y + half_h) / TILE))
			for cx in range(left, right + 1):
				# Phase 9: while _drop_timer runs (drop-through), one-way
				# platforms are ignored entirely — the player falls past.
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

func cell() -> Vector2i:
	return Vector2i(int(floor(position.x / TILE)), int(floor(position.y / TILE)))
