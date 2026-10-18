extends CanvasLayer
const Prof := preload("res://scripts/drive/prof.gd")
## The city map (data: tools/citygen/mapdata.py → assets/city/map.bin).
##   minimap   bottom-left, heading-up, ~600 m across, roads by class, water, your arrow, a north mark, and the
##             direction and distance to your destination pin
##   full map  Tab opens / closes (Esc closes), as in the main game: the whole city, north-up; mouse wheel zooms at the pointer, drag pans,
##             right-click sets a destination pin (right-click it again to clear), road names when zoomed in
## Drawn as vectors, in buckets of 1 km so the minimap only draws what is near you.

const PATH := "res://assets/city/map.bin"
const CELL := 1000.0
const STYLE := {          # class → [colour, width in metres, min width in pixels]
	"motorway": [Color(0.98, 0.72, 0.3), 16.0, 3.0], "trunk": [Color(0.98, 0.72, 0.3), 14.0, 3.0],
	"primary": [Color(0.99, 0.85, 0.45), 11.0, 2.4], "secondary": [Color(1.0, 0.95, 0.65), 9.5, 2.0],
	"tertiary": [Color(0.97, 0.97, 0.95), 8.0, 1.6], "unclassified": [Color(0.9, 0.9, 0.88), 7.0, 1.2],
	"residential": [Color(0.9, 0.9, 0.88), 6.5, 1.0], "living_street": [Color(0.86, 0.86, 0.84), 5.5, 1.0],
	"service": [Color(0.82, 0.82, 0.8), 5.0, 0.8], "track": [Color(0.7, 0.62, 0.5), 3.5, 0.8],
	"footway": [Color(0.75, 0.7, 0.66), 2.2, 0.6]}
const ORDER := ["footway", "track", "service", "living_street", "residential", "unclassified", "tertiary", "secondary",
	"primary", "trunk", "motorway"]
const BG := Color(0.93, 0.91, 0.86)
const WATER := Color(0.62, 0.78, 0.9)

var target: Node3D                         # whose position and heading the map follows
var classes: Array = []
var bounds := Rect2()
var cells := {}                            # Vector2i → {class: PackedVector2Array of segment pairs}
var all_segs := {}                         # class → PackedVector2Array (full map)
var bridge_segs := PackedVector2Array()
var water: Array = []                      # PackedVector2Array polygons
var labels: Array = []                     # [Vector2 pos, angle, class, text]
var pin = null                             # Vector2 destination, or null
var full_open := false

var mini: Control
var full: Control
var _zoom := 0.04                          # full map: pixels per metre
var _centre := Vector2.ZERO                # full map: world point at the centre of the screen
var _dragging := false
var _font: Font
var _ui := 1.0                             # text and marker scale (follows the minimap size)


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	classes = (JSON.parse_string(FileAccess.get_file_as_string("res://assets/city/index.json")) as Dictionary)["classes"]
	_load()
	mini = Control.new()
	mini.name = "Minimap"
	mini.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mini.position = Vector2(20, -300)
	mini.size = Vector2(280, 280)
	mini.clip_contents = true
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.draw.connect(_draw_mini)
	add_child(mini)
	full = Control.new()
	full.name = "FullMap"
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.visible = false
	full.clip_contents = true
	full.draw.connect(_draw_full)
	full.gui_input.connect(_full_input)
	add_child(full)


func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "CMAP":
		push_warning("city map missing: run tools/citygen/mapdata.py")
		return
	var b := f.get_buffer(16).to_float32_array()
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	for _r in f.get_32():
		var cid := f.get_8()
		var fl := f.get_8()
		var n := f.get_16()
		var p := f.get_buffer(n * 8).to_float32_array()
		var cls: String = classes[cid] if cid < classes.size() else "residential"
		if not all_segs.has(cls):
			all_segs[cls] = PackedVector2Array()
		for i in n - 1:
			var a := Vector2(p[i * 2], p[i * 2 + 1])
			var c := Vector2(p[i * 2 + 2], p[i * 2 + 3])
			all_segs[cls].append_array([a, c])
			if fl & 1:
				bridge_segs.append_array([a, c])
			var k := Vector2i(floori((a.x + c.x) * 0.5 / CELL), floori((a.y + c.y) * 0.5 / CELL))
			if not cells.has(k):
				cells[k] = {}
			if not cells[k].has(cls):
				cells[k][cls] = PackedVector2Array()
			cells[k][cls].append_array([a, c])
	for _w in f.get_32():
		var n := f.get_16()
		var p := f.get_buffer(n * 8).to_float32_array()
		var poly := PackedVector2Array()
		for i in n:
			poly.append(Vector2(p[i * 2], p[i * 2 + 1]))
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			water.append(poly)
	for _l in f.get_32():
		var v := f.get_buffer(12).to_float32_array()
		var cid := f.get_8()
		var ln := f.get_16()
		labels.append([Vector2(v[0], v[1]), v[2], cid, f.get_buffer(ln).get_string_from_utf8()])
	_centre = bounds.get_center()


func _process(_dt: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_timed(_dt)
	Prof.add("map", _p0)


func _process_timed(_dt: float) -> void:
	# a quarter of the screen height, whatever the window and display scale
	var h := get_viewport().get_visible_rect().size.y
	var side := clampf(h * 0.27, 220.0, 620.0)
	mini.size = Vector2(side, side)
	mini.position = Vector2(h * 0.02, h - side - h * 0.02)
	_ui = side / 280.0
	if target and not full_open:
		mini.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_TAB or (e.keycode == KEY_ESCAPE and full_open):
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	full_open = not full_open
	full.visible = full_open
	mini.visible = not full_open
	if full_open:
		if target:
			_centre = Vector2(target.global_position.x, target.global_position.z)
		_zoom = 0.12
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		full.queue_redraw()


func _heading() -> float:
	"""the direction the target faces, as an angle on the map (x east, y = world z south)"""
	var f: Vector3 = target.call("forward") if target.has_method("forward") else -target.global_transform.basis.z
	return atan2(f.z, f.x)


func _draw_roads(c: Control, segs_by_class: Dictionary, ppm: float) -> void:
	for cls in ORDER:
		if not segs_by_class.has(cls):
			continue
		var st: Array = STYLE.get(cls, STYLE["residential"])
		var w := maxf(float(st[1]), float(st[2]) / ppm)
		c.draw_multiline(segs_by_class[cls], (st[0] as Color).darkened(0.35), w + 1.6 / ppm)
	for cls in ORDER:
		if not segs_by_class.has(cls):
			continue
		var st: Array = STYLE.get(cls, STYLE["residential"])
		c.draw_multiline(segs_by_class[cls], st[0], maxf(float(st[1]), float(st[2]) / ppm))


func _arrow(c: Control, at: Vector2, ang: float, size: float) -> void:
	var d := Vector2.from_angle(ang)
	var s := d.orthogonal()
	var pts := PackedVector2Array([at + d * size, at - d * size * 0.6 + s * size * 0.65, at - d * size * 0.3,
		at - d * size * 0.6 - s * size * 0.65])
	c.draw_colored_polygon(pts, Color(0.1, 0.45, 0.95))
	pts.append(pts[0])
	c.draw_polyline(pts, Color.WHITE, 2.0)


func _draw_mini() -> void:
	var sz := mini.size
	var mid := sz * 0.5
	mini.draw_rect(Rect2(Vector2.ZERO, sz), BG)
	if target == null:
		return
	var me := Vector2(target.global_position.x, target.global_position.z)
	var head := _heading()
	var ppm := sz.x / 600.0
	# heading-up: rotate the world so the direction we face points up the screen
	var off := -me
	var near := {}
	var kc := Vector2i(floori(me.x / CELL), floori(me.y / CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := kc + Vector2i(dx, dz)
			if not cells.has(k):
				continue
			for cls in cells[k]:
				if not near.has(cls):
					near[cls] = PackedVector2Array()
				near[cls].append_array(cells[k][cls])
	mini.draw_set_transform_matrix(Transform2D(-head - PI * 0.5, Vector2(ppm, ppm), 0.0, mid) * Transform2D(0.0, off))
	for poly in water:
		if (poly[0] - me).length() < 3000.0:
			mini.draw_colored_polygon(poly, WATER)
	_draw_roads(mini, near, ppm)
	if pin != null:
		mini.draw_circle(pin, 9.0 / ppm, Color(0.85, 0.1, 0.1))
	mini.draw_set_transform_matrix(Transform2D())
	_arrow(mini, mid, -PI * 0.5, 11.0 * _ui)
	# north mark on the rim
	var north := mid + Vector2(0, -1).rotated(-head - PI * 0.5) * (sz.x * 0.5 - 16.0 * _ui)
	mini.draw_circle(north, 10.0 * _ui, Color(0.15, 0.15, 0.15, 0.85))
	mini.draw_string(_font, north + Vector2(-5, 5) * _ui, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * _ui), Color.WHITE)
	if pin != null:
		var d: float = (pin - me).length()
		var dir: Vector2 = (pin - me).normalized().rotated(-head - PI * 0.5)
		var edge := mid + dir * minf(d * ppm, sz.x * 0.5 - 12.0)
		mini.draw_circle(edge, 6.0 * _ui, Color(0.85, 0.1, 0.1))
		mini.draw_string(_font, Vector2(8, sz.y - 10) * Vector2(_ui, 1.0), "%.1f km" % (d / 1000.0) if d > 950.0 else "%d m" % int(d),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * _ui), Color(0.1, 0.1, 0.1))
	mini.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.1, 0.1), false, 3.0)
	mini.draw_string(_font, Vector2(sz.x - 66 * _ui, sz.y - 10), "Tab: map", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * _ui), Color(0.2, 0.2, 0.2))


func _w2s(p: Vector2) -> Vector2:
	return (p - _centre) * _zoom + full.size * 0.5


func _s2w(s: Vector2) -> Vector2:
	return (s - full.size * 0.5) / _zoom + _centre


func _draw_full() -> void:
	var sz := full.size
	full.draw_rect(Rect2(Vector2.ZERO, sz), BG)
	full.draw_set_transform_matrix(Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, sz * 0.5) * Transform2D(0.0, -_centre))
	for poly in water:
		full.draw_colored_polygon(poly, WATER)
	_draw_roads(full, all_segs, _zoom)
	full.draw_set_transform_matrix(Transform2D())
	if _zoom > 0.25:
		for l in labels:
			var cls: String = classes[l[2]] if l[2] < classes.size() else ""
			if _zoom < 0.5 and not cls in ["trunk", "primary"]:
				continue
			var p := _w2s(l[0])
			if p.x < -100 or p.y < -40 or p.x > sz.x + 100 or p.y > sz.y + 40:
				continue
			var txt: String = l[3]
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			full.draw_set_transform(p, l[1], Vector2.ONE)
			full.draw_string_outline(_font, Vector2(-w * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(1, 1, 1, 0.9))
			full.draw_string(_font, Vector2(-w * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.15, 0.15, 0.15))
			full.draw_set_transform_matrix(Transform2D())
	if pin != null:
		var pp := _w2s(pin)
		full.draw_circle(pp, 9.0, Color(0.85, 0.1, 0.1))
		full.draw_circle(pp, 4.0, Color.WHITE)
	if target:
		var me := Vector2(target.global_position.x, target.global_position.z)
		_arrow(full, _w2s(me), _heading(), 13.0)
	var help := "Coimbatore   ·   wheel: zoom   drag: move   right-click: set / clear destination   Tab / Esc: close"
	var fs := int(15 * _ui)
	var tw := _font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	full.draw_rect(Rect2(10, 10, tw + 24, fs + 20), Color(0, 0, 0, 0.6))
	full.draw_string(_font, Vector2(22, 10 + fs + 4), help, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# scale bar
	var metres := 1000.0 if _zoom < 0.3 else (200.0 if _zoom < 1.5 else 50.0)
	var px := metres * _zoom
	full.draw_line(Vector2(20, sz.y - 30), Vector2(20 + px, sz.y - 30), Color(0.1, 0.1, 0.1), 3.0)
	full.draw_string(_font, Vector2(20, sz.y - 38), "%d m" % int(metres) if metres < 1000.0 else "1 km",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.1, 0.1))


func _full_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := _s2w(e.position)
			_zoom = clampf(_zoom * (1.2 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.02, 4.0)
			_centre += before - _s2w(e.position)
			full.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var w := _s2w(e.position)
			pin = null if (pin != null and (pin - w).length() * _zoom < 14.0) else w
			full.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = true
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	elif e is InputEventMouseMotion and _dragging:
		_centre -= e.relative / _zoom
		full.queue_redraw()
