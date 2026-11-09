extends RefCounted
## The Mist Village's interface kit: the pieces every screen is drawn with (story tasks, documents, apps, the court),
## on top of hud_style.gd (the type, the palette, the panel, the scale). Drawn, not built from Control nodes, like
## the rest of the game's screens: each piece is a static call taking the CanvasItem to draw on and k (the scale,
## HudStyle.s(): 1.0 at 1080 lines).
##   sizes     SP_* spacing steps, T_* type sizes, R_* corner radii (all at 1080p, times k)
##   colours   hud_style's charcoal / ink / amber / green / red, plus BLUE for the selected thing, PAPER and
##             PEN for documents, and GREY for what's secondary
##   pieces    button (normal / hover / focused / pressed / disabled; primary, secondary, danger), paper (a sheet
##             with a faint grain and a soft shadow), field (a printed label over a ruled line, a handwritten
##             entry), stamp (a round rubber stamp), card, progress (a bar, or segments), keycap, banner (a
##             success / failure line that fades), scrim (the dim behind a modal)
##   motion    ease_out(t), and FAST / NORMAL durations: nothing waits on an animation; input is taken at once

const Hud := preload("res://scripts/ui/hud_style.gd")

const SP_XS := 4.0
const SP_S := 8.0
const SP_M := 16.0
const SP_L := 24.0
const SP_XL := 40.0
const T_CAPTION := 15.0
const T_BODY := 18.0
const T_LABEL := 14.0
const T_TITLE := 26.0
const T_FIGURE := 34.0
const R_S := 6.0
const R_M := 10.0
const FAST := 0.12
const NORMAL := 0.25

const CHARCOAL := Color(0.085, 0.09, 0.1)
const CHARCOAL_2 := Color(0.13, 0.135, 0.15)
const INK := Hud.INK
const DIM := Hud.DIM
const GREY := Color(0.62, 0.63, 0.66)
const AMBER := Hud.AMBER
const GREEN := Hud.GREEN
const RED := Hud.RED
const BLUE := Color(0.27, 0.5, 0.9)
const PAPER := Color(0.965, 0.95, 0.915)
const PAPER_LINE := Color(0.55, 0.52, 0.47)
const PRINT := Color(0.28, 0.27, 0.25)             # the printed words on a form
const PEN := Color(0.1, 0.18, 0.5)                 # a ballpoint's blue

enum { NORMAL_STATE, HOVER, FOCUS, PRESSED, DISABLED }

static var _grain: ImageTexture


static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)


static func _box(col: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(maxi(1, int(bw)))
	sb.anti_aliasing = true
	return sb


## A button. kind: "primary" (blue), "secondary" (charcoal), "danger" (red), "light" (on paper). The focused one
## carries an amber ring (keyboard), hover lifts it a shade, pressed sinks it, disabled greys it and its words.
static func button(c: CanvasItem, r: Rect2, label: String, k: float, state := NORMAL_STATE, kind := "primary",
		hint := "") -> void:
	var base: Color = {"primary": BLUE, "secondary": CHARCOAL_2, "danger": RED.darkened(0.15), "light": Color(0.9, 0.88, 0.84)}[kind]
	var txt := INK if kind != "light" else CHARCOAL
	if state == DISABLED:
		base = Color(0.3, 0.31, 0.33) if kind != "light" else Color(0.85, 0.84, 0.81)
		txt = Hud.fade(txt, 0.45)
	elif state == HOVER:
		base = base.lightened(0.1)
	elif state == PRESSED:
		base = base.darkened(0.15)
	var sb := _box(base, R_S * k, Color(1, 1, 1, 0.1) if kind == "secondary" else Color(0, 0, 0, 0), k if kind == "secondary" else 0.0)
	if state != PRESSED and state != DISABLED:
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = int(4.0 * k)
		sb.shadow_offset = Vector2(0, 2.0 * k)
	c.draw_style_box(sb, r)
	if state == FOCUS:
		c.draw_style_box(_box(Color(0, 0, 0, 0), (R_S + 3.0) * k, AMBER, 2.0 * k), r.grow(4.0 * k))
	var size := T_BODY * k
	var y := r.position.y + r.size.y * 0.5 + size * 0.36
	if hint != "":                                          # the key for it, small and dim, after the words
		var tw := Hud.width_of(label, size, 600)
		var hw := Hud.width_of(hint, T_LABEL * k, 500)
		var x0 := r.position.x + (r.size.x - tw - hw - SP_S * k) * 0.5
		Hud.text(c, Vector2(x0, y), label, size, txt, 600)
		Hud.text(c, Vector2(x0 + tw + SP_S * k, y - 1.0 * k), hint, T_LABEL * k, Hud.fade(txt, 0.6), 500)
	else:
		Hud.text(c, Vector2(r.position.x, y), label, size, txt, 600, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## A sheet of paper: off-white, the faint grain of paper (one small texture, made once, tiled), a soft shadow,
## slightly lighter at the top as if lit from a window.
static func paper(c: CanvasItem, r: Rect2, k: float, col := PAPER) -> void:
	var sh := _box(Color(0, 0, 0, 0), 2.0 * k)
	sh.shadow_color = Color(0, 0, 0, 0.4)
	sh.shadow_size = int(18.0 * k)
	sh.shadow_offset = Vector2(0, 8.0 * k)
	c.draw_style_box(sh, r)
	c.draw_rect(r, col)
	c.draw_texture_rect(_grain_tex(), r, true, Color(1, 1, 1, 0.5))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.3)), Color(1, 1, 1, 0.08))
	c.draw_rect(r, Color(0, 0, 0, 0.12), false, maxf(1.0, k))


static func _grain_tex() -> ImageTexture:
	if _grain:
		return _grain
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	for y in 128:
		for x in 128:
			var v := rng.randf()
			var fibre := 0.5 + 0.5 * sin(x * 0.21 + sin(y * 0.05) * 3.0)
			var a := (v * 0.06 + fibre * 0.025)
			img.set_pixel(x, y, Color(0.35, 0.3, 0.22, a))
	_grain = ImageTexture.create_from_image(img)
	return _grain


## A form field: the printed label, small and grey, the ruled line, and what was written on it in pen.
static func field(c: CanvasItem, at: Vector2, w: float, label: String, value: String, k: float, label_w := 200.0) -> void:
	Hud.text(c, at, label.to_upper(), T_LABEL * k, PRINT, 600)
	var x := at.x + label_w * k
	c.draw_line(Vector2(x, at.y + 6.0 * k), Vector2(at.x + w, at.y + 6.0 * k), PAPER_LINE, maxf(1.0, k))
	Hud.text(c, Vector2(x + SP_S * k, at.y + 1.0 * k), value, 21.0 * k, PEN, 500)


## A round rubber stamp, a little faded and off true: two rings and its words.
static func stamp(c: CanvasItem, centre: Vector2, radius: float, words: String, k: float, col := Color(0.55, 0.12, 0.22)) -> void:
	var ink := Hud.fade(col, 0.55)
	c.draw_arc(centre, radius, 0.0, TAU, 64, ink, 2.5 * k, true)
	c.draw_arc(centre, radius * 0.8, 0.0, TAU, 64, ink, 1.2 * k, true)
	var lines := words.split(" ", false)
	var mid := lines.size() / 2
	var top := " ".join(lines.slice(0, maxi(mid, 1)))
	var bottom := " ".join(lines.slice(maxi(mid, 1)))
	Hud.text(c, centre + Vector2(-radius, -2.0 * k), top, 12.0 * k, ink, 700, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)
	Hud.text(c, centre + Vector2(-radius, 13.0 * k), bottom, 12.0 * k, ink, 700, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)


## A card (an evidence card, an item, a choice): charcoal with a hairline edge; selected: a blue edge and lifted.
static func card(c: CanvasItem, r: Rect2, k: float, selected := false, hover := false) -> void:
	var sb := _box(CHARCOAL_2.lightened(0.04 if hover else 0.0), R_M * k, BLUE if selected else Color(1, 1, 1, 0.1),
		(2.0 if selected else 1.0) * k)
	sb.shadow_color = Color(0, 0, 0, 0.3 if selected else 0.18)
	sb.shadow_size = int((10.0 if selected else 5.0) * k)
	c.draw_style_box(sb, r)


## A progress bar (value 0..1), or `segments` of it (a count: 3 of 8), each segment filled or not.
static func progress(c: CanvasItem, r: Rect2, value: float, k: float, col := GREEN, segments := 0) -> void:
	if segments <= 0:
		c.draw_style_box(_box(Color(1, 1, 1, 0.12), r.size.y * 0.5), r)
		if value > 0.0:
			c.draw_style_box(_box(col, r.size.y * 0.5), Rect2(r.position, Vector2(r.size.x * clampf(value, 0.0, 1.0), r.size.y)))
		return
	var gap := 4.0 * k
	var w := (r.size.x - gap * (segments - 1)) / segments
	for i in segments:
		var sr := Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		var f := clampf(value * segments - i, 0.0, 1.0)
		c.draw_style_box(_box(Color(1, 1, 1, 0.12), 2.0 * k), sr)
		if f > 0.0:
			c.draw_style_box(_box(col, 2.0 * k), Rect2(sr.position, Vector2(sr.size.x * f, sr.size.y)))


## A key on a keypad: a soft rounded key with its figure; pressed sinks it.
static func keycap(c: CanvasItem, r: Rect2, label: String, k: float, state := NORMAL_STATE, light := false) -> void:
	var base := Color(0.95, 0.95, 0.96) if light else CHARCOAL_2
	if state == HOVER:
		base = base.darkened(0.05) if light else base.lightened(0.08)
	elif state == PRESSED:
		base = base.darkened(0.12)
	c.draw_style_box(_box(base, R_M * k, Color(0, 0, 0, 0.08) if light else Color(1, 1, 1, 0.08), k), r)
	Hud.text(c, Vector2(r.position.x, r.get_center().y + 9.0 * k), label, 24.0 * k, CHARCOAL if light else INK, 500,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## A success or failure line under a task: a coloured mark, the words, fading out over its last half second.
static func banner(c: CanvasItem, centre_top: Vector2, text: String, good: bool, k: float, alpha := 1.0) -> void:
	if text == "" or alpha <= 0.0:
		return
	var col := GREEN if good else RED
	var w := Hud.width_of(text, T_BODY * k, 600) + 64.0 * k
	var r := Rect2(centre_top.x - w * 0.5, centre_top.y, w, 44.0 * k)
	var sb := _box(Hud.fade(CHARCOAL, 0.94 * alpha), R_M * k)
	sb.border_color = Hud.fade(col, alpha)
	sb.border_width_left = int(4.0 * k)
	c.draw_style_box(sb, r)
	c.draw_circle(Vector2(r.position.x + 22.0 * k, r.get_center().y), 6.0 * k, Hud.fade(col, alpha))
	Hud.text(c, Vector2(r.position.x + 38.0 * k, r.get_center().y + 6.5 * k), text, T_BODY * k, Hud.fade(INK, alpha), 600)


## The dim behind a modal: the world stays there, darker.
static func scrim(c: CanvasItem, alpha := 0.62) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.get_viewport_rect().size), Color(0.02, 0.02, 0.03, alpha))


## The state of a button at r for the mouse at m (pressed while the button is held), disabled when not enabled,
## focused when it's the keyboard's choice.
static func state_of(r: Rect2, m: Vector2, enabled := true, focused := false, held := false) -> int:
	if not enabled:
		return DISABLED
	if r.has_point(m):
		return PRESSED if held else HOVER
	return FOCUS if focused else NORMAL_STATE
