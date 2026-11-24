extends SceneTree
## (build) The editable man in a shirt (the user's custom-animation brief): the "custom" animation library for the
## inherited scene res://assets/people/person_man_shirt_custom.tscn (the .glb is never touched): Custom_Idle,
## Custom_Walk, Custom_Run, Custom_Talk, Custom_Sit.
##   godot --headless --path . --script scripts/people/person_custom_build.gd
## Writes res://assets/people/person_man_shirt_custom_anims.tres (the library); run again to rebuild it. The scene
## refers to it and needs no rebuilding.
##
## The rig (inspected): 18 bones, Root > Hips > Spine > Chest > Neck > Head; the arms off the Chest (UpperArm, LowerArm,
## Hand, .L/.R), the legs off the Hips (Thigh, Shin, Foot); no fingers, no toes. Bones point along their local Y;
## their local X is the bend (forward/back), Z the side (out/in). The imported clips key Hips position (its height only:
## no root travel) and rotations of every bone but Root, Neck and Hand.L; their Idle is a fixed stance (arms hanging,
## feet flat) with the chest breathing. Every custom clip starts from that stance (or the imported clip it refines)
## and adds small motions as rotations about the bones' own axes, each a whole number of cycles in the clip's length
## so it loops with no seam; tracks only on real bones, at their real paths (Rig/Skeleton3D:<bone>, from the player's
## root, "..").

const GLB := "res://assets/people/person_man_shirt.glb"
const LIB_PATH := "res://assets/people/person_man_shirt_custom_anims.tres"
const SCENE_PATH := "res://assets/people/person_man_shirt_custom.tscn"
const SK := "Rig/Skeleton3D:"
const STEP := 1.0 / 15.0                 # (a key every 1/15 s: smooth curves, the cubic interpolation between)

var _src: AnimationPlayer
var _skel: Skeleton3D


func _init() -> void:
	var base := load(GLB) as PackedScene
	var probe := base.instantiate()
	root.add_child(probe)
	_src = probe.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_skel = probe.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lib := AnimationLibrary.new()
	lib.add_animation("Custom_Idle", _idle())
	lib.add_animation("Custom_Walk", _refine("Walk", 0.0))
	lib.add_animation("Custom_Run", _refine("Run", 0.0))
	lib.add_animation("Custom_Talk", _talk())
	lib.add_animation("Custom_Sit", _refine("Sit", 1.0))
	var e := ResourceSaver.save(lib, LIB_PATH)
	print("CUSTOMBUILD library saved: %s (%s)" % [LIB_PATH, error_string(e)])
	probe.queue_free()
	# the inherited scene is written as text (person_man_shirt_custom.tscn, kept in the repo): the .glb as its base, and
	# a second AnimationPlayer holding the "custom" library. (Not the imported player given a second library: in an
	# inherited scene that override replaces its whole library list, and the imported clips, embedded in the .glb's
	# import, can't be listed beside it; tried: Idle, Walk, Run were gone. player.gd lends the library to the imported
	# player at runtime, so one player drives the skeleton.)
	quit()


## The stance: each bone's rotation in the imported Idle (its first key), or its rest where Idle has no track.
func _stance(bone: String) -> Quaternion:
	var an := _src.get_animation("Idle")
	var t := an.find_track(NodePath(SK + bone), Animation.TYPE_ROTATION_3D)
	if t >= 0:
		return an.track_get_key_value(t, 0)
	return _skel.get_bone_rest(_skel.find_bone(bone)).basis.get_rotation_quaternion()


## A bone's rotation over a clip: base * (turns about its own X, Y, Z, in radians, from f(t) → Vector3).
func _rot_track(an: Animation, bone: String, base_of: Callable, f: Callable) -> void:
	var t := an.add_track(Animation.TYPE_ROTATION_3D)
	an.track_set_path(t, NodePath(SK + bone))
	an.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
	an.track_set_interpolation_loop_wrap(t, true)
	var n := int(round(an.length / STEP))
	for i in n + 1:
		var tm := minf(i * STEP, an.length)
		var e: Vector3 = f.call(tm)
		var base: Quaternion = base_of.call(tm)
		var q := base * Quaternion.from_euler(e)
		an.rotation_track_insert_key(t, tm, q.normalized())


func _const(bone: String) -> Callable:
	var q := _stance(bone)
	return func(_t: float) -> Quaternion: return q


## Custom_Idle: standing, at ease, 4 s, looping. Breathing (one breath in the 4 s: the spine and chest lift a
## little and the shoulders rise with it, the neck taking the chest's tilt back so the head stays level), the head's
## own small drift (looking about by a degree or so, never a jerk), the arms hanging relaxed with the forearms easing
## a touch with the breath, the hands loose. The legs and the hips are the stance exactly, every frame: the feet stay
## planted (no weight shift that would slide them: the clip has no foot IK; the game's own foot_ik.gd plants them at
## runtime, so a sway can be added there later).
func _idle() -> Animation:
	var an := Animation.new()
	an.length = 4.0
	an.loop_mode = Animation.LOOP_LINEAR
	var w := TAU / 4.0                                   # (one cycle in the clip)
	var br := func(t: float) -> float: return sin(w * t - PI * 0.5) * 0.5 + 0.5   # (0 at the start: breathing in)
	var hp := an.add_track(Animation.TYPE_POSITION_3D)   # (the hips' height, still: as the stance)
	an.track_set_path(hp, NodePath(SK + "Hips"))
	var hips_pos: Vector3 = _src.get_animation("Idle").track_get_key_value(_src.get_animation("Idle").find_track(NodePath(SK + "Hips"), Animation.TYPE_POSITION_3D), 0)
	an.position_track_insert_key(hp, 0.0, hips_pos)
	for b in ["Hips", "Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R"]:
		_rot_track(an, b, _const(b), func(_t: float) -> Vector3: return Vector3.ZERO)
	_rot_track(an, "Spine", _const("Spine"), func(t: float) -> Vector3: return Vector3(deg_to_rad(-0.6) * br.call(t), 0, 0))
	_rot_track(an, "Chest", _const("Chest"), func(t: float) -> Vector3: return Vector3(deg_to_rad(-1.2) * br.call(t), 0, 0))
	_rot_track(an, "Neck", _const("Neck"), func(t: float) -> Vector3:
		return Vector3(deg_to_rad(1.2) * br.call(t), deg_to_rad(0.5) * sin(w * t + 0.9), 0))
	_rot_track(an, "Head", _const("Head"), func(t: float) -> Vector3:
		return Vector3(deg_to_rad(0.5) * br.call(t) + deg_to_rad(0.4) * sin(2.0 * w * t + 0.4),
			deg_to_rad(1.1) * sin(w * t + 1.7) + deg_to_rad(0.35) * sin(3.0 * w * t),
			deg_to_rad(0.4) * sin(w * t + 2.6)))
	for s in [["L", 1.0], ["R", -1.0]]:
		var side: String = s[0]
		var m: float = s[1]
		_rot_track(an, "UpperArm." + side, _const("UpperArm." + side), func(t: float) -> Vector3:
			return Vector3(deg_to_rad(0.5) * sin(w * t + 0.6 * m), 0, deg_to_rad(0.7) * m * br.call(t)))
		_rot_track(an, "LowerArm." + side, _const("LowerArm." + side), func(t: float) -> Vector3:
			return Vector3(deg_to_rad(-1.0) * br.call(t), 0, 0))
		_rot_track(an, "Hand." + side, _const("Hand." + side), func(t: float) -> Vector3:
			return Vector3(deg_to_rad(1.5) * sin(w * t + 1.2 + 0.5 * m), 0, 0))
	return an


## Custom_Walk / Run / Sit: the imported clip refined, not replaced: the same bones, poses and timing; looping, its
## curves cubic, keyed densely from the original's own values (so the loop meets itself: the last key is the first's
## pose), the Neck and Hand.L (untracked in the original, so frozen at rest) given tracks that follow: the neck easing
## the head's sway, the left hand matching the right's. breathe > 0 lays a slow breath over the spine and chest (sitting).
func _refine(src_name: String, breathe: float) -> Animation:
	var src := _src.get_animation(src_name)
	var an := Animation.new()
	an.length = src.length
	an.loop_mode = Animation.LOOP_LINEAR
	var n := maxi(int(round(src.length / STEP)), 8)
	var dt := src.length / float(n)
	var w := TAU / src.length
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		var ty := src.track_get_type(t)
		var nt := an.add_track(ty)
		an.track_set_path(nt, path)
		an.track_set_interpolation_type(nt, Animation.INTERPOLATION_CUBIC)
		an.track_set_interpolation_loop_wrap(nt, true)
		var bone := str(path).get_slice(":", 1)
		for i in n + 1:
			var tm := minf(i * dt, src.length - 0.0001) if i < n else 0.0
			var key_t := float(i) * dt
			if ty == Animation.TYPE_POSITION_3D:
				an.position_track_insert_key(nt, minf(key_t, src.length), src.position_track_interpolate(t, tm))
			elif ty == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = src.rotation_track_interpolate(t, tm)
				if breathe > 0.0 and bone in ["Spine", "Chest"]:
					var b := (sin(w * key_t - PI * 0.5) * 0.5 + 0.5) * breathe
					q = q * Quaternion(Vector3.RIGHT, deg_to_rad(-0.6 if bone == "Spine" else -1.1) * b)
				an.rotation_track_insert_key(nt, minf(key_t, src.length), q.normalized())
	# the neck (no track in the original: still at rest): a third of the head's turn, the head keeping the rest
	var ht := src.find_track(NodePath(SK + "Head"), Animation.TYPE_ROTATION_3D)
	if ht >= 0 and src.find_track(NodePath(SK + "Neck"), Animation.TYPE_ROTATION_3D) < 0:
		var nk := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(nk, NodePath(SK + "Neck"))
		an.track_set_interpolation_type(nk, Animation.INTERPOLATION_CUBIC)
		an.track_set_interpolation_loop_wrap(nk, true)
		var rest_n := _stance("Neck")
		var head0: Quaternion = src.rotation_track_interpolate(ht, 0.0)
		for i in n + 1:
			var tm := minf(i * dt, src.length - 0.0001) if i < n else 0.0
			var hq: Quaternion = src.rotation_track_interpolate(ht, tm)
			var d := head0.inverse() * hq                    # (the head's own sway in the clip)
			an.rotation_track_insert_key(nk, minf(float(i) * dt, src.length), (rest_n * Quaternion.IDENTITY.slerp(d, 0.33)).normalized())
	# the left hand: the right's motion, mirrored (Hand.L has no track: it was frozen)
	var hr := src.find_track(NodePath(SK + "Hand.R"), Animation.TYPE_ROTATION_3D)
	if hr >= 0 and src.find_track(NodePath(SK + "Hand.L"), Animation.TYPE_ROTATION_3D) < 0:
		var hl := an.add_track(Animation.TYPE_ROTATION_3D)
		an.track_set_path(hl, NodePath(SK + "Hand.L"))
		an.track_set_interpolation_type(hl, Animation.INTERPOLATION_CUBIC)
		an.track_set_interpolation_loop_wrap(hl, true)
		for i in n + 1:
			var tm := minf(i * dt, src.length - 0.0001) if i < n else 0.0
			var q2: Quaternion = src.rotation_track_interpolate(hr, tm)
			an.rotation_track_insert_key(hl, minf(float(i) * dt, src.length), Quaternion(q2.x, -q2.y, -q2.z, q2.w).normalized())
	return an


## Custom_Talk: the imported Talk refined (as above), with a slow breath laid over the spine and chest.
func _talk() -> Animation:
	var an := _refine("Talk", 1.0)
	return an
