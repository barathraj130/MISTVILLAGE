extends SceneTree
## Paints the bus livery (the way bus mods do it: one image wrapped round the model) and the LED destination
## boards. Text is shaped by Godot, so Tamil comes out right.
##   godot --path godot -s tools/paint_livery.gd -- <out_dir>
## Layout of livery.png (4096 × 4096, S px per metre; must match tools/bus_tn.py):
##   left side (door side, nose at the image's left)   y 0 … SIDE
##   right side (nose at the image's right)             y SIDE … 2·SIDE
##   front (bus's right at the image's left)            x 0 … FW,     y 2·SIDE … 3·SIDE
##   rear  (bus's left at the image's left)             x FW … 2·FW,  y 2·SIDE … 3·SIDE
##   roof                                               y 3·SIDE … 4096

const L := 11.2
const W := 2.55
const H := 3.2
const S := 4096.0 / 11.2
const SIDE := 1170.0
const FW := 933.0

const CREAM := Color(0.99, 0.9, 0.62)
const ORANGE := Color(0.99, 0.66, 0.14)
const BLUE := Color(0.03, 0.1, 0.48)
const RED := Color(0.78, 0.07, 0.05)
const BLACK := Color(0.03, 0.03, 0.035)

var en: SystemFont
var ta: SystemFont


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://livery"
	DirAccess.make_dir_recursive_absolute(out)
	en = SystemFont.new()
	en.font_names = PackedStringArray(["Arial Black", "Arial"])
	ta = SystemFont.new()
	ta.font_names = PackedStringArray(["Tamil Sangam MN", "Tamil MN"])
	ta.font_weight = 700
	await _render(out.path_join("livery.png"), Vector2i(4096, 4096), _draw_livery)
	await _render(out.path_join("board_front.png"), Vector2i(1600, 260), func(c): _draw_board(c, 1600, 260, true))
	await _render(out.path_join("board_rear.png"), Vector2i(1100, 220), func(c): _draw_board(c, 1100, 220, false))
	await _render(out.path_join("board_route.png"), Vector2i(2000, 200), _draw_route)
	quit()


func _render(path: String, size: Vector2i, painter: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Control.new()
	c.size = Vector2(size)
	c.draw.connect(func(): painter.call(c))
	vp.add_child(c)
	root.add_child(vp)
	for _i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
	print("PAINTED ", path)
	vp.queue_free()


# --------------------------------------------------------------------------- helpers in metres on one face
## a face's frame: origin pixel of (u = 0, z = H) and the direction u grows in pixels (+1 / -1 along x)
func _band(c: Control, x0: float, y0: float, w_px: float, z_top: float, z_bot: float, col: Color) -> void:
	c.draw_rect(Rect2(x0, y0 + (H - z_top) * S, w_px, (z_top - z_bot) * S), col)


func _text(c: Control, font: Font, txt: String, centre: Vector2, size: int, col: Color, outline := 0, ocol := Color.BLACK) -> void:
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := centre + Vector2(-w * 0.5, size * 0.35)
	if outline > 0:
		c.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ocol)
	c.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## The side livery: bands, the blue swoosh rising towards the nose, pinstripes, lettering.
## `nose_left`: the nose is at the image's left (left side of the bus) or right (right side).
func _side(c: Control, y0: float, nose_left: bool) -> void:
	var w := L * S
	_band(c, 0, y0, w, H, 0.0, CREAM)
	_band(c, 0, y0, w, 1.22, 0.38, ORANGE)
	_band(c, 0, y0, w, 0.38, 0.0, BLACK)
	_band(c, 0, y0, w, 1.33, 1.22, RED)
	_band(c, 0, y0, w, 1.62, 1.33, BLUE)
	_band(c, 0, y0, w, 1.68, 1.64, BLUE)                       # thin line under the windows
	_band(c, 0, y0, w, 2.93, 2.89, BLUE)                       # thin line over the windows
	# the swoosh: the blue band sweeps up to the window line over the last 2 m before the nose
	var nose_x := 0.0 if nose_left else w
	var dirx := 1.0 if nose_left else -1.0
	var pts := PackedVector2Array()
	for k in 25:
		var f := float(k) / 24.0
		var x := nose_x + dirx * (2.4 * S) * f
		var top := lerpf(2.1, 1.62, smoothstep(0.0, 1.0, f))
		pts.append(Vector2(x, y0 + (H - top) * S))
	for k in range(24, -1, -1):
		var f := float(k) / 24.0
		var x := nose_x + dirx * (2.4 * S) * f
		var bot := lerpf(1.75, 1.33, smoothstep(0.0, 1.0, f))
		pts.append(Vector2(x, y0 + (H - bot) * S))
	c.draw_colored_polygon(pts, BLUE)
	# lettering: EXPRESS over the front windows, the operator on the blue band (Tamil and English), fleet number
	var front_m := func(m: float) -> float: return nose_x + dirx * m * S
	_text(c, en, "EXPRESS", Vector2(front_m.call(3.3), y0 + (H - 3.05) * S), 70, RED)
	_text(c, ta, "கோவை சாலைப் போக்குவரத்துக் கழகம்", Vector2(front_m.call(8.45), y0 + (H - 1.475) * S), 56, Color.WHITE)
	_text(c, en, "KOVAI ROAD TRANSPORT", Vector2(front_m.call(5.15), y0 + (H - 1.475) * S), 44, Color.WHITE)
	_text(c, en, "CBE 1350", Vector2(front_m.call(10.3), y0 + (H - 0.95) * S), 50, BLACK)
	_text(c, ta, "விரைவுப் பேருந்து", Vector2(front_m.call(9.3), y0 + (H - 3.05) * S), 58, BLUE)
	# reflective tape and the step marks along the skirt
	for k in 9:
		var x: float = front_m.call(0.8 + k * 1.2)
		c.draw_rect(Rect2(x - 25, y0 + (H - 0.55) * S, 50, 16), Color(0.95, 0.95, 0.9) if k % 2 == 0 else RED)


func _front(c: Control, x0: float, y0: float) -> void:
	var w := FW
	c.draw_rect(Rect2(x0, y0, w, SIDE), CREAM)
	c.draw_rect(Rect2(x0, y0 + (H - 0.8) * S, w, (0.8 - 0.38) * S), ORANGE)    # bumper face
	c.draw_rect(Rect2(x0, y0 + (H - 0.38) * S, w, 0.38 * S), BLACK)
	c.draw_rect(Rect2(x0, y0 + (H - 2.95) * S - 70, w, 140), BLACK)            # band round the destination board
	# the blue line: straight under the windscreen, dipping down round each pair of lamps to the corners
	var pts := PackedVector2Array()
	var bot := PackedVector2Array()
	for k in 65:
		var f := float(k) / 64.0
		var x := x0 + f * w
		var d := absf(f - 0.5) * 2.0                                         # 0 centre … 1 corner
		var dip := smoothstep(0.25, 0.95, d) * 0.42
		pts.append(Vector2(x, y0 + (H - (1.27 - dip)) * S))
		bot.append(Vector2(x, y0 + (H - (1.19 - dip)) * S))
	bot.reverse()
	pts.append_array(bot)
	c.draw_colored_polygon(pts, BLUE)
	var red := PackedVector2Array()
	var rb := PackedVector2Array()
	for k in 65:
		var f := float(k) / 64.0
		var d := absf(f - 0.5) * 2.0
		var dip := smoothstep(0.25, 0.95, d) * 0.42
		red.append(Vector2(x0 + f * w, y0 + (H - (1.17 - dip)) * S))
		rb.append(Vector2(x0 + f * w, y0 + (H - (1.14 - dip)) * S))
	rb.reverse()
	red.append_array(rb)
	c.draw_colored_polygon(red, RED)
	_text(c, en, "CBE 1350", Vector2(x0 + w * 0.5, y0 + (H - 0.68) * S), 34, BLACK)


func _rear(c: Control, x0: float, y0: float) -> void:
	var w := FW
	c.draw_rect(Rect2(x0, y0, w, SIDE), CREAM)
	c.draw_rect(Rect2(x0, y0 + (H - 1.22) * S, w, (1.22 - 0.38) * S), ORANGE)
	c.draw_rect(Rect2(x0, y0 + (H - 0.38) * S, w, 0.38 * S), BLACK)
	c.draw_rect(Rect2(x0, y0 + (H - 1.33) * S, w, 0.11 * S), RED)
	c.draw_rect(Rect2(x0, y0 + (H - 1.62) * S, w, 0.29 * S), BLUE)
	_text(c, en, "EXPRESS", Vector2(x0 + w * 0.5, y0 + (H - 1.475) * S), 52, Color.WHITE)
	_text(c, en, "CBE 1350", Vector2(x0 + w * 0.5, y0 + (H - 0.95) * S), 44, BLACK)
	_text(c, ta, "இடைவெளி விட்டு வரவும்", Vector2(x0 + w * 0.5, y0 + (H - 0.6) * S), 30, BLACK)   # "keep distance"


func _draw_livery(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 4096, 4096), CREAM)
	_side(c, 0.0, true)
	_side(c, SIDE, false)
	_front(c, 0.0, 2.0 * SIDE)
	_rear(c, FW, 2.0 * SIDE)
	c.draw_rect(Rect2(0, 3.0 * SIDE, 4096, 4096 - 3.0 * SIDE), Color(0.9, 0.88, 0.82))


## LED destination board: black, amber-red EXP, green destination in English, small Tamil line under it.
func _draw_board(c: Control, w: int, h: int, front: bool) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.01, 0.01, 0.012))
	if front:
		_text(c, en, "EXP", Vector2(w * 0.12, h * 0.5), int(h * 0.48), Color(1.0, 0.15, 0.06))
		_text(c, en, "OOTY", Vector2(w * 0.58, h * 0.42), int(h * 0.56), Color(0.2, 1.0, 0.4))
		_text(c, ta, "உதகை", Vector2(w * 0.58, h * 0.86), int(h * 0.22), Color(0.2, 1.0, 0.4))
	else:
		_text(c, en, "OOTY", Vector2(w * 0.5, h * 0.42), int(h * 0.56), Color(0.2, 1.0, 0.4))
		_text(c, ta, "உதகை", Vector2(w * 0.5, h * 0.86), int(h * 0.22), Color(0.2, 1.0, 0.4))
	for x in range(0, w, 6):                                  # a fine LED grid
		c.draw_line(Vector2(x, 0), Vector2(x, h), Color(0, 0, 0, 0.18), 1.0)


## Route board in the front windscreen's top corner: Tamil route on black.
func _draw_route(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 2000, 200), Color(0.95, 0.95, 0.92))
	_text(c, ta, "கோயம்புத்தூர் - மேட்டுப்பாளையம் - உதகமண்டலம்", Vector2(1000, 100), 84, RED)
