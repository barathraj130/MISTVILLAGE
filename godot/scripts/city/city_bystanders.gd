extends Node
## The people standing about the streets (city_streamer.gd's street life: MultiMesh instances, tagged "people")
## and a vehicle coming at them. Nothing here is gory: no one is hurt beyond a fall.
##   in its way, with time to move  they jump clear (a quick sideways hop away from your line) and shout at you.
##                                  A person notices a vehicle coming 0.7–1.7 s before it reaches them (each their
##                                  own: some are on their phones), takes half a second to react, then moves at
##                                  about 3 m/s; if that isn't time enough to get out of its width:
##   knocked down                   they fall away from the hit, lie a few seconds, get up slowly.
##                                  You feel the bump. A crowd's voice. You pay for the hospital on the spot (what
##                                  the wallet holds of it), a rash-driving e-challan follows, and on bail the
##                                  inspector's suspicion rises a good deal.
##   a crawl (under ~11 km/h)       they just step aside
## Each person is the same instance in every MultiMesh of its cell (near, far, the shadow), moved together.

const Fines := preload("res://scripts/city/fines.gd")
const HOSPITAL := 3000                        # paid there and then, to the person (as it is settled on the street)
const REACH := 40.0
const BODY := 0.3                             # a person's radius (m)

var city
var _scan_t := 0.0
var _near: Array = []                         # [{"mms": [MultiMeshInstance3D], "i": int, "xf": Transform3D}]
var _moving: Array = []                       # people mid-hop or mid-fall: {"mms", "i", "from", "to", "t", "dur", "then"}
var _busy := {}                               # "id:i" → true while moving or down
var _said := 0.0
var _doomed := {}                             # "id:i" → true: noticed too late, the hit is coming


func _physics_process(delta: float) -> void:
	_animate(delta)
	if city == null or city.car == null or not city.driving or city.streamer == null:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_scan()
	_said = maxf(0.0, _said - delta)
	var car = city.car
	var v: Vector3 = car.linear_velocity
	v.y = 0.0
	var spd := v.length()
	if spd < 1.0:
		return
	var dir := v / spd
	var cp: Vector3 = car.global_position
	var half: float = _half_width(car)
	for p in _near:
		var key := _key(p)
		if _busy.has(key):
			continue
		var xf: Transform3D = p["xf"]
		var rel := xf.origin - cp
		if absf(rel.y) > 2.5:
			continue
		rel.y = 0.0
		var along := rel.dot(dir)
		var side := rel - dir * along
		var lat := side.length()
		var front: float = _half_length(car)
		if along < -front or along > front + spd * 1.3 + 2.0 or lat > half + BODY + 0.5:
			continue
		var away := side.normalized() if lat > 0.05 else Vector3(dir.z, 0, -dir.x)
		var t_hit := (along - front) / spd
		var need := half + BODY + 0.5 - lat                       # (out of its width, and a little more)
		if spd < 3.0:
			if along - front < 2.5:
				_hop(p, away * need, 0.8)
			continue
		if _doomed.has(key):
			if along - front < BODY and lat < half + BODY:
				_doomed.erase(key)
				_knocked(p, dir, away, spd)
			continue
		var notice := 0.7 + 1.0 * _attention(p)
		if t_hit > notice:
			continue
		if lat > half + BODY:                                     # (it'll pass close by: a startled step back)
			_hop(p, away * 0.6, 0.35)
			_shout(false, spd)
		elif t_hit > 0.5 + need / 3.2:
			_hop(p, away * need, need / 3.2)
			_shout(false, spd)
		else:
			_doomed[key] = true


## How quick this person is to look up (0..1, always the same for the same person).
func _attention(p: Dictionary) -> float:
	var o: Vector3 = (p["xf"] as Transform3D).origin
	return fposmod(sin(o.x * 12.9898 + o.z * 78.233) * 43758.5453, 1.0)


func _half_width(car) -> float:
	var sp: Dictionary = car.SPECS.get(car.vehicle, {})
	return float(sp.get("w", 1.8)) * 0.5 if not car.two_wheeler else 0.45


func _half_length(car) -> float:
	var sp: Dictionary = car.SPECS.get(car.vehicle, {})
	return float(sp.get("len", 4.2)) * 0.5


func _key(p: Dictionary) -> String:
	return "%d:%d" % [(p["mms"][0] as Object).get_instance_id(), p["i"]]


## The people within reach, from the loaded tiles near the car.
func _scan(reach := REACH) -> void:
	_near.clear()
	var cp: Vector3 = city.car.global_position
	for k in city.streamer.loaded:
		var tile := city.streamer.loaded[k] as Node3D
		if tile == null or not is_instance_valid(tile):
			continue
		var groups := {}
		for c in tile.get_children():
			if c is MultiMeshInstance3D and c.has_meta("people") and (c as MultiMeshInstance3D).multimesh:
				var g: String = c.get_meta("people")
				if not groups.has(g):
					groups[g] = []
				groups[g].append(c)
		for g in groups:
			var first := groups[g][0] as MultiMeshInstance3D
			var mm := first.multimesh
			var aabb := first.global_transform * mm.get_aabb()
			if aabb.grow(reach).has_point(cp) == false:
				continue
			for i in mm.instance_count:
				var xf := first.global_transform * mm.get_instance_transform(i)
				if xf.origin.distance_to(cp) < reach:
					_near.append({"mms": groups[g], "i": i, "xf": xf})


func _set_xf(p: Dictionary, xf: Transform3D) -> void:
	var done := {}
	for m in p["mms"]:
		var mi := m as MultiMeshInstance3D
		if not is_instance_valid(mi) or done.has(mi.multimesh):
			continue
		done[mi.multimesh] = true                           # (the far mesh and its shadow share one)
		mi.multimesh.set_instance_transform(p["i"], mi.global_transform.affine_inverse() * xf)
	p["xf"] = xf


## A quick sideways jump, facing the vehicle.
func _hop(p: Dictionary, by: Vector3, dur: float) -> void:
	var from: Transform3D = p["xf"]
	var to := Transform3D(from.basis, from.origin + by)
	_busy[_key(p)] = true
	_moving.append({"p": p, "from": from, "to": to, "t": 0.0, "dur": dur, "arc": 0.25, "then": []})


## Struck: a little throw along the hit, a fall onto the side away from it, a few seconds down, up again slowly.
func _knocked(p: Dictionary, dir: Vector3, away: Vector3, spd: float) -> void:
	var from: Transform3D = p["xf"]
	var throw := dir * clampf(spd * 0.25, 1.0, 4.0) + away * 0.8
	var axis := dir.cross(Vector3.UP).normalized() if (dir + away * 0.3).length() > 0.01 else Vector3.RIGHT
	var down_basis := Basis(axis, -deg_to_rad(82.0)) * from.basis
	var down := Transform3D(down_basis, from.origin + throw + Vector3.UP * 0.12)
	var up := Transform3D(from.basis, from.origin + throw)
	_busy[_key(p)] = true
	_moving.append({"p": p, "from": from, "to": down, "t": 0.0, "dur": 0.55, "arc": 0.35,
		"then": [{"wait": 4.0}, {"to": up, "dur": 1.6}]})
	var car = city.car
	car.jolt = maxf(car.jolt, 40.0)
	car._crash = maxf(car._crash, 0.35)
	car.linear_velocity -= dir * minf(spd, 70.0 * spd / (car.mass + 70.0))   # (a person's weight against the car's)
	_shout(true, spd)
	_consequences(spd)


func _animate(delta: float) -> void:
	for m in _moving.duplicate():
		var p: Dictionary = m["p"]
		if not is_instance_valid(p["mms"][0]):
			_moving.erase(m)
			continue
		if m.has("wait"):
			m["wait"] = float(m["wait"]) - delta
			if float(m["wait"]) <= 0.0:
				_next(m)
			continue
		m["t"] = float(m["t"]) + delta
		var f := clampf(float(m["t"]) / float(m["dur"]), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - f, 3.0)
		var a: Transform3D = m["from"]
		var b: Transform3D = m["to"]
		var xf := a.interpolate_with(b, e)
		xf.origin.y += sin(f * PI) * float(m["arc"])
		_set_xf(p, xf)
		if f >= 1.0:
			_next(m)


func _next(m: Dictionary) -> void:
	var then: Array = m["then"]
	if then.is_empty():
		_moving.erase(m)
		_busy.erase(_key(m["p"]))
		return
	var step: Dictionary = then.pop_front()
	if step.has("wait"):
		m["wait"] = step["wait"]
		return
	m.erase("wait")
	m["from"] = m["p"]["xf"]
	m["to"] = step["to"]
	m["dur"] = step["dur"]
	m["arc"] = 0.0
	m["t"] = 0.0


func _shout(hit: bool, spd: float) -> void:
	if _said > 0.0 or city.hud == null:
		return
	_said = 3.0
	var lines: Array
	if hit:
		lines = [["Stop! Stop the vehicle! You hit him!", "நிறுத்து! வண்டியை நிறுத்து! அவரை இடிச்சிட்டீங்க!"],
			["Aiyyo! Someone help him up!", "ஐயோ! யாராவது அவரைத் தூக்குங்க!"]]
	elif spd > 8.0:
		lines = [["Aiyyo! Are you blind? Slow down!", "ஐயோ! கண்ணு தெரியலையா? மெதுவா போ!"],
			["Mad fellow! There are people here!", "பைத்தியக்காரா! இங்க ஆளுங்க இருக்காங்க!"]]
	else:
		lines = [["Careful, saar.", "பார்த்து, சார்."], ["Can't you use the horn?", "ஹாரன் அடிக்க மாட்டீங்களா?"]]
	var l: Array = lines[randi() % lines.size()]
	city.hud.say(city._t({"en": "On the street" if not hit else "The crowd", "ta": "தெருவில்" if not hit else "கூட்டம்"}),
		city._t({"en": l[0], "ta": l[1]}), 4.0)


func _consequences(spd: float) -> void:
	print("BYSTANDER knocked down at %.0f km/h" % (spd * 3.6))
	if city.fines == null:
		return
	var paid: int = city.fines.pay(HOSPITAL)
	city.fines.challan("Rash driving (pedestrian)", Fines.RASH)
	if city.phone:
		city.phone.message({"en": "Coimbatore City Police", "ta": "கோவை மாநகர காவல்"},
			{"en": "E-challan %s: rash driving, a pedestrian knocked down, %s. Paid %s on the spot for the hospital." % [Fines.rupees(Fines.RASH), city._now12(), Fines.rupees(paid)],
			"ta": "இ-சலான் %s: அலட்சியமாக ஓட்டி ஒருவரை இடித்தது, %s. மருத்துவமனைக்கு அந்த இடத்திலேயே %s கொடுத்தீர்கள்." % [Fines.rupees(Fines.RASH), city._now12(), Fines.rupees(paid)]})
	if city.bail and city.bail.active:
		city.bail.suspicion = clampf(city.bail.suspicion + 10.0, 0.0, 100.0)
