extends SceneTree
## (testing) The eating system on its own (the universal eating brief): Karthik seated at a table, any dish from
## story/food.json served by food_kit.gd (and a drink beside it), eater.gd eating it: the same controller the home
## table and the eateries use. It prints each state as it starts, what came off the table, the right wrist's solve
## (forearm turn, wrist twist, flexion, deviation) and, at the end, what's left of each part; it films the meal from
## one camera (a frame every --step seconds of the meal: 0.05 played at 5 fps is four times slow).
##   godot --path . --audio-driver Dummy --script tests/eat_test.gd -- --dish=poori[,tea] --bites=3 \
##       --cam=front|side|close|hand --step=0.1 --out=DIR [--table=0.775] [--standing]

const Eater := preload("res://scripts/story/eater.gd")
const Kit := preload("res://scripts/story/food_kit.gd")

var out := ""
var dishes: Array = ["poori"]
var bites := 3
var view := "front"
var step := 0.1
var table_top := 0.775
var model: Node3D
var eater
var cam: Camera3D
var fwd := Vector3(0, 0, 1)
var right := Vector3(-1, 0, 0)
var t := -1.2
var n := 0
var since := 0.0
var started := 0
var focus := Vector3.ZERO
var wrist_max := Vector4.ZERO
var done_t := -1.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--out="):
			out = v
		elif a.begins_with("--dish="):
			dishes = Array(v.split(","))
		elif a.begins_with("--bites="):
			bites = int(v)
		elif a.begins_with("--cam="):
			view = v
		elif a.begins_with("--step="):
			step = float(v)
		elif a.begins_with("--table="):
			table_top = float(v)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(200), 0)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_ := _box(world, Vector3(4, 0.02, 4), Color(0.5, 0.45, 0.4), Vector3(0, -0.01, 0))
	floor_.name = "Floor"
	# the table before him and his chair (the home dining corner's sizes: dine3d.gd)
	var teak := Color(0.42, 0.26, 0.14)
	_box(world, Vector3(0.82, 0.03, 0.6), teak, Vector3(0, table_top - 0.015, 0.47))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(world, Vector3(0.045, table_top - 0.03, 0.045), teak, Vector3(sx * 0.36, (table_top - 0.03) * 0.5, 0.47 + sz * 0.26))
	var red := Color(0.68, 0.11, 0.09)
	_box(world, Vector3(0.44, 0.035, 0.42), red, Vector3(0, 0.44, -0.02))
	_box(world, Vector3(0.44, 0.42, 0.03), red, Vector3(0, 0.66, -0.22))
	model = (load("res://assets/people/story_karthik.glb") as PackedScene).instantiate()
	world.add_child(model)
	(model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).play("Sit")
	# what's served: the dish on its plate where his hand goes (0.42 m ahead, 0.1 m to his right), a drink by it
	var servings: Array = []
	for i in dishes.size():
		var d := Kit.build(str(dishes[i]))
		world.add_child(d)
		var at := fwd * 0.42 + right * 0.1 if i == 0 else fwd * 0.36 + right * 0.31
		d.global_transform = Transform3D(Basis(right, Vector3.UP, -fwd), Vector3(at.x, table_top + 0.002, at.z))
		servings.append(d)
	eater = Eater.new()
	world.add_child(eater)
	eater.log_states = true
	eater.bite_taken.connect(func(p): print("EAT taken: %s (%d of %d left)" % [p["label"], int(p["left"]), int(p["bites"])]))
	eater.setup.call_deferred(model, fwd, servings)
	if "--contactdebug" in OS.get_cmdline_user_args():
		(func(): eater.ik.debug_contact = true).call_deferred()
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	world.add_child(cam)
	cam.make_current()
	root.size = Vector2i(1280, 800)


func _box(parent: Node3D, size: Vector3, col: Color, at: Vector3) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	mi.material_override = m
	parent.add_child(mi)
	mi.position = at
	return mi


func _process(dt: float) -> bool:
	t += dt
	if t < 0.0 or eater.ik == null:
		return false
	eater.ik.contact_warm = t > 1.0
	if not eater.busy() and done_t < 0.0:
		if started < bites and eater.left_count() > 0:
			if eater.bite(-1):
				started += 1
		else:
			done_t = t
	if eater.ik.wrist_log.has("r") and eater.bite_t >= 0.0:
		var w: Vector4 = eater.ik.wrist_log["r"]
		wrist_max = Vector4(maxf(wrist_max.x, absf(w.x)), maxf(wrist_max.y, absf(w.y)), maxf(wrist_max.z, absf(w.z)), maxf(wrist_max.w, absf(w.w)))
	# the camera
	var lips: Vector3 = eater.mouth()
	var hand: Vector3 = eater.ik.pinch_world if eater.ik.pinch_world != Vector3.ZERO else lips
	focus = hand if focus == Vector3.ZERO else focus.lerp(hand, 0.2)
	match view:
		"side":
			var c := lips.lerp(Vector3(0, table_top, 0.4), 0.45)
			cam.global_position = c + right * 1.25 + fwd * 0.15
			cam.look_at(c, Vector3.UP)
		"close":
			var c2 := lips.lerp(focus, 0.5)
			cam.global_position = c2 + fwd * 0.75 + right * 0.45 + Vector3.UP * 0.1
			cam.look_at(c2, Vector3.UP)
		"hand":
			cam.global_position = focus + fwd * 0.36 + right * 0.2 + Vector3.UP * 0.06
			cam.look_at(focus, Vector3.UP)
		"handside":
			cam.global_position = focus + right * 0.38 + fwd * 0.06 + Vector3.UP * 0.05
			cam.look_at(focus, Vector3.UP)
		_:
			var c3 := lips.lerp(Vector3(0, table_top, 0.42), 0.4)
			cam.global_position = c3 + fwd * 1.3 + Vector3.UP * 0.15
			cam.look_at(c3, Vector3.UP)
	since += dt
	if out != "" and since >= step:
		since = 0.0
		_capture.call_deferred()
	if done_t >= 0.0 and t > done_t + 0.8:
		var lefts := []
		for p in eater.parts:
			lefts.append("%s %d/%d" % [p["label"], int(p["left"]), int(p["bites"])])
		var cl: Dictionary = eater.ik.contact_log
		print("EATCONTACT %s: deepest into the table, plate, katoris, tumbler or food: right %.1f mm (before the contact pass %.1f; frames over 3 mm: %d of %d), left %.1f mm (before %.1f; over 3 mm: %d of %d)" % [
			",".join(dishes), float(cl["r"]) * 1000.0, float(cl["r_before"]) * 1000.0, int(cl.get("r_over3", 0)), int(cl.get("r_n", 0)),
			float(cl["l"]) * 1000.0, float(cl["l_before"]) * 1000.0, int(cl.get("l_over3", 0)), int(cl.get("l_n", 0))])
		print("EATTEST %s: %d bites, %d of %d taken off the table; left: %s; wrist max: forearm %.0f, twist %.0f, flex %.0f, dev %.0f deg" % [
			",".join(dishes), started, eater.eaten, eater.total, ", ".join(lefts), wrist_max.x, wrist_max.y, wrist_max.z, wrist_max.w])
		return true
	return t > 90.0


func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/f_%04d.jpg" % [out, n], 0.85)
	n += 1
