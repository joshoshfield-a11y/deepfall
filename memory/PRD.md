# DEEPFALL — PRD

## Original request
"Access my github and find the deepfall game repo, and fix the controls, give it better sprite animations and sprites, fix graphics and add physics."
User choices: twin-stick (right stick = attack/mine in pulled direction), buttons for jump / item bar / skills / other; floating sticks that start where you touch on each side; Terraria/WazHack-appropriate sprites; physics = gravity/jumping/falling, solid collisions, knockback & bouncing, breakable/pushable objects; progress saved on phone; polish the current build before new biomes.

## Architecture
Godot 4.8 beta 1 (GDScript, GL Compatibility), Android export. Repo: joshoshfield-a11y/deepfall (cloned at /app).
- scripts/main.gd (world, mining, combat, save, HUD, Phase 11 aim/props/FX hooks + `--selftest-p11`)
- scripts/player.gd (physics movement, skills, aim), scripts/hero_rig.gd (pixel paper-doll animation, cape, swing trail)
- scripts/touch_ui.gd (floating sticks, multi-touch buttons, hotbar), scripts/phys_prop.gd (crates/barrels/pots), scripts/fx.gd (debris, shake, hit-stop, damage text, pickup flyers), scripts/enemy.gd (knockback physics, hit flash, telegraph)
- build_pixel_hero.py -> assets/hero/ (class parts, tools, props, workbench)

## Implemented (Phase 11, Jun 2026)
- Floating twin sticks; full multi-touch buttons (fixes JUMP/ATK failing while holding a stick); JUMP/DASH/SLAM/SWAP, hotbar with counts, CRAFT/SAVE/NEW(confirm); emulated-touch mouse clicks no longer mine under your finger; responsive layout (stretch canvas_items/expand, landscape)
- 360° aimed mining (reach 3.4 tiles, reticle) and aimed sword/staff attacks with cone hits
- Physics: accel/friction, variable jump, apex hang, real knockback (player + enemies, wall bounce), dash, ground slam, pushable/rolling/stacking props, breakable pots with loot, falling props crush enemies
- New pixel-art hero per class with procedural animations, class-select previews, workbench sprite, cleaner HUD
- Self-test `--selftest-p11` passes all checks (move, 2-finger jump, knockback, aimed mining, sword knockback, crate push, pot break, dash, slam)

## Implemented (Phase 12, Jun 2026)
- Pixel-art redraw of all 6 enemies with their own walk/attack animations
- Control settings menu (stick/button size, opacity, volume, vibration, left-handed, drag-to-move buttons, reset), saved on device
- Procedural sound effects for all core actions + haptic rumble
- Self-test `--selftest-p11` extended with P12 checks (all pass)

## Implemented (Phase 13, Jun 2026)
- Per-enemy pixel death animations + bouncing physical loot drops (mimic drops gold, golem sometimes amber)
- Smashed/pushed props persist in the save
- Run summary card (death/extract) with SHARE (PNG + clipboard brag text)
- Depth-reactive looping cave ambience + volume slider
- `--selftest-p11` now also runs P13 checks (all pass)

## Backlog
- P1: native Android share sheet (needs a share plugin); boss / ore events
- P1: on-device feel tuning (stick sizes, button placement options)
- P2: falling sand blocks, more skills per class, new biomes (deferred by user)
