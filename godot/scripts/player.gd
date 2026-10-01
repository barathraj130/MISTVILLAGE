extends CharacterBody3D
## First-person explorer. A capsule stands in until a rigged character is added.

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
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 40000.0
	camera.fov = 70.0
	head.add_child(camera)
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
