extends RefCounted
## Dents you can see: a crash pushes the body's surface in round the point it was hit, deepest at the point and
## easing out to nothing at the dent's edge, crumpled a little (not a smooth dimple), the normals bent with it so
## the light shows the crease. Works on any vehicle model (jeep.gd's own body, the traffic's fleet models): it
## changes copies of the meshes it touches, and keeps the originals so a repair puts them back.
##   dent(root, at, push, radius, depth, keep, skip)
##     root    the vehicle node; every MeshInstance3D under it within reach is dented
##     at      the hit, world position; push: the way the metal goes (world, into the body)
##     keep    {MeshInstance3D: original Mesh}, filled here; mend(keep) restores them
##     skip    nodes whose meshes are left alone (wheels, the rider, the cabin seen from inside)

const MAX_IN := 0.35                 # no point goes in more than this, however many hits (metres)


static func dent(root: Node3D, at: Vector3, push: Vector3, radius: float, depth: float, keep: Dictionary, skip: Array = []) -> int:
	var moved := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _skipped(mi, skip):
			continue
		var xf := mi.global_transform                            # (measured in metres: imported parts can be scaled
		var inv := xf.affine_inverse()                           #  unevenly, 100 units one way and 1.5 another)
		if not (xf * mi.mesh.get_aabb()).grow(radius).has_point(at):
			continue
		var dir := push.normalized()
		var to_root := root.global_transform.affine_inverse() * xf   # (one crumple for every part)
		var src: Mesh = mi.mesh
		if not keep.has(mi):
			keep[mi] = src
		var out := ArrayMesh.new()
		var any := false
		for s in src.get_surface_count():
			var prim := (src as ArrayMesh).surface_get_primitive_type(s) if src is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES   # (BoxMesh, QuadMesh...: triangles)
			var arrays: Array = src.surface_get_arrays(s)
			if prim == Mesh.PRIMITIVE_TRIANGLES:
				arrays = _refine(arrays, xf, at, radius)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var orig: PackedVector3Array = (keep[mi] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX] if keep[mi] != src else v
			for i in v.size():
				var q := v[i]
				var wq := xf * q
				var dist := wq.distance_to(at)
				if dist >= radius:
					continue
				var f := 1.0 - dist / radius
				f = f * f * (3.0 - 2.0 * f)                              # (smooth at the edge)
				var w := to_root * q
				var crumple := 0.85 + 0.3 * sin(w.x * 9.0 + w.y * 7.0) * cos(w.z * 8.0 - w.x * 3.0)
				var nw := wq + dir * depth * f * crumple
				if i < orig.size():
					var ow := xf * orig[i]
					if nw.distance_to(ow) > MAX_IN:
						nw = ow + (nw - ow).normalized() * MAX_IN
				v[i] = inv * nw
				if i < nrm.size():
					var tilt := (xf.basis.transposed() * (wq - at).normalized()).normalized() * f * 0.6   # (the metal round a dent faces in towards it)
					nrm[i] = (nrm[i] - tilt).normalized()
				any = true
				moved += 1
			arrays[Mesh.ARRAY_VERTEX] = v
			if not nrm.is_empty():
				arrays[Mesh.ARRAY_NORMAL] = nrm
			out.add_surface_from_arrays(prim, arrays)
			out.surface_set_material(s, src.surface_get_material(s))
		if any:
			mi.mesh = out
			if OS.is_debug_build() and "--dentdebug" in OS.get_cmdline_user_args():
				print("DENT mesh %s aabb %s" % [root.get_path_to(mi), str(src.get_aabb())])
	return moved


## Low-poly panels have too few points to dent: the triangles that reach into the dent are split in four (their
## new points shared with the neighbour across each edge, so nothing tears) until they're a quarter of the dent
## across. Triangles that don't reach it are left as they are; their edges are outside it, so they don't move.
static func _refine(arrays: Array, xf: Transform3D, c: Vector3, r: float) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tan: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var target := r * 0.25
	var changed := false
	for it in 4:
		var mids := {}
		var out := PackedInt32Array()
		var split := 0
		for t in idx.size() / 3:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var d := idx[t * 3 + 2]
			var pa := xf * v[a]
			var pb := xf * v[b]
			var pd := xf * v[d]
			var longest := maxf(pa.distance_to(pb), maxf(pb.distance_to(pd), pd.distance_to(pa)))
			var centre := (pa + pb + pd) / 3.0
			if longest <= target or centre.distance_to(c) > r + longest or v.size() > 60000:
				out.append_array([a, b, d])
				continue
			var m := []
			for e in [[a, b], [b, d], [d, a]]:
				var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not mids.has(k):
					var i0: int = e[0]
					var i1: int = e[1]
					mids[k] = v.size()
					v.append((v[i0] + v[i1]) * 0.5)
					if nrm.size() > i1 and nrm.size() > i0:
						nrm.append((nrm[i0] + nrm[i1]).normalized())
					if tan.size() >= (maxi(i0, i1) + 1) * 4:
						for j in 4:
							tan.append((tan[i0 * 4 + j] + tan[i1 * 4 + j]) * 0.5)
					if col.size() > maxi(i0, i1):
						col.append(col[i0].lerp(col[i1], 0.5))
					if uv.size() > maxi(i0, i1):
						uv.append((uv[i0] + uv[i1]) * 0.5)
					if uv2.size() > maxi(i0, i1):
						uv2.append((uv2[i0] + uv2[i1]) * 0.5)
				m.append(mids[k])
			out.append_array([a, m[0], m[2], m[0], b, m[1], m[2], m[1], d, m[0], m[1], m[2]])
			split += 1
		idx = out
		if split == 0:
			break
		changed = true
	if not changed:
		return arrays
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	if nrm.size() == v.size():
		arrays[Mesh.ARRAY_NORMAL] = nrm
	if tan.size() == v.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = tan
	if col.size() == v.size():
		arrays[Mesh.ARRAY_COLOR] = col
	if uv.size() == v.size():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	if uv2.size() == v.size():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	for k in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arrays[k] = null
	return arrays


static func mend(keep: Dictionary) -> void:
	for mi in keep:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).mesh = keep[mi]
	keep.clear()


static func _skipped(mi: Node, skip: Array) -> bool:
	for s in skip:
		if s and is_instance_valid(s) and (s == mi or (s as Node).is_ancestor_of(mi)):
			return true
	return false
