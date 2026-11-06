# DEEPFALL: Relics of the Below

Side-view 2D roguelike dungeon platformer — Terraria-style block
mining/crafting/construction plus WazHack-style systemic, lethal dungeon
crawling. Godot 4.8 beta 1, GDScript.

Game Off 2026 entry (theme: SHIFT). Build-and-submit deadline: Dec 1, 2026.

## Status

Phase 10 (Nov 5, 2026): one polished Forgotten Mines slice — 14 rooms,
31 ore veins, 3 starting classes (tech soldier, red soldier, hooded mage),
chunk-streamed persistent world, save/reload, crafting, enemies and combat,
Effekseer orb/death effects, twin-stick touch controls, pickaxe/sword tool
selection, Terraria hotbar and hearts, WazHack message log.

## Open

Godot 4.8 beta 1 (editor + Android export templates). Open `project.godot`.
Android: export preset "Android (Debug)" with a debug keystore.

## Controls (Phase 11)

Touch (floating twin sticks — they appear wherever your thumb lands):
- Left half: MOVE stick (push down = crouch / drop through platforms, strong up-flick = jump)
- Right half: AIM stick — attack / mine in any direction you pull (hold to repeat, tap = attack ahead)
- JUMP (hold for higher jump, double jump), DASH, SLAM, SWAP tool
- Hotbar (top): pickaxe, sword/staff, torch, lantern, workbench (tap to equip / place)
- CRAFT, SAVE, NEW (tap twice) top-right

Desktop: A/D move, Space jump, Shift dash, F slam, mouse aim + hold LMB attack/mine,
J attack, Q / 1 / 2 tools, T torch, L lantern, B bench, C craft, F5 save, F9 new run.

## Phase 11 (graphics, physics, controls)

- Terraria-style pixel paper-doll hero per class (`build_pixel_hero.py` -> `assets/hero/`),
  procedural run / idle / jump / fall / land / crouch / dash poses, aimed tool swings with
  swing trails, verlet cape.
- Physics: acceleration + friction, variable jump height, apex hang, real knockback for
  player and enemies (wall bounce), pushable crates / rolling barrels, breakable pots with
  loot, props fall and crush enemies, ground slam shockwave.
- Juice: block debris, hit flash, damage numbers, pickup flyers, screen shake, hit-stop.
- Self-test: `godot -- --new-run --selftest-p11` (simulated multi-touch session).

## Phase 12 (enemy art, control settings, sound)

- All six enemies redrawn as pixel art matching the hero (`build_pixel_enemies.py` ->
  `assets/enemies_px/`), with distinct walk / attack frames, hit flash, squash and wind-up glow.
- MENU -> Controls & Feel: stick size, button size, opacity, sound volume, vibration,
  left-handed (mirrored) layout, MOVE BUTTONS drag editor, RESET. Saved to
  `user://deepfall_settings.json`; the game pauses while the menu is open.
- Procedural SFX (`build_sfx.py` -> `assets/sfx/`): swing, mine hit/break, hit, hurt, jump,
  land, dash, slam, pickup, prop break, enemy death. Phone vibration on hits, mining,
  slams and damage (Android VIBRATE permission enabled in the export preset).

## Phase 13 (death animations, loot, persistence, run card, ambience)

- Each enemy has its own 6-frame pixel death (flash, species motion, dissolve) played by a
  falling corpse (`enemy_corpse.gd`); drops are physical bouncing pickups with a magnet (`loot_drop.gd`).
- Smashed props stay gone and pushed props keep their place across save / reload.
- Run summary card on death and extraction (depth, kills, ore, blocks, props, deaths, loot)
  with SHARE (saves a PNG of the card + copies brag text) / KEEP DIGGING / NEW RUN.
- Looping cave ambience (`build_ambience.py`): drone, drips, rumbles; deeper = lower drone and
  louder rumbles. "Cave ambience" volume slider in MENU.
