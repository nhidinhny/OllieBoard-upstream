"""Checks for build_skill_rows.py and gen_skill_prompts.py with synthetic pictures in an isolated folder."""
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

import build_skill_rows as build

MAGENTA = (255, 0, 255)


def grid_picture(path, cols=4, rows=2, wide=False):
    """cols x rows drawings on magenta: a head and a body, plus (wide) a prop sticking out to the right."""
    w, h = 1024, 572
    im = Image.new("RGB", (w, h), MAGENTA)
    d = ImageDraw.Draw(im)
    cw, ch = w // cols, h // rows
    for r in range(rows):
        for c in range(cols):
            x, y = c * cw, r * ch
            d.rectangle((x + 50, y + 60, x + 110, y + ch - 30), fill=(40, 120, 220))
            d.ellipse((x + 45, y + 10, x + 115, y + 75), fill=(60, 140, 40))
            if wide:
                d.rectangle((x + 130, y + 80, x + cw - 20, y + ch - 30), fill=(230, 200, 30))
    im.save(path)


class SkillRowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ollieboard-skill-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "assets" / "skills").mkdir(parents=True)
        self.sprites = self.root / "Sprites"
        self.sprites.mkdir()
        grid_picture(self.root / "assets" / "skills" / "luffy_demo.png", wide=True)
        patcher = patch.multiple(build, ROOT=str(self.root), SPRITES=str(self.sprites))
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_build(self, *rows):
        with contextlib.redirect_stdout(io.StringIO()):
            return build.build_skill("luffy", list(rows))

    def test_row_is_eight_cells_and_listed_in_skills_json_entry(self):
        meta = self.run_build({"name": "demo", "height": 200, "anchor": 0.3, "fps": 6})
        self.assertEqual(meta, {"rows": [{"name": "demo", "frames": 8, "fps": 6, "loop": True, "shift": 0}]})
        sheet = Image.open(self.sprites / "luffy-skills.png")
        self.assertEqual(sheet.size, (2048, 256))

    def test_nothing_touches_the_cell_edge_and_feet_are_on_the_ground_line(self):
        self.run_build({"name": "demo", "height": 200, "anchor": 0.3, "cx": 88, "shift": 20, "fps": 6})
        a = np.asarray(Image.open(self.sprites / "luffy-skills.png"))[..., 3]
        for i in range(8):
            cell = a[:, i * 256:(i + 1) * 256]
            ys, xs = np.nonzero(cell > 24)
            self.assertGreater(ys.min(), 1); self.assertLess(ys.max(), 255)
            self.assertGreater(xs.min(), 1); self.assertLess(xs.max(), 255)
            self.assertAlmostEqual(int(ys.max()), build.GROUND_Y, delta=3)

    def test_first_frames_and_grid_options(self):
        grid_picture(self.root / "assets" / "skills" / "luffy_six.png", cols=3, rows=2)
        meta = self.run_build({"name": "six", "grid": [3, 2], "frames": 6, "height": 200, "fps": 8})
        self.assertEqual(meta["rows"][0]["frames"], 6)
        a = np.asarray(Image.open(self.sprites / "luffy-skills.png"))[..., 3]
        self.assertTrue((a[:, 6 * 256:] == 0).all())          # the last two cells stay empty

    def test_head_norm_keeps_the_head_width(self):
        picture = Image.new("RGB", (1024, 572), MAGENTA)
        d = ImageDraw.Draw(picture)
        for i in range(8):                                    # the head gets narrower while the body grows
            x, y = (i % 4) * 256, (i // 4) * 286
            head = 80 - i * 4
            d.ellipse((x + 128 - head // 2, y + 10, x + 128 + head // 2, y + 10 + head), fill=(60, 140, 40))
            d.rectangle((x + 128 - 20 - i * 6, y + 10 + head, x + 128 + 20 + i * 6, y + 250), fill=(40, 120, 220))
        picture.save(self.root / "assets" / "skills" / "luffy_fat.png")
        self.run_build({"name": "fat", "height": 200, "fps": 6, "head_norm": True, "loop": False})
        a = np.asarray(Image.open(self.sprites / "luffy-skills.png"))
        widths = []
        for i in range(8):
            cell = a[:, i * 256:(i + 1) * 256, 3]
            ys = np.nonzero((cell > 24).any(axis=1))[0]
            band = cell[ys.min():ys.min() + int((ys.max() - ys.min()) * 0.3)]     # the head: top 30 percent of the drawing
            xs = np.nonzero((band > 24).any(axis=0))[0]
            widths.append(xs.max() - xs.min())
        self.assertLess(max(widths) - min(widths), 6)

    def test_magenta_fringe_and_sparkle_are_removed(self):
        grid_picture(self.root / "assets" / "skills" / "luffy_demo.png")
        im = Image.open(self.root / "assets" / "skills" / "luffy_demo.png")
        ImageDraw.Draw(im).polygon([(930, 515), (950, 495), (970, 515), (950, 535)], fill=(255, 130, 255))   # corner sparkle
        im.save(self.root / "assets" / "skills" / "luffy_demo.png")
        self.run_build({"name": "demo", "height": 200, "fps": 6})
        a = np.asarray(Image.open(self.sprites / "luffy-skills.png"))
        solid = a[a[..., 3] > 200][:, :3].astype(int)
        self.assertEqual(int(((solid[:, 0] > 200) & (solid[:, 2] > 200) & (solid[:, 1] < 80)).sum()), 0)    # no magenta left
        last = a[:, 7 * 256:, 3]
        xs = np.nonzero((last > 24).any(axis=0))[0]
        self.assertLess(xs.max() - xs.min(), 100)                                                         # only the figure, no sparkle


if __name__ == "__main__":
    unittest.main()
