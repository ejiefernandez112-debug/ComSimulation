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
   with `"kit_folder": "art/models"`. Then run the studio and the import, as in CLAUDE.md.

## Pack status

| Building | Model | Footprint |
|---|---|---|
| Wheat Farm | ✅ `wheat_farm.py` | designed 2×2 (shown on 1 tile until 2×2 footprints exist) |
| Wind Turbine, Electric Substation, Solar Power Plant, Nuclear Power Plant | ✅ `wind_turbine.py`, `electric_substation.py`, `solar_power_plant.py`, `nuclear_power_plant.py` | 1×1 |
| Flour Mill, Bakery, Small House, Construction Office | still Kenney stand-ins | — |
| Trees, rocks | not started | — |
