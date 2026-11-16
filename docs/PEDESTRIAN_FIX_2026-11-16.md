# People on foot: on cars, in cars, in the ground (2026-11-16)

## The cause

Everyone on foot in the city finds the ground with `city_streamer.gd height_at(x, z)`: a ray from 3 km up, the
first thing it hits. Over a parked car (or scooter) that's its collision box; over a car going by, its body. And:

- `citizens.gd _ground()` stood a citizen at the *higher* of the footpath's line and `height_at`: next to a parked
  vehicle that was its roof (Rafiq, at his shop, stood on the scooters parked on the footpath), under a shop's
  awning the awning;
- `city_walkers.gd` walked people at the map's footpath line, which in places lies a metre or more under the
  street the game built (a man sunk into a ramp to his neck), and crossing the road took `height_at` (a car's
  bonnet);
- nobody on foot looked where they were going: the footpath line and the citizens' routes run straight through
  vehicles parked on them, and walkers were even set down inside them.

## The fix (no one moved by hand: they find the ground, and their way)

| File | What changed |
|---|---|
| `scripts/city/city_streamer.gd` | `height_at` looks through vehicles (the parked ones, the traffic's AnimatableBody3D, any body that moves) to the street under them. New `ground_near(x, y, z)`: the surface from 1 m over a person's feet down, vehicles not counted (an awning overhead isn't ground). New `vehicle_at(p)`: is a person's body (a 0.35 m ball, knees and chest) inside a vehicle. |
| `scripts/city/ped_steer.gd` (new) | Seeing the way: rays at the knee and the chest ahead; the nearest clear way round a vehicle (left first: people here keep left), or stop; people kept apart, one coming the other way passed on the left. |
| `scripts/city/city_walkers.gd` | Feet on the street as built (`ground_near`, within a step of the footpath line). `_make_way`: a vehicle ahead, round it on its clear side and back after, or turn back; inside one, out to the clear side; someone coming, keep left; someone stood in the way, a moment's wait; traffic close by the kerb, a step back. Crossing the road: round a vehicle parked at the kerb, or wait. Never set down inside a vehicle. Far ones (50–85 m) look too, each time they're moved. |
| `scripts/city/citizens.gd` | `_ground`: the street as built, never an awning or a car. On their routes, steered round vehicles and people (`ped_steer.gd`), waiting a moment when nothing's clear. Their spot at a place (`_spot_for`, `_clear_spot`): the nearest along the footpath no vehicle covers; standing there, a car parked onto them later, they walk to a clear spot. |
| `scripts/city/city_test.gd` | `--pedcheck` (with `--citizentest=HH:MM`): every second for 100 s, everyone on foot in view checked (on a vehicle, in one, over or under the ground under their feet), counted, pictures. |

## Tested (the game itself: on foot at Gandhipuram, 100 s, every person in view each second)

| | on a vehicle | in a vehicle | floating | sunk |
|---|---|---|---|---|
| before, 09:00 | 100 | 39 | 9 | 122 |
| after, 09:00 | 0 | 0–2 | 0 | 0–4 |
| after, 18:00 | 0 | 0 | 0 | 0 |

(2 000 checks a run; the counts vary a little from run to run with where people are set down. What's left:
a citizen for a second or two as his route takes him past a parked car's corner, and someone paused beside a
raised kerb.) Pictures: `docs/shots/peds/before_sheet.jpg`, `after_sheet.jpg` (the same places).

No regression: the walkers still cross the road (`--walkertest --crosstest`: 9 crossings in 55 s, 8 before,
none stuck); driving and taking a parked car (`--taketest`) as before. Cost: the walkers' update 0.4–0.7 ms a
frame before, 0.6–1.0 ms after (`--noavoid` gives the old behaviour, for comparing).

## Not done yet (the rest of the brief)

- Walking itself: start/stop easing, foot locking against skating, arm swing and weight shift per person,
  male/female walking styles, idle → walk → jog → run transitions.
- Crossing at zebra crossings and signals where there are any (now: where footpaths face each other across
  the road, after looking both ways and waiting for the traffic).
- More of a day for the footpath walkers (now: walk, pause, talk, cross; the citizens have destinations and
  schedules): shopping bags already, benches, buses, entering buildings, walking with friends.
- `--walkertest`'s "off the path's height" counts people on the street as built rather than the map's line:
  it should measure against the ground now.
