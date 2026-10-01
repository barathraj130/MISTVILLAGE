extends RefCounted
## Shares the resort's exported vegetation (full and ~200-triangle LOD meshes) with the drive,
## converting leaf materials to the wind-swayed foliage shader.

const SCENE_JSON := "res://assets/scene.json"
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const LOD_DISTANCE := 140.0
const CELL := 192.0                 # one MultiMesh per asset per cell: bigger cells = fewer draw calls
const LOD_CELL := 512.0
const MAX_DRAW := 700.0             # trees beyond this are left to the far-forest layer

var assets := {}
var hints := {}
var _cache := {}


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCENE_JSON))
	if typeof(parsed) == TYPE_DICTIONARY:
		assets = parsed.get("vegetation", {}).get("assets", {})
		hints = parsed.get("materials", {})


func has(key: String) -> bool:
	return assets.has(key)


func mesh(key: String, lod := false) -> Mesh:
	var ck := key + ("_lod" if lod else "")
	if _cache.has(ck):
		return _cache[ck]
	if not assets.has(key):
		return null
	var path: String = assets[key].get("lod_model" if lod else "model", assets[key]["model"])
	var ps := load("res://assets/" + path) as PackedScene
	if ps == null:
		return null
	var node := ps.instantiate()
	var found := node.find_children("*", "MeshInstance3D", true, false)
	var m: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	node.free()
	if m:
		for s in m.get_surface_count():
			var src := m.surface_get_material(s) as BaseMaterial3D
			if src and hints.get(src.resource_name, {}).get("kind", "") == "leaf":
				var fm := ShaderMaterial.new()
				fm.shader = FOLIAGE_SHADER
				fm.set_shader_parameter("albedo_tex", src.albedo_texture)
				fm.set_shader_parameter("albedo_color", src.albedo_color)
				fm.set_shader_parameter("wind_strength", 0.02)
				m.surface_set_material(s, fm)
	_cache[ck] = m
	return m


## Adds MultiMesh chunks (128 m cells) for `xfs`, with LOD switching when available.
func place(parent: Node, key: String, xfs: Array, shadows := true, max_range := 0.0, cell := CELL) -> void:
	var full := mesh(key)
	if full == null or xfs.is_empty():
		return
	var lod: Mesh = mesh(key, true) if assets[key].has("lod_model") else null
	for c in _cells(xfs, cell).values():
		parent.add_child(multimesh(full, c, 0.0, LOD_DISTANCE if lod else max_range, shadows))
	if lod:
		# the far copies are cheap, so they go in big cells: a hairpin ghat sees dozens of cells at once
		for c in _cells(xfs, LOD_CELL).values():
			parent.add_child(multimesh(lod, c, LOD_DISTANCE, max_range if max_range > 0.0 else MAX_DRAW, false))


static func _cells(xfs: Array, cell: float) -> Dictionary:
	var cells := {}
	for xf in xfs:
		var c := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(xf)
	return cells


static func multimesh(m: Mesh, xfs: Array, begin: float, end: float, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = m
	mm.instance_count = xfs.size()
	var rng := RandomNumberGenerator.new()
	for i in xfs.size():
		var xf: Transform3D = xfs[i]
		mm.set_instance_transform(i, xf)
		rng.seed = hash(xf.origin)
		var v := rng.randf_range(0.8, 1.12)
		mm.set_instance_color(i, Color(v * rng.randf_range(0.92, 1.06), v, v * rng.randf_range(0.9, 1.04)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if begin > 0.0:
		mmi.visibility_range_begin = begin
		mmi.visibility_range_begin_margin = 10.0
	if end > 0.0:
		mmi.visibility_range_end = end
		mmi.visibility_range_end_margin = 10.0 if end <= LOD_DISTANCE else end * 0.1
	return mmi
