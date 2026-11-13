extends Node3D
## People walking Coimbatore's footpaths (the street's standing people are city_streamer.gd's street life: still
## figures, cheap, for the distance; these move). A pool of the crowd people (crowd.gd's: tools/humans/crowd_cast.py,
## Idle, Talk, Walk, Run, Sit…) set down on the footpaths of the loaded tiles round Karthik, 35–85 m away and out of
## his sight where it can be, and walking them, each at their own pace (the Walk clip played to it: a cycle covers
## 1.25 m), a little to one side of the path; at a path's end, on along the next one that starts there, or turning
## back; turning smoothly, never in a snap. What they do:
##   walk       on along the footpath (one in eight with a phone to the ear, one in eight with a shopping bag:
##              crowd_clips.gd)
##   pause      stop a few seconds, look about (a slow turn), and go on
##   talk       two who meet stop and talk a while (one talks, the other listens, then the other way round)
##   aside      Karthik walking straight at one: a step to the other side of the path, and on
##   clear      a vehicle coming along the footpath at them: they run off it for a moment
##   cross      at a footpath's end with another across the road (6–22 m): now and then they cross. At the kerb,
##              facing over, a look one way and the other; when nothing is coming within 28 m (the traffic, his
##              car), straight over a little quicker than they walk, and on along the far footpath. Nothing comes
##              for 20 s: they give up and turn back
## How many are out follows the city's own clock (fines.sim): most in the morning and the evening, fewest at night.
## Far ones (over 50 m) are updated four times less often; past 85 m they're hidden and set down again near him.
## Not in a room (a story scene under the street), not while the story has the city in a cutscene of its own.
## graphics.gd "walkers": the pool's size (Low 16, Medium 24, High 36, Ultra 48).

const CROWD := "res://assets/people/crowd_%s.glb"
const KINDS := ["m1", "m2", "m3", "m4", "m5", "m6", "w1", "w2", "w3", "w4", "w5", "w6"]
const STRIDE := 1.25
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const SPAWN_MIN := 35.0
const SPAWN_MAX := 85.0
const NEAR := 50.0

var city
var count := 24
var people: Array = []
var _rng := RandomNumberGenerator.new()
var _strips: Array = []                        # [{"p": PackedVector3Array, "c": PackedFloat32Array (cumulative m), "hw": half width}]
var _strips_t := 0.0
var _frame := 0
var crossed := 0                               # (testing: crossings made, start to the far kerb)
var gave_up := 0


func _ready() -> void:
	_rng.randomize()
	var scenes := {}
	for kk in KINDS:
		var path := CROWD % kk
		if ResourceLoader.exists(path):
			scenes[kk] = load(path)
	if scenes.is_empty():
		return
	var keys := scenes.keys()
	for i in count:
		var kk: String = keys[i % keys.size()]
		var node := (scenes[kk] as PackedScene).instantiate() as Node3D
		node.visible = false
		add_child(node)
		var aps := node.find_children("*", "AnimationPlayer", true, false)
		if aps.is_empty():
			node.queue_free()
			continue
		var ap := aps[0] as AnimationPlayer
		for a in ["Walk", "Idle", "Talk", "Run"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		var habit := ""                                  # one in eight on the phone as they go, one in eight with a bag
		if CrowdClips.add(node, kk.left(1)):
			habit = ["phone", "bag", "", "", "", "", "", ""][i % 8]
			CrowdClips.hold(node, habit)
		node.set_meta("habit", habit)
		for m in node.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.scale = Vector3.ONE * _rng.randf_range(0.95, 1.04)
		people.append({"node": node, "ap": ap, "strip": -1, "s": 0.0, "dir": 1.0, "side": 0.0,
			"speed": _rng.randf_range(1.05, 1.5), "state": "off", "timer": 0.0, "yaw": 0.0, "want": 0.0, "acc": 0.0,
			"next_pause": _rng.randf_range(15.0, 50.0), "with": -1, "anim": ""})


## (testing) --walkertest: every 5 s, how many are out and doing what, any stuck (walking but not moving), any off
## the footpath's height; at 30 s the camera behind the nearest one walking, a picture (--shots=DIR), and quit.
var _log_t := 0.0
var _test_t := 0.0
var _last_pos := {}


func _test(dt: float, me: Node3D) -> void:
	_test_t += dt
	_log_t += dt
	if _log_t >= 5.0:
		_log_t = 0.0
		var states := {}
		var stuck := 0
		var off_ground := 0
		var near := 0
		for i in people.size():
			var q: Dictionary = people[i]
			states[q["state"]] = int(states.get(q["state"], 0)) + 1
			if q["state"] == "off":
				continue
			var node: Node3D = q["node"]
			if node.global_position.distance_to(me.global_position) < 40.0:
				near += 1
			if q["state"] == "walk" and _last_pos.has(i) and (node.global_position - _last_pos[i]).length() < 0.5:
				stuck += 1
			_last_pos[i] = node.global_position
			if q["strip"] >= 0 and q["strip"] < _strips.size():
				var want_y: float = _at(_strips[q["strip"]], float(q["s"])).y
				if absf(node.global_position.y - want_y) > 0.25:
					off_ground += 1
		print("WALKERS t=%.0f out of %d: %s, within 40 m %d, stuck %d, off the path's height %d, footpaths %d, busy %.2f, crossed %d, gave up %d" % [_test_t,
			people.size(), str(states), near, stuck, off_ground, _strips.size(), _busy(), crossed, gave_up])
	var crossing := people.any(func(q): return q["state"] in ["kerb", "cross"])
	if (_test_t > (90.0 if "--crosstest" in OS.get_cmdline_user_args() else 30.0) or (crossing and "--crosstest" in OS.get_cmdline_user_args() and _test_t > 60.0)) and not has_meta("shot"):
		var best: Dictionary = {}
		var bd := INF
		for q in people:
			if "--habittest" in OS.get_cmdline_user_args() and (q["state"] != "walk" or (q["node"] as Node).get_meta("habit", "") == ""):
				continue                                 # (testing: one on the phone or with a bag)
			if q["state"] == ("cross" if crossing and people.any(func(o): return o["state"] == "cross") else ("kerb" if crossing else "walk")):
				var dd: float = (q["node"] as Node3D).global_position.distance_to(me.global_position)
				if dd < bd:
					bd = dd
					best = q
		if best.is_empty():
			return
		set_meta("shot", true)
		var n: Node3D = best["node"]
		var fwd := Vector3(sin(float(best["yaw"])), 0, cos(float(best["yaw"])))
		var cam := Camera3D.new()                       # (its own: the city moves its camera every frame)
		add_child(cam)
		if crossing:                                     # (from the side: the road, and them going over it)
			cam.global_position = n.global_position + Vector3(fwd.z, 0, -fwd.x) * 9.0 - fwd * 2.0 + Vector3.UP * 2.4
			cam.look_at(n.global_position + fwd * 2.0 + Vector3.UP * 0.9)
		else:
			cam.global_position = n.global_position - fwd * 5.5 + Vector3.UP * 2.2 + Vector3(fwd.z, 0, -fwd.x) * 1.5
			cam.look_at(n.global_position + fwd * 6.0 + Vector3.UP * 0.8)
			if "--habittest" in OS.get_cmdline_user_args():   # (from the front and side: the hand and what's in it)
				cam.global_position = n.global_position + fwd * 3.2 + Vector3(fwd.z, 0, -fwd.x) * -1.6 + Vector3.UP * 1.6
				cam.look_at(n.global_position + Vector3.UP * 1.1)
		cam.make_current()
		var dir := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				dir = a.get_slice("=", 1)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if dir != "":
			get_viewport().get_texture().get_image().save_jpg(dir + "/walkers.jpg", 0.88)
		if crossing:
			print("WALKERS picture of one %s" % best["state"])
		print("WALKERS picture behind one %.0f m from Karthik" % bd)
		get_tree().quit()


func _process(dt: float) -> void:
	if city == null or people.is_empty():
		return
	var me: Node3D = city.walker if city.walker else city.car
	if me == null or city.streamer == null:
		return
	if city.indoors or (city.story and city.story.room != null):
		for q in people:
			q["node"].visible = false
		return
	_frame += 1
	if "--walkertest" in OS.get_cmdline_user_args():
		_test(dt, me)
	_strips_t -= dt
	if _strips_t <= 0.0:
		_strips_t = 2.0
		_gather(me.global_position)
	var want := int(round(count * _busy()))
	var vel := Vector3.ZERO
	var on_foot := city.walker != null
	if not on_foot and city.car:
		vel = city.car.linear_velocity
	for i in people.size():
		var q: Dictionary = people[i]
		if i >= want:                                          # (fewer out at this hour)
			if q["state"] != "off" and not q["node"].visible:
				q["state"] = "off"
			if q["state"] != "off" and (q["node"] as Node3D).global_position.distance_to(me.global_position) > SPAWN_MIN:
				q["state"] = "off"
				q["node"].visible = false
			if q["state"] == "off":
				continue
		if q["state"] == "off":
			_spawn(q, me.global_position)
			continue
		var node: Node3D = q["node"]
		var d := node.global_position.distance_to(me.global_position)
		if d > SPAWN_MAX + 10.0:
			_spawn(q, me.global_position)
			continue
		q["acc"] = float(q["acc"]) + dt
		if d > NEAR and (_frame + i) % 4 != 0:                 # (far: a quarter as often)
			continue
		var step: float = q["acc"]
		q["acc"] = 0.0
		_think(q, i, step, me, on_foot, vel, d)
		_move(q, step)


## How many of the pool are out at this hour of the city's clock (0.25 at night … 1.0 at the busy hours).
func _busy() -> float:
	var m: float = city.fines.sim.minute if city.fines else 600.0
	var h := m / 60.0
	if h < 5.0 or h >= 23.0:
		return 0.2
	if h < 6.5:
		return lerpf(0.2, 0.7, (h - 5.0) / 1.5)
	if h < 10.0:
		return 1.0                                     # the morning: to work, to school, the tea stalls
	if h < 16.0:
		return 0.75
	if h < 21.0:
		return 1.0                                     # the evening: home, the shops at their busiest
	return lerpf(1.0, 0.2, (h - 21.0) / 2.0)


## The footpaths of the loaded tiles within reach.
func _gather(at: Vector3) -> void:
	_strips.clear()
	for k in city.streamer.loaded:
		var node: Node3D = city.streamer.loaded[k]
		var c := Vector2((k.x + 0.5) * city.streamer.tile, (k.y + 0.5) * city.streamer.tile)
		if c.distance_to(Vector2(at.x, at.z)) > SPAWN_MAX + city.streamer.tile:
			continue
		for wk in node.get_meta("walks", []):
			var p: PackedFloat32Array = wk[2]
			var n := p.size() / 3
			if n < 2 or float(wk[1]) < 1.2:
				continue
			var pts := PackedVector3Array()
			var cum := PackedFloat32Array()
			var run := 0.0
			for j in n:
				var v := Vector3(p[j * 3], p[j * 3 + 1], p[j * 3 + 2])
				if j > 0:
					run += v.distance_to(pts[j - 1])
				pts.append(v)
				cum.append(run)
			if run < 8.0:
				continue
			_strips.append({"p": pts, "c": cum, "hw": float(wk[1]) * 0.5, "road_right": (int(wk[0]) & 4) != 0})
	for q in people:                                   # (the strip numbers have changed: each keeps its own place)
		if q["state"] != "off" and q["state"] != "cross" and q.has("pts"):
			var best := -1
			for j in _strips.size():
				if _strips[j]["p"] == q["pts"]:
					best = j
					break
			if best < 0:
				q["state"] = "off"
				q["node"].visible = false
			else:
				q["strip"] = best


## Set one down on a footpath 35–85 m away, out of Karthik's sight where it can be.
func _spawn(q: Dictionary, at: Vector3) -> void:
	if _strips.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var look := -cam.global_basis.z if cam else Vector3.FORWARD
	for attempt in 12:
		var j := _rng.randi() % _strips.size()
		var st: Dictionary = _strips[j]
		var total: float = st["c"][st["c"].size() - 1]
		var s := _rng.randf_range(0.0, total)
		var pos := _at(st, s)
		var d := pos.distance_to(at)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		var seen := (pos - at).normalized().dot(look) > 0.5 and attempt < 9
		if seen and d < 60.0:
			continue
		q["strip"] = j
		q["pts"] = st["p"]
		q["s"] = s
		q["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
		q["side"] = _road_side(st)                       # (on the paving by the road, not the verge behind it)
		q["state"] = "walk"
		q["timer"] = 0.0
		q["with"] = -1
		var node: Node3D = q["node"]
		node.visible = true
		node.global_position = _at(st, s) + _left(st, s, 1.0) * float(q["side"])
		q["yaw"] = _heading(st, s, float(q["dir"]))
		node.rotation.y = q["yaw"]
		_anim(q, "Walk", float(q["speed"]) / STRIDE)
		return


func _think(q: Dictionary, i: int, dt: float, me: Node3D, on_foot: bool, vel: Vector3, d: float) -> void:
	var node: Node3D = q["node"]
	q["timer"] = float(q["timer"]) - dt
	# a vehicle coming along the footpath at them: off it, quickly
	if not on_foot and d < 9.0 and vel.length() > 3.0:
		var to_me := me.global_position - node.global_position
		if vel.dot(-to_me) > 0.0 and absf(to_me.normalized().cross(vel.normalized()).y) < 0.5 and q["state"] != "clear":
			q["state"] = "clear"
			q["timer"] = 1.6
			q["side"] = _road_side(_strips[q["strip"]]) * -1.0       # (off the paving, onto the verge behind)
			_anim(q, "Run", 1.2)
			return
	match str(q["state"]):
		"clear":
			if float(q["timer"]) <= 0.0:
				q["state"] = "walk"
				_anim(q, "Walk", float(q["speed"]) / STRIDE)
		"walk":
			q["next_pause"] = float(q["next_pause"]) - dt
			if on_foot and d < 3.0:                     # Karthik in the way: a step to the other side
				var fwd := Vector3(sin(float(q["yaw"])), 0, cos(float(q["yaw"])))
				var to_me := me.global_position - node.global_position
				if to_me.dot(fwd) > 0.0 and absf(to_me.dot(Vector3(fwd.z, 0, -fwd.x))) < 0.8:
					var rs := _road_side(_strips[q["strip"]])
					q["side"] = rs + (0.5 if rs < 0.0 else -0.5)    # (a step away from the road, letting him by)
			if float(q["next_pause"]) <= 0.0:
				q["state"] = "pause"
				q["timer"] = _rng.randf_range(2.0, 6.0)
				q["want"] = float(q["yaw"]) + _rng.randf_range(-1.4, 1.4)   # (a look about)
				if on_foot and d < 6.0:
					q["want"] = atan2(me.global_position.x - node.global_position.x, me.global_position.z - node.global_position.z)
				_anim(q, "Idle", _rng.randf_range(0.85, 1.1))
				return
			for j in people.size():                    # two who meet: now and then they stop and talk
				if j == i:
					continue
				var o: Dictionary = people[j]
				if o["state"] != "walk" or o["strip"] != q["strip"]:
					continue
				var on: Node3D = o["node"]
				if on.global_position.distance_to(node.global_position) < 1.6 and _rng.randf() < 0.02:
					var secs := _rng.randf_range(6.0, 14.0)
					for pair in [[q, on.global_position, j], [o, node.global_position, i]]:
						var pq: Dictionary = pair[0]
						var other: Vector3 = pair[1]
						var pn: Node3D = pq["node"]
						pq["state"] = "talk"
						pq["timer"] = secs
						pq["with"] = pair[2]
						pq["want"] = atan2(other.x - pn.global_position.x, other.z - pn.global_position.z)
					_anim(q, "Talk", 1.0)
					_anim(o, "Idle", 0.9)
					return
		"kerb":                                          # at the kerb: a look each way, go when it's clear
			var cr: Dictionary = q["cross"]
			cr["looks"] = float(cr["looks"]) + dt
			var over: Vector3 = cr["to"] - cr["from"]
			var face := atan2(over.x, over.z)
			q["want"] = face + sin(float(cr["looks"]) * 1.6) * 0.9   # (left, right, left)
			if float(cr["looks"]) > 1.8 and _clear_to_cross(cr["from"], cr["to"], me, on_foot):
				q["state"] = "cross"
				q["want"] = face
				_anim(q, "Walk", float(q["speed"]) * 1.15 / STRIDE)
			elif float(q["timer"]) <= 0.0:                # nothing but traffic: back the way they came
				gave_up += 1
				q["state"] = "pause"
				q["timer"] = 1.0
				q["dir"] = -float(q["dir"])
				q["want"] = float(q["yaw"]) + PI
		"cross":
			var cr2: Dictionary = q["cross"]
			var to: Vector3 = cr2["to"]
			var dd := Vector2(to.x - node.global_position.x, to.z - node.global_position.z)
			if dd.length() < 0.4:                         # over: on along the far footpath (found again by its points:
				var j := -1                               #  the strips are gathered afresh every 2 s)
				for k in _strips.size():
					if _strips[k]["p"] == cr2["pts"]:
						j = k
						break
				if j < 0:
					q["state"] = "off"
					node.visible = false
					return
				crossed += 1
				q["strip"] = j
				q["pts"] = cr2["pts"]
				q["s"] = cr2["s"]
				q["dir"] = cr2["dir"]
				q["side"] = _road_side(_strips[j])
				q["state"] = "walk"
				_anim(q, "Walk", float(q["speed"]) / STRIDE)
		"pause":
			if float(q["timer"]) <= 0.0:
				q["state"] = "walk"
				q["next_pause"] = _rng.randf_range(15.0, 50.0)
				_anim(q, "Walk", float(q["speed"]) / STRIDE)
		"talk":
			if int(q["timer"] * 0.5) != int((q["timer"] + dt) * 0.5) and q["with"] >= 0:   # (by turns)
				_anim(q, "Talk" if q["anim"] != "Talk" else "Idle", 1.0)
			if float(q["timer"]) <= 0.0:
				q["state"] = "walk"
				q["with"] = -1
				q["next_pause"] = _rng.randf_range(20.0, 60.0)
				_anim(q, "Walk", float(q["speed"]) / STRIDE)


func _move(q: Dictionary, dt: float) -> void:
	var node: Node3D = q["node"]
	if q["strip"] < 0 or q["strip"] >= _strips.size():
		return
	if q["state"] == "cross":                            # straight over the road
		var cr: Dictionary = q["cross"]
		var to: Vector3 = cr["to"]
		node.global_position = node.global_position.move_toward(to, float(q["speed"]) * 1.15 * dt)
		var y: float = city.streamer.height_at(node.global_position.x, node.global_position.z)
		if not is_nan(y):
			node.global_position.y = y
		q["yaw"] = rotate_toward(float(q["yaw"]), float(q["want"]), dt * 3.2)
		node.rotation.y = q["yaw"]
		return
	var st: Dictionary = _strips[q["strip"]]
	var total: float = st["c"][st["c"].size() - 1]
	var moving: bool = q["state"] == "walk" or q["state"] == "clear"
	if moving:
		var spd: float = float(q["speed"]) * (2.6 if q["state"] == "clear" else 1.0)
		q["s"] = float(q["s"]) + spd * dt * float(q["dir"])
		if float(q["s"]) < 0.0 or float(q["s"]) > total:
			_on_end(q, st, total)
			st = _strips[q["strip"]]
		q["want"] = _heading(st, float(q["s"]), float(q["dir"]))
	var target: Vector3 = _at(st, clampf(float(q["s"]), 0.0, st["c"][st["c"].size() - 1])) \
		+ _left(st, float(q["s"]), 1.0) * float(q["side"])
	if moving:
		var cur := node.global_position
		node.global_position = cur.move_toward(target, maxf(float(q["speed"]) * 3.0, 3.0) * dt)   # (the side step eased)
	q["yaw"] = rotate_toward(float(q["yaw"]), float(q["want"]), dt * 3.2)   # (turning, never a snap)
	node.rotation.y = q["yaw"]


## At a footpath's end: on along one that starts (or ends) within 3 m of here, or back the way they came.
func _on_end(q: Dictionary, st: Dictionary, total: float) -> void:
	var at_end: bool = float(q["s"]) > total
	var here: Vector3 = st["p"][st["p"].size() - 1] if at_end else st["p"][0]
	var opts: Array = []
	var across: Array = []                               # footpaths across the road from here
	for j in _strips.size():
		if j == q["strip"]:
			continue
		var o: Dictionary = _strips[j]
		for e in [[0, 0.0, 1.0], [o["p"].size() - 1, float(o["c"][o["c"].size() - 1]), -1.0]]:
			var dd := (o["p"][e[0]] as Vector3).distance_to(here)
			if dd > 6.0 and dd < 22.0 and absf((o["p"][e[0]] as Vector3).y - here.y) < 1.0:
				across.append([j, e[1], e[2], o["p"][e[0]]])
		if (o["p"][0] as Vector3).distance_to(here) < 3.0:
			opts.append([j, 0.0, 1.0])
		elif (o["p"][o["p"].size() - 1] as Vector3).distance_to(here) < 3.0:
			opts.append([j, float(o["c"][o["c"].size() - 1]), -1.0])
	var p_cross := 1.0 if "--crosstest" in OS.get_cmdline_user_args() else (0.55 if opts.is_empty() else 0.3)
	if not across.is_empty() and _rng.randf() < p_cross:
		var c: Array = across[_rng.randi() % across.size()]
		q["s"] = clampf(float(q["s"]), 0.0, total)
		q["state"] = "kerb"
		q["timer"] = 20.0
		q["cross"] = {"from": _at(st, float(q["s"])), "to": c[3], "pts": _strips[c[0]]["p"], "s": c[1], "dir": c[2], "looks": 0.0}
		var d: Vector3 = c[3] - _at(st, float(q["s"]))
		q["want"] = atan2(d.x, d.z)
		_anim(q, "Idle", 1.0)
		return
	if opts.is_empty():
		q["dir"] = -float(q["dir"])
		q["s"] = clampf(float(q["s"]), 0.0, total)
		q["state"] = "pause"
		q["timer"] = _rng.randf_range(0.8, 2.0)
		q["want"] = float(q["yaw"]) + PI
		_anim(q, "Idle", 1.0)
		return
	var pick: Array = opts[_rng.randi() % opts.size()]
	q["strip"] = pick[0]
	q["pts"] = _strips[pick[0]]["p"]
	q["s"] = pick[1]
	q["dir"] = pick[2]
	q["side"] = _road_side(_strips[pick[0]])


## Nothing coming: no vehicle within 28 m of the crossing that's moving (city_traffic.gd's, and his car when he
## drives it); a car standing still lets them by.
func _clear_to_cross(a: Vector3, b: Vector3, me: Node3D, on_foot: bool) -> bool:
	var mid := (a + b) * 0.5
	if city.get("traffic") and city.traffic:
		for v in city.traffic.vehicles:
			var p: Vector3 = v["pos"]
			if p.distance_to(mid) < 28.0 and float(v.get("speed", 0.0)) > 1.0:
				return false
	if not on_foot and city.car and city.car.global_position.distance_to(mid) < 28.0 and absf(city.car.speed) > 1.0:
		return false
	return true


func _anim(q: Dictionary, name: String, speed: float) -> void:
	var ap: AnimationPlayer = q["ap"]
	var habit: String = (q["node"] as Node).get_meta("habit", "")   # (on the phone, or with a bag: their own clips)
	if habit == "phone" and name in ["Walk", "Idle"]:
		name = "crowd/WalkPhone" if name == "Walk" else "crowd/Phone"
	elif habit == "bag" and name == "Walk":
		name = "crowd/WalkCarry"
	if not ap.has_animation(name):
		name = "Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0]
	if q["anim"] != name:
		ap.play(name, 0.35)                                # (a blend: no snap from one to the next)
		ap.seek(_rng.randf_range(0.0, ap.get_animation(name).length), false)
		q["anim"] = name
	ap.speed_scale = speed


## Where along the footpath's width to walk (left of its line positive): the half nearer the road, with a little
## of one's own.
func _road_side(st: Dictionary) -> float:
	var hw: float = st["hw"]
	var toward := -1.0 if bool(st.get("road_right", false)) else 1.0
	return toward * clampf(hw * 0.5, 0.3, 1.2) + _rng.randf_range(-0.15, 0.15) * hw


func _at(st: Dictionary, s: float) -> Vector3:
	var c: PackedFloat32Array = st["c"]
	var p: PackedVector3Array = st["p"]
	s = clampf(s, 0.0, c[c.size() - 1])
	var lo := 0
	var hi := c.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if c[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(c[hi] - c[lo], 0.001)
	return p[lo].lerp(p[hi], (s - c[lo]) / seg)


func _dir_at(st: Dictionary, s: float) -> Vector3:
	var a := _at(st, s - 0.6)
	var b := _at(st, s + 0.6)
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


func _heading(st: Dictionary, s: float, dir: float) -> float:
	var d := _dir_at(st, s) * dir
	return atan2(d.x, d.z)                                 # (the model faces +Z)


func _left(st: Dictionary, s: float, dir: float) -> Vector3:
	var d := _dir_at(st, s) * dir
	return Vector3(d.z, 0, -d.x)
