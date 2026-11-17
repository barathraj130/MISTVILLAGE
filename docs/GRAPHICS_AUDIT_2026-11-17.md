# Graphics and lighting: audit (Phase 1, 17 November 2026)

The AAA graphics brief's first phase: what the game is now, measured in the game. Nothing was changed for this audit.
Evidence: `--gfxaudit` (`godot/scripts/city/gfx_audit.gd`): six places, five hours each (07:15, 13:00, 18:10,
21:30, and 21:30 in rain), a screenshot and three seconds measured at each, on the development machine (MacBook Air
M1, 8 GB) at its default preset (Low), in a 1600 × 900 window. The screenshots are kept in `user://gfx/`; a selection
is in `docs/shots/graphics/`.

## 1. What the project has

| Area | Now |
|---|---|
| Engine, renderer | Godot 4.7.2, Forward+ on Metal (Apple M1, Apple7); Jolt physics |
| Presets | `scripts/graphics.gd`: Low / Medium / High / Ultra (resolution scale 0.5–1.0 with FSR 1 or FSR 2, sun shadow 2048–4096 px with soft filter 1–4 and 80–220 m reach, two splits on Low and Medium, SSAO and its quality, SSIL in rooms, volumetric fog in the mountains, mesh LOD threshold, tiles kept loaded, traffic / walkers / people counts). The M1 or any integrated GPU starts on Low, others on High; F2 cycles; saved in `user://settings.cfg` |
| Sky and light | A procedural sky; the sun follows the game clock (`city_test.gd` `_daylight`): its direction, colour (warm when low), energy; the sky's top and horizon colours by day, dusk and night, greyed by cloud; ambient light from the sky, `lerp(0.16, 0.45, daylight)`; fog with aerial perspective, its colour warm at dusk; AgX tonemapping; glow only after dark; rooms lit by their own lights with SSIL. A trial colour grade by the hour (`scripts/city/grade.gd`, `--grade`) is not on |
| Buildings | Thousands in one facade shader (`shaders/building.gdshader`: windows by floor and bay, shop shutters and sign bands, some windows lit at night) and kit buildings (`building_kit.gdshader`); landmarks as their own models (`assets/landmarks/landmarks.json`) |
| Roads | `shaders/road_surface.gdshader`: asphalt textures, colour variation, wear, and rain (darker, glossy, water pooling in the wheel tracks) |
| Night lights | Street lamps' heads glow, their light on the road a painted pool (`lamp_pool.gdshader`: no real lights); vehicles' head lamps are lights; the petrol bunks' canopies have four real lights each (no shadows) |
| Scale | The city streamed in 256 m tiles round the player (5 × 5 on Low and Medium, 7 × 7 on High and Ultra); near and far building versions by visibility range (an HLOD of sorts); MultiMesh for kit buildings, people, parked vehicles and props; mesh LOD automatic. **No occlusion culling** |

## 2. Measured (Low preset, 1600 × 900, M1)

| Place, hour | fps | CPU (median frame, process) | Draw calls | Objects | Primitives | Video memory |
|---|---|---|---|---|---|---|
| Gandhipuram 07:15 / 13:00 / 18:10 / 21:30 / rain | 8.5 / 14.4 / 11.7 / 10.5 / 13.4 | 73 / 66 / 75 / 86 / 64 ms | 2 040–2 290 | 13 000–13 260 | 1.9–2.2 M | 2.1–2.5 GB |
| Ganapathy (residential) | 11.2 / 14.4 / 16.1 / 7.0 / 12.9 | 91 / 60 / 63 / 131 / 68 ms | 1 420–1 900 | 13 250–13 770 | 1.3–1.8 M | 2.4 GB |
| Kongu Fuels, Sathy Road | 8.0 / 16.2 / 10.2 / 5.8 / 7.9 | 79 / 53 / 79 / 191 / 103 ms | 2 220–2 560 | 12 470–12 800 | 1.7–2.2 M | 2.4 GB |
| Police station | 7.7 / 11.1 / 10.7 / 7.2 / 11.6 | 126 / 80 / 96 / 116 / 71 ms | 1 970–2 190 | 14 160–14 380 | 1.8–2.1 M | 2.4 GB |
| Government hospital | 9.2 / 10.7 / 5.6 / 6.8 / 9.0 | 114 / 70 / 157 / 99 / 101 ms | 1 610–1 800 | 14 440–14 660 | 2.1–2.4 M | 2.4 GB |
| Race Course (trees) | 9.9 / 8.9 / 7.3 / 10.2 / 11.3 | 123 / 96 / 104 / 81 / 71 ms | 1 810–2 070 | 15 370–15 660 | 2.2–2.5 M | 2.4 GB |

(The GPU's own render time reads 0.0 ms on Metal through `viewport_get_measured_render_time_gpu`: not available
here, so the GPU's share isn't separated. Static memory 354–401 MB.)

**The main finding: the frame is bound by the CPU, not the GPU.** The median frame's process time alone is 53–191
ms, enough to hold the game under 20 fps before any drawing; the earlier record of 32 fps on Low (a fixed
city-centre view, in `graphics.gd`) was measured before the citizens, walkers, activity and traffic grew. The scripts
that cost most aren't separated yet: `--profsweep` (city_test.gd) measures each script's share and is the next
step. 2 000+ draw calls and 13–16 k objects a frame are also high for an M1 (each object a cull test); occlusion
culling is absent.

## 3. Visual problems (from the screenshots)

1. **Dark building silhouettes at dusk.** At 18:10 the walls not facing the sun are near black against a bright
   orange sky. Cause: the sky's light (ambient) falls with the sun's own brightness (`lerp(0.16, 0.45, daylight)`,
   daylight going to 0 as the sun reaches the horizon), while a real sky stays bright through twilight.
2. **Night streets nearly black.** Away from the bunk's canopy and the car's own lamps, the street and the buildings
   at 21:30 are unreadable: the lamps' pools are faint and few, the ambient 0.16, lit windows sparse.
3. **Flat midday.** Light walls and grey roads under a white sun, little separation; the facade shader's walls are
   a single flat paint with no texture, dirt or weathering; roofs plain.
4. **Shaded sides cold and flat by day.** No bounce light from sunlit ground and walls out of doors (SSIL only in
   rooms).
5. **Same-looking buildings.** One shader, one wall finish: no plaster, brick, tile or glass identities.
6. **Distant haze** is mild and even; the sky and the city's edge meet hard at some hours.
7. **Vehicles** have good paint and glass (the car kit's PBR); the old fleet and the traffic still use the earlier,
   flatter models.
8. **Test location:** the "Gandhipuram commercial road" point lands on an open lot, not on the road; to be moved for
   the next phases' comparisons.

## 4. Plan for the next phases

- **Phase 2, light and exposure:** ambient from the sky by its own brightness (through civil twilight, the sun to
  6° below the horizon), a little cooler in shade; a night floor that keeps streets readable without lifting the
  whole scene; auto-exposure tried against fixed exposure; fog and horizon blended; tested at the same places and
  hours, before and after.
- **Before Phase 6, the CPU:** `--profsweep` to find which scripts cost the frame, then their fixes (update rates by
  distance, as the brief asks). This matters more for the M1 than any rendering setting.
- Phases 3–8 as the brief orders them, each measured the same way.
