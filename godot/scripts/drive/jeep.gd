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

const PAINT := Color(0.035, 0.12, 0.36)      # electric blue
const BLACK := Color(0.015, 0.015, 0.017)
const CHROME := Color(0.55, 0.56, 0.58)
const CLADDING := Color(0.03, 0.03, 0.032)

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
		_rider = RiderPose.make(randi() % 7, 0.6 if kind == "bike" else 0.5)
		_rider.name = "Rider"
		_rider.position = RiderPose.seat_offset(kind)
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
		var w := _wheel(Vector3(xf.origin.x, xf.origin.y + sp["rest"], xf.origin.z), cw[2], sp)
		w.add_child(cw[0])


func _wheel(pos: Vector3, front: bool, sp: Dictionary) -> VehicleWheel3D:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.use_as_traction = true
	w.use_as_steering = front
	w.wheel_radius = sp["radius"]
	w.wheel_rest_length = sp.get("rest", 0.2)
	w.suspension_travel = sp.get("travel", 0.2)
	w.suspension_stiffness = float(sp.get("stiff", 36.0)) * (1.0 + float(sp["mass"]) / 6000.0)
	w.suspension_max_force = float(sp["mass"]) * 18.0
	w.damping_compression = 3.0
	w.damping_relaxation = 3.6
	w.wheel_friction_slip = 4.6
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
	for spec in [[half_t, ax, true], [-half_t, ax, true], [half_t, -ax, false], [-half_t, -ax, false]]:
		var t: float = spec[0]
		if sp.get("rider", false):
			t = signf(t) * 0.3                    # two-wheelers: a narrow stance that won't tip
		_wheel(Vector3(t, float(sp["radius"]) + 0.18, spec[1]), spec[2], sp)
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
	_weather_grip = mult
	_apply_grip()


## Off the road the tyres find less grip and much more rolling resistance: grass and dirt
## slow you down and slide, so the road is where you want to be (no invisible walls).
func set_surface(kind: String) -> void:
	if kind == surface:
		return
	surface = kind
	match kind:
		"asphalt":
			_surface_grip = 1.0
			_surface_drag = 0.0
		"shoulder":
			_surface_grip = 0.85
			_surface_drag = 160.0
		_:
			_surface_grip = 0.62
			_surface_drag = 420.0
	_apply_grip()


func _apply_grip() -> void:
	for w in _wheels:
		(w as VehicleWheel3D).wheel_friction_slip = 4.6 * _weather_grip * _surface_grip


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
		s.position = Vector3(signf(sx) * lp.x, lp.y, lp.z)
		s.rotation = Vector3(deg_to_rad(-3.5), PI, 0.0)
		s.light_color = Color(0.95, 0.97, 1.0)                 # LED projectors
		s.light_energy = 6.0
		s.spot_range = 70.0
		s.spot_angle = 24.0
		s.spot_attenuation = 0.8
		s.shadow_enabled = false
		s.visible = false
		add_child(s)
		_headlights.append(s)


func _build_audio() -> void:
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
	for s in _headlights:
		s.visible = on
	_lamp_mat.emission_energy_multiplier = 5.0 if on else (0.6 if is_coupe else 2.5)


func honk() -> void:
	_horn_time = 0.45
	honked = true


## 2.2 L diesel: 450 N·m across 1,600–2,800 rpm.
func _torque(r: float) -> float:
	if r < 1600.0:
		return lerpf(220.0, 450.0, clampf((r - IDLE) / 820.0, 0.0, 1.0))
	if r < 2800.0:
		return 450.0
	return lerpf(450.0, 300.0, clampf((r - 2800.0) / 1700.0, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_physics_process_body(delta)
	Prof.add("car_physics", _p0)


func _physics_process_body(delta: float) -> void:
	speed = linear_velocity.dot(forward())
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
		if _brk > 0.05 and speed < 0.4 and gear != 0:
			gear = 0
		elif _thr > 0.05 and gear == 0 and speed > -0.4:
			gear = 1
	var ratio: float = REVERSE if gear == 0 else RATIOS[gear - 1]
	var wheel_rpm := absf(speed) / (TAU * wheel_r) * 60.0
	var pedal := _brk if (gear == 0 and not manual) else _thr
	rpm = maxf(wheel_rpm * ratio * FINAL, lerpf(IDLE, 1600.0, pedal) if absf(speed) < 2.5 else IDLE)
	rpm = minf(rpm, REDLINE + 150.0)
	if not manual and gear >= 1 and _shift_timer <= 0.0:
		if rpm > lerpf(2000.0, 3600.0, _thr) and gear < RATIOS.size():
			gear += 1
			_shift_timer = 0.3
		elif rpm < 1150.0 and gear > 1:
			gear -= 1
			_shift_timer = 0.3
	if _shift_timer > 0.0 or out_of_fuel:
		pedal = 0.0
	var dir := -1.0 if gear == 0 else 1.0
	var drive_force := 0.0
	if rpm < REDLINE and absf(speed) < top_speed:
		drive_force = _torque(rpm) * torque_mul * ratio * FINAL / wheel_r * 0.88 * pedal * dir
	var br := 0.0
	if gear != 0 and _brk > 0.05 and not (manual and gear == 0):
		br = _brk * BRAKE
	if gear == 0 and not manual and _thr > 0.05:
		br = _thr * BRAKE
	if pedal < 0.05:
		br = maxf(br, 0.5 + rpm / REDLINE * 2.4)
	if in_handbrake:
		br = BRAKE * 1.2
	engine_force = drive_force / 4.0 * FWD
	brake = br
	var v := linear_velocity.length()
	if v > 0.3:
		apply_central_force(-linear_velocity / v * (280.0 + 0.95 * v * v + _surface_drag * minf(v, 12.0)))
	# speed-sensitive steering: full lock at a crawl, a few degrees at highway speed
	# full lock only at a crawl (hairpins, parking); it falls away quickly once you're moving
	var s := smoothstep(0.0, 18.0, absf(speed))
	var max_s := lerpf(MAX_STEER, HIGH_SPEED_STEER, sqrt(s)) * (lerpf(1.0, steer_sens, s) if not autopilot else 1.0)
	steering = move_toward(steering, _steer_in * max_s, delta * (1.0 if not autopilot else 2.5))


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
		if Input.is_action_just_pressed("shift_up") and gear < RATIOS.size():
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


## Four-cylinder diesel note: firing pulses at 2 × rpm / 60 Hz, harmonics and a load-dependent clatter.
func _fill_engine() -> void:
	var pb := _engine.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var f := rpm / 60.0 * 2.0
	var load := clampf(_thr if gear != 0 else _brk, 0.0, 1.0)
	var amp := 0.12 + 0.14 * load + 0.05 * rpm / REDLINE
	var inc := f / 22050.0
	for i in pb.get_frames_available():
		_engine_phase = fmod(_engine_phase + inc, 1.0)
		var p := _engine_phase * TAU
		var pulse := pow(maxf(sin(p), 0.0), 6.0)
		var smp := (0.6 * sin(p) + 0.35 * sin(2.0 * p + 0.3) + 0.2 * sin(3.0 * p + 1.1) + 0.12 * sin(0.5 * p)) * 0.5
		smp += (randf() * 2.0 - 1.0) * pulse * (0.2 + 0.4 * load)
		smp *= amp
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
