extends RefCounted
## The player's settings beside the graphics (graphics.gd keeps [graphics]), all in user://settings.cfg:
##   [audio] master        the overall volume, 0–1 (the Master bus)
##   [controls] look_sens  mouse look, a share of the usual (0.5–2): on foot in the city, the cockpit, the resort
##   [driving] steer_sens  the jeep's steering (0.4–1.5; [ and ] change it while driving, drive_game.gd)
##   [game] lang           "auto" (the computer's language), "en" or "ta": what the story starts in (T still switches)
## The settings screen (ui/settings_screen.gd) changes them; everything else only reads.

const CFG := "user://settings.cfg"

static var _cache := {}


static func get_value(section: String, key: String, default):
	var k := section + "/" + key
	if _cache.has(k):
		return _cache[k]
	var cf := ConfigFile.new()
	var v = cf.get_value(section, key, default) if cf.load(CFG) == OK else default
	_cache[k] = v
	return v


## One value into settings.cfg, keeping everything else in it.
static func set_value(section: String, key: String, v) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value(section, key, v)
	cf.save(CFG)
	_cache[section + "/" + key] = v


static func look() -> float:
	return float(get_value("controls", "look_sens", 1.0))


## The story's starting language: the saved choice, else the computer's.
static func lang() -> String:
	var l := str(get_value("game", "lang", "auto"))
	if l in ["en", "ta"]:
		return l
	return "ta" if OS.get_locale_language() == "ta" else "en"


static func apply_audio() -> void:
	var v := clampf(float(get_value("audio", "master", 1.0)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)
