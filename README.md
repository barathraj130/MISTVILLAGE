# THE MIST VILLAGE — KOTAGIRI

*Where the mist slows you down.*

A procedural Blender scene of a 0.35-acre boutique mountain resort in Kotagiri, Nilgiris.
`mist_village.py` builds everything in the scene from nothing and sets up a 45-second, 24 fps, 1920×1080 ten-shot film.

## How to run

**In Blender (4.2 LTS up to 5.x):**

1. Open a new, empty file. The script deletes everything in the current file.
2. Go to *Scripting*, click *Open*, choose `mist_village.py`, then click *Run Script*. It takes about 15–30 s.
3. Press `Numpad 0`, then play the timeline. The camera switches automatically at each shot marker.
4. Choose *Render → Render Animation*. The film is written to `//render/THE_MIST_VILLAGE_45s_1080p.mp4`.

For the night version, set `MODE = "NIGHT"` at the top of the script before running it.

**Headless:**

```bash
blender -b -P mist_village.py -- --save MistVillage.blend            # golden hour
blender -b -P mist_village.py -- --night --save MistVillage_Night.blend
blender -b MistVillage.blend -a                                      # render the 45 s film
```

The render engine is EEVEE, which is quick on a GPU: roughly 1–3 hours for all 1,080 frames at 96 samples.
Every material also works in Cycles if you want to render stills that way.

## Site: survey reconstruction

The boundary follows the dimensions visible on the survey photograph and is **not** a rectangle.

| Edge | Length | Note |
|---|---|---|
| A → B | 13.2 m | top edge |
| B → C | 17.0 m | upper/left segment |
| C → D | 24.8 m | left side, facing the valley (west) |
| D → E | 26.0 m | lower edge |
| E → F | 20.2 m | lower/right segment |
| F → G → A | 10.8 m + 29.2 m | road frontage (east); not dimensioned on the photo |

- The five dimensioned edges alone can't enclose 0.35 acre. The two road-frontage segments were solved so the polygon comes to **1,416 m² (15,240 sq ft, 0.350 acre)** while every dimensioned edge keeps its exact length.
- This is a concept reconstruction, not a legal boundary. If you have the actual survey coordinates, replace `BOUNDARY` in section 3 of the script and everything else follows.
- The collection `01 SITE + SURVEY` contains a viewport-only boundary line, dimension labels and the area readout.

## What's in the scene

The site runs road → gate → parking → reception → courtyard → villas → deck → valley → mountains:

- **Mountain road** along the east frontage: wet asphalt, kerbs and a worn centre line.
- **Stone entrance gate**: stone piers, a timber pergola, brass "THE MIST VILLAGE · KOTAGIRI" lettering and 2700 K lanterns.
- **Parking**: 4 bays of permeable pavers with setts, wheel stops and bollard lights.
- **Reception + café**: 9 × 5.6 m, stone gable ends, a glazed café front, a timber terrace with 3 tables and festoon lights.
- **Central courtyard**: a round stone plaza, a natural-stone fire ring, an animated fire with flicker light and embers, 8 stone and timber seats, and low bollards.
- **3 villas**, each 5.6 × 6.0 m (33.6 m²):
  - *Valley View Villa*: faces the valley, full-height glass gable, a king bed, twin loungers on the deck, and a bathroom.
  - *Mist View Villa*: faces the mist, with a stone fireplace and flue, and a timber soaking tub on the deck.
  - *Forest View Villa*: stone walls, set among dense shola trees, tree ferns and understorey planting.
- **Valley-view deck**: timber boards, a black steel railing, two loungers, a tea table with a tea set, and a warm LED strip.

**Construction details on every building:**

- 250 mm walls on stone plinths.
- 32° charcoal standing-seam roofs, 220 mm thick, with real seam ribs, fascia, barge boards, a ridge cap, half-round gutters, downpipes and gullies.
- Black aluminium mullions, transoms and sliding doors.
- Exposed glulam portal frames, deck joists on posts and footings, and stone steps.

**Terrain:**

- The site steps down in four terraces (+3.0, +2.0, +0.9 and −0.3 m) held by stone retaining walls, with stone steps and cheek walls where the paths cross them.
- Stone-lined drainage channels run along the walls.
- A dry-stone wall follows the survey boundary.

**Landscape:**

- Shola evergreens, cypress, silver oak, eucalyptus, tree ferns, ferns, native shrubs, blue and pink hydrangeas, wild flowers, grass tussocks and mossy boulders.
- Privacy planting follows the boundary, with gaps left open for the valley views.

**Outside the property only:**

- Contour-strip vegetable fields (cabbage, potato, carrot and beans, tilled red soil, fallow land), broken hedgerows, silver-oak shade trees and farmsteads with tin roofs.
- Hill forest.
- The fields start more than 20 m beyond the boundary wall. Nothing agricultural is inside the property.

**Mountains:**

- Four layered ridges at 4, 7, 11 and 17 km, shaped with warped ridged noise so none of them are cones.
- Their surface is a shola-and-grassland mosaic, and they fade into the distance through atmospheric haze.
- Flanking hills to the north and south enclose the valley.

**Visual effects:**

- Volumetric ground fog over the site and haze over the valley.
- Drifting mist layers in the valley and bands of mist between the ridges.
- Floating mist puffs and rising fire embers (particle systems).
- Wet patches on paths and the road.
- A glow (bloom) pass in the compositor.

**Lighting:**

- A golden-hour sun (WSW, 7° elevation), a cool fill from the mountains and a gradient sky.
- Warm 2700 K lights throughout: bedside lamps, pendants, ceiling wash, entry, sign, deck, courtyard and fire.

## Shot list (timeline markers bind each camera)

| # | Time | Shot |
|---|---|---|
| 1 | 0–4 s | High aerial over the Nilgiri ridges and mist |
| 2 | 4–8 s | Along the mountain road toward the property |
| 3 | 8–12 s | Slow approach to the stone entrance gate |
| 4 | 12–16 s | Reveal of the reception and café |
| 5 | 16–21 s | Through the garden to the campfire |
| 6 | 21–27 s | Valley View Villa |
| 7 | 27–32 s | Mist View Villa, with mist and warm light |
| 8 | 32–36 s | Forest View Villa, seen through vegetation |
| 9 | 36–41 s | Toward the valley-view deck and out over the valley |
| 10 | 41–45 s | Aerial pull-back with the title card "THE MIST VILLAGE · Kotagiri · Nilgiris · *Where the mist slows you down.*" |

## Script layout

| Section | Contents |
|---|---|
| 1–2 | Geometry and node helpers, and all procedural materials (no image textures needed) |
| 3 | Survey boundary and terrace plan (`BOUNDARY`, `F0`/`F1`/`F2`, `LEVELS`) |
| 4–6 | Terrain height function, land masks, a non-uniform terrain mesh (0.2 m on site, ~150 m at the horizon) and the road |
| 7 | Boundary wall, retaining walls, steps, paths and drainage |
| 9 | Villas, reception, gate, parking, courtyard and deck (`villa()` controls each villa) |
| 9b | Shot list |
| 10–11 | Vegetation assets and Geometry Nodes scattering, inside and outside the property |
| 12–13 | Mountains and mist/effects |
| 14–16 | Lights, world, cameras, title card, render settings and compositor |

## Game export (Godot 4)

`export_godot.py` converts the saved scene into game assets inside `godot/`, which you open in Godot 4.4 or later. It never saves the `.blend`.

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b MistVillage.blend -P export_godot.py            # ~5 min, 1024 px
/Applications/Blender.app/Contents/MacOS/Blender -b MistVillage.blend -P export_godot.py -- --quick # ~40 s test run
```

| Output | Contents |
|---|---|
| `godot/assets/models/site.gltf` | Buildings, walls, paths and props. Node names ending in `-col` get trimesh collision in Godot. |
| `godot/assets/models/terrain.gltf` | Terrain in three bands (near and mid have collision), with shading baked to vertex colours |
| `valley.gltf`, `mountains.gltf` | Farmsteads and the ridges (mountains use vertex colours) |
| `veg_*.gltf` | 33 plant and rock assets, decimated to ≤7k vertices for trees |
| `models/textures/` | Seamless tiles baked from the procedural materials (albedo, roughness, normal) |
| `godot/assets/scene.json` | 44k vegetation instances, lights, sky, fog, mist, campfire, particles, the 10-shot camera path (1,080 frames), title card, anchors, survey boundary, spawn point, and golden/night presets. Coordinates are already in Godot's Y-up space. |

**Playing it:** open `godot/project.godot` in Godot 4.4 or later. The first open imports the models and can take a few minutes. Then press F5. `scripts/world_builder.gd` builds the whole world from `scene.json` when the game starts: sky, lights, fog volumes, mist, the fire, 44k vegetation instances in MultiMesh chunks with wind, tree colliders, the intro film and a first-person player.
Controls: WASD move · Shift run · Space jump · N golden hour ↔ night · C replay intro · Esc free the mouse.
When you export a build, add `*.json` to the export preset's *Filters to export non-resource files* so `scene.json` is included.

## Start menu

The game opens on a title screen: **Drive up from Coimbatore** (the road trip) or **Start at The Mist Village** (the resort, as before). F10 returns to the menu from either.

## The real Coimbatore → Kotagiri map

The drive now follows the **real road** from OpenStreetMap (Gandhipuram → NH181 → Mettupalayam and the Bhavani → SH15 Kotagiri ghat → Aravenu → Kotagiri), over **real terrain** from 30 m SRTM elevation data. Like Euro Truck Simulator, it's compressed: 70.2 km becomes 24.5 km (straights about 9× on the plains, 2× on the ghat, 3× in towns). Bends and hairpins keep their true shape, and climbs are scaled so the ghat averages about 10%. The HUD shows real altitude and real kilometres to Kotagiri. The checkpost and the viewpoint tea stall sit where OpenStreetMap has them.

```bash
python3 tools/build_real_route.py     # find the route in mapdata/osm.json + sample elevation → real_route.json
python3 tools/compile_drive_map.py    # compress it and bake terrain → godot/assets/drive/*.bin + map.json (~20 s)
```

`mapdata/` holds the downloaded inputs (Overpass export `osm.json`, elevation tile `N11E076.hgt.gz`). Tune the compression in the `ZONES` and `TOWNS` tables and `VERTICAL` in `compile_drive_map.py`. Launch the drive with `-- --fictional` to get the original made-up road.
Map data © OpenStreetMap contributors (ODbL). Elevation: SRTM via Mapzen terrain tiles. The credit is shown on the start menu.

## Your car and the trucks

- **Your car** (`godot/scripts/drive/jeep.gd`; the old file name is kept) is a premium mid-size SUV in the style of the XUV700, with no badges or logos. It has an electric-blue metallic body with a black floating roof and rails, a black grille with chrome slats, C-shaped LED DRLs, split tail lamps, flush door handles, 18" five-spoke alloys, tinted glass all round and TN 43 plates. Inside there's a twin-screen dashboard with a digital speed and gear/RPM readout, a steering wheel that turns, and a live rear-view mirror. Right-hand drive.
- **Driving (Euro Truck-style):** steering ramps in gently and returns to centre faster, and it's speed-sensitive (0.6 rad at a crawl, about 4° at highway speed). Throttle and brakes ramp in. 2,000 kg, soft suspension, low roll, damped yaw. 6-speed diesel automatic with 450 N·m (M for manual, X/Z to shift), AWD, governed at 160 km/h. The chase camera sits further back and lags smoothly.
- **Trucks** (`traffic.gd`) are European cab-over heavy rigids in the style of a Scania (no badges): tall flat-fronted cab, big windscreen, sun visor, roof air deflector, horizontal-slat grille, mirrors on arms, chrome fuel tanks, three axles with dual rear wheels, a box or curtain body with a stripe. Four colour schemes.

## Open-world towns, map and GPS

**Coimbatore** (Gandhipuram, 1.3 km around), **Mettupalayam** (1.1 km) and **Kotagiri** (1.4 km) are explorable at true 1:1 scale. The highway keeps its exact real shape inside them, so every OpenStreetMap street lines up with it.
- `tools/towns.py`, run by `compile_drive_map.py`, builds each town from `mapdata/town_*.json` (Overpass exports). It takes every street, gives it its own height from the real terrain and carves it in, keeps real building footprints (Coimbatore has 5,242), fills thinly-mapped streets with generated shops and houses (about 3,300 in Mettupalayam and 1,000 in Kotagiri), and collects named landmarks (bus stands, temples, markets, the railway station, hospitals, petrol bunks). Output: `godot/assets/drive/towns.json`.
- `godot/scripts/drive/towns.gd` builds the streets (drivable, with collision), buildings, and floating landmark names. Every building shares one facade shader (`shaders/building.gdshader`) that draws windows on each floor, rolling shutters and coloured sign bands on ground-floor shops, and lit windows at night.
- `map_ui.gd` + `nav.gd`: a rotating minimap (bottom-left) and a full map on **Tab** (wheel to zoom, drag to pan, click a landmark to set the GPS, Shift-click any road, right-click to clear). The GPS runs A* over the highway and every town street, draws the route in magenta, counts down the distance and recalculates if you leave the route.
- The drive now continues 2.9 km past Kotagiri on the real Kodanad View Point road to the resort (73 km real, 31 km in game).

## Small details (`godot/scripts/drive/details.gd`)

Built in code and merged into a few meshes per 2 km, so they're cheap to draw:
- **Road surface:** tar patches, potholes with muddy rims, sealed cracks, and reflective studs on the ghat that glow in the headlights.
- **Signs and stones:** black-and-yellow chevron boards on the outside of every sharp bend, 200 m stones, white-painted guard stones on the plains and foothills.
- **Roadside:** small temple shrines (stepped, painted towers with a flag and an oil-lamp glow), bus shelters named after each town, NH181 billboards.
- **Animals:** cows on the verges (you can't drive through them), monkeys sitting on the ghat parapets.
- **Buildings:** upper-floor windows, balconies with railings, tube lights under the awnings.
- **Jeep:** TN 43 number plates (the Nilgiris code), side mirrors, mud flaps and wipers.

## One world: the drive ends at your resort

On the real map, the resort is built **inside the drive world** at the end of the road in Kotagiri (`world_builder.gd` with `embedded = true`). You drive straight up to the gate with no loading screen. The resort's road is clipped to its grounds and joins the drive's road exactly. The map's ground sinks under the resort's own ground, a 70 m ring blends the two, and both use the same photo textures. Map trees, poles and tea bushes stay out of the grounds.
**F** gets you out of the jeep (driver's door, on the right) anywhere along the drive, to walk with the resort's first-person controls (WASD, Shift, Space, mouse). Press **F** next to the jeep to drive again. **F8** jumps to the Kotagiri approach. The start menu's "Start at The Mist Village" still opens the resort on its own, with its intro film and day/night.

## The Road Up (playable prologue)

The game now opens with a drive: Coimbatore → Mettupalayam → the Kotagiri ghat → The Mist Village gate. It's a compressed version of the real road (about 7.8 km, 10–15 minutes) in a right-hand-drive jeep that keeps to the left lane. `godot/scenes/drive.tscn` is the main scene, and arriving at the gate loads the resort with the intro film skipped.

Everything is generated at load in `godot/scripts/drive/`. There's no Blender step:

| File | What it builds |
|---|---|
| `route.gd` | The road's plan (plains curves, 9 hairpins), terrain height, stages, real altitude and temperature for the HUD |
| `terrain.gd` | A 4 m detailed corridor with cuttings and embankments under the road, plus a 64 m backdrop to 9 km |
| `road.gd` | Asphalt, markings (solid yellow on the ghat), shoulders, stone retaining walls, black-and-yellow parapets, the Bhavani bridge and river, milestones and signs |
| `props.gd` | Towns, coconut and areca groves, forest, contour tea gardens, the forest checkpost (boom barrier), a tea stall and the gate |
| `traffic.gd`, `elephants.gd` | Buses, lorries, cars, auto-rickshaws, and an elephant herd crossing |
| `jeep.gd`, `drive_game.gd` | Vehicle physics, headlights, horn, engine sound, camera, HUD, events, mist, arrival |

Realism: CC0 photo textures from ambientCG (`godot/assets/drive/tex/`, listed in `CREDITS.txt`) cover the ground (dry grass on the plains, green hills, red-soil cuttings, rock, forest floor), the asphalt, gravel shoulders, concrete parapets, plaster buildings and tin roofs. The jeep has a 5-speed diesel gearbox (automatic, or manual with M, then X/Z to shift), a torque curve, engine braking and drag, an RPM-driven engine sound, and a cockpit view (V) with working gauges, a turning steering wheel and a live rear-view mirror. Towns have speed breakers and street lamps.

Models (CC0): Poly Haven props made game-ready by `tools/make_game_props.py` (Blender: joins parts, recentres, decimates to 700–6,000 triangles, keeps textures). They're used for wooden electricity poles with sagging wires along the whole route, rolling shutters on shop fronts, plastic monobloc chairs, utility boxes, mossy rocks, shrubs and ferns on the ghat verges, and concrete barriers at the checkpost. Kenney's Car Kit supplies the traffic sedans, taxis, SUVs, vans, trucks and tractors, scaled to real lengths. Sources are in `mapdata/polyhaven/`; the game uses only `godot/assets/drive/props/*.glb` and `godot/assets/drive/models/kenney/`.

Keys: W/S accelerate or brake/reverse · A/D steer · Space handbrake · H horn · L headlights · V camera (chase / cockpit / bonnet) · M manual gears, X/Z shift · R back onto the road · E interact · F2 quality · F8 skip to the resort.
Testing: `godot --path godot -- --autodrive --timescale=3 --trace --shots=/abs/dir --quit-at-end` drives the whole route by itself and saves a screenshot at each stage.
