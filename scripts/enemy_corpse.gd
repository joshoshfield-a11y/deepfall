# enemy_corpse.gd — DEEPFALL Phase 13 enemy death animation.
# Spawned by enemy.gd when a foe dies: plays that species' own 6-frame
# pixel death (assets/enemies_px/<slug>/death_N.png — flash, species
# motion, dissolve) while the body keeps its knockback momentum, falls
# with gravity and lands on the floor, then fades out and frees itself.
extends Node2D

const TILE := 64
const FPS := 11.0
const GRAVITY := 1700.0

var frames: Array = []
var vel := Vector2.ZERO
var main_node: Node = null
var half_h := 32.0
var _sprite: Sprite2D
var _t := 0.0
var _landed := false

func setup(slug: String, p_main: Node, facing: int, p_vel: Vector2, p_half_h: float) -> void:
	main_node = p_main
	half_h = p_half_h
	vel = Vector2(p_vel.x * 0.6, minf(p_vel.y, -160.0))
	for i in range(6):
		frames.append(load("res://assets/enemies_px/%s/death_%d.png" % [slug, i]))
	_sprite = Sprite2D.new()
	_sprite.texture = frames[0]
	_sprite.scale = Vector2(3, 3)
	_sprite.flip_h = facing < 0
	_sprite.position = Vector2(0, half_h - frames[0].get_height() * 1.5)
	add_child(_sprite)
	z_index = 2

func _solid(cx: int, cy: int) -> bool:
	if main_node == null or cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true
	var t: int = main_node.fg[cy][cx]
	return t != 0

func _physics_process(delta: float) -> void:
	_t += delta
	var idx := mini(frames.size() - 1, int(_t * FPS))
	_sprite.texture = frames[idx]
	if not _landed:
		vel.y = minf(1100.0, vel.y + GRAVITY * delta)
		vel.x = move_toward(vel.x, 0.0, 300.0 * delta)
		var nx := position.x + vel.x * delta
		if _solid(int(floor(nx / TILE)), int(floor(position.y / TILE))):
			vel.x = -vel.x * 0.3
		else:
			position.x = nx
		position.y += vel.y * delta
		var cy := int(floor((position.y + half_h) / TILE))
		if vel.y > 0.0 and _solid(int(floor(position.x / TILE)), cy):
			position.y = cy * TILE - half_h - 0.01
			if vel.y > 300.0:
				vel.y = -vel.y * 0.25
				vel.x *= 0.5
			else:
				_landed = true
	var life := frames.size() / FPS
	if _t > life:
		modulate.a = maxf(0.0, 1.0 - (_t - life) / 0.35)
		if _t > life + 0.35:
			queue_free()
