---
name: building-sprites
description: Design building sprites in Blender for this island game. Writes a model script with 2-3 design variants (A main, B other colours and props, C other layout or roof), builds them, shows them on the Building Encyclopedia web page for the user to pick, then puts the picks into the game. Use when the user asks to make, design, model or redo a building sprite, picture, model or art, asks for the next art batch ("Batch B", "Batch C"), says "apply picks ...", or wants to see or rebuild the encyclopedia. For a brand-new building that isn't in data/buildings.json yet, use add-building first.
argument-hint: <building ids | batch letter | apply picks id=b ...>
---

# Building sprites: Blender model → variants → encyclopedia → game

The user isn't a coder: talk in plain words and give clickable file links. This job repeats, so keep
it cheap: read only what this skill names, look at one review picture per batch, and let the scripts
do the mechanical work.

Commands below use `B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"` and
`G="/c/Program Files/Godot/Godot.exe.exe"` (Git Bash).

## 0. Which job?
- The user pasted **"apply picks dairy=b ..."** → go to step 5.
- Building ids, a batch letter, or "the next batch" → step 1. The batches and each building's brief
  are in [briefs.md](briefs.md); read only the entries you need.
- The building isn't in `data/buildings.json` → run the `add-building` skill first.
- One of the 11 buildings made before variants (no `VARIANTS` in its script) → give it variants
  only if the user asks; keep its current design as variant A.

## 1. Read only this
- [kit-cheatsheet.md](kit-cheatsheet.md): helpers, colour names, which sides the player sees,
  sizes, the variant template and known traps. Don't open `kit.py`, `build.py` or `art/README.md`.
- The building's `size`: `grep -A4 '"<id>": {' data/buildings.json | grep -o '"size": [0-9]'`
  (nothing printed = 1). The model's `TILES` must match it.
- Only if the cheat-sheet lacks a pattern (awning, dormer, crane, sails), open the one model that
  has it: bakery.py, city_hall.py, construction_office.py, flour_mill.py, warehouse.py, wheat_farm.py
  in `art/blender/models/`.

## 2. Write the model
`art/blender/models/<id>.py` with `TILES`, a `VARIANTS` dict of plain values and `build(v)`, as in
the cheat-sheet's template: A = the brief's main design, B = same layout with other colours and 1-2
other props, C = another layout or roof. Same footprint and signature prop in all three. Each
variant's `name` (1-3 words) and `note` (one plain sentence) are what the user judges by on the page.

## 3. Build and check
1. One Blender run per building builds every variant:
   `"$B" -b --factory-startup --python art/blender/build.py -- <id> 2>&1 | grep -iE "error|traceback|line [0-9]+|preview ->"`
   A Python error names the line: fix it and run again.
2. One review sheet for the whole batch, one building per row, then Read **only that picture**:
   `"$B" -b --factory-startup --python art/blender/sheet.py -- review <id>-a <id>-b <id>-c <id2>-a ... 2>&1 | grep "sheet:"`
   → `art/previews/review.png`
3. Look for: parts floating or poking through each other, anything off the plot, the signature
   prop hidden, two variants that look alike, big dull or dark areas (more in the cheat-sheet's traps).
   Fix and rebuild only the broken letters (`... build.py -- <id> b`). At most two fix rounds; after
   that, tell the user what still looks off.

## 4. Show the user, then wait
1. `python tools/encyclopedia.py`, then PowerShell: `Start-Process "art\encyclopedia\index.html"`.
2. Tell the user: on the page, open **Needs a pick**, click **Use this one** on the variant they like
   for each building (they can zoom any picture), then **Copy my picks** and paste the line here.
   Stop and wait for it.

## 5. Apply the picks
1. `python tools/apply_picks.py "<the pasted line>"`. A "NOT APPLIED" line names the problem
   (usually a variant that wasn't built: build it, run again).
2. Sprite studio, then the import (commands in CLAUDE.md). The studio opens a window for about a
   minute; append `2>&1 | grep -iE "error|studio:"`. If it prints nothing and doesn't end, read the
   newest file in `%APPDATA%/Godot/app_userdata/Company Sim (working title)/logs/` for the error.
3. `python tools/encyclopedia.py` again (the picks now show "In the game ✓").
4. `"$G" --headless --path . -s tests/check_project.gd`: 0 problems; the "no sprite yet" note for
   each picked building is gone.

## Finish
1. Update the pack-status table in `art/README.md`, and plan.md §4's batch list (✅ when a batch's
   picks are in the game) plus one Revision Log line per batch.
2. Tell the user: which variant each building got, the files changed (model scripts,
   `tools/sprite_studio.json`, `assets/buildings/`), and what's next (the next batch). Don't commit
   unless asked.

## Notes
- `art/models/`, `art/previews/` and `art/encyclopedia/` are generated and not in Git; rebuild them.
  The real art is the model scripts plus `assets/buildings/*.png` and `sprites.json` (written by the
  studio; never edit by hand).
- To change one variant after the user's feedback: edit its settings or branch, rebuild only that
  letter, then sheet + encyclopedia again.
- Python edit scripts with tricky quotes break inside Bash heredocs here: write them to the
  scratchpad and run them. Never edit `data/*.json` with PowerShell Get/Set-Content (it breaks UTF-8).
