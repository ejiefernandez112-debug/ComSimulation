# Art: our own 3D models (Blender)

Every building is a small Python script that Blender runs to build the 3D model. The game never
loads anything in this folder (`.gdignore`). The sprite studio (`tools/sprite_studio.gd`)
photographs the finished models into the 2D sprites the game shows (plan.md §4).

- `blender/kit.py`: the shared **style kit**. Colour palette, scale (1 tile = 5 units) and shape
  helpers with rounded edges. Change a colour here and every model that uses it changes.
- `blender/models/<building_id>.py`: one script per model, e.g. `wheat_farm.py`.
- `blender/build.py`: builds one model, saves `models/<id>.glb` and a preview picture
  `previews/<id>.png`.
- `models/` and `previews/` are generated, so they're not in Git. Re-run the builder to get them back.

## Make or update a model

1. Build it (about 30 seconds):
   `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python art/blender/build.py -- wheat_farm`
   Add `--blend` at the end to also get `models/wheat_farm.blend`, which you can open in Blender to look around.
2. Check `previews/wheat_farm.png`.
3. Photograph it into the game sprite. The model must be listed in `tools/sprite_studio.json`
   with `"kit_folder": "art/models"`. Then run the studio and the import, as in CLAUDE.md
   (`-- only <id>` at the end of the studio command remakes just that building).

**Parts that turn in the game** (the Wind Turbine's `rotor`, the Grain Mill's `sails`): build the
part as its own `Parts("name")` and finish it with `done(pivot=frame(hub, axle_direction, z_axis=(0, 0, 1)))`,
so it turns around its axle. Its `"spin"` in `tools/sprite_studio.json` names that part. A new
version of such a model must keep the part and its name (plan.md §4, "Turning parts").

## Pack status

| Building | Model | Footprint |
|---|---|---|
Style: **soft toy** (chosen 2026-10-05; plan.md §4). A model's `TILES` should match the building's `size` in `data/buildings.json` (2×2 since 2026-10-06): the studio photographs each building at that size.

| Building | Model | Designed for |
|---|---|---|
| Plantation (`wheat_farm`), Bakery, Grain Mill (`flour_mill`), City Hall, Construction Office, Warehouse | ✅ one `.py` each | 2×2 |
| Public Housing | ✅ `public_housing.py` | 1×1 |
| Wind Turbine, Electric Substation, Solar Power Plant, Nuclear Power Plant | ✅ `wind_turbine.py`, `electric_substation.py`, `solar_power_plant.py`, `nuclear_power_plant.py` | 1×1 |
| Makeshift Hut, Regular House (`small_house`), Villa | still Kenney stand-ins (batch B) | — |
| Water Treatment Plant, Supermarket, Trading Post, and the Wave 1 farms and factories | no picture yet (batches B–E, plan.md §4) | — |
| Trees, rocks | not started | — |

Making new building art (2-3 variants per building, picked on the Building Encyclopedia page
`art/encyclopedia/index.html`, made by `python tools/encyclopedia.py`) is a step-by-step job: the
`building-sprites` skill in `.claude/skills/`. `art/blender/sheet.py` tiles previews into one review
picture; `tools/apply_picks.py` puts chosen variants into `tools/sprite_studio.json`.
