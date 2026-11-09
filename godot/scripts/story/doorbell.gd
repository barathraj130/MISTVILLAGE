extends Control
## Ashwin's doorbell camera (STORY_BIBLE.md E05): the landlord's rule, a camera in the door frame of every flat. On the
## night of the delivery it really records him: when he's at Ashwin's door (story.gd, the step with "doorbell") the
## camera in the frame beside Ashwin takes a short clip of what it sees, him at the door with the parcel, and the
## clock it was then (the time he actually got there, late or not). Days later the landlady, Lakshmi aunty, opens
## her doorbell app on her tablet: the clips of the last seven days, that night's among them, and it plays. His
## phone's camera (P) takes a picture of the tablet (frame_tag: E05). Enter, E or Esc: she takes the tablet back.

signal closed

const DIR := "user://doorbell_e05"
const FRAMES := 8
const GAP := 0.45                          # seconds between the clip's frames
const SIZE := Vector2i(640, 480)
const APP := "Kaval Doorbell"              # (a made-up company: the landlord's cheap plan)
const Kit := preload("res://scripts/ui/ui_kit.gd")
const Hud := preload("res://scripts/ui/hud_style.gd")

var lang := "en"
var font: Font
var _frames: Array[ImageTexture] = []
var _meta := {}
var _t := 0.0
var _back: Control                         # the tablet and the app, under the clip
var _feed: TextureRect
var _over: Control                         # the clip's clock and the list, over it
var _play := true                          # the clip: playing, or held on a frame (Space; ← → a frame; drag the bar)
var _pos := 0.0                            # where in the clip, 0..1
var _drag := false
var _mouse := Vector2(-1, -1)


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


## The camera in the door frame at `from`, looking at `at`, records a few seconds into DIR (frames and the clock).
## The world's own picture (a SubViewport on the city's world), so it's what was really there.
func capture(host: Node, world: World3D, from: Vector3, at: Vector3, minute: float, day: int) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.world_3d = world
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 96.0                                       # (a doorbell's wide lens)
	cam.near = 0.05
	vp.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(DIR)
	for i in FRAMES:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png("%s/f%d.png" % [DIR, i])
		await host.get_tree().create_timer(GAP).timeout
	var f := FileAccess.open(DIR + "/meta.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"minute": minute, "day": day, "frames": FRAMES}))
	vp.queue_free()
	print("DOORBELL recorded %d frames, day %d %s" % [FRAMES, day, clock(minute)])


static func has_clip() -> bool:
	return FileAccess.file_exists(DIR + "/meta.json")


static func clock(minute: float) -> String:
	var m := int(minute)
	return "%d:%02d %s" % [((m / 60) + 11) % 12 + 1, m % 60, "PM" if m >= 720 else "AM"]


func open(language: String) -> void:
	lang = language
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_meta = {}
	_frames.clear()
	var f := FileAccess.open(DIR + "/meta.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_meta = d
	for i in int(_meta.get("frames", 0)):
		var img := Image.load_from_file(ProjectSettings.globalize_path("%s/f%d.png" % [DIR, i]))
		if img:
			_frames.append(ImageTexture.create_from_image(img))
	if _feed == null:
		_back = Control.new()
		_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.set_anchors_preset(Control.PRESET_FULL_RECT)
		_back.draw.connect(_draw_back)
		add_child(_back)
		_feed = TextureRect.new()
		_feed.stretch_mode = TextureRect.STRETCH_SCALE
		_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = LENS
		_feed.material = sm
		add_child(_feed)
		_over = Control.new()
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.set_anchors_preset(Control.PRESET_FULL_RECT)
		_over.draw.connect(_draw_over)
		add_child(_over)
	_t = 0.0
	_pos = 0.0
	_play = true
	visible = true


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


## What a picture of the tablet shows: that night's clip, him at the door, and its clock.
func frame_tag() -> Dictionary:
	var at := clock(float(_meta.get("minute", 1341.0)))
	return {"tag": "E05", "label": {"en": "Doorbell, Saravanampatti: me at Ashwin's door, Day %d %s" % [int(_meta.get("day", 1)), at],
		"ta": "டோர்பெல், சரவணம்பட்டி: அஷ்வின் வாசல்ல நான், நாள் %d %s" % [int(_meta.get("day", 1)), at]}}


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if _play and not _drag:
		_pos = fmod(_pos + dt / (GAP * FRAMES), 1.0)
	var r := _screen()
	_feed.position = r.position
	_feed.size = r.size
	if not _frames.is_empty():
		_feed.texture = _frames[mini(int(_pos * _frames.size()), _frames.size() - 1)]
	(_feed.material as ShaderMaterial).set_shader_parameter("t", _t)
	_back.queue_redraw()
	_over.queue_redraw()
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_key_pressed(KEY_ESCAPE):
		close()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse = e.position
		if _drag:
			_seek(e.position.x)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed and _scrub().grow(12.0 * _k()).has_point(e.position)
		if _drag:
			_seek(e.position.x)
		elif e.pressed and _play_btn().has_point(e.position):
			_play = not _play
	accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	var n := maxf(float(_frames.size()), 1.0)
	match e.keycode:
		KEY_SPACE:
			_play = not _play
		KEY_LEFT:
			_play = false
			_pos = fposmod(floorf(_pos * n) / n - 1.0 / n, 1.0)
		KEY_RIGHT:
			_play = false
			_pos = fposmod(floorf(_pos * n) / n + 1.0 / n, 1.0)
		_:
			return
	get_viewport().set_input_as_handled()


func _seek(x: float) -> void:
	var b := _scrub()
	_pos = clampf((x - b.position.x) / b.size.x, 0.0, 0.999)


# ---- the tablet ----
## Lakshmi aunty's tablet, in landscape, with the doorbell app: its bar (the app, the camera), the clip with its
## controls under it, the week's clips on the right.
func _k() -> float:
	return Hud.s(self)


func _tablet() -> Rect2:
	var vs := get_viewport_rect().size
	var k := _k()
	var w := minf(vs.x - 120.0 * k, (vs.y - 150.0 * k) * 1.5)
	var h := w / 1.5
	return Rect2(vs.x * 0.5 - w * 0.5, (vs.y - h) * 0.5 - 16.0 * k, w, h)


func _app() -> Rect2:
	return _tablet().grow(-22.0 * _k())


func _screen() -> Rect2:                                 # the clip, on the left of the app
	var a := _app()
	var k := _k()
	var w := a.size.x * 0.64
	var h := minf(w * 0.75, a.size.y - 64.0 * k - 104.0 * k)
	return Rect2(a.position.x + 20.0 * k, a.position.y + 64.0 * k, h * 4.0 / 3.0, h)


func _scrub() -> Rect2:
	var s := _screen()
	var k := _k()
	return Rect2(s.position.x + 56.0 * k, s.end.y + 26.0 * k, s.size.x - 56.0 * k, 6.0 * k)


func _play_btn() -> Rect2:
	var s := _screen()
	var k := _k()
	return Rect2(s.position.x, s.end.y + 10.0 * k, 40.0 * k, 38.0 * k)


func _draw_back() -> void:
	var c := _back
	var k := _k()
	var tb := _tablet()
	c.draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.02, 0.02, 0.03, 0.62))
	var bez := _rounded(Color(0.06, 0.06, 0.07), 30.0 * k)                            # the tablet, in her hands
	bez.shadow_color = Color(0, 0, 0, 0.5)
	bez.shadow_size = int(24.0 * k)
	bez.border_color = Color(1, 1, 1, 0.08)
	bez.set_border_width_all(maxi(1, int(k)))
	c.draw_style_box(bez, tb)
	c.draw_circle(Vector2(tb.position.x + 11.0 * k, tb.get_center().y), 3.0 * k, Color(0.15, 0.15, 0.17))   # its front camera
	var a := _app()
	c.draw_style_box(_rounded(Color(0.09, 0.1, 0.12), 12.0 * k), a)                  # the app, dark
	c.draw_rect(Rect2(a.position + Vector2(0, 12.0 * k), Vector2(a.size.x, 40.0 * k)), Color(0.11, 0.125, 0.15))
	c.draw_style_box(_rounded(Color(0.11, 0.125, 0.15), 12.0 * k), Rect2(a.position, Vector2(a.size.x, 52.0 * k)))
	var logo := a.position + Vector2(30.0 * k, 26.0 * k)                             # its shield
	var sh := PackedVector2Array([logo + Vector2(-11, -12) * k, logo + Vector2(11, -12) * k, logo + Vector2(11, 2) * k,
		logo + Vector2(0, 13) * k, logo + Vector2(-11, 2) * k])
	c.draw_colored_polygon(sh, Color(0.18, 0.6, 0.72))
	Hud.text(c, logo + Vector2(-11.0 * k, 5.0 * k), "K", 13.0 * k, Color.WHITE, 700, HORIZONTAL_ALIGNMENT_CENTER, 22.0 * k)
	Hud.text(c, a.position + Vector2(52.0 * k, 33.0 * k), APP, 18.0 * k, Kit.INK, 700)
	Hud.text(c, a.position + Vector2(0, 33.0 * k), L("Front door · 1st floor (Ashwin)", "முன் கதவு · 1வது மாடி (அஷ்வின்)"), 14.0 * k, Kit.DIM, 500,
		HORIZONTAL_ALIGNMENT_RIGHT, a.size.x - 20.0 * k)
	var s := _screen()
	c.draw_rect(s.grow(1.0 * k), Color(0, 0, 0))


func _draw_over() -> void:
	var c := _over
	var k := _k()
	var a := _app()
	var s := _screen()
	if _frames.is_empty():
		c.draw_rect(s, Color(0.1, 0.1, 0.1))
		Hud.text(c, s.position + Vector2(0, s.size.y * 0.5), L("Clip not available", "கிளிப் இல்லை"), 18.0 * k, Kit.DIM, 500, HORIZONTAL_ALIGNMENT_CENTER, s.size.x)
	var day := int(_meta.get("day", 1))
	var m := float(_meta.get("minute", 1341.0))
	var secs := int(_pos * GAP * FRAMES)
	var stamp := "FRONT DOOR   DAY %d   %02d:%02d:%02d" % [day, int(m) / 60, int(m) % 60, 4 + secs]
	c.draw_rect(Rect2(s.position + Vector2(10, 10) * k, Vector2(Hud.width_of(stamp, 14.0 * k, 600) + 20.0 * k, 26.0 * k)), Color(0, 0, 0, 0.5))
	Hud.text(c, s.position + Vector2(20.0 * k, 28.0 * k), stamp, 14.0 * k, Color(1, 1, 1, 0.95), 600)
	var badge := Rect2(s.end.x - 110.0 * k, s.position.y + 10.0 * k, 100.0 * k, 26.0 * k)
	c.draw_style_box(_rounded(Color(0, 0, 0, 0.5), 13.0 * k), badge)
	c.draw_circle(badge.position + Vector2(14.0 * k, 13.0 * k), 4.5 * k, Kit.GREEN if _play else Kit.AMBER)
	Hud.text(c, badge.position + Vector2(26.0 * k, 18.0 * k), L("PLAYBACK", "பிளேபேக்"), 12.0 * k, Kit.INK, 700)
	# the controls: play / pause, the bar, the clip's time
	var pb := _play_btn()
	Kit.button(c, pb, "❚❚" if _play else "▶", k * 0.85, Kit.state_of(pb, _mouse), "secondary")
	var sb := _scrub()
	Kit.progress(c, sb, _pos, k, Color(0.18, 0.6, 0.72))
	c.draw_circle(Vector2(sb.position.x + sb.size.x * _pos, sb.get_center().y), 7.0 * k, Kit.INK)
	Hud.text(c, Vector2(sb.position.x, sb.end.y + 30.0 * k), L("Motion at the door", "வாசல்ல அசைவு") + "  ·  " + L("Day %d", "நாள் %d") % day + "  ·  " + clock(m),
		Kit.T_CAPTION * k, Kit.INK, 600)
	Hud.text(c, Vector2(sb.position.x, sb.end.y + 30.0 * k), "0:0%d / 0:0%d" % [secs, int(GAP * FRAMES)], Kit.T_CAPTION * k, Kit.DIM, 500,
		HORIZONTAL_ALIGNMENT_RIGHT, sb.size.x)
	# the week's clips, newest first; the plan keeps seven days
	var lx := s.end.x + 20.0 * k
	var lw := a.end.x - lx - 20.0 * k
	var ly := s.position.y
	Hud.text(c, Vector2(lx, ly + 14.0 * k), L("CLIPS · KEPT 7 DAYS", "கிளிப்கள் · 7 நாள்"), Kit.T_LABEL * k, Kit.DIM, 700)
	var rows := [[day + 5, "6:04 AM", L("Milk delivery", "பால் போடறவர்")], [day + 4, "7:52 PM", L("Courier", "கூரியர்")],
		[day + 2, "6:02 AM", L("Milk delivery", "பால் போடறவர்")], [day, clock(m), L("Motion at the door", "வாசல்ல அசைவு")],
		[day, "6:03 AM", L("Milk delivery", "பால் போடறவர்")]]
	var rh := 62.0 * k
	for i in rows.size():
		var r := Rect2(lx, ly + 30.0 * k + i * (rh + 8.0 * k), lw, rh)
		var on: bool = i == 3
		Kit.card(c, r, k, on, r.has_point(_mouse))
		var th := Rect2(r.position + Vector2(8, 8) * k, Vector2((rh - 16.0 * k) * 4.0 / 3.0, rh - 16.0 * k))
		if on and not _frames.is_empty():
			c.draw_texture_rect(_frames[0], th, false, Color(0.7, 0.7, 0.7))             # (that night's clip: its first frame)
		else:
			c.draw_rect(th, Color(0.16, 0.17, 0.2))
			c.draw_circle(th.get_center(), 6.0 * k, Color(1, 1, 1, 0.12))
		var tx := th.end.x + 12.0 * k
		Hud.text(c, Vector2(tx, r.position.y + 26.0 * k), "%s %d · %s" % [L("Day", "நாள்"), rows[i][0], rows[i][1]], Kit.T_CAPTION * k, Kit.INK if on else Kit.DIM, 600,
			HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 8.0 * k)
		Hud.text(c, Vector2(tx, r.position.y + 47.0 * k), str(rows[i][2]), Kit.T_LABEL * k, Kit.AMBER if on else Hud.fade(Kit.DIM, 0.8), 500,
			HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 8.0 * k)
	var ey := ly + 30.0 * k + rows.size() * (rh + 8.0 * k) + 20.0 * k
	c.draw_circle(Vector2(lx + 5.0 * k, ey - 5.0 * k), 4.0 * k, Kit.RED)
	Hud.text(c, Vector2(lx + 16.0 * k, ey), L("Oldest clip deletes tomorrow", "பழைய கிளிப் நாளைக்கு அழியும்"), Kit.T_LABEL * k, Kit.RED.lightened(0.15), 600,
		HORIZONTAL_ALIGNMENT_LEFT, lw - 16.0 * k)
	var tb := _tablet()
	Hud.text(c, Vector2(tb.position.x, tb.end.y + 30.0 * k), L("Space play / pause  ·  ← → a frame  ·  drag the bar  ·  P your phone's camera: a picture  ·  Enter give it back",
		"Space ஓட்டு / நிறுத்து  ·  ← → ஒரு ஃப்ரேம்  ·  கோட்ட இழுங்க  ·  ஃபோன் கேமராவுல P: படம்  ·  Enter திருப்பிக் குடுங்க"),
		Kit.T_LABEL * k, Hud.fade(Kit.INK, 0.8), 500, HORIZONTAL_ALIGNMENT_CENTER, tb.size.x)


func _rounded(col: Color, r: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r))
	return sb


const LENS := """
shader_type canvas_item;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV - 0.5;
	uv *= 1.0 - 0.12 * dot(uv, uv);                     // the wide lens bulges the middle
	uv += 0.5;
	vec3 c = texture(TEXTURE, uv).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(g), c, 0.12);                          // night: the infrared's grey
	c = pow(max(c, vec3(0.0)), vec3(0.55)) * 1.05;      // (its lamp lights the doorstep)
	c += (h(floor(UV * vec2(640.0, 480.0)) + floor(t * 12.0)) - 0.5) * 0.07;
	c *= 1.0 - 0.8 * dot(UV - 0.5, UV - 0.5);
	COLOR = vec4(c, 1.0);
}
"""
