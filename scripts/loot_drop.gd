# loot_drop.gd — DEEPFALL Phase 13 physical loot.
# Enemy drops pop out of the body with a random arc, bounce off blocks
# (restitution 0.45, ground friction), bob gently once resting, then get
# pulled in by a short-range magnet and are collected on touch. After
# 8 s an uncollected drop homes in on the player so nothing is lost.
extends Node2D

const TILE := 64
const GRAVITY := 1600.0
const HALF := 9.0
const MAGNET := 110.0

var item := "stone"
var amount := 1
var vel := Vector2.ZERO
var main_node: Node = null
var _t := 0.0
var _sprite: Sprite2D
var _resting := false
var collected := false

func setup(p_item: String, n: int, p_main: Node) -> void:
	item = p_item
	amount = n
	main_node = p_main
	vel = Vector2(randf_range(-170.0, 170.0), randf_range(-480.0, -320.0))
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/hero/loot/%s.png" % item)
	_sprite.scale = Vector2(3, 3)
	add_child(_sprite)
	z_index = 4

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true
	var t: int = main_node.fg[cy][cx]
	return t != 0 and t != 7

func _platform(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	return main_node.fg[cy][cx] == 7

func _physics_process(delta: float) -> void:
	if collected or main_node == null:
		return
	_t += delta
	var pl: Node2D = main_node.get("player")
	var to: Vector2 = (pl.position + Vector2(0, -6)) - position
	var dist := to.length()
	if _t > 0.45 and not bool(pl.get("dead")) and (dist < MAGNET or _t > 8.0):
		# magnet: accelerate toward the player, ignore terrain
		vel = vel.lerp(to.normalized() * (520.0 + 900.0 * clampf(1.0 - dist / MAGNET, 0.0, 1.0)), minf(1.0, 9.0 * delta))
		position += vel * delta
		if dist < 26.0:
			collected = true
			main_node.call("collect_loot", self)
			queue_free()
		_sprite.rotation += delta * 10.0
		return
	if not _resting:
		vel.y = minf(1000.0, vel.y + GRAVITY * delta)
		var nx := position.x + vel.x * delta
		if _solid(int(floor((nx + signf(vel.x) * HALF) / TILE)), int(floor(position.y / TILE))):
			vel.x = -vel.x * 0.45
		else:
			position.x = nx
		var prev_bot := position.y + HALF
		position.y += vel.y * delta
		var cx := int(floor(position.x / TILE))
		if vel.y > 0.0:
			var cy := int(floor((position.y + HALF) / TILE))
			if _solid(cx, cy) or (_platform(cx, cy) and prev_bot <= cy * TILE + 1):
				position.y = cy * TILE - HALF - 0.01
				if vel.y > 140.0:
					vel.y = -vel.y * 0.45
					vel.x *= 0.7
					if main_node.get("fx") != null and vel.y < -120.0:
						main_node.fx.sfx("land", 0.2, -16.0)
				else:
					vel = Vector2.ZERO
					_resting = true
		elif vel.y < 0.0:
			var cy2 := int(floor((position.y - HALF) / TILE))
			if _solid(cx, cy2):
				position.y = (cy2 + 1) * TILE + HALF + 0.01
				vel.y = 0.0
		_sprite.rotation += vel.x * delta * 0.05
	else:
		_sprite.rotation = lerpf(_sprite.rotation, 0.0, minf(1.0, 8.0 * delta))
		_sprite.position.y = -absf(sin(_t * 3.0)) * 4.0
		# resting drops still fall if the block under them is mined
		var cyb := int(floor((position.y + HALF + 2.0) / TILE))
		if not _solid(int(floor(position.x / TILE)), cyb) and not _platform(int(floor(position.x / TILE)), cyb):
			_resting = false
	# glint so drops read against the dark
	var k := 0.5 + 0.5 * sin(_t * 6.0)
	_sprite.modulate = Color(1.0 + 0.4 * k, 1.0 + 0.4 * k, 1.0 + 0.3 * k, 1.0)
