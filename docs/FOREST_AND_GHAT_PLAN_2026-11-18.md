# Deep forest and the Kotagiri ghat road: inspection and plan (18 November 2026)

The forest brief's first step: what the map and terrain have now. Nothing was changed for this. It was read from the
code and the map data only, because the disk is nearly full (about 180 MB free), so no game runs were made.

## 1. What exists

| Part | Now (read) |
|---|---|
| The drive (`drive.tscn`, `drive_game.gd`) | "The Road Up": Coimbatore → the plains → Mettupalayam → the forest check post → nine hairpins → the clouds → the Kotagiri tea gardens → The Mist Village gate, from the real road (`assets/drive/real_route.json`, `map.json`; `route.gd`) |
| Terrain (`terrain.gd`) | A 4 m heightfield along the road corridor, carved under the road (red-soil cuttings uphill, embankments downhill), a 64 m backdrop to the horizon; 512 m super-chunks, one mesh and collider each |
| Road (`road.gd`, `details.gd`) | Asphalt, red-earth shoulders, stone retaining walls on cuttings, black-and-yellow parapets on drops and hairpins, the Bhavani bridge and river, milestones, signs, chevron boards on sharp bends, road studs, potholes, delineators, rain-soaked tarmac |
| Forest (`props.gd` `_forest`) | Foothills: eucalyptus, shola evergreen, silver oak (3 a step, 9–160 m off the road). Ghat: four shola evergreens, two silver oaks, eucalyptus (3 a step, 9–200 m). Mist zone: sparse. Kotagiri: cypress. Under them shrubs and ferns within 30 m. Beyond the corridor, 6 000 far canopy cards on the slopes. Trunk colliders only within 26 m of the road |
| Tea (`props.gd` `_tea`) | Contour-clipped tea hedges with silver-oak shade trees from the mist zone to Kotagiri |
| Life | Cows on the verges, monkeys on the ghat parapets, elephants at a crossing, a tea stall above the clouds |
| City trees (`city_streamer.gd`) | Street and yard trees: neem (two), rain tree, gulmohar, coconut palm, from `tools/vegetation.py` and `tools/trees_tn.py` (our own procedural trees) |
| Tree maker (`tools/vegetation.py`) | Procedural: buttressed trunks, recursive branches, leaf-spray crowns from a painted leaf atlas, bushes, grass tufts, palms. New species can be added here: our own designs, no downloads |

**What the 10 November ghat shots show** (`previews/ghat_2026-11-10`): the ghat reads as open grassy hills with
scattered round-crowned trees, not forest. The trees are few, similar in shape, and stand apart; the ground is bare
grass to the horizon.

## 2. Coimbatore's real green areas (OpenStreetMap, `build/cbe/cache/osm.gpkg`)

| Area | Size | Where (game x, z, about) | Use |
|---|---|---|---|
| TNAU Botanical Garden (and the TNAU campus) | 8.7 ha | (−3 930, 160), Lawley Road side | **First city forest pocket**: a real, heavily wooded campus |
| Wood, near Race Course / the centre | 8.1 ha | (−490, 1 500) | A small woodland pocket |
| Bharathi Park | 3.6 ha | (−2 190, −260) | A shaded park |
| Woods to the north (Thudiyalur side) | 3–19 ha | (260, −9 130), (−90, −9 020) | Edge-of-town woodland |
| Scrub, Cheran Maa Nagar | 55 ha | (5 900, −3 060) | Dry scrub with thorn trees: a different look |
| Forest and wood near the Nilgiri foothills | 540 ha, 216 ha | ~30 km north (Mettupalayam side) | Already on the drive's corridor: the foothill forest there |

Only real green areas get forest: the rest of the city stays a city, as the brief asks.

## 3. Plan

**Stage 1, one forest section and one mountain-road section** (what the brief asks first):
1. **New tree species of our own** in `tools/vegetation.py`: banyan (wide crown, aerial roots dropping from the
   limbs), tamarind (dense fine canopy, dark), bamboo clumps, plus a creeper-covered variant of the shola tree. Two
   or three seeds each for variety, near and far versions (LOD), the leaf atlas extended.
2. **City pocket: the TNAU Botanical Garden**: canopy trees by layer (tall, middle, shrubs, ferns, ground cover)
   inside its real outline only, never on roads or paths (the roads' and paths' buffers kept clear); MultiMesh per
   species per tile (the city's streaming), trunk colliders only near paths.
3. **Ghat section: the first three hairpins**: the shola forest made dense and layered on both sides (canopy, under
   storey, ferns, mossy rocks, fallen leaves on the verge), canopy gaps, rock faces on the cuttings, and the far
   slopes as continuous forest (more and varied far cards), the valley views kept open at the parapets. Nothing within
   the road's clearance; colliders only on trunks near the road.
4. **Measure** at fixed cameras before and after (the drive's own shot list and the city's `--gfxaudit`), morning,
   afternoon, evening and night; FPS, CPU frame time, memory (GPU time isn't readable on Metal).

**Stage 2, after your review of stage 1:** the rest of the route by stage (leaving Coimbatore, the countryside,
the full ghat, the Kotagiri approach with tea and mist), forest audio, forest life, the other city pockets.

## 4. Blockers and questions

- **Disk:** about 180 MB free. Building trees in Blender, importing them into Godot, and the test runs all need
  space. Stage 1 needs about 2 GB to work safely.
- **The resort (section 7 of the brief):** you said today not to touch the resort for now. Stage 1 doesn't need
  it; I'll leave the resort's surroundings until you say.

## 5. Results, stage 1 (18–19 November): tested in the game

All pictures are the game's own, from fixed cameras that are the same every run (`--forestshots` in the city,
`--ghatshots` on the drive; `--noforest`, `--noghatforest`, `--nofarground`, `--oldnight` give the "before"), at
07:15, 13:00, 18:10 and 21:30 (and 05:30 for night driving), on the M1 MacBook Air (8 GB), Low preset, 1600 × 900.
Images: `docs/shots/forest/`. Raw captures: `user://forest_ab3` … `forest_ab7`.

**Frame-rate caveat.** Frame rates were taken while other sessions were also using the machine (a load average of
12–18 on 8 cores during round 7), so they swing widely between runs at the same view. The triangle counts don't
depend on load and are the reliable measure of what the forest costs. A clean frame-rate pass on an idle machine
is still to do.

### P0: the grey "void" under and around the city

Reproduced and explained before changing anything:
- **At ground level, it was the test camera, not the world.** It was placed before the ground's collision had
  loaded, at a fixed fallback height below the real ground. With the camera waiting for a real height (logged:
  437–441 m at all three views), the void disappeared from every ground-level shot.
- **From above, it is real.** Low and Medium stream a 5 × 5 block of 256 m tiles (about 640 m each way). Only 8 894
  of the 32 732 cells in the map's bounding box have a tile at all. Beyond the loaded block there is no geometry,
  and the procedural sky's grey lower half shows through. The camera's far clip (4 000 m) is not the cause.
- **Fix:** `FarGround`, one plane to the horizon drawn with the city's ground shader, kept 2.5 m under the lowest
  loaded tile (`city_streamer.gd` `_far_ground_follow`, `--nofarground` to compare). Verified from 140 m up and at
  ground level, at 13:00 and 21:30 (`world_edge_far_ground.jpg`): the void is gone, the ground-level view is
  unchanged, and the cost is one plane.
- **Limitation:** the far plain is flat, with no distant buildings or hills on it. A believable horizon would also
  need the western hills (the Maruthamalai and Western Ghats skyline). That is a follow-up.

### P1: night driving on the ghat

- **Before (`--oldnight`):** an ambient of 0.05, a 0.07 moon and a black sky. Only the headlights' 30° beams lit
  anything, the chevrons were plain paint, and the road edges and the bend were barely visible.
- **After:**
  - a cool moonlit ambient floor blended in as the sky darkens (0.4 at full night), a 0.16 blue moon, and the night
    sky at 0.3 of its daytime strength, so the tree line shows against it;
  - headlight main beams widened from 30° to 36°, plus a short, wide low-beam fill (32 m, 62°) that lights the road
    edges and the inside of bends;
  - chevron boards made retroreflective, like the road studs, so they blaze in your own headlights;
  - the haze catches the low sun at dawn and dusk.
- **Tested:** the jeep on its lane with its headlights on, from the chase-camera position, at the bend before
  hairpin 1 and on a forest straight, at 21:30 and 05:30, plus headlights off.
  - Lights on: the chevrons, road studs, edge and centre lines, parapets, delineator posts and the roadside trees
    are clearly visible.
  - Lights off: faint road edges by moonlight, and the game prompts "press L". It is still clearly night, and the
    forest interior stays dark.
  - Pictures: `night_driving_before_after.jpg`, `night_forest_straight_headlights.jpg`.
- **Not done:** the parapets themselves aren't reflective, and there are no reflectors on the guardrails.

### P2: forest terrain and vegetation

- **City, the TNAU Botanical Garden:** layered woodland of banyan, tamarind, neem, rain tree, gulmohar, bamboo and
  palms, in groves, on a leaf-litter floor (`tnau_round3.jpg`, `tnau_round3_vs_4.jpg`).
- **Ghat, the first three hairpins:**
  - dense shola canopy with silver oak, eucalyptus, tree ferns and bamboo, groves and clearings on the slopes, and
    an under-storey of ferns, shrubs, grass and flowers near the road;
  - the forest floor changed from the orange earth texture to humus, moss, ground cover and leaf litter mixed at
    three scales, plus root and twig streaks;
  - oversized trees capped at 1.25× by the road and 1.35× in the groves, with heights still varied;
  - the shola trees' low-poly versions kept beyond 110 m;
  - nothing on the road, and the downhill side near the road kept open for the valley views.
- **Honest state:** the floor still reads mostly as a green-and-brown patchwork (`ghat_floor_round6_vs_7.jpg`).
  Rocks, roots and fallen-leaf detail on the ground itself, and less repetitive round crowns among the resort's
  shola models, are still to do.

### P3: cost (triangles a frame; frame rate with the caveat above)

| Place | Before | After | Notes |
|---|---|---|---|
| Ghat, five fixed views | 0.8–1.5 M | 1.4–2.5 M (night 1.4–1.9 M) | Round 3: frame rate about the same as before; later runs loaded |
| Ghat, chase view at the bend, by day | — | 3.4 M | The heaviest view |
| City, garden from above | 2.2–2.5 M | 2.9–3.1 M | After the crown cards (was 4.4–5.2 M) |
| City, garden at eye level | 2.3–2.7 M | 5.0–5.7 M | Still heavy: full-detail trees within 28 m |
| Video memory | about 1.6 GB on the drive, 2.0 GB in the city | +20–60 MB | |
| Static memory | | No measurable change | |

The streaming, the roads and the map data are unchanged, and NPCs and traffic run as before. The forest pockets
stream with the city tiles; the ghat forest is built once with the drive.

### What's left

- A clean frame-rate pass on an idle machine.
- The city's eye-level cost: fewer full-detail trees, or a lighter near version.
- Ground detail: rocks, roots and fallen-leaf decals in the forest floor.
- Shape variety beyond the resort's shola models.
- Reflective parapets and guardrails.
- The western hills on the city horizon.
- The rest of the route (stage 2).

## 6. The city's open ground filled (24 November; the mountain and ghat left as they were)

The user asked for the empty ground inside the city to be thick tree cover: "not in mountain, it should be in city".

**Pockets.** `tools/citygen/forest_pockets.py` now plants every OpenStreetMap green area in the city's bounds, 3 000 m²
or larger: 66 pockets, made up of woods, forest, scrub, parks, gardens, meadows and grassland. Woods and forest get
dense canopy, scrub a lower thorny mix, and parks a lighter canopy.

**The fill.** `city_streamer.gd` `_fill_mask` builds a keep-clear map of each tile at 2 m resolution, in the loading
worker. Everything not on the map is planted with a dense mix (banyan, tamarind, neem, rain tree, bamboo, a few
gulmohar and palms) over shrubs and a leaf-litter floor. The keep-clear map holds:
- roads (width + 3 m, flyovers included);
- footpaths (+1.5 m) and junctions (+3 m);
- buildings (+4 m: fronts, doors, steps);
- paved yards and parking, and compound walls (+1.5 m);
- street props (+3 m), and parked vehicles, stalls, carts, bus stops and street people (+4 m);
- landmark pads (+6 m) and landmarks' clear outlines, such as a bunk's lot and its forecourt (+8 m);
- 103 tanks and lakes (+8 m of shore);
- 63 story places from `slice.json` and `prologue.json` (25 m).

The city's forest has no trunk colliders, so nothing can block a walker, a car or traffic. `--nocityfill`,
`--filldebug` (per-tile free ground and trees planted) and `--fillprobe=x,z` (which rule keeps a point clear) are
the switches for testing.

- **Kept clear on purpose:** the two open lots first chosen as test views, at Ganapathy (23 m from Karthik's home)
  and Gandhipuram (9 m from Raghavan's office), lie inside story places' clear zones.
- **How much is planted:** typical tiles have 3–29 % of their ground free after the rules and get about 90–860 trees.

**The far ground.** Beyond the streamed tiles it is now painted as forest canopy, with a ring of about 4 800 cheap
canopy cards (96 triangles each) out to 2.6 km on a fixed world grid (`--nofarforest`).

**Measured** on the M1, Low preset, from fixed cameras, before (`--noforest --nocityfill --nofarforest`) and after
(`docs/shots/forest/city_fill_before_after.jpg`):

| View | Draw calls | Triangles | Static memory |
|---|---|---|---|
| Fill tile A, aerial | 1 760 → 3 390 | 1.5 → 3.4 M | 348 → 430 MB |
| Fill tile B, aerial | 1 660 → 2 830 | 2.3 → 4.6 M | 317 → 385 MB |
| Fill tile C, aerial | 2 040 → 2 570 | 2.1 → 3.2 M | 372 → 412 MB |
| Wood near the centre | 1 260 → 3 070 | 2.0 → 5.9 M | 329 → 416 MB |
| West edge, 140 m up | 850 → 2 330 | 1.0 → 3.0 M | 321 → 414 MB |

The "after" figures are with 64 m forest cells. 32 m cells had cost 4 000–5 500 draws.

Frame rates were measured with other sessions loading the machine (CPU frame times of 50–200 ms either way), so they
aren't reliable; the counts above are. Video memory rose by 40–50 MB.

**Still to do:**
- bring the draw calls down further (merging species into one mesh per cell, or fewer shrub kinds);
- a clean frame-rate pass on an idle machine;
- open ground the map doesn't record (lots inside compounds) stays as it is.
