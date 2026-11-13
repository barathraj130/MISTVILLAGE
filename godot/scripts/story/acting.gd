extends Node
## People acting while they talk (story/emotions.json): whoever speaks a line and whoever hears it, cast or crowd,
## Karthik too. For each line: the speaker shows its feeling (the line's "emotion" and "intensity", else neutral):
## its gestures by turns with Talk (crowd_clips.gd's library on any of the game rig's people: an argument's open
## hands, a shrug, a laugh, pointing the way...), its face where the model has one (face.gd: the feeling's units,
## the mouth moving with the words, blinks), the head on whoever they speak to (head_look.gd, the feeling's
## attitude: looking down, glancing away, a tilt). The others listen: looking at the speaker, now and then a nod, the
## South Indian wobble, a shake of the head or a laugh, as the feeling has it. A line may name a "gesture" (namaste,
## wave, point, shrug, laugh, argue, shake, nod, wobble) for its start, and "to" for whom it's said to. Seated people
## keep their seat (no standing gestures): only the head and face. When the talk is over: stop(), each back to the
## clip they had. Cheap: a handful of people at most, nothing far off.
##   line(line, people)   people: who → their node (a story actor, the walker)
##   stop()

const CrowdClips := preload("res://scripts/city/crowd_clips.gd")
const Face := preload("res://scripts/story/face.gd")
const HeadLook := preload("res://scripts/story/head_look.gd")
const WOMEN := ["amma", "divya", "selvi"]

static var _data := {}
var _who := {}                                         # key → {node, anim, base, look, face, seated, t, cur}
var _speaker := ""
var _line := {}
var _emotion := "neutral"
var _k := 0.7
var _t := 0.0


static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://story/emotions.json"))
		_data = j if j is Dictionary else {"emotions": {"neutral": {"talk": ["Talk"], "listen": ["Idle"]}}, "gestures": {}, "intensity": {}}
	return _data


func _person(key: String, node: Node3D) -> Dictionary:
	if _who.has(key) and is_instance_valid(_who[key]["node"]) and _who[key]["node"] == node:
		return _who[key]
	var model: Node3D = node.get("model") if node.get("model") else node
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	var p := {"node": node, "model": model, "anim": ap, "base": (ap.current_animation if ap else ""), "look": null, "face": null,
		"t": 0.0, "cur": ""}
	if sks.is_empty() or ap == null:
		_who[key] = p
		return p
	CrowdClips.add(model, "w" if key in WOMEN or key.begins_with("w") else "m")
	var hl: HeadLook = (sks[0] as Node).get_node_or_null("HeadLook")
	if hl == null:
		hl = HeadLook.new()
		hl.name = "HeadLook"
		sks[0].add_child(hl)
	p["look"] = hl
	var f := Face.new(model)
	p["face"] = f if f.has_face() else null
	_who[key] = p
	return p


## A listener's feeling: their own (standing.gd's mood toward Karthik), else the line's when it's said to them,
## else neutral.
func _listening(key: String) -> Dictionary:
	var em: Dictionary = data()["emotions"]
	if _moods.has(key) and em.has(_moods[key]):
		return em[_moods[key]]
	if key == str(_line.get("to", "")):
		return em.get(_emotion, em["neutral"])
	return em["neutral"]


func _seated(p: Dictionary) -> bool:
	var n: Node = p["node"]
	if n.get("seated") != null:
		return bool(n.get("seated"))
	return str(p["base"]).begins_with("Sit")


func _play(p: Dictionary, clip: String, blend := 0.35) -> void:
	var ap: AnimationPlayer = p["anim"]
	if ap == null:
		return
	if _seated(p):                                       # (in a chair: the chair's own talk and rest)
		clip = "SitTalk" if clip != "Idle" and not clip.begins_with("crowd/Nod") else str(p["base"])
	if not ap.has_animation(clip):
		clip = "Talk" if clip != "Idle" and ap.has_animation("Talk") else str(p["base"]) if ap.has_animation(str(p["base"])) else "Idle"
	if p["cur"] != clip:
		ap.play(clip, blend)
		p["cur"] = clip


var _thought := false                                  # this line is a thought or an action (no speech)
var _moods := {}                                       # who → their own feeling while listening (standing.gd's mood)


func line(ln: Dictionary, people: Dictionary, moods := {}) -> void:
	_moods = moods
	_line = ln
	_speaker = str(ln.get("who", ""))
	_emotion = str(ln.get("emotion", "neutral"))
	if not data()["emotions"].has(_emotion):
		_emotion = "neutral"
	_k = float(data()["intensity"].get(str(ln.get("intensity", "medium")), 0.7))
	_t = 0.0
	var en := str(ln.get("en", "")).strip_edges()       # a line wholly in brackets is a thought or an action, not words:
	_thought = en.begins_with("(") and en.ends_with(")") and en.count("(") == 1   # no talking, no lips
	for key in people:
		if is_instance_valid(people[key]):
			_person(str(key), people[key])
	var e: Dictionary = data()["emotions"][_emotion]
	for key in _who:
		var p: Dictionary = _who[key]
		if not is_instance_valid(p["node"]) or not people.has(key):
			continue
		p["t"] = randf_range(0.6, 1.6)
		if key == _speaker and _thought:                 # thinking: still, the feeling only
			_play(p, "Idle")
		elif key == _speaker:
			var g := str(ln.get("gesture", ""))
			_play(p, str(data()["gestures"].get(g, e["talk"][0])) if g != "" else str(e["talk"][0]))
			if g != "":
				p["t"] = 2.4                             # (the named gesture, then on to talking)
		else:
			_play(p, "Idle")


func stop() -> void:
	for key in _who:
		var p: Dictionary = _who[key]
		if not is_instance_valid(p["node"]):
			continue
		if p["look"]:
			(p["look"] as HeadLook).weight = 0.0
		if p["face"]:
			(p["face"] as Face).pose({})
		var ap: AnimationPlayer = p["anim"]
		if ap and p["base"] != "" and ap.has_animation(str(p["base"])):
			ap.play(str(p["base"]), 0.4)
		p["cur"] = ""
	_who.clear()
	_speaker = ""


func _process(dt: float) -> void:
	if _who.is_empty():
		return
	_t += dt
	var e: Dictionary = data()["emotions"][_emotion]
	var to := str(_line.get("to", ""))
	var sp: Dictionary = _who.get(_speaker, {})
	for key in _who:
		var p: Dictionary = _who[key]
		if not is_instance_valid(p["node"]):
			continue
		var speaking: bool = key == _speaker and not _thought
		# where they look: the speaker at whom it's said to (else the nearest other), the rest at the speaker
		var at := Vector3.INF
		if speaking:
			var best := INF
			for k2 in _who:
				if k2 == key or not is_instance_valid(_who[k2]["node"]):
					continue
				var d: float = (_who[k2]["node"] as Node3D).global_position.distance_to((p["node"] as Node3D).global_position)
				if k2 == to:
					d = -1.0
				if d < best:
					best = d
					at = (_who[k2]["node"] as Node3D).global_position + Vector3.UP * 1.55
		elif not sp.is_empty() and is_instance_valid(sp["node"]):
			at = (sp["node"] as Node3D).global_position + Vector3.UP * 1.55
		var hl: HeadLook = p["look"]
		if hl:
			hl.target = at
			hl.weight = 0.85
			var mine: Dictionary = e if speaking else _listening(key)
			hl.pitch = float(mine.get("pitch", 0)) * _k
			hl.tilt = float(mine.get("tilt", 0)) * _k
			if p.get("glance_t", 0.0) <= 0.0:          # a glance away now and then (more for the nervous, the sad)
				p["glance_t"] = randf_range(1.5, 4.0)
				var away := randf() < float(mine.get("glance", 0.1))
				hl.away = (float(mine.get("away", 0)) + 14.0) * (1.0 if randf() < 0.5 else -1.0) * _k if away else 0.0
			p["glance_t"] = float(p["glance_t"]) - dt
		# the body: by turns, as the feeling has it
		p["t"] = float(p["t"]) - dt
		if p["t"] <= 0.0:
			var opts: Array = e["talk"] if speaking else _listening(key)["listen"]
			var clip: String = opts[randi() % opts.size()]
			if speaking and randf() < 0.55:
				clip = "Talk"                          # (mostly just talking; the gestures come and go)
			_play(p, clip)
			p["t"] = randf_range(2.2, 4.0) if clip.begins_with("crowd/") else randf_range(1.6, 3.2)
			if not speaking and clip.begins_with("crowd/"):
				p["t"] = 1.8                             # (a nod is brief: then still again, listening)
		var f: Face = p["face"]
		if f:
			var faceu: Dictionary = {}
			var mine2: Dictionary = e if speaking else _listening(key)
			for u in mine2.get("face", {}):
				faceu[u] = float(mine2["face"][u]) * _k
			if speaking:                                 # the mouth with the words (syllables, unevenly)
				var s := absf(sin(_t * 9.0 + sin(_t * 2.3) * 2.0)) * (0.6 + 0.4 * sin(_t * 1.7))
				faceu["mouth-open"] = float(faceu.get("mouth-open", 0.0)) + 0.14 * s
			f.speed = 14.0 if speaking else 6.0
			f.pose(faceu)
			f.update(dt)
