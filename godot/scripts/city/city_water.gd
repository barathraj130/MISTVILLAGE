extends Node3D
## Coimbatore's tanks, ponds and lakes (tools/citygen/water.py → assets/city/water.bin; design tools/ponds.py,
## previews/ponds/). The ground under them is carved in the tiles; here each water body within NEAR of the target
## is built — and freed again beyond FAR:
##   every body   the water (clear over the shallows, murky green-brown deeper, wind ripples, sky reflection,
##                green scum where it is shallow), reeds and cattails along the edge, floating water hyacinth,
##                egrets wading
##   kuttai       lotus patches, palmyra palms and Prosopis scrub on the banks
##   walkway      the restored lakes (Ukkadam, Valankulam, Kurichi): stone-pitched bund, a paved walkway with
##                granite kerbs, railings, lamps and benches on top
##   temple       the carved theppakulam (steps, parapet, gate, mandapam, lamp pillar) fitted to the tank

const Streamer := preload("res://scripts/city/city_streamer.gd")
const NEAR := 900.0
const FAR := 1200.0
const SLOPE := 5.0                  # = water.py
const WALK := 9.0

var target: Node3D
var streamer
var bodies: Array = []
var meshes := {}
var water_mat: ShaderMaterial
var mats := {}
var _t := 0.0


func _ready() -> void:
	var f := FileAccess.open("res://assets/city/water.bin", FileAccess.READ)
	if f == null:
		return
	if f.get_buffer(4).get_string_from_ascii() != "CWAT":
		return
	var n := f.get_32()
	for i in n:
		var b := {}
		b["style"] = f.get_8()
		b["level"] = f.get_float()
		b["bund"] = f.get_float()
		b["rect"] = [f.get_float(), f.get_float(), f.get_float(), f.get_float(), f.get_float()]
		var np := f.get_16()
		var poly := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in np:
			var p := Vector2(f.get_float(), f.get_float())
			poly.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
		var bank := PackedFloat32Array()
		for k in np:
			bank.append(f.get_float())
		# points at most 8 m apart, so ribbons and scatter lines follow the shore closely
		var dp := PackedVector2Array()
		var db := PackedFloat32Array()
		for k in np:
			var a := poly[k]
			var c := poly[(k + 1) % np]
			var steps := maxi(1, ceili(a.distance_to(c) / 8.0))
			for q in steps:
				dp.append(a.lerp(c, float(q) / steps))
				db.append(lerpf(bank[k], bank[(k + 1) % np], float(q) / steps))
		b["poly"] = dp
		b["bank"] = db
		b["box"] = Rect2(lo, hi - lo)
		b["name"] = f.get_buffer(f.get_16()).get_string_from_utf8()
		b["node"] = null
		bodies.append(b)
	for nm in ["reeds_1", "reeds_2", "reeds_3", "hyacinth_1", "hyacinth_2", "lotus_1", "lotus_2", "egret_stand",
			"egret_feed", "palmyra", "prosopis_1", "prosopis_2", "theppakulam"]:
		meshes[nm] = _mesh("res://assets/ponds/%s.glb" % nm)
	water_mat = ShaderMaterial.new()
	water_mat.shader = _water_shader()
	var wn := NoiseTexture2D.new()
	wn.seamless = true
	wn.as_normal_map = true
	wn.bump_strength = 6.0
	wn.width = 512
	wn.height = 512
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	wn.noise = fn
	water_mat.set_shader_parameter("waves", wn)
	var sn := NoiseTexture2D.new()
	sn.seamless = true
	sn.width = 256
	sn.height = 256
	var fs := FastNoiseLite.new()
	fs.frequency = 0.03
	sn.noise = fs
	water_mat.set_shader_parameter("patches", sn)


func _process(dt: float) -> void:
	_t += dt
	if target == null or _t < 0.5:
		return
	_t = 0.0
	var p := Vector2(target.global_position.x, target.global_position.z)
	for b in bodies:
		var r: Rect2 = b["box"]
		var d := _rect_dist(r, p)
		if b["node"] == null and d < NEAR:
			b["node"] = _build(b)
			add_child(b["node"])
			return                                      # one a step: no hitch
		elif b["node"] != null and d > FAR:
			b["node"].queue_free()
			b["node"] = null


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()


# ------------------------------------------------------------------------------------------------- building
func _build(b: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Water_%s" % (b["name"] if b["name"] != "" else str(bodies.find(b)))
	var poly: PackedVector2Array = b["poly"]
	var L: float = b["level"]
	var st: int = b["style"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b["name"]) + int(poly[0].x * 13.0 + poly[0].y * 7.0)
	if st == 2:
		_temple(node, b)
		return node
	node.add_child(_surface(poly, L))
	# reeds and cattails all round, hyacinth drifting a few metres out, egrets in the shallows
	_scatter(node, _offset(poly, -1.0), 3.0 if st == 1 else 2.4, 0.55 if st == 1 else 0.7, ["reeds_1", "reeds_2", "reeds_3"],
		L - 0.1, rng, 1.2, Vector2(0.8, 1.2), 160.0)
	_scatter(node, _offset(poly, -7.0), 24.0, 0.7, ["hyacinth_1", "hyacinth_2"], L, rng, 3.0, Vector2(0.8, 1.6), 220.0)
	_scatter(node, _offset(poly, -1.8), 45.0, 0.9, ["egret_stand", "egret_feed", "egret_stand"], L - 0.15, rng, 1.0,
		Vector2(0.9, 1.1), 120.0)
	if st == 1:
		_walkway(node, b)
	else:
		_shore(node, b)
		_scatter(node, _offset(poly, -11.0), 32.0, 0.75, ["lotus_1", "lotus_2"], L, rng, 4.0, Vector2(1.0, 1.6), 200.0)
		_scatter(node, _offset(poly, 7.0), 15.0, 0.45, ["palmyra"], L + 0.75, rng, 3.0, Vector2(0.9, 1.15), 600.0, true)
		_scatter(node, _offset(poly, 5.0), 6.0, 0.5, ["prosopis_1", "prosopis_2"], L + 0.55, rng, 2.0, Vector2(0.8, 1.3), 260.0, true)
	return node


## The water: the outline filled at the water level (triangulated).
func _surface(poly: PackedVector2Array, y: float) -> MeshInstance3D:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("water outline did not triangulate (%d points)" % poly.size())
	var v := PackedVector3Array()
	for p in poly:
		v.append(Vector3(p.x, y, p.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var nrm := PackedVector3Array()
	nrm.resize(v.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = nrm
	# Godot's front faces wind clockwise seen from the front: make the triangles face up
	var ii := PackedInt32Array(idx)
	if ii.size() >= 3:
		var a := v[ii[0]]
		var c := (v[ii[1]] - a).cross(v[ii[2]] - a)
		if c.y > 0.0:
			for t in range(0, ii.size(), 3):
				var tmp := ii[t + 1]
				ii[t + 1] = ii[t + 2]
				ii[t + 2] = tmp
	arr[Mesh.ARRAY_INDEX] = ii
	var m := ArrayMesh.new()
	if ii.size() >= 3:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The outline moved outward (+) or inward (−) by `d` metres, keeping one point per original point (so two
## offsets can be stitched into a ribbon). Mitred vertex normals, clamped in sharp corners.
static func _offset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var sgn := 1.0 if area > 0.0 else -1.0
	var out := PackedVector2Array()
	for i in n:
		var a := poly[(i - 1 + n) % n]
		var b := poly[i]
		var c := poly[(i + 1) % n]
		var e1 := (b - a).normalized()
		var e2 := (c - b).normalized()
		var n1 := Vector2(e1.y, -e1.x) * sgn
		var n2 := Vector2(e2.y, -e2.x) * sgn
		var m := n1 + n2
		if m.length() < 1e-4:
			m = n1
		m = m.normalized()
		m /= maxf(m.dot(n1), 0.5)
		out.append(b + m * d)
	return out


## Things along a line: every `step` m with probability `prob`, jittered, random kind / turn / size.
## Land things (`land`) take the tile's ground height when it is known.
func _scatter(node: Node3D, line: PackedVector2Array, step: float, prob: float, kinds: Array, y: float,
		rng: RandomNumberGenerator, jitter: float, scale: Vector2, vis: float, land := false) -> void:
	var by := {}
	var n := line.size()
	var carry := 0.0
	for i in n:
		var a := line[i]
		var b := line[(i + 1) % n]
		var L := a.distance_to(b)
		var t := carry
		while t < L:
			if rng.randf() < prob:
				var p := a.lerp(b, t / maxf(L, 1e-4)) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
				var yy := y
				if land and streamer:
					var g: float = streamer.height_at(p.x, p.y)
					if not is_nan(g):
						yy = g - 0.05
				var k: String = kinds[rng.randi() % kinds.size()]
				# grouped in 64 m cells: a visibility range is measured from the whole MultiMesh's centre
				var key := "%s|%d|%d" % [k, floori(p.x / 64.0), floori(p.y / 64.0)]
				if not by.has(key):
					by[key] = []
				var s := rng.randf_range(scale.x, scale.y)
				by[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, yy, p.y)))
			t += step
		carry = t - L
	for key in by:
		var k: String = key.get_slice("|", 0)
		if meshes.get(k) == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = by[key].size()
		for i in by[key].size():
			mm.set_instance_transform(i, by[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = vis + 45.0
		if vis < 200.0:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


## A village pond's bank: wet dark mud from under the water to 1.2 m out, then the city ground up to the bank
## height 6 m out (water.bin) — finer than the 8 m terrain grid, which it covers.
func _shore(node: Node3D, b: Dictionary) -> void:
	var poly: PackedVector2Array = b["poly"]
	var L: float = b["level"]
	var bank: PackedFloat32Array = b["bank"]
	var a := _offset(poly, -1.2)
	var m := _offset(poly, 1.2)
	var o := _offset(poly, 6.0)
	var wet := SurfaceTool.new()
	wet.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dry := SurfaceTool.new()
	dry.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var run := 0.0
	for i in n:
		var j := (i + 1) % n
		var seg := poly[i].distance_to(poly[j])
		if seg > 60.0:
			continue
		# 1.2 m out: the carved ground's own height there (water.py: at least L + 0.12 + 0.09 d)
		var ym_i := L + 0.12 + 0.09 * 1.2 + 0.05
		var ym_j := ym_i
		_quad(wet, Vector3(a[i].x, L - 0.45, a[i].y), Vector3(a[j].x, L - 0.45, a[j].y),
			Vector3(m[j].x, ym_j, m[j].y), Vector3(m[i].x, ym_i, m[i].y), run, seg)
		_quad(dry, Vector3(m[i].x, ym_i, m[i].y), Vector3(m[j].x, ym_j, m[j].y),
			Vector3(o[j].x, bank[j] + 0.08, o[j].y), Vector3(o[i].x, bank[i] + 0.08, o[i].y), run, seg)
		run += seg
	_add(node, wet.commit(), _mat("mud"))
	_add(node, dry.commit(), streamer.ground_mat if streamer and streamer.ground_mat else _mat("mud"))


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, run: float, seg: float) -> void:
	var nrm := (p1 - p0).cross(p3 - p0).normalized()
	var flip := nrm.y < 0.0
	if flip:
		nrm = -nrm
	var P := [p0, p1, p2, p3]
	var uv := [Vector2(run, 0) / 3.0, Vector2(run + seg, 0) / 3.0, Vector2(run + seg, 2.4) / 3.0, Vector2(run, 2.4) / 3.0]
	for t in ([[0, 1, 2], [0, 2, 3]] if flip else [[0, 2, 1], [0, 3, 2]]):
		for q in t:
			st.set_normal(nrm)
			st.set_uv(uv[q])
			st.add_vertex(P[q])


## A restored city lake: stone pitching from below the water up the bund, the walkway on top with granite
## kerbs, railings on the water side, lamps and benches.
func _walkway(node: Node3D, b: Dictionary) -> void:
	var poly: PackedVector2Array = b["poly"]
	var L: float = b["level"]
	var B: float = b["bund"]
	var r0 := _offset(poly, -1.5)
	var r1 := _offset(poly, SLOPE)
	var w0 := _offset(poly, SLOPE + 0.3)
	var w1 := _offset(poly, SLOPE + 4.3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(st, r0, r1, L - 0.9, B + 0.1, 2.4)
	var pitch := st.commit()
	_add(node, pitch, _mat("pitching"))
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(st, w0, w1, B + 0.12, B + 0.12, 3.0)
	_ribbon(st, r1, w0, B, B + 0.12, 3.0)
	_add(node, st.commit(), _mat("pavers"))
	# kerbs, rails, lamps, benches
	var k := SurfaceTool.new()
	k.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array = []
	var lamps: Array = []
	var benches: Array = []
	var rl := _offset(poly, SLOPE + 0.5)
	var lamp_at := 0.0
	var bench_at := 18.0
	var run := 0.0
	for i in rl.size():
		var a := rl[i]
		var c := rl[(i + 1) % rl.size()]
		var len := a.distance_to(c)
		if len < 0.01 or len > 30.0:
			continue
		var dir := (c - a) / len
		_beam(k, w1[i], w1[(i + 1) % w1.size()], B + 0.12, 0.25, 0.3)
		for zz in [0.45, 0.95]:
			_beam(rail, a, c, B + 0.12 + zz, 0.05, 0.05)
		var t := fmod(2.0 - fmod(run, 2.0), 2.0)
		while t < len:
			var q := a + dir * t
			posts.append(Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), Vector3(q.x, B + 0.12, q.y)))
			t += 2.0
		run += len
		while lamp_at < run:
			var f := 1.0 - (run - lamp_at) / len
			var q := w1[i].lerp(w1[(i + 1) % w1.size()], f).lerp(w0[i].lerp(w0[(i + 1) % w0.size()], f), 0.08)
			lamps.append(Transform3D(Basis(), Vector3(q.x, B + 0.12, q.y)))
			lamp_at += 24.0
		while bench_at < run:
			var f := 1.0 - (run - bench_at) / len
			var q := w0[i].lerp(w0[(i + 1) % w0.size()], f).lerp(w1[i].lerp(w1[(i + 1) % w1.size()], f), 0.8)
			benches.append(Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), Vector3(q.x, B + 0.12, q.y)))
			bench_at += 37.0
	_add(node, k.commit(), _mat("granite"))
	# lake-wide meshes: no visibility range (it would be measured from the lake's centre); the lake itself is
	# only built within NEAR
	_add(node, rail.commit(), _mat("rail"))
	_multi(node, _box_mesh(Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0)), _mat("rail"), posts, 0.0)
	_multi(node, _lamp_mesh(), _mat("lamp"), lamps, 0.0)
	_multi(node, _bench_mesh(), _mat("granite"), benches, 0.0)


## A ribbon between two matched outlines at heights ya / yb (u along, v across; tile = texture metres).
static func _ribbon(st: SurfaceTool, a: PackedVector2Array, b: PackedVector2Array, ya: float, yb: float, tile: float) -> void:
	var n := a.size()
	var run := 0.0
	var w := a[0].distance_to(b[0])
	for i in n:
		var j := (i + 1) % n
		var seg := a[i].distance_to(a[j])
		if seg > 30.0:
			run += seg
			continue
		var p := [Vector3(a[i].x, ya, a[i].y), Vector3(a[j].x, ya, a[j].y), Vector3(b[j].x, yb, b[j].y), Vector3(b[i].x, yb, b[i].y)]
		var uv := [Vector2(run / tile, 0), Vector2((run + seg) / tile, 0), Vector2((run + seg) / tile, w / tile), Vector2(run / tile, w / tile)]
		var nrm: Vector3 = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
		# Godot's front faces wind clockwise seen from the front
		if nrm.y < 0.0:
			nrm = -nrm
			for t in [[0, 1, 2], [0, 2, 3]]:
				for q in t:
					st.set_normal(nrm)
					st.set_uv(uv[q])
					st.add_vertex(p[q])
		else:
			for t in [[0, 2, 1], [0, 3, 2]]:
				for q in t:
					st.set_normal(nrm)
					st.set_uv(uv[q])
					st.add_vertex(p[q])
		run += seg


## A rectangular beam from a to b (2D) at height y (its bottom), w wide, h high.
static func _beam(st: SurfaceTool, a: Vector2, b: Vector2, y: float, w: float, h: float) -> void:
	var d := (b - a)
	if d.length() < 0.01:
		return
	var s := Vector2(-d.y, d.x).normalized() * w * 0.5
	var c := [a - s, b - s, b + s, a + s]
	var P := []
	for zz in [y, y + h]:
		for q in c:
			P.append(Vector3(q.x, zz, q.y))
	for f in [[4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]:
		var nrm: Vector3 = (P[f[1]] - P[f[0]]).cross(P[f[3]] - P[f[0]]).normalized()
		var centre: Vector3 = (P[f[0]] + P[f[2]]) * 0.5
		var mid := Vector3((a.x + b.x) * 0.5, y + h * 0.5, (a.y + b.y) * 0.5)
		var flip := nrm.dot(centre - mid) < 0.0
		for t in ([[0, 2, 1], [0, 3, 2]] if not flip else [[0, 1, 2], [0, 2, 3]]):
			for q in t:
				st.set_normal(-nrm if flip else nrm)
				st.add_vertex(P[f[q]])


func _add(node: Node3D, m: Mesh, mat: Material, vis := 0.0) -> void:
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	if vis > 0.0:
		mi.visibility_range_end = vis
	node.add_child(mi)


func _multi(node: Node3D, mesh: Mesh, mat: Material, xf: Array, vis: float) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if vis > 0.0:
		mmi.visibility_range_end = vis
	node.add_child(mmi)


static func _box_mesh(size: Vector3, centre: Vector3) -> Mesh:
	var bm := BoxMesh.new()
	bm.size = size
	var st := SurfaceTool.new()
	st.create_from(bm, 0)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] += centre
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _lamp_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(0.12, 4.2, 0.12), Vector3(0, 2.1, 0)], [Vector3(0.35, 0.18, 0.35), Vector3(0, 4.3, 0)]]:
		st.append_from(_box_mesh(part[0], part[1]), 0, Transform3D())
	return st.commit()


static func _bench_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(1.6, 0.06, 0.42), Vector3(0, 0.42, 0)], [Vector3(0.2, 0.4, 0.38), Vector3(-0.6, 0.2, 0)],
			[Vector3(0.2, 0.4, 0.38), Vector3(0.6, 0.2, 0)]]:
		st.append_from(_box_mesh(part[0], part[1]), 0, Transform3D())
	return st.commit()


## The theppakulam model fitted to the tank's rectangle; its water is the inner square.
func _temple(node: Node3D, b: Dictionary) -> void:
	var r: Array = b["rect"]
	var L: float = b["level"]
	var sx: float = r[3] / 44.0
	var sz: float = r[4] / 44.0
	var basis := Basis(Vector3.UP, -float(r[2])) * Basis.from_scale(Vector3(sx, 1.0, sz))
	if meshes.get("theppakulam"):
		var mi := MeshInstance3D.new()
		mi.mesh = meshes["theppakulam"]
		mi.transform = Transform3D(basis, Vector3(r[0], L, r[1]))
		mi.visibility_range_end = 900.0
		node.add_child(mi)
	var half := 13.0
	var sq := PackedVector2Array()
	for c in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var w := basis * Vector3(c.x, 0, c.y)
		sq.append(Vector2(r[0] + w.x, r[1] + w.z))
	node.add_child(_surface(sq, L))


# ------------------------------------------------------------------------------------------------- materials
func _mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("missing " + path)
		return null
	var m: Mesh = Streamer._scene_mesh(path)
	if m == null:
		return null
	for i in m.get_surface_count():
		var cur := m.surface_get_material(i)
		var nm := cur.resource_name if cur else ""
		var rep := _named(nm)
		if rep:
			m.surface_set_material(i, rep)
	return m


func _named(nm: String) -> Material:
	var table := {
		"Reed": [Color(0.16, 0.24, 0.07), true], "Cattail": [Color(0.18, 0.09, 0.04), false],
		"Hyacinth Flower": [Color(0.5, 0.35, 0.75), false], "Hyacinth": [Color(0.1, 0.26, 0.05), true],
		"Lotus Pad": [Color(0.06, 0.16, 0.035), true], "Lotus Flower": [Color(0.9, 0.42, 0.55), false],
		"Egret White": [Color(0.82, 0.82, 0.78), false], "Egret Bill": [Color(0.8, 0.6, 0.08), false],
		"Egret Leg": [Color(0.03, 0.03, 0.03), false], "Palmyra Trunk": [Color(0.09, 0.075, 0.065), false],
		"Palmyra Leaf": [Color(0.2, 0.3, 0.12), true], "Kalasam": [Color(0.75, 0.55, 0.15), false],
		"Niche Shadow": [Color(0.03, 0.028, 0.025), false]}
	for key in table:
		if nm.begins_with(key):
			var k: String = "named_" + key
			if not mats.has(k):
				var m := StandardMaterial3D.new()
				m.albedo_color = table[key][0]
				m.vertex_color_use_as_albedo = table[key][1]
				m.roughness = 0.55
				if table[key][1]:
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				if key == "Kalasam":
					m.metallic = 0.9
					m.roughness = 0.3
				mats[k] = m
			return mats[k]
	if nm.begins_with("Step Granite") or nm.begins_with("Granite"):
		return _mat("granite")
	if nm.begins_with("Carved Granite"):
		return _mat("carved")
	return null                                        # Bark, Prosopis Leaf: the streamer's own materials


func _mat(kind: String) -> Material:
	if mats.has(kind):
		return mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"granite", "carved":
			m.albedo_texture = load("res://assets/ponds/granite.png")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.roughness = 0.8
			if kind == "carved":
				m.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 0.9, 1.0 / 1.2)
				m.normal_enabled = true
				m.normal_texture = load("res://assets/ponds/lotus_panel_normal.png")
				m.ao_enabled = true
				m.ao_texture = load("res://assets/ponds/lotus_panel_ao.png")
		"mud":
			m.albedo_texture = load("res://assets/models/textures/highland_grass_base.jpg")
			m.albedo_color = Color(0.55, 0.43, 0.31)
			m.roughness = 0.55
		"pitching":
			m.albedo_texture = load("res://assets/models/textures/stone_retaining_wall_base.jpg") if ResourceLoader.exists("res://assets/models/textures/stone_retaining_wall_base.jpg") else load("res://assets/ponds/granite.png")
			m.albedo_color = Color(0.85, 0.82, 0.78)
			m.roughness = 0.9
		"pavers":
			m.albedo_texture = load("res://assets/models/textures/parking_pavers_base.jpg")
			m.albedo_color = Color(0.92, 0.88, 0.84)
			m.roughness = 0.85
		"rail":
			m.albedo_color = Color(0.15, 0.32, 0.4)
			m.metallic = 0.3
			m.roughness = 0.4
		"lamp":
			m.albedo_color = Color(0.3, 0.31, 0.33)
			m.metallic = 0.6
			m.roughness = 0.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[kind] = m
	return m


static func _water_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D waves : hint_normal, repeat_enable;
uniform sampler2D patches : repeat_enable;
uniform vec3 deep : source_color = vec3(0.022, 0.04, 0.026);
uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.42);
uniform vec3 scum : source_color = vec3(0.07, 0.1, 0.03);
uniform float murk = 0.9;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv1 = wpos.xz / 23.0 + vec2(TIME * 0.011, TIME * 0.004);
	vec2 uv2 = wpos.xz / 7.0 - vec2(TIME * 0.007, -TIME * 0.013);
	vec3 n1 = texture(waves, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(waves, uv2).rgb * 2.0 - 1.0;
	vec3 nm = normalize(vec3(n1.xy + n2.xy, 2.0)) * 0.5 + 0.5;
	// how much water lies behind this pixel (view-space distance to the bed)
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float bed = -v.z / v.w;
	float thick = max(bed - (-VERTEX.z), 0.0);
	float t = 1.0 - exp(-thick * murk);
	vec2 off = (nm.xy - 0.5) * 0.02 * clamp(thick, 0.0, 1.0);
	vec3 under = texture(screen_tex, SCREEN_UV + off).rgb;
	float shore = 1.0 - smoothstep(0.15, 0.9, thick);
	float sc = smoothstep(0.45, 0.62, texture(patches, wpos.xz / 31.0).r * shore * 1.4);
	ALBEDO = mix(deep * t, scum, sc);
	EMISSION = under * tint * (1.0 - t) * (1.0 - sc);
	ROUGHNESS = mix(0.04, 0.75, sc);
	SPECULAR = mix(0.5, 0.2, sc);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(0.35, 0.0, sc);
}
"""
	return s
