extends Node
## Suresh's people, as the case closes in (OPEN_WORLD_PLAN phase 7; the gang brief's six stages on the real story,
## docs/OPEN_WORLD_PLAN_2026-11-14.md §2). The stage is read from what Karthik has found (story.gd `evidence`), saved
## in the story's flags ("gang_stage"), and never goes back:
##   1 safe          nobody is watching yet
##   2 watched       from E05 (Day 6, the third piece that holds): now and then the same man keeps 25–35 m behind
##                   him on foot, by a shop or a pole, watching; walk at him or keep looking at him and he turns away
##                   and goes. He never comes closer. A picture of him on the phone: a note, "the same man".
##   3 pursued       once E10 and E13 are his (Day 17), only E19 and E15 left: on his drives a black sedan picks
##                   him up (story.gd's tail and chase, as on Day 13: lose it in the lanes), once a day
##   4 the godown    from E19 (Day 18): the ten men guard the ledger (phase 8)
##   5 hiding        from E15 (the night of Day 18): the search while he hides (phase 8)
##   6 before court  the trial (court_done)
## No frights: the watcher is a man you notice, not a jump.
##   --gangstage=N  testing: start at stage N
##   --gangtest     testing: stage 2, the watcher brought out; pictures of him and of him leaving (user://gang_*.jpg)
const Crowd := preload("res://scripts/city/crowd.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const WATCHER := "m4"                 # the same face each time (crowd_m4), in dark grey
const NAMES := ["", "safe", "watched", "pursued", "the godown", "hiding", "before court"]

var city
var stage := 1
var watcher: Node3D
var _ap: AnimationPlayer
var _look: Node
var _wait := 40.0                     # seconds till he may turn up again
var _out := 0.0                       # how long he's been out this time
var _stared := 0.0                    # how long Karthik has looked straight at him
var _leaving := false
var _leave_to := Vector3.ZERO
var _test := false
var _pursued_day := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gangstage="):
			stage = int(a.get_slice("=", 1))
		if a == "--gangtest":
			_test = true
			stage = maxi(stage, 2)
			_wait = 3.0


func _story():
	return city.story if city and "story" in city else null


## The stage from what he holds; kept in the story's flags (saved with it); only ever forward.
func _read_stage() -> void:
	var st = _story()
	if st == null:
		return
	var found: Dictionary = st.evidence if "evidence" in st else {}
	var s := int(st.flags.get("gang_stage", 1))
	if found.has("E05"):
		s = maxi(s, 2)
	if found.has("E10") and found.has("E13"):
		s = maxi(s, 3)
	if found.has("E19"):
		s = maxi(s, 4)
	if found.has("E15"):
		s = maxi(s, 5)
	if st.flags.get("court_done", false):
		s = 6
	s = maxi(s, stage)
	if s != int(st.flags.get("gang_stage", 1)):
		st.flags["gang_stage"] = s
		print("GANG stage %d (%s)" % [s, NAMES[s]])
	stage = s


func _process(dt: float) -> void:
	_read_stage()
	var w: Node3D = city.walker if city else null
	var indoors: bool = city and "indoors" in city and city.indoors
	if stage in [2, 3] and w != null and not indoors:
		_watch(dt, w)
	elif watcher:
		_gone()
	if stage == 3:
		_pursue()


# ---- the watcher ----
func _watch(dt: float, w: Node3D) -> void:
	if watcher == null:
		_wait -= dt
		if _wait <= 0.0:
			_wait = randf_range(90.0, 200.0)              # (not always: now and then)
			_appear(w)
		return
	_out += dt
	var to_him: Vector3 = w.global_position - watcher.global_position
	to_him.y = 0.0
	var d := to_him.length()
	if _leaving:
		var go := _leave_to - watcher.global_position
		go.y = 0.0
		if go.length() < 1.0 or d > 70.0:
			_gone()
			return
		_walk(go.normalized(), 1.5, dt)
		return
	var cam := get_viewport().get_camera_3d()           # is Karthik looking right at him?
	if cam:
		var see := (watcher.global_position + Vector3.UP * 1.5 - cam.global_position).normalized()
		_stared = (_stared + dt) if (-cam.global_basis.z).dot(see) > 0.97 and d < 45.0 else maxf(_stared - dt, 0.0)
	if d < 12.0 or _stared > 2.5 or _out > 120.0:      # caught looking, or walked at: he turns and goes
		_leave(w)
		return
	if d > 38.0:                                         # (he keeps up, unhurried)
		_walk(to_him.normalized(), 1.35, dt)
	else:
		_play("Idle" if randf() > 0.002 else "crowd/Phone")
		watcher.rotation.y = lerp_angle(watcher.rotation.y, atan2(to_him.x, to_him.z), 1.0 - exp(-dt * 2.0))
	if _look:
		_look.target = w.global_position + Vector3.UP * 1.5
		_look.weight = 0.0 if _leaving else 0.8


func _appear(w: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	var p := (load(Crowd.CROWD % WATCHER) as PackedScene).instantiate() as Node3D
	add_child(p)
	watcher = p
	var st = _story()
	if st and st.has_method("_tint"):
		st._tint(p, "top", Color(0.17, 0.17, 0.19))       # dark grey shirt
		st._tint(p, "bottom", Color(0.1, 0.1, 0.12))
	var aps := p.find_children("*", "AnimationPlayer", true, false)
	_ap = aps[0] if not aps.is_empty() else null
	var sks := p.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_look = HeadLook.new()
		sks[0].add_child(_look)
	CrowdClips.add(p, "m")                                # (the crowd's clips: the phone)
	var back: Vector3 = -(w.get("model") as Node3D).global_basis.z if w.get("model") else -w.global_basis.z
	back.y = 0.0
	var at: Vector3 = w.global_position + back.normalized().rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)) * 30.0
	at = _footpath(at)
	p.global_position = at
	_out = 0.0
	_stared = 0.0
	_leaving = false
	print("GANG the watcher, %.0f m behind him" % at.distance_to(w.global_position))
	if _test:
		_run_test.call_deferred(w)


## The nearest walkable spot (the citizens' footpaths if they're built), on the ground.
func _footpath(at: Vector3) -> Vector3:
	if city and "citizens" in city and city.citizens and city.citizens.has_method("_spot_near"):
		var q: Vector3 = city.citizens._spot_near(at)
		if q != Vector3.INF and q.distance_to(at) < 25.0:
			at = q
	var g: float = city.streamer.height_at(at.x, at.z) if city and city.streamer else NAN
	if not is_nan(g):
		at.y = g
	return at


func _walk(dir: Vector3, pace: float, dt: float) -> void:
	watcher.global_position += dir * pace * dt
	var g: float = city.streamer.height_at(watcher.global_position.x, watcher.global_position.z) if city.streamer else NAN
	if not is_nan(g):
		watcher.global_position.y = lerpf(watcher.global_position.y, g, 1.0 - exp(-dt * 6.0))
	watcher.rotation.y = lerp_angle(watcher.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * 6.0))
	_play("Walk")
	if _ap and _ap.has_animation("Walk"):
		_ap.speed_scale = pace / float(watcher.get_meta("stride", 1.18))


func _leave(w: Node3D) -> void:
	_leaving = true
	var away: Vector3 = watcher.global_position - w.global_position
	away.y = 0.0
	_leave_to = _footpath(watcher.global_position + away.normalized().rotated(Vector3.UP, 0.5) * 45.0)
	print("GANG the watcher turns away (%s)" % ("seen" if _stared > 2.5 else "walked at" if away.length() < 12.0 else "time"))


func _gone() -> void:
	if watcher:
		watcher.queue_free()
	watcher = null
	_ap = null
	_look = null
	_leaving = false


func _play(clip: String) -> void:
	if _ap == null:
		return
	if not _ap.has_animation(clip):
		clip = "Idle"
	if _ap.current_animation != clip:
		_ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_ap.play(clip, 0.4)
		if clip != "Walk":
			_ap.speed_scale = 1.0


## Is he in the picture just taken? (phone.gd asks: the watcher on screen, near enough to be made out)
func in_view(cam: Camera3D) -> bool:
	if watcher == null or cam == null:
		return false
	var p := watcher.global_position + Vector3.UP * 1.4
	return not cam.is_position_behind(p) and cam.global_position.distance_to(p) < 50.0 \
		and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(cam.unproject_position(p))


# ---- the pursuit ----
## Stage 3: on a drive with no tail of its own, once a day, the black sedan picks him up after a minute at the wheel
## (story.gd's tail and chase: lose it in the lanes).
var _drive_t := 0.0


func _pursue() -> void:
	var st = _story()
	if st == null or city.walker != null or st.fines == null:
		_drive_t = 0.0
		return
	var day: int = st.fines.sim.day
	if day == _pursued_day or st.flags.get("gang_pursued_d%d" % day, false):
		return
	if str(st.cur.get("do", "")) != "drive" or st.cur.has("tail") or st._tail != null:
		_drive_t = 0.0
		return
	_drive_t += get_process_delta_time()
	if _drive_t < (5.0 if _test else 60.0):
		return
	_pursued_day = day
	st.flags["gang_pursued_d%d" % day] = true
	print("GANG the black sedan on day %d" % day)
	st._tail_start({"gap": 22.0, "chase": {"top": 21.0, "turn": 7.5, "lose": 110.0, "secs": 5.0, "flag": "gang_shaken_d%d" % day,
		"start": {"en": "(The black sedan. Again. Two cars back, not passing.)", "ta": "(கருப்பு செடான். மறுபடியும். ரெண்டு கார் பின்னாடி, முந்தாம.)"},
		"lost": {"en": "(Gone. For now.)", "ta": "(போயிடுச்சு. இப்போதைக்கு.)"}}})


# ---- testing ----
func _run_test(w: Node3D) -> void:
	var tree := get_tree()
	await tree.create_timer(2.5).timeout
	if watcher == null:
		return
	var cam := Camera3D.new()                            # from beside Karthik, toward him
	cam.fov = 45.0
	add_child(cam)
	var to: Vector3 = watcher.global_position - w.global_position
	to.y = 0.0
	cam.global_position = w.global_position + Vector3.UP * 1.6 - to.normalized() * 1.5 + to.normalized().cross(Vector3.UP) * 0.8
	cam.look_at(watcher.global_position + Vector3.UP * 1.2, Vector3.UP)
	var was := get_viewport().get_camera_3d()
	cam.make_current()
	await _snap("gang_watcher")
	print("GANG test: in the picture %s, %.0f m away" % [in_view(cam), to.length()])
	was.make_current()
	cam.queue_free()
	w.rotation.y = atan2(-to.x, -to.z)                   # Karthik turns and looks right at him
	if "_pitch" in w:
		w._pitch = -0.05
		w.head.rotation.x = -0.05
	var t := 0.0
	while watcher and not _leaving and t < 6.0:
		await tree.process_frame
		t += get_process_delta_time()
		w.rotation.y = atan2(-(watcher.global_position - w.global_position).x, -(watcher.global_position - w.global_position).z)
	print("GANG test: stared at for %.1f s, leaving %s" % [t, _leaving])
	await tree.create_timer(2.0).timeout
	await _snap("gang_leaving")
	await tree.create_timer(1.0).timeout
	tree.quit()


func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % n), 0.85)
