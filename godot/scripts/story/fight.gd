extends Node
## The fight in the godown (Day 18; docs/OPEN_WORLD_PLAN_2026-11-14.md: the ten men at the end): Suresh's men come in
## by waves (the room's Mark_gang_0..9: the shutter and the back door), and Karthik gets out with the ledger or
## doesn't. The fighting is the hand-to-hand system (scripts/combat/): Karthik's keys (player_combat.gd), every
## man a body of his own with his own way of fighting (enemy_ai.gd), the blows landing only when a fist meets a body
## (fighter.gd). This is the encounter: who comes in when, whose turn it is to come at him (one at a time: the rest
## hold their places on a ring round him), and how it ends. Played, not read: no bars.
##   waves        spec "waves" (3, 3, 4): the next comes in as the last of one is down to one man
##   the men      brawler, boxer, cautious in turn; dark shirts (the money-lender's men); put down: they stay down
##   his hurt     life.gd's: down for good at 90 (fighter.gd): they take the ledger
## finished(won) when it's over. Never a game over: losing costs the ledger, the story goes on with what's left.
##   --fight1v1   testing: one man (the first, polished encounter: the brief's "one-on-one first")
##   --fighttest  testing: Karthik fights by himself (player_combat.gd _bot)
##   --fightshots=DIR  testing: a picture a second into DIR: the gameplay view, then round him (front, side, back,
##                side), turn about, so every move is seen from every side in the running game
signal finished(won: bool)

const Crowd := preload("res://scripts/city/crowd.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const Fighter := preload("res://scripts/combat/fighter.gd")
const EnemyAI := preload("res://scripts/combat/enemy_ai.gd")
const PlayerCombat := preload("res://scripts/combat/player_combat.gd")
const MEN := ["m1", "m2", "m3", "m4", "m5", "m6"]
const STYLES := ["brawler", "boxer", "cautious"]

var city
var story
var room: Node3D
var waves: Array = [3, 3, 4]
var men: Array = []                   # enemy_ai.gd, each with .f (fighter.gd)
var turn = null                       # the man whose turn it is to come at him (enemy_ai.gd)
var pc                                # player_combat.gd
var _wave := 0
var _spawned := 0
var _done := false
var _rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func start(spec: Dictionary) -> void:
	_rng.seed = 1818
	waves = spec.get("waves", waves)
	if "--fight1v1" in OS.get_cmdline_user_args():
		waves = [1]
	if room == null:                                    # (no godown to fight in: nothing to fight; on, as won)
		push_warning("fight: no room")
		finished.emit.call_deferred(true)
		return
	var w = city.walker
	if w == null:
		push_warning("fight: no Karthik on foot")
		finished.emit.call_deferred(true)
		return
	CrowdClips.add(w.model, "m", true)                   # (his rig is the crowd's: all the fight's clips)
	pc = PlayerCombat.new()
	pc.name = "PlayerCombat"
	add_child(pc)
	pc.setup(w, city.life, w.get("gait"), func(): return men.map(func(m): return m.f))
	pc.engage()
	pc.f.defeated.connect(_end.bind(false))
	_next_wave()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fightshots="):
			_shots(a.get_slice("=", 1))
	if city.hud:
		city.hud.warn("F: punch (again: a combination) · Q: front kick · R: round kick · right mouse: guard · Space: slip", 7.0)


func _next_wave() -> void:
	if _wave >= waves.size():
		return
	var n: int = waves[_wave]
	_wave += 1
	for i in n:
		var mk := room.find_child("Mark_gang_%d" % (_spawned % 10), true, false) as Node3D
		var style: String = STYLES[_spawned % STYLES.size()]
		_spawned += 1
		men.append(_man(mk.global_position if mk else room.global_position, style, i))
	_slots()
	print("FIGHT wave %d: %d men (%s)" % [_wave, n, ", ".join(men.slice(men.size() - n).map(func(m): return m.style))])


## A man: his own body (a capsule: walls, sacks and other people stop him), the crowd model in it, his fighter and
## his way of fighting.
func _man(at: Vector3, style: String, i: int):
	var body := CharacterBody3D.new()
	body.name = "Man%d" % _spawned
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.72
	cs.shape = cap
	cs.position.y = 0.86
	body.add_child(cs)
	room.add_child(body)
	body.global_position = at + Vector3.UP * 0.05
	var key: String = MEN[_rng.randi() % MEN.size()]
	var p := (load(Crowd.CROWD % key) as PackedScene).instantiate() as Node3D
	body.add_child(p)
	p.scale = Vector3.ONE * _rng.randf_range(0.98, 1.06)
	if story and story.has_method("_tint"):              # dark shirts, the money-lender's men
		story._tint(p, "top", [Color(0.12, 0.12, 0.13), Color(0.2, 0.16, 0.14), Color(0.1, 0.14, 0.2)][i % 3])
	CrowdClips.add(p, "m")
	var ap := p.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var f := Fighter.new()
	f.name = "Fighter"
	f.label = "%s %d" % [style, _spawned]
	f.regen = 9.0 if style == "brawler" else 12.0
	body.add_child(f)
	f.setup(body, p, ap)
	f.opponents = [pc.f]
	var to: Vector3 = city.walker.global_position - at
	body.rotation.y = atan2(to.x, to.z)
	var ai := EnemyAI.new()
	ai.name = "AI"
	body.add_child(ai)
	ai.setup(f, pc.f, self, style, 100 + _spawned)
	f.defeated.connect(_one_down.bind(ai))
	return ai


## Their places on the ring round him: spread evenly, from where each stands now (no one walks through him).
func _slots() -> void:
	var up := men.filter(func(m): return m.f.alive())
	var me: Vector3 = city.walker.global_position
	up.sort_custom(func(a, b):
		var pa: Vector3 = a.f.body.global_position - me
		var pb: Vector3 = b.f.body.global_position - me
		return atan2(pa.x, pa.z) < atan2(pb.x, pb.z))
	var start := 0.0
	if not up.is_empty():
		var p0: Vector3 = up[0].f.body.global_position - me
		start = atan2(p0.x, p0.z)
	for i in up.size():
		up[i].slot = start + TAU * float(i) / float(up.size())


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	var n := 0
	while not _done or n % 2 == 1:
		await get_tree().create_timer(0.5 if n % 2 == 0 else 0.5).timeout
		var view := "game"
		if n % 2 == 1:                                  # (round him: the man he's on and him, from a side)
			var him: Vector3 = city.walker.global_position
			var other: Vector3 = pc.target.body.global_position if pc.target else him + Vector3(0, 0, 1)
			var mid := (him + other) * 0.5
			var ang := float((n / 2) % 4) * PI * 0.5 + atan2(other.x - him.x, other.z - him.z) + PI * 0.5
			var want := mid + Vector3(sin(ang), 0.0, cos(ang)) * 3.6 + Vector3.UP * 1.3
			var rq := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 1.3, want)   # (not inside a wall)
			rq.exclude = [city.walker.get_rid(), pc.target.body.get_rid()] if pc.target else [city.walker.get_rid()]
			var hit: Dictionary = city.walker.get_world_3d().direct_space_state.intersect_ray(rq)
			cam.global_position = want if hit.is_empty() else (hit["position"] as Vector3).lerp(mid + Vector3.UP * 1.3, 0.12)
			cam.look_at(mid + Vector3.UP * 0.9, Vector3.UP)
			cam.make_current()
			view = ["side", "back", "side2", "front"][(n / 2) % 4]
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_jpg("%s/fight_%03d_%s_%s.jpg" % [dir, n, view, pc.f.move if pc.f.move != "" else str(pc.f.state)], 0.8)
		if n % 2 == 1:
			cam.clear_current()
		n += 1
		if n > 400:
			break
	cam.queue_free()


## May he come at Karthik now (his turn asked for): not while Karthik's down, not two at once.
func may_attack(_ai) -> bool:
	return turn == null and pc.f.alive() and not pc.f.down()


func _physics_process(dt: float) -> void:
	if _done or pc == null:
		return
	for ai in men:
		if turn == ai and not ai.f.alive():
			turn = null
		ai.tick(dt)
		ai.f.tick(dt)
		var b: CharacterBody3D = ai.f.body
		var v: Vector3 = ai.f.velocity()
		b.velocity.x = v.x
		b.velocity.z = v.z
		b.velocity.y = 0.0 if b.is_on_floor() else b.velocity.y - _gravity * dt
		b.move_and_slide()


func _one_down(ai) -> void:
	if turn == ai:
		turn = null
	if city.life:                                       # (one fewer: he gets his breath a little)
		city.life.hurt = maxf(city.life.hurt - 4.0, 0.0)
	var up := men.filter(func(m): return m.f.alive()).size()
	print("FIGHT one down (%d still up)" % up)
	if up <= 1 and _wave < waves.size():
		_next_wave()
	elif up == 0:
		_end(true)
	else:
		_slots()


func _end(won: bool) -> void:
	if _done:
		return
	_done = true
	turn = null
	for ai in men:                                      # (those still up stand off)
		ai.f.desired = Vector3.ZERO
	if pc and won and pc.f.alive():                     # (standing, the last of them down: his breath first)
		pc.f.relief()
		await get_tree().create_timer(2.5).timeout
	if pc:
		pc.disengage()
	print("FIGHT over: %s (hurt %.0f)" % ["he got out with it" if won else "they took the ledger", city.life.hurt if city.life else 0.0])
	finished.emit(won)
