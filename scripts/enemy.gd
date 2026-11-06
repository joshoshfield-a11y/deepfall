# enemy.gd — DEEPFALL Phase 5: one enemy class driven by a stats dict.
# Phase 9: the cave bat FLIES (sine hover, no ground collision); the other
# five slugs stay ground-walking. The bat's walk frames still read as a
# low sway — that is the staged art, not the movement.
# player uses (solid = t != 0 and t != 7; 7 = one-way platform, landed on
# only when falling with feet above it). An enemy that spawns with no
# ground under it falls with gravity until it lands — it never teleports.
#
# Collision boxes are deliberately modest vs the 256px-tall art (the art
# is wide/flourished; the box is the body): half_w/half_h per slug below.
# Sprite scale is a uniform 0.5, so the 256px canvas reads 128px tall;
# the sprite is anchored bottom-centre, feet at position.y + half_h.
#
# Attack has a real windup: the first ~0.35s is windup, damage lands at
# the strike point (~0.4s in, frame 2-ish), then a 1.0s cooldown — the
# player can dodge out of range during the windup.
extends Node2D

signal died(enemy)

const TILE := 64
const GRAVITY := 1800.0
const WINDUP := 0.35
const STRIKE_AT := 0.40
const COOLDOWN := 1.0

# slug -> {hp, speed, damage, aggro, range, half_w, half_h, walk, attack, wander}
# walk/attack are EXACT frame counts from assets/enemies/MANIFEST.md:
# ore-mimic attack is 3 frames (never index attack[3]); tunnel-worm
# walk is 2 frames (walk_0..1 only).
const STATS := {
	"cave-bat-swarm": {"hp": 10, "speed": 150.0, "damage": 5, "aggro": 260.0, "range": 48.0, "half_w": 20.0, "half_h": 16.0, "walk": 4, "attack": 4, "wander": true},
	"miner-ghoul": {"hp": 20, "speed": 90.0, "damage": 8, "aggro": 300.0, "range": 56.0, "half_w": 14.0, "half_h": 32.0, "walk": 4, "attack": 4, "wander": true},
	"rock-golem": {"hp": 50, "speed": 45.0, "damage": 12, "aggro": 240.0, "range": 64.0, "half_w": 22.0, "half_h": 40.0, "walk": 4, "attack": 4, "wander": true},
	"cave-spider": {"hp": 15, "speed": 130.0, "damage": 6, "aggro": 320.0, "range": 52.0, "half_w": 24.0, "half_h": 24.0, "walk": 4, "attack": 4, "wander": true},
	"ore-mimic": {"hp": 30, "speed": 60.0, "damage": 10, "aggro": 200.0, "range": 60.0, "half_w": 20.0, "half_h": 32.0, "walk": 4, "attack": 3, "wander": false},
	"tunnel-worm": {"hp": 25, "speed": 70.0, "damage": 8, "aggro": 280.0, "range": 64.0, "half_w": 26.0, "half_h": 20.0, "walk": 2, "attack": 4, "wander": true},
}

var slug := ""
var spawn_id := -1
var fg: Array = []
var player: Node2D = null
var main_node: Node = null

var hp := 10
var max_hp := 10
var speed := 90.0
var damage := 5
var aggro_range := 260.0
var attack_range := 48.0
var half_w := 14.0
var half_h := 32.0
var _wander := true

var vel := Vector2.ZERO
var facing := -1
var on_ground := false
var dead := false

var _walk_frames: Array = []
var _attack_frames: Array = []
var _idle_frame: Texture2D = null
var _sprite: Sprite2D = null
var _anim_time := 0.0
var _moving := false

var _wander_dir := 1
var _wander_timer := 0.0
var _attack_timer := 0.0
var _attack_duration := 0.5
var _strike_at := 0.4
var _struck := false
var _cooldown_timer := 0.0
var _hurt_timer := 0.0
var _kb_timer := 0.0
var _kb_vel := 0.0
# Phase 9: the cave bat FLIES now (sine hover around its spawn height, no
# ground collision, no ledge logic). Every other slug stays ground-walking.
var _flying := false
var _hover_base_y := 0.0
var _hover_time := 0.0

func setup(p_slug: String, p_fg: Array, p_player: Node2D, p_main: Node) -> void:
	slug = p_slug
	fg = p_fg
	player = p_player
	main_node = p_main
	var st: Dictionary = STATS[slug]
	max_hp = int(st["hp"])
	hp = max_hp
	speed = float(st["speed"])
	damage = int(st["damage"])
	aggro_range = float(st["aggro"])
	attack_range = float(st["range"])
	half_w = float(st["half_w"])
	half_h = float(st["half_h"])
	_wander = bool(st["wander"])
	_flying = slug == "cave-bat-swarm"
	for i in range(int(st["walk"])):
		_walk_frames.append(load("res://assets/enemies/%s/walk_%d.png" % [slug, i]))
	for i in range(int(st["attack"])):
		_attack_frames.append(load("res://assets/enemies/%s/attack_%d.png" % [slug, i]))
	_idle_frame = load("res://assets/enemies/%s/idle.png" % slug)
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(0.5, 0.5)
	# 256px canvas at 0.5 = 128px tall; feet at +half_h, so the sprite
	# centre sits half_h - 64 above the node origin.
	_sprite.position = Vector2(0, half_h - 64.0)
	_sprite.texture = _idle_frame
	add_child(_sprite)
	_wander_dir = 1 if randi() % 2 == 0 else -1
	_wander_timer = randf_range(1.5, 3.5)

func take_hit(dmg: int, from_x: float) -> void:
	if dead:
		return
	hp -= dmg
	_hurt_timer = 0.15
	_kb_timer = 0.2
	_kb_vel = 180.0 if position.x >= from_x else -180.0
	if hp <= 0:
		_die()

func _die() -> void:
	dead = true
	died.emit(self)
	if main_node != null and main_node.has_method("spawn_death_fx"):
		main_node.call("spawn_death_fx", position)
	queue_free()

func _physics_process(delta: float) -> void:
	if dead:
		return
	_hurt_timer = max(0.0, _hurt_timer - delta)
	_cooldown_timer = max(0.0, _cooldown_timer - delta)
	_hover_time += delta
	if _flying:
		# Hover: sine bob around the spawn height, clamped to ±20 px so
		# the bat never drifts into a floor or ceiling. No gravity, no
		# Y collision — X collision still applies (walls stop it).
		if _hover_base_y == 0.0:
			_hover_base_y = position.y
		vel.y = sin(_hover_time * 2.5) * 24.0
	else:
		vel.y += GRAVITY * delta
		if vel.y > 1200.0:
			vel.y = 1200.0
	_moving = false
	if _kb_timer > 0.0:
		_kb_timer -= delta
		vel.x = _kb_vel
		_moving = true
	elif _attack_timer > 0.0:
		# Attacking: planted. Windup first, strike, then finish.
		vel.x = 0.0
		_attack_timer -= delta
		if not _struck and _attack_timer <= _attack_duration - _strike_at:
			_struck = true
			_strike()
		if _attack_timer <= 0.0:
			_cooldown_timer = COOLDOWN
	elif _cooldown_timer > 0.0:
		vel.x = 0.0
	else:
		_ai(delta)
	var was_ground := on_ground
	_move_axis(delta, true)
	if _flying:
		position.y += vel.y * delta
		position.y = clampf(position.y, _hover_base_y - 20.0, _hover_base_y + 20.0)
		on_ground = false
	else:
		_move_axis(delta, false)
	# Turn at walls: we tried to move horizontally but got stopped.
	# (Flying bats turn the same way; they just never use on_ground.)
	if _moving and (_flying or on_ground) and vel.x == 0.0 and _kb_timer <= 0.0 and _attack_timer <= 0.0:
		_wander_dir = -_wander_dir
		facing = _wander_dir
	_update_animation(delta)

func _ai(delta: float) -> void:
	if player == null or (player.has_method("is_dead") and player.call("is_dead")):
		_idle_wander(delta)
		return
	var to_player: Vector2 = player.position - position
	var dist: float = to_player.length()
	var dy: float = absf(to_player.y)
	if dist <= attack_range and dy < 56.0:
		# Start attack: face the player, plant, windup then strike.
		facing = 1 if to_player.x >= 0.0 else -1
		_attack_duration = _attack_frames.size() / 8.0
		# Mimic attack is only 3 frames (0.375s): strike must land
		# inside the animation, so clamp the strike point to 60% in.
		_strike_at = minf(STRIKE_AT, _attack_duration * 0.6)
		_attack_timer = _attack_duration
		_struck = false
		vel.x = 0.0
		return
	if dist <= aggro_range and dy < 200.0:
		# Chase: move toward the player, turn at ledges.
		var dir := 1 if to_player.x > 0.0 else -1
		facing = dir
		if _ground_ahead(dir):
			vel.x = dir * speed
			_moving = true
		else:
			vel.x = 0.0
		return
	_idle_wander(delta)

func _idle_wander(delta: float) -> void:
	if not _wander:
		vel.x = 0.0
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.5, 3.5)
		_wander_dir = -_wander_dir
	facing = _wander_dir
	if _flying:
		# No ground under a bat by design: it wanders in the air.
		vel.x = _wander_dir * speed * 0.4
		_moving = true
		return
	if on_ground and not _ground_ahead(_wander_dir):
		_wander_dir = -_wander_dir
		facing = _wander_dir
	if on_ground and _ground_ahead(_wander_dir):
		vel.x = _wander_dir * speed * 0.4
		_moving = true
	else:
		vel.x = 0.0

func _ground_ahead(dir: int) -> bool:
	# Is there ground (solid or platform) under the cell just ahead of
	# the feet? Used to turn at ledges instead of walking off.
	if not on_ground:
		return true
	var ahead_x: float = position.x + dir * (half_w + 4.0)
	var feet_y: float = position.y + half_h + 4.0
	var cx := int(floor(ahead_x / TILE))
	var cy := int(floor(feet_y / TILE))
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	var t: int = fg[cy][cx]
	return t != 0

func _strike() -> void:
	if player == null or dead:
		return
	if player.has_method("is_dead") and player.call("is_dead"):
		return
	var to_player: Vector2 = player.position - position
	if absf(to_player.x) <= attack_range + 8.0 and absf(to_player.y) < 64.0:
		if player.has_method("take_hit"):
			player.call("take_hit", damage, position.x)

func _update_animation(delta: float) -> void:
	_anim_time += delta
	var frames: Array
	var fps := 6.0
	if _attack_timer > 0.0:
		frames = _attack_frames
		fps = 8.0
	elif _moving:
		frames = _walk_frames
		fps = 6.0
	else:
		frames = [_idle_frame]
		fps = 1.0
	var idx := 0
	if _attack_timer > 0.0:
		idx = min(int((_attack_duration - _attack_timer) * 8.0), frames.size() - 1)
	else:
		idx = int(_anim_time * fps) % frames.size()
	_sprite.texture = frames[idx]
	_sprite.flip_h = facing < 0
	if _hurt_timer > 0.0:
		_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	else:
		_sprite.modulate = Color(1, 1, 1, 1)

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true
	var t: int = fg[cy][cx]
	return t != 0 and t != 7

func _platform(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	return fg[cy][cx] == 7

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
				if _solid(cx, cy) or (_platform(cx, cy) and prev_feet <= cy * TILE + 1):
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
