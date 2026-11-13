extends SceneTree
## People acting in conversation (scripts/story/acting.gd, story/emotions.json), on a plain stage with a wide camera:
## each scene a few lines with their feelings and gestures, a picture of each line 1.8 s in.
##   Godot --resolution 1280x720 --script res://tests/acting_test.gd -- --out=DIR
## Scenes: a stranger greeted (namaste), a nervous witness questioned, an angry man confronted, three laughing
## together, two arguing.

const Actor := preload("res://scripts/story/actor.gd")
const Acting := preload("res://scripts/story/acting.gd")

var out := "user://acting"
var world: Node3D
var cam: Camera3D

const SCENES := [
	["greet", {"karthik": ["story_karthik", -0.7, 0.0], "stranger": ["crowd_m3", 0.7, 0.0]}, [
		{"who": "karthik", "en": "Vanakkam, sir.", "gesture": "namaste", "emotion": "respectful", "to": "stranger"},
		{"who": "stranger", "en": "Vanakkam. Yes?", "gesture": "nod", "emotion": "curious", "to": "karthik"}]],
	["witness", {"karthik": ["story_karthik", -0.7, 0.0], "divya": ["story_divya", 0.7, 0.0]}, [
		{"who": "karthik", "en": "Did you see the vehicle that night?", "emotion": "curious", "intensity": "medium", "to": "divya"},
		{"who": "divya", "en": "I... I don't remember. Maybe.", "emotion": "nervous", "intensity": "high", "gesture": "shrug", "to": "karthik"}]],
	["angry", {"karthik": ["story_karthik", -0.75, 0.0], "suresh": ["story_suresh", 0.75, 0.0]}, [
		{"who": "suresh", "en": "Who told you to come here? Get out!", "emotion": "angry", "intensity": "high", "gesture": "argue", "to": "karthik"},
		{"who": "karthik", "en": "Sir, please, just listen.", "emotion": "frustrated", "intensity": "medium", "to": "suresh"}]],
	["friends", {"karthik": ["story_karthik", -0.8, 0.3], "divya": ["story_divya", 0.8, 0.3], "amma": ["story_amma", 0.0, -0.7]}, [
		{"who": "divya", "en": "And then he fell right into the water!", "emotion": "happy", "intensity": "high", "gesture": "laugh"},
		{"who": "amma", "en": "Aiyo, that boy.", "emotion": "happy", "intensity": "medium", "gesture": "wobble"}]],
	["handshake", {"karthik": ["story_karthik", -0.55, 0.0], "stranger": ["crowd_m3", 0.55, 0.0]}, [
		{"who": "karthik", "en": "Nice to meet you, sir.", "gesture": "handshake", "emotion": "respectful", "to": "stranger"}]],
	["comfort", {"karthik": ["story_karthik", -0.5, 0.0], "divya": ["story_divya", 0.5, 0.0]}, [
		{"who": "karthik", "en": "It'll be all right. I promise.", "gesture": "comfort", "emotion": "sad", "intensity": "medium", "to": "divya"}]],
	["give", {"karthik": ["story_karthik", -0.6, 0.0], "kathir": ["crowd_m2", 0.6, 0.0]}, [
		{"who": "karthik", "en": "From my advocate.", "gesture": "give", "emotion": "respectful", "to": "kathir"}]],
	["laugh", {"divya": ["story_divya", -0.6, 0.0], "amma": ["story_amma", 0.6, 0.0]}, [
		{"who": "divya", "en": "And then he fell in!", "gesture": "laugh", "emotion": "happy", "intensity": "high", "to": "amma"}]],
	["argue", {"m": ["crowd_m1", -0.65, 0.0], "w": ["crowd_w2", 0.65, 0.0]}, [
		{"who": "m", "en": "I paid you yesterday!", "emotion": "angry", "intensity": "medium", "gesture": "argue", "to": "w"},
		{"who": "w", "en": "No, you didn't.", "emotion": "frustrated", "intensity": "high", "gesture": "shake", "to": "m"}]],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _stage() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_color = Color(0.9, 0.88, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.45, 0.4)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.55, 4.2)
	cam.look_at(Vector3(0, 1.15, 0))


func _run() -> void:
	_stage()
	for sc in SCENES:
		var people := {}
		for key in sc[1]:
			var spec: Array = sc[1][key]
			var a := Actor.new()
			world.add_child(a)
			a.setup(spec[0], key, func(_x, _z): return 0.0)
			a.place(Vector3(spec[1], 0.0, spec[2]), Vector3(0, 0, 0.4))
			people[key] = a
		var acting := Acting.new()
		world.add_child(acting)
		for i in sc[2].size():
			acting.line(sc[2][i], people)
			await create_timer(1.8).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("%s/%s_%d.jpg" % [out, sc[0], i], 0.88)
			print("ACTING %s line %d" % [sc[0], i])
			await create_timer(0.8).timeout
		acting.stop()
		acting.queue_free()
		for k in people:
			people[k].queue_free()
		await process_frame
	quit()
