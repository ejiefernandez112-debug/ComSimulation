# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Godot 4.7 (GDScript, **Compatibility** renderer) island village builder (production chains + player market). Full design lives in [plan.md](plan.md) — read the relevant section before building a feature. The developer has no prior coding experience: explain changes in plain language, keep scripts small and commented where intent isn't obvious.

## Current phase
**Phase 1a** — City Hall + Construction Office + Public Housing + Warehouse + Electric Substation pre-built; player builds Plantation (was Wheat Farm) → Grain Mill → Bakery; Retailer sell only; offline production; local JSON save. Do not build Phase 1b+ features unless asked. Some later systems (taxes, water, warehouses, cost per unit, Supermarket, building upgrades, construction materials bought at market prices (warehouse goods since 2026-10-06: used first when building, given back by demolishing), construction workers from Construction Offices, Water Treatment Plants, electricity (City Hall grid link, Wind Turbines, Electric Substations), roads with walkers and cars, production batches of 1–48 h with an output bonus, production chains Wave 1 (plant foods, animals, fish) with product choice, by-products, item categories and a Trading Post: plan.md §5.21–5.22, later waves planned there; happiness (simplified 2026-10-08: the plain average of seven needs, the service needs switching on as the village grows, four moods) with service buildings Clinic, Tavern, Chapel and Police Station: plan.md §5.6, §5.23; 2×2 building footprints on a 26×26 plot: plan.md §4; interface and event sounds: plan.md §5.24, ambience and music designed there but not built) were built early on request; plan.md section titles say which parts are "built", "planned" or "on trial".

## Architecture rules (plan.md §3.1 — non-negotiable)
1. **Data-driven content.** Buildings, recipes, resources, prices, timers live in `data/*.json`, loaded by the `GameData` autoload. Never hard-code tuning numbers in scripts.
2. **Simulation separate from presentation.** All game rules (jobs, offline catch-up, selling, population) live in non-visual autoloads under `scripts/autoload/` / `scripts/sim/`. Scenes under `scenes/` only call into them and display results. Visual nodes never own authoritative numbers.
3. **One clock.** Always use `TimeService.now()` (unix seconds). Never call `Time.get_unix_time_from_system()` anywhere else.
4. **Versioned saves.** Saves are JSON in `user://` with `save_version` + `last_saved_at`. Bumping the format means adding a migration step, never breaking old saves. Never save Godot Resource files as player data.

## Other rules
- Store timestamps (`started_at`/`finishes_at`), not countdowns. Offline catch-up is one math calculation, never a tick-by-tick replay. A clock set backwards must never produce negative progress.
- Only actively producing buildings should do per-frame work.
- In-game dev/debug tools go in `scenes/debug/` and load only when `OS.is_debug_build()`: the Developer window (F12, or 5 taps on the cash bar) and the performance overlay (F11, or its button in the Developer window: fps, draw calls, how long each tick takes, switches that hide map layers). Offline tools the game never loads (like the sprite studio) go in `tools/`.
- UI panels: Control nodes with anchors, so the same panel works as a mobile bottom sheet and a PC side panel.

## Performance rules (plan.md §9.1.1)
The game refreshes every second and must stay fast on phones and in big villages. `tests/check_project.gd` (part 4) enforces these, and a hook (`.claude/settings.json` → `.claude/hooks/check_after_edit.sh`) runs it after every `.gd` edit. A deliberate exception gets a `# perf-ok: why` comment on that line.
- Screens' `Economy.changed` refresh functions: update labels in place; never make/free nodes there (rebuild in a separate function, only when something changed); set colours with `UITheme.set_font_color()`.
- Never look up buildings or roads one by one inside a loop (`building_at`, `is_road`, `find_building`, `Economy.building`): build a map once (`_plot_map`, `road_cells`). `_footprint_problem` in a loop gets the map.
- Economy's heavy village-wide answers go through `_remember()`. In `scripts/sim/`, work out housing/employment/happiness/power once per step and pass them down (optional parameters), don't recompute.
- `_process` only for things that move, switched off with `set_process(false)` otherwise.
- After a change that could slow things down, run `tests/bench_performance.gd` and compare with the numbers in plan.md §9.1.1.

## How the code fits together
- `scripts/sim/simulation.gd` holds **all** game rules as pure static functions: no nodes, no clock, no files. Each one receives `(state, data, now)`. Player actions return `{ "ok": bool, "error": String, ... }`. "Settling" turns the time that has passed into finished output in one calculation.
- `scripts/sim/save_format.gd` turns the state into save text and back, and migrates old saves. To change the save's shape, raise `Simulation.SAVE_VERSION` and add a step to `_migrate()`.
- `Economy` autoload (`scripts/autoload/economy.gd`) owns the live `state`, supplies `TimeService.now()` and `GameData` to Simulation, writes `user://save.json` (plus a backup, written via a temp file), and emits `changed` so the UI can refresh. **Scenes read and change the game only through Economy.** Heavy village-wide questions (housing, happiness, employment, power...) go through `Economy._remember()`, which keeps the answer until the next tick or player action; screens refresh every second, so keep their work small (update labels in place, don't rebuild nodes each tick; `UITheme.set_font_color()` instead of re-applying a colour override).
- `GameData` loads `data/*.json` and is read-only. `Settings` keeps player preferences in a separate `user://settings.json`.
- **Sound:** scenes call `Sfx.play("id")` (`scripts/autoload/sfx.gd`); ids, files, buses and loudness are in `data/sounds.json`. Every button clicks by itself. Things that happen by themselves (construction finished, power short, ...) are played by `scenes/main/sound_cues.gd`. Simulation never plays sounds.
- **Money:** data files use plain dollars; the state and Simulation use whole **cents** (`Simulation.cents()`).
- `scenes/main/main.tscn` is the root: the Village View (`scenes/village/`, isometric island map) with the UI (`scenes/ui/`) drawn on top. `main.gd` passes UI requests and map taps on to Economy.

## Tests
Run these after any change to `scripts/sim/` (and add a test for any new rule). Exit code 0 means everything passed.
- `"C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_simulation.gd`: unit tests of the rules. Uses its own test data, not `data/*.json`.
- `... -s tests/test_invariants.gd`: plays random games with the real data and checks rules that must always hold, such as no negative numbers and "time away" ending exactly like "playing through it". Old saves in `tests/saves/` must still load. Options go after `--`: `--seed=N` replays one game step by step, plus `--games=N`, `--from=N`, `--steps=N`, and `--make-save-sample` (run it before raising `SAVE_VERSION`).
- `... -s tests/check_project.gd`: checks that every script compiles, that `data/*.json` is consistent (it flags unknown keys, so add new data keys to its lists), and runs text-search checks of the architecture rules above.
- `... -s tests/bench_performance.gd`: not a pass/fail test. Times the rules and the real screens for a small and a big (full plot) village, in ms (plan.md §9.1). Run it before and after a change that could slow the game down, and compare.

## Layout
- `tests/` — headless test scripts
- `data/` — JSON game content
- `scripts/autoload/` — global singletons (TimeService, GameData, Economy, Settings, Sfx)
- `scripts/sim/` — pure game-rule logic
- `scenes/` — visual scenes (main, village, ui, debug)
- `assets/` — art/audio. `assets/audio/sfx/` holds the sound effects (WAV), made by `tools/sfx/sound_studio.html` (open it in Chrome/Edge: listen, change a recipe, "Save all as WAV files"); don't hand-edit; which sound plays when, and how loud, is in `data/sounds.json`. `assets/fonts/` holds the game font (Overpass Medium and Bold, licence `Overpass-OFL.txt`; Fredoka and `Fredoka-OFL.txt` are only for `tools/encyclopedia.py`). `assets/buildings/` is generated by the sprite studio (one PNG per building id + `sprites.json`); don't hand-edit. The UI look ("Harbor Glass": dark glass panels, plan.md §6) is drawn by `scenes/ui/ui_theme.gd` itself, no skin pictures; its colours and sizes are in `data/ui_look.json`, which the developer edits live in the game (Developer window → Look), so screens must take colours and sizes from `UITheme`, never copy them into their own `const`s (the look and the button colours are explained at the top of it; new screens should build their buttons and labels with its `UITheme.button()` / `label()` helpers). `assets/ui/game_theme.tres` is made from it by `tools/make_theme.gd`, and `assets/ui/icons/` holds the icons (SVG; interface icons are white line drawings on a 24-unit grid; an item's icon is named after its resource id, e.g. `wheat.svg`)
- `tools/` — offline dev tools, never loaded by the game and excluded from exports. `tools/make_theme.gd` saves the UI look (`UITheme.build()`) as `assets/ui/game_theme.tres`, which scenes laid out in the Godot editor use (the Settings window, `scenes/ui/settings_panel.tscn`, is the first; other windows are still built in code). Re-run it after changing `ui_theme.gd`: `"C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tools/make_theme.gd`. `tools/sprite_studio.gd` photographs the 3D models listed in `tools/sprite_studio.json` into building sprites (plan.md §4). Run it after changing that list: `"C:\Program Files\Godot\Godot.exe.exe" --path . --rendering-method forward_plus -s tools/sprite_studio.gd` (needs a real GPU window, not `--headless`), then `--headless --path . --import`
- `art/` — our own 3D models, made by Blender from Python scripts (`art/blender/`; style kit in `kit.py`, one script per model in `models/`). Has a `.gdignore`. Build one: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python art/blender/build.py -- <building_id>` → `art/models/<id>.glb` + `art/previews/<id>.png` (both generated, not in Git), then re-run the sprite studio. Details: `art/README.md`
- `build/android/`, `export_presets.cfg` — Android export setup. `reports/` and `research_notes/` — background research write-ups (not game code)
- Run the game: open the project in Godot (main scene is `scenes/main/main.tscn`), or `"C:\Program Files\Godot\Godot.exe.exe" --path .`
- `Sprites kit/` — raw downloaded 3D model kits (CC0). Has a `.gdignore`, so Godot never imports them; only the studio reads them
