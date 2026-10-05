extends RefCounted
## The designed buildings from tools/buildings.py --export (godot/assets/buildings): city houses,
## apartments, shop-houses, hill cottages, bungalows and hotels in a few sizes and floor counts.
## Each is one mesh with two surfaces (building + glass); its vertex colours pick textures from two
## texture arrays in shaders/building_kit.gdshader, so a whole street of them is a few draw calls.

const DIR := "res://assets/buildings/"
const R := "res://assets/models/textures/"
const D := "res://assets/drive/tex/"
const SHADER := preload("res://shaders/building_kit.gdshader")
# layer → [albedo, normal, tile metres, roughness, metallic]; same order as KIT_LAYERS in buildings.py
const LAYERS := [
	["", "", 1.0, 0.6, 0.0],
	[R + "dark_nilgiri_stone_base.jpg", R + "dark_nilgiri_stone_normal.png", 2.5, 0.85, 0.0],
	[R + "stone_retaining_wall_base.jpg", R + "stone_retaining_wall_normal.png", 2.5, 0.85, 0.0],
	[R + "weathered_stone_coping_base.jpg", R + "weathered_stone_coping_normal.png", 1.5, 0.8, 0.0],
	[R + "warm_mineral_plaster_base.jpg", R + "warm_mineral_plaster_normal.png", 3.0, 0.85, 0.0],
	[D + "plaster_color.jpg", D + "plaster_normal.jpg", 2.5, 0.8, 0.0],
	[R + "warm_natural_timber_base.jpg", R + "warm_natural_timber_normal.png", 1.2, 0.5, 0.0],
	[R + "dark_timber_deck_base.jpg", R + "dark_timber_deck_normal.png", 1.2, 0.45, 0.0],
	[R + "charcoal_standing_seam_roof_base.jpg", R + "charcoal_standing_seam_roof_normal.png", 2.0, 0.35, 0.6],
	[D + "tin_roof_color.jpg", D + "tin_roof_normal.jpg", 2.0, 0.4, 0.5],
	[D + "concrete_color.jpg", D + "concrete_normal.jpg", 3.0, 0.85, 0.0],
	[R + "natural_stone_paving_base.jpg", R + "natural_stone_paving_normal.png", 2.5, 0.8, 0.0],
	[R + "parking_pavers_base.jpg", R + "parking_pavers_normal.png", 2.0, 0.8, 0.0],
	[R + "flagstone_path_base.jpg", R + "flagstone_path_normal.png", 2.0, 0.8, 0.0],
	["", "", 1.0, 0.35, 0.85],
]
const ALBEDO_SIZE := 1024
const NORMAL_SIZE := 512

var manifest := {}                 # variant name → {kind, w, d, floors, min, max, ...}
var material: ShaderMaterial
var glass: StandardMaterial3D
var _meshes := {}
var _by_kind := {}                 # kind → [variant names]


func setup() -> bool:
	var mp := DIR + "manifest.json"
	if not FileAccess.file_exists(mp):
		return false
	manifest = JSON.parse_string(FileAccess.get_file_as_string(mp))
	for name in manifest:
		var k: String = manifest[name]["kind"]
		if not _by_kind.has(k):
			_by_kind[k] = []
		_by_kind[k].append(name)
	material = ShaderMaterial.new()
	material.shader = SHADER
	var alb: Array[Image] = []
	var nrm: Array[Image] = []
	var tiles := PackedFloat32Array()
	var roughs := PackedFloat32Array()
	var metals := PackedFloat32Array()
	for L in LAYERS:
		alb.append(_image(L[0], ALBEDO_SIZE, Color(1, 1, 1)))
		nrm.append(_image(L[1], NORMAL_SIZE, Color(0.5, 0.5, 1.0)))
		tiles.append(L[2])
		roughs.append(L[3])
		metals.append(L[4])
	var ta := Texture2DArray.new()
	ta.create_from_images(alb)
	var tn := Texture2DArray.new()
	tn.create_from_images(nrm)
	material.set_shader_parameter("albedo_tex", ta)
	material.set_shader_parameter("normal_tex", tn)
	material.set_shader_parameter("tiles", tiles)
	material.set_shader_parameter("roughs", roughs)
	material.set_shader_parameter("metals", metals)
	glass = StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.32, 0.38, 0.42, 0.32)
	glass.metallic = 0.6
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	return true


func _image(path: String, size: int, fill: Color) -> Image:
	var img: Image
	if path != "" and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		img = tex.get_image().duplicate() if tex else null
	if img == null:
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(fill)
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return img


func set_night(v: float) -> void:
	if material:
		material.set_shader_parameter("night", v)


func set_wet(w: float) -> void:
	if material:
		material.set_shader_parameter("wet", w)


## The variant of `kind` whose size and floors best match a footprint `w` (front) × `d` (deep).
func pick(kind: String, floors: int, w: float, d: float) -> String:
	var best := ""
	var bs := INF
	for name in _by_kind.get(kind, []):
		var m: Dictionary = manifest[name]
		var bw: float = m["max"][0] - m["min"][0]
		var bd: float = m["max"][1] - m["min"][1]
		var score := absf(log(w / bw)) + absf(log(d / bd)) + absf(float(int(m["floors"]) - floors)) * 0.6
		if score < bs:
			bs = score
			best = name
	return best


## Footprint of a variant in Godot space (x across the front, z towards the front): [centre, size].
func extent(name: String) -> Array:
	var m: Dictionary = manifest[name]
	var mn: Array = m["min"]
	var mx: Array = m["max"]
	# Blender (x, y, z) → Godot (x, z, -y)
	var c := Vector3((mn[0] + mx[0]) * 0.5, 0.0, -(mn[1] + mx[1]) * 0.5)
	var s := Vector3(mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1])
	return [c, s]


func mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var path := DIR + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		found = (mi as MeshInstance3D).mesh
		break
	scene.free()
	if found == null:
		return null
	var m := found.duplicate() as ArrayMesh
	for i in m.get_surface_count():
		var sm := m.surface_get_material(i)
		var is_glass := sm != null and sm.resource_name.begins_with("KitGlass")
		m.surface_set_material(i, glass if is_glass else material)
	_meshes[name] = m
	return m
