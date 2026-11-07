extends RefCounted
## Where Karthik stands (the player's consequences across Part 1), one place for all of it, built on what the game
## already keeps rather than beside it:
##   suspicion    the inspector's (0..100): bail.gd's own, which the signings, lates, strikes and the border move
##   reputation   what Coimbatore says of him (0..100, from 50): the neighbours, the street, the papers
##   trust        each witness's in him (key → 0..100, from 50): Muniyandi, Ganesan, Joseph, Bala, Priya, Selvi...
##   compliance   how he keeps his bail (0..100): from bail.gd's strikes and lates, not kept separately
##   pressure     how hard money presses (0..100): from money.gd's bills due in three days against his wallet
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
	return float(trust.get(key, 50.0))


func value(name: String) -> float:
	if name.begins_with("trust."):
		return trust_of(name.substr(6))
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
	return {"reputation": reputation, "trust": trust, "applied": applied, "noticed": noticed}


## A save's standing; one from before there was any: its flags replayed instead (suspicion is bail's, already saved,
## so a replay leaves it be).
func load(d, flags: Dictionary) -> void:
	if d is Dictionary and not d.is_empty():
		reputation = float(d.get("reputation", 50.0))
		trust = d.get("trust", {})
		applied = d.get("applied", [])
		noticed = d.get("noticed", [])
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
