"""
Street types and street life for the game tiles (docs/COIMBATORE_STREETS.md) — the same rules as the Blender
reference (tools/streetlife.py), written as data: every placed thing is (kind, x, y, z, angle, scale) in the game
frame; `angle` is the direction of the model's local +X (x = cos a, z = sin a); road-facing props are turned so
their local +Z (Blender -Y) faces the road. Pole runs become wire chains.
"""
import math
import random

TYPES = ["none", "arterial", "bazaar", "model", "colony", "oldtown", "industrial", "periurban"]
KINDS = ["pole", "stall0", "stall1", "thatched", "flex0", "flex1", "flex2", "shade0", "shade1", "shade2", "goods", "cart",
         "flowers", "sign", "bin", "bench", "drums", "kolam0", "kolam1", "transformer", "shrine", "school", "manhole",
         "bollard", "bike_scooter_0", "bike_scooter_2", "bike_motorcycle_1", "bike_motorcycle_3", "fleet_auto",
         "fleet_hatchback", "fleet_sedan", "fleet_lorry", "street_man_shirt_walk", "street_man_shirt_stand",
         "street_man_veshti", "street_man_lungi", "street_woman_saree_red", "street_woman_saree_green",
         "street_woman_saree_blue", "street_schoolboy", "veg_neem1", "veg_neem2", "veg_rain1", "veg_gul1", "veg_bush1",
         "veg_bush2", "veg_bush3", "veg_grass", "city_palm_1", "city_palm_2"]
K = {n: i for i, n in enumerate(KINDS)}
BIKES = ["bike_scooter_0", "bike_scooter_2", "bike_motorcycle_1", "bike_motorcycle_3"]
CARS = ["fleet_hatchback", "fleet_sedan"]
PEOPLE = [k for k in KINDS if k.startswith("street_")]
WALKERS = ["street_man_shirt_walk", "street_schoolboy"]
TREES = ["veg_neem1", "veg_neem2", "veg_rain1", "veg_gul1", "city_palm_1", "city_palm_2"]

DISTRICTS = {"oldtown": ((-899.0, 2860.0), 1200.0), "model": ((-1939.0, 1042.0), 900.0),
             "industrial_g": ((1318.0, -2410.0), 1300.0), "industrial_p": ((6136.0, -1003.0), 1500.0)}

# spacing (m) and weighted menu per type
PLAN = {
    "arterial": ((8, 16), {"bikes": 3, "car": 2, "flex": 1, "stall": 1, "autos": 2, "sign": 1, "bin": 1, "people": 3, "none": 2}),
    "bazaar": ((3, 6), {"bikes": 6, "shade": 4, "goods": 3, "cart": 2, "flowers": 2, "stall": 1, "flex": 1, "bin": 1, "people": 6}),
    "model": ((7, 12), {"tree": 4, "bench": 1, "bikes": 1, "car": 1, "people": 2, "bin": 1, "none": 1}),
    "colony": ((10, 22), {"car": 2, "bikes": 2, "drums": 1, "cart": 1, "people": 2, "none": 4}),
    "oldtown": ((4, 9), {"bikes": 4, "drums": 2, "goods": 1, "flowers": 1, "people": 3, "none": 1}),
    "industrial": ((14, 30), {"lorry": 3, "goods": 2, "stall": 1, "people": 1, "none": 3}),
    "periurban": ((20, 45), {"thatched": 1, "tree": 3, "bikes": 1, "people": 1, "none": 4}),
}


def in_district(name, x, z):
    (cx, cz), r = DISTRICTS[name]
    return math.hypot(x - cx, z - cz) < r


def street_type(cls, x, z, near_kinds):
    n = len(near_kinds)
    shops = sum(1 for k in near_kinds if k in ("shop_house", "commercial")) / max(n, 1)
    mills = sum(1 for k in near_kinds if k == "mill_shed")
    if cls in ("trunk", "motorway", "primary"):
        return "arterial"
    if (in_district("industrial_g", x, z) or in_district("industrial_p", x, z) or mills >= 2) and shops < 0.4:
        return "industrial"
    far = math.hypot(x, z) > 7000
    if n < 2 and far:
        return "periurban"
    if in_district("oldtown", x, z):
        return "bazaar" if (cls in ("secondary", "tertiary") or shops >= 0.4) else "oldtown"
    if cls in ("secondary", "tertiary"):
        if in_district("model", x, z):
            return "model"
        return "bazaar" if shops >= 0.45 else ("model" if n < 6 else "colony")
    if shops >= 0.6 and n >= 4:
        return "bazaar"
    if n < 1:
        return "periurban"
    return "colony"


def _angle(vx, vz):
    return math.atan2(vz, vx)


def facing(d, rw):
    """angle for a road-facing prop: local X along the street, local +Z (x × up) towards the road"""
    zx, zz = -d[1], d[0]                 # (x, z) of (d × up) for d = (dx, dz)
    if zx * rw[0] + zz * rw[1] < 0:
        d = (-d[0], -d[1])
    return _angle(d[0], d[1])


def place_walk(typ, fl, hw, pts, rng, out, wires):
    """Street life along one footpath strip (or street edge on streets without a footpath).
    pts: [(x, y, z)] the strip centre; fl & 4: the road is on the strip's right."""
    if typ not in PLAN or len(pts) < 2:
        return
    road_right = bool(fl & 4)
    spacing, menu = PLAN[typ]
    items = [k for k, w in menu.items() for _ in range(w)]
    footpath = typ in ("arterial", "bazaar", "model")
    along = 0.0
    next_thing = rng.uniform(*spacing)
    next_pole = rng.uniform(5, 20)
    next_kolam = rng.uniform(4, 10)
    gap = 25.0 if typ in ("oldtown", "bazaar") else 35.0
    poles = []

    def add(kind, x, y, z, a, s=1.0):
        out.append((K[kind], x, y, z, a, s))
    for i in range(len(pts) - 1):
        ax, ay, az = pts[i]
        cx, cy, cz = pts[i + 1]
        seg = math.hypot(cx - ax, cz - az)
        if seg < 0.05:
            continue
        d = ((cx - ax) / seg, (cz - az) / seg)
        rw = (d[1], -d[0]) if road_right else (-d[1], d[0])          # towards the road
        dy = 0.0 if footpath else -0.15                               # streets without a footpath are flush with the road

        def at(f, off, lift=0.0):
            return (ax + (cx - ax) * f + rw[0] * off, ay + (cy - ay) * f + dy + lift, az + (cz - az) * f + rw[1] * off)
        while road_right and next_pole <= along + seg:
            f = (next_pole - along) / seg
            off = -(hw - 0.2) if footpath else (hw - 0.4)
            p = at(f, off)
            add("pole", *p, _angle(rw[0], rw[1]))
            poles.append(p)
            next_pole += gap
        while next_thing <= along + seg:
            f = (next_thing - along) / seg
            item = items[rng.randrange(len(items))]
            edge = hw + 0.2                                            # the road edge from the strip centre
            if item == "bikes":
                for j in range(rng.randint(3, 7)):
                    q = at(f, edge - 0.9 if footpath else edge - 0.5)
                    a = _angle(rw[0], rw[1]) + rng.uniform(-0.25, 0.25)
                    add(rng.choice(BIKES), q[0] + d[0] * j * 0.85, q[1], q[2] + d[1] * j * 0.85, a)
            elif item == "car":
                q = at(f, edge + 1.2, -0.06 if footpath else 0.0)
                add(rng.choice(CARS), *q, _angle(*d) if road_right else _angle(-d[0], -d[1]))
            elif item == "autos":
                q = at(f, edge + 1.3, -0.06)
                for j in range(3):
                    add("fleet_auto", q[0] + d[0] * j * 3.2, q[1], q[2] + d[1] * j * 3.2, _angle(*d) if road_right else _angle(-d[0], -d[1]))
            elif item == "lorry":
                q = at(f, edge + 1.6, 0.0 if not footpath else -0.06)
                add("fleet_lorry", *q, _angle(*d) if road_right else _angle(-d[0], -d[1]))
            elif item == "stall":
                add(rng.choice(["stall0", "stall1"]), *at(f, -(hw - 0.9) if footpath else -1.6), facing(d, rw))
            elif item == "thatched":
                add("thatched", *at(f, -2.0), facing(d, rw))
            elif item == "flex":
                add(rng.choice(["flex0", "flex1", "flex2"]), *at(f, -(hw - 0.6)), facing(d, rw))
            elif item == "shade":
                add(rng.choice(["shade0", "shade1", "shade2"]), *at(f, -hw), facing(d, rw))
            elif item == "goods":
                add("goods", *at(f, -(hw - 0.6) if footpath else -1.0), _angle(*d))
            elif item == "cart":
                add("cart", *at(f, edge + 0.7, -0.05 if footpath else 0.0), _angle(*d))
            elif item == "flowers":
                add("flowers", *at(f, (hw - 0.75) if footpath else -0.6), _angle(*d))
            elif item == "sign":
                add("sign", *at(f, hw - 0.35), _angle(*d))
            elif item == "bin":
                add("bin", *at(f, -(hw - 0.6) if footpath else -0.6), _angle(*d))
            elif item == "bench":
                add("bench", *at(f, -(hw - 0.6)), facing(d, rw))
            elif item == "drums":
                add("drums", *at(f, -0.2 if footpath else -0.5), _angle(*d))
            elif item == "tree":
                q = at(f, (hw - 0.35) if footpath else -2.5)
                add(rng.choice(TREES), q[0], q[1] - 0.05, q[2], rng.uniform(0, 6.28), rng.uniform(0.8, 1.1))
            elif item == "people":
                for j in range(rng.randint(1, 3 if typ == "bazaar" else 2)):
                    kind = rng.choice(PEOPLE)
                    q = at(f, rng.uniform(-hw + 0.4, hw - 0.5) if footpath else rng.uniform(0.2, 1.0))
                    walk = kind in WALKERS
                    fwd = d if rng.random() < 0.5 else (-d[0], -d[1])
                    # MakeHuman faces local -Y (Godot +Z): its local X is fwd turned right
                    a = _angle(fwd[1], -fwd[0]) if walk else rng.uniform(0, 6.28)
                    add(kind, q[0] + d[0] * j * 0.7, q[1], q[2] + d[1] * j * 0.7, a)
            next_thing += rng.uniform(*spacing)
        while typ in ("colony", "oldtown") and next_kolam <= along + seg:
            f = (next_kolam - along) / seg
            q = at(f, hw + 0.2 - 0.25, 0.005)
            add(rng.choice(["kolam0", "kolam1"]), *q, _angle(*d), 0.9)
            next_kolam += rng.uniform(9, 16)
        along += seg
    if typ in ("colony", "oldtown") and len(pts) > 2 and rng.random() < 0.14:
        ex, ey, ez = pts[-1]
        px, _, pz = pts[-2]
        L = max(math.hypot(ex - px, ez - pz), 1e-6)
        d = ((ex - px) / L, (ez - pz) / L)
        rw = (d[1], -d[0]) if road_right else (-d[1], d[0])
        roll = rng.random()
        if roll < 0.55:
            out.append((K["transformer"], ex - d[0] * 6 - rw[0] * (hw + 1.0), ey - 0.15, ez - d[1] * 6 - rw[1] * (hw + 1.0), _angle(*d), 1.0))
        elif roll < 0.85:
            out.append((K["shrine"], ex - d[0] * 5 - rw[0] * (hw + 0.8), ey - 0.15, ez - d[1] * 5 - rw[1] * (hw + 0.8), facing(d, rw), 1.0))
        else:
            out.append((K["school"], ex - d[0] * 8 + rw[0] * (hw - 0.4), ey, ez - d[1] * 8 + rw[1] * (hw - 0.4), _angle(*d), 1.0))
    if len(poles) >= 2:
        wires.append((2 if typ in ("oldtown", "bazaar") else 1, poles))
