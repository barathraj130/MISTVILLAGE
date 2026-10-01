extends RefCounted
## The living-world rules: clock, weather, wallet and fuel, opening hours and the save file.
## Pure state and arithmetic; drive_game.gd turns it into sky, rain, HUD and prompts.
## Money is play money in rupees: nothing here touches real payments or bank details.

const SAVE_PATH := "user://savegame.json"
const MINUTES_PER_SECOND := 0.1    # 1 real minute = 6 game minutes, a day lasts 4 real hours
const START_MINUTE := 6.0 * 60.0 + 30.0
const START_MONEY := 25000
const TANK_L := 60.0               # XUV700-class diesel tank
const START_FUEL := 0.3            # of the tank: enough to reach Mettupalayam and think about filling up
const LOW_FUEL := 0.12
const DIESEL_RS := 94.0            # per litre, close to the real Tamil Nadu pump price

## sky cover, rain, extra fog, tyre grip; blended over a couple of real minutes
const WEATHER := {
	"clear":  {"cloud": 0.05, "rain": 0.0, "fog": 0.0, "grip": 1.0, "label": "Clear"},
	"cloudy": {"cloud": 0.65, "rain": 0.0, "fog": 0.1, "grip": 1.0, "label": "Cloudy"},
	"rain":   {"cloud": 0.95, "rain": 1.0, "fog": 0.35, "grip": 0.72, "label": "Rain"},
	"mist":   {"cloud": 0.55, "rain": 0.0, "fog": 1.0, "grip": 0.92, "label": "Mist"},
}
## which weather can follow which, with weights; the hills get mist and showers more often
const NEXT_PLAINS := {"clear": {"clear": 5, "cloudy": 3}, "cloudy": {"clear": 3, "cloudy": 2, "rain": 2},
	"rain": {"cloudy": 3, "rain": 1}, "mist": {"cloudy": 2, "clear": 2}}
const NEXT_HILLS := {"clear": {"clear": 3, "cloudy": 3, "mist": 2}, "cloudy": {"clear": 2, "cloudy": 2, "rain": 3, "mist": 3},
	"rain": {"cloudy": 2, "mist": 3, "rain": 1}, "mist": {"mist": 2, "cloudy": 3, "rain": 1}}

## opening hours in minutes of the day [open, close]; anything not listed never shuts
const HOURS := {
	"Petrol bunk": [300, 1380], "Restaurant": [420, 1380], "Café": [420, 1320], "Bank": [600, 960],
	"Market": [360, 1260], "School": [510, 990], "College": [540, 1020], "Cinema": [600, 1440],
	"Theatre": [600, 1380], "Museum": [600, 1020], "Town hall": [600, 1050], "Temple": [330, 1260],
	"Viewpoint": [360, 1140],
}

var minute := START_MINUTE         # minute of the day
var day := 1
var money := START_MONEY
var fuel := START_FUEL * TANK_L    # litres
var weather := "clear"
var wx := {}                       # the blended weather now: cloud, rain, fog, grip
var wet := 0.0                     # how soaked the roads are: soaks in minutes, dries in an hour
var distance_scale := 1.0          # real metres per game metre (the map is compressed)
var _wx_left := 0.0                # game minutes until the weather may change
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	wx = WEATHER[weather].duplicate()
	_wx_left = _rng.randf_range(40.0, 90.0)


func advance(delta: float, altitude: float) -> void:
	minute += delta * MINUTES_PER_SECOND
	if minute >= 1440.0:
		minute -= 1440.0
		day += 1
	_wx_left -= delta * MINUTES_PER_SECOND
	if _wx_left <= 0.0:
		var table: Dictionary = (NEXT_HILLS if altitude > 1100.0 else NEXT_PLAINS)[weather]
		weather = _pick(table)
		_wx_left = _rng.randf_range(25.0, 80.0)
	var gm := delta * MINUTES_PER_SECOND
	wet = minf(wet + gm / 8.0, 1.0) if wx.get("rain", 0.0) > 0.3 else maxf(wet - gm / 60.0, 0.0)
	var target: Dictionary = WEATHER[weather]
	var k := 1.0 - exp(-delta / 40.0)
	for key in ["cloud", "rain", "fog", "grip"]:
		wx[key] = lerpf(wx[key], target[key], k)


func _pick(table: Dictionary) -> String:
	var total := 0
	for k in table:
		total += table[k]
	var r := _rng.randi_range(1, total)
	for k in table:
		r -= table[k]
		if r <= 0:
			return k
	return table.keys()[0]


## Diesel burnt this frame from pedal and revs: ~0.8 L/h idling, ~10 km/L cruising, much more
## climbing the ghat. Scaled by the map compression so the tank drains as over the real 73 km.
func burn(delta: float, pedal: float, rpm: float) -> void:
	var lph := 0.8 + 30.0 * pedal * rpm / 4000.0
	fuel = maxf(fuel - lph / 3600.0 * delta * distance_scale, 0.0)


func fuel_frac() -> float:
	return fuel / TANK_L


func fill_cost() -> int:
	return int(ceil((TANK_L - fuel) * DIESEL_RS))


## Fill up with what you can afford. Returns litres bought.
func refuel() -> float:
	var litres := minf(TANK_L - fuel, float(money) / DIESEL_RS)
	if litres < 0.5:
		return 0.0
	money -= int(ceil(litres * DIESEL_RS))
	fuel += litres
	return litres


func is_open(kind: String) -> bool:
	if not HOURS.has(kind):
		return true
	var h: Array = HOURS[kind]
	return minute >= h[0] and minute < h[1]


func hours_text(kind: String) -> String:
	if not HOURS.has(kind):
		return "Open 24 hours"
	var h: Array = HOURS[kind]
	return "%s – %s" % [clock_text(h[0]), clock_text(h[1])]


static func clock_text(m: float) -> String:
	var mm := int(m) % 1440
	return "%02d:%02d" % [mm / 60, mm % 60]


## Sun direction for the Nilgiris (11° N): rises in the east (+X), sets in the west, leaning
## south (+Z). y < 0 means night.
func sun_dir() -> Vector3:
	var h := (minute - 735.0) / 720.0 * PI          # solar noon ≈ 12:15 IST here
	return Vector3(-sin(h), cos(h) * 0.97, cos(h) * 0.24 + 0.05).normalized()


func daylight() -> float:
	return smoothstep(-0.10, 0.18, sun_dir().y)


# ----------------------------------------------------------------------------- save / load
func save(extra: Dictionary) -> void:
	var data := {"minute": minute, "day": day, "money": money, "fuel": fuel, "weather": weather,
		"saved_at": Time.get_datetime_string_from_system()}
	data.merge(extra)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Restores the shared state and returns the whole file so the game can take its own parts.
func load_save() -> Dictionary:
	if not has_save():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	minute = float(data.get("minute", minute))
	day = int(data.get("day", day))
	money = int(data.get("money", money))
	fuel = clampf(float(data.get("fuel", fuel)), 0.0, TANK_L)
	weather = String(data.get("weather", weather))
	if not WEATHER.has(weather):
		weather = "clear"
	wx = WEATHER[weather].duplicate()
	return data
