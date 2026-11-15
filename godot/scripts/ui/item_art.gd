extends RefCounted
## Small things drawn for the interface (no image files): keys, a wallet, a phone, a brass hook, a trouser pocket.
## Each is a static call drawing on a CanvasItem round a point, at a size (px), in the kit's palette (ui_kit.gd's
## WOOD, BRASS, IRON, IVORY...). Shapes are simple and clean: a key reads as its kind at a glance.
##   key(c, at, kind, s, lift)   at: where its ring hangs (the hook's tip); it hangs down from there.
##                               kind: "suv" (black fob, two buttons, steel blade), "gate" (a long old iron key,
##                               a ring bow and a square bit), "store" (a small brass padlock key), "garden" (steel,
##                               a green tag on its bow), "scooter" (a black rubber head), "house" (a brass flat key)
##   wallet(c, centre, s) / phone(c, centre, s)   in their own box of size s
##   hook(c, at, s)          a brass L-hook on its round plate; its tip is at + (0, s*0.55)
##   plate(c, r, text, k)    a little brass label plate with the words engraved
##   pocket(c, r, k, glow)   a denim trouser pocket, its stitching; glow: something's over it, ready to drop
const Hud := preload("res://scripts/ui/hud_style.gd")

const BRASS := Color(0.78, 0.62, 0.3)
const BRASS_DARK := Color(0.5, 0.37, 0.16)
const BRASS_LIGHT := Color(0.95, 0.82, 0.5)
const STEEL := Color(0.74, 0.76, 0.78)
const STEEL_DARK := Color(0.45, 0.47, 0.5)
const IRON := Color(0.28, 0.27, 0.27)
const IRON_LIGHT := Color(0.45, 0.43, 0.42)
const BLACK := Color(0.09, 0.09, 0.1)
const FOREST := Color(0.2, 0.36, 0.25)
const LEATHER := Color(0.42, 0.25, 0.13)
const LEATHER_DARK := Color(0.28, 0.16, 0.08)
const DENIM := Color(0.2, 0.27, 0.4)
const DENIM_LIGHT := Color(0.29, 0.37, 0.52)
const THREAD := Color(0.86, 0.66, 0.32)


static func _rr(c: CanvasItem, r: Rect2, col: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(maxf(bw, 1.0)))
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)


static func _shadow(c: CanvasItem, r: Rect2, radius: float, a := 0.28) -> void:
	_rr(c, Rect2(r.position + Vector2(2.0, 4.0), r.size), Color(0, 0, 0, a), radius)


## A blade hanging down from p (its top), w wide, l long, teeth on its right edge.
static func _blade(c: CanvasItem, p: Vector2, w: float, l: float, col: Color, dark: Color, teeth := 4) -> void:
	var pts := PackedVector2Array([p + Vector2(-w * 0.5, 0), p + Vector2(w * 0.5, 0)])
	var step := l * 0.55 / teeth
	for i in teeth:                                      # the cuts, from the shoulder down
		var y := l * 0.3 + i * step
		pts.append(p + Vector2(w * 0.5, y))
		pts.append(p + Vector2(w * (0.5 + 0.45 * (1 if i % 2 == 0 else 0.55)), y + step * 0.5))
	pts.append(p + Vector2(w * 0.5, l * 0.88))
	pts.append(p + Vector2(0.0, l))                      # the tip
	pts.append(p + Vector2(-w * 0.5, l * 0.9))
	c.draw_colored_polygon(pts, col)
	c.draw_line(p + Vector2(-w * 0.1, l * 0.08), p + Vector2(-w * 0.1, l * 0.85), dark, maxf(w * 0.14, 1.0))   # the groove


static func key(c: CanvasItem, at: Vector2, kind: String, s: float, lift := 0.0) -> void:
	var p := at + Vector2(0, -lift)
	var ring := s * 0.09
	c.draw_arc(p + Vector2(0, ring), ring, 0, TAU, 20, STEEL_DARK, maxf(s * 0.025, 1.5))   # the split ring on the hook
	var top := p + Vector2(0, ring * 2.0)
	match kind:
		"suv":                                           # a black fob, two buttons, a steel blade under it
			var fob := Rect2(top + Vector2(-s * 0.16, 0), Vector2(s * 0.32, s * 0.42))
			_shadow(c, fob, s * 0.08)
			_rr(c, fob, BLACK, s * 0.1)
			_rr(c, Rect2(fob.position + Vector2(s * 0.03, s * 0.025), Vector2(s * 0.26, s * 0.05)), Color(1, 1, 1, 0.07), s * 0.02)
			for i in 2:
				var b := fob.position + Vector2(fob.size.x * 0.5, s * (0.13 + 0.12 * i))
				c.draw_circle(b, s * 0.045, Color(0.2, 0.2, 0.22))
				c.draw_circle(b, s * 0.03, Color(0.27, 0.27, 0.3))
			c.draw_rect(Rect2(fob.position + Vector2(fob.size.x * 0.5 - s * 0.012, s * 0.33), Vector2(s * 0.024, s * 0.02)), Color(0.85, 0.2, 0.15))   # the lock light
			_blade(c, Vector2(fob.get_center().x, fob.end.y), s * 0.09, s * 0.36, STEEL, STEEL_DARK)
		"gate":                                          # the big old iron key: a ring bow, a long shaft, a square bit
			var bow := top + Vector2(0, s * 0.13)
			c.draw_arc(bow, s * 0.13, 0, TAU, 24, IRON, s * 0.05)
			c.draw_arc(bow, s * 0.13, PI * 1.1, PI * 1.6, 8, IRON_LIGHT, s * 0.02)
			c.draw_line(bow + Vector2(0, s * 0.13), bow + Vector2(0, s * 0.78), IRON, s * 0.055)
			c.draw_rect(Rect2(bow + Vector2(0, s * 0.6), Vector2(s * 0.14, s * 0.16)), IRON)
			c.draw_line(bow + Vector2(s * 0.07, s * 0.6), bow + Vector2(s * 0.07, s * 0.68), Color(0.12, 0.12, 0.12), s * 0.025)
		"store":                                         # a small brass padlock key
			var bow := top + Vector2(0, s * 0.1)
			c.draw_circle(bow, s * 0.11, BRASS)
			c.draw_circle(bow, s * 0.035, Color(0, 0, 0, 0.55))
			c.draw_arc(bow, s * 0.11, PI * 1.1, PI * 1.7, 8, BRASS_LIGHT, s * 0.02)
			_blade(c, bow + Vector2(0, s * 0.1), s * 0.07, s * 0.3, BRASS, BRASS_DARK, 3)
		"garden":                                        # steel, a green plastic tag over the bow
			var bow := Rect2(top + Vector2(-s * 0.11, 0), Vector2(s * 0.22, s * 0.2))
			_shadow(c, bow, s * 0.06)
			_rr(c, bow, FOREST, s * 0.06)
			c.draw_circle(bow.get_center() + Vector2(0, -s * 0.04), s * 0.025, Color(0, 0, 0, 0.5))
			_blade(c, Vector2(bow.get_center().x, bow.end.y), s * 0.08, s * 0.38, STEEL, STEEL_DARK)
		"scooter":                                       # a black rubber head
			var head := Rect2(top + Vector2(-s * 0.13, 0), Vector2(s * 0.26, s * 0.24))
			_shadow(c, head, s * 0.1)
			_rr(c, head, Color(0.12, 0.12, 0.13), s * 0.11)
			c.draw_circle(head.get_center() + Vector2(0, -s * 0.05), s * 0.03, Color(0.05, 0.05, 0.05))
			_blade(c, Vector2(head.get_center().x, head.end.y), s * 0.08, s * 0.4, STEEL, STEEL_DARK)
		"house":                                         # a brass flat key, a wide round bow
			var bow := top + Vector2(0, s * 0.13)
			c.draw_circle(bow, s * 0.14, BRASS)
			c.draw_circle(bow + Vector2(0, -s * 0.06), s * 0.03, Color(0, 0, 0, 0.55))
			c.draw_arc(bow, s * 0.14, PI * 1.1, PI * 1.7, 8, BRASS_LIGHT, s * 0.022)
			_blade(c, bow + Vector2(0, s * 0.12), s * 0.1, s * 0.36, BRASS, BRASS_DARK, 5)


static func wallet(c: CanvasItem, centre: Vector2, s: float) -> void:
	var r := Rect2(centre - Vector2(s * 0.42, s * 0.3), Vector2(s * 0.84, s * 0.6))
	_shadow(c, r, s * 0.07, 0.3)
	_rr(c, Rect2(r.position + Vector2(s * 0.05, -s * 0.05), Vector2(s * 0.3, s * 0.1)), Color(0.82, 0.8, 0.74), s * 0.02)   # a card's edge
	_rr(c, r, LEATHER, s * 0.07)
	_rr(c, Rect2(r.position + Vector2(0, r.size.y * 0.42), Vector2(r.size.x, r.size.y * 0.58)), LEATHER_DARK.lerp(LEATHER, 0.55), s * 0.07)
	c.draw_line(r.position + Vector2(s * 0.03, r.size.y * 0.42), r.position + Vector2(r.size.x - s * 0.03, r.size.y * 0.42), LEATHER_DARK, maxf(s * 0.012, 1.0))
	var inset := r.grow(-s * 0.035)                       # the stitching, dashed round the edge
	var n := 26
	var pts := [inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y), inset.position]
	for side in 4:
		for i in n / 4:
			var a: Vector2 = pts[side].lerp(pts[side + 1], (i + 0.15) / float(n / 4))
			var b: Vector2 = pts[side].lerp(pts[side + 1], (i + 0.6) / float(n / 4))
			c.draw_line(a, b, THREAD, maxf(s * 0.012, 1.0))


static func phone(c: CanvasItem, centre: Vector2, s: float) -> void:
	var r := Rect2(centre - Vector2(s * 0.24, s * 0.44), Vector2(s * 0.48, s * 0.88))
	_shadow(c, r, s * 0.07, 0.32)
	_rr(c, r, BLACK, s * 0.07, Color(0.32, 0.33, 0.35), maxf(s * 0.012, 1.0))
	var scr := r.grow(-s * 0.03)
	scr.position.y += s * 0.03
	scr.size.y -= s * 0.06
	_rr(c, scr, Color(0.08, 0.12, 0.2), s * 0.05)
	c.draw_colored_polygon(PackedVector2Array([scr.position + Vector2(scr.size.x * 0.55, 0), scr.position + Vector2(scr.size.x, 0),
		scr.position + Vector2(scr.size.x, scr.size.y * 0.35)]), Color(1, 1, 1, 0.06))   # a reflection
	Hud.text(c, scr.position + Vector2(0, scr.size.y * 0.32), "6:30", s * 0.13, Color(1, 1, 1, 0.85), 600, HORIZONTAL_ALIGNMENT_CENTER, scr.size.x)
	c.draw_circle(Vector2(r.get_center().x, r.position.y + s * 0.03), s * 0.012, Color(0.2, 0.22, 0.26))   # the camera
	c.draw_rect(Rect2(Vector2(r.end.x, r.position.y + s * 0.2), Vector2(maxf(s * 0.012, 1.5), s * 0.12)), Color(0.25, 0.25, 0.27))   # a side button


static func hook(c: CanvasItem, at: Vector2, s: float, hot := false) -> void:
	c.draw_circle(at + Vector2(1.5, 2.5), s * 0.17, Color(0, 0, 0, 0.35))
	c.draw_circle(at, s * 0.17, BRASS_DARK)
	c.draw_circle(at, s * 0.13, BRASS_LIGHT if hot else BRASS)
	c.draw_circle(at, s * 0.035, BRASS_DARK)                                 # the screw
	var w := maxf(s * 0.06, 2.0)
	c.draw_line(at, at + Vector2(0, s * 0.45), BRASS_DARK, w + 1.5)          # the hook's arm, then its curl up
	c.draw_line(at, at + Vector2(0, s * 0.45), BRASS_LIGHT if hot else BRASS, w)
	c.draw_arc(at + Vector2(s * 0.09, s * 0.45), s * 0.09, 0, PI, 8, BRASS_LIGHT if hot else BRASS, w)


static func plate(c: CanvasItem, r: Rect2, text: String, k: float, hot := false) -> void:
	_shadow(c, r, 3.0 * k, 0.3)
	_rr(c, r, BRASS_LIGHT if hot else BRASS, 3.0 * k, BRASS_DARK, maxf(k, 1.0))
	for x in [r.position.x + 6.0 * k, r.end.x - 6.0 * k]:                     # its two little nails
		c.draw_circle(Vector2(x, r.get_center().y), 1.8 * k, BRASS_DARK)
	Hud.text(c, Vector2(r.position.x, r.get_center().y + 5.5 * k), text.to_upper(), 14.0 * k, Color(0.22, 0.15, 0.06), 700,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


static func pocket(c: CanvasItem, r: Rect2, k: float, glow := false) -> void:
	_rr(c, r.grow(10.0 * k), DENIM.darkened(0.15), 14.0 * k)                  # the trousers round it
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - r.size.y * 0.25),
		Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.end.y - r.size.y * 0.25)])
	c.draw_colored_polygon(pts, DENIM_LIGHT if glow else DENIM)
	c.draw_colored_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.position.y + r.size.y * 0.16), Vector2(r.position.x, r.position.y + r.size.y * 0.16)]), Color(0, 0, 0, 0.35))   # its mouth
	for j in 2:                                                               # double stitching round it
		var g := (6.0 + 6.0 * j) * k
		var q := PackedVector2Array([pts[0] + Vector2(g, g), pts[1] + Vector2(-g, g), pts[2] + Vector2(-g, -g * 0.3),
			pts[3] + Vector2(0, -g), pts[4] + Vector2(g, -g * 0.3), pts[0] + Vector2(g, g)])
		for i in q.size() - 1:
			var a: Vector2 = q[i]
			var b: Vector2 = q[i + 1]
			var n := int(a.distance_to(b) / (9.0 * k))
			for m in n:
				c.draw_line(a.lerp(b, (m + 0.1) / n), a.lerp(b, (m + 0.55) / n), Hud.fade(THREAD, 0.85), maxf(1.4 * k, 1.0))
	if glow:
		_rr(c, r.grow(14.0 * k), Color(0, 0, 0, 0), 16.0 * k, Color(0.42, 0.82, 0.55, 0.9), 3.0 * k)
