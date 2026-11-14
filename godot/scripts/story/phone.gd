extends Control
## Karthik's phone (GAME_DESIGN.md §8: the phone is the menu). P holds it up and puts it away; the mouse taps it.
## Apps:
##   Notes      what he has to do: the story's goals land here (no goal line on the screen), the newest on top
##   Messages   texts from people (the story sends them)
##   Contacts   people he can reach, with where they are and when
##   Map        the places pinned for him (the story's leads)
##   Camera     a viewfinder over the world: left click takes a photo. Things the story is looking for ("targets":
##              a node, a tag) are recognised when they're in the middle of the picture and near enough
##   Recorder   records what people say while it runs (story.gd hands it every line); a recording is evidence
##   Photos     the photos and recordings, to look at again
##   Tamil Nilam  the state's land-records service (when the story gives it him: enable_nilam): an application for a
##              patta extract, district, taluk and village from its lists, the survey numbers typed in, ₹50 by UPI
## A buzz and a dot on the phone's corner when something new arrives; a ringing call slides it up by itself
## (Enter or Answer). Nothing on the phone is narration: it is what is on the phone.
const Prof := preload("res://scripts/drive/prof.gd")

signal photo_taken(tag: String)
signal recording_stopped(clip: Dictionary)
signal call_answered
signal opened_app(app: String)
signal rider_answer(accepted: bool)            # the delivery app: an order taken (or turned down)
signal otp_done                                # the delivery app: the customer's code typed in right
signal dialled(contact: Dictionary)            # a call he made (a contact tapped): it rings out, then they speak
signal nilam_done(ok: bool, form: Dictionary)  # a Tamil Nilam application paid for (ok: the land is where he said)

const W := 300.0
const H := 560.0
var APPS := ["notes", "messages", "contacts", "map", "camera", "recorder", "photos", "rider", "case"]
const APP_NAME := {"notes": ["Notes", "குறிப்பு"], "messages": ["Messages", "மெசேஜ்"], "contacts": ["Contacts", "தொடர்புகள்"],
	"map": ["Map", "மேப்"], "camera": ["Camera", "கேமரா"], "recorder": ["Recorder", "ரெக்கார்டர்"], "photos": ["Photos", "படங்கள்"],
	"rider": ["QuickBite", "குவிக்பைட்"], "nilam": ["Tamil Nilam", "தமிழ் நிலம்"], "case": ["The night", "அந்த ராத்திரி"]}
const APP_COL := {"notes": Color(0.95, 0.75, 0.2), "messages": Color(0.25, 0.7, 0.35), "contacts": Color(0.3, 0.55, 0.9),
	"map": Color(0.2, 0.65, 0.6), "camera": Color(0.35, 0.35, 0.4), "recorder": Color(0.85, 0.25, 0.25),
	"photos": Color(0.75, 0.4, 0.8), "rider": Color(0.9, 0.35, 0.1), "nilam": Color(0.1, 0.45, 0.3),
	"case": Color(0.55, 0.45, 0.3)}
const BG := Color(0.07, 0.08, 0.1)
const FG := Color(0.95, 0.95, 0.97)
const DIM := Color(0.6, 0.62, 0.68)

var lang := "en"
var city                                       # city_test.gd (the clock, the wallet, the walker's camera)
var is_open := false
var app := ""
var notes: Array = []                          # [{"text": {en, ta}, "done": bool}]
var statements: Array = []                     # what people told him (citizens.gd interviews): [{"who", "text", "how"}],
											   #  the newest first; under his notes, in his own words
var messages: Array = []                       # [{"from": {en, ta}, "text": {en, ta}, "time": "9:52 PM", "read": bool}]
var contacts: Array = []                       # [{"name": {en, ta}, "number": "98...", "where": {en, ta}}]
var pins: Array = []                           # [{"place": key, "label": {en, ta}}]
var photos: Array = []                         # [{"tex": Texture2D, "tag": "", "label": {en, ta}}] or recordings:
                                               #   [{"lines": [[who, text]...], "tag": "", "label": {en, ta}}]
var targets: Array = []                        # [{"node": Node3D, "tag": "", "label": {en, ta}, "reach": metres}]
var recording := false
var taken := false                             # handed over (at the station): P finds an empty pocket
var unread := 0
var ringing := {}                              # an incoming call: {"from": {en, ta}}
var calling := {}                              # a call going out: the contact, until it's picked up
var _call_t := 0.0
var rider := {}                                # the delivery app's screen: {"mode": offer | job | otp, "app", "lines", "code",
                                               #  "typed", "decline": label of the turn-down button}
var nilam := {}                                # the land-records form: taluk, village, survey numbers, the field typed in, its stage
const TALUKS := ["Coimbatore North", "Coimbatore South", "Perur", "Madukkarai", "Sulur", "Pollachi"]
const VILLAGES := {"Coimbatore North": ["Ganapathy", "Saravanampatti", "Thudiyalur"], "Coimbatore South": ["Ukkadam", "Selvapuram", "Kuniyamuthur"],
	"Perur": ["Perur", "Theethipalayam", "Pudhur Vayal", "Alandurai", "Madampatti"], "Madukkarai": ["Madukkarai", "Myleripalayam", "Chettipalayam"],
	"Sulur": ["Sulur", "Kannampalayam", "Irugur"], "Pollachi": ["Pollachi", "Kinathukadavu", "Zaminkaliyapuram"]}
var _rec: Array = []
var _rec_t := 0.0
var _view := -1                                # Photos / Messages: the one open (-1: the list)
var _slide := 0.0                              # 0 put away … 1 held up
var _t := 0.0
var _flash := 0.0
var _snap := false
var _p_down := false
var _buzz: AudioStreamPlayer
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buzz = AudioStreamPlayer.new()
	_buzz.stream = _tone([[180.0, 0.18], [0.0, 0.08], [180.0, 0.18]], 0.5, true)
	_buzz.volume_db = -8.0
	add_child(_buzz)
	for arg in OS.get_cmdline_user_args():            # (testing: --snapat=SECS,PATH a screenshot, then quit)
		if arg.begins_with("--snapat="):
			var v := arg.get_slice("=", 1).split(",")
			get_tree().create_timer(float(v[0])).timeout.connect(func():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg(v[1], 0.85)
				get_tree().quit())
	for arg in OS.get_cmdline_user_args():            # (testing: --phoneshow=APP holds it up at that app after a while)
		if arg.begins_with("--phoneshow="):
			get_tree().create_timer(12.0).timeout.connect(func():
				note({"en": "Drive Raghavan sir to the office in Gandhipuram, smoothly.", "ta": "ராகவன் சார ஆஃபீஸ் கூட்டிட்டு போங்க"})
				message({"en": "Divya", "ta": "திவ்யா"}, {"en": "Anna, fees on Friday. Don't forget!!", "ta": "அண்ணா, வெள்ளி ஃபீஸ்!!"})
				add_contact({"name": {"en": "Kathir (CCTV repair)", "ta": "கதிர்"}, "number": "98431 •••••", "where": {"en": "Saibaba Colony, 10 AM – 7 PM", "ta": "சாயிபாபா காலனி"}})
				hold(true)
				_open_app(arg.get_slice("=", 1) if arg.get_slice("=", 1) != "home" else ""))


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


# ---- what the story puts on it ----
func note(text, buzz := true) -> void:
	for n in notes:
		n["done"] = true
	notes.push_front({"text": text, "done": false})
	if buzz:
		_arrive()


func message(from, text, time := "") -> void:
	messages.push_front({"from": from, "text": text, "time": time if time != "" else _now(), "read": false})
	_arrive()


func add_contact(c: Dictionary) -> void:
	for k in contacts:                           # (once: Bala's number may be there already, from the bills)
		if c.has("id") and str(k.get("id", "")) == str(c["id"]):
			return
	contacts.append(c)
	_arrive()


func pin(place: String, label) -> void:
	pins.push_front({"place": place, "label": label})


## The delivery app: an order pings in and the phone comes up by itself (a rider looks at once); Accept or turn
## it down (rider_answer). A job: the order being done, on the app's screen. An OTP: the keypad for the customer's code.
func rider_offer(app, lines: Array, decline = null) -> void:
	rider = {"mode": "offer", "app": app, "lines": lines, "decline": decline if decline != null else {"en": "Decline", "ta": "வேண்டாம்"}}
	_ping()
	hold(true)
	_open_app("rider")


func rider_job(app, lines: Array) -> void:
	rider = {"mode": "job", "app": app, "lines": lines}


func rider_otp(app, lines: Array, code: String) -> void:
	rider = {"mode": "otp", "app": app, "lines": lines, "code": code, "typed": ""}
	hold(true)
	_open_app("rider")


func rider_clear() -> void:
	rider = {}
	if app == "rider":
		_open_app("")


func _ping() -> void:
	if _buzz and is_inside_tree() and not taken:
		_buzz.play()


func _rider_key(k: String) -> void:
	if str(rider.get("mode", "")) != "otp":
		return
	var t := str(rider["typed"])
	if k == "⌫":
		t = t.left(maxi(t.length() - 1, 0))
	elif t.length() < 4:
		t += k
	rider["typed"] = t
	if t.length() == 4:
		if t == str(rider["code"]):
			rider = {"mode": "job", "app": rider["app"], "lines": [{"en": "Delivered ✓", "ta": "டெலிவரி ஆச்சு ✓"}]}
			get_tree().create_timer(0.8).timeout.connect(func():
				hold(false)
				otp_done.emit())
		else:
			rider["typed"] = ""
			rider["wrong"] = 1.0


func _rider_keys() -> Array:
	var s := _screen()
	var out: Array = []
	var w := (s.size.x - 40.0) / 3.0
	var labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
	for i in 12:
		if labels[i] != "":
			out.append([Rect2(s.position.x + 12.0 + (i % 3) * (w + 8.0), s.position.y + 230.0 + floori(i / 3.0) * 54.0, w, 46.0), labels[i]])
	return out


func _rider_btn(i: int) -> Rect2:
	var s := _screen()
	return Rect2(s.position.x + 12.0 + i * (s.size.x * 0.5 - 6.0), s.end.y - 80.0, s.size.x * 0.5 - 18.0, 56.0)


## The land-records app on his phone, for an application: "want" is what the land really is ({taluk, village,
## from, to}); what he fills in decides whether it's found.
func enable_nilam(want: Dictionary) -> void:
	if not "nilam" in APPS:
		APPS.append("nilam")
	nilam = {"want": want, "taluk": 0, "village": 0, "from": "", "to": "", "field": "from", "stage": "form", "msg": ""}
	_ping()


func _nilam_villages() -> Array:
	return VILLAGES[TALUKS[int(nilam["taluk"])]]


func _nilam_key(k: String) -> void:
	if str(nilam.get("stage", "")) != "form":
		return
	var f := str(nilam["field"])
	var t := str(nilam[f])
	if k == "⌫":
		t = t.left(maxi(t.length() - 1, 0))
	elif t.length() < 3:
		t += k
	nilam[f] = t
	if f == "from" and t.length() == 3:
		nilam["field"] = "to"


## Its rows: [rect, what] for the form's taps (the taluk's and village's arrows, the two numbers, the keys, submit).
func _nilam_rects() -> Array:
	var s := _screen()
	var x0 := s.position.x + 10.0
	var w := s.size.x - 20.0
	var out: Array = []
	out.append([Rect2(x0, s.position.y + 112.0, 36.0, 34.0), "taluk-"])
	out.append([Rect2(x0 + w - 36.0, s.position.y + 112.0, 36.0, 34.0), "taluk+"])
	out.append([Rect2(x0, s.position.y + 168.0, 36.0, 34.0), "village-"])
	out.append([Rect2(x0 + w - 36.0, s.position.y + 168.0, 36.0, 34.0), "village+"])
	out.append([Rect2(x0, s.position.y + 226.0, w * 0.5 - 6.0, 34.0), "from"])
	out.append([Rect2(x0 + w * 0.5 + 6.0, s.position.y + 226.0, w * 0.5 - 6.0, 34.0), "to"])
	var kw := (w - 16.0) / 3.0
	var labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
	for i in 12:
		if labels[i] != "":
			out.append([Rect2(x0 + (i % 3) * (kw + 8.0), s.position.y + 272.0 + floori(i / 3.0) * 40.0, kw, 34.0), labels[i]])
	out.append([Rect2(x0, s.end.y - 50.0, w, 40.0), "submit"])
	return out


func _nilam_tap(what: String) -> void:
	match str(nilam.get("stage", "")):
		"form":
			match what:
				"taluk-", "taluk+":
					nilam["taluk"] = (int(nilam["taluk"]) + (1 if what == "taluk+" else -1) + TALUKS.size()) % TALUKS.size()
					nilam["village"] = 0
				"village-", "village+":
					var n := _nilam_villages().size()
					nilam["village"] = (int(nilam["village"]) + (1 if what == "village+" else -1) + n) % n
				"from", "to":
					nilam["field"] = what
				"submit":
					if str(nilam["from"]).length() < 3 or str(nilam["to"]).length() < 3:
						nilam["msg"] = L("Enter the survey numbers.", "சர்வே எண்கள போடுங்க.")
						return
					nilam["stage"] = "pay"
					nilam["msg"] = ""
				_:
					_nilam_key(what)
		"pay":
			if what == "submit":
				var want: Dictionary = nilam["want"]
				var ok: bool = TALUKS[int(nilam["taluk"])] == str(want["taluk"]) and _nilam_villages()[int(nilam["village"])] == str(want["village"]) \
					and str(nilam["from"]) == str(want["from"]) and str(nilam["to"]) == str(want["to"])
				if city and city.fines:
					city.fines.sim.money -= 50
				var form := {"taluk": TALUKS[int(nilam["taluk"])], "village": _nilam_villages()[int(nilam["village"])], "from": nilam["from"], "to": nilam["to"]}
				if ok:
					nilam["stage"] = "done"
					nilam["msg"] = L("Application no. TN-NLM-2026-0884213\nPatta extract: ready in 15 working days.\nYou will get an SMS.",
						"விண்ணப்ப எண் TN-NLM-2026-0884213\nபட்டா நகல்: 15 வேலை நாள்ல கிடைக்கும்.\nSMS வரும்.")
				else:
					nilam["stage"] = "form"
					nilam["msg"] = L("No records found for survey nos. %s–%s in %s village. (₹50 not refunded.)" % [form["from"], form["to"], form["village"]],
						"%s கிராமத்துல சர்வே எண் %s–%s பதிவு இல்ல. (₹50 திரும்ப வராது.)" % [form["village"], form["from"], form["to"]])
				nilam_done.emit(ok, form)


func call_from(from) -> void:
	ringing = {"from": from}
	_ring_sound(true)
	hold(true)


func target(node: Node3D, tag: String, label, reach := 6.0) -> void:
	targets.append({"node": node, "tag": tag, "label": label, "reach": reach})


func clear_targets() -> void:
	targets.clear()


## A spoken line, while the recorder runs.
func heard(who: String, text: String) -> void:
	if recording:
		_rec.append([who, text])


func has_photo(tag: String) -> bool:
	for p in photos:
		if str(p.get("tag", "")) == tag:
			return true
	return false


func _arrive() -> void:
	unread += 1
	if taken:
		return
	if _buzz and is_inside_tree():
		_buzz.play()


func _now() -> String:
	if city and city.fines:
		var m: float = city.fines.sim.minute
		var h := floori(m / 60.0) % 24
		return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, floori(fmod(m, 60.0)), "AM" if h < 12 else "PM"]
	return ""


# ---- holding it ----
func hold(up: bool) -> void:
	if up == is_open:
		return
	is_open = up
	if up:
		unread = 0
		_view = -1
		if ringing.is_empty() and app == "camera":
			app = ""
		mouse_filter = Control.MOUSE_FILTER_STOP
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if not ringing.is_empty():                 # (a call can't be put away: answer it)
			is_open = true
			return
		app = "" if app == "camera" else app
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if city and city.walker and city.walker.active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(dt: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_timed(dt)
	Prof.add("phone", _p0)


func _process_timed(dt: float) -> void:
	_t += dt
	_slide = move_toward(_slide, 1.0 if is_open else 0.0, dt * 5.0)
	_flash = maxf(_flash - dt * 3.0, 0.0)
	if rider.has("wrong"):
		rider["wrong"] = maxf(float(rider["wrong"]) - dt * 2.0, 0.0)
	if recording:
		_rec_t += dt
	if not calling.is_empty():                     # it rings at their end; then they pick up (the talk is theirs)
		_call_t -= dt
		if _call_t <= 0.0:
			var c := calling
			calling = {}
			hold(false)
			dialled.emit(c)
	var p := Input.is_key_pressed(KEY_P)
	if p and not _p_down and not _blocked() and not taken:
		if app == "camera" and is_open:
			_open_app("")
		else:
			hold(not is_open)
	_p_down = p
	queue_redraw()


func _blocked() -> bool:
	var st = city.story if city and "story" in city else null
	return st != null and st.tasks and st.tasks.visible


func _rect() -> Rect2:
	var vs := get_viewport_rect().size
	var y := lerpf(vs.y + 20.0, vs.y - H - 30.0, _ease(_slide))
	return Rect2(vs.x - W - 40.0, y, W, H)


func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _screen() -> Rect2:
	return _rect().grow_individual(-12.0, -42.0, -12.0, -40.0)


func _app_rect(i: int) -> Rect2:
	var s := _screen()
	var cw := (s.size.x - 30.0) / 3.0
	return Rect2(s.position.x + 15.0 + (i % 3) * cw + 8.0, s.position.y + 60.0 + floori(i / 3.0) * 110.0, cw - 16.0, cw - 16.0)


func _row(i: int, h := 64.0) -> Rect2:
	var s := _screen()
	return Rect2(s.position.x + 8.0, s.position.y + 56.0 + i * (h + 6.0), s.size.x - 16.0, h)


func _back_rect() -> Rect2:
	var r := _rect()
	return Rect2(r.get_center().x - 40.0, r.end.y - 34.0, 80.0, 26.0)


# ---- input ----
func _gui_input(e: InputEvent) -> void:
	if not is_open:
		return
	if app == "camera":
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_take_photo()
		accept_event()
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var q: Vector2 = e.position
	accept_event()
	if not ringing.is_empty():
		var s := _screen()
		if Rect2(s.position.x + 20.0, s.end.y - 90.0, s.size.x - 40.0, 60.0).has_point(q):
			answer()
		return
	if _back_rect().has_point(q):
		_back()
		return
	if not _rect().has_point(q):
		hold(false)
		return
	match app:
		"":
			for i in APPS.size():
				if _app_rect(i).has_point(q):
					_open_app(APPS[i])
		"messages":
			if _view < 0:
				for i in mini(messages.size(), 6):
					if _row(i).has_point(q):
						_view = i
						messages[i]["read"] = true
		"contacts":
			for i in mini(contacts.size(), 6):
				if _row(i, 70.0).has_point(q):
					calling = contacts[i]
					_call_t = 2.5
		"photos":
			if _view < 0:
				for i in mini(photos.size(), 8):
					if _thumb(i).has_point(q):
						_view = i
			else:
				_view = -1
		"recorder":
			var s := _screen()
			if Rect2(s.get_center() - Vector2(60, 60), Vector2(120, 120)).has_point(q):
				_toggle_rec()
		"nilam":
			for r in _nilam_rects():
				if (r[0] as Rect2).has_point(q):
					_nilam_tap(str(r[1]))
					break
		"rider":
			match str(rider.get("mode", "")):
				"offer":
					if _rider_btn(1).has_point(q):
						_rider_take(true)
					elif _rider_btn(0).has_point(q):
						_rider_take(false)
				"otp":
					for k in _rider_keys():
						if (k[0] as Rect2).has_point(q):
							_rider_key(str(k[1]))


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_open or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if not ringing.is_empty() and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_E):
		answer()
		get_viewport().set_input_as_handled()
	elif app == "rider" and str(rider.get("mode", "")) == "otp" and (e.keycode >= KEY_0 and e.keycode <= KEY_9 or e.keycode == KEY_BACKSPACE):
		_rider_key("⌫" if e.keycode == KEY_BACKSPACE else str(e.keycode - KEY_0))
		get_viewport().set_input_as_handled()
	elif app == "nilam" and str(nilam.get("stage", "")) == "form" and (e.keycode >= KEY_0 and e.keycode <= KEY_9 or e.keycode == KEY_BACKSPACE):
		_nilam_key("⌫" if e.keycode == KEY_BACKSPACE else str(e.keycode - KEY_0))
		get_viewport().set_input_as_handled()
	elif app == "nilam" and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER):
		_nilam_tap("submit")
		get_viewport().set_input_as_handled()
	elif app == "rider" and str(rider.get("mode", "")) == "offer" and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER):
		_rider_take(true)
		get_viewport().set_input_as_handled()
	elif e.keycode == KEY_ESCAPE or e.keycode == KEY_BACKSPACE:
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	if _view >= 0:
		_view = -1
	elif app != "":
		_open_app("")
	else:
		hold(false)


func _open_app(a: String) -> void:
	app = a
	_view = -1
	if a == "camera":
		mouse_filter = Control.MOUSE_FILTER_STOP
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # look around through it; the click is caught in _input
	elif is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened_app.emit(a)


func _input(e: InputEvent) -> void:
	if is_open and app == "camera" and e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_take_photo()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_open_app("")
		get_viewport().set_input_as_handled()


func _rider_take(yes: bool) -> void:
	if str(rider.get("mode", "")) != "offer":
		return
	if yes:
		rider["mode"] = "job"
		hold(false)
	rider_answer.emit(yes)


func answer() -> void:
	if ringing.is_empty():
		return
	ringing = {}
	_ring_sound(false)
	call_answered.emit()
	hold(false)


func _toggle_rec() -> void:
	recording = not recording
	if recording:
		_rec = []
		_rec_t = 0.0
		return
	var clip := {"lines": _rec.duplicate(), "secs": _rec_t, "tag": "", "label": {"en": "Recording %d" % (photos.size() + 1),
		"ta": "ரெக்கார்டிங் %d" % (photos.size() + 1)}}
	photos.push_front(clip)
	recording_stopped.emit(clip)


func _take_photo() -> void:
	if _snap:
		return
	_snap = true
	var cam := get_viewport().get_camera_3d()
	var tag := ""
	var label = {"en": "Photo", "ta": "படம்"}
	if cam:
		for tg in targets:
			var n: Node3D = tg["node"]
			if n == null or not is_instance_valid(n):
				continue
			var p := n.global_position
			var to := p - cam.global_position
			var ang := (-cam.global_basis.z).angle_to(to)
			if to.length() < float(tg["reach"]) and ang < deg_to_rad(16.0):
				tag = tg["tag"]
				label = tg["label"]
	visible = false                                    # (the photo is of the world, not of the viewfinder)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	visible = true
	img.resize(480, int(480.0 * img.get_height() / img.get_width()))
	photos.push_front({"tex": ImageTexture.create_from_image(img), "tag": tag, "label": label})
	_flash = 1.0
	_snap = false
	photo_taken.emit(tag)


# ---- drawing ----
func _text(pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, s, align, w, size, col)


func _wrap(pos: Vector2, s: String, size: int, col: Color, w: float, max_lines := 12) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, w, size, max_lines, col)
	var n := font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w, size, max_lines).y
	return n


func _draw() -> void:
	if app == "camera" and is_open:
		_draw_viewfinder()
		return
	if _slide <= 0.01:
		if unread > 0 and not taken:                   # the phone's corner in his pocket, lit: something new
			var vs := get_viewport_rect().size
			var c := Vector2(vs.x - 60.0, vs.y - 300.0)
			var k := 0.5 + 0.5 * sin(_t * 5.0)
			draw_rect(Rect2(c - Vector2(14, 24), Vector2(28, 48)), Color(0.08, 0.08, 0.1))
			draw_rect(Rect2(c - Vector2(11, 20), Vector2(22, 38)), Color(0.25, 0.45, 0.8, 0.6 + 0.4 * k))
			draw_circle(c + Vector2(13, -22), 7.0, Color(0.95, 0.3, 0.25))
		return
	var r := _rect()
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.04, 0.04, 0.05))
	var s := _screen()
	draw_rect(s, BG)
	_text(Vector2(s.position.x + 10.0, s.position.y + 22.0), _now(), 15, FG)
	if city and city.fines:
		_text(Vector2(s.position.x, s.position.y + 22.0), "₹%s" % _money(city.fines.sim.money), 15, FG, s.size.x - 10.0, HORIZONTAL_ALIGNMENT_RIGHT)
	if recording:
		draw_circle(Vector2(s.get_center().x, s.position.y + 16.0), 5.0, Color(0.95, 0.2, 0.2, 0.5 + 0.5 * sin(_t * 6.0)))
	draw_rect(_back_rect(), Color(0.2, 0.2, 0.23))
	if not ringing.is_empty():
		_draw_call(s)
		return
	if not calling.is_empty():
		draw_rect(s, Color(0.1, 0.13, 0.2))
		var cc := s.get_center() + Vector2(0, -80)
		draw_circle(cc, 46.0, Color(0.55, 0.57, 0.62))
		_text(Vector2(s.position.x, cc.y + 90.0), t_(calling["name"]), 22, FG, s.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(s.position.x, cc.y + 120.0), L("Calling…", "அழைக்கிறது…"), 15, DIM, s.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	match app:
		"":
			for i in APPS.size():
				var a: String = APPS[i]
				var ar := _app_rect(i)
				draw_rect(ar, APP_COL[a])
				_glyph(a, ar)
				_text(Vector2(ar.position.x - 8.0, ar.end.y + 18.0), L(APP_NAME[a][0], APP_NAME[a][1]), 13, FG, ar.size.x + 16.0, HORIZONTAL_ALIGNMENT_CENTER)
				if a == "messages" and _unread_msgs() > 0:
					draw_circle(ar.position + Vector2(ar.size.x, 0), 9.0, Color(0.95, 0.3, 0.25))
		"notes":
			_title(s, APP_NAME["notes"])
			var y := s.position.y + 70.0
			for n in notes.slice(0, 7 if statements.is_empty() else 3):
				var col := DIM if n["done"] else FG
				if not n["done"]:
					draw_rect(Rect2(s.position.x + 10.0, y - 14.0, 10, 10), APP_COL["notes"])
				y += _wrap(Vector2(s.position.x + 28.0, y), t_(n["text"]), 16, col, s.size.x - 40.0, 4) + 12.0
				if y > s.end.y - 30.0:
					break
			if not statements.is_empty() and y < s.end.y - 80.0:   # what people told him
				y += 6.0
				_text(Vector2(s.position.x + 12.0, y), L("What people said", "மக்கள் சொன்னது"), 14, APP_COL["notes"])
				y += 20.0
				for st in statements:
					y += _wrap(Vector2(s.position.x + 12.0, y), "%s: %s (%s)" % [t_(st["who"]), t_(st["text"]), t_(st["how"])],
						14, FG, s.size.x - 24.0, 4) + 10.0
					if y > s.end.y - 30.0:
						break
		"case":
			_title(s, APP_NAME["case"])
			_case(s)
		"messages":
			_title(s, APP_NAME["messages"])
			if _view >= 0 and _view < messages.size():
				var m: Dictionary = messages[_view]
				_text(Vector2(s.position.x + 12.0, s.position.y + 76.0), t_(m["from"]), 17, FG)
				var b := Rect2(s.position.x + 12.0, s.position.y + 92.0, s.size.x - 50.0, 10.0)
				var h := font.get_multiline_string_size(t_(m["text"]), HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 20.0, 16).y
				b.size.y = h + 26.0
				draw_rect(b, Color(0.2, 0.22, 0.26))
				_wrap(b.position + Vector2(10, 22), t_(m["text"]), 16, FG, b.size.x - 20.0)
				_text(Vector2(b.position.x, b.end.y + 16.0), str(m["time"]), 12, DIM)
			else:
				for i in mini(messages.size(), 6):
					var m: Dictionary = messages[i]
					var rr := _row(i)
					draw_rect(rr, Color(0.13, 0.14, 0.17))
					_text(rr.position + Vector2(10, 22), t_(m["from"]), 16, FG if not m["read"] else DIM)
					_text(rr.position + Vector2(10, 46), t_(m["text"]).left(30) + "…", 13, DIM)
		"contacts":
			_title(s, APP_NAME["contacts"])
			for i in mini(contacts.size(), 6):
				var c: Dictionary = contacts[i]
				var rr := _row(i, 70.0)
				draw_rect(rr, Color(0.13, 0.14, 0.17))
				_text(rr.position + Vector2(10, 22), t_(c["name"]), 16, FG)
				_text(rr.position + Vector2(10, 42), str(c.get("number", "")), 13, DIM)
				_text(rr.position + Vector2(10, 61), t_(c.get("where", "")), 12, DIM, rr.size.x - 20.0)
		"map":
			_title(s, APP_NAME["map"])
			for i in mini(pins.size(), 6):
				var rr := _row(i, 46.0)
				draw_rect(rr, Color(0.13, 0.14, 0.17))
				draw_circle(rr.position + Vector2(18, 23), 7.0, Color(0.95, 0.35, 0.25))
				_text(rr.position + Vector2(34, 28), t_(pins[i]["label"]), 15, FG, rr.size.x - 40.0)
		"recorder":
			_title(s, APP_NAME["recorder"])
			var c := s.get_center()
			draw_circle(c, 60.0, Color(0.2, 0.2, 0.23))
			if recording:
				draw_rect(Rect2(c - Vector2(22, 22), Vector2(44, 44)), Color(0.95, 0.25, 0.25))
				_text(Vector2(s.position.x, c.y + 100.0), "%d:%02d" % [floori(_rec_t / 60.0), floori(fmod(_rec_t, 60.0))], 26, FG, s.size.x, HORIZONTAL_ALIGNMENT_CENTER)
				for k in 24:                               # (the level, moving while anyone speaks)
					var hh := 6.0 + 26.0 * absf(sin(_t * 7.0 + k * 0.9)) * (1.0 if _rec.size() > 0 else 0.3)
					draw_rect(Rect2(s.position.x + 30.0 + k * 9.5, c.y + 150.0 - hh * 0.5, 5.0, hh), Color(0.95, 0.4, 0.4))
			else:
				draw_circle(c, 30.0, Color(0.95, 0.25, 0.25))
		"rider":
			_draw_rider(s)
		"nilam":
			_draw_nilam(s)
		"photos":
			_title(s, APP_NAME["photos"])
			if _view >= 0 and _view < photos.size():
				var p: Dictionary = photos[_view]
				if p.has("tex"):
					var tex: Texture2D = p["tex"]
					var w := s.size.x - 16.0
					draw_texture_rect(tex, Rect2(s.position.x + 8.0, s.position.y + 70.0, w, w * tex.get_height() / tex.get_width()), false)
				else:
					var y := s.position.y + 76.0
					for ln in p["lines"]:
						y += _wrap(Vector2(s.position.x + 12.0, y), "%s: %s" % ln, 14, FG, s.size.x - 24.0, 4) + 8.0
						if y > s.end.y - 30.0:
							break
			else:
				for i in mini(photos.size(), 8):
					var tr := _thumb(i)
					var p: Dictionary = photos[i]
					if p.has("tex"):
						draw_texture_rect(p["tex"], tr, false)
					else:
						draw_rect(tr, Color(0.25, 0.12, 0.12))
						draw_circle(tr.get_center(), 14.0, Color(0.95, 0.3, 0.3))
	if _flash > 0.0:
		draw_rect(s, Color(1, 1, 1, _flash))


func _draw_nilam(s: Rect2) -> void:
	draw_rect(s, Color(0.97, 0.97, 0.95))
	draw_rect(Rect2(s.position, Vector2(s.size.x, 52)), APP_COL["nilam"])
	_text(s.position + Vector2(12, 24), L("Tamil Nilam · e-Services", "தமிழ் நிலம் · இ-சேவைகள்"), 15, Color.WHITE)
	_text(s.position + Vector2(12, 43), L("Revenue Dept., Govt. of Tamil Nadu", "வருவாய் துறை, தமிழ்நாடு அரசு"), 11, Color(0.85, 0.95, 0.88))
	var ink := Color(0.1, 0.1, 0.12)
	var dim := Color(0.4, 0.42, 0.45)
	var x0 := s.position.x + 10.0
	var w := s.size.x - 20.0
	var stage := str(nilam.get("stage", ""))
	if stage == "":
		_text(Vector2(x0, s.position.y + 84.0), L("No application open.", "விண்ணப்பம் எதுவும் இல்ல."), 14, dim)
		return
	_text(Vector2(x0, s.position.y + 72.0), L("Patta extract: application", "பட்டா நகல்: விண்ணப்பம்"), 15, ink)
	_text(Vector2(x0, s.position.y + 92.0), L("District: Coimbatore", "மாவட்டம்: கோயம்புத்தூர்"), 13, dim)
	if stage == "done":
		_wrap(Vector2(x0, s.position.y + 130.0), str(nilam["msg"]), 15, Color(0.1, 0.45, 0.25), w, 8)
		return
	var vill: Array = _nilam_villages()
	for row in [[112.0, L("Taluk", "வட்டம்"), TALUKS[int(nilam["taluk"])]], [168.0, L("Village", "கிராமம்"), vill[int(nilam["village"])]]]:
		_text(Vector2(x0, s.position.y + row[0] - 4.0), row[1], 11, dim)
		draw_rect(Rect2(x0, s.position.y + row[0], w, 34.0), Color(0.9, 0.92, 0.9))
		_text(Vector2(x0, s.position.y + row[0] + 23.0), str(row[2]), 15, ink, w, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(x0 + 10.0, s.position.y + row[0] + 24.0), "‹", 22, APP_COL["nilam"])
		_text(Vector2(x0 + w - 22.0, s.position.y + row[0] + 24.0), "›", 22, APP_COL["nilam"])
	_text(Vector2(x0, s.position.y + 222.0), L("Survey no.   from            to", "சர்வே எண்   முதல்            வரை"), 11, dim)
	for f in ["from", "to"]:
		var r := Rect2(x0 + (0.0 if f == "from" else w * 0.5 + 6.0), s.position.y + 226.0, w * 0.5 - 6.0, 34.0)
		draw_rect(r, Color(0.9, 0.92, 0.9))
		if str(nilam["field"]) == f and stage == "form":
			draw_rect(r, APP_COL["nilam"], false, 2.0)
		_text(r.position + Vector2(0, 24), str(nilam[f]) + ("_" if str(nilam["field"]) == f and stage == "form" and fmod(_t, 1.0) < 0.5 else ""), 17, ink, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if stage == "pay":
		_text(Vector2(x0, s.position.y + 296.0), L("Fee: ₹50", "கட்டணம்: ₹50"), 17, ink)
		_wrap(Vector2(x0, s.position.y + 322.0), L("Pay by UPI from your account. Then the application is sent.", "உங்க கணக்குல இருந்து UPI-ல கட்டுங்க. அப்புறம் விண்ணப்பம் போகும்."), 13, dim, w, 4)
	else:
		for r in _nilam_rects():
			var k := str(r[1])
			if k.length() == 1 or k == "⌫":
				draw_rect(r[0], Color(0.86, 0.87, 0.88))
				_text((r[0] as Rect2).position + Vector2(0, 25), k, 17, ink, (r[0] as Rect2).size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if str(nilam.get("msg", "")) != "":
		_wrap(Vector2(x0, s.end.y - 92.0), str(nilam["msg"]), 12, Color(0.75, 0.15, 0.1), w, 3)
	var sb := Rect2(x0, s.end.y - 50.0, w, 40.0)
	draw_rect(sb, APP_COL["nilam"])
	_text(sb.position + Vector2(0, 27), L("Pay ₹50 by UPI", "UPI-ல ₹50 கட்டு") if stage == "pay" else L("Submit", "சமர்ப்பி"), 16, Color.WHITE, sb.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_rider(s: Rect2) -> void:
	draw_rect(s, Color(0.97, 0.96, 0.95))
	draw_rect(Rect2(s.position, Vector2(s.size.x, 52)), APP_COL["rider"])
	_text(s.position + Vector2(12, 34), t_(rider.get("app", {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"})), 18, Color.WHITE)
	var ink := Color(0.1, 0.1, 0.12)
	var mode := str(rider.get("mode", ""))
	var y := s.position.y + 84.0
	if mode == "":
		_text(Vector2(s.position.x + 12.0, y), L("No order now.", "இப்போ ஆர்டர் இல்ல."), 15, Color(0.4, 0.4, 0.45))
		return
	if mode == "offer":
		_text(Vector2(s.position.x + 12.0, y), L("New order nearby", "அருகில் புது ஆர்டர்"), 19, ink)
		y += 30.0
	for ln in rider.get("lines", []):
		y += _wrap(Vector2(s.position.x + 12.0, y), t_(ln), 14, ink, s.size.x - 24.0, 3) + 6.0
	match mode:
		"offer":
			var a := _rider_btn(0)
			var b := _rider_btn(1)
			draw_rect(a, Color(0.6, 0.6, 0.64))
			draw_rect(b, Color(0.2, 0.6, 0.3))
			_text(a.position + Vector2(0, 35), t_(rider["decline"]), 15, Color.WHITE, a.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_text(b.position + Vector2(0, 35), L("Accept", "ஏத்துக்கோ"), 17, Color.WHITE, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		"otp":
			_text(Vector2(s.position.x + 12.0, s.position.y + 196.0), L("Customer's OTP", "வாடிக்கையாளர் OTP"), 14, Color(0.4, 0.4, 0.45))
			var t := str(rider.get("typed", ""))
			var wrong := float(rider.get("wrong", 0.0))
			for i in 4:
				var bx := Rect2(s.position.x + 40.0 + i * 52.0 + sin(wrong * 30.0) * wrong * 6.0, s.position.y + 160.0 - 8.0, 40.0, 0.0)
				draw_line(Vector2(bx.position.x, bx.position.y + 30.0), Vector2(bx.end.x, bx.position.y + 30.0), Color(0.95, 0.3, 0.25) if wrong > 0.0 else ink, 2.0)
				if i < t.length():
					_text(Vector2(bx.position.x, bx.position.y + 24.0), t[i], 24, ink, 40.0, HORIZONTAL_ALIGNMENT_CENTER)
			for k in _rider_keys():
				draw_rect(k[0], Color(0.88, 0.88, 0.9))
				_text((k[0] as Rect2).position + Vector2(0, 31), str(k[1]), 20, ink, (k[0] as Rect2).size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _thumb(i: int) -> Rect2:
	var s := _screen()
	var w := (s.size.x - 24.0) / 2.0
	return Rect2(s.position.x + 8.0 + (i % 2) * (w + 8.0), s.position.y + 60.0 + floori(i / 2.0) * (w * 0.6 + 8.0), w, w * 0.6)


## The night of Day 3 as he has it, 9:30 to 11:15 PM down the screen: each piece of evidence he has at its time
## (story/knowledge.json "timeline"), each thing he's been told with a time (citizens.gd heard); of two accounts that
## don't fit each other, the weaker (heard, or less sure) in red. Only what he has: an empty night at first.
var _know := {}


func _case(s: Rect2) -> void:
	if _know.is_empty():
		_know = JSON.parse_string(FileAccess.get_file_as_string("res://story/knowledge.json"))
	var t0 := 21.5 * 60.0
	var t1 := 23.25 * 60.0
	var top := s.position.y + 74.0
	var bot := s.end.y - 24.0
	var x := s.position.x + 58.0
	var ym := func(hm: String) -> float:
		var p := hm.split(":")
		return top + (float(p[0]) * 60.0 + float(p[1]) - t0) / (t1 - t0) * (bot - top)
	draw_line(Vector2(x, top), Vector2(x, bot), DIM, 2.0)
	for q in range(0, 8):                                # (a mark each quarter of an hour)
		var m := t0 + q * 15.0
		var yy: float = top + (m - t0) / (t1 - t0) * (bot - top)
		draw_line(Vector2(x - 5, yy), Vector2(x + 5, yy), DIM, 1.0)
		_text(Vector2(s.position.x + 8.0, yy + 4.0), "%d:%02d" % [int(m / 60.0) - 12, int(m) % 60], 11, DIM)
	var rows: Array = []
	var ev: Dictionary = city.story.evidence if city and city.story and city.story.get("evidence") is Dictionary else {}
	for e in _know.get("timeline", []):
		if ev.has(str(e["tag"])):
			rows.append([str(e["at"]), "%s  %s" % [e["tag"], t_(e)], Color(0.95, 0.8, 0.35)])
	var heard: Array = city.citizens.heard if city and city.get("citizens") else []
	for r in _know.get("records", []):
		if r.has("at") and str(r["id"]) in heard:
			var bad := false                             # (of two that don't fit, the weaker: heard, or less sure)
			for r2 in _know.get("records", []):
				var pair: bool = (str(r.get("contradicts", "")) == str(r2["id"]) or str(r2.get("contradicts", "")) == str(r["id"]))
				if pair and str(r2["id"]) in heard and float(r.get("confidence", 0.5)) + (0.3 if r.get("firsthand", false) else 0.0) \
						< float(r2.get("confidence", 0.5)) + (0.3 if r2.get("firsthand", false) else 0.0):
					bad = true
			var who := str(r["who"])
			var nm := who.capitalize()
			if city and city.get("citizens"):
				var pp: Dictionary = city.citizens._person(who)
				nm = t_(pp.get("name", {"en": nm}))
			rows.append([str(r["at"]), "%s%s: %s" % [L("(doesn't fit) ", "(பொருந்தவில்லை) ") if bad else "", nm, t_(r["text"])],
				Color(0.95, 0.4, 0.35) if bad else FG])
	rows.sort_custom(func(a, b): return str(a[0]) < str(b[0]))
	if rows.is_empty():
		_wrap(Vector2(x + 14.0, top + 20.0), L("Nothing yet. What do I know of that night?", "இன்னும் ஒண்ணுமில்ல. அந்த ராத்திரி பத்தி எனக்கு என்ன தெரியும்?"), 14, DIM, s.size.x - 80.0, 3)
		return
	var last := -1e9
	for row in rows:
		var yy: float = ym.call(row[0])
		draw_circle(Vector2(x, yy), 4.0, row[2])
		var ty := maxf(yy + 4.0, last + 6.0)
		draw_line(Vector2(x + 4.0, yy), Vector2(x + 12.0, ty - 4.0), Color(row[2], 0.6), 1.0)
		var h := _wrap(Vector2(x + 14.0, ty), row[1], 12, row[2], s.end.x - x - 22.0, 3)
		last = ty + h


func _title(s: Rect2, n: Array) -> void:
	_text(Vector2(s.position.x + 12.0, s.position.y + 48.0), L(n[0], n[1]), 20, FG)


func _unread_msgs() -> int:
	var n := 0
	for m in messages:
		if not m["read"]:
			n += 1
	return n


func _money(v: int) -> String:
	var s := str(absi(v))
	if s.length() > 3:                                 # Indian grouping: 1,23,456
		var head := s.left(s.length() - 3)
		var parts: Array = []
		while head.length() > 2:
			parts.push_front(head.right(2))
			head = head.left(head.length() - 2)
		if head != "":
			parts.push_front(head)
		s = ",".join(parts) + "," + s.right(3)
	return ("-" if v < 0 else "") + s


func _draw_call(s: Rect2) -> void:
	draw_rect(s, Color(0.1, 0.13, 0.2))
	var c := s.get_center() + Vector2(0, -80)
	var k := 0.5 + 0.5 * sin(_t * 6.0)
	draw_circle(c, 56.0 + k * 10.0, Color(0.3, 0.65, 0.4, 0.25 + 0.3 * k))
	draw_circle(c, 46.0, Color(0.55, 0.57, 0.62))
	_text(Vector2(s.position.x, c.y + 90.0), t_(ringing["from"]), 22, FG, s.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var b := Rect2(s.position.x + 20.0, s.end.y - 90.0, s.size.x - 40.0, 60.0)
	draw_rect(b, Color(0.2, 0.65, 0.35))
	_text(b.position + Vector2(0, 38), L("Answer", "எடு"), 20, Color.WHITE, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_viewfinder() -> void:
	var vs := get_viewport_rect().size
	var c := vs * 0.5
	var col := Color(1, 1, 1, 0.85)
	for sx in [-1, 1]:                                 # the corners of the frame and the focus square
		for sy in [-1, 1]:
			var p := c + Vector2(sx * vs.x * 0.3, sy * vs.y * 0.3)
			draw_line(p, p - Vector2(sx * 40.0, 0), col, 3.0)
			draw_line(p, p - Vector2(0, sy * 40.0), col, 3.0)
	draw_rect(Rect2(c - Vector2(40, 40), Vector2(80, 80)), Color(1, 0.85, 0.3, 0.8), false, 2.0)
	draw_circle(Vector2(c.x, vs.y - 70.0), 26.0, Color(1, 1, 1, 0.9))
	draw_circle(Vector2(c.x, vs.y - 70.0), 21.0, Color(0.85, 0.85, 0.88))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, _flash))


func _glyph(a: String, r: Rect2) -> void:
	var c := r.get_center()
	var w := Color(1, 1, 1, 0.92)
	match a:
		"nilam":                                         # a field's boundary stones on a plot
			draw_rect(Rect2(c - Vector2(16, 12), Vector2(32, 24)), w, false, 2.0)
			draw_line(c + Vector2(-16, 0), c + Vector2(16, 0), w, 1.5)
			draw_line(c + Vector2(0, -12), c + Vector2(0, 12), w, 1.5)
		"notes":
			for k in 3:
				draw_line(c + Vector2(-16, -10 + k * 10), c + Vector2(16, -10 + k * 10), w, 3.0)
		"case":
			draw_line(c + Vector2(-8, -16), c + Vector2(-8, 16), w, 2.0)
			for k in 3:
				draw_circle(c + Vector2(-8, -10 + k * 10), 3.0, w)
				draw_line(c + Vector2(-2, -10 + k * 10), c + Vector2(14, -10 + k * 10), w, 2.0)
		"messages":
			draw_rect(Rect2(c - Vector2(18, 13), Vector2(36, 24)), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 11), c + Vector2(4, 11), c + Vector2(-10, 20)]), w)
		"contacts":
			draw_circle(c + Vector2(0, -7), 8.0, w)
			draw_rect(Rect2(c + Vector2(-13, 4), Vector2(26, 12)), w)
		"map":
			draw_circle(c + Vector2(0, -5), 10.0, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -1), c + Vector2(9, -1), c + Vector2(0, 16)]), w)
			draw_circle(c + Vector2(0, -5), 4.0, APP_COL["map"])
		"camera":
			draw_rect(Rect2(c - Vector2(18, 11), Vector2(36, 24)), w)
			draw_circle(c + Vector2(0, 1), 8.0, APP_COL["camera"])
		"recorder":
			draw_circle(c, 12.0, w)
		"photos":
			draw_rect(Rect2(c - Vector2(16, 12), Vector2(32, 24)), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 10), c + Vector2(-2, -4), c + Vector2(10, 10)]), APP_COL["photos"])


# ---- sounds ----
func _ring_sound(on: bool) -> void:
	if on:
		_buzz.stream = _tone([[440.0, 0.4], [480.0, 0.4], [0.0, 1.2]], 0.35, false)
		(_buzz.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(_buzz.stream as AudioStreamWAV).loop_end = int(2.0 * 22050)
		_buzz.play()
	else:
		_buzz.stop()
		_buzz.stream = _tone([[180.0, 0.18], [0.0, 0.08], [180.0, 0.18]], 0.5, true)


## A short sound from steps of [frequency, seconds] (0: silence); "rough" makes it a vibration's buzz.
static func _tone(steps: Array, amp: float, rough: bool) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var ph := 0.0
	for st in steps:
		var n := int(float(st[1]) * rate)
		for i in n:
			var v := 0.0
			if float(st[0]) > 0.0:
				ph += float(st[0]) / rate
				v = sin(TAU * ph) if not rough else signf(sin(TAU * ph)) * 0.6 + sin(TAU * ph * 2.0) * 0.3
				var edge := minf(1.0, minf(i, n - i) / 200.0)
				v *= amp * edge
			var s := clampi(int(v * 32767.0), -32768, 32767)
			data.append(s & 0xff)
			data.append((s >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
