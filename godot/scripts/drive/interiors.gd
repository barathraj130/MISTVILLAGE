extends Node3D
## Walk-in places. Every named place with a parking lot (and every fuel bunk) gets a shopfront at
## the back of its lot: a lit doorway, a name board in the colour of its kind. On foot, walk up and
## press E to go in: you step into that kind of room (designed in Blender by
## tools/building_interiors.py), with someone working at the counter. E at the doorway brings you
## back out to the lot. Rooms are loaded only while you're inside, well below the street.

const MB := preload("res://scripts/drive/mesh_builder.gd")
const ROOMS := "res://assets/interiors/room_%s.glb"
const STAFF := "res://assets/people/person_%s.glb"
const KIND_ROOM := {"Restaurant": "restaurant", "Café": "tea", "Hotel": "hotel", "Guest House": "hotel",
	"Temple": "temple", "Hospital": "hospital", "Blood Bank": "hospital", "Bank": "bank", "Market": "kirana",
	"Petrol bunk": "fuel"}
const KIND_COLOUR := {"restaurant": Color(0.75, 0.2, 0.1), "tea": Color(0.6, 0.35, 0.1), "hotel": Color(0.15, 0.25, 0.55),
	"temple": Color(0.85, 0.45, 0.05), "hospital": Color(0.1, 0.55, 0.3), "bank": Color(0.1, 0.3, 0.6),
	"kirana": Color(0.8, 0.6, 0.05), "fuel": Color(0.15, 0.5, 0.3), "office": Color(0.35, 0.35, 0.4)}
const DEPTH := 300.0               # rooms sit this far below the street

var doors: Array = []              # {pos, out (unit, away from the shop), name, room}
var inside := {}                   # the door you came in by, while you're inside
var _room: Node3D
var _exit := Vector3.ZERO


func build(towns) -> void:
	var front := MB.new()
	var lit := MB.new()
	for tname in towns.data:
		for lot in towns.data[tname].get("parking", []):
			if lot["kind"] == "Parking":
				continue
			var P: Array = lot["poly"]
			var n := Vector3(lot["n"][0], 0, lot["n"][1])
			var t := Vector3(lot["t"][0], 0, lot["t"][1])
			var back := Vector3((P[2][0] + P[3][0]) * 0.5, float(lot["y"]), (P[2][1] + P[3][1]) * 0.5)
			var room: String = KIND_ROOM.get(lot["kind"], "office")
			_front(front, lit, back + n * 0.35, n, t, room, lot["name"])
			doors.append({"pos": back - n * 0.4, "out": -n, "name": lot["name"], "room": room})
	for b in towns.bunks:
		var p: Vector3 = b["pos"]
		doors.append({"pos": p + Vector3(0, 0, 0), "out": Vector3(0, 0, 1), "name": b["name"] + " store", "room": "fuel"})
	for pair in [[front, MB.vertex_color_material(0.8)], [lit, null]]:
		if pair[0].is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		if pair[1]:
			mi.material_override = pair[1]
		else:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.92, 0.75)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.85, 0.6)
			m.emission_energy_multiplier = 1.4
			mi.material_override = m
		mi.visibility_range_end = 300.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## A shopfront facing the lot: a wall with a lit doorway, a coloured name board above.
func _front(mb, lit, at: Vector3, n: Vector3, t: Vector3, room: String, name: String) -> void:
	var face := Basis(t, Vector3.UP, -n)          # local +Z points away from the lot (into the shop)
	var xf := Transform3D(face, at)
	var col: Color = KIND_COLOUR.get(room, Color(0.4, 0.4, 0.4))
	for sx in [-1.0, 1.0]:
		mb.box(xf * Transform3D(Basis(), Vector3(sx * 2.0, 1.7, 0)), Vector3(2.4, 3.4, 0.25), Color(0.85, 0.82, 0.74))
	mb.box(xf * Transform3D(Basis(), Vector3(0, 3.1, 0)), Vector3(1.6, 0.6, 0.25), Color(0.85, 0.82, 0.74))
	mb.box(xf * Transform3D(Basis(), Vector3(0, 3.75, -0.2)), Vector3(5.2, 0.8, 0.1), col)        # name board
	mb.box(xf * Transform3D(Basis(), Vector3(0, 0.08, -0.6)), Vector3(2.0, 0.16, 1.0), Color(0.6, 0.6, 0.58))   # step
	lit.box(xf * Transform3D(Basis(), Vector3(0, 1.4, 0.1)), Vector3(1.6, 2.8, 0.05), Color.WHITE)   # warm light inside
	var lbl := Label3D.new()
	lbl.text = name
	lbl.font_size = 56
	lbl.pixel_size = 0.006
	lbl.outline_size = 6
	lbl.modulate = Color(1, 0.97, 0.88)
	lbl.width = 800
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.transform = Transform3D(face.rotated(Vector3.UP, PI), xf * Vector3(0, 3.75, -0.27))
	lbl.visibility_range_end = 90.0
	add_child(lbl)


## The door you're standing at (on foot), or {}.
func door_near(p: Vector3) -> Dictionary:
	for d in doors:
		if Vector2(d["pos"].x - p.x, d["pos"].z - p.z).length() < 2.6 and absf(d["pos"].y - p.y) < 3.0:
			return d
	return {}


func at_exit(p: Vector3) -> bool:
	return not inside.is_empty() and p.distance_to(_exit) < 1.6


func enter(d: Dictionary, walker: Node3D) -> void:
	var path: String = ROOMS % d["room"]
	if not ResourceLoader.exists(path):
		return
	inside = d
	_room = (load(path) as PackedScene).instantiate() as Node3D
	_room.name = "Room"
	add_child(_room)
	_room.global_position = d["pos"] + Vector3(0, -DEPTH, 0)
	var body := StaticBody3D.new()
	_room.add_child(body)
	for mi in _room.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		cs.transform = _room.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		body.add_child(cs)
	var light := OmniLight3D.new()
	light.omni_range = 11.0
	light.light_energy = 0.9
	light.light_color = Color(1.0, 0.97, 0.9)
	light.position = Vector3(0, 2.9, 0)
	light.shadow_enabled = false
	_room.add_child(light)
	var entry := _room.find_child("Entry", true, false) as Node3D
	var ex := _room.find_child("Exit", true, false) as Node3D
	_exit = ex.global_position if ex else _room.global_position
	var staff := _room.find_child("Staff", true, false) as Node3D
	if staff:
		var who: String = ["man_shirt", "woman_kurta", "man_lungi", "woman_saree"][hash(d["name"]) % 4]
		if ResourceLoader.exists(STAFF % who):
			var npc := (load(STAFF % who) as PackedScene).instantiate() as Node3D
			_room.add_child(npc)
			npc.global_position = staff.global_position
			var to_door := (_exit - staff.global_position)
			npc.rotation.y = atan2(to_door.x, to_door.z)
			var ap := npc.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
			npc.ready.connect(func() -> void: ap.play("Idle"))
	var at: Vector3 = entry.global_position if entry else _room.global_position
	walker.global_position = at + Vector3(0, 0.1, 0)
	walker.velocity = Vector3.ZERO
	var look := _room.global_position - at
	walker.rotation.y = atan2(-look.x, -look.z)


func leave(walker: Node3D) -> void:
	if inside.is_empty():
		return
	var d := inside
	inside = {}
	if _room:
		_room.queue_free()
		_room = null
	walker.global_position = d["pos"] + d["out"] * 1.8 + Vector3(0, 0.3, 0)
	walker.velocity = Vector3.ZERO
	walker.rotation.y = atan2(-d["out"].x, -d["out"].z)
