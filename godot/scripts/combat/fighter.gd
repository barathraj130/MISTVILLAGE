extends Node
## One person in a fight (Karthik or one of the men): what he's doing (the state), his clips, his stamina, the
## blows he throws (each lands only when his fist meets the other man's body in the clip's contact window, once,
## and not through a wall) and the ones he takes (blocked, slipped, staggered by where they came from, put down).
## The moves' timings are moves.gd's (from the clips as they were made). Travel (a dodge, a stagger) is given to the
## body as velocity along the clip's own curve, and the body's move_and_slide keeps him out of walls, sacks, cars and
## other people: nothing teleports, nothing goes through anything.
##   body       the CharacterBody3D that carries him (Karthik's player.gd, or the man's own)
##   model      what's turned to face (Karthik: player.gd's _model_yaw; a man: his body)
##   is_player  Karthik: his hurt is life.gd's, his stamina gait.gd's
const Moves := preload("res://scripts/combat/moves.gd")

signal attack_started(kind: String)
signal attack_connected(target: Node)
signal attack_missed(kind: String)
signal block_started
signal dodge_started(dir: Vector3)
signal staggered
signal knocked_down
signal recovered
signal defeated

enum S { IDLE, STANCE, MOVING, LIGHT, HEAVY, BLOCKING, DODGING, COUNTERING, STAGGERED, KNOCKED_DOWN, GETTING_UP, RECOVERING, DEFEATED }

var body: CharacterBody3D
var model: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var is_player := false
var player                              # player.gd (Karthik)
var life                                # life.gd (Karthik's hurt)
var gait                                # gait.gd (Karthik's stamina)
var opponents: Array = []               # the other side's fighters
var label := ""                         # (for the log)

var state := S.STANCE
var move := ""                          # the clip playing ("" between moves)
var t := 0.0                            # seconds into it
var hp := 100.0                         # (a man's; Karthik's hurt is life.gd's)
var stamina_own := 100.0                # (a man's; Karthik's is gait.gd's)
var regen := 12.0                       # stamina a second, at rest
var is_player_wind := true              # Karthik's wind is gait.gd's (false: his own, stamina_own, in a fight)
var want_block := false                 # holding the guard up
var desired := Vector3.ZERO             # where he'd go (world, m/s): footwork
var stay_down := false                  # down for good when he next goes down (no getting up)
var counter_t := 0.0                    # a blow just taken on the guard: the opening for a counter
var _hit_done := false
var _queued := ""                       # a combination pressed in time
var _down_wait := 0.0
var _guard_clip := ""
var _sphere := SphereShape3D.new()
var _missed_t := 0.0
var _floor := "back"                   # how he's lying: "back" (KnockDown, FallSide) or "front" (FallF)
var _kneel_t := -1.0                   # getting up hurt: a moment on one knee (s left)


func setup(b: CharacterBody3D, m: Node3D, a: AnimationPlayer) -> void:
	body = b
	model = m
	anim = a
	var sks := m.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if not sks.is_empty() else null
	_sphere.radius = 0.12
	body.set_meta("fighter", self)


# ---- what's what ----
func yaw() -> float:
	return float(player._model_yaw) if is_player else body.rotation.y


func set_yaw(y: float) -> void:
	if is_player:
		player._model_yaw = y
	else:
		body.rotation.y = y


func front() -> Vector3:
	var y := yaw()
	return Vector3(sin(y), 0.0, cos(y))


func stamina() -> float:
	return float(gait.stamina) if is_player and is_player_wind and gait else stamina_own


func spend(v: float) -> void:
	if is_player and is_player_wind and gait:
		gait.stamina = clampf(gait.stamina - v, 0.0, 100.0)
	else:
		stamina_own = clampf(stamina_own - v, 0.0, 100.0)


func hurt() -> float:
	return float(life.hurt) if is_player and life else 100.0 - hp


func alive() -> bool:
	return state != S.DEFEATED


func down() -> bool:
	return state in [S.KNOCKED_DOWN, S.GETTING_UP, S.DEFEATED]


## Free to start something new: standing in his guard (or holding it up).
func ready_() -> bool:
	return state in [S.IDLE, S.STANCE, S.MOVING, S.BLOCKING]


func busy_attacking() -> bool:
	return state in [S.LIGHT, S.HEAVY, S.COUNTERING]


## Low on wind: slower moves, a weaker guard, the breath showing.
func tired() -> float:
	return clampf((30.0 - stamina()) / 30.0, 0.0, 1.0)


# ---- clips ----
func _play(clip: String, blend := 0.1, loop := false, speed := 1.0) -> void:
	var n := "crowd/" + clip
	if not anim.has_animation(n):
		return
	var a := anim.get_animation(n)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if anim.current_animation == n and loop:
		anim.speed_scale = speed
		return
	anim.play(n, blend)
	anim.speed_scale = speed


func _start(clip: String, st: int, blend := 0.08) -> void:
	move = clip
	t = 0.0
	_hit_done = false
	state = st
	_guard_clip = ""
	_play(clip, blend, false, 1.0 - 0.15 * tired() if st in [S.LIGHT, S.HEAVY, S.COUNTERING] else 1.0)


# ---- what he does ----
## A blow: "Jab", "Cross", "Hook" (light), "Heavy", "Haymaker" (heavy). Only from his guard, with the wind for it.
func attack(kind: String) -> bool:
	if state == S.LIGHT and kind in ["Jab", "Cross", "Hook", "Uppercut", "JabR"] and t >= float(Moves.MOVES[move].get("hit", 0.0)) - 0.1:
		_queued = Moves.COMBO.get(move, kind)           # (a combination: the next in it, as this one comes back)
		return true
	if not ready_():
		return false
	var m: Dictionary = Moves.MOVES[kind]
	if stamina() < float(m["cost"]) * 0.5:              # (no wind: nothing in it; he can't)
		return false
	var counter := counter_t > 0.0 and kind in ["Jab", "Cross"]
	if counter:
		kind = "Cross"
	spend(float(m["cost"]))
	_start(kind, S.COUNTERING if counter else (S.HEAVY if m.get("heavy", false) else S.LIGHT))
	counter_t = 0.0
	attack_started.emit(kind)
	return true


func dodge(dir_local: Vector3) -> bool:
	if not ready_() or stamina() < 8.0:
		return false
	var clip := "DodgeB"
	if dir_local.x > 0.5:
		clip = "DodgeL"
	elif dir_local.x < -0.5:
		clip = "DodgeR"
	spend(float(Moves.MOVES[clip]["cost"]))
	_start(clip, S.DODGING)
	dodge_started.emit(dir_local)
	return true


# ---- each frame ----
func tick(dt: float) -> void:
	t += dt * (anim.speed_scale if anim else 1.0)
	counter_t = maxf(counter_t - dt, 0.0)
	_missed_t = maxf(_missed_t - dt, 0.0)
	if state in [S.IDLE, S.STANCE, S.MOVING, S.BLOCKING] and not (want_block and state == S.BLOCKING):
		spend(-regen * dt * (0.5 if desired.length() > 0.3 else 1.0))
	var m: Dictionary = Moves.MOVES.get(move, {})
	var len := float(m.get("len", 0.0))
	match state:
		S.LIGHT, S.HEAVY, S.COUNTERING:
			var h := float(m.get("hit", 0.0))
			if not _hit_done and t >= h - 0.04 and t <= h + 0.06:
				_try_hit(m)
			if not _hit_done and t > h + 0.06:
				_hit_done = true
				_missed_t = 0.5
				attack_missed.emit(move)
				if not opponents.is_empty():                 # (how far it fell short: for tuning)
					var o = opponents[0]
					var fp := _fist()
					var oc: Vector3 = o.body.global_position + Vector3.UP * clampf(fp.y - o.body.global_position.y, 0.3, 1.45)
					_log("missed %s: fist %.2f m from his body's middle (%.2f m apart)" % [move, Vector2(fp.x - oc.x, fp.z - oc.z).length(),
						Vector2(body.global_position.x - o.body.global_position.x, body.global_position.z - o.body.global_position.z).length()])
			if _queued != "" and t >= h + 0.05 and state == S.LIGHT:
				var q := _queued
				_queued = ""
				state = S.STANCE
				if not attack(q):
					state = S.RECOVERING
			elif t >= len:
				_queued = ""
				var kick: bool = Moves.MOVES.get(move, {}).has("bone")
				move = ""
				state = S.RECOVERING if _missed_t > 0.0 and (state == S.HEAVY or kick) else S.STANCE   # (a kick that met nothing: off balance a moment)
				t = 0.0
		S.RECOVERING:                                    # (a big one that missed: off balance a moment)
			if move == "" and t >= 0.45:
				state = S.STANCE
			elif move != "" and t >= len:
				move = ""
				t = 0.0
				state = S.STANCE
		S.DODGING, S.STAGGERED:
			if t >= len:
				move = ""
				state = S.STANCE
				recovered.emit()
		S.KNOCKED_DOWN:
			if t >= len:
				_loop("DownIdle" if _floor == "back" else "DownIdleF", 1.0)   # (lying there, breathing)
				if stay_down or (is_player and hurt() >= 90.0) or (not is_player and hp <= 0.0):
					state = S.DEFEATED
					defeated.emit()
				else:
					_down_wait += dt
					if _down_wait > 1.2:
						_down_wait = 0.0
						_start("GetUp" if _floor == "back" else "GetUpF", S.GETTING_UP, 0.25)
						_kneel_t = 1.2 if (hurt() > 50.0) else -1.0
		S.GETTING_UP:                                    # (hurt: a moment on one knee, his breath, then up)
			var kn := float(m.get("kneel", 0.6)) * len
			if _kneel_t > 0.0 and t >= kn:
				if _guard_clip != "KneelIdle":
					_loop("KneelIdle", 1.0)
				_kneel_t -= dt
				t = kn
				if _kneel_t <= 0.0:
					_play(move, 0.3)
					anim.seek(kn, true)
					_guard_clip = ""
			elif t >= len:
				move = ""
				state = S.STANCE
				recovered.emit()
		S.IDLE, S.STANCE, S.MOVING, S.BLOCKING:
			if want_block and stamina() > 1.0:
				if state != S.BLOCKING:
					block_started.emit()
				state = S.BLOCKING
				if move == "BlockHit" and t < len:
					pass
				else:
					move = ""
					_loop("Block", 1.0)
			else:
				state = S.MOVING if desired.length() > 0.15 else S.STANCE
				if move == "" or t >= len:
					move = ""
					_footwork()


func _loop(clip: String, speed: float) -> void:
	if _guard_clip != clip:
		_guard_clip = clip
		_play(clip, 0.15, true, speed)
	else:
		anim.speed_scale = speed


## His feet: the guard on the spot, or the step-and-drag the way he's going (relative to the way he faces), played at
## the pace he's covering ground (STEP_DIST a cycle).
func _footwork() -> void:
	var v := desired
	if v.length() < 0.15:
		_loop("GuardLow" if tired() > 0.6 else "Guard", 1.0)   # (out of wind: the hands come down)
		return
	var l := Basis(Vector3.UP, yaw()).inverse() * v
	var clip := "GuardStepF"
	if absf(l.x) > absf(l.z):
		clip = "GuardStepL" if l.x > 0.0 else "GuardStepR"
	elif l.z < 0.0:
		clip = "GuardStepB"
	_loop(clip, clampf(v.length() / (Moves.STEP_DIST / Moves.STEP_CYCLE), 0.6, 2.4))


## The body's velocity this frame (world, horizontal): a travelling move's own, or his footwork (none mid-blow).
func velocity() -> Vector3:
	var m: Dictionary = Moves.MOVES.get(move, {})
	if m.has("travel"):
		return Basis(Vector3.UP, yaw()) * Moves.travel_velocity(move, t / float(m["len"]))
	if state in [S.STANCE, S.MOVING]:
		return desired * (1.0 - 0.3 * tired())
	if state == S.BLOCKING:
		return desired * 0.5
	return Vector3.ZERO


# ---- landing a blow ----
func _fist() -> Vector3:
	var mv: Dictionary = Moves.MOVES[move]
	var hand := str(mv.get("bone", "hand_" + str(mv.get("hand", "r"))))
	if skel:
		var i := skel.find_bone(hand)
		if i >= 0:
			var p := skel.global_transform * skel.get_bone_global_pose(i).origin
			return p + (Vector3.ZERO if mv.has("bone") else front() * 0.06)   # (the knuckles, past the wrist)
	return body.global_position + Vector3.UP * 1.4 + front() * 0.75


func _try_hit(m: Dictionary) -> void:
	var space := body.get_world_3d().direct_space_state
	var fist := _fist()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, fist)
	q.exclude = [body.get_rid()]
	for hit in space.intersect_shape(q, 8):
		var co = hit["collider"]
		if not (co is Node and (co as Node).has_meta("fighter")):
			continue
		var other = (co as Node).get_meta("fighter")
		if not other in opponents or other.down():
			continue
		var chest := body.global_position + Vector3.UP * 1.3   # (not through a wall, a post, a stack of sacks)
		var rq := PhysicsRayQueryParameters3D.create(chest, fist)
		rq.exclude = [body.get_rid(), (co as CollisionObject3D).get_rid()]
		if not space.intersect_ray(rq).is_empty():
			continue
		_hit_done = true
		var dmg := float(m["dmg"]) * (Moves.COUNTER_BONUS if state == S.COUNTERING else 1.0) * (1.0 - 0.3 * tired())
		if other.take_hit(self, move, dmg, bool(m.get("heavy", false)) or state == S.COUNTERING):
			attack_connected.emit(other)
		return


## A blow arrives from `by`: true if it landed (blocked counts: it was met), false if it went past him.
func take_hit(by, kind: String, dmg: float, heavy: bool) -> bool:
	if down():
		return false
	if state == S.DODGING and t < float(Moves.MOVES[move]["len"]) * 0.7:   # (slipped: it goes past)
		return false
	var to_him: Vector3 = by.body.global_position - body.global_position
	to_him.y = 0.0
	to_him = to_him.normalized()
	var facing := front().dot(to_him) > 0.3
	if state == S.BLOCKING and facing:
		var cost := 6.0 + (12.0 if heavy else 0.0)
		spend(cost)
		if stamina() <= 0.5 or (heavy and stamina() < 20.0):   # (the guard knocked open)
			_apply(dmg * 0.5)
			_start("GuardBreak", S.STAGGERED, 0.05)
			staggered.emit()
			_log("guard broken by %s" % kind)
			return true
		_apply(dmg * (0.12 + 0.2 * tired()))
		_start("BlockHit", S.BLOCKING, 0.05)
		counter_t = Moves.COUNTER_WINDOW
		_log("blocked %s" % kind)
		return true
	_apply(dmg)
	var dead: bool = (hp <= 0.0) if not is_player else (life != null and life.hurt >= 90.0)
	var push := -to_him                                 # (away from the blow, in his own frame)
	var l := Basis(Vector3.UP, yaw()).inverse() * push
	if dead or (heavy and state == S.STAGGERED):        # down: which way depends on where it came from
		stay_down = dead
		var fall := "KnockDown"
		if l.z > 0.6:
			fall = "FallF"
		elif absf(l.x) > 0.6:
			fall = "FallSide"
		_floor = "front" if fall == "FallF" else "back"
		_start(fall, S.KNOCKED_DOWN, 0.06)
		knocked_down.emit()
		_log("down (%s, %s)" % [kind, fall])
		return true
	var clip := "StaggerF"
	if l.z > 0.6:
		clip = "StaggerB"
	elif absf(l.x) > 0.6:
		clip = "StaggerR" if l.x > 0.0 else "StaggerL"
	_start(clip, S.STAGGERED, 0.05)
	staggered.emit()
	_log("hit by %s (%s)" % [kind, clip])
	return true


## It's over and he's standing: bent over, hands on his knees, getting his breath.
func relief() -> void:
	move = ""
	state = S.IDLE
	desired = Vector3.ZERO
	want_block = false
	_guard_clip = ""
	_loop("Relief", 1.0)


func _apply(dmg: float) -> void:
	if is_player:
		if life:
			life.add_hurt(dmg)
	else:
		hp -= dmg


func _log(s: String) -> void:
	print("FIGHT %s: %s (%s %.0f, wind %.0f)" % [label, s, "hurt" if is_player else "hp", hurt() if is_player else hp, stamina()])
