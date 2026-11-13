extends Node
## The street's standing people brought to life near Karthik on foot. city_streamer.gd's street life puts people on
## the footpaths as still figures (MultiMesh instances tagged "people"), cheap for the distance but statues close
## to. Within ~40 m of him each standing figure is swapped for one of the crowd people (crowd_m1–6, crowd_w1–6:
## a man for a man, a woman for a woman), on the same spot, facing the same way, alive:
##   idle    breathing and shifting their weight (their Idle, each at its own pace and point), now and then a slow
##           look to one side and back
##   phone   a quarter of them on the phone, the phone to the ear or looked at in the hand (crowd_clips.gd)
##   talk    two standing within a couple of metres of each other turn to each other and talk by turns
## Figures caught mid-stride (the walking ones) are only hidden near him (city_walkers.gd walks people there); the
## traffic police and the riders on parked bikes stay as they are. Past ~55 m the figure is put back. Swaps are made
## out of his view where possible (or far enough not to notice). Only on foot in the street: in the car (when
## city_bystanders.gd moves the figures out of a vehicle's way) or indoors, everyone is put back.
## How many at once follows the graphics preset (graphics.gd "living": Low 12, Medium 20, High 28).

const Prof := preload("res://scripts/drive/prof.gd")
const Graphics := preload("res://scripts/graphics.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
# a conversation's mood: what the talker does by turns with Talk, and how the other takes it (crowd_clips.gd)
const MOODS := {"friendly": [["crowd/Laugh", "Talk"], ["crowd/Wobble", "crowd/Laugh", "Idle"]],
	"serious": [["Talk", "crowd/Point"], ["crowd/Nod", "Idle"]],
	"arguing": [["crowd/Argue", "Talk"], ["crowd/Shake", "crowd/Argue", "Idle"]]}
const NEAR := 40.0
const FAR := 55.0
const SEEN_OK := 30.0                                  # beyond this a swap in view isn't noticed
const MEN := ["crowd_m1", "crowd_m2", "crowd_m3", "crowd_m4", "crowd_m5", "crowd_m6"]
const WOMEN := ["crowd_w1", "crowd_w2", "crowd_w3", "crowd_w4", "crowd_w5", "crowd_w6"]

var city
var live := {}                                         # "mmid:i" → {node, anim, mms, i, xf, kind, mode, t, look, mate}
var hidden := {}                                       # "mmid:i" → {mms, i, xf}: walking figures hidden near him
var _pool := {"m": [], "w": []}                        # spare animated people
var _scan_t := 0.0
var _scenes := {}
var _foot_t := 0.0                                     # how long he's been on foot
var _nearest := INF                                    # (testing: the nearest figure at the last look)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():                 # (testing: --livingat=x,z: the car starts there)
		if a.begins_with("--livingat=") and city:
			var v := a.get_slice("=", 1).split(",")
			city.spawn = Vector3(float(v[0]), 0.0, float(v[1]))


func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(dt)
	Prof.add("living", t0)


func _tick(dt: float) -> void:
	if city == null or city.streamer == null:
		return
	var view_test := "--livingview" in OS.get_cmdline_user_args()   # (testing: round the free camera, a fixed view)
	var off: bool = (city.walker == null and not view_test) or city.get("indoors") or "--livingbench" in OS.get_cmdline_user_args() or (city.story != null and city.story.room != null) \
		or "--noliving" in OS.get_cmdline_user_args()      # (on foot is a walker; in the car there's none)
	if ("--livingtest" in OS.get_cmdline_user_args() or "--livingbench" in OS.get_cmdline_user_args()) and city.walker == null and Time.get_ticks_msec() > 8000 and not has_meta("out") \
			and city.car and city.car.global_position.y < 550.0 and absf(city.car.speed) < 0.5:   # (the car set down first)
		set_meta("out", true)                             # (testing: out of the car, on the footpath)
		print("LIVING out of the car: %s, driving %s" % [city.toggle_on_foot(), city.driving])
	if "--livingbench" in OS.get_cmdline_user_args() and city.walker != null:
		_test(dt)
	if off:
		_foot_t = 0.0
		if not live.is_empty() or not hidden.is_empty():
			_put_all_back()
		return
	_foot_t += dt
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 0.5 if _foot_t > 2.0 else 0.1
		_nearest = INF
		_scan()
	for key in live:
		_behave(live[key], dt)
	if "--livingtest" in OS.get_cmdline_user_args():
		_test(dt)
	elif "--livingbench" in OS.get_cmdline_user_args():   # (testing: the same report with the people off)
		_test(dt)


## (testing) --livingtest: every 5 s how many are alive and hidden, the frame rate; at 26 s a picture (--shots=DIR).
var _tt := 0.0
var _acc_t := 0.0
var _acc_n := 0
var _tl := 0.0
func _test(dt: float) -> void:
	_tt += dt
	_tl += dt
	if _tt > 12.0:
		_acc_t += dt
		_acc_n += 1
	if _tl >= 5.0:
		_tl = 0.0
		var talking := 0
		for k in live:
			talking += 1 if live[k]["mate"] != "" else 0
		if _acc_n > 0:
			print("LIVING average since 12 s: %.1f fps (%.1f ms)" % [_acc_n / _acc_t, _acc_t * 1000.0 / _acc_n])
		print("LIVING t=%.0f live %d (talking %d) hidden %d, budget %d, nearest figure left %.0f m, %.0f fps" % [_tt, live.size(),
			talking, hidden.size(), _budget(), _nearest, Engine.get_frames_per_second()])
	if _tt > 22.0 and not has_meta("shot"):
		set_meta("shot", true)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg(a.get_slice("=", 1) + "/living.jpg", 0.85)


func _budget() -> int:
	return {"low": 12, "medium": 20, "high": 28, "ultra": 28}.get(Graphics.preset(), 16)


## Who's near: swap the near ones in (nearest first, within the budget), put the far ones back.
func _scan() -> void:
	var me: Vector3 = city.walker.global_position if city.walker else get_viewport().get_camera_3d().global_position
	var cam := get_viewport().get_camera_3d()
	var names: Array = city.streamer.life_names
	var seen := {}
	var cands := []
	for k in city.streamer.loaded:
		var tile := city.streamer.loaded[k] as Node3D
		if tile == null or not is_instance_valid(tile):
			continue
		var groups := {}
		for c in tile.get_children():
			if c is MultiMeshInstance3D and c.has_meta("people") and (c as MultiMeshInstance3D).multimesh:
				var g: String = c.get_meta("people")
				if not groups.has(g):
					groups[g] = []
				groups[g].append(c)
		for g in groups:
			var first := groups[g][0] as MultiMeshInstance3D
			var mm := first.multimesh
			if not (first.global_transform * mm.get_aabb()).grow(NEAR).has_point(me):
				continue
			var kind := int(str(g).get_slice(",", 0))
			var nm: String = names[kind] if kind < names.size() else ""
			if nm.contains("police") or nm.contains("rider"):
				continue
			for i in mm.instance_count:
				var key := "%d:%d" % [first.get_instance_id(), i]
				seen[key] = true
				if live.has(key) or hidden.has(key):
					continue
				var xf := first.global_transform * mm.get_instance_transform(i)
				var d := xf.origin.distance_to(me)
				if d > NEAR or xf.basis.get_scale().length() < 0.01:
					continue
				var in_view := cam != null and cam.is_position_in_frustum(xf.origin + Vector3.UP)
				_nearest = minf(_nearest, d)
				if in_view and d < SEEN_OK and d > 8.0 and _foot_t > 2.0:   # (just out of the car: the view is new anyway)
					continue                                  # (he'd see it change: wait till he looks away)
				cands.append([d, key, groups[g], i, xf, nm])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		var nm: String = c[5]
		if nm.ends_with("_walk") or nm.contains("schoolboy"):
			hidden[c[1]] = {"mms": c[2], "i": c[3], "xf": c[4]}
			_set_xf(c[2], c[3], Transform3D(Basis().scaled(Vector3.ZERO), c[4].origin))
		elif live.size() < _budget():
			_bring(c[1], c[2], c[3], c[4], nm)
	for key in live.keys():                               # far now, or its tile gone: back to a figure
		var p: Dictionary = live[key]
		if not seen.has(key) or p["xf"].origin.distance_to(me) > FAR:
			_put_back(key)
	for key in hidden.keys():
		var h: Dictionary = hidden[key]
		if not seen.has(key) or h["xf"].origin.distance_to(me) > FAR:
			_set_xf(h["mms"], h["i"], h["xf"])
			hidden.erase(key)
	_pair_up()


func _set_xf(mms: Array, i: int, xf: Transform3D) -> void:
	var done := {}
	for m in mms:
		var mi := m as MultiMeshInstance3D
		if not is_instance_valid(mi) or done.has(mi.multimesh):
			continue
		done[mi.multimesh] = true
		mi.multimesh.set_instance_transform(i, mi.global_transform.affine_inverse() * xf)


func _person(sex: String) -> Node3D:
	if not _pool[sex].is_empty():
		return _pool[sex].pop_back()
	var list: Array = WOMEN if sex == "w" else MEN
	var nm: String = list[randi() % list.size()]
	if not _scenes.has(nm):
		_scenes[nm] = load("res://assets/people/%s.glb" % nm)
	var n := (_scenes[nm] as PackedScene).instantiate() as Node3D
	for a in n.find_children("*", "AnimationPlayer", true, false):
		for clip in (a as AnimationPlayer).get_animation_list():
			(a as AnimationPlayer).get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	n.set_meta("sex", sex)
	return n


func _bring(key: String, mms: Array, i: int, xf: Transform3D, nm: String) -> void:
	var sex := "w" if nm.contains("woman") or nm.contains("women") or nm in ["sf_woman_saree_green", "sf_woman_office", "sf_woman_office2"] else "m"
	var n := _person(sex)
	if n.get_parent() == null:
		add_child(n)
	n.visible = true
	var b := xf.basis.orthonormalized()
	var yaw := atan2(b.z.x, b.z.z)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), xf.origin)
	var a := n.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var stand := "Idle"                                  # a quarter of them on the phone, or looking at it
	if CrowdClips.add(n, sex) and randf() < 0.25:
		stand = "crowd/Phone" if randf() < 0.5 else "crowd/PhoneLook"
	CrowdClips.hold(n, "phone" if stand != "Idle" else "")
	n.set_meta("stand", stand)
	a.play(stand)
	a.seek(randf() * a.current_animation_length, true)
	a.speed_scale = randf_range(0.85, 1.15)
	_set_xf(mms, i, Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
	live[key] = {"node": n, "anim": a, "mms": mms, "i": i, "xf": xf, "yaw0": yaw, "mode": "idle", "t": randf_range(3.0, 9.0),
		"look": 0.0, "look_to": 0.0, "mate": ""}


func _put_back(key: String) -> void:
	var p: Dictionary = live[key]
	_set_xf(p["mms"], p["i"], p["xf"])
	var n: Node3D = p["node"]
	if is_instance_valid(n):
		n.visible = false
		_pool[n.get_meta("sex", "m")].append(n)
	var mate: String = p.get("mate", "")
	if mate != "" and live.has(mate):
		live[mate]["mate"] = ""
		live[mate]["mode"] = "idle"
	live.erase(key)


func _put_all_back() -> void:
	for key in live.keys():
		_put_back(key)
	for key in hidden.keys():
		_set_xf(hidden[key]["mms"], hidden[key]["i"], hidden[key]["xf"])
	hidden.clear()


## Karthik near them: they look at him as he comes up (head_look.gd), and some greet him (a nod, a wave, namaste);
## if he runs into them they step back and shake their head or throw up their hands.
func _notice(p: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	var w = city.walker
	if w == null:
		return
	if not p.has("hl"):
		var sks := n.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			p["hl"] = null
			return
		var hl0: HeadLook = sks[0].get_node_or_null("HeadLook")
		if hl0 == null:
			hl0 = HeadLook.new()
			hl0.name = "HeadLook"
			sks[0].add_child(hl0)
		p["hl"] = hl0
	var hl: HeadLook = p["hl"]
	if hl == null:
		return
	var d: float = n.global_position.distance_to(w.global_position)
	var near := d < 3.2
	hl.target = w.global_position + Vector3.UP * 1.6
	hl.weight = 0.8 if near else 0.0
	p["react_t"] = maxf(float(p.get("react_t", 0.0)) - dt, 0.0)
	var spd: float = Vector2(w.velocity.x, w.velocity.z).length() if w is CharacterBody3D else 0.0
	if d < 0.9 and spd > 3.0 and p["react_t"] <= 0.0:   # barged into
		p["react"] = "crowd/Argue" if randf() < 0.5 else "crowd/Shake"
		p["react_t"] = 2.2
		p["annoyed"] = true                             # (they remember: no greeting now, a look away)
		p["t"] = 0.0
		var away: Vector3 = n.global_position - w.global_position
		away.y = 0.0
		n.global_position += away.normalized() * 0.35   # (a step back)
		return
	if p.get("annoyed", false):                         # him again: a shake of the head, and they look elsewhere
		hl.away = 35.0
		if near and d < 2.0 and p["react_t"] <= 0.0 and not p.get("shook", false):
			p["shook"] = true
			p["react"] = "crowd/Shake"
			p["react_t"] = 1.8
			p["t"] = 0.0
		return
	if near and not p.get("greeted", false) and spd < 2.0:
		p["greeted"] = true
		if randf() < 0.45:
			p["react"] = ["crowd/Nod", "crowd/Wobble", "crowd/Wave", "crowd/Namaste"][randi() % 4]
			p["react_t"] = 2.0
			p["t"] = 0.0


## Two standing close together and both free: they turn to each other and talk.
func _pair_up() -> void:
	var keys := live.keys()
	for a in keys.size():
		var pa: Dictionary = live[keys[a]]
		if pa["mate"] != "":
			continue
		for b in range(a + 1, keys.size()):
			var pb: Dictionary = live[keys[b]]
			if pb["mate"] != "":
				continue
			if pa["xf"].origin.distance_to(pb["xf"].origin) < 2.4:
				pa["mate"] = keys[b]
				pb["mate"] = keys[a]
				pa["mode"] = "talk"
				pb["mode"] = "listen"
				var r := randf()                         # (mostly friendly, some serious, now and then an argument)
				var mood := "friendly" if r < 0.5 else ("serious" if r < 0.85 else "arguing")
				pa["mood"] = mood
				pb["mood"] = mood
				var d: Vector3 = pb["xf"].origin - pa["xf"].origin
				pa["yaw0"] = atan2(d.x, d.z)
				pb["yaw0"] = atan2(-d.x, -d.z)
				break


func _behave(p: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	p["t"] -= dt
	if p["t"] <= 0.0:
		match p["mode"]:
			"idle":                                      # a look to one side, then back
				p["look_to"] = randf_range(-0.7, 0.7) if absf(p["look_to"]) < 0.05 else 0.0
				p["t"] = randf_range(4.0, 10.0)
			"talk", "listen":                            # by turns
				var mate: String = p["mate"]
				p["mode"] = "listen" if p["mode"] == "talk" else "talk"
				if live.has(mate):
					live[mate]["mode"] = "talk" if p["mode"] == "listen" else "listen"
					live[mate]["t"] = 99.0
				p["t"] = randf_range(3.0, 6.0)
		var want := "Talk" if p["mode"] == "talk" else str((p["node"] as Node).get_meta("stand", "Idle"))
		if p["mode"] in ["talk", "listen"]:              # the mood's gestures, by turns
			var m: Array = MOODS.get(p.get("mood", "friendly"), MOODS["friendly"])
			var opts: Array = m[0] if p["mode"] == "talk" else m[1]
			want = opts[randi() % opts.size()]
			if p["mode"] == "listen" and want != "Idle":
				p["t"] = minf(p["t"], 2.0)             # (a nod or a laugh, then listening again)
		if p.get("react_t", 0.0) > 0.0:
			want = p["react"]
		var a: AnimationPlayer = p["anim"]
		if a.current_animation != want:
			a.play(want, 0.4)
	_notice(p, dt)
	p["look"] = lerpf(p["look"], p["look_to"], 1.0 - exp(-dt * 1.5))
	n.global_rotation.y = lerp_angle(n.global_rotation.y, p["yaw0"] + p["look"], 1.0 - exp(-dt * 3.0))
