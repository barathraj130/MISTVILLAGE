# Movement lab (godot/tests/movement_lab.gd)

A scripted walker (player.gd `auto_input`) moves Karthik through measured runs on a test ground, through the real
character physics. Run:

```bash
Godot --headless --fixed-fps 60 --path godot scenes/movement_lab.tscn
```

`--movetrace` prints the stair climb frame by frame. In the game, `--movedebug` shows a line on screen: speed, clip
and its speed, the foot-slide ratio, ground, vertical speed, slope.

## Stage 1, 2026-11-07

| run | before | after |
|---|---|---|
| walk (1.4 m/s): to 90% / stop | 0.37 s / 0.18 m | same |
| run (4.2 m/s): to 90% / stop | 1.08 s / 1.73 m | same |
| run, then back: until walking back | 1.33 s | same |
| up a 10° / 20° ramp | 1.40 / 1.40 m/s (no effort) | 1.28 / 1.16 m/s |
| a flight of 10 steps, 16 cm × 30 cm | stuck at the first step; the body popped 36 cm in a frame | to the top in 4.7 s; the body rises at most 6 cm a frame |
| a 15 cm kerb | onto it | onto it (slows to 1.14 for the step) |
| a 0.9 m passage | through | through |

What changed in scripts/player.gd:
- **The step up:** it now probes from a step's height ahead, finds the top below, and rises exactly to it. The body eases up what he rose; before, the smoothing never engaged.
- **The capsule** is 0.25 m in radius, a person's shoulders. At 0.3 m it jammed on a 30 cm tread.
- **Slopes:** slower uphill, careful down steep ones.
- **Turning** is slower at a run (momentum).
- **The resort/drive mode's default walk and run (3.2 / 7.0 m/s)** are now the story's (1.4 / 4.2), which the clips match, so feet don't slide there either.
- **Joystick:** a stick pushed halfway now walks slower.
