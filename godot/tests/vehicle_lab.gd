extends Node3D
## The vehicle lab: a flat test ground where the autopilot drives each vehicle through measured runs, through the
## real physics (no teleporting while a run is on), and prints one line per run ("LAB {json}"):
##   accel    full throttle from rest: seconds to 60 and 100 km/h, top speed after 30 s
##   brake    from 60 km/h, full brake: stopping distance and time, the nose's dip (pitch, degrees)
##   wet      the same on wet tarmac (grip 0.7)
##   turn     full lock at 10 km/h: turning-circle radius (m)
##   corner   at 40 km/h the steering wound in over 6 s: the most lateral g held, body roll (deg), spun out or not
##   bump     a city speed breaker (3 m, 10 cm: city_streamer.gd's) at 20 and 40 km/h: wheels-off time, peak jolt,
##            peak pitch
## Run: Godot --headless --fixed-fps 60 --path godot scenes/vehicle_lab.tscn -- --vehicles=karthik_scooter,sedan
## (default: the story's own and a spread of the fleet). Numbers are for comparing before/after a change, not claims
## about real vehicles.

const Jeep := preload("res://scripts/drive/jeep.gd")
const DEFAULT := ["karthik_scooter", "bike", "auto", "hatchback", "sedan", "luxury_suv", "bus"]

var car: VehicleBody3D
var results: Array = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4000, 2, 4000)
	gs.shape = bx
	gs.position = Vector3(0, -1, 0)
	ground.add_child(gs)
	add_child(ground)
	_breaker(Vector3(400, 0, 0))                          # the bump lane: x = 400
	_breaker(Vector3(400, 0, 120))
	var light := DirectionalLight3D.new()
	add_child(light)
	var vehicles: Array = DEFAULT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vehicles="):
			vehicles = a.get_slice("=", 1).split(",")
	_run(vehicles)


## A speed breaker across the lane at p (the same profile as the city's).
func _breaker(p: Vector3) -> void:
	var prof := [[-1.5, 0.0], [-0.9, 0.06], [-0.3, 0.1], [0.3, 0.1], [0.9, 0.06], [1.5, 0.0]]
	var faces := PackedVector3Array()
	for i in prof.size() - 1:
		var a := Vector3(-6, prof[i][1], prof[i][0])
		var b := Vector3(6, prof[i][1], prof[i][0])
		var c := Vector3(6, prof[i + 1][1], prof[i + 1][0])
		var d := Vector3(-6, prof[i + 1][1], prof[i + 1][0])
		faces.append_array([a, c, b, a, d, c])
	var sh := ConcavePolygonShape3D.new()
	sh.set_faces(faces)
	sh.backface_collision = true
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = sh
	body.add_child(cs)
	body.position = p
	add_child(body)


func _run(vehicles: Array) -> void:
	for v in vehicles:
		await _vehicle(str(v))
	print("LAB done: %d runs" % results.size())
	get_tree().quit()


func _vehicle(kind: String) -> void:
	if car:
		car.queue_free()
		await get_tree().physics_frame
	car = Jeep.new()
	add_child(car)
	car.configure(kind)
	car.autopilot = true
	await _accel(kind)
	await _brake(kind, "brake", 1.0)
	await _brake(kind, "wet", 0.7)
	await _turn(kind)
	await _corner(kind)
	await _bump(kind, 20.0)
	await _bump(kind, 40.0)


func _place(at: Vector3) -> void:
	car.freeze = true
	car.global_transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.6)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.in_throttle = 0.0
	car.in_brake = 0.0
	car.in_steer = 0.0
	car.set_grip(1.0)
	await get_tree().physics_frame
	car.freeze = false
	for i in 90:                                          # settle on the springs
		await get_tree().physics_frame


func _report(kind: String, test: String, d: Dictionary) -> void:
	d["vehicle"] = kind
	d["test"] = test
	results.append(d)
	print("LAB " + JSON.stringify(d))


## Hold a speed (a plain cruise control on the autopilot's pedals).
func _cruise(target: float) -> void:
	var e: float = target - car.speed
	car.in_throttle = clampf(e * 0.6, 0.0, 1.0)
	car.in_brake = clampf(-e * 0.4, 0.0, 1.0)


func _accel(kind: String) -> void:
	await _place(Vector3(0, 0, -1800))
	var t := 0.0
	var t60 := -1.0
	var t100 := -1.0
	car.in_throttle = 1.0
	while t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t60 < 0.0 and car.speed >= 60.0 / 3.6:
			t60 = t
		if t100 < 0.0 and car.speed >= 100.0 / 3.6:
			t100 = t
		if "--labtrace" in OS.get_cmdline_user_args() and int(t * 60.0) % 60 == 0:
			print("TRACE t=%.0f v=%.1f gear=%d rpm=%.0f thr=%.2f eng=%.0f brake=%.1f" % [t, car.speed * 3.6, car.gear, car.rpm, car._thr, car.engine_force, car.brake])
	_report(kind, "accel", {"t0_60": snappedf(t60, 0.01), "t0_100": snappedf(t100, 0.01), "top_kmh": snappedf(car.speed * 3.6, 0.1)})


func _brake(kind: String, test: String, grip: float) -> void:
	await _place(Vector3(-200, 0, -1800))
	car.set_grip(grip)
	var t := 0.0
	while car.speed < 60.0 / 3.6 and t < 40.0:
		car.in_throttle = 1.0
		await get_tree().physics_frame
		t += 1.0 / 60.0
	if car.speed < 60.0 / 3.6 - 0.5:
		_report(kind, test, {"note": "never reached 60 km/h", "top_kmh": snappedf(car.speed * 3.6, 0.1)})
		return
	var from: Vector3 = car.global_position
	var tb := 0.0
	var pitch := 0.0
	car.in_throttle = 0.0
	car.in_brake = 1.0
	while car.speed > 0.3 and tb < 20.0:
		await get_tree().physics_frame
		tb += 1.0 / 60.0
		pitch = maxf(pitch, rad_to_deg(asin(clampf(-car.global_basis.z.y, -1.0, 1.0))))
	var dist := Vector2(car.global_position.x - from.x, car.global_position.z - from.z).length()
	_report(kind, test, {"dist_m": snappedf(dist, 0.1), "time_s": snappedf(tb, 0.01), "nose_dip_deg": snappedf(pitch, 0.1)})


func _turn(kind: String) -> void:
	await _place(Vector3(-600, 0, 0))
	var t := 0.0
	while t < 12.0:
		_cruise(10.0 / 3.6)
		car.in_steer = 1.0 if t > 2.0 else 0.0
		await get_tree().physics_frame
		t += 1.0 / 60.0
	var yaw: float = absf(car.angular_velocity.y)
	var r: float = absf(car.speed) / maxf(yaw, 0.001)
	_report(kind, "turn", {"radius_m": snappedf(r, 0.1), "speed_kmh": snappedf(car.speed * 3.6, 0.1)})


func _corner(kind: String) -> void:
	await _place(Vector3(-1200, 0, -1500))
	var t := 0.0
	while car.speed < 40.0 / 3.6 - 0.3 and t < 30.0:
		_cruise(40.0 / 3.6)
		await get_tree().physics_frame
		t += 1.0 / 60.0
	if car.speed < 40.0 / 3.6 - 1.0:
		_report(kind, "corner", {"note": "never reached 40 km/h"})
		return
	var lat := 0.0
	var roll := 0.0
	var spun := false
	var tc := 0.0
	while tc < 8.0:
		_cruise(40.0 / 3.6)
		car.in_steer = clampf(tc / 6.0, 0.0, 1.0)
		await get_tree().physics_frame
		tc += 1.0 / 60.0
		var v: Vector3 = car.linear_velocity
		var a: float = absf(v.length() * car.angular_velocity.y) / 9.81
		lat = maxf(lat, a)
		roll = maxf(roll, absf(rad_to_deg(asin(clampf(car.global_basis.x.y, -1.0, 1.0)))))
		var heading := Vector2(car.global_basis.z.x, car.global_basis.z.z).normalized()
		var moving := Vector2(v.x, v.z).normalized()
		if v.length() > 2.0 and heading.dot(moving) < cos(deg_to_rad(25.0)):
			spun = true
	_report(kind, "corner", {"max_lat_g": snappedf(lat, 0.01), "roll_deg": snappedf(roll, 0.1), "spun": spun})


func _bump(kind: String, kmh: float) -> void:
	var z0 := -150.0 if kmh < 30.0 else -30.0
	await _place(Vector3(400, 0, z0))
	var target := 0.0 if kmh < 30.0 else 120.0
	var t := 0.0
	var off := 0.0
	var jolt := 0.0
	var pitch := 0.0
	var passing := false
	while t < 40.0:
		_cruise(kmh / 3.6)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var z: float = car.global_position.z
		passing = absf(z - target) < 6.0
		if passing:
			var any := false
			for w in car._wheels:
				if (w as VehicleWheel3D).position.x != 0.0 and (w as VehicleWheel3D).is_in_contact():
					any = true
			if not any:
				off += 1.0 / 60.0
			jolt = maxf(jolt, car.jolt)
			pitch = maxf(pitch, absf(rad_to_deg(asin(clampf(-car.global_basis.z.y, -1.0, 1.0)))))
		if z > target + 10.0:
			break
	_report(kind, "bump%d" % int(kmh), {"airborne_s": snappedf(off, 0.01), "peak_jolt": snappedf(jolt, 0.1), "pitch_deg": snappedf(pitch, 0.1), "speed_kmh": snappedf(car.speed * 3.6, 0.1)})
