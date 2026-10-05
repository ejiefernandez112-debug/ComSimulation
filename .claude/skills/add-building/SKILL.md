---
name: add-building
description: Add a new building, resource, or recipe to this Godot island village game. Covers every file that has to change (data JSON, build menu, icons, sprite, check script, plan.md) so nothing is forgotten. Use when the user asks to add or create a building, shop, farm, factory, house, product, resource, or recipe.
---

# Add a building / resource / recipe

All content is data-driven (CLAUDE.md rule 1). A new building normally needs **no new GDScript**: only JSON, art and docs. If it seems to need new code, it's a new *rule*. Stop and use the `new-feature` skill instead.

## 1. Check the plan first

- Search [plan.md](../../../plan.md) for the building (§5.4 lists resources, buildings and recipes). Use its numbers if they're there.
- Check the current phase in CLAUDE.md. If the building belongs to a later phase, tell the user and ask before going ahead.
- Ask for any missing tuning numbers, or propose placeholders and label them "PLACEHOLDER" in a `_comment`.

## 2. Data files (edit with the Edit tool; never PowerShell Set-Content, which mangles UTF-8)

**`data/buildings.json`**: copy the closest existing building as a template. For example, `wheat_farm` (the Plantation) is an extractor (no inputs) and `flour_mill`/`bakery`/`food_factory` are processors. Key fields:
- `name`, `category` (extractor / processor / retail / trade / residential / storage / utility / power / civic), `description` (one friendly sentence), `menu_tab`
- `buildable`, `max_workers`, `worker_type`, `materials` (bricks / cement / steel / construction_materials), `max_count` (most a village may have)
- `water_per_hour`, `power_mw` (while making a batch)
- `recipes`: `[{ "id", "inputs": {res: n}, "outputs": {res: n}, "duration": 3600 }]`: every recipe is ONE hour of work. Several recipes = the building makes one product, chosen by its first batch; `switch_fee` (share of its value) lets it switch later, otherwise it's for good (plan.md §5.21). Several outputs = by-products: add `"cost_share": {res: share}` adding up to 1. The selling price comes from the FIRST recipe in the file that makes an item, so keep the usual one first
- Retail: `shelves`, `sells` (item categories it sells)
- `upgrades`: Level 2, 3, 4. Only the stats that change.
- Building ids are permanent once saved games use them. Never rename an existing id (change its `name` instead, as with the Wheat Farm → Plantation).

**`data/resources.json`**: every new input or output needs an entry: `name`, `tier`, `category` (a key of `game_config.json` `item_categories`), and `appetite` if villagers buy it (food needs one; some store must sell its category). Prices are cost-based and worked out live (plan.md §5.12), so don't add a hard-coded price unless plan.md says to.

**`data/build_menu.json`**: only if it needs a new tab.

**New key?** If you invent a new field, add it to the key lists in [tests/check_project.gd](../../../tests/check_project.gd) (`BUILDING_KEYS`, `RESOURCE_KEYS`, `UPGRADE_STATS`). A new key that changes behaviour means new rules in `scripts/sim/simulation.gd`, which is the `new-feature` skill's job.

## 3. Art

- **Icon**: each new resource needs `assets/ui/icons/<resource_id>.svg`. Match the style of the existing icons (open one or two first). Simple flat SVG.
- **Sprite**: the building needs a picture in `assets/buildings/`. Never hand-edit that folder. Either:
  - add an entry to `tools/sprite_studio.json` that points at a model in `Sprites kit/` or `art/models/`, or
  - make a Blender model script in `art/blender/models/<id>.py` (see `art/README.md`).
  Then tell the user to run the sprite studio (it needs a real GPU window, so Claude can't run it headless):
  `"C:\Program Files\Godot\Godot.exe.exe" --path . --rendering-method forward_plus -s tools/sprite_studio.gd`
  and afterwards `--headless --path . --import`.

## 4. Verify

- Run the `test-game` skill. `check_project` catches unknown keys and recipe mistakes, and `test_invariants` plays random games with the real data, so a broken recipe shows up there.
- Suggest the user opens the game and builds it once.

## 5. Document

- Update the plan.md section: mark it "built YYYY-MM-DD" (or "on trial") and add a line to §15 Revision Log.
- Tell the user in plain language what was added, which files changed and why, and which numbers are placeholders.
