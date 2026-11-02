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
## A buzz and a dot on the phone's corner when something new arrives; a ringing call slides it up by itself
## (Enter or Answer). Nothing on the phone is narration: it is what is on the phone.

signal photo_taken(tag: String)
signal recording_stopped(clip: Dictionary)
signal call_answered
signal opened_app(app: String)

const W := 300.0
const H := 560.0
const APPS := ["notes", "messages", "contacts", "map", "camera", "recorder", "photos"]
const APP_NAME := {"notes": ["Notes", "குறிப்பு"], "messages": ["Messages", "மெசேஜ்"], "contacts": ["Contacts", "தொடர்புகள்"],
	"map": ["Map", "மேப்"], "camera": ["Camera", "கேமரா"], "recorder": ["Recorder", "ரெக்கார்டர்"], "photos": ["Photos", "படங்கள்"]}
const APP_COL := {"notes": Color(0.95, 0.75, 0.2), "messages": Color(0.25, 0.7, 0.35), "contacts": Color(0.3, 0.55, 0.9),
	"map": Color(0.2, 0.65, 0.6), "camera": Color(0.35, 0.35, 0.4), "recorder": Color(0.85, 0.25, 0.25),
	"photos": Color(0.75, 0.4, 0.8)}
const BG := Color(0.07, 0.08, 0.1)
const FG := Color(0.95, 0.95, 0.97)
const DIM := Color(0.6, 0.62, 0.68)

var lang := "en"
var city                                       # city_test.gd (the clock, the wallet, the walker's camera)
var is_open := false
var app := ""
var notes: Array = []                          # [{"text": {en, ta}, "done": bool}]
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
	contacts.append(c)
	_arrive()


func pin(place: String, label) -> void:
	pins.push_front({"place": place, "label": label})


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
	_t += dt
	_slide = move_toward(_slide, 1.0 if is_open else 0.0, dt * 5.0)
	_flash = maxf(_flash - dt * 3.0, 0.0)
	if recording:
		_rec_t += dt
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


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_open or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if not ringing.is_empty() and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_E):
		answer()
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
		if unread > 0:                                 # the phone's corner in his pocket, lit: something new
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
			for n in notes.slice(0, 7):
				var col := DIM if n["done"] else FG
				if not n["done"]:
					draw_rect(Rect2(s.position.x + 10.0, y - 14.0, 10, 10), APP_COL["notes"])
				y += _wrap(Vector2(s.position.x + 28.0, y), t_(n["text"]), 16, col, s.size.x - 40.0, 4) + 12.0
				if y > s.end.y - 30.0:
					break
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


func _thumb(i: int) -> Rect2:
	var s := _screen()
	var w := (s.size.x - 24.0) / 2.0
	return Rect2(s.position.x + 8.0 + (i % 2) * (w + 8.0), s.position.y + 60.0 + floori(i / 2.0) * (w * 0.6 + 8.0), w, w * 0.6)


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
		"notes":
			for k in 3:
				draw_line(c + Vector2(-16, -10 + k * 10), c + Vector2(16, -10 + k * 10), w, 3.0)
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
