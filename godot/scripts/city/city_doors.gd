extends Node3D
## Every building in the city can be walked into. On foot, step up to any wall of a building and the door is
## there: "E: go in". You come into a room that suits the building, loaded well below the street while you're
## inside (the rooms of tools/building_interiors.py, tools/story_rooms.py and tools/city_rooms.py):
##   houses, bungalows, cottages            → one of the houses (a family's hall, an old courtyard house, a modern flat)
##   apartment blocks                       → the modern flat
##   shops (a shop on the ground floor)     → a kirana, a tea stall or a restaurant (the same one every time)
##   commercial blocks and tall buildings  → an office
##   hotels                                 → a hotel lobby
##   landmarks                              → their own room (landmarks.json "room", door at "door")
##   Karthik's own house in Ganapathy       → his home (slice.json places.home): his cot, Amma's kitchen
## Inside, E at a room's own spot does what there is to do there (life.gd: eat, sleep, a match, a film...). Public
## rooms have people in them (crowd.gd: on the benches, in the queues, in the pews and the stand).
## E by the doorway inside (or walking out through it) brings you back out where you went in.

const ROOMS := "res://assets/interiors/room_%s.glb"
const Crowd := preload("res://scripts/city/crowd.gd")
const STAFF := "res://assets/people/person_%s.glb"
const DEPTH := 300.0                 # rooms sit this far below the street
const REACH := 1.6                   # how near a wall you must be for its door
const SHOPS := ["kirana", "kirana", "tea", "restaurant", "kirana", "tea", "restaurant", "bank"]
const HOMES := ["house_mid", "house_old", "house_flat", "house_mid", "house_flat"]   # (Karthik's own "home" is the story's)
const KIT_ROOM := {"apartment": "house_flat", "bungalow": "house", "city_house": "house", "tn_house": "house", "hill_cottage": "house",
	"commercial": "office", "shop_house": "shop", "hotel": "hotel", "mill_shed": "office"}
const NAMES := {"home": "Karthik's house", "house_mid": "the house", "house_old": "the house", "house_flat": "the flat",
	"station": "the station", "bus": "the bus stand", "airport": "the airport", "mall_avinashi": "the mall",
	"mall_sathy": "the mall", "church": "the church", "stadium": "the stadium", "kirana": "the kirana store", "tea": "the tea stall", "restaurant": "the restaurant",
	"bank": "the bank", "office": "the offices", "hotel": "the hotel", "temple": "the temple", "hospital": "the hospital",
	"fine_dining": "the restaurant", "mess": "the mess", "police": "the police station", "coopbank": "the bank",
	"fuel": "the store"}

var city                             # city_test.gd: walker, streamer, story, indoors
var inside := {}                     # the door you came in by, while you're inside
var _room: Node3D
var _exit := Vector3.ZERO
var _near := {}                      # the door you're standing at, if any
var _t := 0.0
var _e_down := false
var _label: Label
var _home := Vector2(INF, INF)       # where Karthik's house stands (the story's "home" place)


func _ready() -> void:
	var f := FileAccess.open("res://story/slice.json", FileAccess.READ)
	if f:
		var h = (JSON.parse_string(f.get_as_text()) as Dictionary).get("places", {}).get("home", {})
		if h is Dictionary and h.has("x"):
			_home = Vector2(float(h["x"]), float(h["z"]))
	for a in OS.get_cmdline_user_args():                # (testing: --doortest=N walks into N buildings near the start,
		if a == "--walktest":                           # (testing: Karthik walking and running, filmed from the side)
			_walk_test.call_deferred()
		if a.begins_with("--doortest="):                #  --doorat=<landmark> into that landmark; screenshots in --shots)
			_door_test.call_deferred(int(a.get_slice("=", 1)))
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -300
	_label.offset_right = 300
	_label.offset_top = -120
	_label.offset_bottom = -90
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _process(dt: float) -> void:
	var w: Node3D = city.walker if city else null
	var e := Input.is_key_pressed(KEY_E)
	var pressed := e and not _e_down
	_e_down = e
	if w == null:
		_label.text = ""
		if not inside.is_empty():                       # (back in the car somehow: drop the room)
			_drop_room()
		return
	if not inside.is_empty():
		var life = city.life if "life" in city else null
		if life and life.busy:
			_label.text = ""
			return
		var at_door := w.global_position.distance_to(_exit) < 1.8
		var todo: Dictionary = life.offer(inside["room"], _room, w.global_position) if life and not at_door else {}
		_label.text = ("Inside %s · E: go out" % NAMES.get(inside["room"], "the building")) if at_door else \
			("E: %s" % todo["offer"] if not todo.is_empty() else "")
		if at_door and pressed:
			leave(w)
		elif pressed and not todo.is_empty():
			life.go(todo, _room)
		return
	if _story_busy():
		_label.text = ""
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.15
		_near = door_near(w.global_position)
	_label.text = ("E: go into %s" % NAMES.get(_near.get("room", ""), "the building")) if not _near.is_empty() else ""
	if pressed and not _near.is_empty():
		enter(_near, w)


## The story has its own E here (a room of its own, an eatery's door): the doors keep out of its way.
func _story_busy() -> bool:
	var st = city.story if city else null
	if st == null:
		return false
	if st.room != null:
		return true
	return st.has_method("claims_e") and st.claims_e(city.walker.global_position)


## The door of the building wall nearest p, if p is within REACH of it: {pos, out, room, key}.
func door_near(p: Vector3) -> Dictionary:
	var s = city.streamer
	var here := Vector2(p.x, p.z)
	var best := {}
	var bd := REACH
	for lm in s.landmarks:                              # a landmark's own door first
		if lm.has("door") and lm.has("room"):
			var c := cos(float(lm["yaw"]))
			var sn := sin(float(lm["yaw"]))
			var bx: float = lm["door"][0]
			var gz: float = -float(lm["door"][1])
			var dp := Vector2(float(lm["x"]) + bx * c + gz * sn, float(lm["z"]) - bx * sn + gz * c)
			if here.distance_to(dp) < 3.0:
				return {"pos": Vector3(dp.x, p.y, dp.y), "out": Vector3(sn, 0, c), "room": lm["room"], "key": lm["name"]}
	var k := Vector2i(floori(p.x / s.tile), floori(p.z / s.tile))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var node: Node3D = s.loaded.get(k + Vector2i(dx, dz))
			if node == null:
				continue
			for b in node.get_meta("bldinfo", []):
				var centre: Vector2 = b[1]
				if centre.distance_squared_to(here) > 3600.0:
					continue
				var poly: PackedVector2Array = b[0]
				for i in poly.size():
					var a := poly[i]
					var q := Geometry2D.get_closest_point_to_segment(here, a, poly[(i + 1) % poly.size()])
					var d := q.distance_to(here)
					if d < bd:
						var ed := poly[(i + 1) % poly.size()] - a
						var nrm := Vector2(ed.y, -ed.x).normalized()
						if nrm.dot(q - centre) < 0.0:
							nrm = -nrm
						bd = d
						best = {"pos": Vector3(q.x, p.y, q.y), "out": Vector3(nrm.x, 0, nrm.y),
							"room": "home" if centre.distance_to(_home) < 10.0 else _room_for(b, s),
							"key": "%d,%d" % [roundi(centre.x), roundi(centre.y)]}
	return best


## Which room a building opens into (the same every time: picked by where it stands).
func _room_for(b: Array, s) -> String:
	var floors: int = b[2]
	var shop: bool = b[3]
	var variant: int = b[5]
	var h: int = absi(hash(Vector2i(roundi(b[1].x), roundi(b[1].y))))
	var vnames: Array = s.index.get("variants", [])
	if variant >= 0 and variant < vnames.size():
		for pre in KIT_ROOM:
			if str(vnames[variant]).begins_with(pre):
				var r: String = KIT_ROOM[pre]
				if r == "shop":
					return SHOPS[h % SHOPS.size()]
				return HOMES[h % HOMES.size()] if r == "house" else r
	if shop:
		return SHOPS[h % SHOPS.size()]
	if floors >= 5:
		return "office"
	return HOMES[h % HOMES.size()]


func enter(d: Dictionary, walker: Node3D) -> void:
	var path: String = ROOMS % d["room"]
	if not ResourceLoader.exists(path):
		return
	inside = d
	_room = (load(path) as PackedScene).instantiate() as Node3D
	_room.name = "Room"
	add_child(_room)
	_room.global_position = d["pos"] + Vector3(0, -DEPTH, 0)
	_room.rotation.y = atan2(d["out"].x, d["out"].z)
	var body := StaticBody3D.new()                      # walls and furniture are solid
	_room.add_child(body)
	for mi in _room.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		cs.transform = _room.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		body.add_child(cs)
	var people := Crowd.fill(_room, body, d["key"])        # the station's travellers, the mall's shoppers...
	var lights := _room.find_children("Light_*", "", true, false)
	for e in lights:                                    # the room's own lights (story rooms), else a ceiling light
		var l := OmniLight3D.new()
		l.omni_range = 6.5
		l.light_energy = 1.2
		(e as Node3D).add_child(l)
	if lights.is_empty():
		var light := OmniLight3D.new()
		light.omni_range = 12.0
		light.light_energy = 1.1
		light.light_color = Color(1.0, 0.97, 0.9)
		light.position = Vector3(0, 2.9, 0)
		_room.add_child(light)
	var entry := _room.find_child("Entry", true, false) as Node3D
	var ex := _room.find_child("Exit", true, false) as Node3D
	if entry == null:                                   # (a story room: its door mark is both)
		entry = _room.find_child("Mark_door", true, false) as Node3D
		ex = entry
	_exit = ex.global_position if ex else _room.global_position
	var staff := _room.find_child("Staff", true, false) as Node3D
	if staff:
		var who: String = ["man_shirt", "woman_kurta", "man_lungi", "woman_saree"][absi(hash(d["key"])) % 4]
		if ResourceLoader.exists(STAFF % who):
			var npc := (load(STAFF % who) as PackedScene).instantiate() as Node3D
			_room.add_child(npc)
			npc.global_position = staff.global_position
			var to_door := _exit - staff.global_position
			npc.rotation.y = atan2(to_door.x, to_door.z)
			var aps := npc.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				var ap := aps[0] as AnimationPlayer
				if ap.has_animation("Idle"):
					ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
					ap.play("Idle")
	var at: Vector3 = entry.global_position if entry else _room.global_position
	var into := (_room.global_position - at)
	walker.global_position = at + Vector3(0, 0.15, 0) + Vector3(into.x, 0, into.z).normalized() * 0.8
	walker.velocity = Vector3.ZERO
	walker.rotation.y = atan2(-into.x, -into.z)
	city.indoors = true
	print("DOOR in %s (%s)%s" % [d["room"], d["key"], (" · %d people" % people) if people > 0 else ""])


func leave(walker: Node3D) -> void:
	if inside.is_empty():
		return
	var d := inside
	_drop_room()
	walker.global_position = d["pos"] + d["out"] * 1.4 + Vector3(0, 0.4, 0)
	walker.velocity = Vector3.ZERO
	walker.rotation.y = atan2(-d["out"].x, -d["out"].z)
	print("DOOR out of %s" % d["room"])


func _drop_room() -> void:
	inside = {}
	if _room:
		_room.queue_free()
		_room = null
	city.indoors = false


## (testing) Out of the car, then up to the wall of building after building (or the landmark of --doorat), in through
## its door, a look round, and out again: a screenshot outside and inside each time. --doordo: the outing there too
## (life.gd: the match, the film...), with screenshots of the offer, while it lasts and after.
func _door_test(n: int) -> void:
	var tree := get_tree()
	if city.fines:
		city.fines.persist = false                      # (a test doesn't touch the saved game)
	await tree.create_timer(12.0).timeout
	city.toggle_on_foot()
	await tree.create_timer(2.0).timeout
	var shots: String = city.shots_dir
	var at := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--doorat="):
			at = a.get_slice("=", 1)
	var seen := {}
	var life = city.life if "life" in city else null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--doorlife=") and life:         # energy,tiredness,stress to start from
			var v := a.get_slice("=", 1).split(",")
			life.energy = float(v[0])
			life.tiredness = float(v[1])
			life.stress = float(v[2])
	for k in n:
		var w: Node3D = city.walker
		var d := {}
		if at != "":
			for lm in city.streamer.landmarks:
				if lm["name"] == at and lm.has("door"):
					var c := cos(float(lm["yaw"]))
					var sn := sin(float(lm["yaw"]))
					var gz: float = -float(lm["door"][1])
					var p := Vector3(float(lm["x"]) + lm["door"][0] * c + gz * sn, float(lm["y"]) + 1.0,
						float(lm["z"]) - lm["door"][0] * sn + gz * c)
					w.global_position = p + Vector3(sn, 0, c) * 2.0
					await tree.create_timer(8.0).timeout
					d = door_near(w.global_position)
		elif "--doorhome" in OS.get_cmdline_user_args():  # Karthik's house: set down in its street, in at its wall
			w.global_position = Vector3(_home.x, w.global_position.y + 40.0, _home.y)
			w.velocity = Vector3.ZERO
			await tree.create_timer(1.0).timeout
			while not (w as CharacterBody3D).is_on_floor():
				await tree.create_timer(0.5).timeout
			await tree.create_timer(3.0).timeout
			d = _a_door(w.global_position, seen)
			if not d.is_empty():
				w.global_position = d["pos"] + d["out"] * 0.9 + Vector3(0, 0.6, 0)
				await tree.create_timer(1.5).timeout
				d = door_near(w.global_position)
			print("DOORTEST home: %.0f m from the house's place" % Vector2(w.global_position.x, w.global_position.z).distance_to(_home))
		else:
			d = _a_door(w.global_position, seen)
			if not d.is_empty():
				w.global_position = d["pos"] + d["out"] * 0.9 + Vector3(0, 0.6, 0)
				w.rotation.y = atan2(d["out"].x, d["out"].z)
				await tree.create_timer(1.5).timeout
				d = door_near(w.global_position)
		if d.is_empty():
			print("DOORTEST %d no door" % k)
			continue
		for a2 in OS.get_cmdline_user_args():          # --doorroom=a,b,c: building k opens into room k of these
			if a2.begins_with("--doorroom="):
				var rs := a2.get_slice("=", 1).split(",")
				d["room"] = rs[k % rs.size()]
		seen[d["key"]] = true
		if shots != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/door_%02d_out.jpg" % [shots, k], 0.85)
		enter(d, w)
		await tree.create_timer(2.5).timeout
		if shots != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/door_%02d_in_%s.jpg" % [shots, k, d["room"]], 0.85)
		if "--doordo" in OS.get_cmdline_user_args() and life and life.DOINGS.has(d["room"]):   # (and what's done there)
			for j in life.DOINGS[d["room"]].size():
				var m := _room.find_child(life.DOINGS[d["room"]][j]["mark"], true, false) as Node3D
				if m == null:
					print("DOORTEST no mark %s" % life.DOINGS[d["room"]][j]["mark"])
					continue
				w.global_position = m.global_position + Vector3(0, 0.1, 0)
				await tree.create_timer(1.0).timeout
				var todo: Dictionary = life.offer(d["room"], _room, w.global_position)
				print("DOORTEST offer %s: %s" % [d["room"], todo.get("offer", "none")])
				if todo.is_empty():
					continue
				_shot(shots, "door_%02d_%d_offer" % [k, j])
				await RenderingServer.frame_post_draw
				life.go(todo, _room)
				await tree.create_timer(3.5).timeout
				await _shot(shots, "door_%02d_%d_during" % [k, j])
				await tree.create_timer(5.0).timeout
				await _shot(shots, "door_%02d_%d_after" % [k, j])
				await tree.create_timer(4.0).timeout
		leave(w)
		await tree.create_timer(1.0).timeout
		print("DOORTEST %d %s %s ok" % [k, d["key"], d["room"]])
	tree.quit()


## (testing) The wall of the nearest building not yet visited, as a door.
func _a_door(p: Vector3, seen: Dictionary) -> Dictionary:
	var s = city.streamer
	var here := Vector2(p.x, p.z)
	var best := {}
	var bd := 120.0
	for node in s.loaded.values():
		for b in (node as Node3D).get_meta("bldinfo", []):
			var centre: Vector2 = b[1]
			var key := "%d,%d" % [roundi(centre.x), roundi(centre.y)]
			if seen.has(key) or centre.distance_to(here) > bd:
				continue
			var poly: PackedVector2Array = b[0]
			var q := Geometry2D.get_closest_point_to_segment(here, poly[0], poly[1])
			var nrm := Vector2(poly[1].y - poly[0].y, -(poly[1].x - poly[0].x)).normalized()
			if nrm.dot(q - centre) < 0.0:
				nrm = -nrm
			bd = centre.distance_to(here)
			best = {"pos": Vector3(q.x, p.y, q.y), "out": Vector3(nrm.x, 0, nrm.y), "room": _room_for(b, s), "key": key}
	return best


func _shot(dir: String, name: String) -> void:
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [dir, name], 0.85)


## (testing) --walktest --shots=DIR: out of the car, Karthik runs along the road, stops, walks, turns, filmed from the
## side by a camera that keeps pace: frames in DIR (walk_NNN.jpg) to judge the gait by.
func _walk_test() -> void:
	var tree := get_tree()
	if city.fines:
		city.fines.persist = false
	await tree.create_timer(12.0).timeout
	city.toggle_on_foot()
	await tree.create_timer(2.0).timeout
	var w: Node3D = city.walker
	if "--walktired" in OS.get_cmdline_user_args() and "life" in city and city.life:   # (and he drops off mid-walk)
		city.life.tiredness = 99.8
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var plan := [["move_forward", "run", 3.0], ["", "", 1.2], ["move_forward", "", 3.0], ["move_forward", "", 1.0, 0.8],
		["", "", 1.5]]                                     # run along the road, stop, walk, turn, stop
	var n := 0
	for p in plan:
		var t := 0.0
		if p[0] != "":
			Input.action_press(p[0])
		if p[1] != "":
			Input.action_press(p[1])
		while t < p[2]:
			if p.size() > 3:                               # turning while walking
				w.rotation.y += p[3] * get_process_delta_time()
			var side: Vector3 = w.global_basis.x
			cam.global_position = w.global_position + side * 3.2 + Vector3(0, 1.0, 0)
			cam.look_at(w.global_position + Vector3(0, 0.9, 0))
			cam.make_current()
			await RenderingServer.frame_post_draw
			if city.shots_dir != "" and n % 3 == 0:
				get_viewport().get_texture().get_image().save_jpg("%s/walk_%03d.jpg" % [city.shots_dir, n / 3], 0.8)
			n += 1
			t += get_process_delta_time()
		for act in [p[0], p[1]]:
			if act != "":
				Input.action_release(act)
	while "life" in city and city.life and city.life.busy:   # (asleep on his feet: until he's up again)
		await tree.create_timer(1.0).timeout
	print("WALKTEST frames %d" % (n / 3))
	tree.quit()
