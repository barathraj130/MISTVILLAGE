extends Node3D
const Prof := preload("res://scripts/drive/prof.gd")
## Traffic in the streamed city: hatchbacks, sedans, taxis, autos, and on the main roads buses and lorries, driving
## the real road pieces of the loaded tiles. Each keeps left in its lane, follows one-ways, picks a way at every
## junction (mostly straight on, sometimes turning, the big roads more likely), slows for turns, stops at red
## signals and keeps its distance from the vehicle ahead and from you. They are solid (you can bump them).
## Vehicles live within ~400 m of you: new ones appear out of sight, far ones are recycled.

const Fleet := preload("res://scripts/drive/fleet.gd")
const Streamer := preload("res://scripts/city/city_streamer.gd")
const DRIVE := ["trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street"]
const CRUISE := {"trunk": 15.0, "primary": 13.0, "secondary": 11.5, "tertiary": 10.0, "unclassified": 8.5,
	"residential": 7.5, "living_street": 5.0}
const BIG := {"trunk": 3.0, "primary": 2.5, "secondary": 2.0, "tertiary": 1.5}
const DIMS := {"hatchback": Vector3(1.7, 1.5, 3.9), "sedan": Vector3(1.75, 1.45, 4.4), "taxi": Vector3(1.75, 1.45, 4.4),
	"auto": Vector3(1.4, 1.75, 2.7), "bus": Vector3(2.55, 3.2, 11.0), "lorry": Vector3(2.5, 3.3, 8.2)}
const MASS := {"hatchback": 1050.0, "sedan": 1250.0, "taxi": 1250.0, "auto": 400.0, "bus": 11000.0, "lorry": 9000.0}
const LIFT := 0.09                         # road surface above its centreline points (= streamer RANK + 0.06)
const Dents := preload("res://scripts/drive/dents.gd")
## Drivers, each their own way: how fast they like to go (× the road's cruise), how far behind the one ahead they
## keep (seconds), how hard they pull away and brake (× the vehicle's own), whether they go on an amber, and how far
## they look ahead (seconds of travel) for someone crossing or a car coming across a junction.
const DRIVERS := {
	"careful": {"cruise": 0.9, "headway": 2.2, "accel": 0.8, "brake": 0.85, "amber": false, "look": 4.0},
	"normal": {"cruise": 1.0, "headway": 1.6, "accel": 1.0, "brake": 1.0, "amber": true, "look": 3.2},
	"aggressive": {"cruise": 1.18, "headway": 0.9, "accel": 1.35, "brake": 1.3, "amber": true, "look": 2.2},
	"slow": {"cruise": 0.72, "headway": 2.5, "accel": 0.7, "brake": 0.8, "amber": false, "look": 4.0},
	"new": {"cruise": 0.85, "headway": 2.0, "accel": 0.75, "brake": 1.15, "amber": false, "look": 2.6},
	"commercial": {"cruise": 1.05, "headway": 1.3, "accel": 1.0, "brake": 1.0, "amber": true, "look": 3.0}}
const DRIVER_MIX := [["careful", 0.22], ["normal", 0.44], ["aggressive", 0.13], ["slow", 0.12], ["new", 0.09]]
## What each vehicle can do: pulling away, braking (m/s²), and how slow it takes a bend (× the car's): a bus is
## slow away, long to stop, wide and careful round a corner; an auto nips away but brakes and corners gently.
const DYN := {"hatchback": [2.2, 5.5, 1.0], "sedan": [2.3, 5.8, 1.0], "taxi": [2.3, 5.6, 1.0], "auto": [1.6, 3.8, 0.85],
	"bus": [0.9, 3.0, 0.7], "lorry": [0.8, 2.8, 0.72]}
## How many are about by the hour (× the busy count): the morning's school and office rush, a quieter afternoon,
## the evening's rush the busiest, few at night.
const BY_HOUR := [0.22, 0.15, 0.12, 0.12, 0.18, 0.35, 0.6, 0.9, 1.1, 1.05, 0.85, 0.75, 0.75, 0.8, 0.75, 0.8, 0.95,
	1.1, 1.15, 1.05, 0.8, 0.6, 0.45, 0.3]
## The Sketchfab traffic pack (CC-BY, tools/sketchfab_traffic_pack.py) on the move too: most of each kind one of
## these (the taxis stay the plain fleet's, in their yellow), each with its own indicators, brake and tail lamps.
const SF_FLEET := "res://assets/vehicles/sf_fleet.json"
const SF_FOR := {"hatchback": ["hatchback", "ev", "red"], "sedan": ["luxury", "suv"], "auto": ["rickshaw"], "bus": ["bus", "tnstc"],
	"lorry": ["truck"]}
## (most of Coimbatore's town buses are the state's own: TNSTC, tools/sketchfab_tnstc.py)
const SF_PREFER := {"bus": ["sf_tnstc_bus", 0.6]}
const SF_SHARE := 0.75
var _sf: Dictionary = {}                   # kind → [[key, entry from sf_fleet.json], ...]
var _sf_scenes := {}
var _lamp_on: StandardMaterial3D           # an indicator lit (amber), a brake lamp lit (red)
var _brake_on: StandardMaterial3D
var crashes: Array = []                    # (testing) [time, kinds, severity, closing m/s]
var _touching := {}                        # "a,b" (instance ids) → the time they last touched: a crash counted once
var _ped_t := 0.0
var _peds: Array = []                      # people on the road now (crossing): [position, way]

@export var count := 36                    # out in the suburbs; more in the centre (BUSY)
var busy := 70                             # vehicles around you in central Coimbatore (graphics.gd "traffic")
const CENTRE_R := 4500.0                   # metres from the city origin (Gandhipuram) that count as central
var streamer
var player: Node3D
var vehicles: Array = []
var wet := 0.0                             # how soaked the roads are (city_weather.gd): everyone a little slower
var ends := {}                             # Vector2i (1 m grid) → [[road, at_end(bool)], ...]
var signals: Array = []
## Speed (the CPU's): signals and vehicles kept in a grid of GRID-metre cells, so each one looks only at what's
## near it; and each vehicle thinks (the road's end, the gap ahead, the signals: its target speed) THINK_EVERY
## physics steps, in turn, while its speed and place move on every step.
const GRID := 40.0                         # (≥ the 40 m a driver looks ahead: the 3×3 round him holds all of it)
const THINK_EVERY := 4
var sig_grid := {}                         # Vector2i → [signal, ...]
var _veh_grid := {}                        # Vector2i → [vehicle, ...] (this step)
var _tick := 0
var _built_seen := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026
	if FileAccess.file_exists(SF_FLEET) and not "--nosftraffic" in OS.get_cmdline_user_args():
		var fl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SF_FLEET))
		for key in fl:
			for kind in SF_FOR:
				for pre in SF_FOR[kind]:
					if str(key).begins_with("sf_" + pre + "_") and ResourceLoader.exists(fl[key]["glb"]):
						if not _sf.has(kind):
							_sf[kind] = []
						_sf[kind].append([key, fl[key]])
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.albedo_color = Color(1.0, 0.55, 0.05)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.5, 0.02)
	_lamp_on.emission_energy_multiplier = 4.0
	_brake_on = StandardMaterial3D.new()
	_brake_on.albedo_color = Color(0.9, 0.05, 0.03)
	_brake_on.emission_enabled = true
	_brake_on.emission = Color(1.0, 0.04, 0.02)
	_brake_on.emission_energy_multiplier = 3.0


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Prof.add("traffic_phys", _p0)


func _physics_process_timed(delta: float) -> void:
	if streamer == null or player == null:
		return
	if streamer.stats["built"] + streamer.stats["unloaded"] != _built_seen:
		_built_seen = streamer.stats["built"] + streamer.stats["unloaded"]
		_index()
	var me := player.global_position
	for v in vehicles.duplicate():
		if v["pos"].distance_to(me) > 480.0 or not is_instance_valid(v["road_node"]):
			_remove(v)
	var want := count
	var cd := Vector2(me.x, me.z).length()
	if cd < CENTRE_R:
		want = int(lerpf(float(busy), float(count), smoothstep(CENTRE_R * 0.5, CENTRE_R, cd)))
	want = maxi(4, int(round(want * _hour_k())))
	var tries := 0
	while vehicles.size() < want and tries < 8:
		tries += 1
		_spawn(me)
	_tick += 1
	_veh_grid.clear()
	for v in vehicles:
		var c := _cell(v["pos"])
		if not _veh_grid.has(c):
			_veh_grid[c] = []
		_veh_grid[c].append(v)
	_ped_t -= delta
	if _ped_t <= 0.0:                                       # (who's on the road on foot, a few times a second)
		_ped_t = 0.25
		_gather_peds()
	for i in vehicles.size():
		_drive(vehicles[i], delta, me, (i + _tick) % THINK_EVERY == 0 or not vehicles[i].has("target"))
	_collide(delta)
	for v in vehicles:
		if (v["pos"] as Vector3).distance_to(me) < 200.0:   # (lamps only where they can be seen)
			_lamps(v, delta)


## The hour's share of the busy count (BY_HOUR), from the city's clock; 1 without one.
func _hour_k() -> float:
	var city = get_parent()
	if city == null or not ("fines" in city) or city.fines == null:
		return 1.0
	var h: float = fposmod(float(city.fines.sim.minute) / 60.0, 24.0)
	var a := int(h)
	return lerpf(float(BY_HOUR[a]), float(BY_HOUR[(a + 1) % 24]), h - a)


## People on foot on the road now: the walkers crossing (city_walkers.gd "cross"), the citizens off the footpath.
func _gather_peds() -> void:
	_peds.clear()
	var city = get_parent()
	var w = city.get_node_or_null("Walkers") if city else null
	if w and "people" in w:
		for q in w.people:
			if q["state"] == "cross" and (q["node"] as Node3D).visible:
				_peds.append((q["node"] as Node3D).global_position)


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


## What's in the 3×3 cells round a place (a grid of vehicles or signals).
static func _near(grid: Dictionary, p: Vector3) -> Array:
	var c := _cell(p)
	var out: Array = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(c.x + dx, c.y + dz)
			if grid.has(k):
				out.append_array(grid[k])
	return out


func _index() -> void:
	ends.clear()
	signals.clear()
	for k in streamer.loaded:
		var node: Node3D = streamer.loaded[k]
		for r in node.get_meta("roads", []):
			if not r["c"] in DRIVE or r.get("fly", false):
				continue
			var p: PackedFloat32Array = r["p"]
			if p.size() < 6:
				continue
			r["node"] = node
			for at_end in [false, true]:
				var i: int = (p.size() / 3 - 1) if at_end else 0
				var key := Vector2i(roundi(p[i * 3]), roundi(p[i * 3 + 2]))
				if not ends.has(key):
					ends[key] = []
				ends[key].append([r, at_end])
		signals.append_array(node.get_meta("signals", []))
	sig_grid.clear()
	for sg in signals:
		var c := _cell(sg[0])
		if not sig_grid.has(c):
			sig_grid[c] = []
		sig_grid[c].append(sg)


static func _pt(p: PackedFloat32Array, i: int) -> Vector3:
	return Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])


func _spawn(me: Vector3) -> void:
	if ends.is_empty():
		return
	var keys := ends.keys()
	var e: Array = ends[keys[_rng.randi() % keys.size()]]
	var pick: Array = e[_rng.randi() % e.size()]
	var r: Dictionary = pick[0]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var dir := 1 if not pick[1] else -1
	if int(r["o"]) == 1 and dir < 0:
		dir = 1
	var i0 := 0 if dir > 0 else n - 1
	var at := _pt(p, i0)
	for o in _near(_veh_grid, at):                          # (never on top of one already there: one waiting at the end)
		if (o["pos"] as Vector3).distance_to(at) < 10.0:
			return
	var d := at.distance_to(me)
	var behind := (at - me).dot(player.call("forward") if player.has_method("forward") else Vector3.ZERO) < 0.0
	if d > 400.0 or d < (50.0 if behind else 140.0):
		return
	var central := Vector2(me.x, me.z).length() < CENTRE_R
	if not r["c"] in ["trunk", "primary", "secondary", "tertiary"] and _rng.randf() < (0.35 if central else 0.55):
		return                                                  # most traffic is on the bigger roads
	var big: bool = r["c"] in ["trunk", "primary", "secondary"]
	var roll := _rng.randf()
	var kind := "hatchback" if roll < 0.32 else ("sedan" if roll < 0.55 else ("auto" if roll < 0.75 else ("taxi" if roll < 0.85 else "car")))
	if big and roll > 0.85:
		kind = "bus" if _rng.randf() < 0.5 else "lorry"
	if kind == "car":
		kind = "hatchback"
	if not Fleet.has(kind):
		return
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	var dims: Vector3 = DIMS[kind]
	var sf: Array = []
	if _sf.has(kind) and _rng.randf() < SF_SHARE:
		sf = _sf[kind][_rng.randi() % _sf[kind].size()]
		if SF_PREFER.has(kind) and _rng.randf() < float(SF_PREFER[kind][1]):
			for se in _sf[kind]:
				if se[0] == SF_PREFER[kind][0]:
					sf = se
		dims = Vector3(float(sf[1]["w"]), float(sf[1]["h"]), float(sf[1]["len"]))
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = dims
	cs.shape = bx
	cs.position = Vector3(0, dims.y * 0.5 + 0.25, 0)
	body.add_child(cs)
	var lamps := {}
	if sf.is_empty():
		body.add_child(Fleet.model(kind, Fleet.paint_for(kind, _rng)))
	else:
		body.add_child(_sf_model(str(sf[1]["glb"]), lamps))
	add_child(body)
	var driver := "commercial" if kind in ["bus", "lorry", "taxi"] or (kind == "auto" and _rng.randf() < 0.6) else _pick_driver()
	var v := {"body": body, "kind": kind, "road": r, "road_node": r["node"], "dir": dir, "i": i0, "t": 0.0,
		"speed": float(CRUISE.get(r["c"], 8.0)) * 0.6, "half": dims.z * 0.5, "w": dims.x * 0.5, "pos": at, "fwd": Vector3.FORWARD,
		"wait": 0.0, "off": Vector3.ZERO, "yaw": 0.0, "push": Vector3.ZERO, "spin": 0.0, "stunned": 0.0, "dents": {},
		"driver": driver, "d": DRIVERS[driver], "pass": 0.0, "held": 0.0, "lamps": lamps, "blink": 0.0}
	vehicles.append(v)
	_place(v)


## A pack vehicle as it is (+Z its nose, on y 0), and its lamps found: indicators left and right, brake lamps.
func _sf_model(path: String, lamps: Dictionary) -> Node3D:
	if not _sf_scenes.has(path):
		_sf_scenes[path] = load(path)
	var root := Node3D.new()
	var m := (_sf_scenes[path] as PackedScene).instantiate() as Node3D
	m.rotation.y = -PI * 0.5                    # (the pack's nose +X → +Z)
	root.add_child(m)
	lamps["l"] = []
	lamps["r"] = []
	lamps["brake"] = []
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if gi.get_aabb().size.length() < 1.0 else gi.cast_shadow
		var nm := String(gi.name).to_lower() + "|" + String(gi.get_parent().name).to_lower()
		if nm.contains("turn_l"):
			lamps["l"].append(gi)
		elif nm.contains("turn_r"):
			lamps["r"].append(gi)
		elif nm.contains("light_break") or nm.contains("light_brake"):
			lamps["brake"].append(gi)
	return root


## Its lamps: the indicator on the way it's about to turn (or pulling out round a stopped one), blinking; the brake
## lamps lit while it slows or stands.
func _lamps(v: Dictionary, delta: float) -> void:
	var lm: Dictionary = v.get("lamps", {})
	if lm.is_empty():
		return
	var turn := float(v.get("turn", 0.0))
	if float(v.get("pass", 0.0)) > 0.2 and float(v.get("pass", 0.0)) < 2.8:
		turn = -1.0                                           # (out to the right, round it)
	v["blink"] = fposmod(float(v["blink"]) + delta, 0.7)
	var on := float(v["blink"]) < 0.35
	for side in ["l", "r"]:
		var lit: bool = on and ((side == "l" and turn > 0.3) or (side == "r" and turn < -0.3))
		for gi in lm[side]:
			if is_instance_valid(gi):
				(gi as MeshInstance3D).material_override = _lamp_on if lit else null
	var sp := float(v["speed"])                               # (slowing, more than 0.8 m/s², or standing: lit,
	var slowing := (float(v.get("prev_speed", sp)) - sp) / maxf(delta, 0.001) > 0.8   #  and held a moment after)
	v["prev_speed"] = sp
	v["brake_hold"] = 0.5 if slowing else maxf(float(v.get("brake_hold", 0.0)) - delta, 0.0)
	var braking: bool = float(v["brake_hold"]) > 0.0 or sp < 0.3
	if braking != bool(v.get("braking", false)):
		v["braking"] = braking
		for gi in lm["brake"]:
			if is_instance_valid(gi):
				(gi as MeshInstance3D).material_override = _brake_on if braking else null


func _pick_driver() -> String:
	var roll := _rng.randf()
	for dm in DRIVER_MIX:
		roll -= float(dm[1])
		if roll <= 0.0:
			return str(dm[0])
	return "normal"


func _remove(v: Dictionary) -> void:
	if is_instance_valid(v["body"]):
		v["body"].queue_free()
	if v.has("out") and is_instance_valid(v["out"]):
		v["out"].queue_free()
	vehicles.erase(v)


## Lane offset to the driver's left: half a carriageway's lane on two-way roads, the left lane on one-ways. Where
## there's room, the lane keeps clear of the cars parked along the kerb (city_streamer.gd _park_on_road sets a car's
## middle 0.45 m in from the edge: its side 1.35 m in), its middle PARK_CLEAR from the edge; a narrow street keeps
## its own lane (there's no room for both: you squeeze past, as in Coimbatore).
const PARK_CLEAR := 2.6


static func _lane(r: Dictionary) -> float:
	var half: float = float(r["w"]) * 0.5
	if int(r["o"]) == 1:                                  # (+ is left: the left lane, by the kerb, not the median)
		var l := half - minf(1.75, half * 0.5)
		return minf(l, half - PARK_CLEAR) if half - PARK_CLEAR >= 0.0 else l
	var two := minf(half * 0.5, 1.75 if half < 5.0 else 3.5 * 0.5 + (1.75 if half > 6.5 else 0.0))
	return minf(two, half - PARK_CLEAR) if half - PARK_CLEAR >= 1.2 else two


## Position on the current road piece: segment i → i+dir, fraction t; lane to the left of travel.
func _place(v: Dictionary) -> void:
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var i: int = v["i"]
	var j: int = i + int(v["dir"])
	var n := p.size() / 3
	if j < 0 or j >= n:                         # stopped at the very end of its piece: hold there
		j = i
		i = i - int(v["dir"])
		v["t"] = 1.0
	var a := _pt(p, i)
	var b := _pt(p, j)
	var fwd := (b - a)
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var left := Vector3(flat.z, 0, -flat.x)
	var c := a.lerp(b, float(v["t"])) + left * (_lane(r) - float(v.get("pass", 0.0))) + Vector3(0, LIFT, 0)
	v["pos"] = c
	v["fwd"] = flat
	c += v.get("off", Vector3.ZERO)
	var basis := Basis.looking_at(-flat, Vector3.UP).rotated(Vector3.UP, float(v.get("yaw", 0.0)))
	var pitch := atan2(b.y - a.y, Vector2(b.x - a.x, b.z - a.z).length())
	basis = basis.rotated(left, -pitch) if absf(pitch) < 0.3 else basis
	var body: AnimatableBody3D = v["body"]
	body.global_transform = Transform3D(basis, c)


## Where to go at the end of this piece: another road meeting here (not straight back), mostly the straightest,
## big roads preferred; at a dead end, turn round.
func _next(v: Dictionary) -> bool:
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var idx := n - 1 if int(v["dir"]) > 0 else 0
	var o: Array = v["pick"] if v.get("pick_road") == r else _choose(v)
	v.erase("pick_road")
	if o.is_empty():
		if int(r["o"]) == 1:
			return false
		v["dir"] = -int(v["dir"])                                # dead end: turn round
		v["i"] = idx
		v["t"] = 0.0
		return true
	v["road"] = o[1]
	v["road_node"] = o[1]["node"]
	v["dir"] = o[2]
	v["i"] = o[3]
	v["t"] = 0.0
	v["turn_after"] = 2.0                                     # (the indicator a moment more, through the turn)
	return true


## Where to go at this piece's end (a road meeting there, not straight back; mostly the straightest, the big roads
## preferred): [weight, road, dir, start index], or [] at a dead end. Chosen ~30 m before (so it can indicate):
## v["pick"], and which way it turns, v["turn"] (+ left, - right).
func _choose(v: Dictionary) -> Array:
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var at_end: bool = int(v["dir"]) > 0
	var idx := n - 1 if at_end else 0
	var here := _pt(p, idx)
	var last_dir := here - _pt(p, idx - int(v["dir"]))
	last_dir = Vector3(last_dir.x, 0, last_dir.z).normalized()
	var key := Vector2i(roundi(here.x), roundi(here.z))
	var opts: Array = []
	for dk in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for c in ends.get(key + dk, []):
			var r2: Dictionary = c[0]
			if r2 == r:
				continue
			var dir2 := -1 if c[1] else 1                    # leaving from that end
			if int(r2["o"]) == 1 and dir2 < 0:
				continue
			var p2: PackedFloat32Array = r2["p"]
			var i2: int = 0 if dir2 > 0 else p2.size() / 3 - 1
			var out := _pt(p2, i2 + dir2) - _pt(p2, i2)
			out = Vector3(out.x, 0, out.z).normalized()
			var straight: float = out.dot(last_dir)
			if straight < -0.6:
				continue
			var w := (1.0 + 3.0 * maxf(straight, 0.0)) * float(BIG.get(r2["c"], 1.0))
			opts.append([w, r2, dir2, i2, last_dir.cross(out).y])
	var pick: Array = []
	if not opts.is_empty():
		var total := 0.0
		for o in opts:
			total += o[0]
		var roll := _rng.randf() * total
		pick = opts[opts.size() - 1]
		for o in opts:
			roll -= o[0]
			if roll <= 0.0:
				pick = o
				break
	v["pick"] = pick
	v["pick_road"] = r
	v["turn"] = (-1.0 if float(pick[4]) < 0.0 else 1.0) if not pick.is_empty() and absf(float(pick[4])) > 0.35 else 0.0
	return pick


## You hit one: it is shoved the way you pushed it, as much as the two masses share it (a bus barely moves, an
## auto is knocked aside and spun), slides to a stop on its tyres, and its driver waits a few seconds before
## easing back into the lane. `vel` is your velocity just before, `normal` the way it pushed you back. Returns
## the speed your vehicle keeps along the hit (the share of a bodies-together crash), or −1 if it wasn't one of ours.
func struck(body: Object, vel: Vector3, normal: Vector3, my_mass: float) -> float:
	for v in vehicles:
		if v["body"] != body:
			continue
		var m: float = MASS.get(v["kind"], 1200.0)
		var n := Vector3(-normal.x, 0, -normal.z).normalized()        # (it goes the other way)
		var theirs: Vector3 = (v["fwd"] as Vector3) * float(v["speed"]) + (v["push"] as Vector3)
		var closing := maxf((vel - theirs).dot(n), 0.0)
		var common := closing * my_mass / (my_mass + m)                  # (a crumpling hit: they move off together)
		if common < 0.2:
			return -1.0
		v["push"] = theirs + n * common * 1.1                            # (a little faster: they part)
		var arm: Vector3 = v["fwd"]                                      # off-centre hits spin it
		v["spin"] = clampf(float(v["spin"]) + arm.cross(n).y * common * 0.25, -2.0, 2.0)
		v["stunned"] = maxf(float(v["stunned"]), 3.0 + minf(closing, 10.0) * 0.4)
		v["speed"] = 0.0
		print("TRAFFIC struck %s: shoved %.1f m/s, spin %.2f rad/s" % [v["kind"], (v["push"] as Vector3).length(), v["spin"]])
		return theirs.dot(n) + common * 0.9
	return -1.0


## Its dented meshes (dents.gd keeps the originals there).
func dents_of(body: Object) -> Dictionary:
	for v in vehicles:
		if v["body"] == body:
			return v["dents"]
	return {}


func is_vehicle(body: Object) -> bool:
	for v in vehicles:
		if v["body"] == body:
			return true
	return false


## After a hit: the shove slides out (tyres, about 0.7 g sideways), then the offset eases back.
func _knocked(v: Dictionary, delta: float) -> bool:
	var push: Vector3 = v["push"]
	var off: Vector3 = v["off"]
	if push.length() > 0.01 or absf(float(v["spin"])) > 0.01:
		var fwd: Vector3 = v["fwd"]
		var along := push.dot(fwd)                                        # (forward: on along its road)
		if along > 0.0:
			_advance(v, along * delta)
			off += (push - fwd * along) * delta
		else:
			off += push * delta
		v["yaw"] = float(v["yaw"]) + float(v["spin"]) * delta
		v["push"] = push.move_toward(Vector3.ZERO, 7.0 * delta)
		v["spin"] = move_toward(float(v["spin"]), 0.0, 3.0 * delta)
		v["off"] = off
		v["speed"] = 0.0
		_place(v)
		return true
	if float(v["stunned"]) > 0.0:
		v["stunned"] = float(v["stunned"]) - delta
		v["speed"] = 0.0
		_place(v)
		if float(v["stunned"]) <= 0.0 and v.has("out"):        # (back in: on his way)
			if is_instance_valid(v["out"]):
				v["out"].queue_free()
			v.erase("out")
		return true
	if off.length() > 0.01 or absf(float(v["yaw"])) > 0.01:              # back into the lane as it moves off
		var k := minf(1.0, delta * 0.6)
		v["off"] = off.lerp(Vector3.ZERO, k).move_toward(Vector3.ZERO, delta * 0.3)
		v["yaw"] = move_toward(lerpf(float(v["yaw"]), 0.0, k), 0.0, delta * 0.1)
	return false


func _drive(v: Dictionary, delta: float, me: Vector3, think := true) -> void:
	if _knocked(v, delta):
		return
	if not think:
		var i0: int = v["i"]
		if i0 != (int((v["road"]["p"] as PackedFloat32Array).size() / 3) - 1 if int(v["dir"]) > 0 else 0):
			_move(v, float(v["target"]), delta)
			return
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var dd: Dictionary = v["d"]
	var target: float = CRUISE.get(r["c"], 8.0) * (0.75 if v["kind"] in ["bus", "lorry", "auto"] else 1.0) * (1.0 - 0.2 * wet) \
		* float(dd["cruise"])
	var pos: Vector3 = v["pos"]
	var fwd: Vector3 = v["fwd"]
	# the road ahead: slow for the end of the piece when it bends
	var to_end := 0.0
	var i: int = v["i"]
	var last := n - 1 if int(v["dir"]) > 0 else 0
	if i == last:
		_place(v)
		if not _next(v):
			return
		r = v["road"]
		p = r["p"]
		n = p.size() / 3
		i = v["i"]
		last = n - 1 if int(v["dir"]) > 0 else 0
	to_end = _pt(p, i).distance_to(_pt(p, i + int(v["dir"]))) * (1.0 - float(v["t"]))
	var k := i + int(v["dir"])
	while k != last and to_end < 40.0:
		to_end += _pt(p, k).distance_to(_pt(p, k + int(v["dir"])))
		k += int(v["dir"])
	if to_end < 30.0 and v.get("pick_road") != r:          # (the way it'll go, chosen now: the indicator on)
		_choose(v)
	if v.get("pick_road") != r and float(v.get("turn_after", 0.0)) <= 0.0:
		v["turn"] = 0.0
	v["turn_after"] = maxf(float(v.get("turn_after", 0.0)) - delta * (THINK_EVERY if think else 1.0), 0.0)
	if to_end < 18.0:                                     # (a bus or lorry slower into the turn: its size)
		target = minf(target, (6.0 + to_end * 0.35) * float(DYN.get(v["kind"], [0, 0, 1.0])[2]))
	# vehicles and you ahead in my lane
	var gap := 999.0
	var blocker = null
	var side := Vector3(fwd.z, 0, -fwd.x)
	var spd0: float = v["speed"]
	var look_m := maxf(12.0, spd0 * float(dd["look"]))
	for o in _near(_veh_grid, pos):
		if o == v:
			continue
		var rel: Vector3 = o["pos"] - pos
		var along := rel.dot(fwd)
		var tie := along > -0.5 and along <= 0.0 and (v["body"] as Object).get_instance_id() > (o["body"] as Object).get_instance_id()
		if (along > 0.0 or tie) and along < 40.0 and absf(rel.dot(side)) < 1.2 + float(o.get("w", 0.9)) + float(v.get("w", 0.9)) * 0.3:
			var g := along - float(o["half"]) - float(v["half"])
			if g < gap:
				gap = g
				blocker = o
			continue
		# across my way at a junction: a vehicle coming over it. Where our two lines meet, who's there first? The
		# later one gives way (it waits for the other to be by), never both into the same place.
		var ofwd: Vector3 = o["fwd"]
		if absf(ofwd.dot(fwd)) > 0.6 or along < 0.0 or along > look_m + 10.0:
			continue
		var den := fwd.x * ofwd.z - fwd.z * ofwd.x
		if absf(den) < 0.05:
			continue
		var d0: Vector3 = o["pos"] - pos
		var tm := (d0.x * ofwd.z - d0.z * ofwd.x) / den           # (along my way to the crossing point, m)
		var to := (d0.x * fwd.z - d0.z * fwd.x) / den             # (along its way, m; negative: it's past it)
		if tm < 0.0 or tm > look_m + 6.0 or to < -float(o["half"]) - 2.0 or to > 30.0:
			continue
		var my_t := tm / maxf(spd0, 1.0)
		var its_t := maxf(to, 0.0) / maxf(float(o["speed"]), 0.5)
		if to < 2.5 or my_t > its_t - 0.3:                       # (it's there first, or it's in it now: I wait)
			var g2 := tm - 4.0 - float(v["half"])
			if g2 < gap:
				gap = g2
	for o in _near(_veh_grid, pos):                           # any other way two would meet in the next 1.5 s (a bus
		if o == v or ((o["pos"] as Vector3) - pos).length() > 25.0:   # swinging round a corner, one turning across): the
			continue                                              # one with the lesser claim waits for it to clear
		var tw := _will_meet(v, o)
		if tw >= 0.0 and (_claim(v) < _claim(o) or float(o["speed"]) < 1.0):   # (one standing in the way: always)
			gap = minf(gap, 0.0 if tw <= 1.6 else maxf(0.0, spd0 * tw - 2.0))   # (soon: stop and let it by)
	if to_end < 30.0:                                         # round the corner: one standing just past my road's end
		var endp := _pt(p, last)                              # (out of the straight line I look along)
		for o in _near(_veh_grid, endp):
			if o == v:
				continue
			var de := Vector2((o["pos"] as Vector3).x - endp.x, (o["pos"] as Vector3).z - endp.z).length()
			if de < 9.0 and ((o["pos"] as Vector3) - pos).dot(fwd) > -2.0 and float(o["speed"]) < 2.0:
				gap = minf(gap, to_end + de - float(o["half"]) - float(v["half"]))
	for pp in _peds:                                          # someone crossing in front of me: I stop for them
		var relq: Vector3 = (pp as Vector3) - pos
		var aq := relq.dot(fwd)
		if aq > 0.0 and aq < look_m + 8.0 and absf(relq.dot(side)) < float(v.get("w", 0.9)) + 1.6:
			gap = minf(gap, aq - float(v["half"]) - 1.5)
	var relp := me - pos
	var alongp := relp.dot(fwd)
	if alongp > 0.0 and alongp < 40.0 and absf(relp.dot(Vector3(fwd.z, 0, -fwd.x))) < 2.4:
		gap = minf(gap, alongp - 2.4 - float(v["half"]))
	if gap < 40.0:                                        # (as far behind as this driver keeps: a time gap)
		target = minf(target, maxf(0.0, (gap - 3.0) / float(dd["headway"])))
		var can_brake: float = float(DYN.get(v["kind"], [2.0, 5.0, 1.0])[1]) * float(dd["brake"]) * 1.6
		target = minf(target, sqrt(2.0 * can_brake * maxf(gap - 2.0, 0.0)))   # (never faster than it can stop in)
	_pass(v, blocker, gap, delta * (THINK_EVERY if think else 1.0))
	# red (or amber, if not already committed) signals facing me, just ahead
	for s in _near(sig_grid, pos):
		var sp: Vector3 = s[0]
		var rel2: Vector3 = sp - pos
		var ahead2 := rel2.dot(fwd)
		if ahead2 < 2.0 or ahead2 > 30.0 or absf(rel2.dot(Vector3(fwd.z, 0, -fwd.x))) > 12.0:
			continue
		var face := Vector3(sin(float(s[1])), 0, cos(float(s[1])))
		if face.dot(fwd) > -0.7:
			continue
		var st: int = Streamer.signal_state(float(s[2]))
		var amber_go: bool = bool(dd["amber"]) and ahead2 < 12.0 + spd0 * 0.6   # (too near to stop: on through it)
		if st == 2 or (st == 1 and not amber_go):
			target = minf(target, maxf(0.0, (ahead2 - 6.0) * 0.5))
	if v.has("blind"):                                     # (testing: a driver who doesn't look: --traffictest's crashes)
		target = float(v["blind"])
	v["target"] = target
	if gap < 1.0 and float(v["speed"]) < 3.0 and not v.has("blind"):   # (creeping up to the one ahead: stopped, not into it)
		v["speed"] = 0.0
	_move(v, target, delta)


func _move(v: Dictionary, target: float, delta: float) -> void:
	var spd: float = v["speed"]
	var dy: Array = DYN.get(v["kind"], [2.0, 5.0, 1.0])
	var dd: Dictionary = v.get("d", DRIVERS["normal"])
	var brake: float = float(dy[1]) * float(dd["brake"])
	if target < spd - 4.0:                                    # (a sudden need: harder, as hard as it can)
		brake *= 1.6
	spd = move_toward(spd, target, delta * (brake if target < spd else float(dy[0]) * float(dd["accel"])))
	v["speed"] = spd
	_advance(v, spd * delta)
	_place(v)


## Round a vehicle stopped in my lane that isn't going anywhere (crashed, its driver out, broken down): after a few
## seconds behind it, out to the right as far as a lane, when nothing's coming the other way, by it, and back in.
func _pass(v: Dictionary, blocker, gap: float, dt: float) -> void:
	var want := 0.0
	if blocker != null and gap < 12.0 and float(blocker["speed"]) < 0.5 and float(blocker["stunned"]) > 0.0:
		v["held"] = float(v["held"]) + dt
		if float(v["held"]) > 3.0 and int(v["road"]["o"]) != 1 or float(v["held"]) > 3.0 and float(v["road"]["w"]) > 7.0:
			var clear := true
			var fwd: Vector3 = v["fwd"]
			for o in _near(_veh_grid, v["pos"]):           # (the other way, within 35 m: wait)
				if o != v and (o["fwd"] as Vector3).dot(fwd) < -0.6 and ((o["pos"] as Vector3) - (v["pos"] as Vector3)).dot(fwd) > -5.0 \
						and ((o["pos"] as Vector3) - (v["pos"] as Vector3)).length() < 35.0:
					clear = false
			if clear:
				want = 3.0
	elif float(v.get("pass", 0.0)) > 0.0 and blocker != null and gap < 4.0:
		want = float(v["pass"])                             # (still alongside it)
	else:
		v["held"] = 0.0
	v["pass"] = move_toward(float(v.get("pass", 0.0)), want, dt * 1.2)


## Two of them touching (their boxes overlap, flat): a crash, once (not again while they stay in contact). How
## hard by how fast they closed on each other along the hit, and their masses: low (a bump, a knock), medium (both
## shoved and turned, dented, the drivers out), high (spun, badly dented, a loud one). Momentum shared as in a real
## crumpling hit (they part at about their common speed), off-centre hits turning them.
func _collide(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for v in vehicles:
		for o in _near(_veh_grid, v["pos"]):
			if o == v or (o["body"] as Object).get_instance_id() < (v["body"] as Object).get_instance_id():
				continue
			var pa: Vector3 = v["pos"] + v.get("off", Vector3.ZERO)
			var pb: Vector3 = o["pos"] + o.get("off", Vector3.ZERO)
			if Vector2(pa.x - pb.x, pa.z - pb.z).length() > float(v["half"]) + float(o["half"]) + 0.5:
				continue
			var n := _overlap(v, o)
			var key := "%d,%d" % [(v["body"] as Object).get_instance_id(), (o["body"] as Object).get_instance_id()]
			if n == Vector3.ZERO:
				if _touching.has(key) and now - float(_touching[key]) > 1.5:
					_touching.erase(key)
				continue
			var fresh := not _touching.has(key)
			_touching[key] = now
			if fresh and _closing(v, o, n) >= 1.0:              # (a touch in a queue isn't a crash)
				_crash(v, o, n, (pa + pb) * 0.5)


## When (s, within 1.5 s) `a` and `b` would be in each other going on as they are now; -1 if they won't. (Already in
## each other: not counted here, _collide has it.)
func _will_meet(a: Dictionary, b: Dictionary) -> float:
	if _overlap(a, b) != Vector3.ZERO:
		return -1.0
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	var va: Vector3 = (a["fwd"] as Vector3) * maxf(float(a["speed"]), 1.5)    # (a stopped one as about to go)
	var vb: Vector3 = (b["fwd"] as Vector3) * float(b["speed"])
	for k in [0.4, 0.8, 1.2, 1.6, 2.0, 2.4]:
		a["pos"] = pa + va * k
		b["pos"] = pb + vb * k
		var hit := _overlap(a, b) != Vector3.ZERO
		a["pos"] = pa
		b["pos"] = pb
		if hit:
			return k
	return -1.0


## Right of way where two would meet: the bigger road's, then the one already going faster, then (a tie) a fixed
## order; a vehicle stopped after a crash claims nothing (it isn't moving off).
func _claim(v: Dictionary) -> float:
	if float(v["stunned"]) > 0.0:
		return 1e6                                            # (others must go round it, not wait for it to give way)
	return float(BIG.get(v["road"]["c"], 1.0)) * 100.0 + float(v["speed"]) * 5.0 + float((v["body"] as Object).get_instance_id() % 997) * 0.001


## The way to push `a` off `b` if their footprints overlap (flat boxes, separating axes), or ZERO.
func _overlap(a: Dictionary, b: Dictionary) -> Vector3:
	var ca: Vector3 = a["pos"] + a.get("off", Vector3.ZERO)
	var cb: Vector3 = b["pos"] + b.get("off", Vector3.ZERO)
	var fa: Vector3 = (a["fwd"] as Vector3).rotated(Vector3.UP, float(a.get("yaw", 0.0)))
	var fb: Vector3 = (b["fwd"] as Vector3).rotated(Vector3.UP, float(b.get("yaw", 0.0)))
	var axes := [fa, Vector3(fa.z, 0, -fa.x), fb, Vector3(fb.z, 0, -fb.x)]
	var ext_a := [float(a["half"]), float(a.get("w", 0.9))]
	var ext_b := [float(b["half"]), float(b.get("w", 0.9))]
	var d := cb - ca
	d.y = 0.0
	var best := INF
	var best_ax := Vector3.ZERO
	for ax in axes:
		var ra: float = ext_a[0] * absf(fa.dot(ax)) + ext_a[1] * absf(Vector3(fa.z, 0, -fa.x).dot(ax))
		var rb: float = ext_b[0] * absf(fb.dot(ax)) + ext_b[1] * absf(Vector3(fb.z, 0, -fb.x).dot(ax))
		var pen: float = ra + rb - absf(d.dot(ax))
		if pen <= 0.0:
			return Vector3.ZERO
		if pen < best:
			best = pen
			best_ax = ax if d.dot(ax) < 0.0 else -ax           # (from b toward a)
	return best_ax


func _closing(a: Dictionary, b: Dictionary, n: Vector3) -> float:
	var va: Vector3 = (a["fwd"] as Vector3) * float(a["speed"]) + (a["push"] as Vector3)
	var vb: Vector3 = (b["fwd"] as Vector3) * float(b["speed"]) + (b["push"] as Vector3)
	return maxf((vb - va).dot(n), 0.0)


func _crash(a: Dictionary, b: Dictionary, n: Vector3, at: Vector3) -> void:
	var ma: float = MASS.get(a["kind"], 1200.0)
	var mb: float = MASS.get(b["kind"], 1200.0)
	var va: Vector3 = (a["fwd"] as Vector3) * float(a["speed"]) + (a["push"] as Vector3)
	var vb: Vector3 = (b["fwd"] as Vector3) * float(b["speed"]) + (b["push"] as Vector3)
	var closing := maxf((vb - va).dot(n), 0.0)                 # (n points from b to a: b coming on at a)
	var common := (ma * va + mb * vb) / (ma + mb)              # (a crumpling hit: they move off together)
	var sev := clampf(closing / 14.0, 0.0, 1.0)
	var level := "low" if closing < 3.0 else ("medium" if closing < 8.0 else "high")
	var info := "TRAFFIC crash %s %s-%s, closing %.1f m/s at %s (speeds %.1f/%.1f, headings %.2f, roads %s/%s same %s, i %d/%d, claims %.0f/%.0f, targets %.1f/%.1f)" % [
		level, a["kind"], b["kind"], closing, str(at.snapped(Vector3.ONE * 0.1)), float(a["speed"]), float(b["speed"]),
		(a["fwd"] as Vector3).dot(b["fwd"]), a["road"]["c"], b["road"]["c"], str(a["road"] == b["road"]), int(a["i"]), int(b["i"]),
		_claim(a), _claim(b), float(a.get("target", -1.0)), float(b.get("target", -1.0))]
	for pr in [[a, ma, mb, 1.0], [b, mb, ma, -1.0]]:
		var v: Dictionary = pr[0]
		var share: float = float(pr[2]) / (float(pr[1]) + float(pr[2]))   # (the lighter one moves more)
		var vel: Vector3 = (v["fwd"] as Vector3) * float(v["speed"]) + (v["push"] as Vector3)
		var shove := (common - vel) * minf(1.0, 0.6 + share) + n * float(pr[3]) * (0.6 + closing * share * 0.35)
		v["push"] = vel + shove
		v["speed"] = 0.0
		var arm: Vector3 = v["fwd"]
		v["spin"] = clampf(float(v["spin"]) + arm.cross(n * float(pr[3])).y * closing * share * 0.3, -2.5, 2.5)
		v["stunned"] = maxf(float(v["stunned"]), {"low": 2.5, "medium": 9.0, "high": 16.0}[level])
		if level != "low" and is_instance_valid(v["body"]):
			Dents.dent(v["body"], at + Vector3.UP * 0.7, n * float(pr[3]) * -1.0, 0.5 + sev * 0.8, 0.05 + sev * 0.28, v["dents"])
		if level != "low":
			_driver_out(v, at)
	_crash_sound(at, sev)
	crashes.append([Time.get_ticks_msec() / 1000.0, "%s-%s" % [a["kind"], b["kind"]], level, closing])
	print(info)
	var city = get_parent()
	var w = city.get_node_or_null("Walkers") if city else null
	if w and w.has_method("look_at_crash"):
		w.look_at_crash(at, sev)
	if city and "car" in city and city.car and level == "high" and city.has_method("shake") \
			and (city.car as Node3D).global_position.distance_to(at) < 30.0:
		city.shake(0.4 * sev)


## A crash's sound: a thump and the crunch of panels, louder and longer the harder it was (made here, no file).
var _crash_wav: AudioStreamWAV

func _crash_sound(at: Vector3, sev: float) -> void:
	if _crash_wav == null:
		var rate := 22050
		var nsm := int(rate * 0.9)
		var data := PackedByteArray()
		data.resize(nsm * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var lp := 0.0
		for i in nsm:
			var t := float(i) / rate
			var thump := sin(TAU * 55.0 * t) * exp(-t * 18.0)
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)       # (the crunch: noise, darker)
			var crunch := lp * exp(-t * 5.0) * (0.6 + 0.4 * sin(TAU * 13.0 * t))
			var tink := rng.randf_range(-1.0, 1.0) * exp(-maxf(t - 0.12, 0.0) * 14.0) * (0.25 if t > 0.12 else 0.0)
			data.encode_s16(i * 2, int(clampf((thump * 0.9 + crunch * 0.7 + tink) * 0.8, -1.0, 1.0) * 32000.0))
		_crash_wav = AudioStreamWAV.new()
		_crash_wav.format = AudioStreamWAV.FORMAT_16_BITS
		_crash_wav.mix_rate = rate
		_crash_wav.data = data
	var pl := AudioStreamPlayer3D.new()
	pl.stream = _crash_wav
	pl.volume_db = lerpf(-14.0, 6.0, sev)
	pl.pitch_scale = lerpf(1.25, 0.85, sev)                       # (a big one deeper)
	pl.unit_size = 12.0
	add_child(pl)
	pl.global_position = at
	pl.play()
	pl.finished.connect(pl.queue_free)


## A driver out of the vehicle after a crash that wasn't a mere knock: standing by the door, arguing, looking at
## the damage, back in when it moves off again.
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")

func _driver_out(v: Dictionary, at: Vector3) -> void:
	if v.has("out") and is_instance_valid(v["out"]):
		return
	var kk := "m%d" % (1 + _rng.randi() % 6)
	var path := "res://assets/people/crowd_%s.glb" % kk
	if not ResourceLoader.exists(path):
		return
	var person := (load(path) as PackedScene).instantiate() as Node3D
	add_child(person)
	var fwd: Vector3 = v["fwd"]
	var right := fwd.cross(Vector3.UP)
	var door: Vector3 = v["pos"] + v.get("off", Vector3.ZERO) + right * (float(v.get("w", 0.9)) + 0.6) + fwd * 0.4
	var g: float = streamer.height_at(door.x, door.z) if streamer else NAN
	person.global_position = Vector3(door.x, door.y if is_nan(g) else g, door.z)
	person.look_at(Vector3(at.x, person.global_position.y, at.z), Vector3.UP, true)
	var aps := person.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		var clip := "Talk"
		if CrowdClips.add(person, "m") and ap.has_animation("crowd/Argue"):
			clip = "crowd/Argue"
		if ap.has_animation(clip):
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
	v["out"] = person


## Along the road by `step` metres: on to the next piece at its end.
func _advance(v: Dictionary, step: float) -> void:
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var last := n - 1 if int(v["dir"]) > 0 else 0
	var i: int = v["i"]
	if i == last:
		return
	var guard := 0
	while step > 0.0 and guard < 8:
		guard += 1
		i = v["i"]
		var a := _pt(p, i)
		var b := _pt(p, i + int(v["dir"]))
		var L := maxf(a.distance_to(b), 0.01)
		var remain := L * (1.0 - float(v["t"]))
		if step < remain:
			v["t"] = float(v["t"]) + step / L
			step = 0.0
		else:
			step -= remain
			v["i"] = i + int(v["dir"])
			v["t"] = 0.0
			if int(v["i"]) == last:
				if not _next(v):
					v["speed"] = 0.0
					break
				r = v["road"]
				p = r["p"]
				n = p.size() / 3
				last = n - 1 if int(v["dir"]) > 0 else 0
