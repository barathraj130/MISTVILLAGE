extends Node3D
## Small roadside details that make the drive read as a real Tamil Nadu road:
## tar patches and potholes, glowing road studs on the ghat, chevron boards on sharp bends,
## 200 m stones, white guard stones, little temple shrines, bus shelters, NH181 billboards,
## cows grazing on the verges and monkeys sitting on the ghat parapets.
## Everything is merged into a few meshes per stretch so it stays cheap to draw.

const Route := preload("res://scripts/drive/route.gd")
const Terrain := preload("res://scripts/drive/terrain.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const HALF := 3.6
const SEG := 2000.0                         # metres of road per merged mesh

const YELLOW := Color(0.85, 0.62, 0.04)
const BLACK := Color(0.025, 0.025, 0.025)
const WHITE := Color(0.8, 0.8, 0.77)
const ADS := [["KONGU TEXTILES", "Wedding silks · Coimbatore", Color(0.55, 0.05, 0.1)],
	["HILL FRESH TEA", "Taste the Nilgiris", Color(0.05, 0.3, 0.1)],
	["VISIT KOTAGIRI", "The oldest hill station of the Nilgiris", Color(0.05, 0.2, 0.45)],
	["STRONG CEMENT", "For homes that last", Color(0.35, 0.35, 0.38)],
	["OOTY VARKEY", "Fresh from the hills", Color(0.7, 0.45, 0.05)],
	["DRIVE SAFE", "Ghat road ahead · Use low gear", Color(0.75, 0.55, 0.02)]]

var route: Route
var terrain: Terrain
var rng := RandomNumberGenerator.new()
var mat_vc: StandardMaterial3D
var mat_glow: StandardMaterial3D
var _segs := {}                             # segment index → MB (matte details)
var _glow := {}                             # segment index → MB (road studs)


func build(r: Route, t: Terrain, bumps: Array) -> void:
	route = r
	terrain = t
	rng.seed = 99
	mat_vc = MB.vertex_color_material(0.85)
	mat_glow = StandardMaterial3D.new()
	mat_glow.vertex_color_use_as_albedo = true
	mat_glow.emission_enabled = true
	mat_glow.emission = Color(1.0, 0.75, 0.2)
	mat_glow.emission_energy_multiplier = 0.9
	_road_surface(bumps)
	_studs()
	_chevrons()
	_small_stones()
	_guard_stones()
	_shrines()
	_bus_shelters()
	_billboards()
	_cows()
	_monkeys()
	for k in _segs:
		_commit(_segs[k], "Details_%d" % k, mat_vc, 450.0)
	for k in _glow:
		_commit(_glow[k], "RoadStuds_%d" % k, mat_glow, 350.0)


func _mb(d: float) -> Object:
	var k := int(d / SEG)
	if not _segs.has(k):
		_segs[k] = MB.new()
	return _segs[k]


func _commit(mb, node_name: String, mat: Material, range_end: float) -> void:
	if mb.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.commit()
	mi.material_override = mat
	mi.visibility_range_end = range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _stage(id: String) -> Dictionary:
	for s in route.stages:
		if s["id"] == id:
			return s
	return {}


func _in_town(d: float) -> bool:
	for t in route.towns:
		if d > t["start"] - 30.0 and d < t["end"] + 30.0:
			return true
	return false


func _ground(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z)


func _label(text: String, xf: Transform3D, size: int, col: Color, range_end := 80.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = col
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.transform = xf
	l.visibility_range_end = range_end
	add_child(l)


## Sharp bend near d? Returns the turn's sign (+1 left, -1 right) or 0.
func _bend(d: float, span := 30.0, min_deg := 45.0) -> float:
	var a: Vector3 = route.frame_at(d - span).basis.z
	var b: Vector3 = route.frame_at(d + span).basis.z
	if rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0))) < min_deg:
		return 0.0
	return signf(a.cross(b).y)


# ----------------------------------------------------------------------------- road surface
## Tar patches, repair seams and potholes, a few millimetres above the asphalt.
func _road_surface(bumps: Array) -> void:
	var d := 25.0
	while d < route.length - 30.0:
		var mb = _mb(d)
		var f: Transform3D = route.frame_at(d)
		var l := f.basis.x
		var t := f.basis.z
		var kind := rng.randf()
		var lane := rng.randf_range(-HALF + 0.8, HALF - 0.8)
		var c := f.origin + l * lane + Vector3(0, 0.012, 0)
		if kind < 0.45:
			# rectangular tar patch, darker and fresher than the road
			var w := rng.randf_range(0.8, 2.2)
			var patch_len := rng.randf_range(1.2, 4.0)
			var col := Color(0.035, 0.035, 0.038) if rng.randf() < 0.6 else Color(0.1, 0.1, 0.1)
			mb.quad(c - l * w * 0.5 - t * patch_len * 0.5, c + l * w * 0.5 - t * patch_len * 0.5, c + l * w * 0.5 + t * patch_len * 0.5,
				c - l * w * 0.5 + t * patch_len * 0.5, col, Vector3.UP)
		elif kind < 0.7 and not _in_town(d):
			# pothole: dark irregular ring with a muddy rim
			var r := rng.randf_range(0.25, 0.6)
			var n := 9
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n
				var r0 := r * rng.randf_range(0.75, 1.15)
				var r1 := r * rng.randf_range(0.75, 1.15)
				var p0 := c + (l * cos(a0) + t * sin(a0)) * r0
				var p1 := c + (l * cos(a1) + t * sin(a1)) * r1
				mb.tri(c - Vector3(0, 0.004, 0), p1, p0, Color(0.015, 0.012, 0.01), Vector3.UP)
				mb.tri(p0, p1, c + (l * cos(a1) + t * sin(a1)) * r1 * 1.25, Color(0.22, 0.14, 0.08), Vector3.UP)
		else:
			# a sealed crack across the lane
			var w2 := rng.randf_range(1.5, 3.5)
			var a := c - l * w2 * 0.5
			var b := c + l * w2 * 0.5
			var wob := t * rng.randf_range(-0.4, 0.4)
			mb.quad(a - t * 0.05, (a + b) * 0.5 + wob - t * 0.05, (a + b) * 0.5 + wob + t * 0.05, a + t * 0.05, BLACK, Vector3.UP)
			mb.quad((a + b) * 0.5 + wob - t * 0.05, b - t * 0.05, b + t * 0.05, (a + b) * 0.5 + wob + t * 0.05, BLACK, Vector3.UP)
		d += rng.randf_range(18.0, 55.0)


## Reflective road studs along the ghat and misty stretches: they glow when your headlights hit them.
func _studs() -> void:
	var s0: float = route.marks["ghat_start"]
	var s1: float = _stage("kotagiri").get("start", route.length)
	var d := s0
	while d < s1:
		var mb = _glow_mb(d)
		for off in [0.0, HALF - 0.3, -(HALF - 0.3)]:
			var f: Transform3D = route.frame_at(d, off)
			var col := YELLOW if off == 0.0 else Color(0.9, 0.9, 0.85)
			mb.box(Transform3D(f.basis, f.origin + Vector3(0, 0.03, 0)), Vector3(0.1, 0.03, 0.16), col)
		d += 12.0


func _glow_mb(d: float) -> Object:
	var k := int(d / SEG)
	if not _glow.has(k):
		_glow[k] = MB.new()
	return _glow[k]


# ----------------------------------------------------------------------------- signs and stones
## Black-and-yellow chevron boards on the outside of every sharp bend, arrows pointing into the turn.
func _chevrons() -> void:
	var d := 60.0
	while d < route.length - 60.0:
		var s := _bend(d)
		if s == 0.0 or _in_town(d):
			d += 10.0
			continue
		for k in range(-2, 3):
			var dd := d + k * 9.0
			var f: Transform3D = route.frame_at(dd, -s * (HALF + 1.7))    # outside of the turn
			var face := Basis.looking_at(f.basis.z, Vector3.UP)         # facing the approaching driver
			var y := minf(_ground(f.origin), f.origin.y)
			var mb = _mb(dd)
			var c := Vector3(f.origin.x, y + 1.35, f.origin.z)
			mb.box(Transform3D(face, Vector3(f.origin.x, y + 0.55, f.origin.z)), Vector3(0.07, 1.1, 0.07), Color(0.3, 0.3, 0.3))
			mb.box(Transform3D(face, c), Vector3(0.6, 0.72, 0.04), YELLOW)
			# two black chevrons pointing in the turn's direction (+X of `face` is the driver's right)
			var dir := -s
			for j in 2:
				var cx := (j - 0.5) * 0.2
				var tip := c + face.x * (cx + dir * 0.09) + face.z * 0.025
				var top := c + face.x * (cx - dir * 0.09) + face.y * 0.26 + face.z * 0.025
				var bot := c + face.x * (cx - dir * 0.09) - face.y * 0.26 + face.z * 0.025
				var thick := face.x * dir * 0.08
				mb.quad(top, top + thick, tip + thick, tip, BLACK, face.z)
				mb.quad(tip, tip + thick, bot + thick, bot, BLACK, face.z)
		d += 80.0


## Small 200 m stones (white with an orange cap) between the milestones.
func _small_stones() -> void:
	var d := 200.0
	while d < route.length - 50.0:
		var f: Transform3D = route.frame_at(d, HALF + 1.6)
		var y := minf(_ground(f.origin), f.origin.y)
		var face := Basis.looking_at(f.basis.z, Vector3.UP)
		var mb = _mb(d)
		mb.box(Transform3D(face, Vector3(f.origin.x, y + 0.22, f.origin.z)), Vector3(0.3, 0.45, 0.14), WHITE)
		mb.box(Transform3D(face, Vector3(f.origin.x, y + 0.49, f.origin.z)), Vector3(0.3, 0.1, 0.14), Color(0.8, 0.3, 0.03))
		d += 200.0


## White-painted guard stones every few metres on the plains and foothills.
func _guard_stones() -> void:
	for id in ["plains", "foothills"]:
		var st := _stage(id)
		if st.is_empty():
			continue
		var d: float = st["start"]
		while d < st["end"]:
			if not _in_town(d) and _bend(d, 20.0, 25.0) == 0.0:
				for side in [1.0, -1.0]:
					var f: Transform3D = route.frame_at(d, (HALF + 1.5) * side)
					var y := minf(_ground(f.origin), f.origin.y)
					var mb = _mb(d)
					mb.box(Transform3D(f.basis, Vector3(f.origin.x, y + 0.2, f.origin.z)), Vector3(0.18, 0.5, 0.25), WHITE)
					mb.box(Transform3D(f.basis, Vector3(f.origin.x, y + 0.42, f.origin.z)), Vector3(0.19, 0.08, 0.26), BLACK)
			d += 7.0


# ----------------------------------------------------------------------------- roadside buildings
## Little roadside temples: a whitewashed shrine under a stepped, painted tower, with a flag and lamp.
func _shrines() -> void:
	var spots: Array = []
	for id in ["plains", "plains", "mettupalayam", "ghat", "ghat", "mist", "kotagiri"]:
		var st := _stage(id)
		if not st.is_empty():
			spots.append(rng.randf_range(st["start"] + 80.0, st["end"] - 80.0))
	for d in spots:
		var f: Transform3D = route.frame_at(d, HALF + 5.5)
		if terrain.near_road(f.origin.x, f.origin.z) > 0.6:
			continue
		var y := minf(_ground(f.origin), f.origin.y) - 0.1
		var face := Basis.looking_at(-f.basis.x, Vector3.UP)           # door faces the road
		var mb = _mb(d)
		var base := Vector3(f.origin.x, y, f.origin.z)
		var xf := func(p: Vector3) -> Transform3D: return Transform3D(face, base + face * p)
		mb.box(xf.call(Vector3(0, 0.2, 0)), Vector3(2.6, 0.4, 2.6), Color(0.55, 0.53, 0.5))
		mb.box(xf.call(Vector3(0, 1.2, 0)), Vector3(1.8, 1.6, 1.8), Color(0.85, 0.82, 0.74))
		mb.box(xf.call(Vector3(0, 1.0, 0.91)), Vector3(0.7, 1.1, 0.03), Color(0.05, 0.03, 0.02))
		var tiers := [Color(0.8, 0.45, 0.1), Color(0.7, 0.1, 0.08), Color(0.1, 0.35, 0.65), Color(0.85, 0.7, 0.1)]
		for k in 4:
			var w := 1.9 - k * 0.38
			mb.box(xf.call(Vector3(0, 2.15 + k * 0.42, 0)), Vector3(w, 0.4, w), tiers[k])
		mb.cylinder(xf.call(Vector3(0, 3.8, 0)), 0.14, 0.02, 0.5, Color(0.85, 0.65, 0.2), 6)
		mb.cylinder(xf.call(Vector3(1.1, 0.4, 1.1)), 0.03, 0.03, 4.5, Color(0.4, 0.3, 0.2), 5)
		mb.quad2(base + face * Vector3(1.1, 4.8, 1.1), base + face * Vector3(1.1, 4.35, 1.1),
			base + face * Vector3(1.85, 4.45, 1.1), base + face * Vector3(1.85, 4.75, 1.1), Color(0.9, 0.35, 0.02))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.6, 0.25)
		lamp.light_energy = 0.8
		lamp.omni_range = 4.0
		lamp.position = base + face * Vector3(0, 0.9, 1.2)
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 120.0
		lamp.distance_fade_length = 30.0
		add_child(lamp)


## Bus shelters at the start of each town and village, with the town's name.
func _bus_shelters() -> void:
	for t in route.towns:
		var d: float = t["start"] + 25.0
		var f: Transform3D = route.frame_at(d, HALF + 3.0)
		var y := minf(_ground(f.origin), f.origin.y) - 0.2
		var face := Basis.looking_at(-f.basis.x, Vector3.UP)
		var base := Vector3(f.origin.x, y, f.origin.z)
		var mb = _mb(d)
		var at := func(p: Vector3) -> Transform3D: return Transform3D(face, base + face * p)
		mb.box(at.call(Vector3(0, 0.15, 0)), Vector3(4.5, 0.3, 2.2), Color(0.5, 0.5, 0.48))
		for px in [-2.0, 2.0]:
			for pz in [-0.9, 0.9]:
				mb.box(at.call(Vector3(px, 1.45, pz)), Vector3(0.15, 2.3, 0.15), Color(0.6, 0.6, 0.58))
		mb.box(at.call(Vector3(0, 2.65, 0.1)), Vector3(4.8, 0.14, 2.6), Color(0.55, 0.55, 0.53))
		mb.box(at.call(Vector3(0, 0.75, -0.6)), Vector3(3.6, 0.08, 0.45), Color(0.5, 0.35, 0.2))
		mb.box(at.call(Vector3(0, 1.4, -1.0)), Vector3(4.2, 1.6, 0.06), Color(0.2, 0.4, 0.25))
		mb.box(at.call(Vector3(0, 3.0, 1.3)), Vector3(3.0, 0.5, 0.05), Color(0.05, 0.25, 0.5))
		_label(String(t["name"]).to_upper(), Transform3D(face, base + face * Vector3(0, 3.0, 1.34)), 44, Color.WHITE, 120.0)


## Hoardings along NH181: two legs, a lit frame and a painted panel.
func _billboards() -> void:
	var st := _stage("plains")
	if st.is_empty():
		return
	var d: float = st["start"] + 150.0
	var i := 0
	while d < st["end"] - 100.0:
		var side := 1.0 if i % 2 == 0 else -1.0
		var f: Transform3D = route.frame_at(d, (HALF + 16.0) * side)
		if terrain.near_road(f.origin.x, f.origin.z) < 0.2:
			var y := _ground(f.origin)
			var face := Basis.looking_at(f.basis.z, Vector3.UP).rotated(Vector3.UP, -side * 0.35)
			var base := Vector3(f.origin.x, y, f.origin.z)
			var mb = _mb(d)
			var ad: Array = ADS[i % ADS.size()]
			for px in [-2.8, 2.8]:
				mb.box(Transform3D(face, base + face * Vector3(px, 2.5, 0)), Vector3(0.22, 5.0, 0.22), Color(0.25, 0.25, 0.26))
			mb.box(Transform3D(face, base + face * Vector3(0, 6.3, 0)), Vector3(7.6, 3.4, 0.2), Color(0.15, 0.15, 0.15))
			mb.box(Transform3D(face, base + face * Vector3(0, 6.3, 0.11)), Vector3(7.3, 3.1, 0.02), ad[2])
			_label(ad[0], Transform3D(face, base + face * Vector3(0, 6.9, 0.14)), 150, Color(1, 0.97, 0.9), 400.0)
			_label(ad[1], Transform3D(face, base + face * Vector3(0, 5.8, 0.14)), 70, Color(1, 0.95, 0.8), 300.0)
		d += rng.randf_range(450.0, 750.0)
		i += 1


# ----------------------------------------------------------------------------- animals
## Cows grazing on the verges of NH181 and the foothills (and in villages): white or brown,
## painted horns, standing at odd angles. Solid, so don't hit them.
func _cows() -> void:
	var body := StaticBody3D.new()
	body.name = "Cows"
	add_child(body)
	var ids := ["plains", "plains", "plains", "mettupalayam", "foothills", "kotagiri"]
	for n in 16:
		var st := _stage(ids[n % ids.size()])
		if st.is_empty():
			continue
		var d := rng.randf_range(st["start"] + 40.0, st["end"] - 40.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var f: Transform3D = route.frame_at(d, (HALF + rng.randf_range(2.2, 9.0)) * side)
		if terrain.near_road(f.origin.x, f.origin.z) > 0.85:
			continue
		var base := Vector3(f.origin.x, _ground(f.origin), f.origin.z)
		var face := Basis(Vector3.UP, rng.randf() * TAU)
		var hide: Color = [Color(0.8, 0.78, 0.72), Color(0.35, 0.2, 0.1), Color(0.55, 0.5, 0.45)][rng.randi() % 3]
		var mb = _mb(d)
		var at := func(p: Vector3) -> Transform3D: return Transform3D(face, base + face * p)
		mb.ellipsoid(at.call(Vector3(0, 1.05, 0)), Vector3(0.42, 0.42, 0.85), hide, 5, 8)
		mb.ellipsoid(at.call(Vector3(0, 1.25, 0.95)), Vector3(0.18, 0.2, 0.3), hide, 4, 6)
		mb.ellipsoid(at.call(Vector3(0, 1.3, -0.2)), Vector3(0.2, 0.25, 0.25), hide.darkened(0.1), 3, 6)   # hump
		for sx in [-0.18, 0.18]:
			for sz in [-0.55, 0.55]:
				mb.box(at.call(Vector3(sx, 0.42, sz)), Vector3(0.1, 0.84, 0.1), hide.darkened(0.15))
			mb.cylinder(Transform3D(face * Basis(Vector3.BACK, -sx * 3.0), base + face * Vector3(sx * 0.7, 1.42, 0.95)),
				0.03, 0.01, 0.28, Color(0.1, 0.3, 0.7) if rng.randf() < 0.5 else Color(0.7, 0.15, 0.1), 5)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.9, 1.4, 2.0)
		cs.shape = bx
		cs.transform = Transform3D(face, base + Vector3(0, 0.8, 0))
		body.add_child(cs)


## Monkeys sitting on the black-and-yellow parapets of the ghat, watching the traffic.
func _monkeys() -> void:
	var st := _stage("ghat")
	if st.is_empty():
		return
	for n in 24:
		var d := rng.randf_range(st["start"] + 50.0, st["end"] - 50.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var f: Transform3D = route.frame_at(d, (4.6 + 0.2) * side)
		var nat: float = route.natural_h(f.origin.x + f.basis.x.x * 2.0 * side, f.origin.z + f.basis.x.z * 2.0 * side)
		if nat > f.origin.y - 1.2:
			continue                              # only where there's a parapet (a drop beside the road)
		var base := f.origin + Vector3(0, 0.27, 0)  # parapet top
		var face := Basis.looking_at(-f.basis.x * side, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.8, 0.8))
		var fur := Color(0.28, 0.24, 0.2)
		var mb = _mb(d)
		var at := func(p: Vector3) -> Transform3D: return Transform3D(face, base + face * p)
		mb.ellipsoid(at.call(Vector3(0, 0.22, 0)), Vector3(0.13, 0.2, 0.12), fur, 4, 6)
		mb.ellipsoid(at.call(Vector3(0, 0.5, 0.03)), Vector3(0.09, 0.09, 0.09), fur, 4, 6)
		mb.ellipsoid(at.call(Vector3(0, 0.49, 0.1)), Vector3(0.05, 0.045, 0.03), Color(0.55, 0.38, 0.3), 3, 5)
		mb.cylinder(Transform3D(face * Basis(Vector3.RIGHT, 2.4), base + face * Vector3(0, 0.1, -0.1)), 0.02, 0.012, 0.55, fur, 4)
