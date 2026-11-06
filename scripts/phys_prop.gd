# phys_prop.gd — DEEPFALL Phase 11 physics props.
# crate  : pushable, heavy, breaks in 3 hits, drops wood.
# barrel : pushable, rolls (low friction) and bounces, 2 hits.
# pot    : not pushable, breaks in 1 hit, drops coal / gold / a torch.
# All props have gravity and grid collision (same solid rule as the
# player: t != 0 and t != 7; platforms are landed on from above), fall
# when the block under them is mined, take knockback impulses from hits
# and slam shockwaves, and crush enemies when they land on them fast.
extends Node2D

const TILE := 64
const GRAVITY := 1800.0
const KINDS := {
	"crate": {"hp": 3, "half": Vector2(28, 28), "push": true, "friction": 9.0, "bounce": 0.15, "tex": "crate", "scale": 4.0},
	"barrel": {"hp": 2, "half": Vector2(26, 30), "push": true, "friction": 1.6, "bounce": 0.35, "tex": "barrel", "scale": 4.0},
	"pot": {"hp": 1, "half": Vector2(20, 20), "push": false, "friction": 12.0, "bounce": 0.1, "tex": "pot", "scale": 3.4},
}

var kind := "crate"
var hp := 3
var half := Vector2(28, 28)
var pushable := true
var friction := 8.0
var bounce := 0.2
var vel := Vector2.ZERO
var on_ground := false
var main_node: Node = null
var broken := false
var _sprite: Sprite2D
var _flash := 0.0
var _wobble := 0.0

func setup(k: String, p_main: Node) -> void:
	kind = k
	main_node = p_main
	var d: Dictionary = KINDS[k]
	hp = int(d["hp"]); half = d["half"]; pushable = bool(d["push"])
	friction = float(d["friction"]); bounce = float(d["bounce"])
	z_index = 2
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/hero/props/%s.png" % String(d["tex"]))
	var sc: float = float(d["scale"])
	_sprite.scale = Vector2(sc, sc)
	# texture bottom sits on the collision bottom
	_sprite.position = Vector2(0, half.y - _sprite.texture.get_height() * sc * 0.5)
	add_child(_sprite)

func rect() -> Rect2:
	return Rect2(position - half, half * 2.0)

func _fg() -> Array:
	return main_node.fg

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return true
	var t: int = _fg()[cy][cx]
	return t != 0 and t != 7

func _platform(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= 80 or cy < 0 or cy >= 45:
		return false
	return _fg()[cy][cx] == 7

# Push sideways by dx (player walking into it). Returns the distance
# actually moved after grid collision, so the player is stopped by a
# crate jammed against a wall.
func push(dx: float) -> float:
	if not pushable or not on_ground:
		return 0.0
	var before := position.x
	_move_x(dx)
	if kind == "barrel":
		vel.x = dx / maxf(0.001, get_physics_process_delta_time()) * 0.8
	return position.x - before

func _move_x(dx: float) -> bool:
	position.x += dx
	var top := int(floor((position.y - half.y) / TILE))
	var bot := int(floor((position.y + half.y - 1) / TILE))
	if dx > 0:
		var cx := int(floor((position.x + half.x) / TILE))
		for cy in range(top, bot + 1):
			if _solid(cx, cy):
				position.x = cx * TILE - half.x - 0.01
				return true
	elif dx < 0:
		var cx := int(floor((position.x - half.x) / TILE))
		for cy in range(top, bot + 1):
			if _solid(cx, cy):
				position.x = (cx + 1) * TILE + half.x + 0.01
				return true
	return false

func impulse(v: Vector2) -> void:
	vel += v
	_wobble = 1.0

func take_hit(dmg: int, from_pos: Vector2, kb: Vector2 = Vector2.ZERO) -> void:
	if broken:
		return
	hp -= 1 if dmg > 0 else 0
	_flash = 0.12
	_wobble = 1.0
	var dir := 1.0 if position.x >= from_pos.x else -1.0
	if kb == Vector2.ZERO:
		kb = Vector2(dir * 220.0, -180.0)
	impulse(kb * (1.0 if pushable else 0.3))
	var fx: Node = main_node.get("fx")
	if fx != null:
		fx.burst(position, Color(0.6, 0.4, 0.22), 6, 260.0)
	if hp <= 0:
		_break()

func _break() -> void:
	broken = true
	if main_node != null and main_node.has_method("prop_broken"):
		main_node.call("prop_broken", self)
	queue_free()

func _physics_process(delta: float) -> void:
	if broken or main_node == null:
		return
	_flash = maxf(0.0, _flash - delta)
	_wobble = maxf(0.0, _wobble - delta * 4.0)
	vel.y = minf(1200.0, vel.y + GRAVITY * delta)
	if on_ground:
		vel.x = move_toward(vel.x, 0.0, friction * 120.0 * delta)
	var hit_wall := _move_x(vel.x * delta)
	if hit_wall:
		vel.x = -vel.x * bounce
	var impact := vel.y
	var prev_bot := position.y + half.y
	position.y += vel.y * delta
	var left := int(floor((position.x - half.x + 1) / TILE))
	var right := int(floor((position.x + half.x - 1) / TILE))
	on_ground = false
	if vel.y > 0:
		var cy := int(floor((position.y + half.y) / TILE))
		for cx in range(left, right + 1):
			if _solid(cx, cy) or (_platform(cx, cy) and prev_bot <= cy * TILE + 1):
				position.y = cy * TILE - half.y - 0.01
				vel.y = -impact * bounce if impact > 300.0 else 0.0
				on_ground = absf(vel.y) < 1.0
				if impact > 500.0 and main_node.has_method("prop_landed"):
					main_node.call("prop_landed", self, impact)
				break
		# stack on other props
		if not on_ground and main_node.has_method("prop_support_y"):
			var sy: float = main_node.call("prop_support_y", self, prev_bot)
			if sy > -1e8 and position.y + half.y >= sy:
				position.y = sy - half.y - 0.01
				vel.y = 0.0
				on_ground = true
	elif vel.y < 0:
		var cy := int(floor((position.y - half.y) / TILE))
		for cx in range(left, right + 1):
			if _solid(cx, cy):
				position.y = (cy + 1) * TILE + half.y + 0.01
				vel.y = 0.0
				break
	# visuals: barrels roll, everything wobbles after a hit
	if kind == "barrel" and on_ground:
		_sprite.rotation += vel.x * delta / half.x
	else:
		_sprite.rotation = sin(_wobble * 25.0) * 0.12 * _wobble
	_sprite.modulate = Color(2.5, 2.5, 2.5, 1) if _flash > 0.0 else Color(1, 1, 1, 1)
