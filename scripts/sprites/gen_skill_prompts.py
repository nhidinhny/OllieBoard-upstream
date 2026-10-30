#!/usr/bin/env python3
"""Writes the Gemini task for ONE new animation drawn from a character's CURRENT sprite: a skill row (the character and a
prop drawn together, see build_skill_rows.py), or a row of the main sheet that has to be drawn again (--redo).

Why the current sprite: Gemini invents its own proportions from a name or a model sheet (rounder, cuter, other outfit).
Attaching frames of the sprite that is in the game and saying "copy its proportions" keeps the new rows on-model.

  .venv/bin/python scripts/sprites/gen_skill_prompts.py zoro sake \\
      --prop "a white ceramic sake bottle (tokkuri) with a small red label, in front of him, identical and in the same place in every drawing" \\
      --pose "SITS cross-legged on the ground, side view facing RIGHT" \\
      --frames "cup held out; holding the cup in both hands; raising the cup; drinking with eyes closed; lowering it with a satisfied grin; cup held out again; raising it; drinking with a content nod"

Writes build/sprites/<id>/skill-<name>/{reference.png, task.md}. Options: --grid 4x2 (default; Gemini draws grids more
reliably than one long row and the drawings come out larger), --redo (a main-sheet row: no prop; 'carry' draws empty raised
hands, 'dragged' arms up), --expression "..." (default: cheerful only).
"""
import argparse
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_prompts import CHARACTERS  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SHEET = os.path.join(ROOT, "Sources", "OllieBoard", "Resources", "Sprites")
# (row, frame): standing, a relaxed second pose, seated with the laptop, arms crossed, a skill, a run: shows the design from
# several poses without the soft rows (carry/happy/dragged) that Gemini would copy the blur of.
REFERENCE_FRAMES = [(0, 0), (0, 2), (12, 0), (9, 0), (14, 2), (2, 2)]

TASK = """TASK (follow it with the browser/image tools you actually have; Gemini web app, signed in by the user):

1. Open a NEW Gemini chat. Attach {reference} (upload button / hidden file input) and send ONLY this short message:
   "This is the current in-game sprite of {char}. Describe it briefly."
   Text typed together with the upload can get lost, and without a request Gemini only describes the picture, so this
   first message is just for it to look at the sprite. Wait for its description.
2. In the SAME chat send the prompt below as the second message. Wait until the picture is fully drawn.
3. Check it against the reference: same proportions, outline, face, outfit, FULL legs and feet, the prop identical in every
   drawing, cheerful or neutral expressions, no divider lines. If it is wrong, say what is wrong in the same chat (at most
   twice), then save the best one. Save the displayed picture (not a screenshot) as assets/{kind}/{cid}_{row}.png.
4. Then run: .venv/bin/python scripts/sprites/build_skill_rows.py{redo_flag} {cid}  (add the row to scripts/sprites/skill_rows.json first)
   and look at the result: every drawing, feet on the ground line, nothing cut at the cell edge.

PROMPT (second message):

"""

PROMPT = ("Using that image as the exact art reference for {name} (copy its proportions: head to body ratio and small body; "
          "its outline and shading; {look}; do NOT make the character rounder or cuter than the reference), draw a NEW image: "
          "a sprite animation '{name_anim}' as a grid of {cols} columns x {rows} rows ({n} drawings, read left to right then top to bottom), "
          "each drawing in its own equal square cell with a wide empty magenta gap around it, NO divider lines, NO borders, NO text. "
          "{pose}, FULL BODY INCLUDING BOTH LEGS AND SHOES/FEET FULLY VISIBLE AND SHARP.{prop} "
          "Frames, a smooth loop: {frames}. {expression} Only the arms, head and moving parts change between drawings; the feet "
          "stay on the same ground line. Background: perfectly flat solid pure magenta #FF00FF (no gradient, no shadow, no seams). "
          "Every drawing crisp, sharp, solid flat colours, no motion blur or ghosting. The character{with_prop} fills about 85 percent of the "
          "cell height and nothing touches the cell edge. Output aspect ratio {ratio} at the highest resolution (2K).")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id"); ap.add_argument("name", help="skill or row name, e.g. sake, inflate, carry")
    ap.add_argument("--frames", required=True, help="the drawings in order, separated by ';'")
    ap.add_argument("--pose", default="The character stands in side view facing RIGHT")
    ap.add_argument("--prop", default="", help="the prop, drawn together with the character and identical in every drawing")
    ap.add_argument("--grid", default="4x2"); ap.add_argument("--redo", action="store_true")
    ap.add_argument("--expression", default="Cheerful or content expressions only, never sad or bored.")
    o = ap.parse_args()
    if o.id not in CHARACTERS: sys.exit(f"unknown id {o.id!r}; known: {', '.join(CHARACTERS)}")
    cols, rows = (int(x) for x in o.grid.split("x"))
    frames = [f.strip() for f in o.frames.split(";") if f.strip()]
    if len(frames) > cols * rows: sys.exit(f"{len(frames)} frames do not fit a {o.grid} grid")
    name, look = CHARACTERS[o.id][:2]
    sheet = os.path.join(SHEET, f"{o.id}.png")
    if not os.path.exists(sheet): sys.exit(f"no sheet for {o.id} yet ({sheet}); run assemble.py --install first")
    out = os.path.join(ROOT, "build", "sprites", o.id, f"skill-{o.name}"); os.makedirs(out, exist_ok=True)
    src = Image.open(sheet).convert("RGBA")
    ref = Image.new("RGBA", (256 * 3, 256 * 2), (255, 0, 255, 255))
    for i, (r, c) in enumerate(REFERENCE_FRAMES):
        ref.alpha_composite(src.crop((c * 256, r * 256, (c + 1) * 256, (r + 1) * 256)), ((i % 3) * 256, (i // 3) * 256))
    ref_path = os.path.join(out, "reference.png"); ref.convert("RGB").save(ref_path)
    prop = f" The prop is part of every drawing: {o.prop}" if o.prop else ""
    prompt = PROMPT.format(name=name.split(" (")[0], look=look, name_anim=o.name, cols=cols, rows=rows, n=len(frames), pose=o.pose,
                           prop=prop, frames="; ".join(f"{i + 1} {f}" for i, f in enumerate(frames)), expression=o.expression,
                           with_prop=" and the prop together" if o.prop else "", ratio="16:9" if cols >= rows else "1:1")
    kind = "redo" if o.redo else "skill"
    text = TASK.format(reference=ref_path, char=name.split(" (")[0], kind=kind, cid=o.id, row=o.name,
                       redo_flag=" --redo" if o.redo else "") + prompt + "\n"
    open(os.path.join(out, "task.md"), "w").write(text)
    print(f"Wrote {os.path.join(out, 'task.md')} and {ref_path}")


if __name__ == "__main__":
    main()
