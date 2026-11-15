extends Node
## One of the men in a fight: a person with a way of fighting, not an attack machine. He watches Karthik, comes in
## carefully, circles at his place in the ring while another has his turn, waits for an opening, throws, and pays
## for a miss; he blocks or slips now and then, backs off to get his wind, gets up when he's put down.
##   styles   brawler: walks in and swings (haymakers, crosses), seldom guards
##            boxer:   jab and cross from just out of reach, guards often, keeps his distance
##            cautious: circles, waits for Karthik to throw and miss, then comes; backs off early
## The encounter (fight.gd) holds the turn (one man at a time comes at him: `director.turn`) and each man's place on
## the ring around him. Thinking every 0.1–0.3 s (a man's reaction time), not every frame.
const Moves := preload("res://scripts/combat/moves.gd")
const Fighter := preload("res://scripts/combat/fighter.gd")

enum E { IDLE, OBSERVING, APPROACHING, CIRCLING, ATTACKING, BLOCKING, DODGING, STAGGERED, RETREATING, RECOVERING, DEFEATED }

const STYLES := {
	"brawler":  {"attacks": ["Haymaker", "Cross", "HookR", "FrontKick", "Uppercut", "LowKick", "KneeStrike"], "block": 0.12, "slip": 0.05, "patience": [0.6, 1.6], "speed": 1.5, "tired_at": 15.0, "range": 0.95},
	"boxer":    {"attacks": ["Jab", "Cross", "Jab", "Hook", "JabR", "LowKick", "SideKick"], "block": 0.5, "slip": 0.15, "patience": [1.0, 2.4], "speed": 1.2, "tired_at": 25.0, "range": 1.0},
	"cautious": {"attacks": ["Jab", "Cross", "FrontKick", "Uppercut", "LowKick", "BodyKick"], "block": 0.35, "slip": 0.3, "patience": [1.8, 3.5], "speed": 1.0, "tired_at": 40.0, "range": 1.0},
}

var f                                   # fighter.gd (his)
var target                              # fighter.gd (Karthik's)
var director                            # fight.gd (the turn, the ring)
var style := "brawler"
var state := E.OBSERVING
var slot := 0.0                         # his place on the ring (radians round Karthik)
var _think := 0.0
var _wait := 0.0                        # patience before he asks for his turn
var _combo := 0
var _rng := RandomNumberGenerator.new()
var _next_kind := ""                    # the blow he means to throw next (he closes to its reach)
var _react := -1.0                      # seeing a blow coming: when he'll have moved (s)


func setup(fighter, tgt, dir_, st: String, seed_: int) -> void:
	f = fighter
	target = tgt
	director = dir_
	style = st
	_rng.seed = seed_
	_wait = _rng.randf_range(STYLES[style]["patience"][0], STYLES[style]["patience"][1])
	target.attack_started.connect(_seen_coming)
	f.attack_missed.connect(_missed)
	f.knocked_down.connect(_release.bind(0.0))
	f.staggered.connect(_hurt)


func _missed(_k: String) -> void:
	if director.turn == self:
		_release(0.6)


func _hurt() -> void:                                   # (hit on his turn: half the time he gives it up)
	if director.turn == self and _rng.randf() < 0.5:
		_release(0.4)


func _release(rest: float) -> void:
	if director.turn == self:
		director.turn = null
	_combo = 0
	_wait = _rng.randf_range(STYLES[style]["patience"][0], STYLES[style]["patience"][1]) + rest
	state = E.RECOVERING if rest > 0.0 else E.CIRCLING


## Karthik throws: if it's at him and he's near, he may get his guard up or slip it, if he sees it in time.
func _seen_coming(kind: String) -> void:
	if not f.alive() or f.down() or target.body.global_position.distance_to(f.body.global_position) > 1.8:
		return
	var st: Dictionary = STYLES[style]
	var r := _rng.randf()
	var slow := 1.0 if kind in ["Heavy", "Haymaker"] else 0.0
	if r < float(st["slip"]) + 0.15 * slow:
		_react = _rng.randf_range(0.1, 0.22)
		state = E.DODGING
	elif r < float(st["slip"]) + float(st["block"]) + 0.25 * slow:
		_react = _rng.randf_range(0.08, 0.2)             # (a jab lands at 0.15 s: he's often too late for one)
		state = E.BLOCKING


func tick(dt: float) -> void:
	if not f.alive():
		state = E.DEFEATED
		f.desired = Vector3.ZERO
		return
	if f.down() or f.state == Fighter.S.STAGGERED:
		state = E.STAGGERED
		f.desired = Vector3.ZERO
		f.want_block = false
		return
	var me: Vector3 = f.body.global_position
	var him: Vector3 = target.body.global_position
	var to := him - me
	to.y = 0.0
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	var st: Dictionary = STYLES[style]
	# he always watches Karthik (turning at a person's pace, not snapping)
	f.set_yaw(lerp_angle(f.yaw(), atan2(dir.x, dir.z), 1.0 - exp(-dt * (9.0 if f.ready_() else 2.0))))
	if _react >= 0.0:                                   # (a blow seen coming)
		_react -= dt
		if _react < 0.0:
			if state == E.DODGING:
				f.dodge(Vector3(1.0 if _rng.randf() < 0.5 else -1.0, 0.0, 0.0) if _rng.randf() < 0.6 else Vector3(0, 0, -1))
				state = E.CIRCLING
			elif state == E.BLOCKING:
				f.want_block = true
				_wait = maxf(_wait, 0.5)
	if f.want_block and state != E.BLOCKING:
		f.want_block = false
	elif f.want_block:
		_wait -= dt
		if _wait <= 0.0 or not target.busy_attacking() and _rng.randf() < dt * 2.0:
			f.want_block = false
			state = E.CIRCLING
	_think -= dt
	if _think > 0.0 and state != E.ATTACKING:
		return
	_think = _rng.randf_range(0.1, 0.3)
	if not target.alive() or target.down():             # (he's down: they stand off, they don't kick a man)
		_ring(dir, d, 2.6, st)
		return
	var tired: bool = f.stamina() < float(st["tired_at"])
	match state:
		E.IDLE, E.OBSERVING:
			state = E.APPROACHING
		E.RECOVERING:
			_wait -= _think
			_ring(dir, d, 2.4, st)
			if _wait <= 0.0:
				state = E.CIRCLING
		E.RETREATING:
			_ring(dir, d, 3.2, st)
			if f.stamina() > 70.0:
				state = E.CIRCLING
		E.APPROACHING, E.CIRCLING, E.BLOCKING:
			if tired and director.turn != self:
				state = E.RETREATING
				return
			_wait -= _think
			if style == "cautious" and target._missed_t > 0.0 and d < 2.2:   # (he missed: that's the opening)
				_wait = 0.0
			if _wait <= 0.0 and director.turn == null and director.may_attack(self):
				director.turn = self
				state = E.ATTACKING
				_combo = 1 + (_rng.randi() % 2 if style == "boxer" else 0)
			else:
				_ring(dir, d, 2.3 if director.turn != null else 1.9, st)
		E.ATTACKING:
			if _next_kind == "":
				_next_kind = st["attacks"][_rng.randi() % st["attacks"].size()]
			var kind := _next_kind
			var rng_m: float = float(Moves.MOVES[kind]["reach"]) + 0.3   # (in to where this one lands)
			if d > rng_m + 0.08:                         # (in to his distance)
				f.desired = dir * float(st["speed"])
			elif d < rng_m - 0.25:
				f.desired = -dir * 0.6
			else:
				f.desired = Vector3.ZERO
				if f.ready_() and f.attack(kind):
					_next_kind = ""
					_combo -= 1
					if _combo <= 0:
						_release(_rng.randf_range(0.6, 1.4))


## His place on the ring round Karthik: out at `r`, at his slot, sidestepping round to it; others kept off.
func _ring(dir: Vector3, d: float, r: float, st: Dictionary) -> void:
	var him: Vector3 = target.body.global_position
	var spot: Vector3 = him + Vector3(sin(slot), 0.0, cos(slot)) * r
	var go: Vector3 = spot - f.body.global_position
	go.y = 0.0
	var v := Vector3.ZERO
	if go.length() > 0.25:
		v = go.normalized() * minf(go.length() * 1.5, float(st["speed"]) * 0.8)
	for o in director.men:                              # (not on top of one another)
		if o == self or not o.f.alive():
			continue
		var away: Vector3 = f.body.global_position - o.f.body.global_position
		away.y = 0.0
		if away.length() < 1.2 and away.length() > 0.01:
			v += away.normalized() * (1.2 - away.length()) * 1.5
	f.desired = v
