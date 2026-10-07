# Coimbatore Open-World Map — Pipeline Design

Status: **design only** (nothing in this document is built yet unless marked ✅ *exists*).
Goal: a playable 1:1 recreation of the Coimbatore metropolitan road network, built automatically
from open GIS data, with buildings, landmarks, traffic and people layered on top — extending the
pipeline the game already uses rather than replacing it.

---

## 0. Where we start from (what exists today)

| Piece | Today | File |
|---|---|---|
| OSM extract (Overpass) | ✅ roads, places, rivers, railways, landmarks, buildings around the route | `mapdata/osm.json`, `mapdata/roads.overpassql`, `mapdata/town_*.json` |
| Elevation | ✅ SRTM 1″ tile N11E076 (via Mapzen terrain tiles) | `mapdata/N11E076.hgt.gz` |
| Route + compression | ✅ the Coimbatore → Kotagiri drive, ETS-style compressed outside towns | `tools/build_real_route.py`, `tools/compile_drive_map.py` |
| Towns at 1:1 | ✅ **Coimbatore only 1.3 km around Gandhipuram**, Mettupalayam 1.1 km, Kotagiri 1.4 km | `tools/towns.py` (`TOWN_ZONES`) |
| Street graph | ✅ OSM ways split at shared nodes, junction / end / highway nodes, network repair (100% reachable) | `towns.py _street_graph`, `_repair_network`; `godot/scripts/drive/road_graph.gd` |
| Road meshes | ✅ asphalt, kerbs, drains, pavements, shoulders, lane paint, curved junction corners, driveways | `godot/scripts/drive/towns.gd` |
| Ground | ✅ carved, clamped under every road | `compile_drive_map.py`, `towns.sink_under_roads` |
| Buildings | ✅ OSM footprints + generated fill; 28 designed variants fitted near the player, blocks far | `towns.py`, `tools/buildings.py`, `building_kit.gd` |
| Traffic / people | ✅ town traffic on the street graph (keep left, one-ways), pedestrians on pavements | `town_traffic.gd`, `traffic.gd`, `pedestrians.gd` |
| Day / night, weather | ✅ clock, sun, rain, mist, wet roads, street / window lights | `sim.gd`, `drive_game.gd` |
| Tiling | ✅ 256 m mesh tiles, MultiMesh, visibility ranges — **but everything loads at start** | `towns.gd` |

**Gaps this design closes:** metro-wide coverage, true streaming, elevated bridges / flyovers,
roundabout geometry, a lane graph with traffic signals, water / land use layers, a landmark layer,
pedestrian navmesh, and explicit REAL vs GENERATED provenance.

**Engine decision:** stay on **Godot 4** (primary). Unreal Engine 5 (Nanite, World Partition, HLOD) is
kept as an *optional* export target only: it needs a Windows PC with a strong GPU, does not run well on the
current 8 GB M1, and switching would discard the existing game. The pipeline's outputs are engine-neutral
(JSON + binary grids + glTF) so a UE5 importer can be added later (§14).

---

## 1. Project architecture

```
             ┌──────────── DATA (mapdata/cbe/<date>/) ────────────┐
OSM PBF / Overpass ─┐   SRTM / Copernicus DEM ─┐   ESA WorldCover ─┐
                    ▼                          ▼                   ▼
          tools/citygen/  (Python, one stage per module, cached between stages)
  01 fetch → 02 clip → 03 clean+topology → 04 classify → 05 graph (+lanes) →
  06 geometry (roads, junctions, roundabouts, bridges) → 07 terrain (DEM, carve, water) →
  08 landuse + vegetation → 09 buildings (+ landmarks) → 10 furniture → 11 traffic →
  12 pedestrians → 13 chunk → 14 export → 15 validate / report
                    ▼
   build/cbe/chunks/CBE_x_y/{chunk.json, ground.bin, roads.glb?, …}   + index.json
                    ▼
   Blender (headless): asset library (buildings kit, landmarks, props, vehicles), optional
   per-chunk mesh merging + LODs
                    ▼
   Godot: CityStreamer loads chunks around the player (threaded), builds meshes / MultiMeshes,
   collision, nav regions, traffic lanes; unloads behind.
```

Principles
- **Data-driven:** every number (widths, lanes, densities, styles) lives in config files (§18).
- **Deterministic:** same inputs + config → same world (seeded RNG per chunk).
- **Incremental:** each stage writes a cache; a chunk is rebuilt only if its inputs' hash changed (§19).
- **Provenance everywhere:** every road, building, prop carries `src` = `osm:<type>/<id>` or `gen:<rule>` (§15).
- **Coexists with the drive:** the city world is a 1:1 zone; the Coimbatore → Kotagiri route stays compressed
  outside it, joining the city at its boundary (the existing `TOWN_ZONES` mechanism, scaled up).

## 2. Data acquisition

| Layer | Source | Licence | Notes |
|---|---|---|---|
| Roads, buildings, POIs, landmarks, bus stops, signals, railways, bridges, roundabouts, water, land use, boundaries | OpenStreetMap | **ODbL** — attribution "© OpenStreetMap contributors"; the game is a *Produced Work* (notice required, already shown in the start menu) | Geofabrik "southern-zone" India PBF (whole metro, offline) or Overpass (small areas / updates) |
| Elevation | SRTM 1″ (NASA, public domain) ✅ ; optional Copernicus GLO-30 | PD / Copernicus licence (free, attribution) | 30 m; upsampled to 4 m with bicubic + road carving |
| Land cover (vegetation, farmland, built-up) | ESA WorldCover 10 m | CC-BY 4.0 | fills gaps in OSM land use |
| Satellite imagery | Esri / Google / Bing etc. | **reference only** | used by humans to check alignment / tree cover; never shipped, never traced into the dataset unless the provider permits it |

All downloads are made once into `mapdata/cbe/<YYYY-MM-DD>/` and recorded in `mapdata/cbe/SOURCES.md`
(URL, date, licence, checksum). **New downloads and new Python packages are only fetched after the user
approves** (project rule).

## 3. OSM extraction procedure

1. **Boundary** (`config/city.yaml → boundary`): one of
   - `osm_relation: <id>` — e.g. Coimbatore Municipal Corporation (admin_level 8) or the Local Planning Area;
   - `geojson: config/cbe_boundary.geojson` — hand-drawn polygon;
   - `circle: {lat, lon, radius_m}` — quick tests (today's 1.3 km zone is this).
2. **Extract**: Geofabrik PBF → `osmium extract -p boundary.geojson` → `cbe.osm.pbf` (fast, offline), or Overpass
   with the boundary polygon for small areas. Overpass query keeps: `highway=*`, `railway=*`, `bridge`, `tunnel`,
   `layer`, `junction=roundabout`, `building=*`, `amenity|shop|tourism|leisure|office`, `natural=water`,
   `waterway=*`, `landuse=*`, `public_transport`, `highway=bus_stop|traffic_signals|crossing`, `railway=level_crossing`.
3. **Parse** (`pyosmium` or the existing JSON reader) into GeoDataFrames: `roads`, `nodes_special`
   (signals, crossings, stops), `buildings`, `pois`, `water`, `landuse`, `rail`.
4. **Project**: WGS-84 → **UTM zone 43N (EPSG:32643)** with `pyproj`; game coordinates
   `x = E − E0`, `z = −(N − N0)`, `y = elevation` with the origin at Gandhipuram (11.0183 N, 76.9678 E) —
   the same orientation the game uses now (today's `local_xz` is an equirectangular approximation; UTM removes
   its few-metre drift across a 30 km city).

## 4. Python GIS processing (tools/citygen/)

Dependencies (to approve before installing): `pyproj`, `shapely>=2`, `geopandas`, `pyosmium`, `numpy` ✅,
`scipy` (spline / interpolation), `rasterio` (DEM I/O), `networkx` (graph checks), `pyyaml`.

Stage contracts (each reads the previous cache, writes `build/cbe/cache/<stage>.parquet|.npz`):

| Stage | Does | Reuses |
|---|---|---|
| 03 clean | drop `area=yes` highways, merge duplicate nodes (< 0.5 m), split ways at shared nodes, snap dangling ends < 15 m, prune edge stubs, link islands | `towns._repair_network`, `_street_graph` |
| 04 classify | road class + attributes from config and tags (§5) | `towns.WIDTH` → config |
| 05 graph | nodes (junction / end / boundary / route), edges with geometry, `oneway`, `lanes`, `layer`; junction clusters | `road_graph.gd` model |
| 06 geometry | centreline splines, offsets, junction polygons, roundabouts, bridge decks (§6, §7) | `towns.gd _corners`, `_junctions` |
| 07 terrain | DEM resample, carve roads, sink under roads, water surfaces (§8) | `compile_drive_map`, `sink_under_roads` |
| 09 buildings | heights, typology, kit variant, landmark replacement (§9) | `towns._building`, `_plan_kit` |

## 5. Road classification system

`config/roads.yaml` — one entry per class; OSM tags override where present
(`lanes`, `width`, `oneway`, `sidewalk`, `surface`, `lit`, `maxspeed`, `bridge`, `tunnel`, `layer`, `junction`).

| Class | Width m | Lanes | Sidewalk m | Shoulder m | Marking | Speed km/h | Lights / 100 m | Traffic weight | Material |
|---|---|---|---|---|---|---|---|---|---|
| MOTORWAY | 14.0 | 4 (2+2), divider | 0 | 2.5 | solid edges, dashed lanes | 100 | 2 | 1.0 | asphalt_new |
| TRUNK (NH) | 10.5 | 2–4 | 2.0 | 1.5 | edge + centre dashed / median | 80 | 3 | 1.0 | asphalt |
| PRIMARY | 9.0 | 2 | 2.0 | 0.5 | centre dashed, zebra at junctions | 60 | 3 | 0.8 | asphalt |
| SECONDARY | 7.5 | 2 | 1.8 | 0.5 | centre dashed | 50 | 2 | 0.6 | asphalt |
| TERTIARY | 6.5 | 2 | 1.5 | 0.3 | centre dashed (sparse) | 40 | 1.5 | 0.45 | asphalt_worn |
| RESIDENTIAL | 5.0 | 1–2 | 0 (verge) | 0.8 dirt | none | 30 | 1 | 0.25 | asphalt_patched |
| SERVICE | 4.0 | 1 | 0 | 0.5 | none | 20 | 0.5 | 0.1 | concrete |
| LIVING_STREET | 4.5 | 1 | 0 | 0 | none | 15 | 1 | 0.1 | concrete_pavers |
| UNCLASSIFIED | 5.5 | 2 | 0 | 0.8 | none | 40 | 0.5 | 0.2 | asphalt_worn |
| TRACK | 3.0 | 1 | 0 | 0 | none | 15 | 0 | 0.02 | gravel / red_soil |
| FOOTWAY | 2.0 | — | — | — | — | walk | 1 | peds only | paving |

Indian specifics: keep-left lanes, yellow/black kerb painting on main roads, zebra crossings near schools and
junctions, speed breakers (OSM `traffic_calming=bump` + rules near schools / junctions on residential roads).

## 6. Procedural road generation

For every edge (way segment between graph nodes):
1. **Centreline:** projected points → remove spikes (< 1 m zigzags) → Catmull-Rom spline resampled every 2 m
   (curvature-adaptive: 0.5 m in bends with radius < 30 m). Heights from the terrain profile, smoothed with a
   grade limit by class (≤ 8% main, ≤ 15% residential) — today's `_settle_streets` logic.
2. **Cross-section** from the class profile: carriageway (lanes × lane width, or OSM width), optional median,
   kerb (0.15 m high, painted on main roads), drain, sidewalk (raised 0.15 m) or dirt shoulder.
3. **Mesh:** strips along the spline per cross-section band (asphalt, kerb, drain, pavement) with UVs in metres;
   trimmed back at each end by the junction set-back from §7 so arms meet the junction polygon exactly.
4. **Markings:** generated as thin decal strips from the lane layout (edge lines, centre dashes, lane dividers,
   stop lines, zebras, arrows) — kept off junction interiors.
5. **One-way / multi-lane:** lanes from `lanes`, `lanes:forward|backward`, `oneway`; dual carriageways (two OSM
   ways ~10–20 m apart, opposite one-ways) are detected and given a median between them.
6. **Bridges / flyovers** (`bridge=yes` / `layer>0`): the deck follows the way at `max(ground, crossing road
   + 5.5 m clearance)` for layer ≥ 1, with ramps graded ≤ 6% back down to the ground nodes; piers (instanced)
   every 25 m, parapets, expansion joints; terrain is **not** carved under the deck. Rail bridges and river
   bridges likewise. **Tunnels** (rare in CBE): deck below terrain with a portal mesh; terrain kept above.
7. **Railway crossings** (`railway=level_crossing`): flat crossing panel, booms + signal posts (props), rails
   continue across.
8. **Gap-free joins:** every edge end lands on a node; the node's junction polygon (§7) owns the overlap, so there
   are no seams (the current game already reaches 0 gaps / 100% reachability on its area).

## 7. Intersection generation algorithm

For each graph node of degree ≥ 3 (and clusters, see 5):
1. **Cluster:** merge nodes within `max(12 m, widest arm)` into one junction (dual carriageways and
   slightly-misaligned OSM nodes become one junction).
2. **Arms:** for each incident edge: direction at the node (first 6 m of the spline), half-width, kerb profile.
3. **Set-back:** for neighbouring arms A, B (sorted by angle), intersect A's left kerb line with B's right kerb
   line; the arm is trimmed back to the farthest such intersection + kerb radius
   (radius by class: 6 m main, 3 m residential).
4. **Corner fillets:** a quadratic Bézier between the trimmed kerb points of A and B (today's `_corner_curve`),
   giving the kerb, drain and pavement corner sweeps.
5. **Surface:** polygon = trimmed arm ends + fillets → triangulated, raised to the plane fitted to arm heights
   (`_fit_plane`), carved flat into terrain.
6. **Markings / control:** stop lines on minor arms, zebras on main arms, signals if `highway=traffic_signals`
   or two main roads meet (§11), else give-way.
7. **Roundabouts** (`junction=roundabout` ways, or `highway=mini_roundabout` nodes): the ring is built as a one-way
   circulating road; the inside polygon becomes a raised island (grass, statue / fountain props — the game's
   existing `_islands` / statue logic); approach arms get splitter islands; mini-roundabouts get a painted dome.
8. **T-junctions / Y-junctions / skew:** same algorithm; acute wedges (< 35°) become kerbed traffic islands
   (already implemented as `_islands`).

## 8. Terrain generation

1. DEM (SRTM, optionally Copernicus GLO-30) clipped to boundary + 2 km margin; void-fill; resample to a **4 m grid**
   (bicubic) — the game's current `near.bin` resolution.
2. **Carving:** for every road / junction / parking lot polygon, set ground to surface − clearance and taper
   15 cm/m outwards (today's `sink_under_roads`); embankments / cuttings where grade limits force it.
3. **Water:** OSM `natural=water` polygons (Ukkadam, Valankulam, Singanallur, Kurichi lakes …) and `waterway=river`
   (Noyyal) → water surfaces at a smoothed level, banks lowered 1.5 m; rivers get a channel along their line.
4. **Hills:** the DEM already carries the western ghats edge (Marudhamalai, Velliangiri foothills); far terrain
   beyond the boundary on a 48 m grid (today's `far.bin`).
5. **Chunked output:** per 256 m chunk a 65×65 float16 height tile (shared edges), plus `proximity` (distance to
   road, keeps props off it) and land-cover class tiles.
6. **Vegetation / land use:** OSM `landuse` (residential, commercial, farmland, orchard, meadow, forest) + WorldCover
   fill → per-chunk scatter rules (coconut palms along farmland, neem / rain trees on streets, tea / scrub on the
   hills) as MultiMesh instances; trees kept off roads by the proximity tile.

## 9. Building generation

1. **Footprints:** OSM `building=*` (REAL). Where a block between real streets has none but land use is
   residential / commercial, fill along street frontage (GENERATED, `gen:block_fill`) — today's block fill.
2. **Height:** `building:levels` / `height` if tagged; else rules by land use, street class and area
   (commercial main road 3–5 floors, residential 1–3, apartments 4–8 near arterial roads).
3. **Typology:** footprint rectangularity, size, floors, shop tags, street class →
   city_house / apartment / shop_house / bungalow / hotel / (later) temple, school, office block, mall.
   Tamil Nadu cues per typology: shop shutters and signboards on commercial frontage, terraces with water tanks,
   compound walls with gates, parapets, sunshades (chajjas), kolam-friendly front steps.
4. **Placement:** min-area rectangle fit, facing the nearest street, scaled into the footprint (today's
   `_plan_kit`); non-rectangular footprints → extruded facade-shader blocks.
5. **Detail by distance:** designed kit within ~240 m, facade-shader blocks to ~1.4 km, merged chunk proxy beyond.
6. **Landmark layer:** `config/landmarks.yaml` lists OSM ids or polygons replaced by dedicated assets (§ list in
   12.4), each with an asset path, LOD set and a footprint mask that removes generated buildings / props there.
7. **Lots and frontage:** driveways to the street, compound walls, parking lots, petrol forecourts — as today.

## 10. Street furniture & city dressing

Rules per road class and land use, placed along offsets of the road spline (instanced, per chunk):
utility poles + sagging wires (every ~32 m), streetlights by class density, bus-stop shelters at `highway=bus_stop`,
traffic signs (Indian standard shapes, generic — no brands), billboards on arterial roads (generic art),
street vendors / carts near markets and bus stands, tea stalls, auto stands near stations, trees in the verge,
speed breakers, signal heads, petrol forecourts at `amenity=fuel` (unbranded), parking lots. Every prop carries
`src = gen:<rule>` unless it comes from an OSM node (bus stops, signals, fuel → REAL position).

## 11. Traffic graph generation

1. **Road graph** (exists): nodes / edges with class, oneway, speed.
2. **Lane graph:** for each edge and direction, lane centrelines (offset splines, keep-left). At each junction,
   **connectors** from incoming lanes to outgoing lanes allowed by turn rules (no U-turns except at gaps in
   medians, OSM `turn:lanes`, one-way exits, `restriction` relations) as Bézier curves through the junction polygon.
3. **Control:** signal groups at signalised junctions (phases by arm, 30–60 s cycle, all-red 2 s),
   give-way / stop elsewhere; roundabouts yield-to-circulating.
4. **Spawning:** spawn points on lanes outside the player's view; vehicle mix and density from
   `config/traffic.yaml` by road class × time of day (07–10 & 17–20 rush ×1.8, night ×0.3) × weekday/weekend ×
   area (market, bus stand, IT corridor) × weather (rain: −30% density, −25% speed, longer gaps).
5. **Destinations:** random lane-graph routes (A* on travel time) for through traffic; local trips for autos /
   two-wheelers; buses follow bus-stop sequences.
6. **Runtime:** only lanes in loaded chunks are active; far vehicles despawn; today's `town_traffic.gd`
   behaviours (gaps, slowing into junctions, stopping for the player) move onto the lane graph.

## 12. Pedestrian navigation

1. **Walkable polygons:** sidewalks, footways, crossings (zebras and junction corners), plazas around POIs,
   bus-stop platforms, station forecourts, parking lots; road carriageways only at crossings.
2. **Per-chunk navmesh:** `NavigationRegion3D` per chunk baked from those polygons at load time (cheap — they are
   flat strips), linked across chunk edges with `NavigationLink3D`.
3. **Attractors:** POIs weighted by type and hour (schools 8–9/15–16, markets morning, temples evening, bus stands
   all day, offices 9–18); pedestrians path between attractors, cross at crossings, wait at signals; rain → fewer,
   faster, umbrellas.
4. **Density** from land use + POIs, culled by distance; today's `pedestrians.gd` behaviours are kept.

## 13. City chunk / streaming system

- **Grid:** 256 m chunks named `CBE_<col>_<row>` (index in `build/cbe/index.json`: bounds, file list, hash,
  real/generated counts). Metro 30 km × 30 km ≈ 13,700 chunks; most are light.
- **Chunk content:** terrain tile, road / junction / bridge meshes (pre-built by the pipeline or generated on load),
  building placements (variant + transform), props (instance lists), vegetation, nav polygons, lane segments,
  traffic / pedestrian spawn points, collision.
- **Rings around the player (8 GB M1 budget):**
  - ring 0–1 (≈ 768 m square): full detail — designed buildings, props, traffic, pedestrians, collision;
  - ring 2–4: buildings as facade blocks, no props / peds, simplified collision off;
  - beyond: per-district merged proxy meshes + far terrain (48 m) + skyline impostors.
- **Loading:** `ResourceLoader.load_threaded_request` / `WorkerThreadPool` for parsing and mesh building, a frame
  budget (≤ 4 ms/frame) for instancing into the scene, hysteresis so chunks don't thrash at borders; nothing
  global loads at start except the index, far terrain and the road graph spine (for GPS).
- **Save / sim state** (parked cars, shop state) lives outside chunks keyed by chunk id.

## 14. Blender import / export pipeline

- **Asset library (Blender, our own scripts — no downloaded asset packs):** `tools/buildings.py` (kit),
  `tools/carbody.py` / `carcabin.py` (vehicles), `tools/people.py`, props (`tools/props.py`, new), landmarks
  (`tools/landmarks/<name>.py`, new). All export glTF (`.glb`) with LOD0/1/2 (Decimate / remesh) and collision
  proxies (`-col` suffix).
- **Optional chunk baking:** `tools/citygen/bake_chunk.py` (headless Blender) merges a chunk's static meshes per
  material and writes `CBE_x_y.glb` + LOD proxies — used for the far rings; near rings are generated in Godot.
- **Coordinate convention:** Blender (x, y, z) ↔ Godot (x, z, −y); the game's existing rule.
- **Previews:** every asset and chunk can be rendered for review before it goes into the game (project rule:
  show the Blender design, get approval, then integrate).

## 15. REAL vs GENERATED content

Every output record carries `src`:
- `osm:way/<id>`, `osm:node/<id>`, `osm:relation/<id>` — REAL geometry;
- `dem:srtm` / `dem:glo30` / `lc:worldcover` — REAL raster-derived;
- `gen:<rule>` — GENERATED (block fill, heights by rule, props, vegetation scatter, invented lanes).
The validator writes `build/cbe/report.md` (per chunk: % real roads, real buildings, generated buildings, etc.) and
the in-game F3 debug view colours roads / buildings by provenance (green = OSM, orange = generated).
**Roads are never invented where OSM has data**; the only generated road pieces are junction surfaces,
connectors and repair links ≤ 35 m (each tagged `gen:repair`).

## 16. Unreal Engine 5 implementation (optional target)

Engine-neutral outputs → UE5 via a Python importer (Editor Scripting): one World Partition cell per 256 m chunk
(or 512 m), static meshes from the chunk glTFs with **Nanite** on buildings / landmarks, **HLOD** layers built from
chunk proxies, **PCG** graphs for vegetation / props from the instance lists, Landscape from the height tiles,
ZoneGraph / Mass for traffic and crowds from the lane graph and nav polygons, Chaos Vehicles for driving.
Requires a Windows PC with an RTX-class GPU; not planned on the current machine.

## 17. Godot 4 implementation (primary)

- `scripts/city/city_streamer.gd` — rings, threaded load / unload, frame budget.
- `scripts/city/chunk.gd` — builds a chunk from `chunk.json` + binaries: terrain mesh (from the height tile),
  roads (reuse `towns.gd` strip / junction builders, split per chunk), buildings (`building_kit.gd` MultiMesh
  per variant + facade blocks), props / vegetation MultiMeshes, `StaticBody3D` collision, `NavigationRegion3D`,
  lane segments registered with the traffic manager.
- `scripts/city/lane_graph.gd`, `signals.gd` — lane graph and signal phases; `town_traffic.gd` moves onto it.
- **Visibility ranges** with fade on every chunk node; **OccluderInstance3D** per chunk from building boxes
  (occlusion culling); **LOD** via imported mesh LODs (`lod_bias`); shadows only in ring 0.
- `road_graph.gd` stays the single road truth (GPS, minimap, surface grip), loaded globally but light (spine + edges).

## 18. Optimisation strategy

| Budget (M1, 8 GB, 1080p-equivalent with FSR 2) | Target |
|---|---|
| Frame | 16.6 ms (60 fps) plains / 33 ms min |
| Draw calls | < 2,500 |
| Triangles on screen | < 3 M |
| Loaded chunks | ~100 (ring 0–4) |
| RAM for world | < 2.5 GB |
| Streaming work | ≤ 4 ms / frame |

Techniques: MultiMesh / GPU instancing for every repeated asset; one-material kit buildings with texture arrays
(already); texture atlases for props and signs; merged static meshes per chunk material; LODs + visibility-range
fades; occlusion culling; shadows near only; traffic / pedestrian LOD (far = no animation, despawn); half-res SSAO /
SSIL (already); avoid unique high-poly meshes — landmarks are the only bespoke models.

## 19. Folder structure

```
mist-village/
  config/
    city.yaml            boundary, origin, chunk size, rings, CRS
    roads.yaml           class profiles (§5), tag overrides
    buildings.yaml       height rules, typology rules, styles by area
    landmarks.yaml       landmark ids → assets
    traffic.yaml         densities × time × area × weather, vehicle mix
    pedestrians.yaml     attractors, densities, schedules
    props.yaml           furniture rules
  mapdata/cbe/<date>/    raw downloads (gitignored) + SOURCES.md
  tools/citygen/         stage modules 01…15, run.py, lib/ (projection, spline, polygon, io)
  tools/                 existing Blender asset scripts (+ props.py, landmarks/)
  build/cbe/             cache/, chunks/CBE_x_y/, index.json, report.md   (gitignored; or Git LFS)
  godot/assets/city/     what the game ships: index + chunks (generated), landmark / prop glbs
  godot/scripts/city/    city_streamer.gd, chunk.gd, lane_graph.gd, signals.gd
  docs/                  this document, GAME_DESIGN.md, GAME_BRIEF.md
```

## 20. Configuration files (examples)

```yaml
# config/city.yaml
name: Coimbatore
crs: EPSG:32643
origin: {lat: 11.0183, lon: 76.9678}        # Gandhipuram
boundary: {osm_relation: null, geojson: config/cbe_boundary.geojson, circle: null}
margin_m: 2000
chunk_m: 256
rings: {full: 1, blocks: 4, proxy: 12}
dem: [srtm_1s]                               # add glo30 when approved
landcover: worldcover_2021
```

```yaml
# config/roads.yaml (excerpt)
primary:
  width: 9.0
  lanes: 2
  sidewalk: 2.0
  shoulder: 0.5
  kerb: {height: 0.15, paint: yellow_black}
  marking: {centre: dashed, edge: solid, zebra_at_junctions: true}
  speed: 60
  lights_per_100m: 3
  traffic_weight: 0.8
  material: asphalt
tag_overrides: [lanes, width, oneway, sidewalk, surface, lit, maxspeed, bridge, layer, junction]
```

```yaml
# config/landmarks.yaml (excerpt — order = build priority)
- {name: Coimbatore Junction railway station, osm: way/<id>, asset: landmarks/cbe_junction.glb}
- {name: Gandhipuram central bus stand,       osm: way/<id>, asset: landmarks/gandhipuram_bus_stand.glb}
- {name: Ukkadam bus stand and lake front,     osm: way/<id>, asset: landmarks/ukkadam.glb}
- {name: Race Course walking track,            osm: way/<id>, asset: landmarks/race_course.glb}
- {name: Coimbatore International Airport,     osm: way/<id>, asset: landmarks/airport.glb}
- {name: Gandhipuram flyover,                  osm: way/<id>, asset: generated_bridge}   # from §6.6
# + RS Puram commercial streets, major hospitals, colleges, temples (OSM ids filled in at build time)
```
Landmarks are modelled from our own Blender scripts as recognisable *forms*, without logos or brand marks.

## 21. Updating the map when OSM changes

1. `python tools/citygen/run.py fetch --date today` (new extract into `mapdata/cbe/<date>/`; approval needed).
2. `run.py diff --from <old> --to <new>` → list of changed OSM ids → affected chunks (by geometry bounds).
3. `run.py build --chunks changed` → only those chunks rebuild (each chunk stores the hash of its inputs + config).
4. `run.py validate` → connectivity (100% reachable target), gaps, terrain pokes, real/generated report.
5. Re-export landmarks only if their OSM footprint moved; commit `godot/assets/city/` (or LFS) and the new
   `SOURCES.md` entry; the start-menu attribution stays.

---

## Delivery plan (step by step, each step shown before it goes into the game)

| Step | Deliverable | Depends on |
|---|---|---|
| 1 | `config/` files + `tools/citygen` skeleton; UTM projection; boundary from a circle (4 km) → metro polygon | approval to install pyproj / shapely |
| 2 | Metro extract (Geofabrik PBF + osmium clip) and classification report (counts by class, real vs generated) | download approval |
| 3 | Chunking + `city_streamer.gd` with today's road / building builders per chunk (streaming works) | 1–2 |
| 4 | Junction algorithm v2 (clusters, set-backs) + roundabouts | 3 |
| 5 | Bridges / flyovers + railway crossings | 4 |
| 6 | Water bodies + land use + vegetation | 3 |
| 7 | Lane graph + signals; traffic moves onto it | 4 |
| 8 | Pedestrian nav regions + attractors | 3 |
| 9 | Landmarks, one at a time, each reviewed in Blender first | 3 |
| 10 | Performance pass to the §18 budgets; validation report | all |

Risks: metro data volume on an 8 GB machine (mitigated by offline chunk building and streaming); OSM gaps in
lanes / building heights (filled by rules, marked GENERATED); disk space (≈1.4 GB free now — the metro extract and
build cache need ~5–10 GB; free space first).
