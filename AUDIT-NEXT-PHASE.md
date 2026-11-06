# DEEPFALL — Audit for the Next Improvement Phase

**Date:** 2026-11-04 (audit time; a twin-stick control job was editing this tree concurrently)
**Scope:** audit only. No existing game file was edited to produce this document.
**Project audited:** `~/workspace/goals/game-off-2026-entry/deepfall-game/`
**Staged assets audited:** `~/workspace/asset-pipeline/staging/deepfall/`
**Sources of truth in this document:** file paths and code read at audit time.
Anything without a file reference below is specification, footage, or a
proposal — not an implemented fact.

**How to read the status labels:**
- **IN GAME** — code or an asset in the project tree, verified by reading it.
- **STAGED ONLY** — art exists under `staging/deepfall/` but is not wired
  into any scene or script in the project.
- **SPEC ONLY** — written in `VISUAL-SPEC.md`, `PHASE1-README.md`, or the
  implementation spec, with no matching code or asset in the project.
- **NOT PRESENT** — no code, asset, or spec evidence found.

---

## 1. Implemented vs specified vs missing

### 1.1 Generation

| Item | Status | Evidence |
|---|---|---|
| Seeded world, same seed = same world | IN GAME | `scripts/map_gen.gd`: single `RandomNumberGenerator`, fixed call order; `scripts/main.gd` prints `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31 spawn=(7, 20) exit=(73, 9) connected=true` |
| Single region, Forgotten Mines, 80 × 45 cells | IN GAME | `map_gen.gd`: `W := 80`, `H := 45`; all rooms carved from solid stone |
| Room graph + spanning-tree corridors + 3 loop corridors | IN GAME | `map_gen.gd`: rooms 8–16 × 6–10 cells, sorted left-to-right, 3-wide corridors, 3 extra loop corridors |
| Flood-fill validation + repair | IN GAME | `map_gen.gd`: flood fill from spawn over air + platforms; unreached rooms get a direct corridor from the spawn room; `connected` = rooms reached == rooms total |
| Foreground mineable blocks / background wall grid / one-way platforms | IN GAME | `map_gen.gd` header + `main.gd`: fg ids 1–12, wall ids 1–2, platform id 7; wall rendered behind air only; platforms collidable only when falling onto them (`player.gd` `_platform`) |
| Ore veins as connected walks | IN GAME | `map_gen.gd`: 1–2 veins per non-spawn room, 4–9 steps, gold (4) or amber (5) only |
| Ore clustering / deposits as landmarks | NOT PRESENT | Veins are independent random walks. No cluster origin, no minimum cluster size, no landmark rule. See §3.3 for the rule to add |
| Variation budget / feature clustering / chunk continuity | NOT PRESENT | No budget counters, no cluster rules, no chunk code anywhere in `scripts/*.gd`. See §3.2–§3.4 |
| Chunk streaming | NOT PRESENT | One whole 80 × 45 world is generated and rendered at once. `PHASE1-README.md` states this plainly: "single seeded region now; chunk streaming is a later phase." No chunk loader, no stream/unload code, no chunk-boundary handling |
| Persistent world with edit deltas | NOT PRESENT | Mining, torch placement, and damage live in `main.gd` memory (`fg`, `torches`, `mine_damage`) and are lost on quit. No save file, no delta format |
| Save / reload | NOT PRESENT | The only "save" in code is the `--screenshot` flag writing `screenshot.png` (`main.gd`). No player/world save, no reload path |
| Other regions (Fungal Hollows, Sunken Works, Ember Fault, Hollow City, Black Deep) | SPEC ONLY | Named in `PHASE1-README.md` honest-limits list as later phases. No region code, no region switching |

### 1.2 Terrain and tiles

| Item | Status | Evidence |
|---|---|---|
| 64 px gameplay tiles, 14 materials in game | IN GAME | `assets/tiles/` (dirt, grass-dirt, stone, gold-ore, amber-ore, wood, wood-platform, brick, mossy-stone, cracked-stone, sand, obsidian, cave-wall-dark, dirt-wall); `main.gd` `TILE := 64`, `TILE_NAMES` |
| 4 deterministic variants per material (16 for stone/dirt) | IN GAME | `assets/tiles2/*_v0..v3.png`, `assets/atlas3/rock_0..15.png`, `assets/atlas3/dirt_0..15.png`; `main.gd` `_variant()` = pure function of (seed, cell, material) — no render-time randomness |
| Edge + outer-corner overlays, re-tiled on mining | IN GAME | `assets/edge_*.png`, `assets/corner_*.png`; `main.gd` `_edge_for_cell()` (corners take priority), `_update_edge()`, and the 8-neighbour re-tile loop in `_mine_at()` |
| 2-hit mining with crack overlay | IN GAME | `main.gd` `_mine_at()` + `assets/damage.png` + `DamageLayer`: first hit shows the crack, second breaks the block |
| 3 damaged stages (intact → cracked → heavily cracked) | SPEC ONLY | `VISUAL-SPEC.md` §3.1 requires 3 stages. In game there is exactly one crack overlay and 2-hit mining. A third stage would need new art *and* a mining-hit change — do not claim it exists |
| Rock ↔ dirt transition tiles | SPEC ONLY | `VISUAL-SPEC.md` §3.1/§4. Dirt never abuts rock with a blend in game; the boundary is a hard cell change plus the generic edge overlay |
| Inner (concave) corners | NOT PRESENT | The 8 edge/corner overlays cover straight edges and convex (outer) corners only. A solid cell with a diagonal air neighbour and solid orthogonal neighbours gets no special tile |
| True seamless atlas (no internal brick divisions) | NOT PRESENT | `PHASE1-README.md` Phase 2/3 notes say this plainly: the procedural flip pass reduces repetition but cannot remove the staged tiles' panel read; the rock field still carries internal stone divisions |
| Godot `TileMapLayer` terrain sets / peering bits | NOT PRESENT | The tileset is built at runtime from a stitched atlas image (`main.gd` `_build_tileset()`). There is no `TileSet` terrain set, no peering-bit assignment. The edge layer is a manual overlay, not autotiling |
| Slopes / half-blocks with mirrored collision | STAGED ONLY | `staging/deepfall/tiles-real/terraria-slopes/` (slopes, half-blocks, stairs, ramps). No slope code, no slope collision in `player.gd`; platforms are full-cell one-way tiles, not slopes. The two ramp cells are beams, not platforms (`VISUAL-SPEC.md` §4.4) |
| 112 Terraria tiles total | STAGED ONLY | `staging/deepfall/tiles-real/`: 16 base + 16 new types + 16 slopes + 64 biome/crafted (16 mines/fungal + 16 sunken/ember + 16 city/deep + 16 crafted). Only the 14 Forgotten Mines materials are in the game |
| Slopes facing one direction, flip for the other | SPEC ONLY | `VISUAL-SPEC.md` §4.4. No flip code exists because slopes are not in the game at all |

### 1.3 Backgrounds, depth, lighting

| Item | Status | Evidence |
|---|---|---|
| `CanvasModulate` dark-blue ambient | IN GAME | `scenes/main.tscn`: `Ambient` node, `Color(0.45, 0.52, 0.68, 1)` — note: this is **not** the spec's literal `#0B1420` as a multiplier. `PHASE1-README.md` records why: that value renders near-black even with lights |
| `PointLight2D` torches, warm, ±5% flicker, 7-tile radius | IN GAME | `main.gd` `_place_torch()`: colour (1.0, 0.70, 0.36), energy 1.0, gradient texture 896 px = 7 tiles, flicker `1.0 + 0.05 * sin(time * 5.0 + i * 1.7)` in `_process()` |
| Amber exit-beacon light (5 tiles) and cyan crystal lights (3 tiles) | IN GAME | `main.gd`: beacon light, texture scale 320/448; crystal lights energy 0.6, texture scale 192/448, placed in air cells beside ore cells — but only 3 clusters (ore-list picks 0, 7, 14), not a general crystal system |
| Selective `LightOccluder2D` | IN GAME, narrow | `main.gd` `_render_props()`: occluders on timber posts only. No terrain occluders. `PHASE1-README.md` warns the post shadow wedge can darken gameplay area |
| Background cave silhouette + distant blue-lit opening | IN GAME, partial | `main.gd` `_render_background()`: a flat polygon silhouette, the `assets/atlas3/cave-silhouettes.png` sprite centred on spawn (dimmed 0.55/0.6/0.7), and a blue diamond opening at (4600, 700) with a cyan light |
| Parallax background (factor ~0.5) and foreground framing above the player | SPEC ONLY | `VISUAL-SPEC.md` §5.4 requires both. In game, the background is a static world-space layer (parallax was explicitly skipped to avoid fighting camera limits and revealing void), and foreground framing is only two bottom-corner `ColorRect` wedges (`scenes/main.tscn` `FrameBL`/`FrameBR`) that never sit above the player and are never gameplay-clearance-checked |
| Torch light illuminating stone/timber/moss (material response) | PARTIAL | Lights are real `PointLight2D` nodes, so nearby tiles are lit by construction — but there is no per-material response, no ember particles, no light falloff tuning beyond the squared gradient. Torch pools read ~4 tiles visually, not the full 7-tile texture radius (`PHASE1-README.md`) |
| Ember / dust / spore particles | STAGED ONLY | `staging/deepfall/effects/` holds 11 procedural effect GIFs (ember-burst, smoke-puff, etc.). No particle system is wired into the game |

### 1.4 Characters and animation

| Item | Status | Evidence |
|---|---|---|
| Tech soldier playable, idle / walk / shoot wired | IN GAME | `assets/player_anim/idle_0..8.png` (9 frames, 4 fps), `walk_0..8.png` (9 frames, 8 fps), `shoot_0..4.png` (5 frames, 10 fps, triggered by mining); `player.gd` `_update_animation()`; bottom-centre anchor on a 128×195 canvas, feet at the collision-box bottom |
| Landing squash | IN GAME | `player.gd`: 0.15 s squash (`scale` 0.55 × 0.42) on landing — code, not art |
| Distinct fall pose | NOT PRESENT | `player.gd` comment states it honestly: air pose reuses idle frame 4. No fall set exists in staging for the in-game strip |
| Walk with large leg travel (not a shuffle) | STAGED ONLY, not wired | `staging/deepfall/atlas-art/sliced/tech-walk-cycle/`, `red-walk-cycle/`, `mage-walk-cycle/` (4 frames each, sliced and QC'd) and `tech-fall-land/` (fall/land, with a front-facing frame-3 angle jump caveat). The in-game walk strip still reads as a shuffle (`PHASE1-README.md`) |
| Crouch / climb / melee / swim | STAGED ONLY | `staging/deepfall/multiframe/`: crouch complete for all 5 characters, climb for red/mage/miner/skeleton (ladders baked in; tech climb missing — generation failed, do-not-retry), melee complete for all 5, swim complete for all 5 (with front-facing frame-2 caveats on red/miner/skeleton, upright wading on mage). None wired into `player.gd` |
| Other starting classes (hooded mage, red soldier) | STAGED ONLY | `staging/deepfall/cleaned-regen/` holds 207 frames across 5 characters. In game, only tech soldier is playable; mage/red are design notes, not scenes |
| Skeleton hero | STAGED ONLY | `staging/deepfall/cleaned-regen/skeleton-hero/` + multiframe sets. Per the implementation spec it is a separate/unlockable hero, not a fourth starting class, and it is not in the game |
| Enemies (24 staged) with walk/attack cycles | STAGED ONLY | `staging/deepfall/enemies/` (24 single-pose sprites) + `multiframe/` walk/attack GIFs for all 24 (mimic attack best 3/4; hollow knight/archer walk 3/4; all others 4/4). No enemy scene, no AI, no combat, no health/damage code in `scripts/*.gd` |
| Crafting, inventory, combat | NOT PRESENT | No code, no UI, no item data in the project. The 383 staged item sprites (`items-user*`) are not referenced by any script |

### 1.5 Controls

| Item | Status | Evidence |
|---|---|---|
| Desktop: A/D move, Space/W jump, E mine, click mine, T torch, click torch pickup | IN GAME | `player.gd`, `main.gd` `_input()` / `_process()`; HUD hint text in `main.gd` |
| Coyote time 0.12 s, jump buffer 0.12 s, double jump | IN GAME | `player.gd`: `COYOTE := 0.12`, `BUFFER := 0.12`, `jumps_left := 2`; speed 260, jump velocity −620, gravity 1800, terminal velocity 1200 |
| Grid collision, one-way platforms, world-border solid | IN GAME | `player.gd` `_move_axis()`, `_solid()`, `_platform()`; collision box half-width 14, half-height 40 |
| Twin-stick touch controls | IN TREE, APK UNVERIFIED | `scripts/touch_ui.gd` as read at audit time **is** the twin-stick implementation: left stick (160 px, bottom-left, 0.25 dead zone, x = analog move, push up past 0.6 = jump edge with −0.35 release so a second flick double-jumps), right stick (8-way mine past 0.5 magnitude, same 0.25 s cooldown), one kept TORCH button. **But:** the APK on disk at audit time is `exports/deepfall-phase1-debug.apk`, 59,735,155 bytes, dated 10:21 — byte-identical in size to the pre-twin-stick Phase 3 build, and `PHASE1-README.md` repeats that same size for the twin-stick re-export. Byte-identical size after a script change is not credible evidence of a fresh export. Treat the twin-stick APK as **unverified until a fresh export is made and `touch_ui.gdc` is confirmed inside it**. The twin-stick job was still running when this audit was written |
| Old touch buttons (◀ ▶, JUMP, MINE) | REMOVED (in tree) | `touch_ui.gd` header: "Old ◀ ▶ JUMP MINE buttons are gone entirely." Same APK caveat as above |
| Real-device playtest (any control scheme) | NOT PRESENT | Every phase note states it: headless runs prove load/generate/render, not input feel. S25 playtest is still the user's step |

### 1.6 What footage shows that the game does not (yet) have

The concept/reference footage shows rugged, individually shaded stone,
irregular cave silhouettes, warm torchlight pools, cool blue depth,
detailed timber, moss, and glowing crystals as one composed scene.
The game has the *ingredients* (seeded rooms, edge overlays, real lights,
timber props, crystal lights) but not the *composition*: no parallax,
no foreground framing above gameplay, no rock↔dirt transitions, no
inner corners, no per-material light response, no particles, and the
rock field still reads as tiled texture because each 64 px cell carries
its own internal stone divisions. Nothing in the footage is a playable
feature the game already has — it is the target for §4, not a record
of the current build.

---

## 2. Canonical render scale and tile specification (locked)

These values are taken from the existing project, not invented.
Changing any of them reworks generation, collision, and every staged
asset at once — do not change them in the polished-chamber pass.

| Parameter | Locked value | Source |
|---|---|---|
| Gameplay tile | **64 × 64 px** | `main.gd` `TILE := 64`; `player.gd` `TILE := 64`; `project.godot` tile size 64 in tileset build |
| Viewport | **1280 × 720** | `project.godot` `window/size/viewport_width=1280`, `viewport_height=720` — 20 × 11.25 tiles on screen. Design chambers to read at this scale, not at editor zoom |
| World (current single region) | **80 × 45 cells = 5120 × 2880 px** | `map_gen.gd` `W := 80`, `H := 45`; camera limits 0..5120 × 0..2880 in `main.gd` |
| Renderer | **gl_compatibility (OpenGL 3)** | `project.godot` `renderer/rendering_method="gl_compatibility"`; all lighting/shadow claims must be verified under this renderer, not Vulkan |
| Texture filter | **Nearest, mipmaps off** | `project.godot` `textures/canvas_textures/default_texture_filter=0`; `VISUAL-SPEC.md` §2 |
| Pixel snap | **On** | `project.godot` `snap_2d_transforms_to_pixel` + `snap_2d_vertices_to_pixel`; `scenes/main.tscn` camera zoom 1.0 |
| Camera | **Zoom 1.0, ~0.5-tile lookahead in code, smoothed** | `scenes/main.tscn` zoom (1, 1); `player.gd` lookahead lerps toward `facing * 32.0` px (0.5 tile — note: `VISUAL-SPEC.md` says "about 1 tile"; the code value is 32 px, and the code value is the locked one until deliberately changed) |
| Camera limits | **Clamped to the generated region, 0 margin beyond the outermost solid cell** | `main.gd` `camera.limit_*`; `VISUAL-SPEC.md` §6 |
| Player collision box | **28 × 80 px (half-width 14, half-height 40)** | `player.gd` `half_w := 14.0`, `half_h := 40.0` |
| Player motion | **Speed 260 px/s, jump −620 px/s, gravity 1800 px/s², terminal 1200 px/s** | `player.gd` |
| Animation anchor | **Bottom-centre, feet at collision-box bottom, common 128 × 195 canvas at 0.5 scale** | `player.gd` `_ready()` (`_sprite.position = Vector2(0, -8.75)`, scale 0.5) |
| Layer order (draw order, current) | Background (z −2) → WallLayer (z −1) → FgLayer (0) → Props/EdgeLayer (z 1) → DamageLayer (z 2) → Player → HUD | `scenes/main.tscn`; cave backdrop is a direct Main child moved to just before FgLayer (see `main.gd` comment — a Background child is grouped below the wall layer regardless of its own z-index) |
| Light radii (gameplay rules, unchanged) | Torch **7 tiles = 448 px**; beacon **5 tiles**; crystal **3 tiles = 192 px** | `main.gd` `TORCH_RADIUS_TILES := 7`; beacon texture scale 320/448; crystal scale 192/448 |
| Ambient | `CanvasModulate` **(0.45, 0.52, 0.68)** | `scenes/main.tscn` — the spec's `#0B1420` is a colour target, not the multiplier; do not paste it in as a multiplier (it renders near-black) |
| Palette anchors | Torch `#FFB35C`, crystal `#7FE3F0`, beacon amber `#FFC46B`-family, ambient deep navy | `VISUAL-SPEC.md` §1, §5; torch colour in code is (1.0, 0.70, 0.36), the closest in-engine match |
| Export | Godot 4.8 beta 1, Android debug APK, package `com.dogbyte.deepfall`, min SDK 24, target SDK 36, ETC2/ASTC import on | `export_presets.cfg`, `project.godot` `textures/vram_compression/import_etc2_astc=true` (must be in the `[rendering]` section — a `[textures]` section is ignored; this already caused one failed export) |
| Seed | **20261101** is the reference seed for every comparison | All phase notes; any chamber comparison must re-render this seed and diff it |

**Explicitly not locked / not to be invented in this pass:** a chunk size
for streaming (see §3.4 — it is proposed there, not existing), a save
format (proposed in §5), and any new tile size, viewport, or physics
model. Collision stays grid-data-authoritative until a deliberate
decision moves it onto TileMap physics bodies (`VISUAL-SPEC.md` §3.3).

---

## 3. Terrain-atlas adjacency rules

### 3.0 Definitions (use these exact terms in code and art)

- A cell is **solid** if its fg id is not 0 (air) and not 7 (platform).
  Platforms are never autotiled as solid rock.
- Neighbour bits use the project convention **N = 1, E = 2, S = 4, W = 8**
  (diagonals are derived, never stored).
- **Material** of a solid cell is its fg id's material family: rock
  (stone, mossy-stone, cracked-stone, obsidian), dirt (dirt, grass-dirt,
  sand), ore (gold-ore, amber-ore), built (wood, brick). Ore and built
  cells do **not** take rock/dirt edge or transition tiles — they keep
  their own fill and take only the generic dark-crevice edge overlay
  where they meet air.
- All selection below is a pure function of **(seed, world_x, world_y,
  material, neighbour bits)**. No `randf()` at render time, no
  call-order dependence. This is what makes the rules chunk-safe (§3.4)
  and keeps seed 20261101 pixel-identical on re-render.

### 3.1 Selection order (first match wins)

For each solid rock/dirt cell, compute in this order:

1. **Material transition** — any orthogonal neighbour is solid but of a
   *different* material family (rock vs dirt). Use the rock↔dirt
   transition tile for that side. Transition beats edge/corner:
   a dirt cell against rock is a transition, not a dirt edge.
   (Art gap: these tiles do not exist yet — see §3.5. Until they do,
   fall back to the generic edge overlay and record the cell as
   transition-pending; do not silently ship a hard square cut as
   "done".)
2. **Inner (concave) corner** — a diagonal neighbour is air while both
   orthogonal neighbours on that corner are solid. Example: NE diagonal
   air + N solid + E solid = inner corner NE. (Art gap: inner-corner
   tiles do not exist yet — same fallback rule as transitions.)
3. **Outer (convex) corner** — two adjacent orthogonal neighbours are
   air. Example: N air + W air = outer corner NW. This is the existing
   `corner_*` overlay behaviour, extended to the new atlas.
4. **Straight edge** — exactly one orthogonal neighbour is air.
   N air = top edge, S air = bottom edge, W air = left edge,
   E air = right edge. This is the existing `edge_*` overlay behaviour.
5. **Exposed-face moss** — only after steps 1–4, and only on cells
   with air above (top face) or air on an upper side. Moss is an
   overlay on the fill, never a replacement fill, and never on a
   bottom face or inside a solid mass (`VISUAL-SPEC.md` §3.1).
6. **Interior fill** — no air neighbour, no material transition:
   the base fill variant for that material (§3.1, variant rule below).
7. **Floor / ceiling / wall naming** (for the chamber spec and for
   prop placement, not separate art): a solid cell with air above is a
   *floor top*; with air below, a *ceiling*; with air on a side, a
   *wall face*. Props may only anchor to the face they are defined
   for (timber posts stand on floor tops; roots hang from ceilings;
   sconces mount on wall faces).

### 3.2 Variant rule (fills only, never edges/corners/transitions)

```
variant = hash(seed, world_x, world_y, material) mod variant_count
```

- Rock and dirt: variant_count = 16 (the atlas3 sets). All other
  materials: 4 (the tiles2 sets). The hash must be stable across
  runs and across chunk boundaries — the existing
  `abs(x * 73856093 ^ y * 19349663 ^ SEED) % n` pattern in `main.gd`
  is acceptable; what is **not** acceptable is picking a variant
  from a per-run RNG sequence, because that breaks on chunk reload.
- Variants differ in crack placement, chip pattern, and highlight
  position — never in base hue, and never in a way that makes a
  mineable block look unmineable or a solid block look like air
  (`VISUAL-SPEC.md` §3.3).

### 3.3 Variation budget (per local area — the anti-noise control)

Apply per **room** (the generation unit that already exists), and
per **5 × 5 cell window** for exposed-face decoration. Caps are
ceilings, not targets — a room may have fewer.

| Feature | Cap | Notes |
|---|---|---|
| Exposed-face moss overlays | ≤ 4 per room | Only on top/upper-side faces (§3.1 step 5). Existing mossy-stone hash variants do not count against this — they are fill, not overlay |
| Cracked / damaged-look decorative tiles (not mining damage) | ≤ 3 per room, ≤ 1 per 5 × 5 window | Distinct from the mining crack overlay in `DamageLayer` |
| Floor debris speckles | ≤ 4 per room | Already the code value in `main.gd` `_render_props()` — keep it |
| Hanging roots | ≤ 2 per room | Already the code value — keep it |
| Timber frames (post pairs + trestles) | ≤ 2 per room | Already ~1 post pair + 1 trestle in even rooms — keep it, do not add a third frame type per room |
| Crystal clusters | ≤ 1 per 2 rooms | Crystals are landmarks, never per-tile (`VISUAL-SPEC.md` §5.3). Current code places 3 total for the whole world — that is within budget, but it is index-based (ore-list picks 0, 7, 14), not cluster-based; change it to the cluster rule in §3.3 |
| Torch / lantern lights | ≤ 2–3 in the test chamber, then measure | `VISUAL-SPEC.md` §5.2 count discipline. Every placed torch is a light; cut light count before cutting radius |

Enforcement: decoration placement must check the budget counter for
its room/window before placing, and must skip (not relocate) when the
budget is full. Skipping preserves determinism; relocating on a
second pass does not.

### 3.4 Feature clustering (deposits, not confetti)

- **Ore:** a vein is a connected random walk of **≥ 4 cells** (current
  walks are 4–9 steps — keep that range, and **discard walks that
  end below 3 placed cells** instead of shipping a single-cell ore
  speck). All cells of one vein share one ore type (gold or amber).
  No isolated ore cell may exist outside a vein. Crystal clusters
  spawn only adjacent to a vein, at most one per vein.
- **Moss:** a moss cluster starts from one exposed top face and
  grows to 2–4 adjacent exposed faces (same material family, same
  room). Single-face moss stamps with no neighbour are not placed.
- **Debris / rubble:** debris clusters only where a passage is
  marked collapsed (§4) or directly below a mined-out vein. Random
  debris on open floors is not placed.
- **Crystals:** one cluster per vein at most, in an air cell beside
  an ore cell, never on an ore cell, never on a route cell, never
  on the spawn or exit cell. This replaces the current index-based
  picks (0, 7, 14) with a rule that survives regeneration.
- **Timber:** timber frames cluster as a tunnel (a run of post
  pairs along one corridor/room edge), not as lone posts scattered
  through open rooms. A lone post is only valid where it braces a
  ceiling edge or a collapsed-section boundary.

### 3.5 Chunk-continuity rules (for when streaming lands — not yet implemented)

These rules are **specified here, not implemented**. Do not claim
chunk streaming works because these rules are written down.

1. **Chunk size (proposed, not locked): 16 × 16 cells = 1024 × 1024 px.**
   At 1280 × 720, a viewport spans at most 2 × 2 chunks. The size is
   a proposal for the streaming implementation to confirm against
   memory and load time — it is not an existing constant.
2. **All visual decisions are functions of world coordinates, never
   of chunk-local coordinates or load order.** Variant (§3.2), edge/
   corner/transition (§3.1), prop placement, and decoration budgets
   must be computable from (seed, world_x, world_y) plus a **1-cell
   halo** read across the chunk border. A chunk must never be
   rendered, then re-rendered differently when its neighbour loads.
3. **Generation vs streaming, decided explicitly:** the current
   generator is global (rooms sorted left-to-right, spanning tree,
   flood-fill repair). True chunk-local generation would require
   replacing it with chunk-local rooms plus border stitching, which
   risks changing seed 20261101's world. The lower-risk path that
   preserves determinism is: **keep full-world generation, stream
   rendering and collision in 16-cell chunks, and save only edit
   deltas** (mined cells, placed/picked-up torches) against the
   generated base. That satisfies the implementation spec's delta
   model without rewriting the generator. Whichever path is chosen,
   it must be chosen deliberately and recorded — not drifted into.
4. **Edge decoration at chunk borders** is derived from the same
   neighbour topology as interior cells, using the halo. A border
   cell's edge/corner tile must be identical whether its neighbour
   chunk is loaded or not.
5. **No chunk-boundary pop:** a chunk's tiles, edges, props, and
   lights must be fully built before the chunk becomes visible.
   The test chamber's deliberate chunk transition (§4) exists to
   prove this, with a debug-only boundary marker that is off in
   release builds.

### 3.6 Art gaps that block the adjacency rules (in order)

1. Rock↔dirt transition tiles (straight, per side) — do not exist.
2. Inner (concave) corner tiles — do not exist.
3. A truly seamless rock/dirt fill (no internal brick divisions) —
   the atlas3 slices reduce borders but keep internal divisions.
4. Damaged stages 2–3 as distinct art (currently one crack overlay).
5. Slope tiles wired with mirrored collision — staged, not in game.

---

## 4. The one polished Forgotten Mines test chamber to build next

Build **one** chamber first. Do not expand the generator, add a
region, or stream chunks until this chamber passes §5. The chamber
is a fixed, hand-checked layout applied on top of the existing
generator (either as a dedicated test scene or as a pinned room
template in the seed-20261101 world) — not a new random room.
Its contents, in one continuous section:

1. **Main traversal route.** Ground-level route from the west
   entrance to the east exit, at least 10 cells long, 3 cells high,
   with no jump steeper than the player's jump can clear (jump
   velocity −620, gravity 1800 — verify by playing it, not by
   assuming it). This is the route every player takes.
2. **Optional elevated route.** A second route above the main
   route, reached by one-way wood platforms (the existing platform
   id 7, one-way from above only), rejoining the main route before
   the exit. It must be genuinely optional: skipping it loses
   nothing required, taking it gains ore or a torch.
3. **Mining pocket with a connected ore vein.** A side pocket off
   the main route containing one ore vein of ≥ 4 cells (gold or
   amber, one type per vein, §3.4), reachable without mining
   through the main route's floor. The pocket's entrance must be
   visible from the main route.
4. **Collapsed passage.** A passage blocked by rubble (cracked-
   stone cells, mineable, 2-hit like other blocks) that must be
   mined through to reach a small reward cell (torch or ore).
   Debris clusters sit at the rubble, nowhere else in the chamber
   (§3.4). The collapsed passage must not be the only route —
   it is a shortcut/reward, not a gate.
5. **Timber-supported tunnel.** A corridor section braced by a run
   of timber post pairs plus one trestle (§3.4 clustering), with
   a hanging root and a wall sconce or lantern-post as dressing.
   Timber is visual only, no collision, and never sits on a route
   cell in a way that obscures a mining target.
6. **Distinct foreground and background stonework.** Foreground:
   rock/dirt fills with the §3.1 edge/corner/transition treatment.
   Background: darker, lower-contrast wall fills (cave-wall-dark /
   dirt-wall family, ~40–50% foreground brightness) with an
   irregular silhouette variant — not a flat dark fill, and not
   the foreground texture darkened by the ambient tint alone.
7. **Two or more warm light sources against the cool palette.**
   At least two placed torches (warm `#FFB35C`) plus the cool
   ambient and at least one cyan crystal or the amber beacon as
   contrast. Light count stays within the §3.3 budget, then frame
   cost is measured before any further light is added.
8. **One orienting landmark.** A single, unmistakable feature the
   player can navigate by: the amber exit beacon, or a large
   crystal cluster at the mining pocket, or a ruined masonry
   arch at the tunnel mouth. Exactly one — not three competing
   landmarks. It must be visible from the chamber entrance.
9. **Deliberate transition into the next streamed chunk.**
   The chamber's east edge opens into the next 16-cell chunk
   (§3.5). The transition must demonstrate border-continuity:
   edge/corner tiles at the border derived from the halo, no seam,
   no pop, no re-render when the neighbour loads. In the test
   build only, a debug marker may show the chunk boundary; it
   must be off by default and absent from any shipped build.
10. **What the chamber must not contain:** enemies, combat,
    crafting, a second region, a shift gate (shift is deferred),
    or a fourth class. Those are later phases, not chamber
    dressing.

---

## 5. Validation checklist (the chamber is not done until every box is checked)

### 5.1 Gameplay — play it, do not just render it

- [ ] Walk the full main route west → east without sticking on any
      cell edge, corner, or prop (props have no collision — verify
      by playing, not by reading the prop code).
- [ ] Walk the elevated route, including dropping back to the main
      route through a one-way platform (platforms must not block
      downward movement).
- [ ] Jump: ground jump, coyote-time jump (0.12 s), jump-buffer
      jump (0.12 s), and double jump all fire, in that order, with
      no double-fire on a held key.
- [ ] Mine: every mineable cell in the chamber breaks in 2 hits
      (first hit = crack overlay, second = break to air); wall
      cells and platforms do not break; mining re-tiles all 8
      neighbours' edges correctly, including at the chamber's
      east (chunk-border) edge.
- [ ] Mine the collapsed passage rubble and reach the reward cell.
- [ ] Mine a torch's supporting block: the torch pops off and is
      picked back up, light goes out. Click a torch directly: same
      result. Torch count in the HUD matches torches held.
- [ ] Collect ore from the mining pocket: HUD ore count and
      "Last: Gold ore / Amber ore" update; ore type matches the
      vein's single type.
- [ ] Reach the exit/landmark: HUD reports extract/arrival; no
      soft-lock (the exit must be reachable without the elevated
      route and without the collapsed passage).

### 5.2 Collisions and camera

- [ ] Grid collision holds at every chamber boundary, including
      the world border (solid) and the chunk-transition edge.
- [ ] Camera never reveals void, unfinished edges, or untextured
      area at any point on either route, including at full jump
      height and at the chamber's east edge.
- [ ] Camera lookahead (0.5 tile in code) does not jitter during
      mining or jumping; no camera shake in this pass.
- [ ] Foreground framing (when it lands) never covers the player,
      a torch, a mining target, or the landmark for more than a
      few pixels.

### 5.3 Determinism, streaming, save/reload

- [ ] Seed 20261101 renders the chamber pixel-identical across two
      headless runs (same variant/edge/prop selection — the
      §3.0 purity rule).
- [ ] Chunk transition (when streaming lands): crossing the east
      border produces no seam, no pop, and no re-render of the
      already-visible chunk. Debug boundary marker works in the
      test build and is off by default.
- [ ] Save/reload (when it lands — it does not exist yet): mine
      3 cells, place a torch, quit, reload, and verify all three
      mined cells are still air, the torch is still placed with
      its light, and the rest of the world matches the generated
      base. Save format is seed + edit deltas only (§3.5 item 3).
- [ ] No regression: the existing READY line still prints
      (`rooms=14/14`, `connected=true`) and the existing
      screenshot comparison at the same camera scale still matches
      except for the deliberate chamber changes.

### 5.4 Performance and device

- [ ] Frame cost measured with the chamber's full light count
      (torches + beacon + crystal) on laptop headless first, then
      on the S25. Record fps / frame time; do not add lights
      beyond the §3.3 budget until the measurement exists.
- [ ] `gl_compatibility` shadow behaviour verified on device:
      timber-post occluders either render correctly or are cut
      with the gradient-pool fallback recorded — not silently
      shipped broken.
- [ ] S25 playtest (user's step): twin-stick movement, jump edge,
      8-way mining, and torch button all feel right on a real
      phone. Headless verification is not a substitute for this.
- [ ] Android APK re-verified after the chamber lands: package
      `com.dogbyte.deepfall`, badging, zip test, signature check,
      and — specifically, given the §1.5 caveat — `touch_ui.gdc`
      confirmed inside the APK before anyone claims the twin-stick
      build shipped.

### 5.5 Art survival (the point of this whole phase)

- [ ] A 5 × 5 block of each material renders seam-free at 1280 × 720
      (the `VISUAL-SPEC.md` §9 check), not just at editor zoom.
- [ ] Lighting never hides a hazard, a mining target, or the
      landmark. If a shadow wedge does, cut occlusion before
      cutting gameplay readability.
- [ ] The player silhouette stays crisp against both rock and
      dirt, in both lit and unlit areas.
- [ ] The chamber looks designed, not tiled: transitions,
      corners, clusters, and the landmark read as deliberate
      composition, and the same rules (not hand-painting) produce
      that composition from the generator.

---

## 6. Top findings (summary for the next build decision)

1. **The biggest gap is not art volume, it is the missing
   adjacency system.** The game has 112 staged tiles, 383 item
   sprites, 24 enemies, and 207 character frames — but in the
   project there is no terrain-set/peering-bit autotiling, no
   rock↔dirt transitions, no inner corners, and no 3-stage
   damage. Edges are a manual overlay layer. The polished
   chamber must build the §3 rule set first; more sprites will
   not fix repetition.
2. **Chunk streaming and save/reload are specified, not built.**
   There is no chunk code and no save code in the project at
   all. The honest path is to keep full-world generation and
   stream rendering/collision in 16-cell chunks with edit
   deltas (§3.5 item 3) — but that path has not been chosen or
   implemented yet, and the test chamber's deliberate chunk
   transition (§4 item 9) is the proof item, not an assumption.
3. **The twin-stick APK claim is unverified and must be
   re-checked.** The tree already contains the twin-stick
   `touch_ui.gd`, but the APK on disk is byte-identical in size
   (59,735,155 bytes) to the pre-twin-stick Phase 3 build, and
   the README repeats that size for both. Before any claim that
   the twin-stick build shipped, make a fresh export and confirm
   `touch_ui.gdc` inside it (§5.4). Until then, the twin-stick
   build is code in the tree, not a verified APK.
