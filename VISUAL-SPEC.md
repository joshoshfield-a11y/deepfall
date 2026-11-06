# DEEPFALL — Forgotten Mines Visual Specification

**Status: SPEC ONLY.** No in-engine work is claimed by this document.
It does not change the Godot project, the TileSet, the lighting, or any
scene. It is the target that a later implementation pass should be
measured against. Phase 1 as it stands (see `PHASE1-README.md`) is a
playable, flat-lit, single-frame-player slice; this spec is the gap
between that slice and the concept image.

**Reference images (user-sent, this session):**
- Target: rich concept — rugged, individually shaded stone, irregular
  cave silhouettes, warm torchlight, cool blue atmospheric depth,
  detailed timber supports, moss, hanging roots, glowing crystals,
  a character that reads as part of the environment.
- Current: Phase 1 screenshot — uniform repeated 64 px tiles, flat
  lighting, a single static player frame pasted on a tile grid.
  Measured from that screenshot: the dominant flat grey is about
  `#4D4D4D`, dirt about `#72682F`–`#754A30`. The concept's darks run
  cooler and deeper, roughly `#0B1421`–`#11141E` in shadow, with warm
  light in the `#FF9A3C`–`#FFC46B` range. Those numbers are targets
  below, not measurements of finished art.

**Scope of this spec:** one polished Forgotten Mines chamber, in the
existing Godot 4.8 project (`gl_compatibility` renderer, 1280×720
viewport). Later regions reuse the same pipeline with their own
palettes; they are not specified here.

---

## 1. Final palette — Forgotten Mines

Design rule: warm light against cool dark. Nothing in the mine should
be neutral grey on its own — grey stone is always tinted either warm
near a light or cool blue in shadow. This is the single largest
difference between the concept and the Phase 1 screenshot.

| Role | Target | Notes |
|---|---|---|
| Ambient shadow / unlit cave | `#0B1420` (deep navy) to `#141A26` | CanvasModulate base, see §5. Must stay navigable, never pure black. |
| Deep background silhouette | `#0E1826` to `#1A2436` | Distant cave, back wall. Cooler and darker than playable stone. |
| Rock, lit | `#6E6A72` to `#8A8694` | Mid grey-violet. Top-left faces lightest. |
| Rock, shadow side | `#3A3A44` to `#4A4A56` | Right/bottom faces, crevices. |
| Crevice / crack line | `#1E1E26` | Near-black, never pure `#000000` except in keyed transparency. |
| Dirt | `#7A4A28` to `#9A6236` | Warm brown. Must stay warmer than stone so the two materials never merge. |
| Moss | `#4E7A3E` to `#7AA85A` | Only on exposed faces (see §3). Desaturate in shadow, do not use neon green. |
| Timber | `#6B4A26` (dark beam) to `#A87C46` (lit edge) | Warm brown, darker than dirt, with a lit top edge. |
| Torch flame core | `#FFE9A8` | Small, 2–4 px at native scale. |
| Torch glow | `#FFB35C` core falloff to `#FF8A2A` at the edge | See §5 for radius/falloff. |
| Crystal glow | `#7FE3F0` to `#3AB8D8` | Cyan, reserved for ore/crystal landmarks. Do not use cyan for anything else. |
| Amber ore / exit beacon | `#FFC46B` to `#FF9A3C` | Same family as torchlight, brighter and more saturated at the beacon. |
| Player accent (tech soldier) | Existing cyan armour lights, kept | The cyan must read against warm stone, not against cyan crystals — keep crystals sparse. |

Palette discipline: one warm family (torch/amber/timber/dirt), one
cool family (ambient/background/crystal), stone in between. Any new
tile that introduces a third hue family is out of spec until the
palette is revised.

**Measured staged baselines (for the remake brief, not the target):**
64 px staged tiles average roughly stone `#66676E`, dirt `#8C5636`,
mossy stone `#547B4F`, cave wall `#1A1D1F`. The staged stone is
usable as a *material sample* (see §7) but is too flat and too grey
on its own to hit the palette above — it needs the lighting pass
and the edge/variant work in §4 to get there.

---

## 2. Rendering resolution and camera

- **Gameplay tile: 64 px.** Phase 1 already uses 64 px staged tiles
  and grid collision; do not change the grid size in this pass.
  Changing tile size would rework generation, collision, and every
  staged asset at once.
- **Viewport: 1280×720** (existing `project.godot`). At 64 px tiles
  that is 20 × 11.25 tiles on screen — the chamber must be designed
  to read at that scale, not at editor zoom.
- **Texture filter: Nearest, mipmaps off** for all pixel art.
  No smoothing, no rotation of pixel sprites except the deliberate
  swing/recoil transforms already used in animation previews.
- **Pixel snap: on.** The player, tiles, and props must sit on whole
  pixels at the camera's scale; sub-pixel drift is what makes the
  Phase 1 player look pasted on.
- **Camera:** follows the player, centred, with a small lookahead in
  the facing direction (about 1 tile). No zoom changes inside a
  chamber. Camera limits must clamp to the generated region so the
  camera never reveals unfinished edges or void outside the map —
  this is a definition-of-done item (§9), and it is currently
  unproven in Phase 1.
- **Layer order (scene tree, top to bottom in draw order):**
  `Background (distant cave, parallax) → BackgroundWalls →
  Terrain (rock/dirt) → Platforms → Structures/Props →
  InteractiveObjects (torches, lanterns, ore, containers) →
  Actors (enemies, player) → Foreground framing (see §5) →
  Lighting → HUD`.
  The Phase 1 scene has the first part of this order but no
  background-depth or foreground-framing layers.

---

## 3. Terrain atlas layout and material rules

### 3.1 What the atlas must contain (Forgotten Mines only)

One atlas per material, each with the same grid, so a rock tile and
a dirt tile are interchangeable in code:

- **Base fill:** the solid block texture, seamless on all four edges
  when tiled 2×2 or larger. This is the current staged tile's job —
  and the staged tiles do not yet pass it: they carry a dark border
  and read as panels, not as a continuous material (see §7).
- **Variants:** at least 4 fill variants per material, chosen
  deterministically from the cell seed (same cell + same seed =
  same variant, always). Variants differ in crack placement, chip
  pattern, and highlight position — never in base hue.
- **Edge tiles:** straight edges for each side (top, bottom, left,
  right) where a material meets air or a different material.
- **Corners:** outer corners (convex) and inner corners (concave)
  for each material pair that actually occurs in Mines: rock–air,
  rock–dirt, dirt–air. No other pairs in this chamber.
- **Transitions:** rock↔dirt blend tiles, at least one straight
  transition per side. Dirt must never abut rock with a hard square
  cut — the concept's dirt-to-stone boundary is irregular.
- **Damaged states:** 3 stages per mineable material (intact →
  cracked → heavily cracked), used as mining feedback. Stage changes
  must be visible at 64 px at 1:1 zoom, not only at editor zoom.
- **Moss variants:** moss only on exposed top faces and on the
  upper third of exposed side faces, never inside a solid mass and
  never on a bottom face. Moss coverage must vary by variant, not
  be stamped identically on every tile.

### 3.2 Material rules

- **Rock:** irregular stone faces, not a uniform noise texture.
  Each face gets one highlight (top-left), one mid-tone body, and
  dark crevices between faces. Cracks are single-pixel dark lines
  that stop at face boundaries; they do not run across the whole
  tile in a straight line. Chipped edges break the square silhouette
  by 1–3 px — the edge overlay (§4) does the silhouette work, the
  fill does the surface work.
- **Dirt:** warmer, softer, smaller grain than rock. No hard
  geometric shapes. Pebbles are 1–3 px speckles, not drawn stones.
  Dirt-to-rock transitions are irregular, not a straight line.
- **Ore:** ore tiles are base rock or dirt with a distinct ore
  cluster on top — gold and amber already exist staged, but they
  must be distinguishable at a glance (see §7: iron vs copper is
  the known failure case). Rule: never rely on colour alone.
  Gold = warm yellow cluster, amber = orange glow cluster,
  iron = grey metallic, copper = teal-speckled. Pickup text (item
  name on collect) is the fallback, not the primary signal.
- **Background walls:** darker, lower-contrast versions of the
  foreground materials (about 40–50% brightness of the foreground
  equivalent), with no ore, no moss highlights, and no edge detail
  that competes with the playable layer. The staged `cave-wall-dark`
  (`#1A1D1F` average) and `dirt-wall` are the starting samples,
  but they need a silhouette variant (irregular cave wall, §4)
  before they read as a cavern rather than a dark flat fill.

### 3.3 What must NOT change

The collision grid is the authority. Autotiling, edge overlays,
variants, and damaged states are **visual only**. They must never
add, remove, or move a solid cell, and they must never make a
mineable block look unmineable or a solid block look like air.
Phase 1 already separates grid data (collision authority) from
TileMapLayers (visual); keep that separation until a deliberate
decision moves collision onto TileMap physics bodies.

---

## 4. Edge, corner, and autotile plan

Godot 4 `TileMapLayer` terrain sets, with peering bits. The plan is
deliberately the standard blob (47-tile) pattern, cut down to what
Mines actually needs:

1. **Terrain sets, one per material:** `rock`, `dirt`. Each set
   contains: 4 fill variants, 4 straight edges, 4 outer corners,
   4 inner corners, and the rock↔dirt transition set.
2. **Peering bits are assigned from the grid, not hand-painted.**
   The generator already knows, per cell, what its neighbours are;
   the TileMap build pass (currently in `scripts/main.gd`) must
   translate neighbour bits into terrain peering bits at build
   time, and re-translate the neighbours of any cell that is mined.
   This is the mechanism that makes mining "change the terrain and
   its neighbouring tile variants correctly" (§9).
3. **Edge overlays are a separate visual layer** on top of the fill,
   drawn only where a solid cell meets air. This is what breaks the
   square silhouette in the concept: the silhouette is irregular
   even though the collision cell is square. Overlays must align
   to tile edges exactly, with no gaps or overlaps at corners —
   the same centre-line discipline as the project's tile-overlay
   rule for linear features, applied here to edges.
4. **Slopes and half-blocks** use the staged slope set (see §7):
   stone/dirt/brick/grass/obsidian slopes, stone/dirt half-blocks,
   wood half-platform, wood/stone stairs. Almost all staged slopes
   face one direction; the opposite direction is a horizontal flip
   in Godot, and the collision shape must mirror with the flip.
   The two thin diagonal "ramp" cells are beams, not walkable
   platforms — use as decoration or discard, never as terrain.
5. **Platforms** (wood, mushroom-platform in later regions) are
   one-way: drawn as a distinct thin layer, collidable only from
   above, and never autotiled as solid rock.
6. **Determinism:** variant and edge selection is a pure function
   of (seed, cell, material, neighbour bits). No `randf()` at
   render time. A re-render of seed 20261101 must produce the same
   chamber pixel-for-pixel.

---

## 5. Lighting parameters

Phase 1 lighting is a radial-gradient sprite per torch. That is a
placeholder, not the spec. The spec lighting stack, in order:

### 5.1 Ambient — `CanvasModulate`

- **Colour: `#0B1420`, energy/brightness such that unlit areas
  stay readable.** Start at full CanvasModulate with that colour
  and tune down only until navigation is comfortable — the
  concept's unlit areas are dark blue, not black, and the player
  silhouette must stay readable against both rock and dirt.
- Ambient applies to the whole scene except the HUD. It must not
  tint the HUD, and it must not wash out the torch colours.

### 5.2 Torch — `PointLight2D`

- **Colour: `#FFB35C`, energy 1.0, texture: soft radial falloff**
  (no hard edge), **radius 7 tiles = 448 px** — matching the
  existing torch gameplay rule (light radius 7 tiles), not a new
  number.
- **Falloff:** bright core for the first ~1.5 tiles, smooth falloff
  to zero at 7 tiles. No hard cutoff ring.
- **Flicker:** subtle animated intensity only, ±5% at about 4–6 Hz
  with a smooth (sine/noise) curve. No rapid strobe flicker.
- **Count discipline:** start with 2–3 lights in the test chamber
  and measure frame cost before adding more. Every placed torch
  and lantern is a light; the generator must not place lights
  densely. If frame cost forces a cut, cut light count before
  cutting radius — a few good pools beat many weak ones.
- **Shadows / occlusion:** `LightOccluder2D` on terrain and on
  large structural props only, and only where shadows improve
  depth and readability. Selective occlusion, not every tile.
  This is a *test* item: in the `gl_compatibility` renderer,
  shadows must be verified on the target device (S25 + laptop)
  before being locked in. If shadows cost too much or render
  incorrectly under `gl_compatibility`, fall back to the
  gradient-pool approach with dark overlay shapes — and record
  that fallback in the implementation notes, do not silently
  ship a broken shadow pass.

### 5.3 Crystal — `PointLight2D`

- **Colour: `#7FE3F0`, energy 0.6, radius 3 tiles (192 px).**
  Reserved for crystal clusters and the amber exit beacon
  (beacon uses the amber colour, §1, at energy 1.0 and radius
  5 tiles). Crystals are landmarks: sparse, never per-tile.

### 5.4 Depth layers

- **Distant cave:** a parallax background layer (factor ~0.5)
  with large, dark, irregular silhouettes and occasional ruined
  structures. No gameplay information lives on this layer.
- **Foreground framing:** sparse dark rock shapes at the screen
  edges (top corners, occasional side intrusions) at parallax
  ~1.2, drawn *above* the player but never covering the player,
  an enemy, a torch, or a mineable target for more than a few
  pixels. If a foreground shape would cover gameplay, it does
  not spawn there — decoration rules must check gameplay
  clearance, not just visual variety.

---

## 6. Camera settings

See §2 for the base settings. Additional rules for the polished
chamber:

- **Follow:** player-centred with ~1 tile lookahead in facing
  direction, smoothed (lerp, not snap) so mining and jumping do
  not jitter the view.
- **Limits:** clamp to the generated region, with a margin of
  0 tiles beyond the outermost solid cell — no void, no
  unfinished edge, ever visible.
- **No camera shake** in the polished chamber pass. Shake is an
  effects item for later (explosions, damage), not a default.
- **Zoom: 1.0** at 1280×720. No dynamic zoom in this chamber.

---

## 7. Prop library — what exists staged vs what is genuinely missing

Audit basis: `staging/deepfall/tiles-real/` (112 Terraria tiles:
16 base + 16 new + 16 slopes + 64 biome/crafted), `items/`
(torch/lantern), `items-user*` (383 item sprites), `enemies/`
(24 enemy sprites), `cleaned-regen/` (207 character frames),
`multiframe/` (walk/attack/crouch/climb/melee/swim GIFs), and
the Phase 1 project (14 copied 64 px tiles + 1 player frame).

### 7.1 Reusable as-is (after the lighting pass, not before)

- **Base materials:** dirt, stone, mossy-stone, cracked-stone,
  brick, sand, obsidian, gold-ore, amber-ore, wood, wood-platform,
  cave-wall-dark, dirt-wall — as material *samples* and as the
  Phase 1 fill. They are not yet a seamless atlas (§4).
- **Mines dressing tiles:** mine-timber, rusty-metal, coal-seam,
  rail-block, damp-stone, mossy-mine-stone, fungal-brick,
  spore-stone, spore-dirt, fungal-soil, vine-wall, root-block —
  as wall/fill variants, not as standalone props.
- **Crafted building tiles:** oak/dark/pine planks, red/grey/
  sandstone bricks, marble-tile, iron/copper plates, glass-block,
  reinforced-metal, rope-plank, smooth-stone-floor — for built
  structures, not for natural cave.
- **Torch and lantern items:** `items/torch.png` (315×1079),
  `items/lantern.png` (425×923), plus 64 px icons. These are the
  correct item-layer art for the torch/lantern rule (craftable,
  destructible, drop themselves). The `terraria-crafted`
  `torch-wall` / `lantern-wall` tiles are wall art only and are
  superseded as light sources — do not wire them as lights.
- **Placeable structures (item sprites, not tiles):**
  campfire, lantern-post, wall-torch-sconce, supply-chest,
  workbench-kit, wooden-barricade, sandbag-pile, rope-ladder,
  automated-turret, spike-trap, tripwire-trap, healing-shrine —
  usable as interactive objects, scaled to the 64 px grid, with
  the caveat that they are single-pose sprites, not modular sets.
- **Mining tools:** support-beam-kit, chisel-set, rock-hammer,
  hand-drill, piton-set, climbing-rope-bundle, ore-sifter,
  core-sampler — usable as pickups and inventory icons.
- **Interactive tiles:** wooden-door, iron-gate, trapdoor,
  drawbridge-tile, checkpoint-beacon-tile, elevator-platform,
  moving-platform, one-way-platform, ladder-tile, portal-frame —
  usable as the chamber's interactive set, with portal-frame
  reserved (shift is deferred; do not wire it as a shift gate).

### 7.2 Reusable with rework (named flaws, not vague "needs polish")

- **All 112 Terraria tiles, as an atlas:** they are single
  full-square textures with dark borders. To become the §4 atlas
  they need: border removal / seamless edges, 4 variants per
  material, edge and corner tiles, and rock↔dirt transitions.
  This is the largest art gap in the spec.
- **Stone/ore mini-tile strip:** stone, gold-ore, and amber-ore
  cells carry a thin mini-tile strip at the bottom (model
  artifact). It must be cropped or repainted before those tiles
  are used as fill — it currently reads as a band in ore rows.
- **White sky corners:** grass-dirt, snow-dirt, and mushroom-grass
  tops have white corners. They only read correctly where sky is
  above them. In an underground chamber they need corner
  repainting or restriction to surface cells.
- **Iron vs copper:** the two ores look very similar
  (orange-brown; copper has teal speckles). Keep both, but do
  not rely on colour alone — see the ore rule in §3.2.
- **Slopes:** one direction only; opposite direction is a
  Godot flip (§4.4). The two ramp cells are beams, not platforms.
- **Object-style cells, use sparingly, never as fill:**
  glow-mushroom, mushroom-platform, glow-cap (single big
  mushrooms), collapsed-wall, void-crystal-wall (a hole),
  heat-vent, molten-wall. These are landmarks, not terrain.
- **Player character:** 42 cleaned tech-soldier frames exist,
  plus idle/walk/shoot/reload/thruster/dying strips and
  hurt/jump GIFs, plus multiframe crouch/melee/swim/climb
  sets. But Phase 1 uses exactly one frame. The strips are
  GIF previews, not wired `SpriteFrames`, and the walk cycle
  is subtle (small leg movement, reads as a shuffle at 8 fps).
  Wiring the existing strips is a code task; making the walk
  read as a walk is an art task if the strips do not improve
  under the lighting pass.

### 7.3 Genuinely missing — must be made, not found in staging

- **Seamless edge/corner/transition atlas** (§4). No staged file
  is an edge or corner tile.
- **Large background cave silhouettes** (irregular rock masses,
  stalactites, distant ruined structures) at larger than 64 px.
  No staged background layer exists; the current background is
  flat wall tiles.
- **Modular timber assembly:** beam, brace, joint, and post
  sprites that combine into timber supports of varying width
  and height. `mine-timber` is a 64 px tile, not a modular set;
  `support-beam-kit` is a tool icon, not a structure.
- **Hanging roots as props:** `root-block` and `vine-wall` are
  tiles, not hanging root strands with varied length and sway.
- **Large crystal clusters:** `crystal` (new-types), `amber-crystal`,
  `dark-crystal` are single tiles; the concept's glowing crystal
  clusters are larger, multi-tile landmarks with their own light
  (§5.3). No large cluster sprite exists.
- **Debris and rubble as scatter props:** `destruct-obstacles`
  and `destruct-containers` exist as item sprites, but there is
  no loose-rubble / broken-plank / loose-stone scatter set sized
  for chamber dressing.
- **Damaged-state tiles** (§3.1): no staged tile is a cracked
  stage of another tile; cracked-stone is a different material,
  not a damage stage.
- **Foreground framing shapes** (§5.4): no staged foreground
  rock shapes exist.

---

## 8. Animation requirements — player

All player animation must be wired as `SpriteFrames` (or
equivalent frame sequences) with a common anchor: **bottom-centre**
of every frame, on a common canvas size, so the feet never drift
when the animation changes. This is already the convention of the
staged strips; keep it.

| Animation | Source (staged) | Rate / type | Requirement for the polished chamber |
|---|---|---|---|
| Idle | `animations/*-idle.gif` (7–9 frames) | 4 fps, loop | Must hold still enough to read as idle, not sway. |
| Walk | `animations/*-walk.gif` (7–9 frames) | 8 fps, loop | Must read as legs alternating, not a shuffle. If the staged strip does not read at 1:1 under lighting, it is an art redo, not a timing change. |
| Jump | `*-jump.gif` (vertical arc) | One-shot, tied to vertical velocity | Must have distinct rise and fall poses; a single stretched idle frame is not a jump. |
| Fall | **Missing as a distinct set** | Loop while falling | Needs a falling pose distinct from jump-rise. Do not reuse jump-rise for falling. |
| Land | **Missing** | One-shot, ~150 ms | Small squash on landing. Must not interrupt movement. |
| Shoot | `*-shoot.gif` (5 frames) | 10 fps, one-shot | Muzzle flash from `effects/muzzle-flash.gif` on the firing frame only. Mage: exclude the known-bad `r2c5_shoot` frame (dark, truncated) — it is excluded from animations already and must stay excluded. |
| Melee | `multiframe/*-melee-v2/*.gif` (4 frames) | ~140 ms/frame, one-shot | Must show windup → strike → follow-through → recover with large limb movement (the strict-prompt standard used for the v2 sets). |
| Hurt | `*-hurt.gif` (red flicker) | One-shot | Must not move the player's collision position. |
| Dying | `*-dying.gif` (3–6 frames) | 6 fps, one-shot | Skeleton-hero dying is only 3 frames and reads fast — acceptable for Phase 1, flagged for a longer set later. |
| Crouch | `multiframe/*-crouch-v2/*.gif`, mage from `mage-crouch-redo/` | ~140 ms/frame | Must show a visible height drop. Mage crouch is the redo set (frames 3–4 separated); the old partial mage set (2 frames, no GIF) must not be used. |
| Climb | `multiframe/*-climb-v2/*.gif` (red, mage, miner, skeleton) | ~140 ms/frame, loop | Ladder is baked into every frame — these are reference/climb-loop material, not clean character-only sprites. Do not drop them over an in-game ladder (double-draw). Either mask the ladder out or use them as reference for a clean set. Tech climb is missing (generation failed, not retried) — tech soldier has no climb set. |
| Swim | `multiframe/*-swim-v2/*.gif` (all 5 characters) | ~140 ms/frame, loop | Red, miner, and skeleton each carry one front-facing frame that breaks a horizontal loop (frames 0/1/3 alone form a clean loop); mage's set is upright wading, not horizontal swimming. Use the clean subsets where a horizontal loop is required. |
| Thruster | `*-thruster.gif` (5–7 frames) | 8 fps, loop | Only if the thruster mechanic ships; otherwise do not wire it. |
| Reload | `*-reload.gif` (4–7 frames) | 6 fps, one-shot | Only if a reload mechanic ships. |

**Enemy animation** follows the same bottom-centre rule, using
the `enemies/animations/` sets (idle bob, attack lunge, hurt
flicker, death fade) plus the `multiframe/` walk/attack GIFs.
Transform-based previews (bob, lunge, flicker, fade) are labelled
SYNTH in `ANIMATIONS.md` and must be replicated in Godot with
tween/particles, not treated as hand-drawn frames. Real walk/attack
cycles are the multiframe sets; where a multiframe set is partial
(spider was 2/4, now 4/4 via redo; mimic best is 3/4; knight and
archer walks are 3/4; ash-wraith attack recover is a form-jump),
the partial set ships as-is and the gap is recorded, not faked.

**Effects (existing, `effects/`):** muzzle-flash, explosion,
impact-sparks, frost-burst, acid-splash, spore-puff, ember-burst,
void-implosion, smoke-puff, heal-sparkle, slash-arc. Damage-type
mapping is already documented in `ANIMATIONS.md` and is adopted
here unchanged.

---

## 9. Definition of done — one polished Forgotten Mines chamber

The chamber is done when **all** of the following are true, verified
in the actual Godot build (not in a screenshot or a spec):

1. **Terrain connects without visible seams.** A 5×5 block of each
   material, and every material-pair boundary in the chamber,
   shows no dark border grid, no panel read, and no corner gaps
   at 1:1 zoom.
2. **Lighting creates depth without hiding hazards.** Torch pools
   are warm and soft (§5.2), unlit areas are dark blue and still
   navigable (§5.1), crystals glow cyan (§5.3), and no enemy,
   ore, torch, or hazard is invisible in shadow.
3. **Player silhouette stays crisp** against rock, dirt, timber,
   and background, in both lit and unlit areas, and the feet do
   not drift when animations change (bottom-centre anchor, §8).
4. **Decoration never blocks gameplay.** No prop, foreground
   shape, or background silhouette covers a mineable target, an
   enemy attack, a torch, or the exit beacon, and no decoration
   sits on a cell the generator marks as a route.
5. **Mining updates neighbours correctly.** Mining a cell
   re-tiles its neighbours' edge/corner/variant bits (§4.2) and
   steps the mined material through its damaged states (§3.1)
   before it breaks. A mined-out cell leaves a clean opening,
   not a leftover edge fragment.
6. **Camera never reveals unfinished edges.** Panning to every
   corner of the chamber shows only generated, dressed terrain —
   no void, no untextured area, no streaming gap.
7. **Performance holds on target hardware.** Stable frame rate
   on the S25 and on laptop with the full lighting stack (§5)
   active in the chamber. If it does not hold, light count is
   cut before radius (§5.2) and the cut is recorded.
8. **The chamber contains, working:** the player (idle, walk,
   jump, fall, land, shoot, hurt, dying), a rocky ledge with a
   recognisable silhouette, a dirt-to-stone transition, a
   timber-supported mining chamber, at least one working torch
   or lantern with real light, one mineable ore vein, a distant
   blue-lit cavern visible through an opening, and a functioning
   HUD with actual movement.
9. **Determinism holds:** seed 20261101 re-renders the same
   chamber, including variants, edges, and decoration, every time.
10. **Known staged flaws are either fixed or fenced:** the
    ore mini-tile strip, the white sky corners, and the
    iron/copper confusion (§7.2) are each either repainted or
    explicitly restricted (e.g. white-corner tiles only on
    surface cells, iron/copper distinguished by pickup name).

**Explicitly out of this definition:** other regions, enemies as a
system (individual enemy sprites may appear as dressing only if
they do not imply combat), crafting, the Amber/Void shift
(deferred), chunk streaming, and save/load. Those are later
milestones, not part of "one polished chamber".

---

## 10. Biggest gaps, in order

1. **No seamless autotile atlas.** The 112 staged tiles are
   single full-square textures with dark borders. Everything
   else in this spec depends on this being remade (§4).
2. **No real lighting.** Phase 1 uses a gradient sprite per
   torch. CanvasModulate + PointLight2D + selective occlusion
   is unimplemented and untested under `gl_compatibility`.
3. **No depth layers.** No background cave silhouettes, no
   foreground framing, no parallax — only flat wall tiles.
4. **No modular props at game scale.** Timber, roots, and
   crystal clusters exist only as 64 px tiles or item icons,
   not as the larger assembled structures the concept shows.
5. **Player is a single placeholder frame.** The animation
   strips exist but are unwired, the walk reads as a shuffle,
   and fall/land poses do not exist as distinct sets.
6. **Tile flaws carried forward if unchecked:** ore mini-tile
   strip, white sky corners, iron/copper confusion, one-direction
   slopes, and the baked-in ladder on climb frames.

---

*Spec written from an on-disk audit of `staging/deepfall/` and
`deepfall-game/` (README + screenshot), against the two user-sent
images (concept vs Phase 1 screenshot). No Godot project files
were changed by this spec. The Android APK export running in
parallel was not touched.*
