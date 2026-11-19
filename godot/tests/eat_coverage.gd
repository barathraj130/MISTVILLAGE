extends SceneTree
## (testing) The eating system's coverage: every dish in story/food.json built by food_kit.gd, each part with the
## method its profile resolves to (eat_profiles.gd), where it's served (home rotation, eateries' menus), and whether
## anything is left without a method of its own (a part falling to the default). One line per dish:
##   godot --headless --path . --audio-driver Dummy --script tests/eat_coverage.gd

const Kit := preload("res://scripts/story/food_kit.gd")
const Food := preload("res://scripts/story/food.gd")
const Prof := preload("res://scripts/story/eat_profiles.gd")


func _init() -> void:
	var d: Dictionary = Food.data()
	var where := {}
	for slot in d["home"]:
		for e in d["home"][slot]:
			where[str(e["dish"])] = where.get(str(e["dish"]), []) + ["home " + str(slot)]
	for k in d["eateries"]:
		for m in d["eateries"][k]["menu"]:
			for it in m["items"]:
				where[str(it[0])] = where.get(str(it[0]), []) + [str(k)]
	var methods := {}
	for id in d["dishes"]:
		var root := Kit.build(str(id))
		var seen := {}
		var defaulted := []
		for p in (root.get_meta("parts") as Array):
			var m := Prof.method_of(p, Food.dish(str(id)))
			var lab := str(p["label"])
			seen["%s: %s" % [lab, m]] = true
			methods[m] = methods.get(m, 0) + 1
			if not p.has("eat") and Prof.kind_of(p) == "piece" and m == "pinch_dip" and not lab in ["idli", "vada", "paniyaram", "pongal", "fries"]:
				defaulted.append(lab)
		var util := str(root.get_meta("utensil_kind", ""))
		print("COVER %-16s %-34s %s%s%s" % [id, ", ".join(PackedStringArray(where.get(str(id), ["(story only)"]))),
			"; ".join(PackedStringArray(seen.keys())), ("  [utensil: %s]" % util) if util != "" else "",
			("  CHECK default: %s" % ", ".join(PackedStringArray(defaulted))) if not defaulted.is_empty() else ""])
		root.free()
	print("COVER methods used: ", methods)
	quit()
