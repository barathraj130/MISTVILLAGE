extends Node
## Night on a dark lane (GAME_RULES.md: learnable, not random). A few residential lanes are dark at night, always
## the same ones (from each road piece's own points: about one in thirty residential pieces). Walking down one
## between 9 PM and 5 AM with ₹500 or more in the wallet, a man steps out of a doorway: "Anna. The wallet.
## Quietly." Nobody is hurt, whatever happens:
##   1  hand it over        he takes the cash (up to ₹1,500) and is gone; stress
##   2  pepper spray        (if he has it) a hiss, a shout, the man stumbles off; one use of the can
##   3  whistle             (if he has it) lights in the houses, a man on a terrace shouting: he runs
##   4  walk away, fast     back the way he came: only if he isn't hurt or worn out (hurt over 50, energy under
##                          25, tiredness over 85): then the man catches him up and it's 1 after all
## Once a lane a night. And a scooter left parked within 30 m of one at night for over twenty game minutes is got at
## (the seat box: ₹300 of what's in it, the helmet's visor scratched) unless the disc lock is on it (goods.gd).

const Goods := preload("res://scripts/city/goods.gd")
const SPOT_R := 14.0

var city
var spots := {}                              # Vector2i (tile) → [Vector3, ...]
var _seen_night := {}                        # "x,z:day" → true
var _open := {}                              # the threat now: {"spot", "t"}
var _keys := {}
var _parked := {}                            # the scooter left by a spot: {"spot", "since"}
var _t := 0.0


func _ready() -> void:
	if "--threattest" in OS.get_cmdline_user_args():
		_test.call_deferred()


## (testing) --threattest [--goods=a,b] [--threat=N]: on foot at night, set down at the nearest dark lane.
func _test() -> void:
	var tree := get_tree()
	city.fines.persist = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--goods="):
			for id in a.get_slice("=", 1).split(","):
				Goods.add(city.fines._save_data, id)
	await tree.create_timer(12.0).timeout
	city.fines.sim.minute = 22.0 * 60.0
	city.toggle_on_foot()
	await tree.create_timer(2.0).timeout
	_index()
	var w = city.walker
	var best := Vector3.INF
	for k in spots:
		for sp in spots[k]:
			if best == Vector3.INF or (sp as Vector3).distance_to(w.global_position) < best.distance_to(w.global_position):
				best = sp
	print("THREATTEST spots %d, nearest %.0f m" % [spots.values().reduce(func(n, a): return n + (a as Array).size(), 0), best.distance_to(w.global_position)])
	w.global_position = best + Vector3(0, 1.5, 0)
	w.velocity = Vector3.ZERO
	await tree.create_timer(6.0).timeout
	print("THREATTEST done: wallet %d, bag %s" % [city.fines.sim.money, str(Goods.bag(city.fines._save_data))])
	tree.quit()


func _night() -> bool:
	var m: float = city.fines.sim.minute
	return m >= 21.0 * 60.0 or m < 5.0 * 60.0


func _physics_process(dt: float) -> void:
	if city == null or city.fines == null or city.streamer == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		_index()
		_check_parked()
	if not _open.is_empty():
		_answer(dt)
		return
	var w = city.walker
	if w == null or not _night() or city.fines.sim.money < 500 or (city.life and city.life._story_busy()):
		return
	for s in _spots_near(w.global_position):
		var key := "%d,%d:%d" % [roundi(s.x), roundi(s.z), city.fines.sim.day]
		if _seen_night.has(key):
			continue
		if Vector2(s.x - w.global_position.x, s.z - w.global_position.z).length() < SPOT_R:
			_seen_night[key] = true
			_start(s)
			return


## The dark lanes of the loaded tiles.
func _index() -> void:
	for k in city.streamer.loaded:
		if spots.has(k):
			continue
		var tile = city.streamer.loaded[k]
		var out: Array = []
		for r in (tile as Node3D).get_meta("roads", []):
			if str(r["c"]) != "residential" and str(r["c"]) != "living_street":
				continue
			var p: PackedFloat32Array = r["p"]
			if p.size() < 6 or absi(hash(Vector2i(roundi(p[0]), roundi(p[2])))) % 30 != 0:
				continue
			var mid := p.size() / 3 / 2
			out.append(Vector3(p[mid * 3], p[mid * 3 + 1], p[mid * 3 + 2]))
		spots[k] = out
	for k in spots.keys():
		if not city.streamer.loaded.has(k):
			spots.erase(k)


func _spots_near(at: Vector3) -> Array:
	var out: Array = []
	for k in spots:
		for s in spots[k]:
			if (s as Vector3).distance_to(at) < 60.0:
				out.append(s)
	return out


func _start(s: Vector3) -> void:
	_open = {"spot": s, "t": 14.0}
	var has_spray := Goods.has(city.fines._save_data, "pepper_spray")
	var has_whistle := Goods.has(city.fines._save_data, "whistle")
	var opts := [city._t({"en": "1 hand over the wallet", "ta": "1 பர்ஸ குடு"})]
	if has_spray:
		opts.append(city._t({"en": "2 pepper spray", "ta": "2 பெப்பர் ஸ்ப்ரே"}))
	if has_whistle:
		opts.append(city._t({"en": "3 whistle", "ta": "3 விசில்"}))
	opts.append(city._t({"en": "4 walk away, fast", "ta": "4 வேகமா நடந்து போ"}))
	city.hud.say(city._t({"en": "A man in a doorway", "ta": "வாசல்ல ஒரு ஆள்"}),
		city._t({"en": "Anna. The wallet. Quietly, and nobody gets hurt.", "ta": "அண்ணா. பர்ஸ். சத்தம் இல்லாம குடு, யாருக்கும் ஒண்ணும் ஆகாது."}), 6.0)
	city.hud.warn("   ".join(opts), 14.0)
	print("THREAT on a dark lane at %s (spray %s, whistle %s)" % [str(s.round()), has_spray, has_whistle])


func _answer(dt: float) -> void:
	_open["t"] = float(_open["t"]) - dt
	var pick := 0
	for i in 4:
		var down := Input.is_key_pressed(KEY_1 + i)
		if down and not _keys.get(i, false):
			pick = i + 1
		_keys[i] = down
	for a in OS.get_cmdline_user_args():                # (testing: --threat=N answers it)
		if a.begins_with("--threat="):
			pick = int(a.get_slice("=", 1))
	if pick == 0 and float(_open["t"]) <= 0.0:
		pick = 1                                        # (frozen too long: he takes it)
	if pick == 0:
		return
	var sd: Dictionary = city.fines._save_data
	if pick == 2 and not Goods.has(sd, "pepper_spray") or pick == 3 and not Goods.has(sd, "whistle"):
		return
	var life = city.life
	if pick == 4 and life and (life.hurt > 50.0 or life.energy < 25.0 or life.tiredness > 85.0):
		city.hud.say("Karthik", city._t({"en": "(My legs won't go. He's beside me before the corner.)",
			"ta": "(கால் ஓடல. மூலைக்கு முன்னாடியே அவன் பக்கத்துல வந்துட்டான்.)"}), 4.0)
		pick = 1
	var line := {}
	match pick:
		1:
			var took: int = mini(city.fines.sim.money, 1500)
			city.fines.sim.money -= took
			if life:
				life.add_stress(14.0)
			line = {"en": "(He takes the notes and is gone between the houses. ₹%d.)" % took,
				"ta": "(நோட்ட எடுத்துட்டு வீடுகளுக்கு நடுவுல மறைஞ்சுட்டான். ₹%d.)" % took}
		2:
			Goods.take(sd, "pepper_spray")
			if life:
				life.add_stress(6.0)
			line = {"en": "(A hiss. He shouts, his hands over his eyes, and stumbles off down the lane.)",
				"ta": "(ஒரு ஸ்ஸ். கண்ண மூடிக்கிட்டு கத்தறான், தடுமாறி லேன்ல ஓடறான்.)"}
		3:
			if life:
				life.add_stress(4.0)
			line = {"en": "(The whistle splits the night. Lights in two houses, a man on a terrace shouting. He runs.)",
				"ta": "(விசில் இரவ கிழிக்குது. ரெண்டு வீட்டுல லைட், மாடியில ஒருத்தர் கத்தறாரு. அவன் ஓடிடறான்.)"}
		4:
			if life:
				life.add_stress(8.0)
			line = {"en": "(I turn and walk, fast, back to the lit road. He doesn't follow.)",
				"ta": "(திரும்பி, வேகமா, லைட் இருக்கற ரோட்டுக்கு நடக்கறேன். அவன் பின்னாடி வரல.)"}
	city.hud.warn("", 0.1)
	city.hud.say("Karthik", city._t(line), 5.0)
	city.fines.save()
	print("THREAT answered %d, wallet %d" % [pick, city.fines.sim.money])
	_open = {}


## The scooter, parked near a dark lane at night.
func _check_parked() -> void:
	var car = city.car
	if car == null or city.walker == null or not car.two_wheeler or not _night():
		_parked = {}
		return
	var near_spot := false
	for s in _spots_near(car.global_position):
		if (s as Vector3).distance_to(car.global_position) < 30.0:
			near_spot = true
	if not near_spot:
		_parked = {}
		return
	var now: float = city.fines.sim.day * 1440.0 + city.fines.sim.minute
	if _parked.is_empty():
		_parked = {"since": now, "done": false}
	if bool(_parked["done"]) or now - float(_parked["since"]) < 20.0:
		return
	_parked["done"] = true
	var sd: Dictionary = city.fines._save_data
	if Goods.has(sd, "disc_lock"):
		city.hud.warn(city._t({"en": "Scratches round the scooter's disc lock. Somebody tried.",
			"ta": "ஸ்கூட்டர் டிஸ்க் லாக் சுத்தி கீறல். யாரோ முயற்சி பண்ணியிருக்காங்க."}), 5.0)
		print("THREAT scooter: the lock held")
		return
	city.fines.sim.money = maxi(city.fines.sim.money - 300, 0)
	if city.life:
		city.life.add_stress(8.0)
	city.hud.warn(city._t({"en": "The scooter's seat box forced open. ₹300 of things gone.",
		"ta": "ஸ்கூட்டர் சீட் பாக்ஸ் உடைச்சு திறந்திருக்கு. ₹300 மதிப்புள்ள பொருள் போச்சு."}), 5.0)
	print("THREAT scooter: the seat box forced")
