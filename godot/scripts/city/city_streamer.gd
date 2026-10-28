extends Node3D
const Prof := preload("res://scripts/drive/prof.gd")
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
const RANK := {"trunk": 0.03, "primary": 0.03, "secondary": 0.03, "tertiary": 0.03, "unclassified": 0.03,
	"residential": 0.03, "living_street": 0.03, "service": 0.03, "track": 0.03, "footway": 0.03}   # = chunk.py LIFT: one height, no steps
const FLOOR := 3.2
const KIT_NEAR := 120.0                    # full designs out to here, then their far versions
const KIT_RANGE := 900.0                   # far versions out to here; beyond, plain stand-ins (in the haze)
const KERB := 0.2
const EDGE_W := {4: 1.25, 5: 1.05, 6: 1.6, 7: 1.2}     # street-edge strips' widths by street type (_street_edge)
const LAMP_STEP := 32.0
const LANDMARKS := "res://assets/landmarks/landmarks.json"   # designed buildings of their own (tools/hotel_grand.py...)
const MARK := {"motorway": 3, "trunk": 3, "primary": 2, "secondary": 2, "tertiary": 1, "unclassified": 1, "residential": 1}

@export var radius := 3                    # tiles each way to keep loaded (3 → 7 × 7 tiles ≈ 1.8 km square)
@export var per_frame := 1                 # tiles added to the scene per frame at most
var target: Node3D
var index := {}
var tile := 256.0
var classes: Array = []
var loaded := {}                           # Vector2i → Node3D
var pending := {}                          # Vector2i → task id
var queued := {}                           # Vector2i → requested and not yet added (pending or waiting in ready_q)
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
var landmarks: Array = []                  # {glb, x, y, z, yaw, lots: [[x, z]...], labels}: each in place of the blocks
										   # on its lots, its Tamil / Hindi lettering drawn here (labels)
var kit_meshes: Array = []                 # variant index → Mesh (or null)
var kit_near := KIT_NEAR                   # (--kitnear=N overrides, for comparing near and far versions)
var kit_far_meshes: Array = []             # variant index → its far version (tools/kit_far.py) or null
var kit_boxes: Array = []                  # variant index → AABB of the design (far stand-in and collision)
var tree_meshes: Array = []                # [near Mesh, far LOD Mesh] per tree kind
var bike_meshes: Array = []                # parked scooters and motorcycles
const LIFE_CELL := 64.0
const TREE_NEAR := 70.0                     # full trees this near (from their 64 m cell's centre), the far version beyond
var life_far: Array = []                    # life kind → far Mesh or null (trees and bushes: veg_*_far)
var life_meshes: Array = []                # life kind → Mesh (index.json life_kinds)
var life_names: Array = []                 # life kind → name (index.json life_kinds, then our own extra kinds)
var bhel_kind := -1                        # the snack cart (life_bhel.glb): it stands in for every third push cart
## The Sketchfab street crowd (tools/sketchfab_people.py): each stands in for every third standing man / woman of the
## city's own (always the same person at the same spot); walkers keep their own figures.
const SF_PEOPLE := {"men": ["sf_man_kurta_blue", "sf_man_kurta_red", "sf_man_suit", "sf_man_office", "sf_man_old_coat",
		"sf_man_veshti", "sf_man_dhoti"],
	"women": ["sf_woman_saree_green", "sf_woman_office", "sf_woman_office2"]}
const SF_STANDS_FOR := {"street_man_shirt_stand": "men", "street_man_veshti": "men", "street_man_lungi": "men",
	"street_woman_saree_red": "women", "street_woman_saree_green": "women", "street_woman_saree_blue": "women"}
var sf_kinds := {}                         # "men" / "women" → their life kind indices
var wire_mat: StandardMaterial3D
var shrub_mesh: Mesh                       # planting on the medians
var pier_mesh: Mesh                        # flyover pier and lamp (tools/flyover.py)
var fly_lamp_mesh: Mesh
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kitnear="):
			kit_near = float(a.get_slice("=", 1))
	if FileAccess.file_exists(LANDMARKS):
		landmarks = JSON.parse_string(FileAccess.get_file_as_string(LANDMARKS))
	lamp_mesh = _lamp()
	signal_shader = _signal_shader()
	# Coimbatore street trees: natural neem, rain tree and gulmohar (tools/vegetation.py) and coconut palms
	# (tools/trees_tn.py); far versions from the lighter palm / neem models
	for pair in [["city_props/veg_neem1", "city_props/veg_neem1_far"], ["city_props/veg_neem2", "city_props/veg_neem2_far"],
			["city_props/veg_rain1", "city_props/veg_rain1_far"], ["city_props/veg_gul1", "city_props/veg_gul1_far"],
			["models/city_palm_1", "models/city_palm_1_far"], ["models/city_palm_2", "models/city_palm_2_far"]]:
		var near_m := _scene_mesh("res://assets/%s.glb" % pair[0])
		var far_m: Mesh = _scene_mesh("res://assets/%s.glb" % pair[1]) if pair[1].begins_with("city_props") else _gltf_mesh("res://assets/%s.glb" % pair[1])
		if near_m:
			tree_meshes.append([near_m, far_m if far_m else near_m])
	# street life (tools/citygen/life.py): one mesh per kind
	for kname in index.get("life_kinds", []):
		var path := ""
		for cand in ["res://assets/city_props/life_%s.glb", "res://assets/city_props/%s.glb", "res://assets/vehicles/%s.glb",
				"res://assets/people/%s.glb", "res://assets/models/%s.glb"]:
			if ResourceLoader.exists(cand % kname):
				path = cand % kname
				break
		var lm: Mesh = _scene_mesh(path) if path != "" else null
		if lm and not (kname.begins_with("veg_") or kname.begins_with("city_palm")):
			lm = _with_lods(lm)
		life_meshes.append(lm)
		var far_path := "res://assets/city_props/%s_far.glb" % kname
		life_far.append(_scene_mesh(far_path) if ResourceLoader.exists(far_path) else null)
	life_names = index.get("life_kinds", []).duplicate()
	if "cart" in life_names and ResourceLoader.exists("res://assets/city_props/life_bhel.glb"):
		bhel_kind = life_meshes.size()
		life_meshes.append(_with_lods(_scene_mesh("res://assets/city_props/life_bhel.glb")))
		life_far.append(null)
		life_names.append("bhel")
	for group in SF_PEOPLE:
		sf_kinds[group] = []
		for nm in SF_PEOPLE[group]:
			var pp := "res://assets/people/%s.glb" % nm
			if ResourceLoader.exists(pp):
				sf_kinds[group].append(life_meshes.size())
				life_meshes.append(_with_lods(_scene_mesh(pp)))
				life_far.append(null)
				life_names.append(nm)
	shrub_mesh = _gltf_mesh("res://assets/models/veg_hedgerow_bush_0_lod.gltf")
	pier_mesh = _gltf_mesh("res://assets/city_props/flyover_pier.glb")
	fly_lamp_mesh = _gltf_mesh("res://assets/city_props/flyover_lamp.glb")
	# parked two-wheelers (tools/twowheeler.py), four paints each
	for kind in ["scooter", "motorcycle"]:
		for ci in 4:
			var bm := _with_lods(_gltf_mesh("res://assets/vehicles/bike_%s_%d.glb" % [kind, ci]))
			if bm:
				bike_meshes.append(bm)
	var sig: Mesh = _designed_signal()
	prop_meshes = {1: sig if sig else _signal(), 2: _shelter(), 3: _breaker()}
	var booth: Mesh = _scene_mesh("res://assets/city_props/police_booth.glb")      # 4: traffic police umbrella booth
	if booth:
		prop_meshes[4] = booth
	breaker_faces = (prop_meshes[3] as Mesh).get_faces()        # read here: workers must not touch the mesh
	kit = Kit.new()
	if kit.setup():
		for vname in index.get("variants", []):
			kit_meshes.append(_with_lods(kit.mesh(vname)))
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
	var _p0 := Time.get_ticks_usec()
	_process_timed(_dt)
	Prof.add("streamer", _p0)


func _process_timed(_dt: float) -> void:
	if target == null:
		return
	var c := Vector2i(floori(target.global_position.x / tile), floori(target.global_position.z / tile))
	var want: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not loaded.has(k) and not queued.has(k) and index["tiles"].has("%d,%d" % [k.x, k.y]):
				want.append(k)
	want.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	var busy := pending.size()
	for k in want:
		if busy >= 3:                      # a few at a time: the rest of the frame stays smooth
			break
		pending[k] = WorkerThreadPool.add_task(_build.bind(k))
		queued[k] = true                   # requested: not again until it has been added or dropped
		busy += 1
	var n := 0
	_mutex.lock()
	var backlog := ready_q.size()
	_mutex.unlock()
	var limit := per_frame + (2 if backlog > 4 else 0)
	while n < limit:
		_mutex.lock()
		var item = ready_q.pop_front() if not ready_q.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		var ik: Vector2i = item[0]
		queued.erase(ik)
		if absi(ik.x - c.x) > radius + 1 or absi(ik.y - c.y) > radius + 1:
			continue                       # built for a place we have already left: drop it
		_instance(ik, item[1])
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
		_mutex.lock()
		ready_q.append([k, {}])
		_mutex.unlock()
		return
	if f.get_buffer(4).get_string_from_ascii() != "CBE6":
		_mutex.lock()
		ready_q.append([k, {}])
		_mutex.unlock()
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
		roads.append({"c": classes[cid] if cid < classes.size() else "residential", "o": fl & 1, "b": fl & 2, "w": w, "a0": a0, "len": ln, "c0": c0, "c1": c1,
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
	var life: Array = []
	var wires: Array = []
	if f.get_position() < f.get_length():
		for _l in _s32(f.get_32()):
			var lk := f.get_8()
			life.append([lk, f.get_buffer(20).to_float32_array()])
		for _w in _s32(f.get_32()):
			var wk2 := f.get_8()
			var wn2 := f.get_16()
			wires.append([wk2, f.get_buffer(wn2 * 12).to_float32_array()])
	_raise_flyovers(roads)
	var out := {}
	_ground(k, hn, h, out)
	_roads(roads, out)
	_buildings(blds, out)
	_walks(walks, out, [k, hn, h, float(index["hstep"]), tile])
	_junctions(juncs, out)
	_props(props, out)
	_yards(yards, out)
	_life(life, out, roads)
	_wires(wires, out)
	out["roads_raw"] = roads
	_mutex.lock()
	ready_q.append([k, out])
	_mutex.unlock()


func _ground(k: Vector2i, n: int, h: PackedFloat32Array, out: Dictionary) -> void:
	var step: float = float(index["hstep"])
	var x0 := k.x * tile
	var z0 := k.y * tile
	h = _level(x0, z0, n, step, h)
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
	_mark_overlaps(roads)
	_flyovers(roads, out)
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
		if r.get("under", false):
			code = 0                                # runs inside a wider road: that road's paint is the one you see
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


## Where the map has several roads on top of each other (each direction, slip lanes, a service lane mapped
## inside the main road), each would paint its own dashes and zebras: dots everywhere. A piece that mostly runs
## inside another, wider carriageway is marked "under" and leaves the painting to that road.
static func _mark_overlaps(roads: Array) -> void:
	for i in roads.size():
		var r: Dictionary = roads[i]
		if r.get("fly", false):
			continue
		var p: PackedFloat32Array = r["p"]
		var n := p.size() / 3
		if n < 2:
			continue
		var inside := 0
		for k in n:
			var q := Vector2(p[k * 3], p[k * 3 + 2])
			for j in roads.size():
				if j == i:
					continue
				var o: Dictionary = roads[j]
				if o.get("fly", false):
					continue                         # a flyover passes over, it does not cover
				var ow: float = o["w"]
				if ow < float(r["w"]) or (ow == float(r["w"]) and j > i):
					continue
				var op: PackedFloat32Array = o["p"]
				var hit := false
				for m in op.size() / 3 - 1:
					var a := Vector2(op[m * 3], op[m * 3 + 2])
					var b := Vector2(op[m * 3 + 3], op[m * 3 + 5])
					if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < ow * 0.5 - 0.3:
						hit = true
						break
				if hit:
					inside += 1
					break
		r["under"] = inside >= int(ceil(n * 0.4))


const FLY_H := 8.6                         # flyover deck height above the road it crosses (~7 m clear)
const FLY_RAMP := 140.0                    # ramp length at each end


static func _fly_elev(along: float, len: float) -> float:
	return FLY_H * smoothstep(0.0, FLY_RAMP, along) * smoothstep(0.0, FLY_RAMP, len - along)


## Long bridge ways in the city are flyovers (the map draws them over the road below): lift them up on
## ramps at each end, so the road and its paint are not drawn on top of the road beneath.
static func _raise_flyovers(roads: Array) -> void:
	for r in roads:
		if not r.get("b", 0) or float(r["len"]) < 250.0:
			continue
		var p: PackedFloat32Array = (r["p"] as PackedFloat32Array).duplicate()
		var along: float = r["a0"]
		var n := p.size() / 3
		var ground := PackedFloat32Array()
		for i in n:
			if i > 0:
				along += Vector2(p[i * 3] - p[i * 3 - 3], p[i * 3 + 2] - p[i * 3 - 1]).length()
			ground.append(p[i * 3 + 1])
			p[i * 3 + 1] += _fly_elev(along, float(r["len"]))
		r["p"] = p
		r["ground"] = ground
		r["fly"] = true


## The flyover (tools/flyover.py design): New-Jersey crash barriers along both edges, the girder deck with its
## sloped underside, reinforced-earth panel walls on the ramps, hammerhead piers every 30 m and double-arm
## lamps along the right-hand edge; barriers and piers are solid.
const NJ := [Vector2(0.0, 0.0), Vector2(0.0, 0.075), Vector2(0.05, 0.33), Vector2(0.18, 0.81), Vector2(0.2, 0.9),
	Vector2(0.38, 0.9), Vector2(0.38, 0.0)]
const PIER_CAP_TOP := 7.0                  # in flyover_pier.glb: ground 0, cap top 7 m, cap across 0.84 × 19.7 m
const PIER_DECK_W := 19.7


func _flyovers(roads: Array, out: Dictionary) -> void:
	var t := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var barrier := Color(0.74, 0.74, 0.71)
	var girder := Color(0.55, 0.54, 0.51)
	var panel_a := Color(0.6, 0.58, 0.54)
	var panel_b := Color(0.42, 0.41, 0.39)
	var piers: Array = []
	var lamps2: Array = []
	for r in roads:
		if not r.get("fly", false):
			continue
		var p: PackedFloat32Array = r["p"]
		var g: PackedFloat32Array = r["ground"]
		var n := p.size() / 3
		var half: float = float(r["w"]) * 0.5
		var lift: float = RANK.get(r["c"], 0.02) + 0.06
		var hw := half + 0.38
		var along: float = r["a0"]
		var next_pier := ceilf(along / 30.0) * 30.0
		var next_lamp := ceilf((along - 15.0) / 30.0) * 30.0 + 15.0
		for i in n - 1:
			var a := Vector3(p[i * 3], p[i * 3 + 1] + lift, p[i * 3 + 2])
			var b := Vector3(p[i * 3 + 3], p[i * 3 + 4] + lift, p[i * 3 + 5])
			var seg := Vector3(b.x - a.x, 0, b.z - a.z)
			var L := seg.length()
			if L < 0.05:
				continue
			var dir := seg / L
			var sd := Vector3(dir.z, 0, -dir.x)            # one side; the other is -sd
			var ea := a.y - lift - g[i]
			var eb := b.y - lift - g[i + 1]
			for s in [1.0, -1.0]:
				var side: Vector3 = sd * s
				# barrier: the profile swept from the carriageway edge outwards
				for k in NJ.size() - 1:
					var p0: Vector2 = NJ[k]
					var p1: Vector2 = NJ[k + 1]
					var a0 := a + side * (half + p0.x) + Vector3(0, p0.y, 0)
					var a1 := a + side * (half + p1.x) + Vector3(0, p1.y, 0)
					var b0 := b + side * (half + p0.x) + Vector3(0, p0.y, 0)
					var b1 := b + side * (half + p1.x) + Vector3(0, p1.y, 0)
					var nrm := (b0 - a0).cross(a1 - a0).normalized()
					if nrm.dot(-side + Vector3.UP * 0.01) < 0.0 and k < 3:
						nrm = -nrm
					_quad(t, a0, b0, b1, a1, nrm, barrier, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				var ia := a + side * half
				var ib := b + side * half
				faces.append_array([ia, ib, ib + Vector3(0, 0.9, 0), ia, ib + Vector3(0, 0.9, 0), ia + Vector3(0, 0.9, 0)])
				# outer face: girder edge in the air, a panel wall on the ramps
				var oa := a + side * hw
				var ob := b + side * hw
				if ea > 2.5 and eb > 2.5:
					_quad(t, oa, ob, ob + Vector3(0, -0.56, 0), oa + Vector3(0, -0.56, 0), side, girder,
						Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					var ua := a + side * (hw - 1.2) + Vector3(0, -1.6, 0)
					var ub := b + side * (hw - 1.2) + Vector3(0, -1.6, 0)
					_quad(t, oa + Vector3(0, -0.56, 0), ob + Vector3(0, -0.56, 0), ub, ua, (side + Vector3.DOWN).normalized(), girder,
						Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				else:
					var steps := maxi(1, int(L / 1.5))
					for q in steps:
						var f0 := float(q) / steps
						var f1 := float(q + 1) / steps
						var pa := oa.lerp(ob, f0)
						var pb := oa.lerp(ob, f1)
						var ga := lerpf(g[i], g[i + 1], f0) - 0.4
						var gb := lerpf(g[i], g[i + 1], f1) - 0.4
						var col := panel_a if int((along + L * f0) / 1.5) % 3 != 0 else panel_b
						_quad(t, pa, pb, Vector3(pb.x, gb, pb.z), Vector3(pa.x, ga, pa.z), side, col,
							Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			if ea > 2.5 and eb > 2.5:                     # the flat soffit between the girder edges
				var ua := a + sd * (hw - 1.2) + Vector3(0, -1.6, 0)
				var ub := b + sd * (hw - 1.2) + Vector3(0, -1.6, 0)
				var va := a - sd * (hw - 1.2) + Vector3(0, -1.6, 0)
				var vb := b - sd * (hw - 1.2) + Vector3(0, -1.6, 0)
				_quad(t, ua, ub, vb, va, Vector3.DOWN, girder, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			# hammerhead piers and lamps
			var basis_x := dir
			var basis_z := dir.cross(Vector3.UP)
			while next_pier <= along + L:
				var f := (next_pier - along) / L
				var c := a.lerp(b, f)
				var e := lerpf(ea, eb, f)
				if e > 4.5:
					var gy := c.y - lift - e
					var sy := (e + lift - 1.6) / PIER_CAP_TOP
					var sz := (2.0 * hw) / PIER_DECK_W
					piers.append(Transform3D(Basis(basis_x, Vector3.UP * sy, basis_z * sz), Vector3(c.x, gy, c.z)))
					for k in 4:                            # column collision: a 1.9 m square
						var ang := k * PI * 0.5
						var q0 := Vector3(c.x, gy, c.z) + (basis_x * cos(ang) + basis_z * sin(ang)) * 0.95 * 1.41
						var q1 := Vector3(c.x, gy, c.z) + (basis_x * cos(ang + PI * 0.5) + basis_z * sin(ang + PI * 0.5)) * 0.95 * 1.41
						var top := Vector3(0, e - 1.6, 0)
						faces.append_array([q0, q1, q1 + top, q0, q1 + top, q0 + top])
				next_pier += 30.0
			while next_lamp <= along + L:
				var f := (next_lamp - along) / L
				var c := a.lerp(b, f)
				var right := Vector3(-dir.z, 0, dir.x)          # the driver's right: the median side of a divided road
				lamps2.append(Transform3D(Basis(basis_x, Vector3.UP, basis_z), c + right * (half + 0.19) + Vector3(0, 0.9, 0)))
				next_lamp += 30.0
			along += L
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
	out["fly_mesh"] = m
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	out["fly_shape"] = shape
	for pair in [["fly_piers", piers, pier_mesh], ["fly_lamps", lamps2, fly_lamp_mesh]]:
		var xs: Array = pair[1]
		if xs.is_empty() or pair[2] == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[2]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		out[pair[0]] = mm


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
	var info: Array = []                             # [outline, centre, floors, shop, base, variant]: for doors (CityDoors)
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
		if _landmark_lot(centre):
			continue                                     # a landmark of its own stands here (_landmarks)
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
		info.append([poly, centre, floors, shop > 0.5, base, variant])
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
	out["bldinfo"] = info
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


## The tile's ground height at x, z (g = [tile key, n, heights, step, tile size]): the same two triangles per cell as
## _ground (held at the tile's edge for points just over it).
static func _ground_at(g: Array, x: float, z: float) -> float:
	var k: Vector2i = g[0]
	var n: int = g[1]
	var h: PackedFloat32Array = g[2]
	var st: float = g[3]
	var fx := clampf((x - k.x * float(g[4])) / st, 0.0, n - 1.0)
	var fz := clampf((z - k.y * float(g[4])) / st, 0.0, n - 1.0)
	var j := clampi(int(floor(fx)), 0, n - 2)
	var i := clampi(int(floor(fz)), 0, n - 2)
	var u := fx - j
	var v := fz - i
	if u + v <= 1.0:
		return h[i * n + j] + (h[i * n + j + 1] - h[i * n + j]) * u + (h[(i + 1) * n + j] - h[i * n + j]) * v
	var h11 := h[(i + 1) * n + j + 1]
	return h11 + (h[(i + 1) * n + j] - h11) * (1.0 - u) + (h[i * n + j + 1] - h11) * (1.0 - v)


## Where a face hanging from p (a footpath's back, a strip's end) stops: in the ground below it, however far down
## the land lies (roads on banks stand metres over it), and at least 0.3 m down.
static func _down(g: Array, p: Vector3) -> Vector3:
	return Vector3(p.x, minf(p.y - 0.3, _ground_at(g, p.x, p.z) - 0.15), p.z)


## Streets without a footpath (docs/COIMBATORE_STREETS.md): colony — a 0.5 m concrete edge strip flush with the
## road and a slab-covered drain behind it; old town — an open drain channel at the road edge with slab bridges;
## industrial and outskirts — a gravel shoulder. The strip data sits at footpath height, at least 0.15 above the road
## and 0.05 above the ground; the edges sit 0.04 below that: just over the road's surface (lifted 0.09) and never
## under the ground (it covered them: a strip of bare earth between the road and the houses). Where the ground
## stands higher, a face drops from the strip's road edge to the road.
func _street_edge(kb: Array, faces: PackedVector3Array, a: Vector3, b: Vector3, ra: Vector3, rb: Vector3, hw: float,
		styp: int, along: float, L: float, g: Array) -> void:
	var dn := Vector3(0, -0.04, 0)
	var e0 := a + ra * (hw + 0.2) + dn
	var e1 := b + rb * (hw + 0.2) + dn
	var concrete := Color(0.7, 0.69, 0.66)
	var slab := Color(0.56, 0.55, 0.52)
	var dark := Color(0.04, 0.04, 0.035)
	var gravel := Color(0.55, 0.42, 0.32)
	var rd := (ra + rb).normalized()
	_quad(kb, e1, e0, e0 + Vector3(0, -0.6, 0), e1 + Vector3(0, -0.6, 0), rd,
		concrete if styp == 4 else (slab if styp == 5 else gravel), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	if styp == 4:
		var s0 := e0 - ra * 0.5
		var s1 := e1 - rb * 0.5
		_quad(kb, e0, e1, s1, s0, Vector3.UP, concrete, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var d0 := s0 - ra * 0.75 + Vector3(0, 0.02, 0)
		var d1 := s1 - rb * 0.75 + Vector3(0, 0.02, 0)
		_quad(kb, s0 + Vector3(0, 0.02, 0), s1 + Vector3(0, 0.02, 0), d1, d0, Vector3.UP, slab,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, d0, d1, _down(g, d1), _down(g, d0), -ra, slab, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		faces.append_array([e0, e1, d1, e0, d1, d0])
	elif styp == 5:
		var w := 0.45
		var low := Vector3(0, -0.35, 0)
		var o0 := e0 - ra * w
		var o1 := e1 - rb * w
		_quad(kb, e0 + low, e1 + low, o1 + low, o0 + low, Vector3.UP, dark, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, e0, e1, e1 + low, e0 + low, -ra, slab, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, o1, o0, o0 + low, o1 + low, ra, slab, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, o0, o1, o1 - rb * 0.6, o0 - ra * 0.6, Vector3.UP, concrete, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, o0 - ra * 0.6, o1 - rb * 0.6, _down(g, o1 - rb * 0.6), _down(g, o0 - ra * 0.6), -rd, slab,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		if int(along / 5.0) != int((along + L) / 5.0):                     # a slab bridge to the doors
			var mid := e0.lerp(e1, 0.5) + Vector3(0, 0.02, 0)
			var dd := (e1 - e0).normalized()
			_quad(kb, mid - dd * 0.5, mid + dd * 0.5, mid + dd * 0.5 - ra * (w + 0.1), mid - dd * 0.5 - ra * (w + 0.1),
				Vector3.UP, concrete, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		faces.append_array([e0 + low, e1 + low, o1 + low, e0 + low, o1 + low, o0 + low])
	else:
		var w2 := 1.6 if styp == 6 else 1.2
		var g0 := e0 - ra * w2 + Vector3(0, -0.03, 0)
		var g1 := e1 - rb * w2 + Vector3(0, -0.03, 0)
		_quad(kb, e0, e1, g1, g0, Vector3.UP, gravel, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_quad(kb, g0, g1, _down(g, g1), _down(g, g0), -rd, gravel, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		faces.append_array([e0, e1, g1, e0, g1, g0])


## Footpath strips: paver top, a skirt down the outer edge into the ground, and the kerb on the road side
## (painted black and white on the main roads); streetlights every LAMP_STEP metres on the bigger streets.
func _walks(walks: Array, out: Dictionary, g: Array) -> void:
	var top := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var kb := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	var faces := PackedVector3Array()
	var lamps: Array = []
	var seps: Array = []
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
			var styp := (fl >> 4) & 7                   # street type (tools/citygen/life.py TYPES)
			if styp >= 4 and (fl & 8) == 0:
				_street_edge(kb, faces, a, b, rws[i], rws[i + 1], hw, styp, along, L, g)
				along += L
				continue
			var sep := (fl & 8) != 0                     # a separator / median: planted, kerbed both sides
			var col := grey
			if fl & 1:
				col = white if int(along / 1.2) % 2 == 0 else black
			if sep:
				col = black if int(along / 1.0) % 2 == 0 else Color(0.85, 0.66, 0.08)
				_quad(kb, ai, bi, bo, ao, Vector3.UP, Color(0.3, 0.22, 0.15), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
					Vector2.ZERO, Vector2.ZERO)
				if int(along / 3.0) != int((along + L) / 3.0) and shrub_mesh:
					seps.append(Transform3D(Basis(Vector3.UP, along).scaled(Vector3.ONE * 0.28), (a + b) * 0.5 - Vector3(0, 0.08, 0)))
			else:
				_quad(top, ai, bi, bo, ao, Vector3.UP, Color.WHITE, Vector2(hw, along) / 2.0, Vector2(hw, along + L) / 2.0,
					Vector2(-hw, along + L) / 2.0, Vector2(-hw, along) / 2.0, Vector2.ZERO)
			faces.append_array([ai, bi, bo, ai, bo, ao])
			_quad(kb, ao, bo, _down(g, bo), _down(g, ao), -rw, col if sep else Color(0.5, 0.48, 0.45), Vector2.ZERO, Vector2.ZERO,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			# kerb: 0.2 m wide, a touch above the footpath, its face dropping to the road
			var up := Vector3(0, 0.02, 0)
			var ki := ai + rws[i] * KERB + up
			var kj := bi + rws[i + 1] * KERB + up
			_quad(kb, ai + up, bi + up, kj, ki, Vector3.UP, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			var drop := Vector3(0, -1.0, 0)                # (below the road even where the footpath is 0.55 up, or the
			                                               # road beside it lies lower at a junction)
			_quad(kb, ki, kj, kj + drop, ki + drop, rw, col, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			faces.append_array([ai + up, bi + up, kj, ai + up, kj, ki])
			if fl & 2 and not sep:
				while next_lamp <= along + L:
					var q := a + seg * ((next_lamp - along) / L) + rw * (hw - 0.35)
					var xz := Vector3.UP.cross(rw).normalized()
					lamps.append(Transform3D(Basis(xz, Vector3.UP, rw), q))
					next_lamp += LAMP_STEP
			along += L
		# its two ends close down into the ground: where a strip stops (a junction, a gate) it stood open over the land
		if (fl & 8) == 0:
			var st := (fl >> 4) & 7
			for e in [[0, -1.0], [n - 1, 1.0]]:
				var q: int = e[0]
				var tq := pts[mini(q + 1, n - 1)] - pts[maxi(q - 1, 0)]
				tq.y = 0.0
				if tq.length() < 0.001:
					continue
				tq = tq.normalized() * float(e[1])
				var near_e: Vector3
				var far_e: Vector3
				if st >= 4:
					near_e = pts[q] + rws[q] * (hw + 0.2) + Vector3(0, -0.04, 0)
					far_e = near_e - rws[q] * EDGE_W.get(st, 1.2)
				else:
					near_e = pts[q] + rws[q] * (hw + KERB) + Vector3(0, 0.02, 0)
					far_e = pts[q] - rws[q] * hw
				_quad(kb, near_e, far_e, _down(g, far_e), _down(g, near_e), tq, Color(0.5, 0.48, 0.45),
					Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	if not seps.is_empty():
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = shrub_mesh
		smm.instance_count = seps.size()
		for i in seps.size():
			smm.set_instance_transform(i, seps[i])
		out["sep_plants"] = smm
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
		if not prop_meshes.has(kind):
			continue
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
	var sigs: Array = []                          # for traffic: [position, yaw, phase] of every signal head
	for pr in props:
		if pr[0] == 1:
			var pv2: PackedFloat32Array = pr[1]
			sigs.append([Vector3(pv2[0], pv2[1], pv2[2]), pv2[3], signal_phase(pv2[0], pv2[2], pv2[3])])
	out["signals"] = sigs
	if not hump.is_empty():
		var hs := ConcavePolygonShape3D.new()
		hs.set_faces(hump)
		out["hump_shape"] = hs


## Where a signal is in its 40 s cycle (0..1): the two approaches along one axis are green together, the crossing
## axis half a cycle later; each junction starts at its own offset. Traffic can use the same rule.
## Whether a signal with this phase shows green / amber / red right now (same clock as the lenses' shader TIME).
## Indian timing: a 90 s cycle — 40 s green, 4 s amber, 46 s red; the crossing road runs half a cycle later, so
## each side gets one second of all-red between them.
const SIG_CYCLE := 90.0
const SIG_GREEN := 40.0
const SIG_AMBER := 44.0


static func signal_state(phase: float) -> int:
	var t := fposmod(Time.get_ticks_msec() / 1000.0 + phase * SIG_CYCLE, SIG_CYCLE)
	return 0 if t < SIG_GREEN else (1 if t < SIG_AMBER else 2)        # 0 green, 1 amber, 2 red


static func signal_phase(x: float, z: float, yaw: float) -> float:
	var axis := 0.0 if absf(cos(yaw)) > absf(sin(yaw)) else 0.5
	var jx := floorf(x / 60.0)
	var jz := floorf(z / 60.0)
	var off := fposmod(sin(jx * 12.9898 + jz * 78.233) * 43758.5453, 1.0)
	return fposmod(axis + off, 1.0)


## Signal lenses: lit by the cycle (green 17 s, amber 3 s, red 20 s), INSTANCE_CUSTOM.r = phase.
## The designed Coimbatore signal (tools/traffic_signal.py): pole with striped base, mast arm with two overhead
## heads, a near-side head, the countdown timer and a FREE LEFT board. Its lenses and timer face are lit here,
## on the same 40 s cycle the traffic obeys (signal_state); INSTANCE_CUSTOM.r carries each approach's phase.
func _designed_signal() -> Mesh:
	var m: Mesh = _scene_mesh("res://assets/city_props/signal_india.glb")
	if m == null:
		m = _scene_mesh("res://assets/city_props/traffic_signal.glb")
	if m == null:
		return null
	for i in m.get_surface_count():
		var cur := m.surface_get_material(i)
		var nm := cur.resource_name if cur else ""
		if nm.begins_with("SigLens Red"):
			m.surface_set_material(i, _lens(Color(1.0, 0.07, 0.03), 0))
		elif nm.begins_with("SigLens Amber"):
			m.surface_set_material(i, _lens(Color(1.0, 0.55, 0.02), 1))
		elif nm.begins_with("SigLens Green"):
			m.surface_set_material(i, _lens(Color(0.1, 1.0, 0.55), 2))
		elif nm.begins_with("SigArrow"):
			var am := ShaderMaterial.new()
			am.shader = _arrow_shader()
			am.set_shader_parameter("kind", 0 if nm.contains("Left") else (1 if nm.contains("Straight") else 2))
			m.surface_set_material(i, am)
		elif nm.begins_with("SigTimer"):
			var tm := ShaderMaterial.new()
			tm.shader = _timer_shader()
			m.surface_set_material(i, tm)
	return m


## A green-arrow aspect (left, straight, right) drawn on its lens quad. The left arrow is always lit (FREE LEFT);
## straight and right only while the signal is green.
static var _arrow_sh: Shader
static func _arrow_shader() -> Shader:
	if _arrow_sh:
		return _arrow_sh
	_arrow_sh = Shader.new()
	_arrow_sh.code = """shader_type spatial;
uniform int kind = 0;           // 0 left, 1 straight, 2 right
uniform float cycle = 90.0;
varying float ph;
void vertex() { ph = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 p = vec2(UV.x, 1.0 - UV.y) * 2.0 - 1.0;
	if (kind == 0) p = vec2(-p.x, p.y);
	if (kind == 1) p = vec2(p.y, -p.x);
	// an arrow pointing to +x: a shaft and a head
	bool shaft = p.x > -0.62 && p.x < 0.15 && abs(p.y) < 0.13;
	bool headp = p.x >= 0.1 && p.x < 0.62 && abs(p.y) < (0.62 - p.x) * 0.95;
	bool disc = dot(p, p) < 0.95;
	float t = mod(TIME + ph * cycle, cycle);
	bool on = kind == 0 || t < 40.0;
	bool glyph = disc && (shaft || headp);
	ALBEDO = vec3(0.01, 0.02, 0.015);
	ROUGHNESS = 0.1;
	EMISSION = glyph ? (on ? vec3(0.1, 1.0, 0.5) * 6.0 : vec3(0.004, 0.02, 0.01)) : vec3(0.0);
}
"""
	return _arrow_sh


## The countdown: two seven-segment digits on the timer's face, the seconds left of red (red) or green (green),
## dark through amber.
static func _timer_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform float cycle = 90.0;
varying float ph;
void vertex() { ph = INSTANCE_CUSTOM.r; }
bool seg(vec2 p, int bits) {
	bool on = false;
	if ((bits & 1) != 0 && p.y > 0.9 && p.x > 0.15 && p.x < 0.85) on = true;                 // a
	if ((bits & 2) != 0 && p.x > 0.85 && p.y > 0.52 && p.y < 0.93) on = true;                // b
	if ((bits & 4) != 0 && p.x > 0.85 && p.y > 0.07 && p.y < 0.48) on = true;                // c
	if ((bits & 8) != 0 && p.y < 0.1 && p.x > 0.15 && p.x < 0.85) on = true;                 // d
	if ((bits & 16) != 0 && p.x < 0.15 && p.y > 0.07 && p.y < 0.48) on = true;               // e
	if ((bits & 32) != 0 && p.x < 0.15 && p.y > 0.52 && p.y < 0.93) on = true;               // f
	if ((bits & 64) != 0 && p.y > 0.45 && p.y < 0.55 && p.x > 0.15 && p.x < 0.85) on = true; // g
	return on;
}
void fragment() {
	float t = mod(TIME + ph * cycle, cycle);
	int state = t < 40.0 ? 0 : (t < 44.0 ? 1 : 2);
	int v = state == 0 ? int(ceil(40.0 - t)) : (state == 2 ? int(ceil(90.0 - t)) : -1);
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	int which = uv.x < 0.5 ? 0 : 1;
	vec2 p = (vec2(fract(uv.x * 2.0), uv.y) - vec2(0.2, 0.12)) / vec2(0.6, 0.76);
	int masks[10] = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111};
	bool inside = p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0;
	bool lit = false;
	bool ghost = inside && seg(p, 127);
	if (v >= 0 && inside) {
		int d = which == 0 ? v / 10 : v % 10;
		lit = (which == 1 || d > 0) && seg(p, masks[d]);
	}
	vec3 c = state == 0 ? vec3(0.1, 1.0, 0.5) : vec3(1.0, 0.08, 0.03);
	ALBEDO = vec3(0.015);
	ROUGHNESS = 0.3;
	EMISSION = lit ? c * 5.0 : (ghost ? vec3(0.012) : vec3(0.0));
}
"""
	return sh


func _signal_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec3 col : source_color;
uniform int which = 0;          // 0 red, 1 amber, 2 green
uniform float cycle = 90.0;
varying float ph;
void vertex() { ph = INSTANCE_CUSTOM.r; }
void fragment() {
	float t = mod(TIME + ph * cycle, cycle);
	bool on = which == 2 ? t < 40.0 : (which == 1 ? (t >= 40.0 && t < 44.0) : t >= 44.0);
	ALBEDO = col * (on ? 0.9 : 0.06);
	ROUGHNESS = on ? 0.3 : 0.08;
	EMISSION = on ? col * 7.0 : vec3(0.0);
}
"""
	return sh


func _lens(c: Color, which: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = signal_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("which", which)
	return m


## leaf material name → painted atlas (tools/leaf_atlas.py, copied by tools/export_life.py)
const LEAVES := {"Neem Leaf": "neem", "Rain Tree Leaf": "rain", "Gulmohar Leaf": "gulmohar", "Bush Leaf": "bush",
	"Prosopis Leaf": "rain"}
static var _leaf_mats := {}
static var _grass: ShaderMaterial
static var _leaf_shader: Shader
static var _bark: StandardMaterial3D


## Every mesh of a glTF scene merged into one ArrayMesh (one surface per source surface, transforms baked):
## vehicles, people and props come as several parts. Leaf and bark materials get the game's own versions.
static func _scene_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var sc := (load(path) as PackedScene).instantiate() as Node3D
	var am := ArrayMesh.new()
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D()
		var nd: Node = mi
		while nd and nd != sc:
			xf = (nd as Node3D).transform * xf
			nd = nd.get_parent()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in vs.size():
				vs[i] = xf * vs[i]
			arr[Mesh.ARRAY_VERTEX] = vs
			if arr[Mesh.ARRAY_NORMAL] != null:
				var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in ns.size():
					ns[i] = (xf.basis * ns[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = ns
			arr[Mesh.ARRAY_TANGENT] = null
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat := mi.get_active_material(si)
			am.surface_set_material(am.get_surface_count() - 1, _game_material(mat))
	sc.free()
	return am


static func _game_material(mat: Material) -> Material:
	var nm := mat.resource_name if mat else ""
	for key in LEAVES:
		if nm.begins_with(key):
			if not _leaf_mats.has(key):
				if _leaf_shader == null:
					_leaf_shader = Shader.new()
					# the atlas cut out by its alpha; vertex colour r = light (dark deep in the crown), g = a yellow tint
					_leaf_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
	vec4 t = texture(atlas, UV);
	if (t.a < 0.5) discard;
	vec3 c = t.rgb * mix(0.5, 1.35, COLOR.r) * mix(vec3(1.0), vec3(1.2, 1.08, 0.6), COLOR.g * 0.45);
	ALBEDO = c;
	ROUGHNESS = 0.55;
	BACKLIGHT = c * 0.7;
}
"""
				var sm := ShaderMaterial.new()
				sm.shader = _leaf_shader
				sm.set_shader_parameter("atlas", load("res://assets/city_props/leaves/%s.png" % LEAVES[key]))
				_leaf_mats[key] = sm
			return _leaf_mats[key]
	if nm.begins_with("Grass Blade"):
		if _grass == null:
			var sh := Shader.new()
			sh.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec3 c = mix(vec3(0.1, 0.13, 0.04), vec3(0.3, 0.3, 0.1), COLOR.r);
	ALBEDO = c;
	ROUGHNESS = 0.6;
	BACKLIGHT = c * 0.5;
}
"""
			_grass = ShaderMaterial.new()
			_grass.shader = sh
		return _grass
	if nm.begins_with("Bark"):
		if _bark == null:
			_bark = StandardMaterial3D.new()
			_bark.albedo_texture = load("res://assets/city_props/leaves/bark.png")
			_bark.roughness = 0.95
		return _bark
	return mat


## Street life: one MultiMesh per kind; people, kolams and bikes only near, trees and poles further.
func _life(life: Array, out: Dictionary, roads: Array = []) -> void:
	var by := {}
	var names0: Array = life_names
	var segs := _road_segs(roads)
	for rec in life:
		var kind: int = rec[0]
		if kind >= life_meshes.size() or life_meshes[kind] == null:
			continue
		var v: PackedFloat32Array = rec[1]
		var nm0: String = names0[kind] if kind < names0.size() else ""
		if nm0 == "cart" and bhel_kind >= 0 and posmod(floori(v[0] * 7.0 + v[2] * 13.0), 3) == 0:
			kind = bhel_kind                        # a bhel puri cart instead of fruit (the same spot each visit)
			if OS.is_debug_build() and "--where=bhel" in OS.get_cmdline_user_args():
				print("BHEL at %.1f,%.1f,%.1f" % [v[0], v[1], v[2]])
		elif SF_STANDS_FOR.has(nm0):
			var grp: Array = sf_kinds.get(SF_STANDS_FOR[nm0], [])
			var hsh := floori(v[0] * 7.0 + v[2] * 13.0)
			if not grp.is_empty() and posmod(hsh, 3) == 0:
				kind = grp[posmod(hsh / 3, grp.size())]
				if OS.is_debug_build() and "--where=people" in OS.get_cmdline_user_args():
					print("PERSON %s at %.1f,%.1f,%.1f yaw %.2f" % [life_names[kind], v[0], v[1], v[2], v[3]])
		if nm0.begins_with("fleet_") or nm0.begins_with("bike_") or nm0 == "cart":
			v = _park_on_road(v, segs, 1.3 if nm0 == "fleet_lorry" else (0.95 if nm0.begins_with("fleet_") else 0.45))
		var a := v[3]
		var x := Vector3(cos(a), 0, sin(a))
		var bs := Basis(x, Vector3.UP, x.cross(Vector3.UP)).scaled(Vector3.ONE * v[4])
		# visibility ranges are measured from each MultiMesh's centre, so the things are grouped in 64 m cells
		var key := Vector3i(kind, floori(v[0] / LIFE_CELL), floori(v[2] / LIFE_CELL))
		if not by.has(key):
			by[key] = []
		by[key].append(Transform3D(bs, Vector3(v[0], v[1], v[2])))
	var mms := []
	var names: Array = life_names
	for key in by:
		var kind: int = key.x
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = life_meshes[kind]
		mm.instance_count = by[key].size()
		for i in by[key].size():
			mm.set_instance_transform(i, by[key][i])
		var nm: String = names[kind]
		if kind < life_far.size() and life_far[kind] != null:
			var fm := MultiMesh.new()
			fm.transform_format = MultiMesh.TRANSFORM_3D
			fm.mesh = life_far[kind]
			fm.instance_count = by[key].size()
			for i in by[key].size():
				fm.set_instance_transform(i, by[key][i])
			var near := (TREE_NEAR if nm.begins_with("veg_") and not nm.begins_with("veg_bush") else 40.0) + LIFE_CELL * 0.71
			mms.append([mm, near, 0.0, false])
			mms.append([fm, (320.0 if not nm.begins_with("veg_bush") else 150.0) + LIFE_CELL * 0.71, near - 4.0])
			mms.append([fm, near, 0.0, true])               # the near ones' shadow, from the far mesh
			continue
		var far := 60.0
		if nm.begins_with("veg_") or nm.begins_with("city_palm") or nm == "pole" or nm == "transformer":
			far = 320.0
		elif nm.begins_with("fleet") or nm.begins_with("stall") or nm.begins_with("shade") or nm.begins_with("flex") \
				or nm == "shrine" or nm == "thatched" or nm == "bhel":
			far = 140.0
		if nm.begins_with("fleet") or nm.begins_with("bike_") or nm == "cart" or nm == "bhel":
			mm.set_meta("lod_bias", 6.0)            # keep detail: a coarse level drops bodies and leaves floating wheels
		mms.append([mm, far + LIFE_CELL * 0.71, 0.0])
	out["life"] = mms


## The tile's drivable road centrelines as segments [a, b, half width] (flyovers left out: nothing parks up there).
static func _road_segs(roads: Array) -> Array:
	var segs := []
	for r in roads:
		if r.get("fly", false):
			continue
		var p: PackedFloat32Array = r["p"]
		var half: float = float(r["w"]) * 0.5
		for i in p.size() / 3 - 1:
			segs.append([Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]), Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5]), half])
	return segs


## A parked vehicle (from the map pipeline, its height from the terrain model) on the road the game actually built:
## if it stands on a carriageway it's set on that road's surface (it floated above or sank into it), and if it
## stands out in the lanes it's moved to the edge, where people really park (keep: half its width from the edge).
static func _park_on_road(v: PackedFloat32Array, segs: Array, keep: float) -> PackedFloat32Array:
	var q := Vector2(v[0], v[2])
	var best := INF
	var bp := Vector3.ZERO
	var bn := Vector2.ZERO
	var bh := 0.0
	for sg in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((q - Vector2(a.x, a.z)).dot(ab) / l2, 0.0, 1.0)
		var pr := a.lerp(b, t)
		var d := (q - Vector2(pr.x, pr.z)).length()
		if d - float(sg[2]) < best:
			best = d - float(sg[2])
			bp = pr
			bh = sg[2]
			bn = (q - Vector2(pr.x, pr.z)) / d if d > 0.01 else Vector2(-ab.y, ab.x).normalized()
	if best > 0.6:                          # off the carriageway (a yard, a dirt shoulder): the terrain height is right
		return v
	var out := v.duplicate()
	if OS.get_cmdline_user_args().has("--parklog"):
		print("PARK dy=%.2f d_from_edge=%.2f" % [bp.y + 0.09 - v[1], bh + best - bh])
	var d := bh + best
	if d < bh - keep:                       # out in the lanes: to the edge
		var e := Vector2(bp.x, bp.z) + bn * (bh - keep)
		out[0] = e.x
		out[2] = e.y
	out[1] = bp.y + 0.09                    # the road surface (streamer RANK + 0.06 above the centreline points)
	return out


## Overhead wires between the poles of a run: three conductors sagging 0.9 m at 8.55 m, a cable bundle lower down.
func _wires(wires: Array, out: Dictionary) -> void:
	var t := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
	for w in wires:
		var p: PackedFloat32Array = w[1]
		var n := p.size() / 3
		var offs := [[-0.7, 8.55, 0.9], [0.0, 8.55, 0.9], [0.7, 8.55, 0.9]]
		if w[0] == 2:
			offs.append([0.35, 6.0, 1.6])
		for i in n - 1:
			var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
			var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
			if a.distance_to(b) > 60.0:
				continue
			var dirw := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var side := Vector3(dirw.z, 0, -dirw.x)
			for o in offs:
				var prev := Vector3.ZERO
				for s_ in 11:
					var f := s_ / 10.0
					var q := a.lerp(b, f) + side * float(o[0]) + Vector3(0, float(o[1]) - float(o[2]) * 4.0 * f * (1.0 - f), 0)
					if s_ > 0:
						var up := Vector3(0, 0.012, 0)
						_quad(t, prev - up, q - up, q + up, prev + up, side, Color(0.02, 0.02, 0.02), Vector2.ZERO, Vector2.ZERO,
							Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
						_quad(t, q - up, prev - up, prev + up, q + up, -side, Color(0.02, 0.02, 0.02), Vector2.ZERO, Vector2.ZERO,
							Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					prev = q
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
	out["wires"] = m


## The same mesh with automatic levels of detail (Godot picks a coarser one as it gets smaller on screen):
## a parked bike of 8 000 triangles drops to a few hundred a street away.
static func _with_lods(m: Mesh) -> Mesh:
	if m == null or not (m is ArrayMesh):
		return m
	var im := ImporterMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		if arr[Mesh.ARRAY_INDEX] == null:
			var ix := PackedInt32Array()
			ix.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i in ix.size():
				ix[i] = i
			arr[Mesh.ARRAY_INDEX] = ix
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, m.surface_get_material(si))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


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
			var tkey := Vector3i(ti, floori(q.x / LIFE_CELL), floori(q.z / LIFE_CELL))
			if not trees.has(tkey):
				trees[tkey] = []
			trees[tkey].append(Transform3D(Basis(Vector3.UP, fmod(hsh * 7.0, TAU)).scaled(Vector3(sc, sc, sc)), q))
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
	for tkey in trees:
		for lod in 3:                                   # 0 near, 1 far, 2 the near set's shadow from the far mesh
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = tree_meshes[tkey.x][mini(lod, 1)]
			mm.instance_count = trees[tkey].size()
			for i in trees[tkey].size():
				mm.set_instance_transform(i, trees[tkey][i])
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
	# only inside a closed compound: an open wall (a front wall alone, a U open to the street) has its middle on the
	# footpath or the road, where bikes were standing in the traffic
	if Vector2(p[0] - p[(n - 1) * 3], p[2] - p[(n - 1) * 3 + 2]).length() > 0.5:
		return
	var poly := PackedVector2Array()
	for i in n - 1:
		poly.append(Vector2(p[i * 3], p[i * 3 + 2]))
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
	if not (is_finite(c.x) and is_finite(c.z)):
		return
	var h := fposmod(absf(sin(c.x * 12.9898 + c.z * 78.233) * 43758.5453), 1000.0)
	var count := (2 + int(h) % 4) if shop else (int(h) % 3)
	count = mini(count, int(best / 0.9) - 1)
	var across := Vector3(dir.z, 0, -dir.x)
	for k in count:
		var q := c + dir * ((k - (count - 1) * 0.5) * 0.9) + Vector3(0, 0.02, 0)
		if not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), poly):     # the whole bike inside the yard
			continue
		if not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z) + Vector2(dir.z, -dir.x) * 1.0, poly) \
				or not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z) - Vector2(dir.z, -dir.x) * 1.0, poly):
			continue
		var jit := fmod(h * (k + 3.1), 1.0)
		var bi := posmod(int(h * (k + 1.7)), bike_meshes.size())
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
	if loaded.has(k) or d.is_empty():
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
			mmi.visibility_range_end = kit_near + 10.0
		else:
			mmi.visibility_range_begin = kit_near
			mmi.visibility_range_end = KIT_RANGE + 10.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	if d.has("walk_mesh"):
		var wmi := MeshInstance3D.new()
		wmi.mesh = d["walk_mesh"]
		wmi.material_override = walk_mat
		wmi.visibility_range_end = 700.0
		node.add_child(wmi)
	if d.has("kerb_mesh") and not "--nokerbs" in OS.get_cmdline_user_args():
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
			tmi.visibility_range_end = TREE_NEAR + LIFE_CELL * 0.71
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif tr[1] == 2:
			# the near trees' shadows come from the light far version (an eighth of the triangles)
			tmi.visibility_range_end = TREE_NEAR + LIFE_CELL * 0.71
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			tmi.visibility_range_begin = TREE_NEAR + LIFE_CELL * 0.71 - 4.0
			tmi.visibility_range_end = 500.0
			tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(tmi)
	if d.has("median_mesh") and not "--nokerbs" in OS.get_cmdline_user_args():
		var mdi := MeshInstance3D.new()
		mdi.mesh = d["median_mesh"]
		mdi.material_override = kerb_mat
		mdi.visibility_range_end = 600.0
		node.add_child(mdi)
		var mcs := CollisionShape3D.new()
		mcs.shape = d["median_shape"]
		_shape(node, mcs)
	if d.has("fly_mesh"):
		var fmi2 := MeshInstance3D.new()
		fmi2.mesh = d["fly_mesh"]
		fmi2.material_override = kerb_mat
		node.add_child(fmi2)
		var fcs := CollisionShape3D.new()
		fcs.shape = d["fly_shape"]
		_shape(node, fcs)
	for fk in ["fly_piers", "fly_lamps"]:
		if d.has(fk):
			var fpi := MultiMeshInstance3D.new()
			fpi.multimesh = d[fk]
			fpi.visibility_range_end = 900.0
			node.add_child(fpi)
	if d.has("sep_plants"):
		var spi := MultiMeshInstance3D.new()
		spi.multimesh = d["sep_plants"]
		spi.visibility_range_end = 250.0
		node.add_child(spi)
	if d.has("median_plants"):
		var mpi := MultiMeshInstance3D.new()
		mpi.multimesh = d["median_plants"]
		mpi.visibility_range_end = 250.0
		node.add_child(mpi)
	for lm in ([] if "--nolife" in OS.get_cmdline_user_args() else d.get("life", [])):
		var lmi2 := MultiMeshInstance3D.new()
		lmi2.multimesh = lm[0]
		lmi2.visibility_range_end = lm[1]
		lmi2.visibility_range_begin = lm[2]
		lmi2.lod_bias = lm[0].get_meta("lod_bias", 1.0)
		if lm.size() > 3:
			lmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if lm[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif lm[1] < 150.0 or lm[2] > 0.0:
			lmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lmi2)
	if d.has("wires"):
		var wmi2 := MeshInstance3D.new()
		wmi2.mesh = d["wires"]
		if wire_mat == null:
			wire_mat = StandardMaterial3D.new()
			wire_mat.albedo_color = Color(0.03, 0.03, 0.03)
			wire_mat.roughness = 0.6
		wmi2.material_override = wire_mat
		wmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wmi2.visibility_range_end = 250.0
		node.add_child(wmi2)
	for bm3 in d.get("bikes", []):
		var bmi := MultiMeshInstance3D.new()
		bmi.multimesh = bm3
		bmi.visibility_range_end = 70.0
		bmi.lod_bias = 6.0                  # keep detail: a coarse level drops the painted body and leaves floating wheels
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	node.set_meta("signals", d.get("signals", []))
	node.set_meta("bldinfo", d.get("bldinfo", []))
	_landmarks(k, node)
	loaded[k] = node
	stats["built"] += 1
	stats["loaded"] = loaded.size()
	stats["buildings"] += int(d.get("n_blds", 0))
	stats["designed"] += int(d.get("n_kit", 0))


## Is a footprint centred here the lot of a landmark (whose own design replaces it)?
func _landmark_lot(c: Vector2) -> bool:
	for lm in landmarks:
		for lot in lm.get("lots", []):
			if c.distance_to(Vector2(lot[0], lot[1])) < 3.0:
				return true
		if lm.has("clear"):                          # (an outline whose blocks all go: a bus stand's yard)
			var poly := PackedVector2Array()
			for q in lm["clear"]:
				poly.append(Vector2(q[0], q[1]))
			if Geometry2D.is_point_in_polygon(c, poly):
				return true
	return false


## The ground under a landmark levelled to its floor ("pad": [x0, x1, y0, y1] of the design, Blender metres), easing
## back to the land around over LEVEL_EASE metres: real buildings stand on levelled lots, not on the DEM's slopes.
const LEVEL_EASE := 6.0
func _level(x0: float, z0: float, n: int, step: float, h: PackedFloat32Array) -> PackedFloat32Array:
	var out := h
	for lm in landmarks:
		if not lm.has("pad"):
			continue
		var pad: Array = lm["pad"]
		var c := cos(float(lm["yaw"]))
		var sn := sin(float(lm["yaw"]))
		var reach: float = Vector2(pad[1] - pad[0], pad[3] - pad[2]).length() * 0.5 + LEVEL_EASE + 60.0
		if absf(float(lm["x"]) - (x0 + tile * 0.5)) > tile * 0.5 + reach or absf(float(lm["z"]) - (z0 + tile * 0.5)) > tile * 0.5 + reach:
			continue
		for i in n:
			for j in n:
				var dx := x0 + j * step - float(lm["x"])
				var dz := z0 + i * step - float(lm["z"])
				var bx := dx * c - dz * sn                  # into the design's frame (Blender x, y)
				var by := -(dx * sn + dz * c)
				var ox := maxf(maxf(float(pad[0]) - bx, bx - float(pad[1])), 0.0)
				var oy := maxf(maxf(float(pad[2]) - by, by - float(pad[3])), 0.0)
				var d := Vector2(ox, oy).length()
				if d >= LEVEL_EASE:
					continue
				var t := smoothstep(0.0, 1.0, d / LEVEL_EASE)
				out[i * n + j] = lerpf(float(lm["y"]) - 0.05, out[i * n + j], t)
	return out


## The landmarks standing in tile k (godot/assets/landmarks/landmarks.json), solid like the rest of the city.
func _landmarks(k: Vector2i, node: Node3D) -> void:
	for lm in landmarks:
		if floori(float(lm["x"]) / tile) != k.x or floori(float(lm["z"]) / tile) != k.y or not ResourceLoader.exists(lm["glb"]):
			continue
		var sc := (load(lm["glb"]) as PackedScene).instantiate() as Node3D
		node.add_child(sc)
		sc.global_position = Vector3(lm["x"], lm["y"], lm["z"])
		sc.rotation.y = float(lm["yaw"])
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var cs := CollisionShape3D.new()
			cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
			cs.transform = (mi as MeshInstance3D).global_transform
			_shape(node, cs)
		for lb in lm.get("labels", []):                  # at [x, y, z] of the design (Blender: z up, front -y)
			var l := Label3D.new()
			l.text = lb["text"]
			l.font_size = 96
			l.outline_size = 0
			l.pixel_size = float(lb["h"]) / 96.0
			l.modulate = Color.html(lb.get("color", "#000000"))
			l.position = Vector3(lb["at"][0], lb["at"][2], -float(lb["at"][1]))
			l.shaded = true
			l.double_sided = false
			sc.add_child(l)


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
