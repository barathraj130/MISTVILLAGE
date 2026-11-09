extends Control
## Karthik's bag (B): what he has bought and carries (goods.gd), each with how many. ↑↓ choose, Enter eat / use,
## B or Esc close. Food and drink feed him, first aid heals what hurts (life.gd); the safety things are for carrying
## (the torch: T at night; the whistle and spray do their part on their own when he needs them).

const Goods := preload("res://scripts/city/goods.gd")

var city                                     # city_test.gd: life, fines, hud, story
var lang := "en"
var font: Font
var _sel := 0
var _keys := {}
var _t := 0.0
var msg := ""


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _items() -> Array:
	var b: Dictionary = Goods.bag(city.fines._save_data)
	var out: Array = b.keys()
	out.sort()
	return out


func toggle() -> void:
	visible = not visible
	_sel = 0
	_t = 0.0
	msg = ""
	lang = city.story.lang if city.story else "en"


## Use one (by id): what it does to him, and the message for it.
func use(id: String) -> String:
	var g: Dictionary = Goods.GOODS[id]
	var life = city.life
	match str(g["kind"]):
		"food", "drink":
			if life and life.energy > 92.0 and float(g.get("energy", 0.0)) > 8.0:
				return L("(Not hungry now.)", "(இப்போ பசிக்கல.)")
		"aid":
			if life and life.hurt < 3.0:
				return L("(Nothing hurts. Keep it for later.)", "(எதுவும் வலிக்கல. அப்புறத்துக்கு வச்சுக்கலாம்.)")
		"safety":
			return L("(In the bag, for when it's needed.)", "(பையில இருக்கு, தேவைப்படும்போது.)")
	Goods.take(city.fines._save_data, id)
	if life:
		life.energy = clampf(life.energy + float(g.get("energy", 0.0)), 0.0, 100.0)
		life.hurt = clampf(life.hurt + float(g.get("hurt", 0.0)), 0.0, 100.0)
		life.add_stress(float(g.get("stress", 0.0)))
		life.save()
	print("BAG used %s: energy %.0f hurt %.0f" % [id, life.energy if life else 0.0, life.hurt if life else 0.0])
	return L("Used: %s" % Goods.name_of(id, "en"), "பயன்படுத்தியாச்சு: %s" % Goods.name_of(id, "ta"))


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	queue_redraw()
	var items := _items()
	if _t < 0.2:
		return
	for pair in [[KEY_UP, "up"], [KEY_DOWN, "down"], [KEY_ENTER, "use"], [KEY_KP_ENTER, "use"], [KEY_ESCAPE, "close"]]:
		var down := Input.is_key_pressed(pair[0])
		if down and not _keys.get(pair[1], false):
			match pair[1]:
				"up":
					_sel = maxi(_sel - 1, 0)
				"down":
					_sel = mini(_sel + 1, maxi(items.size() - 1, 0))
				"use":
					if _sel < items.size():
						msg = use(items[_sel])
						_sel = mini(_sel, maxi(_items().size() - 1, 0))
				"close":
					visible = false
		_keys[pair[1]] = down


func _draw() -> void:
	var s := get_viewport_rect().size
	var items := _items()
	var h := 120.0 + maxf(items.size(), 1) * 40.0
	var box := Rect2(s.x - 480.0, s.y * 0.5 - h * 0.5, 440.0, h)
	draw_rect(box, Color(0.08, 0.08, 0.09, 0.88))
	draw_string(font, box.position + Vector2(20, 38), L("Bag", "பை"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1))
	if items.is_empty():
		draw_string(font, box.position + Vector2(20, 84), L("Empty. Shops sell food, first aid and more.", "காலி. கடைகள்ல சாப்பாடு, முதலுதவி எல்லாம் கிடைக்கும்."), HORIZONTAL_ALIGNMENT_LEFT, 400.0, 15, Color(1, 1, 1, 0.7))
	for i in items.size():
		var y := box.position.y + 60.0 + i * 40.0
		if i == _sel:
			draw_rect(Rect2(box.position.x + 10.0, y, box.size.x - 20.0, 34.0), Color(1, 1, 1, 0.12))
		var n := int(Goods.bag(city.fines._save_data)[items[i]])
		draw_string(font, Vector2(box.position.x + 20.0, y + 24.0), Goods.name_of(items[i], lang), HORIZONTAL_ALIGNMENT_LEFT, 320.0, 17, Color(1, 1, 1, 0.95))
		var kit := int(Goods.GOODS[items[i]].get("uses", 1)) > 1          # (a kit or a strip: uses left, not pieces)
		draw_string(font, Vector2(box.end.x - (110.0 if kit else 70.0), y + 24.0), (L("%d left", "%d மீதி") % n) if kit else "× %d" % n,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.8, 0.45))
	draw_string(font, Vector2(box.position.x + 20.0, box.end.y - 22.0), msg if msg != "" else L("↑↓ · Enter: eat / use · B: close", "↑↓ · Enter: சாப்பிடு / பயன்படுத்து · B: மூடு"), HORIZONTAL_ALIGNMENT_LEFT, 400.0, 14, Color(1, 1, 1, 0.75))
