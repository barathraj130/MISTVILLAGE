extends Node3D
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
const LIFT := 0.09                         # road surface above its centreline points (= streamer RANK + 0.06)

@export var count := 36
var streamer
var player: Node3D
var vehicles: Array = []
var ends := {}                             # Vector2i (1 m grid) → [[road, at_end(bool)], ...]
var signals: Array = []
var _built_seen := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2026


func _physics_process(delta: float) -> void:
	if streamer == null or player == null:
		return
	if streamer.stats["built"] + streamer.stats["unloaded"] != _built_seen:
		_built_seen = streamer.stats["built"] + streamer.stats["unloaded"]
		_index()
	var me := player.global_position
	for v in vehicles.duplicate():
		if v["pos"].distance_to(me) > 480.0 or not is_instance_valid(v["road_node"]):
			_remove(v)
	var tries := 0
	while vehicles.size() < count and tries < 6:
		tries += 1
		_spawn(me)
	for v in vehicles:
		_drive(v, delta, me)


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
	var d := at.distance_to(me)
	var behind := (at - me).dot(player.call("forward") if player.has_method("forward") else Vector3.ZERO) < 0.0
	if d > 400.0 or d < (50.0 if behind else 140.0):
		return
	if not r["c"] in ["trunk", "primary", "secondary", "tertiary"] and _rng.randf() < 0.55:
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
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = dims
	cs.shape = bx
	cs.position = Vector3(0, dims.y * 0.5 + 0.25, 0)
	body.add_child(cs)
	body.add_child(Fleet.model(kind, Fleet.paint_for(kind, _rng)))
	add_child(body)
	var v := {"body": body, "kind": kind, "road": r, "road_node": r["node"], "dir": dir, "i": i0, "t": 0.0,
		"speed": float(CRUISE.get(r["c"], 8.0)) * 0.6, "half": dims.z * 0.5, "pos": at, "fwd": Vector3.FORWARD,
		"wait": 0.0}
	vehicles.append(v)
	_place(v)


func _remove(v: Dictionary) -> void:
	if is_instance_valid(v["body"]):
		v["body"].queue_free()
	vehicles.erase(v)


## Lane offset to the driver's left: half a carriageway's lane on two-way roads, the left lane on one-ways.
static func _lane(r: Dictionary) -> float:
	var half: float = float(r["w"]) * 0.5
	if int(r["o"]) == 1:
		return -half + minf(1.75, half * 0.5)
	return minf(half * 0.5, 1.75 if half < 5.0 else 3.5 * 0.5 + (1.75 if half > 6.5 else 0.0))


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
	var c := a.lerp(b, float(v["t"])) + left * _lane(r) + Vector3(0, LIFT, 0)
	v["pos"] = c
	v["fwd"] = flat
	var basis := Basis.looking_at(-flat, Vector3.UP)
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
	var at_end: bool = int(v["dir"]) > 0
	var idx := n - 1 if at_end else 0
	var here := _pt(p, idx)
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
			var straight: float = Vector3(out.x, 0, out.z).normalized().dot(v["fwd"])
			if straight < -0.6:
				continue
			var w := (1.0 + 3.0 * maxf(straight, 0.0)) * float(BIG.get(r2["c"], 1.0))
			opts.append([w, r2, dir2, i2])
	if opts.is_empty():
		if int(r["o"]) == 1:
			return false
		v["dir"] = -int(v["dir"])                                # dead end: turn round
		v["i"] = idx
		v["t"] = 0.0
		return true
	var total := 0.0
	for o in opts:
		total += o[0]
	var roll := _rng.randf() * total
	for o in opts:
		roll -= o[0]
		if roll <= 0.0:
			v["road"] = o[1]
			v["road_node"] = o[1]["node"]
			v["dir"] = o[2]
			v["i"] = o[3]
			v["t"] = 0.0
			return true
	return false


func _drive(v: Dictionary, delta: float, me: Vector3) -> void:
	var r: Dictionary = v["road"]
	var p: PackedFloat32Array = r["p"]
	var n := p.size() / 3
	var target: float = CRUISE.get(r["c"], 8.0) * (0.75 if v["kind"] in ["bus", "lorry", "auto"] else 1.0)
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
	if to_end < 18.0:
		target = minf(target, 6.0 + to_end * 0.35)
	# vehicles and you ahead in my lane
	var gap := 999.0
	for o in vehicles:
		if o == v:
			continue
		var rel: Vector3 = o["pos"] - pos
		var along := rel.dot(fwd)
		if along > 0.0 and along < 40.0 and absf(rel.dot(Vector3(fwd.z, 0, -fwd.x))) < 2.2:
			gap = minf(gap, along - float(o["half"]) - float(v["half"]))
	var relp := me - pos
	var alongp := relp.dot(fwd)
	if alongp > 0.0 and alongp < 40.0 and absf(relp.dot(Vector3(fwd.z, 0, -fwd.x))) < 2.4:
		gap = minf(gap, alongp - 2.4 - float(v["half"]))
	if gap < 40.0:
		target = minf(target, maxf(0.0, (gap - 4.0) * 0.55))
	# red (or amber, if not already committed) signals facing me, just ahead
	for s in signals:
		var sp: Vector3 = s[0]
		var rel2: Vector3 = sp - pos
		var ahead2 := rel2.dot(fwd)
		if ahead2 < 2.0 or ahead2 > 30.0 or absf(rel2.dot(Vector3(fwd.z, 0, -fwd.x))) > 12.0:
			continue
		var face := Vector3(sin(float(s[1])), 0, cos(float(s[1])))
		if face.dot(fwd) > -0.7:
			continue
		var st: int = Streamer.signal_state(float(s[2]))
		if st == 2 or (st == 1 and ahead2 > 12.0):
			target = minf(target, maxf(0.0, (ahead2 - 6.0) * 0.5))
	var spd: float = v["speed"]
	spd = move_toward(spd, target, delta * (5.0 if target < spd else 1.8))
	v["speed"] = spd
	# move along the polyline
	var step := spd * delta
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
	_place(v)
