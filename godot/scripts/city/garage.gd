extends Node
## The vehicles Karthik's family owns (docs/PROLOGUE_PLAN_2026-11-17.md): the old scooter, and what the prologue's
## dealership adds (a motorcycle; a scooter for Divya, or for him if the old one is traded in). Each has its own
## tank and consumption, odometer, condition and loan (finance.gd).
##   fuel       burnt by the distance actually ridden (km / km-per-litre), more under throttle, more when worn; a
##              little at idle. The cluster's gauge and running dry (jeep.gd fuel_frac, out_of_fuel) follow it.
##   condition  0..100: worn by the km and by crashes; under 60 the engine pulls less (jeep.gd torque_mul), and
##              a service or repair (service()) brings it back for what it costs.
##   loans      each instalment becomes a bill in money.gd a few days before it's due (kind "emi", "loan": the id),
##              so reminders and paying through Amma are money.gd's; paid, it's recorded here (finance.gd); missed,
##              a late charge rides on the bill, and three missed take the vehicle (paid back: dues + ₹3,000).
## Saved in the save file's "garage" (city.fines._save_data): vehicles, which one he's on, the loans.
## --financetest: the arithmetic and the save checked, printed, quit.

const Finance := preload("res://scripts/city/finance.gd")
const PETROL_PAISE := 10150          # ₹101.50 a litre (Coimbatore, 2026)
const POST_DAYS := 5                 # an instalment's bill arrives this many days before it's due
const RELEASE_FEE := 3000            # ₹ to get a seized vehicle back, beyond the dues

var city
var finance: Finance = Finance.new()
var vehicles: Array = []             # [{id, kind (jeep.gd SPECS), name {en, ta}, plate, rider ("karthik" | "divya"),
                                     #   tank_l, fuel_l, kmpl, odo_km, condition, loan, seized, bought_day, posted}]
var current := ""                    # the id of the one he's on ("" on foot or in someone else's vehicle)
var _last_kind := ""
var _base_torque := 1.0
var _log := "--fuellog" in OS.get_cmdline_user_args()   # (testing: the vehicle he's on, every 2 s)
var _log_t := 0.0

## What each kind holds and does (a 110 cc scooter's 5.3 L at ~50 km/l; a 125 cc commuter's 11 L at ~62 km/l).
const KINDS := {
	"karthik_scooter": {"tank_l": 5.0, "kmpl": 38.0},     # ten years old: thirstier
	"scooter": {"tank_l": 5.3, "kmpl": 50.0},
	"bike": {"tank_l": 11.0, "kmpl": 62.0},
}


func _ready() -> void:
	load_state(city.fines._save_data.get("garage", {}))
	if vehicles.is_empty():                          # a new game: the old scooter, on its old instalments (money.gd)
		add_vehicle({"id": "old_scooter", "kind": "karthik_scooter", "name": {"en": "the old scooter", "ta": "பழைய ஸ்கூட்டர்"},
			"plate": "TN 38 R 4471", "fuel_l": 2.1, "odo_km": 61240.0, "condition": 34.0})
	for arg in OS.get_cmdline_user_args():
		if arg == "--financetest":
			_test.call_deferred()


func load_state(d: Dictionary) -> void:
	vehicles = []
	for v in d.get("vehicles", []):
		if v is Dictionary:
			vehicles.append(v)
	current = str(d.get("current", ""))
	finance.load_data(d.get("loans", []))


func save() -> void:
	city.fines._save_data["garage"] = {"vehicles": vehicles, "current": current, "loans": finance.save_data()}
	city.fines.save()


func add_vehicle(v: Dictionary) -> Dictionary:
	var k: Dictionary = KINDS.get(str(v["kind"]), {"tank_l": 8.0, "kmpl": 40.0})
	var rec := {"id": str(v["id"]), "kind": str(v["kind"]), "name": v.get("name", {"en": str(v["id"])}), "plate": str(v.get("plate", "")),
		"rider": str(v.get("rider", "karthik")), "tank_l": float(v.get("tank_l", k["tank_l"])), "fuel_l": float(v.get("fuel_l", 1.0)),
		"kmpl": float(v.get("kmpl", k["kmpl"])), "odo_km": float(v.get("odo_km", 0.0)), "condition": float(v.get("condition", 100.0)),
		"loan": str(v.get("loan", "")), "seized": false, "bought_day": int(city.fines.sim.day), "paint": v.get("paint", null)}
	vehicles.append(rec)
	save()
	return rec


func vehicle(id: String) -> Dictionary:
	for v in vehicles:
		if str(v["id"]) == id:
			return v
	return {}


func by_kind(kind: String) -> Dictionary:
	if not current.is_empty():
		var c := vehicle(current)
		if str(c.get("kind", "")) == kind:
			return c
	for v in vehicles:
		if str(v["kind"]) == kind and not bool(v["seized"]):
			return v
	return {}


## A loan for vehicle id: price, down payment and trade-in in rupees (whole), the rate, the months.
func finance_vehicle(id: String, lender: String, price: int, down: int, trade_in: int, rate_pa: float, months: int) -> Dictionary:
	var ln := finance.open_loan("loan_" + id, id, lender, price * 100, down * 100, trade_in * 100, rate_pa, months, int(city.fines.sim.day))
	ln["posted"] = 0
	vehicle(id)["loan"] = ln["id"]
	save()
	return ln


# ---- each frame: the vehicle he's on ----
func _physics_process(dt: float) -> void:
	if city == null or city.car == null:
		return
	var car = city.car
	var kind := str(car.vehicle)
	if kind != _last_kind:                            # (a new vehicle configured: which of ours, if any)
		_last_kind = kind
		_base_torque = float(car.torque_mul)
		var v := by_kind(kind)
		current = str(v.get("id", ""))
		if not v.is_empty():
			car.fuel_frac = float(v["fuel_l"]) / float(v["tank_l"])
	if current.is_empty() or city.walker != null:
		return
	var v := vehicle(current)
	if v.is_empty():
		return
	var spd: float = absf(float(car.speed))
	var km := spd * dt / 1000.0
	var thr: float = float(car.pedal())
	var wear_k := 1.0 + maxf(0.0, 60.0 - float(v["condition"])) / 100.0    # (a worn engine drinks more)
	var litres := km / float(v["kmpl"]) * (0.8 + 0.5 * thr) * wear_k
	if spd < 0.5 and not bool(car.out_of_fuel):
		litres += 0.1 / 3600.0 * dt * Engine.time_scale    # idling: ~0.1 L an hour
	v["fuel_l"] = maxf(float(v["fuel_l"]) - litres, 0.0)
	v["odo_km"] = float(v["odo_km"]) + km
	v["condition"] = maxf(float(v["condition"]) - km * 0.01, 0.0)          # (a point every 100 km)
	car.fuel_frac = float(v["fuel_l"]) / float(v["tank_l"])
	car.out_of_fuel = float(v["fuel_l"]) <= 0.0
	car.torque_mul = _base_torque * (0.7 + 0.3 * clampf(float(v["condition"]) / 60.0, 0.0, 1.0)) * float(v.get("engine_k", 1.0))
	#  (engine_k: a fault of its own, the story's: the old scooter dying in traffic 0, patched and coughing 0.8)
	if _log:
		_log_t += dt
		if _log_t > 2.0:
			_log_t = 0.0
			print("FUEL %s: %.1f km/h, %.4f L (%.0f%%), odo %.3f km, condition %.1f, torque %.2f" % [current, spd * 3.6, float(v["fuel_l"]),
				100.0 * float(car.fuel_frac), float(v["odo_km"]), float(v["condition"]), float(car.torque_mul)])


## A crash's damage to the vehicle he's on (0..1 severity).
func crashed(severity: float) -> void:
	var v := vehicle(current)
	if not v.is_empty():
		v["condition"] = maxf(float(v["condition"]) - severity * 25.0, 0.0)
		save()


## Petrol into vehicle id: litres asked (or the tank's room); returns {litres, paise} actually put in.
func refuel(id: String, litres: float) -> Dictionary:
	var v := vehicle(id)
	if v.is_empty():
		return {"litres": 0.0, "paise": 0}
	var put := clampf(litres, 0.0, float(v["tank_l"]) - float(v["fuel_l"]))
	var paise := int(round(put * PETROL_PAISE))
	v["fuel_l"] = float(v["fuel_l"]) + put
	if id == current and city.car:
		city.car.fuel_frac = float(v["fuel_l"]) / float(v["tank_l"])
		city.car.out_of_fuel = false
	save()
	return {"litres": put, "paise": paise}


## A service or repair: condition back up to `to`.
func service(id: String, to: float) -> void:
	var v := vehicle(id)
	if not v.is_empty():
		v["condition"] = maxf(float(v["condition"]), to)
		save()


# ---- instalments, each morning ----
func _process(_dt: float) -> void:
	if city == null or city.money == null or city.fines == null:
		return
	var d := int(city.fines.sim.day)
	for ln in finance.loans:
		if bool(ln.get("closed", false)):
			continue
		var k := int(ln.get("posted", 0)) + 1
		while k <= int(ln["months"]) and Finance.due_day(ln, k) - POST_DAYS <= d:
			_post(ln, k)
			ln["posted"] = k
			k += 1


func _post(ln: Dictionary, k: int) -> void:
	var v := vehicle(str(ln["vehicle"]))
	var amount := int(ln["emi"]) / 100
	if k == int(ln["months"]):
		var sch := Finance.schedule(int(ln["principal"]), float(ln["rate_pa"]), int(ln["months"]))
		amount = int(ceil(float(sch[sch.size() - 1]["emi"]) / 100.0))
	var nm: Dictionary = v.get("name", {"en": "the vehicle"})
	city.money.add_bill({"id": "%s_%d" % [ln["id"], k], "kind": "emi", "loan": ln["id"], "n": k, "amount": amount,
		"in_days": Finance.due_day(ln, k) - int(city.fines.sim.day),
		"label": {"en": "%s's EMI (%d of %d)" % [str(nm.get("en", "")).capitalize(), k, int(ln["months"])],
			"ta": "%s EMI (%d / %d)" % [str(nm.get("ta", nm.get("en", ""))), k, int(ln["months"])]},
		"from": {"en": str(ln["lender"]), "ta": str(ln["lender"])},
		"text": {"en": "EMI %d of %d: %s due on day %d. Keep the balance ready." % [k, int(ln["months"]), Finance.rupees(amount * 100, false), Finance.due_day(ln, k)],
			"ta": "EMI %d / %d: %s கட்ட வேண்டிய நாள் %d. இருப்பு வைத்திருக்கவும்." % [k, int(ln["months"]), Finance.rupees(amount * 100, false), Finance.due_day(ln, k)]}})


## money.gd: a loan's bill paid (whole, with any late charge on it).
func bill_paid(b: Dictionary) -> void:
	var ln := finance.loan(str(b.get("loan", "")))
	if ln.is_empty():
		return
	if str(b["kind"]) == "redeem":
		vehicle(str(ln["vehicle"]))["seized"] = false
		ln["missed"] = 0
	else:
		finance.pay_instalment(ln, int(city.fines.sim.day))
	save()


## money.gd: a loan's bill `late` days past due. Returns true when it's handled (money.gd's old-scooter rules don't
## apply).
func bill_overdue(b: Dictionary, late: int) -> bool:
	var ln := finance.loan(str(b.get("loan", "")))
	if ln.is_empty():
		return false
	if late >= 1 and not bool(b.get("late_charged", false)):
		b["late_charged"] = true
		var charge := finance.miss(ln, int(city.fines.sim.day))
		b["amount"] = int(b["amount"]) + charge / 100
		city.phone.message({"en": str(ln["lender"]), "ta": str(ln["lender"])},
			{"en": "EMI %d unpaid. Bounce charge and penal interest %s added. Pay %s now." % [int(b.get("n", 0)), Finance.rupees(charge, false), Finance.rupees((int(b["amount"]) - int(b["paid"])) * 100, false)],
			"ta": "EMI %d செலுத்தப்படவில்லை. அபராதம் %s சேர்க்கப்பட்டது. இப்போது %s செலுத்தவும்." % [int(b.get("n", 0)), Finance.rupees(charge, false), Finance.rupees((int(b["amount"]) - int(b["paid"])) * 100, false)]})
	var v := vehicle(str(ln["vehicle"]))
	if int(ln.get("missed", 0)) >= 3 and not bool(v.get("seized", true)):
		v["seized"] = true
		var dues := 0
		for o in city.money.bills:
			if str(o.get("loan", "")) == str(ln["id"]) and str(o["kind"]) == "emi":
				dues += int(o["amount"]) - int(o["paid"])
				o["paid"] = o["amount"]
		city.money.add_bill({"id": "redeem_%s" % ln["id"], "kind": "redeem", "loan": ln["id"], "amount": dues + RELEASE_FEE, "in_days": 30,
			"label": {"en": "%s back" % str(v["name"].get("en", "")), "ta": "%s திரும்ப" % str(v["name"].get("ta", ""))}})
		city.phone.message({"en": str(ln["lender"]), "ta": str(ln["lender"])},
			{"en": "Three EMIs missed. Vehicle %s taken into recovery. Pay all dues + ₹3,000 to release." % str(v["plate"]),
			"ta": "மூணு EMI தவறியது. வாகனம் %s மீட்பு செய்யப்பட்டது. எல்லா நிலுவை + ₹3,000 கட்டி திரும்ப பெறவும்." % str(v["plate"])})
	save()
	return true


# ---- testing ----
func _test() -> void:
	await get_tree().create_timer(1.0).timeout
	var ok := true
	# the formula against a hand-worked case: ₹1,00,000 at 12 % for 12 months → ₹8,884.88 exact, ₹8,885 charged
	var e := Finance.emi_exact(10000000, 0.12, 12)
	print("FINANCE emi exact %.4f paise (expect 888487.88)" % e)
	ok = ok and absf(e - 888487.88) < 0.5
	ok = ok and Finance.emi_rounded(10000000, 0.12, 12) == 888500
	for case in [[7200000, 0.105, 24], [5400000, 0.115, 18], [10000000, 0.12, 12], [3000000, 0.0, 10]]:
		var sch := Finance.schedule(int(case[0]), float(case[1]), int(case[2]))
		var sum_p := 0
		var sum_i := 0
		for row in sch:
			sum_p += int(row["principal"])
			sum_i += int(row["interest"])
		var last: Dictionary = sch[sch.size() - 1]
		print("FINANCE %s at %.1f%% x %d: EMI %s, %d rows, principal back %s (of %s), interest %s, last %s, balance %d" % [Finance.rupees(int(case[0])),
			float(case[1]) * 100.0, int(case[2]), Finance.rupees(Finance.emi_rounded(int(case[0]), float(case[1]), int(case[2]))), sch.size(),
			Finance.rupees(sum_p), Finance.rupees(int(case[0])), Finance.rupees(sum_i), Finance.rupees(int(last["emi"])), int(last["balance"])])
		ok = ok and sum_p == int(case[0]) and int(last["balance"]) == 0 and sch.size() == int(case[2])
	# two loans on two vehicles, instalments posted as bills, paid, one missed, saved and loaded back
	var day0 := int(city.fines.sim.day)
	add_vehicle({"id": "test_bike", "kind": "bike", "name": {"en": "the motorcycle"}, "plate": "TN 38 BX 2741", "fuel_l": 2.0})
	add_vehicle({"id": "test_scooter", "kind": "scooter", "name": {"en": "Divya's scooter"}, "plate": "TN 66 F 9083", "rider": "divya", "fuel_l": 1.0})
	var lb := finance_vehicle("test_bike", "Kongu Two-Wheeler Finance", 92400, 15000, 0, 0.115, 24)
	var ls := finance_vehicle("test_scooter", "Kongu Two-Wheeler Finance", 84600, 12000, 0, 0.115, 24)
	print("FINANCE bike loan: principal %s, EMI %s; scooter loan: principal %s, EMI %s" % [Finance.rupees(int(lb["principal"])),
		Finance.rupees(int(lb["emi"])), Finance.rupees(int(ls["principal"])), Finance.rupees(int(ls["emi"]))])
	ok = ok and int(lb["principal"]) == 7740000 and int(ls["principal"]) == 7260000
	city.fines.sim.day = day0 + Finance.FIRST_DUE_DAYS - POST_DAYS
	await get_tree().process_frame
	await get_tree().process_frame
	print("FINANCE day %d → %d, posted bike %s, bills %d" % [day0, int(city.fines.sim.day), str(lb.get("posted")), city.money.bills.size()])
	var bike_bill := {}
	var scooter_bill := {}
	for b in city.money.bills:
		if str(b.get("id", "")) == "loan_test_bike_1":
			bike_bill = b
		if str(b.get("id", "")) == "loan_test_scooter_1":
			scooter_bill = b
	print("FINANCE bills posted: bike %s, scooter %s" % [str(bike_bill.get("amount", "none")), str(scooter_bill.get("amount", "none"))])
	if bike_bill.is_empty() or scooter_bill.is_empty():
		print("FINANCETEST FAIL (no bills)")
		get_tree().quit()
		return
	ok = ok and int(bike_bill["amount"]) * 100 == int(lb["emi"])
	# the bike's paid on time; the scooter's missed by a day
	bike_bill["paid"] = bike_bill["amount"]
	bill_paid(bike_bill)
	print("FINANCE bike after EMI 1: balance %s, paid %d, left %d" % [Finance.rupees(int(lb["balance"])), int(lb["paid_n"]), finance.remaining_instalments(lb)])
	var sch1: Dictionary = Finance.schedule(int(lb["principal"]), 0.115, 24)[0]
	ok = ok and int(lb["balance"]) == int(sch1["balance"])
	var before := int(scooter_bill["amount"])
	bill_overdue(scooter_bill, 1)
	print("FINANCE scooter EMI 1 missed: bill %d → %d (late charge), missed %d" % [before, int(scooter_bill["amount"]), int(ls["missed"])])
	ok = ok and int(scooter_bill["amount"]) == before + (Finance.LATE_FEE + int(round(float(ls["emi"]) * Finance.PENAL_PM))) / 100
	# fuel: 10 km on the motorcycle at a steady throttle
	var bike := vehicle("test_bike")
	var f0 := float(bike["fuel_l"])
	var r := refuel("test_bike", 5.0)
	print("FINANCE refuel: %.2f L for %s; tank %.2f / %.1f L" % [float(r["litres"]), Finance.rupees(int(r["paise"])), float(bike["fuel_l"]), float(bike["tank_l"])])
	ok = ok and absf(float(bike["fuel_l"]) - (f0 + 5.0)) < 0.001 and int(r["paise"]) == 50750
	# save and load
	save()
	var saved: Dictionary = city.fines._save_data["garage"].duplicate(true)
	var json := JSON.stringify(saved)
	var back = JSON.parse_string(json)
	var g2: Node = (load("res://scripts/city/garage.gd") as GDScript).new()
	g2.load_state(back)
	var lb2: Dictionary = g2.finance.loan("loan_test_bike")
	print("FINANCE after save and load: %d vehicles, bike balance %s, history %d entries" % [g2.vehicles.size(), Finance.rupees(int(lb2.get("balance", 0))), (lb2.get("history", []) as Array).size()])
	ok = ok and int(lb2.get("balance", 0)) == int(lb["balance"]) and g2.vehicles.size() == vehicles.size()
	g2.free()
	print("FINANCETEST %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
