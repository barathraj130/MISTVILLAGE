# Baked contact shading: five-asset test (18 November 2026)

The baking brief: bake only the shading that doesn't depend on the sun (corners, eaves, under canopies, round
steps and doors: where less of the open sky reaches), keep the sun, its shadows and the game's morning-to-night
light dynamic, darken the generated buildings, roads and footpaths cheaply in their shaders, and test five assets
before going further.

## What was done

| Part | How |
|---|---|
| Bake | `tools/bake/bake_ao.py` (Blender, Cycles): ambient occlusion to 1.2 m into a second UV set ("AO", smart UV project: islands of connected faces, so the mesh grows little), 1024–2048 px by area, a white background and 16 px padding (the game's blurred mip levels at a distance must not bleed into the islands), written as glTF occlusion, JPEG. Glass, lamps and emissive parts are left out |
| Originals | Untouched. The baked copy is `NAME_ao.glb` beside the original |
| Loading | `city_streamer.gd` `baked()`: a landmark or room loads its `_ao` copy if there is one; `--noao` loads the originals. `use_baked_ao()` puts the occlusion on UV2 and on ambient light only (`ao_light_affect` 0): Godot's glTF importer ignores the occlusion's texCoord |
| Generated buildings | `building.gdshader` and `building_kit.gdshader`: contact shading at the foot of each wall by height above the building's own base (every building and every tile the same at the same height: no seams between neighbours), window recesses a little darker. Through Godot's AO output: ambient light only |
| Roads | `road_surface.gdshader`: the last 0.7 m by each kerb a little darker (the gutters) |
| Switch | `--noshaderao` turns the shaders' part off (`ao_k` 0), for comparing |
| Footpaths | **Not done**: they use a standard material, not a shader; they'd need one (next step if wanted) |

The test group: the government hospital, The Siruvani Grand, the Kongu Fuels bunk (one model, at five places) and
the showroom's interior were baked. The police station and the showroom's outside are generated buildings, so
they test the shader part.

## Results (M1 MacBook Air, 8 GB, Low preset, 1600 × 900)

Fixed cameras (`--gfxaudit --gfxonly=lm_hospital,lm_hotel,lm_bunk,lm_police`, the same pose every run), at 07:15,
13:00, 18:10 and 21:30, two runs each, everything off (`--noao --noshaderao`) against everything on. Medians of
eight measurements per place (the M1's frame rate varies a lot run to run; Metal reports no GPU time, so CPU time
and frame rate are what can be measured):

| Place | fps off → on | CPU ms off → on | Draw calls | Video memory (MB, peak) | RAM (MB) |
|---|---|---|---|---|---|
| Hospital | 18.6 → 19.3 | 52 → 49 | 2250 → 2280 | 2114 → 2078 | 344 → 348 |
| Siruvani Grand | 18.6 → 19.5 | 49 → 48 | 2922 → 2931 | 2121 → 2083 | 330 → 332 |
| Kongu Fuels | 19.2 → 18.5 | 55 → 49 | 2648 → 2664 | 2129 → 2089 | 348 → 347 |
| Police station street | 17.9 → 19.8 | 50 → 51 | 1786 → 1796 | 2119 → 2082 | 376 → 373 |

**No measurable cost**: every difference is inside the run-to-run noise. Files: hospital 0.3 → 0.9 MB, hotel
0.6 → 1.2 MB, bunk 5.4 → 6.2 MB, showroom room 4.4 → 5.3 MB (each with one AO image, 1024–2048 px).

## Visual (docs/shots/graphics/bake_test_2026-11-18/)

- `before_after_1300.jpg`: the four places at 13:00, off (left) and on (right).
- `bunk_four_hours.jpg`, `police_street_four_hours.jpg`: all four hours.
- `showroom_interior.jpg`: the room, off and on.
- `hospital_facade_fix.jpg`: the first bake (top, wrong), the fixed one (middle), none (bottom).

What it shows: deeper shade under the bunk's canopy and round its kiosk, the hospital's verandah openings and the
hotel's podium recesses, the showroom's stands, desks and wall foot; the generated buildings stand on the ground
(darker feet), windows a little deeper, gutters along the kerbs. No dark patches, seams or wrong shadows were found
in any picture, at any hour, and the sunlit sides and night look as before (the shading is on ambient light only).
The effect is subtle by design.

Problems found and fixed on the way: the importer put the occlusion on a third UV set (fixed: unused UV sets dropped
first); lightmap-packing every face alone nearly tripled the bunk's mesh (fixed: smart UV project); the first bakes
had a black background that the distant mip levels bled into whole facades (fixed: white background, wider padding).

Not in this test: 18:10 is still dark at every place, on or off (the dusk light is the open item from the lighting
step, not the bake).

## Rollback

Delete the `_ao` files (`godot/assets/landmarks/hospital_ao*`, `hotel_grand_ao*`, `godot/assets/world/fuel_bunk_ao*`,
`godot/assets/interiors/room_showroom_ao*`) or run with `--noao`; `--noshaderao` (or `ao_k` 0) for the shader part.

## Expansion (approved; 23 November 2026)

Baked the same way, the 14 other landmarks in `landmarks.json`: the railway station, the central and town bus
stands, both malls (Avinashi Road, Sathy Road), the Collectorate, the clock tower, the church, the stadium, the
temple, CODISSIA, PSG Tech, the private hospital and the airport (each 0.2–5.4 MB, originals untouched). Now all 17
landmark models and the showroom room have `_ao` copies. The footpaths got the shader treatment too:
`footpath.gdshader` (the same pavers, contact shading along both edges; the strip's half width rides in UV2.x),
built from the paver material by `city_streamer.gd`; `--noshaderao` turns it off with the rest.

Checked: each landmark at 13:00 from a fixed camera (`--gfxlm=name[:metres]`), off and on: no dark patches, seams or
wrong shadows on any of them (`landmarks_1_of_2_1300.jpg`, `landmarks_2_of_2_1300.jpg`; the airport and CODISSIA
from farther off, `airport_codissia_far.jpg`); the footpaths keep their pavers and colour, a little darker at the
edges (`footpaths_police_street.jpg`).

Measured again (the same four places and hours, two runs each; everything now baked or shaded). This round ran slower
overall than the first (other changes in the city since), and the medians swing more than any effect:

| Place | fps off → on | CPU ms off → on | Draw calls | Video memory (MB, peak) | RAM (MB) |
|---|---|---|---|---|---|
| Hospital | 8.6 → 13.6 | 111 → 66 | 2168 → 2296 | 2251 → 2133 | 345 → 349 |
| Siruvani Grand | 11.3 → 18.4 | 79 → 53 | 2789 → 2877 | 2217 → 2096 | 331 → 331 |
| Kongu Fuels | 10.2 → 15.6 | 98 → 57 | 2538 → 2611 | 2245 → 2223 | 352 → 353 |
| Police station street | 8.9 → 12.9 | 97 → 74 | 1730 → 1788 | 2273 → 2274 | 371 → 377 |

The "on" runs happened to be faster here (the first test had them within ±1 fps): neither is an effect of the
shading, which costs a texture read on landmark surfaces and a few instructions in the shaders. At the 14 landmarks
(one run each) fps moved between −4 and +2, draw calls by under 5 %, video memory by under 4 MB.

Rollback: as above (the `_ao` files, `--noao`, `--noshaderao`).
