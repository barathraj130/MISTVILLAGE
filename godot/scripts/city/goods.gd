extends RefCounted
## Things Karthik can buy and carry (the bag, B; the shops' counters, store.gd), what each does, and what each kind of
## shop sells. Prices are Coimbatore's, 2026 (₹). Kept in the save file with the wallet: fines._save_data["goods"].
##   food / drink   eaten from the bag: energy (life.gd), a little stress off
##   aid            first aid: "hurt" off (life.gd); a kit is three uses
##   safety         carried, not used on anyone: the torch lights the way at night; the whistle and the pepper
##                  spray see off a threat on a dark lane (city_threats.gd); the disc lock keeps the scooter where
##                  he left it. Legal to carry: a police check doesn't mind them.

const GOODS := {
	"water": {"en": "Water bottle, 1 L", "ta": "தண்ணீர் பாட்டில், 1 லி", "price": 20, "kind": "drink", "energy": 4.0, "stress": -2.0},
	"banana": {"en": "Bananas, two", "ta": "வாழைப்பழம், ரெண்டு", "price": 15, "kind": "food", "energy": 12.0},
	"biscuits": {"en": "Biscuits, a packet", "ta": "பிஸ்கட், ஒரு பாக்கெட்", "price": 20, "kind": "food", "energy": 14.0},
	"bun": {"en": "Sweet bun", "ta": "பன்", "price": 25, "kind": "food", "energy": 16.0},
	"vada_parcel": {"en": "Vada parcel, two", "ta": "வடை பார்சல், ரெண்டு", "price": 30, "kind": "food", "energy": 20.0, "stress": -3.0},
	"tea_flask": {"en": "Tea in a flask", "ta": "ஃப்ளாஸ்க்ல டீ", "price": 40, "kind": "drink", "energy": 6.0, "stress": -6.0},
	"idli_parcel": {"en": "Idli parcel, four with chutney", "ta": "இட்லி பார்சல், நாலு, சட்னியோட", "price": 60, "kind": "food", "energy": 40.0, "stress": -2.0},
	"ors": {"en": "ORS sachets", "ta": "ORS பாக்கெட்", "price": 25, "kind": "drink", "energy": 6.0, "hurt": -4.0},
	"first_aid": {"en": "First-aid kit", "ta": "முதலுதவி பெட்டி", "price": 250, "kind": "aid", "hurt": -40.0, "uses": 3},
	"bandage": {"en": "Bandage and antiseptic", "ta": "கட்டு, ஆன்டிசெப்டிக்", "price": 60, "kind": "aid", "hurt": -15.0},
	"balm": {"en": "Pain balm", "ta": "வலி தைலம்", "price": 45, "kind": "aid", "hurt": -8.0, "stress": -4.0},
	"paracetamol": {"en": "Paracetamol, a strip", "ta": "பாராசிட்டமால், ஒரு அட்டை", "price": 30, "kind": "aid", "hurt": -10.0, "uses": 4},
	"torch": {"en": "Torch (LED)", "ta": "டார்ச் (LED)", "price": 220, "kind": "safety"},
	"whistle": {"en": "Whistle", "ta": "விசில்", "price": 30, "kind": "safety"},
	"pepper_spray": {"en": "Pepper spray", "ta": "பெப்பர் ஸ்ப்ரே", "price": 349, "kind": "safety"},
	"disc_lock": {"en": "Scooter disc lock", "ta": "ஸ்கூட்டர் டிஸ்க் லாக்", "price": 650, "kind": "safety"},
}

## What each kind of shop has on its shelves (the city's kiranas, tea stalls and medicals; the hill towns' too).
const STOCK := {
	"kirana": ["water", "banana", "biscuits", "bun", "ors", "torch", "whistle"],
	"tea": ["tea_flask", "vada_parcel", "bun", "water"],
	"medical": ["first_aid", "bandage", "balm", "paracetamol", "ors", "water"],
	"hardware": ["torch", "whistle", "pepper_spray", "disc_lock"],
	"fuel": ["water", "biscuits", "ors", "torch"],
	"restaurant": ["idli_parcel", "vada_parcel", "water"],
	"mess": ["idli_parcel", "water"],
}

## Shop names as their boards read them (generic, no real brands).
const SHOP_NAMES := {
	"kirana": {"en": "Kirana store", "ta": "மளிகைக் கடை"},
	"tea": {"en": "Tea stall", "ta": "டீக்கடை"},
	"medical": {"en": "Medical shop", "ta": "மருந்துக் கடை"},
	"hardware": {"en": "Hardware and electricals", "ta": "ஹார்டுவேர், எலக்ட்ரிகல்ஸ்"},
	"fuel": {"en": "Fuel station store", "ta": "பெட்ரோல் பங்க் கடை"},
	"restaurant": {"en": "Restaurant counter: parcels", "ta": "ஹோட்டல் கவுண்டர்: பார்சல்"},
	"mess": {"en": "Mess counter: parcels", "ta": "மெஸ் கவுண்டர்: பார்சல்"},
}


static func name_of(id: String, lang: String) -> String:
	var g: Dictionary = GOODS.get(id, {})
	return str(g.get(lang, g.get("en", id)))


## The bag: {id: count} (a kit's count is its uses left), in the save data so it lasts.
static func bag(save_data: Dictionary) -> Dictionary:
	if not save_data.has("goods") or not save_data["goods"] is Dictionary:
		save_data["goods"] = {}
	return save_data["goods"]


static func add(save_data: Dictionary, id: String, n := 1) -> void:
	var b := bag(save_data)
	b[id] = int(b.get(id, 0)) + n * int(GOODS[id].get("uses", 1))


static func has(save_data: Dictionary, id: String) -> bool:
	return int(bag(save_data).get(id, 0)) > 0


static func take(save_data: Dictionary, id: String) -> bool:
	var b := bag(save_data)
	if int(b.get(id, 0)) <= 0:
		return false
	b[id] = int(b[id]) - 1
	if int(b[id]) <= 0:
		b.erase(id)
	return true
