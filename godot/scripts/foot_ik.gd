extends SkeletonModifier3D
## His feet on the ground they're over: on a stair, a kerb or a slope, each foot finds the step under it and the
## hips come down so the lower foot reaches its step, the knee of the higher one bending (TwoBoneIK3D, one setting a
## leg). On flat ground it changes nothing: each foot's target is where the clip already put it.
## Runs as a modifier before the leg IK, under the skeleton: it reads the clip's pose (the animation is applied
## before modifiers), rays down under each foot, lowers the pelvis and sets the IK's targets and knee poles.
##   setup(player)   made by player.gd for its model (the cast's bones: pelvis, thigh/calf/foot_l/r)
## Off in the air, running (a runner's feet barely touch) and when a scene moves him.
## Foot locking (walking): a foot that comes down stays where it landed while it carries him (the clip's foot,
## which drifts a little as the leg swings round the hip, held to that spot; the knee bends to suit), let go as
## its heel lifts, or if holding it would stretch the leg. No sliding, starting, stopping, turning.
const SIDES := ["l", "r"]
const MAX_DROP := 0.32               # the hips come down at most this much (a tall step, half a stair more)
const REACH := 0.55                  # rays look this far above and below his feet

var player: CharacterBody3D
var ik: TwoBoneIK3D
var _targets := {}
var _poles := {}
var _drop := 0.0                     # the hips lowered, metres (smoothed)
var _w := 0.0                        # how much the IK has his legs (smoothed 0..1)
var _ground := {"l": 0.0, "r": 0.0}  # each foot's ground relative to his feet, metres (smoothed)
var _pelvis := -1
var _bones := {}
var debug := ""
var lock_on := true                  # (testing: --nofootlock, to compare)
var _lock := {"l": Vector3.INF, "r": Vector3.INF}   # where each foot landed (world), or INF: not held
var _lock_w := {"l": 0.0, "r": 0.0}
var _ankle_low := 0.12               # the lowest his ankles come over the ground in the clips (m), learned


## Under the model's skeleton: this modifier, then the leg IK. False if the model hasn't the legs' bones.
static func attach(p: CharacterBody3D, model: Node3D) -> Node:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk := sks[0] as Skeleton3D
	for b in ["pelvis", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
		if sk.find_bone(b) < 0:
			return null
	var me: SkeletonModifier3D = load("res://scripts/foot_ik.gd").new()
	me.name = "FootPlant"
	me.player = p
	sk.add_child(me)
	me._setup(sk)
	return me


func _setup(sk: Skeleton3D) -> void:
	_pelvis = sk.find_bone("pelvis")
	ik = TwoBoneIK3D.new()
	ik.name = "LegIK"
	ik.setting_count = 2
	sk.add_child(ik)
	for i in 2:
		var s: String = SIDES[i]
		_bones[s] = [sk.find_bone("thigh_" + s), sk.find_bone("calf_" + s), sk.find_bone("foot_" + s)]
		ik.set_root_bone_name(i, "thigh_" + s)
		ik.set_middle_bone_name(i, "calf_" + s)
		ik.set_end_bone_name(i, "foot_" + s)
		var t := Node3D.new()
		t.name = "Foot_" + s
		player.add_child(t)
		t.top_level = true
		_targets[s] = t
		var pl := Node3D.new()
		pl.name = "Knee_" + s
		player.add_child(pl)
		pl.top_level = true
		_poles[s] = pl
		ik.set_target_node(i, ik.get_path_to(t))
		ik.set_pole_node(i, ik.get_path_to(pl))
	ik.influence = 0.0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or player == null:
		return
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	var on: bool = player.is_on_floor() and sp < 2.6 and not player.get("scripted") and player.get("_down") == 0.0
	if lock_on and "--nofootlock" in OS.get_cmdline_user_args():
		lock_on = false
	_w = move_toward(_w, 1.0 if on else 0.0, delta * 4.0)
	var xf := sk.global_transform
	var base := player.global_position.y + (player.get("model") as Node3D).position.y
	var space := player.get_world_3d().direct_space_state
	var feet := {}
	for s in SIDES:
		var f: Vector3 = xf * sk.get_bone_global_pose(_bones[s][2]).origin
		feet[s] = f
		var g := 0.0
		if _w > 0.0:
			var q := PhysicsRayQueryParameters3D.create(Vector3(f.x, base + REACH, f.z), Vector3(f.x, base - REACH, f.z))
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
				g = clampf(float(hit["position"].y) - base, -REACH, REACH)
		_ground[s] = lerpf(_ground[s], g, 1.0 - exp(-delta * 18.0))
	var want := clampf(-minf(_ground["l"], _ground["r"]), 0.0, MAX_DROP) * _w
	_drop = lerpf(_drop, want, 1.0 - exp(-delta * 10.0))
	if _drop > 0.001:                                    # the hips down: in the pelvis's parent's space
		var par := sk.get_bone_parent(_pelvis)
		var pb := (xf.basis * (sk.get_bone_global_pose(par).basis if par >= 0 else Basis())).inverse()
		var pose := sk.get_bone_pose_position(_pelvis)
		sk.set_bone_pose_position(_pelvis, pose + pb * Vector3(0, -_drop, 0))
	var fwd := (player.get("model") as Node3D).global_basis.z.normalized()
	var locking := false
	for s in SIDES:
		var f: Vector3 = feet[s]
		var t := f + Vector3(0, _ground[s], 0)          # the clip's lift kept, over this foot's own ground
		var lift: float = f.y - base                    # (the clip's ankle over his feet' level)
		if sp < 0.05 and _w > 0.9:
			_ankle_low = lerpf(_ankle_low, minf(_ankle_low, lift), 0.5)   # (standing: the ankle at rest)
		var down := lock_on and _w > 0.5 and sp > 0.1 and lift < _ankle_low + 0.025
		if down and _lock[s] == Vector3.INF:
			_lock[s] = t                                 # (it lands: here)
		if not down:
			_lock[s] = Vector3.INF
		var held: Vector3 = _lock[s]
		if held != Vector3.INF and Vector2(held.x - t.x, held.z - t.z).length() > 0.3:
			_lock[s] = Vector3.INF                        # (holding it would stretch the leg: let go)
			held = Vector3.INF
		_lock_w[s] = move_toward(float(_lock_w[s]), 1.0 if held != Vector3.INF else 0.0, delta * (30.0 if held != Vector3.INF else 12.0))
		if held != Vector3.INF:
			t = Vector3(held.x, t.y, held.z).lerp(t, 1.0 - float(_lock_w[s]))
			locking = true
		(_targets[s] as Node3D).global_position = t
		var knee: Vector3 = xf * sk.get_bone_global_pose(_bones[s][1]).origin
		(_poles[s] as Node3D).global_position = knee + fwd * 0.6
	ik.influence = _w if (_drop > 0.005 or absf(_ground["l"]) > 0.01 or absf(_ground["r"]) > 0.01 or locking) else 0.0
	debug = "feet %+.2f %+.2f  hips -%.2f  ik %.2f" % [_ground["l"], _ground["r"], _drop, ik.influence]
