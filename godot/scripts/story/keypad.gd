extends Control
## A thing with a PIN, worked by him up close (story.gd, the "keypad" step): Bala's key programmer. Two looks:
##   clue    something he found that may hold the code: a note, a photo (its title and what he sees), E or Esc to stop
##   device  its screen: ENTER PIN, four digits (the number keys, or the pad with the mouse), Enter tries it,
##           Backspace rubs one out, Esc steps back. Wrong: WRONG PIN, the digits shake and clear. Right: its log,
##           line by line (the thing it unlocks); then E, Enter or Esc closes it.

signal closed
signal tried(ok: bool)

var lang := "en"
var font: Font
var mode := ""                             # "clue" | "device"
var title := ""
var body := ""
var device_name := ""
var code := ""
var log_lines: Array = []                  # what it shows once open
var typed := ""
var opened := false
var _shake := 0.0
var _wrong := 0.0
var _t := 0.0
var _keys := {}


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func show_clue(t: String, b: String) -> void:
	mode = "clue"
	title = t
	body = b
	_open()


func show_device(name: String, pin: String, lines: Array, already_open := false) -> void:
	mode = "device"
	device_name = name
	code = pin
	log_lines = lines
	typed = ""
	opened = already_open
	_open()


func _open() -> void:
	_t = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func press(k: String) -> void:
	if mode != "device" or opened:
		return
	if k == "back":
		typed = typed.left(maxi(0, typed.length() - 1))
	elif k == "ok":
		if typed.length() < 4:
			return
		if typed == code:
			opened = true
			_t = 0.0
			tried.emit(true)
		else:
			_shake = 0.5
			_wrong = 1.4
			typed = ""
			tried.emit(false)
	elif typed.length() < 4:
		typed += k
	queue_redraw()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	_shake = maxf(0.0, _shake - dt)
	_wrong = maxf(0.0, _wrong - dt)
	queue_redraw()
	if _t < 0.2:
		return
	for i in 10:                                         # the number keys (and the keypad's)
		var down := Input.is_key_pressed(KEY_0 + i) or Input.is_key_pressed(KEY_KP_0 + i)
		if down and not _keys.get(i, false):
			press(str(i))
		_keys[i] = down
	for pair in [[KEY_BACKSPACE, "back"], [KEY_ENTER, "ok"], [KEY_KP_ENTER, "ok"], [KEY_ESCAPE, "esc"], [KEY_E, "e"]]:
		var down := Input.is_key_pressed(pair[0])
		if down and not _keys.get(pair[1], false):
			if pair[1] == "esc" or (pair[1] == "e" and (mode == "clue" or opened)) or (pair[1] == "ok" and opened):
				_keys[pair[1]] = down
				close()
				return
			press(pair[1])
		_keys[pair[1]] = down


func _pad_rects(dev: Rect2) -> Array:
	var out := []
	var labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "back", "0", "ok"]
	var w := 74.0
	var h := 54.0
	var x0 := dev.position.x + (dev.size.x - 3 * w - 2 * 12.0) / 2.0
	var y0 := dev.position.y + 230.0
	for i in labels.size():
		out.append([labels[i], Rect2(x0 + (i % 3) * (w + 12.0), y0 + (i / 3) * (h + 10.0), w, h)])
	return out


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and mode == "device" and not opened:
		for pr in _pad_rects(_dev_rect()):
			if (pr[1] as Rect2).has_point(e.position):
				press(str(pr[0]))
	accept_event()


func _dev_rect() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x / 2.0 - 210.0, s.y / 2.0 - 300.0, 420.0, 600.0)


func _draw() -> void:
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
	if mode == "clue":
		var r := Rect2(s.x / 2.0 - 320.0, s.y / 2.0 - 170.0, 640.0, 340.0)
		draw_rect(r, Color(0.96, 0.94, 0.86))
		draw_rect(r, Color(0.3, 0.25, 0.2), false, 3.0)
		draw_string(font, r.position + Vector2(28, 52), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56, 26, Color(0.15, 0.12, 0.1))
		draw_multiline_string(font, r.position + Vector2(28, 100), body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56, 22, -1, Color(0.2, 0.18, 0.15))
		draw_string(font, r.position + Vector2(28, r.size.y - 22), L("E / Esc: put it back", "E / Esc: திரும்ப வை"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.36, 0.3))
		return
	var dev := _dev_rect()
	dev.position.x += sin(_shake * 60.0) * 10.0 * _shake
	draw_rect(dev, Color(0.32, 0.34, 0.37))
	draw_rect(dev.grow(-6), Color(0.24, 0.25, 0.28))
	draw_string(font, dev.position + Vector2(24, 34), device_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.77, 0.8))
	var scr := Rect2(dev.position + Vector2(24, 50), Vector2(dev.size.x - 48, 160))
	if opened:
		scr.size.y = dev.size.y - 110
	draw_rect(scr, Color(0.06, 0.16, 0.12))
	var g := Color(0.45, 0.95, 0.6)
	if opened:
		draw_string(font, scr.position + Vector2(14, 28), L("KEY LOG", "சாவி பதிவு"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, g)
		var shown := mini(log_lines.size(), int(_t * 2.5) + 1)   # (it scrolls up, line by line)
		var y := 60.0
		for i in shown:
			draw_multiline_string(font, scr.position + Vector2(14, y), str(log_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, scr.size.x - 28, 15, -1, g)
			y += 46.0
		draw_string(font, Vector2(dev.position.x + 24, dev.end.y - 22), L("E / Enter: close", "E / Enter: மூடு"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.77, 0.8))
		return
	draw_string(font, scr.position + Vector2(14, 34), L("ENTER PIN", "PIN போடுங்க"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, g)
	var dots := ""
	for i in 4:
		dots += ("●  " if i < typed.length() else "_  ")
	draw_string(font, scr.position + Vector2(14, 96), dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, g)
	if _wrong > 0.0:
		draw_string(font, scr.position + Vector2(14, 140), L("WRONG PIN", "தப்பான PIN"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.4, 0.35))
	for pr in _pad_rects(dev):
		var rr: Rect2 = pr[1]
		draw_rect(rr, Color(0.42, 0.44, 0.48))
		var lab := str(pr[0])
		lab = "⌫" if lab == "back" else ("OK" if lab == "ok" else lab)
		draw_string(font, rr.position + Vector2(0, 36), lab, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 24, Color(0.95, 0.95, 0.97))
	draw_string(font, Vector2(dev.position.x + 24, dev.end.y - 22), L("Numbers, Enter · Esc: step back", "எண்கள், Enter · Esc: பின்னாடி"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.77, 0.8))
