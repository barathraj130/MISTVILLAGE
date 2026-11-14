extends Node
## The streets' connectivity, measured on the real collision (the road, kerb, footpath and building brief): along every
## road of the loaded tiles, every 8 m, a cross-section of rays down from above, from the road's middle out past each
## edge (0.25 m apart, to the road's half-width + 7 m), and what a person or a car would meet:
##   hole       a point on the road with nothing under it (or far below it)
##   uneven     the road across its width more than 0.25 m out of level (a lip, a seam)
##   step       a rise at the road's edge Karthik can't step up (> 0.35 m) with no lower way within 6 m along
##   trench     a dip behind the footpath, more than 0.3 m below it, before the wall (a slot to fall into)
##   no_ground  nothing under a point beside the road (a hole to the void)
## Printed per kind, with where; the worst of each pictured (user://audit_<kind>_<n>.jpg). Spots: --auditat=x,z;...
## (default: where the city starts and three more round Gandhipuram). Development only.
##   --streetaudit
const STEP := 0.35                    # player.gd STEP_HEIGHT

var city
var found := {"hole": [], "uneven": [], "step": [], "trench": [], "no_ground": []}
var sections := 0


func _ready() -> void:
	_run.call_deferred()


func _ray(x: float, z: float, y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y + 30.0, z), Vector3(x, y - 12.0, z))
	if city.car:
		q.exclude = [city.car.get_rid()]
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else NAN


func _run() -> void:
	var tree := get_tree()
	var spots: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auditat="):
			for s in a.get_slice("=", 1).split(";"):
				var v := s.split(",")
				spots.append(Vector2(float(v[0]), float(v[1])))
	if spots.is_empty():
		spots = [Vector2.ZERO, Vector2(400, 0), Vector2(0, 400), Vector2(-400, -300)]
	await tree.create_timer(10.0).timeout
	var done := {}
	for sp in spots:
		city.streamer.target = null
		city.car.freeze = true
		city.car.global_position = Vector3(sp.x, 600.0, sp.y)
		city.streamer.target = city.car
		await tree.create_timer(6.0).timeout             # (the tiles round it load)
		for k in city.streamer.loaded:
			if done.has(k):
				continue
			done[k] = true
			for r in (city.streamer.loaded[k] as Node3D).get_meta("roads", []):
				if r.get("fly", false):
					continue
				_road(r)
				if sections % 200 == 0:
					await tree.process_frame
	var lines := ["AUDIT %d cross-sections over %d tiles" % [sections, done.size()]]
	for kind in found:
		var arr: Array = found[kind]
		lines.append("AUDIT %-9s %5d (%.1f%%)%s" % [kind, arr.size(), 100.0 * arr.size() / maxf(sections, 1.0),
			("  e.g. " + ", ".join(arr.slice(0, 4).map(func(e): return "%.0f,%.0f (%s)" % [e[0].x, e[0].z, e[1]]))) if not arr.is_empty() else ""])
	for l in lines:
		print(l)
	var f := FileAccess.open(ProjectSettings.globalize_path("user://street_audit.json"), FileAccess.WRITE)
	if f:
		var out := {}
		for kind in found:
			out[kind] = (found[kind] as Array).map(func(e): return [e[0].x, e[0].y, e[0].z, e[1]])
		f.store_string(JSON.stringify(out))
	for kind in found:                                   # the worst of each, pictured
		var arr: Array = found[kind]
		arr.sort_custom(func(a, b): return float(a[2]) > float(b[2]))
		for i in mini(2, arr.size()):
			await _picture(arr[i][0], arr[i][3], "audit_%s_%d" % [kind, i])
	tree.quit()


## One road: a cross-section every 8 m along it.
func _road(r: Dictionary) -> void:
	var p: PackedFloat32Array = r["p"]
	var hw := float(r.get("w", 6.0)) * 0.5
	var n := p.size() / 3
	var carry := 0.0
	for i in n - 1:
		var a := Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
		var b := Vector3(p[i * 3 + 3], p[i * 3 + 4], p[i * 3 + 5])
		var seg := a.distance_to(b)
		if seg < 0.1:
			continue
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var side := Vector3(d.z, 0.0, -d.x)
		var s := 8.0 - carry
		while s < seg:
			var c := a.lerp(b, s / seg)
			if s > 6.0 and s < seg - 6.0:                 # (not in a junction's mouth: the other roads cross there)
				_section(c, d, side, hw)
			s += 8.0
		carry = seg - (s - 8.0)


func _section(c: Vector3, along: Vector3, side: Vector3, hw: float) -> void:
	sections += 1
	var mid := _ray(c.x, c.z, c.y)
	if is_nan(mid) or absf(mid - c.y) > 1.5:
		found["hole"].append([c, "mid %s" % ("none" if is_nan(mid) else "%.1f m off" % (mid - c.y)), 9.0, along])
		return
	var lo := mid
	var hi := mid
	for sg in [-1.0, 1.0]:
		var prof := []
		var x := 0.25
		while x <= hw + 7.0:
			var q: Vector3 = c + side * (sg * x)
			prof.append([x, _ray(q.x, q.z, c.y)])
			x += 0.25
		var at_edge := 0.0
		for e in prof:
			var ex: float = e[0]
			var ey: float = e[1]
			if ex < hw - 0.3:                            # on the road
				if is_nan(ey):
					found["hole"].append([c + side * (sg * ex), "road %.2f m from the middle" % ex, 8.0, along])
					return
				lo = minf(lo, ey)
				hi = maxf(hi, ey)
		if hi - lo > 0.25:
			found["uneven"].append([c, "%.2f m across" % (hi - lo), hi - lo, along])
		# the edge: from the road's edge out, the first rise, and whether it's a wall or a step
		var prev := mid
		var rose := false
		var foot := NAN
		for e in prof:
			var ex: float = e[0]
			var ey: float = e[1]
			if ex < hw - 0.3:
				prev = ey if not is_nan(ey) else prev
				continue
			if is_nan(ey):
				found["no_ground"].append([c + side * (sg * ex), "%.1f m out" % ex, 1.0, along])
				break
			var rise := ey - prev
			if not rose and rise > STEP and rise < 2.0 and ex < hw + 2.5:   # (a kerb or footpath edge too high to step)
				found["step"].append([c + side * (sg * ex), "%.2f m up" % rise, rise, along])
				rose = true
				foot = ey
			elif not rose and rise > 0.08 and rise <= STEP and ex < hw + 2.5:
				rose = true
				foot = ey
			elif rose and not is_nan(foot) and foot - ey > 0.3 and ey > foot - 2.0:   # behind the footpath, a dip
				found["trench"].append([c + side * (sg * ex), "%.2f m down" % (foot - ey), foot - ey, along])
				break
			elif rise > 2.0:                              # (a wall: the footpath's end)
				break
			prev = ey


func _picture(at: Vector3, along: Vector3, name: String) -> void:
	city.car.freeze = true
	city.car.global_position = at + Vector3(0, 600.0 - at.y, 0)
	await get_tree().create_timer(2.5).timeout
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	var side := Vector3(along.z, 0.0, -along.x)
	cam.global_position = at - along * 6.0 + side * 2.0 + Vector3.UP * 2.2
	cam.look_at(at + Vector3.UP * 0.2, Vector3.UP)
	cam.make_current()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % name), 0.85)
	cam.queue_free()
