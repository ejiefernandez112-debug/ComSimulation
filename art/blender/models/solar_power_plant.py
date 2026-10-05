"""SOLAR POWER PLANT (1 tile): three rows of tilted blue panels on posts over gravel, facing the
camera's side (-Y), with a small white inverter hut. Plot is -2.5..2.5 on X and Y (see kit.py)."""
from kit import Parts, mat, place

TILES = 1
TILT = 28  # degrees the panels lean back


def build():
	g = Parts("ground")
	g.box((4.7, 4.7, 0.12), place((0, 0, 0.06)), mat("gravel"))
	g.done(bevel=0.03)

	p = Parts("panels")
	for row, y in enumerate((-1.45, 0.0, 1.45)):
		width = 3.4 if row < 2 else 2.4
		x = -0.45 if row < 2 else -0.95
		for px in (x - width / 2 + 0.3, x + width / 2 - 0.3):
			p.box((0.1, 0.1, 0.55), place((px, y - 0.15, 0.38)), mat("metal_dark"))
			p.box((0.1, 0.1, 0.95), place((px, y + 0.25, 0.58)), mat("metal_dark"))
		p.box((width, 1.15, 0.08), place((x, y + 0.05, 0.85), (TILT, 0, 0)), mat("metal"))
		cells = int(width / 0.42)
		for i in range(cells):
			cx = x - width / 2 + (i + 0.5) * width / cells
			p.box((width / cells - 0.05, 1.05, 0.04), place((cx, y + 0.04, 0.9), (TILT, 0, 0)), mat("solar", 0.08 if i % 2 else 0.0))
		p.box((width - 0.04, 0.03, 0.05), place((x, y + 0.04, 0.93), (TILT, 0, 0)), mat("solar_light"))
	p.done(bevel=0.02)

	h = Parts("inverter")
	h.box((0.9, 0.8, 0.9), place((1.75, 1.5, 0.57)), mat("white"))
	h.box((1.0, 0.9, 0.1), place((1.75, 1.5, 1.07)), mat("roof"))
	h.box((0.3, 0.05, 0.55), place((1.75, 1.08, 0.45)), mat("metal_dark"))
	h.box((0.2, 0.05, 0.2), place((2.21, 1.5, 0.75), (0, 0, 90)), mat("hazard"))
	h.done(bevel=0.03)
