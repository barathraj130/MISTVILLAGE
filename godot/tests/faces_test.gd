extends SceneTree
## The story cast's faces (tools/humans/story_cast.py face_rig: expression units as blend shapes), close up in the game:
## each person neutral, smiling, blinking, angry, sad and mid-word, through scripts/story/face.gd. A picture each:
## <out>/face_<who>_<expression>.jpg.
##   Godot --resolution 900x900 --script res://tests/faces_test.gd -- --out=DIR [--who=amma,divya]

const Face := preload("res://scripts/story/face.gd")
const CAST := ["karthik", "raghavan", "suresh", "amma", "divya", "clerk", "cook", "ashwin", "muniyandi", "murugesan", "selvi", "sundaram"]
const EXPR := {
	"neutral": {},
	"smile": {"mouth-corner-puller": 0.6, "eye-left-slit": 0.2, "eye-right-slit": 0.2},
	"blink": {"eye-left-closure": 1.0, "eye-right-closure": 1.0},
	"angry": {"eyebrows-left-down": 0.7, "eyebrows-right-down": 0.7, "mouth-compression": 0.4},
	"sad": {"eyebrows-left-inner-up": 0.6, "eyebrows-right-inner-up": 0.6, "mouth-depression": 0.35},
	"speak": {"mouth-open": 0.3},
}

var out := "user://faces"
var who: Array = CAST


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		if a.begins_with("--who="):
			who = Array(a.get_slice("=", 1).split(","))
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_color = Color(0.95, 0.92, 0.88)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(35), 0)
	key.light_energy = 1.8
	w.add_child(key)
	var cam := Camera3D.new()
	cam.fov = 22.0
	w.add_child(cam)
	for k in who:
		var path := "res://assets/people/story_%s.glb" % k
		if not ResourceLoader.exists(path):
			continue
		var m := (load(path) as PackedScene).instantiate() as Node3D
		w.add_child(m)
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).play("Idle")
			(aps[0] as AnimationPlayer).pause()
		await process_frame
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))
		var c := head.origin + Vector3(0, 0.07, 0)
		cam.position = c + Vector3(0.12, 0.02, 0.62)
		cam.look_at(c)
		var f := Face.new(m)
		print("FACES %s: %s" % [k, "face shapes" if f.has_face() else "NO face shapes"])
		for e in EXPR:
			for u in ["mouth-corner-puller", "eye-left-slit", "eye-right-slit", "eye-left-closure", "eye-right-closure", "eyebrows-left-down",
					"eyebrows-right-down", "mouth-compression", "eyebrows-left-inner-up", "eyebrows-right-inner-up", "mouth-depression", "mouth-open"]:
				f.put(u, float(EXPR[e].get(u, 0.0)))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("%s/face_%s_%s.jpg" % [out, k, e], 0.88)
		m.queue_free()
		await process_frame
	quit()
