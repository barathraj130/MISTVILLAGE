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
## What a hand must not go into, on this dish: {node, r, h, at (in the node), kind: "cyl"}: the plate's disc, each
## katori, a bowl, a tumbler (its node moves with it when it's lifted). eater.gd hands them to eat_ik.gd's contact.
static func _solid(root: Node3D, node: Node3D, r: float, h: float, at := Vector3.ZERO, kind := "cup") -> void:
	var sl: Array = root.get_meta("solids", [])
	sl.append({"node": node, "r": r, "h": h, "at": at, "kind": kind})
	root.set_meta("solids", sl)


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
	_solid(root, root, KATORI_R, 0.034, pos)
	var f := _disc(root, KATORI_R * 0.94, 0.003, mat("curry_" + key, col, 0.25), pos + Vector3(0, 0.029, 0))
	parts.append({"node": f, "bites": bites, "left": bites, "label": label, "colour": col, "how": "level"})


static func _plate(root: Node3D, leaf: bool) -> void:
	_solid(root, root, 0.158 if not leaf else 0.17, 0.0 if not leaf else -0.004, Vector3.ZERO, "cyl")   # (its face, at the
	                                                     #  food's foot: the fingers' centre kept a finger's half-thickness over it)
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


const DRINKS := ["tea", "filter_coffee", "fresh_lime"]


## A tumbler or a glass with a drink in it: a node of its own (what his hand lifts: the part's "lift"), the liquid
## the part (its level goes down a sip at a time). kind: "steel" (a filter-coffee tumbler), "glass_small" (a tea-shop
## glass), "glass_tall" (a lime juice glass).
static func _tumbler(root: Node3D, parts: Array, pos: Vector3, key: String, col: Color, label: String, kind: String) -> void:
	var cup := Node3D.new()
	cup.name = "Cup_" + key
	root.add_child(cup)
	cup.position = pos
	var h: float = {"steel": 0.085, "glass_small": 0.075, "glass_tall": 0.13}[kind]
	var r: float = {"steel": 0.03, "glass_small": 0.029, "glass_tall": 0.033}[kind]
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * (0.8 if kind == "steel" else 0.85)
	c.height = h
	c.radial_segments = 28
	c.cap_top = false
	var m: StandardMaterial3D
	if kind == "steel":
		m = mat("steel_tumbler_open", Color(0.86, 0.87, 0.88), 0.3, 0.55, false)
	else:
		m = mat("glass_" + kind, Color(0.88, 0.94, 0.96, 0.3), 0.05, 0.0, false)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(cup, c, m, Vector3(0, h * 0.5, 0))
	_solid(root, cup, r, h)
	var lv := h * (0.82 if kind != "steel" else 0.78)
	var liquid := CylinderMesh.new()                     # (the drink: a column from the bottom up to its level; a
	liquid.top_radius = r * 0.93                         #  sip shortens it: Kit.bite "fill")
	liquid.bottom_radius = r * 0.93 * (0.8 if kind == "steel" else 0.85)
	liquid.height = lv
	var lm := mat("drink_" + key, col, 0.15, 0.0, false)
	if col.a < 1.0:
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pivot := Node3D.new()
	cup.add_child(pivot)
	pivot.position = Vector3(0, 0.003, 0)
	_mi(pivot, liquid, lm, Vector3(0, lv * 0.5, 0))
	parts.append({"node": pivot, "bites": 4, "left": 4, "label": label, "colour": col, "how": "fill",
		"eat": "sip_glass" if kind == "glass_tall" else "sip_cup", "lift": cup, "cup_h": h})


static func _davara(root: Node3D, pos: Vector3) -> void:
	var d := CylinderMesh.new()
	d.top_radius = 0.055
	d.bottom_radius = 0.04
	d.height = 0.03
	d.cap_top = false
	var m := mat("steel_davara", Color(0.86, 0.87, 0.88), 0.3, 0.55, false)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(root, d, m, pos + Vector3(0, 0.015, 0))
	_solid(root, root, 0.055, 0.03, pos)


## A spoon or a fork, its origin where the fingers hold the handle, its +Y along the handle toward the bowl or the
## tines, its +Z up (the bowl's hollow faces +Z).
static func utensil(kind: String) -> Node3D:
	var u := Node3D.new()
	u.name = "Utensil_" + kind
	var steel := mat("steel_cutlery", Color(0.88, 0.89, 0.9), 0.22, 0.75, false)
	var hd := BoxMesh.new()
	hd.size = Vector3(0.009, 0.12, 0.0025)
	_mi(u, hd, steel, Vector3(0, 0.03, 0))
	if kind == "fork":
		for i in 4:
			var t := BoxMesh.new()
			t.size = Vector3(0.0018, 0.035, 0.0018)
			_mi(u, t, steel, Vector3(-0.0055 + i * 0.0037, 0.105, 0.002))
		var nk := BoxMesh.new()
		nk.size = Vector3(0.016, 0.01, 0.0025)
		_mi(u, nk, steel, Vector3(0, 0.09, 0.001))
	else:
		var b := SphereMesh.new()
		b.radius = 0.016
		b.height = 0.032
		b.is_hemisphere = true
		_mi(u, b, steel, Vector3(0, 0.1, 0.0), Vector3(0.85, 0.35, 1.25), Vector3(PI, 0, 0))
	return u


## A spoon or a fork laid on the plate beside the food: the dish's "utensil" (the eater picks it up for the first
## bite and puts it back after the last).
static func _lay_utensil(root: Node3D, kind: String, pos: Vector3) -> void:
	var u := utensil(kind)
	root.add_child(u)
	u.position = pos
	u.rotation = Vector3(-PI / 2, 0.15, 0)                # (flat, the handle toward him)
	root.set_meta("utensil", u)
	root.set_meta("utensil_kind", kind)


## A wedge (a pizza slice): its tip at the origin pointing -Z, `length` long, `angle` wide, `t` thick.
static func _wedge(length: float, angle: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	var pts: Array[Vector3] = [Vector3.ZERO]
	for i in n + 1:
		var a := -angle * 0.5 + angle * float(i) / float(n)
		pts.append(Vector3(sin(a) * length, 0, cos(a) * length))
	for y in [t, 0.0]:
		st.set_normal(Vector3.UP if y > 0.0 else Vector3.DOWN)
		for i in n:
			var a: Vector3 = pts[0] + Vector3(0, y, 0)
			var b: Vector3 = pts[i + 1] + Vector3(0, y, 0)
			var c: Vector3 = pts[i + 2] + Vector3(0, y, 0)
			if y > 0.0:
				st.add_vertex(a)
				st.add_vertex(c)
				st.add_vertex(b)
			else:
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(c)
	for i in pts.size():                                 # (the sides and the crust's edge)
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		st.set_normal(((a + b) * 0.5).normalized() if (a + b).length() > 0.001 else Vector3.FORWARD)
		st.add_vertex(a)
		st.add_vertex(b + Vector3(0, t, 0))
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(a + Vector3(0, t, 0))
		st.add_vertex(b + Vector3(0, t, 0))
	return st.commit()


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
	if not id in DRINKS:                                 # (a drink comes as it is: a glass, a tumbler on the table)
		_plate(root, leafy)
	match id:
		"tea":                                          # a tea-shop glass: milky tea
			_tumbler(root, parts, Vector3(0.0, 0.0, 0.0), "tea", Color(0.74, 0.55, 0.36), L.call("tea", "tea"), "glass_small")
		"filter_coffee":                                # a steel tumbler in its davara
			_davara(root, Vector3(0.0, 0.0, 0.0))
			_tumbler(root, parts, Vector3(0.0, 0.012, 0.0), "coffee", Color(0.62, 0.43, 0.27), L.call("coffee", "coffee"), "steel")
		"fresh_lime":                                   # a tall glass, pale and cloudy
			_tumbler(root, parts, Vector3(0.0, 0.0, 0.0), "lime", Color(0.86, 0.9, 0.62, 0.85), L.call("lime", "fresh lime"), "glass_tall")
		"payasam", "kanji":                             # in a katori, with a spoon
			var col := Color(0.93, 0.85, 0.66) if id == "payasam" else Color(0.93, 0.92, 0.86)
			_katori(root, parts, Vector3(0.0, 0.006, 0.0), id, col, L.call(id, id), 4)
			(parts[-1] as Dictionary)["eat"] = "spoon"
			if id == "kanji":
				_add(parts, _dome(root, 0.015, 0.008, mat("pickle", Color(0.7, 0.18, 0.08), 0.5), Vector3(0.08, 0.006, 0.04)), 1, L.call("pickle", "pickle"), Color(0.7, 0.18, 0.08))
			_lay_utensil(root, "spoon", Vector3(0.075, 0.008, 0.0))
		"burger":                                       # a burger and fries, ketchup in a small dish
			var b := Node3D.new()
			root.add_child(b)
			b.position = Vector3(-0.02, 0.006, 0.02)
			var bun := Color(0.78, 0.5, 0.22)
			_disc(b, 0.048, 0.016, mat("bun_bottom", bun, 0.6), Vector3.ZERO)
			_disc(b, 0.05, 0.012, mat("patty", Color(0.3, 0.17, 0.09), 0.7), Vector3(0, 0.016, 0))
			_disc(b, 0.052, 0.003, mat("lettuce", Color(0.45, 0.68, 0.22), 0.6), Vector3(0, 0.028, 0))
			var ch := BoxMesh.new()
			ch.size = Vector3(0.075, 0.003, 0.075)
			_mi(b, ch, mat("cheese", Color(0.98, 0.78, 0.25), 0.4), Vector3(0, 0.032, 0), Vector3.ONE, Vector3(0, 0.6, 0))
			_dome(b, 0.05, 0.03, mat("bun_top", Color(0.82, 0.52, 0.2), 0.5), Vector3(0, 0.034, 0))
			parts.append({"node": b, "bites": 5, "left": 5, "label": L.call("burger", "burger"), "colour": bun, "how": "shrink", "eat": "hold_two", "lift": b})
			for i in 6:                                  # (fries: a little heap)
				var f := BoxMesh.new()
				f.size = Vector3(0.008, 0.008, 0.06)
				_add(parts, _mi(root, f, mat("fries", Color(0.95, 0.78, 0.35), 0.6), Vector3(0.1 + (i % 3) * 0.012, 0.012 + (i / 3) * 0.008, -0.03 + (i % 2) * 0.01), Vector3.ONE, Vector3(0, 0.3 * i - 0.6, 0)), 1, L.call("fries", "fries"), Color(0.95, 0.78, 0.35))
			_katori(root, parts, Vector3(0.07, 0.006, -0.08), "ketchup", Color(0.7, 0.08, 0.05), L.call("ketchup", "ketchup"), 2)
		"pizza":                                        # three slices on the plate, the tips toward the middle
			for i in 3:
				var sl := Node3D.new()
				root.add_child(sl)
				var a := -0.75 + float(i) * 0.75             # (fanned on the plate, the tips in, the crusts out)
				sl.position = Vector3(sin(a) * 0.02, 0.006 + i * 0.002, cos(a) * 0.02 - 0.01)
				sl.rotation.y = a
				var w := _mi(sl, _wedge(0.13, 0.7, 0.008), mat("pizza", Color(0.93, 0.66, 0.3), 0.6), Vector3.ZERO)
				_mi(sl, _wedge(0.118, 0.64, 0.003), mat("pizza_top", Color(0.85, 0.3, 0.12), 0.5), Vector3(0, 0.008, 0.002))
				parts.append({"node": sl, "bites": 3, "left": 3, "label": L.call("pizza", "pizza"), "colour": Color(0.93, 0.66, 0.3), "how": "shrink", "eat": "hold_one", "lift": sl})
				w.set_meta("crust", true)
		"noodles":                                      # in a deep bowl, a fork beside it
			var bw := CylinderMesh.new()
			bw.top_radius = 0.075
			bw.bottom_radius = 0.045
			bw.height = 0.05
			bw.cap_top = false
			bw.radial_segments = 32
			var bm := mat("bowl_white", Color(0.95, 0.95, 0.93), 0.25, 0.0, false)
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mi(root, bw, bm, Vector3(0, 0.031, 0))
			_solid(root, root, 0.075, 0.056)
			var nd := Node3D.new()
			root.add_child(nd)
			nd.position = Vector3(0, 0.045, 0)
			var nc := Color(0.92, 0.78, 0.45)
			for i in 9:                                  # (strands tangled in a heap: thin rings, tipped every way)
				var t := TorusMesh.new()
				t.inner_radius = 0.022 + (i % 3) * 0.006
				t.outer_radius = t.inner_radius + 0.004
				t.rings = 16
				t.ring_segments = 6
				_mi(nd, t, mat("noodles", nc, 0.5), Vector3((i % 3 - 1) * 0.012, (i / 3) * 0.006, ((i * 7) % 3 - 1) * 0.01), Vector3.ONE, Vector3(0.5 * i, 0.9 * i, 0.3 * i))
			_add(parts, nd, 5, L.call("noodles", "noodles"), nc)
			(parts[-1] as Dictionary)["eat"] = "fork"
			_lay_utensil(root, "fork", Vector3(0.105, 0.008, 0.0))
		"ice_cream":                                    # two scoops in a glass cup, a spoon in it
			var cp := CylinderMesh.new()
			cp.top_radius = 0.045
			cp.bottom_radius = 0.03
			cp.height = 0.045
			cp.cap_top = false
			var gm := mat("glass_cup", Color(0.85, 0.92, 0.95, 0.35), 0.05, 0.0, false)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mi(root, cp, gm, Vector3(0, 0.0285, 0))
			_solid(root, root, 0.045, 0.051)
			var ic := Node3D.new()
			root.add_child(ic)
			ic.position = Vector3(0, 0.05, 0)
			var s1 := SphereMesh.new()
			s1.radius = 0.028
			s1.height = 0.05
			_mi(ic, s1, mat("vanilla", Color(0.97, 0.93, 0.8), 0.7), Vector3(-0.012, 0.0, 0))
			_mi(ic, s1, mat("strawberry", Color(0.95, 0.65, 0.68), 0.7), Vector3(0.014, 0.008, 0.004))
			_add(parts, ic, 4, L.call("ice_cream", "ice cream"), Color(0.97, 0.9, 0.82))
			(parts[-1] as Dictionary)["eat"] = "spoon"
			_lay_utensil(root, "spoon", Vector3(0.09, 0.008, 0.0))
		"idli", "idli_vada", "vada":
			var n: int = {"idli": 4, "idli_vada": 2, "vada": 0}[id]
			for i in n:
				var a := float(i) / n * TAU + 0.4
				_add(parts, _dome(root, 0.034, 0.02, mat("idli", white, 0.8), Vector3(cos(a) * 0.05 + 0.01, 0.006, sin(a) * 0.04 + 0.02)), 2, L.call("idli", "idli"), white)
			if id == "idli_vada":
				_add(parts, _ring(root, 0.036, 0.022, mat("vada", Color(0.55, 0.3, 0.1), 0.55), Vector3(0.07, 0.006, 0.02)), 2, L.call("vada", "vada"), Color(0.55, 0.3, 0.1))
			if id == "vada":                             # (two medu vadas, the sambar and chutney beside)
				for i in 2:
					_add(parts, _ring(root, 0.036, 0.022, mat("vada", Color(0.55, 0.3, 0.1), 0.55), Vector3(-0.035 + i * 0.075, 0.006, 0.025)), 2, L.call("vada", "vada"), Color(0.55, 0.3, 0.1))
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
			if id == "dosa_coffee":                       # (the coffee in its tumbler beside the plate)
				_tumbler(root, parts, Vector3(0.21, -0.006, -0.06), "coffee", Color(0.62, 0.43, 0.27), L.call("coffee", "coffee"), "steel")
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
		_:                                              # rice dishes and meals
			var rc: Color = {"lemon_rice": Color(0.95, 0.82, 0.3), "tomato_rice": Color(0.85, 0.42, 0.2), "veg_rice": Color(0.9, 0.75, 0.45),
				"curd_rice": Color(0.97, 0.97, 0.94), "curd_pickle": Color(0.97, 0.97, 0.94), "fried_rice": Color(0.88, 0.75, 0.5)}.get(id, white)
			var y0 := 0.004
			var rm := mat("rice_" + id, rc, 0.85)
			rm.uv1_scale = Vector3(60, 60, 60)                # (fine grain: rice)
			_add(parts, _dome(root, 0.068, 0.028, rm, Vector3(0.0, y0, 0.03), 1.3), 5, L.call(id, "rice"), rc)
			if id == "fried_rice":                       # (eaten with a spoon, as it's served)
				(parts[-1] as Dictionary)["eat"] = "spoon"
				_lay_utensil(root, "spoon", Vector3(0.12, y0 + 0.004, 0.0))
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
	root.set_meta("dish", id)
	return root


## A bite of a part: one fewer left; it shows (an idli, a vada go smaller and smaller; a katori's level sinks; a mound
## sinks); with none left it's gone. Returns its colour (for the morsel in his fingers).
static func bite(part: Dictionary) -> Color:
	part["left"] = maxi(int(part["left"]) - 1, 0)
	var k := float(part["left"]) / maxf(float(part["bites"]), 1.0)
	var n: Node3D = part["node"]
	if part["how"] == "fill":                            # (a drink: the column a sip shorter, a little left at the end)
		n.scale = Vector3(1.0, lerpf(0.06, 1.0, k), 1.0)
		n.visible = true
	elif part["how"] == "level":
		n.position.y -= float(part.get("drop", 0.009)) / maxf(float(part["bites"]), 1.0)
		n.scale = Vector3.ONE * lerpf(float(part.get("narrow", 0.82)), 1.0, k)
		n.visible = part["left"] > 0
	else:
		if not n.has_meta("s0"):
			n.set_meta("s0", n.scale)
		var s0: Vector3 = n.get_meta("s0")
		n.scale = Vector3(s0.x * lerpf(0.45, 1.0, k), s0.y * lerpf(0.4, 1.0, k), s0.z * lerpf(0.45, 1.0, k))
		n.visible = part["left"] > 0
	return part["colour"]
