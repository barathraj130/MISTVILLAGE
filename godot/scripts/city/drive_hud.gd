extends Control
## The driving HUD (hud_style.gd's look; the cockpit has its own dials). Everything on it is read from the game:
##   speed cluster  bottom right: the speed (eased a tenth of a second, so it never lies for long), km/h, the gear as
##                  the car has it (R, or the gear with AUTO / MANUAL), the revs as a thin bar with its redline
##   status         over the cluster, only what is so right now: handbrake, headlights, indicators or hazards (as
##                  they blink), body damage. (No fuel gauge in the city: it doesn't count fuel there.)
##   where & when   top left: the story's day, the time, the weather, the road you're on (the map's own names)
##   objective      under it: what the story wants now (its goal, as the phone has it), a deadline if it has one,
##                  the distance to its pin; after 12 s unchanged it folds to one line (the objective and distance)
##   notifications  top centre: a warning (a red light jumped, a challan) slides in and fades
##   subtitles      bottom centre: who speaks, and what
## F1 still brings back Karthik's meters (life.gd show_meters), top right.

const UI := preload("res://scripts/ui/hud_style.gd")
const Prof := preload("res://scripts/drive/prof.gd")
const FOLD_SECS := 12.0

var car
var fines                          # wallet and challans (fines.gd), when playing
var life                           # Karthik's stress (life.gd)
var message := ""                  # a short warning shown for a few seconds (e.g. a red light jumped)
var message_time := 0.0
var said_who := ""                 # a spoken line (a policeman, Karthik to himself): who and what, subtitled
var said := ""
var said_time := 0.0

var _kmh := 0.0                    # the speed shown, eased
var _gear_seen := ""
var _gear_pulse := 0.0             # a gear change: the gear brightens and settles
var _objective := ""
var _objective_age := 0.0
var _fold := 0.0                   # 0 open .. 1 folded
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	message_time = maxf(0.0, message_time - dt)
	said_time = maxf(0.0, said_time - dt)
	if car:
		_kmh = lerpf(_kmh, absf(car.speed) * 3.6, 1.0 - exp(-dt * 10.0))
		var g := _gear()
		if g != _gear_seen:
			_gear_pulse = 1.0 if _gear_seen != "" else 0.0
			_gear_seen = g
	_gear_pulse = maxf(0.0, _gear_pulse - dt * 2.5)
	var st = _story()
	var obj: String = str(st._goal_first) if st and st.playing() else ""
	if obj != _objective:
		_objective = obj
		_objective_age = 0.0
	_objective_age += dt
	_fold = move_toward(_fold, 1.0 if _objective_age > FOLD_SECS else 0.0, dt * 4.0)
	if st and st.clock:
		st.clock.visible = false                 # (the HUD has the day and the time now)
	queue_redraw()


## Someone says something: shown as a subtitle with their name, as the story's people speak.
func say(who: String, text: String, secs := 3.5) -> void:
	said_who = who
	said = text
	said_time = secs


func warn(text: String, secs := 3.5) -> void:
	message = text
	message_time = secs


func _city():
	return life.city if life and "city" in life else null


func _story():
	var c = _city()
	return c.story if c and "story" in c else null


func _gear() -> String:
	if car == null:
		return ""
	return "R" if car.gear == 0 else car.gear_name()


func _draw() -> void:
	var _p0 := Time.get_ticks_usec()
	_draw_all()
	Prof.add("hud_draw", _p0)


func _draw_all() -> void:
	var k := UI.s(self)
	var vs := get_viewport_rect().size
	_draw_where(k, vs)
	if said_time > 0.0:
		_draw_said(k, vs)
	if message_time > 0.0:
		_draw_message(k, vs)
	if fines and (life == null or life.show_meters):        # (F1: otherwise the phone has the wallet, his body the rest)
		_draw_meters(k, vs)
	var c = _city()
	if car == null or car.cockpit or car.freeze or (c and c.walker != null) or (c and c.indoors):   # (on foot, or
		return                                                                                     #  inside: no speed cluster)
	_draw_cluster(k, vs)


# ---- speed cluster ----
func _draw_cluster(k: float, vs: Vector2) -> void:
	var w := 300.0 * k
	var h := 118.0 * k
	var r := Rect2(vs.x - w - 30.0 * k, vs.y - h - 30.0 * k, w, h)
	UI.panel(self, r, k)
	# the revs: a thin bar along the top, its last part marked as the redline
	var frac := clampf(car.rpm / car.redline, 0.0, 1.0)
	var bar := Rect2(r.position.x + 20.0 * k, r.position.y + 16.0 * k, w - 40.0 * k, 4.0 * k)
	draw_rect(bar, UI.FAINT)
	draw_rect(Rect2(bar.position.x + bar.size.x * 0.86, bar.position.y, bar.size.x * 0.14, bar.size.y), UI.fade(UI.RED, 0.35))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), UI.RED if frac > 0.86 else UI.fade(UI.INK, 0.85))
	# the gear, as the car has it
	var g := _gear()
	var gx := r.position.x + 20.0 * k
	var gcol := UI.AMBER.lerp(Color.WHITE, _gear_pulse * 0.6)
	UI.text(self, Vector2(gx, r.position.y + 78.0 * k), g, (44.0 + 6.0 * _gear_pulse) * k, gcol, 600)
	var mode := "REV" if g == "R" else ("MANUAL" if car.manual else "AUTO")
	UI.text(self, Vector2(gx, r.position.y + 100.0 * k), mode, 11.0 * k, UI.DIM, 600)
	draw_line(Vector2(gx + 84.0 * k, r.position.y + 36.0 * k), Vector2(gx + 84.0 * k, r.end.y - 18.0 * k), UI.FAINT, maxf(1.0, k))
	# the speed
	var sp := "%d" % roundi(_kmh)
	UI.text(self, Vector2(r.position.x, r.position.y + 86.0 * k), sp, 64.0 * k, UI.INK, 700, HORIZONTAL_ALIGNMENT_RIGHT, w - 74.0 * k)
	UI.text(self, Vector2(r.end.x - 66.0 * k, r.position.y + 86.0 * k), "km/h", 15.0 * k, UI.DIM, 500)
	_draw_status(k, Vector2(r.end.x, r.position.y - 10.0 * k))


## The status chips over the cluster, right-aligned: only what is so right now.
func _draw_status(k: float, at: Vector2) -> void:
	var chips: Array = []                       # [label, colour, kind]
	if car.in_handbrake:
		chips.append(["P", UI.AMBER, "text"])
	if car.lights_on:
		chips.append(["LIGHTS", UI.GREEN, "text"])
	var blink := fmod(_t, 0.8) < 0.45
	if car.indicator == 2:
		chips.append(["HAZARDS", UI.AMBER if blink else UI.FAINT, "text"])
	elif car.indicator == 1:
		chips.append(["", UI.GREEN if blink else UI.FAINT, "left"])
	elif car.indicator == -1:
		chips.append(["", UI.GREEN if blink else UI.FAINT, "right"])
	var dmg := 0.0
	for z in car.damage:
		dmg = maxf(dmg, float(car.damage[z]))
	if dmg > 0.02:
		chips.append(["DAMAGE %d%%" % roundi(dmg * 100.0), UI.RED if dmg > 0.6 else UI.AMBER, "text"])
	var x := at.x
	var h := 26.0 * k
	for c in chips:
		var cw: float = (UI.width_of(c[0], 12.0 * k, 700) + 20.0 * k) if c[2] == "text" else 30.0 * k
		x -= cw
		var rr := Rect2(x, at.y - h, cw, h)
		UI.panel(self, rr, k * 0.6)
		var col: Color = c[1]
		if c[2] == "text":
			UI.text(self, Vector2(rr.position.x, rr.position.y + 17.5 * k), c[0], 12.0 * k, col, 700, HORIZONTAL_ALIGNMENT_CENTER, cw)
		else:                                            # an indicator: a small arrow that blinks
			var m := rr.get_center()
			var d := -1.0 if c[2] == "left" else 1.0
			draw_colored_polygon(PackedVector2Array([m + Vector2(7.0 * d, 0) * k, m + Vector2(-4.0 * d, -6.0) * k,
				m + Vector2(-4.0 * d, 6.0) * k]), col)
		x -= 8.0 * k


# ---- where and when, and the objective ----
func _draw_where(k: float, vs: Vector2) -> void:
	if fines == null:
		return
	var sim = fines.sim
	var st = _story()
	var m: float = sim.minute
	var hh := int(m / 60.0) % 24
	var clock := "%d:%02d %s" % [(hh + 11) % 12 + 1, int(m) % 60, "AM" if hh < 12 else "PM"]
	var wx: String = str(sim.WEATHER.get(sim.weather, {}).get("label", "")) if "WEATHER" in sim else ""
	var head := "%s   %s" % [("DAY %d" % sim.day) if st and sim.day >= 1 else "", clock]   # (the prologue's days
	                                                                                       #  before Day 1: no count)
	head = head.strip_edges()
	var c = _city()
	var road: String = c.map.road_here if c and "map" in c and c.map and "road_here" in c.map else ""
	var x := 30.0 * k
	var y := 30.0 * k
	var w := 420.0 * k
	var lines_h := 58.0 * k
	var has_obj := _objective != ""
	var oh := 0.0
	if has_obj:
		oh = lerpf(96.0, 34.0, _fold) * k
	var r := Rect2(x, y, w, lines_h + oh)
	UI.panel(self, r, k, 1.0, UI.AMBER if has_obj else Color(0, 0, 0, 0))
	UI.text(self, Vector2(x + 20.0 * k, y + 26.0 * k), head, 16.0 * k, UI.INK, 600)
	if wx != "":
		UI.text(self, Vector2(x, y + 26.0 * k), wx, 15.0 * k, UI.DIM, 500, HORIZONTAL_ALIGNMENT_RIGHT, w - 20.0 * k)
	UI.text(self, Vector2(x + 20.0 * k, y + 47.0 * k), road if road != "" else "Coimbatore", 14.0 * k, UI.DIM, 500,
		HORIZONTAL_ALIGNMENT_LEFT, w - 40.0 * k)
	if not has_obj:
		return
	var dist_s := ""
	if c and "map" in c and c.map and c.map.pin != null and car:
		var dd: float = (c.map.pin - Vector2(car.global_position.x, car.global_position.z)).length()
		dist_s = "%.1f km" % (dd / 1000.0) if dd > 950.0 else "%d m" % (int(dd / 10.0) * 10)
	if _fold >= 0.99:                                    # folded: the objective's first line and the distance, small
		draw_line(Vector2(x + 20.0 * k, y + lines_h), Vector2(r.end.x - 20.0 * k, y + lines_h), UI.FAINT, maxf(1.0, k))
		UI.text(self, Vector2(x + 20.0 * k, y + lines_h + 23.0 * k), _objective.get_slice("\n", 0), 14.0 * k, UI.INK, 500,
			HORIZONTAL_ALIGNMENT_LEFT, w - 120.0 * k)
		if dist_s != "":
			UI.text(self, Vector2(x, y + lines_h + 23.0 * k), dist_s, 13.0 * k, UI.GREEN, 700, HORIZONTAL_ALIGNMENT_RIGHT, w - 20.0 * k)
		return
	var a := 1.0 - _fold
	draw_line(Vector2(x + 20.0 * k, y + lines_h), Vector2(r.end.x - 20.0 * k, y + lines_h), UI.fade(UI.FAINT, a), maxf(1.0, k))
	var tag := "OBJECTIVE"
	var cur: Dictionary = st.cur if st else {}
	if cur.has("by"):                                    # a deadline: when it's due
		var hm: PackedStringArray = str(cur["by"]).split(":")
		var bh := int(hm[0])
		tag += "   ·   BY %d:%s %s" % [(bh + 11) % 12 + 1, hm[1], "AM" if bh < 12 else "PM"]
	UI.text(self, Vector2(x + 20.0 * k, y + lines_h + 24.0 * k), tag, 11.0 * k, UI.fade(UI.AMBER, a), 700)
	var obj_font := UI.font(500)
	draw_multiline_string(obj_font, Vector2(x + 20.0 * k, y + lines_h + 48.0 * k), _objective, HORIZONTAL_ALIGNMENT_LEFT,
		w - 40.0 * k, int(17.0 * k), 2, UI.fade(UI.INK, a))
	if dist_s != "":
		UI.text(self, Vector2(x, y + lines_h + 24.0 * k), dist_s, 13.0 * k, UI.fade(UI.GREEN, a), 700, HORIZONTAL_ALIGNMENT_RIGHT, w - 20.0 * k)


# ---- notifications and subtitles ----
func _draw_message(k: float, vs: Vector2) -> void:
	var a := clampf(message_time * 2.0, 0.0, 1.0)
	var slide := (1.0 - clampf((3.5 - message_time) * 6.0, 0.0, 1.0)) * -14.0 * k   # (in from above, once)
	var w := minf(UI.width_of(message, 18.0 * k, 600) + 60.0 * k, vs.x - 80.0 * k)
	var r := Rect2(vs.x * 0.5 - w * 0.5, 34.0 * k + slide, w, 50.0 * k)
	UI.panel(self, r, k, a, UI.RED)
	UI.text(self, Vector2(r.position.x + 8.0 * k, r.position.y + 32.0 * k), message, 18.0 * k, UI.fade(UI.INK, a), 600,
		HORIZONTAL_ALIGNMENT_CENTER, w - 16.0 * k)


func _draw_said(k: float, vs: Vector2) -> void:
	var a := clampf(said_time * 2.0, 0.0, 1.0)
	var w := minf(880.0 * k, vs.x - 80.0 * k)
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y - 200.0 * k, w, 112.0 * k)
	UI.panel(self, r, k, a)
	UI.text(self, r.position + Vector2(24, 34) * k, said_who, 17.0 * k, UI.fade(UI.AMBER, a), 600)
	draw_multiline_string(UI.font(400), r.position + Vector2(24, 66) * k, said, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0 * k,
		int(21.0 * k), 2, UI.fade(UI.INK, a))


# ---- F1: the wallet and Karthik's meters ----
func _draw_meters(k: float, vs: Vector2) -> void:
	var w := 260.0 * k
	var x := vs.x - w - 30.0 * k
	var y := 30.0 * k
	var rows: Array = []
	if life:
		rows = [["Energy", 1.0 - life.energy / 100.0, life.energy / 100.0], ["Tired", life.tiredness / 100.0, life.tiredness / 100.0],
			["Stress", life.stress / 100.0, life.stress / 100.0], ["Hurt", life.hurt / 100.0, life.hurt / 100.0]]
	var bail = life.city.bail if life and life.city and "bail" in life.city else null
	var h := 44.0 * k + (20.0 * k if fines.challans.size() > 0 else 0.0) + rows.size() * 24.0 * k + (26.0 * k if bail and bail.active else 0.0)
	UI.panel(self, Rect2(x, y, w, h), k)
	var cy := y + 28.0 * k
	UI.text(self, Vector2(x + 18.0 * k, cy), "Wallet", 14.0 * k, UI.DIM, 500)
	UI.text(self, Vector2(x, cy), fines.rupees(fines.sim.money), 16.0 * k, UI.INK, 600, HORIZONTAL_ALIGNMENT_RIGHT, w - 18.0 * k)
	if fines.challans.size() > 0:
		cy += 20.0 * k
		UI.text(self, Vector2(x + 18.0 * k, cy), "Challans due", 13.0 * k, UI.fade(UI.RED, 0.9), 500)
		UI.text(self, Vector2(x, cy), fines.rupees(fines.owed()), 14.0 * k, UI.RED, 600, HORIZONTAL_ALIGNMENT_RIGHT, w - 18.0 * k)
	cy += 10.0 * k
	for row in rows:                                     # green good .. red bad
		cy += 24.0 * k
		var bad: float = row[1]
		UI.text(self, Vector2(x + 18.0 * k, cy), row[0], 13.0 * k, UI.DIM, 500)
		var bx := x + 90.0 * k
		var bw := w - 108.0 * k
		draw_rect(Rect2(bx, cy - 8.0 * k, bw, 6.0 * k), UI.FAINT)
		var col := UI.GREEN.lerp(UI.AMBER, clampf(bad * 2.0, 0.0, 1.0))
		if bad > 0.5:
			col = UI.AMBER.lerp(UI.RED, (bad - 0.5) * 2.0)
		draw_rect(Rect2(bx, cy - 8.0 * k, bw * clampf(float(row[2]), 0.0, 1.0), 6.0 * k), col)
	if bail and bail.active:                             # (F1: the bail's count too)
		cy += 26.0 * k
		UI.text(self, Vector2(x + 18.0 * k, cy), "Bail  ·  strikes %d  ·  lates %d  ·  suspicion %d" % [bail.strikes.size(), bail.lates,
			roundi(bail.suspicion)], 12.0 * k, UI.fade(UI.AMBER, 0.9), 500)
