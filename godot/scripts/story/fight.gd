extends Node
## The fight in the godown (Day 18; docs/OPEN_WORLD_PLAN_2026-11-14.md: the ten men at the end, the user's choice):
## Suresh's men come in by waves (the room's Mark_gang_0..9: the shutter and the back door), and Karthik gets out with
## the ledger or doesn't. Played, not read: no bars; his hurt shows on him (body.gd), theirs in how they move.
##   the men      crowd men in dark shirts (crowd.gd); they close in, circle him, and come at
##                him, one at a time, with a haymaker you can see coming (crowd_clips.py Haymaker: 0.7 s of wind-up); three punches
##                put one down (he goes over and stays down)
##   Karthik      F or the left mouse: a straight right at the nearest one in front of him (crowd/Punch); the right
##                mouse held: a block (crowd/Block, most of a blow taken on the arms); Space: a quick step back out of
##                a swing (crowd/Dodge); WASD as ever
##   his hurt     life.gd's: a blow 12 (3 blocked), and it knocks him (player.gd knock: a stumble, or down); near the
##                end (90) he goes down for good: they take the ledger
##   waves        3, then 3, then 4 (the next comes in as the last of one is down to one man)
## finished(won) when it's over. Never a game over: losing costs the ledger, the story goes on with what's left.
##   --fighttest  testing: the men come at a test Karthik who punches the nearest every second and blocks the rest
signal finished(won: bool)

const Crowd := preload("res://scripts/city/crowd.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const MEN := ["m1", "m2", "m3", "m4", "m5", "m6"]
const HIT := 7.0
const HIT_BLOCKED := 1.0
const DOWN_AT := 90.0

var city
var story
var room: Node3D
var waves: Array = [3, 3, 4]
var men: Array = []                   # {node, ap, hp, state, t, cool, down, look}
var _wave := 0
var _spawned := 0
var _attackers := 0
var _busy := 0.0                      # his own move, still playing (s)
var _blocking := false
var _dodge := 0.0                     # out of reach while > 0
var _keys := {}
var _done := false
var _rng := RandomNumberGenerator.new()
var _test := false
var _test_t := 0.0
var _said := false


func start(spec: Dictionary) -> void:
	_rng.seed = 1818
	waves = spec.get("waves", waves)
	_test = "--fighttest" in OS.get_cmdline_user_args()
	if room == null:                                    # (no godown to fight in: nothing to fight; on, as won)
		push_warning("fight: no room")
		finished.emit.call_deferred(true)
		return
	var w = city.walker
	if w:
		CrowdClips.add(w.model, "m")
	_next_wave()
	if city.hud and not _said:
		_said = true
		city.hud.warn("F: hit · right mouse: block · Space: step back", 6.0)


func _next_wave() -> void:
	if _wave >= waves.size():
		return
	var n: int = waves[_wave]
	_wave += 1
	for i in n:
		var mk := room.find_child("Mark_gang_%d" % (_spawned % 10), true, false) as Node3D
		_spawned += 1
		var key: String = MEN[_rng.randi() % MEN.size()]
		var p := (load(Crowd.CROWD % key) as PackedScene).instantiate() as Node3D
		room.add_child(p)
		p.global_position = mk.global_position if mk else room.global_position
		p.scale = Vector3.ONE * _rng.randf_range(0.98, 1.06)
		if story and story.has_method("_tint"):          # dark shirts, the money-lender's men
			story._tint(p, "top", [Color(0.12, 0.12, 0.13), Color(0.2, 0.16, 0.14), Color(0.1, 0.14, 0.2)][i % 3])
		CrowdClips.add(p, "m")
		var ap := p.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		men.append({"node": p, "ap": ap, "hp": 3, "state": "come", "t": 0.0, "cool": _rng.randf_range(0.5, 2.0),
			"down": false, "orbit": _rng.randf_range(-1.0, 1.0)})
		_play(men[-1], "Walk")
	print("FIGHT wave %d: %d men" % [_wave, n])


func _play(m: Dictionary, clip: String, blend := 0.2) -> void:
	var ap: AnimationPlayer = m["ap"]
	if not ap.has_animation(clip):
		clip = "crowd/" + clip if ap.has_animation("crowd/" + clip) else "Idle"
	if ap.current_animation == clip:
		return
	var a := ap.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if clip in ["Walk", "Idle", "crowd/Guard", "Run"] else Animation.LOOP_NONE
	ap.play(clip, blend)


func _up(m: Dictionary) -> int:
	return 0 if m["down"] else 1


func _process(dt: float) -> void:
	if _done or city == null or city.walker == null:
		return
	var w = city.walker
	_controls(w, dt)
	var standing := 0
	_attackers = 0
	for m in men:
		if m["state"] == "attack":
			_attackers += 1
	for m in men:
		if not m["down"]:
			standing += 1
			_man(m, w, dt)
	if standing <= 1 and _wave < waves.size():
		_next_wave()
	elif standing == 0 and _wave >= waves.size():
		_end(true)
	elif city.life and city.life.hurt >= DOWN_AT:
		_end(false)


## One of them: closes in, circles at arm's length, comes in with a swing when it's his turn.
func _man(m: Dictionary, w: Node3D, dt: float) -> void:
	var n: Node3D = m["node"]
	var to: Vector3 = w.global_position - n.global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	m["t"] = float(m["t"]) + dt
	m["cool"] = maxf(float(m["cool"]) - dt, 0.0)
	match str(m["state"]):
		"come":
			n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * 8.0))
			var want := 2.2 if _attackers >= 1 else 1.3
			if d > want + 0.2:
				_step(n, dir, 2.2, dt)
				_play(m, "Walk")
			else:
				var side := Vector3(dir.z, 0.0, -dir.x) * float(m["orbit"])   # circling, waiting his turn
				_step(n, side, 0.6, dt)
				_play(m, "crowd/Guard")
				if m["cool"] <= 0.0 and _attackers < 1 and d < 1.6:   # (one at a time comes at him)
					m["state"] = "attack"
					m["t"] = 0.0
					_play(m, "crowd/Haymaker", 0.1)
		"attack":
			n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * (6.0 if m["t"] < 0.6 else 1.0)))
			if m["t"] > 0.75 and m["t"] < 0.9 and not m.get("landed", false):   # the swing comes round
				m["landed"] = true
				var facing: Vector3 = n.global_basis.z
				if d < 1.6 and facing.dot(dir) > 0.5 and _dodge <= 0.0:
					_hit_him(w, dir)
			if m["t"] > 1.2:
				m["state"] = "come"
				m["landed"] = false
				m["cool"] = _rng.randf_range(2.5, 4.5)
		"hit":
			_step(n, -dir, 1.2 * maxf(0.0, 0.4 - float(m["t"])), dt)
			if m["t"] > 0.5:
				m["state"] = "come"


func _step(n: Node3D, dir: Vector3, speed: float, dt: float) -> void:
	var nxt := n.global_position + dir * speed * dt
	for o in men:                                         # (they don't walk through each other)
		var on: Node3D = o["node"]
		if on != n and not o["down"] and on.global_position.distance_to(nxt) < 0.7:
			return
	var q := PhysicsRayQueryParameters3D.create(n.global_position + Vector3.UP * 0.8, nxt + Vector3.UP * 0.8 + dir * 0.35)
	if not room.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return                                            # (a sack stack in the way)
	n.global_position = nxt


func _hit_him(w: Node3D, dir: Vector3) -> void:
	var life = city.life
	if _blocking:
		if life:
			life.add_hurt(HIT_BLOCKED)
		w.knock(dir * 0.8)
		print("FIGHT blocked (hurt %.0f)" % (life.hurt if life else 0.0))
	else:
		if life:
			life.add_hurt(HIT)
		w.knock(dir * (1.9 if (life and life.hurt < 60.0) else 2.6))
		print("FIGHT hit (hurt %.0f)" % (life.hurt if life else 0.0))


# ---- his moves ----
func _controls(w: Node3D, dt: float) -> void:
	_busy = maxf(_busy - dt, 0.0)
	_dodge = maxf(_dodge - dt, 0.0)
	var punch := _pressed("punch", Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var dodge := _pressed("dodge", Input.is_key_pressed(KEY_SPACE))
	var block := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _test:                                           # (testing: as a player would: in close, blocks what's coming)
		_test_t += dt
		var near: Node3D = null
		var nd := 99.0
		var coming := false
		for m in men:
			if m["down"]:
				continue
			var dd: float = (m["node"] as Node3D).global_position.distance_to(w.global_position)
			if dd < nd:
				nd = dd
				near = m["node"]
			if m["state"] == "attack" and float(m["t"]) < 0.9:
				coming = true
		if near and nd > 1.3:
			var to := near.global_position - w.global_position
			w.rotation.y = atan2(-to.x, -to.z)
			w.auto_input = Vector2(0, -1)
		else:
			w.auto_input = Vector2.ZERO
		block = coming
		punch = not coming and nd < 1.6 and fmod(_test_t, 0.7) < dt
		dodge = false
	if w.is_down():
		return
	var gait = w.get("gait")
	if punch and _busy <= 0.0:
		var t := _target(w)
		if not t.is_empty():                             # turned to the nearest in front
			var to: Vector3 = (t["node"] as Node3D).global_position - w.global_position
			w._model_yaw = atan2(to.x, to.z)
		_move(w, gait, "crowd/Punch", 0.5)
		get_tree().create_timer(0.22).timeout.connect(func(): _land(w))
	elif dodge and _busy <= 0.0:
		_move(w, gait, "crowd/Dodge", 0.45)
		_dodge = 0.45
		var back := -Vector3(sin(w._model_yaw), 0.0, cos(w._model_yaw))
		w.velocity += back * 3.5
	_blocking = block and _busy <= 0.0
	if _blocking and gait:
		gait.held = true
		if w.anim.current_animation != "crowd/Block":
			w.anim.get_animation("crowd/Block").loop_mode = Animation.LOOP_LINEAR
			w.anim.play("crowd/Block", 0.12)
	elif not block and _busy <= 0.0 and gait and gait.held:
		gait.held = false
		w.anim.stop()


func _pressed(k: String, down: bool) -> bool:
	var was: bool = _keys.get(k, false)
	_keys[k] = down
	return down and not was


func _move(w: Node3D, gait, clip: String, secs: float) -> void:
	if not w.anim.has_animation(clip):
		return
	_busy = secs
	if gait:
		gait.held = true
	w.anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	w.anim.play(clip, 0.08)
	get_tree().create_timer(secs).timeout.connect(func():
		if gait and not _blocking:
			gait.held = false
			w.anim.stop())


func _target(w: Node3D) -> Dictionary:
	var best := {}
	var bd := 1.6
	var fwd := Vector3(sin(w._model_yaw), 0.0, cos(w._model_yaw))
	for m in men:
		if m["down"]:
			continue
		var to: Vector3 = (m["node"] as Node3D).global_position - w.global_position
		to.y = 0.0
		if to.length() < bd and (to.length() < 0.6 or fwd.dot(to.normalized()) > -0.2):
			bd = to.length()
			best = m
	return best


## The punch lands (a fifth of a second in): on the one in front, if he's still there.
func _land(w: Node3D) -> void:
	var t := _target(w)
	if t.is_empty():
		return
	t["hp"] = int(t["hp"]) - 1
	t["state"] = "hit"
	t["t"] = 0.0
	_play(t, "crowd/HitReact", 0.05)
	if int(t["hp"]) <= 0:
		_drop(t)
	print("FIGHT he lands one (%d left in him)" % int(t["hp"]))


## Down: he goes over backwards and stays there.
func _drop(m: Dictionary) -> void:
	m["down"] = true
	m["state"] = "down"
	var n: Node3D = m["node"]
	(m["ap"] as AnimationPlayer).play("Idle", 0.2)
	var axis := n.global_basis.x.normalized()
	var tw := create_tween()
	tw.tween_method(func(a: float):
		n.global_basis = Basis(axis, -a) * Basis(Vector3.UP, n.rotation.y)
		n.position.y = n.position.y, 0.0, PI * 0.48, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if city.life:                                       # (one fewer: he gets his breath a little)
		city.life.hurt = maxf(city.life.hurt - 6.0, 0.0)
	print("FIGHT one down")


func _end(won: bool) -> void:
	_done = true
	var w = city.walker
	if w and w.get("gait"):
		w.gait.held = false
		w.anim.stop()
	if not won and w:
		w.knock(Vector3(0, 0, 1) * 3.0, true)
	print("FIGHT over: %s (hurt %.0f)" % ["he got out with it" if won else "they took the ledger", city.life.hurt if city.life else 0.0])
	finished.emit(won)
