extends Control
## A shop's counter: its shelf as a list (goods.gd STOCK for that kind of shop), each with − and + (the mouse, or
## ↑↓ to choose and ←→ for how many), the total against his wallet; Enter pays and it goes in his bag (B), Esc
## leaves. Prices and names in English or Tamil.

const Goods := preload("res://scripts/city/goods.gd")

signal finished(bought: Dictionary)          # {id: count}, empty if he left

var lang := "en"
var font: Font
var title := ""
var shelf: Array = []                        # the ids on sale
var counts: Dictionary = {}
var money := 0
var msg := ""
var _sel := 0
var _keys := {}
var _t := 0.0


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func open(shop_title: String, ids: Array, wallet: int) -> void:
	title = shop_title
	shelf = ids
	counts = {}
	money = wallet
	msg = ""
	_sel = 0
	_t = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func total() -> int:
	var n := 0
	for id in counts:
		n += int(Goods.GOODS[id]["price"]) * int(counts[id])
	return n


func change(i: int, by: int) -> void:
	var id: String = shelf[i]
	counts[id] = clampi(int(counts.get(id, 0)) + by, 0, 9)
	if int(counts[id]) == 0:
		counts.erase(id)
	msg = ""


func pay() -> void:
	if counts.is_empty():
		msg = L("Nothing in the basket.", "கூடையில எதுவும் இல்ல.")
		return
	if total() > money:
		msg = L("Not enough in your wallet.", "பர்ஸ்ல போதுமான பணம் இல்ல.")
		return
	var out := counts.duplicate()
	_close()
	finished.emit(out)


func leave() -> void:
	_close()
	finished.emit({})


func _close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _row(i: int) -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x / 2.0 - 360.0, 140.0 + i * 54.0, 720.0, 46.0)


func _btn(i: int, plus: bool) -> Rect2:
	var r := _row(i)
	return Rect2(r.end.x - (60.0 if plus else 150.0), r.position.y + 6.0, 40.0, 34.0)


func _pay_btn(k: int) -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(s.x / 2.0 + (10.0 if k == 1 else -230.0), s.y - 90.0, 220.0, 54.0)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in shelf.size():
			if _btn(i, true).has_point(e.position):
				_sel = i
				change(i, 1)
			elif _btn(i, false).has_point(e.position):
				_sel = i
				change(i, -1)
			elif _row(i).has_point(e.position):
				_sel = i
		if _pay_btn(1).has_point(e.position):
			pay()
		elif _pay_btn(0).has_point(e.position):
			leave()
	accept_event()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	queue_redraw()
	if _t < 0.3:
		return
	for pair in [[KEY_UP, "up"], [KEY_DOWN, "down"], [KEY_RIGHT, "plus"], [KEY_LEFT, "minus"], [KEY_ENTER, "pay"],
			[KEY_KP_ENTER, "pay"], [KEY_ESCAPE, "leave"]]:
		var down := Input.is_key_pressed(pair[0])
		if down and not _keys.get(pair[1], false):
			match pair[1]:
				"up":
					_sel = maxi(_sel - 1, 0)
				"down":
					_sel = mini(_sel + 1, shelf.size() - 1)
				"plus":
					change(_sel, 1)
				"minus":
					change(_sel, -1)
				"pay":
					pay()
				"leave":
					leave()
		_keys[pair[1]] = down


func _draw() -> void:
	var s := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.96, 0.95, 0.92, 0.97))
	draw_string(font, Vector2(s.x / 2.0 - 400.0, 64.0), title, HORIZONTAL_ALIGNMENT_CENTER, 800.0, 30, Color(0.15, 0.12, 0.1))
	draw_string(font, Vector2(s.x / 2.0 - 400.0, 100.0), L("In your wallet: ₹%d" % money, "பர்ஸ்ல: ₹%d" % money), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 18, Color(0.35, 0.33, 0.3))
	for i in shelf.size():
		var id: String = shelf[i]
		var g: Dictionary = Goods.GOODS[id]
		var r := _row(i)
		draw_rect(r, Color(1, 1, 1))
		draw_rect(r, Color(0.15, 0.45, 0.3) if i == _sel else Color(0.82, 0.8, 0.76), false, 3.0 if i == _sel else 1.0)
		draw_string(font, r.position + Vector2(16, 30), Goods.name_of(id, lang), HORIZONTAL_ALIGNMENT_LEFT, 430.0, 18, Color(0.15, 0.13, 0.1))
		draw_string(font, r.position + Vector2(450, 30), "₹%d" % int(g["price"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.15, 0.45, 0.3))
		for plus in [false, true]:
			var b := _btn(i, plus)
			draw_rect(b, Color(0.88, 0.86, 0.82))
			draw_string(font, b.position + Vector2(0, 25), "+" if plus else "−", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 22, Color(0.15, 0.13, 0.1))
		draw_string(font, Vector2(r.end.x - 108.0, r.position.y + 30.0), str(int(counts.get(id, 0))), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 20, Color(0.15, 0.13, 0.1))
	var tot := total()
	draw_string(font, Vector2(s.x / 2.0 - 400.0, s.y - 110.0), L("Total: ₹%d" % tot, "மொத்தம்: ₹%d" % tot), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 22, Color(0.75, 0.15, 0.1) if tot > money else Color(0.15, 0.13, 0.1))
	if msg != "":
		draw_string(font, Vector2(s.x / 2.0 - 400.0, s.y - 140.0), msg, HORIZONTAL_ALIGNMENT_CENTER, 800.0, 16, Color(0.75, 0.15, 0.1))
	draw_string(font, Vector2(s.x / 2.0 - 400.0, s.y - 160.0), L("↑↓ choose · ←→ how many · Enter pay · Esc leave", "↑↓ தேர்வு · ←→ எத்தனை · Enter கட்டு · Esc வெளிய"), HORIZONTAL_ALIGNMENT_CENTER, 800.0, 14, Color(0.45, 0.43, 0.4))
	for k in 2:
		var b := _pay_btn(k)
		draw_rect(b, Color(0.15, 0.45, 0.3) if k == 1 else Color(0.6, 0.58, 0.55))
		draw_string(font, b.position + Vector2(0, 35), L("Pay (Enter)", "கட்டு (Enter)") if k == 1 else L("Leave (Esc)", "வெளிய போ (Esc)"), HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 18, Color.WHITE)
