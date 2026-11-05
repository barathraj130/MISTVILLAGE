extends Control
## The trial (STORY_BIBLE.md Act 6): the Sessions Court puts the night to Karthik, point by point, and he answers with
## what he found. Each of the prosecution's points ("claims") is shown with the evidence he has (story.gd's
## `evidence`: tag → title, body, paid); 1–9 or a click puts one before the court. The right one answers the point;
## one he paid for is objected to ("bought: it walks on one leg") and needs a second, honest one beside it; a wrong
## one costs the court's patience. Then Sundaram's journey reconstruction: the city map, the clock running from
## 9:45 to 11:10 PM, Karthik's way (the hotel, Ashwin's door, home) and the SUV's (Raghavan's gate, the Lawley Road
## camera, Pudhur Vayal) side by side, each moment with its evidence. Enter at the end: the verdict is the court's.

signal finished(result: Dictionary)

var lang := "en"
var font: Font
var claims: Array = []
var evidence := {}                         # tag → {title, body, paid}
var places := {}                           # the chapter's places (x, z)
var map_segs := {}                         # city_map.gd's all_segs: class → segment pairs
var skip := false

var _i := 0                                # the claim before the court
var _given: Array = []                     # tags put before it, this claim
var _say := ""                             # the last thing said (judge, prosecutor, Sundaram)
var _say_who := ""
var _patience := 3
var _won := 0
var _phase := "claims"                     # claims → replay → done
var _t := 0.0
var _keys := {}
var _tags: Array = []

const T0 := 21.0 * 60 + 45.0               # the replay's clock: 9:45 PM …
const T1 := 23.0 * 60 + 10.0               # … 11:10 PM
# [minute, place, what proves it]
const KARTHIK := [[1305.0, "home", "E04"], [1310.0, "hotel", "E04"], [1340.0, "ashwin", "E05"], [1385.0, "home", "E05"]]
const SUV := [[1320.0, "raghavan_house", "E02"], [1332.0, "lawley_junction", "E02"], [1355.0, "pudhur_vayal", "E08"],
	[1365.0, "pudhur_vayal", "E17"], [1390.0, "pudhur_vayal", "E13"]]


func L(d) -> String:
	if d is Dictionary:
		return str(d.get(lang, d.get("en", "")))
	return str(d)


func start(spec: Dictionary, ev: Dictionary, language: String, testing: bool) -> void:
	lang = language
	font = ThemeDB.fallback_font
	claims = spec.get("claims", [])
	evidence = ev
	skip = testing
	_tags = evidence.keys().filter(func(t): return str(t).begins_with("E"))   # (the evidence, not the leads)
	_tags.sort_custom(func(a, b): return int(str(a).substr(1)) < int(str(b).substr(1)))
	_i = 0
	_given.clear()
	_patience = 3
	_won = 0
	_phase = "claims"
	_t = 0.0
	_say_who = L({"en": "Public Prosecutor", "ta": "அரசு வழக்கறிஞர்"})
	_say = L(claims[0]["claim"]) if not claims.is_empty() else ""
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	queue_redraw()
	if _phase == "claims":
		for i in mini(_tags.size(), 9):
			var down := Input.is_key_pressed(KEY_1 + i)
			if down and not _keys.get(i, false):
				_present(str(_tags[i]))
			_keys[i] = down
		if skip and _t > 1.2:                          # (testing: the right one, or what there is)
			_t = 0.0
			var want: Array = claims[_i]["answers"]
			var pick := ""
			for tg in want:
				if evidence.has(tg) and not tg in _given:
					pick = tg
					break
			_present(pick if pick != "" else str(_tags[0]))
	elif _phase == "replay":
		var mins: float = T0 + _t * (12.0 if skip else 3.0)
		if mins >= T1 + 3.0:
			_phase = "done"
			_t = 0.0
	elif _phase == "done":
		if Input.is_key_pressed(KEY_ENTER) or (skip and _t > 1.5):
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			finished.emit({"won": _won, "of": claims.size()})


func _gui_input(e: InputEvent) -> void:
	if _phase == "claims" and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for i in _tags.size():
			if _card(i).has_point(e.position):
				_present(str(_tags[i]))
	accept_event()


## A card put before the court.
func _present(tag: String) -> void:
	if tag == "" or _phase != "claims":
		return
	var c: Dictionary = claims[_i]
	var want: Array = c["answers"]
	if not tag in want:
		_patience -= 1
		_say_who = L({"en": "The judge", "ta": "நீதிபதி"})
		_say = L({"en": "Counsel, how is that relevant to this point?", "ta": "வழக்கறிஞரே, இந்த விஷயத்துக்கு இது எப்படி பொருந்தும்?"})
		print("COURT %d: %s doesn't answer it (patience %d)" % [_i, tag, _patience])
		if _patience <= 0:
			_say = L({"en": "Move on. The court will note the point stands.", "ta": "அடுத்தது. இந்த விஷயம் நிக்குதுன்னு கோர்ட் குறிச்சுக்கும்."})
			_next_claim(false)
		return
	if tag in _given:
		return
	_given.append(tag)
	var honest := 0
	var bought := 0
	for tg in _given:
		if bool(evidence.get(tg, {}).get("paid", false)):
			bought += 1
		else:
			honest += 1
	if honest == 0:                                     # only bought: the defence of the other side
		_say_who = L({"en": "Public Prosecutor", "ta": "அரசு வழக்கறிஞர்"})
		_say = L({"en": "Objection! The accused paid for this. A fact bought at a gate walks on one leg.", "ta": "ஆட்சேபனை! இதுக்கு குற்றம் சாட்டப்பட்டவர் காசு குடுத்திருக்கார். கேட்ல வாங்கின உண்மை ஒரு கால்ல தான் நடக்கும்."})
		print("COURT %d: %s objected (bought)" % [_i, tag])
		return
	print("COURT %d: answered with %s" % [_i, tag])
	_say_who = L({"en": "Advocate Sundaram", "ta": "வக்கீல் சுந்தரம்"})
	_say = L(c["answer"])
	_next_claim(true)


func _next_claim(won: bool) -> void:
	if won:
		_won += 1
	_i += 1
	_given.clear()
	_patience = 3
	if _i >= claims.size():
		_phase = "replay"
		_t = 0.0
		return


# ---- drawing ----
func _card(i: int) -> Rect2:
	var vs := get_viewport_rect().size
	var cols := 4
	var w := (vs.x - 120.0) / cols
	return Rect2(60.0 + (i % cols) * w, 330.0 + floori(i / float(cols)) * 80.0, w - 12.0, 70.0)


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.16, 0.12, 0.09))                      # the court's teak, dim
	if _phase == "claims":
		_draw_claims(vs)
	else:
		_draw_replay(vs)
	draw_rect(Rect2(0, 0, vs.x, 56), Color(0.1, 0.07, 0.05))     # (over the map's edges)
	draw_string(font, Vector2(24, 36), L({"en": "Principal Sessions Court, Coimbatore  ·  S.C. No. 412  ·  State vs. Karthik M.", "ta": "முதன்மை அமர்வு நீதிமன்றம், கோவை  ·  வழக்கு எண் 412  ·  அரசு எதிர் கார்த்திக் ம."}),
		HORIZONTAL_ALIGNMENT_LEFT, vs.x - 48, 18, Color(0.95, 0.88, 0.7))


func _draw_claims(vs: Vector2) -> void:
	var c: Dictionary = claims[mini(_i, claims.size() - 1)]
	draw_string(font, Vector2(60, 100), L({"en": "The prosecution's case, point %d of %d", "ta": "அரசு தரப்பு வழக்கு, %d / %d"}) % [_i + 1, claims.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.72, 0.55))
	draw_multiline_string(font, Vector2(60, 136), L(c["claim"]), HORIZONTAL_ALIGNMENT_LEFT, vs.x - 120, 26, 3, Color(1, 0.97, 0.9))
	draw_rect(Rect2(60, 214, vs.x - 120, 100), Color(0, 0, 0, 0.3))
	draw_string(font, Vector2(76, 240), _say_who, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.8, 0.5))
	draw_multiline_string(font, Vector2(76, 266), _say if _say != L(c["claim"]) else L({"en": "Put your evidence before the court: click a card (or 1–9).", "ta": "சாட்சியத்த கோர்ட் முன்னாடி வைங்க (1–9)."}),
		HORIZONTAL_ALIGNMENT_LEFT, vs.x - 150, 17, 2, Color(1, 1, 1, 0.9))
	for i in _tags.size():
		var r := _card(i)
		var ev: Dictionary = evidence[_tags[i]]
		var used: bool = _tags[i] in _given
		draw_rect(r, Color(0.93, 0.89, 0.8) if not used else Color(0.75, 0.85, 0.7))
		draw_string(font, r.position + Vector2(10, 22), ("%d  " % (i + 1) if i < 9 else "") + L(ev.get("title", _tags[i])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 16, Color(0.12, 0.1, 0.08))
		draw_multiline_string(font, r.position + Vector2(10, 42), L(ev.get("body", "")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 12, 2, Color(0.3, 0.27, 0.22))
		if bool(ev.get("paid", false)):
			draw_string(font, r.position + Vector2(r.size.x - 62, 68), L({"en": "bought", "ta": "வாங்கியது"}), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.2, 0.1))


## The night on the map: the clock runs; his dot and the SUV's move between their moments.
func _draw_replay(vs: Vector2) -> void:
	var mins: float = minf(T0 + _t * (12.0 if skip else 3.0), T1) if _phase == "replay" else T1
	var keys := ["home", "hotel", "ashwin", "raghavan_house", "lawley_junction", "pudhur_vayal"]
	var box := Rect2()
	for k in keys:
		if places.has(k):
			var p := Vector2(float(places[k]["x"]), float(places[k]["z"]))
			box = Rect2(p, Vector2.ZERO) if box.size == Vector2.ZERO and box.position == Vector2.ZERO else box.expand(p)
	box = box.grow(1500.0)
	var area := Rect2(60, 80, vs.x - 120, vs.y - 200)
	var sc := minf(area.size.x / box.size.x, area.size.y / box.size.y)
	var off := area.get_center() - box.get_center() * sc
	draw_rect(area, Color(0.93, 0.91, 0.86))
	draw_set_transform(off, 0.0, Vector2(sc, sc))
	for cls in ["tertiary", "secondary", "primary", "trunk", "motorway"]:
		if map_segs.has(cls):
			draw_multiline(map_segs[cls], Color(0.75, 0.72, 0.65) if cls == "tertiary" else Color(0.9, 0.7, 0.35), 2.0 / sc)
	draw_set_transform(Vector2.ZERO)
	var bg := Color(0.16, 0.12, 0.09)                    # (the map's frame: what spills over is the court's teak again)
	draw_rect(Rect2(0, 56, vs.x, area.position.y - 56), bg)
	draw_rect(Rect2(0, area.end.y, vs.x, vs.y - area.end.y), bg)
	draw_rect(Rect2(0, area.position.y, area.position.x, area.size.y), bg)
	draw_rect(Rect2(area.end.x, area.position.y, vs.x - area.end.x, area.size.y), bg)
	var w2s := func(k: String) -> Vector2:
		return off + Vector2(float(places[k]["x"]), float(places[k]["z"])) * sc
	for k in keys:
		if places.has(k):
			var at: Vector2 = w2s.call(k)
			draw_circle(at, 5.0, Color(0.2, 0.2, 0.2))
			draw_string(font, at + Vector2(8, -6), L(places[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.15, 0.15, 0.15))
	_track(KARTHIK, mins, w2s, Color(0.15, 0.45, 0.9), L({"en": "Karthik", "ta": "கார்த்திக்"}))
	_track(SUV, mins, w2s, Color(0.85, 0.2, 0.15), L({"en": "The white SUV", "ta": "வெள்ள எஸ்யூவி"}))
	var m := int(mins)
	draw_rect(Rect2(area.position + Vector2(12, 12), Vector2(200, 40)), Color(0, 0, 0, 0.7))
	draw_string(font, area.position + Vector2(24, 40), "%d:%02d PM" % [(m / 60) - 12, m % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	var said := L({"en": "Sundaram: \"At 10:12 the SUV is on Lawley Road. At 10:20 my client is at a door in Saravanampatti, on camera. Twelve kilometres apart. He could not be both.\"",
		"ta": "சுந்தரம்: \"10:12-க்கு எஸ்யூவி லாலி ரோட்டுல. 10:20-க்கு என் கட்சிக்காரர் சரவணம்பட்டியில ஒரு வாசல்ல, கேமராவுல. பன்னிரண்டு கிலோமீட்டர் இடைவெளி. ரெண்டு இடத்துலயும் இருக்க முடியாது.\""})
	draw_multiline_string(font, Vector2(60, vs.y - 96), said, HORIZONTAL_ALIGNMENT_LEFT, vs.x - 120, 17, 3, Color(1, 0.95, 0.85))
	if _phase == "done":
		draw_string(font, Vector2(60, vs.y - 24), L({"en": "Enter: the court rises", "ta": "Enter: நீதிமன்றம் எழுகிறது"}), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.8, 0.6))


func _track(path: Array, mins: float, w2s: Callable, col: Color, who: String) -> void:
	var pts := PackedVector2Array()
	var at := Vector2.INF
	for i in path.size():
		if not places.has(path[i][1]):
			continue
		var p: Vector2 = w2s.call(str(path[i][1]))
		if float(path[i][0]) <= mins:
			pts.append(p)
			at = p
			var tag := str(path[i][2])
			draw_string(font, p + Vector2(8, 14), "%s %s" % [tag, "✓" if evidence.has(tag) or tag == "E02" else "?"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		elif i > 0 and float(path[i - 1][0]) <= mins and places.has(path[i - 1][1]):
			var a: Vector2 = w2s.call(str(path[i - 1][1]))
			var k := (mins - float(path[i - 1][0])) / (float(path[i][0]) - float(path[i - 1][0]))
			at = a.lerp(p, k)
			pts.append(at)
	if pts.size() >= 2:
		draw_polyline(pts, col, 3.0)
	if at != Vector2.INF:
		draw_circle(at, 9.0, col)
		draw_string(font, at + Vector2(12, 4), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.darkened(0.3))
