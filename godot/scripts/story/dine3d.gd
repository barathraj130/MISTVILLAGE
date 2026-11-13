extends Node3D
## A meal at home, at the table (docs/MORNING_ROUTINE_AUDIT.md; story/food.json): no menu and no prices. Amma has
## cooked the day's food (food.gd home_meal: by the game's day and the hour, so a loaded save serves the same); it's
## on a steel plate (or a leaf, for a full lunch) at the small table in the hall's dining corner, Karthik on the
## chair before it. Amma says it's ready. You click the food: he eats it a bite at a time with his own hand (his
## SitEat clip: the hand down to the plate, a morsel in his fingers, up to his mouth, then chewing), and what he
## took goes down on the plate. When he has eaten most of it he can stop (Enter, or "I'm done"); all of it, he's
## done. tasks.gd hands home meals to it (begin) and goes on with its `finished(result)`.
## --storyskip plays it by itself (and saves pictures into --storyshots).

signal finished(result: Dictionary)

const Food := preload("res://scripts/story/food.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Face := preload("res://scripts/story/face.gd")
const Style := preload("res://scripts/ui/hud_style.gd")
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
var _bite_t := -1.0                                    # into the bite now (s), -1: between bites
var _bite_part := {}
var _morsel: MeshInstance3D
var _face: Face
var _spec := {}
var _ui: Control
var _layer: CanvasLayer
var _hover := -1
var _done := false
var _anim_mode := 0
var _t := 0.0
var _line := ""


func can(spec: Dictionary) -> bool:
	return spec.get("home", false) and story != null and story.room != null and str(story.cur.get("room", "")) == "home" \
		and city != null and city.walker != null and city.walker.model != null and not spec.get("food_fixed", false)


func begin(spec: Dictionary) -> void:
	_spec = spec
	room = story.room
	walker = city.walker
	model = walker.model
	anim = walker.anim
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_face = Face.new(model)
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
	_anim_mode = anim.callback_mode_process
	walker.global_position = _w(SEAT)
	model.global_rotation = Vector3(0.0, room.global_rotation.y + PI, 0.0)
	anim.play("Sit", 0.3)
	_serve()
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
	var s := SphereMesh.new()
	s.radius = 0.011
	s.height = 0.018
	_morsel = MeshInstance3D.new()
	_morsel.mesh = s
	_morsel.material_override = StandardMaterial3D.new()
	_morsel.visible = false
	add_child(_morsel)
	_props.append(_morsel)


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
	return _eaten >= int(ceil(_total * 0.6)) and _bite_t < 0.0


## A bite of that: his hand goes down to the plate (SitEat from its start), takes it, brings it up, he chews.
func _bite(i: int) -> void:
	if _bite_t >= 0.0:
		return
	_bite_part = parts[i]
	_bite_t = 0.0
	anim.play("SitEat", 0.25)
	anim.seek(0.0, true)
	anim.speed_scale = anim.current_animation_length / BITE_SECS


func _process(dt: float) -> void:
	if cam == null:
		return
	_t += dt
	if _cam_t < 1.0:                                    # into the table shot, eased
		_cam_t = minf(_cam_t + dt / 1.0, 1.0)
		var to := Transform3D.IDENTITY.looking_at(_w(CAM[1]) - _w(CAM[0]), Vector3.UP)
		to.origin = _w(CAM[0])
		var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		cam.global_transform = (_from_cam.global_transform if is_instance_valid(_from_cam) else to).interpolate_with(to, e)
	if _bite_t >= 0.0:
		_bite_t += dt
		var k := _bite_t / BITE_SECS                      # (his SitEat: at the plate till 0.35, at his mouth by 0.85)
		var fist := _fist()
		if k > 0.33 and not _morsel.visible and _morsel.get_meta("taken", false) == false:
			var col := Kit.bite(_bite_part)              # he takes it: there's less on the plate
			(_morsel.material_override as StandardMaterial3D).albedo_color = col
			_morsel.visible = true
			_morsel.set_meta("taken", true)
			_eaten += 1
			_ui.queue_redraw()
		if _morsel.visible:
			_morsel.global_position = fist
		if k > 0.82 and _morsel.visible:                  # in his mouth
			_morsel.visible = false
		if k >= 1.0:
			_bite_t = -1.0
			_morsel.set_meta("taken", false)
			anim.speed_scale = 1.0
			anim.play("Sit", 0.35)
			_chew = 1.4
			_ui.queue_redraw()
			if _eaten >= _total:
				_finish()
	if _face and _face.has_face():                       # chewing: the jaw going, the lips closed
		_chew = maxf(_chew - dt, 0.0)
		var c := sin(_t * 11.0) * 0.5 + 0.5
		var k2 := _bite_t / BITE_SECS if _bite_t >= 0.0 else 0.0
		var open := 0.18 * clampf((k2 - 0.7) / 0.12, 0.0, 1.0) * (1.0 - clampf((k2 - 0.88) / 0.1, 0.0, 1.0))
		_face.pose({"mouth-open": open + (0.06 * c if _chew > 0.0 else 0.0), "mouth-compression": 0.12 if _chew > 0.0 else 0.0})
		_face.update(dt)
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
func _auto(dt: float) -> void:
	_auto_t += dt
	if _done or _cam_t < 1.0 or _bite_t >= 0.0 or _auto_t < 0.4:
		return
	_auto_t = 0.0
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
