extends RefCounted
## Where Karthik stands (the player's consequences across Part 1), one place for all of it, built on what the game
## already keeps rather than beside it:
##   suspicion    the inspector's (0..100): bail.gd's own, which the signings, lates, strikes and the border move
##   reputation   what Coimbatore says of him (0..100, from 50): the neighbours, the street, the papers
##   trust        each witness's in him (key → 0..100, from 50): Muniyandi, Ganesan, Joseph, Bala, Priya, Selvi...
##   compliance   how he keeps his bail (0..100): from bail.gd's strikes and lates, not kept separately
##   pressure     how hard money presses (0..100): from money.gd's bills due in three days against his wallet
##   people       each person's feelings toward him besides trust (key → familiarity, respect, fear, suspicion,
##                anger, 0..100), from story/relations.json (strangers: familiarity 0, the rest low), and what they
##                remember of him (the last few things, with the day). Talking with him makes him familiar; the
##                table's "people" and a line's "feel" move the rest. mood(key) is how they carry themselves with him
##                (acting.gd), greeting(key) how they greet him. A feeling is never evidence of anything.
## The story's "standing" table (slice.json) says what each of its flags does to these, once, the first time the
## flag is true (a bribe, a grab, an honest way): settle() applies the new ones. Old saves have no standing: their
## flags are replayed (the same table, so the same numbers). Story steps may ask "if_standing": {"suspicion": ">=40",
## "trust.muniyandi": "<30"} and are skipped unless it holds; "notice" lines (the table's "notices") are sent the
## first time a value crosses its mark (Selvi's text when the inspector's suspicion passes 60).

var city
var table := {}                     # flag → {"suspicion": n, "reputation": n, "trust": {key: n}}
var notices: Array = []             # [{"value", "at", "from": {en, ta}, "text": {en, ta}}]
var reputation := 50.0
var trust := {}
var applied: Array = []             # the flags already counted
var noticed: Array = []             # the notices already sent (their index)
var people := {}                     # key → {familiarity, respect, fear, suspicion, anger} (trust: `trust`)
var memory := {}                     # key → [{"day", "what"}], the last 8
var _start := {}                     # story/relations.json
const FEELINGS := ["familiarity", "respect", "fear", "suspicion", "anger"]


func setup(c, data: Dictionary) -> void:
	city = c
	table = data.get("standing", {})
	notices = data.get("standing_notices", [])


func suspicion() -> float:
	return float(city.bail.suspicion) if city and city.bail else 30.0


func compliance() -> float:
	if city == null or city.bail == null:
		return 100.0
	return clampf(100.0 - 30.0 * float(city.bail.strikes.size()) - 5.0 * float(city.bail.lates), 0.0, 100.0)


func pressure() -> float:
	if city == null or city.money == null or city.fines == null:
		return 0.0
	var today: int = city.fines.sim.day
	var soon := 0
	var overdue := false
	for b in city.money.bills:
		if b.get("paid", false):
			continue
		var due := int(b.get("due", today))
		if due <= today + 3:
			soon += int(b.get("amount", 0))
			overdue = overdue or due < today
	if soon <= 0:
		return 0.0
	var short := clampf(float(soon - city.fines.sim.money) / float(soon), 0.0, 1.0) * 80.0
	return clampf(short + (20.0 if overdue else 0.0), 0.0, 100.0)


func trust_of(key: String) -> float:
	return float(trust.get(key, float(_starting().get(key, {}).get("trust", 50.0))))


func _starting() -> Dictionary:
	if _start.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://story/relations.json")) if FileAccess.file_exists("res://story/relations.json") else null
		_start = j.get("people", {}) if j is Dictionary else {}
	return _start


## How one feels about him (a feeling of FEELINGS): what's happened since, else where they started.
func feeling(key: String, name: String) -> float:
	if people.has(key) and people[key].has(name):
		return float(people[key][name])
	var st: Dictionary = _starting().get(key, {})
	return float(st.get(name, 0.0 if name == "familiarity" else (30.0 if name == "suspicion" else 20.0)))


func feel(key: String, name: String, by: float, why := "") -> void:
	if name == "trust":
		trust[key] = clampf(trust_of(key) + by, 0.0, 100.0)
	elif name in FEELINGS:
		if not people.has(key):
			people[key] = {}
		people[key][name] = clampf(feeling(key, name) + by, 0.0, 100.0)
	if why != "":
		remember(key, why)


func remember(key: String, what: String) -> void:
	var day: int = city.fines.sim.day if city and city.fines else 1
	var m: Array = memory.get(key, [])
	if not m.is_empty() and m[-1]["what"] == what and int(m[-1]["day"]) == day:
		return
	m.append({"day": day, "what": what})
	memory[key] = m.slice(maxi(m.size() - 8, 0))


## He talked with them today: a little more familiar (once a day), and remembered.
func met(key: String) -> void:
	if key == "karthik" or key == "":
		return
	var day: int = city.fines.sim.day if city and city.fines else 1
	for e in memory.get(key, []):
		if int(e["day"]) == day and e["what"] == "talked":
			return
	feel(key, "familiarity", 6.0 if feeling(key, "familiarity") < 50.0 else 2.0, "talked")
	print("STANDING met %s: familiarity %.0f, trust %.0f, mood %s" % [key, feeling(key, "familiarity"), trust_of(key), mood(key)])


## How they carry themselves with him, from how they feel (acting.gd's feelings): the strongest wins.
func mood(key: String) -> String:
	var anger := feeling(key, "anger")
	var susp := feeling(key, "suspicion")
	var fear := feeling(key, "fear")
	var t := trust_of(key)
	var fam := feeling(key, "familiarity")
	if anger >= 60.0:
		return "angry"
	if fear >= 60.0:
		return "nervous"
	if susp >= 60.0:
		return "suspicious"
	if anger >= 35.0:
		return "frustrated"
	if t >= 70.0 and fam >= 60.0:
		return "relaxed"
	if fam < 15.0:
		return "respectful" if feeling(key, "respect") >= 35.0 else "neutral"
	return "neutral"


## How they greet him: namaste for an elder or a stranger who respects him, a wave or the wobble for the familiar,
## a nod otherwise; nothing from the angry.
func greeting(key: String) -> String:
	if feeling(key, "anger") >= 50.0:
		return ""
	if bool(_starting().get(key, {}).get("elder", false)) or (feeling(key, "familiarity") < 20.0 and feeling(key, "respect") >= 40.0):
		return "namaste"
	if feeling(key, "familiarity") >= 60.0 and trust_of(key) >= 60.0:
		return "wave" if randf() < 0.4 else "wobble"
	if feeling(key, "familiarity") >= 25.0 and trust_of(key) >= 50.0 and not key in ["amma", "divya", "selvi", "priya", "meenakshi", "lakshmi"]:
		return "handshake"                               # (a man he knows a little, at work)
	return "nod"


func value(name: String) -> float:
	if name.begins_with("trust."):
		return trust_of(name.substr(6))
	for f in FEELINGS:                                   # (familiarity.raghavan, anger.murugesan...)
		if name.begins_with(f + "."):
			return feeling(name.substr(f.length() + 1), f)
	match name:
		"suspicion":
			return suspicion()
		"reputation":
			return reputation
		"compliance":
			return compliance()
		"pressure":
			return pressure()
	return 0.0


## Count the flags that have come true since last time; returns the notices now due ([{from, text}]).
func settle(flags: Dictionary) -> Array:
	for f in table:
		if flags.get(f, false) and not f in applied:
			_apply(f, table[f])
	var out: Array = []
	for i in notices.size():
		var n: Dictionary = notices[i]
		if i in noticed:
			continue
		if _holds(value(str(n["value"])), str(n["at"])):
			noticed.append(i)
			out.append(n)
	return out


func _apply(flag: String, e: Dictionary) -> void:
	applied.append(flag)
	if e.has("suspicion") and city and city.bail:
		city.bail.suspicion = clampf(city.bail.suspicion + float(e["suspicion"]), 0.0, 100.0)
	if e.has("reputation"):
		reputation = clampf(reputation + float(e["reputation"]), 0.0, 100.0)
	for k in e.get("trust", {}):
		trust[k] = clampf(trust_of(str(k)) + float(e["trust"][k]), 0.0, 100.0)
	for k in e.get("people", {}):                        # the other feelings: {"murugesan": {"anger": 10}}
		for f in e["people"][k]:
			feel(str(k), str(f), float(e["people"][k][f]), flag)
	print("STANDING %s: suspicion %.0f · reputation %.0f · trust %s" % [flag, suspicion(), reputation, str(trust)])


## "if_standing": every condition holds ({"suspicion": ">=40", "trust.bala": "<30"}).
func allows(cond: Dictionary) -> bool:
	for k in cond:
		if not _holds(value(str(k)), str(cond[k])):
			return false
	return true


func _holds(v: float, test: String) -> bool:
	for op in [">=", "<=", ">", "<"]:
		if test.begins_with(op):
			var n := float(test.substr(op.length()))
			match op:
				">=":
					return v >= n
				"<=":
					return v <= n
				">":
					return v > n
				"<":
					return v < n
	return false


func save() -> Dictionary:
	return {"reputation": reputation, "trust": trust, "applied": applied, "noticed": noticed, "people": people, "memory": memory}


## A save's standing; one from before there was any: its flags replayed instead (suspicion is bail's, already saved,
## so a replay leaves it be).
func load(d, flags: Dictionary) -> void:
	if d is Dictionary and not d.is_empty():
		reputation = float(d.get("reputation", 50.0))
		trust = d.get("trust", {})
		applied = d.get("applied", [])
		noticed = d.get("noticed", [])
		people = d.get("people", {})
		memory = d.get("memory", {})
		return
	for f in table:
		if flags.get(f, false):
			applied.append(f)
			var e: Dictionary = table[f]
			if e.has("reputation"):
				reputation = clampf(reputation + float(e["reputation"]), 0.0, 100.0)
			for k in e.get("trust", {}):
				trust[k] = clampf(trust_of(str(k)) + float(e["trust"][k]), 0.0, 100.0)
	print("STANDING rebuilt from an old save's flags: %d" % applied.size())


func summary() -> String:
	return "suspicion %.0f · reputation %.0f · compliance %.0f · pressure %.0f · trust %s" % [suspicion(), reputation, compliance(), pressure(), str(trust)]
