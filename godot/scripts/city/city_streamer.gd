extends Node3D
## Streams the real Coimbatore (tools/citygen/chunk.py → assets/city/) in 256 m tiles around a target:
## tiles within `radius` tiles load, tiles beyond `radius + 1` unload. Reading a binary tile, building its
## meshes, MultiMeshes and collision shapes all happens on worker threads; the main thread only adds the
## finished nodes, at most `per_frame` tiles a frame, nearest first. Nothing global is kept except the index
## and the designed-building meshes.
##
## A tile holds: ground (33 × 33 heights, 8 m grid, heightmap collision); roads (worn asphalt with their
## paint, road_surface shader, concave collision); kerbed paver footpaths along every street with streetlights on
## the bigger ones; buildings — designed ones (building_kit MultiMeshes) within KIT_RANGE with plain
## facade blocks standing in for them beyond, and facade blocks for every other footprint (concave collision).
## Game frame: x = east, z = south, y = elevation (metres). Tile format: see tools/citygen/chunk.py.

const DIR := "res://assets/city/"
const Kit := preload("res://scripts/drive/building_kit.gd")
const RANK := {"trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03,
	"residential": 0.025, "living_street": 0.02, "service": 0.015, "track": 0.01, "footway": 0.035}
const FLOOR := 3.2
const KIT_NEAR := 120.0                    # full designs out to here, then their far versions
const KIT_RANGE := 900.0                   # far versions out to here; beyond, plain stand-ins (in the haze)
const KERB := 0.2
const LAMP_STEP := 32.0
const MARK := {"motorway": 3, "trunk": 3, "primary": 2, "secondary": 2, "tertiary": 1, "unclassified": 1, "residential": 1}

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
var walk_mat: Material
var kerb_mat: Material
var yard_mat: Material
var wall_mat: Material
var lamp_mesh: ArrayMesh
var prop_meshes := {}                      # prop type → Mesh (1 traffic signal, 2 bus shelter, 3 speed breaker)
var kit
var kit_meshes: Array = []                 # variant index → Mesh (or null)
var kit_far_meshes: Array = []             # variant index → its far version (tools/kit_far.py) or null
var kit_boxes: Array = []                  # variant index → AABB of the design (far stand-in and collision)
var tree_meshes: Array = []                # [near Mesh, far LOD Mesh] per tree kind
var bike_meshes: Array = []                # parked scooters and motorcycles
var shrub_mesh: Mesh                       # planting on the medians
var breaker_faces := PackedVector3Array()
var signal_shader: Shader
var body: StaticBody3D
var stats := {"loaded": 0, "built": 0, "unloaded": 0, "buildings": 0, "designed": 0}


func _ready() -> void:
	index = JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json"))
	tile = float(index["tile"])
	classes = index.get("classes", [])
	body = StaticBody3D.new()
	body.name = "CityCollision"
	add_child(body)
	lamp_mesh = _lamp()
	signal_shader = _signal_shader()
	# Coimbatore street trees (tools/trees_tn.py): coconut palms and neem, near and far versions
	for tn in ["palm_1", "palm_2", "palm_4", "neem_3", "neem_5"]:
		var near_m := _gltf_mesh("res://assets/models/city_%s.glb" % tn)
		var far_m := _gltf_mesh("res://assets/models/city_%s_far.glb" % tn)
		if near_m:
			tree_meshes.append([near_m, far_m if far_m else near_m])
	shrub_mesh = _gltf_mesh("res://assets/models/veg_hedgerow_bush_0_lod.gltf")
	# parked two-wheelers (tools/twowheeler.py), four paints each
	for kind in ["scooter", "motorcycle"]:
		for ci in 4:
			var bm := _gltf_mesh("res://assets/vehicles/bike_%s_%d.glb" % [kind, ci])
			if bm:
				bike_meshes.append(bm)
	prop_meshes = {1: _signal(), 2: _shelter(), 3: _breaker()}
	breaker_faces = (prop_meshes[3] as Mesh).get_faces()        # read here: workers must not touch the mesh
	kit = Kit.new()
	if kit.setup():
		for vname in index.get("variants", []):
			kit_meshes.append(kit.mesh(vname))
			kit_boxes.append(kit_meshes[-1].get_aabb() if kit_meshes[-1] else AABB())
			kit_far_meshes.append(kit.mesh_far(vname))
	else:
		kit = null


func set_materials(road: Material, ground: Material, buildings: Material, walk: Material = null, kerb: Material = null) -> void:
	road_mat = road
	ground_mat = ground
	building_mat = buildings
	walk_mat = walk
	kerb_mat = kerb


func set_yard_materials(yard: Material, wall: Material) -> void:
	yard_mat = yard
	wall_mat = wall


## A streetlight: an 8 m galvanised pole with an arm reaching over the road (+z) and a lamp head.
func _lamp() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 8.0
	pole.radial_segments = 8
	st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, 4.0, 0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 1.8)
	st.append_from(arm, 0, Transform3D(Basis(), Vector3(0, 7.9, 0.9)))
	var foot := BoxMesh.new()
	foot.size = Vector3(0.35, 0.5, 0.35)
	st.append_from(foot, 0, Transform3D(Basis(), Vector3(0, 0.25, 0)))
	st.commit(am)
	var head := BoxMesh.new()
	head.size = Vector3(0.32, 0.12, 0.65)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.append_from(head, 0, Transform3D(Basis(), Vector3(0, 7.82, 1.75)))
	st2.commit(am)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.42, 0.43, 0.44)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.9, 0.9, 0.85)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.92, 0.78)
	glow.emission_energy_multiplier = 0.4
	am.surface_set_material(0, metal)
	am.surface_set_material(1, glow)
	return am


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
	if f.get_buffer(4).get_string_from_ascii() != "CBE5":
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
		var a0 := f.get_float()
		var ln := f.get_float()
		var c0 := f.get_float()
		var c1 := f.get_float()
		roads.append({"c": classes[cid] if cid < classes.size() else "residential", "o": fl & 1, "w": w, "a0": a0, "len": ln, "c0": c0, "c1": c1,
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
	var walks: Array = []
	for _w in _s32(f.get_32()):
		var wf := f.get_8()
		f.get_8()
		var wn := f.get_16()
		var ww := f.get_float()
		walks.append([wf, ww, f.get_buffer(wn * 12).to_float32_array()])
	var juncs: Array = []
	for _j in _s32(f.get_32()):
		var jn := f.get_16()
		juncs.append(f.get_buffer(jn * 12).to_float32_array())
	var props: Array = []
	for _p in _s32(f.get_32()):
		var kind := f.get_8()
		var pv := f.get_buffer(20).to_float32_array()
		props.append([kind, pv])
	var yards: Array = []
	if f.get_position() < f.get_length():
		for _y in _s32(f.get_32()):
			var yk := f.get_8()
			var yn := f.get_16()
			yards.append([yk, f.get_buffer(yn * 12).to_float32_array()])
	var out := {}
	_ground(k, hn, h, out)
	_roads(roads, out)
	_buildings(blds, out)
	_walks(walks, out)
	_junctions(juncs, out)
	_props(props, out)
	_yards(yards, out)
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
	var uv2 := PackedVector2Array()
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
		var code: int = MARK.get(r["c"], 0)
		if code > 0 and half >= 6.0:
			code = 3
		var med := _has_median(r)
		var col := Color(minf(half, 9.0) / 10.0, (code + 4 * int(r["o"])) / 8.0, 1.0 if med else 0.0)
		var along: float = r["a0"]
		var wl := Vector2(r["len"], roundf(float(r["c1"]) * 10.0) * 1000.0 + roundf(float(r["c0"]) * 10.0))
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
			uv2.append(wl)
			uv2.append(wl)
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
	ra[Mesh.ARRAY_TEX_UV2] = uv2
	ra[Mesh.ARRAY_INDEX] = idx
	var rm := ArrayMesh.new()
	rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
	out["road_mesh"] = rm
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	out["road_shape"] = shape
	_medians(roads, out)


## Two-way main roads get a raised centre median, as on Indian city roads (trunk / primary, or 11 m and wider).
static func _has_median(r: Dictionary) -> bool:
	return int(r["o"]) == 0 and (r["c"] in ["trunk", "motorway", "primary"] or float(r["w"]) >= 11.0)


## The median: 1.2 m wide, 0.25 m high, kerbs painted black and yellow, a planted top; it stops short of each
## junction (the way's clear zones) so traffic can turn; solid to drive into.
func _medians(roads: Array, out: Dictionary) -> void:
	var t := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var plants: Array = []
	var black := Color(0.06, 0.06, 0.06)
	var yellow := Color(0.85, 0.66, 0.08)
	var soil := Color(0.3, 0.22, 0.15)
	for r in roads:
		if not _has_median(r):
			continue
		var p: PackedFloat32Array = r["p"]
		var cnt := p.size() / 3
		if cnt < 2:
			continue
		var lift: float = RANK.get(r["c"], 0.02) + 0.06
		var hw := 0.6
		var hh := 0.25
		var along: float = r["a0"]
		var L: float = r["len"]
		var c0: float = r["c0"] + 3.0 if r["c0"] > 0.0 else 0.0
		var c1: float = r["c1"] + 3.0 if r["c1"] > 0.0 else 0.0
		for i in cnt - 1:
			var a := Vector3(p[i * 3], p[i * 3 + 1] + lift, p[i * 3 + 2])
			var b := Vector3(p[i * 3 + 3], p[i * 3 + 4] + lift, p[i * 3 + 5])
			var seg := Vector3(b.x - a.x, 0, b.z - a.z)
			var sl := seg.length()
			if sl < 0.05:
				continue
			var a0 := along
			along += Vector3(b - a).length()
			if a0 < c0 or along > L - c1:                    # leave the junction open
				continue
			var sd := Vector3(seg.z, 0, -seg.x) / sl * hw
			var up := Vector3(0, hh, 0)
			var col := black if int(a0 / 1.0) % 2 == 0 else yellow
			_quad(t, a + sd + up, b + sd + up, b - sd + up, a - sd + up, Vector3.UP, soil, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			for side in [sd, -sd]:
				var nrm: Vector3 = side.normalized()
				_quad(t, a + side - Vector3(0, 0.05, 0), b + side - Vector3(0, 0.05, 0), b + side + up, a + side + up, nrm, col,
					Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				faces.append_array([a + side, b + side, b + side + up, a + side, b + side + up, a + side + up])
			faces.append_array([a + sd + up, b + sd + up, b - sd + up, a + sd + up, b - sd + up, a - sd + up])
			if int(a0 / 3.0) != int(along / 3.0):            # a shrub every 3 m
				plants.append(Transform3D(Basis(Vector3.UP, a0).scaled(Vector3.ONE * 0.28), (a + b) * 0.5 + up - Vector3(0, 0.08, 0)))
		# end caps where the median stops
	if (t[0] as PackedVector3Array).is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = t[0]
	arr[Mesh.ARRAY_NORMAL] = t[1]
	arr[Mesh.ARRAY_COLOR] = t[2]
	arr[Mesh.ARRAY_INDEX] = t[5]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out["median_mesh"] = m
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	out["median_shape"] = shape
	if not plants.is_empty() and shrub_mesh:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shrub_mesh
		mm.instance_count = plants.size()
		for i in plants.size():
			mm.set_instance_transform(i, plants[i])
		out["median_plants"] = mm


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
		var xf := Transform3D()
		if designed:
			# the far stand-in and the collision follow the placed design, not the raw OSM outline
			var nz0 := Vector3(kd[3], 0, kd[4])
			var nx0 := Vector3(nz0.z, 0, -nz0.x)
			xf = Transform3D(Basis(nx0 * kd[5], Vector3.UP, nz0 * kd[6]), Vector3(kd[0], kd[1], kd[2]))
			var bx: AABB = kit_boxes[variant]
			poly = PackedVector2Array()
			for c2 in [Vector2(bx.position.x, bx.position.z), Vector2(bx.end.x, bx.position.z), Vector2(bx.end.x, bx.end.z),
					Vector2(bx.position.x, bx.end.z)]:
				var w3 := xf * Vector3(c2.x, 0, c2.y)
				poly.append(Vector2(w3.x, w3.z))
			n = 4
			centre = (poly[0] + poly[2]) * 0.5
			top = kd[1] + bx.end.y * 0.92
			roof_y = top
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
			# grouped per variant and per 64 m cell, so each group gets its own distance LOD and culling
			var gk := Vector3i(variant, floori(kd[0] / 64.0), floori(kd[2] / 64.0))
			if not kits.has(gk):
				kits[gk] = []
			kits[gk].append(xf)
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
	for gk in kits:
		var variant: int = gk.x
		var xs: Array = kits[gk]
		for lod in 2:                              # 0 the full design (near), 1 its far version
			var m: Mesh = kit_meshes[variant] if lod == 0 else kit_far_meshes[variant]
			if m == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = m
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			mms.append([mm, lod])
	out["kits"] = mms
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		out["building_shape"] = shape
	out["n_blds"] = blds.size()
	out["n_kit"] = kits.values().reduce(func(acc, a): return acc + a.size(), 0)


## Footpath strips: paver top, a skirt down the outer edge into the ground, and the kerb on the road side
## (painted black and white on the main roads); streetlights every LAMP_STEP metres on the bigger streets.
func _walks(walks: Array, out: Dictionary) -> void:
	var top := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var kb := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var lamps: Array = []
	var white := Color(0.86, 0.86, 0.82)
	var black := Color(0.08, 0.08, 0.08)
	var grey := Color(0.62, 0.61, 0.58)
	for wk in walks:
		var fl: int = wk[0]
		var hw: float = float(wk[1]) * 0.5
		var p: PackedFloat32Array = wk[2]
		var n := p.size() / 3
		if n < 2:
			continue
		var pts := PackedVector3Array()
		for i in n:
			pts.append(Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
		var road_right := (fl & 4) != 0
		# mitred offsets at each point, so bends join cleanly instead of overlapping blocks
		var rws := PackedVector3Array()
		for i in n:
			var t0 := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
			t0.y = 0.0
			t0 = t0.normalized() if t0.length() > 0.001 else Vector3.RIGHT
			var r0 := Vector3(t0.z, 0, -t0.x) if road_right else Vector3(-t0.z, 0, t0.x)
			if i > 0 and i < n - 1:
				var ta := Vector3(pts[i].x - pts[i - 1].x, 0, pts[i].z - pts[i - 1].z).normalized()
				var ra := Vector3(ta.z, 0, -ta.x) if road_right else Vector3(-ta.z, 0, ta.x)
				r0 = r0 / maxf(r0.dot(ra), 0.5)
			rws.append(r0)
		var along := 0.0
		var next_lamp := LAMP_STEP * 0.5
		for i in n - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b - a
			var L := Vector2(seg.x, seg.z).length()
			if L < 0.05:
				continue
			var t := Vector3(seg.x, 0, seg.z) / L
			var rw := Vector3(t.z, 0, -t.x) if road_right else Vector3(-t.z, 0, t.x)      # towards the road
			var ai := a + rws[i] * hw
			var bi := b + rws[i + 1] * hw
			var ao := a - rws[i] * hw
			var bo := b - rws[i + 1] * hw
			_quad(top, ai, bi, bo, ao, Vector3.UP, Color.WHITE, Vector2(hw, along) / 2.0, Vector2(hw, along + L) / 2.0,
				Vector2(-hw, along + L) / 2.0, Vector2(-hw, along) / 2.0, Vector2.ZERO)
			faces.append_array([ai, bi, bo, ai, bo, ao])
			var dn := Vector3(0, -0.7, 0)
			_quad(kb, ao, bo, bo + dn, ao + dn, -rw, Color(0.5, 0.48, 0.45), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
				Vector2.ZERO, Vector2.ZERO)
			# kerb: 0.2 m wide, a touch above the footpath, its face dropping to the road
			var col := grey
			if fl & 1:
				col = white if int(along / 1.2) % 2 == 0 else black
			var up := Vector3(0, 0.02, 0)
			var ki := ai + rws[i] * KERB + up
			var kj := bi + rws[i + 1] * KERB + up
			_quad(kb, ai + up, bi + up, kj, ki, Vector3.UP, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			var drop := Vector3(0, -0.4, 0)
			_quad(kb, ki, kj, kj + drop, ki + drop, rw, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			faces.append_array([ai + up, bi + up, kj, ai + up, kj, ki])
			if fl & 2:
				while next_lamp <= along + L:
					var q := a + seg * ((next_lamp - along) / L) + rw * (hw - 0.35)
					var xz := Vector3.UP.cross(rw).normalized()
					lamps.append(Transform3D(Basis(xz, Vector3.UP, rw), q))
					next_lamp += LAMP_STEP
			along += L
	for pair in [["walk_mesh", top], ["kerb_mesh", kb]]:
		var t2: Array = pair[1]
		if (t2[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = t2[0]
		arr[Mesh.ARRAY_NORMAL] = t2[1]
		arr[Mesh.ARRAY_COLOR] = t2[2]
		arr[Mesh.ARRAY_TEX_UV] = t2[3]
		arr[Mesh.ARRAY_INDEX] = t2[5]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out[pair[0]] = m
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		out["walk_shape"] = shape
	if not lamps.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = lamp_mesh
		mm.instance_count = lamps.size()
		for i in lamps.size():
			mm.set_instance_transform(i, lamps[i])
		out["lamps"] = mm


## Junction surfaces: flat-shaded asphalt triangles over the road ends (road shader, junction mode: no lanes).
func _junctions(juncs: Array, out: Dictionary) -> void:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	var uv := PackedVector2Array()
	for j in juncs:
		var p: PackedFloat32Array = j
		for i in range(0, p.size() / 3 - 2, 3):
			var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
			var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
			var c := Vector3(p[i * 3 + 6], p[i * 3 + 7], p[i * 3 + 8])
			if (b - a).cross(c - a).y < 0.0:
				var tmp := b
				b = c
				c = tmp
			for q in [a, c, b]:
				v.append(q)
				nm.append(Vector3.UP)
				cl.append(Color(1, 0, 0))
				uv.append(Vector2(q.x, q.z) / 6.0)
	if v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_COLOR] = cl
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out["junc_mesh"] = m
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(v)
	out["junc_shape"] = shape


func _props(props: Array, out: Dictionary) -> void:
	var by := {}
	for pr in props:
		var kind: int = pr[0]
		var pv: PackedFloat32Array = pr[1]
		var f := Vector3(sin(pv[3]), 0, cos(pv[3]))
		var x := Vector3.UP.cross(f).normalized()
		var xf := Transform3D(Basis(x * (pv[4] if kind == 3 else 1.0), Vector3.UP, f), Vector3(pv[0], pv[1], pv[2]))
		if not by.has(kind):
			by[kind] = []
		by[kind].append([xf, signal_phase(pv[0], pv[2], pv[3])])
	var mms := []
	var hump := PackedVector3Array()
	for kind in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = kind == 1
		mm.mesh = prop_meshes[kind]
		mm.instance_count = by[kind].size()
		for i in by[kind].size():
			mm.set_instance_transform(i, by[kind][i][0])
			if kind == 1:
				mm.set_instance_custom_data(i, Color(by[kind][i][1], 0, 0, 0))
			if kind == 3:                                # the hump is felt: its surface joins the collision
				var hx: Transform3D = by[kind][i][0]
				for q in breaker_faces:
					hump.append(hx * q)
		mms.append(mm)
	out["props"] = mms
	if not hump.is_empty():
		var hs := ConcavePolygonShape3D.new()
		hs.set_faces(hump)
		out["hump_shape"] = hs


## Where a signal is in its 40 s cycle (0..1): the two approaches along one axis are green together, the crossing
## axis half a cycle later; each junction starts at its own offset. Traffic can use the same rule.
static func signal_phase(x: float, z: float, yaw: float) -> float:
	var axis := 0.0 if absf(cos(yaw)) > absf(sin(yaw)) else 0.5
	var jx := floorf(x / 60.0)
	var jz := floorf(z / 60.0)
	var off := fposmod(sin(jx * 12.9898 + jz * 78.233) * 43758.5453, 1.0)
	return fposmod(axis + off, 1.0)


## Signal lenses: lit by the cycle (green 17 s, amber 3 s, red 20 s), INSTANCE_CUSTOM.r = phase.
func _signal_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec3 col : source_color;
uniform int which = 0;          // 0 red, 1 amber, 2 green
uniform float cycle = 40.0;
varying float ph;
void vertex() { ph = INSTANCE_CUSTOM.r; }
void fragment() {
	float t = mod(TIME + ph * cycle, cycle);
	bool on = which == 2 ? t < 17.0 : (which == 1 ? (t >= 17.0 && t < 20.0) : t >= 20.0);
	ALBEDO = col * (on ? 0.9 : 0.12);
	ROUGHNESS = 0.3;
	EMISSION = on ? col * 3.5 : vec3(0.0);
}
"""
	return sh


func _lens(c: Color, which: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = signal_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("which", which)
	return m


static func _gltf_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var sc := (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	sc.free()
	return found


## Yards: paver forecourts, concrete yards and footpath corners with skirts into the ground, plastered compound
## walls with a coping, and trees (two LODs).
func _yards(yards: Array, out: Dictionary) -> void:
	var pav := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var con := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var skirt := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var wall := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var trees := {}
	var bikes := {}
	var paints := [Color(0.95, 0.9, 0.82), Color(0.93, 0.6, 0.6), Color(0.62, 0.84, 0.68), Color(0.62, 0.76, 0.92),
		Color(0.95, 0.85, 0.55), Color(0.88, 0.88, 0.86), Color(0.8, 0.72, 0.9)]
	for yd in yards:
		var kind: int = yd[0]
		var p: PackedFloat32Array = yd[1]
		var n := p.size() / 3
		if kind == 1 or kind == 2 or kind == 6:
			var t: Array = con if kind == 2 else pav
			for i in range(0, n - 2, 3):
				var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
				var c := Vector3(p[i * 3 + 6], p[i * 3 + 7], p[i * 3 + 8])
				if (b - a).cross(c - a).y < 0.0:
					var tmp := b
					b = c
					c = tmp
				var vi: int = t[0].size()
				t[0].append_array([a, c, b])
				t[1].append_array([Vector3.UP, Vector3.UP, Vector3.UP])
				t[2].append_array([Color.WHITE, Color.WHITE, Color.WHITE])
				t[3].append_array([Vector2(a.x, a.z) / 2.0, Vector2(c.x, c.z) / 2.0, Vector2(b.x, b.z) / 2.0])
				t[4].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
				t[5].append_array([vi, vi + 1, vi + 2])
				faces.append_array([a, c, b])
		elif kind > 100:
			if (kind == 101 or kind == 102) and not bike_meshes.is_empty():
				_park_bikes(p, kind == 101, bikes)
			for i in n - 1:
				var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
				var e := b - a
				var nrm := Vector3(e.z, 0, -e.x).normalized()
				var dn := Vector3(0, -0.6, 0)
				_quad(skirt, a, b, b + dn, a + dn, nrm, Color(0.5, 0.48, 0.45), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				_quad(skirt, b, a, a + dn, b + dn, -nrm, Color(0.5, 0.48, 0.45), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		elif kind == 3 or kind == 5:
			var h := 1.5 if kind == 3 else 2.4
			var th := 0.12
			var col: Color = paints[int(absf(p[0] * 0.37 + p[2] * 0.91)) % paints.size()] if kind == 3 else Color(0.88, 0.87, 0.83)
			var along := 0.0
			for i in n - 1:
				var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
				var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
				var e := Vector3(b.x - a.x, 0, b.z - a.z)
				var L := e.length()
				if L < 0.05:
					continue
				var s := Vector3(e.z, 0, -e.x) / L * th
				var lo := Vector3(0, -0.5, 0)
				var hi := Vector3(0, h, 0)
				for side in [s, -s]:
					var nrm: Vector3 = side.normalized()
					_quad(wall, a + side + lo, b + side + lo, b + side + hi, a + side + hi, nrm, col,
						Vector2(along, -0.5), Vector2(along + L, -0.5), Vector2(along + L, h), Vector2(along, h), Vector2.ZERO)
				# coping: a slightly wider cap in grey
				var cs := s * 1.6
				var ch := Vector3(0, h + 0.07, 0)
				_quad(wall, a + cs + ch, b + cs + ch, b - cs + ch, a - cs + ch, Vector3.UP, Color(0.6, 0.59, 0.56),
					Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				for side in [cs, -cs]:
					_quad(wall, a + side + hi, b + side + hi, b + side + ch, a + side + ch, side.normalized(), Color(0.6, 0.59, 0.56),
						Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				faces.append_array([a + s + lo, b + s + lo, b + s + hi, a + s + lo, b + s + hi, a + s + hi])
				along += L
		elif kind == 4 and not tree_meshes.is_empty():
			if fmod(absf(p[0] * 3.7 + p[2] * 1.3), 1.0) > 0.6:     # thin the planting a little
				continue
			var q := Vector3(p[0], p[1] - 0.1, p[2])
			var hsh := absf(sin(q.x * 12.9898 + q.z * 78.233) * 43758.5453)
			var ti := int(hsh) % tree_meshes.size()
			var sc := 0.75 + fmod(hsh, 1.0) * 0.6
			if not trees.has(ti):
				trees[ti] = []
			trees[ti].append(Transform3D(Basis(Vector3.UP, fmod(hsh * 7.0, TAU)).scaled(Vector3(sc, sc, sc)), q))
	for pair in [["pave_mesh", pav], ["yard_mesh", con], ["skirt_mesh", skirt], ["wall_mesh", wall]]:
		var t2: Array = pair[1]
		if (t2[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = t2[0]
		arr[Mesh.ARRAY_NORMAL] = t2[1]
		arr[Mesh.ARRAY_COLOR] = t2[2]
		arr[Mesh.ARRAY_TEX_UV] = t2[3]
		arr[Mesh.ARRAY_INDEX] = t2[5]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out[pair[0]] = m
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		out["yard_shape"] = shape
	var tm := []
	for ti in trees:
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = tree_meshes[ti][lod]
			mm.instance_count = trees[ti].size()
			for i in trees[ti].size():
				mm.set_instance_transform(i, trees[ti][i])
			tm.append([mm, lod])
	out["trees"] = tm
	var bm2 := []
	for bi in bikes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bike_meshes[bi]
		mm.instance_count = bikes[bi].size()
		for i in bikes[bi].size():
			mm.set_instance_transform(i, bikes[bi][i])
		bm2.append(mm)
	out["bikes"] = bm2


## Parked two-wheelers in a forecourt (shops: 2–5) or a house yard (0–2): a row along the yard's long side, nose
## towards the building, each a little askew.
func _park_bikes(p: PackedFloat32Array, shop: bool, bikes: Dictionary) -> void:
	var n := p.size() / 3
	if n < 4:
		return
	var c := Vector3.ZERO
	var best := 0.0
	var dir := Vector3.RIGHT
	for i in n - 1:
		var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
		var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
		c += a
		var e := Vector3(b.x - a.x, 0, b.z - a.z)
		if e.length() > best:
			best = e.length()
			dir = e.normalized()
	c /= n - 1
	var h := absf(sin(c.x * 12.9898 + c.z * 78.233) * 43758.5453)
	var count := (2 + int(h) % 4) if shop else (int(h) % 3)
	count = mini(count, int(best / 0.9) - 1)
	var across := Vector3(dir.z, 0, -dir.x)
	for k in count:
		var q := c + dir * ((k - (count - 1) * 0.5) * 0.9) + Vector3(0, 0.02, 0)
		var jit := fmod(h * (k + 3.1), 1.0)
		var bi := int(h * (k + 1.7)) % bike_meshes.size()
		var basis := Basis.looking_at(across if jit > 0.5 else -across, Vector3.UP).rotated(Vector3.UP, PI * 0.5 + (jit - 0.5) * 0.35)
		if not bikes.has(bi):
			bikes[bi] = []
		bikes[bi].append(Transform3D(basis, q))


static func _mat(c: Color, metal := 0.0, rough := 0.6, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


static func _box(st: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(Basis(), at))


## Traffic signal: black-and-yellow pole at the left kerb, a head on the pole and one on the arm over the road (+x),
## lenses facing the oncoming driver (+z); green lit.
func _signal() -> ArrayMesh:
	var am := ArrayMesh.new()
	var parts := [
		[_mat(Color(0.12, 0.12, 0.12), 0.5, 0.5), func(st):
			var pole := CylinderMesh.new()
			pole.top_radius = 0.08
			pole.bottom_radius = 0.1
			pole.height = 5.6
			pole.radial_segments = 10
			st.append_from(pole, 0, Transform3D(Basis(), Vector3(0, 2.8, 0)))
			_box(st, Vector3(3.6, 0.12, 0.12), Vector3(1.8, 5.5, 0))
			_box(st, Vector3(0.36, 1.05, 0.28), Vector3(0, 3.1, 0.2))
			_box(st, Vector3(0.36, 1.05, 0.28), Vector3(3.3, 4.85, 0.0))],
		[_mat(Color(0.85, 0.7, 0.05), 0.2, 0.5), func(st):
			for k in 4:
				_box(st, Vector3(0.22, 0.3, 0.22), Vector3(0, 0.35 + k * 0.6, 0))],
		[_lens(Color(1.0, 0.08, 0.04), 0), func(st):
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(0, 3.45, 0.35))
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(3.3, 5.2, 0.15))],
		[_lens(Color(1.0, 0.6, 0.05), 1), func(st):
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(0, 3.1, 0.35))
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(3.3, 4.85, 0.15))],
		[_lens(Color(0.1, 1.0, 0.45), 2), func(st):
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(0, 2.75, 0.35))
			_box(st, Vector3(0.22, 0.22, 0.04), Vector3(3.3, 4.5, 0.15))],
	]
	return _parts_mesh(am, parts)


## Bus shelter: four posts, a sloping roof, a back panel and a bench; 4 m along the kerb (x), open to the road (+z).
func _shelter() -> ArrayMesh:
	var am := ArrayMesh.new()
	var parts := [
		[_mat(Color(0.55, 0.56, 0.57), 0.7, 0.4), func(st):
			for sx in [-1.9, 1.9]:
				for sz in [-0.65, 0.55]:
					_box(st, Vector3(0.08, 2.6, 0.08), Vector3(sx, 1.3, sz))
			_box(st, Vector3(3.6, 0.06, 0.4), Vector3(0, 0.45, -0.4))
			for sx in [-1.5, 0.0, 1.5]:
				_box(st, Vector3(0.06, 0.45, 0.3), Vector3(sx, 0.22, -0.4))],
		[_mat(Color(0.1, 0.3, 0.55), 0.3, 0.5), func(st):
			_box(st, Vector3(4.3, 0.08, 1.9), Vector3(0, 2.66, -0.05))
			_box(st, Vector3(3.8, 0.4, 0.04), Vector3(0, 2.4, 0.86))],
		[_mat(Color(0.75, 0.82, 0.85, 1.0), 0.0, 0.1), func(st):
			_box(st, Vector3(3.8, 1.6, 0.03), Vector3(0, 1.45, -0.68))],
	]
	return _parts_mesh(am, parts)


## Speed breaker: a 3 m hump, 0.1 m high, 1 m across (scaled to the road width), painted yellow and black.
func _breaker() -> ArrayMesh:
	var am := ArrayMesh.new()
	var prof := [[-1.5, 0.0], [-0.9, 0.06], [-0.3, 0.1], [0.3, 0.1], [0.9, 0.06], [1.5, 0.0]]
	for col_i in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 10
		for k in n:
			if k % 2 != col_i:
				continue
			var x0 := -0.5 + float(k) / n
			var x1 := x0 + 1.0 / n
			for i in prof.size() - 1:
				var z0: float = prof[i][0]
				var y0: float = prof[i][1]
				var z1: float = prof[i + 1][0]
				var y1: float = prof[i + 1][1]
				var a := Vector3(x0, y0, z0)
				var b := Vector3(x1, y0, z0)
				var c := Vector3(x1, y1, z1)
				var d := Vector3(x0, y1, z1)
				var nrm := (c - b).cross(a - b).normalized()
				if nrm.y < 0:
					nrm = -nrm
				st.set_normal(nrm)
				for q in [a, c, b, a, d, c]:
					st.add_vertex(q)
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1,
			_mat(Color(0.9, 0.72, 0.05) if col_i == 0 else Color(0.05, 0.05, 0.05), 0.0, 0.7))
	return am


func _parts_mesh(am: ArrayMesh, parts: Array) -> ArrayMesh:
	for pt in parts:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		(pt[1] as Callable).call(st)
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, pt[0])
	return am


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
	for km in ([] if "--nokits" in OS.get_cmdline_user_args() else d.get("kits", [])):
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = km[0]
		if km[1] == 0:
			mmi.visibility_range_end = KIT_NEAR + 10.0
		else:
			mmi.visibility_range_begin = KIT_NEAR
			mmi.visibility_range_end = KIT_RANGE + 10.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	if d.has("walk_mesh"):
		var wmi := MeshInstance3D.new()
		wmi.mesh = d["walk_mesh"]
		wmi.material_override = walk_mat
		wmi.visibility_range_end = 700.0
		node.add_child(wmi)
	if d.has("kerb_mesh"):
		var kmi := MeshInstance3D.new()
		kmi.mesh = d["kerb_mesh"]
		kmi.material_override = kerb_mat
		kmi.visibility_range_end = 500.0
		kmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(kmi)
	if d.has("walk_shape"):
		var wcs := CollisionShape3D.new()
		wcs.shape = d["walk_shape"]
		_shape(node, wcs)
	if d.has("junc_mesh"):
		var jmi := MeshInstance3D.new()
		jmi.mesh = d["junc_mesh"]
		jmi.material_override = road_mat
		jmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(jmi)
		var jcs := CollisionShape3D.new()
		jcs.shape = d["junc_shape"]
		_shape(node, jcs)
	for pm in d.get("props", []):
		var pmi := MultiMeshInstance3D.new()
		pmi.multimesh = pm
		pmi.visibility_range_end = 350.0
		node.add_child(pmi)
	if d.has("hump_shape"):
		var hcs := CollisionShape3D.new()
		hcs.shape = d["hump_shape"]
		_shape(node, hcs)
	for pair in [["pave_mesh", walk_mat, 400.0], ["yard_mesh", yard_mat, 400.0], ["skirt_mesh", kerb_mat, 300.0], ["wall_mesh", wall_mat, 450.0]]:
		if d.has(pair[0]) and not "--noyards" in OS.get_cmdline_user_args():
			var ymi := MeshInstance3D.new()
			ymi.mesh = d[pair[0]]
			ymi.material_override = pair[1]
			ymi.visibility_range_end = pair[2]
			node.add_child(ymi)
	if d.has("yard_shape"):
		var ycs := CollisionShape3D.new()
		ycs.shape = d["yard_shape"]
		_shape(node, ycs)
	var skip := OS.get_cmdline_user_args()
	for tr in ([] if "--notrees" in skip else d.get("trees", [])):
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tr[0]
		if tr[1] == 0:
			tmi.visibility_range_end = 220.0
		else:
			tmi.visibility_range_begin = 210.0
			tmi.visibility_range_end = 500.0
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(tmi)
	if d.has("median_mesh"):
		var mdi := MeshInstance3D.new()
		mdi.mesh = d["median_mesh"]
		mdi.material_override = kerb_mat
		mdi.visibility_range_end = 600.0
		node.add_child(mdi)
		var mcs := CollisionShape3D.new()
		mcs.shape = d["median_shape"]
		_shape(node, mcs)
	if d.has("median_plants"):
		var mpi := MultiMeshInstance3D.new()
		mpi.multimesh = d["median_plants"]
		mpi.visibility_range_end = 250.0
		node.add_child(mpi)
	for bm3 in d.get("bikes", []):
		var bmi := MultiMeshInstance3D.new()
		bmi.multimesh = bm3
		bmi.visibility_range_end = 80.0
		node.add_child(bmi)
	if d.has("lamps"):
		var lmi := MultiMeshInstance3D.new()
		lmi.multimesh = d["lamps"]
		lmi.visibility_range_end = 450.0
		node.add_child(lmi)
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
