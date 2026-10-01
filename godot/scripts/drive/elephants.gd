extends Node3D
## A small herd crossing the forest road in the foothills. It starts as the jeep approaches;
## the elephants physically block the road, so the player has to stop and wait quietly.

signal started
signal finished

const Prof := preload("res://scripts/drive/prof.gd")
const Route := preload("res://scripts/drive/route.gd")
const Terrain := preload("res://scripts/drive/terrain.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const SKIN := Color(0.25, 0.23, 0.22)

var route: Route
var terrain: Terrain
var state := "idle"               # idle → crossing → done
var herd: Array = []
var mark := 0.0


func build(r, t) -> void:
	route = r
	terrain = t
	mark = route.marks["elephants"]
	var f: Transform3D = route.frame_at(mark)
	var across: Vector3 = -f.basis.x              # from the left verge to the right, into the forest
	# size, offset along the road, start delay (s), tusker?
	var members := [[1.05, -3.0, 0.0, true], [1.0, 3.5, 2.5, false], [0.55, 1.0, 3.2, false], [0.95, -1.0, 6.0, false],
		[0.6, 5.0, 7.0, false]]
	for m in members:
		var s: float = m[0]
		var along: Vector3 = f.basis.z * float(m[1])
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.9, 2.8, 3.8) * s
		cs.shape = bx
		cs.position = Vector3(0, 1.6 * s, 0.2 * s)
		body.add_child(cs)
		var legs := _elephant(body, s, m[3])
		body.visible = false
		add_child(body)
		var a: Vector3 = f.origin + across * -32.0 + along
		var b: Vector3 = f.origin + across * 36.0 + along
		body.global_transform = Transform3D(Basis.looking_at(-(b - a).normalized(), Vector3.UP), a)
		herd.append({"body": body, "legs": legs, "a": a, "b": b, "delay": m[2], "speed": 1.3, "t": 0.0, "s": s})


## Builds one elephant under `body`, facing +Z. Returns the four leg pivots.
func _elephant(body: Node3D, s: float, tusker: bool) -> Array:
	var mat := MB.vertex_color_material(0.95)
	var mb := MB.new()
	mb.ellipsoid(Transform3D(Basis(), Vector3(0, 2.1, 0) * s), Vector3(0.95, 1.05, 1.6) * s, SKIN, 7, 12)
	mb.ellipsoid(Transform3D(Basis(), Vector3(0, 2.55, 1.65) * s), Vector3(0.62, 0.7, 0.62) * s, SKIN, 6, 10)
	for sx in [-1.0, 1.0]:
		mb.ellipsoid(Transform3D(Basis(Vector3.UP, 0.35 * sx), Vector3(0.62 * sx, 2.6, 1.42) * s),
			Vector3(0.1, 0.62, 0.52) * s, SKIN.darkened(0.1), 5, 8)
	# trunk hanging down and slightly forward
	var pts := [Vector3(0, 2.35, 2.15), Vector3(0, 1.7, 2.45), Vector3(0, 1.0, 2.5), Vector3(0, 0.45, 2.35)]
	for i in 3:
		var p0: Vector3 = pts[i] * s
		var p1: Vector3 = pts[i + 1] * s
		var dir := (p1 - p0).normalized()
		var b := Basis(Quaternion(Vector3.UP, dir))
		mb.cylinder(Transform3D(b, p0), lerpf(0.26, 0.1, i / 3.0) * s, lerpf(0.26, 0.1, (i + 1) / 3.0) * s,
			(p1 - p0).length(), SKIN, 8)
	if tusker:
		for sx in [-0.22, 0.22]:
			var p := Vector3(sx, 2.05, 2.05) * s
			mb.cylinder(Transform3D(Basis(Quaternion(Vector3.UP, Vector3(0, -0.4, 1).normalized())), p), 0.06 * s,
				0.03 * s, 0.7 * s, Color(0.85, 0.82, 0.7), 6)
	mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.8), Vector3(0, 2.4, -1.5) * s), 0.05 * s, 0.03 * s, 1.0 * s, SKIN, 5)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	body.add_child(mi)
	var leg_mb := MB.new()
	leg_mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO), 0.3 * s, 0.26 * s, 1.55 * s, SKIN, 8)
	var leg_mesh := leg_mb.commit()
	var legs: Array = []
	for lp in [Vector3(0.52, 1.55, 1.0), Vector3(-0.52, 1.55, 1.0), Vector3(0.52, 1.55, -0.95), Vector3(-0.52, 1.55, -0.95)]:
		var pivot := Node3D.new()
		pivot.position = lp * s
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.material_override = mat
		pivot.add_child(leg)
		body.add_child(pivot)
		legs.append(pivot)
	return legs


func start() -> void:
	if state != "idle":
		return
	state = "crossing"
	for e in herd:
		e["body"].visible = true
	started.emit()


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_body(delta)
	Prof.add("elephants", _p0)


func _physics_process_body(delta: float) -> void:
	if state != "crossing":
		return
	var all_done := true
	for e in herd:
		e["t"] += delta
		var walk_t: float = maxf(e["t"] - e["delay"], 0.0)
		var path: float = (e["b"] - e["a"]).length()
		var f: float = clampf(walk_t * e["speed"] / path, 0.0, 1.0)
		var p: Vector3 = e["a"].lerp(e["b"], f)
		var y: float = terrain.height_at(p.x, p.z)
		var body: AnimatableBody3D = e["body"]
		var ph: float = walk_t * 2.4 / e["s"]
		body.global_position = Vector3(p.x, y + 0.04 * sin(ph * 2.0), p.z)
		var legs: Array = e["legs"]
		for i in 4:
			var swing := sin(ph + (PI if i in [1, 2] else 0.0)) * 0.32 if f < 1.0 else 0.0
			legs[i].rotation.x = swing
		if f < 1.0:
			all_done = false
	if all_done:
		state = "done"
		for e in herd:
			e["body"].queue_free()
		finished.emit()


func nearest_distance(p: Vector3) -> float:
	var best := INF
	if state != "crossing":
		return best
	for e in herd:
		best = minf(best, p.distance_to(e["body"].global_position))
	return best
