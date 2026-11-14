extends Node
## Karthik taken to hospital (GAME_RULES.md §8): when he can't go on, the 108 comes for him.
##   why      hunger    no food in him for 45 game minutes on foot (life.gd energy at 0): he sways and goes down
##            crash     a serious crash (city_test.gd _on_impact: hard enough, more easily on two wheels)
##            beaten    (city_threats.gd, later: the other side's men) hurt past what he can walk off
##   the 108  he's down where it happened (on his back, the street swimming, his eyes half shut); the 108 ambulance
##            (tools/ambulance.py) comes up the road to him, its lights going, the siren; his eyes close.
##   where    the nearest of the two hospitals: Coimbatore Medical College Hospital (government) or Kongu
##            Multispeciality (private). He wakes inside, a day or more later (hunger one day; a crash or a beating
##            one to three by how bad), fed, his hurt seen to.
##   the bill government: what the ward needs bought outside (₹250 a day); private: ₹4,500 a day, a crash's scans
##            and dressings ₹3,000 more. Paid from the wallet; what isn't there is owed to the hospital
##            (money.gd: a bill, ten days to pay, its reminders), and Bala, the chain or the bank are the ways out.
## A message from the hospital's billing says it all (the game writes nothing on the screen). Not while the story
## is playing one of its own steps, nor indoors.
##   --hospitaltest=hunger|crash   (testing) on foot, at once; pictures to --shots=DIR (down, the 108, inside)

const Sim := preload("res://scripts/drive/sim.gd")
const AMB := "res://assets/vehicles/ambulance.glb"
const DRIVE := ["trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street"]
const HOSPITALS := [
	{"key": "hospital", "x": 236.3, "z": 2435.95, "door": [0.0, -17.8], "yaw": 3.1416, "room": "hospital_gov", "gov": true,
		"en": "Coimbatore Medical College Hospital", "ta": "கோயம்புத்தூர் அரசு மருத்துவக் கல்லூரி மருத்துவமனை"},
	{"key": "hospital_private", "x": 7882.6, "z": -2842.2, "door": [0.0, -18.2], "yaw": -1.5708, "room": "hospital_pvt", "gov": false,
		"en": "Kongu Multispeciality Hospital", "ta": "கொங்கு மல்டிஸ்பெஷாலிட்டி மருத்துவமனை"}]
const STARVE_MIN := 45.0               # game minutes at no food, on his feet, before he goes down
const GOV_PER_DAY := 250
const PVT_PER_DAY := 4500
const PVT_CRASH := 3000

var city
var busy := false
var _starving := 0.0
var _clock := -1.0
var _amb: Node3D
var _siren: AudioStreamPlayer3D
var _lamps: Array = []                 # [mesh, surface, material, blue?]
var _flash := 0.0
var _test := ""
var _shots := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hospitaltest="):
			_test = a.get_slice("=", 1)
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)


func _process(dt: float) -> void:
	if _amb and is_instance_valid(_amb):
		_flash += dt
		for l in _lamps:                                   # the bar's blue and red, by turns
			var on: bool = (fmod(_flash, 0.5) < 0.25) == bool(l[3])
			(l[2] as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.2
	if busy or city == null or city.life == null:
		return
	var life = city.life
	if _test != "" and city.walker == null and Time.get_ticks_msec() > 12000 and absf(city.car.speed) < 0.5 \
			and absf(city.car.linear_velocity.y) < 0.2 and city.car.global_position.y < 550.0:   # (set down on the street)
		city.toggle_on_foot()                              # (testing: out of the car first)
		return
	if _test != "" and city.walker != null and Time.get_ticks_msec() > 22000 and not has_meta("tested") \
			and (city.walker as CharacterBody3D).is_on_floor() and city.walker.global_position.is_finite():
		set_meta("tested", true)
		if _test == "hunger":
			life.energy = 0.0
		if "--hospitalbroke" in OS.get_cmdline_user_args() and city.fines:   # (testing: ₹200 to his name)
			city.fines.sim.money = 200
		for a in OS.get_cmdline_user_args():             # (testing: --hospitalat=x,z: he goes down there)
			if a.begins_with("--hospitalat="):
				var xz := a.get_slice("=", 1).split(",")
				var hy: float = city.streamer.height_at(float(xz[0]), float(xz[1]))
				city.walker.global_position = Vector3(float(xz[0]), (city.walker.global_position.y if is_nan(hy) else hy) + 0.5, float(xz[1]))
				await get_tree().create_timer(6.0).timeout
		admit(_test, 0.7)
		return
	if _test != "" and has_meta("tested") and not has_meta("left") and city.indoors and Time.get_ticks_msec() > get_meta("woke", 1e12) + 4000:
		set_meta("left", true)                             # (testing: out of the hospital's door, and a picture outside)
		city.doors.leave(city.walker)
		print("HOSPITAL test: out at %s" % city.walker.global_position)
		await get_tree().create_timer(6.0).timeout
		print("HOSPITAL test: 6 s later at %s, on the floor %s" % [city.walker.global_position, (city.walker as CharacterBody3D).is_on_floor()])
		await _shot("outside")
	var now: float = life._clock_now()
	var mins := clampf(now - _clock, 0.0, 60.0) if _clock >= 0.0 else 0.0
	_clock = now
	if city.story == null:
		mins = dt * Sim.MINUTES_PER_SECOND
	if life.energy <= 0.0 and city.walker != null and not city.indoors and not life.busy and not life._story_busy():
		_starving += mins
		if _starving >= STARVE_MIN:
			admit("hunger")
	else:
		_starving = 0.0


## A crash: hard enough (severity), more easily on two wheels, and he's in hospital.
func crash(severity: float, two_wheeler: bool) -> void:
	if busy or city.life == null or city.life._story_busy():
		return
	if severity >= (0.45 if two_wheeler else 0.75) or city.life.hurt >= 85.0:
		admit("crash", severity)


## He's taken in: why ("hunger", "crash", "beaten") and how bad (0..1).
func admit(why: String, how_bad := 0.5) -> void:
	if busy or (city.walker and not city.walker.global_position.is_finite()):
		return
	busy = true
	var life = city.life
	life.busy = true
	var w: Node3D = city.walker
	var at: Vector3 = w.global_position if w else city.car.global_position
	print("HOSPITAL %s (%.2f) at %.0f,%.0f" % [why, how_bad, at.x, at.z])
	if w:
		w.set_physics_process(false)
		if w.get("anim"):
			w.anim.play("Idle", 0.3)
		await _go_down(w)
	var called := 0.0
	if city.get("citizens"):                             # (the people near come round; one calls the 108,
		called = 10.0 if city.citizens.gather(at) > 0 else 0.0   #  which takes a while to come)
	var lids := create_tween()                           # the street swimming, his eyes half shut
	lids.tween_property(life.body, "lids_hold", 0.55, 1.5)
	await get_tree().create_timer(1.5).timeout
	var prev := get_viewport().get_camera_3d()
	var path := _path_to(at)
	var stop: Vector3 = path[path.size() - 1]
	var to_road := Vector3(stop.x - at.x, 0.0, stop.z - at.z)
	to_road = to_road.normalized() if to_road.length() > 0.1 else Vector3.FORWARD
	var side := to_road.cross(Vector3.UP)
	var low := Camera3D.new()
	low.fov = 55.0
	if prev:                                               # (the city's own sky, light and exposure)
		low.environment = prev.environment
		low.attributes = prev.attributes
		low.far = prev.far
		low.cull_mask = prev.cull_mask
	add_child(low)
	low.global_position = at + to_road * 4.5 + side * 2.0 + Vector3(0, 2.6, 0)   # him there on the ground a moment
	low.look_at(at + Vector3(0, 0.2, 0))                                           # (from the road: the kerb side is
																				   #  walls and parked cars),
	low.make_current()
	await get_tree().create_timer(2.0).timeout
	var waited := 0.0                                    # (until the first who came running is by him, or 20 s)
	while called > 0.0 and waited < 20.0 and not city.citizens.gathered():
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if called > 0.0:
		await get_tree().create_timer(3.0).timeout
	if _test != "" and city.get("citizens"):
		for c in city.citizens.people:
			if c.get("gather_t", 0.0) > 0.0 and c["node"] != null:
				print("HOSPITAL gathered %s at %.1f m, path %d/%d, clip %s" % [c["d"]["id"], (c["node"] as Node3D).global_position.distance_to(at),
					c["pi"], c["path"].size(), (c["anim"] as AnimationPlayer).current_animation])
	await _shot("down")
	low.global_position = at - to_road * 0.5 + Vector3(0, 0.4, 0)              # then as he sees it: from the ground,
	low.look_at(path[0] + Vector3(0, 1.0, 0))                                      #  the 108 coming
	await _the_108(at, low, path)
	await _shot("ambulance")
	await life.body.eyes(true, 1.4)
	if prev and is_instance_valid(prev):
		prev.make_current()
	low.queue_free()
	if _siren:
		var tw := create_tween()
		tw.tween_property(_siren, "volume_db", -40.0, 1.2)
		await tw.finished
	if _amb and is_instance_valid(_amb):
		_amb.queue_free()
	_amb = null
	_lamps.clear()
	# the nearest hospital; he's inside, on his feet, the days gone by
	var h: Dictionary = _nearest(at)
	if city.walker == null:
		city.toggle_on_foot()
	w = city.walker
	if w.get("model"):
		w.model.rotation = Vector3.ZERO
		w.model.position = Vector3.ZERO
	var c := cos(float(h["yaw"]))
	var sn := sin(float(h["yaw"]))
	var bx: float = h["door"][0]
	var gz: float = -float(h["door"][1])
	var dp := Vector3(float(h["x"]) + bx * c + gz * sn, 0.0, float(h["z"]) - bx * sn + gz * c)
	dp.y = city.streamer.height_at(dp.x, dp.z) if city.streamer else at.y
	if is_nan(dp.y):                                   # (that part of the city not loaded: the room needs no ground)
		dp.y = at.y
	w.global_position = dp + Vector3(sn, 0.5, c) * 2.0
	city.doors.enter({"pos": dp, "out": Vector3(sn, 0, c), "room": h["room"], "key": h["key"]}, w)
	w.set_physics_process(false)
	var days := 1 if why == "hunger" else clampi(1 + roundi(how_bad * 2.0), 1, 3)
	await life._run_clock(days * 24.0 * 60.0 - 6.0 * 60.0, 3.0)        # (he's brought in in the evening, say: he
	life.energy = 70.0                                                  #  wakes in the morning, a day or more on)
	life.tiredness = 10.0
	life.hurt = minf(life.hurt, 15.0 if why != "hunger" else life.hurt)
	life.add_stress(8.0 + 4.0 * days)
	await life.body.eyes(false, 1.8)
	w.set_physics_process(true)
	(w as CharacterBody3D).velocity = Vector3.ZERO
	await _shot("inside")
	set_meta("woke", Time.get_ticks_msec())
	var gy: float = city.streamer.height_at(dp.x, dp.z) if city.streamer else NAN   # (the street there loaded by now:
	if not is_nan(gy) and not city.doors.inside.is_empty():                          #  out of the door onto it)
		city.doors.inside["pos"].y = gy
	_park_at(dp, Vector3(sn, 0, c), gy)
	_bill(h, why, days)
	life.save()
	life.busy = false
	busy = false
	_starving = 0.0


## Down where he stands: a sway, and over onto his back.
func _go_down(w: Node3D) -> void:
	var m: Node3D = w.get("model")
	if m == null:
		return
	var tw := create_tween()
	tw.tween_property(m, "rotation:z", 0.12, 0.5)
	tw.tween_property(m, "rotation:z", -0.08, 0.4)
	tw.set_parallel(true)
	tw.tween_property(m, "rotation:x", -PI / 2.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD).set_delay(0.9)
	await tw.finished
	var space := (w as Node3D).get_world_3d().direct_space_state   # (on the ground itself: what's under him, a ray)
	var q := PhysicsRayQueryParameters3D.create(w.global_position + Vector3.UP * 1.0, w.global_position + Vector3.DOWN * 3.0)
	q.exclude = [(w as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		m.global_position.y = float(hit["position"].y) + 0.14


## The 108 up the road to him: along the nearest street, 50 m back, its lights going, the siren; it stops beside him.
func _the_108(at: Vector3, eye: Camera3D = null, path: Array = []) -> void:
	if not ResourceLoader.exists(AMB):
		return
	_amb = (load(AMB) as PackedScene).instantiate() as Node3D
	add_child(_amb)
	for mi in _amb.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for i in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(i)
			if mat and (mat.resource_name.begins_with("Light blue") or mat.resource_name.begins_with("Light red")):
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				m3.set_surface_override_material(i, dup)
				_lamps.append([m3, i, dup, mat.resource_name.begins_with("Light blue")])
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = _siren_sound()
	_siren.unit_size = 18.0
	_siren.volume_db = 2.0
	_amb.add_child(_siren)
	_siren.play()
	if path.is_empty():
		path = _path_to(at)
	var total := 0.0
	for i in path.size() - 1:
		total += (path[i] as Vector3).distance_to(path[i + 1])
	var speed := 11.0
	var t := 0.0
	var dur := maxf(total / speed, 0.5)
	while t < dur:                                     # along the street at about 40 km/h, slowing to stop
		var dt := get_process_delta_time()
		t += dt
		var s := ease(clampf(t / dur, 0.0, 1.0), 0.6) * total
		var p: Vector3 = path[0]
		var d: Vector3 = (path[1] - path[0]) if path.size() > 1 else Vector3.FORWARD
		var acc := 0.0
		for i in path.size() - 1:
			var seg: float = (path[i] as Vector3).distance_to(path[i + 1])
			if acc + seg >= s or i == path.size() - 2:
				var k := clampf((s - acc) / maxf(seg, 0.01), 0.0, 1.0)
				p = (path[i] as Vector3).lerp(path[i + 1], k)
				d = path[i + 1] - path[i]
				break
			acc += seg
		var gy: float = city.streamer.height_at(p.x, p.z) if city.streamer else p.y
		_amb.global_position = Vector3(p.x, p.y if is_nan(gy) else gy, p.z)
		_amb.rotation.y = atan2(d.x, d.z)
		if eye:
			eye.look_at(_amb.global_position + Vector3(0, 1.2, 0))
		await get_tree().process_frame
	if eye:
		eye.look_at(_amb.global_position + Vector3(0, 1.2, 0))
	await get_tree().create_timer(1.6).timeout


## His car (or scooter) waiting outside the hospital: Amma had someone bring it round (left where he went down, two
## kilometres off, the street there unloads under it and it falls through the world).
func _park_at(door: Vector3, out: Vector3, gy: float) -> void:
	var car = city.car
	if car == null:
		return
	var side := out.cross(Vector3.UP).normalized()
	var p := door + out * 9.0 + side * 5.0
	var y: float = city.streamer.height_at(p.x, p.z) if city.streamer else NAN
	if is_nan(y):
		y = gy if not is_nan(gy) else door.y
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = Transform3D(Basis.looking_at(-side, Vector3.UP), Vector3(p.x, y + 0.6, p.z))
	print("HOSPITAL the car waiting outside at %.0f,%.0f" % [p.x, p.z])


## The street nearest him, as points from 50 m back up it to beside him (or straight in, with no street near).
func _path_to(at: Vector3) -> Array:
	var best := INF
	var road: PackedFloat32Array
	var bi := -1
	if city.streamer:
		for k in city.streamer.loaded:
			var node: Node3D = city.streamer.loaded[k]
			if node == null or not is_instance_valid(node):
				continue
			for r in node.get_meta("roads", []):
				if not r["c"] in DRIVE or r.get("fly", false):
					continue
				var p: PackedFloat32Array = r["p"]
				for i in p.size() / 3:
					var dd := Vector2(p[i * 3] - at.x, p[i * 3 + 2] - at.z).length_squared()
					if dd < best:
						best = dd
						road = p
						bi = i
	if bi < 0 or best > 60.0 * 60.0:
		var back := at + Vector3(40.0, 0.0, 0.0)
		return [back, at + Vector3(3.0, 0.0, 0.0)]
	var n := road.size() / 3
	var pts: Array = [Vector3(road[bi * 3], road[bi * 3 + 1], road[bi * 3 + 2])]
	var step := -1 if bi > 0 else 1                    # (back along the street, whichever way it goes on)
	var i := bi
	var got := 0.0
	while got < 50.0:
		i += step
		if i < 0 or i >= n:
			break
		var q := Vector3(road[i * 3], road[i * 3 + 1], road[i * 3 + 2])
		got += q.distance_to(pts[0])
		pts.push_front(q)
	if pts.size() < 2:
		pts.push_front(pts[0] + (pts[0] - at).normalized() * 40.0)
	var short := 6.0                                    # (it pulls up six metres short of him, not on him)
	while pts.size() > 2 and short > 0.0:
		var a: Vector3 = pts[pts.size() - 2]
		var b: Vector3 = pts[pts.size() - 1]
		var seg := a.distance_to(b)
		if seg > short:
			pts[pts.size() - 1] = b + (a - b).normalized() * short
			short = 0.0
		else:
			pts.pop_back()
			short -= seg
	return pts


func _nearest(at: Vector3) -> Dictionary:
	var best: Dictionary = HOSPITALS[0]
	var bd := INF
	for h in HOSPITALS:
		var d := Vector2(float(h["x"]) - at.x, float(h["z"]) - at.z).length()
		if d < bd:
			bd = d
			best = h
	return best


## What it cost: from the wallet what's there, the rest owed to the hospital (money.gd: ten days), a message.
func _bill(h: Dictionary, why: String, days: int) -> void:
	var gov: bool = h["gov"]
	var total := (GOV_PER_DAY if gov else PVT_PER_DAY) * days + (PVT_CRASH if (not gov and why != "hunger") else 0)
	var sim = city.fines.sim if city.fines else null
	var have: int = sim.money if sim else 0
	var paid := mini(have, total)
	if sim:
		sim.money -= paid
	var owe := total - paid
	var name := {"en": str(h["en"]), "ta": str(h["ta"])}
	var what: String = {"hunger": "admitted collapsed from hunger: drip, food, observation",
		"crash": "admitted after a road accident: X-ray, dressings, observation",
		"beaten": "admitted with injuries from an assault: dressings, observation"}.get(why, "admitted")
	var en := "%s. %d day%s, %s. Bill ₹%s: paid ₹%s." % [what.capitalize().left(1) + what.substr(1), days, "" if days == 1 else "s",
		"ward" if gov else "room", _r(total), _r(paid)]
	if owe > 0:
		en += " Balance ₹%s due in 10 days at the billing counter." % _r(owe)
	var ta := "%d நாள் சிகிச்சை. கட்டணம் ₹%s, செலுத்தியது ₹%s." % [days, _r(total), _r(paid)]
	if owe > 0:
		ta += " மீதி ₹%s, 10 நாட்களுக்குள் செலுத்தவும்." % _r(owe)
	if city.phone:
		city.phone.message(name, {"en": en, "ta": ta})
	if owe > 0 and city.money:
		city.money.add_bill({"id": "hospital_%d" % Time.get_ticks_msec(), "kind": "other", "amount": owe, "in_days": 10,
			"label": {"en": "the hospital bill (%s)" % h["en"], "ta": "மருத்துவமனை கட்டணம்"}})
	print("HOSPITAL %s: %d day(s) at %s, ₹%d, paid ₹%d, owed ₹%d" % [why, days, h["en"], total, paid, owe])


static func _r(v: int) -> String:
	var s := str(v)
	if s.length() <= 3:
		return s
	var head := s.left(s.length() - 3)
	var out := s.right(3)
	while head.length() > 2:                           # (Indian grouping: 1,23,456)
		out = head.right(2) + "," + out
		head = head.left(head.length() - 2)
	return head + "," + out


## The siren: Tamil Nadu's 108, a rising and falling wail, two seconds a cycle, looping.
static func _siren_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 700.0 + 550.0 * (0.5 - 0.5 * cos(t * PI))          # 700 → 1250 → 700 Hz in the two seconds
		ph += TAU * f / rate
		var s := sin(ph) * 0.6 + sin(ph * 2.0) * 0.15
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _shot(tag: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/hospital_%s_%s.jpg" % [_shots, _test, tag], 0.85)
