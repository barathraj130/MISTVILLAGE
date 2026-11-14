extends Node
## People inside a building notice what Karthik does (the stealth brief, fitted to the game: no meters, it shows in
## them). One per room with people in it (city_doors.gd: offices, the hotel, banks, hospitals, the Collectorate, the
## police station). Who's there: the room's crowd (crowd.gd: seated ones are its staff in an office, guests in a hotel,
## visitors elsewhere), its counter person (the "Staff" mark: the receptionist), and in buildings with one, a guard
## by the door.
##   seeing      each person in turn, a few times a second: within 12 m, in a 110° view, nothing solid between (glass
##               doesn't hide him: the room's glass is marked when its collision is made)
##   what he does   walking about is nothing; a jog, a sprint, creeping low, going behind the counter or round an
##               employee's desk, lingering there, staring at someone, and above all opening drawers and searching
##               (interactable.gd tells it) each weigh differently; a person's role changes how much (a guard minds the
##               counter, a worker minds his own desk)
##   suspicion   each person their own, 0..100, fading when he's ordinary again or out of their sight:
##                 20 they glance (the head turns), 45 they watch him, 70 one comes over and asks, 90 the guard asks
##                 him to leave: walked out, and it's remembered
##   politeness  at the counter (E): say who he's here to see, ask the way, or just wait: a visitor then, and the
##               desks are his to walk past (not to search)
##   memory      each building remembers him (user://social.json): seen before ("You were here yesterday as well"),
##               polite or not, asked to leave; twice asked to leave the same day, the guard won't let him in again
##               that day. Never a game over.
##   --socialtest   testing: in an office, walks behind a worker's desk and stays, then searches; pictures and the
##                  people's states (user://social_*.jpg)

const HeadLook := preload("res://scripts/story/head_look.gd")
const Crowd := preload("res://scripts/city/crowd.gd")
const MEMORY := "user://social.json"
## Per room: what its seated people are, whether a guard keeps the door.
const ROOMS := {
	"office": {"sit": "worker", "guard": true, "place": {"en": "the offices", "ta": "ஆஃபீஸ்"}},
	"hotel": {"sit": "guest", "guard": true, "place": {"en": "the hotel", "ta": "ஹோட்டல்"}},
	"bank": {"sit": "visitor", "guard": true, "place": {"en": "the bank", "ta": "வங்கி"}},
	"coopbank": {"sit": "visitor", "guard": true, "place": {"en": "the bank", "ta": "வங்கி"}},
	"hospital_pvt": {"sit": "visitor", "guard": true, "place": {"en": "the hospital", "ta": "ஆஸ்பத்திரி"}},
	"hospital_gov": {"sit": "visitor", "guard": false, "place": {"en": "the hospital", "ta": "ஆஸ்பத்திரி"}},
	"collectorate": {"sit": "visitor", "guard": true, "place": {"en": "the Collectorate", "ta": "கலெக்டரேட்"}},
	"police": {"sit": "visitor", "guard": false, "place": {"en": "the station", "ta": "ஸ்டேஷன்"}},
}
const RANGE := 12.0
const FOV := 110.0

signal suspicion_changed(person: Node3D, value: float)
signal questioned(person: Node3D)
signal sent_out(key: String)

var city
var room: Node3D
var kind := ""
var key := ""
var people: Array = []                # {node, role, sus, look, home, state, said}
var visitor := false                  # said at the counter why he's here
var _i := 0
var _t := 0.0
var _act := ""                        # what he's doing that someone could see ("search", for a moment after)
var _act_t := 0.0
var _act_at := Vector3.ZERO
var _linger := 0.0
var _asking := {}                     # the one who came over, while he answers
var _opts: Array = []
var _box: Label
var _mem := {}
var _leaving := false
var _asked := 0                       # times someone has come over this visit


static func attach(rm: Node3D, room_kind: String, building: String, city_ref) -> Node:
	if not ROOMS.has(room_kind):
		return null
	var s: Node = load("res://scripts/city/social.gd").new()
	s.name = "Social"
	s.city = city_ref
	s.room = rm
	s.kind = room_kind
	s.key = building
	rm.add_child(s)
	s._setup()
	return s


func _lang() -> String:
	return str(city.story.lang) if city and city.story and "lang" in city.story else "en"


func _tx(d) -> String:
	return str(d.get(_lang(), d.get("en", ""))) if d is Dictionary else str(d)


func _setup() -> void:
	_load()
	var m: Dictionary = _mem.get(key, {})
	var cfg: Dictionary = ROOMS[kind]
	for n in room.find_children("*", "Node3D", true, false):
		if not n.has_meta("crowd_pose"):
			continue
		var pose := str(n.get_meta("crowd_pose"))
		var role := str(cfg["sit"]) if pose == "sit" else "visitor"
		_add(n, role)
	var staff := room.find_child("StaffPerson", true, false) as Node3D
	if staff:
		_add(staff, "receptionist")
	if cfg["guard"]:
		_guard()
	_box = Label.new()
	_box.add_theme_font_size_override("font_size", 19)
	_box.add_theme_color_override("font_color", Color(1, 0.96, 0.85))
	_box.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_box.add_theme_constant_override("outline_size", 6)
	_box.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	layer.add_child(_box)
	m["visits"] = int(m.get("visits", 0)) + 1
	m["last_day"] = _day()
	_mem[key] = m
	_save()
	print("SOCIAL %s (%s): %d people, visit %d" % [kind, key, people.size(), int(m["visits"])])
	if "--socialtest" in OS.get_cmdline_user_args():
		_run_test.call_deferred()


func _add(n: Node3D, role: String) -> void:
	var look: Node = null
	var sks := n.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		look = HeadLook.new()
		sks[0].add_child(look)
	people.append({"node": n, "role": role, "sus": 0.0, "look": look, "home": n.global_transform, "state": 0, "said": false,
		"seen": false})


## A guard by the door, inside: one of the crowd's men, in a guard's khaki.
func _guard() -> void:
	var entry := room.find_child("Entry", true, false) as Node3D
	if entry == null:
		entry = room.find_child("Mark_door", true, false) as Node3D
	if entry == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + "guard")
	var g := (load(Crowd.CROWD % "m3") as PackedScene).instantiate() as Node3D
	room.add_child(g)
	var into := (room.global_position - entry.global_position)
	into.y = 0.0
	var side := into.normalized().cross(Vector3.UP)
	g.global_position = entry.global_position + into.normalized() * 1.6 + side * 1.4
	var face := -side
	g.rotation.y = atan2(face.x, face.z)
	if city.story and city.story.has_method("_tint"):
		city.story._tint(g, "top", Color(0.62, 0.55, 0.36))       # khaki
		city.story._tint(g, "bottom", Color(0.48, 0.42, 0.28))
	var aps := g.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var ap := aps[0] as AnimationPlayer
		if ap.has_animation("Idle"):
			ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
			ap.play("Idle")
	g.name = "Guard"
	_add(g, "guard")


func _day() -> int:
	return int(city.fines.sim.day) if city and city.fines and "sim" in city.fines else 0


## Told by interactable.gd: he's opened something that isn't his (a drawer, an almirah) or searched a desk.
func act(what: String, at: Vector3) -> void:
	_act = what
	_act_t = 3.0
	_act_at = at


## Not let in today? (twice asked to leave here today)
static func barred(building: String, day: int) -> bool:
	if not FileAccess.file_exists(MEMORY):
		return false
	var all = JSON.parse_string(FileAccess.get_file_as_string(MEMORY))
	if not all is Dictionary:
		return false
	var m: Dictionary = all.get(building, {})
	return int(m.get("out_day", -1)) == day and int(m.get("out_today", 0)) >= 2


func _process(dt: float) -> void:
	var w: Node3D = city.walker if city else null
	if w == null or _leaving:
		return
	_act_t = maxf(_act_t - dt, 0.0)
	if not _asking.is_empty():
		_answering()
		return
	var how := _how(w, dt)
	_t += dt
	var n := people.size()
	if n == 0:
		return
	# each person in turn: four of them a frame at most, each about four times a second
	var per := maxi(1, ceili(float(n) * dt * 4.0))
	for k in per:
		_i = (_i + 1) % n
		_see(people[_i], w, how, minf(float(n) / 4.0, 1.0) * 0.25 + dt)
	for p in people:
		_react(p, w, dt)


## What he's doing now, as anyone watching would read it: {"what": weight per second, "where": the private place's
## owner if he's at someone's desk}.
func _how(w: Node3D, dt: float) -> Dictionary:
	var g = w.get("gait")
	var st: String = str(g.state) if g else "walk"
	var sp := Vector2(w.velocity.x, w.velocity.z).length()
	var r := {"rate": 0.0, "near": null, "why": ""}
	if g and g.crouched:
		r = {"rate": 6.0, "near": null, "why": "creeping"}
	elif st == "sprint" or sp > 4.5:
		r = {"rate": 9.0, "near": null, "why": "running"}
	elif st == "jog" or sp > 2.6:
		r = {"rate": 4.0, "near": null, "why": "running"}
	var desk := _desk_near(w.global_position)              # behind the counter, round someone's desk
	if not desk.is_empty():
		_linger += dt
		var base := 0.6 if visitor else 1.4
		if desk["role"] in ["receptionist"]:
			base = 3.5                                   # (behind the counter: never his place)
		r["rate"] = float(r["rate"]) + base + minf(_linger / 20.0, 1.0) * 2.0
		r["near"] = desk
		r["why"] = "desk"
	else:
		_linger = maxf(_linger - dt * 2.0, 0.0)
	if _act_t > 0.0:
		r["rate"] = float(r["rate"]) + 22.0
		r["why"] = "search"
	return r


## Someone's own place: within 1.3 m of a seated worker (on their side of the desk), or behind the counter.
func _desk_near(p: Vector3) -> Dictionary:
	for q in people:
		var n: Node3D = q["node"]
		if not is_instance_valid(n):
			continue
		var role := str(q["role"])
		if role == "worker" and Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 1.3:
			return q
		if role == "receptionist":
			var fwd: Vector3 = (q["home"] as Transform3D).basis.z      # (the counter is in front of them: their back is
			var rel := p - n.global_position                          #  the staff side)
			rel.y = 0.0
			if rel.length() < 2.5 and rel.dot(fwd) < -0.3:
				return q
	return {}


## Can this person see him, and what do they make of it.
func _see(p: Dictionary, w: Node3D, how: Dictionary, dt: float) -> void:
	var n: Node3D = p["node"]
	if not is_instance_valid(n):
		return
	var eye := n.global_position + Vector3.UP * (1.15 if str(p["role"]) in ["worker", "guest", "visitor"] and n.get_meta("crowd_pose", "") == "sit" else 1.6)
	var him := w.global_position + Vector3.UP * 1.2
	var to := him - eye
	var seen := false
	if to.length() < RANGE:
		var fwd: Vector3 = n.global_basis.z
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		var ang := rad_to_deg(acos(clampf(Vector3(fwd.x, 0.0, fwd.z).normalized().dot(flat), -1.0, 1.0)))
		if ang < FOV * 0.5 or int(p["state"]) >= 2:    # (once watching, they keep him in view)
			seen = _clear(eye, him, w)
	p["seen"] = seen
	var role := str(p["role"])
	var rate := float(how["rate"])
	if how["why"] == "desk" and how["near"] != null:
		var mine: bool = how["near"]["node"] == n
		rate *= 1.6 if mine else (1.0 if role in ["worker", "guard", "receptionist"] else 0.3)
	if role == "guest" or role == "visitor":            # (other visitors mind less: not their place)
		rate *= 0.35
	if role == "guard":
		rate *= 1.3
	var was := float(p["sus"])
	if seen and rate > 0.0:                              # (lingering at a desk: asked in ~15 s; searching: in a second or two)
		p["sus"] = minf(was + rate * dt * 1.2, 100.0)
	else:
		p["sus"] = maxf(was - dt * 4.0 * (6.0 if not seen else 3.0), 0.0)
	if absf(float(p["sus"]) - was) > 0.5:
		suspicion_changed.emit(n, float(p["sus"]))


## Is anything solid between? (glass isn't: it's marked "see_through" when the room's collision is made)
func _clear(a: Vector3, b: Vector3, w: Node3D) -> bool:
	var space := room.get_world_3d().direct_space_state
	var from := a
	for k in 4:
		var q := PhysicsRayQueryParameters3D.create(from, b)
		q.exclude = [(w as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var co = hit["collider"]
		var see := false
		if co is CollisionObject3D:
			var oid := (co as CollisionObject3D).shape_find_owner(int(hit["shape"]))
			var sn = (co as CollisionObject3D).shape_owner_get_owner(oid) if oid >= 0 else null
			see = sn is Node and (sn as Node).has_meta("see_through")
			if sn is Node and (sn as Node).has_meta("person"):   # (another person in the way: they see past)
				see = true
		if not see:
			return false
		from = (hit["position"] as Vector3) + (b - from).normalized() * 0.05
	return true


## What they do about it: glance, watch, come and ask, send him out.
func _react(p: Dictionary, w: Node3D, dt: float) -> void:
	var n: Node3D = p["node"]
	if not is_instance_valid(n):
		return
	var s := float(p["sus"])
	var state := 0 if s < 20.0 else (1 if s < 45.0 else (2 if s < 70.0 else (3 if s < 90.0 else 4)))
	var was := int(p["state"])
	p["state"] = state
	var look: Node = p["look"]
	if look:
		look.target = w.global_position + Vector3.UP * 1.55
		look.weight = 0.0 if state == 0 else (0.6 if state == 1 else 1.0)
	if state >= 2 and n.get_meta("crowd_pose", "") != "sit":    # (standing: they turn to watch him)
		var to := w.global_position - n.global_position
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), 1.0 - exp(-dt * 2.5))
	if state >= 3 and was < 3 and _asking.is_empty():
		_asked += 1                                      # (asked twice this visit already: the third time it's the guard)
		var out := state >= 4 or _asked >= 3
		var who := p if str(p["role"]) != "visitor" and str(p["role"]) != "guest" else _staff()
		if out:
			for q in people:
				if str(q["role"]) == "guard":
					who = q
		if not who.is_empty():
			_come_ask(who, w, out)
	if state == 0 and was > 0:
		p["said"] = false


func _staff() -> Dictionary:
	for q in people:
		if str(q["role"]) in ["guard", "receptionist", "worker"]:
			return q
	return {}


# ---- asking ----
const ASK := {
	"desk": {"en": "Sir, that's our staff's place. Can I help you with something?", "ta": "சார், அது எங்க ஸ்டாஃப் இடம். ஏதாவது உதவி வேணுமா?"},
	"search": {"en": "Sir! What are you doing there? That's not yours.", "ta": "சார்! அங்க என்ன பண்றீங்க? அது உங்களுது இல்ல."},
	"running": {"en": "Sir, slowly please. What's the hurry?", "ta": "சார், மெதுவா. என்ன அவசரம்?"},
	"creeping": {"en": "Sir... are you all right? What are you looking for?", "ta": "சார்... நல்லா இருக்கீங்களா? என்ன தேடுறீங்க?"},
	"": {"en": "Sir, can I help you?", "ta": "சார், ஏதாவது உதவி வேணுமா?"},
}
const OUT := {"en": "Sir, please come with me. You'll have to leave now.", "ta": "சார், என்கூட வாங்க. நீங்க இப்போ கிளம்பணும்."}


## One of them comes over and asks (the guard, and he's asked to leave, at the worst).
func _come_ask(p: Dictionary, w: Node3D, out: bool) -> void:
	var n: Node3D = p["node"]
	var why := _how(w, 0.0)["why"] as String
	_asking = {"p": p, "out": out}
	var name: Dictionary = {"guard": {"en": "Security", "ta": "செக்யூரிட்டி"}, "receptionist": {"en": "Receptionist", "ta": "ரிசப்ஷன்"},
		"worker": {"en": "Staff", "ta": "ஸ்டாஃப்"}}.get(str(p["role"]), {"en": "Staff", "ta": "ஸ்டாஃப்"})
	_asking["name"] = _tx(name)
	if n.get_meta("crowd_pose", "") != "sit":            # (standing: they step up to him)
		var to := w.global_position - n.global_position
		to.y = 0.0
		if to.length() > 1.4:
			var tw := create_tween()
			tw.tween_property(n, "global_position", n.global_position + to.normalized() * (to.length() - 1.2), clampf(to.length() / 1.3, 0.3, 6.0))
			var aps := n.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty() and (aps[0] as AnimationPlayer).has_animation("Walk"):
				(aps[0] as AnimationPlayer).play("Walk", 0.3)
				tw.tween_callback(func(): (aps[0] as AnimationPlayer).play("Idle", 0.4))
			n.rotation.y = atan2(to.x, to.z)
	if "active" in w:
		w.active = false
	var m: Dictionary = _mem.get(key, {})
	m["questioned"] = int(m.get("questioned", 0)) + 1
	_mem[key] = m
	_save()
	questioned.emit(n)
	if out:
		_say(_tx(OUT))
		_opts = [["leave", {"en": "All right. I'm going.", "ta": "சரி. நான் போறேன்."}],
			["explain", {"en": "I'm sorry. I came to meet someone, I lost my way.", "ta": "மன்னிச்சுக்கோங்க. ஒருத்தரைப் பார்க்க வந்தேன், வழி தெரியல."}]]
	else:
		_say(_tx(ASK.get(why, ASK[""])))
		_opts = [["sorry", {"en": "Sorry, I was looking for the way. I'll wait at the front.", "ta": "மன்னிச்சுக்கோங்க, வழி தேடினேன். முன்னாடி காத்திருக்கேன்."}],
			["meet", {"en": "I came to meet someone. Could you help me?", "ta": "ஒருத்தரைப் பார்க்க வந்தேன். உதவ முடியுமா?"}],
			["curt", {"en": "Nothing. Just looking.", "ta": "ஒண்ணுமில்ல. சும்மா பார்க்கிறேன்."}]]
	_show_opts()
	print("SOCIAL %s asks (%s, %s)" % [str(p["role"]), why, "out" if out else "question"])


func _say(line: String) -> void:
	if city and city.hud:
		city.hud.say(str(_asking.get("name", "")), line, 5.0)


func _show_opts() -> void:
	var lines := []
	for i in _opts.size():
		lines.append("%d  %s" % [i + 1, _tx(_opts[i][1])])
	_box.text = "\n".join(lines)
	var vs := get_viewport().get_visible_rect().size
	_box.position = Vector2(vs.x * 0.06, vs.y * 0.5)
	_box.visible = true


var _keys_was := {}


func _answering() -> void:
	var pick := -1
	for i in _opts.size():
		var k := KEY_1 + i
		var down := Input.is_key_pressed(k)
		if down and not _keys_was.get(k, false):
			pick = i
		_keys_was[k] = down
	if _test_pick >= 0:
		pick = _test_pick
		_test_pick = -1
	if pick < 0 or pick >= _opts.size():
		return
	var choice := str(_opts[pick][0])
	_box.visible = false
	var p: Dictionary = _asking["p"]
	var out: bool = _asking["out"]
	var m: Dictionary = _mem.get(key, {})
	var w: Node3D = city.walker
	var calm := func(v: float) -> void:                  # (at the counter he's just asking: it never raises it)
		p["sus"] = minf(float(p["sus"]), v) if _asking.get("greet", false) else v
	match choice:
		"sorry":
			calm.call(25.0)
			m["polite"] = int(m.get("polite", 0)) + 1
			_say(_tx({"en": "Fine, sir. The waiting chairs are just there.", "ta": "சரி சார். காத்திருக்கற சேர் அங்கதான் இருக்கு."}))
		"meet":
			calm.call(30.0)
			visitor = true
			m["polite"] = int(m.get("polite", 0)) + 1
			_say(_tx({"en": "Who, sir? ...I'll call. Please go ahead, first floor's open.", "ta": "யாரை சார்? ...கூப்பிடறேன். உள்ள போங்க."}) if _asking.get("greet", false)
				else _tx({"en": "Who? ...Ask at the front desk, sir, they'll call him.", "ta": "யாரு? ...முன்னாடி டெஸ்க்ல கேளுங்க சார், கூப்பிடுவாங்க."}))
		"wait":
			calm.call(0.0)
			m["polite"] = int(m.get("polite", 0)) + 1
			_say(_tx({"en": "Please have a seat, sir.", "ta": "உட்காருங்க சார்."}))
		"curt":
			p["sus"] = 72.0                               # (not an answer: they keep their eyes on him)
			m["curt"] = int(m.get("curt", 0)) + 1
			_say({"en": "...Then look from the front, sir.", "ta": "...அப்போ முன்னாடி இருந்து பாருங்க சார்."}[_lang()])
		"explain":
			m["polite"] = int(m.get("polite", 0)) + 1
			if int(m.get("out_today", 0)) == 0 and int(m.get("curt", 0)) == 0:   # (a first time, said well: one chance)
				p["sus"] = 40.0
				out = false
				_say({"en": "...Front desk, sir. Not here again.", "ta": "...முன்னாடி டெஸ்க், சார். மறுபடி இங்க வேண்டாம்."}[_lang()])
			else:
				_say(_tx(OUT))
		"leave":
			pass
	_mem[key] = m
	_save()
	_asking = {}
	if "active" in w:
		w.active = true
	if out:
		_send_out()


## Walked out by the guard: remembered (twice in a day: not let in again that day).
func _send_out() -> void:
	_leaving = true
	var m: Dictionary = _mem.get(key, {})
	if int(m.get("out_day", -1)) != _day():
		m["out_today"] = 0
	m["out_day"] = _day()
	m["out_today"] = int(m.get("out_today", 0)) + 1
	m["sent_out"] = int(m.get("sent_out", 0)) + 1
	_mem[key] = m
	_save()
	sent_out.emit(key)
	print("SOCIAL sent out of %s (%d today)" % [key, int(m["out_today"])])
	await get_tree().create_timer(2.0).timeout
	if city and city.doors and city.walker:
		city.doors.leave(city.walker)


# ---- at the counter ----
## E at the counter: what he can say (city_doors.gd offers it by the counter person).
func greet_offer() -> String:
	return "talk at the front desk" if _lang() == "en" else "முன்னாடி டெஸ்க்ல பேசு"


func greet() -> void:
	var m: Dictionary = _mem.get(key, {})
	var rec := {}
	for q in people:
		if str(q["role"]) == "receptionist":
			rec = q
	if rec.is_empty():
		return
	_asking = {"p": rec, "out": false, "name": "Receptionist" if _lang() == "en" else "ரிசப்ஷன்", "greet": true}
	var line := {"en": "Good morning, sir. Who are you here to meet?", "ta": "வணக்கம் சார். யாரைப் பார்க்க வந்தீங்க?"}
	if int(m.get("visits", 0)) > 1 and int(m.get("last_day", -1)) == _day():
		line = {"en": "You were here a little while ago, sir. Something else?", "ta": "கொஞ்ச நேரம் முன்னாடி வந்திருந்தீங்க சார். வேற ஏதாவது?"}
	elif int(m.get("visits", 0)) > 1:
		line = {"en": "You were here before, sir. Is there something else you need?", "ta": "முன்னாடியும் வந்திருந்தீங்க சார். வேற ஏதாவது வேணுமா?"}
	if int(m.get("sent_out", 0)) > 0:
		line = {"en": "(She recognises me. Her smile goes.) Yes, sir?", "ta": "(அவங்களுக்கு என்னைத் தெரியுது. சிரிப்பு போயிடுச்சு.) சொல்லுங்க சார்?"}
	if "active" in city.walker:
		city.walker.active = false
	_say(_tx(line))
	_opts = [["meet", {"en": "I've come to meet someone here.", "ta": "இங்க ஒருத்தரைப் பார்க்க வந்தேன்."}],
		["sorry", {"en": "Just asking the way, madam. Thank you.", "ta": "வழி கேட்கத்தான் மேடம். நன்றி."}],
		["wait", {"en": "I'll wait here, thank you.", "ta": "இங்க காத்திருக்கேன், நன்றி."}]]
	_show_opts()


func _load() -> void:
	if FileAccess.file_exists(MEMORY):
		var all = JSON.parse_string(FileAccess.get_file_as_string(MEMORY))
		if all is Dictionary:
			_mem = all
	if "--socialtest" in OS.get_cmdline_user_args():     # (a test doesn't keep or use what real visits left)
		_mem = {}


func _save() -> void:
	if "--socialtest" in OS.get_cmdline_user_args():
		return
	var f := FileAccess.open(MEMORY, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_mem))


var _test_pick := -1


# ---- testing ----
func _states() -> String:
	var out := []
	for q in people:
		out.append("%s %.0f%s" % [str(q["role"]), float(q["sus"]), "*" if q["seen"] else ""])
	return ", ".join(out)


func _run_test() -> void:
	var tree := get_tree()
	var w: Node3D = city.walker
	await tree.create_timer(1.0).timeout
	print("SOCIALTEST walking in normally: %s" % _states())
	w.auto_input = Vector2(0, -1)
	await tree.create_timer(3.0).timeout
	w.auto_input = Vector2.ZERO
	print("SOCIALTEST after walking about 3 s: %s" % _states())
	var worker := {}
	for q in people:
		if str(q["role"]) == "worker" and worker.is_empty():
			worker = q
	if worker.is_empty():
		print("SOCIALTEST no worker at a desk here")
		tree.quit()
		return
	var wn: Node3D = worker["node"]                       # round his desk: beside him, in his view
	w.global_position = wn.global_position + wn.global_basis.z * 0.9 + wn.global_basis.x * 0.5 + Vector3.UP * 0.2
	var t := 0.0
	while _asking.is_empty() and t < 25.0:
		await tree.process_frame
		t += get_process_delta_time()
	print("SOCIALTEST lingering at a worker's desk: asked after %.1f s: %s" % [t, _states()])
	await _snap("social_asked")
	_test_pick = 0                                       # "Sorry, I was looking for the way."
	await tree.create_timer(0.5).timeout
	print("SOCIALTEST answered politely: %s" % _states())
	await tree.create_timer(2.0).timeout
	t = 0.0
	while not _leaving and t < 30.0:                     # searching his desk now, again and again
		act("search", wn.global_position)
		if not _asking.is_empty():
			print("SOCIALTEST asked while searching (%s): %s" % ["to leave" if _asking["out"] else "a question", _states()])
			await _snap("social_searching")
			_test_pick = 0
		await tree.create_timer(0.5).timeout
		t += 0.5
	print("SOCIALTEST sent out: %s after %.1f s" % [_leaving, t])
	await tree.create_timer(3.0).timeout
	tree.quit()


func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_jpg(ProjectSettings.globalize_path("user://%s.jpg" % n), 0.85)
