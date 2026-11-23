extends Node3D
## A meal at home, at the table (docs/MORNING_ROUTINE_AUDIT.md; story/food.json): no menu and no prices. Amma has
## cooked the day's food (food.gd home_meal: by the game's day and the hour, so a loaded save serves the same); it's
## on a steel plate (or a leaf, for a full lunch) at the small table in the hall's dining corner, Karthik on the
## chair before it. Amma says it's ready. You click the food: he eats it a bite at a time with his right hand, as
## people eat at home here (eater.gd, the same at every table: the hand to an idli, a piece pinched off between the
## thumb and the first two fingers, dipped in the sambar or the chutney, brought up to his mouth and put in; he chews
## and swallows, looking at his plate, now and then up at Amma; the left hand rests by the plate). This file is the
## place: the table, the camera, Amma's words, the card, the clicks.
## What he took goes down on the plate. When he has eaten most of it he can stop (Enter, or "I'm done"); all of it, he's
## done. tasks.gd hands home meals to it (begin) and goes on with its `finished(result)`.
## --storyskip plays it by itself (and saves pictures into --storyshots).

signal finished(result: Dictionary)

const Food := preload("res://scripts/story/food.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Face := preload("res://scripts/story/face.gd")
const Style := preload("res://scripts/ui/hud_style.gd")
const Eater := preload("res://scripts/story/eater.gd")
# the dining corner in the home room's frame (tools/story_rooms.py home(): Blender (x, y) → (x, -y)); Amma's dinner
# chair is across the table (Mark_amma_dinner)
const SEAT := Vector3(-1.45, 0.0, -1.15)               # his chair, facing the table (-Z)
const TABLE := Vector3(-1.45, 0.0, -1.62)
const TABLE_TOP := 0.775
const CAM := [Vector3(-0.66, 1.64, -1.95), Vector3(-1.45, 1.02, -1.3)]   # (across the table from his right: his face, his hand,
                                                                       # the plate; clear of Amma in her chair opposite)
const BITE_SECS := 1.9                                 # one bite, hand down and up (his SitEat cycle, a little quicker)
const CREAM := Color(0.96, 0.93, 0.86, 0.96)
const CHARCOAL := Color(0.16, 0.16, 0.17)
const FOREST := Color(0.09, 0.29, 0.21)
const GOLD := Color(0.78, 0.6, 0.27)

var city: Node
var story: Node
var lang := "en"
var skip := false
var shots := ""
var room: Node3D
var walker: Node3D
var model: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var cam: Camera3D
var _from_cam: Camera3D
var _cam_t := 0.0
var _props: Array = []
var dish_id := ""
var plate: Node3D
var parts: Array = []
var _eaten := 0
var _total := 0
var _eater                                             # eater.gd: the eating itself (the same at every table)
var _spec := {}
var _ui: Control
var _layer: CanvasLayer
var _hover := -1
var _done := false
var _anim_mode := 0
var _t := 0.0
var _line := ""
var _rng := RandomNumberGenerator.new()
var _views_dir := ""                                   # (testing: --dineviews=DIR, pictures from four cameras)
var _hold := false
var _film_dir := ""                                    # (testing: --dinefilm=DIR, a frame every 0.2 s of the whole meal;
var _film_step := 0.2
var _film_f := Vector3.ZERO                            # (the hand camera's point, followed smoothly)
var _film_cam := ""                                    #  --dinecam=front|side|game: the camera held for it)
var _film_t := 0.0
var _film_n := 0
var _film_v: Camera3D


func can(spec: Dictionary) -> bool:
	return spec.get("home", false) and story != null and story.room != null and str(story.cur.get("room", "")) == "home" \
		and city != null and city.walker != null and city.walker.model != null and not spec.get("food_fixed", false)


func begin(spec: Dictionary) -> void:
	_spec = spec
	_done = false                                       # (one node for every meal: the last one's state cleared;
	_eaten = 0                                          #  with _done left set a second meal never ended)
	_total = 0
	_cam_t = 0.0
	_t = 0.0
	_auto_t = 0.0
	_hover = -1
	_chew = 0.0
	_props.clear()
	room = story.room
	walker = city.walker
	model = walker.model
	anim = walker.anim
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var day: int = city.fines.sim.day if city.fines else 1
	for a in OS.get_cmdline_user_args():                 # (testing: another day's cooking)
		if a.begins_with("--dineday="):
			day = int(a.get_slice("=", 1))
	var slot := _slot()
	var meal := Food.home_meal(day, slot)
	dish_id = str(meal["dish"])
	_line = str(meal["amma"].get(lang, meal["amma"]["en"]))
	print("DINE3D day %d %s: %s" % [day, slot, dish_id])
	_furniture()
	walker.deactivate()
	walker.set("scripted", true)
	var g = walker.get("gait")                           # (the walk's animation tree off: while it's on it plays over
	if g and g.get("tree") and g.tree.active:            #  his Sit, and he stood at the table instead of sitting;
		g.tree.active = false                             #  player.gd doesn't run the walk once he's scripted)
		g.held = true
	_anim_mode = anim.callback_mode_process
	walker.global_position = _w(SEAT)
	model.global_rotation = Vector3(0.0, room.global_rotation.y + PI, 0.0)
	anim.play("Sit", 0.3)
	_serve()
	_rng.randomize()
	_eater = Eater.new()                                # the eating, over the Sit pose (eater.gd, eat_ik.gd)
	add_child(_eater)
	_eater.setup(model, -room.global_basis.z, [plate])
	_eater.glance_at = walker.global_position - room.global_basis.z * 1.6 + Vector3.UP * 1.05   # (Amma, across)
	_eater.bite_taken.connect(func(_p):
		_eaten += 1
		if _ui:
			_ui.queue_redraw())
	_eater.all_eaten.connect(_finish)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dineviews="):
			_views_dir = a.get_slice("=", 1)
		if a.begins_with("--dinefilm="):
			_film_dir = a.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_film_dir)
		if a.begins_with("--dinecam="):
			_film_cam = a.get_slice("=", 1)
		if a.begins_with("--dinefilmstep="):              # (a frame every this many seconds: 0.05 played at 5 fps is
			_film_step = float(a.get_slice("=", 1))       #  slow motion, four times)
	_from_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.05
	add_child(cam)
	if _from_cam:
		cam.global_transform = _from_cam.global_transform
	cam.make_current()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_amma(meal)


## Amma: it's ready, what she made today; then the step's own advice, if it has some.
func _amma(meal: Dictionary) -> void:
	await get_tree().create_timer(0.2).timeout          # (after the task's tip, which tasks.gd's caller says first)
	if story.has_method("_say"):
		story._say({"who": "amma", "en": str(meal["amma"]["en"]), "ta": str(meal["amma"].get("ta", meal["amma"]["en"]))}, false)
		story._box_at_top(true)                         # (her words above, the table clear)
	if _spec.has("tip"):
		await get_tree().create_timer(5.0).timeout
		if not _done and story.has_method("_say"):
			story._say({"who": "amma", "en": str(_spec["tip"].get("en", "")), "ta": str(_spec["tip"].get("ta", ""))}, false)
			story._box_at_top(true)
	_shot("dine_start")


func _slot() -> String:                                # (the step says which meal; else the hour)
	for a in OS.get_cmdline_user_args():                 # (testing: another meal)
		if a.begins_with("--dineslot="):
			return a.get_slice("=", 1)
	return str(_spec.get("slot", Food.slot_at(city.fines.sim.minute if city.fines else 480.0)))


func _w(local: Vector3) -> Vector3:
	return room.global_transform * local


func _box(size: Vector3, col: Color, at: Vector3, rough := 0.6) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = Kit.mat("dine_%s" % col.to_html(), col, rough)
	add_child(mi)
	mi.global_transform = Transform3D(room.global_basis, _w(at))
	_props.append(mi)
	return mi


## The small table in the dining corner (teak, a steel-edged top) and his plastic chair.
func _furniture() -> void:
	var teak := Color(0.42, 0.26, 0.14)
	_box(Vector3(0.82, 0.03, 0.6), teak, TABLE + Vector3(0, TABLE_TOP - 0.015, 0), 0.45)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.045, TABLE_TOP - 0.03, 0.045), teak, TABLE + Vector3(sx * 0.36, (TABLE_TOP - 0.03) * 0.5, sz * 0.26), 0.5)
	var red := Color(0.68, 0.11, 0.09)
	_box(Vector3(0.44, 0.035, 0.42), red, SEAT + Vector3(0, 0.44, 0.02), 0.4)
	_box(Vector3(0.44, 0.42, 0.03), red, SEAT + Vector3(0, 0.66, 0.22), 0.4)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.03, 0.44, 0.03), red, SEAT + Vector3(sx * 0.19, 0.22, 0.02 + sz * 0.18), 0.4)


## The plate where his hand goes (his SitEat: 0.42 m ahead, 0.1 m to his right), a tumbler of water by it.
func _serve() -> void:
	plate = Kit.build(dish_id)
	add_child(plate)
	var fwd := -room.global_basis.z
	var right := room.global_basis.x
	plate.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), walker.global_position + fwd * 0.42 + right * 0.1
		+ Vector3(0, TABLE_TOP + 0.002 - walker.global_position.y + room.global_position.y - room.global_position.y, 0))
	plate.global_position.y = _w(Vector3(0, TABLE_TOP + 0.002, 0)).y
	_props.append(plate)
	parts = plate.get_meta("parts")
	_total = 0
	for p in parts:
		_total += int(p["bites"])
	var cup := CylinderMesh.new()
	cup.top_radius = 0.032
	cup.bottom_radius = 0.026
	cup.height = 0.09
	var t := MeshInstance3D.new()
	t.mesh = cup
	t.material_override = Kit.mat("steel_tumbler", Color(0.86, 0.87, 0.88), 0.3, 0.55, false)
	add_child(t)
	t.global_position = plate.global_position + right * 0.24 + fwd * -0.05 + Vector3(0, 0.045, 0)
	_props.append(t)


# ---- eating ----

func _part_at(p: Vector2) -> int:
	var best := -1
	var bd := 60.0 * (Style.s(_ui) if _ui else 1.0)
	for i in parts.size():
		if int(parts[i]["left"]) <= 0:
			continue
		var n: Node3D = parts[i]["node"]
		var d := cam.unproject_position(n.global_position).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _input(e: InputEvent) -> void:
	if _done or cam == null or (skip and not "--dineinput" in OS.get_cmdline_user_args()):
		return
	if e is InputEventMouseMotion:
		var h := _part_at(e.position)
		if h != _hover:
			_hover = h
			_ui.queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if _done_btn().has_point(e.position) and _can_stop():
			_finish()
		else:
			var i := _part_at(e.position)
			if i >= 0:
				_bite(i)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ENTER, KEY_KP_ENTER] and _can_stop():
		_finish()
		get_viewport().set_input_as_handled()


func _can_stop() -> bool:
	return _eaten >= int(ceil(_total * 0.6)) and not (_eater and _eater.busy())


## A bite of what was clicked (eater.gd builds it from the part's profile: the bread torn and dipped, the idli
## pinched, the rice mixed; a curry clicked: something dipped in it).
func _bite(i: int) -> void:
	if _eater:
		_eater.bite(i)


func _mouth() -> Vector3:
	return _eater.mouth() if _eater else walker.global_position + Vector3.UP * 1.2


func _process(dt: float) -> void:
	if cam == null:
		return
	if _film_dir != "" and not _done and _cam_t >= 1.0 and _eater:
		_film(dt)
	_t += dt
	if _cam_t < 1.0:                                    # into the table shot, eased
		_cam_t = minf(_cam_t + dt / 1.0, 1.0)
		var to := Transform3D.IDENTITY.looking_at(_w(CAM[1]) - _w(CAM[0]), Vector3.UP)
		to.origin = _w(CAM[0])
		var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		cam.global_transform = (_from_cam.global_transform if is_instance_valid(_from_cam) else to).interpolate_with(to, e)
	if _eater and not _done:
		_eater.hold_clock = _hold
		var k: float = _eater.plan_k()
		if k >= 0.0:
			_dine_views(k)
	if skip:
		_auto(dt)


var _chew := 0.0


func _fist() -> Vector3:
	var a := skel.find_bone("index_02_r")
	var b := skel.find_bone("thumb_03_r")
	var g := skel.global_transform
	if a < 0 or b < 0:
		return g * skel.get_bone_global_pose(skel.find_bone("hand_r")).origin
	return (g * skel.get_bone_global_pose(a).origin + g * skel.get_bone_global_pose(b).origin) * 0.5


func _finish() -> void:
	if _done:
		return
	_done = true
	if _eater and is_instance_valid(_eater):
		_eater.release()                                 # (the food and the spoon back down, the arms his own)
		_eater.queue_free()
		_eater = null
	var g = walker.get("gait") if is_instance_valid(walker) else null
	if g:
		g.held = false                                    # (the walk takes his clips back when he moves)
	_shot("dine_done")
	var e := float(Food.dish(dish_id).get("energy", 50)) * clampf(float(_eaten) / maxf(_total, 1.0) + 0.2, 0.4, 1.0)
	var res := {"ate": true, "meal": dish_id, "minutes": int(_spec.get("minutes", 15)), "energy": e, "paid": 0}
	var tw := create_tween()                            # the camera back
	var from := cam.global_transform
	tw.tween_method(func(k: float):
		if is_instance_valid(_from_cam):
			cam.global_transform = from.interpolate_with(_from_cam.global_transform, k), 0.0, 1.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(_from_cam):
		_from_cam.make_current()
	for n in _props + [cam, _layer]:
		if is_instance_valid(n):
			n.queue_free()
	_props.clear()
	cam = null
	anim.speed_scale = 1.0
	walker.global_position = _w(SEAT + Vector3(0.5, 0.0, 0.1))   # (up and beside the chair)
	walker.set("scripted", false)
	walker.activate()
	print("DINE3D done: %s, %d of %d bites, energy +%.0f" % [dish_id, _eaten, _total, e])
	finished.emit(res)


# ---- testing ----

var _auto_t := 0.0
var _pause := 0.6


func _auto(dt: float) -> void:
	_auto_t += dt
	if _done or _cam_t < 1.0 or _eater == null or _eater.busy() or _auto_t < _pause:
		return
	_auto_t = 0.0
	_pause = _rng.randf_range(0.5, 1.8)                  # (a varied pause after each swallow)
	if "--dineinput" in OS.get_cmdline_user_args():      # the real mouse: a click on the next thing with some left
		for i in parts.size():
			if int(parts[i]["left"]) > 0:
				var p := cam.unproject_position((parts[i]["node"] as Node3D).global_position)
				for down in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = down
					ev.position = p
					ev.global_position = p
					Input.parse_input_event(ev)
				break
	else:
		for i in parts.size():
			if int(parts[i]["left"]) > 0:
				_bite(i)
				break
	if _eaten == 2:
		_shot("dine_eating")
	if _eaten >= int(ceil(_total * 0.6)) + 1:
		_finish()


## (testing) --dineviews=DIR: the second bite stopped at its moments (the reach, the pinch, the dip, at his mouth,
## chewing), each seen from the meal's own camera, from the front, from his right and close up.
var _views_taken := {}


func _dine_views(k: float) -> void:
	if _views_dir == "" or _eater.bites_done != 1 or _hold:
		return
	var pl: Dictionary = _eater.plan
	for m in [["reach", 0.12], ["pinch", float(pl["pick_k"]) + 0.01], ["dip", float(pl["dip_k"])], ["mouth", float(pl["in_k"])]]:
		if k >= float(m[1]) and not _views_taken.has(m[0]) and float(m[1]) <= 1.0:
			_views_taken[m[0]] = true
			_four_views(str(m[0]))
			return


func _four_views(moment: String) -> void:
	_hold = true
	var fwd := -room.global_basis.z
	var right := room.global_basis.x
	var head := _mouth()
	var v := Camera3D.new()
	v.fov = 45.0
	v.near = 0.03
	add_child(v)
	var poses := {"game": [], "front": [head + fwd * 1.35 + Vector3.UP * 0.05, head + Vector3.DOWN * 0.3],
		"side": [head + right * 1.2 + fwd * 0.25 + Vector3.DOWN * 0.15, head + fwd * 0.25 + Vector3.DOWN * 0.3],
		"close": [_eater.ik.r_at + right * 0.35 + fwd * 0.3 + Vector3.UP * 0.12, _eater.ik.r_at]}   # (close on the hand and the food)
	DirAccess.make_dir_recursive_absolute(_views_dir)
	for nm in poses:
		var pp: Array = poses[nm]
		if pp.is_empty():
			cam.make_current()
		else:
			v.global_position = pp[0]
			v.look_at(pp[1], Vector3.UP)
			v.make_current()
		for f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("%s/dine_%s_%s.jpg" % [_views_dir, moment, nm], 0.88)
	cam.make_current()
	v.queue_free()
	print("DINEVIEW %s" % moment)
	_hold = false


func _film(dt: float) -> void:
	if _film_cam in ["front", "side", "close", "hand", "handside"]:
		if _film_v == null:
			_film_v = Camera3D.new()
			_film_v.fov = 45.0
			_film_v.near = 0.03
			add_child(_film_v)
		var fwd := -room.global_basis.z
		var right := room.global_basis.x
		var head := _mouth()
		if _film_cam == "front":
			_film_v.global_position = head + fwd * 1.5 + Vector3.UP * 0.1
			_film_v.look_at(head + Vector3.DOWN * 0.3, Vector3.UP)
		elif _film_cam in ["hand", "handside"] and _eater:     # (on the right hand itself, close: the wrist and fingers)
			var hp: Vector3 = _eater.ik.pinch_world if _eater.ik.pinch_world != Vector3.ZERO else _eater.ik.r_at
			_film_f = _film_f.lerp(hp, 0.25) if _film_f != Vector3.ZERO else hp
			var off := (fwd * 0.42 + right * 0.18 + Vector3.UP * 0.08) if _film_cam == "hand" else (right * 0.45 + fwd * 0.08 + Vector3.UP * 0.06)
			_film_v.global_position = _film_f + off
			_film_v.look_at(_film_f, Vector3.UP)
		elif _film_cam == "close":                          # (close: his face and his right hand, as it works)
			var mid := head.lerp(_eater.ik.r_at if _eater else plate.global_position, 0.5)
			_film_v.global_position = mid + right * 0.55 + fwd * 0.45 + Vector3.UP * 0.05
			_film_v.look_at(mid, Vector3.UP)
		else:
			_film_v.global_position = head + right * 1.4 + fwd * 0.3 + Vector3.DOWN * 0.15
			_film_v.look_at(head + fwd * 0.3 + Vector3.DOWN * 0.3, Vector3.UP)
		if not _hold:
			_film_v.make_current()
	_film_t += dt
	if _film_t < _film_step or _hold:
		return
	_film_t = 0.0
	get_viewport().get_texture().get_image().save_jpg("%s/f_%04d.jpg" % [_film_dir, _film_n], 0.8)
	if _eater and _eater.ik and _eater.ik.wrist_log.has("r"):   # (the arm's solve on this frame: forearm roll, wrist
		var ik_ = _eater.ik                                       #  twist, flexion, deviation, degrees; a clamped turn noted)
		var wl: Vector4 = ik_.wrist_log["r"]
		print("WRIST f_%04d k=%.2f %-16s fore %+5.0f  wrist-twist %+4.0f  flex %+4.0f  dev %+4.0f%s" % [_film_n, _eater.plan_k(), _eater.state,
			wl.x, wl.y, wl.z, wl.w, ("  CLAMPED from %.0f" % float(ik_.wrist_log["r_clamped"])) if ik_.wrist_log.has("r_clamped") else ""])
	_film_n += 1


func _shot(name: String) -> void:
	if shots == "":
		return
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(shots + "/" + name + "_" + dish_id + ".jpg", 0.85)


# ---- the card: what's on the plate, how much is left ----

func _done_btn() -> Rect2:
	var k := Style.s(_ui)
	var vs := _ui.get_viewport_rect().size
	var w := clampf(vs.x * 0.3, 360.0 * k, 520.0 * k)
	return Rect2(Vector2(vs.x - w - 32.0 * k + 24.0 * k, vs.y * 0.58 + 93.0 * k - 24.0 * k - 44.0 * k), Vector2(170.0 * k, 44.0 * k))


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	_layer.add_child(_ui)


func _draw_ui() -> void:
	if _done:
		return
	var k := Style.s(_ui)
	var vs := _ui.get_viewport_rect().size
	var w := clampf(vs.x * 0.3, 360.0 * k, 520.0 * k)
	var pad := 24.0 * k
	var h := 186.0 * k
	var r := Rect2(Vector2(vs.x - w - 32.0 * k, vs.y * 0.58 - h * 0.5), Vector2(w, h))   # (right side: clear of the talk)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(int(14 * k))
	sb.shadow_color = Color(0, 0, 0, 0.16)
	sb.shadow_size = int(12 * k)
	_ui.draw_style_box(sb, r)
	var title := (Food.name_of(dish_id, lang))
	var slot := _slot()
	var when: Array = {"breakfast": ["Breakfast", "காலை டிஃபன்"], "lunch": ["Lunch", "மதிய சாப்பாடு"], "dinner": ["Dinner", "இரவு சாப்பாடு"]}[slot]
	_ui.draw_string(Style.font(600), r.position + Vector2(pad, pad + 12 * k), (when[1] if lang == "ta" else when[0]).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * k), GOLD)
	_ui.draw_string(Style.font(600), r.position + Vector2(pad, pad + 40 * k), title, HORIZONTAL_ALIGNMENT_LEFT, w - 2 * pad, int(22 * k), CHARCOAL)
	var hint := ("சாப்பிட உணவைக் கிளிக் செய்" if lang == "ta" else "Click the food to eat")
	if _hover >= 0:
		hint = ("எடு: " if lang == "ta" else "Take some ") + str(parts[_hover]["label"])
	_ui.draw_string(Style.font(500), r.position + Vector2(pad, pad + 66 * k), hint, HORIZONTAL_ALIGNMENT_LEFT, w - 2 * pad, int(16 * k),
		Color(CHARCOAL, 0.72))
	var bar := Rect2(r.position + Vector2(pad, pad + 80 * k), Vector2(w - 2 * pad, 6 * k))
	var tr := StyleBoxFlat.new()
	tr.bg_color = Color(CHARCOAL, 0.1)
	tr.set_corner_radius_all(int(3 * k))
	_ui.draw_style_box(tr, bar)
	var fl := tr.duplicate() as StyleBoxFlat
	fl.bg_color = FOREST
	_ui.draw_style_box(fl, Rect2(bar.position, Vector2(bar.size.x * float(_eaten) / maxf(_total, 1.0), bar.size.y)))
	if _can_stop():
		var b := _done_btn()
		var bs := StyleBoxFlat.new()
		bs.bg_color = FOREST
		bs.set_corner_radius_all(int(10 * k))
		_ui.draw_style_box(bs, b)
		_ui.draw_string(Style.font(600), b.position + Vector2(0, b.size.y * 0.5 + 6 * k), ("முடிந்தது" if lang == "ta" else "I'm done"),
			HORIZONTAL_ALIGNMENT_CENTER, b.size.x, int(16 * k), Color(1, 1, 1))
