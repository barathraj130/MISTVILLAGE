extends Control
## The driving HUD for the chase and bonnet views (the cockpit has its own dials): speed, gear and a rev bar,
## bottom right, quiet and readable over the street.

var car

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if car == null or car.cockpit:
		return
	var vs := get_viewport_rect().size
	var c := Vector2(vs.x - 150.0, vs.y - 110.0)
	draw_circle(c, 92.0, Color(0, 0, 0, 0.35))
	var f := ThemeDB.fallback_font
	var kmh := roundi(absf(car.speed) * 3.6)
	draw_string(f, c + Vector2(-60, 14), "%d" % kmh, HORIZONTAL_ALIGNMENT_CENTER, 120, 46, Color(1, 1, 1, 0.95))
	draw_string(f, c + Vector2(-60, 40), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 1, 0.6))
	var g: String = ("M" if car.manual else "") + (car.gear_name() if car.gear > 0 else "R")
	draw_string(f, c + Vector2(-60, -30), g, HORIZONTAL_ALIGNMENT_CENTER, 120, 26, Color(1.0, 0.82, 0.3, 0.95))
	# the rev arc: 0 .. redline round the bottom-left, red near the top
	var frac := clampf(car.rpm / car.REDLINE, 0.0, 1.0)
	var a0 := deg_to_rad(140.0)
	var a1 := deg_to_rad(400.0)
	draw_arc(c, 84.0, a0, a1, 48, Color(1, 1, 1, 0.15), 6.0, true)
	var col := Color(0.4, 0.85, 1.0, 0.9) if frac < 0.85 else Color(1.0, 0.3, 0.2, 0.95)
	draw_arc(c, 84.0, a0, lerpf(a0, a1, frac), 48, col, 6.0, true)
