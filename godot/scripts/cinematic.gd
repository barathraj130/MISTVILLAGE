extends Node
## Plays the 10-shot, 45-second camera film exported from Blender, then the title card.
## Frames are sampled once per Blender frame; this interpolates between them and
## hard-cuts where the shot number changes, exactly like the timeline markers.

signal finished

const HOLD_AFTER_END := 1.5          # seconds to linger on the title

var playing := false
var camera: Camera3D
var frames: Array = []
var fps := 24.0
var time := 0.0
var title_at := 41.0
var fade_in := Vector2(42.0, 43.2)
var _ui: CanvasLayer
var _title: VBoxContainer
var _hint: Label


func setup(cine: Dictionary, title: Dictionary) -> void:
	frames = cine.get("frames", [])
	fps = float(cine.get("fps", 24))
	camera = Camera3D.new()
	camera.near = 0.1
	camera.far = 40000.0
	add_child(camera)

	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	for top in [true, false]:           # letterbox
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.9
		bar.anchor_bottom = 0.1 if top else 1.0
		_ui.add_child(bar)

	_title = VBoxContainer.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	_ui.add_child(_title)
	var lines: Array = title.get("lines", ["THE MIST VILLAGE", "KOTAGIRI · NILGIRIS", "Where the mist slows you down."])
	var sizes := [56, 18, 22]
	for i in lines.size():
		if i == 2:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 48)
			_title.add_child(gap)
		var l := Label.new()
		l.text = lines[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", sizes[mini(i, 2)])
		l.add_theme_color_override("font_color", Color(0.98, 0.93, 0.84))
		_title.add_child(l)

	_hint = Label.new()
	_hint.text = "Space / Enter: skip"
	_hint.modulate.a = 0.6
	_ui.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)

	title_at = float(title.get("show_at_s", 41.0))
	var fi: Array = title.get("fade_in_s", [42.0, 43.2])
	fade_in = Vector2(fi[0], fi[1])


func play() -> void:
	if frames.size() < 2:
		finished.emit()
		return
	time = 0.0
	playing = true
	_ui.visible = true
	camera.make_current()
	_apply(0.0)


func stop() -> void:
	playing = false
	_ui.visible = false
	finished.emit()


func _process(delta: float) -> void:
	if not playing:
		return
	time += delta
	if time * fps >= frames.size() - 1 + HOLD_AFTER_END * fps:
		stop()
		return
	_apply(time)


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("skip_intro"):
		get_viewport().set_input_as_handled()
		stop()


func _apply(t: float) -> void:
	var f := minf(t * fps, frames.size() - 1.001)
	var i := int(f)
	var k := f - i
	var a: Array = frames[i]
	var b: Array = frames[i + 1]
	if a[0] != b[0]:
		k = 0.0                          # cut between shots
	camera.position = Vector3(a[1], a[2], a[3]).lerp(Vector3(b[1], b[2], b[3]), k)
	var qa := Quaternion(a[4], a[5], a[6], a[7]).normalized()
	var qb := Quaternion(b[4], b[5], b[6], b[7]).normalized()
	camera.quaternion = qa.slerp(qb, k)
	camera.fov = lerpf(a[8], b[8], k)
	_title.modulate.a = clampf((t - fade_in.x) / (fade_in.y - fade_in.x), 0.0, 1.0)
	_hint.visible = t < title_at
