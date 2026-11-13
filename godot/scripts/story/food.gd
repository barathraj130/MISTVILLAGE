extends RefCounted
## The food data (story/food.json): dishes, Amma's cooking by the day, the eateries' menus.
##   dish(id)                     → its entry ({en, ta, desc, energy})
##   home_meal(day, slot)         → {dish, amma: {en, ta}}: the same on the same day (a loaded save serves the same),
##                                  a different one the next (slot: breakfast, lunch, dinner)
##   slot_at(minute)              → which meal the hour is for
##   menu(eatery)                 → [{cat, items: [[dish, price]]}] or [] (then the step's own menu stands)

const PATH := "res://story/food.json"
static var _d := {}


static func data() -> Dictionary:
	if _d.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_d = j if j is Dictionary else {"dishes": {}, "home": {}, "eateries": {}, "categories": {}}
	return _d


static func dish(id: String) -> Dictionary:
	return data()["dishes"].get(id, {"en": id.capitalize(), "ta": id, "energy": 40})


static func name_of(id: String, lang: String) -> String:
	return str(dish(id).get(lang, dish(id).get("en", id)))


static func slot_at(minute: float) -> String:
	var h := fmod(minute, 1440.0) / 60.0
	return "breakfast" if h < 11.0 else ("lunch" if h < 16.5 else "dinner")


## Each meal's rotation turns once a day; the three are offset so the same dish isn't breakfast and dinner today.
static func home_meal(day: int, slot: String) -> Dictionary:
	var rot: Array = data()["home"].get(slot, [])
	if rot.is_empty():
		return {"dish": "home_meals", "amma": {"en": "Come and eat.", "ta": "வந்து சாப்பிடு."}}
	var off: int = {"breakfast": 0, "lunch": 2, "dinner": 3}.get(slot, 0)   # (dinner never the same as that day's breakfast or the next)
	return rot[posmod(day - 1 + off, rot.size())]


static func menu(eatery: String) -> Array:
	return data()["eateries"].get(eatery, {}).get("menu", [])


static func kind_of(eatery: String, lang: String) -> String:
	var k: Dictionary = data()["eateries"].get(eatery, {}).get("kind", {})
	return str(k.get(lang, k.get("en", "")))


static func category(cat: String, lang: String) -> String:
	var c: Dictionary = data()["categories"].get(cat, {})
	return str(c.get(lang, c.get("en", cat.capitalize())))
