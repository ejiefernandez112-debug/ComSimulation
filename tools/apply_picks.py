"""APPLY PICKS: puts the variants chosen on the encyclopedia page into the game's sprite list.

	python tools/apply_picks.py "dairy=b ranch=a"

For each building id, tools/sprite_studio.json gets  "<id>": { "kit_folder": "art/models",
"model": "<id>-<letter>.glb" }  (the line is replaced, or added). The variant's model must exist
in art/models/ (built by art/blender/build.py). Afterwards run the sprite studio and the import
(CLAUDE.md), which turn the chosen models into the game's pictures.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STUDIO = ROOT / "tools" / "sprite_studio.json"


def main():
	text = " ".join(sys.argv[1:])
	picks = re.findall(r"([a-z_]+)\s*[=:]\s*([a-z])\b", text)
	if not picks:
		raise SystemExit('Nothing to apply. Example: python tools/apply_picks.py "dairy=b ranch=a"')
	buildings = json.loads((ROOT / "data" / "buildings.json").read_text(encoding="utf-8"))
	lines = STUDIO.read_text(encoding="utf-8").split("\n")
	problems = []
	for building_id, letter in picks:
		model = f"{building_id}-{letter}.glb"
		if building_id not in buildings or building_id.startswith("_"):
			problems.append(f"{building_id}: not a building in data/buildings.json")
			continue
		if not (ROOT / "art" / "models" / model).exists():
			problems.append(f"{building_id}: art/models/{model} doesn't exist (build it first)")
			continue
		entry = f'\t\t"{building_id}": {{ "kit_folder": "art/models", "model": "{model}" }},'
		at = next((i for i, line in enumerate(lines) if line.startswith(f'\t\t"{building_id}":')), -1)
		if at >= 0:
			lines[at] = entry if lines[at].rstrip().endswith(",") else entry.rstrip(",")
		else:
			last = max(i for i, line in enumerate(lines) if line.startswith('\t\t"'))
			if not lines[last].rstrip().endswith(","):
				lines[last] = lines[last].rstrip() + ","
			lines.insert(last + 1, entry.rstrip(","))
		print(f"{buildings[building_id].get('name', building_id)}: variant {letter.upper()} ({model})")
	new_text = "\n".join(lines)
	json.loads(new_text)  # never write a broken file
	STUDIO.write_text(new_text, encoding="utf-8", newline="\n")
	for problem in problems:
		print("NOT APPLIED - " + problem)
	if len(problems) == len(picks):
		sys.exit(1)


main()
