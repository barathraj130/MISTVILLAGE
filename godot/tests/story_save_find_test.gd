extends SceneTree
## A save finds its step again after steps were inserted before it (story.gd _step_sig / _find_step).
##   Godot --headless --path godot -s tests/story_save_find_test.gd   → PASS / FAIL

func _initialize() -> void:
	var S = load("res://scripts/story/story.gd")
	var st = S.new()
	st.data = {"steps": [{"do": "home", "n": 0}, {"do": "talk", "n": 1}, {"do": "home", "n": 2}, {"do": "drive", "n": 3}]}
	var sig: String = st._step_sig(2)
	var ok := true
	ok = ok and st._find_step(2, sig) == 2                  # unchanged
	st.data["steps"].insert(1, {"do": "provoke", "n": 9})
	st.data["steps"].insert(1, {"do": "talk", "n": 8})
	ok = ok and st._find_step(2, sig) == 4                  # two steps inserted before it
	st.data["steps"].remove_at(0)
	ok = ok and st._find_step(2, sig) == 3                  # one taken out
	ok = ok and st._find_step(1, "") == 1                   # an old save without a fingerprint: its number
	print("PASS" if ok else "FAIL")
	st.free()
	quit(0 if ok else 1)
