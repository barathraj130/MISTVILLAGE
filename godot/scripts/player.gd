extends CharacterBody3D
## You on foot: one of our own Blender-made people (tools/people.py) with idle / walk / run
## animations, seen from a third-person camera on a spring arm (it pulls in rather than going
## through walls). V switches to first person. The mouse turns the view; the body turns to face
## the way you walk, as a person does: it gets going and slows down over a few steps, turns at a
## person's pace (slowing to turn sharply, leaning a little into a curve), stands facing where it
## stopped while you look about, and rises onto a step rather than jumping up it.
## His body (OPEN_WORLD_PLAN phase 5): his feet find the step each is over (foot_ik.gd: the hips come down, the
## higher knee bends); knocked by someone running into him, or landing from a height, he stumbles a few steps to
## catch himself, or, knocked harder, goes over: a pendulum from his feet (the push starts it, gravity finishes
## it), down on the ground a moment, then up again. knock(push) is how anything pushes him (people, the gang).
##   --falltest  testing: a light push, a hard one and a drop, pictures of each (user://fall_*.jpg)
##   --gaittest  testing: every pace, a stop, turns of 90° and 180°, a circle, a step back, getting his breath;
##               how far his planted foot slides (m/s, should be near 0) and a picture of each (user://gait_*.jpg)
##   --standtest=TAG testing: standing, seen from the front, back, left, right and the play camera, close on the
##               legs and whole (user://stand_<TAG>_*.jpg: a before and an after)
##   --stairtest testing: in a room with a stair (the story's climb: --storyfrom=138), up it from Mark_cut to
##               Mark_landing, his feet's IK printed, pictures from the side (user://stair_*.jpg)
const Prof := preload("res://scripts/drive/prof.gd")
const Settings := preload("res://scripts/settings.gd")

const STEP_HEIGHT := 0.6           # stone steps 15–25 cm; a footpath stands up to 0.57 over the road: a big step, but a step

@export var walk_speed := 1.4       # a person's pace: the Walk clip covers 1.18–1.5 m a cycle, so feet don't slide
@export var run_speed := 4.2        # a run: the Run clip covers 3.9–5.5 m
@export var jump_velocity := 4.2
@export var mouse_sensitivity := 0.0025

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var active := false
var head: Node3D
var camera: Camera3D
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var _pitch := 0.0
var third_person := true
var arm: SpringArm3D
var model: Node3D
var anim: AnimationPlayer
var _model_yaw := PI                # the body's facing in the world (radians, as rotation.y)
var _lean := 0.0
var _step_drop := 0.0               # a step just climbed: the body still catching up, metres
var _last_pos := Vector3.INF       # (a jump of metres in a frame is a teleport: the body faces as it was set)
const ACCEL := 3.5                  # m/s² getting going (walking pace in about half a second)
const DECEL := 5.0                  # m/s² coming to a stop
const TURN_RATE := 7.0              # how quickly the body swings round to the way you go, walking…
const TURN_RATE_RUN := 3.5          # …and running (momentum: no about-turn on the spot at a run)
var auto_input := Vector2.INF       # (testing: a move held as if from the keys, tests/movement_lab.gd)
var auto_run := false
var auto_pace := ""                 # (testing: slow, walk, fast, jog, sprint as if from the keys: gait.gd)
var debug_label: Label              # (development: --movedebug shows how he moves)
const AVATAR := "res://assets/people/person_man_shirt.glb"
static var avatar := ""            # who you are on foot, when not the default (the story: Karthik himself)
var avatar_run_stride := false     # a story cast model: its Run covers ~3.9 m/s at speed 1
var scripted := false              # a scene moves him (brush3d.gd): his clips and facing are its, not the walk's
var combat = null                   # in a fight (combat/player_combat.gd): his moves, facing and clips are its
const FootIK := preload("res://scripts/foot_ik.gd")
const Gait := preload("res://scripts/gait.gd")
const Reach := preload("res://scripts/reach.gd")
var hand_reach: Node                # reach.gd: his hand to a door, a drawer, a switch
var feet: Node                      # foot_ik.gd, on the model's skeleton
var gait: Node                      # gait.gd: his speeds, the AnimationTree, breath, ground, head, camera (Karthik)
var _want_yaw := INF                # where the keys say to go (the body's yaw), INF with none
var _turn_rate := 0.0               # how fast the body is turning (rad/s), for the clips and the head
var _sp_was := 0.0
var _accel := 0.0                   # along the way he faces, m/s² (smoothed): he leans into a start, back into a stop
var _back_t := 0.0                  # how long S alone has been held (a short one: a step or two backwards)
var _flinch := 0.0                  # walked into something: a moment's lean back
const TURN_IN_PLACE := 3.6          # rad/s stepping round on the spot (a half turn in under a second)
var _down := 0.0                    # 0 on his feet; 1 going over; 2 on the ground; 3 getting up
var _theta := 0.0                   # how far over he is (radians from upright)
var _omega := 0.0
var _axis := Vector3.RIGHT          # what he goes over about (level, across the push)
var _down_t := 0.0
var _stumble := 0.0                 # seconds still catching himself
var _stumble_dir := Vector3.ZERO
var _fall_vy := 0.0                 # how fast he was falling, the frame before he landed
const COM := 0.95                   # his centre of mass over his feet, metres (the pendulum's length)
signal fell                         # (on the ground: someone may come and help)


var _shape: CollisionShape3D
var _capsule: CapsuleShape3D


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	_shape = shape
	_capsule = capsule
	capsule.radius = 0.25                                # (a person's shoulders; 0.3 jammed on a stair's 30 cm tread)
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	arm = SpringArm3D.new()
	arm.spring_length = 3.0
	arm.margin = 0.2
	arm.position = Vector3(0.35, 0.05, 0)              # over the right shoulder
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	arm.shape = probe
	arm.add_excluded_object(get_rid())
	head.add_child(arm)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 40000.0
	camera.fov = 70.0
	arm.add_child(camera)
	var who := avatar if avatar != "" else AVATAR
	avatar_run_stride = who.contains("/story_")          # the story cast's own Run (tools/humans/story_cast.py)
	if ResourceLoader.exists(who):
		model = (load(who) as PackedScene).instantiate() as Node3D
		add_child(model)
		anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for a in ["Idle", "Walk", "Run"]:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		feet = FootIK.attach(self, model)
		gait = Gait.attach(self, model, anim)
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			hand_reach = Reach.attach(self, sks[0])
	_set_view(true)
	if "--movedebug" in OS.get_cmdline_user_args():
		var layer := CanvasLayer.new()
		layer.layer = 30
		add_child(layer)
		debug_label = Label.new()
		debug_label.position = Vector2(16, 120)
		debug_label.add_theme_font_size_override("font_size", 16)
		debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
		debug_label.add_theme_constant_override("outline_size", 4)
		layer.add_child(debug_label)
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = STEP_HEIGHT + 0.05


func spawn_at(pos: Vector3, look_at_point: Vector3) -> void:
	spawn_point = pos + Vector3.UP * 0.3
	var d := look_at_point - pos
	spawn_yaw = atan2(-d.x, -d.z)
	_respawn()


func _respawn() -> void:
	global_position = spawn_point
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	_model_yaw = spawn_yaw + PI                         # (the model faces +Z, the body -Z)


func _set_view(third: bool) -> void:
	third_person = third
	arm.spring_length = 3.0 if third else 0.0
	arm.position = Vector3(0.35, 0.05, 0) if third else Vector3.ZERO
	if model:
		model.visible = third


func activate() -> void:
	if not active and "--stairtest" in OS.get_cmdline_user_args() and not has_meta("stairtest"):
		set_meta("stairtest", true)
		_stair_test.call_deferred()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--standtest=") and not active and not has_meta("standtest"):
			set_meta("standtest", true)
			_stand_test.call_deferred(a.get_slice("=", 1))
	if not active and "--sittest" in OS.get_cmdline_user_args() and not has_meta("sittest"):
		set_meta("sittest", true)
		_sit_test.call_deferred()
	if not active and "--gaittest" in OS.get_cmdline_user_args() and not has_meta("gaittest"):
		set_meta("gaittest", true)
		_gait_test.call_deferred()
	if not active and "--falltest" in OS.get_cmdline_user_args() and not has_meta("falltest"):
		set_meta("falltest", true)
		_fall_test.call_deferred()
	active = true
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func deactivate() -> void:
	active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity * Settings.look()
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity * Settings.look(), -1.45, 1.45)
		head.rotation.x = _pitch
	elif InputMap.has_action("camera_view") and event.is_action_pressed("camera_view"):
		_set_view(not third_person)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Prof.add("walker_phys", _p0)


func _physics_process_timed(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		_fall_vy = velocity.y
	if gait and active and _down == 0.0 and InputMap.has_action("crouch") and Input.is_action_just_pressed("crouch"):
		set_crouch(not gait.crouched)
	if _down > 0.0:
		_downed(delta)
	elif active and combat != null and combat.engaged:  # (a fight: the keys are its; the body still slides on walls)
		var cin := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if auto_input == Vector2.INF else auto_input
		var cdir := (transform.basis * Vector3(cin.x, 0.0, cin.y))
		cdir.y = 0.0
		var cv: Vector3 = combat.steer(cdir.normalized() * minf(cin.length(), 1.0), delta)
		velocity.x = cv.x
		velocity.z = cv.z
	elif active:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if auto_input == Vector2.INF else auto_input
		if auto_input == Vector2.INF:                    # a controller's right stick looks about, as the mouse does
			var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
			if look.length() > 0.15:
				rotation.y -= look.x * 2.6 * delta * Settings.look()
				_pitch = clampf(_pitch - look.y * 1.8 * delta * Settings.look(), -1.45, 1.45)
				head.rotation.x = _pitch
		var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		var running := Input.is_action_pressed("run") if auto_input == Vector2.INF else auto_run
		var speed := (run_speed if running else walk_speed) * minf(input.length(), 1.0)   # (a stick half pushed: slower)
		if gait:
			speed = gait.want(input, running)
			var back_only := input.y > 0.5 and absf(input.x) < 0.35 and not running
			_back_t = _back_t + delta if back_only else 0.0
			gait.backing = back_only and _back_t < 1.1 and Vector2(velocity.x, velocity.z).length() < 1.2
			if gait.backing:                             # (a step or two back, facing on; held, he turns round)
				speed = minf(speed, 0.8)
		_want_yaw = atan2(dir.x, dir.z) if dir != Vector3.ZERO else INF
		if gait and gait.backing:
			_want_yaw = INF
		if dir != Vector3.ZERO and model and not (gait and gait.backing):   # a sharp turn: he slows to make it
			var off := absf(angle_difference(_model_yaw, atan2(dir.x, dir.z)))
			speed *= clampf(1.0 - (off - 0.6) / 2.0, 0.35, 1.0)
			if gait:
				var have_sp := Vector2(velocity.x, velocity.z).length()
				if have_sp < 0.35 and off > 1.0:            # standing: he turns on the spot first, then sets off
					speed = 0.0
				elif off > 0.7:                          # moving: on the way he faces, slowing, as the body comes
					var fwd := Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))   #  round (no sideways slide)
					dir = (fwd * cos(minf(off, 1.5)) + dir * 0.35).normalized()
					speed *= clampf(cos(off * 0.8), 0.2, 1.0)
		if dir != Vector3.ZERO and is_on_floor():       # a slope: slower up it, careful down a steep one
			var grade := -dir.dot(get_floor_normal())    # (sin of the slope, + uphill)
			if grade > 0.0:
				speed *= 1.0 - clampf(grade * 0.5, 0.0, 0.3)
			else:
				speed *= 1.0 - clampf((-grade - 0.2) * 0.8, 0.0, 0.2)
		if _stumble > 0.0:                               # catching himself: carried the push's way, your keys half his
			_stumble -= delta
			dir = (dir * 0.4 + _stumble_dir * clampf(_stumble, 0.0, 0.6) * 1.6).normalized()
			speed = maxf(speed, walk_speed * 1.3)
		var want := Vector2(dir.x, dir.z) * speed
		var have := Vector2(velocity.x, velocity.z)
		var rate := (ACCEL if want.length() > have.length() else DECEL) * (1.0 if is_on_floor() else 0.3)
		if gait:
			rate = (gait.accel(want.length()) if want.length() > have.length() else gait.decel(have.length())) \
				* (1.0 if is_on_floor() else 0.3)
		have = have.move_toward(want, rate * delta)
		velocity.x = have.x
		velocity.z = have.y
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if active:                                          # up a step: the body catches up with the capsule
		_step_drop = minf(_step_drop + _try_step_up(delta), 0.4)
	var was_air := not is_on_floor()
	var pre := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if gait and _down == 0.0 and pre.length() > 1.0:     # into a wall or a post: a flinch; at a run, a stumble back
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var nrm := c.get_normal()
			if absf(nrm.y) < 0.35 and pre.normalized().dot(Vector3(nrm.x, 0.0, nrm.z).normalized()) < -0.8:
				if pre.length() > 3.0:
					knock(Vector3(nrm.x, 0.0, nrm.z).normalized() * 1.4)
				_flinch = 0.35
				break
	if was_air and is_on_floor() and _down == 0.0:   # landed: from a height, it shows
		var v := -_fall_vy
		var fwd := Vector3(velocity.x, 0.0, velocity.z)
		if fwd.length() < 0.3:
			fwd = Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))
		if v > 8.5:                                      # (2.5 m or more: he goes down)
			knock(fwd.normalized() * (v * 0.35), true)
		elif v > 6.0:                                    # (a metre and a half: he stumbles)
			knock(fwd.normalized() * 1.6)
		_fall_vy = 0.0
	if global_position.y < -400.0:         # fell off the world
		_respawn()
	_animate(delta)


func _animate(delta: float) -> void:
	if model == null or scripted:
		return
	if combat != null and combat.engaged:                # (a fight: the clips are its; he faces the way it says)
		model.global_rotation = Vector3(0.0, _model_yaw, 0.0)
		model.position.y = 0.0
		_last_pos = global_position
		return
	if _last_pos.distance_to(global_position) > 3.0:
		_model_yaw = rotation.y + PI
		_step_drop = 0.0
	_last_pos = global_position
	var flat := Vector3(velocity.x, 0, velocity.z)
	var sp := flat.length()
	var turned := 0.0
	if gait and gait.backing:                            # (stepping back: he faces the way the view does)
		var was_b := _model_yaw
		_model_yaw = lerp_angle(_model_yaw, rotation.y + PI, 1.0 - exp(-delta * 6.0))
		turned = angle_difference(was_b, _model_yaw) / maxf(delta, 0.001)
	elif gait and sp <= 0.35 and _want_yaw != INF and _down == 0.0:   # on the spot: stepping round at a person's rate
		var was_t := _model_yaw
		var d := angle_difference(_model_yaw, _want_yaw)
		_model_yaw += clampf(d, -TURN_IN_PLACE * delta, TURN_IN_PLACE * delta)
		turned = angle_difference(was_t, _model_yaw) / maxf(delta, 0.001)
	elif sp > 0.2:
		# face the way you're walking (the model faces +Z), turning at a person's pace; standing, he stays put
		var was := _model_yaw
		var rate := lerpf(TURN_RATE, TURN_RATE_RUN, clampf((sp - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0))
		_model_yaw = lerp_angle(_model_yaw, atan2(flat.x, flat.z), 1.0 - exp(-delta * rate))
		turned = angle_difference(was, _model_yaw) / maxf(delta, 0.001)
	_lean = lerpf(_lean, clampf(-turned * sp * 0.012, -0.12, 0.12), 1.0 - exp(-delta * 6.0))   # into the curve
	_turn_rate = lerpf(_turn_rate, turned, 1.0 - exp(-delta * 10.0))
	var a_long := (sp - _sp_was) / maxf(delta, 0.001)    # speeding up (+) or slowing (−), m/s²
	_sp_was = sp
	_accel = lerpf(_accel, a_long, 1.0 - exp(-delta * 6.0))
	_flinch = maxf(_flinch - delta, 0.0)
	model.global_rotation = Vector3(0.0, _model_yaw, 0.0)
	model.rotate_object_local(Vector3.FORWARD, _lean)
	if gait:                                            # his weight: forward into a start, back into a stop, back from a wall
		var pitch := clampf(_accel * 0.022, -0.13, 0.09) - _flinch * 0.35
		model.rotate_object_local(Vector3.RIGHT, pitch)
	if _stumble > 0.0:                                  # (pitched the push's way, arms of the walk catching up)
		var k := clampf(_stumble / 0.7, 0.0, 1.0)
		model.global_basis = Basis(Vector3.UP.cross(_stumble_dir).normalized(), 0.22 * k) * model.global_basis
	if _down > 0.0:                                     # over, about his feet
		model.global_basis = Basis(_axis, _theta) * model.global_basis
	_step_drop = move_toward(_step_drop, 0.0, delta * 1.6)       # up onto the step over a fifth of a second
	model.position.y = -_step_drop + (0.13 * sin(_theta) if _down > 0.0 else 0.0)   # (lying, he's on his back's thickness)
	var a := "Idle"
	var has_run := anim.has_animation("Run")
	if _down > 0.0:
		sp = 0.0
	if gait:                                            # (gait.gd: the clips blended on his speed)
		gait.update(delta, sp, _turn_rate, _down > 0.0)
		if debug_label:
			debug_label.text = "%.2f m/s  %s  accel %+.1f  turn %+.1f  %s  vy %.2f" % [sp, str(gait.debug_data()),
				_accel, _turn_rate, "ground" if is_on_floor() else "air", velocity.y]
		return
	if sp > (2.6 if has_run else 99.0):
		a = "Run"
	elif sp > 0.3:
		a = "Walk"
	if anim.current_animation != a:
		anim.play(a, 0.35 if a == "Idle" or anim.current_animation == "Idle" else 0.25)
	# each cycle covers a stride: the cast's Walk 1.18 m/s, its Run 3.9 m/s at speed 1 (measured on the clips:
	# story_cast.py --walkstrip); the resort figure's walk 1.5, run 5.5
	var stride := (1.18 if avatar_run_stride else 1.5) if a == "Walk" else (3.9 if avatar_run_stride else 5.5)
	anim.speed_scale = clampf(sp / stride, 0.45, 1.8) if a != "Idle" else 1.0
	if debug_label:                                  # how he moves, for tuning: the foot-slide ratio is the ground the
		var slide := (sp / maxf(stride * anim.speed_scale, 0.01)) if a != "Idle" else 0.0   #  body covers per the clip's
		var slope := rad_to_deg(get_floor_normal().angle_to(Vector3.UP)) if is_on_floor() else 0.0
		debug_label.text = "%.2f m/s  %s ×%.2f  slide %.2f  %s  vy %.2f  slope %.0f°" % [sp, a, anim.speed_scale, slide,
			"ground" if is_on_floor() else "air", velocity.y, slope]


## CharacterBody3D cannot climb steps on its own: if something low blocks us
## and the same move is free one step higher, lift the body and let floor snap settle it.
## How: something just ahead blocks him; from a step's height up, the way ahead is free; looking down from there
## finds a walkable top within that height. Then he rises exactly to it (not a fixed lift and a fall back: that
## floated over the first step and jammed at the next riser of a flight).
func _try_step_up(delta: float) -> float:
	var h := Vector3(velocity.x, 0.0, velocity.z) * delta
	if h.length() < 0.0005 or not is_on_floor():
		return 0.0
	var ahead := h.normalized() * maxf(h.length(), 0.1)
	if not test_move(global_transform, ahead):
		return 0.0
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):                  # (a low ceiling: no room to rise)
		return 0.0
	var high := global_transform.translated(up)
	if test_move(high, ahead):                           # (still blocked up there: a wall, not a step)
		return 0.0
	var hit := KinematicCollision3D.new()
	if not test_move(high.translated(ahead), Vector3.DOWN * (STEP_HEIGHT + 0.02), hit):
		return 0.0
	if hit.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return 0.0
	var rise := STEP_HEIGHT - hit.get_travel().length()
	if rise <= 0.02:
		return 0.0
	global_position.y += rise + 0.005
	return rise + 0.005


## Pushed: by someone running into him, a shove, landing hard. push is horizontal, m/s of shove. Light (under 2.4,
## not hard): he stumbles a few steps to catch himself; harder: he goes over.
func knock(push: Vector3, hard := false) -> void:
	push.y = 0.0
	var s := push.length()
	if _down > 0.0 or scripted or s < 0.05:
		return
	if s < 2.4 and not hard:
		_stumble = 0.7
		_stumble_dir = push / s
		velocity += push * 0.8
		return
	_down = 1.0
	_theta = 0.0
	_omega = clampf(s * 0.55, 1.0, 4.0)                 # (the shove tips him; gravity does the rest)
	_axis = Vector3.UP.cross(push / s).normalized()     # (Basis(axis, +θ) turns up towards the push)
	velocity.x = push.x * 0.5
	velocity.z = push.z * 0.5
	_stumble = 0.0


func is_down() -> bool:
	return _down > 0.0


## Going over, on the ground, getting up.
func _downed(delta: float) -> void:
	var f := 1.0 - exp(-delta * (2.0 if _down == 1.0 else 8.0))   # (his feet drag; lying, he stops)
	velocity.x = lerpf(velocity.x, 0.0, f)
	velocity.z = lerpf(velocity.z, 0.0, f)
	match int(_down):
		1:                                               # a pendulum from his feet: θ'' = g/L sin θ
			_omega += gravity / COM * sin(maxf(_theta, 0.05)) * delta
			_theta += _omega * delta
			if _theta >= 1.5:                            # the ground: a small bounce, then still
				_theta = 1.5
				_omega = -_omega * 0.12
				if absf(_omega) < 0.6:
					_omega = 0.0
					_down = 2.0
					_down_t = 1.8
					fell.emit()
		2:
			_down_t -= delta
			if _down_t <= 0.0:
				_down = 3.0
				_down_t = 0.0
		3:                                               # up again: onto a knee and up, in a second and a half
			_down_t += delta / 1.5
			var k := clampf(_down_t, 0.0, 1.0)
			_theta = 1.5 * (1.0 - (k * k * (3.0 - 2.0 * k)))
			if k >= 1.0:
				_theta = 0.0
				_down = 0.0


# ---- testing ----
func _fall_test() -> void:
	var tree := get_tree()
	await tree.create_timer(2.0).timeout
	var fwd := Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))
	print("FALLTEST light push")
	knock(fwd.cross(Vector3.UP) * 1.8)
	await tree.create_timer(0.3).timeout
	await _fall_snap("fall_1_stumble")
	await tree.create_timer(2.0).timeout
	print("FALLTEST hard push")
	knock(fwd.cross(Vector3.UP) * -4.5)
	await tree.create_timer(0.35).timeout
	await _fall_snap("fall_2_going")
	await tree.create_timer(0.8).timeout
	print("FALLTEST down=%d theta=%.2f" % [int(_down), _theta])
	await _fall_snap("fall_3_down")
	await tree.create_timer(2.2).timeout
	await _fall_snap("fall_4_getting_up")
	await tree.create_timer(1.6).timeout
	print("FALLTEST up again: down=%d theta=%.2f" % [int(_down), _theta])
	global_position += Vector3.UP * 4.0
	velocity = Vector3(fwd.x, 0.0, fwd.z) * 1.2
	await tree.create_timer(1.3).timeout
	print("FALLTEST after the drop: down=%d theta=%.2f" % [int(_down), _theta])
	await _fall_snap("fall_5_drop")
	await tree.create_timer(5.0).timeout
	print("FALLTEST done: down=%d" % int(_down))
	tree.quit()


func _fall_snap(n: String) -> void:
	print("FALLTEST %s at %s floor %s cam %s vel %s" % [n, str(global_position), is_on_floor(), str(get_viewport().get_camera_3d().global_position), str(velocity)])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % n), 0.85)


func _stair_test() -> void:
	var tree := get_tree()
	await tree.create_timer(2.0).timeout
	var a := tree.root.find_child("Mark_cut", true, false) as Node3D
	var b := tree.root.find_child("Mark_landing", true, false) as Node3D
	if a == null or b == null:
		print("STAIRTEST no stair here")
		tree.quit()
		return
	var up := Vector3(b.global_position.x - a.global_position.x, 0.0, b.global_position.z - a.global_position.z).normalized()
	spawn_at(a.global_position + up * 0.6 + Vector3.UP * 0.6, b.global_position)
	await tree.create_timer(1.0).timeout
	var side := Camera3D.new()                           # a camera from the stair's open side, level with his legs
	side.fov = 45.0
	get_parent().add_child(side)
	var lamp := OmniLight3D.new()                        # (the power is cut on this stair: a lamp for the pictures)
	lamp.omni_range = 5.0
	lamp.light_energy = 2.0
	side.add_child(lamp)
	var right := up.cross(Vector3.UP)
	for k in 6:
		auto_input = Vector2(0, -1) if k > 0 else Vector2.INF
		await tree.create_timer(0.55 if k > 0 else 0.3).timeout
		auto_input = Vector2.ZERO if k > 0 else Vector2.INF
		await tree.create_timer(0.6).timeout
		var at := global_position + Vector3.UP * 0.5
		side.global_position = at + right * 2.0 + Vector3.UP * 0.1 - up * 0.2
		side.look_at(at, Vector3.UP)
		side.make_current()
		print("STAIRTEST %d at y %.2f: %s" % [k, global_position.y, feet.debug if feet else "no foot IK"])
		await _fall_snap("stair_%d" % k)
		camera.make_current()
	auto_input = Vector2.INF
	tree.quit()


## (development) how he's moving, for the debug display and the tests.
func get_movement_debug_data() -> Dictionary:
	var d := {"speed": snappedf(Vector2(velocity.x, velocity.z).length(), 0.01), "grounded": is_on_floor(),
		"vertical_velocity": snappedf(velocity.y, 0.01), "facing": snappedf(_model_yaw, 0.01), "down": _down}
	if gait:
		d.merge(gait.debug_data())
	return d


var _slide_sum := 0.0
var _slide_n := 0
var _slide_prev := {}


## The planted foot's slide: the lower foot each frame (it's the one bearing him), how it moves over the ground,
## m/s; and along his way (+: it creeps forward, the clip's steps too short for his speed; −: too long).
var _slide_fwd := 0.0


func _measure_slide(delta: float) -> void:
	if gait == null or gait._sk == null:
		return
	var sk: Skeleton3D = gait._sk
	var lo := ""
	var ly := INF
	var pos := {}
	for s in ["l", "r"]:
		var w: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot_" + s)).origin
		pos[s] = w
		if w.y < ly:
			ly = w.y
			lo = s
	if _slide_prev.get("foot", "") == lo and ly - global_position.y < 0.1:   # (on the ground: not the run's flight)
		var d: Vector3 = pos[lo] - _slide_prev["at"]
		var fwd := Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))
		_slide_sum += Vector2(d.x, d.z).length() / maxf(delta, 0.001)
		_slide_fwd += d.dot(fwd) / maxf(delta, 0.001)
		_slide_n += 1
	_slide_prev = {"foot": lo, "at": pos[lo]}


func _gait_phase(name: String, input: Vector2, pace: String, secs: float, side: Camera3D, turn_input := 0.0) -> void:
	var tree := get_tree()
	auto_input = input
	auto_pace = pace
	_slide_sum = 0.0
	_slide_fwd = 0.0
	_slide_n = 0
	_slide_prev = {}
	var t := 0.0
	var top := 0.0
	var snapped := false
	while t < secs:
		await tree.physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if turn_input != 0.0:                            # (a circle: the keys' way turning steadily)
			auto_input = Vector2(sin(t * turn_input), -cos(t * turn_input))
		if t > secs * 0.4:
			_measure_slide(dt)
		top = maxf(top, Vector2(velocity.x, velocity.z).length())
		if not snapped and t > secs * 0.7:
			snapped = true
			var at := global_position + Vector3.UP * 0.9
			var fwd := Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))
			side.global_position = at + fwd.cross(Vector3.UP) * 3.2 + fwd * 0.6 + Vector3.UP * 0.2
			side.look_at(at, Vector3.UP)
			side.make_current()
			await _fall_snap("gait_" + name)
			camera.make_current()
	var d := get_movement_debug_data()
	print("GAITTEST %-9s speed %.2f (top %.2f)  planted foot slides %.2f m/s (along his way %+.2f) over %d samples  %s" % [name,
		d["speed"], top, _slide_sum / maxf(_slide_n, 1), _slide_fwd / maxf(_slide_n, 1), _slide_n, str(gait.debug_data()) if gait else "no gait"])


func _gait_test() -> void:
	var tree := get_tree()
	await tree.create_timer(2.0).timeout
	if gait == null:
		print("GAITTEST no gait (this model has no Loco clips)")
		tree.quit()
		return
	var side := Camera3D.new()
	side.fov = 45.0
	get_parent().add_child(side)
	await _gait_phase("idle", Vector2.ZERO, "", 4.0, side)
	await _gait_phase("slow", Vector2(0, -1), "slow", 4.0, side)
	await _gait_phase("walk", Vector2(0, -1), "walk", 4.0, side)
	await _gait_phase("fast", Vector2(0, -1), "fast", 4.0, side)
	await _gait_phase("jog", Vector2(0, -1), "jog", 4.0, side)
	await _gait_phase("sprint", Vector2(0, -1), "sprint", 5.0, side)
	await _gait_phase("stop", Vector2.ZERO, "", 1.2, side)
	await _gait_phase("turn90", Vector2(1, 0), "walk", 2.5, side)
	await _gait_phase("turn180", Vector2(-1, 0), "walk", 3.0, side)
	await _gait_phase("circle", Vector2(0, -1), "walk", 6.0, side, 1.0)
	await _gait_phase("standturn", Vector2.ZERO, "", 1.0, side)
	rotation.y += PI * 0.5                                # (the view turned: the keys now ask him to turn on the spot)
	await _gait_phase("spotturn", Vector2(0, -1), "slow", 0.6, side)
	await _gait_phase("back", Vector2(0, 1), "walk", 0.9, side)
	await _gait_phase("breath", Vector2.ZERO, "", 4.0, side)
	set_crouch(true)
	await _gait_phase("crouch", Vector2.ZERO, "", 2.0, side)
	await _gait_phase("crouchwalk", Vector2(0, -1), "", 4.0, side)
	print("GAITTEST up again: %s" % (not set_crouch(false)))
	await _gait_phase("stood", Vector2.ZERO, "", 1.0, side)
	auto_input = Vector2.INF
	auto_pace = ""
	tree.quit()


func _stand_test(tag: String) -> void:
	var tree := get_tree()
	await tree.create_timer(3.0).timeout
	var cam := Camera3D.new()
	cam.fov = 40.0
	get_parent().add_child(cam)
	for n in get_parent().find_children("*", "VehicleBody3D", true, false) + get_parent().find_children("*", "RigidBody3D", true, false):
		var b := n as Node3D                             # (what's near him, and how high over the ground under it)
		if b.global_position.distance_to(global_position) > 15.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(b.global_position + Vector3.UP * 0.5, b.global_position + Vector3.DOWN * 8.0)
		q.exclude = [(b as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		print("STANDTEST near: %s (%s) at %s, %.2f m over %s; frozen %s" % [b.name, b.get_class(), str(b.global_position.snapped(Vector3.ONE * 0.01)),
			(b.global_position.y - float(hit["position"].y)) if not hit.is_empty() else -1.0, str(hit["collider"].name) if not hit.is_empty() else "-",
			str(b.get("freeze"))])
	var fwd := Vector3(sin(_model_yaw), 0.0, cos(_model_yaw))
	var right := fwd.cross(Vector3.UP)
	var base := global_position
	for v in [["front", fwd], ["back", -fwd], ["left", -right], ["right", right]]:
		var d: Vector3 = v[1]
		for k in [["whole", 3.4, 0.95], ["legs", 1.9, 0.5]]:
			cam.global_position = base + d * float(k[1]) + Vector3.UP * float(k[2])
			cam.look_at(base + Vector3.UP * float(k[2]), Vector3.UP)
			cam.make_current()
			await tree.create_timer(0.4).timeout
			await _fall_snap("stand_%s_%s_%s" % [tag, v[0], k[0]])
	camera.make_current()
	await tree.create_timer(0.4).timeout
	await _fall_snap("stand_%s_play" % tag)
	if gait:                                             # the hands in his pockets: stood still a while
		gait._still = 0.0
		gait._pocket = true
		gait._pocket_at = 9999.0
		await tree.create_timer(1.5).timeout
		for v in [["front", fwd], ["right", right], ["back", -fwd], ["close", fwd * 0.45 + right * 0.35]]:
			cam.global_position = base + (v[1] as Vector3) * (3.4 if v[0] != "close" else 2.0) + Vector3.UP * (0.95 if v[0] != "close" else 1.0)
			cam.look_at(base + Vector3.UP * 0.95, Vector3.UP)
			cam.make_current()
			await tree.create_timer(0.3).timeout
			await _fall_snap("stand_%s_pocket_%s" % [tag, v[0]])
		gait._pocket = false
		gait._still = 0.0
		gait._pocket_at = 8.0
		camera.make_current()
	if gait:                                             # his hands: close, from the front, in each pose
		for pose in ["", "open", "point", "phone", "papers", "fist", "grip"]:
			gait.hand_test = pose
			await tree.create_timer(0.6).timeout
			var hp: Vector3 = global_position + Vector3.UP * 0.85     # (both hands, from the front, a little to his right)
			cam.global_position = hp + fwd * 1.15 + right * 0.3 + Vector3.UP * 0.05
			cam.look_at(hp, Vector3.UP)
			cam.make_current()
			await tree.create_timer(0.2).timeout
			await _fall_snap("stand_%s_hand_%s" % [tag, pose if pose != "" else "relaxed"])
			var sk: Skeleton3D = gait._sk
			var msg := ""
			for sd in ["l", "r"]:
				var palm: Vector3 = (sk.get_bone_global_pose(sk.find_bone("middle_01_" + sd)).origin + sk.get_bone_global_pose(sk.find_bone("hand_" + sd)).origin) * 0.5
				for f in ["thumb_03", "index_03", "pinky_03", "thumb_01"]:
					msg += " %s_%s %.3f" % [f, sd, sk.get_bone_global_pose(sk.find_bone(f + "_" + sd)).origin.distance_to(palm)]
			print("STANDTEST hand %s distances to the palm:%s" % [pose, msg])
			if pose in ["", "fist"]:                     # (the right hand close: from his front and from his right)
				var hr: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("middle_01_r")).origin
				for vv in [["front", fwd], ["side", right]]:
					cam.global_position = hr + (vv[1] as Vector3) * 0.4 + Vector3.UP * 0.05
					cam.look_at(hr, Vector3.UP)
					await tree.create_timer(0.15).timeout
					await _fall_snap("stand_%s_rhand_%s_%s" % [tag, pose if pose != "" else "relaxed", vv[0]])
			print("STANDTEST hand %s: weights l %.2f r %.2f, index_02 bend l %.0f° r %.0f°" % [pose, float(gait.tree.get("parameters/hand_l/blend_amount")),
				float(gait.tree.get("parameters/hand_r/blend_amount")), rad_to_deg(sk.get_bone_pose_rotation(sk.find_bone("index_02_l")).get_angle()),
				rad_to_deg(sk.get_bone_pose_rotation(sk.find_bone("index_02_r")).get_angle())])
		gait.hand_test = ""
	tree.quit()


## His hand to a point (a door, a drawer's pull, a switch): turned to it, the arm reaches, the hand in `pose`;
## returns when it's there (await it), lets go `hold` seconds later. Nothing happens for a model without arms' IK.
func reach(point: Vector3, pose := "open", hold := 0.35) -> void:
	if hand_reach == null or _down > 0.0 or scripted:
		return
	var to := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to.length() > 0.1:                                # (facing it first, at a person's turn)
		var want := atan2(to.x, to.z)
		var tw := create_tween()
		tw.tween_method(func(v: float): _model_yaw = lerp_angle(_model_yaw, want, v), 0.0, 1.0, 0.18)
		await tw.finished
	await hand_reach.go(point, pose, hold)


## Low or up: the capsule shortened to a crouching man's height (1.15 m) or back; standing only where there's room
## over his head (a ray up the capsule's extra height). Returns whether he's now crouched.
func set_crouch(low: bool) -> bool:
	if gait == null or low == gait.crouched:
		return gait != null and gait.crouched
	if not low:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.1, global_position + Vector3.UP * 1.8)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return true                                  # (something over him: he stays down)
	gait.crouched = low
	_capsule.height = 1.15 if low else 1.75
	_shape.position.y = _capsule.height * 0.5
	return low


## Into a seat as a person sits: to just in front of it (his back to it), then down onto it (crowd_clips.py SitDown:
## the feet stay where they are, the knees and hips bend, the chest forward for balance), then seated (pose). seat: where
## his hips go, yaw: the way he faces seated (as rotation.y). Awaitable. Without the clip: straight into the pose.
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const SIT_BACK := 0.42               # (SitDown's hips travel back this far onto the seat: its feet stand this far ahead)


func sit_down_at(seat: Vector3, yaw: float, pose := "Sit") -> void:
	if anim == null or model == null:
		return
	CrowdClips.add(model, "m")
	if gait:                                               # (his own tree out of the way while he sits)
		gait.held = true
		gait.tree.active = false
	rotation.y = yaw
	var my := yaw + PI                                     # (the model faces +Z)
	var fwd := Vector3(sin(my), 0.0, cos(my))
	var feet := seat + fwd * SIT_BACK
	feet.y = global_position.y if absf(global_position.y - seat.y) < 1.2 else seat.y
	var d := Vector2(feet.x - global_position.x, feet.z - global_position.z).length()
	if d > 0.15 and anim.has_animation("Walk"):            # (a few steps to the seat's front)
		anim.play("Walk", 0.25)
		var walk_yaw := atan2(feet.x - global_position.x, feet.z - global_position.z)
		model.global_rotation = Vector3(0.0, walk_yaw, 0.0)
		var tw := create_tween()
		tw.tween_property(self, "global_position", Vector3(feet.x, global_position.y, feet.z), clampf(d / 1.2, 0.25, 2.5))
		await tw.finished
	model.global_rotation = Vector3(0.0, my, 0.0)          # (turned, his back to the seat)
	_model_yaw = my
	if anim.has_animation("crowd/SitDown"):
		var a := anim.get_animation("crowd/SitDown")
		a.loop_mode = Animation.LOOP_NONE
		anim.play("crowd/SitDown", 0.25)
		await get_tree().create_timer(a.length - 0.05).timeout
	global_position = Vector3(seat.x, seat.y, seat.z)      # (the hips over the seat: the seated pose's own place)
	if anim.has_animation(pose):
		anim.play(pose, 0.15)


## Up out of the seat he's in (the reverse: the feet first, the chest forward, up); then standing. Awaitable.
func stand_up_from_seat() -> void:
	if anim == null or model == null:
		return
	var my := model.global_rotation.y
	var fwd := Vector3(sin(my), 0.0, cos(my))
	if anim.has_animation("crowd/StandUp"):
		global_position += fwd * SIT_BACK                 # (StandUp starts with the hips SIT_BACK behind the feet)
		var a := anim.get_animation("crowd/StandUp")
		a.loop_mode = Animation.LOOP_NONE
		anim.play("crowd/StandUp", 0.15)
		await get_tree().create_timer(a.length - 0.05).timeout
	if anim.has_animation("Idle"):
		anim.play("Idle", 0.3)
	if gait:
		gait.held = false
		anim.stop()                                        # (the tree has him again, standing)


func _sit_test() -> void:
	var tree := get_tree()
	await tree.create_timer(2.0).timeout
	set_physics_process(false)
	var my := _model_yaw
	var fwd := Vector3(sin(my), 0.0, cos(my))
	var seat := global_position - fwd * 1.0                # a chair a metre behind him, facing the way he does
	var chair := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.45, 0.46, 0.45)
	chair.mesh = b
	get_parent().add_child(chair)
	chair.global_position = seat + Vector3.UP * 0.23 - fwd * 0.05
	var cam := Camera3D.new()
	cam.fov = 45.0
	get_parent().add_child(cam)
	var right := fwd.cross(Vector3.UP)
	cam.global_position = seat + fwd * 2.6 + right * 1.3 + Vector3.UP * 1.3   # (from in front, a little to his side)
	cam.look_at(seat + fwd * 0.2 + Vector3.UP * 0.6, Vector3.UP)
	cam.make_current()
	sit_down_at.call_deferred(seat, my - PI, "Sit")       # (the sitting runs; the pictures are taken as it goes)
	await tree.create_timer(1.55).timeout
	await _fall_snap("sit_1_going_down")
	await tree.create_timer(1.6).timeout
	await _fall_snap("sit_2_seated")
	stand_up_from_seat.call_deferred()
	await tree.create_timer(0.6).timeout
	await _fall_snap("sit_3_getting_up")
	await tree.create_timer(1.4).timeout
	await _fall_snap("sit_4_up")
	print("SITTEST done")
	tree.quit()
