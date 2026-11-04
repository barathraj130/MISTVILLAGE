extends Node
## Karthik's bail (GAME_RULES.md §5), from the day Sundaram gets him out until the end of Part 1:
##   signing   every evening 6–7 PM at Nagar Police Station: in the station, Constable Selvi's desk, E, the register
##             (the same signing picture as the bank's). 7–8 PM is late; three lates are a strike. Before 6 she sends
##             him to the bench. The inspector says what he thinks of it, every time.
##   reminders his phone, at 5 PM and 5:45 (a note and the alarm).
##   missed    no signature by 8 PM: a strike. Selvi texts the warning; the inspector's suspicion rises.
##             A third strike within 7 days cancels bail: Sundaram calls, Karthik spends the next days inside, and
##             ₹15,000 to Sundaram gets bail back (the jail chapter itself is still to be built).
##   border    he may not leave Coimbatore district: at the foot of each ghat out of Mettupalayam (Kallar on the
##             Coonoor road, the Kotagiri road's first climb) a police checkpost turns him back, and so do the
##             checkposts where any other road leaves the built world (borders.json); the second time is a strike.
## Nothing of this is written on the screen: the phone, the people and the register say it. F1's bars show the count.
## While the story is playing one of its own steps the evening is the story's (an excuse, as the rules say).

const Tasks := preload("res://scripts/story/tasks.gd")
const Actor := preload("res://scripts/story/actor.gd")
const WINDOW := 18.0 * 60.0                  # 6 PM
const LATE_END := 20.0 * 60.0                # 8 PM: missed

var city
var active := false
var signed_day := -1                         # the last day he signed
var lates := 0
var strikes: Array = []                      # game days of the strikes
var suspicion := 30.0                        # the inspector's (0..100)
var border_tries := 0
var _reminded := {}                          # "day:minute" → true
var _missed_checked := -1
var _border_t := 0.0
var _tasks: Control
var _cast := {}                              # the station's people in free play: key → Actor
var _signing := false
var _e_down := false


func _ready() -> void:
	var sd: Dictionary = city.fines._save_data.get("bail", {})
	active = bool(sd.get("active", false))
	signed_day = int(sd.get("signed_day", -1))
	lates = int(sd.get("lates", 0))
	strikes = sd.get("strikes", [])
	suspicion = float(sd.get("suspicion", 30.0))
	border_tries = int(sd.get("border", 0))
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_tasks = Tasks.new()
	_tasks.visible = false
	_tasks.finished.connect(_signed)
	layer.add_child(_tasks)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bailtest="):
			_test.call_deferred(arg.get_slice("=", 1))


## (testing) --bailtest=DIR: an evening in free play, with screenshots: the reminders, the station too early, the
## signing, the next evening missed, the district border.
func _test(dir: String) -> void:
	var tree := get_tree()
	city.fines.persist = false
	await tree.create_timer(14.0).timeout
	start()
	var sim = city.fines.sim
	sim.minute = 17.0 * 60.0 + 1.0
	await tree.create_timer(1.0).timeout
	sim.minute = 17.0 * 60.0 + 46.0
	await tree.create_timer(1.0).timeout
	city.phone.hold(true)
	city.phone._open_app("messages")
	await _shot(dir, "bail_1_reminders")
	city.phone.hold(false)
	city.car.speed = 0.0
	city.toggle_on_foot()
	var pol: Vector2 = city.doors._police
	var w: Node3D = city.walker
	var d := {}
	for r in [6.0, 10.0, 14.0, 18.0, 24.0, 30.0]:                # (round the station's place: its building's wall)
		for k in 12:
			var a := TAU * k / 12.0
			w.global_position = Vector3(pol.x + cos(a) * r, w.global_position.y + 30.0, pol.y + sin(a) * r)
			w.velocity = Vector3.ZERO
			await tree.create_timer(0.6).timeout
			var dd: Dictionary = city.doors.door_near(w.global_position)
			if not dd.is_empty() and str(dd.get("room", "")) == "police":
				d = dd
				break
		if not d.is_empty():
			break
	print("BAILTEST door: %s" % str(d))
	if d.is_empty():
		tree.quit()
		return
	city.doors.enter(d, w)
	await tree.create_timer(2.5).timeout
	var m := city.doors._room.find_child("Mark_constable", true, false) as Node3D
	w.global_position = m.global_position - m.global_basis.z * 1.3 + Vector3.UP * 0.2
	w.look_at(m.global_position, Vector3.UP)
	await tree.create_timer(1.5).timeout
	print("BAILTEST offer: '%s'" % offer("police", city.doors._room, w.global_position))
	sim.minute = 17.0 * 60.0 + 30.0
	go()
	await tree.create_timer(0.5).timeout
	await _shot(dir, "bail_2_too_early")
	sim.minute = 18.0 * 60.0 + 20.0
	go()
	_tasks.skip = true
	await tree.create_timer(0.8).timeout
	await _shot(dir, "bail_3_register")
	await tree.create_timer(3.0).timeout
	await _shot(dir, "bail_4_inspector")
	sim.day += 1
	sim.minute = 20.0 * 60.0 + 5.0
	await tree.create_timer(1.0).timeout
	city.phone.hold(true)
	city.phone._open_app("messages")
	city.phone._view = 0
	await tree.create_timer(0.5).timeout
	await _shot(dir, "bail_5_missed")
	city.phone.hold(false)
	city.doors.leave(w)
	await tree.create_timer(1.0).timeout
	city.walker.global_position = city.car.global_position + Vector3.UP
	city.toggle_on_foot()
	_load_borders()
	if not _checks.is_empty():                        # (to the Kallar checkpost, from just below it)
		var c: Dictionary = _checks[0]
		var below := Vector3(float(c["x"]) - float(c["up_x"]) * 120.0, 0.0, float(c["z"]) - float(c["up_z"]) * 120.0)
		city.car.global_position = Vector3(below.x, 900.0, below.z)
		city.car.freeze = true
		for k in 40:                                  # (the ground there loads)
			await tree.create_timer(0.5).timeout
			var g: float = city.streamer.height_at(below.x, below.z)
			if not is_nan(g):
				city.car.global_position = Vector3(below.x, g + 0.8, below.z)
				break
		city.car.freeze = false
		city.car.global_basis = Basis()
		var f: Vector3 = city.car.forward()
		city.car.rotate_y(Vector3(f.x, 0.0, f.z).normalized().signed_angle_to(Vector3(float(c["up_x"]), 0.0, float(c["up_z"])), Vector3.UP))
		await tree.create_timer(1.5).timeout
		await _shot(dir, "bail_6a_below_checkpost")
		city.car.global_position = Vector3(float(c["x"]), city.car.global_position.y, float(c["z"]))
		_border_t = 0.0
		await tree.create_timer(1.0).timeout
		await _shot(dir, "bail_6_border")
	print("BAILTEST done: strikes %d lates %d suspicion %.0f border %d" % [strikes.size(), lates, suspicion, border_tries])
	tree.quit()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [dir, name], 0.85)


func start() -> void:
	active = true
	_save()


func _save() -> void:
	city.fines._save_data["bail"] = {"active": active, "signed_day": signed_day, "lates": lates, "strikes": strikes,
		"suspicion": snappedf(suspicion, 0.1), "border": border_tries}


func _day() -> int:
	return int(city.fines.sim.day)


func _min() -> float:
	return float(city.fines.sim.minute)


## The story is playing one of its own steps (an arrest, a scene): the evening is excused.
func _story_owns() -> bool:
	var st = city.story
	return st != null and st.step >= 0 and str(st.cur.get("do", "")) != "free"


func _process(dt: float) -> void:
	if not active or city.fines == null:
		return
	_station_people()
	_border(dt)
	if _story_owns():
		return
	var d := _day()
	var m := _min()
	if signed_day != d:
		for r in [[WINDOW - 60.0, {"en": "Sign at Nagar Police Station: 6–7 PM", "ta": "நகர் காவல் நிலையத்துல கையெழுத்து: 6–7"}],
				[WINDOW - 15.0, {"en": "Signing in 15 minutes. Nagar Police Station.", "ta": "இன்னும் 15 நிமிஷத்துல கையெழுத்து. நகர் காவல் நிலையம்."}]]:
			var key := "%d:%d" % [d, int(r[0])]
			if m >= float(r[0]) and m < LATE_END and not _reminded.has(key):
				_reminded[key] = true
				city.phone.note(r[1])
				city.phone.message({"en": "Reminder", "ta": "நினைவூட்டல்"}, r[1])
	if m >= LATE_END and signed_day != d and _missed_checked != d:
		_missed_checked = d
		_strike({"en": "Inspector asked where you were tonight. Come tomorrow, six o'clock, without fail. – Selvi",
			"ta": "இன்னைக்கு ராத்திரி நீ எங்கன்னு இன்ஸ்பெக்டர் கேட்டாரு. நாளைக்கு ஆறு மணிக்கு கண்டிப்பா வா. – செல்வி"})


func _strike(warning: Dictionary) -> void:
	strikes = strikes.filter(func(sd): return _day() - int(sd) < 7)
	strikes.append(_day())
	suspicion = minf(suspicion + 25.0, 100.0)
	city.phone.message({"en": "Constable Selvi", "ta": "கான்ஸ்டபிள் செல்வி"}, warning)
	if city.life:
		city.life.add_stress(15.0)
	print("BAIL strike %d (day %d), suspicion %.0f" % [strikes.size(), _day(), suspicion])
	if strikes.size() >= 3:
		_cancel()
	_save()


## Three strikes in a week: bail is cancelled. Sundaram calls; the days inside pass; his fee gets bail back.
func _cancel() -> void:
	print("BAIL cancelled")
	city.phone.call_from({"en": "Sundaram sir (advocate)", "ta": "சுந்தரம் சார் (வக்கீல்)"})
	await city.phone.call_answered
	city.hud.say("Sundaram sir", "Thambi, they've cancelled your bail. Three missed evenings! Go to the station and sit. I'll come with the papers.", 7.0)
	await get_tree().create_timer(7.5).timeout
	if city.life:
		await city.life._pass(3.0 * 1440.0, "three days inside", null, {"sleep": true, "stress": 20.0, "rough": true})
	city.fines.sim.money -= 15000
	strikes.clear()
	lates = 0
	suspicion = 70.0
	signed_day = _day()
	city.phone.message({"en": "Sundaram sir (advocate)", "ta": "சுந்தரம் சார் (வக்கீல்)"},
		{"en": "Bail restored. My fee, ₹15,000, I have taken from you. Do not make me do this again, thambi.",
		"ta": "ஜாமீன் திரும்ப கிடைச்சுது. என் ஃபீஸ் ₹15,000 வாங்கிட்டேன். இனிமே இப்படி பண்ணாதே தம்பி."})
	_save()


# ---- the signing ----
## What's to do at this spot of the station (city_doors.gd asks): the register at Selvi's desk.
func offer(room_name: String, room: Node3D, p: Vector3) -> String:
	if not active or room_name != "police" or room == null or _signing:
		return ""
	var m := room.find_child("Mark_constable", true, false) as Node3D
	if m == null or Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length() > 2.2:
		return ""
	return "sign the bail register" if signed_day != _day() and _min() < LATE_END else ""   # (after 8: missed)


func go() -> void:
	var m := _min()
	if m < WINDOW:                                    # too early: she sends him to the bench
		city.hud.say("Constable Selvi", "Six to seven, Karthik. Sit on the bench till six.", 4.0)
		return
	_signing = true
	_tasks.start("sign", {"header": {"en": "Nagar Police Station", "ta": "நகர் காவல் நிலையம்"},
		"form": {"en": "BAIL ATTENDANCE REGISTER", "ta": "ஜாமீன் வருகை பதிவேடு"},
		"fields": [[{"en": "Crime No.", "ta": "குற்ற எண்"}, "412"], [{"en": "Name", "ta": "பெயர்"}, {"en": "Karthik M.", "ta": "கார்த்திக் ம."}],
			[{"en": "Date", "ta": "தேதி"}, "Day %d" % _day()], [{"en": "Time", "ta": "நேரம்"}, city.phone._now()]],
		"sign_label": {"en": "Signature of the accused", "ta": "குற்றம் சாட்டப்பட்டவர் கையொப்பம்"},
		"seal": {"en": "STATION SEAL", "ta": "நிலைய முத்திரை"}},
		city.story.lang if city.story else "en")


func _signed(_result: Dictionary) -> void:
	_signing = false
	if city.walker and city.walker.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sign_now()


## A signature in the register now (the story's own signing calls this too): on time, or late.
func sign_now() -> void:
	var m := _min()
	signed_day = _day()
	var line := ""
	if m <= WINDOW + 60.0:
		suspicion = maxf(suspicion - 5.0, 0.0)
		line = "Hm. On time." if suspicion < 50.0 else "On time today. We'll see tomorrow."
	else:
		lates += 1
		suspicion = minf(suspicion + 10.0, 100.0)
		line = "%s. Six to seven, Karthik. Not eight." % city.phone._now()
		if lates >= 3:                                # three lates are a missed evening
			lates = 0
			line = "Late again. Three times now. That's as good as not coming. Noted."
			_strike({"en": "Three late signings count as a missed one. Be careful. – Selvi", "ta": "மூணு தடவ தாமதமா வந்தா ஒரு நாள் வராத மாதிரி. கவனமா இரு. – செல்வி"})
	if city.hud and not _story_owns():
		city.hud.say("Inspector Murugesan", line, 4.5)
	print("BAIL signed day %d at %s (lates %d, strikes %d, suspicion %.0f)" % [signed_day, city.phone._now(), lates, strikes.size(), suspicion])
	_save()
	if city.life:
		city.life.save()                              # (the rules: an autosave after each signing)


## In free play the station has its people: Selvi at her desk, the inspector at his.
func _station_people() -> void:
	var doors = city.doors
	var inside: bool = doors != null and not doors.inside.is_empty() and str(doors.inside.get("room", "")) == "police" and doors._room != null
	if inside and _cast.is_empty():
		for k in [["selvi", "story_selvi", "Mark_constable"], ["murugesan", "story_murugesan", "Mark_inspector"]]:
			var m := doors._room.find_child(k[2], true, false) as Node3D
			if m == null:
				continue
			var a := Actor.new()
			doors._room.add_child(a)
			a.setup(k[1], k[0], Callable())
			a.floor_y = m.global_position.y
			a.place(m.global_position, m.global_position - m.global_basis.z)
			_cast[k[0]] = a
	elif not inside and not _cast.is_empty():
		for a in _cast.values():
			if is_instance_valid(a):
				a.queue_free()
		_cast.clear()


# ---- the district border ----
## godot/assets/landmarks/borders.json (tools/citygen/boundary.py): "checks", the police checkposts at the ghat feet
## where Coimbatore district ends (Kallar on the Coonoor road, the Kotagiri road's first climb), each with the way up
## the ghat; "area", the outline of the built world (the city and the Mettupalayam corridor). On bail he's turned
## back at a checkpost, and anywhere a road would take him out of the area (the police checkposts on the city's other
## roads out); the second time is a strike.
const BORDERS := "res://assets/landmarks/borders.json"
var _checks: Array = []
var _area := PackedVector2Array()
var _last_inside := Vector3.INF
var _posts := {}                             # check index → the checkpost's set, once its ground has loaded


func _load_borders() -> void:
	if not FileAccess.file_exists(BORDERS):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(BORDERS))
	_area.clear()                                     # (loaded again: once, not twice over)
	if d is Dictionary:
		_checks = d.get("checks", [])
		for q in d.get("area", []):
			_area.append(Vector2(float(q[0]), float(q[1])))
	elif d is Array:
		_checks = d


func _border(dt: float) -> void:
	if _checks.is_empty() and _area.is_empty():
		_load_borders()
	_posts_near()
	_border_t -= dt
	var who: Node3D = city.walker if city.walker else city.car
	if who == null or _border_t > 0.0:
		return
	_border_t = 0.25
	var p := who.global_position
	for c in _checks:                                 # the ghat checkposts
		var cp := Vector3(float(c["x"]), p.y, float(c["z"]))
		if Vector2(p.x - cp.x, p.z - cp.z).length() < 40.0:
			var down := -Vector3(float(c["up_x"]), 0.0, float(c["up_z"]))
			_turn_back(who, cp + down * 35.0, down, "Police (%s)" % str(c["name"]),
				"Stop. Beyond here is the Nilgiris. ...Karthik? On bail? You can't leave Coimbatore district. Turn back.")
			return
	if _area.size() > 2:                              # out of the built world by some other road
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _area):
			_last_inside = p
		elif _last_inside != Vector3.INF:
			var back := Vector3(_last_inside.x - p.x, 0.0, _last_inside.z - p.z).normalized()
			print("BAIL out of the area: %s at (%.0f, %.0f)" % [who.name, p.x, p.z])
			_turn_back(who, _last_inside + back * 20.0, back, "Police checkpost",
				"Stop. Where to? ...On bail, the inspector said: not past the checkposts. Turn back.")


func _turn_back(who: Node3D, to: Vector3, facing: Vector3, who_says: String, line: String) -> void:
	_border_t = 8.0
	border_tries += 1
	city.hud.say(who_says, line, 5.0)
	if who == city.car:
		var spot: Array = _road_spot(to, facing)          # on a carriageway, heading back, not on the median
		to = spot[0]
		facing = spot[1]
		city.car.speed = 0.0
		city.car.linear_velocity = Vector3.ZERO
		var g: float = city.streamer.height_at(to.x, to.z)
		city.car.angular_velocity = Vector3.ZERO
		city.car.global_basis = Basis()                  # upright, whatever it had been doing
		city.car.global_position = Vector3(to.x, (g if not is_nan(g) else to.y) + 0.6, to.z)
		var f: Vector3 = city.car.forward()
		city.car.rotate_y(Vector3(f.x, 0.0, f.z).normalized().signed_angle_to(facing, Vector3.UP))
	else:
		who.global_position = to + Vector3.UP * 0.5
	print("BAIL border turned back (%d) at %s, to (%.0f, %.0f)" % [border_tries, who_says, to.x, to.z])
	if border_tries == 2:
		_strike({"en": "The checkpost called the station. Second time. That's a strike, Karthik. – Selvi",
			"ta": "செக்போஸ்ட்லேர்ந்து ஸ்டேஷனுக்கு போன் வந்துச்சு. ரெண்டாவது தடவ. இது ஒரு ஸ்ட்ரைக். – செல்வி"})
	_save()


## The nearest point of a road's centreline to `to` (within 60 m) and the way along it closest to `facing`.
func _road_spot(to: Vector3, facing: Vector3) -> Array:
	var best := [to, facing]
	var bd := 60.0
	for k in city.streamer.loaded:
		for r in (city.streamer.loaded[k] as Node3D).get_meta("roads", []):
			if str(r["c"]) in ["footway", "track", "path", "service"]:
				continue
			var a = r["p"]
			var n: int = a.size() / 3
			for i in n - 1:
				var p0 := Vector3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2])
				var p1 := Vector3(a[i * 3 + 3], a[i * 3 + 4], a[i * 3 + 5])
				var q := Geometry3D.get_closest_point_to_segment(to, p0, p1)
				var d := Vector2(q.x - to.x, q.z - to.z).length()
				if d < bd:
					var dir := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
					bd = d
					best = [q, dir if dir.dot(facing) >= 0.0 else -dir]
	return best


## The ghat checkposts stand there for good (the police checking set: barricades, the SUV, the policemen), put down
## once the ground under them has loaded.
func _posts_near() -> void:
	if city.streamer == null:
		return
	for i in _checks.size():
		if _posts.has(i):
			continue
		var c: Dictionary = _checks[i]
		var g: float = city.streamer.height_at(float(c["x"]), float(c["z"]))
		if is_nan(g):
			continue
		var mesh: Mesh = city.streamer._scene_mesh("res://assets/city_props/police_checkpoint.glb") if city.streamer.has_method("_scene_mesh") else null
		var set := Node3D.new()
		set.name = "Checkpost%d" % i
		city.add_child(set)
		set.global_position = Vector3(float(c["x"]), g, float(c["z"]))
		set.look_at(set.global_position + Vector3(float(c["up_x"]), 0.0, float(c["up_z"])), Vector3.UP)   # facing down to town
		if mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			set.add_child(mi)
		_posts[i] = set
		print("BAIL checkpost at %s (%.0f, %.0f)" % [c["name"], c["x"], c["z"]])
