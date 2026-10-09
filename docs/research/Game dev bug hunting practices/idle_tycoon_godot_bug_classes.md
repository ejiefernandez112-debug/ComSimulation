# Bug classes in idle / incremental / tycoon / economy-sim games and Godot 4 mobile+PC games, and how developers catch them

Research date: 2026-10-03 (Godot 4.7 current). Scope: a single-player Godot 4 business sim with production chains, offline catch-up from saved timestamps, money in whole cents, versioned local JSON saves, JSON content files, and Android + PC targets.

About "[Probe]" citations: some Godot facts below were checked directly by running small headless GDScript scripts on the user's installed **Godot v4.7.2.stable.official.ed1daf0bf** (Windows 11), in a throwaway scratch project, not the game project. They are primary evidence with no URL. Anyone can reproduce them with a few lines of script. Sources marked **[low quality]** are vendor marketing, AI-skill aggregator sites, or search-snippet-only claims. Do not rely on them for key claims.

---

## 1. Offline progress / idle catch-up: time away gives different results than playing, huge absences, clocks moved backwards or forwards

### Takeaway
Shipped idle games handle offline time in one of two ways. Some replay the gap as many coarse ticks, with a cap and a progress bar (Antimatter Dimensions). Others compute it in closed form (Pecorella's formulas). Either way, the common bugs fall into a few groups:
- the offline formula forgets a modifier, so the result differs from live play;
- huge gaps cause freezes or overflow;
- a backwards clock produces negative time;
- a forward clock is a free exploit.

Developers guard against these by clamping negative time to zero, capping the offline duration or tick count, and sometimes penalising a backwards clock. For single-player games, many simply accept forward-clock cheating.

### Cited Findings
- **Antimatter Dimensions (open-source JS idle game), offline catch-up code.** It converts the away-time into 50 ms ticks (`let ticks = Math.floor(seconds * 20);`). It caps them at a player-chosen `maxOfflineTicks` unless "fast" mode is on (`if (ticks > maxTicks && !fast) { ticks = maxTicks; }`). It guards against a backwards clock with `if (seconds < 0) return;`. It runs the catch-up asynchronously (`Async.run(...)`) behind a modal with "Speed up" (halves the remaining ticks, so less accurate) and "SKIP". — [AD source, src/game.js (GitHub, fetched 2026-10)](https://raw.githubusercontent.com/IvarK/AntimatterDimensionsSourceCode/master/src/game.js)
- **AD also clamps the live game loop's delta.** `Math.clamp(thisUpdate - player.lastUpdate, 1, 8.64e7)` limits each frame step to between 1 ms and 1 day. This stops one giant step when a tab or device wakes from sleep. — [AD source, src/game.js](https://raw.githubusercontent.com/IvarK/AntimatterDimensionsSourceCode/master/src/game.js)
- **AD's players describe the trade-off.** Higher max offline ticks gives more accurate offline progress but takes longer to compute. "Skip" drastically reduces the ticks, so you get almost no further progress. — [AD community wiki/Reddit via search snippet; low-quality confirmation](https://antimatter-dimensions.fandom.com/wiki/Guide)
- **Closed-form math instead of loops.** Pecorella (AdVenture Capitalist producer, Kongregate) gives:
  - next cost: `cost_next = cost_base × rate_growth^owned`
  - bulk cost: `cost = b·r^k·(r^n − 1)/(r − 1)`
  - max affordable: `max = floor(log_r(c(r−1)/(b·r^k) + 1))`
  - production: `(production_base × owned) × multipliers`

  The article does not cover offline progress itself. — [Pecorella, "The Math of Idle Games, Part I", 2016, Game Developer (orig. Kongregate blog)](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i)
- **Bug example, an offline formula missing a modifier (Idle Clans, 2023):** "Fixed combat offline progress not giving accurate results when using a potion of swiftness to reduce your attack speed. The modified attack speed wasn't factored in correctly and it was causing you to miss a lot of potential attacks during offline combat." The same patch fixed "daily boosts not properly resetting on date change if you were logged in at midnight server time" (a calendar-boundary bug). — [Idle Clans wiki, 8 May 2023 update notes](https://idleclans.wiki/w/5/8/2023_-_%27May_8th_updates%27)
- **More offline-catch-up fixes in indie idle-game changelogs** (search snippets of itch.io devlogs, not individually verified):
  - Idle Chaos 0.5.2 "fixed Techniques Offline Progress Calculation"
  - Power Idle "re-enabled Offline Progress and fixed Most Offline Progress Bugs"
  - Law of the Cat God 0.4.5b: departments "can now promote more than 999 Disciples when coming back" (a per-return cap bug) and "offline progression was optimized for much faster performance"

  Sources: [Idle Chaos devlog](https://dipi-is.itch.io/idle-chaos/devlog/517599/version-052-patch); [Power Idle devlog](https://itch.io/devlog/191222/transcension-bug-patch-2.amp); [LotCG devlog](https://aimless-studios.itch.io/lotcg/devlog/841099/045b-fixes-more-update)
- **Cookie Clicker, both clock directions.** Setting the clock forward lets the player "harvest all the sugar lumps in those time differences". Setting it back makes the next lump grow extremely slowly: the game says the lump "has been exposed to time travel shenanigans", and it takes "as long as how far back you have set in time plus the remaining time". — [Cookie Clicker wiki: Sugar Lumps](https://cookieclicker.wiki.gg/wiki/Sugar_Lumps)
- **Egg, Inc.** Opening the game with a date earlier than the last open reportedly pauses egg production for one hour. — [expertbeacon.com, **low quality**, unverified](https://expertbeacon.com/can-you-get-banned-from-egg-inc/)
- **Melvor Idle** reportedly caps offline progress, but snippets disagree: one says 18 hours, another 24 hours. One snippet also says offline progress "is simulated with perfect accuracy, with every single tick accounted for". — [Steam discussion via search snippet, unverified](https://steamcommunity.com/app/1267910/discussions/0/591762563949134719)
- **Godot forum thread (Mar 2025) on idle-game background progress:**
  - One answer suggests detecting clock tampering with scheduled "invisible local notifications", by comparing expected and actual fire times.
  - For leaderboards it suggests server-side timestamps at run start and at submit.
  - It also asks whether preventing single-player cheating is worth the effort.

  — [Godot Forum: Idle Game Background Progress (2025)](https://forum.godotengine.org/t/idle-game-background-progress/105645)
- **Godot clocks, [Probe] 4.7.2.** `Time.get_unix_time_from_system()` returns a **float** (wall clock, which the user can change). `Time.get_ticks_msec()` returns an **int** (time since engine start).
- **Vendor articles** say the same things: compute elapsed time from a trusted source, cap and integrate offline time correctly, spread catch-up work over frames, and detect "impossible" currency totals. — [bugnet.io, **low quality / vendor marketing**](https://bugnet.io/blog/how-to-fix-idle-game-offline-progress-wrong)

### Inferences
- **The most common shipped bug is that offline catch-up and live play disagree.** The Idle Clans case shows the typical cause: the offline path is a separate code path that misses a modifier. The cheapest guard is a parity test. Simulate N hours tick-by-tick in a test, then run the one-step offline calculation for the same N hours from the same start state, and assert the results match (exactly for whole goods and cents).
- **Production chains break single-rate formulas.** If the farm's wheat stock or the warehouse cap runs out partway through an absence, one "rate × elapsed" formula overproduces. Catch-up has to be split into segments at each event (stock runs out, storage fills, a job finishes). Test cases should cover "input runs out halfway" and "storage fills halfway".
- **Edge cases to keep as fixed test inputs:**
  - elapsed = 0
  - elapsed < 0 (clock moved back), which must give zero progress, as AD's `seconds < 0` guard does
  - elapsed = several years (overflow and performance)
  - a save whose `last_saved_at` is in the future
- **Choosing a response to a backwards clock** (AD, Cookie Clicker and Egg Inc each chose differently):
  - ignore it (zero progress, AD)
  - penalise it (Cookie Clicker, Egg Inc)
  - re-anchor `last_saved_at` to "now" so the clock moving forward again doesn't pay out twice.

  The re-anchoring point is an inference. Neither source described it.
- AD's 1-day clamp on frame delta is a cheap guard worth copying for the in-session loop. It stops a phone that slept for hours mid-frame from taking one huge step through a code path built for small steps.

### Gaps
- No primary developer write-ups (blog posts or talks) were found on offline-progress testing for Cookie Clicker, Melvor Idle, NGU Idle, Egg Inc, Clicker Heroes, AdVenture Capitalist or Spry Fox. Their offline caps and clock handling are known only from community wikis or snippets.
- Pecorella's Kongregate series (2016) covers growth, prestige and balance math, not offline-progress bugs.
- The exact Melvor offline cap (18 h vs 24 h) is unresolved.
- Egg Inc's one-hour pause rests on a low-quality source.
- The monotonic guarantee of `Time.get_ticks_msec()` was not fetched from docs this session; only its int type was probed.

---

## 2. Save files: corruption (crash mid-write, power loss, app killed), migration bugs, keeping old sample saves

### Takeaway
In Godot, `FileAccess.open(path, WRITE)` empties the existing file the moment it opens, and the new contents only land at `close()`. So a crash, kill or power loss in between leaves an empty or partial save, unless the game writes to a temp file and renames it over the old save. Renaming over an existing file works on Windows. Two techniques catch migration bugs in shipped games:
- **Determinism / save-load-compare tests** (Factorio).
- **A library of real old saves** loaded by each new version (Factorio asked players for saves before 0.17).

Shipped migration crashes, such as Stardew Valley 1.6's `SaveMigrator_1_6`, show what happens without them.

### Cited Findings
- **[Probe] 4.7.2, Windows: WRITE truncates immediately.** After `FileAccess.open(p, FileAccess.WRITE)` on an existing 27-byte save, the file on disk was **0 bytes** before anything was written. It stayed 0 until `close()`, then held the new content. No `.tmp` file was created. A crash in that window leaves an empty save.
- **[Probe] 4.7.2, Windows: rename overwrites.** `DirAccess.rename_absolute(tmp_path, existing_path)` returned OK and replaced the existing file's content. So temp-file-then-rename works with Godot's API on Windows.
- **Godot's own "safe save" is an editor-only setting.** `filesystem/on_save/safe_save_on_backup_then_rename` is listed under **EditorSettings**, which hold project-independent editor settings. — [Godot docs: EditorSettings (4.7)](https://docs.godotengine.org/en/stable/classes/class_editorsettings.html)
  - A snippet describes it as renaming the old file, saving the new one, and removing the old only afterwards, enabled by default, with a note about Windows antivirus interference. — [search snippet; full text not fetched](https://docs.godotengine.org/en/stable/classes/class_editorsettings.html)
  - The probe above confirms that a running game does not get this behaviour.
- **Factorio FFF #270 (23 Nov 2018), save/load overview:**
  - Requirement: "for a given save file (when no external factors change) saving, exiting, and loading the save shouldn't change any observable behavior."
  - Payoff: "we can easily test that saving and loading produces no observable change."
  - Migration bugs they hit: items changing type during migration and leaving wrong inventory contents; entity bounding boxes changing with prototype changes; electric-network membership changing when entity sizes change; destruction-order dependencies.
  - They dropped direct migration from 0.13/0.14 (players must step through intermediate versions).
  - The system had become "difficult for us to remember all of the special rules", so it was documented.

  — [Factorio FFF #270 (2018)](https://www.factorio.com/blog/post/fff-270)
- **Factorio's Rseding91 asked players for save files to test 0.17 migrations.** Saves had to be small enough to attach and run at ≥60 UPS. — [Factorio forums, "Save files for testing 0.17 migrations" (2018–19), via search snippet](https://forums.factorio.com/viewtopic.php?p=394317)
- **Stardew Valley 1.6.x (2024).** Players reported crashes on loading old saves with "Object reference not set to an instance of an object" in `SaveMigrator_1_6.cs`, across several 1.6 patch versions. — [Stardew Valley forums thread (2024), via search snippet](https://forums.stardewvalley.net/threads/save-file-corrupted-after-1-6-4-update.29420/latest)
  - Stardew's temp-file save and `_old` backups are covered in the sibling notes `Error handling in game development/player_facing_and_saves.md`.
- **Minecraft's DataFixerUpper.** Every chunk is versioned. On load, outdated data runs through a chain of upgraders to the current version, which is why years-old worlds still open. The fixers cannot run backwards, so newer worlds can't be opened by older versions. — [Madeline Miller, "Minecraft server forceUpgrade" (blog), via search snippet](https://madelinemiller.dev/blog/minecraft-server-forceupgrade/); [Minecraft.net "Programmers play: Minecraft's inner workings"](https://minecraft.net/article/programmers-play-minecrafts-inner-workings) (fetch timed out; content via snippet)
- **OpenTTD desync docs.** The listed root causes include "Incomplete gamestate representation". In other words, information that affects the simulation is not saved or loaded, which is the same bug that makes a single-player game behave differently after a reload. They recommend exporting savegames to JSON and comparing them semantically rather than byte-for-byte. — [OpenTTD docs/desync.md (GitHub)](https://github.com/OpenTTD/OpenTTD/blob/master/docs/desync.md)
- **Arms Trade Tycoon: Tanks 1.1.9.1 (2025-10-14):** "The breakthrough diceroll is now saved with the save". The random roll was not saved, so players could reload until they got a good result (savescumming). — [GOGDB release notes](https://www.gogdb.org/product/1613845936/releasenotes)
- **OpenRCT2 issue #19292 (Jan 2023).** Widening an overflowing money field to `money64` clashed with the fixed-size structs of the old s4/s6 save formats. The proposed fix keeps reading the legacy formats and declares a new save version that stores money64. — [OpenRCT2 GitHub #19292](https://github.com/OpenRCT2/OpenRCT2/issues/19292)
- **Vendor articles** recommend temp-file + rename, a `.bak` of the previous save, and a version number in every save. — [bugnet.io, **low quality / vendor**](https://bugnet.io/blog/game-save-best-practices-godot)

### Inferences
- **Safe save sequence for the game:**
  1. Serialize.
  2. Write `save.json.tmp`.
  3. `close()` it.
  4. Re-open the temp file and parse it to confirm it's valid JSON with the expected `save_version`.
  5. Copy or rename the current `save.json` to `save.json.bak`.
  6. Rename the temp file over `save.json`.

  On load, if `save.json` is missing, empty or fails to parse, fall back to `.bak`, then to any leftover `.tmp`.
- **Migration tests:** keep a folder of frozen fixture saves, one per past `save_version` plus odd cases (huge offline gap, clock moved backwards, empty warehouse, max money). A headless test loads each one, migrates it, checks invariants, re-saves, re-loads and compares the two dictionaries. This mirrors Factorio's save-load-no-change test and its player-save library.
- **Round-trip test:** save → load → save again, and the two JSON texts (or dictionaries) must be equal. This catches "state not saved" bugs: the OpenTTD "incomplete gamestate representation" class and the Arms Trade Tycoon dice roll.
- Never edit a migration step after release. Add a new one instead, because old fixture saves rely on the exact chain. This is inferred from DFU's chain-of-upgraders design.

### Gaps
- No primary source was found on how Paradox or RimWorld test old saves, or on checksums inside save files in idle games.
- Not verified:
  - whether Godot's `DirAccess.rename` is atomic on Android (ext4/F2FS renames are atomic in POSIX, but Godot's Android path was not checked);
  - whether `FileAccess.flush()` forces data to disk (fsync).
- The Factorio 0.17 save-collection thread and the Stardew `SaveMigrator_1_6` crash rest on search snippets.

---

## 3. Money and numbers: float drift, integer overflow, big-number precision, rounding of prices and taxes

### Takeaway
Integer cents avoid float drift. But a Godot JSON save hands every number back as a **float**, and type-strict code then fails quietly: `match`, `has()`, typed-int truncation. Godot ints also wrap silently on overflow. Shipped tycoon games have had real money-overflow bugs: OpenRCT2's 32-bit bank balance and overflowing ride value. OpenTTD uses a clamping "overflow-safe" integer for money. Incremental games that go past about 1e308 use mantissa+exponent big-number libraries, trading accuracy for speed.

### Cited Findings
- **[Probe] 4.7.2: float drift and truncation**
  - Adding 0.1 ten times gives `0.99999999999999989` (≠ 1.0).
  - `int(19.99 * 100.0)` = **1998**, while `roundi(19.99 * 100.0)` = 1999.
  - `int(0.29 * 100.0)` = **28**.

  So converting float prices to cents with `int()` loses a cent.
- **[Probe] 4.7.2: silent int overflow**
  - `9223372036854775807 + 1` = `-9223372036854775808`.
  - `int(1e19)` = `-9223372036854775808`.

  No error or warning was printed.
- **[Probe] 4.7.2: JSON numbers come back as floats**
  - `JSON.parse_string('{"a": 100}')["a"]` is a float, `100.0`.
  - 2^53+1 (`9007199254740993`) loads as `9007199254740992`.
  - `JSON.stringify` writes ints without ".0", so the loss happens on load.
  - Saving `{"cash_cents": 123456789}` and loading it back gives a float that compares `==` to the int but fails `is int`.
- **[Probe] 4.7.2: type-strict code breaks on JSON-loaded numbers**
  - Assigning JSON `2.7` to `var y: int` silently gives `2`.
  - `match` on `100:` misses float `100.0`.
  - `{100: "a"}.has(100.0)` and `[100].has(100.0)` are both false.
  - `str(100.0)` gives `"100.0"`, so stray ".0" can appear in UI text.
- **[Probe] 4.7.2: JSON.from_native / to_native.** `JSON.from_native({"cash": 100})` gives `{"args":["s:cash","i:100"],"type":"Dictionary"}`, and `JSON.to_native` restores an int. This is a type-preserving (but verbose) alternative.
- **Godot's JSON class reference:** "converting a Variant to JSON text will convert all numerical values to float types". Numbers are parsed with `String.to_float()`. `full_precision` on stringify adds the "unreliable digits" so floats decode exactly. — [Godot docs: JSON (4.7)](https://docs.godotengine.org/en/stable/classes/class_json.html)
- **OpenTTD money type.** `Money` is `OverflowSafeInt64`. On overflow of multiplication or addition, the result is clamped to `T_MAX`/`T_MIN` instead of wrapping, using compiler builtins such as `__builtin_mul_overflow`. — [OpenTTD source docs: overflowsafe_type.hpp (2026)](https://docs.openttd.org/source/df/d61/overflowsafe__type_8hpp_source)
- **OpenRCT2 #19292 (Jan 2023).** In free-entry, pay-per-ride parks, `totalRideValue` overflowed in `Park.cpp`, producing a false "entry fee too high" message. The same report cites #18087: the bank balance was clamped to a 32-bit integer on every transaction. — [OpenRCT2 GitHub #19292](https://github.com/OpenRCT2/OpenRCT2/issues/19292)
- **break_infinity.js.** It exists because JavaScript numbers top out near 1e308. It stores numbers as mantissa + exponent, reaching about 1e(9e15), and prioritises "speed over accuracy" (use decimal.js when accuracy matters). Antimatter Dimensions' "script time improved by 4.5x after swapping from decimal.js to break_infinity.js". The successor, break_eternity.js, handles tetration-scale numbers. — [break_infinity.js README (GitHub)](https://github.com/Patashu/break_infinity.js)
- **Exponential costs outgrow any polynomial.** "exponential growth will eventually catch and far exceed any polynomial growth", which is why idle-game numbers explode. — [Pecorella, Math of Idle Games Part I (2016)](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-i)

### Inferences
- **Load-time normalization pass:** after `JSON.parse_string`, convert every money/quantity/timestamp field to int (with `roundi` or `int`, checking the value is integral) before any game code touches it. Better still, have the migration/validation step reject non-integral cents. This stops the `match`/`has`/`is int` failures and the "100.0" display bugs.
- **No exactness problem in cents below 2^53** (about $90 trillion), so float storage in JSON is safe for this game's scale once it is converted back to int. Saving totals near 2^53 would lose cents.
- **Rounding rule for taxes and percentages:** compute in integer cents with one explicit, tested rule, for example `(amount_cents * rate_basis_points + 5000) / 10000` with round-half-up. The `integer_division` warning will flag the `/`, so it should be suppressed deliberately where integer division is intended. Test fixtures should pin values like 19.99 and 0.29, which fail with naive float-to-int conversion.
- **Overflow guards:** since Godot wraps silently, a cheap invariant check ("cash is never negative unless debt is allowed, and never above a sane maximum") after each simulated step catches wrapping. Clamped helper functions (like OpenTTD's OverflowSafeInt) can cap money at a maximum.
- Exponential cost formulas (`base × rate^owned`) in int cents overflow int64 (~9.2e18 cents ≈ $92 quadrillion) after a modest number of purchases with rate ≥ 1.07. Compute them in float and convert at the end, or cap the purchase count.

### Gaps
- No primary-source example was found of a float-drift money bug in a shipped tycoon game (as opposed to overflow).
- No Godot-specific big-number library was evaluated.

---

## 4. Economy and balance exploits in tycoon/production games: infinite-money loops, arbitrage, refund exploits, duplication; how developers find them

### Takeaway
The recurring exploit shapes are:
- **asymmetric buy/refund:** refund at the full price after buying at a discount;
- **financial loops:** sell shares, borrow, buy back cheaper;
- **duplication during state transitions:** quick-replace, placing, moving between inventories;
- **re-rollable randomness** that isn't saved.

Developers find these through player reports and through structural checks:
- **conservation and cache checks:** OpenTTD's desync level 2 re-checks caches;
- **"test runs must not modify state"** for cost previews;
- **simulation tools** such as Machinations and spreadsheet models.

### Cited Findings
- **Refund asymmetry, Arms Trade Tycoon: Tanks 1.1.9.1 (2025-10-14):** "The money exploit is fixed. You can no longer buy a building upgrade discounted and refund it for its price without discount." The same game's 1.1.3.0 (2024-02-12) fixed "Corrupted contracts with negative tanks quantity" (a negative-quantity state). — [GOGDB release notes for Arms Trade Tycoon: Tanks](https://www.gogdb.org/product/1613845936/releasenotes)
- **Financial loop, Prison Architect (2016 Steam thread).** Sell all shares, max out the bank loan, buy shares back cheaper, and repay the loan with the difference, giving infinite money. Players pointed to the official "Unlimited Funds" option, and whether it was patched is unclear. — [Steam discussion, via search snippet (page content not retrievable)](https://steamcommunity.com/app/233450/discussions/0/312265256995935209)
- **Duplication, Factorio (2016).** Quick-replacing a circuit-connected iron chest with a passive provider chest made the circuit network report duplicated item counts (a duplicated signal, not physical items). Rseding91: "Fixed for 0.13.5." — [Factorio forums #27847](https://forums.factorio.com/27847)
- **More recent Factorio duplication reports** (via search snippets): "Landfill duplicates when placed" (2.0.72, "fixed for 2.1"), and "Item duplication in tank" (2.0.76, modules appear both in the tank and in logistics trash; reported Mar 2026). — [Factorio forums: landfill](https://forums.factorio.com/132440); [tank](https://forums.factorio.com/viewtopic.php?p=690527)
- **Duplication left in on purpose, Satisfactory.** Items can be duplicated with a Factory Cart (and other ways). The developers reportedly said the belt duplication wouldn't be patched because "it only affects those that seek it out". — [Steam discussion via search snippet, unverified](https://steamcommunity.com/app/526870/discussions/0/601892242036200406)
- **OpenTTD desync docs, two bug classes that also cause single-player economy bugs:**
  - "Cache mismatch: The game logic depends on some cached values, which are not invalidated properly".
  - "Command test-runs should never alter gamestate, yet sometimes do". OpenTTD runs each command first as a test (cost estimate) and then for real.

  The desync debug level 2 re-checks vehicle caches; level 3 adds monthly saves; commands are logged and replayed from a start save. — [OpenTTD docs/desync.md](https://github.com/OpenTTD/OpenTTD/blob/master/docs/desync.md); levels via [mirror of desync.md, search snippet](https://git.blob42.xyz/Archives/OpenTTD-patches/src/branch/jgrpp/docs/desync.md)
- **Machinations.** A diagram language and simulator for game economies (resources, converters, gates) that runs mechanics before implementation, to study emergent balance and pacing. — [Dormans, "Simulating Mechanics to Study Emergence in Games", AIIDE 2011 (AAAI)](https://ojs.aaai.org/index.php/AIIDE/article/view/12477)
- **Spreadsheet models.** Pecorella's idle-math articles ship with spreadsheet models of growth and prestige balance. — [Math of Idle Games Part III (2016)](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii)
- **Vendor framing:** "The economy in a tycoon game is a feedback system, and feedback systems drift." — [bugnet.io tycoon article, **low quality / vendor**](https://bugnet.io/blog/bug-tracking-for-management-tycoon-games)

### Inferences
- **Arbitrage invariant test:** for every resource, the cheapest way to obtain one unit (buy price, or the inputs plus fees of making it) must cost more than the most you can sell it for, across all sale channels and taxes. A headless test over `data/*.json` can check this for every recipe chain (wheat → flour → bread) and fail the build on a profitable loop with no time cost.
- **Refund invariant:** refund(x) ≤ what was actually paid for x, so store the price paid, not the current list price. Demolish or cancel must never return more than was spent. Arms Trade Tycoon's discounted-upgrade refund broke exactly this.
- **Conservation / ledger invariant:** after any sequence of actions, `cash_now == cash_start + Σ income − Σ spending`, and goods are conserved (produced − consumed − sold = change in stock). Asserting this after every step of a random-action "monkey" simulation finds duplication and refund bugs. This is the single-player analogue of OpenTTD's cache checks and Factorio's CRC checks.
- **Preview vs execute:** the UI's "this will cost X" preview should call the same function as the real action in a dry-run mode that provably doesn't change state, which is the OpenTTD test-run rule.
- **Decide deliberately which exploits matter.** For a single-player game, Satisfactory and the Godot forum answerer both suggest that some exploits can be tolerated. Anything that breaks progression pacing or leaderboards needs fixing.

### Gaps
- No primary sources were found for economy exploits or testing practice in Sim Companies, Two Point Hospital, Rise of Industry, Transport Fever, or RimWorld's economy.
- No public OpenTTD "regression test" documentation was fetched; only desync tooling was confirmed.
- Prison Architect and Satisfactory details rest on search snippets.

---

## 5. Mobile/Android lifecycle: paused or killed in background, save on pause, orientation, low-end performance, aspect ratios

### Takeaway
The OS can kill a backgrounded Android or iOS app at any time with no further callback. So the game must save when it is paused or loses focus, and periodically. Saving only on quit is not enough. On iOS the app gets about 5 seconds after the pause notification. Developers test process death by backgrounding the app and killing it with `adb shell am kill`. Aspect ratios are handled with stretch mode `canvas_items` + aspect `expand`, anchored Controls and safe-area checks.

### Cited Findings
- **Godot docs on quitting.** Mobile apps "can quit at any time while it is suspended to the background". "On both Android and iOS, the app can be killed while suspended at any time by either the user or the OS". Use `NOTIFICATION_APPLICATION_PAUSED` "to perform any needed actions as the app is being suspended". The Android Back button quits by default (`application/config/quit_on_go_back`) and fires `NOTIFICATION_WM_GO_BACK_REQUEST`. — [Godot docs: Handling quit requests (4.7)](https://docs.godotengine.org/en/stable/tutorials/inputs/handling_quit_requests.html)
- **Godot MainLoop notifications** (each specific to the platforms named):
  - `NOTIFICATION_APPLICATION_PAUSED`/`RESUMED`: Android and iOS only. iOS gives "approximately 5 seconds to finish a task started by this signal. If you go over this allotment, iOS will kill the app instead of pausing it."
  - `FOCUS_IN`/`FOCUS_OUT`: desktop and mobile.
  - `NOTIFICATION_OS_MEMORY_WARNING`: iOS only.
  - `NOTIFICATION_CRASH`: desktop only, when the crash handler is enabled.

  — [Godot docs: MainLoop (4.7)](https://docs.godotengine.org/en/stable/classes/class_mainloop.html)
- **Project settings defaults (4.7):** `application/run/auto_accept_quit` = true; `quit_on_go_back` = true. — [Godot docs: ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html)
- **Android official docs:**
  - "The system kills processes when it needs to free up RAM".
  - "it kills the process the activity runs in", not individual activities.
  - "`onPause` execution is very brief and does not necessarily offer enough time to perform save operations. For this reason, **don't** use `onPause` to save application or user data".
  - Heavier shutdown work belongs in `onStop`.

  — [Android Developers: Activity lifecycle](https://developer.android.com/guide/components/activities/activity-lifecycle)
- **adb commands for testing process death:**
  - `am kill <package>`: "Kill all processes associated with package. This command kills only processes that are safe to kill and that will not impact the user experience" (so background the app with Home first).
  - `am force-stop <package>`: "Force-stop everything associated with package".

  — [Android Developers: adb](https://developer.android.com/tools/adb)
- **The common recipe:** press Home, then `adb shell am kill <package>`. Alternatively, enable the "Don't keep activities" developer option. — [dev.to "Hey Android, where's my process" (**lower quality**, but a standard technique)](https://dev.to/_nikhi1/hey-android-where-s-my-process-4f0e)
- **Open question on the Godot forum (Apr 2026).** Does `NOTIFICATION_APPLICATION_PAUSED` always fire before the user swipes the app away? Is there a grace period? Do async calls finish? No answer was visible in the fetched content. — [Godot Forum: manual user app termination on mobile (2026)](https://forum.godotengine.org/t/how-is-manual-user-app-termination-handled-on-mobile/137120)
- **Godot one-click deploy to Android** needs USB debugging, or wireless ADB (`adb pair <ip>:<port>`), and a Runnable export preset. "If you can't see the device in the list of devices when running the `adb devices` command in a terminal, it will not be visible by Godot either." — [Godot docs: One-click deploy](https://docs.godotengine.org/en/stable/tutorials/export/one-click_deploy.html)
- **Aspect ratios:**
  - Use stretch mode `canvas_items` or `viewport`, with aspect `expand` to "support multiple aspect ratios and make better use of tall smartphone displays".
  - Portrait base size 720×1280.
  - "Design your UI with small window sizes in mind", with anchors via the Layout menu.
  - Notches are handled with `DisplayServer.get_display_safe_area`.

  — [Godot docs: Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- **Desktop approximations of slow or odd devices:** `--frame-delay <ms>` ("Simulate high CPU load"), `--fixed-fps`, `--time-scale`, `--print-fps`, `--disable-vsync`. — [Godot docs: Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

### Inferences
- **When to save:**
  - on `NOTIFICATION_APPLICATION_PAUSED` (mobile)
  - on `NOTIFICATION_APPLICATION_FOCUS_OUT` (all platforms)
  - on `NOTIFICATION_WM_CLOSE_REQUEST` (desktop) and the Back-button request
  - on a periodic autosave timer
  - after important actions (purchase, build)

  Keep saves small and synchronous so they fit iOS's ~5 s and Android's short window. Android's own guidance warns that `onPause` is brief.
- **Manual test script per release:**
  1. Start a build job.
  2. Press Home.
  3. `adb shell am kill <package>`.
  4. Reopen and check that the job's timestamps and money survived.
  5. Repeat with the clock moved forward and backward between steps.
  6. Repeat with airplane mode.
  7. Rotate (if allowed) and resize.

  Then check the same flow on desktop with `--frame-delay`.
- Combine the temp-file + rename pattern from section 2 with pause-time saving, because a kill during a save is more likely on mobile.

### Gaps
- Not confirmed:
  - which Android callback (`onPause` vs `onStop`) Godot 4.7 maps to `NOTIFICATION_APPLICATION_PAUSED`;
  - whether swipe-to-close always delivers it.
- No Godot-specific source on low-end Android performance testing (for example Compatibility-renderer profiling on device) was fetched.
- Godot remote profiler use over USB/Wi-Fi was not detailed on the one-click deploy page.

---

## 6. Godot 4 tooling: GUT, gdUnit4, warnings, --headless/--check-only, debugger/profiler/remote, Sentry, bisect; recommendations for a small project

### Takeaway
For a small GDScript-only project, the essentials are:
- Headless test scripts run with `--headless -s` in CI, or GUT 9.x / gdUnit4 6.x when fixtures, doubles or reports are needed.
- Raising key GDScript warnings to Error.
- `--check-only` parse checks.
- Remembering that `assert()` vanishes in release builds.
- Optionally the official Sentry SDK for crash and error reports from players.

Several useful warnings (`unsafe_*`, `untyped_declaration`, `return_value_discarded`) are **off by default**.

### Cited Findings
- **GDScript warnings (4.7).** Configured under `debug/gdscript/warnings/*` (Advanced Settings). Each can be Ignore/Warn/Error, and Error makes the project refuse to run. Suppress locally with `@warning_ignore("name")` or `@warning_ignore_start`/`@warning_ignore_restore`. — [Godot docs: GDScript warning system (4.7)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/warning_system.html)
- **4.7 defaults** (0 = Ignore, 1 = Warn, 2 = Error), as summarised from the ProjectSettings page:

  | Default | Warnings |
  |---|---|
  | 0 (Ignore) | `untyped_declaration`, `inferred_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_cast`, `unsafe_call_argument`, `return_value_discarded`, `missing_await` |
  | 1 (Warn) | `integer_division`, `narrowing_conversion`, `unused_variable`, `shadowed_variable`, `standalone_expression`, `redundant_await`, `confusable_identifier`, `int_as_enum_without_cast`, `unreachable_code` |
  | 2 (Error) | `inference_on_variant`, `get_node_default_without_onready`, `onready_with_export` |

  `directory_rules` default `{"res://addons": 0}` silences addons. — [Godot docs: ProjectSettings (4.7)](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html) (values via a summarising fetch; spot-check in the editor)
- **assert():** "For performance reasons, the code inside assert() is only executed in debug builds or when running the project from the editor. Don't include code that has side effects in an assert() call." — [Godot docs: @GDScript (4.7)](https://docs.godotengine.org/en/stable/classes/class_@gdscript.html)
- **Command line:**
  - `--headless` ("Useful for servers and with `--script`")
  - `--check-only` ("Only parse for errors and quit (use with `--script`)", editor/extended builds only)
  - `-s/--script`, `--import`, `--quit-after`, `--log-file`
  - `--remote-debug tcp://host:port`
  - `--gpu-profile`, `--debug-stringnames`

  — [Godot docs: Command line tutorial (4.7)](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- **[Probe] 4.7.2:** a GDScript parse error under `--headless -s` printed `SCRIPT ERROR: Parse Error: ...` with the file and line, plus `Failed to load script ... with error "Parse error"`. `JSON.parse_string` on bad input prints `ERROR: Parse JSON failed...` with a GDScript backtrace, so parse problems show up in headless logs.
- **GUT:** GUT 9.x supports Godot 4.x (9.7.1 for Godot 4.7.x; 9.6.1 for 4.6.x); GUT 7.x supports Godot 3.5. Features: full and partial doubles, stubs, spies, parameterized tests, inner test classes, JUnit XML export, CLI for headless/CI, VSCode extension. — [GUT README (GitHub)](https://github.com/bitwes/Gut)
- **gdUnit4:** v6.2.x supports Godot 4.5–4.7.1. Features: GDScript and C#, fluent asserts, parameterized and fuzz tests, mocks, a scene runner that simulates mouse/keyboard/touch, flaky-test retry, orphan-node detection with stack traces, headless CLI, HTML + JUnit reports, and the `gdunit4-action` GitHub Action. — [gdUnit4 README (GitHub)](https://github.com/MikeSchulze/gdUnit4)
- **Developers' views (Godot forum, Jan 2026):**
  - One uses GUT "for unit tests of simple scripts and also UI".
  - Another prefers gdUnit4 (an assessment "a year and a half ago"), rarely uses it professionally because "Godot is really good about telling you when things aren't working", and mentions GDToolkit (lint/format).

  — [Godot Forum: Quick and dirty testing for GDScript functions (2026)](https://forum.godotengine.org/t/quick-and-dirty-testing-for-gdscript-functions/130742)
- **Comparison sites** say "GUT for pure GDScript, gdUnit4 for C#/mixed". — [claudeskills.info / dev.co, **low quality**](https://dev.co/testing/open-source/gdunit4)
- **Sentry (official Godot SDK, 2.3.0):**
  - Platforms: Windows/Linux (Native SDK), macOS 12+, iOS 15+, Android, Web.
  - Captures: runtime script and shader errors, GDScript stack traces with optional local/member variables, surrounding source, C# errors, breadcrumbs, structured logs, attachments, device info, and scene tree + screenshots (experimental).
  - Also: event throttling, Release Health, and `before_send` filtering.

  — [Sentry docs: Godot (2026)](https://docs.sentry.io/platforms/godot/)
  - Pricing and minimum Godot version are in the sibling notes `Error handling in game development/post_release_reporting.md`.
- **Bisecting regressions:** first reproduce with older or newer **official builds** to narrow the range, then use `git bisect` (build, run, reproduce, mark good/bad). — [Godot docs: Bisecting regressions (4.4 page)](https://docs.godotengine.org/en/4.4/contributing/workflow/bisecting_regressions.html)

### Inferences
- **Warnings worth raising for this game** (each tied to a bug class above):
  - `integer_division` to Error. Integer cents make `/` truncation a money bug; suppress it where truncation is intended.
  - `narrowing_conversion` to Error.
  - `return_value_discarded` to Warn. Catches ignored `Error` returns from `FileAccess`/`DirAccess.rename`/`JSON.parse`.
  - `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument` and `untyped_declaration` to Warn, at least in `scripts/sim/` (via `directory_rules`). Untyped Dictionary data from JSON is where float/int and typo bugs hide.
  - Note: the probe shows Variant→int truncation at runtime is not caught by any static warning.
- **CI with a GitHub Actions job:**
  1. Download Godot 4.7.
  2. Run `--headless --import`.
  3. Run `--headless -s tests/test_simulation.gd`, and fail on a non-zero exit code.
  4. Optionally grep the log for `SCRIPT ERROR`/`ERROR:`.

  The existing hand-rolled test script already fits this. GUT or gdUnit4 adds value mainly through JUnit reports, parameterized tests, and (gdUnit4) touch-input scene runners for UI.
- Never put game logic inside `assert()`. Tests that rely on `assert()` won't run in exported release builds, which is fine for tests but not for runtime checks. Runtime invariant checks should use explicit `if` + `push_error` and should not be in hot per-frame paths.

### Gaps
- No first-hand write-up by a well-known Godot developer comparing GUT and gdUnit4 for small projects was found. Comparison pages found were low quality.
- Android remote debugging and profiler specifics (deploy with remote debug, logcat filtering) were not fetched.
- GDToolkit (gdlint) capabilities were not verified.

---

## 7. Data-driven content bugs: typos in JSON keys silently ignored, missing references between data files, validating data files

### Takeaway
Godot's JSON parser is lax: it accepted a trailing comma in the probe. `Dictionary.get(key, default)` hides typos by returning the default. So bad content data usually fails silently. Mature data-driven games fail loudly at load instead:
- **RimWorld** logs "doesn't correspond to any field" for unknown XML tags and "Could not resolve cross-reference" for missing ids.
- **Factorio** refuses to start with "Key 'x' not found in property tree at ROOT…".

A small game gets the same protection from a validator script, run as a test, that checks allowed keys, required keys, types and cross-file references.

### Cited Findings
- **[Probe] 4.7.2: lax parsing and silent typos**
  - `{"production_time": 30}.get("prodution_time", 0)` returns `0` with no warning.
  - `JSON.new().parse('{"a": 1,}')` (trailing comma) returned `OK`, so the parser accepts input that strict JSON tools reject.
  - `JSON.parse_string("{bad json")` returns `null` and logs `Parse JSON failed. Error at line 0: Expected key`.
- **Godot JSON class:** `parse()` returns an `Error`, and `get_error_line()` "Returns 0 if the last call to parse() was successful, or the line number where the parse failed". Numbers are parsed with `String.to_float()`, "which is generally more lax than the JSON specification". — [Godot docs: JSON (4.7)](https://docs.godotengine.org/en/stable/classes/class_json.html)
- **RimWorld's loader** reports content errors at startup, for example:
  - "XML error: <costStaffCount>50</costStaffCount> doesn't correspond to any field in type ThingDef." (unknown key / typo)
  - "Could not resolve cross-reference: No SoundDef named Slurp found to give to ThingDef SomeName." (dangling reference)
  - "XML RimWorld.ThoughtDef defines the same field twice: stackLimit." (duplicate key)
  - "Could not find type named …" (bad class reference)

  The wiki notes errors cascade, so fix the first and reload. Capitalisation and stray whitespace (`compClass` vs `CompClass`, trailing spaces) are common causes. — [RimWorld Wiki: Modding Tutorials/Troubleshooting](https://rimworldwiki.com/wiki/Modding_Tutorials/Troubleshooting)
- **Factorio refuses to load bad prototypes.** Error format: "Error while loading [type] prototype '[name]' ([type]): … at ROOT.[path]". Example: "Key 'select' not found in property tree at ROOT.selection-tool.AbandonedRuins-claim", after 2.0 restructured selection-tool properties (Nov 2024). — [Factorio forums: Error updating mod for Factorio 2.0 (2024)](https://forums.factorio.com/viewtopic.php?p=638525)
- **Factorio staff discussed improving prototype error messages** in a dedicated forum thread. — [Factorio forums: Prototype error(s) improvements, via search snippet](https://forums.factorio.com/viewtopic.php?p=212380)

### Inferences
- **A `tests/check_data.gd` validator** (or a section of the existing test) should check:
  1. Every `data/*.json` parses (use `JSON.new().parse()` and report `get_error_line()`).
  2. Every object only has keys from an allowed list per type, which catches `prodution_time`.
  3. Required keys are present.
  4. Values have the right type and range (integral cents ≥ 0, durations > 0, ids are lower_snake_case).
  5. Every cross-reference resolves (recipe inputs and outputs exist in resources; a building's recipe exists; each resource has an icon `assets/ui/icons/<id>.svg`).
  6. No duplicate ids.

  This copies RimWorld's and Factorio's "fail at load with a path" behaviour. The project's existing test files were not inspected for this research.
- **In game code,** read required keys with `data["key"]` (missing key raises an error in debug) or a `GameData.require(obj, "key")` helper that `push_error`s with the file and id. Reserve `.get(key, default)` for genuinely optional keys.
- Because the parser accepts trailing commas and other lax input, a stricter external check (any standard JSON linter) on `data/` in CI keeps files portable to other tools and to a future server.

### Gaps
- No built-in JSON Schema validation exists in Godot 4.7, as far as the fetched docs show. Third-party Godot JSON-schema addons were not researched.
- No primary source was found on Paradox's script `error.log` workflow.
