# map_gen.gd — DEEPFALL Phase 1 generation.
# Port of deepfall_map_gen.py, adapted to the Terraria block-grid model:
#  fg  = foreground mineable blocks (collision), 0 = air
#  wall = background wall grid (NO collision, rendered behind air)
#  platform cells are one-way (collision only when falling onto them).
# Tile ids (fg): 0 air, 1 dirt, 2 grass-dirt, 3 stone, 4 gold-ore, 5 amber-ore,
#  6 wood, 7 wood-platform, 8 brick, 9 mossy-stone, 10 cracked-stone,
#  11 sand, 12 obsidian, 13 coal-ore (Phase 7).
#  Wall: 0 none, 1 dirt-wall, 2 cave-wall-dark.
# Same seed = same world (single RandomNumberGenerator, fixed call order).
extends RefCounted
class_name DeepfallMapGen

const W := 80
const H := 45
const AIR := 0
const PLATFORM := 7

static func generate(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var fg: Array = []
	var wall: Array = []
	for _y in range(H):
		var fr: Array = []; fr.resize(W); fr.fill(3)  # stone default
		var wr: Array = []; wr.resize(W); wr.fill(0)
		fg.append(fr); wall.append(wr)
	# --- rooms (non-overlapping, sorted left -> right) ---
	var rooms: Array = []
	var tries := 0
	while rooms.size() < 14 and tries < 800:
		tries += 1
		var rw := rng.randi_range(8, 16)
		var rh := rng.randi_range(6, 10)
		var rx := rng.randi_range(2, W - rw - 2)
		var ry := rng.randi_range(2, H - rh - 2)
		var overlap := false
		for o in rooms:
			if not (rx > o[0] + o[2] + 1 or rx + rw < o[0] - 1 or ry > o[1] + o[3] + 1 or ry + rh < o[1] - 1):
				overlap = true; break
		if overlap:
			continue
		rooms.append([rx, ry, rw, rh])
	rooms.sort_custom(func(a, b): return a[0] < b[0])
	var carve_room := func(r: Array) -> void:
		for yy in range(r[1], r[1] + r[3] - 1):  # leave bottom row solid = floor
			for xx in range(r[0], r[0] + r[2]):
				fg[yy][xx] = AIR
	var corridor := func(a: Array, b: Array) -> void:
		var ax: int = int(a[0]) + int(a[2]) / 2; var ay: int = int(a[1]) + int(a[3]) / 2
		var bx: int = int(b[0]) + int(b[2]) / 2; var by: int = int(b[1]) + int(b[3]) / 2
		for xx in range(min(ax, bx), max(ax, bx) + 1):
			for dy in range(3):
				if ay + dy < H:
					fg[ay + dy][xx] = AIR
		for yy in range(min(ay, by), max(ay, by) + 1):
			for dx in range(3):
				if bx + dx < W:
					fg[yy][bx + dx] = AIR
	for r in rooms:
		carve_room.call(r)
	# --- spanning tree + 3 loop corridors ---
	var connected: Array = [rooms[0]]
	for r in rooms.slice(1):
		var near: Array = connected[0]
		var best := 99999
		for o in connected:
			var d: int = abs(int(o[0]) - int(r[0])) + abs(int(o[1]) - int(r[1]))
			if d < best:
				best = d; near = o
		corridor.call(near, r)
		connected.append(r)
	for _i in range(3):
		var a: Array = rooms[rng.randi_range(0, rooms.size() - 1)]
		var b: Array = rooms[rng.randi_range(0, rooms.size() - 1)]
		if abs(a[0] - b[0]) > 20:
			corridor.call(a, b)
	# --- platforms in tall rooms ---
	for r in rooms:
		if r[3] >= 8:
			var px: int = int(r[0]) + 2
			while px < r[0] + r[2] - 2:
				var py: int = int(r[1]) + 3
				if fg[py][px] == AIR:
					for dx in range(3):
						if px + dx < r[0] + r[2]:
							fg[py][px + dx] = PLATFORM
				px += 5
	# --- ore veins: connected random walks in solid cells above rooms ---
	var ore_count := 0
	for i in range(rooms.size()):
		if i == 0:
			continue  # never in spawn room
		var r: Array = rooms[i]
		for _v in range(rng.randi_range(1, 2)):
			var vx: int = int(r[0]) + rng.randi_range(0, int(r[2]) - 1)
			var vy: int = int(r[1]) - 1
			for _s in range(rng.randi_range(4, 9)):
				if vx >= 0 and vx < W and vy >= 0 and vy < H and fg[vy][vx] != AIR and fg[vy][vx] != PLATFORM:
					fg[vy][vx] = 4 if rng.randi_range(0, 1) == 0 else 5
					ore_count += 1
				vx += rng.randi_range(-1, 1)
				vy += rng.randi_range(0, 1)
	# --- Phase 7: coal + wood veins (connected random walks, same shape
	# as the ore veins, AFTER them so the ore count / READY line is
	# untouched). Solid-to-solid only (never air/platform/ore), so
	# topology, flood-fill and spawn/exit are unchanged. Coal and wood
	# are the Phase 7 crafting materials: coal-ore (13) and wood (6)
	# were never generated before this phase — wood blocks in
	# particular existed as a tile id but with zero cells in the world,
	# which would have made torch crafting impossible.
	var coal_count := 0
	for _cv in range(8):
		var cr: Array = rooms[rng.randi_range(1, rooms.size() - 1)]
		var cx: int = int(cr[0]) + rng.randi_range(0, int(cr[2]) - 1)
		var cy: int = int(cr[1]) - 1
		for _s in range(rng.randi_range(4, 7)):
			if cx >= 0 and cx < W and cy >= 0 and cy < H and fg[cy][cx] != AIR and fg[cy][cx] != PLATFORM and fg[cy][cx] != 4 and fg[cy][cx] != 5 and fg[cy][cx] != 13:
				fg[cy][cx] = 13
				coal_count += 1
			cx += rng.randi_range(-1, 1)
			cy += rng.randi_range(-1, 1)
	var wood_count := 0
	for _wv in range(10):
		var wr2: Array = rooms[rng.randi_range(1, rooms.size() - 1)]
		var wx: int = int(wr2[0]) + rng.randi_range(0, int(wr2[2]) - 1)
		var wy: int = int(wr2[1]) - 1
		for _s in range(rng.randi_range(6, 10)):
			if wx >= 0 and wx < W and wy >= 0 and wy < H and fg[wy][wx] != AIR and fg[wy][wx] != PLATFORM and fg[wy][wx] != 4 and fg[wy][wx] != 5 and fg[wy][wx] != 13 and fg[wy][wx] != 6:
				fg[wy][wx] = 6
				wood_count += 1
			wx += rng.randi_range(-1, 1)
			wy += rng.randi_range(-1, 1)
	# --- spawn / exit ---
	var spawn_room: Array = rooms[0]
	var exit_room: Array = rooms[rooms.size() - 1]
	var spawn := Vector2i(spawn_room[0] + spawn_room[2] / 2, spawn_room[1] + spawn_room[3] - 2)
	var exit_cell := Vector2i(exit_room[0] + exit_room[2] / 2, exit_room[1] + exit_room[3] - 2)
	# brick floor under the exit room
	for xx in range(exit_room[0], exit_room[0] + exit_room[2]):
		fg[exit_room[1] + exit_room[3] - 1][xx] = 8
	# --- validation: flood fill from spawn over air + platforms ---
	var reachable := func() -> Dictionary:
		var seen := {}
		var stack: Array = [spawn]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			if seen.has(c) or c.x < 0 or c.x >= W or c.y < 0 or c.y >= H:
				continue
			var t: int = fg[c.y][c.x]
			if t != AIR and t != PLATFORM:
				continue
			seen[c] = true
			stack.append(Vector2i(c.x + 1, c.y)); stack.append(Vector2i(c.x - 1, c.y))
			stack.append(Vector2i(c.x, c.y + 1)); stack.append(Vector2i(c.x, c.y - 1))
		return seen
	var seen: Dictionary = reachable.call()
	var unreached: Array = []
	for r in rooms:
		var c := Vector2i(r[0] + r[2] / 2, r[1] + r[3] / 2)
		if not seen.has(c):
			unreached.append(r)
	for r in unreached:  # repair: direct corridor from spawn room
		corridor.call(spawn_room, r)
	seen = reachable.call()
	var reached := 0
	for r in rooms:
		if seen.has(Vector2i(r[0] + r[2] / 2, r[1] + r[3] / 2)):
			reached += 1
	# --- solid tile variety + wall grid (behind air only) ---
	for yy in range(H):
		for xx in range(W):
			if fg[yy][xx] == 3:
				if yy < 5:
					fg[yy][xx] = 11 if (xx * 7 + yy) % 5 == 0 else 1
				else:
					# Moss clusters, not scattered singles: the condition
					# depends on the 3x3 block, so a whole block turns
					# mossy together (topology unchanged — still solid).
					var h := (xx * 31 + yy * 17) % 20
					var bx := xx / 3; var by := yy / 3
					if (bx * 7 + by * 11 + seed) % 10 == 0: fg[yy][xx] = 9
					elif h == 1: fg[yy][xx] = 10
					elif yy > 35 and h == 2: fg[yy][xx] = 12
			if fg[yy][xx] == AIR or fg[yy][xx] == PLATFORM:
				wall[yy][xx] = 2 if yy > 25 else 1
	# grass on the topmost solid row where the cell above is air
	for yy in range(1, H):
		for xx in range(W):
			if fg[yy][xx] == 1 and fg[yy - 1][xx] == AIR:
				fg[yy][xx] = 2
	return {"fg": fg, "wall": wall, "rooms": rooms, "spawn": spawn,
		"exit": exit_cell, "ore": ore_count, "coal": coal_count, "wood": wood_count,
		"rooms_total": rooms.size(),
		"rooms_reached": reached, "connected": reached == rooms.size()}
