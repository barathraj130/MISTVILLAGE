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
## Saved in the save file's "accounts" (fines._save_data), beside bail's ("money" there is the wallet itself).

const Actor := preload("res://scripts/story/actor.gd")

var city
var frozen := false
var bank := 0                                # what's in the frozen account (it's there; he can't touch it)
var amma_holds := 0                          # the app's pay, in Amma's account, to be handed over
var bills: Array = []                        # [{"id", "label": {en, ta}, "amount", "paid", "due" (day), "kind":
                                             #   rent | power | emi | fees | other, "stage": 0.., "missed": 0}]
var seized := false                          # the scooter, taken for three missed instalments
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--moneytest="):
			_test.call_deferred(arg.get_slice("=", 1))


func _save() -> void:
	city.fines._save_data["accounts"] = {"frozen": frozen, "bank": bank, "amma_holds": amma_holds, "bills": bills,
		"seized": seized}


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
					city.phone.message({"en": "Kongu Two-Wheeler Finance", "ta": "கொங்கு டூ-வீலர் ஃபைனான்ஸ்"},
						{"en": "Three instalments missed. Your vehicle TN 38 has been taken into recovery. Pay all dues + ₹3,000 to release.",
						"ta": "மூணு தவணை தவறியது. உங்கள் வாகனம் TN 38 மீட்பு செய்யப்பட்டது. எல்லா நிலுவை + ₹3,000 கட்டி திரும்ப பெறவும்."})
		"fees":
			if stage < 1 and late >= 0:
				b["stage"] = 1
				city.phone.message({"en": "Divya", "ta": "திவ்யா"}, {"en": "They didn't let me into the exam hall. Fees. It's okay anna. It's okay.",
					"ta": "எக்ஸாம் ஹால்ல விடல. ஃபீஸ். பரவாயில்ல அண்ணா. பரவாயில்ல."})


# ---- paying, at home, to Amma ----
## E near Amma at home: the first bill still owed, to hold money out for.
func offer(room_name: String, room: Node3D, p: Vector3) -> String:
	if room_name != "home" or room == null or _paying != "" or _amma == null:
		return ""
	if Vector2(_amma.global_position.x - p.x, _amma.global_position.z - p.z).length() > 2.2:
		return ""
	for b in bills:
		var left: int = int(b["amount"]) - int(b["paid"])
		if left > 0:
			return ("give Amma money for %s (%s owed)" if _lang() == "en" else "%s-க்கு அம்மா கிட்ட காசு குடுங்க (%s நிலுவை)") % [_t(b["label"]), _money(left)]
	return ""


func go() -> void:
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
	tree.quit()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [dir, name], 0.85)
