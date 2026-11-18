extends Node
## (testing) --popwatch[=drive|still]: the population brief's acceptance test. Every frame, every person the city
## puts on its streets (city_walkers.gd's walkers, city_activity.gd's people at spots, citizens.gd's near bodies) is
## watched from the camera, and three things are counted when they happen where Karthik could see them (in the
## camera's view, within 120 m, nothing solid between):
##   appear   someone shows up who wasn't there the frame before
##   vanish   someone in view is gone the next frame (hidden or freed)
##   jump     someone moves more than 4 m in one frame (set down elsewhere)
## drive: the car on autopilot through the streets for 120 s. still: the car stopped, turned round every 15 s (the
## camera looking behind and back), 120 s. One line every 10 s ("POPS ..."), a summary at the end, then quit.

const SEE := 120.0
const SECS := 120.0

var city
var mode := "drive"
var _last := {}                # instance id → {"vis": bool, "pos": Vector3, "seen": bool}
var counts := {"appear": 0, "vanish": 0, "jump": 0, "frames": 0, "people_seen": 0}
var _t := 0.0
var _log := 0.0
var _turn := 0.0
var _go := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--popwatch="):
			mode = a.get_slice("=", 1)
	_start.call_deferred()


func _start() -> void:
	await get_tree().create_timer(14.0).timeout
	if mode == "drive":
		city.car.autopilot = true
	_go = true


func _physics_process(dt: float) -> void:
	if not _go:
		return
	_t += dt
	_log += dt
	if mode == "still":
		city.car.linear_velocity = Vector3.ZERO
		_turn += dt
		if _turn > 15.0:
			_turn = 0.0
			city.car.rotate_y(PI)
	_watch()
	if _log >= 10.0:
		_log = 0.0
		print("POPS t=%.0f %s" % [_t, str(counts)])
	if _t >= SECS:
		print("POPS done (%s): %s" % [mode, str(counts)])
		get_tree().quit()


func _people() -> Array:
	var out: Array = []
	var w = city.get_node_or_null("Walkers")
	if w:
		for q in w.people:
			out.append([q["node"], "walker"])
	var a = city.get_node_or_null("Activity")
	if a:
		for p in a.pool:
			out.append([p["node"], "activity"])
	if city.get("citizens") and city.citizens:
		for c in city.citizens.people:
			if c["node"] != null and is_instance_valid(c["node"]):
				out.append([c["node"], "citizen"])
	return out


func _seen(cam: Camera3D, pos: Vector3) -> bool:
	var chest := pos + Vector3.UP * 1.2
	if cam.global_position.distance_to(chest) > SEE or not cam.is_position_in_frustum(chest):
		return false
	var rq := PhysicsRayQueryParameters3D.create(cam.global_position, chest)
	rq.exclude = [city.car.get_rid()]
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(rq)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(chest) < 1.0


func _watch() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	counts["frames"] += 1
	var now := {}
	for e in _people():
		var n = e[0]
		if not is_instance_valid(n):
			continue
		var node := n as Node3D
		var id := node.get_instance_id()
		var vis := node.is_visible_in_tree()
		var pos := node.global_position
		var seen := vis and _seen(cam, pos)
		now[id] = {"vis": vis, "pos": pos, "seen": seen}
		if seen:
			counts["people_seen"] += 1
		var was: Dictionary = _last.get(id, {})
		if was.is_empty():
			if seen and counts["frames"] > 1:
				counts["appear"] += 1
			continue
		if vis and not bool(was["vis"]) and seen:
			counts["appear"] += 1
			print("POPS appear %s %.0f m" % [e[1], cam.global_position.distance_to(pos)])
		elif bool(was["seen"]) and not vis:
			counts["vanish"] += 1
			print("POPS vanish %s %.0f m" % [e[1], cam.global_position.distance_to(pos)])
		elif vis and bool(was["vis"]) and (pos - (was["pos"] as Vector3)).length() > 4.0 and (seen or bool(was["seen"])):
			counts["jump"] += 1
			counts["jump_" + str(e[1])] = int(counts.get("jump_" + str(e[1]), 0)) + 1
			print("POPS jump %s %.0f m → %.0f m from the camera" % [e[1], cam.global_position.distance_to(was["pos"]), cam.global_position.distance_to(pos)])
	for id in _last:                                     # (freed while in view)
		if not now.has(id) and bool(_last[id]["seen"]):
			counts["vanish"] += 1
	_last = now
