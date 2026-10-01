extends RefCounted
## The one road network everything reads: the highway (route samples) plus every town street as
## an edge between two shared nodes (compiled from OpenStreetMap by tools/towns.py).
## Street meshes and collision (towns.gd), GPS (nav.gd), the minimap, surface grip and the
## validator / debug view all come from here, so what you see is what you can drive and route on.

const CELL := 20.0

var route
var nodes := {}                    # id -> {pos: Vector3, kind: junction|end|edge|highway, route_i?, edges: [street idx]}
var streets: Array = []            # {pts: PackedVector3Array, a, b, width, class, name, oneway, town}
var _grid := {}                    # CELL grid -> [[street idx, segment idx]] for "which road am I on"


func build(r, towns_data: Dictionary) -> void:
	route = r
	for tname in towns_data:
		var tw: Dictionary = towns_data[tname]
		var tn: Dictionary = tw.get("nodes", {})
		for id in tn:
			var nd: Dictionary = tn[id]
			var e := {"pos": Vector3(nd["x"], nd["y"], nd["z"]), "kind": nd["kind"], "edges": []}
			if nd.has("route_i"):
				e["route_i"] = int(nd["route_i"])
			nodes[id] = e
		for s in tw["streets"]:
			var pts := PackedVector3Array()
			for q in s["pts"]:
				pts.append(Vector3(q[0], q[1], q[2]))
			var si := streets.size()
			streets.append({"pts": pts, "a": s.get("a", ""), "b": s.get("b", ""), "width": float(s["width"]),
				"class": s["class"], "name": s["name"], "oneway": s.get("oneway", false), "town": tname})
			for id in [s.get("a", ""), s.get("b", "")]:
				if nodes.has(id):
					nodes[id]["edges"].append(si)
			for k in pts.size() - 1:
				var m := (pts[k] + pts[k + 1]) * 0.5
				var key := Vector2i(floori(m.x / CELL), floori(m.z / CELL))
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append([si, k])


func has_graph() -> bool:
	return not nodes.is_empty()


func degree(id: String) -> int:
	return nodes[id]["edges"].size() if nodes.has(id) else 0


## Is this node a real meeting of roads (needs a junction surface, no lane paint through it)?
func is_junction(id: String) -> bool:
	if not nodes.has(id):
		return false
	return nodes[id]["kind"] == "highway" or degree(id) >= 3


## Nearest town street to a point: [street idx, distance to its centreline] (or [-1, INF]).
func nearest_street(p: Vector3) -> Array:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var best := -1
	var bd := INF
	var p2 := Vector2(p.x, p.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e in _grid.get(Vector2i(key.x + dx, key.y + dz), []):
				var pts: PackedVector3Array = streets[e[0]]["pts"]
				var a := Vector2(pts[e[1]].x, pts[e[1]].z)
				var b := Vector2(pts[e[1] + 1].x, pts[e[1] + 1].z)
				var dd := p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, a, b))
				if dd < bd:
					bd = dd
					best = e[0]
	return [best, bd]


## What's under the wheels: "asphalt", "shoulder" or "ground".
func surface_at(p: Vector3, hint: int) -> String:
	var i: int = route.nearest(p, hint, 30)
	var lat := Vector2(p.x - route.pts[i].x, p.z - route.pts[i].z).length()
	if lat < route.ROAD_HALF + 0.3:
		return "asphalt"
	var ns := nearest_street(p)
	if ns[0] >= 0 and ns[1] < streets[ns[0]]["width"] * 0.5 + 0.4:
		return "asphalt"
	if lat < route.ROAD_HALF + 2.0 or (ns[0] >= 0 and ns[1] < streets[ns[0]]["width"] * 0.5 + 1.6):
		return "shoulder"
	return "ground"


# ----------------------------------------------------------------------------- validation
## Checks the network the way the GPS and the car experience it. `height_fn(x, z)` is the
## visible ground. Returns {report: String, problems: [{pos, what}]}.
func validate(height_fn: Callable) -> Dictionary:
	var problems: Array = []
	var dangling := 0
	var bad_refs := 0
	var floating := 0
	var buried := 0
	var near_miss := 0
	# 1-2: every street starts and ends on a node that lists it
	for si in streets.size():
		var s: Dictionary = streets[si]
		for id in [s["a"], s["b"]]:
			if not nodes.has(id) or not si in nodes[id]["edges"]:
				bad_refs += 1
				problems.append({"pos": s["pts"][0], "what": "street %d has no node '%s'" % [si, id]})
		# 5: the road surface sits on the ground (sampled every ~12 m)
		var pts: PackedVector3Array = s["pts"]
		for k in range(0, pts.size(), 4):
			var g: float = height_fn.call(pts[k].x, pts[k].z)
			var gap := pts[k].y - g
			if gap > 0.8:
				floating += 1
				problems.append({"pos": pts[k], "what": "street floats %.1f m above ground" % gap})
			elif gap < -0.6:
				buried += 1
				problems.append({"pos": pts[k], "what": "street buried %.1f m" % -gap})
	# 10: dead ends that almost touch another street are probably missing a connection
	for id in nodes:
		var nd: Dictionary = nodes[id]
		if nd["kind"] != "end" or nd["edges"].size() != 1:
			continue
		dangling += 1
		var ns := _nearest_other(nd["pos"], nd["edges"][0])
		if ns[1] < 6.0:
			near_miss += 1
			problems.append({"pos": nd["pos"], "what": "dead end %.1f m from another street" % ns[1]})
	# connectivity: which nodes can be reached from the highway?
	var comp := _components()
	var reach := 0
	for id in nodes:
		if comp["of"].get(id, -1) in comp["highway"]:
			reach += 1
	var islands: int = comp["count"] - comp["highway"].size()
	for c in comp["sample"]:
		if not c in comp["highway"]:
			problems.append({"pos": nodes[comp["sample"][c]]["pos"], "what": "street island not linked to the main network"})
	var edge_ends := 0
	var hw := 0
	for id in nodes:
		if nodes[id]["kind"] == "edge":
			edge_ends += 1
		elif nodes[id]["kind"] == "highway":
			hw += 1
	var lines := PackedStringArray([
		"ROAD NETWORK VALIDATION",
		"  Streets: %d   Nodes: %d   Junctions on the highway: %d" % [streets.size(), nodes.size(), hw],
		"  Reachable from the highway: %d / %d nodes (%.1f%%)" % [reach, nodes.size(), 100.0 * reach / maxi(nodes.size(), 1)],
		"  Islands (unlinked street groups): %d" % islands,
		"  Broken node references: %d" % bad_refs,
		"  Dead ends: %d (of which %d end within 6 m of another street)" % [dangling, near_miss],
		"  Streets leaving the mapped town area: %d" % edge_ends,
		"  Terrain gaps: %d floating, %d buried samples" % [floating, buried],
	])
	return {"report": "\n".join(lines), "problems": problems}


func _nearest_other(p: Vector3, own: int) -> Array:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var bd := INF
	var p2 := Vector2(p.x, p.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e in _grid.get(Vector2i(key.x + dx, key.y + dz), []):
				if e[0] == own:
					continue
				var pts: PackedVector3Array = streets[e[0]]["pts"]
				var dd := p2.distance_to(Geometry2D.get_closest_point_to_segment(p2,
					Vector2(pts[e[1]].x, pts[e[1]].z), Vector2(pts[e[1] + 1].x, pts[e[1] + 1].z)))
				bd = minf(bd, dd)
	return [-1, bd]


func _components() -> Dictionary:
	var of := {}
	var count := 0
	var highway := []
	var sample := {}
	for start in nodes:
		if of.has(start):
			continue
		var stack := [start]
		of[start] = count
		sample[count] = start
		var touches_hw := false
		while not stack.is_empty():
			var id: String = stack.pop_back()
			if nodes[id]["kind"] == "highway":
				touches_hw = true
			for si in nodes[id]["edges"]:
				for other in [streets[si]["a"], streets[si]["b"]]:
					if nodes.has(other) and not of.has(other):
						of[other] = count
						stack.append(other)
		if touches_hw:
			highway.append(count)
		count += 1
	return {"of": of, "count": count, "highway": highway, "sample": sample}
