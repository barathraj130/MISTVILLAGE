extends Control
## GTA-style map. A rotating minimap in the bottom-left corner (your heading is always up) and a
## full-screen map on Tab: mouse wheel to zoom, drag to pan, click a landmark (or any road) to set
## a GPS destination; the route is drawn in magenta on both maps with the distance to go.
## Everything is drawn as vectors from the real map data, so it's sharp at every zoom.

const Prof := preload("res://scripts/drive/prof.gd")
const Nav := preload("res://scripts/drive/nav.gd")
const BG := Color(0.13, 0.17, 0.12)
const ROUTE_COL := Color(1.0, 0.78, 0.2)
const STREET_COL := Color(0.78, 0.78, 0.74)
const BUILDING_COL := Color(0.36, 0.32, 0.28)
const GPS_COL := Color(0.95, 0.2, 0.75)
const MINI := Vector2(270, 270)
const CELL := 250.0

var route
var towns_data := {}
var nav: Nav
var destinations: Array = []               # {name, kind, pos}
var focus: Callable                        # () -> [Vector3 position, Vector3 forward]
var gps := PackedVector3Array()
var gps_target := {}
var full_open := false
var full_scale := 0.05                     # pixels per metre on the full map
var full_centre := Vector2.ZERO            # world x,z at the screen centre
var _cells := {}                           # CELL grid → [kind, data] for fast culling
var _cell_mesh := {}                       # CELL grid → {"b": buildings mesh, "s": streets mesh}, built once
var _route2d := PackedVector2Array()
var _dragging := false
var _mini: Control
var _full: Control
var _info: Label
var _gps_label: Label
var _redraw_t := 0.0
var _recalc_until := 0.0


func setup(r, towns: Dictionary, pois: Array, extra: Array, focus_fn: Callable, graph = null) -> void:
	route = r
	towns_data = towns
	focus = focus_fn
	for i in route.pts.size():
		_route2d.append(Vector2(route.pts[i].x, route.pts[i].z))
	for tname in towns:
		for s in towns[tname]["streets"]:
			var pl := PackedVector2Array()
			for q in s["pts"]:
				pl.append(Vector2(q[0], q[2]))
			_bucket(pl[pl.size() / 2], ["street", pl, float(s["width"])])
		for b in towns[tname]["buildings"]:
			var pg := PackedVector2Array()
			for q in b["poly"]:
				pg.append(Vector2(q[0], q[1]))
			_bucket(pg[0], ["building", pg])
	for p in pois:
		destinations.append({"name": p["name"], "kind": p["kind"], "pos": p["pos"]})
	destinations.append_array(extra)
	_build_cell_meshes()
	nav = Nav.new()
	nav.build(route, towns, graph)
	_build_controls()


## Bake each map cell's buildings and streets into two 2D meshes once, so redrawing the
## minimap is a handful of draw_mesh calls instead of thousands of polygons.
func _build_cell_meshes() -> void:
	for k in _cells:
		var bv := PackedVector2Array()
		var bc := PackedColorArray()
		var sv := PackedVector2Array()
		var sc := PackedColorArray()
		for it in _cells[k]:
			if it[0] == "building":
				var pg: PackedVector2Array = it[1]
				var tri := Geometry2D.triangulate_polygon(pg)
				for i in tri:
					bv.append(pg[i])
					bc.append(BUILDING_COL)
			else:
				var pl: PackedVector2Array = it[1]
				var hw: float = maxf(it[2] * 0.5, 2.5)
				for i in pl.size() - 1:
					var a := pl[i]
					var b := pl[i + 1]
					var n := (b - a).orthogonal().normalized() * hw
					sv.append_array([a + n, b + n, b - n, a + n, b - n, a - n])
					for q in 6:
						sc.append(STREET_COL)
		var entry := {}
		for pair in [["b", bv, bc], ["s", sv, sc]]:
			if pair[1].is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = pair[1]
			arr[Mesh.ARRAY_COLOR] = pair[2]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			entry[pair[0]] = m
		_cell_mesh[k] = entry


func _bucket(p: Vector2, item: Array) -> void:
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not _cells.has(k):
		_cells[k] = []
	_cells[k].append(item)


func _build_controls() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini = Control.new()
	_mini.custom_minimum_size = MINI
	_mini.size = MINI
	_mini.clip_contents = true
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mini)
	_mini.draw.connect(_draw_mini)
	_gps_label = Label.new()
	_gps_label.add_theme_font_size_override("font_size", 15)
	_gps_label.add_theme_color_override("font_color", Color(1, 0.8, 0.95))
	_gps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_gps_label.add_theme_constant_override("outline_size", 4)
	add_child(_gps_label)
	_full = Control.new()
	_full.visible = false
	_full.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_full)
	_full.draw.connect(_draw_full)
	_full.gui_input.connect(_full_input)
	_info = Label.new()
	_info.text = "MAP   ·   wheel: zoom   ·   drag: pan   ·   click a place or road: set GPS   ·   right-click: clear   ·   Tab: close"
	_info.add_theme_font_size_override("font_size", 15)
	_info.position = Vector2(24, 18)
	_full.add_child(_info)


# ----------------------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("map_process", _p0)


func _process_body(delta: float) -> void:
	if focus.is_null():
		return
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.08
		_mini.queue_redraw()
		if full_open:
			_full.queue_redraw()
		_update_gps_text()
	# lay out by hand every frame: the screen size isn't known when the map is built
	var parent_size: Vector2 = get_parent().size if get_parent() is Control else get_viewport_rect().size
	position = Vector2.ZERO
	size = parent_size
	_mini.position = Vector2(22.0, parent_size.y - MINI.y - 22.0)
	_mini.size = MINI
	_full.position = Vector2.ZERO
	_full.size = parent_size
	_gps_label.position = _mini.position + Vector2(0, -26)


func toggle_full() -> void:
	full_open = not full_open
	_full.visible = full_open
	if full_open:
		var f: Array = focus.call()
		full_centre = Vector2(f[0].x, f[0].z)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_destination(pos: Vector3, label: String) -> void:
	var f: Array = focus.call()
	gps = nav.path(f[0], pos)
	gps_target = {"name": label, "pos": pos}


func clear_destination() -> void:
	gps = PackedVector3Array()
	gps_target = {}


func _update_gps_text() -> void:
	if gps.is_empty():
		_gps_label.text = ""
		return
	var f: Array = focus.call()
	var p: Vector3 = f[0]
	if p.distance_to(gps_target["pos"]) < 25.0:
		_gps_label.text = "Arrived: %s" % gps_target["name"]
		gps = PackedVector3Array()
		return
	# trim the part of the path already driven
	var best := 0
	var bd := INF
	for i in mini(gps.size(), 400):
		var dd := p.distance_squared_to(gps[i])
		if dd < bd:
			bd = dd
			best = i
	if best > 0:
		gps = gps.slice(best)
	if bd > 25.0 * 25.0:
		gps = nav.path(p, gps_target["pos"])          # left the route: find another way on the roads
		_recalc_until = Time.get_ticks_msec() / 1000.0 + 2.0
	var km := Nav.length(gps) / 1000.0
	if Time.get_ticks_msec() / 1000.0 < _recalc_until:
		_gps_label.text = "Route deviation · recalculating…"
	else:
		_gps_label.text = "GPS → %s   %.1f km" % [gps_target["name"], km]


# ----------------------------------------------------------------------------- drawing
func _world_items(centre: Vector2, radius: float) -> Array:
	var out: Array = []
	var r := int(ceil(radius / CELL)) + 1
	var k := Vector2i(floori(centre.x / CELL), floori(centre.y / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			out.append_array(_cells.get(Vector2i(k.x + dx, k.y + dz), []))
	return out


func _draw_layers(ci: CanvasItem, centre: Vector2, radius: float, scale: float, show_buildings: bool) -> void:
	var r := int(ceil(radius / CELL)) + 1
	var kc := Vector2i(floori(centre.x / CELL), floori(centre.y / CELL))
	var zoomed_out := scale < 0.3
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := Vector2i(kc.x + dx, kc.y + dz)
			var e: Dictionary = _cell_mesh.get(k, {})
			if e.is_empty():
				continue
			if show_buildings and e.has("b"):
				ci.draw_mesh(e["b"], null)
			if zoomed_out:
				# whole-region view: thin lines read better than true-width streets
				for it in _cells[k]:
					if it[0] == "street":
						ci.draw_polyline(it[1], STREET_COL, 1.5 / scale)
			elif e.has("s"):
				ci.draw_mesh(e["s"], null)
	# the highway, drawn in visible stretches
	var run := PackedVector2Array()
	var step := maxi(1, int(2.0 / (scale * 4.0)))
	for i in range(0, _route2d.size(), step):
		var p := _route2d[i]
		if p.distance_to(centre) < radius * 1.2:
			run.append(p)
		elif run.size() > 1:
			ci.draw_polyline(run, ROUTE_COL, maxf(9.0, 3.0 / scale))
			run = PackedVector2Array()
		else:
			run = PackedVector2Array()
	if run.size() > 1:
		ci.draw_polyline(run, ROUTE_COL, maxf(9.0, 3.0 / scale))
	if gps.size() > 1:
		var g := PackedVector2Array()
		for q in gps:
			g.append(Vector2(q.x, q.z))
		ci.draw_polyline(g, GPS_COL, maxf(5.0, 4.0 / scale))


func _draw_mini() -> void:
	var _p0 := Time.get_ticks_usec()
	_draw_mini_body()
	Prof.add("minimap_draw", _p0)


func _draw_mini_body() -> void:
	var f: Array = focus.call()
	var pos: Vector3 = f[0]
	var fwd: Vector3 = f[1]
	var c := Vector2(pos.x, pos.z)
	var scale := 0.55                               # px per metre
	var half := MINI * 0.5
	_mini.draw_rect(Rect2(Vector2.ZERO, MINI), BG)
	var rot := -PI * 0.5 - atan2(fwd.z, fwd.x)
	var xf := Transform2D(rot, Vector2(scale, scale), 0.0, half) * Transform2D(0.0, -c)
	_mini.draw_set_transform_matrix(xf)
	_draw_layers(_mini, c, 330.0, scale, true)
	for dst in destinations:
		var p2 := Vector2(dst["pos"].x, dst["pos"].z)
		if p2.distance_to(c) < 330.0:
			_mini.draw_circle(p2, 5.0 / scale, _kind_colour(dst["kind"]))
	if not gps_target.is_empty():
		var tp := Vector2(gps_target["pos"].x, gps_target["pos"].z)
		_mini.draw_circle(tp, 8.0 / scale, GPS_COL)
	_mini.draw_set_transform_matrix(Transform2D.IDENTITY)
	# you: an arrow pointing up
	_mini.draw_colored_polygon(PackedVector2Array([half + Vector2(0, -11), half + Vector2(8, 9), half + Vector2(0, 4),
		half + Vector2(-8, 9)]), Color.WHITE)
	_mini.draw_string(get_theme_default_font(), half + Vector2(cos(-PI * 0.5 + rot), sin(-PI * 0.5 + rot)) * 118.0 - Vector2(5, -5),
		"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))
	_mini.draw_rect(Rect2(Vector2.ZERO, MINI), Color(0, 0, 0, 0.8), false, 3.0)


func _draw_full() -> void:
	var sz := _full.size
	_full.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.1, 0.13, 0.1, 0.97))
	var xf := Transform2D(0.0, Vector2(full_scale, full_scale), 0.0, sz * 0.5) * Transform2D(0.0, -full_centre)
	_full.draw_set_transform_matrix(xf)
	var radius := sz.length() * 0.5 / full_scale
	_draw_layers(_full, full_centre, radius, full_scale, full_scale > 0.35)
	for dst in destinations:
		var p2 := Vector2(dst["pos"].x, dst["pos"].z)
		_full.draw_circle(p2, 5.0 / full_scale, _kind_colour(dst["kind"]))
	var f: Array = focus.call()
	var me := Vector2(f[0].x, f[0].z)
	_full.draw_circle(me, 9.0 / full_scale, Color.WHITE)
	_full.draw_circle(me, 6.0 / full_scale, Color(0.1, 0.5, 1.0))
	if not gps_target.is_empty():
		_full.draw_circle(Vector2(gps_target["pos"].x, gps_target["pos"].z), 10.0 / full_scale, GPS_COL)
	_full.draw_set_transform_matrix(Transform2D.IDENTITY)
	# labels in screen space so they stay readable
	var font := get_theme_default_font()
	for tname in towns_data:
		var tc: Array = towns_data[tname]["centre"]
		var sp := xf * Vector2(tc[0], tc[1])
		_full.draw_string_outline(font, sp - Vector2(60, 0), tname.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
		_full.draw_string(font, sp - Vector2(60, 0), tname.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.95, 0.85))
	if full_scale > 0.25:
		for dst in destinations:
			var sp2 := xf * Vector2(dst["pos"].x, dst["pos"].z)
			if Rect2(Vector2.ZERO, sz).has_point(sp2):
				_full.draw_string_outline(font, sp2 + Vector2(8, 4), dst["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
				_full.draw_string(font, sp2 + Vector2(8, 4), dst["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	else:
		for dst in destinations:
			if dst["kind"] in ["Resort", "Viewpoint", "Check post", "Bridge"]:
				var sp3 := xf * Vector2(dst["pos"].x, dst["pos"].z)
				_full.draw_string(font, sp3 + Vector2(8, 4), dst["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.6))
	if not gps.is_empty():
		_full.draw_string(font, Vector2(24, sz.y - 30), _gps_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.8, 0.95))


func _kind_colour(kind: String) -> Color:
	match kind:
		"Resort": return Color(0.3, 1.0, 0.5)
		"Bus stand": return Color(0.2, 0.55, 1.0)
		"Temple": return Color(1.0, 0.55, 0.1)
		"Market": return Color(0.9, 0.3, 0.6)
		"Railway station": return Color(0.6, 0.4, 1.0)
		"Hospital": return Color(1.0, 0.25, 0.25)
		_: return Color(1.0, 1.0, 0.7)


# ----------------------------------------------------------------------------- input on the full map
func _full_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			full_scale = minf(full_scale * 1.25, 3.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			full_scale = maxf(full_scale / 1.25, 0.01)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			clear_destination()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_dragging = true
			_click(ev.position)
		_full.queue_redraw()
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	elif ev is InputEventMouseMotion and _dragging:
		full_centre -= ev.relative / full_scale
		_full.queue_redraw()


func _click(screen: Vector2) -> void:
	var sz := _full.size
	var world := full_centre + (screen - sz * 0.5) / full_scale
	var best := {}
	var bd := 14.0 / full_scale
	for dst in destinations:
		var dd := Vector2(dst["pos"].x, dst["pos"].z).distance_to(world)
		if dd < bd:
			bd = dd
			best = dst
	if not best.is_empty():
		set_destination(best["pos"], best["name"])
	elif Input.is_key_pressed(KEY_SHIFT):
		# shift-click anywhere: nearest road point
		var id := nav.closest(Vector3(world.x, 0, world.y))
		if id >= 0:
			set_destination(nav.astar.get_point_position(id), "Marked point")
