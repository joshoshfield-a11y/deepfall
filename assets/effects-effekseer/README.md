# DEEPFALL — Effekseer particle effects

Two real Effekseer effects for DEEPFALL (Godot 4.8 beta 1, 2D side-view).
Built 2026-11-05 with Effekseer **1.80.8** (MIT) via its headless CLI — no
GUI mouse-driving, no AI images. Textures are procedural (PIL, white so the
particle `ColorAll` tints them).

## Files

```
assets/effects-effekseer/
  README.md                      this file
  build_effects.py               regenerates the textures + both .efkproj files
  verify-orb-in-editor.png       screenshot: mage_orb_impact open in Effekseer 1.80.8
  verify-poof-in-editor.png      screenshot: enemy_death_poof open in Effekseer 1.80.8
  mage_orb_impact/
    mage_orb_impact.efkproj     13,339 B  — editable project (open in Effekseer)
    mage_orb_impact.efkefc       5,750 B  — Godot build (EFKE container, see below)
    Texture/particle_soft.png    1,764 B  — 64x64 soft radial blob (white)
  enemy_death_poof/
    enemy_death_poof.efkproj    11,106 B  — editable project
    enemy_death_poof.efkefc      4,937 B  — Godot build (EFKE container)
    Texture/particle_soft.png    1,764 B  — same soft blob
    Texture/smoke_puff.png       5,218 B  — 128x128 irregular smoke blob (white)
```

SHA-256 (verify with `sha256sum`):

| file | sha256 |
|---|---|
| `mage_orb_impact/mage_orb_impact.efkefc` | `84b8a094…4f8` |
| `mage_orb_impact/mage_orb_impact.efkproj` | `a72bd1cf…4e4` |
| `enemy_death_poof/enemy_death_poof.efkefc` | `e5553149…a4c0` |
| `enemy_death_poof/enemy_death_poof.efkproj` | `8bc8a982…cb9` |
| `*/Texture/particle_soft.png` (identical in both) | `84a37301…6960` |
| `enemy_death_poof/Texture/smoke_puff.png` | `8778ce99…c0` |

## The two effects

### (a) `mage_orb_impact` — mage orb impact burst, cyan/amber, 0.67 s (40 frames @ 60 fps)

In the style of the staged `frost-burst` (cyan `60,120,255` / `120,200,255`,
small radial burst):

| node | what it does |
|---|---|
| `CoreFlash` | 1 particle, 8 frames, white-cyan flash, grows 2.0 → ~4.8, additive |
| `CyanShards` | 24 particles, 15–25 frames, sphere r=0.5, random velocity ±5, cyan `R 60–120 / G 140–200 / B 230–255`, additive, fade in 2 / out 10 |
| `AmberEmbers` | 12 particles, 25–35 frames, drift up (+1.0…+2.5 Y), amber `R 255 / G 150–200 / B 40–100`, additive |
| `ShockRing` | 1 expanding ring, 14 frames, cyan, additive, fade out 10 |

### (b) `enemy_death_poof` — enemy death poof, smoke/ember, 1.0 s (60 frames @ 60 fps)

Matches the grey (`150,150,150`) of the staged `death_*` PNG frames:

| node | what it does |
|---|---|
| `Smoke` | 10 particles, 35–55 frames, sphere r=0.6, slow rise (+0.4…+0.9 Y), scale 0.6–1.2 growing +0.05/frame, grey `130–170`, **normal blend** (not additive), fade in 8 / out 25 |
| `Embers` | 14 particles, 22–34 frames, fast rise (+1.2…+2.4 Y), orange `R 255 / G 110–170 / B 20–80`, additive, fade out 14 |
| `Flash` | 1 particle, 6 frames, warm white-orange flash, additive |

## Format — read this before re-exporting

**The `.efkefc` here is the `EFKE` container** (`INFO` + `EDIT` + `BIN_` chunks),
produced with the CLI **`-o` (save) flag, NOT `-e` (export)**:

```sh
Effekseer -cui -in mage_orb_impact.efkproj -o mage_orb_impact.efkefc
```

The `-e` flag writes a newer `SKFE` container (magic `SKFE`, version 1810).
That file is valid Effekseer, but the Godot plugin **1.80.5.1** rejects it:
its `EfkEfcFile` parser only accepts the `EFKE` magic, so import leaves the
effect empty and Godot prints `Failed load effect:` (proven — see
Verification below). Use `-o` for anything destined for Godot.

**Textures are NOT embedded in the `.efkefc`.** The binary only stores the
relative paths (`Texture/particle_soft.png`, …). Copy each effect's whole
folder — `.efkefc` **plus** its `Texture/` subfolder, same relative layout —
into `res://`, or the effect loads with missing textures.

## Wiring into Godot (EffekseerForGodot4 plugin, NOT yet installed in this project)

Plugin: **EffekseerForGodot4 1.80.5.1** (GDExtension, Godot 4.2+,
`effekseer/EffekseerForGodot4` releases, `EffekseerForGodot4-180_5_1.zip`,
33,795,321 B — prebuilt Linux/Android/macOS/Windows/iOS/Web binaries
included). Install steps:

1. Unzip the release, copy `addons/effekseer/` into the DEEPFALL project root.
2. Project Settings → Plugins → enable **Effekseer for Godot4**.
3. Copy `assets/effects-effekseer/mage_orb_impact/` and `enemy_death_poof/`
   (whole folders, `.efkefc` + `Texture/`) into `res://assets/effects-effekseer/`.
   Godot auto-imports each `.efkefc` as an `EffekseerEffect` resource
   (importer `effekseer.effect`, `.efkefc.res`).
4. In a scene, add an **`EffekseerEmitter2D`** node (DEEPFALL is 2D) and set
   its `effect` property to the imported `.efkefc` resource. `autoplay` is
   on by default; or call `emitter.play()`. `scale` / `speed` are emitter
   properties; import `scale` is on the `.efkefc` Import tab.
5. Suggested swap-in points (human call — **not wired yet**):
   - orb impact: `scripts/main.gd` `_spawn_orb_impact()` — replace/augment the
     `orb_impact_0..2.png` sprite flip with an `EffekseerEmitter2D` at `pos`,
     `play()` once, `queue_free()` after ~0.7 s.
   - death poof: `scripts/death_fx.gd` — replace/augment the `death_0..3.png`
     flip with an `EffekseerEmitter2D`, `play()` once, free after ~1.0 s.
   The current PNG-frame effects keep working as-is; this is an upgrade path,
   not a replacement already made.

Notes / caveats:

- The plugin's `addons/` tree is ~150 MB with all platforms; for the Android
  target only `bin/android/libeffekseer.*.so` is used — the rest can be trimmed
  if size matters.
- Effect scale: authored in Effekseer units at roughly 1 unit ≈ 1 tile px at
  import scale 1.0. If it reads too big/small in-game, tune the emitter's
  `scale` or the `.efkefc` import `scale` — do not re-author the project.
- The `.efkproj` files are the source of truth. `build_effects.py` regenerates
  them from scratch — **it overwrites hand edits made in the Effekseer
  editor**, so after editing in the GUI, re-export with the `-o` command above
  and do not re-run the script.

## Verification (all actually run 2026-11-05, nothing claimed unrun)

1. **CLI export works headless.** `Effekseer -cui -in <proj> -o <file>.efkefc`
   exits 0 for both effects (~2 s each). Earlier GUI-mode runs failed with
   `DllNotFoundException: Viewer` — that is GUI-only; the `-cui` path works.
2. **Projects open in the real editor.** Both `.efkproj` files launched in
   Effekseer 1.80.8 under `xvfb-run`, no errors; screenshots in this folder
   show the full node trees (`CoreFlash/CyanShards/AmberEmbers/ShockRing`
   and `Smoke/Embers/Flash`, all enabled) and the frame-0 flash rendering.
3. **`.efkefc` structure matches Effekseer's own samples.** `EFKE` magic,
   `INFO`/`EDIT`/`BIN_` chunks; `BIN_` payloads are 4,174 B (orb) and
   3,444 B (poof); texture paths embedded as UTF-16 (`Texture/particle_soft.png`,
   `Texture/smoke_puff.png`). Same layout as the stock `boss_death` export.
4. **Godot plugin import verified end-to-end** (scratch copy of the project,
   NOT the live tree — nothing was wired into `deepfall-game` itself):
   plugin 1.80.5.1 installed, `--headless --import` produced real
   `EffekseerEffect` resources (944 B / 825 B `.res`, vs 187 B empty on the
   failed SKFE attempt). A headless test scene created an
   `EffekseerEmitter2D` per effect, called `play()`, ran 90 frames with
   **zero errors**, and `calculate_duration()` returned exactly the authored
   lengths: **0.6667 s (orb, 40 frames)** and **1.0 s (poof, 60 frames)**.
5. **The SKFE trap, proven.** The `-e` export of these same projects — and
   of stock sample `boss_death.efkproj` — imports as an empty 187 B resource
   with `Failed load effect:`; the shipped sample `Laser01.efkefc` (old `EFKE`
   format) imports fine (843 B). Root cause read from the plugin/runtimes
   source: `EfkEfcFile` requires the `EFKE` magic. The `-o` files above are
   the fix.
6. **Not verified on a real device.** Headless Godot ran the effects; no
   Android APK was built with the plugin and nothing was played on the S25.
   That is the remaining human step (see below).

## What still needs a human hand

- **Install the plugin + wire the emitters** (steps 1–5 above) — a project
  decision, not done here; the live tree is untouched.
- **Eyeball the look in-game** (size, brightness, additive vs normal smoke
  against the Mines palette) and tune emitter/import `scale` if needed.
- **Real-device check**: build the APK with the plugin and play it on the S25.
- **Tune in the editor if wanted**: open the `.efkproj` in Effekseer 1.80.8
  on the laptop, tweak, re-export with `-o` (never `-e` for Godot).
