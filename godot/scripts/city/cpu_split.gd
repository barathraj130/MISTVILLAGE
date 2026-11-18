extends Node
## (testing) --cpusplit[=x,z]: where the frame's CPU goes that the scripts' own timers (Prof, the PROF line) don't see:
## the engine's work per node kind. The car set down at x,z (default: where it is), then for each kind three times
## off and on, three seconds each, the median frame's process and physics time compared ("CPUSPLIT" lines):
##   anim       every AnimationMixer (AnimationPlayer, AnimationTree) paused: the people's clips not advanced
##   modifiers  every SkeletonModifier3D off (the IK: rider_ik, foot IK, arm IK, look-at)
##   skeletons  every Skeleton3D hidden (with its meshes: skinning and pose updates skipped)
##   scripts    every scripted node's _process and _physics_process off (as --profsweep, all at once)
## Counts of each kind printed first.

var city
var _xz := Vector2.INF
var _kinds := ["anim", "modifiers", "skeletons", "scripts"]
var _win := 2.5
var _reps := 3


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cpusplit="):
			var p := a.get_slice("=", 1).split(",")
			_xz = Vector2(float(p[0]), float(p[1]))
		if a.begins_with("--cpukinds="):                 # (just these kinds, longer windows: e.g. shadows)
			_kinds = Array(a.get_slice("=", 1).split(","))
			_win = 8.0
			_reps = 4
	_run.call_deferred()


func _median(secs: float) -> Vector2:
	var tree := get_tree()
	var pr: Array = []
	var ph: Array = []
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	await tree.process_frame
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
		pr.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	pr.sort()
	ph.sort()
	return Vector2(pr[pr.size() / 2], ph[ph.size() / 2]) if not pr.is_empty() else Vector2.ZERO


func _nodes(kind: String) -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "", true, false):
		match kind:
			"anim":
				if n is AnimationMixer and (n as AnimationMixer).active:
					out.append(n)
			"modifiers":
				if n is SkeletonModifier3D and (n as SkeletonModifier3D).active:
					out.append(n)
			"skeletons":
				if n is Skeleton3D and (n as Node3D).is_visible_in_tree():
					out.append(n)
			"scripts":
				if n.get_script() != null and n != self and n != city and (n.is_processing() or n.is_physics_processing()):
					out.append(n)
			"shadows":
				if n is Light3D and (n as Light3D).shadow_enabled:
					out.append(n)
	return out


func _toggle(kind: String, nodes: Array, on: bool, was: Dictionary) -> void:
	for n in nodes:
		if not is_instance_valid(n):
			continue
		match kind:
			"anim", "modifiers":
				n.active = on
			"shadows":
				n.shadow_enabled = on
			"skeletons":
				n.visible = on
			"scripts":
				if not on:
					was[n] = [n.is_processing(), n.is_physics_processing()]
					n.set_process(false)
					n.set_physics_process(false)
				elif was.has(n):
					n.set_process(was[n][0])
					n.set_physics_process(was[n][1])


func _run() -> void:
	var tree := get_tree()
	await tree.create_timer(12.0).timeout
	if _xz != Vector2.INF:
		var car = city.car
		car.freeze = true
		car.global_position = Vector3(_xz.x, 500.0, _xz.y)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 25000:
			if city.streamer.loaded.size() >= 9 and city.streamer.pending.is_empty():
				break
			await tree.create_timer(0.5).timeout
		var g: float = city.streamer.height_at(_xz.x, _xz.y)
		car.global_position = Vector3(_xz.x, (g if not is_nan(g) else 400.0) + 0.6, _xz.y)
		car.freeze = false
		car.linear_velocity = Vector3.ZERO
	await tree.create_timer(20.0).timeout                  # (the people round him given out, walking)
	if "census" in _kinds:                               # (what's drawn: visible meshes near the camera, by owner)
		_census()
		tree.quit()
		return
	for kind in _kinds:
		print("CPUSPLIT count %-10s %d" % [kind, _nodes(kind).size()])
	var all := await _median(4.0)
	print("CPUSPLIT all on: process %.1f ms, physics %.1f ms, fps %d" % [all.x, all.y, Engine.get_frames_per_second()])
	for kind in _kinds:
		var d: Array = []
		for rep in _reps:
			var base := await _median(_win)
			var draws0 := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var nodes := _nodes(kind)
			var was := {}
			_toggle(kind, nodes, false, was)
			await tree.create_timer(0.3).timeout
			var off := await _median(_win)
			print("CPUSPLIT %s draws on %d, off %d" % [kind, int(draws0), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
			_toggle(kind, nodes, true, was)
			await tree.create_timer(0.3).timeout
			d.append(base - off)
		d.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
		print("CPUSPLIT %-10s saves process %5.1f ms, physics %5.1f ms (runs: %s)" % [kind, d[d.size() / 2].x, d[d.size() / 2].y,
			", ".join(d.map(func(v): return "%.1f/%.1f" % [v.x, v.y]))])
	tree.quit()


## The visible mesh instances within 400 m of the camera (a draw each per surface), grouped by what owns them: the
## nearest ancestor with a recognisable name (a tile's group, a vehicle, a person). Surfaces summed.
func _census() -> void:
	var cam := get_viewport().get_camera_3d()
	var groups := {}
	var total_s := 0
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var aabb := g.get_aabb()
		var centre := g.global_transform * aabb.get_center()
		var reach := aabb.size.length() * 0.5
		var dcam := centre.distance_to(cam.global_position)
		if g.visibility_range_end > 0.0 and dcam - reach > g.visibility_range_end:
			continue                                     # (past its visibility range: not drawn)
		if dcam - reach > cam.far:
			continue
		var surf := 1
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			surf = (g as MeshInstance3D).mesh.get_surface_count()
		var key := ""
		var a: Node = g
		var path: Array = []
		while a and a != get_tree().root:
			path.append(String(a.name))
			a = a.get_parent()
		path.reverse()
		key = "/".join(path.slice(0, mini(path.size(), 3))) + " · " + String(g.name).rstrip("0123456789@").substr(0, 20)
		key = key.substr(0, 60)
		if g is MultiMeshInstance3D:
			var mmi := g as MultiMeshInstance3D
			var mn := "?"
			if mmi.multimesh and mmi.multimesh.mesh:
				mn = mmi.multimesh.mesh.resource_path.get_file() if mmi.multimesh.mesh.resource_path != "" else mmi.multimesh.mesh.resource_name
				surf = mmi.multimesh.mesh.get_surface_count()
				if mmi.multimesh.visible_instance_count == 0 or mmi.multimesh.instance_count == 0:
					continue
			var mk := "mm " + (String(mmi.get_meta("kind", "")) if mmi.has_meta("kind") else "") + " " + mn.substr(0, 30) + " vis_end %d" % int(mmi.visibility_range_end)
			var em: Array = groups.get(mk, [0, 0])
			em[0] += 1
			em[1] += surf
			groups[mk] = em
			total_s += surf
			continue
		var e: Array = groups.get(key, [0, 0])
		e[0] += 1
		e[1] += surf
		groups[key] = e
		total_s += surf
	var top := {}                                        # (and summed by system: the first two levels)
	for k in groups:
		var t2 := "/".join(String(k).split("/").slice(0, 2)).get_slice(" · ", 0) + " · " + String(k).get_slice(" · ", 1).get_slice(" [", 0) + (" [multimesh]" if String(k).ends_with("[multimesh]") else "")
		var e2: Array = top.get(t2, [0, 0])
		e2[0] += groups[k][0]
		e2[1] += groups[k][1]
		top[t2] = e2
	for k in top:
		print("CPUSPLIT system %5d surfaces %5d instances  %s" % [top[k][1], top[k][0], k])
	var keys := groups.keys()
	keys.sort_custom(func(x, y): return groups[x][1] > groups[y][1])
	print("CPUSPLIT census: %d surfaces within 400 m (draws in frame %d)" % [total_s, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	for k in keys.slice(0, 30):
		print("CPUSPLIT census %5d surfaces %5d instances  %s" % [groups[k][1], groups[k][0], k])

