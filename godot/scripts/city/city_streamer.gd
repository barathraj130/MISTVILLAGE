extends Node3D
## Streams the real Coimbatore (tools/citygen/chunk.py → assets/city/) in 256 m tiles around a target:
## tiles within `radius` tiles load, tiles beyond `radius + 1` unload. Reading a binary tile, building its
## meshes, MultiMeshes and collision shapes all happens on worker threads; the main thread only adds the
## finished nodes, at most `per_frame` tiles a frame, nearest first. Nothing global is kept except the index
## and the designed-building meshes.
##
## A tile holds: ground (33 × 33 heights, 8 m grid, heightmap collision); roads (worn asphalt, road_surface
## shader, concave collision); buildings — designed ones (building_kit MultiMeshes) within KIT_RANGE with plain
## facade blocks standing in for them beyond, and facade blocks for every other footprint (concave collision).
## Game frame: x = east, z = south, y = elevation (metres). Tile format: see tools/citygen/chunk.py.

const DIR := "res://assets/city/"
const Kit := preload("res://scripts/drive/building_kit.gd")
const RANK := {"trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03,
	"residential": 0.025, "living_street": 0.02, "service": 0.015, "track": 0.01, "footway": 0.035}
const FLOOR := 3.2
const KIT_RANGE := 250.0

@export var radius := 3                    # tiles each way to keep loaded (3 → 7 × 7 tiles ≈ 1.8 km square)
@export var per_frame := 1                 # tiles added to the scene per frame at most
var target: Node3D
var index := {}
var tile := 256.0
var classes: Array = []
var loaded := {}                           # Vector2i → Node3D
var pending := {}                          # Vector2i → task id
var ready_q: Array = []                    # [key, resources] made on a worker, waiting for the main thread
var _mutex := Mutex.new()
var road_mat: Material
var ground_mat: Material
var building_mat: Material
var kit
var kit_meshes: Array = []                 # variant index → Mesh (or null)
var body: StaticBody3D
var stats := {"loaded": 0, "built": 0, "unloaded": 0, "buildings": 0, "designed": 0}


func _ready() -> void:
	index = JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json"))
	tile = float(index["tile"])
	classes = index.get("classes", [])
	body = StaticBody3D.new()
	body.name = "CityCollision"
	add_child(body)
	kit = Kit.new()
	if kit.setup():
		for vname in index.get("variants", []):
			kit_meshes.append(kit.mesh(vname))
	else:
		kit = null


func set_materials(road: Material, ground: Material, buildings: Material) -> void:
	road_mat = road
	ground_mat = ground
	building_mat = buildings


func _process(_dt: float) -> void:
	if target == null:
		return
	var c := Vector2i(floori(target.global_position.x / tile), floori(target.global_position.z / tile))
	var want: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not loaded.has(k) and not pending.has(k) and index["tiles"].has("%d,%d" % [k.x, k.y]):
				want.append(k)
	want.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	var busy := pending.size()
	for k in want:
		if busy >= 3:                      # a few at a time: the rest of the frame stays smooth
			break
		pending[k] = WorkerThreadPool.add_task(_build.bind(k))
		busy += 1
	var n := 0
	while n < per_frame:
		_mutex.lock()
		var item = ready_q.pop_front() if not ready_q.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		_instance(item[0], item[1])
		n += 1
	for k in loaded.keys():
		if absi(k.x - c.x) > radius + 1 or absi(k.y - c.y) > radius + 1:
			(loaded[k] as Node3D).queue_free()
			loaded.erase(k)
			stats["unloaded"] += 1
	for k in pending.keys():
		if WorkerThreadPool.is_task_completed(pending[k]):
			WorkerThreadPool.wait_for_task_completion(pending[k])
			pending.erase(k)


# ----------------------------------------------------------------------------- worker side
static func _s32(v: int) -> int:
	return v - 4294967296 if v >= 2147483648 else v


func _build(k: Vector2i) -> void:
	var path := DIR + "chunks/CBE_%d_%d.bin" % [k.x, k.y]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	if f.get_buffer(4).get_string_from_ascii() != "CBE2":
		return
	f.get_32()
	f.get_32()
	var hn := f.get_32()
	var h := f.get_buffer(hn * hn * 4).to_float32_array()
	var roads: Array = []
	for _r in _s32(f.get_32()):
		var cid := f.get_8()
		var fl := f.get_8()
		var np := f.get_16()
		var w := f.get_float()
		roads.append({"c": classes[cid] if cid < classes.size() else "residential", "o": fl & 1, "w": w,
			"p": f.get_buffer(np * 12).to_float32_array()})
	var blds: Array = []
	for _b in _s32(f.get_32()):
		var floors := f.get_8()
		var fl := f.get_8()
		var col := Color(f.get_8() / 255.0, f.get_8() / 255.0, f.get_8() / 255.0)
		var rnd := f.get_8() / 255.0
		var nv := f.get_16()
		var base := f.get_float()
		var variant := _s32(f.get_32())
		var kd := f.get_buffer(28).to_float32_array()
		var xz := f.get_buffer(nv * 8).to_float32_array()
		blds.append([floors, fl, col, rnd, base, variant, kd, xz])
	var out := {}
	_ground(k, hn, h, out)
	_roads(roads, out)
	_buildings(blds, out)
	out["roads_raw"] = roads
	_mutex.lock()
	ready_q.append([k, out])
	_mutex.unlock()


func _ground(k: Vector2i, n: int, h: PackedFloat32Array, out: Dictionary) -> void:
	var step: float = float(index["hstep"])
	var x0 := k.x * tile
	var z0 := k.y * tile
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var idx := PackedInt32Array()
	v.resize(n * n)
	nm.resize(n * n)
	for i in n:
		for j in n:
			v[i * n + j] = Vector3(x0 + j * step, h[i * n + j], z0 + i * step)
	for i in n:
		for j in n:
			var l := v[i * n + maxi(j - 1, 0)]
			var r := v[i * n + mini(j + 1, n - 1)]
			var u := v[maxi(i - 1, 0) * n + j]
			var dn := v[mini(i + 1, n - 1) * n + j]
			nm[i * n + j] = (dn - u).cross(r - l).normalized()
	for i in n - 1:
		for j in n - 1:
			var a := i * n + j
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_INDEX] = idx
	var gm := ArrayMesh.new()
	gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out["ground_mesh"] = gm
	var hs := HeightMapShape3D.new()
	hs.map_width = n
	hs.map_depth = n
	hs.map_data = h
	out["ground_shape"] = hs


func _roads(roads: Array, out: Dictionary) -> void:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for r in roads:
		var p: PackedFloat32Array = r["p"]
		var cnt := p.size() / 3
		if cnt < 2:
			continue
		var half: float = float(r["w"]) * 0.5
		var lift: float = RANK.get(r["c"], 0.02) + 0.06
		var pts := PackedVector3Array()
		for q in cnt:
			pts.append(Vector3(p[q * 3], p[q * 3 + 1] + lift, p[q * 3 + 2]))
		var col := Color(minf(half, 9.0) / 10.0, 1, 1)
		var along := 0.0
		var base := v.size()
		for q in cnt:
			var t := pts[mini(q + 1, cnt - 1)] - pts[maxi(q - 1, 0)]
			var l := Vector3(t.z, 0, -t.x).normalized()
			if q > 0:
				along += pts[q].distance_to(pts[q - 1])
			v.append(pts[q] + l * half)
			v.append(pts[q] - l * half)
			nm.append(Vector3.UP)
			nm.append(Vector3.UP)
			cl.append(col)
			cl.append(col)
			uv.append(Vector2(0.0, along / 6.0))
			uv.append(Vector2(half / 3.0, along / 6.0))
		for q in cnt - 1:
			var a := base + q * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
			faces.append_array([v[a], v[a + 2], v[a + 1], v[a + 1], v[a + 2], v[a + 3]])
	if v.is_empty():
		return
	var ra := []
	ra.resize(Mesh.ARRAY_MAX)
	ra[Mesh.ARRAY_VERTEX] = v
	ra[Mesh.ARRAY_NORMAL] = nm
	ra[Mesh.ARRAY_COLOR] = cl
	ra[Mesh.ARRAY_TEX_UV] = uv
	ra[Mesh.ARRAY_INDEX] = idx
	var rm := ArrayMesh.new()
	rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
	out["road_mesh"] = rm
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	out["road_shape"] = shape


## Facade blocks for every footprint (into "near" or, for designed buildings, "far"), designed buildings as
## MultiMeshes per variant, one concave collision shape for all of them.
func _buildings(blds: Array, out: Dictionary) -> void:
	var near := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var far := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var kits := {}
	for b in blds:
		var floors: int = b[0]
		var shop := 1.0 if (int(b[1]) & 1) else 0.0
		var col: Color = b[2]
		var rnd: float = b[3]
		var base: float = b[4]
		var variant: int = b[5]
		var kd: PackedFloat32Array = b[6]
		var xz: PackedFloat32Array = b[7]
		var n := xz.size() / 2
		var poly := PackedVector2Array()
		var centre := Vector2.ZERO
		for i in n:
			poly.append(Vector2(xz[i * 2], xz[i * 2 + 1]))
			centre += poly[i]
		centre /= n
		var designed := variant >= 0 and variant < kit_meshes.size() and kit_meshes[variant] != null
		var t: Array = far if designed else near
		var roof_y := base + 0.3 + floors * FLOOR
		var top := roof_y + 0.6
		var along := 0.0
		for i in n:
			var p0 := poly[i]
			var p1 := poly[(i + 1) % n]
			var e := p1 - p0
			var el := e.length()
			if el < 0.05:
				continue
			var nrm := Vector3(e.y, 0, -e.x).normalized()
			if Vector2(nrm.x, nrm.z).dot((p0 + p1) * 0.5 - centre) < 0.0:
				nrm = -nrm
			var a := Vector3(p0.x, base - 0.5, p0.y)
			var bb := Vector3(p1.x, base - 0.5, p1.y)
			var cc := Vector3(p1.x, top, p1.y)
			var d := Vector3(p0.x, top, p0.y)
			_quad(t, a, bb, cc, d, nrm, Color(col.r, col.g, col.b, 1.0), Vector2(along, -0.5), Vector2(along + el, -0.5),
				Vector2(along + el, top - base), Vector2(along, top - base), Vector2(rnd, shop))
			faces.append_array([a, bb, cc, a, cc, d])
			along += el
		var tris := Geometry2D.triangulate_polygon(poly)
		for q in range(0, tris.size(), 3):
			_tri(t, Vector3(poly[tris[q]].x, roof_y, poly[tris[q]].y), Vector3(poly[tris[q + 1]].x, roof_y, poly[tris[q + 1]].y),
				Vector3(poly[tris[q + 2]].x, roof_y, poly[tris[q + 2]].y), Color(0.55, 0.54, 0.52, 0.0))
		if designed:
			var nz := Vector3(kd[3], 0, kd[4])
			var nx := Vector3(nz.z, 0, -nz.x)
			var xf := Transform3D(Basis(nx * kd[5], Vector3.UP, nz * kd[6]), Vector3(kd[0], kd[1], kd[2]))
			if not kits.has(variant):
				kits[variant] = []
			kits[variant].append(xf)
	for pair in [["near_mesh", near], ["far_mesh", far]]:
		var t: Array = pair[1]
		if (t[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = t[0]
		arr[Mesh.ARRAY_NORMAL] = t[1]
		arr[Mesh.ARRAY_COLOR] = t[2]
		arr[Mesh.ARRAY_TEX_UV] = t[3]
		arr[Mesh.ARRAY_TEX_UV2] = t[4]
		arr[Mesh.ARRAY_INDEX] = t[5]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out[pair[0]] = m
	var mms: Array = []
	for variant in kits:
		var xs: Array = kits[variant]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kit_meshes[variant]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		mms.append(mm)
	out["kits"] = mms
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		out["building_shape"] = shape
	out["n_blds"] = blds.size()
	out["n_kit"] = kits.values().reduce(func(acc, a): return acc + a.size(), 0)


func _quad(t: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, u2: Vector2) -> void:
	var i: int = t[0].size()
	t[0].append_array([a, b, c, d])
	t[1].append_array([nrm, nrm, nrm, nrm])
	t[2].append_array([col, col, col, col])
	t[3].append_array([ua, ub, uc, ud])
	t[4].append_array([u2, u2, u2, u2])
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		t[5].append_array([i, i + 2, i + 1, i, i + 3, i + 2])
	else:
		t[5].append_array([i, i + 1, i + 2, i, i + 2, i + 3])


func _tri(t: Array, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var i: int = t[0].size()
	t[0].append_array([a, b, c])
	t[1].append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	t[2].append_array([col, col, col])
	t[3].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	t[4].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	if (b - a).cross(c - a).dot(Vector3.UP) > 0.0:
		t[5].append_array([i, i + 2, i + 1])
	else:
		t[5].append_array([i, i + 1, i + 2])


# ----------------------------------------------------------------------------- main thread
func _instance(k: Vector2i, d: Dictionary) -> void:
	if loaded.has(k):
		return
	var node := Node3D.new()
	node.name = "CBE_%d_%d" % [k.x, k.y]
	add_child(node)
	var gmi := MeshInstance3D.new()
	gmi.mesh = d["ground_mesh"]
	gmi.material_override = ground_mat
	node.add_child(gmi)
	var step: float = float(index["hstep"])
	var cs := CollisionShape3D.new()
	cs.shape = d["ground_shape"]
	cs.scale = Vector3(step, 1, step)
	cs.position = Vector3(k.x * tile + tile * 0.5, 0, k.y * tile + tile * 0.5)
	_shape(node, cs)
	if d.has("road_mesh"):
		var rmi := MeshInstance3D.new()
		rmi.mesh = d["road_mesh"]
		rmi.material_override = road_mat
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rmi)
		var rcs := CollisionShape3D.new()
		rcs.shape = d["road_shape"]
		_shape(node, rcs)
	if d.has("near_mesh"):
		var bmi := MeshInstance3D.new()
		bmi.mesh = d["near_mesh"]
		bmi.material_override = building_mat
		node.add_child(bmi)
	if d.has("far_mesh"):
		var fmi := MeshInstance3D.new()
		fmi.mesh = d["far_mesh"]
		fmi.material_override = building_mat
		fmi.visibility_range_begin = KIT_RANGE - 10.0
		node.add_child(fmi)
	for mm in d.get("kits", []):
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = KIT_RANGE + 10.0
		node.add_child(mmi)
	if d.has("building_shape"):
		var bcs := CollisionShape3D.new()
		bcs.shape = d["building_shape"]
		_shape(node, bcs)
	node.set_meta("roads", d["roads_raw"])
	loaded[k] = node
	stats["built"] += 1
	stats["loaded"] = loaded.size()
	stats["buildings"] += int(d.get("n_blds", 0))
	stats["designed"] += int(d.get("n_kit", 0))


## Collision shapes live under one StaticBody3D, and are freed with their tile.
func _shape(node: Node3D, cs: CollisionShape3D) -> void:
	body.add_child(cs)
	node.tree_exiting.connect(func() -> void:
		if is_instance_valid(cs):
			cs.queue_free())


## Ground height under (x, z) from loaded tiles, or NAN.
func height_at(x: float, z: float) -> float:
	var k := Vector2i(floori(x / tile), floori(z / tile))
	if not loaded.has(k):
		return NAN
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 3000, z), Vector3(x, -500, z))
	var hit := space.intersect_ray(q)
	return hit["position"].y if hit else NAN
