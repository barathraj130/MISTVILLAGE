extends Control
## The settings screen (from the start menu): graphics, the window, the volume, mouse look and steering, the story's
## language. Every change is saved at once (graphics.gd, settings.gd: user://settings.cfg) and the window and volume
## change at once; the graphics preset takes effect when a world loads (F2 still steps through them in one).
## Esc or Back closes it ("closed").

signal closed

const Graphics := preload("res://scripts/graphics.gd")
const Settings := preload("res://scripts/settings.gd")
const Jeep := preload("res://scripts/drive/jeep.gd")
const Style := preload("res://scripts/ui/hud_style.gd")

var _first: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var k := Style.s(self)
	theme = make_theme(k)
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, int(36 * k))
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(14 * k))
	m.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", int(34 * k))
	title.add_theme_font_override("font", Style.font(600))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(40 * k))
	grid.add_theme_constant_override("v_separation", int(14 * k))
	box.add_child(grid)

	_heading(grid, "Graphics", k)
	var names := []
	for p in Graphics.ORDER:
		names.append(p.capitalize() + ("  (suggested)" if p == Graphics.default_preset() else ""))
	_first = _choice(grid, "Quality", names, Graphics.ORDER.find(Graphics.preset()), func(i: int):
		Graphics.current = Graphics.ORDER[i]
		Graphics.save_value("preset", Graphics.current), k)
	_toggle(grid, "Fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, func(on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		Graphics.save_value("fullscreen", on), k)
	_toggle(grid, "VSync", DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, func(on: bool):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
		Graphics.save_value("vsync", on), k)

	_heading(grid, "Sound", k)
	_slider(grid, "Volume", 0, 100, 5, float(Settings.get_value("audio", "master", 1.0)) * 100.0, func(v: float):
		Settings.set_value("audio", "master", v / 100.0)
		Settings.apply_audio(), k)

	_heading(grid, "Controls", k)
	_slider(grid, "Mouse look", 50, 200, 10, Settings.look() * 100.0, func(v: float):
		Settings.set_value("controls", "look_sens", v / 100.0), k)
	_slider(grid, "Steering", 40, 150, 10, float(Settings.get_value("driving", "steer_sens", Jeep.steer_sens)) * 100.0,
		func(v: float):
			Jeep.steer_sens = v / 100.0
			Settings.set_value("driving", "steer_sens", v / 100.0), k)

	_heading(grid, "Language", k)
	var langs := ["auto", "en", "ta"]
	_choice(grid, "Story", ["As this computer (%s)" % ("தமிழ்" if OS.get_locale_language() == "ta" else "English"), "English", "தமிழ்"],
		maxi(langs.find(str(Settings.get_value("game", "lang", "auto"))), 0), func(i: int):
			Settings.set_value("game", "lang", langs[i]), k)

	var note := Label.new()
	note.text = "Quality takes effect when the game loads (F2 changes it while playing). T switches the language in the story."
	note.add_theme_color_override("font_color", Style.DIM)
	note.add_theme_font_size_override("font_size", int(15 * k))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(620 * k, 0)
	box.add_child(note)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200 * k, 48 * k)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_close)
	box.add_child(back)
	_first.grab_focus()
	panel.reset_size()
	panel.position = (get_viewport_rect().size - panel.size) * 0.5
	_test_hooks()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _heading(grid: GridContainer, t: String, k: float) -> void:
	for i in 2:
		var l := Label.new()
		l.text = t.to_upper() if i == 0 else ""
		l.add_theme_color_override("font_color", Style.AMBER)
		l.add_theme_font_size_override("font_size", int(14 * k))
		l.add_theme_font_override("font", Style.font(600))
		grid.add_child(l)


func _label(grid: GridContainer, t: String, k: float) -> void:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(200 * k, 0)
	grid.add_child(l)


func _choice(grid: GridContainer, t: String, items: Array, sel: int, on: Callable, k: float) -> Control:
	_label(grid, t, k)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(sel)
	o.custom_minimum_size = Vector2(380 * k, 44 * k)
	o.item_selected.connect(on)
	grid.add_child(o)
	return o


func _toggle(grid: GridContainer, t: String, on: bool, cb: Callable, k: float) -> void:
	_label(grid, t, k)
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(cb)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(c)


func _slider(grid: GridContainer, t: String, lo: float, hi: float, step: float, v: float, cb: Callable, k: float) -> void:
	_label(grid, t, k)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(14 * k))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = clampf(snappedf(v, step), lo, hi)
	s.custom_minimum_size = Vector2(300 * k, 44 * k)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := Label.new()
	n.text = "%d%%" % roundi(s.value)
	n.custom_minimum_size = Vector2(66 * k, 0)
	s.value_changed.connect(func(x: float):
		n.text = "%d%%" % roundi(x)
		cb.call(x))
	row.add_child(s)
	row.add_child(n)
	grid.add_child(row)


## The look (the start menu uses it too): the HUD's type, dark panel and amber focus.
static func make_theme(k: float) -> Theme:
	var th := Theme.new()
	th.default_font = Style.font(400)
	th.default_font_size = int(19 * k)
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.07, 0.075, 0.085, 0.94)
	pb.set_corner_radius_all(int(12 * k))
	pb.border_color = Style.EDGE
	pb.set_border_width_all(1)
	th.set_stylebox("panel", "PanelContainer", pb)
	for cls in ["Button", "OptionButton"]:
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var b := StyleBoxFlat.new()
			b.bg_color = {"normal": Color(1, 1, 1, 0.07), "hover": Color(1, 1, 1, 0.13), "pressed": Color(1, 1, 1, 0.18),
				"focus": Color(0, 0, 0, 0), "disabled": Color(1, 1, 1, 0.03)}[st]
			b.set_corner_radius_all(int(8 * k))
			b.content_margin_left = 16 * k
			b.content_margin_right = 16 * k
			if st == "focus":
				b.border_color = Style.AMBER
				b.set_border_width_all(maxi(2, int(2 * k)))
			th.set_stylebox(st, cls, b)
		th.set_color("font_color", cls, Style.INK)
		th.set_color("font_hover_color", cls, Style.INK)
		th.set_color("font_focus_color", cls, Style.INK)
	th.set_color("font_color", "Label", Style.INK)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Style.AMBER
	focus.set_border_width_all(maxi(2, int(2 * k)))
	focus.set_corner_radius_all(int(8 * k))
	for cls in ["HSlider", "CheckButton"]:
		th.set_stylebox("focus", cls, focus)
	var track := StyleBoxFlat.new()
	track.bg_color = Style.FAINT
	track.set_corner_radius_all(int(3 * k))
	track.content_margin_top = 3 * k
	track.content_margin_bottom = 3 * k
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Style.AMBER
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return th


## (testing) --settingsshot=FILE: a picture of this screen.
func _test_hooks() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--settingsshot="):
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg(a.get_slice("=", 1), 0.85)
			print("SETTINGSSHOT %s" % a.get_slice("=", 1))
			get_tree().quit()
