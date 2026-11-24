extends Node
## Petrol bunks in the city (docs/PROLOGUE_PLAN_2026-11-17.md, the fuel stage): our own made-up brand ("Kongu Fuels",
## tools/cars/build_bunk.py) in real areas. They're landmarks (godot/assets/landmarks/landmarks.json, "bunk_*"): the
## city stands each on its levelled, cleared lot by a main road, solid, when its tile loads (city_streamer.gd); here
## the pumps' screens and the attendant are added to it, and the filling done. Their places were chosen by
## --bunksurvey: along the bigger roads near each one's rough position, the fewest buildings over the lot.
##   filling  a vehicle he owns (garage.gd), stopped in a bay beside a pump, E: the attendant asks how much (₹100,
##            ₹200, ₹500, a full tank), then cash or UPI (UPI declined while his account's frozen: money.gd); the
##            pump runs (its screen's rupees and litres climbing, the gauge rising), the money goes when it stops.
##   low fuel  under 15 % of the tank, a message, and the nearest bunk pinned on his phone's map.
## The story waits on `filled` (its "refuel" step).

const Garage := preload("res://scripts/city/garage.gd")
const PETROL_PAISE := Garage.PETROL_PAISE
const GLB := "res://assets/world/fuel_bunk.glb"
const BUNKS := [
	{"id": "peelamedu", "x": 4300.0, "z": -760.0, "en": "Kongu Fuels, Avinashi Road, Peelamedu", "ta": "கொங்கு ஃப்யூயல்ஸ், அவிநாசி ரோடு, பீளமேடு"},
	{"id": "ganapathy", "x": 820.0, "z": -2150.0, "en": "Kongu Fuels, Ganapathy", "ta": "கொங்கு ஃப்யூயல்ஸ், கணபதி"},
	{"id": "gandhipuram", "x": -1000.0, "z": 300.0, "en": "Kongu Fuels, 100 Feet Road", "ta": "கொங்கு ஃப்யூயல்ஸ், 100 அடி ரோடு"},
	{"id": "race_course", "x": 1150.0, "z": 1850.0, "en": "Kongu Fuels, Race Course", "ta": "கொங்கு ஃப்யூயல்ஸ், ரேஸ் கோர்ஸ்"},
	{"id": "ramanathapuram", "x": 3300.0, "z": 2200.0, "en": "Kongu Fuels, Trichy Road", "ta": "கொங்கு ஃப்யூயல்ஸ், திருச்சி ரோடு"},
	# (more of them, the user asked: one on each main road out of the city, in its real locality; places from their
	#  latitude and longitude on the city's origin, Gandhipuram 11.0183 N 76.9678 E, then settled by --bunksurvey)
	{"id": "saibaba_colony", "x": -2054.0, "z": -962.0, "en": "Kongu Fuels, Mettupalayam Road, Saibaba Colony", "ta": "கொங்கு ஃப்யூயல்ஸ், மேட்டுப்பாளையம் ரோடு, சாயிபாபா காலனி"},
	{"id": "thudiyalur", "x": -2491.0, "z": -6712.0, "en": "Kongu Fuels, Mettupalayam Road, Thudiyalur", "ta": "கொங்கு ஃப்யூயல்ஸ், மேட்டுப்பாளையம் ரோடு, துடியலூர்"},
	{"id": "hope_college", "x": 6032.0, "z": -1073.0, "en": "Kongu Fuels, Avinashi Road, Hope College", "ta": "கொங்கு ஃப்யூயல்ஸ், அவிநாசி ரோடு, ஹோப் காலேஜ்"},
	{"id": "singanallur", "x": 6687.0, "z": 2134.0, "en": "Kongu Fuels, Trichy Road, Singanallur", "ta": "கொங்கு ஃப்யூயல்ஸ், திருச்சி ரோடு, சிங்காநல்லூர்"},
	{"id": "saravanampatti", "x": 3518.0, "z": -6601.0, "en": "Kongu Fuels, Sathy Road, Saravanampatti", "ta": "கொங்கு ஃப்யூயல்ஸ், சத்தி ரோடு, சரவணம்பட்டி"},
	{"id": "ukkadam", "x": -699.0, "z": 2853.0, "en": "Kongu Fuels, Palakkad Road, Ukkadam", "ta": "கொங்கு ஃப்யூயல்ஸ், பாலக்காடு ரோடு, உக்கடம்"},
	{"id": "kuniyamuthur", "x": -1945.0, "z": 5672.0, "en": "Kongu Fuels, Palakkad Road, Kuniyamuthur", "ta": "கொங்கு ஃப்யூயல்ஸ், பாலக்காடு ரோடு, குனியமுத்தூர்"},
	{"id": "sundarapuram", "x": 1333.0, "z": 6999.0, "en": "Kongu Fuels, Pollachi Road, Sundarapuram", "ta": "கொங்கு ஃப்யூயல்ஸ், பொள்ளாச்சி ரோடு, சுந்தராபுரம்"},
	{"id": "vadavalli", "x": -6862.0, "z": -741.0, "en": "Kongu Fuels, Maruthamalai Road, Vadavalli", "ta": "கொங்கு ஃப்யூயல்ஸ், மருதமலை ரோடு, வடவள்ளி"},
]
const ROAD_KINDS := ["trunk", "primary", "secondary", "tertiary", "unclassified", "residential"]
const FLOW_LPS := 0.45                # litres a second from the nozzle
const LOW := 0.15

signal filled(vehicle_id: String, litres: float, rupees: int)

var city
var placed := {}                      # id → {node, origin, yaw, bays: [Vector3], screens: [Label3D]}
var _tried := {}                      # id → the time it last looked for a place (and found none)
var _ui: Control
var _state := ""                      # "" | "ask" | "pay" | "filling"
var _bay := {}                        # {bunk, i}
var _ask_litres := 0.0
var _ask_rupees := 0
var _paid_how := ""
var _put := 0.0
var _label: Label
var _e_down := false
var _warned := false
var _t := 0.0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-200, -150)
	_label.size = Vector2(400, 30)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_label)
	_ui = Control.new()
	_ui.visible = false
	layer.add_child(_ui)
	if "--bunktest" in OS.get_cmdline_user_args():
		_test.call_deferred()
	if " ".join(OS.get_cmdline_user_args()).contains("--bunksurvey"):   # (--bunksurvey, or --bunksurvey=id,id)
		_survey.call_deferred()
	if " ".join(OS.get_cmdline_user_args()).contains("--npcbunktest"):   # (--npcbunktest[=bunk id])
		_npc_test.call_deferred()
	if "--furnituretest" in OS.get_cmdline_user_args():
		_furniture_test.call_deferred()


func lang() -> String:
	return city.story.lang if city.story else "en"


func L(en: String, ta: String) -> String:
	return ta if lang() == "ta" else en


# ---- the bunks the city has stood up ----
## (Godot local, from the model's Blender empties: Bay_n at (±3.2, −0.6), the screens at (±3.2, 0.73, 1.6), the
##  attendant at (±3.2 + 0.9, 0.2): Blender (x, y, z) is Godot (x, z, −y))
const BAYS := [Vector3(-3.2, 0.0, 0.6), Vector3(3.2, 0.0, 0.6)]
const SCREENS := [Vector3(-3.2, 1.6, -0.7), Vector3(3.2, 1.6, -0.7)]
const ATTENDANT := Vector3(-2.3, 0.0, -0.2)

func _process(dt: float) -> void:
	if city == null or city.streamer == null:
		return
	_t += dt
	for lm in city.streamer.landmarks:
		var nm := str(lm.get("name", ""))
		if not nm.begins_with("bunk_"):
			continue
		var id := nm.substr(5)
		var k := Vector2i(floori(float(lm["x"]) / city.streamer.tile), floori(float(lm["z"]) / city.streamer.tile))
		var tile: Node3D = city.streamer.loaded.get(k)
		if tile == null:
			if placed.has(id):
				placed.erase(id)                       # (its tile's gone: the screens and the man with it)
			continue
		if placed.has(id) and is_instance_valid(placed[id]["tile"]) and placed[id]["tile"] == tile:
			continue
		_decorate(id, lm, tile)
	var dark: bool = city.fines.sim.daylight() < 0.35 if city.fines else false
	for id in placed:
		for l in placed[id].get("lights", []):
			if is_instance_valid(l):
				(l as Light3D).visible = dark
	_interact(dt)
	_low_fuel()


func _decorate(id: String, lm: Dictionary, tile: Node3D) -> void:
	var xf := Transform3D(Basis(Vector3.UP, float(lm["yaw"])), Vector3(float(lm["x"]), float(lm["y"]), float(lm["z"])))
	var rec := {"tile": tile, "origin": xf.origin, "xf": xf, "bays": [], "screens": [], "b": {}, "men": [], "busy": {}}
	for b in BUNKS:
		if str(b["id"]) == id:
			rec["b"] = b
	for i in 2:
		rec["bays"].append(xf * BAYS[i])
		var l := Label3D.new()
		l.font_size = 40
		l.pixel_size = 0.0022
		l.modulate = Color(1.0, 0.45, 0.15)
		l.outline_size = 0
		l.text = "  0.00\n 0.00 L\n101.50"
		tile.add_child(l)
		l.global_transform = Transform3D(xf.basis, xf * SCREENS[i] + xf.basis.z * 0.03)
		rec["screens"].append(l)
	if ResourceLoader.exists("res://assets/people/crowd_m4.glb"):
		var man := (load("res://assets/people/crowd_m4.glb") as PackedScene).instantiate() as Node3D
		tile.add_child(man)
		man.global_position = xf * ATTENDANT
		man.look_at(man.global_position + xf.basis.z, Vector3.UP)
		man.rotate_y(PI)                                 # (the models face their −Z: he looks at the bay)
		rec["men"].append(man)
		for ap in man.find_children("*", "AnimationPlayer", true, false):
			var p := ap as AnimationPlayer
			for an in ["Idle", "idle", "Stand"]:
				if p.has_animation(an):
					p.get_animation(an).loop_mode = Animation.LOOP_LINEAR
					p.play(an)
					break
	# a second attendant at the other pump, a customer's motorcycle on its stand by the air stand
	for extra in [["res://assets/people/crowd_m2.glb", Vector3(4.1, 0.0, -0.2)], ["res://assets/vehicles/bike_motorcycle_1.glb", Vector3(-8.6, 0.0, -4.2)]]:   # (the bike by the
		                                                 #  cashier's building, off the way in and out: cars drive the front)
		if ResourceLoader.exists(str(extra[0])):
			var e := (load(str(extra[0])) as PackedScene).instantiate() as Node3D
			tile.add_child(e)
			e.global_position = xf * (extra[1] as Vector3)
			e.global_basis = xf.basis.rotated(Vector3.UP, PI * 0.5 if str(extra[0]).contains("bike") else PI)
			if not str(extra[0]).contains("bike"):
				rec["men"].append(e)                     # (the second pump's attendant)
			for ap in e.find_children("*", "AnimationPlayer", true, false):
				var p := ap as AnimationPlayer
				for an in ["Idle", "idle", "Stand"]:
					if p.has_animation(an):
						p.get_animation(an).loop_mode = Animation.LOOP_LINEAR
						p.play(an)
						break
	# the canopy's lights after dark: four downlights over the pumps, one at the sales window (no shadows: cheap)
	var lights: Array = []
	for lp in [Vector3(-4.8, 5.0, -1.0), Vector3(-1.6, 5.0, -1.0), Vector3(1.6, 5.0, -1.0), Vector3(4.8, 5.0, -1.0), Vector3(0.0, 2.9, -5.4)]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.97, 0.9)
		sl.light_energy = 3.0
		sl.spot_range = 9.0
		sl.spot_angle = 62.0
		sl.shadow_enabled = false
		tile.add_child(sl)
		sl.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), xf * lp)
		sl.visible = false
		lights.append(sl)
	rec["lights"] = lights
	placed[id] = rec
	print("BUNK %s at (%.0f, %.0f)" % [id, xf.origin.x, xf.origin.z])


# ---- the city's own customers (city_traffic.gd brings cars, autos and taxis in) ----

## A bay a visiting vehicle may take: free of another visitor and of him (his vehicle stopped there); -1 if none.
func free_bay(id: String, from_side := 0.0) -> int:
	if not placed.has(id):
		return -1
	var rec: Dictionary = placed[id]
	# (in at the −X opening: the +X pump first, a long straight glide to it; in at the +X one, the −X pump first)
	var order := ([1, 0] if from_side > 0.0 else [0, 1]) if from_side != 0.0 else ([0, 1] if randf() < 0.5 else [1, 0])
	for i in order:
		if (rec["busy"] as Dictionary).has(i):
			continue
		var bay: Vector3 = rec["bays"][i]
		if city.car and Vector2(city.car.global_position.x - bay.x, city.car.global_position.z - bay.z).length() < 6.0:
			continue
		if not _bay.is_empty() and str(_bay.get("bunk", "")) == id and int(_bay.get("i", -1)) == i:
			continue
		return i
	return -1


func take_bay(id: String, i: int, who) -> void:
	if placed.has(id):
		placed[id]["busy"][i] = who


func leave_bay(id: String, i: int) -> void:
	if placed.has(id):
		(placed[id]["busy"] as Dictionary).erase(i)
		var men: Array = placed[id]["men"]
		if i < men.size() and is_instance_valid(men[i]):      # (the attendant back to facing his pump's island)
			var xf: Transform3D = placed[id]["xf"]
			var m: Node3D = men[i]
			m.look_at(m.global_position + xf.basis.z, Vector3.UP)
			m.rotate_y(PI)


## A visitor being filled: the attendant at that pump turned to its tank side, the pump's screen counting up (the
## same screen and prices as his own filling).
func npc_serve(id: String, i: int, litres: float, at: Vector3) -> void:
	if not placed.has(id):
		return
	var rec: Dictionary = placed[id]
	var men: Array = rec["men"]
	if i < men.size() and is_instance_valid(men[i]):
		var m: Node3D = men[i]
		var to := Vector3(at.x, m.global_position.y, at.z)
		if to.distance_to(m.global_position) > 0.3:
			m.look_at(to, Vector3.UP)
			m.rotate_y(PI)                                    # (the models face their −Z)
	var scr: Label3D = rec["screens"][i]
	if is_instance_valid(scr):
		scr.text = "%6.2f\n%5.2f L\n101.50" % [litres * PETROL_PAISE / 100.0, litres]


## What a car must not drive into on the forecourt (the lot's frame, from tools/cars/build_bunk.py, Blender y → −z):
## [centre x, centre z, half x, half z]: the price board's totem, the two pump islands with their barriers, the air and
## water stand, the sand stand, the parked bike, the cashier's building. city_traffic.gd keeps its paths clear of them.
const SOLIDS := [[-10.3, 5.6, 1.0, 0.45], [-3.2, -1.0, 2.95, 0.7], [3.2, -1.0, 2.95, 0.7], [9.6, 2.5, 0.4, 0.35],
	[-8.4, -8.0, 0.8, 0.25], [-8.6, -4.2, 1.1, 0.5], [0.0, -6.5, 6.5, 2.5]]


## The nearest bunk to p: {id, pos, name} (placed or not: its rough place, until it's found its own).
func nearest(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for b in BUNKS:
		var at := Vector3(float(b["x"]), 0.0, float(b["z"]))
		if placed.has(b["id"]):
			at = placed[b["id"]]["origin"]
		var d := Vector2(at.x - p.x, at.z - p.z).length()
		if d < bd:
			bd = d
			best = {"id": b["id"], "pos": at, "name": {"en": b["en"], "ta": b["ta"]}}
	return best


# ---- filling ----
func _interact(dt: float) -> void:
	var g = city.get("garage")
	if g == null or city.car == null:
		_label.text = ""
		return
	if _state == "filling":
		_fill(dt)
		return
	if _state != "":
		return
	_label.text = ""
	if city.walker != null or str(g.current).is_empty():
		return
	var car = city.car
	if absf(float(car.speed)) > 0.6:
		return
	for id in placed:
		var rec: Dictionary = placed[id]
		for i in (rec["bays"] as Array).size():
			var bay: Vector3 = rec["bays"][i]
			if Vector2(car.global_position.x - bay.x, car.global_position.z - bay.z).length() < 3.0:
				var v: Dictionary = g.vehicle(str(g.current))
				var room := float(v["tank_l"]) - float(v["fuel_l"])
				if room < 0.2:
					_label.text = L("The tank's full.", "டேங்க் நிறைஞ்சிருக்கு.")
					return
				_label.text = L("E: fill petrol", "E: பெட்ரோல் போடுங்க")
				var e := Input.is_key_pressed(KEY_E)
				if e and not _e_down:
					_bay = {"bunk": id, "i": i}
					_ask(v)
				_e_down = e
				return
	_e_down = Input.is_key_pressed(KEY_E)


func _panel() -> VBoxContainer:
	for c in _ui.get_children():
		c.queue_free()
	_ui.visible = true
	var vp := _ui.get_viewport_rect().size
	_ui.position = Vector2.ZERO
	_ui.size = vp
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.95)
	sb.border_color = Color(0.02, 0.32, 0.16)
	sb.border_width_top = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(460, 0)
	pc.position = Vector2(vp.x * 0.5 - 230, vp.y * 0.42)
	_ui.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pc.add_child(box)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return box


func _lbl(box: Control, t: String, sz := 18, col := Color(0.92, 0.92, 0.92)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l)
	return l


func _btn(box: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _ask(v: Dictionary) -> void:
	_state = "ask"
	var room := float(v["tank_l"]) - float(v["fuel_l"])
	var full := int(ceil(room * PETROL_PAISE / 100.0))
	var box := _panel()
	_lbl(box, L("Attendant", "பங்க் ஊழியர்"), 15, Color(0.6, 0.85, 0.65))
	_lbl(box, L("How much, sir? Petrol ₹101.50 a litre. The tank takes %.1f L more." % room,
		"எவ்வளவு சார்? பெட்ரோல் லிட்டர் ₹101.50. இன்னும் %.1f லி. போகும்." % room), 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for amt in [100, 200, 500]:
		if float(amt) * 100.0 / PETROL_PAISE > room + 0.05:
			continue
		_btn(row, "₹%d" % amt, func() -> void:
			_ask_rupees = amt
			_ask_litres = float(amt) * 100.0 / PETROL_PAISE
			_pay())
	_btn(row, L("Full tank (₹%d)" % full, "ஃபுல் டேங்க் (₹%d)" % full), func() -> void:
		_ask_litres = room
		_ask_rupees = full
		_pay())
	_btn(box, L("Not now", "இப்போ வேண்டாம்"), _close)


func _pay() -> void:
	_state = "pay"
	var box := _panel()
	_lbl(box, L("₹%d of petrol. Cash or UPI?" % _ask_rupees, "₹%d பெட்ரோல். கேஷா, UPI-ஆ?" % _ask_rupees), 18)
	var cash: int = int(city.fines.sim.money)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var cb := _btn(row, L("Cash (₹%d on him)" % cash, "கேஷ் (கையில் ₹%d)" % cash), func() -> void:
		_paid_how = "cash"
		_start())
	cb.disabled = cash < _ask_rupees
	_btn(row, "UPI", func() -> void:
		_paid_how = "upi"
		_start())
	_btn(box, L("Not now", "இப்போ வேண்டாம்"), _close)


func _start() -> void:
	if _paid_how == "upi" and city.money and bool(city.money.frozen):
		city.money.pay_online(_ask_rupees, "Kongu Fuels")       # (the bank's refusal on his phone)
		_paid_how = ""
		_pay()
		return
	_state = "filling"
	_put = 0.0
	for c in _ui.get_children():
		c.queue_free()
	_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	city.car.freeze = true


func _fill(dt: float) -> void:
	var g = city.garage
	var step := minf(FLOW_LPS * dt, _ask_litres - _put)
	var r: Dictionary = g.refuel(str(g.current), step)
	_put += float(r["litres"])
	var rs := _put * PETROL_PAISE / 100.0
	var rec: Dictionary = placed.get(str(_bay.get("bunk", "")), {})
	var screens: Array = rec.get("screens", [])
	var i := int(_bay.get("i", 0))
	if i < screens.size():
		(screens[i] as Label3D).text = "%7.2f\n%5.2f L\n101.50" % [rs, _put]
	_label.text = L("Filling... ₹%.2f, %.2f L" % [rs, _put], "நிரப்புகிறது... ₹%.2f, %.2f லி." % [rs, _put])
	if _put >= _ask_litres - 0.001 or float(r["litres"]) <= 0.0 and step > 0.0:
		var rupees := int(ceil(rs - 0.001))
		if _paid_how == "upi" and city.money:
			if not city.money.pay_online(rupees, "Kongu Fuels"):
				city.fines.sim.money = maxi(int(city.fines.sim.money) - rupees, 0)
		else:
			city.fines.sim.money -= rupees
		city.car.freeze = false
		_state = ""
		_warned = false
		var vid := str(g.current)
		g.save()
		print("BUNK filled %s: %.2f L for ₹%d (%s); tank %.2f / %.1f L" % [vid, _put, rupees, _paid_how,
			float(g.vehicle(vid)["fuel_l"]), float(g.vehicle(vid)["tank_l"])])
		filled.emit(vid, _put, rupees)
		if city.get("hud") and city.hud.has_method("say"):
			city.hud.say(L("Attendant", "பங்க் ஊழியர்"), L("₹%d, sir. Check the meter: zero to start, as you saw." % rupees,
				"₹%d சார். மீட்டர் பாருங்க: பூஜ்யத்துல ஆரம்பிச்சது." % rupees), 3.0)


func _close() -> void:
	for c in _ui.get_children():
		c.queue_free()
	_ui.visible = false
	_state = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## (testing) the attendant asked for a full tank, paid in cash.
func auto_fill() -> bool:
	if _state != "":
		return false
	var g = city.garage
	var v: Dictionary = g.vehicle(str(g.current))
	if v.is_empty():
		return false
	_ask_litres = float(v["tank_l"]) - float(v["fuel_l"])
	_ask_rupees = int(ceil(_ask_litres * PETROL_PAISE / 100.0))
	_paid_how = "cash"
	_start()
	return true


func _low_fuel() -> void:
	var g = city.get("garage")
	if g == null or str(g.current).is_empty() or _warned or city.phone == null:
		return
	var v: Dictionary = g.vehicle(str(g.current))
	if v.is_empty() or float(v["fuel_l"]) / float(v["tank_l"]) > LOW:
		return
	_warned = true
	var nb := nearest(city.car.global_position)
	if nb.is_empty():
		return
	city.phone.message({"en": "Fuel", "ta": "எரிபொருள்"}, {"en": "The fuel light's on: about %.1f L left. Nearest bunk: %s." % [float(v["fuel_l"]), nb["name"]["en"]],
		"ta": "எரிபொருள் விளக்கு எரியுது: சுமார் %.1f லி. மிச்சம். அருகில் பங்க்: %s." % [float(v["fuel_l"]), nb["name"]["ta"]]})
	if city.get("map") and city.map.get("pin") != null or city.get("map"):
		city.map.pin = Vector2(nb["pos"].x, nb["pos"].z)       # (the nearest bunk on the map)


# ---- testing ----
## --bunktest: on the old scooter, at the Ganapathy bunk once it's found its place: stopped in a bay, a full tank paid
## in cash; pictures of the bunk and of the pump's screen (user://bunk_*.jpg).
func _test() -> void:
	var tree := get_tree()
	await tree.create_timer(4.0).timeout
	city.car.configure("karthik_scooter")
	var b: Dictionary = BUNKS[1]
	for lm in city.streamer.landmarks:                 # (to its lot: where the survey stood it)
		if str(lm.get("name", "")) == "bunk_" + str(b["id"]):
			city.car.global_position = Vector3(float(lm["x"]), float(lm["y"]) + 30.0, float(lm["z"]))
	var t0 := Time.get_ticks_msec()
	while not placed.has(b["id"]) and Time.get_ticks_msec() - t0 < 60000:
		await tree.create_timer(0.5).timeout
	if not placed.has(b["id"]):
		print("BUNKTEST FAIL: no place found for %s" % b["id"])
		tree.quit()
		return
	var rec: Dictionary = placed[b["id"]]
	var bay: Vector3 = rec["bays"][0]
	var xf: Transform3D = rec["xf"]
	var road: Vector3 = xf.origin + xf.basis.z * 12.0
	city.car.global_transform = Transform3D(Basis(Vector3.UP, atan2(xf.basis.x.x, xf.basis.x.z)), bay + Vector3.UP * 0.6)
	city.car.linear_velocity = Vector3.ZERO
	await tree.create_timer(2.0).timeout
	var cam := Camera3D.new()
	city.add_child(cam)
	cam.global_position = road + Vector3.UP * 3.5 + xf.basis.x * 10.0
	cam.look_at(xf.origin + Vector3.UP * 2.0)
	cam.make_current()
	for f in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://bunk_wide.jpg"), 0.85)
	var g = city.garage
	var v: Dictionary = g.vehicle(str(g.current))
	print("BUNKTEST on %s, fuel %.2f / %.1f L, wallet ₹%d, prompt '%s'" % [str(g.current), float(v.get("fuel_l", 0)), float(v.get("tank_l", 0)), int(city.fines.sim.money), _label.text])
	var money0 := int(city.fines.sim.money)
	city.fines.sim.money = maxi(money0, 1000)
	money0 = int(city.fines.sim.money)
	_bay = {"bunk": b["id"], "i": 0}
	if not auto_fill():
		print("BUNKTEST FAIL: not on an owned vehicle")
		tree.quit()
		return
	var scr: Label3D = rec["screens"][0]
	cam.global_position = scr.global_position + xf.basis.z * 1.6 + Vector3.UP * 0.2
	cam.look_at(scr.global_position)
	await tree.create_timer(3.0).timeout
	for f in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("user://bunk_pump.jpg"), 0.85)
	while _state == "filling":
		await tree.process_frame
	v = g.vehicle(str(g.current))
	var paid := money0 - int(city.fines.sim.money)
	var expect := int(ceil(_put * PETROL_PAISE / 100.0 - 0.001))
	print("BUNKTEST filled %.2f L, paid ₹%d (expect ₹%d), tank %.2f / %.1f L, gauge %.2f" % [_put, paid, expect, float(v["fuel_l"]), float(v["tank_l"]), float(city.car.fuel_frac)])
	print("BUNKTEST %s" % ("PASS" if paid == expect and absf(float(v["fuel_l"]) - float(v["tank_l"])) < 0.01 and absf(float(city.car.fuel_frac) - 1.0) < 0.01 else "FAIL"))
	tree.quit()


## --npcbunktest: the city's own vehicles at the 100 Feet Road bunk: his vehicle parked at the lot's back corner (out
## of the way), every car, auto and taxi passing the way in turning in (city_traffic.gd bunk_chance 1), a fixed camera
## across the road; a picture every 2 s for 4 minutes (user://npcbunk/), each visit's stages printed (NPCBUNK).
func _npc_test() -> void:
	var tree := get_tree()
	await tree.create_timer(4.0).timeout
	var b: Dictionary = BUNKS[2]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--npcbunktest="):
			for bb in BUNKS:
				if str(bb["id"]) == a.get_slice("=", 1):
					b = bb
	for lm in city.streamer.landmarks:
		if str(lm.get("name", "")) == "bunk_" + str(b["id"]):
			city.car.global_position = Vector3(float(lm["x"]), float(lm["y"]) + 30.0, float(lm["z"]))
	var t0 := Time.get_ticks_msec()
	while not placed.has(b["id"]) and Time.get_ticks_msec() - t0 < 60000:
		await tree.create_timer(0.5).timeout
	if not placed.has(b["id"]):
		print("NPCBUNK FAIL: no place found for %s" % b["id"])
		tree.quit()
		return
	var rec: Dictionary = placed[b["id"]]
	var xf: Transform3D = rec["xf"]
	city.car.global_transform = Transform3D(xf.basis, xf * Vector3(-10.5, 0.6, -5.5))
	city.car.linear_velocity = Vector3.ZERO
	var tr = city.get("traffic")
	if tr:
		tr.bunk_chance = 1.0
		tr.bunk_log = true
		await tree.create_timer(3.0).timeout
		_roads_through(tr)
	var cam := Camera3D.new()
	city.add_child(cam)
	cam.global_position = xf * Vector3(0.0, 7.5, 24.0)
	cam.look_at(xf * Vector3(0.0, 0.5, 2.0))
	cam.fov = 62.0
	cam.make_current()
	var dir := ProjectSettings.globalize_path("user://npcbunk")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in 120:
		await tree.create_timer(2.0).timeout
		if tr and f % 5 == 0:                               # (where the traffic is: how many, the nearest to the lot)
			var near := []
			for v in tr.vehicles:
				var lp: Vector3 = xf.affine_inverse() * (v["pos"] as Vector3)
				if lp.length() < 80.0:
					var lf: Vector3 = xf.basis.inverse() * (v["fwd"] as Vector3)
					near.append("%s at (%.0f, %.0f) heading %.2f" % [v["kind"], lp.x, lp.z, lf.x])
			print("NPCBUNK traffic %d vehicles, %d within 80 m: %s" % [tr.vehicles.size(), near.size(), "; ".join(PackedStringArray(near.slice(0, 5)))])
		cam.make_current()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("%s/f_%03d.jpg" % [dir, f], 0.8)
	print("NPCBUNK done")
	tree.quit()


## (testing) --furnituretest: the street's furniture solid to a car (city_streamer.gd: it was solid only to people on
## foot, and cars drove through bins and poles). His car set 9 m from one of the poles, signs, bins, bollards, trees or
## stalls near Gandhipuram, aimed at it, at 30 km/h; for each of six: how near its middle the car's middle came, and
## its speed after. A pass: it stopped or glanced off at the thing's surface, never through it. (In this node because
## it's in every city run.)
func _furniture_test() -> void:
	var tree := get_tree()
	await tree.create_timer(8.0).timeout
	var car = city.car
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var probe := BoxShape3D.new()
	probe.size = Vector3(120, 8, 120)
	q.shape = probe
	q.transform = Transform3D(Basis(), car.global_position)
	q.collision_mask = 1
	q.collide_with_bodies = true
	var found: Array = []
	for hit in space.intersect_shape(q, 400):
		if hit["collider"] == city.streamer.street_body:
			var xf := PhysicsServer3D.body_get_shape_transform(hit["rid"], int(hit["shape"]))
			found.append(xf.origin)
	print("FURNTEST %d furniture shapes solid to cars near the start" % found.size())
	var tried := 0
	var passed := 0
	for at in found:
		if tried >= 6:
			break
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		var from: Vector3 = at - dir * 9.0
		var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.8, at + Vector3.UP * 0.8 - dir * 0.6)
		ray.exclude = [car.get_rid()]
		var rh := space.intersect_ray(ray)
		if not rh.is_empty():                              # (something else in the way: another one)
			continue
		tried += 1
		car.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(from.x, at.y + 0.7, from.z))
		car.linear_velocity = dir * 8.33
		car.angular_velocity = Vector3.ZERO
		var nearest := INF
		for f in 150:
			await tree.physics_frame
			var d := Vector2(car.global_position.x - at.x, car.global_position.z - at.z).length()
			nearest = minf(nearest, d)
			if car.global_position.distance_to(from) > 14.0:
				break
		var past: bool = (car.global_position - at).dot(dir) > 1.5     # (its middle beyond the thing: through it)
		var ok: bool = not past and nearest > 0.9
		passed += 1 if ok else 0
		print("FURNTEST at (%.0f, %.0f): nearest %.2f m, speed after %.1f m/s, %s" % [at.x, at.z, nearest, car.linear_velocity.length(), "stopped or glanced off" if ok else "WENT THROUGH"])
	print("FURNTEST %d of %d stopped or glanced off" % [passed, tried])
	tree.quit()


## (testing) The road pieces that run over a placed bunk's lot (|x| < 12.5 m along the road, −10 m to +7.5 m across:
## the forecourt, the pumps, the building behind), each bunk: "NPCBUNK road over <id>: class, metres inside".
func _roads_through(tr) -> void:
	var seen := {}
	for k in tr.ends:
		for e in tr.ends[k]:
			seen[e[0]] = true
	for id in placed:
		var xf: Transform3D = placed[id]["xf"]
		var inv := xf.affine_inverse()
		var hits := 0
		for r in seen:
			var p: PackedFloat32Array = r["p"]
			var n := p.size() / 3
			var inside := 0.0
			for i in n - 1:
				var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
				var steps := maxi(1, int(a.distance_to(b) / 1.0))
				for k2 in steps:
					var q := inv * a.lerp(b, float(k2) / steps)
					if absf(q.x) < 12.5 and q.z > -10.0 and q.z < 7.5:
						inside += a.distance_to(b) / steps
			if inside > 0.5:
				hits += 1
				print("NPCBUNK road over %s: %s, %.0f m inside the lot" % [id, str(r.get("c", "?")), inside])
		print("NPCBUNK %s: %d road pieces over its lot" % [id, hits])


## (development) --bunksurvey: each bunk's best place along the bigger roads near its rough position, buildings
## allowed (their lot is cleared, as landmarks' are): the bigger the road, the fewer buildings to clear, the nearer,
## the better. Prints a landmarks.json entry for each (godot/assets/landmarks/landmarks.json).
const RANK := {"trunk": 0, "primary": 1, "secondary": 2, "tertiary": 3}

func _survey() -> void:
	var tree := get_tree()
	var only := []                                       # (--bunksurvey=id,id: just those)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bunksurvey="):
			only = Array(a.get_slice("=", 1).split(","))
	for b in BUNKS:
		if not only.is_empty() and not str(b["id"]) in only:
			continue
		city.car.global_position = Vector3(float(b["x"]), 60.0, float(b["z"]))
		city.car.freeze = true
		await tree.create_timer(12.0).timeout
		var want := Vector2(float(b["x"]), float(b["z"]))
		var best := {}
		var best_s := INF
		for k in city.streamer.loaded:
			var node: Node3D = city.streamer.loaded[k]
			for r in node.get_meta("roads", []):
				if not RANK.has(str(r["c"])) or r.get("fly", false) or r.get("under", false):
					continue
				var p: PackedFloat32Array = r["p"]
				var npt := p.size() / 3
				var along := 0.0
				var next_at := 15.0
				for i in range(npt - 1):
					var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
					var c := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
					var sl := Vector2(c.x - a.x, c.z - a.z).length()
					while sl > 0.01 and along + sl >= next_at:
						var on := a.lerp(c, (next_at - along) / sl)
						next_at += 10.0
						var d := Vector2(on.x, on.z).distance_to(want)
						if d > 450.0:
							continue
						var dir := Vector3(c.x - a.x, 0.0, c.z - a.z).normalized()
						var n := Vector3(-dir.z, 0.0, dir.x)
						for side in [1.0, -1.0]:
							var o: Vector3 = on + n * side * (float(r["w"]) * 0.5 + 1.2 + 6.5)
							var ydir: Vector3 = n * side
							var nb := _blocks_over(o, dir, ydir)
							var s := float(RANK[str(r["c"])]) * 40.0 + float(nb) * 12.0 + d / 15.0
							if s < best_s and _roads_over(o, dir, ydir, r) > 0.5:
								continue                         # (another road through the lot: never on a road)
							if s < best_s:
								best_s = s
								var bz := -ydir
								var poly: Array = []
								for cc in [[-12.0, -7.5], [12.0, -7.5], [12.0, 9.8], [-12.0, 9.8]]:
									var q: Vector3 = o + dir * float(cc[0]) + ydir * float(cc[1])
									poly.append([snappedf(q.x, 0.01), snappedf(q.z, 0.01)])
								best = {"name": "bunk_" + str(b["id"]), "glb": GLB, "x": snappedf(o.x, 0.01), "y": snappedf(on.y, 0.01), "z": snappedf(o.z, 0.01),
									"yaw": snappedf(atan2(bz.x, bz.z), 0.0001), "lots": [], "clear": poly, "pad": [-12, 12, -8, 10],
									"_road": str(r["c"]), "_blocks": nb, "_d": snappedf(d, 1.0)}
					along += sl
		print("BUNKSURVEY " + JSON.stringify(best))
	tree.quit()


## How many metres of road (any road but `own`, the one it fronts; not flyovers or underpasses) run inside the lot
## (the same rectangle as _blocks_over, a metre of margin round it). The first survey didn't look: the 100 Feet Road
## bunk stood across a trunk road and a residential street, and the traffic drove between its pumps.
func _roads_over(o: Vector3, xdir: Vector3, ydir: Vector3, own: Dictionary) -> float:
	var inside := 0.0
	for k in city.streamer.loaded:
		for r in (city.streamer.loaded[k] as Node3D).get_meta("roads", []):
			if r == own or r.get("fly", false) or r.get("under", false):
				continue
			var p: PackedFloat32Array = r["p"]
			var n := p.size() / 3
			for i in n - 1:
				var a := Vector3(p[i * 3], 0.0, p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], 0.0, p[i * 3 + 5])
				if Vector2(a.x - o.x, a.z - o.z).length() > 80.0 and Vector2(b.x - o.x, b.z - o.z).length() > 80.0:
					continue
				var steps := maxi(1, int(a.distance_to(b)))
				for j in steps:
					var q := a.lerp(b, (float(j) + 0.5) / steps) - Vector3(o.x, 0.0, o.z)
					var lx := q.dot(xdir)
					var ly := q.dot(ydir)
					if absf(lx) < 13.0 and ly > -8.5 and ly < 10.8:
						inside += a.distance_to(b) / steps
	return inside


func _blocks_over(o: Vector3, xdir: Vector3, ydir: Vector3) -> int:
	var rect := PackedVector2Array()
	for c in [[-12.0, -7.5], [12.0, -7.5], [12.0, 9.8], [-12.0, 9.8]]:
		var q: Vector3 = o + xdir * float(c[0]) + ydir * float(c[1])
		rect.append(Vector2(q.x, q.z))
	var nb := 0
	for k in city.streamer.loaded:
		for bi in (city.streamer.loaded[k] as Node3D).get_meta("bldinfo", []):
			var ctr = bi[1]
			var cv := Vector2(ctr.x, ctr.y) if ctr is Vector2 else Vector2(ctr.x, ctr.z)
			if cv.distance_to(Vector2(o.x, o.z)) > 60.0:
				continue
			if not Geometry2D.intersect_polygons(rect, bi[0]).is_empty():
				nb += 1
	return nb
