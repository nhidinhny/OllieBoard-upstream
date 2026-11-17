"""Checks for gait_step.py with synthetic walk pictures in an isolated folder."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

import assemble_grid as grid
import gait_step
from test_grid import like_sheet

MAGENTA = (255, 0, 255)

SWIFT = '''
let allCharacters: [Character] = [
    Character(
        id: "demo", name: "Demo", series: .onePiece, walkSpeed: 80,
        weights: [.wander: 1], grumpyAnim: .grumpy, shy: false, prankster: false, skills: [],
        runSpeed: 185),
    Character(
        id: "plain", name: "Plain", series: .onePiece, walkSpeed: 100,
        weights: [.wander: 1], grumpyAnim: .grumpy, shy: false, prankster: false, skills: []),
]
'''


def walk_picture(path, cols=4, rows=1, stride=60):
    """cols x rows drawings on magenta: a head, a body and two feet; the front foot moves back `stride` px over the
    drawings of a row, as a planted foot does while the body walks over it."""
    cw, ch = 400, 450
    im = Image.new("RGB", (cols * cw, rows * ch), MAGENTA)
    d = ImageDraw.Draw(im)
    for i in range(cols * rows):
        x, y = (i % cols) * cw, (i // cols) * ch
        foot = y + ch - 40
        d.ellipse((x + 150, foot - 260, x + 250, foot - 160), fill=(240, 200, 180))
        d.rectangle((x + 165, foot - 165, x + 235, foot - 40), fill=(40, 90, 200))
        k = i % cols
        front = x + 260 - k * stride // max(1, cols - 1)
        d.rectangle((front, foot - 40, front + 40, foot), fill=(90, 60, 30))
        d.rectangle((x + 110, foot - 40, x + 150, foot), fill=(90, 60, 30))
    im.save(path)


class GaitStepTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ollieboard-gait-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sprites = self.root / "Sprites"
        self.sprites.mkdir()
        like_sheet(self.sprites / "demo.png", height=180)
        swift = self.root / "Sources/OllieBoard"
        swift.mkdir(parents=True)
        (swift / "Characters.swift").write_text(SWIFT)
        self.raw = self.root / "build/sprites/demo/raw"
        self.raw.mkdir(parents=True)
        for mod in (grid, gait_step):
            p = patch.multiple(mod, ROOT=self.root, SPRITES=self.sprites)
            p.start()
            self.addCleanup(p.stop)

    def run_step(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            gait_step.main(list(args))
        return out.getvalue()

    def row(self, kind):
        sheet = np.asarray(Image.open(self.sprites / "demo.png"))
        r = grid.LAYOUT[kind]["row"]
        return sheet[r * grid.CELL:(r + 1) * grid.CELL]

    def test_speeds_read_run_speed_or_fall_back_to_walk_x_2_2(self):
        self.assertEqual(gait_step.speeds("demo", SWIFT), (80.0, 185.0))
        self.assertEqual(gait_step.speeds("plain", SWIFT), (100.0, 220.00000000000003))

    def test_single_step_is_played_twice_and_fps_follows_the_planted_foot(self):
        walk_picture(self.raw / "walk.png")
        log = self.run_step("demo", "walk", "build/sprites/demo/raw/walk.png", "--grid", "4x1", "--no-sparkle")
        self.assertIn("fps", log)
        fps = float(log.split("->  fps ")[1].split()[0])
        travel = float(log.split("travel ")[1].split("px")[0])
        self.assertGreater(travel, 10)
        self.assertAlmostEqual(fps, 80 * gait_step.PX_PER_PT / travel, delta=0.1)   # walkSpeed x 2 / travel
        strip = np.asarray(Image.open(self.root / "build/sprites/demo/walk_step.png"))
        filled = [(strip[:, i * 256:(i + 1) * 256, 3] > 60).any() for i in range(8)]
        self.assertEqual(filled, [True] * 8)
        self.assertTrue((self.root / "build/sprites/demo/walk_step.gif").exists())
        self.assertFalse((self.sprites / "gait.json").exists())   # nothing installed without --install

    def test_cycle_pick_bob_and_install_write_the_row_and_gait_json(self):
        walk_picture(self.raw / "jog6.png", cols=3, rows=2)
        (self.sprites / "gait.json").write_text(json.dumps({"other": {"walk": {"frames": 6, "fps": 7}}}))
        self.run_step("demo", "run", "build/sprites/demo/raw/jog6.png", "--grid", "3x2", "--cycle",
                      "--pick", "2,3,1,2,3,5", "--no-sparkle", "--bob", "0,-4,-2,0,-4,-2", "--fps", "8.4", "--install")
        gait = json.loads((self.sprites / "gait.json").read_text())
        self.assertEqual(gait["demo"]["run"], {"frames": 6, "fps": 8.4})
        self.assertEqual(gait["other"]["walk"], {"frames": 6, "fps": 7})          # other characters kept
        row = self.row("run")
        filled = [(row[:, i * 256:(i + 1) * 256, 3] > 60).any() for i in range(8)]
        self.assertEqual(filled, [True] * 6 + [False] * 2)
        bottoms = [np.nonzero((row[:, i * 256:(i + 1) * 256, 3] > 60).any(1))[0].max() for i in range(6)]
        self.assertEqual(bottoms[0] - bottoms[1], 4)                              # the bob lifts drawing 2 by 4 px
        self.assertEqual(bottoms[0], bottoms[3])

    def test_bob_needs_one_value_per_drawing(self):
        walk_picture(self.raw / "walk.png")
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_step("demo", "walk", "build/sprites/demo/raw/walk.png", "--grid", "4x1", "--bob", "0,-3")

    def test_unpurple_recolours_magenta_specks(self):
        a = np.zeros((20, 20, 4), np.uint8)
        a[..., :3] = (40, 90, 200)
        a[..., 3] = 255
        a[9:11, 9:11, :3] = (200, 60, 200)
        out = np.asarray(gait_step.unpurple(Image.fromarray(a)))
        self.assertTrue((out[9:11, 9:11, :3] == (40, 90, 200)).all())


if __name__ == "__main__":
    unittest.main()
