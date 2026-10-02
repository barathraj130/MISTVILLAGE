extends RefCounted
## The two screens of a modern cab, drawn live into SubViewports and shown on the dashboard:
## a digital driver display (blue speed and rev arcs, big speed, gear, fuel, clock, indicators,
## warning lamps) and a navigation screen (moving map with your GPS route, like the minimap).

class Cluster extends Control:
	var car
	var clock := ""
	var fuel := 1.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.06:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.01, 0.012, 0.018))
		if car == null:
			return
		var font := get_theme_default_font()
		var kmh := absf(car.speed) * 3.6
		var c1 := Vector2(sz.x * 0.22, sz.y * 0.56)
		var c2 := Vector2(sz.x * 0.78, sz.y * 0.56)
		var r := sz.y * 0.4
		_arc(c1, r, clampf(kmh / 180.0, 0.0, 1.0), Color(0.15, 0.6, 1.0))
		_arc(c2, r, clampf(car.rpm / 5000.0, 0.0, 1.0), Color(0.15, 0.85, 0.9) if car.rpm < 4000.0 else Color(1.0, 0.35, 0.2))
		for k in 10:                                         # scale marks
			for cc in [c1, c2]:
				var a := deg_to_rad(150.0 + 240.0 * k / 9.0)
				draw_line(cc + Vector2(cos(a), sin(a)) * r * 0.82, cc + Vector2(cos(a), sin(a)) * r * 0.92, Color(0.6, 0.65, 0.7), 2.0)
		draw_string(font, c1 + Vector2(-60, 22), "%d" % roundi(kmh), HORIZONTAL_ALIGNMENT_CENTER, 120, 54, Color.WHITE)
		draw_string(font, c1 + Vector2(-60, 50), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(0.6, 0.7, 0.8))
		draw_string(font, c2 + Vector2(-60, 22), "%.1f" % (car.rpm / 1000.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 40, Color.WHITE)
		draw_string(font, c2 + Vector2(-60, 50), "×1000 rpm", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(0.6, 0.7, 0.8))
		# centre column: gear, clock, fuel bar
		var mid := sz.x * 0.5
		var gear: String = ("M" if car.manual else "D") + car.gear_name() if car.gear > 0 else "R"
		draw_string(font, Vector2(mid - 60, sz.y * 0.48), gear, HORIZONTAL_ALIGNMENT_CENTER, 120, 46, Color(0.9, 0.95, 1.0))
		draw_string(font, Vector2(mid - 60, sz.y * 0.16), clock, HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(0.75, 0.8, 0.85))
		var bar := Rect2(mid - 50, sz.y * 0.68, 100, 10)
		draw_rect(bar, Color(0.15, 0.17, 0.2))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fuel, bar.size.y)), Color(1.0, 0.55, 0.1) if fuel < 0.12 else Color(0.2, 0.75, 1.0))
		draw_string(font, Vector2(mid - 60, sz.y * 0.68 + 30), "DIESEL", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.55, 0.6, 0.65))
		# indicator arrows and warnings along the top
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.66) < 0.36
		var green := Color(0.15, 1.0, 0.35)
		if blink and (car.indicator == 1 or car.indicator == 2):
			draw_colored_polygon(PackedVector2Array([Vector2(mid - 140, 26), Vector2(mid - 116, 12), Vector2(mid - 116, 40)]), green)
		if blink and (car.indicator == -1 or car.indicator == 2):
			draw_colored_polygon(PackedVector2Array([Vector2(mid + 140, 26), Vector2(mid + 116, 12), Vector2(mid + 116, 40)]), green)
		if car.lights_on:
			draw_string(font, Vector2(mid - 95, 34), "◉", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.2, 0.55, 1.0))
		if car.in_handbrake:
			draw_string(font, Vector2(mid + 70, 34), "(P)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.2, 0.15))

	func _arc(c: Vector2, r: float, f: float, col: Color) -> void:
		var a0 := deg_to_rad(150.0)
		var a1 := deg_to_rad(390.0)
		draw_arc(c, r, a0, a1, 48, Color(0.1, 0.13, 0.18), r * 0.12, true)
		if f > 0.002:
			draw_arc(c, r, a0, lerpf(a0, a1, f), 48, col, r * 0.12, true)


class Nav extends Control:
	var map_ui
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.15:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.1, 0.09))
		if map_ui == null or map_ui.focus.is_null():
			return
		var f: Array = map_ui.focus.call()
		var pos: Vector3 = f[0]
		var fwd: Vector3 = f[1]
		var c := Vector2(pos.x, pos.z)
		var scale := 0.9
		var me := Vector2(sz.x * 0.5, sz.y * 0.68)
		var rot := -PI * 0.5 - atan2(fwd.z, fwd.x)
		draw_set_transform_matrix(Transform2D(rot, Vector2(scale, scale), 0.0, me) * Transform2D(0.0, -c))
		map_ui._draw_layers(self, c, 260.0, scale, true)
		if not map_ui.gps_target.is_empty():
			var tp := Vector2(map_ui.gps_target["pos"].x, map_ui.gps_target["pos"].z)
			draw_circle(tp, 8.0 / scale, Color(0.95, 0.2, 0.75))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_colored_polygon(PackedVector2Array([me + Vector2(0, -16), me + Vector2(12, 12), me + Vector2(0, 5), me + Vector2(-12, 12)]),
			Color(0.2, 0.6, 1.0))
		# top bar: next destination / distance, like a real head unit
		draw_rect(Rect2(0, 0, sz.x, 34), Color(0, 0, 0, 0.7))
		var font := get_theme_default_font()
		var label: String = map_ui._gps_label.text if map_ui._gps_label.text != "" else "No destination · Tab to set GPS"
		draw_string(font, Vector2(12, 24), label, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 24, 18, Color(0.95, 0.95, 0.95))
		draw_rect(Rect2(0, sz.y - 30, sz.x, 30), Color(0, 0, 0, 0.6))
		for i in 6:
			draw_circle(Vector2(sz.x * (0.12 + 0.152 * i), sz.y - 15), 7, Color(0.6, 0.65, 0.7, 0.8))


## A screen in the car: a lit quad at `xf` of size `w`×`h` m showing `control` drawn at `px` pixels.
static func screen(parent: Node3D, control: Control, px: Vector2i, xf: Transform3D, w: float, h: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	control.size = Vector2(px)
	vp.add_child(control)
	parent.add_child(vp)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	parent.add_child(mi)
	vp.set_meta("quad", mi)
	return vp
