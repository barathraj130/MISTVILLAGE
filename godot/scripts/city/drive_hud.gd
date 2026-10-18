extends Control
## The driving HUD for the chase and bonnet views (the cockpit has its own dials): speed, gear and a rev bar,
## bottom right, quiet and readable over the street.

var car
var fines                          # wallet and challans (fines.gd), when playing
var message := ""                  # a short warning shown for a few seconds (e.g. a red light jumped)
var message_time := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	message_time = maxf(0.0, message_time - dt)
	queue_redraw()


func warn(text: String, secs := 3.5) -> void:
	message = text
	message_time = secs


func _draw() -> void:
	if message_time > 0.0:
		var vs0 := get_viewport_rect().size
		var a := clampf(message_time, 0.0, 1.0)
		draw_rect(Rect2(vs0.x * 0.5 - 260, 70, 520, 54), Color(0.55, 0.02, 0.02, 0.75 * a))
		draw_string(ThemeDB.fallback_font, Vector2(vs0.x * 0.5 - 260, 107), message, HORIZONTAL_ALIGNMENT_CENTER, 520, 26, Color(1, 1, 1, a))
	if fines:
		var vs1 := get_viewport_rect().size
		var f1 := ThemeDB.fallback_font
		draw_rect(Rect2(vs1.x - 250, 18, 232, 56 if fines.challans.size() > 0 else 34), Color(0, 0, 0, 0.4))
		draw_string(f1, Vector2(vs1.x - 240, 42), "Wallet  " + fines.rupees(fines.sim.money), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.92))
		if fines.challans.size() > 0:
			draw_string(f1, Vector2(vs1.x - 240, 64), "Challans due  " + fines.rupees(fines.owed()), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.45, 0.35, 0.95))
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
