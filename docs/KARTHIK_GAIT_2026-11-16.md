# Karthik's walk and run (2026-11-16)

Looked at first: the model (MPFB2's 53-bone game rig), the clips (`tools/humans/story_cast.py`: hand-keyed on
clinical gait curves; five paces, 1 s cycles with the heels down at the same moments), the AnimationTree
(`scripts/gait.gd`: a BlendSpace1D of the five on his speed, synced, under a TimeScale so a cycle covers the ground
it's played over), the foot IK (`scripts/foot_ik.gd`) and the controller (`scripts/player.gd`). The system was
sound: running isn't a sped-up walk (its own clips, its own curves), the knees never bent backward, the weights
are MPFB's own. What was wrong was in the clips and in three numbers.

## What was wrong, and the fix

| Fault | Cause | Fix (where) |
|---|---|---|
| **Wide legs** (walk and run): ankles 41–52 cm apart | The rig's rest pose stands splayed (hips 23 cm apart, ankles 42 cm). The Idle brings the feet in; the walk and the run never did. | Each thigh brought in under the hip (8°, about the axis he faces along) and the foot turned back flat, before the swing (`legs_under`). The hips' dip to the swinging side, and most of their turn, no longer carried the legs out with them (each hip takes it up). Ankles now **16–18 cm apart**, two nearly parallel tracks, the swing along his way. |
| **Feet floating and sinking** | The planted foot wasn't kept on the ground: the leg swings round the hip, so the heel was ~15 cm up at heel strike, 6 cm at mid-stance, the toes 4 cm into the ground at push-off (the hips rose and fell only 2 cm). | `_plant`: each pose, the hips raised or lowered so the lowest of his heels, balls and toe tips is where it is when he stands. The hips' rise and fall comes out of the leg geometry, as in a real walk (the body vaulting over the standing leg); in a run only while a foot is down, never into the ground in the flight. |
| **Planted foot sliding** | gait.gd's numbers for the ground a cycle covers weren't the clips' (walk 1.41 m against the clip's 1.27, jog 2.2 against 2.86): the clip played too slow walking (the foot slid forward), too fast jogging (it slid back, −1.1 m/s). | POINTS set to the clips' own (story_cast.py walk_strip's measure): slow 0.86, walk 1.27, fast 1.61, jog 2.86, sprint 3.58. And foot locking (`foot_ik.gd`): a foot that comes down is held where it landed while it bears him, let go as its heel lifts (or if holding it would stretch the leg). |
| **Stiff walk** | The swinging knee barely bent (the foot skimmed the ground), the toes never bent, the forearms hardly moved. | A longer stride, the knee folding to ~64° through the swing, the toes bending up ~28° as he rolls off them, a little more arm swing with the forearm following. |

The run keeps its own curves (stronger knee lift ~100°, the lean, the arms pumping, both feet off the ground
between steps): only the legs under him and its stance on the ground changed.

## Tested (the game: `--gaittest`, on the Coimbatore street)

The planted foot's slide along his way (m/s):

| pace | before | after |
|---|---|---|
| walk 1.4 m/s | +0.14 | −0.04 |
| fast walk 1.9 | +0.17 | −0.02 |
| slow 0.9 | | +0.01 |
| jog 3.6 | −1.14 | (too few samples with a foot down to measure at this machine's frame rate) |
| turn 90°, 180°, circle | | +0.13, −0.12, −0.07 |

Feet apart (the clips, measured in the exported model): walk 41–52 cm → 16–18 cm; jog 42–51 cm → 16–18 cm.
Knees: never backward (as before).

Pictures (`docs/shots/gait/`): `before_walk_front`, `after_walk_front` (the A-shape gone, the legs under him),
`*_side` (the knee folding through the swing, the roll off the toes), `after_*_rear`, the jog the same.

## Not done

- Slopes and uneven pavements were covered by foot_ik.gd already (each foot finds its step, the hips come down);
  not filmed again this time.
- The walk's cadence is a little quick for his speed (1.1 cycles a second at 1.4 m/s; a man walks ~0.95): a
  still longer stride would want the hip's swing beyond what looks natural on this rig. Left as it is.
- The crowd's walk is the same code (`walk_phase`); their models aren't rebuilt (another session has uncommitted
  changes to some of them).
