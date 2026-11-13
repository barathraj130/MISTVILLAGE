# World life audit (13 November 2026)

This covers the brief "Complete game quality and world-life upgrade", stages 1 and 2. It builds on
`docs/AUDIT_2026-11-10.md`, the whole-project audit, which still stands for release, story QA and performance.
Here the focus is the people in the city: who moves, who stands like a statue, and what's missing.

## What already works (kept)

| System | File | What it does |
|---|---|---|
| Footpath walkers | `scripts/city/city_walkers.gd` | A pool of 12 crowd models (6 men, 6 women) walks the footpaths round Karthik: walk, pause and look about, two who meet stop and talk, step aside for him, run off the path from a vehicle. Numbers follow the clock (busiest morning and evening). Those over 50 m update four times less often, and those past 85 m are recycled. 16 on Low. |
| People at places | `scripts/city/city_activity.gd` | Bus shelters (waiting, looking up the road), stalls and carts (seller and buyers talking by turns), tea stalls with benches (sitting, drinking, getting up and going), shop doors (8 AM–9 PM), security guards walking a beat. Driven by the clock. 14 on Low. |
| Rooms | `scripts/city/room_walkers.gd` | People walking a public room's routes, keeping left, giving way, pausing at shops and boards. |
| Traffic | `scripts/city/city_traffic.gd` | Hatchbacks, sedans, taxis, autos, buses and lorries on the real roads: keeping left in lane, one-ways, a choice at each junction, slowing for turns, stopping at red signals, keeping distance. |
| Bystanders | `scripts/city/city_bystanders.gd` | The street's still figures jump clear of a vehicle coming at them, or are knocked down and get up; the consequences follow (hospital money, an e-challan, bail suspicion). |
| Karthik's needs | `scripts/city/life.gd` | Energy, tiredness and stress. Meals now feed energy (this session). |
| Story people | `scripts/story/actor.gd` | The story cast with Idle (breathing, weight shift, a look about), Walk, Run, Sit, Talk, SitTalk, SitEat and Ride. Listeners turn to the speaker. |
| Karthik's face | `tools/humans/story_cast.py` `face_rig`, `scripts/story/face.gd` | Blinking, jaw, lips and brows as blend shapes (this session). |

## The statues

| Where | How many | State |
|---|---|---|
| **Street life's people** (`city_streamer.gd` street life: `street_*` and `sf_*` figures as MultiMesh instances) | 816 groups in the 26 tiles round the test spot, 1–3 figures each, up to 6 a stretch in bazaars | **Fixed now, near him on foot** (see below). Still figures far off: fine at that distance. |
| The same figures, mid-stride (`street_man_shirt_walk`, `street_schoolboy`) | part of the above | **Hidden near him now.** The walkers pool covers the footpaths there. |
| Traffic police (`street_police_stand`, `street_police_stop`) | at junctions | Still. They need a signalling clip (arm, whistle) on a rigged model. Not done. |
| Riders on parked bikes (`street_rider_*`) | parked two-wheelers | Still. They should either ride away or not sit on parked bikes. Not done. |
| Crowd faces | all 12 crowd models | No blinking or mouth movement. `face_rig` could be added to `tools/humans/crowd_cast.py` the same way; its cost needs measuring first, since there are up to 40 of them. |

## Missing

1. **Daily schedules per person.** People come from pools driven by the clock, not individuals who wake, commute,
   work and go home. A shopkeeper is "at the door 8 AM–9 PM", not someone who opens up.
2. **Navigation.** There's no `NavigationAgent3D` or navmesh anywhere. People follow footpath strips and room
   routes. Nobody crosses a road: pedestrians never step off the footpath.
3. **Two-wheelers in city traffic.** Scooters and motorcycles, the commonest vehicles in Coimbatore, aren't in
   `city_traffic.gd`'s fleet (only parked ones in street life). `tools/riders.py` exists in the working tree but
   isn't committed, probably another session's work in progress.
4. **Clips.** Phone, carrying a bag, opening a door, getting on and off a scooter, surprise, drinking (sitting).
   The crowd has Idle, Talk, Walk, Run, Sit, SitEat, SitTalk and Ride.
5. **Lip-sync** in dialogue (Karthik's mouth units exist now; the others have none).
6. Personalities in body language: everyone in the crowd shares one Idle and one Talk.

## Performance (Apple M1, Low)

- City on foot: 24–51 fps in this session's tests. The swings follow tile loading, so it isn't a steady figure.
  The earlier audit: Low 22–32 fps in the city centre.
- CPU (the 2026-11-10 profile): traffic 22–27 ms and bystanders 13–17 ms a frame at 7–10 fps (physics stepping
  several times a frame), everything else about 7 ms. GPU: about 3,000 draws and 2.5 million triangles.
- **The city is still drawn while he's indoors** (about 3,400 draws in the house). That's the biggest saving
  available for every interior.
- Animated people cost skinning per person (crowd models are 20–36k vertices). The new swap is capped by preset:
  Low 12, Medium 20, High 28. Its effect on the frame rate isn't measured yet, because these numbers swing too much
  with tile loading. A fixed-view benchmark with and without it (`--noliving`) is next.

## Done in this pass (Stage 1 and the start of Stage 2)

- `scripts/city/city_living.gd`: within about 40 m of Karthik on foot, each standing figure is swapped for an
  animated crowd person of the same sex, on the same spot and facing the same way. They idle at their own pace
  and look about. Two standing within 2.4 m turn to each other and talk by turns. Mid-stride figures are hidden near
  him. Past 55 m the figure is put back. Swaps happen out of his view when possible (or beyond 30 m). It's off in
  the car (bystanders own the figures then) and indoors. `--noliving` turns it off; `--livingtest` (with
  `--livingat=x,z`) reports and takes a picture.
- Tested on foot: figures swapped and hidden near him, put back on leaving, no script errors. **Not yet tested:**
  a long walk through a bazaar, and frame-rate cost on a fixed view.

## Order from here

1. Stage 2 continued: a fixed-view benchmark for `city_living` and a bazaar walk; then road crossings at junctions
   for the walkers (wait for a gap, cross, go on), and two-wheelers in traffic (with the riders work, if that's
   another session's).
2. Schedules for kinds of people (shopkeepers who open and shut, office workers' commute in the walkers' numbers,
   tea-stall regulars), on the pools that exist, not a new system.
3. Clips: phone, carrying, the police signal; blinking for the crowd, if the measured cost allows.
4. Indoors: stop drawing the city (every interior gains).
5. Then stages 3–9 as the brief orders them.
