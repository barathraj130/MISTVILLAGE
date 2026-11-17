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
	if "--bunksurvey" in OS.get_cmdline_user_args():
		_survey.call_deferred()


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
	_interact(dt)
	_low_fuel()


func _decorate(id: String, lm: Dictionary, tile: Node3D) -> void:
	var xf := Transform3D(Basis(Vector3.UP, float(lm["yaw"])), Vector3(float(lm["x"]), float(lm["y"]), float(lm["z"])))
	var rec := {"tile": tile, "origin": xf.origin, "xf": xf, "bays": [], "screens": [], "b": {}}
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
		for ap in man.find_children("*", "AnimationPlayer", true, false):
			var p := ap as AnimationPlayer
			for an in ["Idle", "idle", "Stand"]:
				if p.has_animation(an):
					p.get_animation(an).loop_mode = Animation.LOOP_LINEAR
					p.play(an)
					break
	placed[id] = rec
	print("BUNK %s at (%.0f, %.0f)" % [id, xf.origin.x, xf.origin.z])


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


## (development) --bunksurvey: each bunk's best place along the bigger roads near its rough position, buildings
## allowed (their lot is cleared, as landmarks' are): the bigger the road, the fewer buildings to clear, the nearer,
## the better. Prints a landmarks.json entry for each (godot/assets/landmarks/landmarks.json).
const RANK := {"trunk": 0, "primary": 1, "secondary": 2, "tertiary": 3}

func _survey() -> void:
	var tree := get_tree()
	for b in BUNKS:
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
