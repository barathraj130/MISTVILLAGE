extends RefCounted
## The living Sketchfab people (tools/sketchfab_living.py: sfa_<name>.glb): real-looking people on the game's bones
## with the game's clips (their own Idle, Talk, Walk... and the gestures, crowd_clips.gd's "crowd/..." the same clips)
## and a face (face.gd's units). Each stands in near Karthik for its still figure far off (sf_<name>.glb in the street's
## crowd, city_streamer.gd SF_PEOPLE), the same person; a saree woman also comes in colours (sfa_<name>_t<i>.jpg: her
## texture with the saree's hues turned; the far figure "sf_<name>@<i>" wears the same).
##   names()             the ones built
##   make(name, tint)    one, ready: clips looping, in that colour (0: as made)
##   tints(name)         its colours (1, 2, ...)
##   living(kind)        the living name for a far figure's kind name ("sf_woman_saree_yellow@2" → that, 2), or ""

const PEOPLE := {"woman_saree_yellow": "w", "woman_saree_pink": "w", "woman_saree_green": "w", "woman_office": "w",
	"woman_office2": "w", "man_kurta_blue": "m", "man_kurta_red": "m", "man_suit": "m", "man_office": "m",
	"man_old_coat": "m"}
const PATH := "res://assets/people/sfa_%s.glb"
const TINT := "res://assets/people/sfa_%s_t%d.jpg"

static var _scenes := {}
static var _tints := {}


static func names() -> Array:
	return PEOPLE.keys().filter(func(n): return ResourceLoader.exists(PATH % n))


static func sex(name: String) -> String:
	return PEOPLE.get(name, "m")


static func tints(name: String) -> Array:
	if not _tints.has(name):
		var t := []
		for i in range(0, 8):
			if ResourceLoader.exists(TINT % [name, i]):
				t.append(i + 1)
		_tints[name] = t
	return _tints[name]


static func living(kind: String) -> Array:
	if not kind.begins_with("sf_"):
		return ["", 0]
	var nm := kind.substr(3).get_slice("@", 0)
	var t := int(kind.get_slice("@", 1)) if kind.contains("@") else 0
	if PEOPLE.has(nm) and ResourceLoader.exists(PATH % nm):
		return [nm, t]
	return ["", 0]


static func make(name: String, tint := 0) -> Node3D:
	if not ResourceLoader.exists(PATH % name):
		return null
	if not _scenes.has(name):
		_scenes[name] = load(PATH % name)
	var n := (_scenes[name] as PackedScene).instantiate() as Node3D
	for a in n.find_children("*", "AnimationPlayer", true, false):
		for clip in (a as AnimationPlayer).get_animation_list():
			(a as AnimationPlayer).get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if tint > 0:
		retexture(n, load(TINT % [name, tint - 1]) as Texture2D)
	n.set_meta("sex", sex(name))
	n.set_meta("living", name)
	return n


## Every textured material of a model given another texture (a colour variant: the same layout, other hues).
static func retexture(model: Node, tex: Texture2D) -> void:
	if tex == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for i in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(i)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_texture = tex
				m3.set_surface_override_material(i, dup)
