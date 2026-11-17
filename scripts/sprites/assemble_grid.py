#!/usr/bin/env python3
"""Builds a whole sheet <id>.png (every row of layout.json) from Gemini's 4x2 pictures in build/sprites/<id>/raw/.

Each picture is 8 drawings in a 4 x 2 grid on magenta. The background is removed by flood fill from the picture's
border (so pink blush inside the figure stays), magenta enclosed by the figure is removed on a stricter test, the edge
is despilled, Gemini's corner sparkle and loose specks are dropped. One scale is used for the whole sheet: the median
idle height of the `--like` character divided by this character's idle height (or `scale` in rows.json). The lowest
foot of each frame lands on y = 244 (the whole row shares one baseline when `airborne` is set, so jumps stay jumps).

Which drawings go to which row is in build/sprites/<id>/rows.json:

    {"rows": [
      {"row": "idle", "picture": "idle_bored", "cells": [0, 1, 2, 3]},
      {"row": "walk", "picture": "walk", "cells": [0, 1, 2, 3, 0, 1, 2, 3]},
      {"row": "happy", "picture": "happy", "cells": [0, 1, 2, 3, 4, 5], "airborne": true},
      {"row": "skill1", "picture": "skill1_punch", "cells": [0, 1, 2, 3, 4, 5, 6, 7], "anchor": "head", "noprop": true}
    ]}

`picture` is raw/<id>_<picture>.png, `cells` are drawings in reading order (0-3 top row, 4-7 bottom row).
Options per row: `largest` keeps only the biggest piece (drops a ball beside the figure), `airborne` keeps the
row's jumps (shared baseline, fitted under the top of the cell), `anchor: "head"` centres on the head instead of
the whole drawing (for poses with a prop sticking out), `noprop` measures only the figure, `scale` overrides the
sheet scale for this row, `dx` nudges the row sideways in px.

Rows missing from rows.json fall back to the idle drawings, so the sheet is always complete.

Options:
  --like ID        character already in the game whose height (and skin with --match-skin) this one should match
  --match-skin     shifts skin pixels close to the character's own skin so their median colour equals --like's
  --demagenta      takes the magenta cast out of pale colours and the outline (white or lavender outfits)
  --install        copies the sheet to Sources/OllieBoard/Resources/Sprites/<id>.png and lists it in custom-sheets.txt
  --style-ref OUT  only writes Gemini's style reference: six frames of --like on magenta (idle, walk, happy)

Writes build/sprites/<id>/<id>.png and contact.jpg (every row, half size, on grey). Needs pillow and numpy.
Usage: .venv/bin/python scripts/sprites/assemble_grid.py <id> --like ID [--match-skin] [--demagenta] [--install]
       .venv/bin/python scripts/sprites/assemble_grid.py <id> --like ID --style-ref build/sprites/<id>/style.png
"""
import argparse
import json
import shutil
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SPRITES = ROOT / "Sources/OllieBoard/Resources/Sprites"
GROUND, CELL = 244, 256
LAYOUT = json.loads((SPRITES / "layout.json").read_text())["animations"]
ROW_NAMES = [name for name, _ in sorted(LAYOUT.items(), key=lambda kv: kv[1]["row"])]


def magenta(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (r > 150) & (b > 150) & (g < 130) & (np.abs(r - b) < 90)


def flood(mask):
    """Pixels of `mask` connected to the picture border."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; q.append((ny, nx))
    return seen


def label(mask):
    """Connected components (8-neighbour); scipy is much faster when it is installed."""
    try:
        from scipy import ndimage
        return ndimage.label(mask, structure=np.ones((3, 3)))
    except ImportError:
        pass
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n += 1
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n; q.append((ny, nx))
    return lab, n


def cut(path):
    """RGBA drawings (reading order) of one 4x2 Gemini picture, background removed."""
    im = Image.open(path).convert("RGB")
    im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)  # half size is still >2x the game size
    rgb = np.asarray(im).astype(np.int32)
    bg = flood(magenta(rgb))
    # Magenta enclosed by the figure (inside a net, between an arm and the body) is background too; it is judged on a
    # stricter magenta than the border fill so pink blush and lips stay.
    r0, g0, b0 = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    holes = (r0 > 170) & (b0 > 150) & (g0 < 100) & (np.abs(r0 - b0) < 80) & ~bg
    lab, n = label(holes)
    if n:
        sizes = np.bincount(lab.ravel())
        bg |= (sizes[lab] > 8) & holes
    # One more pixel of loose pink around the figure (anti-aliased edge).
    edge = np.zeros_like(bg)
    edge[1:, :] |= bg[:-1, :]; edge[:-1, :] |= bg[1:, :]; edge[:, 1:] |= bg[:, :-1]; edge[:, :-1] |= bg[:, 1:]
    edge &= ~bg
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    pinkness = np.clip((np.minimum(r, b) - g) / 120.0, 0, 1)
    alpha = np.where(bg, 0.0, 1.0)
    alpha = np.where(edge, 1 - pinkness, alpha)
    # Despill the edge: pull red and blue down towards green.
    spill = np.clip(np.minimum(r, b) - g, 0, None) * edge
    out = rgb.copy()
    out[..., 0] -= (spill * 0.8).astype(np.int32)
    out[..., 2] -= (spill * 0.8).astype(np.int32)
    out = np.clip(out, 0, 255).astype(np.uint8)
    rgba = np.dstack([out, (alpha * 255).astype(np.uint8)])
    # Gemini's sparkle in the bottom-right corner.
    h, w = alpha.shape
    rgba[int(h * 0.86):, int(w * 0.93):, 3] = 0
    cw, ch = w // 4, h // 2
    return [rgba[(i // 4) * ch:(i // 4 + 1) * ch, (i % 4) * cw:(i % 4 + 1) * cw].copy() for i in range(8)]


def clean(cell, largest=False):
    """Drops specks; with `largest`, keeps only the biggest piece (the figure, not a ball beside it)."""
    a = cell[..., 3] > 20
    lab, n = label(a)
    if n == 0:
        return cell
    sizes = np.bincount(lab.ravel())[1:]
    keep = np.zeros(n + 1, bool)
    main = 1 + int(np.argmax(sizes))
    if largest:
        keep[main] = True
    else:
        keep[1:] = sizes > 60
        # Bits of the drawing above that cross into this cell (they touch the cell's top edge).
        for k in range(1, n + 1):
            if k != main and (lab[0] == k).any():
                keep[k] = False
    cell[..., 3] = np.where(keep[lab], cell[..., 3], 0)
    return cell


def bbox(a, thr=40):
    ys, xs = np.nonzero(a > thr)
    return xs.min(), ys.min(), xs.max(), ys.max()


def figure_bbox(cell, noprop=False):
    """Bounding box of the character; with `noprop`, only the largest piece (no prop or grass beside her)."""
    a = cell[..., 3]
    if noprop:
        lab, n = label(a > 40)
        sizes = np.bincount(lab.ravel())[1:]
        a = np.where(lab == 1 + int(np.argmax(sizes)), 255, 0)
    return bbox(a)


def sheet_cells(sheet, row, frames):
    return [sheet[row * CELL:(row + 1) * CELL, c * CELL:(c + 1) * CELL] for c in range(frames)]


def idle_height(sheet):
    hs = []
    for cell in sheet_cells(sheet, LAYOUT["idle"]["row"], LAYOUT["idle"]["frames"]):
        if (cell[..., 3] > 40).any():
            x0, y0, x1, y1 = bbox(cell[..., 3])
            hs.append(y1 - y0)
    return float(np.median(hs))


def skin_mask(rgba):
    """Opaque warm pixels in the light-skin range (face, hands, legs)."""
    r, g, b, a = (rgba[..., i].astype(np.int32) for i in range(4))
    return (a > 250) & (r > 190) & (r >= g) & (g > b) & (r - b > 18) & (r - b < 90) & (r - g < 55)


def skin_median(sheet):
    """Median skin colour over the standing rows, read in the upper body where the face and hands are."""
    px = []
    for name in ("idle", "walk", "happy", "bored", "sad"):
        info = LAYOUT[name]
        for cell in sheet_cells(sheet, info["row"], info["frames"]):
            m = skin_mask(cell)
            m[int(CELL * 0.75):] = False
            px.append(cell[m][:, :3])
    px = np.concatenate(px) if px else np.zeros((0, 3))
    return np.median(px, axis=0) if len(px) > 50 else None


def demagenta(sheet):
    """Neutralises magenta-hued pale pixels (the background's cast on white cloth and skin) and fades the pink outline.
    Strong purples and dark crimson hair tips stay."""
    x = sheet.astype(np.float32)
    R, G, B, A = x[..., 0], x[..., 1], x[..., 2], x[..., 3]
    tint = np.minimum(R, B) - G
    magenta_hue = (np.abs(R - B) < 45) & (tint > 8)
    soft = magenta_hue & (tint < 70) & ((G > 70) | (B >= R - 4))
    k = np.where(soft, 0.85, 0.0) * np.clip(tint / 40, 0, 1)
    for ch in (0, 2):
        x[..., ch] -= (x[..., ch] - G) * k
    t = A < 40
    edge = np.zeros_like(t)
    edge[1:] |= t[:-1]; edge[:-1] |= t[1:]; edge[:, 1:] |= t[:, :-1]; edge[:, :-1] |= t[:, 1:]
    edge &= ~t & magenta_hue
    x[..., 3][edge] *= 0.55
    return np.clip(x, 0, 255).astype(np.uint8)


def paste_clipped(cell, crop, px, py):
    tmp = Image.new("RGBA", (CELL + 600, CELL + 600), (0, 0, 0, 0))
    tmp.alpha_composite(crop, (px + 300, py + 300))
    cell.alpha_composite(tmp.crop((300, 300, 300 + CELL, 300 + CELL)))


def place(drawings, s, opt):
    """Scales the drawings by `s` and puts them in 256 px cells, feet on the ground line."""
    bottom = max(bbox(c[..., 3])[3] for c in drawings)
    if opt.get("airborne"):
        # Fit the highest jump under the top of the cell (2 px margin).
        top = min(bbox(c[..., 3])[1] for c in drawings)
        s = min(s, (GROUND - 2) / (bottom - top))
    frames = []
    for c in drawings:
        x0, y0, x1, y1 = bbox(c[..., 3])
        fx0, fy0, fx1, fy1 = figure_bbox(c, True)
        if opt.get("anchor") == "head":
            head = c[fy0:fy0 + (fy1 - fy0) // 3, fx0:fx1 + 1, 3]
            hx0, _, hx1, _ = bbox(head)
            cx = fx0 + (hx0 + hx1) / 2
        else:
            cx = (fx0 + fx1) / 2
        crop = Image.fromarray(c[y0:y1 + 1, x0:x1 + 1])
        crop = crop.resize((max(1, round(crop.width * s)), max(1, round(crop.height * s))), Image.LANCZOS)
        px = round(CELL / 2 - (cx - x0) * s) + opt.get("dx", 0)
        py = round(GROUND - (bottom - y0) * s) if opt.get("airborne") else round(GROUND - (y1 - y0) * s)
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        paste_clipped(cell, crop, px, py)
        if px < 0 or py < 0 or px + crop.width > CELL or py + crop.height > CELL:
            print(f"    frame {len(frames)} touches the cell edge: check it in contact.jpg")
        frames.append(cell)
    return frames, s


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("id")
    ap.add_argument("--like", required=True)
    ap.add_argument("--match-skin", action="store_true")
    ap.add_argument("--demagenta", action="store_true")
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--style-ref", metavar="OUT")
    o = ap.parse_args()

    if o.style_ref:
        return write_style_ref(o.like, Path(o.style_ref))

    here = ROOT / "build/sprites" / o.id
    config = json.loads((here / "rows.json").read_text())
    rows = {r["row"]: r for r in config["rows"]}
    if "idle" not in rows:
        raise SystemExit("rows.json needs an idle row: it sets the scale and fills the rows that are missing")
    like = np.asarray(Image.open(SPRITES / f"{o.like}.png").convert("RGBA"))

    missing = [name for name in ROW_NAMES if name not in rows]
    pictures, cleaned = {}, {}
    def drawings(spec):
        key = (spec["picture"], spec.get("largest", False))
        if key not in cleaned:
            if spec["picture"] not in pictures:
                pictures[spec["picture"]] = cut(here / "raw" / f"{o.id}_{spec['picture']}.png")
            cleaned[key] = [clean(d.copy(), key[1]) for d in pictures[spec["picture"]]]
        return cleaned[key]

    # One scale for the whole sheet: Gemini keeps a character the same size from picture to picture.
    idle = drawings(rows["idle"])
    own = np.median([figure_bbox(idle[i])[3] - figure_bbox(idle[i])[1] for i in set(rows["idle"]["cells"])])
    scale = config.get("scale", idle_height(like) / own)
    print(f"scale {scale:.3f} (idle height like {o.like})")

    sheet = Image.new("RGBA", (8 * CELL, len(ROW_NAMES) * CELL), (0, 0, 0, 0))
    for name in ROW_NAMES:
        spec = rows.get(name)
        n = LAYOUT[name]["frames"]
        if spec is None:
            spec = dict(rows["idle"], cells=(rows["idle"]["cells"] * 4)[:n])
            print(f"{name}: not in rows.json, idle drawings used")
        if len(spec["cells"]) != n:
            print(f"{name}: {len(spec['cells'])} cells for {n} frames, check rows.json")
        frames, s = place([drawings(spec)[i] for i in spec["cells"]], spec.get("scale", scale), spec)
        for i, f in enumerate(frames[:8]):
            sheet.alpha_composite(f, (i * CELL, LAYOUT[name]["row"] * CELL))
        print(f"{name}: {len(frames)} frames, scale {s:.3f}")

    out = np.asarray(sheet).copy()
    if o.demagenta:
        out = demagenta(out)
    if o.match_skin:
        mine, theirs = skin_median(out), skin_median(like)
        if mine is None or theirs is None:
            print("skin: not enough skin pixels to compare, left as drawn")
        else:
            # Only colours close to her own skin move, so a beige or orange outfit keeps its colour.
            m = skin_mask(out) & (np.abs(out[..., :3].astype(np.float32) - mine).max(axis=-1) < 32)
            out[..., :3][m] = np.clip(out[..., :3][m].astype(np.float32) + (theirs - mine), 0, 255).astype(np.uint8)
            print(f"skin: median {mine.astype(int)} moved to {theirs.astype(int)} ({o.like})")
    path = here / f"{o.id}.png"
    Image.fromarray(out).save(path)

    contact = Image.new("RGBA", sheet.size, (150, 150, 150, 255))
    contact.alpha_composite(Image.fromarray(out))
    contact.convert("RGB").resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS).save(here / "contact.jpg", quality=85)
    print(f"wrote {path.relative_to(ROOT)} and contact.jpg")
    if o.install:
        if missing:
            raise SystemExit(f"not installed: rows {missing} are only idle drawings. Draw them first.")
        shutil.copy(path, SPRITES / f"{o.id}.png")
        print(f"installed Sources/OllieBoard/Resources/Sprites/{o.id}.png")
        # SpriteGen would redraw this sheet from code; listing it makes SpriteGen leave it alone.
        listing = SPRITES / "custom-sheets.txt"
        existing = listing.read_text() if listing.exists() else ""
        ids = {line.strip() for line in existing.splitlines() if line.strip() and not line.lstrip().startswith("#")}
        if o.id not in ids:
            listing.write_text(existing + ("" if not existing or existing.endswith("\n") else "\n") + o.id + "\n")
            print(f"added {o.id} to custom-sheets.txt")


def write_style_ref(like, out):
    """Six frames of a character already in the game on magenta, twice the size: Gemini copies its proportions,
    outline and shading from it, so the new character looks like it belongs next to the others."""
    sheet = Image.open(SPRITES / f"{like}.png").convert("RGBA")
    picks = [("idle", 0), ("walk", 0), ("walk", 2), ("walk", 4), ("happy", 0), ("happy", 2)]
    strip = Image.new("RGB", (len(picks) * CELL, CELL), (255, 0, 255))
    for i, (name, col) in enumerate(picks):
        row = LAYOUT[name]["row"]
        cell = sheet.crop((col * CELL, row * CELL, col * CELL + CELL, row * CELL + CELL))
        strip.paste(cell, (i * CELL, 0), cell)
    out.parent.mkdir(parents=True, exist_ok=True)
    strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST).save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
