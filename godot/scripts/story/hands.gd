extends Control
## Things in Karthik's hands (GAME_DESIGN.md §8: evidence is a thing). Something he's given or picks up (the
## warrant, a copy of the FIR, a folded note, the cheque, a printed photo) comes up in front of him to read; the
## mouse tilts it, the wheel brings it closer, E (or Enter, or a click outside it) puts it in his pocket. I opens the
## pocket: what he carries, along the bottom; click one to take it out again.
## His hands are his: the more stressed he is, the more the paper shakes (life.gd's stress).
const Prof := preload("res://scripts/drive/prof.gd")

signal put_away(id: String)
signal note_given(amount: int)              # the wallet: a note taken out and held out to someone

const PAPER := Color(0.96, 0.95, 0.9)
const NOTE := Color(0.98, 0.93, 0.62)
const CHEQUE := Color(0.82, 0.9, 0.88)
const INK := Color(0.1, 0.1, 0.14)
const BLUE := Color(0.1, 0.18, 0.55)

var lang := "en"
var city                                    # city_test.gd (life.gd's stress for the hands)
var items: Array = []                       # the pocket: [{"id", "kind": paper | note | cheque | photo, "title", "body",
                                            #   "from", "stamp", "tex"}]
var held := {}
var pocket_open := false
var _zoom := 1.0
var _tilt := Vector2.ZERO
var _t := 0.0
var _rise := 0.0
var _i_down := false
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if "--handsshow" in OS.get_cmdline_user_args():     # (testing: the warrant in his hands after a while)
		get_tree().create_timer(12.0).timeout.connect(func(): give({"id": "warrant", "kind": "paper", "stamp": true,
			"from": {"en": "Nagar Police Station, Coimbatore City", "ta": "நகர் காவல் நிலையம்"},
			"title": {"en": "Warrant of Arrest", "ta": "கைது வாரண்ட்"},
			"body": {"en": "To: Karthik M., son of Muthu, Ganapathy.\n\nYou are required to accompany the officers to the station in connection with Crime No. 412 of this year, the death of Shri R. Raghavan.\n\nInspector of Police (L&O)", "ta": "கார்த்திக் ம."}}))


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func has(id: String) -> bool:
	return _find(id) >= 0


func _find(id: String) -> int:
	for i in items.size():
		if str(items[i]["id"]) == id:
			return i
	return -1


## Into his hands (and his pocket, after).
func give(item: Dictionary) -> void:
	var i := _find(str(item["id"]))
	if i < 0:
		items.append(item)
	else:
		items[i] = item
	hold(str(item["id"]))


func take(id: String) -> void:
	var i := _find(id)
	if i >= 0:
		items.remove_at(i)
	if str(held.get("id", "")) == id:
		held = {}
		_refresh_mouse()


func hold(id: String) -> void:
	var i := _find(id)
	if i < 0:
		return
	held = items[i]
	pocket_open = false
	_zoom = 1.0
	_rise = 0.0
	_refresh_mouse()


func put_back() -> void:
	if held.is_empty():
		return
	var id := str(held["id"])
	held = {}
	_refresh_mouse()
	put_away.emit(id)


func is_busy() -> bool:
	return not held.is_empty() or pocket_open


func _refresh_mouse() -> void:
	if is_busy():
		mouse_filter = Control.MOUSE_FILTER_STOP
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if city and city.walker and city.walker.active and not (city.phone and city.phone.is_open):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(dt: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_timed(dt)
	Prof.add("hands", _p0)


func _process_timed(dt: float) -> void:
	_t += dt
	_rise = move_toward(_rise, 1.0, dt * 4.0)
	var ik := Input.is_key_pressed(KEY_I)
	if ik and not _i_down and held.is_empty() and not _tasks_open():
		pocket_open = not pocket_open and not items.is_empty()
		_refresh_mouse()
	_i_down = ik
	var vs := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	_tilt = _tilt.lerp(((m - vs * 0.5) / vs).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), dt * 4.0)
	queue_redraw()


func _tasks_open() -> bool:
	var st = city.story if city and "story" in city else null
	return st != null and st.tasks and st.tasks.visible


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom + 0.1, 1.6)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom - 0.1, 0.7)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if str(held.get("kind", "")) == "wallet":     # a note out of the wallet, held out
				for n in _notes():
					if (n[1] as Rect2).has_point(e.position):
						var amount: int = n[0]
						put_back()
						note_given.emit(amount)
						accept_event()
						return
			if pocket_open:
				for i in items.size():
					if _slot(i).has_point(e.position):
						hold(str(items[i]["id"]))
						accept_event()
						return
				pocket_open = false
				_refresh_mouse()
			elif not held.is_empty() and not _sheet().has_point(e.position):
				put_back()
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if not held.is_empty() and e.keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		put_back()
		get_viewport().set_input_as_handled()
	elif pocket_open and e.keycode == KEY_ESCAPE:
		pocket_open = false
		_refresh_mouse()
		get_viewport().set_input_as_handled()


# ---- drawing ----
func _shake() -> Vector2:
	var s := 0.0
	if city and city.life:
		s = clampf((float(city.life.stress) - 55.0) / 45.0, 0.0, 1.0)
	return Vector2(sin(_t * 23.0) + sin(_t * 37.0) * 0.5, cos(_t * 29.0) + sin(_t * 17.0) * 0.5) * s * 4.0 \
		+ Vector2(sin(_t * 1.3), sin(_t * 1.7)) * 2.0       # (and everyone's hands breathe a little)


func _sheet() -> Rect2:
	var vs := get_viewport_rect().size
	var k := str(held.get("kind", "paper"))
	var base := {"paper": Vector2(560, 760), "note": Vector2(380, 300), "cheque": Vector2(820, 360), "wallet": Vector2(900, 420),
		"photo": Vector2(720, 480)}.get(k, Vector2(560, 760)) as Vector2
	var sc := minf(1.0, (vs.y - 120.0) / base.y) * _zoom
	var size := base * sc
	var c := vs * 0.5 + Vector2(0, (1.0 - _ease(_rise)) * vs.y * 0.6) + _shake() + _tilt * 40.0
	return Rect2(c - size * 0.5, size)


func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _slot(i: int) -> Rect2:
	var vs := get_viewport_rect().size
	var w := 150.0
	var x0 := vs.x * 0.5 - items.size() * (w + 14.0) * 0.5
	return Rect2(x0 + i * (w + 14.0), vs.y - 170.0, w, 120.0)


func _draw() -> void:
	if pocket_open:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(0, vs.y - 200.0, vs.x, 200.0), Color(0, 0, 0, 0.45))
		for i in items.size():
			var r := _slot(i)
			var it: Dictionary = items[i]
			draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.4))
			draw_rect(r, _paper_col(str(it.get("kind", "paper"))))
			if it.has("tex"):
				draw_texture_rect(it["tex"], r.grow(-6.0), false)
			else:
				_lines(r.grow(-14.0), 6, Color(0, 0, 0, 0.18))
			draw_string(font, Vector2(r.position.x, r.end.y + 20.0), t_(it.get("title", "")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color.WHITE)
	if held.is_empty():
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.35 * _rise))
	var r := _sheet()
	var k := str(held.get("kind", "paper"))
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, _paper_col(k))
	var sc: float = r.size.x / {"paper": 560.0, "note": 380.0, "cheque": 820.0, "photo": 720.0, "wallet": 900.0}.get(k, 560.0)
	match k:
		"photo":
			if held.has("tex"):
				draw_texture_rect(held["tex"], r.grow(-14.0 * sc), false)
		"wallet":                                      # open, the notes standing up in it: pick one
			draw_rect(r, Color(0.28, 0.17, 0.1))
			draw_rect(r.grow(-10.0 * sc), Color(0.35, 0.22, 0.13))
			for n in _notes():
				var nr: Rect2 = n[1]
				draw_rect(Rect2(nr.position + Vector2(3, 4), nr.size), Color(0, 0, 0, 0.3))
				draw_rect(nr, NOTE_COL.get(n[0], Color(0.8, 0.8, 0.7)))
				draw_string(font, nr.position + Vector2(10, nr.size.y * 0.6), "₹%d" % n[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * sc), Color(0.15, 0.12, 0.1))
			if _notes().is_empty():
				draw_string(font, r.get_center() + Vector2(-80, 0), L("Empty.", "காலி."), HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * sc), Color(1, 1, 1, 0.7))
		"note":                                        # a scrap torn from a pad, folded twice, written in a hurry
			draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), Color(0, 0, 0, 0.08), 2.0)
			draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color(0, 0, 0, 0.06), 2.0)
			draw_multiline_string(font, r.position + Vector2(34, 80) * sc, t_(held.get("body", "")), HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x - 68.0 * sc, int(30 * sc), 8, BLUE)
		"cheque":
			draw_string(font, r.position + Vector2(30, 50) * sc, t_(held.get("from", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * sc), Color(0.05, 0.3, 0.3))
			draw_multiline_string(font, r.position + Vector2(30, 120) * sc, t_(held.get("body", "")), HORIZONTAL_ALIGNMENT_LEFT,
				r.size.x - 60.0 * sc, int(22 * sc), 8, INK)
			draw_line(r.position + Vector2(520, 300) * sc, r.position + Vector2(780, 300) * sc, INK, 1.5)
		_:
			var y: float = r.position.y + 60.0 * sc
			if held.has("from"):
				draw_string(font, Vector2(r.position.x, y), t_(held["from"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(17 * sc), INK)
				y += 30.0 * sc
			draw_string(font, Vector2(r.position.x, y + 10.0 * sc), t_(held.get("title", "")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(26 * sc), INK)
			draw_line(Vector2(r.position.x + 40.0 * sc, y + 26.0 * sc), Vector2(r.end.x - 40.0 * sc, y + 26.0 * sc), INK, 1.5)
			draw_multiline_string(font, Vector2(r.position.x + 44.0 * sc, y + 70.0 * sc), t_(held.get("body", "")),
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 88.0 * sc, int(18 * sc), 30, Color.html(str(held["ink"])) if held.has("ink") else INK)   # (his green ink)
			if held.get("stamp", false):                # the station's round seal, in violet ink, a little crooked
				var c := Vector2(r.end.x - 120.0 * sc, r.end.y - 120.0 * sc)
				draw_arc(c, 62.0 * sc, 0, TAU, 48, Color(0.45, 0.2, 0.6, 0.75), 4.0 * sc)
				draw_arc(c, 46.0 * sc, 0, TAU, 48, Color(0.45, 0.2, 0.6, 0.6), 2.0 * sc)
				draw_string(font, c + Vector2(-60, 6) * sc, L("POLICE", "காவல்"), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * sc, int(16 * sc), Color(0.45, 0.2, 0.6, 0.8))


const NOTE_COL := {500: Color(0.72, 0.7, 0.62), 200: Color(0.95, 0.75, 0.35), 100: Color(0.72, 0.68, 0.85),
	50: Color(0.6, 0.85, 0.85), 20: Color(0.78, 0.85, 0.55), 10: Color(0.8, 0.65, 0.5)}


## The wallet's notes: [amount, rect], what's in it now (the wallet's money, as notes a man carries).
func _notes() -> Array:
	var money := 0
	if city and city.fines:
		money = mini(int(city.fines.sim.money), 2000)          # (the rest is in the bank)
	var out: Array = []
	var r := _sheet()
	var i := 0
	for v in [500, 200, 100, 50, 20, 10]:
		if money >= v:
			var w := r.size.x * 0.13
			out.append([v, Rect2(r.position.x + r.size.x * 0.06 + i * (w + r.size.x * 0.025), r.position.y + r.size.y * 0.2, w, r.size.y * 0.6)])
			money -= v
			i += 1
	return out


func _paper_col(k: String) -> Color:
	return {"note": NOTE, "cheque": CHEQUE, "photo": Color(0.97, 0.97, 0.97)}.get(k, PAPER)


func _lines(r: Rect2, n: int, col: Color) -> void:
	for i in n:
		var y := r.position.y + (i + 0.5) * r.size.y / n
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x - (30.0 if i == n - 1 else 0.0), y), col, 2.0)
