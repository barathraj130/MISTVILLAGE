extends CharacterBody3D
## You on foot: one of our own Blender-made people (tools/people.py) with idle / walk / run
## animations, seen from a third-person camera on a spring arm (it pulls in rather than going
## through walls). V switches to first person. The mouse turns the view; the body turns to face
## the way you walk, as a person does: it gets going and slows down over a few steps, turns at a
## person's pace (slowing to turn sharply, leaning a little into a curve), stands facing where it
## stopped while you look about, and rises onto a step rather than jumping up it.
const Prof := preload("res://scripts/drive/prof.gd")
const Settings := preload("res://scripts/settings.gd")

const STEP_HEIGHT := 0.35          # stone steps and kerbs are 15–25 cm

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
var debug_label: Label              # (development: --movedebug shows how he moves)
const AVATAR := "res://assets/people/person_man_shirt.glb"
static var avatar := ""            # who you are on foot, when not the default (the story: Karthik himself)
var avatar_run_stride := false     # a story cast model: its Run covers ~3.9 m/s at speed 1
var scripted := false              # a scene moves him (brush3d.gd): his clips and facing are its, not the walk's


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
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
	if active:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if auto_input == Vector2.INF else auto_input
		var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		var running := Input.is_action_pressed("run") if auto_input == Vector2.INF else auto_run
		var speed := (run_speed if running else walk_speed) * minf(input.length(), 1.0)   # (a stick half pushed: slower)
		if dir != Vector3.ZERO and model:               # a sharp turn: he slows to make it, then goes on
			var off := absf(angle_difference(_model_yaw, atan2(dir.x, dir.z)))
			speed *= clampf(1.0 - (off - 0.6) / 2.0, 0.35, 1.0)
		if dir != Vector3.ZERO and is_on_floor():       # a slope: slower up it, careful down a steep one
			var grade := -dir.dot(get_floor_normal())    # (sin of the slope, + uphill)
			if grade > 0.0:
				speed *= 1.0 - clampf(grade * 0.5, 0.0, 0.3)
			else:
				speed *= 1.0 - clampf((-grade - 0.2) * 0.8, 0.0, 0.2)
		var want := Vector2(dir.x, dir.z) * speed
		var have := Vector2(velocity.x, velocity.z)
		var rate := (ACCEL if want.length() > have.length() else DECEL) * (1.0 if is_on_floor() else 0.3)
		have = have.move_toward(want, rate * delta)
		velocity.x = have.x
		velocity.z = have.y
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if active:                                          # up a step: the body catches up with the capsule
		_step_drop = minf(_step_drop + _try_step_up(delta), 0.4)
	move_and_slide()
	if global_position.y < -400.0:         # fell off the world
		_respawn()
	_animate(delta)


func _animate(delta: float) -> void:
	if model == null or scripted:
		return
	if _last_pos.distance_to(global_position) > 3.0:
		_model_yaw = rotation.y + PI
		_step_drop = 0.0
	_last_pos = global_position
	var flat := Vector3(velocity.x, 0, velocity.z)
	var sp := flat.length()
	var turned := 0.0
	if sp > 0.2:
		# face the way you're walking (the model faces +Z), turning at a person's pace; standing, he stays put
		var was := _model_yaw
		var rate := lerpf(TURN_RATE, TURN_RATE_RUN, clampf((sp - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0))
		_model_yaw = lerp_angle(_model_yaw, atan2(flat.x, flat.z), 1.0 - exp(-delta * rate))
		turned = angle_difference(was, _model_yaw) / maxf(delta, 0.001)
	_lean = lerpf(_lean, clampf(-turned * sp * 0.012, -0.12, 0.12), 1.0 - exp(-delta * 6.0))   # into the curve
	model.global_rotation = Vector3(0.0, _model_yaw, 0.0)
	model.rotate_object_local(Vector3.FORWARD, _lean)
	_step_drop = move_toward(_step_drop, 0.0, delta * 1.6)       # up onto the step over a fifth of a second
	model.position.y = -_step_drop
	var a := "Idle"
	var has_run := anim.has_animation("Run")
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
