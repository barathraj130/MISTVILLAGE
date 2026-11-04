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
##   room      a scene in a room (tools/building_interiors.py: home, dev_office, bank...), loaded under the
##             street at the place ("at"): people stand on its marks ("mark": Mark_<name>), shots use its
##             planned cameras ("cam": "wide" → Cam_wide / Look_wide); "keep_room" keeps it (and the camera)
##             for the tasks and talk that follow, until a drive or a jump
##   lapse     time passing on screen: the camera holds on the street while the clock and the sky run to "to"
##   meet      someone standing at the place: get out (F), walk up and press E to talk
##   home      walk the house yourself (the room, "room"/"at"): "visits" in order, each a place in it ("to": its
##             mark) where E does that place's task (the bathroom: brush and bathe; the kitchen: a meal from the
##             month's groceries...); a marker shows where to go next
##   eat_out   find somewhere to eat: "eateries" (places) on the map; on foot at any door, E: inside (room_mess, or
##             "rooms": place → room, e.g. the five-star's restaurant), Karthik at a table, its menu, paid from
##             the wallet
##   gigs      a delivery shift on the rider app: orders one after another (a restaurant of "pickups", a neighbourhood
##             of "drops", pay by distance, a tip when on time); E takes the order, Q ends the shift (or "until")
##   choose    a choice: "prompt" and "options" (1, 2, 3 on the keyboard), each one may "set" a flag (later steps
##             follow it with "when" / "unless"), "pay" from the wallet and change Karthik's "stress"; one with
##             "max_stress" is out of reach for a Karthik more stressed than that (shown with its "shaken" line)
##   climb     on foot through a room ("room"/"at", from Mark_"start") up to Mark_landing, where the talk that
##             follows takes place; walking past Mark_cut the power fails (as it does in Coimbatore): the lights die
##             and the phone's torch comes on
##   free      free drive with a goal line, the end of the chapter
## Any step may have "when": flag / "unless": flag (results of earlier tasks) and is skipped otherwise; any line
## may "pay" an amount into the wallet when it's shown (a tip from the owner, a customer).
## T switches English / Tamil at any time. The clock runs (GAME_RULES.md §1) while you drive, pauses on cards
## and in talk.
##   --storyskip     testing: each drive step jumps the car to its place after 3 s, and talk advances by itself
##   --storyshots=D  testing: a screenshot of every card, talk line and arrival into the folder D
##   --storyflags=a,b / --storymoney=N  testing: with --storyfrom, what had happened before, and his wallet
##   --eatat=P       testing: the lunch break is eaten at the place P (an eat_out "eateries" key)
##   --storyta       start in Tamil
##   --storychoose=N testing: at every choice, option N (1, 2...)
##   --storyfrom=N   testing: start the chapter at step N
##   --storyclock=HH:MM testing: the clock it starts at

const Sim := preload("res://scripts/drive/sim.gd")
const Tasks := preload("res://scripts/story/tasks.gd")
const Table := preload("res://scripts/story/table.gd")
const Wall := preload("res://scripts/story/wall.gd")
const Dvr := preload("res://scripts/story/dvr.gd")
const Doorbell := preload("res://scripts/story/doorbell.gd")
const Actor := preload("res://scripts/story/actor.gd")
const Walker := preload("res://scripts/player.gd")
const RoomSound := preload("res://scripts/city/room_sound.gd")
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
var _gig := {}                       # the delivery shift ("gigs"): the order on offer or under way
var _gig_done := 0                   # orders delivered this shift
var _gig_earned := 0                 # and what they paid
var _q_down := false
var _peek := -1                     # (testing) the house visit the walker was set down near
var _beam: MeshInstance3D
var flags := {}                     # what the player did in tasks (short_found, signed, ...)
var _paid := {}                     # lines that already paid (step:line)
var tasks: Control
var table: Control                    # the questioning (table.gd)
var wall: Control                     # the wall in his room (wall.gd)
var dvr: Control                      # a camera recorder's footage on someone's monitor (dvr.gd)
var doorbell: Control                 # Ashwin's doorbell camera: it records him that night, plays on a tablet later (doorbell.gd)
var _park := ""                       # a place the car is being set down at, out of sight (after a ride)
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
var _visit := 0                       # home: which visit of the house is next
var _in_task := false                 # home / eat_out: a task is open
var _ring: MeshInstance3D             # home: the marker on the floor where to go
var _climb := 0                       # climb: 0 walking up, 1 the power's gone, 3 at the top
var _f_down := false                  # (F held: Amma's money, once per press)
var _paid_test := false
var _props: Array[Node3D] = []         # things a meet sets out (a tea stall), until the next drive
var _snap_ready := false               # (a snapshot step: its picture is in his hands)
var _climbing := false                # (on foot in a climb's room, until the story leaves it)
var _torch: SpotLight3D
var _sfx: AudioStreamPlayer
var _num_down := {}
var _f2f: Node3D                      # face to face: the person Karthik is talking to, filling the view
var _goal_first := ""                 # the goal now on his phone (its first line)
var prompt: Label                     # the key for the thing in front of him
var _KEY_LINE := RegEx.create_from_string("^(E|F|Q|P|I|Enter|Shift|Space)\\b|^[A-Z]: ")
var _knock_t := 0.0
var _note := ""                       # home: a line under the goal for a few seconds (the car's HUD is off indoors)
var _note_t := 0.0
var room: Node3D                    # the room a scene is playing in, under the street
var face_light: SpotLight3D         # a soft key light on whoever is speaking (close-ups)
const ROOMS := "res://assets/interiors/room_%s.glb"

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


## Another chapter now, from its first step (bail cancelled: the jail, story/jail.json); its last step is free play.
var _chapters := 0


func play_chapter(path: String) -> bool:
	if not load_chapter(path):
		return false
	_chapters += 1
	_clear_cast()
	step = -1
	cur = {}
	return true


func playing() -> bool:
	return step >= 0 and step < data["steps"].size() and str(cur.get("do", "")) != "free"


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
	if _park != "" and str(cur.get("do", "")) != "ride" and _place_at(place_pos(_park)):
		_park = ""
	match str(cur["do"]):
		"card":
			if t_step > (2.0 if _skip else 5.0):
				_next()
		"talk":
			if _skip and t_step > 1.2:
				_advance_line()
		"drive":
			_drive(dt)
		"home":
			_home()
		"eat_out":
			_eat_out()
		"comfort_verdict", "deliver_verdict":
			if _skip and t_step > 1.2:
				_advance_line()
		"jump":
			if _place_at(place_pos(cur["to"])) and t_step > (1.5 if _skip else 3.0):
				car.visible = true
				_next()
		"scene", "room":
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
		"choose":
			_choose()
		"climb":
			_climb_step(dt)
		"gigs":
			_gigs(dt)
		"task":
			if _skip and t_step > 1.5 and str(cur["task"]) == "phone" and str(cur.get("mode", "offer")) == "offer" and not city.phone.rider.is_empty():
				city.phone._rider_take(true)
			elif _skip and t_step > 1.5 and str(cur["task"]) == "otp" and str(city.phone.rider.get("mode", "")) == "otp":
				for ch in str(cur.get("code", "")):
					city.phone._rider_key(ch)
		"snapshot":                                      # (then like a give: his to look at, then the pocket)
			if _snap_ready and _skip and t_step > 1.5:
				city.hands.put_back()
			if _snap_ready and t_step > 0.3 and city.hands.held.is_empty():
				_next()
		"give":                                          # read it, then put it in his pocket (E)
			if _skip and t_step > 1.5:
				city.hands.put_back()
			if t_step > 0.3 and city.hands.held.is_empty():
				_next()
		"ride":
			_ride(dt)
		"wait":
			_wait_step()
		"gate":
			_gate()
		"dvr":
			_dvr_step()
		"dial":                                          # he calls someone from his contacts
			if _skip and t_step > 1.5 and t_step < 9.0:
				t_step = 9.0
				_on_dial({"id": str(cur["who"])})
		"deal":
			_deal()
		"call":                                          # the phone rings until he answers
			if _skip and t_step > 1.5:
				city.phone.answer()
			if city.phone.ringing.is_empty():
				_next()
		"free":
			_tick_clock(dt)
			if _skip and t_step > 4.0 and (_chapters > 0 or not "--jailtest" in OS.get_cmdline_user_args()):
				print("STORY done: flags %s" % str(flags))
				print("STORY done: comfort %.1f stars, on time %s, wallet %d, clock %s day %d" % [stars, on_time,
					fines.sim.money if fines else 0, _clock12(), fines.sim.day if fines else 1])
				get_tree().quit()
	clock.text = "%s %d   %s" % ["Day" if lang == "en" else "நாள்", fines.sim.day if fines else 1, _clock12()]
	_route_goal()


## What the story wants of him goes on his phone (a buzz, the Notes app), not on the screen; only the key for the
## thing in front of him ("E: talk") shows, small, under the middle of the view (GAME_DESIGN.md §8).
func _route_goal() -> void:
	var lines: PackedStringArray = goal.text.split("\n") if goal.visible else PackedStringArray()
	var keys: Array = []
	var rest: Array = []
	for l in lines:
		if l.strip_edges() == "":
			continue
		if _KEY_LINE.search(l):
			keys.append(l)
		else:
			rest.append(l)
	goal.modulate.a = 0.0
	prompt.text = "   ·   ".join(keys)
	prompt.visible = not keys.is_empty() and not city.hands.is_busy() and not city.phone.is_open
	if rest.is_empty() or city.phone == null:
		return
	if rest[0] != _goal_first:
		_goal_first = rest[0]
		city.phone.note("\n".join(rest))
	elif not city.phone.notes.is_empty():
		city.phone.notes[0]["text"] = "\n".join(rest)


func _keys() -> void:
	var enter := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	if enter and not _enter_down:
		match str(cur.get("do", "")):
			"card":
				_next()
			"talk", "comfort_verdict", "deliver_verdict":
				_advance_line()
			"scene", "room":
				if shot_t > 0.3:
					_next_shot()
	_enter_down = enter
	var tk := Input.is_key_pressed(KEY_T)
	if tk and not _t_down:
		lang = "en" if lang == "ta" else "ta"
		_sync_lang()
		_refresh()
	_t_down = tk


func _bike() -> bool:
	return "scooter" in str(car.vehicle) or "bike" in str(car.vehicle)


func _off_key() -> String:
	if _bike():
		return "F: get off" if lang == "en" else "F: இறங்குங்க"
	return "F: get out" if lang == "en" else "F: இறங்குங்க"


func _on_key() -> String:
	if _bike():
		return "F: back on the scooter" if lang == "en" else "F: ஸ்கூட்டர்ல ஏறுங்க"
	return "F: back in the car" if lang == "en" else "F: காருக்குள்ள ஏறுங்க"


func _sync_lang() -> void:
	if city and city.phone:
		city.phone.lang = lang
		city.hands.lang = lang


func _next() -> void:
	_sync_lang()
	if step < 0 and _chapters == 0:
		for a in OS.get_cmdline_user_args():          # (testing: --storyclock=HH:MM, the time it starts at)
			if a.begins_with("--storyclock=") and fines:
				var hm0: PackedStringArray = a.get_slice("=", 1).split(":")
				fines.sim.minute = float(hm0[0]) * 60.0 + float(hm0[1])
		for a in OS.get_cmdline_user_args():          # (testing: --storyflags=a,b as if those had happened;
			if a.begins_with("--storyflags="):        #  --storymoney=N in his wallet)
				for f in a.get_slice("=", 1).split(","):
					flags[f] = true
					if f == "frozen" and city.money:     # (the account, as the arrest leaves it)
						city.money.freeze(23400)
			elif a.begins_with("--storymoney=") and fines:
				fines.sim.money = int(a.get_slice("=", 1))
		for a in OS.get_cmdline_user_args():          # (testing: --storyfrom=N starts the chapter at step N)
			if a.begins_with("--storyfrom="):
				step = int(a.get_slice("=", 1)) - 1
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
		var to := float(hm[0]) * 60.0 + float(hm[1])
		if not cur.get("clock_forward", false) or _since_noon(to) > _since_noon(fines.sim.minute):
			fines.sim.minute = to                        # ("clock_forward": only ever later, e.g. after a long shift)
	if cur.has("add_days") and fines:                   # days that pass off screen (bail, a week in jail)
		fines.sim.day += int(cur["add_days"])
	var life = city.life if "life" in city else null
	if life and cur.has("life"):                        # where those days leave him (rested, fed, worn down)
		for k in cur["life"]:
			life.set(k, float(cur["life"][k]))
	if life and cur.has("life_add"):                    # what this moment does to him (the arrest: stress)
		for k in cur["life_add"]:
			life.set(k, clampf(float(life.get(k)) + float(cur["life_add"][k]), 0.0, 100.0))
	if life and (cur.has("clock") or cur.has("add_days")):   # a jump of the clock isn't hours awake
		life._clock = life._clock_now()
	if cur.has("set_flag"):                             # (a step that, when it plays, tells the later ones so)
		flags[str(cur["set_flag"])] = true
	if cur.has("add_minutes") and fines:                # time that passes off screen (a ride on the scooter)
		fines.sim.minute += float(cur["add_minutes"])
	_jumped = false
	if _f2f and not str(cur["do"]) in ["talk", "choose", "give", "table"]:          # the talk is over: his own eyes again
		_f2f_off()
	if _climbing and not str(cur["do"]) in ["talk", "choose"]:     # out of the dark building, back to the street
		_end_climb()
	if room != null and not str(cur["do"]) in ["room", "task", "talk", "comfort_verdict", "deliver_verdict", "card", "home", "choose",
			"give", "take", "note", "message", "contact", "pin", "call", "table", "dvr", "deal", "money", "bail", "snapshot", "evidence", "record"]:
		_unload_room()
		_cams_back()
	for k in cur.get("hide", []):                       # (someone gone in: sir into his car, through his gate)
		if cast.has(k):
			cast[k].visible = false
	if cur.has("vehicle"):                              # (the night delivery is on his scooter; taken: Bala's bike)
		var want := "bike" if str(cur["vehicle"]) == "karthik_scooter" and city.money and city.money.seized else str(cur["vehicle"])
		if car.vehicle != want:
			car.configure(want)
	if str(cur["do"]) in ["drive", "jump", "home", "ride"] and not _props.is_empty():
		for pr in _props:
			if is_instance_valid(pr):
				pr.queue_free()
		_props.clear()
	if cur.get("doorbell", false):                     # (at Ashwin's door: his doorbell camera is recording)
		_doorbell_capture()
	match str(cur["do"]):
		"message":                                       # a text arrives (from, en/ta)
			city.phone.message(cur["from"], cur["text"], str(cur.get("time", "")))
			_next()
			return
		"contact":                                       # a number he's given
			city.phone.add_contact(cur["contact"])
			_next()
			return
		"pin":                                           # a place pinned on his phone's map
			city.phone.pin(str(cur["place"]), cur.get("label", data["places"].get(cur["place"], {})))
			_next()
			return
		"money":                                         # the account frozen ("freeze": bank, "wallet"), bills due ("bills")
			if city.money:
				if cur.has("freeze"):
					city.money.freeze(int(cur["freeze"]), int(cur.get("wallet", -1)))
				for b in cur.get("bills", []):
					city.money.add_bill(b)
			_next()
			return
		"bail":                                          # bail begins: the evenings at the station (city/bail.gd)
			if city.bail and cur.get("restore", false):  # (out of jail: bail granted again)
				city.bail.restore()
			elif city.bail:
				city.bail.start()
			_next()
			return
		"note":                                          # something to do, on his phone
			city.phone.note(cur["text"])
			_goal_first = ""
			_next()
			return
		"take":                                          # out of his pocket (handed over, taken from him)
			city.hands.take(str(cur["id"]))
			_next()
			return
		"give":                                          # into his hands, to read
			city.hands.give(cur["item"])
			if city.walker:
				city.walker.active = false
		"call":
			city.phone.call_from(cur["from"])
		"ride":
			_ride_start()
		"gate":
			_has_tea = false
			_in_task = false
			_cast(cur.get("cast", {}))
			if cast.has("seller") and not cast["seller"].has_node("Lamp"):   # the stall's bulb, warm in the dark
				var lamp := OmniLight3D.new()
				lamp.name = "Lamp"
				lamp.position = Vector3(0, 2.4, 0.4)
				lamp.light_color = Color(1.0, 0.72, 0.38)
				lamp.light_energy = 2.2
				lamp.omni_range = 7.0
				cast["seller"].add_child(lamp)
			if _ring:
				_ring.visible = false
		"dvr":
			_photo_hook()
			_dvr_open()
		"doorbell":
			_photo_hook()
			_doorbell_open()
		"snapshot":
			_snap_ready = false
			_snapshot()
		"dial":
			if not city.phone.dialled.is_connected(_on_dial):
				city.phone.dialled.connect(_on_dial)
		"deal":
			_photo_hook()
			_deal_start()
		"record":                                        # (testing only: the recorder a player would start himself)
			if _skip:
				city.phone.recording = not bool(cur.get("on", true))
				city.phone._toggle_rec()
			_next()
			return
		"evidence":                                      # what was recorded becomes evidence, if it was
			_evidence()
			_next()
			return
		"table":                                         # across the table from him: answer by what you do
			if city.walker:
				_face_to_face()
			box.anchor_top = 0.0                           # (his words above on the left, clear of his face;
			box.anchor_bottom = 0.0                        #  the table below)
			box.anchor_left = 0.0
			box.anchor_right = 0.0
			box.offset_top = 24.0
			box.offset_bottom = 150.0
			box.offset_left = 24.0
			box.offset_right = 520.0
			var pick := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--storychoose="):
					pick = int(a.get_slice("=", 1))
			table.lang = lang
			table.life = city.life
			table.start(cur, lang, _skip, pick)
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
			var tk := str(cur["task"])
			if tk == "phone" and str(cur.get("mode", "offer")) == "offer":   # the order, on his phone's rider app
				if not city.phone.rider_answer.is_connected(_offer_answer):
					city.phone.rider_answer.connect(_offer_answer)
				city.phone.rider_offer(cur.get("app", {}), cur.get("order", []))
			elif tk == "otp":                              # the customer's code, on the app's keypad
				if not city.phone.otp_done.is_connected(_otp_typed):
					city.phone.otp_done.connect(_otp_typed)
				city.phone.rider_otp(cur.get("app", {}), cur.get("order", []), str(cur.get("code", "")))
			else:
				tasks.start(tk, cur, lang, _skip)
			_speak_tip.call_deferred(cur)
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
		"room":
			_load_room(str(cur["room"]), str(cur.get("at", data["spawn"])))
			_cast(cur.get("cast", {}))
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
			for pr in cur.get("props", []):              # (a tea stall at the roadside: city_props, in the car's frame)
				var ps := load(str(pr["scene"])) as PackedScene
				if ps == null:
					continue
				var pn := ps.instantiate() as Node3D
				add_child(pn)
				var at := _w2(pr["pos"])
				var gy: float = city.streamer.height_at(at.x, at.z)
				at.y = gy if not is_nan(gy) else at.y
				var lk := _w2(pr.get("look", [0.0, 0.0]))
				pn.global_position = at
				pn.rotation.y = atan2(lk.x - at.x, lk.z - at.z) + float(pr.get("turn", 0.0))
				_props.append(pn)
			var a: Node3D = cast.get(cur["who"])
			if a:
				map.pin = Vector2(a.global_position.x, a.global_position.z)
		"home":
			_load_room(str(cur["room"]), str(cur.get("at", data["spawn"])))
			_cast(cur.get("cast", {}))
			if str(cur["room"]) == "home" and cur.get("cast", {}).has("amma") and city.money:
				city.money.handover.call_deferred()     # (what the app paid into her account, into his hand)
			_visit = 0
			_in_task = false
			_knock_t = 0.0
			if str(cur.get("start", "")) == "here" and city.walker:   # (on from where he stands: a talk in between)
				city.walker.activate()
				_ring.visible = true
			elif str(cur.get("start", "")) == "here":     # (nobody on foot yet: a test started here) in at the door
				_walk_in("door" if _mark("door") else str(cur["visits"][0]["to"]))
			else:
				_walk_in(str(cur.get("start", "karthik_room")))
		"talk":
			if cur.has("cast"):                         # (someone comes in: Sundaram at the door)
				_cast(cur["cast"])
			if city.walker and not cur.get("backdrop", false):
				_face_to_face()
		"climb":
			_load_room(str(cur["room"]), str(cur.get("at", data["spawn"])))
			_cast(cur.get("cast", {}))
			for k in cur.get("cast", {}):
				if cur["cast"][k].get("hidden", false):
					cast[k].visible = false                  # (there, in the dark, unseen)
			_climb = 0
			_climbing = true
			_walk_in(str(cur.get("start", "start")))
		"gigs":
			_gig = {}
			_gig_done = 0
			_gig_earned = 0
			_gig_offer()
		"eat_out":
			_in_task = false
			var best := Vector3.INF
			for k in cur["eateries"]:
				var q := place_pos(str(k))
				if best == Vector3.INF or q.distance_to(car.global_position) < best.distance_to(car.global_position):
					best = q
			map.pin = Vector2(best.x, best.z)
			_beam.visible = true
			_beam.global_position = Vector3(best.x, car.global_position.y + 30.0, best.z)
		"deliver_verdict":
			var k := "ontime" if on_time else "late"
			var pay := int(cur["pay"][k])
			if fines:
				fines.sim.money += pay
			city.phone.message(cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"}),
				{"en": "Order delivered%s. ₹%d credited to your wallet." % ["" if on_time else " (late)", pay],
				"ta": "ஆர்டர் டெலிவரி ஆச்சு%s. ₹%d வாலட்ல வந்துச்சு." % ["" if on_time else " (தாமதம்)", pay]})
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
			var hair_hex: String = str(data["people"].get(key, {}).get("hair", ""))
			a.setup(str(d.get("model", data["people"].get(key, {}).get("model", "person_man_shirt"))), key,
				Callable(city.streamer, "height_at"), Color.html(hair_hex) if hair_hex != "" else Color(0, 0, 0, 0))
			for part in ["top", "pants"]:                # (a uniform on a crowd model: the warder's khaki)
				var hex: String = str(data["people"].get(key, {}).get(part, ""))
				if hex != "":
					a.tint_cloth(part, Color.html(hex))
			cast[key] = a
		var act: Node3D = cast[key]
		act.visible = true
		if d.has("mark") and room != null:
			_to_mark(act, str(d["mark"]))
		elif d.has("pos"):
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
	if face_light:
		face_light.visible = false
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
		if cur.get("keep_room", false) and room != null:
			for b in bars:                               # stay in the room: the tasks and talk play on here
				b.visible = false
			box.visible = false
		else:
			_unload_room()
			_cams_back()
		if not cur.get("keep_cast", false) and not cur.get("keep_room", false):
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
		if act.has("walk_mark") and room != null:
			var m := _mark(str(act["walk_mark"]))
			if m:
				a.walk_to(m.global_position, float(act.get("speed", 1.2)), str(act.get("then", "Idle")))
		if act.has("mark") and room != null:
			_to_mark(a, str(act["mark"]))
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
	if sh.has("line") and not sh.get("fixed_cam", false) and _auto_frame(str(sh["line"]["who"]), str(sh["line"].get("to", ""))):
		pass                                             # dialogue: framed on whoever is speaking (rooms too)
	elif sh.get("cam") is String and room != null:
		_room_cam(str(sh["cam"]))                        # a planned shot of the room (wide, the photos...)
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


# ---- rooms ----
func _load_room(name: String, at_key: String) -> void:
	if room != null and room.get_meta("room", "") == name:
		return
	_unload_room()
	var path := ROOMS % name
	if not ResourceLoader.exists(path):
		push_warning("story: no room " + path)
		return
	room = (load(path) as PackedScene).instantiate() as Node3D
	room.set_meta("room", name)
	add_child(room)
	var p: Vector3 = place_pos(at_key) if data["places"].has(at_key) else car.global_position
	var g: float = city.streamer.height_at(p.x, p.z)
	room.global_position = Vector3(p.x, (g if not is_nan(g) else car.global_position.y) - 200.0, p.z)
	var body := StaticBody3D.new()                       # walls and furniture are solid (cameras keep out of them)
	room.add_child(body)
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		cs.transform = room.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		body.add_child(cs)
	var lights := room.find_children("Light_*", "", true, false)
	for e in lights:                                     # the room's own lights (tools/story_rooms.py Light_ empties)
		var l := OmniLight3D.new()
		var kind := str(e.name).split("_")[1]
		l.omni_range = {"tube": 6.5, "window": 5.0, "lamp": 2.2}.get(kind, 6.0)
		l.light_energy = {"tube": 1.3, "window": 1.4, "lamp": 0.9}.get(kind, 1.2)
		l.light_color = {"tube": Color(0.96, 0.98, 1.0), "window": Color(1.0, 0.94, 0.82),
				"lamp": Color(1.0, 0.62, 0.28)}.get(kind, Color(1, 1, 1))
		if kind == "tube" and (str(e.name).ends_with("_0") or str(e.name).ends_with("_1")):
			l.shadow_enabled = true                      # soft shadows under the furniture and people
			l.light_size = 0.25
			l.shadow_blur = 1.5
		(e as Node3D).add_child(l)
	var box := AABB()                                    # a reflection probe the size of the room (polished floors, glass, steel)
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	var probe := ReflectionProbe.new()
	probe.size = box.size
	probe.position = box.get_center()
	probe.box_projection = true
	probe.interior = true
	probe.enable_shadows = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	room.add_child(probe)                                # (Godot leaves its reflection atlas behind at quit:
	                                                     #  "7 RIDs of type Texture were leaked", harmless)
	if lights.is_empty():
		for lp in [Vector3(-2.2, 2.85, 0.6), Vector3(2.2, 2.85, -0.6), Vector3(0.0, 2.85, -2.6)]:   # the tube lights' glow
			var l := OmniLight3D.new()
			l.omni_range = 9.0
			l.light_energy = 1.6
			l.light_color = Color(1.0, 0.97, 0.92)
			l.position = lp
			room.add_child(l)
	city.indoors = true


func _unload_room() -> void:
	if room == null:
		return
	room.queue_free()
	room = null
	city.indoors = false


func _mark(name: String) -> Node3D:
	return room.find_child("Mark_" + name, true, false) as Node3D if room else null


## Stand a person on a room mark, facing the way the mark faces (the empties' Blender +Y, Godot -Z).
func _to_mark(a: Node3D, name: String) -> void:
	var m := _mark(name)
	if m == null:
		push_warning("story: no mark " + name)
		return
	a.floor_y = m.global_position.y
	a.place(m.global_position, m.global_position - m.global_basis.z)


func _room_cam(name: String) -> void:
	var c := room.find_child("Cam_" + name, true, false) as Node3D
	var l := room.find_child("Look_" + name, true, false) as Node3D
	if c == null or l == null:
		push_warning("story: no room shot " + name)
		return
	scene_cam.global_position = c.global_position
	scene_cam.look_at(l.global_position, Vector3.UP)


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
func _auto_frame(who: String, to := "") -> bool:
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
	if to != "" and cast.has(to) and (cast[to] as Node3D).visible:   # a line said to someone in particular
		li = cast[to]
	var head := sp.global_position + Vector3.UP * (1.05 if sp.get("seated") else 1.45)     # (seated: lower)
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
	var pick := -1
	for i in cands.size():
		if _clear(cands[i], head):
			at = cands[i]
			pick = i
			break
	if pick < 0:                                         # nothing clear (a small room): pull the best shot in, in front of the wall
		for i in cands.size():
			var c := _pull_in(head, cands[i])
			if c != Vector3.INF:
				at = c
				pick = 10 + i
				break
	if _skip:
		var fw: Vector3 = sp.global_basis.z                 # the model's front (+Z)
		print("FRAME %s: speaker %s at %s facing %s, listener %s, camera #%d of %d at %s, faces camera: %.2f" % [who,
			sp.who, str(sp.global_position.snapped(Vector3.ONE * 0.1)), str(fw.snapped(Vector3.ONE * 0.01)),
			li.who if li else "-", pick, cands.size(), str(at.snapped(Vector3.ONE * 0.1)),
			fw.dot((at - sp.global_position).normalized())])
	scene_cam.global_position = at
	scene_cam.look_at(head - Vector3.UP * 0.12, Vector3.UP)
	scene_cam.fov = clampf(rad_to_deg(2.0 * atan(0.42 / maxf(at.distance_to(head), 0.5))), 12.0, 50.0)   # head and shoulders fill it
	_key_light(sp, at)
	return true


## A soft key light from beside the camera onto the speaker's face (the way films light close-ups).
func _key_light(sp: Node3D, cam_at: Vector3) -> void:
	if face_light == null:
		face_light = SpotLight3D.new()
		face_light.spot_range = 6.0
		face_light.spot_angle = 22.0
		face_light.light_energy = 2.2
		face_light.light_color = Color(1.0, 0.94, 0.86)
		face_light.shadow_enabled = false
		add_child(face_light)
	var head := sp.global_position + Vector3.UP * 1.5
	var side := (head - cam_at).cross(Vector3.UP).normalized()
	face_light.global_position = cam_at + side * 0.8 + Vector3.UP * 0.4
	face_light.look_at(head, Vector3.UP)
	face_light.visible = true


## The camera spot on the line from the head out to `cand`, just in front of whatever stands in the way; INF if
## that leaves it closer than a metre (no room for a shot that way).
func _pull_in(head: Vector3, cand: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(head, cand)
	var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return cand
	var d := (cand - head).normalized()
	var at: Vector3 = (hit["position"] as Vector3) - d * 0.3
	return at if at.distance_to(head) >= 1.0 else Vector3.INF


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
	if _skip and t_step > 1.0:                           # (testing: out of the car and up to them, as a player would)
		if city.walker == null and city.has_method("toggle_on_foot"):
			car.speed = 0.0
			city.toggle_on_foot()
		if city.walker:
			city.walker.global_position = a.global_position + Vector3(a.global_basis.z.x, 0.0, a.global_basis.z.z).normalized() * 1.4 + Vector3.UP * 0.1
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
		hint = _off_key()
	elif near:
		hint = "E: talk" if lang == "en" else "E: பேசுங்க"
	goal.text = tr_(cur["goal"]) + ("\n" + hint if hint != "" else "")


## Talking on foot: the view becomes Karthik's own eyes on the person he's talking to, close, their face and
## shoulders filling it in a soft key light, as one sees a face across a counter or a gate.
func _face_to_face() -> void:
	var w: Node3D = city.walker
	var who: Node3D = null
	for ln in cur.get("lines", []):
		var k := str(ln.get("who", ""))
		if k != "karthik" and cast.has(k) and (cast[k] as Node3D).visible:
			who = cast[k]
			break
	if who == null:
		return
	who.face(w.global_position)
	var head: Vector3 = who.global_position + Vector3.UP * (1.05 if who.get("seated") else 1.5)
	var d := Vector3(w.global_position.x - who.global_position.x, 0.0, w.global_position.z - who.global_position.z)
	d = d.normalized() if d.length() > 0.05 else -who.global_basis.z
	var at := _pull_in(head, head + d * 1.05 + Vector3.UP * 0.05)
	if at == Vector3.INF:
		at = head + d * 0.8
	if scene_cam == null:
		scene_cam = Camera3D.new()
		scene_cam.far = 4000.0
		add_child(scene_cam)
	scene_cam.fov = 38.0
	scene_cam.global_position = at
	scene_cam.look_at(head - Vector3.UP * 0.06, Vector3.UP)
	scene_cam.make_current()
	_key_light(who, at)
	if w.model:
		w.model.visible = false                         # (it's his eyes: he isn't in the picture)
	w.active = false
	hud.visible = false                                 # (only the face and the words, no map or meters)
	map.visible = false
	_f2f = who


func _f2f_off() -> void:
	_f2f = null
	if face_light:
		face_light.visible = false
	if scene_cam:
		scene_cam.fov = 50.0
	hud.visible = true
	map.visible = true
	var w: Node3D = city.walker
	if w:
		if w.model:
			w.model.visible = w.third_person
		w.active = true
		w.camera.make_current()


## A choice: 1, 2, 3 on the keyboard. The option's flag is set for the steps after; its cost paid, its stress felt.
func _choose() -> void:
	var opts: Array = cur["options"]
	var pick := -1
	for i in opts.size():
		var down := Input.is_key_pressed(KEY_1 + i) or Input.is_key_pressed(KEY_KP_1 + i)
		if down and not _num_down.get(i, false):
			pick = i
		_num_down[i] = down
	if _skip and t_step > 1.0:
		pick = 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--storychoose="):
				pick = clampi(int(a.get_slice("=", 1)) - 1, 0, opts.size() - 1)
		while pick < opts.size() - 1 and _shaken(opts[pick]):
			pick += 1
	if pick < 0 or _shaken(opts[pick]):
		return
	var o: Dictionary = opts[pick]
	if o.has("set"):
		flags[str(o["set"])] = true
	if int(o.get("pay", 0)) > 0 and fines:
		fines.sim.money -= int(o["pay"])
	var life = city.life if "life" in city else null
	if life and o.has("stress"):
		life.add_stress(float(o["stress"]))
	print("STORY chose %d: %s" % [pick + 1, tr_(o["text"])])
	_next()


## An option a stressed Karthik can't manage ("max_stress": above it, it's shown greyed with its "shaken" line).
func _shaken(o: Dictionary) -> bool:
	var life = city.life if "life" in city else null
	return life != null and o.has("max_stress") and life.stress > float(o["max_stress"])


## On foot up the building's stair: the power fails at Mark_cut; at Mark_landing the talk begins.
func _climb_step(dt: float) -> void:
	var w: Node3D = city.walker
	if w == null:
		return
	var cut := _mark("cut")
	var top := _mark("landing")
	if _skip and _climb == 0 and t_step > 1.0 and cut:           # (testing: up the stair in two hops)
		w.global_position = cut.global_position + Vector3(0, 0.5, 0)
	if _skip and _climb == 1 and t_step > 2.5 and top:
		w.global_position = top.global_position + Vector3(0, 0.3, 0.4)
	var flat := func(m: Node3D) -> float:
		return Vector2(w.global_position.x - m.global_position.x, w.global_position.z - m.global_position.z).length()
	if _climb == 0 and cut and flat.call(cut) < 1.2:
		_climb = 1
		_power_cut()
	elif _climb == 1 and top and flat.call(top) < 1.4 and w.global_position.y > top.global_position.y - 0.6:
		_climb = 3
		for k in cast:                                            # whoever waits at the top turns to him
			if (cast[k] as Node3D).visible:
				cast[k].face(w.global_position)
		_next()
		return
	var g: Dictionary = cur["goal"] if _climb == 0 else cur.get("goal_dark", cur["goal"])
	goal.text = tr_(g)


func _power_cut() -> void:
	for l in room.find_children("*", "OmniLight3D", true, false):
		(l as Light3D).visible = false
	var dark := StandardMaterial3D.new()                         # the tubes go dark too
	dark.albedo_color = Color(0.85, 0.85, 0.85)
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat and (mat.resource_name.begins_with("tube_glow") or mat.resource_name.begins_with("panel_light")):
				m.set_surface_override_material(s, dark)
	city.dark_room = true
	if _torch == null:
		_torch = SpotLight3D.new()
		_torch.spot_range = 14.0
		_torch.spot_angle = 24.0
		_torch.light_energy = 3.5
		_torch.light_color = Color(1.0, 0.97, 0.9)
		_torch.shadow_enabled = true
	if _torch.get_parent():
		_torch.get_parent().remove_child(_torch)
	city.walker.camera.add_child(_torch)
	_torch.position = Vector3(0.15, -0.15, 0.0)
	_play_sfx("powercut", 0.0)
	print("STORY power cut")


func _play_sfx(kind: String, db: float) -> void:
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		add_child(_sfx)
	var p := AudioStreamPlayer.new()                             # (one each: the shout and the stick overlap)
	p.stream = RoomSound.sound(kind)
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _end_climb() -> void:
	_climbing = false
	city.dark_room = false
	if _torch:
		_torch.queue_free()
		_torch = null
	_walk_out()


func _task_done(result: Dictionary) -> void:
	for k in result:
		flags[k] = result[k]
	if result.has("minutes") and fines:                 # chores take game time
		fines.sim.minute += float(result["minutes"])
	if int(result.get("paid", 0)) > 0 and fines:         # a meal out, from the wallet
		fines.sim.money -= int(result["paid"])
	print("STORY task %s → %s" % [cur.get("task", cur.get("do", "")), str(result)])
	if result.get("signed", false) and room != null and str(room.get_meta("room", "")) == "police" and city.bail:
		city.bail.sign_now()                             # (the story's signing is the register's too)
	_in_task = false
	box.visible = false
	_box_at_top(false)
	if str(cur.get("do", "")) == "home":
		var v: Dictionary = cur["visits"][_visit]
		if v.get("home_meal", false) and result.get("ate", false) and fines:   # a meal at home: the groceries
			fines.sim.groceries = maxi(fines.sim.groceries - 1, 0)
			_note = ("Groceries: %d meals left this month" if lang == "en" else "மளிகை: இந்த மாசம் இன்னும் %d வேளை") % fines.sim.groceries
			_note_t = 5.0
		_visit += 1
		if _visit >= cur["visits"].size():
			if cur.has("late_after") and fines:          # out of the house after this: late (for later steps)
				var hm: PackedStringArray = str(cur["late_after"]).split(":")
				flags["late_morning"] = fines.sim.minute > float(hm[0]) * 60.0 + float(hm[1])
			if not cur.get("keep", false):               # ("keep": he stays on his feet in the room for what follows)
				_walk_out()
			elif _ring:
				_ring.visible = false
			_next()
		return
	if str(cur.get("do", "")) == "eat_out" and room != null:     # eating out: a moment of him eating, then on
		_in_task = true
		if result.get("ate", false) and cast.has("karthik"):
			_dish(str(result.get("meal", "meals")))
			cast["karthik"].play("SitEat")
		get_tree().create_timer(0.5 if _skip else 1.5).timeout.connect(_shot)
		get_tree().create_timer(1.2 if _skip else 3.5).timeout.connect(func():
			for k in ["karthik", "cook"]:
				if cast.has(k):
					cast[k].visible = false
			_in_task = false
			_next())
		return
	_next()


## You on foot in the house: Karthik himself (the story cast's model), standing at a mark of the room.
func _walk_in(at_mark: String) -> void:
	var m := _mark(at_mark)
	if m == null:
		return
	if city.walker == null:
		Walker.avatar = "res://assets/people/story_karthik.glb"
		city.walker = Walker.new()
		city.walker.name = "OnFoot"
		city.walker.walk_speed = 1.4                     # a person's walking pace (the Walk clip plays to it, no sliding feet)
		city.walker.run_speed = 4.2
		city.add_child(city.walker)
		Walker.avatar = ""
	city.walker.spawn_at(m.global_position + Vector3.UP * 0.1, m.global_position - m.global_basis.z)
	city.walker.activate()
	car.visible = false
	car.freeze = true
	_cams_back()
	map.visible = false                                   # (no city map or speedometer indoors)
	hud.visible = false
	city.walker.camera.make_current()
	if _ring == null:                                    # a soft ring on the floor where to go next
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.5
		_ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.8, 0.25)
		rm.emission_enabled = true
		rm.emission = Color(1.0, 0.75, 0.2)
		_ring.material_override = rm
		add_child(_ring)
	_ring.visible = true


func _walk_out() -> void:
	if _ring:
		_ring.visible = false
	if city.walker:
		city.walker.deactivate()
		city.walker.queue_free()
		city.walker = null
	city.streamer.target = car                           # (out of the car by F, the city followed him on foot:
	if city.map:                                         #  it follows the car again, as getting back in does)
		city.map.target = car
	if city.traffic:
		city.traffic.player = car
	car.visible = true
	car.freeze = false
	map.visible = true
	hud.visible = true
	city.cam.make_current()


## Walking the house: go to the next place (the ring), E there does what you came for.
func _home() -> void:
	if _in_task or city.walker == null:
		return
	var v: Dictionary = cur["visits"][_visit]
	if cur.has("knock"):                                 # someone at the door, knocking until it's opened
		_knock_t -= get_process_delta_time()
		if _knock_t <= 0.0:
			_knock_t = float(cur["knock"])
			_play_sfx("knock", -4.0)
	var at := Vector3.INF
	if cast.has(str(v["to"])) and (cast[str(v["to"])] as Node3D).visible:   # (to a person: up to them)
		var a: Node3D = cast[str(v["to"])]
		at = a.global_position + (city.walker.global_position - a.global_position).normalized() * 0.9
		at.y = a.global_position.y
	else:
		var m := _mark(str(v["to"]))
		if m == null:
			_task_done({})
			return
		at = m.global_position
	_ring.global_position = at + Vector3.UP * 0.03 + Vector3(0, sin(t_step * 4.0) * 0.02, 0)
	var near := Vector2(city.walker.global_position.x - at.x, city.walker.global_position.z - at.z).length() < float(v.get("reach", 1.1))
	if near and v.get("auto", false):                    # (just getting there is enough: the door, the corridor's end)
		t_step = 0.0
		_start_visit(v)
		return
	var e := Input.is_key_pressed(KEY_E)
	var pay := ""                                        # (Amma here: F gives her money for what's owed, as in free play)
	if city.money and str(cur.get("room", "")) == "home" and cast.has("amma") and (cast["amma"] as Node3D).visible:
		city.money.story_amma = cast["amma"]
		if _skip and not _paid_test and "--storypay" in OS.get_cmdline_user_args():   # (testing: beside her first)
			var am: Node3D = cast["amma"]
			city.walker.global_position = am.global_position - am.global_basis.z * 1.0
			print("STORY pay test: bills %d, wallet %d" % [city.money.bills.size(), fines.sim.money])
		pay = city.money.offer("home", room, city.walker.global_position)
		var f := Input.is_key_pressed(KEY_F)
		if pay != "" and f and not _f_down:
			city.money.go()
		elif pay != "" and _skip and not _paid_test and "--storypay" in OS.get_cmdline_user_args():   # (testing: ₹500 to her once)
			_paid_test = true
			print("STORY pay: '%s', wallet %d" % [pay, fines.sim.money])
			city.money.go()
			city.money._note(500)
			city.hands.put_back()
			print("STORY paid: wallet %d, %s" % [fines.sim.money, str(city.money.bills.map(func(b): return "%s %d/%d" % [b["id"], b["paid"], b["amount"]]))])
		_f_down = f
	if _skip and v.get("home_meal", false) and _peek == -1 and t_step > 0.2:   # (testing: walk him up to the meal)
		_peek = _visit
		var from: Vector3 = city.walker.global_position
		var d := Vector3(at.x - from.x, 0.0, at.z - from.z)
		if d.length() > 2.4:
			var look := at                              # (turned a little towards whoever is home, in the picture)
			for k in cast:
				look = (at + (cast[k] as Node3D).global_position) * 0.5
			city.walker.spawn_at(at - d.normalized() * 2.4, look)
			city.walker._pitch = -0.45                 # (looking down a little, at the room rather than the fan)
			city.walker.head.rotation.x = -0.45
	if _peek == _visit and t_step > 0.7:
		_peek = -2 - _visit
		t_step = 0.0                                    # (the meal card opens a second after the picture)
		_shot()
	if (near and e and not _e_down) or (_skip and t_step > 1.0):
		t_step = 0.0
		_peek = -1
		_start_visit(v)
	_e_down = e
	_note_t -= get_process_delta_time()
	goal.text = tr_(v.get("goal", "")) + ("\n" + ("E: " if lang == "en" else "E: ") + tr_(v.get("prompt", {"en": "go", "ta": "போ"})) if near else "") \
		+ ("\n" + _note if _note_t > 0.0 else "") + ("\nF: " + pay if pay != "" else "")


func _start_visit(v: Dictionary) -> void:
	_in_task = true
	if not v.has("task"):                                # walking somewhere, and what he does there
		_visit_do(v)
		return
	var spec: Dictionary = v.duplicate()
	if v.get("home_meal", false) and fines and fines.sim.groceries <= 0:
		# the month's groceries are finished: the next month's bought now (the kirana delivers)
		fines.sim.money -= fines.sim.GROCERY_COST
		fines.sim.groceries += fines.sim.GROCERY_MEALS
		_note = ("Groceries finished: this month's bought  −₹%d" if lang == "en" else "மளிகை தீர்ந்துச்சு: இந்த மாச மளிகை  −₹%d") % fines.sim.GROCERY_COST
		_note_t = 6.0
	if str(v.get("task", "")) == "sign" and city.bail and fines and fines.sim.minute < city.bail.WINDOW:
		await _bench_till_six()                          # (before six the register isn't open: the bench first)
	if fines:
		spec["wallet"] = fines.sim.money
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tasks.start(str(v.get("task", "ready")), spec, lang, _skip)
	_speak_tip(v)


## The rider app's first order: accepted, the story goes on; turned down, Divya's text, and it's still there.
func _offer_answer(yes: bool) -> void:
	if str(cur.get("do", "")) != "task" or str(cur.get("task", "")) != "phone":
		return
	if yes:
		_task_done({"accepted": true})
	else:
		city.phone.message({"en": "Divya", "ta": "திவ்யா"}, cur.get("decline_says", {"en": "Anna. Friday. Fees.", "ta": "அண்ணா. வெள்ளி. ஃபீஸ்."}))
		city.phone.rider_offer(cur.get("app", {}), cur.get("order", []))


func _otp_typed() -> void:
	if str(cur.get("do", "")) == "task" and str(cur.get("task", "")) == "otp":
		_task_done({"otp": true})


## A task's tip is said by whoever gave it (in his ear, remembered): a subtitle over the task, not a box of text.
const TIP_BY := {"Raghavan": "raghavan", "Amma": "amma", "Hotel owner": "cook", "Suresh": "suresh", "Divya": "divya"}


func _speak_tip(spec: Dictionary) -> void:
	if not spec.has("tip"):
		return
	var by := "karthik"
	var label := str(spec.get("tip_who", {}).get("en", "")) if spec.get("tip_who") is Dictionary else ""
	for k in TIP_BY:
		if label.begins_with(k):
			by = TIP_BY[k]
	_say({"who": by, "en": str(spec["tip"].get("en", "")), "ta": str(spec["tip"].get("ta", ""))}, false)
	ui.move_child(box, ui.get_child_count() - 1)        # (over the task's picture, above it: its buttons are below)
	_box_at_top(true)


func _box_at_top(on: bool) -> void:
	box.anchor_top = 0.0 if on else 1.0
	box.anchor_bottom = 0.0 if on else 1.0
	box.offset_top = 20.0 if on else -200.0
	box.offset_bottom = 150.0 if on else -40.0


## Early at the station: Selvi sends him to the visitors' bench on the left wall, and he sits there till six
## (W gets him up; she says it again when he comes back).
func _bench_till_six() -> void:
	city.hud.say("Constable Selvi" if lang == "en" else "கான்ஸ்டபிள் செல்வி",
		"Six to seven, Karthik. Sit on the bench till six." if lang == "en" else "ஆறு மணியிலிருந்து ஏழு வரைக்கும், கார்த்திக். ஆறு மணி வரைக்கும் பெஞ்சுல உக்காரு.", 4.0)
	var c := _mark("constable")
	var seat: Node3D = null
	if c:
		seat = Node3D.new()                              # (the bench has no mark: 3.55 m left of her chair, 1.55 m nearer the door)
		c.get_parent().add_child(seat)
		seat.position = c.position + Vector3(-3.55, 0.0, 1.55)
		seat.rotation.y = PI / 2.0                       # facing into the room
	print("STORY early at the register (%s): on the bench till six" % city.phone._now())
	if city.life.busy:                                   # (already sitting or sleeping: the minutes just go by)
		fines.sim.minute = city.bail.WINDOW + 1.0
	else:
		if _skip:
			get_tree().create_timer(1.0).timeout.connect(_shot)   # (testing: the view from the bench)
		await city.life.sit_wait(seat, city.bail.WINDOW + 1.0, "Sit")
	if seat:
		seat.queue_free()
	if fines.sim.minute < city.bail.WINDOW:              # (he got up early)
		city.hud.say("Constable Selvi" if lang == "en" else "கான்ஸ்டபிள் செல்வி",
			"Not yet. Six." if lang == "en" else "இன்னும் இல்ல. ஆறு மணி.", 3.0)
		await _bench_till_six()


## A visit without a picture task: what he does when he gets there.
##   "sleep_until": "06:10"  lies down; his eyes close and the night goes by (life.gd), to that time the next day
##   "wait": minutes         sits there (the mark faces the way he sits) while the clock runs, stress "stress_per_hour"
##   "hand_phone": true      hands his phone over (it's gone from his pocket until "phone_back")
##   "phone_back": true      gets it back
##   (none of these)         just being there (and E) is enough: the next step follows
func _visit_do(v: Dictionary) -> void:
	var life = city.life
	if v.has("sleep_until") and life:
		var hm: PackedStringArray = str(v["sleep_until"]).split(":")
		var to := float(hm[0]) * 60.0 + float(hm[1])
		var mins: float = to - fines.sim.minute + (1440.0 if to <= fines.sim.minute + 30.0 else 0.0)   # (a night, not a nap)
		var m0: float = fines.sim.minute
		await life._pass(mins, "night's sleep", null, {"sleep": true, "stress": -8.0, "food": 0.0})
		life.tiredness = 0.0
		print("STORY slept %.0f min: %.0f → day %d %.0f" % [mins, m0, fines.sim.day, fines.sim.minute])
	elif v.has("wait") and life:
		var m := _mark(str(v["to"]))
		var s0: float = life.stress
		var m0: float = fines.sim.minute
		var mins := float(v["wait"])
		if v.has("until"):                               # (till a time of day: the drivers' hours)
			var hm: PackedStringArray = str(v["until"]).split(":")
			mins = float(hm[0]) * 60.0 + float(hm[1]) - fines.sim.minute
		mins = maxf(mins, 0.0) * (0.2 if _skip else 1.0)
		await life.sit_wait(m, fines.sim.minute + mins, str(v.get("pose", "Sit")))
		life.stress = clampf(s0 + float(v.get("stress_per_hour", 0.0)) * (fines.sim.minute - m0) / 60.0, 0.0, 100.0)
		if _skip and v.has("until"):                     # (testing: the rest of the wait at once)
			var hm2: PackedStringArray = str(v["until"]).split(":")
			fines.sim.minute = maxf(fines.sim.minute, float(hm2[0]) * 60.0 + float(hm2[1]))
	if v.get("wall", false):                             # at his wall: pin what he has (wall.gd); done when he steps back
		for it in city.hands.items:
			wall.add(it)
		for ph in city.phone.photos:
			if str(ph.get("tag", "")) != "":
				var w: Dictionary = ph.duplicate()
				w["id"] = ph["tag"]
				w["title"] = ph["label"]
				w["kind"] = "photo" if ph.has("tex") else "recording"
				wall.add(w)
		wall.open(lang)
		if _skip:                                        # (testing: everything up, two threads, then back)
			var i := 0
			for it in wall.pool:
				wall.state["pins"][str(it["id"])] = Vector2(0.15 + (i % 5) * 0.17, 0.35 + floori(i / 5.0) * 0.3)
				i += 1
			if wall.pool.size() >= 3:
				wall.state["threads"] = [[str(wall.pool[0]["id"]), str(wall.pool[1]["id"])], [str(wall.pool[1]["id"]), str(wall.pool[2]["id"])]]
			get_tree().create_timer(0.8).timeout.connect(_shot)
			get_tree().create_timer(1.6).timeout.connect(func():
				wall.visible = false
				wall.closed.emit())
		return
	if v.get("hand_phone", false):
		city.phone.hold(false)
		city.phone.taken = true
	if v.get("phone_back", false):
		city.phone.taken = false
	_task_done({})


# ---- riding as a passenger ----
## "ride": Karthik in the back seat of someone else's vehicle ("vehicle", "paint"), the streets going past the window,
## for "secs"; then the picture goes dark and the next step finds him there. "cast": people where it sets off
## (Amma at the gate), placed in the vehicle's frame as scenes are.
var _ride_path := PackedVector3Array()
var _ride_i2 := 0
var _ride_speed := 0.0
var _ride_used := {}
var _ride_snd: AudioStreamPlayer
var _window: Control                     # the back seat's window: a dark frame and the rear grille's bars


func _draw_window() -> void:
	var vs := _window.get_viewport_rect().size
	var c := Color(0.02, 0.02, 0.025)
	var m := Vector4(vs.x * 0.07, vs.y * 0.1, vs.x * 0.07, vs.y * 0.2)     # left, top, right, bottom
	_window.draw_rect(Rect2(0, 0, vs.x, m.y), c)
	_window.draw_rect(Rect2(0, vs.y - m.w, vs.x, m.w), c)
	_window.draw_rect(Rect2(0, 0, m.x, vs.y), c)
	_window.draw_rect(Rect2(vs.x - m.z, 0, m.z, vs.y), c)
	var r := 60.0                                         # rounded inner corners
	for k in 4:
		var cx: float = m.x if k % 2 == 0 else vs.x - m.z
		var cy: float = m.y if k < 2 else vs.y - m.w
		var sx := 1.0 if k % 2 == 0 else -1.0
		var sy := 1.0 if k < 2 else -1.0
		var pts := PackedVector2Array([Vector2(cx, cy)])
		for i in 9:
			var a := PI * 0.5 * i / 8.0
			pts.append(Vector2(cx + sx * (r - r * sin(a)), cy + sy * (r - r * cos(a))))
		_window.draw_colored_polygon(pts, c)
	for i in 3:                                           # the steel bars of a police jeep's back
		var x := m.x + (vs.x - m.x - m.z) * (i + 1) / 4.0
		_window.draw_rect(Rect2(x - 5.0, m.y, 10.0, vs.y - m.y - m.w), Color(0.08, 0.08, 0.09))
	_window.draw_rect(Rect2(m.x, vs.y - m.w - 70.0, vs.x - m.x - m.z, 8.0), Color(0.08, 0.08, 0.09))


func _ride_start() -> void:
	_walk_out()
	_unload_room()
	if car.vehicle != str(cur.get("vehicle", "xuv")):
		var pc: Array = cur.get("paint", [0.95, 0.95, 0.93])
		car.configure(str(cur.get("vehicle", "xuv")), Color(pc[0], pc[1], pc[2]))
	car.visible = false                                  # (we're inside it: the window's frame is drawn over the view)
	car.freeze = true
	map.visible = false
	hud.visible = false
	_window.visible = true
	_anchor()
	_cast(cur.get("cast", {}))
	_ride_path = PackedVector3Array()
	_ride_i2 = 0
	_ride_speed = 0.0
	_ride_used = {}
	if scene_cam == null:
		scene_cam = Camera3D.new()
		scene_cam.far = 4000.0
		add_child(scene_cam)
	scene_cam.fov = 62.0
	scene_cam.make_current()
	_ride_snd = AudioStreamPlayer.new()
	_ride_snd.stream = RoomSound.sound("engine")
	(_ride_snd.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	(_ride_snd.stream as AudioStreamWAV).loop_end = (_ride_snd.stream as AudioStreamWAV).data.size() / 2
	_ride_snd.volume_db = -14.0
	add_child(_ride_snd)
	_ride_snd.play()


## The next stretch of street from p: a road piece that starts or ends there (the bigger roads first, none twice); at
## the start, the street he's on, from the point of it nearest the gate onwards.
func _ride_next(p: Vector3, first: bool) -> PackedVector3Array:
	var best := PackedVector3Array()
	var score := INF
	var rank := {"trunk": 0.0, "primary": 0.0, "secondary": 2.0, "tertiary": 4.0, "residential": 8.0, "unclassified": 8.0}
	for k in city.streamer.loaded:
		for r in (city.streamer.loaded[k] as Node3D).get_meta("roads", []):
			if not rank.has(str(r["c"])):
				continue
			var a = r["p"]
			var n: int = a.size() / 3
			if n < 2:
				continue
			var key := "%.1f,%.1f" % [a[0], a[2]]
			if _ride_used.has(key):
				continue
			if first:                                       # the nearest point of any street, then along it
				for i in n:
					var d := Vector2(a[i * 3] - p.x, a[i * 3 + 2] - p.z).length()
					if d < score:
						score = d
						best = PackedVector3Array()
						var fwd: bool = i < n - 1
						var j := i
						while j >= 0 and j < n:
							best.append(Vector3(a[j * 3], a[j * 3 + 1], a[j * 3 + 2]))
							j += 1 if fwd else -1
						_ride_used[key] = true
				continue
			for flip in [false, true]:
				var e := (n - 1) * 3 if flip else 0
				var d := Vector2(a[e] - p.x, a[e + 2] - p.z).length()
				if d > 30.0:
					continue
				var sc: float = d + float(rank[str(r["c"])]) + randf() * 3.0
				if sc < score:
					score = sc
					best = PackedVector3Array()
					for i in n:
						var j: int = n - 1 - i if flip else i
						best.append(Vector3(a[j * 3], a[j * 3 + 1], a[j * 3 + 2]))
	if not best.is_empty() and not first:
		_ride_used["%.1f,%.1f" % [best[0].x, best[0].z]] = true
		_ride_used["%.1f,%.1f" % [best[best.size() - 1].x, best[best.size() - 1].z]] = true
	if best.is_empty() and not first and _ride_path.size() >= 2:   # a dead end: turn round, back the way we came
		for i in _ride_path.size():
			best.append(_ride_path[_ride_path.size() - 1 - i])
	return best


func _ride(dt: float) -> void:
	var secs := float(cur.get("secs", 25.0)) * (0.25 if _skip else 1.0)
	if _ride_path.is_empty() or _ride_i2 >= _ride_path.size() - 1:
		var from: Vector3 = car.global_position if _ride_path.is_empty() else _ride_path[_ride_path.size() - 1]
		var nxt := _ride_next(from, _ride_path.is_empty())
		if not nxt.is_empty():
			_ride_path = nxt
			_ride_i2 = 0
	if _ride_path.size() >= 2 and _ride_i2 < _ride_path.size() - 1 and t_step > 2.5:          # (a moment at the gate first, then away)
		_ride_speed = move_toward(_ride_speed, 9.0, dt * 2.0)
		var a := _ride_path[_ride_i2]
		var b := _ride_path[_ride_i2 + 1]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var tgt := b + Vector3(dir.z, 0.0, -dir.x) * 1.1      # keeping left
		var to := Vector3(tgt.x - car.global_position.x, 0.0, tgt.z - car.global_position.z)
		if to.length() < 1.5:
			_ride_i2 += 1
		var stepv := to.normalized() * minf(_ride_speed * dt, to.length())
		var y := lerpf(car.global_position.y, b.y, minf(1.0, dt * 3.0))   # (the road's own height: the street
		car.global_position = Vector3(car.global_position.x + stepv.x, y, car.global_position.z + stepv.z)   # may not be loaded yet)
		if to.length() > 0.2:
			var want := atan2(-to.x, -to.z)
			car.rotation.y = lerp_angle(car.rotation.y, want, minf(1.0, dt * 2.0))
	var fwd: Vector3 = Vector3(car.forward().x, 0.0, car.forward().z).normalized()
	var left := Vector3(-fwd.z, 0.0, fwd.x)
	var seat: Vector3 = car.global_position + Vector3.UP * float(cur.get("eye", 1.45)) - fwd * 0.7 + left * 0.45 \
		+ Vector3.UP * sin(t_step * 9.0) * 0.008 * _ride_speed / 9.0
	scene_cam.global_position = seat                     # the back seat, on the footpath side: out of his window
	scene_cam.look_at(seat + fwd * 1.6 + left * 2.0 - Vector3.UP * 0.2, Vector3.UP)
	if _shots != "" and int(t_step / 6.0) != int((t_step - dt) / 6.0):   # (testing: the view every 6 s)
		_shot()
	if t_step > secs:
		_window.visible = false
		car.visible = true
		if _ride_snd:
			_ride_snd.queue_free()
			_ride_snd = null
		_clear_cast()
		_cams_back()
		car.freeze = false
		_park = str(cur.get("park", ""))                # (the car's set down there, out of sight, for later)
		_next()


## "wait": somewhere to be until a time ("until": "21:00"): on foot, E sits him down where he is (the kerb, a step)
## and the evening goes by (life.gd sit_wait); already that late, on at once.
func _wait_step() -> void:
	var hm: PackedStringArray = str(cur["until"]).split(":")
	var to := float(hm[0]) * 60.0 + float(hm[1])
	if fines.sim.minute >= to or (fines.sim.minute < 240.0 and to > 720.0):   # (past it, or past midnight)
		_next()
		return
	if _in_task:
		return
	if _skip and t_step > 1.0 and city.walker == null and city.has_method("toggle_on_foot"):
		car.speed = 0.0
		city.toggle_on_foot()
	var e := Input.is_key_pressed(KEY_E)
	if city.walker and ((e and not _e_down) or (_skip and t_step > 1.5)):
		_in_task = true
		await city.life.sit_wait(null, to if not _skip else minf(to, fines.sim.minute + 20.0))
		_in_task = false
		if _skip:
			fines.sim.minute = to
	_e_down = e
	var hint := _off_key() if city.walker == null else ("E: sit and wait" if lang == "en" else "E: உட்கார்ந்து காத்திருங்க")
	goal.text = tr_(cur["goal"]) + "\n" + hint


## "gate": someone won't let him by, and two ways round it, both done, not chosen from a list: take out his wallet
## and hold a note out to them (a "bribe" or more: "sets"["bribe"]); or go to the stall nearby ("cast"'s "seller"),
## buy tea and vadai ("price") and bring them back ("sets"["tea"]).
var _has_tea := false


func _gate() -> void:
	var a: Node3D = cast.get(str(cur["who"]))
	var sl: Node3D = cast.get("seller")
	if a == null or city.walker == null or _in_task:
		return
	var w: Vector3 = city.walker.global_position
	var near_him := w.distance_to(a.global_position) < 2.4
	var near_stall := sl != null and w.distance_to(sl.global_position) < 2.4
	var e := Input.is_key_pressed(KEY_E)
	var pick := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--storychoose="):
			pick = int(arg.get_slice("=", 1))
	if _skip and t_step > 1.0:                           # (testing: 1 the note, 2 the tea)
		if pick != 2:
			_gate_note(int(cur.get("bribe", 300)))
			return
		var to: Node3D = a if _has_tea else sl
		city.walker.global_position = to.global_position + Vector3(1.0, 0.1, 0.0)
		near_him = _has_tea
		near_stall = not _has_tea
		e = true
		_e_down = false
	if e and not _e_down:
		if near_stall and not _has_tea:
			var price := int(cur.get("price", 40))
			if fines.sim.money >= price:
				fines.sim.money -= price
				_has_tea = true
				_play_sfx("clink", -6.0)
				city.hands.items.append({"id": "tea", "kind": "note", "title": {"en": "Tea and vadai", "ta": "டீ, வடை"},
					"body": {"en": "Two glasses of tea, two vadai in newspaper.", "ta": "ரெண்டு கிளாஸ் டீ, பேப்பர்ல ரெண்டு வடை."}})
		elif near_him and _has_tea:
			city.hands.take("tea")
			flags[str(cur["sets"]["tea"])] = true
			print("STORY gate → tea")
			_next()
			return
		elif near_him:
			city.hands.give({"id": "wallet", "kind": "wallet", "title": {"en": "Wallet", "ta": "பர்ஸ்"}})
			if not city.hands.note_given.is_connected(_gate_note):
				city.hands.note_given.connect(_gate_note)
	_e_down = e
	var hint := ""
	if near_stall and not _has_tea:
		hint = ("E: tea and vadai, ₹%d" if lang == "en" else "E: டீ, வடை, ₹%d") % int(cur.get("price", 40))
	elif near_him and _has_tea:
		hint = "E: give him the tea" if lang == "en" else "E: அவருக்கு டீ குடுங்க"
	elif near_him:
		hint = "E: your wallet" if lang == "en" else "E: உங்க பர்ஸ்"
	goal.text = tr_(cur["goal"]) + ("\n" + hint if hint != "" else "")


func _gate_note(amount: int) -> void:
	if str(cur.get("do", "")) != "gate":
		return
	if city.hands.note_given.is_connected(_gate_note):
		city.hands.note_given.disconnect(_gate_note)
	city.hands.take("wallet")
	if amount < int(cur.get("bribe", 300)):              # too little: he pushes it back
		_say({"who": str(cur["who"]), "en": "₹%d? For that you can go home. Go." % amount, "ta": "₹%d-ஆ? அதுக்கு வீட்டுக்கு போ. போ." % amount}, false)
		get_tree().create_timer(2.5).timeout.connect(func(): box.visible = false)
		return
	fines.sim.money -= amount
	flags[str(cur["sets"]["bribe"])] = true
	print("STORY gate → note %d" % amount)
	_next()


## "evidence": the newest recording on his phone with "speaker" in it becomes evidence ("tag", "label"; "label_paid"
## when the flag "paid" is set: a bought word); either way the wall gets his memory of it ("memory": a card).
func _evidence() -> void:
	var who := tr_(data["people"].get(str(cur["speaker"]), {}))
	for ph in city.phone.photos:
		if ph.has("lines") and str(ph.get("tag", "")) == "":
			var has := false
			for ln in ph["lines"]:
				if str(ln[0]) == who:
					has = true
			if has:
				ph["tag"] = str(cur["tag"])
				ph["label"] = cur.get("label_paid", cur["label"]) if flags.get(str(cur.get("paid", "-")), false) else cur["label"]
				print("STORY evidence: recording → %s" % ph["tag"])
				break
	if cur.has("memory"):
		wall.add(cur["memory"])


## "dvr": someone's monitor with a recorder's footage on it (dvr.gd), worked by him: he steps up to it with E, plays
## and scrubs it, and takes pictures of the screen with his phone. The step is done when he steps back with at least
## one picture of it (until then E at "who" opens it again: "(I should have a picture of that.)").
func _photo_hook() -> void:
	if not city.phone.photo_taken.is_connected(_on_photo):
		city.phone.photo_taken.connect(_on_photo)


func _on_photo(tag: String) -> void:
	if doorbell.visible and not city.phone.photos.is_empty():   # a picture of her tablet: that night's clip
		var fd: Dictionary = doorbell.frame_tag()
		city.phone.photos[0]["tag"] = fd["tag"]
		city.phone.photos[0]["label"] = fd["label"]
		flags["doorbell_photo"] = true
		print("STORY photo of the doorbell clip")
	elif dvr.visible and not city.phone.photos.is_empty():   # a picture of the monitor: what's on the screen right now
		var ft: Dictionary = dvr.frame_tag()
		city.phone.photos[0]["tag"] = ft["tag"]
		city.phone.photos[0]["label"] = ft["label"]
		flags["dvr_photo"] = true
		flags[str(ft["tag"])] = true
		if ft.get("card", false):
			flags["dvr_card"] = true
		print("STORY photo of the screen: %s at %s" % [ft["tag"], dvr.hms(dvr.t)])
	elif str(cur.get("do", "")) == "deal" and tag == "qr_" + str(cur["who"]):
		city.phone.photos.pop_front()                   # (a scan, not a picture he keeps)
		_deal_pay()


## The doorbell in Ashwin's door frame, beside him, looking at whoever is at the door (Karthik): a few seconds of
## him, and the clock (doorbell.gd keeps it for E05).
func _doorbell_capture() -> void:
	var a: Node3D = cast.get("ashwin")
	var w = city.walker
	if a == null or w == null:
		return
	var to_him: Vector3 = w.global_position - a.global_position
	to_him.y = 0.0
	if to_him.length() < 0.2:
		return
	var side := to_him.normalized().cross(Vector3.UP)
	var from: Vector3 = a.global_position + side * 0.8 + to_him.normalized() * 0.1 + Vector3.UP * 1.65
	if w.model:
		w.model.visible = true                           # (his body, for the camera, even in his own eyes)
	await doorbell.capture(self, get_viewport().world_3d, from, w.global_position + Vector3.UP * 1.1, fines.sim.minute, fines.sim.day)
	if w.model and is_instance_valid(w):
		w.model.visible = w.third_person


## "snapshot": a family photo, taken in the room he's in (an album's picture: "group" stood in a row before the room's
## wide camera, facing it), warm and faded like an old print, then put in his hands ("item": a photo) to look at.
func _snapshot() -> void:
	var cm := room.find_child("Cam_wide", true, false) as Node3D if room else null
	var lk := room.find_child("Look_wide", true, false) as Node3D if room else null
	if cm == null or lk == null:
		_snap_ready = true
		return
	var flat := Vector3(lk.global_position.x - cm.global_position.x, 0.0, lk.global_position.z - cm.global_position.z)
	var floor_y: float = _mark("karthik").global_position.y if _mark("karthik") else lk.global_position.y - 1.0
	var mid := Vector3(cm.global_position.x, floor_y, cm.global_position.z) + flat.normalized() * minf(flat.length() * 0.55, 2.3)
	var side := flat.normalized().cross(Vector3.UP)
	mid -= side * 0.5                                    # (clear of the plastic chairs in the middle of the room)
	var group: Array = cur.get("group", [])
	var spec := {}
	for k in group:
		spec[k] = {}
	_cast(spec)
	for i in group.size():
		var a: Node3D = cast[group[i]]
		a.floor_y = floor_y
		var at := mid + side * (float(i) - (group.size() - 1) * 0.5) * 0.62
		a.place(at, Vector3(cm.global_position.x, floor_y, cm.global_position.z))
		a.play("Idle")
	var w = city.walker
	var shown: bool = w != null and w.model != null and w.model.visible
	if shown:
		w.model.visible = false
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 480)
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 48.0
	vp.add_child(cam)
	var from := Vector3(cm.global_position.x, floor_y + 1.45, cm.global_position.z) + flat.normalized() * 0.1
	cam.global_transform = Transform3D(Basis.looking_at(mid + Vector3.UP * 1.2 - from, Vector3.UP), from)
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if shown and is_instance_valid(w):
		w.model.visible = true
	for k in group:
		cast[k].visible = false
	for y in img.get_height():                           # an old print: warm, faded, the corners darker
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var dx := (x / float(img.get_width())) - 0.5
			var dy := (y / float(img.get_height())) - 0.5
			var v := 1.0 - 0.7 * (dx * dx + dy * dy)
			c = Color(c.r * 0.88 + 0.1, c.g * 0.8 + 0.08, c.b * 0.62 + 0.06) * v
			img.set_pixel(x, y, c)
	var item: Dictionary = cur["item"].duplicate()
	item["tex"] = ImageTexture.create_from_image(img)
	city.hands.give(item)
	if city.walker:
		city.walker.active = false
	_snap_ready = true
	t_step = 0.0
	print("STORY snapshot: %s" % str(group))
	if _skip:
		await get_tree().create_timer(0.6).timeout
		_shot()


## "doorbell": she holds out her tablet with the app open on that night's clip; he can take a picture of it (P on his
## phone's camera); Enter gives it back.
func _doorbell_open() -> void:
	if city.walker:
		city.walker.active = false
	_in_task = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	doorbell.open(lang)
	if _skip:                                           # (testing: a picture of it, then back)
		await get_tree().create_timer(1.2).timeout
		_shot()
		await city.phone._take_photo()
		await get_tree().create_timer(0.4).timeout
		doorbell.close()


func _doorbell_closed() -> void:
	if str(cur.get("do", "")) != "doorbell":
		return
	_in_task = false
	if city.walker:
		city.walker.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_next()


## "dial": done when he calls "who" from his contacts (phone.gd's dialled, after it rings out).
func _on_dial(c: Dictionary) -> void:
	if str(cur.get("do", "")) != "dial" or str(c.get("id", "")) != str(cur["who"]):
		return
	print("STORY dialled %s" % str(c.get("id", "")))
	_next()


func _dvr_open() -> void:
	if city.walker:
		city.walker.active = false
	_in_task = true
	dvr.open(lang)
	if _skip:                                           # (testing: 9:39 he comes in, a picture; 9:58 he leaves, another; then back)
		dvr.t = 21.0 * 3600 + 2393.0
		dvr.playing = false
		await get_tree().create_timer(0.5).timeout
		await city.phone._take_photo()
		dvr.t = 21.0 * 3600 + 3494.0
		await get_tree().create_timer(0.5).timeout
		await city.phone._take_photo()
		_shot()
		dvr.close()
		dvr.closed.emit()


func _dvr_closed() -> void:
	if str(cur.get("do", "")) != "dvr":
		return
	_in_task = false
	if city.walker:
		city.walker.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if flags.get("dvr_photo", false):
		_next()
		return
	_say({"who": "karthik", "en": "(I should have a picture of that. On my phone.)", "ta": "(அத ஒரு படம் எடுத்திருக்கணும். என் ஃபோன்ல.)"}, false)
	get_tree().create_timer(3.0).timeout.connect(func(): box.visible = false)


func _dvr_step() -> void:
	if _in_task or dvr.visible:
		return
	var a: Node3D = cast.get(str(cur["who"]))
	var near: bool = city.walker != null and a != null and city.walker.global_position.distance_to(a.global_position) < 2.6
	var e := Input.is_key_pressed(KEY_E)
	if near and e and not _e_down:
		_dvr_open()
	_e_down = e
	goal.text = tr_(cur["goal"]) + ("\n" + ("E: his screen" if lang == "en" else "E: அவர் ஸ்கிரீன்") if near else "")


## "deal": he wants money for it ("price"), by UPI: the QR code on his counter ("qr": where, in the scene frame), which
## Karthik's phone camera scans (P, the camera, a picture of the code) and the money goes; "sets"["paid"]. Or he walks
## away ("away" metres, or onto his scooter): "sets"["walked"]. Short of money, the payment fails and the code stays.
var _qr: Node3D


func _deal_start() -> void:
	_anchor()
	_cast(cur.get("cast", {}))
	if _qr == null:
		_qr = Node3D.new()
		add_child(_qr)
		var stand := MeshInstance3D.new()                # a printed QR on a little acrylic stand
		var qm := QuadMesh.new()
		qm.size = Vector2(0.22, 0.28)
		stand.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _qr_texture()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		stand.material_override = mat
		stand.position = Vector3(0, 1.15, 0)
		_qr.add_child(stand)
		var leg := MeshInstance3D.new()                  # (on a stool by his shutter, at a hand's height)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 1.0, 0.4)
		leg.mesh = bm
		leg.position = Vector3(0, 0.5, 0)
		_qr.add_child(leg)
	_qr.visible = true
	var qm: Node3D = _mark(str(cur["qr_mark"])) if cur.has("qr_mark") and room != null else null
	if qm:                                               # (on his counter: the stand only, no stool)
		_qr.global_position = qm.global_position + Vector3.UP * 0.05
		_qr.get_child(0).position = Vector3(0, 0.13, 0)
		_qr.get_child(1).visible = false
	else:
		var at := _w2(cur.get("qr", [-3.0, 2.0]))
		var g: float = city.streamer.height_at(at.x, at.z)
		_qr.global_position = Vector3(at.x, g if not is_nan(g) else _o.y, at.z)
		_qr.get_child(0).position = Vector3(0, 1.15, 0)
		_qr.get_child(1).visible = true
	var a: Node3D = cast.get(str(cur["who"]))
	if a:
		_qr.look_at(Vector3(a.global_position.x, _qr.global_position.y, a.global_position.z), Vector3.UP)   # (its face, +z, to the customer)
	city.phone.target(_qr.get_child(0), "qr_" + str(cur["who"]), {"en": "QR", "ta": "QR"}, 3.0)
	if _skip:
		var pick := 1
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--storychoose="):
				pick = int(arg.get_slice("=", 1))
		await get_tree().create_timer(1.0).timeout
		if pick == 1 and city.money and city.money.frozen and fines.sim.money >= int(cur["price"]):
			_deal_note(int(cur["price"]))                # (frozen: the cash, at once)
		elif pick == 1:
			_deal_pay()
		if str(cur.get("do", "")) == "deal":
			_deal_end("walked")


func _deal() -> void:
	var a: Node3D = cast.get(str(cur["who"]))
	if a == null:
		return
	var door: Node3D = _mark("door") if room != null else null
	if city.walker == null or city.walker.global_position.distance_to(a.global_position) > float(cur.get("away", 18.0)) \
			or (door != null and city.walker.global_position.distance_to(door.global_position) < 1.0):   # (out of his shop)
		if t_step > 1.0:
			_deal_end("walked")
		return
	var near: bool = city.walker.global_position.distance_to(_qr.global_position) < 3.0
	var hint := ("P: your phone, the camera: scan the QR (₹%d)" if lang == "en" else "P: உங்க ஃபோன், கேமரா: QR ஸ்கேன் (₹%d)") % int(cur["price"])
	var cash_ok: bool = city.money != null and city.money.frozen
	if cash_ok and city.walker.global_position.distance_to(a.global_position) < 2.6:
		hint = ("E: your wallet (₹%d of ₹%d in his hand)" if lang == "en" else "E: உங்க பர்ஸ் (₹%d / ₹%d அவர் கையில)") % [_cash_in, int(cur["price"])]
		var e := Input.is_key_pressed(KEY_E)
		if e and not _e_down and not city.hands.is_busy():
			city.hands.give({"id": "wallet", "kind": "wallet", "title": {"en": "Wallet", "ta": "பர்ஸ்"}})
			if not city.hands.note_given.is_connected(_deal_note):
				city.hands.note_given.connect(_deal_note)
		_e_down = e
	goal.text = tr_(cur["goal"]) + ("\n" + hint if near or cash_ok else "")


## Cash for the deal, a note at a time; what's held out stays with him until it's all there (then it's paid).
var _cash_in := 0


func _deal_note(amount: int) -> void:
	if str(cur.get("do", "")) != "deal":
		return
	fines.sim.money -= amount
	_cash_in += amount
	if _cash_in >= int(cur["price"]):
		_cash_in = 0
		if city.hands.note_given.is_connected(_deal_note):
			city.hands.note_given.disconnect(_deal_note)
		_play_sfx("clink", -6.0)
		_deal_end("paid")
	elif fines.sim.money <= 0:                          # all he had: he takes it back
		fines.sim.money += _cash_in
		_say({"who": str(cur["who"]), "en": "₹%d? Come back when you have five." % _cash_in, "ta": "₹%d-ஆ? அஞ்சாயிரம் இருக்கும்போது வா." % _cash_in}, false)
		get_tree().create_timer(3.0).timeout.connect(func(): box.visible = false)
		_cash_in = 0
	else:
		city.hands.give({"id": "wallet", "kind": "wallet", "title": {"en": "Wallet", "ta": "பர்ஸ்"}})


func _deal_pay() -> void:
	var price := int(cur["price"])
	if city.money and city.money.frozen:
		city.money.pay_online(price, tr_(cur.get("payee", {"en": "merchant"})))
		_say({"who": str(cur["who"]), "en": "Frozen? Then cash. Five thousand, in my hand.", "ta": "முடக்கமா? அப்போ கேஷ். அஞ்சாயிரம், என் கையில."}, false)
		get_tree().create_timer(3.0).timeout.connect(func(): box.visible = false)
		return
	if fines.sim.money < price:
		city.phone.message({"en": "UPI", "ta": "UPI"}, {"en": "Payment of ₹%d failed: not enough balance." % price,
			"ta": "₹%d பேமென்ட் தோல்வி: பேலன்ஸ் போதாது." % price})
		return
	fines.sim.money -= price
	city.phone.message({"en": "UPI", "ta": "UPI"}, {"en": "₹%d paid to %s." % [price, tr_(cur.get("payee", {"en": "merchant"}))],
		"ta": "₹%d %s-க்கு அனுப்பப்பட்டது." % [price, tr_(cur.get("payee", {"en": "merchant"}))]})
	_play_sfx("clink", -6.0)
	_deal_end("paid")


func _deal_end(how: String) -> void:
	if how == "walked" and _cash_in > 0:                # (the notes he'd held out go back in his wallet)
		fines.sim.money += _cash_in
		_cash_in = 0
	if city.hands.note_given.is_connected(_deal_note):
		city.hands.note_given.disconnect(_deal_note)
	city.phone.clear_targets()
	if _qr:
		_qr.visible = false
	flags[str(cur["sets"][how])] = true
	print("STORY deal → %s" % how)
	_next()


static func _qr_texture() -> ImageTexture:
	var n := 29
	var img := Image.create(n + 4, n + 4, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4120
	for y in n:
		for x in n:
			if rng.randf() < 0.5:
				img.set_pixel(x + 2, y + 2, Color.BLACK)
	for c in [Vector2i(0, 0), Vector2i(n - 7, 0), Vector2i(0, n - 7)]:   # the three finder squares
		for y in 7:
			for x in 7:
				var ring := maxi(absi(x - 3), absi(y - 3))
				img.set_pixel(c.x + x + 2, c.y + y + 2, Color.BLACK if ring != 2 else Color.WHITE)
	return ImageTexture.create_from_image(img)


## Somewhere to eat: on foot at the door of any of the eateries, E for the menu.
func _eat_out() -> void:
	if _in_task:
		return
	var here: Vector3 = city.walker.global_position if city.walker else car.global_position
	var near_k := ""
	for k in cur["eateries"]:
		var q := place_pos(str(k))
		if Vector2(here.x - q.x, here.z - q.z).length() < 8.0:
			near_k = str(k)
	var e := Input.is_key_pressed(KEY_E)
	if (near_k != "" and city.walker != null and e and not _e_down) or (_skip and t_step > 1.0):
		if near_k == "":
			near_k = str(cur["eateries"][0])
			for a in OS.get_cmdline_user_args():      # (testing: --eatat=<place> eats there)
				if a.begins_with("--eatat="):
					near_k = a.get_slice("=", 1)
		_in_task = true
		_beam.visible = false
		map.pin = null
		var spec: Dictionary = cur.duplicate()
		spec["title"] = data["places"][near_k]
		spec["menu"] = cur["menus"].get(near_k, cur["menus"].values()[0])
		spec.merge(cur.get("tips", {}).get(near_k, {}), true)   # (a place's own tip: the five-star's host)
		if fines:
			spec["wallet"] = fines.sim.money
		_load_room(str(cur.get("rooms", {}).get(near_k, "mess")), near_k)   # inside (a mess, or the five-star's
		# restaurant): Karthik at his table, the owner (or the host) at the counter
		_cast({"karthik": {"mark": "karthik_eat", "anim": "Sit"}, "cook": {"mark": "cook", "anim": "Idle"}})
		_dish("")                                       # an empty leaf till he orders
		for n in (room.find_children("Sign_*", "", true, false) if room else []):   # the board over the hatch: its name
			(n as Node3D).visible = str(n.name) == "Sign_" + near_k
		_cams_on()
		_room_cam("wide")                               # walking in: the hall, the place's name over the hatch
		_shot()
		get_tree().create_timer(0.6 if _skip else 2.0).timeout.connect(func():   # then at his table
			_room_cam("eat")
			_shot())
		get_tree().create_timer(1.2 if _skip else 3.6).timeout.connect(func():   # a look round, then the menu
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			tasks.start("meal", spec, lang, _skip)
			_shot())                                    # (testing: the menu)
	_e_down = e
	var hint := ""
	if near_k != "":
		hint = (_off_key()) if city.walker == null else \
			(("E: go in and eat at " if lang == "en" else "E: சாப்பிட உள்ளே போங்க: ") + tr_(data["places"][near_k]))
	goal.text = tr_(cur["goal"]) + ("\n" + hint if hint != "" else "")


## Does the story use E where you stand (a room of its own, an eatery's door)? The city's doors (city_doors.gd)
## stay out of its way there.
func claims_e(p: Vector3) -> bool:
	match str(cur.get("do", "")):
		"home":
			return true
		"eat_out":
			for k in cur["eateries"]:
				var q := place_pos(str(k))
				if Vector2(p.x - q.x, p.z - q.z).length() < 10.0:
					return true
	return false


## Minutes since noon (so 11 PM is before 12:30 AM): comparing night times across midnight.
func _since_noon(m: float) -> float:
	return fmod(m - 720.0 + 2880.0, 1440.0)


## A delivery shift on the rider app: an order is offered (a restaurant to pick up from, a neighbourhood to drop
## at, the pay and the time to be there by); E takes it, Q ends the shift. Ride to the restaurant, then to the
## customer: paid on arrival (with a tip when on time), and the next order comes in. The shift ends on Q or at
## "until"; the story goes on (home).
var _gig_take := 0                    # the rider app's answer: 1 taken, 2 shift ended


func _gig_answer(yes: bool) -> void:
	if str(cur.get("do", "")) == "gigs":
		_gig_take = 1 if yes else 2


func _gig_offer() -> void:
	var here: Vector3 = car.global_position
	var picks: Array = cur["pickups"].duplicate()
	picks.sort_custom(func(a, b): return place_pos(str(a)).distance_to(here) < place_pos(str(b)).distance_to(here))
	var pick: String = str(picks[randi() % mini(3, picks.size())])         # one of the three nearest restaurants
	var drops: Array = cur["drops"].filter(func(k): return place_pos(str(k)).distance_to(place_pos(pick)) > 900.0)
	if drops.is_empty():
		drops = cur["drops"]
	var drop: String = str(drops[randi() % drops.size()])
	var km := (here.distance_to(place_pos(pick)) + place_pos(pick).distance_to(place_pos(drop))) * 1.3 / 1000.0
	var ride_km := place_pos(pick).distance_to(place_pos(drop)) * 1.3 / 1000.0
	var pay := int(round((30.0 + ride_km * 12.0) / 5.0)) * 5
	var by := fmod((fines.sim.minute if fines else 1320.0) + km / float(cur.get("speed_kmh", 25.0)) * 60.0 + 12.0, 1440.0)
	_gig = {"state": "offer", "pick": pick, "drop": drop, "pay": pay, "by": by, "no": 4472 + _gig_done + randi() % 20}
	get_tree().create_timer(4.0 if not _skip else 0.5).timeout.connect(func():   # (after the last one's message)
		if str(cur.get("do", "")) != "gigs" or str(_gig.get("state", "")) != "offer":
			return
		if not city.phone.rider_answer.is_connected(_gig_answer):
			city.phone.rider_answer.connect(_gig_answer)
		city.phone.rider_offer(cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"}), [
			{"en": "Order #%d · pickup %s" % [_gig["no"], tr_(data["places"][pick])], "ta": "ஆர்டர் #%d · பிக்அப் %s" % [_gig["no"], tr_(data["places"][pick])]},
			{"en": "Drop: %s, by %s" % [tr_(data["places"][drop]), _clock12_of(by)], "ta": "டிராப்: %s, %s-க்குள்" % [tr_(data["places"][drop]), _clock12_of(by)]},
			{"en": "Pay ₹%d + tip" % pay, "ta": "கூலி ₹%d + டிப்" % pay}], {"en": "End shift", "ta": "ஷிஃப்ட் முடி"}))
	map.pin = null
	_beam.visible = false
	goal.text = ""
	t_step = 0.0
	get_tree().create_timer(4.2 if not _skip else 4.6).timeout.connect(_shot)   # (testing: each order as it comes in)


func _gig_goal() -> void:
	var app = cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"})
	var by := _clock12_of(float(_gig.get("by", 0.0)))
	goal.text = ""                                       # (it's on the rider app, and the map's pin)
	match str(_gig.get("state", "")):
		"pickup":
			city.phone.rider_job(app, [{"en": "Order #%d: pick up at" % _gig["no"], "ta": "ஆர்டர் #%d: பிக்அப்" % _gig["no"]}, data["places"][_gig["pick"]]])
		"drop":
			city.phone.rider_job(app, [{"en": "Order #%d: deliver to" % _gig["no"], "ta": "ஆர்டர் #%d: டெலிவரி" % _gig["no"]}, data["places"][_gig["drop"]],
				{"en": "by " + by, "ta": by + "-க்குள்"}])


func _clock12_of(m: float) -> String:
	var h := int(m / 60.0) % 24
	return "%d:%02d %s" % [(h + 11) % 12 + 1, int(m) % 60, "AM" if h < 12 else "PM"]


func _gigs(dt: float) -> void:
	_tick_clock(dt)
	if _skip and city.walker and city.has_method("toggle_on_foot"):   # (testing: back on the scooter)
		city.walker.global_position = car.global_position + Vector3.UP
		city.toggle_on_foot()
	var e := Input.is_key_pressed(KEY_E)
	var q := Input.is_key_pressed(KEY_Q)
	var e_hit := _gig_take == 1
	var q_hit := _gig_take == 2
	_gig_take = 0
	_e_down = e
	_q_down = q
	var late_night: bool = fines != null and cur.has("until") and _since_noon(fines.sim.minute) > _since_noon(_hhmm(str(cur["until"])))
	match str(_gig.get("state", "")):
		"offer":
			if t_step < 4.0:                             # (the next order shows once the "paid" note has gone)
				goal.text = ""
				return
			goal.text = ""
			if _skip and t_step > 4.5:                 # (testing: take two more orders, then go home)
				if _gig_done < 2:
					e_hit = true
				else:
					q_hit = true
				city.phone.rider["mode"] = "job"
				city.phone.hold(false)
			if q_hit or late_night:
				city.phone.message(cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"}),
					{"en": "Shift ended: %d orders, ₹%d earned." % [_gig_done, _gig_earned], "ta": "ஷிஃப்ட் முடிஞ்சது: %d ஆர்டர், ₹%d." % [_gig_done, _gig_earned]})
				city.phone.rider_clear()
				print("STORY gigs: %d orders, ₹%d" % [_gig_done, _gig_earned])
				flags["gig_orders"] = _gig_done
				_next()
				return
			if e_hit:
				_gig["state"] = "pickup"
				t_step = 0.0
				_jumped = false
				_gig_goal()
		"pickup", "drop":
			var key: String = _gig["pick"] if _gig["state"] == "pickup" else _gig["drop"]
			var p := place_pos(key)
			var g: float = city.streamer.height_at(p.x, p.z)
			map.pin = Vector2(p.x, p.z)
			_beam.visible = true
			_beam.global_position = Vector3(p.x, (g if not is_nan(g) else car.global_position.y) + 35.0, p.z)
			if _skip and t_step > 2.0 and not _jumped:  # (testing: jump there, spending the ride's minutes)
				var mins := Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length() * 1.3 / 1000.0 / float(cur.get("speed_kmh", 25.0)) * 60.0
				if _place_at(p):
					fines.sim.minute = fmod(fines.sim.minute + mins, 1440.0)
					_jumped = true
				return
			var d := Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length()
			if d < 45.0 + (60.0 if _skip else 0.0) and absf(car.speed) < 1.5 and (_jumped or not _skip):
				_jumped = false
				t_step = 0.0
				if _gig["state"] == "pickup":
					pass                                 # (the app moves on to the drop: _gig_goal)
					_gig["state"] = "drop"
					_gig_goal()
				else:
					var ontime := _since_noon(fines.sim.minute) <= _since_noon(float(_gig["by"]))
					var tip: int = (10 + randi() % 4 * 10) if ontime else 0
					var paid: int = int(_gig["pay"]) + tip
					if city.money:
						city.money.earn(paid, cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"}))
					else:
						fines.sim.money += paid
					_gig_done += 1
					_gig_earned += paid
					city.phone.message(cur.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"}),
						{"en": "Order #%d delivered. ₹%d credited%s." % [_gig["no"], paid, (" (₹%d tip)" % tip) if tip else " (late: no tip)"],
						"ta": "ஆர்டர் #%d டெலிவரி. ₹%d வந்துச்சு%s." % [_gig["no"], paid, (" (₹%d டிப்)" % tip) if tip else " (தாமதம்)"]})
					print("STORY gig #%d %s → %s paid %d %s" % [_gig["no"], _gig["pick"], _gig["drop"], paid, "ontime" if ontime else "late"])
					_gig_offer()


func _hhmm(s: String) -> float:
	var hm: PackedStringArray = s.split(":")
	return float(hm[0]) * 60.0 + float(hm[1])


## The dish on Karthik's leaf in the mess: the one ordered (room_mess Food_<kind>: tools/story_rooms.py food), or none.
func _dish(kind: String) -> void:
	if room == null:
		return
	for n in room.find_children("Food_*", "", true, false):
		(n as Node3D).visible = str(n.name) == "Food_" + kind


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
	if _skip and t_step > 1.5 and city.walker and city.has_method("toggle_on_foot"):   # (testing: back in, as a player would)
		city.walker.global_position = car.global_position + Vector3.UP
		city.toggle_on_foot()
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
			pass                                         # (his word on the ride is the verdict: comfort_verdict)
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
		_say({"who": "raghavan", "en": "Aiyo!", "ta": "ஐயோ!"}, false)
		get_tree().create_timer(1.8).timeout.connect(func():
			if str(cur.get("do", "")) == "drive":
				box.visible = false)
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
	said.custom_minimum_size = Vector2(440, 60)
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
	_window = Control.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.visible = false
	_window.draw.connect(_draw_window)
	ui.add_child(_window)
	ui.move_child(_window, 0)
	table = Table.new()
	table.visible = false
	table.said.connect(func(line: Dictionary):
		_say(line)
		if _f2f:
			_f2f.play("Talk" if str(line["who"]) == str(_f2f.get("who")) else "Idle")
		_shot()
		if _shots != "" and line == cur["lines"][-1]:     # (testing: the table while he waits, and the phone held up)
			get_tree().create_timer(1.3).timeout.connect(_shot)
			get_tree().create_timer(2.6).timeout.connect(_shot))
	table.finished.connect(func(result: Dictionary):
		for k in result:
			flags[k] = result[k]
		print("STORY table → %s" % str(result))
		for c in cur.get("remember", []):              # what he'll write down from memory, for the wall
			wall.add(c)
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.anchor_left = 0.5
		box.anchor_right = 0.5
		box.offset_top = -200
		box.offset_bottom = -40
		box.offset_left = -430
		box.offset_right = 430
		_next())
	ui.add_child(table)
	wall = Wall.new()
	wall.visible = false
	wall.closed.connect(func():
		if str(cur.get("do", "")) == "home" and _in_task:
			_task_done({"pinned": wall.pinned(), "tied": wall.tied()}))
	ui.add_child(wall)
	dvr = Dvr.new()
	dvr.visible = false
	dvr.closed.connect(_dvr_closed)
	ui.add_child(dvr)
	doorbell = Doorbell.new()
	doorbell.visible = false
	doorbell.closed.connect(_doorbell_closed)
	ui.add_child(doorbell)
	tasks = Tasks.new()
	tasks.visible = false
	tasks.finished.connect(_task_done)
	tasks.stage_changed.connect(_shot)
	tasks.dish_chosen.connect(_dish)
	ui.add_child(tasks)
	prompt = _label(18, Color(1, 1, 1, 0.9))
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.62
	prompt.offset_left = -400
	prompt.offset_right = 400
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	ui.add_child(prompt)
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


func _say(line: Dictionary, arrow := true) -> void:
	var key := "%d:%d:%s" % [step, line_i, str(line.get("en", "")).left(12)]
	if line.has("pay") and not _paid.has(key) and fines:
		_paid[key] = true
		fines.sim.money += int(line["pay"])
		pass                                             # (handed over in the line itself: no notice)
	var p: Dictionary = data["people"].get(line["who"], {})
	who.text = tr_(p)
	if city and city.phone:
		city.phone.heard(tr_(p), tr_(line))
	who.add_theme_color_override("font_color", Color.html(str(p.get("colour", "#ffffff"))))
	said.text = tr_(line)
	hint.text = "▸" if arrow else ""
	box.visible = true


func _refresh() -> void:
	if ui == null:
		return
	var kind := str(cur.get("do", ""))
	backdrop.visible = step < 0 or kind in ["card", "jump"] or (kind == "talk" and cur.get("backdrop", false))
	big.visible = kind in ["card", "jump"]
	small.visible = kind in ["card", "jump"]
	box.visible = false
	goal.visible = kind in ["drive", "free", "meet", "home", "eat_out", "gigs", "climb"]
	clock.visible = kind in ["drive", "free", "talk", "comfort_verdict", "deliver_verdict", "task", "lapse", "meet", "home", "eat_out", "gigs", "climb", "choose"]
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
			if _f2f and kind == "talk":                  # face to face: he talks when it's his line, listens to Karthik's
				_f2f.play("Talk" if str(cur["lines"][line_i]["who"]) == str(_f2f.get("who")) else "Idle")
		"drive":
			var to: Dictionary = data["places"][cur["to"]]
			goal.text = tr_(cur["goal"]) + "\n" + tr_(to)
			if city.walker:
				goal.text += "\n" + _on_key()
			if cur.has("ride_talk") and _ride_i >= 0 and _ride_i < cur["ride_talk"]["lines"].size():
				_say(cur["ride_talk"]["lines"][_ride_i], false)
		"free":
			goal.text = tr_(cur["goal"])
		"choose":
			who.text = ""
			var lines: Array = [tr_(cur["prompt"]), ""]
			for i in cur["options"].size():
				var o: Dictionary = cur["options"][i]
				if _shaken(o):                           # too stressed for this one: shown, but out of reach
					lines.append("%d   %s" % [i + 1, tr_(o.get("shaken", {"en": "(you can't, now)", "ta": "(இப்போ முடியாது)"}))])
				else:
					lines.append("%d   %s" % [i + 1, tr_(o["text"])])
			said.text = "\n".join(lines)
			hint.text = ("Press 1 – %d" if lang == "en" else "1 – %d அழுத்துங்க") % cur["options"].size()
			box.visible = true


func _shot() -> void:
	if _shots == "":
		return
	for i in 3:                                          # (a room just loaded draws a frame or two later)
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/story_%02d.jpg" % [_shots, _shot_n], 0.85)
	print("STORYSHOT %02d step %d %s line %d" % [_shot_n, step, str(cur.get("do", "")), line_i])
	_shot_n += 1
