extends Node3D
## A meal at home, at the table (docs/MORNING_ROUTINE_AUDIT.md; story/food.json): no menu and no prices. Amma has
## cooked the day's food (food.gd home_meal: by the game's day and the hour, so a loaded save serves the same); it's
## on a steel plate (or a leaf, for a full lunch) at the small table in the hall's dining corner, Karthik on the
## chair before it. Amma says it's ready. You click the food: he eats it a bite at a time with his right hand, as
## people eat at home here (eat_ik.gd over his Sit pose): the hand to an idli, a piece pinched off between the thumb
## and the first two fingers, dipped in the sambar or the chutney, brought up to his mouth and put in; he chews and
## swallows, looking at his plate, now and then up; the left hand rests by the plate. Every bite a little different.
## What he took goes down on the plate. When he has eaten most of it he can stop (Enter, or "I'm done"); all of it, he's
## done. tasks.gd hands home meals to it (begin) and goes on with its `finished(result)`.
## --storyskip plays it by itself (and saves pictures into --storyshots).

signal finished(result: Dictionary)

const Food := preload("res://scripts/story/food.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Face := preload("res://scripts/story/face.gd")
const Style := preload("res://scripts/ui/hud_style.gd")
const EatIK := preload("res://scripts/story/eat_ik.gd")
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
var _ik                                                # eat_ik.gd under his skeleton while he eats
var _plan := {}                                        # this bite: {keys: [[k, pos, fingers, pinch]], dur, main, dip, ...}
var _bites_done := 0
var _chew_t := 0.0                                     # chewing after a bite (s left), then the swallow
var _swallow := 0.0
var _l_shift := 0.0                                    # the left hand to the plate's rim and back (s left)
var _l_next := 7.0
var _glance := 0.0                                     # a look up across the table (s left)
var _rng := RandomNumberGenerator.new()
var _views_dir := ""                                   # (testing: --dineviews=DIR, pictures from four cameras)
var _hold := false
var _film_dir := ""                                    # (testing: --dinefilm=DIR, a frame every 0.2 s of the whole meal;
var _film_cam := ""                                    #  --dinecam=front|side|game: the camera held for it)
var _film_t := 0.0
var _film_n := 0
var _film_v: Camera3D


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
	var g = walker.get("gait")                           # (the walk's animation tree off: while it's on it plays over
	if g and g.get("tree") and g.tree.active:            #  his Sit, and he stood at the table instead of sitting;
		g.tree.active = false                             #  player.gd doesn't run the walk once he's scripted)
		g.held = true
	_anim_mode = anim.callback_mode_process
	walker.global_position = _w(SEAT)
	model.global_rotation = Vector3(0.0, room.global_rotation.y + PI, 0.0)
	anim.play("Sit", 0.3)
	_serve()
	_ik = EatIK.new()                                   # the eating, over the Sit pose
	_ik.active = true
	_ik.face_fwd = -room.global_basis.z
	skel.add_child(_ik)
	_ik.wrist_floor = plate.global_position.y + 0.06    # (the wrist above the plate: the fingers do the picking)
	_rng.randomize()
	_bites_done = 0
	_chew_t = 0.0
	_swallow = 0.0
	_l_next = _rng.randf_range(6.0, 10.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dineviews="):
			_views_dir = a.get_slice("=", 1)
		if a.begins_with("--dinefilm="):
			_film_dir = a.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_film_dir)
		if a.begins_with("--dinecam="):
			_film_cam = a.get_slice("=", 1)
	_rest_pose(0.0)
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


## How a part is eaten (the universal eating system's styles, docs/EATING_SYSTEM_2026-11-18.md): a bread torn with
## both hands, rice mixed and scooped, a piece pinched; and the sides it goes into (curries in katoris, a masala or a
## kurma on the plate).
const BREADS := ["poori", "dosa", "chapati", "parotta", "appam", "puttu", "idiyappam"]
const RICES := ["rice", "meals", "pongal", "upma", "curd", "lemon", "tomato", "biryani"]
const SIDES := ["sambar", "chutney", "masala", "kurma", "salna", "curry", "stew", "kadala", "rasam", "poriyal", "kuzhambu", "pickle"]


static func _kind_of(part: Dictionary) -> String:
	var lab := str(part.get("label", "")).to_lower()
	for w in SIDES:
		if lab.contains(w):
			return "side"
	if part.get("how", "") == "level":
		return "side"
	for w in BREADS:
		if lab.contains(w):
			return "bread"
	for w in RICES:
		if lab.contains(w):
			return "rice"
	return "piece"


## A bite: an idli piece (the one clicked, or the nearest with some left when a curry is clicked) dipped in a curry
## (the one clicked, or one with some left); with no idli left, a scoop of the curry itself.
func _bite(i: int) -> void:
	if _bite_t >= 0.0 or _chew_t > 1.0:
		return
	var clicked: Dictionary = parts[i]
	var main := {}
	var dip := {}
	if _kind_of(clicked) != "side":
		main = clicked
	else:
		dip = clicked
	if main.is_empty():
		for p in parts:
			if _kind_of(p) != "side" and int(p["left"]) > 0:
				main = p
				break
	if dip.is_empty() and _rng.randf() < 0.85:          # (now and then a piece eaten as it is)
		var curries: Array = parts.filter(func(p): return _kind_of(p) == "side" and int(p["left"]) > 0)
		if curries.is_empty():
			curries = parts.filter(func(p): return _kind_of(p) == "side")
		if not curries.is_empty():
			dip = curries[(_bites_done + _rng.randi_range(0, 1)) % curries.size()]
	_bite_part = main if not main.is_empty() else dip
	_plan = _make_plan(main, dip)
	_bite_t = 0.0


## The bite's path for the right hand: keys of [k (0..1 of the bite), fingertip position, the fingers' way, pinch].
func _make_plan(main: Dictionary, dip: Dictionary) -> Dictionary:
	var fwd := -room.global_basis.z
	var right := room.global_basis.x
	var upv := Vector3.UP
	var jit := func(r: float) -> Vector3: return Vector3(_rng.randf_range(-r, r), _rng.randf_range(-r * 0.5, r * 0.5), _rng.randf_range(-r, r))
	var rest := _r_rest()
	var mouth := _mouth()
	var down_fwd := (Vector3.DOWN * 0.45 + fwd * 0.85).normalized()   # (fingers near level: the wrist behind and above)
	var to_mouth := (-fwd * 0.9 + upv * 0.08 - right * 0.3).normalized()   # (the fingertips level, in toward his lips)
	var keys: Array = [[0.0, rest, _r_rest_fingers(), 0.2]]
	var k := 0.14
	var style := _kind_of(main) if not main.is_empty() else "side"
	var hold := {}                                                         # (the left hand's part in it)
	if not main.is_empty():
		var fs := _food_shape(main)
		var cc: Vector3 = fs["c"]
		# the fingertips at its near edge, at its top (not into it): a pinch of its rim
		var edge: Vector3 = Vector3(cc.x, float(fs["top"]) - 0.004, cc.z) - fwd * float(fs["r"]) * 0.75 + right * 0.01
		var pp: Vector3 = edge + jit.call(0.004)
		if style == "bread":                                               # (the left hand holds its far side down)
			hold = {"at": Vector3(cc.x, float(fs["top"]) + 0.004, cc.z) - right * float(fs["r"]) * 0.7 + fwd * 0.01,
				"from": k - 0.04, "to": k + 0.26}
		keys.append([k, pp + upv * 0.035 - fwd * 0.02, down_fwd, 0.0])    # (over it, a little lift: not a dive)
		keys.append([k + 0.09, pp, down_fwd, 0.0])
		keys.append([k + 0.15, pp, down_fwd, 1.0])                         # (the fingers close: pinched)
		if style == "bread":
			keys.append([k + 0.22, pp - fwd * 0.028 + upv * 0.014, down_fwd, 1.0])   # (torn: a short pull toward him)
			k += 0.07
		elif style == "rice" and not dip.is_empty():                       # (the curry first, then mixed in)
			pass
		k += 0.16
	if style == "rice" and not main.is_empty():                            # (mixed: small rounds on the rice, gathered)
		var rp: Vector3 = (main["node"] as Node3D).global_position + upv * 0.012
		var flat := (Vector3.DOWN * 0.7 + fwd * 0.6).normalized()
		if not dip.is_empty():
			var cp: Vector3 = (dip["node"] as Node3D).global_position
			keys.append([k + 0.07, cp + upv * 0.03, flat, 0.2])
			keys.append([k + 0.11, cp - upv * 0.004, flat, 0.2])
			k += 0.12
		for r in 3:
			var a := float(r) * TAU / 3.0 + _rng.randf_range(0.0, 1.0)
			keys.append([k + 0.05 * (r + 1), rp + (right * cos(a) + fwd * sin(a)) * 0.018, flat, 0.3])
		keys.append([k + 0.2, rp + upv * 0.006, flat, 0.85])                # (gathered on the fingers)
		k += 0.2
		dip = {}                                                            # (no separate dip after mixing)
	var touch_k := 2.0
	if not dip.is_empty():
		var ds := _food_shape(dip)
		var dc: Vector3 = ds["c"]
		var dp: Vector3 = Vector3(dc.x, float(ds["top"]) - 0.003, dc.z) - fwd * float(ds["r"]) * 0.3 + jit.call(0.004)   # (its surface)
		var into := (Vector3.DOWN * 0.6 + fwd * 0.8).normalized()
		keys.append([k + 0.09, dp + upv * 0.03, into, 1.0])
		keys.append([k + 0.15, dp, into, 1.0])                              # (touched in: lightly coated)
		touch_k = k + 0.15
		if _rng.randf() < 0.35:                                            # (and stirred round once)
			keys.append([k + 0.19, dp + right * 0.012 - upv * 0.003, into, 1.0])
		keys.append([k + 0.22, dp + upv * 0.035, into, 1.0])
		k += 0.22
	var km := maxf(k + 0.18, 0.66)
	keys.append([km, mouth + fwd * 0.09 - upv * 0.03 + jit.call(0.006), to_mouth, 1.0])   # (up from below, not over)
	keys.append([km + 0.08, mouth + fwd * 0.005, to_mouth, 1.0])          # (in: the fingertips at his lips, still closed)
	keys.append([km + 0.15, mouth + fwd * 0.11 - upv * 0.06, to_mouth.lerp(down_fwd, 0.5).normalized(), 0.35])
	keys.append([1.0, rest + jit.call(0.01), _r_rest_fingers(), 0.2])
	var dur := 3.3 * _rng.randf_range(0.85, 1.2) * (0.85 if dip.is_empty() else 1.0)
	return {"keys": keys, "dur": dur, "main": main, "dip": dip, "picked": false, "dipped": false, "gone": false, "hold": hold,
		"pick_k": keys[3][0] if not main.is_empty() else 0.0, "dip_k": touch_k,
		"in_k": km + 0.08, "mouth_k": km}


## A part's real shape on the plate (its mesh's bounds in the world): its middle, its top, its radius.
func _food_shape(part: Dictionary) -> Dictionary:
	var n: Node3D = part["node"]
	var c := n.global_position
	var top := c.y + 0.02
	var rad := 0.03
	if n is VisualInstance3D:
		var bb: AABB = (n as VisualInstance3D).get_aabb()
		var g := n.global_transform
		var lo := g * bb.position
		var hi := g * bb.end
		c = (lo + hi) * 0.5
		top = maxf(lo.y, hi.y)
		rad = maxf(absf(hi.x - lo.x), absf(hi.z - lo.z)) * 0.5
	return {"c": c, "top": top, "r": rad}


## The piece in his fingers, by what it was torn or taken from.
## A torn bit of bread (poori, dosa, chapati): a thin, irregular piece, about 3 x 2.5 cm, its rim ragged (seven
## to ten points at uneven distances, one side straighter where it was the bread's edge), a little thicker in the
## middle, slightly curled. Its centre is at the origin, flat in XZ: what the fingertips hold.
static func torn_piece(rng: RandomNumberGenerator) -> ArrayMesh:
	var n := rng.randi_range(7, 10)
	var rim: Array[Vector3] = []
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var r := rng.randf_range(0.009, 0.017)
		if absf(wrapf(a - a0, -PI, PI)) < 0.6:          # (the bread's own rim: straighter, a little further out)
			r = 0.015 / maxf(cos(wrapf(a - a0, -PI, PI)), 0.8)
		rim.append(Vector3(cos(a) * r * 1.15, 0.0, sin(a) * r * 0.95))
	var th := rng.randf_range(0.0025, 0.004)
	var curl := rng.randf_range(4.0, 10.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := func(v: Vector3, y: float) -> Vector3:
		return Vector3(v.x, y - curl * v.x * v.x, v.z)
	for i in n:                                          # (top and bottom fans from the centre, the sides between)
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, th * 0.75, 0))
		st.add_vertex(top.call(b, th * 0.5))
		st.add_vertex(top.call(a, th * 0.5))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(0, -th * 0.5, 0))
		st.add_vertex(top.call(a, -th * 0.4))
		st.add_vertex(top.call(b, -th * 0.4))
		var out := ((a + b) * 0.5).normalized()
		st.set_normal(out)
		st.add_vertex(top.call(a, th * 0.5))
		st.add_vertex(top.call(b, th * 0.5))
		st.add_vertex(top.call(b, -th * 0.4))
		st.add_vertex(top.call(a, th * 0.5))
		st.add_vertex(top.call(b, -th * 0.4))
		st.add_vertex(top.call(a, -th * 0.4))
	return st.commit()


func _piece_mesh(kind: String) -> Mesh:
	match kind:
		"bread":                                          # (a torn flat piece, ragged, never the same twice)
			return torn_piece(_rng)
		"rice":                                           # (a small gathered ball)
			var r := SphereMesh.new()
			r.radius = 0.012
			r.height = 0.02
			return r
		_:                                                # (a soft lump: idli, vada, a sweet)
			var l := SphereMesh.new()
			l.radius = 0.013
			l.height = 0.018
			return l


func _mouth() -> Vector3:
	var hb := skel.find_bone("head")
	var fwd := -room.global_basis.z
	if hb < 0:
		return walker.global_position + Vector3.UP * 1.2 + fwd * 0.1
	var h: Vector3 = skel.global_transform * skel.get_bone_global_pose(hb).origin
	return h + fwd * 0.1 - Vector3.UP * 0.09             # (the lips: below and ahead of the head bone's root; seen
	                                                     #  in the --dineviews close-ups, 12 cm under it)


func _r_rest() -> Vector3:
	var fwd := -room.global_basis.z
	var right := room.global_basis.x
	return plate.global_position + right * 0.185 - fwd * 0.03 + Vector3.UP * 0.035


func _r_rest_fingers() -> Vector3:
	return (-room.global_basis.z * 0.75 + Vector3.DOWN * 0.35 - room.global_basis.x * 0.25).normalized()


## The hands at rest (between bites): the right by the plate's edge, the left flat on its side of the plate, both
## breathing a little; the left now and then to the plate's rim, steadying it.
func _rest_pose(dt: float) -> void:
	var fwd := -room.global_basis.z
	var right := room.global_basis.x
	var drift := Vector3(sin(_t * 0.7) * 0.004, 0.0, cos(_t * 0.5) * 0.004)
	var l_rest := plate.global_position - right * 0.21 + fwd * 0.01 + Vector3.UP * 0.022 + drift
	_l_next -= dt
	if _l_next <= 0.0 and _l_shift <= 0.0:
		_l_shift = _rng.randf_range(1.2, 2.0)
		_l_next = _rng.randf_range(7.0, 13.0)
	if _l_shift > 0.0:
		_l_shift -= dt
		var k := sin(clampf(_l_shift / 1.6, 0.0, 1.0) * PI)
		l_rest = l_rest.lerp(plate.global_position - right * 0.14 + Vector3.UP * 0.02, k)
	if _bite_t >= 0.0 and not _plan.is_empty() and not (_plan.get("hold", {}) as Dictionary).is_empty():
		var hd: Dictionary = _plan["hold"]
		var kk := clampf(_bite_t / float(_plan["dur"]), 0.0, 1.0)
		var on := smoothstep(float(hd["from"]), float(hd["from"]) + 0.06, kk) * (1.0 - smoothstep(float(hd["to"]), float(hd["to"]) + 0.08, kk))
		l_rest = l_rest.lerp(hd["at"], on)                                 # (fingers on the bread, holding it down)
	_ik.l_at = l_rest
	_ik.l_fingers = (fwd * 0.9 + Vector3.DOWN * 0.12 + right * 0.2).normalized()
	_ik.l_knuckles = right
	_ik.l_thumb = right                                  # (palm down on the table)
	if _bite_t < 0.0:
		_ik.r_thumb = -right
		_ik.r_at = _r_rest() + drift * 0.6
		_ik.r_fingers = _r_rest_fingers()
		_ik.r_knuckles = right
		_ik.pinch = 0.2
		_ik.lean_in = lerpf(_ik.lean_in, 0.03 + 0.012 * sin(_t * TAU * 0.24), 1.0 - exp(-dt * 3.0))   # (breathing)
		var ahead: Vector3 = _mouth() + fwd * 1.2 + Vector3.DOWN * 0.45     # (chewing: his eyes on his plate, half up)
		if _glance > 0.0:
			_glance -= dt
			ahead = walker.global_position + fwd * 1.6 + Vector3.UP * 1.05   # (across the table: Amma)
		_ik.look_at_pt = _ik.look_at_pt.lerp(ahead if _chew_t > 0.0 or _glance > 0.0 else plate.global_position, 1.0 - exp(-dt * 2.5))


## Where the bite's plan has the hand at k: between keys eased (each key a moment's stop, as hands move).
func _plan_at(k: float) -> Array:
	var keys: Array = _plan["keys"]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= float(b[0]) or i == keys.size() - 2:
			var u := clampf((k - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u).normalized(), lerpf(a[3], b[3], u)]
	return [keys[-1][1], keys[-1][2], keys[-1][3]]


func _process(dt: float) -> void:
	if cam == null:
		return
	if _ik and not _done:
		_rest_pose(dt)
	if _film_dir != "" and not _done and _cam_t >= 1.0 and _ik:
		_film(dt)
	_t += dt
	if _cam_t < 1.0:                                    # into the table shot, eased
		_cam_t = minf(_cam_t + dt / 1.0, 1.0)
		var to := Transform3D.IDENTITY.looking_at(_w(CAM[1]) - _w(CAM[0]), Vector3.UP)
		to.origin = _w(CAM[0])
		var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		cam.global_transform = (_from_cam.global_transform if is_instance_valid(_from_cam) else to).interpolate_with(to, e)
	if _bite_t >= 0.0 and not _plan.is_empty() and _ik:   # (a meal ended mid-bite: nothing more to move)
		if not _hold:
			_bite_t += dt
		var k := clampf(_bite_t / float(_plan["dur"]), 0.0, 1.0)
		var at := _plan_at(k)
		var right := room.global_basis.x
		var floor_y := plate.global_position.y + 0.012                       # (the fingertips above the plate, always)
		if (at[0] as Vector3).y < floor_y:
			at[0] = Vector3(at[0].x, floor_y, at[0].z)
		_ik.r_at = at[0]
		_ik.r_fingers = at[1]
		_ik.r_knuckles = right
		if not (_plan.get("hold", {}) as Dictionary).is_empty():          # (the tear: a small twist of the wrist)
			var tk := float(_plan["pick_k"])
			var tw := smoothstep(tk, tk + 0.05, k) * (1.0 - smoothstep(tk + 0.08, tk + 0.14, k))
			_ik.r_knuckles = Basis(at[1], 0.35 * tw) * right
		_ik.pinch = at[2]
		# palm down to pick and dip; turned up toward his face as it comes to his mouth (the fingertips in first)
		var to_face := smoothstep(float(_plan["mouth_k"]) - 0.12, float(_plan["mouth_k"]), k) * (1.0 - smoothstep(float(_plan["in_k"]) + 0.05, float(_plan["in_k"]) + 0.14, k))
		_ik.r_thumb = (-right).lerp((Vector3.UP * 0.7 - right * 0.3).normalized(), to_face).normalized()
		_ik.lean_in = lerpf(_ik.lean_in, 0.07 if k < float(_plan["mouth_k"]) - 0.1 else 0.035, 1.0 - exp(-dt * 4.0))
		_ik.look_at_pt = _ik.look_at_pt.lerp(at[0] if k < float(_plan["mouth_k"]) - 0.08 else _mouth() + (-room.global_basis.z) * 1.0 + Vector3.DOWN * 0.3, 1.0 - exp(-dt * 6.0))
		if not _plan["picked"] and k >= float(_plan["pick_k"]):
			_plan["picked"] = true
			var src: Dictionary = _plan["main"] if not (_plan["main"] as Dictionary).is_empty() else _plan["dip"]
			var col := Kit.bite(src)                     # a piece off it: there's less on the plate
			(_morsel.material_override as StandardMaterial3D).albedo_color = col
			_morsel.mesh = _piece_mesh(_kind_of(src))      # (a torn bit of bread, a soft lump of idli, a ball of rice)
			_morsel.scale = Vector3.ONE * (_rng.randf_range(0.85, 1.1) if _kind_of(src) == "bread" else _rng.randf_range(0.8, 1.3))
			_morsel.rotation = Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf() * TAU, _rng.randf_range(-0.6, 0.6))
			_morsel.visible = true
			_eaten += 1
			_ui.queue_redraw()
		if not _plan["dipped"] and k >= float(_plan["dip_k"]) and not (_plan["dip"] as Dictionary).is_empty():
			_plan["dipped"] = true
			var dp: Dictionary = _plan["dip"]
			var mm := _morsel.material_override as StandardMaterial3D
			mm.albedo_color = mm.albedo_color.lerp(dp["colour"], 0.55)   # (coated)
			if int(dp["left"]) > 0 and (_bites_done % 2 == 1 or (_plan["main"] as Dictionary).is_empty()):
				Kit.bite(dp)                             # (the katori's level goes down every other dip)
				_eaten += 1
				_ui.queue_redraw()
		if _morsel.visible:
			_morsel.global_position = _ik.pinch_point(skel)
		if k >= float(_plan["in_k"]) - 0.01 and _morsel.visible:   # in his mouth (his lips close on it)
			_morsel.visible = false
		_dine_views(k)
		if k >= 1.0:
			_bite_t = -1.0
			_plan = {}
			_bites_done += 1
			_chew_t = _rng.randf_range(1.6, 2.6)
			_swallow = 0.0
			if _rng.randf() < 0.3:
				_glance = _rng.randf_range(0.8, 1.4)
			_ui.queue_redraw()
			if _eaten >= _total:
				_finish()
	if _face and _face.has_face():                       # the mouth opening for it, the lips closing on it, chewing
		var want := {}
		if _bite_t >= 0.0 and not _plan.is_empty():
			var k2 := clampf(_bite_t / float(_plan["dur"]), 0.0, 1.0)
			var mk := float(_plan["mouth_k"])
			var open := 0.32 * smoothstep(mk - 0.06, mk + 0.04, k2) * (1.0 - smoothstep(mk + 0.08, mk + 0.12, k2))
			want["mouth-open"] = open
			want["mouth-pursing"] = 0.28 * smoothstep(mk + 0.08, mk + 0.12, k2) * (1.0 - smoothstep(mk + 0.16, 1.0, k2))
			want["eye-left-slit"] = 0.3 if k2 < mk - 0.08 else 0.1          # (the lids down, looking at his food)
			want["eye-right-slit"] = want["eye-left-slit"]
		elif _chew_t > 0.0:
			_chew_t -= dt
			var c := 0.5 + 0.5 * sin(_t * TAU * 1.7)
			want["mouth-open"] = 0.04 + 0.06 * c                              # (the jaw going, lips together)
			want["mouth-compression"] = 0.12 + 0.08 * (1.0 - c)
			want["eye-left-slit"] = 0.15
			want["eye-right-slit"] = 0.15
			if _chew_t <= 0.0:
				_swallow = 0.35
		elif _swallow > 0.0:
			_swallow -= dt
			want["mouth-compression"] = 0.4                                   # (the swallow)
			want["mouth-corner-puller"] = 0.08
		_face.pose(want)
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
	if _ik and is_instance_valid(_ik):
		_ik.active = false
		_ik.queue_free()
		_ik = null
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
	if _done or _cam_t < 1.0 or _bite_t >= 0.0 or _chew_t > 0.0 or _swallow > 0.0 or _auto_t < _pause:
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
	if _views_dir == "" or _bites_done != 1 or _hold:
		return
	for m in [["reach", 0.12], ["pinch", float(_plan["pick_k"]) + 0.01], ["dip", float(_plan["dip_k"])], ["mouth", float(_plan["in_k"])]]:
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
		"close": [_ik.r_at + right * 0.35 + fwd * 0.3 + Vector3.UP * 0.12, _ik.r_at]}   # (close on the hand and the food)
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
	if _film_cam in ["front", "side", "close"]:
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
		elif _film_cam == "close":                          # (close: his face and his right hand, as it works)
			var mid := head.lerp(_ik.r_at if _ik else plate.global_position, 0.5)
			_film_v.global_position = mid + right * 0.55 + fwd * 0.45 + Vector3.UP * 0.05
			_film_v.look_at(mid, Vector3.UP)
		else:
			_film_v.global_position = head + right * 1.4 + fwd * 0.3 + Vector3.DOWN * 0.15
			_film_v.look_at(head + fwd * 0.3 + Vector3.DOWN * 0.3, Vector3.UP)
		if not _hold:
			_film_v.make_current()
	_film_t += dt
	if _film_t < 0.2 or _hold:
		return
	_film_t = 0.0
	get_viewport().get_texture().get_image().save_jpg("%s/f_%04d.jpg" % [_film_dir, _film_n], 0.8)
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
