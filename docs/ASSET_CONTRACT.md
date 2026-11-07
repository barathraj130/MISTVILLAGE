# Asset contract: what the game's code expects of people and vehicle models

New or redesigned models can look however they like. If they keep what is listed here, the code keeps working
with them unchanged. If something here has to change, say so first: the code that reads it is named, and it
can be changed with it.

After a new model arrives:
- **Vehicles:** run the vehicle lab, `Godot --headless --fixed-fps 60 --path godot scenes/vehicle_lab.tscn -- --vehicles=<name>`, and compare with docs/VEHICLE_LAB.md.
- **People:** play a story scene with them, for example `--story --storyskip --storyfrom=N --storyshots=DIR`.

## Everything

- **Format:** glTF binary (`.glb`). **Units:** metres (1 unit = 1 m).
- **Up:** +Y in Godot (+Z in Blender). **Front:** the model faces **+Z in Godot** (−Y in Blender).
- **Origin:** on the ground, under the middle of the model (a person: between the feet).
- **Paths and file names** stay as they are (`godot/assets/people/<name>.glb`, `godot/assets/vehicles/<name>.glb`).
  A new model under a new name is fine; then it is added where it is used.
- **Licences:** our own work, or a source approved for the project (see docs/DATA_SOURCES.md). Note the source
  and licence of anything not made here.

## People (`godot/assets/people/`)

Used by: `scripts/player.gd` (Karthik on foot), `scripts/story/actor.gd` (the story cast),
`scripts/city/crowd.gd`, `room_walkers.gd`, `scripts/drive/pedestrians.gd`, `scripts/drive/jeep.gd` (riders),
`scripts/story/dvr.gd` (the cap), `scripts/story/story.gd` (clothes and conversations).

- **One Skeleton3D, with an AnimationPlayer next to it.**
- **Bone names the code finds by name:**
  - `head`: the helmet on a rider (jeep.gd) and Pandi's cap (dvr.gd matches any bone containing "head").
  - `thigh_l`, `thigh_r`: a rider's hips set on the seat (jeep.gd `_settle_rider`).
  - Foot IK and animation blending (planned) will use the leg bones. Keep the current rig's names, or tell us the new ones.
- **Animation clip names** (played by name; the same for everyone):

  | Clip | What it is |
  |---|---|
  | `Idle` | standing |
  | `Walk` | a loop; one cycle covers about 1.18 m at speed 1 (actor.gd, player.gd) |
  | `Run` | a loop; one cycle covers about 3.9 m |
  | `Talk` | standing and talking |
  | `Sit` | seated |
  | `SitTalk` | seated, talking |
  | `SitEat` | seated, eating |
  | `Ride` | astride a scooter or bike |

  - **New clips are welcome** (planned: walk speeds, turns, crouch, stairs, sitting down and standing up, interactions).
  - **If a cycle's stride changes,** tell us the new metres per cycle (`WALK_STRIDE` in actor.gd, `stride` in player.gd), or feet will slide.
- **Material names the code looks for:**
  - `Top …` and `Pants …` (for example `Top trousers`): clothes recoloured by the game (uniforms; the shirt Karthik buys on Day 12).
  - `Hair`: tinted per person.
  - Anything with `short` in its name on a rider (jeep.gd).
- **Size:** adult height about 1.6–1.8 m. Conversations frame the face at about 1.5 m. The walking capsule is 1.75 m tall, 0.3 m radius.
- **Shared with:** the faces session works on these same models (tools/humans/). Changes to people go through
  one place at a time, so they don't overwrite each other.

## Vehicles (`godot/assets/vehicles/`)

Used by: `scripts/drive/jeep.gd` (anything driven), its `SPECS` table (one entry per vehicle), `DRIVE`/`DRIVE_OF`
(the engine, gearbox, brakes and tyres: independent of the look), the traffic (`scripts/city/city_traffic.gd`)
and the story's props (`story.gd`: a vehicle as scenery, painted).

- **Wheels:** separate nodes named `Wheel_F…` (front: steers) and `Wheel_R…` (rear), each centred on its axle.
  The physics wheels are placed from them.
  - **If the wheels' size or place changes,** update that vehicle's `radius`, `rest` and `travel` in SPECS, then run the lab.
- **Body paint:** the paintable body's material named exactly `Paint`. The story paints a car with it (Suresh's black sedan).
- **Lights and glass:** top-level objects whose names start with the prefixes in SPECS: headlights (`Headlight…`),
  tail lamps (`TailBar…`, `TailCorner…`, `TailLamp…`), glass (`Glass`, `Greenhouse`, `Canopy`). The code lights
  the lamps and tints the glass by these names.
- **Interiors (cars you sit in):** `interior_<name>.glb` with `Eye`, `SteeringPivot`, `INT_Cluster`, `INT_SteeringRim`,
  `INT_CenterScreen`, `Mirror…` and the `INT_Ambient` material, where they exist today.
- **Size:** real-world size in metres, facing +Z.
  - **If the length, width or height changes,** update that vehicle's collision `boxes`, `seat`, `lamp` and indicator
    (`ind`) positions in SPECS.
- **Mass and handling** are not part of the model: they're in SPECS (`mass`, `com`) and DRIVE (engine, gears, brakes,
  grip). A redesign doesn't change how a vehicle drives unless those are changed too.

## Working together

- **Model work happens on its own git branch** (`git switch -c models/<what>`).
- **Before merging,** the vehicle lab and a story run are re-run and compared.
- **Renders of any new or replaced model are shown before it goes into the game** (as for every asset in this project).
