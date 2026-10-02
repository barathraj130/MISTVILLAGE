extends RefCounted
## The Indian traffic fleet built in Blender by tools/fleet.py (hatchback, sedan, auto-rickshaw,
## city bus, lorry): loading, recolouring and caching, shared by parked cars, town and highway
## traffic. Paint follows real Indian roads: mostly white and silver.

const DIR := "res://assets/vehicles/fleet_%s.glb"
## game kind → fleet model
const MODEL := {"hatchback": "hatchback", "sedan": "sedan", "taxi": "sedan", "auto": "auto", "bus": "bus",
	"lorry": "lorry", "car": "hatchback"}
const CAR_PAINT := [[Color(0.86, 0.86, 0.84), 30], [Color(0.62, 0.63, 0.65), 18], [Color(0.32, 0.33, 0.35), 10],
	[Color(0.06, 0.06, 0.07), 9], [Color(0.55, 0.06, 0.05), 9], [Color(0.08, 0.18, 0.45), 8],
	[Color(0.38, 0.06, 0.1), 6], [Color(0.55, 0.42, 0.25), 5], [Color(0.75, 0.55, 0.1), 3]]
const BUS_PAINT := [Color(0.06, 0.2, 0.5), Color(0.55, 0.08, 0.06), Color(0.1, 0.35, 0.2), Color(0.85, 0.85, 0.82)]
const LORRY_PAINT := [Color(0.85, 0.42, 0.05), Color(0.9, 0.7, 0.05), Color(0.1, 0.3, 0.6), Color(0.6, 0.1, 0.08), Color(0.2, 0.45, 0.2)]

static var _scenes := {}
static var _mats := {}
static var _parts := {}


static func has(kind: String) -> bool:
	return MODEL.has(kind) and ResourceLoader.exists(DIR % MODEL[kind])


static func paint_for(kind: String, rng: RandomNumberGenerator) -> Color:
	match kind:
		"taxi":
			return Color(0.9, 0.72, 0.05) if rng.randf() < 0.5 else Color(0.88, 0.88, 0.86)
		"auto":
			return Color(0.1, 0.33, 0.12) if rng.randf() < 0.7 else Color(0.08, 0.08, 0.08)
		"bus":
			return BUS_PAINT[rng.randi() % BUS_PAINT.size()]
		"lorry":
			return LORRY_PAINT[rng.randi() % LORRY_PAINT.size()]
	var total := 0
	for p in CAR_PAINT:
		total += p[1]
	var r := rng.randi_range(1, total)
	for p in CAR_PAINT:
		r -= p[1]
		if r <= 0:
			return p[0]
	return CAR_PAINT[0][0]


## A recoloured model (wheels in place), +Z forward, standing on y = 0.
static func model(kind: String, paint: Color) -> Node3D:
	var path: String = DIR % MODEL[kind]
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var root := Node3D.new()
	var m := (_scenes[path] as PackedScene).instantiate() as Node3D
	m.rotation.y = -PI * 0.5                    # Blender +X nose → +Z
	root.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for s in inst.mesh.get_surface_count():
			var v := _variant(inst.mesh.surface_get_material(s), paint)
			if v:
				inst.set_surface_override_material(s, v)
	return root


## Recoloured paint, and lamps that don't glow by day (the glTF lamps are emissive).
static func _variant(mat: Material, paint: Color) -> Material:
	var bm := mat as BaseMaterial3D
	if bm == null:
		return null
	var nm := bm.resource_name
	if nm == "Paint":
		var key := "paint" + paint.to_html()
		if not _mats.has(key):
			var p := bm.duplicate() as BaseMaterial3D
			p.albedo_color = paint
			_mats[key] = p
		return _mats[key]
	if nm == "Headlight" or nm == "Taillight":
		if not _mats.has(nm):
			var l := bm.duplicate() as BaseMaterial3D
			l.emission_energy_multiplier = 0.15 if nm == "Taillight" else 0.0
			_mats[nm] = l
		return _mats[nm]
	if nm == "Glass":
		if not _mats.has("glass"):
			var g := bm.duplicate() as BaseMaterial3D
			g.albedo_color = Color(0.03, 0.035, 0.045)
			g.roughness = 0.05
			g.metallic_specular = 0.9
			_mats["glass"] = g
		return _mats["glass"]
	return null


## [Mesh, Transform3D] parts in car space with the paint baked in, for MultiMesh (parked cars).
static func parts(kind: String, paint: Color) -> Array:
	var key := kind + paint.to_html()
	if _parts.has(key):
		return _parts[key]
	var out: Array = []
	var root := model(kind, paint)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var mesh := inst.mesh.duplicate() as Mesh
		for s in mesh.get_surface_count():
			var o := inst.get_surface_override_material(s)
			if o:
				mesh.surface_set_material(s, o)
		var xf := Transform3D()
		var cur: Node = inst
		while cur and cur != root:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		out.append([mesh, xf])
	root.free()
	_parts[key] = out
	return out
