# Dragged row redraw (Luffy, 2026-11-16)

The old row 10 was pre-Gemini art (blurry, thin outline, pink fringe). Attach: 1. one crisp drawing of the character
from the game (STYLE), 2. a strip of the 4 old dragged frames (POSES only), with the prompt of SKILL.md section 7.

Keep: shocked eyes, small open mouth, blush; pose 1 arms out sideways, 2 arms slightly out, 3 flailing with one leg
kicked out, 4 hanging calm. No sweat drops (the effect layer draws them). Build it with `assemble_grid.py` using
`"anchor": "head"` and `"airborne": true` so the figure hangs under the hand; fix a single bad frame (Luffy's frame 3
sleeves) in a separate chat, then match the skin to idle.
