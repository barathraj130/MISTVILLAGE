extends Node3D
## People on the town pavements (Quaternius CC0/CC-BY animated characters, recoloured per person:
## South Indian skin tones, dark hair, everyday clothes). They walk the same road graph the cars
## and GPS use, on the pavement or the street edge, stand at shopfronts, chat in pairs and wave;
## more of them on busy main roads near shops, few on side streets, none out on the open highway.
## A recycled pool around the player keeps it cheap; nobody pops up in front of you.

const Prof := preload("res://scripts/drive/prof.gd")
const DIR := "res://assets/drive/people/"
const MODELS := ["man_casual", "man_farmer", "man_worker", "man_business", "man_beach", "man_hoodie",
	"woman_a", "woman_b", "woman_worker", "woman_suit"]
const POOL := 36
const NEAR := 120.0
const SPAWN_MIN := 35.0
const SPAWN_MAX := 95.0
const MAIN := ["trunk", "primary", "secondary", "tertiary"]
const SKIN := [Color(0.42, 0.27, 0.17), Color(0.36, 0.22, 0.13), Color(0.48, 0.32, 0.2), Color(0.3, 0.18, 0.11),
	Color(0.55, 0.38, 0.25), Color(0.4, 0.25, 0.16)]
const CLOTH := [Color(0.85, 0.85, 0.82), Color(0.15, 0.22, 0.45), Color(0.55, 0.1, 0.12), Color(0.12, 0.35, 0.25),
	Color(0.75, 0.55, 0.15), Color(0.45, 0.15, 0.4), Color(0.3, 0.3, 0.32), Color(0.85, 0.45, 0.1), Color(0.6, 0.75, 0.85),
	Color(0.9, 0.8, 0.6), Color(0.08, 0.08, 0.1), Color(0.7, 0.2, 0.35)]
const KEEP := ["Eye", "Eyebrows", "Black", "Gold", "Earrings", "Moustache", "Suit", "Tie"]

var graph
var player: Node3D
var people: Array = []
var _cum := {}
var _rng := RandomNumberGenerator.new()
var _scan := 0
var _mat_cache := {}


func build(g, p: Node3D) -> void:
	graph = g
	player = p
	_rng.randomize()
	var scenes := {}
	for m in MODELS:
		if ResourceLoader.exists(DIR + m + ".glb"):
			scenes[m] = load(DIR + m + ".glb")
	if scenes.is_empty():
		return
	var keys: Array = scenes.keys()
	for k in POOL:
		var model: String = keys[k % keys.size()]
		var node := (scenes[model] as PackedScene).instantiate() as Node3D
		node.visible = false
		add_child(node)
		var ap := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for a in ["CharacterArmature|Walk", "CharacterArmature|Idle", "CharacterArmature|Idle_Neutral", "CharacterArmature|Interact", "CharacterArmature|Wave"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		var h := _rng.randf_range(1.5, 1.66) if model.begins_with("woman") else _rng.randf_range(1.6, 1.78)
		node.scale = Vector3.ONE * (h / _model_height(node))
		_dress(node)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(m as MeshInstance3D).visibility_range_end = 110.0
		people.append({"node": node, "ap": ap, "meshes": meshes, "shadow": false, "si": -1, "fwd": true, "s": 0.0, "side": 1.0,
			"speed": _rng.randf_range(1.0, 1.45), "state": "walk", "timer": 0.0, "pos": Vector3.ZERO,
			"dir": Vector3.FORWARD, "edge": 1.2})


## Height of the rig in its own units, from the highest bone (head) with a little for the crown.
func _model_height(node: Node3D) -> float:
	var skel := node.find_children("*", "Skeleton3D", true, false)
	if skel.is_empty():
		return 1.7
	var sk := skel[0] as Skeleton3D
	var lo := INF
	var hi := -INF
	var to_root: Transform3D = node.global_transform.affine_inverse() * sk.global_transform
	for i in sk.get_bone_count():
		var y: float = (to_root * sk.get_bone_global_rest(i).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return maxf((hi - minf(lo, 0.0)) * 1.07, 0.01)


## Per-person colours: one skin tone for every skin surface, black hair, and fresh clothing colours.
func _dress(node: Node3D) -> void:
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var swaps := {}
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var name := mat.resource_name
			var col: Color
			if name.begins_with("Skin"):
				col = skin * (0.88 if name.contains("Darker") else 1.0)
			elif name.begins_with("Hair"):
				col = Color(0.05, 0.04, 0.035)
			elif name in KEEP:
				continue
			else:
				if not swaps.has(name):
					swaps[name] = CLOTH[_rng.randi() % CLOTH.size()]
				col = swaps[name]
			mi.set_surface_override_material(s, _variant(mat, col))


func _variant(base: BaseMaterial3D, col: Color) -> Material:
	var key := "%s|%s" % [base.resource_name, col.to_html()]
	if not _mat_cache.has(key):
		var m := base.duplicate() as BaseMaterial3D
		m.albedo_color = col
		m.roughness = 0.85
		_mat_cache[key] = m
	return _mat_cache[key]


# ----------------------------------------------------------------------------- behaviour
func _process(delta: float) -> void:
	if graph == null or player == null or people.is_empty():
		return
	var _p0 := Time.get_ticks_usec()
	_update(delta)
	Prof.add("pedestrians", _p0)


var _filled := false

func _update(delta: float) -> void:
	var pp := player.global_position
	if not _filled:
		# first frame (still behind the loading fade): fill the pavements around you
		_filled = true
		for q in people:
			_respawn(q, pp, true)
	_scan = (_scan + 1) % people.size()
	# only people close to you cast shadows (that's where grounding shows; far ones cost draw calls)
	var qs: Dictionary = people[(_scan * 7) % people.size()]
	var want: bool = qs["si"] >= 0 and qs["pos"].distance_to(pp) < 22.0
	if want != qs["shadow"]:
		qs["shadow"] = want
		for m in qs["meshes"]:
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q0: Dictionary = people[_scan]
	if q0["si"] < 0 or q0["pos"].distance_to(pp) > NEAR:
		_respawn(q0, pp)
	for q in people:
		if q["si"] < 0:
			continue
		q["timer"] -= delta
		match q["state"]:
			"walk":
				# stop for a car bearing down on us
				var rel: Vector3 = q["pos"] - pp
				var car_close := player.has_method("forward") and rel.length() < 7.0 and absf(player.get("speed")) > 1.5
				if car_close:
					_anim(q, "CharacterArmature|Idle", 1.0)
					continue
				q["s"] += q["speed"] * delta
				var cum := _lengths(q["si"])
				if q["s"] >= cum[cum.size() - 1]:
					if not _next_street(q):
						q["si"] = -1
						q["node"].visible = false
						continue
					q["s"] = 0.0
				_place(q)
				_anim(q, "CharacterArmature|Walk", q["speed"] / 1.25)
				if q["timer"] <= 0.0:
					q["timer"] = _rng.randf_range(8.0, 25.0)
					if _rng.randf() < 0.25:
						q["state"] = "pause"
						q["timer"] = _rng.randf_range(3.0, 9.0)
						# turn to face the shopfront (away from the road) or just look about
						var away: Vector3 = Vector3(q["dir"].z, 0, -q["dir"].x) * q["side"]
						q["node"].global_transform.basis = Basis.looking_at(-away, Vector3.UP).scaled(q["node"].scale)
			"pause":
				_anim(q, "CharacterArmature|Interact" if q["timer"] > 2.0 else "CharacterArmature|Idle_Neutral", 1.0)
				if q["timer"] <= 0.0:
					q["state"] = "walk"
					q["timer"] = _rng.randf_range(8.0, 25.0)
			"stand":
				_anim(q, q["idle_anim"], 1.0)


func _anim(q: Dictionary, name: String, speed: float) -> void:
	var ap: AnimationPlayer = q["ap"]
	if not ap.has_animation(name):
		name = "CharacterArmature|Idle"
	if ap.current_animation != name:
		ap.play(name, 0.25)
	ap.speed_scale = speed


func _next_street(q: Dictionary) -> bool:
	var st: Dictionary = graph.streets[q["si"]]
	var node: String = st["b"] if q["fwd"] else st["a"]
	if not graph.nodes.has(node) or graph.nodes[node]["kind"] in ["highway", "edge"]:
		q["fwd"] = not q["fwd"]                       # turn back rather than walk onto the highway
		return true
	var options: Array = []
	for si in graph.nodes[node]["edges"]:
		if si != q["si"] and not graph.streets[si]["class"] in ["trunk_link", "primary_link"]:
			options.append(si)
	if options.is_empty():
		q["fwd"] = not q["fwd"]
		return true
	var si: int = options[_rng.randi() % options.size()]
	q["si"] = si
	q["fwd"] = graph.streets[si]["a"] == node
	q["edge"] = _edge_offset(graph.streets[si])
	return true


func _edge_offset(st: Dictionary) -> float:
	# on the raised pavement of a main road, on the dirt edge of a side street
	return st["width"] * 0.5 + (1.3 if st["class"] in MAIN else 0.55)


func _respawn(q: Dictionary, pp: Vector3, anywhere := false) -> void:
	q["node"].visible = false
	q["si"] = -1
	var fwd: Vector3 = player.forward() if player.has_method("forward") else -player.global_basis.z
	for attempt in (12 if anywhere else 5):
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(8.0, 70.0) if anywhere else _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var at := pp + Vector3(cos(ang), 0, sin(ang)) * dist
		if not anywhere and (at - pp).normalized().dot(fwd) > 0.35:
			continue
		var ns: Array = graph.nearest_street(at)
		if ns[0] < 0 or ns[1] > 20.0:
			continue
		var st: Dictionary = graph.streets[ns[0]]
		var busy: float = 0.9 if st["class"] in MAIN else 0.35
		if _rng.randf() > busy:
			continue
		q["si"] = ns[0]
		q["fwd"] = _rng.randf() < 0.5
		q["side"] = 1.0 if _rng.randf() < 0.5 else -1.0
		q["edge"] = _edge_offset(st)
		var cum := _lengths(ns[0])
		q["s"] = _rng.randf() * cum[cum.size() - 1]
		var roll := _rng.randf()
		if roll < 0.18:
			q["state"] = "stand"                     # waiting, chatting, watching the street
			q["idle_anim"] = "CharacterArmature|Wave" if roll < 0.03 else ("CharacterArmature|Idle_Neutral" if roll < 0.1 else "CharacterArmature|Idle")
		else:
			q["state"] = "walk"
		q["timer"] = _rng.randf_range(5.0, 20.0)
		_place(q)
		var crowded := false
		for o in people:
			if o != q and o["si"] >= 0 and o["pos"].distance_to(q["pos"]) < 1.6:
				crowded = true
				break
		if crowded:
			q["si"] = -1
			continue
		if q["state"] == "stand":
			var face: Vector3 = Vector3(q["dir"].z, 0, -q["dir"].x) * -q["side"]
			if _rng.randf() < 0.5:
				face = q["dir"]
			q["node"].global_transform.basis = Basis.looking_at(-face, Vector3.UP).scaled(q["node"].scale)
		q["node"].visible = true
		return


func _place(q: Dictionary) -> void:
	var st: Dictionary = graph.streets[q["si"]]
	var pts: PackedVector3Array = st["pts"]
	var cum := _lengths(q["si"])
	var total: float = cum[cum.size() - 1]
	var s: float = clampf(q["s"], 0.0, total)
	var u: float = s if q["fwd"] else total - s
	var k := clampi(cum.bsearch(u) - 1, 0, pts.size() - 2)
	var t: float = (u - cum[k]) / maxf(cum[k + 1] - cum[k], 0.001)
	var p := pts[k].lerp(pts[k + 1], t)
	var dir := (pts[k + 1] - pts[k]) * (1.0 if q["fwd"] else -1.0)
	dir = Vector3(dir.x, 0, dir.z).normalized()
	if dir != Vector3.ZERO:
		q["dir"] = dir
	var side: Vector3 = Vector3(q["dir"].z, 0, -q["dir"].x) * float(q["side"])
	var lift := 0.17 if st["class"] in MAIN else 0.0
	p += side * q["edge"] + Vector3(0, lift, 0)
	q["pos"] = p
	q["node"].global_transform = Transform3D(Basis.looking_at(-q["dir"], Vector3.UP).scaled(q["node"].scale), p)


func _lengths(si: int) -> PackedFloat32Array:
	if _cum.has(si):
		return _cum[si]
	var pts: PackedVector3Array = graph.streets[si]["pts"]
	var cum := PackedFloat32Array([0.0])
	for k in pts.size() - 1:
		cum.append(cum[k] + pts[k].distance_to(pts[k + 1]))
	_cum[si] = cum
	return cum
