#!/usr/bin/env python3
"""Builds a character's skills sheet: Sources/OllieBoard/Resources/Sprites/<id>-skills.png (one 8-frame row per skill)
and its entry in skills.json, from Gemini pictures assets/skills/<id>_<name>.png.

A skill row has the character and the prop drawn together (the dumbbell, the bottle, a puffed-up belly), so nothing is
pasted next to the sprite at run time. Every picture holds the drawings in a grid on flat magenta; each drawing is cut
out, keyed (soft edges, no magenta fringe, Gemini's corner sparkle removed), the row gets one scale and the drawings keep
their place relative to each other, so a prop that must not move does not move. Skin is graded to the game's tone with
assemble.py's own skin grading, like a normal sheet. Options per row: see skill_rows.json.

Usage (from the repository root; needs pillow and numpy):
  .venv/bin/python scripts/sprites/build_skill_rows.py luffy zoro      # only these ids (default: all in skill_rows.json)
  .venv/bin/python scripts/sprites/build_skill_rows.py --redo luffy    # also redraw rows of the main sheet, see below

--redo: rows of the main sheet that were drawn again (assets/redo/<id>_<row>.png, same grid format, options under "redo" in
skill_rows.json) replace those rows of <id>.png in place (same row index and frame count as layout.json).
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assemble  # noqa: E402  (skin grading and the sheet contract live there)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SPRITES = os.path.join(ROOT, "Sources", "OllieBoard", "Resources", "Sprites")
CELL, GROUND_Y, CENTER_X = 256, 244, 128


def blur(a, radius):
    """Gaussian blur of a 2-D float array (separable, no scipy needed)."""
    n = int(radius * 3)
    k = np.exp(-np.arange(-n, n + 1) ** 2 / (2 * radius ** 2)); k /= k.sum()
    out = np.pad(a.astype(np.float32), ((n, n), (n, n)), mode="edge")
    out = sum(w * out[:, i:i + a.shape[1]] for i, w in enumerate(k))
    return sum(w * out[i:i + a.shape[0], :] for i, w in enumerate(k))


def key_out(im, glow=False):
    """Magenta -> transparent. Half-transparent edge pixels are blended with the magenta, so they take the colour of the
    solid pixels next to them (yellow lightning stays yellow, outlines stay dark: no pink fringe). glow=True turns the
    pale pink halo of a yellow glow back into soft yellow."""
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    s = np.minimum(r, b) - g
    alpha = np.clip((190 - s) / 80, 0, 1)
    solid = (alpha > 0.6).astype(np.float32)
    weight = blur(solid, 2.5)
    rgb = a.copy()
    edge = (alpha < 0.97) & (weight > 0.03)
    for c in range(3):
        rgb[..., c] = np.where(edge, blur(a[..., c] * solid, 2.5) / np.maximum(weight, 1e-3), a[..., c])
    if glow:
        pink = (r > 200) & (b > 150) & (s > 35) & (alpha > 0)
        rgb[pink] = (255, 236, 130)
        alpha = np.where(pink, np.clip((190 - s) / 110, 0, 1), alpha)
    return Image.fromarray(np.clip(np.dstack([rgb, alpha * 255]), 0, 255).astype(np.uint8), "RGBA")


def cells(path, grid=(4, 2), inset=0):
    """The drawings of a picture laid out `grid` = (columns, rows), left to right, top to bottom."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # Gemini's sparkle watermark (bottom right): pink or pale pixels in that corner become background again.
    px = np.asarray(im).copy()
    box = px[int(h * 0.76):int(h * 0.94), int(w * 0.86):int(w * 0.98)]
    box[(box[..., 0] > 200) & (box[..., 2] > 200) & (box[..., 1] > 40)] = (255, 0, 255)
    im = Image.fromarray(px)
    cols, rows = grid
    cw, ch = w // cols, h // rows
    return [im.crop((c * cw + inset, r * ch + inset, (c + 1) * cw - inset, (r + 1) * ch - inset))
            for r in range(rows) for c in range(cols)]


def bbox(f):
    return f.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()


def free_row(path, o):
    frames = [key_out(c, o.get("glow", False)) for c in cells(path, tuple(o.get("grid", (4, 2))), o.get("inset", 0))]
    frames = frames[:o.get("frames", len(frames))]
    ground = o.get("ground", GROUND_Y)
    boxes = [bbox(f) for f in frames]
    if o.get("head_norm"):
        # Every drawing is scaled so its head (top 30 percent) is as wide as in the first one; the body hangs below.
        heads = []
        for f, b in zip(frames, boxes):
            top = f.getchannel("A").point(lambda v: 255 if v > 24 else 0).crop((b[0], b[1], b[2], b[1] + int((b[3] - b[1]) * .3)))
            hb = top.getbbox(); heads.append((b[0] + hb[0], b[0] + hb[2]))
        rel = [(heads[0][1] - heads[0][0]) / (h[1] - h[0]) for h in heads]
        tallest = max((b[3] - b[1]) * r for b, r in zip(boxes, rel))
        base = min(o["height"] / (boxes[0][3] - boxes[0][1]), (ground - 4) / tallest)
        scales = [base * r for r in rel]
        anchors = [(h[0] + h[1]) / 2 * s for h, s in zip(heads, scales)]
        bottoms = [b[3] * s for b, s in zip(boxes, scales)]
    else:
        s = o["height"] / float(np.median([b[3] - b[1] for b in boxes]))
        scales = [s] * len(frames)
        ax = float(np.mean([(b[0] + o.get("anchor", .5) * (b[2] - b[0])) * s for b in boxes]))
        anchors = [ax] * len(frames)
        med = float(np.median([b[3] * s for b in boxes]))
        bottoms = [b[3] * s if o.get("level") else med for b in boxes]
    row = Image.new("RGBA", (CELL * 8, CELL))
    for i, (f, s) in enumerate(zip(frames, scales)):
        f2 = f.resize((round(f.width * s), round(f.height * s)), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL, CELL))
        cell.alpha_composite(f2, (round(o.get("cx", CENTER_X) - anchors[i]), round(ground - bottoms[i])))
        bb = cell.getchannel("A").getbbox()
        edge = bb[0] <= 1 or bb[1] <= 1 or bb[2] >= CELL - 1 or bb[3] >= CELL - 1
        print(f"  {os.path.basename(path)} drawing {i}: box {bb}{'  TOUCHES THE CELL EDGE' if edge else ''}")
        row.alpha_composite(cell, (i * CELL, 0))
    return row


def grade(rows, cid):
    """Moves Gemini's skin tone of these rows to the game's (assemble.py's grade_skin, same strength as a sheet)."""
    arrays = [np.asarray(r).copy() for r in rows]
    src = next((s for s in (assemble.estimate_skin(a) for a in arrays) if s is not None), None)
    if src is None:
        print("  skin: no skin-coloured area found, colours left as Gemini drew them")
        return rows
    dst = assemble.to_lab(np.array(assemble.GAME_SKIN.get(cid, assemble.DEFAULT_SKIN), float))
    return [Image.fromarray(assemble.grade_skin(a, src, dst, assemble.SKIN_STRENGTH), "RGBA") for a in arrays]


def build_skill(cid, rows):
    print(f"{cid}: skill rows")
    images = [free_row(os.path.join(ROOT, "assets", "skills", f"{cid}_{o['name']}.png"), o) for o in rows]
    sheet = Image.new("RGBA", (CELL * 8, CELL * len(rows)))
    for i, im in enumerate(grade(images, cid)):
        sheet.alpha_composite(im, (0, i * CELL))
    sheet.save(os.path.join(SPRITES, f"{cid}-skills.png"))
    return {"rows": [dict(name=o["name"], frames=o.get("frames", 8), fps=o["fps"], loop=o.get("loop", True),
                          shift=o.get("shift", 0)) for o in rows]}


def redo_main(cid, rows):
    layout = json.load(open(os.path.join(SPRITES, "layout.json")))["animations"]
    path = os.path.join(SPRITES, f"{cid}.png")
    sheet = Image.open(path).convert("RGBA")
    images = [free_row(os.path.join(ROOT, "assets", "redo", f"{cid}_{o['name']}.png"), o) for o in rows]
    for o, im in zip(rows, grade(images, cid)):
        info = layout[o["name"]]
        n = info["frames"]
        sheet.paste(Image.new("RGBA", (CELL * 8, CELL)), (0, info["row"] * CELL))
        sheet.alpha_composite(im.crop((0, 0, CELL * n, CELL)), (0, info["row"] * CELL))
        print(f"  {o['name']}: row {info['row']} ({n} frames)")
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*"); ap.add_argument("--redo", action="store_true")
    o = ap.parse_args()
    config = json.load(open(os.path.join(HERE, "skill_rows.json")))
    ids = o.ids or [k for k in config if not k.startswith("_") and k != "redo"]
    meta_path = os.path.join(SPRITES, "skills.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for cid in ids:
        if cid not in config: sys.exit(f"{cid} is not in skill_rows.json")
        if o.redo:
            redo_main(cid, config.get("redo", {}).get(cid, []))
        else:
            meta[cid] = build_skill(cid, config[cid])
    if not o.redo:
        json.dump(meta, open(meta_path, "w"), indent=2, sort_keys=True); open(meta_path, "a").write("\n")


if __name__ == "__main__":
    main()
