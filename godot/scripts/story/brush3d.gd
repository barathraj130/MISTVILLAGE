extends Node3D
## Brushing his teeth in the bathroom at home, in 3D (docs/MORNING_ROUTINE_AUDIT.md, plan B): Karthik himself at the
## shelf under the mirror, the camera close by the mirror, and you doing it with the mouse on the real things:
##   1  drag his brush from the shelf to him: he reaches out and takes it (Reach, then BrushHold)
##   2  drag the paste tube onto the brush's head: a line of paste squeezes out along it
##   3  hold the mouse button on his mouth and scrub left and right: he brushes (Brush, its speed your hand's),
##      foam comes, and each side (his right, the front, his left) fills as you brush it
##   4  drag the tumbler to him: he takes a mouthful, gargles and spits into the drain (Rinse)
##   5  he puts the brush back in the cup and the tumbler on the shelf; the camera goes back to the walk
## His clips are tools/humans/story_morning.py's (story_karthik_morning.glb), added to his own AnimationPlayer.
## tasks.gd hands the "brush" chore over to it (begin) and goes on when it says `finished`. --storyskip plays it
## by itself (and saves pictures into --storyshots).

signal finished

const MORNING := "res://assets/people/story_karthik_morning.glb"
const Style := preload("res://scripts/ui/hud_style.gd")
const Face := preload("res://scripts/story/face.gd")
# the bathroom in the home room's own frame (tools/story_rooms.py bathroom(): Blender (x, y, z) → (x, z, -y))
const STAND := Vector3(-5.07, 0.0, 0.14)               # facing the mirror (-Z), the shelf in front
const SHELF_Y := 1.262
const CUP := Vector3(-4.95, SHELF_Y, -0.3)             # the toothbrush cup (baked into the room)
const BRUSH_HOME := Vector3(-4.86, SHELF_Y + 0.008, -0.27)
const TUBE_HOME := Vector3(-5.12, SHELF_Y + 0.018, -0.25)
const TUMBLER_HOME := Vector3(-4.78, SHELF_Y, -0.29)
# the camera: over the shelf and his hand (taking the brush, the paste), then his face from his front right
const SHOTS := {"shelf": [Vector3(-4.42, 2.02, 0.42), Vector3(-4.98, 1.45, -0.2)],
	"face": [Vector3(-5.13, 1.76, -0.72), Vector3(-5.03, 1.66, 0.06)]}   # (from beyond the mirror wall: the near
const FACE_NEAR := 0.44                                                  # plane cuts the wall and glass away)
# the palette of the morning screens: cream, charcoal, forest green, wood
const CREAM := Color(0.96, 0.93, 0.86, 0.96)
const CHARCOAL := Color(0.16, 0.16, 0.17)
const FOREST := Color(0.23, 0.45, 0.3)
const WOOD := Color(0.55, 0.38, 0.24)

var city: Node
var story: Node                                        # (story.gd: its room, its step)
var lang := "en"
var skip := false
var shots := ""
var stage := ""                                        # take, paste, scrub, rinse, putback, done
var room: Node3D
var walker: Node3D
var model: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var cam: Camera3D
var _from_cam: Camera3D
var _cam_t := 0.0
var _cam_from := Transform3D.IDENTITY
var _shot_name := "shelf"
var held := {}                                         # thing → "r" or "l": in that hand, placed every frame
var _grip_t := {}                                      # thing → 0–1 on its way into the hand
var _grip_from := {}
var brush: Node3D
var paste: MeshInstance3D
var tube: Node3D
var tumbler: Node3D
var _lip_foam: MeshInstance3D
var _foam_mat: StandardMaterial3D
var _bubbles: GPUParticles3D
var _phase := 0.0                                      # brushing strokes made (your hand's, or slowly by himself)
var _zone := 0.0                                       # where the brush is: -1 his right … 0 front … 1 his left
var _zone_want := 0.0
var _anim_mode := 0
var _snd: AudioStreamPlayer3D
var _snd_pb: AudioStreamGeneratorPlayback
var _lp := 0.0
var _face: Face
var _teeth_local := Vector3.ZERO                       # his front teeth in the head bone's frame (from the teeth mesh)
var _hp := 0.0
var _drag: Node3D = null
var _drag_depth := 0.0
var _scrubbing := false
var _last_mouse := Vector2.ZERO
var _speed := 0.0                                      # scrub speed, px a second, smoothed
var sides := [0.0, 0.0, 0.0]                           # his right, front, his left: 0–1 each
var _t := 0.0
var _say := ""
var _ui: Control
var _layer: CanvasLayer
var _paste_k := 0.0
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _mirror_quad: MeshInstance3D
const MIRROR_C := Vector3(-5.03, 1.6, -0.333)          # the mirror over the shelf: its face, 0.36 × 0.45 m, facing +Z
const MIRROR_SIZE := Vector2(0.36, 0.45)


func can(chore: String) -> bool:
	return chore == "brush" and ResourceLoader.exists(MORNING) and story != null and story.room != null \
		and str(story.cur.get("room", "")) == "home" and city != null and city.walker != null and city.walker.model != null


func begin(chore: String) -> void:
	room = story.room
	walker = city.walker
	model = walker.model
	anim = walker.anim
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_add_clips()
	_face = Face.new(model)
	_find_teeth()
	_anim_mode = anim.callback_mode_process
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # (we advance it: then the head
	walker.deactivate()                                 # and the brush are set after it, every frame)
	walker.set("scripted", true)
	walker.global_position = _w(STAND)
	model.global_rotation = Vector3(0.0, room.global_rotation.y + PI, 0.0)
	anim.play("Idle", 0.3)
	_props()
	_mirror()
	_from_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.03
	add_child(cam)
	if _from_cam:
		cam.global_transform = _from_cam.global_transform
	cam.make_current()
	_cam_t = 0.0
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_stage("take")


## The mirror over the shelf, a real one: a camera behind it, reflected from ours, sees the room through its frame
## (an off-axis frustum on the mirror's rectangle) into a small picture, shown flipped on the glass. Only while it's
## in shot.
func _mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(288, 360)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mirror_vp.world_3d = get_viewport().world_3d
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_mirror_vp.add_child(_mirror_cam)
	var q := QuadMesh.new()
	q.size = MIRROR_SIZE + Vector2(0.012, 0.012)         # (over the baked glass's edge)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _mirror_vp.get_texture()
	m.uv1_scale = Vector3(-1, 1, 1)                     # (a mirror turns left and right about)
	m.uv1_offset = Vector3(1, 0, 0)
	m.albedo_color = Color(0.93, 0.95, 0.96)
	_mirror_quad = MeshInstance3D.new()
	_mirror_quad.mesh = q
	_mirror_quad.material_override = m
	_mirror_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mirror_quad.layers = 1 << 19
	add_child(_mirror_quad)
	_mirror_quad.global_transform = Transform3D(room.global_basis, _w(MIRROR_C))
	_mirror_cam.cull_mask = 0xFFFFF & ~(1 << 19)


func _update_mirror() -> void:
	if _mirror_cam == null or cam == null:
		return
	var n := room.global_basis.z.normalized()           # the mirror's face, into the bathroom
	var c := _w(MIRROR_C)
	var d := (cam.global_position - c).dot(n)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if d > 0.0 and _shot_name == "shelf" else SubViewport.UPDATE_DISABLED
	if d <= 0.0:
		return
	var eye := cam.global_position - n * 2.0 * d       # our camera seen in the mirror: as far behind the glass
	var right := room.global_basis.x.normalized()
	var up := room.global_basis.y.normalized()
	_mirror_cam.global_transform = Transform3D(Basis(-right, up, -n), eye)   # looking out through the glass, into the room
	var off := c - eye                                   # the mirror's centre in that camera's frame (its x is -right)
	_mirror_cam.set_frustum(MIRROR_SIZE.y, Vector2(-off.dot(right), off.dot(up)), d, 8.0)


func _w(local: Vector3) -> Vector3:                    # a point of the room to the world
	return room.global_transform * local


func _add_clips() -> void:
	if anim.has_animation_library("morning"):
		return
	var src := (load(MORNING) as PackedScene).instantiate()
	var ap := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var lib := AnimationLibrary.new()
	for n in ap.get_animation_list():
		var a := ap.get_animation(n).duplicate() as Animation
		a.loop_mode = Animation.LOOP_NONE if n == "Rinse" else Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	anim.add_animation_library("morning", lib)
	src.free()


# ---- the things on the shelf ----

func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _props() -> void:
	# the brush: 17.5 cm along its own +X, the bristles at the far end facing +Y
	brush = Node3D.new()
	add_child(brush)
	var pm0 := _mat(Color(1, 1, 1), 0.32)                # moulded plastic: blue, a white rubber grip, a soft sheen
	pm0.vertex_color_use_as_albedo = true
	pm0.clearcoat_enabled = true
	pm0.clearcoat = 0.4
	pm0.clearcoat_roughness = 0.3
	_mesh(brush, _brush_mesh(), pm0, Vector3.ZERO)
	var tuft := BoxMesh.new()                            # the bristles: 8 × 3 tufts, white with a blue row
	tuft.size = Vector3(0.0022, 0.011, 0.0022)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft
	mm.instance_count = 24
	for i in 24:
		var ix := i % 8
		var iz := i / 8
		var bx := 0.146 + ix * 0.0036
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(bx, _brush_center(bx) + 0.0032 + 0.0052, (iz - 1) * 0.0034)))
		mm.set_instance_color(i, Color(0.55, 0.75, 0.95) if iz == 1 and ix % 3 == 0 else Color(0.96, 0.96, 0.97))
	var tm := MultiMeshInstance3D.new()
	tm.multimesh = mm
	var bm := _mat(Color(1, 1, 1), 0.75)
	bm.vertex_color_use_as_albedo = true
	tm.material_override = bm
	tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush.add_child(tm)
	var pm := CapsuleMesh.new()                          # a line of paste along the bristles' tips
	pm.radius = 0.0038
	pm.height = 0.024
	paste = _mesh(brush, pm, _mat(Color(0.97, 0.98, 1.0), 0.45), Vector3(0.159, _brush_center(0.159) + 0.0146, 0), Vector3(0, 0, PI / 2))
	paste.visible = false
	brush.global_position = _w(BRUSH_HOME)
	brush.global_rotation = Vector3(0, room.global_rotation.y + 0.35, 0)
	# the paste tube: a white and red tube lying on the shelf, its cap toward the brush
	tube = Node3D.new()
	add_child(tube)
	var body := CylinderMesh.new()
	body.top_radius = 0.016
	body.bottom_radius = 0.012
	body.height = 0.13
	_mesh(tube, body, _mat(Color(0.93, 0.93, 0.92), 0.4), Vector3.ZERO, Vector3(0, 0, PI / 2))
	var band := CylinderMesh.new()
	band.top_radius = 0.0165
	band.bottom_radius = 0.0155
	band.height = 0.03
	_mesh(tube, band, _mat(Color(0.78, 0.12, 0.12), 0.4), Vector3(-0.02, 0, 0), Vector3(0, 0, PI / 2))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.008
	cap.bottom_radius = 0.008
	cap.height = 0.018
	_mesh(tube, cap, _mat(Color(0.12, 0.12, 0.13), 0.5), Vector3(0.074, 0, 0), Vector3(0, 0, PI / 2))
	tube.global_position = _w(TUBE_HOME)
	tube.global_rotation = Vector3(0, room.global_rotation.y - 0.25, 0)
	# the steel tumbler
	tumbler = Node3D.new()
	add_child(tumbler)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.034
	cup.bottom_radius = 0.027
	cup.height = 0.095
	_mesh(tumbler, cup, _mat(Color(0.82, 0.83, 0.84), 0.3, 0.75), Vector3(0, 0.0475, 0))
	tumbler.global_position = _w(TUMBLER_HOME)
	# the foam: a ring of it on his lips, patchy (a noise cut-out that fills in as he brushes), and a few bubbles
	var tor := TorusMesh.new()
	tor.inner_radius = 0.0125
	tor.outer_radius = 0.0175
	tor.rings = 24
	tor.ring_segments = 8
	_foam_mat = _mat(Color(0.98, 0.98, 1.0), 0.9)
	var nz := NoiseTexture2D.new()
	nz.width = 96
	nz.height = 96
	nz.seamless = true
	nz.noise = FastNoiseLite.new()
	(nz.noise as FastNoiseLite).frequency = 0.24
	var ramp := Gradient.new()                           # (the noise as alpha: white foam, its holes see-through)
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	nz.color_ramp = ramp
	_foam_mat.albedo_texture = nz
	_foam_mat.albedo_color = Color(1, 1, 1)
	_foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_foam_mat.alpha_scissor_threshold = 0.99
	_foam_mat.uv1_scale = Vector3(3, 1, 1)
	_lip_foam = _mesh(self, tor, _foam_mat, Vector3.ZERO)
	_lip_foam.visible = false
	_bubbles = GPUParticles3D.new()
	_bubbles.amount = 10
	_bubbles.lifetime = 0.6
	_bubbles.emitting = false
	_bubbles.local_coords = false
	var pp := ParticleProcessMaterial.new()
	pp.direction = Vector3(0, -1, 0)
	pp.spread = 70.0
	pp.initial_velocity_min = 0.01
	pp.initial_velocity_max = 0.03
	pp.gravity = Vector3(0, -0.25, 0)
	pp.scale_min = 0.5
	pp.scale_max = 1.2
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pp.emission_sphere_radius = 0.012
	_bubbles.process_material = pp
	var bq := QuadMesh.new()
	bq.size = Vector2(0.0035, 0.0035)
	var bmat := _mat(Color(1, 1, 1, 0.85), 0.6)
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bq.material = bmat
	_bubbles.draw_pass_1 = bq
	add_child(_bubbles)


## The brush's body as one moulded piece: a tube swept along a gently curved line (a slight S, thumb rest up),
## round-oval in section, full in the grip, slim at the neck, then the small flat head (17.5 cm in all, its
## bristles' side +Y). Blue, with a white rubber grip on top of the handle.
const BRUSH_LEN := 0.175
func _brush_center(x: float) -> float:
	return 0.0025 * sin(x / BRUSH_LEN * TAU * 0.9) - 0.0015 * smoothstep(0.11, 0.15, x)


func _brush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_len := 40
	var n_ring := 14
	var rings := []
	for i in n_len + 1:
		var x := -0.004 + (BRUSH_LEN + 0.004) * float(i) / n_len
		var ry: float                                     # half-height (bristles' way) and half-width
		var rz: float
		if x < 0.0:
			ry = 0.004; rz = 0.005
		elif x < 0.09:
			var g := sin(clampf(x / 0.09, 0.0, 1.0) * PI)  # the grip swells in the middle
			ry = 0.0052 + 0.0016 * g; rz = 0.0062 + 0.0016 * g
		elif x < 0.14:
			var t := (x - 0.09) / 0.05
			ry = lerpf(0.0052, 0.0028, t); rz = lerpf(0.0062, 0.0034, t)
		else:
			var t2 := clampf((x - 0.14) / 0.035, 0.0, 1.0)
			ry = 0.0032; rz = lerpf(0.0045, 0.0058, sin(t2 * PI) * 0.7 + 0.3)
			if t2 > 0.92:
				rz *= 0.7
		var ring := []
		for j in n_ring:
			var a := TAU * float(j) / n_ring
			var p := Vector3(x, _brush_center(x) + sin(a) * ry, cos(a) * rz)
			var white := x > 0.015 and x < 0.075 and sin(a) > 0.35
			ring.append([p, Color(0.93, 0.95, 0.97) if white else Color(0.14, 0.42, 0.86)])
		rings.append(ring)
	for i in n_len:
		for j in n_ring:
			var j2 := (j + 1) % n_ring
			for v in [rings[i][j], rings[i + 1][j], rings[i + 1][j2], rings[i][j], rings[i + 1][j2], rings[i][j2]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
	for end in [0, n_len]:                               # the two ends closed
		var c := Vector3(rings[end][0][0].x, _brush_center(rings[end][0][0].x), 0)
		for j in n_ring:
			var j2 := (j + 1) % n_ring
			var vs := [c, rings[end][j2][0], rings[end][j][0]] if end == 0 else [c, rings[end][j][0], rings[end][j2][0]]
			for v in vs:
				st.set_color(Color(0.14, 0.42, 0.86))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A thing into his hand: from where it is to his palm over `secs`, then held there (placed every frame, _grip).
func _hold(thing: Node3D, side: String, secs := 0.3) -> void:
	held[thing] = side
	_grip_t[thing] = 0.0 if secs > 0.0 else 1.0
	_grip_from[thing] = thing.global_transform
	set_meta("grip_secs", secs)


func _palm(side: String) -> Transform3D:
	var h := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_" + side))
	return Transform3D(h.basis.orthonormalized(), h.origin + h.basis.y.normalized() * 0.065)


## Where a held thing goes: the brush through his fist, its head out past the thumb, toward his mouth when he
## brushes (else across to his left, bristles up); the tumbler upright in his palm, tipping to his lips as he drinks.
func _grip(thing: Node3D) -> Transform3D:
	var side: String = held[thing]
	var palm := _palm(side)
	var up := Vector3.UP
	if thing == brush:
		var dir: Vector3 = model.global_basis.x.lerp(model.global_basis.z, 0.25).normalized()   # his left, a little ahead
		var m := _mouth()
		var fist := _fist(side)
		var at := fist - dir * 0.04
		if fist.distance_to(m) < 0.26:                     # brushing: through his fist, the bristles on his teeth:
			var fwd := model.global_basis.z                 # the side ones a little further back, the stroke along them
			var to := m - model.global_basis.x * (_zone * 0.021 + sin(_phase * TAU) * 0.006) - fwd * absf(_zone) * 0.012
			dir = (to - fist).normalized()
			at = to - dir * 0.16
		var side_v := dir.cross(up).normalized()
		var b := Basis(dir, side_v.cross(dir).normalized(), -side_v)
		return Transform3D(b, at)
	var m2 := _mouth()
	var tip := clampf(1.0 - (palm.origin.distance_to(m2) - 0.08) / 0.1, 0.0, 1.0)   # near his lips: tipped
	var y := up.lerp((m2 - palm.origin).normalized(), tip * 0.45).normalized()
	var x := y.cross(model.global_basis.z).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), palm.origin + palm.basis.z.normalized() * 0.0 - y * 0.035)


func _let_go(thing: Node3D) -> void:
	held.erase(thing)
	_grip_t.erase(thing)


func _put(thing: Node3D, home: Vector3, yaw: float, secs := 0.35) -> void:
	_let_go(thing)
	var start := thing.global_transform
	var to := Transform3D(Basis.from_euler(Vector3(0, room.global_rotation.y + yaw, 0)), _w(home))
	var tw := create_tween()
	tw.tween_method(func(k: float): thing.global_transform = start.interpolate_with(to, k), 0.0, 1.0, secs) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)




# ---- the stages ----

func _set_stage(s: String) -> void:
	stage = s
	_t = 0.0
	match s:
		"take":
			_say = _L("Drag his toothbrush to him", "டூத் பிரஷை அவரிடம் இழு")
		"paste":
			_say = _L("Drag the paste onto the brush", "பேஸ்ட்டை பிரஷ் மேல் இழு")
		"scrub":
			_say = _L("Move and scrub the toothbrush across all three sections of your teeth.",
				"மூன்று பக்கப் பற்களிலும் பிரஷை நகர்த்தித் தேய்.")
		"rinse":
			_say = _L("Drag the tumbler to him to rinse", "வாய் கொப்பளிக்க டம்ளரை அவரிடம் இழு")
		"putback":
			_say = _L("All clean.", "சுத்தம்.")
	if _ui:
		_ui.queue_redraw()


func _L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func _take() -> void:
	_set_stage("taking")
	anim.play("morning/Reach", 0.35)
	await get_tree().create_timer(0.45).timeout
	_hold(brush, "r")
	await get_tree().create_timer(0.35).timeout
	anim.play("morning/BrushHold", 0.45)
	await get_tree().create_timer(0.5).timeout
	_set_stage("paste")
	_shot("brush_holding")


func _paste_on() -> void:
	_set_stage("pasting")
	var start := tube.global_transform
	var tw := create_tween()
	_paste_k = 0.0
	paste.visible = true
	paste.scale = Vector3(1, 0.05, 1)
	tw.tween_method(func(k: float):
		_paste_k = k
		paste.scale = Vector3(1, maxf(k, 0.05), 1), 0.0, 1.0, 0.9)
	tw.tween_interval(0.2)
	await tw.finished
	tube.global_transform = start
	_put(tube, TUBE_HOME, -0.25)
	_shot("brush_paste")
	_set_stage("scrub")
	anim.play("morning/Brush", 0.45)
	anim.speed_scale = 1.0                              # (after the blend in, its strokes are yours: _brushing)
	_sound()


func _rinse() -> void:
	_set_stage("rinsing")
	_lip_foam.visible = false
	_bubbles.emitting = false
	anim.speed_scale = 1.0
	anim.play("morning/BrushHold", 0.3)
	_put(brush, BRUSH_HOME, 0.35, 0.01)                 # (on the shelf while he rinses)
	brush.visible = false
	await get_tree().create_timer(0.25).timeout
	_hold(tumbler, "l")
	anim.play("morning/Rinse", 0.3)
	await get_tree().create_timer(1.4).timeout
	_shot("brush_gargle")
	await get_tree().create_timer(1.7).timeout
	_set_stage("putback")
	anim.play("morning/Reach", 0.4)
	await get_tree().create_timer(0.4).timeout
	_put(tumbler, TUMBLER_HOME, 0.0)
	brush.visible = true
	paste.visible = false
	await get_tree().create_timer(0.5).timeout
	anim.play("Idle", 0.5)
	await get_tree().create_timer(0.6).timeout
	_end()


func _end() -> void:
	stage = "done"
	_close_up(false)
	print("BRUSH3D done: %.1f s, %.1f fps on average (the scrub %.1f fps)" % [_secs, _frames / maxf(_secs, 0.001),
		_scrub_frames / maxf(_scrub_secs, 0.001)])
	var tw := create_tween()                            # the camera back to the walk
	var from := cam.global_transform
	tw.tween_method(func(k: float):
		if is_instance_valid(_from_cam):
			cam.global_transform = from.interpolate_with(_from_cam.global_transform, k), 0.0, 1.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(_from_cam):
		_from_cam.make_current()
	held.clear()
	for n in [brush, tube, tumbler, cam, _layer, _mirror_vp, _mirror_quad]:
		if is_instance_valid(n):
			n.queue_free()
	for n in [_lip_foam, _bubbles, _snd]:
		if is_instance_valid(n):
			n.queue_free()
	anim.callback_mode_process = _anim_mode
	anim.speed_scale = 1.0
	walker.set("scripted", false)
	walker.activate()
	finished.emit()


# ---- the hand ----

func _screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _mouth() -> Vector3:                              # his front teeth, as his head is now
	var h := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))
	if _teeth_local != Vector3.ZERO:
		return h * _teeth_local
	return h.origin + model.global_basis.z * 0.1 + Vector3(0, -0.015, 0)


## The front of his upper teeth (the teeth mesh's front, at rest) in the head bone's frame, so the brush finds them
## however the head moves. (A model without teeth: an estimate from the head bone.)
## The face close-up drawn sharper than Low draws the city (his brows and lashes are fine strands: at half
## resolution they break up into dots), only while it lasts.
var _vp_scale := -1.0
var _vp_mode := 0
func _close_up(on: bool) -> void:
	var vp := get_viewport()
	if on and _vp_scale < 0.0:
		_vp_scale = vp.scaling_3d_scale
		_vp_mode = vp.scaling_3d_mode
		if _vp_scale < 0.8:
			vp.scaling_3d_scale = 0.8
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	elif not on and _vp_scale >= 0.0:
		vp.scaling_3d_scale = _vp_scale
		vp.scaling_3d_mode = _vp_mode as Viewport.Scaling3DMode
		_vp_scale = -1.0


func _find_teeth() -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).to_lower().contains("teeth") and (mi as MeshInstance3D).mesh:
			var bb: AABB = (mi as MeshInstance3D).mesh.get_aabb()
			var front := bb.position + Vector3(bb.size.x * 0.5, bb.size.y * 0.62, bb.size.z)   # (the model faces +Z)
			var to_skel := skel.global_transform.affine_inverse() * (mi as Node3D).global_transform
			var head_rest := skel.get_bone_global_rest(skel.find_bone("head"))
			_teeth_local = head_rest.affine_inverse() * (to_skel * front)
			print("BRUSH3D teeth at %s in the head's frame" % _teeth_local)
			return


## Brushing: his right arm turned at the shoulder (the elbow and wrist as the clip has them) so his fist comes
## level with his teeth, a hand's width to his right, a little ahead: where a brush 16 cm long reaches them straight.
func _fist_to_mouth(k: float) -> void:
	var ua := skel.find_bone("upperarm_r")
	if ua < 0 or _teeth_local == Vector3.ZERO:
		return
	var g := skel.global_transform
	var sh: Vector3 = g * skel.get_bone_global_pose(ua).origin
	var fist := _fist("r")
	var want := _mouth() - model.global_basis.x * 0.115 + model.global_basis.z * 0.035 + Vector3(0, -0.012, 0)   # (+X: his left)
	var a := (fist - sh)
	var b := (want - sh)
	if a.length() < 0.01 or b.length() < 0.01:
		return
	var q := Quaternion(a.normalized(), b.normalized())
	q = Quaternion.IDENTITY.slerp(q, k)
	var gb := g.basis.orthonormalized()
	var q_skel := Quaternion(gb.inverse() * Basis(q) * gb)              # (that turn in the skeleton's own frame)
	var par := skel.get_bone_parent(ua)
	var pg := skel.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
	var cur := skel.get_bone_global_pose(ua).basis.orthonormalized()
	var new_local := pg.inverse() * (Basis(q_skel) * cur)
	skel.set_bone_pose_rotation(ua, new_local.get_rotation_quaternion())


## Where his fingers close: between the middle joints of the index and little fingers (the handle runs there).
func _fist(side: String) -> Vector3:
	var a := skel.find_bone("index_02_" + side)
	var b := skel.find_bone("pinky_02_" + side)
	if a < 0 or b < 0:
		return _palm(side).origin
	var g := skel.global_transform
	return (g * skel.get_bone_global_pose(a).origin + g * skel.get_bone_global_pose(b).origin) * 0.5


func _brush_head() -> Vector3:
	return brush.global_transform * Vector3(0.16, 0.012, 0)


func _input(e: InputEvent) -> void:
	if stage == "" or stage == "done" or cam == null or (skip and not "--brushinput" in OS.get_cmdline_user_args()):
		return
	var k := Style.s(_ui) if _ui else 1.0
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var p: Vector2 = e.position
			if stage == "take" and _screen(brush.global_position).distance_to(p) < 70 * k:
				_grab(brush)
			elif stage == "paste" and _screen(tube.global_position).distance_to(p) < 70 * k:
				_grab(tube)
			elif stage == "rinse" and _screen(tumbler.global_position + Vector3(0, 0.05, 0)).distance_to(p) < 70 * k:
				_grab(tumbler)
			elif stage == "scrub" and _screen(_mouth()).distance_to(p) < 160 * k:
				if "--brushinput" in OS.get_cmdline_user_args():
					print("BRUSH3D scrub press at %s, mouth %s" % [p, _screen(_mouth())])
				_scrubbing = true
				_last_mouse = p
			get_viewport().set_input_as_handled()
		else:
			_scrubbing = false
			if _drag:
				_drop(e.position)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if _drag:
			_drag.global_position = cam.project_position(e.position, _drag_depth)
		elif _scrubbing:
			var d: Vector2 = e.position - _last_mouse
			_last_mouse = e.position
			if absf(d.x) > absf(d.y) * 0.8:              # side to side, as you brush: holding still or dragging up
				_scrub(absf(d.x), e.position, get_process_delta_time())   # and down does nothing


func _grab(thing: Node3D) -> void:
	_drag = thing
	_drag_depth = cam.global_position.distance_to(thing.global_position)


func _drop(at: Vector2) -> void:
	var thing := _drag
	_drag = null
	var k := Style.s(_ui) if _ui else 1.0
	var hand := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_r"))
	var body := _screen(_mouth() + Vector3(0, -0.3, 0))
	if thing == brush:
		if at.distance_to(body) < 240 * k or at.distance_to(_screen(hand.origin)) < 120 * k:
			_take()
			return
		_put(brush, BRUSH_HOME, 0.35)
		_hint(_L("Bring it to him", "அவரிடம் கொண்டு போ"))
	elif thing == tube:
		if at.distance_to(_screen(_brush_head())) < 60 * k:
			tube.global_position = _brush_head() + Vector3(0, 0.03, 0)
			_paste_on()
			return
		_put(tube, TUBE_HOME, -0.25)
		_hint(_L("Onto the brush's head", "பிரஷ் தலை மேல"))
	elif thing == tumbler:
		if at.distance_to(body) < 240 * k:
			_rinse()
			return
		_put(tumbler, TUMBLER_HOME, 0.0)
		_hint(_L("Bring it to him", "அவரிடம் கொண்டு போ"))


func _hint(s: String) -> void:
	var was := _say
	_say = s
	_ui.queue_redraw()
	await get_tree().create_timer(1.6).timeout
	if _say == s:
		_say = was
		_ui.queue_redraw()


## A scrub of `px` pixels at screen point `at`: the side of his mouth it's on fills (his right is the screen's left:
## he faces the camera).
func _scrub(px: float, at: Vector2, dt: float) -> void:
	if stage != "scrub":
		return
	if "--brushinput" in OS.get_cmdline_user_args() and Engine.get_process_frames() % 30 == 0:
		print("BRUSH3D scrub %.0f px at %s, sides %s" % [px, at, sides])
	var m := _screen(_mouth())
	var k := Style.s(_ui) if _ui else 1.0
	if absf(at.y - m.y) > 110 * k or absf(at.x - m.x) > 230 * k:   # (off his mouth: it doesn't count)
		return
	var his_right := (_screen(_mouth() - model.global_basis.x * 0.1) - m).normalized()   # (model +X is his left)
	var off := (at - m).dot(his_right)
	var side := 1 if absf(off) < 40 * k else (0 if off > 0.0 else 2)
	_zone_want = float(side - 1)
	if absf(_zone - _zone_want) > 0.3:                  # (the brush still on its way there: not yet)
		return
	sides[side] = minf(sides[side] + px / (900.0 * k), 1.0)
	_speed = lerpf(_speed, px / maxf(dt, 0.001), 0.3)
	_phase += px / (120.0 * k)
	_ui.queue_redraw()
	_ui.queue_redraw()
	if sides.min() >= 1.0:
		_scrubbing = false
		_shot("brush_done")
		_set_stage("rinse")
		anim.play("morning/BrushHold", 0.4)
		anim.speed_scale = 1.0


func _process(dt: float) -> void:
	if stage == "" or cam == null:
		return
	_t += dt
	var want := "face" if stage in ["scrub", "rinse", "rinsing", "putback"] else "shelf"
	if stage != "done" and want != _shot_name:          # to the other framing, eased
		_shot_name = want
		_cam_t = 0.0
		_cam_from = cam.global_transform
	if stage != "done" and _cam_t < 1.0:
		if _cam_t == 0.0 and _cam_from == Transform3D.IDENTITY:
			_cam_from = _from_cam.global_transform if is_instance_valid(_from_cam) else cam.global_transform
		_cam_t = minf(_cam_t + dt / 0.9, 1.0)
		var sh: Array = SHOTS[_shot_name]
		var to := Transform3D.IDENTITY.looking_at(_w(sh[1]) - _w(sh[0]), Vector3.UP)
		to.origin = _w(sh[0])
		var e := _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		cam.global_transform = _cam_from.interpolate_with(to, e)
		cam.near = FACE_NEAR if _shot_name == "face" else 0.03
		cam.fov = lerpf(58.0, 36.0, e) if _shot_name == "face" else lerpf(36.0, 58.0, e) if cam.fov < 58.0 else 58.0
	_update_mirror()
	if stage == "scrub":
		_brushing(dt)
	_expressions(dt)
	anim.advance(dt)
	if stage == "scrub":
		_fist_to_mouth(clampf(_t / 0.6, 0.0, 1.0))
	if stage == "scrub" and _t > 0.5:                   # his head turns a little to the side being brushed
		var hb := skel.find_bone("head")
		skel.set_bone_pose_rotation(hb, Quaternion(Vector3.UP, -_zone * 0.12) * skel.get_bone_pose_rotation(hb))
	if stage in ["scrub", "rinse"] and _cam_t >= 1.0:   # the camera breathes a little (a hand-held close-up)
		cam.global_position += Vector3(sin(_t * 0.7) * 0.00012, sin(_t * 0.9 + 1.0) * 0.0001, 0.0)
	for thing in held:                                  # what he holds, in his hand
		var g := _grip(thing)
		_grip_t[thing] = minf(_grip_t[thing] + dt / maxf(float(get_meta("grip_secs", 0.3)), 0.01), 1.0)
		var e2: float = _grip_t[thing] * _grip_t[thing] * (3.0 - 2.0 * _grip_t[thing])
		thing.global_transform = (_grip_from[thing] as Transform3D).interpolate_with(g, e2) if e2 < 1.0 else g
	if stage == "scrub":
		_foam(dt)
		_scrub_frames += 1
		_scrub_secs += dt
	_frames += 1
	_secs += dt
	if skip and "--brushinput" in OS.get_cmdline_user_args():
		_drive(dt)
	elif skip:
		_auto(dt)


var _frames := 0
var _secs := 0.0
var _scrub_frames := 0
var _scrub_secs := 0.0


## His face: relaxed, blinking; brushing, the mouth a little open and rounded on the brush, the jaw going with the
## strokes, the cheek out on the side brushed; rinsing, the cheeks full of water, then the lips pushed out to spit.
func _expressions(dt: float) -> void:
	if _face == null or not _face.has_face():
		return
	match stage:
		"scrub":
			var s := sin(_phase * TAU)
			_face.pose({"mouth-open": 0.09 + 0.025 * s, "mouth-pursing": 0.14, "mouth-protusion": 0.06,
				"eyebrows-left-inner-up": 0.08, "eyebrows-right-inner-up": 0.08, "eye-left-slit": 0.06, "eye-right-slit": 0.06})
		"rinsing":
			var t := anim.current_animation_position / maxf(anim.current_animation_length, 0.01) if anim.current_animation == "morning/Rinse" else 0.0
			if t < 0.32:
				_face.pose({"mouth-open": 0.22 * clampf(t / 0.2, 0.0, 1.0)})
			elif t < 0.66:
				_face.pose({"mouth-compression": 0.7, "mouth-protusion": 0.25, "eye-left-slit": 0.35, "eye-right-slit": 0.35})
			elif t < 0.84:
				_face.pose({"mouth-pursing": 0.85, "mouth-protusion": 0.6})
			else:
				_face.pose({})
		"paste", "pasting":
			_face.pose({"eyebrows-left-inner-up": 0.15, "eyebrows-right-inner-up": 0.15})
		_:
			_face.pose({"mouth-corner-puller": 0.05})
	_face.update(dt)


## The strokes: the clip's three strokes a second follow your hand (a stroke for every ~120 px it moves), slowly by
## themselves when it rests; the brush's head eases to the side you're on.
func _brushing(dt: float) -> void:
	_speed = lerpf(_speed, 0.0, 1.0 - exp(-dt * 4.0))
	_phase += dt * 0.5
	_zone = lerpf(_zone, _zone_want, 1.0 - exp(-dt * 6.0))
	if _t > 0.6:                                        # (the time the next advance() lands on: the stroke you're at)
		var len := anim.get_animation("morning/Brush").length
		anim.seek(maxf(fmod(_phase / 3.0, 1.0) * len - dt, 0.0), false)


func _foam(dt: float) -> void:
	var total: float = (sides[0] + sides[1] + sides[2]) / 3.0
	var h := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))
	var m := _mouth()
	var fwd := (m - h.origin)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	_lip_foam.visible = total > 0.05
	_foam_mat.alpha_scissor_threshold = lerpf(0.98, 0.68, clampf(total * 1.2, 0.0, 1.0))   # (patches, never a ring)
	_lip_foam.global_transform = Transform3D(Basis(right * 1.25, fwd * 0.5, Vector3.UP * 0.62), m + fwd * 0.012 + Vector3(0, -0.006, 0))
	paste.scale = Vector3(1, clampf(1.0 - total * 1.5, 0.0, 1.0), 1)   # the paste goes into the foam
	paste.visible = paste.scale.y > 0.05
	_bubbles.global_position = m + fwd * 0.012 + right * _zone * -0.012
	_bubbles.emitting = false                          # (they read as specks: the foam alone)
	_sound_fill()


## The brush's sound: bristles on teeth (filtered noise), louder with each stroke and with how fast you scrub; quiet.
func _sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = gen
	_snd.volume_db = -16.0
	_snd.unit_size = 0.6
	add_child(_snd)
	_snd.global_position = _mouth()
	_snd.play()
	_snd_pb = _snd.get_stream_playback() as AudioStreamGeneratorPlayback


func _sound_fill() -> void:
	if _snd_pb == null:
		return
	var n := _snd_pb.get_frames_available()
	var loud := clampf(_speed / 1400.0, 0.0, 1.0)
	var ph := _phase
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		ph += 0.0000227 * (1.5 + loud * 3.0)              # (the strokes, as heard)
		var env := 0.35 + 0.65 * absf(sin(ph * PI * 2.0))
		var w := randf() * 2.0 - 1.0
		_hp += (w - _hp) * 0.08                          # a soft high hiss: noise with its lows taken out (w - low)
		_lp += ((w - _hp) - _lp) * 0.5                   # and its harshest highs softened
		var v := _lp * env * (0.05 + loud * 0.45)
		buf[i] = Vector2(v, v)
	_snd_pb.push_buffer(buf)


## (testing, with --storyskip --brushinput) the real mouse: presses, drags and releases sent as input events, so
## the drag and drop and the scrubbing are tested as a player does them.
var _drive_t := 0.0
var _drive_busy := false
func _drive(dt: float) -> void:
	_drive_t += dt
	if _drive_busy or _drive_t < 1.3 or _cam_t < 1.0:
		return
	_drive_t = 0.0
	match stage:
		"take":
			_shot("in_start")
			_mouse_drag(_screen(brush.global_position), _screen(_mouth() + Vector3(0, -0.3, 0)))
		"paste":
			_mouse_drag(_screen(tube.global_position), _screen(_brush_head()))
		"scrub":
			_mouse_scrub()
		"rinse":
			_mouse_drag(_screen(tumbler.global_position + Vector3(0, 0.05, 0)), _screen(_mouth() + Vector3(0, -0.3, 0)))


func _send_button(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _send_motion(at: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	Input.parse_input_event(e)


func _mouse_drag(from: Vector2, to: Vector2) -> void:
	_drive_busy = true
	print("BRUSH3D drag %s: %s → %s" % [stage, from, to])
	_send_button(from, true)
	var last := from
	for i in 20:
		await get_tree().process_frame
		var p := from.lerp(to, (i + 1) / 20.0)
		_send_motion(p, p - last)
		last = p
	await get_tree().process_frame
	_send_button(to, false)
	_drive_busy = false


func _mouse_scrub() -> void:
	_drive_busy = true
	var m := _screen(_mouth())
	_send_button(m, true)
	var last := m
	var n := 0
	while stage == "scrub" and n < 2400:
		await get_tree().process_frame
		n += 1
		m = _screen(_mouth())
		var kk := Style.s(_ui)                           # a section at a time, as you would: short strokes on each
		var his_right := (_screen(_mouth() - model.global_basis.x * 0.1) - m).normalized()
		var sec: float = [1.0, 0.0, -1.0][mini(n / 120, 2)] if n < 360 else [1.0, 0.0, -1.0][(n / 60) % 3]
		var p: Vector2 = m + his_right * sec * 110.0 * kk + Vector2(sin(n * 0.5) * 28.0 * kk, 0.0)
		_send_motion(p, p - last)
		last = p
		if n in [60, 200, 330]:
			_shot("in_scrub_%d" % n)
	_send_button(last, false)
	print("BRUSH3D scrubbed %d frames, sides %s" % [n, sides])
	_drive_busy = false


## --storyskip: it plays itself (the drags made as you would, a beat apart).
var _auto_t := 0.0
func _auto(dt: float) -> void:
	_auto_t += dt
	if _auto_t < 1.2:
		return
	_auto_t = 0.0
	match stage:
		"take":
			_shot("brush_start")
			_take()
		"paste":
			tube.global_position = _brush_head() + Vector3(0, 0.03, 0)
			_paste_on()
		"scrub":
			for i in 3:
				sides[i] = minf(sides[i] + 0.34, 1.0)
			_scrub(0.0, _screen(_mouth()), dt)
			_speed = 900.0
			_shot("brush_scrub")
		"rinse":
			_rinse()


func _shot(name: String) -> void:
	if shots == "":
		return
	var hd := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("head"))
	var hr := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_r"))
	print("BRUSH3D %s: him %s head %s hand_r %s (basis y %s) brush %s cam %s room %s" % [name, room.to_local(walker.global_position),
		room.to_local(hd.origin), room.to_local(hr.origin), hr.basis.y.normalized(), room.to_local(brush.global_position),
		room.to_local(cam.global_position), room.global_position])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(shots + "/" + name + ".jpg", 0.85)


# ---- the card: what to do, and the brushing's three sides ----

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	_layer.add_child(_ui)


func _draw_ui() -> void:
	if stage == "done":
		return
	var k := Style.s(_ui)
	var vs := _ui.get_viewport_rect().size
	var w := clampf(vs.x * 0.34, 380.0 * k, 560.0 * k)  # (bottom left, clear of his face)
	var pad := 22.0 * k
	var body := Style.font(500)
	var size := int(19 * k)
	var tw := w - 2.0 * pad
	var text_h := body.get_multiline_string_size(_say, HORIZONTAL_ALIGNMENT_LEFT, tw, size).y
	var bars := stage in ["scrub", "rinse"]
	var h := pad + 22.0 * k + text_h + (58.0 * k if bars else 0.0) + pad
	var r := Rect2(Vector2(32.0 * k, vs.y - h - 32.0 * k), Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(int(14 * k))
	sb.border_color = Color(WOOD.r, WOOD.g, WOOD.b, 0.35)
	sb.set_border_width_all(maxi(1, int(k)))
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = int(12 * k)
	_ui.draw_style_box(sb, r)
	var y := r.position.y + pad + 14.0 * k
	_ui.draw_string(Style.font(600), Vector2(r.position.x + pad, y), _L("Brush your teeth", "பல் தேய்"), HORIZONTAL_ALIGNMENT_LEFT,
		-1, int(15 * k), WOOD)
	y += 10.0 * k + size
	_ui.draw_multiline_string(body, Vector2(r.position.x + pad, y), _say, HORIZONTAL_ALIGNMENT_LEFT, tw, size, -1, CHARCOAL)
	if not bars:
		return
	y = r.position.y + pad + 22.0 * k + text_h + 26.0 * k
	var names := [_L("Right", "வலது"), _L("Front", "முன்"), _L("Left", "இடது")]
	var gap := 16.0 * k
	var bw := (tw - 2.0 * gap) / 3.0
	for i in 3:
		var x := r.position.x + pad + i * (bw + gap)
		var done: bool = sides[i] >= 1.0
		var here: bool = stage == "scrub" and _scrubbing and not done and i == int(roundf(_zone)) + 1   # (the brush is there)
		_ui.draw_string(Style.font(600 if done or here else 500), Vector2(x, y), names[i] + ("  ✓" if done else ("  ●" if here else "")),
			HORIZONTAL_ALIGNMENT_LEFT, bw, int(15 * k), FOREST if done or here else Color(CHARCOAL, 0.75))
		var track := StyleBoxFlat.new()
		track.bg_color = Color(CHARCOAL, 0.1)
		track.set_corner_radius_all(int(4 * k))
		_ui.draw_style_box(track, Rect2(x, y + 10 * k, bw, 9 * k))
		if sides[i] > 0.0:
			var fill := track.duplicate() as StyleBoxFlat
			fill.bg_color = FOREST
			_ui.draw_style_box(fill, Rect2(x, y + 10 * k, bw * sides[i], 9 * k))
