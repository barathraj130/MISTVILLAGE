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

var lang := "en"
var font: Font
var _frames: Array[ImageTexture] = []
var _meta := {}
var _t := 0.0
var _back: Control                         # the tablet and the app, under the clip
var _feed: TextureRect
var _over: Control                         # the clip's clock and the list, over it


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
	var r := _screen()
	_feed.position = r.position
	_feed.size = r.size
	if not _frames.is_empty():
		_feed.texture = _frames[int(_t / GAP) % _frames.size()]
	(_feed.material as ShaderMaterial).set_shader_parameter("t", _t)
	_back.queue_redraw()
	_over.queue_redraw()
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_key_pressed(KEY_ESCAPE):
		close()


func _gui_input(e: InputEvent) -> void:
	accept_event()


# ---- the tablet ----
func _tablet() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x * 0.78, (vs.y - 120.0) * 1.5)
	return Rect2(vs.x * 0.5 - w * 0.5, vs.y * 0.5 - w / 3.0 - 20.0, w, w / 1.5)


func _screen() -> Rect2:                                 # the clip, on the left of the app
	var tb := _tablet().grow(-26.0)
	var w := tb.size.x * 0.64
	return Rect2(tb.position.x + 14.0, tb.position.y + 58.0, w, w * 0.75)


func _draw_back() -> void:
	var tb := _tablet()
	var c := _back
	c.draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.45))
	c.draw_style_box(_rounded(Color(0.07, 0.07, 0.08), 26.0), tb)                    # the tablet, in her hands
	var sc := tb.grow(-26.0)
	c.draw_rect(sc, Color(0.96, 0.96, 0.97))                                         # the app
	c.draw_rect(Rect2(sc.position, Vector2(sc.size.x, 44.0)), Color(0.12, 0.42, 0.55))
	c.draw_string(font, sc.position + Vector2(16, 29), APP, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
	c.draw_string(font, sc.position + Vector2(16, 29), L("Front door · 1st floor (Ashwin)", "முன் கதவு · 1வது மாடி (அஷ்வின்)"),
		HORIZONTAL_ALIGNMENT_RIGHT, sc.size.x - 32.0, 14, Color(0.85, 0.93, 0.97))


func _draw_over() -> void:
	var tb := _tablet()
	var c := _over
	var sc := tb.grow(-26.0)
	var s := _screen()
	if _frames.is_empty():
		c.draw_rect(s, Color(0.1, 0.1, 0.1))
		c.draw_string(font, s.position + Vector2(20, s.size.y * 0.5), L("Clip not available", "கிளிப் இல்லை"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8))
	var day := int(_meta.get("day", 1))
	var m := float(_meta.get("minute", 1341.0))
	var secs := int(fmod(_t, GAP * FRAMES))
	var stamp := "FRONT DOOR   DAY %d   %02d:%02d:%02d" % [day, int(m) / 60, int(m) % 60, 4 + secs]
	c.draw_rect(Rect2(s.position + Vector2(8, 8), Vector2(300, 24)), Color(0, 0, 0, 0.45))
	c.draw_string(font, s.position + Vector2(14, 26), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
	c.draw_circle(s.position + Vector2(s.size.x - 18, 22), 6.0, Color(0.9, 0.15, 0.1) if fmod(_t, 1.0) < 0.6 else Color(0.4, 0.1, 0.1))
	c.draw_string(font, s.position + Vector2(s.size.x - 60, 27), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var prog := fmod(_t, GAP * FRAMES) / (GAP * FRAMES)                              # the clip's bar
	c.draw_rect(Rect2(s.position.x, s.end.y + 10.0, s.size.x, 5.0), Color(0.8, 0.82, 0.85))
	c.draw_rect(Rect2(s.position.x, s.end.y + 10.0, s.size.x * prog, 5.0), Color(0.12, 0.42, 0.55))
	c.draw_string(font, Vector2(s.position.x, s.end.y + 36.0), L("Motion at the door · %s · 0:0%d" % [clock(float(_meta.get("minute", 1341.0))), int(GAP * FRAMES)],
		"வாசல்ல அசைவு · %s · 0:0%d" % [clock(float(_meta.get("minute", 1341.0))), int(GAP * FRAMES)]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 0.15, 0.18))
	# the week's clips, newest first; the plan keeps seven days
	var lx := s.end.x + 18.0
	var ly := s.position.y + 6.0
	var lw := sc.end.x - lx - 12.0
	c.draw_string(font, Vector2(lx, ly + 12.0), L("Clips · kept 7 days", "கிளிப்கள் · 7 நாள்"), HORIZONTAL_ALIGNMENT_LEFT, lw, 15, Color(0.3, 0.32, 0.36))
	var rows := [[day + 5, "6:04 AM", L("Milk delivery", "பால் போடறவர்")], [day + 4, "7:52 PM", L("Courier", "கூரியர்")],
		[day + 2, "6:02 AM", L("Milk delivery", "பால் போடறவர்")], [day, clock(float(_meta.get("minute", 1341.0))), L("Motion at the door", "வாசல்ல அசைவு")],
		[day, "6:03 AM", L("Milk delivery", "பால் போடறவர்")]]
	for i in rows.size():
		var y := ly + 30.0 + i * 52.0
		var on: bool = i == 3
		c.draw_rect(Rect2(lx, y, lw, 46.0), Color(0.86, 0.93, 0.96) if on else Color(0.92, 0.92, 0.94))
		c.draw_string(font, Vector2(lx + 10, y + 19), "%s %d · %s" % [L("Day", "நாள்"), rows[i][0], rows[i][1]], HORIZONTAL_ALIGNMENT_LEFT, lw - 20, 14, Color(0.1, 0.1, 0.12))
		c.draw_string(font, Vector2(lx + 10, y + 37), str(rows[i][2]), HORIZONTAL_ALIGNMENT_LEFT, lw - 20, 13, Color(0.35, 0.36, 0.4))
	c.draw_string(font, Vector2(lx, ly + 30.0 + rows.size() * 52.0 + 18.0), L("Oldest clip deletes tomorrow", "பழைய கிளிப் நாளைக்கு அழியும்"),
		HORIZONTAL_ALIGNMENT_LEFT, lw, 13, Color(0.75, 0.25, 0.15))
	c.draw_string(font, Vector2(tb.position.x, tb.end.y + 24.0), L("P on your phone's camera: a picture   ·   Enter: give it back", "ஃபோன் கேமராவுல P: படம்   ·   Enter: திருப்பிக் குடுங்க"),
		HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, 15, Color(1, 1, 1, 0.85))


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
