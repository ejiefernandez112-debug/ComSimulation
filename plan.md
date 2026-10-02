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
- **Target look:** `ChatGPT Image Sep 30, 2026, 07_51_57 PM.png` (repo root) — lush island, rock cliffs, beaches, mountain, dense trees. A mood reference only, never game art: AI images can't keep one camera angle, light direction and scale across many pieces, so placed side by side they look like a collage.
- **Pipeline — decided 2026-10-01: 3D models "photographed" into 2D sprites** (CoC's approach)
  - A small Godot "photo studio" tool scene (built and run by Claude Code, never shipped) places each 3D model under the game's exact camera angle and the same sun, and saves a PNG with its shadow. The game itself stays 2D — fast on low-end Android and Web.
  - ~~Start with free CC0 low-poly model libraries (Kenney, Quaternius, KayKit); Blender is not required.~~ **Changed 2026-10-01: we make our own models in Blender** (5.2, installed), because free kits have no real farm/mill/bakery and don't match each other. Each model is a Python script in `art/blender/models/` that Blender runs in the background (no Blender skills needed), all sharing one style kit (`art/blender/kit.py`: palette, 1 tile = 5 units, rounded edges). Style: "a bit more detailed, closer to Clash of Clans": shingled roofs, trim, props, not just blocks. The studio still takes the final photo, so lighting stays identical to the game. Paid or commissioned models can still replace any of them later. How-to: `art/README.md`
  - Rejected: AI-generated images as game art (see above); a truly 3D game (costs phone battery/performance, and the Compatibility renderer's lighting is simpler than a pre-rendered picture).
- **Look rules (every asset follows these):**
  - One sun, from the upper left of the screen; shadows fall to the right (`Iso.SHADOW` in code)
  - The buildable plot is flat; height (cliffs, mountain) lives in the scenery around it
  - Tall scenery goes at the back (top of the screen) so it never hides buildings
  - Fixed scenery becomes one baked background picture; anything the player can change (buildings, clearable trees, roads) is a separate sprite on top
  - Things lower on screen are drawn in front of things higher up (y-sorting)
- **Visual roadmap:**
  1. ✅ **Stage setup** (code only, placeholder art; done 2026-10-01) — animated water with depth colour and shoreline foam, smooth coast, rock cliffs and sandy beaches, grid lines only in Placement Mode, soft ground shadows, y-sorted objects, placeholder trees. Lives in `scenes/village/` (`island.gdshader` paints the island; `island_map.gd` decides where land, beaches and trees are)
  2. **Photo studio + first real art** — Construction Office, Small House, Wheat Farm, Flour Mill, Bakery, trees, rocks. Buildings grow to 2×2/3×3 footprints (a game-rule change, with tests).
	 - ✅ Studio built (`tools/sprite_studio.gd`, 2026-10-01): two photos per model (the building, then its shadow alone) combined into one transparent PNG with a baked shadow; also makes a contact sheet of a whole kit to choose from. All 5 buildings use **temporary** models from Kenney City Kit (Commercial) — a city kit, so the farm and mill are stand-in office blocks. **Expect these sprites to be swapped:** changing art = edit `tools/sprite_studio.json` and re-run the studio; no game code changes
	 - Raw model kits live in `Sprites kit/` but are **not committed** (big, re-downloadable, likely to change; sources noted in `tools/sprite_studio.json`); only the small generated sprites are. So Git LFS isn't needed yet — turn it on before the step-3 island picture (several MB)
	 - ✅ **Wheat Farm** made in Blender (2026-10-01): red gambrel barn with cupola, silo, fenced wheat field with scarecrow, yard with hay bales, sacks and a cart. Designed for **2×2**, but shown on 1 tile until footprints grow (the studio's `tiles` setting in `tools/sprite_studio.json` goes 1 → 2 then)
	 - Still to do: Flour Mill, Bakery, Small House, Construction Office in Blender (same style kit); trees and rocks as sprites; bigger footprints (decided: 2×2)
  3. **The island itself** — 3D terrain built in the studio from the same coastline seed (flat plot in the middle, cliffs and beaches around it, mountain and forest at the back), baked once into a background picture cut into chunks for phones
  4. **Life** — spinning mill sails, bakery smoke, swaying trees, drifting cloud shadows, birds, boats
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
  - The **Warehouse** has its own overall cap: since 2026-10-02 it is the room of all Warehouse buildings together (§5.10)
- **Offline/idle production:** included from Phase 1a — elapsed real time simulates completed jobs on reopen, capped by the jobs already queued and by output storage capacity
- **Design tension (resolved 2026-10-01):** target offline window is ~1–2 hours. Extractors produce continuously until storage is full; processor batches/timers were scaled ×4 with queues of 8 (see 5.4). Implemented in `scripts/sim/simulation.gd`.
- **Land/grid:** bounded plot, expandable (spend currency) — details deferred
- **Building upgrades (Phase 2):** cost **construction materials + laborers** from the Construction Office (no money fee; decided 2026-10-02, §5.15) + time, improve batch size/timer/storage/recipes — capped by Construction Office level (see 5.8)

### 5.2 Economy / Market — Three Sale Channels
1. **Retailer (NPC)** — instant sell, set/slow-drifting price, likely demand-capped. **Only channel in Phases 1–3** (apart from Dock export contracts once the Dock unlocks, §5.11).
2. **Market/Exchange (player-driven)** — where players buy and sell goods **fast**, with no partner needed; real-time AMM pricing (same mechanic as the Currency/Stock Exchange prototypes), **3% fee per trade** paid by the seller (§5.9). **Phase 4.**
3. **Contract (player-to-player)** — fixed-price posted offers, **no market fee**; goods go through the **Dock** (§5.11). With in-game buyers once the Dock unlocks; with other players from **Phase 4.**
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

> **Electricity design planned 2026-10-02, not built yet.** All numbers are PLACEHOLDERS (they will go in `data/*.json`). Scaled to the Phase 1a economy (buildings $2,000–$8,000, wages $15/worker/hour), not to Tropico's.

#### 5.5.1 How power works: a grid, not a stockpile
- **Electricity** is a utility, not a warehouse item: it can't be stored, carried or sold at the Retailer. It is a **flow**: plants **produce** a steady number of MW, working buildings **use** a steady number of MW
- **Supply order:** your own plants first, then the public grid (5.5.3) fills the gap, up to your connection size
- **Short of power:** if plants + grid connection can't cover demand, **every** powered building slows down by the same share (30 MW wanted, 24 MW available → all run at 80%)
- **One speed rule:** `speed = worker share × power share`. Electricity reuses the existing workers math (5.6), so offline catch-up, the speed display and the halt rule keep working
- **Power is only used while a building is producing**, the same rule as wages (decided 2026-10-02): halted buildings (storage full) and idle ones (no jobs queued) use **no power**. Use it in code through `Simulation.is_producing`, so wages and power can never disagree
- **Power use per building:** Flour Mill **3 MW**, Bakery **4 MW**, Wheat Farm **0 MW** (decided 2026-10-02: farms don't need electricity). The balanced 2 farm / 3 mill / 5 bakery chain needs **29 MW**
- Changes from the earlier plan: power was "consumed per job start" and players had to be "self-sufficient, can't buy their way out". Both replaced by the flow model and the public grid

#### 5.5.2 Power plants
Each plant has a role; none is simply "the best":

| Plant | When | Build cost | Workers | Fuel | Output | Strength | Weakness |
|---|---|---|---|---|---|---|---|
| **Thermal (Coal) Power Plant** | First plant (Phase 2/3) | $15,000 | 6 low-skilled | ~10 coal/min | **40 MW** at full staff | Cheapest to build per MW (~$375/MW), steady | Coal + wages forever; pollution later |
| **Wind Turbine** | Early–mid | $6,000 | 0–1 | none | ~5 MW average (0–10 MW) | Free to run, small footprint | Output rises and falls with the wind |
| **Solar Farm** | Mid | $10,000 | 0 | none | 8 MW in daylight, 0 at night | Free to run | Daytime only, big footprint, ~$2,500 per average MW |
| **Nuclear Plant** | Late (after schools) | ~$120,000 | Professionals (college grads) | uranium (slow) | ~300 MW | Cheapest per MW at scale | Very expensive, needs educated workers |
| *Hydro Dam (idea)* | Later | TBD | TBD | none | TBD | The island already has a **waterfall** | Only one spot to build it |

**Thermal Power Plant details:**
- **Output scales with workers** like every other building: the Low/Medium/High staffing choice is its "budget" (fewer workers = less power and lower wages)
- **Coal** comes from a new **Coal Mine** (an extractor like the Wheat Farm, ~$3,000, 8 low-skilled workers, ~12 coal/min). The plant has its own coal storage (~600 coal = 1 hour) that the player fills from the warehouse
- **No coal → 0 MW.** The moment coal runs out is predictable, so it works offline like "storage full"
- **Running cost:** 6 × $15 wages + coal ≈ **$17 per MWh**, cheaper than the grid's ~$25, so building one pays off
- **Upgrade (later):** oil-fuelled furnace (burns oil instead of coal)
- Workers are low-skilled for now, because high-skilled workers need schools (5.7). Nuclear is the plant that needs educated workers

#### 5.5.3 Public grid
**Automatic, no "Buy electricity" button.** It works like a real home connection: the grid covers whatever your plants don't, and you pay for what you use, settled the same way as wages (including offline, and into debt if cash runs out). A buy button with pre-bought blocks was rejected: it means micromanaging, and the town would stop overnight while the player is offline.

**Connection size** (the player's one choice, upgraded like a building):

| Connection | Max draw from the grid | One-time cost |
|---|---|---|
| Small | 10 MW | Free (comes with the Construction Office) |
| Medium | 25 MW | $2,000 |
| Large | 60 MW | $8,000 |

The grid is a **safety net with a ceiling**: a big company still has to build its own plants.

**Price per MWh** = base × time of day × market mood × usage tier:
- **Base:** ~**$25/MWh**
- **Time of day:** daytime ×1.2 (peak), night ×0.8 (cheap), following the game day (5.5.4)
- **Market mood:** a slow drift of ±20% over days from a fixed pattern ("electricity prices up 12% today"). It also nudges Retailer prices (the dynamic-pricing idea; see Section 11)
- **Usage tier:** like the sales tax brackets, heavy users pay more for the extra part (e.g. the first 20 MW at the normal price, anything above +25%). Small companies aren't punished; big ones are pushed to build plants
- **Phase 4 (online):** the price also rises with **everyone's** combined grid use. It plugs into the same formula
- **Later:** sell surplus power **back** to the grid at a lower price (~$12/MWh)

**Scale check:** the 29 MW balanced chain fully on the grid ≈ **$725/hour**, against ~$5,760/hour of bread sales, so power is **~13% of sales**. Noticeable, not crushing.

#### 5.5.4 Day and night
- **One game day = 12 real hours:** ~**6 hours daylight + 6 hours night**, so two game days per real day. A player who always plays at the same real time sees both day and night over the week
- **Solar** follows it: steps up in the morning, peaks at midday, steps down in the evening, 0 at night
- **The grid price** is cheaper at night
- **Visual (optional, separate art task):** the island darkens at night and building lights come on

#### 5.5.5 Offline catch-up rule
Everything stays **one calculation**, never a replay. Anything that changes power is either a **predictable moment** or **changes in steps** from a fixed pattern (a formula of time, not dice rolls):
- Wind gets a new strength every ~10 minutes; the sun moves in hourly steps; the grid price changes once per game hour and at day/night
- Coal running out and storage filling are predictable moments, like construction finishing today
- So 8 hours offline is a few hundred quick steps, not millions, and the result is the same whether the player was online or not

#### 5.5.6 Build order
1. Grid model + public grid (Small connection) + power use on the Mill and Bakery
2. Coal Mine + Thermal Power Plant; connection upgrades
3. Changing grid price (the start of dynamic pricing) + day/night cycle
4. Wind Turbine, then Solar Farm
5. Nuclear Plant, after schools (5.7) provide educated workers

#### 5.5.7 Employees
- **Employees** — each building requires N employees to operate; hired (small recruiting cost) then draw a recurring **wage** per time tick — the game's first ongoing upkeep/cash-flow pressure
- **Employee education-tier requirement varies by business/industry:** basic Industrial buildings accept Uneducated workers; other businesses require High School Graduates or College Graduates depending on tier (exact per-building requirements TBD when those buildings are designed)
- **Offline rule needed:** wages and electricity must also be settled in the one-time offline catch-up calculation — including what happens if cash runs out while the player is away (see Open Questions)
- Deeper layer (happiness/skill training) explicitly deferred as a future idea, not committed scope

### 5.6 Population & Residential (Phase 1a, functional from Phase 2/3)

- **Small House** (Residential) — +10 population capacity, one-time build cost, no recipe. **Included in Phase 1a's starting kit.**
- **Population** grows automatically toward capacity (e.g. +1/10s), shown on the persistent HUD; offline growth is calculated from `last_saved_at` like production
- **Workers & wages (built 2026-10-01, pulled forward from Phase 2/3):** each production building can employ up to `max_workers` (8 at level 1; Wheat Farm, Flour Mill, Bakery). The player picks its **Staffing** in the building window: **Low 4 / Medium 6 / High 8** (`staffing_levels` in `game_config.json`, as shares of `max_workers`; new buildings start at High). **Speed = workers actually working ÷ max_workers** (6 of 8 = 75%). *(The even-share rule, "10 people for 14 jobs = 71% each", was replaced on 2026-10-02 by whole, tied workers hired by bonus: see **Hiring & wage bonuses** below.)* **Worker types:** only **Low-skilled** can be hired now; High-skilled (high school graduates, e.g. engineers) and Professional (college graduates) are in the data with their wages but switched off until schools exist (§5.7). **Wages** (fixed PLACEHOLDERS, to move to the backend later): Low-skilled 15 / High-skilled 30 / Professional 60 per worker per hour, paid for every worker actually working, also while the game is closed. **Wages are only paid while a building is producing** (decided 2026-10-02): a halted building (storage full) or an idle Mill/Bakery (no jobs queued) pays nothing; its workers stay tied to it, unpaid, and are back the moment it restarts (changed 2026-10-02, see below; before, they were freed). **Cash may go below 0 (debt)**: sales pay it back; nothing can be built while in debt; the HUD shows debt in red. Prices were raised (Flour 4, Bread 8) so each step still pays after wages. The Small House is buildable so players can grow the workforce. Offline catch-up stays one calculation: the time away is split only at the moments staffing changes (a person moves in, a building finishes, a building fills up or runs out of jobs) and each piece is worked out in one go; part-coins of wages carry over so many short settles cost the same as one long one
- **Hiring & wage bonuses (decided 2026-10-02):**
  - **Whole workers only.** Each building has a real headcount (`hired`, stored in the save), never a share like 4.3. Speed = workers working ÷ max_workers (3 of 8 = 37%)
  - **Workers are tied to their building.** Nobody moves on their own, and there's no job-hopping. A building only loses workers when the player decides: **lowers its staffing** (the extra workers are freed), **suspends** it or **demolishes** it (all freed; a resumed building queues again for workers)
  - **Full or idle buildings keep their workers**, unpaid, until they restart (wages only while producing)
  - **Fixed minimum wage** per worker type, set by the game (`wage_per_hour` in `worker_types`: low-skilled $15, high-skilled $30, professional $60). Players can't pay less. Phase 4: the server could change it, like a law
  - **Wage bonus per building**, chosen in its window like staffing (Tropico-style budget): **None 0% / Small +20% / Good +40% / Big +60%** (`wage_bonuses` in `game_config.json`; whole dollars: $15 → $18 / $21 / $24). New buildings start at None. Shown as "Wage: $15 + $6 bonus = $21 per worker / hour"
  - **Warehouses are always staffed first** (decided 2026-10-02; `staffed_first` in `buildings.json`): they get free workers before every other building, whatever bonus the others pay, and lose them last, so storage room never vanishes while people are free
  - **Who gets free workers** (new arrivals, or workers freed by the player), after the warehouses: each takes an open post at the building with the **biggest bonus**. Same bonus: they take turns one at a time, the emptiest building (fewest hired compared with what it asked for) first, then the older building. Open posts = what the staffing level asks for, at finished, non-suspended buildings
  - **Fewer people** (a house demolished): the unemployed leave first, then workers at the buildings with the **smallest bonus** (newest building first among equals)
  - Raising a bonus doesn't pull workers from other buildings (they're tied); it puts the building first in line for the next free workers
  - Later (Phase 3, happiness): a bigger bonus could also make workers happier and more productive, like Tropico's budget. Not now: it would change the whole balance
  - **Warehouses get no bonus** (decided 2026-10-02; `fixed_wage` in `buildings.json`): they always pay the minimum wage, since they're staffed first anyway
  - Offline catch-up stays one calculation: each person moving in takes the best open post at that moment
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
  - Warehouse — pre-built (added 2026-10-02, §5.10), room for 10,000 goods with its 4 workers
  - Starting cash — **$10,000** (`starting_cash` in `game_config.json`; raised from $5,750 on 2026-10-02 so a new player can afford the basic buildings, including their first Supermarket, §5.16; still tunable)
  - Wheat Farm — **not** pre-built; building it is the player's first tutorial action

### 5.9 Taxes & Fees (sales tax built 2026-10-02)

**The government taxes the player's company** (not Tropico-style "you are the government"). Taxes are also the economy's **money sink**: money leaves the game, which keeps prices from inflating once the player market exists. Our own design, inspired by (not copied from) Sim Companies' "costs grow with the company".

| Charge | What | When | Status |
|---|---|---|---|
| **Sales tax** | Progressive tax on Retailer sales, taken from the proceeds | At each sale | ✅ Built 2026-10-02; to be replaced by the Company Tax (5.9.1) |
| **Market fee** | **3% per trade** on the player market, paid by the seller, **on top of** the Company Tax (§5.9.1): the price of selling fast to anyone | At each trade | Phase 4 (`market_fee` already in `game_config.json`, unused) |

**Progressive daily-sales tax** (all PLACEHOLDERS, in `game_config.json` → `sales_tax_brackets`, `sales_tax_window_hours`):
- The rate depends on how much the company sold to the Retailer in the **last 24 hours** (a rolling window, so a quiet day brings the rate back down):

| Sold in the last 24 h | Rate on that part |
|---|---|
| First $5,000 | 0% |
| $5,000 – $25,000 | 8% |
| $25,000 – $100,000 | 15% |
| Above $100,000 | 22% |

- **Marginal, like income-tax brackets:** each part of a sale pays the rate of the bracket it falls in, so selling more never leaves you with less money
- **Taxes grow as the company grows** automatically: more buildings → more sales → higher brackets. No separate "company size" count is needed (this replaced the earlier proposal of 5% + 1% per building)
- ~~Market trades pay the 3% fee only~~ — **superseded 2026-10-02 by the Company Tax (§5.9.1):** every sale in every channel pays the Company Tax; the Market adds its 3% fee, Dock contracts add nothing
- **No property tax or profit tax** for now (a profit tax by company size is planned to replace these brackets: 5.9.1)
- **Where it shows:** the sell message ("Sold 100 Bread for $744 ($56 sales tax)"); Stats → Cash flow ("Sales tax" under money out, plus a box with 24 h sales, the current rate and the next bracket)
- **Rules:** `Simulation.sell`, `sales_tax`, `tax_bracket` in `scripts/sim/simulation.gd`; sales are logged in `state.sales_log` as [time, amount], entries older than the window are dropped

**Building costs raised with the tax** (the balance check found a farm paid for itself in ~6 minutes): Wheat Farm **$2,000**, Flour Mill **$5,000**, Bakery **$8,000**.

**Halt rule (built 2026-10-02):** a building whose storage is full **halts**: it makes nothing, its workers wait, unpaid and still tied to it (since 2026-10-02, §5.6), and it pays **no wages** until the player collects. Offline, wages stop at the exact moment storage fills. The same goes for an **idle** Mill/Bakery (no jobs queued, decided 2026-10-02): no wages until a job is queued, and offline the wages stop the moment the last job is done.

**Balance check** (per day, before the cost raise; PLACEHOLDERS):

| Company | Sales | Wages | Sales tax | Tax share | Profit |
|---|---|---|---|---|---|
| Small (1 chain) | $49.5k | $8,640 | $5,275 | 10.7% | $35.6k |
| Medium (3 chains) | $148.5k | — | $23,520 | 15.8% | ~$99k |
| Large (10 chains) | $495k | — | $99,750 | 20.2% | ~$308.9k |

Still to decide: whether bracket changes are announced in advance once the server sets them (Phase 4).

#### 5.9.1 Company size and Company Tax (planned 2026-10-02; replaces the sales brackets above; not built)

**Why it replaces the brackets:** the brackets only look at the last 24 h of sales, so a big company that sells little that day pays almost nothing. Real taxes (e.g. Philippine corporate income tax, used only as inspiration) tax **profit**, at a rate that depends on **how big the company is**. Our own version, not a copy of any real law or of Sim Companies.

**Company size: the company score**
- **Company score = assets + sales in the last 30 days**
  - **Assets** = what all the company's buildings cost to build (houses, warehouses and starter buildings included). Cash and goods in stock are **not** counted, so saving is never punished
  - **Sales** = everything sold in the last 30 days (a long window, so storing goods and dumping them in one day can't buy a size the company hasn't earned)
- Checked **continuously**: the moment the score passes a limit the company moves up, with a message ("Your company is now a Corporation!")
- **The size never goes down**, like a reputation: a slow month doesn't demote you

**Size tiers** (names decided 2026-10-02; limits and rates are PLACEHOLDERS, in `game_config.json`):

| Size | Company score | Company Tax on profit |
|---|---|---|
| **Startup** | under $50,000 | 10% |
| **Small Business** | $50,000 – $250,000 | 15% |
| **Company** | $250,000 – $1,000,000 | 20% |
| **Corporation** | $1,000,000 – $5,000,000 | 25% |
| **Conglomerate** | $5,000,000 and up | 30% |

**Company Tax**
- Taxed on **profit**: sale price − what the goods cost you to make (their cost tag, §5.14). The whole profit pays the rate of your current size (no brackets inside a size)
- **Worked out at each sale**, at the size you have at that moment (so building right after a bill can't dodge a cycle at the new rate), and **collected every 12 hours together with the water bill** (§5.13): one shared bill time. Unpaid = debt, no late fee
- **No minimum tax for now**: selling prices always cover costs and nothing can be bought yet, so a sale can't make a loss. Add a small minimum (e.g. 1% of sales) when buying goods arrives
- **Moving up must feel like a reward, not a punishment:** each size will later unlock things (new buildings, more building slots, bigger loans, better contracts). Until unlocks exist, only the tax changes
- **Where it shows:** a size badge in the HUD; Stats → "Company score $85,000 · next: Small Business at $50,000…" with a progress bar; the Build Menu warns when a building would move you up; the sell message and bills show the tax
- **Knock-on changes when built:** the selling price formula (§5.12) assumes a 10% tax on sales and must switch to a tax on profit; the Dock and the Market were re-decided for it (2026-10-02): **Company Tax on every sale in every channel** (Retailer, Market, Dock contracts); the **Market adds its 3% fee**; **Dock contracts pay no extra charge** (the separate 1.5% contract tax is dropped), so direct deals stay 3% cheaper than the Market
- Example, one cycle with $3,000 sales and goods made for $1,800 ($1,200 profit): Startup pays $120, Company $240, Conglomerate $360

**Critique that shaped it (2026-10-02):** fixed tiers make a jump at each limit (one more farm can raise the tax on *all* profit). Accepted on purpose because a size is something players will want for its rewards; a smooth rate (10% + 1% per $20k of assets) was the alternative.

#### 5.9.2 Later: administration overhead, credit rating, reputation (ideas, not planned in detail)
Three other ways "bigger" or "trusted" could matter. None is built or scheduled.
- **Administration overhead** (Sim Companies-style): an extra % on all wages that grows with the number of production buildings (e.g. 2% per building after the first), shown as an "Admin" line in cost per unit. Makes big companies' goods cost more to make. Maybe later, once there are many buildings to grow into
- **Credit rating** (with loans/bonds): the game's own "rating agency" judges whether the company can be **trusted with money**, from bills paid on time, debt, cash flow and activity. Unlike the size it **can go down**. It sets loan interest and how much can be borrowed, and finally gives unpaid bills a consequence. Sim Companies has a similar secret-formula rating for bonds; ours gets its own design
- **Reputation** (multiplayer, Phase 4+): **players rate each other** after each deal. Fits **contracts** (promises to deliver, pay, meet quality), not instant market buys where nothing can go wrong. Simple 👍/👎 with an optional reason; no rating in 24 h = 👍; shown as "97% 👍 (312 deals)" over the last 90 days. Against abuse: blind ratings (shown only after both sides rated or 24 h passed), only real completed deals, big deals count more. Good reputation lists your offers higher; players can block low-rated companies

### 5.10 Warehouse Buildings & Suspending (built 2026-10-02)

**Warehouse** (`warehouse` in `buildings.json`, category `storage`, Build Menu tab "Storage"):
- All warehouses together hold the company's goods: **one shared stock**, no moving goods between them. Room = the sum of every finished, working warehouse
- One comes **pre-built** in the starting kit; more cost **$3,000** each (5 s to build). PLACEHOLDERS
- **Workers: a fixed 4 low-skilled** at the **minimum wage** ($60/hour, no wage bonus), with **no Low / Medium / High choice** (decided 2026-10-02; `fixed_workers` in `buildings.json`). **Workers make the room:** 10,000 with all 4 working (raised from 2,000 on 2026-10-02). The only way to get fewer is a town short of people (2 of 4 = 5,000 room), so build houses. **Warehouses are staffed before any other building** (§5.6), so this only happens when the town has fewer free people than warehouse posts
- **More workers only by upgrading** (Phase 2 building upgrades): **Level 2 doubles the workers to 8**, and since workers make the room, the room doubles too (4,000). Upgrade cost and time TBD (see Section 11)
- The building window shows **every stored item as a tile with its icon and amount** (all warehouses together), above the workers
- Warehouses are **always working** (they store), so they always pay wages unless suspended. If an empty warehouse sent its workers home it would have no room for the first goods
- **Less room never destroys goods:** if room shrinks below what's stored, nothing new comes in (Collect is refused) until there's room again
- You can't demolish or suspend your last warehouse's room away: demolishing needs at least one warehouse to remain and the others to have room for everything stored; suspending a warehouse needs the same room
- Screens: the **Warehouse** card in the bottom menu lists the stock (amount, worth at today's price) and the room; tapping a warehouse opens its building window (stored goods with icons, workers, usable room, all warehouses' fill)
- **Selling is not done here:** a separate **Retail** building comes later (decided 2026-10-02). The temporary Sell test buttons stay until then
- Save format version 2: older saves get the starter warehouse added (`save_format.gd` `_migrate`)
- Later ideas: special storage (cold store for bread, grain silo), power for cold storage

**Suspend** (building window → Suspend / Resume; any building with workers):
- A **"soft demolish" that keeps the building**: the player switches it off instead of demolishing and paying to rebuild
- On suspending: **work in progress is lost** (the batch being made, a half-grown field), and **everything already produced or paid for goes to the warehouse**, with demolish's rules: goods in its storage and a finished batch in full, waiting jobs' ingredients in full, the batch being made gives back half its ingredients (`cancel_refund_in_progress`). What doesn't fit stays inside the building, to collect later
- While suspended: **no workers** (freed for other buildings), **no wages**, and from Phase 2/3 **no power**; it takes no jobs; it looks greyed on the map. It stays suspended while the player is away
- **Resume is free and instant**; its work starts from the beginning
- Asks "Are you sure?" first and shows what goes back to the warehouse
- Rules: `Simulation.can_suspend`, `suspend`, `resume`; `is_producing` is false while suspended, so wages, jobs and later power all follow

### 5.11 Dock — Export & Import (planned 2026-10-02, later in the game; not built)

A coastal building, inspired by Tropico's docks. Unlocked later in the game (when exactly is TBD).

**Why it exists: to get players dealing with each other.** Selling by direct contract through the Dock is **cheaper** than selling on the Market, so players are rewarded for finding trade partners instead of selling to an anonymous market (decided 2026-10-02). The Market stays the quick, convenient option.
- **Stores goods like a warehouse:** its room adds to the one shared stock (§5.10)
- **Fixed workers**, like the warehouse (number TBD)
- **One dock at first**; more may be allowed later
- **Export and import any goods:** raw resources, in-between goods (Flour) and finished products
- **Export = a contract signed directly with the buyer**, so there is **no 3% market fee** (that fee is only for selling on the Market, §5.9). That is the dock's advantage. Before live players exist (Phase 4) the buyers are in-game companies; from Phase 4 they can be other players (Contract channel, §5.2)
- **Export contracts pay the Company Tax and nothing else** (decided 2026-10-02, §5.9.1): all sales are taxable, so contracts pay the Company Tax on their profit like every sale, but **no 3% market fee and no extra contract tax**. So a direct deal is always 3% cheaper than the Market. (Replaces the earlier flat 1.5% contract tax, which was set against the old sales brackets)
- **Contract price limits** (decided 2026-10-02, against cheating): a contract price that is unrealistically low or high is refused, so players can't use contracts to pass money between their own accounts (e.g. "selling" 1 Wheat for $50,000). Where the limits sit is TBD (Section 11)
- **Prices follow the cost per unit:** what it costs to make a good sets its export and import price, so a finished product is worth more than the raw materials that went into it (respecting the conversion ratios in §5.4)
- **Cost per unit = the running costs of making it** (decided 2026-10-02): ingredients, wages, and electricity (what the power costs), plus water if a water utility is added later. **Not** the building's construction cost
- **Parked for later** (see Section 11): ships and their timing, placing it on the coast, when it unlocks

### 5.12 Prices: cost-based, worked out live (decided 2026-10-02)

**Why:** the first fixed prices (Wheat $2, Flour $4, Bread $8) made raw wheat the best business: the Farm paid for itself in 1.9 hours, the Mill in 14 and the Bakery in 30, so processing didn't pay. Prices now follow a rule, so every building pays off the same way, and later costs (power, water) flow into prices by themselves.

> **This is the SELLING price, not the player's cost** (clarified 2026-10-02). It is the designer's price, built from **standard numbers** in the data files (minimum wage, base water price, a standard crew), so a player's own choices never move it. What it actually cost *you* to make something is the **cost per unit** (§5.14): running costs only, no building share. Selling price − cost per unit − tax at the sale = your profit. (Same split as Sim Companies: research report `C:Program FilesProject_AIMYSIMSeportsSim Companies production cost.md`.)

**The formula** (Retail price of one unit; for the building that makes it, at full staff):

> **Price = (ingredients + wages + building share + later power/water) ÷ units made ÷ (1 − typical tax rate)**

1. **Ingredients** at their own price (flour's cost includes the wheat you could have sold instead)
2. **Wages** for a standard crew: `max_workers` at the **minimum wage**. A player's own bonuses never raise prices: they cut that player's profit, so they stay a real choice
3. **Building share** = build cost ÷ **payback time**, for the batch's duration. **Payback = 12 hours of production** (one game day, `pricing.payback_hours`): every production building pays for itself in 12 hours at full staff. This is the **profit margin** built into the price, never part of the cost per unit
4. **Power and water** (Phase 2/3): their cost per batch is added the same way, so a rise in the electricity price raises every product that uses power
5. **Tax**: divided by (1 − **10%**, `pricing.typical_tax_rate`), so a typical company keeps that profit after sales tax; big companies in higher brackets keep less (the tax's job)

**Worked out live** by the game rules from the data (`Simulation.unit_price`), never typed in by hand: change a wage, a build cost or a timer, and prices follow. Later, dynamic prices multiply this by supply and market mood (see Section 11). An item can have a fixed `price` (dollars) in `resources.json`, which wins over the formula: for goods no building makes, and in tests.

**Cents (decided 2026-10-02):** only **prices and costs per unit** show cents ("$0.53 each"). Everything else shows **whole dollars, rounded**: cash in the HUD ("$1,876"), building costs ("$8,000"), totals, wages and statistics. Internally the game rules still count money in whole **cents** (575000 = $5,750), so adding and subtracting never drifts; it just isn't shown. Unit prices are rounded to the cent; a sale's total is units × unit price (shown rounded to the dollar).

**Today's numbers** (PLACEHOLDERS, from the formula; water added 2026-10-02, §5.13):

| Product | Built from | Price | Building's profit / hour |
|---|---|---|---|
| Wheat | ($120 wages + $60 water + $166.67 building share) ÷ 600 wheat, ÷ 0.9 | **$0.64** | Farm ≈ $167 (pays back $2,000 in 12 h) |
| Flour | (400 wheat at $0.64 + $120 + $416.67) ÷ 320 flour, ÷ 0.9 | **$2.75** | Mill ≈ $417 ($5,000 in 12 h) |
| Bread | (192 flour at $2.75 + $120 + $666.67) ÷ 144 bread, ÷ 0.9 | **$10.14** | Bakery ≈ $667 ($8,000 in 12 h) |

**Selling** happens in the **Supermarket** (§5.16): the player puts any amount on a shelf at a price tag, and the shelf sells over time.

### 5.13 Water: the public water supply (decided 2026-10-02)

The first **utility** (electricity, §5.5, will work the same way and reuse the same rules).
- **Source: the government's public water supply only**, piped in from outside the village. Players don't build water sources (no wells for now; maybe later as an upgrade path)
- **A flow, not a good:** buildings use a steady number of **m³ per hour** while they work; nothing is stored or carried. Automatic, no buttons
- **Who uses it** (`water_per_hour` in `buildings.json`, PLACEHOLDERS): **Wheat Farm 30 m³/h** (irrigation). Bakery: TBD (Section 11). Flour Mill: none
- **Only while producing**, the same rule as wages and power: a halted, idle or suspended building uses none. A building at part speed (short of workers) uses that share (6 of 8 workers = 75% of its water)
- **Unlimited supply, heavy users pay more** (decided 2026-10-02): nobody is ever cut off, so water never slows a building down. The price per m³ is tiered on the company's total use per billing cycle, like the tax brackets: the first **1,200 m³ per cycle** (100 m³/h over 12 h) at the base price, anything above at **+25%** (`water` in `game_config.json`)
- **Base price ~$2 per m³** (PLACEHOLDER). Later it can drift slowly (market mood), like the electricity price
- **Paid like wages:** settled over time, also while away, into debt if cash runs out; parts of a cent carry over. Shows as **Water** under money out (Stats → Cash flow) and in the Welcome back window. *(Paid continuously at first; replaced by the billing cycle below on 2026-10-02)*
- **Billing cycle (decided and built 2026-10-02):** utilities are billed like in the real world. Applies to water now and electricity later; **wages stay continuous** (no payday)
  - **One cycle = 12 real hours** (one game day, matching the 12-hour day/night cycle in §5.5.4); bills fall due at fixed moments, so time away still settles in one calculation
  - **A meter runs all the time** (also while away): each m³ is recorded at the price in effect when it was used, so a price change mid-cycle only affects use after it
  - **Charged all at once at the end of the cycle.** Not enough cash: it goes into **debt**, like wages; buildings keep running. **No late fee**
  - **Heavy users pay more per cycle:** the first **1,200 m³ per cycle** at the base price, anything above **+25%** (the same 100 m³/h limit as before, over 12 hours)
  - **Always visible:** "Water bill so far: $412 · due in 3h 20m" (HUD or Stats); a message when it's charged ("Water bill paid: $718 for 359 m³"); bills paid while away in the Welcome back window; a short bill history in Stats
  - Cost per unit (building window) still uses the current price per m³: the bill changes *when* you pay, not *what* it costs
- **In prices (§5.12):** a batch's water (at the base price) is one more cost line, so a water price change flows down the chain. Farm: 30 m³/h × $2 = $60/h → Wheat **$0.53 → $0.64**, Flour $2.60 → $2.75, Bread $9.92 → $10.14

### 5.14 Cost per unit (decided and built 2026-10-02)

**What it costs YOU to make one unit**, shown in each production building's window. It is a fact about your company, separate from the selling price (§5.12, the designer's price). Same approach as Sim Companies (research report in `C:\Program Files\Project_AI\MYSIMS\reports\Sim Companies production cost.md`).

**Cost per unit = (ingredients + wages + water + later electricity) for one batch ÷ units the batch makes**

| Line | Counted at | Changes when… |
|---|---|---|
| **Ingredients** | the **cost tag** of the units used (what they actually cost you), not today's market price | the cost of what went in changes |
| **Wages** | **your** workers' wage: minimum wage + **your bonus** | you change the bonus, or the minimum wage changes |
| **Water** | the m³ the batch used × the price when it was used (metered, §5.13) | the water price changes |
| **Electricity** (Phase 2/3) | MW × batch time × the power price | the power price changes |

**Never part of cost per unit:** the building's construction cost (its payback is the profit margin inside the selling price), the sales tax and the market fee (they're charged **at the sale** and shown there), and transport if it's added later.

**Cost tags in the warehouse:**
- Every item in stock carries an **average cost per unit**. Made goods carry what making them cost; bought goods carry what you paid
- **Mixing averages them:** 32 own flour at $0.75 + 32 bought flour at $2.75 = 64 flour at **$1.75** each. Using some keeps that average
- A batch's ingredients take their cost tag with them into the batch, and the output goes into storage with its new tag

**Staffing doesn't change the cost per unit:** half the workers means half the wages per hour, but each batch takes twice as long, so each unit costs the same. Only the **bonus** raises wages per unit.

**Worked example** (today's numbers: full staff, no bonus, water $2/m³, everything made by your own company):

| Step | Batch | Costs of one batch | Cost per unit |
|---|---|---|---|
| Wheat Farm | 1 min → 10 wheat | wages 8 × $15/h × 1 min = $2.00 · water 0.5 m³ × $2 = $1.00 → **$3.00** | **$0.30** per wheat |
| Flour Mill | 6 min, 40 wheat → 32 flour | wheat 40 × $0.30 = $12.00 · wages $12.00 → **$24.00** | **$0.75** per flour |
| Bakery | 10 min, 32 flour → 24 bread | flour 32 × $0.75 = $24.00 · wages $20.00 → **$44.00** | **$1.83** per bread |

Selling the 24 bread: **sold for $243.36** (24 × $10.14) − **made for $44.00** − **sales tax $0** (first $5,000 in 24 h; $19.47 in the 8% bracket) = **profit $199.36**.

| What happens | Bread's cost per unit |
|---|---|
| Normal (above) | $1.83 |
| Bakery bonus **+40%** (wages $20 → $28) | ($24 + $28) ÷ 24 = **$2.17** |
| Water price doubles to $4/m³ (wheat $0.40, flour $0.875) | about **$2.00** |
| All flour **bought** at $2.75 | ($88 + $20) ÷ 24 = **$4.50** |
| Half own flour, half bought (average $1.75) | ($56 + $20) ÷ 24 = **$3.17** |
| Half the workers | still **$1.83** |

**The water bill** (§5.13): each batch's water goes into its cost tag when it's used (the farm's $1.00 above); the 12-hour bill only collects the money (12 h of the farm = 360 m³ = $720). The bill changes *when* you pay, not what anything cost.

**In the building window** (draft):
```
Cost per unit                    Bread  $1.83
   Flour    1.33 × $0.75         $1.00
   Wages    8 × $15/h, 10 min    $0.83
   Water                         $0.00
Sells for $10.14 · about $8.31 profit each (before tax)
If you sold the flour instead: 32 × $2.75 = $88 → baking earns $135 more
```
- **Your numbers** (your bonus, your water costs, your ingredients' tags); the selling price stays on standard numbers
- The "if you sold the inputs instead" line uses today's selling prices: it answers "is this building worth running?"
- **The breakdown opens with a tap** (decided 2026-10-02): the window shows "Cost per unit $1.83 ▸"; tapping it shows the lines. A ▲ / ▼ for the change since an hour ago is still undecided (Section 11)

**How the rules can keep the tags exact** (for building it): per unit, wages = `max_workers` × wage per worker × batch time ÷ units (the same whatever the staffing, see above), and water = `water_per_hour` × batch time × price ÷ units. So a finished batch's cost can be worked out the moment it finishes, without tracking every second; the save stores each stock's **total cost** next to its amount (average = total ÷ amount).

### 5.15 Building Upgrades & the Construction Company (planned 2026-10-02, Phase 2; not built)

**Upgrades cost materials + labor, not a money fee** (decided 2026-10-02). Realistic: you buy the materials (from your own production, an in-game supplier, or from other players from Phase 4) and pay the laborers who build it.

**Construction materials** (new goods, made by ordinary production buildings, priced by the cost-based formula, §5.12):

| Material | Made by | From |
|---|---|---|
| Wood | Lumber Camp (extractor) | Trees |
| Planks | Sawmill | Wood |
| Bricks | Brick Kiln | Clay (Clay Pit) |
| Cement | Cement Plant (uses power) | Limestone (Quarry) |
| Steel | Steel Mill (uses power) | Iron ore + Coal (Coal Mine, §5.5) |

- **Simple rule: the higher the level, the more materials and the bigger the crew** (decided 2026-10-02). Each building has a **base cost** for Level 2 in `buildings.json`; each next level multiplies it by a growth factor (`upgrade_growth` in `game_config.json`, PLACEHOLDER ×1.6). New material types join as levels go up: Level 2 Planks + Bricks, Level 3 adds Cement, Level 4+ adds Steel. Crew size and hours grow the same way
- **Material buildings are ordinary buildings every player can build**, but not yet: they arrive in a later phase with upgrades (not in the current early stage)
- Each level says what it improves (batch, timer, storage, workers; the Warehouse's Level 2 doubles its workers, §5.10)
- Still capped by the Construction Office's level (§5.8)

**The Construction Office is the construction company** (decided 2026-10-02):
- It has **laborers**, workers from the town's population
- Every **upgrade** needs some laborers for some time (e.g. 5 laborers for 6 hours). Laborers on a project are tied up until it's done, so the crew size limits how many projects run at once. A higher Construction Office level gives a bigger crew
- **Laborers are paid per project, not per hour:** the fee (laborers × wage × hours) is paid once when the project starts, so a project can never stall halfway. Idle laborers cost nothing. The fee goes to people in the game, so it's a **money sink**
- Materials are also taken from the warehouse when the project starts (like a job's ingredients)
- Whether **new buildings** also need the construction company and materials (today: cash + 5 seconds) is still open (Section 11)

**A building stops while it is upgraded** (decided 2026-10-02). That makes upgrading a real decision (production is lost), instead of something you always do.
- **"Upgrade after this batch"** (default): the batch being made finishes, then the upgrade starts. Nothing is lost
- **"Start now":** the batch being made is cancelled with the usual rule (half its ingredients back, `cancel_refund_in_progress`)
- Queued jobs keep their ingredients and continue after the upgrade; goods in storage can still be collected
- No workers or wages while upgrading (like Suspend, §5.10); finishing offline is one calculation from timestamps (`upgrade_started_at` / `upgrade_finishes_at`)

**Hiring out idle laborers** (idea 2026-10-02, Phase 4): a player can **post** their idle laborers, like a Market listing (how many, price per hour). Players without enough laborers can hire them for a project. The owner earns the price and pays the laborers' wages; the laborers are tied up until the project is done.
- Contract-style, so it should follow the Dock rules: Company Tax only, no market fee (§5.11), and **price limits** against passing money between one's own accounts
- Reliability can feed Rating/Reputation (§5.3)
- Before Phase 4 there are no other players, so an **in-game contractor** could fill the same role (pricier than your own crew)

### 5.16 Supermarket — the Retail building, with village demand (built 2026-10-02, on trial)

The Retail building (selling to the village) is the **Supermarket** (`supermarket` in `buildings.json`, category `retail`, Build Menu tab "Shops"). It replaced the temporary Sell test buttons. **On trial:** built in its own Git commit so it can be undone if the design doesn't feel right.
- **The player builds it** (not pre-built). $2,500 (PLACEHOLDER), so the $10,000 start covers a Wheat Farm + Flour Mill + Supermarket (§5.8)
- **Sells finished food only:** Flour and Bread now; fruits later (§5.17). **Raw Wheat can't be sold** (decided 2026-10-02): only items with an `appetite` in `resources.json` go on shelves
- **Shelves:** 4 per store (`shelves`). Each shelf sells one product; **several shelves sell at once**. A product can be on **only one shelf in the whole village** at a time (the village has one appetite for it), so extra stores let you sell more *different* products, not more of the same
- **Putting food on a shelf:** choose the food, the amount (slider or All) and a **price tag**. The goods leave the warehouse at once (with their cost tags, §5.14); the window first shows the price, how many the village buys per hour, the time to sell out, sales, cost to make, sales tax and profit
- **Price tags** (our own idea instead of typing a price; `retail.price_tags` in `game_config.json`, PLACEHOLDERS from a demand curve speed = 1 ÷ price³):

| Tag | Price | Sells |
|---|---|---|
| Big Sale | −20% | 1.95× as fast |
| Sale | −10% | 1.37× |
| Normal | cost-based price (§5.12) | 1× |
| Premium | +10% | 0.75× |
| Luxury | +20% | 0.58× |

- **Village demand:** a shelf sells **people × the item's appetite × the tag's speed** per hour (appetite PLACEHOLDERS: Bread 3.6, Flour 3.2 per person per hour, tuned so ~40 people buy what one Farm + Mill + Bakery make; the game only shows village totals). The rate and price are fixed when the goods go on the shelf, so more people help the *next* shelf
- **Variety brings shoppers ("one-stop shop", our own idea):** +10% for each different product on the store's shelves beyond the first (`retail.variety_bonus`). It changes the moment a shelf sells out, so keeping shelves full keeps shoppers coming
- **Workers: a fixed 4 at the minimum wage** (decided 2026-10-02, like the warehouse: `fixed_workers`, `fixed_wage`): no Low / Medium / High and no bonus, because neither did anything worth having here (half the workers sell half as fast for the same total wages; a bonus only wins hiring priority). More only by upgrading later. **Not staffed first:** it waits its turn for free people; short of people, shelves sell slower (3 of 4 = 75%). Paid per hour **only while a shelf is selling**; empty shelves = idle, no wages. Electricity later (0 MW for now)
- **Paid at the end of each shelf batch** (decided 2026-10-02): when a shelf sells out, its sales minus sales tax (§5.9; Company Tax when that's built) reach cash. Taking a shelf down early (red X, asks first) pays for what's sold so far and returns the rest to the warehouse; demolish and suspend do the same
- **Offline:** exact, one calculation per stretch: settling splits time at each sell-out (the shoppers bonus changes then) and at worker changes. The Welcome back window lists what sold and what it earned; while playing, a message says "Sold out: 1,000 Bread. +$9,331"
- **Why demand limits volume (re-assessed 2026-10-02):** a price-only "demand meter" (±30%) was rejected: dumping goods at −30% still made a profit, and holding stock back to sell at +30% could be gamed. Here more goods simply take longer to sell, and lowering the price is the player's choice
- **More store types later** (decided 2026-10-02), each selling its own category, e.g. a **Hardware Store** for Planks, Bricks and Cement once construction materials exist
- Rules: `Simulation.can_stock_shelf`, `stock_shelf`, `can_clear_shelf`, `clear_shelf`, `stock_preview`, `_settle_retail`; window: `building_panel.gd` (Shelves + "Put on a shelf"). The Retailer's instant `sell` stays in the rules (tests use it) but no screen calls it

### 5.17 Plantation & Fruits (planned 2026-10-02, later; not built)

- **Plantation**: an extractor like the Wheat Farm, where the **player chooses the crop** per building: **Banana, Mango, Lemon, Pineapple, Papaya, Coconut** (that's all for now). Each fruit has its own timer, batch and price in the data files
- **Fresh fruit is a finished product:** sold straight to customers at the Supermarket (§5.16) for local consumption. **Processing is optional, never forced** (decided 2026-10-02); unlike raw Wheat, fruit doesn't need a processor to earn money
- **Fruit vs. wheat is balanced by demand** (decided 2026-10-02): fruit needs one building to earn, wheat needs a Farm + Mill. If everyone grows fruit, fruit floods and Flour/Bread get scarce, so their prices and demand rise. Needs demand in the game: dynamic pricing (Section 11) and, from Phase 4, other companies buying
- **Processing ideas for later** (optional extra value, not needed to sell): Juice Factory (Mango/Pineapple juice, Lemonade), Banana Bread (a second Bakery recipe: Flour + Banana), Coconut Oil and Coconut Vinegar (Oil Mill / Vinegar Plant), Banana Chips (Banana + Coconut Oil), Dried Mango, Pickled Papaya (Papaya + Vinegar), Canned Pineapple (needs cans from Steel)

## 6. UI/UX Screens

**Phase 1 screens:**
- **Village View** — main isometric view, tap/click a building to interact, pan/zoom camera. Starts on the whole-island view (re-framed if the window changes size before the player moves); zooming out stops at that view and panning stops at the island's edges
- **Build Menu + Placement Mode** — list of buildable buildings with cost, then place on the grid (needed in Phase 1a: the player's first action is building a Wheat Farm)
  - ✅ Redesigned 2026-10-01 (Tropico-style, tabs on the right): a window with category tabs down its right edge (the open tab joins the page), a title banner, a grid of building cards (picture + name; lock badge = not available, coin badge = can't afford yet), and a details strip (name, cost or "Need X more", description, what it makes, storage, Build button). Tap a card to see its details, tap it again or press Build to place it; on PC, pointing at a card previews it. Tabs are listed in `data/build_menu.json`; each building picks its tab with `menu_tab` in `buildings.json` (buildings with `buildable: false` show locked; tabs with nothing in them are hidden). Wide screens: a window nudged clear of the money bar; tall screens: a bottom sheet. File: `scenes/ui/build_menu.gd`
- **Building Panel** — current recipe, timer progress, job queue, collect button, upgrade button (upgrade button from Phase 2) — ✅ built, plus a **Workers** section: Low / Medium / High staffing buttons, workers working (of asked for, max), wages per hour, and the production rate at the current speed
  - ✅ Built 2026-10-01, Clash-of-Clans style: tapping a building selects it (bounce + glow + ring) and shows an action bar (Info / Collect / Produce / Build); tapping a building with goods waiting also collects; "ready" bubbles float over buildings; "+32"/"-40" numbers rise on collect/produce. Info opens the full panel (recipe, progress, queue slots, storage, Collect / Make). Files: `scenes/ui/building_bar.gd`, `building_panel.gd`
  - Industrial buildings (extractor/processor) skip the bar: tapping opens the panel straight away
  - **Cancel a batch:** tap a queue slot. A waiting batch refunds 100% of its ingredients at once; the batch being made refunds 50% after an "are you sure?" (`cancel_refund_waiting` / `cancel_refund_in_progress` in `game_config.json`). A finished batch can't be cancelled (collect it). No "pause": with no upkeep costs, pausing would gain nothing over cancelling
  - **Demolish:** red button at the bottom of the panel, with a confirm window showing what comes back: 50% of the build cost (`demolish_refund`), goods inside, and queued ingredients (same refund rules). Only buildings the player can build can be demolished (starters stay). Refused if the warehouse can't hold what comes back
  - **Move:** blue button in the panel (or the action bar for the Construction Office / Small House). Uses Placement Mode: the building fades where it stands, a preview follows the pointer, tap a free tile. Free, works for every building, and production carries on through the move
  - **Fill queue:** "Fill xN" beside the Now heading queues as many batches as there are free slots and ingredients for. The Now box shows status, progress and the queue together (its first slot is the batch being made)
- **Recipe Select** — sub-panel of Building Panel (once 2+ recipes unlocked)
- **Inventory/Warehouse** — all resources held, quantities, storage caps
- **Retailer/Sell Screen** — sellable resources, current NPC price, quantity selector, sell button
  - ✅ Built 2026-10-02 as the **Supermarket** window (§5.16): shelves with progress and a take-down X, then "Put on a shelf" (food, amount slider + All, five price tags, a preview of price / speed / time / profit). The temporary Sell test buttons are gone
- **Offline Summary** — "While you were away…" popup listing what was produced (and, from Phase 2/3, wages paid)
  - ✅ Built 2026-10-02 as **Welcome back!** (`scenes/ui/welcome_back.gd`): shows at start-up after at least `welcome_back_after_seconds` (120) away. Time away, goods made, people who moved in, wages paid, cash now, plus warnings for full (halted) buildings and debt
- **Settings** — sound/music volume, save reset, language (if localized)
- **Statistics** (✅ built 2026-10-01, "Stats" card in the bottom menu) — four tabs: **Production** (made / used / net per minute right now from working buildings, how many buildings are working / idle / full / being built, all-time made / sold / earned per item), **People** (population, employed, unemployed, open jobs, jobs per building type), **Cash flow** (last hour and all-time money in by source and out by category), **Graphs** (cash, cash flow, people, production over 15 min / 1 h / 6 h; rates are 10-minute averages; point at or drag across a graph for values). Counters and the graph history live in the save (`state.stats`, updated by the game rules); a graph point is added every `stats_sample_seconds` (60) and time away becomes one point, never a minute-by-minute replay. Keeps `stats_history_size` (360) points
  - ✅ Built 2026-10-01 (the "Menu" card in the bottom menu bar): Music, Sound effects, Building names, Water detail (High/Low, for slow phones), Full screen (PC), About, Quit (PC). Saved in `user://settings.json` by the `Settings` autoload, separate from the game save. **Start over** (2026-10-02, asks "Are you sure?" first) starts a new game. Still to add: language (if localized). Music/Sound switches mute the "Music"/"SFX" audio buses, ready for when the game has sound
- **Quest Log** (Phase 1b) — active tutorial + daily/weekly quests, progress, claim-reward button
- **Profile** (Phase 1b) — XP/level, badges earned (Phase 4 adds rating)
- **Persistent HUD** — currency balance, XP bar, active quest progress (compact), Population (current/capacity), notification icons
  - ✅ Phase 1a part built 2026-10-01: top-right resource bars (cash with count-up, workers needed / people — red when there are more jobs than people, tap or point at it for the breakdown incl. room in homes — and warehouse fill) plus a chip per item; short messages ("toasts") at the top. XP/quests arrive with Phase 1b. File: `scenes/ui/hud.gd`
  - ✅ **Bottom menu bar** (2026-10-01, Tropico-style), bottom centre: paper cards with an icon, clipped onto blue folders with the name underneath; pointing at a card lifts it. Cards: Build, Warehouse, Market, Menu (Settings). Market is greyed with a lock until that screen exists (tapping says "coming soon"); Warehouse opens the stock list since 2026-10-02. It slides away while a building's action bar, Placement Mode or the Build window is using the bottom of the screen. The card list is at the top of `scenes/ui/menu_bar.gd`; art in `assets/ui/menu_tile.svg` / `menu_card.svg`
- **UI look** — one theme for everything (`scenes/ui/ui_theme.gd`): chunky glossy buttons in 5 colours, cream windows, bold white outlined text; all art is SVG in `assets/ui/` (easy to restyle). Pop-up windows share `scenes/ui/modal_window.gd` (centred on wide screens, bottom sheet on tall ones)

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

**✅ Built 2026-10-02:**
- `scripts/sim/save_format.gd` turns the state into JSON text and back (pure, tested in `tests/test_simulation.gd`). Times are written at full precision; whole numbers come back as whole numbers; a save from a **newer** game version is refused rather than misread; buildings or goods no longer in `data/*.json` are dropped with a note. Format changes: raise `Simulation.SAVE_VERSION` and add a step to `_migrate()`
- `Economy` loads `user://save.json` at start-up and catches up the time away in one settle (its report feeds the Welcome back window). It saves every `autosave_seconds` (30), within a second of any player action, and when the window closes, the phone app goes to the background, Android Back is pressed, or the game quits
- **Safe writing:** the new save goes to `save.tmp` first and is then swapped in; the previous save is kept as `save.backup.json`. A damaged save is renamed `save.unreadable-<time>.json` (never overwritten) and the backup is loaded instead; if both fail, a new game starts and the player is told
- Test runs never touch the real save (`Engine` meta `running_tests`)
- Dev clock: if a save was made after the dev panel skipped time ahead, a debug build skips ahead again on loading
- Saved as-is today: `profile.currency`, `plot`, `next_building_id`, `buildings` (with `job_started_at`, `built_at`, `blocked`, `staffing`), `inventory`, `population`, `settled_at`, `wage_carry`, `sales_log`, `stats`. Not yet: xp/level, quests, badges (later phases)

**Phase 4 additions:**
- Market/Exchange and Contract data are shared/global state — not part of an individual player's save
- Server must own all timers once state is server-side (never trust a client-reported completion time)

## 9. Performance & Security

### 9.1 Mobile Performance
- **Texture atlasing** — pack building/tile sprites into shared texture sheets (via TexturePacker) to minimize draw calls
- **Limit active per-frame logic** — only actively-producing buildings need per-frame updates; idle/finished ones don't
- **Offline/idle catch-up must be a one-time math calculation, not a simulated tick-by-tick replay** — calculate completed jobs via elapsed time ÷ timer duration, never simulate every second that passed (would visibly freeze the game on reopen after a long absence)
- **Test on a real low-to-mid-range Android device early**, not just in-editor or on PC — catch problems in Phase 1 (3-4 buildings) rather than Phase 3 (full village)
- **Watch the island shader** — `scenes/village/island.gdshader` runs for every screen pixel every frame (the water animates). It is kept cheap (detail work only near the coast), but check its frame cost in that first real-device test; once the island becomes a baked picture (Section 4, visual step 3) only the water part remains

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

✅ **Built so far (2026-10-01):** `scenes/debug/dev_panel.gd`, the **Developer** window: set cash to any amount (negative to test debt), add any amount, quick +$1,000 / +$10,000 / +$100,000, set $0. Opens with **F12** on a computer or **5 quick taps on the cash bar** on a phone; `main.gd` only loads it when `OS.is_debug_build()`. Dev cash isn't counted as income in the statistics. Step 2 (exclude `scenes/debug/` from export) waits until there is a separate release preset: the only preset today is the Android one used for phone testing, which should keep the dev window.

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
- [x] Construction timers for new buildings → **5 seconds for every building** (`build_time` in `data/buildings.json`, changed from instant on 2026-10-01). While being built a building is faded with a countdown bar, makes nothing, takes no orders and adds no housing; starting buildings come already built. Builder limits (one construction at a time, etc.) may come in a later phase
- [x] Phone orientation → **Sideways (landscape) only**, like Clash of Clans (decided 2026-10-01). `display/window/handheld/orientation` = sensor landscape, so the game flips if the phone is turned the other way round. Held upright, the whole game was drawn at about a third of its size (the 1280x720 layout stretched across a narrow screen)
- [x] Soft currency → **dollars ($)**, shown everywhere money appears as "$1,250" (debt as "-$202") via `UITheme.money()` (decided 2026-10-01). Premium currency name still TBD

**Later phases:**
- [ ] Target platforms — is iOS in scope?
- [x] Art pipeline → **3D models rendered into 2D sprites by a Godot "photo studio" tool; free CC0 low-poly models first, upgrade later** (decided 2026-10-01, see Section 4)
- [ ] Audio/music plan (sources, licensing, or commissioned)
- [ ] Localization — which languages, and from which phase
- [ ] Firebase vs. Nakama — not needed until Phase 4
- [ ] Whether Market/Exchange stock-style companies get flavored to match in-game industries, or stay generic
- [x] Retailer prices → **cost-based formula, worked out live, 12-hour payback, cents allowed** (decided 2026-10-02, 5.12)
- [x] Retail building: instant sale, pre-built, no workers? → **No: a Grocery Store the player builds, with workers and (later) electricity, selling over time like a production job** (decided 2026-10-02, 5.16)
- [x] Grocery Store (5.16): can raw Wheat be sold? → **No, not at any store**: it is only an ingredient (decided 2026-10-02)
- [ ] Raw goods on the Dock and Market: §5.11 says the Dock exports *any* goods, raw included. Does "raw Wheat not sellable" also cover the Dock/Market, or only stores?
- [x] Fruits → **later**, from a **Plantation** with a crop choice (Banana, Mango, Lemon, Pineapple, Papaya, Coconut), sold fresh at the Grocery Store; processing optional (decided 2026-10-02, 5.17)
- [ ] Plantation (5.17): does changing crop lose the growing batch (replanting)? One crop per building, or several plots?
- [ ] Supermarket (5.16): tune the PLACEHOLDERS by playing: build cost $2,500, 4 shelves, 4 fixed workers, appetites (Bread 3.6, Flour 3.2), price tags, +10% variety bonus. Should fruits share one "fruit" appetite (5.17)?
- [x] Water → **public government supply only, a flow (m³/h), unlimited, heavy users pay more (+25% above 100 m³/h)**; Wheat Farm 30 m³/h (decided 2026-10-02, 5.13)
- [ ] Does the Bakery use water (e.g. 5 m³/h for dough)? (5.13, user decides later)
- [x] Utility billing → **a bill every 12 real hours (one game day), metered at the price when used, unpaid = debt, no late fee; wages stay continuous** (decided 2026-10-02, 5.13)
- [x] Cost per unit → **running costs only (ingredients at their cost tag + your wages incl. bonus + metered water + later electricity) per batch ÷ units; shown in each production building with the selling price, profit each and an "if you sold the inputs instead" line** (decided 2026-10-02, 5.14)
- [x] Building share in cost per unit? → **No: it is the profit margin inside the selling price (5.12)**; ingredients at what they actually cost you, not market price (decided 2026-10-02, 5.14; resolves the 5.11 Dock vs 5.12 Prices disagreement)
- [x] Cost per unit breakdown → **opens with a tap** (decided 2026-10-02, 5.14)
- [ ] Cost per unit: show a ▲ / ▼ for the change since an hour ago? (5.14)
- [ ] Land/grid size and expansion cost curve — and whether premium currency may buy land (see Section 7 caution)
- [ ] Quest content — specific tutorial quest list and daily/weekly quest pool
- [ ] Onboarding/tutorial flow (concrete first-5-minutes script)
- [ ] Economy safety / anti-abuse plan for Phase 4 player-driven market
- [ ] Social/community features (chat, friends, trade alliances)
- [ ] Legal basics (ToS, Privacy Policy) — needed once real accounts exist (Phase 4); also check local rules on selling premium currency in each launch country
- [ ] Marketing/launch plan
- [x] Power plants and the public grid → **planned 2026-10-02** (5.5): power is a flow (MW), and shortages slow every building by the same share; Thermal 40 MW first, then Wind, Solar, Nuclear; automatic public grid with Small/Medium/Large connection and a price that changes with time of day, market mood and usage; one game day = 12 real hours. Numbers are placeholders
- [x] Does the Wheat Farm use power? → **No, 0 MW** (decided 2026-10-02, 5.5.1)
- [x] Warehouse staffing → **fixed workers, no Low/High choice; Level 2 doubles them** (decided 2026-10-02, 5.10)
- [ ] Warehouse Level 2 upgrade: cost and build time; confirm the room doubles with the workers (4,000); Level 3 and beyond?
- [ ] Dynamic pricing: Retailer prices move with supply (selling a lot lowers the price, recovering over hours), market mood, and input costs like the grid price; swings kept modest (~±10–30%) and shown with a reason
- [x] Employee hiring cost, wage amount, and headcount-per-building numbers → **no hiring cost; wages Low-skilled 15 / High-skilled 30 / Professional 60 per hour; max 8 workers per production building at level 1, staffing Low 4 / Medium 6 / High 8** (decided 2026-10-01, placeholders, wages to move to the backend later)
- [x] What happens when the player can't pay wages (especially while offline) → **debt**: cash goes below 0 and sales pay it back; nothing can be built while in debt; buildings keep working (decided 2026-10-01)
- [ ] School timer/batch/storage-cap numbers for Elementary/High School/College
- [ ] Do Graduates stay in Population / count toward Employment Matching, or are they a separate pool?
- [ ] Specific per-building education-tier requirements for Employees
- [ ] Construction Office upgrade cost curve and exact level-cap relationship to other buildings
- [x] Upgrades (5.15): materials and amounts per level → **our own simple rule: base cost × growth factor per level; higher level = more materials and a bigger crew** (decided 2026-10-02). Exact base numbers set when built
- [ ] Upgrades (5.15): do **new buildings** also need the construction company and materials, or only upgrades? (Maybe cash only for the first, cheap buildings, so a new player is never stuck)
- [ ] Upgrades (5.15): before Phase 4, where materials come from when your own chain is short (in-game supplier?) and whether an in-game contractor rents out laborers
- [x] Upgrades (5.15): who can build the material buildings (Lumber Camp, Sawmill, Clay Pit, Brick Kiln, Quarry, Cement Plant, Steel Mill)? → **every player, from the later phase that brings upgrades**; not available in the early stage (decided 2026-10-02)
- [ ] Population growth rate tuning and House capacity numbers beyond the first Small House
- [ ] Dock (5.11): ships and their timing (how often, how much they carry, what happens while the player is offline)
- [ ] Dock (5.11): placement on the coast (needs a new placement rule; Placement Mode only knows the grass plot)
- [ ] Dock (5.11): when it unlocks (player level, Construction Office level, phase), its build cost and number of workers
- [x] Dock (5.11): how "cost per unit" is worked out → **running costs only: ingredients, wages, electricity (and water if added later); not the construction cost** (decided 2026-10-02)
- [x] Dock (5.11): do export contracts pay sales tax? → **Yes, all sales are taxable**; same brackets and same 24-hour total as Retailer sales (decided 2026-10-02)
- [x] Taxes per sale channel (re-decided 2026-10-02 for the Company Tax, 5.9.1) → **Company Tax on every sale in every channel; Market adds its 3% fee; Dock contracts add nothing** (no separate contract tax), so dealing directly is always 3% cheaper. Replaces the earlier "Market fee only" and "1.5% contract tax" answers
- [x] Dock (5.11), Phase 4 anti-abuse: a cheap direct contract could be used to pass money between a player's own accounts (selling at a silly price) → **contract prices have a floor and a cap; unrealistically low or high prices are refused** (decided 2026-10-02)
- [ ] Dock (5.11): what the contract price limits are measured from (cost per unit? recent Market price?) and how wide they are (e.g. 50%–200%)
- [ ] Dock (5.11): should imports cost a little more than making the good yourself, so the production chain stays worth building?
- [x] How is tax tied to company size? → **Company Tax on profit, rate by size tier (Startup / Small Business / Company / Corporation / Conglomerate); size = assets + 30-day sales, never goes down; collected with the water bill** (decided 2026-10-02, 5.9.1; replaces the sales brackets; not built)
- [ ] Company size: what each size unlocks (5.9.1); limits and tax rates are placeholders
- [ ] Administration overhead, credit rating and player reputation: if and when (5.9.2)

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

**2026-10-02 (Supermarket: fixed workers):**
- The Supermarket has a fixed 4 workers at the minimum wage, like the warehouse: no staffing or bonus choice (neither helped selling). It waits its turn for free people (not staffed first)

**2026-10-02 (Supermarket built, on trial):**
- The Retail building is the Supermarket (5.16): 4 shelves selling different foods at once, five price tags (Big Sale → Luxury), village demand from population × appetite, +10% shoppers per extra product, paid when a shelf sells out, wages only while selling. Raw wheat can't be sold. Replaces the Sell test buttons
- Demand re-assessed: volume is limited by the village, not a ±30% price meter (dumping still paid, and the meter could be gamed). Our own design, compared with Sim Companies' free price entry
- No save-format change (older saves load as they are; a save with a Supermarket loads in an older build with the Supermarket dropped)

**2026-10-02 (Grocery Store planned, starting cash):**
- The Retail building is a Grocery Store the player builds (5.16): sells finished goods over time like a production job, with workers and later power; more store types later
- Starting cash raised from $5,750 to $10,000 (`starting_cash`) so new players can afford the basic buildings
- Raw Wheat can't be sold at stores (ingredient only); fruits come later
- Plantation with a crop choice (Banana, Mango, Lemon, Pineapple, Papaya, Coconut), fruit sold fresh at the Grocery Store; processing optional ideas listed (5.17)

**2026-10-02 (sale-channel taxes re-decided for the Company Tax):**
- Company Tax on every sale in every channel; the Market adds its 3% fee; Dock contracts add nothing. Dropped the 1.5% contract tax and the "Market fee only" rule (5.9, 5.9.1, 5.11)

**2026-10-02 (building upgrades planned):**
- Upgrades (5.15): materials (Planks, Bricks, Cement, Steel; new construction chain) + laborers from the Construction Office, paid per project; no money fee. A building stops while upgraded ("after this batch" or "start now"). Idea for Phase 4: hire out idle laborers to other players. Not built
- Material amounts: our own simple rule (base cost × growth per level, more materials and bigger crew at higher levels); material buildings buildable by every player once upgrades arrive

**2026-10-02 (company size and Company Tax planned):**
- New 5.9.1: Company Tax on profit at a rate set by company size (Startup 10% → Conglomerate 30%, placeholders); size = assets + last 30 days of sales, checked continuously, never goes down; worked out at each sale, collected every 12 h with the water bill; no minimum tax yet. Replaces the 0/8/15/22% sales brackets once built
- New 5.9.2: future ideas kept apart from size: administration overhead, a credit rating (with loans) and player-to-player reputation (multiplayer contracts)
- Warehouse room raised from 2,000 to 10,000 goods per warehouse (5.10)

**2026-10-02 (cost per unit planned):**
- New 5.14 Cost per unit: running costs only (ingredients at their cost tag, your wages incl. bonus, metered water, later electricity) per batch ÷ units, with warehouse cost tags (averaged when mixed) and a worked wheat → flour → bread example ($0.30 / $0.75 / $1.83)
- 5.12 clarified: its formula is the designer's **selling** price on standard numbers, with the building share as profit margin; resolves the 5.11 vs 5.12 disagreement. Based on research into Sim Companies (report in `C:\Program Files\Project_AI\MYSIMS\reports\`)

**2026-10-02 (Dock planned):**
- New planned building, the Dock (5.11): stores goods like a warehouse, fixed workers, one at first; exports through direct contracts (no 3% market fee) and imports any goods; prices follow the cost per unit. Ships, coast placement and unlock parked (Section 11). Not built
- Export contracts pay sales tax (all sales are taxable), counted in the same 24-hour total as Retailer sales; cost per unit = running costs (ingredients, wages, electricity, later maybe water), not the construction cost
- The 3% market fee counts as the Market's sales tax (fee only, no bracket tax on top)
- The Dock's purpose is getting players to deal with each other: export contracts pay a flat contract tax below 3% (placeholder 1.5%) instead of the brackets, so direct deals are always the cheapest way to sell
- Contract prices get a floor and a cap (unrealistic prices refused) so contracts can't move money between a player's own accounts; limits TBD

**2026-10-02 (whole workers, hiring by wage bonus):**
- Workers are whole people tied to their building (`hired` per building), replacing the even share; full or idle buildings keep them, unpaid (5.6)
- Fixed minimum wage per worker type + a wage bonus per building (None / +20% / +40% / +60%); free people take the open post with the biggest bonus, equal bonuses take turns; fewer people: smallest bonus loses first
- Save version 3 (older saves get their workers handed out by the new rules)
- Warehouses are always staffed first and lose workers last (`staffed_first`), so their room doesn't shrink when other buildings pay bonuses
- Warehouses have no wage bonus: always the minimum wage (`fixed_wage`)

**2026-10-02 (warehouse: fixed workers, stored goods):**
- Warehouses have a fixed number of workers (4), with no Low/Medium/High choice; Level 2 (Phase 2 upgrades) will double them (5.10)
- The warehouse window shows every stored item with its icon and amount

**2026-10-02 (warehouse buildings, suspend):**
- The warehouse is a real building (5.10): pre-built starter, more for $3,000, 4 workers who make its room; one shared stock; Warehouse card in the bottom menu now opens the stock list. `warehouse_cap` in `game_config.json` is gone
- Suspend / Resume (5.10): progress lost, goods to the warehouse, no workers or wages, free resume
- Save version 2 (older saves get the starter warehouse). Selling moves to a separate Retail building later

**2026-10-02 (wages only while producing):**
- Idle Mills/Bakeries (no jobs queued) now pay no wages and free their workers, like halted ones; power will follow the same rule (5.5.1, 5.6)
- Fixed the building window calling a halted building "short of workers"

**2026-10-02 (save and load):**
- The game now saves and loads (Section 8): versioned JSON in `user://`, autosave, safe writing with a backup, damaged-save recovery
- Welcome back window (the Offline Summary, Section 6) and Settings → Start over

**2026-10-02 (taxes, costs, halt):**
- Built the progressive daily-sales tax (5.9): 0/8/15/22% brackets on the last 24 h of Retailer sales; replaced the building-count proposal
- Raised build costs: Wheat Farm $2,000, Flour Mill $5,000, Bakery $8,000
- Buildings with full storage halt: no production, no wages, workers freed

**2026-10-02 (electricity plan):**
- Rewrote 5.5 with the electricity design: power as a flow with one speed rule (workers × power), plant roster (Thermal, Wind, Solar, Nuclear, Hydro idea) with placeholder numbers, automatic public grid with connection sizes and a changing price, 12-hour game day, offline rule, build order
- Dropped two earlier rules: power "consumed per job start" and "self-sufficient, can't buy power"

**2026-10-01 (Blender art pipeline):**
- Building art is now modelled in Blender from Python scripts (`art/blender/`), replacing "use free kits, no Blender" (Section 4). Style: more detailed, closer to Clash of Clans. Footprints for the pack: 2×2
- First model: Wheat Farm. The sprite studio can now read a building's model from its own folder (`kit_folder` per entry)

**2026-10-01 (HUD, building interaction, settings):**
- Clash-of-Clans-style HUD, building selection/action bar/info panel, Settings window, and a shared UI theme with SVG art (see Section 6)
- New game rule `can_enqueue` (read-only check shared by the UI and `enqueue`, like `can_build`), with tests; buildings got a `description` in `data/buildings.json`
- The temporary test panel is down to Sell buttons and Skip-time until the Retailer screen exists

**2026-10-01 (camera framing):**
- Starting view fits the whole island including cliffs, and re-frames when the window settles to its real size (the editor's stretched game panel, phones); zoom-out is capped at the whole-island view and panning stays within the island

**2026-10-01 (visual step 2, first part — sprite studio):**
- Built the sprite studio (`tools/sprite_studio.gd` + `tools/sprite_studio.json`); buildings now show studio pictures from `assets/buildings/`, falling back to the placeholder box if a building has none
- Temporary building art from Kenney City Kit (Commercial), kept in `Sprites kit/` (ignored by Godot via `.gdignore`, excluded from the Android export along with `tools/`)
- Textures now import with mipmaps by default (`project.godot` importer defaults), so detailed sprites don't shimmer when zoomed out

**2026-10-01 (art direction + visual step 1):**
- Decided the art pipeline (Section 4): 3D models rendered into 2D sprites by a Godot "photo studio" tool, free CC0 low-poly models first; added look rules and a 4-step visual roadmap
- Visual step 1 done: shader-painted island (smooth coast, cliffs, beaches, animated water and foam), placeholder trees, soft shadows, y-sorted buildings/trees, grid only in Placement Mode; the hover highlight now only shows in Placement Mode
- New island settings in `game_config.json`: `beaches`, `tree_density`

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
