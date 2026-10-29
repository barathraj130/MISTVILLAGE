extends Node3D
## People walking through a public room: along the room's routes (tools/city_rooms.py Walk_<name>[o]_<n>: points on
## clear aisles, walked to and fro, or round and round when the name ends in "o"), two or three on each, at a
## person's pace (the Walk clip played to it: a cycle covers 1.25 m, as the street crowd's), keeping to the left
## of the way (so those coming the other way pass by) and behind anyone going their way just ahead, slowing round the
## corners, now and then stopping a few seconds (a look at a shop, at the board) and at the ends of a way before
## turning back. One who has Karthik right in front of them waits for him to pass (or, if he stays, turns back).

const Crowd := preload("res://scripts/city/crowd.gd")
const STRIDE := 1.25

var player: Node3D                   # Karthik on foot (city.walker)
var _walkers: Array = []             # {node, anim, pts, loop, seg, t, dir, speed, wait}


## Send people along room's routes (decided by the building: the same people every visit).
func setup(room: Node3D, key: String, who: Node3D) -> int:
	player = who
	var routes := {}
	for e in room.find_children("Walk_*", "", true, false):
		var parts := String(e.name).split("_")
		if parts.size() < 3:
			continue
		if not routes.has(parts[1]):
			routes[parts[1]] = []
		routes[parts[1]].append([int(parts[2]), (e as Node3D).global_position])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + "walk")
	for name in routes:
		var pts := PackedVector3Array()
		var arr: Array = routes[name]
		arr.sort_custom(func(a, b): return a[0] < b[0])
		for p in arr:
			pts.append(p[1])
		if pts.size() < 2:
			continue
		var loop := String(name).ends_with("o")
		for i in (2 + rng.randi() % 2):
			var npc := Crowd.person(self, rng)
			if npc == null:
				continue
			var w := {"node": npc, "anim": null, "pts": pts, "loop": loop, "seg": rng.randi() % (pts.size() - 1),
				"t": rng.randf(), "dir": 1 if rng.randf() < 0.5 else -1, "speed": rng.randf_range(1.0, 1.35),
				"wait": 0.0, "yaw": 0.0}
			var aps := npc.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				w["anim"] = aps[0]
				for a in ["Walk", "Idle"]:
					if (aps[0] as AnimationPlayer).has_animation(a):
						(aps[0] as AnimationPlayer).get_animation(a).loop_mode = Animation.LOOP_LINEAR
			_place(w, 0.0)
			_walkers.append(w)
	return _walkers.size()


func _process(dt: float) -> void:
	for w in _walkers:
		_step(w, dt)


func _step(w: Dictionary, dt: float) -> void:
	var node: Node3D = w["node"]
	if w["wait"] > 0.0:                                    # stopped: a look about
		w["wait"] -= dt
		_play(w, "Idle", 1.0)
		return
	var pts: PackedVector3Array = w["pts"]
	var a := pts[w["seg"]]
	var b := pts[w["seg"] + 1]
	var ahead: Vector3 = (b - a).normalized() * float(w["dir"])
	if player and is_instance_valid(player):              # Karthik in the way: wait for him
		var to := player.global_position - node.global_position
		to.y = 0.0
		if to.length() < 1.3 and to.normalized().dot(ahead) > 0.4:
			_play(w, "Idle", 1.0)
			w["blocked"] = float(w.get("blocked", 0.0)) + dt
			if w["blocked"] > 2.5:                         # he isn't moving: go back the other way
				w["dir"] = -w["dir"]
				w["blocked"] = 0.0
			return
	w["blocked"] = 0.0
	for o in _walkers:                                     # someone just ahead going this way: keep behind them
		if o == w:
			continue
		var rel: Vector3 = (o["node"] as Node3D).global_position - node.global_position
		rel.y = 0.0
		var fwd := rel.dot(ahead)
		if fwd > 0.0 and fwd < 1.1 and (rel - ahead * fwd).length() < 0.5:
			_play(w, "Idle", 1.0)
			return
	var seg_len := maxf(a.distance_to(b), 0.01)
	w["t"] += w["dir"] * w["speed"] * dt / seg_len
	if w["t"] > 1.0 or w["t"] < 0.0:                       # the end of this stretch: the next, or turn back
		var last := pts.size() - 2
		var nxt: int = w["seg"] + w["dir"]
		if nxt > last or nxt < 0:
			if w["loop"]:
				w["seg"] = 0 if nxt > last else last
				w["t"] = 0.0 if nxt > last else 1.0
			else:
				w["dir"] = -w["dir"]
				w["t"] = clampf(w["t"], 0.0, 1.0)
				w["wait"] = randf_range(1.0, 4.0)
		else:
			w["seg"] = nxt
			w["t"] = 0.0 if w["dir"] > 0 else 1.0
			if randf() < 0.25:
				w["wait"] = randf_range(1.5, 4.0)
	_place(w, dt)
	_play(w, "Walk", w["speed"] / STRIDE)


func _place(w: Dictionary, dt: float) -> void:
	var pts: PackedVector3Array = w["pts"]
	var a := pts[w["seg"]]
	var b := pts[w["seg"] + 1]
	var node: Node3D = w["node"]
	var d: Vector3 = (b - a) * float(w["dir"])
	var left := Vector3.UP.cross(d.normalized()) * 0.45    # keeping to the left, as people here do: those coming
	w["side"] = left if dt == 0.0 else (w.get("side", left) as Vector3).lerp(left, 1.0 - exp(-dt * 2.0))   # pass by
	node.global_position = a.lerp(b, clampf(w["t"], 0.0, 1.0)) + (w["side"] as Vector3)
	var want := atan2(d.x, d.z)                            # the model faces +Z
	w["yaw"] = want if dt == 0.0 else lerp_angle(w["yaw"], want, 1.0 - exp(-dt * 6.0))
	node.global_rotation = Vector3(0, w["yaw"], 0)


func _play(w: Dictionary, clip: String, speed: float) -> void:
	var ap: AnimationPlayer = w["anim"]
	if ap == null or not ap.has_animation(clip):
		return
	if ap.current_animation != clip:
		ap.play(clip, 0.3)
	ap.speed_scale = speed
