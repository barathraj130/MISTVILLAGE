extends Node3D
## Streams the real Coimbatore (tools/citygen/chunk.py → assets/city/) in 256 m tiles around a target:
## tiles within `radius` tiles load, tiles beyond `radius + 1` unload. Reading and parsing a tile and building
## its mesh arrays happens on worker threads; only creating the meshes / collision touches the main thread,
## at most `per_frame` tiles a frame, nearest first. Nothing global is kept except the index.
##
## A tile node holds: ground (33 × 33 heights, 8 m grid, heightmap collision) and its roads (worn asphalt
## strips with the road_surface shader, concave collision). Game frame: x = east, z = south, y = elevation.

const DIR := "res://assets/city/"
const RANK := {"trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03,
	"residential": 0.025, "living_street": 0.02, "service": 0.015, "track": 0.01, "footway": 0.035}

@export var radius := 3                    # tiles each way to keep loaded (3 → 7 × 7 = 1.8 km square)
@export var per_frame := 1                 # tiles instanced per frame at most
var target: Node3D
var index := {}
var tile := 256.0
var loaded := {}                           # Vector2i → Node3D
var pending := {}                          # Vector2i → task id
var ready_q: Array = []                    # [key, data] built on a worker, waiting for the main thread
var _mutex := Mutex.new()
var road_mat: Material
var ground_mat: Material
var body: StaticBody3D
var stats := {"loaded": 0, "built": 0, "unloaded": 0}


func _ready() -> void:
	index = JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json"))
	tile = float(index["tile"])
	body = StaticBody3D.new()
	body.name = "CityCollision"
	add_child(body)


func set_materials(road: Material, ground: Material) -> void:
	road_mat = road
	ground_mat = ground


func _process(_dt: float) -> void:
	if target == null:
		return
	var c := Vector2i(floori(target.global_position.x / tile), floori(target.global_position.z / tile))
	# request what's missing, nearest first
	var want: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not loaded.has(k) and not pending.has(k) and index["tiles"].has("%d,%d" % [k.x, k.y]):
				want.append(k)
	want.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	for k in want.slice(0, 6):
		pending[k] = WorkerThreadPool.add_task(_build.bind(k))
	# finish a few on the main thread
	var n := 0
	while n < per_frame:
		_mutex.lock()
		var item = ready_q.pop_front() if not ready_q.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		_instance(item[0], item[1])
		n += 1
	# unload far tiles
	for k in loaded.keys():
		if absi(k.x - c.x) > radius + 1 or absi(k.y - c.y) > radius + 1:
			(loaded[k] as Node3D).queue_free()
			loaded.erase(k)
			stats["unloaded"] += 1
	for k in pending.keys():
		if WorkerThreadPool.is_task_completed(pending[k]):
			WorkerThreadPool.wait_for_task_completion(pending[k])
			pending.erase(k)


## Worker thread: read the tile and turn it into plain arrays (no scene objects here).
func _build(k: Vector2i) -> void:
	var path := DIR + "chunks/CBE_%d_%d.json" % [k.x, k.y]
	if not FileAccess.file_exists(path):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := _resources(k, _ground_arrays(k, d["h"]), _road_arrays(d["roads"]))
	out["roads_raw"] = d["roads"]
	_mutex.lock()
	ready_q.append([k, out])
	_mutex.unlock()


func _ground_arrays(k: Vector2i, h: Array) -> Dictionary:
	var n: int = int(index["hn"])
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
			v[i * n + j] = Vector3(x0 + j * step, float(h[i * n + j]), z0 + i * step)
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
	var hm := PackedFloat32Array()
	hm.resize(n * n)
	for q in n * n:
		hm[q] = float(h[q])
	return {"v": v, "n": nm, "i": idx, "hm": hm}


func _road_arrays(roads: Array) -> Dictionary:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for r in roads:
		var p: Array = r["p"]
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
	return {"v": v, "n": nm, "c": cl, "uv": uv, "i": idx, "f": faces}


## Worker thread: meshes and collision shapes are plain resources, safe to make here.
func _resources(k: Vector2i, g: Dictionary, r: Dictionary) -> Dictionary:
	var out := {}
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g["v"]
	arr[Mesh.ARRAY_NORMAL] = g["n"]
	arr[Mesh.ARRAY_INDEX] = g["i"]
	var gm := ArrayMesh.new()
	gm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out["ground_mesh"] = gm
	var n: int = int(index["hn"])
	var hs := HeightMapShape3D.new()
	hs.map_width = n
	hs.map_depth = n
	hs.map_data = g["hm"]
	out["ground_shape"] = hs
	if not (r["v"] as PackedVector3Array).is_empty():
		var ra := []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = r["v"]
		ra[Mesh.ARRAY_NORMAL] = r["n"]
		ra[Mesh.ARRAY_COLOR] = r["c"]
		ra[Mesh.ARRAY_TEX_UV] = r["uv"]
		ra[Mesh.ARRAY_INDEX] = r["i"]
		var rm := ArrayMesh.new()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		out["road_mesh"] = rm
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(r["f"])
		out["road_shape"] = shape
	return out


## Main thread: only nodes go into the scene here (everything heavy was made on a worker).
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
	node.add_child(_owned_shape(cs))
	if d.has("road_mesh"):
		var rmi := MeshInstance3D.new()
		rmi.mesh = d["road_mesh"]
		rmi.material_override = road_mat
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rmi)
		var rcs := CollisionShape3D.new()
		rcs.shape = d["road_shape"]
		node.add_child(_owned_shape(rcs))
	node.set_meta("roads", d["roads_raw"])
	loaded[k] = node
	stats["built"] += 1
	stats["loaded"] = loaded.size()


## Collision shapes live under one StaticBody3D, but are freed with their tile.
func _owned_shape(cs: CollisionShape3D) -> Node:
	var holder := Node.new()
	holder.name = "shape"
	var gx := cs.position
	cs.position = gx
	body.add_child(cs)
	holder.tree_exiting.connect(func() -> void:
		if is_instance_valid(cs):
			cs.queue_free())
	return holder


## Ground height under (x, z) from loaded tiles, or NAN.
func height_at(x: float, z: float) -> float:
	var k := Vector2i(floori(x / tile), floori(z / tile))
	if not loaded.has(k):
		return NAN
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 3000, z), Vector3(x, -500, z))
	var hit := space.intersect_ray(q)
	return hit["position"].y if hit else NAN


## A drivable line to follow from loaded tiles: points of main roads near p (for tests and spawning).
func road_near(p: Vector3, classes := ["trunk", "primary", "secondary"]) -> PackedVector3Array:
	var best := PackedVector3Array()
	var bd := INF
	for k in loaded:
		for r in (loaded[k] as Node3D).get_meta("roads", []):
			if not r["c"] in classes:
				continue
			var a: Array = r["p"]
			var q := Vector3(a[0], a[1], a[2])
			var dd := Vector2(q.x - p.x, q.z - p.z).length()
			if dd < bd:
				bd = dd
				best = PackedVector3Array()
				for i in a.size() / 3:
					best.append(Vector3(a[i * 3], a[i * 3 + 1], a[i * 3 + 2]))
	return best
