extends RefCounted
## The Mist Village's interface style, shared by every HUD piece and screen: the type (Inter, with Noto Sans Tamil for
## Tamil: assets/fonts, SIL Open Font License), the palette, and the dark translucent panel everything sits on.
## Sizes are given for 1080p and scaled by s() to the window, whatever its size or shape.
##   charcoal panels, white and grey text; muted amber for what matters; green for the way to go and for good;
##   red only for warnings.

const INK := Color(0.96, 0.96, 0.95)                 # main text
const DIM := Color(0.96, 0.96, 0.95, 0.74)           # labels, units
const FAINT := Color(0.96, 0.96, 0.95, 0.16)         # tracks, rules
const AMBER := Color(0.95, 0.72, 0.32)
const GREEN := Color(0.42, 0.82, 0.55)
const RED := Color(0.93, 0.3, 0.26)
const PANEL := Color(0.07, 0.075, 0.085, 0.72)
const EDGE := Color(1, 1, 1, 0.09)

static var _fonts := {}


## The type at a weight (400 regular, 500 medium, 600 semibold, 700 bold), Tamil falling back to Noto Sans Tamil.
static func font(weight := 400) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var inter: FontFile = load("res://assets/fonts/Inter.ttf")
	var tamil: FontFile = load("res://assets/fonts/NotoSansTamil.ttf")
	if inter == null:                                    # (not imported yet: the default, once, not a load a frame)
		_fonts[weight] = ThemeDB.fallback_font
		return _fonts[weight]
	var ta := FontVariation.new()
	ta.base_font = tamil
	ta.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	var f := FontVariation.new()
	f.base_font = inter
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}   # (figures that don't jump)
	f.fallbacks = [ta]
	_fonts[weight] = f
	return f


## The scale for this window: 1.0 at 1080 lines, never so small it can't be read.
static func s(c: CanvasItem) -> float:
	return maxf(c.get_viewport_rect().size.y / 1080.0, 0.62)


## The panel: dark, a little see-through, softly rounded, a hairline edge and a faint shadow.
static func panel(c: CanvasItem, r: Rect2, k: float, alpha := 1.0, accent := Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, PANEL.a * alpha)
	sb.set_corner_radius_all(int(10.0 * k))
	sb.border_color = Color(EDGE.r, EDGE.g, EDGE.b, EDGE.a * alpha)
	sb.set_border_width_all(maxi(1, int(k)))
	sb.shadow_color = Color(0, 0, 0, 0.22 * alpha)
	sb.shadow_size = int(10.0 * k)
	sb.anti_aliasing = true
	if accent.a > 0.0:                                   # a coloured bar down the left (a warning, an objective)
		sb.border_color = Color(accent.r, accent.g, accent.b, accent.a * alpha)
		sb.border_width_left = int(4.0 * k)
	c.draw_style_box(sb, r)


static func text(c: CanvasItem, at: Vector2, t: String, size: float, col: Color, weight := 400, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0) -> void:
	c.draw_string(font(weight), at, t, align, width, int(size), col)


static func width_of(t: String, size: float, weight := 400) -> float:
	return font(weight).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x


static func fade(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * a)
