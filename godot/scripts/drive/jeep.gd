extends VehicleBody3D
## Your car: a premium mid-size SUV in the style of the Mahindra XUV700 (no badges or logos):
## long sleek body, black roof with rails, big black grille with chrome slats, C-shaped LED
## daytime running lights, split tail lamps, flush door handles, 18" alloys. Right-hand drive,
## keeps left. Inside: a dual-screen dashboard with a digital speed/RPM readout, a steering
## wheel that turns, and a live rear-view mirror.
##
## Driving is tuned like Euro Truck Simulator: steering ramps in gently, is speed-sensitive and
## self-centres; throttle and brakes ramp too; a calm, heavy body with soft suspension.
## (The file keeps its old name, jeep.gd, so the rest of the game needs no changes.)

const Dents := preload("res://scripts/drive/dents.gd")
const Prof := preload("res://scripts/drive/prof.gd")
const MB := preload("res://scripts/drive/mesh_builder.gd")
const RiderPose := preload("res://scripts/drive/rider_pose.gd")
const Fleet := preload("res://scripts/drive/fleet.gd")
const CockpitKit := preload("res://scripts/drive/cockpit.gd")
const CarScreens := preload("res://scripts/drive/car_screens.gd")
## where the wipers park (centre of their pivots) and how long they are, per vehicle
const WIPERS := {"luxury_suv": [Vector3(0, 1.12, 1.06), 0.62], "coupe": [Vector3(0, 0.84, 0.74), 0.5],
	"xuv": [Vector3(0, 1.2, 1.22), 0.6], "hatchback": [Vector3(0, 0.9, 0.9), 0.52], "sedan": [Vector3(0, 0.9, 0.96), 0.52],
	"taxi": [Vector3(0, 0.9, 0.96), 0.52], "bus": [Vector3(0, 1.62, 5.18), 1.0], "lorry": [Vector3(0, 1.98, 4.42), 0.9]}
const FWD := 1.0                   # VehicleBody3D drives along +Z with positive engine force
const BRAKE := 55.0
const MAX_STEER := 0.6             # at a crawl; shrinks with speed
const HIGH_SPEED_STEER := 0.045    # at ~110 km/h
## Steering sensitivity, 0.4 (very calm) … 1.5 (quick). [ and ] change it in the game; it's saved.
static var steer_sens := 0.7
const TOP_SPEED := 44.0            # m/s ≈ 160 km/h, governed
const DRIVER_SEAT := Vector3(-0.42, 1.5, -0.08)    # right-hand seat (+X is the car's left)
## The player's sports coupe, built in Blender by tools/coupe.py → tools/export_coupe.py.
## Without it (or with --xuv) the procedural XUV-style SUV below is used instead.
const COUPE := "res://assets/vehicles/coupe.glb"
const COUPE_CABIN := Vector3(0, -0.12, -0.15)       # cockpit parts sit lower and further back
# 6-speed diesel automatic: 450 N·m from 1,600–2,800 rpm
const RATIOS := [4.46, 2.61, 1.66, 1.24, 1.0, 0.83]
const REVERSE := 4.0
const FINAL := 3.6
const WHEEL_R := 0.36
const IDLE := 780.0
const REDLINE := 4500.0

## What drives each kind of vehicle (tunable, measured in tests/vehicle_lab.gd, not claims about real models):
##   torque   the engine's curve, [rpm, N·m] points (straight lines between)
##   ratios   the gears (overall with "final"); "cvt": [low, high] overall ratios, the engine held near its best
##   idle, redline, up   rpm; up: the upshift point at light and at full throttle
##   brake_g  full braking, in g (scaled to the mass: a bus and a hatchback stop as they weigh)
##   cda      drag area (Cd × frontal m²): air drag ½ρ·CdA·v²;  crr: rolling resistance × weight
##   grip     tyre friction (VehicleWheel3D's friction slip); wet and off-road scale it
##   wet_k    how much of the wet's loss these tyres feel (1 a car's; a scooter's narrow small tyres more)
const DRIVE := {
	"diesel_suv": {"torque": [[780.0, 220.0], [1600.0, 450.0], [2800.0, 450.0], [4500.0, 300.0]], "ratios": [4.46, 2.61, 1.66, 1.24, 1.0, 0.83],
		"final": 3.6, "reverse": 4.0, "idle": 780.0, "redline": 4500.0, "up": [2000.0, 3600.0], "brake_g": 0.85, "cda": 0.95, "crr": 0.015, "grip": 4.6},
	"petrol_car": {"torque": [[800.0, 70.0], [2000.0, 100.0], [4200.0, 113.0], [6200.0, 95.0]], "ratios": [3.55, 1.95, 1.29, 0.97, 0.78],
		"final": 4.1, "reverse": 3.5, "idle": 800.0, "redline": 6200.0, "up": [2600.0, 5600.0], "brake_g": 0.85, "cda": 0.65, "crr": 0.013, "grip": 4.6,
		"rear_grip": 1.08},
	"sport": {"torque": [[800.0, 250.0], [1800.0, 420.0], [5000.0, 420.0], [6800.0, 330.0]], "ratios": [3.8, 2.3, 1.6, 1.25, 1.0, 0.82],
		"final": 3.5, "reverse": 3.5, "idle": 850.0, "redline": 6800.0, "up": [2800.0, 6200.0], "brake_g": 0.95, "cda": 0.6, "crr": 0.012, "grip": 5.0,
		"rear_grip": 0.94},
	"auto": {"torque": [[1200.0, 8.0], [3000.0, 12.5], [5000.0, 12.0], [6500.0, 9.0]], "ratios": [3.9, 2.4, 1.6, 1.15],
		"final": 8.5, "reverse": 3.9, "idle": 1200.0, "redline": 6500.0, "up": [3500.0, 5800.0], "brake_g": 0.6, "cda": 1.2, "crr": 0.02, "grip": 4.0},
	"scooter": {"torque": [[1500.0, 6.0], [5000.0, 8.8], [7500.0, 8.0], [9000.0, 6.0]], "cvt": [22.0, 8.0], "rpm_band": [3200.0, 7000.0],
		"final": 1.0, "reverse": 0.0, "idle": 1500.0, "redline": 9000.0, "up": [0.0, 0.0], "brake_g": 0.7, "cda": 0.6, "crr": 0.015, "grip": 4.0,
		"wet_k": 1.55},
	"bike": {"torque": [[1500.0, 6.0], [4000.0, 11.0], [7000.0, 13.0], [9500.0, 11.0]], "ratios": [14.5, 9.6, 7.2, 5.9, 5.0],
		"final": 1.0, "reverse": 0.0, "idle": 1400.0, "redline": 9500.0, "up": [4000.0, 8500.0], "brake_g": 0.8, "cda": 0.5, "crr": 0.015, "grip": 4.4,
		"wet_k": 1.3},
	"heavy": {"torque": [[600.0, 400.0], [1200.0, 800.0], [1800.0, 800.0], [2600.0, 600.0]], "ratios": [4.5, 2.8, 1.8, 1.3, 1.0],
		"final": 4.0, "reverse": 4.5, "idle": 600.0, "redline": 2600.0, "up": [1400.0, 2300.0], "brake_g": 0.55, "cda": 6.5, "crr": 0.008, "grip": 4.2},
	"light_truck": {"torque": [[700.0, 120.0], [1500.0, 250.0], [2800.0, 250.0], [3800.0, 190.0]], "ratios": [5.0, 2.9, 1.8, 1.25, 1.0],
		"final": 4.3, "reverse": 4.5, "idle": 700.0, "redline": 3800.0, "up": [1800.0, 3200.0], "brake_g": 0.65, "cda": 2.6, "crr": 0.01, "grip": 4.4},
	"tractor": {"torque": [[800.0, 120.0], [1400.0, 180.0], [2200.0, 170.0]], "ratios": [9.0, 6.0, 4.0, 2.6], "final": 6.0, "reverse": 9.0,
		"idle": 800.0, "redline": 2200.0, "up": [1300.0, 2000.0], "brake_g": 0.4, "cda": 3.0, "crr": 0.03, "grip": 5.0},
}
## Which profile each vehicle has, and its own scale of the engine ("tq") where it differs from its kind's.
const DRIVE_OF := {"luxury_suv": ["diesel_suv", 1.0], "xuv": ["diesel_suv", 1.0], "suv": ["diesel_suv", 0.75], "van": ["diesel_suv", 0.6],
	"coupe": ["sport", 1.0], "hatchback": ["petrol_car", 1.0], "sedan": ["petrol_car", 1.15], "taxi": ["petrol_car", 1.15],
	"auto": ["auto", 1.0], "bus": ["heavy", 1.0], "lorry": ["heavy", 1.1], "delivery": ["light_truck", 1.0], "tractor": ["tractor", 1.0],
	"bike": ["bike", 1.0], "karthik_scooter": ["scooter", 1.0], "scooter": ["scooter", 1.0]}
## How each kind of engine sounds (synthesised, _engine_sample): "fires" a revolution (a single-cylinder four-stroke
## 0.5, a four-cylinder 2, a six 3), the harmonics' weights and a sub-octave, how sharp each firing is ("pulse") and
## how much clatter rides on it (idle, full load), a turbo's whistle, a CVT belt's whine, a rattle, and the overall level.
const ENGINE_SOUND := {
	"diesel_suv": {"fires": 2.0, "harm": [0.6, 0.35, 0.2, 0.0], "sub": 0.12, "pulse": 6.0, "noise": [0.2, 0.4], "turbo": 0.035, "whine": 0.0, "rattle": 0.0, "level": 1.0},
	"petrol_car": {"fires": 2.0, "harm": [0.5, 0.4, 0.25, 0.12], "sub": 0.04, "pulse": 3.0, "noise": [0.04, 0.12], "turbo": 0.0, "whine": 0.0, "rattle": 0.0, "level": 0.85},
	"sport": {"fires": 3.0, "harm": [0.55, 0.45, 0.35, 0.2], "sub": 0.1, "pulse": 4.0, "noise": [0.06, 0.2], "turbo": 0.02, "whine": 0.0, "rattle": 0.0, "level": 1.1},
	"auto": {"fires": 0.5, "harm": [0.4, 0.3, 0.3, 0.25], "sub": 0.15, "pulse": 10.0, "noise": [0.3, 0.5], "turbo": 0.0, "whine": 0.0, "rattle": 0.25, "level": 0.9},
	"scooter": {"fires": 0.5, "harm": [0.5, 0.35, 0.3, 0.2], "sub": 0.05, "pulse": 8.0, "noise": [0.1, 0.2], "turbo": 0.0, "whine": 0.03, "rattle": 0.0, "level": 0.7},
	"bike": {"fires": 0.5, "harm": [0.6, 0.4, 0.25, 0.1], "sub": 0.25, "pulse": 7.0, "noise": [0.15, 0.3], "turbo": 0.0, "whine": 0.0, "rattle": 0.0, "level": 0.95},
	"heavy": {"fires": 3.0, "harm": [0.7, 0.4, 0.2, 0.1], "sub": 0.2, "pulse": 5.0, "noise": [0.3, 0.5], "turbo": 0.02, "whine": 0.0, "rattle": 0.05, "level": 1.25},
	"light_truck": {"fires": 2.0, "harm": [0.6, 0.35, 0.2, 0.05], "sub": 0.15, "pulse": 6.0, "noise": [0.3, 0.5], "turbo": 0.02, "whine": 0.0, "rattle": 0.05, "level": 1.05},
	"tractor": {"fires": 1.5, "harm": [0.6, 0.4, 0.3, 0.1], "sub": 0.3, "pulse": 7.0, "noise": [0.4, 0.6], "turbo": 0.0, "whine": 0.0, "rattle": 0.15, "level": 1.1},
}

## Godot's VehicleBody3D brake is a force-like number per wheel: this many N of stopping per unit (measured).
const BRAKE_K := 236.0

const PAINT := Color(0.035, 0.12, 0.36)      # electric blue
const BLACK := Color(0.015, 0.015, 0.017)
const CHROME := Color(0.55, 0.56, 0.58)
const CLADDING := Color(0.03, 0.03, 0.032)

## A crash: which side took it (front, rear, left, right), how hard (0..1), and what it hit (city_test.gd fines it,
## the police hear of it).
signal impacted(zone: String, severity: float, other: Object)

## Driver inputs. The keyboard fills these unless `autopilot` is on.
var autopilot := false
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var speed := 0.0                   # forward speed, m/s
var lights_on := false
var honked := false
var gear := 1                      # 0 = reverse, 1..6
var rpm := IDLE
var drive_kind := "diesel_suv"     # this vehicle's DRIVE profile, and what it reads from it:
var ratios: Array = RATIOS
var final_drive := FINAL
var reverse_ratio := REVERSE
var idle_rpm := IDLE
var redline := REDLINE
var _curve: Array = []
var _up := [2000.0, 3600.0]
var _cvt: Array = []               # [low, high] overall ratios of a CVT (a scooter's), else empty
var _band := [3200.0, 7000.0]      # a CVT holds the engine here, from light to full throttle
var brake_full := BRAKE            # full braking for this mass
var cda := 0.95
var crr := 0.015
var tyre_grip := 4.6
var wet_k := 1.0
var rear_grip := 1.0               # the rear tyres' grip against the front's: over 1 a car understeers, under 1 its tail steps out
var _feel_t := 0.0                 # (the road under it, looked at ten times a second)
var _hb_on := false                # (the handbrake's hold on the rear tyres, to let go of)
## Damage, from crashes: each side 0..1, and what it does (readable, never the end of it: repair() mends it all):
## the front past 0.45 breaks the headlights, past 0.65 cracks the windscreen; a bent front pulls the steering;
## past 2.5 in all, the engine limps at 60%.
var damage := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
var _v_prev := Vector3.ZERO
var hit_velocity := Vector3.ZERO   # the last crash: its velocity just before, and the way the other pushed it (world)
var hit_normal := Vector3.ZERO
var hit_point := Vector3.ZERO      # (world)
var _dents := {}                   # the meshes a crash has dented → their originals (dents.gd)
var _glass_mat: Material           # the windscreen before it cracked
var _share := Vector4.ZERO         # a crash with something kinematic: (normal, speed along it) to set next step
var _crash := 0.0                  # (the crunch, sounding)
var _crash_phase := 0.0
var _pull := 0.0                   # (the steering's pull from a bent front, rad)
var two_wheeler := false           # a scooter or a motorbike: two wheels in line, balanced and leaning (_balance)
var lean := 0.0                    # its lean now (rad, + to its left) and the lean the turn asks for
var lean_target := 0.0
var _lean_i := 0.0                 # (the balance's memory of a lean it hasn't reached: a turn's steady push outward)
var manual := false
var cockpit := false
var is_coupe := false
var seat := DRIVER_SEAT            # eye position for the cockpit camera
var _coupe_wheels: Array = []      # [[wheel parts Node3D, Transform3D in car space, is_front]]
var out_of_fuel := false
var surface := "asphalt"           # asphalt | shoulder | ground (from the road graph)
var _weather_grip := 1.0
var _surface_grip := 1.0
var _surface_drag := 0.0           # extra rolling resistance off the tarmac, N per (m/s)           # engine starves: no drive, just idle coasting
var _wheels: Array = []

var _shift_timer := 0.0
var _steer_in := 0.0               # smoothed steering input
var _thr := 0.0                    # smoothed pedals
var _brk := 0.0
var _driver: MeshInstance3D
var _glass: MeshInstance3D
var _steering_wheel: Node3D
var _screen_speed: Label3D
var _screen_info: Label3D
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _headlights: Array = []
var _lamp_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _rev_mat: StandardMaterial3D
var _ind_mats: Array = []          # [left, right]
var indicator := 0                 # 0 off, 1 left, -1 right, 2 hazards
var _ind_yaw := 0.0
var _blink := 0.0
var jolt := 0.0                    # vertical shock this frame (m/s² change): camera shake, suspension thud
var slip := 0.0                    # how much the tyres are sliding (0 grip .. 1 skidding): squeal
var _vy_prev := 0.0
var _abs_t := 0.0
var _road: AudioStreamPlayer
var _road_lp := [0.0, 0.0, 0.0]    # filter states: wind, rumble, squeal noise
var _squeal_phase := 0.0
var _thud := 0.0
var _turbo_phase := 0.0
var _engine: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _engine_phase := 0.0
var _horn_phase := 0.0
var _horn_time := 0.0


## Every drivable vehicle. "glb": the user's Blender cars (tools/*.py → assets/vehicles/), with
## separate wheels and (luxury SUV) a modelled interior. Others reuse the traffic / parked models.
## len/w/h in metres; torque multiplies the 450 N·m curve; top in m/s; seat = driver's eyes.
const SPECS := {
	"luxury_suv": {"name": "Luxury SUV", "glb": "res://assets/vehicles/luxury_suv.glb", "mass": 2150.0,
		"com": Vector3(0, 0.5, 0.05), "radius": 0.40, "rest": 0.2, "travel": 0.22, "stiff": 34.0, "torque": 1.15,
		"top": 50.0, "seat": Vector3(-0.42, 1.47, -0.3), "interior": true, "glass": "Greenhouse",
		"head": ["Headlight", "FogDRL"], "tail": ["TailCorner", "TailStrip"], "lamp": Vector3(0.7, 0.99, 2.55),
		"boxes": [[Vector3(2.0, 0.9, 5.0), Vector3(0, 0.75, 0)], [Vector3(1.7, 0.7, 3.4), Vector3(0, 1.5, -0.65)]],
		"ind": [Vector3(0.9, 0.99, 2.47), Vector3(0.82, 1.2, -2.5), Vector3(0.82, 0.62, -2.5)]},
	"coupe": {"name": "Sports Coupe", "glb": "res://assets/vehicles/coupe.glb", "mass": 1450.0,
		"com": Vector3(0, 0.32, 0.05), "radius": 0.34, "rest": 0.16, "travel": 0.14, "stiff": 48.0, "torque": 1.0,
		"top": 52.0, "seat": Vector3(-0.4, 1.17, -0.36), "cabin": Vector3(0, -0.12, -0.15), "glass": "Canopy",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.6, 0.6, 2.12),
		"boxes": [[Vector3(1.9, 0.72, 4.5), Vector3(0, 0.55, 0)], [Vector3(1.25, 0.45, 2.1), Vector3(0, 1.02, -0.4)]],
		"ind": [Vector3(0.74, 0.42, 2.12), Vector3(0.62, 0.62, -2.25), Vector3(0.45, 0.5, -2.27)]},
	"xuv": {"name": "SUV", "procedural": true, "mass": 2000.0, "com": Vector3(0, 0.42, 0.05), "radius": 0.36,
		"torque": 1.0, "top": 44.0, "seat": DRIVER_SEAT, "lamp": Vector3(0.72, 0.98, 2.3)},
	"hatchback": {"name": "Hatchback", "glb": "res://assets/vehicles/fleet_hatchback.glb", "mass": 1000.0,
		"com": Vector3(0, 0.45, 0), "radius": 0.29, "rest": 0.16, "travel": 0.16, "stiff": 40.0, "torque": 0.55,
		"top": 42.0, "seat": Vector3(-0.36, 1.27, -0.05), "cabin": Vector3(0, -0.21, 0.05), "cab_scale": 0.78, "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.6, 0.64, 1.95),
		"boxes": [[Vector3(1.7, 0.72, 3.8), Vector3(0, 0.6, 0)], [Vector3(1.4, 0.55, 2.4), Vector3(0, 1.17, -0.3)]],
		"ind": [Vector3(0.7, 0.5, 1.9), Vector3(0.62, 0.78, -1.92), Vector3(0.4, 0.45, -1.93)]},
	"sedan": {"name": "Sedan", "glb": "res://assets/vehicles/fleet_sedan.glb", "mass": 1150.0,
		"com": Vector3(0, 0.45, 0), "radius": 0.30, "rest": 0.16, "travel": 0.16, "stiff": 40.0, "torque": 0.65,
		"top": 46.0, "seat": Vector3(-0.36, 1.26, 0.0), "cabin": Vector3(0, -0.22, 0.1), "cab_scale": 0.78, "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.6, 0.64, 2.24),
		"boxes": [[Vector3(1.74, 0.72, 4.35), Vector3(0, 0.6, 0)], [Vector3(1.4, 0.55, 2.4), Vector3(0, 1.15, -0.2)]],
		"ind": [Vector3(0.7, 0.5, 2.18), Vector3(0.62, 0.78, -2.2), Vector3(0.4, 0.45, -2.21)]},
	"taxi": {"name": "Taxi", "glb": "res://assets/vehicles/fleet_sedan.glb", "mass": 1150.0,
		"com": Vector3(0, 0.45, 0), "radius": 0.30, "rest": 0.16, "travel": 0.16, "stiff": 40.0, "torque": 0.6,
		"top": 42.0, "seat": Vector3(-0.36, 1.26, 0.0), "cabin": Vector3(0, -0.22, 0.1), "cab_scale": 0.78, "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.6, 0.64, 2.24),
		"boxes": [[Vector3(1.74, 0.72, 4.35), Vector3(0, 0.6, 0)], [Vector3(1.4, 0.55, 2.4), Vector3(0, 1.15, -0.2)]],
		"ind": [Vector3(0.7, 0.5, 2.18), Vector3(0.62, 0.78, -2.2), Vector3(0.4, 0.45, -2.21)]},
	"auto": {"name": "Auto-rickshaw", "glb": "res://assets/vehicles/fleet_auto.glb", "mass": 450.0,
		"com": Vector3(0, 0.45, -0.2), "radius": 0.22, "rest": 0.14, "travel": 0.12, "stiff": 30.0, "torque": 0.2,
		"top": 15.0, "seat": Vector3(0, 1.45, 0.3), "nocab": true, "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.0, 0.82, 1.4),
		"boxes": [[Vector3(1.3, 1.3, 2.6), Vector3(0, 0.95, 0)]],
		"ind": [Vector3(0.5, 0.9, 1.25), Vector3(0.62, 0.62, -1.33), Vector3(0.3, 0.5, -1.34)]},
	"bus": {"name": "Bus", "glb": "res://assets/vehicles/fleet_bus.glb", "mass": 11000.0,
		"com": Vector3(0, 1.1, 0), "radius": 0.5, "rest": 0.25, "travel": 0.2, "stiff": 30.0, "torque": 4.5,
		"top": 22.0, "seat": Vector3(-0.75, 2.25, 2.92), "cabin": Vector3(-0.33, 0.75, 3.0), "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.95, 0.95, 5.35),
		"boxes": [[Vector3(2.5, 2.7, 10.5), Vector3(0, 1.75, 0)]],
		"ind": [Vector3(1.15, 0.95, 5.3), Vector3(1.1, 1.5, -5.3), Vector3(0.6, 0.7, -5.31)]},
	"lorry": {"name": "Lorry", "glb": "res://assets/vehicles/fleet_lorry.glb", "mass": 12000.0,
		"com": Vector3(0, 1.0, 0.5), "radius": 0.52, "rest": 0.25, "travel": 0.2, "stiff": 30.0, "torque": 5.0,
		"top": 20.0, "seat": Vector3(-0.6, 2.35, 3.52), "cabin": Vector3(-0.2, 0.9, 3.0), "glass": "Glass",
		"head": ["Headlight"], "tail": ["TailBar"], "lamp": Vector3(0.85, 1.25, 4.65),
		"boxes": [[Vector3(2.5, 1.0, 9.2), Vector3(0, 1.0, 0)], [Vector3(2.5, 2.2, 2.0), Vector3(0, 2.0, 3.6)],
			[Vector3(2.5, 1.8, 6.9), Vector3(0, 1.9, -1.0)]],
		"ind": [Vector3(1.15, 1.25, 4.6), Vector3(1.1, 0.95, -4.52), Vector3(0.6, 0.8, -4.52)]},
	"suv": {"name": "Compact SUV", "kenney": "suv", "len": 4.5, "w": 1.85, "h": 1.75, "mass": 1650.0, "radius": 0.36, "torque": 0.85, "top": 44.0},
	"van": {"name": "Van", "kenney": "van", "len": 4.6, "w": 1.85, "h": 2.0, "mass": 1800.0, "radius": 0.34, "torque": 0.7, "top": 36.0},
	"delivery": {"name": "Delivery truck", "kenney": "delivery", "len": 5.2, "w": 1.95, "h": 2.3, "mass": 2400.0, "radius": 0.36, "torque": 0.8, "top": 32.0},
	"tractor": {"name": "Tractor", "kenney": "tractor", "len": 3.9, "w": 1.9, "h": 2.4, "mass": 2500.0, "radius": 0.5, "torque": 1.0, "top": 9.0},
	"bike": {"name": "Motorbike", "built": "bike", "len": 2.0, "w": 0.8, "h": 1.4, "mass": 230.0, "radius": 0.31, "torque": 0.16, "top": 26.0, "rider": true},
	## Karthik's own scooter (tools/story_scooter.py) with him riding it in his helmet (the story's night delivery)
	"karthik_scooter": {"name": "Karthik's scooter", "glb": "res://assets/vehicles/karthik_scooter.glb", "mass": 190.0,
		"com": Vector3(0, 0.5, -0.1), "radius": 0.24, "rest": 0.12, "travel": 0.1, "sag": 0.0, "stiff": 40.0, "torque": 0.11,
		"top": 21.0, "seat": Vector3(0, 1.62, -0.2), "glass": "NoGlass", "head": ["Headlamp"], "tail": ["TailLamp"],
		"lamp": Vector3(0.0, 1.02, 0.5), "boxes": [[Vector3(0.6, 0.8, 1.85), Vector3(0, 0.62, -0.15)]],
		"ind": [Vector3(0.2, 0.9, 0.49), Vector3(0.135, 0.6, -0.9), Vector3(0.1, 0.5, -0.92)], "rider": true,
		"two_wheeler": true, "rider_model": "story_karthik", "helmet": "res://assets/vehicles/helmet.glb",
		"hip": Vector3(0, 0.945, -0.17)},
	"scooter": {"name": "Scooter", "built": "scooter", "len": 1.8, "w": 0.75, "h": 1.4, "mass": 190.0, "radius": 0.25, "torque": 0.11, "top": 21.0, "rider": true},
}
const START_VEHICLE := "luxury_suv"

var vehicle := ""                  # SPECS key of what you're driving now
var top_speed := TOP_SPEED
var torque_mul := 1.0
var wheel_r := WHEEL_R
var _steer_base := Basis(Vector3.RIGHT, deg_to_rad(-65.0))
var _cab_parts: Array = []         # procedural dash/wheel/labels/mirror
var _rider: Node3D                 # you, astride a two-wheeler
var _paint := Color(0, 0, 0, 0)    # body colour of the car you took (alpha 0: the model's own)
var kit: CockpitKit                # analog cluster, live door mirrors, wipers
var night := 0.0                   # set by the game: dial backlighting
var fuel_frac := 1.0
var wiping := false
var screens: Array = []            # SubViewports of the dash screens (drawn only in the cockpit view)
var map_ui                         # set by the game: the nav screen draws from it
var clock_text := ""
var _nav: Control


func _init() -> void:
	angular_damp = 1.2                # settles yaw and roll: no twitching
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_build_audio()
	var want := START_VEHICLE
	if "--xuv" in OS.get_cmdline_user_args():
		want = "xuv"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vehicle="):
			want = a.get_slice("=", 1)
	if not _available(want):
		want = "coupe" if _available("coupe") else "xuv"
	configure(want)


static func _available(kind: String) -> bool:
	if not SPECS.has(kind):
		return false
	var sp: Dictionary = SPECS[kind]
	return not sp.has("glb") or ResourceLoader.exists(sp["glb"])


## Rebuild this car as another vehicle (GTA-style: you just got into it).
func configure(kind: String, paint := Color(0, 0, 0, 0)) -> void:
	_paint = paint
	for c in get_children():
		if c == _engine or c == _horn:
			continue
		remove_child(c)
		c.queue_free()
	_wheels.clear()
	_ind_mats.clear()
	_headlights.clear()
	_coupe_wheels.clear()
	_cab_parts.clear()
	screens.clear()
	_cluster_ui = null
	_nav = null
	_glass = null
	_rider = null
	_steer_base = Basis(Vector3.RIGHT, deg_to_rad(-65.0))
	vehicle = kind
	var sp: Dictionary = SPECS[kind]
	is_coupe = kind == "coupe"
	mass = sp["mass"]
	center_of_mass = sp.get("com", Vector3(0, float(sp.get("h", 1.5)) * 0.32, 0.05))
	top_speed = sp["top"]
	torque_mul = sp["torque"]
	wheel_r = sp["radius"]
	two_wheeler = bool(sp.get("two_wheeler", false)) or (bool(sp.get("rider", false)) and kind != "auto")
	contact_monitor = true                      # (crashes: _integrate_forces reads the contacts)
	max_contacts_reported = 8
	repair()
	_set_drive(kind)
	seat = sp.get("seat", Vector3.ZERO)
	gear = 1
	if sp.has("glb"):
		_build_glb(sp)
		_build_glb_wheels(sp)
	elif sp.get("procedural", false):
		_build_body()
		_build_wheels()
	else:
		_build_generic(sp)
	_track_cab(func(): _build_cockpit())
	if not sp.get("interior", false) and _steering_wheel:
		for ch in _steering_wheel.get_children():
			(ch as Node3D).visible = false
		var mw := MeshInstance3D.new()
		mw.mesh = modern_wheel(0.18)
		mw.material_override = MB.vertex_color_material(0.55)
		mw.rotation.y = PI                      # third spoke down
		_steering_wheel.add_child(mw)
	if sp.get("rider", false):
		for c in _cab_parts:
			c.visible = false
		# a person on it: seated, feet on the pegs, hands on the bars
		if sp.has("rider_model"):
			_rider = _story_rider(sp)
		else:
			_rider = RiderPose.make(randi() % 7, 0.6 if kind == "bike" else 0.5)
			_rider.position = RiderPose.seat_offset(kind)
		_rider.name = "Rider"
		add_child(_rider)
		seat = Vector3(0, 1.62, -0.2)
	elif sp.get("interior", false):
		_fit_model_interior(sp)
	elif ResourceLoader.exists(CABINS % _cabin_name(kind)):
		_fit_cabin(kind)
	elif sp.get("nocab", false):
		for c in _cab_parts:
			c.visible = false
	else:
		var shift: Vector3 = sp.get("cabin", _generic_cabin(sp))
		var cs: float = sp.get("cab_scale", 1.0)          # narrower cars: a narrower dash
		for c in _cab_parts:
			var n3 := c as Node3D
			n3.position = Vector3(n3.position.x * cs, n3.position.y, n3.position.z) + shift
			n3.scale.x *= cs
		if not sp.has("seat"):
			seat = DRIVER_SEAT + shift
	if not sp.get("rider", false) and not sp.get("nocab", false):
		_build_kit(sp)
	else:
		kit = null
	_camera_rig(sp)
	_build_lights()
	set_lights(lights_on)
	_apply_grip()


const CABINS := "res://assets/vehicles/interior_%s.glb"

func _cabin_name(kind: String) -> String:
	return kind


## Each vehicle's own cabin from tools/interiors.py: the stand-in dash goes, the driver's eyes come
## from the cabin's "Eye" marker and its own steering wheel (or handlebar) turns with you.
func _fit_cabin(kind: String) -> void:
	for c in _cab_parts:
		c.visible = false
	var cab := (load(CABINS % _cabin_name(kind)) as PackedScene).instantiate() as Node3D
	cab.name = "Cabin"
	cab.rotation.y = -PI * 0.5                  # Blender +X nose → +Z
	add_child(cab)
	for mi in cab.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var eye := cab.find_child("Eye", true, false) as Node3D
	if eye:
		seat = _rel(eye, self).origin
	var piv := cab.find_child("SteeringPivot", true, false) as Node3D
	if piv:
		_steering_wheel = piv
		_steer_base = piv.basis
	if _driver:
		_driver.visible = false
	_screen_speed.visible = false
	_screen_info.visible = false


## Camera framing for this vehicle: a bike close behind, a bus or lorry far back and high.
var chase_back := 8.6
var chase_up := 2.9
var bonnet := Vector3(0, 1.32, 1.6)

func _camera_rig(sp: Dictionary) -> void:
	var L := 4.5
	var H := 1.6
	if sp.has("len"):
		L = float(sp["len"])
		H = float(sp.get("h", 1.6))
	elif sp.has("boxes"):
		for b in sp["boxes"]:
			L = maxf(L if L != 4.5 else 0.0, float(b[0].z))
			H = maxf(H if H != 1.6 else 0.0, float(b[1].y) + float(b[0].y) * 0.5)
	chase_back = clampf(2.6 + L * 1.15, 4.2, 17.0)
	chase_up = clampf(0.9 + H * 0.9, 1.9, 6.0)
	bonnet = Vector3(0, H * 0.72 + 0.1, L * 0.5 - 0.5)
	if sp.get("rider", false):
		bonnet = Vector3(0, 1.45, 0.3)


func _build_kit(sp: Dictionary) -> void:
	kit = CockpitKit.new()
	kit.name = "CockpitKit"
	add_child(kit)
	var half_w := 0.92
	if sp.has("w"):
		half_w = float(sp["w"]) * 0.5
	elif sp.has("boxes"):
		half_w = float(sp["boxes"][0][0].x) * 0.5
	var wp: Array = WIPERS.get(vehicle, [seat + Vector3(0, -0.33, 1.0), 0.5])
	var cluster_at = null
	if has_node("Cabin"):
		var ce := get_node("Cabin").find_child("Cluster", true, false) as Node3D
		if ce:
			cluster_at = _rel(ce, self).origin + Vector3(0, 0, -0.02)
			_screen_speed.visible = false
			_screen_info.visible = false
	if cluster_at == null and has_node("Model"):
		var cl := get_node("Model").find_child("INT_Cluster", true, false) as Node3D
		if cl:
			cluster_at = _rel(cl, self).origin + Vector3(0.0, 0.04, -0.11)
	if cluster_at == null and _steering_wheel and _steering_wheel.visible:
		cluster_at = _steering_wheel.position + Vector3(0, 0.16, 0.2)
		# the analog cluster replaces the stand-in digital screens in these cars
		_screen_speed.visible = false
		_screen_info.visible = false
	# a model with its own door mirrors gets the live glass on their backs instead of stand-ins
	var mirrors: Array = []
	if has_node("Model"):
		for n in get_node("Model").find_children("Mirror*", "MeshInstance3D", true, false):
			if String(n.name).begins_with("MirrorArm"):
				continue
			var mi := n as MeshInstance3D
			var bb := mi.get_aabb()
			var xf := _rel(mi, self)
			var c := xf * bb.get_center()
			var lo := INF
			for k in 8:
				lo = minf(lo, (xf * bb.get_endpoint(k)).z)
			mirrors.append([Vector3(c.x, c.y, lo - 0.004), signf(c.x)])
	kit.build(self, seat, half_w, wp[0], wp[1], cluster_at, not sp.get("interior", false), mirrors)


## Runs a builder and remembers the 3D nodes it added (the procedural cabin parts).
func _track_cab(build: Callable) -> void:
	var before := get_child_count()
	build.call()
	for i in range(before, get_child_count()):
		if get_child(i) is Node3D:
			_cab_parts.append(get_child(i))


func _generic_cabin(sp: Dictionary) -> Vector3:
	if not sp.has("len"):
		return Vector3.ZERO
	return Vector3(0, (float(sp["h"]) - 1.75) * 0.85, float(sp["len"]) * 0.5 - 2.33)


# ----------------------------------------------------------------------------- the user's Blender cars
func _build_glb(sp: Dictionary) -> void:
	_add_boxes(sp["boxes"])
	var model := (load(sp["glb"]) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = -PI * 0.5                  # Blender +X (the nose) → the car's +Z
	add_child(model)
	_lamp_mat = _emitter(Color(0.9, 0.9, 0.95), Color(1.0, 0.97, 0.9), 0.6)
	_tail_mat = _emitter(Color(0.5, 0.0, 0.0), Color(1.0, 0.03, 0.01), 0.3)
	_rev_mat = _emitter(Color(0.8, 0.8, 0.8), Color(1, 1, 0.95), 0.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.015, 0.02, 0.025, 0.86)     # dark privacy tint, mirror-like
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.55
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var top: Node = m
		while top.get_parent() != model:
			top = top.get_parent()
		var nm := String(top.name)
		if nm.begins_with(sp["glass"]):
			m.material_override = glass
			_glass = m
		elif _starts(nm, sp["head"]):
			m.material_override = _lamp_mat
		elif _starts(nm, sp["tail"]):
			m.material_override = _tail_mat
	# glTF from Blender is double-sided; from the driver's seat that walls you in. One-sided surfaces
	# let you see out (shells face outward), like any car interior made of panels.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		for si in gi.mesh.get_surface_count():
			var bm := gi.get_surface_override_material(si) as BaseMaterial3D
			if bm == null:
				bm = gi.mesh.surface_get_material(si) as BaseMaterial3D
			if bm and bm.cull_mode != BaseMaterial3D.CULL_BACK and not String(sp["glb"]).contains("luxury"):
				var one := bm.duplicate() as BaseMaterial3D
				one.cull_mode = BaseMaterial3D.CULL_BACK
				gi.set_surface_override_material(si, one)
	if _paint.a > 0.0:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			for si in inst.mesh.get_surface_count():
				var mat := inst.mesh.surface_get_material(si) as BaseMaterial3D
				if mat and mat.resource_name == "Paint":
					var v := mat.duplicate() as BaseMaterial3D
					v.albedo_color = _paint
					v.cull_mode = BaseMaterial3D.CULL_BACK
					inst.set_surface_override_material(si, v)
	var wheel_nodes: Array = []
	for n in model.find_children("Wheel_*", "Node3D", true, false):
		wheel_nodes.append(n)
	for w in wheel_nodes:
		var wn := String(w.name)
		var xf: Transform3D = model.transform * w.transform
		w.owner = null
		for d in w.find_children("*", "", true, false):
			d.owner = null
		w.get_parent().remove_child(w)
		w.transform = Transform3D(xf.basis, Vector3.ZERO)
		_coupe_wheels.append([w, xf, wn.substr(6, 1) == "F"])
	_corner_lamps(sp["ind"][0], sp["ind"][1], sp["ind"][2])
	_add_driver(sp["seat"])


static func _starts(nm: String, prefixes: Array) -> bool:
	for p in prefixes:
		if nm.begins_with(p):
			return true
	return false


func _build_glb_wheels(sp: Dictionary) -> void:
	for cw in _coupe_wheels:
		var xf: Transform3D = cw[1]
		# (the mounts moved by "ride" so that, the springs settled under the weight, the body rides at the model's own
		#  height: measured, -0.06 for the scooter, which otherwise sat 6 cm low)
		var w := _wheel(Vector3(xf.origin.x, xf.origin.y + sp["rest"] + float(sp.get("ride", 0.0)), xf.origin.z), cw[2], sp)
		w.add_child(cw[0])
		if sp.get("two_wheeler", false) and cw[2]:
			w.use_as_traction = false                  # (a scooter drives its rear wheel)
	# (a two-wheeler stands on its own two wheels: _balance keeps it up and leans it into a turn; it used to have a
	#  pair of unseen outrigger wheels, which carried its weight and braked: slow away, short stops, no lean)


## The story's own person riding (scripts/story people, the cast's "Ride" clip, tools/humans/story_cast.py): the
## hips on the seat, and the helmet (tools/story_scooter.py) put on once the pose has settled.
const HELMET_OFFSET := Vector3(0.0, 0.0385, -0.0112)      # from the head bone (tools/story_scooter.py prints it)
const RIDE_HIP := Vector3(0.0, 0.9963, -0.0049)           # the person's hip point in the Ride pose

func _story_rider(sp: Dictionary) -> Node3D:
	var path := "res://assets/people/%s.glb" % sp["rider_model"]
	var node := (load(path) as PackedScene).instantiate() as Node3D
	var aps := node.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		if ap.has_animation("Ride"):
			ap.get_animation("Ride").loop_mode = Animation.LOOP_LINEAR
			node.ready.connect(func() -> void: ap.play("Ride"))
	var hip: Vector3 = sp["hip"]
	node.position = hip - RIDE_HIP
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for i in m3.mesh.get_surface_count():                # his hair dark (the export's hair texture is light)
			var mat := m3.get_active_material(i)
			if mat and mat.resource_name.to_lower().contains("short") and mat is BaseMaterial3D:
				var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = Color(0.06, 0.05, 0.04)
				m3.set_surface_override_material(i, dup)
	node.ready.connect(func() -> void: get_tree().create_timer(0.15).timeout.connect(
		_settle_rider.bind(node, hip, String(sp.get("helmet", "")))))
	return node


## Once the Ride pose is on: his hips exactly on the seat (measured from his own skeleton), then the helmet on.
func _settle_rider(rider: Node3D, hip: Vector3, helmet: String) -> void:
	if not is_instance_valid(rider):
		return
	var sks := rider.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var l := sk.find_bone("thigh_l")
	var r := sk.find_bone("thigh_r")
	if l >= 0 and r >= 0:
		var mid := (sk.get_bone_global_pose(l).origin + sk.get_bone_global_pose(r).origin) * 0.5
		var at := global_transform.affine_inverse() * (sk.global_transform * mid)     # his hips, in the scooter's frame
		rider.position += hip - at
		rider.force_update_transform()
	if helmet != "" and ResourceLoader.exists(helmet):
		_put_on_helmet(rider, helmet)


func _put_on_helmet(rider: Node3D, path: String) -> void:
	if not is_instance_valid(rider):
		return
	var sks := rider.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var bi := sk.find_bone("head")
	if bi < 0:
		return
	var att := BoneAttachment3D.new()                      # the helmet moves with his head
	att.bone_name = "head"
	sk.add_child(att)
	var hel := (load(path) as PackedScene).instantiate() as Node3D
	att.add_child(hel)
	for mi in hel.find_children("*", "MeshInstance3D", true, false):    # the shell's gloss-black paint (its Blender
		var m3 := mi as MeshInstance3D                                   # colour is a shader the export can't carry)
		for i in m3.mesh.get_surface_count():
			var mat := m3.mesh.surface_get_material(i) as BaseMaterial3D
			if mat and mat.resource_name.begins_with("Helmet Paint"):
				var paint := mat.duplicate() as BaseMaterial3D
				paint.albedo_color = Color(0.035, 0.035, 0.04)
				paint.roughness = 0.2
				paint.clearcoat_enabled = true
				paint.clearcoat = 1.0
				m3.set_surface_override_material(i, paint)
	var bone := sk.get_bone_global_pose(bi)                 # (the attachment follows the bone from the next frame)
	var head := sk.global_transform * bone
	var want := Transform3D(rider.global_basis, head.origin + rider.global_basis * HELMET_OFFSET)
	hel.transform = bone.affine_inverse() * (sk.global_transform.affine_inverse() * want)


func _wheel(pos: Vector3, front: bool, sp: Dictionary) -> VehicleWheel3D:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.use_as_traction = true
	w.use_as_steering = front
	w.wheel_radius = sp["radius"]
	w.wheel_rest_length = sp.get("rest", 0.2)
	w.suspension_travel = sp.get("travel", 0.2)
	w.suspension_stiffness = float(sp.get("stiff", 36.0)) * (1.0 + float(sp["mass"]) / 6000.0) * (3.0 if sp.get("rider", false) else 1.0)
	#  (a two-wheeler's two springs carry it all: twice as stiff, or the body sits on the road)
	w.suspension_max_force = float(sp["mass"]) * 18.0
	w.damping_compression = 3.0
	w.damping_relaxation = 3.6
	w.wheel_friction_slip = tyre_grip * _wet_grip() * _surface_grip
	w.wheel_roll_influence = 0.05 if sp.get("rider", false) else 0.12
	_wheels.append(w)
	add_child(w)
	return w


func _add_boxes(boxes: Array) -> void:
	for b in boxes:
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = b[0]
		shape.shape = bx
		shape.position = b[1]
		add_child(shape)


## Amber indicators (front corner, rear corner) and reverse lamps; positions given on the car's
## left (+X) and mirrored to the right.
func _corner_lamps(front: Vector3, rear: Vector3, rev_at: Vector3) -> void:
	var rev := MB.new()
	for sx in [-1.0, 1.0]:
		rev.box(Transform3D(Basis(), Vector3(rev_at.x * sx, rev_at.y, rev_at.z)), Vector3(0.13, 0.05, 0.03), Color.WHITE)
	var rev_mi := MeshInstance3D.new()
	rev_mi.mesh = rev.commit()
	rev_mi.material_override = _rev_mat
	add_child(rev_mi)
	for side in [1.0, -1.0]:
		var m := _emitter(Color(0.6, 0.35, 0.02), Color(1.0, 0.55, 0.05), 0.0)
		var ind := MB.new()
		ind.box(Transform3D(Basis(), Vector3(front.x * side, front.y, front.z)), Vector3(0.1, 0.04, 0.05), Color.WHITE)
		ind.box(Transform3D(Basis(), Vector3(rear.x * side, rear.y, rear.z)), Vector3(0.12, 0.04, 0.03), Color.WHITE)
		var ind_mi := MeshInstance3D.new()
		ind_mi.mesh = ind.commit()
		ind_mi.material_override = m
		add_child(ind_mi)
		_ind_mats.append(m)


func _add_driver(eye: Vector3) -> void:
	var drv := MB.new()
	drv.box(Transform3D(Basis(), eye + Vector3(0, -0.42, -0.08)), Vector3(0.42, 0.42, 0.26), Color(0.85, 0.85, 0.82))
	drv.box(Transform3D(Basis(), eye + Vector3(0, -0.02, -0.06)), Vector3(0.18, 0.22, 0.2), Color(0.30, 0.17, 0.10))
	drv.box(Transform3D(Basis(), eye + Vector3(0, 0.1, -0.08)), Vector3(0.2, 0.05, 0.22), Color(0.02, 0.02, 0.02))
	_driver = MeshInstance3D.new()
	_driver.mesh = drv.commit()
	_driver.material_override = MB.vertex_color_material(0.8)
	add_child(_driver)


## The luxury SUV brings its own cabin: hide the stand-in dash, turn the modelled steering wheel
## with the car's steering, and put the live speed / gear readouts on its screens.
func _fit_model_interior(_sp: Dictionary) -> void:
	var model := get_node("Model") as Node3D
	for c in _cab_parts:
		if c is MeshInstance3D:
			c.visible = false
	_steering_wheel.visible = false
	var rim := model.find_child("INT_SteeringRim", true, false) as Node3D
	if rim:
		var pivot := Node3D.new()
		pivot.name = "SteeringPivot"
		var pxf := _rel(rim, self)
		pivot.transform = pxf
		add_child(pivot)
		for part_name in ["INT_SteeringRim", "INT_SteeringHub", "INT_SteeringSpoke", "INT_SteeringSpokeLow", "INT_SteeringBadge"]:
			var part := model.find_child(part_name, true, false) as Node3D
			if part == null:
				continue
			var rel := pxf.affine_inverse() * _rel(part, self)
			part.owner = null
			part.get_parent().remove_child(part)
			part.transform = rel
			pivot.add_child(part)
		_steering_wheel = pivot
		_steer_base = pxf.basis
		# a modern three-spoke wheel with button pads in place of the plain one
		for part in pivot.get_children():
			(part as Node3D).visible = false
		var mw := MeshInstance3D.new()
		mw.mesh = modern_wheel(0.19)
		mw.rotation.y = -PI * 0.5                  # spokes at 9 and 3 o'clock, the third one down
		mw.material_override = MB.vertex_color_material(0.55)
		pivot.add_child(mw)
	_dark_cabin(model)
	_screen_speed.visible = false
	_screen_info.visible = false
	for old in ["INT_Cluster", "INT_CenterScreen", "INT_ScreenFrame"]:
		var o := model.find_child(old, true, false) as Node3D
		if o:
			o.visible = false
	var cluster := model.find_child("INT_Cluster", true, false) as Node3D
	if cluster:
		# the digital driver display, a little wider than the panel it sits on
		var cp := _rel(cluster, self).origin + Vector3(0.0, 0.03, -0.035)
		var face := (seat - cp)
		var xf := Transform3D(Basis.looking_at(-face.normalized(), Vector3.UP), cp)
		var cl := CarScreens.Cluster.new()
		cl.car = self
		screens.append(CarScreens.screen(self, cl, Vector2i(640, 240), xf, 0.4, 0.15))
		_cluster_ui = cl
	var centre := model.find_child("INT_CenterScreen", true, false) as Node3D
	if centre:
		var sp2 := _rel(centre, self)
		var cpos := sp2.origin + Vector3(0, 0, -0.012)
		var face2 := seat + Vector3(0.3, 0, 0) - cpos
		var xf2 := Transform3D(Basis.looking_at(-face2.normalized(), Vector3.UP), cpos)
		_nav = CarScreens.Nav.new()
		_nav.map_ui = map_ui
		screens.append(CarScreens.screen(self, _nav, Vector2i(560, 300), xf2, 0.42, 0.22))
	var mirror := _cab_parts[_cab_parts.size() - 1] as Node3D
	mirror.position = Vector3(0.0, 1.66, 0.62)
	mirror.visible = true


var _cluster_ui: Control

## Dark leather and trim, like a modern cab, instead of the light grey upholstery.
func _dark_cabin(model: Node3D) -> void:
	var colors := {"INT_Leather": Color(0.15, 0.1, 0.075), "INT_DarkLeather": Color(0.03, 0.03, 0.032),
		"INT_Headliner": Color(0.14, 0.14, 0.15), "INT_Carpet": Color(0.03, 0.03, 0.03),
		"INT_Wood": Color(0.11, 0.055, 0.03)}         # Blender's procedural grain doesn't export: dark walnut
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for si in inst.mesh.get_surface_count():
			var mat := inst.mesh.surface_get_material(si) as BaseMaterial3D
			if mat and mat.resource_name == "INT_Ambient":
				var amb := mat.duplicate() as BaseMaterial3D
				amb.emission_energy_multiplier = 0.12            # a thin glow, not a light bar
				inst.set_surface_override_material(si, amb)
				continue
			if mat and colors.has(mat.resource_name):
				var v := mat.duplicate() as BaseMaterial3D
				v.albedo_color = colors[mat.resource_name] if not "--redcab" in OS.get_cmdline_user_args() else Color(1, 0, 0)
				v.roughness = 0.62
				inst.set_surface_override_material(si, v)


## A modern three-spoke steering wheel (ring in the local XZ plane, driver on +Y): thick leather
## rim, silver-trimmed spokes with button pads, and a padded centre.
static func modern_wheel(r: float) -> Mesh:
	var mb := MB.new()
	var leather := Color(0.05, 0.045, 0.04)
	var segs := 36
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := Vector3(cos(a1), 0, sin(a1)) * r
		var grip := 0.019 if absf(sin((a0 + a1) * 0.5)) < 0.75 else 0.016   # fatter at 9 and 3 o'clock
		mb.box(Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) * 0.5), Vector3(grip * 2.0, grip * 2.0, p0.distance_to(p1) * 1.08), leather)
	# spokes at 9, 3 and 6 o'clock (+X is the car's left)
	for ang in [0.0, PI, PI * 0.5]:
		var d := Vector3(cos(ang), 0, sin(ang))
		var mid := d * r * 0.55
		var long := r * 0.78 if ang != PI * 0.5 else r * 0.7
		var bas := Basis.looking_at(d, Vector3.UP)
		mb.box(Transform3D(bas, mid + Vector3(0, 0.004, 0)), Vector3(0.05 if ang != PI * 0.5 else 0.035, 0.016, long), Color(0.05, 0.05, 0.055))
		for edge in [-1.0, 1.0]:                      # thin satin-silver edges
			var w := 0.025 if ang != PI * 0.5 else 0.0175
			mb.box(Transform3D(bas, mid + bas * Vector3(edge * w, 0.012, 0)), Vector3(0.004, 0.004, long * 0.85), Color(0.42, 0.43, 0.45))
		mb.box(Transform3D(bas, mid + Vector3(0, 0.013, 0)), Vector3(0.008, 0.004, long * 0.9), Color(0.42, 0.43, 0.45))
		if ang != PI * 0.5:
			# button pad: a dark panel with a ring of small keys
			var pad := d * r * 0.5 + Vector3(0, 0.017, 0)
			mb.box(Transform3D(bas, pad), Vector3(0.05, 0.004, 0.06), Color(0.03, 0.03, 0.035))
			for bx in [-0.014, 0.014]:
				for bz in [-0.016, 0.0, 0.016]:
					mb.box(Transform3D(bas, pad + bas * Vector3(bx, 0.003, bz)), Vector3(0.011, 0.003, 0.01), Color(0.2, 0.2, 0.22))
	mb.ellipsoid(Transform3D(Basis(), Vector3(0, 0.01, 0.0)), Vector3(0.065, 0.025, 0.055), Color(0.045, 0.045, 0.05), 5, 12)
	mb.box(Transform3D(Basis(), Vector3(0, 0.035, 0)), Vector3(0.05, 0.003, 0.012), Color(0.55, 0.56, 0.58))   # a plain trim strip (no badge)
	return mb.commit()


func _rel(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# ----------------------------------------------------------------------------- everything else you can drive
func _build_generic(sp: Dictionary) -> void:
	var L: float = sp["len"]
	var W: float = sp["w"]
	var H: float = sp["h"]
	var bottom := float(sp["radius"]) + 0.14
	var bh := maxf(H - bottom - 0.1, 0.4)
	_add_boxes([[Vector3(W, bh, L * 0.92), Vector3(0, bottom + bh * 0.5, 0)]])
	add_child(visual_for(vehicle))
	_lamp_mat = _emitter(Color(0.9, 0.9, 0.95), Color(1.0, 0.97, 0.9), 0.0)
	_tail_mat = _emitter(Color(0.5, 0.0, 0.0), Color(1.0, 0.03, 0.01), 0.0)
	_rev_mat = _emitter(Color(0.8, 0.8, 0.8), Color(1, 1, 0.95), 0.0)
	var lamps := MB.new()
	var tails := MB.new()
	for sx in [-1.0, 1.0]:
		lamps.box(Transform3D(Basis(), Vector3(sx * W * 0.33, H * 0.42, L * 0.5 + 0.01)), Vector3(0.18, 0.08, 0.02), Color.WHITE)
		tails.box(Transform3D(Basis(), Vector3(sx * W * 0.36, H * 0.45, -L * 0.5 - 0.01)), Vector3(0.16, 0.08, 0.02), Color.WHITE)
	for pair in [[lamps, _lamp_mat], [tails, _tail_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0].commit()
		mi.material_override = pair[1]
		add_child(mi)
	_corner_lamps(Vector3(W * 0.45, H * 0.42, L * 0.5), Vector3(W * 0.45, H * 0.52, -L * 0.5 - 0.01),
		Vector3(W * 0.2, H * 0.36, -L * 0.5 - 0.01))
	# physics wheels (the model draws its own)
	var half_t := maxf(W * 0.5 - 0.18, 0.28)
	var ax := L * 0.5 - maxf(L * 0.17, 0.45)
	if sp.get("rider", false):                    # a two-wheeler: two wheels in line, the front steering, the rear driving
		var fw := _wheel(Vector3(0, float(sp["radius"]) + 0.18, ax), true, sp)
		fw.use_as_traction = false
		_wheel(Vector3(0, float(sp["radius"]) + 0.18, -ax), false, sp)
	else:
		for spec in [[half_t, ax, true], [-half_t, ax, true], [half_t, -ax, false], [-half_t, -ax, false]]:
			_wheel(Vector3(spec[0], float(sp["radius"]) + 0.18, spec[1]), spec[2], sp)
	if not sp.get("rider", false):
		_add_driver(DRIVER_SEAT + _generic_cabin(sp))


var _helpers := {}

## A standalone model of any vehicle kind (also used for the cars you leave parked).
func visual_for(kind: String, paint := Color(0, 0, 0, 0)) -> Node3D:
	var sp: Dictionary = SPECS[kind]
	var root := Node3D.new()
	root.name = "Visual"
	if Fleet.has(kind) and String(sp.get("glb", "")).contains("fleet_"):
		var p: Color = paint if paint.a > 0.0 else Fleet.paint_for(kind, RandomNumberGenerator.new())
		root.add_child(Fleet.model(kind, p))
	elif sp.has("glb"):
		var model := (load(sp["glb"]) as PackedScene).instantiate() as Node3D
		model.rotation.y = -PI * 0.5
		root.add_child(model)
	elif sp.has("kenney"):
		var path := "res://assets/drive/models/kenney/%s.glb" % sp["kenney"]
		if ResourceLoader.exists(path):
			var node := (load(path) as PackedScene).instantiate() as Node3D
			var aabb := AABB()
			var first := true
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				var box: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
				aabb = box if first else aabb.merge(box)
				first = false
			var sc: float = float(sp["len"]) / maxf(aabb.size.z, 0.01)
			node.scale = Vector3.ONE * sc
			node.position = Vector3(-aabb.get_center().x * sc, -aabb.position.y * sc, -aabb.get_center().z * sc)
			root.add_child(node)
	elif sp.has("built"):
		if not _helpers.has("life"):
			_helpers["life"] = load("res://scripts/drive/street_life.gd").new()
		var mi := MeshInstance3D.new()
		mi.mesh = _helpers["life"]._built(sp["built"])
		root.add_child(mi)
	elif sp.has("traffic"):
		if not _helpers.has("traffic"):
			_helpers["traffic"] = load("res://scripts/drive/traffic.gd").new()
		var mi := MeshInstance3D.new()
		mi.mesh = _helpers["traffic"]._mesh_bus() if sp["traffic"] == "bus" else _helpers["traffic"]._truck_mesh(randi() % 4)
		mi.material_override = MB.vertex_color_material(0.6)
		root.add_child(mi)
	elif sp.get("procedural", false):
		var mi := MeshInstance3D.new()             # the SUV parked: a simple stand-in body
		var mb := MB.new()
		mb.box(Transform3D(Basis(), Vector3(0, 0.95, 0)), Vector3(1.88, 1.1, 4.6), PAINT)
		mi.mesh = mb.commit()
		mi.material_override = MB.vertex_color_material(0.5)
		root.add_child(mi)
	return root


func _ready() -> void:
	_engine.play()
	_horn.play()


func forward() -> Vector3:
	return global_basis.z * FWD


# ----------------------------------------------------------------------------- body
func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.88, 1.2, 4.66)
	shape.shape = bx
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)

	var mb := MB.new()
	var at := func(p: Vector3) -> Transform3D: return Transform3D(Basis(), p)
	# main body: lower half, then the shoulder that runs into a long flat bonnet
	mb.box(at.call(Vector3(0, 0.78, 0)), Vector3(1.88, 0.62, 4.5), PAINT)
	var hood := [Vector3(-0.9, 1.09, 0.95), Vector3(0.9, 1.09, 0.95), Vector3(0.88, 1.02, 2.22), Vector3(-0.88, 1.02, 2.22)]
	mb.quad(hood[0], hood[1], hood[2], hood[3], PAINT, Vector3.UP)
	mb.quad(Vector3(-0.94, 0.47, 2.25), Vector3(0.94, 0.47, 2.25), Vector3(0.88, 1.02, 2.22), Vector3(-0.88, 1.02, 2.22),
		PAINT, Vector3.BACK)                                    # nose
	for sx in [-1.0, 1.0]:
		mb.quad(Vector3(sx * 0.94, 1.09, 0.95), Vector3(sx * 0.94, 1.09, 2.2), Vector3(sx * 0.94, 0.47, 2.25),
			Vector3(sx * 0.94, 0.47, 0.95), PAINT, Vector3(sx, 0, 0))    # front wings
	mb.box(at.call(Vector3(0, 1.08, -0.5)), Vector3(1.88, 0.06, 2.9), PAINT)   # beltline
	mb.box(at.call(Vector3(0, 0.78, -2.28)), Vector3(1.84, 0.62, 0.12), PAINT)  # tailgate lower
	# black cladding: bumpers, sills, wheel arches
	mb.box(at.call(Vector3(0, 0.42, 2.28)), Vector3(1.9, 0.26, 0.14), CLADDING)
	mb.box(at.call(Vector3(0, 0.42, -2.3)), Vector3(1.9, 0.28, 0.14), CLADDING)
	for sx in [-1.0, 1.0]:
		mb.box(at.call(Vector3(sx * 0.95, 0.42, 0.0)), Vector3(0.05, 0.16, 1.7), CLADDING)
		for sz in [-1.38, 1.38]:
			for a in 5:                                         # arch as a short arc of blocks
				var ang := PI * (a + 0.5) / 5.0
				var p := Vector3(sx * 0.955, 0.55 + sin(ang) * 0.44, sz + cos(ang) * 0.44)
				mb.box(Transform3D(Basis(Vector3.RIGHT, -ang + PI * 0.5), p), Vector3(0.05, 0.1, 0.3), CLADDING)
		# door shut lines and flush handles
		for dz in [0.15, -1.05]:
			mb.box(at.call(Vector3(sx * 0.943, 0.8, dz)), Vector3(0.01, 0.55, 0.015), BLACK)
		for hz in [-0.2, -1.35]:
			mb.box(at.call(Vector3(sx * 0.945, 0.98, hz)), Vector3(0.012, 0.03, 0.2), CHROME)
		# door mirrors in body colour with black arms
		mb.box(at.call(Vector3(sx * 1.02, 1.18, 0.75)), Vector3(0.14, 0.03, 0.05), BLACK)
		mb.box(at.call(Vector3(sx * 1.1, 1.22, 0.72)), Vector3(0.07, 0.15, 0.22), PAINT)
	# grille: a big black shield with vertical chrome slats
	mb.box(at.call(Vector3(0, 0.78, 2.262)), Vector3(1.2, 0.42, 0.02), BLACK)
	for k in 11:
		mb.box(at.call(Vector3(-0.55 + k * 0.11, 0.78, 2.275)), Vector3(0.018, 0.38, 0.01), CHROME)
	mb.box(at.call(Vector3(0, 1.0, 2.27)), Vector3(1.24, 0.03, 0.02), CHROME)
	mb.box(at.call(Vector3(0, 0.55, 2.3)), Vector3(0.75, 0.1, 0.04), BLACK)    # lower intake
	# roof, pillars and rails (the black floating roof)
	mb.box(at.call(Vector3(0, 1.74, -0.72)), Vector3(1.62, 0.05, 2.15), BLACK)
	for sx in [-1.0, 1.0]:
		mb.box(at.call(Vector3(sx * 0.72, 1.79, -0.72)), Vector3(0.04, 0.04, 1.9), CHROME)
		for rz in [-1.55, 0.1]:
			mb.box(at.call(Vector3(sx * 0.72, 1.77, rz)), Vector3(0.05, 0.04, 0.06), BLACK)
		# A, B, C pillars
		mb.quad(Vector3(sx * 0.9, 1.1, 0.95), Vector3(sx * 0.9, 1.1, 0.88), Vector3(sx * 0.8, 1.72, 0.3),
			Vector3(sx * 0.8, 1.72, 0.37), BLACK, Vector3(sx, 0.3, 0.3))
		mb.box(at.call(Vector3(sx * 0.86, 1.4, -0.45)), Vector3(0.06, 0.62, 0.1), BLACK)
		mb.quad(Vector3(sx * 0.9, 1.1, -2.2), Vector3(sx * 0.9, 1.1, -1.75), Vector3(sx * 0.8, 1.72, -1.7),
			Vector3(sx * 0.8, 1.72, -1.8), BLACK, Vector3(sx, 0.2, -0.2))
	mb.box(at.call(Vector3(0, 1.66, -1.84)), Vector3(1.5, 0.06, 0.18), BLACK)   # rear spoiler
	# number plates
	mb.box(at.call(Vector3(0, 0.5, 2.32)), Vector3(0.52, 0.13, 0.02), Color(0.95, 0.95, 0.92))
	mb.box(at.call(Vector3(0, 0.78, -2.35)), Vector3(0.52, 0.13, 0.02), Color(0.95, 0.95, 0.92))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mb.commit()
	var paint := MB.vertex_color_material(0.25)
	paint.metallic = 0.55
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.8
	body.material_override = paint
	add_child(body)
	for zp in [[Vector3(0, 0.5, 2.335), 0.0], [Vector3(0, 0.78, -2.365), PI]]:
		var plate := Label3D.new()
		plate.text = "TN 43 AB 1947"
		plate.font_size = 22
		plate.pixel_size = 0.0035
		plate.modulate = Color(0.02, 0.02, 0.02)
		plate.double_sided = false
		plate.position = zp[0]
		plate.rotation.y = zp[1]
		add_child(plate)

	# the glasshouse: windscreen, side windows, rear glass (tinted, see-through)
	var gl := MB.new()
	var tint := Color(0.06, 0.08, 0.1)
	var w0 := 0.9
	var w1 := 0.79
	gl.quad(Vector3(-w0, 1.1, 0.93), Vector3(w0, 1.1, 0.93), Vector3(w1, 1.72, 0.34), Vector3(-w1, 1.72, 0.34), tint, Vector3(0, 0.6, 1))
	gl.quad(Vector3(-w0, 1.1, -2.18), Vector3(w0, 1.1, -2.18), Vector3(w1, 1.72, -1.78), Vector3(-w1, 1.72, -1.78), tint, Vector3(0, 0.3, -1))
	for sx in [-1.0, 1.0]:
		gl.quad(Vector3(sx * w0, 1.1, 0.92), Vector3(sx * w0, 1.1, -2.17), Vector3(sx * w1, 1.72, -1.77),
			Vector3(sx * w1, 1.72, 0.33), tint, Vector3(sx, 0.2, 0))
	_glass = MeshInstance3D.new()
	var glass := _glass
	glass.mesh = gl.commit()
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.albedo_color = Color(0.6, 0.65, 0.7, 0.78)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.08
	gm.metallic_specular = 0.35
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	# lamps: C-shaped LED daytime running lights, headlamp lenses, split tail lamps
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.9, 0.95, 1.0)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.85, 0.93, 1.0)
	_lamp_mat.emission_energy_multiplier = 2.5
	var drl := MB.new()
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 0.72
		drl.box(at.call(Vector3(cx + sx * 0.12, 0.8, 2.27)), Vector3(0.025, 0.36, 0.02), Color.WHITE)   # C spine
		drl.box(at.call(Vector3(cx + sx * 0.06, 0.97, 2.268)), Vector3(0.14, 0.025, 0.02), Color.WHITE)
		drl.box(at.call(Vector3(cx + sx * 0.06, 0.63, 2.268)), Vector3(0.14, 0.025, 0.02), Color.WHITE)
		drl.box(at.call(Vector3(cx - sx * 0.02, 1.0, 2.2)), Vector3(0.24, 0.05, 0.05), Color.WHITE)  # headlamp strip
	var drl_mi := MeshInstance3D.new()
	drl_mi.mesh = drl.commit()
	drl_mi.material_override = _lamp_mat
	add_child(drl_mi)
	var tail_mat := _emitter(Color(0.5, 0.02, 0.02), Color(1.0, 0.04, 0.02), 0.3)
	_tail_mat = tail_mat
	# reverse lamps and amber indicators (front corners, mirrors' line, rear)
	_rev_mat = _emitter(Color(0.8, 0.8, 0.8), Color(1, 1, 0.95), 0.0)
	var rev := MB.new()
	for sx in [-1.0, 1.0]:
		rev.box(at.call(Vector3(sx * 0.62, 0.62, -2.31)), Vector3(0.12, 0.06, 0.02), Color.WHITE)
	var rev_mi := MeshInstance3D.new()
	rev_mi.mesh = rev.commit()
	rev_mi.material_override = _rev_mat
	add_child(rev_mi)
	for side in [1.0, -1.0]:                       # +X is the car's left
		var m := _emitter(Color(0.6, 0.35, 0.02), Color(1.0, 0.55, 0.05), 0.0)
		var ind := MB.new()
		ind.box(at.call(Vector3(side * 0.88, 0.78, 2.22)), Vector3(0.1, 0.05, 0.05), Color.WHITE)
		ind.box(at.call(Vector3(side * 0.86, 1.06, -2.29)), Vector3(0.12, 0.04, 0.02), Color.WHITE)
		ind.box(at.call(Vector3(side * 1.0, 1.12, 0.62)), Vector3(0.03, 0.03, 0.12), Color.WHITE)
		var ind_mi := MeshInstance3D.new()
		ind_mi.mesh = ind.commit()
		ind_mi.material_override = m
		add_child(ind_mi)
		_ind_mats.append(m)
	var tail := MB.new()
	for sx in [-1.0, 1.0]:
		tail.box(at.call(Vector3(sx * 0.78, 1.0, -2.3)), Vector3(0.3, 0.08, 0.03), Color.WHITE)
		tail.box(at.call(Vector3(sx * 0.9, 0.9, -2.2)), Vector3(0.04, 0.2, 0.2), Color.WHITE)
	var tail_mi := MeshInstance3D.new()
	tail_mi.mesh = tail.commit()
	tail_mi.material_override = tail_mat
	add_child(tail_mi)

	# the driver, seen through the glass in chase view
	var drv := MB.new()
	drv.box(at.call(Vector3(-0.42, 1.18, -0.2)), Vector3(0.44, 0.5, 0.28), Color(0.85, 0.85, 0.82))  # white shirt
	drv.box(at.call(Vector3(-0.42, 1.55, -0.18)), Vector3(0.19, 0.24, 0.21), Color(0.30, 0.17, 0.10))
	drv.box(at.call(Vector3(-0.42, 1.68, -0.2)), Vector3(0.21, 0.06, 0.23), Color(0.02, 0.02, 0.02))
	_driver = MeshInstance3D.new()
	_driver.mesh = drv.commit()
	_driver.material_override = MB.vertex_color_material(0.8)
	add_child(_driver)


## Dashboard with twin screens, seats, steering wheel and a rear-view mirror (cockpit view).
func _build_cockpit() -> void:
	var mat := MB.vertex_color_material(0.6)
	var mb := MB.new()
	var at := func(p: Vector3) -> Transform3D: return Transform3D(Basis(), p)
	mb.box(at.call(Vector3(0, 1.05, 0.72)), Vector3(1.72, 0.16, 0.42), Color(0.08, 0.07, 0.065))   # dash top
	mb.box(at.call(Vector3(0, 0.85, 0.7)), Vector3(1.6, 0.3, 0.3), Color(0.12, 0.1, 0.09))          # dash face
	mb.box(at.call(Vector3(0, 0.75, 0.25)), Vector3(0.25, 0.25, 0.7), Color(0.1, 0.09, 0.08))       # centre console
	for seat_x in [-0.42, 0.42]:
		mb.box(at.call(Vector3(seat_x, 0.72, -0.25)), Vector3(0.52, 0.14, 0.52), Color(0.16, 0.13, 0.11))
		mb.box(at.call(Vector3(seat_x, 1.08, -0.52)), Vector3(0.52, 0.66, 0.12), Color(0.16, 0.13, 0.11))
	# a centre infotainment screen (the analog cluster sits in front of the driver)
	mb.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Vector3(0.18, 1.16, 0.7)), Vector3(0.36, 0.17, 0.03),
		Color(0.01, 0.015, 0.03))
	var dash := MeshInstance3D.new()
	dash.mesh = mb.commit()
	dash.material_override = mat
	add_child(dash)
	_screen_speed = Label3D.new()
	_screen_speed.font_size = 48
	_screen_speed.pixel_size = 0.0011
	_screen_speed.modulate = Color(0.75, 0.9, 1.0)
	_screen_speed.position = Vector3(-0.5, 1.17, 0.672)
	_screen_speed.rotation = Vector3(deg_to_rad(-18.0), PI, 0.0)
	_screen_speed.double_sided = false
	add_child(_screen_speed)
	_screen_info = Label3D.new()
	_screen_info.font_size = 24
	_screen_info.pixel_size = 0.0011
	_screen_info.modulate = Color(0.55, 0.85, 1.0)
	_screen_info.position = Vector3(-0.2, 1.17, 0.672)
	_screen_info.rotation = Vector3(deg_to_rad(-18.0), PI, 0.0)
	_screen_info.double_sided = false
	add_child(_screen_info)

	_steering_wheel = Node3D.new()
	_steering_wheel.position = Vector3(-0.42, 1.05, 0.42)
	_steering_wheel.rotation.x = deg_to_rad(-65.0)
	add_child(_steering_wheel)
	var sw := MB.new()
	for k in 18:
		var a0 := TAU * k / 18.0
		var a1 := TAU * (k + 1) / 18.0
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.18
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.18
		sw.box(Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) * 0.5), Vector3(0.03, 0.03, p0.distance_to(p1)), BLACK)
	sw.box(Transform3D(Basis(), Vector3.ZERO), Vector3(0.34, 0.02, 0.05), Color(0.08, 0.08, 0.08))
	sw.cylinder(Transform3D(Basis(), Vector3(0, -0.03, 0)), 0.06, 0.06, 0.05, Color(0.1, 0.1, 0.1), 12)
	var swi := MeshInstance3D.new()
	swi.mesh = sw.commit()
	swi.material_override = mat
	_steering_wheel.add_child(swi)

	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(320, 96)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 38.0
	_mirror_cam.far = 800.0
	_mirror_vp.add_child(_mirror_cam)
	var mirror := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.065)
	mirror.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_texture = _mirror_vp.get_texture()
	mm.uv1_scale = Vector3(-1, 1, 1)
	mm.uv1_offset = Vector3(1, 0, 0)
	mirror.material_override = mm
	mirror.position = Vector3(-0.02, 1.66, 0.5)
	mirror.rotation.y = PI
	add_child(mirror)


func set_cockpit(on: bool) -> void:
	cockpit = on
	if _driver:
		_driver.visible = not on
	if _rider:
		_rider.visible = not on
	if kit:
		kit.set_active(on)
	for vp in screens:
		(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _engine:
		_engine.volume_db = -7.0 if on else 0.0        # muffled inside the cabin
	if _glass:
		_glass.visible = not on          # from inside, the tinted glass would veil the view
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## Throttle actually applied (0..1), for fuel burn.
func pedal() -> float:
	return 0.0 if out_of_fuel else _thr


## Weather grip: 1 dry, ~0.7 on wet tarmac.
func set_grip(mult: float) -> void:
	if absf(mult - _weather_grip) < 0.002:             # (called every step by the city's weather)
		return
	_weather_grip = mult
	_apply_grip()


## The weather's grip as these tyres feel it: a scooter's lose more of it in the wet than a car's.
func _wet_grip() -> float:
	return clampf(1.0 - (1.0 - _weather_grip) * wet_k, 0.2, 1.0)


## Off the road the tyres find less grip and much more rolling resistance: grass and dirt
## slow you down and slide, so the road is where you want to be (no invisible walls).
func set_surface(kind: String) -> void:
	if kind == surface:
		return
	surface = kind
	match kind:
		"asphalt", "concrete":
			_surface_grip = 1.0
			_surface_drag = 0.0
		"gravel":
			_surface_grip = 0.65
			_surface_drag = 40.0
		"mud":
			_surface_grip = 0.4
			_surface_drag = 100.0
		"shoulder":
			_surface_grip = 0.85
			_surface_drag = 160.0
		_:
			_surface_grip = 0.62
			_surface_drag = 420.0
	_apply_grip()


func _apply_grip() -> void:
	for w in _wheels:
		var vw := w as VehicleWheel3D
		vw.wheel_friction_slip = tyre_grip * _wet_grip() * _surface_grip * (rear_grip if vw.position.z < 0.0 else 1.0)


func gear_name() -> String:
	return "R" if gear == 0 else str(gear)


func _build_wheels() -> void:
	var tyre := MB.new()
	tyre.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.13, 0, 0)), WHEEL_R, WHEEL_R, 0.26, Color(0.02, 0.02, 0.02), 18)
	# diamond-cut alloy: rim disc plus five spokes
	tyre.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.14, 0, 0)), 0.24, 0.24, 0.02, Color(0.12, 0.12, 0.13), 16)
	for k in 5:
		var a := TAU * k / 5.0
		tyre.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3(0.15, 0, 0) + Vector3(0, cos(a), sin(a)) * 0.12),
			Vector3(0.02, 0.2, 0.05), CHROME)
	tyre.cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.155, 0, 0)), 0.05, 0.05, 0.02, CHROME, 10)
	var tyre_mesh := tyre.commit()
	var mat := MB.vertex_color_material(0.4)
	mat.metallic = 0.5
	for spec in [[0.8, 1.38, true], [-0.8, 1.38, true], [0.8, -1.38, false], [-0.8, -1.38, false]]:
		var w := VehicleWheel3D.new()
		w.position = Vector3(spec[0], 0.55, spec[1])
		w.use_as_traction = true                              # AWD
		w.use_as_steering = spec[2]
		w.wheel_radius = WHEEL_R
		w.wheel_rest_length = 0.2
		w.suspension_travel = 0.22
		w.suspension_stiffness = 30.0                          # soft, comfortable
		w.suspension_max_force = 32000.0
		w.damping_compression = 2.8
		w.damping_relaxation = 3.4
		w.wheel_friction_slip = 4.6
		w.wheel_roll_influence = 0.15                          # less body roll
		_wheels.append(w)
		var mi := MeshInstance3D.new()
		mi.mesh = tyre_mesh
		mi.material_override = mat
		if spec[0] < 0:
			mi.rotation.y = PI
		w.add_child(mi)
		add_child(w)


func _build_lights() -> void:
	for sx in [-0.72, 0.72]:
		var s := SpotLight3D.new()
		var lp: Vector3 = SPECS[vehicle].get("lamp", Vector3(0.72, 0.98, 2.3))
		if SPECS[vehicle].has("len"):
			lp = Vector3(float(SPECS[vehicle]["w"]) * 0.33, float(SPECS[vehicle]["h"]) * 0.42, float(SPECS[vehicle]["len"]) * 0.5 + 0.05)
		s.position = Vector3(signf(sx) * lp.x, lp.y, lp.z + 0.35)   # just ahead of the lens, clear of the bonnet
		s.rotation = Vector3(deg_to_rad(-4.0), PI, 0.0)
		s.light_color = Color(0.95, 0.97, 1.0)                 # LED projectors
		s.light_energy = 18.0
		s.spot_range = 110.0
		s.spot_angle = 30.0
		s.spot_attenuation = 1.1
		s.spot_angle_attenuation = 1.6                     # bright centre, soft edge to the beam
		s.light_volumetric_fog_energy = 3.0                # the beam shows in night mist
		s.shadow_enabled = sx > 0.0                        # one shadowed lamp: trees, posts, walls throw shadows
		s.visible = false
		add_child(s)
		_headlights.append(s)


func _build_audio() -> void:
	_road = AudioStreamPlayer.new()
	var rg := AudioStreamGenerator.new()
	rg.mix_rate = 22050.0
	rg.buffer_length = 0.12
	_road.stream = rg
	_road.volume_db = -14.0
	add_child(_road)
	for i in 2:
		var p := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.12
		p.stream = gen
		p.volume_db = -19.0 if i == 0 else -10.0
		add_child(p)
		if i == 0:
			_engine = p
		else:
			_horn = p


# ----------------------------------------------------------------------------- driving
func _emitter(albedo: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	return m


## Brake, tail, reverse and indicator lamps, every frame. Indicators blink at 1.5 Hz and cancel
## themselves once a turn is done (the wheel back near centre after ~35° of heading change).
func _update_lamps(delta: float) -> void:
	var braking := _brk > 0.1 and gear != 0 or (gear == 0 and not manual and _thr > 0.1 and speed > 0.3)
	_tail_mat.emission_energy_multiplier = 6.0 if braking else (1.4 if lights_on else 0.3)
	_rev_mat.emission_energy_multiplier = 4.0 if gear == 0 and absf(speed) < 12.0 and (_brk > 0.05 or speed < -0.2) else 0.0
	if not autopilot:
		if Input.is_action_just_pressed("indicate_left"):
			indicator = 0 if indicator == 1 else 1
			_ind_yaw = global_rotation.y
		if Input.is_action_just_pressed("indicate_right"):
			indicator = 0 if indicator == -1 else -1
			_ind_yaw = global_rotation.y
		if Input.is_action_just_pressed("hazards"):
			indicator = 0 if indicator == 2 else 2
	if indicator == 1 or indicator == -1:
		var turned := absf(wrapf(global_rotation.y - _ind_yaw, -PI, PI))
		if turned > 0.6 and absf(_steer_in) < 0.12:
			indicator = 0
	_blink += delta
	var on := fmod(_blink, 0.66) < 0.36
	_ind_mats[0].emission_energy_multiplier = 5.0 if on and (indicator == 1 or indicator == 2) else 0.0
	_ind_mats[1].emission_energy_multiplier = 5.0 if on and (indicator == -1 or indicator == 2) else 0.0


func set_lights(on: bool) -> void:
	lights_on = on
	var broken: bool = float(damage.get("front", 0.0)) >= 0.45
	for s in _headlights:
		s.visible = on and not broken
	_lamp_mat.emission_energy_multiplier = 0.0 if broken else (5.0 if on else (0.6 if is_coupe else 2.5))


func honk() -> void:
	_horn_time = 0.45
	honked = true


## 2.2 L diesel: 450 N·m across 1,600–2,800 rpm.
## This vehicle's engine, gearbox, brakes, drag and tyres, from its DRIVE profile. The vehicle body's own damping
## is switched off: the drag is the profile's (Godot's default damping had acted as a hidden brake).
func _set_drive(kind: String) -> void:
	var of: Array = DRIVE_OF.get(kind, ["diesel_suv", 1.0])
	drive_kind = of[0]
	var d: Dictionary = DRIVE[drive_kind]
	torque_mul = float(of[1])
	_curve = d["torque"]
	_cvt = d.get("cvt", [])
	_band = d.get("rpm_band", [3200.0, 7000.0])
	ratios = d.get("ratios", [1.0])
	final_drive = float(d["final"])
	reverse_ratio = float(d["reverse"])
	idle_rpm = float(d["idle"])
	redline = float(d["redline"])
	_up = d["up"]
	brake_full = float(d["brake_g"]) * 9.81 * mass / BRAKE_K * (2.0 if two_wheeler else 1.0)   # (two wheels share it, not four)
	cda = float(d["cda"])
	crr = float(d["crr"])
	tyre_grip = float(d["grip"])
	rear_grip = float(d.get("rear_grip", 1.0))
	wet_k = float(d.get("wet_k", 1.0))
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	rpm = idle_rpm
	_apply_grip()


func _torque(r: float) -> float:
	if _curve.is_empty():
		return 0.0
	if r <= _curve[0][0]:
		return _curve[0][1]
	for i in range(1, _curve.size()):
		if r <= _curve[i][0]:
			return lerpf(_curve[i - 1][1], _curve[i][1], (r - _curve[i - 1][0]) / (_curve[i][0] - _curve[i - 1][0]))
	return _curve[-1][1]


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_body(delta)
	Prof.add("car_physics", _p0)


func _physics_process_body(delta: float) -> void:
	speed = linear_velocity.dot(forward())
	_feel_t -= delta
	if _feel_t <= 0.0:                                  # the road under it: the city's collision says what it is
		_feel_t = 0.1
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6, global_position + Vector3.DOWN * 1.2)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is CollisionObject3D:
			var co := hit["collider"] as CollisionObject3D
			var owner_id := co.shape_find_owner(int(hit["shape"]))
			var sn = co.shape_owner_get_owner(owner_id) if owner_id >= 0 else null
			if sn is Node and (sn as Node).has_meta("surface"):
				set_surface(str((sn as Node).get_meta("surface")))
	var target_steer := in_steer
	if not autopilot:
		in_throttle = Input.get_action_strength("accelerate")
		in_brake = Input.get_action_strength("brake")
		target_steer = Input.get_axis("steer_right", "steer_left")
		in_handbrake = Input.is_action_pressed("handbrake")
		# Euro Truck-style: pedals and steering ramp instead of snapping
		_thr = move_toward(_thr, in_throttle, delta * (1.0 if in_throttle > _thr else 3.0))
		_brk = move_toward(_brk, in_brake, delta * (2.2 if in_brake > _brk else 5.0))
		var turning_in := absf(target_steer) > absf(_steer_in) and signf(target_steer) == signf(_steer_in)
		# gentle in (slower still at speed), quicker back to centre
		var calm := lerpf(1.0, 0.55, smoothstep(5.0, 25.0, absf(speed)))
		var rate := (0.6 * steer_sens * calm) if (turning_in or _steer_in == 0.0) else 1.8
		_steer_in = move_toward(_steer_in, target_steer, rate * delta)
	else:
		_thr = in_throttle
		_brk = in_brake
		_steer_in = target_steer
	_shift_timer -= delta
	if not manual:
		if _brk > 0.05 and speed < 0.4 and gear != 0 and reverse_ratio > 0.0:   # (a two-wheeler has no reverse)
			gear = 0
		elif _thr > 0.05 and gear == 0 and speed > -0.4:
			gear = 1
	var wheel_rpm := absf(speed) / (TAU * wheel_r) * 60.0
	var pedal := _brk if (gear == 0 and not manual) else _thr
	var ratio: float
	if not _cvt.is_empty():                             # a CVT: the engine held in its band, the ratio sliding
		gear = 0 if gear == 0 else 1
		var want := lerpf(float(_band[0]), float(_band[1]), pedal)
		ratio = clampf(want / maxf(wheel_rpm, 1.0), float(_cvt[1]), float(_cvt[0])) if gear != 0 else float(_cvt[0])
		rpm = maxf(wheel_rpm * ratio, lerpf(idle_rpm, want, pedal))   # (below the band the clutch slips)
	else:
		ratio = reverse_ratio if gear == 0 else ratios[gear - 1]
		rpm = maxf(wheel_rpm * ratio * final_drive, lerpf(idle_rpm, idle_rpm * 2.0, pedal) if absf(speed) < 2.5 else idle_rpm)
	rpm = minf(rpm, redline + 150.0)
	if not manual and _cvt.is_empty() and gear >= 1 and _shift_timer <= 0.0:
		var up_at := lerpf(float(_up[0]), float(_up[1]), _thr)
		if rpm > up_at and gear < ratios.size():
			gear += 1
			_shift_timer = 0.25
		elif rpm < maxf(idle_rpm * 1.45, float(_up[0]) * 0.55) and gear > 1:
			gear -= 1
			_shift_timer = 0.25
		elif _thr > 0.9 and gear > 1 and rpm < up_at * 0.64 and ratios[gear - 2] / ratios[gear - 1] * rpm < up_at - 500.0:
			gear -= 1                                   # kickdown: floor it and it drops a gear (only to a gear it
			_shift_timer = 0.2                          #  won't leave again at once: no hunting between two)
	if out_of_fuel:
		pedal = 0.0
	elif _shift_timer > 0.0:
		pedal *= 0.25                                   # a torque dip while the box shifts, not a dead stop
	var dir := -1.0 if gear == 0 else 1.0
	var drive_force := 0.0
	if rpm < redline and absf(speed) < top_speed:
		drive_force = _torque(rpm) * torque_mul * ratio * (1.0 if not _cvt.is_empty() else final_drive) / wheel_r * 0.88 * pedal * dir
	var br := 0.0
	if gear != 0 and _brk > 0.05 and not (manual and gear == 0):
		br = _brk * brake_full
	if gear == 0 and not manual and _thr > 0.05:
		br = _thr * brake_full
	if pedal < 0.05:                                    # engine braking, off the throttle
		br = maxf(br, (0.5 + rpm / redline * 2.4) * mass / 1500.0)
	if in_handbrake:
		br = brake_full * 1.2
	# the road's grip caps what the tyres can do (VehicleWheel3D's friction doesn't limit the brakes or the drive by
	# itself): about 1 g on dry tarmac, 0.7 wet, less off the road. Braking past it is lost, as ABS loses it (he
	# keeps steering), and the tyres squeal; the drive past it spins them.
	var mu := _wet_grip() * _surface_grip
	var cap := mu * 9.81 * mass / BRAKE_K * (2.0 if two_wheeler else 1.0)
	var over := 0.0
	if br > cap and not in_handbrake:
		over = (br - cap) / maxf(br, 0.001)
		br = cap
	var drive_cap := mu * 9.81 * mass
	if absf(drive_force) > drive_cap:
		over = maxf(over, (absf(drive_force) - drive_cap) / absf(drive_force))
		drive_force = signf(drive_force) * drive_cap
	# tyre slip (VehicleWheel3D skid info: 1 = gripping, 0 = sliding)
	var grip := 1.0
	var on_ground := false
	for w in _wheels:
		if (w as VehicleWheel3D).is_in_contact():
			on_ground = true
			grip = minf(grip, (w as VehicleWheel3D).get_skidinfo())
	slip = move_toward(slip, maxf(clampf((0.75 - grip) / 0.6, 0.0, 1.0), over * 2.0) if on_ground and absf(speed) > 2.0 else 0.0, delta * 6.0)
	# ABS: when the wheels lock under braking, pulse the brakes (about 12 times a second)
	_abs_t += delta
	if br > brake_full * 0.3 and grip < 0.45 and absf(speed) > 3.0 and not in_handbrake:
		br *= 0.35 if fmod(_abs_t, 0.083) < 0.04 else 1.0
	# traction control: wheelspin from a standstill eases the throttle
	if pedal > 0.3 and grip < 0.5 and absf(speed) < 14.0:
		drive_force *= 0.55
	var driven := 0                                     # (split between the driven wheels: two on a scooter)
	for w in _wheels:
		if (w as VehicleWheel3D).use_as_traction:
			driven += 1
	engine_force = drive_force / float(maxi(driven, 1)) * FWD
	brake = br
	if in_handbrake and not two_wheeler:                # the handbrake holds the rear wheels only, and locked they
		for w in _wheels:                               #  slide sideways too: the tail can come round
			var vw := w as VehicleWheel3D
			vw.brake = brake_full * 1.6 if vw.position.z < 0.0 else _brk * brake_full
			if vw.position.z < 0.0 and absf(speed) > 3.0:
				vw.wheel_friction_slip = 0.35 * _wet_grip() * _surface_grip     # (locked: a fixed low grip, not a share of a grippy tyre)
		_hb_on = true
	elif _hb_on:
		_hb_on = false
		_apply_grip()
	if two_wheeler:
		_balance(delta, on_ground)
	elif on_ground:
		# anti-roll bars: the body leans into a corner but settles, it doesn't wallow
		var fwd_axis := forward()
		var roll := asin(clampf(global_transform.basis.x.y, -1.0, 1.0))
		var roll_rate := angular_velocity.dot(fwd_axis)
		apply_torque(-fwd_axis * (roll * mass * 5.5 + roll_rate * mass * 0.8))
		# yaw stability at speed (a gentle hand, like ESP), off with the handbrake
		if not in_handbrake and absf(speed) > 8.0:
			var yaw_rate := angular_velocity.dot(global_transform.basis.y)
			var expect := steering * speed / 2.7
			apply_torque(global_transform.basis.y * (expect - yaw_rate) * mass * 0.35 * smoothstep(8.0, 25.0, absf(speed)))
	# bumps: vertical shock, for the camera and the suspension thud
	var vy := linear_velocity.y
	jolt = absf(vy - _vy_prev) / maxf(delta, 0.001)
	_vy_prev = vy
	if jolt > 18.0:
		_thud = minf(1.0, _thud + jolt / 80.0)
	var v := linear_velocity.length()
	if v > 0.3:
		# rolling resistance and air drag, this vehicle's own (and more of it off the tarmac)
		apply_central_force(-linear_velocity / v * (crr * mass * 9.81 + 0.6 * cda * v * v + _surface_drag * mass / 1500.0 * minf(v, 12.0)))
	# speed-sensitive steering: full lock at a crawl, a few degrees at highway speed
	# full lock only at a crawl (hairpins, parking); it falls away quickly once you're moving
	var s := smoothstep(0.0, 18.0, absf(speed))
	var max_s := lerpf(MAX_STEER, HIGH_SPEED_STEER, sqrt(s)) * (lerpf(1.0, steer_sens, s) if not autopilot else 1.0)
	if two_wheeler and _wheels.size() >= 2:              # (a rider's bars ask no more turn than the tyres hold: ~0.95 g)
		var wb := maxf(absf((_wheels[0] as Node3D).position.z - (_wheels[_wheels.size() - 1] as Node3D).position.z), 0.8)
		max_s = minf(max_s, atan(wb * 0.95 * _wet_grip() * _surface_grip * 9.81 / maxf(speed * speed, 1.0)))
	steering = move_toward(steering, _steer_in * max_s + _pull, delta * (1.0 if not autopilot else 2.5))


## A crash is a change of velocity no brake makes (over 3 m/s in one step) while touching something that isn't the
## road: the hardest contact says which side took it.
## After a crash into something that can't take momentum itself (the traffic, moved by script): this body keeps
## its share, `along` m/s in the direction `n`, as if the two had moved off together.
func share_momentum(n: Vector3, along: float) -> void:
	_share = Vector4(n.x, n.y, n.z, along)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _share != Vector4.ZERO:
		var n := Vector3(_share.x, _share.y, _share.z)
		state.linear_velocity += n * (_share.w - state.linear_velocity.dot(n))
		_share = Vector4.ZERO
		_v_prev = state.linear_velocity
		return
	var dv := state.linear_velocity - _v_prev
	var before := _v_prev
	_v_prev = state.linear_velocity
	if dv.length() < 3.0:
		return
	var best := -1
	var most := 0.0
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		if n.y > 0.6:                                    # (the ground under it)
			continue
		var imp := state.get_contact_impulse(i).length()
		if imp > most:
			most = imp
			best = i
	if best < 0:
		return
	var ln := global_basis.inverse() * state.get_contact_local_normal(best)   # (pushed this way: the hit came from the other)
	var zone := "front" if ln.z < -0.5 else ("rear" if ln.z > 0.5 else ("left" if ln.x < 0.0 else "right"))
	var severity := clampf((dv.length() - 3.0) / 12.0, 0.05, 1.0)
	hit_velocity = before
	hit_normal = state.get_contact_local_normal(best)
	hit_point = state.get_contact_local_position(best)
	_hit(zone, severity, state.get_contact_collider_object(best))


func _hit(zone: String, severity: float, other: Object) -> void:
	damage[zone] = minf(1.0, float(damage[zone]) + severity * 0.6)
	_crash = maxf(_crash, 0.4 + severity * 0.6)
	jolt = maxf(jolt, 30.0 + severity * 90.0)          # (the camera feels it)
	_apply_damage()
	print("CRASH %s %.2f (front %.2f rear %.2f left %.2f right %.2f)" % [zone, severity, damage["front"], damage["rear"], damage["left"], damage["right"]])
	if hit_point != Vector3.ZERO:
		# the dent: centred where the panels are (a wall's contact can be at the floor's edge), as wide and deep
		# as the hit was hard: a 50 km/h crash crumples the whole nose by a hand's width or more
		var lp := to_local(hit_point)
		var sp: Dictionary = SPECS.get(vehicle, {})
		lp.y = clampf(lp.y, 0.45, float(sp.get("h", 1.5)) * 0.45)
		if zone == "front" or zone == "rear":                   # (square on: towards the middle of the nose)
			lp.x *= 0.5
		else:
			lp.z *= 0.6
		var skip: Array = _wheels + _cab_parts + [_rider]
		var n := Dents.dent(self, to_global(lp), hit_normal, 0.45 + severity * 0.75, 0.04 + severity * 0.26, _dents, skip)
		print("DENT %d vertices, %d meshes, at %s local" % [n, _dents.size(), str(lp.snapped(Vector3.ONE * 0.01))])
	impacted.emit(zone, severity, other)


## What the damage shows and does: broken headlights, a cracked windscreen, a pull, a limping engine.
func _apply_damage() -> void:
	var front: float = damage["front"]
	if front >= 0.45:
		for h in _headlights:
			(h as Node3D).visible = false
		if _lamp_mat:
			_lamp_mat.emission_energy_multiplier = 0.0
	if front >= 0.65 and _glass and _glass.material_override is BaseMaterial3D:
		if _glass_mat == null:
			_glass_mat = _glass.material_override
		var g := (_glass.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
		g.albedo_color = Color(0.55, 0.58, 0.6, 0.9)               # (crazed: milky, rough)
		g.roughness = 0.7
		g.metallic = 0.1
		_glass.material_override = g
	_pull = clampf(front - 0.5, 0.0, 0.5) * 0.06 * (1.0 if float(damage["left"]) >= float(damage["right"]) else -1.0)
	var total: float = damage["front"] + damage["rear"] + damage["left"] + damage["right"]
	torque_mul = float(DRIVE_OF.get(vehicle, ["", 1.0])[1]) * (0.6 if total > 2.5 else 1.0)


## Mended (a garage, a new day's car): no damage, the lamps and the glass as they were.
func repair() -> void:
	for k in damage:
		damage[k] = 0.0
	_pull = 0.0
	torque_mul = float(DRIVE_OF.get(vehicle, ["", 1.0])[1])
	Dents.mend(_dents)
	if _glass_mat and _glass:
		_glass.material_override = _glass_mat
	_glass_mat = null
	if _lamp_mat:
		set_lights(lights_on)


## A two-wheeler kept up and leaned as a rider does it: the lean a turn needs (tan = v·yaw-rate / g, into the turn),
## held by a torque about its length (a spring to the target, a damper on the rate); at a crawl it is held upright
## (his feet), and never past 45°. The rider is part of the body, so he leans with it.
func _balance(delta: float, on_ground: bool) -> void:
	var fwd_axis := forward()
	lean = asin(clampf(global_basis.x.y, -1.0, 1.0))
	var rate := angular_velocity.dot(fwd_axis)
	var yaw_rate := angular_velocity.dot(Vector3.UP)
	var v := absf(speed)
	var want := -atan(v * yaw_rate / 9.81) * smoothstep(1.0, 4.0, v)
	lean_target = lerp_angle(lean_target, clampf(want, -0.78, 0.78), 1.0 - exp(-delta * 8.0))
	# (a critically damped spring on the roll rate: a plain torque, against these light bodies' tiny shape-made
	#  inertia, overshot and threw them over)
	var w0 := lerpf(22.0, 16.0, smoothstep(1.0, 6.0, v))          # (stiffer at a crawl: his feet)
	if not on_ground:
		w0 *= 0.3
		_lean_i = 0.0
	var err := lean - lean_target
	_lean_i = clampf(_lean_i + err * delta, -0.3, 0.3)
	var accel := -(w0 * w0 * err + 2.0 * w0 * rate + w0 * w0 * 2.0 * _lean_i)
	# its line: a bike's steering geometry (trail) keeps it on the line the bars ask for (yaw rate = v·tan(steer) /
	# wheelbase); without it, it wandered off a straight road and weaved
	var wb := 1.25
	if _wheels.size() >= 2:
		wb = maxf(absf((_wheels[0] as Node3D).position.z - (_wheels[_wheels.size() - 1] as Node3D).position.z), 0.8)
	var yaw_want := speed * tan(steering) / wb
	var grip_turn := _wet_grip() * _surface_grip * 9.81 / maxf(v, 1.0)   # (no more turn than the tyres hold: ~1 g dry)
	yaw_want = clampf(yaw_want, -grip_turn, grip_turn)
	var yaw_acc := (yaw_want - yaw_rate) * 8.0 * smoothstep(0.5, 2.5, v) if on_ground else 0.0
	var st := PhysicsServer3D.body_get_direct_state(get_rid())   # (a nudge of exactly that much roll and yaw rate,
	if st:                                                        #  whatever the body's inertia; setting the velocity
		var inertia := st.inverse_inertia_tensor.inverse()        #  itself froze the body's turning under Jolt)
		apply_torque_impulse(inertia * ((fwd_axis * accel + Vector3.UP * yaw_acc) * delta))


func _process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("car_process", _p0)


func _process_body(delta: float) -> void:
	honked = false
	if not autopilot and Input.is_action_just_pressed("horn"):
		honk()
	if not autopilot and Input.is_action_just_pressed("headlights"):
		set_lights(not lights_on)
	if not autopilot and Input.is_action_just_pressed("toggle_manual"):
		manual = not manual
		if gear == 0:
			gear = 1
	if manual and not autopilot and _shift_timer <= 0.0:
		if Input.is_action_just_pressed("shift_up") and gear < ratios.size():
			gear += 1
			_shift_timer = 0.3
		elif Input.is_action_just_pressed("shift_down") and (gear > 1 or absf(speed) < 1.0):
			gear -= 1
			_shift_timer = 0.3
	_steering_wheel.basis = _steer_base * Basis(Vector3.UP, -steering * 7.5)
	_screen_speed.text = "%d" % roundi(absf(speed) * 3.6)
	_screen_info.text = "km/h\n%s   %s rpm" % [("M" + gear_name()) if manual else ("D" + gear_name() if gear > 0 else "R"),
		str(roundi(rpm / 50.0) * 50)]
	if cockpit:
		_mirror_cam.global_transform = Transform3D(Basis.looking_at(-forward(), Vector3.UP),
			global_transform * Vector3(-0.02, 1.62, 0.2))
	_update_lamps(delta)
	if kit:
		kit.wiping = wiping
		kit.update(delta, night, fuel_frac)
	if _cluster_ui:
		_cluster_ui.fuel = fuel_frac
		_cluster_ui.clock = clock_text
	if _nav and _nav.map_ui == null:
		_nav.map_ui = map_ui
	_fill_engine()
	_fill_horn(delta)
	_fill_road()


## Four-cylinder diesel note: firing pulses at 2 × rpm / 60 Hz, harmonics and a load-dependent clatter.
func _fill_engine() -> void:
	var pb := _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var load := clampf(_thr if gear != 0 else _brk, 0.0, 1.0)
	for i in pb.get_frames_available():
		var smp := _engine_sample(load)
		pb.push_frame(Vector2(smp, smp))


## One sample (22,050 a second) of this vehicle's engine at its rpm now, under `load` (0..1): its kind's firing
## rate and harmonics, the clatter on each firing, a turbo's whistle, a CVT's whine, a rattle (ENGINE_SOUND).
func _engine_sample(load: float) -> float:
	var es: Dictionary = ENGINE_SOUND.get(drive_kind, ENGINE_SOUND["diesel_suv"])
	var f := rpm / 60.0 * float(es["fires"])
	_engine_phase = fmod(_engine_phase + f / 22050.0, 1.0)
	var p := _engine_phase * TAU
	var h: Array = es["harm"]
	var smp := (float(h[0]) * sin(p) + float(h[1]) * sin(2.0 * p + 0.3) + float(h[2]) * sin(3.0 * p + 1.1)
		+ float(h[3]) * sin(4.0 * p + 0.7) + float(es["sub"]) * sin(0.5 * p)) * 0.5
	var pulse := pow(maxf(sin(p), 0.0), float(es["pulse"]))
	var nz: Array = es["noise"]
	smp += (randf() * 2.0 - 1.0) * pulse * lerpf(float(nz[0]), float(nz[1]), load)
	if float(es["turbo"]) > 0.0:                         # a faint whistle climbing with revs, only under load
		_turbo_phase = fmod(_turbo_phase + (900.0 + rpm * 0.6) / 22050.0, 1.0)
		smp += sin(_turbo_phase * TAU) * float(es["turbo"]) * load * clampf((rpm - idle_rpm * 2.0) / (redline * 0.45), 0.0, 1.0)
	if float(es["whine"]) > 0.0:                         # the belt of a CVT, rising with the road speed
		_turbo_phase = fmod(_turbo_phase + (300.0 + absf(speed) * 45.0) / 22050.0, 1.0)
		smp += sin(_turbo_phase * TAU) * float(es["whine"]) * (0.4 + 0.6 * load)
	if float(es["rattle"]) > 0.0:                        # loose panels shaken by each firing
		smp += (randf() * 2.0 - 1.0) * float(es["rattle"]) * pulse * pulse
	return smp * (0.12 + 0.14 * load + 0.05 * rpm / redline) * float(es["level"])


## Road noise: wind (rising with the square of speed), tyre rumble on the surface (rougher off the tarmac),
## tyre squeal when sliding, and a thud when the suspension hits a bump or a speed breaker.
func _fill_road() -> void:
	if _road == null:
		return
	if not _road.playing:
		_road.play()
	var pb := _road.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var v := absf(speed)
	var wind_amp := clampf(v * v / 1600.0, 0.0, 0.6)
	var rough := 1.0 if surface in ["asphalt", "concrete"] else (1.6 if surface == "gravel" else 2.2)
	var rumble_amp := clampf(v / 30.0, 0.0, 0.5) * rough
	var sq := slip * clampf(v / 6.0, 0.0, 1.0)
	for i in pb.get_frames_available():
		var n := randf() * 2.0 - 1.0
		_road_lp[0] += (n - _road_lp[0]) * 0.08                      # wind: soft hiss
		_road_lp[1] += (n - _road_lp[1]) * 0.015                     # rumble: low roar
		_road_lp[2] += (n - _road_lp[2]) * 0.35
		_squeal_phase = fmod(_squeal_phase + (780.0 + 140.0 * _road_lp[2]) / 22050.0, 1.0)
		var smp: float = _road_lp[0] * wind_amp * 0.9 + _road_lp[1] * rumble_amp * 2.2
		smp += sin(_squeal_phase * TAU) * sq * 0.18 * (0.7 + 0.3 * _road_lp[2])
		if _thud > 0.0:
			smp += sin(_thud * 140.0) * _thud * 0.5
			_thud = maxf(0.0, _thud - 1.0 / 22050.0 * 9.0)
		if _crash > 0.0:                                  # a crash: a thump, a crunch, metal ringing
			_crash_phase += 1.0 / 22050.0
			smp += (sin(_crash_phase * TAU * 55.0) * 0.6 + n * 0.8 + sin(_crash_phase * TAU * 870.0) * 0.25 * _crash) * _crash * 0.9
			_crash = maxf(0.0, _crash - 1.0 / 22050.0 * 2.2)
			if _crash <= 0.0:
				_crash_phase = 0.0
		pb.push_frame(Vector2(smp, smp))


func _fill_horn(delta: float) -> void:
	var pb := _horn.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	for i in pb.get_frames_available():
		var smp := 0.0
		if _horn_time > 0.0:
			_horn_phase += 1.0 / 22050.0
			smp = (signf(sin(_horn_phase * TAU * 415.0)) + signf(sin(_horn_phase * TAU * 523.0))) * 0.12
		pb.push_frame(Vector2(smp, smp))
	_horn_time -= delta
