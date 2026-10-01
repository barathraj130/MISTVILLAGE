extends RefCounted
## GPS: A* over the road graph (road_graph.gd): highway points every 10 m, street points every
## ~9 m, joined only where roads really meet: shared junction nodes, and streets' highway nodes
## tied to their route sample. (Old maps without nodes fall back to joining near-touching points.)

var astar := AStar3D.new()
var _next := 0
var _cells := {}                           # 12 m grid → point ids (for junctions)


const HW_STEP := 5

func build(route, towns_data: Dictionary, graph = null) -> void:
	var chain := PackedVector3Array()
	for i in range(0, route.pts.size(), HW_STEP):
		chain.append(route.pts[i])
	_add_chain(chain, 0)                    # highway point k has id k
	if graph and graph.has_graph():
		_build_from_graph(route, graph)
		return
	var road := 1
	for tname in towns_data:
		for s in towns_data[tname]["streets"]:
			var pts: Array = s["pts"]
			var c := PackedVector3Array()
			for i in range(0, pts.size(), 3):
				c.append(Vector3(pts[i][0], pts[i][1], pts[i][2]))
			var last: Array = pts[pts.size() - 1]
			c.append(Vector3(last[0], last[1], last[2]))
			_add_chain(c, road)
			road += 1
	# junctions: connect points of different roads that nearly touch
	for key in _cells:
		var here: Array = _cells[key]
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var other: Array = _cells.get(Vector2i(key.x + dx, key.y + dz), [])
				for a in here:
					for b in other:
						if a[1] >= b[1] or a[2] == b[2]:
							continue
						if astar.get_point_position(a[1]).distance_to(astar.get_point_position(b[1])) < 7.5:
							astar.connect_points(a[1], b[1])


func _build_from_graph(route, graph) -> void:
	var node_id := {}
	for id in graph.nodes:
		var nd: Dictionary = graph.nodes[id]
		var pid := _next
		_next += 1
		astar.add_point(pid, nd["pos"])
		_index(nd["pos"], pid, -1)
		node_id[id] = pid
		if nd["kind"] == "highway":
			var k: int = clampi(int(round(float(nd["route_i"]) / HW_STEP)), 0, (route.pts.size() - 1) / HW_STEP)
			astar.connect_points(pid, k)
	for si in graph.streets.size():
		var s: Dictionary = graph.streets[si]
		if not node_id.has(s["a"]) or not node_id.has(s["b"]):
			continue
		var pts: PackedVector3Array = s["pts"]
		var prev: int = node_id[s["a"]]
		for i in range(3, pts.size() - 2, 3):
			var id := _next
			_next += 1
			astar.add_point(id, pts[i])
			_index(pts[i], id, si + 1)
			astar.connect_points(prev, id)
			prev = id
		astar.connect_points(prev, node_id[s["b"]])


func _index(p: Vector3, id: int, road: int) -> void:
	var key := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
	if not _cells.has(key):
		_cells[key] = []
	_cells[key].append([key, id, road])


func _add_chain(pts: PackedVector3Array, road: int) -> void:
	var prev := -1
	for p in pts:
		var id := _next
		_next += 1
		astar.add_point(id, p)
		if prev >= 0:
			astar.connect_points(prev, id)
		prev = id
		var key := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append([key, id, road])


## Nearest road point by map position only (roads climb 800 m, so ignore height).
func closest(p: Vector3) -> int:
	var k := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
	for r in [1, 3, 8]:
		var best := -1
		var bd := INF
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				for e in _cells.get(Vector2i(k.x + dx, k.y + dz), []):
					var q := astar.get_point_position(e[1])
					var dd := Vector2(q.x - p.x, q.z - p.z).length_squared()
					if dd < bd:
						bd = dd
						best = e[1]
		if best >= 0:
			return best
	return astar.get_closest_point(p)


## Road path from one position to another (empty if unreachable).
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := closest(from)
	var b := closest(to)
	if a < 0 or b < 0:
		return PackedVector3Array()
	var p := astar.get_point_path(a, b)
	if p.is_empty():
		return p
	p.append(to)
	return p


static func length(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in p.size() - 1:
		l += p[i].distance_to(p[i + 1])
	return l
