extends RigidBody3D
## A raycast-wheel car (OPEN_WORLD_PLAN phase 6, the physics brief's comparison): a rigid body held up by four rays,
## each a spring and damper, with a tyre model of our own, to measure against Godot's VehicleBody3D (jeep.gd) on the
## vehicle lab. Not used in the game: docs/VEHICLE_LAB.md has the comparison and the decision.
##   suspension  a ray per wheel from its mount: spring (8 cm sag under the car's weight) and damper (0.35 of
##               critical), an anti-roll bar across each axle
##   tyres       slip angle → side force on a simplified Pacejka curve (B 8, C 1.6), scaled by the wheel's load and
##               the road's grip; the drive and the brakes along the wheel; the two together held inside the
##               friction circle (μ·load), so braking in a bend costs cornering as it does
##   engine      jeep.gd's DRIVE profile (petrol_car for the sedan): its torque curve and gearbox, front-wheel drive;
##               air drag and rolling resistance on the body; the brakes as jeep.gd's (brake_g of the car's weight),
##               which the tyres cap (ABS: they never lock)
## The lab drives it through the same controls and reads the same numbers as jeep.gd: in_throttle, in_brake,
## in_steer, in_handbrake, speed, set_grip, set_surface, surface, _wheels (is_in_contact), jolt, steering, rpm, gear.

const Jeep := preload("res://scripts/drive/jeep.gd")
const SAG := 0.08                    # m the springs give under the car's own weight
const REST := 0.22                   # m of suspension below the mount at rest length
const DAMP := 0.35                   # of critical damping
const B := 8.0                       # the tyre curve's stiffness and shape (simplified Pacejka)
const C := 1.6
const MU := 1.0                      # dry tarmac, this tyre
const ARB := 9000.0                  # N/m anti-roll per axle

signal impacted(zone: String, severity: float, other: Object)

var vehicle := "sedan"
var autopilot := true
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var speed := 0.0
var steering := 0.0
var rpm := 800.0
var gear := 1
var engine_force := 0.0
var brake := 0.0
var _thr := 0.0
var jolt := 0.0
var surface := "asphalt"
var lean := 0.0
var lean_target := 0.0
var damage := {"front": 0.0}
var _pull := 0.0
var torque_mul := 1.0
var _grip := 1.0
var _surface_grip := 1.0
var _wheels: Array = []              # RCWheel, front left/right, rear left/right
var _drive: Dictionary
var _r := 0.31                       # wheel radius
var _vy_was := 0.0


class RCWheel:
	extends RefCounted
	var mount := Vector3.ZERO         # in the car's frame
	var front := false
	var contact := false
	var comp := 0.0                   # m compressed
	var comp_was := 0.0
	var load := 0.0                   # N on the road

	func is_in_contact() -> bool:
		return contact


func configure(kind: String) -> void:
	vehicle = kind
	_drive = Jeep.DRIVE[Jeep.DRIVE_OF.get(kind, ["petrol_car", 1.0])[0]]
	mass = 1250.0
	var cs := CollisionShape3D.new()                     # the body, its belly 0.3 m clear of the road
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.75, 1.0, 4.4)
	cs.shape = bx
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.55, 0.15)
	inertia = Vector3(mass * (1.0 + 0.25) / 12.0 * 1.6, mass * (4.4 * 4.4 + 1.75 * 1.75) / 12.0, mass * (4.4 * 4.4 + 1.0) / 12.0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	for spec in [[0.75, 1.32, true], [-0.75, 1.32, true], [0.75, -1.28, false], [-0.75, -1.28, false]]:
		var w := RCWheel.new()
		w.mount = Vector3(spec[0], _r + REST, spec[1])
		w.front = spec[2]
		_wheels.append(w)
	var mi := MeshInstance3D.new()                       # (a plain box to see it by)
	var bm := BoxMesh.new()
	bm.size = bx.size
	mi.mesh = bm
	mi.position = cs.position
	add_child(mi)


func forward() -> Vector3:
	return global_basis.z


func set_grip(g: float) -> void:
	_grip = g


func set_surface(kind: String) -> void:
	surface = kind
	_surface_grip = {"asphalt": 1.0, "concrete": 1.0, "gravel": 0.65, "earth": 0.85, "mud": 0.4, "ground": 0.8}.get(kind, 1.0)


func repair() -> void:
	damage = {"front": 0.0}


func _physics_process(dt: float) -> void:
	if freeze:
		return
	var xf := global_transform
	var up := xf.basis.y
	var fwd := xf.basis.z
	speed = linear_velocity.dot(fwd)
	var v := absf(speed)
	_thr = move_toward(_thr, in_throttle, dt * 3.0)
	var steer_max := 0.6 / (1.0 + v / 14.0)              # (less lock as speed rises, as a driver gives it)
	steering = move_toward(steering, in_steer * steer_max, dt * 1.6)
	# the engine through the gearbox
	var ratios: Array = _drive["ratios"]
	var final: float = _drive["final"]
	var wheel_rpm := v / _r * 60.0 / TAU
	rpm = clampf(wheel_rpm * float(ratios[gear - 1]) * final, float(_drive["idle"]), float(_drive["redline"]))
	if rpm > float(_drive["up"][1]) and gear < ratios.size():
		gear += 1
	elif gear > 1 and wheel_rpm * float(ratios[gear - 2]) * final < float(_drive["up"][0]):
		gear -= 1
	var torque := _torque_at(rpm) * _thr * torque_mul
	engine_force = torque * float(ratios[gear - 1]) * final / _r * 0.9   # (driveline losses)
	brake = in_brake * float(_drive["brake_g"]) * mass * 9.81
	# air and rolling
	var drag := -fwd * signf(speed) * (0.5 * 1.2 * float(_drive["cda"]) * speed * speed + float(_drive["crr"]) * mass * 9.81 * (1.0 if v > 0.2 else v / 0.2))
	apply_central_force(drag)
	var k := mass * 9.81 / 4.0 / SAG
	var c := DAMP * 2.0 * sqrt(k * mass / 4.0)
	var mu := MU * _grip * _surface_grip
	# the springs first (their loads set what each tyre can do), the anti-roll bars between
	for w in _wheels:
		var r: RCWheel = w
		var from: Vector3 = xf * r.mount
		var q := PhysicsRayQueryParameters3D.create(from, from - up * (REST + _r))
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		r.comp_was = r.comp
		r.contact = not hit.is_empty()
		r.comp = (REST + _r - from.distance_to(hit["position"])) if r.contact else 0.0
		r.load = maxf(k * r.comp + c * (r.comp - r.comp_was) / dt, 0.0) if r.contact else 0.0
	for pair in [[0, 1], [2, 3]]:
		var a: RCWheel = _wheels[pair[0]]
		var b2: RCWheel = _wheels[pair[1]]
		var bar := (a.comp - b2.comp) * ARB
		if a.contact:
			a.load = maxf(a.load + bar, 0.0)
		if b2.contact:
			b2.load = maxf(b2.load - bar, 0.0)
	var driven := 2.0
	for w in _wheels:
		var r: RCWheel = w
		if not r.contact:
			continue
		var at: Vector3 = xf * (r.mount - Vector3(0, REST + _r - r.comp, 0))
		var rel := at - global_position
		apply_force(up * r.load, rel)
		var wf := fwd.rotated(up, steering) if r.front else fwd   # the wheel's own heading
		var wr := up.cross(wf).normalized()
		var pv := linear_velocity + angular_velocity.cross(rel)
		var vl := pv.dot(wf)
		var vt := pv.dot(wr)
		var cap := mu * r.load
		# side: the slip angle on the tyre curve; at a crawl a plain damping (the curve is undefined at rest)
		var alpha := atan2(vt, maxf(absf(vl), 0.5))
		var fy := -cap * sin(C * atan(B * alpha))
		if absf(vl) < 1.0:
			fy = lerpf(clampf(-vt * mass / 4.0 / dt * 0.25, -cap, cap), fy, absf(vl))
		# along: the drive (front wheels), the brakes (60 % front), the handbrake (rear)
		var fx := 0.0
		if r.front:
			fx += engine_force / driven
		var bshare := 0.3 if r.front else 0.2
		var bf := brake * bshare + (mass * 9.81 * 0.5 if in_handbrake and not r.front else 0.0)
		if absf(vl) > 0.05:
			fx -= signf(vl) * bf
		elif bf > 0.0:
			fx -= clampf(vl * mass / 4.0 / dt, -bf, bf)
		var f := Vector2(fx, fy)                         # the friction circle
		if f.length() > cap:
			f = f.normalized() * cap
		apply_force(wf * f.x + wr * f.y, rel)
	jolt = absf(linear_velocity.y - _vy_was) / dt * 0.1 + jolt * 0.9
	_vy_was = linear_velocity.y


func _torque_at(r: float) -> float:
	var curve: Array = _drive["torque"]
	if r <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(curve.size() - 1):
		var a: Array = curve[i]
		var b: Array = curve[i + 1]
		if r <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (r - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(curve[-1][1])
