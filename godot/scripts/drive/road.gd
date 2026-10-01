extends Node3D
## Road surface and markings, red-earth shoulders, stone retaining walls on cuttings,
## black-and-yellow parapets on drops and hairpins, the Bhavani bridge and river,
## milestones and road signs. Road, walls and parapets have collision.

const Route := preload("res://scripts/drive/route.gd")
const Terrain := preload("res://scripts/drive/terrain.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const TEX := "res://assets/models/textures/"
const HALF := 3.6
const SHOULDER := 1.4
const WALL_OFF := 5.1
const PARAPET_OFF := 4.6
const CHUNK := 300                         # samples per road mesh (~600 m)

const WHITE := Color(0.82, 0.82, 0.78)
const YELLOW := Color(0.85, 0.62, 0.04)
const BLACK := Color(0.025, 0.025, 0.025)
const DIRT := Color(0.62, 0.36, 0.24)
const CONCRETE := Color(0.55, 0.54, 0.5)

var route: Route
var terrain: Terrain
var mat_asphalt: StandardMaterial3D
var mat_wall: StandardMaterial3D
var mat_vc: StandardMaterial3D
var mat_water: StandardMaterial3D
var mat_gravel: StandardMaterial3D
var mat_concrete: StandardMaterial3D
var body: StaticBody3D
var labels: Node3D
var bumps: Array = []                     # distances of speed breakers (the autopilot slows for them)


func build(r, t) -> void:
	route = r
	terrain = t
	_materials()
	body = StaticBody3D.new()
	body.name = "RoadCollision"
	add_child(body)
	labels = Node3D.new()
	labels.name = "Signs"
	add_child(labels)
	_surface()
	_walls()
	_bridge()
	_signs()
	_town_details()


func _tex_mat(tex_name: String, rough: float, uv_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + tex_name + "_base.jpg"):
		m.albedo_texture = load(TEX + tex_name + "_base.jpg")
	if ResourceLoader.exists(TEX + tex_name + "_normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(TEX + tex_name + "_normal.png")
	m.roughness = rough
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _materials() -> void:
	if ResourceLoader.exists("res://assets/drive/tex/asphalt_color.jpg"):
		mat_asphalt = StandardMaterial3D.new()
		mat_asphalt.albedo_texture = load("res://assets/drive/tex/asphalt_color.jpg")
		mat_asphalt.normal_enabled = true
		mat_asphalt.normal_texture = load("res://assets/drive/tex/asphalt_normal.jpg")
		mat_asphalt.roughness_texture = load("res://assets/drive/tex/asphalt_rough.jpg")
		mat_asphalt.albedo_color = Color(0.62, 0.62, 0.64)
		mat_asphalt.uv1_scale = Vector3(1.5, 1.5, 1.0)          # UVs are in 6 m units → 4 m tiles
		mat_asphalt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		mat_asphalt = _tex_mat("wet_mountain_asphalt", 0.75)
		mat_asphalt.albedo_color = Color(0.85, 0.85, 0.85)
	mat_gravel = MB.cc0_material("gravel", 3.0, 1.0)
	mat_concrete = MB.cc0_material("concrete", 2.5, 0.85)
	mat_wall = _tex_mat("stone_retaining_wall", 0.9)
	mat_vc = MB.vertex_color_material(0.8)
	mat_water = StandardMaterial3D.new()
	mat_water.albedo_color = Color(0.04, 0.10, 0.10)
	mat_water.roughness = 0.06
	mat_water.metallic_specular = 0.8


## Rain soaks the tarmac: darker and glossy (sky and lamps reflect in it), drying slowly after.
func set_wet(w: float) -> void:
	if mat_asphalt:
		mat_asphalt.roughness = lerpf(1.0, 0.22, w)
		mat_asphalt.albedo_color = Color(0.62, 0.62, 0.64) * lerpf(1.0, 0.55, w)
		mat_asphalt.metallic_specular = lerpf(0.5, 0.75, w)
		mat_asphalt.normal_scale = lerpf(1.0, 0.25, w)          # water fills the texture
	if mat_concrete:
		mat_concrete.roughness = lerpf(0.85, 0.4, w)


func _add(mb, mat: Material, collide: bool, node_name := "") -> MeshInstance3D:
	if mb.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat
	if node_name != "":
		mi.name = node_name
	mi.visibility_range_end = 1600.0
	mi.visibility_range_end_margin = 100.0
	if mat != mat_wall:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # flat road surfaces cast nothing useful
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
	return mi


# ----------------------------------------------------------------------------- surface + markings
func _surface() -> void:
	var n: int = route.pts.size()
	var ghat0: float = route.marks["ghat_start"]
	var ghat1: float = route.marks["ghat_end"]
	var i0 := 0
	while i0 < n - 1:
		var i1 := mini(i0 + CHUNK, n - 1)
		var asphalt := MB.new()
		var shoulder := MB.new()
		var lines := MB.new()
		for i in range(i0, i1):
			var j := i + 1
			var ci: Vector3 = route.pts[i]
			var cj: Vector3 = route.pts[j]
			var li: Vector3 = route.left(i)
			var lj: Vector3 = route.left(j)
			var di: float = route.dist[i]
			var dj: float = route.dist[j]
			asphalt.quad(ci + li * HALF, ci - li * HALF, cj - lj * HALF, cj + lj * HALF, Color.WHITE, Vector3.UP,
				Vector2(0.0, di / 6.0), Vector2(7.2 / 6.0, di / 6.0), Vector2(7.2 / 6.0, dj / 6.0), Vector2(0.0, dj / 6.0))
			for s in [1.0, -1.0]:
				var e0: Vector3 = ci + li * HALF * s
				var e1: Vector3 = cj + lj * HALF * s
				var o0: Vector3 = ci + li * (HALF + SHOULDER) * s + Vector3(0, -0.4, 0)
				var o1: Vector3 = cj + lj * (HALF + SHOULDER) * s + Vector3(0, -0.4, 0)
				shoulder.quad(e0, o0, o1, e1, DIRT, Vector3.UP)
				# solid edge line
				_stripe(lines, ci, cj, li, lj, (HALF - 0.3) * s, 0.12, WHITE)
			# centre: solid yellow on the ghat (no overtaking), dashed white elsewhere
			if di > ghat0 and di < ghat1:
				_stripe(lines, ci, cj, li, lj, 0.1, 0.1, YELLOW)
				_stripe(lines, ci, cj, li, lj, -0.1, 0.1, YELLOW)
			elif fmod(di, 9.0) < 4.5:
				_stripe(lines, ci, cj, li, lj, 0.0, 0.12, WHITE)
		_add(asphalt, mat_asphalt, true, "Road_%d" % i0)
		_add(shoulder, mat_gravel, true)
		_add(lines, mat_vc, false)
		i0 = i1


func _stripe(mb, ci: Vector3, cj: Vector3, li: Vector3, lj: Vector3, off: float, w: float, col: Color) -> void:
	var up := Vector3(0, 0.02, 0)
	mb.quad(ci + li * (off + w * 0.5) + up, ci + li * (off - w * 0.5) + up,
		cj + lj * (off - w * 0.5) + up, cj + lj * (off + w * 0.5) + up, col, Vector3.UP)


# ----------------------------------------------------------------------------- walls + parapets
func _walls() -> void:
	var n: int = route.pts.size()
	var towns := ["coimbatore", "mettupalayam", "kotagiri", "arrival"]
	var bs: float = route.marks["bridge_start"] - 10.0
	var be: float = route.marks["bridge_end"] + 10.0
	for s in [1.0, -1.0]:
		var kind := PackedInt32Array()           # 0 none, 1 wall, 2 parapet
		var height := PackedFloat32Array()
		kind.resize(n)
		height.resize(n)
		for i in n:
			var d: float = route.dist[i]
			var st: Dictionary = route.stage_at(d)
			if towns.has(st["id"]) or (d > bs and d < be) or _in_town(d):
				continue
			var c: Vector3 = route.pts[i]
			var p: Vector3 = c + route.left(i) * (HALF + 3.0) * s
			var diff: float = route.natural_h(p.x, p.z) - c.y
			if diff > 1.3:
				kind[i] = 1
				height[i] = clampf(diff * 0.8, 1.0, 4.5)
			elif diff < -1.6 or (st["id"] == "ghat" and diff < 0.0):
				kind[i] = 2
		# smooth wall heights so tops don't jitter
		for i in range(1, n - 1):
			if kind[i] == 1:
				height[i] = (height[i - 1] + height[i] * 2.0 + height[i + 1]) / 4.0 if kind[i - 1] == 1 and kind[i + 1] == 1 else height[i]
		var walls := MB.new()
		var parapets := MB.new()
		for i in n - 1:
			if kind[i] == 0 or kind[i] != kind[i + 1]:
				continue
			var ci: Vector3 = route.pts[i]
			var cj: Vector3 = route.pts[i + 1]
			var li: Vector3 = route.left(i) * s
			var lj: Vector3 = route.left(i + 1) * s
			var di: float = route.dist[i]
			var dj: float = route.dist[i + 1]
			if kind[i] == 1:
				_wall_segment(walls, ci, cj, li, lj, WALL_OFF, 0.55, -0.6, height[i], height[i + 1], di, dj)
			else:
				var col := YELLOW if int(di / 1.2) % 2 == 0 else BLACK
				_block_segment(parapets, ci, cj, li, lj, PARAPET_OFF, 0.4, -0.45, 0.72, col)
		_add(walls, mat_wall, true)
		_add(parapets, mat_concrete, true)


func _in_town(d: float) -> bool:
	for t in route.towns:
		if d > t["start"] - 20.0 and d < t["end"] + 20.0:
			return true
	return false


## Textured wall: road-facing face, top and back, following the road between two samples.
func _wall_segment(mb, ci: Vector3, cj: Vector3, li: Vector3, lj: Vector3, off: float, thick: float,
		y0: float, hi: float, hj: float, di: float, dj: float) -> void:
	var a0 := ci + li * off + Vector3(0, y0, 0)
	var b0 := cj + lj * off + Vector3(0, y0, 0)
	var a1 := ci + li * off + Vector3(0, hi, 0)
	var b1 := cj + lj * off + Vector3(0, hj, 0)
	var a2 := a1 + li * thick
	var b2 := b1 + lj * thick
	var a3 := a0 + li * thick
	var b3 := b0 + lj * thick
	var inward := -li
	mb.quad(a0, b0, b1, a1, Color.WHITE, inward, Vector2(di / 3.0, y0 / 3.0), Vector2(dj / 3.0, y0 / 3.0),
		Vector2(dj / 3.0, hj / 3.0), Vector2(di / 3.0, hi / 3.0))
	mb.quad(a1, b1, b2, a2, Color.WHITE, Vector3.UP, Vector2(di / 3.0, 0), Vector2(dj / 3.0, 0),
		Vector2(dj / 3.0, thick / 3.0), Vector2(di / 3.0, thick / 3.0))
	mb.quad(a3, b3, b2, a2, Color.WHITE, li, Vector2(di / 3.0, y0 / 3.0), Vector2(dj / 3.0, y0 / 3.0),
		Vector2(dj / 3.0, hj / 3.0), Vector2(di / 3.0, hi / 3.0))


## Painted block (parapet or bridge edge) between two samples.
func _block_segment(mb, ci: Vector3, cj: Vector3, li: Vector3, lj: Vector3, off: float, thick: float,
		y0: float, y1: float, col: Color) -> void:
	var a0 := ci + li * off + Vector3(0, y0, 0)
	var b0 := cj + lj * off + Vector3(0, y0, 0)
	var a1 := ci + li * off + Vector3(0, y1, 0)
	var b1 := cj + lj * off + Vector3(0, y1, 0)
	var a2 := a1 + li * thick
	var b2 := b1 + lj * thick
	var a3 := a0 + li * thick
	var b3 := b0 + lj * thick
	mb.quad(a0, b0, b1, a1, col, -li)
	mb.quad(a1, b1, b2, a2, col, Vector3.UP)
	mb.quad(a3, b3, b2, a2, col, li)


# ----------------------------------------------------------------------------- bridge + river
func _bridge() -> void:
	var d0: float = route.marks["bridge_start"] - 6.0
	var d1: float = route.marks["bridge_end"] + 6.0
	var i0: int = route.index_at(d0)
	var i1: int = route.index_at(d1)
	var mb := MB.new()
	for i in range(i0, i1):
		var ci: Vector3 = route.pts[i]
		var cj: Vector3 = route.pts[i + 1]
		var li: Vector3 = route.left(i)
		var lj: Vector3 = route.left(i + 1)
		# deck underside and fascia
		for s in [1.0, -1.0]:
			_block_segment(mb, ci, cj, li * s, lj * s, HALF + 0.9, 0.35, -1.3, 0.9, CONCRETE)
		mb.quad(ci + li * (HALF + 1.25) + Vector3(0, -1.3, 0), cj + lj * (HALF + 1.25) + Vector3(0, -1.3, 0),
			cj - lj * (HALF + 1.25) + Vector3(0, -1.3, 0), ci - li * (HALF + 1.25) + Vector3(0, -1.3, 0),
			CONCRETE, Vector3.DOWN)
	# river bed: the real map takes the lowest ground across the crossing
	var mid: Transform3D = route.frame_at((d0 + d1) * 0.5)
	var bed: float = route.river_bed
	if route.is_real:
		bed = INF
		for k in range(-40, 41):
			var p: Vector3 = mid.origin + mid.basis.x * (k * 8.0)
			bed = minf(bed, route.natural_h(p.x, p.z))
		bed = minf(bed, mid.origin.y - 6.0)
	# piers down to the river bed
	for f in [0.33, 0.67]:
		var fr: Transform3D = route.frame_at(lerpf(d0, d1, f))
		var top := fr.origin.y - 1.3
		var bot: float = bed - 1.0
		var xf := Transform3D(fr.basis, Vector3(fr.origin.x, (top + bot) * 0.5, fr.origin.z))
		mb.box(xf, Vector3(HALF * 2.0 + 1.0, top - bot, 1.4), CONCRETE)
	_add(mb, mat_concrete, true, "Bridge")

	# the Bhavani
	var water := MB.new()
	if route.is_real:
		var lvl := bed + 1.2
		var a: Vector3 = mid.basis.x * 420.0
		var b: Vector3 = mid.basis.z * 26.0
		var o := Vector3(mid.origin.x, lvl, mid.origin.z)
		water.quad(o + a - b, o - a - b, o - a + b, o + a + b, Color.WHITE, Vector3.UP)
		var rmi := _add(water, mat_water, false, "BhavaniRiver")
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var zc: float = route.river_z
	var level: float = route.river_bed + 2.2
	var z := zc - 900.0
	while z < zc + 900.0:
		var xa: float = route.river_centre(z)
		var xb: float = route.river_centre(z + 20.0)
		water.quad(Vector3(xa + 24.0, level, z), Vector3(xa - 24.0, level, z),
			Vector3(xb - 24.0, level, z + 20.0), Vector3(xb + 24.0, level, z + 20.0), Color.WHITE, Vector3.UP)
		z += 20.0
	var wmi := _add(water, mat_water, false, "BhavaniRiver")
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ----------------------------------------------------------------------------- signs
func sign_board(d: float, side: float, text: String, board: Color, ink: Color, size := Vector2(2.4, 1.2),
		height := 2.2, offset := HALF + 2.4, font := 40) -> void:
	var f: Transform3D = route.frame_at(d, offset * side)
	var ground: float = terrain.height_at(f.origin.x, f.origin.z)
	var base := minf(ground, f.origin.y) - 0.2
	var face := Basis.looking_at(f.basis.z, Vector3.UP)        # faces oncoming traffic
	var mb := MB.new()
	var post_h := height + size.y * 0.5 - (base - f.origin.y)
	for px in [-size.x * 0.35, size.x * 0.35]:
		mb.box(Transform3D(face, Vector3(f.origin.x, base, f.origin.z) + face.x * px + Vector3(0, post_h * 0.5, 0)),
			Vector3(0.08, post_h, 0.08), Color(0.3, 0.3, 0.3))
	var centre := Vector3(f.origin.x, f.origin.y + height, f.origin.z)
	mb.box(Transform3D(face, centre), Vector3(size.x, size.y, 0.06), board)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat_vc
	mi.visibility_range_end = 400.0
	labels.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = 0.0075
	l.modulate = ink
	l.outline_size = 0
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.width = size.x / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.transform = Transform3D(face, centre + face.z * 0.04)
	l.visibility_range_end = 160.0
	labels.add_child(l)


func _signs() -> void:
	var total: float = route.length
	var green := Color(0.02, 0.18, 0.06)
	var yellow := Color(0.85, 0.62, 0.04)
	sign_board(40.0, 1.0, "METTUPALAYAM  35 km\nKOTAGIRI  68 km", green, Color.WHITE, Vector2(3.4, 1.6), 2.6)
	# milestones every game-kilometre, showing real-world kilometres to Kotagiri
	var d := 500.0
	while d < total - 200.0:
		var km := roundi((route.real_length - route.real_distance(d)) / 1000.0) if route.is_real else roundi((total - d) / total * 68.0)
		_milestone(d, km)
		d += 700.0
	sign_board(route.marks["checkpost"] - 180.0, 1.0, "WILD ELEPHANTS\nDrive slowly · Keep your distance", yellow, BLACK)
	sign_board(route.marks["ghat_start"] - 60.0, 1.0, "GHAT ROAD\nUphill vehicles have right of way · Use low gear", yellow, BLACK, Vector2(2.8, 1.4))
	for k in route.hairpin_idx.size():
		var i: int = route.hairpin_idx[k]
		sign_board(route.dist[i] - 70.0, 1.0, "HAIRPIN BEND\n%d / %d" % [k + 1, route.hairpin_idx.size()], yellow, BLACK,
			Vector2(1.6, 1.0))
	sign_board(route.stage_at(route.marks["ghat_end"] + 50.0)["start"] + 400.0, 1.0,
		"WELCOME TO THE NILGIRIS\nPlastic is banned", green, Color.WHITE, Vector2(3.0, 1.4))
	for s in route.stages:
		if s["id"] == "kotagiri":
			sign_board(s["start"] + 20.0, 1.0, "KOTAGIRI", Color(0.8, 0.8, 0.78), BLACK, Vector2(2.4, 0.8))


func _milestone(d: float, km: int) -> void:
	var f: Transform3D = route.frame_at(d, HALF + 1.9)
	var ground: float = terrain.height_at(f.origin.x, f.origin.z)
	var y := minf(ground, f.origin.y)
	var face := Basis.looking_at(f.basis.z, Vector3.UP)
	var mb := MB.new()
	mb.box(Transform3D(face, Vector3(f.origin.x, y + 0.35, f.origin.z)), Vector3(0.45, 0.9, 0.2), Color(0.8, 0.8, 0.76))
	mb.box(Transform3D(face, Vector3(f.origin.x, y + 0.9, f.origin.z)), Vector3(0.45, 0.25, 0.2), YELLOW)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = mat_vc
	mi.visibility_range_end = 300.0
	labels.add_child(mi)
	var l := Label3D.new()
	l.text = "KOTAGIRI\n%d" % km
	l.font_size = 22
	l.pixel_size = 0.006
	l.modulate = BLACK
	l.double_sided = false
	l.transform = Transform3D(face, Vector3(f.origin.x, y + 0.5, f.origin.z) + face.z * 0.11)
	l.visibility_range_end = 60.0
	labels.add_child(l)


# ----------------------------------------------------------------------------- towns: speed breakers + street lamps
func _town_details() -> void:
	var ranges: Array = []
	if route.is_real:
		for t in route.towns:
			ranges.append([t["start"], t["end"]])
	else:
		for st in route.stages:
			if st["id"] in ["coimbatore", "mettupalayam", "kotagiri"]:
				ranges.append([st["start"], st["end"]])
	var humps := MB.new()
	var poles := MB.new()
	for r in ranges:
		var d: float = r[0] + 60.0
		while d < r[1] - 40.0:
			bumps.append(d)
			_speed_breaker(humps, d)
			d += 240.0
		d = r[0] + 10.0
		var side := 1.0
		while d < r[1]:
			_street_lamp(poles, d, side)
			side = -side
			d += 38.0
	_add(humps, mat_vc, true, "SpeedBreakers")
	var lamps := _add(poles, mat_vc, false, "StreetLamps")
	if lamps:
		lamps.visibility_range_end = 700.0


## A painted hump across the road, 0.12 m high and 1.4 m long, striped yellow and black.
func _speed_breaker(mb, d: float) -> void:
	var f: Transform3D = route.frame_at(d)
	var l := f.basis.x
	var t := f.basis.z
	var profile := [[-0.7, 0.0], [-0.35, 0.09], [0.0, 0.12], [0.35, 0.09], [0.7, 0.0]]
	var stripes := 8
	for k in stripes:
		var s0 := lerpf(-HALF, HALF, float(k) / stripes)
		var s1 := lerpf(-HALF, HALF, float(k + 1) / stripes)
		var col := YELLOW if k % 2 == 0 else BLACK
		for m in profile.size() - 1:
			var a0: Vector3 = f.origin + t * profile[m][0] + Vector3(0, profile[m][1] + 0.01, 0)
			var a1: Vector3 = f.origin + t * profile[m + 1][0] + Vector3(0, profile[m + 1][1] + 0.01, 0)
			mb.quad(a0 + l * s0, a0 + l * s1, a1 + l * s1, a1 + l * s0, col, Vector3.UP)


func _street_lamp(mb, d: float, side: float) -> void:
	var f: Transform3D = route.frame_at(d, (HALF + 1.8) * side)
	var ground: float = terrain.height_at(f.origin.x, f.origin.z)
	var base := Vector3(f.origin.x, minf(ground, f.origin.y) - 0.2, f.origin.z)
	var grey := Color(0.35, 0.36, 0.36)
	mb.cylinder(Transform3D(Basis(), base), 0.09, 0.06, 7.5, grey, 6)
	var arm: Vector3 = -f.basis.x * side
	var top := base + Vector3(0, 7.4, 0)
	mb.box(Transform3D(Basis.looking_at(arm, Vector3.UP), top + arm * 0.8), Vector3(0.08, 0.08, 1.6), grey)
	mb.box(Transform3D(Basis.looking_at(arm, Vector3.UP), top + arm * 1.6 + Vector3(0, -0.08, 0)), Vector3(0.28, 0.12, 0.5),
		Color(0.85, 0.82, 0.7))
