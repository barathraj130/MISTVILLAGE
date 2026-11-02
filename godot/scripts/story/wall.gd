extends Control
## The wall in Karthik's room (GAME_DESIGN.md §8 rule 5): the deduction board as a cork board he works at himself.
## Along the bottom, what he has to pin: papers from his pocket (the warrant, the FIR), photos and recordings off his
## phone, and cards he wrote from memory (what the inspector put on the table). Drag one up onto the board to pin it;
## drag a pin to move it; drag with the right button from one pin to another to tie a red thread between them (again
## to untie it). Across the top, four questions he wants answered: who, how, when, why. Esc or E: step back.
## What's on the wall stays (state), and the story can ask how much is pinned and tied.

signal closed

const CORK := Color(0.71, 0.55, 0.36)
const CORK2 := Color(0.64, 0.48, 0.3)
const INK := Color(0.1, 0.1, 0.14)
const THREAD := Color(0.8, 0.08, 0.08)
const CARD := Vector2(170, 120)

var lang := "en"
var pool: Array = []                       # [{"id", "title": {en, ta}, "kind": paper | note | card | photo | recording,
                                           #   "tex"?, "body"?}]
var state := {"pins": {}, "threads": []}   # pins: id → Vector2 (board fraction); threads: [[a, b]]
var font: Font
var _drag := ""
var _drag_off := Vector2.ZERO
var _tie := ""
var _mouse := Vector2.ZERO
var _t := 0.0


func open(language: String) -> void:
	lang = language
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func add(item: Dictionary) -> void:
	for p in pool:
		if str(p["id"]) == str(item["id"]):
			return
	pool.append(item)


func pinned() -> int:
	return state["pins"].size()


func tied() -> int:
	return state["threads"].size()


# ---- layout ----
func _board() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(40.0, 40.0, vs.x - 80.0, vs.y - 250.0)


func _pin_rect(id: String) -> Rect2:
	var b := _board()
	var f: Vector2 = state["pins"][id]
	return Rect2(b.position + f * b.size - CARD * 0.5, CARD)


func _loose() -> Array:
	var out: Array = []
	for p in pool:
		if not state["pins"].has(str(p["id"])):
			out.append(p)
	return out


func _slot(i: int, n: int) -> Rect2:
	var vs := get_viewport_rect().size
	var w := CARD.x * 0.85
	var x0 := vs.x * 0.5 - n * (w + 16.0) * 0.5
	return Rect2(x0 + i * (w + 16.0), vs.y - 185.0, w, CARD.y * 0.85)


func _item(id: String) -> Dictionary:
	for p in pool:
		if str(p["id"]) == id:
			return p
	return {}


# ---- input ----
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse = e.position
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var loose := _loose()
		for i in loose.size():
			if _slot(i, loose.size()).has_point(e.position):
				_drag = str(loose[i]["id"])
				_drag_off = Vector2.ZERO
				accept_event()
				return
		for id in state["pins"].keys():
			if _pin_rect(id).has_point(e.position):
				_drag = id
				_drag_off = _pin_rect(id).get_center() - e.position
				accept_event()
				return
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _drag != "":
		var b := _board()
		var c: Vector2 = e.position + _drag_off
		if b.has_point(c):
			state["pins"][_drag] = ((c - b.position) / b.size).clamp(Vector2(0.06, 0.18), Vector2(0.94, 0.92))
		else:
			state["pins"].erase(_drag)                # (taken down again)
			_untie_all(_drag)
		_drag = ""
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT:
		var at := _pin_at(e.position)
		if e.pressed:
			_tie = at
		elif _tie != "":
			if at != "" and at != _tie:
				_toggle_thread(_tie, at)
			_tie = ""
	accept_event()


func _pin_at(p: Vector2) -> String:
	for id in state["pins"].keys():
		if _pin_rect(id).has_point(p):
			return id
	return ""


func _toggle_thread(a: String, b: String) -> void:
	for th in state["threads"]:
		if (th[0] == a and th[1] == b) or (th[0] == b and th[1] == a):
			state["threads"].erase(th)
			return
	state["threads"].append([a, b])


func _untie_all(id: String) -> void:
	var keep: Array = []
	for th in state["threads"]:
		if th[0] != id and th[1] != id:
			keep.append(th)
	state["threads"] = keep


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_E]:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().set_input_as_handled()
		closed.emit()


func _process(dt: float) -> void:
	if visible:
		_t += dt
		queue_redraw()


# ---- drawing ----
func _text(pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, s, align, w, size, col)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.12, 0.1, 0.09))
	var b := _board()
	draw_rect(b.grow(14.0), Color(0.35, 0.23, 0.13))          # the frame
	draw_rect(b, CORK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 900:                                             # the cork's grain
		draw_circle(b.position + Vector2(rng.randf() * b.size.x, rng.randf() * b.size.y), rng.randf_range(1.0, 2.5), CORK2)
	var qs := [L("WHO?", "யார்?"), L("HOW?", "எப்படி?"), L("WHEN?", "எப்போ?"), L("WHY?", "ஏன்?")]
	for i in 4:                                               # his four questions, in marker on index cards
		var r := Rect2(b.position.x + b.size.x * (0.07 + i * 0.235), b.position.y + 14.0, b.size.x * 0.16, 54.0)
		draw_rect(r, Color(0.97, 0.97, 0.94))
		_text(r.position + Vector2(0, 38), qs[i], 26, Color(0.15, 0.2, 0.5), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		draw_circle(r.position + Vector2(r.size.x * 0.5, 4), 5.0, Color(0.85, 0.15, 0.15))
	for th in state["threads"]:                               # red string, sagging a little
		if state["pins"].has(th[0]) and state["pins"].has(th[1]):
			var a: Vector2 = _pin_rect(th[0]).position + Vector2(CARD.x * 0.5, 6)
			var c: Vector2 = _pin_rect(th[1]).position + Vector2(CARD.x * 0.5, 6)
			var mid: Vector2 = (a + c) * 0.5 + Vector2(0, a.distance_to(c) * 0.08)
			var pts := PackedVector2Array()
			for k in 17:
				var u := k / 16.0
				pts.append(a.lerp(mid, u).lerp(mid.lerp(c, u), u))
			draw_polyline(pts, THREAD, 2.5, true)
	if _tie != "" and state["pins"].has(_tie):
		draw_line(_pin_rect(_tie).position + Vector2(CARD.x * 0.5, 6), _mouse, THREAD, 2.0)
	for id in state["pins"].keys():
		if id != _drag:
			_card(_item(id), _pin_rect(id), true)
	draw_rect(Rect2(0, vs.y - 210.0, vs.x, 210.0), Color(0, 0, 0, 0.35))
	var loose := _loose()
	for i in loose.size():
		if str(loose[i]["id"]) != _drag:
			_card(loose[i], _slot(i, loose.size()), false)
	if loose.is_empty():
		_text(Vector2(0, vs.y - 120.0), L("Everything he has is on the wall.", "அவர் கிட்ட இருக்கறது எல்லாம் சுவத்துல."), 18, Color(1, 1, 1, 0.5), vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _drag != "":
		_card(_item(_drag), Rect2(_mouse + _drag_off - CARD * 0.5, CARD), false)
	_text(Vector2(0, vs.y - 18.0), L("drag to pin  ·  right-drag between two pins: thread  ·  E: step back",
		"இழுத்து குத்துங்க  ·  வலது பட்டன் இழுத்தா: நூல்  ·  E: பின்னால"), 14, Color(1, 1, 1, 0.45), vs.x, HORIZONTAL_ALIGNMENT_CENTER)


func _card(it: Dictionary, r: Rect2, pin: bool) -> void:
	if it.is_empty():
		return
	var k := str(it.get("kind", "card"))
	draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.3))
	var col := {"note": Color(0.98, 0.93, 0.62), "photo": Color(0.97, 0.97, 0.97), "recording": Color(0.92, 0.9, 0.95),
		"card": Color(0.98, 0.98, 0.95)}.get(k, Color(0.96, 0.95, 0.9)) as Color
	draw_rect(r, col)
	if it.has("tex"):
		draw_texture_rect(it["tex"], Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, r.size.y - 40)), false)
	elif k == "recording":
		for j in 14:
			var h := 6.0 + 20.0 * absf(sin(j * 1.9))
			draw_rect(Rect2(r.position.x + 16.0 + j * 10.0, r.position.y + 40.0 - h * 0.5, 5.0, h), Color(0.75, 0.2, 0.2))
	elif k == "card":
		for j in 3:
			draw_line(r.position + Vector2(10, 46 + j * 18), r.position + Vector2(r.size.x - 10, 46 + j * 18), Color(0.6, 0.75, 0.9, 0.6), 1.0)
		draw_multiline_string(font, r.position + Vector2(10, 44), t_(it.get("body", "")), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 20.0, 13, 3, Color(0.15, 0.2, 0.5))
	else:
		for j in 4:
			draw_line(r.position + Vector2(12, 30 + j * 14), r.position + Vector2(r.size.x - 12 - (30 if j == 3 else 0), 30 + j * 14), Color(0, 0, 0, 0.15), 2.0)
	_text(Vector2(r.position.x + 6.0, r.end.y - 10.0), t_(it.get("title", "")), 13, INK, r.size.x - 12.0)
	if pin:
		draw_circle(r.position + Vector2(r.size.x * 0.5, 6), 6.0, Color(0.85, 0.15, 0.15))
		draw_circle(r.position + Vector2(r.size.x * 0.5 - 1.5, 4.5), 2.0, Color(1, 0.6, 0.6))
