---
name: add-character
description: Add an OllieBoard character or desktop pet with two moves, English/Vietnamese/Japanese dialogue, and a sprite sheet from the requested image generator. Use update-sprites for existing character art only.
---

# Add an OllieBoard character

This project skill is shared by Codex and Claude Code. Work from the repository root. Its canonical folder is `.claude/skills/add-character`; `.agents/skills/add-character` links here.

## Establish the design

Use what the user already specified; propose reasonable defaults and ask only about unresolved choices that affect the result:

- Unique lowercase alphanumeric id, display name, series, appearance and reference.
- Personality, walk speed, behaviour weights, shy/prankster flags and annoyed reaction.
- Two moves: names, eight-frame action sequence, impact frame, dialogue, and runtime effect.

Write original dialogue in the character's spirit. For a new original design, obtain an approved reference picture before the art step. Do not treat tool availability or a model's ability to reproduce a character as verified until checked.

## Integrate the character

Inspect current symbols instead of relying on fixed line numbers. Paths below are under `Sources/OllieBoard/`.

1. `Characters.swift`: add two `Skill` cases, a `Series` case only if needed, and a `Character` entry in `allCharacters`. Include `.skill` in behaviour weights if moves should fire autonomously. Preserve existing entries and menu ordering.
2. `Dialogue.swift`: add the moves' `Line` cases and `skillSpeakers` mappings. Add extra lines only when the move uses them.
3. `Dialogue+English.swift`, `Dialogue+Vietnamese.swift`, `Dialogue+Japanese.swift`: add the character's `Lines` entry, pair greetings, move dialogue, and both localized skill names. Use an existing complete character as the template. Preserve `%@` partner-name and `{app}` substitutions.
4. `Pet.swift`: add cases to the exhaustive `skillPlan(_:)` switch. Use existing step/effect helpers. Match runtime effects to the eight-frame animation timing; do not shift a hit to compensate for malformed generated art.
5. `README.md`: add the character consistently with the existing feature list.
6. Run `swift build -c release --product OllieBoard`. Do not launch with the new character enabled until its sprite exists; missing sheets fail at runtime.

Do not add a procedural `Look` in `Sources/SpriteGen/Looks.swift` for an image-generated sheet. Add new shared effects only when the requested move actually needs them.

## Create the sprite

Read [update-sprites](../update-sprites/SKILL.md), select the user's requested provider, and follow the matching native-atlas or Gemini-strip route on either host.

1. Add the id to `CHARACTERS` in `scripts/sprites/gen_prompts.py`: full name, appearance, and two explicit frame-by-frame skill descriptions including impact frames. Add original designs to `ORIGINAL` and supply `--reference`.
2. Generate the model/animation artwork, assemble without installing, inspect the source images and preview, and regenerate failed poses. Match the character's intended skin/fur colours. For the Gemini strip route only, add non-human characters to `NO_SKIN_FILTER` if needed.
3. Install the accepted sheet with the chosen route's packer (`assemble_atlas.py` for native RGBA, `assemble.py` for Gemini strips) and `--install`. Check the 2048 × 4096 RGBA sheet and `custom-sheets.txt` entry.

If the browser or image tools are unavailable, leave the task/prompts ready and report art as pending. Do not report a character complete while its sheet or visual checks are missing.

Once the character has a sheet it can also get skills (an animation drawn together with a prop) and rows redrawn from its current sprite: see `update-sprites/references/skill-rows.md`. That route reuses the sprite in the game as Gemini's reference, which keeps the proportions on-model.

## Verify and hand off

- Build the app again with the installed resource.
- Follow update-sprites' process-local launch method; do not change/delete saved preferences or replace the installed app.
- Verify menu placement, all three language names/dialogue, movement, interactions, and both skills' timing/effects. Separate source/build evidence from actual app observations; ask for user verification only where tools cannot observe the result.
- Report changed files, sheet/preview paths, checks run, and pending work. Do not commit or push unless requested.
