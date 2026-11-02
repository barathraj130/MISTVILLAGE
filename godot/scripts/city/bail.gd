extends Node
## Karthik's bail (GAME_RULES.md §5), from the day Sundaram gets him out until the end of Part 1:
##   signing   every evening 6–7 PM at Nagar Police Station: in the station, Constable Selvi's desk, E, the register
##             (the same signing picture as the bank's). 7–8 PM is late; three lates are a strike. Before 6 she sends
##             him to the bench. The inspector says what he thinks of it, every time.
##   reminders his phone, at 5 PM and 5:45 (a note and the alarm).
##   missed    no signature by 8 PM: a strike. Selvi texts the warning; the inspector's suspicion rises.
##             A third strike within 7 days cancels bail: Sundaram calls, Karthik spends the next days inside, and
##             ₹15,000 to Sundaram gets bail back (the jail chapter itself is still to be built).
##   border    he may not leave Coimbatore district: where the roads run off the edge of the map (the Kerala border
##             at Walayar to the west, the district's other edges) a police check turns him back; the second time
##             is a strike.
## Nothing of this is written on the screen: the phone, the people and the register say it. F1's bars show the count.
## While the story is playing one of its own steps the evening is the story's (an excuse, as the rules say).

const Tasks := preload("res://scripts/story/tasks.gd")
const Actor := preload("res://scripts/story/actor.gd")
const WINDOW := 18.0 * 60.0                  # 6 PM
const LATE_END := 20.0 * 60.0                # 8 PM: missed
const EDGE := 700.0                          # metres from the map's edge: the border check

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
	var b: Array = city.streamer.index["bounds"]
	var t: float = city.streamer.tile
	city.car.global_position = Vector3(b[0] * t + EDGE - 50.0, city.car.global_position.y + 5.0, city.car.global_position.z)
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
func _border(dt: float) -> void:
	_border_t -= dt
	var who: Node3D = city.walker if city.walker else city.car
	if who == null or _border_t > 0.0 or city.streamer == null or city.streamer.index.is_empty():
		return
	var b: Array = city.streamer.index.get("bounds", [])
	if b.size() < 4:
		return
	var t: float = city.streamer.tile
	var p := who.global_position
	var near: bool = p.x < b[0] * t + EDGE or p.x > (b[2] + 1) * t - EDGE or p.z < b[1] * t + EDGE or p.z > (b[3] + 1) * t - EDGE
	if not near:
		return
	_border_t = 20.0
	var centre := Vector3((b[0] + b[2] + 1) * t * 0.5, p.y, (b[1] + b[3] + 1) * t * 0.5)
	var back := (centre - p).normalized()
	border_tries += 1
	city.hud.say("Police (district border)", "Stop. Where to? ...Karthik, on bail? You can't leave the district. Turn back. Now.", 5.0)
	if who == city.car:                               # turned round, set back on his own side of the check
		city.car.speed = 0.0
		city.car.linear_velocity = Vector3.ZERO
		city.car.global_position = p + back * 40.0 + Vector3.UP * 0.5
		var f: Vector3 = city.car.forward()
		city.car.rotate_y(Vector3(f.x, 0.0, f.z).normalized().signed_angle_to(Vector3(back.x, 0.0, back.z).normalized(), Vector3.UP))
	else:
		who.global_position = p + back * 25.0 + Vector3.UP * 0.5
	print("BAIL border turned back (%d)" % border_tries)
	if border_tries == 2:
		_strike({"en": "The border check called the station. Second time. That's a strike, Karthik. – Selvi",
			"ta": "பார்டர் செக்போஸ்ட்லேர்ந்து ஸ்டேஷனுக்கு போன் வந்துச்சு. ரெண்டாவது தடவ. இது ஒரு ஸ்ட்ரைக். – செல்வி"})
	_save()
