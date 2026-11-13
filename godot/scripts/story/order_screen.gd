extends Control
## Ordering at an eatery (story/food.json "eateries"; tasks.gd hands meals out to it): the menu as a restaurant's
## own card, then the food at his table, then the bill.
##   menu       the place's name and kind, the wallet; its categories as tabs; a card per dish (a picture of the dish
##              itself, rendered from food_kit.gd, its name, a line about it, the price, Add or − n +); the order
##              on the right (each line, the total); Place order (not past the wallet), Leave restaurant (Esc)
##   preparing  a moment while the kitchen makes it
##   eating     the order on his table (food_kit.gd at his seat), Karthik eating it (his SitEat), the plate going down
##   bill       what he had and the total; Pay: the money goes (tasks.gd's result "paid"), and the meal's in him
## Keyboard: Tab / ← → the category, ↑ ↓ the dish, + − Enter (place the order, pay), Esc leave.

signal finished(result: Dictionary)

const Food := preload("res://scripts/story/food.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Style := preload("res://scripts/ui/hud_style.gd")
const IVORY := Color("#F4F0E6")
const PANEL := Color("#FFFDF7")
const FOREST := Color("#174B35")
const SAGE := Color("#A9B9A1")
const GOLD := Color("#C69A45")
const INK := Color("#252923")
const INK2 := Color("#77776E")
const WARN := Color("#B85C45")

var story: Node
var lang := "en"
var skip := false
var shots := ""
var spec := {}
var eatery := ""
var menu: Array = []                                   # [{cat, items: [[dish, price]]}]
var tab := 0
var focus := 0                                         # the dish card the keyboard is on
var cart := {}                                         # dish → how many
var state := "menu"
var _thumbs := {}                                      # dish → its picture
var _hover := ""
var _msg := ""
var _msg_bad := false
var _t := 0.0
var _rects := {}
var _plate: Node3D
var _bites := 0


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func begin(s: Dictionary) -> void:
	spec = s
	eatery = str(s.get("eatery", ""))
	menu = Food.menu(eatery)
	if menu.is_empty():                                  # (a place not in food.json: the step's own list)
		var items := []
		for m in s.get("menu", []):
			items.append([str(m.get("food", "meals")), int(m.get("price", 0)), m.get("name", {})])
		menu = [{"cat": "meals", "items": items}]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = true
	state = "menu"
	cart.clear()
	tab = 0
	focus = 0
	_msg = ""
	_make_thumbs()
	grab_focus()
	queue_redraw()
	if skip:                                             # (testing: two of the first dish and one more, as you'd order)
		await get_tree().create_timer(1.6).timeout
		var its := _items()
		_press("add:" + str(its[0][0]))
		if its.size() > 1:
			_press("add:" + str(its[1][0]))
		_press("tab:%d" % (menu.size() - 1))
		await get_tree().create_timer(0.5).timeout
		_shot("order_tab_" + eatery)
		_press("tab:0")
		await get_tree().create_timer(0.4).timeout
		_press("order")


func _items() -> Array:
	return menu[tab]["items"] if tab < menu.size() else []


func _name(it: Array) -> String:
	if it.size() > 2 and it[2] is Dictionary and not (it[2] as Dictionary).is_empty():
		return str(it[2].get(lang, it[2].get("en", "")))
	return Food.name_of(str(it[0]), lang)


func _price(dish: String) -> int:
	for c in menu:
		for it in c["items"]:
			if str(it[0]) == dish:
				return int(it[1])
	return 0


func _total() -> int:
	var t := 0
	for d in cart:
		t += _price(d) * int(cart[d])
	return t


func _wallet() -> int:
	return int(spec.get("wallet", 1 << 30))


# ---- pictures of the dishes (rendered once each, in a little world of their own) ----

func _make_thumbs() -> void:
	var todo := []
	for c in menu:
		for it in c["items"]:
			if not _thumbs.has(str(it[0])) and not str(it[0]) in todo:
				todo.append(str(it[0]))
	if todo.is_empty():
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 200)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.25, 0.17)       # a teak table top under the plate
	env.ambient_light_color = Color(1.0, 0.95, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60), deg_to_rad(25), 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	cam.position = Vector3(0, 0.33, 0.36)
	cam.look_at(Vector3(0, 0.0, -0.025))
	for d in todo:
		var dish := Kit.build(d)
		vp.add_child(dish)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			return
		_thumbs[d] = ImageTexture.create_from_image(vp.get_texture().get_image())
		dish.queue_free()
		queue_redraw()
	vp.queue_free()


# ---- input ----

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := ""
		for k in _rects:
			if (_rects[k] as Rect2).has_point(e.position):
				h = k
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for k in _rects:
			if (_rects[k] as Rect2).has_point(e.position):
				_press(k)
				break
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var items := _items()
	match e.keycode:
		KEY_ESCAPE:
			if state == "menu":
				_press("leave")
		KEY_TAB, KEY_RIGHT:
			if state == "menu":
				tab = (tab + 1) % menu.size()
				focus = 0
		KEY_LEFT:
			if state == "menu":
				tab = posmod(tab - 1, menu.size())
				focus = 0
		KEY_DOWN:
			focus = mini(focus + 1, items.size() - 1)
		KEY_UP:
			focus = maxi(focus - 1, 0)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_SPACE:
			if state == "menu" and focus < items.size():
				_press("add:" + str(items[focus][0]))
		KEY_MINUS, KEY_KP_SUBTRACT:
			if state == "menu" and focus < items.size():
				_press("sub:" + str(items[focus][0]))
		KEY_ENTER, KEY_KP_ENTER:
			_press("order" if state == "menu" else ("pay" if state == "bill" else ""))
	get_viewport().set_input_as_handled()
	queue_redraw()


func _press(k: String) -> void:
	if k.begins_with("tab:") and state == "menu":
		tab = int(k.get_slice(":", 1))
		focus = 0
	elif k.begins_with("add:") and state == "menu":
		var d := k.get_slice(":", 1)
		if _total() + _price(d) > _wallet():
			_say(L("That's more than you have in your wallet.", "பர்ஸ்ல அவ்வளவு பணம் இல்லை."), true)
		else:
			cart[d] = int(cart.get(d, 0)) + 1
			_say("", false)
	elif k.begins_with("sub:") and state == "menu":
		var d2 := k.get_slice(":", 1)
		cart[d2] = int(cart.get(d2, 0)) - 1
		if int(cart[d2]) <= 0:
			cart.erase(d2)
	elif k == "order" and state == "menu":
		if cart.is_empty():
			_say(L("Add something to your order first.", "முதல்ல ஏதாவது ஆர்டர் பண்ணு."), true)
		else:
			_place()
	elif k == "leave" and state == "menu":
		_finish({"paid": 0, "ate": false})
	elif k == "pay" and state == "bill":
		_pay()
	elif k == "finish" and state == "eating":
		_to_bill()
	queue_redraw()


func _say(s: String, bad: bool) -> void:
	_msg = s
	_msg_bad = bad


# ---- the order, the food, the bill ----

func _place() -> void:
	state = "preparing"
	_t = 0.0
	_shot("order_menu_" + eatery)
	await get_tree().create_timer(0.6 if skip else 2.2).timeout
	_serve()


func _main_dish() -> String:                           # what goes on his plate: the first thing that isn't a drink
	for d in cart:
		if not d in ["tea", "filter_coffee", "fresh_lime"]:
			return d
	return cart.keys()[0]


## The food on his table: the cast Karthik sits at the place's Mark_karthik_eat; the plate where his hand goes.
func _serve() -> void:
	state = "eating"
	_t = 0.0
	visible = true
	var guy = story.cast.get("karthik") if story else null
	if story and story.has_method("_dish"):
		story._dish("")                                 # (the room's own built-in dishes away)
	if guy and guy.model:
		var m: Node3D = guy.model
		var fwd := m.global_basis.z.normalized()
		var right := -m.global_basis.x.normalized()
		var seat: Node3D = guy
		_plate = Kit.build(_main_dish())
		story.room.add_child(_plate)
		_plate.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), seat.global_position + fwd * 0.42 + right * 0.1 + Vector3(0, 0.79, 0))
		guy.play("SitEat")
	queue_redraw()
	await get_tree().create_timer(0.8).timeout
	_shot("order_served_" + eatery)


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if state == "eating" and _plate:                    # a bite every cycle of his hand
		var parts: Array = _plate.get_meta("parts")
		var n := int(_t / 2.67)
		while _bites < n and _bites < parts.size() * 2:
			for p in parts:
				if int(p["left"]) > 0:
					Kit.bite(p)
					break
			_bites += 1
		if _t > (3.0 if skip else 8.0):
			_to_bill()
	if state in ["preparing", "eating"]:
		queue_redraw()


func _to_bill() -> void:
	if state != "eating":
		return
	state = "bill"
	var guy = story.cast.get("karthik") if story else null
	if guy:
		guy.play("Sit")
	queue_redraw()
	_shot("order_bill_" + eatery)
	if skip:
		await get_tree().create_timer(0.6).timeout
		_pay()


func _pay() -> void:
	var energy := 0.0
	for d in cart:
		energy += float(Food.dish(d).get("energy", 40)) * int(cart[d])
	_finish({"paid": _total(), "ate": true, "meal": "", "minutes": int(spec.get("minutes", 20)), "energy": minf(energy, 80.0),
		"order": cart.duplicate()})


func _finish(res: Dictionary) -> void:
	if is_instance_valid(_plate):
		_plate.queue_free()
	visible = false
	state = "done"
	finished.emit(res)


func _shot(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(shots + "/" + name + ".jpg", 0.85)


# ---- drawing ----

func _box(r: Rect2, col: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0, shadow := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(maxf(bw, 1.0)))
	if shadow > 0.0:
		sb.shadow_color = Color(0, 0, 0, 0.16)
		sb.shadow_size = int(shadow)
	draw_style_box(sb, r)


func _txt(at: Vector2, s: String, size: float, col: Color, weight := 400, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(Style.font(weight), at, s, align, w, int(size), col)


func _button(key: String, r: Rect2, label: String, primary: bool, k: float, enabled := true) -> void:
	var hov := _hover == key and enabled
	var col := (FOREST.lightened(0.08) if hov else FOREST) if primary else (Color(INK, 0.06) if hov else Color(0, 0, 0, 0))
	if not enabled:
		col = Color(SAGE, 0.5) if primary else Color(0, 0, 0, 0)
	_box(r, col, 10 * k, Color(INK, 0.25) if not primary else Color(0, 0, 0, 0), 0.0 if primary else maxf(k, 1.0))
	_txt(r.position + Vector2(0, r.size.y * 0.5 + 6.5 * k), label, 17 * k, (Color.WHITE if enabled else Color(1, 1, 1, 0.8)) if primary else INK,
		600, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if enabled:
		_rects[key] = r


func _draw() -> void:
	_rects.clear()
	var k := Style.s(self)
	var vs := get_viewport_rect().size
	if state == "eating":                               # the table in view: only a small card
		var r := Rect2(Vector2(vs.x - 400 * k - 32 * k, vs.y * 0.62), Vector2(400 * k, 118 * k))
		_box(r, Color(PANEL, 0.97), 14 * k, Color(0, 0, 0, 0), 0, 12 * k)
		_txt(r.position + Vector2(24 * k, 38 * k), L("Enjoy your meal", "நல்லா சாப்பிடுங்க"), 20 * k, INK, 600)
		_txt(r.position + Vector2(24 * k, 64 * k), Food.name_of(_main_dish(), lang), 15 * k, INK2, 500)
		_button("finish", Rect2(r.position + Vector2(24 * k, 76 * k), Vector2(170 * k, 32 * k)), L("Ask for the bill", "பில் கேளு"), false, k)
		return
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
	var pw := minf(vs.x - 80 * k, 1500 * k)
	var ph := minf(vs.y - 80 * k, 880 * k)
	var p := Rect2((vs - Vector2(pw, ph)) * 0.5, Vector2(pw, ph))
	_box(p, IVORY, 18 * k, Color(0, 0, 0, 0), 0, 24 * k)
	var pad := 36 * k
	# header: the place, its kind, the wallet
	var title := str(spec.get("title", {}).get(lang, spec.get("title", {}).get("en", "")) if spec.get("title") is Dictionary else spec.get("title", ""))
	_txt(p.position + Vector2(pad, pad + 26 * k), title, 30 * k, INK, 700, pw * 0.6)
	_txt(p.position + Vector2(pad, pad + 54 * k), Food.kind_of(eatery, lang), 16 * k, INK2, 500)
	var wr := Rect2(Vector2(p.end.x - pad - 220 * k, p.position.y + pad + 4 * k), Vector2(220 * k, 44 * k))
	_box(wr, PANEL, 22 * k, Color(GOLD, 0.6), maxf(k, 1.0))
	_txt(wr.position + Vector2(0, 29 * k), L("Wallet  ", "பர்ஸ்  ") + "₹" + _money(_wallet()), 17 * k, INK, 600, wr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var top := p.position.y + pad + 84 * k
	if state == "preparing":
		var c := p.get_center()
		_txt(Vector2(p.position.x, c.y - 10 * k), L("Preparing your order…", "உங்கள் ஆர்டர் தயாராகிறது…"), 26 * k, INK, 600, pw, HORIZONTAL_ALIGNMENT_CENTER)
		var bar := Rect2(Vector2(c.x - 160 * k, c.y + 20 * k), Vector2(320 * k, 6 * k))
		_box(bar, Color(INK, 0.1), 3 * k)
		_box(Rect2(bar.position, Vector2(bar.size.x * clampf(_t / 2.2, 0.0, 1.0), bar.size.y)), FOREST, 3 * k)
		return
	if state == "bill":
		_draw_bill(p, k)
		return
	# the categories
	var x := p.position.x + pad
	for i in menu.size():
		var name := Food.category(str(menu[i]["cat"]), lang)
		var tw := Style.width_of(name, 16 * k, 600) + 36 * k
		var tr := Rect2(Vector2(x, top), Vector2(tw, 40 * k))
		var on := i == tab
		_box(tr, FOREST if on else (Color(INK, 0.07) if _hover == "tab:%d" % i else Color(0, 0, 0, 0)), 20 * k, Color(INK, 0.2), 0.0 if on else maxf(k, 1.0))
		_txt(tr.position + Vector2(0, 26 * k), name, 16 * k, Color.WHITE if on else INK, 600, tw, HORIZONTAL_ALIGNMENT_CENTER)
		_rects["tab:%d" % i] = tr
		x += tw + 10 * k
	# the dish cards
	var sum_w := 400 * k
	var grid := Rect2(Vector2(p.position.x + pad, top + 64 * k), Vector2(pw - 2 * pad - sum_w - 28 * k, p.end.y - pad - top - 64 * k))
	var cols := 3
	var gap := 20 * k
	var cw := (grid.size.x - gap * (cols - 1)) / cols
	var ch := minf(cw * 1.05, (grid.size.y - gap) / 2.0)
	var items := _items()
	for i in items.size():
		var d := str(items[i][0])
		var cr := Rect2(grid.position + Vector2((i % cols) * (cw + gap), (i / cols) * (ch + gap)), Vector2(cw, ch))
		if cr.end.y > grid.end.y + 1:
			break
		var foc := i == focus
		_box(cr, PANEL, 14 * k, GOLD if foc else Color(INK, 0.1), 2 * k if foc else maxf(k, 1.0), 6 * k)
		var img := Rect2(cr.position + Vector2(8 * k, 8 * k), Vector2(cw - 16 * k, ch * 0.5))
		if _thumbs.has(d):
			draw_texture_rect(_thumbs[d], img, false)
		else:
			_box(img, Color(SAGE, 0.35), 10 * k)
		var ty := img.end.y + 30 * k
		_txt(Vector2(cr.position.x + 18 * k, ty), _name(items[i]), 19 * k, INK, 600, cw - 36 * k)
		var desc: Dictionary = Food.dish(d).get("desc", {})
		draw_multiline_string(Style.font(400), Vector2(cr.position.x + 18 * k, ty + 24 * k), str(desc.get(lang, desc.get("en", ""))),
			HORIZONTAL_ALIGNMENT_LEFT, cw - 36 * k, int(14 * k), 2, INK2)
		var by := cr.end.y - 18 * k - 40 * k
		_txt(Vector2(cr.position.x + 18 * k, by + 28 * k), "₹" + _money(int(items[i][1])), 20 * k, GOLD.darkened(0.25), 700)
		var n := int(cart.get(d, 0))
		if n == 0:
			_button("add:" + d, Rect2(Vector2(cr.end.x - 18 * k - 110 * k, by), Vector2(110 * k, 40 * k)), L("Add", "சேர்"), true, k)
		else:
			var sx := cr.end.x - 18 * k - 130 * k
			_button("sub:" + d, Rect2(Vector2(sx, by), Vector2(40 * k, 40 * k)), "−", false, k)
			_txt(Vector2(sx + 40 * k, by + 27 * k), str(n), 18 * k, INK, 700, 50 * k, HORIZONTAL_ALIGNMENT_CENTER)
			_button("add:" + d, Rect2(Vector2(sx + 90 * k, by), Vector2(40 * k, 40 * k)), "+", true, k)
	# the order so far
	var sr := Rect2(Vector2(p.end.x - pad - sum_w, top + 64 * k), Vector2(sum_w, grid.size.y))
	_box(sr, PANEL, 14 * k, Color(INK, 0.1), maxf(k, 1.0))
	_txt(sr.position + Vector2(24 * k, 40 * k), L("Your order", "உங்கள் ஆர்டர்"), 22 * k, INK, 700)
	var y := sr.position.y + 80 * k
	if cart.is_empty():
		_txt(Vector2(sr.position.x + 24 * k, y), L("Nothing yet. Add a dish.", "இன்னும் எதுவும் இல்லை."), 15 * k, INK2, 400)
	for d in cart:
		_txt(Vector2(sr.position.x + 24 * k, y), "%s  × %d" % [Food.name_of(d, lang), int(cart[d])], 16 * k, INK, 500, sum_w - 140 * k)
		_txt(Vector2(sr.end.x - 24 * k - 110 * k, y), "₹" + _money(_price(d) * int(cart[d])), 16 * k, INK, 600, 110 * k, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 30 * k
	var ty2 := sr.end.y - 24 * k - 48 * k * 2 - 14 * k - 46 * k
	draw_line(Vector2(sr.position.x + 24 * k, ty2 - 24 * k), Vector2(sr.end.x - 24 * k, ty2 - 24 * k), Color(INK, 0.12), maxf(k, 1.0))
	_txt(Vector2(sr.position.x + 24 * k, ty2 + 6 * k), L("Total", "மொத்தம்"), 18 * k, INK, 600)
	_txt(Vector2(sr.end.x - 24 * k - 150 * k, ty2 + 6 * k), "₹" + _money(_total()), 24 * k, INK, 700, 150 * k, HORIZONTAL_ALIGNMENT_RIGHT)
	if _msg != "":
		draw_multiline_string(Style.font(500), Vector2(sr.position.x + 24 * k, ty2 + 34 * k), _msg, HORIZONTAL_ALIGNMENT_LEFT, sum_w - 48 * k,
			int(14 * k), 2, WARN if _msg_bad else FOREST)
	_button("order", Rect2(Vector2(sr.position.x + 24 * k, sr.end.y - 24 * k - 48 * k * 2 - 14 * k), Vector2(sum_w - 48 * k, 48 * k)),
		L("Place order", "ஆர்டர் செய்"), true, k, not cart.is_empty())
	_button("leave", Rect2(Vector2(sr.position.x + 24 * k, sr.end.y - 24 * k - 48 * k), Vector2(sum_w - 48 * k, 48 * k)),
		L("Leave restaurant", "உணவகத்தை விட்டு வெளியேறு"), false, k)


func _draw_bill(p: Rect2, k: float) -> void:
	var w := 520 * k
	var r := Rect2(Vector2(p.get_center().x - w * 0.5, p.position.y + 150 * k), Vector2(w, p.size.y - 220 * k))
	_box(r, PANEL, 14 * k, Color(INK, 0.1), maxf(k, 1.0), 8 * k)
	_txt(r.position + Vector2(32 * k, 48 * k), L("Your bill", "உங்கள் பில்"), 26 * k, INK, 700)
	var y := r.position.y + 100 * k
	for d in cart:
		_txt(Vector2(r.position.x + 32 * k, y), "%s  × %d" % [Food.name_of(d, lang), int(cart[d])], 17 * k, INK, 500, w - 200 * k)
		_txt(Vector2(r.end.x - 32 * k - 130 * k, y), "₹" + _money(_price(d) * int(cart[d])), 17 * k, INK, 600, 130 * k, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 34 * k
	draw_line(Vector2(r.position.x + 32 * k, y), Vector2(r.end.x - 32 * k, y), Color(INK, 0.15), maxf(k, 1.0))
	_txt(Vector2(r.position.x + 32 * k, y + 40 * k), L("Total", "மொத்தம்"), 20 * k, INK, 600)
	_txt(Vector2(r.end.x - 32 * k - 160 * k, y + 40 * k), "₹" + _money(_total()), 26 * k, INK, 700, 160 * k, HORIZONTAL_ALIGNMENT_RIGHT)
	_txt(Vector2(r.position.x + 32 * k, y + 74 * k), L("Wallet after paying: ₹", "கொடுத்த பின் பர்ஸ்: ₹") + _money(_wallet() - _total()), 15 * k, INK2, 500)
	_button("pay", Rect2(Vector2(r.position.x + 32 * k, r.end.y - 32 * k - 52 * k), Vector2(w - 64 * k, 52 * k)),
		L("Pay ₹", "₹") + _money(_total()) + L("", " கொடு"), true, k)


func _money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	if s.length() > 3:                                   # Indian grouping: 1,23,456
		out = "," + s.right(3)
		s = s.left(s.length() - 3)
		while s.length() > 2:
			out = "," + s.right(2) + out
			s = s.left(s.length() - 2)
		out = s + out
	else:
		out = s
	return ("-" if n < 0 else "") + out
