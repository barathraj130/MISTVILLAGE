extends Node3D
## Buses, lorries, cars and auto-rickshaws in their own (left) lane. They slow and stop behind
## the jeep, never overtake, and loop within their stretch of road out of the player's sight.

const Prof := preload("res://scripts/drive/prof.gd")
const Route := preload("res://scripts/drive/route.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const Fleet := preload("res://scripts/drive/fleet.gd")
const LANE := 1.8
const KENNEY := "res://assets/drive/models/kenney/"
## Kenney Car Kit (CC0) models per traffic kind, with the real length they're scaled to.
const MODELS := {"car": [["sedan", 4.3], ["taxi", 4.3], ["suv", 4.6], ["van", 4.8]],
	"tractor": [["tractor", 3.9]]}

var route: Route
var jeep_d := 0.0                 # set by the game each frame
var jeep_lat := 0.0               # + = left of the road's direction
var jeep_pos := Vector3.ZERO
var vehicles: Array = []
var mat: StandardMaterial3D


func build(r) -> void:
	route = r
	mat = MB.vertex_color_material(0.6)
	var st := {}
	for s in route.stages:
		st[s["id"]] = s
	var gs: float = route.marks["ghat_start"]
	var ge: float = route.marks["ghat_end"]
	var L: float = route.length
	# kind, direction (+1 uphill), stretch start, stretch end, cruise m/s, starting distance
	var specs := [
		["auto", 1, 60.0, st["coimbatore"]["end"], 8.0, 320.0],
		["auto", -1, 60.0, st["coimbatore"]["end"], 8.0, 560.0],
		["bus", 1, 200.0, st["foothills"]["end"], 13.0, 950.0],
		["car", -1, 100.0, st["mettupalayam"]["end"], 15.0, 1500.0],
		["tractor", 1, st["plains"]["start"], st["mettupalayam"]["end"], 5.0, st["plains"]["start"] + 900.0],
		["car", 1, 100.0, st["foothills"]["end"], 14.0, 1800.0],
		["lorry", 1, st["plains"]["start"], st["foothills"]["end"], 10.0, st["plains"]["start"] + 2200.0],
		["lorry", -1, 100.0, st["mettupalayam"]["end"], 12.0, 2400.0],
		["auto", 1, st["mettupalayam"]["start"], st["mettupalayam"]["end"], 7.5, st["mettupalayam"]["start"] + 60.0],
		["bus", -1, gs - 300.0, st["mist"]["end"], 8.5, gs + (ge - gs) * 0.55],
		["bus", -1, gs - 300.0, st["mist"]["end"], 8.5, gs + (ge - gs) * 0.15],
		["lorry", 1, gs - 150.0, st["kotagiri"]["start"], 5.0, gs + 260.0],
		["car", -1, st["mist"]["start"], L - 120.0, 10.0, st["mist"]["start"] + 300.0],
		["car", 1, st["kotagiri"]["start"], L - 120.0, 8.0, st["kotagiri"]["start"] + 160.0],
		["auto", -1, st["kotagiri"]["start"], L - 90.0, 7.0, st["kotagiri"]["start"] + 300.0],
	]
	for s in specs:
		_spawn(s[0], s[1], s[2], s[3], s[4], s[5])


func _spawn(kind: String, dir: int, d0: float, d1: float, cruise: float, start: float) -> void:
	var body := AnimatableBody3D.new()
	body.name = "%s_%d" % [kind, vehicles.size()]
	body.sync_to_physics = true
	var dims := {"bus": Vector3(2.5, 3.1, 10.5), "lorry": Vector3(2.55, 4.1, 10.2), "car": Vector3(1.7, 1.55, 3.9),
		"auto": Vector3(1.35, 1.75, 2.7), "tractor": Vector3(1.9, 2.4, 3.9)}
	var size: Vector3 = dims[kind]
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = Vector3(0, size.y * 0.5 + 0.1, 0)
	body.add_child(cs)
	# the Blender fleet where there is one (cars alternate hatchback / sedan), else the old models
	var fleet_kind: String = kind
	if kind == "car":
		fleet_kind = "hatchback" if vehicles.size() % 2 == 0 else "sedan"
	var rng := RandomNumberGenerator.new()
	rng.seed = vehicles.size() * 7919
	var paint := Fleet.paint_for(fleet_kind, rng)
	var model: Node3D = Fleet.model(fleet_kind, paint) if Fleet.has(fleet_kind) else _kenney(kind, vehicles.size())
	if model:
		body.add_child(model)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _truck_mesh(vehicles.size() % 4) if kind == "lorry" else call("_mesh_" + kind)
		mi.material_override = mat
		body.add_child(mi)
	if kind == "bus":
		var dest := Label3D.new()
		dest.text = "KOTAGIRI" if dir > 0 else "METTUPALAYAM"
		dest.font_size = 36
		dest.pixel_size = 0.006
		dest.modulate = Color(1.0, 0.7, 0.1)
		dest.double_sided = false
		dest.position = Vector3(0, 2.75, 5.27)
		dest.visibility_range_end = 80.0
		body.add_child(dest)
	add_child(body)
	var model_name: String = fleet_kind
	if not Fleet.has(fleet_kind) and MODELS.has(kind):
		var opts: Array = MODELS[kind]
		model_name = opts[vehicles.size() % opts.size()][0]
	vehicles.append({"body": body, "d": start, "dir": dir, "d0": d0, "d1": d1, "cruise": cruise,
		"speed": cruise, "half": size.z * 0.5, "model": model_name, "taken": false, "paint": paint})


## You hopped in: it leaves the traffic for good (you're driving it now).
func take(v: Dictionary) -> void:
	v["taken"] = true
	v["body"].visible = false
	v["body"].global_position = Vector3(0, -900, 0)


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_body(delta)
	Prof.add("traffic", _p0)


func _physics_process_body(delta: float) -> void:
	for v in vehicles:
		if v["taken"]:
			continue
		var dir: int = v["dir"]
		var target: float = v["cruise"]
		# keep a gap behind the jeep when it's in our lane
		var ahead: float = (jeep_d - v["d"]) * dir - v["half"]
		var in_lane: bool = jeep_lat * dir > -0.8 and absf(jeep_lat) < 5.0
		if ahead > -2.0 and ahead < 30.0 and in_lane:
			target = minf(target, maxf(0.0, (ahead - 7.0) * 0.7))
		# slow round hairpins
		var t0: Vector3 = route.frame_at(v["d"]).basis.z
		var t1: Vector3 = route.frame_at(v["d"] + 25.0 * dir).basis.z
		if t0.dot(t1) < 0.6:
			target = minf(target, 4.5)
		v["speed"] = move_toward(v["speed"], target, delta * (4.0 if target < v["speed"] else 1.5))
		v["d"] += v["speed"] * dir * delta
		# past the end of its stretch: keep driving until out of sight, then loop back
		if v["d"] > v["d1"] or v["d"] < v["d0"]:
			var restart: float = v["d0"] if dir > 0 else v["d1"]
			if jeep_pos.distance_to(route.frame_at(restart).origin) > 250.0 and jeep_pos.distance_to(v["body"].global_position) > 150.0:
				v["d"] = restart
			elif v["d"] <= 0.0 or v["d"] >= route.length:
				v["d"] = clampf(v["d"], 0.0, route.length)
				v["speed"] = 0.0
		var f: Transform3D = route.frame_at(v["d"], LANE * dir)
		var b: Basis = f.basis if dir > 0 else f.basis.rotated(Vector3.UP, PI)
		v["body"].global_transform = Transform3D(b, f.origin + Vector3(0, 0.02, 0))


## A Kenney model for this kind, scaled to real length, standing on y = 0 and facing +Z.
func _kenney(kind: String, seed_i: int) -> Node3D:
	if not MODELS.has(kind):
		return null
	var options: Array = MODELS[kind]
	var pick: Array = options[seed_i % options.size()]
	var path: String = KENNEY + pick[0] + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var node := (load(path) as PackedScene).instantiate() as Node3D
	var aabb := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var s: float = pick[1] / maxf(aabb.size.z, 0.01)
	node.scale = Vector3.ONE * s
	node.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)
	return node


## Distance to the nearest vehicle ahead of the jeep in its lane (for the autopilot).
func gap_ahead(d: float, lat: float) -> float:
	var best := INF
	for v in vehicles:
		if v["taken"]:
			continue
		var dir: int = v["dir"]
		if lat * dir < -0.5:
			continue
		var gap: float = (v["d"] - d) * signf(dir) - v["half"]
		if dir > 0 and gap > 0.0:
			best = minf(best, gap)
	return best


# ----------------------------------------------------------------------------- vehicle meshes (+Z forward)
func _wheels(mb, half_w: float, zs: Array, r := 0.45) -> void:
	for z in zs:
		for s in [-1.0, 1.0]:
			mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(half_w * s + 0.15, r, z)), r, r, 0.3,
				Color(0.03, 0.03, 0.03), 10)


func _mesh_bus() -> ArrayMesh:
	var mb := MB.new()
	var red := Color(0.45, 0.04, 0.03)
	var cream := Color(0.72, 0.65, 0.48)
	mb.box(Transform3D(Basis(), Vector3(0, 1.05, 0)), Vector3(2.5, 1.2, 10.5), red)
	mb.box(Transform3D(Basis(), Vector3(0, 2.1, 0)), Vector3(2.46, 0.9, 10.4), Color(0.05, 0.07, 0.08))
	mb.box(Transform3D(Basis(), Vector3(0, 2.8, 0)), Vector3(2.5, 0.5, 10.5), cream)
	mb.box(Transform3D(Basis(), Vector3(0, 2.1, 5.23)), Vector3(2.2, 0.85, 0.05), Color(0.12, 0.16, 0.18))
	mb.box(Transform3D(Basis(), Vector3(0, 2.75, 5.24)), Vector3(1.6, 0.3, 0.04), Color(0.02, 0.02, 0.02))
	for k in 8:
		mb.box(Transform3D(Basis(), Vector3(0, 2.1, -4.6 + k * 1.3)), Vector3(2.52, 0.9, 0.08), red)
	_wheels(mb, 1.1, [3.4, -3.2])
	return mb.commit()


## European cab-over heavy truck in the style of a Scania rigid (no badges): tall flat-fronted cab
## with a big windscreen, sun visor, roof air deflector, horizontal-slat grille and mirrors on arms,
## on a three-axle chassis with a box or curtain body. Four colour schemes.
const TRUCK_SCHEMES := [
	[Color(0.55, 0.04, 0.04), Color(0.8, 0.8, 0.78), Color(0.55, 0.04, 0.04)],     # red cab, white box
	[Color(0.85, 0.85, 0.83), Color(0.85, 0.85, 0.83), Color(0.05, 0.2, 0.55)],    # white, blue stripe
	[Color(0.05, 0.18, 0.45), Color(0.55, 0.56, 0.58), Color(0.85, 0.6, 0.05)],    # blue cab, grey box
	[Color(0.85, 0.42, 0.03), Color(0.1, 0.3, 0.15), Color(0.85, 0.42, 0.03)],     # orange cab, green curtains
]


func _truck_mesh(scheme: int) -> ArrayMesh:
	var sc: Array = TRUCK_SCHEMES[scheme % TRUCK_SCHEMES.size()]
	var cab: Color = sc[0]
	var body: Color = sc[1]
	var stripe: Color = sc[2]
	var dark := Color(0.03, 0.03, 0.035)
	var glass := Color(0.05, 0.08, 0.1)
	var chrome := Color(0.55, 0.56, 0.58)
	var mb := MB.new()
	var at := func(p: Vector3) -> Transform3D: return Transform3D(Basis(), p)
	# chassis and fuel tanks
	mb.box(at.call(Vector3(0, 0.95, -0.2)), Vector3(0.95, 0.28, 9.8), dark)
	for sx in [-1.0, 1.0]:
		mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.92, 0.95, 1.6)), 0.28, 0.28, 1.2, chrome, 10)
	# cab: tall flat front, doors, windows
	mb.box(at.call(Vector3(0, 2.35, 3.95)), Vector3(2.5, 2.4, 2.1), cab)
	mb.box(at.call(Vector3(0, 1.2, 4.95)), Vector3(2.5, 0.25, 0.2), dark)                 # bumper
	mb.box(at.call(Vector3(0, 0.95, 4.9)), Vector3(1.6, 0.18, 0.15), dark)                # step
	mb.quad(Vector3(-1.12, 2.6, 5.02), Vector3(1.12, 2.6, 5.02), Vector3(1.08, 3.42, 4.96), Vector3(-1.08, 3.42, 4.96),
		glass, Vector3.BACK)                                                               # windscreen
	mb.box(at.call(Vector3(0, 3.5, 5.03)), Vector3(2.4, 0.12, 0.2), dark)                 # sun visor
	mb.box(at.call(Vector3(0, 1.95, 5.01)), Vector3(1.5, 0.85, 0.03), dark)               # grille
	for k in 5:
		mb.box(at.call(Vector3(0, 1.6 + k * 0.17, 5.03)), Vector3(1.45, 0.035, 0.02), chrome)
	for sx in [-1.0, 1.0]:
		mb.box(at.call(Vector3(sx * 0.95, 1.4, 5.0)), Vector3(0.42, 0.16, 0.05), Color(0.9, 0.9, 0.85))   # headlamps
		mb.box(at.call(Vector3(sx * 1.251, 2.9, 4.2)), Vector3(0.02, 0.7, 1.2), glass)                   # door window
		mb.box(at.call(Vector3(sx * 1.252, 2.1, 4.6)), Vector3(0.015, 1.1, 0.02), dark)                  # door line
		mb.box(at.call(Vector3(sx * 1.45, 3.0, 4.75)), Vector3(0.45, 0.05, 0.05), dark)                  # mirror arm
		mb.box(at.call(Vector3(sx * 1.66, 2.75, 4.75)), Vector3(0.08, 0.6, 0.25), dark)                  # mirror
		mb.box(at.call(Vector3(sx * 1.08, 1.05, 4.2)), Vector3(0.3, 0.12, 0.5), dark)                   # cab step
	# roof air deflector
	mb.quad(Vector3(-1.2, 3.55, 4.9), Vector3(1.2, 3.55, 4.9), Vector3(1.15, 4.1, 3.2), Vector3(-1.15, 4.1, 3.2), cab,
		Vector3(0, 1, 0.5))
	for sx in [-1.0, 1.0]:
		mb.quad(Vector3(sx * 1.2, 3.55, 4.9), Vector3(sx * 1.15, 4.1, 3.2), Vector3(sx * 1.15, 3.55, 3.2),
			Vector3(sx * 1.2, 3.55, 3.3), cab, Vector3(sx, 0, 0))
	mb.quad(Vector3(-1.15, 4.1, 3.2), Vector3(1.15, 4.1, 3.2), Vector3(1.15, 3.55, 3.2), Vector3(-1.15, 3.55, 3.2), cab,
		Vector3.FORWARD)
	# cargo body with a coloured stripe
	mb.box(at.call(Vector3(0, 2.6, -1.3)), Vector3(2.55, 2.8, 7.2), body)
	for sx in [-1.0, 1.0]:
		mb.box(at.call(Vector3(sx * 1.28, 1.6, -1.3)), Vector3(0.02, 0.3, 7.2), stripe)
	mb.box(at.call(Vector3(0, 1.6, -4.91)), Vector3(2.55, 0.3, 0.02), stripe)
	for sx in [-0.62, 0.62]:
		mb.box(at.call(Vector3(sx, 2.6, -4.92)), Vector3(0.02, 2.6, 0.02), dark)          # rear door lines
	mb.box(at.call(Vector3(0, 1.05, -4.95)), Vector3(2.4, 0.18, 0.1), dark)               # under-run bar
	for sx in [-1.0, 1.0]:
		mb.box(at.call(Vector3(sx * 1.0, 1.3, -4.95)), Vector3(0.35, 0.12, 0.04), Color(0.7, 0.03, 0.02))
	# three axles: steer axle, twin rear axles with dual wheels
	for spec in [[4.1, false], [-2.3, true], [-3.7, true]]:
		for sx in [-1.0, 1.0]:
			var off: Array = [1.05, 0.72] if spec[1] else [1.05]
			for xo in off:
				mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * xo + 0.15, 0.52, spec[0])), 0.52, 0.52, 0.3,
					Color(0.025, 0.025, 0.025), 14)
			mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.2 + 0.02, 0.52, spec[0])), 0.25, 0.25, 0.02,
				chrome, 10)
	return mb.commit()


func _mesh_car() -> ArrayMesh:
	var mb := MB.new()
	var white := Color(0.75, 0.75, 0.73)
	mb.box(Transform3D(Basis(), Vector3(0, 0.72, 0)), Vector3(1.7, 0.7, 3.9), white)
	mb.box(Transform3D(Basis(), Vector3(0, 1.3, -0.3)), Vector3(1.55, 0.55, 2.2), Color(0.06, 0.08, 0.1))
	mb.box(Transform3D(Basis(), Vector3(0, 1.6, -0.3)), Vector3(1.5, 0.06, 2.0), white)
	_wheels(mb, 0.72, [1.25, -1.25], 0.32)
	return mb.commit()


func _mesh_auto() -> ArrayMesh:
	var mb := MB.new()
	mb.box(Transform3D(Basis(), Vector3(0, 0.75, -0.2)), Vector3(1.3, 0.7, 2.1), Color(0.75, 0.55, 0.02))
	mb.box(Transform3D(Basis(), Vector3(0, 1.05, 1.0)), Vector3(0.9, 1.0, 0.5), Color(0.75, 0.55, 0.02))
	mb.box(Transform3D(Basis(), Vector3(0, 1.62, -0.1)), Vector3(1.35, 0.1, 2.3), Color(0.03, 0.03, 0.03))
	for sx in [-0.62, 0.62]:
		mb.box(Transform3D(Basis(), Vector3(sx, 1.3, -0.9)), Vector3(0.05, 0.6, 0.05), Color(0.03, 0.03, 0.03))
	mb.box(Transform3D(Basis(), Vector3(0, 1.45, 1.22)), Vector3(0.85, 0.35, 0.03), Color(0.1, 0.12, 0.14))
	_wheels(mb, 0.55, [-0.9], 0.25)
	mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.12, 0.25, 1.05)), 0.25, 0.25, 0.22,
		Color(0.03, 0.03, 0.03), 10)
	return mb.commit()
