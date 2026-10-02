extends RefCounted
## A rider for two-wheelers: one of our own people (tools/people.py) playing the "Sit" pose
## (thighs along the seat, shins to the footpegs, hands forward to the bars).

const DIR := "res://assets/people/person_%s.glb"
const RIDERS := ["man_shirt", "man_lungi", "man_shirt", "woman_kurta", "schoolkid", "man_lungi", "woman_saree"]
const SKIN := [Color(0.42, 0.27, 0.17), Color(0.36, 0.22, 0.13), Color(0.48, 0.32, 0.2), Color(0.3, 0.18, 0.11)]
const SHIRTS := [Color(0.85, 0.85, 0.82), Color(0.15, 0.25, 0.55), Color(0.55, 0.12, 0.1), Color(0.3, 0.45, 0.3), Color(0.9, 0.75, 0.3)]

static var _scenes := {}


## The rider's node: place it so its origin sits `seat_h` below the saddle (the Sit pose drops the
## hips about 0.53 m below standing height).
static func make(seed_i: int, _seat_h := 0.6, _reach := 0.55) -> Node3D:
	var model: String = RIDERS[seed_i % RIDERS.size()]
	var path: String = DIR % model
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var node := (_scenes[path] as PackedScene).instantiate() as Node3D
	var ap := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	ap.get_animation("Sit").loop_mode = Animation.LOOP_LINEAR
	node.ready.connect(func() -> void: ap.play("Sit"))
	var skin: Color = SKIN[seed_i % SKIN.size()]
	var shirt: Color = SHIRTS[(seed_i * 3) % SHIRTS.size()]
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var col := Color(-1, 0, 0)
			match mat.resource_name:
				"Skin": col = skin
				"Top": col = shirt if model.begins_with("man") else mat.albedo_color
			if col.r >= 0.0:
				var v := mat.duplicate() as BaseMaterial3D
				v.albedo_color = col
				mi.set_surface_override_material(s, v)
	return node


## Where to put the rider on a bike / scooter so the hips sit on the saddle.
static func seat_offset(kind: String) -> Vector3:
	return Vector3(0, 0.84 - 0.53, -0.3) if kind == "bike" else Vector3(0, 0.8 - 0.53, -0.28)
