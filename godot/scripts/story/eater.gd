extends Node3D
## Eating and drinking, anywhere he sits at a table (the universal eating brief): one controller for home, the
## eateries, the hotel, a tea shop. The place gives it his model (seated, his Sit pose playing), the way he faces and
## what's served (food_kit.gd builds: a plate, a tumbler, a bowl; each with its parts); every bite is built from the
## part's profile (eat_profiles.gd: pinch and dip, tear and dip, mix and scoop, a spoon, a fork, a slice in one hand, a
## burger in two, a tumbler sipped), never from the mission or the dish's name in code.
##
## Under it: eat_ik.gd (the arms as arms move: the elbow's own hinge, the forearm's turn, the wrist within its range;
## the grips; the hand socket that carries the food) and face.gd (the mouth, the lids, blinking).
##
## A bite, its states (each bite uses the ones its profile needs; `state` says which it's in):
##   IDLE → LOOK_AT_FOOD → REACH → GRIP → PREPARE_BITE (tear, break, mix) → PICK_UP → DIP_OR_SCOOP →
##   BRING_TO_MOUTH → BITE_OR_SIP → CHEW_OR_SWALLOW (the hand waits, lowered, until he has swallowed) → RETURN → REST
## The food: taken from the plate at the pick (the plate's part goes down: Kit.bite), held in the fingers (or on the
## spoon, or the thing itself lifted) from the pick to the lips, gone at the bite; a sip lowers the drink. The count
## (eaten / total) is what's actually gone from the table: the place ends the meal on it, not on the animation.
##
##   setup(model, fwd, servings)   servings: [Node3D] from food_kit.gd (their dish ids in each one's "dish" meta)
##   bite(i := -1) → bool          a bite of parts[i] (or the next thing worth eating); false when busy or none left
##   busy() → bool                 mid-bite, chewing or swallowing
##   release()                     done or interrupted: the food and the spoon back on the table, the arms his own
##   mouth() → Vector3             where his lips are (world)
## Signals: bite_taken(part) (something came off the table), bite_done (the hand back at rest), all_eaten.

signal bite_taken(part: Dictionary)
signal bite_done
signal all_eaten

const EatIK := preload("res://scripts/story/eat_ik.gd")
const Kit := preload("res://scripts/story/food_kit.gd")
const Face := preload("res://scripts/story/face.gd")
const Food := preload("res://scripts/story/food.gd")
const Prof := preload("res://scripts/story/eat_profiles.gd")

var model: Node3D
var skel: Skeleton3D
var face
var ik
var fwd := Vector3.FORWARD
var right := Vector3.RIGHT
var servings: Array = []
var parts: Array = []                   # every part of every serving; each knows its "_root" and "_dish"
var plate: Node3D                       # the main serving (where the hands rest by)
var rng := RandomNumberGenerator.new()
var eaten := 0
var total := 0
var plan := {}
var bite_t := -1.0                      # into the bite (s); -1 between bites
var state := "IDLE"
var chew_t := 0.0
var swallow_t := 0.0
var glance_at := Vector3.ZERO           # something across the table to look up at now and then (Amma), or nothing
var hold_clock := false                 # (testing: the bite's clock stopped)
var log_states := false                 # (testing: each state printed as it starts)
var bites_done := 0
var table_y := 0.0                      # the table's top (world y)

var _morsel: MeshInstance3D
var _utensil: Node3D = null             # the spoon or fork in his hand (null: none)
var _utensil_home := {}                 # utensil → [its serving root, its local transform there]
var _lifted: Node3D = null              # a thing lifted whole (a slice, a burger, a tumbler)
var _lift_home := Transform3D()
var _t := 0.0
var _glance := 0.0
var _l_shift := 0.0
var _l_next := 7.0
var _look := Vector3.ZERO
var _aim_from := 2.0
var _lips_local := Vector3.ZERO
var _l_spot := Vector3.ZERO


## Where the left hand rests: on the table to the plate's left, the first spot clear of every katori, bowl and
## tumbler (a meals leaf has a row of katoris where it would otherwise lie).
func _left_spot() -> Vector3:
	var pc := plate.global_position
	for off in [Vector2(0.21, 0.01), Vector2(0.21, 0.09), Vector2(0.27, 0.01), Vector2(0.27, 0.09), Vector2(0.33, 0.04)]:
		var at: Vector3 = Vector3(pc.x, table_y + 0.012, pc.z) - right * off.x + fwd * off.y
		var clear := true
		for root in servings:
			for so in (root.get_meta("solids", []) as Array):
				if str(so.get("kind", "cup")) != "cup":
					continue
				var c: Vector3 = (so["node"] as Node3D).global_transform * (so["at"] as Vector3)
				if Vector2(at.x - c.x, at.z - c.z).length() < float(so["r"]) + 0.075:
					clear = false
		if clear:
			return at
	return Vector3(pc.x, table_y + 0.012, pc.z) - right * 0.33 + fwd * 0.04                    # (a lifted thing: aimed from the moment it's in the hand on)

# the palm's facings (world, by his right): see eat_ik.gd r_palm
func _pd() -> Vector3: return (Vector3.DOWN - right * 0.35).normalized()              # down, a little in: picking
func _pf() -> Vector3: return (-right * 0.85 + Vector3.UP * 0.35).normalized()        # in, thumb up: at his mouth
func _ps() -> Vector3: return (Vector3.DOWN * 0.55 - right * 0.8).normalized()         # a spoon's hand: half turned
func _pw() -> Vector3: return (-right * 0.95 + Vector3.DOWN * 0.1).normalized()        # round a tumbler, from its right


func setup(model_: Node3D, fwd_: Vector3, servings_: Array) -> void:
	model = model_
	fwd = Vector3(fwd_.x, 0.0, fwd_.z).normalized()
	right = fwd.cross(Vector3.UP).normalized()
	skel = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	face = Face.new(model)
	rng.randomize()
	servings = servings_
	plate = servings[0]
	parts.clear()
	total = 0
	eaten = 0
	for root in servings:
		var dish: Dictionary = Food.dish(str(root.get_meta("dish", "")))
		for p in (root.get_meta("parts", []) as Array):
			p["_root"] = root
			p["_dish"] = dish
			parts.append(p)
			total += int(p["bites"])
			eaten += int(p["bites"]) - int(p["left"])       # (a meal taken up again: what's gone stays gone)
		if root.has_meta("utensil"):
			var u: Node3D = root.get_meta("utensil")
			_utensil_home[u] = [root, u.transform]
	table_y = plate.global_position.y
	ik = EatIK.new()
	ik.active = true
	ik.face_fwd = fwd
	skel.add_child(ik)
	ik.wrist_floor = table_y + 0.06
	_lips_local = lips_of(skel)
	ik.lips_local = _lips_local
	_morsel = MeshInstance3D.new()
	_morsel.material_override = StandardMaterial3D.new()
	_morsel.visible = false
	add_child(_morsel)
	_look = plate.global_position
	_l_next = rng.randf_range(6.0, 10.0)
	_l_spot = _left_spot()
	_rest(0.0)


func release() -> void:
	_drop_lifted()
	if _utensil:
		_put_utensil_back()
	if is_instance_valid(_morsel):
		_morsel.visible = false
	if ik and is_instance_valid(ik):
		ik.held = null
		ik.active = false
		ik.queue_free()
	ik = null
	plan = {}
	bite_t = -1.0
	state = "IDLE"


func busy() -> bool:
	return bite_t >= 0.0 or chew_t > 0.0 or swallow_t > 0.0


func plan_k() -> float:
	return clampf(bite_t / float(plan.get("dur", 1.0)), 0.0, 1.0) if bite_t >= 0.0 and not plan.is_empty() else -1.0


func left_count() -> int:
	var n := 0
	for p in parts:
		n += int(p["left"])
	return n


func mouth() -> Vector3:
	if ik and is_instance_valid(ik) and ik.lips_world != Vector3.ZERO:
		return ik.lips_world                             # (measured on the face, carried by the head as it turns)
	var hb := skel.find_bone("head")
	if hb < 0:
		return model.global_position + Vector3.UP * 1.2 + fwd * 0.1
	var g: Transform3D = skel.global_transform * skel.get_bone_global_pose(hb)
	return g * (_lips_local if _lips_local != Vector3.ZERO else Vector3(0, -0.035, 0.103))


## His lips, in the head bone's frame: the middle of the skin the face's "mouth-pursing" shape moves most (the lips
## themselves), at rest. (On Karthik: 3.5 cm under the head bone and 10.3 cm before it; the old guess, 9 cm under,
## was his chin.)
static func lips_of(sk: Skeleton3D) -> Vector3:
	var hb := sk.find_bone("head")
	if hb < 0:
		return Vector3.ZERO
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		if am == null:
			continue
		var idx := -1
		for i in am.get_blend_shape_count():
			if str(am.get_blend_shape_name(i)) == "mouth-pursing":
				idx = i
		if idx < 0:
			continue
		var base: PackedVector3Array = am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bs: Array = am.surface_get_blend_shape_arrays(0)
		if bs.size() <= idx:
			continue
		var tv: PackedVector3Array = bs[idx][Mesh.ARRAY_VERTEX]
		var mx := 0.0
		for i in base.size():
			mx = maxf(mx, (tv[i] - base[i]).length())
		var acc := Vector3.ZERO
		var n := 0
		for i in base.size():
			if (tv[i] - base[i]).length() > mx * 0.5:
				acc += base[i]
				n += 1
		if n == 0:
			continue
		var p := (mi as Node3D).transform * (acc / n)    # (the mesh in the skeleton's space)
		return sk.get_bone_global_rest(hb).affine_inverse() * p
	return Vector3.ZERO


# ---- choosing what to eat ----

## A bite of parts[i] (a side clicked: the main thing dipped in it), or with i = -1 the next thing worth eating: the
## main thing, now and then a sip of the drink, the sides when the rest is gone.
func bite(i := -1) -> bool:
	if busy() or ik == null:
		return false
	var clicked: Dictionary = parts[i] if i >= 0 and i < parts.size() else _next_part()
	if clicked.is_empty() or int(clicked["left"]) <= 0:
		clicked = _next_part()
	if clicked.is_empty():
		return false
	var prof := Prof.profile(clicked, clicked["_dish"])
	var main := clicked
	var dip := {}
	if Prof.is_side(clicked):                            # (a curry clicked: something dipped in it, if there's any)
		var m := _first(func(p): return p["_root"] == clicked["_root"] and not Prof.is_side(p) and int(p["left"]) > 0 \
			and str(Prof.profile(p, p["_dish"])["method"]) in ["tear_dip", "pinch_dip", "mix_scoop"])
		if not m.is_empty():
			main = m
			dip = clicked
			prof = Prof.profile(main, main["_dish"])
	if dip.is_empty() and (prof.get("dip", false) or prof.get("mix", false)) and rng.randf() < 0.85:
		var curries: Array = parts.filter(func(p): return p["_root"] == main["_root"] and Prof.is_side(p) and int(p["left"]) > 0)
		if curries.is_empty():
			curries = parts.filter(func(p): return p["_root"] == main["_root"] and Prof.is_side(p))
		if not curries.is_empty():
			dip = curries[(bites_done + rng.randi_range(0, 1)) % curries.size()]
	plan = _make_plan(main, dip, prof)
	bite_t = 0.0
	return true


func _first(f: Callable) -> Dictionary:
	for p in parts:
		if f.call(p):
			return p
	return {}


func _next_part() -> Dictionary:
	var drinks: Array = parts.filter(func(p): return str(Prof.method_of(p, p["_dish"])).begins_with("sip") and int(p["left"]) > 0)
	var foods: Array = parts.filter(func(p): return not str(Prof.method_of(p, p["_dish"])).begins_with("sip") and not Prof.is_side(p) and int(p["left"]) > 0)
	if not drinks.is_empty() and (foods.is_empty() or (bites_done > 0 and rng.randf() < 0.22)):
		return drinks[0]
	if not foods.is_empty():
		return foods[0]
	var rest: Array = parts.filter(func(p): return int(p["left"]) > 0)
	return rest[0] if not rest.is_empty() else {}


# ---- the bite's plan ----

## Where a part is: its middle, its top, its half width (world), from its mesh's box.
static func shape_of(part: Dictionary) -> Dictionary:
	var n: Node3D = part["node"]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var any := false
	for mi in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if not mi is VisualInstance3D:
			continue
		var bb: AABB = (mi as VisualInstance3D).get_aabb()
		var g: Transform3D = (mi as Node3D).global_transform
		for c in 8:
			var q: Vector3 = g * bb.get_endpoint(c)
			lo = lo.min(q)
			hi = hi.max(q)
			any = true
	if not any:
		var c0 := n.global_position
		return {"c": c0, "top": c0.y + 0.02, "r": 0.03, "lo": c0, "hi": c0}
	var c := (lo + hi) * 0.5
	return {"c": c, "top": hi.y, "r": maxf(hi.x - lo.x, hi.z - lo.z) * 0.5, "lo": lo, "hi": hi}


## Keys: {k, at (the fingertips' or grip's point), f (the fingers' way), p (grip 0..1), palm, s (the state it's in
## on the way to this key)}; optional left-hand keys (la, lf, lpalm, lp) and a held thing's tilt (tilt).
func _key(keys: Array, k: float, at: Vector3, f: Vector3, p: float, palm: Vector3, s: String, extra := {}) -> void:
	var d := {"k": k, "at": at, "f": f.normalized(), "p": p, "palm": palm.normalized(), "s": s}
	d.merge(extra)
	keys.append(d)


func _make_plan(main: Dictionary, dip: Dictionary, prof: Dictionary) -> Dictionary:
	var m := str(prof["method"])
	var up := Vector3.UP
	var lips := mouth()
	var rest := _r_rest()
	var rf := _r_rest_fingers()
	var keys: Array = []
	var ev := {"pick_k": 2.0, "dip_k": 2.0, "in_k": 2.0, "wait_k": 2.0, "drop_k": 2.0, "take_k": 2.0, "put_k": 2.0}
	var jit := func(r: float) -> Vector3: return Vector3(rng.randf_range(-r, r), rng.randf_range(-r * 0.5, r * 0.5), rng.randf_range(-r, r))
	_key(keys, 0.0, rest, rf, 0.15, _pd(), "IDLE")
	_key(keys, 0.05, rest + up * 0.005, rf, 0.15, _pd(), "LOOK_AT_FOOD")
	var k := 0.05
	var left := {}
	var utensil := str(prof.get("utensil", ""))
	# a spoon or fork: picked up from beside the dish first (kept in hand while the bites need it)
	if utensil != "" and _utensil == null:
		var u: Node3D = (main["_root"] as Node3D).get_meta("utensil", null)
		if u:
			var hp := u.global_position + up * 0.026        # (a flat thing taken from above: fingertips down onto its
			var uf := (fwd * 0.5 + Vector3.DOWN * 0.75 - right * 0.35).normalized()   #  handle, the knuckles up)
			_key(keys, k + 0.08, hp + up * 0.04, uf, 0.0, _ps(), "REACH")
			_key(keys, k + 0.13, hp, uf, 0.0, _ps(), "GRIP")
			_key(keys, k + 0.17, hp, uf, 1.0, _ps(), "GRIP")
			ev["take_k"] = k + 0.17
			plan["_take"] = u
			k += 0.19
	elif utensil == "" and _utensil != null:              # (fingers now: the spoon put down first)
		var home: Array = _utensil_home.get(_utensil, [])
		if not home.is_empty():
			var at: Vector3 = (home[0] as Node3D).global_transform * ((home[1] as Transform3D) * ik.aim_local)   # (its bowl's spot)
			_key(keys, k + 0.08, at + up * 0.03, _spoon_f(), 1.0, _ps(), "RETURN")
			_key(keys, k + 0.12, at + up * 0.012, _spoon_f(), 1.0, _ps(), "RETURN")
			_key(keys, k + 0.15, at + up * 0.012, _spoon_f(), 0.0, _ps(), "RETURN")
			ev["put_k"] = k + 0.14
			k += 0.17
	var sh := shape_of(main)
	var c: Vector3 = sh["c"]
	var top := float(sh["top"])
	var r := float(sh["r"])
	var pick_f := (Vector3.DOWN * 0.45 + fwd * 0.75 - right * 0.45).normalized()   # (fingers near level, angled in)
	var to_m := (-fwd * 0.6 + up * 0.55 - right * 0.35).normalized()              # (fingertips up and in to the lips)
	var mouth_palm := _pf()
	var open := 0.3
	var hold_size := 0.012
	var piece := str(prof.get("piece", "lump"))
	match m:
		"tear_dip", "pinch_dip", "scoop", "side_scoop", "mix_scoop":
			# the fingertips at the near edge, on top (a bread's rim, an idli's side), or into the rice's surface
			# its near edge (not over it: the hand never covers the whole thing), at the food's own surface there
			var pp: Vector3 = Vector3(c.x, top, c.z) - fwd * r * 0.75 + right * 0.01 + jit.call(0.004)
			if m in ["scoop", "side_scoop", "mix_scoop"]:
				pp = Vector3(c.x, top, c.z) - fwd * r * 0.3 + jit.call(0.006)
				pick_f = (Vector3.DOWN * 0.65 + fwd * 0.6 - right * 0.4).normalized()
			pp.y = surface_at(sh, pp) + (0.002 if m == "tear_dip" else -0.002)
			if m == "tear_dip":                          # (the left hand holds the bread's far side down)
				left = {"at": Vector3(c.x, top + 0.004, c.z) - right * r * 0.7 + fwd * 0.01, "from": k + 0.06, "to": k + 0.36}
			_key(keys, k + 0.12, pp + up * 0.035 - fwd * 0.02, pick_f, 0.0, _pd(), "REACH")
			_key(keys, k + 0.2, pp, pick_f, 0.0, _pd(), "GRIP")
			if m == "mix_scoop" and not dip.is_empty():   # (the curry poured on, mixed in small rounds, gathered)
				var cs := shape_of(dip)
				var cp: Vector3 = Vector3((cs["c"] as Vector3).x, float(cs["top"]) - 0.004, (cs["c"] as Vector3).z)
				var flat := (Vector3.DOWN * 0.7 + fwd * 0.5 - right * 0.35).normalized()
				_key(keys, k + 0.27, cp + up * 0.03, flat, 0.3, _pd(), "DIP_OR_SCOOP")
				_key(keys, k + 0.31, cp, flat, 0.3, _pd(), "DIP_OR_SCOOP")
				ev["dip_k"] = k + 0.31
				for i in 3:
					var a := float(i) * TAU / 3.0 + rng.randf()
					_key(keys, k + 0.36 + 0.05 * i, pp + (right * cos(a) + fwd * sin(a)) * 0.016, flat, 0.4, _pd(), "PREPARE_BITE")
				k += 0.18
				plan["_mixed"] = true                    # (the curry counted at the mix; no dip after it)
			_key(keys, k + 0.26, pp, pick_f, 1.0, _pd(), "GRIP")
			ev["pick_k"] = k + 0.26
			if m == "tear_dip":                           # (torn: a short pull toward him, the wrist turning a little)
				_key(keys, k + 0.33, pp - fwd * 0.028 + up * 0.012, pick_f, 1.0, (Basis(pick_f, 0.3) * _pd()), "PREPARE_BITE")
				k += 0.07
			elif m == "pinch_dip":                        # (a piece broken off: a small twist and lift)
				_key(keys, k + 0.31, pp + right * 0.008 + up * 0.008, pick_f, 1.0, (Basis(pick_f, -0.2) * _pd()), "PREPARE_BITE")
				k += 0.05
			_key(keys, k + 0.33, keys[-1]["at"] + up * 0.035, pick_f, 1.0, _pd(), "PICK_UP")
			k += 0.33
			if m in ["scoop", "side_scoop", "mix_scoop"]:
				hold_size = 0.016
			else:
				hold_size = float(prof.get("hold", 0.012))
			open = 0.3
		"spoon", "fork":
			# the spoon's bowl into the food: the hand behind it by the spoon's length, the bowl scooping toward him
			var sf := _spoon_f()
			var into: Vector3 = Vector3(c.x, top - 0.006, c.z) - fwd * r * 0.2 + jit.call(0.006)
			var reach := 0.0                              # (the spoon's bowl itself is aimed: eat_ik aim_local)
			_key(keys, k + 0.12, into - sf * reach + up * 0.04, sf, 1.0, _ps(), "REACH")
			_key(keys, k + 0.18, into - sf * reach, sf, 1.0, _ps(), "DIP_OR_SCOOP")
			if m == "fork" and prof.get("twirl", false):  # (the noodles wound on: the wrist turning, twice)
				_key(keys, k + 0.22, into - sf * reach, sf, 1.0, Basis(sf, 0.5) * _ps(), "PREPARE_BITE")
				_key(keys, k + 0.26, into - sf * reach, sf, 1.0, Basis(sf, -0.3) * _ps(), "PREPARE_BITE")
				_key(keys, k + 0.3, into - sf * reach, sf, 1.0, Basis(sf, 0.4) * _ps(), "PREPARE_BITE")
				k += 0.12
			_key(keys, k + 0.23, into - sf * reach - fwd * 0.02 + up * 0.005, sf, 1.0, _ps(), "DIP_OR_SCOOP")
			ev["pick_k"] = k + 0.22
			_key(keys, k + 0.3, into - sf * reach + up * 0.05, sf, 1.0, _ps(), "PICK_UP")
			k += 0.3
			to_m = (-right * 0.85 - fwd * 0.3 + up * 0.15).normalized()   # (across before his chin: the spoon's bowl
			mouth_palm = (Vector3.DOWN * 0.7 - right * 0.45 - fwd * 0.2).normalized()   #  comes in from his right)
			open = 0.26
		"hold_one":                                       # a slice: by its crust, the tip to his mouth
			hold_size = float(prof.get("hold", 0.01))
			var g := _crust_of(main)
			var hf := (fwd * 0.6 + Vector3.DOWN * 0.5 - right * 0.5).normalized()
			_key(keys, k + 0.13, g + up * 0.04 - fwd * 0.02, hf, 0.0, _pd(), "REACH")
			_key(keys, k + 0.2, g + up * 0.006, hf, 0.0, _pd(), "GRIP")
			_key(keys, k + 0.26, g + up * 0.006, hf, 1.0, _pd(), "GRIP")
			ev["pick_k"] = k + 0.26
			_key(keys, k + 0.32, g + up * 0.06, hf, 1.0, _pd(), "PICK_UP")
			k += 0.32
			to_m = (-fwd * 0.5 + up * 0.2 - right * 0.6).normalized()
			mouth_palm = (Vector3.UP * 0.6 - right * 0.8).normalized()   # (palm up under it, carrying it)
			open = 0.42
		"hold_two":                                       # a burger: both hands, the thumbs over, the fingers under
			var side_r: Vector3 = c + right * (r + 0.004) + up * 0.005
			var side_l: Vector3 = c - right * (r + 0.004) + up * 0.005
			var rfh := (-right * 0.7 + fwd * 0.6 + Vector3.DOWN * 0.2).normalized()
			var lfh := (right * 0.7 + fwd * 0.6 + Vector3.DOWN * 0.2).normalized()
			var lp := Vector3(right.x, 0.2, right.z).normalized()
			var rp := Vector3(-right.x, 0.2, -right.z).normalized()
			_key(keys, k + 0.14, side_r + right * 0.03 + up * 0.03, rfh, 0.0, rp, "REACH", {"la": side_l - right * 0.03 + up * 0.03, "lf": lfh, "lpalm": lp, "lp": 0.0})
			_key(keys, k + 0.21, side_r, rfh, 0.0, rp, "GRIP", {"la": side_l, "lf": lfh, "lpalm": lp, "lp": 0.0})
			_key(keys, k + 0.26, side_r, rfh, 1.0, rp, "GRIP", {"la": side_l, "lf": lfh, "lpalm": lp, "lp": 1.0})
			ev["pick_k"] = k + 0.26
			_key(keys, k + 0.33, side_r + up * 0.08, rfh, 1.0, rp, "PICK_UP", {"la": side_l + up * 0.08, "lf": lfh, "lpalm": lp, "lp": 1.0})
			k += 0.33
			open = 0.5
			plan["_two"] = true
			plan["_l_side"] = side_l
		"sip_cup", "sip_glass":                           # the tumbler: the hand round it from its right, lifted
			var cup: Node3D = main.get("lift", main["node"])
			var h := float(main.get("cup_h", 0.08))
			var gp := cup.global_position + up * h * 0.58 + right * 0.035   # (round its middle: the little finger clear
			                                                                  #  of the table)
			var wf := (fwd * 0.75 - right * 0.55).normalized()
			ik.wrist_floor = table_y + 0.01
			_key(keys, k + 0.13, gp + right * 0.04 + up * 0.02, wf, 0.0, _pw(), "REACH")
			_key(keys, k + 0.2, gp, wf, 0.0, _pw(), "GRIP")
			_key(keys, k + 0.25, gp, wf, 1.0, _pw(), "GRIP")
			ev["pick_k"] = k + 0.25
			_key(keys, k + 0.31, gp + up * 0.06, wf, 1.0, _pw(), "PICK_UP")
			k += 0.31
			to_m = (-fwd * 0.3 + up * 0.35 - right * 0.85).normalized()
			mouth_palm = _pw()
			open = 0.12
			plan["_cup_h"] = h
	# a dip: the held piece touched into the side's surface, lightly coated
	if not dip.is_empty() and m in ["tear_dip", "pinch_dip", "scoop"] and not plan.get("_mixed", false):
		var ds := shape_of(dip)
		var dp: Vector3 = Vector3((ds["c"] as Vector3).x, float(ds["top"]) - 0.003, (ds["c"] as Vector3).z) - fwd * float(ds["r"]) * 0.3 + jit.call(0.004)
		var into := (Vector3.DOWN * 0.6 + fwd * 0.65 - right * 0.4).normalized()
		_key(keys, k + 0.08, dp + up * 0.03, into, 1.0, _pd(), "DIP_OR_SCOOP")
		_key(keys, k + 0.14, dp, into, 1.0, _pd(), "DIP_OR_SCOOP")
		ev["dip_k"] = k + 0.14
		if rng.randf() < 0.35:                            # (and stirred round once)
			_key(keys, k + 0.18, dp + right * 0.012 - up * 0.003, into, 1.0, _pd(), "DIP_OR_SCOOP")
		_key(keys, k + 0.22, dp + up * 0.035, into, 1.0, _pd(), "DIP_OR_SCOOP")
		k += 0.22
	# to his mouth: up from below and in front (not over), the food at his lips, in; the fingers let go; the hand
	# lowered a little and waiting while he chews and swallows; back to the plate
	var km := maxf(k + 0.17, 0.55)
	var la := lips
	var hold_off := Vector3.ZERO
	match m:
		"spoon", "fork":
			la = lips + fwd * 0.004                               # (the bowl at the lips: aimed, the hand behind it)
		"hold_one", "hold_two", "sip_cup", "sip_glass":
			la = lips + fwd * 0.006                               # (its tip, its edge, its rim at the lips: aimed)
	var two := {"la": la - right * 0.11, "lf": (right * 0.7 + fwd * 0.6).normalized(), "lpalm": Vector3(right.x, 0.3, right.z).normalized(), "lp": 1.0} if plan.get("_two", false) else {}
	var approach: Vector3 = la + fwd * 0.08 - up * 0.05 + jit.call(0.005)
	if m in ["spoon", "fork"]:
		approach = la + fwd * 0.05 - up * 0.03
	var tilt_up := {"tilt": float(prof.get("tilt", 0.0))} if m.begins_with("sip") else {}
	# (these keys move with his lips as his head moves: kept as offsets from them, resolved every frame)
	_key(keys, km, approach, to_m, 1.0, mouth_palm, "BRING_TO_MOUTH", _with(_with(two, {"la": approach - right * 0.11} if not two.is_empty() else {}), {"lo": approach - lips}))
	_key(keys, km + 0.07, la, to_m, 1.0, mouth_palm, "BITE_OR_SIP", _with(_with(two, tilt_up), {"lo": la - lips}))
	ev["in_k"] = km + 0.07
	var let_go := 0.45 if m in ["tear_dip", "pinch_dip", "scoop", "side_scoop", "mix_scoop"] else 1.0
	_key(keys, km + 0.1, la + fwd * 0.012, to_m, let_go, mouth_palm, "BITE_OR_SIP", _with(_with(two, tilt_up), {"lo": la + fwd * 0.012 - lips}))
	# while he chews: finger food, the hand comes down and rests by the plate, relaxed (no hand hanging in the air);
	# a thing still held (a slice, a burger, a glass, the spoon) is held lowered before his chest
	var held_still := _lifts(m) or m in ["spoon", "fork"]
	var wait_at := lips + fwd * 0.2 - up * 0.22 + right * 0.06 if held_still else rest + up * 0.006
	var wait_f := to_m.lerp(pick_f, 0.6).normalized() if held_still else rf
	var wait_palm := mouth_palm.slerp(_pd(), 0.5) if held_still else _pd()
	if plan.get("_two", false):
		wait_at = lips + fwd * 0.2 - up * 0.2
	_key(keys, km + 0.2, wait_at, wait_f, 0.15 if let_go < 1.0 else 1.0, wait_palm, "CHEW_OR_SWALLOW",
		{"la": wait_at - right * 0.11, "lf": (right * 0.7 + fwd * 0.6).normalized(), "lpalm": Vector3(right.x, 0.3, right.z).normalized(), "lp": 1.0} if plan.get("_two", false) else {})
	ev["wait_k"] = km + 0.2
	# back down: a thing lifted whole is put back where it was; the hand to its rest
	if _lifts(m):
		var home := _lift_target(main)
		var hf: Vector3 = keys[keys.size() - 5]["f"] if keys.size() >= 5 else pick_f
		# (two hands: the left comes down with it to its own side of the thing, not left up at his mouth)
		var lh: Vector3 = plan.get("_l_side", home)
		var two_d := _with(two, {"la": lh + up * 0.05}) if not two.is_empty() else {}
		var two_e := _with(two, {"la": lh}) if not two.is_empty() else {}
		var two_o := _with(two, {"la": lh - right * 0.03 + up * 0.03, "lp": 0.0}) if not two.is_empty() else {}
		_key(keys, km + 0.29, home + up * 0.05, hf, 1.0, keys[2]["palm"] if keys.size() > 2 else _pd(), "RETURN", two_d)
		_key(keys, km + 0.34, home, hf, 1.0, keys[2]["palm"] if keys.size() > 2 else _pd(), "RETURN", two_e)
		ev["drop_k"] = km + 0.34
		_key(keys, km + 0.38, home + up * 0.02, hf, 0.0, _pd(), "RETURN", two_o)
	var end_at: Vector3 = rest + jit.call(0.01)
	if _utensil != null or utensil != "":
		end_at = _spoon_rest()
	_key(keys, 1.0, end_at, rf if utensil == "" else _spoon_f(), 1.0 if utensil != "" else 0.15, _pd() if utensil == "" else _ps(), "REST")
	_vary_timing(keys, ev)
	var dur := float(prof.get("pace", 3.3)) * rng.randf_range(0.9, 1.12)
	var out := {"keys": keys, "dur": dur, "main": main, "dip": dip, "prof": prof, "left": left, "piece": piece,
		"open": open, "hold_size": hold_size, "picked": false, "dipped": false, "gone": false, "dropped": false,
		"taken": false, "put": false}
	out.merge(ev)
	for x in ["_take", "_two", "_cup_h", "_mixed", "_l_side"]:
		if plan.has(x):
			out[x] = plan[x]
	return out


## The food's height at a point over it (a dome's or a mound's surface from its box: highest in the middle, down to
## its foot at the rim), so the fingers meet the food itself, not the air over it or the plate under it.
static func surface_at(sh: Dictionary, at: Vector3) -> float:
	var c: Vector3 = sh["c"]
	var lo: Vector3 = sh["lo"]
	var r := maxf(float(sh["r"]), 0.005)
	var d := Vector2(at.x - c.x, at.z - c.z).length() / r
	return lo.y + (float(sh["top"]) - lo.y) * sqrt(maxf(1.0 - d * d, 0.0)) + 0.003 * (1.0 - clampf(d, 0.0, 1.0))


## Each stage of the bite a little longer or shorter on its own (a reach slower, a lift quicker), not the whole bite
## scaled: the keys' gaps each varied by up to 18 %, then all put back between 0 and 1; the events moved with them.
func _vary_timing(keys: Array, ev: Dictionary) -> void:
	var old: Array = []
	for kk in keys:
		old.append(float(kk["k"]))
	var nk: Array = [0.0]
	for i in range(1, old.size()):
		nk.append(float(nk[i - 1]) + (float(old[i]) - float(old[i - 1])) * rng.randf_range(0.82, 1.18))
	var last: float = nk[-1]
	for i in nk.size():
		nk[i] = float(nk[i]) / maxf(last, 0.001)
		keys[i]["k"] = nk[i]
	for e in ev:                                         # (an event between two keys stays between them)
		var v := float(ev[e])
		if v > 1.0:
			continue
		for i in range(1, old.size()):
			if v <= float(old[i]) + 1e-6:
				var u := (v - float(old[i - 1])) / maxf(float(old[i]) - float(old[i - 1]), 1e-6)
				ev[e] = lerpf(nk[i - 1], nk[i], clampf(u, 0.0, 1.0))
				break


static func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate()
	o.merge(b, true)
	return o


static func _lifts(m: String) -> bool:
	return m in ["hold_one", "hold_two", "sip_cup", "sip_glass"]


## Where the hand puts a lifted thing back down: the grip's point when it was picked up.
func _lift_target(main: Dictionary) -> Vector3:
	var m := str(Prof.method_of(main, main["_dish"]))
	if m.begins_with("sip"):
		var cup: Node3D = main.get("lift", main["node"])
		var h := float(main.get("cup_h", 0.08))
		return cup.global_position + Vector3.UP * h * 0.58 + right * 0.035
	if m == "hold_one":
		return _crust_of(main) + Vector3.UP * 0.006
	var sh := shape_of(main)
	return (sh["c"] as Vector3) + right * (float(sh["r"]) + 0.004) + Vector3.UP * 0.005


## A slice's crust: the point of it furthest from its own tip (the tip toward the plate's middle).
func _crust_of(main: Dictionary) -> Vector3:
	var n: Node3D = main.get("lift", main["node"])
	var tip := n.global_position
	var sh := shape_of(main)
	var c: Vector3 = sh["c"]
	return Vector3(c.x, float(sh["top"]), c.z) + (Vector3(c.x, tip.y, c.z) - tip).normalized() * float(sh["r"]) * 0.6


func _spoon_f() -> Vector3:
	return (fwd * 0.72 + Vector3.DOWN * 0.42 - right * 0.55).normalized()


func _spoon_to_mouth() -> Vector3:
	return (-fwd * 0.8 + Vector3.UP * 0.25 - right * 0.5).normalized()


func _spoon_rest() -> Vector3:                         # (held between bites: its bowl or tines just over the plate's
	return plate.global_position + right * 0.1 - fwd * 0.02 + Vector3.UP * 0.07   #  right side, the hand off the table)


## The right hand at rest: by the plate on the table, nearly flat (palm down, the fingers just curled, their tips
## touching the table), not hovering and not pressed into it.
func _r_rest() -> Vector3:
	return Vector3(0, table_y, 0) + _flat(plate.global_position + right * 0.19 - fwd * 0.02) + Vector3.UP * 0.012


func _r_rest_fingers() -> Vector3:
	return (fwd * 0.88 + Vector3.DOWN * 0.14 - right * 0.3).normalized()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _plan_at(k: float) -> Dictionary:
	var keys: Array = plan["keys"]
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if k <= float(b["k"]) or i == keys.size() - 2:
			var u := clampf((k - float(a["k"])) / maxf(float(b["k"]) - float(a["k"]), 0.001), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			var pa: Vector3 = (mouth() + (a["lo"] as Vector3)) if a.has("lo") else a["at"]
			var pb: Vector3 = (mouth() + (b["lo"] as Vector3)) if b.has("lo") else b["at"]
			var o := {"at": pa.lerp(pb, u), "f": (a["f"] as Vector3).slerp(b["f"], u).normalized(),
				"p": lerpf(a["p"], b["p"], u), "palm": (a["palm"] as Vector3).slerp(b["palm"], u).normalized(), "s": b["s"],
				"tilt": lerpf(float(a.get("tilt", 0.0)), float(b.get("tilt", 0.0)), u)}
			if a.has("la") and b.has("la"):
				o["la"] = (a["la"] as Vector3).lerp(b["la"], u)
				o["lf"] = (a["lf"] as Vector3).slerp(b["lf"], u).normalized()
				o["lpalm"] = (a["lpalm"] as Vector3).slerp(b["lpalm"], u).normalized()
				o["lp"] = lerpf(a["lp"], b["lp"], u)
			elif b.has("la") and u > 0.0:                 # (the left hand coming in: from its rest to the first key)
				o["la_in"] = [b, u]
			return o
	var last: Dictionary = keys[-1]
	return {"at": last["at"], "f": last["f"], "p": last["p"], "palm": last["palm"], "s": last["s"], "tilt": 0.0}


# ---- each frame ----

func _process(dt: float) -> void:
	if ik == null or not is_instance_valid(ik):
		return
	_solids()
	_t += dt
	_rest(dt)
	if bite_t >= 0.0 and not plan.is_empty():
		_bite_step(dt)
	_face_step(dt)


## The solids for eat_ik.gd's contact pass, where they are now: the table's top; each serving's plate, katoris,
## bowl, tumbler (food_kit.gd's "solids"; a lifted tumbler with it); the food on the plate as soft domes (only the
## palm and the knuckles kept out of it).
func _solids() -> void:
	var sl: Array = [{"kind": "plane", "y": table_y - 0.002}]
	for root in servings:
		if not is_instance_valid(root):
			continue
		for so in (root.get_meta("solids", []) as Array):
			var n: Node3D = so["node"]
			if not is_instance_valid(n):
				continue
			sl.append({"kind": str(so.get("kind", "cyl")), "c": n.global_transform * (so["at"] as Vector3), "r": so["r"], "h": so["h"], "node": n})
	for p in parts:
		if int(p["left"]) <= 0 or Prof.is_side(p) or p.has("lift"):
			continue
		var n2: Node3D = p["node"]
		if not is_instance_valid(n2) or not n2.visible:
			continue
		var sh := shape_of(p)
		var lo: Vector3 = sh["lo"]
		sl.append({"kind": "dome", "c": Vector3((sh["c"] as Vector3).x, lo.y, (sh["c"] as Vector3).z), "r": float(sh["r"]) * 0.85,
			"h": float(sh["top"]) - lo.y})
	ik.solids = sl
	ik.held_solid = _lifted


func _set_state(s: String) -> void:
	if s != state:
		state = s
		if log_states:
			print("EAT state %-16s k=%.2f %s" % [s, plan_k(), str(plan.get("prof", {}).get("method", ""))])


func _bite_step(dt: float) -> void:
	var k := plan_k()
	var waiting := k >= float(plan["wait_k"]) and (chew_t > 0.0 or swallow_t > 0.0)
	if not hold_clock and not waiting:
		bite_t += dt
	k = plan_k()
	var at := _plan_at(k)
	var p: Vector3 = at["at"]
	if not _lifts(str(plan["prof"]["method"])) and str(plan["prof"]["method"]) not in ["spoon", "fork"] and p.y < table_y + 0.012:
		p.y = table_y + 0.012                             # (the fingertips above the plate, always)
	ik.r_at = p
	ik.r_fingers = at["f"]
	ik.pinch = at["p"]
	ik.r_palm = at["palm"]
	ik.r_grip = str(plan["prof"].get("grip", "pinch"))
	ik.hold_size = float(plan.get("hold_size", 0.012))
	ik.held_tilt = at["tilt"]
	_set_state("CHEW_OR_SWALLOW" if waiting else str(at["s"]))
	var mk := float(plan["in_k"]) - 0.07
	ik.lean_in = lerpf(ik.lean_in, 0.07 if k < mk - 0.1 else 0.035, 1.0 - exp(-dt * 4.0))
	var look := (at["at"] as Vector3) if k < mk - 0.06 else mouth() + fwd * 1.0 + Vector3.DOWN * 0.3
	_look = _look.lerp(look, 1.0 - exp(-dt * 6.0))
	ik.look_at_pt = _look
	# the left hand: its keys when it has a part (a burger), else holding the bread, else resting
	if at.has("la"):
		ik.l_at = at["la"]
		ik.l_fingers = at["lf"]
		ik.l_palm = at["lpalm"]
		ik.l_pinch = at["lp"]
		ik.l_grip = "hold"
	elif at.has("la_in"):
		var b: Dictionary = at["la_in"][0]
		var u: float = at["la_in"][1]
		ik.l_at = ik.l_at.lerp(b["la"], u)
		ik.l_fingers = ik.l_fingers.slerp(b["lf"], u).normalized()
		ik.l_palm = ik.l_palm.slerp(b["lpalm"], u).normalized()
		ik.l_pinch = lerpf(0.0, float(b["lp"]), u)
		ik.l_grip = "hold"
	_events(k)
	if _lifted != null and not ik.request_keep:
		ik.aim_on = k >= _aim_from and k < float(plan.get("drop_k", 2.0)) - 0.06
	if k >= 1.0:
		bite_t = -1.0
		plan = {}
		bites_done += 1
		_set_state("REST")
		ik.wrist_floor = table_y + 0.06
		if rng.randf() < 0.3:
			_glance = rng.randf_range(0.8, 1.4)
		bite_done.emit()
		if left_count() <= 0:
			all_eaten.emit()


func _events(k: float) -> void:
	var main: Dictionary = plan["main"]
	var m := str(plan["prof"]["method"])
	if not plan["taken"] and k >= float(plan["take_k"]) and plan.has("_take"):
		plan["taken"] = true
		_take_utensil(plan["_take"], str((main["_root"] as Node3D).get_meta("utensil_kind", "spoon")))
	if not plan["put"] and k >= float(plan["put_k"]) and _utensil != null:
		plan["put"] = true
		_put_utensil_back()
	if not plan["picked"] and k >= float(plan["pick_k"]):
		plan["picked"] = true
		match m:
			"hold_one", "hold_two", "sip_cup", "sip_glass":     # the thing itself lifted
				_lifted = main.get("lift", main["node"])
				_lift_home = _lifted.transform
				ik.held = _lifted
				ik.held_mode = "keep" if m == "hold_one" else ("both" if m == "hold_two" else "upright")
				ik.request_keep = true
				# what's aimed from now (the keys after the pick are its targets): a slice's tip, a burger's near
				# edge, a tumbler's near rim (the dish's local +Z is toward him)
				match m:
					"hold_one":
						ik.aim_local = Vector3(0, 0.006, 0.0)
					"hold_two":
						ik.aim_local = Vector3(0, 0.03, 0.05)
					_:
						ik.aim_local = Vector3(0, float(main.get("cup_h", 0.08)), 0.024)
				_aim_from = k
			_:
				var col := Kit.bite(main)                      # a piece off it: the plate has less on it
				_count(main)
				var mm := _morsel.material_override as StandardMaterial3D
				mm.albedo_color = col
				_morsel.mesh = _piece_mesh(str(plan["piece"]), main)
				_morsel.scale = Vector3.ONE * rng.randf_range(0.9, 1.1)
				_morsel.visible = true
				if _utensil != null:                           # (on the spoon's bowl, the fork's tines)
					_morsel.reparent(_utensil, false)
					_morsel.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0.006))
					ik.held = _utensil
				else:
					if _morsel.get_parent() != self:
						_morsel.reparent(self, false)
					ik.held = _morsel
					ik.held_mode = "pinch"
					ik.held_basis = Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
					ik.held_offset = Vector3.ZERO
	if not plan["dipped"] and k >= float(plan["dip_k"]) and not (plan["dip"] as Dictionary).is_empty():
		plan["dipped"] = true
		var dp: Dictionary = plan["dip"]
		var mm := _morsel.material_override as StandardMaterial3D
		mm.albedo_color = mm.albedo_color.lerp(dp["colour"], 0.55)   # (coated)
		if int(dp["left"]) > 0 and (bites_done % 2 == 1 or plan.get("_mixed", false)):
			Kit.bite(dp)                                       # (the katori's level goes down every other dip)
			_count(dp)
	if not plan["gone"] and k >= float(plan["in_k"]) - 0.005:      # at his lips: in (a bite off it, a sip)
		plan["gone"] = true
		match m:
			"hold_one", "hold_two", "sip_cup", "sip_glass":
				Kit.bite(main)
				_count(main)
			_:
				_morsel.visible = false
				if _utensil == null:
					ik.held = null
					ik.held_mode = ""
		var ch: Array = plan["prof"].get("chew", [1.4, 2.2])
		chew_t = rng.randf_range(float(ch[0]), float(ch[1]))
		swallow_t = 0.0 if chew_t > 0.0 else 0.45
	if not plan["dropped"] and k >= float(plan["drop_k"]):
		plan["dropped"] = true
		_drop_lifted()


func _count(part: Dictionary) -> void:
	eaten += 1
	bite_taken.emit(part)


func _drop_lifted() -> void:
	if ik and is_instance_valid(ik) and _utensil == null:
		ik.aim_on = false
	if _lifted and is_instance_valid(_lifted):
		_lifted.transform = Transform3D(_lift_home.basis.orthonormalized() * Basis.from_scale(_lifted.scale), _lift_home.origin)
	_lifted = null
	if ik and is_instance_valid(ik) and _utensil == null:
		ik.held = null
		ik.held_mode = ""


func _take_utensil(u: Node3D, kind: String) -> void:
	_utensil = u
	ik.held = u
	ik.held_mode = "pinch"
	ik.aim_local = Vector3(0, 0.105, 0.004) if kind == "fork" else Vector3(0, 0.1, 0.004)   # (the tines, the bowl)
	ik.aim_on = true
	# (as a spoon is held: the handle across the hand from under the heel of the thumb, out of the web between the
	#  thumb and the index, the bowl beyond them toward the thumb's side; its hollow up off the back of the hand)
	var pn: Vector3 = (ik.PALM_N["r"] as Vector3).normalized()
	var ts := Vector3(0.73, 0.0, 0.6)                     # (the thumb's side, in the hand's frame: measured from the rig)
	ts = (ts - pn * ts.dot(pn)).normalized()
	var y := (Vector3(0, 1, 0) * 0.5 + ts * 0.85)
	y = (y - pn * y.dot(pn)).normalized()
	var z := -pn
	ik.held_basis = Basis(y.cross(z).normalized(), y, z)
	ik.held_offset = -y * 0.035


func _put_utensil_back() -> void:
	if _utensil == null:
		return
	var home: Array = _utensil_home.get(_utensil, [])
	if not home.is_empty() and is_instance_valid(home[0]):
		_utensil.transform = home[1]
	for c in _utensil.get_children():                     # (whatever was on it, eaten by now)
		if c == _morsel:
			_morsel.visible = false
			_morsel.reparent(self, false)
	if ik and is_instance_valid(ik) and ik.held == _utensil:
		ik.held = null
		ik.held_mode = ""
		ik.aim_on = false
	_utensil = null


## The piece in his fingers, a bite-sized portion of what it was taken from.
func _piece_mesh(kind: String, _src: Dictionary) -> Mesh:
	match kind:
		"torn":
			return torn_piece(rng)
		"ball":
			var r := SphereMesh.new()
			r.radius = 0.011
			r.height = 0.017
			return r
		"spoonful":
			var s := SphereMesh.new()
			s.radius = 0.011
			s.height = 0.009
			return s
		_:
			var l := SphereMesh.new()
			l.radius = 0.011
			l.height = 0.015
			return l


## A torn bit of bread (poori, dosa, chapati): a small irregular piece, about 2 x 1.7 cm and 4-6 mm thick (a puffed
## poori's two layers), its rim ragged (seven to ten points at uneven distances, one side straighter where it was the
## bread's own edge), a little thicker in the middle, slightly curled. Centred on the origin, flat in XZ.
static func torn_piece(r_: RandomNumberGenerator) -> ArrayMesh:
	var n := r_.randi_range(7, 10)
	var rim: Array[Vector3] = []
	var a0 := r_.randf() * TAU
	for i in n:
		var a := a0 + TAU * (float(i) + r_.randf_range(-0.3, 0.3)) / float(n)
		var r := r_.randf_range(0.007, 0.012)
		if absf(wrapf(a - a0, -PI, PI)) < 0.6:
			r = 0.011 / maxf(cos(wrapf(a - a0, -PI, PI)), 0.8)
		rim.append(Vector3(cos(a) * r * 1.1, 0.0, sin(a) * r * 0.92))
	var th := r_.randf_range(0.004, 0.006)
	var curl := r_.randf_range(4.0, 9.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := func(v: Vector3, y: float) -> Vector3:
		return Vector3(v.x, y - curl * v.x * v.x, v.z)
	for i in n:
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % n]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, th * 0.75, 0))
		st.add_vertex(top.call(b, th * 0.5))
		st.add_vertex(top.call(a, th * 0.5))
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(0, -th * 0.5, 0))
		st.add_vertex(top.call(a, -th * 0.4))
		st.add_vertex(top.call(b, -th * 0.4))
		var out := ((a + b) * 0.5).normalized()
		st.set_normal(out)
		st.add_vertex(top.call(a, th * 0.5))
		st.add_vertex(top.call(b, th * 0.5))
		st.add_vertex(top.call(b, -th * 0.4))
		st.add_vertex(top.call(a, th * 0.5))
		st.add_vertex(top.call(b, -th * 0.4))
		st.add_vertex(top.call(a, -th * 0.4))
	return st.commit()


# ---- between bites, and the face ----

## The hands at rest between bites: the right by the plate's edge (or holding the spoon above it), the left flat on
## its side of the plate (now and then to the rim, steadying it; on the bread for the tear; on the bowl's rim for a
## spoon), both breathing a little; the eyes on the plate, while chewing half up, now and then across the table.
func _rest(dt: float) -> void:
	var drift := Vector3(sin(_t * 0.7) * 0.004, 0.0, cos(_t * 0.5) * 0.004)
	var pc := plate.global_position
	var l_rest := _l_spot + drift                         # (on the table, flat, clear of the katoris)
	_l_next -= dt
	if _l_next <= 0.0 and _l_shift <= 0.0:
		_l_shift = rng.randf_range(1.2, 2.0)
		_l_next = rng.randf_range(7.0, 13.0)
	if _l_shift > 0.0:
		_l_shift -= dt
		l_rest = l_rest.lerp(pc - right * 0.14 + Vector3.UP * 0.02, sin(clampf(_l_shift / 1.6, 0.0, 1.0) * PI))
	if bite_t >= 0.0 and not plan.is_empty():
		var lft: Dictionary = plan.get("left", {})
		var k := plan_k()
		if not lft.is_empty():
			var on := smoothstep(float(lft["from"]), float(lft["from"]) + 0.06, k) * (1.0 - smoothstep(float(lft["to"]), float(lft["to"]) + 0.08, k))
			l_rest = l_rest.lerp(lft["at"], on)           # (fingers on the bread, holding it down)
		elif str(plan["prof"].get("left", "rest")) == "hold_bowl":
			var root_: Node3D = (plan["main"] as Dictionary)["_root"]
			l_rest = root_.global_position - right * 0.16 + Vector3.UP * 0.012   # (fingers on the plate's rim, by the bowl)
	ik.l_at = l_rest
	ik.l_fingers = (fwd * 0.9 + Vector3.DOWN * 0.1 + right * 0.25).normalized()
	ik.l_palm = (Vector3.DOWN + right * 0.15).normalized()
	ik.l_pinch = 0.0
	ik.l_grip = "pinch"
	if bite_t < 0.0:
		var holding := _utensil != null
		ik.r_palm = _ps() if holding else _pd()
		ik.r_at = (_spoon_rest() if holding else _r_rest()) + drift * 0.6
		ik.r_fingers = _spoon_f() if holding else _r_rest_fingers()
		ik.r_grip = "spoon" if holding else "pinch"
		ik.pinch = 1.0 if holding else 0.15
		ik.lean_in = lerpf(ik.lean_in, 0.03 + 0.012 * sin(_t * TAU * 0.24), 1.0 - exp(-dt * 3.0))   # (breathing)
		var ahead := mouth() + fwd * 1.2 + Vector3.DOWN * 0.45
		if _glance > 0.0:
			_glance -= dt
			if glance_at != Vector3.ZERO:
				ahead = glance_at
		_look = _look.lerp(ahead if chew_t > 0.0 or _glance > 0.0 else pc, 1.0 - exp(-dt * 2.5))
		ik.look_at_pt = _look


func _face_step(dt: float) -> void:
	if face == null or not face.has_face():
		return
	var want := {}
	var k := plan_k()
	var near_bite := false
	if k >= 0.0:
		var ik_ := float(plan["in_k"])
		var o := float(plan["open"])
		# open a little before the food arrives, held open as it goes in, closed on it at the bite
		var op := o * smoothstep(ik_ - 0.1, ik_ - 0.03, k) * (1.0 - smoothstep(ik_ + 0.005, ik_ + 0.04, k))
		if op > 0.0:
			want["mouth-open"] = op
			near_bite = true
		if k >= ik_ and k < ik_ + 0.06:
			want["mouth-pursing"] = 0.28 * (1.0 - smoothstep(ik_ + 0.03, ik_ + 0.06, k))   # (the lips closing on it)
		if k < ik_ - 0.12:
			want["eye-left-slit"] = 0.3                    # (the lids down, looking at his food)
			want["eye-right-slit"] = 0.3
	if not near_bite and chew_t > 0.0:
		chew_t -= dt
		var c := 0.5 + 0.5 * sin(_t * TAU * 1.7)
		want["mouth-open"] = 0.035 + 0.055 * c             # (the jaw going, the lips together)
		want["mouth-compression"] = 0.12 + 0.08 * (1.0 - c)
		want["mouth-corner-puller"] = 0.03 * c
		want["eye-left-slit"] = 0.15
		want["eye-right-slit"] = 0.15
		if chew_t <= 0.0:
			swallow_t = 0.4
	elif not near_bite and swallow_t > 0.0:
		swallow_t -= dt
		want["mouth-compression"] = 0.4                    # (the swallow)
		want["mouth-corner-puller"] = 0.08
	face.pose(want)
	face.update(dt)
