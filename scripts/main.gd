# main.gd — DEEPFALL Phase 7: crafting + inventory (on Phase 6 chunk-streamed persistent world).
# Phase 5 and earlier kept: seeded generation (seed 20261101, 80x45),
# polished chamber, 2-hit mining, torches, PointLight2D lighting,
# enemies + combat, twin-stick touch controls.
#
# Phase 6 (this file) follows AUDIT-NEXT-PHASE.md §3.5 item 3, the
# lower-risk path: KEEP full-world generation from the seed (no per-chunk
# regeneration, no topology change, READY line unchanged). Streaming
# applies to rendering / props / lights / enemies in 16x16-cell chunks
# (5 x 3 = 15 chunks); collision stays the fg grid (always resident,
# 3600 ints — the TileMapLayers were never the collision authority).
# Player edits are edit deltas against the generated base and are saved
# to user://deepfall_save.json (single slot): mined cells, 1-hit crack
# state, placed torches, slain enemies (by deterministic spawn id),
# plus player state (pos, HP, ore, torches held, kills, extracted).
# On load the world is regenerated from the seed and deltas re-applied.
# Legacy Phase 4 chunk readout (x//20, 0-3) and the x=20 chunk gate are
# kept; streaming chunks are the separate 16-cell grid shown as Stream.
# No Amber/Void shift (deferred). No fourth class. Three starting classes
# (Phase 8): tech soldier, red soldier, hooded mage — skeleton hero stays a
# separate/unlockable hero and is NOT selectable.
extends Node2D

const SEED := 20261101
const TILE := 64
const TORCH_RADIUS_TILES := 7

const TILE_NAMES := ["dirt", "grass-dirt", "stone", "gold-ore", "amber-ore",
	"wood", "wood-platform", "brick", "mossy-stone", "cracked-stone", "sand", "obsidian", "coal-ore"]
const FG_TO_ATLAS := {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 8: 7, 9: 8, 10: 9, 11: 10, 12: 11, 13: 12}
const WALL_TO_ATLAS := {1: 13, 2: 14}
# edge overlay atlas order: top, bottom, left, right, tl, tr, bl, br
const EDGE_NAMES := ["edge_top", "edge_bottom", "edge_left", "edge_right",
	"corner_tl", "corner_tr", "corner_bl", "corner_br"]

var fg: Array = []
var wall: Array = []
var data: Dictionary = {}
var ore_collected := 0
var last_ore_name := ""
var torches_held := 3
var torches: Dictionary = {}
# Phase 7: inventory + placeable crafted items. inv holds materials AND
# crafted-item counts (glass, lantern, workbench); torches stay in the
# legacy torches_held var. Wood-platform (id 7) is never mined, so it
# never gives wood — only solid wood blocks (id 6) do.
var inv: Dictionary = {"wood": 0, "stone": 0, "dirt": 0, "coal": 0, "gold": 0, "amber": 0, "sand": 0, "glass": 0, "lantern": 0, "workbench": 0}
var lanterns: Dictionary = {}
var workbenches: Dictionary = {}
var _pending_lanterns: Array = []
var _pending_workbenches: Array = []
var extracted := false
var mine_cooldown := 0.0
var mine_damage: Dictionary = {}
var _time := 0.0
var _crystal_cells: Array = []

# Phase 5 combat: enemies, kills, death/respawn.
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const FX_SCRIPT := preload("res://scripts/fx.gd")
const PROP_SCRIPT := preload("res://scripts/phys_prop.gd")
const CORPSE_SCRIPT := preload("res://scripts/enemy_corpse.gd")
const LOOT_SCRIPT := preload("res://scripts/loot_drop.gd")
# Phase 13: persistent props, run stats + summary card
var _props_broken: Dictionary = {}
var _props_moved: Dictionary = {}
var _run_time := 0.0
var _max_depth := 0
var _props_smashed := 0
var _deaths := 0
var _card: CanvasLayer = null
var _card_open := false
var _card_pending := 0.0
var _card_reason := ""
var _cards_enabled := true
var _card_status: Label = null
# Phase 11: game-feel FX node, physics props, aim reticle, tile colours
var fx: Node2D = null
var phys_props: Array = []
var _tile_colors: Dictionary = {}
var _reticle: Line2D = null
var _aim_cell := Vector2i(-1, -1)
var _aim_show := 0.0
const REACH := 3.4 * 64.0
const DEATH_FX_SCRIPT := preload("res://scripts/death_fx.gd")
# Phase 9b: Effekseer effects (EffekseerForGodot4 1.80.5.1, addons/effekseer).
# Both .efkefc files are the EFKE container (CLI -o export, NOT -e/SKFE —
# the plugin parser rejects SKFE). Textures live in each effect's
# Texture/ folder and must travel with the .efkefc. All Effekseer use
# goes through _make_effekseer_emitter(), which returns null when the
# plugin is absent, so the game never hard-crashes on a missing addon.
const ORB_IMPACT_EFK := "res://assets/effects-effekseer/mage_orb_impact/mage_orb_impact.efkefc"
const DEATH_POOF_EFK := "res://assets/effects-effekseer/enemy_death_poof/enemy_death_poof.efkefc"
const ENEMY_SLUGS := ["cave-bat-swarm", "miner-ghoul", "rock-golem",
	"cave-spider", "ore-mimic", "tunnel-worm"]
var enemies: Array = []
var kills := 0
var _enemies_node: Node2D = null
var _respawn_timer := 0.0

@onready var props: Node2D = $Props
@onready var player: Node2D = $Player
@onready var hud: Label = $HUD/Label
@onready var camera: Camera2D = $Player/Camera2D

const CHUNK_W := 20
var _decor_area: Dictionary = {}
var _chamber_gate: Vector2i = Vector2i(-1, -1)

# --- Phase 6: chunk streaming + edit deltas + save/load ---

# Phase 9: true transition / outer-corner tiles (build_phase9_assets.py,
# generated procedurally from the rock/dirt atlas fills — staged art + code,
# no AI images). Each is a single variant; selected by neighbour mask in
# _fill_special(). Straight edges keep the dark overlay (the silhouette
# breaker); transition/corner cells use real tile art instead of the overlay.
const TRANS_NAMES := ["trans_rock_N", "trans_rock_E", "trans_rock_S", "trans_rock_W",
	"trans_dirt_N", "trans_dirt_E", "trans_dirt_S", "trans_dirt_W",
	"corner_rock_TL", "corner_rock_TR", "corner_rock_BL", "corner_rock_BR",
	"corner_dirt_TL", "corner_dirt_TR", "corner_dirt_BL", "corner_dirt_BR"]
# Phase 9: parallax layers (staged cave-silhouettes art, already in the
# tree). Far moves at 0.35x camera, mid at 0.65x — positions are set every
# frame in _update_parallax() from the camera centre.
var _plx_far: Sprite2D = null
var _plx_mid: Sprite2D = null
# Phase 9: second HUD label (hint line, font 14) so line 1 and the hint
# line are measured and fitted independently at 1280x720.
var _hud2: Label = null
# Phase 10: equipped tool ("pickaxe" mines / weak 5-dmg attack, "sword" =
# class melee, cannot mine). Both owned from the start. Saved in the
# v8 save JSON as "tool" (SAVE_VERSION stays 8 — old v8 saves without
# the field load fine and default to pickaxe, see _apply_save).
var tool := "pickaxe"
# Phase 10: WazHack-style message log — one compact line above the
# hotbar showing the LAST event (pickup, craft, slain, warning).
# Replaces scattered transient HUD notes; kept, not auto-cleared.
var _log_label: Label = null
var _log_msg := ""
# Phase 10: Terraria-style hearts (top-left, under the hint line).
# Drawn by HeartBar; the HP number stays in HUD line 1 as well.
var _hearts: Control = null
# Phase 10 perf: torch-light culling timer + last parallax camera pos
# (skip _update_parallax when the camera has not moved).
var _light_cull_timer := 0.0
var _last_parallax_cam := Vector2(-99999, -99999)
# Phase 9: mage orb trail dots + impact FX (frost-burst frames).
var _orb_fx: Array = []
var _orb_impact_frames: Array = []
const STREAM := 16
const STREAM_COLS := 5
const STREAM_ROWS := 3
const STREAM_TOTAL := 15
const SAVE_PATH := "user://deepfall_save.json"
const SAVE_VERSION := 8
var _saved_class := "tech"
# Phase 8: class select. _selecting is true until a class is picked on a
# new run; the player physics is frozen and world clicks are ignored
# while the select screen is up. Loading a save skips the select.
var _selecting := false
var _class_panel: PanelContainer = null
var _class_cards: Array = []
var _class_index := 0
var _fg_layers: Array = []
var _wall_layers: Array = []
var _edge_layers: Array = []
var _damage_layers: Array = []
var _prop_chunks: Array = []
var _main_tileset: TileSet = null
var _edge_tileset: TileSet = null
var _damage_tileset: TileSet = null
var _tileset_built := false
var _chunks_created := false
var _active_chunks: Dictionary = {}
var _last_stream_chunk := Vector2i(-1, -1)
var _loaded_chunk_count := 0
var _world_ready := false
var _mined_cells: Dictionary = {}
var _slain_ids: Dictionary = {}
var _enemy_spawns: Array = []
var _pending_torches: Array = []
var _saved_player_pos := Vector2.ZERO
var _saved_hp := 100
var _has_save := false
var _save_note := ""
var _save_time := -100.0
var _extract_saved := false

# Phase 10: hearts bar — one heart per 10 max HP, full / partial /
# empty by current HP. Drawn with circles + triangle (no font glyph,
# so no missing-♥ risk in the default font).
class HeartBar extends Control:
	var main_node: Node = null
	func _draw() -> void:
		if main_node == null:
			return
		var pl: Node2D = main_node.get("player")
		if pl == null:
			return
		var hp: int = int(pl.get("hp"))
		var max_hp: int = int(pl.get("max_hp"))
		var n: int = int(ceil(float(max_hp) / 10.0))
		for i in range(n):
			var cx := 10.0 + i * 22.0
			var cy := 11.0
			var remain: float = clampf(float(hp - i * 10) / 10.0, 0.0, 1.0)
			_draw_heart(Vector2(cx, cy), 1.0, Color(0.25, 0.07, 0.09, 1.0))
			if remain > 0.0:
				var s := 0.4 + 0.6 * remain
				_draw_heart(Vector2(cx, cy), s, Color(0.9, 0.12, 0.18, 1.0))
	func _draw_heart(c: Vector2, s: float, col: Color) -> void:
		draw_circle(c + Vector2(-3.2, -2.0) * s, 4.0 * s, col)
		draw_circle(c + Vector2(3.2, -2.0) * s, 4.0 * s, col)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-7.0, -1.0) * s, c + Vector2(7.0, -1.0) * s,
			c + Vector2(0.0, 7.5) * s]), col)

func log_event(msg: String) -> void:
	# Phase 10: the WazHack-style log line. Kept until replaced.
	_log_msg = msg
	if _log_label != null:
		_log_label.text = msg
	print("DEEPFALL_LOG %s" % msg)

func set_tool(t: String) -> void:
	# Phase 10: Q / 1 / 2 / TOOL button / hotbar slot all land here.
	tool = "sword" if t == "sword" else "pickaxe"
	if player != null and player.has_method("set_tool"):
		player.call("set_tool", tool)
	var tu: Node = get_node_or_null("TouchUI")
	if tu != null and tu.has_method("_refresh_hotbar"):
		tu.call("_refresh_hotbar")
	log_event("Tool: %s" % ("Sword" if tool == "sword" else "Pickaxe"))

func cycle_tool() -> void:
	set_tool("sword" if tool == "pickaxe" else "pickaxe")

func _ready() -> void:
	if "--new-run" in OS.get_cmdline_user_args():
		DirAccess.remove_absolute(SAVE_PATH)
		print("DEEPFALL_NEW_RUN save cleared before launch")
	_rebuild_world(true)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 80 * TILE
	camera.limit_bottom = 45 * TILE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	_render_background()
	var exit_cell: Vector2i = data["exit"]
	var beacon := ColorRect.new()
	beacon.size = Vector2(TILE, TILE * 2)
	beacon.position = Vector2(exit_cell.x * TILE, (exit_cell.y - 1) * TILE)
	beacon.color = Color(1.0, 0.75, 0.2, 0.9)
	beacon.name = "ExitBeacon"
	add_child(beacon)
	var beacon_light := PointLight2D.new()
	beacon_light.color = Color(1.0, 0.77, 0.42)
	beacon_light.energy = 1.0
	beacon_light.texture = _light_gradient_texture()
	beacon_light.texture_scale = 320.0 / 448.0
	beacon_light.position = Vector2((exit_cell.x + 0.5) * TILE, (exit_cell.y - 0.5) * TILE)
	add_child(beacon_light)
	_build_craft_panel()
	_build_class_select()
	# Phase 9: second HUD label for the hint line (font 14, own rect).
	var hud2 := Label.new()
	hud2.name = "HintLabel"
	hud2.offset_left = 16.0
	hud2.offset_top = 38.0
	hud2.offset_right = 1264.0
	hud2.offset_bottom = 62.0
	hud2.add_theme_font_size_override("font_size", 14)
	$HUD.add_child(hud2)
	_hud2 = hud2
	# Phase 10: WazHack-style message log line (one compact line above
	# the hotbar, x 380-900 y 548-572, centred, font 14) and the
	# Terraria-style hearts (top-left, under the hint line, y 66-90).
	var logl := Label.new()
	logl.name = "LogLabel"
	logl.offset_left = 380.0
	logl.offset_top = 548.0
	logl.offset_right = 900.0
	logl.offset_bottom = 572.0
	logl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logl.add_theme_font_size_override("font_size", 14)
	logl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75, 1.0))
	$HUD.add_child(logl)
	_log_label = logl
	_hearts = HeartBar.new()
	_hearts.name = "Hearts"
	_hearts.offset_left = 16.0
	_hearts.offset_top = 16.0
	_hearts.offset_right = 300.0
	_hearts.offset_bottom = 40.0
	# Phase 11 HUD: compact stats under the hearts; the long desktop
	# key-hint line only shows on devices without a touchscreen.
	hud.offset_top = 44.0
	hud.offset_bottom = 66.0
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 5)
	_hud2.offset_top = 690.0
	_hud2.offset_bottom = 712.0
	_hud2.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_hud2.visible = not DisplayServer.is_touchscreen_available()
	logl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logl.offset_left = -300.0
	logl.offset_right = 300.0
	logl.offset_top = 84.0
	logl.offset_bottom = 108.0
	logl.add_theme_font_size_override("font_size", 16)
	logl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	logl.add_theme_constant_override("outline_size", 5)
	for fr in ["Foreground/FrameBL", "Foreground/FrameBR"]:
		var frn: Node = get_node_or_null(fr)
		if frn != null:
			frn.queue_free()
	_reticle = Line2D.new()
	_reticle.width = 3.0
	_reticle.closed = true
	_reticle.default_color = Color(1.0, 0.85, 0.45, 0.9)
	_reticle.points = PackedVector2Array([Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)])
	_reticle.z_index = 4
	_reticle.visible = false
	add_child(_reticle)
	_hearts.main_node = self
	$HUD.add_child(_hearts)
	log_event("Tool: Pickaxe")
	print("DEEPFALL_PHASE1_READY seed=%d rooms=%d/%d ore_veins=%d spawn=%s exit=%s connected=%s" % [
		SEED, data["rooms_reached"], data["rooms_total"], data["ore"],
		str(data["spawn"]), str(exit_cell), str(data["connected"])])
	_world_ready = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Phase 8 class-select flow: a save skips the select (saved class
	# was applied in _rebuild_world); a new run shows it. Headless
	# modes pick deterministically instead of waiting on a key press:
	# --selftest / --selftest-load honour --class=<id> (default tech),
	# plain --screenshot auto-picks tech, --screenshot-class captures
	# the select screen itself.
	if "--selftest" in args or "--selftest-load" in args:
		for a in args:
			if a.begins_with("--class="):
				player.set_class(a.trim_prefix("--class="))
	elif _has_save:
		pass  # saved class already applied; no re-pick
	elif ("--screenshot" in args or "--screenshot-pair" in args) and "--screenshot-class" not in args:
		player.set_class("tech")
	else:
		_show_class_select(true)
	for a0 in args:
		if a0 == "--selftest" or a0 == "--selftest-load" or a0.begins_with("--screenshot"):
			_cards_enabled = false
	if "--selftest-p11" in args:
		_show_class_select(false)
		for a in args:
			if a.begins_with("--class="):
				player.set_class(a.trim_prefix("--class="))
		await _run_selftest_p11()
		get_tree().quit()
		return
	if "--screenshot-pair" in OS.get_cmdline_user_args():
		await _run_screenshot_pair()
		get_tree().quit()
	elif "--screenshot" in OS.get_cmdline_user_args():
		if "--screenshot-craft" in OS.get_cmdline_user_args():
			_show_craft_panel(true)
		await get_tree().create_timer(1.0).timeout
		if "--screenshot-orb" in OS.get_cmdline_user_args():
			# Phase 9b: fire a real orb impact in front of the player and
			# capture it early (~0.1 s in, while the CoreFlash is at peak
			# and the shards are mid-flight of the 0.67 s effect).
			_spawn_orb_impact(player.position + Vector2(96, -32))
			await get_tree().create_timer(0.1).timeout
			var orb_img := get_viewport().get_texture().get_image()
			orb_img.save_png("res://screenshot_orb.png")
			print("DEEPFALL_SCREENSHOT_ORB_SAVED")
			get_tree().quit()
			return
		if "--screenshot-p10-mine" in OS.get_cmdline_user_args():
			# Phase 10: pickaxe mining shot — mine the solid cell
			# directly in front of the player twice (crack + clear)
			# so the frame shows the mining swing + the log line.
			set_tool("pickaxe")
			var mcell := Vector2i(-1, -1)
			for d in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
					Vector2i(-1, 0), Vector2i(1, -1)]:
				var c: Vector2i = player.cell() + d
				if fg[c.y][c.x] != 0 and fg[c.y][c.x] != 7:
					mcell = c
					break
			if mcell.x >= 0:
				_face_cell(mcell)
				_mine_at(mcell)
				_mine_at(mcell)
			await get_tree().create_timer(0.2).timeout
			var mine_img := get_viewport().get_texture().get_image()
			mine_img.save_png("res://screenshot_p10_mine.png")
			print("DEEPFALL_SCREENSHOT_P10_MINE_SAVED")
			get_tree().quit()
			return
		if "--screenshot-p10-sword" in OS.get_cmdline_user_args():
			# Phase 10: sword swing shot — equip the sword and swing
			# toward a ghoul placed in front, captured mid-arc
			# (~0.15 s in, slash polygon at peak sweep).
			set_tool("sword")
			var scell: Vector2i = player.cell() + Vector2i(1, 0)
			_spawn_one("miner-ghoul", scell)
			player.facing = 1
			player.attack_cooldown = 0.0
			player.try_attack()
			await get_tree().create_timer(0.15).timeout
			var sword_img := get_viewport().get_texture().get_image()
			sword_img.save_png("res://screenshot_p10_sword.png")
			print("DEEPFALL_SCREENSHOT_P10_SWORD_SAVED")
			get_tree().quit()
			return
		if "--screenshot-p10-walk" in OS.get_cmdline_user_args():
			# Phase 10: mid-walk shot — walk right for ~0.35 s so the
			# walkcycle frame is live, proving the rescaled walk
			# reads at idle height in-game. Kept short so the player
			# stays on the spawn platform (0.6 s walked off the edge
			# and caught the landing squash instead).
			player.touch_move = 1.0
			await get_tree().create_timer(0.35).timeout
			player.touch_move = 0.0
			var walk_img := get_viewport().get_texture().get_image()
			walk_img.save_png("res://screenshot_p10_walk.png")
			print("DEEPFALL_SCREENSHOT_P10_WALK_SAVED")
			get_tree().quit()
			return
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://screenshot.png")
		print("DEEPFALL_SCREENSHOT_SAVED")
		get_tree().quit()
	elif "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
	elif "--selftest-load" in OS.get_cmdline_user_args():
		_run_selftest_load()

# --- Phase 6: world (re)build — generate from seed, apply deltas, render ---

func _rebuild_world(use_save: bool) -> void:
	_clear_dynamic()
	data = DeepfallMapGen.generate(SEED)
	fg = data["fg"]; wall = data["wall"]
	_build_polished_chamber()
	ore_collected = 0
	last_ore_name = ""
	for k in inv.keys():
		inv[k] = 0
	torches_held = 3
	kills = 0
	extracted = false
	mine_damage.clear()
	_mined_cells.clear()
	_slain_ids.clear()
	_props_broken.clear()
	_props_moved.clear()
	_run_time = 0.0
	_max_depth = 0
	_props_smashed = 0
	_deaths = 0
	_enemy_spawns.clear()
	_pending_torches.clear()
	_pending_lanterns.clear()
	_pending_workbenches.clear()
	_has_save = false
	_extract_saved = false
	_saved_hp = 100
	if use_save:
		var d := _load_save_dict()
		if not d.is_empty():
			_apply_save(d)
	if not _tileset_built:
		_build_tileset()
		_create_chunk_layers()
		_tileset_built = true
	_render_layers()
	_render_edges()
	_restore_damage_overlays()
	_render_props()
	_render_chamber()
	_restore_pending_torches()
	_restore_pending_lanterns()
	_restore_pending_workbenches()
	_build_enemy_spawn_table()
	if _enemies_node == null:
		_enemies_node = Node2D.new()
		_enemies_node.name = "Enemies"
		_enemies_node.z_index = 2
		add_child(_enemies_node)
		move_child(_enemies_node, player.get_index())
	_last_stream_chunk = Vector2i(-1, -1)
	var spawn: Vector2i = data["spawn"]
	if _has_save:
		player.set_class(_saved_class)
		player.set_tool(tool)
		player.respawn_at(_saved_player_pos)
		player.hp = _saved_hp
	else:
		tool = "pickaxe"
		player.set_class("tech")
		player.set_tool("pickaxe")
		player.position = Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
		player.hp = player.max_hp
	player.fg = fg
	player.main_node = self
	_ensure_fx()
	_spawn_phys_props()
	# Player must be positioned BEFORE chunk activation, or the first
	# active set is computed from the (0, 0) default position.
	_apply_chunk_visibility(true)

func _clear_dynamic() -> void:
	if _chunks_created:
		for l in _fg_layers:
			l.clear()
		for l in _wall_layers:
			l.clear()
		for l in _edge_layers:
			l.clear()
		for l in _damage_layers:
			l.clear()
		for c in _prop_chunks:
			for child in c.get_children():
				child.free()
	for key in torches.keys():
		var tn: Node = torches[key]
		tn.free()
	torches.clear()
	for key in lanterns.keys():
		var ln: Node = lanterns[key]
		ln.free()
	lanterns.clear()
	for key in workbenches.keys():
		var wn: Node = workbenches[key]
		wn.free()
	workbenches.clear()
	if _enemies_node != null:
		for e in enemies:
			if is_instance_valid(e):
				e.free()
	enemies.clear()
	for o in _orbs:
		if is_instance_valid(o["node"]):
			(o["node"] as Node).free()
	_orbs.clear()
	for fx in _orb_fx:
		if is_instance_valid(fx["node"]):
			(fx["node"] as Node).free()
	_orb_fx.clear()
	# Phase 9b: also free any live Effekseer impact emitters (orb impacts
	# and death poofs are emitter children, not _orb_fx entries).
	for c in get_children():
		if c.get_class() == "EffekseerEmitter2D":
			c.free()
	_decor_area.clear()
	_crystal_cells.clear()
	_chamber_gate = Vector2i(-1, -1)
	_active_chunks.clear()

# --- Phase 6: save / load / new run ---

func _cell_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _key_to_cell(s: String) -> Vector2i:
	var p := s.split(",")
	if p.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(p[0]), int(p[1]))

func _load_save_dict() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}

func _apply_save(d: Dictionary) -> void:
	if int(d.get("version", 0)) != SAVE_VERSION or int(d.get("seed", 0)) != SEED:
		print("DEEPFALL_SAVE_IGNORED version/seed mismatch")
		return
	ore_collected = int(d.get("ore", 0))
	torches_held = int(d.get("torches_held", 3))
	kills = int(d.get("kills", 0))
	extracted = bool(d.get("extracted", false))
	for key in d.get("mined", []):
		var c := _key_to_cell(String(key))
		if c.x >= 0 and c.x < 80 and c.y >= 0 and c.y < 45:
			fg[c.y][c.x] = 0
			_mined_cells[c] = true
	for key in d.get("cracked", []):
		var c2 := _key_to_cell(String(key))
		if c2.x >= 0 and c2.x < 80 and c2.y >= 0 and c2.y < 45 and fg[c2.y][c2.x] != 0:
			mine_damage[c2] = 1
	_slain_ids.clear()
	for sid in d.get("slain", []):
		_slain_ids[int(sid)] = true
	# Phase 13: smashed props stay smashed, pushed props stay pushed
	_props_broken.clear()
	for pid in d.get("props_broken", []):
		_props_broken[int(pid)] = true
	_props_moved.clear()
	var pm: Dictionary = d.get("props_moved", {})
	for k in pm.keys():
		_props_moved[int(k)] = Vector2(float(pm[k][0]), float(pm[k][1]))
	var st: Dictionary = d.get("stats", {})
	_run_time = float(st.get("time", 0.0))
	_max_depth = int(st.get("max_depth", 0))
	_props_smashed = int(st.get("props_smashed", 0))
	_deaths = int(st.get("deaths", 0))
	var invd: Dictionary = d.get("inventory", {})
	for k in inv.keys():
		inv[k] = int(invd.get(k, 0))
	_pending_lanterns.clear()
	var ld: Dictionary = d.get("lanterns", {})
	for key in ld.keys():
		_pending_lanterns.append({"cell": _key_to_cell(String(key)),
			"support": _key_to_cell(String(ld[key]))})
	_pending_workbenches.clear()
	var wd: Dictionary = d.get("workbenches", {})
	for key in wd.keys():
		_pending_workbenches.append({"cell": _key_to_cell(String(key)),
			"floor": _key_to_cell(String(wd[key]))})
	_pending_torches.clear()
	var td: Dictionary = d.get("torches", {})
	for key in td.keys():
		_pending_torches.append({"cell": _key_to_cell(String(key)),
			"support": _key_to_cell(String(td[key]))})
	var pd: Dictionary = d.get("player", {})
	_saved_player_pos = Vector2(float(pd.get("x", 0.0)), float(pd.get("y", 0.0)))
	_saved_hp = int(pd.get("hp", 100))
	_saved_class = String(d.get("class", "tech"))
	if _saved_class not in ["tech", "red", "mage"]:
		_saved_class = "tech"
	# Phase 10: equipped tool, SAVE_VERSION stays 8. Old v8 saves have
	# no "tool" field — d.get defaults to "pickaxe", so they load
	# exactly as before. Invalid values fall back to pickaxe too.
	tool = String(d.get("tool", "pickaxe"))
	if tool not in ["pickaxe", "sword"]:
		tool = "pickaxe"
	_has_save = true
	print("DEEPFALL_SAVE_LOADED mined=%d cracked=%d torches=%d slain=%d ore=%d pos=%s hp=%d class=%s inv=%s lanterns=%d workbenches=%d" % [
		_mined_cells.size(), mine_damage.size(), _pending_torches.size(),
		_slain_ids.size(), ore_collected, str(_saved_player_pos), _saved_hp,
		_saved_class,
		str(inv), _pending_lanterns.size(), _pending_workbenches.size()])

func save_game(reason: String) -> void:
	if not _world_ready:
		return
	var mined_keys: Array = []
	for c in _mined_cells.keys():
		mined_keys.append(_cell_key(c))
	var cracked_keys: Array = []
	for c in mine_damage.keys():
		cracked_keys.append(_cell_key(c))
	var torch_dict := {}
	for key in torches.keys():
		torch_dict[_cell_key(key)] = _cell_key(torches[key].get_meta("support"))
	var lantern_dict := {}
	for key in lanterns.keys():
		lantern_dict[_cell_key(key)] = _cell_key(lanterns[key].get_meta("support"))
	var bench_dict := {}
	for key in workbenches.keys():
		bench_dict[_cell_key(key)] = _cell_key(workbenches[key].get_meta("floor"))
	var slain_list: Array = []
	for sid in _slain_ids.keys():
		slain_list.append(int(sid))
	var broken_list: Array = []
	for pid in _props_broken.keys():
		broken_list.append(int(pid))
	for pr in phys_props:
		if is_instance_valid(pr) and pr.has_meta("prop_id") and (pr.position - (pr.get_meta("spawn_pos") as Vector2)).length() > 4.0:
			_props_moved[int(pr.get_meta("prop_id"))] = pr.position
	var moved_dict := {}
	for pid in _props_moved.keys():
		moved_dict[str(pid)] = [(_props_moved[pid] as Vector2).x, (_props_moved[pid] as Vector2).y]
	var d := {"version": SAVE_VERSION, "seed": SEED,
		"player": {"x": player.position.x, "y": player.position.y, "hp": player.hp},
		"class": player.class_id,
		"tool": tool,
		"ore": ore_collected, "torches_held": torches_held, "kills": kills,
		"extracted": extracted, "mined": mined_keys, "cracked": cracked_keys,
		"torches": torch_dict, "slain": slain_list,
		"inventory": inv.duplicate(), "lanterns": lantern_dict, "workbenches": bench_dict,
		"props_broken": broken_list, "props_moved": moved_dict,
		"stats": {"time": _run_time, "max_depth": _max_depth, "props_smashed": _props_smashed, "deaths": _deaths}}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		print("DEEPFALL_SAVE_FAILED reason=%s" % reason)
		return
	f.store_string(JSON.stringify(d))
	f.close()
	_save_note = "Saved (%s)" % reason
	_save_time = _time
	print("DEEPFALL_SAVE_SAVED reason=%s mined=%d cracked=%d torches=%d slain=%d ore=%d inv=%s lanterns=%d workbenches=%d" % [
		reason, mined_keys.size(), cracked_keys.size(), torch_dict.size(),
		slain_list.size(), ore_collected, str(inv), lantern_dict.size(), bench_dict.size()])

func new_run() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	print("DEEPFALL_NEW_RUN save cleared, regenerating clean")
	_rebuild_world(false)
	_show_class_select(true)
	print("DEEPFALL_NEW_RUN done")

# --- Phase 6: chunk helpers ---

func _stream_chunk_of(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x / STREAM, 0, STREAM_COLS - 1),
		clampi(c.y / STREAM, 0, STREAM_ROWS - 1))

func _chunk_id_for_cell(c: Vector2i) -> int:
	var sc := _stream_chunk_of(c)
	return sc.y * STREAM_COLS + sc.x

func _is_chunk_active(chunk_id: int) -> bool:
	return bool(_active_chunks.get(chunk_id, false))

func _fg_layer_for(c: Vector2i) -> TileMapLayer:
	return _fg_layers[_chunk_id_for_cell(c)]

func _wall_layer_for(c: Vector2i) -> TileMapLayer:
	return _wall_layers[_chunk_id_for_cell(c)]

func _edge_layer_for(c: Vector2i) -> TileMapLayer:
	return _edge_layers[_chunk_id_for_cell(c)]

func _damage_layer_for(c: Vector2i) -> TileMapLayer:
	return _damage_layers[_chunk_id_for_cell(c)]

func _prop_node_for_cell(c: Vector2i) -> Node2D:
	return _prop_chunks[_chunk_id_for_cell(c)]

func _add_prop(node: Node, cell: Vector2i) -> void:
	_prop_node_for_cell(cell).add_child(node)

func _create_chunk_layers() -> void:
	for i in range(STREAM_TOTAL):
		var fgl := TileMapLayer.new()
		fgl.tile_set = _main_tileset
		fgl.z_index = 0
		fgl.name = "FgChunk%d" % i
		add_child(fgl)
		_fg_layers.append(fgl)
		var wl := TileMapLayer.new()
		wl.tile_set = _main_tileset
		wl.z_index = -1
		wl.name = "WallChunk%d" % i
		add_child(wl)
		_wall_layers.append(wl)
		var el := TileMapLayer.new()
		el.tile_set = _edge_tileset
		el.z_index = 1
		el.name = "EdgeChunk%d" % i
		add_child(el)
		_edge_layers.append(el)
		var dl := TileMapLayer.new()
		dl.tile_set = _damage_tileset
		dl.z_index = 2
		dl.name = "DamageChunk%d" % i
		add_child(dl)
		_damage_layers.append(dl)
		var pc := Node2D.new()
		pc.name = "PropChunk%d" % i
		pc.z_index = 1
		props.add_child(pc)
		_prop_chunks.append(pc)
	_chunks_created = true

func _apply_chunk_visibility(force := false) -> void:
	var sc := _stream_chunk_of(player.cell())
	if not force and sc == _last_stream_chunk:
		return
	_last_stream_chunk = sc
	_active_chunks.clear()
	var loaded := 0
	for cy in range(STREAM_ROWS):
		for cx in range(STREAM_COLS):
			var chunk_id := cy * STREAM_COLS + cx
			var active := absi(cx - sc.x) <= 1 and absi(cy - sc.y) <= 1
			_active_chunks[chunk_id] = active
			_fg_layers[chunk_id].visible = active
			_wall_layers[chunk_id].visible = active
			_edge_layers[chunk_id].visible = active
			_damage_layers[chunk_id].visible = active
			_prop_chunks[chunk_id].visible = active
			# Phase 10 perf: hidden chunks cost no draw calls, but
			# their CPUParticles2D embers kept SIMULATING while
			# hidden. Pause emission in inactive chunks (and resume
			# on re-entry) so unloaded chunks cost nothing at all.
			# Props themselves are freed on world rebuild
			# (_clear_dynamic), not per chunk — re-rendering them on
			# every chunk swap would cost more than hiding them.
			for ch in _prop_chunks[chunk_id].get_children():
				if ch is CPUParticles2D:
					(ch as CPUParticles2D).emitting = active
			if active:
				loaded += 1
	_loaded_chunk_count = loaded
	_refresh_enemies_for_chunks()
	print("DEEPFALL_CHUNK stream=%s loaded=%d/15" % [str(sc), loaded])

func _restore_damage_overlays() -> void:
	for cell in mine_damage.keys():
		_damage_layer_for(cell).set_cell(cell, 0, Vector2i(0, 0))

func _restore_pending_torches() -> void:
	for t in _pending_torches:
		_place_torch_at(t["cell"], t["support"])
	_pending_torches.clear()

func _restore_pending_lanterns() -> void:
	for t in _pending_lanterns:
		_place_lantern_at(t["cell"], t["support"])
	_pending_lanterns.clear()

func _restore_pending_workbenches() -> void:
	for t in _pending_workbenches:
		_place_workbench_at(t["cell"], t["floor"])
	_pending_workbenches.clear()

# --- Phase 5: enemies (Phase 6: spawn table + chunk-gated live set) ---

func _build_enemy_spawn_table() -> void:
	# Deterministic from SEED + 5000: same seed = same spawn table, so
	# a chunk reload or a player-death respawn re-derives the same set.
	# The table is the source of truth; _refresh_enemies_for_chunks()
	# decides which of them are live right now. Slain ids stay dead.
	_enemy_spawns.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5000
	var spawn: Vector2i = data["spawn"]
	var exit_cell: Vector2i = data["exit"]
	var rooms: Array = data["rooms"]
	# 5 of rooms 1..13, 2 enemies each = 10 total.
	var room_idx: Array = []
	for i in range(1, rooms.size()):
		room_idx.append(i)
	# Fisher-Yates with the seeded rng (not Array.shuffle, which uses
	# the global RNG) so the chosen rooms are deterministic per seed.
	for i in range(room_idx.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = room_idx[i]
		room_idx[i] = room_idx[j]
		room_idx[j] = tmp
	var chosen: Array = room_idx.slice(0, 5)
	var next_id := 0
	for ri in chosen:
		var r: Array = rooms[ri]
		for k in range(2):
			var slug: String = ENEMY_SLUGS[rng.randi_range(0, ENEMY_SLUGS.size() - 1)]
			var cell := _pick_enemy_cell(r, rng, spawn, exit_cell)
			if cell == Vector2i(-1, -1):
				continue
			_enemy_spawns.append({"slug": slug, "cell": cell, "id": next_id})
			next_id += 1
	print("DEEPFALL_ENEMY_SPAWNS total=%d" % _enemy_spawns.size())

func _pick_enemy_cell(r: Array, rng: RandomNumberGenerator, spawn: Vector2i, exit_cell: Vector2i) -> Vector2i:
	var rx: int = r[0]; var ry: int = r[1]; var rw: int = r[2]; var rh: int = r[3]
	var cands: Array = []
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			var c := Vector2i(x, y)
			if fg[y][x] != 0:
				continue  # must be an air cell
			if y + 1 >= 45:
				continue
			var below: int = fg[y + 1][x]
			if below == 0:
				continue  # solid or platform below (7 = platform, ok)
			if c.distance_to(spawn) < 3.0 or c.distance_to(exit_cell) < 3.0:
				continue
			if _chamber_gate != Vector2i(-1, -1) and c.distance_to(_chamber_gate) < 3.0:
				continue
			if torches.has(c) or _crystal_cells.has(c):
				continue
			cands.append(c)
	if cands.is_empty():
		return Vector2i(-1, -1)
	return cands[rng.randi_range(0, cands.size() - 1)]

func _refresh_enemies_for_chunks() -> void:
	# Live set follows the active chunks. An enemy whose current cell
	# is in an unloaded chunk is freed (not slain): if it was alive it
	# respawns at its deterministic spawn cell, full HP, when its
	# chunk loads again. Slain spawn ids never respawn.
	if _enemy_spawns.is_empty():
		return
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			continue
		if not _is_chunk_active(_chunk_id_for_cell(e.cell())):
			enemies.erase(e)
			e.queue_free()
	for s in _enemy_spawns:
		var sid: int = s["id"]
		if _slain_ids.has(sid):
			continue
		var cell: Vector2i = s["cell"]
		if not _is_chunk_active(_chunk_id_for_cell(cell)):
			continue
		var live := false
		for e in enemies:
			if is_instance_valid(e) and e.spawn_id == sid:
				live = true
				break
		if not live:
			_spawn_one(s["slug"], cell, sid)

func _foes_remaining() -> int:
	return _enemy_spawns.size() - _slain_ids.size()

func _spawn_one(slug: String, cell: Vector2i, spawn_id := -1) -> void:
	var e: Node2D = ENEMY_SCRIPT.new()
	e.setup(slug, fg, player, self)
	e.spawn_id = spawn_id
	# Feet on the ground-cell top: ground top is (cell.y + 1) * TILE.
	e.position = Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE - e.half_h)
	e.died.connect(_on_enemy_died)
	_enemies_node.add_child(e)
	enemies.append(e)

func _on_enemy_died(enemy: Node2D) -> void:
	enemies.erase(enemy)
	kills += 1
	_grant_enemy_drop(enemy)
	if enemy.spawn_id >= 0:
		_slain_ids[enemy.spawn_id] = true
	print("DEEPFALL_ENEMY_SLAIN slug=%s remaining=%d" % [enemy.slug, _foes_remaining()])
	log_event("Slain %s" % enemy.slug)
	save_game("kill")

func _face_cell(cell: Vector2i) -> void:
	# Phase 10: turn the player toward a cell (used for sword swings
	# via the right stick so the slash goes where the stick points).
	var dx: int = cell.x - player.cell().x
	if dx != 0:
		player.facing = 1 if dx > 0 else -1

func player_attack_hit(from_pos: Vector2, facing: int, dmg := -1, aim := Vector2.ZERO) -> void:
	# Phase 10: dmg is set by the player's equipped tool (pickaxe 5,
	# sword = class melee). Default -1 = class melee, which keeps the
	# Phase 5 self-test call (2 args) working unchanged.
	if dmg < 0:
		dmg = player.melee_dmg
	# Player melee strike: all enemies within 90px in front, 64px
	# vertical tolerance, the passed damage (tool-based) with knockback
	# away from the player. (Phase 8: was hardcoded 15 for the tech soldier.)
	# Phase 11: the swing follows the aim direction (360°). Anything in
	# a ~110° cone within 110 px is hit; knockback goes along the swing.
	if aim == Vector2.ZERO:
		aim = Vector2(facing, 0)
	aim = aim.normalized()
	var origin := from_pos + Vector2(0, -8)
	var any_hit := false
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			continue
		var d: Vector2 = e.position - origin
		var in_cone: bool = d.length() <= 110.0 + e.half_w and (d.length() < 24.0 or d.normalized().dot(aim) > 0.35)
		if in_cone:
			var kb := (aim * 0.7 + d.normalized() * 0.3).normalized() * 340.0 + Vector2(0, -160)
			e.take_hit(dmg, from_pos.x, kb)
			any_hit = true
			if fx != null:
				fx.burst(e.position, Color(1.0, 0.85, 0.5), 10, 320.0, 600.0, 5.0)
				fx.float_text(e.position + Vector2(0, -50), str(dmg), Color(1, 0.95, 0.6), dmg >= 15)
	for pr in phys_props.duplicate():
		if not is_instance_valid(pr) or pr.broken:
			continue
		var dp: Vector2 = pr.position - origin
		if dp.length() <= 100.0 + pr.half.x and (dp.length() < 24.0 or dp.normalized().dot(aim) > 0.35):
			pr.take_hit(dmg, from_pos, aim * 300.0 + Vector2(0, -140))
			any_hit = true
	if any_hit and fx != null:
		fx.shake(6.0)
		fx.hitstop(0.045)
		fx.sfx("hit", 0.1)
		fx.rumble(35)

# --- Phase 8: hooded mage orb bolt (ranged attack, no new damage type) ---
const ORB_SPEED := 500.0
const ORB_RANGE := 320.0
const ORB_DMG := 12
var _orbs: Array = []

func spawn_orb(from_pos: Vector2, facing: int, aim := Vector2.ZERO) -> void:
	if aim == Vector2.ZERO:
		aim = Vector2(facing, 0)
	aim = aim.normalized()
	var orb := Node2D.new()
	orb.position = from_pos + Vector2(0, -10.0) + aim * 24.0
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(8):
		var a := TAU * k / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 10.0)
	dot.polygon = pts
	dot.color = Color(0.5, 0.89, 0.94, 1.0)
	orb.add_child(dot)
	var halo := Polygon2D.new()
	var pts2 := PackedVector2Array()
	for k in range(8):
		var a := TAU * k / 8.0
		pts2.append(Vector2(cos(a), sin(a)) * 16.0)
	halo.polygon = pts2
	halo.color = Color(0.5, 0.89, 0.94, 0.25)
	orb.add_child(halo)
	add_child(orb)
	_orbs.append({"node": orb, "dir": facing, "v": aim, "travelled": 0.0, "trail_left": 0.0})
	print("DEEPFALL_ORB_FIRED facing=%d" % facing)

# Phase 9: mage orb trail + impact, from the staged effects library
# (frost-burst frames, sliced to assets/effects/orb_impact_0..2.png).
# The trail is small fading cyan dots dropped every 24 px of flight
# (code-drawn, same cyan as the orb); the impact is the staged burst.
func _orb_impact_frames_loaded() -> Array:
	if _orb_impact_frames.is_empty():
		for i in range(3):
			_orb_impact_frames.append(load("res://assets/effects/orb_impact_%d.png" % i))
	return _orb_impact_frames

# Phase 9b: one EffekseerEmitter2D for an effect path, played once and
# freed after `life` seconds via a child Timer. Returns null when the
# plugin is absent, the resource fails to load, or instantiation fails.
# Dynamic (ClassDB / set / call) on purpose: no static reference to the
# plugin classes, so this file parses with the addon removed.
func _make_effekseer_emitter(effect_path: String, pos: Vector2, life: float) -> Node:
	if not ClassDB.class_exists("EffekseerEmitter2D"):
		return null
	var res: Resource = load(effect_path)
	if res == null:
		return null
	var em: Node = ClassDB.instantiate("EffekseerEmitter2D")
	if em == null:
		return null
	em.set("effect", res)
	em.set("autoplay", false)
	em.position = pos
	add_child(em)
	em.call("play")
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = life
	timer.timeout.connect(em.queue_free)
	em.add_child(timer)
	timer.start()
	return em

func _spawn_orb_impact(pos: Vector2) -> void:
	# Phase 9b: Effekseer mage_orb_impact replaces the PNG burst when the
	# plugin is present; the staged frost-burst frames are the fallback.
	if _make_effekseer_emitter(ORB_IMPACT_EFK, pos, 0.8) != null:
		return
	var spr := Sprite2D.new()
	var frames := _orb_impact_frames_loaded()
	spr.texture = frames[0]
	spr.scale = Vector2(0.5, 0.5)
	spr.position = pos
	add_child(spr)
	_orb_fx.append({"node": spr, "frames": frames, "t": 0.0, "dur": 0.25, "fade": false})

func _spawn_orb_trail_dot(pos: Vector2) -> void:
	var dot := Polygon2D.new()
	var pts := PackedVector2Array()
	for k in range(8):
		var a := TAU * k / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 6.0)
	dot.polygon = pts
	dot.color = Color(0.5, 0.89, 0.94, 0.45)
	dot.position = pos
	add_child(dot)
	_orb_fx.append({"node": dot, "frames": [], "t": 0.0, "dur": 0.25, "fade": true})

func _update_fx(delta: float) -> void:
	for fx in _orb_fx.duplicate():
		var node: Node2D = fx["node"]
		if not is_instance_valid(node):
			_orb_fx.erase(fx)
			continue
		fx["t"] = float(fx["t"]) + delta
		var frames: Array = fx["frames"]
		if not frames.is_empty():
			var idx: int = mini(int(float(fx["t"]) * 12.0), frames.size() - 1)
			(node as Sprite2D).texture = frames[idx]
		elif bool(fx["fade"]):
			node.modulate = Color(1, 1, 1, clampf(1.0 - float(fx["t"]) / float(fx["dur"]), 0.0, 1.0))
		if float(fx["t"]) >= float(fx["dur"]):
			_orb_fx.erase(fx)
			node.queue_free()

func _update_orbs(delta: float) -> void:
	for o in _orbs.duplicate():
		var orb: Node2D = o["node"]
		if not is_instance_valid(orb):
			_orbs.erase(o)
			continue
		var step := ORB_SPEED * delta
		orb.position += (o.get("v", Vector2(int(o["dir"]), 0)) as Vector2) * step
		o["travelled"] = float(o["travelled"]) + step
		# Phase 9 trail: a fading dot every 24 px of flight.
		o["trail_left"] = float(o.get("trail_left", 0.0)) + step
		if float(o["trail_left"]) >= 24.0:
			o["trail_left"] = 0.0
			_spawn_orb_trail_dot(orb.position)
		var hit := false
		for e in enemies.duplicate():
			if is_instance_valid(e) and orb.position.distance_to(e.position) <= 28.0:
				e.take_hit(ORB_DMG, orb.position.x - int(o["dir"]) * 24.0, (o.get("v", Vector2(int(o["dir"]), 0)) as Vector2) * 300.0 + Vector2(0, -120))
				if fx != null:
					fx.float_text(e.position + Vector2(0, -50), str(ORB_DMG), Color(0.6, 1.0, 0.95))
				hit = true
				break
		if not hit:
			for pr in phys_props.duplicate():
				if is_instance_valid(pr) and not pr.broken and pr.rect().grow(6.0).has_point(orb.position):
					pr.take_hit(ORB_DMG, orb.position - (o.get("v", Vector2.RIGHT) as Vector2) * 24.0)
					hit = true
					break
		var cell := Vector2i(int(floor(orb.position.x / TILE)),
			int(floor(orb.position.y / TILE)))
		if not hit and (cell.x < 0 or cell.x >= 80 or cell.y < 0 or cell.y >= 45
				or (fg[cell.y][cell.x] != 0 and fg[cell.y][cell.x] != 7)):
			hit = true  # orb dies on a solid block (platforms do not stop it)
		if hit or float(o["travelled"]) >= ORB_RANGE:
			_spawn_orb_impact(orb.position)
			_orbs.erase(o)
			orb.queue_free()

func spawn_death_fx(pos: Vector2) -> void:
	var fx: Node2D = DEATH_FX_SCRIPT.new()
	fx.position = pos
	add_child(fx)

func player_died() -> void:
	print("DEEPFALL_PLAYER_DIED")
	spawn_death_fx(player.position)
	_deaths += 1
	if _cards_enabled:
		_card_pending = 0.9
		_card_reason = "death"
	else:
		_respawn_timer = 1.2

func respawn_run() -> void:
	var spawn: Vector2i = data["spawn"]
	player.respawn_at(Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE))
	# Phase 6: slain enemies stay dead across a player death — the
	# respawn re-derives the spawn table and only re-spawns the living.
	_refresh_enemies_for_chunks()
	print("DEEPFALL_PLAYER_RESPAWN")

func _find_air_cell_in_chunk(sc: Vector2i) -> Vector2i:
	for y in range(sc.y * STREAM, sc.y * STREAM + STREAM):
		for x in range(sc.x * STREAM, sc.x * STREAM + STREAM):
			if y + 1 >= 45:
				continue
			if fg[y][x] == 0 and fg[y + 1][x] != 0:
				return Vector2i(x, y)
	for y in range(sc.y * STREAM, sc.y * STREAM + STREAM):
		for x in range(sc.x * STREAM, sc.x * STREAM + STREAM):
			if fg[y][x] == 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _run_screenshot_pair() -> void:
	# --screenshot-pair: shot 1 spawn chamber (torch lit here), shot 2
	# the chunk gate (x=20, the first room boundary — never visually
	# confirmed before), shot 3 a trestle room (room 2, even-numbered).
	# Run with --new-run so a saved game does not restore class/position.
	_try_place_torch_here()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("res://screenshot_pair_spawn.png")
	print("DEEPFALL_SCREENSHOT_PAIR_SPAWN")
	var gate_cell := _chamber_gate
	player.position = Vector2((gate_cell.x + 0.5) * TILE, (gate_cell.y + 1) * TILE - player.half_h)
	player.vel = Vector2.ZERO
	player.on_ground = false
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("res://screenshot_pair_gate.png")
	print("DEEPFALL_SCREENSHOT_PAIR_GATE")
	var rc: Vector2i = _room_center(2)
	player.position = Vector2((rc.x + 0.5) * TILE, (rc.y + 1) * TILE - player.half_h)
	player.vel = Vector2.ZERO
	player.on_ground = false
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("res://screenshot_pair_room2.png")
	print("DEEPFALL_SCREENSHOT_PAIR_ROOM2")

func _run_selftest() -> void:
	# Headless-only combat smoke test (--selftest): spawns one ghoul
	# next to the player, forces a melee strike and an enemy hit, then
	# runs the Phase 6 chunk/delta/save checks, prints DEEPFALL_SELFTEST
	# lines and quits. Never runs in normal play.
	await get_tree().create_timer(0.5).timeout
	var cell: Vector2i = player.cell() + Vector2i(1, 0)
	_spawn_one("miner-ghoul", cell)
	var ghoul: Node2D = enemies[enemies.size() - 1]
	# Force the player strike directly (bypasses the physics-timer path).
	player_attack_hit(player.position, 1)
	print("DEEPFALL_SELFTEST enemy_hp_after_player_hit=%d (ghoul max 20, expect 5)" % ghoul.hp)
	# Enemy hits the player: 8 damage from full HP.
	player.take_hit(8, ghoul.position.x)
	print("DEEPFALL_SELFTEST player_hp_after_enemy_hit=%d (expect 92)" % player.hp)
	# Finish the ghoul off and confirm the kill count + death path.
	# (Test ghoul has spawn_id -1: it is not in the spawn table, so it
	# does not consume a delta slot; foes remaining stays 10.)
	ghoul.take_hit(99, player.position.x)
	print("DEEPFALL_SELFTEST kills=%d foes_remaining=%d (expect 1, 10)" % [kills, _foes_remaining()])
	_run_selftest_phase6()
	_run_selftest_phase7()
	_run_selftest_phase8()
	await _run_selftest_phase9()
	await _run_selftest_phase9b()
	await _run_selftest_phase10()
	print("DEEPFALL_SELFTEST done")
	get_tree().quit()

func _run_selftest_phase6() -> void:
	print("DEEPFALL_SELFTEST_PHASE6 start")
	var spawn: Vector2i = data["spawn"]
	# (a) Mine a solid cell in the player's stream chunk, twice.
	var sc0 := _stream_chunk_of(player.cell())
	var test_cell := Vector2i(-1, -1)
	for y in range(sc0.y * STREAM, sc0.y * STREAM + STREAM):
		for x in range(sc0.x * STREAM, sc0.x * STREAM + STREAM):
			var t: int = fg[y][x]
			if t != 0 and t != 7 and _is_air(Vector2i(x, y - 1)):
				test_cell = Vector2i(x, y)
				break
		if test_cell.x >= 0:
			break
	if test_cell.x < 0:
		print("DEEPFALL_SELFTEST_PHASE6 a FAIL no solid test cell in stream chunk %s" % str(sc0))
		return
	_mine_at(test_cell)
	var cracked_ok: bool = mine_damage.has(test_cell)
	_mine_at(test_cell)
	var mined_ok: bool = fg[test_cell.y][test_cell.x] == 0 and _mined_cells.has(test_cell) and _fg_layer_for(test_cell).get_cell_source_id(test_cell) == -1
	print("DEEPFALL_SELFTEST_PHASE6 a cell=%s cracked_first=%s mined=%s layer_erased=%s" % [
		str(test_cell), str(cracked_ok), str(mined_ok),
		str(_fg_layer_for(test_cell).get_cell_source_id(test_cell) == -1)])
	# Leave the chunk: teleport to a far chunk (4,0), force a chunk update.
	var far_cell := _find_air_cell_in_chunk(Vector2i(4, 0))
	player.position = Vector2((far_cell.x + 0.5) * TILE, (far_cell.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	_apply_chunk_visibility(true)
	var old_id: int = _chunk_id_for_cell(test_cell)
	var old_unloaded: bool = not _fg_layers[old_id].visible
	var far_loaded: bool = _fg_layers[_chunk_id_for_cell(far_cell)].visible
	print("DEEPFALL_SELFTEST_PHASE6 a2 left_chunk old_chunk=%d unloaded=%s far_chunk_loaded=%s fg_still_mined=%s" % [
		old_id, str(old_unloaded), str(far_loaded), str(fg[test_cell.y][test_cell.x] == 0)])
	# Come back: the mined cell must still be mined, chunk visible again.
	player.position = Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	_apply_chunk_visibility(true)
	var back_ok: bool = fg[test_cell.y][test_cell.x] == 0 and _fg_layers[old_id].visible and _fg_layer_for(test_cell).get_cell_source_id(test_cell) == -1
	print("DEEPFALL_SELFTEST_PHASE6 a3 returned still_mined=%s chunk_visible=%s layer_erased=%s" % [
		str(fg[test_cell.y][test_cell.x] == 0), str(_fg_layers[old_id].visible),
		str(_fg_layer_for(test_cell).get_cell_source_id(test_cell) == -1)])
	# (c) Cross the x=20 legacy chunk boundary and the x=16 stream boundary.
	var row_y: float = (spawn.y + 0.5) * TILE
	player.position = Vector2(15.5 * TILE, row_y)
	_apply_chunk_visibility(true)
	var leg_before: int = clampi(int(player.cell().x) / CHUNK_W, 0, 3)
	var stream_before := _stream_chunk_of(player.cell())
	player.position = Vector2(20.5 * TILE, row_y)
	_apply_chunk_visibility(true)
	var leg_after: int = clampi(int(player.cell().x) / CHUNK_W, 0, 3)
	var stream_after := _stream_chunk_of(player.cell())
	player.position = Vector2(16.5 * TILE, row_y)
	_apply_chunk_visibility(true)
	var stream_mid := _stream_chunk_of(player.cell())
	print("DEEPFALL_SELFTEST_PHASE6 c legacy_chunk %d->%d (expect 0->1) stream %s->%s (expect (0,1)->(1,1)) stream_at_16.5=%s" % [
		leg_before, leg_after, str(stream_before), str(stream_after), str(stream_mid)])
	# (b) Place a torch, save, rebuild from the save file in-process.
	player.position = Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	_apply_chunk_visibility(true)
	var torch_cell := _try_place_torch_here()
	var saved_pos: Vector2 = player.position
	var saved_hp: int = player.hp
	var saved_ore: int = ore_collected
	save_game("selftest")
	_rebuild_world(true)
	var b_ok: bool = fg[test_cell.y][test_cell.x] == 0 and player.position == saved_pos and ore_collected == saved_ore and player.hp == saved_hp
	var torch_ok: bool = torch_cell.x < 0 or torches.has(torch_cell)
	print("DEEPFALL_SELFTEST_PHASE6 b reload mined_still_air=%s torch_cell=%s torch_restored=%s pos_restored=%s hp=%d ore=%d" % [
		str(fg[test_cell.y][test_cell.x] == 0), str(torch_cell), str(torch_ok),
		str(player.position == saved_pos), player.hp, ore_collected])
	print("DEEPFALL_SELFTEST_PHASE6 done a=%s a3=%s c_legacy=%s c_stream=%s b=%s" % [
		str(mined_ok), str(back_ok), str(leg_before == 0 and leg_after == 1),
		str(stream_before == Vector2i(0, 1) and stream_after == Vector2i(1, 1)), str(b_ok and torch_ok)])

func _run_selftest_load() -> void:
	# Fresh-process reload check (--selftest-load): the world was built
	# from the save file in _ready; verify every delta in the file
	# against the live world, then quit. Run after a --selftest run
	# (which saves) to prove save/load survives an app restart.
	var d := _load_save_dict()
	if d.is_empty():
		print("DEEPFALL_SELFTEST_LOAD FAIL no save file found")
		get_tree().quit()
		return
	var ok := true
	for key in d.get("mined", []):
		var c := _key_to_cell(String(key))
		if fg[c.y][c.x] != 0:
			ok = false
			print("DEEPFALL_SELFTEST_LOAD FAIL mined cell %s not air" % str(c))
	var td: Dictionary = d.get("torches", {})
	for key in td.keys():
		var c2 := _key_to_cell(String(key))
		if not torches.has(c2):
			ok = false
			print("DEEPFALL_SELFTEST_LOAD FAIL torch %s missing" % str(c2))
	var pd: Dictionary = d.get("player", {})
	var expect_pos := Vector2(float(pd.get("x", 0.0)), float(pd.get("y", 0.0)))
	var pos_ok: bool = player.position == expect_pos
	var hp_ok: bool = player.hp == int(pd.get("hp", 100))
	var ore_ok: bool = ore_collected == int(d.get("ore", 0))
	if not pos_ok or not hp_ok or not ore_ok:
		ok = false
	print("DEEPFALL_SELFTEST_LOAD mined=%d torches=%d slain=%d pos_ok=%s hp_ok=%s ore_ok=%s PASS=%s" % [
		(d.get("mined", []) as Array).size(), td.size(),
		(d.get("slain", []) as Array).size(), str(pos_ok), str(hp_ok), str(ore_ok), str(ok)])
	var invd: Dictionary = d.get("inventory", {})
	var inv_ok := true
	for k in inv.keys():
		if int(invd.get(k, 0)) != int(inv[k]):
			inv_ok = false
			print("DEEPFALL_SELFTEST_LOAD FAIL inv %s save=%s live=%s" % [k, str(invd.get(k, 0)), str(inv[k])])
	var ld7: Dictionary = d.get("lanterns", {})
	var lan_ok := true
	for key in ld7.keys():
		if not lanterns.has(_key_to_cell(String(key))):
			lan_ok = false
			print("DEEPFALL_SELFTEST_LOAD FAIL lantern %s missing" % str(key))
	var wd7: Dictionary = d.get("workbenches", {})
	var bench_ok := true
	for key in wd7.keys():
		if not workbenches.has(_key_to_cell(String(key))):
			bench_ok = false
			print("DEEPFALL_SELFTEST_LOAD FAIL workbench %s missing" % str(key))
	print("DEEPFALL_SELFTEST_LOAD_PHASE7 inv_ok=%s lanterns=%d lan_ok=%s workbenches=%d bench_ok=%s PASS7=%s" % [
		str(inv_ok), ld7.size(), str(lan_ok), wd7.size(), str(bench_ok), str(inv_ok and lan_ok and bench_ok)])
	# Phase 8: the save's class field must match the live player class.
	var save_class := String(d.get("class", "tech"))
	var class_ok: bool = player.class_id == save_class
	print("DEEPFALL_SELFTEST_LOAD_PHASE8 save_class=%s live_class=%s class_ok=%s" % [
		save_class, player.class_id, str(class_ok)])
	get_tree().quit()

func _build_polished_chamber() -> void:
	# Phase 4 chamber: built INTO the seeded world (spawn room + first
	# corridor), never a separate scene. All choices derive from stable
	# world coordinates / the seed, so re-rendering seed 20261101 gives
	# the identical chamber. Collision topology is unchanged except:
	# an elevated platform row inside the spawn room (one-way platforms,
	# already traversable by the flood-fill) and a 2-cell mining pocket
	# carved into solid rock adjacent to room air (reachable by
	# construction). Everything else is visual-only or solid-to-solid.
	var r0: Array = data["rooms"][0]
	var rx: int = r0[0]; var ry: int = r0[1]; var rw: int = r0[2]; var rh: int = r0[3]
	var floor_y: int = ry + rh - 1
	# Elevated route: one-way wood platforms across the spawn room.
	var plat_y: int = floor_y - 3
	if plat_y > ry:
		for xx in range(rx + 1, rx + rw - 1):
			if fg[plat_y][xx] == 0:
				fg[plat_y][xx] = 7
	# Mining pocket + connected ore vein, carved into the right wall.
	var px: int = rx + rw
	if px + 2 < 80:
		for py in [floor_y - 2, floor_y - 1]:
			if py >= 0 and fg[py][px] != 0:
				fg[py][px] = 0
		var vein := [Vector2i(px + 1, floor_y - 2), Vector2i(px + 1, floor_y - 1),
			Vector2i(px + 2, floor_y - 2)]
		var k := 0
		for vc in vein:
			if fg[vc.y][vc.x] != 0 and fg[vc.y][vc.x] != 7:
				fg[vc.y][vc.x] = 4 if k % 2 == 0 else 5
				k += 1
	# Collapsed passage: left wall turns cracked-stone (still solid —
	# collision unchanged), debris props are added in _render_chamber().
	for py in [floor_y - 2, floor_y - 1]:
		if rx - 1 >= 0 and fg[py][rx - 1] != 0:
			fg[py][rx - 1] = 10

func _render_chamber() -> void:
	# Visual chamber furniture, called after _render_props. All visual
	# only; no collision, never on spawn/exit cells. Props are added to
	# their chunk container (Phase 6) so they stream with the chunk.
	var r0: Array = data["rooms"][0]
	var rx: int = r0[0]; var ry: int = r0[1]; var rw: int = r0[2]; var rh: int = r0[3]
	var floor_y: int = ry + rh - 1
	var spawn: Vector2i = data["spawn"]
	var exit_cell: Vector2i = data["exit"]
	# Timber-supported tunnel: two posts + a beam across the room centre.
	var midx: int = rx + rw / 2
	for sx in [midx - 2, midx + 2]:
		var post := Sprite2D.new()
		post.texture = load("res://assets/atlas3/timber_post.png")
		post.scale = Vector2(128.0 / 766.0, 128.0 / 766.0)
		post.position = Vector2(sx * TILE + 32, (floor_y - 2) * TILE + 64)
		post.z_index = 1
		_add_prop(post, Vector2i(sx, floor_y - 2))
	var beam := ColorRect.new()
	beam.size = Vector2(5 * TILE, 12)
	beam.position = Vector2((midx - 2) * TILE, (floor_y - 3) * TILE + 20)
	beam.color = Color(0.35, 0.24, 0.12, 1.0)
	beam.z_index = 1
	_add_prop(beam, Vector2i(midx, floor_y - 3))
	# Collapsed-passage debris cluster at the cracked left wall.
	for k in range(3):
		var dc := Vector2i(rx + k, floor_y - 1)
		if dc == spawn or dc == exit_cell or fg[floor_y - 1][rx + k] != 0:
			continue
		if not _decor_ok(dc):
			continue
		var deb := ColorRect.new()
		deb.size = Vector2(14, 7)
		deb.position = Vector2(dc.x * TILE + 8 + k * 12, floor_y * TILE - 7)
		deb.color = Color(0.16, 0.15, 0.17, 1.0)
		deb.z_index = 1
		_add_prop(deb, dc)
	# Landmark: the Amber Spire, a large amber crystal on the room floor.
	var spire_x: float = (rx + 2.5) * TILE
	var spire := Polygon2D.new()
	spire.polygon = PackedVector2Array([Vector2(0, -30), Vector2(18, 0),
		Vector2(0, 30), Vector2(-18, 0)])
	spire.color = Color(1.0, 0.77, 0.42, 1.0)
	spire.position = Vector2(spire_x, floor_y * TILE - 30)
	spire.z_index = 1
	_add_prop(spire, Vector2i(rx + 2, floor_y - 1))
	var spire_light := PointLight2D.new()
	spire_light.color = Color(1.0, 0.77, 0.42)
	spire_light.energy = 0.8
	spire_light.texture = _light_gradient_texture()
	spire_light.texture_scale = 256.0 / 448.0
	spire_light.shadow_enabled = false
	spire_light.position = spire.position
	_add_prop(spire_light, Vector2i(rx + 2, floor_y - 1))
	# Two static warm chamber lights (not pickable torches — they are
	# not in the torches dict, so click-pickup does not touch them).
	for lx in [rx + 2, rx + rw - 3]:
		var lc := Vector2i(lx, floor_y - 2)
		if fg[floor_y - 2][lx] != 0:
			continue
		var light := PointLight2D.new()
		light.color = Color(1.0, 0.70, 0.36)
		light.energy = 1.0
		light.texture = _light_gradient_texture()
		light.texture_scale = 1.0
		light.shadow_enabled = false
		light.position = Vector2((lc.x + 0.5) * TILE, (lc.y + 0.5) * TILE)
		_add_prop(light, lc)
		var stick := Sprite2D.new()
		stick.texture = load("res://assets/torch.png")
		stick.scale = Vector2(0.08, 0.08)
		stick.position = light.position
		_add_prop(stick, lc)
		var embers := CPUParticles2D.new()
		# Phase 10 perf: 10 -> 6 per light (2 chamber lights: 20 -> 12
		# particles total). Same lifetime/velocity, slightly sparser.
		embers.amount = 6
		embers.lifetime = 1.2
		embers.emitting = true
		embers.direction = Vector2(0, -1)
		embers.spread = 20.0
		embers.gravity = Vector2(0, -60)
		embers.initial_velocity_min = 20.0
		embers.initial_velocity_max = 40.0
		embers.scale_amount_min = 2.0
		embers.scale_amount_max = 4.0
		embers.color = Color(1.0, 0.6, 0.2, 1.0)
		embers.position = light.position + Vector2(0, -16)
		_add_prop(embers, lc)
	# Chunk transition gate: first floor-standing air cell on the x=20
	# chunk boundary, derived from world coordinates only — streaming
	# the neighbouring chunk re-derives the same gate, no seam.
	for yy in range(45):
		if fg[yy][CHUNK_W] == 0 and fg[yy][CHUNK_W - 1] == 0 and yy + 1 < 45 and fg[yy + 1][CHUNK_W] != 0:
			_chamber_gate = Vector2i(CHUNK_W, yy)
			for gx in [CHUNK_W - 1, CHUNK_W]:
				var gpost := Sprite2D.new()
				gpost.texture = load("res://assets/atlas3/timber_post.png")
				gpost.scale = Vector2(96.0 / 766.0, 96.0 / 766.0)
				gpost.position = Vector2(gx * TILE + 32, yy * TILE + 32)
				gpost.z_index = 1
				_add_prop(gpost, Vector2i(gx, yy))
			var glight := PointLight2D.new()
			glight.color = Color(1.0, 0.77, 0.42)
			glight.energy = 0.7
			glight.texture = _light_gradient_texture()
			glight.texture_scale = 192.0 / 448.0
			glight.shadow_enabled = false
			glight.position = Vector2((CHUNK_W - 0.5) * TILE, (yy - 1) * TILE)
			_add_prop(glight, Vector2i(CHUNK_W, yy))
			break

func _decor_ok(c: Vector2i) -> bool:
	# Variation budget: at most 3 decorative items per 5x5 local area.
	var key := Vector2i(c.x / 5, c.y / 5)
	var n: int = _decor_area.get(key, 0)
	if n >= 3:
		return false
	_decor_area[key] = n + 1
	return true

func _render_background() -> void:
	# Distant cave silhouettes, world-space (no parallax: a ParallaxBackground
	# would fight the camera limits and risk revealing void — recorded gap).
	var bg: Node2D = $Background
	var sil := Polygon2D.new()
	sil.polygon = PackedVector2Array([Vector2(0, 0), Vector2(5120, 0),
		Vector2(5120, 320), Vector2(4300, 180), Vector2(3400, 300),
		Vector2(2500, 140), Vector2(1500, 280), Vector2(600, 160), Vector2(0, 300)])
	sil.color = Color(0.055, 0.09, 0.15, 1.0)
	bg.add_child(sil)
	# Atlas-art cave scene as a large backdrop centred on the spawn chamber.
	# World-space, no parallax; outside its footprint the old fill remains.
	var spawn_c: Vector2i = data["spawn"]
	var cave := Sprite2D.new()
	cave.texture = load("res://assets/atlas3/cave-silhouettes.png")
	cave.scale = Vector2(0.8, 0.8)
	cave.position = Vector2((spawn_c.x + 0.5) * TILE, (spawn_c.y + 0.5) * TILE)
	cave.z_index = 0
	# NOTE: must be a direct child of Main, not of Background (z=-2):
	# a Background child is grouped below the wall layer regardless of
	# its own z_index, which hid the sprite entirely in the first pass.
	add_child(cave)
	# Phase 6 fix: the cave must sit BEFORE Player in child order
	# (same z_index 0). Pointing it at the first chunk FgLayer put it
	# AFTER Player — the chunk layers are appended in code, not in
	# scene order — and the big dark backdrop then hid the player.
	move_child(cave, player.get_index())
	cave.modulate = Color(0.55, 0.6, 0.7, 1.0)
	var ruin := ColorRect.new()
	ruin.position = Vector2(120, 900)
	ruin.size = Vector2(180, 420)
	ruin.color = Color(0.08, 0.12, 0.20, 1.0)
	bg.add_child(ruin)
	# distant blue-lit cavern opening, behind the far rooms
	var opening := Polygon2D.new()
	opening.polygon = PackedVector2Array([Vector2(0, -90), Vector2(70, 0),
		Vector2(0, 90), Vector2(-70, 0)])
	opening.color = Color(0.20, 0.55, 0.65, 0.55)
	opening.position = Vector2(4600, 700)
	bg.add_child(opening)
	var glow := PointLight2D.new()
	glow.color = Color(0.5, 0.89, 0.94)
	glow.energy = 0.5
	glow.texture = _light_gradient_texture()
	glow.texture_scale = 0.6
	glow.shadow_enabled = false
	glow.position = Vector2(4600, 700)
	bg.add_child(glow)
	# Phase 9: PARALLAX — two layers of the staged cave-silhouettes art,
	# moving at different rates from the camera (far 0.35x, mid 0.65x).
	# They are direct Main children with negative z so they sit behind
	# the wall layer; _update_parallax() repositions them every frame
	# from the camera centre (base offsets chosen so the texture always
	# covers the 1280x720 viewport at any camera position — see the
	# self-test, which prints both layers' positions at two cameras).
	# Modulate is brighter than the old static backdrop's because
	# CanvasModulate darkens this canvas too; effective brightness ends
	# up comparable to the static layer.
	_plx_far = Sprite2D.new()
	_plx_far.texture = load("res://assets/atlas3/cave-silhouettes.png")
	_plx_far.scale = Vector2(1.5, 1.5)
	_plx_far.modulate = Color(0.35, 0.42, 0.58, 1.0)
	_plx_far.z_index = -3
	add_child(_plx_far)
	_plx_mid = Sprite2D.new()
	_plx_mid.texture = load("res://assets/atlas3/cave-silhouettes.png")
	_plx_mid.scale = Vector2(2.0, 2.0)
	_plx_mid.flip_h = true
	_plx_mid.modulate = Color(0.5, 0.58, 0.75, 1.0)
	_plx_mid.z_index = -2
	add_child(_plx_mid)
	_update_parallax()

func _update_torch_lights() -> void:
	# Phase 10 perf: cap simultaneous real torch PointLight2Ds in view
	# (nearest 6, shadows only on the nearest 4). Lights beyond the cap
	# are disabled and fall back to their cheap gradient-glow sprite
	# (added in _place_torch_at), so the room never goes dark. Lanterns
	# keep their (shadowless) lights — they are rare and stationary.
	# Lights in unloaded chunks are freed by _apply_chunk_visibility,
	# not just hidden (see the cull there).
	var pp: Vector2 = player.position
	var items: Array = []
	for key in torches.keys():
		var t: Node2D = torches[key]
		items.append({"node": t, "d": t.position.distance_squared_to(pp)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	for idx in range(items.size()):
		var t: Node2D = items[idx]["node"]
		var light: PointLight2D = t.get_node_or_null("Light")
		var glow: Sprite2D = t.get_node_or_null("Glow")
		var on: bool = idx < 6
		if light != null:
			light.enabled = on
			light.shadow_enabled = on and idx < 4
		if glow != null:
			glow.visible = not on

func _update_parallax() -> void:
	# world_pos = base + camera_centre * (1 - factor): the layer drifts
	# slower than the world, which is what makes it read as distant.
	if _plx_far == null or _plx_mid == null or camera == null:
		return
	var cc: Vector2 = camera.get_screen_center_position()
	# Phase 10 perf: the two 1920x1280 parallax sprites were
	# repositioned every frame even when the camera was static (the
	# common case: standing still). Skip the writes when unchanged.
	if cc == _last_parallax_cam:
		return
	_last_parallax_cam = cc
	_plx_far.position = Vector2(-128.0 + cc.x * 0.65, -200.0 + cc.y * 0.65)
	_plx_mid.position = Vector2(0.0 + cc.x * 0.35, -200.0 + cc.y * 0.35)

const VARIANT_COUNTS := {"stone": 16, "dirt": 16,
	"trans_rock_N": 1, "trans_rock_E": 1, "trans_rock_S": 1, "trans_rock_W": 1,
	"trans_dirt_N": 1, "trans_dirt_E": 1, "trans_dirt_S": 1, "trans_dirt_W": 1,
	"corner_rock_TL": 1, "corner_rock_TR": 1, "corner_rock_BL": 1, "corner_rock_BR": 1,
	"corner_dirt_TL": 1, "corner_dirt_TR": 1, "corner_dirt_BL": 1, "corner_dirt_BR": 1}

func _neighbour_mask(x: int, y: int) -> int:
	# Topology bits, not randomness: N=1, E=2, S=4, W=8 where the
	# neighbour is air (inside the world; borders count as solid).
	var m := 0
	if y > 0 and fg[y - 1][x] == 0: m += 1
	if x + 1 < 80 and fg[y][x + 1] == 0: m += 2
	if y + 1 < 45 and fg[y + 1][x] == 0: m += 4
	if x > 0 and fg[y][x - 1] == 0: m += 8
	return m

func _variant(x: int, y: int, tile_name: String = "") -> int:
	# Phase 4 adjacency rule: variant is a pure function of the cell's
	# neighbour mask and its stable world-coordinate block (x//4, y//4).
	# No random pick from the whole atlas; same seed + same world =
	# same variant, and a mined neighbour re-derives only its own cell.
	var n: int = VARIANT_COUNTS.get(tile_name, 4)
	var mask := _neighbour_mask(x, y)
	return (mask * 3 + (x / 4 + y / 4)) % n

func _mat_group(t: int) -> int:
	# 0 stone family, 1 dirt family, 2 ore, 3 other (wood/brick/platform)
	if t == 3 or t == 9 or t == 10 or t == 12: return 0
	if t == 1 or t == 2 or t == 11: return 1
	if t == 4 or t == 5 or t == 13: return 2
	return 3

func _build_tileset() -> void:
	var names: Array = TILE_NAMES + ["dirt-wall", "cave-wall-dark"] + TRANS_NAMES
	var cols := names.size()
	var atlas := Image.create(cols * TILE, 16 * TILE, false, Image.FORMAT_RGBA8)
	for i in range(names.size()):
		var count: int = VARIANT_COUNTS.get(names[i], 4)
		for v in range(count):
			var path: String = "res://assets/tiles2/%s_v%d.png" % [names[i], v]
			if names[i] == "stone":
				path = "res://assets/atlas3/rock_%d.png" % v
			elif names[i] == "dirt":
				path = "res://assets/atlas3/dirt_%d.png" % v
			var tex: Texture2D = load(path)
			var im: Image = tex.get_image()
			im.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(im, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, v * TILE))
	var atlas_tex := ImageTexture.create_from_image(atlas)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = atlas_tex
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in range(names.size()):
		for v in range(VARIANT_COUNTS.get(names[i], 4)):
			src.create_tile(Vector2i(i, v), Vector2i(1, 1))
	tileset.add_source(src)
	_main_tileset = tileset
	# edge / corner overlay tileset (8 tiles in one row)
	var eatlas := Image.create(8 * TILE, TILE, false, Image.FORMAT_RGBA8)
	for i in range(EDGE_NAMES.size()):
		var tex: Texture2D = load("res://assets/%s.png" % EDGE_NAMES[i])
		var im: Image = tex.get_image()
		im.convert(Image.FORMAT_RGBA8)
		eatlas.blit_rect(im, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	var etex := ImageTexture.create_from_image(eatlas)
	var etileset := TileSet.new()
	etileset.tile_size = Vector2i(TILE, TILE)
	var esrc := TileSetAtlasSource.new()
	esrc.texture = etex
	esrc.texture_region_size = Vector2i(TILE, TILE)
	for i in range(EDGE_NAMES.size()):
		esrc.create_tile(Vector2i(i, 0), Vector2i(1, 1))
	etileset.add_source(esrc)
	_edge_tileset = etileset
	# damage overlay tileset (single tile)
	var datlas := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var dtex2: Texture2D = load("res://assets/damage.png")
	var dim: Image = dtex2.get_image()
	dim.convert(Image.FORMAT_RGBA8)
	datlas.blit_rect(dim, Rect2i(0, 0, TILE, TILE), Vector2i(0, 0))
	var dtileset := TileSet.new()
	dtileset.tile_size = Vector2i(TILE, TILE)
	var dsrc := TileSetAtlasSource.new()
	dsrc.texture = ImageTexture.create_from_image(datlas)
	dsrc.texture_region_size = Vector2i(TILE, TILE)
	dsrc.create_tile(Vector2i(0, 0), Vector2i(1, 1))
	dtileset.add_source(dsrc)
	_damage_tileset = dtileset

# Phase 9: true transition / corner tile selection. Returns the atlas
# COLUMN of the special tile for this cell, or -1 for a plain fill variant.
# Priority (first match wins): material transition (a solid orthogonal
# neighbour of the other family — rock vs dirt), then outer corner (two
# adjacent air orthogonals). Ore / wood / brick cells never take these
# tiles — they keep their own fill. Pure function of (fg, cell), so a
# mined neighbour re-derives the cell via _set_fill_cell() with no RNG.
func _fill_special(c: Vector2i) -> int:
	if c.x < 0 or c.x >= 80 or c.y < 0 or c.y >= 45:
		return -1
	var t: int = fg[c.y][c.x]
	var g := _mat_group(t)
	if g != 0 and g != 1:
		return -1
	# Atlas columns: 0..12 TILE_NAMES, 13..14 walls, 15..30 TRANS_NAMES.
	var base_col := 15
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for i in range(4):
		var nb: Vector2i = c + dirs[i]
		if nb.x >= 0 and nb.x < 80 and nb.y >= 0 and nb.y < 45 and _is_solid_cell(nb):
			var ng := _mat_group(fg[nb.y][nb.x])
			if (g == 0 and ng == 1) or (g == 1 and ng == 0):
				# TRANS_NAMES order: rock N/E/S/W (0-3), dirt N/E/S/W (4-7).
				return base_col + (i if g == 0 else 4 + i)
	var top := _is_air(c + Vector2i(0, -1))
	var bot := _is_air(c + Vector2i(0, 1))
	var left := _is_air(c + Vector2i(-1, 0))
	var right := _is_air(c + Vector2i(1, 0))
	var corner_off := -1
	if top and left:
		corner_off = 0
	elif top and right:
		corner_off = 1
	elif bot and left:
		corner_off = 2
	elif bot and right:
		corner_off = 3
	if corner_off >= 0:
		# TRANS_NAMES order: corner rock TL/TR/BL/BR (8-11), dirt (12-15).
		return base_col + 8 + (corner_off if g == 0 else 4 + corner_off)
	return -1

func _set_fill_cell(c: Vector2i) -> void:
	# (Re)derives one cell's fill tile in its chunk layer: special
	# transition/corner art when the neighbour mask calls for it, else
	# the Phase 4 neighbour-mask variant. Air erases the cell.
	if c.x < 0 or c.x >= 80 or c.y < 0 or c.y >= 45:
		return
	var layer := _fg_layer_for(c)
	var t: int = fg[c.y][c.x]
	if t == 0:
		layer.erase_cell(c)
		return
	var sp := _fill_special(c)
	if sp >= 0:
		layer.set_cell(c, 0, Vector2i(sp, 0))
		return
	var idx: int = FG_TO_ATLAS.get(t, 2)
	layer.set_cell(c, 0, Vector2i(idx, _variant(c.x, c.y, TILE_NAMES[idx])))

func _render_layers() -> void:
	for y in range(45):
		for x in range(80):
			var c := Vector2i(x, y)
			_set_fill_cell(c)
			var w: int = wall[y][x]
			if w != 0:
				var idx2: int = WALL_TO_ATLAS[w]
				_wall_layer_for(c).set_cell(c, 0, Vector2i(idx2, _variant(x, y)))

func _is_solid_cell(c: Vector2i) -> bool:
	if c.x < 0 or c.x >= 80 or c.y < 0 or c.y >= 45:
		return true
	var t: int = fg[c.y][c.x]
	return t != 0 and t != 7

func _is_air(c: Vector2i) -> bool:
	if c.x < 0 or c.x >= 80 or c.y < 0 or c.y >= 45:
		return false
	return fg[c.y][c.x] == 0

func _edge_for_cell(c: Vector2i) -> int:
	# returns edge atlas index, or -1 for no overlay. Priority:
	# material transition, outer corner, edge, then inner corner (air
	# cells boxed in by solid on two perpendicular sides).
	if _is_solid_cell(c):
		# Phase 9: cells carrying real transition/corner tile art get NO
		# overlay — the art already is the boundary treatment, and the
		# dark wedge on top would double-darken it. Straight edges keep
		# the overlay (that is still the silhouette breaker there).
		if _fill_special(c) >= 0:
			return -1
		var own := _mat_group(fg[c.y][c.x])
		# Transition (ore cells exempt — an overlay on every ore cell
		# would darken the pickup itself): a solid neighbour of a
		# different material family
		# gets an edge overlay facing that neighbour (visual only —
		# no true transition tiles exist yet; this is the overlay
		# treatment, stated as such in the README).
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var nb: Vector2i = c + d
			if own != 2 and nb.x >= 0 and nb.x < 80 and nb.y >= 0 and nb.y < 45 and _is_solid_cell(nb) and _mat_group(fg[nb.y][nb.x]) != own:
				if d == Vector2i(0, -1): return 0
				if d == Vector2i(0, 1): return 1
				if d == Vector2i(-1, 0): return 2
				return 3
		var top := _is_air(c + Vector2i(0, -1))
		var bot := _is_air(c + Vector2i(0, 1))
		var left := _is_air(c + Vector2i(-1, 0))
		var right := _is_air(c + Vector2i(1, 0))
		if top and left: return 4
		if top and right: return 5
		if bot and left: return 6
		if bot and right: return 7
		if top: return 0
		if bot: return 1
		if left: return 2
		if right: return 3
		return -1
	# Air cell: inner corner where solid boxes it on two sides.
	if c.x < 0 or c.x >= 80 or c.y < 0 or c.y >= 45:
		return -1
	var stop := _is_solid_cell(c + Vector2i(0, -1))
	var sbot := _is_solid_cell(c + Vector2i(0, 1))
	var sleft := _is_solid_cell(c + Vector2i(-1, 0))
	var sright := _is_solid_cell(c + Vector2i(1, 0))
	if stop and sleft: return 4
	if stop and sright: return 5
	if sbot and sleft: return 6
	if sbot and sright: return 7
	return -1

func _update_edge(c: Vector2i) -> void:
	var e := _edge_for_cell(c)
	var l := _edge_layer_for(c)
	if e < 0:
		l.erase_cell(c)
	else:
		l.set_cell(c, 0, Vector2i(e, 0))

func _render_edges() -> void:
	for y in range(45):
		for x in range(80):
			_update_edge(Vector2i(x, y))

func _render_props() -> void:
	var spawn: Vector2i = data["spawn"]
	var exit_cell: Vector2i = data["exit"]
	# timber supports: one frame per room, at the room's side walls, visual only
	for r in data["rooms"]:
		var rx: int = r[0]; var ry: int = r[1]; var rw: int = r[2]; var rh: int = r[3]
		var floor_y: int = ry + rh - 1
		for side in [-1, 1]:
			var px: int = rx + (1 if side < 0 else rw - 2)
			var pc := Vector2i(px, floor_y - 1)
			if pc == spawn or pc == exit_cell:
				continue
			if fg[floor_y][px] == 0:
				continue  # post must stand on a solid floor cell
			var post := Sprite2D.new()
			post.texture = load("res://assets/atlas3/timber_post.png")
			post.scale = Vector2(128.0 / 766.0, 128.0 / 766.0)
			post.position = Vector2(px * TILE + 32, (floor_y - 2) * TILE + 64)
			post.z_index = 1
			_add_prop(post, pc)
			var occ := LightOccluder2D.new()
			var poly := OccluderPolygon2D.new()
			poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(12, 0),
				Vector2(12, TILE * 2), Vector2(0, TILE * 2)])
			occ.occluder = poly
			occ.position = Vector2(px * TILE + 15, (floor_y - 2) * TILE)
			# Phase 9: narrowed from 2.5x to 1.0x (12 px). The old 30 px
			# occluder threw a wide shadow wedge that darkened gameplay
			# area to the right of any torch; a 12 px post still reads
			# as a post shadow without hiding a hazard or enemy.
			occ.scale = Vector2(1.0, 1.0)
			_add_prop(occ, pc)
		# timber trestle prop, even rooms only, standing on the room floor.
		# Visual only, no collision; never on spawn/exit cells.
		var room_idx: int = data["rooms"].find(r)
		if room_idx % 2 == 0:
			var tx: int = rx + rw / 2
			var tc := Vector2i(tx, floor_y - 1)
			if tc != spawn and tc != exit_cell and fg[floor_y - 1][tx] == 0:
				var tres := Sprite2D.new()
				tres.texture = load("res://assets/atlas3/timber_trestle.png")
				tres.scale = Vector2(128.0 / 559.0, 128.0 / 559.0)
				tres.position = Vector2((tx + 0.5) * TILE, floor_y * TILE - 38)
				tres.z_index = 1
				_add_prop(tres, tc)
		# hanging roots from the ceiling, 2 per room, deterministic
		for k in range(2):
			var hx: int = rx + 2 + ((k * 5 + rw) % max(1, rw - 4))
			if fg[ry - 1][hx] == 0:
				continue  # root must hang from a solid ceiling cell
			var rc := Vector2i(hx, ry)
			if rc == spawn or rc == exit_cell:
				continue
			if fg[ry][hx] != 0:
				continue  # root hangs into air only
			if not _decor_ok(rc):
				continue  # variation budget: max 3 decor per 5x5 area
			var root := ColorRect.new()
			root.size = Vector2(4, 48 + (k * 16))
			root.position = Vector2(hx * TILE + 30, ry * TILE)
			root.color = Color(0.23, 0.18, 0.10, 1.0)
			root.z_index = 1
			_add_prop(root, rc)
		# floor debris: small dark speckles on the room floor, visual only
		for k in range(4):
			var dx: int = rx + 1 + ((k * 3 + rw) % max(1, rw - 2))
			var dc := Vector2i(dx, floor_y - 1)
			if dc == spawn or dc == exit_cell or fg[floor_y - 1][dx] != 0:
				continue
			if not _decor_ok(dc):
				continue  # variation budget
			var deb := ColorRect.new()
			deb.size = Vector2(10, 5)
			deb.position = Vector2(dx * TILE + 12 + k * 9, floor_y * TILE - 5)
			deb.color = Color(0.12, 0.12, 0.14, 1.0)
			deb.z_index = 1
			_add_prop(deb, dc)
	# Moss clusters (props): one cluster per room, 2-3 adjacent patches
	# on a floor top, never scattered singles, budget-checked.
	for ri in range(data["rooms"].size()):
		var r: Array = data["rooms"][ri]
		var rx2: int = r[0]; var rw2: int = r[2]; var fy2: int = r[1] + r[3] - 1
		var cx2: int = rx2 + 2 + ((ri * 7) % max(1, rw2 - 4))
		for k in range(3):
			var mx: int = cx2 + k
			if mx >= rx2 + rw2 - 1:
				break
			if fg[fy2][mx] == 0 or fg[fy2 - 1][mx] != 0:
				continue
			var mc := Vector2i(mx, fy2 - 1)
			if mc == spawn or mc == exit_cell or not _decor_ok(mc):
				continue
			var moss := ColorRect.new()
			moss.size = Vector2(20, 6)
			moss.position = Vector2(mx * TILE + 10 + k * 6, fy2 * TILE - 6)
			moss.color = Color(0.35, 0.60, 0.25, 1.0)
			moss.z_index = 1
			_add_prop(moss, mc)
	# crystal clusters: cyan diamond + light in an air cell beside an ore cell
	var ore_cells: Array = []
	for y in range(45):
		for x in range(80):
			if fg[y][x] == 4 or fg[y][x] == 5:
				ore_cells.append(Vector2i(x, y))
	for pick in [0, 7, 14]:
		if pick >= ore_cells.size():
			continue
		var oc: Vector2i = ore_cells[pick]
		var placed := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var ac: Vector2i = oc + d
			if _is_air(ac) and ac != spawn and ac != exit_cell:
				var dia := Polygon2D.new()
				dia.polygon = PackedVector2Array([Vector2(0, -14), Vector2(10, 0),
					Vector2(0, 14), Vector2(-10, 0)])
				dia.color = Color(0.5, 0.89, 0.94, 1.0)
				dia.position = Vector2((ac.x + 0.5) * TILE, (ac.y + 0.5) * TILE)
				dia.z_index = 1
				_add_prop(dia, ac)
				var cl := PointLight2D.new()
				cl.color = Color(0.5, 0.89, 0.94)
				cl.energy = 0.6
				cl.texture = _light_gradient_texture()
				cl.texture_scale = 192.0 / 448.0
				cl.shadow_enabled = false
				cl.position = dia.position
				_add_prop(cl, ac)
				_crystal_cells.append(ac)
				placed = true
				break
		if not placed:
			continue

func _process(delta: float) -> void:
	_time += delta
	_update_orbs(delta)
	_update_fx(delta)
	_update_parallax()
	mine_cooldown = max(0.0, mine_cooldown - delta)
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn_run()
	# Phase 8: while the class-select screen is up the world is frozen
	# for input (no mining / torch placing); HUD and lights keep running.
	if not _selecting:
		if Input.is_key_pressed(KEY_E) and mine_cooldown <= 0.0:
			_mine_at(player.cell() + Vector2i(player.facing, 0))
			mine_cooldown = 0.25
		if Input.is_key_pressed(KEY_T) and mine_cooldown <= 0.0:
			_place_torch()
			mine_cooldown = 0.25
		var tu: Node = get_node_or_null("TouchUI")
		var touch_mode: bool = tu != null and bool(tu.get("touch_used"))
		if not touch_mode and DisplayServer.is_touchscreen_available() == false:
			var md: Vector2 = get_global_mouse_position() - player.position
			var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			player.set_aim(md, lmb)
			if lmb and not (_craft_panel != null and _craft_panel.visible):
				aim_action(md.normalized(), true)
	# torch flicker: subtle, +-5%
	var i := 0
	for key in torches.keys():
		var light: PointLight2D = torches[key].get_node("Light")
		if light != null:
			light.energy = 1.0 + 0.05 * sin(_time * 5.0 + i * 1.7)
		i += 1
	for key in lanterns.keys():
		var llight: PointLight2D = lanterns[key].get_node("Light")
		if llight != null:
			llight.energy = 1.0 + 0.05 * sin(_time * 4.0 + i * 1.3)
		i += 1
	# Phase 10: hearts redraw on HP change, torch-light cull at 4 Hz.
	if _hearts != null:
		_hearts.queue_redraw()
	_light_cull_timer += delta
	if _light_cull_timer >= 0.25:
		_light_cull_timer = 0.0
		_update_torch_lights()
	var pc: Vector2i = player.cell()
	if pc == data["exit"] and not extracted:
		extracted = true
		print("DEEPFALL_EXTRACT_REACHED")
		if _cards_enabled:
			_card_pending = 0.4
			_card_reason = "extract"
	if extracted and not _extract_saved:
		_extract_saved = true
		save_game("extract")
	# Phase 6: autosave when the player enters a new stream chunk.
	if _world_ready:
		var sc := _stream_chunk_of(pc)
		if sc != _last_stream_chunk:
			_apply_chunk_visibility()
			save_game("chunk")
	var depth: int = max(0, pc.y)
	if not _selecting and not _card_open:
		_run_time += delta
		_max_depth = maxi(_max_depth, depth)
	if fx != null:
		fx.update_ambience(clampf(float(depth) / 44.0, 0.0, 1.0))
	if _card_pending > 0.0:
		_card_pending -= delta
		if _card_pending <= 0.0:
			show_run_card(_card_reason)
	var sc_now := _stream_chunk_of(pc)
	var save_note := ""
	if _save_note != "" and _time - _save_time < 3.0:
		save_note = "  |  " + _save_note
	# Phase 9 HUD fix: the old line 1 lost its final ")" and the hint
	# line ran off the right edge at 1280 px. Line 1 is now compact
	# (short labels, no "DEEPFALL |" prefix) at font 16, and the hint
	# lives on its own label (_hud2, font 14) — both measured in the
	# Phase 9 self-test and both fit inside 1264 px.
	hud.text = "Depth %d   Ore %d   Foes %d%s%s" % [
		depth, ore_collected, _foes_remaining(),
		"   EXTRACT!" if extracted else "", save_note]
	_update_aim_reticle(delta)
	if _hud2 != null:
		# Phase 10: hint line trimmed to fit < 1248 px at font 14
		# (the Phase 9 line plus "Q tool" and the new touch buttons
		# ran to 1589 px). F5 save / F9 new stay in the README; the
		# SAVE/NEW buttons are visible on screen.
		_hud2.text = "A/D move  Space jump  Shift dash  F slam  Mouse aim + hold LMB attack/mine  J attack%s  Q tool  T torch  L lantern  B bench  C craft" % [
			" (orb bolt)" if player.ranged else ""]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Phase 8: class select keys (desktop) — 1/2/3 pick directly,
		# Left/Right move the highlight, Enter confirms it.
		if _selecting:
			if event.keycode == KEY_1:
				_pick_class("tech")
			elif event.keycode == KEY_2:
				_pick_class("red")
			elif event.keycode == KEY_3:
				_pick_class("mage")
			elif event.keycode == KEY_LEFT:
				_highlight_class((_class_index + 2) % 3)
			elif event.keycode == KEY_RIGHT:
				_highlight_class((_class_index + 1) % 3)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_pick_class(["tech", "red", "mage"][_class_index])
			return
		if event.keycode == KEY_F5:
			save_game("manual")
		elif event.keycode == KEY_F9:
			new_run()
		elif event.keycode == KEY_C:
			_toggle_craft_panel()
		elif event.keycode == KEY_L:
			_place_lantern()
		elif event.keycode == KEY_B:
			_place_workbench()
		# Phase 10: tool selection — Q toggles, 1 = pickaxe, 2 = sword.
		# (While class-select is up these keys pick classes instead;
		# that branch returns above, so no clash.)
		elif event.keycode == KEY_Q:
			cycle_tool()
		elif event.keycode == KEY_SHIFT:
			player.try_dash()
		elif event.keycode == KEY_F:
			player.try_slam()
		elif event.keycode == KEY_1:
			set_tool("pickaxe")
		elif event.keycode == KEY_2:
			set_tool("sword")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return  # Phase 11: touches are handled by touch_ui (sticks / buttons)
		if _selecting:
			return  # clicks on the select screen go to its buttons only
		if _craft_panel != null and _craft_panel.visible and _craft_panel.get_global_rect().has_point(event.position):
			return  # click landed on the crafting panel, not the world
		var cell := Vector2i(int(floor(get_global_mouse_position().x / TILE)),
			int(floor(get_global_mouse_position().y / TILE)))
		if torches.has(cell):
			_pickup_torch(cell)
		elif lanterns.has(cell):
			_pickup_lantern(cell)
		elif workbenches.has(cell):
			_pickup_workbench(cell)
		else:
			aim_action((get_global_mouse_position() - player.position).normalized(), true)

func _mine_at(cell: Vector2i, via_stick := false) -> void:
	if cell.x < 0 or cell.x >= 80 or cell.y < 0 or cell.y >= 45:
		return
	var t: int = fg[cell.y][cell.x]
	# Phase 10: mining and attacking are separated by the equipped
	# tool. Sword cannot mine: E / click shows the log note (never a
	# silent fail); the right stick swings the sword instead. Air /
	# platform cells with the sword via the stick also swing (attacking
	# the air in that direction); E / click on air does nothing.
	if t == 0 or t == 7:
		if tool == "sword" and via_stick:
			_face_cell(cell)
			player.call("try_attack")
		return
	if tool != "pickaxe":
		if via_stick:
			_face_cell(cell)
			player.call("try_attack")
		else:
			log_event("Need pickaxe to mine")
		return
	# Pickaxe: unchanged 2-hit + crack behaviour, but the mining swing
	# plays the melee animation now (not the shoot animation).
	player.call("trigger_melee")
	_face_cell(cell)
	var cpos := Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
	if fx != null:
		fx.burst(cpos, _tile_color(t), 7 if mine_damage.has(cell) else 5, 280.0)
		fx.shake(2.5)
		fx.sfx("mine_hit", 0.12)
	# damaged state first: crack overlay, block survives one hit.
	# Phase 6: the crack is an edit delta, saved with the run.
	if not mine_damage.has(cell):
		mine_damage[cell] = 1
		_damage_layer_for(cell).set_cell(cell, 0, Vector2i(0, 0))
		save_game("mine")
		return
	mine_damage.erase(cell)
	_damage_layer_for(cell).erase_cell(cell)
	fg[cell.y][cell.x] = 0
	_mined_cells[cell] = true
	_fg_layer_for(cell).erase_cell(cell)
	_edge_layer_for(cell).erase_cell(cell)
	player.fg = fg
	_grant_material(t)
	if fx != null:
		fx.burst(cpos, _tile_color(t), 16, 360.0, 1400.0, 8.0)
		fx.flyer(cpos, _tile_color(t), "+1 %s" % _material_name(t))
		fx.shake(4.0)
		fx.sfx("mine_break", 0.1)
		fx.rumble(20)
	if t == 4 or t == 5:
		ore_collected += 1
		last_ore_name = "Gold ore" if t == 4 else "Amber ore"
		print("DEEPFALL_ORE_COLLECTED type=%d name=%s total=%d" % [t, last_ore_name, ore_collected])
		log_event("Picked up %s" % last_ore_name)
	# re-tile neighbours (edges AND fills change when a cell opens: a
	# neighbour can gain or lose transition/corner art from this mine)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		_set_fill_cell(cell + d)
		_update_edge(cell + d)
	for key in torches.keys():
		var sup: Vector2i = torches[key].get_meta("support")
		if sup == cell:
			_pickup_torch(key)
	for key in lanterns.keys():
		var lsup: Vector2i = lanterns[key].get_meta("support")
		if lsup == cell:
			_pickup_lantern(key)
	for key in workbenches.keys():
		var wfloor: Vector2i = workbenches[key].get_meta("floor")
		if wfloor == cell:
			_pickup_workbench(key)
	save_game("mine")

var _light_tex: Texture2D = null

func _light_gradient_texture() -> Texture2D:
	# white radial falloff; PointLight2D colours it. Kept as the light
	# texture (the old gradient *sprite* glow is gone — lights are real).
	if _light_tex != null:
		return _light_tex
	var size := TORCH_RADIUS_TILES * TILE * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx := size / 2.0
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(Vector2(cx, cx)) / cx
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			# Phase 9 diagnosis (see README): the old squared falloff
			# (a*a) made the outer ring too dim to see against the
			# ambient tint, so the 7-tile texture read as a ~4-tile pool.
			# pow 1.25 keeps a soft edge but roughly doubles the brightness
			# at 4 tiles (0.18 -> 0.35) — measured in the Phase 9 notes.
			a = pow(a, 1.25)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_light_tex = ImageTexture.create_from_image(img)
	return _light_tex

func _place_torch_at(cell: Vector2i, support: Vector2i) -> bool:
	if torches.has(cell):
		return false
	if cell.x < 0 or cell.x >= 80 or cell.y < 0 or cell.y >= 45:
		return false
	if fg[cell.y][cell.x] != 0:
		return false
	if not _is_solid_cell(support):
		return false
	var torch := Node2D.new()
	torch.position = Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
	torch.set_meta("support", support)
	var light := PointLight2D.new()
	light.name = "Light"
	light.color = Color(1.0, 0.70, 0.36)
	light.energy = 1.0
	light.texture = _light_gradient_texture()
	light.texture_scale = 1.0  # gradient texture is already 7 tiles wide
	light.shadow_enabled = true  # selective occluders: timber props only
	torch.add_child(light)
	# Phase 10 perf: cheap gradient-glow fallback. Hidden while the
	# real light is on; shown when the light cull disables this torch
	# (see _update_torch_lights), so the room never goes dark.
	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = _light_gradient_texture()
	glow.modulate = Color(1.0, 0.70, 0.36, 0.55)
	glow.scale = Vector2(0.45, 0.45)
	glow.visible = false
	torch.add_child(glow)
	var stick := Sprite2D.new()
	stick.texture = load("res://assets/torch.png")
	stick.scale = Vector2(0.08, 0.08)
	stick.centered = true
	torch.add_child(stick)
	add_child(torch)
	torches[cell] = torch
	return true

func _try_place_torch_here() -> Vector2i:
	# First valid candidate wins; returns the placed cell or (-1, -1).
	# Decrements torches_held on success (restore path calls
	# _place_torch_at directly instead, so held count is not double-cut).
	if torches_held <= 0:
		return Vector2i(-1, -1)
	var base: Vector2i = player.cell()
	var candidates: Array = [
		{"cell": Vector2i(base.x + player.facing, base.y), "support": Vector2i(base.x + player.facing, base.y + 1)},
		{"cell": Vector2i(base.x, base.y - 1), "support": Vector2i(base.x, base.y)},
		{"cell": Vector2i(base.x + player.facing, base.y - 1), "support": Vector2i(base.x + player.facing, base.y)},
	]
	for cand in candidates:
		var cell: Vector2i = cand["cell"]
		if _place_torch_at(cell, cand["support"]):
			torches_held -= 1
			print("DEEPFALL_TORCH_PLACED cell=%s held=%d" % [str(cell), torches_held])
			return cell
	return Vector2i(-1, -1)

func _place_torch() -> void:
	var placed := _try_place_torch_here()
	if placed.x >= 0:
		log_event("Placed torch")
		save_game("torch")

func _pickup_torch(cell: Vector2i) -> void:
	var torch: Node2D = torches[cell]
	torch.queue_free()
	torches.erase(cell)
	torches_held += 1
	print("DEEPFALL_TORCH_PICKED_UP cell=%s held=%d" % [str(cell), torches_held])
	log_event("Picked up torch")
	save_game("torch")

# --- Phase 7: crafting + inventory ---

# Iron-plate decision (documented in the README): the staged iron-ore
# tile is visually indistinguishable from copper-ore (mean RGB
# 117,97,89 vs 126,105,95), the same reason iron was fenced out in
# Phase 2. So the lantern does NOT use an iron plate in this phase:
# it uses 1 gold ore instead (gold is visually distinct and already
# mined in the Forgotten Mines). The locked iron-plate recipe stays
# locked until iron is distinguishable — the lantern is craftable now,
# with the substitution stated plainly, not silently.
const RECIPES := {
	"torch": {"name": "Torch", "cost": {"wood": 1, "coal": 1}, "station": "hand",
		"desc": "1 wood + 1 coal — hand — light 7 tiles"},
	"glass": {"name": "Glass block", "cost": {"sand": 2}, "station": "hand",
		"desc": "2 sand — hand — lantern ingredient"},
	"workbench": {"name": "Workbench", "cost": {"wood": 4}, "station": "hand",
		"desc": "4 wood — hand — floor prop, craft lanterns near it"},
	"lantern": {"name": "Lantern", "cost": {"gold": 1, "glass": 1, "torch": 1}, "station": "workbench",
		"desc": "1 gold ore + 1 glass + 1 torch — WORKBENCH — light 10 tiles"},
}
const LANTERN_RADIUS_TILES := 10
const WORKBENCH_RANGE := 3

var _craft_panel: PanelContainer = null
var _craft_status: Label = null
var _craft_buttons: Dictionary = {}
var _place_buttons: Dictionary = {}

func _grant_material(t: int) -> void:
	# Mining yields, by tile id. Wood-platform (7) is never mined (the
	# _mine_at early return), so it never gives wood — only solid wood
	# blocks (6) do. Brick / mossy / cracked / obsidian read as stone.
	match t:
		1, 2:
			inv["dirt"] += 1
		3, 8, 9, 10, 12:
			inv["stone"] += 1
		4:
			inv["gold"] += 1
		5:
			inv["amber"] += 1
		6:
			inv["wood"] += 1
		11:
			inv["sand"] += 1
		13:
			inv["coal"] += 1
			last_ore_name = "Coal ore"
			print("DEEPFALL_ORE_COLLECTED type=13 name=Coal ore coal=%d" % int(inv["coal"]))
			log_event("Picked up Coal ore")

func _grant_enemy_drop(enemy: Node2D) -> void:
	# Small deterministic drop table, seed-determined via spawn_id
	# (never the global RNG, so the same run always drops the same).
	# Phase 13: drops are physical pickups that bounce out of the body
	# (loot_drop.gd); the inventory is credited when collected.
	var drops: Array = []
	match enemy.slug:
		"cave-bat-swarm":
			print("DEEPFALL_DROP slug=%s item=none" % enemy.slug)
		"rock-golem":
			drops = [["stone", 1], ["stone", 1], ["amber", 1]] if enemy.spawn_id >= 0 and enemy.spawn_id % 3 == 0 else [["stone", 1], ["stone", 1]]
			print("DEEPFALL_DROP slug=%s item=stone n=2" % enemy.slug)
		"ore-mimic":
			drops = [["gold", 1], ["gold", 1], ["stone", 1]]
			print("DEEPFALL_DROP slug=%s item=gold n=2" % enemy.slug)
		_:
			if enemy.spawn_id >= 0 and enemy.spawn_id % 2 == 0:
				drops = [["coal", 1]]
				print("DEEPFALL_DROP slug=%s item=coal n=1" % enemy.slug)
			else:
				drops = [["stone", 1]]
				print("DEEPFALL_DROP slug=%s item=stone n=1" % enemy.slug)
	for dspec in drops:
		var ld: Node2D = LOOT_SCRIPT.new()
		ld.setup(String(dspec[0]), int(dspec[1]), self)
		ld.position = enemy.position + Vector2(0, -10)
		add_child(ld)

func collect_loot(drop: Node2D) -> void:
	inv[drop.item] = int(inv.get(drop.item, 0)) + drop.amount
	if fx != null:
		fx.sfx("pickup", 0.12)
		fx.float_text(player.position + Vector2(0, -60), "+%d %s" % [drop.amount, String(drop.item).capitalize()], Color(1, 0.95, 0.7))
	print("DEEPFALL_LOOT_COLLECTED item=%s n=%d total=%d" % [drop.item, drop.amount, int(inv[drop.item])])

func spawn_enemy_corpse(e: Node2D) -> void:
	var c: Node2D = CORPSE_SCRIPT.new()
	c.setup(String(e.slug), self, int(e.facing), e.vel, float(e.half_h))
	c.position = e.position
	add_child(c)

func _near_workbench() -> bool:
	var pc: Vector2i = player.cell()
	for key in workbenches.keys():
		var d: Vector2i = (key as Vector2i) - pc
		if maxi(absi(d.x), absi(d.y)) <= WORKBENCH_RANGE:
			return true
	return false

func _can_craft(rid: String) -> bool:
	var r: Dictionary = RECIPES[rid]
	if String(r["station"]) == "workbench" and not _near_workbench():
		return false
	for k in (r["cost"] as Dictionary).keys():
		var need: int = int((r["cost"] as Dictionary)[k])
		var have: int = torches_held if k == "torch" else int(inv.get(k, 0))
		if have < need:
			return false
	return true

func _craft(rid: String) -> bool:
	var r: Dictionary = RECIPES[rid]
	if String(r["station"]) == "workbench" and not _near_workbench():
		_set_craft_status("Lantern needs a workbench within %d tiles — place one with B first." % WORKBENCH_RANGE)
		print("DEEPFALL_CRAFT_FAIL id=%s reason=needs_workbench" % rid)
		return false
	for k in (r["cost"] as Dictionary).keys():
		var need: int = int((r["cost"] as Dictionary)[k])
		var have: int = torches_held if k == "torch" else int(inv.get(k, 0))
		if have < need:
			_set_craft_status("Need %d %s for %s." % [need, k, String(r["name"])])
			print("DEEPFALL_CRAFT_FAIL id=%s reason=missing_%s" % [rid, k])
			return false
	for k in (r["cost"] as Dictionary).keys():
		var need2: int = int((r["cost"] as Dictionary)[k])
		if k == "torch":
			torches_held -= need2
		else:
			inv[k] = int(inv[k]) - need2
	match rid:
		"torch":
			torches_held += 1
		"glass":
			inv["glass"] += 1
		"workbench":
			inv["workbench"] += 1
		"lantern":
			inv["lantern"] += 1
	_set_craft_status("Crafted %s." % String(r["name"]))
	print("DEEPFALL_CRAFTED id=%s inv=%s torches=%d" % [rid, str(inv), torches_held])
	save_game("craft")
	_refresh_craft_panel()
	return true

func _set_craft_status(msg: String) -> void:
	if _craft_status != null:
		_craft_status.text = msg
	# Phase 10: crafting results also land in the message log line.
	log_event(msg)

# --- Phase 7: lantern placement (separate item layer, like torches) ---

func _place_lantern_at(cell: Vector2i, support: Vector2i) -> bool:
	if lanterns.has(cell):
		return false
	if cell.x < 0 or cell.x >= 80 or cell.y < 0 or cell.y >= 45:
		return false
	if fg[cell.y][cell.x] != 0:
		return false
	if not _is_solid_cell(support):
		return false
	var lan := Node2D.new()
	lan.position = Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)
	lan.set_meta("support", support)
	var light := PointLight2D.new()
	light.name = "Light"
	light.color = Color(1.0, 0.78, 0.45)
	light.energy = 1.0
	light.texture = _light_gradient_texture()
	light.texture_scale = LANTERN_RADIUS_TILES * TILE / 448.0
	light.shadow_enabled = false
	lan.add_child(light)
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/items/lantern-64.png")
	spr.centered = true
	lan.add_child(spr)
	add_child(lan)
	lanterns[cell] = lan
	return true

func _place_lantern() -> void:
	if int(inv["lantern"]) <= 0:
		_set_craft_status("No lanterns to place — craft one at a workbench (C).")
		print("DEEPFALL_LANTERN_NONE")
		return
	var base: Vector2i = player.cell()
	var candidates: Array = [
		{"cell": base, "support": Vector2i(base.x, base.y - 1)},
		{"cell": base, "support": Vector2i(base.x, base.y + 1)},
		{"cell": Vector2i(base.x + player.facing, base.y), "support": Vector2i(base.x + player.facing, base.y - 1)},
		{"cell": Vector2i(base.x + player.facing, base.y), "support": Vector2i(base.x + player.facing, base.y + 1)},
	]
	for cand in candidates:
		var cell: Vector2i = cand["cell"]
		if _place_lantern_at(cell, cand["support"]):
			inv["lantern"] -= 1
			print("DEEPFALL_LANTERN_PLACED cell=%s held=%d" % [str(cell), int(inv["lantern"])])
			log_event("Placed lantern")
			save_game("lantern")
			_refresh_craft_panel()
			return
	_set_craft_status("No place to hang/set a lantern here — need solid above or below.")
	print("DEEPFALL_LANTERN_NOSPACE")

func _pickup_lantern(cell: Vector2i) -> void:
	var lan: Node2D = lanterns[cell]
	lan.queue_free()
	lanterns.erase(cell)
	inv["lantern"] += 1
	print("DEEPFALL_LANTERN_PICKED_UP cell=%s held=%d" % [str(cell), int(inv["lantern"])])
	save_game("lantern")

# --- Phase 7: workbench placement (floor prop, no collision) ---

func _place_workbench_at(cell: Vector2i, floor_cell: Vector2i) -> bool:
	if workbenches.has(cell):
		return false
	if cell.x < 0 or cell.x >= 80 or cell.y < 0 or cell.y >= 45:
		return false
	if fg[cell.y][cell.x] != 0:
		return false
	if not _is_solid_cell(floor_cell):
		return false
	var bench := Node2D.new()
	bench.position = Vector2(cell.x * TILE, (cell.y + 1) * TILE)
	bench.set_meta("floor", floor_cell)
	var bspr := Sprite2D.new()
	bspr.texture = load("res://assets/hero/props/workbench.png")
	bspr.centered = false
	bspr.scale = Vector2(4, 4)
	bspr.position = Vector2(0, -52)
	bench.add_child(bspr)
	add_child(bench)
	workbenches[cell] = bench
	return true

func _place_workbench() -> void:
	if int(inv["workbench"]) <= 0:
		_set_craft_status("No workbenches to place — craft one with 4 wood (C).")
		print("DEEPFALL_WORKBENCH_NONE")
		return
	var base: Vector2i = player.cell()
	for cx in [base.x, base.x + player.facing, base.x - player.facing]:
		var cell := Vector2i(cx, base.y)
		if _place_workbench_at(cell, Vector2i(cx, base.y + 1)):
			inv["workbench"] -= 1
			print("DEEPFALL_WORKBENCH_PLACED cell=%s held=%d" % [str(cell), int(inv["workbench"])])
			log_event("Placed workbench")
			save_game("workbench")
			_refresh_craft_panel()
			return
	_set_craft_status("No floor to place a workbench on here.")
	print("DEEPFALL_WORKBENCH_NOSPACE")

func _pickup_workbench(cell: Vector2i) -> void:
	var bench: Node2D = workbenches[cell]
	bench.queue_free()
	workbenches.erase(cell)
	inv["workbench"] += 1
	print("DEEPFALL_WORKBENCH_PICKED_UP cell=%s held=%d" % [str(cell), int(inv["workbench"])])
	save_game("workbench")

# --- Phase 7: crafting panel (pauses nothing — the game keeps running) ---

func _build_craft_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_top = -200
	panel.offset_right = 280
	panel.offset_bottom = 200
	panel.visible = false
	panel.name = "CraftPanel"
	$HUD.add_child(panel)
	_craft_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "CRAFTING  (game keeps running — C to close)"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	_craft_status = Label.new()
	_craft_status.text = "Torch: 1 wood + 1 coal. Lantern needs a workbench nearby."
	_craft_status.add_theme_font_size_override("font_size", 16)
	vb.add_child(_craft_status)
	for rid in ["torch", "glass", "workbench", "lantern"]:
		var r: Dictionary = RECIPES[rid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var lab := Label.new()
		lab.text = "%s — %s" % [String(r["name"]), String(r["desc"])]
		lab.add_theme_font_size_override("font_size", 16)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b := Button.new()
		b.text = "Craft"
		b.custom_minimum_size = Vector2(90, 36)
		b.pressed.connect(_craft.bind(rid))
		row.add_child(b)
		_craft_buttons[rid] = b
	var place_row := HBoxContainer.new()
	place_row.add_theme_constant_override("separation", 10)
	vb.add_child(place_row)
	var place_lab := Label.new()
	place_lab.text = "Place:"
	place_lab.add_theme_font_size_override("font_size", 16)
	place_row.add_child(place_lab)
	for kind in ["torch", "lantern", "workbench"]:
		var pb := Button.new()
		pb.text = kind.capitalize()
		pb.custom_minimum_size = Vector2(110, 36)
		if kind == "torch":
			pb.pressed.connect(_place_torch)
		elif kind == "lantern":
			pb.pressed.connect(_place_lantern)
		else:
			pb.pressed.connect(_place_workbench)
		place_row.add_child(pb)
		_place_buttons[kind] = pb
	var close_b := Button.new()
	close_b.text = "Close (C)"
	close_b.custom_minimum_size = Vector2(120, 36)
	close_b.pressed.connect(_show_craft_panel.bind(false))
	vb.add_child(close_b)
	_refresh_craft_panel()

func _refresh_craft_panel() -> void:
	if _craft_panel == null:
		return
	for rid in _craft_buttons.keys():
		var b: Button = _craft_buttons[rid]
		b.disabled = not _can_craft(rid)
		var r: Dictionary = RECIPES[rid]
		b.text = "Craft" if _can_craft(rid) else "Craft (need)"
		if String(r["station"]) == "workbench" and not _near_workbench():
			b.text = "Craft (bench?)"
	(_place_buttons["torch"] as Button).text = "Torch (%d)" % torches_held
	(_place_buttons["lantern"] as Button).text = "Lantern (%d)" % int(inv["lantern"])
	(_place_buttons["workbench"] as Button).text = "Workbench (%d)" % int(inv["workbench"])
	(_place_buttons["torch"] as Button).disabled = torches_held <= 0
	(_place_buttons["lantern"] as Button).disabled = int(inv["lantern"]) <= 0
	(_place_buttons["workbench"] as Button).disabled = int(inv["workbench"]) <= 0

func _show_craft_panel(open: bool) -> void:
	if _craft_panel == null:
		return
	_craft_panel.visible = open
	if open:
		_refresh_craft_panel()
		print("DEEPFALL_CRAFT_OPEN")

func _toggle_craft_panel() -> void:
	if _craft_panel == null:
		return
	_show_craft_panel(not _craft_panel.visible)

# --- Phase 8: class select (three starting classes, no skeleton hero) ---

const CLASS_CARDS := [
	{"id": "tech", "name": "Tech Soldier",
		"desc": "Balanced all-rounder. Sword and pickaxe, steady and quick.",
		"stats": "HP 100  |  Sword 15  |  Speed normal"},
	{"id": "red", "name": "Red Soldier",
		"desc": "Heavy hitter. Slower, hits harder, takes more punishment.",
		"stats": "HP 120  |  Sword 20  |  Speed slower"},
	{"id": "mage", "name": "Hooded Mage",
		"desc": "Fragile caster. The staff fires an orb bolt wherever you aim.",
		"stats": "HP 80  |  Staff orb 12 (aimed)  |  Speed normal"},
]

func _class_idle_texture(id: String) -> Texture2D:
	# Phase 11: the pixel paper-doll preview (build_pixel_hero.py)
	return load("res://assets/hero/%s/preview.png" % id)

func _build_class_select() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560
	panel.offset_top = -260
	panel.offset_right = 560
	panel.offset_bottom = 260
	panel.visible = false
	panel.name = "ClassSelectPanel"
	$HUD.add_child(panel)
	_class_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "DEEPFALL — CHOOSE YOUR CLASS"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "Tap PLAY on a card  (desktop: 1 / 2 / 3, or Left / Right + Enter)"
	hint.add_theme_font_size_override("font_size", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_class_cards.clear()
	for i in range(CLASS_CARDS.size()):
		var card: Dictionary = CLASS_CARDS[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.custom_minimum_size = Vector2(340, 380)
		row.add_child(cell)
		var pic := TextureRect.new()
		pic.texture = _class_idle_texture(String(card["id"]))
		pic.custom_minimum_size = Vector2(128, 195)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(pic)
		var name_lab := Label.new()
		name_lab.text = "%d. %s" % [i + 1, String(card["name"])]
		name_lab.add_theme_font_size_override("font_size", 20)
		name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_lab)
		var desc_lab := Label.new()
		desc_lab.text = String(card["desc"])
		desc_lab.add_theme_font_size_override("font_size", 15)
		desc_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(desc_lab)
		var stats_lab := Label.new()
		stats_lab.text = String(card["stats"])
		stats_lab.add_theme_font_size_override("font_size", 14)
		stats_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(stats_lab)
		var b := Button.new()
		b.text = "PLAY"
		b.custom_minimum_size = Vector2(160, 44)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_pick_class.bind(String(card["id"])))
		cell.add_child(b)
		_class_cards.append({"id": String(card["id"]), "button": b, "cell": cell})
	_highlight_class(0)

func _highlight_class(i: int) -> void:
	_class_index = clampi(i, 0, _class_cards.size() - 1)
	for k in range(_class_cards.size()):
		var cell: VBoxContainer = _class_cards[k]["cell"]
		cell.modulate = Color(1, 1, 1, 1) if k == _class_index else Color(0.75, 0.75, 0.75, 1)
	var b: Button = _class_cards[_class_index]["button"]
	b.grab_focus()

func _show_class_select(open: bool) -> void:
	if _class_panel == null:
		return
	_class_panel.visible = open
	_selecting = open
	if open:
		_highlight_class(0)
		player.set_physics_process(false)
		print("DEEPFALL_CLASS_SELECT_SHOWN")
	else:
		player.set_physics_process(true)

func _pick_class(id: String) -> void:
	if not _selecting and id == player.class_id:
		return
	player.set_class(id)
	_show_class_select(false)
	save_game("class")
	print("DEEPFALL_CLASS_PICKED id=%s" % id)

# --- Phase 7 self-test ---

func _find_tile_cell(tid: int, exclude: Array = []) -> Vector2i:
	for y in range(45):
		for x in range(80):
			if fg[y][x] == tid and not exclude.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _mine_cell_twice(cell: Vector2i) -> void:
	_mine_at(cell)
	_mine_at(cell)

func _run_selftest_phase7() -> void:
	print("DEEPFALL_SELFTEST_PHASE7 start")
	var ok := true
	# (a) Mining gives the right materials (deltas, not absolutes —
	# Phase 6 already mined one cell into the inventory).
	var coal_cell := _find_tile_cell(13)
	var wood_cell := _find_tile_cell(6)
	var sand_cell := _find_tile_cell(11)
	var gold_cell := _find_tile_cell(4)
	print("DEEPFALL_SELFTEST_PHASE7 cells coal=%s wood=%s sand=%s gold=%s" % [
		str(coal_cell), str(wood_cell), str(sand_cell), str(gold_cell)])
	if coal_cell.x < 0 or wood_cell.x < 0 or sand_cell.x < 0 or gold_cell.x < 0:
		print("DEEPFALL_SELFTEST_PHASE7 FAIL missing material cell")
		return
	var before := inv.duplicate()
	_mine_cell_twice(coal_cell)
	_mine_cell_twice(wood_cell)
	_mine_cell_twice(sand_cell)
	_mine_cell_twice(gold_cell)
	var d_coal: int = int(inv["coal"]) - int(before["coal"])
	var d_wood: int = int(inv["wood"]) - int(before["wood"])
	var d_sand: int = int(inv["sand"]) - int(before["sand"])
	var d_gold: int = int(inv["gold"]) - int(before["gold"])
	print("DEEPFALL_SELFTEST_PHASE7 a mined coal+%d wood+%d sand+%d gold+%d (expect 1,1,1,1)" % [d_coal, d_wood, d_sand, d_gold])
	if d_coal != 1 or d_wood != 1 or d_sand != 1 or d_gold != 1:
		ok = false
	# (b) Torch crafting consumes 1 wood + 1 coal, adds a torch.
	var t_before := torches_held
	var w_before: int = int(inv["wood"])
	var c_before: int = int(inv["coal"])
	var torch_ok: bool = _craft("torch")
	print("DEEPFALL_SELFTEST_PHASE7 b torch craft=%s torches %d->%d wood %d->%d coal %d->%d (expect true, +1, -1, -1)" % [
		str(torch_ok), t_before, torches_held, w_before, int(inv["wood"]), c_before, int(inv["coal"])])
	if not torch_ok or torches_held != t_before + 1 or int(inv["wood"]) != w_before - 1 or int(inv["coal"]) != c_before - 1:
		ok = false
	# Glass sub-recipe: mine one more sand cell, craft glass from 2 sand.
	var sand2 := _find_tile_cell(11)
	_mine_cell_twice(sand2)
	var glass_ok: bool = _craft("glass")
	print("DEEPFALL_SELFTEST_PHASE7 b2 glass craft=%s glass=%d sand=%d (expect true, 1, 0)" % [
		str(glass_ok), int(inv["glass"]), int(inv["sand"])])
	if not glass_ok or int(inv["glass"]) != 1:
		ok = false
	# (c) Lantern fails without a workbench, succeeds near one.
	var lan_before: int = int(inv["lantern"])
	var lan_fail: bool = _craft("lantern")
	print("DEEPFALL_SELFTEST_PHASE7 c lantern without bench craft=%s lantern=%d (expect false, %d)" % [
		str(lan_fail), int(inv["lantern"]), lan_before])
	if lan_fail or int(inv["lantern"]) != lan_before:
		ok = false
	# Mine wood until we can afford the 4-wood workbench.
	var mined_wood: Array = [wood_cell]
	while int(inv["wood"]) < 4:
		var wc := _find_tile_cell(6, mined_wood)
		if wc.x < 0:
			break
		mined_wood.append(wc)
		_mine_cell_twice(wc)
	var bench_ok: bool = _craft("workbench")
	print("DEEPFALL_SELFTEST_PHASE7 c2 workbench craft=%s held=%d wood=%d (expect true, 1, 0)" % [
		str(bench_ok), int(inv["workbench"]), int(inv["wood"])])
	if not bench_ok or int(inv["workbench"]) != 1:
		ok = false
	var spawn: Vector2i = data["spawn"]
	player.position = Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	_place_workbench()
	var bench_placed: bool = workbenches.size() == 1
	print("DEEPFALL_SELFTEST_PHASE7 c3 workbench placed=%s near=%s (expect true, true)" % [
		str(bench_placed), str(_near_workbench())])
	if not bench_placed or not _near_workbench():
		ok = false
	var lan_ok: bool = _craft("lantern")
	print("DEEPFALL_SELFTEST_PHASE7 c4 lantern near bench craft=%s lantern=%d gold=%d glass=%d torches=%d (expect true, 1, 0, 0, %d)" % [
		str(lan_ok), int(inv["lantern"]), int(inv["gold"]), int(inv["glass"]), torches_held, t_before])
	if not lan_ok or int(inv["lantern"]) != 1:
		ok = false
	# Place the lantern one cell right of spawn, then save/rebuild/load.
	player.position = Vector2((spawn.x + 1.5) * TILE, (spawn.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	_place_lantern()
	var lan_cell := Vector2i(-1, -1)
	for key in lanterns.keys():
		lan_cell = key
	var bench_cell := Vector2i(-1, -1)
	for key in workbenches.keys():
		bench_cell = key
	print("DEEPFALL_SELFTEST_PHASE7 d lantern placed cell=%s bench cell=%s (expect both valid)" % [str(lan_cell), str(bench_cell)])
	if lan_cell.x < 0 or bench_cell.x < 0:
		ok = false
	# (d) Inventory + placed lantern survive save -> rebuild -> load.
	var inv_before: Dictionary = inv.duplicate()
	var torches_before: int = torches_held
	save_game("selftest7")
	_rebuild_world(true)
	var inv_same: bool = true
	for k in inv.keys():
		if int(inv[k]) != int(inv_before[k]):
			inv_same = false
			print("DEEPFALL_SELFTEST_PHASE7 d FAIL inv %s before=%s after=%s" % [k, str(inv_before[k]), str(inv[k])])
	var lan_same: bool = lan_cell.x >= 0 and lanterns.has(lan_cell)
	var bench_same: bool = bench_cell.x >= 0 and workbenches.has(bench_cell)
	print("DEEPFALL_SELFTEST_PHASE7 d reload inv_same=%s lantern_restored=%s workbench_restored=%s torches=%d (expect true, true, true, %d)" % [
		str(inv_same), str(lan_same), str(bench_same), torches_held, torches_before])
	if not inv_same or not lan_same or not bench_same or torches_held != torches_before:
		ok = false
	save_game("selftest7")
	print("DEEPFALL_SELFTEST_PHASE7 done PASS=%s" % str(ok))

# --- Phase 8 self-test: classes, orb, class save/load ---

func _run_selftest_phase8() -> void:
	print("DEEPFALL_SELFTEST_PHASE8 start")
	var ok := true
	# (a) Each class loads its own frames (no tech frames leaking into
	# red/mage) and its own stats.
	var expect := {
		"tech": {"hp": 100, "melee": 15, "speed": 1.0, "ranged": false,
			"idle": 9, "shoot": 5, "walkcycle": 4},
		"red": {"hp": 120, "melee": 20, "speed": 0.9, "ranged": false,
			"idle": 9, "shoot": 5, "walkcycle": 4},
		"mage": {"hp": 80, "melee": 10, "speed": 1.0, "ranged": true,
			"idle": 7, "shoot": 5, "walkcycle": 4},
	}
	for cid in ["tech", "red", "mage"]:
		player.set_class(cid)
		var e: Dictionary = expect[cid]
		var idle_path: String = (player.get("_anim_idle")[0] as Texture2D).resource_path
		var shoot_path: String = (player.get("_anim_shoot")[0] as Texture2D).resource_path
		var walk_path: String = (player.get("_anim_walkcycle")[0] as Texture2D).resource_path
		var leak := false
		if cid == "tech":
			leak = idle_path.contains("/red/") or idle_path.contains("/mage/")
		else:
			leak = not idle_path.contains("/%s/" % cid) \
				or not shoot_path.contains("/%s/" % cid) \
				or not walk_path.contains("/%s/" % cid)
		var stats_ok: bool = player.max_hp == int(e["hp"]) \
			and player.melee_dmg == int(e["melee"]) \
			and is_equal_approx(player.speed_mult, float(e["speed"])) \
			and player.ranged == bool(e["ranged"])
		var counts_ok: bool = player.get("_anim_idle").size() == int(e["idle"]) \
			and player.get("_anim_shoot").size() == int(e["shoot"]) \
			and player.get("_anim_walkcycle").size() == int(e["walkcycle"])
		print("DEEPFALL_SELFTEST_PHASE8 a class=%s hp=%d melee=%d speed=%.2f ranged=%s idle_path=%s leak=%s stats_ok=%s counts_ok=%s" % [
			cid, player.max_hp, player.melee_dmg, player.speed_mult,
			str(player.ranged), idle_path, str(leak), str(stats_ok), str(counts_ok)])
		if leak or not stats_ok or not counts_ok:
			ok = false
	# (c) Mage shoot excludes the bad frame: exactly 5 clean frames,
	# and no shoot_5.png (which would be the bad r2c5) exists on disk.
	player.set_class("mage")
	var mage_shoot_n: int = player.get("_anim_shoot").size()
	var bad_exists: bool = FileAccess.file_exists(
		"res://assets/player_anim/mage/shoot_5.png")
	print("DEEPFALL_SELFTEST_PHASE8 c mage_shoot_frames=%d (expect 5) bad_frame_file_exists=%s (expect false)" % [
		mage_shoot_n, str(bad_exists)])
	if mage_shoot_n != 5 or bad_exists:
		ok = false
	# Mage orb: spawn a ghoul one cell right, fire, step the orb until it hits.
	# Phase 10: the orb only fires with the sword equipped — equip it
	# first (the test's precondition, not a gameplay change).
	set_tool("sword")
	var cell: Vector2i = player.cell() + Vector2i(1, 0)
	_spawn_one("miner-ghoul", cell)
	var ghoul: Node2D = enemies[enemies.size() - 1]
	player.position = Vector2((player.cell().x + 0.5) * TILE, (player.cell().y + 0.5) * TILE)
	player.facing = 1
	player.attack_cooldown = 0.0
	player.try_attack()
	var orb_fired: bool = _orbs.size() == 1
	for k in range(20):
		if _orbs.is_empty():
			break
		_update_orbs(0.05)
	print("DEEPFALL_SELFTEST_PHASE8 orb fired=%s ghoul_hp=%d (expect true, 8)" % [
		str(orb_fired), ghoul.hp])
	if not orb_fired or ghoul.hp != 8:
		ok = false
	# Red melee: 20 damage kills a fresh 20-HP ghoul in one swing.
	player.set_class("red")
	_spawn_one("miner-ghoul", player.cell() + Vector2i(1, 0))
	var ghoul2: Node2D = enemies[enemies.size() - 1]
	player_attack_hit(player.position, 1)
	print("DEEPFALL_SELFTEST_PHASE8 red_melee ghoul2_hp=%d (expect 0)" % ghoul2.hp)
	if ghoul2.hp != 0:
		ok = false
	# (d) Picking a class, saving, rebuilding from the save, and loading
	# restores that class — for red, then for mage.
	for cid in ["red", "mage"]:
		player.set_class(cid)
		save_game("selftest8")
		_rebuild_world(true)
		var restored: bool = player.class_id == cid
		var hp_ok: bool = player.max_hp == int(expect[cid]["hp"]) \
			and player.hp == int(expect[cid]["hp"])
		print("DEEPFALL_SELFTEST_PHASE8 d class=%s restored=%s hp=%d/%d (expect true, %d/%d)" % [
			cid, str(restored), player.hp, player.max_hp,
			int(expect[cid]["hp"]), int(expect[cid]["hp"])])
		if not restored or not hp_ok:
			ok = false
	# Leave the world in the mage class (the final save on disk is mage);
	# --selftest-load will verify the class field against the live player.
	save_game("selftest8")
	print("DEEPFALL_SELFTEST_PHASE8 done PASS=%s" % str(ok))

# --- Phase 9 self-test: physics measurements, platforms, collision,
# twin sticks, newly wired animation states, orb FX, HUD, parallax,
# transition/corner tiles. Synchronous except the parallax section,
# which awaits two process frames so the camera transform settles.
# Called with `await` from _run_selftest; restores a clean world and
# saves as mage at the end (same convention as Phase 8). ---

func _p9_place_feet(cell_x: int, feet_y: int) -> void:
	player.position = Vector2(cell_x * TILE + TILE * 0.5, feet_y - player.half_h)
	player.vel = Vector2.ZERO
	player.on_ground = false

func _p9_settle(max_steps: int = 40) -> bool:
	for k in range(max_steps):
		if player.on_ground:
			return true
		player._physics_process(1.0 / 60.0)
	return player.on_ground

func _room_center(ri: int) -> Vector2i:
	# Rooms are [rx, ry, rw, rh] arrays in data["rooms"] (see map_gen).
	var r: Array = data["rooms"][ri]
	return Vector2i(int(r[0]) + int(r[2]) / 2, int(r[1]) + int(r[3]) / 2)

func _p9_first_solid_below(cx: int, from_y: int) -> int:
	for y in range(from_y, 45):
		if fg[y][cx] != 0:
			return y
	return -1

func _run_selftest_phase9() -> void:
	print("DEEPFALL_SELFTEST_PHASE9 start")
	var ok := true
	# Phase 10: the Phase 8 orb section leaves the sword equipped —
	# this phase's mining/collision/stick tests need the pickaxe.
	set_tool("pickaxe")
	player.set_physics_process(false)
	player.touch_move = 0.0
	player.touch_jump = false
	player.touch_crouch = false
	player.touch_drop = false
	# HUD: both lines must fit inside 1264 px at 1280x720.
	await get_tree().process_frame
	var font: Font = hud.get_theme_default_font()
	var w1 := font.get_string_size(hud.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	var w2 := 0.0
	if _hud2 != null:
		w2 = font.get_string_size(_hud2.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14).x
	print("DEEPFALL_SELFTEST_PHASE9 hud line1_px=%.0f line2_px=%.0f (expect both < 1248)" % [w1, w2])
	if w1 >= 1248.0 or w2 >= 1248.0:
		ok = false
	# Transition/corner tiles: count cells carrying real art.
	var trans_n := 0
	var corner_n := 0
	for y in range(45):
		for x in range(80):
			var sp := _fill_special(Vector2i(x, y))
			if sp >= 15 and sp <= 22:
				trans_n += 1
			elif sp >= 23 and sp <= 30:
				corner_n += 1
	print("DEEPFALL_SELFTEST_PHASE9 tiles transition_cells=%d corner_cells=%d (expect both > 0)" % [trans_n, corner_n])
	if trans_n <= 0 or corner_n <= 0:
		ok = false
	# Parallax: far must drift less on screen than mid, both less than
	# the camera. World-space deltas are the inverse (far 0.65x, mid
	# 0.35x of the camera delta); the on-screen shift is (1 - that),
	# so far drifts 0.35x and mid 0.65x on screen.
	var cc0: Vector2 = camera.get_screen_center_position()
	var far0: Vector2 = _plx_far.position
	var mid0: Vector2 = _plx_mid.position
	camera.position_smoothing_enabled = false
	var rc8: Vector2i = _room_center(8)
	player.position = Vector2((rc8.x + 0.5) * TILE, (rc8.y + 0.5) * TILE)
	player.vel = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	var cc1: Vector2 = camera.get_screen_center_position()
	var far1: Vector2 = _plx_far.position
	var mid1: Vector2 = _plx_mid.position
	camera.position_smoothing_enabled = true
	var cam_dx := cc1.x - cc0.x
	var far_dx := far1.x - far0.x
	var mid_dx := mid1.x - mid0.x
	var far_ratio := (far_dx / cam_dx) if cam_dx != 0.0 else 0.0
	var mid_ratio := (mid_dx / cam_dx) if cam_dx != 0.0 else 0.0
	print("DEEPFALL_SELFTEST_PHASE9 parallax cam_dx=%.1f far_dx=%.1f (%.2fx) mid_dx=%.1f (%.2fx) (expect far 0.65x, mid 0.35x of camera)" % [cam_dx, far_dx, far_ratio, mid_dx, mid_ratio])
	if cam_dx == 0.0 or absf(far_ratio - 0.65) > 0.05 or absf(mid_ratio - 0.35) > 0.05:
		ok = false
	# (a) Physics measurements. Theory: JUMP_VEL 620, GRAVITY 1800 ->
	# height 620^2/(2*1800) = 106.8 px (1.67 tiles), air time
	# 2*620/1800 = 0.69 s (41 frames); a double jump pressed near the
	# apex adds ~107 px.
	var spawn_cell: Vector2i = data["spawn"]
	var floor_y := _p9_first_solid_below(spawn_cell.x, spawn_cell.y)
	# One-way platform for the platform tests (first found anywhere).
	var plat := Vector2i(-1, -1)
	for y in range(1, 44):
		for x in range(1, 79):
			if fg[y][x] == 7 and fg[y - 1][x] == 0 and fg[y + 1][x] == 0 and fg[y + 2][x] == 0 and fg[y + 3][x] != 0:
				plat = Vector2i(x, y)
				break
		if plat.x >= 0:
			break
	var plat_floor_y := plat.y + 3
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	var feet0: float = player.position.y + player.half_h
	player.touch_jump = true
	player._physics_process(1.0 / 60.0)
	player.touch_jump = false
	var min_feet: float = player.position.y + player.half_h
	var frames := 0
	while frames < 120 and not player.on_ground:
		player._physics_process(1.0 / 60.0)
		frames += 1
		min_feet = minf(min_feet, player.position.y + player.half_h)
	var jump_h: float = feet0 - min_feet
	var air_frames := frames + 1
	var squash := float(player.get("_land_timer"))
	print("DEEPFALL_SELFTEST_PHASE9 physics single_jump height_px=%.1f tiles=%.2f air_frames=%d air_s=%.2f (theory 106.8px/1.67 tiles/41 frames/0.69s) land_timer=%.3f (expect ~0.133)" % [jump_h, jump_h / 64.0, air_frames, air_frames / 60.0, squash])
	if absf(jump_h - 106.8) > 12.0 or air_frames < 35 or air_frames > 48 or squash < 0.1:
		ok = false
	# Double jump: second press 12 frames in, near the apex.
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	feet0 = player.position.y + player.half_h
	player.touch_jump = true
	player._physics_process(1.0 / 60.0)
	player.touch_jump = false
	min_feet = feet0
	var dj_fired := false
	frames = 0
	while frames < 150 and not player.on_ground:
		if frames == 12 and not dj_fired:
			player.touch_jump = true
			player._physics_process(1.0 / 60.0)
			player.touch_jump = false
			dj_fired = bool(player.get("_double_jumped"))
		else:
			player._physics_process(1.0 / 60.0)
		frames += 1
		min_feet = minf(min_feet, player.position.y + player.half_h)
	var dj_h: float = feet0 - min_feet
	print("DEEPFALL_SELFTEST_PHASE9 physics double_jump height_px=%.1f tiles=%.2f double_fired=%s (expect ~200px/3.1 tiles/true)" % [dj_h, dj_h / 64.0, str(dj_fired)])
	if absf(dj_h - 200.0) > 25.0 or not dj_fired:
		ok = false
	# Coyote: walk off a platform end, jump on the next step.
	var coyote_cell := Vector2i(-1, -1)
	for y in range(1, 44):
		for x in range(1, 78):
			if fg[y][x] == 7 and fg[y][x + 1] == 0 and fg[y - 1][x + 1] == 0 and fg[y + 1][x + 1] == 0:
				coyote_cell = Vector2i(x, y)
				break
		if coyote_cell.x >= 0:
			break
	if coyote_cell.x < 0:
		print("DEEPFALL_SELFTEST_PHASE9 physics coyote SKIP (no platform with a clear drop to its right)")
	else:
		_p9_place_feet(coyote_cell.x, coyote_cell.y * TILE)
		_p9_settle()
		player.touch_move = 1.0
		var left_frames := 0
		while left_frames < 240 and player.on_ground:
			player._physics_process(1.0 / 60.0)
			left_frames += 1
		player.touch_jump = true
		player._physics_process(1.0 / 60.0)
		player.touch_jump = false
		player.touch_move = 0.0
		var coyote_vel: float = player.vel.y
		print("DEEPFALL_SELFTEST_PHASE9 physics coyote left_after_frames=%d vel_y=%.0f (expect -620: jump fired inside the 0.12s window)" % [left_frames, coyote_vel])
		if not is_equal_approx(coyote_vel, -620.0):
			ok = false
		_p9_settle(120)
	# Jump buffer: jump, then double-jump at frame 12 (so jumps_left is
	# 0), then press jump ~5 frames before landing. The press must NOT
	# fire mid-air — it must fire within 3 frames of touching down.
	# The test runs on a floor column with clear air above it: the spawn
	# room has a platform 192 px overhead, and the double jump rises
	# ~207 px, so the player would land on the platform (192 px above
	# the floor) and the "within 50 px of the floor" window would never
	# open — that is what the first version of this test measured.
	var buf_x := -1
	var buf_floor_y := -1
	for yy in range(5, 44):
		for xx in range(1, 79):
			if fg[yy][xx] != 0 and fg[yy][xx] != 7 and fg[yy - 1][xx] == 0 and fg[yy - 2][xx] == 0 and fg[yy - 3][xx] == 0 and fg[yy - 4][xx] == 0:
				buf_x = xx
				buf_floor_y = yy
				break
		if buf_x >= 0:
			break
	_p9_place_feet(buf_x, buf_floor_y * TILE)
	_p9_settle()
	feet0 = player.position.y + player.half_h
	player.touch_jump = true
	player._physics_process(1.0 / 60.0)
	player.touch_jump = false
	frames = 0
	var dj2_done := false
	while frames < 40 and not dj2_done:
		if frames == 12:
			player.touch_jump = true
			player._physics_process(1.0 / 60.0)
			player.touch_jump = false
			dj2_done = bool(player.get("_double_jumped"))
		else:
			player._physics_process(1.0 / 60.0)
		frames += 1
	var buffered := false
	var landed := false
	var fire_frames := -1
	frames = 0
	while frames < 150:
		if not buffered and player.vel.y > 0.0 and (buf_floor_y * TILE - (player.position.y + player.half_h)) < 50.0:
			player.touch_jump = true
			player._physics_process(1.0 / 60.0)
			player.touch_jump = false
			buffered = true
		else:
			player._physics_process(1.0 / 60.0)
		frames += 1
		if not landed and player.on_ground:
			landed = true
			fire_frames = 0
		elif landed and fire_frames >= 0:
			fire_frames += 1
			if is_equal_approx(player.vel.y, -620.0) and not player.on_ground:
				break
			if fire_frames > 3:
				break
	print("DEEPFALL_SELFTEST_PHASE9 physics jump_buffer double_used=%s pressed=%s fired_within_frames=%d (expect true, true, <=3)" % [str(dj2_done), str(buffered), fire_frames])
	if not dj2_done or not buffered or fire_frames < 0 or fire_frames > 3:
		ok = false
	_p9_settle(150)
	# (b) One-way platforms: single jump cannot reach (107 px < 192 px),
	# double jump lands on top; drop-through falls back to the floor.
	if plat.x < 0:
		print("DEEPFALL_SELFTEST_PHASE9 platform SKIP (no one-way platform found)")
	else:
		_p9_place_feet(plat.x, plat_floor_y * TILE)
		_p9_settle()
		feet0 = player.position.y + player.half_h
		player.touch_jump = true
		player._physics_process(1.0 / 60.0)
		player.touch_jump = false
		min_feet = feet0
		frames = 0
		while frames < 120 and not player.on_ground:
			player._physics_process(1.0 / 60.0)
			frames += 1
			min_feet = minf(min_feet, player.position.y + player.half_h)
		var single_top: float = min_feet
		var single_land_feet: float = player.position.y + player.half_h
		print("DEEPFALL_SELFTEST_PHASE9 platform single_jump min_feet_vs_plat_top=%+.1f land_feet=%.1f (expect feet stay below the top, i.e. +85, and land back on the floor %d)" % [single_top - plat.y * TILE, single_land_feet, plat_floor_y * TILE])
		if single_top <= plat.y * TILE or absf(single_land_feet - plat_floor_y * TILE) > 1.0:
			ok = false
		# Double jump onto the platform (second press 14 frames in).
		_p9_place_feet(plat.x, plat_floor_y * TILE)
		_p9_settle()
		feet0 = player.position.y + player.half_h
		player.touch_jump = true
		player._physics_process(1.0 / 60.0)
		player.touch_jump = false
		min_feet = feet0
		frames = 0
		dj_fired = false
		while frames < 150 and not player.on_ground:
			if frames == 14 and not dj_fired:
				player.touch_jump = true
				player._physics_process(1.0 / 60.0)
				player.touch_jump = false
				dj_fired = bool(player.get("_double_jumped"))
			else:
				player._physics_process(1.0 / 60.0)
			frames += 1
			min_feet = minf(min_feet, player.position.y + player.half_h)
		var dj_land_feet: float = player.position.y + player.half_h
		print("DEEPFALL_SELFTEST_PHASE9 platform double_jump min_feet_vs_plat_top=%+.1f land_feet=%.1f on_ground=%s (expect feet pass above the top, land feet == plat top %d)" % [min_feet - plat.y * TILE, dj_land_feet, str(player.on_ground), plat.y * TILE])
		if min_feet >= plat.y * TILE or absf(dj_land_feet - plat.y * TILE) > 1.0 or not player.on_ground:
			ok = false
		# Drop-through: standing on the platform, down + jump drops.
		_p9_place_feet(plat.x, plat.y * TILE)
		_p9_settle()
		player.touch_drop = true
		player.touch_jump = true
		player._physics_process(1.0 / 60.0)
		player.touch_jump = false
		player.touch_drop = false
		var dropped: bool = not player.on_ground and float(player.get("_drop_timer")) > 0.0
		frames = 0
		while frames < 90 and not player.on_ground:
			player._physics_process(1.0 / 60.0)
			frames += 1
		var drop_land_feet: float = player.position.y + player.half_h
		print("DEEPFALL_SELFTEST_PHASE9 platform drop_through fired=%s land_feet=%.1f (expect true, %d = the floor below)" % [str(dropped), drop_land_feet, plat_floor_y * TILE])
		if not dropped or absf(drop_land_feet - plat_floor_y * TILE) > 1.0:
			ok = false
	# (c) Collision: wall clamp, mine-the-floor-under-feet, knockback,
	# bottom-row safety.
	var wall_c := Vector2i(-1, -1)
	for y in range(1, 44):
		for x in range(1, 79):
			if fg[y][x] != 0 and fg[y][x] != 7 and fg[y][x - 1] == 0 and fg[y + 1][x - 1] != 0:
				wall_c = Vector2i(x, y)
				break
		if wall_c.x >= 0:
			break
	if wall_c.x < 0:
		print("DEEPFALL_SELFTEST_PHASE9 collision SKIP (no wall-with-floor cell found)")
	else:
		var wall_floor_y := _p9_first_solid_below(wall_c.x - 1, wall_c.y)
		_p9_place_feet(wall_c.x - 1, wall_floor_y * TILE)
		_p9_settle()
		player.touch_move = 1.0
		for k in range(60):
			player._physics_process(1.0 / 60.0)
		player.touch_move = 0.0
		var right_edge: float = player.position.x + player.half_w
		print("DEEPFALL_SELFTEST_PHASE9 collision wall right_edge=%.2f wall_left=%d vel_x=%.1f (expect right edge <= wall left + 0.5, vel_x 0)" % [right_edge, wall_c.x * TILE, player.vel.x])
		if right_edge > wall_c.x * TILE + 0.5 or not is_equal_approx(player.vel.x, 0.0):
			ok = false
		# Mine the floor block under the player's feet, twice: the player
		# must fall exactly one cell and land, not clip inside solid.
		_p9_place_feet(wall_c.x - 1, wall_floor_y * TILE)
		_p9_settle()
		var feet_before: float = player.position.y + player.half_h
		var under := Vector2i(wall_c.x - 1, wall_floor_y)
		if fg[wall_floor_y + 1][under.x] == 0:
			print("DEEPFALL_SELFTEST_PHASE9 collision mine_floor SKIP (no solid row below)")
		else:
			_mine_at(under)
			_mine_at(under)
			player.on_ground = false
			frames = 0
			while frames < 90 and not player.on_ground:
				player._physics_process(1.0 / 60.0)
				frames += 1
			var feet_after: float = player.position.y + player.half_h
			print("DEEPFALL_SELFTEST_PHASE9 collision mine_floor feet_before=%d feet_after=%d on_ground=%s (expect +64, true)" % [int(feet_before), int(feet_after), str(player.on_ground)])
			if absf(feet_after - feet_before - 64.0) > 1.0 or not player.on_ground:
				ok = false
		# Enemy knockback toward a wall: take_hit from the open side.
		_p9_place_feet(wall_c.x - 1, wall_floor_y * TILE)
		_p9_settle()
		player.hp = 10000
		player.hurt_timer = 0.0
		var kb_x0 := player.position.x
		player.take_hit(8, player.position.x - 100.0)
		for k in range(30):
			player._physics_process(1.0 / 60.0)
		var kb_dx := player.position.x - kb_x0
		right_edge = player.position.x + player.half_w
		print("DEEPFALL_SELFTEST_PHASE9 collision knockback dx=%.2f right_edge=%.2f wall_left=%d (expect dx ~0, no penetration. NOTE: take_hit sets vel.x but _physics_process overwrites it with the move input every step, so the horizontal knockback never displaces the player — only the -150 hop applies. Pre-existing behaviour, not changed.)" % [kb_dx, right_edge, wall_c.x * TILE])
		if absf(kb_dx) > 1.0 or right_edge > wall_c.x * TILE + 0.5:
			ok = false
	# Bottom-row safety: drop the player into the lowest air row.
	# Row 43 is all solid, so scan upward for the lowest air cell with
	# solid ground below it: the player must land, never leave the map.
	var bot_cell := Vector2i(-1, -1)
	for y in range(43, 0, -1):
		for x in range(1, 79):
			if fg[y][x] == 0 and fg[y + 1][x] != 0:
				bot_cell = Vector2i(x, y)
				break
		if bot_cell.x >= 0:
			break
	if bot_cell.x < 0:
		print("DEEPFALL_SELFTEST_PHASE9 collision bottom_row SKIP (no air cell found)")
	else:
		player.position = Vector2(bot_cell.x * TILE + 32.0, bot_cell.y * TILE + 32.0)
		player.vel = Vector2.ZERO
		player.on_ground = false
		frames = 0
		while frames < 120 and not player.on_ground:
			player._physics_process(1.0 / 60.0)
			frames += 1
		print("DEEPFALL_SELFTEST_PHASE9 collision bottom_row y=%.1f on_ground=%s (expect y < %d, true)" % [player.position.y, str(player.on_ground), 45 * TILE])
		if player.position.y >= 45 * TILE or not player.on_ground:
			ok = false
	# (d) Twin sticks: superseded by the Phase 11 floating sticks —
	# see _run_selftest_p11 (--selftest-p11, simulated multi-touch).
	# (e) Enemy animation: walk + attack actually play per slug.
	player.hp = 10000
	player.hurt_timer = 0.0
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	for slug in ENEMY_SLUGS:
		var scell: Vector2i = player.cell() + Vector2i(2, 0)
		_spawn_one(slug, scell)
		var e: Node2D = enemies[enemies.size() - 1]
		e.set_physics_process(false)
		var walk_seen := {}
		for k in range(90):
			e._physics_process(1.0 / 60.0)
			var spr: Sprite2D = e.get("_sprite")
			if spr.texture != null:
				walk_seen[spr.texture.resource_path] = true
		player.position = e.position + Vector2(40.0, 0.0)
		player.vel = Vector2.ZERO
		var attacked := false
		var atk_seen := {}
		for k in range(240):
			e._physics_process(1.0 / 60.0)
			var spr2: Sprite2D = e.get("_sprite")
			if spr2.texture != null:
				atk_seen[spr2.texture.resource_path] = true
			if float(e.get("_attack_timer")) > 0.0:
				attacked = true
		var atk_played := false
		for p in atk_seen.keys():
			if String(p).contains("attack"):
				atk_played = true
		print("DEEPFALL_SELFTEST_PHASE9 enemy slug=%s walk_frames_seen=%d attack_started=%s attack_frames_seen=%s (ore-mimic walk is 1 by design: ambush, wander=false)" % [slug, walk_seen.size(), str(attacked), str(atk_played)])
		if walk_seen.is_empty() or not attacked:
			ok = false
	# Bat hover: sine bob, no ground, wanders in the air.
	var bcell: Vector2i = player.cell() + Vector2i(2, -1)
	_spawn_one("cave-bat-swarm", bcell)
	var bat: Node2D = enemies[enemies.size() - 1]
	bat.set_physics_process(false)
	var y0 := bat.position.y
	var x0 := bat.position.x
	var ymin := y0
	var ymax := y0
	for k in range(120):
		bat._physics_process(1.0 / 60.0)
		ymin = minf(ymin, bat.position.y)
		ymax = maxf(ymax, bat.position.y)
	var bat_dx := bat.position.x - x0
	print("DEEPFALL_SELFTEST_PHASE9 enemy bat hover_y_range=%.1f (expect <= 41, i.e. +-20 clamp) dx=%.1f (expect != 0: it wanders) on_ground=%s (expect false)" % [ymax - ymin, bat_dx, str(bat.on_ground)])
	if ymax - ymin > 41.5 or absf(bat_dx) < 5.0 or bat.on_ground:
		ok = false
	# (f) Player animation states: dying, crouch, thruster, landing.
	var spawn_pos := Vector2((spawn_cell.x + 0.5) * TILE, (spawn_cell.y + 0.5) * TILE)
	for cid in ["tech", "red", "mage"]:
		player.set_class(cid)
		player.respawn_at(spawn_pos)
		player.hp = 10
		player.hurt_timer = 0.0
		player.take_hit(999, player.position.x)
		var die_seen := {}
		for k in range(75):
			player._physics_process(1.0 / 60.0)
			var spr3: Sprite2D = player.get("_sprite")
			if spr3.texture != null:
				die_seen[spr3.texture.resource_path] = true
		var die_hidden := not (player.get("_sprite") as Sprite2D).visible
		_respawn_timer = 0.0
		player.respawn_at(spawn_pos)
		var expect_die: int = (player.get("_anim_dying") as Array).size()
		print("DEEPFALL_SELFTEST_PHASE9 anim dying class=%s frames_seen=%d (expect %d) hidden_at_end=%s" % [cid, die_seen.size(), expect_die, str(die_hidden)])
		if die_seen.size() != expect_die or not die_hidden:
			ok = false
	player.set_class("tech")
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	player.touch_crouch = true
	var crouch_seen := {}
	for k in range(30):
		player._physics_process(1.0 / 60.0)
		var spr4: Sprite2D = player.get("_sprite")
		if spr4.texture != null:
			crouch_seen[spr4.texture.resource_path] = true
	var crouching := bool(player.get("_crouching"))
	player.touch_move = 1.0
	player._physics_process(1.0 / 60.0)
	var crouch_speed: float = player.vel.x
	player.touch_move = 0.0
	player.touch_crouch = false
	print("DEEPFALL_SELFTEST_PHASE9 anim crouch active=%s frames_seen=%d speed_while_crouched=%.0f (expect true, >=2, 130 = half of 260)" % [str(crouching), crouch_seen.size(), crouch_speed])
	if not crouching or crouch_seen.size() < 2 or not is_equal_approx(crouch_speed, 130.0):
		ok = false
	# Thruster: airborne after the double jump.
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	player.touch_jump = true
	player._physics_process(1.0 / 60.0)
	player.touch_jump = false
	for k in range(12):
		player._physics_process(1.0 / 60.0)
	player.touch_jump = true
	player._physics_process(1.0 / 60.0)
	player.touch_jump = false
	var thruster_on := bool(player.get("_double_jumped"))
	for k in range(3):
		player._physics_process(1.0 / 60.0)
	var thr_tex := ((player.get("_sprite") as Sprite2D).texture as Texture2D).resource_path
	print("DEEPFALL_SELFTEST_PHASE9 anim thruster double_jumped=%s texture=%s (expect true, a thruster frame)" % [str(thruster_on), thr_tex])
	if not thruster_on or not thr_tex.contains("thruster"):
		ok = false
	_p9_settle(150)
	# Landing: the lowest frame, consistently per class.
	for cid in ["tech", "red", "mage"]:
		player.set_class(cid)
		_p9_place_feet(spawn_cell.x, floor_y * TILE)
		_p9_settle()
		player.touch_jump = true
		player._physics_process(1.0 / 60.0)
		player.touch_jump = false
		frames = 0
		while frames < 120 and not player.on_ground:
			player._physics_process(1.0 / 60.0)
			frames += 1
		var land_tex := ((player.get("_sprite") as Sprite2D).texture as Texture2D).resource_path
		var land_expect := "fall_2" if cid == "tech" else "crouch_3"
		print("DEEPFALL_SELFTEST_PHASE9 anim landing class=%s texture=%s (expect %s)" % [cid, land_tex, land_expect])
		if not land_tex.contains(land_expect):
			ok = false
	# (g) Mage orb: trail dots while flying, frost-burst impact on hit.
	# Hermetic: clear stale orbs/FX from earlier tests (the multitouch
	# ATK press fires a real mage orb; Phase 8 left trail/impact FX)
	# and free the test enemies so the orb flies its full range.
	for o in _orbs:
		if is_instance_valid(o["node"]):
			(o["node"] as Node).free()
	_orbs.clear()
	for fx in _orb_fx:
		if is_instance_valid(fx["node"]):
			(fx["node"] as Node).free()
	_orb_fx.clear()
	for e in enemies:
		if is_instance_valid(e):
			e.free()
	enemies.clear()
	# Phase 9b: also free any live Effekseer impact emitters (the
	# multitouch ATK press in (f) fires a real mage orb whose impact is
	# an emitter child, not an _orb_fx entry).
	for c in get_children():
		if c.get_class() == "EffekseerEmitter2D":
			c.free()
	player.set_class("mage")
	_p9_place_feet(spawn_cell.x, floor_y * TILE)
	_p9_settle()
	player.facing = 1
	player.attack_cooldown = 0.0
	# Phase 10: the orb only fires with the sword equipped — equip it
	# first (the test's precondition, not a gameplay change).
	set_tool("sword")
	player.try_attack()
	var orb_ok := _orbs.size() == 1
	for k in range(6):
		if _orbs.is_empty():
			break
		_update_orbs(0.05)
	var trail_n := _orb_fx.size()
	frames = 0
	while frames < 40 and not _orbs.is_empty():
		_update_orbs(0.05)
		frames += 1
	var impact_n := 0
	for fx in _orb_fx:
		if (fx["frames"] as Array).size() > 0:
			impact_n += 1
	# Phase 9b: the impact is an EffekseerEmitter2D child when the plugin
	# is present, not an _orb_fx entry — count those too.
	for c in get_children():
		if c.get_class() == "EffekseerEmitter2D":
			impact_n += 1
	_update_fx(0.3)
	var fx_left := _orb_fx.size()
	print("DEEPFALL_SELFTEST_PHASE9 orb fired=%s trail_dots_after_6_steps=%d impact_spawned=%d fx_left_after_0.3s=%d (expect true, >=4, 1, 0)" % [str(orb_ok), trail_n, impact_n, fx_left])
	if not orb_ok or trail_n < 4 or impact_n != 1 or fx_left != 0:
		ok = false
	# (h) Transition re-derivation: mining a neighbour changes the fill.
	# Phase 10: the orb section above left the sword equipped — mining
	# needs the pickaxe back first.
	set_tool("pickaxe")
	var tcell := Vector2i(-1, -1)
	var tnb := Vector2i(-1, -1)
	for y in range(1, 44):
		for x in range(1, 79):
			var sp := _fill_special(Vector2i(x, y))
			if sp >= 15 and sp <= 22:
				var g0 := _mat_group(fg[y][x])
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var nb: Vector2i = Vector2i(x, y) + d
					if _is_solid_cell(nb):
						var g1 := _mat_group(fg[nb.y][nb.x])
						if (g0 == 0 and g1 == 1) or (g0 == 1 and g1 == 0):
							tcell = Vector2i(x, y)
							tnb = nb
							break
				if tcell.x >= 0:
					break
		if tcell.x >= 0:
			break
	if tcell.x < 0:
		print("DEEPFALL_SELFTEST_PHASE9 tiles transition_rederive SKIP (no transition cell found)")
	else:
		var sp0 := _fill_special(tcell)
		_mine_at(tnb)
		_mine_at(tnb)
		var sp1 := _fill_special(tcell)
		print("DEEPFALL_SELFTEST_PHASE9 tiles transition_rederive cell=%s special_before=%d special_after=%d changed=%s (expect true)" % [str(tcell), sp0, sp1, str(sp1 != sp0)])
		if sp1 == sp0:
			ok = false
	# Restore: clean world, mage class, saved — same convention as
	# Phase 8, so --selftest-load stays consistent.
	_rebuild_world(false)
	player.set_class("mage")
	_respawn_timer = 0.0
	player.set_physics_process(true)
	player.touch_move = 0.0
	player.touch_jump = false
	player.touch_crouch = false
	player.touch_drop = false
	save_game("selftest9")
	print("DEEPFALL_SELFTEST_PHASE9 done PASS=%s" % str(ok))

func _run_selftest_phase9b() -> void:
	# Phase 9b: Effekseer wiring check (--selftest). Both emitters are
	# created, played, run 90 frames, and must self-free via their
	# timers; calculate_duration() must return the authored lengths
	# (orb 0.6667 s / 40 frames, poof 1.0 s / 60 frames). Also fires
	# the real in-game paths once (_spawn_orb_impact + spawn_death_fx).
	print("DEEPFALL_SELFTEST_PHASE9B start")
	var ok := true
	var has_plugin: bool = ClassDB.class_exists("EffekseerEmitter2D")
	print("DEEPFALL_SELFTEST_PHASE9B plugin_class_exists=%s (expect true)" % str(has_plugin))
	if not has_plugin:
		ok = false
	var orb_res: Resource = load(ORB_IMPACT_EFK)
	var poof_res: Resource = load(DEATH_POOF_EFK)
	print("DEEPFALL_SELFTEST_PHASE9B orb_res_null=%s poof_res_null=%s (expect false false)" % [str(orb_res == null), str(poof_res == null)])
	if orb_res == null or poof_res == null:
		ok = false
	var emitters: Array = []
	if has_plugin and orb_res != null and poof_res != null:
		var e1: Node = _make_effekseer_emitter(ORB_IMPACT_EFK, player.position + Vector2(64, -32), 0.8)
		var e2: Node = _make_effekseer_emitter(DEATH_POOF_EFK, player.position + Vector2(-64, -32), 1.1)
		emitters = [e1, e2]
		print("DEEPFALL_SELFTEST_PHASE9B emitters_created=%s (expect true true)" % str([e1 != null, e2 != null]))
		if e1 == null or e2 == null:
			ok = false
		else:
			# calculate_duration() lives on the EffekseerEffect resource
			# (see addons/effekseer/src/EffekseerEffectInspector.gd),
			# not on the emitter.
			var d1: float = float(orb_res.call("calculate_duration"))
			var d2: float = float(poof_res.call("calculate_duration"))
			print("DEEPFALL_SELFTEST_PHASE9B duration orb=%.4f (expect 0.6667) poof=%.4f (expect 1.0000)" % [d1, d2])
			if absf(d1 - 0.6667) > 0.01 or absf(d2 - 1.0) > 0.01:
				ok = false
	# Real in-game paths: orb impact + death fx at the player.
	_spawn_orb_impact(player.position + Vector2(96, -32))
	spawn_death_fx(player.position + Vector2(-96, -32))
	# 90 frames at 60 fps = 1.5 s: both emitters (0.8 s / 1.1 s timers)
	# and both fired FX must be freed by then. The extra real-time wait
	# covers headless runs where frames tick faster than wall-clock 60 fps.
	for i in range(90):
		await get_tree().process_frame
	await get_tree().create_timer(1.6).timeout
	var alive := 0
	for e in emitters:
		if is_instance_valid(e):
			alive += 1
	print("DEEPFALL_SELFTEST_PHASE9B emitters_alive_after_90_frames=%d (expect 0)" % alive)
	if alive != 0:
		ok = false
	print("DEEPFALL_SELFTEST_PHASE9B done PASS=%s" % str(ok))

func _run_selftest_phase10() -> void:
	# Phase 10: tool separation, JUMP button, HUD widths, hearts/log,
	# perf caps, walk-height audit (--selftest). Runs on a clean world;
	# the Phase 9 restore left the mage selected — reset to tech +
	# pickaxe first so the tool tests start from the default state.
	print("DEEPFALL_SELFTEST_PHASE10 start")
	var ok := true
	_rebuild_world(false)
	player.set_class("tech")
	set_tool("pickaxe")
	# (a) Tool switching: Q toggle / 1 / 2 via the main functions and
	# the player's tool var in lockstep.
	cycle_tool()
	var t1: bool = tool == "sword" and player.tool == "sword"
	set_tool("pickaxe")
	var t2: bool = tool == "pickaxe" and player.tool == "pickaxe"
	set_tool("sword")
	var t3: bool = tool == "sword" and player.tool == "sword"
	print("DEEPFALL_SELFTEST_PHASE10 a tool_cycle=%s to_pickaxe=%s to_sword=%s (expect true true true)" % [str(t1), str(t2), str(t3)])
	if not (t1 and t2 and t3):
		ok = false
	# (b) Sword cannot mine: solid cell + E/click path leaves the block
	# intact and shows the log note; the right stick swings instead.
	var cell := Vector2i(-1, -1)
	for y in range(5, 40):
		for x in range(5, 75):
			if fg[y][x] != 0 and fg[y][x] != 7 and _is_air(Vector2i(x, y - 1)):
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	var before: int = fg[cell.y][cell.x]
	_mine_at(cell, false)
	var sword_blocked: bool = fg[cell.y][cell.x] == before and _log_msg == "Need pickaxe to mine"
	print("DEEPFALL_SELFTEST_PHASE10 b sword_mine_blocked=%s log=%s (expect true 'Need pickaxe to mine')" % [str(sword_blocked), _log_msg])
	if not sword_blocked:
		ok = false
	# (c) Pickaxe mines: two hits on the same cell, ore +1 if it is an
	# ore tile (gold/amber/coal); otherwise a plain block still clears.
	set_tool("pickaxe")
	var ore_before: int = ore_collected
	_mine_at(cell)
	_mine_at(cell)
	var mined: bool = fg[cell.y][cell.x] == 0
	print("DEEPFALL_SELFTEST_PHASE10 c pickaxe_mined=%s ore_before=%d ore_after=%d type=%d" % [str(mined), ore_before, ore_collected, before])
	if not mined:
		ok = false
	# (d) Damage by tool: pickaxe 5 dmg, sword class dmg (tech 15).
	# Spawn one ghoul next to the player for each hit.
	var g1: Node2D = _spawn_test_enemy()
	player_attack_hit(player.position, 1, 5 if tool == "pickaxe" else player.melee_dmg)
	var pick_dmg: bool = g1.hp == 15
	print("DEEPFALL_SELFTEST_PHASE10 d pickaxe_dmg ghoul_hp=%d (expect 15)" % g1.hp)
	if not pick_dmg:
		ok = false
	g1.take_hit(99, player.position.x)
	set_tool("sword")
	var g2: Node2D = _spawn_test_enemy()
	player_attack_hit(player.position, 1, 5 if tool == "pickaxe" else player.melee_dmg)
	var sword_dmg: bool = g2.hp == 5
	print("DEEPFALL_SELFTEST_PHASE10 d sword_dmg ghoul_hp=%d (expect 5)" % g2.hp)
	if not sword_dmg:
		ok = false
	g2.take_hit(99, player.position.x)
	# (e) JUMP button: the TouchUI JUMP button exists, is inside the
	# viewport, and pressing it (the real _jump_down handler) triggers
	# the same jump path as Space (touch_jump set; the physics step
	# then consumes it — verified by the jump firing).
	var tu: Node = get_node_or_null("TouchUI")
	var jump_ok := false
	if tu != null and tu.has_method("_jump_down"):
		tu.call("_jump_down")
		jump_ok = player.touch_jump
		player.touch_jump = false
	print("DEEPFALL_SELFTEST_PHASE10 e jump_button_triggers=%s (expect true)" % str(jump_ok))
	if not jump_ok:
		ok = false
	# (f) HUD widths at 1280x720: line 1 + hint line + log line all
	# under 1248 px (font 16/14/14). Measured with the default font.
	var hud1 := hud.text
	var w1: float = _measure_text(hud1, 16)
	var w2: float = _measure_text(_hud2.text, 14)
	var w3: float = _measure_text(_log_label.text, 14)
	print("DEEPFALL_SELFTEST_PHASE10 f hud1_px=%.0f hud2_px=%.0f log_px=%.0f (expect all < 1248)" % [w1, w2, w3])
	if w1 >= 1248.0 or w2 >= 1248.0 or w3 >= 1248.0:
		ok = false
	# (g) Hearts: 10 hearts at full HP 100; one heart lost per 10 HP.
	player.hp = 100
	var hearts_full: int = int(ceil(float(player.hp) / 10.0))
	player.hp = 55
	var hearts_half: int = int(ceil(float(player.hp) / 10.0))
	print("DEEPFALL_SELFTEST_PHASE10 g hearts full=%d at_55hp=%d (expect 10, 6)" % [hearts_full, hearts_half])
	if hearts_full != 10 or hearts_half != 6:
		ok = false
	player.hp = player.max_hp
	# (h) Perf caps: ember total 12 (2 lights x 6), torch light cap 6
	# with shadows on the nearest 4, chunk layers 60, parallax static
	# skip armed (last cam pos cached after one _update_parallax).
	_update_parallax()
	var ember_total := 0
	for n in _prop_chunks:
		for ch in n.get_children():
			if ch is CPUParticles2D:
				ember_total += int(ch.amount)
	var layers_total: int = _fg_layers.size() + _wall_layers.size() + _edge_layers.size() + _damage_layers.size()
	print("DEEPFALL_SELFTEST_PHASE10 h embers=%d (expect 12) chunk_layers=%d (expect 60) parallax_cached=%s (expect true)" % [ember_total, layers_total, str(_last_parallax_cam.x > -99999.0)])
	if ember_total != 12 or layers_total != 60 or _last_parallax_cam.x <= -99999.0:
		ok = false
	# (i) Walk-height audit: every wired walkcycle frame's figure height
	# (alpha-extent scan of the authored PNG) must lie within the idle
	# set's own height range (±2 px) for its class — the Phase 10
	# rescale. Idle frames vary among themselves (tech 189-191, red
	# 189-191, mage 102-106), so a single-frame 2 px tolerance would
	# be stricter than the idle set's own variation.
	var walk_ok := true
	for cid in ["tech", "red", "mage"]:
		player.set_class(cid)
		var idle_hs: Array = []
		for f in player.get("_anim_idle"):
			idle_hs.append(_figure_height(f))
		var idle_min: int = idle_hs.min()
		var idle_max: int = idle_hs.max()
		for f in player.get("_anim_walkcycle"):
			var h: int = _figure_height(f)
			if h < idle_min - 2 or h > idle_max + 2:
				print("DEEPFALL_SELFTEST_PHASE10 i MISMATCH class=%s walk_h=%d idle_range=%d-%d" % [cid, h, idle_min, idle_max])
				walk_ok = false
	print("DEEPFALL_SELFTEST_PHASE10 i walk_heights_match_idle=%s (expect true)" % str(walk_ok))
	if not walk_ok:
		ok = false
	# (j) Save round-trip: save with sword equipped, reload the JSON,
	# confirm version 8 + tool sword; then confirm an old v8 save
	# WITHOUT the tool field loads and defaults to pickaxe.
	set_tool("sword")
	save_game("selftest10")
	var d := _load_save_dict()
	var save_ok: bool = int(d.get("version", 0)) == 8 and String(d.get("tool", "")) == "sword"
	print("DEEPFALL_SELFTEST_PHASE10 j save_version=%s tool=%s (expect 8 sword)" % [str(d.get("version", "?")), str(d.get("tool", "?"))])
	if not save_ok:
		ok = false
	var d_old := d.duplicate()
	d_old.erase("tool")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d_old))
	f.close()
	_rebuild_world(true)
	var old_ok: bool = tool == "pickaxe"
	print("DEEPFALL_SELFTEST_PHASE10 j old_v8_save_defaults_pickaxe=%s (expect true)" % str(old_ok))
	if not old_ok:
		ok = false
	print("DEEPFALL_SELFTEST_PHASE10 done PASS=%s" % str(ok))

func _spawn_test_enemy() -> Node2D:
	# Phase 10 self-test helper: a ghoul (HP 20) one cell right of the
	# player, facing into the player's attack arc.
	var cell: Vector2i = player.cell() + Vector2i(1, 0)
	_spawn_one("miner-ghoul", cell)
	return enemies[enemies.size() - 1]

func _figure_height(tex: Texture2D) -> int:
	# Phase 10: figure height = vertical alpha extent of the AUTHORED
	# PNG, loaded straight from disk. The imported texture's
	# get_image() is ETC2-compressed (project setting) and its
	# decompression noise puts stray alpha at the canvas extremes, so
	# it always reads the full 195 px — useless for this measurement.
	var img: Image = Image.load_from_file(tex.resource_path)
	if img == null:
		return -1
	var top := -1
	var bottom := -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				if top < 0:
					top = y
				bottom = y
				break
	if top < 0:
		return 0
	return bottom - top + 1

func _measure_text(s: String, size: int) -> float:
	# Phase 10: HUD width measurement, same method as the Phase 9
	# self-test (the HUD label's own default font).
	var font: Font = hud.get_theme_default_font()
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x


# --- Phase 11: aim actions, physics props, FX helpers ---

func _ensure_fx() -> void:
	if fx == null:
		fx = FX_SCRIPT.new()
		fx.name = "FX"
		fx.main_node = self
		fx.z_index = 5
		add_child(fx)

func _tile_color(t: int) -> Color:
	if _tile_colors.has(t):
		return _tile_colors[t]
	var col := Color(0.5, 0.5, 0.5)
	if t >= 1 and t <= TILE_NAMES.size():
		var tex: Texture2D = load("res://assets/tiles/%s.png" % TILE_NAMES[t - 1])
		if tex != null:
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				col = img.get_pixel(0, 0).lightened(0.15)
	_tile_colors[t] = col
	return col

func _material_name(t: int) -> String:
	match t:
		1, 2:
			return "Dirt"
		4:
			return "Gold"
		5:
			return "Amber"
		6:
			return "Wood"
		11:
			return "Sand"
		13:
			return "Coal"
	return "Stone"

# Ray from the hero's chest along `dir`, up to REACH. Returns the first
# solid cell (or (-1,-1)) and the first prop on the way (or null).
func _aim_probe(dir: Vector2) -> Dictionary:
	var origin: Vector2 = player.position + Vector2(0, -8)
	var step := 8.0
	var dist := 0.0
	while dist <= REACH:
		var p := origin + dir * dist
		for pr in phys_props:
			if is_instance_valid(pr) and not pr.broken and pr.rect().has_point(p):
				return {"cell": Vector2i(-1, -1), "prop": pr}
		var c := Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))
		if c.x >= 0 and c.x < 80 and c.y >= 0 and c.y < 45:
			var t: int = fg[c.y][c.x]
			if t != 0 and t != 7:
				return {"cell": c, "prop": null}
		dist += step
	return {"cell": Vector2i(-1, -1), "prop": null}

# The right stick / mouse action: pickaxe mines the first block along
# the aim (or smacks a prop / swings at enemies), sword / staff attacks
# in the aim direction. Rate-limited by mine_cooldown / attack_cooldown.
func aim_action(dir: Vector2, _via_stick := true) -> void:
	if _selecting or player.dead or dir.length() < 0.05:
		return
	dir = dir.normalized()
	_aim_show = 0.25
	if tool == "sword":
		player.try_attack_dir(dir)
		return
	if mine_cooldown > 0.0 or float(player.attack_timer) > 0.0:
		return
	var probe := _aim_probe(dir)
	var c: Vector2i = probe["cell"]
	if probe["prop"] != null:
		player.try_attack_dir(dir)
		mine_cooldown = 0.3
	elif c.x >= 0 and not _enemy_closer_than_cell(dir, c):
		player.set("_swing_aim", dir)
		_mine_at(c)
		player.set("_swing_aim", dir)
		mine_cooldown = 0.26
	else:
		player.try_attack_dir(dir)
		mine_cooldown = 0.3

func _enemy_closer_than_cell(dir: Vector2, c: Vector2i) -> bool:
	var origin: Vector2 = player.position + Vector2(0, -8)
	var cd: float = origin.distance_to(Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE))
	for e in enemies:
		if is_instance_valid(e):
			var d: Vector2 = e.position - origin
			if d.length() < minf(cd, 110.0) and d.normalized().dot(dir) > 0.5:
				return true
	return false

func _update_aim_reticle(delta: float) -> void:
	if _reticle == null:
		return
	_aim_show = maxf(0.0, _aim_show - delta)
	var show: bool = (bool(player.get("aiming")) or _aim_show > 0.0) and tool == "pickaxe" and not _selecting
	if show:
		var c: Vector2i = _aim_probe(player.aim)["cell"]
		show = c.x >= 0
		if show:
			_reticle.position = Vector2(c.x * TILE, c.y * TILE)
			var k := 0.6 + 0.4 * sin(_time * 10.0)
			_reticle.default_color = Color(1.0, 0.85, 0.45, k)
	_reticle.visible = show

# Breakable / pushable props, placed deterministically on room floors.
func _spawn_phys_props() -> void:
	for pr in phys_props:
		if is_instance_valid(pr):
			pr.free()
	phys_props.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1111
	var spawn: Vector2i = data["spawn"]
	var exit_cell: Vector2i = data["exit"]
	var kinds := ["crate", "crate", "barrel", "pot", "pot"]
	var next_id := 0
	var skipped := 0
	var placed_x: Array = []
	for r in data["rooms"]:
		var rx: int = r[0]; var ry: int = r[1]; var rw: int = r[2]; var rh: int = r[3]
		var want := rng.randi_range(1, 3)
		var tries := 0
		while want > 0 and tries < 20:
			tries += 1
			var x := rng.randi_range(rx + 1, rx + rw - 2)
			var y := ry + rh - 2
			while y > ry and fg[y][x] != 0:
				y -= 1
			if fg[y][x] != 0 or fg[y - 1][x] != 0:
				continue
			var fl: int = fg[y + 1][x]
			if fl == 0:
				continue
			var c := Vector2i(x, y)
			if absi(c.x - spawn.x) <= 2 or c == exit_cell or torches.has(c) or workbenches.has(c) or lanterns.has(c):
				continue
			var dup := false
			for px0 in placed_x:
				if absf(float(px0) - (x + 0.5) * TILE) < TILE:
					dup = true
			if dup:
				continue
			var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var pid := next_id
			next_id += 1
			var roll := rng.randi_range(0, 99)
			want -= 1
			placed_x.append((x + 0.5) * TILE)
			if _props_broken.has(pid):
				skipped += 1
				continue
			var pr2: Node2D = PROP_SCRIPT.new()
			pr2.setup(k, self)
			pr2.position = Vector2((x + 0.5) * TILE, (y + 1) * TILE - pr2.half.y - 0.01)
			pr2.set_meta("loot_roll", roll)
			pr2.set_meta("prop_id", pid)
			pr2.set_meta("spawn_pos", pr2.position)
			if _props_moved.has(pid):
				pr2.position = _props_moved[pid]
			add_child(pr2)
			move_child(pr2, player.get_index())
			phys_props.append(pr2)
	print("DEEPFALL_PROPS spawned=%d skipped_broken=%d" % [phys_props.size(), skipped])

func prop_broken(pr: Node2D) -> void:
	phys_props.erase(pr)
	_props_smashed += 1
	if pr.has_meta("prop_id"):
		_props_broken[int(pr.get_meta("prop_id"))] = true
		_props_moved.erase(int(pr.get_meta("prop_id")))
	var roll: int = int(pr.get_meta("loot_roll", 0))
	var col := Color(0.62, 0.42, 0.22)
	var msg := ""
	match String(pr.kind):
		"crate":
			inv["wood"] += 2
			msg = "+2 Wood"
		"barrel":
			inv["wood"] += 1
			if roll < 50:
				torches_held += 1
				msg = "+1 Wood, +1 Torch"
			else:
				inv["coal"] += 1
				msg = "+1 Wood, +1 Coal"
		"pot":
			col = Color(0.75, 0.42, 0.3)
			if roll < 35:
				inv["gold"] += 1
				msg = "+1 Gold"
			elif roll < 70:
				inv["coal"] += 1
				msg = "+1 Coal"
			else:
				torches_held += 1
				msg = "+1 Torch"
	if fx != null:
		fx.burst(pr.position, col, 22, 420.0, 1500.0, 9.0, 0.9)
		fx.flyer(pr.position, Color(1.0, 0.85, 0.4), msg)
		fx.shake(5.0)
		fx.sfx("prop_break")
		fx.rumble(40)
	log_event("Smashed a %s: %s" % [pr.kind, msg])
	print("DEEPFALL_PROP_BROKEN kind=%s loot=%s" % [pr.kind, msg])
	save_game("prop")

func prop_landed(pr: Node2D, impact: float) -> void:
	# A prop dropped from height crushes enemies under it.
	if fx != null:
		fx.burst(pr.position + Vector2(0, pr.half.y), Color(0.6, 0.55, 0.5), 8, 200.0)
		fx.shake(minf(8.0, impact / 150.0))
	for e in enemies.duplicate():
		if is_instance_valid(e) and Rect2(e.position - Vector2(e.half_w, e.half_h), Vector2(e.half_w, e.half_h) * 2.0).intersects(pr.rect().grow(4.0)):
			e.take_hit(int(impact / 40.0), pr.position.x, Vector2(0, -300))

func prop_support_y(pr: Node2D, prev_bot: float) -> float:
	# Top of another prop directly under `pr` (props stack), or -1e9.
	var best := -1e9
	for o in phys_props:
		if o == pr or not is_instance_valid(o):
			continue
		var r: Rect2 = o.rect()
		if absf(o.position.x - pr.position.x) < (o.half.x + pr.half.x) * 0.8 and prev_bot <= r.position.y + 2.0:
			if best < -1e8 or r.position.y < best:
				best = r.position.y
	return best

func slam_impact(pos: Vector2) -> void:
	# Ground slam shockwave: knocks enemies away + up, launches and
	# damages props, breaks pots, and shakes the screen.
	if fx != null:
		fx.burst(pos, Color(0.85, 0.8, 0.7), 26, 520.0, 1600.0, 8.0, 0.7, 0.3)
		fx.shake(12.0)
		fx.hitstop(0.05)
		fx.sfx("slam")
		fx.rumble(120)
	for e in enemies.duplicate():
		if not is_instance_valid(e):
			continue
		var d: Vector2 = e.position - pos
		if d.length() < 170.0:
			var dir := 1.0 if d.x >= 0.0 else -1.0
			e.take_hit(10, pos.x, Vector2(dir * 420.0, -380.0))
			if fx != null:
				fx.float_text(e.position + Vector2(0, -50), "10", Color(1, 0.95, 0.6))
	for pr in phys_props.duplicate():
		if not is_instance_valid(pr):
			continue
		var dp: Vector2 = pr.position - pos
		if dp.length() < 170.0:
			var dir2 := 1.0 if dp.x >= 0.0 else -1.0
			pr.take_hit(1, pos, Vector2(dir2 * 320.0, -420.0))
	log_event("Ground slam!")


# --- Phase 11 self-test: simulated multi-touch play session ---

func _t11_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _t11_drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	Input.parse_input_event(ev)

func _t11_wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _t11_shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshot_p11_%s.png" % name)
	print("DEEPFALL_P11_SHOT %s" % name)

func _spawn_test_prop(kind: String, c: Vector2i) -> Node2D:
	var pr: Node2D = PROP_SCRIPT.new()
	pr.setup(kind, self)
	pr.position = Vector2((c.x + 0.5) * TILE, (c.y + 1) * TILE - pr.half.y - 0.01)
	add_child(pr)
	move_child(pr, player.get_index())
	phys_props.append(pr)
	return pr

func _run_selftest_p11() -> void:
	await _run_selftest_p13_pre()
	var tu: Node = get_node("TouchUI")
	var vs: Vector2 = get_viewport().get_visible_rect().size
	await _t11_wait(0.6)
	# 1. floating move stick (anywhere on the left half)
	var x0: float = player.position.x
	_t11_touch(0, Vector2(300, 420), true)
	_t11_drag(0, Vector2(380, 420))
	await _t11_wait(0.35)
	print("DEEPFALL_P11 move touch_move=%.2f dx=%.1f (expect >0.9, >40)" % [player.touch_move, player.position.x - x0])
	# 2. JUMP with a SECOND finger while the stick is held
	var jb: Control = tu.get_node("JumpButton")
	var jc: Vector2 = jb.position + jb.size * 0.5
	var y0: float = player.position.y
	_t11_touch(1, jc, true)
	await _t11_wait(0.2)
	print("DEEPFALL_P11 multitouch_jump rose=%.1f vel_y=%.0f (expect >30)" % [y0 - player.position.y, player.vel.y])
	await _t11_shot("jump")
	_t11_touch(1, jc, false)
	_t11_touch(0, Vector2(380, 420), false)
	await _t11_wait(0.9)
	print("DEEPFALL_P11 released touch_move=%.2f on_ground=%s" % [player.touch_move, str(player.on_ground)])
	# 3. knockback is real now
	var kx: float = player.position.x
	player.take_hit(1, player.position.x - 30.0)
	await _t11_wait(0.3)
	print("DEEPFALL_P11 knockback dx=%.1f (expect > 20)" % (player.position.x - kx))
	player.hp = player.max_hp
	await _t11_wait(0.8)
	# 4. aim stick DOWN with the pickaxe mines the block below
	set_tool("pickaxe")
	var sp0: Vector2i = data["spawn"]
	player.respawn_at(Vector2((sp0.x - 1.5) * TILE, (sp0.y + 0.5) * TILE))
	await _t11_wait(0.6)
	var below: Vector2i = _aim_probe(Vector2(0, 1))["cell"]
	var t_before: int = fg[below.y][below.x] if below.x >= 0 else -1
	_t11_touch(2, Vector2(vs.x * 0.7, 300), true)
	_t11_drag(2, Vector2(vs.x * 0.7, 380))
	await _t11_wait(0.15)
	await _t11_shot("mine")
	await _t11_wait(0.75)
	_t11_touch(2, Vector2(vs.x * 0.7, 380), false)
	print("DEEPFALL_P11 aim_mine_down cell=%s before=%d after=%d (expect after 0)" % [str(below), t_before, fg[below.y][below.x]])
	await _t11_wait(1.0)
	# 5. sword swing up-right via the aim stick hits + knocks back a ghoul
	var sb: Control = tu._slot_sword
	_t11_touch(3, sb.position + sb.size * 0.5, true)
	_t11_touch(3, sb.position + sb.size * 0.5, false)
	var gc: Vector2i = player.cell() + Vector2i(1, 0)
	_spawn_one("rock-golem", gc)
	var g: Node2D = enemies[enemies.size() - 1]
	var ghp: int = g.hp
	var gx: float = g.position.x
	_t11_touch(4, Vector2(vs.x * 0.7, 300), true)
	_t11_drag(4, Vector2(vs.x * 0.7 + 80, 300))
	await _t11_wait(0.2)
	await _t11_shot("sword")
	await _t11_wait(0.15)
	_t11_touch(4, Vector2(vs.x * 0.7 + 80, 300), false)
	print("DEEPFALL_P11 sword tool=%s golem_hp %d->%d pushed=%.1f (expect sword, lower, >10)" % [tool, ghp, g.hp, g.position.x - gx])
	g.take_hit(999, player.position.x)
	await _t11_wait(0.5)
	# 6. push a crate, smash a pot
	var sp: Vector2i = data["spawn"]
	player.respawn_at(Vector2((sp.x + 0.5) * TILE, (sp.y + 0.5) * TILE))
	await _t11_wait(0.6)
	var pc: Vector2i = player.cell()
	player.facing = 1
	var crate := _spawn_test_prop("crate", pc + Vector2i(2, 0))
	await _t11_wait(0.4)
	var cx0: float = crate.position.x
	_t11_touch(0, Vector2(300, 420), true)
	_t11_drag(0, Vector2(380, 420))
	await _t11_wait(0.6)
	await _t11_shot("push")
	_t11_touch(0, Vector2(380, 420), false)
	print("DEEPFALL_P11 crate_push dx=%.1f player_overlap=%s (expect >20, false)" % [crate.position.x - cx0, str(player._my_rect().grow(-2).intersects(crate.rect()))])
	var pot := _spawn_test_prop("pot", player.cell() + Vector2i(-1, 0))
	await _t11_wait(0.3)
	var wood0: int = inv["wood"] + inv["coal"] + inv["gold"] + torches_held
	player.attack_cooldown = 0.0
	player.try_attack_dir(Vector2(-1, 0))
	await _t11_wait(0.5)
	print("DEEPFALL_P11 pot_broken=%s loot_delta=%d (expect true, 1)" % [str(not is_instance_valid(pot)), inv["wood"] + inv["coal"] + inv["gold"] + torches_held - wood0])
	# 7. DASH and SLAM buttons
	var db: Control = tu.get_node("DashButton")
	var dx0: float = player.position.x
	_t11_touch(5, db.position + db.size * 0.5, true)
	await _t11_wait(0.12)
	_t11_touch(5, db.position + db.size * 0.5, false)
	print("DEEPFALL_P11 dash dx=%.1f cooldown=%.2f (expect |dx|>50, >0)" % [absf(player.position.x - dx0), player.dash_cooldown])
	await _t11_wait(0.6)
	_spawn_one("miner-ghoul", player.cell() + Vector2i(2, 0))
	var g2: Node2D = enemies[enemies.size() - 1]
	await _t11_wait(0.3)
	var g2hp: int = g2.hp
	var slb: Control = tu.get_node("SlamButton")
	_t11_touch(6, slb.position + slb.size * 0.5, true)
	_t11_touch(6, slb.position + slb.size * 0.5, false)
	await _t11_wait(0.5)
	await _t11_shot("slam")
	print("DEEPFALL_P11 slam ghoul_hp %d->%d (expect lower)" % [g2hp, g2.hp if is_instance_valid(g2) else -1])
	await _t11_wait(1.0)
	await _t11_shot("end")
	print("DEEPFALL_P11 done hp=%d props=%d" % [player.hp, phys_props.size()])
	# --- Phase 12: control settings, enemy art, sound ---
	var g3: Node2D = enemies[0] if not enemies.is_empty() else null
	print("DEEPFALL_P12 enemy_art tex=%s scale=%.1f (expect enemies_px, 3.0)" % [g3._sprite.texture.resource_path if g3 != null else "none", g3._sprite.scale.y if g3 != null else 0.0])
	print("DEEPFALL_P12 sfx loaded=%d volume=%.2f" % [fx._streams.size(), fx.volume])
	var mb: Control = tu.get_node("MenuButton")
	_t11_touch(7, mb.position + mb.size * 0.5, true)
	_t11_touch(7, mb.position + mb.size * 0.5, false)
	await get_tree().process_frame
	print("DEEPFALL_P12 menu panel=%s paused=%s (expect true, true)" % [str(tu._settings_panel.visible), str(get_tree().paused)])
	(tu._sliders["stick_scale"] as HSlider).value = 1.4
	(tu._sliders["button_scale"] as HSlider).value = 1.2
	await _t11_shot("settings")
	var jbtn: Control = tu.get_node("JumpButton")
	print("DEEPFALL_P12 scales stick_r=%.1f jump_radius=%.1f (expect 100.8, 76.8)" % [tu._stick_r, jbtn.radius])
	tu._start_edit()
	var jpos: Vector2 = jbtn.position
	var grab: Vector2 = jbtn.position + jbtn.size * 0.5
	_t11_touch(8, grab, true)
	_t11_drag(8, grab + Vector2(-200, -150))
	_t11_touch(8, grab + Vector2(-200, -150), false)
	await get_tree().process_frame
	await _t11_shot("edit")
	tu._end_edit()
	tu._layout()
	print("DEEPFALL_P12 move_button moved=%s saved=%s (expect true, true)" % [str(jbtn.position.distance_to(jpos) > 100.0), str(FileAccess.file_exists("user://deepfall_settings.json"))])
	(tu._checks["left_handed"] as CheckButton).button_pressed = true
	tu._close_settings()
	await get_tree().process_frame
	_t11_touch(9, Vector2(200, 400), true)
	await get_tree().process_frame
	print("DEEPFALL_P12 left_handed left_touch_is_aim=%s paused=%s (expect true, false)" % [str(tu._aim_active), str(get_tree().paused)])
	_t11_touch(9, Vector2(200, 400), false)
	await _t11_shot("lefthand")
	tu._reset_settings()
	print("DEEPFALL_P12 reset stick_r=%.1f (expect 72)" % tu._stick_r)


# --- Phase 13: run summary card ---

func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	return "%d:%02d" % [m, int(t) % 60]

func _loot_line() -> String:
	var parts: Array = []
	for k in ["gold", "amber", "coal", "stone", "wood", "dirt", "sand", "glass"]:
		if int(inv.get(k, 0)) > 0:
			parts.append("%d %s" % [int(inv[k]), k])
	return "Loot: " + (", ".join(parts) if not parts.is_empty() else "none yet")

func _brag_text() -> String:
	var how := "made it out alive" if _card_reason == "extract" else "fell"
	return "DEEPFALL: my %s %s at depth %d after %s. %d kills, %d ore, %d blocks mined, %d props smashed. %s. Can you dig deeper?" % [
		player.class_display_name, how, _max_depth, _fmt_time(_run_time), kills, ore_collected,
		_mined_cells.size(), _props_smashed, _loot_line()]

func show_run_card(reason: String) -> void:
	if _card != null:
		_card.queue_free()
	_card_reason = reason
	_card_open = true
	get_tree().paused = true
	var tui: Node = get_node_or_null("TouchUI")
	if tui != null:
		tui.call("_release_all")
	_card = CanvasLayer.new()
	_card.layer = 30
	_card.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_card)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vs
	_card.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "RunCard"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.09, 0.97)
	sb.border_color = Color(1.0, 0.78, 0.35) if reason == "extract" else Color(0.85, 0.3, 0.3)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	_card.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.name = "CardTitle"
	title.text = "EXTRACTED!" if reason == "extract" else "YOU FELL"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", sb.border_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "%s   ·   run time %s" % [player.class_display_name, _fmt_time(_run_time)]
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	vb.add_child(hb)
	var pic := TextureRect.new()
	pic.texture = _class_idle_texture(player.class_id)
	pic.custom_minimum_size = Vector2(128, 168)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(pic)
	var grid := GridContainer.new()
	grid.name = "CardStats"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	hb.add_child(grid)
	for row in [["Deepest", "%d" % _max_depth], ["Kills", "%d" % kills], ["Ore", "%d" % ore_collected],
			["Blocks mined", "%d" % _mined_cells.size()], ["Props smashed", "%d" % _props_smashed], ["Deaths", "%d" % _deaths]]:
		var kl := Label.new()
		kl.text = String(row[0])
		kl.add_theme_font_size_override("font_size", 20)
		kl.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
		grid.add_child(kl)
		var vl := Label.new()
		vl.text = String(row[1])
		vl.add_theme_font_size_override("font_size", 24)
		vl.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		grid.add_child(vl)
	var loot := Label.new()
	loot.name = "CardLoot"
	loot.text = _loot_line()
	loot.add_theme_font_size_override("font_size", 17)
	loot.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	loot.autowrap_mode = TextServer.AUTOWRAP_WORD
	loot.custom_minimum_size = Vector2(520, 0)
	vb.add_child(loot)
	var foot := Label.new()
	foot.text = "DEEPFALL  ·  Relics of the Below"
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(foot)
	var btns := HBoxContainer.new()
	btns.name = "CardButtons"
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	vb.add_child(btns)
	var specs: Array = [["SHARE", _share_card], ["KEEP DIGGING", _close_run_card]]
	if reason == "extract":
		specs.append(["NEW RUN", _card_new_run])
	for spec in specs:
		var b := Button.new()
		b.name = "Card" + String(spec[0]).replace(" ", "")
		b.text = String(spec[0])
		b.custom_minimum_size = Vector2(170, 58)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(spec[1])
		btns.add_child(b)
	_card_status = Label.new()
	_card_status.name = "CardStatus"
	_card_status.add_theme_font_size_override("font_size", 14)
	_card_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	_card_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_card_status)
	panel.reset_size()
	panel.position = ((vs - panel.size) * 0.5).floor()
	if fx != null:
		fx.sfx("pickup" if reason == "extract" else "enemy_die", 0.0)
	print("DEEPFALL_RUN_CARD reason=%s depth=%d kills=%d ore=%d mined=%d props=%d" % [
		reason, _max_depth, kills, ore_collected, _mined_cells.size(), _props_smashed])

func _share_card() -> void:
	# Render just the card to a PNG (buttons hidden), save it on the
	# device, and put the brag text on the clipboard to paste anywhere.
	var panel: Control = _card.get_node("RunCard")
	var btns: Control = panel.get_node("VBoxContainer/CardButtons") if panel.has_node("VBoxContainer/CardButtons") else null
	var rect := panel.get_global_rect()
	if btns != null:
		btns.modulate.a = 0.0
	_card_status.text = ""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if btns != null:
		btns.modulate.a = 1.0
	var k: Vector2 = Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var r := Rect2i(Vector2i(rect.position * k), Vector2i(rect.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var card_img := img.get_region(r)
	var saved := ProjectSettings.globalize_path("user://deepfall_run_card.png")
	card_img.save_png("user://deepfall_run_card.png")
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "" and card_img.save_png(pics.path_join("deepfall_run_card.png")) == OK:
		saved = pics.path_join("deepfall_run_card.png")
	DisplayServer.clipboard_set(_brag_text())
	_card_status.text = "Card image saved (%s). Brag text copied: paste it in any chat or post." % saved.get_file()
	print("DEEPFALL_RUN_CARD_SHARED path=%s size=%s" % [saved, str(card_img.get_size())])

func _close_run_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	_card_open = false
	get_tree().paused = false
	if player.dead:
		_respawn_timer = 0.05

func _card_new_run() -> void:
	_close_run_card()
	new_run()

# --- Phase 13 self-test (runs first inside --selftest-p11) ---

func _run_selftest_p13_pre() -> void:
	await _t11_wait(0.4)
	# 1. physical loot: kill a ghoul, drop pops out, then is collected
	var c0: int = inv["coal"] + inv["stone"]
	_spawn_one("miner-ghoul", player.cell() + Vector2i(2, 0))
	var g: Node2D = enemies[enemies.size() - 1]
	g.take_hit(999, player.position.x)
	await get_tree().physics_frame
	var drops := get_children().filter(func(n): return n.get_script() == LOOT_SCRIPT)
	var corpses := get_children().filter(func(n): return n.get_script() == CORPSE_SCRIPT)
	print("DEEPFALL_P13 death_anim corpses=%d drops=%d inv_unchanged=%s (expect 1, 1, true)" % [corpses.size(), drops.size(), str(inv["coal"] + inv["stone"] == c0)])
	await _t11_wait(0.25)
	await _t11_shot("death")
	await _t11_wait(1.6)
	print("DEEPFALL_P13 loot_collected inv_delta=%d corpse_gone=%s (expect 1, true)" % [inv["coal"] + inv["stone"] - c0, str(get_children().filter(func(n): return n.get_script() == CORPSE_SCRIPT).is_empty())])
	# 2. smashed prop persists through save + reload
	var target: Node2D = null
	for pr in phys_props:
		if pr.has_meta("prop_id"):
			target = pr
			break
	var tid: int = int(target.get_meta("prop_id"))
	var before := phys_props.size()
	target.take_hit(99, target.position + Vector2(-10, 0))
	target.take_hit(99, target.position + Vector2(-10, 0))
	target.take_hit(99, target.position + Vector2(-10, 0))
	await get_tree().physics_frame
	save_game("p13")
	_rebuild_world(true)
	await get_tree().physics_frame
	var still_gone := true
	for pr in phys_props:
		if int(pr.get_meta("prop_id", -1)) == tid:
			still_gone = false
	print("DEEPFALL_P13 prop_persist id=%d before=%d after_reload=%d gone=%s smashed=%d (expect true, 1+)" % [tid, before, phys_props.size(), str(still_gone), _props_smashed])
	# 3. ambience running, deeper = lower drone
	for _i in range(400):
		fx.update_ambience(0.0)
	var p_top: float = fx._amb["drone"].pitch_scale
	for _i in range(400):
		fx.update_ambience(1.0)
	print("DEEPFALL_P13 ambience playing=%s drone_pitch top=%.2f deep=%.2f rumble_db=%.1f (expect true, 1.00, <0.8)" % [str(fx._amb["drone"].playing), p_top, fx._amb["drone"].pitch_scale, fx._amb["rumble"].volume_db])
	# 4. run summary card on death, share, keep digging
	_max_depth = maxi(_max_depth, 21)
	player.hp = 1
	player.hurt_timer = 0.0
	player.take_hit(5, player.position.x - 10.0)
	await _t11_wait(1.2)
	print("DEEPFALL_P13 card_open=%s paused=%s (expect true, true)" % [str(_card_open), str(get_tree().paused)])
	await _t11_shot("card")
	await _share_card()
	print("DEEPFALL_P13 share clipboard_ok=%s file=%s" % [str(DisplayServer.clipboard_get().begins_with("DEEPFALL")), str(FileAccess.file_exists("user://deepfall_run_card.png"))])
	_close_run_card()
	await _t11_wait(0.5)
	print("DEEPFALL_P13 after_card dead=%s paused=%s (expect false, false)" % [str(player.dead), str(get_tree().paused)])
	await _t11_wait(0.5)
