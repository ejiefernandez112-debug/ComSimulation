"""BUILDING ENCYCLOPEDIA: one web page with every building, its picture in the game now, and the
design variants made in Blender, so the user can pick which variant the game uses.

	python tools/encyclopedia.py            (then open art/encyclopedia/index.html in a browser)

Reads data/buildings.json (names, sizes, what they make), tools/sprite_studio.json (which model
each building uses now), the VARIANTS in art/blender/models/<id>.py (letters, names, notes), the
previews in art/previews/ and the game pictures in assets/buildings/. Writes one self-contained
page; nothing else changes. Picks made on the page stay in that browser; "Copy my picks" gives the
line to apply them (tools/apply_picks.py, the building-sprites skill).
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
		})
	data = json.dumps({"made": time.strftime("%Y-%m-%d %H:%M"), "buildings": entries, "tabs": list(tabs.values())})
	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(PAGE.replace("__DATA__", data.replace("</", "<\\/")), encoding="utf-8")
	counts = {s: sum(1 for e in entries if e["status"] == s) for s in ("pick", "done", "none")}
	print(f"Encyclopedia: {len(entries)} buildings ({counts['pick']} need a pick, {counts['done']} done, "
		f"{counts['none']} without art) -> {OUT.relative_to(ROOT).as_posix()}")


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
main { max-width: 1240px; margin: 0 auto; padding: 16px; display: grid; gap: 16px; }
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
.desc { margin: 6px 0 2px; }
.makes { color: var(--muted); font-size: 14px; }
.row { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 12px; align-items: stretch; }
.now { flex: 0 0 190px; background: var(--sand); border-radius: 14px; padding: 10px; text-align: center;
	display: flex; flex-direction: column; justify-content: space-between; }
.now .label { font-size: 13px; color: var(--muted); }
.now .stage { display: flex; align-items: center; justify-content: center; min-height: 120px; }
.variant { flex: 1 1 260px; max-width: 340px; border: 3px solid var(--edge); border-radius: 14px; padding: 8px;
	background: #fff; display: flex; flex-direction: column; gap: 6px; }
.variant.picked { border-color: var(--honey-dark); box-shadow: 0 0 0 3px var(--honey); }
.variant.ingame { border-color: var(--go); }
.variant img, .solo img { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 10px; cursor: zoom-in; background: #7cba5a; }
.variant h3 { margin: 0; font-size: 17px; }
.variant p { margin: 0; font-size: 14px; color: var(--muted); flex: 1; }
.solo { flex: 0 1 260px; }
.empty { color: var(--muted); font-style: italic; align-self: center; }
#zoom { position: fixed; inset: 0; background: rgba(40, 22, 8, 0.82); display: none; align-items: center;
	justify-content: center; z-index: 10; cursor: zoom-out; padding: 16px; }
#zoom img { max-width: 100%; max-height: 100%; border-radius: 12px; }
footer { text-align: center; color: var(--muted); font-size: 13px; padding: 10px 16px 30px; }
@media (max-width: 640px) { .bar { margin-left: 0; } .now { flex-basis: 100%; } .variant { max-width: none; } }
</style>
</head>
<body>
<header>
	<h1>Building Encyclopedia</h1>
	<span class="counts" id="counts"></span>
	<div class="bar">
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

function card(b) {
	const top = el("div", { class: "top" }, el("h2", {}, b.name),
		el("span", { class: "pill status-" + b.status }, STATUS[b.status]),
		el("span", { class: "pill" }, b.size + "×" + b.size), el("span", { class: "pill" }, b.tab));
	const now = el("div", { class: "now" }, el("div", { class: "label" }, "In the game now"));
	const stage = el("div", { class: "stage" });
	if (b.sprite) {
		const img = el("img", { src: b.sprite, alt: b.name + " in the game" });
		img.addEventListener("load", () => { img.style.width = Math.round(img.naturalWidth * 0.8) + "px"; });
		stage.append(img);
	} else stage.append(el("span", { class: "empty" }, "a plain box"));
	now.append(stage, el("div", { class: "label" }, b.sprite ? (b.standin ? "borrowed stand-in" : "real size, zoomed in") : "no picture yet"));
	const row = el("div", { class: "row" }, now);
	if (b.variants.length) {
		for (const v of b.variants) {
			const picked = picks[b.id] === v.letter;
			const inGame = b.in_game === v.letter;
			const box = el("div", { class: "variant" + (picked ? " picked" : "") + (inGame ? " ingame" : "") },
				v.preview ? zoomable(v.preview, b.name + " variant " + v.letter) : el("span", { class: "empty" }, "not built yet"),
				el("h3", {}, v.letter.toUpperCase() + (v.name ? " · " + v.name : "")),
				el("p", {}, v.note || ""));
			const button = el("button", { class: inGame ? "chip on" : (picked ? "button" : "chip"), onclick: () => {
				if (picks[b.id] === v.letter || inGame) delete picks[b.id]; else picks[b.id] = v.letter;
				save(); render();
			} }, inGame ? "In the game ✓" : (picked ? "Picked ✓" : "Use this one"));
			if (inGame) button.disabled = true;
			box.append(button);
			row.append(box);
		}
	} else if (b.preview) {
		row.append(el("div", { class: "solo variant" }, zoomable(b.preview, b.name + " model"), el("h3", {}, "One design"),
			el("p", {}, "Made before variants existed. Ask Claude for variants of it if you'd like a choice.")));
	} else {
		row.append(el("span", { class: "empty" }, b.status === "none" ? "No Blender design yet: it's in a later batch." : ""));
	}
	return el("div", { class: "card" }, top, el("p", { class: "desc" }, b.description),
		b.makes.length ? el("div", { class: "makes" }, "Makes: " + b.makes.join(", ")) : null, row);
}

function render() {
	const tab = document.getElementById("tab").value;
	const words = document.getElementById("search").value.trim().toLowerCase();
	const list = document.getElementById("list");
	list.replaceChildren();
	const shown = DATA.buildings.filter(b => (filter === "all" || b.status === filter) && (!tab || b.tab === tab)
		&& (!words || (b.name + " " + b.description + " " + b.makes.join(" ")).toLowerCase().includes(words)));
	for (const b of shown) list.append(card(b));
	if (!shown.length) list.append(el("p", { class: "empty" }, "Nothing here."));
	const n = s => DATA.buildings.filter(b => b.status === s).length;
	document.getElementById("counts").textContent = `${DATA.buildings.length} buildings · ${n("pick")} need a pick · ${n("done")} done · ${n("none")} no art yet`;
	const line = Object.entries(picks).map(([id, l]) => id + "=" + l).join(" ");
	document.getElementById("copy").disabled = !line;
	document.getElementById("paste").style.display = line ? "block" : "none";
	document.getElementById("line").textContent = "apply picks " + line;
}

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
