# DEEPFALL — Phase 1: Forgotten Mines (playable slice)

First playable slice, NOT the full game and NOT the chunk-streamed world.
Architecture is a single seeded region now; chunk streaming is a later phase.

## What runs (verified)

- Godot 4.8 beta 1 project, opens and runs headless without script errors.
- Seeded generation, seed **20261101**, ported from
  `staging/deepfall/tiles/deepfall_map_gen.py` to the Terraria block-grid model:
  foreground mineable blocks, a separate non-colliding background wall grid,
  one-way wood platforms. Room graph + spanning-tree corridors + loop
  corridors + ore veins as connected random walks + flood-fill
  validation/repair.
- Verified headless output (twice, identical — same seed = same world):
  `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31
  spawn=(7, 20) exit=(73, 9) connected=true`
- Screenshot under Xvfb + OpenGL 3 (llvmpipe): `screenshot.png` in this folder.
  It shows the player standing in the spawn room, stone/dirt tiles,
  background walls, wood platforms, gold ore, and the HUD.
- Player: tech soldier only. Placeholder sprite = a single cleaned frame
  (`cleaned-regen/tech-soldier/r0c0_idle.png`, copied to `assets/`).
  Movement: A/D or arrows, Space/W jump with coyote time 0.12 s,
  jump buffer 0.12 s, double jump, gravity, grid collision vs foreground blocks.

## Controls

- A/D or arrows — move
- Space / W — jump (press again in air for double jump)
- E — mine the foreground block in the facing direction
- Click — mine the block under the mouse
- Q — cycle tool (pickaxe ↔ sword); 1 = pickaxe, 2 = sword (Phase 10).
  Sword cannot mine ("Need pickaxe to mine" in the log line); pickaxe
  attacks for 5 damage, sword for class melee (15/20/10).
- J — attack (tool damage, see above)
- Touch: twin sticks (left move + stick-up jump, right 8-way mine),
  JUMP button (same jump as Space), TOOL button + bottom-centre hotbar
  (tap a slot to select; torch slot places a torch).
- T — place a torch (starts with 3)
- Click a torch — pick it back up (it drops itself)
- Reach the amber exit beacon in the far room — HUD reports
  "EXTRACT REACHED — run slice complete"

## Systems in this slice

- Mining: foreground blocks break to air. Gold/amber ore increments the
  ore counter. Wall grid is NOT mined. Platforms are not mined.
- Torch: placeable on top of or beside a solid block, light radius 7 tiles,
  destructible (click it and it drops itself, light goes out). If the block
  supporting a torch is mined, the torch pops off and is picked back up.
- HUD: depth (tile row), ore collected, torches held, extract status.

## Honest limits — what this is NOT yet

- Collision is grid-based in `player.gd`, not TileMap physics bodies.
  The TileMapLayers are visual; the grid data is the collision authority.
- Torch light is a radial-gradient sprite, NOT real Godot lighting
  (no CanvasModulate / PointLight2D lighting pass yet).
- Mining and torch placement are implemented and code-reviewed but were
  NOT interactively playtested with real keyboard/mouse input — the
  headless runs above prove the scene loads, generates, and renders,
  not that every input path feels right. That needs a real-device pass.
- No Amber/Void shift (deferred per the implementation spec).
- No fourth starting class. Skeleton hero is a separate/unlockable hero
  and is NOT in Phase 1. Design notes keep the three starting classes as
  tech soldier / hooded mage / red soldier; only tech soldier is playable.
- No enemies, no combat, no crafting, no chunk streaming, no save/load,
  no other regions (Fungal Hollows, Sunken Works, Ember Fault,
  Hollow City, Black Deep are all later phases).
- Tile art is a copied subset of staged tiles only (dirt, grass-dirt,
  stone, gold-ore, amber-ore, wood, wood-platform, brick, cave-wall-dark,
  dirt-wall, mossy-stone, cracked-stone, sand, obsidian). Staged originals
  were copied, not moved.

## How to run

```sh
~/tools/godot/godot --path deepfall-game
# headless render check:
xvfb-run -a ~/tools/godot/godot --path deepfall-game \
  --rendering-driver opengl3 -- --screenshot
```

## Layout

- `project.godot` — Godot 4.8, gl_compatibility renderer
- `scenes/main.tscn` — main scene (layers, player, camera, HUD)
- `scripts/map_gen.gd` — seeded generation (DeepfallMapGen)
- `scripts/main.gd` — tileset build, mining, torches, HUD, extract
- `scripts/player.gd` — platformer movement + grid collision
- `assets/tiles/` — copied staged tiles (64 px)
- `assets/player_idle.png` — placeholder tech-soldier frame

## Phase 2 — polished Forgotten Mines chamber (2026-11-04, VISUAL-SPEC.md)

No AI images were generated for this pass; everything is procedural/code
from staged assets on disk (`build_assets.py` in this folder).

What changed:
- Atlas remake, procedurally: the 14 game tiles now ship as 4 deterministic
  variants each (`assets/tiles2/*_v0..v3.png`: original cleaned, flip-H,
  flip-V, flip-both + 0.94 brightness). Variant is a pure function of
  (seed, cell) — seed 20261101 re-renders identically. Dark panel borders
  softened by blending outer pixels toward the interior.
- Edge/corner overlays: a separate EdgeLayer draws jagged dark-crevice
  overlays where a solid cell meets air (corners take priority). Mining a
  cell re-tiles its 8 neighbours' edges, so openings stay clean.
- Damaged states: mining now takes 2 hits — first hit shows the crack
  overlay, second breaks the block. Ore pickup name is now shown in the HUD
  ("Last: Gold ore" / "Last: Amber ore").
- Real lighting: CanvasModulate dark-blue ambient + PointLight2D torches
  (warm #FFB35C, ±5% flicker), amber exit beacon light (5 tiles), cyan
  crystal lights (3 tiles, in air cells beside ore cells, not on ore cells).
  The old gradient-sprite glow is gone; the gradient image survives only as
  the PointLight2D texture. Selective LightOccluder2D on timber posts only.
- Depth: background cave silhouette + distant blue-lit cavern opening
  (world-space layer, NOT parallax — see gaps), foreground framing wedges
  at the bottom screen corners only, never over the HUD or centre.
- Props, deterministic per room: timber posts with lit edges, hanging roots
  from solid ceilings into air only, floor debris speckles. None have
  collision; none sit on spawn/exit cells or on route air cells.
- Player: idle (9 frames, 4 fps), walk (9 frames, 8 fps), shoot (5 frames,
  10 fps, triggered by mining) wired from the staged tech-soldier strips,
  bottom-centre anchored on a common 128×195 canvas, feet at the collision
  box bottom. Landing squash (~150 ms) added. Walk still reads as a
  shuffle — that is the staged strip's leg movement, not a timing bug.
- Camera: zoom 1.0 (spec §6, was 0.75), pixel snap on, limits clamped to
  the generated region (0..5120 × 0..2880), ~1 tile lookahead.
- Known flaws fixed or fenced: ore mini-tile strip removed (bottom 8 rows
  replaced with the band above, stone/gold/amber); grass-dirt white sky
  corners repainted to dirt brown; iron/copper NOT added to the game —
  fenced out entirely until they are distinguishable (gold/amber are the
  only ores in this chamber, and pickup name is the fallback signal).

Deviations from VISUAL-SPEC.md, recorded honestly:
- Ambient is CanvasModulate (0.45, 0.52, 0.68), NOT the spec's literal
  #0B1420 as a multiplier — that value multiplies the scene to ~0.04–0.13
  and renders near-black even with lights. The tint used hits the same
  navigable dark-blue target.
- No rock↔dirt transition tiles: variant + edge overlays only. A true
  jagged transition atlas still needs authored art.
- No parallax: background silhouettes are a static world-space layer.
  Parallax was skipped to avoid fighting camera limits and revealing void.
- Torch light radius reads ~4 tiles visually in the screenshot, not the
  full 7-tile texture radius — the squared falloff makes the outer ring
  too dim to see against the ambient tint. Radius is unchanged in code;
  the visible pool is smaller.
- Torch shadows work under gl_compatibility (verified in a /tmp test copy
  with a pre-placed torch: warm pool + a shadow wedge from the timber
  post occluder). That wedge does darken gameplay area to the right of a
  torch — occlusion count may need cutting if it hides hazards in play.
- No distinct fall pose: air pose reuses an idle frame. Fall/land sets do
  not exist in staging; land squash is code, not art.
- .tscn lesson: comment lines inside scenes/main.tscn after a node block
  caused Godot's parser to swallow the following node (Background was
  "not found" at runtime until the comments were removed). Do not put
  # comments inside .tscn node blocks.

Verified headless under xvfb + OpenGL 3 (after an editor import pass for
the new assets): no script errors (audio-driver error only, irrelevant
headless), `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31
spawn=(7, 20) exit=(73, 9) connected=true`, screenshot saved as
`screenshot.png` (new, zoom 1.0). Re-export to Android was NOT done in
this task — the APK in exports/ is still the Phase 1 build.

Definition-of-done status (VISUAL-SPEC.md §9): 5, 6, 9 pass (mining
re-tiles neighbours, camera clamped, determinism holds). 1, 2, 3, 4, 8
partially pass (seams reduced but the staged stone/dirt textures still
read as repeating panels; lighting works but the visible torch pool is
smaller than spec; player silhouette is crisp and feet-anchored; props
avoid routes; chamber contents work except the fall pose). 7 and 10
unproven on device / partially fenced (see above). NOT real-device
tested — S25 performance is the user's step.

What still needs AI-regenerated art to close the gap:
1. A truly seamless rock/dirt atlas (no internal brick divisions, true
   edge/corner/transition tiles) — the procedural variant/flip pass
   reduces repetition but cannot remove the staged tiles' panel read.
2. Large background cave silhouettes / ruined structures at >64 px and
   modular timber assemblies — current silhouettes and posts are flat
   code shapes, not art.
3. A walk cycle with larger leg travel and distinct fall/land poses —
   the staged walk strip is a shuffle even at correct timing.

## Android build (debug, 2026-11-04)
- APK: `exports/deepfall-phase1-debug.apk` (56,172,868 bytes, package `com.dogbyte.deepfall`, version 1.0 / code 1, min SDK 24, target SDK 36, arm64-v8a + armeabi-v7a, debug-signed, v2/v3 signature verified, zip test clean).
- Exported with Godot 4.8 beta 1, prebuilt template (no Gradle), ETC2/ASTC import enabled in project settings (the export initially failed on this until the setting was moved to the rendering section).
- Touch controls added for Android: on-screen ◀ ▶, JUMP, MINE, TORCH buttons (scripts/touch_ui.gd, wired into player.gd touch_move/touch_jump and main's mine/torch with the same 0.25s cooldown). Desktop keyboard/mouse paths unchanged; headless re-run after adding them printed the identical READY line.
- NOT real-device tested. Install and playtest on a real phone before calling it working.

## Phase 3 — Atlas art integration (2026-11-04)
- New sheets in staging/deepfall/atlas-art/, sliced to assets/atlas3/ (rock_0..15, dirt_0..15, timber_*, cave-silhouettes.png; also copied to staging/atlas-art/sliced/).
- Stone tiles replaced with the 16 rock-atlas cells; dirt replaced with 16 tiles cut from the seamless dirt texture. Tileset now supports per-name variant counts (stone/dirt 16, others 4); variant is still a pure function of seed+cell, so seed 20261101 stays deterministic. Collision grid untouched.
- Cave scene wired as a large backdrop centred on spawn, dimmed (0.55/0.6/0.7), inserted before the foreground layer. Two layering fixes were needed and are recorded here: a Background-node child is grouped below the wall layer regardless of its own z_index, and an appended Main child draws over the player — the sprite is now a direct Main child moved to just before FgLayer.
- Timber posts replaced the old ColorRect posts (timber_post sprite, occluder widened to match); a timber trestle prop is placed in even-numbered rooms on the room floor, visual only, never on spawn/exit.
- Known caveats: the corner-frame slice originally caught the top of the T-frame and was re-cut with that region masked; dirt reads flatter than the source texture at 64px (roots mostly vanish at game scale); the cave backdrop replaces wall art inside its footprint and its bottom rock piles can read as terrain at a glance — they have no collision and the player/platform layer stays on top. Trestle props are not visible in the spawn screenshot (they sit in other rooms).
- Verified headless (xvfb + OpenGL3): DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31 connected=true, no script errors (ALSA audio error only, irrelevant headless).

## Android re-export, Phase 3 build (2026-11-04)
- exports/deepfall-phase1-debug.apk, 59,735,155 bytes, package com.dogbyte.deepfall v1.0 (code 1), min SDK 24 / target 36, debug-signed, v2+v3 signature verified, zip test clean. Contains the Phase 3 atlas art (rock/dirt/cave/timber textures confirmed in the APK). Still NOT real-device tested.

## Phase 4 — polished test chamber (2026-11-04)

No AI images generated; staged assets + code/procedural techniques only.
AUDIT-NEXT-PHASE.md was still being written when this phase started, so
this phase was built from VISUAL-SPEC.md and the code itself, not the audit.

What changed:
- Terrain-atlas adjacency: tile variant is now a pure function of the
  cell's neighbour mask (N/E/S/W air bits) and its stable world-coordinate
  block (x//4, y//4). No random pick from the whole atlas; a mined
  neighbour re-derives only its own cell. Edge overlays now also handle
  material transitions (stone↔dirt boundary gets an edge overlay, visual
  only — true transition tiles still do not exist) and inner corners
  (air cells boxed in by solid on two perpendicular sides). Ore cells are
  exempt from transition overlays so the pickup is never darkened.
- Variation budget: at most 3 decorative items per 5x5 local area
  (roots, debris, moss props, chamber debris). Timber posts/trestles are
  structural and exempt.
- Feature clustering: moss in map_gen is now block-based (a whole 3x3
  block turns mossy together) instead of scattered singles; ore veins
  were already connected walks; crystals sit beside ore cells; moss
  props are placed as 2-3 adjacent patches per room, never singles.
  Changing moss assignment is solid-to-solid, so world topology and the
  READY line are unchanged.
- Polished chamber, built INTO the seeded world (spawn room + first
  corridor, seed 20261101, deterministic from world coordinates):
  main traversal route, an elevated one-way platform route across the
  spawn room, a 2-cell mining pocket carved into the right wall with a
  connected 3-cell gold/amber vein, a collapsed passage (left wall turned
  cracked-stone, still solid, plus a debris cluster), a timber-supported
  tunnel (two posts + beam at room centre), distinct foreground wedges
  and background cave stonework, two static warm chamber lights with
  small ember particles, one orienting landmark (the Amber Spire — a
  large amber crystal + light on the room floor), and a deliberate chunk
  transition gate (timber posts + amber light at the first floor-standing
  air cell on the x=20 chunk boundary, derived from world coordinates so
  re-streaming re-derives the same gate). HUD now shows the current
  chunk (x//20, 0-3).
- Player animation: walk now uses the newly sliced tech walk cycle
  (atlas-art/sliced/tech-walk-cycle, 4 frames, large leg travel — a run,
  not the old shuffle), fall uses tech-fall-land frames 0-2 only
  (airborne tuck, falling, land crouch). Frame 3 of that sheet is a
  front-facing standing pose and is deliberately NOT used as a land
  pose. Frames were normalised to a common 256x195 canvas at the same
  0.5 scale, feet still at +40px. Idle/shoot strips are unchanged.
- Light count, restrained: chamber adds 2 warm lights + spire light +
  chunk-gate light + 3 crystal lights + beacon light; player torches
  (max 3) are the only other dynamic lights. Ember particles are
  CPUParticles2D, 10 particles per chamber light.
- Twin-stick controls and desktop controls untouched
  (scripts/touch_ui.gd not edited in this phase).

Validation (headless, xvfb + OpenGL3): no script errors (ALSA audio
error only, irrelevant headless), `DEEPFALL_PHASE1_READY seed=20261101
rooms=14/14 ore_veins=31 spawn=(7, 20) exit=(73, 9) connected=true`,
new screenshot at the same scale. Note: the READY ore count (31) is
from map_gen before the chamber build, so the chamber's extra 3-cell
vein is NOT included in that count. The screenshot shows the spawn
chamber (timber tunnel, spire, chamber flames, elevated platforms,
twin sticks, Chunk: 0); the chunk gate itself sits off-screen to the
right of spawn and was not visually confirmed in this screenshot.

What still fails or is unproven:
- True rock↔dirt transition tiles still do not exist (overlay only).
- No parallax (background remains a static world-space layer).
- Walk/jump/mine/collision/chunk-transition behaviour is code-verified
  and headless-run only — headless proves load/generate/render, not
  input feel. Twin sticks are untouched but were not re-playtested here.
- S25 performance and real-device behaviour are NOT proven — the user's
  phone pass, as before. No enemies, combat, crafting, save/load, or
  other regions yet; chunk streaming itself is a gate + HUD readout,
  not a full streaming implementation.

## Android controls — twin sticks (2026-11-04, supersedes the button layout above)
- The old ◀ ▶, JUMP, and MINE buttons are REMOVED entirely. scripts/touch_ui.gd is now two fixed virtual joysticks (160px, bottom corners, 0.25 dead zone) plus one small TORCH button.
- Left stick (bottom-left): x = move left/right, analog, via the same player.touch_move; push up past 0.6 = jump via the same player.touch_jump, so coyote time (0.12s), jump buffer (0.12s) and double jump are unchanged — relax above -0.35 and push up again for the second jump. No separate jump button.
- Right stick (bottom-right): push past 0.5 magnitude = mine the block in the stick direction (8-way), via main._mine_at with the same 0.25s mine_cooldown; releasing stops. This replaces the old facing-only MINE button, so mining up/down/diagonally now works from touch.
- TORCH (one kept button, above the right stick): a joystick has no natural torch action, so place/pickup stays a button — stated plainly, not hidden. It shares the 0.25s cooldown, same as before.
- Desktop keyboard/mouse paths unchanged (mouse input never produces InputEventScreenTouch). HUD hint updated to the twin-stick scheme.
- Re-exported APK: exports/deepfall-phase1-debug.apk, 59,735,155 bytes, package com.dogbyte.deepfall v1.0 (code 1), min SDK 24 / target 36, debug-signed, v2+v3 signature verified, zip test clean, new touch_ui.gdc confirmed inside. Verified headless (xvfb + OpenGL3): DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31 connected=true, no script errors.
- NOT real-device tested: twin sticks are code-verified and headless-run only until playtested on a phone.

## Phase 5 — enemies + combat, Forgotten Mines only (2026-11-05)

No AI images generated; staged assets + code only. Staged originals were
copied, never moved (asset prep in `build_phase5_assets.py`, manifest in
`assets/enemies/MANIFEST.md`).

What was built:
- `scripts/enemy.gd` (new): one enemy class driven by a stats dict.
  Gravity + grid collision copied from the player's logic (same fg grid,
  one-way platforms, world border solid). Wander patrol with wall/ledge
  turns (ground-ahead check), chase within aggro range and ±200 px height,
  attack with a 0.35 s windup, strike at ~0.4 s, 1.0 s cooldown — the
  windup is the dodge window. `take_hit(dmg, from_x)`: HP loss, red hurt
  flicker, knockback. Death: `died` signal + smoke-poof death FX
  (`scripts/death_fx.gd`, frames `assets/effects/death_0..3.png`, code
  fades modulate alpha to 0 over 0.5 s — the frames themselves never
  dissipate) + `queue_free`. Walk 6 fps, idle when still, attack 8 fps,
  sprite flipped by facing, 0.5 scale, bottom-centre anchored.
- Spawning (in `main.gd`, after world gen): deterministic —
  `RandomNumberGenerator` seeded `SEED + 5000`, Fisher-Yates with the
  seeded RNG. **10 enemies total, 2 each in 5 of rooms 1..13** (never
  room 0, the spawn room). Spawn cell must be air with solid-or-platform
  ground below, ≥3 cells from the spawn cell, the exit beacon cell, and
  the chunk gate, never on a torch/crystal cell. `Enemies` Node2D is a
  direct Main child inserted just before `Player` in child order, so
  enemies never draw over the player.
- Player combat (`player.gd`): HP 100/100, melee on **J only** (left-click
  stays mining — one clear binding, documented here). J / ATK button:
  0.55 s swing, 4 melee frames (`assets/player_anim/melee_0..3.png`,
  tech-melee-v2, common canvas 317×195, reuses the existing 0.5 scale /
  −8.75 offset), strike at ~0.3 s remaining, hits all enemies within
  90 px in front of the player (64 px vertical tolerance) for 15 damage
  with knockback. `take_hit(dmg, from_x)`: 0.5 s invulnerability + red
  hurt flicker + knockback. Death: sprite hidden, death FX, 1.2 s delay,
  respawn at the spawn cell with full HP; `respawn_run()` re-spawns the
  same deterministic enemy set. Mined state, ore, and torches are kept
  for the session only — **no save system yet, that is a later phase**.
- Touch (`touch_ui.gd`): one 80×80 **ATK** button, bottom-right left of
  the right stick (x 960–1040, y 550–630), overlapping neither the stick
  nor TORCH. Twin sticks and the TORCH button are untouched.
- HUD: existing fields kept (depth, ore, torches, chunk, last ore,
  extract) and appended: `HP: %d/100 | Foes: %d left (%d slain)`. Hint
  line now includes `J attack` and `ATK button / J attack`. Prints:
  `DEEPFALL_ENEMY_SLAIN slug=… remaining=…`,
  `DEEPFALL_PLAYER_DIED`, `DEEPFALL_PLAYER_RESPAWN`.
- Headless self-test (`--selftest`, in `main.gd` only, never runs in
  normal play): spawns a ghoul next to the player, forces a player
  attack and an enemy attack, prints `DEEPFALL_SELFTEST` lines.

Enemy roster (as implemented — matches `enemy.gd` STATS):

| slug | HP | speed | dmg | aggro (px) | range (px) | walk | attack | wander |
|---|---|---|---|---|---|---|---|---|
| cave-bat-swarm | 10 | 150 | 5 | 260 | 48 | 4 | 4 | yes |
| miner-ghoul | 20 | 90 | 8 | 300 | 56 | 4 | 4 | yes |
| rock-golem | 50 | 45 | 12 | 240 | 64 | 4 | 4 | yes |
| cave-spider | 15 | 130 | 6 | 320 | 52 | 4 | 4 | yes |
| ore-mimic | 30 | 60 | 10 | 200 | 60 | 4 | **3** | no (ambush) |
| tunnel-worm | 25 | 70 | 8 | 280 | 64 | **2** | 4 | yes |

Balance: deliberately forgiving — a first combat pass, not a hard
roguelike. Golem is the only tank (50 HP); bat dies to one melee hit
(10 HP vs 15 dmg).

Controls (additions — everything earlier is unchanged):
- **J** — melee attack (desktop). **ATK button** — melee attack (touch).
- Player HP and foes remaining are in the HUD top line.

Verification (re-run by the Phase 5 owner, not only by the builder):
- Editor import pass: clean, exit 0.
- Headless (xvfb + OpenGL 3, `--audio-driver Dummy`):
  `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31
  spawn=(7, 20) exit=(73, 9) connected=true` — identical to Phases 1–4,
  no script errors. (The ALSA `ERR_CANT_OPEN` line seen without the
  Dummy driver is audio init, not a script error.)
- `--selftest` run:
  `enemy_hp_after_player_hit=5` (ghoul 20 − 15, as expected),
  `player_hp_after_enemy_hit=92` (100 − 8, as expected),
  `DEEPFALL_ENEMY_SLAIN slug=miner-ghoul remaining=10`,
  `kills=1 enemies_left=10`, `DEEPFALL_SELFTEST done`.
- Screenshot (`screenshot.png`): spawn chamber as before — tech soldier
  idle between the timber posts, amber spire + torch glow, cave
  backdrop, ore bottom-centre. HUD reads `HP: 100/100 | Foes: 10 left
  (0 slain)`. The ATK button is visible bottom-right, left of the right
  stick; TORCH above it. **No enemy in view — correct by design, the
  spawn room has none.**

Honest limits:
- Headless only — **NOT real-device tested**. Touch ATK placement was
  verified only visually in the screenshot, not by a real tap. Twin
  sticks, mining, and torch feel are still the user's phone pass.
- Bat is ground-walking, not flying; its walk reads as sway, not a
  real cycle (staged art limitation, carried forward honestly).
- Tunnel-worm walk is **2 frames** and ore-mimic attack is **3 frames**
  (per `assets/enemies/MANIFEST.md`) — the code never indexes past
  what exists; the mimic's strike point is clamped to 60% of its
  0.375 s attack so the hit still lands inside the animation.
- Enemy AI (wander/ledge turns, chase, windup dodge window, knockback,
  death fade, player death → 1.2 s respawn → deterministic re-spawn)
  is code-verified and partially exercised by `--selftest` (player hit,
  enemy hit, kill path), but full in-game behaviour — enemies landing
  on floors across all rooms, chase/attack cycles over minutes, the
  respawn flow end-to-end — was **not** verified headless. No scripted
  playthrough exists that walks the player into an enemy room; that is
  the main unverified area, and a real-phone or scripted-input playtest
  is still needed.
- Death-FX fade and hurt flicker are implemented per spec but only the
  spawn path was observed headless, not the visual fade itself.
- Cosmetic, not fixed in this pass: the second HUD hint line already
  overflowed the right edge before Phase 5; the longer hint text
  (`J attack` / `ATK button`) makes it worse. The first HUD line fits.
- Still not built: crafting, save/reload, other regions, red soldier /
  hooded mage as playable classes, skeleton hero, Amber/Void shift
  (deferred), full chunk streaming (gate + HUD readout only).

## Android build, Phase 5 (2026-11-05)
- APK: `exports/deepfall-phase1-debug.apk`, **64,845,472 bytes**,
  SHA-256 `30262470bf68fad5cc59f7b79f6cd5f89719385958e16f5e79aa9c196f017d16`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  Enemy textures (51 files under `assets/enemies/`), melee frames,
  `enemy.gdc` and `death_fx.gdc` confirmed inside the APK. Exported
  with Godot 4.8 beta 1 headless, prebuilt template, build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section.
- NOT real-device tested.

## Phase 6 — chunk-streamed persistent world (2026-11-05)

No AI images generated; code only. Follows AUDIT-NEXT-PHASE.md §3.5
item 3, the lower-risk path: **full-world generation from seed
20261101 is kept exactly** (no per-chunk regeneration, no topology
change, READY line unchanged). Streaming applies to rendering,
props, lights, and enemies in 16×16-cell chunks; player edits are
saved as deltas against the generated base.

What was built:
- Chunk system (`scripts/main.gd`): the 80×45 world is divided into
  16×16-cell chunks, 5 × 3 = 15. Each chunk owns its own Fg / Wall /
  Edge / Damage TileMapLayers (60 layers, tilesets shared) and a
  Props container. Active set = the player's chunk plus its
  neighbours (up to 3×3 = 9 chunks, 4–9 in practice at the edges);
  distant chunks are hidden (layers + prop containers set
  invisible) but their base data stays derivable from the seed.
  Chunk visuals are pure functions of world coordinates + neighbour
  masks (the Phase 4 rule) with a 1-cell halo read across borders,
  so a border cell renders identically whether its neighbour chunk
  is loaded or not — no seams on re-stream. Collision was never
  TileMap-based: the fg grid stays the collision authority and is
  always resident (3600 ints), so unloading a chunk's visuals
  cannot change collision.
- Edit deltas: mined cells, 1-hit crack state, placed torches
  (cell + support cell), and slain enemies (by deterministic spawn
  id) are recorded as deltas. Deltas are applied on top of the
  generated base whenever the world (re)builds, so a mined cell
  stays mined and a dead enemy stays dead across chunk trips.
- Enemies now spawn from a deterministic spawn table (seed + 5000,
  same 10 spawns as Phase 5) instead of being spawned all at once:
  only spawns in active chunks are live; an alive enemy whose
  chunk unloads is freed and re-spawns at its spawn cell, full HP,
  when the chunk loads again. Slain ids never respawn — including
  across a player death (Phase 5 respawned the whole set; Phase 6
  keeps the dead dead). HUD "Foes: N left" now counts the spawn
  table minus slain, not the live-node count.
- Save/load: single slot, `user://deepfall_save.json` (on Linux:
  `~/.local/share/godot/app_userdata/DEEPFALL Phase 1/deepfall_save.json`),
  JSON `{version: 6, seed, player {x, y, hp}, ore, torches_held,
  kills, extracted, mined ["x,y"], cracked ["x,y"], torches
  {"x,y": "support-x,support-y"}, slain [spawn ids]}`. Triggers:
  autosave on entering a new stream chunk, on reaching the exit
  beacon, on every mine hit/break, torch place/pickup, and enemy
  kill; manual save on **F5** (desktop) or the **SAVE** button
  (touch, top-right, below the HUD); **F9** or the **NEW** button
  clears the save and regenerates a clean run. `--new-run` does the
  same at launch. On launch, if a save exists it is applied
  automatically (world regenerated from seed, deltas re-applied,
  player restored) — no prompt UI; a mismatched version/seed save
  is ignored with a `DEEPFALL_SAVE_IGNORED` print.
- HUD: legacy `Chunk: x//20` (0–3) and the x=20 chunk gate are
  untouched; the HUD now also shows `Stream: (cx,cy) N/15` (the
  16-cell chunk and loaded-chunk count) and a brief `Saved (...)`
  note for 3 s after a save.
- Touch: SAVE and NEW buttons added top-right (below the HUD text);
  twin sticks, ATK, and TORCH are untouched.

Verification (headless, xvfb + OpenGL 3, `--audio-driver Dummy`):
- Plain run: `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14
  ore_veins=31 spawn=(7, 20) exit=(73, 9) connected=true` —
  identical to Phases 1–5, no script errors.
- `--selftest` (Phase 5 checks + Phase 6, output verbatim):
  `DEEPFALL_SELFTEST enemy_hp_after_player_hit=5 (ghoul max 20, expect 5)`
  `DEEPFALL_SELFTEST player_hp_after_enemy_hit=92 (expect 92)`
  `DEEPFALL_ENEMY_SLAIN slug=miner-ghoul remaining=10`
  `DEEPFALL_SELFTEST kills=1 foes_remaining=10 (expect 1, 10)`
  `DEEPFALL_SELFTEST_PHASE6 a cell=(2, 21) cracked_first=true mined=true layer_erased=true`
  `DEEPFALL_SELFTEST_PHASE6 a2 left_chunk old_chunk=5 unloaded=true far_chunk_loaded=true fg_still_mined=true`
  `DEEPFALL_SELFTEST_PHASE6 a3 returned still_mined=true chunk_visible=true layer_erased=true`
  `DEEPFALL_SELFTEST_PHASE6 c legacy_chunk 0->1 (expect 0->1) stream (0, 1)->(1, 1) (expect (0,1)->(1,1)) stream_at_16.5=(1, 1)`
  `DEEPFALL_TORCH_PLACED cell=(8, 20) held=2`
  `DEEPFALL_SAVE_LOADED mined=1 cracked=0 torches=1 slain=0 ore=0 pos=(480.0, 1312.0) hp=92`
  `DEEPFALL_SELFTEST_PHASE6 b reload mined_still_air=true torch_cell=(8, 20) torch_restored=true pos_restored=true hp=92 ore=0`
  `DEEPFALL_SELFTEST_PHASE6 done a=true a3=true c_legacy=true c_stream=true b=true`
  `DEEPFALL_SELFTEST done`
  That is: (a) mining a cell in chunk (0,1), leaving to chunk (4,0),
  and returning shows it still mined; (b) torch + position + HP
  survive an in-process rebuild from the save file; (c) crossing
  x=20 flips the legacy chunk 0→1 and crossing x=16 flips the
  stream chunk (0,1)→(1,1), with no errors.
- Restart proof, fresh process `--selftest-load` after the
  `--selftest` run (output verbatim):
  `DEEPFALL_SAVE_LOADED mined=1 cracked=0 torches=1 slain=0 ore=0 pos=(480.0, 1312.0) hp=92`
  `DEEPFALL_SELFTEST_LOAD mined=1 torches=1 slain=0 pos_ok=true hp_ok=true ore_ok=true PASS=true`
  The save file on disk after the selftest run:
  `{"cracked":[],"extracted":false,"kills":1,"mined":["2,21"],"ore":0,"player":{"hp":92,"x":480.0,"y":1312.0},"seed":20261101,"slain":[],"torches":{"8,20":"8,21"},"torches_held":2,"version":6}`
- Screenshot: `screenshot.png` re-rendered with `--new-run
  --screenshot` (clean spawn chamber, no save applied), 1,143,660
  bytes. It shows the tech soldier idle in the spawn chamber
  (timber tunnel, amber spire, torch, cave backdrop, gold ore
  bottom-centre), HUD reading `Stream: (0, 1) 6/15`, and the new
  SAVE / NEW buttons top-right. Regression found and fixed during
  this phase: the cave backdrop sprite was moved to sit before the
  first chunk FgLayer, which put it AFTER Player in child order
  (chunk layers are appended in code, not in scene order), so the
  big dark backdrop hid the player entirely — the first new
  screenshot showed an empty chamber. The backdrop is now moved to
  just before Player in child order and the player renders again.
  (Also learned: `--headless` gives the screenshot branch a null
  viewport texture — screenshots must run under xvfb without
  `--headless`, as in prior phases.)
- One ordering fix during this phase: the first chunk activation
  ran while the player was still at the (0, 0) default position,
  printing `stream=(0, 0)` and triggering a spurious chunk-change
  autosave at launch. The player is now positioned before chunk
  activation, so launch prints a single `stream=(0, 1) loaded=6/15`
  and no save at startup.

## Phase 7 — crafting + inventory (2026-11-05)

No AI images generated; staged assets + code only. Staged originals
copied, never moved: coal tile
(`staging/deepfall/tiles-real/terraria-blocks-new/64/coal.png` →
`assets/tiles/coal-ore.png`, 4 flip/brightness variants in
`assets/tiles2/coal-ore_v0..v3.png`, same recipe as Phase 2) and
lantern art (`staging/deepfall/items/lantern-64.png` →
`assets/items/lantern-64.png`). The workbench has no staged art — it
is a procedural prop (brown plank + legs + grey vice, code-drawn).

### Material sources (all Forgotten Mines only)

Mining is 2 hits as before; the break (not the crack) grants the
material. Wood-platform (id 7) is never mined, so it never gives
wood — only solid wood blocks (id 6) do.

| material | source tile | notes |
|---|---|---|
| wood | wood block, id 6 | NEW in Phase 7: 10 connected wood veins (28 cells, seed 20261101) in solid rock above rooms. Wood blocks existed as a tile id before but with **zero cells in the world** — torch crafting would have been impossible without this. Solid-to-solid, topology unchanged. |
| stone | stone 3, brick 8, mossy 9, cracked 10, obsidian 12 | brick/mossy/cracked/obsidian all read as stone |
| dirt | dirt 1, grass-dirt 2 | |
| coal | coal-ore, id 13 | NEW: 8 connected coal veins (22 cells) in solid rock above rooms, same walk shape as the ore veins, placed after them so the gold/amber ore count is untouched |
| gold ore | gold-ore, id 4 | also increments the legacy ore counter |
| amber ore | amber-ore, id 5 | also increments the legacy ore counter |
| sand | sand, id 11 | top rows, as generated since Phase 1 |

Enemy drops (deterministic, from spawn_id parity — never the global
RNG, so the same run always drops the same): bat drops nothing,
golem drops 2 stone, every other slug drops at most 1 coal (even
spawn_id) or 1 stone (odd spawn_id; test spawns with id −1 fall back
to 1 stone). Prints `DEEPFALL_DROP slug=… item=… n=…`.

### Recipes (full list)

- **Torch** = 1 wood + 1 coal, hand-crafted anywhere. Light radius 7
  tiles (unchanged in-game behaviour). Crafting is now the way
  torches are obtained; the player still starts with 3.
- **Glass block** = 2 sand, hand-crafted anywhere. Sub-recipe so the
  lantern chain is completable from sand, which is already a game
  tile/material.
- **Workbench** = 4 wood, hand-crafted anywhere. Placed on the floor
  as a prop the player stands near — it occupies a floor cell
  visually but has **no collision**: the player walks past/through
  its cell. Mining the floor under it pops it back into the
  workbench count; clicking it also picks it up.
- **Lantern** = 1 gold ore + 1 glass block + 1 torch, **at a
  workbench only** (within 3 tiles, Chebyshev). Light radius 10
  tiles, on the separate item layer like torches: no collision,
  destructible (click it and it drops itself intact), mining its
  support pops it off. Hangs from a solid block above or sits on a
  solid block below.

### The iron-plate decision

Option (b) from the brief, chosen deliberately. The locked lantern
recipe wants 1 iron plate, but the staged iron-ore tile is visually
indistinguishable from copper-ore (mean RGB 117,97,89 vs 126,105,95)
— the same reason iron/copper were fenced out entirely in Phase 2.
Re-adding iron silently would repeat that mistake. So the lantern
uses **1 gold ore instead of 1 iron plate**, and this substitution
is stated here and in the code (`RECIPES` comment in `main.gd`),
not hidden. Gold is visually distinct and already mined in this
chamber. The iron-plate recipe stays locked until iron is
distinguishable from copper; no iron ore was added to the world.

### Controls and UI

- **C** — open/close the crafting panel (desktop). **L** — place a
  lantern. **B** — place a workbench. **T** — place a torch
  (unchanged).
- Touch: a **CRAFT** button, bottom-centre (x 560–720, y 640–720).
  It overlaps neither twin stick (x 60–220 / 1060–1220), ATK
  (x 960–1040, y 550–630), TORCH, SAVE, nor NEW. Tapping it opens
  the panel; the panel has PLACE buttons for torch / lantern /
  workbench with live counts, so touch placing goes through the
  panel. Clicking inside the panel never mines the world behind it
  (the click is swallowed when it lands on the panel rect).
- Panel: lists all four recipes with ingredient counts and a Craft
  button each, greyed out when ingredients are missing (lantern
  shows "Craft (bench?)" when no workbench is in range, and
  crafting it then prints `DEEPFALL_CRAFT_FAIL … needs_workbench`
  plus a "needs workbench" status line). Crafting consumes
  ingredients and adds the item (torches to the torch count,
  lanterns / glass / workbenches to their counts).
- **The panel pauses nothing** — the game keeps running while it
  is open, enemies and all.
- HUD: one compact inventory readout on line 1 —
  `Inv W0 S0 C0 G0 A0 Sd0 Gl0` (wood, stone, coal, gold, amber,
  sand, glass). The "— Forgotten Mines" prefix and the legacy
  `Chunk: x//20` readout were dropped from line 1 to make room;
  the Stream readout stays. The second hint line still overflows
  the right edge (pre-existing, Phase 5 note).

### Persistence

Save is now **version 7** (`SAVE_VERSION = 7` in `scripts/main.gd`).
The delta JSON gains `inventory` (all 10 counts), `lanterns`
(`{"x,y": "support-x,support-y"}`), and `workbenches`
(`{"x,y": "floor-x,floor-y"}`). Old **v6 saves are ignored** with
the existing `DEEPFALL_SAVE_IGNORED` path — verified headless with
a hand-written v6 save (ignored, clean run, READY line unchanged).
There is no migration and no silent corruption. Crafting, lantern
and workbench place/pickup all autosave (`save_game("craft" /
"lantern" / "workbench")`).

### Verification (headless, xvfb + OpenGL 3, `--audio-driver Dummy`)

- Plain run: `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14
  ore_veins=31 spawn=(7, 20) exit=(73, 9) connected=true` —
  identical to Phases 1–6, no script errors. Coal (22 cells) and
  wood (28 cells) veins are solid-to-solid, so the air-cell count
  (1511) and every READY number are unchanged.
- `--selftest` (Phase 5 + 6 checks unchanged, then Phase 7):
  mining gives coal+1 wood+1 sand+1 gold+1; torch craft
  torches 2→3, wood 1→0, coal 1→0; glass craft true, glass=1,
  sand=0; lantern without a workbench fails (lantern stays 0);
  workbench craft true (held 1, wood 0), placed at (7, 20), near
  check true; lantern near the bench crafts true (lantern 1,
  gold 0, glass 0, torches 2); lantern placed at (8, 20);
  save → rebuild → load restores inventory, lantern, and
  workbench identically. `DEEPFALL_SELFTEST_PHASE7 done PASS=true`
  and `DEEPFALL_SELFTEST done`. (One real bug found by the test:
  the first vein walks drifted only downward into room air, so
  only 3 distinct wood cells existed — the walks now wander
  ±1 in both axes and the counts count distinct cells only.)
- Fresh-process `--selftest-load` after the selftest run:
  `DEEPFALL_SELFTEST_LOAD … PASS=true` and
  `DEEPFALL_SELFTEST_LOAD_PHASE7 inv_ok=true lanterns=1 lan_ok=true
  workbenches=1 bench_ok=true PASS7=true`. Save file on disk is
  version 7 with `inventory`, `lanterns`, `workbenches`.
- Screenshot: `screenshot.png` re-rendered with `--new-run
  --screenshot-craft --screenshot` (1,107,257 bytes). It shows the
  spawn chamber with the crafting panel open — all four recipes,
  greyed-out Craft buttons, Place row (Torch 3, Lantern 0,
  Workbench 0), Close (C) — plus the CRAFT button bottom-centre,
  the compact `Inv W0 S0 C0 G0 A0 Sd0 Gl0` readout, and
  `HP: 100/100 | Foes: 10 left (0 slain…` on line 1 (the final ")"
  is still just past the right edge at 1280 px; the hint line
  still overflows, as before).

### Honest limits (Phase 7)

- Headless only — **NOT real-device tested**. The CRAFT button
  placement, panel tap targets, and lantern/workbench feel on a
  phone are code-verified and screenshot-verified only.
- The lantern and the Phase 6 torch can share one cell (the
  self-test places the lantern at (8, 20), the same cell as the
  torch) — two lights stack there with no rule against it. Not a
  bug, but unpolished.
- A workbench's cell and a lantern's cell can overlap the same way;
  placement only checks the cell is air with a solid support/floor.
- Coal/wood veins sit in solid rock above rooms, so some cells are
  only reachable by mining through stone first — by design (they
  are mining targets, not floor pickups).
- Still not built: other regions, red soldier / hooded mage as
  playable classes, skeleton hero, Amber/Void shift (deferred),
  iron plate (locked, see above).

## Android build, Phase 6 (2026-11-05)
- APK: `exports/deepfall-phase1-debug.apk`, **64,861,856 bytes**,
  SHA-256 `b991db7e66f7daea6b003c2ec096e71ca7ef615cbfd7e1e42e38f1f11e551bc3`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  New `main.gdc` (35,620 bytes), `touch_ui.gdc`, `enemy.gdc`,
  and `icon-512.png` confirmed inside the APK. Exported with
  Godot 4.8 beta 1 headless, prebuilt template, build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section. Note: `--export-release` fails on this
  project (no release keystore configured — "Could not find release
  keystore"); the debug APK is built with `--export-debug`, which
  signs with the `~/.android/debug.keystore`, as in prior phases.
  (One benign aapt2 warning: themed_icon file reference missing.)
- NOT real-device tested.

Honest limits (Phase 6):
- Headless only — **NOT real-device tested**. Chunk pop-in on a
  real phone is unmeasured: chunks toggle visibility as a whole
  (no fade, no preloading beyond the 1-chunk halo), so a fast
  player crossing a boundary may see a 1-frame pop of the newly
  loaded chunk's props/lights. The 3×3 active set means the chunk
  ahead is usually already loaded before it is visible, but that
  is reasoning, not a measurement.
- Save edge cases: the save is a single slot with no backup — a
  crash mid-write can corrupt it (no atomic write / journal; a
  corrupt file fails JSON parse and is treated as "no save").
  There is no save-version migration: a version/seed mismatch is
  silently ignored. Player death does NOT autosave — a quit
  between dying and the next chunk change loses nothing (deltas
  are saved at the moment they happen), but HP/position after a
  death-respawn are only persisted at the next chunk-change /
  manual save.
- An unloaded alive enemy resets to its spawn cell at full HP
  when its chunk reloads — wandering progress and partial damage
  on live enemies are not persisted (only slain is a delta).
- The in-process reload in `--selftest` re-runs the whole world
  rebuild; the fresh-process `--selftest-load` is the real
  restart proof and it passed.
- The scene still contains the old empty FgLayer / WallLayer /
  EdgeLayer / DamageLayer nodes (unused since chunk layers are
  created in code); they are harmless but dead weight in the
  scene file.
- Still not built: crafting, other regions, red soldier / hooded
  mage as playable classes, skeleton hero, Amber/Void shift
  (deferred).

## Android build, Phase 7 (2026-11-05)
- APK: `exports/deepfall-phase1-debug.apk`, **64,969,810 bytes**,
  SHA-256 `d3e6d34d1303e0b83586b8b2e85962ef9ac697457e85d6adb1bae8e5a42f5676`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  New `main.gdc` (49,475 bytes), `map_gen.gdc`, `touch_ui.gdc`,
  coal-ore variants, lantern textures, and `icon-512.png`
  confirmed inside the APK. Exported with Godot 4.8 beta 1
  headless, prebuilt template, build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section, `--export-debug` (debug keystore, as in
  prior phases; `--export-release` fails — no release keystore).
- NOT real-device tested.

## Phase 8 — playable classes: tech soldier, red soldier, hooded mage (2026-11-05)
- Class select: a select screen on every new run (before the world is
  playable), three cards, each with its idle sprite, a one-line
  description, and its stats. Desktop: keys 1 / 2 / 3 pick directly,
  Left / Right move the highlight, Enter confirms. Touch: tap PLAY on
  a card. After picking, the run starts with that class (picking also
  saves immediately). Loading an existing save uses the saved class
  directly — no re-pick. NEW run (F9 / NEW button) clears the save,
  regenerates clean, and re-shows the select screen. The skeleton hero
  is a SEPARATE/unlockable hero, NOT a fourth starting class — it is
  not on the select screen and was not added as selectable.
- Class stats (real, in `player.gd` CLASS_DATA):
  - Tech Soldier: HP 100, melee 15, speed 1.0x, melee attack.
  - Red Soldier: HP 120, melee 20, speed 0.9x, melee attack.
  - Hooded Mage: HP 80, melee 10, speed 1.0x, ranged orb bolt
    (12 dmg, ~320px range, 500px/s, dies on solid blocks; same J /
    ATK input and 0.55s cooldown as melee; the shoot animation plays).
    No new damage-type system was invented.
  - Mining speed is identical for all three classes (mining is not
    class-gated). Enemy aggro / HP / damage are unchanged. Player
    death/respawn keeps the class.
- Animation sets wired (`assets/player_anim/<class>/`, built by
  `build_phase8_assets.py` from staged frames, MANIFEST.json in that
  folder; same canvases tech uses: 128x195 strip sets, 256x195
  walkcycle/melee/crouch/climb/swim, bottom-centre):
  - Tech: unchanged (idle 9, walk 9, shoot 5, walkcycle 4, fall 3,
    melee 4 — flat `assets/player_anim/` root, Phases 2-4 layout).
  - Red: idle 9, walk 9, shoot 5, reload 4, thruster 6, dying 6,
    walkcycle 4, melee 4, crouch 4, climb 4, swim 3.
  - Mage: idle 7, walk 7, shoot 5, reload 7, thruster 5, dying 5,
    walkcycle 4, melee 4, crouch 4, climb 4, swim 4.
  - Excluded, not faked: mage shoot is the 5 clean frames r2c0..c4 —
    `r2c5_shoot.png` (bad/partial, dark and truncated) is excluded
    and no `mage/shoot_5.png` exists in the tree. Red swim uses
    frames 0/1/3 only — frame 2 is a front-facing star-jump pose.
  - Driven in-game: idle, walk (walkcycle), shoot, melee, fall/land,
    hurt flicker, jump. Loaded but not yet driven by any game state
    (same gap tech has): reload, thruster, dying, crouch, climb,
    swim — no crouch/climb/swim state exists in-game yet, so those
    sets are in the tree but no state plays them.
  - No fall/land frames exist for red or mage: airborne reuses
    thruster frame 0 and landing reuses the lowest crouch frame
    (real frames of that character, not generated). Distinct
    fall/land poses are still missing for red/mage. Climb frames
    have ladders baked in (same caveat as the tech climb set).
    Red/mage walk cycles read as 2-pose alternations; mage swim is
    upright/wading — both used as-is.
- HUD: shows `Class: <name>` and `HP: <hp>/<max_hp>` (was hardcoded
  `/100`); the hint line adds `(orb bolt)` for the mage.
- Save: `SAVE_VERSION` 7 -> 8; the save JSON gains a `"class"` field.
  Old v7 saves are ignored via the existing `DEEPFALL_SAVE_IGNORED`
  path (verified: a hand-written v7-style save is ignored, clean run)
  — no migration, no silent corruption.
- Verification (headless, xvfb + OpenGL 3, Dummy audio): identical
  READY line (`seed=20261101 rooms=14/14 ore_veins=31 spawn=(7, 20)
  exit=(73, 9) connected=true`), no script errors. One parse error
  found and fixed during the build: `class_name` is a reserved
  GDScript keyword — the player field is `class_display_name`.
  `--selftest` Phase 8 lines (verbatim): each class loads its own
  frames with no tech-frame leak (`idle_path` contains its own class
  folder), stats differ as documented (tech 100/15/1.0, red
  120/20/0.9, mage 80/10/1.0 ranged), mage shoot is 5 frames with no
  bad-frame file, orb fired and a 20-HP ghoul took 12 (hp 8), red
  melee one-shots a 20-HP ghoul (hp 0), and class save -> rebuild ->
  load restores red (120/120) then mage (80/80) — `PASS=true`.
  Fresh-process `--selftest-load`: `save_class=mage live_class=mage
  class_ok=true`. Screenshots: `screenshot.png` is the chamber view
  with `Class: Tech Soldier | HP: 100/100` in the HUD; the class
  select screen was captured with `--screenshot --screenshot-class`
  (all three cards, sprites, stats, PLAY buttons visible).
  Headless flags: `--class=<id>` picks a class in `--selftest` /
  `--selftest-load`; plain `--screenshot` auto-picks tech.

Honest limits (Phase 8):
- Headless only — **NOT real-device tested**. Class-card tap
  targets, PLAY button placement, and the select screen on a real
  phone are screenshot-verified only; keyboard flow (1/2/3, arrows,
  Enter) is code-verified, not interactively playtested.
- Red/mage have no distinct fall/land poses (thruster/crouch reuse,
  above); reload/thruster/dying/crouch/climb/swim sets are loaded
  but no game state plays them yet.
- The mage orb has no trail or impact effect (a plain cyan disc);
  orb-vs-enemy hit radius is 28px.
- Still not built: other regions, skeleton hero (unlockable, not a
  starting class), Amber/Void shift (deferred).

## Android build, Phase 8 (2026-11-05)
- APK: `exports/deepfall-phase1-debug.apk`, **67,607,457 bytes**,
  SHA-256 `4ba587b91fb1e01f8e30a7a2f4b7ee02d1016bdd5aa03b8bd59d8542ad6be15c`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  Red/mage animation textures (114 files under
  `assets/player_anim/red/` + `assets/player_anim/mage/`), new
  `player.gdc` / `main.gdc`, and `icon-512.png` confirmed inside the
  APK. Exported with Godot 4.8 beta 1 headless, prebuilt template,
  build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section, `--export-debug` (debug keystore, as in
  prior phases; `--export-release` fails — no release keystore).
  One benign aapt2 warning: themed_icon file reference missing.
- NOT real-device tested.

## Phase 9 — polish pass: Forgotten Mines, graphics / physics / animation (2026-11-05)

REDEFINED scope: no second region, no new enemies or classes — nail the
one region first. Staged assets + code only, no AI images. Nothing
pushed, published, or submitted. Built by `build_phase9_assets.py`
(tech dying/thruster/crouch slices + 16 procedural transition/corner
tiles + frost-burst orb impact frames).

### Graphics

- True edge/corner/transition tiles (neighbour-derived, NOT a Godot
  terrain set): the staged rock/dirt atlas cells (`rock_0..15`,
  `dirt_0..15`) are 16 fill variants only — NO staged edge/corner/
  transition art exists, so a true autotile terrain set was not
  possible from staged art. What was built instead: `_fill_special(c)`
  in `main.gd` picks one of 16 procedurally generated 64x64 tiles
  (`assets/tiles2/trans_rock_{N,E,S,W}_v0`, `trans_dirt_{N,E,S,W}_v0`,
  `corner_rock_{TL,TR,BL,BR}_v0`, `corner_dirt_{TL,TR,BL,BR}_v0`,
  generated from rock_0/dirt_0 fills) — transition first (orthogonal
  solid neighbour of the other family, rock vs dirt, order N,E,S,W),
  then outer corner (two adjacent air orthogonals). Straight edges
  keep the old dark overlay (`_edge_for_cell` returns -1 for special
  cells, whose art already carries the boundary). Ore/built families
  are exempt (keep the overlay). Measured in the world: 62 transition
  cells, 52 corner cells; mining re-derives the 9 neighbouring cells
  (self-test: `transition_rederive changed=true`). What is still
  overlay: straight-edge wedges, and all ore/built boundaries.
- Parallax: two direct Main children in `_render_background` using the
  staged `assets/atlas3/cave-silhouettes.png` (1920x1280): far layer
  scale 1.5, z -3, modulate ~(0.35,0.42,0.58), base (-128,-200),
  world-pos rate 0.65x camera; mid layer scale 2.0, flip_h, z -2,
  modulate ~(0.5,0.58,0.75), base (0,-200), world-pos rate 0.35x
  camera. On-screen drift is therefore far 0.35x, mid 0.65x camera
  (farther drifts less). Self-test measured over a 2016 px camera
  move: far 1310.4 px (0.65x), mid 705.6 px (0.35x). The old static
  world-space cave backdrop is kept as-is underneath. (Manual
  Sprite2D layers, not ParallaxBackground, so the sprites stay in the
  lit canvas under CanvasModulate.)
- Lighting: torch visible pool was ~4 tiles vs the 7-tile spec radius.
  Diagnosis: NOT a renderer limit — the light texture IS 896 px
  (7 tiles) and the falloff was squared (`a*a`), which made the outer
  ring too dim to read against the ambient tint. Fix: falloff
  `pow(a,1.25)` in `_light_gradient_texture` — brightness at 4 tiles
  0.18 -> 0.35. Measured on `screenshot_pair_spawn.png` (ring-averaged
  rock brightness around the torch): 2-4 tiles ~92-98, 5 tiles 82,
  6 tiles 56, vs ambient ~25 — the pool now reads to ~6 tiles and
  fades at the 7-tile texture edge. Timber-post occluders narrowed
  from scale (2.5,1.0) to (1.0,1.0) (12 px wide x 128 tall) so the
  shadow wedge no longer darkens the gameplay area.
- Screenshot verification (`--screenshot-pair`, all 1280x720):
  spawn chamber (torch + posts + player in view, HUD fits), chunk
  gate at x=20 (continuous terrain, no chunk seam or void; the pale
  yellow squares in the dirt field are pre-existing SAND tiles,
  fg id 11, `sand_v0` mean (234,207,109) under ambient — not a
  Phase 9 artifact), trestle props in room 2 (even room: long timber
  platform with support posts + torches, verified visually). The cave
  backdrop reads as background depth, not terrain.
- HUD: split into two labels — line 1 font 20 -> 16, compacted
  (dropped the "DEEPFALL |" prefix; "D:20", "T:3", "S(0,1) 6/15"),
  line 2 is a new code-created `_hud2` Label, font 14, hint
  shortened to "(S+Space drops thru)". Measured: line1 892 px,
  line2 1225 px (limit < 1248 at 1280 px wide). The final ")" of the
  Foes count is no longer clipped.

### Physics (measured, scripted headless test — not "feels fine")

Theory: jump velocity -620, gravity 1800 -> height 620^2/(2*1800) =
106.8 px = 1.67 tiles, air time 2*620/1800 = 0.69 s (41 frames).
Measured (tech class, spawn floor): single jump 112.0 px / 1.75
tiles, 43 frames / 0.72 s; landing squash `_land_timer` 0.133 s
(0.15 s squash, one 1/60 step consumed). Double jump 207.3 px /
3.24 tiles, fired. Coyote 0.12 s: jumped 11 frames after walking off
a ledge, vel_y -620 (fired inside the window). Jump buffer 0.12 s:
press ~5 frames before landing fired 1 frame after touchdown
(`fired_within_frames=1`). Test note: the buffer test runs on a
floor column with clear air above it — the spawn room has a platform
192 px overhead and the double jump rises ~207 px, so the player
would land on the platform and the "within 50 px of the floor" press
window would never open (that is what the first version measured).
- One-way wood platforms: single jump cannot reach (107 px < 192 px
  gap; feet stay 80 px below the platform top, land back on the
  floor 1344); double jump lands on top (feet == platform top 1152).
  Drop-through ADDED: S + Space (desktop) or left-stick-down + jump
  (touch) — 0.25 s platform collision skip, falls back to the floor
  below (1344). Documented in the HUD hint line. The desktop S-key
  path itself cannot be simulated headless — code-verified only.
- Collision edge cases (scripted teleports): wall — right edge
  4799.99 vs wall left 4864, vel_x 0 (no penetration); mining the
  floor underfoot — feet +64 px (one tile), on_ground true; knockback
  — dx 0.00, no wall penetration. KNOWN GAP (pre-existing, NOT
  changed): horizontal knockback is effectively a no-op — `take_hit`
  sets vel.x = +/-220 and vel.y = -150, but `_physics_process`
  overwrites vel.x from the move input every step before
  `_move_axis`, so the player is never displaced horizontally by a
  hit; only the -150 hop applies. Bottom row: row 43 is entirely
  solid; lowest air cell found lands at y 2648, on_ground true —
  the player never falls out of the world.
- Twin sticks (code-level scripted input test, TouchUI node):
  dead zone 0.25 (v=0.14 -> move 0.00; v=0.5 -> move 0.50); left-
  stick jump threshold -0.6 (v=-0.71 -> jump, v=-0.14 -> no jump);
  stick-down v=0.7 -> crouch=true, drop=true; right stick 8-way
  mining (east, south-east both true); multi-touch (two sticks + ATK
  at once) atk_cooldown 0.55 (> 0). What was exercised: the input
  mapping and cooldown logic. What still needs a real phone: stick
  FEEL, multi-touch ergonomics, and the desktop S-key drop path.

### Animation

- Dying: plays on death before respawn (non-loop, 6 fps) — tech 6
  frames, red 6, mage 5; sprite hidden at the end; all fit inside
  main's 1.2 s respawn delay (tech/red 1.0 s, mage 0.83 s). No dying
  frames -> old behaviour (hide immediately).
- Crouch: hold S / Down / stick-down while on ground — crouch frames
  loop at 4 fps, speed 0.5x while crouching (130 vs 260). Collision
  box unchanged (documented). Tech crouch frames are the clean
  `multiframe/crouch/tech-soldier-crouch-0..3.png` set (the
  `tech-crouch-v2` GIF ghosts/double-exposes under PIL extraction and
  was NOT used as a source).
- Thruster: while airborne after the double jump, thruster frames
  loop at 8 fps (tech 6 frames now sliced; red 6, mage 5 already
  existed). Before the double jump, red/mage keep the existing
  static thruster[0] air pose and tech keeps its fall frames.
- Landing: uses the LAST frame consistently for all three classes —
  tech `fall_2`, red/mage `crouch_3` (deepest). (Changed from
  crouch[2] for red/mage.)
- Climb / swim / reload: NO ladder or water state exists in-game, and
  reload has no mechanic — documented as staged-but-untriggered, NO
  state was faked. Red/mage reload frames stay loaded but unplayed;
  tech reload frames exist staged (`r2c5..c8`) but were NOT sliced,
  since there is nothing to trigger them.
- Enemy animation: every mines slug's walk and attack actually play
  in-game (walk frames seen / attack started / attack frames seen):
  cave-bat-swarm 4/true/true, miner-ghoul 5/true/true, rock-golem
  4/true/true, cave-spider 4/true/true, ore-mimic 2/true/true
  (mimic is ambush, wander=false, so its walk barely advances —
  reported honestly), tunnel-worm 3/true/true. (Counts vary run to
  run: the 90-frame walk window can also catch chase/attack frames
  when the enemy closes range.) Bat FLIES now: sine hover
  (vel.y = sin(t*2.5)*24, clamped to hover base +/- 20 px), no
  gravity, no ground collision — measured hover range 19.2 px over
  2 s (partial sine cycle), dx != 0 (wanders), on_ground false.
  Small change, done; other slugs stay ground-walking.
- Mage orb: trail of small fading cyan dots (every 24 px travelled,
  0.25 s fade) + impact effect from the staged frost-burst frames
  (`assets/effects/orb_impact_0..2.png`, 12 fps, 0.25 s) on hit or
  range end. Self-test: fired=true, 6 trail dots after 6 steps,
  1 impact spawned, 0 FX left after 0.3 s.

### Self-test (Phase 9, `--new-run --selftest`, 2026-11-05)

`DEEPFALL_SELFTEST_PHASE9 done PASS=true` (Phases 6/7/8 still PASS
in the same runs). Verbatim Phase 9 lines:

```
DEEPFALL_SELFTEST_PHASE9 hud line1_px=892 line2_px=1225 (expect both < 1248)
DEEPFALL_SELFTEST_PHASE9 tiles transition_cells=62 corner_cells=52 (expect both > 0)
DEEPFALL_SELFTEST_PHASE9 parallax cam_dx=2016.0 far_dx=1310.4 (0.65x) mid_dx=705.6 (0.35x) (expect far 0.65x, mid 0.35x of camera)
DEEPFALL_SELFTEST_PHASE9 physics single_jump height_px=112.0 tiles=1.75 air_frames=43 air_s=0.72 (theory 106.8px/1.67 tiles/41 frames/0.69s) land_timer=0.133 (expect ~0.133)
DEEPFALL_SELFTEST_PHASE9 physics double_jump height_px=207.3 tiles=3.24 double_fired=true (expect ~200px/3.1 tiles/true)
DEEPFALL_SELFTEST_PHASE9 physics coyote left_after_frames=11 vel_y=-620 (expect -620: jump fired inside the 0.12s window)
DEEPFALL_SELFTEST_PHASE9 physics jump_buffer double_used=true pressed=true fired_within_frames=1 (expect true, true, <=3)
DEEPFALL_SELFTEST_PHASE9 platform single_jump min_feet_vs_plat_top=+80.0 land_feet=1344.0 (expect feet stay below the top, i.e. +85, and land back on the floor 1344)
DEEPFALL_SELFTEST_PHASE9 platform double_jump min_feet_vs_plat_top=-22.5 land_feet=1152.0 on_ground=true (expect feet pass above the top, land feet == plat top 1152)
DEEPFALL_SELFTEST_PHASE9 platform drop_through fired=true land_feet=1344.0 (expect true, 1344 = the floor below)
DEEPFALL_SELFTEST_PHASE9 collision wall right_edge=4799.99 wall_left=4864 vel_x=0.0 (expect right edge <= wall left + 0.5, vel_x 0)
DEEPFALL_SELFTEST_PHASE9 collision mine_floor feet_before=127 feet_after=191 on_ground=true (expect +64, true)
DEEPFALL_SELFTEST_PHASE9 collision knockback dx=0.00 right_edge=4846.00 wall_left=4864 (expect dx ~0, no penetration. NOTE: take_hit sets vel.x but _physics_process overwrites it with the move input every step, so the horizontal knockback never displaces the player — only the -150 hop applies. Pre-existing behaviour, not changed.)
DEEPFALL_SELFTEST_PHASE9 collision bottom_row y=2648.0 on_ground=true (expect y < 2880, true)
DEEPFALL_SELFTEST_PHASE9 sticks deadzone v=0.14 -> move=0.00 (expect 0.0); v=0.5 -> move=0.50 (expect 0.5); jump v=-0.71 -> true, v=-0.14 -> false (expect true/false); down v=0.7 -> crouch=true drop=true (expect true/true)
DEEPFALL_SELFTEST_PHASE9 sticks right_mine east=true south_east=true (expect true/true)
DEEPFALL_SELFTEST_PHASE9 sticks multitouch atk_cooldown=0.55 (expect > 0)
DEEPFALL_SELFTEST_PHASE9 enemy slug=cave-bat-swarm walk_frames_seen=4 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy slug=miner-ghoul walk_frames_seen=5 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy slug=rock-golem walk_frames_seen=6 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy slug=cave-spider walk_frames_seen=9 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy slug=ore-mimic walk_frames_seen=4 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy slug=tunnel-worm walk_frames_seen=2 attack_started=true attack_frames_seen=true (ore-mimic walk is 1 by design: ambush, wander=false)
DEEPFALL_SELFTEST_PHASE9 enemy bat hover_y_range=19.2 (expect <= 41, i.e. +-20 clamp) dx=-12.0 (expect != 0: it wanders) on_ground=false (expect false)
DEEPFALL_SELFTEST_PHASE9 anim dying class=tech frames_seen=6 (expect 6) hidden_at_end=true
DEEPFALL_SELFTEST_PHASE9 anim dying class=red frames_seen=6 (expect 6) hidden_at_end=true
DEEPFALL_SELFTEST_PHASE9 anim dying class=mage frames_seen=5 (expect 5) hidden_at_end=true
DEEPFALL_SELFTEST_PHASE9 anim crouch active=true frames_seen=3 speed_while_crouched=130 (expect true, >=2, 130 = half of 260)
DEEPFALL_SELFTEST_PHASE9 anim thruster double_jumped=true texture=res://assets/player_anim/thruster_0.png (expect true, a thruster frame)
DEEPFALL_SELFTEST_PHASE9 anim landing class=tech texture=res://assets/player_anim/fall_2.png (expect fall_2)
DEEPFALL_SELFTEST_PHASE9 anim landing class=red texture=res://assets/player_anim/red/crouch_3.png (expect crouch_3)
DEEPFALL_SELFTEST_PHASE9 anim landing class=mage texture=res://assets/player_anim/mage/crouch_3.png (expect crouch_3)
DEEPFALL_SELFTEST_PHASE9 orb fired=true trail_dots_after_6_steps=6 impact_spawned=1 fx_left_after_0.3s=0 (expect true, >=4, 1, 0)
DEEPFALL_SELFTEST_PHASE9 tiles transition_rederive cell=(1, 4) special_before=21 special_after=-1 changed=true (expect true)
DEEPFALL_SELFTEST_PHASE9 done PASS=true
```

Reload proof (`--selftest-load`, fresh process, no `--new-run` —
`--new-run` clears the save, so the load check must run WITHOUT it):
`DEEPFALL_SELFTEST_LOAD mined=0 torches=0 slain=0 pos_ok=true
hp_ok=true ore_ok=true PASS=true`,
`DEEPFALL_SELFTEST_LOAD_PHASE7 inv_ok=true lanterns=0 lan_ok=true
workbenches=0 bench_ok=true PASS7=true`,
`DEEPFALL_SELFTEST_LOAD_PHASE8 save_class=mage live_class=mage
class_ok=true`.

Headless READY line unchanged:
`DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31
spawn=(7, 20) exit=(73, 9) connected=true`, no script errors.

### Controls added / changed

- Drop-through: S + Space (desktop), left-stick-down + jump (touch).
  HUD hint line documents it.
- Crouch: hold S / Down (desktop) or left-stick-down (touch) while on
  ground; speed halves while crouching.
- No other controls changed. Class select, mining, torch, lantern,
  bench, craft, save/new unchanged.

### Still overlay / untriggered (honest limits)

- Straight-edge wedges and ore/built boundaries are still the dark
  overlay; only rock/dirt transitions and outer corners got real
  tile art (the staged atlas has no edge/corner art — the 16
  transition/corner tiles are procedurally generated from rock_0 /
  dirt_0).
- Climb, swim, and reload remain staged-but-untriggered (no ladder,
  water, or reload mechanic exists); tech reload frames were not
  even sliced.
- Horizontal knockback is a no-op (pre-existing, see Physics above).
- Twin-stick feel, multi-touch ergonomics, and the desktop S-key
  drop path still need a real phone. NOT real-device tested.

## Android build, Phase 9 (2026-11-05)
- APK: `exports/deepfall-phase1-debug.apk`, **70,425,512 bytes**,
  SHA-256 `2828e496e2bee8fff8a7570c26ac344a946ea20944942ed7b3e8b0084ed3601e`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  Exported with Godot 4.8 beta 1 headless, prebuilt template,
  build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section, `--export-debug` (debug keystore, as in
  prior phases; `--export-release` fails — no release keystore).
  One benign aapt stderr line: `AndroidManifest.xml:0: error: failed
  to read attribute 'android:required'` while dumping badging (the
  badging output itself is complete and correct). Pre-Phase-9 APK
  backed up at `/tmp/deepfall-phase1-pre9.apk` (67,607,457 bytes).
- NOT real-device tested.

## Phase 9b — Effekseer effects wiring (2026-11-05)

Two verified Effekseer effects (built in the use-them job, see
`assets/effects-effekseer/README.md`) are now wired into the live game.
No second region, no new enemies/classes; chunk streaming, save format
(SAVE_VERSION stays 8), classes, and twin-stick controls untouched.

### Plugin install

- **EffekseerForGodot4 1.80.5.1** (`EffekseerForGodot4-180_5_1.zip`,
  33,795,321 B, SHA-256
  `1a4987f748156b4707659e9b96b9e28dad42614e2862dc63ec0da8408e089cb6`,
  from `effekseer/EffekseerForGodot4` releases) in `addons/effekseer/`,
  enabled in `project.godot` (`[editor_plugins]`).
- **Trimmed to 9.5 MB, 20 files** (plus editor-generated `.uid` sidecars):
  only `bin/linux/libeffekseer.x86_64.so` (headless verification) and
  `bin/android/libeffekseer.arm32.so` + `libeffekseer.arm64.so` (the APK
  architectures) are kept; iOS/macOS/Web/Windows binaries dropped, and
  `effekseer.gdextension` was rewritten to list only the three present
  libraries (the stock file references all platforms).
- Both `.efkefc` files import as real `EffekseerEffect` resources
  (944 B orb / 825 B poof — the 187 B size means an empty import, see
  the SKFE trap below), with their `Texture/` folders alongside.

### What was wired

- **Mage orb impact** (`scripts/main.gd` `_spawn_orb_impact()`): an
  `EffekseerEmitter2D` (cyan shards + amber embers + shock ring, 0.67 s)
  **replaces** the staged frost-burst PNG flip when the plugin is
  present. The PNG frames stay as the fallback.
- **Enemy death poof** (`scripts/death_fx.gd`, used by enemies and the
  player death path): an `EffekseerEmitter2D` (grey smoke + orange
  embers + warm flash, 1.0 s, lives 1.1 s) **replaces** the
  `death_0..3.png` flip when the plugin is present. The PNG frames stay
  as the fallback.
- **Fallback, no hard dependency:** both call sites use `ClassDB` /
  dynamic `set`/`call` only — no static reference to any plugin class —
  so both scripts parse and run with the addon removed. Verified by
  running the full self-test with `addons/effekseer/` moved aside (see
  below).
- Emitters are one-shot: a child one-shot Timer frees each emitter
  after its effect length (orb 0.8 s, poof 1.1 s).

### Verification (headless, xvfb + OpenGL 3, `--audio-driver Dummy`)

- Identical READY line:
  `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14 ore_veins=31
  spawn=(7, 20) exit=(73, 9) connected=true`. No script errors.
- New `--selftest` Phase 9b (runs inside the existing self-test):
  `plugin_class_exists=true`, both `.efkefc` resources load,
  `emitters_created=[true, true]`,
  `duration orb=0.6667 (expect 0.6667) poof=1.0000 (expect 1.0000)`,
  `emitters_alive_after_90_frames=0 (expect 0)`,
  `DEEPFALL_SELFTEST_PHASE9B done PASS=true`.
- Phases 6/7/8/9 all still PASS in the same run
  (`DEEPFALL_SELFTEST_PHASE9 done PASS=true`).
  Two real bugs found and fixed during this wiring: (1)
  `calculate_duration()` lives on the `EffekseerEffect` resource, not
  the emitter (first run aborted with a script error);
  (2) the Phase 9 orb test counted impacts only in `_orb_fx`, so the
  Effekseer impact made it read 0 — the test now also counts live
  `EffekseerEmitter2D` children, and the hermetic cleanup in the orb
  test plus the world-teardown path now free stray emitters too (a
  stale emitter from the multitouch ATK test had double-counted the
  impact as 2 until that cleanup landed).
- Fresh-process `--selftest-load`: `PASS=true`, `PASS7=true`,
  `save_class=mage live_class=mage class_ok=true`. Save file cleared
  afterwards.
- **Fallback test (addon removed):** game still runs, READY identical,
  Phases 6–9 all PASS, no crash, no script errors; Phase 9b correctly
  reports `PASS=false` (`plugin_class_exists=false`). The PNG fallbacks
  play. Note: `load()` of the `.efkefc` resources logs ERROR lines
  ("Resource of unrecognized type in file: 'EffekseerEffect'") when the
  plugin is missing — handled nulls, console noise only.
- **Orb screenshot:** `--screenshot --screenshot-orb` fires a real orb
  impact in front of the player and captures it at ~0.1 s
  (`screenshot_orb.png`, 1,191,836 bytes). The burst IS visible in a
  4x crop of the impact point — a small soft white-cyan flash with
  cyan/amber specks at exactly the expected position — but at import
  scale 1.0 it reads small (~15 px flash) against the chamber. Scale
  left at the authored 1.0; emitter scale 2.0 is the open eyeball
  tuning if it reads too subtle on a real screen.
  (`screenshot.png` re-generated cleanly alongside it.)

### Android build, Phase 9b (2026-11-05)

- APK: `exports/deepfall-phase1-debug.apk`, **76,299,872 bytes**,
  SHA-256 `bd07b0fdfa145e304d36131608d2a520a867934660f7211d29e0dada37382f66`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `unzip -t` clean, `apksigner verify` v2 + v3 true, 1 signer.
  Confirmed inside: `lib/arm64-v8a/libeffekseer.arm64.so`,
  `lib/armeabi-v7a/libeffekseer.arm32.so`, both effect `.res` files
  (944 B / 825 B), both effect textures (`.ctex`), `icon-512.png`.
  Exported with Godot 4.8 beta 1 headless, prebuilt template,
  build-tools 36.1.0,
  `rendering/textures/vram_compression/import_etc2_astc=true` in the
  `[rendering]` section, `--export-debug` (debug keystore, as in prior
  phases). One benign aapt2 stderr line: the `themed_icon` file-reference
  warning (same as Phase 8).
- NOT real-device tested.

### Honest limits

- The SKFE trap (from the effects README, still true): the Effekseer
  CLI `-e` flag writes an `SKFE` container the plugin 1.80.5.1 parser
  rejects (empty 187 B import + `Failed load effect:`). Only `-o`
  exports (EFKE container) work in Godot. The shipped `.efkefc` files
  are `-o` exports; re-export with `-o` after any editor tweak.
- Orb impact at scale 1.0 reads small in-game (see screenshot note
  above); brightness/size on a real phone screen is unverified, as is
  the death poof against busy backgrounds. Both are eyeball items for
  the S25 playtest.
- Plugin adds ~5.9 MB of native libs to the APK (Phase 9 APK was
  70,425,512 bytes; this one is 76,299,872). Only the two Android
  architectures ship; the Linux `.so` is editor/verification-only and
  is not in the APK.
- The old PNG fallbacks are still in the tree and still work, but they
  are no longer the live path while the plugin is installed.

## Phase 10 — playtest fixes (2026-11-05)

Built from Skit's first real-phone playtest video (~22 s, spawn chamber,
tech soldier) and his words: "We need more fluid animations, a jump
button, mining and attacking are separated by tools selection like
pickaxe to a sword, character sprites need to match and look right."
Plus his correction the same day: the sprite problem is specifically the
walk cycle ("when he's in motion his sprite grows in size and doesnt
look like a side view of the character at all"), and the game is laggy
on the phone. Headless verification only — nothing here was
real-device tested.

### 1. Walk-cycle rescale (the sprite fix)

Root cause, measured in the assets: the walk-cycle frames
(`atlas-art/sliced/tech-walk-cycle/`, a separate generated sheet) were
at a different figure scale than the idle/shoot strips from
cleaned-regen, so swapping idle → walk visibly grew the character.
`build_phase10_walk.py` rescaled every walk frame so the figure height
matches idle exactly, feet anchored at the same +40 px line. Backups in
`assets/player_anim/walkcycle_orig/<class>/`.

Measured figure heights (alpha extent, before → after):

| class | idle | walk before | walk after |
|---|---|---|---|
| tech | 188–191 px | ~230 px (grew) | 189 px |
| red | 189–191 px | ~230 px (grew) | 189 px |
| mage | 102–106 px | ~130 px (grew) | 103 px |

Feet bottoms: walk 191 vs idle 192–193 (tech/red), 194 vs 195 (mage).
All 12 walk frames are true side views — none dropped. Tech walk_0's
boot tip is slightly clipped at the canvas left edge (was already at
the edge in the source; torso kept centred). The original brief's
"scale the player up modestly" was NOT done — inconsistency between
states was the problem, not overall size.
The in-game mid-walk shot (`screenshot_p10_walk.png`) shows a true
side-view stride at idle height, feet on the floor line. Verified in
the self-test (i) by scanning the authored PNGs' alpha extents — the
imported textures' `get_image()` is ETC2-compressed and its
decompression noise reads the full 195 px canvas, so the test loads
the PNG from disk instead.

### 2. Fluid animations (procedural — no new frames drawn)

The staged walk strips are only 4 frames; true drawn fluidity needs
more frames (the PixiEditor projects waiting on Skit's hand), so no
frames were faked. Motion was smoothed code-side in `player.gd`:

- Walk playback 8 fps, phase durations [1.3 / 0.7 / 1.3 / 0.7] s-units
  (contact frames held longer, passing frames shorter), vertical bob
  ±3 px peaking on passing frames, 0 on contact frames.
- Land squash 0.15 s (scale 0.55, 0.42 vs base 0.5 — i.e. 84% height,
  110% width), verified playing in the Phase 9 physics test
  (`land_timer=0.133`).
- Jump-takeoff stretch 0.12 s (scale 0.46, 0.54).
- Idle breathing: 2% vertical at 2.2 rad/s.
- Smooth facing flips: `scale.x` lerps across 0 at ~14/s (~0.1 s to
  turn); `flip_h` no longer used in the alive path.
- Melee swing: a slash-arc Polygon2D sweeps −65°..+65° during the
  0.55 s swing and fades, so the slash reads attached to the character
  (visible in `screenshot_p10_sword.png`).
- Feet stay anchored at +40 px through all of it (sprite origin is
  its centre; bob is 0 on contact frames).

### 3. Jump button (touch)

Dedicated JUMP button, bottom-right cluster, x960–1040 y450–530 —
directly above ATK, clear of the right stick, TORCH, CRAFT, SAVE and
NEW at 1280×720. It sets the same `touch_jump` flag as stick-up, so
coyote 0.12 s / jump buffer 0.12 s / double jump are identical to
Space and stick-up. Stick-up jump is kept as a secondary path.
Drop-through is now: hold left stick down + tap JUMP (S+Space on
desktop unchanged). Self-test (e) presses the real `_jump_down`
handler and confirms `touch_jump` fires.

### 4. Tool selection — pickaxe vs sword

- Two tools, both owned from the start. Pickaxe: mines (unchanged
  2-hit + crack), weak attack 5 dmg. Sword: class melee 15/20/10,
  cannot mine. Mage orb bolt fires only with the sword equipped.
- Switch: desktop Q toggles, 1 = pickaxe, 2 = sword. Touch: TOOL
  button (x480–548, y580–628) cycles; tapping a hotbar slot selects
  directly.
- With sword: E / click on a block does nothing to it and shows
  "Need pickaxe to mine" in the message log (never a silent fail);
  right-stick swings the sword toward the stick direction (air cells
  included). With pickaxe: E / click / right-stick mines as before.
- J / ATK attacks with the equipped tool's damage. Mining swings play
  the melee animation (not the shoot animation); sword swings play
  the same frames — honest reuse, stated here.
- HUD line 1 shows `Tool: Pickaxe` / `Tool: Sword`. The hint line was
  trimmed to fit: the F5-save / F9-new segment was dropped from the
  line (SAVE/NEW buttons are on screen; F5/F9 stay documented in
  Controls above). Measured widths at 1280×720: line 1 1156 px, hint
  995 px, log 119 px — all under 1248 px.
- Save format: SAVE_VERSION stays 8. The equipped tool is saved as
  `"tool"` in the JSON. Old v8 saves without the field load fine and
  default to pickaxe (verified in self-test (j) in-process and by a
  fresh-process `--selftest-load`).

### 5. Terraria / WazHack UI (borrowed layouts)

- Terraria-style hotbar, bottom-centre, 48×48 slots at y580–628:
  pickaxe x560–608, sword x616–664, torch x672–720. Selected slot
  full-bright, others dimmed. Icons are staged art copied into
  `assets/items/hotbar_pickaxe.png` (iron-pickaxe),
  `hotbar_sword.png` (hollow-city-sword), `hotbar_torch.png`
  (torch-64) — needed an editor import pass (`.import` files) before
  headless runs could load them. Torch slot places a torch.
- Terraria-style hearts, top-left under the hint line (y66–90): one
  heart per 10 max HP, full / partial / empty. The HP number stays in
  HUD line 1 as well.
- WazHack-style message log line, y548 x380–900, centred, font 14:
  shows the last event and stays until replaced — ore pickups,
  "Need pickaxe to mine", craft results ("Crafted Torch." and the
  failure reasons), "Slain <slug>", torch/lantern/workbench placed
  and picked up, tool switches.
- All existing HUD fields kept (depth, ore, inventory, foes);
  rearranged, nothing deleted. Nothing was dropped for fit.

### 6. Character readability + class-frame audit

- Rim/outline: a rim-glow Sprite2D behind the player (z −1, warm
  1.07× scale, mirrors texture/scale, hidden on death, restored on
  respawn) so the dark soldier reads against dark rock. Visible in
  the spawn screenshot; subtle — the soldier still reads mainly by
  its own teal accents.
- Class audit (all wired frames, alpha-extent measurement): every
  canvas is 195 px tall and every set's feet sit at alpha-bottom
  191–195 — no anchoring mismatch beyond the walk scale, fixed above.
  Known items, no action taken: red `walk_0` is front-facing (the
  `walk` set is unused in-game; the walkcycle is wired); red swim
  frame 2 is 131 px vs frame 1's 95 px (swim is staged-but-untriggered
  — no water mechanic); mage shoot is 5 frames with the bad r2c5
  frame excluded (Phase 8 test (c) confirms
  `bad_frame_file_exists=false`).

### 7. Performance pass (laggy on the phone)

Counts before → after, measured from the code in a typical spawn view:

| cost | before | after |
|---|---|---|
| Static PointLight2D in view (beacon 1, spire 1, chamber warm 2, gate 1, background glow 1, crystals 3) | 9 | 9 (unchanged — all shadowless except none) |
| Placed-torch lights (shadow on, one per torch) | uncapped | nearest 6 visible, shadows only on nearest 4; the rest fall back to a cheap gradient-glow sprite (never dark) |
| Chamber ember particles (2 lights × 10) | 20 | 12 (2 × 6) |
| Chunk TileMapLayers | 60 (15 chunks × 4) | 60 (unchanged — streaming is the design) |
| Parallax layers | 2 sprites (1920×1280), repositioned every frame | same 2, writes skipped when the camera hasn't moved |
| Effekseer emitters alive | 0 persistent (transient 0.67–1.0 s only) | unchanged — NOT removed; they are not the steady-state cost |
| CPUParticles2D in unloaded chunks | simulated while hidden | emission paused on chunk deactivation, resumed on re-entry |

Lights/particles in unloaded chunks: ember emission is now actually
stopped, not just hidden. Static chamber props (lights included) are
still hidden rather than freed on chunk swap — freeing them would
mean re-rendering the whole chamber on every re-entry, which costs
more than hiding them; hidden lights cost no draw calls. Props are
freed on world rebuild (`_clear_dynamic`), as before.
Headless frame-time proxy: none exists in the project, so the
counts above are the evidence and the before/after counts are the
improvement. Phone FPS cannot be measured headless — see honest
limits.

### Verification (headless, xvfb + OpenGL 3, --audio-driver Dummy)

- READY identical: `DEEPFALL_PHASE1_READY seed=20261101 rooms=14/14
  ore_veins=31 spawn=(7, 20) exit=(73, 9) connected=true`. No script
  errors.
- `--selftest` (full run): Phase 6 PASS, Phase 7 PASS, Phase 8 PASS,
  Phase 9 PASS, Phase 9b PASS, **Phase 10 PASS**. Phase 10 checks:
  (a) tool cycle Q/1/2 + player mirror; (b) sword cannot mine (block
  intact, log "Need pickaxe to mine"); (c) pickaxe mines (2-hit,
  block cleared); (d) pickaxe 5 dmg (ghoul 20→15), sword class dmg
  (ghoul 20→5 tech); (e) JUMP button triggers via the real handler;
  (f) HUD lines 1156 / 995 / 119 px; (g) hearts 10 at full HP, 6 at
  55 HP; (h) embers 12, chunk layers 60, parallax cache armed;
  (i) walk heights within the idle set's range for all 3 classes;
  (j) save round-trip version 8 + tool sword, and an old v8 save
  without the tool field loads defaulting to pickaxe.
- Fresh-process `--selftest-load`: `PASS=true` (mined/torches/slain/
  pos/hp/ore/inv/lanterns/workbenches/class all OK).
- Two regressions caught by the run and fixed in the tests (not the
  game): the Phase 8/9 mage-orb tests called `try_attack()` with the
  default pickaxe equipped, so no orb fired — the tests now equip the
  sword first (the orb's real precondition). Phase 9's mining tests
  (mine_floor, right-stick mine, transition re-derive) then failed
  with the sword still equipped — Phase 9 now restores the pickaxe
  at its start and before its tile test.
- Screenshots (all 1280×720, under xvfb): `screenshot.png`
  (1,185,458 B — spawn chamber, new JUMP/TOOL/hotbar/hearts/log
  visible), `screenshot_p10_mine.png` (1,182,688 B — pickaxe mining
  swing, "Saved (mine)" in HUD), `screenshot_p10_sword.png`
  (1,180,436 B — sword swing, slash arc attached, Tool: Sword),
  `screenshot_p10_walk.png` (1,185,566 B — mid-stride side view at
  idle height). First walk capture ran 0.6 s and caught the player
  walking off the platform edge mid-landing-squash; retaken at 0.35 s
  on flat ground.

### Android build, Phase 10 (2026-11-05)

- APK: `exports/deepfall-phase1-debug.apk`, **79,179,373 bytes**,
  SHA-256 `83265c85ad79f864919725397cdea9071b686adac69ef323e9dbc558f1a7079d`,
  package `com.dogbyte.deepfall`, version 1.0 (code 1), min SDK 24 /
  target SDK 36, debug-signed. Verified: `aapt2 dump badging`,
  `apksigner verify` v2 + v3 true, 1 signer, icon-512 inside, hotbar
  icons inside. New code inside: `assets/scripts/main.gdc`,
  `player.gdc`, `touch_ui.gdc` with fresh export timestamps — and
  byte-identical to a second deterministic export from the same
  source (the `.gdc` bytecode is opaque, so determinism is the
  check). Exported with Godot 4.8 beta 1 headless, `--export-debug`
  (debug keystore, as in prior phases). APK grew ~2.9 MB over Phase
  9b (new icons, hotbar art, Phase 10 code).
- NOT real-device tested.

### Honest limits

- Nothing in Phase 10 was real-device tested. Only Skit's phone can
  settle: jump-button thumb reach, tool-switch feel, whether the
  sprite now reads right at play size, whether the lag is actually
  gone (no headless FPS proxy exists), twin-stick feel, and the
  hotbar tap targets at phone scale. Phone aspect in his video is
  1600×720 vs the 1280×720 layout viewport — HUD positions assume
  1280 wide.
- The walk cycle is still only 4 poses per class — motion is smoother
  code-side, but true drawn fluidity needs the hand-drawn frames
  from the waiting PixiEditor projects.
- Mage orb fires only with the sword equipped: a fresh mage run
  starts on pickaxe and must press Q / 2 / TOOL before orbs work.
  That is the brief's rule, stated here so it isn't a surprise.
- Horizontal knockback is still a no-op (pre-existing, Phase 9
  note): `take_hit` sets `vel.x` but `_physics_process` overwrites
  it with move input every step; only the −150 hop applies.
- The rim glow is subtle by design (1.07×, warm, semi-transparent);
  if the soldier still blends in on the phone, it needs a stronger
  outline pass, not more glow.
