extends SceneTree
# Run: Godot --headless --path godot --script res://tests/standing_test.gd   (prints PASS or FAIL, exit code 0 or 1)
# standing.gd on its own: settle once per flag, notices once, conditions, and an old save rebuilt from flags.
class FakeBail:
	var suspicion := 30.0
	var strikes: Array = []
	var lates := 0
class FakeCity:
	var bail = FakeBail.new()
	var money = null
	var fines = null

func _init() -> void:
	var S = load("res://scripts/story/standing.gd")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://story/slice.json"))
	var ok := true
	var st = S.new()
	var city := FakeCity.new()
	st.setup(city, data)
	var flags := {"honest_watchman": true, "trap_went": true}
	var n: Array = st.settle(flags)
	ok = ok and is_equal_approx(st.trust_of("muniyandi"), 75.0) and is_equal_approx(city.bail.suspicion, 35.0)
	st.settle(flags)                                   # again: nothing counted twice
	ok = ok and is_equal_approx(city.bail.suspicion, 35.0)
	flags["lied_home"] = true
	flags["pm_paid"] = true
	n = st.settle(flags)                               # 35 + 15 + 8 = 58: no notice yet
	ok = ok and n.is_empty() and is_equal_approx(city.bail.suspicion, 58.0)
	flags["bribed_watchman"] = true
	n = st.settle(flags)                               # 63: Selvi's notice, once
	ok = ok and n.size() == 1 and str(n[0]["text"]["en"]).begins_with("The inspector")
	ok = ok and st.settle(flags).is_empty()
	ok = ok and st.allows({"suspicion": ">=60", "trust.muniyandi": ">60"}) and not st.allows({"trust.muniyandi": "<30"})
	var saved: Dictionary = st.save()
	var st2 = S.new()
	st2.setup(city, data)
	st2.load(saved, flags)
	ok = ok and is_equal_approx(st2.trust_of("muniyandi"), st.trust_of("muniyandi")) and st2.applied.size() == st.applied.size()
	var st3 = S.new()                                  # an old save: no standing, its flags replayed (suspicion left as saved)
	st3.setup(city, data)
	st3.load({}, flags)
	ok = ok and is_equal_approx(st3.trust_of("muniyandi"), 65.0) and st3.settle(flags).size() <= 1 and is_equal_approx(city.bail.suspicion, 63.0)
	print("STANDING TEST " + ("PASS" if ok else "FAIL") + "  " + st.summary())
	quit(0 if ok else 1)
