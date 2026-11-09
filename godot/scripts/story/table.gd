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

const Kit := preload("res://scripts/ui/ui_kit.gd")
const Hud := preload("res://scripts/ui/hud_style.gd")
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
	font = Hud.font(500)
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
	var x0 := vs.x * 0.5 - (n * (w + 30.0)) * 0.5 + 60.0     # (right of his answer, on the left)
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
	var k := Hud.s(self)
	var ap := Rect2(40.0 * k, vs.y - 320.0 * k, 480.0 * k, 290.0 * k)
	return Rect2(ap.position.x + 20.0 * k, ap.end.y - 56.0 * k - 14.0 * k, ap.size.x - 40.0 * k, 56.0 * k)


## His answer, set out on the left once the inspector waits: the three things he can do, the one he can say a
## button, and how long the inspector will wait.
func _answer_panel() -> Rect2:
	var vs := get_viewport_rect().size
	var k := Hud.s(self)
	return Rect2(40.0 * k, vs.y - 320.0 * k, 480.0 * k, 290.0 * k)


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
	var kk := Hud.s(self)
	var tr := _tray()                                      # Selvi's steel tray, his phone in it
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.5, 0.52, 0.55)
	tsb.set_corner_radius_all(int(10.0 * kk))
	tsb.border_color = Color(0.68, 0.7, 0.73)
	tsb.set_border_width_all(maxi(2, int(3.0 * kk)))
	tsb.shadow_color = Color(0, 0, 0, 0.35)
	tsb.shadow_size = int(10.0 * kk)
	draw_style_box(tsb, tr)
	Hud.text(self, Vector2(tr.position.x, tr.end.y + 24.0 * kk), L("Selvi's tray · your phone", "செல்வியோட தட்டு · உங்க ஃபோன்"), Kit.T_LABEL * kk, Kit.DIM, 600,
		HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	for id in _on_table:
		if id != _hover:
			_draw_exhibit(id, _ex_rect(id), 1.0)
	if _hover != "":
		var r := _ex_rect(_hover)
		var big := Rect2(r.get_center() - r.size * 0.9, r.size * 1.8)
		big.position.y = minf(big.position.y, vs.y - big.size.y - 10.0)
		_draw_exhibit(_hover, big, 1.8)
	elif not _on_table.is_empty() and not _waiting:
		Hud.text(self, Vector2(0, top + 40.0 * kk), L("Point at a thing on the table to read it  ·  Enter or a click: go on", "படிக்க மேசையில ஒண்ண சுட்டுங்க  ·  Enter அல்லது கிளிக்: அடுத்து"),
			Kit.T_LABEL * kk, Hud.fade(Kit.INK, 0.6), 500, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_draw_own_phone(_phone_pos())
	if not _waiting:
		return
	if _drag:
		var z := _show_zone()
		var zsb := StyleBoxFlat.new()
		zsb.bg_color = Color(1, 1, 1, 0.05 + 0.04 * sin(_t * 4.0))
		zsb.set_corner_radius_all(int(14.0 * kk))
		zsb.border_color = Hud.fade(Kit.AMBER, 0.5 if not z.has_point(_phone_pos()) else 0.95)
		zsb.set_border_width_all(maxi(1, int(2.0 * kk)))
		draw_style_box(zsb, z)
		Hud.text(self, Vector2(z.position.x, z.position.y - 12.0 * kk), L("Hold it up to him, steady", "அவர்கிட்ட நீட்டிப் பிடிங்க, அசையாம"), Kit.T_LABEL * kk, Kit.AMBER, 600,
			HORIZONTAL_ALIGNMENT_CENTER, z.size.x)
		draw_arc(_phone_pos() + Vector2(0, -124), 24.0, 0, TAU, 32, Color(1, 1, 1, 0.15), 5.0)
		draw_arc(_phone_pos() + Vector2(0, -124), 24.0, -PI * 0.5, -PI * 0.5 + TAU * _steady, 32, Kit.AMBER, 5.0, true)
	var ap := _answer_panel()                              # his answer: what he can do, and how long he has
	Hud.panel(self, ap, kk, 1.3, Kit.AMBER)
	Hud.text(self, ap.position + Vector2(24.0 * kk, 34.0 * kk), L("THE INSPECTOR WAITS FOR AN ANSWER", "இன்ஸ்பெக்டர் பதிலுக்கு காத்திருக்கார்"), Kit.T_LABEL * kk, Kit.AMBER, 700)
	var opts := [[L("Show him", "காட்டுங்க"), L("drag your phone up to him, hold it", "ஃபோன இழுத்து அவர்கிட்ட பிடிங்க")],
		[L("Say it", "சொல்லுங்க"), L("the words below", "கீழ இருக்கற வார்த்தை")],
		[L("Say nothing", "பேசாதீங்க"), L("and he loses his patience", "அவர் பொறுமை போகும்")]]
	for i in opts.size():
		var y := ap.position.y + 70.0 * kk + i * 40.0 * kk
		Hud.text(self, Vector2(ap.position.x + 24.0 * kk, y), opts[i][0], Kit.T_CAPTION * kk, Kit.INK, 700)
		Hud.text(self, Vector2(ap.position.x + 160.0 * kk, y), opts[i][1], Kit.T_LABEL * kk, Kit.DIM, 500, HORIZONTAL_ALIGNMENT_LEFT, ap.size.x - 180.0 * kk)
	var pat := clampf(1.0 - _wait_t / PATIENCE, 0.0, 1.0)
	Kit.progress(self, Rect2(ap.position.x + 24.0 * kk, ap.position.y + 196.0 * kk, ap.size.x - 48.0 * kk, 4.0 * kk), pat, kk,
		Kit.GREY if pat > 0.45 else Kit.AMBER)
	Hud.text(self, Vector2(ap.position.x + 24.0 * kk, ap.position.y + 186.0 * kk), L("His patience", "அவர் பொறுமை"), Kit.T_LABEL * kk, Hud.fade(Kit.DIM, 0.8), 500)
	var sb := _say_btn()                                   # the one thing he can only say
	sb.position.y = ap.end.y - sb.size.y - 14.0 * kk
	sb.position.x = ap.position.x + 20.0 * kk
	sb.size.x = ap.size.x - 40.0 * kk
	Kit.button(self, sb, "“" + L("I was at home, sir. All night.", "நான் வீட்லதான் இருந்தேன் சார். ராத்திரி முழுக்க.") + "”", kk,
		Kit.state_of(sb, _held), "secondary")
	if _breath > 0.0 or _stress() > 60.0:                  # his breath (Space), when his hand shakes
		var c := Vector2(vs.x - 90.0 * kk, vs.y - 80.0 * kk)
		draw_circle(c, (18.0 + 30.0 * sin(_breath * PI)) * kk, Color(0.7, 0.85, 1.0, 0.25))
		Hud.text(self, Vector2(c.x - 160.0 * kk, c.y + 64.0 * kk), L("Hold Space: breathe", "Space அழுத்திப் பிடிங்க: மூச்சு"), Kit.T_LABEL * kk, Kit.DIM, 500,
			HORIZONTAL_ALIGNMENT_CENTER, 320.0 * kk)


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
	var n := _on_table.find(id) + 1                       # the station's exhibit tag, tied on
	var tw := Hud.width_of(L("EXH. %d", "சான்று %d") % n, 11.0 * k, 700) + 14.0 * k
	var tag := Rect2(r.position.x + r.size.x - tw - 6.0 * k, r.position.y - 14.0 * k, tw, 22.0 * k)
	if id == _hover:
		draw_rect(r.grow(4.0), Kit.AMBER, false, 2.0)
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
	draw_rect(tag, Color(0.93, 0.88, 0.72))
	draw_rect(tag, Color(0.5, 0.42, 0.3), false, 1.0)
	Hud.text(self, Vector2(tag.position.x, tag.position.y + 16.0 * k), L("EXH. %d", "சான்று %d") % n, 11.0 * k, Color(0.25, 0.2, 0.15), 700,
		HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)


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
