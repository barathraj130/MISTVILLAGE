extends Control
## Hands-on story tasks shown as pictures (drawn here, no image files): the player does the thing instead of
## reading about it. One task at a time; `finished(result)` when it's done.
##   sign   a document (bank slip, police register) with a box you sign in with the mouse
##   count  cash bundles on a counter: click each to count it, then say whether the total is right
##   hang   drag a thing (a key, a phone) onto the right place (a hook in a key box, a charger)
##   otp    a delivery app on the phone: type the customer's OTP on the keypad
##   phone  the phone in your hand: "offer" a job notification to accept, or "call" an incoming call to answer
##   ready  getting ready in the morning, chore by chore (alarm, brush, bath, dress, breakfast, pockets), each a
##          small hands-on picture; every chore costs game minutes (result "minutes"), the shirt and whether you
##          reached for the cap are remembered
## Every task can carry a tip (advice from the owner, a boss, a hotel owner) shown above it.

signal finished(result: Dictionary)
signal stage_changed                            # (getting ready: the next chore is up)

const PAPER := Color(0.97, 0.94, 0.86)
const INK := Color(0.08, 0.15, 0.55)
const DARK := Color(0.12, 0.12, 0.14)
const NOTE := Color(0.62, 0.55, 0.42)          # the ₹500 note's stone grey-brown
const GOOD := Color(0.2, 0.65, 0.3)
const BAD := Color(0.8, 0.2, 0.15)

var kind := ""
var spec := {}
var lang := "en"
var skip := false                               # (testing) do the task by itself
var font: Font
var _t := 0.0
var _msg := ""
var _msg_col := DARK
var _msg_t := 0.0

# sign
var strokes: Array = []                         # Array of PackedVector2Array (box-local)
var _ink := 0.0
var _drawing := false
# count
var bundles: Array = []                         # [{"n": notes, "counted": float progress 0..1 or -1}]
var _counting := -1
# hang
var _drag := false
var _thing := Vector2.ZERO
var _home := Vector2.ZERO
# ready
const CHORES := ["alarm", "brush", "bath", "dress", "eat", "pocket"]
const CHORE_MIN := {"alarm": 0, "brush": 5, "bath": 12, "dress": 6, "eat": 12, "pocket": 3}
var chore := 0
var minutes := 0
var _prog := 0.0                                # this chore's progress 0..1
var _last_x := 0.0
var _scrub := false
var _picked := {}                               # dress: shirt; pocket: items in; eat: idlis eaten
var shirt := ""
var reached_cap := false
var _pocket_items := ["wallet", "phone", "scooter key", "house key"]
var _drag_item := ""
# otp
var _code := ""
var _keys: Array = []                           # [Rect2, label]


func start(k: String, s: Dictionary, language: String, testing := false) -> void:
	kind = k
	spec = s
	lang = language
	skip = testing
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	strokes.clear()
	_ink = 0.0
	_code = ""
	_t = 0.0
	_msg = ""
	_answered = false
	if kind == "ready":
		chore = 0
		minutes = 0
		_prog = 0.0
		_picked = {}
		shirt = ""
		reached_cap = false
	if kind == "count":
		bundles.clear()
		var short_i := int(spec.get("short", -1))
		for i in int(spec.get("bundles", 8)):
			bundles.append({"n": 99 if i == short_i else 100, "counted": -1.0})
	visible = true
	queue_redraw()


func t_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


# ---- layout ----
func _panel() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(980.0, vs.x - 80.0)
	var h := minf(600.0, vs.y - 120.0)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5 + 20.0, w, h)


func _sign_box() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + p.size.x * 0.52, p.position.y + p.size.y * 0.62, p.size.x * 0.4, p.size.y * 0.2)


func _bundle_rect(i: int) -> Rect2:
	var p := _panel()
	var col := i % 4
	var row := i / 4
	var w := p.size.x * 0.19
	var h := p.size.y * 0.19
	return Rect2(p.position.x + p.size.x * 0.08 + col * (w + p.size.x * 0.03), p.position.y + p.size.y * 0.17 + row * (h + 56.0), w, h)


func _button(i: int, n: int) -> Rect2:
	var p := _panel()
	var w := 300.0
	var gap := 24.0
	var x0 := p.position.x + (p.size.x - (w * n + gap * (n - 1))) * 0.5
	return Rect2(x0 + i * (w + gap), p.end.y - 70.0, w, 48.0)


func _targets() -> Array:
	var p := _panel()
	var out := []
	var ts: Array = spec.get("targets", [])
	for i in ts.size():
		var x := p.position.x + p.size.x * (0.18 + 0.64 * (float(i) / maxf(ts.size() - 1, 1)))
		out.append(Rect2(x - 55.0, p.position.y + p.size.y * 0.25, 110.0, 150.0))
	return out


func _phone() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + p.size.x * 0.5 - 170.0, p.position.y + 10.0, 340.0, p.size.y - 20.0)


# ---- input ----
func _gui_input(e: InputEvent) -> void:
	match kind:
		"sign":
			var box := _sign_box()
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed and box.has_point(e.position):
					_drawing = true
					strokes.append(PackedVector2Array([e.position - box.position]))
				elif not e.pressed:
					_drawing = false
					if _ink > 120.0 and _button(1, 2).has_point(e.position):
						_done({"signed": true, "strokes": strokes.size()})
					elif _button(0, 2).has_point(e.position):
						strokes.clear()
						_ink = 0.0
			elif e is InputEventMouseMotion and _drawing and box.has_point(e.position):
				var s: PackedVector2Array = strokes[-1]
				var q: Vector2 = e.position - box.position
				_ink += q.distance_to(s[-1])
				s.append(q)
				strokes[-1] = s
			queue_redraw()
		"count":
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				for i in bundles.size():
					if _bundle_rect(i).has_point(e.position) and bundles[i]["counted"] < 0.0 and _counting < 0:
						_counting = i
						bundles[i]["counted"] = 0.0
				if _button(0, 2).has_point(e.position):
					_answer(false)
				elif _button(1, 2).has_point(e.position):
					_answer(true)
		"hang":
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed and Rect2(_thing - Vector2(50, 50), Vector2(100, 100)).has_point(e.position):
					_drag = true
				elif not e.pressed and _drag:
					_drag = false
					_drop()
			elif e is InputEventMouseMotion and _drag:
				_thing = e.position
				queue_redraw()
		"ready":
			_ready_input(e)
		"phone":
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				var ph := _phone()
				var a := Rect2(ph.position.x + 20, ph.end.y - 90, ph.size.x * 0.5 - 30, 60)
				var b := Rect2(ph.get_center().x + 10, ph.end.y - 90, ph.size.x * 0.5 - 30, 60)
				if a.has_point(e.position):
					_phone_answer(false)
				elif b.has_point(e.position):
					_phone_answer(true)
		"otp":
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				for k in _keys:
					if (k[0] as Rect2).has_point(e.position):
						_otp_key(str(k[1]))


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	if kind == "otp":
		if e.keycode >= KEY_0 and e.keycode <= KEY_9:
			_otp_key(str(e.keycode - KEY_0))
		elif e.keycode >= KEY_KP_0 and e.keycode <= KEY_KP_9:
			_otp_key(str(e.keycode - KEY_KP_0))
		elif e.keycode == KEY_BACKSPACE:
			_otp_key("⌫")
		accept_event()
	elif kind == "sign" and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and _ink > 120.0:
		_done({"signed": true, "strokes": strokes.size()})
		accept_event()


func _say(text: String, col: Color) -> void:
	_msg = text
	_msg_col = col
	_msg_t = 2.5


func _answer(says_short: bool) -> void:
	var short_i := int(spec.get("short", -1))
	var found: bool = short_i >= 0 and bundles[short_i]["counted"] >= 1.0
	var counted := 0
	for b in bundles:
		if b["counted"] >= 1.0:
			counted += 1
	_done({"short_reported": says_short, "short_found": found and says_short, "counted": counted})


func _drop() -> void:
	var ts: Array = spec.get("targets", [])
	var rs := _targets()
	for i in rs.size():
		if (rs[i] as Rect2).grow(20.0).has_point(_thing):
			if ts[i].get("right", false):
				_thing = (rs[i] as Rect2).get_center() + Vector2(0, 20)
				_say(L("Done.", "முடிஞ்சது."), GOOD)
				queue_redraw()
				get_tree().create_timer(0.9).timeout.connect(func(): _done({"placed": true}))
				return
			_say(t_(ts[i].get("wrong", {"en": "Not there.", "ta": "அங்க இல்ல."})), BAD)
	_thing = _home
	queue_redraw()


func _otp_key(k: String) -> void:
	if k == "⌫":
		_code = _code.substr(0, maxi(_code.length() - 1, 0))
	elif _code.length() < 4:
		_code += k
	if _code.length() == 4:
		if _code == str(spec.get("code", "")):
			_say(L("OTP verified. Order delivered.", "ஓடிபி சரி. ஆர்டர் டெலிவரி ஆச்சு."), GOOD)
			get_tree().create_timer(1.0).timeout.connect(func(): _done({"otp": true}))
		else:
			_say(L("Wrong OTP. Ask again.", "தப்பான ஓடிபி. மறுபடி கேளுங்க."), BAD)
			_code = ""
	queue_redraw()


func _done(result: Dictionary) -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finished.emit(result)


# ---- running ----
func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_msg_t -= dt
	if kind == "count" and _counting >= 0:
		bundles[_counting]["counted"] = minf(bundles[_counting]["counted"] + dt / 1.1, 1.0)
		if bundles[_counting]["counted"] >= 1.0:
			_counting = -1
	if kind == "hang" and _home == Vector2.ZERO:
		var p := _panel()
		_home = Vector2(p.get_center().x, p.end.y - 70.0)
		_thing = _home
	if skip and _t > 1.5:
		match kind:
			"sign":
				var s := PackedVector2Array()
				for i in 40:
					s.append(Vector2(20 + i * 6, 40 + sin(i * 0.7) * 18))
				strokes = [s]
				_ink = 300.0
				if _t > 2.2:
					_done({"signed": true, "strokes": 1})
			"count":
				for b in bundles:
					b["counted"] = 1.0
				if _t > 2.2:
					_answer(true)
			"hang":
				var ts: Array = spec.get("targets", [])
				for i in ts.size():
					if ts[i].get("right", false):
						_thing = (_targets()[i] as Rect2).get_center()
				if _t > 2.2:
					_done({"placed": true})
			"otp":
				_code = str(spec.get("code", ""))
				if _t > 2.2:
					_done({"otp": true})
			"phone":
				if _t > 2.0:
					_phone_answer(true)
			"ready":
				if _t > 1.6:
					_t = 1.0
					if CHORES[chore] == "dress":
						shirt = "blue"
					_next_chore()
	queue_redraw()


# ---- drawing ----
func _text(pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, s, align, w, size, col)


func _draw() -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var p := _panel()
	# the tip from the owner / boss, above the picture
	if spec.has("tip"):
		var tb := Rect2(p.position.x, p.position.y - 72.0, p.size.x, 58.0)
		draw_rect(tb, Color(0.1, 0.09, 0.05, 0.92))
		draw_rect(tb, Color(1.0, 0.82, 0.35, 0.9), false, 2.0)
		_text(tb.position + Vector2(16, 24), t_(spec.get("tip_who", {"en": "Tip", "ta": "டிப்"})), 16, Color(1.0, 0.82, 0.35))
		_text(tb.position + Vector2(16, 47), t_(spec["tip"]), 18, Color.WHITE, tb.size.x - 32.0)
	match kind:
		"sign":
			_draw_sign(p)
		"count":
			_draw_count(p)
		"hang":
			_draw_hang(p)
		"otp":
			_draw_otp(p)
		"ready":
			_draw_ready(p)
		"phone":
			_draw_phone()
	if _msg_t > 0.0 and _msg != "":
		var mb := Rect2(p.position.x + p.size.x * 0.25, p.end.y + 12.0, p.size.x * 0.5, 40.0)
		draw_rect(mb, Color(1, 1, 1, 0.95))
		_text(mb.position + Vector2(0, 27), _msg, 19, _msg_col, mb.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _btn(r: Rect2, label: String, on := true) -> void:
	draw_rect(r, Color(0.2, 0.45, 0.85) if on else Color(0.45, 0.45, 0.5))
	_text(r.position + Vector2(0, 31), label, 19, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_sign(p: Rect2) -> void:
	# the paper, slightly tilted shadow, printed lines and the filled fields
	draw_rect(Rect2(p.position + Vector2(8, 10), p.size), Color(0, 0, 0, 0.35))
	draw_rect(p, PAPER)
	draw_rect(Rect2(p.position, Vector2(p.size.x, 64)), Color(0.12, 0.35, 0.25))
	_text(p.position + Vector2(24, 40), t_(spec.get("header", "")), 24, Color.WHITE)
	_text(p.position + Vector2(p.size.x - 260, 40), t_(spec.get("form", "")), 16, Color(0.85, 0.95, 0.88))
	var y := p.position.y + 110.0
	for f in spec.get("fields", []):
		_text(Vector2(p.position.x + 30, y), t_(f[0]), 16, Color(0.35, 0.33, 0.3))
		draw_line(Vector2(p.position.x + 250, y + 6), Vector2(p.end.x - 40, y + 6), Color(0.6, 0.58, 0.52), 1.0)
		_text(Vector2(p.position.x + 260, y), t_(f[1]), 20, INK)
		y += 46.0
	var box := _sign_box()
	draw_rect(box, Color(1, 1, 0.97))
	draw_rect(box, Color(0.5, 0.48, 0.42), false, 1.5)
	_text(Vector2(box.position.x, box.end.y + 20), t_(spec.get("sign_label", {"en": "Signature", "ta": "கையொப்பம்"})), 15, Color(0.35, 0.33, 0.3))
	if strokes.is_empty():
		_text(box.position + Vector2(0, box.size.y * 0.58), L("Sign here with the mouse", "மவுஸால இங்க கையெழுத்து போடுங்க"), 17,
			Color(0.6, 0.6, 0.6), box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	for s in strokes:
		if (s as PackedVector2Array).size() > 1:
			var pts := PackedVector2Array()
			for q in s:
				pts.append(q + box.position)
			draw_polyline(pts, INK, 3.0, true)
	draw_circle(Vector2(p.position.x + 120, box.get_center().y), 46.0, Color(0.55, 0.12, 0.2, 0.25))
	_text(Vector2(p.position.x + 74, box.get_center().y + 6), L("BANK SEAL", "வங்கி முத்திரை"), 14, Color(0.55, 0.12, 0.2, 0.6))
	_btn(_button(0, 2), L("Clear", "அழி"))
	_btn(_button(1, 2), L("Done  (Enter)", "முடிஞ்சது  (Enter)"), _ink > 120.0)


func _draw_count(p: Rect2) -> void:
	draw_rect(p, Color(0.33, 0.24, 0.16))                      # the counter top
	draw_rect(Rect2(p.position, Vector2(p.size.x, 50)), Color(0.2, 0.15, 0.1))
	_text(p.position + Vector2(24, 34), L("Count every bundle: 100 notes of ₹500 each", "ஒவ்வொரு கட்டையும் எண்ணுங்க: ₹500 நோட்டு 100"), 20, Color.WHITE)
	var total := 0
	for i in bundles.size():
		var r := _bundle_rect(i)
		var b: Dictionary = bundles[i]
		var c: float = b["counted"]
		if c < 0.0:
			for k in 6:                                         # a strapped bundle, edges of notes showing
				draw_rect(Rect2(r.position + Vector2(k * 1.5, k * -2.0), r.size), NOTE.darkened(0.05 * (5 - k)))
			draw_rect(Rect2(r.position.x + r.size.x * 0.4, r.position.y - 10, r.size.x * 0.2, r.size.y), Color(0.85, 0.82, 0.7))
			_text(r.position + Vector2(0, r.size.y * 0.55), "₹500 × 100", 18, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_text(r.position + Vector2(0, r.size.y + 22), L("click to count", "எண்ண கிளிக்"), 14, Color(0.9, 0.85, 0.7), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var n := int(round(float(b["n"]) * c))
			for k in 9:                                         # fanned out while being counted
				var a := (k - 4) * 0.09 * c
				var q := r.get_center() + Vector2(0, r.size.y * 0.2)
				var pts := PackedVector2Array()
				for v in [Vector2(-r.size.x * 0.4, -r.size.y * 0.7), Vector2(r.size.x * 0.4, -r.size.y * 0.7), Vector2(r.size.x * 0.4, 0), Vector2(-r.size.x * 0.4, 0)]:
					pts.append(q + (v as Vector2).rotated(a))
				draw_colored_polygon(pts, NOTE.lightened(0.04 * k))
			var col := Color.WHITE if c < 1.0 else (GOOD.lightened(0.3) if b["n"] == 100 else Color(1.0, 0.5, 0.4))
			_text(r.position + Vector2(0, r.size.y + 22), str(n) + (L(" notes", " நோட்டு")), 18, col, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			if c >= 1.0:
				total += int(b["n"]) * 500
	_text(Vector2(p.position.x + 24, p.end.y - 92), L("Counted so far: ", "இதுவரை எண்ணியது: ") + _rupees(total), 20, Color.WHITE)
	_btn(_button(0, 2), L("All correct: ₹4,00,000", "எல்லாம் சரி: ₹4,00,000"))
	_btn(_button(1, 2), L("A bundle is short", "ஒரு கட்டு குறையுது"))


func _draw_hang(p: Rect2) -> void:
	var thing := str(spec.get("thing", "key"))
	if thing == "key":
		draw_rect(p.grow_individual(-p.size.x * 0.08, 0, -p.size.x * 0.08, 0), Color(0.45, 0.3, 0.17))   # the wooden key board
		_text(p.position + Vector2(0, 40), t_(spec.get("title", "")), 22, Color.WHITE, p.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		draw_rect(p, Color(0.55, 0.42, 0.3))                   # a desk top
		_text(p.position + Vector2(0, 40), t_(spec.get("title", "")), 22, Color.WHITE, p.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var ts: Array = spec.get("targets", [])
	var rs := _targets()
	for i in rs.size():
		var r: Rect2 = rs[i]
		if thing == "key":
			draw_circle(Vector2(r.get_center().x, r.position.y + 20), 9.0, Color(0.75, 0.72, 0.65))   # the hook
			draw_line(Vector2(r.get_center().x, r.position.y + 20), Vector2(r.get_center().x, r.position.y + 42), Color(0.75, 0.72, 0.65), 4.0)
		else:
			draw_rect(Rect2(r.position + Vector2(10, 30), r.size - Vector2(20, 40)), Color(0.25, 0.22, 0.2))
		_text(Vector2(r.position.x - 20, r.end.y + 8), t_(ts[i]["label"]), 17, Color.WHITE, r.size.x + 40, HORIZONTAL_ALIGNMENT_CENTER)
	# the thing being placed
	var c := _thing
	if thing == "key":
		draw_circle(c + Vector2(0, -18), 16.0, Color(0.78, 0.68, 0.3))
		draw_circle(c + Vector2(0, -18), 6.0, Color(0.45, 0.3, 0.17))
		draw_rect(Rect2(c + Vector2(-4, -4), Vector2(8, 44)), Color(0.78, 0.68, 0.3))
		draw_rect(Rect2(c + Vector2(4, 24), Vector2(10, 5)), Color(0.78, 0.68, 0.3))
		draw_rect(Rect2(c + Vector2(4, 32), Vector2(7, 5)), Color(0.78, 0.68, 0.3))
		draw_rect(Rect2(c + Vector2(-14, -48), Vector2(28, 18)), Color(0.15, 0.15, 0.17))       # the SUV key's fob
	else:
		draw_rect(Rect2(c - Vector2(24, 44), Vector2(48, 88)), Color(0.08, 0.08, 0.1))
		draw_rect(Rect2(c - Vector2(20, 38), Vector2(40, 72)), Color(0.2, 0.35, 0.55))
	if not _drag and _thing == _home:
		_text(Vector2(p.position.x, p.end.y - 20), L("Drag it to the right place", "சரியான இடத்துக்கு இழுத்து வையுங்க"), 16,
			Color(1, 1, 1, 0.8), p.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_otp(p: Rect2) -> void:
	var ph := _phone()
	draw_rect(ph.grow(10.0), Color(0.05, 0.05, 0.06))
	draw_rect(ph, Color(0.96, 0.96, 0.98))
	draw_rect(Rect2(ph.position, Vector2(ph.size.x, 60)), Color(0.9, 0.35, 0.1))
	_text(ph.position + Vector2(16, 38), t_(spec.get("app", "")), 20, Color.WHITE)
	var y := ph.position.y + 92.0
	for line in spec.get("order", []):
		_text(Vector2(ph.position.x + 16, y), t_(line), 16, DARK, ph.size.x - 32.0)
		y += 26.0
	_text(Vector2(ph.position.x + 16, y + 14), L("Enter the customer's OTP", "வாடிக்கையாளர் ஓடிபி போடுங்க"), 17, DARK)
	for i in 4:
		var r := Rect2(ph.position.x + 40 + i * 68, y + 30, 56, 56)
		draw_rect(r, Color(1, 1, 1))
		draw_rect(r, Color(0.5, 0.5, 0.55), false, 2.0)
		if i < _code.length():
			_text(r.position + Vector2(0, 40), _code[i], 30, DARK, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_keys.clear()
	var labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
	var ky := y + 110.0
	var kw := (ph.size.x - 60.0) / 3.0
	var kh := minf(52.0, (ph.end.y - ky - 20.0) / 4.0 - 8.0)
	for i in labels.size():
		if labels[i] == "":
			continue
		var r := Rect2(ph.position.x + 20 + (i % 3) * (kw + 10), ky + (i / 3) * (kh + 8), kw, kh)
		draw_rect(r, Color(0.88, 0.88, 0.92))
		_text(r.position + Vector2(0, kh * 0.68), labels[i], 24, DARK, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_keys.append([r, labels[i]])


# ---- the phone ----
var _answered := false


func _phone_answer(yes: bool) -> void:
	if str(spec.get("mode", "offer")) == "offer":
		if yes:
			_done({"accepted": true})
		else:
			_say(t_(spec.get("decline_says", {"en": "Divya: \"Anna. Friday. Fees.\"", "ta": "திவ்யா: \"அண்ணா. வெள்ளி. ஃபீஸ்.\""})), BAD)
		return
	if _answered:
		return
	_answered = true
	if yes:
		_say(t_(spec.get("silence", {"en": "...breathing. Then the line goes dead.", "ta": "...மூச்சு சத்தம். அப்புறம் லைன் கட் ஆகுது."})), DARK)
	get_tree().create_timer(2.6).timeout.connect(func(): _done({"answered": yes}))


func _draw_phone() -> void:
	var ph := _phone()
	var call := str(spec.get("mode", "offer")) == "call"
	draw_rect(ph.grow(10.0), Color(0.05, 0.05, 0.06))
	draw_rect(ph, Color(0.1, 0.12, 0.18) if call else Color(0.96, 0.96, 0.98))
	if call:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_circle(ph.get_center() + Vector2(0, -90), 60.0 + pulse * 10.0, Color(0.3, 0.6, 0.35, 0.3 + 0.3 * pulse))
		draw_circle(ph.get_center() + Vector2(0, -90), 50.0, Color(0.6, 0.6, 0.65))
		_text(ph.position + Vector2(0, ph.size.y * 0.55), L("Unknown number", "தெரியாத நம்பர்"), 24, Color.WHITE, ph.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(ph.position + Vector2(0, ph.size.y * 0.55 + 34), "+91 9•••• ••••7", 18, Color(0.7, 0.7, 0.75), ph.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		if not _answered:
			_btn(Rect2(ph.position.x + 20, ph.end.y - 90, ph.size.x * 0.5 - 30, 60), L("Ignore", "விடு"), true)
			_btn(Rect2(ph.get_center().x + 10, ph.end.y - 90, ph.size.x * 0.5 - 30, 60), L("Answer", "எடு"), true)
		return
	draw_rect(Rect2(ph.position, Vector2(ph.size.x, 60)), Color(0.9, 0.35, 0.1))
	_text(ph.position + Vector2(16, 38), t_(spec.get("app", "")), 20, Color.WHITE)
	var y := ph.position.y + 100.0
	_text(Vector2(ph.position.x + 16, y), L("New order nearby", "அருகில் புது ஆர்டர்"), 22, DARK)
	y += 36.0
	for line in spec.get("order", []):
		_text(Vector2(ph.position.x + 16, y), t_(line), 17, DARK, ph.size.x - 32.0)
		y += 28.0
	_btn(Rect2(ph.position.x + 20, ph.end.y - 90, ph.size.x * 0.5 - 30, 60), L("Decline", "வேண்டாம்"), false)
	_btn(Rect2(ph.get_center().x + 10, ph.end.y - 90, ph.size.x * 0.5 - 30, 60), L("Accept", "ஏத்துக்கோ"), true)


# ---- getting ready ----
func _chore_rects() -> Dictionary:
	"""Hotspots of the current chore's picture (panel coordinates)."""
	var p := _panel()
	var c := p.get_center() + Vector2(90, 10)
	var out := {}
	match CHORES[chore]:
		"alarm":
			out["snooze"] = Rect2(c + Vector2(-230, 140), Vector2(200, 54))
			out["up"] = Rect2(c + Vector2(30, 140), Vector2(200, 54))
		"brush", "bath":
			out["area"] = Rect2(c - Vector2(220, 150), Vector2(440, 280))
		"dress":
			var names := ["blue", "white", "check", "cap"]
			for i in 4:
				out[names[i]] = Rect2(c + Vector2(-300 + i * 150, -150), Vector2(120, 230))
		"eat":
			for i in 4:
				out["idli%d" % i] = Rect2(c + Vector2(-150 + (i % 2) * 150, -110 + (i / 2) * 110), Vector2(120, 90))
		"pocket":
			for i in _pocket_items.size():
				out[_pocket_items[i]] = Rect2(c + Vector2(-330 + i * 140, -170), Vector2(120, 90))
			out["pocket"] = Rect2(c + Vector2(-150, 30), Vector2(300, 160))
	return out


func _ready_input(e: InputEvent) -> void:
	var r := _chore_rects()
	var ch: String = CHORES[chore]
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			match ch:
				"alarm":
					if r["snooze"].has_point(e.position):
						minutes += 10
						_say(L("Ten more minutes... (6:%d)" % (30 + minutes), "இன்னும் பத்து நிமிஷம்... (6:%d)" % (30 + minutes)), DARK)
						if minutes >= 30:
							_say(L("Amma: \"Karthik! It's seven o'clock!\"", "அம்மா: \"கார்த்திக்! மணி ஏழு!\""), BAD)
							_next_chore()
					elif r["up"].has_point(e.position):
						_next_chore()
				"brush", "bath":
					if r["area"].has_point(e.position):
						_scrub = true
						_last_x = e.position.x
						if ch == "bath":                            # one mug of water per click
							_prog = minf(_prog + 1.0 / 7.0, 1.0)
							if _prog >= 1.0:
								_next_chore()
				"dress":
					for k in ["blue", "white", "check"]:
						if r[k].has_point(e.position):
							shirt = k
							_say(L("A good shirt for a big day.", "பெரிய நாளுக்கு நல்ல சட்டை."), GOOD)
							get_tree().create_timer(0.8).timeout.connect(_next_chore)
					if r["cap"].has_point(e.position):
						reached_cap = true
						_say(L("Divya: \"Anna, a cap? It ruins your hair. Put it back.\"", "திவ்யா: \"அண்ணா, தொப்பியா? முடி கெட்டுப்போகும். வச்சுடு.\""), BAD)
				"eat":
					for i in 4:
						var k := "idli%d" % i
						if r[k].has_point(e.position) and not _picked.has(k):
							_picked[k] = true
							if _picked.size() == 4:
								_say(L("Amma: \"Good. Now go, and drive carefully.\"", "அம்மா: \"நல்லது. இப்போ போ, கவனமா ஓட்டு.\""), GOOD)
								get_tree().create_timer(0.9).timeout.connect(_next_chore)
				"pocket":
					for it in _pocket_items:
						if r[it].has_point(e.position) and not _picked.has(it):
							_drag_item = it
							_thing = e.position
		else:
			_scrub = false
			if ch == "pocket" and _drag_item != "":
				if r["pocket"].grow(30.0).has_point(_thing):
					_picked[_drag_item] = true
					if _picked.size() == _pocket_items.size():
						_next_chore()
				_drag_item = ""
	elif e is InputEventMouseMotion:
		if ch == "brush" and _scrub and r["area"].has_point(e.position):
			_prog = minf(_prog + absf(e.position.x - _last_x) / 2400.0, 1.0)
			_last_x = e.position.x
			if _prog >= 1.0:
				_scrub = false
				_next_chore()
		if ch == "pocket" and _drag_item != "":
			_thing = e.position
	queue_redraw()


func _next_chore() -> void:
	if chore >= CHORES.size():
		return
	minutes += int(CHORE_MIN[CHORES[chore]])
	chore += 1
	_prog = 0.0
	_picked = {}
	stage_changed.emit()
	if chore >= CHORES.size():
		_done({"minutes": minutes, "shirt": shirt, "reached_cap": reached_cap, "late_morning": minutes > 45})
	queue_redraw()


func _draw_ready(p: Rect2) -> void:
	# the house: a whitewashed room in morning light, the checklist of chores on the left
	draw_rect(p, Color(0.93, 0.9, 0.82))
	draw_rect(Rect2(p.position.x, p.end.y - 70, p.size.x, 70), Color(0.62, 0.5, 0.38))          # red-oxide floor
	draw_rect(Rect2(p.end.x - 190, p.position.y + 40, 140, 120), Color(0.75, 0.88, 1.0))      # the window
	draw_rect(Rect2(p.end.x - 190, p.position.y + 40, 140, 120), Color(0.3, 0.45, 0.3), false, 6.0)
	var names := {"alarm": L("Wake up", "எழுந்திரு"), "brush": L("Brush your teeth", "பல் தேய்"), "bath": L("Bath", "குளி"),
		"dress": L("Get dressed", "டிரஸ் பண்ணு"), "eat": L("Breakfast", "சாப்பிடு"), "pocket": L("Wallet, phone, keys", "பர்ஸ், ஃபோன், சாவி")}
	for i in CHORES.size():
		var y := p.position.y + 50 + i * 40
		var col := GOOD if i < chore else (DARK if i == chore else Color(0.55, 0.55, 0.55))
		_text(Vector2(p.position.x + 24, y), ("✔ " if i < chore else ("▸ " if i == chore else "   ")) + str(names[CHORES[i]]), 19, col)
	var h := 6 * 60 + 30 + minutes
	_text(Vector2(p.position.x + 24, p.end.y - 28), L("Clock: ", "நேரம்: ") + "%d:%02d AM" % [h / 60, h % 60] +
		L("   (leave by 7:15)", "   (7:15-க்குள் கிளம்பணும்)"), 18, BAD if minutes > 45 else DARK)
	if chore >= CHORES.size():
		return
	var r := _chore_rects()
	var c := p.get_center() + Vector2(90, 10)
	match CHORES[chore]:
		"alarm":
			draw_rect(Rect2(c - Vector2(110, 180), Vector2(220, 300)), Color(0.08, 0.08, 0.1))      # the phone
			draw_rect(Rect2(c - Vector2(100, 170), Vector2(200, 280)), Color(0.15, 0.2, 0.35))
			var shake := sin(_t * 40.0) * 4.0
			_text(c + Vector2(-100 + shake, -60), "6:%02d" % (30 + minutes), 54, Color.WHITE, 200, HORIZONTAL_ALIGNMENT_CENTER)
			_text(c + Vector2(-100, 0), L("ALARM", "அலாரம்"), 22, Color(1, 0.8, 0.3), 200, HORIZONTAL_ALIGNMENT_CENTER)
			_btn(r["snooze"], L("Snooze (+10 min)", "ஸ்னூஸ் (+10 நிமி)"), true)
			_btn(r["up"], L("Get up", "எழுந்திரு"), true)
		"brush":
			var a: Rect2 = r["area"]
			draw_rect(a, Color(0.85, 0.92, 0.95))                                                    # the mirror
			draw_rect(Rect2(a.get_center() - Vector2(120, 40), Vector2(240, 80)), Color(0.95, 0.95, 0.92))   # teeth
			for k in 8:
				draw_line(a.get_center() + Vector2(-120 + k * 30, -40), a.get_center() + Vector2(-120 + k * 30, 40), Color(0.8, 0.8, 0.78), 2.0)
			var bx := a.get_center().x + sin(_t * 6.0) * 90.0 if _prog < 0.05 else get_local_mouse_position().x
			draw_rect(Rect2(Vector2(bx - 70, a.get_center().y + 46), Vector2(140, 12)), Color(0.2, 0.5, 0.85))   # the brush
			draw_rect(Rect2(Vector2(bx - 70, a.get_center().y + 30), Vector2(40, 16)), Color(1, 1, 1))
			_text(Vector2(a.position.x, a.end.y + 26), L("Hold the mouse and scrub left and right", "மவுஸை அழுத்தி இடம் வலமா தேய்"), 17, DARK, a.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_bar(Rect2(a.position.x, a.end.y + 40, a.size.x, 14), _prog)
		"bath":
			var a: Rect2 = r["area"]
			draw_rect(a, Color(0.7, 0.78, 0.8))                                                      # the bathroom tiles
			for k in 6:
				draw_line(Vector2(a.position.x + k * a.size.x / 6, a.position.y), Vector2(a.position.x + k * a.size.x / 6, a.end.y), Color(0.6, 0.68, 0.7), 1.0)
			draw_rect(Rect2(a.get_center() + Vector2(-80, 20), Vector2(160, 110)), Color(0.15, 0.4, 0.7))   # the bucket
			draw_rect(Rect2(a.get_center() + Vector2(90, -20), Vector2(50, 40)), Color(0.9, 0.35, 0.2))      # the mug
			for k in int(_prog * 7.0):
				draw_circle(a.get_center() + Vector2(-60 + k * 20, -60 + (k % 2) * 14), 6.0, Color(0.6, 0.85, 1.0))
			_text(Vector2(a.position.x, a.end.y + 26), L("Click to pour mug after mug", "கிளிக் பண்ணி மக் மக்கா ஊத்து"), 17, DARK, a.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_bar(Rect2(a.position.x, a.end.y + 40, a.size.x, 14), _prog)
		"dress":
			var cols := {"blue": Color(0.3, 0.5, 0.8), "white": Color(0.95, 0.95, 0.93), "check": Color(0.7, 0.3, 0.25)}
			for k in ["blue", "white", "check"]:
				var b: Rect2 = r[k]
				draw_line(Vector2(b.get_center().x, b.position.y - 20), Vector2(b.get_center().x, b.position.y), Color(0.4, 0.3, 0.2), 3.0)
				draw_rect(Rect2(b.position + Vector2(10, 20), b.size - Vector2(20, 40)), cols[k])     # a shirt on its hanger
				draw_rect(Rect2(b.position + Vector2(-8, 24), Vector2(26, 80)), cols[k])
				draw_rect(Rect2(b.position + Vector2(b.size.x - 18, 24), Vector2(26, 80)), cols[k])
				if k == "check":
					for q in 5:
						draw_line(Vector2(b.position.x + 10, b.position.y + 40 + q * 30), Vector2(b.end.x - 10, b.position.y + 40 + q * 30), Color(0.95, 0.85, 0.6), 2.0)
			var cb: Rect2 = r["cap"]
			draw_circle(cb.get_center() + Vector2(0, -20), 40.0, Color(0.15, 0.15, 0.17))         # the cap on its hook
			draw_rect(Rect2(cb.get_center() + Vector2(-50, 10), Vector2(80, 14)), Color(0.15, 0.15, 0.17))
			_text(Vector2(c.x - 300, c.y + 120), L("Pick a shirt", "ஒரு சட்டையை எடு"), 18, DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)
		"eat":
			draw_circle(c + Vector2(0, -10), 190.0, Color(0.2, 0.45, 0.15))                       # the banana leaf
			for i in 4:
				var k := "idli%d" % i
				if not _picked.has(k):
					var b: Rect2 = r[k]
					draw_circle(b.get_center(), 42.0, Color(0.97, 0.96, 0.9))
					draw_circle(b.get_center(), 42.0, Color(0.85, 0.83, 0.75), false, 2.0)
			draw_circle(c + Vector2(140, 120), 30.0, Color(0.95, 0.95, 0.85))                     # coconut chutney
			draw_circle(c + Vector2(-140, 120), 30.0, Color(0.75, 0.35, 0.1))                     # sambar
			_text(Vector2(c.x - 300, c.y + 200), L("Click each idli to eat it", "ஒவ்வொரு இட்லியையும் கிளிக் பண்ணி சாப்பிடு"), 18, DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)
		"pocket":
			var pk: Rect2 = r["pocket"]
			draw_rect(pk, Color(0.35, 0.35, 0.45))                                                   # the trouser pocket
			_text(pk.position + Vector2(0, pk.size.y * 0.55), L("Pocket", "பாக்கெட்"), 22, Color.WHITE, pk.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			var icol := {"wallet": Color(0.4, 0.25, 0.12), "phone": Color(0.1, 0.1, 0.12), "scooter key": Color(0.8, 0.7, 0.3), "house key": Color(0.7, 0.7, 0.72)}
			for it in _pocket_items:
				if _picked.has(it):
					continue
				var b: Rect2 = r[it]
				var at := b
				if it == _drag_item:
					at = Rect2(_thing - b.size * 0.5, b.size)
				draw_rect(Rect2(at.position + Vector2(20, 10), at.size - Vector2(40, 30)), icol[it])
				_text(Vector2(at.position.x - 10, at.end.y + 12), _item_name(it), 16, DARK, at.size.x + 20, HORIZONTAL_ALIGNMENT_CENTER)
			_text(Vector2(c.x - 300, pk.end.y + 30), L("Drag everything into your pocket", "எல்லாத்தையும் பாக்கெட்டுக்குள்ள இழு"), 18, DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)


func _item_name(it: String) -> String:
	var n := {"wallet": ["Wallet", "பர்ஸ்"], "phone": ["Phone", "ஃபோன்"], "scooter key": ["Scooter key", "ஸ்கூட்டர் சாவி"],
		"house key": ["House key", "வீட்டு சாவி"]}
	return n[it][1] if lang == "ta" else n[it][0]


func _bar(r: Rect2, f: float) -> void:
	draw_rect(r, Color(0.8, 0.8, 0.8))
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), GOOD)


static func _rupees(n: int) -> String:
	var s := str(n)
	if s.length() <= 3:
		return "₹" + s
	var last := s.substr(s.length() - 3)
	var rest := s.substr(0, s.length() - 3)
	var parts := []
	while rest.length() > 2:
		parts.push_front(rest.substr(rest.length() - 2))
		rest = rest.substr(0, rest.length() - 2)
	if rest != "":
		parts.push_front(rest)
	return "₹" + ",".join(parts) + "," + last
