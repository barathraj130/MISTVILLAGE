extends Node
## The night of Day 18 (docs/OPEN_WORLD_PLAN_2026-11-14.md: hiding until court): out of the godown with the ledger,
## he can't go home (they're watching the street); he lies low in the fields at Pudhur Vayal while Suresh's men search
## with torches, till the light comes. Played, not read: no meters; the torches, their voices, his heartbeat (body.gd).
##   the men      four, walking the fields (a point within 35 m of where he went to ground, a pause, a look about),
##                a torch each (a SpotLight3D in the hand); a glimpse sends one to where he saw him
##   being seen   a man sees him within 14 m in a 100° view if nothing's between (a ray: the sacks, a wall, a bund);
##                crouched (Z) only 7; in his torch's beam 18. Held in view 1.2 s: they have him
##   caught       they rough him up (life.gd hurt), and if he still has the ledger they take it; finished(true)
##   dawn         about 100 real seconds; the clock runs from where it is to 05:30; finished(false)
##   --hidetest   testing: he lies low where he is (crouched, still); the men's searching printed
signal finished(caught: bool)

const Crowd := preload("res://scripts/city/crowd.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const LENGTH := 100.0                # real seconds of the night
const SEE := 14.0
const SEE_LOW := 7.0
const SEE_TORCH := 18.0
const HOLD := 1.2                    # seconds held in view before they have him

var city
var story
var men: Array = []                  # {node, ap, torch, goal, wait, seen}
var centre := Vector3.ZERO
var _t := 0.0
var _clock0 := 0.0
var _done := false
var _rng := RandomNumberGenerator.new()
var _test := false
var _shout := 0.0


func start(spec: Dictionary, at: Vector3) -> void:
	_rng.seed = 1819
	_test = "--hidetest" in OS.get_cmdline_user_args()
	centre = _ground(at + Vector3(float(spec.get("off", [18.0, 0.0])[0]), 0.0, float(spec.get("off", [18.0, 0.0])[1])))
	if city.indoors and story and story.room:
		story._unload_room()
	if city.walker == null:                             # (still in the car: out, there; the fields' tiles in first)
		city.car.linear_velocity = Vector3.ZERO
		city.car.global_position = centre + Vector3(0, 2.0, -8.0)
		city.streamer.target = city.car
		await get_tree().create_timer(4.0).timeout
		centre = _ground(centre)
		city.car.global_position = centre + Vector3(0, 0.8, -8.0)
		await get_tree().create_timer(1.0).timeout
		city.toggle_on_foot()
	var w = city.walker
	if w:
		w.set_physics_process(true)
		w.spawn_at(centre + Vector3.UP * 0.4, centre + Vector3(0, 0, 10))
		w.activate()
		if _test:
			w.set_crouch(true)
	if story and story.fines:
		_clock0 = float(story.fines.sim.minute)
		if _clock0 < 21.0 * 60.0 and _clock0 > 6.0 * 60.0:
			_clock0 = 22.0 * 60.0 + 40.0
			story.fines.sim.minute = _clock0
	for i in int(spec.get("men", 4)):
		var p := (load(Crowd.CROWD % ["m2", "m4", "m5", "m6"][i % 4]) as PackedScene).instantiate() as Node3D
		add_child(p)
		var a := _rng.randf() * TAU
		p.global_position = _ground(centre + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(25.0, 35.0))
		if story and story.has_method("_tint"):
			story._tint(p, "top", Color(0.12, 0.12, 0.13))
		CrowdClips.add(p, "m")
		var ap := p.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var torch := SpotLight3D.new()                   # the torch, held out ahead of him
		torch.spot_range = SEE_TORCH + 4.0
		torch.spot_angle = 18.0
		torch.light_energy = 6.0
		torch.light_color = Color(1.0, 0.92, 0.75)
		torch.shadow_enabled = true
		p.add_child(torch)
		torch.position = Vector3(-0.25, 1.25, 0.35)
		torch.rotation = Vector3(-0.25, PI, 0.0)         # (a SpotLight shines down its -Z; the man faces +Z)
		men.append({"node": p, "ap": ap, "torch": torch, "goal": p.global_position, "wait": 0.0, "seen": 0.0})
	if city.hud:
		city.hud.warn("Z: low · keep out of their torches till it's light", 6.0)
	print("HIDE at %s: %d men searching" % [str(centre.round()), men.size()])


func _ground(p: Vector3) -> Vector3:
	var g: float = city.streamer.height_at(p.x, p.z) if city and city.streamer else NAN
	return Vector3(p.x, g if not is_nan(g) else p.y, p.z)


func _process(dt: float) -> void:
	if _done or city == null or city.walker == null:
		return
	var w = city.walker
	_t += dt
	if story and story.fines:                           # the night going: to half past five as the time runs out
		var end := 5.5 * 60.0 + (24.0 * 60.0 if _clock0 > 12.0 * 60.0 else 0.0)
		var m := lerpf(_clock0, end, clampf(_t / LENGTH, 0.0, 1.0))
		_to_clock(m)
	for m in men:
		_search(m, w, dt)
	_shout = maxf(_shout - dt, 0.0)
	if _t >= LENGTH:
		_end(false)


## The night's clock: m counted on from the evening (past 1440: the next day; the day turns once, at midnight).
var _turned := false


func _to_clock(m: float) -> void:
	if m >= 24.0 * 60.0 and not _turned:
		_turned = true
		story.fines.sim.day += 1
	story.fines.sim.minute = fmod(m, 24.0 * 60.0)


func _search(m: Dictionary, w: Node3D, dt: float) -> void:
	var n: Node3D = m["node"]
	var to: Vector3 = w.global_position - n.global_position
	to.y = 0.0
	var d := to.length()
	var seen := _sees(n, w, d, to)
	m["seen"] = (float(m["seen"]) + dt) if seen else maxf(float(m["seen"]) - dt * 0.5, 0.0)
	if seen and float(m["seen"]) > 0.25:                # a glimpse: he goes to look
		m["goal"] = w.global_position
		m["wait"] = 0.0
		if _shout <= 0.0 and city.hud:
			_shout = 4.0
			city.hud.say("", "(Dei! Anga yaaru?)" if story == null or story.lang == "en" else "(டேய்! அங்க யாரு?)", 2.0)
	if float(m["seen"]) >= HOLD:
		print("HIDE seen by a man %.0f m off" % d)
		_end(true)
		return
	var go: Vector3 = m["goal"] - n.global_position
	go.y = 0.0
	if float(m["wait"]) > 0.0:
		m["wait"] = float(m["wait"]) - dt
		_play(m, "crowd/StandWait")
		n.rotation.y += sin(_t * 0.7 + n.get_instance_id() % 7) * dt * 0.8   # (sweeping the torch about)
		if float(m["wait"]) <= 0.0:
			var a := _rng.randf() * TAU
			m["goal"] = _ground(centre + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(4.0, 35.0))
	elif go.length() < 1.0:
		m["wait"] = _rng.randf_range(2.0, 4.5)
	else:
		var dir := go.normalized()
		n.global_position = _ground(n.global_position + dir * 1.3 * dt)
		n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * 5.0))
		_play(m, "Walk")


## Does he see him: near enough (low, less; in the beam, more), in front, nothing solid between.
func _sees(n: Node3D, w: Node3D, d: float, to: Vector3) -> bool:
	var fwd: Vector3 = n.global_basis.z
	var dir := to / maxf(d, 0.01)
	var low: bool = w.get("gait") != null and w.gait.crouched
	var reach := SEE_LOW if low else SEE
	if fwd.dot(dir) > cos(deg_to_rad(9.0)):            # (in the torch's beam)
		reach = SEE_TORCH * (0.7 if low else 1.0)
	if d > reach or fwd.dot(dir) < cos(deg_to_rad(50.0)):
		return false
	var eye := n.global_position + Vector3.UP * 1.6
	var him: Vector3 = w.global_position + Vector3.UP * (0.6 if low else 1.2)
	var q := PhysicsRayQueryParameters3D.create(eye, him)
	q.exclude = [(w as CollisionObject3D).get_rid()]
	return n.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _play(m: Dictionary, clip: String) -> void:
	var ap: AnimationPlayer = m["ap"]
	if not ap.has_animation(clip):
		clip = "Idle"
	if ap.current_animation != clip:
		ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		ap.play(clip, 0.3)


func _end(caught: bool) -> void:
	_done = true
	if caught:
		if story and story.fines:                       # (left in the paddy till they've gone: it's light when he's up)
			_to_clock(5.5 * 60.0 + (24.0 * 60.0 if _clock0 > 12.0 * 60.0 else 0.0))
		if city.life:
			city.life.add_hurt(25.0)
		if city.walker:
			city.walker.knock(Vector3(1, 0, 0) * 3.0, true)
	print("HIDE over at %s: %s" % [story._clock12() if story and story.has_method("_clock12") else "?", "they found him" if caught else "it's light; they've gone"])
	for m in men:
		(m["node"] as Node3D).queue_free()
	men.clear()
	finished.emit(caught)
