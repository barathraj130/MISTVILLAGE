extends Node
## His hand going to something (OPEN_WORLD_PLAN phase 5 "a hand on a door"): the arm nearer it reaches out with a
## two-bone IK (arm_ik.gd: shoulder, elbow, wrist) to the point, the elbow down and out as an arm goes, the hand in
## a pose for it (gait.gd hand: open on a door or a drawer's pull, a point at a switch); held a moment, then the arm
## eases back into whatever he's doing. The clips are untouched: the IK lies over them and its influence eases in
## and out.
##   attach(player, skeleton)   made by player.gd beside the foot IK
##   go(point, pose, hold)      await it: it returns when the hand is there (the door opens then)

var p: CharacterBody3D
var sk: Skeleton3D
const ArmIK := preload("res://scripts/arm_ik.gd")

var ik: SkeletonModifier3D           # arm_ik.gd
var _side := "r"
var _w := 0.0
var _busy := 0


static func attach(player: CharacterBody3D, skel: Skeleton3D) -> Node:
	for b in ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]:
		if skel.find_bone(b) < 0:
			return null
	var r: Node = load("res://scripts/reach.gd").new()
	r.name = "Reach"
	r.p = player
	r.sk = skel
	player.add_child(r)
	r._build()
	return r


func _build() -> void:
	ik = ArmIK.new()
	ik.name = "ArmIK"
	sk.add_child(ik)                                     # (after the foot IK and the head: last on the stack)


func _set_side(s: String) -> void:
	_side = s
	ik.side = s


## The hand to `point` (the world): the arm on its side, the hand in `pose`; returns once it's there; `hold` seconds
## later it lets go.
func go(point: Vector3, pose := "open", hold := 0.35) -> void:
	var model: Node3D = p.get("model")
	if model == null:
		return
	_busy += 1
	var me := _busy
	var right_dir: Vector3 = -model.global_basis.x.normalized()  # (the model faces +Z: its right is −X)
	var side := "r" if (point - p.global_position).dot(right_dir) >= 0.0 else "l"
	_set_side(side)
	var shoulder: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("upperarm_" + side)).origin
	var elbow: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("lowerarm_" + side)).origin
	var wrist: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_" + side)).origin
	var arm_len := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var to := point - shoulder
	if to.length() > arm_len * 0.96:                     # (out of reach: as far as the arm goes, toward it)
		point = shoulder + to.normalized() * arm_len * 0.96
	ik.target = point
	var outward: Vector3 = right_dir if side == "r" else -right_dir
	ik.pole = shoulder + Vector3.DOWN * 0.5 + outward * 0.4 - model.global_basis.z * 0.2
	var gait = p.get("gait")
	if gait:
		gait.hand(pose, side)
	var tw := create_tween()
	tw.tween_method(func(v: float): _w = v; ik.weight = v, _w, 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	_let_go.call_deferred(me, hold, side)


func _let_go(me: int, hold: float, side: String) -> void:
	await get_tree().create_timer(hold).timeout
	if me != _busy:                                      # (another reach since: it has the arm)
		return
	var gait = p.get("gait")
	if gait:
		gait.hand("", side)
	var tw := create_tween()
	tw.tween_method(func(v: float): _w = v; ik.weight = v, _w, 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
