extends Control
## The questioning (GAME_DESIGN.md §8.3): Karthik at the table across from the inspector, whose face fills the view
## above (story.gd's face-to-face camera); the table top is the lower part of the screen. The inspector puts things
## down one at a time as he speaks ("lines": each may bring an "exhibit"); then he waits for an answer, and the
## answer is what Karthik does:
##   show       drag his own phone from Selvi's tray (the delivery app's trips) up to the inspector and hold it
##              there, steady, until he takes it: the truth (told_truth). His hand shakes with his stress (life.gd):
##              over 85 the phone won't stay up, it slips back. Holding Space, he breathes, slowly, and it eases.
##   say        the one thing he can only say: "I was at home all night." (lied_home)
##   nothing    the inspector's patience runs out (his fingers drumming), and Karthik asks for a lawyer (kept_silent)
## Moving the mouse over a thing on the table brings it closer, to read.

signal said(line: Dictionary)
signal finished(result: Dictionary)

const WOOD := Color(0.36, 0.22, 0.12)
const WOOD2 := Color(0.3, 0.18, 0.1)
const PAPER := Color(0.96, 0.95, 0.9)
const INK := Color(0.1, 0.1, 0.14)

var lang := "en"
var life                                   # life.gd (stress: the shaking hand)
var skip := false
var choice := 0                             # (testing: 1 show, 2 say, 3 nothing)
var lines: Array = []
var font: Font
var _i := -1                                # the inspector's line now
var _line_t := 0.0
var _on_table: Array = []                   # exhibit ids, in the order they were put down
var _arrive := {}                           # id → 0..1 sliding in
var _waiting := false                       # all said: his answer now
var _wait_t := 0.0
var _drag := false
var _held := Vector2.ZERO                   # where his hand holds the phone
var _steady := 0.0                          # 0..1 held up there long enough
var _slip_t := 0.0
var _hover := ""
var _breath := 0.0                          # 0..1 one slow breath
var _t := 0.0
var _done := false
var _tap: AudioStreamPlayer

const PATIENCE := 28.0                      # seconds he'll wait in silence


func start(spec: Dictionary, language: String, testing: bool, pick: int) -> void:
	lang = language
	skip = testing
	choice = pick
	lines = spec.get("lines", [])
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_i = -1
	_on_table.clear()
	_arrive.clear()
	_waiting = false
	_done = false
	_steady = 0.0
	visible = true
	if _tap == null:
		_tap = AudioStreamPlayer.new()
		_tap.stream = _knuckle()
		_tap.volume_db = -10.0
		add_child(_tap)
	_next_line()


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func _next_line() -> void:
	_i += 1
	_line_t = 0.0
	if _i >= lines.size():
		_waiting = true
		_wait_t = 0.0
		return
	var ln: Dictionary = lines[_i]
	if ln.has("exhibit"):
		_on_table.append(str(ln["exhibit"]))
		_arrive[str(ln["exhibit"])] = 0.0
	said.emit(ln)


# ---- layout ----
func _top() -> float:
	return get_viewport_rect().size.y * 0.56


func _ex_rect(id: String) -> Rect2:
	var vs := get_viewport_rect().size
	var i := _on_table.find(id)
	var n := maxi(_on_table.size(), 3)
	var w := minf(260.0, vs.x * 0.16)
	var x0 := vs.x * 0.5 - (n * (w + 30.0)) * 0.5 - 60.0
	var y := _top() + 70.0 - (1.0 - _ease(float(_arrive.get(id, 1.0)))) * 120.0
	return Rect2(x0 + i * (w + 30.0), y, w, w * 1.15)


func _tray() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x - 330.0, _top() + 60.0, 270.0, 300.0)


func _own_phone_home() -> Vector2:
	return _tray().get_center() + Vector2(0, 10)


func _show_zone() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x * 0.5 - 170.0, _top() - 190.0, 340.0, 210.0)


func _say_btn() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(60.0, vs.y - 110.0, 420.0, 64.0)


func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


# ---- the hands ----
func _stress() -> float:
	return float(life.stress) if life else 50.0


func _shake() -> Vector2:
	var a := maxf(0.0, _stress() - 40.0) * 1.3
	return Vector2(sin(_t * 21.0) + 0.6 * sin(_t * 47.0 + 1.0), cos(_t * 17.0) + 0.6 * sin(_t * 39.0)) * a * 0.5


func _phone_pos() -> Vector2:
	if _drag:
		return _held + _shake()
	return _own_phone_home()


func _gui_input(e: InputEvent) -> void:
	if _done:
		return
	if e is InputEventMouseMotion:
		_held = e.position
		_hover = ""
		for id in _on_table:
			if _ex_rect(id).has_point(e.position):
				_hover = id
	if not _waiting:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _line_t > 0.6:
			_next_line()                                 # (a click, like Enter: he goes on)
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if Rect2(_own_phone_home() - Vector2(70, 110), Vector2(140, 220)).has_point(e.position):
				_drag = true
				_held = e.position
			elif _say_btn().has_point(e.position):
				_finish("lied_home")
		elif _drag:
			_drag = false
			_steady = 0.0
	accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or _done or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if not _waiting and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and _line_t > 0.4:
		_next_line()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not visible or _done:
		return
	_t += dt
	_line_t += dt
	for id in _arrive:
		_arrive[id] = minf(float(_arrive[id]) + dt * 2.5, 1.0)
	if not _waiting and skip and _line_t > 1.0:
		_next_line()
	if _waiting:
		_wait_t += dt
		if Input.is_key_pressed(KEY_SPACE):            # a slow breath in, and out: it eases him
			_breath = minf(_breath + dt / 4.0, 1.0)
			if life:
				life.stress = maxf(float(life.stress) - dt * 3.0, 0.0)
		else:
			_breath = maxf(_breath - dt, 0.0)
		if skip:
			_test_pick(dt)
		if _drag:
			var held_at := _phone_pos()
			if _stress() > 85.0:                           # his hand won't hold it up
				_slip_t += dt
				if _slip_t > 1.2:
					_slip_t = 0.0
					_drag = false
					_steady = 0.0
			elif _show_zone().has_point(held_at):
				_steady += dt / 2.2
				_wait_t = 0.0
				if _steady >= 1.0:
					_finish("told_truth")
			else:
				_steady = maxf(_steady - dt, 0.0)
		elif _wait_t > PATIENCE * 0.45 and fmod(_wait_t, 0.5) < dt:   # his fingers on the table
			_tap.play()
		if _wait_t > PATIENCE:
			_finish("kept_silent")
	queue_redraw()


func _test_pick(dt: float) -> void:
	if _wait_t < 1.5:
		return
	match choice:
		1:
			_drag = true
			_held = _show_zone().get_center()
		2:
			_finish("lied_home")
		3:
			_wait_t += dt * 20.0                        # (the wait, quickly)


func _finish(flag: String) -> void:
	if _done:
		return
	_done = true
	_drag = false
	get_tree().create_timer(0.4).timeout.connect(func():
		visible = false
		finished.emit({flag: true}))


# ---- drawing ----
func _text(pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, s, align, w, size, col)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var top := _top()
	# the table top, its near edge under his hands
	draw_rect(Rect2(0, top, vs.x, vs.y - top), WOOD)
	for k in 9:
		var y := top + (vs.y - top) * (k + 0.5) / 9.0
		draw_line(Vector2(0, y), Vector2(vs.x, y + sin(k * 1.7) * 8.0), WOOD2, 2.0)
	draw_rect(Rect2(0, top - 6.0, vs.x, 8.0), Color(0.22, 0.13, 0.07))
	# Selvi's tray, his phone in it
	var tr := _tray()
	draw_rect(tr, Color(0.55, 0.57, 0.6))
	draw_rect(tr.grow(-10.0), Color(0.45, 0.47, 0.5))
	_text(Vector2(tr.position.x, tr.end.y + 22.0), L("Selvi's tray", "செல்வியோட தட்டு"), 14, Color(1, 1, 1, 0.6), tr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	for id in _on_table:
		if id != _hover:
			_draw_exhibit(id, _ex_rect(id), 1.0)
	if _hover != "":
		var r := _ex_rect(_hover)
		var big := Rect2(r.get_center() - r.size * 0.9, r.size * 1.8)
		big.position.y = minf(big.position.y, vs.y - big.size.y - 10.0)
		_draw_exhibit(_hover, big, 1.8)
	_draw_own_phone(_phone_pos())
	if not _waiting:
		return
	if _drag:
		var z := _show_zone()
		draw_rect(z, Color(1, 1, 1, 0.06 + 0.06 * sin(_t * 4.0)))
		draw_arc(_phone_pos() + Vector2(0, -120), 26.0, -PI * 0.5, -PI * 0.5 + TAU * _steady, 32, Color(1, 0.85, 0.35), 5.0)
	var sb := _say_btn()                                   # the one thing he can only say
	draw_rect(sb, Color(0.05, 0.05, 0.07, 0.8))
	_text(sb.position + Vector2(18, 40), "“" + L("I was at home, sir. All night.", "நான் வீட்லதான் இருந்தேன் சார். ராத்திரி முழுக்க.") + "”",
		19, Color(1, 1, 1, 0.92), sb.size.x - 30.0)
	if _breath > 0.0:                                      # his breath
		var c := Vector2(vs.x - 90.0, vs.y - 80.0)
		draw_circle(c, 18.0 + 30.0 * sin(_breath * PI), Color(0.7, 0.85, 1.0, 0.25))


func _draw_own_phone(p: Vector2) -> void:
	var r := Rect2(p - Vector2(70, 110), Vector2(140, 220))
	draw_rect(Rect2(r.position + Vector2(5, 7), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, Color(0.05, 0.05, 0.06))
	var s := r.grow(-6.0)
	draw_rect(s, Color(0.97, 0.96, 0.95))
	draw_rect(Rect2(s.position, Vector2(s.size.x, 22)), Color(0.9, 0.35, 0.1))
	_text(s.position + Vector2(4, 16), "QuickBite", 11, Color.WHITE)
	var rows := [["#4471", "9:50 PM"], ["", L("Gandhipuram", "காந்திபுரம்")], ["→", "10:20 PM"], ["", L("Saravanampatti", "சரவணம்பட்டி")], ["OTP", "5512 ✓"]]
	for i in rows.size():
		_text(s.position + Vector2(6, 42 + i * 26), str(rows[i][0]), 11, Color(0.4, 0.4, 0.45))
		_text(s.position + Vector2(36, 42 + i * 26), str(rows[i][1]), 12, INK, s.size.x - 40.0)


func _draw_exhibit(id: String, r: Rect2, k: float) -> void:
	draw_rect(Rect2(r.position + Vector2(6, 8) * k, r.size), Color(0, 0, 0, 0.35))
	match id:
		"workphone":                                       # his work phone, the message open
			draw_rect(r, Color(0.05, 0.05, 0.06))
			var s := r.grow(-8.0 * k)
			draw_rect(s, Color(0.93, 0.95, 0.97))
			_text(s.position + Vector2(8, 22) * k, L("Raghavan sir", "ராகவன் சார்"), int(13 * k), INK)
			var b := Rect2(s.position.x + s.size.x * 0.3, s.position.y + 60.0 * k, s.size.x * 0.66, 56.0 * k)
			draw_rect(b, Color(0.3, 0.6, 0.95))
			_text(b.position + Vector2(8, 22) * k, L("I'll come with", "கார்ல"), int(13 * k), Color.WHITE)
			_text(b.position + Vector2(8, 40) * k, L("the car.", "வரேன்."), int(13 * k), Color.WHITE)
			_text(Vector2(b.position.x, b.end.y + 16.0 * k), "9:52 PM  ✓✓", int(11 * k), Color(0.4, 0.4, 0.45))
		"still":                                           # the camera's still: the car, a man in a cap at the wheel
			draw_rect(r, Color(0.92, 0.92, 0.9))
			var s := r.grow(-8.0 * k)
			draw_rect(s, Color(0.32, 0.33, 0.34))
			draw_rect(Rect2(s.position.x, s.position.y + s.size.y * 0.55, s.size.x, s.size.y * 0.45), Color(0.22, 0.22, 0.23))
			var c := Rect2(s.position.x + s.size.x * 0.25, s.position.y + s.size.y * 0.45, s.size.x * 0.5, s.size.y * 0.22)
			draw_rect(c, Color(0.85, 0.85, 0.82))
			draw_rect(Rect2(c.position.x + c.size.x * 0.15, c.position.y - c.size.y * 0.45, c.size.x * 0.6, c.size.y * 0.5), Color(0.6, 0.62, 0.62))
			draw_circle(c.position + Vector2(c.size.x * 0.32, -c.size.y * 0.2), 6.0 * k, Color(0.12, 0.12, 0.13))   # the cap
			_text(s.position + Vector2(6, 16) * k, "LAWLEY RD CAM-03", int(10 * k), Color(1, 1, 1, 0.85))
			_text(Vector2(s.position.x + 6.0 * k, s.end.y - 8.0 * k), "22:12:41", int(11 * k), Color(1, 1, 1, 0.9))
		"slip":                                            # the withdrawal slip, his signature
			draw_rect(r, PAPER)
			var s := r.grow(-12.0 * k)
			_text(s.position + Vector2(0, 18) * k, L("Kovai Nagar Co-op Bank", "கோவை நகர் கூட்டுறவு வங்கி"), int(12 * k), INK)
			_text(s.position + Vector2(0, 40) * k, L("Cash withdrawal", "பணம் எடுத்தல்"), int(11 * k), Color(0.35, 0.35, 0.4))
			_text(s.position + Vector2(0, 76) * k, "₹ 4,00,000", int(22 * k), INK)
			var y := s.end.y - 36.0 * k
			var pts := PackedVector2Array()
			for i in 24:                                    # his signature, as he signed it at the counter
				pts.append(Vector2(s.position.x + 10.0 * k + i * 5.0 * k, y + sin(i * 1.3) * 8.0 * k - (6.0 * k if i % 7 == 3 else 0.0)))
			draw_polyline(pts, Color(0.1, 0.18, 0.55), 2.0 * k)
			_text(Vector2(s.position.x, s.end.y), L("Authorised: Karthik M.", "அனுமதி: கார்த்திக் ம."), int(10 * k), Color(0.35, 0.35, 0.4))
		_:
			draw_rect(r, PAPER)


static func _knuckle() -> AudioStreamWAV:
	var rate := 16000
	var data := PackedByteArray()
	var n := int(0.12 * rate)
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := (sin(TAU * 210.0 * t) + randf_range(-0.6, 0.6)) * exp(-t * 60.0) * 0.6
		data.encode_s16(i * 2, clampi(int(v * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
