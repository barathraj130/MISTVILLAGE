extends RefCounted
## The people in a public room (the station, a bus stand, the airport, a mall, the church, the stadium): the room's
## Crowd_<pose>_<n> marks (tools/city_rooms.py: sitting on a bench, standing in a queue, two friends talking) filled
## with the crowd people (tools/humans/crowd_cast.py: made as the story's cast is, faces of their own, lighter),
## sitting, idling or talking, each at its own moment of the clip. Who is where is decided by the building (the same
## crowd every visit); not every mark is taken. Standing people are solid. (Without the crowd people, the older
## figures of tools/people.py, dressed in colours of their own as the street crowd is.)

const CROWD := "res://assets/people/crowd_%s.glb"
const CROWD_WHO := ["m1", "m2", "m3", "m4", "m5", "m6", "w1", "w2", "w3", "w4", "w5", "w6"]
const STRIDE := {"m3": 1.0, "w1": 0.85, "w2": 0.85, "w3": 0.85, "w6": 0.85}   # m a Walk cycle (saree, veshti: shorter)
const DIR := "res://assets/people/person_%s.glb"
const WHO := ["man_shirt", "man_shirt", "man_lungi", "woman_saree", "woman_saree", "woman_kurta", "woman_kurta",
	"elder", "schoolkid"]
const POSE := {"sit": "Sit", "stand": "Idle", "talk": "Talk"}
const SKIN := [Color(0.42, 0.27, 0.17), Color(0.36, 0.22, 0.13), Color(0.48, 0.32, 0.2), Color(0.3, 0.18, 0.11),
	Color(0.55, 0.38, 0.25), Color(0.4, 0.25, 0.16)]
const CLOTH := [Color(0.85, 0.85, 0.82), Color(0.15, 0.22, 0.45), Color(0.55, 0.1, 0.12), Color(0.12, 0.35, 0.25),
	Color(0.75, 0.55, 0.15), Color(0.45, 0.15, 0.4), Color(0.3, 0.3, 0.32), Color(0.85, 0.45, 0.1), Color(0.6, 0.75, 0.85),
	Color(0.9, 0.8, 0.6), Color(0.08, 0.08, 0.1), Color(0.7, 0.2, 0.35)]


## Fill room's marks (about `fill` of them; a big stand fewer) and give the standing ones a body in `body`.
static func fill(room: Node3D, body: StaticBody3D, key: String, fill := 0.7) -> int:
	var marks := room.find_children("Crowd_*", "", true, false)
	if marks.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var share := fill if marks.size() < 80 else fill * 0.65
	var n := 0
	for m in marks:
		if rng.randf() > share:
			continue
		var pose: String = String(m.name).get_slice("_", 1)
		var npc := person(room, rng)
		if npc == null:
			continue
		var mk := m as Node3D
		npc.global_position = mk.global_position
		var f := -mk.global_basis.z                        # the mark faces +Y in Blender: -Z here
		npc.global_rotation = Vector3(0, atan2(f.x, f.z) + rng.randf_range(-0.15, 0.15), 0)
		var aps := npc.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			var clip: String = POSE.get(pose, "Idle")
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				ap.play(clip)
				ap.seek(rng.randf() * ap.current_animation_length, true)
				ap.speed_scale = rng.randf_range(0.85, 1.15)
		if pose != "sit" and body:                         # you walk round them, not through
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.25
			cap.height = 1.6
			cs.shape = cap
			body.add_child(cs)
			cs.global_position = mk.global_position + Vector3(0, 0.8, 0)
		n += 1
	return n


## One of our people, chosen and dressed by rng, added under parent (null if the model isn't there).
static func person(parent: Node, rng: RandomNumberGenerator) -> Node3D:
	var key: String = CROWD_WHO[rng.randi() % CROWD_WHO.size()]
	if ResourceLoader.exists(CROWD % key):
		var p := (load(CROWD % key) as PackedScene).instantiate() as Node3D
		parent.add_child(p)
		p.scale = Vector3.ONE * rng.randf_range(0.96, 1.04)
		p.set_meta("stride", STRIDE.get(key, 1.18))    # (the cast's Walk: 1.18 m a cycle, measured on the clip)
		return p
	var who: String = WHO[rng.randi() % WHO.size()]
	if not ResourceLoader.exists(DIR % who):
		return null
	var npc := (load(DIR % who) as PackedScene).instantiate() as Node3D
	parent.add_child(npc)
	npc.scale = Vector3.ONE * rng.randf_range(0.94, 1.06)
	npc.set_meta("stride", 1.25)
	_dress(npc, who, rng)
	return npc


## Skin, hair and clothes of their own (the elder's white veshti and the school uniform stay as made).
static func _dress(node: Node3D, who: String, rng: RandomNumberGenerator) -> void:
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var swaps := {}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var name := mat.resource_name
			var col: Color
			if name.begins_with("Skin"):
				col = skin * (0.88 if name.contains("Darker") else 1.0)
			elif name.begins_with("Hair"):
				col = Color(0.68, 0.68, 0.66) if who == "elder" else Color(0.03, 0.025, 0.02)
			elif who == "elder" or who == "schoolkid" or name == "Shoes":
				continue
			else:
				if not swaps.has(name):
					swaps[name] = CLOTH[rng.randi() % CLOTH.size()]
				col = swaps[name]
			var m2 := mat.duplicate() as BaseMaterial3D
			m2.albedo_color = col
			(mi as MeshInstance3D).set_surface_override_material(s, m2)
