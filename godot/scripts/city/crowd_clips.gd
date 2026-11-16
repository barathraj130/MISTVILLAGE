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


## The clip as this person's: its bones' turns only (and the hips' place), not every bone's position as the source
## man had it. Positions keyed from one man's rest pose pulled another's face bones away (the eyebrows and lashes
## stretched into long spikes across the fight); turns fit any body of the same rig, each keeping its own proportions.
static func _turns_only(a: Animation) -> void:
	for t in range(a.get_track_count() - 1, -1, -1):
		var ty := a.track_get_type(t)
		var bone := String(a.track_get_path(t)).get_slice(":", 1)
		if ty == Animation.TYPE_SCALE_3D or (ty == Animation.TYPE_POSITION_3D and not bone in ["pelvis", "root", "Root"]):
			a.remove_track(t)


static func add(person: Node, sex: String, same_rig := false) -> bool:
	var aps := person.find_children("*", "AnimationPlayer", true, false)
	var sks := person.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or sks.is_empty():
		return false
	var ap := aps[0] as AnimationPlayer
	if same_rig:                                        # (one of the story's own people, built on the crowd's rig
		var skp := String(ap.get_node(ap.root_node).get_path_to(sks[0]))   #  (story_cast.py): every clip he lacks,
		var have: AnimationLibrary = ap.get_animation_library("crowd") if ap.has_animation_library("crowd") else null
		if have == null:                                #  added to his "crowd" set, whatever's there already)
			have = AnimationLibrary.new()
			ap.add_animation_library("crowd", have)
		for pair in _source(sex):
			if have.has_animation(pair[0]):
				continue
			var c := (pair[1] as Animation).duplicate(true) as Animation
			for t in c.get_track_count():
				c.track_set_path(t, NodePath(skp + ":" + String(c.track_get_path(t)).get_slice(":", 1)))
			_turns_only(c)
			have.add_animation(pair[0], c)
		return true
	if ap.has_animation_library("crowd"):
		return true
	if ap.has_animation("Phone"):                       # (a living Sketchfab person: only the clips made for HER bones
		var own := AnimationLibrary.new()               #  when she was built (sketchfab_living.py retargets them to her
		for pair in _source(sex):                       #  rest pose); the crowd's own tracks, copied straight across,
			if ap.has_animation(pair[0]):               #  twisted her (her bones rest at other angles): one lay flat)
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
		_turns_only(a)
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(pair[0], a)
	if lib.get_animation_list().is_empty():
		return false
	ap.add_animation_library("crowd", lib)
	return true


static func _slot(sk: Skeleton3D, name: String, bone: String) -> BoneAttachment3D:
	var att: BoneAttachment3D = sk.get_node_or_null(name)
	if att == null:
		att = BoneAttachment3D.new()
		att.name = name
		att.bone_name = bone
		sk.add_child(att)
	for c in att.get_children():
		c.queue_free()
	return att


static func _part(att: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	att.add_child(mi)
	return mi


static func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c


## What a worker holds (made here, plain shapes in the hand bones' frames: +Y along the fingers):
##   "broom" a short coconut-frond broom; "tea" a steel jug (right) and a glass (left); "ladle"; "pen"; "cloth";
##   "load" a basket on the head; and the old "phone", "bag"; "" nothing.
static func hold(person: Node, what: String) -> void:
	var sks := person.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var att := _slot(sk, "Held", "hand_r")
	var left := _slot(sk, "HeldL", "hand_l")
	var top := _slot(sk, "HeldHead", "head")
	var steel := Kit.mat("crowd_steel", Color(0.78, 0.78, 0.8), 0.25, 0.85, false)
	match what:
		"broom":                                      # the stick in the fist, the fronds fanning down past the fingers
			_part(att, _cyl(0.018, 0.32), Kit.mat("crowd_twine", Color(0.55, 0.42, 0.25), 0.9), Vector3(0, 0.04, 0.02))
			_part(att, _cyl(0.03, 0.42, 0.012), Kit.mat("crowd_fronds", Color(0.62, 0.55, 0.3), 0.95), Vector3(0, 0.38, 0.02))
		"tea":
			_part(att, _cyl(0.045, 0.14), steel, Vector3(0, 0.05, 0.04))
			_part(left, _cyl(0.028, 0.1, 0.033), Kit.mat("crowd_glass", Color(0.85, 0.75, 0.55), 0.1, 0.0, false), Vector3(0, 0.05, 0.035))
		"ladle":
			_part(att, _cyl(0.007, 0.42), steel, Vector3(0, 0.18, 0.02))
			_part(att, _cyl(0.04, 0.03), steel, Vector3(0, 0.39, 0.02))
		"pen":
			_part(att, _cyl(0.004, 0.14), Kit.mat("crowd_pen", Color(0.1, 0.15, 0.5), 0.4), Vector3(0, 0.06, 0.015), Vector3(0.4, 0, 0))
		"cloth":
			var b := BoxMesh.new()
			b.size = Vector3(0.12, 0.1, 0.03)
			_part(att, b, Kit.mat("crowd_cloth", Color(0.85, 0.85, 0.8), 0.95), Vector3(0, 0.06, 0.03))
		"load":                                       # a cane basket on a coiled cloth, on the head
			_part(top, _cyl(0.24, 0.16, 0.2), Kit.mat("crowd_basket", Color(0.6, 0.45, 0.25), 0.9), Vector3(0, 0.22, 0))
			_part(top, _cyl(0.1, 0.03), Kit.mat("crowd_coil", Color(0.75, 0.2, 0.2), 0.95), Vector3(0, 0.13, 0))
		"phone", "bag":
			pass
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
