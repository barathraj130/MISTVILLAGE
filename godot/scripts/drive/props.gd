extends Node3D
## Everything along the roadside: Coimbatore, Mettupalayam and Kotagiri, coconut and areca
## groves on the plains, forest up the ghat, contour tea gardens with silver-oak shade trees,
## the forest check post, a tea stall above the clouds and The Mist Village gate.

const Route := preload("res://scripts/drive/route.gd")
const Terrain := preload("res://scripts/drive/terrain.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const VegLibrary := preload("res://scripts/drive/veg_library.gd")
const HALF := 3.6

const PALETTE := [Color(0.62, 0.48, 0.30), Color(0.55, 0.33, 0.26), Color(0.36, 0.52, 0.47), Color(0.70, 0.62, 0.48),
	Color(0.45, 0.47, 0.62), Color(0.75, 0.55, 0.22), Color(0.66, 0.66, 0.60), Color(0.50, 0.60, 0.35)]
const TIN := [Color(0.35, 0.07, 0.05), Color(0.06, 0.20, 0.10), Color(0.07, 0.14, 0.32), Color(0.40, 0.40, 0.40)]
const BOARDS := [Color(0.60, 0.05, 0.05), Color(0.05, 0.15, 0.45), Color(0.80, 0.55, 0.02), Color(0.05, 0.35, 0.12),
	Color(0.85, 0.85, 0.82)]
const SHOPS := ["Sri Murugan Tea Stall", "Kovai Textiles", "Ganesh Stores", "Lakshmi Bakery", "Arun Mobiles",
	"Nilgiri Tea Depot", "Saravanan Mess", "Meenakshi Sweets", "Vel Hardware", "Anbu Medicals", "Kannan Fruits",
	"Senthil Motors", "Hotel Annam", "Selvi Tailors", "Bharath Tyres", "Kumar Provisions", "Hill View Lodge",
	"Karthik Electricals", "Amman Flower Shop", "Raja Cycle Works"]

var route: Route
var terrain: Terrain
var veg: VegLibrary
var rng := RandomNumberGenerator.new()
var mat_vc: StandardMaterial3D
var mat_plaster: StandardMaterial3D
var mat_tin: StandardMaterial3D
var colliders: StaticBody3D
var barrier_pivot: Node3D
var barrier_shape: CollisionShape3D
var tea_stall_pos := Vector3.ZERO
const PROP_DIR := "res://assets/drive/props/"
var _prop_cache := {}
var _shutters: Array = []            # shop-front shutter transforms, placed by _towns
var _chairs: Array = []
var _boxes: Array = []
var gate_pos := Vector3.ZERO


func build(r, t, progress: Callable) -> void:
	route = r
	terrain = t
	veg = VegLibrary.new()
	rng.seed = 42
	mat_vc = MB.vertex_color_material(0.85)
	mat_plaster = MB.cc0_material("plaster", 2.0, 0.92)
	mat_tin = MB.cc0_material("tin_roof", 1.5, 0.55)
	mat_tin.metallic = 0.4
	mat_tin.cull_mode = BaseMaterial3D.CULL_DISABLED
	colliders = StaticBody3D.new()
	colliders.name = "PropCollision"
	add_child(colliders)
	var steps := [_towns, _palms, _forest, _tea, _checkpost, _tea_stall, _gate, _power_lines, _verges, _street_furniture]
	var trace := "--trace" in OS.get_cmdline_user_args()
	for i in steps.size():
		var t0 := Time.get_ticks_msec()
		steps[i].call()
		if trace:
			print("  PROPS %-20s %5d ms" % [steps[i].get_method(), Time.get_ticks_msec() - t0])
		progress.call(float(i + 1) / steps.size())
		await get_tree().process_frame


func _mesh(mb, node_name: String, range_end := 0.0, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.commit()
	mi.material_override = mat if mat else mat_vc
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	add_child(mi)
	return mi


func _box_collider(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	colliders.add_child(cs)


func _label(text: String, pos: Vector3, facing: Vector3, size := 28, col := Color.WHITE, range_end := 90.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.modulate = col
	l.double_sided = false
	l.transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), pos)
	l.visibility_range_end = range_end
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _stage(id: String) -> Dictionary:
	for s in route.stages:
		if s["id"] == id:
			return s
	return {}


# ----------------------------------------------------------------------------- towns
func _towns() -> void:
	if route.is_real:
		for t in route.towns:
			var t_end: float = t["end"]
			if route.resort_attached:
				t_end = minf(t_end, route.length - 260.0)       # leave the approach to the resort clear
			if t_end > t["start"] + 30.0:
				_town(t["start"], t_end, t["hill"], int(t["floors"]), String(t["name"]).validate_node_name())
		return
	var cbe := _stage("coimbatore")
	var mtp := _stage("mettupalayam")
	var kot := _stage("kotagiri")
	_town(cbe["start"] + 20.0, cbe["end"] - 120.0, false, 3, "Coimbatore")
	_town(mtp["start"] + 10.0, route.marks["bridge_start"] - 30.0, false, 2, "Mettupalayam")
	_town(route.marks["bridge_end"] + 30.0, mtp["end"] - 40.0, false, 2, "Mettupalayam2")
	_town(kot["start"] + 40.0, kot["end"] - 30.0, true, 2, "Kotagiri")


func _town(d0: float, d1: float, hill: bool, max_floors: int, town_name: String) -> void:
	var mb := MB.new()
	var roofs := MB.new()
	for side in [1.0, -1.0]:
		var d := d0 + rng.randf_range(0.0, 8.0)
		while d < d1:
			var w := rng.randf_range(7.0, 12.0)
			var depth := rng.randf_range(8.0, 12.0)
			var f: Transform3D = route.frame_at(d + w * 0.5)
			var out: Vector3 = f.basis.x * side
			var c: Vector3 = f.origin + out * (HALF + 3.2 + depth * 0.5)
			var base: float = f.origin.y - 0.3
			var floors := rng.randi_range(1, max_floors)
			var bh := floors * 3.1
			var col: Color = PALETTE[rng.randi() % PALETTE.size()]
			var tin: Color = TIN[rng.randi() % TIN.size()]
			mb.box(Transform3D(f.basis, Vector3(c.x, base - 2.0, c.z)), Vector3(depth, 4.0, w), col.darkened(0.55))
			mb.box(Transform3D(f.basis, Vector3(c.x, base + bh * 0.5, c.z)), Vector3(depth, bh, w), col)
			var front := c - out * (depth * 0.5 + 0.04)
			if ResourceLoader.exists(PROP_DIR + "shutter.glb"):
				var face := Basis.looking_at(-out, Vector3.UP)     # the shutter model faces -Z
				var doors := maxi(1, roundi(w * 0.75 / 1.1))
				for k in doors:
					var along := (k - (doors - 1) * 0.5) * 1.12
					_shutters.append(Transform3D(face, Vector3(front.x, base, front.z) + f.basis.z * along - out * 0.02))
				if rng.randf() < 0.18:
					for k in 2:
						var cp := Vector3(front.x, base, front.z) - out * 1.3 + f.basis.z * (k * 0.8 - 0.4 + rng.randf_range(-0.2, 0.2))
						_chairs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp))
				if rng.randf() < 0.15:
					_boxes.append(Transform3D(face, Vector3(front.x, base, front.z) - out * 0.3 + f.basis.z * (w * 0.45)))
			else:
				mb.box(Transform3D(f.basis, Vector3(front.x, base + 1.25, front.z)), Vector3(0.08, 2.4, w * 0.7),
					Color(0.18, 0.19, 0.2) if rng.randf() < 0.5 else Color(0.03, 0.03, 0.03))
			roofs.box(Transform3D(f.basis, Vector3(front.x, base + 2.75, front.z) - out * 0.7), Vector3(1.4, 0.06, w * 0.95), tin * 2.2)
			# tube light under the awning, and upper-floor windows and balconies
			mb.box(Transform3D(f.basis, Vector3(front.x, base + 2.62, front.z) - out * 0.25), Vector3(0.06, 0.05, 1.2),
				Color(1.2, 1.2, 1.15))
			for fl in range(1, floors):
				var fy := base + fl * 3.1 + 1.5
				var wins := maxi(1, int(w / 2.4))
				for k in wins:
					var along := (k - (wins - 1) * 0.5) * 2.2
					var wp := Vector3(front.x, fy, front.z) + f.basis.z * along
					mb.box(Transform3D(f.basis, wp - out * 0.02), Vector3(0.08, 1.25, 1.05), col.darkened(0.35))
					mb.box(Transform3D(f.basis, wp - out * 0.05), Vector3(0.04, 1.05, 0.85), Color(0.06, 0.08, 0.1))
					mb.box(Transform3D(f.basis, wp - out * 0.07), Vector3(0.03, 1.05, 0.05), Color(0.35, 0.35, 0.33))
				if rng.randf() < 0.4:
					var bp := Vector3(front.x, base + fl * 3.1 + 0.05, front.z) - out * 0.6
					mb.box(Transform3D(f.basis, bp), Vector3(1.2, 0.12, w * 0.6), col.darkened(0.2))
					mb.box(Transform3D(f.basis, bp - out * 0.55 + Vector3(0, 0.5, 0)), Vector3(0.05, 0.9, w * 0.6), Color(0.15, 0.15, 0.16))
			if rng.randf() < 0.55:
				var sign_pos := Vector3(front.x, base + 3.35, front.z) - out * 0.06
				mb.box(Transform3D(f.basis, sign_pos), Vector3(0.1, 0.8, w * 0.85), BOARDS[rng.randi() % BOARDS.size()])
				_label(SHOPS[rng.randi() % SHOPS.size()], sign_pos - out * 0.07, -out, 30, Color(0.98, 0.95, 0.85))
			if hill:
				_gable(roofs, f.basis, Vector3(c.x, base + bh, c.z), depth, w, tin * 2.2, col)
			elif rng.randf() < 0.65:
				mb.cylinder(Transform3D(Basis(), Vector3(c.x, base + bh, c.z) + out * 1.5), 0.7, 0.7, 1.4,
					Color(0.02, 0.02, 0.02), 10)
			_box_collider(Transform3D(f.basis, Vector3(c.x, base + bh * 0.5 - 1.0, c.z)), Vector3(depth, bh + 2.0, w))
			d += w + rng.randf_range(0.3, 3.5)
	_mesh(mb, town_name, 1200.0, mat_plaster)
	_mesh(roofs, town_name + "Roofs", 1200.0, mat_tin)


func _gable(mb, b: Basis, top: Vector3, depth: float, w: float, tin: Color, wall: Color) -> void:
	var xf := Transform3D(b, top)
	var dx := depth * 0.5 + 0.4
	var wz := w * 0.5 + 0.3
	var rh := depth * 0.32
	mb.quad2(xf * Vector3(-dx, 0, -wz), xf * Vector3(-dx, 0, wz), xf * Vector3(0, rh, wz), xf * Vector3(0, rh, -wz), tin)
	mb.quad2(xf * Vector3(dx, 0, -wz), xf * Vector3(dx, 0, wz), xf * Vector3(0, rh, wz), xf * Vector3(0, rh, -wz), tin)
	for s in [-1.0, 1.0]:
		var z: float = w * 0.5 * s
		mb.tri(xf * Vector3(-depth * 0.5, 0, z), xf * Vector3(depth * 0.5, 0, z), xf * Vector3(0, rh * 0.9, z), wall,
			b * Vector3(0, 0, s))


# ----------------------------------------------------------------------------- palms
func _palm_mesh(areca: bool) -> ArrayMesh:
	var mb := MB.new()
	var H := 12.0 if areca else 9.5
	var r0 := 0.12 if areca else 0.24
	var r1 := 0.10 if areca else 0.15
	var lean := 0.25 if areca else 0.9
	var trunk := Color(0.28, 0.24, 0.18) if not areca else Color(0.35, 0.34, 0.28)
	var segs := 5
	for s in segs:
		var t0 := float(s) / segs
		var t1 := float(s + 1) / segs
		var c0 := Vector3(lean * t0 * t0, H * t0, 0)
		var c1 := Vector3(lean * t1 * t1, H * t1, 0)
		var ra := lerpf(r0, r1, t0)
		var rb := lerpf(r0, r1, t1)
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			var u0 := Vector3(cos(a0), 0, sin(a0))
			var u1 := Vector3(cos(a1), 0, sin(a1))
			mb.quad(c0 + u0 * ra, c0 + u1 * ra, c1 + u1 * rb, c1 + u0 * rb, trunk, (u0 + u1) * 0.5)
	var top := Vector3(lean, H, 0)
	if areca:
		mb.cylinder(Transform3D(Basis(), top - Vector3(0, 1.3, 0)), r1 * 1.3, r1 * 1.1, 1.4, Color(0.10, 0.20, 0.05), 6, false)
	var fronds := 7 if areca else 10
	var L := 2.8 if areca else 4.8
	var droop := 1.4 if areca else 2.6
	for f in fronds:
		var a := TAU * f / fronds + 0.3 * sin(f * 1.7)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var prev := top
		var prev_w := 0.0
		for s in 4:
			var t := float(s + 1) / 4.0
			var p := top + dir * L * t + Vector3(0, (0.9 * t - droop * t * t) * L * 0.45, 0)
			var w := (0.5 if areca else 0.75) * sin(PI * minf(t, 0.92)) + 0.04
			var col := Color(0.05, 0.16, 0.03).lerp(Color(0.18, 0.22, 0.05), t * 0.7)
			mb.quad2(prev + side * prev_w, p + side * w, p - side * w, prev - side * prev_w, col)
			prev = p
			prev_w = w
	if not areca:
		for k in 5:
			var a := TAU * k / 5.0
			mb.box(Transform3D(Basis(), top + Vector3(cos(a) * 0.35, -0.5, sin(a) * 0.35)), Vector3(0.3, 0.3, 0.3),
				Color(0.18, 0.2, 0.05))
	return mb.commit()


func _palms() -> void:
	var coconut := _palm_mesh(false)
	var areca := _palm_mesh(true)
	var lists := {"coconut": [], "areca": []}
	var cbe := _stage("coimbatore")
	var foot := _stage("foothills")
	var i0: int = route.index_at(cbe["end"] - 250.0)
	var i1: int = route.index_at(foot["start"] + 120.0)
	var bridge_mid: float = (route.marks["bridge_start"] + route.marks["bridge_end"]) * 0.5
	for i in range(i0, i1, 6):
		var d: float = route.dist[i]
		var is_areca := d > bridge_mid
		for side in [1.0, -1.0]:
			for k in 6:
				var off := rng.randf_range(13.0, 170.0)
				var p: Vector3 = route.pts[i] + route.left(i) * off * side + route.tangents[i] * rng.randf_range(-6.0, 6.0)
				if route.noise.get_noise_2d(p.x * 3.0, p.z * 3.0) < -0.15 and off > 30.0:
					continue                     # gaps between groves
				if terrain.near_road(p.x, p.z) > 0.0 or route.near_river(p):
					continue
				var y: float = terrain.height_at(p.x, p.z)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2))
				lists["areca" if is_areca else "coconut"].append(Transform3D(b, Vector3(p.x, y - 0.2, p.z)))
				if off < 22.0:
					_trunk_collider(Vector3(p.x, y, p.z), 0.3, 8.0)
	var node := Node3D.new()
	node.name = "Palms"
	add_child(node)
	for key in lists:
		var cells := {}
		for xf in lists[key]:
			var c := Vector2i(floori(xf.origin.x / 256.0), floori(xf.origin.z / 256.0))
			if not cells.has(c):
				cells[c] = []
			cells[c].append(xf)
		for c in cells:
			var mmi: MultiMeshInstance3D = VegLibrary.multimesh(coconut if key == "coconut" else areca, cells[c], 0.0, 1600.0, true)
			mmi.material_override = mat_vc
			node.add_child(mmi)


func _trunk_collider(p: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = p + Vector3(0, h * 0.5, 0)
	colliders.add_child(cs)


# ----------------------------------------------------------------------------- forest
func _scatter(d0: float, d1: float, keys: Array, per_step: int, off0: float, off1: float, lists: Dictionary,
		step := 5, scale := Vector2(0.75, 1.25), collide := true) -> void:
	for i in range(route.index_at(d0), route.index_at(d1), step):
		for side in [1.0, -1.0]:
			for k in per_step:
				var off := rng.randf_range(off0, off1)
				var p: Vector3 = route.pts[i] + route.left(i) * off * side + route.tangents[i] * rng.randf_range(-5.0, 5.0)
				if terrain.near_road(p.x, p.z) > 0.0:
					continue
				var key: String = keys[rng.randi() % keys.size()]
				if not veg.has(key):
					continue
				var y: float = terrain.height_at(p.x, p.z)
				var s := rng.randf_range(scale.x, scale.y)
				if not lists.has(key):
					lists[key] = []
				lists[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y - 0.15, p.z)))
				if collide and off < 26.0:
					_trunk_collider(Vector3(p.x, y, p.z), 0.35 * s, 5.0 * s)


func _forest() -> void:
	var trees := {}
	var under := {}
	var foot := _stage("foothills")
	var ghat := _stage("ghat")
	var mist := _stage("mist")
	var kot := _stage("kotagiri")
	_scatter(foot["start"] + 60.0, foot["end"], ["eucalyptus_0", "eucalyptus_1", "shola_evergreen_0", "silver_oak_0"], 3, 9.0, 160.0, trees)
	_scatter(ghat["start"], ghat["end"], ["shola_evergreen_0", "shola_evergreen_1", "shola_evergreen_2", "shola_evergreen_3",
		"silver_oak_0", "silver_oak_1", "eucalyptus_0"], 3, 9.0, 200.0, trees)
	_scatter(mist["start"], mist["end"], ["eucalyptus_0", "eucalyptus_1", "shola_evergreen_1"], 1, 60.0, 220.0, trees, 8)
	_scatter(kot["start"], kot["end"], ["cypress_0", "cypress_1", "cypress_2", "eucalyptus_1"], 1, 24.0, 120.0, trees, 8)
	_scatter(foot["start"], ghat["end"], ["shrub_0", "shrub_1", "shrub_2", "fern_0", "fern_1", "fern_2"], 2, 7.0, 30.0,
		under, 4, Vector2(0.7, 1.3), false)
	var node := Node3D.new()
	node.name = "Forest"
	add_child(node)
	for key in trees:
		veg.place(node, key, trees[key], true)
	for key in under:
		veg.place(node, key, under[key], false, 160.0)
	# distant forest cover on the Nilgiri slopes, beyond the detailed corridor
	var far: Array = []
	var d0: float = ghat["start"] - 1500.0
	var d1: float = mist["end"]
	var tries := 0
	while far.size() < 6000 and tries < 60000:
		tries += 1
		var f: Transform3D = route.frame_at(rng.randf_range(d0, d1))
		var off := rng.randf_range(230.0, 1400.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p: Vector3 = f.origin + f.basis.x * off + f.basis.z * rng.randf_range(-60.0, 60.0)
		if terrain.near_road(p.x, p.z) > 0.0:
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5))
		far.append(Transform3D(b, Vector3(p.x, terrain.height_at(p.x, p.z) - 0.3, p.z)))
	var keys := ["far_canopy_0", "far_canopy_1", "far_canopy_2"]
	var third := far.size() / 3
	for k in 3:
		veg.place(node, keys[k], far.slice(k * third, (k + 1) * third), false, 0.0, 768.0)


# ----------------------------------------------------------------------------- tea gardens
func _tea() -> void:
	var mist := _stage("mist")
	var kot := _stage("kotagiri")
	var i0: int = route.index_at(route.marks["tea_stall"] + 60.0)
	var i1: int = route.index_at(kot["start"] + 200.0)
	if route.is_real:
		i0 = route.index_at(mist["start"])
		i1 = route.index_at(kot["end"] - 150.0)
	var mb := MB.new()
	for side in [1.0, -1.0]:
		for k in 16:
			if k % 6 == 5:
				continue                        # a footpath every few rows
			var off := 12.5 + k * 2.1
			var strip: Array = []
			for i in range(i0, i1, 2):                 # every other sample: 4 m segments read the same
				var p: Vector3 = route.pts[i] + route.left(i) * off * side
				# cheapest tests first; slope from three height reads instead of four
				var ok: bool = not route.is_real or route.noise.get_noise_2d(p.x * 0.6, p.z * 0.6) > -0.05   # estates in blocks
				ok = ok and terrain.near_road(p.x, p.z) == 0.0
				var y := 0.0
				if ok:
					y = terrain.height_at(p.x, p.z)
					var sx: float = terrain.height_at(p.x + 2.0, p.z) - y
					var sz: float = terrain.height_at(p.x, p.z + 2.0) - y
					ok = Vector2(sx, sz).length() < 1.4
				if ok:
					strip.append(Vector3(p.x, y, p.z))
				else:
					_hedge(mb, strip)
					strip = []
			_hedge(mb, strip)
		if mb.verts.size() > 60000:
			_mesh(mb, "TeaGardens", 900.0)
			mb = MB.new()
	var tea_last := _mesh(mb, "TeaGardens", 900.0)
	tea_last.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shade := {}
	_scatter(mist["start"] + 150.0, kot["start"] + 200.0, ["silver_oak_0", "silver_oak_1"], 1, 14.0, 60.0, shade, 12,
		Vector2(0.8, 1.2))
	var node := Node3D.new()
	node.name = "ShadeTrees"
	add_child(node)
	for key in shade:
		veg.place(node, key, shade[key], true)


const PROFILE := [Vector2(-0.6, 0.0), Vector2(-0.52, 0.45), Vector2(-0.3, 0.78), Vector2(0.0, 0.86),
	Vector2(0.3, 0.78), Vector2(0.52, 0.45), Vector2(0.6, 0.0)]


## A continuous clipped tea hedge along a contour row.
func _hedge(mb, strip: Array) -> void:
	if strip.size() < 3:
		return
	var rings: Array = []
	for i in strip.size():
		var a: Vector3 = strip[maxi(i - 1, 0)]
		var b: Vector3 = strip[mini(i + 1, strip.size() - 1)]
		var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var lat := Vector3(t.z, 0, -t.x)
		var p: Vector3 = strip[i]
		var bump := 0.9 + 0.2 * route.noise.get_noise_2d(p.x * 20.0, p.z * 20.0)
		var ring: Array = []
		for q in PROFILE:
			ring.append(p + lat * q.x + Vector3(0, q.y * bump, 0))
		rings.append(ring)
	for i in rings.size() - 1:
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		var centre: Vector3 = strip[i]
		for m in PROFILE.size() - 1:
			var col := Color(0.14, 0.30, 0.05) if m == 2 or m == 3 else Color(0.06, 0.19, 0.035)
			var mid: Vector3 = (ra[m] + ra[m + 1]) * 0.5
			mb.quad(ra[m], rb[m], rb[m + 1], ra[m + 1], col, mid - centre)


# ----------------------------------------------------------------------------- check post, tea stall, gate
func _checkpost() -> void:
	var d: float = route.marks["checkpost"]
	var f: Transform3D = route.frame_at(d)
	var left := f.basis.x
	var mb := MB.new()
	var hut := f.origin + left * (HALF + 5.5) + f.basis.z * 7.0
	mb.box(Transform3D(f.basis, hut + Vector3(0, 1.1, 0)), Vector3(3.2, 2.8, 3.4), Color(0.75, 0.70, 0.55))
	mb.box(Transform3D(f.basis, hut + Vector3(0, -1.0, 0)), Vector3(3.4, 1.6, 3.6), Color(0.3, 0.28, 0.26))
	_gable(mb, f.basis, hut + Vector3(0, 2.5, 0), 3.2, 3.4, Color(0.1, 0.25, 0.1), Color(0.75, 0.70, 0.55))
	mb.box(Transform3D(f.basis, hut + Vector3(0, 1.4, 0) - left * 1.62), Vector3(0.05, 0.9, 1.4), Color(0.05, 0.06, 0.07))
	var board := hut - left * 1.7 + Vector3(0, 3.1, 0) + f.basis.z * 1.9
	mb.box(Transform3D(f.basis, board), Vector3(0.1, 0.9, 3.2), Color(0.05, 0.3, 0.1))
	_mesh(mb, "CheckPost", 600.0, mat_plaster)
	_label("FOREST CHECK POST", board - left * 0.07, -left, 34, Color.WHITE, 150.0)
	_box_collider(Transform3D(f.basis, hut + Vector3(0, 1.0, 0)), Vector3(3.2, 3.0, 3.4))

	# boom barrier across our (left) lane, hinged at the verge
	barrier_pivot = Node3D.new()
	barrier_pivot.name = "BoomBarrier"
	barrier_pivot.transform = Transform3D(f.basis, f.origin + left * (HALF + 0.4) + Vector3(0, 1.0, 0))
	add_child(barrier_pivot)
	var pole := MB.new()
	for k in 8:
		pole.box(Transform3D(Basis(), Vector3(-0.28 - k * 0.56, 0, 0)), Vector3(0.56, 0.12, 0.12),
			Color(0.75, 0.03, 0.02) if k % 2 == 0 else Color(0.85, 0.85, 0.82))
	var post := MB.new()
	post.box(Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(0.3, 1.1, 0.3), Color(0.3, 0.3, 0.3))
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole.commit()
	pole_mi.material_override = mat_vc
	barrier_pivot.add_child(pole_mi)
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post.commit()
	post_mi.material_override = mat_vc
	barrier_pivot.add_child(post_mi)
	var body := StaticBody3D.new()
	barrier_shape = CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4.5, 0.9, 0.4)
	barrier_shape.shape = bx
	barrier_shape.position = Vector3(-2.25, -0.2, 0)
	body.add_child(barrier_shape)
	barrier_pivot.add_child(body)


## Lift the boom (the game calls this once the jeep has stopped at it).
func open_barrier() -> void:
	if barrier_pivot == null or barrier_shape.disabled:
		return
	barrier_shape.set_deferred("disabled", true)
	var base := barrier_pivot.basis
	var axis := base.z.normalized()
	create_tween().tween_method(func(a: float): barrier_pivot.basis = base.rotated(axis, a),
		0.0, deg_to_rad(-80.0), 1.6).set_trans(Tween.TRANS_SINE)


func _tea_stall() -> void:
	var d: float = route.marks["tea_stall"]
	var f: Transform3D = route.frame_at(d)
	var left := f.basis.x
	var a: float = route.natural_h(f.origin.x + left.x * 14.0, f.origin.z + left.z * 14.0)
	var b: float = route.natural_h(f.origin.x - left.x * 14.0, f.origin.z - left.z * 14.0)
	var side := 1.0 if a < b else -1.0                  # the valley side, for the view
	var out := left * side
	var c := f.origin + out * (HALF + 5.0)
	var y := f.origin.y - 0.3
	var ground: float = terrain.height_at(c.x, c.z)
	var mb := MB.new()
	mb.box(Transform3D(f.basis, Vector3(c.x, (y + minf(ground, y) - 3.0) * 0.5, c.z)), Vector3(5.0, y - minf(ground, y) + 3.0, 6.0),
		Color(0.3, 0.28, 0.25))
	for px in [-2.1, 2.1]:
		for pz in [-2.6, 2.6]:
			mb.box(Transform3D(f.basis, Vector3(c.x, y + 1.2, c.z) + f.basis.x * px + f.basis.z * pz), Vector3(0.12, 2.4, 0.12),
				Color(0.2, 0.12, 0.07))
	var roof := Basis(f.basis.z, deg_to_rad(8.0 * side)) * f.basis
	mb.box(Transform3D(roof, Vector3(c.x, y + 2.5, c.z)), Vector3(5.2, 0.06, 6.4), Color(0.35, 0.07, 0.05))
	mb.box(Transform3D(f.basis, Vector3(c.x, y + 0.55, c.z) + out * 1.2), Vector3(0.6, 1.1, 4.0), Color(0.45, 0.28, 0.12))
	mb.box(Transform3D(f.basis, Vector3(c.x, y + 0.25, c.z) - out * 1.3), Vector3(0.45, 0.45, 3.2), Color(0.35, 0.2, 0.1))
	mb.cylinder(Transform3D(Basis(), Vector3(c.x, y + 1.1, c.z) + out * 1.2 + f.basis.z * 1.2), 0.18, 0.18, 0.35,
		Color(0.55, 0.55, 0.55), 8)
	_mesh(mb, "TeaStall", 700.0, mat_plaster)
	var board := Vector3(c.x, y + 2.9, c.z) - out * 2.4
	_label("TEA STALL\nChai ₹15 · Bajji · Bun", board, -out, 34, Color(1.0, 0.85, 0.3), 200.0)
	tea_stall_pos = Vector3(c.x, y, c.z)
	for k in 4:
		_chairs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, y, c.z) - out * 0.4 + f.basis.z * (k * 0.9 - 1.35)))


func _gate() -> void:
	if route.resort_attached:
		return                              # your resort has the real gate
	var d: float = route.length - 60.0
	var f: Transform3D = route.frame_at(d)
	var left := f.basis.x
	var mb := MB.new()
	var span := HALF + 1.6
	for s in [1.0, -1.0]:
		var p: Vector3 = f.origin + left * span * s
		mb.box(Transform3D(f.basis, p + Vector3(0, 1.4, 0)), Vector3(1.1, 3.8, 1.1), Color(0.22, 0.21, 0.19))
		_box_collider(Transform3D(f.basis, p + Vector3(0, 1.4, 0)), Vector3(1.1, 3.8, 1.1))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.62, 0.3)
		lamp.light_energy = 1.6
		lamp.omni_range = 9.0
		lamp.position = p + Vector3(0, 2.6, 0) - f.basis.z * 0.7
		add_child(lamp)
		mb.box(Transform3D(f.basis, lamp.position), Vector3(0.25, 0.35, 0.25), Color(1.0, 0.75, 0.4))
	mb.box(Transform3D(f.basis, f.origin + Vector3(0, 3.55, 0)), Vector3(span * 2.0 + 1.6, 0.35, 0.45), Color(0.3, 0.16, 0.07))
	for k in 7:
		var x := lerpf(-span, span, k / 6.0)
		mb.box(Transform3D(f.basis, f.origin + left * x + Vector3(0, 3.8, 0)), Vector3(0.18, 0.18, 1.6), Color(0.3, 0.16, 0.07))
	_mesh(mb, "Gate", 800.0, mat_plaster)
	var l := _label("THE MIST VILLAGE", f.origin + Vector3(0, 3.1, 0) - f.basis.z * 0.26, -f.basis.z, 44,
		Color(0.85, 0.66, 0.35), 300.0)
	l.outline_size = 0
	gate_pos = f.origin


# ----------------------------------------------------------------------------- Poly Haven props (CC0)
## Starts background loads of every prop model (ResourceLoader's own threads, safe unlike GDScript workers).
static func preload_models() -> void:
	for f in DirAccess.get_files_at(PROP_DIR):
		if f.ends_with(".glb.import"):           # exported builds list only the .import stubs
			ResourceLoader.load_threaded_request(PROP_DIR + f.trim_suffix(".import"))


func _prop(name: String) -> Mesh:
	if _prop_cache.has(name):
		return _prop_cache[name]
	var m: Mesh = null
	var path := PROP_DIR + name + ".glb"
	if ResourceLoader.exists(path):
		var scene: PackedScene
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			scene = ResourceLoader.load_threaded_get(path)
		else:
			scene = load(path)
		var node := scene.instantiate()
		var found := node.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			m = (found[0] as MeshInstance3D).mesh
		node.free()
	_prop_cache[name] = m
	return m


## MultiMesh chunks of one prop.
func _place_prop(name: String, xfs: Array, shadows: bool, range_end: float, cell := 256.0) -> void:
	var m := _prop(name)
	if m == null or xfs.is_empty():
		return
	var cells := {}
	for xf in xfs:
		var c := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(xf)
	var node := Node3D.new()
	node.name = name.capitalize().replace(" ", "")
	add_child(node)
	for c in cells:
		node.add_child(VegLibrary.multimesh(m, cells[c], 0.0, range_end, shadows))


## Wooden distribution poles on the far verge with three sagging wires, all along the route.
func _power_lines() -> void:
	if _prop("power_pole") == null:
		return
	var xfs: Array = []
	var wires := MB.new()
	var tops: Array = []
	var scale := 1.35
	var bs: float = route.marks["bridge_start"] - 30.0
	var be: float = route.marks["bridge_end"] + 30.0
	var d := 20.0
	var prev: Array = []
	while d < route.length - 120.0:
		var f: Transform3D = route.frame_at(d, -(HALF + 3.4))
		var ok: bool = not (d > bs and d < be) and terrain.near_road(f.origin.x, f.origin.z) < 0.5
		if ok:
			var y: float = terrain.height_at(f.origin.x, f.origin.z) - 0.3
			var xf := Transform3D(f.basis.scaled(Vector3.ONE * scale), Vector3(f.origin.x, y, f.origin.z))
			xfs.append(xf)
			var cur: Array = [xf * Vector3(0.5, 5.6, 0), xf * Vector3(-0.5, 5.6, 0), xf * Vector3(0, 6.0, 0)]
			if not prev.is_empty() and (cur[0] as Vector3).distance_to(prev[0]) < 80.0:
				for k in 3:
					_wire(wires, prev[k], cur[k])
			prev = cur
		else:
			prev = []
		d += 48.0
	_place_prop("power_pole", xfs, false, 700.0, 512.0)
	var wm := MeshInstance3D.new()
	wm.name = "PowerLines"
	wm.mesh = wires.commit()
	wm.material_override = MB.vertex_color_material(0.6, BaseMaterial3D.CULL_DISABLED)
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wm.visibility_range_end = 600.0
	add_child(wm)
	for xf in xfs:
		_trunk_collider(xf.origin, 0.15, 7.0)


## A sagging wire as two crossed thin ribbons (visible from any angle).
func _wire(mb, a: Vector3, b: Vector3) -> void:
	var segs := 8
	var sag := a.distance_to(b) * 0.025
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized() * 0.012
	var up := Vector3(0, 0.012, 0)
	var col := Color(0.05, 0.05, 0.05)
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var p0 := a.lerp(b, t0) - Vector3(0, sag * 4.0 * t0 * (1.0 - t0), 0)
		var p1 := a.lerp(b, t1) - Vector3(0, sag * 4.0 * t1 * (1.0 - t1), 0)
		mb.quad(p0 - up, p1 - up, p1 + up, p0 + up, col, side)
		mb.quad(p0 - side, p1 - side, p1 + side, p0 + side, col, Vector3.UP)


## Mossy rocks, shrubs and ferns on the verges of the forest and ghat roads.
func _verges() -> void:
	var foot := _stage("foothills")
	var mist := _stage("mist")
	var sets := {}
	for name in ["mossy_rock_1", "mossy_rock_2", "mossy_rock_3", "mossy_rock_4", "mossy_rock_5", "mossy_rock_6",
			"shrub_a", "shrub_b", "shrub_c", "shrub_d", "fern"]:
		sets[name] = []
	var names: Array = sets.keys()
	for i in range(route.index_at(foot["start"]), route.index_at(mist["end"]), 4):
		for side in [1.0, -1.0]:
			if rng.randf() > 0.55:
				continue
			var off := rng.randf_range(6.8, 30.0)
			var p: Vector3 = route.pts[i] + route.left(i) * off * side + route.tangents[i] * rng.randf_range(-4.0, 4.0)
			if terrain.near_road(p.x, p.z) > 0.45:
				continue
			var name: String = names[rng.randi() % names.size()]
			var rock := name.begins_with("mossy")
			var s := rng.randf_range(0.35, 0.9) if rock else rng.randf_range(0.7, 1.3)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			sets[name].append(Transform3D(b, Vector3(p.x, terrain.height_at(p.x, p.z) - (0.25 * s if rock else 0.05), p.z)))
	for name in sets:
		_place_prop(name, sets[name], false, 220.0, 320.0)


func _street_furniture() -> void:
	_place_prop("shutter", _shutters, false, 220.0, 256.0)
	_place_prop("monobloc_chair", _chairs, false, 120.0, 256.0)
	_place_prop("utility_box", _boxes, false, 150.0, 256.0)
	# concrete barriers staggered on the far lane at the check post
	var cp: float = route.marks["checkpost"]
	var bars: Array = []
	for k in 4:
		var f: Transform3D = route.frame_at(cp - 16.0 + k * 1.7, -(HALF + 0.9))
		bars.append(Transform3D(f.basis * Basis(Vector3.UP, PI * 0.5), f.origin - Vector3(0, 0.05, 0)))
	_place_prop("road_barrier", bars, true, 300.0)
	for xf in bars:
		_box_collider(Transform3D(xf.basis, xf.origin + Vector3(0, 0.4, 0)), Vector3(1.5, 0.8, 0.6))
