---
name: gemini-gait-prompts
description: Redraw a character's walk or run row with Gemini so the feet do not slide and the gait does not limp - Gemini chat flow, one-step and six-pose prompts, scripts/sprites/gait_step.py (cut, scale, bounce, fps from the planted foot, install into gait.json), the rules learned on Luffy and Mikoto, and the fixes for a stiff, limping or stuttering gait. Use when redoing a walk, run, jump or dragged row, or when a gait looks stiff, limps, stutters or has extra limbs.
---

# Walk and run rows with Gemini

Everything needed is in this skill and in `scripts/sprites/gait_step.py`. For whole sheets and other rows see
`update-sprites` (and its `references/gemini-grid.md`, `references/skill-rows.md`).

How the game plays a gait: the pet moves at `walkSpeed` points per second (Characters.swift), and at `runSpeed` when
it runs (default `walkSpeed x 2.2`), while the row plays at a fixed fps. The planted foot only stays put if

    fps = speed x 2 (sprite px per point) / (px the planted foot moves back per drawing)

The shared layout (walk 8 frames 12 fps, run 6 frames 16 fps) is wrong for almost every redrawn gait, so each
character can override a row's `frames` and `fps` in `Sources/OllieBoard/Resources/Sprites/gait.json`:

```json
{ "luffy": { "walk": { "frames": 6, "fps": 6 }, "run": { "frames": 6, "fps": 8.4 } } }
```

Luffy today: `walkSpeed: 74`, `runSpeed: 185`, walk 6 drawings at 6 fps, run 6 drawings at 8.4 fps.

## 1. Rules (all learned the hard way; the user reviewing the sprites is the judge)

1. **The arm on one side swings with the leg on the OTHER side, in every frame.** Check each frame, not the sheet.
2. **Between two leg switches there is a frame with one foot down and one foot up**, and the lifted foot reaches the
   **same height on both sides** (Luffy once had 82 px vs 20 px: it looked jerky). Measure it.
3. **Walk: one in-between (swing) frame right before each leg switch**: the lifted leg passes under the hip, foot a
   few px off the ground, arms close to the body. Without it the walk looks like frames are missing.
4. **Small knee lifts, no extra lift or flight frames in a light jog** (Luffy's run with a knee-up frame was rejected
   as "an extra step"). No fake limb shading (do not paint depth onto a flat limb).
5. **ONE facial expression across the whole loop.** A mouth that changes every frame looks wrong; life comes from
   head tilt and bounce.
6. **Count feet and arms on every frame at full size** (exactly 2 and 2). Gemini sometimes draws a 3rd foot: reject
   the drawing, do not fix it by hand.
7. **Same head size and skin tone as idle** in every row. Never graft the upper body of an old row onto new legs:
   the head size jumps.
8. **"The other leg" means the left and right legs really trade places**, not a sock or cuff colour swap on the same
   outlines. Ordering drawings by cuff colour instead of leg shape made a limp.
9. Show **static frames first**, animate only after they are approved. Ask before using another character as a
   reference (pose-only use was allowed once, for Mikoto from Luffy).
10. Never take screenshots of the user's desktop to check a gait; check the files (strip, GIF) and ask the user to
    look at the running app.

## 2. Driving Gemini (browser tool, e.g. Claude in Chrome)

- Gemini Pro, one chat per character and gait so the design stays the same. Note the chat URL to come back to it.
  Ask which Google account to use if several are signed in.
- Upload through the page's hidden `input[type=file]`. **Text sent together with an upload is often lost**: send the
  pictures with a short "Describe these pictures" first, then the real request as the next message. If the
  describe message fails ("something went wrong"), sending the request directly worked.
- Download with the last "Download full size image" button and move the file into
  `build/sprites/<id>/raw/<id>_<name>.png`. Check that the saved file is the picture you meant (open it) before going on.
- Gemini returns a 4x2 grid whatever grid you ask for; ask for 4x2 and use the top row (`--top-row`), or ask for
  "ONE row of six drawings" for a six-pose strip.
- If Gemini refuses a pose, describe it more gently ("kick" was refused for Shisui; "taps a ball with her foot" worked).
- A chat that keeps returning the same image is stuck: start a new chat with the same pictures.

## 3. Quick route: one step played twice

Good for characters whose two legs look alike (same socks and shoes). Ask, in the character's chat:

> Using exactly this <name> and this art style (same chibi proportions, thick dark outline, flat cel shading, <hair,
> outfit, shoes>), draw ONE walking step: 8 drawings in a grid of 4 columns x 2 rows (16:9), but only the first 4
> drawings matter and the bottom row repeats them. Side view facing RIGHT (profile, not toward the viewer).
> Drawing 1: front foot lands on the ground, back leg behind. Drawing 2: weight over the front foot. Drawing 3: legs
> pass each other. Drawing 4: back foot about to leave the ground, just before the next landing. Arms swing opposite
> to the legs. Both legs look alike (same socks and shoes). FULL BODY, feet visible and sharp in every drawing. Same
> size and same ground line in every drawing. Each drawing stays inside its own cell with a wide magenta gap; NO
> divider lines, NO borders. Background: perfectly flat solid pure magenta #FF00FF, no gradient, no shadow, no text.
> Crisp single drawings: no motion blur, no afterimage, no speed lines.

Run step: same chat, "ONE running step ... only the first 3 drawings matter. Drawing 1: front foot touches down, body
leaning forward. Drawing 2: body crouches low and pushes off. Drawing 3: other leg kicks back, both feet briefly off
the ground. Arms bent and pumping opposite to the legs." plus the same size / magenta / crisp sentences. Add what the
character would otherwise get wrong ("hair stays behind her and does not cover the legs", "swords stay at the hip",
"hands in pockets is NOT wanted").

```sh
python3 scripts/sprites/gait_step.py <id> walk build/sprites/<id>/raw/<id>_walkstep.png --grid 4x1 --top-row
python3 scripts/sprites/gait_step.py <id> run  build/sprites/<id>/raw/<id>_runstep.png  --grid 3x1 --top-row --fps 9.5
```

It prints the planted-foot travel and the fps and writes `build/sprites/<id>/<kind>_step.png` and `<kind>_step.gif`
(old row against the new one, moving at the game's speed). **Watch the GIF: the planted foot must not slide and the
pet must not judder.** Then add `--install` (writes the row and `gait.json`). Runs have a flight phase, so the
computed run fps is unreliable: pass `--fps` (8.4-10.5 so far) after looking at the strip.

A step played twice swings the same arm on both steps. If that reads as a limp, or the legs differ on purpose
(Maomao: white sock vs dark stocking), use the six-pose route.

## 4. Six-pose route (what finally worked for Mikoto's walk and Luffy's run)

1. **Pose reference: a dressed mannequin strip.** Six simple figures in one row on magenta, no labels, in the
   character's build: the NEAR leg light with a white cuff/sock, the FAR leg darker with a grey one, and the leg
   that is in front drawn on top. A plain two-colour mannequin is ignored; the dressed one makes Gemini put the FAR
   leg forward when asked, which it otherwise never does. Draw it with a few lines of PIL from joint angles, or in any
   drawing tool.
   - Walk (6 poses): contact, passing (one foot down, other lifted), swing, then the same three with the legs traded.
   - Light jog (6 poses), the rhythm Luffy's run was approved with: **kick back -> legs together under the body ->
     legs wide**, then the same with the other leg. Low heel kick, small knee lift, slight forward lean.
2. **Style reference:** one crisp drawing of the character from the game (crop off any sparkle).
3. **All six poses in ONE generation**, fresh Gemini Pro chat, style first, mannequin second. Prompts:
   [walk-strip6-prompt.md](references/walk-strip6-prompt.md) and
   [run-jog6-prompt.md](references/run-jog6-prompt.md). One picture keeps one build, face and size; generating
   one frame per chat drifts (body, socks, line weight, face angle) and 15 tries never gave a consistent set.
4. **Fix a few frames in the same chat**: it redraws the whole strip, so take the good frames from each version
   (same chat, so they line up). A leg that came out as a stiff mannequin tube: crop that one drawing on a magenta
   square, new chat, attach it plus the style drawing, "keep everything, change ONLY the <which> leg: redraw it as a
   real leg like picture 2, same pose".
5. **Pick and order by leg shape**, not by cuff colour, and drop drawings where arm and leg on the same side are
   forward together. Luffy's run uses drawings `2,3,1,2,3,5` of his jog strip.
6. **Arms**: Gemini cannot swap which arm is in front, even with a mannequin (it reverts on the next edit). If the
   arm swing is wrong, swing it in code: cut the forearm and fist, rotate them about the elbow (about +-12 degrees,
   opposite to the legs; 22 looked like flapping), keep a seam band at the elbow so no gap opens.
7. **Install** (6 cells put in a 3x2 grid, or a 6x1 strip):

   ```sh
   python3 scripts/sprites/gait_step.py <id> run build/sprites/<id>/raw/<id>_jog6.png --grid 3x2 --cycle \
       --pick 2,3,1,2,3,5 --no-sparkle --bob 0,-4,-2,0,-4,-2 --fps 8.4 --install
   ```

   For a full cycle the computed travel is wrong: measure the planted foot from contact to contact yourself
   (Mikoto 18.5 px per frame) and pass `--fps`. Then set `walkSpeed` so `walkSpeed x 2 = fps x travel`, and
   `runSpeed` (Characters.swift) so the run keeps its speed (Mikoto: 6 fps, walkSpeed 56; Luffy: walkSpeed 74,
   runSpeed 185).
8. **Compare with idle**: skin (new drawings came out pinker: move skin pixels so their median matches idle's face;
   `assemble.py` has `grade_skin` / `estimate_skin`) and head size (scale a row about the feet anchor (128, 244) if
   its head is smaller, and divide its fps by the same factor).

## 5. Editing single drawings (when only one thing is wrong)

Always attach the drawing to edit (a prompt sent without images makes Gemini draw something unrelated). End every
prompt with: `One single drawing, flat magenta (#FF00FF) background, no sparkles, no text.`

**Raise the lifted foot higher / equalise both sides:**
> Edit picture 1 (keep it exactly: same character, clothes, size, style, background, same arms). Change ONLY the
> raised back foot. In picture 1 the back foot is lifted only a little. Lift it much higher, exactly like the back
> foot in picture 2: knee bent, shin angled back, the sole clearly off the ground, roughly 1/4 of the leg length above
> the ground line. The planted foot stays flat on the ground. Do not change the arms or the front leg.

**Legs only (run pass frame):**
> Edit picture 1 (a running <name>): keep EVERYTHING exactly the same, both ARMS exactly as they are. Change ONLY the
> legs, to the passing moment of the run shown in picture 2: one foot planted flat under the body, the OTHER foot
> lifted behind with the shin angled back and the sole clearly off the ground (about 1/3 of the leg length up). The
> character has EXACTLY TWO legs and TWO feet (no extra leg).

**Swing / in-between frame** (picture 1 = back foot raised, picture 2 = the next drawing, legs wide). The capitalised
two-feet sentence is what fixed a 3-feet result:
> Draw ONE new drawing exactly halfway between picture 1 and picture 2 in time: same character, size, style and
> background. IMPORTANT: the character has EXACTLY TWO legs and TWO feet (never three, no ghost or duplicate leg). One
> foot is planted flat on the ground under the body. The other leg has swung forward: thigh and knee slightly
> forward, shin hanging down, that foot just above the ground (about 1/8 of the leg length) and a little in front of
> the planted foot. The body stays the same height as in picture 1. Arms close to the body, halfway between the two
> pictures.

A run swing frame failed twice (3 feet, then a frontal one-legged pose): runs keep their drawings without one.

**Change only the mouth:**
> Edit THIS drawing. Keep EVERYTHING exactly the same: pose, both legs and feet, arms, hair, clothes, size, position
> and background. Change ONLY the mouth: <the expression>. Do not change anything else.

Better than asking per frame: transplant one mouth. Align the grin picture on the eye-white centres, take the
difference against the source inside `y in [eyes + 0.4d, eyes + 1.0d]`, `x in [-0.8d, +1.1d]` (d = eye distance),
keep the largest blob and paste it on the other frames shifted by their eye offsets. A taller mask picks up arm pixels.

**Graft** when Gemini fixed one half and broke the other: cut both drawings at the top of the sash/belt and join the
good upper body to the good legs (same chat only, so the sizes match). Not across rows (rule 7).

**Head tilt** for life without changing the face: rotate the head (everything above the neck) about the neck,
about +2.5 degrees on contact frames, -1.5 on passing frames, 0 on swing frames. **Bounce**: `gait_step.py --bob`.

What does not work (do not spend tries on it): asking for the far arm to be hidden behind the chest; asking an edit
to make the near leg cover the far leg (only recolours socks); "draw the mirror / opposite step" (returns the same
legs); a full-body reference when you want a new camera angle (Gemini copies its angle; attach only a head crop).

## 6. 3/4 view

In pure side view the two contact frames look the same whichever leg is forward. A 3/4 walk makes left and right
readable (near leg lower on the page, overlapping the far leg) but looks different from side-view rows: ask before
installing one. Gemini always draws the NEAR leg forward at contact in a 3/4 walk; **passing frames do work**, each in
its own fresh chat ("near leg standing straight in front, far leg lifted behind it, mostly hidden"). For the
far-leg-forward contact use the six-pose route with a dressed mannequin, or a drawing that already has that pose as a
pose-only reference. Hand-built far-leg contacts and mixing separate generations flickered and were rejected.

## 7. Jump, happy and dragged rows (old blurry rows in the new style)

Attach (1) one crisp frame of the new walk as the style and (2) a strip of the old poses, and say image 2 only gives
the pose:
> Image 1 is the exact style to keep: crisp single drawing, thick dark outline, clean cel shading, same head size,
> hat, outfit and colours. Image 2 only shows the POSE I want (old, blurry, off-style). Redraw image 2's poses in
> image 1's crisp style: ONE picture with the drawings side by side on flat pure magenta #FF00FF, each in its own cell
> with a wide gap. <pose per drawing>. Side/three-quarter view facing RIGHT. FULL BODY, exactly TWO legs and TWO feet
> per drawing, exactly two arms. Same size as image 1. Crisp clean edges: no blur, no halo, no extra limbs, no text,
> no shadows, no divider lines, no sparkles.

Build the row with `assemble_grid.py` (rows.json with `"airborne": true` keeps a jump in the air; `"anchor": "head"`
keeps a dangling figure under the hand). Dragged row: [dragged-prompt.md](references/dragged-prompt.md). Check
**every row that copies old art** (Luffy's habit row held a copy of the old jump). A pink matte fringe or a thin
outline is the sign a row is old art and needs the redraw.

## 8. Checklist before installing

- [ ] 2 feet, 2 arms on every frame (at full size)
- [ ] arm opposite to the forward leg in every frame; lifted foot the same height on both sides
- [ ] one-foot-down frame between switches; swing frame before each switch (walk); no extra knee-up frame (jog)
- [ ] one expression; head size and skin match idle; no purple specks near fists or neck
- [ ] the GIF from `gait_step.py`: planted foot does not slide, no judder
- [ ] static frames approved, then the GIF, then `--install`
- [ ] `gait.json` has the row's `frames` and `fps`; `walkSpeed` / `runSpeed` set to match
- [ ] `swift build -c release --product OllieBoard`, then the user checks it in the running app

## 9. Stutter ("khựng") and limp fixes

1. Planted-foot travel uneven between frames (e.g. 20, 6, 55 px) = some leg poses are wrong: redraw those frames.
   A wrong speed/fps match gives an even slide, not a stutter.
2. A foot in the air twice per cycle reads as a limp: order the drawings by leg shape (contact, passing, contact).
3. Arms on the same side as the forward leg: drop that drawing (`--pick`) or swing the arms in code (section 4.6).
4. Add a small bob (`--bob`, e.g. 0,-5,-3) and keep torso and head pinned otherwise (`gait_step.py` pins the torso
   to the old row's x).
