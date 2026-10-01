# Project Plan: MMO Business Simulation Game

_Last updated: 2026-10-01 (review pass — see Section 15 for what changed)_

## 1. Pitch

An MMO business/economy simulation game inspired by **Sim Companies** (production chains, shared player-driven market), with visual polish closer to **Clash of Clans** (isometric buildings, building-level production animations — e.g. a distillery bubbling). No combat, no troops. Increasingly, it also leans toward **Tropico**-style town management — population, employment, and education systems sit alongside the pure production/trading loop. Includes a live player-driven stock market/exchange system (closest existing reference: **TyconX: Business Tycoon Game**).

Solo developer, works full time, building in off-hours, no prior coding/engine experience, planning to rely heavily on **Claude Code** rather than learning traditional programming from scratch.

**Target platforms (inferred from Sections 6 & 9 — confirm):** Android (primary test device), PC, Web. iOS is TBD — building for iOS requires a Mac and an Apple Developer account (paid yearly), so decide early whether it's in scope.

## 2. Build Order / Phases

Single-player first. Multiplayer/backend last. Do not attempt MMO infrastructure before there's a fun single-player loop.

| Phase | Goal | Notes |
|---|---|---|
| **Phase 1a** | Pipeline + core chain — Construction Office + Small House pre-built; player builds Wheat Farm → Flour Mill → Bakery; Retailer sell channel only; offline production; local save/load; Population visible but not yet functional | Confirm the pipeline works end-to-end (Godot + Git + Claude Code) and that the loop is fun before adding anything else |
| **Phase 1b** | Progression layer | XP/Leveling, tutorial + daily/weekly Quests, Profile Badges (low priority) |
| **Phase 2** | Expand single-player core loop | Chain 2 (Dairy/Pastry, interconnected via shared Flour), building upgrades + Construction Office leveling (the upgrade cap), more UI polish |
| **Phase 2/3** | Industrial category | Electricity + Employees + Power Plants (Coal, Solar) + Population becomes functional (Employment Matching) |
| **Phase 3+** | Education system | Elementary School → High School → College; advanced Industrial buildings require minimum graduate tier for Employees |
| **Phase 4** | Shared market / MMO backend | Real accounts, persistent live world, Market/Exchange + Contract sale channels, Rating/Reputation system, backend choice (Firebase vs. Nakama) finalized here, not before |

Rough realistic timeline (traditional coding): ~12–18 months part-time for single-player v1, ~2–2.5 years for full multiplayer version. Claude Code may compress the single-player build (to perhaps ~5–8 months), but treat that as optimistic: with no prior coding experience, time spent understanding, debugging, and directing architecture decisions is the real bottleneck, not typing code. Phase 4 is the riskiest estimate, since it effectively means rebuilding the game's rules on a server (see 3.1).

## 3. Tech Stack

**Phases 1–3 (single-player):**
- **Engine:** Godot Engine 4 (GDScript build, *not* the .NET/C# build) — chosen because the art style is 2D isometric sprite-based, not true rotatable 3D
- **Renderer:** **Compatibility** renderer — best fit for 2D, the most reliable on low-to-mid-range Android devices, and the only renderer Godot 4 supports for Web export
- **Save system:** JSON save file written to `user://` via Godot's `FileAccess` — no backend/database needed yet (see Section 8)
- **Version control:** Git + GitHub, set up from day one
- **AI coding assistant:** Claude Code (has a VS Code extension)
- **Editor:** Godot's built-in script editor is sufficient on its own; VS Code + Godot Tools extension optional
- **Engine choice reaffirmed (Unity considered, rejected):** Unity was evaluated as an alternative — it's also free (Personal plan, under $200K revenue, no runtime/install fees since the 2024 rollback) and deploys to mobile+PC at no cost. However, Godot fits a Claude-Code-driven workflow much better: GDScript is simpler for AI-generated code, and Godot's scenes are plain text files meant to be edited directly — which is exactly how Claude Code works (reading/editing files). Unity relies heavily on its visual Editor (GameObjects, Inspector wiring) for actual game assembly, which Claude Code cannot reach — a solo dev without coding experience would end up doing significant manual GUI work Claude Code can't help with. **Staying with Godot.**

**Phase 4 (shared market / MMO backend) — decision deliberately deferred:**
- **Firebase** — simpler starting choice for a solo dev (server logic in Cloud Functions: JavaScript/TypeScript/Python)
- **Nakama** — more powerful, self-hosted, better for real scale/cost control long-term (server logic in Go/TypeScript/Lua)
- Neither runs GDScript, so the game rules will need to be re-implemented server-side (or run as a headless Godot server). Section 3.1 is designed to make that port small.

### 3.1 Architecture Principles (apply from Phase 1a)

These are cheap now and very expensive to retrofit later. Include them in instructions to Claude Code.

1. **Data-driven content** — buildings, recipes, resources, prices, and timers live in data files (JSON or Godot Resource files), not hard-coded in scripts. Tuning numbers never requires code changes, and the same data can later be loaded by the server.
2. **Simulation separate from presentation** — all game rules (job completion, offline catch-up, selling, population growth) live in a small set of non-visual scripts (e.g. an `Economy`/`Simulation` autoload) that UI scenes only *call* and *display*. Buildings on screen never own the authoritative numbers. This is the part that gets ported to the server in Phase 4.
3. **One clock** — all code asks a single `TimeService` for "now" instead of reading the system clock directly. The dev menu's time-warp (Section 10) and the Phase 4 switch to server time then become one-line changes.
4. **Versioned saves** — every save carries a `save_version`; loading an older version runs a migration step instead of breaking. The save format will change in every phase.

## 4. Art Direction

- **Style:** 2D isometric sprite art styled to look 3D (illusion of 3D, not true rotatable 3D)
- **Camera:** Fixed-angle, Clash-of-Clans-style top-down village view — zoom/pan only, no rotation
- **Pipeline — not yet chosen:**
  1. **3D-model-to-sprite:** Blender + TexturePacker — most authentic to CoC's actual pipeline, steeper learning curve
  2. **Hand-drawn 2D isometric:** Aseprite/Krita + DragonBones + TexturePacker — faster start, flatter look unless skilled at shading
- **Current recommendation:** start with hand-drawn/placeholder art for Phase 1; Blender as a later polish-phase skill; commissioning an artist later also valid.
- **Audio** — not yet planned (see Open Questions); placeholder SFX for collect/sell/build go a long way for game feel even in Phase 1.

## 5. Game Mechanics

### 5.1 Core Production Loop
- Pattern: **Extractor** (no inputs) → **Processor A** (raw → intermediate) → **Processor B** (intermediate → final product)
- **Production model:** discrete timers (CoC-style)
- Each building has: recipe, timer duration, batch size, storage cap, job queue (up to 3–5 stacked)
- **Resource flow (proposed — confirm):**
  - Inputs are taken from the **Warehouse** at the moment a job is *queued* (not when it starts), so a queued job can never stall for missing inputs
  - Finished output sits in the **building's own storage** (the Storage Cap column in 5.4) until the player taps **Collect**, which moves it to the Warehouse
  - A job cannot complete if the building's output storage is full; the queue pauses until the player collects
  - The **Warehouse** has its own overall cap (number TBD)
- **Offline/idle production:** included from Phase 1a — elapsed real time simulates completed jobs on reopen, capped by the jobs already queued and by output storage capacity
- **Design tension (resolved 2026-10-01):** target offline window is ~1–2 hours. Extractors produce continuously until storage is full; processor batches/timers were scaled ×4 with queues of 8 (see 5.4). Implemented in `scripts/sim/simulation.gd`.
- **Land/grid:** bounded plot, expandable (spend currency) — details deferred
- **Building upgrades (Phase 2):** cost currency + time, improve batch size/timer/storage/recipes — capped by Construction Office level (see 5.8)

### 5.2 Economy / Market — Three Sale Channels
1. **Retailer (NPC)** — instant sell, set/slow-drifting price, likely demand-capped. **Only channel in Phases 1–3.**
2. **Market/Exchange (player-driven)** — real-time AMM pricing (same mechanic as the Currency/Stock Exchange prototypes). **Phase 4.**
3. **Contract (player-to-player)** — fixed-price posted offers. **Phase 4.**
- Any resource tier can be sold; price should still increase meaningfully per tier so processing is worth doing.

### 5.3 Progression
- **XP/Leveling** (Phase 1b) — unlocks *what's available*: new building types, recipes, plot size
- **Construction Office** (placed in Phase 1a at Level 1; leveling arrives with building upgrades in Phase 2) — separate axis, caps *how far* other buildings can be upgraded (Town-Hall-style ceiling); upgrading it costs currency + time like any building
- **Quests** (Phase 1b) — tutorial + ongoing daily/weekly
- **Profile Badges** (Phase 1b, low priority) — cosmetic milestones
- **Rating/Reputation** (Phase 4) — tied to Contract reliability, feeds a leaderboard
- **Chain 2** (Phase 2) — interconnected with Chain 1 via shared Flour

### 5.4 Concrete Resources, Buildings & Recipes

**Chain 1 — Food & Agriculture (Phase 1a):**

| Building | Type | Recipe | Output | Timer | Batch | Storage Cap |
|---|---|---|---|---|---|---|
| Wheat Farm | Extractor (continuous, no queue) | (none) | Wheat | 60s | 10 Wheat | 900 (90 min) |
| Flour Mill | Processor A (queue 8 = 48 min) | 40 Wheat → | 32 Flour | 6 min | 32 Flour | 256 |
| Bakery | Processor B (queue 8 = 80 min) | 32 Flour → | 24 Bread (Final) | 10 min | 24 Bread | 192 |

_Rescaled 2026-10-01 for the ~1–2h offline window: batches ×4 and timers ×4, so the per-minute rates below are unchanged. Live values are in `data/buildings.json`._

**Balance check (per building, running continuously):**

| Building | Consumes | Produces |
|---|---|---|
| Wheat Farm | — | 10 Wheat/min |
| Flour Mill | 6.7 Wheat/min | 5.3 Flour/min |
| Bakery | 3.2 Flour/min | 2.4 Bread/min |

- One Wheat Farm can feed ~1.5 Flour Mills; one Flour Mill can feed ~1.7 Bakeries. With one of each, the Farm and Mill will pile up surplus — which is fine (it gives the player something to sell), but intentional.
- Overall conversion: **10 Wheat → 8 Flour → 6 Bread**, i.e. 1 Bread ≈ 1.67 Wheat. For processing to be worth it, the Retailer price of Bread must be comfortably above 1.67× the Wheat price *plus* a margin for the extra build cost and waiting time (same logic for Flour vs. Wheat: 1 Flour = 1.25 Wheat).

**Chain 2 — Dairy/Pastry (Phase 2, interconnected via shared Flour):**

| Building | Type | Recipe | Output |
|---|---|---|---|
| Dairy Farm | Extractor | (none) | Milk |
| Creamery | Processor | Milk → | Butter |
| Pastry Shop | Processor | Butter + Flour (from Chain 1) → | Pastries (Final) |

### 5.5 Industrial Category — Electricity & Employees (Phase 2/3)

- **Electricity** — utility resource, not tradeable/sellable; feeds a shared grid pool; consumed per job start by Industrial buildings; self-sufficient (players must build their own supply, can't buy their way out of a shortage)
- **Power Plants:**
  - **Coal Power Plant** — consumes Coal (from a Coal Mine extractor), high output, low build cost, ongoing fuel dependency
  - **Solar Farm** — no fuel input, high build cost, large plot footprint, low-medium output scaling with count built
  - (Gas Plant, Wind Turbine, Hydro Dam identified as later additions, not yet committed)
- **Employees** — each building requires N employees to operate; hired (small recruiting cost) then draw a recurring **wage** per time tick — the game's first ongoing upkeep/cash-flow pressure
- **Employee education-tier requirement varies by business/industry:** basic Industrial buildings accept Uneducated workers; other businesses require High School Graduates or College Graduates depending on tier (exact per-building requirements TBD when those buildings are designed)
- **Offline rule needed:** wages and electricity must also be settled in the one-time offline catch-up calculation — including what happens if cash runs out while the player is away (see Open Questions)
- Deeper layer (happiness/skill training) explicitly deferred as a future idea, not committed scope

### 5.6 Population & Residential (Phase 1a, functional from Phase 2/3)

- **Small House** (Residential) — +10 population capacity, one-time build cost, no recipe. **Included in Phase 1a's starting kit.**
- **Population** grows automatically toward capacity (e.g. +1/10s), shown on the persistent HUD; offline growth is calculated from `last_saved_at` like production
- In **Phase 1**, Population is purely a visible/growing number with no mechanical effect yet
- In **Phase 2/3**, once Employees exist, **Employment Matching** activates: Available = Population − Employed. Understaffed buildings run at reduced capacity/output rather than failing to hire outright.

### 5.7 Education System (Phase 3+)

- **Elementary School → High School → College**, unlocked progressively at higher player levels
- Each works exactly like a Processor: input is Population (or the prior tier's Graduates), timer, batch size, storage cap, queue
- Output is a distinct resource tier: Elementary Graduates → High School Graduates → College Graduates
- Advanced Industrial buildings require a minimum graduate tier for their Employees, not just headcount — segments the workforce by education level, incentivizing players to build Schools ahead of need
- **Needs clarifying:** whether Graduates remain part of Population (and of the Employment Matching formula) or are removed from it when they enroll — see Open Questions

### 5.8 Construction Office & Starting Kit (Phase 1a)

- **Construction Office** — mandatory anchor building (Town-Hall equivalent); required to exist before other construction; has its own level that caps other buildings' max upgrade level, separate from the XP/Level system (leveling active from Phase 2)
- **Starting kit (Phase 1a):**
  - Construction Office — pre-built, Level 1, already placed
  - Small House (Residential) — pre-built, already placed → Population growth begins immediately
  - Starting cash — placeholder amount (e.g. ₱500–1000, tunable later; soft/premium currency names TBD)
  - Wheat Farm — **not** pre-built; building it is the player's first tutorial action

## 6. UI/UX Screens

**Phase 1 screens:**
- **Village View** — main isometric view, tap/click a building to interact, pan/zoom camera
- **Build Menu + Placement Mode** — list of buildable buildings with cost, then place on the grid (needed in Phase 1a: the player's first action is building a Wheat Farm)
- **Building Panel** — current recipe, timer progress, job queue, collect button, upgrade button (upgrade button from Phase 2)
- **Recipe Select** — sub-panel of Building Panel (once 2+ recipes unlocked)
- **Inventory/Warehouse** — all resources held, quantities, storage caps
- **Retailer/Sell Screen** — sellable resources, current NPC price, quantity selector, sell button
- **Offline Summary** — "While you were away…" popup listing what was produced (and, from Phase 2/3, wages paid)
- **Settings** — sound/music volume, save reset, language (if localized)
- **Quest Log** (Phase 1b) — active tutorial + daily/weekly quests, progress, claim-reward button
- **Profile** (Phase 1b) — XP/level, badges earned (Phase 4 adds rating)
- **Persistent HUD** — currency balance, XP bar, active quest progress (compact), Population (current/capacity), notification icons

**Phase 4 additions:**
- **Market/Exchange** — live AMM-style buy/sell interface
- **Contract Board** — open player-posted offers + post-new-contract form
- **Leaderboard** — ranked by net worth/rating

**Architecture note:** Building Panel and Inventory/Sell screens should be built as overlay panels (Control nodes, responsive anchors) — a bottom-sheet on mobile, a side panel on PC/web, from one shared implementation.

## 7. Monetization

Premium currency + soft currency hybrid, explicitly **non-pay-to-win**.

**Premium currency CAN buy:**
- Construction speed-up, building upgrade speed-up
- Cosmetics (skins, decorations, profile customization)
- Plot/grid expansion (if currency-gated — to confirm later; **caution:** more land means more production buildings, so selling land for premium currency is closer to pay-to-win than the other items here — consider soft-currency-only expansion, or premium only for cosmetic/decorative plots)

**Premium currency CANNOT buy (hard rule, no exceptions):**
- Production job timers (Farm/Mill/Bakery batch completion) — always real-time
- Retail sell price or speed
- Any direct resource/currency grant

Note: upgrade speed-ups aren't perfectly neutral (they let paying players reach a stronger engine sooner), but this is an accepted trade-off in respected non-P2W builder/sim games — the key protection is that production timers themselves are never purchasable.

## 8. Data / Save Architecture

**Phase 1 (local save):** one JSON file per player profile, written to `user://` with `FileAccess`. JSON is preferred over saving Godot Resource files, because loading Resource files from outside the game can execute embedded code (a risk once saves are shared or edited), and JSON maps directly onto what a Phase 4 backend will store.

```
PlayerSave
├── save_version: 1
├── last_saved_at: <unix timestamp>
├── profile: { player_id, name, xp, level, currency, premium_currency }
├── plot: { grid_size }
├── buildings: [
│     { id, type, level, position,
│       construction: { finishes_at } | null,
│       storage: {resource: qty},
│       queue: [ {recipe_id, started_at, finishes_at} ] }
│   ]
├── inventory: { resource: qty }          # the Warehouse
├── population: { current, capacity }
├── retailer: { resource: current_price } # only if prices drift
├── quests: { active: [...], completed: [...] }
└── badges: [ badge_id, ... ]
```

- Building position lives on the building entry itself (the earlier draft kept a separate `plot.building_slots` list that duplicated id/type/level — two copies of the same data can drift out of sync)
- Buildings store **timestamps** (`started_at`/`finishes_at`), not countdowns, so offline production can be calculated from elapsed real time
- In single-player, timestamps come from the device clock, so a player can fast-forward by changing it. Acceptable for Phase 1–3 (it only affects their own game); just make sure a clock set *backwards* never causes negative progress or crashes
- Structure intentionally close to what a Phase 4 cloud backend would need

**Phase 4 additions:**
- Market/Exchange and Contract data are shared/global state — not part of an individual player's save
- Server must own all timers once state is server-side (never trust a client-reported completion time)

## 9. Performance & Security

### 9.1 Mobile Performance
- **Texture atlasing** — pack building/tile sprites into shared texture sheets (via TexturePacker) to minimize draw calls
- **Limit active per-frame logic** — only actively-producing buildings need per-frame updates; idle/finished ones don't
- **Offline/idle catch-up must be a one-time math calculation, not a simulated tick-by-tick replay** — calculate completed jobs via elapsed time ÷ timer duration, never simulate every second that passed (would visibly freeze the game on reopen after a long absence)
- **Test on a real low-to-mid-range Android device early**, not just in-editor or on PC — catch problems in Phase 1 (3-4 buildings) rather than Phase 3 (full village)

### 9.2 Security — Two Separate Concerns
**App cloning/piracy** (someone repackages/redistributes the built app):
- Godot supports encrypting exported game files, but this requires compiling custom export templates with your own key — a real setup hurdle for a non-coder. It raises the difficulty of extracting scripts/assets without making it impossible. Low priority while the game is single-player; revisit before public launch.
- Google Play (Play Integrity API) and Apple's own app signing provide additional baseline protection against casual repackaging

**Economy duplication/cheating** (editing save data, faking currency, exploiting trades):
- Core defense (already established in Section 8): **server must be the sole authority on currency, resources, and timers once Phase 4's backend exists** — client only displays what the server confirms, never trusted to report its own state
- This is the standard, correct way MMO economies protect against save-editing and duplication exploits — treat "server-authoritative state" as a first-class item in the Phase 4 anti-abuse plan, not a separate afterthought

## 10. Debug / Developer Mode

A hidden dev menu (key combo on PC, secret tap sequence on mobile) for testing that **never ships to real players**. Godot does not strip debug code automatically, so this takes two deliberate steps:
1. Put the dev menu in its own scene/folder and only load it when `OS.is_debug_build()` is true
2. Exclude that folder from release export presets (Export → Resources → exclude filter), so the code isn't even in the shipped files

**Planned commands:**

| Category | Commands |
|---|---|
| Economy | Add currency/premium currency, spawn any resource in any quantity, reset wallet |
| Time | Instantly finish current building job, warp time forward by N minutes/hours via the `TimeService` (primary tool for testing offline-production logic without waiting) |
| Progression | Set XP/level directly, unlock all buildings/recipes, max Construction Office level |
| Population/Employees | Instantly fill population to capacity, force hire/fire, bypass education-tier requirements |
| Meta | Reset save, "god mode" (free instant builds), skip tutorial |

**Phase 4 rule:** debug commands (e.g. "add currency") must route through the same server-side logic as normal play, gated by a developer-account flag checked server-side — never a client-side shortcut that fakes a value locally, which would undermine the server-authoritative economy protection above.

## 11. Open Questions

**Design decisions that affect Phase 1a:**
- [x] Do Extractors (Wheat Farm) run continuously until storage is full (CoC-collector style) or only through a job queue like Processors? → **Run continuously until storage is full** (decided 2026-10-01)
- [x] Target offline window → **~1–2 hours** (decided 2026-10-01); Phase 1a numbers in 5.4 rescaled to match
- [x] Confirm the proposed resource-flow rules in 5.1 → **Confirmed as written** (decided 2026-10-01); Warehouse cap placeholder 2000 total units
- [x] Construction timers for new buildings → **Instant in Phase 1a** (decided 2026-10-01); timers/builder limits may return in a later phase
- [ ] Soft and premium currency names (₱ is a placeholder)

**Later phases:**
- [ ] Target platforms — is iOS in scope?
- [ ] Art pipeline final choice (Blender-to-sprite vs. hand-drawn vs. commissioned artist)
- [ ] Audio/music plan (sources, licensing, or commissioned)
- [ ] Localization — which languages, and from which phase
- [ ] Firebase vs. Nakama — not needed until Phase 4
- [ ] Whether Market/Exchange stock-style companies get flavored to match in-game industries, or stay generic
- [ ] Exact Retailer pricing curve/demand-cap numbers per resource tier (must respect the 5.4 conversion ratios)
- [ ] Land/grid size and expansion cost curve — and whether premium currency may buy land (see Section 7 caution)
- [ ] Quest content — specific tutorial quest list and daily/weekly quest pool
- [ ] Onboarding/tutorial flow (concrete first-5-minutes script)
- [ ] Economy safety / anti-abuse plan for Phase 4 player-driven market
- [ ] Social/community features (chat, friends, trade alliances)
- [ ] Legal basics (ToS, Privacy Policy) — needed once real accounts exist (Phase 4); also check local rules on selling premium currency in each launch country
- [ ] Marketing/launch plan
- [ ] Power Plant recipe numbers (timer, batch, storage cap) for Coal Power Plant and Solar Farm
- [ ] Employee hiring cost, wage amount, and headcount-per-building numbers
- [ ] What happens when the player can't pay wages (especially while offline) — buildings pause? employees quit? debt?
- [ ] School timer/batch/storage-cap numbers for Elementary/High School/College
- [ ] Do Graduates stay in Population / count toward Employment Matching, or are they a separate pool?
- [ ] Specific per-building education-tier requirements for Employees
- [ ] Construction Office upgrade cost curve and exact level-cap relationship to other buildings
- [ ] Population growth rate tuning and House capacity numbers beyond the first Small House

## 12. Setup Checklist (from-scratch walkthrough)

- [ ] Install Godot Engine 4 (godotengine.org/download — standard GDScript build, not .NET)
- [ ] Create GitHub account + install Git (git-scm.com)
- [ ] Create new empty GitHub repo (e.g. `company-sim-game`)
- [ ] Create Godot project locally (New Project, **Compatibility** renderer — best for 2D, low-end Android, and required for Web export)
- [ ] Connect project to Git (`git init`, remote add origin, Godot `.gitignore` — ignores the `.godot/` cache folder — first commit + push)
- [ ] (Later, once real art arrives) enable Git LFS for large image/audio files to keep the repo fast
- [ ] Install Claude Code, point it at the project folder; add a `CLAUDE.md` in the project root summarizing Section 3.1's principles so every session follows them
- [ ] Build/run a first placeholder scene in Godot to confirm the pipeline works
- [ ] Export a test build to a real Android device (confirms the export pipeline early, per 9.1)

## 13. Reference / Comparable Games

- **Sim Companies** — production chains + shared player-driven market
- **TyconX: Business Tycoon Game** — production chains + live stock market/IPOs/dividends
- **Rise of Industry**, **Production Line** — production-chain sim references
- **Factory Default**, **Compile** — isometric factory builders (Compile has combat, explicitly avoided here)
- **Rent Please! Landlord Sim** — visual/animation reference only (side-view cutaway, explicitly not this project's camera style)
- **Tropico** — reference for population/employment/education systems and non-combat town management feel

## 14. Prototypes Built So Far

- **Currency Exchange Sandbox ("Kambyo")** — AMM-based (constant-product, 0.3% fee) currency trading sandbox
- **Stock Exchange Sandbox ("Ticker")** — same AMM pricing model applied to fictional company stocks, tracks per-player net worth

Both are functional, self-contained HTML/JS artifacts used to validate the trading-mechanic math and UX before porting logic into Godot.

## 15. Revision Log

**2026-10-01 (Phase 1a step 2 — game rules):**
- Resolved four Phase 1a Open Questions (extractor behavior, offline window, resource flow, construction timers)
- Rescaled Chain 1 batches/timers/storage for the ~1–2h offline window (rates unchanged)
- Save schema detail: population stores `current` + `growth_anchor` (capacity is calculated from buildings, not stored, so it can't drift); buildings store `job_started_at` + `blocked` instead of per-job timestamps (a job paused for full storage would otherwise invalidate every later timestamp)

**2026-10-01 review:**
- Split Phase 1 into 1a (pipeline + core chain) and 1b (progression) to keep the first milestone small
- Resolved a phase conflict: building upgrades and Construction Office leveling were listed as both Phase 1 and Phase 2 — now Phase 2 (matches the phase table); the Construction Office itself is still placed in Phase 1a
- Fixed cross-reference in 5.1 (Construction Office is 5.8, not 5.5)
- Added target platforms, Architecture Principles (3.1), proposed resource-flow rules, balance check with production rates and conversion ratios, and the offline-window design tension
- Renderer changed from Mobile to Compatibility (Web export requires it; better on low-end Android)
- Save schema: added `save_version`, `last_saved_at`, Warehouse `inventory`, `population`, construction state; merged the duplicated building-slot list; switched to JSON
- Corrected debug-mode stripping (Godot doesn't do it automatically) and noted that export encryption needs custom export templates
- Added missing screens: Build Menu/Placement, Offline Summary, Settings
- Flagged premium-currency land expansion as a pay-to-win risk
- Added new Open Questions (extractor behavior, offline window, construction timers, wages when broke, graduates vs. population, iOS, audio, localization)
