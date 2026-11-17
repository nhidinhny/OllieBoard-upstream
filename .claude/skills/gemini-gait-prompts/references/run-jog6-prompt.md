# Run (light jog): all 6 poses in ONE generation (Luffy, 2026-11-16)

Attach in this order, fresh Gemini Pro chat:
1. one crisp drawing of the character from the game = STYLE
2. a strip of six dressed mannequins in the jog rhythm (kick back -> legs together -> legs wide, then the same with
   the other leg): near leg light with a white cuff, far leg darker with a grey cuff, the forward leg drawn on top
   = POSE ONLY (see SKILL.md section 4)

Prompt (one paragraph; replace Luffy's parts):

Image 1 is the exact character and style to keep: this chibi boy, same face, same straw hat with red band, same messy black hair, same head size and head angle (three-quarter view facing RIGHT), same open red jacket, yellow sash, blue shorts with white fur cuffs, bare legs and straw sandals, same thick dark outline and clean cel shading, same body proportions. Give him a big happy open-mouth grin, the SAME grin in every drawing. Image 2 only shows SIX POSES of one gentle jogging cycle, left to right. It is a simple mannequin, not the style. In image 2 the LIGHTER leg with the WHITE cuff is his NEAR leg (closer to us) and the DARKER leg with the GREY cuff is his FAR leg (behind). Copy for each pose exactly which leg is forward, which leg is lifted, how high each foot is, and which leg is drawn on top. In poses 4, 5 and 6 the FAR leg is the forward leg: keep it forward. Copy the arm swing too: elbows bent, the arm on one side always swings opposite to the leg on that side. It is a light jog, not a sprint: low heel kick, small knee lift, body only slightly leaning forward. Draw ONE picture with EXACTLY SIX drawings of the boy from image 1 in one row, in the same order and poses as image 2, each in its own cell with a wide gap, all the same size and the same head size, all on the same ground line. In your drawing both legs are normal skin with the same white fur cuffs like image 1; the far leg may be a little darker because it is behind. Only the arms and legs change between drawings. FULL BODY, exactly two legs, two feet and two arms in each drawing. Crisp, no motion blur. One single picture, flat magenta (#FF00FF) background, no sparkles, no text, no numbers, no divider lines, no shadows.

After it: check every drawing (2 feet, 2 arms, same head size, far leg forward in 4-6), pick and order by leg shape
(Luffy: drawings 2,3,1,2,3,5), swing the arms in code if they are wrong, match the skin to idle, then
`gait_step.py ... --cycle --pick ... --fps 8.4 --install` and set `runSpeed`. A first version with a flight
(both feet off) frame and a high knee was rejected as an extra step.
