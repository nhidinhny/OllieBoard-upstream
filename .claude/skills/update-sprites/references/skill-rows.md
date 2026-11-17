# Skill rows and redrawn rows from the current sprite

Use this when a character needs a NEW animation with a prop (a skill: yo-yo, dumbbell, sake...) or when rows of the main sheet are soft, ghosted or have lost their feet and must be drawn again. It works for any character that already has a sheet.

## Why start from the current sprite

Gemini invents its own proportions from a name or a model sheet (rounder, cuter, another outfit). Attaching frames of the sprite that is in the game and asking it to "copy its proportions" keeps the new art on-model. `gen_skill_prompts.py` cuts six frames of the current sheet (standing, seated, arms crossed, a skill, a run) onto magenta as the reference and writes the whole task.

Observed with Gemini (web app, Claude in Chrome):
- Send the reference with ONE short message ("This is the current in-game sprite of X. Describe it briefly."), wait for the description, then send the real request as the second message in the same chat. Text typed together with the upload was dropped, and without a request Gemini only describes the image.
- Ask for a grid (4 columns × 2 rows, 16:9), not one long row: the drawings come out about twice as large and the counts are right more often. 3 × 2 for six frames, 2 × 2 for four, 2 × 1 for two. If Gemini draws black divider lines, say so and redo it, or give the row an `inset`.
- Say "FULL BODY, both legs and shoes fully visible and sharp". Without it the legs fade out (old rows had socks that vanished).
- A prop must be drawn "identical and in the same place in every drawing"; otherwise it changes between frames. Check it.
- A request for a different expression ("sad", "tired") is not needed for skills: say "cheerful or content expressions only".
- Gemini adds a small sparkle in the bottom-right corner, sometimes over the figure. `build_skill_rows.py` removes it from the corner; look at the last drawing of every picture.
- It sometimes answers "something went wrong": use "Try again" in the same chat.

## Steps

1. `.venv/bin/python scripts/sprites/gen_skill_prompts.py <id> <name> --frames "…; …" [--pose "…"] [--prop "…"]` (add `--redo` for a row of the main sheet). It writes `build/sprites/<id>/skill-<name>/task.md` and `reference.png`.
2. Follow the task with the available browser tool, or hand it to the user. Save the displayed picture as `assets/skills/<id>_<name>.png` (or `assets/redo/<id>_<row>.png` with `--redo`). Same rules as the strip workflow: inspect the saved file, no page screenshots, retry at most twice.
3. Add the row to `scripts/sprites/skill_rows.json` (options are described in its `_doc`: `height`, `anchor`, `cx` + `shift`, `grid`, `frames`, `level`, `head_norm`, `loop`, `inset`, `glow`).
4. `.venv/bin/python scripts/sprites/build_skill_rows.py <id>` (or `--redo <id>` for main-sheet rows). It prints every drawing's box and flags the ones that touch the cell edge; look at the result in the app or in a contact sheet with the ground line drawn at y = 244.

## What the builder does

- Keys out the magenta without a pink fringe (edge pixels take the colour of the solid pixels next to them; `glow` turns the pink halo of lightning back into yellow), removes the corner sparkle, and cuts the grid.
- One scale per row from the median drawing height, the drawings keep their place relative to each other (a prop that must not move does not move), the median lowest pixel goes to the ground line (`level` stands every drawing on it).
- `head_norm` is for a body that changes a lot (a belly that swells up): every drawing is scaled so the head keeps the width it has in the first drawing, the body hangs below.
- `cx` and `shift`: a prop that sticks out to the right makes the figure+prop wider than the cell if the character stands in the middle. Put the figure left of the middle (`cx`, px in the cell) and give the row the matching `shift` (points, towards the facing direction): the sprite is nudged back at run time so the character still stands on the pet's spot.
- Skin is graded to the game's tone with `assemble.py`'s `grade_skin`, like a normal sheet.

## In the app

- `<id>-skills.png` has one 256 px row per skill; `skills.json` lists the rows per id: `name` (an `Anim` case), `frames`, `fps`, `loop`, `shift`. The main sheet and `layout.json` do not change.
- A skill is a `Skill` case listed in the character's `skills`; `Pet.drawnSkillPlan` plays its rows (`.play(.sake, 5.4)`), the right-click menu lists it after the skills, and the normal skill behaviour picks one at random. A skill whose rows are missing from the sheet is skipped.
- Dialogue: lines for the skill in all three languages (`Dialogue+*.swift`) and its menu name in `drawnSkillNames`.
