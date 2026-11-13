extends RefCounted
## Food as things on a plate (story/food.json dishes): a steel plate or a banana leaf, and on it what Amma made or
## the eatery served, built from shapes in code (no downloaded models): idlis as soft domes, a dosa folded half-moon,
## vadas as rings, pooris puffed, curries in steel katoris filled near the brim, rice in a mound. Each material has a
## little uneven colour (a shared noise texture) so nothing looks flat. The parts are what he eats: each one knows
## its bites and how it shrinks (a katori's level drops, a mound sinks, an idli goes piece by piece).
## These are made-in-code stand-ins for proper food models: good enough to read as the dish, not final art.
##   build(dish_id) → Node3D, its metadata "parts": [{node, bites, left, label, colour, how}]

const KATORI_R := 0.034

static var _mats := {}
static var _noise: NoiseTexture2D


static func _tex() -> NoiseTexture2D:
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
		var n := FastNoiseLite.new()
		n.frequency = 0.06
		n.fractal_octaves = 3
		_noise.noise = n
		var g := Gradient.new()                          # (the noise as a light-dark variation round 1.0)
		g.colors = PackedColorArray([Color(0.82, 0.82, 0.82), Color(1.0, 1.0, 1.0)])
		_noise.color_ramp = g
	return _noise


static func mat(key: String, col: Color, rough := 0.7, metal := 0.0, grain := true) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if grain:
		m.albedo_texture = _tex()
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(14, 14, 14)
	_mats[key] = m
	return m


static func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _dome(parent: Node3D, r: float, h: float, m: Material, pos: Vector3, sx := 1.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.is_hemisphere = true
	s.radial_segments = 24
	s.rings = 8
	return _mi(parent, s, m, pos, Vector3(sx, h / r, 1.0))


static func _disc(parent: Node3D, r: float, t: float, m: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = t
	c.radial_segments = 32
	return _mi(parent, c, m, pos + Vector3(0, t * 0.5, 0), scl, rot)


static func _ring(parent: Node3D, r: float, w: float, m: Material, pos: Vector3, flat := 0.55) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - w
	t.outer_radius = r
	t.rings = 24
	t.ring_segments = 12
	return _mi(parent, t, m, pos + Vector3(0, w * 0.5 * flat, 0), Vector3(1, flat, 1))


## A steel katori (small bowl) with a curry in it, filled near the brim; the curry is the part he eats from.
static func _katori(root: Node3D, parts: Array, pos: Vector3, key: String, col: Color, label: String, bites := 2) -> void:
	var c := CylinderMesh.new()
	c.top_radius = KATORI_R
	c.bottom_radius = KATORI_R * 0.72
	c.height = 0.034
	c.radial_segments = 28
	c.cap_top = false                                    # (open: the curry shows)
	var km := mat("steel_katori", Color(0.86, 0.87, 0.88), 0.3, 0.55, false)
	km.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(root, c, km, pos + Vector3(0, 0.017, 0))
	var f := _disc(root, KATORI_R * 0.94, 0.003, mat("curry_" + key, col, 0.25), pos + Vector3(0, 0.029, 0))
	parts.append({"node": f, "bites": bites, "left": bites, "label": label, "colour": col, "how": "level"})


static func _plate(root: Node3D, leaf: bool) -> void:
	if leaf:                                            # a banana leaf: long, its midrib down the middle
		var q := BoxMesh.new()
		q.size = Vector3(0.52, 0.002, 0.34)
		_mi(root, q, mat("banana_leaf", Color(0.2, 0.48, 0.16), 0.4), Vector3(0, 0.001, 0))
		var rib := BoxMesh.new()
		rib.size = Vector3(0.52, 0.003, 0.008)
		_mi(root, rib, mat("leaf_rib", Color(0.55, 0.68, 0.3), 0.5), Vector3(0, 0.002, -0.06))
		return
	var p := CylinderMesh.new()                          # a steel plate with a raised rim
	p.top_radius = 0.15
	p.bottom_radius = 0.14
	p.height = 0.006
	p.radial_segments = 40
	_mi(root, p, mat("steel_plate", Color(0.86, 0.87, 0.88), 0.3, 0.55, false), Vector3(0, 0.003, 0))
	_ring(root, 0.155, 0.012, mat("steel_plate", Color(0.86, 0.87, 0.88), 0.3, 0.55, false), Vector3(0, 0.004, 0), 0.9)


static func _add(parts: Array, node: Node3D, bites: int, label: String, col: Color, how := "shrink") -> void:
	parts.append({"node": node, "bites": bites, "left": bites, "label": label, "colour": col, "how": how})


## The dish, on its plate. +X is to the eater's right, -Z away from him (the curries beyond the main thing).
static func build(id: String, labels: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Dish_" + id
	var parts: Array = []
	var L := func(k: String, fallback: String) -> String: return str(labels.get(k, fallback))
	var white := Color(0.95, 0.94, 0.88)
	var golden := Color(0.82, 0.55, 0.24)
	var sambar := Color(0.78, 0.42, 0.12)
	var coconut := Color(0.94, 0.93, 0.82)
	var leafy := id in ["meals", "home_meals", "thali", "exec_lunch", "mini_meals"]
	_plate(root, leafy)
	match id:
		"idli", "idli_vada":
			var n := 4 if id == "idli" else 2
			for i in n:
				var a := float(i) / n * TAU + 0.4
				_add(parts, _dome(root, 0.034, 0.02, mat("idli", white, 0.8), Vector3(cos(a) * 0.05 + 0.01, 0.006, sin(a) * 0.04 + 0.02)), 2, L.call("idli", "idli"), white)
			if id == "idli_vada":
				_add(parts, _ring(root, 0.036, 0.022, mat("vada", Color(0.55, 0.3, 0.1), 0.55), Vector3(0.07, 0.006, 0.02)), 2, L.call("vada", "vada"), Color(0.55, 0.3, 0.1))
			_katori(root, parts, Vector3(-0.07, 0.006, -0.08), "sambar", sambar, L.call("sambar", "sambar"))
			_katori(root, parts, Vector3(0.03, 0.006, -0.1), "coconut", coconut, L.call("chutney", "chutney"))
		"dosa", "masala_dosa", "dosa_coffee":
			var roll := CylinderMesh.new()                   # rolled, as it comes off the tawa: crisp and golden
			roll.top_radius = 0.022
			roll.bottom_radius = 0.028
			roll.height = 0.26
			roll.radial_segments = 20
			var d := _mi(root, roll, mat("dosa", golden, 0.55), Vector3(0.0, 0.006 + 0.024, 0.025), Vector3(1, 0.85, 1), Vector3(0, 0.12, PI / 2))
			_add(parts, d, 4, L.call("dosa", "dosa"), golden)
			if id != "dosa":
				_add(parts, _dome(root, 0.026, 0.02, mat("masala", Color(0.9, 0.7, 0.2), 0.75), Vector3(-0.125, 0.006, 0.04)), 2, L.call("masala", "masala"), Color(0.9, 0.7, 0.2))
			_katori(root, parts, Vector3(-0.08, 0.006, -0.09), "sambar", sambar, L.call("sambar", "sambar"))
			_katori(root, parts, Vector3(0.0, 0.006, -0.11), "tomato", Color(0.78, 0.25, 0.12), L.call("chutney", "chutney"))
			if id == "dosa_coffee":
				_katori(root, parts, Vector3(0.09, 0.006, -0.09), "coffee", Color(0.55, 0.38, 0.22), L.call("coffee", "coffee"))
		"pongal":
			_add(parts, _dome(root, 0.06, 0.035, mat("pongal", Color(0.93, 0.86, 0.6), 0.8), Vector3(-0.01, 0.006, 0.02), 1.2), 4, L.call("pongal", "pongal"), Color(0.93, 0.86, 0.6))
			_add(parts, _ring(root, 0.034, 0.02, mat("vada", Color(0.55, 0.3, 0.1), 0.55), Vector3(0.08, 0.006, 0.03)), 2, L.call("vada", "vada"), Color(0.55, 0.3, 0.1))
			_katori(root, parts, Vector3(-0.07, 0.006, -0.09), "sambar", sambar, L.call("sambar", "sambar"))
			_katori(root, parts, Vector3(0.03, 0.006, -0.1), "coconut", coconut, L.call("chutney", "chutney"))
		"poori":
			for i in 3:
				_add(parts, _dome(root, 0.05, 0.026, mat("poori", Color(0.86, 0.6, 0.28), 0.5), Vector3(-0.04 + i * 0.04, 0.006 + i * 0.004, 0.03 - i * 0.012)), 2, L.call("poori", "poori"), Color(0.86, 0.6, 0.28))
			_add(parts, _dome(root, 0.04, 0.025, mat("masala", Color(0.9, 0.7, 0.2), 0.75), Vector3(0.0, 0.006, -0.08), 1.3), 3, L.call("masala", "masala"), Color(0.9, 0.7, 0.2))
		"upma":
			_add(parts, _dome(root, 0.065, 0.035, mat("upma", Color(0.92, 0.88, 0.72), 0.85), Vector3(0, 0.006, 0.01), 1.2), 5, L.call("upma", "upma"), Color(0.92, 0.88, 0.72))
			_katori(root, parts, Vector3(0.0, 0.006, -0.1), "coconut", coconut, L.call("chutney", "chutney"))
		"puttu":
			var c := CylinderMesh.new()
			c.top_radius = 0.035
			c.bottom_radius = 0.035
			c.height = 0.09
			_add(parts, _mi(root, c, mat("puttu", Color(0.95, 0.94, 0.9), 0.85), Vector3(0.02, 0.006 + 0.045, 0.02), Vector3.ONE, Vector3(0, 0, PI / 2)), 4, L.call("puttu", "puttu"), Color(0.95, 0.94, 0.9))
			_katori(root, parts, Vector3(-0.06, 0.006, -0.09), "kadala", Color(0.42, 0.22, 0.12), L.call("kadala", "kadala curry"), 3)
		"appam":
			for i in 2:
				var ap := _disc(root, 0.07, 0.006, mat("appam", Color(0.96, 0.94, 0.86), 0.75), Vector3(-0.035 + i * 0.07, 0.006 + i * 0.006, 0.03))
				_add(parts, ap, 2, L.call("appam", "appam"), Color(0.96, 0.94, 0.86))
			_katori(root, parts, Vector3(0.0, 0.006, -0.1), "stew", Color(0.95, 0.9, 0.78), L.call("stew", "stew"), 3)
		"chapati", "idiyappam":
			if id == "chapati":
				for i in 3:
					_add(parts, _disc(root, 0.075, 0.003, mat("chapati", Color(0.83, 0.66, 0.42), 0.8), Vector3(0.01, 0.007 + i * 0.003, 0.02)), 2, L.call("chapati", "chapati"), Color(0.83, 0.66, 0.42))
			else:
				for i in 3:
					var a := float(i) / 3.0 * TAU
					_add(parts, _ring(root, 0.03, 0.016, mat("idiyappam", Color(0.97, 0.96, 0.93), 0.85), Vector3(cos(a) * 0.045, 0.006, sin(a) * 0.035 + 0.02), 1.3), 2, L.call("idiyappam", "idiyappam"), Color(0.97, 0.96, 0.93))
			_katori(root, parts, Vector3(-0.05, 0.006, -0.1), "kurma", Color(0.85, 0.55, 0.25), L.call("kurma", "kurma"), 3)
		"parotta", "chicken_curry", "malabar_chicken":
			for i in 2:
				_add(parts, _disc(root, 0.07, 0.012, mat("parotta", golden, 0.6), Vector3(-0.025 + i * 0.045, 0.006 + i * 0.01, 0.025), Vector3.ONE, Vector3(0, 0, 0.1 * i)), 3, L.call("parotta", "parotta"), golden)
			var curry := Color(0.55, 0.25, 0.08) if id == "parotta" else Color(0.62, 0.22, 0.06)
			_katori(root, parts, Vector3(-0.05, 0.006, -0.1), "salna_" + id, curry, L.call("salna" if id == "parotta" else "curry", "salna"), 3)
		"paniyaram":
			for i in 6:
				var a := float(i) / 6.0 * TAU
				var s := SphereMesh.new()
				s.radius = 0.018
				s.height = 0.03
				_add(parts, _mi(root, s, mat("paniyaram", Color(0.8, 0.55, 0.25), 0.6), Vector3(cos(a) * 0.05, 0.02, sin(a) * 0.04 + 0.02)), 1, L.call("paniyaram", "paniyaram"), Color(0.8, 0.55, 0.25))
			_katori(root, parts, Vector3(0.0, 0.006, -0.1), "coconut", coconut, L.call("chutney", "chutney"))
		"kanji":
			_katori(root, parts, Vector3(0.0, 0.006, 0.0), "kanji", Color(0.93, 0.92, 0.86), L.call("kanji", "kanji"), 4)
			_add(parts, _dome(root, 0.015, 0.008, mat("pickle", Color(0.7, 0.18, 0.08), 0.5), Vector3(0.08, 0.006, 0.04)), 1, L.call("pickle", "pickle"), Color(0.7, 0.18, 0.08))
		_:                                              # rice dishes and meals
			var rc: Color = {"lemon_rice": Color(0.95, 0.82, 0.3), "tomato_rice": Color(0.85, 0.42, 0.2), "veg_rice": Color(0.9, 0.75, 0.45),
				"curd_rice": Color(0.97, 0.97, 0.94), "curd_pickle": Color(0.97, 0.97, 0.94), "fried_rice": Color(0.88, 0.75, 0.5)}.get(id, white)
			var y0 := 0.004
			var rm := mat("rice_" + id, rc, 0.85)
			rm.uv1_scale = Vector3(60, 60, 60)                # (fine grain: rice)
			_add(parts, _dome(root, 0.068, 0.028, rm, Vector3(0.0, y0, 0.03), 1.3), 5, L.call(id, "rice"), rc)
			if leafy or id in ["kuzhambu_rice", "jail_meals"]:
				var cur := [["sambar", sambar], ["rasam", Color(0.6, 0.2, 0.08)], ["poriyal", Color(0.42, 0.62, 0.22)], ["curd", Color(0.97, 0.97, 0.95)]]
				if id == "kuzhambu_rice":
					cur = [["kuzhambu", Color(0.45, 0.2, 0.08)], ["poriyal", Color(0.42, 0.62, 0.22)]]
				elif id == "jail_meals":
					cur = [["sambar", sambar]]
				for k in cur.size():
					_katori(root, parts, Vector3(-0.15 + k * 0.08, y0, -0.1), cur[k][0], cur[k][1], L.call(cur[k][0], cur[k][0]))
				if leafy:
					_disc(root, 0.045, 0.003, mat("appalam", Color(0.95, 0.85, 0.55), 0.6), Vector3(0.15, y0, 0.03))
			elif id in ["lemon_rice", "tomato_rice"]:
				_disc(root, 0.042, 0.003, mat("appalam", Color(0.95, 0.85, 0.55), 0.6), Vector3(0.09, y0, -0.06))
			if id in ["curd_rice", "curd_pickle", "lemon_rice"]:
				_add(parts, _dome(root, 0.015, 0.008, mat("pickle", Color(0.7, 0.18, 0.08), 0.5), Vector3(0.1, y0, 0.05)), 1, L.call("pickle", "pickle"), Color(0.7, 0.18, 0.08))
	root.set_meta("parts", parts)
	return root


## A bite of a part: one fewer left; it shows (an idli, a vada go smaller and smaller; a katori's level sinks; a mound
## sinks); with none left it's gone. Returns its colour (for the morsel in his fingers).
static func bite(part: Dictionary) -> Color:
	part["left"] = maxi(int(part["left"]) - 1, 0)
	var k := float(part["left"]) / maxf(float(part["bites"]), 1.0)
	var n: Node3D = part["node"]
	if part["how"] == "level":
		n.position.y -= 0.009 / maxf(float(part["bites"]), 1.0)
		n.scale = Vector3.ONE * lerpf(0.82, 1.0, k)
		n.visible = part["left"] > 0
	else:
		if not n.has_meta("s0"):
			n.set_meta("s0", n.scale)
		var s0: Vector3 = n.get_meta("s0")
		n.scale = Vector3(s0.x * lerpf(0.45, 1.0, k), s0.y * lerpf(0.4, 1.0, k), s0.z * lerpf(0.45, 1.0, k))
		n.visible = part["left"] > 0
	return part["colour"]
