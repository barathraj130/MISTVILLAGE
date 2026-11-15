extends RefCounted
## Hand-to-hand: what each move is, taken from how its clip was made (tools/humans/crowd_clips.py combat section;
## the clips are keyed at 24 frames a second, frame 1 to the last). Nothing here is guessed off a clip: a strike's
## contact is the u its STRIKES entry says the fist arrives, a travelling move's distance and curve are its TRAVEL
## entry's (the body's progress over the feet is smoothstep(u): the game moves him along the same curve, so his
## planted feet don't slide).
##   len      seconds (frames - 1) / 24
##   hit      seconds from the start the fist arrives (a strike); the window is hit - 0.04 .. hit + 0.06
##   hand     the fist that lands ("l"/"r"); bone: a kick's (the ball of the foot, the ankle: the shin's end)
##   dmg      damage (a man's 100; Karthik's hurt, life.gd, 0..100, down at 90)
##   cost     stamina (100)
##   heavy    a heavy blow: it can open a tired guard and put a staggered man down
##   reach    how far ahead of his body's centre the fist gets (m, measured in the game: fighter.gd's miss log); a
##            blow lands with the other man's centre within reach + 0.42 (his body's 0.3 and the fist's 0.12)
##   loops: Guard, GuardLow (out of wind), Block, DownIdle / DownIdleF (lying, breathing), KneelIdle (on one knee),
##            Relief (it's over: hands on his knees), GuardStepF/B/L/R (footwork)
##   travel   [metres, local direction (x: his left, z: ahead)] over the move, smoothstep in u
const FPS := 24.0
const STEP_CYCLE := 16.0 / 24.0          # a GuardStep loop (step and drag)
const STEP_DIST := 0.36                  # covered in a cycle (crowd_clips.py guard_step S)

const MOVES := {
	"Jab":        {"len": 9.0 / FPS,  "hit": 0.4 * 9.0 / FPS,   "hand": "l", "dmg": 7.0,  "cost": 7.0,  "reach": 0.82},
	"Cross":      {"len": 12.0 / FPS, "hit": 0.45 * 12.0 / FPS, "hand": "r", "dmg": 12.0, "cost": 10.0, "reach": 0.76},
	"Hook":       {"len": 13.0 / FPS, "hit": 0.5 * 13.0 / FPS,  "hand": "l", "dmg": 14.0, "cost": 12.0, "reach": 0.6},
	"Heavy":      {"len": 23.0 / FPS, "hit": 0.58 * 23.0 / FPS, "hand": "r", "dmg": 24.0, "cost": 18.0, "reach": 0.78, "heavy": true},
	"JabR":       {"len": 10.0 / FPS, "hit": 0.4 * 10.0 / FPS,  "hand": "r", "dmg": 8.0,  "cost": 8.0,  "reach": 0.74},
	"HookR":      {"len": 13.0 / FPS, "hit": 0.5 * 13.0 / FPS,  "hand": "r", "dmg": 15.0, "cost": 13.0, "reach": 0.6},
	"Uppercut":   {"len": 14.0 / FPS, "hit": 0.55 * 14.0 / FPS, "hand": "r", "dmg": 16.0, "cost": 13.0, "reach": 0.47},
	"FrontKick":  {"len": 15.0 / FPS, "hit": 0.45 * 15.0 / FPS, "bone": "ball_r", "dmg": 10.0, "cost": 12.0, "reach": 0.85},
	"LowKick":    {"len": 14.0 / FPS, "hit": 0.5 * 14.0 / FPS,  "bone": "foot_r", "dmg": 11.0, "cost": 12.0, "reach": 0.7, "low": true},
	"BodyKick":   {"len": 17.0 / FPS, "hit": 0.5 * 17.0 / FPS,  "bone": "foot_r", "dmg": 18.0, "cost": 18.0, "reach": 0.72, "heavy": true},
	"KneeStrike": {"len": 12.0 / FPS, "hit": 0.45 * 12.0 / FPS, "bone": "calf_r", "dmg": 13.0, "cost": 10.0, "reach": 0.4},
	"SideKick":   {"len": 17.0 / FPS, "hit": 0.5 * 17.0 / FPS,  "bone": "foot_r", "dmg": 14.0, "cost": 15.0, "reach": 0.9},
	"Haymaker":   {"len": 28.0 / FPS, "hit": 0.805 * 28.0 / FPS, "hand": "r", "dmg": 16.0, "cost": 16.0, "reach": 0.58, "heavy": true},
	"Block":      {"len": 24.0 / FPS},
	"BlockHit":   {"len": 9.0 / FPS},
	"GuardBreak": {"len": 19.0 / FPS},
	"DodgeL":     {"len": 9.0 / FPS, "cost": 15.0, "travel": [0.55, Vector3(1, 0, 0)]},
	"DodgeR":     {"len": 9.0 / FPS, "cost": 15.0, "travel": [0.55, Vector3(-1, 0, 0)]},
	"DodgeB":     {"len": 9.0 / FPS, "cost": 15.0, "travel": [0.5, Vector3(0, 0, -1)]},
	"StaggerF":   {"len": 13.0 / FPS, "travel": [0.32, Vector3(0, 0, -1)]},
	"StaggerL":   {"len": 13.0 / FPS, "travel": [0.28, Vector3(-1, 0, 0)]},   # (hit from his left: carried to his right)
	"StaggerR":   {"len": 13.0 / FPS, "travel": [0.28, Vector3(1, 0, 0)]},
	"StaggerB":   {"len": 13.0 / FPS, "travel": [0.32, Vector3(0, 0, 1)]},    # (from behind: carried forward)
	"KnockDown":  {"len": 36.0 / FPS},                # onto his back (from in front)
	"FallF":      {"len": 36.0 / FPS},                # onto his front (from behind)
	"FallSide":   {"len": 36.0 / FPS},                # over sideways, ending on his back
	"GetUp":      {"len": 48.0 / FPS, "kneel": 0.6},  # from his back (kneel: the u he's on one knee)
	"GetUpF":     {"len": 48.0 / FPS, "kneel": 0.6},  # from his front
	"Guard":      {"len": 24.0 / FPS},
}
## combinations: after this, a light press in time (from the contact to the end) goes on to that
const COMBO := {"Jab": "Cross", "Cross": "Hook", "Hook": "Uppercut", "Uppercut": "Jab"}
## the counter: a light press just after a blow taken on the guard: a cross that comes through the opening
const COUNTER_WINDOW := 0.45
const COUNTER_BONUS := 1.5


static func smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## How fast the body goes (m/s, local) at u through a travelling move: d/dt of dist * smooth(u).
static func travel_velocity(name: String, u: float) -> Vector3:
	var m: Dictionary = MOVES.get(name, {})
	if not m.has("travel") or u < 0.0 or u > 1.0:
		return Vector3.ZERO
	var tr: Array = m["travel"]
	return (tr[1] as Vector3) * float(tr[0]) * 6.0 * u * (1.0 - u) / float(m["len"])
