extends Node3D
## Town traffic on the road graph (road_graph.gd), the same network the GPS and the street meshes
## use: autos, motorbikes, scooters, cars and the odd bus keep left, slow into junctions, pick a
## real connected street at every node (one-way streets only the right way), queue behind each
## other and stop for you. A small pool is recycled around the player: vehicles that fall far
## behind reappear on a street out of view, never right in front of you.

const Prof := preload("res://scripts/drive/prof.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const StreetLife := preload("res://scripts/drive/street_life.gd")
const RiderPose := preload("res://scripts/drive/rider_pose.gd")
const Fleet := preload("res://scripts/drive/fleet.gd")
const KENNEY := "res://assets/drive/models/kenney/"
const POOL := 64
const NEAR := 300.0                # recycle beyond this
const SPAWN_MIN := 70.0
const SPAWN_MAX := 260.0
const MAIN := ["trunk", "primary", "secondary", "tertiary"]
## kind, length, width, height, cruise on main roads (m/s), weight
const KINDS := [
	["auto", 2.7, 1.35, 1.75, 8.5, 26], ["bike", 2.0, 0.8, 1.4, 10.0, 24], ["scooter", 1.8, 0.75, 1.4, 8.5, 18],
	["hatchback", 3.85, 1.73, 1.53, 11.0, 14], ["sedan", 4.4, 1.75, 1.5, 11.0, 9], ["suv", 4.5, 1.85, 1.7, 11.0, 4],
	["taxi", 4.4, 1.75, 1.5, 10.5, 5], ["van", 4.6, 1.8, 2.0, 9.5, 2], ["bus", 10.5, 2.5, 3.1, 8.0, 3],
]

var graph
var player: Node3D                 # the jeep or you on foot (set by the game)
var cars: Array = []
var _cum := {}                     # street idx -> cumulative lengths
var _rng := RandomNumberGenerator.new()
var _scan := 0
var _mat: StandardMaterial3D


func build(g, p: Node3D) -> void:
	graph = g
	player = p
	_rng.randomize()
	_mat = MB.vertex_color_material(0.55)
	var helper := StreetLife.new()
	for k in POOL:
		var spec: Array = _pick_kind()
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		body.name = "Town%s_%d" % [spec[0], k]
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(spec[2], spec[3], spec[1])
		cs.shape = bx
		cs.position = Vector3(0, spec[3] * 0.5 + 0.05, 0)
		body.add_child(cs)
		body.add_child(_visual(spec, helper, k))
		body.visible = false
		add_child(body)
		var meshes := body.find_children("*", "GeometryInstance3D", true, false)
		for m in meshes:
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cars.append({"body": body, "kind": spec[0], "len": spec[1], "cruise": spec[4], "si": -1, "fwd": true,
			"s": 0.0, "speed": 0.0, "pos": Vector3.ZERO, "dir": Vector3.FORWARD, "meshes": meshes, "shadow": false})
	helper.free()


func _pick_kind() -> Array:
	var total := 0
	for k in KINDS:
		total += k[5]
	var r := _rng.randi_range(1, total)
	for k in KINDS:
		r -= k[5]
		if r <= 0:
			return k
	return KINDS[0]


func _visual(spec: Array, helper, seed_i: int) -> Node3D:
	var kind: String = spec[0]
	var root := Node3D.new()
	if Fleet.has(kind):
		# the Blender fleet: real proportions, glass, lamps, a paint of its own
		var p := Fleet.paint_for(kind, _rng)
		root.add_child(Fleet.model(kind, p))
		root.set_meta("paint", p)
		return root
	if kind in ["auto", "bike", "scooter"]:
		var mi := MeshInstance3D.new()
		mi.mesh = helper._built(kind)
		if kind != "auto":
			var m := MB.vertex_color_material(0.55)
			m.albedo_color = StreetLife.BIKE_PAINT[seed_i % StreetLife.BIKE_PAINT.size()]
			mi.material_override = m
		root.add_child(mi)
		if kind != "auto":
			var r := RiderPose.make(seed_i, 0.6 if kind == "bike" else 0.5)
			r.position = RiderPose.seat_offset(kind)
			for m in r.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(m as MeshInstance3D).visibility_range_end = 160.0
			root.add_child(r)
		return root
	if kind == "bus":
		var mb := MB.new()
		var body_c: Color = [Color(0.45, 0.04, 0.03), Color(0.08, 0.28, 0.5), Color(0.5, 0.42, 0.1)][seed_i % 3]
		mb.box(Transform3D(Basis(), Vector3(0, 1.05, 0)), Vector3(2.5, 1.2, 10.5), body_c)
		mb.box(Transform3D(Basis(), Vector3(0, 2.1, 0)), Vector3(2.46, 0.9, 10.4), Color(0.05, 0.07, 0.08))
		mb.box(Transform3D(Basis(), Vector3(0, 2.8, 0)), Vector3(2.5, 0.5, 10.5), Color(0.72, 0.65, 0.48))
		for z in [-3.6, 3.4]:
			for x in [-1.1, 1.1]:
				mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.15, 0.48, z)), 0.48, 0.48, 0.3, Color(0.03, 0.03, 0.03), 10)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit()
		mi.material_override = _mat
		root.add_child(mi)
		return root
	var path := KENNEY + kind + ".glb"
	if ResourceLoader.exists(path):
		var node := (load(path) as PackedScene).instantiate() as Node3D
		var aabb := AABB()
		var first := true
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		var s: float = spec[1] / maxf(aabb.size.z, 0.01)
		node.scale = Vector3.ONE * s
		node.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)
		root.add_child(node)
	return root


## A seated rider for two-wheelers: shirt, trousers, head and a helmet half the time.
func _rider() -> MeshInstance3D:
	var mb := MB.new()
	var shirts := [Color(0.85, 0.85, 0.82), Color(0.15, 0.25, 0.55), Color(0.55, 0.12, 0.1), Color(0.3, 0.45, 0.3), Color(0.9, 0.75, 0.3)]
	var shirt: Color = shirts[_rng.randi() % shirts.size()]
	var skin := Color(0.42, 0.28, 0.18).lerp(Color(0.3, 0.19, 0.12), _rng.randf())
	mb.box(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 1.25, -0.2)), Vector3(0.42, 0.6, 0.26), shirt)
	mb.box(Transform3D(Basis(), Vector3(0, 0.92, -0.05)), Vector3(0.38, 0.18, 0.55), Color(0.15, 0.15, 0.2))
	mb.box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0.13, 1.25, 0.15)), Vector3(0.09, 0.45, 0.09), shirt)
	mb.box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(-0.13, 1.25, 0.15)), Vector3(0.09, 0.45, 0.09), shirt)
	mb.ellipsoid(Transform3D(Basis(), Vector3(0, 1.68, -0.1)), Vector3(0.12, 0.14, 0.13), skin)
	if _rng.randf() < 0.55:
		mb.ellipsoid(Transform3D(Basis(), Vector3(0, 1.73, -0.1)), Vector3(0.15, 0.14, 0.16), Color(0.05, 0.05, 0.06))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = _mat
	return mi


# ----------------------------------------------------------------------------- driving
func _physics_process(delta: float) -> void:
	if graph == null or player == null:
		return
	var _p0 := Time.get_ticks_usec()
	_drive(delta)
	Prof.add("town_traffic", _p0)


func _drive(delta: float) -> void:
	var pp := player.global_position
	# one empty or far vehicle per frame looks for a new street near the player
	_scan = (_scan + 1) % cars.size()
	# only vehicles near you cast shadows (where grounding shows; far ones just cost draw calls)
	var cz: Dictionary = cars[(_scan * 5) % cars.size()]
	var want: bool = cz["si"] >= 0 and cz["pos"].distance_to(pp) < 35.0
	if want != cz["shadow"]:
		cz["shadow"] = want
		for m in cz["meshes"]:
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c0: Dictionary = cars[_scan]
	if c0["si"] < 0 or c0["pos"].distance_to(pp) > NEAR:
		_respawn(c0, pp)
	for c in cars:
		if c["si"] < 0:
			continue
		var st: Dictionary = graph.streets[c["si"]]
		var cum: PackedFloat32Array = _lengths(c["si"])
		var total: float = cum[cum.size() - 1]
		var main: bool = st["class"] in MAIN
		var target: float = c["cruise"] * (1.0 if main else 0.65)
		var left_to_go: float = total - c["s"]
		var node: String = st["b"] if c["fwd"] else st["a"]
		if graph.is_junction(node) and left_to_go < 14.0:
			target = minf(target, 3.5 + left_to_go * 0.25)
		# queue behind whatever is ahead in our lane (other traffic, or you)
		var ahead := INF
		for o in cars:
			if o == c or o["si"] < 0:
				continue
			var rel: Vector3 = o["pos"] - c["pos"]
			var along: float = rel.dot(c["dir"])
			if along > 0.0 and along < ahead and absf(rel.dot(Vector3(c["dir"].z, 0, -c["dir"].x))) < 1.6 and o["dir"].dot(c["dir"]) > 0.3:
				ahead = along - (o["len"] + c["len"]) * 0.5
		var relp: Vector3 = pp - c["pos"]
		var ap: float = relp.dot(c["dir"])
		if ap > 0.0 and absf(relp.dot(Vector3(c["dir"].z, 0, -c["dir"].x))) < 2.2:
			ahead = minf(ahead, ap - c["len"] * 0.5 - 2.4)
		if ahead < 18.0:
			target = minf(target, maxf(0.0, (ahead - 2.5) * 0.8))
		c["speed"] = move_toward(c["speed"], target, delta * (6.0 if target < c["speed"] else 2.0))
		c["s"] += c["speed"] * delta
		if c["s"] >= total:
			var carry: float = c["s"] - total
			if not _next_street(c, node):
				c["si"] = -1
				c["body"].visible = false
				continue
			c["s"] = carry
		_place(c)


## Choose the next street at a node: any other connected street we're allowed to enter,
## preferring to carry on straight; a U-turn only at a dead end. Town traffic stays off the highway.
func _next_street(c: Dictionary, node: String) -> bool:
	if not graph.nodes.has(node) or graph.nodes[node]["kind"] == "highway" or graph.nodes[node]["kind"] == "edge":
		return false
	var options: Array = []
	var weights: Array = []
	for si in graph.nodes[node]["edges"]:
		if si == c["si"]:
			continue
		var st: Dictionary = graph.streets[si]
		if st["class"] in ["service", "pedestrian"]:
			continue
		var fwd: bool = st["a"] == node
		if st["oneway"] and not fwd:
			continue
		var pts: PackedVector3Array = st["pts"]
		var d0: Vector3 = (pts[1] - pts[0]) if fwd else (pts[pts.size() - 2] - pts[pts.size() - 1])
		var straight: float = Vector3(d0.x, 0, d0.z).normalized().dot(c["dir"])
		options.append([si, fwd])
		weights.append(1.0 + maxf(straight, 0.0) * 2.0 + (1.5 if st["class"] in MAIN else 0.0))
	if options.is_empty():
		var st0: Dictionary = graph.streets[c["si"]]
		if st0["oneway"]:
			return false
		c["fwd"] = not c["fwd"]                  # dead end: turn round
		return true
	var total := 0.0
	for w in weights:
		total += w
	var r := _rng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			c["si"] = options[i][0]
			c["fwd"] = options[i][1]
			return true
	c["si"] = options[0][0]
	c["fwd"] = options[0][1]
	return true


func _respawn(c: Dictionary, pp: Vector3) -> void:
	c["body"].visible = false
	c["si"] = -1
	var fwd: Vector3 = -player.global_basis.z if not player.has_method("forward") else player.forward()
	for attempt in 6:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var q := pp + Vector3(cos(ang), 0, sin(ang)) * dist
		var to := (q - pp).normalized()
		if to.dot(fwd) > 0.3:
			continue                                 # would pop up in plain view ahead
		var ns: Array = graph.nearest_street(q)
		if ns[0] < 0 or ns[1] > 25.0:
			continue
		var st: Dictionary = graph.streets[ns[0]]
		if st["class"] in ["service", "pedestrian"]:
			continue
		if c["kind"] == "bus" and not st["class"] in MAIN:
			continue
		c["si"] = ns[0]
		c["fwd"] = true if st["oneway"] else _rng.randf() < 0.5
		var cum := _lengths(ns[0])
		c["s"] = _rng.randf() * cum[cum.size() - 1]
		c["speed"] = c["cruise"] * 0.5
		_place(c)
		c["body"].visible = true
		return


func _place(c: Dictionary) -> void:
	var st: Dictionary = graph.streets[c["si"]]
	var pts: PackedVector3Array = st["pts"]
	var cum := _lengths(c["si"])
	var total: float = cum[cum.size() - 1]
	var s: float = clampf(c["s"], 0.0, total)
	var u: float = s if c["fwd"] else total - s
	var k := cum.bsearch(u) - 1
	k = clampi(k, 0, pts.size() - 2)
	var t: float = (u - cum[k]) / maxf(cum[k + 1] - cum[k], 0.001)
	var p := pts[k].lerp(pts[k + 1], t)
	var dir := (pts[k + 1] - pts[k]) * (1.0 if c["fwd"] else -1.0)
	dir = Vector3(dir.x, 0, dir.z).normalized()
	if dir == Vector3.ZERO:
		dir = c["dir"]
	var blended: Vector3 = (c["dir"] + dir).normalized()
	c["dir"] = blended if c["dir"].dot(dir) > -0.3 and blended.length_squared() > 0.5 else dir
	var left := Vector3(c["dir"].z, 0, -c["dir"].x)          # keep left (India)
	var lane: float = 0.0 if st["oneway"] else st["width"] * 0.24
	if c["kind"] in ["bike", "scooter"]:
		lane = st["width"] * 0.36
	p += left * lane + Vector3(0, 0.05, 0)
	c["pos"] = p
	c["body"].global_transform = Transform3D(Basis.looking_at(-c["dir"], Vector3.UP), p)


func take(c: Dictionary) -> void:
	c["si"] = -1
	c["body"].visible = false
	c["body"].global_position = Vector3(0, -900, 0)


func summary() -> String:
	var active := 0
	var moving := 0
	var near := INF
	for c in cars:
		if c["si"] >= 0:
			active += 1
			if c["speed"] > 1.0:
				moving += 1
			near = minf(near, c["pos"].distance_to(player.global_position))
	return "active %d / %d, moving %d, nearest %.0f m" % [active, cars.size(), moving, near]


func _lengths(si: int) -> PackedFloat32Array:
	if _cum.has(si):
		return _cum[si]
	var pts: PackedVector3Array = graph.streets[si]["pts"]
	var cum := PackedFloat32Array([0.0])
	for k in pts.size() - 1:
		cum.append(cum[k] + pts[k].distance_to(pts[k + 1]))
	_cum[si] = cum
	return cum
