---
name: test-game
description: Run all three headless test scripts for this Godot game (unit tests, invariants, project check) and explain the results in plain language. Use after any change to scripts/sim/, data/*.json, or scripts in general, or when the user says "test", "check", "did I break anything", or "run the tests".
---

# Test the game

The developer has no coding experience. Run the checks, then report back in plain words.

## Steps

1. Run all three from the project root (they're independent, so run them in parallel):

   ```
   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_simulation.gd
   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_invariants.gd
   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/check_project.gd
   ```

   Exit code 0 = passed. Anything else = failed. Allow a few minutes for the invariants run.

2. If the invariants test fails, it prints a seed. Re-run just that game to see the step where it broke:
   `... -s tests/test_invariants.gd -- --seed=N`

3. Report as a short table: test name, passed/failed, one-line meaning.
   - `test_simulation`: the game rules, using test data.
   - `test_invariants`: random games with the real data; things that must always be true (no negative money or stock, "time away" equals "playing through it", old saves still load).
   - `check_project`: every script compiles, `data/*.json` is consistent, architecture rules are followed.

4. For each failure: quote the key error line, say in plain language what it means for the game (for example "a bakery could end up with -3 bread"), and name the likely file with a clickable link. Offer to fix it, but don't change code unless asked.

## Notes

- `check_project` "unknown setting" notes usually mean a new data key was added without listing it in `tests/check_project.gd` (`BUILDING_KEYS`, `RESOURCE_KEYS`, `CONFIG_KEYS`, ...). Say so.
- If a change touched `scripts/sim/` and no new test covers it, point that out. CLAUDE.md asks for a test for every new rule.
- Before raising `Simulation.SAVE_VERSION`, run `-s tests/test_invariants.gd -- --make-save-sample` first.
