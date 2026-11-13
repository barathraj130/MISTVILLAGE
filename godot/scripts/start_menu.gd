extends Control
## Title screen: Continue, New game, Settings, Credits, Quit, in a column down the left (the background picture
## carries the title). Keyboard: ↑/↓ to choose, Enter to start. Mouse works too.
## --dev adds the test starts: the drive up from Coimbatore and the resort alone.

const DRIVE_SCENE := "res://scenes/drive.tscn"
const RESORT_SCENE := "res://scenes/main.tscn"
const BACKGROUND := "res://assets/ui/menu_background.jpg"
const Style := preload("res://scripts/ui/hud_style.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const CREDITS := [
	["Road map data", "© OpenStreetMap contributors (ODbL)"],
	["Elevation", "SRTM / Mapzen terrain tiles"],
	["Textures", "ambientCG (CC0)"],
	["Models", "Poly Haven, Kenney (CC0)"],
	["People", "MakeHuman / MPFB2 (CC0 assets)"],
	["Type", "Inter and Noto Sans Tamil (SIL Open Font License)"],
	["Engine", "Godot Engine (MIT)"],
]

var _buttons: Array = []
var _box: VBoxContainer
var _new_armed := false


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
	bg.modulate = Color(0.88, 0.88, 0.9)
	add_child(bg)
	# slow drift so the title screen feels alive
	var tw := create_tween().set_loops()
	tw.tween_property(bg, "scale", Vector2(1.06, 1.06), 20.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(bg, "scale", Vector2(1.0, 1.0), 20.0).set_trans(Tween.TRANS_SINE)
	bg.pivot_offset = get_viewport_rect().size * 0.5

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.12)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var k := Style.s(self)
	theme = SettingsScreen.make_theme(k)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(12 * k))
	box.position = Vector2(get_viewport_rect().size.x * 0.06, get_viewport_rect().size.y * 0.42)
	add_child(box)
	_box = box
	var story_save := FileAccess.file_exists("user://story_save.json")
	if story_save:
		_button(box, "Continue", "From the morning it was last saved (every morning, after a night's sleep)",
			func():
				Engine.set_meta("story", true)
				Engine.set_meta("story_continue", true)
				_go("res://scenes/city_test.tscn"))
	_button(box, "New game", "Part 1, The Wrong Accusation, from the beginning", func():
		if story_save and not _new_armed:          # (starting over replaces the saved story at the first morning)
			_new_armed = true
			_buttons[1].text = "Start over? Press again"
			return
		Engine.set_meta("story", true)
		_go("res://scenes/city_test.tscn"))
	if "--dev" in OS.get_cmdline_user_args():
		if FileAccess.file_exists("user://savegame.json"):
			_button(box, "Continue the drive", "", func():
				Engine.set_meta("continue_game", true)
				_go(DRIVE_SCENE))
		_button(box, "Drive up from Coimbatore", "", func(): _go(DRIVE_SCENE))
		_button(box, "The Mist Village (resort)", "", func(): _go(RESORT_SCENE))
	_button(box, "Settings", "", _open_settings)
	_button(box, "Credits", "", _open_credits)
	_button(box, "Quit", "", func(): get_tree().quit())
	_buttons[0].grab_focus()
	_test_hooks()


func _open_settings() -> void:
	_box.visible = false
	var st := SettingsScreen.new()
	st.closed.connect(func():
		_box.visible = true
		_buttons[_buttons.size() - 3].grab_focus())
	add_child(st)


func _open_credits() -> void:
	_box.visible = false
	var k := Style.s(self)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.6)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(scrim)
	var panel := PanelContainer.new()
	layer.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, int(36 * k))
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(12 * k))
	m.add_child(v)
	var t := Label.new()
	t.text = "Credits"
	t.add_theme_font_size_override("font_size", int(34 * k))
	t.add_theme_font_override("font", Style.font(600))
	v.add_child(t)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", int(36 * k))
	g.add_theme_constant_override("v_separation", int(10 * k))
	v.add_child(g)
	for row in CREDITS:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Style.DIM)
		g.add_child(a)
		var b := Label.new()
		b.text = row[1]
		g.add_child(b)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200 * k, 48 * k)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)
	var close := func():
		layer.queue_free()
		_box.visible = true
		_buttons[_buttons.size() - 2].grab_focus()
	back.pressed.connect(close)
	back.grab_focus()
	panel.reset_size()
	panel.position = (get_viewport_rect().size - panel.size) * 0.5


func _button(parent: Control, title: String, hint: String, action: Callable) -> void:
	var k := Style.s(self)
	var b := Button.new()
	b.text = title
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380 * k, 54 * k)
	b.add_theme_font_size_override("font_size", int(23 * k))
	b.add_theme_font_override("font", Style.font(500))
	b.tooltip_text = hint
	b.pressed.connect(action)
	parent.add_child(b)
	_buttons.append(b)


## (testing an exported build, which can't be given a scene on the command line) --menushot=FILE: a picture of
## this screen; --play=story|drive|resort: start it as its button would (the rest of the arguments go on with it).
func _test_hooks() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			if "--menuopen=settings" in OS.get_cmdline_user_args():
				_open_settings()
			elif "--menuopen=credits" in OS.get_cmdline_user_args():
				_open_credits()
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
