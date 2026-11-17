"""Checks for assemble_grid.py with synthetic 4x2 pictures in an isolated folder."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

import assemble_grid as grid

MAGENTA = (255, 0, 255)
SKIN = (240, 200, 180)


def grid_picture(path, height=200, jump=0):
    """8 drawings on magenta: a skin-coloured head over a blue body, `height` px tall, the bottom row `jump` px up."""
    w, h = 1600, 900
    im = Image.new("RGB", (w, h), MAGENTA)
    d = ImageDraw.Draw(im)
    cw, ch = w // 4, h // 2
    for i in range(8):
        x, y = (i % 4) * cw, (i // 4) * ch
        foot = y + ch - 40 - (jump if i >= 4 else 0)
        top = foot - height
        d.ellipse((x + 150, top, x + 250, top + 100), fill=SKIN)
        d.rectangle((x + 160, top + 90, x + 240, foot), fill=(40, 90, 200))
    im.save(path)


def like_sheet(path, height=150, skin=(250, 225, 215)):
    """A sheet of a character already in the game: every frame `height` px tall, feet on the ground line."""
    rows = 1 + max(v["row"] for v in grid.LAYOUT.values())
    sheet = Image.new("RGBA", (8 * grid.CELL, rows * grid.CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for r in range(rows):
        for c in range(8):
            x, y = c * grid.CELL, r * grid.CELL
            top = y + grid.GROUND - height
            d.ellipse((x + 98, top, x + 158, top + 60), fill=skin + (255,))
            d.rectangle((x + 104, top + 55, x + 152, y + grid.GROUND), fill=(30, 140, 60, 255))
    sheet.save(path)


class GridTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ollieboard-grid-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sprites = self.root / "Sprites"
        self.sprites.mkdir()
        like_sheet(self.sprites / "luffy.png")
        raw = self.root / "build/sprites/demo/raw"
        raw.mkdir(parents=True)
        grid_picture(raw / "demo_stand.png")
        grid_picture(raw / "demo_jump.png", jump=60)
        patcher = patch.multiple(grid, ROOT=self.root, SPRITES=self.sprites)
        patcher.start()
        self.addCleanup(patcher.stop)

    def rows(self, rows):
        (self.root / "build/sprites/demo/rows.json").write_text(json.dumps({"rows": rows}))

    def run_grid(self, *args):
        out = io.StringIO()
        with patch.object(sys, "argv", ["assemble_grid.py", "demo", "--like", "luffy", *args]), \
                contextlib.redirect_stdout(out):
            grid.main()
        return np.asarray(Image.open(self.root / "build/sprites/demo/demo.png")), out.getvalue()

    def cell(self, sheet, name, col):
        row = grid.LAYOUT[name]["row"]
        return sheet[row * grid.CELL:(row + 1) * grid.CELL, col * grid.CELL:(col + 1) * grid.CELL]

    def test_scale_follows_the_like_character_and_feet_land_on_the_ground(self):
        self.rows([{"row": "idle", "picture": "stand", "cells": [0, 1, 2, 3]}])
        sheet, log = self.run_grid()
        self.assertIn("not in rows.json", log)
        for name in grid.ROW_NAMES:
            a = self.cell(sheet, name, 0)[..., 3]
            ys = np.nonzero((a > 40).any(1))[0]
            self.assertAlmostEqual(ys.max(), grid.GROUND, delta=2, msg=name)
            self.assertAlmostEqual(ys.max() - ys.min(), 150, delta=4, msg=name)

    def test_airborne_rows_keep_the_jump(self):
        self.rows([{"row": "idle", "picture": "stand", "cells": [0, 1, 2, 3]},
                   {"row": "happy", "picture": "jump", "cells": [0, 1, 4, 5, 0, 1], "airborne": True}])
        sheet, _ = self.run_grid()
        ground = np.nonzero((self.cell(sheet, "happy", 0)[..., 3] > 40).any(1))[0].max()
        up = np.nonzero((self.cell(sheet, "happy", 2)[..., 3] > 40).any(1))[0].max()
        self.assertAlmostEqual(ground, grid.GROUND, delta=2)
        self.assertGreater(ground - up, 30)

    def test_match_skin_moves_only_the_skin(self):
        self.rows([{"row": "idle", "picture": "stand", "cells": [0, 1, 2, 3]}])
        sheet, log = self.run_grid("--match-skin")
        self.assertIn("skin: median", log)
        c = self.cell(sheet, "idle", 0)
        opaque = c[..., 3] == 255
        colours = {tuple(p) for p in c[opaque][:, :3]}
        self.assertIn((250, 225, 215), colours)
        self.assertIn((40, 90, 200), colours)

    def test_install_refuses_rows_that_were_not_drawn(self):
        self.rows([{"row": "idle", "picture": "stand", "cells": [0, 1, 2, 3]}])
        with self.assertRaises(SystemExit):
            self.run_grid("--install")
        self.assertFalse((self.sprites / "demo.png").exists())

    def test_install_lists_the_sheet(self):
        self.rows([{"row": name, "picture": "stand", "cells": ([0, 1, 2, 3] * 2)[:grid.LAYOUT[name]["frames"]]}
                   for name in grid.ROW_NAMES])
        (self.sprites / "custom-sheets.txt").write_text("# custom\nluffy\n")
        self.run_grid("--install")
        self.assertTrue((self.sprites / "demo.png").exists())
        self.assertEqual((self.sprites / "custom-sheets.txt").read_text(), "# custom\nluffy\ndemo\n")

    def test_style_ref(self):
        out = self.root / "style.png"
        with patch.object(sys, "argv", ["assemble_grid.py", "demo", "--like", "luffy", "--style-ref", str(out)]), \
                contextlib.redirect_stdout(io.StringIO()):
            grid.main()
        with Image.open(out) as image:
            self.assertEqual(image.size, (6 * grid.CELL * 2, grid.CELL * 2))


if __name__ == "__main__":
    unittest.main()
