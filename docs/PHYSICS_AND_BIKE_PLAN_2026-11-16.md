# Two-wheelers and world object physics: audit and plan (16 November 2026)

Two briefs: realistic two-wheeler riding (physics, rider, foot down, mounting, crashes, recovery) and one physics
and interaction framework for every object in the world. Audit first, then one phase at a time, each tested in the
game (sound off) with pictures before the next.

## 1. Audit: two-wheelers today

| Area | Today | Gap |
|---|---|---|
| Architecture | `jeep.gd`: one VehicleBody3D for every vehicle; `two_wheeler` (scooter, motorbike) adds `_balance` (a critically damped spring on the roll rate holding the lean a turn needs, tan = v·yaw/g, upright at a crawl, never past 45°, through torques, not set rotations); speed-sensitive steering capped at ~0.95 g of grip; brakes split front/rear by mass; engine curves, CVT on the scooter; surfaces (`surfaces.gd`), wet grip (`wet_k`). Vehicle lab numbers in `docs/VEHICLE_LAB.md`. | Keep it: the lab shows it holds a line, leans, brakes and corners well. Missing: front/rear brake as two inputs, a stoppie/lock-up limit, weight transfer felt in the pitch. |
| Suspension | VehicleWheel3D springs per wheel (front and rear independent); speed breakers measured (scooter jolt 9.8, pitch 5.6°). | Fine; potholes (`potholes_phys`) exist. |
| Rider | `rider_pose.gd`: one of our people playing a fixed "Sit" clip, placed on the seat; Karthik's own model on his scooter (`_story_rider`). Leans only because the bike leans. | No hands on the grips (IK), no feet on the footboard or pegs by IK, no foot down at a stop, no counter-lean or head into the turn, no handlebar turning with the hands. |
| Mount / dismount | `city_test.toggle_on_foot()` (F): the walker appears beside the vehicle or vanishes into it at once. | No approach, leg over, sit, stand off. |
| Crashes | `_hit(zone, severity, other)`: dents (`dents.gd`), a pull from damage, `last_dv` for the hospital; on a two-wheeler the rider stays on. | No fall off, no bike on its side sliding, no rider on the ground, no getting up and picking the bike up. |
| Damage | zones and severity, a pull; engine and lights hurt on cars. | No separate wheel / brake / engine condition on two-wheelers. |

## 2. Audit: world objects today

| Kind | Today |
|---|---|
| City (roads, buildings, footpaths, terrain) | `city_streamer.gd`: static collision per tile, each shape tagged with its surface; parked vehicles have boxes (`_life`). |
| Story rooms (`tools/story_rooms.py` → `room_*.glb`) | the whole room is one mesh with exact-shape static collision; since 15 Nov, chairs are separate `Move_chair_N` RigidBody3Ds (`story.gd _movables`: mass, convex shape, friction 0.3, damping); only the office and the godown are rebuilt with them so far. |
| City rooms (`city_doors.gd` landmark interiors) | their own builder; static collision; crowds; no movables. |
| Things to use | `interactable.gd` + `story/interactables.json`: look, drawer (slides, sound, blocked check), switch, locked, inspect (lift, turn, put back); office only. |
| Characters | Karthik a CharacterBody3D (`player.gd`), pushes rigid bodies (~70 N); NPCs kinematic; fighters CharacterBody3D. |

## 3. Plan

### A. World objects (one framework)
1. **Profiles** `scripts/world/physics_profiles.gd`: kinds of object with mass, friction, damping, what you can do
   with them (static, heavy, medium, light, small to inspect), used by every builder: `Move_<kind>_N` names a
   profile (`chair`, `stool`, `bin`, `crate`, `table_small`...). One place, no per-scene physics code.
2. **Every room**: rebuild all story rooms so their chairs, stools and bins are `Move_`; the city's room builder
   tags the same kinds; heavy things (almirahs, counters, desks) stay static.
3. **Things to use everywhere**: `interactables.json` entries for Karthik's house, the godown, the police station,
   a restaurant; doors (hinged, limits, sound) as a kind.
4. **Persistence**: a moved chair keeps its place in the save (by room and name), dirty only when it moved.
5. **Validator** `--physicsaudit`: every room loaded in turn; reports objects with no collision, movables with no
   profile, rigid bodies that fall through or jitter, oversize shapes. Report only; nothing changed by it.

### B. Two-wheelers (on the existing VehicleBody3D, not a rewrite)
1. **The rider on the bike** (`rider_ik.gd`, a SkeletonModifier3D like `foot_ik.gd`): hands on the grips (the grips
   are points on the handlebar, which turns with the steering), feet on the footboard (scooter) or pegs (motorbike),
   knees in, the body leaning a little into the turn and the head level, looking where the bike goes.
2. **Foot down**: under ~1.5 m/s, the left foot goes to the ground (a ray finds it), the bike tilts onto it at rest;
   moving off, the foot comes back up to the footboard over ~0.4 s.
3. **Mount and dismount**: F walks him to the left side, a hand to the bar, the right leg over the seat, sits, feet
   up (and the reverse); the controls are his only once seated. Clips made in `story_cast.py` like SitDown.
4. **Crashes**: from `_hit`: by speed and direction, a low-speed tip-over (the bike falls to its side, he steps
   off), a side fall, a front hit at speed (he comes off forward, lands, slides a little); the bike on its side as
   a body sliding to rest. The fight's floor clips (KnockDown, FallSide, FallF, GetUp) are reused for him on the
   ground.
5. **Getting up and the bike**: he gets up, walks to the bike, lifts it (a clip), and can ride on if it's fit.
6. **Condition**: wheel, brakes, engine on two-wheelers from the crash zones: a bent wheel wobbles, worn brakes
   stop longer, a hurt engine pulls less; small knocks do nothing.
7. **Camera and sound**: lean with the bike a little; brake and tyre sounds; engine pitch from rpm (already).

### Order
B1 → B2 → B3 (what you see every ride first), then A1 → A2 → A4 (the framework and every room), then B4 → B5 → B6
(crashes), then A3, A5 and B7. Each step: the change, a test in the game, pictures, a commit.
