extends RefCounted
## What the ground is, for tyres and for feet alike (OPEN_WORLD_PLAN phase 6: one surface table). The city's
## collision shapes say what they are (city_streamer.gd _shape: "surface" meta: asphalt, concrete, gravel, earth,
## mud, shoulder, ground); jeep.gd reads the tyres' grip and drag here, gait.gd what it is underfoot (with the
## weather's wet: earth and open ground turn to mud, a road to a wet road) and how that changes his pace.
## (Wet roads take grip from tyres in jeep.gd's own weather term, as before: this table is the dry ground.)

## Tyres: grip (× the tyre's own), drag (N per tonne at speed: sinking, rolling through it).
const TYRE := {
	"asphalt": [1.0, 0.0],
	"concrete": [1.0, 0.0],
	"gravel": [0.65, 40.0],
	"earth": [0.85, 25.0],         # a village road's packed earth: nearly a road's grip
	"mud": [0.4, 100.0],
	"shoulder": [0.85, 160.0],
}
const TYRE_ELSE := [0.62, 420.0]   # open ground, a field

## Feet: his pace (× what he means to go), how quickly he gets going and stops (×), the step's sound.
const FOOT := {
	"asphalt": {"pace": 1.0, "accel": 1.0, "stop": 1.0},
	"concrete": {"pace": 1.0, "accel": 1.0, "stop": 1.0},
	"wet_road": {"pace": 1.0, "accel": 1.0, "stop": 0.85},    # careful stopping; no slipping
	"grass": {"pace": 0.96, "accel": 1.0, "stop": 1.0},
	"earth": {"pace": 0.95, "accel": 1.0, "stop": 1.0},
	"sand": {"pace": 0.88, "accel": 0.7, "stop": 1.0},        # gravel and sand: slow to push off
	"mud": {"pace": 0.8, "accel": 0.65, "stop": 0.8},
}


static func tyre(kind: String) -> Array:
	return TYRE.get(kind, TYRE_ELSE)


## The ground under his feet, from the collision's kind and how wet it is (0..1).
static func foot(kind: String, wet: float) -> String:
	match kind:
		"ground":
			return "mud" if wet > 0.5 else "grass"
		"earth", "shoulder":
			return "mud" if wet > 0.5 else "earth"
		"gravel":
			return "sand"
		"mud":
			return "mud"
		"asphalt", "concrete":
			return "wet_road" if wet > 0.35 else kind
	return "concrete"


static func foot_of(kind: String) -> Dictionary:
	return FOOT.get(kind, FOOT["concrete"])
