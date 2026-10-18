extends RefCounted
## Traffic fines in the city: the shared play-money wallet (scripts/drive/sim.gd, ₹ play money, the same save
## file as the mountain drive) and a log of e-challans. A camera at a junction issues a challan (unpaid until
## a police check collects it, or you pay); a police check fines on the spot.
##
## Cameras are fixed, not random: a junction either has a red-light camera / a speed camera or it doesn't
## (decided from its position), so a driver can learn where they are.

const Sim := preload("res://scripts/drive/sim.gd")
const RED_LIGHT := 1000
const OVERSPEED := 1000
const SKIP_CHECK := 2000
const CITY_LIMIT_KMH := 50.0

var sim: Sim = Sim.new()
var challans: Array = []          # [{"what", "amount", "day", "time"}] unpaid
var persist := false              # write the save file (only when a person is playing, not in tests)
var _save_data := {}              # everything else in the save file (the mountain drive's own keys) kept as is


func load_wallet() -> void:
	_save_data = sim.load_save()
	challans = []
	for c in _save_data.get("challans", []):
		if c is Dictionary:
			challans.append(c)


func save() -> void:
	if not persist:
		return
	var extra := _save_data.duplicate()
	extra["challans"] = challans
	sim.save(extra)                  # the wallet keys come from sim; other games' keys ride along unchanged


func owed() -> int:
	var t := 0
	for c in challans:
		t += int(c["amount"])
	return t


## A camera caught it: logged, to be paid later.
func challan(what: String, amount: int) -> void:
	challans.append({"what": what, "amount": amount, "day": sim.day, "time": Sim.clock_text(sim.minute)})
	save()


## Pay now from the wallet (a police check); returns what was actually paid (the wallet can't go below zero —
## what can't be paid stays owed).
func pay(amount: int) -> int:
	var paid := mini(amount, maxi(sim.money, 0))
	sim.money -= paid
	save()
	return paid


## Settle every logged challan the wallet can cover; returns [count settled, total paid].
func settle_challans() -> Array:
	var n := 0
	var total := 0
	var left: Array = []
	for c in challans:
		var amt := int(c["amount"])
		if sim.money >= amt:
			sim.money -= amt
			total += amt
			n += 1
		else:
			left.append(c)
	challans = left
	save()
	return [n, total]


## Does this junction (a signal head at p) have a red-light camera (about 70 %) / a speed camera (about 35 %)?
static func has_red_camera(p: Vector3) -> bool:
	return _hash(p, 1.7) < 0.7


static func has_speed_camera(p: Vector3) -> bool:
	return _hash(p, 5.3) < 0.35


static func _hash(p: Vector3, salt: float) -> float:
	# by junction (≈ 60 m cell), so every head at a junction agrees
	var jx := floorf(p.x / 60.0)
	var jz := floorf(p.z / 60.0)
	return fposmod(sin(jx * 12.9898 + jz * 78.233 + salt) * 43758.5453, 1.0)


## Indian grouping: 1,23,456
static func rupees(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	if s.length() > 3:
		var head := s.substr(0, s.length() - 3)
		var out := s.substr(s.length() - 3)
		while head.length() > 2:
			out = head.substr(head.length() - 2) + "," + out
			head = head.substr(0, head.length() - 2)
		s = head + "," + out
	return ("-" if neg else "") + "₹" + s
