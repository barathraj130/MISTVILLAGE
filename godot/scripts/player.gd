extends CharacterBody3D
## You on foot: one of our own Blender-made people (tools/people.py) with idle / walk / run
## animations, seen from a third-person camera on a spring arm (it pulls in rather than going
## through walls). V switches to first person. The mouse turns the view; the body turns to face
## the way you walk, as a person does: it gets going and slows down over a few steps, turns at a
## person's pace (slowing to turn sharply, leaning a little into a curve), stands facing where it
## stopped while you look about, and rises onto a step rather than jumping up it.

const STEP_HEIGHT := 0.35          # stone steps and kerbs are 15–25 cm

@export var walk_speed := 3.2
@export var run_speed := 7.0
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
const TURN_RATE := 7.0              # how quickly the body swings round to the way you go
const AVATAR := "res://assets/people/person_man_shirt.glb"
static var avatar := ""            # who you are on foot, when not the default (the story: Karthik himself)
var avatar_run_stride := false     # a story cast model: its Run covers ~3.9 m/s at speed 1


func _init() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
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
		rotation.y -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.45, 1.45)
		head.rotation.x = _pitch
	elif InputMap.has_action("camera_view") and event.is_action_pressed("camera_view"):
		_set_view(not third_person)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if active:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		var speed := run_speed if Input.is_action_pressed("run") else walk_speed
		if dir != Vector3.ZERO and model:               # a sharp turn: he slows to make it, then goes on
			var off := absf(angle_difference(_model_yaw, atan2(dir.x, dir.z)))
			speed *= clampf(1.0 - (off - 0.6) / 2.0, 0.35, 1.0)
		var want := Vector2(dir.x, dir.z) * speed
		var have := Vector2(velocity.x, velocity.z)
		var rate := (ACCEL if want.length() > have.length() else DECEL) * (1.0 if is_on_floor() else 0.3)
		have = have.move_toward(want, rate * delta)
		velocity.x = have.x
		velocity.z = have.y
		_try_step_up(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	var y0 := global_position.y
	move_and_slide()
	var rise := global_position.y - y0
	if rise > 0.08 and rise < 0.5 and is_on_floor():   # up a step: the body catches up with the capsule
		_step_drop = minf(_step_drop + rise, 0.4)
	if global_position.y < -400.0:         # fell off the world
		_respawn()
	_animate(delta)


func _animate(delta: float) -> void:
	if model == null:
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
		_model_yaw = lerp_angle(_model_yaw, atan2(flat.x, flat.z), 1.0 - exp(-delta * TURN_RATE))
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


## CharacterBody3D cannot climb steps on its own: if something low blocks us
## and the same move is free one step higher, lift the body and let floor snap settle it.
func _try_step_up(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z) * delta
	if h.length() < 0.001 or not is_on_floor():
		return
	if not test_move(global_transform, h):
		return
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return
	if test_move(global_transform.translated(up), h):
		return
	global_position += up
