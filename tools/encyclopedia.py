"""BUILDING ENCYCLOPEDIA: one web page with every building, its picture in the game now, and the
design variants made in Blender, so the user can pick which variant the game uses.

	python tools/encyclopedia.py            (then open art/encyclopedia/index.html in a browser)

Reads data/buildings.json (names, sizes, what they make), tools/sprite_studio.json (which model
each building uses now), the VARIANTS in art/blender/models/<id>.py (letters, names, notes), the
previews in art/previews/ and the game pictures in assets/buildings/.

Every building gets the same wiki card, in the same order: name; an infobox with its picture in
the game and the same rows for all (category, description, size, availability, workers,
electricity, water, road, build cost; infobox_of); the build and upgrade table (levels_of); the
extra sections only some have (production, selling, housing, storage, ...; more_info_of); its
features from tools/encyclopedia_notes.json (built, on trial, planned, idea); and its Blender
design variants, folded away unless it needs a pick. A second view, "Game systems" (population, happiness, ...), shows the same for the rules
that aren't buildings: their numbers from data/game_config.json (SYSTEM_FACTS below) and their
feature lists from the notes' "systems". Writes one self-contained page; nothing else changes.
Picks made on the page stay in that browser; "Copy my picks" gives the line to apply them (tools/apply_picks.py, the building-sprites skill).
"""
import ast
import json
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "encyclopedia" / "index.html"


def load(path: str) -> dict:
	return json.loads((ROOT / path).read_text(encoding="utf-8"))


def variants_of(building_id: str) -> list:
	"""[{"letter", "name", "note"}] from the model script's VARIANTS (a plain dict), or []."""
	script = ROOT / "art" / "blender" / "models" / f"{building_id}.py"
	if not script.exists():
		return []
	for node in ast.parse(script.read_text(encoding="utf-8")).body:
		if isinstance(node, ast.Assign) and any(getattr(t, "id", "") == "VARIANTS" for t in node.targets):
			try:
				found = ast.literal_eval(node.value)
			except ValueError:  # settings that aren't plain values: keep just the letters
				found = {ast.literal_eval(k): {} for k in node.value.keys}
			return [{"letter": letter, "name": str(s.get("name", "")), "note": str(s.get("note", ""))}
				for letter, s in found.items()]
	return []


def money(dollars: float) -> str:
	return f"${dollars:,.0f}"


def number(value) -> str:
	return f"{value:,g}" if isinstance(value, (int, float)) else str(value)


def duration(seconds: float) -> str:
	"""10 -> "10 s", 1800 -> "30 min", 3600 -> "1 h", 9000 -> "2 h 30 min"."""
	seconds = int(seconds)
	if seconds < 60:
		return f"{seconds} s"
	if seconds < 3600:
		return f"{seconds // 60} min"
	return f"{seconds // 3600} h" + (f" {seconds % 3600 // 60} min" if seconds % 3600 >= 60 else "")


def pct(share: float) -> str:
	return f"{round(share * 100)}%"


def per_level(b: dict, key: str) -> str:
	"""A number that upgrades change: "4 at Level 1, then 5 / 6 / 7 at Level 2 / 3 / 4"."""
	more = [number(u[key]) for u in b.get("upgrades", []) if key in u]
	text = f"{number(b[key])} at Level 1"
	if more:
		text += f", then {' / '.join(more)} at Level {' / '.join(str(i + 2) for i in range(len(more)))}"
	return text


# The words shown for a building's category, and for the numbers an upgrade changes.
CATEGORY_NAMES = {
	"civic": "Civic", "construction": "Construction", "extractor": "Extractor (grows or raises goods)",
	"processor": "Processor (turns goods into other goods)", "retail": "Retail (sells to the village)",
	"residential": "Residential (homes)", "storage": "Storage", "power": "Power", "utility": "Utility",
	"trade": "Trade",
}
CHANGE_NAMES = {
	"max_workers": "{} workers", "capacity": "room for {}", "shelves": "{} shelves", "households": "{} households",
	"power_supply": "makes {} MW", "power_radius": "power reaches {} tiles", "water_supply": "cleans {} m³/h",
}


def levels_of(b: dict, cfg: dict, resources: dict) -> list:
	"""Building (Level 1) and each upgrade: time, crew, materials, cost and what it changes, worked
	out the way Simulation.construction_needs / construction_seconds / _quote do, at base prices
	(the game's material prices swing by up to price_swing every hour). Labor is labor_share of the
	materials' value."""
	if not b.get("materials"):
		return []
	con = cfg.get("construction", {})
	growth = max(float(con.get("level_growth", 1)), 1.0)
	times = con.get("level_seconds", [])
	swing = float(con.get("price_swing", 0))
	share = min(max(float(con.get("labor_share", 0)), 0.0), 1.0)
	upgrades = b.get("upgrades", [])
	rows = []
	for level in range(1, len(upgrades) + 2):
		factor = growth ** (level - 1)
		amounts = {m: round(q * factor) for m, q in b["materials"].items()}
		crew = float(b.get("crew", con.get("crew", 0)))
		if "crew_per_level" in con:
			crew = round(crew + float(con["crew_per_level"]) * (level - 1))
		else:
			crew = round(crew * factor)
		seconds = float(times[min(level, len(times)) - 1]) if times else 0.0
		if level == 1 and "build_time" in b:
			seconds = float(b["build_time"])
		changes = {} if level == 1 else upgrades[level - 2]
		if "time" in changes:
			seconds = float(changes["time"])
		materials = sum(q * float(resources.get(m, {}).get("price", 0)) for m, q in amounts.items())
		rows.append({
			"level": level, "time": duration(seconds), "crew": crew,
			"materials": ", ".join(f"{q:,} {resources.get(m, {}).get('name', m)}" for m, q in amounts.items()),
			"value": materials * (1 + share),
			"cost": money(materials * (1 + share)),
			"range": money(materials * (1 - swing) * (1 + share)) + " – " + money(materials * (1 + swing) * (1 + share)),
			"changes": ", ".join(CHANGE_NAMES.get(k, k.replace("_", " ") + " {}").format(number(v))
				for k, v in changes.items() if k != "time"),
		})
	return rows


def infobox_of(b: dict, cfg: dict, tab: str, starts: int, levels: list) -> list:
	"""The rows every card shows, always the same ones in the same order: [label, text]."""
	workers = int(b.get("max_workers", 0))
	home = "households" in b
	where = f"Build menu: {tab}" if tab else "not in the Build menu"
	available = []
	if starts:
		available.append(f"{starts} already built in a new game")
	if b.get("hut"):
		available.append("appears by itself for each homeless household and goes when they get a home")
	elif b.get("coming_soon"):
		available.append(f"greyed out in the Build menu for now: {b['coming_soon']}")
	elif b.get("buildable"):
		available.append("you can build it" + (f", at most {b['max_count']} per village" if b.get("max_count") else ""))
	else:
		available.append("can't be built or demolished")
	if workers:
		kind = cfg["worker_types"].get(b.get("worker_type", "low_skilled"), {})
		staff = "always this many" if b.get("fixed_workers") else "you pick Low / Medium / High staffing"
		wage = "the minimum wage only" if b.get("fixed_wage") else "a wage bonus per batch (more units)"
		team = f"{workers} {kind.get('name', '').lower()} at ${kind.get('wage_per_hour', 0)}/h; {staff}; {wage}"
		if b.get("staffed_first"):
			team += "; hired before every other building"
	else:
		team = "None"
	power = []
	if b.get("power_mw"):
		power.append(f"uses {number(b['power_mw'])} MW " + ("while anyone lives there" if home else "while making a batch"))
	if b.get("power_supply"):
		power.append(f"makes {number(b['power_supply'])} MW" + (" (with all its workers)" if workers else ""))
	if b.get("grid_mw"):
		power.append(f"links to the public grid: up to {number(b['grid_mw'])} MW")
	if b.get("power_radius"):
		power.append(f"its power reaches {b['power_radius']} tiles around it")
	water = []
	if b.get("water_per_hour"):
		water.append(f"uses {number(b['water_per_hour'])} m³ an hour while making a batch")
	if b.get("water_supply"):
		water.append(f"cleans {number(b['water_supply'])} m³ an hour (with all its workers) for your buildings")
	if b.get("road_hub"):
		road = "every road starts here"
	elif workers:
		road = "needs a road linked to City Hall, or it gets no workers"
	else:
		road = "not needed (no workers)"
	if levels:
		cost = f"{levels[0]['cost']} at normal prices ({levels[0]['range']}), takes {levels[0]['time']}"
	else:
		cost = "free" if b.get("hut") else "– (can't be built)"
	return [
		["Category", f"{CATEGORY_NAMES.get(b.get('category', ''), b.get('category', ''))} · {where}"],
		["Description", b.get("description", "")],
		["Size", f"{b.get('size', 1)}×{b.get('size', 1)} tiles" if b.get("size", 1) > 1 else "1×1 (one tile)"],
		["Availability", "; ".join(available)],
		["Workers", team],
		["Electricity", "; ".join(power) if power else "None"],
		["Water", "; ".join(water) if water else "None"],
		["Road", road],
		["Build cost", cost],
	]


def more_info_of(b: dict, cfg: dict, resources: dict, levels: list) -> list:
	"""The extra sections that only some buildings have: [{"title", "rows"?, "head"?, "table"?}]."""
	def items(amounts: dict) -> str:
		return ", ".join(f"{number(q)} {resources.get(r, {}).get('name', r)}" for r, q in amounts.items()) or "nothing"

	sections = []
	recipes = b.get("recipes", [])
	if recipes:
		table = [[resources.get(next(iter(r["outputs"]), ""), {}).get("name", r.get("id", "")),
			items(r.get("inputs", {})), items(r.get("outputs", {}))] for r in recipes]
		rows = []
		if len(recipes) > 1:
			rows.append(["Products", f"{len(recipes)} to choose from; set up for one at a time (its first batch picks it, free)"])
			if b.get("switch_fee"):
				fee = float(b["switch_fee"])
				value = levels[0]["value"] if levels else 0
				rows.append(["Switching", f"while it has no batch, for {pct(fee)} of what it's worth (≈ {money(value * fee)} at Level 1)"])
			else:
				rows.append(["Switching", "keeps its product for good: build another one to make something else"])
		rows.append(["Batches", "you choose how many hours (each hour of work makes the amounts below)"])
		sections.append({"title": "Production", "rows": rows,
			"head": ["Product", "Uses (per hour of work)", "Makes (per hour of work)"], "table": table})
	if "shelves" in b or b.get("sells"):
		cats = b.get("sells", [])
		names = [r.get("name", k) for k, r in resources.items()
			if isinstance(r, dict) and r.get("category") in cats and r.get("appetite")]
		cat_names = ", ".join(cfg.get("item_categories", {}).get(c, {}).get("name", c) for c in cats)
		retail = cfg.get("retail", {})
		rows = [["Shelves", per_level(b, "shelves")] if "shelves" in b else None,
			["Sells", f"{cat_names}: {len(names)} items ({', '.join(names)})"],
			["Price tags", " · ".join(f"{t['name']} {round((t['price'] - 1) * 100):+d}% → {number(t['speed'])}× as fast"
				for t in retail.get("price_tags", {}).values())]]
		if retail.get("variety_bonus"):
			rows.append(["Variety bonus", f"+{pct(retail['variety_bonus'])} shoppers for each different product beyond the first"])
		sections.append({"title": "Selling", "rows": [r for r in rows if r]})
	if "households" in b:
		names = {c["id"]: c["name"] for c in cfg.get("housing", {}).get("wealth_classes", [])}
		rent = float(b.get("rent_per_household", 0))
		sections.append({"title": "Housing", "rows": [
			["Households", per_level(b, "households")],
			["Who lives here", ", ".join(names.get(w, w) for w in b.get("wealth", [])) or "homeless households"],
			["Rent", f"${rent:g} an hour per household, paid to you" if rent else "free"],
		]})
	if "capacity" in b:
		sections.append({"title": "Storage", "rows": [["Room for goods", per_level(b, "capacity")],
			["Workers", "the room above is with all its workers; fewer workers = less room (2 of 4 = half)"]]})
	if b.get("construction_crew"):
		con = cfg.get("construction", {})
		sections.append({"title": "Construction", "rows": [["Construction workers", f"its workers are the village's construction workers. Building anything needs {con.get('crew', 1)} free; each upgrade level needs {con.get('crew_per_level', 0)} more. They're busy until the work is done"]]})
	if b.get("category") == "trade":
		trade = cfg.get("trade", {})
		sections.append({"title": "Trade", "rows": [
			["Buys from you", f"any item at {pct(trade.get('sell_share', 0))} of its normal price, at once (sales tax applies)"],
			["Sells to you", f"any item at {pct(trade.get('buy_share', 0))} of its normal price"],
		]})
	return sections


def population_facts(cfg: dict, buildings: dict) -> dict:
	life = cfg.get("life", {})
	housing = cfg.get("housing", {})
	every = int(cfg.get("population_growth_seconds", 0))
	arrive = f"a group of up to {cfg.get('move_in_group_size', 1)} adults every {every // 60} min{f' {every % 60} s' if every % 60 else ''} at normal speed"
	if cfg.get("move_in_only_for_jobs"):
		arrive += ", only while a job is open that nobody here can take"
	if not cfg.get("move_in_needs_home", True):
		arrive += "; they don't need a free home (huts)"
	birth = float(life.get("birth_rate_per_hour", 0))
	death = float(life.get("death_rate_per_hour", 0))
	facts = [
		["Start", f"{cfg.get('starting_population', 0)} adults"],
		["Newcomers", arrive],
		["Births", f"{birth} babies an hour for each adult (100 adults ≈ {round(birth * 100)} an hour), times the birth speed from happiness"],
		["Growing up", f"{life.get('grow_up_hours', 0)} hours after birth"],
		["Deaths", f"{death * 100:g}% of people an hour (an average life of about {round(1 / death) if death else 0} hours)" if death else "none"],
		["Household", f"up to {housing.get('adults_per_household', 0)} adults + {housing.get('children_per_household', 0)} children"],
		["Affordable home", f"rent at most {pct(float(housing.get('rent_share', 0)))} of the household's wages"],
	]
	classes = housing.get("wealth_classes", [])
	wealth_rows = []
	for i, c in enumerate(classes):
		top = classes[i + 1]["from_wage"] if i + 1 < len(classes) else None
		start = "a job" if c["from_wage"] < 1 else f"${c['from_wage']:g}/h"
		wage = "no job" if c["from_wage"] == 0 else start + (f", under ${top:g}/h" if top else " and more")
		wealth_rows.append([c["name"], wage])
	names = {c["id"]: c["name"] for c in classes}
	home_rows = []
	for b in buildings.values():
		if isinstance(b, dict) and "households" in b:
			home_rows.append([b.get("name", ""), str(b["households"]),
				", ".join(names.get(w, w) for w in b.get("wealth", [])) or "anyone (homeless)",
				f"${b.get('rent_per_household', 0):g}/h" if b.get("rent_per_household") else "free",
				f"{b.get('power_mw', 0):g} MW"])
	return {"facts": facts, "tables": [
		{"title": "Wealth classes (from the wage)", "head": ["Class", "Wage"], "rows": wealth_rows},
		{"title": "Homes", "head": ["Home", "Households", "For", "Rent per household", "Power when lived in"], "rows": home_rows},
	]}


def happiness_facts(cfg: dict, buildings: dict) -> dict:
	h = cfg.get("happiness", {})
	needs = h.get("needs", {})
	weights = h.get("weights", {})
	total = sum(weights.values()) or 1
	scores = needs.get("food", {}).get("scores", [])
	name = lambda need: needs.get(need, {}).get("name", need.title())
	safety = needs.get("safety", {})
	facts = [
		["Mix (everyone)", ", ".join(f"{name(k)} {pct(v / total)}" for k, v in weights.items())],
		["Jobs quality by wage bonus", ", ".join(f"{k} {pct(v)}" for k, v in needs.get("jobs", {}).get("quality", {}).items())],
		["A home without power", f"counts {pct(needs.get('housing', {}).get('unpowered', 1))} of its quality"],
		["Crime", f"{pct(safety.get('crime', 0))} + {pct(safety.get('crime_per_jobless', 0))} × the jobless share + {pct(safety.get('crime_per_homeless', 0))} × the share in huts"],
		["Content when needs met = expected", pct(h.get("content_at", 0.5))],
		["People leave in groups of", str(h.get("leave_group_size", 1))],
	]
	food = [[str(i) + ("+" if i == len(scores) - 1 else ""), pct(v)] for i, v in enumerate(scores)]
	expect = [[str(p["people"]), pct(p["expected"])] for p in h.get("expectations", [])]
	homes = [[b.get("name", ""), pct(b["housing_quality"])] for b in buildings.values() if isinstance(b, dict) and "housing_quality" in b]
	classes = [[c, ", ".join(f"{name(k)} {v:g}" for k, v in w.items())] for c, w in h.get("class_weights", {}).items()]
	bands = h.get("growth_speeds", [])
	band_rows = []
	for i, band in enumerate(bands):
		top = bands[i + 1]["from"] if i + 1 < len(bands) else 1.0
		move = band.get("move_in", band.get("speed", 0))
		# Who leaves: adults only while jobless (plus workers in huts with homeless_workers_leave);
		# children at their own share (the adults' when left out).
		adults = band.get("leave_per_hour", 0)
		children = band.get("children_leave_per_hour", adults)
		who = []
		if adults:
			who.append(f"jobless adults{' + workers in huts' if band.get('homeless_workers_leave') else ''} {pct(adults)} an hour")
		if children:
			who.append(f"children {pct(children)} an hour")
		band_rows.append([f"{pct(band['from'])} – {round(top * 100) - (1 if i + 1 < len(bands) else 0)}%",
			f"×{band.get('speed', 0):g}" if band.get("speed") else "no babies",
			f"×{move:g}" if move else "nobody comes",
			", ".join(who) if who else "nobody"])
	return {"facts": facts, "tables": [
		{"title": "Food need: different foods selling", "head": ["Foods", "Food need"], "rows": food},
		{"title": "Housing quality", "head": ["Home", "Quality"], "rows": homes},
		{"title": "Each wealth class's weights", "head": ["Class", "Weights"], "rows": classes},
		{"title": "What people expect", "head": ["People", "Expected"], "rows": expect},
		{"title": "What happiness does", "head": ["Happiness", "Births", "Job seekers", "People leaving"], "rows": list(reversed(band_rows))},
	]}


# Each game system's numbers, read from the data so the page never goes stale.
SYSTEM_FACTS = {"population": population_facts, "happiness": happiness_facts}


def picture(path: Path) -> str:
	"""A link to a picture from the page, with its change time so a rebuilt picture shows up."""
	if not path.exists():
		return ""
	return f"{Path('../..', path.relative_to(ROOT)).as_posix()}?v={int(path.stat().st_mtime)}"


def main():
	buildings = load("data/buildings.json")
	resources = load("data/resources.json")
	tabs = {t["id"]: t["name"] for t in load("data/build_menu.json")["tabs"]}
	studio = load("tools/sprite_studio.json")["buildings"]
	cfg = load("data/game_config.json")
	notes = load("tools/encyclopedia_notes.json")
	starts = [s["type"] for s in cfg.get("starting_buildings", [])]
	entries = []
	for building_id, b in buildings.items():
		if building_id.startswith("_") or not isinstance(b, dict):
			continue
		made = []
		for recipe in b.get("recipes", []):
			for res in recipe.get("outputs", {}):
				name = resources.get(res, {}).get("name", res)
				if name not in made:
					made.append(name)
		levels = levels_of(b, cfg, resources)
		setup = studio.get(building_id, {})
		own = setup.get("kit_folder") == "art/models"
		model = str(setup.get("model", ""))
		variants = variants_of(building_id)
		for v in variants:
			v["preview"] = picture(ROOT / "art" / "previews" / f"{building_id}-{v['letter']}.png")
		in_game = next((v["letter"] for v in variants if model == f"{building_id}-{v['letter']}.glb"), "")
		if variants:
			status = "done" if in_game else "pick"
		elif own:
			status = "done"
		else:
			status = "none"
		entries.append({
			"id": building_id, "name": b.get("name", building_id), "category": b.get("category", ""),
			"tab": tabs.get(b.get("menu_tab", ""), "Not in the Build menu"), "size": int(b.get("size", 1)),
			"description": b.get("description", ""), "makes": made, "status": status,
			"standin": bool(setup) and not own, "in_game": in_game, "variants": variants,
			"sprite": picture(ROOT / "assets" / "buildings" / f"{building_id}.png"),
			"preview": picture(ROOT / "art" / "previews" / f"{building_id}.png") if own and not variants else "",
			"infobox": infobox_of(b, cfg, tabs.get(b.get("menu_tab", ""), ""), starts.count(building_id), levels),
			"levels": levels, "sections": more_info_of(b, cfg, resources, levels), "notes": notes.get(building_id, {}),
		})
	systems = []
	for system_id, n in notes.get("systems", {}).items():
		found = SYSTEM_FACTS.get(system_id, lambda c, b: {"facts": [], "tables": []})(cfg, buildings)
		systems.append({"id": system_id, "name": n.get("name", system_id), "notes": n, **found})
	data = json.dumps({"made": time.strftime("%Y-%m-%d %H:%M"), "buildings": entries, "systems": systems,
		"tabs": list(tabs.values())})
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(PAGE.replace("__DATA__", data.replace("</", "<\\/")), encoding="utf-8")
	counts = {s: sum(1 for e in entries if e["status"] == s) for s in ("pick", "done", "none")}
	print(f"Encyclopedia: {len(entries)} buildings ({counts['pick']} need a pick, {counts['done']} done, "
		f"{counts['none']} without art), {len(systems)} game systems -> {OUT.relative_to(ROOT).as_posix()}")


PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Building Encyclopedia</title>
<style>
@font-face { font-family: Fredoka; src: url("../../assets/fonts/Fredoka.ttf"); }
:root {
	--cream: #fff8e9; --sand: #f7e5c1; --edge: #e0be83; --caramel: #d9a066; --brown: #8a5a2b;
	--honey: #f6b13f; --honey-dark: #8e5312; --text: #5a3618; --muted: #85623f; --heading: #8e4f14;
	--go: #3f8a2a; --go-soft: #e3f2d6; --warn: #c23b2c; --warn-soft: #fbe3dc; --card: #fffdf6;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--cream); color: var(--text); font: 16px/1.45 Fredoka, "Segoe UI", sans-serif; }
header { position: sticky; top: 0; z-index: 5; background: var(--sand); border-bottom: 3px solid var(--edge);
	padding: 12px 16px; display: flex; flex-wrap: wrap; gap: 10px 16px; align-items: center; }
h1 { margin: 0; font-size: 26px; color: var(--heading); }
.counts { color: var(--muted); font-size: 14px; }
.bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-left: auto; }
.chip, select, input, .button { font: inherit; border-radius: 999px; border: 2px solid var(--edge);
	background: var(--card); color: var(--text); padding: 5px 14px; cursor: pointer; }
input { cursor: text; width: 150px; }
.chip.on { background: var(--honey); border-color: var(--honey-dark); color: #4a2a08; }
.button { background: var(--honey); border-color: var(--honey-dark); font-weight: 600; }
.button:disabled { opacity: 0.45; cursor: default; }
main { max-width: 1240px; margin: 0 auto; padding: 16px; display: grid; grid-template-columns: minmax(0, 1fr); gap: 16px; }
.paste { background: var(--go-soft); border: 2px dashed var(--go); border-radius: 14px; padding: 10px 14px; display: none; }
.paste code { font-size: 15px; user-select: all; }
.card { background: var(--card); border: 3px solid var(--edge); border-radius: 18px; padding: 14px 16px;
	box-shadow: 0 4px 0 rgba(122, 74, 31, 0.15); }
.top { display: flex; flex-wrap: wrap; gap: 6px 10px; align-items: baseline; }
.top h2 { margin: 0; font-size: 22px; color: var(--heading); }
.pill { font-size: 13px; padding: 1px 10px; border-radius: 999px; background: var(--sand); color: var(--muted); }
.status-pick { background: var(--honey); color: #4a2a08; }
.status-done { background: var(--go-soft); color: var(--go); }
.status-none { background: var(--warn-soft); color: var(--warn); }
#list { display: grid; gap: 16px; min-width: 0; }
.card { min-width: 0; }
.facts dd { overflow-wrap: anywhere; }
.infobox { display: grid; grid-template-columns: 240px minmax(0, 1fr); gap: 16px; margin-top: 12px; align-items: start; }
.row { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 12px; align-items: stretch; }
.now { background: var(--sand); border-radius: 14px; padding: 10px; text-align: center;
	display: flex; flex-direction: column; justify-content: space-between; }
.now .label { font-size: 13px; color: var(--muted); }
.now .stage { display: flex; align-items: center; justify-content: center; min-height: 170px; }
.now .stage img { max-width: 100%; cursor: zoom-in; }
.section { margin-top: 4px; }
.section h4, .card > h4 { margin: 16px 0 6px; color: var(--heading); font-size: 16px; border-bottom: 2px solid var(--sand); padding-bottom: 2px; }
details.variants { margin-top: 14px; }
details.variants > summary { cursor: pointer; font-weight: 600; color: var(--heading); }
.variant { flex: 1 1 260px; max-width: 340px; border: 3px solid var(--edge); border-radius: 14px; padding: 8px;
	background: #fff; display: flex; flex-direction: column; gap: 6px; }
.variant.picked { border-color: var(--honey-dark); box-shadow: 0 0 0 3px var(--honey); }
.variant.ingame { border-color: var(--go); }
.variant img, .solo img { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 10px; cursor: zoom-in; background: #7cba5a; }
.variant h3 { margin: 0; font-size: 17px; }
.variant p { margin: 0; font-size: 14px; color: var(--muted); flex: 1; }
.solo { flex: 0 1 260px; }
.empty { color: var(--muted); font-style: italic; align-self: center; }
.views { display: flex; gap: 8px; }
.system h2 { margin: 0; font-size: 24px; color: var(--heading); }
details.info { margin-top: 12px; border-top: 2px dashed var(--edge); padding-top: 8px; }
details.info > summary { cursor: pointer; font-weight: 600; color: var(--heading); }
.info h4, .card h4 { margin: 14px 0 6px; color: var(--heading); font-size: 16px; }
.info .summary { margin: 8px 0; }
.facts { display: grid; grid-template-columns: max-content 1fr; gap: 4px 14px; font-size: 14px; margin: 0; }
.facts dt { color: var(--muted); }
.facts dd { margin: 0; }
.scroll { overflow-x: auto; }
table { border-collapse: collapse; font-size: 14px; min-width: 560px; }
th, td { text-align: left; padding: 4px 10px; border-bottom: 1px solid var(--sand); vertical-align: top; }
th { color: var(--muted); font-weight: 600; }
.features { list-style: none; margin: 0; padding: 0; display: grid; gap: 5px; font-size: 14px; }
.features li { display: flex; gap: 8px; align-items: baseline; }
.features .pill { flex: 0 0 76px; text-align: center; }
.when { color: var(--muted); font-size: 12px; white-space: nowrap; }
.f-built { background: var(--go-soft); color: var(--go); }
.f-trial { background: #e1ecfb; color: #2c5c9a; }
.f-planned { background: var(--honey); color: #4a2a08; }
.f-idea { background: var(--warn-soft); color: var(--warn); }
.note { font-size: 13px; color: var(--muted); margin: 6px 0 0; }
.code { font-size: 13px; color: var(--muted); margin: 0; padding-left: 18px; }
@media (max-width: 640px) { .facts { grid-template-columns: 1fr; } .facts dd { margin-bottom: 6px; } }
#zoom { position: fixed; inset: 0; background: rgba(40, 22, 8, 0.82); display: none; align-items: center;
	justify-content: center; z-index: 10; cursor: zoom-out; padding: 16px; }
#zoom img { max-width: 100%; max-height: 100%; border-radius: 12px; }
footer { text-align: center; color: var(--muted); font-size: 13px; padding: 10px 16px 30px; }
@media (max-width: 640px) { .bar { margin-left: 0; } .infobox { grid-template-columns: minmax(0, 1fr); } .variant { max-width: none; } }
</style>
</head>
<body>
<header>
	<h1>Building Encyclopedia</h1>
	<span class="counts" id="counts"></span>
	<div class="views">
		<button class="chip on" data-view="buildings">Buildings</button>
		<button class="chip" data-view="systems">Game systems</button>
	</div>
	<div class="bar" id="bar">
		<button class="chip on" data-filter="all">All</button>
		<button class="chip" data-filter="pick">Needs a pick</button>
		<button class="chip" data-filter="done">Done</button>
		<button class="chip" data-filter="none">No art yet</button>
		<select id="tab"><option value="">Every tab</option></select>
		<input id="search" type="search" placeholder="Search">
		<button class="button" id="copy" disabled>Copy my picks</button>
	</div>
</header>
<main>
	<div class="paste" id="paste">Paste this to Claude to use your picks in the game: <code id="line"></code></div>
	<div id="list"></div>
</main>
<footer id="made"></footer>
<div id="zoom"><img alt=""></div>
<script type="application/json" id="data">__DATA__</script>
<script>
const DATA = JSON.parse(document.getElementById("data").textContent);
const STATUS = { pick: "Needs a pick", done: "Done", none: "No art yet" };
let picks = {};
try { picks = JSON.parse(localStorage.getItem("encyclopedia-picks") || "{}"); } catch (e) { picks = {}; }
// A pick that's already in the game needs nothing more.
for (const b of DATA.buildings) if (picks[b.id] && picks[b.id] === b.in_game) delete picks[b.id];
let filter = "all";

function save() { try { localStorage.setItem("encyclopedia-picks", JSON.stringify(picks)); } catch (e) {} }
function el(tag, attrs, ...kids) {
	const node = document.createElement(tag);
	for (const [k, v] of Object.entries(attrs || {})) {
		if (k === "class") node.className = v; else if (k.startsWith("on")) node.addEventListener(k.slice(2), v); else node.setAttribute(k, v);
	}
	for (const kid of kids) if (kid !== null && kid !== undefined) node.append(kid);
	return node;
}
function zoomable(src, alt) { return el("img", { src, alt, loading: "lazy", onclick: () => zoom(src) }); }
function zoom(src) { const z = document.getElementById("zoom"); z.querySelector("img").src = src; z.style.display = "flex"; }
document.getElementById("zoom").addEventListener("click", e => e.currentTarget.style.display = "none");

const FEATURE = { built: "Built", trial: "On trial", planned: "Planned", idea: "Idea" };
function featureCounts(b) {
	const n = {};
	for (const f of (b.notes.features || [])) n[f.status] = (n[f.status] || 0) + 1;
	return Object.keys(FEATURE).filter(k => n[k]).map(k => n[k] + " " + FEATURE[k].toLowerCase()).join(" · ");
}
function facts(rows) {
	const dl = el("dl", { class: "facts" });
	for (const [k, v] of rows) dl.append(el("dt", {}, k), el("dd", {}, v));
	return dl;
}
function table(head, rows) {
	const t = el("table", {}, el("tr", {}, ...head.map(h => el("th", {}, h))));
	for (const r of rows) t.append(el("tr", {}, ...r.map(c => el("td", {}, c))));
	return el("div", { class: "scroll" }, t);
}
// The hand-kept part: the feature list and where it lives in the code.
function features(notes) {
	const out = [];
	if ((notes.features || []).length) {
		const list = el("ul", { class: "features" });
		for (const f of notes.features) list.append(el("li", {}, el("span", { class: "pill f-" + f.status }, FEATURE[f.status] || f.status),
			el("span", {}, f.text, f.since ? el("span", { class: "when" }, "  since " + f.since) : null)));
		out.push(el("h4", {}, "Features" + (notes.plan ? " (" + notes.plan + ")" : "")), list);
	} else out.push(el("p", { class: "note" }, "No feature list yet: ask Claude to add one (tools/encyclopedia_notes.json)."));
	if ((notes.code || []).length) out.push(el("h4", {}, "Where it lives in the code"), el("ul", { class: "code" }, ...notes.code.map(c => el("li", {}, c))));
	return out;
}
function systemCard(sys) {
	const counts = featureCounts(sys);
	const box = el("div", { class: "card system info" }, el("div", { class: "top" }, el("h2", {}, sys.name),
		counts ? el("span", { class: "pill" }, counts) : null));
	if (sys.notes.summary) box.append(el("p", { class: "summary" }, sys.notes.summary));
	if (sys.facts.length) box.append(el("h4", {}, "From the game data"), facts(sys.facts));
	for (const t of sys.tables) box.append(el("h4", {}, t.title), table(t.head, t.rows));
	box.append(...features(sys.notes));
	return box;
}
let view = "buildings";
try { view = localStorage.getItem("encyclopedia-view") === "systems" ? "systems" : "buildings"; } catch (e) {}

// One wiki card, the same parts in the same order for every building.
function card(b) {
	const counts = featureCounts(b);
	const top = el("div", { class: "top" }, el("h2", {}, b.name),
		el("span", { class: "pill status-" + b.status }, "Art: " + STATUS[b.status]),
		counts ? el("span", { class: "pill" }, counts) : null);
	// The infobox: the picture in the game, and the same rows for every building.
	const stage = el("div", { class: "stage" });
	if (b.sprite) {
		const img = el("img", { src: b.sprite, alt: b.name + " in the game", onclick: () => zoom(b.sprite) });
		stage.append(img);
	} else stage.append(el("span", { class: "empty" }, "No picture yet"));
	const now = el("div", { class: "now" }, el("div", { class: "label" }, "In the game now"), stage,
		el("div", { class: "label" }, b.sprite ? (b.standin ? "a borrowed stand-in" : "its own art") : "a plain box in the game"));
	const box = el("div", { class: "card" }, top, el("div", { class: "infobox" }, now, facts(b.infobox)));
	if (b.notes.summary) box.append(el("p", { class: "summary" }, b.notes.summary));
	// Build and upgrade, always shown.
	box.append(el("h4", {}, "Build and upgrade"));
	if (b.levels.length) {
		box.append(table(["Level", "Takes", "Crew", "Materials needed", "Cost", "Cost range", "What changes"],
			b.levels.map(l => [l.level === 1 ? "1 (build)" : String(l.level), l.time, String(l.crew), l.materials, l.cost, l.range, l.changes || "–"])),
			el("p", { class: "note" }, "Cost = materials at their normal price + the construction crew's share. Materials already in your Warehouse are used first; the rest is bought at today's price, which changes every hour within the cost range."));
	} else box.append(el("p", { class: "note" }, "Can't be built or upgraded."));
	// The extra parts only some buildings have.
	for (const sec of b.sections) {
		const part = el("div", { class: "section" }, el("h4", {}, sec.title));
		if ((sec.rows || []).length) part.append(facts(sec.rows));
		if (sec.table) part.append(table(sec.head, sec.table));
		box.append(part);
	}
	box.append(...features(b.notes));
	// The Blender designs to pick from: folded away unless this building needs a pick.
	const designs = el("div", { class: "row" });
	if (b.variants.length) {
		for (const v of b.variants) {
			const picked = picks[b.id] === v.letter;
			const inGame = b.in_game === v.letter;
			const tile = el("div", { class: "variant" + (picked ? " picked" : "") + (inGame ? " ingame" : "") },
				v.preview ? zoomable(v.preview, b.name + " variant " + v.letter) : el("span", { class: "empty" }, "not built yet"),
				el("h3", {}, v.letter.toUpperCase() + (v.name ? " · " + v.name : "")),
				el("p", {}, v.note || ""));
			const button = el("button", { class: inGame ? "chip on" : (picked ? "button" : "chip"), onclick: () => {
				if (picks[b.id] === v.letter || inGame) delete picks[b.id]; else picks[b.id] = v.letter;
				save(); render();
			} }, inGame ? "In the game ✓" : (picked ? "Picked ✓" : "Use this one"));
			if (inGame) button.disabled = true;
			tile.append(button);
			designs.append(tile);
		}
	} else if (b.preview) {
		designs.append(el("div", { class: "solo variant" }, zoomable(b.preview, b.name + " model"), el("h3", {}, "One design"),
			el("p", {}, "Made before variants existed. Ask Claude for variants of it if you'd like a choice.")));
	} else designs.append(el("span", { class: "empty" }, "No Blender design yet: it's in a later batch."));
	const fold = el("details", { class: "variants" },
		el("summary", {}, "Design variants" + (b.variants.length ? " (" + b.variants.length + ")" : "")), designs);
	if (b.status === "pick") fold.open = true;
	box.append(fold);
	return box;
}

function render() {
	document.querySelectorAll("[data-view]").forEach(c => c.classList.toggle("on", c.dataset.view === view));
	document.getElementById("bar").style.display = view === "buildings" ? "" : "none";
	if (view === "systems") {
		document.getElementById("list").replaceChildren(...DATA.systems.map(systemCard));
		document.getElementById("counts").textContent = DATA.systems.length + " game systems";
		document.getElementById("paste").style.display = "none";
		return;
	}
	const tab = document.getElementById("tab").value;
	const words = document.getElementById("search").value.trim().toLowerCase();
	const list = document.getElementById("list");
	list.replaceChildren();
	const shown = DATA.buildings.filter(b => (filter === "all" || b.status === filter) && (!tab || b.tab === tab)
		&& (!words || [b.name, b.makes.join(" "), JSON.stringify(b.infobox), JSON.stringify(b.sections), (b.notes.features || []).map(f => f.text).join(" ")].join(" ").toLowerCase().includes(words)));
	for (const b of shown) list.append(card(b));
	if (!shown.length) list.append(el("p", { class: "empty" }, "Nothing here."));
	const n = s => DATA.buildings.filter(b => b.status === s).length;
	document.getElementById("counts").textContent = `${DATA.buildings.length} buildings · ${n("pick")} need a pick · ${n("done")} done · ${n("none")} no art yet`;
	const line = Object.entries(picks).map(([id, l]) => id + "=" + l).join(" ");
	document.getElementById("copy").disabled = !line;
	document.getElementById("paste").style.display = line ? "block" : "none";
	document.getElementById("line").textContent = "apply picks " + line;
}

for (const chip of document.querySelectorAll("[data-view]")) chip.addEventListener("click", () => {
	view = chip.dataset.view;
	try { localStorage.setItem("encyclopedia-view", view); } catch (e) {}
	render();
});
for (const chip of document.querySelectorAll("[data-filter]")) chip.addEventListener("click", () => {
	filter = chip.dataset.filter;
	document.querySelectorAll("[data-filter]").forEach(c => c.classList.toggle("on", c === chip));
	render();
});
const tabs = document.getElementById("tab");
for (const t of [...DATA.tabs, "Not in the Build menu"]) tabs.append(el("option", { value: t }, t));
tabs.addEventListener("change", render);
document.getElementById("search").addEventListener("input", render);
document.getElementById("copy").addEventListener("click", async () => {
	const text = document.getElementById("line").textContent;
	try { await navigator.clipboard.writeText(text); document.getElementById("copy").textContent = "Copied!"; }
	catch (e) { document.getElementById("copy").textContent = "Select the line below"; }
	setTimeout(() => document.getElementById("copy").textContent = "Copy my picks", 1500);
});
document.getElementById("made").textContent = "Made " + DATA.made + " by tools/encyclopedia.py. Rebuild it after new designs: python tools/encyclopedia.py";
render();
</script>
</body>
</html>
"""

main()
