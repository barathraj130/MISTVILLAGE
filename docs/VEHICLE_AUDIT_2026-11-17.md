# Vehicles: audit and plan (17 November 2026)

Phase 0 of the automotive overhaul brief. Nothing is changed by this document. Screenshots of every drivable vehicle
as it is now, from outside and from the driver's seat: `docs/shots/vehicles/all_outside.jpg`, `all_seat.jpg` (and
one picture of each, `NN_<kind>_outside.jpg` / `_seat.jpg`).

## 1. Inventory (what the game drives and draws today)

| Category | Model now (source) | Quality now | Physics now | Upgrade needed |
|---|---|---|---|---|
| Luxury SUV (the player's) | `luxury_suv.glb` (tools/luxury_suv.py + suv_interior.py): lofted body, glass, multi-spoke wheels, a modelled interior. 154 k tris, 17 materials | the best in the game; boxy, flat paint, opaque-looking glass from outside | VehicleBody3D, its own spec (2 150 kg, CoM, springs) | paint, glass, lamps, panel detail, LODs |
| Sedan / taxi | `fleet_sedan.glb` (tools/fleet.py / carbody.py): one swept body, zones for glass/lamps/grille. 19.6 k tris, 10 materials | recognisable car, soft blobby shape, flat colours; the generic cabin's roof pokes through the body from outside | own spec (1 150 kg) | new model: the reference vehicle (Stage 1) |
| Hatchback | `fleet_hatchback.glb` (same tools) | as the sedan | own spec (1 000 kg) | new model (Stage 3) |
| Coupe | `coupe.glb` (tools/coupe.py): sports coupe | stylised, not a Coimbatore car | own spec | keep for now / retire |
| SUV, XUV | built in code (jeep.gd boxes) | **boxes** | own spec | new models (Stage 2) |
| Van, delivery van | built in code (boxes) | **boxes**; no interior (seat view inside a box) | own spec | new models (Stage 4) |
| Bus | `fleet_bus.glb` (tools/bus_tn.py: our own Tamil Nadu express bus, no badges) | decent shape, flat colours; camera too close in the test | own spec (11 000 kg) | detail, materials, an Indian town bus as well |
| Lorry | `fleet_lorry.glb` (tools/fleet.py) | simple cab and body | own spec (12 000 kg) | new model (Stage 4) |
| Auto | `fleet_auto.glb` / `fleet_auto2.glb` (fleet.py; Sketchfab CC-BY auto, an earlier session's) | fair | own spec (450 kg, 3 wheels) | detail, interior (Stage 5) |
| Motorcycle | built in code (boxes); parked: `bike_motorcycle_*.glb` (bikes_real.py) | **boxes** when driven | two-wheeler balance (works well: docs/VEHICLE_LAB.md) | use the detailed bikes (Stage 5) |
| Scooter | `karthik_scooter.glb` (bikes_real.py + story_scooter.py), 43 k tris; the plain "scooter" is boxes | Karthik's is good; the plain one is boxes | balance, rider IK, mount (B1–B3) | the plain one from the detailed model |
| Tractor | built in code (boxes) | **boxes** | own spec | new model (late) |
| Parked bikes | `bike_scooter_*`, `bike_motorcycle_*` (MultiMesh) | good | static boxes | keep |

**Systems** (all in `scripts/drive/jeep.gd` unless said):

- **Physics**: VehicleBody3D + VehicleWheel3D, one controller for every vehicle, a spec each (`BASE_SPECS`: mass,
  centre of mass, wheel radius, rest, travel, stiffness, torque, top speed, boxes for collision). Engine curve,
  gears (a CVT on scooters), speed-sensitive steering capped by grip, front/rear brake split, anti-roll, surfaces
  and wet grip; two-wheelers balance by torque (`_balance`). Tested in `docs/VEHICLE_LAB.md`. **Sound; keep.**
- **Collision**: box shapes from the spec, layer 1; the street's furniture is on its own layer (4) that cars ignore.
- **Interiors**: `interiors.py` cabins per kind (hatchback, sedan, taxi, auto, bus, lorry, coupe), fitted by
  `_fit_cabin` with an Eye and a SteeringPivot; the luxury SUV its own. The box vehicles have none.
- **Lights**: head and tail lamps by material/name, corner indicators (`_corner_lamps`), night; the traffic's own
  indicators and brake lamps (`city_traffic.gd _lamps`) light any model whose lamp parts are named for it.
- **Damage**: zones (front, rear, left, right), real mesh dents at the hit (`dents.gd`), a pull, hurt engine/lamps;
  NPC-to-NPC crashes in `city_traffic.gd` (low/medium/high, once per contact).
- **Audio**: synthesised engine (AudioStreamGenerator, rpm), road noise, horn; crash sound for traffic.
- **Cameras**: chase, cockpit, bonnet (`cam_mode`), mirrors (a SubViewport).
- **Traffic**: `city_traffic.gd` kinematic vehicles on lanes (drivers, signals, junctions, people, crashes), the
  `fleet.gd` models; parked cars a MultiMesh per tile (`city_streamer.gd`) with collision boxes, takeable.
- **LOD**: MultiMesh visibility ranges and `lod_bias` for parked; Godot's automatic mesh LOD; no hand-made LODs.

**Dependencies to keep working** when a model changes: `fleet.gd` (traffic, parked meshes via `parts`), jeep.gd
SPECS (`glb`, wheel names `Wheel_*`, the materials named Paint / Glass / Headlight / Taillight), `interiors.py`
(the cabin's Eye and SteeringPivot), `dents.gd` (mesh-deformable surfaces), the parked MultiMesh (one merged mesh).

**Other sessions' drafts** (not committed, not touched): `tools/aruvia_suv_concept.py`, `nilgiri_tourer_draft.py`,
`real_vehicle_drafts.py`, `road_fleet_review.py`.

## 2. What's wrong, in one line each

Seven of the sixteen drivable vehicles are boxes; the modelled ones are soft, flat-coloured and simple-surfaced;
glass reads as dark opaque panels; no PBR (paint is a flat colour, no clearcoat, no normal maps, tyres and rubber and
chrome are all plain colours); the generic cabins show through the bodies from outside; no hand-made LODs.

## 3. Plan (the brief's roadmap, adapted)

**Stage 1, the reference sedan**: a new compact Indian sedan (our own, unbadged design, ~4.0 × 1.73 × 1.5 m,
right-hand drive), modelled for quality: separate body panels (doors with gaps, bonnet, boot, bumpers, fenders,
skirts), bevelled edges, weighted normals, real wheel arches; wheels with tyre sidewalls and tread, rims, hubs,
discs and calipers; a full interior (dash, cluster, wheel, column, seats with headrests, door cards, pedals,
mirrors, wipers, belts). A PBR material library used by every vehicle from then on: car paint (base, flakes,
clearcoat via a ShaderMaterial), glass (transparent, reflective, tinted; cheap for distant cars), tyre rubber with
a normal map, chrome, plastics, upholstery; lamp lenses with emissive parts named for the lamp system; LOD1/LOD2
exported alongside. Into the game as `sedan` (player and traffic), tested in the city: pictures outside, inside,
wheels, a drive, a crash, the traffic, frame times.

**Stages 2–7**: the SUV (a different body, its own physics), the hatchback and an MPV, the commercial vehicles (a
TN town bus, the lorry, a van and a goods carrier), the auto and the two-wheelers (from bikes_real.py), then the
traffic LOD and the performance benchmark (5 / 15 / 30 / 50 vehicles).

**One decision first (the user's)**: where the models come from. Our own, built in Blender (original, no licence
questions, the existing pipeline; quality limited by what we can model in code, a vehicle a stage), or downloaded
high-quality models with interiors (CC0 / CC-BY, cleaned up and unbadged: faster, possibly better looking, needs
your approval and Sketchfab login for each, and the earlier ones were taken out for their quality).

## 4. Progress

**Stage 1, the reference sedan, first version (17 Nov)** — `tools/cars/sedan_ref.py` on `tools/cars/carkit.py`:
our own compact sedan (3.995 × 1.735 × 1.515 m, 2.45 m wheelbase, 185/65 R15, right-hand drive), in the game as
the drivable `sedan` (`godot/assets/vehicles/car_sedan.glb`, `"own_cabin": true`). The body swept through
cross-sections; panel gaps cut (doors, bonnet, boot, bumpers, the fuel lid); arches cut and lined; glass, lamps,
grille, intake and fog lamps cut to their outlines on the curved surface (clean edges); lamps with housings,
projectors, DRLs, indicators, tail/brake/reverse segments named for the lamp system; slatted grille, intake mesh,
mirrors with indicators, handles, wipers, aerial, exhaust, Indian plates (made-up registration); wheels with
shaped tyres and tread, alloys, hubs, discs and calipers; a PBR library (clear-coated paint, see-through glass,
chrome, grained plastics, fabric, carpet, rubber; their detail textures made in the script). The cabin: dash with
a hooded cluster (speed, revs, fuel dials whose needles the game turns), centre screen, vents, hazard switch,
climate knobs, glovebox; the wheel on its column (turns with the steering), stalks, three pedals, bolstered seats
with headrests, rear bench, console with gear lever and handbrake, door cards, headliner, visors, rear-view
mirror, belts, cabin light; the driver's Eye. 226 k triangles. Tested: `--sfvehicletest=sedan` (pictures
`docs/shots/sedan_ref/`), `--taketest` (taken from the street, driven, parked).

Still to do on it: the A pillar is too thick from the driver's seat; the dash wants more shape and detail; Karthik
seated with his hands on the wheel (IK); LODs; the traffic and parked cars keep the old model until the traffic
stage (a 226 k-triangle car is too heavy for hundreds of parked copies without LODs); then the cameras (the
interiors-and-cameras brief).

**Cameras and the driver (17 Nov)**, the interiors-and-cameras brief, first part: five driving cameras on V
(city_test.gd `CAM_MODES`): Chase (lagging into bends, speed-aware, kept off walls/poles/vehicles by a ball's sweep
not a ray), Driver (his eyes: the faintest give to the car's accelerations, ~1 cm), Driver (head) (a soft spring
against pulling away, braking, cornering and bumps, ~2–4 cm, a little roll, looking into the turn), Bonnet,
Cinematic (a slow orbit); Q / E look left / right and C behind, held, in any of them, without touching the
steering. Settings (field of view inside and out, follow distance, height, smoothing, head movement, shake, invert)
in the settings screen's Camera section (scrolls now), saved in settings.cfg. Karthik sits in the sedan (the Sit
clip, reclined against the seat, hands on the rim at ten to two turning with it, feet on the pedals: rider_ik.gd),
the cockpit camera at his own eyes (jeep.gd `eye_point`), his head and neck hidden from there so his arms and hands
on the wheel are seen. Tested (`--camtest=sedan`: every mode pulling away and braking, the looks;
`docs/shots/cameras/`).

Still to do on the cameras: per-vehicle camera configurations (bus, truck, auto, two-wheelers), his hands closed
round the rim, the steering wheel easier to see, entering through the door (an animation), interior/exterior
audio states.
