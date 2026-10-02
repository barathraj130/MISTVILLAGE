extends Node3D
## Euro Truck-style cockpit kit added to whatever you drive: a real analog cluster behind the wheel
## (speedometer and rev counter with moving needles, fuel and temperature gauges, warning lights),
## two exterior mirrors with live views behind you, and wipers that sweep the screen in the rain.
## Only active in the cockpit view; backlit at night.

const MB := preload("res://scripts/drive/mesh_builder.gd")

var car                            # jeep.gd
var _speed_needle: Node3D
var _rpm_needle: Node3D
var _fuel_needle: Node3D
var _temp_needle: Node3D
var _lights := {}                  # name → StandardMaterial3D
var _face_mat: StandardMaterial3D
var _mirrors: Array = []           # [SubViewport, Camera3D, local mirror transform, outward]
var _wipers: Array = []            # pivot nodes
var _wipe_phase := 0.0
var wiping := false                # set by the game while it rains
var temp := 0.0                    # engine temperature 0..1 (warms up)
var active := false


func build(c, eye: Vector3, half_width: float, wiper_at: Vector3, wiper_len: float, cluster_at = null, analog := true) -> void:
	car = c
	var at: Vector3 = cluster_at if cluster_at != null else eye + Vector3(0, -0.27, 0.62)
	if analog:
		_build_cluster(at, eye)
	else:
		_speed_needle = null
	_build_roof(eye)
	# door mirrors: driver's (right, -X) and passenger's (left, +X), just outside the A-pillars
	_add_mirror(Vector3(-half_width - 0.08, eye.y - 0.22, eye.z + 0.78), eye, -1.0)
	_add_mirror(Vector3(half_width + 0.08, eye.y - 0.22, eye.z + 0.82), eye, 1.0)
	for sx in [-0.28, 0.32]:
		_add_wiper(wiper_at + Vector3(sx * wiper_len * 1.6, 0, 0), wiper_len)
	set_active(false)


# ----------------------------------------------------------------------------- cluster
func _build_cluster(at: Vector3, eye: Vector3) -> void:
	var cluster := Node3D.new()
	cluster.name = "Cluster"
	add_child(cluster)
	# face the driver's eyes
	var to_eye := (eye - at).normalized()
	cluster.transform = Transform3D(Basis.looking_at(-to_eye, Vector3.UP), at)
	_face_mat = StandardMaterial3D.new()
	_face_mat.vertex_color_use_as_albedo = true
	_face_mat.roughness = 0.6
	_face_mat.emission_enabled = true
	_face_mat.emission = Color(0.85, 0.95, 1.0)
	_face_mat.emission_energy_multiplier = 0.0
	var hood := MB.new()
	hood.box(Transform3D(Basis(), Vector3(0, 0.0, -0.025)), Vector3(0.42, 0.16, 0.04), Color(0.03, 0.03, 0.035))     # binnacle back
	hood.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.095, 0.03)), Vector3(0.44, 0.012, 0.09), Color(0.03, 0.03, 0.035))  # visor
	var hood_mi := MeshInstance3D.new()
	hood_mi.mesh = hood.commit()
	hood_mi.material_override = MB.vertex_color_material(0.7)
	cluster.add_child(hood_mi)
	_speed_needle = _dial(cluster, Vector3(-0.095, 0, 0), 0.068, 180, 20, "km/h")
	_rpm_needle = _dial(cluster, Vector3(0.095, 0, 0), 0.068, 5, 1, "×1000 rpm")
	_fuel_needle = _small_dial(cluster, Vector3(0.0, 0.035, 0), 0.026, "F", "E")
	_temp_needle = _small_dial(cluster, Vector3(0.0, -0.035, 0), 0.026, "H", "C")
	# warning lights along the bottom: ← indicator, high beam, handbrake, low fuel, indicator →
	var specs := [["left", Color(0.1, 1.0, 0.2), -0.17], ["beam", Color(0.2, 0.5, 1.0), -0.06],
		["brake", Color(1.0, 0.15, 0.1), 0.0], ["fuel", Color(1.0, 0.6, 0.05), 0.06], ["right", Color(0.1, 1.0, 0.2), 0.17]]
	for sp in specs:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.05, 0.05)
		m.emission_enabled = true
		m.emission = sp[1]
		m.emission_energy_multiplier = 0.0
		var lamp := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.009) if sp[0] in ["left", "right"] else Vector2(0.01, 0.01)
		lamp.mesh = q
		lamp.material_override = m
		lamp.position = Vector3(sp[2], -0.062, 0.006)
		cluster.add_child(lamp)
		_lights[sp[0]] = m


## A round gauge: dark face, 240° of ticks with numbers, a red needle. Returns the needle pivot.
func _dial(parent: Node3D, pos: Vector3, r: float, max_v: int, step: int, unit: String) -> Node3D:
	var mb := MB.new()                  # dark face and chrome ring (not lit)
	var tk := MB.new()                  # tick marks: these glow at night
	var segs := 28
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		mb.tri(Vector3.ZERO, Vector3(cos(a1), sin(a1), 0) * r, Vector3(cos(a0), sin(a0), 0) * r, Color(0.02, 0.02, 0.025), Vector3.BACK)
		mb.quad(Vector3(cos(a0), sin(a0), 0) * r, Vector3(cos(a1), sin(a1), 0) * r, Vector3(cos(a1), sin(a1), 0) * r * 1.08,
			Vector3(cos(a0), sin(a0), 0) * r * 1.08, Color(0.55, 0.56, 0.58), Vector3.BACK)          # chrome ring
	var ticks := max_v / step
	for t in range(ticks * 2 + 1):
		var f := float(t) / (ticks * 2)
		var ang := deg_to_rad(210.0 - 240.0 * f)
		var major := t % 2 == 0
		var dir := Vector3(cos(ang), sin(ang), 0)
		var inner := r * (0.78 if major else 0.86)
		var side := Vector3(-dir.y, dir.x, 0) * (0.0018 if major else 0.001)
		tk.quad(dir * inner - side, dir * inner + side, dir * r * 0.95 + side, dir * r * 0.95 - side, Color(0.92, 0.92, 0.9), Vector3.BACK)
		if major and t % (2 if ticks <= 6 else 4) == 0:
			var lbl := Label3D.new()
			lbl.text = str(int(t / 2 * step))
			lbl.font_size = 22
			lbl.pixel_size = 0.00028
			lbl.modulate = Color(0.95, 0.95, 0.92)
			lbl.position = pos + dir * r * 0.62 + Vector3(0, 0, 0.002)
			parent.add_child(lbl)
	var face := MeshInstance3D.new()
	face.mesh = mb.commit()
	face.material_override = MB.vertex_color_material(0.5)
	face.position = pos + Vector3(0, 0, 0.001)
	parent.add_child(face)
	var ticks_mi := MeshInstance3D.new()
	ticks_mi.mesh = tk.commit()
	ticks_mi.material_override = _face_mat
	ticks_mi.position = pos + Vector3(0, 0, 0.0015)
	parent.add_child(ticks_mi)
	var unit_lbl := Label3D.new()
	unit_lbl.text = unit
	unit_lbl.font_size = 16
	unit_lbl.pixel_size = 0.00028
	unit_lbl.modulate = Color(0.75, 0.75, 0.72)
	unit_lbl.position = pos + Vector3(0, -r * 0.4, 0.002)
	parent.add_child(unit_lbl)
	return _needle(parent, pos, r * 0.85)


func _small_dial(parent: Node3D, pos: Vector3, r: float, hi: String, lo: String) -> Node3D:
	var mb := MB.new()
	for k in 16:
		var a0 := TAU * k / 16
		var a1 := TAU * (k + 1) / 16
		mb.tri(Vector3.ZERO, Vector3(cos(a1), sin(a1), 0) * r, Vector3(cos(a0), sin(a0), 0) * r, Color(0.02, 0.02, 0.025), Vector3.BACK)
	var face := MeshInstance3D.new()
	face.mesh = mb.commit()
	face.material_override = MB.vertex_color_material(0.5)
	face.position = pos + Vector3(0, 0, 0.001)
	parent.add_child(face)
	for pair in [[hi, 0.6], [lo, -0.6]]:
		var l := Label3D.new()
		l.text = pair[0]
		l.font_size = 14
		l.pixel_size = 0.00028
		l.modulate = Color(0.9, 0.9, 0.88) if pair[0] != "H" else Color(1.0, 0.4, 0.3)
		l.position = pos + Vector3(-pair[1] * r * 0.75, r * 0.45, 0.002)
		parent.add_child(l)
	return _needle(parent, pos, r * 0.85)


func _needle(parent: Node3D, pos: Vector3, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, 0, 0.004)
	parent.add_child(pivot)
	var mb := MB.new()
	mb.quad(Vector3(-0.0016, -length * 0.15, 0), Vector3(0.0016, -length * 0.15, 0), Vector3(0.0006, length, 0),
		Vector3(-0.0006, length, 0), Color(1.0, 0.25, 0.1), Vector3.BACK)
	mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.001)), 0.005, 0.005, 0.003, Color(0.1, 0.1, 0.1), 10)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	var m := MB.vertex_color_material(0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.1)
	m.emission_energy_multiplier = 0.4
	mi.material_override = m
	pivot.add_child(mi)
	return pivot


# ----------------------------------------------------------------------------- roof
## Sun visors folded up against the headliner and an overhead console with switches and lamps.
func _build_roof(eye: Vector3) -> void:
	var mb := MB.new()
	var y := eye.y + 0.31
	for sx in [-1.0, 1.0]:
		var vx: float = float(sx) * 0.36
		mb.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(vx, y, eye.z + 0.5)), Vector3(0.4, 0.025, 0.17), Color(0.13, 0.12, 0.115))
		mb.box(Transform3D(Basis(), Vector3(vx + sx * 0.17, y + 0.015, eye.z + 0.58)), Vector3(0.03, 0.02, 0.03), Color(0.08, 0.08, 0.08))
	mb.box(Transform3D(Basis(), Vector3(0, y + 0.01, eye.z + 0.28)), Vector3(0.3, 0.05, 0.34), Color(0.06, 0.06, 0.065))   # console
	for k in 4:
		mb.box(Transform3D(Basis(), Vector3(-0.09 + k * 0.06, y - 0.017, eye.z + 0.36)), Vector3(0.035, 0.008, 0.05), Color(0.18, 0.18, 0.19))
	for sx in [-0.07, 0.07]:
		mb.box(Transform3D(Basis(), Vector3(sx, y - 0.017, eye.z + 0.2)), Vector3(0.08, 0.006, 0.05), Color(0.75, 0.72, 0.62))   # map lamps
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = MB.vertex_color_material(0.8)
	add_child(mi)


# ----------------------------------------------------------------------------- mirrors
func _add_mirror(pos: Vector3, eye: Vector3, outward: float) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(170, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 44.0
	cam.far = 600.0
	vp.add_child(cam)
	var mirror := Node3D.new()
	mirror.position = pos
	var to_eye := (eye - pos)
	to_eye.y = 0.0
	mirror.basis = Basis.looking_at(-to_eye.normalized(), Vector3.UP)
	add_child(mirror)
	var housing := MB.new()
	housing.box(Transform3D(Basis(), Vector3(0, 0, -0.03)), Vector3(0.19, 0.33, 0.06), Color(0.03, 0.03, 0.035))
	housing.box(Transform3D(Basis(), Vector3(-outward * 0.12, -0.02, -0.03)), Vector3(0.08, 0.03, 0.03), Color(0.03, 0.03, 0.035))
	var hmi := MeshInstance3D.new()
	hmi.mesh = housing.commit()
	hmi.material_override = MB.vertex_color_material(0.6)
	mirror.add_child(hmi)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.17, 0.31)
	glass.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = vp.get_texture()
	gm.uv1_scale = Vector3(-1, 1, 1)                 # a mirror flips left-right
	gm.uv1_offset = Vector3(1, 0, 0)
	glass.material_override = gm
	glass.position = Vector3(0, 0, 0.002)
	mirror.add_child(glass)
	_mirrors.append([vp, cam, pos, outward])


# ----------------------------------------------------------------------------- wipers
func _add_wiper(base: Vector3, length: float) -> void:
	var pivot := Node3D.new()
	pivot.position = base
	add_child(pivot)
	var mb := MB.new()
	mb.box(Transform3D(Basis(), Vector3(0, length * 0.5, 0)), Vector3(0.012, length, 0.012), Color(0.02, 0.02, 0.02))
	mb.box(Transform3D(Basis(), Vector3(0, length * 0.55, 0.008)), Vector3(0.02, length * 0.9, 0.01), Color(0.04, 0.04, 0.04))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = MB.vertex_color_material(0.5)
	pivot.add_child(mi)
	# lie along the screen's slope, parked flat at the bottom
	pivot.rotation = Vector3(deg_to_rad(-35.0), 0, deg_to_rad(80.0))
	_wipers.append(pivot)


# ----------------------------------------------------------------------------- per frame
func set_active(on: bool) -> void:
	active = on
	for m in _mirrors:
		(m[0] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for c in get_children():
		if c is Node3D and not c in _wipers:
			(c as Node3D).visible = on


func update(delta: float, night: float, fuel_frac: float) -> void:
	# wipers sweep whenever it rains (seen from outside too)
	if wiping or _wipe_phase > 0.0:
		_wipe_phase = fmod(_wipe_phase + delta * 1.1, 1.0) if wiping else maxf(_wipe_phase + delta * 1.1, 0.0)
		if not wiping and _wipe_phase >= 0.999:
			_wipe_phase = 0.0
	var sweep := sin(_wipe_phase * PI) * deg_to_rad(95.0)
	for w in _wipers:
		w.rotation.z = deg_to_rad(80.0) - sweep
	if not active:
		return
	_update_mirrors()
	if _speed_needle == null:
		return
	var kmh := absf(car.speed) * 3.6
	# needles point along +Y; a tick at angle a (from +X, anticlockwise) needs a turn of a − 90°
	_speed_needle.rotation.z = deg_to_rad(210.0 - 240.0 * clampf(kmh / 180.0, 0.0, 1.0)) - PI * 0.5
	_rpm_needle.rotation.z = deg_to_rad(210.0 - 240.0 * clampf(car.rpm / 5000.0, 0.0, 1.0)) - PI * 0.5
	temp = move_toward(temp, 0.55 if not car.out_of_fuel else 0.3, delta * 0.01)
	_fuel_needle.rotation.z = lerpf(deg_to_rad(60.0), deg_to_rad(-60.0), fuel_frac)
	_temp_needle.rotation.z = lerpf(deg_to_rad(60.0), deg_to_rad(-60.0), temp)
	_face_mat.emission_energy_multiplier = 1.6 * night + (0.6 if car.lights_on else 0.0)
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.66) < 0.36
	_lights["left"].emission_energy_multiplier = 4.0 if blink and (car.indicator == 1 or car.indicator == 2) else 0.0
	_lights["right"].emission_energy_multiplier = 4.0 if blink and (car.indicator == -1 or car.indicator == 2) else 0.0
	_lights["beam"].emission_energy_multiplier = 3.0 if car.lights_on else 0.0
	_lights["brake"].emission_energy_multiplier = 3.0 if car.in_handbrake else 0.0
	_lights["fuel"].emission_energy_multiplier = 3.0 if fuel_frac < 0.12 else 0.0


func _update_mirrors() -> void:
	# mirror cameras look back past the car's flanks
	var xf: Transform3D = car.global_transform
	for m in _mirrors:
		var cam: Camera3D = m[1]
		var p: Vector3 = xf * (m[2] as Vector3)
		var back: Vector3 = -xf.basis.z.normalized()
		var side: Vector3 = xf.basis.x.normalized() * float(m[3])
		cam.global_transform = Transform3D(Basis.looking_at(back + side * 0.18 + Vector3(0, -0.05, 0), Vector3.UP), p)
