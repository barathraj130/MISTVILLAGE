extends Control
## The dealership's paperwork on screen (the prologue's "dealer" and "finance_desk" steps, story.gd):
##   card      a display vehicle's card, as on the stand beside it: the name, what kind, the specifications (engine,
##             power, mileage, tank, weight, seat height, brakes) and the on-road price broken down (ex-showroom,
##             registration, insurance, accessories). "Choose this one" or "Back".
##   finance   the finance officer's desk: for each vehicle chosen, its on-road price, a trade-in where there is one,
##             the down payment (a slider, from the lender's minimum), the tenure (12, 18, 24 or 36 months), the rate,
##             and the EMI worked out as you change them (finance.gd: P·r·(1+r)^n / ((1+r)^n − 1), rounded to the
##             rupee), the total interest, what he pays now against what he has. "Sign the loan papers" or "Not now".
## Mouse, or the keyboard: Enter confirms, Esc goes back.

const Finance := preload("res://scripts/city/finance.gd")

signal card_closed(chosen: bool)
signal finance_done(result: Dictionary)      # {"ok": bool, "plans": [{"id", "down", "months", "emi"}]}

var lang := "en"
var mode := ""                               # "card" | "finance"
var _panel: PanelContainer
var _box: VBoxContainer
var _items: Array = []                       # finance: [{model, trade_in, down (₹), months}]
var _cfg := {}
var _cash := 0
var _sum: Label
var _ok_btn: Button
var _rows: Array = []                        # finance: per item, its labels to refresh


func L(en: String, ta: String) -> String:
	return ta if lang == "ta" else en


func t_(d) -> String:
	return str(d.get(lang, d.get("en", ""))) if d is Dictionary else str(d)


static func on_road(m: Dictionary) -> int:
	return int(m["ex_showroom"]) + int(m.get("rto", 0)) + int(m.get("insurance", 0)) + int(m.get("accessories", 0))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _frame(width: float) -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = get_viewport_rect().size
	add_child(dim)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.085, 0.97)
	sb.border_color = Color(0.62, 0.05, 0.06)
	sb.border_width_top = 4
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(width, 0)
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	var cc := CenterContainer.new()                 # (the panel in the middle of the screen, whatever its size)
	cc.position = Vector2.ZERO
	cc.size = vp
	add_child(cc)
	var scroll := ScrollContainer.new()             # (a tall desk scrolls on a small window)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width + 60, minf(get_viewport_rect().size.y - 60.0, 880.0))
	cc.add_child(scroll)
	scroll.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _label(text: String, sz := 18, col := Color(0.9, 0.9, 0.9), parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	(parent if parent else _box).add_child(l)
	return l


func _row(parent: Control, left: String, right: String, col := Color(0.85, 0.85, 0.85)) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var a := _label(left, 16, Color(0.6, 0.62, 0.66), h)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _label(right, 16, col, h)


func _button(text: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(190, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _close() -> void:
	visible = false
	mode = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---- the card ----
func open_card(m: Dictionary, already_chosen := false) -> void:
	mode = "card"
	_frame(560)
	_label(t_(m["name"]), 28, Color(1, 1, 1))
	_label(t_(m.get("kind_label", {})), 16, Color(0.95, 0.55, 0.5))
	_box.add_child(HSeparator.new())
	for s in m.get("specs", []):
		_row(_box, t_(s[0]), str(s[1]))
	_box.add_child(HSeparator.new())
	_row(_box, L("Ex-showroom", "ஷோரூம் விலை"), Finance.rupees(int(m["ex_showroom"]) * 100, false))
	_row(_box, L("Registration (RTO)", "பதிவு (RTO)"), Finance.rupees(int(m.get("rto", 0)) * 100, false))
	_row(_box, L("Insurance (1 + 5 years)", "காப்பீடு (1 + 5 ஆண்டு)"), Finance.rupees(int(m.get("insurance", 0)) * 100, false))
	if int(m.get("accessories", 0)) > 0:
		_row(_box, L("Accessories (guard, mats, helmet)", "உபகரணங்கள் (கார்டு, மேட், ஹெல்மெட்)"), Finance.rupees(int(m["accessories"]) * 100, false))
	_row(_box, L("On-road price", "ஆன்-ரோடு விலை"), Finance.rupees(on_road(m) * 100, false), Color(1, 0.85, 0.4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_box.add_child(h)
	if m.get("display_only", false):                  # (on show, not within what he came for: look, and back)
		_label(t_(m.get("note", {"en": "More than he came to spend.", "ta": "அவர் செலவழிக்க வந்ததை விட அதிகம்."})), 15, Color(0.75, 0.75, 0.78))
		_button(L("Back", "திரும்ப"), func() -> void:
			_close()
			card_closed.emit(false), h)
		return
	_button(L("Chosen ✓", "தேர்ந்தெடுத்தது ✓") if already_chosen else L("Choose this one", "இதை தேர்வு செய்"), func() -> void:
		_close()
		card_closed.emit(true), h)
	_button(L("Back", "திரும்ப"), func() -> void:
		_close()
		card_closed.emit(false), h)


# ---- the finance desk ----
## items: [{"model", "trade_in" (₹)}]; cfg: {"lender", "rate_pa", "tenures", "min_down_pct", "default_months"}.
func open_finance(items: Array, cfg: Dictionary, cash: int) -> void:
	mode = "finance"
	_cfg = cfg
	_cash = cash
	_items = []
	_rows = []
	_frame(760)
	_label(L("Finance desk: %s" % str(cfg.get("lender", "")), "நிதி மேசை: %s" % str(cfg.get("lender", ""))), 24, Color(1, 1, 1))
	_label(L("Rate %.1f%% a year, reducing balance. Minimum down payment %d%% of the on-road price." % [float(cfg["rate_pa"]) * 100.0, int(cfg["min_down_pct"])],
		"வட்டி ஆண்டுக்கு %.1f%%, குறையும் இருப்பு. குறைந்தபட்ச முன்பணம் ஆன்-ரோடு விலையில் %d%%." % [float(cfg["rate_pa"]) * 100.0, int(cfg["min_down_pct"])]), 15, Color(0.65, 0.67, 0.7))
	for it in items:
		var m: Dictionary = it["model"]
		var price := on_road(m)
		var trade := int(it.get("trade_in", 0))
		var min_down := maxi(int(ceil(float(price) * float(cfg["min_down_pct"]) / 100.0 / 500.0)) * 500 - trade, 0)
		var rec := {"model": m, "trade_in": trade, "down": maxi(min_down, 0), "min_down": min_down, "months": int(cfg.get("default_months", 24))}
		_items.append(rec)
		_box.add_child(HSeparator.new())
		_label(t_(m["name"]) + (L("  (for Divya)", "  (திவ்யாவுக்கு)") if str(it.get("rider", "")) == "divya" else ""), 20, Color(1, 0.85, 0.4))
		_row(_box, L("On-road price", "ஆன்-ரோடு விலை"), Finance.rupees(price * 100, false))
		if trade > 0:
			_row(_box, L("Old scooter taken in exchange", "பழைய ஸ்கூட்டர் மாற்று மதிப்பு"), "− " + Finance.rupees(trade * 100, false), Color(0.6, 0.9, 0.6))
		var dl := _row(_box, L("Down payment", "முன்பணம்"), "")
		var sl := HSlider.new()
		sl.min_value = min_down
		sl.max_value = maxi(price - trade - 5000, min_down)
		sl.step = 500
		sl.value = min_down
		sl.custom_minimum_size = Vector2(0, 26)
		var track := StyleBoxFlat.new()                 # (the slider's track, visible on the dark panel)
		track.bg_color = Color(0.32, 0.33, 0.36)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		var filled := StyleBoxFlat.new()
		filled.bg_color = Color(0.85, 0.3, 0.3)
		filled.content_margin_top = 3
		filled.content_margin_bottom = 3
		sl.add_theme_stylebox_override("slider", track)
		sl.add_theme_stylebox_override("grabber_area", filled)
		sl.add_theme_stylebox_override("grabber_area_highlight", filled)
		_box.add_child(sl)
		var th := HBoxContainer.new()
		th.add_theme_constant_override("separation", 6)
		_box.add_child(th)
		_label(L("Tenure:", "காலம்:"), 16, Color(0.6, 0.62, 0.66), th)
		var group := ButtonGroup.new()
		for n in cfg["tenures"]:
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.text = L("%d months" % int(n), "%d மாதம்" % int(n))
			b.button_pressed = int(n) == int(rec["months"])
			b.pressed.connect(func() -> void:
				rec["months"] = int(n)
				_refresh())
			th.add_child(b)
		var loan_l := _row(_box, L("Loan amount", "கடன் தொகை"), "")
		var emi_l := _row(_box, L("EMI", "மாத தவணை (EMI)"), "", Color(1, 1, 1))
		var int_l := _row(_box, L("Total interest over the loan", "மொத்த வட்டி"), "")
		sl.value_changed.connect(func(v: float) -> void:
			rec["down"] = int(v)
			_refresh())
		_rows.append({"rec": rec, "down": dl, "loan": loan_l, "emi": emi_l, "interest": int_l})
	_box.add_child(HSeparator.new())
	_sum = _label("", 18, Color(1, 1, 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_box.add_child(h)
	_ok_btn = _button(L("Sign the loan papers", "கடன் ஆவணங்களில் கையெழுத்து"), _confirm, h)
	_button(L("Not now", "இப்போ வேண்டாம்"), func() -> void:
		_close()
		finance_done.emit({"ok": false, "plans": []}), h)
	_refresh()


func plan_of(rec: Dictionary) -> Dictionary:
	var price := on_road(rec["model"])
	var p := (price - int(rec["trade_in"]) - int(rec["down"])) * 100
	var sch := Finance.schedule(p, float(_cfg["rate_pa"]), int(rec["months"]))
	var interest := 0
	for r in sch:
		interest += int(r["interest"])
	return {"principal": p, "emi": Finance.emi_rounded(p, float(_cfg["rate_pa"]), int(rec["months"])), "interest": interest}


func now_due() -> int:
	var n := 0
	for rec in _items:
		n += int(rec["down"])
	return n


func _refresh() -> void:
	var monthly := 0
	for r in _rows:
		var rec: Dictionary = r["rec"]
		var pl := plan_of(rec)
		(r["down"] as Label).text = Finance.rupees(int(rec["down"]) * 100, false)
		(r["loan"] as Label).text = Finance.rupees(int(pl["principal"]), false)
		(r["emi"] as Label).text = L("%s a month × %d" % [Finance.rupees(int(pl["emi"]), false), int(rec["months"])],
			"மாதம் %s × %d" % [Finance.rupees(int(pl["emi"]), false), int(rec["months"])])
		(r["interest"] as Label).text = Finance.rupees(int(pl["interest"]), true)
		monthly += int(pl["emi"])
	var due := now_due()
	_sum.text = L("To pay now: %s of the %s he has.   Every month from now: %s in EMIs." % [Finance.rupees(due * 100, false), Finance.rupees(_cash * 100, false), Finance.rupees(monthly, false)],
		"இப்போ கட்ட வேண்டியது: %s (கையில் %s).   இனி மாதா மாதம் EMI: %s." % [Finance.rupees(due * 100, false), Finance.rupees(_cash * 100, false), Finance.rupees(monthly, false)])
	_sum.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if due > _cash else Color(1, 1, 1))
	_ok_btn.disabled = due > _cash


func _confirm() -> void:
	if now_due() > _cash:
		return
	var plans: Array = []
	for rec in _items:
		var pl := plan_of(rec)
		plans.append({"id": str(rec["model"]["id"]), "down": int(rec["down"]), "months": int(rec["months"]), "emi": int(pl["emi"]),
			"principal": int(pl["principal"]), "trade_in": int(rec["trade_in"])})
	_close()
	finance_done.emit({"ok": true, "plans": plans})


## (testing) the lender's minimum down payments, the default tenure, confirmed.
func auto() -> void:
	if mode == "card":
		_close()
		card_closed.emit(true)
	elif mode == "finance":
		_confirm()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed:
		return
	var k := (e as InputEventKey).keycode
	if k == KEY_ESCAPE:
		var was := mode
		_close()
		if was == "card":
			card_closed.emit(false)
		else:
			finance_done.emit({"ok": false, "plans": []})
		get_viewport().set_input_as_handled()
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		if mode == "card":
			_close()
			card_closed.emit(true)
		elif mode == "finance" and not _ok_btn.disabled:
			_confirm()
		get_viewport().set_input_as_handled()
