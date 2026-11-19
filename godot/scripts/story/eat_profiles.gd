extends RefCounted
## How each thing on the table is eaten (the universal eating brief's FoodInteractionProfile): data, not code per
## dish. eater.gd reads a part's profile and builds every bite from it; a new dish needs a profile (or a method name),
## never a new controller.
##
## Where a part's profile comes from, first found:
##   1. the part itself: food_kit.gd may put "eat": "<method>" on a part (a burger's bun, a cup of tea)
##   2. the dish in story/food.json: "eat": {"method": ..., any field below to override}
##   3. the part's name: a side (sambar, chutney, masala, curry...), a bread, rice, or else a soft piece (_kind_of)
##
## A method's fields:
##   hand       "right" | "both"                       which hand takes it (the left rests, holds or steadies)
##   grip       "pinch" | "scoop" | "spoon" | "wrap" | "hold"
##                pinch: thumb to the index fingertip, the middle under it (a torn piece, an idli piece)
##                scoop: the four fingertips together, the thumb behind (rice gathered on the fingers)
##                spoon / fork: the handle between the thumb and the first two fingers
##                wrap: the fingers round a tumbler or a glass, the thumb opposite
##                hold: the fingers under, the thumb over (a burger in both hands, a slice of pizza)
##   piece      "torn" | "lump" | "ball" | "spoonful" | "whole" | "sip"
##                what reaches his mouth: a torn bit, a soft lump, a ball of rice, the spoon's load, the thing itself
##                (a slice, a burger: bitten, it gets smaller), a sip (the level in the cup goes down)
##   size       the piece's size (m, about): a bite-sized portion, never the dish
##   hold       for a pinch: how far apart the thumb and index stop (m): the thing's thickness where it's held (a
##              torn bread's edge 7 mm, an idli piece 14 mm, a slice's crust 10 mm); the other grips have their own
##   dip        dips it in a side (sambar, masala, curry) when there's one with something left
##   mix        mixes it with a side on the plate first (rice and sambar)
##   left       "rest" | "hold_bread" | "hold_bowl" | "hold_item"   the left hand's part
##   utensil    "" | "spoon" | "fork"
##   tilt       a cup or glass tipped this much at the lips (radians)
##   chew       [min, max] seconds of chewing after the bite (0 for a sip: a swallow)
##   pace       the bite's length (s, about; each bite varied round it)
##   lift_from  where his fingers take it: "near_rim" (the near edge, on top), "surface", "whole" (the thing lifted)

const METHODS := {
	"tear_dip": {"hand": "right", "grip": "pinch", "hold": 0.007, "piece": "torn", "size": 0.024, "dip": true, "left": "hold_bread",
		"chew": [1.6, 2.6], "pace": 3.4, "lift_from": "near_rim"},
	"pinch_dip": {"hand": "right", "grip": "pinch", "hold": 0.014, "piece": "lump", "size": 0.02, "dip": true, "left": "rest",
		"chew": [1.4, 2.2], "pace": 3.1, "lift_from": "near_rim"},
	"mix_scoop": {"hand": "right", "grip": "scoop", "piece": "ball", "size": 0.022, "mix": true, "left": "rest",
		"chew": [1.6, 2.4], "pace": 3.8, "lift_from": "surface"},
	"scoop": {"hand": "right", "grip": "scoop", "piece": "ball", "size": 0.02, "left": "rest",
		"chew": [1.4, 2.2], "pace": 2.9, "lift_from": "surface"},
	"side_scoop": {"hand": "right", "grip": "scoop", "piece": "ball", "size": 0.016, "left": "rest",
		"chew": [0.8, 1.4], "pace": 2.6, "lift_from": "surface"},
	"spoon": {"hand": "right", "grip": "spoon", "piece": "spoonful", "size": 0.018, "utensil": "spoon",
		"left": "hold_bowl", "chew": [0.5, 1.2], "pace": 2.6, "lift_from": "surface"},
	"fork": {"hand": "right", "grip": "spoon", "piece": "spoonful", "size": 0.02, "utensil": "fork", "twirl": true,
		"left": "hold_bowl", "chew": [1.4, 2.2], "pace": 3.4, "lift_from": "surface"},
	"hold_one": {"hand": "right", "grip": "pinch", "hold": 0.01, "piece": "whole", "size": 0.0, "left": "rest",
		"chew": [1.6, 2.6], "pace": 3.6, "lift_from": "whole"},
	"hold_two": {"hand": "both", "grip": "hold", "piece": "whole", "size": 0.0, "left": "hold_item",
		"chew": [2.0, 3.0], "pace": 4.2, "lift_from": "whole"},
	"sip_cup": {"hand": "right", "grip": "wrap", "piece": "sip", "size": 0.0, "left": "rest", "tilt": 0.55,
		"chew": [0.0, 0.0], "pace": 3.6, "lift_from": "whole"},
	"sip_glass": {"hand": "right", "grip": "wrap", "piece": "sip", "size": 0.0, "left": "rest", "tilt": 0.7,
		"chew": [0.0, 0.0], "pace": 3.8, "lift_from": "whole"},
}

const BREADS := ["poori", "dosa", "chapati", "parotta", "appam", "idiyappam", "roti", "naan", "paratha"]
const RICES := ["rice", "meals", "pongal", "upma", "curd", "lemon", "tomato", "biryani", "puttu"]   # (puttu crumbles:
                                                                                                 #  mixed with kadala)
const SIDES := ["sambar", "chutney", "masala", "kurma", "salna", "curry", "stew", "kadala", "rasam", "poriyal",
	"kuzhambu", "pickle", "dal", "ketchup", "sauce", "mayo"]


## A part's kind from its name: "side" (what things are dipped in or mixed with), "bread", "rice" or "piece".
static func kind_of(part: Dictionary) -> String:
	var lab := str(part.get("label", "")).to_lower()
	for w in SIDES:
		if lab.contains(w):
			return "side"
	if part.get("how", "") == "level" and not part.has("eat"):
		return "side"
	for w in BREADS:
		if lab.contains(w):
			return "bread"
	for w in RICES:
		if lab.contains(w):
			return "rice"
	return "piece"


## The method name for a part (see the top).
static func method_of(part: Dictionary, dish: Dictionary = {}) -> String:
	if part.has("eat"):
		return str(part["eat"])
	var de = dish.get("eat", {})
	if de is Dictionary and de.has("method") and kind_of(part) != "side":
		return str(de["method"])
	match kind_of(part):
		"side":
			return "side_scoop"
		"bread":
			return "tear_dip"
		"rice":
			return "mix_scoop"
	return "pinch_dip"


## The whole profile for a part: its method's fields, the dish's overrides on top, "method" set.
static func profile(part: Dictionary, dish: Dictionary = {}) -> Dictionary:
	var m := method_of(part, dish)
	var p: Dictionary = (METHODS.get(m, METHODS["pinch_dip"]) as Dictionary).duplicate(true)
	var de = dish.get("eat", {})
	if de is Dictionary and kind_of(part) != "side" and not part.has("eat"):
		for k in de:
			p[k] = de[k]
	p["method"] = m
	return p


## Whether a part is something the others are dipped in or mixed with (not eaten on its own first).
static func is_side(part: Dictionary) -> bool:
	return kind_of(part) == "side" and not part.has("eat")
