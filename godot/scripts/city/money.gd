extends Node
## Karthik's money after the arrest (GAME_DESIGN.md §9): hard to handle, and never a number on the screen.
##   frozen   at the arrest the police have the co-op bank debit-freeze his account (Crime No. 412). From then
##            payments from his phone fail ("account frozen"), and the wallet's notes (sim.money) are all he has.
##   earnings the delivery app can't pay a frozen account: it pays Amma's. At home she counts it into his hand
##            (with Amma there, the next time he's home).
##   bills    each comes as a message with its date (rent, electricity, the scooter's instalment, Divya's fees),
##            a reminder two days before and on the day, and is paid by holding out notes: at home, to Amma, who
##            pays the owner, the board and the college (E near her: "give Amma ₹… for the rent").
##   unpaid   nothing is taken that he doesn't have; the bill stays owed and comes back each morning as a person:
##            the owner at the door, a red slip on the meter, the finance company's calls (three missed instalments:
##            the scooter is taken), Divya kept out of her exam.
##   ways out each one costs something:
##            Bala   call him (his phone's contacts): he lends without being asked twice, ₹5,000, then ₹3,000 a week
##                   later, then nothing this week; it can't go to a frozen account, so he leaves it with Amma.
##                   What's owed to him is kept (Act 5).
##            the chain  at home, tell Amma what's owed: she takes her gold chain off herself. At the co-op bank's
##                   counter it's pledged (a jewel loan, the appraiser's form signed): ₹50,000 in his hand, ₹500 a
##                   month interest, and six months to bring the ₹50,000 back or it goes to auction.
##            the bike   when the scooter's taken, Bala's old motorbike is left for him; the scooter comes back when
##                   everything owed on it and ₹3,000 more are paid (to Amma, who takes it to the finance company).
## Saved in the save file's "accounts" (fines._save_data), beside bail's ("money" there is the wallet itself).

const Actor := preload("res://scripts/story/actor.gd")
const Tasks := preload("res://scripts/story/tasks.gd")
const BALA := {"id": "bala", "name": {"en": "Bala", "ta": "பாலா"}, "number": "94433 •••••",
	"where": {"en": "Bala's workshop, Ganapathy", "ta": "பாலா வொர்க்ஷாப், கணபதி"}}

var city
var frozen := false
var bank := 0                                # what's in the frozen account (it's there; he can't touch it)
var amma_holds := 0                          # the app's pay, in Amma's account, to be handed over
var bills: Array = []                        # [{"id", "label": {en, ta}, "amount", "paid", "due" (day), "kind":
                                             #   rent | power | emi | fees | other, "stage": 0.., "missed": 0}]
var seized := false                          # the scooter, taken for three missed instalments
var owes_bala := 0                           # lent by Bala (never asked back; Act 5 remembers)
var bala_loans: Array = []                   # the days he lent
var bala_left := 0                           # Bala's money, left with Amma, to be handed over
var chain := ""                              # Amma's gold chain: "" at home | with_him | pledged | redeemed
var _bike_due := false                       # the scooter's gone: Bala's bike, when he's next on foot
var _tasks: Control
var _reminded := {}
var _morning := -1
var _amma: Node3D                            # Amma at home in free play
var _paying := ""                            # the bill whose money he's holding out to her


func _ready() -> void:
	var sd: Dictionary = city.fines._save_data.get("accounts", {})
	frozen = bool(sd.get("frozen", false))
	bank = int(sd.get("bank", 0))
	amma_holds = int(sd.get("amma_holds", 0))
	bills = sd.get("bills", [])
	seized = bool(sd.get("seized", false))
	owes_bala = int(sd.get("owes_bala", 0))
	bala_loans = sd.get("bala_loans", [])
	bala_left = int(sd.get("bala_left", 0))
	chain = str(sd.get("chain", ""))
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_tasks = Tasks.new()
	_tasks.visible = false
	_tasks.finished.connect(_pledged)
	layer.add_child(_tasks)
	if city.phone:
		city.phone.dialled.connect(_dialled)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--moneytest="):
			_test.call_deferred(arg.get_slice("=", 1))


func _save() -> void:
	city.fines._save_data["accounts"] = {"frozen": frozen, "bank": bank, "amma_holds": amma_holds, "bills": bills,
		"seized": seized, "owes_bala": owes_bala, "bala_loans": bala_loans, "bala_left": bala_left, "chain": chain}


func _day() -> int:
	return int(city.fines.sim.day)


func _min() -> float:
	return float(city.fines.sim.minute)


func _lang() -> String:
	return city.story.lang if city.story else "en"


func _t(d) -> String:
	return str(d.get(_lang(), d.get("en", ""))) if d is Dictionary else str(d)


func _money(v: int) -> String:
	var s := str(v)
	if s.length() > 3:                               # Indian grouping: 1,23,456
		var head := s.left(s.length() - 3)
		var out := ""
		while head.length() > 2:
			out = "," + head.right(2) + out
			head = head.left(head.length() - 2)
		s = head + out + "," + s.right(3)
	return "₹" + s


# ---- what the story does to it ----
## The police freeze the account; "bank": what's in it, "wallet": the cash on him.
func freeze(in_bank: int, wallet := -1) -> void:
	frozen = true
	bank = in_bank
	if wallet >= 0:
		city.fines.sim.money = wallet
	city.phone.message({"en": "Kovai Nagar Co-op Bank", "ta": "கோவை நகர் கூட்டுறவு வங்கி"},
		{"en": "Your SB account XX4417 has been debit-frozen on the request of Nagar Police Station (Crime No. 412). Balance %s. For details contact your branch." % _money(bank),
		"ta": "உங்கள் சேமிப்பு கணக்கு XX4417 நகர் காவல் நிலைய (குற்ற எண் 412) கோரிக்கையின் பேரில் முடக்கப்பட்டுள்ளது. இருப்பு %s. விவரங்களுக்கு கிளையை அணுகவும்." % _money(bank)})
	_save()


## A bill falls due: {"id", "label", "amount", "in_days", "kind", "from": who sends it, "text": their message}.
func add_bill(b: Dictionary) -> void:
	for o in bills:
		if str(o["id"]) == str(b["id"]):
			return
	var bill := {"id": str(b["id"]), "label": b["label"], "amount": int(b["amount"]), "paid": 0,
		"due": _day() + int(b.get("in_days", 7)), "kind": str(b.get("kind", "other")), "stage": 0, "missed": 0}
	bills.append(bill)
	if not city.phone.contacts.any(func(c): return str(c.get("id", "")) == "bala"):
		city.phone.add_contact(BALA)
	if b.has("text"):
		city.phone.message(b.get("from", {"en": "Amma", "ta": "அம்மா"}), b["text"])
	_save()


func owed(id: String) -> int:
	for b in bills:
		if str(b["id"]) == id:
			return int(b["amount"]) - int(b["paid"])
	return 0


## Pay that comes in from work: the app's money, into his account, or (frozen) into Amma's.
func earn(amount: int, app) -> void:
	if not frozen:
		city.fines.sim.money += amount
		return
	amma_holds += amount
	city.phone.message(app, {"en": "Payout of %s sent to the alternate account (LAKSHMI M, XX0932): your account is frozen." % _money(amount),
		"ta": "%s மாற்று கணக்குக்கு (லட்சுமி ம., XX0932) அனுப்பப்பட்டது: உங்கள் கணக்கு முடக்கப்பட்டுள்ளது." % _money(amount)})
	_save()


## A payment from his phone (a QR, a bill): false, and the bank's refusal on his phone, while it's frozen.
func pay_online(amount: int, to: String) -> bool:
	if frozen:
		city.phone.message({"en": "UPI", "ta": "UPI"}, {"en": "Payment of %s to %s declined: account frozen." % [_money(amount), to],
			"ta": "%s-க்கு %s பேமென்ட் நிராகரிக்கப்பட்டது: கணக்கு முடக்கம்." % [to, _money(amount)]})
		return false
	if city.fines.sim.money < amount:
		return false
	city.fines.sim.money -= amount
	return true


## At home with Amma: what the app paid into her account, counted into his hand.
func handover() -> bool:
	if bala_left > 0:                                # Bala's, first: he came by
		var bl := bala_left
		bala_left = 0
		city.fines.sim.money += bl
		city.hud.say("Amma", ("Bala came. He left this, %s. He said don't argue with him." if _lang() == "en" else
			"பாலா வந்தான். இத விட்டுட்டு போனான், %s. அவன் கிட்ட சண்டை போடாதேன்னு சொன்னான்.") % _money(bl), 4.5)
		_save()
		if amma_holds > 0:
			get_tree().create_timer(4.8).timeout.connect(handover)
		return true
	if amma_holds <= 0:
		return false
	var amt := amma_holds
	amma_holds = 0
	city.fines.sim.money += amt
	city.hud.say("Amma", ("%s came on my phone from that app. Here. Count it." if _lang() == "en" else
		"அந்த ஆப்ல இருந்து என் ஃபோனுக்கு %s வந்துச்சு. இந்தா. எண்ணிப் பாரு.") % _money(amt), 4.5)
	if city.hands:
		city.hands.items.append({"id": "cash_%d" % _day(), "kind": "note", "title": {"en": "From Amma", "ta": "அம்மா குடுத்தது"},
			"body": {"en": "%s, in old notes, folded twice." % _money(amt), "ta": "%s, பழைய நோட்டுகள், ரெண்டா மடிச்சது." % _money(amt)}})
	_save()
	return true


# ---- the days ----
func _process(_dt: float) -> void:
	if city == null or city.fines == null:
		return
	_amma_at_home()
	if _bike_due and city.walker != null:            # (gone while he was away from it: Bala's old bike there instead)
		_bike_due = false
		city.car.configure("bike" if seized else "karthik_scooter")
		if seized:
			city.phone.message({"en": "Bala", "ta": "பாலா"}, {"en": "Heard about the scooter. Take my old bike, da. It pulls left a bit. Don't argue.",
				"ta": "ஸ்கூட்டர் பத்தி கேள்விப்பட்டேன். என் பழைய பைக்க எடுத்துக்கோ டா. கொஞ்சம் இடது பக்கம் இழுக்கும். சண்டை போடாத."})
	var d := _day()
	var m := _min()
	if m >= 9.0 * 60.0 and _morning != d:            # each morning, what's owed comes back
		_morning = d
		for b in bills:
			if int(b["paid"]) >= int(b["amount"]):
				continue
			var left: int = int(b["due"]) - d
			var key := "%s:%d" % [b["id"], d]
			if (left == 2 or left == 0) and not _reminded.has(key):
				_reminded[key] = true
				city.phone.message({"en": "Reminder", "ta": "நினைவூட்டல்"}, {"en": "%s: %s %s" % [_t(b["label"]), _money(int(b["amount"]) - int(b["paid"])),
					"today" if left == 0 else "in two days"], "ta": "%s: %s %s" % [_t(b["label"]), _money(int(b["amount"]) - int(b["paid"])),
					"இன்னைக்கு" if left == 0 else "ரெண்டு நாள்ல"]})
			if left < 0:
				_overdue(b, -left)
		_save()


## A bill not paid, `late` days past its date: what happens, once each stage.
func _overdue(b: Dictionary, late: int) -> void:
	var k := str(b["kind"])
	var stage := int(b["stage"])
	var amma := {"en": "Amma", "ta": "அம்மா"}
	match k:
		"rent":
			if stage < 1 and late >= 1:
				b["stage"] = 1
				city.phone.message(amma, {"en": "Rajendran sir came about the rent. He was polite. He'll come again on Sunday.",
					"ta": "ராஜேந்திரன் சார் வாடகைக்கு வந்தாரு. மரியாதையா தான் பேசினாரு. ஞாயிறு திரும்ப வருவாராம்."})
			elif stage < 2 and late >= 7:
				b["stage"] = 2
				city.phone.message(amma, {"en": "He gave a letter. Two weeks, he says, or we find another house. Come home early.",
					"ta": "ஒரு லெட்டர் குடுத்தாரு. ரெண்டு வாரம், இல்லன்னா வேற வீடு பாக்கணுமாம். சீக்கிரம் வீட்டுக்கு வா."})
		"power":
			if stage < 1 and late >= 1:
				b["stage"] = 1
				city.phone.message({"en": "TNEB", "ta": "மின் வாரியம்"}, {"en": "Service 04-317-2281: %s overdue. Disconnection after 7 days." % _money(int(b["amount"])),
					"ta": "இணைப்பு 04-317-2281: %s நிலுவை. 7 நாள்ல துண்டிப்பு." % _money(int(b["amount"]))})
			elif stage < 2 and late >= 7:
				b["stage"] = 2
				city.phone.message(amma, {"en": "They cut the current. Divya is studying by the phone's torch.",
					"ta": "கரண்ட் கட் பண்ணிட்டாங்க. திவ்யா ஃபோன் டார்ச்ல படிக்கறா."})
		"emi":
			var missed := 1 + late / 7
			if missed > int(b["missed"]):
				b["missed"] = missed
				if missed < 3:
					city.phone.message({"en": "Kongu Two-Wheeler Finance", "ta": "கொங்கு டூ-வீலர் ஃபைனான்ஸ்"},
						{"en": "Instalment %s overdue (%d missed). Pay at once to avoid recovery action." % [_money(int(b["amount"])), missed],
						"ta": "தவணை %s நிலுவை (%d தவறியது). மீட்பு நடவடிக்கையை தவிர்க்க உடனே செலுத்தவும்." % [_money(int(b["amount"])), missed]})
				elif not seized:
					seized = true
					_bike_due = true
					add_bill({"id": "redeem", "kind": "redeem", "amount": missed * int(b["amount"]) + 3000, "in_days": 30,
						"label": {"en": "the scooter back", "ta": "ஸ்கூட்டர் திரும்ப"}})
					city.phone.message({"en": "Kongu Two-Wheeler Finance", "ta": "கொங்கு டூ-வீலர் ஃபைனான்ஸ்"},
						{"en": "Three instalments missed. Your vehicle TN 38 has been taken into recovery. Pay all dues + ₹3,000 to release.",
						"ta": "மூணு தவணை தவறியது. உங்கள் வாகனம் TN 38 மீட்பு செய்யப்பட்டது. எல்லா நிலுவை + ₹3,000 கட்டி திரும்ப பெறவும்."})
		"chain":
			if stage < 1 and late >= 1 and chain == "pledged":
				b["stage"] = 1
				city.phone.message({"en": "Kovai Nagar Co-op Bank", "ta": "கோவை நகர் கூட்டுறவு வங்கி"},
					{"en": "Jewel loan JL-2291 is past its term. Redeem within 15 days or the pledge goes to public auction.",
					"ta": "நகைக்கடன் JL-2291 காலம் முடிந்தது. 15 நாளில் மீட்கவும், இல்லையெனில் பொது ஏலம்."})
			elif stage < 2 and late >= 15 and chain == "pledged":
				b["stage"] = 2
				chain = "lost"
				b["paid"] = b["amount"]
				city.phone.message({"en": "Amma", "ta": "அம்மா"}, {"en": "The bank's letter came. It's gone. It's only gold, kanna. Eat something.",
					"ta": "வங்கி லெட்டர் வந்துச்சு. போயிடுச்சு. வெறும் தங்கம் தான் கண்ணா. ஏதாவது சாப்பிடு."})
		"fees":
			if stage < 1 and late >= 0:
				b["stage"] = 1
				city.phone.message({"en": "Divya", "ta": "திவ்யா"}, {"en": "They didn't let me into the exam hall. Fees. It's okay anna. It's okay.",
					"ta": "எக்ஸாம் ஹால்ல விடல. ஃபீஸ். பரவாயில்ல அண்ணா. பரவாயில்ல."})


# ---- paying, at home, to Amma ----
## E near Amma at home: the first bill still owed, to hold money out for.
func offer(room_name: String, room: Node3D, p: Vector3) -> String:
	if room_name == "coopbank" and room != null and chain == "with_him" and not _tasks.visible:
		var cm := room.find_child("Mark_clerk", true, false) as Node3D
		if cm and Vector2(cm.global_position.x - p.x, cm.global_position.z - p.z).length() < 2.4:
			return "pledge Amma's chain (a jewel loan)" if _lang() == "en" else "அம்மா செயின அடகு வைங்க (நகைக்கடன்)"
		return ""
	if room_name != "home" or room == null or _paying != "" or _amma == null:
		return ""
	if Vector2(_amma.global_position.x - p.x, _amma.global_position.z - p.z).length() > 2.2:
		return ""
	var total := 0
	for b in bills:
		total += maxi(int(b["amount"]) - int(b["paid"]), 0)
	if chain == "" and total > 5000 and city.fines.sim.money < 500:   # owed, and nothing left to give: say so
		return "tell Amma what's owed (%s)" % _money(total) if _lang() == "en" else "எவ்வளவு நிலுவைன்னு அம்மா கிட்ட சொல்லுங்க (%s)" % _money(total)
	for b in bills:
		var left: int = int(b["amount"]) - int(b["paid"])
		if left > 0 and city.fines.sim.money > 0:
			return ("give Amma money for %s (%s owed)" if _lang() == "en" else "%s-க்கு அம்மா கிட்ட காசு குடுங்க (%s நிலுவை)") % [_t(b["label"]), _money(left)]
	return ""


func go() -> void:
	var doors = city.doors
	if doors and str(doors.inside.get("room", "")) == "coopbank":
		_pledge()
		return
	var total := 0
	for b in bills:
		total += maxi(int(b["amount"]) - int(b["paid"]), 0)
	if chain == "" and total > 5000 and city.fines.sim.money < 500:
		_the_chain()
		return
	for b in bills:
		if int(b["amount"]) - int(b["paid"]) > 0:
			_paying = str(b["id"])
			break
	if _paying == "" or city.hands == null:
		return
	city.hands.give({"id": "wallet", "kind": "wallet", "title": {"en": "Wallet", "ta": "பர்ஸ்"}})
	if not city.hands.note_given.is_connected(_note):
		city.hands.note_given.connect(_note)


## A note held out to her: it goes to the bill; the wallet opens again until it's paid or he puts it away.
func _note(amount: int) -> void:
	if _paying == "":
		return
	for b in bills:
		if str(b["id"]) == _paying:
			var give := mini(amount, int(b["amount"]) - int(b["paid"]))
			city.fines.sim.money -= give
			b["paid"] = int(b["paid"]) + give
			if int(b["paid"]) >= int(b["amount"]):
				city.hud.say("Amma", ("That's %s. I'll pay it tomorrow morning." if _lang() == "en" else "%s ஆயிடுச்சு. நாளைக்கு காலையில கட்டிடறேன்.") % _t(b["label"]), 4.0)
				_paid_off(b)
				_done()
			elif city.fines.sim.money > 0:
				city.hands.give({"id": "wallet", "kind": "wallet", "title": {"en": "Wallet", "ta": "பர்ஸ்"}})
			else:
				city.hud.say("Amma", ("%s more. Keep something for petrol, kanna." if _lang() == "en" else "இன்னும் %s. பெட்ரோலுக்கு கொஞ்சம் வச்சுக்கோ கண்ணா.") % _money(int(b["amount"]) - int(b["paid"])), 4.0)
				_done()
	_save()


func _done() -> void:
	_paying = ""
	if city.hands.note_given.is_connected(_note):
		city.hands.note_given.disconnect(_note)


## In free play, Amma is at home (her kitchen) when he comes in, and hands over what the app paid her.
func _amma_at_home() -> void:
	var doors = city.doors
	var inside: bool = doors != null and not doors.inside.is_empty() and str(doors.inside.get("room", "")) == "home" and doors._room != null
	if inside and _amma == null:
		var m := doors._room.find_child("Mark_amma_kitchen", true, false) as Node3D
		if m == null:
			return
		_amma = Actor.new()
		doors._room.add_child(_amma)
		_amma.setup("story_amma", "amma", Callable(), Color.html("#5a554f"))
		_amma.floor_y = m.global_position.y
		_amma.place(m.global_position, m.global_position - m.global_basis.z)
		handover.call_deferred()
	elif not inside and _amma != null:
		if is_instance_valid(_amma):
			_amma.queue_free()
		_amma = null


# ---- (testing) --moneytest=DIR ----
## The account frozen, two bills, a night's pay into Amma's account; home: her handover, money held out for the
## rent; then the days going by unpaid: the owner, the finance company, the scooter taken. Screenshots into DIR.
func _test(dir: String) -> void:
	var tree := get_tree()
	city.fines.persist = false
	await tree.create_timer(14.0).timeout
	var sim = city.fines.sim
	sim.minute = 20.0 * 60.0
	freeze(23400, 600)
	add_bill({"id": "rent", "kind": "rent", "amount": 9500, "in_days": 2, "label": {"en": "the rent", "ta": "வாடகை"}})
	add_bill({"id": "emi", "kind": "emi", "amount": 2850, "in_days": 1, "label": {"en": "the scooter's instalment", "ta": "ஸ்கூட்டர் தவணை"}})
	earn(1460, {"en": "QuickBite Rider", "ta": "குவிக்பைட் ரைடர்"})
	print("MONEYTEST frozen %s wallet %d amma %d online %s" % [frozen, sim.money, amma_holds, pay_online(5000, "KATHIR CCTV SERVICE")])
	city.car.speed = 0.0
	city.toggle_on_foot()
	var w: Node3D = city.walker
	var hp: Vector2 = city.doors._home
	var d := {}
	for r in [4.0, 8.0, 12.0, 16.0, 22.0]:
		for k in 12:
			var a := TAU * k / 12.0
			w.global_position = Vector3(hp.x + cos(a) * r, w.global_position.y + 30.0, hp.y + sin(a) * r)
			w.velocity = Vector3.ZERO
			await tree.create_timer(0.6).timeout
			var dd: Dictionary = city.doors.door_near(w.global_position)
			if not dd.is_empty() and str(dd.get("room", "")) == "home":
				d = dd
				break
		if not d.is_empty():
			break
	print("MONEYTEST door: %s" % str(d))
	if d.is_empty():
		tree.quit()
		return
	city.doors.enter(d, w)
	await tree.create_timer(3.0).timeout
	print("MONEYTEST handed over: wallet %d amma %d" % [sim.money, amma_holds])
	await _shot(dir, "money_1_handover")
	if _amma:
		w.global_position = _amma.global_position + _amma.global_basis.z * 1.2 + Vector3.UP * 0.2
		await tree.create_timer(1.0).timeout
	print("MONEYTEST offer: '%s'" % offer("home", city.doors._room, w.global_position))
	go()
	await tree.create_timer(0.6).timeout
	await _shot(dir, "money_2_wallet")
	for n in [500, 500, 200]:
		_note(n)
		await tree.create_timer(0.3).timeout
	print("MONEYTEST rent owed %d, wallet %d" % [owed("rent"), sim.money])
	city.hands.put_back()
	_done()
	_dialled(BALA)                                    # Bala, on the phone
	await tree.create_timer(10.0).timeout
	handover()
	print("MONEYTEST after Bala: wallet %d, owed to Bala %d" % [sim.money, owes_bala])
	city.hands.put_back()
	_done()
	sim.money = 300                                   # (spent: nothing left to give her)
	print("MONEYTEST offer: '%s'" % offer("home", city.doors._room, w.global_position))
	go()                                              # tell Amma: the chain
	await tree.create_timer(1.0).timeout
	await _shot(dir, "money_4_chain")
	print("MONEYTEST chain: %s" % chain)
	city.doors.leave(w)
	await tree.create_timer(1.0).timeout
	var bp: Vector2 = city.doors._bank
	var bd := {}
	for r in [6.0, 10.0, 14.0, 18.0, 24.0, 30.0]:
		for k in 12:
			var a2 := TAU * k / 12.0
			w.global_position = Vector3(bp.x + cos(a2) * r, w.global_position.y + 30.0, bp.y + sin(a2) * r)
			w.velocity = Vector3.ZERO
			await tree.create_timer(0.6).timeout
			var dd: Dictionary = city.doors.door_near(w.global_position)
			if not dd.is_empty() and str(dd.get("room", "")) == "coopbank":
				bd = dd
				break
		if not bd.is_empty():
			break
	print("MONEYTEST bank door: %s" % str(bd))
	if not bd.is_empty():
		city.doors.enter(bd, w)
		await tree.create_timer(2.5).timeout
		var cm := city.doors._room.find_child("Mark_clerk", true, false) as Node3D
		w.global_position = cm.global_position - cm.global_basis.z * 1.3 + Vector3.UP * 0.2
		await tree.create_timer(1.0).timeout
		print("MONEYTEST bank offer: '%s'" % offer("coopbank", city.doors._room, w.global_position))
		go()
		_tasks.skip = true                            # (after start(), which resets it)
		await tree.create_timer(0.8).timeout
		await _shot(dir, "money_5_pledge")
		await tree.create_timer(4.0).timeout
		print("MONEYTEST pledged: chain %s, wallet %d" % [chain, sim.money])
		city.doors.leave(w)
		await tree.create_timer(1.0).timeout
	for k in 4:                                       # four mornings unpaid, then two weeks more
		sim.day += 1
		sim.minute = 9.0 * 60.0 + 5.0
		await tree.create_timer(0.5).timeout
	city.phone.hold(true)
	city.phone._open_app("messages")
	await tree.create_timer(0.5).timeout
	await _shot(dir, "money_3_owed")
	city.phone.hold(false)
	for k in 14:
		sim.day += 1
		sim.minute = 9.0 * 60.0 + 5.0
		await tree.create_timer(0.3).timeout
	print("MONEYTEST after: rent stage %d, emi missed %d, seized %s" % [bills[0]["stage"], bills[1]["missed"], seized])
	await tree.create_timer(0.5).timeout
	print("MONEYTEST vehicle while seized: %s" % city.car.vehicle)
	_paying = "redeem"
	sim.money += 20000
	_note(20000)
	await tree.create_timer(0.5).timeout
	print("MONEYTEST redeemed: seized %s, vehicle %s, redeem owed %d" % [seized, city.car.vehicle, owed("redeem")])
	tree.quit()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [dir, name], 0.85)


# ---- the ways out ----
## A bill paid off: what it ends (the scooter back; the chain home again).
func _paid_off(b: Dictionary) -> void:
	match str(b["kind"]):
		"redeem":
			seized = false
			for o in bills:
				if str(o["kind"]) == "emi":
					o["paid"] = o["amount"]
			_bike_due = true
			city.phone.message({"en": "Kongu Two-Wheeler Finance", "ta": "கொங்கு டூ-வீலர் ஃபைனான்ஸ்"},
				{"en": "Dues received. Vehicle TN 38 released. Collect from the yard, Avinashi Road.",
				"ta": "நிலுவை பெறப்பட்டது. வாகனம் TN 38 விடுவிக்கப்பட்டது. அவிநாசி ரோடு யார்டில் பெற்றுக்கொள்ளவும்."})
		"chain":
			chain = "redeemed"
			city.hud.say("Amma", "(She puts it on without a word, and touches it once.)" if _lang() == "en" else "(ஒண்ணும் பேசாம போட்டுக்கறாங்க, ஒரு தடவ தொட்டுப் பாக்கறாங்க.)", 4.0)
	_save()


## He tells Amma what's owed; she takes her chain off herself.
func _the_chain() -> void:
	chain = "with_him"
	city.hud.say("Amma", ("(She listens. Then she takes off her chain and puts it in his hand.) The co-op bank gives on jewels. Go before it closes." if _lang() == "en" else
		"(கேக்கறாங்க. அப்புறம் தன் செயின கழட்டி அவன் கையில வைக்கறாங்க.) கூட்டுறவு வங்கில நகைக்கு குடுப்பாங்க. மூடறதுக்கு முன்னாடி போ."), 6.0)
	if city.hands:                                   # (in his hands: he looks at it, then it goes in his pocket)
		city.hands.give({"id": "chain", "kind": "note", "title": {"en": "Amma's chain", "ta": "அம்மா செயின்"},
			"body": {"en": "Her gold chain, still warm. Six grams, she said. She has worn it since Appa.", "ta": "அவங்க தங்க செயின், இன்னும் சூடா. ஆறு கிராம்னு சொன்னாங்க. அப்பா காலத்துல இருந்து போட்டிருக்காங்க."}})
	city.phone.pin("bank", {"en": "Kovai Nagar Co-op Bank: jewel loans", "ta": "கோவை நகர் கூட்டுறவு வங்கி: நகைக்கடன்"})
	_save()


## At the bank's counter: the appraiser's form, signed.
func _pledge() -> void:
	_tasks.start("sign", {"header": {"en": "Kovai Nagar Co-operative Bank", "ta": "கோவை நகர் கூட்டுறவு வங்கி"},
		"form": {"en": "JEWEL LOAN: APPRAISAL AND PLEDGE", "ta": "நகைக்கடன்: மதிப்பீடு மற்றும் அடமானம்"},
		"fields": [[{"en": "Item", "ta": "பொருள்"}, {"en": "Gold chain, 22 ct", "ta": "தங்க செயின், 22 கேரட்"}],
			[{"en": "Net weight", "ta": "நிகர எடை"}, "6.1 g"], [{"en": "Loan", "ta": "கடன்"}, "₹50,000"],
			[{"en": "Interest", "ta": "வட்டி"}, {"en": "12% a year, ₹500 a month", "ta": "ஆண்டுக்கு 12%, மாதம் ₹500"}],
			[{"en": "Redeem by", "ta": "மீட்க கடைசி"}, {"en": "six months", "ta": "ஆறு மாதம்"}]],
		"sign_label": {"en": "Signature of the pledger", "ta": "அடமானம் வைப்பவர் கையொப்பம்"},
		"seal": {"en": "BANK SEAL", "ta": "வங்கி முத்திரை"}}, _lang())


func _pledged(_r: Dictionary) -> void:
	chain = "pledged"
	if city.hands:
		city.hands.take("chain")
	city.fines.sim.money += 50000
	city.hud.say("Clerk", "Fifty thousand. Count it here, sir, in front of me. The packet stays sealed till you come back." if _lang() == "en" else
		"ஐம்பதாயிரம். இங்கயே என் முன்னாடி எண்ணுங்க சார். நீங்க திரும்ப வர்ற வரைக்கும் பாக்கெட் சீல்ல இருக்கும்.", 5.0)
	add_bill({"id": "chain_interest", "kind": "other", "amount": 500, "in_days": 30, "label": {"en": "the chain's interest", "ta": "செயின் வட்டி"}})
	add_bill({"id": "chain", "kind": "chain", "amount": 50000, "in_days": 180, "label": {"en": "Amma's chain back", "ta": "அம்மா செயின் திரும்ப"}})
	if city.walker and city.walker.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_save()


## A call he made: Bala picks up.
func _dialled(c: Dictionary) -> void:
	if str(c.get("id", "")) != "bala":
		return
	var d := _day()
	var amt := 5000 if bala_loans.is_empty() else (3000 if d - int(bala_loans[-1]) >= 7 else 0)
	var lines: Array
	if amt == 5000:
		lines = [["Bala", "Da! ...How much? ...Don't say sorry to me.", "டா! ...எவ்வளவு? ...என் கிட்ட சாரி சொல்லாத."],
			["Bala", "Your account's frozen, no? I'll give it to Amma tonight. Five thousand. Pay me when this is over. Not before.",
				"உன் அக்கவுண்ட் முடக்கம் தானே? ராத்திரி அம்மா கிட்ட குடுக்கறேன். அஞ்சாயிரம். இது முடிஞ்சப்புறம் குடு. அதுக்கு முன்னாடி இல்ல."]]
	elif amt > 0:
		lines = [["Bala", "Three. That's what I have this week, da. Amma will get it.", "மூணு. இந்த வாரம் என் கிட்ட இருக்கறது அவ்வளவு தான் டா. அம்மா கிட்ட குடுக்கறேன்."]]
	else:
		lines = [["Bala", "Da... this week I have nothing. The workshop's rent. Next week, da. Sorry.", "டா... இந்த வாரம் ஒண்ணும் இல்ல. வொர்க்ஷாப் வாடகை. அடுத்த வாரம் டா. சாரி."]]
	var t := 0.0
	for ln in lines:
		get_tree().create_timer(t).timeout.connect(city.hud.say.bind(ln[0], ln[1] if _lang() == "en" else ln[2], 4.5))
		t += 4.8
	if amt > 0:
		bala_loans.append(d)
		owes_bala += amt
		bala_left += amt
	print("MONEY Bala lends %d (owed to him %d)" % [amt, owes_bala])
	_save()
