#!/usr/bin/env python3
"""Walk or run row from Gemini drawings, with the fps that keeps the planted foot still on the ground.

Two ways in:
  * ONE step (walk 4 drawings, run 3) that is played twice. Fine when both legs look alike.
  * A whole cycle (--cycle, usually 6 drawings in one picture) in the order you choose with --pick.

    python3 scripts/sprites/gait_step.py <id> walk build/sprites/<id>/raw/<id>_walkstep.png --grid 4x1 --top-row
    python3 scripts/sprites/gait_step.py <id> run  build/sprites/<id>/raw/<id>_runstep.png  --grid 3x1 --top-row --fps 9.5
    python3 scripts/sprites/gait_step.py <id> run  build/sprites/<id>/raw/<id>_jog6.png --grid 3x2 --cycle \
        --pick 2,3,1,2,3,5 --no-sparkle --bob 0,-4,-2,0,-4,-2 --fps 8.4 --install

The picture is drawings on flat magenta, side view facing RIGHT. For a single step: drawing 1 = front foot lands,
last drawing = right before the next landing.

Does: cut + scale (walk: the idle height of the sheet; run: the height of the sheet's run row, because a run
crouches), holds the torso at the old row's x (no sideways wobble), optional bounce, prints the planted-foot travel
and the fps, writes build/sprites/<id>/<kind>_step.png (strip) and <kind>_step.gif (old row against the new one,
moving at the real game speed: watch it, the planted foot must not slide). --install writes the row into
Sprites/<id>.png and frames + fps into Sprites/gait.json, which SpriteSheet.swift reads per character.

Speeds come from Characters.swift: walkSpeed, and runSpeed when set (else walkSpeed x 2.2, as in Pet.swift).
"""
import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import assemble_grid as grid  # noqa: E402  (magenta / flood / clean / place shared with the 4x2 grid route)

ROOT = grid.ROOT
SPRITES = grid.SPRITES
CELL = grid.CELL
PX_PER_PT = 2          # sprite px per screen point (256 px cell drawn at 128 pt)
RUN_MUL = 2.2          # Pet.swift: walkSpeed x 2.2 when running and no runSpeed is set


def cut_grid(path, cols, rows, top_row=False, sparkle=True):
    """Cells of a cols x rows picture, magenta keyed out, at half size. top_row: the picture is Gemini's usual 4x2
    grid (it ignores "4x1"); keep the first `cols` drawings of its top row."""
    im = Image.open(path).convert("RGB")
    if top_row:
        a = np.asarray(im).astype(np.int32)
        h2 = im.height // 2
        ink = ~((a[..., 0] > 200) & (a[..., 2] > 200) & (a[..., 1] < 80))
        if (ink[h2 - 1] & ink[h2]).sum() > 20:          # same columns inked just above and below the cut
            print("WARNING: figure crosses the picture's middle line: regrid first")
        im = im.crop((0, 0, im.width * cols // 4, im.height // 2))
    im = im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.int32)
    bg = grid.flood(grid.magenta(rgb))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    edge = np.zeros_like(bg)
    edge[1:] |= bg[:-1]; edge[:-1] |= bg[1:]; edge[:, 1:] |= bg[:, :-1]; edge[:, :-1] |= bg[:, 1:]
    edge &= ~bg
    pink = np.clip((np.minimum(r, b) - g) / 120.0, 0, 1)
    alpha = np.where(bg, 0.0, 1.0)
    alpha = np.where(edge, 1 - pink, alpha)
    alpha = np.where((r > 190) & (b > 170) & (g < 100), 0.0, alpha)   # magenta seen through gaps is background too
    spill = np.clip(np.minimum(r, b) - g, 0, None) * edge
    out = rgb.copy()
    out[..., 0] -= (spill * .8).astype(int)
    out[..., 2] -= (spill * .8).astype(int)
    rgba = np.dstack([np.clip(out, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
    H, W = alpha.shape
    # Gemini's sparkle sits in the bottom-right corner of the WHOLE 16:9 picture. A top-row crop no longer has that
    # corner, and erasing there would cut the front foot off the last drawing.
    if sparkle and H / W > 0.45:
        rgba[int(H * .86):, int(W * .93):, 3] = 0
    cw, ch = W // cols, H // rows
    for k in range(1, cols):   # a drawing crossing a grid line is cut in half
        if (alpha[:, k * cw - 1:k * cw + 1] > 0).any():
            print(f"WARNING: figure crosses vertical line {k}: regrid first")
    return [grid.clean(rgba[(i // cols) * ch:(i // cols + 1) * ch, (i % cols) * cw:(i % cols + 1) * cw].copy())
            for i in range(cols * rows)]


def height(c):
    ys = np.nonzero((c[..., 3] > 60).any(1))[0]
    return ys.max() - ys.min()


def torso_x(im):
    al = np.asarray(im)[..., 3] > 60
    ys, _ = np.nonzero(al)
    t, b = ys.min(), ys.max()
    return np.nonzero(al[int(t + .35 * (b - t)):int(t + .6 * (b - t))])[1].mean()


def feet(im):
    """(x0, x1) of each foot on the lowest 9 pixel rows."""
    al = np.asarray(im)[..., 3] > 60
    bot = np.nonzero(al.any(1))[0].max()
    xs = np.nonzero(al[bot - 8:bot + 1].any(0))[0]
    return [(int(r[0]), int(r[-1])) for r in np.split(xs, np.where(np.diff(xs) > 2)[0] + 1) if len(r) > 3]


def shift(f, dy):
    """Move a whole drawing up (dy < 0) or down; nothing wraps past the cell edge."""
    a = np.asarray(f)
    out = np.zeros_like(a)
    if dy < 0:
        out[:dy] = a[-dy:]
    elif dy > 0:
        out[dy:] = a[:-dy]
    else:
        out = a.copy()
    return Image.fromarray(out)


def unpurple(f, passes=12):
    """Leftover magenta spill (purple specks at the neck, between hair and collar) takes the colour of the solid
    pixels next to it."""
    a = np.asarray(f).copy()
    c = a.astype(int)
    bad = (c[..., 3] > 40) & (c[..., 0] > 90) & (c[..., 2] > 90) & (c[..., 2] > c[..., 1] + 35) & (c[..., 0] > c[..., 1] + 35)
    good = (c[..., 3] > 200) & ~bad
    for _ in range(passes):
        if not bad.any():
            break
        acc = np.zeros(a.shape[:2] + (3,), float)
        n = np.zeros(a.shape[:2], float)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            g = np.roll(good, (dy, dx), (0, 1))
            acc += np.roll(a[..., :3].astype(float), (dy, dx), (0, 1)) * g[..., None]
            n += g
        fix = bad & (n > 0)
        a[fix, :3] = (acc[fix] / n[fix, None]).astype(np.uint8)
        bad &= ~fix
        good |= fix
    return Image.fromarray(a)


def speeds(cid, swift_text):
    """(walkSpeed, runSpeed) of a character in Characters.swift."""
    m = re.search(rf'id: "{cid}"(.*?)\n    \)', swift_text, re.S) or re.search(rf'id: "{cid}"(.*?)Character\(', swift_text, re.S)
    block = m.group(1) if m else ""
    w = re.search(r"walkSpeed: ([\d.]+)", block)
    r = re.search(r"runSpeed: ([\d.]+)", block)
    walk = float(w.group(1)) if w else 100.0
    return walk, float(r.group(1)) if r else walk * RUN_MUL


def write_gait(path, cid, kind, frames, fps):
    data = json.loads(path.read_text()) if path.exists() else {}
    data.setdefault(cid, {})[kind] = {"frames": frames, "fps": fps}
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id")
    ap.add_argument("kind", choices=["walk", "run"])
    ap.add_argument("raw", help="the picture, relative to the repository or absolute")
    ap.add_argument("--grid", default="4x1", help="COLSxROWS of the picture (walk step 4x1, run step 3x1, 6-pose strip 6x1 or 3x2)")
    ap.add_argument("--frames", type=int, help="drawings that make one step (default: all)")
    ap.add_argument("--fps", type=float, help="use this fps (runs: a flight phase makes the planted-foot estimate unreliable)")
    ap.add_argument("--top-row", action="store_true", help="raw is Gemini's full 4x2 picture: use the first COLS drawings of its top row")
    ap.add_argument("--cycle", action="store_true", help="raw is a FULL cycle: play the drawings once, not one step twice")
    ap.add_argument("--pick", help="with --cycle: comma list of drawing numbers (read left to right, top to bottom) in play order; "
                                   "drop any drawing where the forward arm and the forward leg are on the same side (limp)")
    ap.add_argument("--no-sparkle", action="store_true", help="the picture was put together from cells (no Gemini sparkle in its corner)")
    ap.add_argument("--bob", help="vertical offset in px per drawing in play order (negative = up), e.g. 0,-5,-3,0,-5,-3")
    ap.add_argument("--install", action="store_true", help="write the row into Sprites/<id>.png and frames + fps into gait.json")
    o = ap.parse_args(argv)

    cols, rows = map(int, o.grid.split("x"))
    raw = ROOT / o.raw
    if o.cycle:
        allc = cut_grid(raw, cols, rows, o.top_row, sparkle=not o.no_sparkle)
        d = [allc[int(k) - 1] for k in o.pick.split(",")] if o.pick else allc[:o.frames or cols * rows]
        n = max(2, len(d) // 2)
    else:
        d = cut_grid(raw, cols, rows, o.top_row, sparkle=not o.no_sparkle)
        d = d[:o.frames] if o.frames else d[:cols * rows]
        n = len(d)

    L = grid.LAYOUT
    sheet_path = SPRITES / f"{o.id}.png"
    sheet = np.asarray(Image.open(sheet_path).convert("RGBA"))
    cells = lambda name: [sheet[L[name]["row"] * CELL:(L[name]["row"] + 1) * CELL, i * CELL:(i + 1) * CELL]
                          for i in range(L[name]["frames"])]
    idle = cells("idle")
    old = [c for c in cells(o.kind) if (c[..., 3] > 60).any()] or idle
    ref = old if o.kind == "run" and old is not idle else idle
    scale = np.median([height(c) for c in ref]) / np.median([height(x) for x in d])
    frames, s = grid.place(d, scale, {"airborne": o.kind == "run"})

    tx = np.mean([torso_x(Image.fromarray(c)) for c in old])

    def pin(f):   # torso to the old row's x, never past the cell edge
        a = np.asarray(f)
        xs = np.nonzero((a[..., 3] > 0).any(0))[0]
        dx = int(np.clip(round(tx - torso_x(f)), -xs.min(), a.shape[1] - 1 - xs.max()))
        return Image.fromarray(np.roll(a, dx, axis=1))

    step = [pin(f) for f in frames]
    if o.bob:
        offs = [int(v) for v in o.bob.split(",")]
        if len(offs) != len(step):
            ap.error(f"--bob needs one value per drawing ({len(step)})")
        step = [shift(f, dy) for f, dy in zip(step, offs)]

    f = [feet(x) for x in step]
    print("feet per drawing", f)
    walk_speed, run_speed = speeds(o.id, (ROOT / "Sources/OllieBoard/Characters.swift").read_text())
    speed = run_speed if o.kind == "run" else walk_speed
    if o.kind == "walk":     # planted foot: front one in drawing 1 to the back one in drawing n
        travel = (np.mean(f[0][-1]) - np.mean(f[n - 1][0])) / (n - 1)
    else:                    # runs: front shoe of drawing 1 to under the body in drawing 2
        travel = (f[0][-1][1] - 12) - np.mean(f[1][0])
    fps = round(speed * PX_PER_PT / max(travel, 8), 1)
    if o.fps:
        fps = o.fps
    print(f"scale {s:.3f}  travel {travel:.1f}px/drawing  {o.kind} speed {speed:g}  ->  fps {fps}")
    if fps < 5 or fps > 16:
        print("WARNING: fps outside 5-16: the stride is too short/long for this speed: redraw, or change walkSpeed/runSpeed")

    step = [unpurple(x) for x in step]
    row = step if o.cycle else step + step
    if len(row) > 8:
        ap.error(f"{len(row)} drawings do not fit the 8 cells of a row")
    out = ROOT / f"build/sprites/{o.id}"
    out.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (8 * CELL, CELL))
    for i, x in enumerate(row):
        strip.alpha_composite(x, (i * CELL, 0))
    strip.save(out / f"{o.kind}_step.png")

    W, imgs = 1100, []
    olds = [Image.fromarray(c) for c in old]
    old_fps = L[o.kind].get("fps", 12)
    for t in range(int(fps * 3)):
        pic = Image.new("RGB", (W, 600), (235, 235, 235))
        dd = ImageDraw.Draw(pic)
        for k, (label, fr, ff) in enumerate([("now", olds, old_fps), ("new", row, fps)]):
            y0 = k * 300
            dd.line((0, y0 + 270, W, y0 + 270), fill=(120, 120, 120), width=2)
            for x in range(0, W, 40):
                dd.line((x, y0 + 270, x, y0 + 280), fill=(120, 120, 120))
            dd.text((10, y0 + 6), label, fill=(0, 0, 0))
            sec = t / fps
            x = 20 + (sec * speed * PX_PER_PT) % (W - 280)
            im = fr[int(sec * ff) % len(fr)]
            pic.paste(im, (int(x), y0 + 270 - grid.GROUND), im)
        imgs.append(pic)
    imgs[0].save(out / f"{o.kind}_step.gif", save_all=True, append_images=imgs[1:], duration=int(1000 / fps), loop=0)
    print("wrote", out / f"{o.kind}_step.png", "and .gif  (watch the gif: the planted foot must not slide)")

    if o.install:
        a = sheet.copy()
        r0 = L[o.kind]["row"] * CELL
        a[r0:r0 + CELL] = 0
        a[r0:r0 + CELL, :len(row) * CELL] = np.asarray(strip)[:, :len(row) * CELL]
        Image.fromarray(a).save(sheet_path)
        write_gait(SPRITES / "gait.json", o.id, o.kind, len(row), fps)
        print(f"installed row {o.kind} ({len(row)} frames, {fps} fps) and gait.json")
        print("If the walk got slower than walkSpeed allows, set walkSpeed so walkSpeed x 2 = fps x travel, and set"
              " runSpeed in Characters.swift so the run keeps its speed.")


if __name__ == "__main__":
    main()
