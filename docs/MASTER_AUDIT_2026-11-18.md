# The Mist Village: master technical audit (Phase 1), 18 November 2026

This responds to the master audit brief and its two NPC addenda (spawning continuity, occupations). It builds on
the audits that already exist and doesn't repeat them: `AUDIT_2026-11-10.md` (the whole project),
`WORLD_LIFE_AUDIT_2026-11-13.md`, `OPEN_WORLD_PLAN_2026-11-14.md`, `PEDESTRIAN_FIX_2026-11-16.md`,
`TRAFFIC_AND_OBSTACLES_2026-11-16.md`, `VEHICLE_AUDIT_2026-11-17.md`, `GRAPHICS_AUDIT_2026-11-17.md`,
`PROLOGUE_PLAN_2026-11-17.md` and `TWO_WHEELERS_2026-11-17.md`. Nothing was changed to write this audit. Each
statement is marked as **measured** (from a run), **read** (from the code), or **not checked**.

## 1. Baseline

| Item | State |
|---|---|
| Engine | Godot 4.7.2, Forward+ on Metal (M1, 8 GB); Jolt physics; physics interpolation on (read) |
| Main scene | `start_menu.tscn` → the city (`city_test.tscn`), the ghat drive (`drive.tscn`), the resort (`main.tscn`) (read) |
| Autoloads | None. Each world builds its own managers as children of its root script (read) |
| Code | 51 900 lines of GDScript. Largest: story.gd 4 663, city_streamer.gd 2 900, city_test.gd 2 849, jeep.gd 2 355, drive_game.gd 2 115, towns.gd 1 902, tasks.gd 1 594 (read) |
| Story data | `slice.json` (Day 1–20, 599 steps, English and Tamil on every line), `jail.json`, `prologue.json` (the new 3-day prologue, partly built), `citizens.json` (23 named citizens with homes, workplaces and day schedules), `interactables.json`, `knowledge.json`, `relations.json`, `emotions.json`, `food.json` (read) |
| Saves | The story save is version 2 and finds steps by signature (`tests/story_save_find_test.gd`). Money, bail, life, fines, garage and finance each have `save`/`load_state`. **Not checked**: whether the garage and finance state ride in the story save in every path (the prologue's purchase writes them, the reload is untested) |
| Export | Presets exist for Windows, Linux and macOS; templates 4.7.2 are installed. **No build has been made or boot-tested** (not checked) |
| Audio | No audio files. Engines, horns, rain and rooms are synthesised in code. No music (read) |
| Git | `main`, 3 commits ahead of `origin/main` (not pushed: waits for your word). Other sessions' uncommitted work in the tree (HUD, map, people glbs, trailer, the humans tools) is left alone (read) |
| Performance | Low preset: **6–16 fps** at six city places and five hours. The frame is CPU-bound: 53–191 ms of script time a frame, 2 000+ draw calls, no occlusion culling (measured 17 Nov, `--gfxaudit`) |

## 2. What exists (feature inventory, by the brief's sections)

| Brief section | Exists (read; tested where marked) | Main gaps |
|---|---|---|
| 3 Prologue, finance | `prologue.json` stages 1–3: payday, the dealership (`dealer.gd`) with both branches (keep the old scooter for ₹7 500 + a scooter for Divya, or trade in for ₹6 000), finance desk (`finance.gd`: exact EMI in paise, schedule, late fee), learning to ride, deliveries, Kongu Fuels bunks (`fuel_bunks.gd`) (tested: `--storychapter=prologue`, `--financetest`, `--bunktest`) | The breakdown on the road, hazards, the phone map to a mechanic, the job card, Amma's conversation, the chapter's day flow into `slice.json` Day 1, save/load of the branch (stages 4–6 of the prologue plan) |
| Vehicle condition | `garage.gd`: fuel, odometer, condition (wear by km and crashes; under 60 the engine pulls less and drinks more) | Battery, tyres, brakes and suspension aren't separate. No servicing, no rough running or sounds from wear, no breakdowns outside the scripted one |
| City | OSM Coimbatore streamed in 256 m tiles; facade shader; kit buildings; landmarks; footpaths; signals; lamps; petrol bunks; interiors through `city_doors.gd` | Same-looking walls, flat midday, dark dusk and night (`GRAPHICS_AUDIT`) |
| NPCs | Four systems: `city_walkers.gd` (a pool walking the footpaths, crossing, talking, stepping aside), `city_living.gd` (standing figures brought to life near him on foot), `city_activity.gd` (people at spots: bus shelters, stalls, tea benches, shop doors, guards), `citizens.gd` (23 people with names, roles, homes, workplaces and schedules, in three tiers: state everywhere, a body within 70 m). Also `social.gd` (people in rooms noticing him) and the Sketchfab living people (`sf_living.gd`, another session's) | **Continuity (section 3 below).** Walkers have no occupation or destination (they walk strips). Only the 23 citizens have a home, work and a day. No navigation mesh: walkers follow footpath polylines and `ped_steer.gd` |
| Characters, animation | Karthik's gait (`gait.gd`, foot IK, `KARTHIK_GAIT_2026-11-16.md`), crowd clips, rider IK with the steering-wheel grip (hands turn with the wheel to ±60°) | Phone, door and pickup animations; transitions; important characters' identities (faces session) |
| Vehicles | `jeep.gd` specs per vehicle (mass, centre of mass, suspension, torque, gearbox and CVT, two-wheeler balance and lean); own-cabin cars with live needles; dents; lamps; indicators; the new luxury SUV body (d1f21fe) | Old fleet models flat; cameras: cockpit, chase and bonnet exist, cinematic and look-back don't (not checked) |
| Traffic | `city_traffic.gd` (lanes, signals, following, give-way at obstacles, `TRAFFIC_AND_OBSTACLES`); drive world `traffic.gd`; resort traffic: three separate systems | Overtaking, indicators on turns, emergency response; collisions don't weigh angle or mass |
| Life, economy | `life.gd` (energy, tiredness, stress, sleep, relief activities), `money.gd` (wallet, bank, bills, UPI), salary, delivery gigs, fuel costs, EMIs | An economy balance check across the 20 days with the prologue's loans hasn't been run |
| Investigation | E01–E19 in the story data; evidence wall; DVR; phone records; keypad; court with six points; journey replay on the map | Evidence states (unverified, verified, disputed) aren't one data model; E01 and E03 aren't tracked in code (`AUDIT_2026-11-10`, item 10) |
| UI | HUD, phone, map, evidence wall, dealer and finance panels | A settings screen and a pause menu exist only in part; controller mappings are missing (not checked since 10 Nov) |
| Audio | Synthesised engines, horns, rain, rooms | Everything else in section 13 |
| Performance | Presets Low–Ultra; streaming; MultiMesh; tiers by distance in walkers and citizens | CPU per frame: `--profsweep` not yet run on the current build |

## 3. NPC continuity: what the code does now (read; confirms the addendum's complaint)

| System | Spawn | Despawn | Problem |
|---|---|---|---|
| `city_walkers.gd` | On a footpath 35–85 m away. It avoids a ±60° cone ahead only under 60 m, and after 9 of 12 tries it takes any spot | Over the hour's quota and past 35 m: **hidden at once, in view or not**. Past 95 m: **set down elsewhere at once** | People appear 35–85 m in front of the camera; a walker 40 m ahead vanishes when the hour's count falls; while driving, walkers ahead pop out at 95 m |
| `city_living.gd` | Swaps a still figure for a live one within ~40 m, "out of his view where possible" (frustum check) | Back to the still figure past ~55 m | The figure is the same person in the same place, so a swap is mostly invisible. Low risk |
| `city_activity.gd` | Spot people given out nearest first when a tile loads | Taken back when the tile goes or a better spot is nearer | Not checked for view. Medium risk |
| `citizens.gd` | A body within 70 m, at their place or on their route | Body freed past the range | Not checked for view. The person keeps their identity and schedule (state tier), so their reappearance is consistent |

### Fixed: walkers (18 Nov)

`city_walkers.gd` now sets a walker down, hides one (when the hour's count falls) or moves one (when it's left
behind) only where the camera can't see the spot: outside the view, or behind something solid (a ray from the
camera). Past `HARD_FAR` (170 m) they may go regardless. If no unseen spot is found, it waits for a later tick: no
fallback into view. Thresholds are constants at the top (`SPAWN_MIN`, `SPAWN_MAX`, `HARD_FAR`, `VIEW_FAR`).

Measured with the new `--popwatch=drive|still` (`pop_watch.gd`: every frame, every walker, activity person and
citizen body seen from the camera within 120 m, nothing solid between; 120 s; 09:00 unless noted):

| Run | Appear in view | Vanish in view | Jump in view | Person-frames in view |
|---|---|---|---|---|
| Before, drive | 0 | 0 | 5 | 2 157 |
| Before, drive (tagged) | 0 | 0 | **5, all walkers: ~100 m away moved to 37–91 m** | 13 164 |
| Before, still, turning round every 15 s | 0 | 0 | 2 | 23 542 |
| After, drive | 0 | 0 | 1 (untagged run: source unknown) | 20 929 |
| After, drive | 0 | 0 | 0 | 6 775 |
| After, drive, 08:30 / 09:30 | 0 / 0 | 0 / 0 | 0 / 0 | 24 792 / 19 428 |
| After, still, turning round | 0 | 0 | 0 | 11 237 |

The autopilot's route differs between runs, so the counts are per run, not comparable to the person. Not yet
covered: on foot through a crowd, entering and leaving buildings, returning to a street, and the activity and
citizen systems' own swaps (no pops from them were seen in these runs).

## 4. Story continuity (to reconcile, not changed)

1. **Calendar:** the bible puts the trial on Day 19 and the keys on Day 20; earlier test runs reached court on the
   20th–21st sleep (`AUDIT_2026-11-10`, item 9). Still open.
2. **The prologue and Day 1:** the prologue's three days end before `slice.json` Day 1. On the trade-in branch the
   old scooter in later scenes must become the new one ("karthik_scooter" mapping), and the old scooter's
   instalment bill must not post. Planned in `PROLOGUE_PLAN`, not built.
3. **The brief versus the prologue as you decided it:** the brief has the breakdown on "the first morning" on the
   way to Raghavan's and the salary that evening. You decided (17 Nov): no day numbers; the purchase comes after a
   salary; the scooter breaks down while riding on day 1. These fit together if day 1 is the payday. **Proposal:**
   breakdown on the morning ride (day 1), late to Raghavan's, drives the SUV, salary in the evening, Amma's talk that
   night, dealership on day 2, deliveries on day 3. This needs your yes, since it moves the payday from where the
   current `prologue.json` has it.
4. **The brief's branch A** says "purchase a motorcycle for Karthik" when he keeps the old scooter; the built branch
   A buys a scooter for Divya and overhauls his old one. **Proposal:** keep what you chose on 17 Nov (Divya's
   scooter, his old one overhauled) and treat the motorcycle as an optional later purchase. Needs your yes.

## 5. Prioritised list

**Critical blockers**
1. Frame rate on the M1 (6–16 fps). Nothing else reads well until the game is above 25. Run `--profsweep` first.
2. NPC pop-in and pop-out (section 3). Fix in `city_walkers.gd` first, then check the other three systems.
3. Untested save/load of the prologue's purchase branch (garage, loans) across a restart.
4. No build has been made or boot-tested on any platform.

**High priority**
5. Prologue stages 4–6: the breakdown, the mechanic and the job card, Amma, the chapter flow, both branches into
   Day 1.
6. Dusk and night lighting (graphics Phase 2).
7. Purpose for every walker: give the pooled walkers an occupation and a destination drawn from the district's
   places (shops, bus stops, offices), using the citizens' schedule format, not a second system.
8. Evidence as one data model, with states and sources, for E01–E19 (no change to the facts).

**Medium priority**
9. Vehicle condition parts (battery, tyres, brakes) and servicing at the mechanic, wear you can feel, rare breakdowns.
10. Traffic indicators, overtaking and emergency response; collision response by angle and mass.
11. Audio: recorded ambience and music (downloads need your OK).
12. Settings screen, pause menu, controller.

**Low priority, polish**
13. Old fleet models; cinematic and look-back cameras; phone, door and pickup animations.

**Dependencies:** 1 before 6 and 10 (lighting and traffic cost frame time); 3 before 5 (the prologue needs a save
it can trust); 2 before 7 (purposeful walkers reuse the fixed spawn rules); 8 before any court changes.

## 6. Plan: the next steps, in order

1. **NPC continuity, walkers** (now): spawn only outside the camera's view frustum (or behind something solid), never
   force a spot in view (try again next tick), and hide or move a walker only once it's out of view or past a
   configurable far distance. Log spawns and despawns, with how many were in view, under `--walkertest`. Measure
   before and after on a drive and on foot.
2. The same rule for `city_activity.gd` and `citizens.gd`.
3. `--profsweep` on the current build; fix the top CPU costs.
4. Prologue save/load test across a restart, both branches.
5. Prologue stage 4 (the breakdown, the mechanic, the job card), after your answer on section 4 items 3 and 4.
