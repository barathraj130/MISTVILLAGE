extends Control
## Title screen: drive up from Coimbatore, or start straight at The Mist Village.
## Keyboard: ↑/↓ to choose, Enter to start. Mouse works too.

const DRIVE_SCENE := "res://scenes/drive.tscn"
const RESORT_SCENE := "res://scenes/main.tscn"
const BACKGROUND := "res://assets/ui/menu_background.jpg"

var _buttons: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	if Engine.has_meta("arrived_by_jeep"):
		Engine.remove_meta("arrived_by_jeep")
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	if ResourceLoader.exists(BACKGROUND):
		bg.texture = load(BACKGROUND)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.75, 0.75, 0.78)
	add_child(bg)
	# slow drift so the title screen feels alive
	var tw := create_tween().set_loops()
	tw.tween_property(bg, "scale", Vector2(1.06, 1.06), 20.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bg, "scale", Vector2(1.0, 1.0), 20.0).set_trans(Tween.TRANS_SINE)
	bg.pivot_offset = get_viewport_rect().size * 0.5

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_text(box, "THE MIST VILLAGE", 64, Color(0.98, 0.93, 0.84))
	_text(box, "K O T A G I R I   ·   N I L G I R I S", 18, Color(0.9, 0.86, 0.78))
	_text(box, "Where the mist slows you down.", 20, Color(0.9, 0.88, 0.82))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)
	if FileAccess.file_exists("user://savegame.json"):
		_button(box, "Continue your journey", "Pick up where you saved (F5, or automatically every few minutes)",
			func():
				Engine.set_meta("continue_game", true)
				_go(DRIVE_SCENE))
	if FileAccess.file_exists("user://story_save.json"):
		_button(box, "Continue the story", "From the morning it was last saved (every morning, after a night's sleep)",
			func():
				Engine.set_meta("story", true)
				Engine.set_meta("story_continue", true)
				_go("res://scenes/city_test.tscn"))
	_button(box, "Story", "Part 1, The Wrong Accusation, from the beginning. Enter: next line, T: English / தமிழ்",
		func():
			Engine.set_meta("story", true)
			_go("res://scenes/city_test.tscn"))
	_button(box, "Drive up from Coimbatore", "The real road via NH181 and the Kotagiri ghat, ending at your resort. Get out and walk in",
		func(): _go(DRIVE_SCENE))
	_button(box, "Start at The Mist Village", "Just the resort, with its intro film and day/night",
		func(): _go(RESORT_SCENE))
	_button(box, "Quit", "", func(): get_tree().quit())
	_buttons[0].grab_focus()
	_test_hooks()

	var credit := Label.new()
	credit.text = "Road map data © OpenStreetMap contributors (ODbL) · Elevation: SRTM / Mapzen terrain tiles · Textures: ambientCG · Models: Poly Haven, Kenney (CC0)"
	credit.add_theme_font_size_override("font_size", 12)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(credit)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)


func _text(parent: Control, t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _button(parent: Control, title: String, hint: String, action: Callable) -> void:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size = Vector2(440, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.tooltip_text = hint
	b.pressed.connect(action)
	parent.add_child(b)
	_buttons.append(b)
	if hint != "":
		var h := _text(parent, hint, 13, Color(0.92, 0.9, 0.85, 0.85))
		h.custom_minimum_size = Vector2(440, 0)


## (testing an exported build, which can't be given a scene on the command line) --menushot=FILE: a picture of
## this screen; --play=story|drive|resort: start it as its button would (the rest of the arguments go on with it).
func _test_hooks() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			await get_tree().create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(a.get_slice("=", 1), 0.85)
			print("MENUSHOT %s" % a.get_slice("=", 1))
		elif a.begins_with("--play="):
			match a.get_slice("=", 1):
				"story":
					Engine.set_meta("story", true)
					_go("res://scenes/city_test.tscn")
				"drive":
					_go(DRIVE_SCENE)
				"resort":
					_go(RESORT_SCENE)


func _go(scene: String) -> void:
	for b in _buttons:
		b.disabled = true
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))
