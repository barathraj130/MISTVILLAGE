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
##   meal   a meal: eating out, the menu with prices (paid from the wallet: result "paid"); at home, Amma's plate
##          (from the month's groceries); then eat it, item by item, off the banana leaf
## Every task can carry a tip (advice from the owner, a boss, a hotel owner) shown above it.

signal finished(result: Dictionary)
signal stage_changed                            # (getting ready: the next chore is up)
signal dish_chosen(food: String)                # (a meal out: the dish picked from the menu, to put on his leaf)

const Kit := preload("res://scripts/ui/ui_kit.gd")
const Hud := preload("res://scripts/ui/hud_style.gd")
const Art := preload("res://scripts/ui/item_art.gd")
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

# the pointer and the keyboard's choice (the bank slip and the count: hover, pressed, focus)
var _mouse := Vector2(-1, -1)
var _held := false
var _focus := -1                                # bank slip: 0 Clear, 1 Submit; count: 0..7 a bundle, 8 / 9 the answers
var _closing := 0.0                             # the count: its answer shown a moment before it closes
var _closing_good := true
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
# the key box (hang, a key): which hook the mouse is over, the close look at the key in hand, the key flying back to
# his hand after a wrong hook (from, 0..1), where the press began (a click looks, a drag hangs), the hook it went on
var _hover := -1
var _inspect := false
var _ret_from := Vector2.ZERO
var _ret_t := -1.0
var _press_at := Vector2.ZERO
var _hung := -1
var _snd: AudioStreamPlayer
# the pockets: the keyboard's item, things on their way into the pocket (item → 0..1) or back to their place
var _pk_focus := -1
var _pk_in := {}
var _pk_back := {}
# ready
const ALL_CHORES := ["alarm", "brush", "bath", "dress", "eat", "pocket"]
var chores: Array = ALL_CHORES                  # this visit's chores (the morning is walked: a few at each place)
const CHORE_MIN := {"alarm": 0, "brush": 5, "bath": 12, "dress": 6, "eat": 12, "pocket": 3}
var chore := 0
var minutes := 0
var _prog := 0.0                                # this chore's progress 0..1
var _picked := {}                               # dress: shirt; pocket: items in; eat: idlis eaten
var shirt := ""
var reached_cap := false
var _pocket_items := ["wallet", "phone", "scooter key", "house key"]
var _drag_item := ""
# meal
var _meal_pick := -1                            # the dish chosen (-1: still reading the menu)
var _eaten := {}
var groom := preload("res://scripts/story/groom.gd").new()   # brushing and bathing as touch play
var scene_chore: Node = null                    # a chore done in the 3D room instead (brush3d.gd): its can(), begin()
var _away := false                              # …while it is: the panel hidden, the mouse the room's
var scene_meal: Node = null                     # a meal at home eaten at the table in 3D (dine3d.gd): no menu
var scene_order: Control = null                 # ordering at an eatery (order_screen.gd): the menu, the food, the bill
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
		chores = spec.get("chores", ALL_CHORES)
		chore = 0
		minutes = 0
		_prog = 0.0
		_picked = {}
		shirt = ""
		reached_cap = false
		if not chores.is_empty() and chores[0] in ["brush", "bath"]:
			groom.start(chores[0], _chore_rects()["area"], lang, self)
		_hand_over()
	if kind == "meal":
		_meal_pick = -1 if not spec.get("home", false) else 0
		_eaten = {}
		if scene_meal != null and scene_meal.can(spec):   # at home: Amma's food on the table, eaten there
			_away = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			scene_meal.lang = lang
			scene_meal.skip = testing
			scene_meal.finished.connect(func(res: Dictionary):
				_away = false
				mouse_filter = Control.MOUSE_FILTER_STOP
				_done(res), CONNECT_ONE_SHOT)
			scene_meal.begin(spec)
		elif scene_order != null and not spec.get("home", false) and spec.has("eatery"):
			_away = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			scene_order.lang = lang
			scene_order.skip = testing
			scene_order.finished.connect(func(res: Dictionary):
				_away = false
				mouse_filter = Control.MOUSE_FILTER_STOP
				_done(res), CONNECT_ONE_SHOT)
			scene_order.begin(spec)
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


func _k() -> float:
	return Hud.s(self)


## The bank slip: a sheet of paper in the middle, and the bar of actions under it.
func _slip() -> Rect2:
	var vs := get_viewport_rect().size
	var k := _k()
	var w := minf(940.0 * k, vs.x - 64.0 * k)
	var h := minf(600.0 * k, vs.y - 190.0 * k)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5 - 30.0 * k, w, h)


func _sign_box() -> Rect2:
	var p := _slip()
	var k := _k()
	return Rect2(p.end.x - 380.0 * k - 36.0 * k, p.end.y - 150.0 * k, 380.0 * k, 104.0 * k)


## The counter: one charcoal panel with the eight bundles on its mat.
func _counter() -> Rect2:
	var vs := get_viewport_rect().size
	var k := _k()
	var w := minf(1080.0 * k, vs.x - 64.0 * k)
	var h := minf(640.0 * k, vs.y - 120.0 * k)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)


func _bundle_rect(i: int) -> Rect2:
	var p := _counter()
	var k := _k()
	var mat := Rect2(p.position.x + 32.0 * k, p.position.y + 104.0 * k, p.size.x - 64.0 * k, p.size.y - 230.0 * k)
	var cw := mat.size.x / 4.0
	var ch := mat.size.y / 2.0
	var w := minf(cw - 40.0 * k, 210.0 * k)
	var h := minf(ch - 70.0 * k, 104.0 * k)
	return Rect2(mat.position.x + (i % 4) * cw + (cw - w) * 0.5, mat.position.y + (i / 4) * ch + 24.0 * k, w, h)


func _button(i: int, n: int) -> Rect2:
	if kind == "sign" or kind == "count":               # (the redesigned two: their own bar of actions)
		var k := _k()
		var area := _slip() if kind == "sign" else _counter()
		var bw := 300.0 * k
		var gap := 16.0 * k
		var y := area.end.y + 24.0 * k if kind == "sign" else area.end.y - 76.0 * k
		var x0 := area.end.x - (bw * n + gap * (n - 1)) - (0.0 if kind == "sign" else 32.0 * k)
		return Rect2(x0 + i * (bw + gap), y, bw, 52.0 * k)
	var p := _panel()
	var w := 300.0
	var gap := 24.0
	var x0 := p.position.x + (p.size.x - (w * n + gap * (n - 1))) * 0.5
	return Rect2(x0 + i * (w + gap), p.end.y - 70.0, w, 48.0)


func _targets() -> Array:
	if kind == "hang" and str(spec.get("thing", "key")) == "key":
		return _hooks()
	var p := _panel()
	var out := []
	var ts: Array = spec.get("targets", [])
	for i in ts.size():
		var x := p.position.x + p.size.x * (0.18 + 0.64 * (float(i) / maxf(ts.size() - 1, 1)))
		out.append(Rect2(x - 55.0, p.position.y + p.size.y * 0.25, 110.0, 150.0))
	return out


# ---- the key box (a hang task with a key): a wooden board by the door, four brass hooks, the key in his hand ----
## The board: dark wood, sized to the window.
func _board() -> Rect2:
	var vs := get_viewport_rect().size
	var k := _k()
	var w := minf(880.0 * k, vs.x - 64.0 * k)
	var h := minf(600.0 * k, vs.y - 200.0 * k)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5 - 20.0 * k, w, h)


## Each hook's area: the hook, the key under it and its plate (one Rect2 per target).
func _hooks() -> Array:
	var b := _board()
	var k := _k()
	var ts: Array = spec.get("targets", [])
	var out := []
	var inner := b.size.x - 120.0 * k
	for i in ts.size():
		var x := b.position.x + 60.0 * k + inner * (float(i) + 0.5) / float(maxi(ts.size(), 1))
		out.append(Rect2(x - 80.0 * k, b.position.y + 92.0 * k, 160.0 * k, 270.0 * k))
	return out


func _key_size() -> float:
	return 120.0 * _k()


func _hook_point(i: int) -> Vector2:
	var r: Rect2 = _hooks()[i]
	return Vector2(r.get_center().x, r.position.y + 28.0 * _k())


## Where a key hangs on a hook: its ring on the hook's curl.
func _hook_tip(i: int) -> Vector2:
	return _hook_point(i) + Vector2(0.09, 0.45) * _key_size()


func _key_home() -> Vector2:
	var b := _board()
	return Vector2(b.get_center().x, b.end.y - 178.0 * _k())


## Which key belongs on hook i (by its label): the right one is the SUV's (the one in his hand).
func _key_kind(i: int) -> String:
	var ts: Array = spec.get("targets", [])
	if ts[i].get("right", false):
		return "suv"
	var lab = ts[i].get("label", "")
	var en := (str(lab.get("en", "")) if lab is Dictionary else str(lab)).to_lower()
	for kk in ["gate", "store", "garden", "suv"]:
		if en.contains(kk):
			return kk
	return "house"


## What each hook is for (shown as the mouse comes over it, or the keyboard does).
func _hook_about(kk: String) -> String:
	match kk:
		"gate":
			return L("The front gate's padlock.", "முன் கேட் பூட்டு.")
		"store":
			return L("The store room behind the kitchen.", "சமையலறைக்கு பின்னாடி ஸ்டோர் ரூம்.")
		"garden":
			return L("The garden shed and the tap.", "தோட்டக் கொட்டகையும் குழாயும்.")
		"suv":
			return L("Sir's SUV. Its own hook.", "சார் கார். அதுக்குன்னே ஒரு கொக்கி.")
	return ""


func _hang_input(e: InputEvent) -> void:
	if _hung >= 0:
		return
	if e is InputEventMouseMotion:
		_hover = -1
		var rs := _hooks()
		for i in rs.size():
			if (rs[i] as Rect2).has_point(e.position):
				_hover = i
		if _hover >= 0:
			_focus = -1                                  # (the mouse is used: the keyboard's ring goes)
		if _drag:
			_thing = e.position
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if _inspect:
			if not e.pressed:
				_inspect = false
			return
		var k := _k()
		if e.pressed and Rect2(_thing - Vector2(48, 30) * k, Vector2(96, 150) * k).has_point(e.position):
			_drag = true
			_press_at = e.position
			_ret_t = -1.0
		elif not e.pressed and _drag:
			_drag = false
			if e.position.distance_to(_press_at) < 6.0 * k:   # a click, not a drag: a close look at it
				_inspect = true
			else:
				_drop()
	queue_redraw()


## The key box by keyboard: ←/→ (or Tab) choose a hook, Enter (Space, E) hangs it there; I looks at the key closely;
## Esc puts the close look away.
func _hang_key(code: int) -> void:
	var n: int = (spec.get("targets", []) as Array).size()
	if _hung >= 0 or n == 0:
		return
	if code == KEY_ESCAPE:
		if _inspect:
			_inspect = false
		elif _drag:
			_drag = false
			_send_back()
	elif code in [KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		_inspect = false
		_focus = 0 if _focus < 0 else (_focus + (-1 if code == KEY_LEFT else 1) + n) % n
	elif code == KEY_I:
		_inspect = not _inspect
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E]:
		if _inspect:
			_inspect = false
		elif _focus >= 0:
			_thing = _hook_tip(_focus)
			_drop()
	queue_redraw()


func _send_back() -> void:
	_ret_from = _thing
	_ret_t = 0.0


func _phone() -> Rect2:
	var p := _panel()
	return Rect2(p.position.x + p.size.x * 0.5 - 170.0, p.position.y + 10.0, 340.0, p.size.y - 20.0)


# ---- input ----
func _gui_input(e: InputEvent) -> void:
	if _away:
		return
	if e is InputEventMouseMotion:
		_mouse = e.position
		if kind == "sign" or kind == "count":
			queue_redraw()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_held = e.pressed
		if kind == "count":
			_focus = -1                                   # (the mouse is used: the keyboard's ring goes)
	if _closing > 0.0:
		return
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
				queue_redraw()
		"hang":
			if str(spec.get("thing", "key")) == "key":
				_hang_input(e)
				return
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
		"meal":
			_meal_input(e)
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
	if not visible or _away or not (e is InputEventKey) or not e.pressed:
		return
	if kind == "otp":
		if e.keycode >= KEY_0 and e.keycode <= KEY_9:
			_otp_key(str(e.keycode - KEY_0))
		elif e.keycode >= KEY_KP_0 and e.keycode <= KEY_KP_9:
			_otp_key(str(e.keycode - KEY_KP_0))
		elif e.keycode == KEY_BACKSPACE:
			_otp_key("⌫")
		accept_event()
	elif kind == "ready" and e.keycode == KEY_Z and chore < chores.size() and chores[chore] == "bath":
		groom.set_zoom(not groom.zoom)                  # the bath: whole, or close on his face
		queue_redraw()
		accept_event()
	elif kind == "sign" and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and _ink > 120.0 and _focus != 0:
		_done({"signed": true, "strokes": strokes.size()})
		accept_event()
	elif kind == "sign" and (e.keycode == KEY_TAB or e.keycode == KEY_LEFT or e.keycode == KEY_RIGHT):
		_focus = 1 - _focus if _focus >= 0 else 0           # (Tab, arrows: between Clear and Submit)
		queue_redraw()
		accept_event()
	elif kind == "sign" and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_SPACE) and _focus == 0:
		strokes.clear()
		_ink = 0.0
		queue_redraw()
		accept_event()
	elif kind == "count" and _closing <= 0.0:
		_count_key(e.keycode)
		accept_event()
	elif kind == "hang" and str(spec.get("thing", "key")) == "key":
		_hang_key(e.keycode)
		accept_event()
	elif kind == "ready" and chore < chores.size() and chores[chore] == "pocket":
		_pocket_key(e.keycode)
		accept_event()


func _say(text: String, col: Color) -> void:
	_msg = text
	_msg_col = col
	_msg_t = 2.5


## The count by keyboard: arrows move between the bundles (and down to the answers), Space or E counts the one
## chosen, Enter answers with the chosen answer; 1 and 2 answer at once.
func _count_key(code: int) -> void:
	if _focus < 0 and code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_TAB]:
		_focus = 0
	elif code == KEY_LEFT:
		_focus = maxi(_focus - 1, 0) if _focus < 8 else 8
	elif code == KEY_RIGHT:
		_focus = mini(_focus + 1, bundles.size() - 1) if _focus < 8 else 9
	elif code == KEY_UP:
		_focus = _focus - 4 if _focus >= 4 and _focus < 8 else (4 if _focus >= 8 else _focus)
	elif code == KEY_DOWN:
		_focus = _focus + 4 if _focus < 4 else 8
	elif code == KEY_TAB:
		_focus = (_focus + 1) % 10
	elif (code == KEY_SPACE or code == KEY_E) and _focus >= 0 and _focus < bundles.size() and bundles[_focus]["counted"] < 0.0 and _counting < 0:
		_counting = _focus
		bundles[_focus]["counted"] = 0.0
	elif (code == KEY_ENTER or code == KEY_KP_ENTER) and _focus >= 8:
		_answer(_focus == 9)
	elif code == KEY_1:
		_answer(false)
	elif code == KEY_2:
		_answer(true)
	queue_redraw()


func _answer(says_short: bool) -> void:
	if _closing > 0.0:
		return
	var short_i := int(spec.get("short", -1))
	var found: bool = short_i >= 0 and bundles[short_i]["counted"] >= 1.0
	var counted := 0
	for b in bundles:
		if b["counted"] >= 1.0:
			counted += 1
	var result := {"short_reported": says_short, "short_found": found and says_short, "counted": counted}
	# what he did, for a moment, before the counter closes (the story's own lines follow it)
	if says_short:
		_say(L("You hand back the short bundle.", "குறைஞ்ச கட்ட திருப்பி குடுக்கறீங்க.") if found else L("You say one is short.", "ஒண்ணு குறையுதுன்னு சொல்றீங்க."), GOOD if found else DARK)
	else:
		_say(L("%s, taken as counted." % _rupees(bundles.size() * 50000), "%s, எண்ணினதா எடுத்துக்கிட்டீங்க." % _rupees(bundles.size() * 50000)), DARK)
	_closing = 0.7
	get_tree().create_timer(0.7).timeout.connect(func():
		_closing = 0.0
		_done(result))


func _drop() -> void:
	var ts: Array = spec.get("targets", [])
	var rs := _targets()
	var keybox := str(spec.get("thing", "key")) == "key"
	for i in rs.size():
		if (rs[i] as Rect2).grow(20.0).has_point(_thing):
			if ts[i].get("right", false):
				_thing = _hook_tip(i) if keybox else (rs[i] as Rect2).get_center() + Vector2(0, 20)
				_hung = i
				_say(L("On its own hook.", "அதோட கொக்கியில.") if keybox else L("Done.", "முடிஞ்சது."), GOOD)
				_click(0.9)
				queue_redraw()
				get_tree().create_timer(0.9).timeout.connect(func(): _done({"placed": true}))
				return
			_say(t_(ts[i].get("wrong", {"en": "Not there.", "ta": "அங்க இல்ல."})), BAD)
	if keybox:
		_send_back()                                     # (back into his hand: he can try again)
	else:
		_thing = _home
	queue_redraw()


## A soft click (a key onto its hook, a thing into a pocket): made here, no sound file.
func _click(pitch := 1.0) -> void:
	if _snd == null:
		_snd = AudioStreamPlayer.new()
		_snd.volume_db = -14.0
		var rate := 22050
		var n := int(rate * 0.06)
		var data := PackedByteArray()
		data.resize(n * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in n:
			var tt := float(i) / rate
			var v := (sin(TAU * 1900.0 * tt) * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5) * exp(-tt * 90.0)
			data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate
		w.data = data
		_snd.stream = w
		add_child(_snd)
	_snd.pitch_scale = pitch
	_snd.play()



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


## (testing) a picture of the task as it is now, into the --storyshots folder.
func _test_shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--storyshots="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/task_%s%s.jpg" % [a.get_slice("=", 1), name, "_ta" if lang == "ta" else ""], 0.88)


func _done(result: Dictionary) -> void:
	if has_meta("half_shot"):
		remove_meta("half_shot")
	if has_meta("answered"):
		remove_meta("answered")
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
	if _closing > 0.0:
		_closing = maxf(_closing - dt, 0.0001)
	if kind == "count" and _counting >= 0:
		bundles[_counting]["counted"] = minf(bundles[_counting]["counted"] + dt / 1.1, 1.0)
		if bundles[_counting]["counted"] >= 1.0:
			_counting = -1
	if _away:
		return
	if kind == "ready" and chore < chores.size() and chores[chore] in ["brush", "bath"]:
		groom.area = _chore_rects()["area"]               # (the window may have changed size)
		groom.process(dt)
		if groom.said_new:
			groom.said_new = false
			_say(groom.said, DARK)
		if groom.done and not skip:
			_next_chore()
	if kind == "hang" and str(spec.get("thing", "key")) == "key":
		_home = _key_home()
		if _ret_t >= 0.0:                                # (back to his hand, quickly, easing in)
			_ret_t = minf(_ret_t + dt / Kit.NORMAL, 1.0)
			_thing = _ret_from.lerp(_home, Kit.ease_out(_ret_t))
			if _ret_t >= 1.0:
				_ret_t = -1.0
		elif not _drag and _hung < 0:
			_thing = _home
	elif kind == "hang" and _home == Vector2.ZERO:
		var p := _panel()
		_home = Vector2(p.get_center().x, p.end.y - 70.0)
		_thing = _home
	if kind == "ready":
		for it in _pk_in.keys():                         # (things sliding into the pocket, or back to their place)
			_pk_in[it]["t"] = minf(float(_pk_in[it]["t"]) + dt / Kit.NORMAL, 1.0)
		for it in _pk_back.keys():
			_pk_back[it]["t"] = minf(float(_pk_back[it]["t"]) + dt / Kit.NORMAL, 1.0)
			if _pk_back[it]["t"] >= 1.0:
				_pk_back.erase(it)
	if skip and _t > 1.5:
		match kind:
			"sign":
				var s := PackedVector2Array()
				for i in 40:
					s.append(Vector2(40 + i * 7, 52 + sin(i * 0.7) * 20))
				strokes = [s]
				_ink = 300.0
				if _t > 2.2 and not has_meta("answered"):
					set_meta("answered", true)
					await _test_shot("sign_done")
					_done({"signed": true, "strokes": 1})
			"count":
				if not has_meta("answered"):
					var n := clampi(int((_t - 1.5) / 0.12), 0, bundles.size() + 1)   # (one after another, as he would)
					for i in bundles.size():
						bundles[i]["counted"] = 1.0 if i < n - 1 else (0.55 if i == n - 1 else -1.0)
					if _t > 1.5 + 0.12 * 4.5 and not has_meta("half_shot"):
						set_meta("half_shot", true)
						_test_shot("count_half")
					if _t > 2.8:
						set_meta("answered", true)
						for b in bundles:
							b["counted"] = 1.0
						_answer(true)
						get_tree().create_timer(0.3).timeout.connect(func(): _test_shot("count_answer"))
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
			"meal":
				if _t > 2.2:
					var menu: Array = spec.get("menu", [])
					var price := 0 if spec.get("home", false) or menu.is_empty() else int(menu[0]["price"])
					_done({"paid": price, "ate": true, "meal": str(spec.get("food", "meals")), "minutes": int(spec.get("minutes", 15))})
			"ready":
				if _t > 1.6:
					_t = 1.0
					if chores[chore] == "dress":
						shirt = "blue"
					_next_chore()
	queue_redraw()


# ---- drawing ----
func _text(pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, s, align, w, size, col)


func _draw() -> void:
	if not visible or _away:
		return
	var vs := get_viewport_rect().size
	if kind == "sign" or kind == "count" or kind == "hang" or kind == "ready":
		Kit.scrim(self, 0.66)
	else:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var p := _panel()
	# (a tip is said by whoever gave it, as a subtitle: story.gd _speak_tip)
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
		"meal":
			_draw_meal(p)
		"phone":
			_draw_phone()
	var keybox := kind == "hang" and str(spec.get("thing", "key")) == "key"
	if _msg_t > 0.0 and _msg != "" and (kind == "sign" or kind == "count" or keybox or kind == "ready"):
		var area := _slip() if kind == "sign" else (_counter() if kind == "count" else (_board() if keybox else _ready_card()))
		Kit.banner(self, Vector2(area.get_center().x, area.position.y - 58.0 * _k()), _msg, _msg_col != BAD, _k(), clampf(_msg_t * 2.0, 0.0, 1.0))
	elif _msg_t > 0.0 and _msg != "":
		var mb := Rect2(p.position.x + p.size.x * 0.25, p.end.y + 12.0, p.size.x * 0.5, 40.0)
		draw_rect(mb, Color(1, 1, 1, 0.95))
		_text(mb.position + Vector2(0, 27), _msg, 19, _msg_col, mb.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _btn(r: Rect2, label: String, on := true) -> void:
	draw_rect(r, Color(0.2, 0.45, 0.85) if on else Color(0.45, 0.45, 0.5))
	_text(r.position + Vector2(0, 31), label, 19, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## The bank slip, as a cooperative bank prints them: the bank's name and monogram, the form's title in a box,
## the filled fields (the amount in its own box), the bank's seal and the signature box; Clear and Submit below.
func _draw_sign(_p: Rect2) -> void:
	var k := _k()
	var r := _slip()
	var green := Color(0.1, 0.33, 0.24)
	Kit.paper(self, r, k)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 6.0 * k)), green)                     # the printed band at the top
	var mono := Vector2(r.position.x + 64.0 * k, r.position.y + 64.0 * k)              # the bank's monogram
	draw_circle(mono, 28.0 * k, green)
	draw_arc(mono, 23.0 * k, 0.0, TAU, 48, Color(0.95, 0.93, 0.85, 0.8), 1.4 * k, true)
	var initials := ""
	var hdr = spec.get("header", "")
	for w in str(hdr.get("en", "") if hdr is Dictionary else hdr).split(" ", false):   # (the monogram is the bank's, in English, whatever the language)
		if initials.length() < 4 and w.length() > 0 and w.unicode_at(0) < 128:
			initials += w.substr(0, 1)
	Hud.text(self, mono + Vector2(-28.0 * k, 6.0 * k), initials, 14.0 * k, Color(0.97, 0.95, 0.88), 700, HORIZONTAL_ALIGNMENT_CENTER, 56.0 * k)
	Hud.text(self, Vector2(r.position.x + 108.0 * k, r.position.y + 60.0 * k), t_(spec.get("header", "")), 27.0 * k, green, 700)
	var form := t_(spec.get("form", ""))
	var fw := Hud.width_of(form, 15.0 * k, 700) + 32.0 * k
	var fb := Rect2(r.end.x - fw - 36.0 * k, r.position.y + 42.0 * k, fw, 34.0 * k)
	draw_rect(fb, green, false, 1.5 * k)
	Hud.text(self, fb.position + Vector2(0, 23.0 * k), form, 15.0 * k, green, 700, HORIZONTAL_ALIGNMENT_CENTER, fw)
	draw_line(Vector2(r.position.x + 36.0 * k, r.position.y + 112.0 * k), Vector2(r.end.x - 36.0 * k, r.position.y + 112.0 * k), Kit.PAPER_LINE, k)
	var y := r.position.y + 158.0 * k
	var fx := r.position.x + 40.0 * k
	var fwid := r.size.x - 80.0 * k
	for f in spec.get("fields", []):
		var val := t_(f[1])
		if val.begins_with("₹"):                                                       # the amount, in its own box
			Hud.text(self, Vector2(fx, y), t_(f[0]).to_upper(), Kit.T_LABEL * k, Kit.PRINT, 600)
			var ab := Rect2(fx + 200.0 * k, y - 29.0 * k, 260.0 * k, 42.0 * k)
			draw_rect(ab, Color(1, 1, 1, 0.5))
			draw_rect(ab, Kit.PRINT, false, 1.4 * k)
			Hud.text(self, ab.position + Vector2(14.0 * k, 30.0 * k), val, 24.0 * k, Kit.PEN, 600)
			y += 56.0 * k
			continue
		Kit.field(self, Vector2(fx, y), fwid, t_(f[0]), val, k)
		y += 46.0 * k
	Kit.stamp(self, Vector2(r.position.x + 118.0 * k, r.end.y - 92.0 * k), 50.0 * k, t_(spec.get("seal", {"en": "BANK SEAL", "ta": "வங்கி முத்திரை"})), k)
	var box := _sign_box()
	draw_rect(box, Color(1, 1, 1, 0.55))
	_dash_rect(box, Kit.PAPER_LINE, k)
	Hud.text(self, Vector2(box.position.x, box.end.y + 22.0 * k), t_(spec.get("sign_label", {"en": "Signature", "ta": "கையொப்பம்"})).to_upper(),
		Kit.T_LABEL * k, Kit.PRINT, 600, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if strokes.is_empty():
		Hud.text(self, box.position + Vector2(0, box.size.y * 0.56), L("Sign here with the mouse", "மவுஸால இங்க கையெழுத்து போடுங்க"), 17.0 * k,
			Color(0.5, 0.5, 0.5, 0.75 + 0.25 * sin(_t * 3.0)), box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	elif box.has_point(_mouse):
		draw_circle(_mouse, 3.0 * k, Kit.PEN)
	for st in strokes:
		if (st as PackedVector2Array).size() > 1:
			var pts := PackedVector2Array()
			for q in st:
				pts.append(q + box.position)
			draw_polyline(pts, Kit.PEN, 2.6 * k, true)
	var signed := _ink > 120.0
	if signed:                                                                         # signed: a tick under the box
		Hud.text(self, Vector2(box.position.x, box.position.y - 10.0 * k), L("✓ Signed", "✓ கையெழுத்து ஆச்சு"), 16.0 * k, Color(0.15, 0.5, 0.25), 600)
	var b0 := _button(0, 2)
	var b1 := _button(1, 2)
	Kit.button(self, b0, L("Clear", "அழி"), k, Kit.state_of(b0, _mouse, not strokes.is_empty(), _focus == 0, _held), "secondary")
	Kit.button(self, b1, L("Sign and submit", "சமர்ப்பி"), k, Kit.state_of(b1, _mouse, signed, _focus == 1, _held), "primary", "Enter")
	if not signed:
		Hud.text(self, Vector2(r.position.x, b0.get_center().y + 6.0 * k), L("Sign in the box to hand in the slip", "சீட்ட குடுக்க பெட்டியில கையெழுத்து போடுங்க"),
			Kit.T_CAPTION * k, Kit.DIM, 500)


func _dash_rect(r: Rect2, col: Color, k: float) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var n := maxi(int(a.distance_to(b) / (9.0 * k)), 2)
		for i in range(0, n, 2):
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 1.2 * k)


## The counter: eight strapped bundles of ₹500 notes on the mat. Click one (or choose it with the arrows, Space)
## to count it: the notes flick through, a counter runs to its total; a bundle that comes up short says so in
## red. Below: how many are counted and how much, and the two answers.
func _draw_count(_p: Rect2) -> void:
	var k := _k()
	var r := _counter()
	Hud.panel(self, r, k, 1.3)
	Hud.text(self, r.position + Vector2(32.0 * k, 50.0 * k), L("Count the cash", "பணத்த எண்ணுங்க"), Kit.T_TITLE * k, Kit.INK, 700)
	var expect := bundles.size() * 100 * 500
	Hud.text(self, r.position + Vector2(32.0 * k, 80.0 * k), L("%d bundles · 100 notes of ₹500 in each · %s on the slip" % [bundles.size(), _rupees(expect)],
		"%d கட்டு · ஒவ்வொண்ணுலயும் ₹500 நோட்டு 100 · சீட்டுல %s" % [bundles.size(), _rupees(expect)]), Kit.T_CAPTION * k, Kit.DIM, 500)
	var mat := Rect2(r.position.x + 32.0 * k, r.position.y + 104.0 * k, r.size.x - 64.0 * k, r.size.y - 230.0 * k)
	draw_style_box(_mat_box(k), mat)
	var total := 0
	var done := 0
	for i in bundles.size():
		var b: Dictionary = bundles[i]
		if float(b["counted"]) >= 1.0:
			total += int(b["n"]) * 500
			done += 1
		_draw_bundle(i, k)
	var bar := Rect2(r.position.x + 32.0 * k, r.end.y - 100.0 * k, r.size.x * 0.3, 8.0 * k)
	Hud.text(self, Vector2(bar.position.x, bar.position.y - 12.0 * k), L("Counted %d of %d" % [done, bundles.size()], "எண்ணியது %d / %d" % [done, bundles.size()]),
		Kit.T_CAPTION * k, Kit.DIM, 500)
	Kit.progress(self, bar, float(done) / maxf(bundles.size(), 1), k, Kit.GREEN, bundles.size())
	Hud.text(self, Vector2(bar.position.x, bar.end.y + 36.0 * k), _rupees(total), Kit.T_FIGURE * k, Kit.INK, 600)
	Hud.text(self, Vector2(bar.position.x + Hud.width_of(_rupees(total), Kit.T_FIGURE * k, 600) + 12.0 * k, bar.end.y + 36.0 * k),
		L("of %s" % _rupees(expect), "/ %s" % _rupees(expect)), Kit.T_BODY * k, Kit.DIM, 500)
	var b0 := _button(0, 2)
	var b1 := _button(1, 2)
	Kit.button(self, b0, L("All correct: %s" % _rupees(expect), "எல்லாம் சரி: %s" % _rupees(expect)), k,
		Kit.state_of(b0, _mouse, _closing <= 0.0, _focus == 8, _held), "secondary", "1")
	Kit.button(self, b1, L("A bundle is short", "ஒரு கட்டு குறையுது"), k, Kit.state_of(b1, _mouse, _closing <= 0.0, _focus == 9, _held), "secondary", "2")
	Hud.text(self, Vector2(r.position.x + 32.0 * k, r.end.y - 14.0 * k), L("Click a bundle to count it  ·  arrows and Space  ·  1 or 2 to answer",
		"எண்ண ஒரு கட்ட கிளிக் பண்ணுங்க  ·  அம்புக்குறி, Space  ·  பதில் சொல்ல 1 அல்லது 2"), Kit.T_LABEL * k, Hud.fade(Kit.DIM, 0.7), 500)


func _mat_box(k: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.19, 0.16)                      # the counter's green rubber mat
	sb.set_corner_radius_all(int(8.0 * k))
	sb.border_color = Color(1, 1, 1, 0.05)
	sb.set_border_width_all(maxi(1, int(k)))
	return sb


func _note(c: Vector2, size: Vector2, ang: float, shade: float) -> void:
	var pts := PackedVector2Array()
	for v in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		pts.append(c + (Vector2(v.x * size.x, v.y * size.y)).rotated(ang))
	draw_colored_polygon(pts, NOTE.lightened(shade))
	pts.append(pts[0])
	draw_polyline(pts, NOTE.darkened(0.35), 1.0, true)


func _draw_bundle(i: int, k: float) -> void:
	var r := _bundle_rect(i)
	var b: Dictionary = bundles[i]
	var c: float = b["counted"]
	var hover := r.grow(8.0 * k).has_point(_mouse) and c < 0.0 and _counting < 0 and _closing <= 0.0
	if (hover or _focus == i) and c < 0.0:
		r.position.y -= 4.0 * k                               # (picked up a little)
	if c < 0.0:                                               # strapped: the edges of the notes under the top one
		_bundle_face(r, k)
		var band := Rect2(r.position.x + r.size.x * 0.4, r.position.y - 3.0 * k, r.size.x * 0.2, r.size.y + 6.0 * k)
		draw_rect(band, Color(0.93, 0.9, 0.8))                # the paper band, the bank's own count on it
		Hud.text(self, Vector2(band.position.x, band.get_center().y - 2.0 * k), "100", 13.0 * k, Kit.PRINT, 700, HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
		Hud.text(self, Vector2(band.position.x, band.get_center().y + 13.0 * k), "×500", 11.0 * k, Kit.PRINT, 600, HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
		var tip := L("Count this bundle", "இந்த கட்ட எண்ணுங்க") if hover or _focus == i else L("Click to count", "எண்ண கிளிக்")
		Hud.text(self, Vector2(r.position.x - 20.0 * k, r.end.y + 32.0 * k), tip, Kit.T_LABEL * k, Kit.AMBER if hover or _focus == i else Kit.DIM, 600,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0 * k)
	else:                                                     # counting: the notes flick through; then the total
		var n := int(round(float(b["n"]) * c))
		if c < 1.0:
			var fan := 9
			for f in fan:
				_note(r.get_center() + Vector2(0, f * 0.6 * k), r.size * 0.96, (f - fan * 0.5) * 0.06 * sin(c * PI), 0.02 * f)
		else:                                                 # counted: the band off, the stack squared, its face up
			_bundle_face(r, k)
		var short: bool = c >= 1.0 and int(b["n"]) < 100
		var col := Kit.INK if c < 1.0 else (Kit.GREEN if not short else Kit.RED)
		var line := ("%d / 100" % n) if c < 1.0 else (L("✓  100 notes", "✓  100 நோட்டு") if not short else L("%d notes · short" % n, "%d நோட்டு · குறைவு" % n))
		Hud.text(self, Vector2(r.position.x - 20.0 * k, r.end.y + 32.0 * k), line, 17.0 * k, col, 700, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0 * k)
		if c < 1.0:
			Kit.progress(self, Rect2(r.position.x, r.end.y + 42.0 * k, r.size.x, 4.0 * k), c, k, Kit.AMBER)
		elif short:
			draw_rect(r.grow(5.0 * k), Kit.RED, false, 2.0 * k)
	if _focus == i:
		draw_style_box(_ring(k), r.grow(10.0 * k))


## A bundle's stack and its top ₹500 note: the edges of the notes under it, the watermark, the figures.
func _bundle_face(r: Rect2, k: float) -> void:
	for e in 4:
		draw_rect(Rect2(r.position + Vector2(-(3 - e) * 1.2 * k, (4 - e) * 2.2 * k), r.size), NOTE.darkened(0.3 - e * 0.06))
	draw_rect(r, NOTE.lightened(0.05))
	draw_rect(r, NOTE.darkened(0.35), false, k)
	draw_circle(Vector2(r.position.x + r.size.x * 0.76, r.get_center().y), r.size.y * 0.24, NOTE.lightened(0.16))   # the watermark
	Hud.text(self, r.position + Vector2(10.0 * k, 22.0 * k), "₹500", 15.0 * k, NOTE.darkened(0.5), 700)
	Hud.text(self, Vector2(r.end.x - 44.0 * k, r.end.y - 10.0 * k), "500", 17.0 * k, NOTE.darkened(0.45), 700)


func _ring(k: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(int(8.0 * k))
	sb.border_color = Kit.AMBER
	sb.set_border_width_all(maxi(2, int(2.0 * k)))
	return sb


## The key box by Raghavan sir's door: a dark wooden board with a brass plate, four brass hooks with their keys and
## engraved plates (the SUV's hook empty), the SUV key in his hand below; under it, what the hook under the mouse (or
## the keyboard) is for. A click on the key: a close look at it.
func _draw_keybox() -> void:
	var b := _board()
	var k := _k()
	var ks := _key_size()
	# the board: dark wood, a darker frame, the grain running across
	Art._shadow(self, b, 14.0 * k, 0.45)
	Art._rr(self, b, Color(0.2, 0.12, 0.07), 14.0 * k)
	var inner := b.grow(-12.0 * k)
	Art._rr(self, inner, Color(0.29, 0.18, 0.1), 8.0 * k)
	var y := inner.position.y + 6.0 * k
	var n := 0
	while y < inner.end.y - 4.0 * k:
		var a := 0.05 + 0.05 * absf(sin(n * 1.7))
		draw_line(Vector2(inner.position.x + 4.0 * k, y), Vector2(inner.end.x - 4.0 * k, y + sin(n * 0.9) * 2.0 * k),
			Color(0.1, 0.05, 0.02, a), maxf(1.5 * k, 1.0))
		y += (9.0 + 7.0 * absf(sin(n * 2.3))) * k
		n += 1
	# its brass name plate
	var title := t_(spec.get("title", ""))
	var tw := Hud.width_of(title, 17.0 * k, 600) + 56.0 * k
	var tp := Rect2(b.get_center().x - tw * 0.5, b.position.y + 28.0 * k, tw, 38.0 * k)
	Art._shadow(self, tp, 4.0 * k, 0.4)
	Art._rr(self, tp, Art.BRASS, 4.0 * k, Art.BRASS_DARK, maxf(k, 1.0))
	Hud.text(self, Vector2(tp.position.x, tp.get_center().y + 6.0 * k), title, 17.0 * k, Color(0.2, 0.13, 0.05), 600,
		HORIZONTAL_ALIGNMENT_CENTER, tp.size.x)
	# the hooks, their keys, their plates
	var ts: Array = spec.get("targets", [])
	var rs := _hooks()
	var over := -1                                       # (the hook a dragged key is over: the one it would go on)
	for i in rs.size():
		if _drag and (rs[i] as Rect2).grow(20.0).has_point(_thing):
			over = i
	for i in rs.size():
		var r: Rect2 = rs[i]
		var kk := _key_kind(i)
		var hot := i == _hover or i == _focus or i == over
		var hp := _hook_point(i)
		Art.hook(self, hp, ks, hot)
		if kk != "suv":
			Art.key(self, _hook_tip(i), kk, ks, 5.0 * k if hot else 0.0)
		elif i != _hung and (_drag or _focus == i):        # (its own hook, empty: a faint ring where the key goes)
			draw_arc(_hook_tip(i), 10.0 * k, 0, TAU, 20, Hud.fade(Hud.GREEN, 0.5 + 0.3 * sin(_t * 5.0)), 2.0 * k)
		var pr := Rect2(r.get_center().x - 66.0 * k, r.end.y - 34.0 * k, 132.0 * k, 28.0 * k)
		Art.plate(self, pr, t_(ts[i]["label"]), k, hot)
		if i == _focus:                                   # (the keyboard's hook: a ring round it)
			Art._rr(self, r.grow(4.0 * k), Color(0, 0, 0, 0), 10.0 * k, Hud.fade(Kit.BLUE, 0.9), 2.0 * k)
	# his hand: a dark patch on the board's foot with the SUV key in it (until it's hung)
	var tray := Rect2(b.get_center().x - 150.0 * k, b.end.y - 214.0 * k, 300.0 * k, 186.0 * k)
	Art._rr(self, tray, Color(0, 0, 0, 0.22), 12.0 * k, Color(1, 1, 1, 0.06), k)
	Hud.text(self, tray.position + Vector2(14.0 * k, 24.0 * k), L("IN YOUR HAND", "உங்க கையில"), 12.0 * k,
		Color(0.95, 0.9, 0.8, 0.55), 700)
	if _hung >= 0:
		Art.key(self, _hook_tip(_hung), "suv", ks)
	else:
		var near := not _drag and _mouse.distance_to(_thing + Vector2(0, 60.0 * k)) < 70.0 * k
		Art.key(self, _thing, "suv", ks * (1.08 if _drag else 1.0), 4.0 * k if near else 0.0)
	# what the hook is for, or what to do
	var sel := _hover if _hover >= 0 else _focus
	if _drag and over >= 0:
		sel = over
	var bar := Rect2(b.position.x, b.end.y + 14.0 * k, b.size.x, 54.0 * k)
	Hud.panel(self, bar, k)
	if sel >= 0:
		var lbl := t_(ts[sel]["label"])
		Hud.text(self, Vector2(bar.position.x + 22.0 * k, bar.get_center().y + 6.5 * k), lbl, 18.0 * k, Hud.AMBER, 600)
		Hud.text(self, Vector2(bar.position.x + 34.0 * k + Hud.width_of(lbl, 18.0 * k, 600), bar.get_center().y + 6.5 * k),
			_hook_about(_key_kind(sel)), 17.0 * k, Hud.INK)
	else:
		Hud.text(self, Vector2(bar.position.x + 22.0 * k, bar.get_center().y + 6.5 * k),
			L("Hang the SUV key on its hook: drag it there, or ← → and Enter.  Click it to look closer.",
			"கார் சாவியை அதோட கொக்கியில மாட்டுங்க: இழுத்து வையுங்க, அல்லது ← → பிறகு Enter.  கிட்ட பார்க்க கிளிக் பண்ணுங்க."),
			16.0 * k, Hud.DIM)
	# a close look at the key in his hand
	if _inspect:
		Kit.scrim(self, 0.55)
		var vs := get_viewport_rect().size
		var cr := Rect2(vs.x * 0.5 - 250.0 * k, vs.y * 0.5 - 250.0 * k, 500.0 * k, 470.0 * k)
		Hud.panel(self, cr, k)
		Art.key(self, Vector2(cr.get_center().x, cr.position.y + 40.0 * k), "suv", 290.0 * k)
		Hud.text(self, Vector2(cr.position.x, cr.end.y - 104.0 * k), L("The SUV key", "கார் சாவி"), 22.0 * k, Hud.INK, 700,
			HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		Hud.text(self, Vector2(cr.position.x + 30.0 * k, cr.end.y - 72.0 * k),
			L("A black fob, lock and unlock, the steel key in it. Sir's car.", "கருப்பு ஃபோப், பூட்டவும் திறக்கவும், உள்ள இரும்புச் சாவி. சார் கார்."),
			16.0 * k, Hud.DIM, 400, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 60.0 * k)
		Hud.text(self, Vector2(cr.position.x, cr.end.y - 26.0 * k), L("Click, or Esc, to hold it again", "மறுபடி கையில எடுக்க கிளிக், அல்லது Esc"),
			14.0 * k, Hud.fade(Hud.INK, 0.5), 400, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)


func _draw_hang(p: Rect2) -> void:
	var thing := str(spec.get("thing", "key"))
	if thing == "key":
		_draw_keybox()
		return
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
	match chores[chore]:
		"alarm":
			out["snooze"] = Rect2(c + Vector2(-230, 140), Vector2(200, 54))
			out["up"] = Rect2(c + Vector2(30, 140), Vector2(200, 54))
		"brush", "bath":
			out["area"] = Rect2(p.position.x + 230, p.position.y + 10, p.size.x - 245, p.size.y - 120)
		"dress":
			var names := ["blue", "white", "check", "cap"]
			for i in 4:
				out[names[i]] = Rect2(c + Vector2(-300 + i * 150, -150), Vector2(120, 230))
		"eat":
			for i in 4:
				out["idli%d" % i] = Rect2(c + Vector2(-150 + (i % 2) * 150, -110 + (i / 2) * 110), Vector2(120, 90))
		"pocket":
			var area := Rect2(p.position.x + 250.0, p.position.y + 24.0, p.size.x - 280.0, p.size.y - 110.0)
			var cw := minf(area.size.x / 4.0, 170.0)
			var x0 := area.get_center().x - cw * 2.0
			for i in _pocket_items.size():
				out[_pocket_items[i]] = Rect2(x0 + i * cw + 8.0, area.position.y + 66.0, cw - 16.0, cw - 16.0)
			out["pocket"] = Rect2(area.get_center().x - 150.0, area.position.y + 66.0 + cw + 34.0, 300.0, minf(176.0, area.end.y - (area.position.y + 66.0 + cw + 34.0)))
	return out


func _ready_input(e: InputEvent) -> void:
	var r := _chore_rects()
	var ch: String = chores[chore]
	if ch == "brush" or ch == "bath":
		groom.input(e)
		queue_redraw()
		return
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
						if r[it].has_point(e.position) and not _picked.has(it) and not _pk_back.has(it):
							_drag_item = it
							_press_at = r[it].get_center() - e.position     # (held where it was taken: no jump)
							_thing = e.position + _press_at
							_pk_focus = -1
		else:
			if ch == "pocket" and _drag_item != "":
				if r["pocket"].grow(30.0).has_point(_thing):
					_pack(_drag_item, _thing)
				else:                                    # (not the pocket: it slides back to its place)
					_pk_back[_drag_item] = {"from": _thing, "t": 0.0}
				_drag_item = ""
	elif e is InputEventMouseMotion:
		_mouse = e.position
		if ch == "pocket" and _drag_item != "":
			_thing = e.position + _press_at
	queue_redraw()


## Into the pocket (from where it was let go): it slides in, a soft click; all four in, the next chore.
func _pack(it: String, from: Vector2) -> void:
	if _picked.has(it):
		return
	_picked[it] = true
	_pk_in[it] = {"from": from, "t": 0.0}
	_click(1.0 + 0.08 * _picked.size())
	if _picked.size() == _pocket_items.size():
		_say(L("Wallet, phone, keys. Ready.", "பர்ஸ், ஃபோன், சாவி. ரெடி."), GOOD)
		get_tree().create_timer(0.6).timeout.connect(_next_chore)


## The pockets by keyboard: ←/→ choose a thing, Enter (Space, E) puts it in the pocket.
func _pocket_key(code: int) -> void:
	var left: Array = _pocket_items.filter(func(it): return not _picked.has(it))
	if left.is_empty():
		return
	if code in [KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		var at := left.find(_pocket_items[_pk_focus]) if _pk_focus >= 0 else -1
		at = 0 if at < 0 else (at + (-1 if code == KEY_LEFT else 1) + left.size()) % left.size()
		_pk_focus = _pocket_items.find(left[at])
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E] and _pk_focus >= 0 and not _picked.has(_pocket_items[_pk_focus]):
		var it: String = _pocket_items[_pk_focus]
		_pack(it, (_chore_rects()[it] as Rect2).get_center())
		var rest: Array = _pocket_items.filter(func(x): return not _picked.has(x))
		_pk_focus = _pocket_items.find(rest[0]) if not rest.is_empty() else -1
	queue_redraw()


func _ready_card() -> Rect2:
	return _panel()


## One of his things, drawn in its card's box (b) at size s.
func _draw_item(it: String, centre: Vector2, s: float) -> void:
	match it:
		"wallet":
			Art.wallet(self, centre, s)
		"phone":
			Art.phone(self, centre, s)
		"scooter key":
			Art.key(self, centre - Vector2(0, s * 0.42), "scooter", s)
		"house key":
			Art.key(self, centre - Vector2(0, s * 0.42), "house", s)


func _next_chore() -> void:
	if chore >= chores.size():
		return
	minutes += int(CHORE_MIN[chores[chore]])
	chore += 1
	_prog = 0.0
	_picked = {}
	stage_changed.emit()
	if chore < chores.size() and chores[chore] in ["brush", "bath"]:
		groom.start(chores[chore], _chore_rects()["area"], lang, self)
	_hand_over()
	if chore >= chores.size():
		var res := {"minutes": minutes}                  # (only what this visit did: a later visit mustn't undo it)
		if "dress" in chores:
			res["shirt"] = shirt
			res["reached_cap"] = reached_cap
		if chores.size() == ALL_CHORES.size():
			res["late_morning"] = minutes > 45
		_done(res)
	queue_redraw()


## The chore now, done in the room in 3D if the scene can: the panel steps aside until it's finished.
func _hand_over() -> void:
	if kind != "ready" or chore >= chores.size() or scene_chore == null or not scene_chore.can(chores[chore]):
		return
	_away = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_chore.lang = lang
	scene_chore.skip = skip
	scene_chore.finished.connect(func():
		_away = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		_next_chore(), CONNECT_ONE_SHOT)
	scene_chore.begin(chores[chore])
	queue_redraw()


func _draw_ready(p: Rect2) -> void:
	# the morning card: ivory paper, the chores down the left, the clock and the deadline in a footer
	var kp := 1.0
	Kit.paper(self, p, kp)
	var side := Rect2(p.position, Vector2(228.0, p.size.y - 64.0))
	Art._rr(self, side, Color(0.2, 0.36, 0.25, 0.08), 0.0)
	Hud.text(self, p.position + Vector2(24, 42), L("THIS MORNING", "இன்னைக்கு காலை"), 13.0, Color(0.2, 0.36, 0.25), 700)
	var names := {"alarm": L("Wake up", "எழுந்திரு"), "brush": L("Brush your teeth", "பல் தேய்"), "bath": L("Bath", "குளி"),
		"dress": L("Get dressed", "டிரஸ் பண்ணு"), "eat": L("Breakfast", "சாப்பிடு"), "pocket": L("Wallet, phone, keys", "பர்ஸ், ஃபோன், சாவி")}
	for i in chores.size():
		var y := p.position.y + 84 + i * 38
		var col := Color(0.2, 0.45, 0.28) if i < chore else (Kit.CHARCOAL if i == chore else Color(0.5, 0.5, 0.5))
		if i == chore:
			Art._rr(self, Rect2(p.position.x + 12, y - 24, 204, 34), Color(0.2, 0.36, 0.25, 0.12), 6.0)
		Hud.text(self, Vector2(p.position.x + 24, y), ("✓  " if i < chore else ("›  " if i == chore else "    ")) + str(names[chores[i]]),
			17.0, col, 600 if i == chore else 400)
	var foot := Rect2(p.position.x, p.end.y - 64.0, p.size.x, 64.0)
	Art._rr(self, foot, Color(0.13, 0.135, 0.15, 0.94), 0.0)
	var h := 6 * 60 + 30 + minutes
	Hud.text(self, Vector2(foot.position.x + 24, foot.get_center().y + 7), "%d:%02d AM" % [h / 60, h % 60], 22.0,
		Hud.RED if minutes > 45 else Hud.INK, 600)
	Hud.text(self, Vector2(foot.position.x + 130, foot.get_center().y + 6), L("Leave by 7:15", "7:15-க்குள் கிளம்பணும்") +
		("  ·  " + L("%d min left" % maxi(45 - minutes, 0), "இன்னும் %d நிமிஷம்" % maxi(45 - minutes, 0)) if minutes <= 45 else
		"  ·  " + L("late", "லேட்")), 16.0, Hud.DIM)
	if chore >= chores.size():
		return
	var r := _chore_rects()
	var c := p.get_center() + Vector2(90, 10)
	match chores[chore]:
		"alarm":
			draw_rect(Rect2(c - Vector2(110, 180), Vector2(220, 300)), Color(0.08, 0.08, 0.1))      # the phone
			draw_rect(Rect2(c - Vector2(100, 170), Vector2(200, 280)), Color(0.15, 0.2, 0.35))
			var shake := sin(_t * 40.0) * 4.0
			_text(c + Vector2(-100 + shake, -60), "6:%02d" % (30 + minutes), 54, Color.WHITE, 200, HORIZONTAL_ALIGNMENT_CENTER)
			_text(c + Vector2(-100, 0), L("ALARM", "அலாரம்"), 22, Color(1, 0.8, 0.3), 200, HORIZONTAL_ALIGNMENT_CENTER)
			_btn(r["snooze"], L("Snooze (+10 min)", "ஸ்னூஸ் (+10 நிமி)"), true)
			_btn(r["up"], L("Get up", "எழுந்திரு"), true)
		"brush", "bath":
			groom.draw(self, font)
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
			var area := Rect2(p.position.x + 250.0, p.position.y + 24.0, p.size.x - 280.0, p.size.y - 110.0)
			Hud.text(self, area.position + Vector2(0, 26), L("Your things", "உங்க பொருட்கள்"), 22.0, Kit.CHARCOAL, 700)
			Hud.text(self, area.position + Vector2(0, 50), L("Into your trouser pocket before you go.", "கிளம்பறதுக்கு முன்னாடி பேண்ட் பாக்கெட்டுக்குள்ள."),
				15.0, Kit.PRINT)
			var foot_r := Rect2(p.end.x - 300.0, p.end.y - 64.0, 280.0, 64.0)   # the packing progress, in the footer
			Hud.text(self, Vector2(foot_r.position.x, foot_r.get_center().y + 6), L("Packed", "வச்சது"), 15.0, Hud.DIM)
			Kit.progress(self, Rect2(foot_r.position.x + 70, foot_r.get_center().y - 4, 130, 8), float(_picked.size()) / _pocket_items.size(), 1.0, Hud.GREEN, _pocket_items.size())
			Hud.text(self, Vector2(foot_r.position.x + 212, foot_r.get_center().y + 6), "%d / %d" % [_picked.size(), _pocket_items.size()], 16.0, Hud.INK, 600)
			# the pocket, glowing when something's over it; what's in it peeking from its mouth
			Art.pocket(self, pk, 1.0, _drag_item != "" and pk.grow(30.0).has_point(_thing))
			var inside := 0
			for it in _pocket_items:
				if _picked.has(it) and float(_pk_in.get(it, {"t": 1.0})["t"]) >= 1.0:
					_draw_item(it, Vector2(pk.position.x + 60.0 + inside * 60.0, pk.position.y + 34.0), 52.0)
					inside += 1
			Art._rr(self, Rect2(pk.position, Vector2(pk.size.x, pk.size.y * 0.16)), Color(0.12, 0.16, 0.24), 4.0)   # (the mouth over them)
			if _picked.is_empty() and _drag_item == "":
				Hud.text(self, Vector2(pk.position.x, pk.get_center().y + 18), L("Drop them here", "இங்க போடுங்க"), 15.0,
					Color(1, 1, 1, 0.55), 500, HORIZONTAL_ALIGNMENT_CENTER, pk.size.x)
			# the things, each on its card (taken, packed or sliding back)
			for i in _pocket_items.size():
				var it: String = _pocket_items[i]
				var b: Rect2 = r[it]
				var hov := b.has_point(_mouse) and _drag_item == "" and not _picked.has(it)
				var foc := i == _pk_focus
				Art._rr(self, b, Color(1, 1, 1, 0.55) if not hov else Color(1, 1, 1, 0.85), 10.0,
					Kit.BLUE if foc else Color(0, 0, 0, 0.08), 2.0 if foc else 1.0)
				Hud.text(self, Vector2(b.position.x, b.end.y + 20), _item_name(it), 14.0, Kit.PRINT if not _picked.has(it) else Color(0.6, 0.6, 0.6),
					500, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
				if _picked.has(it):
					var tin: Dictionary = _pk_in.get(it, {"t": 1.0, "from": b.get_center()})
					if float(tin["t"]) < 1.0:                # (sliding into the pocket, getting smaller)
						var e := Kit.ease_out(float(tin["t"]))
						_draw_item(it, (tin["from"] as Vector2).lerp(pk.get_center() - Vector2(0, 20), e), lerpf(b.size.x * 0.8, 52.0, e))
					else:
						Hud.text(self, Vector2(b.position.x, b.get_center().y + 6), "✓", 26.0, Color(0.2, 0.45, 0.28), 700, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
					continue
				var at := b.get_center()
				if it == _drag_item:
					at = _thing
				elif _pk_back.has(it):                      # (let go off the pocket: back to its place)
					at = (_pk_back[it]["from"] as Vector2).lerp(b.get_center(), Kit.ease_out(float(_pk_back[it]["t"])))
				_draw_item(it, at + (Vector2(0, -4) if hov else Vector2.ZERO), b.size.x * (0.86 if it == _drag_item else 0.8))
			Hud.text(self, Vector2(area.position.x, area.end.y + 4), L("Drag each into the pocket, or ← → and Enter", "ஒவ்வொண்ணையும் பாக்கெட்டுக்குள்ள இழுங்க, அல்லது ← → பிறகு Enter"),
				14.0, Kit.PRINT, 400, HORIZONTAL_ALIGNMENT_CENTER, area.size.x)


# ---- meals ----
const FOOD_ITEMS := {"idli": ["idli", "idli", "idli", "idli", "vada"], "meals": ["rice", "sambar", "rasam", "poriyal", "kootu", "curd", "appalam"],
	"parotta": ["parotta", "parotta", "salna", "egg"], "dosa": ["dosa", "chutney", "sambar"],
	"curd_rice": ["curd rice", "pickle", "appalam"], "kanji": ["kanji", "pickle"], "jail_meals": ["rice", "sambar"]}
const FOOD_COL := {"idli": Color(0.97, 0.96, 0.9), "vada": Color(0.75, 0.5, 0.2), "rice": Color(0.97, 0.97, 0.94),
	"sambar": Color(0.8, 0.45, 0.12), "rasam": Color(0.7, 0.25, 0.1), "poriyal": Color(0.45, 0.65, 0.25),
	"kootu": Color(0.85, 0.75, 0.3), "curd": Color(0.98, 0.98, 0.96), "appalam": Color(0.95, 0.85, 0.55),
	"parotta": Color(0.9, 0.75, 0.45), "salna": Color(0.65, 0.3, 0.1), "egg": Color(0.98, 0.95, 0.85),
	"dosa": Color(0.88, 0.65, 0.3), "chutney": Color(0.95, 0.95, 0.85), "curd rice": Color(0.97, 0.97, 0.95),
	"pickle": Color(0.75, 0.2, 0.1), "kanji": Color(0.9, 0.88, 0.8)}


func _meal_food() -> String:
	if spec.get("home", false):
		return str(spec.get("food", "idli"))
	var menu: Array = spec.get("menu", [])
	return str(menu[_meal_pick].get("food", "meals")) if _meal_pick >= 0 and _meal_pick < menu.size() else "meals"


func _meal_rects() -> Dictionary:
	var p := _panel()
	var c := p.get_center() + Vector2(0, 10)
	var out := {}
	if _meal_pick < 0:
		var menu: Array = spec.get("menu", [])
		for i in menu.size():
			out["dish%d" % i] = Rect2(c + Vector2(-260, -150 + i * 78), Vector2(520, 64))
		out["leave"] = Rect2(c + Vector2(-150, 180), Vector2(300, 44))
	else:
		var items: Array = FOOD_ITEMS[_meal_food()]
		for i in items.size():
			var a := TAU * float(i) / items.size() - PI * 0.5
			out["item%d" % i] = Rect2(c + Vector2(cos(a) * 150, sin(a) * 110) - Vector2(48, 38), Vector2(96, 76))
	return out


func _meal_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed):
		return
	var r := _meal_rects()
	if _meal_pick < 0:
		var menu: Array = spec.get("menu", [])
		for i in menu.size():
			if r["dish%d" % i].has_point(e.position):
				var price := int(menu[i].get("price", 0))
				if price > int(spec.get("wallet", 1 << 30)):
					_say(L("Not enough money for that.", "அதுக்கு பணம் போதாது."), BAD)
					return
				_meal_pick = i
				dish_chosen.emit(_meal_food())
				_say(L("Paid ₹%d. Here's your plate." % price, "₹%d கொடுத்தாச்சு. இதோ சாப்பாடு." % price), GOOD)
		if r["leave"].has_point(e.position):
			_done({"paid": 0, "ate": false})
		queue_redraw()
		return
	for k in r:
		if r[k].has_point(e.position) and not _eaten.has(k):
			_eaten[k] = true
			if _eaten.size() == r.size():
				var paid := 0
				if not spec.get("home", false):
					paid = int(spec["menu"][_meal_pick].get("price", 0))
				_say(L("That was good.", "நல்லா இருந்துச்சு."), GOOD)
				get_tree().create_timer(0.8).timeout.connect(func(): _done({"paid": paid, "ate": true,
					"meal": _meal_food(), "minutes": int(spec.get("minutes", 15))}))
	queue_redraw()


func _draw_meal(p: Rect2) -> void:
	draw_rect(p, Color(0.93, 0.9, 0.82) if spec.get("home", false) else Color(0.86, 0.9, 0.84))
	var c := p.get_center() + Vector2(0, 10)
	var r := _meal_rects()
	_text(Vector2(p.position.x + 24, p.position.y + 40), t_(spec.get("title", {"en": "Meal", "ta": "சாப்பாடு"})), 24, DARK)
	if spec.has("wallet") and not spec.get("home", false):
		_text(Vector2(p.end.x - 260, p.position.y + 40), L("Wallet ", "பர்ஸ் ") + _rupees(int(spec["wallet"])), 20, DARK, 236, HORIZONTAL_ALIGNMENT_RIGHT)
	if _meal_pick < 0:
		var menu: Array = spec.get("menu", [])
		draw_rect(Rect2(c + Vector2(-290, -190), Vector2(580, 340)), Color(0.08, 0.28, 0.16))           # the menu board
		_text(c + Vector2(-290, -160), L("MENU", "மெனு"), 24, Color(1, 0.9, 0.5), 580, HORIZONTAL_ALIGNMENT_CENTER)
		for i in menu.size():
			var b: Rect2 = r["dish%d" % i]
			draw_rect(b, Color(1, 1, 1, 0.08))
			_text(b.position + Vector2(18, 41), t_(menu[i]["name"]), 22, Color(0.97, 0.97, 0.92))
			_text(b.position + Vector2(0, 41), "₹%d" % int(menu[i]["price"]), 22, Color(1, 0.85, 0.4), b.size.x - 18, HORIZONTAL_ALIGNMENT_RIGHT)
		_btn(r["leave"], L("Not hungry: leave", "பசியில்ல: போகலாம்"), true)
		_text(Vector2(c.x - 300, c.y + 250), L("Pick a dish (you pay at the counter)", "ஒரு உணவை தேர்ந்தெடு (கவுண்டரில் பணம்)"), 18, DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)
		return
	draw_circle(c + Vector2(0, -10), 210.0, Color(0.2, 0.45, 0.15))                   # the banana leaf
	draw_line(c + Vector2(-200, -10), c + Vector2(200, -10), Color(0.35, 0.6, 0.25), 3.0)
	var items: Array = FOOD_ITEMS[_meal_food()]
	for i in items.size():
		var k := "item%d" % i
		if _eaten.has(k):
			continue
		var b: Rect2 = r[k]
		var col: Color = FOOD_COL.get(items[i], Color.WHITE)
		draw_circle(b.get_center(), 36.0, col)
		draw_circle(b.get_center(), 36.0, col.darkened(0.25), false, 2.0)
		_text(Vector2(b.position.x - 10, b.end.y + 14), str(items[i]), 15, DARK, b.size.x + 20, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(c.x - 300, c.y + 230), L("Click each thing to eat it", "ஒவ்வொன்றையும் கிளிக் பண்ணி சாப்பிடு"), 18, DARK, 600, HORIZONTAL_ALIGNMENT_CENTER)


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
