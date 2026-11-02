extends Node
## Karthik's body and mind, kept in the save file with the wallet (each 0..100):
##   energy     food in him. It runs down by the game hour (faster when he works the streets); a meal fills it.
##              Under 25 he's hungry and can't run; at 0 it starts to wear on his nerves too.
##   tiredness  how long he's been on his feet. It climbs by the game hour, faster behind the wheel. Only sleep
##              clears it, and sleep is at least 5 game hours: his cot at home (Ganapathy), or a hotel room.
##              Over 80 he's warned; at 100 he can't go on: out of the car, he falls asleep where he is (5 hours,
##              badly: stress goes up); behind the wheel the screen dims until he stops, then he sleeps in his seat.
##   stress     traffic, every e-challan and fine, money going out (pay coming in eases it a little), hunger, bad
##              sleep. What brings it down is what people here do to get away for a while: a ticket for the match
##              at Nehru Stadium, a film at the mall's multiplex, a tea at a tea stall, a quiet sit in a pew.
## Each of these is at its own spot in a room (city_doors.gd offers it: "E: ..."): it costs what it costs, and its
## hours pass while we see him there (the stand, the cot), the clock and the light running on; sleep is his eyes
## closing and opening again. No caption, no numbers (GAME_DESIGN.md §8): body.gd shows what it did to him, and
## F1 brings back the bars (show_meters).

const Sim := preload("res://scripts/drive/sim.gd")
const STRESS0 := 55.0                # where the story finds him: a lot on his mind
const ENERGY_PER_HOUR := 7.0         # a full stomach lasts about 14 game hours
const TIRED_PER_HOUR := 5.5          # about 18 game hours awake to the end of him
const DRIVING_EXTRA := 2.5           # tiredness per game hour more, behind the wheel
const DRIVE_STRESS_PER_MIN := 1.2    # stress per real minute driving through the traffic
const CHALLAN := 6.0
const PER_RUPEE_LOST := 1.0 / 150.0
const PER_RUPEE_EARNED := 1.0 / 400.0
const SLEEP_MIN_HOURS := 5.0
const Body := preload("res://scripts/city/body.gd")

## room → what there is to do there. mark: the room's empty to stand at; cost (₹); hours (game); stress: change;
## food: energy gained; sleep: a night's sleep (hours from how tired he is, never under 5); groceries: eats one of the
## month's meals at home; seat: where we see him while it lasts.
const DOINGS := {
	"stadium": [{"mark": "Mark_ticket", "cost": 60, "hours": 2.0, "stress": -35.0, "seat": "Mark_seat", "pose": "Sit",
		"drop": 0.47,
		"offer": "Buy a ticket (₹60) and watch the match",
		"caption": "Coimbatore vs Madurai at Nehru Stadium. The crowd on its feet for the second goal."}],
	"mall_avinashi": [{"mark": "Mark_ticket", "cost": 190, "hours": 2.75, "stress": -40.0, "food": 10.0,
		"offer": "Buy a ticket (₹190) for the film",
		"caption": "Kovai Express on the big screen. Popcorn, the AC, nobody calling for three hours."}],
	"mall_sathy": [{"mark": "Mark_ticket", "cost": 190, "hours": 2.75, "stress": -40.0, "food": 10.0,
		"offer": "Buy a ticket (₹190) for the film",
		"caption": "Mazhai Kaalam at the multiplex. He laughs out loud at the interval scene."}],
	"church": [{"mark": "Mark_pray", "cost": 0, "hours": 0.5, "stress": -12.0,
		"offer": "Sit a while in the quiet", "caption": "The fans turning slowly. The noise of the road far away."}],
	"temple_hall": [{"mark": "Mark_pray", "cost": 0, "hours": 0.75, "stress": -18.0,
		"offer": "Pray at the sanctum", "caption": "The bell, the camphor flame, the priest's chant. His mind goes quiet."}],
	"tea": [{"mark": "Staff", "cost": 20, "hours": 0.25, "stress": -6.0, "food": 12.0,
		"offer": "A tea and a vada (₹20)", "caption": "Strong tea in a glass, a hot vada, the street going by."}],
	"kirana": [{"mark": "Staff", "cost": 30, "hours": 0.1, "food": 15.0,
		"offer": "Biscuits and a banana (₹30)", "caption": "A packet of biscuits and a banana, eaten at the counter."}],
	"restaurant": [{"mark": "Staff", "cost": 120, "hours": 0.5, "food": 60.0, "stress": -4.0,
		"offer": "Meals (₹120)", "caption": "Rice, sambar, rasam, two vegetables, curd. He finishes everything."}],
	"mess": [{"mark": "Mark_cook", "cost": 90, "hours": 0.5, "food": 60.0, "stress": -4.0,
		"offer": "Meals on a leaf (₹90)", "caption": "Meals on a banana leaf, a second helping of rice."}],
	"fine_dining": [{"mark": "Mark_cook", "cost": 1450, "hours": 1.0, "food": 70.0, "stress": -12.0,
		"offer": "Lunch at the restaurant (₹1,450)", "caption": "White linen, a quiet room, a meal he'll talk about for weeks."}],
	"hotel": [{"mark": "Staff", "cost": 1800, "sleep": true, "stress": -5.0,
		"offer": "A room for the night (₹1,800): sleep", "caption": "A clean room, the AC humming. He's asleep in minutes."}],
	"home": [{"mark": "Mark_karthik_room", "cost": 0, "sleep": true, "stress": -15.0, "seat": "Mark_karthik_room",
		"offer": "Sleep", "caption": "His own cot, the fan overhead, Amma's radio low in the hall."},
		{"mark": "Mark_kitchen", "cost": 0, "hours": 0.5, "food": 60.0, "stress": -5.0, "groceries": true,
		"offer": "Eat at home", "caption": "Amma's rice and kuzhambu, still warm."}],
}

var city                             # city_test.gd: walker, car, fines, hud, story
var stress := STRESS0
var energy := 70.0
var tiredness := 30.0
var busy := false                    # an outing (or sleep) under way: the doors and the walker wait
var _money := -1
var _challans := -1
var _clock := -1.0                   # the game clock (day * 1440 + minute) last frame
var _warn := {}
var _card: ColorRect
var body                             # body.gd: his eyes, his heart, his stomach
var show_meters := false             # F1: the bars under the wallet
var _f1_down := false
var waiting := false                 # sit_wait under way


func _ready() -> void:
	var sd: Dictionary = city.fines._save_data
	stress = float(sd.get("stress", STRESS0))
	energy = float(sd.get("energy", 70.0))
	tiredness = float(sd.get("tiredness", 30.0))
	for arg in OS.get_cmdline_user_args():            # (testing: --life=energy,tiredness,stress to start from)
		if arg.begins_with("--life="):
			var v := arg.get_slice("=", 1).split(",")
			energy = float(v[0])
			tiredness = float(v[1])
			stress = float(v[2])
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_card = ColorRect.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.color = Color(0, 0, 0, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_card)
	body = Body.new()
	body.life = self
	add_child(body)
	show_meters = "--meters" in OS.get_cmdline_user_args()


func _clock_now() -> float:
	return city.fines.sim.day * 1440.0 + city.fines.sim.minute


func _process(dt: float) -> void:
	var f = city.fines
	if f == null:
		return
	if _money < 0:
		_money = f.sim.money
		_challans = f.challans.size()
		_clock = _clock_now()
	var f1 := Input.is_key_pressed(KEY_F1)
	if f1 and not _f1_down:
		show_meters = not show_meters
	_f1_down = f1
	if busy:
		return
	var hours := clampf((_clock_now() - _clock) / 60.0, 0.0, 24.0)   # game hours since last frame (story jumps too)
	if city.story == null:                            # (free roam has no running clock: his day goes on at its pace)
		hours = dt * Sim.MINUTES_PER_SECOND / 60.0
	_clock = _clock_now()
	var driving: bool = city.walker == null and absf(city.car.speed) > 2.0
	energy = clampf(energy - ENERGY_PER_HOUR * hours, 0.0, 100.0)
	tiredness = clampf(tiredness + (TIRED_PER_HOUR + (DRIVING_EXTRA if driving else 0.0)) * hours, 0.0, 100.0)
	if energy <= 0.0:
		add_stress(4.0 * hours)
	if f.sim.money != _money:                         # money in or out
		var d: int = f.sim.money - _money
		add_stress(-d * PER_RUPEE_LOST if d < 0 else -d * PER_RUPEE_EARNED)
		_money = f.sim.money
	if f.challans.size() > _challans:
		add_stress(CHALLAN * (f.challans.size() - _challans))
	_challans = f.challans.size()
	if driving:
		add_stress(DRIVE_STRESS_PER_MIN * dt / 60.0)
	var w = city.walker
	if w:                                             # hungry or worn out: no running
		var run: float = 4.2 if w.avatar_run_stride else 7.0
		w.run_speed = w.walk_speed if (energy < 25.0 or stress > 90.0 or tiredness > 90.0) else run
	_nag(dt, "food", energy < 25.0, "Karthik is hungry. Time to eat something.")
	_nag(dt, "sleep", tiredness > 80.0, "Karthik needs sleep: home, or a hotel.")
	_nag(dt, "stress", stress > 75.0, "Karthik is stressed. A match or a film?")
	if tiredness >= 100.0:
		if city.walker and not _story_busy():           # on his feet: he drops off where he is
			collapse()
		elif city.walker == null and absf(city.car.speed) < 0.5 and not _story_busy():   # pulled over: asleep at the wheel
			_card.color.a = 0.0
			_warn.erase("wheel")
			_pass(SLEEP_MIN_HOURS * 60.0, "He pulls over, puts the seat back and is asleep at once.", null,
				{"sleep": true, "stress": 6.0, "rough": true})
		elif driving:
			body.lids_hold = 0.45 + 0.35 * sin(Time.get_ticks_msec() / 400.0)   # his eyes closing at the wheel
			if not _warn.has("wheel"):
				_warn["wheel"] = 0.0
				print("LIFE dozing at the wheel")
	elif body.lids_hold > 0.0 and not busy:
		body.lids_hold = 0.0


func _nag(dt: float, key: String, on: bool, text: String) -> void:
	_warn[key] = float(_warn.get(key, 0.0)) - dt
	if on and _warn[key] <= 0.0 and show_meters:          # (otherwise his body says it: body.gd)
		_warn[key] = 180.0
		city.hud.warn(text, 5.0)


func _story_busy() -> bool:
	var st = city.story if "story" in city else null
	return st != null and (st.room != null or (st.has_method("claims_e") and city.walker and st.claims_e(city.walker.global_position)))


func add_stress(v: float) -> void:
	stress = clampf(stress + v, 0.0, 100.0)


func save() -> void:
	var sd: Dictionary = city.fines._save_data
	sd["stress"] = snappedf(stress, 0.1)
	sd["energy"] = snappedf(energy, 0.1)
	sd["tiredness"] = snappedf(tiredness, 0.1)
	city.fines.save()


## What there is to do in this room near p, if anything (one of DOINGS[room_name]).
func offer(room_name: String, room: Node3D, p: Vector3) -> Dictionary:
	if busy or not DOINGS.has(room_name) or room == null:
		return {}
	for d in DOINGS[room_name]:
		var m := room.find_child(d["mark"], true, false) as Node3D
		if m and Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length() < 1.8:
			return d
	return {}


func sleep_hours() -> float:
	return clampf(tiredness / 100.0 * 8.0, SLEEP_MIN_HOURS, 9.0)


## Do it: pay, the hours pass while we see him there, then what it did to him.
func go(d: Dictionary, room: Node3D) -> void:
	var f = city.fines
	var cost: int = d.get("cost", 0)
	if f.sim.money < cost:
		city.hud.warn("Not enough in the wallet for that.", 3.0)
		return
	if d.get("groceries", false) and f.sim.groceries <= 0:
		city.hud.warn("The month's groceries are finished: buy them at the kirana.", 4.0)
		return
	if d.get("sleep", false) and tiredness < 35.0:
		city.hud.warn("He isn't tired enough to sleep yet.", 3.0)
		return
	f.sim.money -= cost
	_money = f.sim.money
	if d.get("groceries", false):
		f.sim.groceries -= 1
	var mins: float = (sleep_hours() if d.get("sleep", false) else float(d.get("hours", 0.5))) * 60.0
	var seat: Node3D = room.find_child(d.get("seat", "-"), true, false) as Node3D if room else null
	await _pass(mins, d["caption"], seat, d)


## He's on his feet past the end of him: asleep where he stands, 5 hours, badly.
func collapse() -> void:
	await _pass(SLEEP_MIN_HOURS * 60.0, "He sits down for a moment and is asleep before he knows it.", null,
		{"sleep": true, "stress": 10.0, "rough": true})


func _pass(mins: float, caption: String, seat: Node3D, d: Dictionary) -> void:
	busy = true
	var w: Node3D = city.walker
	if w:
		w.set_physics_process(false)
	var sleep: bool = d.get("sleep", false)
	if sleep:
		await body.eyes(true, 2.0)                     # his eyes close
	else:
		await _fade(1.0, 0.6)
	if seat and w:                                     # (the stand, the cot: there he is)
		w.global_position = seat.global_position - Vector3(0, float(d.get("drop", 0.0)), 0)
		w.rotation.y = seat.global_rotation.y + PI
		if d.has("pose") and w.anim and w.anim.has_animation(d["pose"]):   # sitting in his seat with everyone
			w.anim.play(d["pose"], 0.3)
	if not sleep and seat:
		await _fade(0.0, 0.6)                          # we watch him there while the hours go
	var was: Array[int] = [roundi(energy), roundi(tiredness), roundi(stress)]
	await _run_clock(mins, clampf(mins / 60.0 * 1.6, 3.0, 9.0))
	energy = clampf(energy + float(d.get("food", 0.0)) - (2.0 * mins / 60.0 if sleep else 0.0), 0.0, 100.0)
	if sleep:
		tiredness = 25.0 if d.get("rough", false) else 0.0
	add_stress(float(d.get("stress", 0.0)))
	if sleep:
		await body.eyes(false, 1.6)                    # and open
	elif _card.color.a > 0.0:
		await _fade(0.0, 0.6)
	if w and is_instance_valid(w):
		w.set_physics_process(true)
		(w as CharacterBody3D).velocity = Vector3.ZERO
	save()
	busy = false
	var parts: Array = []
	for k in 3:
		var now: int = [roundi(energy), roundi(tiredness), roundi(stress)][k]
		if now != was[k]:
			parts.append("%s %d → %d" % [["energy", "tiredness", "stress"][k], was[k], now])
	print("LIFE %s: %s" % [caption.left(40), " · ".join(parts)])


## The clock runs on: mins of game time in secs of real time (the sun and the street lights with it).
func _run_clock(mins: float, secs: float) -> void:
	var f = city.fines
	var done := 0.0
	while done < mins:
		await get_tree().process_frame
		var step := minf(mins * get_process_delta_time() / secs, mins - done)
		done += step
		f.sim.minute += step
		while f.sim.minute >= 1440.0:
			f.sim.minute -= 1440.0
			f.sim.day += 1
		_clock = _clock_now()


## Sit and wait (a bench, a chair): he sits there and the time runs fast, 20 game minutes a second, until the clock
## reaches until_min (a game minute of the day) or the player gets up (W, S, E or Space). Awaitable.
func sit_wait(seat: Node3D, until_min: float, pose := "Sit") -> void:
	var w = city.walker
	if w == null or busy:
		return
	busy = true
	waiting = true
	w.set_physics_process(false)
	if seat:
		w.global_position = seat.global_position
		w.rotation.y = seat.global_rotation.y + PI
	if w.anim and w.anim.has_animation(pose):
		w.anim.play(pose, 0.3)
	var f = city.fines
	await get_tree().create_timer(0.6).timeout
	while waiting:
		await get_tree().process_frame
		var left: float = until_min - f.sim.minute
		if left <= 0.0 or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_SPACE):
			break
		var step := minf(20.0 * get_process_delta_time(), left)
		f.sim.minute += step
		var hours := step / 60.0
		energy = clampf(energy - ENERGY_PER_HOUR * hours, 0.0, 100.0)
		tiredness = clampf(tiredness + TIRED_PER_HOUR * 0.6 * hours, 0.0, 100.0)
		_clock = _clock_now()
	waiting = false
	if is_instance_valid(w):
		w.set_physics_process(true)
		if w.anim and w.anim.has_animation("Idle"):
			w.anim.play("Idle", 0.3)
	busy = false


func _fade(to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(_card, "color:a", to, secs)
	await tw.finished


static func Sim_clock(m: float) -> String:
	return "%02d:%02d" % [floori(m / 60.0) % 24, floori(fmod(m, 60.0))]


static func _hours(mins: float) -> String:
	if mins < 60.0:
		return "%d minutes" % roundi(mins)
	var h := floori(mins / 60.0)
	var m := roundi(mins - h * 60.0)
	return ("%d hours" % h if h > 1 else "An hour") + (" %d minutes" % m if m > 0 else "")
