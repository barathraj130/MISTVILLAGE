"""
Indian junction signals, as they stand on Coimbatore's roads (our own design; design reference before the game):

  * a kerb pole on the left of each approach (India drives on the left), 4.8 m, galvanised, black-and-yellow
    bands at the foot — no long mast arm
  * the main head facing the approaching driver: red, amber, green (300 mm LED) under hoods, plain black housing
  * a row of green arrows under it (left, straight, right); the left arrow stays lit — FREE LEFT
  * a big two-digit countdown box on top of the head
  * a second head back to back, higher up, for the traffic coming the other way (with its own countdown)
  * a "maintained by" sponsor board on the pole (fictional sponsor)
  * at a corner of the bigger junctions, a traffic police umbrella booth: a round podium and a striped sponsor
    umbrella (fictional names)

    Blender -b --factory-startup --python tools/signal_india.py -- --out previews/signals_india
    Blender -b --factory-startup --python tools/signal_india.py -- --export     (game models)
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import traffic_signal as TS  # noqa: E402
from traffic_signal import LIT, box, cyl, hood, mat, obj, text_obj  # noqa: E402

SPONSOR = ("MAINTAINED BY", "SRI VELAN SILKS")
BOOTH_SPONSOR = "KOVAI SILKS"


def mats(state):
    """Materials and their indices for one installation in the given state."""
    lst = [mat("Galvanised", (0.42, 0.43, 0.44), 0.45, 0.8), mat("Stripe Black", (0.02, 0.02, 0.02), 0.6),
           mat("Stripe Yellow", (0.85, 0.62, 0.02), 0.5), mat("Concrete", (0.45, 0.44, 0.41), 0.9),
           mat("Housing", (0.015, 0.015, 0.016), 0.45)]
    I = {"pole": 0, "black": 1, "yellow": 2, "concrete": 3, "housing": 4}
    for c in ("red", "amber", "green"):
        I["lens_%s_on" % c] = len(lst)
        lst.append(TS.lens_mat(c, state == c))
        I["lens_%s_off" % c] = I["lens_%s_on" % c] if state == c else len(lst)
        if state != c:
            lst.append(TS.lens_mat(c, False))
    I["led"] = len(lst)
    lst.append(mat("SigTimer" if TS.GAME else "LED", (0.3, 0.02, 0.01), 0.3, 0,
                   LIT["green"] if state == "green" else LIT["red"], 0.0 if state == "amber" or TS.GAME else 30.0))
    I["led_off"] = len(lst)
    lst.append(mat("LED Off", (0.03, 0.02, 0.02), 0.3))
    for nm, key in (("Arrow Left", "arrow_l"), ("Arrow Straight", "arrow_s"), ("Arrow Right", "arrow_r")):
        I[key] = len(lst)
        lit = (key == "arrow_l") or (state == "green")
        lst.append(mat("SigArrow " + nm.split()[1] if TS.GAME else nm, (0.02, 0.06, 0.04), 0.2, 0, LIT["green"],
                       0.0 if TS.GAME else (28.0 if lit else 0.0)))
    I["white"] = len(lst)
    lst.append(mat("Sign White", (0.9, 0.9, 0.88), 0.4))
    I["red_band"] = len(lst)
    lst.append(mat("Sponsor Red", (0.6, 0.04, 0.04), 0.45))
    return lst, I


def arrow_row(bm, base, R, I, texts):
    """Three 200 mm green-arrow aspects in a row: a black box, round lenses under short hoods. In the game
    version each lens is a UV quad the arrow shader draws on; in the design the arrow is text on the lens."""
    box(bm, base, (0.78, 0.22, 0.28), I["housing"], R)
    fwd = R @ Vector((0, 1, 0))
    right = -(R @ Vector((1, 0, 0)))
    for k, key in enumerate(("arrow_l", "arrow_s", "arrow_r")):
        c = base + right * ((k - 1) * 0.25) + fwd * 0.115
        if TS.GAME:
            uv = bm.loops.layers.uv.verify()
            up = Vector((0, 0, 1))
            vs = [bm.verts.new(c - right * 0.09 - up * 0.09), bm.verts.new(c + right * 0.09 - up * 0.09),
                  bm.verts.new(c + right * 0.09 + up * 0.09), bm.verts.new(c - right * 0.09 + up * 0.09)]
            f = bm.faces.new(vs)
            f.material_index = I[key]
            for lp, t in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                lp[uv].uv = t
        else:
            cyl(bm, c - fwd * 0.005, c, 0.095, None, 20, I["housing"])
            texts.append((("←", "↑", "→")[k], c + fwd * 0.004, key))
        hood(bm, c, fwd, 0.105, 0.14, I["housing"])


def installation(state="red", count=45, back_state="red", back_count=45):
    """One approach's kerb pole at the origin: the main head faces Blender -Y (towards the driver coming up
    +Y), the road lies to +X. Returns the object (and lit text objects, in the design)."""
    lst, I = mats(state)
    bm = bmesh.new()
    texts = []
    # plinth, banded foot, pole
    box(bm, Vector((0, 0, 0.2)), (0.6, 0.6, 0.4), I["concrete"])
    for k in range(8):
        cyl(bm, Vector((0, 0, 0.4 + k * 0.2)), Vector((0, 0, 0.6 + k * 0.2)), 0.1, 0.099, 12,
            I["black"] if k % 2 == 0 else I["yellow"])
    cyl(bm, Vector((0, 0, 2.0)), Vector((0, 0, 4.9)), 0.095, 0.075, 12, I["pole"])
    cyl(bm, Vector((0, 0, 4.9)), Vector((0, 0, 4.95)), 0.1, 0.1, 12, I["pole"])
    # main head (facing -Y) on a short bracket towards the road, the arrows under it, the countdown on top
    R = Matrix.Rotation(math.pi, 3, 'Z')                       # local +Y (outward) → world -Y
    hc = Vector((0.32, -0.05, 3.05))
    box(bm, Vector((0.16, 0, 3.05)), (0.32, 0.08, 0.08), I["pole"])
    TS.head(bm, hc, Vector((0, -1, 0)), state, I, board=False)
    arrow_row(bm, hc + Vector((0, -0.05, -0.8)), R, I, texts)
    TS.countdown(bm, hc + Vector((0, 0.05, 0.86)), Vector((0, -1, 0)), count, I["led"], I["led_off"], I["housing"])
    # the back-to-back head for the opposite flow (facing +Y), higher, with its own countdown
    bc = Vector((0.0, 0.25, 4.15))
    lst_b_state = back_state
    TS.head(bm, bc, Vector((0, 1, 0)), lst_b_state, I, board=False)
    TS.countdown(bm, bc + Vector((0, -0.05, 0.86)), Vector((0, 1, 0)), back_count, I["led"], I["led_off"], I["housing"])
    # sponsor board facing the driver, below the head
    box(bm, Vector((0, -0.14, 1.72)), (0.95, 0.03, 0.62), I["white"])
    box(bm, Vector((0, -0.156, 1.95)), (0.95, 0.005, 0.16), I["red_band"])
    ob = obj(bm, "Signal pole", lst)
    t_objs = []
    if not TS.GAME:
        for glyph, loc, key in texts:
            t_objs.append(text_obj(glyph, loc, 0.0, 0.14, lst[I[key]], 0.002))
    t_objs.append(text_obj(SPONSOR[0], Vector((0, -0.16, 1.95)), 0.0, 0.08, lst[I["white"]], 0.002))
    t_objs.append(text_obj(SPONSOR[1], Vector((0, -0.16, 1.65)), 0.0, 0.12, lst[I["red_band"]], 0.002))
    return ob, t_objs


def police_booth():
    """A traffic police umbrella booth: an octagonal podium (white, blue band, TRAFFIC), a pole, an eight-panel
    umbrella in alternating red and white with a sponsor on the valance, at the origin."""
    lst = [mat("Booth White", (0.85, 0.85, 0.82), 0.6), mat("Booth Blue", (0.03, 0.12, 0.45), 0.5),
           mat("Umbrella Red", (0.7, 0.05, 0.04), 0.7), mat("Umbrella White", (0.88, 0.86, 0.8), 0.7),
           mat("Galvanised", (0.42, 0.43, 0.44), 0.45, 0.8), mat("Booth Black", (0.03, 0.03, 0.03), 0.6)]
    bm = bmesh.new()
    cyl(bm, Vector((0, 0, 0)), Vector((0, 0, 0.25)), 0.9, 0.9, 8, 0)
    cyl(bm, Vector((0, 0, 0.25)), Vector((0, 0, 1.05)), 0.8, 0.8, 8, 0)
    cyl(bm, Vector((0, 0, 0.75)), Vector((0, 0, 0.95)), 0.805, 0.805, 8, 1)
    cyl(bm, Vector((0, 0, 1.05)), Vector((0, 0, 1.12)), 0.86, 0.86, 8, 5)
    cyl(bm, Vector((0, 0, 1.12)), Vector((0, 0, 3.2)), 0.04, 0.04, 8, 4)
    # umbrella: 8 panels, alternating, and a valance
    apex = Vector((0, 0, 3.35))
    for k in range(8):
        a0, a1 = k * math.tau / 8, (k + 1) * math.tau / 8
        p0 = Vector((math.cos(a0) * 1.7, math.sin(a0) * 1.7, 2.85))
        p1 = Vector((math.cos(a1) * 1.7, math.sin(a1) * 1.7, 2.85))
        v = [bm.verts.new(apex), bm.verts.new(p0), bm.verts.new(p1)]
        f = bm.faces.new(v)
        f.material_index = 2 + (k % 2)
        q0, q1 = p0 - Vector((0, 0, 0.28)), p1 - Vector((0, 0, 0.28))
        f2 = bm.faces.new([bm.verts.new(p0), bm.verts.new(p1), bm.verts.new(q1), bm.verts.new(q0)])
        f2.material_index = 3 if k % 2 else 2
    ob = obj(bm, "Police booth", lst)
    t = [text_obj("TRAFFIC", Vector((0, -0.81, 0.85)), 0.0, 0.16, lst[0], 0.003)]
    for k in range(4):
        a = k * math.tau / 4 + math.tau / 16
        t.append(text_obj(BOOTH_SPONSOR, Vector((math.cos(a) * 1.69, math.sin(a) * 1.69, 2.71)), a + math.pi / 2, 0.13,
                          lst[3 if k % 2 == 0 else 2], 0.002))
    return ob, t


# ----------------------------------------------------------------------------- the design junction
def junction4():
    """A four-way junction, drive on the left: a main road along Y (14 m, undivided) crossing one along X (10 m)."""
    bm = bmesh.new()
    lst = [mat("Asphalt", (0.05, 0.05, 0.052), 0.85), mat("Paint White", (0.85, 0.85, 0.82), 0.6),
           mat("Kerb", (0.5, 0.49, 0.46), 0.8), mat("Footpath", (0.45, 0.4, 0.36), 0.85),
           mat("Kerb Black", (0.03, 0.03, 0.03), 0.7), mat("Kerb Yellow", (0.8, 0.62, 0.05), 0.6)]
    box(bm, Vector((0, 0, -0.05)), (14.0, 160.0, 0.1), 0)
    box(bm, Vector((0, 0, -0.049)), (160.0, 10.0, 0.1), 0)
    # stop lines and zebras on all four arms (stop line on the left half of each)
    for ang in range(4):
        Rz = Matrix.Rotation(ang * math.pi / 2, 3, 'Z')
        half_w, half_x = (7.0, 5.0) if ang % 2 == 0 else (5.0, 7.0)
        box(bm, Rz @ Vector((-half_w / 2, -half_x - 4.6, 0.002)), (half_w, 0.4, 0.004) if ang % 2 == 0 else (half_w, 0.4, 0.004), 1, Rz)
        for k in range(int(half_w * 2 / 1.75)):
            box(bm, Rz @ Vector((-half_w + 0.9 + k * 1.75, -half_x - 2.0, 0.002)), (0.9, 3.0, 0.004), 1, Rz)
        for k in range(8):
            box(bm, Rz @ Vector((0, -half_x - 9.0 - k * 6.0, 0.002)), (0.15, 3.0, 0.004), 1, Rz)
    # footpaths in the four corners (kerbs painted black and yellow near the junction)
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * (7.0 + 40.0), sy * (5.0 + 40.0), 0.075))
            box(bm, c, (80.0 - 0.0, 80.0, 0.15), 3)
            for k in range(14):
                box(bm, Vector((sx * 7.15, sy * (5.5 + k), 0.16)), (0.3, 1.0, 0.03), 4 + (k % 2))
                box(bm, Vector((sx * (7.5 + k), sy * 5.15, 0.16)), (1.0, 0.3, 0.03), 4 + (k % 2))
    obj(bm, "Junction", lst)


def place(ob_list, d, centre_gap, road_half):
    """Turn and place an approach's objects: d = travel direction (towards the junction), the pole on the left
    kerb just back from the stop line."""
    d = Vector((d[0], d[1], 0.0)).normalized()
    left = Vector((-d.y, d.x, 0))
    pos = -d * (centre_gap + 5.4) + left * (road_half + 0.7)
    rot = math.atan2(d.y, d.x) - math.pi / 2
    for o in ob_list:
        o.matrix_world = Matrix.Translation((pos.x, pos.y, 0.15)) @ Matrix.Rotation(rot, 4, 'Z') @ o.matrix_world


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--export" in args:
        export_game()
        return
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(HERE, "..", "previews", "signals_india")
    os.makedirs(out, exist_ok=True)
    sc = TS.setup(64)
    TS._M.clear()
    junction4()
    # main road (north-south) red 45 s; the cross road green 38 s
    for d, gap, half, st, cnt in (((0, 1), 5.0, 7.0, "red", 45), ((0, -1), 5.0, 7.0, "red", 45),
                                  ((1, 0), 7.0, 5.0, "green", 38), ((-1, 0), 7.0, 5.0, "green", 38)):
        ob, ts = installation(st, cnt, st, cnt)
        place([ob] + ts, d, gap, half)
    bo, bt = police_booth()
    for o in [bo] + bt:
        o.matrix_world = Matrix.Translation((10.5, 8.5, 0.15)) @ o.matrix_world
    shoot(sc, os.path.join(out, "india_driver.jpg"), (-3.5, -42.0, 1.35), (-1.0, 0.0, 3.0), 30)
    shoot(sc, os.path.join(out, "india_pole.jpg"), (-4.6, -15.5, 2.2), (-7.7, -10.4, 3.0), 30)
    shoot(sc, os.path.join(out, "india_junction.jpg"), (-16.0, -22.0, 7.5), (2.0, 3.0, 1.0), 24)


def shoot(sc, path, loc, target, lens):
    TS.shoot(sc, path, loc, target, lens)


def export_game():
    """Game models: the kerb pole (main head facing Blender -Y = the game's +Z, the road to +X) and the police
    booth. Lenses, arrows and countdown faces get named materials the game lights (SigLens / SigArrow /
    SigTimer)."""
    import export_life as EL
    TS.GAME = True
    for name, build in (("signal_india", lambda: installation("red", 0)), ("police_booth", police_booth)):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        TS._M.clear()
        ob, ts = build()
        for t in ts:
            bpy.ops.object.select_all(action='DESELECT')
            t.select_set(True)
            bpy.context.view_layer.objects.active = t
            bpy.ops.object.convert(target='MESH')
        out = os.path.join(HERE, "..", "godot", "assets", "city_props", name + ".glb")
        EL.export_objects([o for o in bpy.data.objects if o.type == 'MESH'], out)
        print("EXPORT", out, flush=True)


if __name__ == "__main__":
    main()
