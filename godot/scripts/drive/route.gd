extends RefCounted
## The compressed Coimbatore → Kotagiri drive (≈ 6.7 km, about 9 minutes at road speeds).
## A turtle draws the plan-view centreline; the plains, the Nilgiri face and the plateau
## come from natural_h(); the road gets its own smoothed height profile with a constant
## grade up the nine hairpins. Metres; the road runs broadly +X, from the plains to the hills.

const SAMPLE := 2.0
const ROAD_HALF := 3.6
const LANE := 1.8
const FACE_RISE := 225.0
const HAIRPINS := 9

var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var pts := PackedVector3Array()          # centreline samples, y = road height
var tangents := PackedVector3Array()     # horizontal unit tangents
var dist := PackedFloat32Array()         # distance along the road
var length := 0.0
var stages: Array = []                   # {id, title, subtitle, start, end, alt0, alt1}
var hairpin_idx: Array = []              # sample index of each hairpin apex
var marks := {}                          # named distances: checkpost, elephants, tea_stall, bridge_start, ...
var face_x0 := 0.0
var face_x1 := 0.0
var river_x := 0.0
var river_z := 0.0
var river_bed := 0.0

# real map (tools/compile_drive_map.py): OpenStreetMap road + SRTM terrain, ETS-style compressed
const MAP_DIR := "res://assets/drive/"
var is_real := false
var resort_attached := false             # your resort sits at the end of the road
var towns: Array = []                    # {name, start, end, floors, hill}
var real_d := PackedFloat32Array()       # real-world distance (m) at each sample
var alt := PackedFloat32Array()          # real altitude (m) at each sample
var real_length := 0.0
var credit := ""
var _nat := PackedFloat32Array()
var _near_meta := {}
var _far := PackedFloat32Array()
var _far_meta := {}

var _pos := Vector2.ZERO                 # (x, z)
var _heading := 0.0                      # 0 = +X; increasing turns towards +Z (a right turn)
var _d := 0.0


func build() -> void:
	noise.seed = 11
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	noise2.seed = 23
	noise2.frequency = 0.0015
	noise2.fractal_octaves = 3
	_emit()

	_stage("coimbatore", "Coimbatore", "Early morning on the edge of the city", 411, 400)
	_fwd(260); _turn(320, 10); _fwd(180); _turn(320, -10); _fwd(120)

	_stage("plains", "Towards Mettupalayam", "Coconut groves, and the blue hills ahead", 400, 330)
	_fwd(180); _turn(450, 22); _fwd(220); _turn(450, -40); _fwd(200); _turn(500, 18); _fwd(160)

	_stage("mettupalayam", "Mettupalayam", "Gateway to the Nilgiris", 320, 330)
	_fwd(200)
	marks["bridge_start"] = _d
	_fwd(70)
	marks["bridge_end"] = _d
	_fwd(230)

	_stage("foothills", "Foothills", "Forest check post · wild elephants", 350, 480)
	_fwd(120)
	marks["checkpost"] = _d
	_fwd(100); _turn(160, 25); _fwd(140)
	marks["elephants"] = _d
	_fwd(60); _turn(160, -25); _fwd(80)

	_stage("ghat", "Kotagiri Ghat Road", "Nine hairpin bends · uphill traffic has right of way", 480, 1550)
	marks["ghat_start"] = _d
	var gi0 := pts.size() - 1
	_turn(30, 85.6)                      # swing round to climb across the face
	var s := 1.0
	for k in HAIRPINS:
		_fwd(260)
		var i0 := pts.size()
		_turn(14, -171.2 * s)
		hairpin_idx.append((i0 + pts.size()) / 2)
		s = -s
	_fwd(260)
	_turn(30, -rad_to_deg(_heading))     # back onto the plateau heading
	marks["ghat_end"] = _d
	var gi1 := pts.size() - 1

	_stage("mist", "Into the Clouds", "Tea gardens above the mist", 1550, 1760)
	_fwd(120)
	marks["tea_stall"] = _d
	_fwd(60); _turn(200, 30); _fwd(180); _turn(220, -45); _fwd(160); _turn(200, 15); _fwd(120)

	_stage("kotagiri", "Kotagiri", "Almost there", 1780, 1793)
	_fwd(260); _turn(150, -20); _fwd(140)

	_stage("arrival", "The Mist Village", "Where the mist slows you down", 1793, 1793)
	_fwd(90)
	length = _d
	stages[-1]["end"] = length

	face_x0 = pts[gi0].x + 20.0
	face_x1 = pts[gi1].x
	var bi := index_at((marks["bridge_start"] + marks["bridge_end"]) * 0.5)
	river_z = pts[bi].z
	river_x = pts[bi].x - 25.0 * sin(river_z / 90.0)
	_road_heights(gi0, gi1)
	river_bed = pts[bi].y - 7.0
	_tangents()


## Loads the compiled real map. Returns false if it hasn't been compiled yet.
func load_map() -> bool:
	var path := MAP_DIR + "map.json"
	if not FileAccess.file_exists(path):
		return false
	var m = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(m) != TYPE_DICTIONARY:
		return false
	is_real = true
	noise.seed = 11
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	noise2.seed = 23
	noise2.frequency = 0.0015
	noise2.fractal_octaves = 3
	var s: Dictionary = m["samples"]
	var xs: Array = s["x"]
	var ys: Array = s["y"]
	var zs: Array = s["z"]
	var rd: Array = s["real_d"]
	var al: Array = s["alt"]
	var n := xs.size()
	pts.resize(n)
	dist.resize(n)
	real_d.resize(n)
	alt.resize(n)
	for i in n:
		pts[i] = Vector3(xs[i], ys[i], zs[i])
		dist[i] = i * SAMPLE
		real_d[i] = rd[i]
		alt[i] = al[i]
	length = dist[n - 1]
	real_length = m["real_length"]
	stages = m["stages"]
	stages[-1]["end"] = length
	marks = m["marks"]
	towns = m["towns"]
	credit = m["source"]
	for h in m["hairpins"]:
		hairpin_idx.append(index_at(h))
	_near_meta = m["near"]
	_far_meta = m["far"]
	_nat = FileAccess.get_file_as_bytes(MAP_DIR + _near_meta["natural"]).to_float32_array()
	_far = FileAccess.get_file_as_bytes(MAP_DIR + _far_meta["file"]).to_float32_array()
	_tangents()
	return true


func near_grid() -> Dictionary:
	return _near_meta


func far_grid() -> Dictionary:
	return _far_meta


func far_data() -> PackedFloat32Array:
	return _far


func _bilinear(a: PackedFloat32Array, w: int, h: int, fx: float, fz: float) -> float:
	fx = clampf(fx, 0.0, w - 1.001)
	fz = clampf(fz, 0.0, h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * w + ix
	var a00 := a[k]
	var a10 := a[k + 1]
	var a01 := a[k + w]
	var a11 := a[k + w + 1]
	if is_nan(a00) or is_nan(a10) or is_nan(a01) or is_nan(a11):
		return NAN
	return lerpf(lerpf(a00, a10, tx), lerpf(a01, a11, tx), tz)


func far_h(x: float, z: float) -> float:
	var fm := _far_meta
	return _bilinear(_far, int(fm["w"]), int(fm["h"]), (x - fm["ox"]) / fm["cell"], (z - fm["oz"]) / fm["cell"])


func _real_h(x: float, z: float) -> float:
	var nm := _near_meta
	var c: float = nm["cell"]
	var fx: float = x / c - float(nm["gx0"])
	var fz: float = z / c - float(nm["gz0"])
	if fx >= 0.0 and fz >= 0.0 and fx < nm["nx"] - 1 and fz < nm["nz"] - 1:
		var v := _bilinear(_nat, int(nm["nx"]), int(nm["nz"]), fx, fz)
		if not is_nan(v):
			return v
	return far_h(x, z)


## Rewrites far-backdrop heights in a square region: fn(x, z, h) -> h.
func blend_far(centre: Vector3, radius: float, fn: Callable) -> void:
	var fm := _far_meta
	var w := int(fm["w"])
	var hh := int(fm["h"])
	var c: float = fm["cell"]
	var ix0 := maxi(floori((centre.x - radius - fm["ox"]) / c), 0)
	var ix1 := mini(ceili((centre.x + radius - fm["ox"]) / c), w - 1)
	var iz0 := maxi(floori((centre.z - radius - fm["oz"]) / c), 0)
	var iz1 := mini(ceili((centre.z + radius - fm["oz"]) / c), hh - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var k := iz * w + ix
			_far[k] = fn.call(fm["ox"] + ix * c, fm["oz"] + iz * c, _far[k])


## Is p near the river crossing (keeps groves out of the river)?
func near_river(p: Vector3) -> bool:
	if not is_real:
		return absf(p.x - river_centre(p.z)) < 30.0
	var mid: Vector3 = frame_at((marks["bridge_start"] + marks["bridge_end"]) * 0.5).origin
	return Vector2(p.x - mid.x, p.z - mid.z).length() < 70.0


func real_distance(d: float) -> float:
	if not is_real:
		return d / length * 70000.0
	return real_d[index_at(d)]


# ----------------------------------------------------------------------------- turtle
func _emit() -> void:
	pts.append(Vector3(_pos.x, 0.0, _pos.y))
	dist.append(_d)


func _fwd(l: float) -> void:
	var dir := Vector2(cos(_heading), sin(_heading))
	var n := maxi(1, roundi(l / SAMPLE))
	for i in n:
		_pos += dir * (l / n)
		_d += l / n
		_emit()


func _turn(r: float, deg: float) -> void:
	var total := deg_to_rad(deg)
	var arc := r * absf(total)
	var n := maxi(1, roundi(arc / SAMPLE))
	var side := Vector2(-sin(_heading), cos(_heading)) * signf(total)
	var c := _pos + side * r
	var a0 := atan2(_pos.y - c.y, _pos.x - c.x)
	for i in n:
		var a := a0 + total * float(i + 1) / n
		_pos = c + Vector2(cos(a), sin(a)) * r
		_d += arc / n
		_emit()
	_heading += total


func _stage(id: String, title: String, subtitle: String, alt0: float, alt1: float) -> void:
	if not stages.is_empty():
		stages[-1]["end"] = _d
	stages.append({"id": id, "title": title, "subtitle": subtitle, "start": _d, "end": _d,
		"alt0": alt0, "alt1": alt1})


# ----------------------------------------------------------------------------- heights
## Natural ground: flat plains, low foothills, the Nilgiri face, rolling plateau,
## a far massif, and the Bhavani river valley at Mettupalayam.
func natural_h(x: float, z: float, with_river := true) -> float:
	if is_real:
		return _real_h(x, z)
	var n := noise.get_noise_2d(x, z)
	var h := 3.0 * n
	h += smoothstep(face_x0 - 450.0, face_x0, x) * 16.0 * (0.7 + 0.3 * n)
	var t := smoothstep(face_x0, face_x1, x)
	h += t * FACE_RISE
	h += t * (1.0 - t) * 100.0 * noise2.get_noise_2d(x * 2.0, z * 2.0)
	h += smoothstep(face_x1 - 100.0, face_x1 + 600.0, x) * 30.0 * noise2.get_noise_2d(x, z)
	h += smoothstep(face_x1 + 900.0, face_x1 + 5000.0, x) * 520.0 * (0.6 + 0.4 * noise2.get_noise_2d(x * 0.5, z * 0.5))
	# the hills also rise north and south of the plains so the valley reads enclosed
	h += smoothstep(1400.0, 4000.0, absf(z)) * 260.0 * (0.6 + 0.4 * n)
	if with_river:
		h -= 7.0 * (1.0 - smoothstep(10.0, 34.0, absf(x - river_centre(z))))
	return h


func river_centre(z: float) -> float:
	return river_x + 25.0 * sin(z / 90.0)


func _road_heights(gi0: int, gi1: int) -> void:
	var n := pts.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = natural_h(pts[i].x, pts[i].z, false)
	var ha := _mean(raw, gi0, 15)
	var hb := _mean(raw, gi1, 15)
	for i in range(gi0, gi1 + 1):
		raw[i] = lerpf(ha, hb, (dist[i] - dist[gi0]) / (dist[gi1] - dist[gi0]))
	raw = _smooth(_smooth(raw, 15), 15)
	for i in n:
		pts[i].y = raw[i]


func _mean(a: PackedFloat32Array, i: int, w: int) -> float:
	var s := 0.0
	var c := 0
	for k in range(maxi(0, i - w), mini(a.size(), i + w + 1)):
		s += a[k]
		c += 1
	return s / c


func _smooth(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = _mean(a, i, w)
	return out


func _tangents() -> void:
	tangents.resize(pts.size())
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		tangents[i] = Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()


# ----------------------------------------------------------------------------- queries
## Left of travel (India drives on the left).
func left(i: int) -> Vector3:
	var t := tangents[i]
	return Vector3(t.z, 0.0, -t.x)


func index_at(d: float) -> int:
	return _bsearch(d)


func _bsearch(d: float) -> int:
	var lo := 0
	var hi := dist.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if dist[mid] < d:
			lo = mid
		else:
			hi = mid
	return lo


## Position and tangent at distance d, offset sideways (+ = left).
func frame_at(d: float, offset := 0.0) -> Transform3D:
	d = clampf(d, 0.0, length)
	var i := _bsearch(d)
	var j := mini(i + 1, pts.size() - 1)
	var f := 0.0 if j == i else clampf((d - dist[i]) / (dist[j] - dist[i]), 0.0, 1.0)
	var p := pts[i].lerp(pts[j], f)
	var t := tangents[i].lerp(tangents[j], f).normalized()
	var l := Vector3(t.z, 0.0, -t.x)
	# +Z forward, +Y up, +X = left: the vehicles' convention, right-handed
	return Transform3D(Basis(l, Vector3.UP, t), p + l * offset)


## Nearest sample to p, searching around a previous index so switchbacks don't alias.
func nearest(p: Vector3, hint: int, window := 90) -> int:
	var best := hint
	var bd := INF
	for i in range(maxi(0, hint - window), mini(pts.size(), hint + window + 1)):
		var dd := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if dd < bd:
			bd = dd
			best = i
	return best


## Nearest road sample anywhere on the route (coarse scan, then a local refine).
func nearest_global(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in range(0, pts.size(), 8):
		var dd := Vector2(pts[i].x - p.x, pts[i].z - p.z).length_squared()
		if dd < bd:
			bd = dd
			best = i
	return nearest(p, best, 10)


func stage_at(d: float) -> Dictionary:
	for s in stages:
		if d < s["end"]:
			return s
	return stages[-1]


## Real-world altitude for the HUD (the game compresses the climb).
func real_altitude(d: float) -> float:
	if is_real:
		return alt[index_at(d)]
	var s := stage_at(d)
	var f := clampf((d - s["start"]) / maxf(s["end"] - s["start"], 1.0), 0.0, 1.0)
	return lerpf(s["alt0"], s["alt1"], f)


## About 32 °C in Coimbatore to 17 °C in Kotagiri on a misty morning.
static func temperature(alt: float) -> float:
	return 32.0 - (alt - 400.0) / 1400.0 * 15.0
