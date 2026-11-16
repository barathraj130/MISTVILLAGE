extends Node3D
## Things in a room he can use on foot (story/interactables.json): sir's photo, the files on his desk, his own
## drawer, the light switch, small things he picks up and turns over (inspect). Walk up, face it, E. Played, not read: the camera comes close to the thing and his
## thought is a subtitle; a drawer slides out with what's in it; a switch puts the tube lights out. Nothing here is
## evidence (the story's own steps give that): it's what he notices, the room made solid.
##   attach(room, name, city, story)  one per room, from story.gd _load_room and city_doors.gd enter
##   offer(walker) → "the photo..."   what E would do where he stands ("" for nothing)
##   inspect   a small thing (model: tumbler, pen, file, key, phone; made here) on a desk: E lifts it smoothly to
##             in front of the close camera (never through it), the mouse dragged or WASD / the arrows turn it, E or
##             Esc puts it back exactly where it lay (nothing is taken: the story's own steps give things)
##   drawer    slides out along its runners with a wooden sound; if something stands in front of it (a chair, a
##             person) it only knocks against it: "(Something's in the way.)"
##   go(walker)                       do it
## Seen things are remembered as story flags ("seen_<id>") when there's a story.
##   --interacttest  testing: in the first room that has things, every one used in turn, a picture of each
##                   (user://interact_<id>.jpg)
const DATA := "res://story/interactables.json"
const FACING := 0.25                 # how nearly he must face it (the dot of his facing and the way to it)

var city
var story
var lang := "en"
var items: Array = []
var busy := false                    # the close camera is on: the walker waits
var _room: Node3D
var _open := {}                      # drawer id → its node, while it's out
var _drawers := {}                   # drawer id → its node
var _lights_on := true
var _cam: Camera3D
var _was: Camera3D
var _hold := 0.0
var _e_was := true
var _test := -1
var _held: Node3D                    # the thing in his hands, inspected
var _held_home := Transform3D()
var _things := {}                    # inspect id → its node


static func attach(room: Node3D, name: String, city_ref, story_ref) -> Node3D:
	if not FileAccess.file_exists(DATA):
		return null
	var all = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not all is Dictionary or not all.has(name):
		return null
	var n: Node3D = load("res://scripts/story/interactable.gd").new()
	n.name = "Interact"
	n.city = city_ref
	n.story = story_ref
	n._room = room
	n.items = all[name]
	room.add_child(n)
	n._build()
	return n


## A point in the room's Blender coordinates (x right, y back, z up), in the world.
func _w(v: Array) -> Vector3:
	return _room.global_transform * Vector3(float(v[0]), float(v[2]), -float(v[1]))


## A direction in the room's Blender axes, in the world.
func _wd(v: Array) -> Vector3:
	return _room.global_basis * Vector3(float(v[0]), float(v[2]), -float(v[1]))


func _tr(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func _build() -> void:
	for it in items:
		match str(it["kind"]):
			"drawer":
				_drawers[it["id"]] = _drawer(it)
			"switch":
				_switch(it)
			"inspect":
				_things[it["id"]] = _thing(it)
	if "--interacttest" in OS.get_cmdline_user_args():
		_test = 0


## A drawer under the desk top: a wooden box with a steel pull, its things lying in it.
func _drawer(it: Dictionary) -> Node3D:
	var s: Array = it.get("size", [0.42, 0.5, 0.12])
	var root := Node3D.new()
	root.name = "Drawer_" + str(it["id"])
	add_child(root)
	root.global_transform = Transform3D(_room.global_basis.rotated(_room.global_basis.y.normalized(), float(it.get("yaw", 0.0))), _w(it["at"]))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.45, 0.32)
	wood.roughness = 0.6
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.42, 0.33, 0.22)
	inner.roughness = 0.8
	var w := float(s[0])
	var d := float(s[1])
	var h := float(s[2])
	var t := 0.012
	# (in the room's Godot axes: x right, y up, z = −Blender y; the front faces Blender +y, Godot −z)
	_slab(root, Vector3(w, t, d), Vector3(0, -h / 2 + t / 2, 0), inner)                  # bottom
	_slab(root, Vector3(t, h, d), Vector3(-w / 2 + t / 2, 0, 0), inner)                  # sides
	_slab(root, Vector3(t, h, d), Vector3(w / 2 - t / 2, 0, 0), inner)
	_slab(root, Vector3(w, h, t), Vector3(0, 0, d / 2 - t / 2), inner)                   # back
	_slab(root, Vector3(w + 0.02, h + 0.02, 0.018), Vector3(0, 0, -d / 2 - 0.009), wood)  # the front
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.76, 0.78)
	steel.metallic = 0.8
	steel.roughness = 0.3
	_slab(root, Vector3(0.12, 0.018, 0.02), Vector3(0, 0.01, -d / 2 - 0.03), steel)       # the pull
	for th in it.get("inside", []):
		var sz: Array = th["size"]
		var m := StandardMaterial3D.new()
		m.roughness = 0.85
		var thick := 0.003
		match str(th["what"]):
			"letter":
				m.albedo_color = Color(0.95, 0.94, 0.9)
				m.albedo_texture = _letter_tex()
			"notebook":
				m.albedo_color = Color(0.16, 0.24, 0.45)
				thick = 0.014
			_:
				m.albedo_color = Color(0.8, 0.8, 0.8)
		var p := _slab(root, Vector3(float(sz[0]), thick, float(sz[1])),
			Vector3(float(th["at"][0]), -h / 2 + t + thick / 2 + 0.001, -float(th["at"][1])), m)
		p.rotation.y = float(th.get("turn", 0.0))
	root.set_meta("closed", root.position)
	return root


## A small thing lying where it is ("at": its foot on the surface), made of a few simple shapes.
func _thing(it: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Thing_" + str(it["id"])
	add_child(root)
	root.global_transform = Transform3D(_room.global_basis.rotated(_room.global_basis.y.normalized(), float(it.get("yaw", 0.0))), _w(it["at"]))
	var m := StandardMaterial3D.new()
	m.roughness = 0.6
	match str(it.get("model", "")):
		"tumbler":                                      # a steel tumbler, a little tea in it
			m.albedo_color = Color(0.86, 0.87, 0.89)         # (brushed steel: light, not a black mirror of the room)
			m.metallic = 0.25
			m.roughness = 0.35
			var c := CylinderMesh.new()
			c.top_radius = 0.036
			c.bottom_radius = 0.03
			c.height = 0.11
			var mi := MeshInstance3D.new()
			mi.mesh = c
			mi.material_override = m
			mi.position.y = 0.055
			root.add_child(mi)
			var tea := StandardMaterial3D.new()
			tea.albedo_color = Color(0.55, 0.36, 0.2)
			var t := CylinderMesh.new()
			t.top_radius = 0.032
			t.bottom_radius = 0.032
			t.height = 0.004
			var ti := MeshInstance3D.new()
			ti.mesh = t
			ti.material_override = tea
			ti.position.y = 0.075
			root.add_child(ti)
		"pen":
			m.albedo_color = Color(0.12, 0.2, 0.6)
			var c2 := CylinderMesh.new()
			c2.top_radius = 0.004
			c2.bottom_radius = 0.004
			c2.height = 0.145
			var mi2 := MeshInstance3D.new()
			mi2.mesh = c2
			mi2.material_override = m
			mi2.rotation.z = PI * 0.5
			mi2.position.y = 0.004
			root.add_child(mi2)
		"file":                                         # slips clipped in a khaki file cover
			m.albedo_color = Color(0.72, 0.6, 0.38)
			_slab(root, Vector3(0.24, 0.006, 0.32), Vector3(0, 0.003, 0), m)
			var paper := StandardMaterial3D.new()
			paper.albedo_color = Color(0.95, 0.94, 0.9)
			paper.albedo_texture = _letter_tex()
			_slab(root, Vector3(0.21, 0.004, 0.29), Vector3(0, 0.008, 0), paper)
			var clip := StandardMaterial3D.new()
			clip.albedo_color = Color(0.2, 0.2, 0.22)
			clip.metallic = 0.7
			_slab(root, Vector3(0.06, 0.008, 0.03), Vector3(0, 0.012, -0.13), clip)
		"key":
			m.albedo_color = Color(0.78, 0.62, 0.3)
			m.metallic = 0.85
			m.roughness = 0.3
			_slab(root, Vector3(0.012, 0.003, 0.055), Vector3(0, 0.002, 0.02), m)
			var bow := CylinderMesh.new()
			bow.top_radius = 0.014
			bow.bottom_radius = 0.014
			bow.height = 0.003
			var bi := MeshInstance3D.new()
			bi.mesh = bow
			bi.material_override = m
			bi.position = Vector3(0, 0.002, -0.015)
			root.add_child(bi)
		_:                                              # a phone, face down
			m.albedo_color = Color(0.05, 0.05, 0.06)
			_slab(root, Vector3(0.075, 0.009, 0.155), Vector3(0, 0.0045, 0), m)
	return root


## A drawer's runners: a wooden slide, made here (a rumble of noise, softer as it ends).
func _slide_sound(at: Vector3, out: bool) -> void:
	var p := AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.5
	p.stream = gen
	p.unit_size = 2.0
	p.volume_db = -8.0
	add_child(p)
	p.global_position = at
	p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		var n := int(22050 * (0.32 if out else 0.26))
		var lp := 0.0
		for i in n:
			var u := float(i) / n
			var env := sin(PI * minf(u * 1.4, 1.0)) * (1.0 - u * 0.5)
			lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)       # (low-passed: wood, not hiss)
			var a := lp * env * 0.7 + (0.5 if u > 0.93 and not out else 0.0) * randf_range(-1.0, 1.0) * exp(-(u - 0.93) * 60.0)
			pb.push_frame(Vector2(a, a))
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


## Is there something in front of the drawer, within its travel (a chair pushed against the desk, a person)?
func _blocked(dr: Node3D, travel: float) -> bool:
	var fwd := -dr.global_basis.z.normalized()
	var s: Array = []
	for it in items:
		if _drawers.get(it["id"]) == dr:
			s = it.get("size", [0.42, 0.5, 0.12])
	var front := dr.global_position + fwd * (float(s[1]) * 0.5 + 0.03 if not s.is_empty() else 0.28)
	var q := PhysicsRayQueryParameters3D.create(front, front + fwd * (travel + 0.03))
	var ex: Array[RID] = []
	if city and city.walker:
		ex.append((city.walker as CollisionObject3D).get_rid())
	q.exclude = ex
	return not dr.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _slab(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi


## The fee letter: a printed letterhead, lines of type and a boxed amount (made here, not a picture from outside).
func _letter_tex() -> ImageTexture:
	var img := Image.create(128, 168, false, Image.FORMAT_RGB8)
	img.fill(Color(0.96, 0.95, 0.91))
	img.fill_rect(Rect2i(10, 8, 108, 14), Color(0.15, 0.25, 0.5))         # the college's letterhead
	for k in range(12):
		var n := 96 - (k * 23) % 40
		img.fill_rect(Rect2i(12, 34 + k * 9, n, 2), Color(0.3, 0.3, 0.32))
	img.fill_rect(Rect2i(66, 146, 50, 12), Color(0.75, 0.15, 0.12))       # the amount, boxed in red
	img.fill_rect(Rect2i(68, 148, 46, 8), Color(0.96, 0.95, 0.91))
	img.fill_rect(Rect2i(72, 151, 36, 2), Color(0.3, 0.3, 0.32))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A light switch plate by the door: the board of a Coimbatore office, two white rockers.
func _switch(it: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Switch_" + str(it["id"])
	add_child(root)
	root.global_transform = Transform3D(_room.global_basis, _w(it["at"]))
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.94, 0.92)
	white.roughness = 0.35
	_slab(root, Vector3(0.16, 0.1, 0.015), Vector3.ZERO, white)
	for k in [-1, 1]:
		var r := _slab(root, Vector3(0.03, 0.05, 0.012), Vector3(k * 0.035, 0, -0.012), white)
		r.name = "Rocker"
		r.rotation.x = 0.12


func _tubes() -> Array:
	var out := []
	for e in _room.find_children("Light_tube*", "", true, false):
		for c in e.get_children():
			if c is OmniLight3D:
				out.append(c)
	return out


func _set_lights(on: bool) -> void:
	_lights_on = on
	for l in _tubes():
		(l as OmniLight3D).visible = on
	for mi in _room.find_children("*", "MeshInstance3D", true, false):   # the ceiling panels' glow
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat and mat.resource_name.begins_with("panel_light"):
				if on:
					m.set_surface_override_material(i, null)
				else:
					var dark := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dark.emission_enabled = false
					dark.albedo_color = Color(0.55, 0.55, 0.55)
					m.set_surface_override_material(i, dark)
	for r in find_children("Rocker", "", true, false):
		(r as Node3D).rotation.x = 0.12 if on else -0.12


func _ok(it: Dictionary) -> bool:
	var flags: Dictionary = story.flags if story and "flags" in story else {}
	if it.has("when") and not flags.get(str(it["when"]), false):
		return false
	if it.has("unless") and flags.get(str(it["unless"]), false):
		return false
	return true


## The thing he's at and facing, if any.
func _at(w: Node3D) -> Dictionary:
	var best := {}
	var bd := INF
	var fwd := -w.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for it in items:
		if not _ok(it):
			continue
		var p := _w(it["at"])
		if _open.has(it["id"]):
			p = (_open[it["id"]] as Node3D).global_position
		var to := Vector3(p.x - w.global_position.x, 0.0, p.z - w.global_position.z)
		var d := to.length()
		var dot := fwd.dot(to / d) if d > 0.001 else 1.0
		if d > float(it.get("reach", 1.2)) or (d > 0.3 and dot < FACING):
			continue
		var score := d * 0.4 + (1.0 - dot) * 3.0          # (the one he's looking at, not only the nearest: things
		if score < bd:                                   #  side by side on a desk)
			bd = score
			best = it
	return best


func offer(w: Node3D) -> String:
	if busy or w == null:
		return ""
	var it := _at(w)
	if it.is_empty():
		return ""
	if str(it["kind"]) == "drawer" and _open.has(it["id"]):
		return _tr(it.get("shut", {"en": "shut it", "ta": "மூடு"}))
	if str(it["kind"]) == "switch":
		return _tr(it["prompt"]) + ((" off" if lang == "en" else " ஆஃப்") if _lights_on else (" on" if lang == "en" else " ஆன்"))
	return _tr(it["prompt"])


func go(w: Node3D) -> void:
	var it := _at(w)
	if it.is_empty() or busy:
		return
	var kind := str(it["kind"])                          # his hand to it first: the drawer's pull, the switch, the
	var at := _w(it["at"])
	if kind in ["drawer", "switch", "locked"] and w.has_method("reach") and float(it["at"][2]) > 0.8:   #  almirah's
		# (a low drawer, under a desk, is pulled without a reach: standing, his hand can't get down to it)
		if kind == "drawer":
			var dr: Node3D = _drawers[it["id"]]
			at = dr.global_position - dr.global_basis.z * (float(it.get("size", [0, 0.5])[1]) * 0.5 + 0.05)
		busy = true
		await w.reach(at, "point" if kind == "switch" else "open", 0.25)
		busy = false
	_use(it, w)


func _use(it: Dictionary, w: Node3D) -> void:
	var soc = city.doors.social if city and "doors" in city and city.doors and "social" in city.doors else null
	if soc and is_instance_valid(soc) and str(it["kind"]) in ["drawer", "locked"] or (soc and is_instance_valid(soc) and it.get("private", false)):
		soc.act("search", _w(it["at"]))                  # (opening what isn't his, with people about: social.gd)
	match str(it["kind"]):
		"switch":
			_set_lights(not _lights_on)
			_click()
			return
		"locked":
			_think(it)
			return
		"drawer":
			var dr: Node3D = _drawers[it["id"]]
			var closed: Vector3 = dr.get_meta("closed")
			if _open.has(it["id"]):
				_open.erase(it["id"])
				create_tween().tween_property(dr, "position", closed, 0.35).set_trans(Tween.TRANS_SINE)
				_slide_sound(dr.global_position, false)
				return
			var out: Array = it.get("out", [0, 0.3, 0])
			var to := closed + Vector3(float(out[0]), float(out[2]), -float(out[1]))
			if _blocked(dr, (to - closed).length()):         # (it would open into something: a knock, no more)
				var bump := closed + (to - closed).normalized() * 0.02
				var tb := create_tween()
				tb.tween_property(dr, "position", bump, 0.06)
				tb.tween_property(dr, "position", closed, 0.1)
				_think({"line": {"en": "(Something's in the way.)", "ta": "(ஏதோ இடைஞ்சலா இருக்கு.)"}})
				return
			_open[it["id"]] = dr
			create_tween().tween_property(dr, "position", to, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_slide_sound(dr.global_position, true)
			_close_look(_room.global_transform * to, it, w, 0.45)
		"inspect":                                       # picked up: brought up before his eyes, to turn over
			var th: Node3D = _things[it["id"]]
			_close_look(th.global_position, it, w, 0.0)
			_hold = 60.0
			_held = th
			_held_home = th.global_transform
			var look_from: Vector3 = th.global_position + _wd(it.get("view", [0, -0.6, 0.2]))   # (where the close camera ends up)
			var eye := Transform3D(Basis.looking_at(th.global_position - look_from, Vector3.UP), look_from)
			await get_tree().create_timer(0.25).timeout
			if _held == th and _cam and is_instance_valid(_cam):
				var to2 := Transform3D(th.global_basis, eye.origin - eye.basis.z * float(it.get("near", 0.34)) - eye.basis.y * 0.02)
				var tw := create_tween()
				tw.tween_method(func(k: float):
					if _held == th:
						th.global_transform = _held_home.interpolate_with(to2, k), 0.0, 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_:
			_close_look(_w(it["at"]), it, w, 0.0)
	_think(it)
	if story and "flags" in story:
		story.flags["seen_" + str(it["id"])] = true


## His thought, as the story's subtitles show a line (its box, his name in his colour); in free play the HUD's.
func _think(it: Dictionary) -> void:
	if not it.has("line"):
		return
	var name := "Karthik" if lang == "en" else "கார்த்திக்"
	if story and "box" in story and story.box:
		var p: Dictionary = story.data["people"].get("karthik", {}) if "data" in story else {}
		story.who.text = story.tr_(p) if not p.is_empty() else name
		story.who.add_theme_color_override("font_color", Color.html(str(p.get("colour", "#ffffff"))))
		story.said.text = _tr(it["line"])
		story.hint.text = ""
		story.box.visible = true
		_boxed = true
		_said += 1
		if not busy:                                    # (a locked almirah: no close look, the line a while)
			var n := _said
			get_tree().create_timer(3.5).timeout.connect(func(): if n == _said: _unbox())
	elif city and city.hud:
		city.hud.say(name, _tr(it["line"]), 4.5)


var _boxed := false
var _said := 0                       # (a later line's box isn't put away by an earlier one's timer)


func _unbox() -> void:
	if _boxed and story and story.box:
		story.box.visible = false
	_boxed = false


func _click() -> void:
	var p := AudioStreamPlayer3D.new()               # a rocker's click: a few milliseconds of noise, made here
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	p.stream = gen
	p.unit_size = 2.0
	add_child(p)
	p.global_position = city.walker.global_position if city and city.walker else global_position
	p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		for i in 260:
			var a := randf_range(-1.0, 1.0) * exp(-float(i) / 40.0) * 0.6
			pb.push_frame(Vector2(a, a))
	get_tree().create_timer(0.5).timeout.connect(p.queue_free)


## The camera comes close to the thing (from "view", in the room's axes) and holds while he looks; E, Esc or a few
## seconds give him back.
func _close_look(p: Vector3, it: Dictionary, w: Node3D, delay: float) -> void:
	busy = true
	_hold = 4.5
	_e_was = true
	_was = get_viewport().get_camera_3d()
	if "active" in w:
		w.active = false
	if "velocity" in w:
		w.velocity = Vector3.ZERO
	if "model" in w and w.model:                     # (his own shoulder would be in the way, close up)
		w.model.visible = false
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.02
	if _was:
		_cam.environment = _was.environment
		_cam.attributes = _was.attributes
	add_child(_cam)
	var from := p + _wd(it.get("view", [0, -0.6, 0.2]))
	var start: Vector3 = _was.global_position if _was else from
	_cam.global_position = start
	_cam.look_at_from_position(start, p, Vector3.UP)
	_cam.make_current()
	var tw := create_tween()
	tw.tween_interval(delay * 0.3)
	tw.tween_method(func(k: float):
		if _cam == null or not is_instance_valid(_cam):
			return
		var q := start.lerp(from, k)
		_cam.look_at_from_position(q, p, Vector3.UP), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _back() -> void:
	busy = false
	_unbox()
	if _held and is_instance_valid(_held):               # (put back exactly where it lay)
		var th := _held
		var from := th.global_transform
		var home := _held_home
		_held = null
		create_tween().tween_method(func(k: float):
			if is_instance_valid(th):
				th.global_transform = from.interpolate_with(home, k), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	if _cam:
		_cam.queue_free()
		_cam = null
	if _was and is_instance_valid(_was):
		_was.make_current()
	if city and city.walker:
		city.walker.active = true
		if city.walker.model:
			city.walker.model.visible = true


func _process(dt: float) -> void:
	if story and "lang" in story:
		lang = str(story.lang)
	if busy:
		_hold -= dt
		if _held and is_instance_valid(_held) and _cam and is_instance_valid(_cam):   # (turning it over in his hands)
			var yaw := (float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))) * 2.2 * dt
			var pitch := (float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))) * 2.2 * dt
			yaw += _drag_turn.x
			pitch += _drag_turn.y
			_drag_turn = Vector2.ZERO
			if yaw != 0.0 or pitch != 0.0:
				var b := _held.global_basis
				b = Basis(_cam.global_basis.y, yaw) * b
				b = Basis(_cam.global_basis.x, pitch) * b
				_held.global_basis = b.orthonormalized()
		var e := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_ESCAPE)
		if (e and not _e_was and _hold < 4.0) or _hold <= 0.0:
			_back()
		_e_was = e
		return
	if _test >= 0:
		_run_test(dt)


var _drag_turn := Vector2.ZERO


func _input(ev: InputEvent) -> void:
	if busy and _held and ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_turn += Vector2(ev.relative.x, ev.relative.y) * 0.01   # (the mouse held and moved: it turns)


# ---- testing ----
var _tt := 0.0
var _testing := false


func _run_test(dt: float) -> void:
	var w: Node3D = city.walker if city else null
	if w == null or _testing:
		return
	_tt += dt
	if _tt < 1.5:
		return
	_tt = 0.0
	if _test >= items.size():
		print("INTERACT test done: %d things" % items.size())
		_test = -2
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
		return
	_testing = true
	var it: Dictionary = items[_test]
	var p := _w(it["at"])
	var v := _wd(it.get("view", [0, -0.8, 0]))
	v.y = 0.0
	var stand := p + v.normalized() * minf(float(it.get("reach", 1.2)) * 0.7, 0.9)
	stand.y = _room.global_position.y + 0.1
	if w.has_method("spawn_at"):
		w.spawn_at(stand, Vector3(p.x, stand.y + 1.0, p.z))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var o := offer(w)
	print("INTERACT %s: offer '%s' at %s (stand %s, thing %s)" % [it["id"], o, str(w.global_position), str(stand), str(p)])
	if o != "":
		go(w)
	if str(it["kind"]) in ["drawer", "switch", "locked"]:   # (his hand on it: a picture from beside him)
		await get_tree().create_timer(0.42).timeout
		var r = w.get("hand_reach")
		if r:
			var hb: int = r.sk.find_bone("hand_" + r._side)
			var hp: Vector3 = r.sk.global_transform * r.sk.get_bone_global_pose(hb).origin
			print("INTERACT   reach %s hand: weight %.2f, the wrist %.2f m from where it's going (target %.2f m from the shoulder)" % [r._side,
				r.ik.weight, r.ik.error, (r.sk.global_transform * r.sk.get_bone_global_pose(r.sk.find_bone("upperarm_" + r._side)).origin).distance_to(r.ik.target)])
			var cam := Camera3D.new()                    # (from his side, wherever the room leaves space)
			add_child(cam)
			var model: Node3D = w.get("model")
			var fwd: Vector3 = model.global_basis.z
			var rt: Vector3 = -model.global_basis.x
			var eye := w.global_position + Vector3.UP * 1.2
			for c in [rt * 1.4 + fwd * 0.4, -rt * 1.4 + fwd * 0.4, rt * 1.0 - fwd * 0.6, -rt * 1.0 - fwd * 0.6]:
				var q := PhysicsRayQueryParameters3D.create(eye, eye + c)
				q.exclude = [(w as CollisionObject3D).get_rid()]
				if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					cam.global_position = eye + c
					break
			cam.look_at(hp.lerp(eye, 0.3), Vector3.UP)
			var was := get_viewport().get_camera_3d()
			cam.make_current()
			await _snap("interact_%s_reach" % it["id"])
			if was:
				was.make_current()
			cam.queue_free()
	await get_tree().create_timer(1.1).timeout
	var cc := get_viewport().get_camera_3d()
	print("INTERACT   camera %s at %s busy %s; walker cam at %s" % [cc.name if cc else "-", str(cc.global_position) if cc else "", busy, str(w.camera.global_position)])
	await _snap("interact_" + str(it["id"]))
	if str(it["kind"]) == "switch":                 # (and back on)
		await get_tree().create_timer(0.3).timeout
		_set_lights(true)
	if busy:
		_back()
	_test += 1
	_testing = false


func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % n), 0.85)
