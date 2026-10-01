# Coimbatore → Kotagiri: realistic travel, exploration and life simulation

The working brief for the game: a condensed version of the master prompt, with the current status of each phase.
Engine: **Godot 4.7** on an Apple M1 (8 GB). The brief's Unreal terms map to Godot equivalents:
World Partition becomes tile streaming, HLOD becomes merged tile meshes plus LOD, and Blueprints become GDScript systems.

## Non-negotiables
1. **The resort is finished. Do not redesign it.** It's the canonical destination, built from `MistVillage.blend` (via `export_godot.py`) with its architecture, layout, roads, gate and landscaping preserved. Build the world *around* it.
2. **Genre:** realistic travel, driving, exploration, life simulation and light missions. Not racing, arcade, combat or a GTA clone.
3. **Realism rule:** "Would this realistically exist or happen on a Coimbatore → Kotagiri journey?" If not, don't add it.
4. **Priorities:** believability → detail → interaction → simulation → performance → visual quality, ahead of map size.
5. **Real-world proportions** for roads, vehicles, buildings, doors, people, footpaths and parking.
6. **Controlled imperfection:** potholes, dust, faded paint, varied vehicle condition. Variation, not dirt everywhere.
7. **Data-driven systems:** missions, buildings and NPCs are defined as data (JSON), not hard-coded one by one.
8. **No real brands or logos, and no real banking credentials:** vehicles are "in the style of", payments are fictional cash/card/UPI-style.

## Journey and zones
Coimbatore city (A) → outskirts (B) → rural/foothills and Mettupalayam (C) → mountain ascent and hairpins (D) → Nilgiri tea and forest (E) → Kotagiri (F) → resort area (G).
Resort approach sequence: main road → local road → **resort access road → resort sign → gate → security → parking → reception**.

## Systems (reusable, data-driven)
Vehicle · Traffic · NPC · Building · Interaction ([E] prompts) · Shop · Restaurant · Inventory · Economy (₹25,000 start) ·
Mission · GPS · Map · Phone (Map, Messages, Contacts, Money, Weather, Missions) · Weather · Time (day/night, opening hours) ·
Police · Hospital · Emergency (accident → police → ambulance → tow) · Save · Audio · World streaming.

## Phase status (as of 2026-10-01)
| # | Phase | Status |
|---|---|---|
| 1 | Player + vehicle + camera | **Done (basic).** SUV (XUV700-style), 6-speed diesel auto/manual, ETS-style steering, chase/cockpit/bonnet cameras. Missing: hatchback and sedan player cars, indicators, high beam, wipers, entry/exit animation |
| 2 | Roads + terrain | **Done.** Real OSM route with SRTM terrain, ETS-style compression, cuttings and embankments, walls and parapets |
| 3 | Coimbatore | **Partial.** 777 real streets, 5,242 real buildings, landmarks. Missing: footpaths, kerbs, traffic lights, street lights, signs, parked vehicles |
| 4 | Traffic | **Basic.** Highway-only lane followers (bus, truck, car, auto, tractor). Missing: town traffic, overtaking, lane changes, junctions, signals, bikes and scooters |
| 5 | Foothills | **Partial.** Mettupalayam as an open town, Bhavani bridge, checkpost, elephants |
| 6 | Mountain roads | **Done (basic).** 9 real hairpins, chevrons, parapets, studs, mist. Missing: convex mirrors, narrow passing sections, rain |
| 7 | Kotagiri | **Partial.** Real streets plus generated buildings. Missing: functional businesses |
| 8 | Resort integration | **Done.** Embedded at the end of the Kodanad road with blended terrain. Missing: access road, resort sign, security, parking flow, reception |
| 9 | Walking | **Done (basic).** First-person on foot (F) |
| 10 | NPC AI | Not started (needs rigged, animated characters) |
| 11–15 | Interactive buildings, shops, restaurants, fuel/mechanic, hospital/police | Not started |
| 16 | GPS + map + phone | **Partial.** Minimap, Tab map, A* GPS with recalculation. Missing: street names, ETA, turn arrows, search, POI filters, phone |
| 17–18 | Missions, economy, inventory | Not started |
| 19 | Weather + day/night | Resort only. Drive: fixed morning plus mist by altitude |
| 20 | Dynamic events | Elephants and checkpost only |
| 21 | Audio + animation | Synthesised engine and horn only |
| 22 | Optimisation | **Urgent.** 6–40 fps on the M1 |
| 23 | Polish | Not started |

## Test harness
`godot --path godot res://scenes/drive.tscn -- --autodrive --start=<m> --snap=<file.jpg>` (also `--trace`, `--cam=1|3`, `--nofog`, `--gps --openmap`, `--onfoot`, `--timescale=N`, `--quit-at-end`).

## Progress log
- 2026-10-01 · M1 performance: resort streamed out beyond 1.6 km (ghat 10 → ~40 fps), far-tree LOD in 512 m cells (draws 538 → 418), prop GLBs preloaded on engine threads (props load 8.2 s → 2.7 s), cheaper tea rows.
- 2026-10-01 · M2 core loop: `scripts/drive/sim.gd` (clock ×6, Markov weather clear/cloudy/rain/mist with altitude bias and tyre grip, ₹ wallet, diesel burn scaled to real distance, opening hours, save file `user://savegame.json`). Sky follows the clock (dawn/noon/night gradients, overcast, moonlight), rain particles and hiss, town windows, bunk floodlights and resort lamps at night. HUD at top right. [E] prompts for fuel bunks (generic forecourts beside OSM fuel stations, no brands) and the chai stall. Low fuel sets GPS to the nearest bunk. F5 save, autosave every 3 min and on F10, "Continue your journey" in the menu. Test flags: --time=H --weather=rain|mist|cloudy|clear --fuel=0..1 --bunk=N --save --continue.
- 2026-10-01 · Road network: tools/towns.py now builds a junction graph (OSM ways split at shared vertices; streets reaching the highway run to its edge and end on a `highway` node tied to a route sample; streets settled onto the final carved ground). towns.json carries `nodes` + per-street `a`/`b`. `scripts/drive/road_graph.gd` is the single source for street meshes, junction surfaces, GPS (nav.gd joins only at real nodes, no fuzzy 7.5 m links), surface grip and validation. Validator (`--validate-roads`, or F3): 3,202 streets, 97.5% of nodes reachable from the highway, 0 broken refs, terrain gaps 327 → 4. F3 debug mode: fps/pos/surface, road-graph overlay, F6 +1 h, F7 weather, F8 skip. GPS shows "Route deviation · recalculating…" when you leave the route by 25 m.
- 2026-10-01 · Street edges: main roads get drain + black/white kerb + raised pavement (with collision); small streets get dirt shoulders. Concrete poles with sagging wires along streets; streetlights with glowing heads and light pools on the road at night. ~4,300 parked vehicles (Kenney cars/vans + built autos, motorbikes, scooters) by street class and shop density. Off-road: grass/dirt lowers grip and adds rolling resistance (no invisible walls). Chase cam avoids walls, reacts to acceleration/braking, widens FOV with speed. Debug teleport `--at=x,z[,yaw]`.
- Waiting on the user: realistic SUV model (Sketchfab CC-BY or bought) to drop into godot/assets/vehicles/.
- 2026-10-01 (pm) · fps re-checked with best of three runs: Coimbatore 115–137, ghat ~39, Kotagiri ~60–130, resort ~114. Coimbatore's unmapped blocks are now filled with generated buildings (+3,174). Rooftops: black water tanks, stair-head rooms, dishes; balconies with railings; split-AC units. Town traffic (`town_traffic.gd`): 34 autos/bikes/scooters/cars/buses on the road graph, keep left, slow into junctions, turn onto real connected streets, obey one-ways, queue and stop for the player, recycled out of view (~1.4 ms/frame). Wet roads: asphalt darkens and turns glossy in rain, dries over an hour (sim.wet). Car lamps: brake, tail (with headlights), reverse, indicators `,` `.` and hazards `/`, self-cancelling after the turn.
- Still open: pedestrians (need a decision on CC0 character models: procedural people would look low-poly), realistic player SUV (user download).
- 2026-10-01 (eve) · Pedestrians (`pedestrians.gd`): 10 Quaternius characters from poly.pizza (8 CC0, 2 CC-BY 3.0, credits in godot/assets/drive/people/CREDITS.txt), 14 MB. 36-person pool walking the road graph's pavements/edges, stopping for cars, pausing at shopfronts (Interact), standing/chatting/waving; recoloured per person (South Indian skin tones, black hair, varied clothes); denser on main roads; filled around you at load, later respawns out of view; shadows only within 22 m. ~1 ms/frame, Coimbatore best-of-3 143 fps.
- 2026-10-01 (night) · Player car is now the user's sports coupe: tools/coupe.py (the user's Blender generator, unchanged) + tools/export_coupe.py (`/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/export_coupe.py`) → godot/assets/vehicles/coupe.glb. jeep.gd loads it (`--xuv` brings back the SUV): Blender wheels ride the physics wheels (2.6 m wheelbase, 0.34 m wheels, firmer suspension, 1,450 kg, low centre of mass), see-through tinted canopy, its headlights/tail bar are the working lamps (+ indicators, reverse lamps), cockpit lowered with an interior trim panel, bonnet cam moved.
- 2026-10-01 (night) · GTA-style vehicles: jeep.gd is data-driven (`SPECS`, `configure(kind)`): the user's Luxury SUV (tools/luxury_suv.py + tools/suv_interior.py → tools/export_vehicle.py → assets/vehicles/luxury_suv.glb, full interior, turning steering wheel, live screens) is the start car; their coupe waits parked behind you; get out (F), walk to any vehicle (parked on the street, town or highway traffic, or one you left) and F to drive it — sedan, compact SUV, taxi, van, delivery truck, tractor, auto, motorbike, scooter, bus, lorry. Cars you leave stay parked. Two-wheelers carry a posed Quaternius rider (rider_pose.gd), also on traffic bikes. Save remembers the vehicle. Debug: `--vehicle=<kind>`, `--swaptest`, `--cam=4` side view.
- Repo: github.com/barathraj130/MISTVILLAGE (dedicated repo in mist-village/; ignores godot/.godot, mapdata/, *.blend1).
