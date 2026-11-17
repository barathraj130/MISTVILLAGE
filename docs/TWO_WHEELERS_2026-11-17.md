# Motorcycles and scooters: audit, and the first one rebuilt (17 November 2026)

The two-wheeler overhaul brief. Order kept: one commuter motorcycle first (this), then one scooter, then the rest
of the two-wheeler fleet, then the traffic.

## 1. Audit (what was there)

| Part | What it was | Kept / changed |
|---|---|---|
| Models | the drivable "bike" and "scooter": boxes built in code until today's morning, then the rider scenes' models (`tools/bikes_real.py`: tubes and lofts, a disc-like wheel, stylised); Karthik's scooter (`tools/story_scooter.py`, the same scooter in his paint) | the motorcycle rebuilt (below); the scooters next |
| Physics | `jeep.gd`, one VehicleBody3D controller: two wheels in line, balanced by torque on the physics body (`_balance`: a damped spring on the roll toward the lean the turn needs, `v·yaw/g`, stiffer at a crawl), the line held as a bike's trail does (`yaw = v·tan(steer)/wheelbase`, capped by the tyres' grip), speed-sensitive steering capped at ~0.95 g, front/rear brake split, wet grip, surfaces | kept: it leans the body itself, nothing is turned apart from the physics. The motorcycle's gearing was wrong (first gear so tall the engine idled at 11 km/h): a commuter's now |
| Rider | Karthik in his helmet (the Ride clip), `rider_ik.gd`: hands to grip markers on the bar, feet to pegs, body leaning with the bike, his left foot down when stopped | kept; the bar's axis, grips and pegs now from each bike's spec |
| Lights | head lamp and tail lamp by part name (the tail brightens when braking), indicators and hazards (`_update_lamps`) on stand-in boxes placed from the spec | the model's own indicator lenses blink now (`own_ind`) |
| Cameras | chase, his eyes, his head, "bonnet", cinematic, the looks (Q/E/C) | his eyes tilted down to see the bars (`eye_pitch`), the "bonnet" camera a handlebar camera on two-wheelers (`bonnet`) |
| Audio | a synthesised engine per kind (a single-cylinder's firing, `ENGINE_SOUND`), horn, gears on the motorcycle | unchanged |
| Damage | zones, dents in the meshes at the hit (`dents.gd`), the rider hurt / hospital | dents a bike's size now (they spread over the whole bike) |
| Crashes off the bike | set aside (docs/wip/bike_crash_B4.patch: falling off, sliding) | still to do |

## 2. The commuter motorcycle (`tools/cars/build_moto.py`)

Our own 125 cc commuter, unbadged, built in Blender from code on the car kit's PBR library (no downloads):
2.02 m long, 1.285 m wheelbase, 0.74 m across the bars, the seat at 0.79 m, 26° rake; 2.75-18 / 3.00-18 tyres.

- **Wheels**: round-crowned tyres with bulged sidewalls and a zig-zag tread; five-spoke Y alloys (black, machined
  lips), hubs, axle nuts; a 240 mm drilled disc on its carrier (spins with the wheel) and a twin-piston caliper on
  its bracket; the rear drum, its plate, arm and rod, the 42-tooth sprocket.
- **Front**: telescopic forks (polished sliders, chrome stanchions, painted covers, top nuts), both yokes, the
  painted headlamp nacelle with a chrome bezel, reflector, lens and bulb, the visor, the cluster (an analogue
  speedometer whose needle reads the real speed to 120 km/h, a fuel gauge, tell-tales), swept handlebar with
  clamps, ribbed grips, bar ends, switch housings, levers on perches, the brake master cylinder and reservoir,
  throttle, cables and the brake hose, mirrors, indicators on stalks, the front mudguard on stays, the horn, the
  front plate.
- **Engine**: crankcase, the clutch cover with its bolts and oil filler, the magneto cover, the sprocket cover, the
  forward-inclined barrel with eleven fins, the finned head and valve cover, plug cap and lead, carburettor,
  intake, air box, starter motor; the exhaust header round under the engine into a chrome silencer with a black
  heat shield and its bolts.
- **Frame and rear**: head tube, backbone, downtube, pivot plates, seat rails, struts, engine hangers; box-section
  swingarm, brace, pivot bolt, chain adjusters; twin shocks (red springs, damper bodies, chrome rods, rubber
  eyes); the chain (link by link round both sprockets), the front sprocket, the chain guard.
- **Body**: a sculpted tank with knee recesses, rubber knee pads, the filler cap; the seat (stepped for the pillion,
  red stitching and piping); side panels with louvres; the tail cowl, tail and brake lamp, rear indicators; the
  rear mudguard, plate holder, plate, plate lamp; cast grab rails; the saree guard on the left (as on every bike
  sold here); a crash guard; footrests, pillion pegs on hangers, gear lever, brake pedal, side and centre stands.
- **Materials**: clear-coated metallic paint (recoloured per bike by the game), chrome, brushed engine alloy, dark
  engine paint, gloss frame black, grained plastics, rubber, the seat's vinyl and stitching, glass lenses,
  emissive lamps. Its detail textures are 256 × 256 normal maps made in the script (grain, weave, flake).
- **Size**: 62 k triangles, 17 objects (parts joined by what they do: wheels, the bars, body, frame, engine,
  brightwork, blackwork, details, the lamps apart), 2.4 MB `.glb`.

**In the game** as `bike` (`godot/assets/vehicles/moto_commuter.glb`, 235 kg). Tested:

- `--sfvehicletest=bike`: two wheels, seat, mass; Karthik seated, hands on the grips, feet on the pegs.
- `--ride=bike --ridetest`: standing with his foot down; away at 3.3 m/s after 2 s at 60 % throttle; 8.5° and
  11.5° of lean in the left and right turns; braked to a stop, foot down.
- `--ride=bike --camtest=bike`: every camera (his eyes see the nacelle, indicators, cluster and mirrors; the
  handlebar camera behind the cluster; looking left shows the mirror and grip).
- `--ride=bike --crashtest`: into a hatchback at 64 km/h and an auto at 56 km/h: front damage, local dents, the
  rider hurt.

Pictures: `docs/shots/two_wheelers/moto_blender.jpg` (bars, engine, front, three-quarter, rear, rear
three-quarter, both sides, wheel), `moto_in_game.jpg` (standing, riding, turning, braking, stopped),
`moto_cameras.jpg`. No frame-time measurement yet (one bike of 62 k triangles; the traffic stage will measure).

## 3. Not done yet

- On this motorcycle: the engine's carburettor and air box are still plain shapes; the knee pads flat; no LODs.
- The scooter (its own step-through architecture, apron, under-seat storage, floorboard, its own handling).
- Colour variants exposed in the game (the paint is recoloured; no list per bike yet); high/low beam; the indicator
  tick sound; broken mirrors and indicators in a crash; falling off and sliding (docs/wip/bike_crash_B4.patch).
- The rest of the fleet (a classic roadster, a sport bike, a tourer; a family scooter, a modern scooter, an
  electric one) and the two-wheelers in the traffic.
