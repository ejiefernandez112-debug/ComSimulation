# Project Plan: Island Village Builder (production chains + player market)

_Last updated: 2026-10-05 (production chains in waves, §5.21; Trading Post, §5.22; earlier: pitch rewritten as a village builder, 2026-10-04; see Section 15)_

## 1. Pitch

**A cozy island village builder: grow a town from a handful of founders by building farms, mills and bakeries. Keep your people fed, housed and employed, and trade what you make with other players.**

- **Anno** and **SimCity BuildIt**: production chains (wheat → flour → bread) whose goods keep a growing town alive and happy
- **Tropico**: population, needs, jobs and education
- **Clash of Clans**: the look. Isometric village view, building-level production animations (e.g. a distillery bubbling). No combat, no troops
- **Sim Companies**: the shared, player-driven market where players set prices. **Anno Online** (browser MMO, closed 2018) is a precedent for player-to-player trading in an Anno-like game
- **TyconX: Business Tycoon Game**: the live player-driven stock market/exchange

**Selling point:** an Anno-style village combined with a Sim Companies-style live player market is a rare mix. (Changed 2026-10-04 from "MMO business simulation": the population systems made the village, not the company, the heart of the game. Who the player *is*, company owner or village founder, is still open; it affects names like Company Tax and company size, §5.9.1.)

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
	 - **Style confirmed 2026-10-05: "soft toy"** (smooth shading, rounded edges, no outlines). The user compared it side by side with a flat "vector" look (flat colour faces + dark outlines) and kept the soft one
	 - **Full building set, in 5 review batches** (2026-10-05). Each batch: models → studio → the user reviews a preview sheet. Production/civic buildings are designed 2×2, homes 1×1, and since 2026-10-06 they stand on that many tiles in the game too (Footprints, below)
		 - ✅ Batch A: Bakery, Grain Mill (`flour_mill`), City Hall, Construction Office, Public Housing, Warehouse
		 - Batch B: Makeshift Hut, Regular House, Villa, Water Treatment Plant, Supermarket, Trading Post (the last Kenney stand-ins go here)
		 - Batch C: Feed Mill, Ranch, Fishery, Apiary, Sugar Mill · Batch D: Oil Press, Food Factory, Confectionery, Beverage Plant, Cannery · Batch E: Dairy, Slaughterhouse, Meat Plant, Fish Plant
	 - ✅ **Footprints (built 2026-10-06, on trial).** Asked for because City Hall (designed 2×2, squeezed onto 1 tile) looked smaller than Public Housing. `"size": 2` in `buildings.json` = a 2×2 square: City Hall, Construction Office, Warehouse, Water Treatment Plant, every farm and food factory, Supermarket, Trading Post, Solar and Nuclear plants. 1×1: homes, Makeshift Hut, Wind Turbine, Electric Substation
		 - A building's `position` is its square's tile with the smallest x and y (its top corner on screen); nothing else may stand on any of its tiles, and it may not hang off the land
		 - Roads: a linked road on a tile beside any side of the square counts (§5.20). Power reach is measured from the building's middle (§5.5)
		 - The land grew from 20×20 to **26×26** (`grid_size`), with a new starting layout: one main street (row 13) with City Hall, the Warehouse and three homes above it, the Construction Office, two homes and the Substation below
		 - **The land grew again to 40×40** (2026-10-08, the user: "later on, as the village grows, it needs more space"; about 2.4× the room). The starting layout moved 7 tiles inward (main street on row 20). Old saves (version 16) move their whole village 7 tiles inward and nothing else changes (`SaveFormat._grow_plot`). Zooming out no longer shows the whole island (Village View, §6)
		 - Old saves (version 14): the land grows and the whole village moves 3 tiles inward to stay in the middle; then, oldest building first, a building that fits stays and the road tiles under it are removed and paid back (counted like a demolish refund); one that overlaps an older building moves to the nearest free spot; buildings left without a road get free road. The player sees a note listing what changed
		 - The sprite studio photographs each building at its `size` (no setting needed in `tools/sprite_studio.json`)
	 - Still to do: trees and rocks as sprites
  3. **The island itself** — 3D terrain built in the studio from the same coastline seed (flat plot in the middle, cliffs and beaches around it, mountain and forest at the back), baked once into a background picture cut into chunks for phones
  4. **Life** — bakery smoke, swaying trees, drifting cloud shadows, birds, boats. ✅ People walking and cars driving on the roads (2026-10-05, §5.20; simple shapes drawn in code for now)
	 - ✅ **Turning parts (built 2026-10-08, the user's request "the wind turbine and mill aren't spinning"):** the Wind Turbine's rotor turns (clockwise, one turn in 4 s) whenever it makes power; the Grain Mill's sails turn (anticlockwise like Dutch mills, one turn in 8 s) only while someone is working there (a batch, workers and power), so a standing mill shows at a glance. Under construction, switched off or idle they stand still in the normal picture
		 - How: the turning part is its own part in the Blender model, made with a pivot on its axle (`Parts.done(pivot=...)`, `art/blender/kit.py`). Its entry in `tools/sprite_studio.json` has a `"spin"` (part, frames, repeat_degrees, clockwise, seconds_per_turn); the studio then also makes `<id>_base.png` (the picture without the part) and `<id>_spin.png` (a sheet of the part at each angle, keeping only the pixels it changes: the part and its shadow on the building). `building_view.gd` shows the base with the sheet's pictures in turn on top; Build menu and placement keep the normal picture
		 - Cost: the turbine's 16 pictures and the mill's 12 add about 4 MB of video memory in all (shared by every turbine and mill); per frame, each turning building only picks a picture number (no work while standing still)
		 - Redo one or two buildings without re-photographing the rest: `... -s tools/sprite_studio.gd -- only wind_turbine flour_mill`
- **Audio** — ✅ interface and event sounds built 2026-10-07 (§5.24). Direction: realistic, modern, restrained. Ambience, building sounds and adaptive music are designed but not built (§5.24).

## 5. Game Mechanics

### 5.1 Core Production Loop
- Pattern: **Extractor** (no inputs) → **Processor A** (raw → intermediate) → **Processor B** (intermediate → final product)
- **Production batches (decided and built 2026-10-05, on trial; Sim Companies style).** They replaced the job queue, the building storage and the Farm growing on its own:
  - A Farm, Mill or Bakery runs **one batch at a time**, of as many **hours of work** as the player picks: **1 to 48 h** (`batch.max_hours` in `game_config.json`). Each recipe is **one hour of work** (`duration` 3600 in `buildings.json`), so a batch of 24 h is 24 × the recipe
  - **Choosing the length (few buttons):** the window offers `batch.default_hours` (24) or less if stock runs out. **− / +** move the finish time an hour at a time ("24 h · done Tue 6:00 PM"); **All** = as long as the ingredients in the Warehouse and the cash for the wages last
  - **Before starting, the window shows** what the batch makes and costs: units, ingredients (at their cost tags), labor, water (estimate), **total cost**, **cost per unit** and the selling price. **Start** asks once more with the whole breakdown
  - **Starting pays everything at once:** all the ingredients leave the Warehouse (with their cost tags) and **all the wages are paid now** (the full Level 1 crew for every hour, whatever the staffing). It needs the cash for the wages. So the batch's **cost and cost per unit are locked in**, and so is its **bonus** (§5.6)
  - **Hourly harvest:** every finished hour of work makes its **share of the batch** (units ÷ hours, rounded down so the shares add up exactly). The shares wait **in the batch** (no building storage any more) and a bubble floats over the building; tapping it collects them into the Warehouse. Several hours can pile up; collect any time. A full Warehouse takes what fits; the rest keeps waiting. The batch never pauses
  - **Fewer workers = the batch takes longer**, never costs more (speed = workers working ÷ Level 1's crew, as before). No workers: it waits
  - When every hour is made and collected, the building is **idle** until the next batch. One batch at a time: a finished batch must be collected before the next starts
  - **Cancel** (a running batch): the hours already made stay, to collect, at the batch's cost per unit; of the hours not made yet (work on the current hour is lost), `cancel_refund_in_progress` (**50%**) of their ingredients and wages comes back. Counted as money in ("Cancelled batches")
  - **A building with a batch can't be upgraded, suspended or demolished**: finish (or cancel) it and collect first
  - Older saves (version 8) hand everything in their queues and storage to the Warehouse when loaded (queued ingredients in full, a finished batch as its products)
  - Rules: `start_batch`, `batch_quote`, `batch_max_hours`, `cancel_batch`, `ready_units`, `collect` in `scripts/sim/simulation.gd`
- The **Warehouse** has its own overall cap: since 2026-10-02 it is the room of all Warehouse buildings together (§5.10)
- **Offline/idle production:** included from Phase 1a. Elapsed real time works out the finished hours of each batch on reopen, in one calculation
- **Design tension (2026-10-01, changed 2026-10-05):** the target offline window was ~1–2 hours (short timers and queues of 8). With batches of up to 48 h the game is now "check in a few times a day", like Sim Companies; production per hour was cut to a tenth so a 24 h batch fits the Warehouse (§5.4)
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

| Building | Type | One hour of work (the recipe) | A 24 h batch |
|---|---|---|---|
| Wheat Farm | Extractor (no ingredients) | → 60 Wheat | 1,440 Wheat |
| Flour Mill | Processor A | 40 Wheat → 32 Flour | 960 Wheat → 768 Flour |
| Bakery | Processor B | 20 Flour → 15 Bread (Final) | 480 Flour → 360 Bread |

_Changed 2026-10-05 for production batches (§5.1): every recipe is one hour of work, and output per hour was cut to a tenth of the old rates (600 Wheat / 320 Flour / 144 Bread an hour), so a 24 h batch fits a 10,000 Warehouse. Wages and water per hour stayed, so cost per unit and the cost-based prices went up about ×10, and profit per hour stayed about the same. Shop appetites were cut to a tenth too (§5.16). No building storage or queue any more. Live values are in `data/buildings.json`._

**Balance check (per building, running continuously, full staff, no bonus):**

| Building | Consumes | Produces |
|---|---|---|
| Wheat Farm | — | 60 Wheat/h |
| Flour Mill | 40 Wheat/h | 32 Flour/h |
| Bakery | 20 Flour/h | 15 Bread/h |

- One Wheat Farm can feed ~1.5 Flour Mills; one Flour Mill can feed ~1.6 Bakeries. With one of each, the Farm and Mill will pile up surplus — which is fine (it gives the player something to sell), but intentional.
- Overall conversion: **10 Wheat → 8 Flour → 6 Bread**, i.e. 1 Bread ≈ 1.67 Wheat. For processing to be worth it, the Retailer price of Bread must be comfortably above 1.67× the Wheat price *plus* a margin for the extra build cost and waiting time (same logic for Flour vs. Wheat: 1 Flour = 1.25 Wheat).

**Chain 2 — Dairy/Pastry (Phase 2, interconnected via shared Flour):**

| Building | Type | Recipe | Output |
|---|---|---|---|
| Dairy Farm | Extractor | (none) | Milk |
| Creamery | Processor | Milk → | Butter |
| Pastry Shop | Processor | Butter + Flour (from Chain 1) → | Pastries (Final) |

### 5.5 Industrial Category — Electricity & Employees (Phase 2/3)

> **Electricity design planned 2026-10-02; partly built 2026-10-05 (on trial), see 5.5.0.** All numbers are PLACEHOLDERS (in `data/*.json`). Scaled to the Phase 1a economy (buildings $2,000–$8,000, wages $15/worker/hour), not to Tropico's.

#### 5.5.0 What's built (2026-10-05, on trial)
The user asked for a Wind Turbine, a Solar Power Plant (High School graduates), a Nuclear Power Plant (uranium store, College graduates, greyed "soon") and an Electric Substation that expands grid coverage. Built Tropico-style, which **replaces** two rules below (proportional slowdown in 5.5.1, connection sizes in 5.5.3):
- **All or nothing:** a building that needs more MW than is left gets **none and doesn't work at all** (the user's rule: "needs 10, the town has 9 → it won't operate"). Power goes to buildings **oldest first**; one that doesn't fit is skipped, so a smaller newer one can still use what's left. Suspending a building frees its power
- **Who uses power:** Flour Mill 3 MW and Bakery 4 MW while making a batch (with workers); a lived-in home its `power_mw` (since 2026-10-07 a home without power counts 80% of its quality for the Housing need, §5.6). Farms, shops, warehouses: none
- **Coverage (Tropico-style radius):** ~~City Hall,~~ each plant and each Electric Substation cover a circle of `power_radius` tiles, measured from the building's middle (~~City Hall 5,~~ Wind Turbine 3, Substation 6 → 7/8/9 when upgraded; it stays on while upgraded). Circles that overlap join one network, ~~starting at City Hall~~ **starting at every power plant (since 2026-10-06)**; a substation joins only when its circle touches a plant's or another joined substation's. Buildings outside it get no power ("No power" sign); plants outside it add nothing. Placing a power building, or selecting one, shows the network's tiles in yellow and its own circle (green = joins, orange = doesn't)
- ~~**City Hall's grid link:**~~ **Removed 2026-10-06 (user's rule: City Hall is not a power source).** Power comes only from plants you build; a new village (and older saves) has **no power until a Wind Turbine is built** (the user chose this over a free turbine). The grid-link code and billing stay for data that sets `grid_mw`, but no building does. Before: the public grid adds up to **10 MW** (`grid_mw`) on top of your plants, at **$25/MWh**, metered and billed every 12 h like water (`game_config.json` → `power`). Own plants' power is used first and costs only their wages (a Wind Turbine has none: free)
- **Wind Turbine:** 5 MW steady (7 / 9 / 11 when upgraded), no workers, ~$6,000. Steady output for now; wind changes and day/night later (5.5.4)
- **Solar Power Plant** (8 MW, 4 High-skilled workers) and **Nuclear Power Plant** (300 MW, 20 Professionals, uranium store) are in the Build menu greyed out with a "coming soon" reason (`coming_soon`) until schools exist (5.7)
- **Cost per unit and prices** include power (MW × hours × the grid price), like water
- **Rules:** `Simulation.power_summary` / `_update_power` (run with hiring at every moment that can change it, so time away stays one calculation), `power_network`, `cover_all_with_power`; bills share the water code (`utility_meter`, `_bill_if_due`)
- **Save version 12:** older saves get a power meter and free Electric Substations so every building that uses power is inside the network; new games start with one Substation at [16, 11]

#### 5.5.1 How power works: a grid, not a stockpile
- **Electricity** is a utility, not a warehouse item: it can't be stored, carried or sold at the Retailer. It is a **flow**: plants **produce** a steady number of MW, working buildings **use** a steady number of MW
- **Supply order:** your own plants first, then the public grid (5.5.3) fills the gap, up to your connection size
- **Short of power:** if plants + grid connection can't cover demand, **every** powered building slows down by the same share (30 MW wanted, 24 MW available → all run at 80%)
- **One speed rule:** `speed = worker share × power share`. Electricity reuses the existing workers math (5.6), so offline catch-up, the speed display and the halt rule keep working
- **Power is only used while a building is producing**, the same rule as wages (decided 2026-10-02): halted buildings (storage full) and idle ones (no jobs queued) use **no power**. Use it in code through `Simulation.is_producing`, so wages and power can never disagree
- **Power use per building:** Flour Mill **3 MW**, Bakery **4 MW**, Wheat Farm **0 MW** (decided 2026-10-02: farms don't need electricity). The balanced 2 farm / 3 mill / 5 bakery chain needs **29 MW**
- **Homes use power too** (planned 2026-10-03, §5.18): an empty home 0 MW; a lived-in home its type's fixed MW (Public Housing 0.3, Regular House 0.5, Villa 1.0; Makeshift Huts none), paid by the player as the landlord
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
- **Population** grows automatically toward capacity, shown on the persistent HUD. **Houses only give room; they never add people by themselves.** A house's window shows its own residents ("4 of 10 living here · next in 2m"): people fill the oldest homes first (`Simulation.home_residents`, display only). Until 2026-10-03 it wrongly showed the whole village's population in every house, which looked like each new house added people. People move in one at a time: +1 every `population_growth_seconds`, **slowed from 10 s to 3 min on 2026-10-03** (a house used to fill in about a minute, which looked like "+10 people"; now it fills in 20–30 min, and births will matter too). The pace is still set by happiness; offline growth is calculated from `last_saved_at` like production
- **Workers & wages (built 2026-10-01, pulled forward from Phase 2/3):** each production building can employ up to `max_workers` (8 at level 1; Wheat Farm, Flour Mill, Bakery). The player picks its **Staffing** in the building window: **Low 4 / Medium 6 / High 8** (`staffing_levels` in `game_config.json`, as shares of `max_workers`; new buildings start at High). **Speed = workers actually working ÷ max_workers** (6 of 8 = 75%). *(The even-share rule, "10 people for 14 jobs = 71% each", was replaced on 2026-10-02 by whole, tied workers hired by bonus: see **Hiring & wage bonuses** below.)* **Worker types:** only **Low-skilled** can be hired now; High-skilled (high school graduates, e.g. engineers) and Professional (college graduates) are in the data with their wages but switched off until schools exist (§5.7). **Wages** (fixed PLACEHOLDERS, to move to the backend later): Low-skilled 15 / High-skilled 30 / Professional 60 per worker per hour, paid for every worker actually working, also while the game is closed. **Wages are only paid for work** (decided 2026-10-02; since 2026-10-05 a Farm, Mill or Bakery pays a batch's wages all at the start, §5.1): an idle building pays nothing; its workers stay tied to it and are back the moment it restarts (changed 2026-10-02, see below; before, they were freed). **Cash may go below 0 (debt)**: sales pay it back; nothing can be built while in debt; the HUD shows debt in red. Prices were raised (Flour 4, Bread 8) so each step still pays after wages. The Small House is buildable so players can grow the workforce. Offline catch-up stays one calculation: the time away is split only at the moments staffing changes (a person moves in, a building finishes, a building fills up or runs out of jobs) and each piece is worked out in one go; part-coins of wages carry over so many short settles cost the same as one long one
- **Hiring & wage bonuses (decided 2026-10-02):**
  - **Whole workers only.** Each building has a real headcount (`hired`, stored in the save), never a share like 4.3. Speed = workers working ÷ max_workers (3 of 8 = 37%)
  - **Workers are tied to their building.** Nobody moves on their own, and there's no job-hopping. A building only loses workers when the player decides: **lowers its staffing** (the extra workers are freed), **suspends** it or **demolishes** it (all freed; a resumed building queues again for workers)
  - **Idle buildings keep their workers** until their next batch
  - **Wages of a Farm, Mill or Bakery are paid per batch, all at the start (changed 2026-10-05, §5.1):** the full Level 1 crew × wage × the batch's hours. Warehouses and shops still pay their working workers by the hour
  - **Fixed minimum wage** per worker type, set by the game (`wage_per_hour` in `worker_types`: low-skilled $15, high-skilled $30, professional $60). Players can't pay less. Phase 4: the server could change it, like a law
  - **Wage bonus = more units per batch (changed 2026-10-05, on trial).** Chosen **per batch** in the batch set-up: **None / Small / Good / Big** pays **+0 / 20 / 40 / 60%** on the minimum wage (`wage_bonuses`) and the batch makes **+0 / 10 / 20 / 30% units** (`bonus_output`; PLACEHOLDERS). It's how a player gets more out of a building without more workers. **Locked in** once the batch starts: it can't change until the batch is done and collected. The window remembers the last choice. Cost per unit rises a little with a bonus (wages up more than units), but each batch makes more
  - **Warehouses are always staffed first** (decided 2026-10-02; `staffed_first` in `buildings.json`): they get free workers before every other building, and lose them last, so storage room never vanishes while people are free
  - **Who gets free workers** (new arrivals, or workers freed by the player), after the warehouses: they take turns one at a time, the emptiest building (fewest hired compared with what it asked for) first, then the older building. Open posts = what the staffing level asks for, at finished, non-suspended buildings. *(Until 2026-10-05 the biggest bonus got free workers first; the bonus now makes more units instead.)*
  - **Fewer people** (a house demolished): the unemployed leave first, then workers at the newest building (warehouses last)
  - **Warehouses get no bonus** (decided 2026-10-02; `fixed_wage` in `buildings.json`): they always pay the minimum wage, since they're staffed first anyway
  - Offline catch-up stays one calculation: each person moving in takes the best open post at that moment
- **Needs & happiness (planned and built 2026-10-03; Tropico-style 2026-10-07; simplified 2026-10-08, on trial):** one **village happiness** % that changes **births, migrant workers moving in and people leaving** (nobody works slower). All numbers are PLACEHOLDERS (the `happiness` block in `game_config.json`). **2026-10-08 simplification (the user: "I think it's too complex, let's make it simple"; research in `reports/Happiness systems in similar games.md`):** the 2026-10-07 Tropico version (5 wealth classes each weighing 7 needs, 42 weights; rising expectations with a 50% baseline; crime from the jobless and huts; job quality by wage bonus; 7 bands with children and hut workers leaving) was replaced by the rules below. Wealth classes still decide wages and who lives where (§5.18), just not happiness
  - **Happiness = the plain average of the needs that count**, each 0-100% for the whole village:

	| Need | Counts from | How it's scored |
	|---|---|---|
	| Food | the start | how many different foods are selling at a staffed store: 0 / 1 / 2 / 3 / 4 / 5+ → 0 / 40 / 60 / 75 / 90 / 100% (`needs.food.scores`; only category food counts) |
	| Jobs | the start | the share of adults with a job (a wage bonus doesn't change it) |
	| Housing | the start | how good each household's home is (`housing_quality` in buildings.json: hut 0, Public Housing 50%, Regular House 75%, Villa 100%), × 80% for a home that needs power and has none (`needs.housing.unpowered`) |
	| Health, Fun, Faith, Safety | 75 / 100 / 150 / 200 people | met by service buildings (§5.23: Clinic, Tavern, Chapel, Police Station): their places for everyone, at most all, × their quality |

  - **Needs switch on as the village grows** (`from_people`, counting children; like Anno's and Foundation's needs that come with rank): this replaced rising expectations. A small village only wants food, work and homes; at 75 people it also wants Health, and so on. When a need switches on unmet, the average drops, which is the growth pressure. Statistics says what's next ("Fun counts from 100 people")
  - **No food: at most 35%** (`needs.food.max_happiness_when_unmet`; 40% from 2026-10-08 until the simplification lowered it to stay under Content): while no food is selling, happiness is at most that, however well the other needs are met, so hunger always shows. `Simulation.happiness_cap`; "To raise it" counts lifting the limit in the gain of one more food
  - **Four moods** (`happiness.moods`, each `{from, name, births, move_in, leave_per_hour}`; the % shown is **rounded down**, so each mood starts at a whole shown number):

	| Happiness (shown) | Mood | Births | Migrant workers (only for open jobs) | Leaving (jobless adults only, share of all adults an hour, in groups of 5) |
	|---|---|---|---|---|
	| 0–14% | Angry | none | nobody comes | 5% |
	| 15–39% | Unhappy | half speed | come | 2% |
	| 40–69% | Content | normal | come | none |
	| 70–100% | Happy | ×1.5 | come | none |

  - **Why these edges:** a new game (50 adults, 8 working, unpowered Public Housing, no food) scores Food 0, Jobs 16%, Housing 40% → about 19%, so it starts **Unhappy, not Angry** (with the first proposal's 25/50/75 edges it would have started Angry: no babies, people leaving from minute one). One food → about 32%; Content (40%) needs food and about half the adults working. Left idle for 3 days it shrinks to its 8 workers and their children, exactly as before the simplification (checked 2026-10-08)
  - **People leaving:** in an Angry or Unhappy village **only the jobless adults leave** (`Simulation._leave_pool`), each hour, with part-people carried over like deaths so time away stays one calculation, in groups of `happiness.leave_group_size` (5). Once everyone left has a job, nobody leaves. **Workers never leave, even in huts, and children never leave because of happiness** (both special cases were dropped in the simplification). Counted as "Left the island" (`stats.people.moved_away`)
  - **Migrant workers come for jobs only** (`move_in_only_for_jobs`): nobody while Angry; from Unhappy up at the normal speed, and only the open jobs decide how many
  - **Shown** as a happiness % on the HUD next to Population (green / gold / red bar by birth speed). Tapping it opens Statistics → Happiness: **"52% content"** and bar, **"Average of 4 needs ⋅ Fun counts from 100 people"** (plus "no food selling: at most 35%" while it applies), births and newcomers, who is leaving, **"To raise it: Clinic for 120 more people +9% ⋅ 1 more food +6% ⋅ homes for 10 households in huts +4%"** (`Simulation.happiness_gains`, biggest gain first), then **Needs** (each need with its reason; a need that doesn't count yet shows "counts from 100 people"). A service building's window shows "Serves 75 people ⋅ Health 60%" (or "Health counts from 75 people")
  - **Offline stays one calculation:** happiness changes instantly (no slow "mood"), and only at moments settling already splits on: people arriving, born, dying, leaving or growing up (which is also when a need can switch on); a building finished, upgraded, staffed or suspended (and the power that goes with it); a shelf selling out; a player action
  - **Save:** happiness is worked out from the state, so it can't drift; the save only remembers the speeds in force (`population.growth_speed`, `population.move_in_speed`). The simplification stores nothing new: **no `SAVE_VERSION` bump**. Old developer locks on the hut penalty or on "what people expect" are left out (`OLD_DEV_LOCKS`); old tuning changes to removed settings (`happiness.growth_speeds...`, weights, expectations) no longer point anywhere and are ignored
  - **Not now (later ideas, see the research report):** a reward for a Happy village (e.g. better Retailer prices), timed "memories" with an end time (a shortage remembered for a few hours), festivals, luxury goods for the richer classes, overtime staffing; services that only reach homes nearby (a radius); a slow mood (rejected: it makes time away harder and hides the effect of a fix)
  - **Code:** `Simulation.happiness` (→ `{score, percent, mood, needs_met (the average before the cap), cap, needs (those that count), later ({need: people} for those that don't yet), people, foods, households, homeless, unpowered, home_quality, unpowered_loss, coverage, jobless, growth_speed, move_in_speed, leave_per_hour, dev_locks}`), `need_ids`, `need_name`, `need_from_people`, `_happiness_walk` (one walk over the buildings: home quality, service places), `home_quality`, `service_places`, `_average`, `_happiness_from`, `happiness_cap`, `happiness_percent`, `happiness_gains`, `_band_for` (the mood), `_leave_pool`, `foods_selling`, `_update_growth_speed` (read at the start of each settle piece). Tests: `test_happiness_is_plain_average`, `test_jobs_need_is_share_working`, `test_safety_is_police_coverage`, `test_workers_and_children_stay_when_angry`, `test_needs_switching_on_away_matches_playing`, `test_real_happiness_data`
- **Births, children & deaths (planned and built 2026-10-03, on trial):** Tropico grows its population by immigration, births and events, and simulates every citizen. We keep people as **group counts** (no per-person simulation) and add births, children and a steady death rate. All numbers are PLACEHOLDERS (a `life` block in `game_config.json`)
  - **Immigration was switched off (2026-10-03), then came back as migrant workers (decided and built 2026-10-04):** playtesting showed births alone were too slow: three farms stood without workers, which wasn't fun. Now newcomers are **migrant workers** (`move_in_only_for_jobs`): a **group of up to 5 adults** (`move_in_group_size`, since 2026-10-04; one adult before) every **2 minutes** (`population_growth_seconds` 120, times the happiness band's `move_in`), but **only while a job is open that no adult already here could take** and ~~only at 50% happiness or more~~ **only above 20% happiness** (since 2026-10-06). They **don't need a free home** (`move_in_needs_home` false, decided after a second playtest where full homes left 12 jobs open): with no room they live in **Makeshift Huts** (§5.18) until the player builds homes, which lowers the Housing need, so the player is still pushed to build homes and too many huts stop the migrants (under 50%) and make people leave, the homeless first. They stop by themselves when the jobs are filled, so the village can't run away; the 2-minute wait starts when a job opens. The open jobs are read at the start of each settle piece (a building finishing partway doesn't let several in at once), so time away stays the same as playing through. A boat at the Dock (§5.11) or an immigration campaign could still come later as extras
  - **Founders (decided 2026-10-03):** every new game (first start, or New game in Settings) starts with **50 adults** (`starting_population`) in **5 Small Houses**, never more than the starting homes hold; the Warehouse is staffed at once
  - ~~**Grace period (decided 2026-10-03):**~~ **Replaced 2026-10-07 by rising expectations (above): a small village expects nothing, so it sits at 50% or more.** Before: needs didn't count in a new village's first **3 hours** (`happiness.grace_hours`), so 46 unemployed founders don't freeze births before the player builds jobs and a Supermarket. Saves from before have no start time, so no grace
  - **Two groups:** **adults** move in, work and have babies; **children** are born here, live in homes and eat, but don't work. Population = adults + children. Elderly / old age: a later idea
  - **Immigrants are adults.** Moving in works exactly as now (happiness sets the pace)
  - **Births:** babies per hour = **all** adults × `birth_rate_per_hour` (**0.1** since 2026-10-04, 10x the 0.01 before: 100 adults ≈ 10 an hour) × the speed from happiness (an unhappy village has fewer babies; below 20% none). Since 2026-10-04 a house isn't needed: adults in huts have babies too. Part-babies carry over (`birth_carry`), like part-cents of wages, so many short settles give the same as one long one
  - **Room:** since housing types (§5.18), room is counted in **households** of 2 adults + 2 children. A baby needs a free child place in a household (2 per family, house or hut alike); a job seeker needs room for an adult in a real home
  - **Growing up:** a child becomes an adult (a free worker, hired by the usual rules) `grow_up_hours` (**6** since 2026-10-04; 24 before) after birth. Births in the same game hour form one **age group** `{count, grows_up_at}`, so the save holds at most ~6 groups
  - **Grown-ups with no job leave (decided and built 2026-10-08, the user's choice; `life.grown_ups_leave_without_job`):** a child growing up stays only if a **job is waiting** for them: an open job that no jobless adult already here could take (`Simulation.jobs_waiting`, the same test migrant workers use). The others **leave the island to find work** at that moment, counted as "Left the island" (the settle report's `left_for_work` says which part; the message reads "N grown-up children left the island to find work"). Babies still need no house or job. Why: before, every grown-up child stayed jobless and needed a home, so births kept pulling happiness down to the 20% edge where births stop and the jobless leave, and back up again (rising expectations add to it: more people expect more). A real village (16 jobs, ~90 adults, no food) went round that loop for days (7,683 born, 6,420 left), showing 19–21% whatever the player did, and a new game left alone ended there too at about 104 people. With the rule, that village climbs steadily (to 65% without the no-food limit, to the 40% limit with it), its size set by its jobs. The Developer window's "Grow up now" follows the rule too, and the switch is in its tuning page
  - **Deaths: a steady rate (decided 2026-10-03).** Deaths per hour = people × `death_rate_per_hour` (0.005 = 0.5% an hour, an average life of ~200 hours ≈ 8 real days). **In proportion:** adults and children each die at that rate with their own part-person carry, so each group loses its share. A child is taken from the youngest age group; an adult like when a home is demolished: unemployed first, then workers at the smallest bonus. A dead worker's post opens and the usual hiring rules fill it. Deaths free home room, so babies and newcomers keep the village turning over. Rejected for now: **life stages** (child → adult → elderly → dies at a fixed age), because immigrants all arrive "the same age" and would die in waves; it may come back with elderly people and pensions
  - **Needs:** Food counts everyone (children eat: Supermarket demand = all people). Jobs = share of **adults** with a job. The "needs from 10 people" threshold counts everyone
  - **Fewer homes (a house demolished):** ~~unemployed adults leave first, then children, then workers~~ replaced by housing types (§5.18): nobody leaves; households without a home put up Makeshift Huts
  - **Offline stays one calculation:** births and deaths happen at predictable moments (their rates only change at moments settling already splits on), and growing up is a fixed timestamp, so settling also splits at each birth, death and `grows_up_at`, like arrivals today
  - **Save (version 6, built):** `population.children: [{count, grows_up_at}]`, `population.life_carry` (`{born, adult_deaths, child_deaths, adult_leaves, child_leaves}`: part-people still to come), `started_at` (for the grace period), `stats.people`. The migration step makes everyone in an older save an adult, with no part-people and no grace. **Version 7** (housing types, §5.18): a save from before housing types (no Public Housing, Villa or hut) gets its Small Houses back as **Public Housing**, since they were free homes; otherwise its jobless households would be homeless the moment it loads
  - **Display:** the HUD stays "people / room"; Welcome back lists "+N moved in, +N born, +N grew up, −N died"
  - **Statistics by group (decided 2026-10-03):** Statistics → People gets a **Population by group** section:
	- **Groups now:** Adults (split into Employed / Unemployed) and Children, each with its count and share of the village (e.g. "Children 18 · 15%"), shown as one stacked bar
	- **Children by age:** one row per age group, e.g. "6 children grow up in 3 h 20 min", soonest first
	- **Comings and goings, last hour and all time:** moved in, born, grew up, died, and the net change ("+12 people this hour")
	- **Graphs:** the People graph gets lines for Adults, Children and Employed (the history points also record `adults` and `children`), plus a **Births** graph (born, died, grew up per hour, averaged over the hour before each point: they're rare events)
	- Counters live in `stats` (`stats.people: {moved_in, born, grew_up, died}`, all time), so they're saved and the last-hour numbers come from the history, like cash flow
	- New groups slot in later without a new screen: Elderly (old age) and education levels (§5.7: Uneducated / High School / College graduates)
  - **Why groups, not individuals:** simulating each person would mean rewriting hiring, saves and offline catch-up, and is heavy on phones and on a Phase 4 server. For Tropico flavour, tapping a house could later show **generated** named residents ("Maria, 34, Bakery worker"), made from a fixed seed and never stored
  - **Later ideas (not now):** schools take children (§5.7: children → graduates), elderly & old age, a Clinic / healthcare changing the death rate, special events (a player-paid festival or immigration campaign, or calendar immigration waves; never random dice), the named-residents view
  - **Code:** `Simulation.adults`, `children_count`, `children_groups`, `people_stats`, `people_flow`, `next_birth_at`; rates read at the start of each settle piece (`_life_rates`), the piece ends at the next birth, death or grow-up (`_next_life_event`), then `_settle_life` applies it; `_remove_children` for deaths (since housing types, demolished homes send nobody away, §5.18); `_hire` and `employment()` count adults. Screens: house window ("next baby in the village in …"), Statistics → People (Population by group, Children by age, Comings and goings), Graphs (Adults / Children lines, Births), Welcome back (Born / Grew up / Died)
- In **Phase 2/3**, once Employees exist, **Employment Matching** activates: Available = Population − Employed. Understaffed buildings run at reduced capacity/output rather than failing to hire outright.

### 5.7 Education System (Phase 3+)

- **Elementary School → High School → College**, unlocked progressively at higher player levels
- Each works exactly like a Processor: input is Population (or the prior tier's Graduates), timer, batch size, storage cap, queue
- Output is a distinct resource tier: Elementary Graduates → High School Graduates → College Graduates
- Advanced Industrial buildings require a minimum graduate tier for their Employees, not just headcount — segments the workforce by education level, incentivizing players to build Schools ahead of need
- **Needs clarifying:** whether Graduates remain part of Population (and of the Employment Matching formula) or are removed from it when they enroll — see Open Questions

### 5.8 City Hall, Construction Office & Starting Kit (Phase 1a)

- **City Hall** (renamed 2026-10-05; it was called the Construction Office) — the anchor building (Town-Hall equivalent): pre-built, can't be built or demolished, and every road starts here (§5.20). Idea for later: its own level caps other buildings' upgrade level, separate from the XP/Level system
- **Construction Office** (built 2026-10-05, on trial, §5.15) — a separate, buildable building whose workers are the construction workers. Building or upgrading anything (not roads) needs free ones, so at least one office is required; the last one can't be demolished
- **Starting kit (Phase 1a):**
  - City Hall — pre-built, already placed
  - Construction Office — pre-built beside the road, 4 construction workers
  - **5 Public Housing** buildings (Residential, §5.18) — pre-built, already placed, home to the **50 founding adults** (`starting_population`, decided 2026-10-03; before, 1 Small House and 0 people)
  - Warehouse — pre-built (added 2026-10-02, §5.10), room for 10,000 goods with its 4 workers
  - Starting cash — **$15,000** (`starting_cash` in `game_config.json`; raised from $5,750 on 2026-10-02 so a new player can afford the basic buildings, including their first Supermarket, §5.16, to $12,000 on 2026-10-04 so they still can when construction materials are at their highest price, §5.15, and to **$15,000** on 2026-10-05 because production batches pay their wages up front, §5.1; still tunable)
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

**Suspend** (building window → Suspend / Resume; any building with workers, except the Warehouse and the Construction Office: `"suspendable": false` in buildings.json, since 2026-10-06):
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

> **This is the SELLING price, not the player's cost** (clarified 2026-10-02). It is the designer's price, built from **standard numbers** in the data files (minimum wage, base water price, a standard crew), so a player's own choices never move it. What it actually cost *you* to make something is the **cost per unit** (§5.14): running costs only, no building share. Selling price − cost per unit − tax at the sale = your profit. (Same split as Sim Companies: research report `C:Program FilesProject_AIMYSIMSeportsSim Companies production cost.md`.)

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
- **Source: the government's public water supply**, piped in from outside the village. *(Since 2026-10-05 players can also build their own Water Treatment Plants, §5.13.1; the public supply covers whatever they don't.)*
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

#### 5.13.1 Water Treatment Plant: your own water (decided and built 2026-10-05, on trial)
The user asked for Water Treatment Plants. Their choices: the plant is your own water supply, its water costs its running costs, and spare water isn't sold ("most farms need water").

**What the plant does**
- **It is a flow, like the public supply.** A plant cleans `water_supply` m³ an hour when all its workers are working. Fewer workers clean less (2 of 4 = half).
- **Your buildings use its water first.** Only the rest is drawn from the public supply, metered and billed (12-hour cycle, tiers as above).
- **Spare water is lost.** Nothing is stored or sold.
- **It is a utility.** It has new category `utility`, a new Build menu tab **Utilities**, fixed workers and the minimum wage. Like a warehouse, its workers are paid by the hour and it is always working unless suspended. It closes while upgrading, and the public supply covers in the meantime.

**What its water costs**
- **Its own water costs only its wages.** At Level 1, 4 × $15 / 60 m³ = **$1.00 a m³**, against $2 public.
- **It pays only if the water gets used.** One Wheat Farm uses 30 m³/h, so with just one farm half the water is spare and the real cost is the same as public water. Two farms save about $60/h.
- **Batch cost per unit** estimates the water with the plants' spare water first at their price and the rest at the public price.
- **The farm's Water line** shows the blended cost.
- **Selling prices (§5.12)** still use the public base price, as the standard.

**Numbers** (all PLACEHOLDERS, in `buildings.json`)

| Level | Workers | m³/h | ≈ $ per m³ |
|---|---|---|---|
| 1 | 4 | 60 | 1.00 |
| 2 | 6 | 100 | 0.90 |
| 3 | 8 | 140 | 0.86 |
| 4 | 10 | 180 | 0.83 |

Materials: 600 Bricks, 60 Cement, 20 Steel and 30 Construction materials (about $2,900 with the crew).

**Shown:**
- the plant's window, e.g. "Cleaning 60 m³/h · your buildings use 30 · 30 spare", its price per m³ and "Water Cleaned";
- Statistics → Water bill → "Using now: X m³/h · Y from your plants, Z public".

**Later:**
- electricity for the plant (§5.5);
- a sprite (it shows as a placeholder for now).

### 5.14 Cost per unit (decided and built 2026-10-02)

**What it costs YOU to make one unit**, shown in each production building's window. It is a fact about your company, separate from the selling price (§5.12, the designer's price). Same approach as Sim Companies (research report in `C:\Program Files\Project_AI\MYSIMS\reports\Sim Companies production cost.md`).

**Cost per unit = (ingredients + wages + water + later electricity) for one batch ÷ units the batch makes**

**Since production batches (2026-10-05, §5.1)** the whole batch's cost is worked out and **locked in when it starts**: ingredients at their cost tags, the wages paid then (whole cents, bonus included), and water as an **estimate** (`water_per_hour` × hours × today's price; the real water still goes on the 12-hour bill). Every unit collected carries cost ÷ units. The set-up shows it before starting (units, ingredients, labor, water, total, cost per unit, sells for). The worked example below uses the old per-minute batches; with the new data a wheat costs about **$3.00**, a flour **$7.50**, a bread **$18.00** to make (standard numbers), about ×10 the old values, because output per hour was cut to a tenth (§5.4).

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

### 5.15 Building Upgrades & the Construction Company (planned 2026-10-02; upgrades to Level 4 with materials + a crew bought at market prices built 2026-10-04, on trial; real construction workers from the Construction Office built 2026-10-05, on trial; material buildings not built)

**Construction workers (built 2026-10-05, on trial; the user's choices).** The Construction Office is a real employer, separate from City Hall (§5.8):
- **Crew per job:** building anything needs **1 construction worker**; an upgrade needs **one more per level** (Level 2 → 2, Level 3 → 3, Level 4 → 4). The same for every building (`construction.crew` = 1, `crew_per_level` = 1). Roads need none
- **Busy until done:** the workers stay on the job until the building or upgrade is finished, then they're free for the next one
- **How many:** each Construction Office employs **4** villagers (Level 2: 6, Level 3: 8, Level 4: 10). They're real jobs, hired before other buildings (`staffed_first`, so the village can always build), and the office needs a road like any workplace. The total across all offices is the crew
- **Not enough free:** the job can't start yet. The message says how long until enough are free, or (when the job needs more than all offices have, e.g. Level 4 with one 4-worker office busy elsewhere) to upgrade the office or build another
- **Paid per project:** the Labor line of the quote is paid when the work starts; idle construction workers cost nothing, so the office has no hourly wage bill. ~~workers × hours × $15~~ **Since 2026-10-06: a share of the materials' value** (`construction.labor_share` = 10%, PLACEHOLDER; the user's idea, because a 10-second build would have made hourly pay almost free). It counts all the materials at today's prices, including those taken from the warehouse (they still need building with)
- **Stays open while upgraded,** like homes and warehouses
- Save version 11: the old headquarters (saved as `construction_office`) becomes `city_hall`, and older saves get a free Construction Office on the free tile nearest City Hall beside a linked road
- Not built: a waiting list that starts jobs by itself; real material buildings (below)

**Construction requirements (built 2026-10-04, the user's choices).** Building and every upgrade need **Bricks, Cement, Steel, Construction materials and labor**. The same rules apply to every building:
- **Fixed amounts per level, doubling each level.** Each building has its own Level 1 amounts (`materials` in `buildings.json`, sized so bigger buildings need more). Level 2 needs 2×, Level 3 4×, Level 4 8× (`construction.level_growth` = 2 in `game_config.json`)
- **Labor = a construction crew**: ~~8 laborers at Level 1, doubling each level~~ (replaced 2026-10-05 by real construction workers, above: 1, then one more per level). ~~Paid once at the low-skilled minimum wage ($15/h) for the hours the work takes~~ Paid once, **10% of the materials' value** (since 2026-10-06, above)
- **Construction time** (`construction.level_seconds`; building cut from 1 h to **10 seconds** on 2026-10-06, the user's choice; upgrades unchanged. Buildings already under construction keep their finish time):

| | Time | Crew |
|---|---|---|
| Build (Level 1) | 10 s | 1 |
| Upgrade to Level 2 | 1:00 h | 2 |
| Upgrade to Level 3 | 2:00 h | 3 |
| Upgrade to Level 4 | 3:00 h | 4 |

- **Materials are bought from an in-game supplier at today's market price** when the work starts, so the cost shown is approximate ("≈ $1,850"). Each material's price is its base price (Bricks $1, Cement $10 a bag, Steel $50 a beam, Construction materials $20 a crate) give or take up to 20%, a new price every hour. The price comes from the hour alone, so time away = playing and nothing is saved. ~~Once material buildings exist (below), materials will become real goods~~ They are real goods since 2026-10-06 (below). **Upgrades since 2026-10-06 (user's rule): never buy materials.** Every unit must already be in the warehouse, or the Upgrade button says what's missing and to buy it at the Trading Post or produce it; the money then pays only the crew. New buildings still buy what the warehouse lacks
- **Everything is paid at the start** (materials + crew), so work never stalls. The building's value on the balance sheet is what was actually paid (plus the cost tags of warehouse materials it used); its share in selling prices (§5.12) and the starting buildings use its value at base prices
- **Materials are warehouse goods, and demolishing gives them back (built 2026-10-06, the user's choices; on trial).** Bricks, Cement, Steel and Construction materials are items in `resources.json` (category `building_material`, with their base `price` and `unit`), brought forward from Wave 2 (§5.21):
  - **Warehouse first:** building and upgrading take the warehouse's own materials first and buy only the rest at today's price (`Simulation.construction_plan`). The Build menu and the Upgrade box say "400 Bricks (300 from your warehouse)"
  - **Each building remembers what it was built with** (`b.materials` units, `b.materials_cost` cents): every unit used for building it and every upgrade, at what it **really cost** (prices change every hour, so this is its own record, not today's price). The building window shows "Built with … (worth $X)"
  - **Demolishing gives no money** (`demolish_refund` is gone): every unit of material comes back to the warehouse with its cost tags, plus the goods inside. The crew's pay is what's lost. If the warehouse has no room for all of it, demolishing is refused ("Make room first"); nothing is ever thrown away
  - They take warehouse room like any goods, show in the Warehouse, and the Trading Post buys and sells them (§5.22)
  - Save version 15: buildings in older saves get their materials (their level, plus an upgrade under way) at base prices
- **Level 1 amounts** (PLACEHOLDERS; a Wheat Farm is about $1,820 at base prices):

| Building | Bricks | Cement | Steel | Constr. materials |
|---|---|---|---|---|
| Public Housing | 160 | 16 | 4 | 8 |
| Regular House | 200 | 20 | 5 | 10 |
| Villa | 1,200 | 120 | 30 | 60 |
| Warehouse | 600 | 60 | 15 | 30 |
| Wheat Farm | 400 | 40 | 10 | 20 |
| Flour Mill | 1,000 | 100 | 25 | 50 |
| Bakery | 1,600 | 160 | 40 | 80 |
| Supermarket | 500 | 50 | 13 | 25 |

- Starting cash raised to $12,000 so a Wheat Farm + Flour Mill + Supermarket is affordable even at the highest prices. A new building now takes an hour before it works
- **Robotic workers: coming soon.** Shown greyed out in every building's Upgrade section; what they do is still open (Section 11)

**How upgrades work** (built 2026-10-04, on trial):
- **Data:** each building's `upgrades` in `buildings.json` lists Level 2, 3 and 4: the numbers that change (`max_workers`, `storage_cap`, `queue_size`, `capacity`, `shelves`, `households`); anything a level leaves out stays as the level below. (Test data may still give a level a fixed `cost` and its own `time`)
- **Bigger building:** farms, mills and bakeries get +50% / +100% / +150% workers, storage and queue; Warehouse 2× / 3× / 4× workers and room; Supermarket ~~5 / 6 / 7~~ **2 / 3 / 4** shelves (since 2026-10-06); homes 1.5× / 2× / 2.5× households
- **Speed counts against Level 1's crew:** a farm with 12 of 8 workers works 1.5× as fast. Wages per batch stay the same (more workers, shorter batch), so the gain is more output per building, not cheaper goods
- **Closes while upgrading** (farms, mills, bakeries, Supermarkets): no posts, no wages, nothing made or sold; the batch in progress is paused, not lost, and queued jobs stay. This replaces the "after this batch / start now" choice above with something simpler. **Homes and warehouses stay in use**; their extra room counts from the moment the upgrade is done
- **No Construction Office cap yet**, and one upgrade at a time per building. Offline: the upgrade's end is a moment settling splits on, so time away = playing. Stored on the building as `upgrade_started_at` / `upgrade_done_at`; no save format change

**Upgrades cost materials + labor, not a money fee** (decided 2026-10-02; built above with an in-game supplier). Realistic: you buy the materials (from your own production, an in-game supplier, or from other players from Phase 4) and pay the laborers who build it. The rest of this section is the plan for later.

**Construction materials** (new goods, made by ordinary production buildings, priced by the cost-based formula, §5.12):

| Material | Made by | From |
|---|---|---|
| Wood | Lumber Camp (extractor) | Trees |
| Planks | Sawmill | Wood |
| Bricks | Brick Kiln | Clay (Clay Pit) |
| Cement | Cement Plant (uses power) | Limestone (Quarry) |
| Steel | Steel Mill (uses power) | Iron ore + Coal (Coal Mine, §5.5) |

- **Simple rule: the higher the level, the more materials and the bigger the crew** (decided 2026-10-02; settled 2026-10-04 as **doubling per level**, all four materials from Level 1, see above)
- **Material buildings are ordinary buildings every player can build**, but not yet: they arrive in a later phase with upgrades (not in the current early stage)
- Each level says what it improves (batch, timer, storage, workers; the Warehouse's Level 2 doubles its workers, §5.10)
- Still capped by the Construction Office's level (§5.8)

**The Construction Office is the construction company** (decided 2026-10-02):
- It has **laborers**, workers from the town's population
- Every **upgrade** needs some laborers for some time (e.g. 5 laborers for 6 hours). Laborers on a project are tied up until it's done, so the crew size limits how many projects run at once. A higher Construction Office level gives a bigger crew
- **Laborers are paid per project, not per hour:** the fee (laborers × wage × hours) is paid once when the project starts, so a project can never stall halfway. Idle laborers cost nothing. The fee goes to people in the game, so it's a **money sink**
- Materials are also taken from the warehouse when the project starts (like a job's ingredients)
- **New buildings** need materials and a crew too (decided 2026-10-04)

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
- **The player builds it** (not pre-built). About $2,270 of materials and crew (PLACEHOLDER, §5.15), so the $12,000 start covers a Wheat Farm + Flour Mill + Supermarket even at the highest material prices (§5.8)
- **Sells finished food only:** Flour and Bread, and since 2026-10-05 the Wave 1 foods (§5.21). **Raw Wheat can't be sold** (decided 2026-10-02): only items with an `appetite` in `resources.json` go on shelves, and only of a category in the store's `sells` list (the Supermarket: food; other store types later). The Trading Post buys anything (§5.22)
- **Shelves:** ~~4 per store~~ **1 at Level 1, one more per upgrade (2 / 3 / 4)** since 2026-10-06, the user's choice (`shelves`). Old saves (version 15): shelves past the new number are taken down as the game was saved (what sold is paid, the rest goes back to the warehouse). Each shelf sells one product; **several shelves sell at once**. **Each store sells on its own (changed 2026-10-04):** a product can be on only one shelf *per store*, but several stores can sell the same product at once. The village still has one appetite for it, so the stores **share its shoppers**: 2 stores selling flour each sell it half as fast, and total flour sold per hour stays the same (`Simulation.selling_counts`; only stores that are selling count: built, not suspended, with workers). When one sells out, the others speed up at that moment (a split point already). Before, a product could be on only one shelf in the whole village, which blocked a second Supermarket from selling flour at all. The same food in two stores still counts as one food for happiness
- **Putting food on a shelf:** choose the food, the amount (slider or All) and a **price tag**. The goods leave the warehouse at once (with their cost tags, §5.14); the window first shows the price, how many the village buys per hour, the time to sell out, sales, cost to make, sales tax and profit
- **Price tags** (our own idea instead of typing a price; `retail.price_tags` in `game_config.json`, PLACEHOLDERS from a demand curve speed = 1 ÷ price³):

| Tag | Price | Sells |
|---|---|---|
| Big Sale | −20% | 1.95× as fast |
| Sale | −10% | 1.37× |
| Normal | cost-based price (§5.12) | 1× |
| Premium | +10% | 0.75× |
| Luxury | +20% | 0.58× |

- **Village demand:** a shelf sells **people × the item's appetite × the tag's speed** per hour (appetite PLACEHOLDERS: Bread 0.36, Flour 0.32 per person per hour since 2026-10-05, a tenth of before like production (§5.4), tuned so ~40 people buy what one Farm + Mill + Bakery make; the game only shows village totals). The rate and price are fixed when the goods go on the shelf, so more people help the *next* shelf
- **Variety brings shoppers ("one-stop shop", our own idea):** +10% for each different product on the store's shelves beyond the first (`retail.variety_bonus`). It changes the moment a shelf sells out, so keeping shelves full keeps shoppers coming
- **Workers: a fixed 4 at the minimum wage** (decided 2026-10-02, like the warehouse: `fixed_workers`, `fixed_wage`): no Low / Medium / High and no bonus, because neither did anything worth having here (half the workers sell half as fast for the same total wages; a bonus only wins hiring priority). More only by upgrading later. **Not staffed first:** it waits its turn for free people; short of people, shelves sell slower (3 of 4 = 75%). Paid per hour **only while a shelf is selling**; empty shelves = idle, no wages. Electricity later (0 MW for now)
- **Paid at the end of each shelf batch** (decided 2026-10-02): when a shelf sells out, its sales minus sales tax (§5.9; Company Tax when that's built) reach cash. Taking a shelf down early (red X, asks first) pays for what's sold so far and returns the rest to the warehouse; demolish and suspend do the same
- **Offline:** exact, one calculation per stretch: settling splits time at each sell-out (the shoppers bonus changes then) and at worker changes. The Welcome back window lists what sold and what it earned; while playing, a message says "Sold out: 1,000 Bread. +$9,331"
- **Why demand limits volume (re-assessed 2026-10-02):** a price-only "demand meter" (±30%) was rejected: dumping goods at −30% still made a profit, and holding stock back to sell at +30% could be gamed. Here more goods simply take longer to sell, and lowering the price is the player's choice
- **More store types later** (decided 2026-10-02), each selling its own category, e.g. a **Hardware Store** for Planks, Bricks and Cement once construction materials exist
- Rules: `Simulation.can_stock_shelf`, `stock_shelf`, `can_clear_shelf`, `clear_shelf`, `stock_preview`, `_settle_retail`; window: `building_panel.gd` (Shelves + "Put on a shelf"). The Retailer's instant `sell` stays in the rules (tests use it) but no screen calls it

### 5.17 Plantation & Fruits (planned 2026-10-02; a single Plantation with generic Fruit built 2026-10-05, §5.21)

> **2026-10-05:** the Wheat Farm became the **Plantation**: one building that grows one crop at a time (wheat, corn, rice, soybeans, sugarcane, potatoes, vegetables, fruit, coffee and cocoa beans) and switches for a fee (§5.21). Fruit is one generic item for now; the island fruits below may replace it later.

- **Plantation**: an extractor like the Wheat Farm, where the **player chooses the crop** per building: **Banana, Mango, Lemon, Pineapple, Papaya, Coconut** (that's all for now). Each fruit has its own timer, batch and price in the data files
- **Fresh fruit is a finished product:** sold straight to customers at the Supermarket (§5.16) for local consumption. **Processing is optional, never forced** (decided 2026-10-02); unlike raw Wheat, fruit doesn't need a processor to earn money
- **Fruit vs. wheat is balanced by demand** (decided 2026-10-02): fruit needs one building to earn, wheat needs a Farm + Mill. If everyone grows fruit, fruit floods and Flour/Bread get scarce, so their prices and demand rise. Needs demand in the game: dynamic pricing (Section 11) and, from Phase 4, other companies buying
- **Processing ideas for later** (optional extra value, not needed to sell): Juice Factory (Mango/Pineapple juice, Lemonade), Banana Bread (a second Bakery recipe: Flour + Banana), Coconut Oil and Coconut Vinegar (Oil Mill / Vinegar Plant), Banana Chips (Banana + Coconut Oil), Dried Mango, Pickled Papaya (Papaya + Vinegar), Canned Pineapple (needs cans from Steel)

### 5.18 Housing types, households, wealth & rent (planned and built 2026-10-03, on trial)

Housing gets **types**, each with a name, a base build cost, a number of households, the wealth class it's for, a rent per household and a power use. Inspired by Tropico's housing, kept as group counts (no per-person simulation, like §5.6). All numbers are PLACEHOLDERS (in `buildings.json` when built). More types later: apartments, condos and so on.

- **Household:** up to **2 adults + 2 children** (decided 2026-10-03). Homes give room in **households**, not people. A household needs at least one adult; babies need a free child place in a household
- **Wealth classes** (decided 2026-10-03: from the **wage**, like Tropico). A household's class comes from its best-paid adult; children share their household's class:

  | Class | Who |
  |---|---|
  | Broke | no job |
  | Poor | minimum wage ($15/h) |
  | Well off | with a wage bonus ($18–29/h) |
  | Rich | $30–59/h (high-skilled, after schools §5.7) |
  | Filthy rich | $60+/h (professionals) |

  Today every worker is low-skilled, so only Broke, Poor and Well off can exist. A wage bonus only counts while a batch is being made with it: workers at an idle Farm, Mill or Bakery count at the minimum wage, and their job's quality (the Jobs need) at no bonus, whatever bonus is chosen for the next batch (`Simulation.bonus_earned_now`, fixed 2026-10-08)
- **Housing quality (2026-10-07, for the Housing need, §5.6):** each type has a `housing_quality`: Makeshift Hut 0, Public Housing 50%, Regular House 75%, Villa 100%; a home that needs power and has none counts 80% of it
- **Housing types** (decided 2026-10-03; 4 types):

  | # | Type | Build cost | Households | For | Rent per household | Power while lived in |
  |---|---|---|---|---|---|---|
  | 0 | **Makeshift Hut** | free (appears by itself) | 1 | Homeless: anyone without a home | none | 0 MW |
  | 1 | **Public Housing** | $800 | 6 | Broke, Poor | free | 0.3 MW |
  | 2 | **Regular House** (today's Small House) | $1,000 | 6 | Poor, Well off | $1 / hour | 0.5 MW |
  | 3 | **Villa** | $6,000 | 2 | Rich, Filthy rich | $15 / hour | 1.0 MW |

- **Who lives where:** each household takes the best home it can afford (rent ≤ 30% of its wages, `housing.rent_share`), richest households first; Broke households only fit Public Housing. Rich households fill Villas first; when Villas are full they may take a leftover Regular House (the fallback below). With no room anywhere, a household becomes **homeless** and a Makeshift Hut appears for it. Worked out from the counts each time (like `home_residents` today), so nothing can drift. A household that loses its job (Broke) moves out of a Regular House at the next settle
- **Makeshift Huts** (decided 2026-10-03: they **appear by themselves**, Tropico-style): on the nearest free grass tile to the village centre, in a fixed order (no dice); 1 household each, free, no power. They lower happiness (a future Housing need). A hut disappears when its household gets a real home, or the player demolishes it. Appearing is a predictable moment, so time away stays one calculation
- **Rent** (decided 2026-10-03: **the player receives it**, as the landlord): a fixed amount per household living there, paid continuously like wages (also while away), counted under money in as "Rent". Public Housing earns nothing
- **Power** (decided 2026-10-03): an **empty home uses no power**; a home with anyone living in it uses its type's **fixed MW**, full or not. Counted in the village demand once electricity exists (§5.5); the player (the landlord) pays for it, Public Housing included
- **Starting kit** (decided 2026-10-03): the 50 founders (25 households) live in **Public Housing**: 5 buildings = 30 households, replacing today's 5 Small Houses (§5.8)
- **Later:** apartments, condos and more types; a Housing need in happiness (§5.6); housing upgrades (§5.15)
- **✅ Built 2026-10-03 — what the rules do, including choices made while building:**
  - **Fallback:** households first take homes *meant* for their class; any still without a home then take any leftover home they can afford, so a Well off household lives in Public Housing rather than on the street, but Broke and Poor households get first claim on it
  - **Babies need child places:** 2 per household, **house or hut alike** (since 2026-10-04; before that only households with a real home had them). Child places come from adults, not homes. This replaces the old "no room in homes → no births" rule
  - **Nobody leaves any more:** demolishing a home makes its households move to other homes or put up huts (the old "people over the room move away" rule is gone)
  - **Huts can't be demolished** (they'd only go up again): they go by themselves once their household has a home. They take a tile, so a build on a tile where a hut just went up is refused ("That spot is taken")
  - **Rent** is collected like wages (also while away), shown as "Rent" under money in (Statistics → Cash flow) and in the Welcome back window
  - **Power** is only counted for now (Statistics → People → Housing: "Homes' power use … once electricity exists")
  - **Developer option** (F12 → Developer → "Rent per household"): −$1 / +$1 / +$10 / Reset for each home type; the change is kept in the save (`dev_rent`) until reset, marked with * in the window
  - **Screens:** house window ("4 of 6 households · 7 adults, 3 children · rent $4.00/h"), Build Menu ("6 households · for Broke, Poor · free · 0.3 MW when lived in"), Statistics → People: Housing (households per type, homeless, rent coming in, homes' power) and Households by wealth
  - **Sprites:** temporary Kenney stand-ins (Public Housing `building-e`, Villa `building-a`, Makeshift Hut `detail-awning`), like the other buildings
  - **Code:** `Simulation.housing()` (who lives where, worked out from the counts), `adults_by_class`, `wealth_class_of`, `rent_per_household`, `adult_room`, `_update_huts` (run after every hiring), `_collect_rent`, `dev_set_rent`. No save version change: huts are ordinary buildings, and `dev_rent` / `rent_carry` are optional

### 5.19 Balance sheet, cash check & money log (built 2026-10-04)
The player wanted a balance sheet (like Sim Companies') and to be sure **every cent of cash is tracked: where it came from and where it went**.
- **Every cash change is counted** under money in (sales by item, rent, demolish refunds) or money out (construction incl. upgrades, wages, water, sales tax). Developer-tool cash changes are counted separately (`stats.adjustments`), so they don't show up as income in the graphs.
- **Cash check** (Statistics → Cash flow): starting cash + all money in − all money out (± dev tools) = cash now, exact to the cent. The invariant test checks this after every step of every random game.
- **Balance sheet** (Statistics → Balance), all at what was paid (decided with the user):
  - **Owned:** cash; shop sales not paid yet (Supermarket goods sold but paid only when the shelf sells out or is taken down; after the sales tax they'll pay); goods per item at their cost tags (§5.14), wherever they are (warehouse, building storage, unsold on shelves); ingredients in queued batches; buildings at **price paid** (build + upgrades, no wear); buildings and upgrades still being built
  - **Owed:** debt (cash below $0); the water bill so far this cycle
  - **Company value** = owned − owed. **Starting capital** = starting cash + the starter buildings at their build cost (they were free, but count at list price). **Profit kept** = company value − starting capital
  - Demolishing shows as a loss of the half of the price that isn't refunded
- **Money log** (Statistics → Cash flow): money in and out per **30-minute block** (`money_log_minutes`), the last 24 hours (`money_log_size` 48), by source; the running block is shown live; time spent away = one block. Kept cheap on purpose (the user asked): it saves a copy of the running totals every 30 minutes, never one entry per payment.
- **Save version 8:** each building keeps `paid` (and `upgrade_paid` while an upgrade is under way), `stats.capital`, `stats.adjustments`, `stats.money_log`. Older saves get list prices and the starting cash that makes the cash check add up.
- **Not built (ideas):** a profit & loss statement (would need the cost of goods sold vs actual wages paid tracked as well), wear on buildings (depreciation), a CSV export.
- **Code:** `Simulation.balance_sheet`, `cash_check`, `money_log`, `_record_money_log`; `scenes/ui/money_pages.gd`

### 5.20 Roads & traffic (built 2026-10-05, on trial)
The user asked for roads, intersections, bridges, overpasses and flyovers, with people walking and cars driving ("or we copy Tropico"). They chose:
- **roads matter:** a building works only with a road;
- **traffic is for show:** no jams;
- **roads first, bridges later.**

All numbers are PLACEHOLDERS, in the `roads` block of `game_config.json`.

**Road tiles**
- A road goes on any free tile of the plot. It costs **$25 a tile** (`price`), paid at once and ready at once, with no crew and no waiting.
- Removing a road is free, and nothing is paid back.
- Buildings, Makeshift Huts and moved buildings can't stand on a road.
- Corners, T-junctions and crossroads appear by themselves, from each tile's road neighbours.

**The network**
- The network starts at **City Hall** (`"road_hub": true` in `buildings.json`; it was called the Construction Office until 2026-10-05).
- A road tile is **linked** when roads lead from it to a tile beside the office.

**Who needs a road**
- Every building with workers (`max_workers` > 0) needs a road, except the office. This includes farms, mills, bakeries, Supermarkets, warehouses and Water Treatment Plants.
- The road must be a linked road on a tile beside one of the building's sides (not diagonal): for a 1×1 one of its 4 neighbours, for a 2×2 one of the 8 tiles along its sides.
- **Without a road there are no posts:** no workers, no wages and no work, so the building stops, like a suspended one. A running batch waits.
- Homes and huts don't need roads yet (a later idea).
- A road (or a move) can't cut off a warehouse while the other warehouses don't have room for the goods.

**Time away stays one calculation**
- Road links only change when the player acts: building or removing road, or building, moving or demolishing a building. Every one of those actions settles first.
- The links are worked out again whenever workers are handed out (`_hire`), and each building keeps a `road` flag.

**New games and old saves**
- A new game starts with roads joining the office, the Warehouse and the houses (`starting_roads`). They count in the starting capital at their price.
- Save version 10: older saves get **free roads laid automatically**, the shortest way from each building, oldest first.
  - These roads are worth $0 on the balance sheet.
  - A building no road can reach shows "No road".

**Screens**
- **Road Mode:** Build → Roads → Road.
  - Drag from a tile to stretch a road, straight or with one corner. Green tiles are new road, faint tiles are already road, and red tiles are blocked.
  - The bar shows the tiles and the cost; ✓ builds it, and Road Mode stays on for the next stretch.
  - The blue/red switch changes between laying and removing road.
  - Two fingers still pan and zoom.
- **A building with no road:**
  - a red "no road" sign floats over it;
  - its window has a **No road** section that says why and points to Build → Roads (no automatic road: the player lays every road; the "Build road" button was removed 2026-10-05 at the user's request);
  - its status says why it stopped.
- **Placing a building** where no road reaches warns, but doesn't block.
- **Money screens:** roads show under money out ("Roads") and on the balance sheet ("Roads", at the price paid).

**Traffic (for show only)**
- Little people walk on the pavements and cars and vans drive on the right-hand lane, from road tile to road tile.
  - About 1 walker per 4 workers at work, at most 30.
  - About 1 car per working building plus 1 per 10 road tiles, at most 12. About half the cars drive to the Warehouse, like deliveries.
- They never slow anything down and are never saved, so randomness is fine here, and none of it is in the rules. There are half as many on the Low detail setting.

**Art** (clean isometric city-block look, from a reference picture the user chose, 2026-10-05)
- The roads are drawn in code for now: grey asphalt, a pale pavement on both sides and a dashed centre line.
- **Pedestrian crossings:** zebra stripes only at corners, T-junctions and crossroads, on each arm (the crossings in front of buildings were removed at the user's request).
- **Street lights:** a few lamp posts on the pavements (every 4th straight tile, alternating sides, and one at each junction; none on bends; reduced 2026-10-05 at the user's request). They stand in the y-sorted Objects layer, so people, cars and buildings pass in front of and behind them.
- **Building plots:** every building (not the Makeshift Huts) stands on its own little island, a lawn with a raised pavement edge and a few bushes. No road runs into a building (the driveway stubs were removed at the user's request). Placeholder boxes are a bit smaller than a tile, so the lawn shows around them.
- Later: 16 road pieces made in Blender and photographed by the sprite studio.

**Later ideas (not now)**
- **Bridges**, once there is water to cross: a river through the plot, or the Dock (§5.11). A road tile over water would be a bridge.
- Homes needing roads, so people can reach work.
- Distance mattering, so workers far away along the roads are slower (closer to Tropico).
- Road upgrades (dirt → asphalt).
- **Not planned:** overpasses and flyovers (they need height, which is hard in a flat 2D picture game on a 20×20 plot), and real traffic jams (they would need a car-by-car replay, which breaks the rule that time away is one calculation).

**Code**
- `scripts/sim/simulation.gd` "Roads": `road_quote`, `build_roads`, `can_remove_roads`, `remove_roads`, `linked_roads`, `_update_road_links`, `needs_road`, `on_road`, `road_path_for` + `lay_roads_to_all` (only for the old-save upgrade).
- Map and screens: `scenes/village/road_layer.gd` (drawing), `scenes/village/traffic.gd` (people and cars), Road Mode in `scenes/village/village.gd`.

### 5.21 Production chains, in waves (decided 2026-10-05; Wave 1 built, on trial)
The user asked to add about 150 items in 15 groups of chains (agriculture, livestock, forestry, metals, minerals, energy, chemicals, construction materials, food, textiles, furniture, electronics, cars, medicine, luxury goods), all connected, extending the existing systems. Reviewed together, they chose to build it **in waves, food first**, each wave playable and tested before the next:

| Wave | What | Status |
|---|---|---|
| **1A** | Plantation crops + plant foods: Grain Mill, Oil Press, Sugar Mill, Food Factory, Confectionery, Beverage Plant, Cannery | **built 2026-10-05, on trial** |
| **1B** | Animals and fish: Feed Mill, Ranch, Fishery, Apiary, Dairy, Slaughterhouse, Meat Plant, Fish Plant, canned fish | **built 2026-10-05, on trial** |
| **2** | Construction materials and coal power: clay, limestone, sand, gravel, stone, iron ore, coal, timber → bricks, cement, glass, concrete, steel, lumber; **your own materials used by construction** (warehouse first, the supplier for the rest; **built early 2026-10-06** for Bricks, Cement, Steel and Construction materials, which demolishing puts back in the warehouse, §5.15); a coal power plant that burns fuel by the batch (same power grid as today) | planned |
| **3** | Textiles (cotton, wool → yarn → fabric → clothing), leather (hides from Wave 1B), furniture, paper; new store types | planned |
| **4** | Oil and gas (gasoline, diesel, plastic, chemicals), fertilizer (+ phosphate, potash), electronics (copper, silicon, gold), rubber → tires → cars, medicine, jewelry and other luxury goods | planned; decide then: educated workers (schools, §5.7), whether fertilizer is a "boost" choice in the batch window |

**Trimmed on purpose** (the user's list, kept out unless asked; "not every chain needs all four stages"): raw sugar, juice concentrate, cocoa products, potato products and processed vegetables (one step instead of two), packaged eggs and honey, processed fish/seafood steps; tin, zinc, nickel, stainless steel, lead, lithium and batteries, bauxite/aluminium, gypsum/drywall, goats, diamonds, hydro power. Corn oil and soy oil are one item, **Cooking Oil**. Fruit is one generic item for now (the island fruits of §5.17 may replace it).

**Engine changes for Wave 1 (built 2026-10-05):**
- **Product choice.** A building with several recipes makes **one product**: its first batch chooses it, for free (`b.product`). The **Plantation** (the old Wheat Farm, same id), and later the Ranch and Fishery, can **switch** for a fee: `switch_fee` = 10% of the building's value, instant, only while it has no batch (the user's choice: "1 plantation, the player can switch it but there's a cost"). Factories keep their product **for good**: build another to make something else (the user's choice: "no switching"). The batch window shows the products as buttons with a note on what choosing means; the Start dialog warns when the choice is for good; switching asks with the fee. Old saves (version 12 → 13) keep what each building was making. Rules: `product_of`, `is_switchable`, `switch_fee`, `can_switch_product` / `switch_product`
- **By-products.** A recipe can make several things (soybeans → cooking oil **and** soy meal; later cattle → beef and hide). `cost_share` splits the batch's cost between them (soy: oil 60%, meal 40%), so a by-product isn't priced like the main product. Prices (§5.12), standard costs, cost tags (§5.14), cancelling and the balance sheet all use it; a batch locks in its `unit_cost` when it starts. Rules: `output_shares`, `batch_unit_cost`
- **Item categories and store types.** Every item has a `category` (food, crop, animal, ingredient, material; names in `game_config.json` `item_categories`). A store sells the categories in its `sells` list (Supermarket: food), so clothing or furniture stores can come as data in Wave 3
- **Food need rewards variety** (the user's choice): 0 / 1 / 2 / 3 / 4 / 5+ different foods selling = **0 / 40 / 60 / 75 / 90 / 100%** (`happiness.food_scores`; before: 2 foods = 100%). Only food counts. Statistics → People says what one more food would bring
- **Screens for many goods:** the Build menu's tabs scroll; the HUD shows a chip only for goods in stock; Statistics and the balance sheet list only goods in play; the shelf form lists only what the store sells, in a wrapping grid
- **Demand stays per item** (people × appetite), with smaller appetites for the new foods (one building's output feeds about 100 villagers, against about 40 for flour and bread). A shared food budget, where more kinds of food don't mean more eating, is an option if the money grows too fast
- **Icons:** one hand-drawn SVG per new item (same style as wheat/flour/bread). **Buildings** are placeholder boxes until their Blender models are made

**Wave 1A content** (all numbers PLACEHOLDERS, from the price formula §5.12; live in `data/*.json`):

| Building | One hour of work | Notes |
|---|---|---|
| **Plantation** (was Wheat Farm) | 60 Wheat / 60 Corn / 50 Rice / 40 Soybeans / 80 Sugarcane / 70 Potatoes / 50 Vegetables / 40 Fruit / 15 Coffee Beans / 15 Cocoa Beans | one crop at a time; switch fee 10% |
| **Grain Mill** (was Flour Mill) | 40 Wheat → 32 Flour · 40 Corn → 32 Cornmeal · 40 Rice → 30 Milled Rice | existing mills stay flour mills |
| **Oil Press** | 40 Soybeans → 8 Cooking Oil + 30 Soy Meal · 40 Corn → 8 Cooking Oil | soy meal feeds animals in 1B |
| **Sugar Mill** | 60 Sugarcane → 30 Sugar | |
| **Food Factory** | 30 Flour → 30 Pasta · 20 Cornmeal + 5 Sugar → 25 Cereal · 30 Milled Rice → 30 Packaged Rice · 30 Potatoes + 3 Oil → 30 Chips · 30 Vegetables + 3 Oil → 30 Packaged Food | |
| **Confectionery** | 15 Sugar → 30 Candy · 10 Cocoa Beans + 5 Sugar → 20 Chocolate | |
| **Beverage Plant** | 40 Fruit → 40 Juice · 20 Fruit + 10 Sugar → 60 Soft Drinks · 15 Coffee Beans → 15 Coffee | uses 20 m³ water/h |
| **Cannery** | 30 Fruit → 30 Canned Fruit | canned fish in 1B |

**Wave 1B content** (PLACEHOLDERS):

| Building | One hour of work | Notes |
|---|---|---|
| **Feed Mill** (Farming tab) | 40 Corn → 40 Animal Feed · 20 Soy Meal → 40 Animal Feed | soy meal from the Oil Press goes twice as far |
| **Ranch** | 40 Feed → 4 Cattle · 30 Feed → 6 Pigs · 20 Feed → 30 Chickens · 30 Feed → 60 Milk · 20 Feed → 60 Eggs | one kind of animal at a time; switch fee 10% |
| **Fishery** | 40 Fish · or 20 Shrimp | switch fee 10%; any tile for now |
| **Apiary** | 10 Honey + 2 Beeswax | by-product: the wax carries 15% of the cost |
| **Dairy** | 60 Milk → 10 Cheese · 60 Milk → 15 Butter · 40 Milk → 40 Yogurt | |
| **Slaughterhouse** | 4 Cattle → 40 Beef + 4 Hides · 6 Pigs → 60 Pork · 30 Chickens → 45 Chicken | hides carry 10% of the cost; sold to the trader until leather (Wave 3) |
| **Meat Plant** | 30 Beef → 30 Burgers · 30 Pork → 40 Sausages · 30 Chicken → 30 Chicken Nuggets | |
| **Fish Plant** | 40 Fish → 40 Frozen Fish · 20 Shrimp → 20 Packaged Seafood | |
| **Cannery** (+1) | 30 Fish → 30 Canned Fish | |

The animal chain is the interconnection the user asked for: Plantation (corn or soybeans) → Oil Press / Feed Mill → Ranch → Slaughterhouse → Meat Plant → Supermarket. Example prices: Animal Feed $16.47, Cattle $286.82, Beef $42.44, Hide $47.16, Burgers $73.71, Cheese $168.29.

Sold in Supermarkets (food): Potatoes, Vegetables, Fruit, Sugar, Pasta, Cereal, Packaged Rice, Chips, Packaged Food, Candy, Chocolate, Juice, Soft Drinks, Coffee, Canned Fruit, Milk, Eggs, Fish, Shrimp, Honey, Cheese, Butter, Yogurt, Beef, Pork, Chicken, Burgers, Sausages, Chicken Nuggets, Canned Fish, Frozen Fish, Packaged Seafood (plus Flour and Bread). Animals (Cattle, Pigs, Chickens), Animal Feed, Hides and Beeswax go into other buildings or to the trader.

**Tested end to end** with the real data (`tests/test_simulation.gd`, "Whole production chains"): Corn + Sugarcane → Cereal; Soybeans → Oil + Soy Meal, Potatoes + Oil → Chips (meal to the trader); Corn → Feed → Cattle → Beef + Hides → Burgers (hides to the trader); and Coffee Beans bought from the trader → Coffee. Each sells out in a Supermarket for more than it cost to make. Crops and ingredients (Corn, Rice, Soybeans, Sugarcane, Coffee/Cocoa Beans, Cornmeal, Milled Rice, Cooking Oil, Soy Meal) go into other buildings, or to the Trading Post (§5.22). Example prices: Wheat $5.98, Coffee Beans $23.92, Cooking Oil $75.77, Soy Meal $13.47, Pasta $57.03, Coffee $70.31.

**Open:** sprites for the new buildings; whether rice and coffee should need more water than wheat (water is per building now, not per crop); island geography (fishing on the coast, mines in the hills) is not a rule yet: any building goes on any tile.

### 5.22 Trading Post (built 2026-10-05, on trial)
Before it, nothing could be bought and only finished food could be sold, so a half-finished chain earned nothing and players couldn't specialise. The user chose a simple trader in its own building:
- **Trading Post** (Build → Shops): one per village (`max_count`), no workers (so no road needed), about $3,400 to build. Placeholder until the Dock (§5.11) takes over
- **Sell anything** (raw, half-made or finished) at **60%** of its normal price (§5.12), at once, no demand limit. Pays sales tax like any sale (§5.9) and counts as sales in Statistics
- **Buy anything** at **150%** of its normal price, needs the cash (no buying into debt) and room in the Warehouse. Bought goods carry what was paid as their cost tag (§5.14); counted as "Trading Post purchases" under money out
- Both shares in `game_config.json` `trade` (PLACEHOLDERS). The trader always pays less than it charges, so buying and selling back loses money
- Its window: Sell / Buy, a filter by kind (Food, Crops, …), the item, the amount (slider or All) and what it brings or costs before you commit
- Rules: `has_trading_post`, `trade_price`, `can_trade_sell` / `trade_sell`, `can_trade_buy` / `trade_buy`, `at_build_limit`; window `scenes/ui/trade_box.gd`
- **Later:** prices that move with what's been sold or bought (a sell glut lowers the price), daily limits, contracts with in-game buyers at the Dock (§5.11)

### 5.23 Services: Clinic, Tavern, Chapel, Police Station (built 2026-10-07, on trial)
Part of the happiness restructure (§5.6): Tropico meets Healthcare, Fun, Faith and Safety with service buildings, and the user asked for all four in this round. All numbers are PLACEHOLDERS (`buildings.json`, category `service`):

| Building | Size | Workers (L1 → L4) | Power | Need | People served (L1 → L4) | Quality |
|---|---|---|---|---|---|---|
| Clinic | 2×2 | 4 → 10 | 1 MW | Health | 100 → 250 | 100% |
| Tavern | 1×1 | 3 → 6 | 0.5 MW | Fun | 80 → 200 | 90% |
| Chapel | 1×1 | 2 → 5 | none | Faith | 120 → 300 | 100% |
| Police Station | 2×2 | 4 → 10 | 0.5 MW | Safety | 150 → 375 | 100% |

- **Capacity only, no radius (the user's choice):** each building serves up to `service_capacity` people **anywhere** in the village. The need = the places for everyone (at most all) × the places' quality, e.g. a Clinic for 100 in a village of 230 = Health 43%. A radius (only homes nearby) is a later idea
- **Workers:** fixed crews of low-skilled workers at the minimum wage (`fixed_workers`, `fixed_wage`), paid by the hour like a warehouse; fewer workers serve fewer (2 of 4 = half). Nobody is served while it's being built, suspended, without a road or without power. Doctors (high-skilled workers) come later with schools (§5.7)
- **The Chapel needs no power** on purpose: faith can be met before the first Wind Turbine
- **Upgrades** to Level 4 (more workers and people served); a service building **stays open while being upgraded** (like homes and warehouses)
- **Build menu:** a new **Services** tab (heart icon). Icons `health`, `fun`, `faith`, `safety`. No pictures yet: they show as plain boxes until an art batch
- **Rules:** `service_places`, `service_need`, `service_quality`, `service_building_for`; the needs in `Simulation.happiness`. Tests: `test_service_coverage`, `test_safety_is_police_coverage`, `test_service_away_matches_playing`, `test_real_service_buildings`

### 5.24 Sound (interface and event sounds built 2026-10-07; ambience and music designed, not built)
The user asked for a modern, realistic sound identity: things that could exist in the real world, restrained, nothing cartoonish or arcade-like, original (nothing borrowed from other games). Designed and reviewed on the Island Sound Board (a design canvas): 1 city soundscape, 2 interface and economic events, 3 adaptive music, 4 the audio system spec. Two review rounds; the user rejected anything tune-like, long or loud, so the rules are: one tone at most, real-world feedback first (latches, stamps, paper, relays), about half a second for confirmations and one second for events, quiet.
- **27 sounds**, all made by us (synthesised, nothing recorded or downloaded): `tools/sfx/sound_studio.html` holds the approved recipes; open it in Chrome or Edge to listen, and "Save all as WAV files" renders them into `assets/audio/sfx/` (44.1 kHz stereo, one shared loudness boost so their balance stays as approved). Open Godot afterwards so it imports them
- `data/sounds.json`: per sound its file, bus, `volume_db`, `pitch_jitter` (repeats don't sound identical), `min_gap` (a burst of sales is one sound) and what plays it. Loaded by `GameData.sounds`
- **Buses:** `UI` (taps, windows, confirmations) and `Alerts` (important events, warnings) both feed `SFX`, so the Sound switch in Settings silences them; made in code by the `Settings` autoload
- **`Sfx` autoload** (`scripts/autoload/sfx.gd`): `Sfx.play("collect")`. 8 voices; when all are busy the oldest is cut. Every button clicks by itself (tap, or toggle for chips, check boxes and switches). No per-frame work
- **What plays what:** windows and the Build menu open and close; a building selected; road built or removed; building placed or moved, upgrade started; batch started; goods collected, shelf stocked or cleared; Trading Post sale and purchase, shelves selling; refused actions (error); warnings (warehouse full, no road, not enough workers, people leaving). `scenes/main/sound_cues.gd` watches for things that happen by themselves: construction finished, upgrade finished, buildings short of power or cash below zero (critical), the sales tax rate changing. What happened while the game was closed stays quiet
- **Ready but not used yet** (their systems don't exist): milestone, large profit, major investment, trade agreement, growth, surplus, shortage, recession, market crash, bankruptcy. Demolish and Welcome back have no sound of their own yet
- **Designed, not built** (Sound Board boards 1, 3, 4): district ambience beds mixed by camera zoom (detail, not volume, rises as you zoom in), building sound families with "stopped" states, vehicles, construction stages, adaptive music that follows the village's state, day/night and weather layers, a 24-voice priority budget for phones. Engines, people, animals and machines will need real recordings from sources that allow commercial use (CC0), each logged with its licence

## 6. UI/UX Screens

**Phase 1 screens:**
- **Village View** — main isometric view, tap/click a building to interact, pan/zoom camera. Starts on City Hall, zoomed out as far as it goes (re-framed if the window changes size before the player moves). ~~Zooming out stopped at the whole-island view~~: since 2026-10-08 it stops at a fixed zoom (`ZOOM_MIN` 0.9 in `village_camera.gd`: a 2×2 building about 115 px wide on a 1280×720 screen, up from about 80; the user: "even if zoomed out, I want to see the building a bit bigger"), so the island is bigger than the screen and you pan to see the rest. A screen big enough for the whole island stops there instead. Panning stops at the island's edges
- **Build Menu + Placement Mode** — list of buildable buildings with cost, then place on the grid (needed in Phase 1a: the player's first action is building a Wheat Farm)
  - ✅ Redesigned 2026-10-01 (Tropico-style, tabs on the right): a window with category tabs down its right edge (the open tab joins the page), a title banner, a grid of building cards (picture + name; lock badge = not available, coin badge = can't afford yet), and a details strip (name, cost or "Need X more", description, what it makes, storage, Build button). Tap a card to see its details, tap it again or press Build to place it; on PC, pointing at a card previews it. Tabs are listed in `data/build_menu.json`; each building picks its tab with `menu_tab` in `buildings.json` (buildings with `buildable: false` show locked; tabs with nothing in them are hidden). Wide screens: a window in the middle (since 2026-10-06 below the HUD strip); tall screens: a bottom sheet. File: `scenes/ui/build_menu.gd`
  - ✅ **Rebuilt 2026-10-06 as the mockup's Build panel** (Harbor Glass UI kit, the user: "it doesn't look as what was created"): the categories are the **bottom build toolbar** (one button each, the open one blue; a thin line before Roads: `divider_before`), and picking one opens a wide frosted panel **just above the toolbar**, the map live around it (no dim). Header: the category's coloured square (`color` in build_menu.json), name, a line about it (`about`) and ✕. Left: building cards (picture, name, one line: **Materials ready** (green) / **Buy $X more** (amber: materials to buy) / **Need $X more** (red: cash) / Coming soon / Already built; lock badge), and a note "Materials come from your warehouse first; anything missing is bought at market price." Right: name with a **BUY $X** tag (materials to buy), description, what it makes, the **materials list** (amount, and *in stock* or *buy N* per material, the crew and how long), a note line, and **Place ⋅ $X** (the whole cost). Tall screens: a sheet, cards above the details
  - ~~**Placing:** picking a card that can be built puts its ghost on the map at once, ... info box beside the ghost ... Place / ✕~~ (replaced 2026-10-07)
  - **Placing (2026-10-07):** tapping a card only **chooses** it (on a computer, pointing at one previews it; moving across cards changes the details once per card, and the panel keeps **one size per category**, tall enough for its biggest building, so it never jumps or flickers). The details' button is **Build ⋅ $X** (the tag beside the name reads **MATERIALS $X**: the materials the warehouse doesn't have). **Build** closes the panel and puts the ghost on the map with the bar along the bottom (✕ / hint / ✓, like Move and Road Mode): the hint says why a spot can't be used or gives a heads-up (no road, no power); ✓ builds it there (the panel stays closed), ✕ / Esc / right-click goes **back to the panel** on the same card. The info box beside the ghost is gone
- **Building Panel** — current recipe, timer progress, job queue, collect button, upgrade button (upgrade button from Phase 2) — ✅ built, plus a **Workers** section: Low / Medium / High staffing buttons, workers working (of asked for, max), wages per hour, and the production rate at the current speed
  - ✅ Built 2026-10-01, Clash-of-Clans style: tapping a building selects it (bounce + glow + ring) and shows an action bar (Info / Collect / Produce / Build); tapping a building with goods waiting also collects; "ready" bubbles float over buildings; "+32"/"-40" numbers rise on collect/produce. Info opens the full panel (recipe, progress, queue slots, storage, Collect / Make). Files: `scenes/ui/building_bar.gd`, `building_panel.gd`
  - Industrial buildings (extractor/processor) skip the bar: tapping opens the panel straight away
  - **Production batch (built 2026-10-05, §5.1; replaced the queue slots, Fill, Make and the storage bar):** the Production box shows what one hour of work makes, then (`scenes/ui/batch_box.gd`):
	- **Idle:** Bonus buttons (None / +10% / +20% / +30% units), the length row `[−] 24 h · done Tue 6:00 PM [+] [All]`, and the lines Makes / Ingredients / Labor (paid now) / Water (estimate) / Total cost / Cost per unit / Sells for, then **Start 24 h batch** (greyed but tappable with the reason when it can't start). Start opens a "Start this batch?" window with the whole breakdown ("Back" / "Start")
	- **With a batch:** status ("Making Flour · 6 of 24 h · done at 6:00 PM"), progress bar, "Ready: 192 Flour" with **Collect**, what's locked in (hours, bonus, cost, cost per unit), and **Cancel batch** (asks first, showing the refund)
	- The action bar's Produce button (idle production buildings) opens the panel to set up a batch
  - **Demolish:** red button at the bottom of the panel, with a confirm window showing what comes back: ~~50% of the build cost (`demolish_refund`)~~ every unit of building material it was built with (since 2026-10-06, no money, §5.15) and goods inside. Only buildings the player can build can be demolished (starters stay). Refused while it has a batch, or if the warehouse can't hold what comes back
  - **Move:** blue button in the panel (or the action bar for the Construction Office / Small House). Uses Placement Mode: the building fades where it stands, a preview follows the pointer, tap a free tile. Free, works for every building, and production carries on through the move
- **Recipe Select** — sub-panel of Building Panel (once 2+ recipes unlocked)
- **Inventory/Warehouse** — all resources held, quantities, storage caps
- **Retailer/Sell Screen** — sellable resources, current NPC price, quantity selector, sell button
  - ✅ Built 2026-10-02 as the **Supermarket** window (§5.16): shelves with progress and a take-down X, then "Put on a shelf" (food, amount slider + All, five price tags, a preview of price / speed / time / profit). The temporary Sell test buttons are gone
- **Offline Summary** — "While you were away…" popup listing what was produced (and, from Phase 2/3, wages paid)
  - ✅ Built 2026-10-02 as **Welcome back!** (`scenes/ui/welcome_back.gd`): shows at start-up after at least `welcome_back_after_seconds` (120) away. Time away, goods made, people who moved in, wages paid, cash now, plus warnings for full (halted) buildings and debt
- **Settings** — sound/music volume, save reset, language (if localized)
- **Statistics** (✅ built 2026-10-01, "Stats" card in the bottom menu) — four tabs: **Production** (made / used / net per minute right now from working buildings, how many buildings are working / idle / full / being built, all-time made / sold / earned per item), **People** (population, employed, unemployed, open jobs, jobs per building type), **Cash flow** (last hour and all-time money in by source and out by category), **Graphs** (cash, cash flow, people, production over 15 min / 1 h / 6 h; rates are 10-minute averages; point at or drag across a graph for values). Counters and the graph history live in the save (`state.stats`, updated by the game rules); a graph point is added every `stats_sample_seconds` (60) and time away becomes one point, never a minute-by-minute replay. Keeps `stats_history_size` (360) points
  - ✅ Built 2026-10-01 (the "Menu" card in the bottom menu bar): Music, Sound effects, Building names, Water detail (High/Low, for slow phones), Full screen (PC), About, Quit (PC). Saved in `user://settings.json` by the `Settings` autoload, separate from the game save. **Start over** (2026-10-02, asks "Are you sure?" first) starts a new game. Still to add: language (if localized). Music/Sound switches mute the "Music"/"SFX" audio buses (Sound also silences the UI and Alerts buses that feed SFX, §5.24)
- **Quest Log** (Phase 1b) — active tutorial + daily/weekly quests, progress, claim-reward button
- **Profile** (Phase 1b) — XP/level, badges earned (Phase 4 adds rating)
- **Persistent HUD** — currency balance, XP bar, active quest progress (compact), Population (current/capacity) with village happiness % (planned, §5.6), notification icons
  - ✅ Phase 1a part built 2026-10-01: top-right resource bars (cash with count-up, workers needed / people — red when there are more jobs than people, tap or point at it for the breakdown incl. room in homes — and warehouse fill) plus a chip per item; short messages ("toasts") at the top. XP/quests arrive with Phase 1b. File: `scenes/ui/hud.gd`
  - ✅ Restyled 2026-10-06 ("UI look" below): one dark glass strip across the top-right corner (cash, people / room in homes, happiness % — tap it for the breakdown — and warehouse fill, each with an icon and a thin bar), the item chips in small glass boxes under it, and messages with an info or warning sign just below the strip. ~~Item chips~~ removed the same day to match the mockup (the Warehouse window lists every item)
  - ✅ **Bottom menu bar** (2026-10-01, Tropico-style), bottom centre: paper cards with an icon, clipped onto caramel folders (blue until the 2026-10-05 restyle) with the name underneath; pointing at a card lifts it. Cards: Build, Warehouse, Market, Menu (Settings). Market is greyed with a lock until that screen exists (tapping says "coming soon"); Warehouse opens the stock list since 2026-10-02. It slides away while a building's action bar, Placement Mode or the Build window is using the bottom of the screen. The card list is at the top of `scenes/ui/menu_bar.gd`
  - ✅ Restyled 2026-10-06 as a dark glass toolbar: a plain tile per screen (white line icon, name under it), no box until pointed at; Market dimmed with a small lock. It now also slides away while a window is open
  - ✅ **Split 2026-10-06 like the mockup:** the screens moved to a small frosted strip of icon buttons in the **top-left corner** (Menu ☰, Statistics, Warehouse, Market dimmed "coming soon"); the bottom toolbar holds the **build categories** (see Build Menu). Docked windows now start below the top-left strip. `scenes/ui/menu_bar.gd`
- **UI look** — ✅ **"Harbor Glass", a realistic city-builder look (2026-10-06, chosen by the user: "more realistic like Cities: Skylines 2, rather than cartoonish"; mockups on the "Harbor Glass UI Kit" page).** One theme for everything (`scenes/ui/ui_theme.gd`), drawn by Godot itself (no skin pictures): **dark slate glass** panels (~~93% opaque, no blur~~ since 2026-10-06 **frosted like the mockup**: 80% opaque with the map blurred behind (`UITheme.frost()`, a shader reading Godot's blurred copies of the screen); **Settings → Frosted glass** turns it off and the glass goes back to 93%; phones start with it off, as blur costs speed and battery) with a 1 px light rim, 4–6 px corners and a soft shadow; one **blue** highlight colour; green / amber / red only for good / warning / bad. Font **Overpass** Medium and Bold (`assets/fonts/`, SIL Open Font License, credited in Settings → About) with same-width digits, so changing numbers don't wobble. **Interface icons** are white line drawings (`assets/ui/icons/`, same file names as before, plus `alert`, `tab_farming`, `tab_food`); the goods icons are still the cartoon ones (to redraw later).
  - **Windows:** every pop-up window has the same title strip (title + close ✕) and fades in (`scenes/ui/modal_window.gd`). On wide screens (PC) they **dock along the left edge** so the map stays in view, with only a light dim; small questions ("Are you sure?", "Welcome back!") stay in the middle; tall screens get a bottom sheet. ~~The Build menu is a window in the middle, below the HUD~~ (since 2026-10-06 the Build panel sits above the bottom toolbar)
  - **Buttons: one shape, colour = meaning** — glass = normal action, blue (`GoButton`) = go / start / collect, red (`DangerButton`) = demolish / can't be undone, outline only (`BackButton`) = back or can't do it yet, no box (`IconButton`) = close ✕ and the toolbar; pick-one choices are outlined pills with the picked one blue (`ChipButton` / `ChipOnButton`). Three button sizes (small 40 / normal 46 / big 54 high) and five text styles (small 14, body 17, heading 19, big 23, title 21; white outlined text only over the map). Tile buttons (`RoundButton`: icon + caption) for the building card and the placing bar
  - **Over the map:** the screen buttons (top left), the HUD strip (top right), the build toolbar (bottom), and the building card (picture, name, status, progress, action tiles) when a building is tapped
  - Screens make their buttons, labels, icons and boxes with the shared builders in ui_theme.gd (`UITheme.button()`, `label()`, `wrapped()`, `icon_rect()`, `title_bar()`, `tag()`, `divider()`, `category_square()`, `frost()`). Between parts of a line use "⋅", not "·": Overpass draws its middle dot against the next word (all screens switched 2026-10-06), so a new screen matches automatically. `assets/ui/game_theme.tres` (for scenes laid out in the editor) is made from it by `tools/make_theme.gd`
  - ✅ **The look's numbers live in `data/ui_look.json` (2026-10-07)**: colours, shapes (corners, rims, padding, shadow), text sizes, button sizes, window and panel sizes, and icon swaps (`"icons": {"close": "check"}` draws one icon in another's place). The user edits them **in the game**: Developer window → **Look** (colour pickers and sliders; colours, shapes and text sizes change at once, button and window sizes and icons after **Rebuild windows**, which loads the screen again and reopens the page; **Save** writes the file when the game runs from Godot, elsewhere it copies the text; Copy as JSON; Undo changes). `tests/check_project.gd` checks the file against `UITheme.LOOK_KEYS`
  - Not built yet (shown as "New" on the mockup page): money per hour in the HUD, notice pins over buildings with a list under a bell (and the bell in the top-left strip), ~~build categories in the bottom toolbar~~ (built 2026-10-06), status tags on the building window, the building window's Batch / Workers / Upgrade tabs, steppers and switches
  - Before 2026-10-06: the "Honey & cream" cartoon theme (2026-10-05: cream paper windows, honey title ribbon, chunky SVG buttons, Fredoka font); replaced because the user wanted a realistic look

**Phase 4 additions:**
- **Market/Exchange** — live AMM-style buy/sell interface
- **Contract Board** — open player-posted offers + post-new-contract form
- **Leaderboard** — ranked by net worth/rating

**Architecture note:** Building Panel and Inventory/Sell screens should be built as overlay panels (Control nodes, responsive anchors) — a bottom-sheet on mobile, a side panel on PC/web, from one shared implementation. (✅ Since 2026-10-06 every window does this: `ModalWindow` docks on the left on wide screens and is a bottom sheet on tall ones.)

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
- Saved as-is today: `profile.currency`, `plot`, `next_building_id`, `buildings` (with `job_started_at`, `built_at`, `staffing`, and since version 9 `batch`: `{recipe_id, hours, bonus, units, cost, wages, inputs, input_cost, collected, made_hours}` or `{}`; the job `queue` and `blocked` are gone), `inventory`, `population` (with `children` age groups and `life_carry`, version 6), `started_at`, `settled_at`, `wage_carry`, `sales_log`, `stats` (with `people` counters; `capital`, `adjustments` and `money_log`, version 8), each building's `paid` / `upgrade_paid` (version 8), `roads` (`[x, y, cents paid]` per tile) and each building's `road` flag (version 10, §5.20). Not yet: xp/level, quests, badges (later phases)

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

#### 9.1.1 Performance check-up (built 2026-10-06)
**Measuring tools:** `tests/bench_performance.gd` (headless, see CLAUDE.md: times the rules and the real screens for a small village and a big one: a full 26×26 block (the whole plot until it grew to 40×40 on 2026-10-08; kept the same so the numbers stay comparable), 153 buildings, 251 road tiles, 800 people, 58 batches running) and the **performance overlay** in test builds (F11, or Developer window → Performance: fps and its limit, frame time, draw calls, nodes, how long the last tick took for the rules and for the screens, and switches that hide the island, trees, shadows, roads or traffic, so a phone shows what each costs to draw).

**Measured** on the development PC (Godot editor build; phones are slower), big village, before → after:

| | before | after |
|---|---|---|
| One tick, every second (rules + screens) | 54 ms | 14 ms |
| — of which the rules (settle) | 47 ms | 9.3 ms (small village 3.0 → 0.67 ms) |
| 24 h away (one catch-up at start-up) | 29 s | 6.7 s (small village 0.36 → 0.11 s) |
| Warehouse window open, per tick | 59 ms | 7.8 ms |
| Statistics → People open, per tick | 39 ms | 13.5 ms |
| Starting Placement Mode (finding a free spot) | 67 ms | 3.3 ms |
| A new hut's spot | 8 ms | 1.2 ms |

**What changed** (no rule changed: 24 h away and 300 ticks give byte-identical saves before and after, and the tests check the shortcuts against working things out afresh):
- `settle` works out who lives where, employment, happiness and the power once per step and hands them on (each was worked out up to 10 times); hiring works out each building's posts once; a tick hands its hiring on to the next one, which skips repeating it when nothing happened in between (`settle`'s `moment`).
- Spot searches (huts, Placement Mode, migration) use a plot map made once instead of checking every building and road for every tile; prices and standard costs are remembered (`data.cache`: data/*.json never changes while playing).
- Economy remembers heavy answers (housing, happiness, power, ...) until the next tick or player action (`_remember`); screens update their labels in place and re-colour text only when the colour changes (`UITheme.set_font_color`); traffic and roads re-read the map only when it changed (`Economy.layout_key`); icons and building pictures are looked up once; cars are redrawn only when they turn.

**After the happiness restructure (2026-10-07, §5.6, §5.23; the big village now also has a Clinic, Tavern, Chapel and Police Station):** `happiness()` 2.8 → 3.6 ms (its own part, without housing and employment, about 0.2 → 0.75 ms: seven needs per wealth class, one walk over the buildings), HUD numbers 3.3 → 4.1 ms, one tick 14.8 → 15.3 ms, Statistics → People open 13.5 → 13.9 ms, 24 h away 7.2 → 2.0 s (the village now settles differently). Small village: one tick's rules 0.68 → 0.79 ms. `test_invariants` is a little slower (2 games: 41 → 54 s), partly because it now checks happiness after every step.

**Laptop running hot (2026-10-08):** the frame-rate limiter (`scenes/main/frame_rate.gd`: about 60 pictures a second while playing, 30 after 10 s untouched) had been written but never added to the game, so Godot drew as fast as the screen refreshes. Measured fullscreen on the development laptop (2560×1440 at 165 Hz, Godot running on its RTX 3060), small village:

| | pictures a second | graphics chip busy | CPU (of the whole machine) |
|---|---|---|---|
| Before (no limit) | ~160 | ~33% | ~4–5% |
| — island hidden | ~160 | ~30% | same |
| — glass blur off | ~147 | ~29% | same |
| After: playing | 55 | ~12% | ~1.5% |
| After: 10 s untouched | 33 | ~7% | ~1% |

So the culprit was how many frames were drawn, not the island shader or the glass blur (hiding them saved little on this GPU; a phone may differ). Fixed: `main.gd` now adds the limiter, `Settings` has its `frame_rate` key ("smooth"; no Settings button yet), and it drops to **15 while the window is behind another app** on a computer (a click or key brings it straight back; the mouse just passing over doesn't). On a 165 Hz screen "60" becomes 55 and "30" becomes 33 so each picture stays up for a whole number of screen refreshes.

**Still open:**
- **Frame rate button in Settings** (Saver 30 / Smooth 60 / Max): the limiter already reads the `frame_rate` setting; the Settings window needs a row for it.
- **Long time away in a big village.** Every birth is its own step (about 1,500 a day at 800 people), so 24 h away still takes ~6.7 s on the PC, more on a phone. Options: a quick path for steps where only a baby was born (same rules), or babies arriving in small groups like people leaving (a small rule change).
- **Phone test with the overlay**: what the island shader costs (Island switch). If it's a lot, bake the land and cliffs into a picture once at start-up and let the shader paint only the water (an early part of Section 4, visual step 3).
- Opening the Warehouse window in a big village builds ~50 rows at once (~40 ms on the PC).

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

✅ **Pages, locks and live tuning (built 2026-10-06, the user's request "adjust happiness and its factors, and it should update the whole game"):** the window has tabs:
- **Money & time:** cash (as above); **skip 10 min / 1 h / 6 h / 24 h** (`TimeService.warp` + one tick, so it's the real time-away catch-up; replaces the temporary "Skip 10 min" button that sat on the map); rent per home type (2026-10-03); the performance overlay; **Reset all developer changes**
- **Happiness:** what happiness does right now (%, mood, the needs' average, babies, migrants, who leaves, each need and when the others start counting), and **locks**: the happiness % or one need (Food, Jobs, Housing, Health, Fun, Faith, Safety; the hut penalty lock went 2026-10-07, the "people expect" lock 2026-10-08) forced to a value in 1- or 10-point steps, or Off. Births, migrants, leaving, the HUD and Statistics all follow (`Simulation.dev_lock_happiness`, `dev_lock_keys`, `state.dev.locks`)
- **Tuning:** game_config.json's happiness numbers (the village size each need counts from, food scores, the no-food limit, the unpowered-home factor, leave group size, every mood's start / births / migrants / jobless leaving; simplified 2026-10-08), births, deaths, grow-up hours and migrant interval and group size, changed live with − / + (a band's start can't pass its neighbours; * = changed). The change goes into the save (`state.dev.config`, `{path: value}`) and Economy puts it onto `GameData.config` in memory (`GameData.apply_dev_config`), so the rules and every screen use it; the file is never written. **Copy as JSON** puts the changed blocks on the clipboard, to paste into `data/game_config.json` once a tuning is liked
- **People:** adults −10 / −1 / +1 / +10 (the jobless go first; not counted as moving in or away), children +1 / +10, children grow up now (~~end the new-village grace period~~: gone with the grace period, 2026-10-07)
- **Buildings & items:** finish all construction and upgrades now (construction workers freed); put 10 / 100 / 1000 of any item in the warehouse (as much as fits)
- Every tool goes through Economy and Simulation like a player action: the rules first catch up to now with the old numbers, so a change counts only from the moment it's made and time away still equals playing through (tested). Locks, tuning and rent are **kept in the save until Reset all** (no `SAVE_VERSION` bump: `state.dev` is optional); a red **DEV** tag shows at the top of the screen while any is on, and Statistics → People says "dev lock". A new game drops the tuning

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
- [x] Audio/music plan (sources, licensing, or commissioned): decided 2026-10-07, §5.24. Synthesised by us where it holds up (interface, alerts, wind, hum, music sketch); CC0 recordings for engines, people, animals and machines
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
- [x] Upgrades (5.15): do **new buildings** also need the construction company and materials, or only upgrades? → **Yes, new buildings too: materials + a crew of 8, 1 h** (decided 2026-10-04)
- [x] Upgrades (5.15): before Phase 4, where materials come from when your own chain is short → **an in-game supplier at a market price that moves ±20% every hour; materials are bought automatically when work starts** (decided 2026-10-04). Still open: whether an in-game contractor rents out laborers
- [ ] Upgrades (5.15): what **Robotic workers** do (shown as "coming soon"), what they cost, and from which level
- [ ] Upgrades (5.15): per-building crew sizes (every building uses 8 for now) and whether laborers become real villagers taken from their jobs
- [x] Upgrades (5.15): who can build the material buildings (Lumber Camp, Sawmill, Clay Pit, Brick Kiln, Quarry, Cement Plant, Steel Mill)? → **every player, from the later phase that brings upgrades**; not available in the early stage (decided 2026-10-02)
- [ ] Population growth rate tuning and House capacity numbers beyond the first Small House
- [x] Should people have needs? → **Yes: Food and Jobs, one village happiness score that only changes move-in speed** (decided and built 2026-10-03, 5.6; on trial). **Restructured Tropico-style 2026-10-07:** seven needs, per wealth class, quality levels, rising expectations, service buildings (5.6, 5.23). **Simplified 2026-10-08:** the plain average of the needs, needs switching on with village size, four moods
- [ ] Happiness (5.6): tune by playing: the village sizes the service needs switch on at, housing qualities, service capacities, the mood edges and speeds. Do huts still hurt enough?
- [ ] Happiness (5.6): should Jobs count only unemployed people, or also open posts nobody fills (too few people)?
- [x] Births and deaths → **yes: adults have babies (children grow up after 24 h), and a steady death rate takes adults and children in proportion; people stay group counts, not individuals** (decided 2026-10-03, 5.6; not built)
- [ ] Births & deaths (5.6): tune the birth rate (2% of adults an hour), death rate (0.5% an hour) and grow-up time (24 h) by playing
- [x] Births (5.6): people moved in every 10 s, far faster than babies are born. Should moving in slow down so births matter? → **Yes: 1 every 3 minutes at normal speed** (decided 2026-10-03, PLACEHOLDER). Check that the Supermarket's appetites (tuned for ~40 people) still feel right with slower growth
- [ ] Births & deaths (5.6): who leaves first when homes shrink (now: unemployed adults, then children, then workers)? Should a Clinic (built 2026-10-07, 5.23: today it only raises Health) or unhappiness change the death rate?
- [x] Starting population → **50 adults in 5 Small Houses; immigration off for now, the village grows through births; a 3-hour grace period for needs** (decided and built 2026-10-03, 5.6, 5.8)
- [x] Births (5.6): with 5 full starting houses no baby was born until the player built another house → **answered by housing types (5.18): babies need child places in households, so the founders have babies from the start**
- [ ] Housing (5.18): rent amounts and the affordability share (20%?); households, build costs and power per type
- [ ] Housing (5.18): where Makeshift Huts may appear, and do they block building there?
- [ ] Housing (5.18): does a household split when its children grow up (a new household needs a new home)?
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

**2026-10-08 (bigger buildings when zoomed out; land 40×40):**
- Tested on the Redmi Note 10 Pro (Android 13, Adreno 618, 120 Hz): 60 fps while touching, about 40% of one CPU core, 29 °C. Found: the Back gesture (a swipe in from the screen edge) closes the game at once (Godot's default; it saves first).
- The user asked for bigger buildings even when zoomed out, and more land for later. Zooming out now stops at a fixed zoom (a 2×2 building about 1.45× its old zoomed-out size) instead of the whole island, the map opens on City Hall, and the land grew from 26×26 to 40×40 (save version 16 moves old villages to the middle). §4 Footprints, §6 Village View

**2026-10-08 (happiness simplified):**
- The user asked for a deep look at how similar games do happiness (`reports/Happiness systems in similar games.md`: Anno 1800 and 117, Against the Storm, Timberborn, Civilization VI, Manor Lords, Foundation, RimWorld, Frostpunk, SimCity BuildIt and more), then said the current system was too complex and chose four simplifications: **one plain average, no class weights**; **needs that switch on as the village grows** instead of rising expectations; **Safety = police coverage** (no crime formula); **four named moods** (Angry, Unhappy, Content, Happy) instead of 7 bands, dropping "children leave" and "workers in huts leave". And **Jobs = the share of adults with a job** (wage bonuses no longer count)
- Mood edges set at 15 / 40 / 70% (not the 25 / 50 / 75 first shown) so a new game starts Unhappy, as before, not Angry; the no-food limit went from 40% to 35% so hunger stays below Content. An idle new game shrinks over 3 days exactly as before (same people numbers, checked against the old rules)
- Removed from game_config.json: `weights`, `class_weights`, `expectations`, `content_at`, `growth_speeds` (now `moods`, with `births` for `speed`), the Jobs `quality` list, the Safety crime numbers, `children_leave_per_hour`, `homeless_workers_leave`. No save change
- Seen while checking (not changed): an idle new game has no children for its first 2 days, under the old rules too

**2026-10-08 (happiness stuck at 19–21%; idle farms' wage bonus):**
- The user saw happiness stuck at 19–20%, even with no food selling. Their save showed a loop: at 20% or more babies come; 6 hours later they grow up jobless (16 jobs for ~90 adults), need homes and raise what people expect, so happiness falls below 20%; then births stop and the jobless leave until it's back. The village changed size instead of getting happier or sadder (7,683 born, 6,420 left). A new game left alone ends up the same way at about 104 people. Tried on a copy of the save first: slower births alone only move the stuck point
- The user's choices: **grown-up children with no job waiting leave the island to find work** (`life.grown_ups_leave_without_job`), and **no food selling holds happiness at 40% at most** (`happiness.needs.food.max_happiness_when_unmet`). "Food counts double" was chosen first, on the older rules, but in the 2026-10-07 needs it only moved a no-food village from 65% to 62%, so the user picked the limit instead. On the copy of their save with no player actions, happiness now climbs from 21% to the 40% limit in a day and holds; the village shrinks to its 16 workers. A new game is 40% until food sells (5.6)
- Bug fix: a Farm, Mill or Bakery with no batch being made counted its workers at the bonus chosen for the next batch: an idle farm with "Big" made its workers Well off (better homes) and gave them a 100% job in the Jobs need. Both now use the bonus paid now (`Simulation.bonus_earned_now`): none while idle (5.18)

**2026-10-07 (Sound: interface and event sounds):**
- The user asked for game sounds. First round (cozy marimba vs arcade blips) was replaced by their directive: realistic, modern, restrained. Designed on the Island Sound Board (soundscape, interface and events, adaptive music, system spec); two review rounds picked 27 interface and event sounds. Details: §5.24
- Built: `tools/sfx/sound_studio.html` (recipes, renders the WAVs), `assets/audio/sfx/`, `data/sounds.json`, the `Sfx` autoload, UI and Alerts buses, sounds on actions, windows, warnings and errors, and `scenes/main/sound_cues.gd` for construction and upgrades finishing, power shortage, cash below zero and tax changes
- Not built yet: ambience, building and vehicle sounds, adaptive music (designed on the board)

**2026-10-07 (Build panel without flicker; no scroll bars):**
- The user found the Build panel messy: it changed size and flickered while pointing at cards, and a small info box popped up next to the ghost. Now the panel keeps one size per category (measured once when it opens), pointing from card to card changes the details once, the material rows are reused instead of rebuilt, and the info box is gone. Tapping a card only chooses it; **Build ⋅ $X** (was Place) closes the panel and the bottom bar places the building; ✕ goes back to the panel (6, Build Menu)
- **No scroll bars in windows on wide screens** (the user: "if it doesn't fit in one window just add a panel"): rows that don't fit the window's height move to a second glass panel beside it (a third while the screen is wide enough); once a window needs a second panel, both may use the whole screen height. A tab of Statistics or the Developer window splits section by section (`ModalWindow.flow_page`). Phones held upright, and pages too long even for the extra panels (the Developer window's Tuning page), still scroll. The building window's **No road** / **No power** boxes became short red lines (also fixes a doubled ".."), so a Feed Mill fits two panels at 1280×720
- **No shadows** under windows, glass bars (HUD, toolbar) and message pills, to save drawing (the user: "save resources"): `window_shadow` in `data/ui_look.json` is 0 and now controls all three (Developer window → Look can bring it back)
- Benchmark (big village): one tick 15.7 ms; opening a Build category 14.5 ms (it measures each building once); statistics open 8–13 ms a tick. UI only: no rules or save changes

**2026-10-07 (windows smaller and tidier):**
- The user found every window too big (too tall, too wide, text and rows too large, messy). Smaller look in `data/ui_look.json` (body text 17 → 15, buttons 46 → 40 high, windows 540 → 460 wide, build cards 144 → 124); a window takes at most 72% of the screen's height (80% in the middle) and scrolls after that (`ModalWindow`); long lines wrap instead of widening a window. Statistics got a sixth tab, **Happiness** (the % , what people expect, "To raise it" with the 3 biggest gains, each need with its reason on a small line under it, each wealth class); People merged its sections (Population, Work, Homes and wealth, Comings and goings); the top bar's happiness opens the Happiness tab. Developer window rows that were wider than the window now put their buttons on a second line; Settings rows are smaller. UI only: no rules or save changes

**2026-10-07 (happiness restructured Tropico-style; services):**
- The user asked to restructure happiness after a deep look at how Tropico does it, and chose all four of its ideas: **quality levels** (Jobs by wage bonus, Housing by home quality and power), **happiness per wealth class** (each class weighs the needs its own way), **rising expectations** (like Caribbean happiness: happiness = 50% + needs met − what people expect, rising with the village's size) and **new service needs** (Health, Fun, Faith, Safety) with four new buildings: **Clinic, Tavern, Chapel, Police Station** (Build → Services; capacity only, no radius). What happiness does (births, migrants, leaving) is unchanged, and it still changes instantly (5.6, 5.23)
- Removed: the hut penalty, the 10-person rule and the 3-hour grace period (expectations replace the last two). A new game now starts at about 62% instead of 100%. No save change (nothing new is stored)
- Developer window: locks for each need and for what people expect, tuning for the new numbers; the "end grace period" button is gone (10)

**2026-10-07 (Look editor in the Developer window):**
- The user wanted to change the size, shape, panels, buttons and icons themselves, seeing the result, and chose to do it inside the game rather than in the Godot editor. The look's constants moved from `ui_theme.gd` into `data/ui_look.json`, and the Developer window got a sixth tab, **Look**, that edits it live and saves it (§6 "UI look"). UI only: no game rules or save changes

**2026-10-06 (Developer window: happiness locks, live tuning, test tools):**
- The user asked for developer options to set the happiness % and its factors themselves, with the whole game following, plus other important test tools. Their choices: both locks and live tuning; kept in the save until "Reset all" with a DEV tag; time skip, people, buildings and items tools; a "Copy as JSON" button for tuning. Built as five tabs in the Developer window; the temporary "Skip 10 min" map button is gone (10)
- Found while testing: headless Godot crashes on quitting once the main scene has been loaded (exit 139, also on the last commit, so not from this change); the tests that don't load the main scene are unaffected

**2026-10-06 (happiness review: shown % rounded down, who leaves the island, "To raise it"):**
- The user saw a baby born "below 19%" and noticed happiness never reaches 0%. A review of the rules and their save (58 h of history) found every birth came at 20.4% or more: the rule works. The HUD rounded to the nearest whole number, so 19.6% (no babies) and 20.4% (half-speed babies) both showed "20%". A part-baby carried over while births are stopped also arrives ~40 s after happiness gets back to 20%. The shown % is now **rounded down**, so it always falls in the band that counts; the migrant edge moved from 20.5% to 21% to match (5.6)
- Why not 0%: it takes no food, no jobs and everyone in a hut; the jobless leaving first and the 30-point hut cap keep a real village around 15% at worst. Their village (37%) had no food selling at all (−33 points) and went round a loop: half-speed babies at 20–49% grow up jobless and homeless, happiness falls to ~16%, people leave, babies again (362 born, 290 left)
- The user's leaving rules: **only the jobless adults leave** (workers stay, even in huts); **children leave only at 15% or less**; **at 10% or less workers living in huts leave too** (their posts stay open: no migrants at 20% or less). New band keys `children_leave_per_hour`, `homeless_workers_leave` (5.6)
- Statistics → People: says who is leaving, and a **"To raise it"** line with the gain of each fix (one more food, homes for the households in huts, jobs for the jobless), biggest first (5.6)

**2026-10-06 (UI restyle: "Harbor Glass", realistic):**
- The user turned down the cartoon UI ("more realistic like city skylines 2 styles rather than cartoonish"). A mockup page (the Harbor Glass UI kit: PC and phone screens, HUD, buttons, windows, forms) was made first; the user said "go ahead".
- Built (§6 "UI look"): dark glass theme drawn by Godot (the 14 SVG skins are gone), Overpass font, 28 interface icons redrawn as white line icons, HUD as one strip in the top-right corner, bottom toolbar, building card, tile buttons, windows docked on the left on PC, darker charts. UI only: no game rules or save changes; `build_menu.json` points the Farming and Food tabs at new tab icons.
- Replaces the 2026-10-05 plan to give buttons and windows a "chunkier 3D finish".
- Left for later: money per hour, notices, build categories in the toolbar, redrawn goods icons.

**2026-10-06 (Harbor Glass, part 2: matching the mockup):**
- The user ran the first restyle and said it didn't look like the mockup: "not transparent glass and the positions weren't changed". It had skipped the blur (93% solid glass) and the mockup's new layout.
- Built: frosted glass (80% + blur; Settings → Frosted glass, off on phones), screen buttons in the top-left corner, build categories as the bottom toolbar, the Build panel above it (category square, cards with a cost line, materials list with in stock / buy N, Place ⋅ $X), the info box beside the ghost while placing, docked windows below the top-left strip. The HUD's item chips are gone (not in the mockup). "·" → "⋅" in all screens (Overpass's middle dot sits against the next word).
- Benchmark (big village): one tick 15 ms (14 before), Build panel open 7 ms a tick; the blur's cost on a phone is still to be measured with the overlay (it starts off there).

**2026-10-06 (faster building, smaller Supermarkets, migrants by jobs, materials back on demolish):**
- The user asked for four changes: new buildings take **10 seconds** (upgrades unchanged); the Supermarket starts with **1 shelf**, +1 per upgrade; **no migrants at 20% happiness or less**, otherwise only open jobs decide; **demolishing gives back every unit of material**, into the warehouse, and no money
- Follow-ups they chose: warehouse materials are **reused** by building and upgrading (warehouse first, buy the rest); each building keeps a record of its materials and what they **really cost**, since prices change hourly; demolishing is refused when the warehouse has no room; the crew is paid **a share of the materials' value** (10%) instead of by the hour. Details: §5.15, §5.16, §5.6. Save version 15
- Left for later: the shelf form lists only foods you have in stock (the user saw only 2)
- Later the same day the user changed two things: **upgrades take materials only from the warehouse** (missing ones must be bought at the Trading Post or produced; §5.15), and the **Warehouse and Construction Office have no Suspend button** (§5.10)
- Then: **City Hall is no longer a power source** (no grid link, no power circle). Power starts at the plants you build; villages start with none (§5.5.0)

**2026-10-06 (2×2 footprints, land 26×26):**
- After Batch A the user saw City Hall looking smaller than Public Housing, and chose to fix the size first. Decisions: big buildings plus the Solar and Nuclear plants are 2×2 (homes, Wind Turbine and Substation stay 1×1); old saves: roads under a growing building are removed and paid back, and only a building overlapping another moves; the land grows to 26×26 now. Details: §4 "Footprints". Save version 14
- Bug fix found by the random-game test: starting a batch with a wage bonus could move a household into a richer class without updating the Makeshift Huts until the next hiring; huts are now updated right away

**2026-10-05 (Building art: style chosen, Batch A made):**
- The user asked for Blender sprites for every building, plus a 3D finish on buttons and windows. Plan: §4 "Full building set, in 5 review batches"; buttons and windows stay SVG, get a chunkier 3D finish, and each building window gets the building's picture (still to do)
- Style sample rendered both ways (soft toy vs flat vector with outlines); the user kept **soft toy**
- Batch A modelled (`art/blender/models/`): Bakery, Grain Mill, City Hall, Construction Office, Public Housing, Warehouse; the studio now photographs them instead of the Kenney stand-ins (Warehouse had no picture before)
- Tools: the Blender preview now frames the whole model (tall ones were cut off); the studio's contact sheet can show any folder (`-- sheet <out.png> art/models`)

**2026-10-05 (UI restyle: "Honey & cream" cartoon look):**
- The user asked for all the UI in a casual, warm, adorable 2D cartoon style, with every pop-up window and every button uniform. They chose: Honey & cream colours, buttons with one shape where colour shows meaning (honey normal, green go, red danger, grey back/can't; choices as cream chips), and the Fredoka font.
- Built (§6 "UI look"): new theme and SVG skins, Fredoka font, one title ribbon + close button for every window (the Build menu too), cream HUD bubbles, three button sizes and five text styles applied across every screen through shared builders in `ui_theme.gd`. The old blue and yellow button skins are gone. UI only: no game rules, data or save changes.

**2026-10-05 (Production chains Wave 1, Trading Post, on trial):**
- The user asked to add ~150 items of interconnected production chains (15 groups) to the existing systems. Reviewed together: doable, but in waves; they chose food first, a simple Trading Post, product choice per building (one Plantation that switches crops for a fee; factories pick once, for good), real by-products, new store types for non-food goods later, generic Fruit, a separate Ranch, and a Food need that rewards variety.
- Built (§5.21, §5.22): item categories and store `sells` lists; Food need counts only food (0/40/60/75/90/100%); by-products with `cost_share`; product choice and switch fees (save version 13: older buildings keep their product); the Trading Post; screens that cope with many goods; Wave 1A: the Wheat Farm becomes the Plantation (10 crops), the Flour Mill the Grain Mill (+ cornmeal, milled rice), and Oil Press, Sugar Mill, Food Factory, Confectionery, Beverage Plant, Cannery; 25 new item icons.
- Wave 1B: Feed Mill, Ranch (switchable animals), Fishery (fish or shrimp), Apiary (honey + beeswax), Dairy, Slaughterhouse (beef + hides), Meat Plant, Fish Plant, canned fish; 23 more icons; four whole-chain tests on the real data.
- Waves 2 (construction materials, coal power), 3 (textiles, furniture, paper, stores) and 4 (oil, chemicals, electronics, cars, medicine, luxury) are planned in §5.21.

**2026-10-05 (Electricity: Wind Turbine, Substation, Solar + Nuclear coming soon, on trial):**
- The user asked (Build menu, new Power tab) for a Wind Turbine (no workers, a smaller amount of power), a Solar Power Plant (needs High School graduates), a Nuclear Power Plant (uranium store, College; greyed out "soon") and an Electric Substation that expands the grid's coverage.
- Their choices: Tropico-style all-or-nothing power (a building that doesn't fit gets none and stops), oldest building first; coverage by radius with overlapping circles; City Hall's public grid link (10 MW, billed); Solar and Nuclear greyed out until schools; steady output for now.
- Built (5.5.0): power use on the Mill and Bakery, the network and its coverage view on the map, "No power" warnings, power bill in Statistics and Welcome back, power in batch costs and prices. Own Blender models for all four buildings.
- Save version 12: older saves get free Substations covering their buildings that use power.

**2026-10-05 (City Hall and real construction workers, on trial):**
- The user asked for the Construction Office to be a real construction company, needed to build or upgrade anything except roads, with 1 construction worker to build and one more per level for upgrades, and for the old headquarters to become City Hall.
- Their choices: 4 workers per office; paid per project; when all are busy the job can't start yet; more crew by upgrading the office (6 / 8 / 10) or building another.
- Built (§5.8, §5.15): City Hall (the road hub), a buildable Construction Office (starts pre-built), crew checks on building and upgrading, the office's window shows free workers and what they're on. New sprites: City Hall keeps the old headquarters picture, the office uses Kenney building-d (temporary).
- Save version 11: the headquarters is renamed City Hall and older saves get a free Construction Office by the roads.

**2026-10-05 (Roads & traffic, on trial):**
- The user asked for roads, intersections, bridges, overpasses and flyovers, with people and cars. They chose:
  - roads that matter: buildings with workers need a road to the Construction Office;
  - traffic for show only;
  - roads first, bridges later.
- Overpasses and flyovers are not planned (§5.20).
- Built:
  - road tiles at $25, with automatic corners, T-junctions and crossroads;
  - Road Mode (drag to lay or remove road);
  - later the same day, at the user's request: the automatic "Build road" button and the road stubs into buildings were removed; buildings got their own plots (lawn and pavement edge), and roads got lamp posts and more zebra crossings;
  - a "no road" sign over cut-off buildings;
  - walkers and cars;
  - starting roads in new games.
- Save version 10: old saves get free roads laid automatically.

**2026-10-05 (Water Treatment Plant, on trial):**
- The user asked for Water Treatment Plants. Their choices: your own water supply (your buildings use it first, and the public supply covers the rest), its water costs only its running costs (wages), and spare water isn't sold.
- Built:
  - a new category `utility`;
  - a Build menu tab Utilities;
  - Level 1 needs 4 workers and cleans 60 m³/h, about $1 a m³ against $2 public, with upgrades to Level 4;
  - only public water is metered on the bill;
  - batch water estimates and the farm's water line use the cheaper own water.
- No save change (5.13.1).

**2026-10-05 (production batches, on trial):**
- The user asked for Sim Companies-style production: pick a batch length (finish time, or All the stock allows, up to 48 h), see the total cost, labor, finish time and cost per unit before producing, collect an hourly share from a bubble, and a worker bonus that adds units per batch instead of hiring more workers. Their choices: all three production buildings, production slowed ÷10 so 24 h fits the Warehouse, no building storage (only the Warehouse), wages paid up front, cancel with a 50% refund of the unworked part, the bonus locked in per batch and no longer deciding hiring. Starting cash raised to $15,000 since wages are now paid up front. Save version 9 (5.1, 5.4, 5.6, 5.14, 6, 8)

**2026-10-04 (balance sheet):**
- The user asked for a balance sheet and to track where all cash comes from and goes. Built: Statistics → Balance (what the company owns and owes, company value, starting capital, profit kept), a Cash check and a 30-minute Money log on the Cash flow tab; developer cash changes are now counted too. Buildings at price paid, starter buildings at list price (user's choices). Save version 8 (5.19)

**2026-10-04 (building upgrades to Level 3):**
- The user asked for building upgrades up to Level 3. Their choices: money for now (materials + laborers later), a bigger building each level, the building stops while upgraded, no Construction Office cap. Built: Upgrade section in the building window; farms, mills, bakeries and shops close for 10 / 30 min (work in progress waits), homes and warehouses stay in use; more workers mean faster work at the same wages per batch (5.15)

**2026-10-04 (babies don't need a house):**
- The user: "having a house shouldn't be a basis to having kids". Now all adults have babies, and every family (household), in a house or a hut, has 2 child places. Homelessness still slows births, but only through happiness (the homeless penalty) (5.6, 5.18)

**2026-10-04 (every Supermarket sells on its own):**
- Playtest: a second Supermarket couldn't sell flour or bread ("already on a shelf") because a product could be on only one shelf in the whole village. Now each store sells on its own (one shelf per product per store) and stores selling the same product share the village's shoppers for it (2 stores: half as fast each). The stock window shows "shared with N other stores" (5.16)

**2026-10-04 (faster population, on trial):**
- Playtest: the village grew too slowly. Migrant workers now arrive in **groups of up to 5** every 2 minutes (`move_in_group_size`; fewer when fewer jobs are open), unhappy people leave in **groups of 5** (`happiness.leave_group_size`) and faster (**2%** an hour at 20–49%, **5%** below 20%), births are **10x** (`birth_rate_per_hour` 0.01 → 0.1) and children grow up in **6 hours** instead of 24. A toast shows each group arriving, babies born, children growing up and (in red) people leaving. Statistics → People says how many the next group brings (5.6)

**2026-10-04 (construction materials + labor, on trial):**
- The user asked for real construction requirements: Bricks, Cement, Steel, Construction materials and labor, fixed per level and doubling each level, for building and for every upgrade. Their choices: materials auto-bought from an in-game supplier at a market price that changes every hour (±20%, so costs show as "≈"); labor = a crew of 8 at Level 1 doubling per level (8/16/32/64), paid once at $15/h; amounts per building; times 1 h to build, then 1 h / 2 h / 3 h to Levels 2 / 3 / 4; Level 4 added with the same pattern; "Robotic workers: coming soon" shown in the Upgrade section. Starting cash $12,000 (5.15)

**2026-10-04 (homeless penalty):**
- Every household in a Makeshift Hut takes 2 points off happiness (at most 30), on top of the Housing need, shown as its own line. On the playtest save: 82% → 70% once 12 migrants live in 6 huts, and 46% (people start leaving) when the shelves then run empty (5.6)

**2026-10-04 (migrant workers):**
- Second playtest: job seekers filled the old save from 6 to 36 adults, then stopped because the 3 Public Housing blocks were full (12 jobs open, the Supermarket empty, so no food). Job seekers became **migrant workers who don't need a free home** (`move_in_needs_home` false): they live in Makeshift Huts until homes are built, lowering the Housing need. Measured on that save: the 12 jobs filled in 20 minutes with 6 huts, happiness 67% → 82% (the Supermarket got workers) (5.6)
- Playtest: an old save from before the founders had 6 adults and three farms without workers; births alone (about one baby every 11 hours for 6 adults, then 24 hours to grow up) were too slow to be fun. Newcomers are back as **job seekers**: one adult every 2 minutes, only for open jobs nobody here can take, only with room in a real home, only at 50% happiness or more (`move_in_only_for_jobs`, `population_growth_seconds` 120, `move_in` per happiness band). Statistics → People shows when the next one comes or why none is coming (5.6)

**2026-10-03 (village growth bounded; old saves keep free homes):**
- A review found the village could outgrow its homes forever (a contented village: ~540 people and ~210 huts by day 30). Fixed with the user's design: a **Housing need** in happiness (share of households with a home), **people leave the island** when happiness is low (1% an hour at 20–49%, 3% below 20%; the homeless first), births **halved to 1%** of housed adults an hour; homeless adults have no babies (5.6)
- Save version 7: saves from before housing types get their free Small Houses back as Public Housing, so nobody becomes homeless on loading (5.18, 8)
- Found while testing: Godot's JSON reader can misread the last digit of a 17-digit time; harmless in play (a billionth of a second), so the save round-trip check now ignores differences that have played out a second later

**2026-10-03 (housing types built, on trial):**
- Makeshift Hut, Public Housing, Regular House (the old Small House, same id so saves keep their houses) and Villa; households of 2 adults + 2 children; wealth from wages; rent to the player; huts appear for the homeless; homes' power counted for later. New games start in 5 Public Housing. A developer option changes the rent per home type (5.18)
- Changed while building: households fall back to any home they can afford; babies need a child place in a household with a home; demolishing a home no longer sends people away; huts can't be demolished

**2026-10-03 (housing types planned, no code yet):**
- Housing types (5.18): Makeshift Hut (appears by itself for the homeless), Public Housing (free, Broke / Poor), Regular House (rent, Poor / Well off), Villa (rent, Rich / Filthy rich). A household = 2 adults + 2 children; wealth class from wages; rent goes to the player; an occupied home uses its type's fixed MW, an empty one none; the founders will live in Public Housing

**2026-10-03 (founders, births, children & deaths built, on trial):**
- A new game starts with 50 adults in 5 Small Houses; immigration is off for now; the village grows through births (children grow up after 24 h) and loses people at a steady death rate; needs don't count in the first 3 hours. Save format 6 (older saves: everyone is an adult). Statistics → People shows groups, children by age and comings and goings; a Births graph (5.6, 5.8)

**2026-10-03 (moving in slowed down):**
- People move in every 3 minutes instead of every 10 s (`population_growth_seconds` 10 → 180). Houses only give room; a new house now fills in 20–30 minutes instead of about one, so births (planned) will matter too (5.6)

**2026-10-03 (births, children & deaths planned, no code yet):**
- People become adults and children (group counts, not individuals, unlike Tropico). Adults have babies (2% an hour, sped up or slowed by happiness); children grow up after 24 h; a steady 0.5%-an-hour death rate takes adults and children in proportion. Save format 6 planned (5.6)
- Statistics → People gets "Population by group": adults (employed / unemployed) and children with shares, children by age group, moved in / born / grew up / died (last hour and all time), and group lines on the graphs

**2026-10-03 (population needs built, on trial):**
- Built: happiness on the HUD and in Statistics → People; `happiness` block in `game_config.json`; the save keeps `population.growth_speed` (optional, old saves load as they are)

**2026-10-03 (population needs planned, no code yet):**
- People get two needs, Food (foods selling at the Supermarket) and Jobs (share employed), combined into one village happiness %. Happiness only changes move-in speed (×1.5 / ×1 / ×0.5 / stops); needs count from 10 people. Nothing new in the save (5.6)

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
