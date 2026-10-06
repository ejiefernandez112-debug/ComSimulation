"""REVIEW SHEET: tiles preview pictures into one image, to check a batch at a glance (one picture
to look at instead of one per variant). Runs in Blender, which has numpy built in:

	"C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/blender/sheet.py -- batch_b dairy-a dairy-b dairy-c

Writes art/previews/batch_b.png: the previews art/previews/<name>.png, left to right, 3 per row
(add --columns=N to change), each shrunk to 400 px. A name without a preview leaves its cell empty.
"""
import sys
from pathlib import Path

import bpy
import numpy as np

PREVIEWS = Path(__file__).resolve().parent.parent / "previews"
CELL = 400


def main():
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	columns = 3
	for a in [a for a in args if a.startswith("--columns=")]:
		columns = int(a.split("=")[1])
		args.remove(a)
	if len(args) < 2:
		raise SystemExit("Usage: ... sheet.py -- <sheet name> <preview name> [<preview name> ...]")
	out, names = args[0], args[1:]
	rows = (len(names) + columns - 1) // columns
	sheet = np.ones((rows * CELL, columns * CELL, 4), dtype=np.float32)
	for i, name in enumerate(names):
		path = PREVIEWS / f"{name}.png"
		if not path.exists():
			print(f"Review sheet: no preview for {name}")
			continue
		img = bpy.data.images.load(str(path))
		w, h = img.size
		px = np.empty(w * h * 4, dtype=np.float32)
		img.pixels.foreach_get(px)
		step = max(1, round(w / CELL))
		small = px.reshape(h, w, 4)[::step, ::step][:CELL, :CELL]
		row, col = i // columns, i % columns
		y0 = (rows - 1 - row) * CELL  # Blender images start at the bottom row
		sheet[y0:y0 + small.shape[0], col * CELL:col * CELL + small.shape[1]] = small
		# A thin dark line between cells.
		sheet[y0:y0 + CELL, col * CELL:col * CELL + 2] = (0.2, 0.2, 0.2, 1.0)
		sheet[y0:y0 + 2, col * CELL:(col + 1) * CELL] = (0.2, 0.2, 0.2, 1.0)
	picture = bpy.data.images.new("sheet", columns * CELL, rows * CELL, alpha=True)
	picture.pixels.foreach_set(sheet.ravel())
	picture.filepath_raw = str(PREVIEWS / f"{out}.png")
	picture.file_format = "PNG"
	picture.save()
	print(f"Review sheet: {len(names)} pictures -> {picture.filepath_raw}")


main()
