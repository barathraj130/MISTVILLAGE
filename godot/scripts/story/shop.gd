extends Control
## A shop's counter (story.gd, the "shop" step): its racks as rows of things with their prices (a shirt, then
## something for the feet), one picked from each by a click (or the number keys, a row at a time), the total
## against his wallet. Enter (or Pay) pays and he wears them; Esc leaves with nothing. Each thing has a "smart"
## (0: a T-shirt, rubber slippers; 1 and up: what gets past a hotel door) and a colour he'll be seen in.

signal finished(bought: Array)                # the things paid for ([] if he left)

var lang := "en"
var font: Font
var title := ""
var rows: Array = []                          # [{"label": {en, ta}, "items": [{"name": {en, ta}, "price", "smart", "colour"}]}]
var picked: Array = []                        # an index per row (-1: none yet)
var money := 0
var msg := ""
var _t := 0.0
var _keys := {}
var _row := 0                                 # the row the number keys pick in


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	return str(d.get(lang, d.get("en", ""))) if d is Dictionary else str(d)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func open(shop_title: String, shop_rows: Array, wallet: int) -> void:
	title = shop_title
	rows = shop_rows
	picked = []
	for r in rows:
		picked.append(-1)
	money = wallet
	msg = ""
	_row = 0
	_t = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func total() -> int:
	var n := 0
	for r in rows.size():
		if picked[r] >= 0:
			n += int(rows[r]["items"][picked[r]]["price"])
	return n


func pay() -> void:
	for p in picked:
		if p < 0:
			msg = L("Pick one from each rack.", "ஒவ்வொரு ரேக்லயும் ஒண்ணு எடுங்க.")
			return
	if total() > money:
		msg = L("Not enough in the account.", "கணக்குல போதுமான பணம் இல்ல.")
		return
	var out: Array = []
	for r in rows.size():
		out.append(rows[r]["items"][picked[r]])
	_close()
	finished.emit(out)


func leave() -> void:
	_close()
	finished.emit([])


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _card(r: int, i: int) -> Rect2:
	var s := get_viewport_rect().size
	var n: int = rows[r]["items"].size()
	var w := 200.0
	var x0 := s.x / 2.0 - (n * w + (n - 1) * 16.0) / 2.0
	return Rect2(x0 + i * (w + 16.0), 150.0 + r * 230.0, w, 180.0)


func _btn(k: int) -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x / 2.0 + (10.0 if k == 1 else -230.0), s.y - 90.0, 220.0, 54.0)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for r in rows.size():
			for i in rows[r]["items"].size():
				if _card(r, i).has_point(e.position):
					picked[r] = i
					_row = mini(r + 1, rows.size() - 1)
					msg = ""
		if _btn(1).has_point(e.position):
			pay()
		elif _btn(0).has_point(e.position):
			leave()
	accept_event()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	queue_redraw()
	if _t < 0.3:
		return
	for i in 9:
		var down := Input.is_key_pressed(KEY_1 + i)
		if down and not _keys.get(i, false) and i < rows[_row]["items"].size():
			picked[_row] = i
			_row = mini(_row + 1, rows.size() - 1)
		_keys[i] = down
	for pair in [[KEY_ENTER, "pay"], [KEY_KP_ENTER, "pay"], [KEY_ESCAPE, "leave"]]:
		var down := Input.is_key_pressed(pair[0])
		if down and not _keys.get(pair[1], false):
			if pair[1] == "pay":
				pay()
			else:
				leave()
		_keys[pair[1]] = down


func _draw() -> void:
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.96, 0.95, 0.92, 0.97))
	draw_string(font, Vector2(s.x / 2.0 - 400.0, 64.0), title, HORIZONTAL_ALIGNMENT_CENTER, 800.0, 30, Color(0.15, 0.12, 0.1))
	draw_string(font, Vector2(s.x / 2.0 - 400.0, 100.0), L("In your account: ₹%d" % money, "உங்க கணக்குல: ₹%d" % money), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 18, Color(0.35, 0.33, 0.3))
	for r in rows.size():
		var c0 := _card(r, 0)
		draw_string(font, Vector2(c0.position.x, c0.position.y - 12.0), t_(rows[r]["label"]) + ("   (1–%d)" % rows[r]["items"].size() if r == _row else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.3, 0.28, 0.25))
		for i in rows[r]["items"].size():
			var it: Dictionary = rows[r]["items"][i]
			var cr := _card(r, i)
			draw_rect(cr, Color(1, 1, 1))
			draw_rect(cr, Color(0.15, 0.45, 0.3) if picked[r] == i else Color(0.8, 0.78, 0.74), false, 4.0 if picked[r] == i else 1.5)
			var sw := Rect2(cr.position + Vector2(20, 16), Vector2(cr.size.x - 40.0, 70.0))   # the thing's colour, folded on the shelf
			draw_rect(sw, Color.html(str(it.get("colour", "#888888"))))
			if str(it.get("pattern", "")) == "check":
				for k in 6:
					draw_line(Vector2(sw.position.x + k * sw.size.x / 6.0, sw.position.y), Vector2(sw.position.x + k * sw.size.x / 6.0, sw.end.y), Color(1, 1, 1, 0.35), 2.0)
					draw_line(Vector2(sw.position.x, sw.position.y + k * sw.size.y / 6.0), Vector2(sw.end.x, sw.position.y + k * sw.size.y / 6.0), Color(1, 1, 1, 0.35), 2.0)
			draw_multiline_string(font, cr.position + Vector2(14, 110), t_(it["name"]), HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 28.0, 15, 2, Color(0.15, 0.13, 0.1))
			draw_string(font, cr.position + Vector2(14, 166), "₹%d" % int(it["price"]) if int(it["price"]) > 0 else L("(what you have on)", "(போட்டிருக்கறது)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.15, 0.45, 0.3))
	var tot := total()
	draw_string(font, Vector2(s.x / 2.0 - 400.0, s.y - 110.0), L("Total: ₹%d" % tot, "மொத்தம்: ₹%d" % tot), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 22, Color(0.75, 0.15, 0.1) if tot > money else Color(0.15, 0.13, 0.1))
	if msg != "":
		draw_string(font, Vector2(s.x / 2.0 - 400.0, s.y - 140.0), msg, HORIZONTAL_ALIGNMENT_CENTER, 800.0, 16, Color(0.75, 0.15, 0.1))
	for k in 2:
		var b := _btn(k)
		draw_rect(b, Color(0.15, 0.45, 0.3) if k == 1 else Color(0.6, 0.58, 0.55))
		draw_string(font, b.position + Vector2(0, 35), L("Pay (Enter)", "கட்டு (Enter)") if k == 1 else L("Leave (Esc)", "வெளிய போ (Esc)"), HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 18, Color.WHITE)
