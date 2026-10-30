---
name: update-sprites
description: Redraw or replace an OllieBoard character sprite with the requested image generator, assemble native RGBA atlases or Gemini strips, and verify before installation. For a new character use add-character.
---

# Update OllieBoard sprites

Run commands from the OllieBoard repository root. These instructions are shared by Claude Code and Codex: the canonical folder is `.claude/skills/update-sprites`; `.agents/skills/update-sprites` links here. Use the tools actually exposed by the current session.

## Tools and scope

- Use the image provider the user requested. For the built-in image tool and native transparent atlases, read [native-atlas](references/native-atlas.md) and use that generation/assembly route instead of the Gemini sections below. The Gemini strip route remains available when requested. Do not silently switch providers or introduce a paid API.
- Claude Code may use Claude in Chrome when available. Codex may use its available browser/computer-use tool. Neither host guarantees a browser, image upload, download, page JavaScript, or login. Read the chosen tool's instructions first; generated task text does not grant extra capabilities.
- If automation cannot upload/save native images, generate the task file and hand it to the user for manual execution. Let the user handle login. Report exactly which rows remain; do not claim browser execution happened.
- Use supplied design decisions and authorization. Ask only for missing choices that materially affect the character. Upload only the selected character reference; do not send repository source or unrelated images.

## Sprite contract

Check `Sources/OllieBoard/SpriteSheet.swift`, `Resources/Sprites/layout.json` under the same directory, and the character's `Pet.swift` skill plan when changing animations.

- PNG RGBA, 2048 × 4096 px: 8 columns × 16 rows of 256 px cells. Character faces right; feet anchor is (128, 244) px, corresponding to (64, 122) points.
- Rows and frame counts: idle 4, walk 8, run 6, kick 7, carry 8, happy 6, bored 4, yawn 8, sleep 4, grumpy 4, dragged 4, surprised 2, work 4, sad 4, skill1 8, skill2 8. Agent mascots use rows 0–13; the complete sheet still has 16 rows.
- Carry: arms up, holding nothing; the app supplies the desktop icon. Dragged: lifted by both hands, legs dangling. Work: seated with a laptop.
- Skill rows must preserve all 8 frames and their action timing from `Pet.swift`. Runtime effects must not be duplicated in the art. Regenerate a wrong action frame instead of resampling it.
- Preserve unrelated character sheets, `layout.json`, and `effects.png`.

## Skill rows, and rows that must be drawn again

For a new animation with a prop (a skill) or a main-sheet row that is soft or lost its feet, draw it from the character's current sprite instead of the model-sheet flow below: read [skill-rows](references/skill-rows.md) (`gen_skill_prompts.py` writes the task, `build_skill_rows.py` builds `<id>-skills.png` / replaces rows, `skill_rows.json` holds the options).

## Generate

1. Select an existing id with `python3 scripts/sprites/gen_prompts.py --list`. Read its `CHARACTERS` entry and compare it with the current design and skill plan; the table is a snapshot, not the source of truth.
2. Prepare dependencies if missing:

   ```sh
   python3 -m venv .venv
   .venv/bin/python -m pip install -r scripts/sprites/requirements.txt
   ```

3. Run `.venv/bin/python scripts/sprites/gen_prompts.py <id>`. It writes `build/sprites/<id>/gemini-task.md` and creates `raw/`. Original characters need a reference: existing originals get an idle-frame crop; a new original needs `--reference /path/to/approved-picture.png`.
4. Execute that task with the available browser tool, or hand it to the user. Use one Gemini chat per character: model sheet first, then one row at a time. For retries, keep that chat and use `--rows 2,5,9`. Record the chat URL if available so the next turn can resume.
5. Save the native image to `raw/<id>_row<N>_<animation>.png`, matching the row and animation exactly. Check that the saved file matches the completed image in the chat. Do not use a page screenshot or select an image only because it is last/largest in the DOM.

Earlier PR experiments found corrupt or blurry results from Gemini's “Download full size” button. Treat that as an observed failure mode, not a permanent browser rule: inspect the saved file and use another supported save action or manual handoff if needed. Do not inject an undocumented canvas/download script or change the browser's global download directory. Move only known files created by this task.

Retry a bad row at most twice. Stop and report quota, login, refusal, or unsupported-browser blockers with completed and missing rows. Do not try to circumvent a provider refusal.

## Assemble and inspect

Run `.venv/bin/python scripts/sprites/assemble.py <id>` without `--install` first. Inspect both `build/sprites/<id>/raw-contact.png` and `<id>-preview.png` using the current host's image viewer. If none is available, hand the previews to the user and leave visual validation pending.

- Reject wrong poses, clipped limbs, ghosting, inconsistent design/scale, baseline errors, missing frames, and incorrectly timed skill actions. Heuristic checks cannot establish visual correctness.
- The assembler rejects missing/rejected rows at installation and refuses repaired/resampled skill rows. Non-skill rows can be resampled or have a bad frame replaced; review every such warning before installing.
- `--keep-bad` is for debugging previews only and cannot be combined with `--install`.
- Skin correction defaults to 0.6 for the original Gemini workflow; `--skin 0` preserves input colours. Inspect skin and similarly coloured props. For fur/robots, update `NO_SKIN_FILTER` as appropriate. Use the same chosen skin value for preview and installation.
- The current chroma-key pipeline expects magenta RGB strips. It includes a bottom-right watermark mask and border cleanup that can erase artwork; inspect those areas. Do not feed another provider's transparent images through it unchanged.

Redo failed rows in the same Gemini chat, then reassemble. Do not install merely because the command completed.

## Install and verify

Once the previews pass and installation is within the user's request:

1. Run `.venv/bin/python scripts/sprites/assemble.py <id> --install` with the same skin option as the preview. It writes only that character's sheet and adds its id to `Sources/OllieBoard/Resources/Sprites/custom-sheets.txt`.
2. Verify the id is listed and `Sources/SpriteGen/main.swift` skips listed ids. That guard prevents `make sprites` / `make app` from overwriting custom art. Do not regenerate every source sprite as a smoke test; use a temporary output directory to test SpriteGen.
3. Run `swift build -c release --product OllieBoard`. Build success proves compilation, not animation quality.
4. When a live app test is requested, use the built development executable. For example, for Luffy:

   ```sh
   "$(swift build -c release --show-bin-path)/OllieBoard" \
     -enabledCharacters '("luffy")' \
     -agentCharacters '<?xml version="1.0"?><plist version="1.0"><false/></plist>' \
     -language vi
   ```

   Replace luffy with the selected id; relaunch with language vi/en/ja to check translations. These launch arguments override preferences for that process and disable monitoring of real AI sessions. The XML boolean is intentional: this app reads `agentCharacters` with `object(forKey:) as? Bool`, so plain `NO` remains a string and does not disable it. Do not use `defaults write/delete`, toggle saved settings, replace the installed app, or kill unrelated app instances. Stop only the process you started. Launch a desktop interaction test only when the user has authorized it, explaining that the app can move real Desktop icons through Finder.
5. Inspect idle/walk, happy click, grumpy clicks, dragging, and both skills with dialogue/effects. Use available screenshot/computer-use tools; otherwise request user verification. Report build checks, preview inspection, and live app validation separately.

Report the character, changed files, output paths, unresolved warnings, and coverage. Leave commit/push/PR actions to a separate user request.
