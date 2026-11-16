# Traffic drivers and crashes; people round obstacles (2026-11-16)

## Traffic (scripts/city/city_traffic.gd)

**Audit.** The traffic was kinematic (AnimatableBody3D) vehicles on the real road pieces: keeping left in a lane,
one-ways, a choice at each junction, red signals, a distance kept from the one ahead in the same lane. Missing:
anyone on foot crossing in front (they drove through them); vehicles coming across a junction, or turning across,
weren't looked for (they went through each other); only your car could crash into one (`struck`); every driver
the same; the same number about at every hour.

**Now:**

- **Drivers, each their own** (`DRIVERS`): careful, normal, aggressive, slow, new, commercial (buses, lorries,
  taxis, most autos): how fast they like to go, the time gap they keep, how hard they pull away and brake, whether
  they go on an amber, how far ahead they look.
- **What each vehicle can do** (`DYN`): pulling away, braking, how slow it takes a bend: a bus or lorry slow away,
  long to stop, careful round a corner; an auto nips away but brakes gently.
- **Following by a time gap**, and never faster than it can stop in the gap ahead.
- **Looking across the junction**: any other vehicle whose way would meet mine in the next 2.4 s (crossing,
  turning across, a bus swinging round a corner): the one with the lesser claim (the smaller road, then the slower)
  gives way, stopping if it's soon; one standing in the way is always waited for. One stopped just round a corner
  (past my road's end) is seen.
- **People on the road**: someone crossing (city_walkers.gd) in front: they stop for them.
- **Round a crash**: stopped behind one that isn't moving (crashed, its driver out) for 3 s, out to the right as
  far as a lane when nothing's coming the other way, by it, and back in.
- **Crashes between them** (`_collide`): two footprints overlapping (flat boxes, separating axes) and closing at
  over 1 m/s: a crash, once (not again while they stay in contact). **Low** (< 3 m/s): a knock. **Medium** (< 8):
  shoved and turned, dented (dents.gd, as your car's crashes dent them), the drivers out by their doors arguing.
  **High**: spun, badly dented, a loud one, the view shaken if you're near. Momentum shared as a crumpling hit
  does (they part at about their common speed, the lighter one thrown more), off-centre hits turning them. A
  crash's sound made in code: a thump, the crunch of panels, louder and deeper the harder. Those on foot near stop
  and look (city_walkers.gd `look_at_crash`; too near a bad one, a step back).
- **By the hour** (`BY_HOUR`): the morning school and office rush, a quieter afternoon, the evening rush the
  busiest, few at night.

**Tested** (`--traffictest`: a minute of ordinary traffic, then two crashes staged with a driver who doesn't look):
three minutes running before the last fixes had crashes of their own at two junctions (a car waiting at a road's
end with its nose in the main road, one turning across a bus, one creeping into the back of another round a
corner) and vehicles inside each other (up to 1 307 physics steps a minute); after: **0 crashes, 0 inside each
other, 0 through a red** in three runs; the nearest any followed 0.5–1.3 s. Staged: at 9 km/h a low knock (no
dents, a moment's stop), at 50 km/h high (5 dents each, both drivers out, ~15 s stopped), each counted once.

Not done: indicators (the fleet models have no indicator lamps), horns, motorcycles in the traffic (only parked),
lights and glass breaking (the fleet models' lamps aren't separate), police coming to a crash.

## People round obstacles (city_streamer.gd, ped_steer.gd, city_walkers.gd, citizens.gd)

**Audit.** No NavigationRegion3D or NavigationAgent3D anywhere: the walkers follow the footpaths' lines, the
citizens a graph of footpath points (AStar3D). The root cause of walking into things: **the street's furniture
had no collision at all** (trees, palms, poles, signs, bollards, bins, drums, benches, stalls, carts, thatched
shops, transformers, shrines, flex boards, goods, the people standing about): only buildings, the ground and
parked vehicles were solid. Nothing could see a pole, so nobody went round one (Karthik walked through them too).

**Now:** all of it is solid to people on foot (`FOOT_LAYER`, a layer of its own: Karthik on foot and everyone's
eyes see it; cars don't, so driving is as it was): a cylinder each (trees, poles, people standing...) or its
model's box (stalls, benches...), one physics-server body a tile. People look ahead (two rays, the knee above any
kerb and the chest) for anything upright (a vehicle, the furniture, a wall, a compound wall, a gate), go round it
the nearest clear way (left first), or stop and wait, or turn back; never set down inside anything, never given a
spot to stand inside anything. (`--oldsight`: only vehicles seen, as before, for comparing.)

**Tested** (`--citizentest=09:00 --pedcheck`, Gandhipuram, 2 000 checks of everyone in view; "walked through" =
something solid between where they were a second ago and where they are):

| | before | after |
|---|---|---|
| walked through something | 27 | 7 (wedge ramps' sides, a building's corner the footpath line cuts, one transformer box) |
| inside a piece of furniture | 8–10 | 0 |
| on / in a vehicle | 0 | 0 |
| floating / sunk | 0 / 1 | 0 / 1 |

Crossings unchanged (9 in 55 s, 3 of 3 at the signal on its red), none stuck; the same frame rate either way.
