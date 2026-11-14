extends Node
## The citizens (story/citizens.json): people of Coimbatore with a name, a home, a place of work and a day, who go
## on living whether Karthik is there or not (OPEN_WORLD_PLAN_2026-11-14.md, phase 2). Each one's day is a list of
## [minute, what, where]: asleep, at home, walking to the next place, opening a shop, working, eating, waiting at the
## bus stand, chatting, guarding a gate, away (at college, on a delivery). The city's clock (fines.sim) says which.
## Kept in three tiers, by distance from Karthik (the streamer's target: him on foot, or his car):
##   state   everyone, always: what they're doing now and where they are (on the way: along the straight line,
##           by the time) — a few numbers, every half second
##   near    within 70 m, on the loaded streets: a body (a crowd person or one of the Sketchfab people), at their
##           place or walking the footpaths to the next (a route on the footpaths' graph, crossing where the
##           city's walkers cross), at a person's pace, the Walk clip played to it; at their place what the activity
##           shows (serving, arms folded at a gate, on the phone at the bus stop, talking with another there)
##   far     past 100 m: the body is put away again
## Indoors (home, asleep, eating inside, away) they aren't seen. A walk takes the time it takes at a person's pace:
## seen, they arrive when they arrive (the game's minutes run faster than a man walks); unseen, they're where the
## schedule says. Karthik (on foot) can greet one (E): they turn to him, and answer as what they're doing has them
## (`say`). What they know and remember is phase 3 (knowledge.gd).
##   --citizentest[=HH:MM]   (testing) on foot at Gandhipuram at that hour; every 10 s who's where; pictures (--shots=DIR)

const Prof := preload("res://scripts/drive/prof.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const Living := preload("res://scripts/city/sf_living.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const DATA := "res://story/citizens.json"
const STORY := "res://story/slice.json"
const NEAR := 70.0
const FAR := 100.0
const PACE := 1.3                       # m/s, a person walking with somewhere to be
const STRIDE := 1.25                    # metres the crowd's Walk clip covers in a cycle
const SEEN := ["walk", "open", "work", "close", "guard", "wait", "chat", "shop"]   # (the rest: indoors, unseen)

var city
var people: Array = []                  # [{data, act, at (Vector3), node, path, ...}]
var say := {}
var _places := {}                       # place key → Vector2
var _t := 0.0
var _astar := AStar3D.new()
var _graph_sig := ""
var _graph_want := ""                   # the tiles waited for (they settle before the graph is built)
var _graph_wait := 0.0
var _spots := {}                        # place key or "x,z" → [Vector3 on the footpath, facing]
var _slots := {}                        # place → the ids that stand there, in the order they came: their slot
var _label: Label
var _e_down := false
var _test := ""
var _shots := ""
var _test_t := 0.0


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STORY))
	for k in story.get("places", {}):
		var p: Dictionary = story["places"][k]
		_places[k] = Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
	say = d.get("say", {})
	for p in d.get("people", []):
		people.append({"d": p, "act": "", "place": "", "node": null, "path": [], "pi": 0, "wait": 0.0, "pos": Vector3.INF})
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	cl.add_child(_label)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--citizentest"):
			_test = a.get_slice("=", 1) if a.contains("=") else "08:00"
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	print("CITIZENS %d people" % people.size())


func _now() -> float:
	return float(city.fines.sim.minute) if city and city.fines else 480.0


## Where a place is on the map: a story place's key, or [x, z].
func _place(where, p: Dictionary) -> Vector2:
	if where is Array:
		return Vector2(float(where[0]), float(where[1]))
	var w := str(where)
	if w == "home":
		return Vector2(float(p["home"][0]), float(p["home"][1]))
	if w == "work":
		return _place(p["work"], p)
	return _places.get(w, Vector2.ZERO)


## What they're doing at this minute: [index of the entry, the entry].
static func _entry(day: Array, m: float) -> int:
	var i := day.size() - 1
	for j in day.size():
		if float(day[j][0]) <= m:
			i = j
	return i


## Where they are now (the state tier): at the place, or part of the way to the next.
func _where(c: Dictionary, m: float) -> Vector2:
	var p: Dictionary = c["d"]
	var day: Array = p["day"]
	var i := _entry(day, m)
	var e: Array = day[i]
	if str(e[1]) != "walk":
		return _place(e[2], p)
	var prev: Array = day[(i - 1 + day.size()) % day.size()]
	var nxt: Array = day[(i + 1) % day.size()]
	var t0 := float(e[0])
	var t1 := float(nxt[0])
	if t1 <= t0:
		t1 += 1440.0
	var k := clampf((m - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	return _place(prev[2], p).lerp(_place(nxt[2], p), k)


func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(dt)
	Prof.add("citizens", t0)


func _process_timed(dt: float) -> void:
	if city == null or city.streamer == null or city.streamer.target == null:
		return
	if _test != "":
		_run_test(dt)
	_t -= dt
	var me: Vector3 = city.streamer.target.global_position
	if _t <= 0.0:
		_t = 0.5
		_graph()
		var m := _now()
		var off: bool = city.get("indoors") or (city.story != null and city.story.room != null)
		for c in people:
			_think(c, m, me, off)
	for c in people:
		if c["node"] != null:
			_move(c, dt)
	_greet(me)


## Each one, every half second: what now, and near enough to be seen?
func _think(c: Dictionary, m: float, me: Vector3, off: bool) -> void:
	var p: Dictionary = c["d"]
	var day: Array = p["day"]
	var i := _entry(day, m)
	var act := str(day[i][1])
	var target_key := str(day[(i + 1) % day.size()][2]) if act == "walk" else str(day[i][2])
	var target_raw = day[(i + 1) % day.size()][2] if act == "walk" else day[i][2]
	var w2 := _where(c, m)
	var near := Vector2(me.x, me.z).distance_to(w2 if c["node"] == null else Vector2(c["node"].global_position.x, c["node"].global_position.z))
	var changed: bool = act != c["act"] or target_key != c["place"]
	c["act"] = act
	c["place"] = target_key
	if c["node"] == null:
		if off or not act in SEEN or near > NEAR or _astar.get_point_count() == 0:
			return
		var spot := _spot_near(Vector3(w2.x, me.y, w2.y))
		if spot == Vector3.INF:
			return
		_bring(c, spot)
		changed = true
	elif off or near > FAR:
		_away(c)
		return
	if changed:
		var key := str(target_raw)                       # (each at a place has their own slot there)
		if not _slots.has(key):
			_slots[key] = []
		if not _slots[key].has(p["id"]):
			_slots[key].append(p["id"])
		var dest := _spot_for(target_raw, p, _slots[key].find(p["id"]))
		if dest[0] == Vector3.INF:
			return
		c["dest"] = dest
		c["path"] = _route(c["node"].global_position, dest[0])
		c["pi"] = 0
		_play(c, "Walk" if c["path"].size() > 1 else _pose(act))


## A body for them: their model, the crowd's clips, a head that turns to Karthik.
func _bring(c: Dictionary, at: Vector3) -> void:
	var p: Dictionary = c["d"]
	var model := str(p.get("model", "crowd_m1"))
	var n: Node3D
	if model.begins_with("sfa_"):
		n = Living.make(model.substr(4))
	elif ResourceLoader.exists("res://assets/people/%s.glb" % model):
		n = (load("res://assets/people/%s.glb" % model) as PackedScene).instantiate() as Node3D
	if n == null:
		return
	add_child(n)
	n.name = "Citizen_" + str(p["id"])
	n.global_position = Vector3(at.x, _ground(at, at.y), at.z)
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		n.queue_free()
		return
	for clip in (aps[0] as AnimationPlayer).get_animation_list():
		(aps[0] as AnimationPlayer).get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	CrowdClips.add(n, str(p.get("sex", "m")))
	var sks := n.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var hl := HeadLook.new()
		hl.name = "HeadLook"
		sks[0].add_child(hl)
		c["hl"] = hl
	c["node"] = n
	c["anim"] = aps[0]
	c["gest"] = randf_range(3.0, 8.0)


## The height to stand at: the footpath's own, unless the ground there is higher (some footpaths' lines lie under
## the ground the city built: the map's heights and the streets' differ); a footpath on a flyover stays up.
func _ground(p: Vector3, path_y: float) -> float:
	var g: float = city.streamer.height_at(p.x, p.z) if city.streamer else NAN
	return path_y if is_nan(g) else maxf(path_y, g)


func _away(c: Dictionary) -> void:
	if c["node"] and is_instance_valid(c["node"]):
		c["node"].queue_free()
	c["node"] = null
	c["path"] = []


## Along the route at a person's pace; at its end, their place: what the activity looks like.
func _move(c: Dictionary, dt: float) -> void:
	var n: Node3D = c["node"]
	if not is_instance_valid(n):
		c["node"] = null
		return
	var path: Array = c["path"]
	if c["pi"] < path.size():
		var tgt: Vector3 = path[c["pi"]]
		var d := Vector3(tgt.x - n.global_position.x, 0.0, tgt.z - n.global_position.z)
		if d.length() < 0.4:
			c["pi"] += 1
			if c["pi"] >= path.size():
				_arrive(c)
			return
		var step := d.normalized() * minf(PACE * dt, d.length())
		n.global_position += step
		n.global_position.y = lerpf(n.global_position.y, _ground(n.global_position, tgt.y), 1.0 - exp(-dt * 6.0))
		n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 1.0 - exp(-dt * 8.0))
		return
	var face: float = c.get("face", n.rotation.y)
	n.rotation.y = lerp_angle(n.rotation.y, face, 1.0 - exp(-dt * 4.0))
	c["gest"] -= dt
	if c["gest"] <= 0.0:                               # now and then, what the work looks like
		c["gest"] = randf_range(5.0, 11.0)
		_play(c, _gesture(c), 0.4)


func _arrive(c: Dictionary) -> void:
	var act := str(c["act"])
	if act == "walk" or not act in SEEN:               # (there: they go in)
		if not act in SEEN or act == "walk":
			var p: Dictionary = c["d"]
			var day: Array = p["day"]
			var nxt := str(day[(_entry(day, _now()) + 1) % day.size()][1])
			if not nxt in SEEN:
				_away(c)
				return
	if c.has("dest"):
		c["face"] = c["dest"][1]
	_play(c, _pose(act))


static func _pose(act: String) -> String:
	return {"guard": "crowd/Fold", "wait": "Idle", "chat": "Talk", "shop": "Idle", "open": "Idle", "close": "Idle"}.get(act, "Idle")


func _gesture(c: Dictionary) -> String:
	var act := str(c["act"])
	var opts: Array = {"work": ["Talk", "crowd/Give", "crowd/Nod", "Idle"], "open": ["crowd/Give", "Idle"],
		"close": ["crowd/Give", "Idle"], "guard": ["crowd/Fold", "Idle", "crowd/Shake"],
		"wait": ["crowd/PhoneLook", "Idle", "crowd/Phone"], "chat": ["Talk", "crowd/Laugh", "crowd/Nod", "crowd/Wobble"],
		"shop": ["crowd/Point", "Idle", "Talk"]}.get(act, ["Idle"])
	return opts[randi() % opts.size()]


func _play(c: Dictionary, clip: String, blend := 0.3) -> void:
	var ap: AnimationPlayer = c.get("anim")
	if ap == null or not is_instance_valid(ap):
		return
	var held := clip.ends_with("Phone") or clip.ends_with("PhoneLook")
	CrowdClips.hold(c["node"], "phone" if held else "")
	if not ap.has_animation(clip):
		clip = "Idle"
	if ap.current_animation != clip:
		ap.play(clip, blend)
	ap.speed_scale = (PACE / STRIDE) if clip == "Walk" else 1.0


# ---- the footpaths' graph -----------------------------------------------------------------------------------------

## Every footpath of the loaded tiles a graph: their points joined along each path, joined where paths meet (2.5 m)
## and across the road where one path's end faces another's (6–20 m: where the city's walkers cross).
func _graph() -> void:
	var s = city.streamer
	var me: Vector3 = s.target.global_position
	var c := Vector2i(floori(me.x / s.tile), floori(me.z / s.tile))
	var keys: Array = []                                # (the tiles round him only: 3 × 3)
	for k in s.loaded:
		if absi(k.x - c.x) <= 1 and absi(k.y - c.y) <= 1:
			keys.append(k)
	keys.sort()
	var sig := str(keys)
	if sig != _graph_sig:                                # (streets still arriving: wait till they've settled)
		if sig != _graph_want:
			_graph_want = sig
			_graph_wait = 1.5
			return
		_graph_wait -= 0.5
		if _graph_wait > 0.0 and _astar.get_point_count() > 0:
			return
	else:
		return
	_graph_sig = sig
	var t0 := Time.get_ticks_usec()
	_astar.clear()
	_spots.clear()
	var grid := {}
	var ends: Array = []
	var id := 0
	for k in keys:
		var node: Node3D = s.loaded[k]
		if node == null or not is_instance_valid(node):
			continue
		for wk in node.get_meta("walks", []):
			var p: PackedFloat32Array = wk[2]
			var n := p.size() / 3
			if n < 2 or float(wk[1]) < 1.2:
				continue
			var first := id
			for j in n:
				var v := Vector3(p[j * 3], p[j * 3 + 1], p[j * 3 + 2])
				_astar.add_point(id, v)
				if j > 0:
					_astar.connect_points(id - 1, id)
				var cell := Vector2i(floori(v.x / 3.0), floori(v.z / 3.0))
				if not grid.has(cell):
					grid[cell] = []
				grid[cell].append(id)
				id += 1
			ends.append(first)
			ends.append(id - 1)
	for a in _astar.get_point_ids():                    # where paths meet
		var v := _astar.get_point_position(a)
		var cell := Vector2i(floori(v.x / 3.0), floori(v.z / 3.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for b in grid.get(cell + Vector2i(dx, dz), []):
					if b > a and not _astar.are_points_connected(a, b) and v.distance_to(_astar.get_point_position(b)) < 2.5:
						_astar.connect_points(a, b)
	var egrid := {}                                     # across the road, end to end
	for e in ends:
		var v := _astar.get_point_position(e)
		var cell := Vector2i(floori(v.x / 20.0), floori(v.z / 20.0))
		if not egrid.has(cell):
			egrid[cell] = []
		egrid[cell].append(e)
	for e in ends:
		var v := _astar.get_point_position(e)
		var cell := Vector2i(floori(v.x / 20.0), floori(v.z / 20.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for f in egrid.get(cell + Vector2i(dx, dz), []):
					if f > e and not _astar.are_points_connected(e, f):
						var dd := v.distance_to(_astar.get_point_position(f))
						if dd > 6.0 and dd < 20.0:
							_astar.connect_points(e, f)
	print("CITIZENS footpath graph: %d points in %d tiles, %.1f ms" % [_astar.get_point_count(), keys.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	for p in people:                                    # (the old points are gone: new routes)
		if p["node"] != null:
			p["place"] = ""


func _spot_near(at: Vector3) -> Vector3:
	if _astar.get_point_count() == 0:
		return Vector3.INF
	var i := _astar.get_closest_point(at)
	var p := _astar.get_point_position(i)
	return p if Vector2(p.x - at.x, p.z - at.z).length() < 60.0 else Vector3.INF


## Where one of them stands at a place: the footpath nearest it, a step along for each (so two at a shop don't
## stand in each other), facing the place. [position, facing yaw]
func _spot_for(where, p: Dictionary, idx: int) -> Array:
	var pl := _place(where, p)
	var at := _spot_near(Vector3(pl.x, 0.0, pl.y))
	if at == Vector3.INF:
		return [Vector3.INF, 0.0]
	var i := _astar.get_closest_point(at)
	var nb := _astar.get_point_connections(i)
	if not nb.is_empty():                              # a step along the path, by who they are
		var along := (_astar.get_point_position(nb[0]) - at).normalized()
		at += along * float((idx + 1) / 2) * (1.0 if idx % 2 == 0 else -1.0) * 1.3   # (0, +1.3, -1.3, +2.6 ...)
	var to := Vector2(pl.x - at.x, pl.y - at.z)
	var face := atan2(to.x, to.y) if to.length() > 0.5 else 0.0
	return [at, face]


func _route(from: Vector3, to: Vector3) -> Array:
	if _astar.get_point_count() == 0:
		return [to]
	var a := _astar.get_closest_point(from)
	var b := _astar.get_closest_point(to)
	var pts := _astar.get_point_path(a, b)
	var out: Array = []
	for q in pts:
		out.append(q)
	out.append(to)
	return out


# ---- greeting ---------------------------------------------------------------------------------------------------

## Karthik on foot by one of them: E to greet; they turn to him and say what they're at.
func _greet(me: Vector3) -> void:
	var w = city.walker
	var e := Input.is_key_pressed(KEY_E)
	var pressed := e and not _e_down
	_e_down = e
	_label.text = ""
	if w == null or city.get("indoors"):
		return
	var best: Dictionary = {}
	var bd := 2.4
	for c in people:
		if c["node"] != null and is_instance_valid(c["node"]):
			var d: float = (c["node"] as Node3D).global_position.distance_to(w.global_position)
			if d < bd:
				bd = d
				best = c
	for c in people:                                   # (the one he's with looks at him)
		if c.has("hl") and is_instance_valid(c["hl"]):
			(c["hl"] as HeadLook).target = w.global_position + Vector3.UP * 1.6
			(c["hl"] as HeadLook).weight = 0.85 if c == best else 0.0
	if best.is_empty():
		return
	var lang: String = city.story.lang if city.story and "lang" in city.story else "en"
	var nm: String = best["d"]["name"].get(lang, best["d"]["name"]["en"])
	_label.text = ("E: வணக்கம், %s" if lang == "ta" else "E: Vanakkam, %s") % nm
	var vs := get_viewport().get_visible_rect().size
	_label.position = Vector2(vs.x * 0.5 - 90.0, vs.y * 0.78)
	if pressed and city.doors and city.doors._near.is_empty():
		var lines: Array = say.get(str(best["act"]), say.get("walk", {})).get(lang, ["Vanakkam."])
		var line: String = lines[randi() % lines.size()]
		_play(best, "crowd/Nod", 0.2)
		best["gest"] = 2.5
		if city.hud:
			city.hud.say(nm, line, 4.0)
		print("CITIZENS %s (%s) to Karthik: %s" % [nm, best["act"], line])


# ---- testing ------------------------------------------------------------------------------------------------------

func _run_test(dt: float) -> void:
	_test_t += dt
	if not has_meta("set") and city.fines and city.walker == null and Time.get_ticks_msec() > 12000 \
			and city.car.global_position.y < 550.0 and absf(city.car.linear_velocity.y) < 0.2:
		set_meta("set", true)
		if not " ".join(OS.get_cmdline_user_args()).contains("--clock="):   # (--clock= sets it with the sky)
			var hm := _test.split(":")
			city.fines.sim.minute = float(hm[0]) * 60.0 + (float(hm[1]) if hm.size() > 1 else 0.0)
		city.toggle_on_foot()
		if city.walker:                                  # (at Gandhipuram itself, by Kovai Tiffin Centre)
			var y: float = city.streamer.height_at(-250.0, 125.0)
			city.walker.global_position = Vector3(-250.0, (432.7 if is_nan(y) else y) + 0.5, 125.0)
		print("CITIZENTEST on foot at %s, %s" % [city.walker.global_position if city.walker else Vector3.ZERO, city.fines.sim.minute])
	if _test_t >= 10.0:
		_test_t = 0.0
		var seen := 0
		var parts: Array = []
		for c in people:
			if c["node"] != null:
				seen += 1
				var np: Vector3 = (c["node"] as Node3D).global_position
				var gy: float = city.streamer.height_at(np.x, np.z)
				parts.append("%s %s (%+.1f m)" % [c["d"]["id"], c["act"], np.y - gy])
		print("CITIZENTEST %s: %d near (%s); graph %d" % [city.fines.sim.clock_text(_now()) if city.fines else "",
			seen, ", ".join(parts), _astar.get_point_count()])
		if _shots != "" and seen > 0 and not has_meta("portraits") and Time.get_ticks_msec() > 40000:
			set_meta("portraits", true)                    # each one there, from a few metres in front
			var prev := get_viewport().get_camera_3d()
			var cam := Camera3D.new()
			cam.fov = 45.0
			if prev:
				cam.environment = prev.environment
				cam.attributes = prev.attributes
			add_child(cam)
			cam.make_current()
			for c in people:
				if c["node"] == null or not is_instance_valid(c["node"]):
					continue
				var n: Node3D = c["node"]
				var fwd := n.global_basis.z
				cam.global_position = n.global_position + fwd * 3.2 + n.global_basis.x * 1.0 + Vector3.UP * 1.6
				cam.look_at(n.global_position + Vector3.UP * 1.1)
				for f in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg("%s/citizen_%s_%s_%s.jpg" % [_shots, _test.replace(":", ""),
					c["d"]["id"], c["act"]], 0.85)
			if prev:
				prev.make_current()
			cam.queue_free()
