extends Node
## Karthik in a fight: the keys to his fighter (fighter.gd), his footwork facing the man he's on, and the view.
##   F or the left mouse    a jab; pressed again in time, the cross, then the hook (a combination)
##   Q                      a front kick (the ball of the foot into his middle: it puts him back)
##   R                      a round kick: to the thigh; to the body when he's staggered or his guard's down
##                          (that one can put a staggered man down)
##   the right mouse held   the guard (blows on it cost wind; a big one on a tired guard knocks it open);
##                          a light press just after a blow on the guard: a counter (a cross through the opening)
##   Space                  a slip: left or right with A/D, back with nothing or S (it costs wind)
##   WASD                   footwork in the guard, facing him: in, out, round
## The view keeps him and the man he's on in it (turned gently, only when the man's well off to the side), a small
## knock when a blow lands. Played, not read: no bars; the hurt shows on him (body.gd), the wind in his breath.
##   --fighttest   testing: he fights by himself (in, blocks what's coming, combinations, now and then the big one)
const Moves := preload("res://scripts/combat/moves.gd")
const Fighter := preload("res://scripts/combat/fighter.gd")
const SPEED := 1.25                     # footwork, m/s

var f                                   # his fighter.gd
var player                              # player.gd
var engaged := false
var target                              # the fighter he's on
var test := false
var _keys := {}
var _shake := 0.0
var _snd: AudioStreamPlayer3D
var _test_t := 0.0


func setup(p, life, gait, opponents_getter: Callable) -> void:
	player = p
	f = Fighter.new()
	f.name = "Fighter"
	f.is_player = true
	f.player = p
	f.life = life
	f.gait = gait
	f.label = "Karthik"
	add_child(f)
	f.setup(p, p.model, p.anim)
	_opponents = opponents_getter
	f.attack_connected.connect(_landed)
	_snd = AudioStreamPlayer3D.new()
	_snd.stream = _thud()
	_snd.unit_size = 4.0
	p.add_child(_snd)
	test = "--fighttest" in OS.get_cmdline_user_args()


var _opponents: Callable


func engage() -> void:
	engaged = true
	player.combat = self
	f.is_player_wind = false                            # (his own wind for the fight: he came in walking, rested)
	f.stamina_own = maxf(float(player.gait.stamina) if player.gait else 100.0, 80.0)
	if player.gait:
		player.gait.held = true


func disengage() -> void:
	engaged = false
	player.combat = null
	if player.gait:
		player.gait.held = false
		player.gait.stamina = f.stamina_own              # (out of breath after it, as he is)
	if player.anim:
		player.anim.speed_scale = 1.0
		player.anim.stop()
	if player.camera:
		player.camera.h_offset = 0.0
		player.camera.v_offset = 0.0


func _pressed(k: String, down: bool) -> bool:
	var was: bool = _keys.get(k, false)
	_keys[k] = down
	return down and not was


## The nearest man still up, the one ahead first.
func _pick() -> void:
	var best = null
	var bd := 99.0
	var fwd: Vector3 = f.front()
	for o in _opponents.call():
		if not o.alive():
			continue
		var to: Vector3 = o.body.global_position - player.global_position
		to.y = 0.0
		var score := to.length() - 1.2 * fwd.dot(to.normalized()) + (2.0 if o.down() else 0.0)
		if score < bd:
			bd = score
			best = o
	target = best
	f.opponents = _opponents.call()


## player.gd asks, each physics frame, how he moves (wish: the keys' way in the world, unit or zero).
func steer(wish: Vector3, dt: float) -> Vector3:
	_pick()
	var light := _pressed("light", Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var heavy := _pressed("heavy", Input.is_key_pressed(KEY_R))
	var push := _pressed("push", Input.is_key_pressed(KEY_Q))
	var dodge := _pressed("dodge", Input.is_key_pressed(KEY_SPACE))
	f.want_block = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if test:
		var b := _bot(dt)
		light = b[0]
		heavy = b[1]
		dodge = b[2]
		wish = b[3]
		push = b[4]
	var to := Vector3.ZERO
	var d := 99.0
	if target:
		to = target.body.global_position - player.global_position
		to.y = 0.0
		d = to.length()
		if f.ready_() or f.state == Fighter.S.DODGING:   # (facing him, turning as a man does: quickly, not snapping)
			f.set_yaw(lerp_angle(f.yaw(), atan2(to.x, to.z), 1.0 - exp(-dt * 10.0)))
		_view(to, dt)
	f.desired = wish * SPEED
	if light:
		f.attack("Jab")
	elif heavy:                                         # (a round kick: high if he's open)
		f.attack("BodyKick" if target and (target.state == Fighter.S.STAGGERED or target.tired() > 0.5) else "LowKick")
	elif push:                                          # (in close: the knee; at range: the front kick)
		f.attack("KneeStrike" if d < 0.75 else "FrontKick")
	elif dodge:
		var l: Vector3 = Basis(Vector3.UP, f.yaw()).inverse() * wish
		f.dodge(Vector3(signf(l.x), 0.0, 0.0) if absf(l.x) > 0.4 else Vector3(0, 0, -1))
	f.tick(dt)
	var v: Vector3 = f.velocity()
	if f.busy_attacking() and target and not f._hit_done:   # (a short step in to land it, if he's just out of reach)
		var m: Dictionary = Moves.MOVES[f.move]
		var short := d - float(m["reach"]) - 0.25
		if short > 0.0 and short < 0.8 and f.t < float(m["hit"]):
			v += to.normalized() * clampf(short / maxf(float(m["hit"]) - f.t, 0.05), 0.0, 3.0)
	_shake = maxf(_shake - dt * 6.0, 0.0)
	if player.camera:
		player.camera.h_offset = sin(Time.get_ticks_msec() * 0.09) * 0.03 * _shake
		player.camera.v_offset = cos(Time.get_ticks_msec() * 0.11) * 0.02 * _shake
	return v


## The view: when the man he's on drifts well off to the side, it comes round (gently) to keep them both in it.
func _view(to: Vector3, dt: float) -> void:
	var want := atan2(-to.x, -to.z)                     # (the view looks down its -Z: along `to`)
	var off := angle_difference(player.rotation.y, want)
	if absf(off) > 0.5:
		player.rotation.y += off * (1.0 - exp(-dt * 2.0)) * (absf(off) - 0.5) / absf(off)


func _landed(_other) -> void:
	_shake = 1.0
	_snd.pitch_scale = randf_range(0.85, 1.15)
	_snd.play()


## A blow's sound, made here: a short low thump with a slap of noise on it.
static func _thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.16)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var tt := float(i) / rate
		var env := exp(-tt * 38.0)
		var s := (sin(TAU * (95.0 - 260.0 * tt) * tt) * 0.8 + rng.randf_range(-1.0, 1.0) * exp(-tt * 120.0) * 0.6) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## (testing) as a player would: in to reach, the guard up for what's coming, a combination, the big one on a
## staggered man, a slip from a haymaker now and then.
func _bot(dt: float) -> Array:
	_test_t += dt
	var wish := Vector3.ZERO
	var light := false
	var heavy := false
	var dodge := false
	if target == null:
		return [false, false, false, wish, false]
	var to: Vector3 = target.body.global_position - player.global_position
	to.y = 0.0
	var d := to.length()
	var coming := false
	for o in _opponents.call():
		if o.alive() and o.busy_attacking() and not o._hit_done and o.body.global_position.distance_to(player.global_position) < 1.8:
			coming = true
			if o.move == "Haymaker" and fmod(_test_t, 3.0) < 1.0:
				dodge = o.t > 0.5
	f.want_block = coming and not dodge
	if d > 1.0:
		wish = to.normalized()
	elif d < 0.75:
		wish = -to.normalized()
	var push := false
	if not coming and d < 1.3:
		var beat := int(_test_t / 0.35)
		if fmod(_test_t, 0.35) < dt:                   # (punches, a kick every so often)
			if target.state == Fighter.S.STAGGERED or beat % 7 == 3:
				heavy = true
			elif beat % 9 == 5:
				push = true
			else:
				light = true
	return [light, heavy, dodge, wish, push]
