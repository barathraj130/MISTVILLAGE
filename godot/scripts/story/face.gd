extends RefCounted
## A character's face, for a model with MakeHuman's expression units as blend shapes (tools/humans/story_cast.py
## face_rig: Karthik): every mesh that has a unit (the skin, brows, lashes, teeth, tongue) is set together, so a blink
## closes the lashes with the lids and the jaw takes the lower teeth.
##   put(unit, v)       one unit (0–1) on all of them
##   pose({unit: v})    eased towards these values (others back to 0) by update()
##   update(dt)         eases, and blinks now and then (every 2–6 s, a fifth of a second; sometimes twice)

var _meshes: Array = []                 # [MeshInstance3D, {unit: blend shape index}]
var _now := {}
var _want := {}
var _blink_in := 2.0
var _blink_t := -1.0
var _double := false
var speed := 8.0                        # how quickly an expression comes (1/s)


func _init(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or not m is ArrayMesh:
			continue
		var idx := {}
		for i in (m as ArrayMesh).get_blend_shape_count():
			idx[str((m as ArrayMesh).get_blend_shape_name(i))] = i
		if not idx.is_empty():
			_meshes.append([mi, idx])


func has_face() -> bool:
	return not _meshes.is_empty()


func put(unit: String, v: float) -> void:
	for e in _meshes:
		if (e[1] as Dictionary).has(unit):
			(e[0] as MeshInstance3D).set_blend_shape_value(e[1][unit], v)


func pose(p: Dictionary) -> void:
	_want = p


func update(dt: float) -> void:
	var units := {}
	for u in _now:
		units[u] = true
	for u in _want:
		units[u] = true
	for u in units:
		if u.begins_with("eye-") and u.ends_with("-closure"):
			continue
		var v: float = lerpf(float(_now.get(u, 0.0)), float(_want.get(u, 0.0)), 1.0 - exp(-dt * speed))
		_now[u] = v
		put(u, v)
	# the blink: down fast, up a little slower
	_blink_in -= dt
	if _blink_in <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_double = randf() < 0.15
	var lid: float = maxf(float(_want.get("eye-left-closure", 0.0)), 0.0)
	if _blink_t >= 0.0:
		_blink_t += dt
		var t := _blink_t / 0.2
		lid = maxf(lid, sin(clampf(t, 0.0, 1.0) * PI))
		if t >= 1.0:
			_blink_t = 0.0 if _double else -1.0
			if _double:
				_double = false
			else:
				_blink_in = randf_range(2.0, 6.0)
	put("eye-left-closure", lid)
	put("eye-right-closure", lid)
