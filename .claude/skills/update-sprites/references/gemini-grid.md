# Whole sheet from 4 × 2 grids, in the game's style

Use this to draw a new character (or redraw a whole sheet) with Gemini so it looks like it belongs next to the sprites already in the game. It replaces the per-row strips of the main workflow with 4 × 2 grids and adds a style reference. The model-sheet and strip route in [SKILL.md](../SKILL.md) still works; this one gave cleaner, more consistent sheets.

## Pictures to attach

1. **The character**: 2–4 pictures from the anime or game the user picked: full body (outfit and colours) and a close-up of the face and hair. Do not search for them yourself when the user gave some.
2. **The game's style**: six frames of a character already in the game, on magenta, at twice the size. Gemini copies the head-to-body ratio, the outline, the cel shading and the size from it. Pick one of a similar build (a girl for a girl):

   ```sh
   .venv/bin/python scripts/sprites/assemble_grid.py <id> --like maomao --style-ref build/sprites/<id>/refs/style.png
   ```

Fan-made chibi drawings are not needed. Their style pulls Gemini away from ours, and they are someone else's work. Keep the pictures in `build/sprites/<id>/refs/`, which is not committed, and show the model sheet to the user before drawing the rows.

## Chat flow (Claude in Chrome)

- Use one chat per character: the model sheet first, then the rows, so the design stays the same. Note the chat URL to come back to it.
- Attach the pictures with ONE short message: "Describe these pictures: the character in the first ones, and the art style of the sprite strip in the last one." Text typed together with an upload gets dropped. Send the real request as the next message.
- Save every picture as `build/sprites/<id>/raw/<id>_<name>.png`. Inspect the saved file as the main workflow says.
- If Gemini refuses a pose, describe it more gently rather than pushing. A kick aimed at someone was refused; "taps a ball with her foot" was drawn.

## Prompts

Model sheet:

> Draw <name> from the first pictures in EXACTLY the art style of the sprite strip (same chibi proportions, about 2.5 heads tall, thick dark outline, flat cel shading, soft blush). Model sheet in a 4x2 grid on a perfectly flat pure magenta #FF00FF background: front, side facing RIGHT, back, 3/4 facing right, then happy, surprised, <skill 1 pose>, <skill 2 pose>. <hair, eyes, outfit with colours, shoes>. Full body including feet, same size and same foot line in every drawing, no divider lines, no text.

Every row is a 4 × 2 grid of 8 drawings. Two 4-frame rows can share one picture: idle + bored, sleep + grumpy, dragged + work, surprised + sad.

> Using that exact <name> design and the same art style, draw <what>: 8 drawings in a grid of 4 columns x 2 rows (16:9), read left to right, top to bottom. Side view facing RIGHT. <frame-by-frame description; say on which frame the hit or the reveal happens>. FULL BODY, feet visible and sharp in every drawing. Same size and same ground line in every drawing. Each drawing stays inside its own cell with a wide magenta gap; NO divider lines, NO borders. Background: perfectly flat solid pure magenta #FF00FF, no gradient, no shadow, no text. Crisp single drawings: no motion blur, no afterimage, no speed lines.

Row notes:
- **walk / run**: Gemini often turns the bottom row of drawings towards the viewer. Ask for "all 8 in side view"; if it still happens, use the top four drawings twice (`[0, 1, 2, 3, 0, 1, 2, 3]`).
- **carry**: both arms up, holding NOTHING. The app draws the icon.
- **dragged**: lifted from above, legs dangling.
- **work**: sitting with a laptop. It comes out larger than the standing rows; give it its own `scale`.
- **happy / surprised**: jumps. Mark them `airborne` so the jump is kept.
- **skills**: keep the 8 frames and the timing of the skill plan in `Pet.swift`, and do not draw the app's effects (hearts, sparkles, smoke).

## Build the sheet

Write `build/sprites/<id>/rows.json` (the format is in the header of `assemble_grid.py`). It says which drawings make each row: `cells` are drawings in reading order, 0–3 on the top row and 4–7 on the bottom row. Then:

```sh
.venv/bin/python scripts/sprites/assemble_grid.py <id> --like maomao [--match-skin] [--demagenta]
```

- **Scale:** one scale for the whole sheet, which makes the idle height equal to the `--like` character's idle height. The new character is not a head taller than the others.
- **Feet:** they land on y = 244. `airborne` rows share one baseline so jumps stay jumps. `anchor: "head"` centres a pose with a prop on the head, and `largest` drops a loose prop beside the figure.
- **`--match-skin`:** moves the skin to the median skin colour of `--like`. It only changes colours close to the character's own skin, so a beige or orange outfit keeps its colour. Judge skin over many rows, not one frame: one frame is misleading. The user decides the final tone.
- **`--demagenta`:** for white, lavender or pale outfits. The magenta background leaves a purple cast on pale cloth and a pink outline; this removes it and keeps strong purples and dark red hair tips.
- **Missing rows:** they are filled with idle drawings so the preview is complete. `--install` refuses until every row is drawn.

Look at `build/sprites/<id>/contact.jpg`, and at the walk as a GIF, before `--install`. The install copies the sheet and lists it in `custom-sheets.txt`. Redraw a bad row in the same chat instead of stretching it. Then follow the build and live-test steps of the main workflow.
