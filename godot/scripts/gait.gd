extends Node
## How he moves on foot, for a model with the Loco clips (tools/humans/story_cast.py: Karthik): player.gd asks it
## how fast he wants to go and it animates him at that pace.
##   speeds     slow walk 0.9 m/s (Ctrl), walk 1.4, fast walk 1.9 (C), jog 3.6 (Shift), sprint 5.6 (Shift twice
##              and hold, or the stick pressed in); a stick pushed part way is a slow walk. Each its own clip.
##   the tree   one AnimationTree: the five Loco clips in a BlendSpace1D on his speed (m/s), all 1 s cycles with the
##              heels down at the same moments so any two blend in step (sync), under a TimeScale set so a cycle
##              covers exactly the ground he covers (no sliding: the cycle's length, blended as the clips are,
##              over his speed); standing, Idle, and Tired as he gets his breath back; StepTurn while he turns on
##              the spot; a short step back is a walk backwards (the slow clip run in reverse).
##   stamina    100: a sprint spends it (~11 s), a jog barely, walking and standing give it back; low, no sprint;
##              spent, no jog either until he's caught his breath. Ordinary walking is never touched.
##   the ground the city's collision says what's underfoot (city_streamer.gd _shape "surface"), the weather how wet
##              (sim.wet): grass and earth a touch slower, gravel (sand) slow to get going, wet earth is mud (slower,
##              no sprint), wet roads a little careful stopping; stairs (his feet at different steps, foot_ik.gd) no
##              faster than a jog. No slipping. Each footstep is heard on what it lands on, and wet ground splashes.
##   crouched   Z: low (the Crouch and CrouchWalk clips, the hips down as far as the knees fold), a crouched step
##              at most 0.6 m/s, the view lower; up again only where there's room over his head (player.gd).
##   his head   looks a little into a turn, at someone near him now and then, about him when he's standing.
##   his hands  relaxed in every clip (story_cast.py HANDS: each finger its own curl, the thumb along the index, the
##              two hands not mirrored); hand(pose, side) lays a hand's pose over whatever he's doing, only on that
##              hand's bones: the phone in his right hand, papers, a pointing finger, a fist, open, a grip.
##   the camera rises with him onto a step smoothly (the body jumps; the view doesn't); a jog and a sprint widen it a
##              little and draw it back.
## Animation is given up whenever someone else is playing his clips (a scene, sitting, the hospital): the tree goes
## quiet and comes back when he moves again.
const Prof := preload("res://scripts/drive/prof.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const Surfaces := preload("res://scripts/surfaces.gd")

const SLOW := 0.9
const WALK := 1.4
const FAST := 1.9
const JOG := 3.6
const SPRINT := 5.6
## The clips and where they sit on his speed (m/s), and the ground a 1 s cycle covers at time scale 1 (m).
const POINTS := [["LocoSlow", SLOW, 1.03], ["LocoWalk", WALK, 1.41], ["LocoFast", FAST, 1.66], ["LocoJog", JOG, 2.2],
	["LocoSprint", SPRINT, 2.9]]
const CLIPS := ["LocoSlow", "LocoWalk", "LocoFast", "LocoJog", "LocoSprint", "Idle", "Tired", "StepTurn", "HandOpen", "HandPoint",
	"HandPhone", "HandPapers", "HandFist", "HandGrip", "Crouch", "CrouchWalk"]
const CROUCH := 0.6                   # m/s, crouched (CrouchWalk: ~0.34 m a cycle)
const CROUCH_CYCLE := 0.34

var p: CharacterBody3D                # player.gd
var ap: AnimationPlayer
var tree: AnimationTree
var look: Node                        # head_look.gd, his own (acting.gd has another for talk)
var stamina := 100.0
var spent := false                    # run out: no jog until he's caught his breath
var surface := "asphalt"              # what's under his feet
var wet := 0.0
var on_stairs := false
var state := "idle"                   # idle, slow, walk, fast, jog, sprint, back, turn (for the debug and the tests)
var crouched := false                 # low (Z): player.gd shortens him; the Crouch clips here
var _crouch_w := 0.0
var held := false                     # a scene of his own (sitting down): the tree keeps out of it
var backing := false                  # stepping backwards (a short S): facing on, the slow clip reversed
var _back_t := 0.0
var _turn_w := 0.0
var _move_w := 0.0
var _tired_w := 0.0
var _still := 0.0                     # how long he's stood still
var _pocket := false                  # hands in his pockets (IdlePocket), for a while
var _pocket_at := 8.0
var _pocket_w := 0.0
var _shift_was := false
var _shift_t := -9.0                  # when Shift was last pressed (a second press soon after: a sprint)
var _sprint_latch := false
var _surf_t := 0.0
var _cam_lag := 0.0                   # metres the view is still below where his head is (a step up, eased away)
var _last_y := INF
var _fov := 70.0
var _arm := 3.0
var _look_t := 2.0
var _look_at := Vector3.INF
var _foot_y := {"l": 0.0, "r": 0.0}
var _foot_v := {"l": 0.0, "r": 0.0}
var _foot_down := {"l": true, "r": true}
var _steps := {}                      # surface → [AudioStreamWAV...]
var _step_players: Array = []
var _step_i := 0
var _splash: CPUParticles3D
var _sk: Skeleton3D
var _fl := -1
var _fr := -1


## For the model just made (player.gd _init): null if it hasn't the Loco clips (the resort figure, the crowd).
static func attach(player: CharacterBody3D, model: Node3D, anim: AnimationPlayer) -> Node:
	if anim == null:
		return null
	for c in CLIPS:
		if not anim.has_animation(c):
			return null
	var g: Node = load("res://scripts/gait.gd").new()
	g.name = "Gait"
	g.p = player
	g.ap = anim
	player.add_child(g)
	g._build(model)
	return g


func _build(model: Node3D) -> void:
	for c in CLIPS:
		ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	var root := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.sync = true                                     # (the heels of every clip down together)
	move.min_space = 0.0
	move.max_space = 7.0
	for pt in POINTS:
		var an := AnimationNodeAnimation.new()
		an.animation = pt[0]
		move.add_blend_point(an, float(pt[1]))
	root.add_node("move", move)
	root.add_node("cadence", AnimationNodeTimeScale.new())
	root.connect_node("cadence", 0, "move")
	for c in ["Idle", "Tired", "StepTurn"]:
		var an := AnimationNodeAnimation.new()
		an.animation = c
		root.add_node(c.to_lower(), an)
	var idle_in := "idle"
	if ap.has_animation("IdlePocket"):                   # standing a while: the hands into his pockets, now and then
		ap.get_animation("IdlePocket").loop_mode = Animation.LOOP_LINEAR
		var pk := AnimationNodeAnimation.new()
		pk.animation = "IdlePocket"
		root.add_node("idlepocket", pk)
		var pm := AnimationNodeBlend2.new()
		pm.sync = true                                   # (the two stand alike: the weight shifting together)
		root.add_node("pocketmix", pm)
		root.connect_node("pocketmix", 0, "idle")
		root.connect_node("pocketmix", 1, "idlepocket")
		idle_in = "pocketmix"
	root.add_node("rest", AnimationNodeBlend2.new())
	root.connect_node("rest", 0, idle_in)
	root.connect_node("rest", 1, "tired")
	root.add_node("stand", AnimationNodeBlend2.new())
	root.connect_node("stand", 0, "rest")
	root.connect_node("stand", 1, "stepturn")
	root.add_node("out", AnimationNodeBlend2.new())
	root.connect_node("out", 0, "stand")
	root.connect_node("out", 1, "cadence")
	for c in ["Crouch", "CrouchWalk"]:                   # crouched: still, or stepping low (its own pace)
		var an := AnimationNodeAnimation.new()
		an.animation = c
		root.add_node(c.to_lower(), an)
	root.add_node("ccad", AnimationNodeTimeScale.new())
	root.connect_node("ccad", 0, "crouchwalk")
	root.add_node("cmove", AnimationNodeBlend2.new())
	root.connect_node("cmove", 0, "crouch")
	root.connect_node("cmove", 1, "ccad")
	root.add_node("crouchmix", AnimationNodeBlend2.new())
	root.connect_node("crouchmix", 0, "out")
	root.connect_node("crouchmix", 1, "cmove")
	var last := "crouchmix"
	for side in ["l", "r"]:                              # a hand's own pose over whatever he's doing (hand())
		var hn := AnimationNodeAnimation.new()
		hn.animation = "HandOpen"
		root.add_node("handpose_" + side, hn)
		var hb := AnimationNodeBlend2.new()
		hb.filter_enabled = true
		for path in _hand_tracks(side):
			hb.set_filter_path(path, true)
		root.add_node("hand_" + side, hb)
		root.connect_node("hand_" + side, 0, last)
		root.connect_node("hand_" + side, 1, "handpose_" + side)
		last = "hand_" + side
	root.connect_node("output", 0, last)
	tree = AnimationTree.new()
	tree.name = "Gait"
	tree.tree_root = root
	ap.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.active = true
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_sk = sks[0]
		_fl = _sk.find_bone("foot_l")
		_fr = _sk.find_bone("foot_r")
		look = HeadLook.new()
		look.name = "WalkLook"
		_sk.add_child(look)
		var ik := _sk.get_node_or_null("FootPlant")       # (after the feet: the head last)
		if ik:
			_sk.move_child(look, -1)
	_make_steps()
	_splash = CPUParticles3D.new()                       # wet ground: a little water off each step
	_splash.emitting = false
	_splash.one_shot = true
	_splash.amount = 10
	_splash.lifetime = 0.35
	_splash.explosiveness = 1.0
	_splash.direction = Vector3.UP
	_splash.spread = 55.0
	_splash.initial_velocity_min = 0.6
	_splash.initial_velocity_max = 1.3
	_splash.gravity = Vector3(0, -9.8, 0)
	_splash.scale_amount_min = 0.012
	_splash.scale_amount_max = 0.025
	var dm := SphereMesh.new()
	dm.radius = 0.5
	dm.height = 1.0
	dm.radial_segments = 4
	dm.rings = 2
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.7, 0.75, 0.8, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.1
	dm.material = wm
	_splash.mesh = dm
	_splash.top_level = true
	add_child(_splash)
	_actions()


## The tracks of one hand's bones (the wrist and every finger joint) as the clips name them.
func _hand_tracks(side: String) -> Array:
	var out := []
	var an := ap.get_animation("HandOpen")
	for i in an.get_track_count():
		var path := an.track_get_path(i)
		var bone := str(path.get_concatenated_subnames())
		if bone.ends_with("_" + side) and (bone.begins_with("hand") or bone.begins_with("thumb") or bone.begins_with("index")
				or bone.begins_with("middle") or bone.begins_with("ring") or bone.begins_with("pinky")):
			out.append(path)
	return out


var _hand := {"l": "", "r": ""}
var _hand_w := {"l": 0.0, "r": 0.0}


## A hand's pose over his clips: "open", "point", "phone", "papers", "fist", "grip"; "" lets it go (it eases in and
## out over a fifth of a second). side "l", "r" or "both".
func hand(pose: String, side := "r") -> void:
	for sd in (["l", "r"] if side == "both" else [side]):
		if pose != "":
			var clip := "Hand" + pose.capitalize()
			if ap.has_animation(clip):
				((tree.tree_root as AnimationNodeBlendTree).get_node("handpose_" + sd) as AnimationNodeAnimation).animation = clip
				_hand[sd] = pose
		else:
			_hand[sd] = ""


var _held := ""                      # what the game has in his hands now (the phone, a paper)
var hand_test := ""                   # (testing: a pose held on both hands)


## What he's holding, read from the game each frame: the phone up (phone.gd) in his right hand; a paper up to read
## (hands.gd) in both.
func _hands_for_what_he_holds() -> void:
	var city = p.get_parent()
	var now := hand_test
	if now == "" and city and "hands" in city and city.hands and city.hands.has_method("is_busy") and city.hands.is_busy():
		now = "papers"
	if now == "" and city and "phone" in city and city.phone and "is_open" in city.phone and city.phone.is_open:
		now = "phone"
	if now == _held:
		return
	_held = now
	hand("", "both")
	match now:
		"phone", "point":
			hand(now, "r")
		"":
			pass
		_:
			hand(now, "both")


## The keys and the stick: the existing actions kept; slow / fast walk and the sprint added if missing; the left
## stick on the move actions, if nothing has them yet.
func _actions() -> void:
	for pair in [["slow_walk", [KEY_CTRL]], ["fast_walk", [KEY_C]], ["sprint", []], ["crouch", [KEY_Z]]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0], 0.2)
			for kc in pair[1]:
				var ev := InputEventKey.new()
				ev.physical_keycode = kc
				InputMap.action_add_event(pair[0], ev)
	if InputMap.has_action("sprint") and InputMap.action_get_events("sprint").is_empty():
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BUTTON_LEFT_STICK
		InputMap.action_add_event("sprint", jb)
	for m in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0],
			["move_forward", JOY_AXIS_LEFT_Y, -1.0], ["move_back", JOY_AXIS_LEFT_Y, 1.0]]:
		if not InputMap.has_action(m[0]):
			continue
		var has := false
		for e in InputMap.action_get_events(m[0]):
			has = has or e is InputEventJoypadMotion
		if not has:
			var jm := InputEventJoypadMotion.new()
			jm.axis = m[1]
			jm.axis_value = m[2]
			InputMap.action_add_event(m[0], jm)
	if InputMap.has_action("run"):
		var has := false
		for e in InputMap.action_get_events("run"):
			has = has or e is InputEventJoypadButton
		if not has:
			var jr := InputEventJoypadButton.new()
			jr.button_index = JOY_BUTTON_RIGHT_SHOULDER
			InputMap.action_add_event("run", jr)


## How fast he means to go for this input (m/s), before the ground, his breath and the turn; sets `state`.
func want(input: Vector2, keys_run: bool) -> float:
	var n := input.length()
	if n < 0.05:
		state = "idle"
		return 0.0
	if crouched:                                         # (low: no faster than a crouched step)
		state = "crouch"
		return CROUCH * clampf(n, 0.4, 1.0) * _ground_mult()
	var pace := str(p.get("auto_pace"))                  # (testing: a pace held as if from the keys)
	if pace in ["slow", "walk", "fast", "jog", "sprint"]:
		state = pace
		var pv: float = {"slow": SLOW, "walk": WALK, "fast": FAST, "jog": JOG, "sprint": SPRINT}[pace]
		if pv > JOG and (stamina < 15.0 or spent):
			pv = JOG
			state = "jog"
		return pv * _ground_mult()
	var shift := keys_run
	var now := Time.get_ticks_msec() / 1000.0
	if shift and not _shift_was:                         # Shift twice quickly, and held: a sprint
		_sprint_latch = now - _shift_t < 0.4
		_shift_t = now
	if not shift:
		_sprint_latch = false
	_shift_was = shift
	var sprint := _sprint_latch and shift
	if InputMap.has_action("sprint") and Input.is_action_pressed("sprint"):
		sprint = true
	var v := WALK
	state = "walk"
	if Input.is_action_pressed("slow_walk") or n < 0.55:
		v = SLOW
		state = "slow"
	elif sprint:
		v = SPRINT
		state = "sprint"
	elif shift:
		v = JOG
		state = "jog"
	elif Input.is_action_pressed("fast_walk"):
		v = FAST
		state = "fast"
	if v > JOG and (stamina < 15.0 or spent):            # out of breath: no sprint
		v = JOG
		state = "jog"
	if v > FAST and spent:                               # spent: not even a jog, till he's got it back
		v = FAST
		state = "fast"
	var m := _ground_mult()
	if on_stairs and v > JOG * 0.8:
		v = JOG * 0.8
	if surface == "mud" and v > JOG:
		v = JOG
	return v * m


func _ground_mult() -> float:
	return float(Surfaces.foot_of(surface)["pace"])


## Getting going / stopping (m/s²) for this speed on this ground: a walk eases in in half a second, a sprint
## builds over a couple; sand slow to push off, mud slower, a wet road a little careful stopping.
func accel(v: float) -> float:
	var a := 3.5 if v <= FAST else (4.5 if v <= JOG else 5.0)
	return a * float(Surfaces.foot_of(surface)["accel"])


func decel(from: float) -> float:
	var d := 5.0 if from <= FAST else 6.5
	return d * float(Surfaces.foot_of(surface)["stop"])


## Each physics frame from player.gd after it moved: his breath, the ground, the clips, the head, the camera.
func update(delta: float, sp: float, turning: float, down: bool) -> void:
	var _p0 := Time.get_ticks_usec()
	if ap.is_playing() and sp > 0.3 and p.is_physics_processing() and not p.scripted and not down:
		ap.stop()                                        # (he's moving: whatever was played on him is over, the tree again)
	var externally: bool = ap.is_playing() or p.scripted or not p.is_physics_processing() or held
	if externally and tree.active:                       # (someone else is playing his clips: leave them be)
		tree.active = false
	elif not externally and not tree.active:
		tree.active = true
	_breath(delta, sp)
	_surf_t -= delta
	if _surf_t <= 0.0:
		_surf_t = 0.15
		_feel_ground()
	_hands_for_what_he_holds()
	if tree.active:
		_blend(delta, sp, turning, down)
	_head(delta, sp, turning)
	_camera(delta, sp)
	if sp > 0.3 and p.is_on_floor() and not down:
		_footsteps()
	Prof.add("gait", _p0)


func _breath(delta: float, sp: float) -> void:
	if state == "sprint" and sp > JOG:
		stamina -= 9.0 * delta
	elif sp > FAST + 0.3:
		stamina -= 0.8 * delta
	elif sp > 0.3:
		stamina += 6.0 * delta
	else:
		stamina += 10.0 * delta
	stamina = clampf(stamina, 0.0, 100.0)
	if stamina <= 0.5:
		spent = true
	elif spent and stamina > 40.0:
		spent = false


func _blend(delta: float, sp: float, turning: float, down: bool) -> void:
	var moving := 0.0 if down else clampf((sp - 0.08) / 0.45, 0.0, 1.0)
	_move_w = lerpf(_move_w, moving, 1.0 - exp(-delta * 10.0))
	var pos := clampf(sp, SLOW, SPRINT)
	tree.set("parameters/move/blend_position", pos)
	var cyc := _cycle(pos)                               # the ground one cycle covers at this blend (m)
	var scale := maxf(sp, 0.25) / cyc                    # cycles a second: the feet keep pace with the ground
	if backing:
		scale = -scale
	tree.set("parameters/cadence/scale", scale)
	var want_turn := clampf(absf(turning) / 2.0, 0.0, 1.0) if sp < 0.3 and not down else 0.0
	_turn_w = lerpf(_turn_w, want_turn, 1.0 - exp(-delta * 8.0))
	tree.set("parameters/stand/blend_amount", _turn_w)
	var tired := clampf((55.0 - stamina) / 45.0, 0.0, 1.0) if (spent or stamina < 55.0) else 0.0
	_tired_w = lerpf(_tired_w, tired, 1.0 - exp(-delta * 2.0))
	tree.set("parameters/rest/blend_amount", _tired_w)
	if sp < 0.1 and not down and not backing and _tired_w < 0.3:   # standing still: the hands go into his pockets
		_still += delta                                  # after a while, come out again, go back in...
		if _still > _pocket_at:
			_pocket = not _pocket
			_pocket_at = _still + (randf_range(12.0, 25.0) if _pocket else randf_range(15.0, 30.0))
	else:
		_still = 0.0
		_pocket = false
		_pocket_at = 8.0
	_pocket_w = move_toward(_pocket_w, 1.0 if _pocket else 0.0, delta * (1.2 if _pocket else 3.0))
	tree.set("parameters/pocketmix/blend_amount", _pocket_w)
	tree.set("parameters/out/blend_amount", _move_w)
	_crouch_w = move_toward(_crouch_w, 1.0 if crouched else 0.0, delta * 3.5)   # (down or up in about a third of a second)
	tree.set("parameters/crouchmix/blend_amount", _crouch_w)
	tree.set("parameters/cmove/blend_amount", _move_w)
	tree.set("parameters/ccad/scale", maxf(sp, 0.2) / CROUCH_CYCLE)
	for sd in ["l", "r"]:
		_hand_w[sd] = move_toward(_hand_w[sd], 1.0 if _hand[sd] != "" else 0.0, delta * 5.0)
		tree.set("parameters/hand_%s/blend_amount" % sd, _hand_w[sd])
	if sp < 0.3 and absf(turning) > 0.8:
		state = "turn"
	if backing:
		state = "back"


## The cycle's ground at a blend position, interpolated between the clips as their weights are.
func _cycle(pos: float) -> float:
	for i in range(POINTS.size() - 1):
		var a: Array = POINTS[i]
		var b: Array = POINTS[i + 1]
		if pos <= float(b[1]):
			var t := (pos - float(a[1])) / (float(b[1]) - float(a[1]))
			return lerpf(float(a[2]), float(b[2]), clampf(t, 0.0, 1.0))
	return float(POINTS[-1][2])


## What's under his feet: the collision's "surface", the weather's wet; the steps his feet are on (foot IK).
func _feel_ground() -> void:
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.4, p.global_position + Vector3.DOWN * 0.6)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var kind := "concrete"
	if not hit.is_empty() and hit["collider"] is CollisionObject3D:
		var co := hit["collider"] as CollisionObject3D
		if not co.get_shape_owners().is_empty():
			var oid := co.shape_find_owner(int(hit["shape"]))
			var sn = co.shape_owner_get_owner(oid) if oid >= 0 else null
			if sn is Node and (sn as Node).has_meta("surface"):
				kind = str((sn as Node).get_meta("surface"))
	var city = p.get_parent()
	wet = 0.0
	if city and "fines" in city and city.fines and "sim" in city.fines and "wet" in city.fines.sim:
		wet = float(city.fines.sim.wet)
	if city and "indoors" in city and city.indoors:
		wet = 0.0
		kind = "concrete"
	surface = Surfaces.foot(kind, wet)                    # (scripts/surfaces.gd: the table tyres read too)
	var f = p.get("feet")
	on_stairs = f != null and is_instance_valid(f) and absf(float(f._ground["l"]) - float(f._ground["r"])) > 0.07


## His head: into a turn as he walks, at someone near when he's at a walk or standing, about him now and then.
func _head(delta: float, sp: float, turning: float) -> void:
	if look == null:
		return
	_look_t -= delta
	var fwd: Vector3 = (p.model as Node3D).global_basis.z
	var head: Vector3 = p.global_position + Vector3.UP * 1.6
	if absf(turning) > 0.6 and sp > 0.2:               # (into the turn: the way he's going, ahead of the body)
		var a := clampf(turning * 0.25, -0.6, 0.6)
		look.target = head + fwd.rotated(Vector3.UP, a) * 4.0
		look.weight = 0.7
		return
	if sp > FAST + 0.3:                                  # (running: eyes ahead)
		look.weight = 0.0
		_look_at = Vector3.INF
		return
	if _look_t <= 0.0:
		_look_t = randf_range(2.5, 6.0)
		_look_at = Vector3.INF
		var near := _someone_near(head, fwd)
		if near != Vector3.INF and randf() < 0.7:
			_look_at = near + Vector3.UP * 1.55
		elif sp < 0.3 and randf() < 0.5:                 # (standing: a look about)
			_look_at = head + fwd.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * 5.0 + Vector3.UP * randf_range(-0.4, 0.3)
	look.target = _look_at
	look.weight = 0.65 if _look_at != Vector3.INF else 0.0


## Someone within 5 m ahead of him (the citizens' near tier, the story's cast standing about).
func _someone_near(head: Vector3, fwd: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := 5.0
	var city = p.get_parent()
	var ppl: Array = []
	if city and "citizens" in city and city.citizens and city.citizens.has_method("near_nodes"):
		ppl = city.citizens.near_nodes()
	if city and "story" in city and city.story and "cast" in city.story:
		for k in city.story.cast:
			var n = city.story.cast[k]
			if is_instance_valid(n) and (n as Node3D).visible:
				ppl.append(n)
	for n in ppl:
		var q: Vector3 = (n as Node3D).global_position
		var d := Vector3(q.x - head.x, 0.0, q.z - head.z)
		if d.length() < bd and d.length() > 0.5 and fwd.dot(d.normalized()) > 0.2:
			bd = d.length()
			best = q
	return best


## The view: up a step smoothly; a jog and a sprint draw it back and widen it a touch.
func _camera(delta: float, sp: float) -> void:
	var y := p.global_position.y
	if _last_y != INF and p.is_on_floor():
		var dy := y - _last_y
		if absf(dy) > 0.025 and absf(dy) < 0.5:          # (a step, a kerb: the body jumped; the eyes needn't)
			_cam_lag = clampf(_cam_lag + dy, -0.4, 0.4)
	_last_y = y
	_cam_lag = lerpf(_cam_lag, 0.0, 1.0 - exp(-delta * 7.0))
	if p.head:
		p.head.position.y = lerpf(1.62, 1.05, _crouch_w) - _cam_lag
	var want_fov := 70.0 + (6.0 if sp > JOG + 0.5 else (2.5 if sp > FAST + 0.4 else 0.0))
	var want_arm := 3.0 + (0.35 if sp > JOG + 0.5 else (0.15 if sp > FAST + 0.4 else 0.0))
	_fov = lerpf(_fov, want_fov, 1.0 - exp(-delta * 2.5))
	_arm = lerpf(_arm, want_arm, 1.0 - exp(-delta * 2.5))
	if p.camera and p.third_person:
		p.camera.fov = _fov
		p.arm.spring_length = _arm


# ---- footsteps ----
## A foot coming down (its height over his feet stops falling, low): the step's sound on what it's on, a splash
## if wet.
func _footsteps() -> void:
	if _sk == null or _fl < 0:
		return
	var base := p.global_position.y
	for s in ["l", "r"]:
		var b := _fl if s == "l" else _fr
		var y := (_sk.global_transform * _sk.get_bone_global_pose(b).origin).y - base
		var v: float = y - _foot_y[s]
		if not _foot_down[s] and _foot_v[s] < -0.002 and v > -0.001 and y < 0.16:
			_foot_down[s] = true
			_step(_sk.global_transform * _sk.get_bone_global_pose(b).origin)
		elif y > 0.13:
			_foot_down[s] = false
		_foot_v[s] = v
		_foot_y[s] = y


func _step(at: Vector3) -> void:
	var key := surface if _steps.has(surface) else "concrete"
	var bank: Array = _steps[key]
	var pl: AudioStreamPlayer3D = _step_players[_step_i % _step_players.size()]
	_step_i += 1
	pl.stream = bank[randi() % bank.size()]
	pl.pitch_scale = randf_range(0.9, 1.1)
	var sp := Vector2(p.velocity.x, p.velocity.z).length()
	pl.volume_db = -14.0 + clampf(sp * 2.0, 0.0, 9.0)
	pl.global_position = at
	pl.play()
	if surface in ["wet_road", "mud"]:
		_splash.global_position = at + Vector3.UP * 0.03
		_splash.restart()


## The sounds, made here (no recordings): noise shaped as each ground sounds underfoot: a hard tap on concrete and
## asphalt, a soft brush on grass, a dull pat on earth, many small grains on sand and gravel, a wet slap on a wet
## road, a heavy squelch in mud. Four of each.
func _make_steps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for kind in ["concrete", "asphalt", "grass", "earth", "sand", "wet_road", "mud"]:
		var bank: Array = []
		for k in 4:
			bank.append(_synth(kind, rng))
		_steps[kind] = bank
	for i in 4:
		var pl := AudioStreamPlayer3D.new()
		pl.unit_size = 3.0
		pl.max_distance = 25.0
		pl.top_level = true
		add_child(pl)
		_step_players.append(pl)


func _synth(kind: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var rate := 22050
	var dur: float = {"concrete": 0.09, "asphalt": 0.1, "grass": 0.16, "earth": 0.11, "sand": 0.2, "wet_road": 0.18, "mud": 0.24}[kind]
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var cut: float = {"concrete": 0.55, "asphalt": 0.4, "grass": 0.25, "earth": 0.12, "sand": 0.5, "wet_road": 0.6, "mud": 0.06}[kind]
	var thump: float = {"concrete": 0.5, "asphalt": 0.45, "grass": 0.15, "earth": 0.5, "sand": 0.2, "wet_road": 0.35, "mud": 0.7}[kind]
	var f0: float = {"concrete": 140.0, "asphalt": 110.0, "grass": 90.0, "earth": 80.0, "sand": 90.0, "wet_road": 120.0, "mud": 60.0}[kind] * rng.randf_range(0.9, 1.1)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * {"grass": 22.0, "sand": 14.0, "wet_road": 18.0, "mud": 10.0}.get(kind, 45.0))
		var x := rng.randf_range(-1.0, 1.0)
		if kind == "sand" and rng.randf() > 0.12:          # (grains: sparse crackle)
			x *= 0.15
		lp += (x - lp) * cut
		lp2 += (lp - lp2) * cut
		var noise := lp2 if kind in ["earth", "mud"] else lp
		var s := noise * env * 0.9 + sin(TAU * f0 * t) * exp(-t * 60.0) * thump
		if kind == "wet_road" and t > 0.02:                # (the water off the sole, a moment later)
			s += rng.randf_range(-1.0, 1.0) * exp(-(t - 0.02) * 25.0) * 0.35
		var v := int(clampf(s, -1.0, 1.0) * 26000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## (development: --movedebug and the tests)
func debug_data() -> Dictionary:
	return {"state": state, "stamina": snappedf(stamina, 0.1), "surface": surface, "stairs": on_stairs,
		"blend": snappedf(float(tree.get("parameters/move/blend_position")), 0.01),
		"cadence": snappedf(float(tree.get("parameters/cadence/scale")), 0.01), "tree": tree.active}
