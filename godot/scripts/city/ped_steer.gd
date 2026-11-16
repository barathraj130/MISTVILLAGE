extends RefCounted
## A person on foot finding their way past what's in it (city_walkers.gd, citizens.gd): anything solid and upright
## ahead (a car parked or going by, a tree, a pole, a bin, a bench, a stall, a wall, a compound wall, a gate: the
## street's furniture is solid to people on foot, city_streamer.gd FOOT_LAYER) and other people. Two rays, at the
## knee (above any kerb) and the chest, along the way they want to go; if something's there, the nearest clear way
## round it (a little to the left first, as people here keep left, then the right, wider each time), or nothing
## (stop: wait for it, or turn back). People: a gentle push apart within a body's width or so, and one coming the
## other way passed on the left.

static var OLD := "--oldsight" in OS.get_cmdline_user_args()   # (testing: only vehicles seen, as before)
const LOOK := 2.4                      # m ahead they look
const TRIES := [0.0, 0.45, -0.45, 0.9, -0.9, 1.35, -1.35]   # radians off the way they want, in this order


## Is (o) a vehicle or something movable (not the ground, a wall, a kerb)?
static func is_vehicle(o, parked_body) -> bool:
	return o != null and (o == parked_body or o is VehicleBody3D or o is RigidBody3D or o is AnimatableBody3D)


## Anything solid ahead of `from` along `dir` within `dist` (the knee, above a kerb, and the chest)? Anything
## upright: a vehicle, the street's furniture, a wall (not the ground rising, a ramp). The hit point, or INF if it's
## clear. (`walls` is kept for the callers: everything upright counts now.)
static func blocked(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, dist: float, parked_body,
		walls := false) -> Vector3:
	for h in [0.65, 1.2]:
		var a: Vector3 = from + Vector3.UP * float(h)
		var q := PhysicsRayQueryParameters3D.create(a, a + dir * dist)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		if is_vehicle(hit["collider"], parked_body) or (absf((hit["normal"] as Vector3).y) < 0.6 and not OLD):
			return hit["position"]
	return Vector3.INF


## The way to go: `want` (flat, normalised) if it's clear, else the nearest clear way round, else
## Vector3.ZERO (nothing clear: stop).
static func steer(space: PhysicsDirectSpaceState3D, from: Vector3, want: Vector3, parked_body, dist := LOOK) -> Vector3:
	for a in TRIES:
		var d: Vector3 = want.rotated(Vector3.UP, a)
		# (aside, they must not step into a wall either: the footpath runs between the buildings and the road)
		if blocked(space, from, d, dist if a == 0.0 else dist * 0.8, parked_body, a != 0.0) == Vector3.INF:
			return d
	return Vector3.ZERO


## Apart from the others (positions, flat) near `at`: a push away from each within `r`, and one coming at them
## (ahead, close to their line) passed on the left of the way they're going.
static func apart(at: Vector3, going: Vector3, others: Array, r := 0.8) -> Vector3:
	var push := Vector3.ZERO
	var left := Vector3(going.z, 0.0, -going.x)
	for o in others:
		var to: Vector3 = (o as Vector3) - at
		to.y = 0.0
		var dd := to.length()
		if dd < 0.01 or dd > maxf(r, 2.2):
			continue
		if dd < r:
			push -= to / dd * (r - dd) / r
		if going.length() > 0.1 and to.dot(going) > 0.0 and absf(to.dot(left)) < 0.6 and dd < 2.2:
			push += left * 0.35 * (2.2 - dd) / 2.2          # (someone in the way ahead: round them on the left)
	return push
