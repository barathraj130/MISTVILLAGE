extends CharacterBody3D
## You on foot: one of our own Blender-made people (tools/people.py) with idle / walk / run
## animations, seen from a third-person camera on a spring arm (it pulls in rather than going
## through walls). V switches to first person. The mouse turns the view; the body turns to face
## the way you walk.

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
var _model_yaw := PI
const AVATAR := "res://assets/people/person_man_shirt.glb"


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
	if ResourceLoader.exists(AVATAR):
		model = (load(AVATAR) as PackedScene).instantiate() as Node3D
		model.rotation.y = _model_yaw
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
		var accel := (10.0 if is_on_floor() else 2.0) * speed * delta
		velocity.x = move_toward(velocity.x, dir.x * speed, accel)
		velocity.z = move_toward(velocity.z, dir.z * speed, accel)
		_try_step_up(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	if global_position.y < -400.0:         # fell off the world
		_respawn()
	_animate(delta)


func _animate(delta: float) -> void:
	if model == null:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var sp := flat.length()
	if sp > 0.3:
		# face the way you're walking (the model faces +Z; the body's forward is -Z)
		var local := global_transform.basis.inverse() * flat
		var want := atan2(local.x, local.z)
		_model_yaw = lerp_angle(_model_yaw, want, 1.0 - exp(-delta * 10.0))
		model.rotation.y = _model_yaw
	var a := "Idle"
	if sp > 4.2:
		a = "Run"
	elif sp > 0.3:
		a = "Walk"
	if anim.current_animation != a:
		anim.play(a, 0.2)
	anim.speed_scale = clampf(sp / (1.4 if a == "Walk" else 5.5), 0.6, 1.6) if a != "Idle" else 1.0


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
