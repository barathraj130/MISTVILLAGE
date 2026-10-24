extends Node
## The story runner for Part 1 (docs/STORY_BIBLE.md): plays a chapter file (story/slice.json) step by step in the
## Coimbatore city scene. Steps:
##   card      a title card on black (clock set if given); Enter or a few seconds
##   talk      dialogue, Enter for the next line; "backdrop" plays it over black (a scene we can't show yet)
##   drive     an objective: a beam and a map pin at a place; done when you stop inside its radius.
##             "comfort" rates the ride with a passenger (hard braking, swerving, bumps, fines);
##             "ride_talk" plays lines as subtitles while you drive
##             "realtime": the clock runs at real speed (1 game minute a real minute), for drives where the
##             story's timeline matters (GAME_RULES.md §1); "by": a deadline ("22:20"), checked on arrival
##   comfort_verdict  the passenger's word on the ride (5 / 3 / 1 stars)
##   jump      a card on black while the car is moved to another place (the story skips the drive between)
##   deliver_verdict  the customer's word on a delivery made by the deadline or late, and the pay for it
##   task      a hands-on picture task (tasks.gd: sign, count, hang, otp) with a tip from the owner; its result
##             is remembered (e.g. short_found) for later steps
##   scene     a cutscene in the world: the cast (story people, tools/people.py) placed around the car, shots with
##             a camera (positions in the car's frame: x right, y up, z forward, metres), characters walking,
##             talking, getting in; lines as subtitles; black bars. Enter: next shot
##   lapse     time passing on screen: the camera holds on the street while the clock and the sky run to "to"
##   meet      someone standing at the place: get out (F), walk up and press E to talk
##   free      free drive with a goal line, the end of the chapter
## Any step may have "when": flag / "unless": flag (results of earlier tasks) and is skipped otherwise; any line
## may "pay" an amount into the wallet when it's shown (a tip from the owner, a customer).
## T switches English / Tamil at any time. The clock runs (GAME_RULES.md §1) while you drive, pauses on cards
## and in talk.
##   --storyskip     testing: each drive step jumps the car to its place after 3 s, and talk advances by itself
##   --storyshots=D  testing: a screenshot of every card, talk line and arrival into the folder D
##   --storyta       start in Tamil

const Sim := preload("res://scripts/drive/sim.gd")
const Tasks := preload("res://scripts/story/tasks.gd")
const Actor := preload("res://scripts/story/actor.gd")
const CHAPTER := "res://story/slice.json"

var city                            # city_test.gd: car placement, `placed`
var car
var map
var hud
var fines
var lang := "ta" if OS.get_locale_language() == "ta" else "en"
var data := {}
var step := -1
var cur := {}
var line_i := 0
var t_step := 0.0
var stars := 5.0
var _pen := 0.0                     # comfort penalty, in stars
var _prev_v := Vector3.ZERO
var _challans0 := 0
var _ride_i := -1
var _ride_t := 0.0
var _enter_down := false
var _t_down := false
var _skip := false
var _shots := ""
var _jumped := false
var on_time := true                 # the last deadline ("by") was met
var _skip_minutes := 0.0            # (testing) game minutes a skipped real-time drive would have taken
var _shot_n := 0
var _beam: MeshInstance3D
var flags := {}                     # what the player did in tasks (short_found, signed, ...)
var _paid := {}                     # lines that already paid (step:line)
var tasks: Control
var cast := {}                      # story people in the world: key → Actor
var _o := Vector3.ZERO              # the scene frame: origin (the car), forward, right
var _f := Vector3.FORWARD
var _r := Vector3.RIGHT
var scene_cam: Camera3D
var bars: Array = []
var shot_i := -1
var shot_t := 0.0
var _dur := 3.0
var _lapse := Vector2.ZERO          # (from, to) minutes
var _e_down := false

var ui: Control
var backdrop: ColorRect
var big: Label
var small: Label
var box: PanelContainer
var who: Label
var said: Label
var hint: Label
var goal: Label
var clock: Label


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--storyskip":
			_skip = true
		if a == "--storyta":
			lang = "ta"
		if a.begins_with("--storyshots="):
			_shots = a.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_shots)
	_build_ui()
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 70.0
	_beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.75, 0.2, 0.28)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = m
	_beam.visible = false
	add_child(_beam)


func load_chapter(path := CHAPTER) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("story: no chapter at " + path)
		return false
	data = JSON.parse_string(f.get_as_text())
	return data is Dictionary


## Where the car starts (the first scene's place), for the city scene to load the world there.
func spawn_point() -> Vector3:
	var p: Dictionary = data["places"][data["spawn"]]
	return Vector3(p["x"], 0.0, p["z"])


func place_pos(key: String) -> Vector3:
	var p: Dictionary = data["places"][key]
	return Vector3(p["x"], 0.0, p["z"])


func tr_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


# ---- the flow ----
func _process(dt: float) -> void:
	if data.is_empty() or city == null:
		return
	if step < 0:
		if city.placed:
			_next()
		return
	t_step += dt
	_keys()
	match str(cur["do"]):
		"card":
			if t_step > (2.0 if _skip else 5.0):
				_next()
		"talk":
			if _skip and t_step > 1.2:
				_advance_line()
		"drive":
			_drive(dt)
		"comfort_verdict", "deliver_verdict":
			if _skip and t_step > 1.2:
				_advance_line()
		"jump":
			if _place_at(place_pos(cur["to"])) and t_step > (1.5 if _skip else 3.0):
				car.visible = true
				_next()
		"scene":
			_scene(dt)
		"lapse":
			var secs := float(cur.get("secs", 5.0)) * (0.3 if _skip else 1.0)
			var k := clampf(t_step / secs, 0.0, 1.0)
			fines.sim.minute = fmod(lerpf(_lapse.x, _lapse.y, smoothstep(0.0, 1.0, k)), 1440.0)
			if k >= 1.0:
				_cams_back()
				_next()
		"meet":
			_meet()
		"free":
			_tick_clock(dt)
			if _skip and t_step > 4.0:
				print("STORY done: flags %s" % str(flags))
				print("STORY done: comfort %.1f stars, on time %s, wallet %d, clock %s day %d" % [stars, on_time,
					fines.sim.money if fines else 0, _clock12(), fines.sim.day if fines else 1])
				get_tree().quit()
	clock.text = "%s %d   %s" % ["Day" if lang == "en" else "நாள்", fines.sim.day if fines else 1, _clock12()]


func _keys() -> void:
	var enter := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	if enter and not _enter_down:
		match str(cur.get("do", "")):
			"card":
				_next()
			"talk", "comfort_verdict", "deliver_verdict":
				_advance_line()
			"scene":
				if shot_t > 0.3:
					_next_shot()
	_enter_down = enter
	var tk := Input.is_key_pressed(KEY_T)
	if tk and not _t_down:
		lang = "en" if lang == "ta" else "ta"
		_refresh()
	_t_down = tk


func _next() -> void:
	step += 1
	t_step = 0.0
	line_i = 0
	if step >= data["steps"].size():
		return
	for a in OS.get_cmdline_user_args():                # (testing: --storystop=N quits on reaching step N)
		if a.begins_with("--storystop=") and step >= int(a.get_slice("=", 1)):
			get_tree().quit()
	cur = data["steps"][step]
	while (cur.has("when") and not flags.get(cur["when"], false)) or (cur.has("unless") and flags.get(cur["unless"], false)):
		step += 1
		if step >= data["steps"].size():
			return
		cur = data["steps"][step]
	if cur.has("clock") and fines:
		var hm: PackedStringArray = str(cur["clock"]).split(":")
		fines.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
	if cur.has("add_minutes") and fines:                # time that passes off screen (a ride on the scooter)
		fines.sim.minute += float(cur["add_minutes"])
	_jumped = false
	match str(cur["do"]):
		"drive":
			var p := place_pos(cur["to"])
			map.pin = Vector2(p.x, p.z)
			if cur.get("realtime", false):              # (testing: a skipped drive takes its road time at 30 km/h)
				_skip_minutes = Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length() * 1.3 / 500.0
			_beam.visible = true
			if cur.get("comfort", false):
				_pen = 0.0
				_prev_v = car.linear_velocity
				_challans0 = fines.challans.size() if fines else 0
				_ride_i = -1
				_ride_t = 0.0
		"comfort_verdict":
			var k := "5" if stars >= 4.5 else ("3" if stars >= 2.5 else "1")
			cur = {"do": "comfort_verdict", "lines": [cur["lines"][k]]}
		"task":
			tasks.start(str(cur["task"]), cur, lang, _skip)
		"scene":
			_anchor()
			_cast(cur.get("cast", {}))
			if cur.get("hide_car", false):
				car.visible = false
			_cams_on()
			_refresh()
			shot_i = -1
			_next_shot()
			return
		"lapse":
			_anchor()
			_cams_on()
			_put_cam(_w3(cur.get("cam", [3.0, 2.2, -8.0])), _w3(cur.get("look", [-4.0, 4.0, 20.0])))
			var hm: PackedStringArray = str(cur["to"]).split(":")
			var to := float(hm[0]) * 60.0 + float(hm[1])
			_lapse = Vector2(fines.sim.minute, to if to > fines.sim.minute else to + 1440.0)
		"meet":
			_anchor()
			_cast(cur.get("cast", {}))
			var a: Node3D = cast.get(cur["who"])
			if a:
				map.pin = Vector2(a.global_position.x, a.global_position.z)
		"deliver_verdict":
			var k := "ontime" if on_time else "late"
			var pay := int(cur["pay"][k])
			if fines:
				fines.sim.money += pay
			hud.warn(("Delivery paid  +" if lang == "en" else "டெலிவரி பணம்  +") + "₹%d" % pay + ("" if on_time else ("  (late)" if lang == "en" else "  (தாமதம்)")), 5.0)
			cur = {"do": "deliver_verdict", "lines": cur["lines"][k]}
	_refresh()
	_shot()


# ---- scenes ----
## The scene frame is the car where it stands: people and cameras are placed in metres to its right (x), up (y) and
## ahead (z). The car keeps left, so the footpath and the buildings are on its left (negative x).
func _anchor() -> void:
	_o = car.global_position
	_f = Vector3(car.forward().x, 0.0, car.forward().z).normalized()
	_r = _f.cross(Vector3.UP)


func _w2(v: Array) -> Vector3:
	return _o + _r * float(v[0]) + _f * float(v[1])


func _w3(v: Array) -> Vector3:
	var g: float = city.streamer.height_at(_o.x, _o.z)
	var base := Vector3(_o.x, g if not is_nan(g) else _o.y, _o.z)
	return base + _r * float(v[0]) + Vector3.UP * float(v[1]) + _f * float(v[2])


func _cast(spec: Dictionary) -> void:
	for key in spec:
		var d: Dictionary = spec[key]
		if not cast.has(key):
			var a := Actor.new()
			add_child(a)
			a.setup(str(d.get("model", data["people"].get(key, {}).get("model", "person_man_shirt"))), key,
				Callable(city.streamer, "height_at"))
			cast[key] = a
		var act: Node3D = cast[key]
		act.visible = true
		if d.has("pos"):
			act.place(_w2(d["pos"]), _w2(d.get("look", [0.0, 0.0])))
		if d.has("anim"):
			act.play(str(d["anim"]))


func _clear_cast() -> void:
	for a in cast.values():
		a.queue_free()
	cast.clear()


func _cams_on() -> void:
	if scene_cam == null:
		scene_cam = Camera3D.new()
		scene_cam.fov = 50.0
		scene_cam.far = 4000.0
		add_child(scene_cam)
	scene_cam.make_current()
	for b in bars:
		b.visible = true
	goal.visible = false
	backdrop.visible = false
	big.visible = false
	small.visible = false
	map.visible = false                                  # a cutscene: no minimap or speedometer
	hud.visible = false


func _cams_back() -> void:
	for b in bars:
		b.visible = false
	box.visible = false
	map.visible = true
	hud.visible = true
	if city.walker:
		city.walker.camera.make_current()
	else:
		city.cam.make_current()


func _next_shot() -> void:
	shot_i += 1
	shot_t = 0.0
	var shots: Array = cur.get("shots", [])
	if shot_i >= shots.size():
		_cams_back()
		if not cur.get("keep_cast", false):
			_clear_cast()
		if not cur.get("car_stays_hidden", false):
			car.visible = true
		_next()
		return
	var sh: Dictionary = shots[shot_i]
	if sh.has("clock_note") and fines:                   # time moves on within the scene
		var hm: PackedStringArray = str(sh["clock_note"]).split(":")
		fines.sim.minute = float(hm[0]) * 60.0 + float(hm[1])
	for key in sh.get("do", {}):
		var a: Node3D = cast.get(key)
		if a == null:
			continue
		var act: Dictionary = sh["do"][key]
		if act.has("walk"):
			a.walk_to(_w2(act["walk"]), float(act.get("speed", 1.4)), str(act.get("then", "Idle")))
		if act.has("anim"):
			a.play(str(act["anim"]))
		if act.has("look"):
			a.face(_w2(act["look"]))
		if act.has("pos"):
			a.place(_w2(act["pos"]), _w2(act.get("look", [0.0, 0.0])))
		if act.get("hide", false):
			a.visible = false
		if act.get("show", false):
			a.visible = true
	if sh.has("line") and not sh.get("fixed_cam", false) and _auto_frame(str(sh["line"]["who"])):
		pass                                             # dialogue: framed on whoever is speaking
	elif sh.has("cam"):
		_put_cam(_w3(sh["cam"]), _w3(sh.get("look", [0.0, 1.5, 0.0])))
	if sh.has("line"):
		line_i = shot_i
		_say(sh["line"])
		_dur = clampf(str(tr_(sh["line"])).length() / 13.0, 3.0, 9.0)
	else:
		box.visible = false
		_dur = 3.0
	_dur = float(sh.get("dur", _dur))
	_shot()


## Place the scene camera at `at` looking at `look`, but never behind a wall: if something solid stands between
## them (a compound wall, a building), the camera moves in front of it, like the on-foot camera's spring arm.
func _put_cam(at: Vector3, look: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(look, at)
	var ex: Array[RID] = []                              # (the car counts as solid: no shots through its roof)
	if city.walker:
		ex.append(city.walker.get_rid())
	q.exclude = ex
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		at = hit["position"] + (look - at).normalized() * 0.35
	scene_cam.global_position = at
	if at.distance_to(look) > 0.05:
		scene_cam.look_at(look, Vector3.UP)


## Dialogue framing: over the listener's shoulder onto the speaker's face, from the road side; if the speaker isn't
## standing in the scene (Karthik talking from the car), onto the person he's talking to. False if nobody's there.
func _auto_frame(who: String) -> bool:
	var sp: Node3D = cast.get(who)
	if sp != null and not sp.visible:
		sp = null
	var others: Array = []
	for k in cast:
		if k != who and cast[k].visible:
			others.append(cast[k])
	if sp == null:
		if others.is_empty():
			return false
		sp = others[0]                                   # the speaker is off screen: show who listens
		others = []
	var li: Node3D = null
	for o in others:
		if li == null or o.global_position.distance_to(sp.global_position) < li.global_position.distance_to(sp.global_position):
			li = o
	var head := sp.global_position + Vector3.UP * 1.45
	if li != null:
		sp.face(li.global_position)                      # people talk to each other, not to the camera
	# candidate shots, best first; the first with a clear view of the speaker's face wins
	var cands: Array = []
	if li != null and li.global_position.distance_to(sp.global_position) < 6.0:
		var d := Vector3(sp.global_position.x - li.global_position.x, 0.0, sp.global_position.z - li.global_position.z).normalized()
		var side := d.cross(Vector3.UP)
		if side.dot(_r) < 0.0:                           # on the road side, where it's open
			side = -side
		cands.append(li.global_position - d * 0.9 + side * 0.55 + Vector3.UP * 1.62)      # over the listener's shoulder
		var mid := (sp.global_position + li.global_position) * 0.5
		cands.append(mid + side * 3.4 + Vector3.UP * 1.55)                              # a two-shot from the side
	var toward := _r
	if li != null:
		toward = Vector3(li.global_position.x - sp.global_position.x, 0.0, li.global_position.z - sp.global_position.z).normalized().lerp(_r, 0.5).normalized()
	cands.append(sp.global_position + toward * 2.6 + Vector3.UP * 1.55)                  # the speaker alone
	cands.append(sp.global_position + _r * 3.0 + _f * 0.8 + Vector3.UP * 1.6)
	var at: Vector3 = cands[-1]
	for c in cands:
		if _clear(c, head):
			at = c
			break
	scene_cam.global_position = at
	scene_cam.look_at(head - Vector3.UP * 0.12, Vector3.UP)
	return true


func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	return space.intersect_ray(q).is_empty()


func _scene(dt: float) -> void:
	shot_t += dt
	var sh: Dictionary = cur["shots"][shot_i] if shot_i < cur["shots"].size() else {}
	if sh.has("cam2"):                                   # a slow dolly from cam to cam2
		var k := smoothstep(0.0, 1.0, clampf(shot_t / _dur, 0.0, 1.0))
		_put_cam(_w3(sh["cam"]).lerp(_w3(sh["cam2"]), k),
			_w3(sh.get("look", [0.0, 1.5, 0.0])).lerp(_w3(sh.get("look2", sh.get("look", [0.0, 1.5, 0.0]))), k))
	if sh.has("follow"):                                 # keep a walking person in frame
		var a: Node3D = cast.get(sh["follow"])
		if a:
			scene_cam.look_at(a.global_position + Vector3.UP * 1.4, Vector3.UP)
	if shot_t > _dur * (0.25 if _skip else 1.0):
		_next_shot()


func _meet() -> void:
	var a: Node3D = cast.get(cur["who"])
	if a == null:
		_next()
		return
	if _skip and t_step > 1.0:
		_next()
		return
	var near: bool = city.walker != null and city.walker.global_position.distance_to(a.global_position) < 2.4
	if near:
		a.face(city.walker.global_position)
	var e := Input.is_key_pressed(KEY_E)
	if near and e and not _e_down:
		map.pin = null
		_next()
	_e_down = e
	var hint := ""
	if city.walker == null:
		hint = "F: get out of the car" if lang == "en" else "F: காரை விட்டு இறங்குங்க"
	elif near:
		hint = "E: talk" if lang == "en" else "E: பேசுங்க"
	goal.text = tr_(cur["goal"]) + ("\n" + hint if hint != "" else "")


func _task_done(result: Dictionary) -> void:
	for k in result:
		flags[k] = result[k]
	if result.has("minutes") and fines:                 # chores take game time
		fines.sim.minute += float(result["minutes"])
	print("STORY task %s → %s" % [cur.get("task", ""), str(result)])
	_next()


func _advance_line() -> void:
	line_i += 1
	t_step = 0.0
	if line_i >= cur["lines"].size():
		_next()
	else:
		_refresh()
		_shot()


func _drive(dt: float) -> void:
	_tick_clock(dt)
	var p := place_pos(cur["to"])
	var g: float = city.streamer.height_at(p.x, p.z)
	_beam.global_position = Vector3(p.x, (g if not is_nan(g) else car.global_position.y) + 35.0, p.z)
	if _skip and t_step > 3.0 and not _jumped:            # (testing: jump to the place)
		if _skip_minutes > 0.0 and fines:                 # (and spend the minutes a real drive would take)
			fines.sim.minute += _skip_minutes
			_skip_minutes = 0.0
		_place_at(p)
	if cur.get("comfort", false):
		_comfort(dt)
		_ride_talk(dt)
	var d := Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length()
	var r := float(cur.get("radius", 40.0)) + (60.0 if _skip else 0.0)
	if _skip and not _jumped:                            # (testing: not there until the car is set down)
		return
	if d < r and absf(car.speed) < 1.5:
		if cur.has("by") and fines:
			var hm: PackedStringArray = str(cur["by"]).split(":")
			on_time = fines.sim.minute <= float(hm[0]) * 60.0 + float(hm[1])
		map.pin = null
		_beam.visible = false
		if cur.get("comfort", false):
			stars = clampf(5.0 - _pen - float((fines.challans.size() if fines else 0) - _challans0), 1.0, 5.0)
			hud.warn(("Ride comfort  " if lang == "en" else "பயண சௌகரியம்  ") + "★".repeat(int(round(stars))) + "☆".repeat(5 - int(round(stars))), 5.0)
		_next()


## A passenger feels harsh changes of speed or direction: over 3.5 m/s² costs comfort while it lasts, a sudden
## jolt (a bump into something) costs a whole star.
func _comfort(dt: float) -> void:
	if dt <= 0.0:
		return
	var v: Vector3 = car.linear_velocity
	var dv := Vector3(v.x - _prev_v.x, 0.0, v.z - _prev_v.z)
	_prev_v = v
	var acc := dv.length() / dt
	if dv.length() > 3.0:
		_pen += 1.0
		hud.warn("Raghavan sir: \"Aiyo!\"" if lang == "en" else "ராகவன் சார்: \"ஐயோ!\"", 2.0)
	elif acc > 3.5:
		_pen += (acc - 3.5) * dt * 0.12


func _ride_talk(dt: float) -> void:
	if not cur.has("ride_talk"):
		return
	var rt: Dictionary = cur["ride_talk"]
	if _ride_i < 0:
		if t_step > float(rt["after"]) * (0.1 if _skip else 1.0):
			_ride_i = 0
			_ride_t = 0.0
			_refresh()
		return
	_ride_t += dt
	if _ride_t > 5.5 and _ride_i < rt["lines"].size():
		_ride_i += 1
		_ride_t = 0.0
		_refresh()


func _tick_clock(dt: float) -> void:
	if fines == null:
		return
	if cur.get("realtime", false):
		fines.sim.minute += dt / 60.0                    # one game minute a real minute: real travel times
	else:
		fines.sim.advance(dt, 0.0)


## Move the car to a place, waiting for the city there to load first. True once it's set down there.
func _place_at(p: Vector3) -> bool:
	if _jumped:
		return true
	var k := Vector2i(floori(p.x / city.streamer.tile), floori(p.z / city.streamer.tile))
	if not city.streamer.loaded.has(k):
		car.freeze = true
		car.global_position = Vector3(p.x, 600.0, p.z)
		return false
	if city._place_car(p):
		_jumped = true
	return _jumped


func _clock12() -> String:
	var m := int(fines.sim.minute if fines else 0) % 1440
	var h := m / 60
	var ap := "AM" if h < 12 else "PM"
	h = h % 12
	if h == 0:
		h = 12
	return "%d:%02d %s" % [h, m % 60, ap]


# ---- the screen ----
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20                               # over the map and the HUD, so scene cards cover them
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.03, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(backdrop)
	big = _label(46, Color(1.0, 0.92, 0.75))
	big.set_anchors_preset(Control.PRESET_CENTER)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.position = Vector2(-600, -90)
	big.size = Vector2(1200, 70)
	ui.add_child(big)
	small = _label(22, Color(0.85, 0.85, 0.85))
	small.set_anchors_preset(Control.PRESET_CENTER)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	small.position = Vector2(-500, -10)
	small.size = Vector2(1000, 80)
	ui.add_child(small)
	box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.86)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -430
	box.offset_right = 430
	box.offset_top = -200
	box.offset_bottom = -40
	ui.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	who = _label(20, Color.WHITE)
	vb.add_child(who)
	said = _label(22, Color(0.95, 0.95, 0.95))
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.custom_minimum_size = Vector2(800, 60)
	vb.add_child(said)
	hint = _label(14, Color(0.6, 0.6, 0.65))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	goal = _label(20, Color(1.0, 0.85, 0.4))
	goal.anchor_left = 0.5
	goal.anchor_right = 0.5
	goal.offset_left = -450
	goal.offset_right = 450
	goal.offset_top = 18
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(goal)
	for top in [true, false]:                             # cinematic bars for cutscenes
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.anchor_right = 1.0
		b.anchor_top = 0.0 if top else 0.89
		b.anchor_bottom = 0.11 if top else 1.0
		b.visible = false
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(b)
		ui.move_child(b, 1)
		bars.append(b)
	tasks = Tasks.new()
	tasks.visible = false
	tasks.finished.connect(_task_done)
	tasks.stage_changed.connect(_shot)
	ui.add_child(tasks)
	clock = _label(18, Color(0.9, 0.9, 0.9))
	clock.offset_left = 24
	clock.offset_top = 18
	ui.add_child(clock)
	_refresh()


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _say(line: Dictionary, prompt := true) -> void:
	var key := "%d:%d:%s" % [step, line_i, str(line.get("en", "")).left(12)]
	if line.has("pay") and not _paid.has(key) and fines:
		_paid[key] = true
		fines.sim.money += int(line["pay"])
		hud.warn(("+₹%d  " % int(line["pay"])) + ("tip from " if lang == "en" else "டிப்: ") + tr_(data["people"].get(line["who"], {})), 5.0)
	var p: Dictionary = data["people"].get(line["who"], {})
	who.text = tr_(p)
	who.add_theme_color_override("font_color", Color.html(str(p.get("colour", "#ffffff"))))
	said.text = tr_(line)
	hint.text = ("Enter ▸   ·   T: தமிழ்" if lang == "en" else "Enter ▸   ·   T: English") if prompt else ""
	box.visible = true


func _refresh() -> void:
	if ui == null:
		return
	var kind := str(cur.get("do", ""))
	backdrop.visible = step < 0 or kind in ["card", "jump"] or (kind == "talk" and cur.get("backdrop", false))
	big.visible = kind in ["card", "jump"]
	small.visible = kind in ["card", "jump"]
	box.visible = false
	goal.visible = kind in ["drive", "free", "meet"]
	clock.visible = kind in ["drive", "free", "talk", "comfort_verdict", "deliver_verdict", "task", "lapse", "meet"]
	if step < 0:
		big.visible = false                          # (no title shown: the story's name would give it away)
		small.visible = true
		small.text = "Loading Coimbatore…" if lang == "en" else "கோயம்புத்தூர் ஏறுது…"
		return
	match kind:
		"card":
			big.text = tr_(cur.get("big", ""))
			small.text = tr_(cur.get("small", ""))
		"jump":                                          # a cut: only the time and the place, no narration
			big.text = _clock12()
			small.text = tr_(data["places"][cur["to"]])
		"talk", "comfort_verdict", "deliver_verdict":
			_say(cur["lines"][line_i])
		"drive":
			var to: Dictionary = data["places"][cur["to"]]
			goal.text = tr_(cur["goal"]) + "\n" + tr_(to)
			if city.walker:
				goal.text += "\n" + ("F: back in the car" if lang == "en" else "F: காருக்குள்ள ஏறுங்க")
			if cur.has("ride_talk") and _ride_i >= 0 and _ride_i < cur["ride_talk"]["lines"].size():
				_say(cur["ride_talk"]["lines"][_ride_i], false)
		"free":
			goal.text = tr_(cur["goal"])


func _shot() -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/story_%02d.jpg" % [_shots, _shot_n], 0.85)
	print("STORYSHOT %02d step %d %s line %d" % [_shot_n, step, str(cur.get("do", "")), line_i])
	_shot_n += 1
