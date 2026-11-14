# The Mist Village: open-world investigation plan, 14 November 2026

Phase 1 of the master brief (open-world investigation, NPC intelligence, physics, the gang's stages). Nothing in the
game was changed to write it. It builds on [AUDIT_2026-11-10.md](AUDIT_2026-11-10.md) (project health, the M1
baselines, worlds, saves, release state) and does not repeat it. Decisions taken with the user on 14 November are in
§1; what still needs a decision is in §9.

## 1. The brief, and what was decided

Three briefs: the master brief (ten phases), the physics brief (ten modules, starting with Karthik's movement and the
car), and the gang brief (six persistent stages). The rules they share: audit first, reuse before building, one phase
at a time, a small working prototype tested in the real game, before-and-after pictures, approval before anything
destructive. Shadows of Doubt is a model for systemic depth only.

Decided on 14 November:

| Question | Decision |
|---|---|
| The Act 6 trap against a gang fight | **Both.** The trap stays where it is (Day 16, won by staying lawful); the ten-man fight comes at the end. |
| Life imprisonment against "never game over" | Only when the critical evidence is irrecoverably lost and nothing independent replaces it. Everything else stays playable (jail, debt, bail as chapters). |
| On-screen journal and cards against "played, not read" | Played, not read stays. The wall in his room is the evidence board; the phone carries the journal, statements and timeline; no floating cards or objective lines. |
| E19's date | Inside the 20-day timeline (the slice's Day 17), not the catalogue's Day 22. |
| The final fight's place | **E15 becomes Joseph's copy of the money-lender's ledger, hidden in Suresh's godown at Pudhur Vayal, guarded by the gang** (Day 18): the ten-man fight is there. |
| Order of work | **The master brief's order** (citizens first), with **the best physics in every system as it's built** (the physics brief's modules folded into each phase, not left to the end). |

## 2. The story as written and as played

The Story Bible describes the **full game** (Act 6 on Days 21–25). The playable story (`story/slice.json`, 599 steps)
compresses Part 1 into **20 days**, and its own day table is in the Bible's §"slice" (Days 1–20). The brief's timeline
(Day 19 trial, Day 20 handover) matches the slice. **The slice is the timeline kept**; the Bible's catalogue needs a
note where its days differ.

Mismatches found:

| Where | Bible | Playable |
|---|---|---|
| E19, the bus stand CCTV | Day 22 | Day 17 (step 542) |
| Act 6 | Days 21–25 | Days 16–20 |
| E01–E04 | Listed as evidence (Days 1–2) | E01–E03 are the police's case, not things Karthik finds; E04 (his delivery record) has no evidence step and is put before the court at step 583 |
| E07 | Found in Act 4 | Handed over at step 162 (a "give" step, Day 5); recorded nowhere as an `evidence` step |
| "Verified" | The catalogue says E06 is unverified until E07 | The game keeps no verified state: evidence is honest or bought (`paid`); the two-legs rule lives only in court.gd |

**Evidence as the player gets it** (step, the slice's day, how):

| Order | Id | Day | Step | Note |
|---|---|---|---|---|
| 1 | E06 | 3–5 | 145 | the watchman (₹500 opens the gate: bought) |
| 2 | E07 | 5 | 162 | the DVR (a "give" step); verifies E06 |
| 3 | E05 | 6 | 204 | the doorbell clip |
| 4 | E08 | 7 | 228 | the tea stall |
| 5 | E14 | 7 | 234 | Amma's albums |
| 6 | E09 | 10 | 329 | the green-ink note |
| 7 | E16 | 11 | 358/363 | land records (bought, or Revathi) |
| 8 | E18 | 12 | 397 | the Siruvani Grand |
| 9 | E17 | 13 | 431 (523) | post-mortem |
| 10 | E11, E12 | 14–15 | 480–481 | the workshop, Bala |
| 11 | E10, E13 | 17 | 520–521 | the court orders |
| 12 | **E19** | 17 | 542 | Pandi at the bus stand |
| 13 | **E15** | 18 | 565 | Joseph at the CODISSIA fair |

**The gang's stages on the real story:**

- **Stage 2 (one observer)** starts with the third *verified* evidence. Counting E06 only once E07 confirms it, the
  third is **E05 on Day 6**. Counting every item as found, it is **E05** as well (E06, E07, E05). Either way: Day 6.
- **Stage 3 (pursuit)** starts when only the final two remain: after E10 and E13, on **Day 17**.
- **The final two** are **E19** (Day 17, the bus stand) and **E15** (Day 18, Joseph at the fair).
- **Stage 4's fight** needs a guarded place for the last evidence. In the story E15 is a quiet recording of Joseph at
  a public fair, which a ten-man fight doesn't fit. A decision is needed (§9).
- **Stage 5 (hiding)** falls on the night of Day 18; **the trial is Day 19** and **the keys Day 20**: the timeline
  already fits.
- The existing **black sedan tail** (Day 13, `story.gd` `_chase`: lose it in the lanes, 100 m clear for 4 s) is
  already a Stage 2 moment. It is the starting point for the observer, not a separate system.

## 3. The fifteen areas

| # | Area | What there is | Reuse | Missing for the brief |
|---|---|---|---|---|
| 1 | Scenes | `city_test.tscn` (Coimbatore, streamed 256 m tiles), `drive.tscn` (the ghat), `main.tscn` (the resort), labs (`movement_lab`, `vehicle_lab`) | all | a test scene per physics module (most can be flags on the city, as now) |
| 2 | Player | `player.gd` CharacterBody3D: walk/run, acceleration and deceleration, slope speed, step-up, model turn rate, lean | yes | crouch, cover, stumble/fall/get up, foot IK, stairs check |
| 3 | NPCs | `city_living.gd` (still figures alive near him: idle, phone, pairs and groups talking, noticing him), `city_walkers.gd` (footpath walkers, crossings, habits), `crowd.gd`, `room_walkers.gd`, `actor.gd` and `acting.gd` (story cast: feelings, gestures, faces), `standing.gd` (each person's feelings and memories of Karthik), `sf_living.gd` | yes | named citizens with home, work and a day; schedules; activities by time; distance tiers |
| 4 | Navigation | No NavigationAgent3D, no navmesh. Walkers follow the footpath polylines of the loaded tiles; traffic follows the road polylines (`city_traffic.gd` `ends`) | the polylines | a graph across tiles for errands (footpaths, crossings, doors); navmesh only inside the rooms that need it |
| 5 | Animation | AnimationPlayer per model, clips by name (Idle, Walk, Run, Sit, Talk, gestures through `crowd_clips.gd`); no AnimationTree; IK only for the head (`head_look.gd`, a SkeletonModifier3D) | yes | foot IK (SkeletonModifier3D, as the head), a hand IK for doors and objects, a fall and get-up |
| 6 | Vehicles | `jeep.gd` (1,943 lines): VehicleBody3D, engine, gears, suspension, surfaces, wet grip, dents, two-wheelers with their own balance and lean; `vehicle_lab.tscn` and `docs/VEHICLE_LAB.md` | yes | a measured comparison with a raycast-wheel prototype (the physics brief asks for it), torque curve and slip numbers, the chase's AI drivers |
| 7 | Physics | Jolt; almost everything on the default collision layer (two explicit masks in the code); trimesh collision for rooms; boxes for traffic | yes | a layer plan (world, roads, people, vehicles, props, triggers), simplified shapes, sleeping props |
| 8 | Evidence E01–E19 | `story.gd` `evidence` (tag → title, body, paid); 22 evidence steps; the catalogue in STORY_BIBLE §5 | yes | a status per item (found, honest/bought, corroborated, submitted, lost); E07 recorded as evidence |
| 9 | Verification | court.gd's two-legs rule (a bought item needs an honest one beside it) | yes | the same rule outside court, so the wall and the gang's stages can read it |
| 10 | Story and triggers | `story.gd` (4,089 lines): steps, conditions (`when`), flags, chases, choices, detours, saves by step signature | yes | the gang's six states as story flags; their own triggers |
| 11 | Saves | the story save (version 2, steps found by signature), plus bail, money, life, fines and the drive world | yes | the gang state, the citizens' day, the knowledge store |
| 12 | Interaction | `city_doors.gd` (every building enterable; rooms), `store.gd`, `hands.gd`, `bag.gd`, `tasks.gd` (sign, count, hang, OTP), `keypad.gd`, `dvr.gd`, `doorbell.gd`, `table.gd` | yes | drawers, desks, documents and switches as things, only in story rooms |
| 13 | Dialogue | talk steps with emotions and gestures; `choose`; the interrogation table; the phone (calls, messages, apps) | yes | asking a citizen about a person, place, time or vehicle; showing evidence; recorded statements |
| 14 | City | Coimbatore from OpenStreetMap: roads, 6,000+ buildings a few tiles round him, landmarks with rooms, signals, water | yes | — |
| 15 | M1 performance | measured 10 Nov and again 13–14 Nov: 20–31 fps on Low at 1280 × 720 in the streets, 4–14 fps at a few dense spots (also without the new people) | the profiler (`prof.gd` PROF lines), `--livingbench`, `--viewbench` | per-system budgets; the dense spots investigated |

## 4. Systems missing

1. **Citizens with a day**: identity, home, work, a schedule, the activity now; the distance tiers.
2. **Knowledge**: who saw what, when, where, how sure, first-hand or heard; asked about by person, place, time or
   vehicle; contradictions; statements.
3. **Evidence state**: found, honest or bought, corroborated (two independent legs), submitted, lost.
4. **The phone's investigation app**: statements, timeline, people (the journal, played on his phone).
5. **The wall, extended**: thread types (supports, contradicts, places, times, identifies, relates), read from
   the evidence state.
6. **Interaction objects**: drawers, desks, documents, switches, a vehicle's doors, in story rooms only.
7. **Body**: stumble, fall and get up, crouch and cover, foot IK, a hand on a door.
8. **The gang**: the observer, the pursuers, their vehicles in traffic, the final fight, the search while he hides.
9. **Collision layers** and a surface table read by both feet and tyres.

## 5. What depends on what

```
evidence state ──► the wall's threads ──► court (exists)
      │
      ├──► the gang's stages ──► observer ──► pursuit (vehicle AI on jeep.gd) ──► final fight ──► hiding ──► court
      │                              ▲                                            ▲
knowledge store ◄── citizens with a day ◄── navigation graph                body: fall, IK, combat moves
      │
      └──► interviews (talk steps, the phone app)
collision layers ──► everything physical (do it early, it touches every body)
```

## 6. The phases on this project

Each phase: what changes, the files, a small prototype, a test in the game, pictures, approval.

| Phase | First prototype | Files |
|---|---|---|
| 2 Citizens | twenty named people round Gandhipuram with a home, a workplace and a day; tiers by distance; seen opening a shop, going to work, eating, going home | new `citizens.gd` and `citizens.json`; `city_living.gd`, `city_walkers.gd` (reuse), `standing.gd` (memory) |
| 3 Knowledge and evidence | the evidence state for E05–E19 (honest/bought/corroborated), shown on the wall; Sekar the tea stall owner answering about a car, a person and a time, from his own knowledge | new `knowledge.gd`; `story.gd` (state), `wall.gd`, `phone.gd` (an app) |
| 4 Interaction | one story room (the Raghavan office) with a desk, a drawer and a document | `city_doors.gd`, a small `interactable.gd` |
| 5 Body | stumble and fall when barged, get up; foot IK on stairs | `player.gd`, a foot SkeletonModifier3D beside `head_look.gd` |
| 6 Vehicles | the raycast-wheel prototype against VehicleBody3D on `vehicle_lab.tscn`, measured; layers and the surface table | `jeep.gd`, `vehicle_lab`, `docs/VEHICLE_LAB.md` |
| 7 Gang, stages 1–3 | the six states as saved flags; the observer from Day 6 (built on the sedan tail); one pursuit on Day 17 | `story.gd`, a new `gang.gd`, `city_traffic.gd` |
| 8 Fight and hiding | five men first, then ten, in waves with telegraphed attacks; the night hidden | new `fight.gd`; the hiding place a story room |
| 9 Court and endings | the court reads the evidence state; the bad ending only on irrecoverable loss | `court.gd`, `story.gd` |
| 10 QA and performance | per-system budgets on the M1, the dense spots, a full playthrough | — |

The physics brief's order (Karthik's movement and the car first) is phases 5 and 6. They can move earlier if the
user wants, since they don't depend on the investigation.

## 7. Performance risks on the M1

- **Citizens**: every animated person costs a skeleton and its clips; the near tier must stay at the graphics
  preset's budget (`city_living` already has one: 12/20/28).
- **Dense spots**: 4–14 fps measured at Ramanathapuram with or without people: the cause is not known yet (traffic,
  buildings, draw calls).
- **Navigation across tiles**: building a graph as tiles stream costs main-thread time, as the tiles already do
  (6–7 ms a frame).
- **Ten fighters**: ten skeletons, physics and AI at once; waves keep it to a few active.
- **The realistic Sketchfab people**: up to 65,000 triangles each; fine for a few near, too heavy for a crowd.

## 8. What this plan does not change

The story's order, its lines, the evidence ids, the court, the bail rules, the saves' format (new keys are added,
none removed), the worlds, the controls.

## 9. Decisions still needed

None for Phase 2. (Both were decided on 14 November: §1.)
