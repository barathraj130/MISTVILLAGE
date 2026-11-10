extends Node3D
## People doing something at the places where people do things in Coimbatore's streets (city_walkers.gd has the
## ones walking by): a pool of the crowd people (crowd_m1–6, crowd_w1–6), given out to the spots of the loaded tiles
## round Karthik, nearest first (the tiles keep them: city_streamer.gd metas "spots", "shelters", "bldinfo"):
##   bus      a bus shelter: one to three waiting, facing the road, now and then a look up the road for the bus
##   stall    a stall or a cart: the seller behind it, facing the street; one or two buying in front, talking and
##            listening by turns; after a while one walks off and another comes. Half the stalls are tea stalls,
##            with a bench beside them: two sitting on it, drinking their tea or eating, talking, then getting up
##            and going, and another sitting down in time
##   shade    a bazaar shade or a goods display: the seller standing under it
##   shop     a shop's front (a building with a shopfront): the shopkeeper at the door, 8 AM to 9 PM
##   guard    a tall building with no shop (offices, flats; one in three, the same ones every visit): a security
##            guard walking a short beat along its front, stopping at each end, day and night
## The city's clock decides who's out (the shops and stalls shut at night; fewer wait for a bus). Nobody is set down
## in front of him: a spot is only taken when it's 30 m off or out of sight; one he walks away from is let go past
## 95 m. Far ones (over 50 m) are updated a quarter as often. graphics.gd "activity": the pool's size.

const CROWD := "res://assets/people/crowd_%s.glb"
const KINDS := ["m1", "m2", "m3", "m4", "m5", "m6", "w1", "w2", "w3", "w4", "w5", "w6"]
const STRIDE := 1.25
const REACH := 90.0
const NEAR := 50.0
const BENCH := "res://assets/city_props/life_bench.glb"

var city
var count := 18
var pool: Array = []                       # {"node", "ap", "anim", "role": {} or empty, "yaw", "want", "acc"}
var _roles := {}                           # spot id → [person indices]
var _rng := RandomNumberGenerator.new()
var _scan_t := 0.0
var _frame := 0
var _bench_scene: PackedScene
var _benches := {}                         # tea stall id → its bench (put down while the stall is wanted)


func _ready() -> void:
	_rng.randomize()
	var scenes: Array = []
	for kk in KINDS:
		if ResourceLoader.exists(CROWD % kk):
			scenes.append(load(CROWD % kk))
	if scenes.is_empty():
		return
	for i in count:
		var node := (scenes[(i * 5 + 3) % scenes.size()] as PackedScene).instantiate() as Node3D
		node.visible = false
		add_child(node)
		var aps := node.find_children("*", "AnimationPlayer", true, false)
		if aps.is_empty():
			node.queue_free()
			continue
		var ap := aps[0] as AnimationPlayer
		for a in ["Walk", "Idle", "Talk", "Sit", "SitEat", "SitTalk"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		for m in node.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.scale = Vector3.ONE * _rng.randf_range(0.95, 1.04)
		pool.append({"node": node, "ap": ap, "anim": "", "role": {}, "yaw": 0.0, "want": 0.0, "acc": 0.0})
	if ResourceLoader.exists(BENCH):
		_bench_scene = load(BENCH)


## (testing) --activitytest: every 5 s, how many are at each kind of spot; at 30 s a picture of the nearest of
## each kind (--shots=DIR: activity_<kind>.jpg, from its own camera), and quit.
var _t := 0.0
var _log_t := 0.0


func _test(dt: float, me: Node3D) -> void:
	_t += dt
	if not has_meta("moved"):                              # (--activityat=x,z: the car moved there first)
		set_meta("moved", true)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--activityat=") and city.car:
				var v := a.get_slice("=", 1).split(",")
				var h: float = city.streamer.height_at(float(v[0]), float(v[1]))
				city.car.global_position = Vector3(float(v[0]), (h if not is_nan(h) else 430.0) + 2.0, float(v[1]))
				city.car.linear_velocity = Vector3.ZERO
				_t = -20.0                                 # (time for the tiles there to come in)
	_log_t += dt
	if _log_t >= 5.0:
		_log_t = 0.0
		var by := {}
		for p in pool:
			var r: Dictionary = p["role"]
			var k: String = "free" if r.is_empty() else str(r["kind"])
			by[k] = int(by.get(k, 0)) + 1
		print("ACTIVITY t=%.0f %s (clock %.1f h)" % [_t, str(by), _hour()])
	if _t > 30.0 and not has_meta("shots"):
		set_meta("shots", true)
		var dir := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				dir = a.get_slice("=", 1)
		var cam := Camera3D.new()
		add_child(cam)
		cam.make_current()
		for kind in ["bus", "stall", "tea", "shade", "shop", "guard"]:
			var best: Dictionary = {}
			var bd := INF
			for p in pool:
				var r: Dictionary = p["role"]
				if not r.is_empty() and (r["kind"] == kind or (kind == "tea" and r["state"] == "sit")):
					var dd: float = (p["node"] as Node3D).global_position.distance_to(me.global_position)
					if dd < bd:
						bd = dd
						best = p
			if best.is_empty():
				print("ACTIVITY no %s about" % kind)
				continue
			var n: Node3D = best["node"]
			var f := Vector3(sin(float(best["yaw"])), 0, cos(float(best["yaw"])))
			cam.global_position = n.global_position + f * 5.0 + Vector3.UP * 1.9 + Vector3(f.z, 0, -f.x) * 1.5
			cam.look_at(n.global_position + Vector3.UP * 1.0)
			for k in 4:
				await RenderingServer.frame_post_draw
			if dir != "":
				get_viewport().get_texture().get_image().save_jpg("%s/activity_%s.jpg" % [dir, kind], 0.88)
			print("ACTIVITY picture: %s, %.0f m from him" % [kind, bd])
		get_tree().quit()


func _hour() -> float:
	return (city.fines.sim.minute if city.fines else 600.0) / 60.0


func _process(dt: float) -> void:
	if city == null or pool.is_empty() or city.streamer == null:
		return
	var me: Node3D = city.walker if city.walker else city.car
	if me == null:
		return
	if city.indoors or (city.story and city.story.room != null):
		for p in pool:
			p["node"].visible = false
		for id in _benches:
			_benches[id].visible = false
		return
	_frame += 1
	if "--activitytest" in OS.get_cmdline_user_args():
		_test(dt, me)
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 2.0
		_assign(me.global_position)
	for i in pool.size():
		var p: Dictionary = pool[i]
		if (p["role"] as Dictionary).is_empty():
			continue
		var node: Node3D = p["node"]
		p["acc"] = float(p["acc"]) + dt
		if node.global_position.distance_to(me.global_position) > NEAR and (_frame + i) % 4 != 0:
			continue
		var step: float = p["acc"]
		p["acc"] = 0.0
		_act(p, step, me)


# ---- where people are wanted ----
## The spots near him now, each with how many people it wants and where they go.
func _spots(at: Vector3) -> Array:
	var h := _hour()
	var day := h >= 6.5 and h < 21.5
	var out: Array = []
	for k in city.streamer.loaded:
		var node: Node3D = city.streamer.loaded[k]
		var c := Vector2((k.x + 0.5) * city.streamer.tile, (k.y + 0.5) * city.streamer.tile)
		if c.distance_to(Vector2(at.x, at.z)) > REACH + city.streamer.tile:
			continue
		for sh in node.get_meta("shelters", []):
			var pos: Vector3 = sh[0]
			var n := 1 + absi(hash(Vector2i(roundi(pos.x), roundi(pos.z)))) % 3
			out.append({"id": "bus%d,%d" % [roundi(pos.x), roundi(pos.z)], "kind": "bus", "pos": pos, "yaw": float(sh[1]),
				"n": n if day else (1 if n == 3 else 0)})
		for sp in node.get_meta("spots", []):
			if not day:
				continue
			var pos: Vector3 = sp[1]
			var kind: String = sp[0]
			var id := "%s%d,%d" % [kind, roundi(pos.x), roundi(pos.z)]
			var tea := kind == "stall" and _bench_scene != null and (absi(hash(id + "tea")) % 2 == 0
				or "--teatest" in OS.get_cmdline_user_args())     # (testing: every stall a tea stall)
			var buyers := (2 if tea else absi(hash(id)) % 3) if kind == "stall" else 0
			out.append({"id": id, "kind": kind, "pos": pos, "yaw": float(sp[2]), "n": 1 + buyers, "tea": tea})
		for b in node.get_meta("bldinfo", []):
			var centre: Vector2 = b[1]
			if centre.distance_to(Vector2(at.x, at.z)) > REACH:
				continue
			if "--activitytest" in OS.get_cmdline_user_args() and _scans % 3 == 1:
				_dbg["blds"] = int(_dbg.get("blds", 0)) + 1
				_dbg["shops"] = int(_dbg.get("shops", 0)) + (1 if b[3] else 0)
				_dbg["tall"] = int(_dbg.get("tall", 0)) + (1 if int(b[2]) >= 4 else 0)
				_dbg["front"] = int(_dbg.get("front", 0)) + (0 if _front(node, b).is_empty() else 1)
			# who's at a building is from its street (the map's shop tags and storeys are mostly missing): on a
			# main road, a bazaar or the old town, half the fronts have their shopkeeper out (8 AM–9 PM); a big
			# building on a main road or a planned layout, one in four, a security guard (day and night)
			var bid := "b%d,%d" % [roundi(centre.x), roundi(centre.y)]
			var hsh := absi(hash(bid))
			if hsh % 2 != 0 and hsh % 4 != 1:
				continue
			var fr := _front(node, b)
			if fr.is_empty():
				continue
			var street: int = fr["street"]
			var shopish: bool = b[3] or street in [1, 2, 5]
			if shopish and hsh % 2 == 0 and h >= 8.0 and h < 21.0 and float(fr["area"]) >= 30.0:
				out.append({"id": bid, "kind": "shop", "pos": fr["pos"], "yaw": fr["yaw"], "n": 1, "edge": fr["edge"]})
			elif street in [1, 3] and hsh % 4 == 1 and float(fr["area"]) >= 250.0:
				out.append({"id": bid, "kind": "guard", "pos": fr["pos"], "yaw": fr["yaw"], "n": 1, "edge": fr["edge"]})
	for o in out:
		o["d"] = (o["pos"] as Vector3).distance_to(at)
	out = out.filter(func(o): return float(o["d"]) < REACH and int(o["n"]) > 0)
	out.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	return out


## A building's front: the point of its outline nearest the nearest footpath, just outside it, facing the street;
## and the direction of that wall ("edge"), for a guard's beat.
func _front(node: Node3D, b: Array) -> Dictionary:
	var poly: PackedVector2Array = b[0]
	var centre: Vector2 = b[1]
	var best := INF
	var bp := Vector2.ZERO
	var stype := 0
	var by := 0.0
	for wk in node.get_meta("walks", []):
		var p: PackedFloat32Array = wk[2]
		for j in range(0, p.size() / 3, 2):
			var q := Vector2(p[j * 3], p[j * 3 + 2])
			var dd := q.distance_squared_to(centre)
			if dd < best:
				best = dd
				bp = q
				by = p[j * 3 + 1]                              # (the footpath's top: where he stands)
				stype = (int(wk[0]) >> 4) & 7                  # the street's kind (citygen life.py TYPES)
	if best > 40.0 * 40.0 or poly.size() < 3:
		return {}
	var fp := Vector2.ZERO
	var fd := INF
	var edge := Vector2.RIGHT
	for e in poly.size():
		var a: Vector2 = poly[e]
		var c: Vector2 = poly[(e + 1) % poly.size()]
		var q := Geometry2D.get_closest_point_to_segment(bp, a, c)
		if q.distance_to(bp) < fd:
			fd = q.distance_to(bp)
			fp = q
			edge = (c - a).normalized()
	var out := (bp - fp).normalized() if bp.distance_to(fp) > 0.01 else (fp - centre).normalized()
	var y := by
	var at := fp + out * 0.8
	var face := atan2(out.x, out.y)
	var area := 0.0
	for e in poly.size():
		area += poly[e].x * poly[(e + 1) % poly.size()].y - poly[(e + 1) % poly.size()].x * poly[e].y
	return {"pos": Vector3(at.x, y, at.y), "yaw": face, "edge": Vector3(edge.x, 0, edge.y), "street": stype,
		"area": absf(area) * 0.5}


## Give the pool out to the nearest spots, keeping whoever is already somewhere still wanted.
var _scans := 0
var _dbg := {}


var _last_at := Vector3.INF


func _assign(at: Vector3) -> void:
	_scans += 1
	if _last_at == Vector3.INF or _last_at.distance_to(at) > 150.0:
		_scans = 0                                         # (just arrived somewhere, or set down by the story: fill it)
	_last_at = at
	var spots := _spots(at)
	if "--activitytest" in OS.get_cmdline_user_args() and _scans % 3 == 1:
		var kinds := {}
		for sp in spots:
			kinds[sp["kind"]] = int(kinds.get(sp["kind"], 0)) + 1
		print("ACTIVITY spots within %.0f m: %s; buildings %s" % [REACH, str(kinds), str(_dbg)])
		_dbg = {}
	var want := {}
	var left := pool.size()
	for sp in spots:
		if left <= 0:
			break
		var n: int = mini(int(sp["n"]), left)
		want[sp["id"]] = [sp, n]
		left -= n
	for i in pool.size():                                   # let go those whose spot isn't wanted any more
		var p: Dictionary = pool[i]
		var r: Dictionary = p["role"]
		if r.is_empty():
			continue
		if not want.has(r["id"]) and (p["node"] as Node3D).global_position.distance_to(at) > 40.0:
			p["role"] = {}
			p["node"].visible = false
	for id in _benches.keys():                             # the benches of tea stalls no longer wanted, taken up
		if not want.has(id) and (_benches[id] as Node3D).global_position.distance_to(at) > 40.0:
			_benches[id].queue_free()
			_benches.erase(id)
	for id in want:
		var sp: Dictionary = want[id][0]
		if sp.get("tea", false):
			_bench(sp).visible = true
	var cam := get_viewport().get_camera_3d()
	var look := -cam.global_basis.z if cam else Vector3.FORWARD
	for id in want:                                        # fill the wanted ones not yet full
		var sp: Dictionary = want[id][0]
		var n: int = want[id][1]
		var have: Array = []
		for i in pool.size():
			if not (pool[i]["role"] as Dictionary).is_empty() and pool[i]["role"]["id"] == id:
				have.append(i)
		if have.size() >= n:
			continue
		var pos: Vector3 = sp["pos"]
		var seen := (pos - at).normalized().dot(look) > 0.55 and float(sp["d"]) < 60.0
		if seen and _scans > 2:
			continue                                         # (not set down where he's looking; at the start, anywhere)
		for slot in range(have.size(), n):
			var free := -1
			for i in pool.size():
				if (pool[i]["role"] as Dictionary).is_empty():
					free = i
					break
			if free < 0:
				return
			_start(pool[free], sp, slot)


## A tea stall's bench: beside it, along the way the stall faces, the ones on it facing the stall.
func _bench(sp: Dictionary) -> Node3D:
	if _benches.has(sp["id"]):
		return _benches[sp["id"]]
	var f := Vector3(sin(float(sp["yaw"])), 0, cos(float(sp["yaw"])))
	var side := Vector3(f.z, 0, -f.x)
	var b := _bench_scene.instantiate() as Node3D
	add_child(b)
	b.global_position = (sp["pos"] as Vector3) + side * 2.3 + f * 0.2
	b.rotation.y = atan2(-side.x, -side.z)                  # (its front, +Z, towards the stall; its length along the street's way)
	for m in b.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_benches[sp["id"]] = b
	return b


func _start(p: Dictionary, sp: Dictionary, slot: int) -> void:
	var f := Vector3(sin(float(sp["yaw"])), 0, cos(float(sp["yaw"])))   # (the spot's front, towards the street)
	var side := Vector3(f.z, 0, -f.x)
	var pos: Vector3 = sp["pos"]
	var role := {"id": sp["id"], "kind": sp["kind"], "slot": slot, "timer": _rng.randf_range(4.0, 12.0), "state": "stay"}
	var at := pos
	var face := float(sp["yaw"])
	match str(sp["kind"]):
		"bus":
			at = pos + f * 0.9 + side * (slot - 1) * 1.1
		"stall":
			if slot == 0:
				at = pos - f * 0.9                            # behind it, facing the street
			elif sp.get("tea", false):                       # on the bench, a cup of tea or a bite to eat
				var b := _bench(sp)
				var bx := b.global_basis.x
				var bz := b.global_basis.z
				at = b.global_position + bx * (0.45 if slot == 1 else -0.45) + bz * 0.12
				face = b.rotation.y
				role["state"] = "sit"
				role["sf"] = f
			else:
				var sd := -1.0 if slot == 1 else 1.0          # beside it, a little forward: on the paving, not the road
				at = pos + side * sd * 1.25 + f * 0.25
				face = atan2(pos.x - at.x, pos.z - at.z)
		"shade":
			at = pos - f * 0.4
		"shop":
			at = pos
		"guard":
			var e: Vector3 = sp["edge"]
			role["a"] = pos - e * 3.0
			role["b"] = pos + e * 3.0
			role["state"] = "beat"
			role["to_b"] = true
			at = role["a"]
	role["home"] = at
	role["face"] = face
	p["role"] = role
	var node: Node3D = p["node"]
	node.visible = true
	node.global_position = at
	p["yaw"] = face
	p["want"] = face
	node.rotation.y = face
	if role["state"] == "sit":
		_anim(p, "SitEat" if _rng.randf() < 0.5 else "SitTalk", 1.0)
	else:
		_anim(p, "Walk" if role["state"] == "beat" else ("Talk" if sp["kind"] == "stall" and slot > 0 else "Idle"), 1.0)


# ---- what they do there ----
func _act(p: Dictionary, dt: float, me: Node3D) -> void:
	var r: Dictionary = p["role"]
	var node: Node3D = p["node"]
	r["timer"] = float(r["timer"]) - dt
	match str(r["kind"]):
		"bus":                                           # a look up the road for the bus, then back
			if float(r["timer"]) <= 0.0:
				r["timer"] = _rng.randf_range(6.0, 16.0)
				p["want"] = float(r["face"]) + _rng.randf_range(-1.0, 1.0)
		"stall":
			if int(r["slot"]) > 0:
				if r["state"] == "stay" and float(r["timer"]) <= 0.0:   # talking and listening by turns
					_anim(p, "Idle" if p["anim"] == "Talk" else "Talk", 1.0)
					r["timer"] = _rng.randf_range(3.0, 7.0)
					r["turns"] = int(r.get("turns", 0)) + 1
					if int(r["turns"]) > _rng.randi_range(5, 12):
						r["state"] = "leave"                    # done: off down the street
						var away := Vector3(sin(float(p["yaw"]) + PI * 0.5), 0, cos(float(p["yaw"]) + PI * 0.5)) * (1.0 if _rng.randf() < 0.5 else -1.0)
						r["to"] = node.global_position + away * 9.0
						p["want"] = atan2(away.x, away.z)
						_anim(p, "Walk", 1.2 / STRIDE)
				elif r["state"] == "sit" and float(r["timer"]) <= 0.0:   # eating, then talking, by turns; then up and off
					r["timer"] = _rng.randf_range(5.0, 10.0)
					r["turns"] = int(r.get("turns", 0)) + 1
					if int(r["turns"]) > _rng.randi_range(4, 9):
						r["state"] = "up"
						r["timer"] = 0.8
						_anim(p, "Idle", 1.0)
						node.global_position += Vector3(sin(float(p["yaw"])), 0, cos(float(p["yaw"]))) * 0.35   # (stood up, off the bench)
					else:
						_anim(p, "SitTalk" if p["anim"] == "SitEat" else "SitEat", 1.0)
				elif r["state"] == "up" and float(r["timer"]) <= 0.0:
					r["state"] = "leave"
					var fw := Vector3(sin(float(p["yaw"])), 0, cos(float(p["yaw"])))   # (on past the stall's front: the
					var away := (fw * 9.0 + (r["sf"] as Vector3) * 0.7)                 #  bench is behind him)
					r["to"] = node.global_position + away
					_anim(p, "Walk", 1.2 / STRIDE)
				elif r["state"] == "leave":
					if _walk_to(p, r["to"], 1.2, dt):
						p["role"] = {}                         # (gone; another comes at the next look round)
						node.visible = false
			elif float(r["timer"]) <= 0.0:
				r["timer"] = _rng.randf_range(4.0, 9.0)
				_anim(p, "Talk" if p["anim"] == "Idle" else "Idle", 1.0)
		"shade", "shop":
			if float(r["timer"]) <= 0.0:
				r["timer"] = _rng.randf_range(5.0, 14.0)
				var d := node.global_position.distance_to(me.global_position)
				if d < 8.0:                                 # someone walking up: a look at him
					p["want"] = atan2(me.global_position.x - node.global_position.x, me.global_position.z - node.global_position.z)
				else:
					p["want"] = float(r["face"]) + _rng.randf_range(-0.5, 0.5)
		"guard":
			if r["state"] == "beat":
				var to: Vector3 = r["b"] if r["to_b"] else r["a"]
				if _walk_to(p, to, 0.9, dt):
					r["state"] = "wait"
					r["timer"] = _rng.randf_range(3.0, 7.0)
					_anim(p, "Idle", 1.0)
			elif float(r["timer"]) <= 0.0:
				r["to_b"] = not r["to_b"]
				r["state"] = "beat"
				_anim(p, "Walk", 0.9 / STRIDE)
	p["yaw"] = rotate_toward(float(p["yaw"]), float(p["want"]), dt * 3.0)
	node.rotation.y = p["yaw"]


## Walk towards a point at a pace; true on arrival.
func _walk_to(p: Dictionary, to: Vector3, speed: float, dt: float) -> bool:
	var node: Node3D = p["node"]
	var d := Vector3(to.x - node.global_position.x, 0, to.z - node.global_position.z)
	if d.length() < 0.15:
		return true
	p["want"] = atan2(d.x, d.z)
	if p["anim"] != "Walk":
		_anim(p, "Walk", speed / STRIDE)
	var step := minf(speed * dt, d.length())
	node.global_position += d.normalized() * step
	node.global_position.y = lerpf(node.global_position.y, to.y, minf(1.0, dt * 4.0))
	return false


func _anim(p: Dictionary, name: String, speed: float) -> void:
	var ap: AnimationPlayer = p["ap"]
	if not ap.has_animation(name):
		name = "Idle"
	if p["anim"] != name:
		ap.play(name, 0.35)
		ap.seek(_rng.randf_range(0.0, ap.get_animation(name).length), false)
		p["anim"] = name
	ap.speed_scale = speed
