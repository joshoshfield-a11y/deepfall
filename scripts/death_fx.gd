# death_fx.gd — smoke-poof death effect (shared by enemies and the player).
# Phase 9b: tries the Effekseer enemy_death_poof effect first (plugin
# EffekseerEmitter2D, .efkefc 1.0 s); if the plugin is absent the old
# staged death_0..3.png flip runs instead. No hard dependency on the
# addon — ClassDB is checked before any Effekseer class is touched, so
# this script still parses and runs with the plugin removed.
# The source frames grow but never dissipate on their own, so the PNG
# path fades modulate alpha to 0 over its ~0.5s lifetime, then frees
# itself. The Effekseer path lives 1.1 s (effect 1.0 s + margin).
extends Node2D

const POOF_EFK := "res://assets/effects-effekseer/enemy_death_poof/enemy_death_poof.efkefc"

var _frames: Array = []
var _time := 0.0
var _life := 0.5
var _sprite: Sprite2D = null
var _emitter: Node = null

func _ready() -> void:
	if ClassDB.class_exists("EffekseerEmitter2D"):
		var res: Resource = load(POOF_EFK)
		if res != null:
			_emitter = ClassDB.instantiate("EffekseerEmitter2D")
			if _emitter != null:
				_emitter.set("effect", res)
				_emitter.set("autoplay", false)
				add_child(_emitter)
				_emitter.call("play")
				_life = 1.1
				return
	# Fallback: staged PNG frames (Phase 5 path, unchanged).
	for i in range(4):
		_frames.append(load("res://assets/effects/death_%d.png" % i))
	_sprite = Sprite2D.new()
	_sprite.texture = _frames[0]
	_sprite.scale = Vector2(0.75, 0.75)
	add_child(_sprite)

func _process(delta: float) -> void:
	_time += delta
	if _emitter != null:
		if _time >= _life:
			queue_free()
		return
	var t: float = clamp(_time / _life, 0.0, 1.0)
	var idx: int = min(int(t * _frames.size()), _frames.size() - 1)
	_sprite.texture = _frames[idx]
	_sprite.modulate = Color(1, 1, 1, 1.0 - t)
	if _time >= _life:
		queue_free()
