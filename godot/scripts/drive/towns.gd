extends Node3D
## Open-world towns (Coimbatore, Mettupalayam, Kotagiri) from towns.json, compiled from
## OpenStreetMap by tools/towns.py: every street as drivable asphalt, every building footprint
## raised into a painted building (one shared facade shader draws windows, shutters and
## shop signs), and landmark names floating over bus stands, temples and markets.
## Meshes and collision are grouped into 256 m tiles.

const MB := preload("res://scripts/drive/mesh_builder.gd")
const StreetLife := preload("res://scripts/drive/street_life.gd")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const TILE := 256.0
const FLOOR := 3.2
const RANK := {"trunk": 0.07, "primary": 0.06, "secondary": 0.05, "tertiary": 0.04, "unclassified": 0.03,
	"residential": 0.025, "living_street": 0.02, "service": 0.015, "road": 0.02, "pedestrian": 0.015}
const MARKED := ["trunk", "primary", "secondary", "tertiary"]
const POI_COLOURS := {"Bus stand": Color(0.2, 0.55, 1.0), "Temple": Color(1.0, 0.55, 0.1), "Market": Color(0.9, 0.3, 0.6),
	"Railway station": Color(0.6, 0.4, 1.0), "Hospital": Color(1.0, 0.25, 0.25), "Petrol bunk": Color(0.2, 0.8, 0.3)}

var data := {}
var mat_road: Material
var mat_lines: StandardMaterial3D
var mat_building: ShaderMaterial
var body: StaticBody3D
var pois: Array = []                      # {name, kind, pos, town}
var parked := 0
var lives: Array = []                     # street_life.gd per town (parked vehicles you can take)
var bunks: Array = []                     # fuel forecourts: {name, pos, town}
var bunk_lights: Array = []
var lamp_mat: StandardMaterial3D           # streetlight heads: glow after dusk
var pool_mat: StandardMaterial3D           # the pools of light they throw on the road
var _pools: Array = []
var highway_gap: Callable
var graph                                 # road_graph.gd: built here from towns.json, shared with GPS etc.                 # (Vector3) -> metres to the main road's centreline


func build(path: String, asphalt: Material, progress: Callable) -> void:
	if not FileAccess.file_exists(path):
		return
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if graph:
		var tg := Time.get_ticks_msec()
		graph.build(graph.route, data)
		if "--trace" in OS.get_cmdline_user_args(): print("  TOWN graph %d ms" % (Time.get_ticks_msec() - tg))
	mat_road = asphalt
	mat_lines = MB.vertex_color_material(0.6)
	mat_building = ShaderMaterial.new()
	mat_building.shader = BUILDING_SHADER
	body = StaticBody3D.new()
	body.name = "TownCollision"
	add_child(body)
	var names := data.keys()
	for i in names.size():
		var tw: Dictionary = data[names[i]]
		progress.call("Building %s" % names[i], float(i) / names.size())
		await get_tree().process_frame
		var tr := "--trace" in OS.get_cmdline_user_args()
		var t0 := Time.get_ticks_msec()
		_streets(names[i], tw["streets"])
		if tr: print("  TOWN %s streets %d ms" % [names[i], Time.get_ticks_msec() - t0])
		await get_tree().process_frame
		t0 = Time.get_ticks_msec()
		_buildings(names[i], tw["buildings"])
		if tr: print("  TOWN %s buildings %d ms" % [names[i], Time.get_ticks_msec() - t0])
		t0 = Time.get_ticks_msec()
		_rooftops(names[i], tw["buildings"])
		_utilities(names[i], tw["streets"])
		if tr: print("  TOWN %s utilities %d ms" % [names[i], Time.get_ticks_msec() - t0])
		t0 = Time.get_ticks_msec()
		var shops: Array = []
		for b in tw["buildings"]:
			if b.get("shop", false):
				shops.append(Vector2(b["poly"][0][0], b["poly"][0][1]))
		var life := StreetLife.new()
		life.name = "%sParked" % names[i]
		add_child(life)
		parked += life.build(names[i], tw["streets"], graph, body, shops)
		lives.append(life)
		if tr: print("  TOWN %s parked %d ms" % [names[i], Time.get_ticks_msec() - t0])
		_fuel_bunks(names[i], tw)
		_pois(names[i], tw["pois"])


func set_wet(w: float) -> void:
	for k in _edge_mats:
		var m: StandardMaterial3D = _edge_mats[k]
		m.roughness = lerpf(0.9, 0.45, w)
		m.albedo_color = Color.WHITE * lerpf(1.0, 0.75, w)


func set_night(v: float) -> void:
	if mat_building:
		mat_building.set_shader_parameter("night", v)
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 4.0 * smoothstep(0.3, 0.7, v)
	if pool_mat:
		pool_mat.albedo_color = Color(1.0, 0.78, 0.5, 0.8 * smoothstep(0.35, 0.75, v))
		for p in _pools:
			p.visible = v > 0.35
	for l in bunk_lights:
		(l as OmniLight3D).light_energy = 3.0 * smoothstep(0.3, 0.7, v)
		(l as OmniLight3D).visible = v > 0.3


func _tile(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


# ----------------------------------------------------------------------------- streets
func _streets(town: String, streets: Array) -> void:
	var ts0 := Time.get_ticks_msec()
	var roads := {}
	var lines := {}
	var walks := {}                            # kerbs, drains and sidewalks (concrete)
	var verges := {}                           # gravel shoulders on small streets
	for s in streets:
		var raw: Array = s["pts"]
		var n := raw.size()
		if n < 2:
			continue
		var pts := PackedVector3Array()
		for q in raw:
			pts.append(Vector3(q[0], q[1] + RANK.get(s["class"], 0.02), q[2]))
		var half: float = float(s["width"]) * 0.5
		var joined: bool = graph != null and graph.has_graph()
		if not joined:
			# old map data: nudge the ends out a little so they close the gap at junctions
			pts[0] += (pts[0] - pts[1]).normalized() * 1.2
			pts[n - 1] += (pts[n - 1] - pts[n - 2]).normalized() * 1.2
		# lane paint stops short of a junction instead of running through it
		var clear_a: float = half * 2.2 if joined and graph.is_junction(s.get("a", "")) else 0.0
		var clear_b: float = half * 2.2 if joined and graph.is_junction(s.get("b", "")) else 0.0
		var total := 0.0
		for i in n - 1:
			total += pts[i].distance_to(pts[i + 1])
		var key := _tile(pts[n / 2])
		if not roads.has(key):
			roads[key] = MB.new()
			lines[key] = MB.new()
			walks[key] = MB.new()
			verges[key] = MB.new()
		var mb = roads[key]
		var lm = lines[key]
		var wm = walks[key]
		var vm = verges[key]
		var main: bool = s["class"] in MARKED or s["class"] == "trunk_link" or s["class"] == "primary_link"
		var edge_a := clear_a if clear_a > 0.0 else 0.0
		var edge_b := clear_b if clear_b > 0.0 else 0.0
		if joined and graph.nodes.has(s.get("a", "")) and graph.nodes[s["a"]]["kind"] == "highway":
			edge_a = 4.0 / 0.7
		if joined and graph.nodes.has(s.get("b", "")) and graph.nodes[s["b"]]["kind"] == "highway":
			edge_b = 4.0 / 0.7
		var dist := 0.0
		var marked: bool = s["class"] in MARKED
		for i in n - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ta := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
			var tb := (pts[mini(i + 2, n - 1)] - pts[i])
			var la := Vector3(ta.z, 0, -ta.x).normalized()
			var lb := Vector3(tb.z, 0, -tb.x).normalized()
			var seg := a.distance_to(b)
			mb.quad(a + la * half, a - la * half, b - lb * half, b + lb * half, Color.WHITE, Vector3.UP,
				Vector2(0, dist / 6.0), Vector2(half / 3.0, dist / 6.0), Vector2(half / 3.0, (dist + seg) / 6.0),
				Vector2(0, (dist + seg) / 6.0))
			# edges in 6 m pieces (every other segment): plenty on a 3 m polyline, half the geometry
			if i % 2 == 0 and dist > edge_a * 0.7 and dist + seg * 2.0 < total - edge_b * 0.7:
				var j := mini(i + 2, n - 1)
				var b2 := pts[j]
				var tj := pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)]
				var lj := Vector3(tj.z, 0, -tj.x).normalized()
				for side in [1.0, -1.0]:
					if main:
						# drain channel, kerb and a raised pavement, like a city main road
						_strip(wm, a, b2, la * side, lj * side, half, half + 0.45, -0.12, -0.12, Color(0.32, 0.31, 0.29), 2)
						_strip(wm, a, b2, la * side, lj * side, half + 0.45, half + 0.7, 0.16, 0.16, Color(0.78, 0.77, 0.73) if i % 4 == 0 or s["class"] == "tertiary" else Color(0.12, 0.12, 0.12), 0)
						_strip(wm, a, b2, la * side, lj * side, half + 0.7, half + 1.9, 0.15, 0.15, Color(0.66, 0.63, 0.58), 3)
					else:
						_strip(vm, a, b2, la * side, lj * side, half - 0.05, half + 1.0, -0.01, -0.06, Color(0.52, 0.47, 0.40))
			if marked and fmod(dist, 8.0) < 4.0 and dist > clear_a and dist + seg < total - clear_b:
				var up := Vector3(0, 0.015, 0)
				lm.quad(a + la * 0.06 + up, a - la * 0.06 + up, b - lb * 0.06 + up, b + lb * 0.06 + up,
					Color(0.8, 0.8, 0.76), Vector3.UP)
			dist += seg
	var tj0 := Time.get_ticks_msec()
	if graph and graph.has_graph():
		_junctions(town, roads, walks, verges)
	var tj1 := Time.get_ticks_msec()
	if "--trace" in OS.get_cmdline_user_args():
		print("    streets: polylines %d ms, junctions %d ms" % [tj0 - ts0, tj1 - tj0])
	for key in roads:
		var mi := MeshInstance3D.new()
		mi.name = "%sStreets_%d_%d" % [town, key.x, key.y]
		mi.mesh = roads[key].commit()
		mi.material_override = mat_road
		mi.visibility_range_end = 900.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		for pair in [[walks, "concrete", 2.0, true], [verges, "gravel", 1.5, false]]:
			var emb = pair[0][key]
			if emb.is_empty():
				continue
			var em := MeshInstance3D.new()
			em.name = "%s%s_%d_%d" % [town, "Pavements" if pair[3] else "Shoulders", key.x, key.y]
			em.mesh = emb.commit()
			em.material_override = _edge_mat(pair[1], pair[2])
			em.visibility_range_end = 450.0
			em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(em)
			if pair[3]:
				var ecs := CollisionShape3D.new()
				ecs.shape = em.mesh.create_trimesh_shape()
				body.add_child(ecs)
		if not lines[key].is_empty():
			var li := MeshInstance3D.new()
			li.mesh = lines[key].commit()
			li.material_override = mat_lines
			li.visibility_range_end = 300.0
			li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(li)


var _edge_mats := {}

func _edge_mat(key: String, tile: float) -> Material:
	if not _edge_mats.has(key):
		_edge_mats[key] = MB.cc0_material(key, tile, 0.9)
	return _edge_mats[key]


## A strip beside a street segment from offset o0 to o1 (metres from the centreline, along the
## side vectors sa/sb), top at h0 → h1 above the road. `walls`: 0 none (shoulder), 1 kerb face
## towards the road, 2 drain (walls down from the road and up to the kerb), 3 outer edge down.
func _strip(mb, a: Vector3, b: Vector3, sa: Vector3, sb: Vector3, o0: float, o1: float, h0: float, h1: float,
		col: Color, walls := 0) -> void:
	var a0 := a + sa * o0 + Vector3(0, h0, 0)
	var a1 := a + sa * o1 + Vector3(0, h1, 0)
	var b0 := b + sb * o0 + Vector3(0, h0, 0)
	var b1 := b + sb * o1 + Vector3(0, h1, 0)
	mb.quad(a0, a1, b1, b0, col, Vector3.UP)
	match walls:
		1:
			mb.quad(a + sa * o0, a0, b0, b + sb * o0, col * 0.9, -sa)
		2:
			mb.quad(a + sa * o0, a0, b0, b + sb * o0, col * 0.7, sa)
			mb.quad(a1, a + sa * o1 + Vector3(0, 0.16, 0), b + sb * o1 + Vector3(0, 0.16, 0), b1, col * 0.7, -sa)
		3:
			mb.quad(a1, a + sa * o1 + Vector3(0, -0.25, 0), b + sb * o1 + Vector3(0, -0.25, 0), b1, col * 0.85, sa)


## One continuous asphalt surface where streets meet: a disc (a half disc where a street joins
## the highway) fitted to the meeting streets' slope, laid just above them so their overlapping
## ends and edges disappear under it.
func _junctions(town: String, roads: Dictionary, walks: Dictionary = {}, verges: Dictionary = {}) -> void:
	for id in graph.nodes:
		var nd: Dictionary = graph.nodes[id]
		if not graph.is_junction(id):
			continue
		var edges: Array = nd["edges"]
		if edges.is_empty() or graph.streets[edges[0]]["town"] != town:
			continue
		var c: Vector3 = nd["pos"]
		var r := 0.0
		var lift := 0.0
		var samples: Array = [c]
		for si in edges:
			var st: Dictionary = graph.streets[si]
			r = maxf(r, st["width"] * 0.5 + 1.2)
			lift = maxf(lift, RANK.get(st["class"], 0.02))
		for si in edges:
			samples.append(_along(graph.streets[si], id, r))
		var out := Vector3.ZERO
		if nd["kind"] == "highway":
			var rp: Vector3 = graph.route.pts[nd["route_i"]]
			samples.append(rp)
			out = Vector3(c.x - rp.x, 0, c.z - rp.z).normalized()
		# least-squares plane y = a + b·dx + c·dz through the samples; where a street meets the
		# highway the patch lies flat at the highway's level instead (no hump onto the carriageway)
		var plane := _fit_plane(c, samples)
		if nd["kind"] == "highway":
			plane = Vector3(c.y, 0.0, 0.0)
			lift = 0.02
		var key := _tile(c)
		if not roads.has(key):
			roads[key] = MB.new()
		if not walks.has(key):
			walks[key] = MB.new()
			verges[key] = MB.new()
		var mb = roads[key]
		if not walks.is_empty():
			var hw_arms: Array = []
			if nd["kind"] == "highway":
				# the highway as two arms running away along its edge (its shoulder line sits
				# HALF + shoulder from the centre, the node 3.2 m from it)
				var ri: int = nd["route_i"]
				var tan: Vector3 = graph.route.tangents[ri]
				tan = Vector3(tan.x, 0, tan.z).normalized()
				for sgn in [1.0, -1.0]:
					hw_arms.append({"dir": tan * sgn, "half": 1.8, "main": false, "hw": true, "clear": 7.0,
						"ang": atan2(tan.z * sgn, tan.x * sgn)})
			_corners(id, c, plane, lift, walks[key], verges[key], hw_arms)
		var segs := 20
		var ring: Array = []
		for k in segs + 1:
			var ang := TAU * k / segs
			var dir := Vector3(cos(ang), 0, sin(ang))
			var rr := r
			if out != Vector3.ZERO and dir.dot(out) < 0.0:
				rr = r * lerpf(1.0, 0.25, minf(-dir.dot(out) * 1.6, 1.0))   # stay off the highway lanes
			var q := c + dir * rr
			q.y = plane.x + plane.y * (q.x - c.x) + plane.z * (q.z - c.z) + lift + 0.012
			ring.append(q)
		var cy: float = plane.x + lift + 0.012
		var cc := Vector3(c.x, cy, c.z)
		for k in segs:
			var a: Vector3 = ring[k]
			var b: Vector3 = ring[k + 1]
			mb.tri(cc, a, b, Color.WHITE, Vector3.UP, Vector2(cc.x, cc.z) / 6.0, Vector2(a.x, a.z) / 6.0, Vector2(b.x, b.z) / 6.0)


## Rounded corners between neighbouring streets at a junction: the drain, kerb and pavement (or a
## dirt edge on small streets) sweep round from one street's footpath to the next, as built.
func _corners(id: String, c: Vector3, plane: Vector3, lift: float, wm, vm, extra_arms: Array = []) -> void:
	var arms: Array = extra_arms.duplicate()
	var at_highway := not extra_arms.is_empty()
	for si in graph.nodes[id]["edges"]:
		var st: Dictionary = graph.streets[si]
		var p1 := _along(st, id, 3.0)
		var dir := Vector3(p1.x - c.x, 0, p1.z - c.z).normalized()
		if dir == Vector3.ZERO:
			continue
		arms.append({"dir": dir, "half": float(st["width"]) * 0.5, "main": st["class"] in MARKED,
			"ang": atan2(dir.z, dir.x), "clear": 4.0 if at_highway else float(st["width"]) * 0.5 * 1.54 + 3.0})
	if arms.size() < 2:
		return
	arms.sort_custom(func(a, b): return a["ang"] < b["ang"])
	var height := func(q: Vector3) -> float:
		return plane.x + plane.y * (q.x - c.x) + plane.z * (q.z - c.z) + lift + 0.004
	for k in arms.size():
		var A: Dictionary = arms[k]
		var B: Dictionary = arms[(k + 1) % arms.size()]
		var turn := wrapf(float(B["ang"]) - float(A["ang"]), 0.0, TAU)
		if A.get("hw", false) and B.get("hw", false):
			continue                                   # that side is the highway itself
		if turn > PI * 1.1 or turn < 0.15:
			continue                                   # an open side or two streets on top of each other
		var mid := Vector3(cos(float(A["ang"]) + turn * 0.5), 0, sin(float(A["ang"]) + turn * 0.5))
		var pa := Vector3(-A["dir"].z, 0, A["dir"].x)
		if pa.dot(mid) < 0.0:
			pa = -pa
		var pb := Vector3(-B["dir"].z, 0, B["dir"].x)
		if pb.dot(mid) < 0.0:
			pb = -pb
		var ca: float = A["clear"]
		var cb: float = B["clear"]
		var main: bool = A["main"] or B["main"]
		var bands: Array = [[0.0, 0.45, -0.12, 2, Color(0.32, 0.31, 0.29)], [0.45, 0.7, 0.16, 0, Color(0.78, 0.77, 0.73)],
			[0.7, 1.9, 0.15, 3, Color(0.66, 0.63, 0.58)]] if main else [[-0.05, 1.0, -0.03, 0, Color(0.52, 0.47, 0.40)]]
		for band in bands:
			var inner := _corner_curve(c, A, B, pa, pb, ca, cb, band[0])
			var outer := _corner_curve(c, A, B, pa, pb, ca, cb, band[1])
			var target = wm if main else vm
			for i in inner.size() - 1:
				var a0: Vector3 = inner[i]
				var a1: Vector3 = outer[i]
				var b0: Vector3 = inner[i + 1]
				var b1: Vector3 = outer[i + 1]
				var h0: float = height.call(a0)
				var h1: float = height.call(b0)
				a0.y = h0 + band[2]
				a1.y = h0 + band[2]
				b0.y = h1 + band[2]
				b1.y = h1 + band[2]
				target.quad(a0, a1, b1, b0, band[4], Vector3.UP)
				if band[3] == 2:                       # drain wall down from the road
					target.quad(Vector3(a0.x, h0, a0.z), a0, b0, Vector3(b0.x, h1, b0.z), band[4] * 0.7, a0 - a1)
				elif band[3] == 3:                     # pavement's outer edge into the ground
					target.quad(a1, a1 - Vector3(0, 0.4, 0), b1 - Vector3(0, 0.4, 0), b1, band[4] * 0.85, a1 - a0)
			if main and band[3] == 2:
				# kerb face rising from the drain to the kerb top
				for i in outer.size() - 1:
					var o0: Vector3 = outer[i]
					var o1: Vector3 = outer[i + 1]
					var y0: float = height.call(o0)
					var y1: float = height.call(o1)
					wm.quad(Vector3(o0.x, y0 - 0.12, o0.z), Vector3(o0.x, y0 + 0.16, o0.z), Vector3(o1.x, y1 + 0.16, o1.z),
						Vector3(o1.x, y1 - 0.12, o1.z), Color(0.7, 0.69, 0.66), (o0 - c).normalized() * -1.0)


## The corner line `extra` metres outside both streets' edges: along street A, round a curve
## whose control point is where the two edge lines cross, and out along street B.
func _corner_curve(c: Vector3, A: Dictionary, B: Dictionary, pa: Vector3, pb: Vector3, ca: float, cb: float, extra: float) -> PackedVector3Array:
	var oa: float = A["half"] + extra
	var ob: float = B["half"] + extra
	var da: Vector3 = A["dir"]
	var db: Vector3 = B["dir"]
	var start: Vector3 = c + da * ca + pa * oa
	var finish: Vector3 = c + db * cb + pb * ob
	# the two edge lines: c + pa*oa + t*dirA and c + pb*ob + u*dirB
	var p := Vector2(c.x + pa.x * oa, c.z + pa.z * oa)
	var q := Vector2(c.x + pb.x * ob, c.z + pb.z * ob)
	var r := Vector2(da.x, da.z)
	var sv := Vector2(db.x, db.z)
	var den := r.cross(sv)
	var ctrl: Vector3 = (start + finish) * 0.5
	if absf(den) > 0.05:
		var t := (q - p).cross(sv) / den
		t = clampf(t, 0.0, ca)
		ctrl = Vector3(p.x + r.x * t, c.y, p.y + r.y * t)
	var out := PackedVector3Array()
	var n := 10
	for i in n + 1:
		var u := float(i) / n
		out.append(start.lerp(ctrl, u).lerp(ctrl.lerp(finish, u), u))
	return out


## Point `d` metres into a street from its node end.
func _along(st: Dictionary, from_id: String, d: float) -> Vector3:
	var pts: PackedVector3Array = st["pts"]
	var n := pts.size()
	var rev: bool = st["b"] == from_id and st["a"] != from_id
	var acc := 0.0
	for k in n - 1:
		var a: Vector3 = pts[n - 1 - k] if rev else pts[k]
		var b: Vector3 = pts[n - 2 - k] if rev else pts[k + 1]
		var seg := a.distance_to(b)
		if acc + seg >= d:
			return a.lerp(b, (d - acc) / maxf(seg, 0.001))
		acc += seg
	return pts[0] if rev else pts[n - 1]


func _fit_plane(c: Vector3, pts: Array) -> Vector3:
	# normal equations for y = a + b x + c z (x, z relative to the node)
	var sxx := 0.0; var sxz := 0.0; var szz := 0.0; var sx := 0.0; var sz := 0.0
	var sy := 0.0; var sxy := 0.0; var szy := 0.0
	var n := float(pts.size())
	for p in pts:
		var x: float = p.x - c.x
		var z: float = p.z - c.z
		sx += x; sz += z; sy += p.y
		sxx += x * x; sxz += x * z; szz += z * z; sxy += x * p.y; szy += z * p.y
	var m := Basis(Vector3(n, sx, sz), Vector3(sx, sxx, sxz), Vector3(sz, sxz, szz))
	if absf(m.determinant()) < 1e-6:
		return Vector3(c.y, 0, 0)
	var sol: Vector3 = m.inverse() * Vector3(sy, sxy, szy)
	return Vector3(sol.x, clampf(sol.y, -0.3, 0.3), clampf(sol.z, -0.3, 0.3))


# ----------------------------------------------------------------------------- buildings
func _buildings(town: String, list: Array) -> void:
	var tiles := {}                            # key → [verts, normals, colors, uv, uv2, idx, faces]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(town)
	for b in list:
		var raw: Array = b["poly"]
		var n := raw.size()
		if n < 3:
			continue
		var poly := PackedVector2Array()
		var centre := Vector2.ZERO
		for q in raw:
			poly.append(Vector2(q[0], q[1]))
			centre += Vector2(q[0], q[1])
		centre /= n
		var base: float = b["base"]
		var hill: bool = b.has("roof")
		var roof_y := base + 0.3 + int(b["floors"]) * FLOOR
		var top := roof_y + (0.0 if hill else 0.6)             # flat roofs get a parapet
		var c: Array = b["color"]
		var wall := Color(c[0], c[1], c[2], 1.0)
		var rnd := rng.randf()
		var shop := 1.0 if b.get("shop", false) else 0.0
		var key := _tile(Vector3(centre.x, 0, centre.y))
		if not tiles.has(key):
			tiles[key] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(),
				PackedVector2Array(), PackedInt32Array(), PackedVector3Array()]
		var t: Array = tiles[key]
		var along := 0.0
		for i in n:
			var p0 := poly[i]
			var p1 := poly[(i + 1) % n]
			var e := p1 - p0
			var edge_len := e.length()
			if edge_len < 0.05:
				continue
			var nrm := Vector3(e.y, 0, -e.x).normalized()
			var mid := (p0 + p1) * 0.5
			if Vector2(nrm.x, nrm.z).dot(mid - centre) < 0.0:
				nrm = -nrm
			var a := Vector3(p0.x, base - 0.5, p0.y)
			var bb := Vector3(p1.x, base - 0.5, p1.y)
			var cc := Vector3(p1.x, top, p1.y)
			var d := Vector3(p0.x, top, p0.y)
			_quad(t, a, bb, cc, d, nrm, wall, Vector2(along, -0.5), Vector2(along + edge_len, -0.5),
				Vector2(along + edge_len, top - base), Vector2(along, top - base), Vector2(rnd, shop))
			t[6].append_array([a, bb, cc, a, cc, d])
			along += edge_len
		# roof
		var tris := Geometry2D.triangulate_polygon(poly)
		var rc := Color(0.55, 0.54, 0.52, 0.0)
		if hill:
			var rr: Array = b["roof"]
			rc = Color(rr[0] * 1.8, rr[1] * 1.8, rr[2] * 1.8, 0.0)
		for k in range(0, tris.size(), 3):
			var r0 := Vector3(poly[tris[k]].x, roof_y, poly[tris[k]].y)
			var r1 := Vector3(poly[tris[k + 1]].x, roof_y, poly[tris[k + 1]].y)
			var r2 := Vector3(poly[tris[k + 2]].x, roof_y, poly[tris[k + 2]].y)
			_tri(t, r0, r1, r2, Vector3.UP, rc)
	for key in tiles:
		var t: Array = tiles[key]
		if t[0].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = t[0]
		arr[Mesh.ARRAY_NORMAL] = t[1]
		arr[Mesh.ARRAY_COLOR] = t[2]
		arr[Mesh.ARRAY_TEX_UV] = t[3]
		arr[Mesh.ARRAY_TEX_UV2] = t[4]
		arr[Mesh.ARRAY_INDEX] = t[5]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "%sBuildings_%d_%d" % [town, key.x, key.y]
		mi.mesh = mesh
		mi.material_override = mat_building
		mi.visibility_range_end = 1400.0
		add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(t[6])
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)


## Appends a quad, wound so it faces `nrm` (Godot's front faces are clockwise).
func _quad(t: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, u2: Vector2) -> void:
	var i: int = t[0].size()
	t[0].append_array([a, b, c, d])
	t[1].append_array([nrm, nrm, nrm, nrm])
	t[2].append_array([col, col, col, col])
	t[3].append_array([ua, ub, uc, ud])
	t[4].append_array([u2, u2, u2, u2])
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		t[5].append_array([i, i + 2, i + 1, i, i + 3, i + 2])
	else:
		t[5].append_array([i, i + 1, i + 2, i, i + 2, i + 3])


func _tri(t: Array, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
	var i: int = t[0].size()
	t[0].append_array([a, b, c])
	t[1].append_array([nrm, nrm, nrm])
	t[2].append_array([col, col, col])
	t[3].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	t[4].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		t[5].append_array([i, i + 2, i + 1])
	else:
		t[5].append_array([i, i + 1, i + 2])


# ----------------------------------------------------------------------------- landmarks
## What makes an Indian roofline and facade: black plastic water tanks on stands, stair-head
## rooms, the odd satellite dish on flat roofs; balconies with railings and split-AC units on
## the walls. Seeded per building, so every visit looks the same; one MultiMesh / mesh per tile.
func _rooftops(town: String, list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(town + "roofs")
	var tanks := {}
	var heads := {}
	var dishes := {}
	var acs := {}
	var facades := {}                          # tile -> MB (balconies)
	for b in list:
		var raw: Array = b["poly"]
		var n := raw.size()
		if n < 3:
			continue
		var floors := int(b["floors"])
		var base: float = b["base"]
		var roof_y := base + 0.3 + floors * FLOOR
		var c := Vector2.ZERO
		for q in raw:
			c += Vector2(q[0], q[1])
		c /= n
		# longest edge = the main facade
		var best := 0
		var bl := 0.0
		for i in n:
			var l := Vector2(raw[(i + 1) % n][0] - raw[i][0], raw[(i + 1) % n][1] - raw[i][1]).length()
			if l > bl:
				bl = l
				best = i
		var p0 := Vector2(raw[best][0], raw[best][1])
		var p1 := Vector2(raw[(best + 1) % n][0], raw[(best + 1) % n][1])
		var along := (p1 - p0).normalized()
		var out := Vector2(along.y, -along.x)
		if out.dot((p0 + p1) * 0.5 - c) < 0.0:
			out = -out
		var key := _tile(Vector3(c.x, 0, c.y))
		var flat: bool = not b.has("roof")
		if flat:
			# tank near a corner, pulled inwards
			var corner := Vector2(raw[rng.randi() % n][0], raw[rng.randi() % n][1])
			if rng.randf() < 0.8:
				var tp := corner.lerp(c, 0.3)
				_push(tanks, key, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)),
					Vector3(tp.x, roof_y + 0.6, tp.y)))
			if floors >= 2 and rng.randf() < 0.55 and bl > 6.0:
				var hp := c.lerp(corner, 0.35)
				_push(heads, key, Transform3D(Basis(Vector3.UP, atan2(along.x, along.y)), Vector3(hp.x, roof_y, hp.y)))
			if rng.randf() < 0.12:
				var dp := c.lerp(p0, 0.5)
				_push(dishes, key, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(dp.x, roof_y, dp.y)))
		var yaw := atan2(out.x, out.y)
		# balconies on upper floors of the facade
		if floors >= 2 and bl > 5.0 and rng.randf() < 0.45:
			if not facades.has(key):
				facades[key] = MB.new()
			var w := minf(bl * rng.randf_range(0.3, 0.55), 6.0)
			var t := rng.randf_range(0.2, 0.8)
			var mid := p0.lerp(p1, t)
			mid = mid.clamp(Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)), Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y)))
			for f in range(1, floors):
				var y := base + 0.3 + f * FLOOR
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y, mid.y) + Vector3(out.x, 0, out.y) * 0.55)
				facades[key].box(xf, Vector3(w, 0.15, 1.1), Color(0.7, 0.69, 0.66))
				facades[key].box(xf * Transform3D(Basis(), Vector3(0, 0.5, 0.52)), Vector3(w, 0.9, 0.05), Color(0.22, 0.22, 0.24))
		# split-AC outdoor units hung on the walls
		for f in floors:
			if rng.randf() < 0.35:
				var t := rng.randf_range(0.1, 0.9)
				var ap := p0.lerp(p1, t) + out * 0.25
				_push(acs, key, Transform3D(Basis(Vector3.UP, yaw), Vector3(ap.x, base + 0.3 + f * FLOOR + 2.2, ap.y)))
	var tank := MB.new()
	tank.cylinder(Transform3D(Basis(), Vector3(0, -0.6, 0)), 0.5, 0.5, 0.35, Color(0.4, 0.4, 0.4), 6)
	tank.cylinder(Transform3D(Basis(), Vector3(0, -0.25, 0)), 0.62, 0.6, 1.15, Color(0.05, 0.05, 0.06), 12)
	tank.cylinder(Transform3D(Basis(), Vector3(0, 0.9, 0)), 0.6, 0.2, 0.18, Color(0.05, 0.05, 0.06), 12)
	var head := MB.new()
	head.box(Transform3D(Basis(), Vector3(0, 1.2, 0)), Vector3(2.6, 2.4, 2.8), Color(0.72, 0.7, 0.66))
	head.box(Transform3D(Basis(), Vector3(0, 2.45, 0)), Vector3(2.9, 0.12, 3.1), Color(0.6, 0.6, 0.58))
	head.box(Transform3D(Basis(), Vector3(0, 1.0, 1.41)), Vector3(0.9, 2.0, 0.05), Color(0.35, 0.22, 0.12))
	var dish := MB.new()
	dish.cylinder(Transform3D(Basis(), Vector3(0, 0, 0)), 0.03, 0.03, 0.8, Color(0.5, 0.5, 0.5), 5)
	dish.cylinder(Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(0, 0.85, 0)), 0.38, 0.05, 0.12, Color(0.85, 0.85, 0.85), 10)
	var ac := MB.new()
	ac.box(Transform3D(), Vector3(0.8, 0.55, 0.3), Color(0.86, 0.86, 0.84))
	ac.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.12, 0, 0.15)), 0.2, 0.2, 0.02, Color(0.2, 0.2, 0.2), 10)
	var mat := MB.vertex_color_material(0.7)
	for pair in [[tanks, tank.commit(), 500.0], [heads, head.commit(), 700.0], [dishes, dish.commit(), 250.0], [acs, ac.commit(), 180.0]]:
		for key in pair[0]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[1]
			var xs: Array = pair[0][key]
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = pair[2]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	for key in facades:
		var mi := MeshInstance3D.new()
		mi.mesh = facades[key].commit()
		mi.material_override = mat
		mi.visibility_range_end = 400.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _push(d: Dictionary, key: Vector2i, xf: Transform3D) -> void:
	if not d.has(key):
		d[key] = []
	d[key].append(xf)


## Concrete distribution poles down one side of every street, every ~32 m, carrying sagging
## wires from pole to pole along the street; main roads get a lamp arm over the carriageway.
func _utilities(town: String, streets: Array) -> void:
	var plain := []
	var lit := []
	var wires := {}
	var si := 0
	for s in streets:
		si += 1
		var cls: String = s["class"]
		if cls in ["service", "pedestrian", "living_street"]:
			continue
		var pts: Array = s["pts"]
		var n := pts.size()
		if n < 8:
			continue
		var main: bool = cls in MARKED
		var half: float = float(s["width"]) * 0.5
		var off := half + (1.55 if main else 1.3)
		var side := 1.0 if si % 2 == 0 else -1.0
		var total := 0.0
		var cum: Array = [0.0]
		for k in n - 1:
			total += Vector3(pts[k + 1][0] - pts[k][0], 0, pts[k + 1][2] - pts[k][2]).length()
			cum.append(total)
		if total < 30.0:
			continue
		var prev_tops: Array = []
		var d := 8.0
		var k := 0
		while d < total - 8.0:
			while k < n - 2 and float(cum[k + 1]) < d:
				k += 1
			var a := Vector3(pts[k][0], pts[k][1], pts[k][2])
			var b := Vector3(pts[k + 1][0], pts[k + 1][1], pts[k + 1][2])
			var t: float = (d - float(cum[k])) / maxf(float(cum[k + 1]) - float(cum[k]), 0.01)
			var c := a.lerp(b, t)
			var fwd := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var left := Vector3(fwd.z, 0, -fwd.x) * side
			var base := c + left * off + Vector3(0, -0.1 if not main else 0.05, 0)
			# pole faces the road: local -X points at the carriageway
			var xf := Transform3D(Basis(left, Vector3.UP, left.cross(Vector3.UP)), base)
			if main:
				lit.append(xf)
			else:
				plain.append(xf)
			var tops := [xf * Vector3(0, 8.3, 0.55), xf * Vector3(0, 8.3, -0.55)]
			if not prev_tops.is_empty():
				var key := _tile(base)
				if not wires.has(key):
					wires[key] = MB.new()
				for w in 2:
					_wire(wires[key], prev_tops[w], tops[w])
			prev_tops = tops
			d += 32.0
	var pole := _pole_mesh(false)
	var lamp := _pole_mesh(true)
	_light_pools(lit)
	for pair in [[plain, pole], [lit, lamp]]:
		var cells := {}
		for xf in pair[0]:
			var key := _tile(xf.origin)
			if not cells.has(key):
				cells[key] = []
			cells[key].append(xf)
		for key in cells:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[1]
			mm.instance_count = cells[key].size()
			for i in cells[key].size():
				mm.set_instance_transform(i, cells[key][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 450.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
	var wmat := MB.vertex_color_material(0.6, BaseMaterial3D.CULL_DISABLED)
	for key in wires:
		var wi := MeshInstance3D.new()
		wi.mesh = wires[key].commit()
		wi.material_override = wmat
		wi.visibility_range_end = 260.0
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wi)


func _light_pools(lit: Array) -> void:
	if lit.is_empty():
		return
	if pool_mat == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		pool_mat = StandardMaterial3D.new()
		pool_mat.albedo_texture = tex
		pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pool_mat.albedo_color = Color(1, 0.78, 0.5, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(13, 13)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = pool_mat
	var cells := {}
	for xf in lit:
		var at: Vector3 = xf * Vector3(-1.75, 0.0, 0.0)
		var key := _tile(at)
		if not cells.has(key):
			cells[key] = []
		cells[key].append(Transform3D(Basis(), at + Vector3(0, 0.19, 0)))
	for key in cells:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = cells[key].size()
		for i in cells[key].size():
			mm.set_instance_transform(i, cells[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 350.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
		_pools.append(mmi)


var _pole_cache := {}

func _pole_mesh(with_lamp: bool) -> Mesh:
	if _pole_cache.has(with_lamp):
		return _pole_cache[with_lamp]
	var mb := MB.new()
	var conc := Color(0.62, 0.61, 0.58)
	mb.box(Transform3D(Basis(), Vector3(0, 4.3, 0)), Vector3(0.2, 8.6, 0.24), conc)              # tapered look: two stacked boxes
	mb.box(Transform3D(Basis(), Vector3(0, 1.2, 0)), Vector3(0.26, 2.4, 0.3), conc * 0.95)
	mb.box(Transform3D(Basis(), Vector3(0, 8.2, 0)), Vector3(0.12, 0.1, 1.4), Color(0.25, 0.25, 0.26))   # cross-arm
	for z in [-0.55, 0.55]:
		mb.box(Transform3D(Basis(), Vector3(0, 8.32, z)), Vector3(0.07, 0.14, 0.07), Color(0.75, 0.72, 0.62))
	mb.box(Transform3D(Basis(), Vector3(0.14, 2.9, 0)), Vector3(0.1, 0.35, 0.25), Color(0.5, 0.5, 0.48))  # meter / junction box
	var mesh := mb.commit()
	var mat := MB.cc0_material("concrete", 2.0, 0.9)
	mesh.surface_set_material(0, mat)
	if with_lamp:
		var arm := MB.new()
		arm.box(Transform3D(Basis(), Vector3(-0.9, 7.4, 0)), Vector3(1.8, 0.08, 0.08), Color(0.3, 0.3, 0.3))
		arm.box(Transform3D(Basis(), Vector3(-1.75, 7.33, 0)), Vector3(0.55, 0.12, 0.24), Color(0.35, 0.35, 0.35))
		arm.commit(mesh)
		mesh.surface_set_material(1, MB.vertex_color_material(0.5))
		var head := MB.new()
		head.box(Transform3D(Basis(), Vector3(-1.75, 7.26, 0)), Vector3(0.45, 0.03, 0.18), Color(1, 0.95, 0.8))
		head.commit(mesh)
		if lamp_mat == null:
			lamp_mat = StandardMaterial3D.new()
			lamp_mat.albedo_color = Color(0.9, 0.88, 0.8)
			lamp_mat.emission_enabled = true
			lamp_mat.emission = Color(1.0, 0.82, 0.55)
			lamp_mat.emission_energy_multiplier = 0.0
		mesh.surface_set_material(2, lamp_mat)
	_pole_cache[with_lamp] = mesh
	return mesh


## A sagging wire as a thin ribbon in a few straight pieces.
func _wire(mb, a: Vector3, b: Vector3) -> void:
	var prev := a
	var side := Vector3(b.z - a.z, 0, a.x - b.x).normalized() * 0.012
	for k in range(1, 7):
		var t := k / 6.0
		var q := a.lerp(b, t) - Vector3(0, 0.55 * 4.0 * t * (1.0 - t), 0)
		mb.quad(prev - side, prev + side, q + side, q - side, Color(0.05, 0.05, 0.05), Vector3.UP)
		mb.quad(prev - Vector3(0, 0.012, 0), prev + Vector3(0, 0.012, 0), q + Vector3(0, 0.012, 0), q - Vector3(0, 0.012, 0),
			Color(0.05, 0.05, 0.05), side)
		prev = q


## A generic forecourt (no company colours) beside the street nearest each OSM fuel station:
## a concrete apron, a canopy on four columns and two dispensers. Renames the POI so no brand shows.
func _fuel_bunks(town: String, tw: Dictionary) -> void:
	var mb := MB.new()
	var n := 0
	var polys: Array = []
	for p in tw["pois"]:
		if p["kind"] != "Petrol bunk":
			continue
		if polys.is_empty():
			for b in tw["buildings"]:
				var pg := PackedVector2Array()
				for q in b["poly"]:
					pg.append(Vector2(q[0], q[1]))
				polys.append(pg)
		n += 1
		var at := Vector3(p["x"], p["y"], p["z"])
		var best := Vector3.ZERO
		var bd := INF
		var width := 6.0
		var street := ""
		var along := Vector3.RIGHT
		for st in tw["streets"]:
			var pts: Array = st["pts"]
			for k in pts.size():
				var q := Vector3(pts[k][0], pts[k][1], pts[k][2])
				var dd := Vector2(q.x - at.x, q.z - at.z).length_squared()
				if dd < bd:
					bd = dd
					best = q
					width = float(st["width"])
					street = st["name"]
					var o: Array = pts[mini(k + 1, pts.size() - 1)] if k + 1 < pts.size() else pts[k - 1]
					along = Vector3(o[0] - q.x, 0.0, o[2] - q.z).normalized()
		var side := Vector3(-along.z, 0.0, along.x)
		if side.dot(at - best) < 0.0:
			side = -side
		# first spot beside the street that's clear of the highway and of every building
		var c := best + side * (width * 0.5 + 9.0)
		var found := false
		for sgn in [1.0, -1.0]:
			for gap in [9.0, 13.0, 18.0, 24.0]:
				var q: Vector3 = best + side * float(sgn) * (width * 0.5 + float(gap))
				if _forecourt_clear(q, side * sgn, along, polys):
					c = q
					side = side * float(sgn)
					found = true
					break
			if found:
				break
		if not found:
			continue
		var b := Basis(side, Vector3.UP, side.cross(Vector3.UP)).orthonormalized()   # x: away from the street
		var xf := Transform3D(b, c)
		mb.box(xf * Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(16.0, 0.3, 22.0), Color(0.55, 0.55, 0.53))
		mb.box(xf * Transform3D(Basis(), Vector3(0, 5.6, 0)), Vector3(10.0, 0.7, 14.0), Color(0.93, 0.93, 0.9))
		mb.box(xf * Transform3D(Basis(), Vector3(-5.02, 5.6, 0)), Vector3(0.06, 0.5, 14.0), Color(0.15, 0.45, 0.3))
		for sx in [-3.5, 3.5]:
			for sz in [-5.0, 5.0]:
				mb.box(xf * Transform3D(Basis(), Vector3(sx, 2.7, sz)), Vector3(0.45, 5.4, 0.45), Color(0.85, 0.85, 0.82))
		for sz in [-3.0, 3.0]:
			var pump := xf * Transform3D(Basis(), Vector3(0, 0.95, sz))
			mb.box(pump, Vector3(0.7, 1.6, 1.1), Color(0.2, 0.42, 0.32))
			mb.box(pump * Transform3D(Basis(), Vector3(0.36, 0.3, 0)), Vector3(0.02, 0.4, 0.6), Color(0.05, 0.06, 0.07))
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.9, 1.9, 1.3)
			cs.shape = sh
			cs.transform = pump
			body.add_child(cs)
		var name := "Fuel Bunk · %s" % pretty_street(street) if street != "" else "%s Fuel Bunk %d" % [town, n]
		p["name"] = name
		p["x"] = c.x                                 # label and GPS point on the forecourt itself
		p["y"] = c.y
		p["z"] = c.z
		bunks.append({"name": name, "pos": c, "town": town})
		var lamp := OmniLight3D.new()                  # canopy floodlights, on after dusk
		lamp.position = c + Vector3(0, 4.8, 0)
		lamp.omni_range = 18.0
		lamp.light_color = Color(0.95, 0.97, 1.0)
		lamp.light_energy = 0.0
		lamp.visible = false
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 180.0
		lamp.distance_fade_length = 40.0
		add_child(lamp)
		bunk_lights.append(lamp)
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "FuelBunks"
		mi.mesh = mb.commit()
		mi.material_override = MB.vertex_color_material(0.7)
		mi.visibility_range_end = 700.0
		add_child(mi)


func _forecourt_clear(c: Vector3, out: Vector3, along: Vector3, buildings: Array) -> bool:
	if highway_gap.is_valid() and highway_gap.call(c) < 22.0:
		return false
	for sx in [-8.0, 0.0, 8.0]:
		for sz in [-11.0, 0.0, 11.0]:
			var q: Vector3 = c + out * float(sx) + along * float(sz)
			for pg in buildings:
				if Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), pg):
					return false
	return true


## OSM street names are often typed without spaces ("Gandhipuram1stStreet", "LSPuram2ndSt").
static func pretty_street(n: String) -> String:
	var re := RegEx.new()
	re.compile("([a-z])([A-Z0-9])")
	n = re.sub(n, "$1 $2", true)
	re.compile("([A-Z])([A-Z][a-z])")
	n = re.sub(n, "$1 $2", true)
	return n.split(" - ")[0] if n.length() > 30 else n


func _pois(town: String, list: Array) -> void:
	for p in list:
		var pos := Vector3(p["x"], p["y"], p["z"])
		var kind: String = p["kind"]
		pois.append({"name": p["name"], "kind": kind, "pos": pos, "town": town})
		var l := Label3D.new()
		l.text = "%s\n%s" % [p["name"], kind]
		l.font_size = 40
		l.pixel_size = 0.008
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = POI_COLOURS.get(kind, Color(1, 1, 0.85))
		l.outline_size = 8
		l.position = pos + Vector3(0, 5.0, 0)
		l.visibility_range_end = 140.0
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.no_depth_test = false
		add_child(l)
