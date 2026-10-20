extends Node3D
## Police vehicle checking (design: tools/police_checkpoint.py, previews/police/): now and then a NAGAR POLICE
## checking point is set up on the road ahead of you — barricades in a chicane, cones, the STOP board, the
## police SUV and two traffic policemen, one in the lane with his hand up.
##   * 70 m before it the HUD tells you to slow down and stop
##   * stop beside the policeman (under 1 m/s for 1.5 s): your papers are checked and any unpaid e-challans
##     are collected from the wallet
##   * drive through without stopping: fined on the spot (fines.gd SKIP_CHECK)
## The set is taken down once you are well past it, or after five minutes.

const Fines := preload("res://scripts/city/fines.gd")
const Streamer := preload("res://scripts/city/city_streamer.gd")
const EVERY := Vector2(240.0, 480.0)        # seconds between chances of a checkpoint
const CHANCE := 0.5
const AHEAD := 250.0                        # metres ahead on your road
## the barricades' boxes in the set's frame (centre, size): they are solid
const BARRICADES := [[Vector3(-5.6, 0.55, 0.0), Vector3(2.4, 1.1, 0.4)], [Vector3(-3.3, 0.55, -0.6), Vector3(2.4, 1.1, 0.4)],
	[Vector3(-1.4, 0.55, -9.0), Vector3(2.4, 1.1, 0.4)], [Vector3(-3.6, 0.55, -9.6), Vector3(2.4, 1.1, 0.4)]]
const OFFICER := Vector3(-2.4, 0.0, 4.5)    # the policeman with his hand up, in the set's frame

var car
var streamer
var hud
var fines
var _mesh: Mesh
var _set: Node3D
var _next := 0.0
var _age := 0.0
var _warned := false
var _stopped_for := 0.0
var _done := false
var _prev_past := -INF
var _grounded := false
var _body: StaticBody3D


func _ready() -> void:
	var m: Mesh = Streamer._scene_mesh("res://assets/city_props/police_checkpoint.glb")
	_mesh = Streamer._with_lods(m) if m else null
	_next = randf_range(EVERY.x, EVERY.y)
	if "--police" in OS.get_cmdline_user_args():
		_next = 3.0                                     # testing: one straight away


func _process(dt: float) -> void:
	if _set != null and not _grounded:
		_ground()
	if car == null or _mesh == null:
		return
	if _set == null:
		_next -= dt
		if _next <= 0.0:
			_next = randf_range(EVERY.x, EVERY.y)
			if randf() < CHANCE or "--police" in OS.get_cmdline_user_args():
				_spawn()
		return
	_age += dt
	var cp: Vector3 = car.global_position
	var local: Vector3 = _set.global_transform.affine_inverse() * cp
	var past := OFFICER.z - local.z                     # > 0 once you've passed the policeman (traffic goes −Z)
	var dist := cp.distance_to(_set.global_transform * OFFICER)
	if not _warned and dist < 70.0 and past < 0.0:
		_warned = true
		_say("POLICE CHECKING AHEAD — slow down and stop")
	if not _done:
		if dist < 16.0 and absf(car.speed) < 1.0 and absf(local.x) < 9.0:
			_stopped_for += dt
			if _stopped_for > 1.5:
				_check()
		else:
			_stopped_for = 0.0
		if _prev_past < 0.0 and past >= 0.0 and absf(local.x) < 9.0 and absf(car.speed) > 4.0:
			_done = true
			if fines:
				var paid: int = fines.pay(Fines.SKIP_CHECK)
				_say("FINED %s — you drove through a police check" % Fines.rupees(paid), 5.0)
			else:
				_say("You drove through a police check!", 5.0)
	_prev_past = past
	if past > 150.0 or _age > 300.0 or dist > 900.0:
		_set.queue_free()
		_set = null


func _check() -> void:
	_done = true
	if fines == null:
		_say("Papers checked — drive safely", 5.0)
		return
	var n: int = fines.challans.size()
	if n == 0:
		_say("Papers in order. Drive safely!", 5.0)
		return
	var r: Array = fines.settle_challans()
	if r[0] == n:
		_say("Papers checked · %d challan(s) paid, %s" % [r[0], Fines.rupees(r[1])], 6.0)
	else:
		_say("Papers checked · paid %s · %s still due (wallet short)" % [Fines.rupees(r[1]), Fines.rupees(fines.owed())], 6.0)


func _say(text: String, secs := 4.0) -> void:
	if hud:
		hud.warn(text, secs)


## Set it up on the road you're driving, about AHEAD metres on, facing you, in your carriageway.
func _spawn() -> void:
	var cp: Vector3 = car.global_position
	var fwd: Vector3 = car.forward()
	var best = null
	var bd := 12.0
	var bi := 0
	for k in streamer.loaded:
		for r in (streamer.loaded[k] as Node3D).get_meta("roads", []):
			if r.get("fly", false) or not r["c"] in ["trunk", "primary", "secondary", "tertiary", "residential", "unclassified"]:
				continue
			var p: PackedFloat32Array = r["p"]
			for i in p.size() / 3:
				var d := Vector2(p[i * 3] - cp.x, p[i * 3 + 2] - cp.z).length()
				if d < bd:
					bd = d
					best = r
					bi = i
	if best == null:
		return
	var p: PackedFloat32Array = best["p"]
	var n := p.size() / 3
	# which way along the road is "ahead"
	var step := 1
	if bi + 1 < n:
		var dv := Vector3(p[(bi + 1) * 3] - p[bi * 3], 0, p[(bi + 1) * 3 + 2] - p[bi * 3 + 2])
		step = 1 if dv.dot(fwd) >= 0.0 else -1
	else:
		step = -1
	var walked := 0.0
	var i := bi
	var ahead := 60.0 if "--police" in OS.get_cmdline_user_args() else AHEAD
	while i + step >= 0 and i + step < n and walked < ahead:
		walked += Vector2(p[(i + step) * 3] - p[i * 3], p[(i + step) * 3 + 2] - p[i * 3 + 2]).length()
		i += step
	if walked < minf(90.0, ahead * 0.7):                # this piece of road is too short: try again later
		return
	var j: int = clampi(i - step, 0, n - 1)
	var at := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
	var back := Vector3(p[j * 3], p[j * 3 + 1], p[j * 3 + 2])
	var d := Vector3(at.x - back.x, 0, at.z - back.z).normalized()        # the way the traffic goes
	if d == Vector3.ZERO:
		return
	place(at, d)


## Sit the set on the real road surface: ray-cast down at the policeman and at each barricade's feet (the road is
## crowned and junction surfaces are a little higher than the centre line) and lift the set to the highest.
func _ground() -> void:
	var space := get_world_3d().direct_space_state
	var xf := _set.global_transform
	var ys: Array = []
	var pts: Array = [OFFICER]
	for bb in BARRICADES:
		pts.append(Vector3(bb[0].x, 0, bb[0].z))
	for lp in pts:
		var w: Vector3 = xf * Vector3(lp.x, 0, lp.z)
		var q := PhysicsRayQueryParameters3D.create(w + Vector3.UP * 6.0, w - Vector3.UP * 6.0)
		q.exclude = [_body.get_rid()] if _body else []
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return                                      # the ground isn't loaded yet: try next frame
		ys.append(float(hit["position"].y))
	# the policeman's feet decide: he must stand exactly on the road (the barricades' feet can take a few cm)
	_set.global_position.y = ys[0]
	_grounded = true
	print("POLICE grounded at y=%.2f (under the policeman), barricades %s" % [ys[0], str(ys.slice(1))])


## Set the checkpoint up at `at` (on the road's centre line) for traffic going `d`.
func place(at: Vector3, d: Vector3) -> void:
	if _mesh == null:
		return
	_set = Node3D.new()
	_set.name = "PoliceCheck"
	add_child(_set)
	_set.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), at)      # −Z along the traffic
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	_set.add_child(mi)
	var body := StaticBody3D.new()
	_body = body
	_set.add_child(body)
	for b in BARRICADES:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		body.add_child(cs)
	print("POLICE CHECK at %s heading %s" % [str(at.round()), str(d)])
	_grounded = false
	_age = 0.0
	_warned = false
	_done = false
	_stopped_for = 0.0
	_prev_past = -INF
