# Style kit cheat-sheet (`art/blender/kit.py`)

Look: **soft toy** (chosen 2026-10-05): warm, fairly saturated colours, softly rounded edges, no
outlines, chunky props. Detail level like `bakery.py` and `wheat_farm.py`.

## Scale and sides
- 1 tile = 5 units. `TILES = 2` → the plot is -5..5 on X and Y; `TILES = 1` → -2.5..2.5. Keep
  everything inside the plot seen from above (sails, cranes, flags). Height is free.
- The player sees the **-Y face** (lower left on screen) and the **+X face** (lower right): doors,
  windows and signs go there. +Y and -X are the hidden back. Tall things go to the back (the -X/+Y
  corner is the top of the screen) so they don't hide the front.
- Sun from the upper left of the screen. Anything turned straight at the camera, i.e. facing
  (1, -1) like windmill sails, is in shade: give it light colours.
- The game shows a 2x2 about 200 px wide at the closest zoom, a 1x1 about 100 px. Small details
  vanish: **one big recognisable shape + one signature prop** that shows what the building makes.
- Ground: paving or dirt pads where people walk; leave the rest of the plot empty (map grass shows).

## Helpers
```python
from mathutils import Vector
from kit import Parts, frame, mat, place, rng

p = Parts("walls")                      # collects shapes into one object
p.box((sx, sy, sz), place((x, y, z), (rx, ry, rz)), mat("brick"))   # centred; rotations in degrees
p.cylinder(r, h, m, material, sides=16, top_radius=None)              # along local Z, centred; cone with top_radius
p.ball(r, m, material, squash=(1, 1, 0.8), detail=2)
p.prism([(x, z), ...], depth, m, material)   # 2D outline (local X/Z) pushed out along local Y, centred
p.done(bevel=0.03)                      # rounds edges; 0.02-0.04 usual, 0 for many tiny bits (tiles, wheat)
m = frame(at, x_axis, z_axis=dir)       # placement from directions; local y = z cross x
m @ place((dx, dy, dz))                 # a placement relative to m
mat("wood", -0.08)                      # palette colour, a bit darker (+ = lighter)
r = rng(7)                              # fixed random: same model every build
```

## Palette names
barn_red, barn_red_dark, trim, roof, roof_dark, wood_light, wood, wood_dark, stone, stone_dark,
metal, metal_dark, soil, soil_dark, dirt, wheat, wheat_light, stalk, hay, sack, cloth_blue,
cloth_red, leaf, window, white, concrete, concrete_dark, solar, solar_light, hazard, gravel,
plaster, brick, brick_dark, terracotta, terracotta_dark, bread, bread_light, shop_green, paving,
fire, copper, copper_dark, water. Need another? Add it to `PALETTE` in kit.py (sRGB hex, warm).

## Patterns
Placement on a visible wall (x runs along the wall, -y points out of it):
```python
def _wall(side, along, z):
	if side == "front":
		return place((along, FRONT, z))                        # FRONT = y of the -Y face
	return frame((SIDE, along, z), (0, 1, 0), z_axis=(0, 0, 1))  # SIDE = x of the +X face
```
House body with gable ends at both X ends (ridge along X):
```python
outline = [(-D / 2, BASE), (D / 2, BASE), (D / 2, EAVE), (0, RIDGE), (-D / 2, EAVE)]
p.prism(outline, W, frame((X, Y, 0), (0, 1, 0), z_axis=(0, 0, 1)), mat("plaster"))
```
One roof slope (run it for sign = -1 front and +1 back):
```python
eave, ridge = Vector((X, Y + sign * D / 2, EAVE)), Vector((X, Y, RIDGE))
u = (ridge - eave).normalized()
w = Vector((0, -u.z, u.y)); w = -w if w.z < 0 else w        # points out of the roof
start = eave - u * 0.4; run = (ridge - start).length          # 0.4 = eave overhang
p.box((W + 0.6, run, 0.12), frame(start + u * run / 2 + w * 0.06, (1, 0, 0), z_axis=w), mat("roof"))
```
Tilts: a box turned +angle about X rises toward +Y; turned +angle about Y, its +X end goes **down**.
Bush: `p.ball(rad, place((x, y, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9))`

## Variants template
```python
TILES = 2  # = "size" in data/buildings.json
# Plain values only: the encyclopedia reads this without Blender. "name" 1-3 words, "note" one sentence.
VARIANTS = {
	"a": {"name": "Classic", "note": "Red-brick dairy with a white milk tank and cows in the yard.",
		"walls": "brick", "roof": "roof", "layout": "tank_right"},
	"b": {"name": "Farm colours", "note": "Same dairy in cream and green, milk churns instead of the cart.",
		"walls": "plaster", "roof": "shop_green", "layout": "tank_right"},
	"c": {"name": "Long barn", "note": "A long barn with a round roof and the tank on the left.",
		"walls": "brick", "roof": "roof", "layout": "long_barn"},
}


def build(v):
	r = rng(11)
	_ground()
	_body(v["walls"], v["layout"])
	_roof(v["roof"], v["layout"])
	_props(r, v["layout"])
```
A = the brief's main design. B = the same layout with other colours and 1-2 other props.
C = another layout or roof shape. All three keep the footprint and the signature prop.

## Traps seen before
- A full ball shows its underside: sink half of it (the hard hat on the site cabin's roof) or squash it.
- A cone lid on a tank reads as an open bowl from above: use a squashed ball.
- Big flat dark roofs look dull small: lighter colour, or vents and skylights on them.
- Bright blue panels look like solar panels. Frosted skylights: `mat("white", -0.12)`.
- Flagpoles, lamps and trees in front of the door hide it: put them at the sides or corners.
- Check thin parts against each other (shutters vs corner stones, props vs walls): overlaps flicker.
- Smoke or steam: 2-3 white balls rising and drifting right; small, so they don't hide the roof.
- 1x1 homes are about 4-5 units wide, 2x2 buildings about 9-10: the studio scales each model to
  fill its tiles, so a model much smaller than its plot ends up looking oversized.
- Parts that turn in the game (Wind Turbine `rotor`, Grain Mill `sails`; their `"spin"` in
  `tools/sprite_studio.json`): every variant must build that part as its own
  `Parts("<same name>")`, finished with `done(pivot=frame(hub, axle_direction, z_axis=(0, 0, 1)))`,
  and nothing else in it (the nacelle or cap is a separate part, it stands still).
