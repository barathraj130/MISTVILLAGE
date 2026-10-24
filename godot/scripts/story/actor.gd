extends Node3D
## A story character in the world: one of the animated people (tools/people.py: Idle, Walk, Run, Sit, Talk),
## standing on the ground, who can face a point, talk, sit, or walk to a spot. Used by cutscenes and by people
## you walk up to and talk to (E).

const PEOPLE := "res://assets/people/%s.glb"

var model: Node3D
var anim: AnimationPlayer
var ground: Callable                   # (x, z) -> ground height (the city streamer's height_at)
var who := ""                          # the person's key in the chapter (raghavan, amma, ...)
var _target := Vector3.INF
var _speed := 1.4
var _after := "Idle"


func setup(person: String, key: String, height_fn: Callable) -> void:
	who = key
	ground = height_fn
	var path := PEOPLE % person
	if not ResourceLoader.exists(path):
		push_warning("actor: no model " + path)
		return
	model = (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0] as AnimationPlayer
		for a in anim.get_animation_list():
			if not a.begins_with("Sit"):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	play("Idle")


func play(name: String) -> void:
	if anim and anim.has_animation(name) and anim.current_animation != name:
		anim.play(name, 0.25)


## Stand at (x, z) on the ground, facing towards `look` (a point).
func place(at: Vector3, look: Vector3) -> void:
	global_position = Vector3(at.x, _h(at.x, at.z), at.z)
	face(look)
	_target = Vector3.INF


func face(look: Vector3) -> void:
	var d := Vector3(look.x - global_position.x, 0.0, look.z - global_position.z)
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)          # the people models face +Z (as player.gd)


func walk_to(at: Vector3, speed := 1.4, then := "Idle") -> void:
	_target = Vector3(at.x, 0.0, at.z)
	_speed = speed
	_after = then
	play("Walk" if speed < 2.5 else "Run")


func walking() -> bool:
	return _target != Vector3.INF


func _h(x: float, z: float) -> float:
	if ground.is_valid():
		var g: float = ground.call(x, z)
		if not is_nan(g):
			return g
	return global_position.y


func _process(dt: float) -> void:
	if _target == Vector3.INF:
		return
	var p := global_position
	var d := Vector3(_target.x - p.x, 0.0, _target.z - p.z)
	if d.length() < 0.15:
		_target = Vector3.INF
		play(_after)
		return
	var step := d.normalized() * minf(_speed * dt, d.length())
	global_position = Vector3(p.x + step.x, _h(p.x + step.x, p.z + step.z), p.z + step.z)
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-dt * 10.0))
