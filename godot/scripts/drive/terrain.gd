extends Node3D
## Terrain for the drive: a 4 m heightfield along the road corridor, carved under the road
## (steep red-soil cuttings uphill, long embankments downhill), plus a coarse 64 m backdrop
## out to the horizon with holes where the detailed chunks are. Built once at load.

const Route := preload("res://scripts/drive/route.gd")
const CELL := 4.0
const CHUNK := 32                 # cells per chunk side → 128 m chunks
const CORRIDOR := 320.0           # detailed terrain this far from the road
const FLAT := 6.2                 # flat half-width under road + shoulders
const BLEND_CUT := 14.0           # uphill: ground returns to natural quickly (cutting)
const BLEND_FILL := 30.0          # downhill: long embankment
const NEAR_RADIUS := 12.0         # "near a road" radius used to keep props off it
const FAR_CELL := 64.0
const FAR_EXTENT := 9000.0
const DRAW_DISTANCE := 1300.0
const SKIRT := 12.0

var route: Route
var material: Material
var gx0 := 0
var gz0 := 0
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var near := PackedFloat32Array()      # 0..1, 1 on a road
var have := PackedByteArray()
var chunk_keys: Array = []
var _prox := PackedByteArray()        # real map: 0..255 closeness to a road
var _chunk_set := {}


func setup(r, mat: Material) -> void:
	route = r
	material = mat


func _wx(ix: int) -> float:
	return (ix + gx0) * CELL


func _wz(iz: int) -> float:
	return (iz + gz0) * CELL


func _k(ix: int, iz: int) -> int:
	return iz * nx + ix


# ----------------------------------------------------------------------------- heights
func build_heights() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in route.pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var span := CHUNK * CELL
	gx0 = floori((lo.x - CORRIDOR) / span) * CHUNK
	gz0 = floori((lo.y - CORRIDOR) / span) * CHUNK
	nx = ceili((hi.x + CORRIDOR) / span) * CHUNK - gx0 + 1
	nz = ceili((hi.y + CORRIDOR) / span) * CHUNK - gz0 + 1
	h.resize(nx * nz)
	near.resize(nx * nz)
	near.fill(0.0)
	have.resize(nx * nz)
	have.fill(0)

	# chunks within the corridor
	var ncx := (nx - 1) / CHUNK
	var ncz := (nz - 1) / CHUNK
	for i in range(0, route.pts.size(), 8):
		var p: Vector3 = route.pts[i]
		var cx0 := clampi(floori(((p.x - CORRIDOR) / CELL - gx0) / CHUNK), 0, ncx - 1)
		var cx1 := clampi(floori(((p.x + CORRIDOR) / CELL - gx0) / CHUNK), 0, ncx - 1)
		var cz0 := clampi(floori(((p.z - CORRIDOR) / CELL - gz0) / CHUNK), 0, ncz - 1)
		var cz1 := clampi(floori(((p.z + CORRIDOR) / CELL - gz0) / CHUNK), 0, ncz - 1)
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var key := Vector2i(cx, cz)
				if not _chunk_set.has(key):
					_chunk_set[key] = true
					chunk_keys.append(key)

	# natural ground
	for key in chunk_keys:
		for lz in CHUNK + 1:
			var iz: int = key.y * CHUNK + lz
			for lx in CHUNK + 1:
				var ix: int = key.x * CHUNK + lx
				var k := _k(ix, iz)
				if have[k] == 0:
					h[k] = route.natural_h(_wx(ix), _wz(iz))
					have[k] = 1

	# carve the road in: nearest road sample wins where switchback legs overlap
	var w := PackedFloat32Array()
	w.resize(nx * nz)
	w.fill(0.0)
	var tgt := PackedFloat32Array()
	tgt.resize(nx * nz)
	var bs: float = route.marks["bridge_start"] - 8.0
	var be: float = route.marks["bridge_end"] + 8.0
	var r := int(BLEND_FILL / CELL) + 1
	for i in route.pts.size():
		var p: Vector3 = route.pts[i]
		var on_bridge: bool = route.dist[i] > bs and route.dist[i] < be
		var cx := roundi(p.x / CELL) - gx0
		var cz := roundi(p.z / CELL) - gz0
		for iz in range(maxi(cz - r, 0), mini(cz + r + 1, nz)):
			var dz := _wz(iz) - p.z
			for ix in range(maxi(cx - r, 0), mini(cx + r + 1, nx)):
				var k := iz * nx + ix
				if have[k] == 0:
					continue
				var dx := _wx(ix) - p.x
				var dd := sqrt(dx * dx + dz * dz)
				if dd < NEAR_RADIUS:
					near[k] = maxf(near[k], 1.0 - dd / NEAR_RADIUS)
				if on_bridge:
					continue
				var blend := BLEND_CUT if h[k] > p.y else BLEND_FILL
				if dd >= blend:
					continue
				var wt := 1.0 if dd <= FLAT else 1.0 - smoothstep(FLAT, blend, dd)
				if wt > w[k]:
					w[k] = wt
					tgt[k] = p.y - 0.3
	for k in h.size():
		if w[k] > 0.0:
			h[k] = lerpf(h[k], tgt[k], w[k])


## Real map: carved heights, road proximity and corridor chunks come precompiled.
func load_real() -> void:
	var nm: Dictionary = route.near_grid()
	gx0 = int(nm["gx0"])
	gz0 = int(nm["gz0"])
	nx = int(nm["nx"])
	nz = int(nm["nz"])
	h = FileAccess.get_file_as_bytes(Route.MAP_DIR + nm["file"]).to_float32_array()
	_prox = FileAccess.get_file_as_bytes(Route.MAP_DIR + nm["proximity"])
	have.resize(nx * nz)
	have.fill(0)
	for c in nm["chunks"]:
		var key := Vector2i(int(c[0]), int(c[1]))
		_chunk_set[key] = true
		chunk_keys.append(key)
		for lz in CHUNK + 1:
			var iz: int = key.y * CHUNK + lz
			for lx in CHUNK + 1:
				var ix: int = key.x * CHUNK + lx
				var k := iz * nx + ix
				if have[k] == 1:
					continue
				if is_nan(h[k]):
					h[k] = route.far_h(_wx(ix), _wz(iz))
				have[k] = 1


## Rewrites heights (and road proximity) in a square region: fn(x, z, h, prox) -> Vector2(h, prox).
## Used to blend the map into the resort's own ground.
func blend_region(centre: Vector3, radius: float, fn: Callable) -> void:
	var ix0 := maxi(floori((centre.x - radius) / CELL) - gx0, 0)
	var ix1 := mini(ceili((centre.x + radius) / CELL) - gx0, nx - 1)
	var iz0 := maxi(floori((centre.z - radius) / CELL) - gz0, 0)
	var iz1 := mini(ceili((centre.z + radius) / CELL) - gz0, nz - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var k := iz * nx + ix
			if is_nan(h[k]):
				continue
			var pr := (_prox[k] / 255.0) if not _prox.is_empty() else near[k]
			var r: Vector2 = fn.call(_wx(ix), _wz(iz), h[k], pr)
			h[k] = r.x
			if not _prox.is_empty():
				_prox[k] = clampi(roundi(r.y * 255.0), 0, 255)


## Ground height anywhere (detailed where built, natural elsewhere).
func height_at(x: float, z: float) -> float:
	var fx := x / CELL - gx0
	var fz := z / CELL - gz0
	var ix := floori(fx)
	var iz := floori(fz)
	if ix < 0 or iz < 0 or ix >= nx - 1 or iz >= nz - 1:
		return route.natural_h(x, z)
	var k := _k(ix, iz)
	if have[k] == 0 or have[k + 1] == 0 or have[k + nx] == 0 or have[k + nx + 1] == 0:
		return route.natural_h(x, z)
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(h[k], h[k + 1], tx), lerpf(h[k + nx], h[k + nx + 1], tx), tz)


## 0..1 closeness to any stretch of road (1 = on it).
func near_road(x: float, z: float) -> float:
	var ix := roundi(x / CELL) - gx0
	var iz := roundi(z / CELL) - gz0
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return 0.0
	if not _prox.is_empty():
		return _prox[_k(ix, iz)] / 255.0
	return near[_k(ix, iz)]


func slope_at(x: float, z: float) -> float:
	var a := height_at(x + 2.0, z) - height_at(x - 2.0, z)
	var b := height_at(x, z + 2.0) - height_at(x, z - 2.0)
	return Vector2(a, b).length() / 4.0


# ----------------------------------------------------------------------------- meshes
func _hs(ix: int, iz: int, fallback: float) -> float:
	if ix < 0 or iz < 0 or ix >= nx or iz >= nz:
		return fallback
	var k := _k(ix, iz)
	return h[k] if have[k] == 1 else fallback


func _normal(ix: int, iz: int) -> Vector3:
	var c := h[_k(ix, iz)]
	var l := _hs(ix - 1, iz, c)
	var r := _hs(ix + 1, iz, c)
	var d := _hs(ix, iz - 1, c)
	var u := _hs(ix, iz + 1, c)
	return Vector3(l - r, 2.0 * CELL, d - u).normalized()


func _chunk_arrays(key: Vector2i) -> Array:
	var n := CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	for lz in n:
		var iz := key.y * CHUNK + lz
		for lx in n:
			var ix := key.x * CHUNK + lx
			verts[lz * n + lx] = Vector3(_wx(ix), h[_k(ix, iz)], _wz(iz))
			normals[lz * n + lx] = _normal(ix, iz)
	for lz in CHUNK:
		for lx in CHUNK:
			var a := lz * n + lx
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	# skirts hide cracks against the coarse backdrop
	var edges := [[0, 1, 0], [n * (n - 1), 1, 0], [0, n, 0], [n - 1, n, 0]]
	for e in edges:
		var start: int = e[0]
		var step: int = e[1]
		var base := verts.size()
		for m in n:
			var v := verts[start + step * m]
			verts.append(v)
			normals.append(normals[start + step * m])
			verts.append(v - Vector3(0, SKIRT, 0))
			normals.append(normals[start + step * m])
		for m in n - 1:
			var a := base + m * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])     # both windings
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _chunk_mesh(key: Vector2i) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _chunk_arrays(key))
	return mesh


## Builds detailed chunks; yields every few chunks so a loading screen can update.
## Builds the detailed ground in super-chunks of 4×4 chunks (512 m): one mesh and one collision
## shape each, so the GPU sees ~16× fewer terrain objects. Terrain casts no shadows (hills don't need it).
const SUPER := 4


func build_chunks(progress: Callable) -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	add_child(body)
	var supers := {}
	for key in chunk_keys:
		supers[Vector2i(floori(float(key.x) / SUPER), floori(float(key.y) / SUPER))] = true
	_super_set = supers
	var index_cache := {}
	var i := 0
	for sk in supers:
		var ix0: int = sk.x * SUPER * CHUNK
		var iz0: int = sk.y * SUPER * CHUNK
		var w := mini(SUPER * CHUNK + 1, nx - ix0)
		var d := mini(SUPER * CHUNK + 1, nz - iz0)
		var ik := Vector2i(w, d)
		if not index_cache.has(ik):
			index_cache[ik] = _grid_indices(w, d)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _super_arrays(ix0, iz0, w, d, index_cache[ik]))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = DRAW_DISTANCE + 256.0
		mi.visibility_range_end_margin = 150.0
		add_child(mi)
		body.add_child(_heightmap_shape(sk))
		i += 1
		if i % 6 == 0:
			progress.call(float(i) / supers.size())
			await get_tree().process_frame


var _super_set := {}


## Triangle indices for a w×d grid plus skirts round the outside (same for every super-chunk).
func _grid_indices(w: int, d: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (d - 1) * 6)
	var t := 0
	for lz in d - 1:
		for lx in w - 1:
			var a := lz * w + lx
			# split each cell along the same diagonal as HeightMapShape3D, so collision matches
			idx[t] = a
			idx[t + 1] = a + 1
			idx[t + 2] = a + w
			idx[t + 3] = a + 1
			idx[t + 4] = a + w + 1
			idx[t + 5] = a + w
			t += 6
	# skirts: for each edge, a strip down to SKIRT below (both windings)
	var base := w * d
	for e in [[0, 1, w], [w * (d - 1), 1, w], [0, w, d], [w - 1, w, d]]:
		var cnt: int = e[2]
		for m in cnt - 1:
			var a := base + m * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3, a, a + 1, a + 2, a + 1, a + 3, a + 2])
		base += cnt * 2
	return idx


## Vertices and normals of one super-chunk, straight from the height grid.
func _super_arrays(ix0: int, iz0: int, w: int, d: int, idx: PackedInt32Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(w * d)
	normals.resize(w * d)
	var hh := h
	var two_cell := 2.0 * CELL
	for lz in d:
		var iz := iz0 + lz
		var row := iz * nx
		var up := maxi(iz - 1, 0) * nx
		var dn := mini(iz + 1, nz - 1) * nx
		var z := (iz + gz0) * CELL
		for lx in w:
			var ix := ix0 + lx
			var k := row + ix
			var hl := hh[row + maxi(ix - 1, 0)]
			var hr := hh[row + mini(ix + 1, nx - 1)]
			var v := lz * w + lx
			verts[v] = Vector3((ix + gx0) * CELL, hh[k], z)
			normals[v] = Vector3(hl - hr, two_cell, hh[up + ix] - hh[dn + ix]).normalized()
	for e in [[0, 1, w], [w * (d - 1), 1, w], [0, w, d], [w - 1, w, d]]:
		var start: int = e[0]
		var step: int = e[1]
		var cnt: int = e[2]
		for m in cnt:
			var v := verts[start + step * m]
			var nrm := normals[start + step * m]
			verts.append(v)
			normals.append(nrm)
			verts.append(v - Vector3(0, SKIRT, 0))
			normals.append(nrm)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Heightmap collision for one 4×4 super-chunk, straight from row slices of the height grid.
func _heightmap_shape(sk: Vector2i) -> CollisionShape3D:
	var ix0 := sk.x * SUPER * CHUNK
	var iz0 := sk.y * SUPER * CHUNK
	var w := mini(SUPER * CHUNK + 1, nx - ix0)
	var d := mini(SUPER * CHUNK + 1, nz - iz0)
	var data := PackedFloat32Array()
	for r in d:
		var k := (iz0 + r) * nx + ix0
		data.append_array(h.slice(k, k + w))
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = d
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)
	cs.position = Vector3(_wx(ix0) + (w - 1) * CELL * 0.5, 0.0, _wz(iz0) + (d - 1) * CELL * 0.5)
	return cs


func build_far() -> void:
	var c: Vector3 = route.pts[route.pts.size() / 2]
	var n := int(FAR_EXTENT * 2.0 / FAR_CELL) + 1
	var ox := floorf((c.x - FAR_EXTENT) / FAR_CELL) * FAR_CELL
	var oz := floorf((c.z - FAR_EXTENT) / FAR_CELL) * FAR_CELL
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	for iz in n:
		for ix in n:
			var x := ox + ix * FAR_CELL
			var z := oz + iz * FAR_CELL
			verts[iz * n + ix] = Vector3(x, route.natural_h(x, z) - 0.5, z)
	normals.resize(n * n)
	for iz in n:
		for ix in n:
			var l := verts[iz * n + maxi(ix - 1, 0)].y
			var rr := verts[iz * n + mini(ix + 1, n - 1)].y
			var d := verts[maxi(iz - 1, 0) * n + ix].y
			var u := verts[mini(iz + 1, n - 1) * n + ix].y
			normals[iz * n + ix] = Vector3(l - rr, 2.0 * FAR_CELL, d - u).normalized()
	var span := CHUNK * CELL
	for iz in n - 1:
		for ix in n - 1:
			var cx := ox + (ix + 0.5) * FAR_CELL
			var cz := oz + (iz + 0.5) * FAR_CELL
			var key := Vector2i(floori((cx / CELL - gx0) / CHUNK), floori((cz / CELL - gz0) / CHUNK))
			if _chunk_set.has(key) and cx / CELL - gx0 >= 0 and cz / CELL - gz0 >= 0:
				continue
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Real map backdrop: the compiled 48 m grid, with holes where detailed chunks are.
func build_far_real() -> void:
	var fm: Dictionary = route.far_grid()
	var data: PackedFloat32Array = route.far_data()
	var w := int(fm["w"])
	var hh := int(fm["h"])
	var c: float = fm["cell"]
	var ox: float = fm["ox"]
	var oz: float = fm["oz"]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(w * hh)
	normals.resize(w * hh)
	for iz in hh:
		for ix in w:
			verts[iz * w + ix] = Vector3(ox + ix * c, data[iz * w + ix], oz + iz * c)
	for iz in hh:
		for ix in w:
			var l := data[iz * w + maxi(ix - 1, 0)]
			var r := data[iz * w + mini(ix + 1, w - 1)]
			var d := data[maxi(iz - 1, 0) * w + ix]
			var u := data[mini(iz + 1, hh - 1) * w + ix]
			normals[iz * w + ix] = Vector3(l - r, 2.0 * c, d - u).normalized()
	for iz in hh - 1:
		for ix in w - 1:
			var cx := ox + (ix + 0.5) * c
			var cz := oz + (iz + 0.5) * c
			var fx := cx / CELL - gx0
			var fz := cz / CELL - gz0
			if fx >= 0.0 and fz >= 0.0 and _super_set.has(Vector2i(floori(fx / (CHUNK * SUPER)), floori(fz / (CHUNK * SUPER)))):
				continue
			var a := iz * w + ix
			idx.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
