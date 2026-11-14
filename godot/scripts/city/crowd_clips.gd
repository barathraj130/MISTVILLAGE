extends RefCounted
## The crowd's extra clips (tools/humans/crowd_clips.py: Phone, PhoneLook, WalkPhone, WalkCarry, built on one man and
## one woman) onto any crowd person: their tracks moved onto that person's own skeleton, as the library "crowd", and
## what they hold put in the right hand (a phone; a cloth bag).
##   add(person, sex)        the clips, once per AnimationPlayer
##   hold(person, what)      "phone", "bag" or "" (nothing)

const SRC := {"m": "res://assets/people/crowd_clips_m.glb", "w": "res://assets/people/crowd_clips_w.glb"}
const Kit := preload("res://scripts/story/food_kit.gd")

static var _libs := {}                                  # sex → [clip name, Animation (tracks as "Skeleton3D:bone")]


static func _source(sex: String) -> Array:
	if _libs.has(sex):
		return _libs[sex]
	var out := []
	if ResourceLoader.exists(SRC[sex]):
		var src := (load(SRC[sex]) as PackedScene).instantiate()
		var ap := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for n in ap.get_animation_list():
			out.append([n, ap.get_animation(n).duplicate(true)])
		src.free()
	_libs[sex] = out
	return out


static func add(person: Node, sex: String) -> bool:
	var aps := person.find_children("*", "AnimationPlayer", true, false)
	var sks := person.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or sks.is_empty():
		return false
	var ap := aps[0] as AnimationPlayer
	if ap.has_animation_library("crowd"):
		return true
	if ap.has_animation("Phone"):                       # (a living Sketchfab person: these clips are already hers,
		var own := AnimationLibrary.new()               #  made for her bones: "crowd/..." the same ones)
		for pair in _source(sex):
			if ap.has_animation(pair[0]):
				own.add_animation(pair[0], ap.get_animation(pair[0]))
		ap.add_animation_library("crowd", own)
		return true
	var skel_path := String(ap.get_node(ap.root_node).get_path_to(sks[0]))
	var lib := AnimationLibrary.new()
	for pair in _source(sex):
		var a := (pair[1] as Animation).duplicate(true) as Animation
		for t in a.get_track_count():                   # (its rig's node name → this person's)
			var p := String(a.track_get_path(t))
			a.track_set_path(t, NodePath(skel_path + ":" + p.get_slice(":", 1)))
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(pair[0], a)
	if lib.get_animation_list().is_empty():
		return false
	ap.add_animation_library("crowd", lib)
	return true


static func hold(person: Node, what: String) -> void:
	var sks := person.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var att: BoneAttachment3D = sk.get_node_or_null("Held")
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "Held"
		att.bone_name = "hand_r"
		sk.add_child(att)
	for c in att.get_children():
		c.queue_free()
	if what == "phone":                                 # a black phone in the palm (the hand bone's +Y: the fingers)
		var b := BoxMesh.new()
		b.size = Vector3(0.072, 0.15, 0.009)
		var mi := MeshInstance3D.new()
		mi.mesh = b
		mi.material_override = Kit.mat("crowd_phone", Color(0.04, 0.04, 0.05), 0.25, 0.3, false)
		mi.position = Vector3(0.0, 0.07, 0.025)
		att.add_child(mi)
	elif what == "bag":                                 # a cloth shopping bag hanging from the fingers
		var bag := BoxMesh.new()
		bag.size = Vector3(0.3, 0.32, 0.1)
		var bm := MeshInstance3D.new()
		bm.mesh = bag
		var cols := [Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.3), Color(0.85, 0.75, 0.5), Color(0.2, 0.3, 0.6)]
		var col: Color = cols[absi(person.get_instance_id()) % cols.size()]
		bm.material_override = Kit.mat("crowd_bag_%s" % col.to_html(), col, 0.9)
		bm.position = Vector3(0.0, 0.26, 0.0)            # (below the hand as it hangs: the fingers point down)
		att.add_child(bm)
