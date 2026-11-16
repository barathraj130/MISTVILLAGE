extends RefCounted
## One place for how the world's movable things behave (docs/PHYSICS_AND_BIKE_PLAN_2026-11-16.md A1): every builder
## names a thing by its kind (tools/story_rooms.py Move_<kind>_<n>; city rooms the same) and this says what it is:
## its mass, how it slides on a floor, how quickly it settles; static things (walls, counters, almirahs, desks) are
## never here. New kinds of object get a line here, not new physics code.
##   kind      mass kg   friction (on tile)   damping (linear, angular)   what he can do
const PROFILES := {
	"chair":       {"mass": 7.0,  "friction": 0.3,  "damp": 1.2, "adamp": 4.0, "push": true},   # office chair on castors, plastic chair
	"stool":       {"mass": 3.0,  "friction": 0.45, "damp": 1.5, "adamp": 4.0, "push": true},
	"bin":         {"mass": 2.0,  "friction": 0.5,  "damp": 1.5, "adamp": 3.0, "push": true},   # a plastic dustbin
	"box":         {"mass": 4.0,  "friction": 0.55, "damp": 1.8, "adamp": 4.0, "push": true},   # a carton
	"crate":       {"mass": 18.0, "friction": 0.6,  "damp": 2.0, "adamp": 5.0, "push": true},   # a wooden crate
	"table_small": {"mass": 12.0, "friction": 0.5,  "damp": 2.0, "adamp": 5.0, "push": true},
	"drum":        {"mass": 25.0, "friction": 0.6,  "damp": 2.5, "adamp": 5.0, "push": true},   # a plastic drum, part full
}
const DEFAULT := "box"


static func of(kind: String) -> Dictionary:
	return PROFILES.get(kind, PROFILES[DEFAULT])


## A rigid body set up as its kind (mass, a shared physics material per kind, damping, sleeping when at rest).
static var _mats := {}


static func apply(rb: RigidBody3D, kind: String) -> void:
	var p := of(kind)
	rb.mass = float(p["mass"])
	if not _mats.has(kind):
		var m := PhysicsMaterial.new()
		m.friction = float(p["friction"])
		m.bounce = 0.0
		_mats[kind] = m
	rb.physics_material_override = _mats[kind]
	rb.linear_damp = float(p["damp"])
	rb.angular_damp = float(p["adamp"])
	rb.can_sleep = true
	rb.set_meta("movable", kind)
