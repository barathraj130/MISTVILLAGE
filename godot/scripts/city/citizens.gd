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
##   middle  within 300 m (the footpaths' graph round him), no body: a walk goes on along its real route at a
##           person's pace, so whoever comes into sight is where they'd really be by now
##   far     past 100 m: the body is put away again (the middle tier carries on from where it was)
## Indoors (home, asleep, eating inside, away) they aren't seen. A walk takes the time it takes at a person's pace:
## seen, they arrive when they arrive (the game's minutes run faster than a man walks); unseen, they're where the
## schedule says. Karthik (on foot) can greet one (E): they turn to him, and answer as what they're doing has them
## (`say`). What they know and remember is phase 3 (knowledge.gd).
## Story people with a day of their own ("story": their key in slice.json's people, their model from there): while
## the story has them on stage (story.gd `cast`), the story's is the only one.
## Shops (where someone's day has "open" and "close"): a rolling shutter on the shop's wall (the building's own,
## nearest the place), down before the owner opens and after he's closed, rolling up as he opens it (his "open"
## quarter of an hour) and down as he closes; only round Karthik (a few nodes each). Off by default (`_shutters`).
## They react: in the rain they hurry (running), and those standing about chatting or shopping go in; someone
## collapsing or knocked down near them (`gather`, hospital.gd) brings the near ones round, one on the phone.
##   --citizentest[=HH:MM]   (testing) on foot at Gandhipuram at that hour; every 10 s who's where; pictures (--shots=DIR)

const Prof := preload("res://scripts/drive/prof.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const Living := preload("res://scripts/city/sf_living.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const DATA := "res://story/citizens.json"
const KNOW := "res://story/knowledge.json"
const STORY := "res://story/slice.json"
const NEAR := 70.0
const FAR := 100.0
const PACE := 1.3                       # m/s, a person walking with somewhere to be
const RAIN_PACE := 2.6                  # in the rain: hurrying, half running
const MID := 300.0
const SHUTTER_W := 3.2
const SHUTTER_H := 2.7
const HELP_PACE := 3.6                  # running to someone who's gone down
const STRIDE := 1.25                    # metres the crowd's Walk clip covers in a cycle
const SEEN := ["walk", "open", "work", "close", "guard", "wait", "chat", "shop"]   # (the rest: indoors, unseen)

var city
var people: Array = []                  # [{data, act, at (Vector3), node, path, ...}]
var say := {}
var know := {}                          # knowledge.json: topics, records, dont_know
var heard: Array = []                   # the records he's been told (ids), kept in the save
var _iv := {}                           # the citizen he's interviewing (empty: none)
var _iv_page := "topics"
var _iv_opts: Array = []                # [label, action]
var _iv_box: Label
var _places := {}                       # place key → Vector2
var _t := 0.0
var _astar := AStar3D.new()
var _graph_sig := ""
var _graph_want := ""                   # the tiles waited for (they settle before the graph is built)
var _graph_wait := 0.0
var _spots := {}                        # place key or "x,z" → [Vector3 on the footpath, facing]
var _slots := {}                        # place → the ids that stand there, in the order they came: their slot
var _label: Label
## (off for now: the tiles' building outlines don't always match the designed models' fronts, and a shutter can
## land on an inner wall; --shutters to try them. To do: put them on the kit models' own shop fronts.)
var _shutters := "--shutters" in OS.get_cmdline_user_args()
var _shops := {}                        # place key → {open, close (minutes), node, frac (1 shut .. 0 open)}
var _e_down := false
var _test := ""
var _shots := ""
var _test_t := 0.0
var _test_at := Vector2(-250.0, 125.0)


func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STORY))
	for k in story.get("places", {}):
		var p: Dictionary = story["places"][k]
		_places[k] = Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
	say = d.get("say", {})
	know = JSON.parse_string(FileAccess.get_file_as_string(KNOW))
	var cast: Dictionary = story.get("people", {})
	for p in d.get("people", []):
		if p.has("story") and not p.has("model"):         # (a story person: the model the story gives him)
			p["model"] = str(cast.get(p["story"], {}).get("model", "crowd_m1"))
		if p.has("story") and not p.has("name"):
			p["name"] = cast.get(p["story"], {"en": p["story"]})
		people.append({"d": p, "act": "", "place": "", "node": null, "path": [], "pi": 0, "wait": 0.0, "pos": Vector3.INF})
	for c in people:                                    # (who opens and shuts where, and when)
		var day: Array = c["d"]["day"]
		var op := -1.0
		var cl := -1.0
		var where := ""
		for e in day:
			if str(e[1]) == "open":
				op = float(e[0])
				where = str(e[2])
			elif str(e[1]) == "close":
				cl = float(e[0]) + 15.0
		if op >= 0.0 and cl >= 0.0:
			var key := str(c["d"]["work"]) if where == "work" else where
			_shops[key] = {"open": op, "close": cl, "raw": c["d"]["work"] if where == "work" else where, "p": c["d"], "node": null, "frac": 1.0}
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
			if _test.contains("@"):                          # (HH:MM@x,z: where he stands)
				var xz := _test.get_slice("@", 1).split(",")
				_test_at = Vector2(float(xz[0]), float(xz[1]))
				_test = _test.get_slice("@", 0)
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	_iv_box = Label.new()                               # the questions he can ask (an interview)
	_iv_box.add_theme_font_size_override("font_size", 17)
	_iv_box.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_iv_box.add_theme_constant_override("shadow_offset_x", 2)
	_iv_box.add_theme_constant_override("shadow_offset_y", 2)
	cl.add_child(_iv_box)
	_load_heard.call_deferred()
	print("CITIZENS %d people, %d things known" % [people.size(), know.get("records", []).size()])


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
		if _shutters:
			for key in _shops:
				_shop(_shops[key], m, me, off)
	for c in people:
		if c["node"] != null:
			_move(c, dt)
	for key in _shops:                                  # (the shutters roll: a quarter of a metre a second)
		var sh: Dictionary = _shops[key]
		if sh["node"] != null and is_instance_valid(sh["node"]):
			var want: float = sh.get("want", 1.0)
			sh["frac"] = move_toward(float(sh["frac"]), want, dt * 0.1)
			var cur: MeshInstance3D = sh["curtain"]
			cur.scale.y = maxf(float(sh["frac"]), 0.02)
			cur.position.y = SHUTTER_H - SHUTTER_H * cur.scale.y * 0.5
	_greet(me)


## Each one, every half second: what now, and near enough to be seen?
func _think(c: Dictionary, m: float, me: Vector3, off: bool) -> void:
	var p: Dictionary = c["d"]
	var day: Array = p["day"]
	var i := _entry(day, m)
	var act := str(day[i][1])
	if p.has("story") and city.story and city.story.get("cast") is Dictionary and city.story.cast.has(p["story"]):
		if c["node"] != null:                            # (the story has him: its own, not a second)
			_away(c)
		return
	if _rain() and act in ["chat", "shop"]:             # (rain: no standing about, they go in)
		act = "away"
	if c.get("gather_t", 0.0) > 0.0 and c["node"] != null and (off or (c["node"] as Node3D).global_position.distance_to(me) > FAR):
		c["gather_t"] = 0.0                              # (he's gone from there: so are they)
	if c.get("gather_t", 0.0) > 0.0:                     # (round someone who's gone down)
		c["gather_t"] -= 0.5
		if c["gather_t"] > 0.0:
			return
		c["place"] = ""
	var target_key := str(day[(i + 1) % day.size()][2]) if act == "walk" else str(day[i][2])
	var target_raw = day[(i + 1) % day.size()][2] if act == "walk" else day[i][2]
	var w2 := _where(c, m)
	if c["node"] == null and c["pos"] != Vector3.INF and c.get("mid_act", "") == act:   # (the middle tier's place)
		w2 = Vector2(c["pos"].x, c["pos"].z)
	var near := Vector2(me.x, me.z).distance_to(w2 if c["node"] == null else Vector2(c["node"].global_position.x, c["node"].global_position.z))
	if c["node"] == null and act in SEEN and near < MID and near > NEAR and not off and _astar.get_point_count() > 0:
		_middle(c, act, target_key, day[(i + 1) % day.size()][2] if act == "walk" else day[i][2], w2)
		return
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
		if c.get("mid_act", "") == act and not c.get("mid_path", []).is_empty():   # (on with the walk it was on)
			c["path"] = c["mid_path"]
			c["pi"] = int(c.get("mid_pi", 0))
			c["dest"] = c.get("mid_dest", [spot, 0.0])
			c["act"] = act
			c["place"] = target_key
			_play(c, "Walk" if c["pi"] < c["path"].size() else _pose(act))
			return
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


## A shop's shutter near Karthik: put on its wall, shut or open by the hour; rolling while its owner opens or shuts it.
func _shop(sh: Dictionary, m: float, me: Vector3, off: bool) -> void:
	var pl := _place(sh["raw"], sh["p"])
	var d := Vector2(me.x, me.z).distance_to(pl)
	if off or d > FAR:
		if sh["node"] != null and is_instance_valid(sh["node"]):
			sh["node"].queue_free()
		sh["node"] = null
		return
	var open_now: bool = m >= float(sh["open"]) + 15.0 and m < float(sh["close"]) - 15.0   # (between his opening and closing it)
	var owner_open := false                             # (rolling only with him there doing it)
	for c in people:
		if c["d"] == sh["p"] and c["node"] != null and str(c["act"]) in ["open", "close"] and int(c["pi"]) >= (c["path"] as Array).size():
			owner_open = true
	if sh["node"] == null:
		if d > NEAR:
			return
		var foot: Array = _spot_for(sh["raw"], sh["p"], 0)    # (the wall facing the footpath he stands on)
		var wall := _wall_near(pl if foot[0] == Vector3.INF else Vector2(foot[0].x, foot[0].z))
		if wall.is_empty():
			return
		sh["node"] = _make_shutter(wall)
		sh["curtain"] = (sh["node"] as Node3D).get_meta("curtain")
		if _test != "":
			var sp: Vector3 = (sh["node"] as Node3D).global_position
			var nn: Vector2 = wall["n"]
			print("CITIZENTEST shutter at %.1f,%.1f,%.1f facing %.2f,%.2f" % [sp.x, sp.y, sp.z, nn.x, nn.y])
		sh["frac"] = 0.0 if open_now else 1.0           # (as it is at this hour, already)
	var act_open := false
	for c in people:
		if c["d"] == sh["p"]:
			act_open = str(c["act"]) == "open"
	if owner_open:
		sh["want"] = 0.0 if act_open else 1.0
	elif not open_now:
		sh["want"] = 1.0
	elif sh.get("want", -1.0) < 0.0 or float(sh["frac"]) > 0.99 and m > float(sh["open"]) + 15.0:
		sh["want"] = 0.0                                # (open by now: he opened it while no one was looking)


## The wall of the building nearest a point: [the point on it, its outward normal], from the tiles' outlines.
func _wall_near(p: Vector2) -> Dictionary:
	var s = city.streamer
	var best := 25.0
	var out := {}
	for k in s.loaded:
		var node: Node3D = s.loaded[k]
		if node == null or not is_instance_valid(node):
			continue
		for b in node.get_meta("bldinfo", []):
			var centre: Vector2 = b[1]
			if centre.distance_to(p) > 60.0:
				continue
			var poly: PackedVector2Array = b[0]
			for i in poly.size():
				var a := poly[i]
				var e := poly[(i + 1) % poly.size()]
				if a.distance_to(e) < SHUTTER_W + 0.4:
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, a, e)
				var ed := (e - a).normalized()
				var nrm := Vector2(ed.y, -ed.x)
				if nrm.dot(q - centre) < 0.0:
					nrm = -nrm
				if nrm.dot(p - q) < 0.3 * q.distance_to(p):      # (only a wall that faces the footpath: a shop front)
					continue
				var dd := q.distance_to(p) + (0.0 if bool(b[3]) else 4.0)   # (a shop's building before a house)
				if dd < best:
					var lo := a + ed * (SHUTTER_W * 0.5 + 0.2)   # (whole on the wall)
					var hi := e - ed * (SHUTTER_W * 0.5 + 0.2)
					q = Geometry2D.get_closest_point_to_segment(q, lo, hi)
					best = dd
					out = {"at": q, "n": nrm}
	return out


func _make_shutter(wall: Dictionary) -> Node3D:
	var at: Vector2 = wall["at"]
	var n: Vector2 = wall["n"]
	var y: float = city.streamer.height_at(at.x, at.y)
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(at.x + n.x * 0.08, (0.0 if is_nan(y) else y), at.y + n.y * 0.08)
	root.rotation.y = atan2(n.x, n.y)
	var mat := StandardMaterial3D.new()                  # (ribbed galvanised steel: stripes drawn into a texture)
	var img := Image.create(4, 32, false, Image.FORMAT_RGB8)
	for j in 32:
		var v := 0.47 if j % 4 == 0 else (0.62 if j % 4 == 1 else 0.56)
		for i in 4:
			img.set_pixel(i, j, Color(v, v, v * 1.02))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(1, 6, 1)
	mat.metallic = 0.55
	mat.roughness = 0.45
	var cur := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SHUTTER_W, SHUTTER_H, 0.04)
	cur.mesh = bm
	cur.material_override = mat
	cur.position.y = SHUTTER_H * 0.5
	root.add_child(cur)
	var box := MeshInstance3D.new()                      # (the housing it rolls into)
	var hb := BoxMesh.new()
	hb.size = Vector3(SHUTTER_W + 0.2, 0.32, 0.32)
	box.mesh = hb
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.4, 0.41, 0.42)
	hm.metallic = 0.4
	hm.roughness = 0.55
	box.material_override = hm
	box.position = Vector3(0, SHUTTER_H + 0.16, 0.1)
	root.add_child(box)
	root.set_meta("curtain", cur)
	return root


## No body, but on their way: along the real route at a person's pace (half-second steps).
func _middle(c: Dictionary, act: String, key: String, raw, at: Vector2) -> void:
	var p: Dictionary = c["d"]
	if c.get("mid_act", "") != act or c.get("mid_key", "") != key or c["pos"] == Vector3.INF:
		c["mid_act"] = act
		c["mid_key"] = key
		var start := _spot_near(Vector3(at.x, 0.0, at.y))
		if start == Vector3.INF:
			return
		c["pos"] = start
		var dest := _spot_for(raw, p, 0)
		if dest[0] == Vector3.INF:
			c["mid_path"] = []
			return
		c["mid_dest"] = dest
		c["mid_path"] = _route(start, dest[0]) if act == "walk" or c["pos"].distance_to(dest[0]) > 3.0 else []
		c["mid_pi"] = 0
	var path: Array = c.get("mid_path", [])
	var left := (RAIN_PACE if _rain() else PACE) * 0.5
	while left > 0.0 and int(c["mid_pi"]) < path.size():
		var tgt: Vector3 = path[c["mid_pi"]]
		var d: float = c["pos"].distance_to(tgt)
		if d <= left:
			c["pos"] = tgt
			c["mid_pi"] = int(c["mid_pi"]) + 1
			left -= d
		else:
			c["pos"] = c["pos"] + (tgt - c["pos"]).normalized() * left
			left = 0.0


func _rain() -> bool:
	return city.fines != null and str(city.fines.sim.weather) == "rain"


## Someone gone down near them (a collapse, a knock-down): the near ones come round and stand a while, one on the
## phone (for the 108), the others shaking their heads, looking on.
## Has the first of those gathering reached him?
func gathered() -> bool:
	for c in people:
		if c.get("gather_t", 0.0) > 0.0 and c["node"] != null and int(c["pi"]) >= (c["path"] as Array).size():
			return true
	return false


func gather(at: Vector3) -> int:
	var k := 0
	for c in people:
		if c["node"] == null or not is_instance_valid(c["node"]):
			continue
		if (c["node"] as Node3D).global_position.distance_to(at) > 45.0:
			continue
		var ang := k * 1.3
		var spot := at + Vector3(cos(ang), 0.0, sin(ang)) * (2.6 + 0.4 * (k % 3))
		c["path"] = _route(c["node"].global_position, spot)
		c["pi"] = 0
		c["dest"] = [spot, atan2(at.x - spot.x, at.z - spot.z)]
		c["gather_t"] = 45.0
		c["gather_clip"] = "crowd/Phone" if k == 0 else ("crowd/Shake" if k % 2 == 1 else "Idle")
		_play(c, "Walk")
		k += 1
	if k > 0:
		print("CITIZENS %d gather round at %.0f,%.0f" % [k, at.x, at.z])
	return k


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
	if c["node"] != null and is_instance_valid(c["node"]):
		c["pos"] = (c["node"] as Node3D).global_position    # (the middle tier carries on from here)
		c["mid_act"] = c["act"]
		c["mid_key"] = c["place"]
		c["mid_path"] = c["path"]
		c["mid_pi"] = c["pi"]
		c["mid_dest"] = c.get("dest", [c["pos"], 0.0])
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
		var pace := HELP_PACE if c.get("gather_t", 0.0) > 0.0 else (RAIN_PACE if _rain() else PACE)   # (hurrying)
		var step := d.normalized() * minf(pace * dt, d.length())
		n.global_position += step
		n.global_position.y = lerpf(n.global_position.y, _ground(n.global_position, tgt.y), 1.0 - exp(-dt * 6.0))
		n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), 1.0 - exp(-dt * 8.0))
		return
	var face: float = c.get("face", n.rotation.y)
	n.rotation.y = lerp_angle(n.rotation.y, face, 1.0 - exp(-dt * 4.0))
	c["gest"] -= dt
	if c.get("gather_t", 0.0) > 0.0:                    # (gathered round: they stay with it)
		return
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
	if c.get("gather_t", 0.0) > 0.0:
		_play(c, str(c.get("gather_clip", "Idle")))
		return
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
	if clip == "Walk" and (_rain() or c.get("gather_t", 0.0) > 0.0) and ap.has_animation("Run"):
		clip = "Run"                                   # (hurrying: out of the rain, or to someone down)
		if ap.current_animation != clip:
			ap.play(clip, blend)
	var run_pace := HELP_PACE if c.get("gather_t", 0.0) > 0.0 else RAIN_PACE
	ap.speed_scale = (PACE / STRIDE) if clip == "Walk" else ((run_pace / 3.9) if clip == "Run" else 1.0)


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
	if not _iv.is_empty():
		if w == null or _iv["node"] == null or not is_instance_valid(_iv["node"]) or (_iv["node"] as Node3D).global_position.distance_to(w.global_position) > 4.0:
			_end_interview()
		return
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
		if str(best["act"]) != "walk":                   # (one in a hurry won't stop to talk)
			interview(best)


# ---- interviews -------------------------------------------------------------------------------------------------

func _lang() -> String:
	return city.story.lang if city.story and "lang" in city.story else "en"


func _tx(d) -> String:
	return str(d.get(_lang(), d.get("en", ""))) if d is Dictionary else str(d)


func _flag(k: String) -> bool:
	if city.story == null or not (city.story.get("flags") is Dictionary):
		return false
	return bool(city.story.flags.get(k, false))


## Talking with one of them: what he can ask (the topics he knows of), or something of his to show them.
func interview(c: Dictionary) -> void:
	_iv = c
	_iv_page = "topics"
	if city.walker:
		city.walker.active = false
	c["gather_t"] = 0.0
	_play(c, "Idle")
	_menu()


func _end_interview() -> void:
	if city.walker:
		city.walker.active = true
	_iv = {}
	_iv_box.text = ""


func _menu() -> void:
	_iv_opts = []
	if _iv_page == "topics":
		for tp in know.get("topics", []):
			if tp.has("needs") and not _flag(str(tp["needs"])):
				continue
			_iv_opts.append([_tx(tp), "ask:" + str(tp["key"])])
		var ev: Dictionary = city.story.get("evidence") if city.story and city.story.get("evidence") is Dictionary else {}
		if not ev.is_empty():
			_iv_opts.append(["Show something" if _lang() == "en" else "எதையாவது காட்டு", "page:evidence"])
		_iv_opts.append(["Thank them and go" if _lang() == "en" else "நன்றி சொல்லிட்டு போ", "bye"])
	else:
		var ev2: Dictionary = city.story.get("evidence")
		for tag in ev2:
			_iv_opts.append([_tx(ev2[tag].get("title", {"en": tag})), "ask:evidence:" + str(tag)])
		_iv_opts.append(["Back" if _lang() == "en" else "பின்னால", "page:topics"])
	var nm: String = _tx(_iv["d"]["name"])
	var lines: Array = [("Ask %s:" if _lang() == "en" else "%s-கிட்ட கேளு:") % nm]
	for i in _iv_opts.size():
		lines.append("%d  %s" % [i + 1, _iv_opts[i][0]])
	_iv_box.text = "\n".join(lines)
	var vs := get_viewport().get_visible_rect().size
	_iv_box.position = Vector2(vs.x * 0.06, vs.y * 0.42)


func _input(e: InputEvent) -> void:
	if _iv.is_empty() or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = (e as InputEventKey).keycode
	if k == KEY_ESCAPE or k == KEY_E:
		_end_interview()
		get_viewport().set_input_as_handled()
		return
	var n := k - KEY_1
	if n >= 0 and n < _iv_opts.size():
		get_viewport().set_input_as_handled()
		_choose(str(_iv_opts[n][1]))


func _choose(a: String) -> void:
	if a == "bye":
		_play(_iv, "crowd/Nod", 0.2)
		_end_interview()
		return
	if a.begins_with("page:"):
		_iv_page = a.substr(5)
		_menu()
		return
	ask(_iv, a.substr(4))
	_menu()


## What they say to a question, from what they know: seen or heard, sure or not; nothing if they don't know (they
## say so). What he's told goes in his phone's notes, with when and where and how they came by it; one that doesn't
## fit something he's already been told, he notices (a thought); one that names someone else, he notes the name.
func ask(c: Dictionary, topic: String) -> Dictionary:
	var who := str(c["d"]["id"])
	var nm: String = _tx(c["d"]["name"])
	var rec: Dictionary = {}
	for r in know.get("records", []):
		if str(r["who"]) == who and str(r["topic"]) == topic:
			rec = r
	if rec.is_empty():
		var dk: Array = know.get("dont_know", {}).get(_lang(), ["I don't know."])
		if city.hud:
			city.hud.say(nm, dk[randi() % dk.size()], 3.5)
		_play(c, "crowd/Shrug" if randf() < 0.6 else "crowd/Shake", 0.2)
		print("CITIZENS asked %s about %s: doesn't know" % [who, topic])
		return {}
	if city.hud:
		city.hud.say(nm, _tx(rec["text"]), 6.0)
	_play(c, "Talk" if bool(rec.get("firsthand", false)) else "crowd/Shrug", 0.2)
	c["gest"] = 5.0
	if not str(rec["id"]) in heard:
		heard.append(str(rec["id"]))
		_note(rec)
		_save_heard()
	var thought := ""
	if rec.has("contradicts") and str(rec["contradicts"]) in heard:
		var other := _rec(str(rec["contradicts"]))
		var on: String = _tx(_person(str(other.get("who", "")))["name"]) if not other.is_empty() else ""
		thought = ("(That isn't what %s told me.)" if _lang() == "en" else "(%s சொன்னது இது இல்லையே.)") % on
	elif rec.has("lead"):
		var ln: String = _tx(_person(str(rec["lead"])).get("name", {"en": str(rec["lead"]).capitalize()}))
		thought = ("(%s. I should ask %s.)" if _lang() == "en" else "(%s. அவர்கிட்ட கேக்கணும்.)") % [ln, ln]
	if thought != "" and city.hud:
		get_tree().create_timer(6.0).timeout.connect(func(): city.hud.say("Karthik", thought, 4.0))
	print("CITIZENS asked %s about %s: %s (%s, %.1f)%s" % [who, topic, str(rec["id"]), "seen" if rec.get("firsthand", false) else "heard",
		float(rec.get("confidence", 0.5)), (" " + thought) if thought != "" else ""])
	return rec


func _rec(id: String) -> Dictionary:
	for r in know.get("records", []):
		if str(r["id"]) == id:
			return r
	return {}


func _person(id: String) -> Dictionary:
	for c in people:
		if str(c["d"]["id"]) == id:
			return c["d"]
	return {}


func _note(rec: Dictionary) -> void:
	if city.phone == null or not "statements" in city.phone:
		return
	var p := _person(str(rec["who"]))
	var how_en := "%s; %s%s" % [str(rec["seen"].get("en", "")) if rec.has("seen") else "", "saw it" if rec.get("firsthand", false) else "heard it",
		", not sure" if float(rec.get("confidence", 0.5)) < 0.5 else ""]
	var how_ta := "%s; %s%s" % [rec["seen"].get("ta", "") if rec.has("seen") else "", "நேரில் பார்த்தது" if rec.get("firsthand", false) else "கேட்டது",
		", உறுதியில்லை" if float(rec.get("confidence", 0.5)) < 0.5 else ""]
	city.phone.statements.push_front({"id": rec["id"], "who": p.get("name", {"en": rec["who"]}), "text": rec["text"],
		"how": {"en": how_en, "ta": how_ta}})


func _save_heard() -> void:
	if city.fines:
		city.fines._save_data["statements"] = heard.duplicate()
		if city.fines.has_method("save") and city.fines.persist:
			city.fines.save()


func _load_heard() -> void:
	if city == null or city.fines == null:
		return
	heard = Array(city.fines._save_data.get("statements", []))
	for id in heard:
		var r := _rec(str(id))
		if not r.is_empty():
			_note(r)


# ---- testing ------------------------------------------------------------------------------------------------------

## (testing) A camera on `at` from `dist` away, the way `dir` points or turned from it, wherever it sees it clear.
func _aim(cam: Camera3D, at: Vector3, dir: Vector3, dist: float, up: float) -> void:
	var space := cam.get_world_3d().direct_space_state
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, PI]:
		var d := dir.rotated(Vector3.UP, turn).normalized()
		var p := at + d * dist + Vector3.UP * (up - 1.1)
		var q := PhysicsRayQueryParameters3D.create(at, p)
		if space.intersect_ray(q).is_empty():
			cam.global_position = p
			cam.look_at(at)
			return
	cam.global_position = at + dir * dist + Vector3.UP * (up - 1.1)
	cam.look_at(at)


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
			var y: float = city.streamer.height_at(_test_at.x, _test_at.y)
			city.walker.global_position = Vector3(_test_at.x, (432.7 if is_nan(y) else y) + 0.5, _test_at.y)
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
		var mids: Array = []
		for c in people:
			if c["node"] == null and c["pos"] != Vector3.INF and c.get("mid_act", "") in SEEN:
				mids.append("%s %s %.0f m" % [c["d"]["id"], c["mid_act"], Vector2(c["pos"].x, c["pos"].z).distance_to(Vector2(city.streamer.target.global_position.x, city.streamer.target.global_position.z))])
		print("CITIZENTEST %s%s: %d near (%s); middle: %s; graph %d" % [city.fines.sim.clock_text(_now()) if city.fines else "",
			" rain" if _rain() else "", seen, ", ".join(parts), ", ".join(mids), _astar.get_point_count()])
		if "--interviewtest" in OS.get_cmdline_user_args() and not has_meta("interviewed") and Time.get_ticks_msec() > 30000:
			set_meta("interviewed", true)                 # (testing: everyone near asked everything, Rafiq first)
			var order := people.filter(func(c): return c["node"] != null)
			order.sort_custom(func(a, b): return str(a["d"]["id"]) == "rafiq")
			for c in order:
				interview(c)
				for tp in know.get("topics", []):
					ask(c, str(tp["key"]))
				for tag in ["E05", "E07", "E14"]:
					ask(c, "evidence:" + tag)
				_end_interview()
			if city.phone and _shots != "":
				city.phone.hold(true)
				city.phone._open_app("notes")
				for f in 20:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg("%s/interview_notes.jpg" % _shots, 0.9)
				city.phone._open_app("case")
				for f in 10:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg("%s/interview_night.jpg" % _shots, 0.9)
				city.phone.hold(false)
		for a in OS.get_cmdline_user_args():              # (testing: --shotview=x,y,z>x,y,z[;...]: pictures from there)
			if a.begins_with("--shotview=") and not has_meta("viewed") and Time.get_ticks_msec() > 35000 and _shots != "":
				set_meta("viewed", true)
				var vc := Camera3D.new()
				var pv := get_viewport().get_camera_3d()
				if pv:
					vc.environment = pv.environment
					vc.attributes = pv.attributes
					vc.far = pv.far
				vc.fov = 60.0
				add_child(vc)
				vc.make_current()
				var vi := 0
				for v in a.substr(11).split(";"):
					var ab := v.split(">")
					var p0 := ab[0].split(",")
					var p1 := ab[1].split(",")
					vc.global_position = Vector3(float(p0[0]), float(p0[1]), float(p0[2]))
					vc.look_at(Vector3(float(p1[0]), float(p1[1]), float(p1[2])))
					for f in 20:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_jpg("%s/view_%d.jpg" % [_shots, vi], 0.9)
					vi += 1
				if pv:
					pv.make_current()
				vc.queue_free()
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
				_aim(cam, n.global_position + Vector3.UP * 1.1, n.global_basis.z, 3.2, 1.6)
				for f in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg("%s/citizen_%s_%s_%s.jpg" % [_shots, _test.replace(":", ""),
					c["d"]["id"], c["act"]], 0.85)
			for key in _shops:                              # (and each shop's shutter, now and 12 s on)
				var sh: Dictionary = _shops[key]
				if sh["node"] == null or not is_instance_valid(sh["node"]):
					continue
				var sn: Node3D = sh["node"]
				_aim(cam, sn.global_position + Vector3.UP * 1.4, sn.global_basis.z, 4.5, 2.2)
				for shot in 2:
					for f in 3:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_jpg("%s/shop_%s_%s_%d.jpg" % [_shots, _test.replace(":", ""), key, shot], 0.85)
					print("CITIZENTEST shop %s shutter %.2f" % [key, float(sh["frac"])])
					await get_tree().create_timer(12.0).timeout
			if prev:
				prev.make_current()
			cam.queue_free()
