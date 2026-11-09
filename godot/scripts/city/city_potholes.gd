extends Node
## Potholes on the city's roads: placed by city_streamer.gd (`_potholes`, always the same ones in the same places:
## many on residential and unclassified streets, few on the big roads, none on flyovers), drawn with
## shaders/pothole.gdshader, and felt here. A wheel that drops into one:
##   the hole's far edge kicks that corner up (harder the faster, and the bigger the hole), the body jolts, the
##   suspension thuds, a little speed is lost; on a two-wheeler the bars twitch. Hit hard and fast (over ~45 km/h)
##   the front takes a little damage, as a rim or an alignment would.
## After rain they hold water (the material's `wet`, from city_weather.gd).
const Prof := preload("res://scripts/drive/prof.gd")

var city
var _inside := {}                          # wheel index → the pothole it's in (so one hole is one hit)
var _hits := 0


func _physics_process(_delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_timed(_delta)
	Prof.add("potholes_phys", _p0)


func _physics_process_timed(_delta: float) -> void:
	if city == null or city.car == null or city.streamer == null or not city.driving:
		return
	var st = city.streamer
	if st.pothole_mat and city.fines:
		st.pothole_mat.set_shader_parameter("wet", float(city.fines.sim.wet))
	var car = city.car
	var spd: float = absf(car.speed)
	for i in car._wheels.size():
		var w := car._wheels[i] as VehicleWheel3D
		if not w.is_in_contact():
			_inside.erase(i)
			continue
		var p: Vector3 = w.get_contact_point() if w.has_method("get_contact_point") else w.global_position
		var hole: Array = st.pothole_at(p)
		if hole.is_empty():
			_inside.erase(i)
			continue
		if _inside.get(i) == hole:
			continue
		_inside[i] = hole
		if spd > 1.0:
			_hit(car, w, float(hole[1]), spd)


func _hit(car, w: VehicleWheel3D, r: float, spd: float) -> void:
	_hits += 1
	var k := clampf(spd / 14.0, 0.0, 1.6) * clampf(r / 0.45, 0.5, 1.5)          # how hard: speed and size
	var at: Vector3 = w.global_position - car.global_position
	car.apply_impulse(Vector3.UP * car.mass * 0.9 * k, at)                     # (the far edge, under that wheel)
	car.apply_central_impulse(-car.linear_velocity.normalized() * car.mass * 0.35 * k)
	car.jolt = maxf(car.jolt, 18.0 + 40.0 * k)
	car._crash = maxf(car._crash, 0.12 + 0.18 * k)                            # (the thud, quieter than a crash)
	if car.two_wheeler:
		car.apply_torque_impulse(car.global_basis.z * car.mass * 0.25 * k * (1.0 if randf() < 0.5 else -1.0))
	if spd > 12.5 and k > 0.9:
		car.damage["front"] = minf(1.0, float(car.damage["front"]) + 0.03 * k)
		car._apply_damage()
	print("POTHOLE r %.2f m at %.0f km/h: kick %.2f" % [r, spd * 3.6, k])
