# CLAUDE.md

Godot 4.7 (GDScript, **Compatibility** renderer) business-sim game. Full design lives in [plan.md](plan.md) — read the relevant section before building a feature. The developer has no prior coding experience: explain changes in plain language, keep scripts small and commented where intent isn't obvious.

## Current phase
**Phase 1a** — Construction Office + Small House pre-built; player builds Wheat Farm → Flour Mill → Bakery; Retailer sell only; offline production; local JSON save. Do not build Phase 1b+ features unless asked.

## Architecture rules (plan.md §3.1 — non-negotiable)
1. **Data-driven content.** Buildings, recipes, resources, prices, timers live in `data/*.json`, loaded by the `GameData` autoload. Never hard-code tuning numbers in scripts.
2. **Simulation separate from presentation.** All game rules (jobs, offline catch-up, selling, population) live in non-visual autoloads under `scripts/autoload/` / `scripts/sim/`. Scenes under `scenes/` only call into them and display results. Visual nodes never own authoritative numbers.
3. **One clock.** Always use `TimeService.now()` (unix seconds). Never call `Time.get_unix_time_from_system()` anywhere else.
4. **Versioned saves.** Saves are JSON in `user://` with `save_version` + `last_saved_at`. Bumping the format means adding a migration step, never breaking old saves. Never save Godot Resource files as player data.

## Other rules
- Store timestamps (`started_at`/`finishes_at`), not countdowns. Offline catch-up is one math calculation, never a tick-by-tick replay. A clock set backwards must never produce negative progress.
- Only actively producing buildings should do per-frame work.
- Dev/debug tools go in `scenes/debug/` and load only when `OS.is_debug_build()`.
- UI panels: Control nodes with anchors, so the same panel works as a mobile bottom sheet and a PC side panel.

## Tests
Game rules are covered by `tests/test_simulation.gd` (uses its own test data, not `data/*.json`). Run after any change to `scripts/sim/` and add a test for new rules:
`"C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_simulation.gd` — exit code 0 = all passed.

## Layout
- `tests/` — headless test scripts
- `data/` — JSON game content
- `scripts/autoload/` — global singletons (TimeService, GameData, …)
- `scripts/sim/` — pure game-rule logic
- `scenes/` — visual scenes (main, ui, buildings, debug)
- `assets/` — art/audio
