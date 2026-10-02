extends Node3D
## Parked vehicles along the town streets: two-wheelers nosed in at an angle, autos and cars
## pulled up at the kerb, vans outside shops. Denser on main roads and near shopfronts, never
## inside a junction, never perfectly aligned. One MultiMesh per model per 256 m tile.

const MB := preload("res://scripts/drive/mesh_builder.gd")
const Fleet := preload("res://scripts/drive/fleet.gd")
const KENNEY := "res://assets/drive/models/kenney/"
const TILE := 256.0
const MARKED := ["trunk", "primary", "secondary", "tertiary"]
## model, length (m), weight on main roads, weight on side streets, gets a collider
const FLEET := [
	["bike", 2.0, 30, 30, false], ["scooter", 1.8, 22, 25, false], ["auto", 2.65, 12, 6, true],
	["hatchback", 3.85, 16, 16, true], ["sedan", 4.4, 10, 7, true], ["suv", 4.5, 4, 4, true],
	["taxi", 4.4, 4, 2, true], ["van", 4.6, 3, 2, true], ["delivery", 5.2, 3, 1, true],
]

const BIKE_PAINT := [Color(0.08, 0.08, 0.09), Color(0.7, 0.07, 0.06), Color(0.1, 0.2, 0.6), Color(0.75, 0.75, 0.78),
	Color(1, 1, 1), Color(0.35, 0.36, 0.38), Color(0.55, 0.1, 0.12), Color(0.08, 0.3, 0.2)]

var _meshes := {}
var entries: Array = []             # every parked vehicle: {model, xf, key, index, cs, taken}
var _grid := {}                     # 12 m cells -> entries
var _mmis := {}                     # tile -> model -> [MultiMeshInstance3D per part]                  # model -> [[Mesh, local Transform3D], ...]
var _rng := RandomNumberGenerator.new()


func build(town: String, streets: Array, graph, body: StaticBody3D, shop_points: Array) -> int:
	_rng.seed = hash(town + "parked")
	var shops := {}                # 20 m grid of shopfronts, to park more where there's business
	for p in shop_points:
		var k := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
		shops[k] = true
	var by_tile := {}              # tile -> model -> [Transform3D]
	var count := 0
	for s in streets:
		var cls: String = s["class"]
		if cls in ["service", "pedestrian", "trunk_link", "primary_link"]:
			continue
		var main: bool = cls in MARKED
		var pts: Array = s["pts"]
		var n := pts.size()
		if n < 6:
			continue
		var half: float = float(s["width"]) * 0.5
		var clear_a := half * 2.6 if graph and graph.is_junction(s.get("a", "")) else 4.0
		var clear_b := half * 2.6 if graph and graph.is_junction(s.get("b", "")) else 4.0
		var cum := [0.0]
		for k in n - 1:
			cum.append(float(cum[k]) + Vector2(pts[k + 1][0] - pts[k][0], pts[k + 1][2] - pts[k][2]).length())
		var total: float = cum[n - 1]
		for side in [1.0, -1.0]:
			var d: float = clear_a + _rng.randf_range(0.0, 10.0)
			var k := 0
			while d < total - clear_b:
				while k < n - 2 and float(cum[k + 1]) < d:
					k += 1
				var a := Vector3(pts[k][0], pts[k][1], pts[k][2])
				var b := Vector3(pts[k + 1][0], pts[k + 1][1], pts[k + 1][2])
				var t: float = (d - float(cum[k])) / maxf(float(cum[k + 1]) - float(cum[k]), 0.01)
				var c := a.lerp(b, t)
				var fwd := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var left: Vector3 = Vector3(fwd.z, 0, -fwd.x) * float(side)
				var busy: bool = shops.has(Vector2i(floori(c.x / 20.0), floori(c.z / 20.0)))
				var chance := (0.12 if main else 0.03) + (0.18 if busy else 0.0)
				if _rng.randf() > chance:
					d += _rng.randf_range(8.0, 22.0)
					continue
				var model := _pick(main)
				var len_m: float = _len(model)
				var two_wheeler := model == "bike" or model == "scooter"
				var yaw := atan2(fwd.x, fwd.z) + (0.0 if _rng.randf() < 0.5 else PI)
				var off := half - (0.85 if main else 0.2)
				if two_wheeler:
					# nosed in towards the kerb at an angle, often a few in a row
					yaw = atan2(left.x, left.z) + PI + _rng.randf_range(-0.5, 0.5)
					off = half - 0.9 if main else half + 0.1
				else:
					yaw += _rng.randf_range(-0.07, 0.07)
					off += _rng.randf_range(-0.25, 0.2)
				var row := 1 if not two_wheeler else _rng.randi_range(1, 3)
				for r in row:
					var at: Vector3 = c + fwd * (r * 0.95) + left * off
					var y := c.y + (0.06 if main else 0.0)
					var xf := Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.12, 0.12) * float(two_wheeler)), Vector3(at.x, y, at.z))
					var key := Vector2i(floori(at.x / TILE), floori(at.z / TILE))
					# the Blender fleet comes in many paints: one MultiMesh per model + colour
					var vkey := model
					if Fleet.has(model):
						vkey = model + "|" + Fleet.paint_for(model, _rng).to_html()
					if not by_tile.has(key):
						by_tile[key] = {}
					if not by_tile[key].has(vkey):
						by_tile[key][vkey] = []
					by_tile[key][vkey].append(xf)
					count += 1
					var entry := {"model": model, "vkey": vkey, "xf": xf, "key": key, "index": by_tile[key][vkey].size() - 1, "cs": null, "taken": false}
					entries.append(entry)
					var g := Vector2i(floori(at.x / 12.0), floori(at.z / 12.0))
					if not _grid.has(g):
						_grid[g] = []
					_grid[g].append(entry)
					if _collides(model):
						var cs := CollisionShape3D.new()
						var box := BoxShape3D.new()
						box.size = Vector3(1.7 if model != "auto" else 1.3, 1.4, len_m * 0.95)
						cs.shape = box
						cs.transform = xf.translated_local(Vector3(0, 0.75, 0))
						body.add_child(cs)
						entry["cs"] = cs
				d += len_m + _rng.randf_range(0.6, 3.0) + (row - 1) * 0.95
	for key in by_tile:
		for vkey in by_tile[key]:
			var model: String = vkey.get_slice("|", 0)
			var parts: Array = Fleet.parts(model, Color.html(vkey.get_slice("|", 1))) if "|" in vkey else _parts(model)
			for part in parts:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				var tint: bool = model in ["bike", "scooter"]
				mm.use_colors = tint
				mm.mesh = part[0]
				var list: Array = by_tile[key][vkey]
				mm.instance_count = list.size()
				for i in list.size():
					mm.set_instance_transform(i, list[i] * part[1])
					if tint:
						mm.set_instance_color(i, BIKE_PAINT[_rng.randi() % BIKE_PAINT.size()])
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.visibility_range_end = 260.0 if not model in ["bike", "scooter"] else 150.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)
				if not _mmis.has(key):
					_mmis[key] = {}
				if not _mmis[key].has(vkey):
					_mmis[key][vkey] = []
				_mmis[key][vkey].append(mmi)
	return count


## The nearest parked vehicle within r metres of p (or {}).
func nearest(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	var g := Vector2i(floori(p.x / 12.0), floori(p.z / 12.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e in _grid.get(Vector2i(g.x + dx, g.y + dz), []):
				if e["taken"]:
					continue
				var dd: float = (e["xf"].origin as Vector3).distance_to(p)
				if dd < bd:
					bd = dd
					best = e
	return best


## You drove off in it: remove it from the street (and its collider).
func take(e: Dictionary) -> void:
	e["taken"] = true
	for mmi in _mmis.get(e["key"], {}).get(e["vkey"], []):
		(mmi as MultiMeshInstance3D).multimesh.set_instance_transform(e["index"],
			Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -900, 0)))
	if e["cs"]:
		(e["cs"] as Node).queue_free()
		e["cs"] = null


func _pick(main: bool) -> String:
	var total := 0
	for f in FLEET:
		total += f[2] if main else f[3]
	var r := _rng.randi_range(1, total)
	for f in FLEET:
		r -= f[2] if main else f[3]
		if r <= 0:
			return f[0]
	return "bike"


func _len(model: String) -> float:
	for f in FLEET:
		if f[0] == model:
			return f[1]
	return 4.0


func _collides(model: String) -> bool:
	for f in FLEET:
		if f[0] == model:
			return f[4]
	return false


## The meshes of a model as [Mesh, local transform] parts: Kenney GLBs scaled to real length
## and set on the ground facing +Z, or the hand-built two- and three-wheelers.
func _parts(model: String) -> Array:
	if _meshes.has(model):
		return _meshes[model]
	var parts: Array = []
	match model:
		"bike", "scooter", "auto":
			parts.append([_built(model), Transform3D()])
		_:
			var path := KENNEY + model + ".glb"
			if ResourceLoader.exists(path):
				var node := (load(path) as PackedScene).instantiate() as Node3D
				var aabb := AABB()
				var first := true
				var found: Array = []
				for mi in node.find_children("*", "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					var xf := _local_xf(m, node)
					var box: AABB = xf * m.get_aabb()
					aabb = box if first else aabb.merge(box)
					first = false
					found.append([m.mesh, xf])
				var s: float = _len(model) / maxf(aabb.size.z, 0.01)
				var fix := Transform3D(Basis().scaled(Vector3.ONE * s),
					Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s))
				for f in found:
					parts.append([f[0], fix * f[1]])
				node.free()
	_meshes[model] = parts
	return parts


func _local_xf(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _built(model: String) -> Mesh:
	var mb := MB.new()
	var tyre := Color(0.03, 0.03, 0.03)
	var steel := Color(0.55, 0.56, 0.58)
	var paint := Color(1, 1, 1)                 # tinted per instance
	match model:
		"bike":
			for z in [-0.68, 0.68]:
				mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.05, 0.31, z)), 0.31, 0.31, 0.1, tyre, 12)
			mb.box(Transform3D(Basis(), Vector3(0, 0.55, 0.05)), Vector3(0.22, 0.3, 0.75), steel * 0.6)        # engine
			mb.box(Transform3D(Basis(), Vector3(0, 0.82, 0.25)), Vector3(0.3, 0.22, 0.5), paint)               # tank
			mb.box(Transform3D(Basis(), Vector3(0, 0.82, -0.32)), Vector3(0.26, 0.1, 0.6), Color(0.04, 0.04, 0.04))   # seat
			mb.box(Transform3D(Basis(), Vector3(0, 0.62, -0.68)), Vector3(0.2, 0.08, 0.5), paint * 0.8)        # rear guard
			mb.box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0.75, 0.62)), Vector3(0.06, 0.6, 0.06), steel)  # fork
			mb.box(Transform3D(Basis(), Vector3(0, 1.05, 0.55)), Vector3(0.7, 0.04, 0.04), steel)              # handlebar
			mb.box(Transform3D(Basis(), Vector3(0, 0.98, 0.72)), Vector3(0.18, 0.16, 0.08), Color(0.9, 0.9, 0.8))   # headlamp
		"scooter":
			for z in [-0.6, 0.6]:
				mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.05, 0.25, z)), 0.25, 0.25, 0.11, tyre, 12)
			var sc := Color(1, 1, 1)
			mb.box(Transform3D(Basis(), Vector3(0, 0.55, -0.3)), Vector3(0.36, 0.45, 0.75), sc)                 # rear body
			mb.box(Transform3D(Basis(), Vector3(0, 0.33, 0.15)), Vector3(0.3, 0.08, 0.5), sc * 0.8)             # floorboard
			mb.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.75, 0.48)), Vector3(0.34, 0.85, 0.12), sc)   # leg shield
			mb.box(Transform3D(Basis(), Vector3(0, 0.82, -0.32)), Vector3(0.3, 0.1, 0.6), Color(0.04, 0.04, 0.04))
			mb.box(Transform3D(Basis(), Vector3(0, 1.12, 0.55)), Vector3(0.65, 0.05, 0.05), steel)
		"auto":
			# three-wheeler: green-and-yellow body, black canvas top, open sides
			var yellow := Color(0.85, 0.66, 0.08)
			var green := Color(0.1, 0.32, 0.12)
			for x in [-0.6, 0.6]:
				mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.22, -0.75)), 0.22, 0.22, 0.12, tyre, 10)
			mb.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.05, 0.22, 1.0)), 0.22, 0.22, 0.12, tyre, 10)
			mb.box(Transform3D(Basis(), Vector3(0, 0.45, -0.3)), Vector3(1.3, 0.45, 1.5), green)               # rear tub
			mb.box(Transform3D(Basis(), Vector3(0, 0.75, -0.55)), Vector3(1.25, 0.5, 0.15), yellow)             # seat back
			mb.box(Transform3D(Basis(), Vector3(0, 0.62, -0.3)), Vector3(1.15, 0.14, 0.6), Color(0.08, 0.08, 0.08))   # bench
			mb.box(Transform3D(Basis(), Vector3(0, 0.6, 0.85)), Vector3(0.75, 0.75, 0.3), yellow)               # nose
			mb.box(Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0, 1.15, 0.72)), Vector3(0.95, 0.6, 0.04), Color(0.2, 0.25, 0.28))   # windscreen
			mb.box(Transform3D(Basis(), Vector3(0, 1.7, -0.15)), Vector3(1.32, 0.08, 1.9), Color(0.04, 0.04, 0.04))   # canvas roof
			for x in [-0.62, 0.62]:
				mb.box(Transform3D(Basis(), Vector3(x, 1.15, -0.95)), Vector3(0.05, 1.1, 0.05), Color(0.04, 0.04, 0.04))
				mb.box(Transform3D(Basis(), Vector3(x, 1.2, 0.68)), Vector3(0.05, 1.0, 0.05), Color(0.04, 0.04, 0.04))
			mb.box(Transform3D(Basis(), Vector3(0, 1.25, -1.05)), Vector3(1.3, 0.85, 0.04), Color(0.04, 0.04, 0.04))   # back canvas
	var mesh := mb.commit()
	mesh.surface_set_material(0, MB.vertex_color_material(0.55))
	return mesh
