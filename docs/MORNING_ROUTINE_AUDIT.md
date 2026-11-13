# Morning routine: audit and plan (13 November 2026)

## How it works now

- **Story:** `story/slice.json` step 0 is a `home` step. You walk Karthik round the house (`story.gd`, `home`), and a
  ring marks the next place. At each place, E opens a `ready` task (`tasks.gd`) with its chores: the alarm in his room,
  then `brush` and `bath` at the bathroom door, then `dress`, then breakfast and pockets (step 2, late after 7:15).
  Each chore costs game minutes (`CHORE_MIN`: brush 5, bath 12, dress 6). The shirt you pick is remembered
  (`res["shirt"]`), and the day is saved at the next morning (`story_save.json`).
- **Brushing and bathing** (`groom.gd`, 917 lines): a 2D close-up in the cream task panel, played with the mouse.
  For brushing you drag the paste onto the brush, scrub the stains off (foam, progress), then hand him the tumbler
  to gargle. For bathing you pour mug after mug, soap him, rinse and towel him dry, with a zoom. Drag and drop,
  masks for "on his body", progress and reactions are all **already real**.
- **Karthik in those pictures:** still frames rendered in Blender (`tools/story_groom.py`), one per expression
  (idle, blink, giggle, grin, squeeze, wet or dry). He changes expression, but **he doesn't move**: no arm, no head
  turn, no motion between frames. This is the "statue" problem.
- **Dressing** (`tasks.gd` `_draw` "dress"): three flat coloured rectangles on hangers and a cap. Clicking one sets
  the shirt. It doesn't change what he's wearing in the world, and there are no trousers.
- **The house** (`tools/building_interiors.py` `home`): a front room, a kitchen corner, and Karthik's room with a
  cot, a table, shirts on hooks and a window. **There is no bathroom room** (the bathroom is a mark at a door) and
  **no wardrobe** (only hooks).
- **Karthik's rig** (`assets/people/story_karthik.glb`): 53 bones, including the fingers. The clips are Idle, Walk,
  Run, Sit, SitEat, SitTalk, Talk and Ride, all made by code in Blender (`tools/humans/story_cast.py`, which already
  has two-bone IK and aim helpers). **There are no face shapes in the game model**, so in 3D he can't blink or smile;
  only the Blender stills have expressions. His clothes are one mesh (`male_casualsuit03`), tinted by colour (the
  story already tints his "top").
- **Sound:** everything is synthesised in code. There are no sound files for brushing, water, a wardrobe or birds.

## What's real and what's missing, against your brief

| Brief item | Now | Missing |
|---|---|---|
| 2. Animations | Brushing and bathing are stills with expressions | All of the body motion: raising the brush, scrubbing, the mug, dressing |
| 4. Brushing | Real drag and drop, paste onto the brush, progress, feedback | Karthik's hand and head moving with it |
| 5. Bathing | Real pouring, soap, rinse, towel, zoom | Arm and mug motion; water sound; better water particles |
| 6. Dressing | A flat picker | Thumbnails, trousers, a preview, the change on the 3D model, saving the outfit |
| 7. Rooms | A bedroom with no wardrobe; no bathroom | The bathroom room, a wardrobe, morning sun |
| 9. Sound | Synthesised clicks | Every listed sound |
| 10. People | Idle clips breathe and shift weight; walk, sit and talk | Blinking needs face shapes on the game models (shared with the faces work) |

## The choice that decides the rest

**A. Keep the close-up panels and make Karthik move in them.** Render short animated loops in Blender (raising the
brush, scrubbing, lifting and pouring the mug), with your mouse driving which frame shows. This looks the most
realistic (Cycles, his real face with expressions), costs the M1 almost nothing, and reuses the working games. But
it stays a screen over the house, not him in the house.

**B. Do it in the house, in 3D (my recommendation).** Build a bathroom and a wardrobe into the house. Write new
skeletal clips on his own rig (`BrushTeeth`, `PickMug`, `PourMug`, `OpenWardrobe`, `PullOnShirt`), with IK putting
his hand on the brush and the mug. Play the mini-games on the real 3D objects, with the camera moving in close.
You see him walk in, sit on the stool and pour. This is closer to "living inside his house". It's more work, and his
face won't change expression in 3D unless face shapes are added to the game model (about 1–3 ms a frame on the M1
for him alone; measured before I commit to it).

## Plan for B, one activity at a time, each tested and shown to you before it replaces the old one

1. **Brushing:** the bathroom (tiles, a sink and tap, a mirror (a reflection probe, not real-time, on Low)); a
   `BrushTeeth` clip in three parts (raise, a scrub loop, put back), the brush held with IK; dragging the paste onto
   the brush and scrubbing on the real objects, the progress as it is now; a camera close-up. Pictures for your OK.
2. **Bathing:** a stool and a bucket; `SitDown`, `PickMug`, `PourMug` and `PutMugBack`, with the mug in his hand
   by IK; your mouse aims the pour; a water stream and splash (GPU particles, a few hundred); the soap and towel
   steps kept. Pictures for your OK.
3. **Dressing:** a steel almirah in his room (doors on hinges); shirts and trousers as thumbnails rendered from the
   real model; picking one previews it on him, `PullOnShirt` plays, and the outfit goes into `story_save.json`.
4. **UI:** cream, charcoal, forest green and wood across all three, from the existing `ui_kit.gd`.
5. **Sound:** your call: original, synthesised in code as now (no downloads), or CC0 recordings (each download
   listed for your OK first).
6. **QA:** the whole morning from the alarm to the scooter, the clock minutes, the saved outfit, and story step 3
   continuing; frame rate on Low measured before and after.

Kept as they are: the story steps, the clock, the chore minutes, the saves, and the existing games' rules. The old
pictures are kept until you approve the new ones.
