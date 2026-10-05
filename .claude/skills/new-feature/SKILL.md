---
name: new-feature
description: Build a new game rule or system in this Godot game the project's way. Read plan.md, write the rule as a pure function in scripts/sim with a test, connect it through Economy, then add the UI, run the tests and update plan.md. Use when the user asks for a new mechanic, system, rule or feature (taxes, power, events, population changes, etc.), not just new content.
---

# Build a new feature

The developer has no coding experience. Work in small steps and explain each one in plain language.

## 0. Understand before coding

1. Find the matching section in [plan.md](../../../plan.md) and read it in full, plus §3.1 Architecture Principles.
2. Check the phase in CLAUDE.md. If the feature is marked "planned" for a later phase, say so and confirm the user wants it now.
3. If the plan doesn't decide something that changes the player's experience (a number, a choice of behaviour), ask. Don't guess silently. Give a recommendation.
4. Give a short plan: what changes, which files, and what the player will see.

## 1. Rules first (`scripts/sim/simulation.gd`)

- Pure static functions that take `(state, data, now)`. No nodes, no files, no `Time.*`.
- Player actions return `{ "ok": bool, "error": String, ... }`, and the error text is friendly enough to show in the game.
- Money is whole **cents** in state (`Simulation.cents()`); data files use dollars.
- Store timestamps (`started_at` / `finishes_at`), never countdowns. Offline catch-up must be one calculation, not a replay. A clock set backwards must never make progress negative.
- Tuning numbers go in `data/*.json` (usually `game_config.json`), never in the script. Add new keys to the lists in `tests/check_project.gd`.

## 2. Save format (only if the state's shape changes)

1. Run `"C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_invariants.gd -- --make-save-sample` **before** changing anything.
2. Raise `Simulation.SAVE_VERSION` and add a step to `_migrate()` in `scripts/sim/save_format.gd` that fills in the new fields for old saves.

## 3. Test the rule (`tests/test_simulation.gd`)

Add tests that use the test file's own data, not `data/*.json`: the normal case, an edge case (zero, full storage, no money) and the offline case (one long gap equals many short ones).

## 4. Connect it (`scripts/autoload/economy.gd`)

Scenes reach the game only through Economy. Add a thin method that calls Simulation with `TimeService.now()` and `GameData`, saves, and emits `changed`.

## 5. UI (`scenes/ui/`, `scenes/village/`)

- UI only displays and forwards taps. It never owns the real numbers.
- Control nodes with anchors, so it works as a mobile bottom sheet and a PC side panel.
- Only actively producing things should do per-frame work. Otherwise refresh on `Economy.changed`.
- Debug-only tools go in `scenes/debug/` behind `OS.is_debug_build()`.

## 6. Finish

1. Run the `test-game` skill. All three tests must pass.
2. Update plan.md: mark the section "built YYYY-MM-DD" or "on trial", and add a line to §15 Revision Log. Update CLAUDE.md's "Current phase" note if it lists early-built systems.
3. Sum up for the user in plain language: what the player will notice, which files changed, which numbers are placeholders, and how to try it in the game.
