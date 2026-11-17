extends RefCounted
## Vehicle loans (docs/PROLOGUE_PLAN_2026-11-17.md): the motorcycle's and the scooter's, each its own record.
## All sums in paise (int), shown as rupees with two decimals; play money only.
##
##   EMI   = P · r · (1+r)^n / ((1+r)^n − 1), r the monthly rate (annual / 12), n the months. Lenders here round the
##           instalment to the rupee; each month's interest is the balance × r (to the paisa), the rest of the EMI
##           pays the principal, and the last instalment is whatever clears the balance exactly.
##   due   the first instalment a fixed number of game days after the purchase (FIRST_DUE_DAYS), then every
##         MONTH_DAYS; each one becomes a bill in money.gd (kind "emi", "loan": the id), so its reminders, paying at
##         home through Amma, and what missing them does (the finance company's calls, the vehicle taken after
##         three) are money.gd's, as for the old scooter's instalment.
##   late  a missed instalment adds a bounce charge (LATE_FEE) and penal interest (PENAL_PM a month on what's
##         overdue), recorded in the history like every payment.
## Saved in the save file's "loans" (city.fines._save_data).

const MONTH_DAYS := 30              # a game month
const FIRST_DUE_DAYS := 10          # bought near the month's end, the first EMI on the 5th of the next
const LATE_FEE := 59000             # ₹590 bounce charge (₹500 + GST)
const PENAL_PM := 0.02              # 2 % a month on the overdue instalment

var loans: Array = []               # [{id, vehicle, lender, price, down, trade_in, principal, rate_pa, months, emi,
                                    #   start_day, paid_n, balance, overdue, history: [{day, kind, amount,
                                    #   interest, principal, balance}]}]


## The exact instalment in paise for principal p (paise), annual rate (0.105 = 10.5 %), n months (unrounded).
static func emi_exact(p: int, rate_pa: float, n: int) -> float:
	var r := rate_pa / 12.0
	if r <= 0.0:
		return float(p) / float(n)
	var f := pow(1.0 + r, n)
	return float(p) * r * f / (f - 1.0)


## The instalment as charged: rounded to the rupee (paise).
static func emi_rounded(p: int, rate_pa: float, n: int) -> int:
	return int(round(emi_exact(p, rate_pa, n) / 100.0)) * 100


## The whole schedule: [{n, interest, principal, emi, balance}] (paise), the last instalment adjusted.
static func schedule(p: int, rate_pa: float, n: int) -> Array:
	var r := rate_pa / 12.0
	var emi := emi_rounded(p, rate_pa, n)
	var bal := p
	var out: Array = []
	for k in n:
		var interest := int(round(float(bal) * r))
		var pay := emi
		if k == n - 1 or emi - interest > bal:
			pay = bal + interest
		var princ := pay - interest
		bal -= princ
		out.append({"n": k + 1, "interest": interest, "principal": princ, "emi": pay, "balance": bal})
		if bal <= 0:
			break
	return out


## "₹1,23,456.78" (Indian grouping) from paise.
static func rupees(paise: int, decimals := true) -> String:
	var neg := paise < 0
	var a := absi(paise)
	var s := str(a / 100)
	if s.length() > 3:
		var head := s.left(s.length() - 3)
		var tail := s.right(3)
		var out := ""
		while head.length() > 2:
			out = "," + head.right(2) + out
			head = head.left(head.length() - 2)
		s = head + out + "," + tail
	var t := ("-" if neg else "") + "₹" + s
	if decimals:
		t += ".%02d" % (a % 100)
	return t


## A new loan: price of the vehicle, down payment and trade-in (paise), the rate, the months; returns it.
func open_loan(id: String, vehicle: String, lender: String, price: int, down: int, trade_in: int, rate_pa: float,
		months: int, day: int) -> Dictionary:
	var p := price - down - trade_in
	var ln := {"id": id, "vehicle": vehicle, "lender": lender, "price": price, "down": down, "trade_in": trade_in,
		"principal": p, "rate_pa": rate_pa, "months": months, "emi": emi_rounded(p, rate_pa, months),
		"start_day": day, "paid_n": 0, "balance": p, "overdue": 0, "missed": 0, "closed": false,
		"history": [{"day": day, "kind": "disbursed", "amount": p, "interest": 0, "principal": 0, "balance": p}]}
	loans.append(ln)
	return ln


func loan(id: String) -> Dictionary:
	for l in loans:
		if str(l["id"]) == id:
			return l
	return {}


## The day instalment k (1-based) falls due.
static func due_day(ln: Dictionary, k: int) -> int:
	return int(ln["start_day"]) + FIRST_DUE_DAYS + (k - 1) * MONTH_DAYS


## The next instalment: {n, due, emi (what this one is: the schedule's, the last adjusted), interest, principal}.
func next_due(ln: Dictionary) -> Dictionary:
	if bool(ln.get("closed", false)):
		return {}
	var k := int(ln["paid_n"]) + 1
	var r := float(ln["rate_pa"]) / 12.0
	var bal := int(ln["balance"])
	var interest := int(round(float(bal) * r))
	var emi := int(ln["emi"])
	if k >= int(ln["months"]) or emi - interest > bal:
		emi = bal + interest
	return {"n": k, "due": due_day(ln, k), "emi": emi, "interest": interest, "principal": emi - interest}


## An instalment paid (the whole of it; money.gd pays bills whole): the balance goes down by its principal part.
func pay_instalment(ln: Dictionary, day: int) -> Dictionary:
	var nd := next_due(ln)
	if nd.is_empty():
		return {}
	ln["balance"] = int(ln["balance"]) - int(nd["principal"])
	ln["paid_n"] = int(nd["n"])
	ln["history"].append({"day": day, "kind": "emi", "n": nd["n"], "amount": nd["emi"], "interest": nd["interest"],
		"principal": nd["principal"], "balance": ln["balance"]})
	if int(ln["overdue"]) > 0:                       # the late charges ride on the instalment that clears them
		ln["history"].append({"day": day, "kind": "late_paid", "amount": ln["overdue"], "interest": 0, "principal": 0,
			"balance": ln["balance"]})
		ln["overdue"] = 0
	if int(ln["balance"]) <= 0:
		ln["closed"] = true
	return nd


## An instalment missed (its due day passed unpaid): the bounce charge and a month's penal interest on it.
func miss(ln: Dictionary, day: int) -> int:
	var nd := next_due(ln)
	if nd.is_empty():
		return 0
	var charge := LATE_FEE + int(round(float(nd["emi"]) * PENAL_PM))
	ln["overdue"] = int(ln["overdue"]) + charge
	ln["missed"] = int(ln.get("missed", 0)) + 1
	ln["history"].append({"day": day, "kind": "late", "n": nd["n"], "amount": charge, "interest": 0, "principal": 0,
		"balance": ln["balance"]})
	return charge


func remaining_instalments(ln: Dictionary) -> int:
	return 0 if bool(ln.get("closed", false)) else int(ln["months"]) - int(ln["paid_n"])


func save_data() -> Array:
	return loans.duplicate(true)


func load_data(a) -> void:
	loans = []
	if a is Array:
		for l in a:
			if l is Dictionary:
				loans.append(l)
