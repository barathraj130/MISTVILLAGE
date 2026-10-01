extends RefCounted
## Accumulates coloured triangles, quads, boxes and cylinders into one ArrayMesh,
## so a whole town, vehicle or wall run is a single draw call.
## Pass faces counter-clockwise as seen from the front (or give an outward hint);
## they are emitted clockwise, which is Godot's front-face winding.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


func is_empty() -> bool:
	return verts.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, hint := Vector3.ZERO,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if hint != Vector3.ZERO and n.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		var tu := uvb
		uvb = uvc
		uvc = tu
		n = -n
	var i := verts.size()
	verts.append_array([a, b, c])
	normals.append_array([n, n, n])
	colors.append_array([col, col, col])
	uvs.append_array([uva, uvb, uvc])
	indices.append_array([i, i + 2, i + 1])


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint := Vector3.ZERO,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO, uvd := Vector2.ZERO) -> void:
	if hint == Vector3.ZERO:
		hint = (b - a).cross(c - a)
	tri(a, b, c, col, hint, uva, uvb, uvc)
	tri(a, c, d, col, hint, uva, uvc, uvd)


## Double-sided quad (fronds, leaves, thin boards).
func quad2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	quad(a, b, c, d, col, n)
	quad(a, b, c, d, col, -n)


## Axis-aligned box in the frame `xf` (centre = xf.origin), size in local axes.
func box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in 3:
		for s in [-1.0, 1.0]:
			var n: Vector3 = axes[i] * s
			var u: Vector3 = axes[(i + 1) % 3]
			var v: Vector3 = axes[(i + 2) % 3]
			var c: Vector3 = n * h[i]
			var hu: Vector3 = u * h[(i + 1) % 3]
			var hv: Vector3 = v * h[(i + 2) % 3]
			quad(xf * (c - hu - hv), xf * (c + hu - hv), xf * (c + hu + hv), xf * (c - hu + hv),
				col, xf.basis * n)


## Cylinder along local +Y from the frame origin, `sides` facets, optional caps.
func cylinder(xf: Transform3D, r0: float, r1: float, h: float, col: Color, sides := 8, caps := true) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var q0 := Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := Vector3(cos(a1) * r1, h, sin(a1) * r1)
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		quad(xf * p0, xf * p1, xf * q1, xf * q0, col, xf.basis * mid)
		if caps:
			tri(xf * Vector3(0, h, 0), xf * q0, xf * q1, col, xf.basis * Vector3.UP)
			tri(xf * Vector3.ZERO, xf * p0, xf * p1, col, xf.basis * Vector3.DOWN)


## Faceted ellipsoid centred on the frame origin.
func ellipsoid(xf: Transform3D, radii: Vector3, col: Color, rings := 6, segs := 10) -> void:
	for r in rings:
		var t0 := PI * r / rings - PI * 0.5
		var t1 := PI * (r + 1) / rings - PI * 0.5
		for s in segs:
			var p0 := TAU * s / segs
			var p1 := TAU * (s + 1) / segs
			var a := Vector3(cos(t0) * cos(p0), sin(t0), cos(t0) * sin(p0)) * radii
			var b := Vector3(cos(t0) * cos(p1), sin(t0), cos(t0) * sin(p1)) * radii
			var c := Vector3(cos(t1) * cos(p1), sin(t1), cos(t1) * sin(p1)) * radii
			var d := Vector3(cos(t1) * cos(p0), sin(t1), cos(t1) * sin(p0)) * radii
			var mid := (a + b + c + d) * 0.25
			quad(xf * a, xf * b, xf * c, xf * d, col, xf.basis * mid)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func vertex_color_material(rough := 0.85, cull := BaseMaterial3D.CULL_BACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.cull_mode = cull
	return m


## Photo-textured (CC0, assets/drive/tex) material, projected in world space (no UVs needed),
## multiplied by vertex colour so painted surfaces keep their paint.
static func cc0_material(key: String, tile: float, rough := 0.9, vertex_color := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/drive/tex/" + key
	if ResourceLoader.exists(base + "_color.jpg"):
		m.albedo_texture = load(base + "_color.jpg")
		if ResourceLoader.exists(base + "_normal.jpg"):
			m.normal_enabled = true
			m.normal_texture = load(base + "_normal.jpg")
			m.normal_scale = 0.8
		if ResourceLoader.exists(base + "_rough.jpg"):
			m.roughness_texture = load(base + "_rough.jpg")
	m.roughness = rough
	m.vertex_color_use_as_albedo = vertex_color
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
