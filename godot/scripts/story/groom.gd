extends RefCounted
## Brushing and bathing as touch play (the way Talking Tom 2 does it): a big close-up of Karthik who reacts to
## what you do with your hand (the mouse).
##   brush  drag the paste onto the brush; scrub the stains off his teeth (foam builds up, he giggles); hand him
##          the tumbler: he gargles and spits; a sparkling grin
##   bath   a bucket bath: pour mug after mug of cold morning water (he shivers); rub the soap all over him (foam,
##          giggles); rinse the foam away with the mug; towel him dry
## tasks.gd owns the panel; it forwards input to `input()`, calls `process()` every frame and `draw()` from its
## own _draw, and moves on when `done` turns true.

const SKIN := Color(0.8, 0.6, 0.45)
const SKIN_DARK := Color(0.66, 0.46, 0.33)
const HAIR := Color(0.06, 0.05, 0.05)
const LIP := Color(0.55, 0.28, 0.25)
const MOUTH := Color(0.35, 0.08, 0.1)
const TOOTH := Color(0.98, 0.97, 0.93)
const STAIN := Color(0.78, 0.62, 0.22)
const FOAM := Color(1.0, 1.0, 1.0)
const FOAM_EDGE := Color(0.75, 0.88, 1.0)
const WATER := Color(0.55, 0.8, 1.0, 0.85)
const INK := Color(0.12, 0.12, 0.14)

var mode := ""                                  # brush / bath
var stage := ""
var done := false
var area := Rect2()
var lang := "en"
var said := ""                                  # a line for tasks.gd to show (what he says)
var said_new := false
var t := 0.0

var hand := Vector2.ZERO                        # the mouse
var held := ""                                  # what the hand holds: brush / tube / tumbler / mug / soap / towel
var down := false
var _last := Vector2.ZERO
var face := "normal"                            # normal / giggle / squeeze / shiver / puff / grin / spit
var _face_t := 0.0
var _blink := 2.0
var _wait := 0.0                                # a little beat before the next stage
var _spat := false

# brush
var pasted := false
var stains: Array = []                          # [{p: Vector2 (rel. to the mouth), r, dirt 0..1}]
# both
var foam: Array = []                            # [{p (rel. to area centre), r, w (wobble phase)}]
var drops: Array = []                           # [{p, v, life}] water in the air
var wet := 0.0
var cells := {}                                 # bath: soaped body cells
var beads: Array = []                           # bath: water beads on his skin, towelled off
var sparkle := 0.0

var _audio: AudioStreamPlayer
var _scrub_snd: AudioStreamPlayer
var _sounds := {}


func start(m: String, a: Rect2, language: String, host: Node) -> void:
	mode = m
	area = a
	lang = language
	done = false
	held = ""
	foam.clear()
	drops.clear()
	beads.clear()
	cells.clear()
	wet = 0.0
	pasted = false
	_spat = false
	sparkle = 0.0
	_wait = 0.0
	face = "normal"
	if mode == "brush":
		stage = "paste"
		stains.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 9:                             # on the upper and lower rows of teeth
			var up := i % 2 == 0
			stains.append({"p": Vector2(rng.randf_range(-70, 70), -14.0 if up else 22.0), "r": rng.randf_range(11, 17), "dirt": 1.0})
	else:
		stage = "wet"
	_say("")
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.volume_db = -8.0
		host.add_child(_audio)
		_scrub_snd = AudioStreamPlayer.new()
		_scrub_snd.volume_db = -14.0
		host.add_child(_scrub_snd)
		_sounds = {"pop": _tone(0.07, 900.0, 1600.0, 0.0), "ting": _tone(0.6, 2600.0, 2600.0, 0.0, true),
			"splash": _noise(0.55, 0.5), "scrub": _noise(0.22, 0.12), "gargle": _gargle(1.1), "spit": _noise(0.25, 0.35)}


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func _say(s: String) -> void:
	said = s
	said_new = s != ""


func _play(name: String) -> void:
	if _audio and _sounds.has(name):
		_audio.stream = _sounds[name]
		_audio.play()


func _react(f: String, secs := 0.8) -> void:
	face = f
	_face_t = secs


# ---- where things are (relative to the area) ----
func _c() -> Vector2:
	return area.get_center()


func _mouth() -> Vector2:                       # brush: the open mouth's centre
	return _c() + Vector2(0, 92)


func _head_c() -> Vector2:                      # bath: his head
	return _c() + Vector2(-60, -120)


func _tool_home(name: String) -> Vector2:
	var a := area
	match name:
		"brush":
			return Vector2(a.end.x - 110, a.end.y - 60)
		"tube":
			return Vector2(a.position.x + 90, a.end.y - 60)
		"tumbler":
			return Vector2(a.end.x - 90, a.position.y + 150)
		"mug":
			return Vector2(a.end.x - 120, a.end.y - 150)
		"soap":
			return Vector2(a.position.x + 90, a.end.y - 70)
		"towel":
			return Vector2(a.position.x + 100, a.position.y + 110)
	return a.get_center()


func _tools() -> Array:
	if mode == "brush":
		match stage:
			"paste":
				return ["tube", "brush"]
			"scrub":
				return ["brush"]
			"rinse":
				return ["tumbler", "brush"]
		return ["brush"]
	match stage:
		"wet", "rinse":
			return ["mug", "soap", "towel"]
		"soap":
			return ["soap", "mug", "towel"]
		"towel":
			return ["towel", "mug", "soap"]
	return ["mug", "soap", "towel"]


func _active_tool() -> String:                  # the one the hint points at
	match stage:
		"paste":
			return "tube"
		"scrub":
			return "brush"
		"rinse":
			return "tumbler" if mode == "brush" else "mug"
		"wet":
			return "mug"
		"soap":
			return "soap"
		"towel":
			return "towel"
	return ""


func _tool_at(name: String) -> Vector2:
	return hand if held == name else _tool_home(name)


func _on_body(p: Vector2) -> bool:              # bath: is p on him (head, torso, arms)?
	var h := _head_c()
	if ((p - h) / Vector2(72, 84)).length() < 1.0:
		return true
	var tc := _c() + Vector2(-60, 40)
	if ((p - tc) / Vector2(125, 120)).length() < 1.0:
		return true
	return false


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _c().x) / 34.0), floori((p.y - _c().y) / 34.0))


func _body_cells() -> int:                      # how many soap cells his body has
	var n := 0
	for x in range(-8, 4):
		for y in range(-7, 6):
			if _on_body(_c() + Vector2(x * 34 + 17, y * 34 + 17)):
				n += 1
	return n


# ---- the hand ----
func input(e: InputEvent) -> void:
	if done:
		return
	if e is InputEventMouseMotion:
		var p: Vector2 = e.position
		var moved := p.distance_to(_last)
		hand = p
		if down:
			_rub(p, moved)
		_last = p
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		hand = e.position
		_last = hand
		if e.pressed:
			down = true
			for k in _tools():
				if hand.distance_to(_tool_home(k)) < 60.0:
					held = k
					_play("pop")
					if k != _active_tool() and _wait <= 0.0:
						_hint_wrong(k)
					break
		else:
			down = false
			_let_go()


func _hint_wrong(k: String) -> void:
	match k:
		"soap":
			_say(L("Wet him first — pour some water.", "முதல்ல தண்ணி ஊத்து.") if stage == "wet" else L("Rinse off the soap first.", "முதல்ல சோப்பை கழுவு."))
		"towel":
			_say(L("Not yet — he's still soapy.", "இன்னும் இல்ல — சோப்பு இருக்கு."))
		"brush":
			if stage == "paste":
				_say(L("Paste first! Drag the tube onto the brush.", "முதல்ல பேஸ்ட்! டியூபை பிரஷ் மேல இழு."))


func _let_go() -> void:
	if held == "tube" and _tool_home("brush").distance_to(hand) < 70.0:
		pasted = true
		_play("pop")
		stage = "scrub"
		_say(L("Now scrub the yellow off his teeth!", "இப்போ பல்லுல இருக்கிற மஞ்சளை தேய்!"))
	elif held == "tumbler" and stage == "rinse" and hand.distance_to(_mouth()) < 90.0:
		stage = "gargle"
		_wait = 2.1
		_react("puff", 1.35)
		_play("gargle")
		_say(L("Glug glug glug...", "குளுக் குளுக் குளுக்..."))
	held = ""


func _rub(p: Vector2, moved: float) -> void:
	if moved <= 0.0:
		return
	if mode == "brush" and held == "brush" and stage == "scrub":
		var tip := p + Vector2(-58, -6)            # the bristles are at the brush's left end
		var m := _mouth()
		if ((tip - m) / Vector2(115, 62)).length() < 1.0:
			for s in stains:
				if tip.distance_to(m + s["p"]) < s["r"] + 16.0:
					s["dirt"] = maxf(s["dirt"] - moved / 260.0, 0.0)
			if randf() < moved / 30.0 and foam.size() < 70:
				var rel := tip - _c() + Vector2(randf_range(-14, 14), randf_range(-10, 10))
				foam.append({"p": rel, "r": randf_range(6, 14), "w": randf() * TAU})
			if not _scrub_snd.playing:
				_scrub_snd.stream = _sounds["scrub"]
				_scrub_snd.play()
			if face != "giggle" and randf() < 0.02:
				_react("giggle", 0.9)
				_say(L("Heehee — that tickles!", "ஹிஹி — கூச்சமா இருக்கு!"))
			var left := 0
			for s in stains:
				if s["dirt"] > 0.06:
					left += 1
			if left == 0:
				stage = "rinse"
				_play("ting")
				_say(L("Sparkling! Give him the tumbler to rinse.", "பளிச்! கொப்பளிக்க டம்ளரை கொடு."))
	elif mode == "bath" and held == "soap" and stage == "soap" and _on_body(p):
		var c := _cell(p)
		if not cells.has(c):
			cells[c] = true
		if randf() < moved / 18.0 and foam.size() < 160:
			foam.append({"p": p - _c() + Vector2(randf_range(-12, 12), randf_range(-12, 12)), "r": randf_range(9, 19), "w": randf() * TAU})
		if not _scrub_snd.playing:
			_scrub_snd.stream = _sounds["scrub"]
			_scrub_snd.play()
		if face != "giggle" and randf() < 0.015:
			_react("giggle", 1.0)
			_say([L("Heehee! Stop, it tickles!", "ஹிஹி! போதும், கூச்சமா இருக்கு!"), L("Mysore sandal... nice.", "மைசூர் சாண்டல்... நல்லா இருக்கு.")][randi() % 2])
		if float(cells.size()) / maxf(_body_cells(), 1) > 0.8:
			stage = "rinse"
			_say(L("All soapy! Now rinse him with the mug.", "முழுக்க சோப்பு! இப்போ மக்கால கழுவு."))
	elif mode == "bath" and held == "towel" and stage == "towel" and _on_body(p):
		for i in range(beads.size() - 1, -1, -1):
			if (beads[i]["p"] + _c()).distance_to(p) < 40.0:
				beads.remove_at(i)
		wet = maxf(wet - moved / 1800.0, 0.0)
		if beads.is_empty():
			stage = "fresh"
			_wait = 1.5
			sparkle = 1.5
			_react("grin", 1.6)
			_play("ting")
			_say(L("Fresh as a jasmine!", "மல்லிகை மாதிரி ஃப்ரெஷ்!"))


func process(dt: float) -> void:
	t += dt
	_face_t -= dt
	if _face_t <= 0.0 and face != "normal" and stage != "shine" and stage != "fresh":
		face = "normal"
	_blink -= dt
	if _blink < -0.13:
		_blink = randf_range(2.0, 4.5)
	sparkle = maxf(sparkle - dt, 0.0)
	# the mug pours while it's held down over him (tilted), the water falls and washes
	if mode == "bath" and held == "mug" and down and (stage == "wet" or stage == "rinse"):
		for k in 3:
			drops.append({"p": hand + Vector2(-34 + randf_range(-6, 6), 14), "v": Vector2(randf_range(-40, 10), randf_range(60, 140)), "life": 1.2})
		if not _audio.playing:
			_play("splash")
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d["v"] += Vector2(0, 900) * dt
		d["p"] += d["v"] * dt
		d["life"] -= dt
		if mode == "bath" and _on_body(d["p"]):
			if stage == "wet":
				wet = minf(wet + dt * 0.08, 1.0)
				if face != "shiver" and _face_t <= 0.0:
					_react("shiver", 1.0)
					_say([L("Brrr! Cold!", "ப்ர்ர்ர்! ஜில்லுனு இருக்கு!"), L("Aiyo, the water's ice!", "ஐயோ, தண்ணி ஐஸ் மாதிரி!")][randi() % 2])
				if wet >= 1.0:
					stage = "soap"
					_say(L("Now the soap — rub it all over.", "இப்போ சோப்பு — எல்லா இடத்துலயும் தேய்."))
			elif stage == "rinse":
				for j in range(foam.size() - 1, -1, -1):
					if (foam[j]["p"] + _c()).distance_to(d["p"]) < 26.0:
						foam.remove_at(j)
						if randf() < 0.3:
							beads.append({"p": d["p"] - _c() + Vector2(randf_range(-10, 10), randf_range(-6, 6))})
				if face != "squeeze" and _face_t <= 0.0:
					_react("squeeze", 0.8)
				if foam.size() < 4:
					foam.clear()
					stage = "towel"
					while beads.size() < 14:
						var bp := Vector2(randf_range(-170, 40), randf_range(-170, 120))
						if _on_body(bp + _c()):
							beads.append({"p": bp})
					_say(L("Squeaky clean! Dry him with the towel.", "சுத்தம்! டவலால துடை."))
		if d["life"] <= 0.0 or d["p"].y > area.end.y:
			drops.remove_at(i)
	# brushing: the beats after the gargle
	if _wait > 0.0:
		_wait -= dt
		if mode == "brush" and stage == "gargle" and _wait < 0.8 and not _spat:
			_spat = true
			_react("spit", 0.6)
			_play("spit")
			foam.clear()
			for k in 16:
				drops.append({"p": _mouth() + Vector2(randf_range(-20, 20), 10), "v": Vector2(randf_range(-160, 160), randf_range(-80, 60)), "life": 0.9})
		if _wait <= 0.0:
			if mode == "brush" and stage == "gargle":
				stage = "shine"
				_wait = 1.6
				sparkle = 1.6
				_react("grin", 2.0)
				_play("ting")
				_say(L("Ting! What a smile.", "டிங்! என்ன ஒரு சிரிப்பு."))
			elif stage == "shine" or stage == "fresh":
				done = true


# ---- drawing ----
func draw(ci: CanvasItem, font: Font) -> void:
	ci.draw_rect(area, Color(0.82, 0.9, 0.93) if mode == "brush" else Color(0.74, 0.84, 0.86))
	_tiles(ci)
	if mode == "brush":
		_draw_face(ci)
	else:
		_draw_bather(ci)
	for f in foam:
		var p: Vector2 = f["p"] + _c() + Vector2(sin(t * 3.0 + f["w"]), cos(t * 2.5 + f["w"])) * 1.5
		ci.draw_circle(p, f["r"] + 1.5, FOAM_EDGE)
		ci.draw_circle(p, f["r"], FOAM)
		ci.draw_circle(p + Vector2(-f["r"] * 0.35, -f["r"] * 0.35), f["r"] * 0.25, Color(1, 1, 1, 0.9))
	for b in beads:
		var p: Vector2 = b["p"] + _c()
		ci.draw_circle(p, 4.0, Color(0.7, 0.9, 1.0, 0.8))
		ci.draw_circle(p + Vector2(-1.2, -1.2), 1.4, Color(1, 1, 1))
	for d in drops:
		ci.draw_line(d["p"], d["p"] - d["v"] * 0.02, WATER, 3.0)
	if sparkle > 0.0:
		for k in 5:
			var a := float(k) / 5.0 * TAU + t
			var sp := (_mouth() if mode == "brush" else _head_c()) + Vector2(cos(a) * 110, sin(a) * 40 - 10)
			_star(ci, sp, 10.0 + 8.0 * sin(t * 12.0 + k), Color(1, 1, 0.75))
	for k in _tools():
		if held != k:
			_draw_tool(ci, k, _tool_home(k), false)
	if held != "":
		_draw_tool(ci, held, hand, down)
	var act := _active_tool()
	if act != "" and held == "" and _wait <= 0.0:          # a pulsing ring on what to pick up next
		var r := 46.0 + 6.0 * sin(t * 6.0)
		ci.draw_arc(_tool_home(act), r, 0, TAU, 40, Color(1, 0.85, 0.2, 0.9), 4.0)
	ci.draw_string(font, Vector2(area.position.x, area.end.y + 24), _instruction(), HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 17, INK)


func _instruction() -> String:
	match stage:
		"paste":
			return L("Drag the toothpaste onto the brush", "டூத்பேஸ்டை பிரஷ் மேல இழு")
		"scrub":
			return L("Hold the brush and scrub every yellow spot", "பிரஷை பிடிச்சு ஒவ்வொரு மஞ்சள் புள்ளியையும் தேய்")
		"rinse":
			return L("Drag the tumbler to his mouth", "டம்ளரை வாய்க்கு இழு") if mode == "brush" else L("Hold the mug over him to wash the soap off", "மக்கை மேல பிடிச்சு சோப்பை கழுவு")
		"wet":
			return L("Hold the mug over him and pour", "மக்கை அவன் மேல பிடிச்சு ஊத்து")
		"soap":
			return L("Rub the soap all over him", "சோப்பை எல்லா இடத்துலயும் தேய்")
		"towel":
			return L("Rub him dry with the towel", "டவலால துடை")
	return ""


func _tiles(ci: CanvasItem) -> void:
	var col := Color(1, 1, 1, 0.25)
	var s := 60.0
	var x := area.position.x
	while x < area.end.x:
		ci.draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), col, 1.0)
		x += s
	var y := area.position.y
	while y < area.end.y:
		ci.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), col, 1.0)
		y += s


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, n := 40) -> void:
	var pts := PackedVector2Array()
	for i in n:
		var a := float(i) / n * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_poly(ci, pts, col)


## A filled shape kept inside the picture's frame.
func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var frame := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	for q in Geometry2D.intersect_polygons(pts, frame):
		if q.size() >= 3:
			ci.draw_colored_polygon(q, col)


func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := float(i) / 8.0 * TAU
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.3))
	ci.draw_colored_polygon(pts, col)


func _eyes(ci: CanvasItem, c: Vector2, sx: float, sy: float, sc: float) -> void:
	"""Both eyes at c ± sx, by the face's mood."""
	for s in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(s * sx, sy)
		ci.draw_line(e + Vector2(-26, -34) * sc, e + Vector2(24, -38 - s * 2) * sc, HAIR, 9.0 * sc)    # the brows
		match face:
			"giggle", "grin":
				ci.draw_arc(e + Vector2(0, 6) * sc, 18.0 * sc, PI + 0.3, TAU - 0.3, 16, INK, 5.0 * sc)
			"squeeze", "shiver", "spit":
				ci.draw_line(e + Vector2(-18, -4) * sc, e + Vector2(16, 4) * sc, INK, 5.0 * sc)
				ci.draw_line(e + Vector2(-18, 8) * sc, e + Vector2(16, 2) * sc, INK, 5.0 * sc)
			"puff":
				_ellipse(ci, e, 22 * sc, 20 * sc, Color.WHITE)
				ci.draw_circle(e + Vector2(s * -4, 0) * sc, 10.0 * sc, Color(0.2, 0.12, 0.08))
			_:
				if _blink < 0.0:
					ci.draw_line(e + Vector2(-20, 0) * sc, e + Vector2(20, 0) * sc, INK, 5.0 * sc)
				else:
					_ellipse(ci, e, 22 * sc, 15 * sc, Color.WHITE)
					var look: Vector2 = ((hand - e).normalized() * 6.0 * sc) if hand != Vector2.ZERO else Vector2.ZERO
					ci.draw_circle(e + look, 10.0 * sc, Color(0.22, 0.13, 0.08))
					ci.draw_circle(e + look, 5.0 * sc, Color(0.02, 0.02, 0.02))
					ci.draw_circle(e + look + Vector2(-3, -3) * sc, 2.5 * sc, Color.WHITE)


## Short hair with a side parting, over the head at c (sc: the head's scale; wet: flatter, lower).
func _hair(c: Vector2, sc: float, wet: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 21:                                  # the crown, ear to ear over the top
		var a := PI + 0.42 + float(i) / 20.0 * (PI - 0.84)
		pts.append(c + Vector2(cos(a) * 184, sin(a) * (222 - wet * 20) - 4) * sc)
	for i in 13:                                  # the hairline: temples, a wave, the parting on his left
		var u := float(i) / 12.0
		var x := lerpf(178, -178, u)
		var y := -88.0 - 26.0 * sin(u * PI) + 10.0 * sin(u * 9.0) + wet * 16.0
		if absf(u - 0.7) < 0.05:
			y -= 22.0
		pts.append(c + Vector2(x, y) * sc)
	return pts


func _draw_face(ci: CanvasItem) -> void:
	var c := _c() + Vector2(0, 6)
	var wob := Vector2(sin(t * 30.0) * 3.0, 0) if face == "puff" else Vector2.ZERO
	c += wob
	# shoulders, a vest, the neck, ears, the head, his hair
	_ellipse(ci, c + Vector2(0, 290), 260, 110, Color(0.93, 0.93, 0.9))
	_poly(ci, PackedVector2Array([c + Vector2(-55, 150), c + Vector2(55, 150), c + Vector2(55, 240), c + Vector2(-55, 240)]), SKIN_DARK)
	for s in [-1.0, 1.0]:
		_ellipse(ci, c + Vector2(s * 172, 10), 26, 40, SKIN_DARK)
	_ellipse(ci, c, 175, 205, SKIN)
	_poly(ci, _hair(c, 1.0, 0.0), HAIR)
	ci.draw_arc(c + Vector2(-60, -150), 70, PI + 0.5, TAU - 0.9, 12, Color(0.3, 0.3, 0.35, 0.6), 4.0)   # the oil's shine
	if face == "puff":                          # gargling: the cheeks puffed out
		for s in [-1.0, 1.0]:
			_ellipse(ci, c + Vector2(s * 95, 80), 60, 52, SKIN.lerp(Color(0.95, 0.5, 0.45), 0.25))
	_eyes(ci, c + Vector2(0, -20), 68, 0, 1.0)
	ci.draw_arc(c + Vector2(0, 36), 16, 0.2, PI - 0.2, 12, SKIN_DARK, 5.0)            # the nose
	var m := _mouth() + wob
	# the moustache
	ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-82, -58), m + Vector2(0, -70), m + Vector2(82, -58), m + Vector2(60, -48),
		m + Vector2(0, -56), m + Vector2(-60, -48)]), HAIR)
	match face:
		"puff", "spit":
			ci.draw_line(m + Vector2(-26, -10), m + Vector2(26, -10), LIP, 7.0)
			if face == "spit":
				_ellipse(ci, m + Vector2(0, -8), 16, 12, MOUTH)
		_:
			var open := 1.0 if stage in ["scrub", "rinse", "paste"] else 0.8
			_ellipse(ci, m, 118, 62 * open, LIP)
			_ellipse(ci, m, 108, 52 * open, MOUTH)
			_ellipse(ci, m + Vector2(0, 30 * open), 60, 20, Color(0.85, 0.4, 0.42))            # the tongue
			for row in [-1, 1]:                                                                  # teeth, upper and lower
				var y := m.y + (-24.0 if row < 0 else 20.0) * open
				for k in 8:
					var x := m.x - 84 + k * 24
					var h := 22.0 - absf(k - 3.5) * 1.6
					ci.draw_rect(Rect2(Vector2(x, y - h * 0.5), Vector2(21, h)), TOOTH)
			for s in stains:
				if s["dirt"] > 0.02:
					var col := STAIN
					col.a = 0.85 * s["dirt"]
					ci.draw_circle(m + s["p"] * Vector2(1, open), s["r"], col)


func _draw_bather(ci: CanvasItem) -> void:
	var c := _c()
	# the bathroom: a tap on the wall, the bucket with the mug, a stool, a towel on a nail, soap on the ledge
	ci.draw_rect(Rect2(Vector2(area.position.x, area.end.y - 40), Vector2(area.size.x, 40)), Color(0.55, 0.6, 0.62))
	ci.draw_rect(Rect2(Vector2(area.end.x - 160, area.position.y + 40), Vector2(16, 60)), Color(0.75, 0.75, 0.78))
	var bk := Vector2(area.end.x - 120, area.end.y - 90)
	ci.draw_colored_polygon(PackedVector2Array([bk + Vector2(-70, -60), bk + Vector2(70, -60), bk + Vector2(55, 60), bk + Vector2(-55, 60)]), Color(0.15, 0.4, 0.75))
	_ellipse(ci, bk + Vector2(0, -60), 70, 14, Color(0.45, 0.72, 0.95))
	ci.draw_rect(Rect2(Vector2(area.position.x + 40, area.end.y - 85), Vector2(100, 14)), Color(0.85, 0.85, 0.82))   # the soap ledge
	var shiver := Vector2(sin(t * 60.0) * 2.5, 0) if face == "shiver" else Vector2.ZERO
	var h := _head_c() + shiver
	# the stool, his legs, the thorthu (towel) round his waist
	var tc := c + Vector2(-60, 40) + shiver
	ci.draw_rect(Rect2(tc + Vector2(-110, 150), Vector2(220, 30)), Color(0.75, 0.15, 0.12))
	for s in [-1.0, 1.0]:
		ci.draw_rect(Rect2(tc + Vector2(s * 90 - 10, 180), Vector2(20, 14)), Color(0.65, 0.12, 0.1))
	# the body: a slim young man's torso and arms, wet skin darker and shinier
	var skin := SKIN.lerp(SKIN_DARK, wet * 0.35)
	for s in [-1.0, 1.0]:                          # the arms, from the shoulder to the hands on his knees
		_poly(ci, PackedVector2Array([tc + Vector2(s * 92, -92), tc + Vector2(s * 122, -78), tc + Vector2(s * 128, 0),
			tc + Vector2(s * 118, 96), tc + Vector2(s * 92, 100), tc + Vector2(s * 96, 0)]), skin.darkened(0.07))
		_ellipse(ci, tc + Vector2(s * 104, 102), 20, 14, skin.darkened(0.1))
	_poly(ci, PackedVector2Array([tc + Vector2(-60, -112), tc + Vector2(60, -112), tc + Vector2(100, -92), tc + Vector2(98, -30),
		tc + Vector2(80, 40), tc + Vector2(76, 110), tc + Vector2(-76, 110), tc + Vector2(-80, 40), tc + Vector2(-98, -30),
		tc + Vector2(-100, -92)]), skin)
	ci.draw_arc(tc + Vector2(-34, -40), 30, 0.5, 2.6, 10, SKIN_DARK, 3.0)        # the chest
	ci.draw_arc(tc + Vector2(34, -40), 30, 0.55, 2.65, 10, SKIN_DARK, 3.0)
	ci.draw_line(tc + Vector2(0, -10), tc + Vector2(0, 70), SKIN_DARK.lerp(skin, 0.5), 2.0)
	ci.draw_circle(tc + Vector2(0, 72), 3.0, SKIN_DARK)
	if wet > 0.2:                                   # the wet sheen
		ci.draw_arc(tc + Vector2(-50, -60), 34, PI + 0.4, TAU - 0.6, 10, Color(1, 1, 1, 0.35 * wet), 4.0)
	# the thorthu (a thin cotton towel) round his waist
	_ellipse(ci, tc + Vector2(0, 124), 120, 46, Color(0.95, 0.95, 0.92))
	for k in 4:
		ci.draw_line(tc + Vector2(-110, 106 + k * 12), tc + Vector2(110, 106 + k * 12), Color(0.8, 0.3, 0.25, 0.6), 2.0)
	ci.draw_rect(Rect2(h + Vector2(-26, 60), Vector2(52, 50)), skin.darkened(0.08))           # the neck
	for s in [-1.0, 1.0]:
		_ellipse(ci, h + Vector2(s * 70, 6), 14, 22, skin.darkened(0.08))
	_ellipse(ci, h, 72, 84, skin)
	var hair := HAIR.lerp(Color(0.12, 0.14, 0.18), wet)                                      # wet hair sticks down and shines
	_poly(ci, _hair(h, 0.41, wet), hair)
	if wet > 0.3:
		for k in 5:                                 # wet strands stuck to the forehead
			ci.draw_line(h + Vector2(-46 + k * 23, -34), h + Vector2(-44 + k * 23, -26 + (k % 2) * 4), hair, 4.0)
		ci.draw_arc(h + Vector2(-20, -66), 16, PI + 0.6, TAU - 0.6, 8, Color(1, 1, 1, 0.5), 3.0)
	_eyes(ci, h + Vector2(0, -6), 28, 0, 0.42)
	ci.draw_colored_polygon(PackedVector2Array([h + Vector2(-34, 30), h + Vector2(0, 25), h + Vector2(34, 30), h + Vector2(26, 35),
		h + Vector2(0, 31), h + Vector2(-26, 35)]), HAIR)                                       # the moustache
	match face:
		"shiver":
			_ellipse(ci, h + Vector2(0, 50), 12, 9 + sin(t * 50.0) * 3.0, MOUTH)
		"giggle", "grin":
			_ellipse(ci, h + Vector2(0, 48), 24, 14, MOUTH)
			ci.draw_rect(Rect2(h + Vector2(-18, 38), Vector2(36, 7)), TOOTH)
		"squeeze":
			ci.draw_line(h + Vector2(-14, 50), h + Vector2(14, 50), LIP, 5.0)
		_:
			ci.draw_arc(h + Vector2(0, 38), 18, 0.4, PI - 0.4, 12, LIP, 5.0)


func _draw_tool(ci: CanvasItem, k: String, p: Vector2, using: bool) -> void:
	match k:
		"brush":
			ci.draw_rect(Rect2(p + Vector2(-60, -8), Vector2(130, 16)), Color(0.2, 0.55, 0.9))
			ci.draw_rect(Rect2(p + Vector2(-66, -26), Vector2(34, 18)), Color(0.95, 0.95, 0.98))      # bristles
			for i in 6:
				ci.draw_line(p + Vector2(-64 + i * 6, -26), p + Vector2(-64 + i * 6, -8), Color(0.7, 0.85, 1.0), 1.5)
			if pasted and stage == "scrub":
				for i in 4:
					ci.draw_circle(p + Vector2(-60 + i * 9, -30), 6.0, Color(0.95, 0.98, 1.0))
					ci.draw_circle(p + Vector2(-58 + i * 9, -31), 3.0, Color(0.4, 0.75, 1.0))
		"tube":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-45, -16), p + Vector2(35, -12), p + Vector2(35, 12), p + Vector2(-45, 16)]), Color(0.95, 0.95, 0.95))
			ci.draw_rect(Rect2(p + Vector2(-45, -16), Vector2(30, 32)), Color(0.85, 0.15, 0.15))
			ci.draw_rect(Rect2(p + Vector2(35, -7), Vector2(14, 14)), Color(0.2, 0.4, 0.8))
		"tumbler":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-26, -38), p + Vector2(26, -38), p + Vector2(20, 38), p + Vector2(-20, 38)]), Color(0.78, 0.8, 0.83))
			ci.draw_line(p + Vector2(-10, -30), p + Vector2(-8, 30), Color(1, 1, 1, 0.7), 4.0)
		"mug":
			var tilt := -0.9 if using else 0.0
			var pts := PackedVector2Array()
			for q in [Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)]:
				pts.append(p + q.rotated(tilt))
			ci.draw_colored_polygon(pts, Color(0.9, 0.35, 0.2))
			ci.draw_arc(p + Vector2(42, 0).rotated(tilt), 16, -1.4, 1.4, 10, Color(0.9, 0.35, 0.2), 7.0)
		"soap":
			ci.draw_rect(Rect2(p + Vector2(-34, -18), Vector2(68, 36)), Color(0.95, 0.6, 0.45))
			ci.draw_rect(Rect2(p + Vector2(-28, -12), Vector2(56, 24)), Color(0.98, 0.7, 0.55))
		"towel":
			ci.draw_rect(Rect2(p + Vector2(-45, -50), Vector2(90, 100)), Color(0.95, 0.95, 0.92))
			for i in 4:
				ci.draw_line(p + Vector2(-45, -40 + i * 26), p + Vector2(45, -40 + i * 26), Color(0.85, 0.3, 0.25), 3.0)


# ---- sounds, made here (no audio files) ----
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.data = b
	return w


func _tone(secs: float, f0: float, f1: float, _unused: float, bell := false) -> AudioStreamWAV:
	var n := int(secs * 22050)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var u := float(i) / n
		ph += TAU * lerpf(f0, f1, u) / 22050.0
		var v := sin(ph) * (1.0 - u)
		if bell:
			v = (sin(ph) * 0.6 + sin(ph * 1.5) * 0.3 + sin(ph * 2.01) * 0.2) * exp(-u * 5.0)
		s[i] = v * 0.5
	return _wav(s)


func _noise(secs: float, smooth: float) -> AudioStreamWAV:
	var n := int(secs * 22050)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		lp = lerpf(lp, randf_range(-1, 1), smooth)
		s[i] = lp * sin(u * PI) * 0.6
	return _wav(s)


func _gargle(secs: float) -> AudioStreamWAV:
	var n := int(secs * 22050)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		lp = lerpf(lp, randf_range(-1, 1), 0.15)
		s[i] = lp * (0.5 + 0.5 * sin(u * TAU * 14.0)) * sin(u * PI) * 0.8
	return _wav(s)
