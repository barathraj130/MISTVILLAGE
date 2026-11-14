extends SceneTree
## The living Sketchfab people (tools/sketchfab_living.py → assets/people/sfa_<name>.glb) in the game's renderer: each
## from the front, walking, on the phone (crowd_clips.gd), turning the head (head_look.gd), and the face close: as
## it is, the eyes shut, the mouth open, a smile, the brows up; then each colour variant (sfa_<name>_t<i>.jpg).
## Pictures: <out>/<name>_<view>.jpg.
##   Godot --resolution 1000x800 --script res://tests/living_preview.gd -- --out=DIR [--who=woman_saree_yellow,...]

const Face := preload("res://scripts/story/face.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const Living := preload("res://scripts/city/sf_living.gd")

var out := "user://living"
var who: Array = []
var w: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		if a.begins_with("--who="):
			who = Array(a.get_slice("=", 1).split(","))
	if who.is_empty():
		who = Living.names()
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _shot(name: String) -> void:
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, name], 0.88)


func _look(pos: Vector3, at: Vector3, fov := 34.0) -> void:
	cam.fov = fov
	cam.position = pos
	cam.look_at(at)


func _run() -> void:
	w = Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.7, 0.8)
	env.ambient_light_color = Color(0.95, 0.92, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.55, 0.5, 0.44)
	fl.material_override = fm
	w.add_child(fl)
	cam = Camera3D.new()
	w.add_child(cam)
	for k in who:
		var m := Living.make(k, 0)
		if m == null:
			print("LIVING no ", k)
			continue
		w.add_child(m)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
		if ap:
			ap.play("Idle")
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		await process_frame
		var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin
		var tall := head.y + 0.2
		_look(Vector3(0.0, tall * 0.62, 3.0), Vector3(0, tall * 0.52, 0))
		await _shot(k + "_front")
		if ap == null:                                  # (built --noclips: the face only)
			await _faces(m, k, head)
			m.queue_free()
			continue
		ap.play("Walk")
		ap.seek(ap.current_animation_length * 0.45, true)
		_look(Vector3(2.4, tall * 0.62, 1.6), Vector3(0, tall * 0.52, 0))
		await _shot(k + "_walk")
		CrowdClips.add(m, Living.sex(k))
		CrowdClips.hold(m, "phone")
		ap.play("crowd/Phone")
		ap.seek(1.5, true)
		_look(Vector3(1.2, tall * 0.85, 1.6), Vector3(0, tall * 0.8, 0))
		await _shot(k + "_phone")
		CrowdClips.hold(m, "")
		ap.play("Idle")
		var hl := HeadLook.new()
		sk.add_child(hl)
		hl.target = Vector3(-2.0, 1.6, 1.0)
		hl.weight = 1.0
		for i in 30:
			await process_frame
		_look(Vector3(0.0, tall * 0.85, 1.8), Vector3(0, tall * 0.8, 0))
		await _shot(k + "_turn")
		hl.weight = 0.0
		hl.queue_free()
		await _faces(m, k, head)
		m.queue_free()
		for t in Living.tints(k):
			var mt := Living.make(k, t)
			w.add_child(mt)
			_look(Vector3(0.0, tall * 0.62, 3.0), Vector3(0, tall * 0.52, 0))
			await _shot("%s_tint%d" % [k, t])
			mt.queue_free()
		await process_frame
	quit()


func _faces(m: Node3D, k: String, head: Vector3) -> void:
	var f := Face.new(m)
	var close := head + Vector3(0, 0.035, 0)
	for e in [["face", {}], ["blink", {"eye-left-closure": 1.0, "eye-right-closure": 1.0}],
			["talk", {"mouth-open": 0.35}], ["smile", {"mouth-corner-puller": 0.8}],
			["brows", {"eyebrows-left-up": 0.8, "eyebrows-right-up": 0.8, "eye-left-slit": 0.0}]]:
		for u in ["eye-left-closure", "eye-right-closure", "mouth-open", "mouth-corner-puller", "eyebrows-left-up", "eyebrows-right-up"]:
			f.put(u, 0.0)
		for u in e[1]:
			f.put(u, e[1][u])
		_look(close + Vector3(0.0, 0.0, 0.55), close, 22.0)
		await _shot("%s_%s" % [k, e[0]])
		if e[0] == "face":                             # (and from the side, three-quarter and profile: its shape)
			_look(close + Vector3(0.36, 0.0, 0.42), close, 22.0)
			await _shot("%s_face34" % k)
			_look(close + Vector3(0.55, 0.0, 0.02), close, 22.0)
			await _shot("%s_profile" % k)
	print("LIVING ", k, " face ", f.has_face())
