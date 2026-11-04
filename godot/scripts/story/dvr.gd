extends Control
## Kathir's monitor (STORY_BIBLE.md E07): the building's lobby camera, his copy of that night, and Karthik works it
## himself. The picture is the building's own ground floor (room_office_stairs, the room Karthik climbs) seen from the
## camera high on the right wall, looking at the gate and the stair, rendered live, with the people of that night where they were at the
## footage's time: Muniyandi on his chair and then out at the gate, and a man in a cap who crosses the lobby at 9:39,
## climbs the stair and opens the office's glass door with a card; at 9:58 he comes down again and goes out. The
## recorder writes its clock, its name and its card log over the picture. Space plays and pauses, ← → step ten
## seconds, 1 2 3 the speed, drag the bar to go anywhere from 9:30 to 10:10 PM. His phone's camera (P) takes a
## picture of the screen, and what the screen shows then is what the picture is (frame_tag). E or Esc: step back.

signal closed

const T0 := 21.5 * 3600.0                  # the copy runs 21:30:00 …
const T1 := 22.0 * 3600.0 + 600.0          # … 22:10:00
const SPEEDS := [1.0, 8.0, 32.0]
const SITE := "RAGHAVAN DEV  GPM  NVR-1"
const ROOM := "res://assets/interiors/room_office_stairs.glb"
const Actor := preload("res://scripts/story/actor.gd")
const IN := 21.0 * 3600 + 2388.0           # 21:39:48 the cap man at the gate
const OUT := 21.0 * 3600 + 3470.0          # 21:57:50 out of the office door again
# The man in the cap, in the room's frame (Godot: x, up, z; the gate at +z, the stair up the left wall to the
# landing at the back, the office's glass door at x 1.6 on the landing): [seconds after IN, where]
const PATH_IN := [[0.0, Vector3(0.3, 0, 6.4)], [5.0, Vector3(-1.6, 0, 4.0)], [8.0, Vector3(-3.25, 0, 3.5)],
	[18.0, Vector3(-3.25, 3.3, -3.0)], [22.0, Vector3(-1.0, 3.3, -3.9)], [26.0, Vector3(1.6, 3.3, -4.55)],
	[29.0, Vector3(1.6, 3.3, -5.4)]]
const CHAIR := Vector3(2.6, 0, 3.4)
const GATE := Vector3(0.75, 0, 5.5)

var lang := "en"
var font: Font
var t := T0                                # the footage's clock, seconds since midnight
var playing := true
var speed_i := 1
var _drag := false
var _noise := 0.0
# The office door's card reader, as the recorder logs it: [time, door, card, result]
var card_log := [[19.0 * 3600 + 1860, "1F-OFFICE", "#03", "OK"], [20.0 * 3600 + 720, "1F-OFFICE", "#11", "OK"],
	[IN + 27.0, "1F-OFFICE", "#07", "OK"], [OUT - 1.0, "1F-OFFICE", "#07", "EXIT"]]

var _vp: SubViewport
var _feed: TextureRect
var _over: Control
var _cam: Camera3D
var _man: Node3D
var _watch: Node3D


func open(language: String) -> void:
	lang = language
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _vp == null:
		_build()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


static func hms(s: float) -> String:
	var i := int(s)
	return "%02d:%02d:%02d" % [i / 3600, (i / 60) % 60, i % 60]


## What a picture of the screen right now would show: the cap man where the camera sees him (the lobby floor; up the
## stair and on the landing he's behind the stair and over the camera), and whether the card log's #07 line is on it.
func frame_tag() -> Dictionary:
	var mp := _man_at()
	var card := t >= IN + 27.0
	if mp != Vector3.INF and mp.y < 0.5 and t < OUT - 60.0:
		return {"tag": "E07_in", "card": card, "label": {"en": "Lobby camera 9:39 PM: a man in a cap comes in", "ta": "லாபி கேமரா இரவு 9:39: தொப்பி போட்ட ஒருத்தர் உள்ள வர்றாரு"}}
	if mp != Vector3.INF and mp.y < 0.5:
		return {"tag": "E07_out", "card": card, "label": {"en": "Lobby camera 9:58 PM: the cap man leaves", "ta": "லாபி கேமரா இரவு 9:58: தொப்பி ஆள் போறாரு"}}
	if card and t < IN + 600.0:
		return {"tag": "E07_card", "card": card, "label": {"en": "Lobby camera's card log: #07 at the office door, 9:40 PM", "ta": "லாபி கேமரா கார்டு பதிவு: ஆஃபீஸ் கதவுல #07, இரவு 9:40"}}
	return {"tag": "dvr_screen", "card": card, "label": {"en": "Kathir's screen: the building's lobby camera", "ta": "கதிர் ஸ்கிரீன்: கட்டிடத்து லாபி கேமரா"}}


# ---- that night ----
func _along(path: Array, s: float) -> Vector3:
	if s < path[0][0] or s > path[-1][0]:
		return Vector3.INF
	for i in range(1, path.size()):
		if s <= path[i][0]:
			var k: float = (s - path[i - 1][0]) / (path[i][0] - path[i - 1][0])
			return (path[i - 1][1] as Vector3).lerp(path[i][1], k)
	return path[-1][1]


func _man_at() -> Vector3:
	if t < IN + 40.0:
		return _along(PATH_IN, t - IN)
	var back: float = PATH_IN[-1][0] - (t - OUT)       # the way he came, the other way round
	return _along(PATH_IN, back)


func _watch_at() -> Vector3:
	var out := 21.0 * 3600 + 2290.0           # 21:38:10 up from his chair to the gate (the tea boy), 21:46 back
	var back := 21.0 * 3600 + 2760.0
	if t < out or t >= back + 6.0:
		return CHAIR
	if t < out + 6.0:
		return CHAIR.lerp(GATE, (t - out) / 6.0)
	if t < back:
		return GATE
	return GATE.lerp(CHAIR, (t - back) / 6.0)


func _pose(a: Node3D, at: Vector3, prev: Vector3, rest: String, look: Vector3) -> void:
	a.visible = at != Vector3.INF
	if not a.visible:
		return
	a.floor_y = at.y
	a.global_position = at
	var d := at - prev
	d.y = 0.0
	if d.length() > 0.004:
		a.rotation.y = atan2(d.x, d.z)
		_anim(a, "Walk")
	else:
		_anim(a, rest)
		if rest != "Sit":
			a.rotation.y = atan2(look.x - at.x, look.z - at.z)
	if a.anim:
		a.anim.speed_scale = (SPEEDS[speed_i] if playing else 0.0) * (0.9 if a.anim.current_animation == "Walk" else 1.0)


## The clip, at once when the footage is paused or jumped (a blend at speed 0 never finishes).
func _anim(a: Node3D, name: String) -> void:
	a.seated = name.begins_with("Sit")
	if a.anim and a.anim.has_animation(name) and a.anim.current_animation != name:
		a.anim.play(name, 0.25 if playing and not _drag else 0.0)
		a.anim.advance(0.0)


# ---- the set ----
func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(704, 528)                   # (a DVR's D1-ish picture, scaled up soft)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	if ResourceLoader.exists(ROOM):
		var room := (load(ROOM) as PackedScene).instantiate() as Node3D
		_vp.add_child(room)
		for e in room.find_children("Light_*", "", true, false):
			var l := OmniLight3D.new()                   # the tube lights, on (the power held that night)
			l.omni_range = 7.0
			l.light_energy = 1.0
			l.light_color = Color(0.95, 0.98, 1.0)
			(e as Node3D).add_child(l)
	var street := OmniLight3D.new()                     # the sodium street light through the gate
	street.position = Vector3(0, 3.0, 7.5)
	street.omni_range = 9.0
	street.light_energy = 1.2
	street.light_color = Color(1.0, 0.65, 0.3)
	_vp.add_child(street)
	_cam = Camera3D.new()                               # high on the wall, looking down at the gate
	_cam.fov = 74.0
	_vp.add_child(_cam)
	var at := Vector3(3.75, 3.0, -1.9)                  # (on the right wall past the lift: the gate, the chair, the stair)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(-1.4, 0.6, 3.2) - at, Vector3.UP), at)
	_cam.current = true
	_watch = Actor.new()
	_vp.add_child(_watch)
	_watch.setup("story_muniyandi", "muniyandi", Callable())
	_man = Actor.new()
	_vp.add_child(_man)
	_man.setup("crowd_m4", "pandi", Callable(), Color(0.05, 0.04, 0.035))
	_cap(_man)
	_feed = TextureRect.new()
	_feed.texture = _vp.get_texture()
	_feed.stretch_mode = TextureRect.STRETCH_SCALE
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = CCTV
	_feed.material = sm
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)


## A dark cotton cap on his head bone: the brim forward, over his face from a camera above.
func _cap(a: Node3D) -> void:
	if a.model == null:
		return
	var sk: Array = a.model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	var s := sk[0] as Skeleton3D
	var head := -1
	for i in s.get_bone_count():
		var n := s.get_bone_name(i).to_lower()
		if n.contains("head") and not n.contains("end"):
			head = i
			break
	if head < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = head
	s.add_child(ba)
	var cap := Node3D.new()
	ba.add_child(cap)
	var rest := s.get_bone_global_rest(head)
	cap.transform = Transform3D(rest.basis.inverse(), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, 0.13, -0.005))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.07, 0.08, 0.1)
	cloth.roughness = 0.9
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.105
	sph.height = 0.12
	sph.is_hemisphere = true
	crown.mesh = sph
	crown.material_override = cloth
	crown.scale = Vector3(1.0, 0.9, 1.08)
	cap.add_child(crown)
	var brim := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.012, 0.09)
	brim.mesh = bm
	brim.material_override = cloth
	brim.position = Vector3(0, 0.0, 0.135)
	brim.rotation.x = 0.12
	cap.add_child(brim)


const CCTV := """
shader_type canvas_item;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 + 0.06 * dot(uv, uv);                     // the cheap lens's barrel
	uv += 0.5;
	vec3 c = texture(TEXTURE, uv).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(g), c, 0.22);                          // night: nearly grey
	c = (c - 0.5) * 1.15 + 0.53;
	c += (h(floor(UV * vec2(704.0, 528.0)) + t) - 0.5) * 0.09;    // the sensor's grain
	c *= 0.93 + 0.07 * sin(UV.y * 528.0 * 3.14159);
	c *= 1.0 - 0.55 * dot(UV - 0.5, UV - 0.5);          // darker corners
	float roll = fract(t * 0.07);
	c += 0.035 * smoothstep(0.03, 0.0, abs(UV.y - roll));
	COLOR = vec4(c, 1.0);
}
"""


# ---- layout ----
func _monitor() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x * 0.72, (vs.y - 170.0) * 4.0 / 3.0)
	return Rect2(vs.x * 0.5 - w * 0.5, 50.0, w, w * 0.75)


func _bar() -> Rect2:
	var m := _monitor()
	return Rect2(m.position.x, m.end.y + 34.0, m.size.x, 14.0)


# ---- input ----
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed and _bar().grow(10.0).has_point(e.position)
		if _drag:
			_seek(e.position.x)
	elif e is InputEventMouseMotion and _drag:
		_seek(e.position.x)
	accept_event()


func _seek(x: float) -> void:
	var b := _bar()
	t = lerpf(T0, T1, clampf((x - b.position.x) / b.size.x, 0.0, 1.0))


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	match e.keycode:
		KEY_SPACE:
			playing = not playing
		KEY_LEFT:
			t = maxf(t - 10.0, T0)
		KEY_RIGHT:
			t = minf(t + 10.0, T1)
		KEY_1, KEY_2, KEY_3:
			speed_i = e.keycode - KEY_1
			playing = true
		KEY_E, KEY_ESCAPE:
			if e.echo:
				return
			close()
			closed.emit()
		_:
			return
	get_viewport().set_input_as_handled()


var _prev_man := Vector3.INF
var _prev_watch := Vector3.INF


func _process(dt: float) -> void:
	if not visible:
		return
	if playing and not _drag:
		t = minf(t + dt * SPEEDS[speed_i], T1)
		if t >= T1:
			playing = false
	_noise += dt
	if _vp:
		var mp := _man_at()
		var wp := _watch_at()
		_pose(_man, mp, _prev_man if _prev_man != Vector3.INF else mp, "Idle", Vector3(0, 0, 10))
		_pose(_watch, wp, _prev_watch if _prev_watch != Vector3.INF else wp, "Sit" if wp == CHAIR else "Idle", Vector3(0.6, 0, 9.0))
		if wp == CHAIR:
			_watch.rotation.y = -PI / 2.0 + PI          # (his chair faces across the lobby, to the gate side)
		_prev_man = mp
		_prev_watch = wp
		var f := _monitor().grow(-18.0)
		_feed.position = f.position
		_feed.size = f.size
		_over.position = f.position
		_over.size = f.size
		(_feed.material as ShaderMaterial).set_shader_parameter("t", _noise)
		_over.queue_redraw()
	queue_redraw()


# ---- drawing ----
func _text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	ci.draw_string(font, pos, s, align, w, size, col)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.065, 0.06))            # Kathir's dark counter
	var m := _monitor()
	draw_rect(m.grow(16.0), Color(0.05, 0.05, 0.055))                       # the bezel
	draw_rect(m, Color(0.02, 0.02, 0.02))
	var b := _bar()                                                          # the timeline under the screen
	draw_rect(b, Color(0.2, 0.2, 0.22))
	var k := (t - T0) / (T1 - T0)
	draw_rect(Rect2(b.position, Vector2(b.size.x * k, b.size.y)), Color(0.75, 0.3, 0.25))
	draw_circle(Vector2(b.position.x + b.size.x * k, b.get_center().y), 10.0, Color(0.95, 0.95, 0.95))
	for mark in [21.5, 21.75, 22.0]:
		var x: float = b.position.x + b.size.x * (mark * 3600.0 - T0) / (T1 - T0)
		_text(self, Vector2(x - 40, b.position.y - 6), "%d:%02d PM" % [int(mark) - 12, int(fmod(mark, 1.0) * 60.0)], 13, Color(1, 1, 1, 0.5), 80.0, HORIZONTAL_ALIGNMENT_CENTER)
	_text(self, Vector2(b.position.x, b.end.y + 26.0), ("▶ ×%d" % int(SPEEDS[speed_i])) if playing else "❚❚", 16, Color(1, 1, 1, 0.8))
	_text(self, Vector2(0, vs.y - 18.0), L("Space: play / pause  ·  ← →: ten seconds  ·  1 2 3: speed  ·  drag the bar  ·  P: your phone  ·  E: step back",
		"Space: ஓட்டு / நிறுத்து  ·  ← →: பத்து வினாடி  ·  1 2 3: வேகம்  ·  கோட்ட இழுங்க  ·  P: உங்க ஃபோன்  ·  E: பின்னால"),
		14, Color(1, 1, 1, 0.45), vs.x, HORIZONTAL_ALIGNMENT_CENTER)


## The recorder's own writing over its picture: channel, clock, its name, the card log.
func _draw_over() -> void:
	var sz := _over.size
	var ov := Color(0.95, 0.95, 0.95)
	var sh := Color(0, 0, 0, 0.6)
	var rows := [[Vector2(12, 26), "CH02  LOBBY", HORIZONTAL_ALIGNMENT_LEFT, 18], [Vector2(0, 26), "TUE  " + hms(t), HORIZONTAL_ALIGNMENT_RIGHT, 18],
		[Vector2(0, sz.y - 12), SITE, HORIZONTAL_ALIGNMENT_RIGHT, 14]]
	var shown := 0
	for i in range(card_log.size() - 1, -1, -1):
		if card_log[i][0] <= t and shown < 2:
			rows.append([Vector2(12, sz.y - 34 + 20.0 * (1 - shown) - 20.0), "%s  %s  CARD %s  %s" % [hms(card_log[i][0]), card_log[i][1], card_log[i][2], card_log[i][3]], HORIZONTAL_ALIGNMENT_LEFT, 14])
			shown += 1
	for r in rows:
		var w: float = sz.x - 12.0 if r[2] == HORIZONTAL_ALIGNMENT_RIGHT else -1.0
		_text(_over, r[0] + Vector2(1, 1), r[1], r[3], sh, w, r[2])
		_text(_over, r[0], r[1], r[3], ov, w, r[2])
