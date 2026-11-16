---
name: gemini-gait-prompts
description: Gemini prompts and rules that gave a natural walk and run for OllieBoard pets (learned on Luffy, 2026-11-09) - edit one drawing instead of generating grids, contralateral arms, swing frame, one expression, head tilt, bounce. Use when redoing a character's walk, run or jump row, or when a gait looks stiff, limping or has extra limbs.
---

# Gemini prompts for walk and run (Luffy, 2026-11-09)

Complements `gemini-sprites` (section 5: one step as a 4x2 grid + `scripts/gait-step.py`). Use this when that first
result looks stiff or limps. Chat flow, upload, download and scratchpad pitfalls are in `gemini-sprites` section 2
and the HANDOFF in `build/sprites/_gaitwork/HANDOFF.md`.

## Rules from Nhi (all learned the hard way)

1. **Arm on one side goes with the leg on the OTHER side in every frame.** Check each frame, not just the sheet.
2. **Between two leg switches there must be a frame with one foot down, one foot up**, and the lifted foot reaches the
   **same height on both sides** (Luffy once had 82 px vs 20 px: it looked jerky). Measure it.
3. **Add one in-between (swing) frame right before each leg switch**: lifted leg passes under the hip, foot a few px
   off the ground, arms close to the body. Without it the walk looks like frames are missing.
4. **Small knee lifts.** No fake limb shading (do not paint depth on a flat limb).
5. **Keep ONE facial expression across the whole loop.** A mouth that changes every frame looks unnatural. Alive-ness
   comes from head tilt + bounce, not from face swaps.
6. **Count feet on every new frame at full size** (exactly 2 sandals, 2 arms). Gemini sometimes draws a 3rd foot;
   reject it, do not fix it by hand.
7. Show **static frames first**, animate only after she approves. Do not use another character as the model.
8. Never open `~/Downloads`; download only into `~/Downloads/downloaded/`. Never screen-capture her desktop.

## Method that worked

- **Edit ONE existing drawing; do not ask for new grids.** Edits keep the style, new grids drift. Always attach the
  drawing to edit (a prompt sent without images makes Gemini draw something unrelated: stop it and re-upload from
  the CURRENT scratchpad folder, `file_upload` refuses other paths).
- **Graft** (`graft.py`): cut at the top of the sash and join the upper body of one drawing with the legs of another
  when Gemini changes one half correctly but breaks the other.
- Check which leg is in front with the cuffs (`cuff.py`: the far leg is greyer).
- Gemini **cannot change which arm is in front** (depth/occlusion), even when told. Two attempts failed; keep the
  flat versions and get the difference from tilt + bounce.
- After the drawings are fixed: grin transplant (one expression for all frames), `headtilt.py` (head blob rotated
  around the neck: +2.5 deg on contact frames, -1.5 on pass frames, 0 on swing), `gait-step.py --bob` for bounce
  (e.g. `--bob 0,-5,-3,0,-5,-3`), `--cycle --pick ... --no-sparkle`, `unpurple()` removes magenta specks.
- A row with fewer drawings than the layout cells (6 of 8) is fine: `SpriteSheet.swift` drops blank trailing cells.
- fps from the planted-foot estimate; Luffy: walk 6, run 9.4.

## Prompts (replace Luffy's parts; always end with the magenta sentence)

End of every prompt: `One single drawing, flat magenta (#FF00FF) background, no sparkles, no text.`

**Swap the arms only** (picture 1 = drawing, picture 2 = a drawing that already has the wanted arm swing):
> Edit picture 1 (keep it exactly: same Luffy, hat, face, jacket, shorts, sash, same size and style, same background,
> same legs and feet). Change ONLY the arms. Right now the RIGHT (near) arm is bent at the chest and the other arm is
> hidden. I need the OPPOSITE arm swing, like picture 2: the LEFT (far) arm swung forward with the fist out in front of
> the chest, and the RIGHT (near) arm swung back behind the body with the fist behind the hip, both clearly visible.
> Do not change the legs.

For a run add: `Keep the arms bent like a runner (elbows bent), not straight.` and name the picture "a running Luffy".

**Raise the lifted foot higher / equalise both sides:**
> Edit picture 1 (keep it exactly ... same arms ...). Change ONLY the raised back foot. In picture 1 the back foot is
> lifted only a little. Lift it much higher, exactly like the back foot in picture 2: knee bent, shin angled back,
> the sole of the sandal clearly off the ground, roughly 1/4 of the leg length above the ground line. The planted
> foot stays flat on the ground. Do not change the arms or the front leg.

**Legs only (run pass frame):**
> Edit picture 1 (a running Luffy): keep EVERYTHING exactly the same: ..., both ARMS exactly as they are, ...
> Change ONLY the legs, to the passing moment of the run shown in picture 2: one foot planted flat under the body, the
> OTHER foot lifted behind with the shin angled back and the sandal sole clearly off the ground (about 1/3 of the leg
> length up). The character has EXACTLY TWO legs and TWO feet (two sandals in total, no extra leg).

**Swing / in-between frame** (picture 1 = back foot raised, picture 2 = next drawing, legs wide). Version that worked
after a 3-feet failure; the capitalised two-feet sentence is what fixed it:
> Picture 1 is a walk drawing with the back foot raised behind. Picture 2 is the next walk drawing with the legs wide
> apart. Draw ONE new drawing exactly halfway between picture 1 and picture 2 in time: same Luffy, hat, face, jacket,
> shorts, sash, same size, style and background. IMPORTANT: the character has EXACTLY TWO legs and TWO feet (two
> sandals in total, never three, no ghost or duplicate leg). One foot is planted flat on the ground under the body.
> The other leg has swung forward: thigh and knee slightly forward, shin hanging down, that foot just above the ground
> (about 1/8 of the leg length) and a little in front of the planted foot, so the two legs are close and the two
> sandals are clearly separate and at different heights. The body stays the same height as in picture 1. Arms close
> to the body halfway between the two pictures.

The run swing frame failed twice (3 feet, then a frontal one-legged pose): the run keeps 4 drawings, no swing.

**Change only the mouth** (to put one grin on every frame; better still, transplant the mouth, see below):
> Edit THIS drawing. Keep EVERYTHING exactly the same: pose, both legs and both feet (exactly two sandals), arms, hat,
> hair, clothes, size, position and the background. Change ONLY the mouth: replace the closed smile with a big
> open-mouth happy grin showing the top teeth, same eyes. Do not change anything else.

Mouth transplant: align the grin picture on the eye-white centres, diff against the source, mask
`y in [eyes+0.4d, eyes+1.0d]` and `x in [-0.8d, +1.1d]` (d = eye distance, ~94 px), keep the largest blob, paste on
the other frames shifted by their eye offsets. A mask taller than the face pastes arm pixels (arm glitch near the fist).

**Depth redraw (FAILED twice, do not repeat):** asking for the far arm to be hidden behind the chest. Gemini keeps
both arms visible.

## Leg switch / 3/4 view (Mikoto, 2026-11-10)

- **"This leg / the other leg" means her LEFT and RIGHT legs really trade places**, not a sock or cuff colour swap.
  A colour swap on the same outlines is NOT a leg switch (Mikoto walk v2 rejected for this).
- In pure side view the two contact frames look the same whichever leg is forward. To make left/right readable, draw
  the walk in **3/4 (front three-quarter) view**: near leg lower on the page and overlapping the far leg. A 3/4 walk
  looks different from side-view rows (run): ask Nhi before installing.
- Gemini **cannot change which leg is in front** (occlusion), same as arms: edits asking the near leg to cover the far
  leg only recolour socks (3 tries failed).
- **A full-body reference anchors the camera angle and pose**: Gemini copies it even when told "3/4 view". Attach
  ONLY a **head crop** as the style reference to get a new angle.
- "Draw 2 = the mirror/opposite step" and "edit A so the legs switch" both returned the SAME legs. Do not repeat.
  A fresh chat (head-only ref) describing the B legs absolutely also FAILED 3 times (2026-11-10, chat
  `ca98963eff928552`): by picture side, by which leg overlaps, and by her anatomical left/right. Gemini always draws
  the NEAR leg forward in a 3/4 walk. Do not spend more tries on wording. Asking a chat for "the next moment" after a
  good passing frame (far leg lifted) also came back near-leg-forward. **Passing frames DO work**, each in its own
  fresh chat: "near leg standing straight in front, far leg lifted behind it, mostly hidden" gave the real other-leg
  frame (Mikoto qP2). A follow-up asking for a new pose in a chat that is stuck returns the same image: start a new
  chat. The far-leg-forward contact has to be built by hand: mirror A's legs below the skirt, swap A's own loafers
  onto the new legs, then **repaint the overlap so the FORWARD leg's thigh is in front** (Nhi: the back leg's thigh
  covering the front leg looks like crossed legs). Tools in `build/sprites/_gaitwork/tools/` (buildB4, cleanB,
  frontthigh). Nhi rejected the hand-built B anyway, and a 3/4 walk mixing separate generations flickers.
- Fresh side-view full-cycle grids for Mikoto (2 tries, 2026-11-10) never drew the far leg in front either: Gemini
  always puts the near leg forward at contact. Luffy's grid did contain one (luffy_WB), so it is luck per grid; for a
  character whose two legs look different, budget for it failing. The Thinking model did no better (turned her
  to face LEFT, near leg forward again, and drifted off the chibi style).
- **What worked (Pro):** attach a drawing that ALREADY has the far leg forward (Luffy's `luffy_WB.png`) as a
  POSE-only reference + the character's head crop as style, and say which leg is behind/forward. Gemini copies the
  pose including the leg layering (Mikoto `mikoto_poseWB.png`). Ask Nhi before using another character as a pose
  reference (her rule); she allowed pose-only.

## Jump / happy row (redraw an old blurry row in the walk's style)

Attach (1) one crisp frame of the walk as the style and (2) a strip of the old poses, and say image 2 only gives the
pose:
> Image 1 is the exact style to keep: crisp single drawing, thick dark outline, clean cel shading, same head size,
> hat, outfit and colours. Image 2 only shows the POSE I want (old, blurry, off-style). Redraw image 2's two poses in
> image 1's crisp style: ONE picture with TWO drawings side by side on flat pure magenta #FF00FF, each in its own cell
> with a wide gap. Drawing 1: the jump take-off, a deep crouch ... Drawing 2: the peak of the jump, both arms raised
> high with fists, knees tucked, feet off the ground. Side/three-quarter view facing RIGHT. FULL BODY, exactly TWO
> legs and TWO feet per drawing, exactly two arms. Same size as image 1. Crisp clean edges: no blur, no halo, no extra
> limbs, no text, no shadows, no divider lines, no sparkles.

Then `build/sprites/_gaitwork/tools/jumprow.py <scale> <lifts>` (Luffy: `0.28 0,-10,-22,-26,-10,0`: crouch, peak
lifted, crouch). Check **every row that copies the old art** (Luffy's `habit` row held a copy of the old jump and played
after begging for food). Old rows can have a pink matte fringe: that is the sign it needs the redraw.

## Checklist before installing

- [ ] 2 feet, 2 arms on every frame (count at full size)
- [ ] arm opposite to the forward leg in every frame; lifted foot same height both sides
- [ ] a one-foot-down frame between switches, a swing frame before each switch (walk)
- [ ] same expression on all frames; no stray marks near fists or neck (purple/pink specks)
- [ ] Nhi saw the static frames; then preview video; then `--install` and `./scripts/install-local.sh`
- [ ] `skills.json` has both `fps.walk` and `fps.run`

## Pose-chart pilot (Mikoto walk, 2026-11-13/14) — Nhi: "not effective"

- A **dressed mannequin** (tools/mannequin.py `DRESS=1`, sock colours + which leg is drawn on top) as the POSE reference
  makes Gemini draw the far leg forward correctly. A plain two-colour mannequin does not (it ignores near/far).
- But **one generation per frame drifts** (body build, socks, loafers, line weight, face angle). Head transplant
  (tools/headhold.py) and body rescale fix one drift at a time; 15 generations still gave no consistent set.
  Do not repeat per-frame generation for a whole cycle. Next ideas are in HANDOFF.md (2026-11-15): cut-out puppet
  from the old sprite, or all 6 poses in ONE generation.

## What finally worked for Mikoto's walk (2026-11-15)

1. **All 6 poses in ONE generation**: attach (1) one crisp drawing of the character as style (crop off the sparkle) and
   (2) a strip of the 6 slim dressed mannequins (`DRESS=1 SLIM=0.6 mannequin.py walk`, cells on magenta, no labels).
   One picture = one consistent build, face and size. Prompt: `build/sprites/_gaitwork/prompt_mikoto_strip6.md`.
   It got 2-3 poses wrong (passing frames drawn as contact) and copied the mannequin's grey-blue tube legs.
2. Fixing a few frames **in the same chat** redraws the whole strip: take the good frames from each version. Both came
   from one chat, so the frames line up (same top, feet within 6 px).
3. **Mannequin legs** (stiff tube, grey-blue or long white sock): crop that ONE drawing on a magenta square, new chat,
   attach it + the style drawing, "keep everything, change ONLY the <which> leg: redraw it as a real leg like picture 2,
   loose sock at the ankle, same pose". Worked first try on 4 frames. Check every frame: Nhi spotted 3 of them.
4. Install: put the 6 cells in a 3x2 grid and run `gait-step.py --grid 3x2 --cycle --pick 1,2,3,4,5,6 --no-sparkle
   --bob 0,-5,-3,0,-5,-3 --fps <x> --install`. Its travel estimate is wrong for a full cycle; measure contact to
   contact yourself (Mikoto 18.5 px/frame). Nhi liked 6 fps -> walkSpeed 56 and a separate `runSpeed` (Characters.swift)
   so the run keeps its speed.
5. After installing, compare against idle and run: **skin tone** (the new frames were pinker: shift skin per frame to
   idle's face median) and **head size** (the old run row was 12% smaller: scale it about the feet anchor (128,244)
   and divide its fps by the same factor).

## Installing a redrawn walk/run (gait.json, runSpeed) and fixing the "stutter"

A redrawn walk or run usually has fewer frames and longer strides than the shared layout (8 frames, 12/16 fps).
Per character, `Sprites/gait.json` overrides a row's `frames` and `fps`; `Character.runSpeed` keeps the run as fast
as before when the walk had to be slowed down.

```json
{ "luffy": { "walk": { "frames": 6, "fps": 6 }, "run": { "frames": 6, "fps": 8.4 } } }
```

Foot-sliding rule: `fps = speed x 2 px/pt / (planted-foot travel per drawing in px)`. Measure the planted foot's x in
every frame; the travel between frames should be even (e.g. ~25 px each). Pick fps from that, then set
`walkSpeed` so `walkSpeed x 2 = fps x travel`, and set `runSpeed` separately.

Stutter checklist (walk looks "khựng"):
1. Planted-foot travel uneven (e.g. 20, 6, 55 px) = the leg poses of some frames are wrong. Redraw those frames, or
   lock the foot in code. A bad speed/fps match only gives uniform sliding, not stutter.
2. A "lift" frame with the foot in the air twice per cycle reads as a limp: order the drawings by leg shape (contact,
   passing, contact) like a 6-pose walk, not by sock/cuff colour.
3. Head must keep the same size and the same skin tone across rows (median skin px vs idle); do not graft old upper
   bodies onto new legs (head size jumps). Swing arms in code (cut forearm + fist, rotate about the elbow, keep a seam
   band) instead of asking Gemini to swap which arm is forward; it reverts.
4. Add a small bob (e.g. 0, 2, -3 px) and keep torso/head pinned otherwise.

Working prompts (attach a dressed mannequin strip as POSE only plus a crisp style drawing, ALL poses in one
generation): `references/walk-strip6-prompt.md` (6-pose walk), `references/run-jog6-prompt.md` (6-pose jog),
`references/dragged-prompt.md` (dangling "being carried" row).
