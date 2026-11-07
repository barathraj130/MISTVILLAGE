# Vehicle lab (godot/tests/vehicle_lab.gd)

The autopilot drives each vehicle through measured runs on a flat test ground, through the real physics (no teleporting). Run:

```bash
Godot --headless --fixed-fps 60 --path godot scenes/vehicle_lab.tscn -- --vehicles=karthik_scooter,sedan
```

Numbers are for comparing before/after a change, not claims about real vehicles. `--labtrace` prints speed, gear, rpm each second of the acceleration run.

## Baseline, 2026-11-07

Before = the driving as it was. After = with the gearbox's kickdown fixed (it no longer hunts between two gears at full throttle).

### Full throttle: 0–60 km/h (s), speed after 30 s

| vehicle | before | after |
|---|---|---|
| karthik_scooter | t0_60 -1.0, top_kmh 17.7 | t0_60 -1.0, top_kmh 29.4 |
| bike | t0_60 -1.0, top_kmh 43.2 | t0_60 4.97, top_kmh 68.1 |
| auto | t0_60 -1.0, top_kmh 31.9 | t0_60 -1.0, top_kmh 54.0 |
| hatchback | t0_60 -1.0, top_kmh 42.3 | t0_60 4.1, top_kmh 81.0 |
| sedan | t0_60 -1.0, top_kmh 43.4 | t0_60 3.95, top_kmh 83.4 |
| luxury_suv | t0_60 -1.0, top_kmh 57.4 | t0_60 4.55, top_kmh 86.1 |
| bus | t0_60 -1.0, top_kmh 42.4 | t0_60 6.43, top_kmh 68.0 |

### Braking from 60 km/h

| vehicle | before | after |
|---|---|---|
| karthik_scooter | never reached 60 km/h | never reached 60 km/h |
| bike | never reached 60 km/h | dist_m 3.3, time_s 0.43, nose_dip_deg 61.7 |
| auto | never reached 60 km/h | never reached 60 km/h |
| hatchback | never reached 60 km/h | dist_m 9.6, time_s 1.18, nose_dip_deg 1.7 |
| sedan | never reached 60 km/h | dist_m 11.0, time_s 1.35, nose_dip_deg 1.2 |
| luxury_suv | never reached 60 km/h | dist_m 19.0, time_s 2.35, nose_dip_deg 0.6 |
| bus | never reached 60 km/h | dist_m 61.5, time_s 8.33, nose_dip_deg 0.0 |

### Braking from 60 km/h, wet (grip 0.7)

| vehicle | before | after |
|---|---|---|
| karthik_scooter | never reached 60 km/h | never reached 60 km/h |
| bike | never reached 60 km/h | dist_m 3.1 |
| auto | never reached 60 km/h | never reached 60 km/h |
| hatchback | never reached 60 km/h | dist_m 9.6 |
| sedan | never reached 60 km/h | dist_m 11.0 |
| luxury_suv | never reached 60 km/h | dist_m 19.0 |
| bus | never reached 60 km/h | dist_m 61.5 |

### Turning circle at 10 km/h

| vehicle | before | after |
|---|---|---|
| karthik_scooter | radius_m 2.4 | radius_m 2.4 |
| bike | radius_m 0.0 | radius_m 0.0 |
| auto | radius_m 3.9 | radius_m 3.9 |
| hatchback | radius_m 5.3 | radius_m 5.3 |
| sedan | radius_m 5.6 | radius_m 5.6 |
| luxury_suv | radius_m 6.4 | radius_m 6.4 |
| bus | radius_m 12.0 | radius_m 12.0 |

### Cornering at 40 km/h

| vehicle | before | after |
|---|---|---|
| karthik_scooter | never reached 40 km/h | never reached 40 km/h |
| bike | max_lat_g 1.18, roll_deg 90.0, spun True | max_lat_g 1.18, roll_deg 90.0, spun True |
| auto | never reached 40 km/h | max_lat_g 0.55, roll_deg 22.2, spun False |
| hatchback | max_lat_g 0.72, roll_deg 3.2, spun False | max_lat_g 0.72, roll_deg 3.2, spun False |
| sedan | max_lat_g 0.67, roll_deg 2.9, spun False | max_lat_g 0.67, roll_deg 2.9, spun False |
| luxury_suv | max_lat_g 0.58, roll_deg 2.1, spun False | max_lat_g 0.58, roll_deg 2.1, spun False |
| bus | max_lat_g 0.31, roll_deg 1.0, spun False | max_lat_g 0.31, roll_deg 1.0, spun False |

### Speed breaker at 40 km/h

| vehicle | before | after |
|---|---|---|
| karthik_scooter | airborne_s 0.0, peak_jolt 12.3, pitch_deg 5.4, speed_kmh 17.9 | airborne_s 0.0, peak_jolt 17.9, pitch_deg 5.1, speed_kmh 25.7 |
| bike | airborne_s 0.0, peak_jolt 10.0, pitch_deg 3.9, speed_kmh 36.9 | airborne_s 0.0, peak_jolt 9.8, pitch_deg 4.0, speed_kmh 36.9 |
| auto | airborne_s 0.0, peak_jolt 5.3, pitch_deg 2.8, speed_kmh 31.4 | airborne_s 0.0, peak_jolt 6.5, pitch_deg 2.5, speed_kmh 36.7 |
| hatchback | airborne_s 0.0, peak_jolt 6.5, pitch_deg 2.6, speed_kmh 37.9 | airborne_s 0.0, peak_jolt 6.5, pitch_deg 2.7, speed_kmh 37.9 |
| sedan | airborne_s 0.0, peak_jolt 6.6, pitch_deg 2.5, speed_kmh 38.0 | airborne_s 0.0, peak_jolt 7.0, pitch_deg 2.5, speed_kmh 38.0 |
| luxury_suv | airborne_s 0.0, peak_jolt 6.5, pitch_deg 2.1, speed_kmh 38.4 | airborne_s 0.0, peak_jolt 7.1, pitch_deg 2.1, speed_kmh 38.4 |
| bus | airborne_s 0.0, peak_jolt 7.7, pitch_deg 1.4, speed_kmh 37.5 | airborne_s 0.0, peak_jolt 7.7, pitch_deg 1.4, speed_kmh 37.5 |

## What the baseline shows (to fix in the next steps)

1. **Hidden damping.** Every vehicle carries Godot's default linear damping, a drag proportional to mass × speed (about 2,650 N on the sedan at 83 km/h, three times its air drag): no car reaches 100 km/h, lifting off the throttle slows hard, heavy vehicles feel sluggish.
2. **One brake force for every mass.** The sedan stops from 60 km/h in 11 m (about 1.3 g, too short), the bus in 61 m (too long).
3. **Wet roads don't change braking.** Brakes never reach the tyres' limit, so grip 0.7 gives the same distance.
4. **Karthik's scooter tops out at about 29 km/h** (18 before the gearbox fix): it borrows the SUV's diesel gearbox, shrunk.
5. **The motorbike falls over:** it tips onto its side when cornering at 40 km/h, and its front flips it in a hard stop (a 62° nose dive).
6. **The auto-rickshaw rolls 22°** when cornering at 40 km/h.
7. **The chase (Day 13):** the black sedan follows at up to 19 m/s (68 km/h) on straights and 7 m/s in sharp bends; with the scooter at 29 km/h, it can only be lost in a run of tight lanes. Not changed here; see the next step's report.
