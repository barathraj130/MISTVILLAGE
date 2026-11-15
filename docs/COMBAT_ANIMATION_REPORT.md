# Combat animation: audit and corrections (2026-11-15)

The hand-to-hand clips are made in code (`tools/humans/crowd_clips.py`, the combat section), on the game rig that
Karthik and the crowd men share (the MPFB game skeleton: `pelvis`, `spine_01..03`, `neck_01`, `head`,
`upperarm_/lowerarm_/hand_` l/r, `thigh_/calf_/foot_/ball_` l/r), exported to `godot/assets/people/crowd_clips_m.glb`
and copied onto each person at runtime as the `crowd/` library (`scripts/city/crowd_clips.gd`). Karthik keeps his
own model, face, shirt, trousers and shoes: only his bones move. Checked on contact sheets from the front quarter
and the side (`crowd_clips.py --strip DIR --only combat [--cam x,y,z]`), then in the running game.

## Rig facts used
- He faces -Y in Blender (+Z in Godot), his left is +X, 24 frames a second.
- Arm length (shoulder to wrist): about 0.54 m. Any wrist target beyond it makes the two-bone solve fold the arm
  back across the face: the first cross and heavy did exactly that. Targets are now clamped to 97% of the arm
  (`_reach`), and the extra reach comes from the hips, shoulders and weight, as a real punch does.
- `SC.turn` (story_cast's world-axis bone turn) and a plain world `Matrix.Rotation` about Z turn opposite ways.
  The first stance put the right shoulder forward, and every punch turned the wrong way. The hips' yaw now uses
  `SC.turn`'s sense.

## Audit of the first set (the sheet before this one) against the reference sheet
| Clip | What was wrong | Correction |
|---|---|---|
| Guard (stance) | knees bowed outward (back toes 28° out, knees aimed past them); a little deep and wide | back toes 20°, knees over the toes, hips 4.5 cm down, feet a shoulder's width with the left ~17 cm ahead |
| Cross | arm folded across the face (unreachable target); no heel | target clamped to the arm; the back heel lifts and turns (the ball stays down) as the hips drive |
| Heavy | the same fold; wind-up fine | clamped; the heel lifts; more weight through the front knee |
| Haymaker (the men's) | wind-up held the arm straight out to the side (a T-pose arm) | drawn back: the elbow back and up, the fist by the ear, the shoulder turned away; then round |
| Knockdown, sitting | sat down with the hands out to the sides, nothing taking the weight | one hand reaches back to the floor as he sits (as in the reference), then he goes onto his back |
| Get-up | sat up, then a squat (no knee on the floor), then up: not how a man gets up | the reference sequence: from the back over onto his front, hands and knees, the right knee down and the left foot planted (half kneel), hands on the knees, up, the guard |
| Missing | forward fall, side fall, ground idle, kneel recovery, uppercut, right hook, a quick right, low guard, stagger from behind, relief | made (below) |

Checked on every clip: elbows bend only forward (the IK pole is always behind and out from the elbow); hands
never go inside the head (guard wrists 12 cm in front of the chin); the legs never cross (the feet keep their sides
in every step and dodge); knees point over the toes; on the floor no bone goes under it (floor test below); no foot
moves while it's carrying weight (the travelling moves carry the travel in the feet, `_travel_feet`).

## The library (crowd_clips.py → `crowd/<name>`)
| Brief name | Clip | Notes |
|---|---|---|
| combat_idle, combat_guard_high | Guard | loop, breathing |
| combat_guard_low | GuardLow | loop; hands at the chest (tired: the game uses it at low wind) |
| combat_jab_left | Jab | 0.375 s, contact 0.15 s |
| combat_jab_right | JabR | a quick right, no pivot: 0.42 s |
| combat_cross | Cross (Punch) | 0.5 s, contact 0.225 s, back heel up |
| combat_hook_left / right | Hook, HookR | 0.54 s, contact 0.27 s |
| combat_uppercut | Uppercut | 0.58 s: dip, drive up from the legs |
| combat_attack_recovery | built into each strike (contact, held a moment, back to the guard) | |
| combat_block | Block | loop |
| combat_block_impact | BlockHit | 0.375 s |
| (guard knocked open) | GuardBreak | 0.79 s |
| combat_dodge_left / right / backward | DodgeL, DodgeR, DodgeB | travel 0.55 / 0.55 / 0.5 m in the feet |
| combat_counter | Cross played through the opening (the game's COUNTERING state, 1.5× damage) | |
| combat_stagger_front / back / left / right | StaggerF, StaggerB, StaggerL, StaggerR | each carries its step in the feet |
| combat_fall_backward | KnockDown | stumbles back, sits with a hand behind, onto his back |
| combat_fall_forward | FallF | knees go, hands out, onto his forearms, face down |
| combat_fall_side | FallSide | onto his right hip and shoulder |
| combat_ground_idle | DownIdle, DownIdleF | lying, breathing (back / front) |
| combat_ground_recovery, combat_kneel_recovery | KneelIdle | on one knee, a hand on it, getting his breath |
| combat_get_up | GetUp (from the back), GetUpF (from the front) | continuous, as in the reference |
| combat_victory_or_relief | Relief | bent over, hands on the knees, breathing |
| footwork | GuardStepF/B/L/R | step and drag, 0.36 m a cycle |

## In the game (scripts/combat/)
- `moves.gd`: every move's length, contact, hand, damage, cost and travel, taken from how the clip was made (frames
  and the authored contact u), not read off by eye.
- `fighter.gd`: the states (IDLE, COMBAT_STANCE, MOVING, LIGHT, HEAVY, BLOCKING, DODGING, COUNTERING, STAGGERED,
  KNOCKED_DOWN, GETTING_UP, RECOVERING, DEFEATED), the transitions (only from the guard; a combination only after a
  blow's contact), the hit window (a sphere at the actual fist bone, the clip's contact −0.04/+0.06 s, once per blow,
  never through a wall: a ray from the chest), reactions by where the blow came from and how hard.
- Blending: crossfades on the AnimationPlayer (0.05–0.15 s by move), with the walking AnimationTree held off for the
  fight (`gait.held`). One thing drives the bones at a time, so two systems never fight over a bone.
- Physics: every man is a CharacterBody3D; dodges and staggers move the body along the clip's own curve through
  `move_and_slide`, so walls, sacks, cars and people stop them. No impulses on a CharacterBody3D, no ragdoll.
