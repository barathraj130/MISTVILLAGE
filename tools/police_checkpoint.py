"""
A police vehicle-checking point on a Coimbatore road — design reference in Blender (our own design; a fictional
force, NAGAR POLICE), before it goes into the game.

  * yellow steel crowd barricades with the NAGAR POLICE board, set in a chicane across the left carriageway so
    traffic has to slow and weave (India drives on the left)
  * orange cones with white reflective bands along the centre line
  * the bilingual board on an A-frame: நிறுத்தவும் / STOP / காவல் சோதனை · POLICE CHECKING
  * a police SUV (the game's SUV repainted white, a blue band, a red-and-blue light bar, NAGAR POLICE livery)
  * two traffic policemen in khaki (tools/humans/street_people.py): one in a fluorescent vest in the lane with a
    hand raised to stop the traffic, one by the SUV

    Blender -b --factory-startup --python tools/police_checkpoint.py -- --out previews/police
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
from traffic_signal import box, cyl, mat, obj  # noqa: E402

ROOT = os.path.join(HERE, "..")
BOARDS = os.path.join(ROOT, "art", "boards")


def img_mat(name, png, rough=0.5, emit=0.0):
    key = ("img", name)
    if key in TS._M:
        return TS._M[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.abspath(png), check_existing=True)
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    if emit:
        nt.links.new(t.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = emit
    TS._M[key] = m
    return m


def picture(bm, uv, centre, right, up, w, h, m):
    """A flat picture (a board's face): a quad with 0..1 UVs, facing right × up."""
    c = Vector(centre)
    vs = [bm.verts.new(c - right * w / 2 - up * h / 2), bm.verts.new(c + right * w / 2 - up * h / 2),
          bm.verts.new(c + right * w / 2 + up * h / 2), bm.verts.new(c - right * w / 2 + up * h / 2)]
    f = bm.faces.new(vs)
    f.material_index = m
    for lp, t in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp[uv].uv = t


def barricade(at, yaw):
    """A 2.4 m steel crowd barricade: end frames on splayed feet, top and bottom rails, bars between, painted
    yellow with black bands; the NAGAR POLICE board along its top half (both faces)."""
    lst = [mat("Barricade Yellow", (0.85, 0.62, 0.03), 0.45, 0.3), mat("Barricade Black", (0.02, 0.02, 0.02), 0.5, 0.2),
           img_mat("Barricade Board", os.path.join(BOARDS, "police_barricade.png"), 0.45)]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    L, H = 2.4, 1.1
    for sx in (-1, 1):
        x = sx * L / 2
        cyl(bm, (x, 0, 0.08), (x, 0, H), 0.025, None, 8, 0)
        for sy in (-1, 1):                                          # splayed feet
            cyl(bm, (x, 0, 0.1), (x, sy * 0.35, 0.0), 0.018, None, 6, 1)
    for z in (0.12, H):
        cyl(bm, (-L / 2, 0, z), (L / 2, 0, z), 0.022, None, 8, 0)
    for k in range(1, 20):
        x = -L / 2 + k * L / 20
        cyl(bm, (x, 0, 0.12), (x, 0, 0.62), 0.009, None, 6, 1 if (k // 2) % 2 else 0)
    box(bm, Vector((0, 0, 0.86)), (L - 0.1, 0.02, 0.44), 0)
    for sgn in (-1, 1):
        picture(bm, uv, (0, sgn * 0.0115, 0.86), Vector((-sgn, 0, 0)), Vector((0, 0, 1)), L - 0.16, 0.38, 2)
    ob = obj(bm, "Barricade", lst)
    ob.matrix_world = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, 'Z')
    return ob


def cone(at):
    lst = [mat("Cone Orange", (0.9, 0.25, 0.02), 0.5), mat("Cone White", (0.92, 0.92, 0.9), 0.3),
           mat("Cone Base", (0.03, 0.03, 0.03), 0.7)]
    bm = bmesh.new()
    box(bm, Vector((0, 0, 0.015)), (0.36, 0.36, 0.03), 2)
    cyl(bm, (0, 0, 0.03), (0, 0, 0.3), 0.13, 0.085, 16, 0)
    cyl(bm, (0, 0, 0.3), (0, 0, 0.44), 0.085, 0.058, 16, 1)
    cyl(bm, (0, 0, 0.44), (0, 0, 0.7), 0.058, 0.02, 16, 0)
    ob = obj(bm, "Cone", lst)
    ob.location = at
    return ob


def stop_board(at, yaw):
    """The bilingual STOP / POLICE CHECKING board on a folding A-frame stand."""
    lst = [mat("Stand", (0.12, 0.12, 0.13), 0.5, 0.4), img_mat("Stop Board", os.path.join(BOARDS, "police_check.png"), 0.4)]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    w, h = 1.2, 0.8
    for sx in (-1, 1):
        cyl(bm, (sx * 0.55, -0.3, 0.0), (sx * 0.55, 0.0, 1.75), 0.022, None, 6, 0)
        cyl(bm, (sx * 0.55, 0.3, 0.0), (sx * 0.55, 0.0, 1.75), 0.022, None, 6, 0)
    box(bm, Vector((0, 0.02, 1.35)), (w + 0.06, 0.03, h + 0.06), 0)
    picture(bm, uv, (0, -0.0, 1.35), Vector((1, 0, 0)), Vector((0, 0, 1)), w, h, 1)
    ob = obj(bm, "Stop board", lst)
    ob.matrix_world = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, 'Z')
    return ob


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    return new, roots


def police_suv(at, yaw):
    """The game's SUV, repainted white with a blue band, a red/blue light bar on the roof and the livery."""
    new, roots = import_glb(os.path.join(ROOT, "godot", "assets", "vehicles", "luxury_suv.glb"))
    for o in new:
        if o.type == 'MESH':
            for slot in o.material_slots:
                if slot.material and slot.material.name.startswith("SatinPaint"):
                    m = slot.material
                    p = m.node_tree.nodes.get("Principled BSDF")
                    if p:
                        for l in list(p.inputs["Base Color"].links):
                            m.node_tree.links.remove(l)
                        p.inputs["Base Color"].default_value = (0.86, 0.87, 0.88, 1)
    holder = bpy.data.objects.new("Police SUV", None)
    bpy.context.scene.collection.objects.link(holder)
    for r in roots:
        r.parent = holder
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in new if o.type == 'MESH' for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    # light bar, band and livery boards in the car's own frame (its long axis is the longer of x / y)
    along_y = (hi.y - lo.y) > (hi.x - lo.x)
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    lst = [mat("Bar Base", (0.05, 0.05, 0.06), 0.4), mat("Bar Red", (0.6, 0.02, 0.02), 0.2, 0, (1.0, 0.05, 0.03), 18.0),
           mat("Bar Blue", (0.02, 0.05, 0.6), 0.2, 0, (0.05, 0.2, 1.0), 18.0), mat("Police Blue", (0.03, 0.12, 0.5), 0.35),
           img_mat("Police Livery", os.path.join(BOARDS, "police_livery.png"), 0.35)]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    length = (hi.y - lo.y) if along_y else (hi.x - lo.x)
    width = (hi.x - lo.x) if along_y else (hi.y - lo.y)
    R = Matrix.Rotation(0.0 if along_y else math.pi / 2, 3, 'Z')
    roof = hi.z
    box(bm, Vector((cx, cy, roof + 0.05)), (1.2, 0.3, 0.1) if along_y else (0.3, 1.2, 0.1), 0)
    for k, m in ((-1, 1), (1, 2)):
        off = R @ Vector((k * 0.3, 0, 0))
        box(bm, Vector((cx, cy, roof + 0.13)) + off, (0.55, 0.26, 0.08) if along_y else (0.26, 0.55, 0.08), m)
    for side in (-1, 1):
        n = R @ Vector((side, 0, 0))
        t = R @ Vector((0, 1, 0))
        base = Vector((cx, cy, lo.z + (roof - lo.z) * 0.5)) + n * (width / 2 + 0.012)
        box(bm, base - Vector((0, 0, 0.12)), (0.006, length * 0.86, 0.09) if along_y else (length * 0.86, 0.006, 0.09), 3)
        picture(bm, uv, base + Vector((0, 0, 0.02)), t * (-side), Vector((0, 0, 1)), length * 0.5, length * 0.5 * 160 / 1024, 4)
    bar = obj(bm, "Police livery", lst)
    bar.parent = holder
    holder.matrix_world = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, 'Z')
    return holder


def policeman(name, at, yaw):
    new, roots = import_glb(os.path.join(ROOT, "godot", "assets", "people", name + ".glb"))
    holder = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(holder)
    for r in roots:
        r.parent = holder
    holder.matrix_world = Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, 'Z')
    return holder


def road():
    lst = [mat("Asphalt", (0.05, 0.05, 0.052), 0.85), mat("Paint White", (0.85, 0.85, 0.82), 0.6),
           mat("Kerb", (0.5, 0.49, 0.46), 0.8), mat("Footpath", (0.42, 0.38, 0.34), 0.85),
           mat("Ground", (0.3, 0.22, 0.14), 0.95)]
    bm = bmesh.new()
    box(bm, Vector((0, 0, -0.05)), (14.0, 220.0, 0.1), 0)
    for k in range(-18, 18):
        box(bm, Vector((0, k * 6.0, 0.002)), (0.15, 3.0, 0.004), 1)
    for sx in (-1, 1):
        box(bm, Vector((sx * 7.15, 0, 0.08)), (0.3, 220.0, 0.2), 2)
        box(bm, Vector((sx * 9.0, 0, 0.075)), (3.5, 220.0, 0.15), 3)
        box(bm, Vector((sx * 60.0, 0, -0.02)), (98.0, 220.0, 0.1), 4)
    obj(bm, "Road", lst)


def trees():
    import vegetation as VG
    VG._M.clear()
    src = [VG.neem(3), VG.raintree(2)]
    for o in src:
        o.location = (0, 0, -100)
    k = 0
    for sx in (-1, 1):
        for y in range(-60, 100, 18):
            inst = bpy.data.objects.new("tree", src[k % 2].data)
            bpy.context.scene.collection.objects.link(inst)
            inst.location = (sx * (10.5 + (k % 3) * 0.6), y + (k % 4) * 2.0, 0.1)
            inst.rotation_euler = (0, 0, k * 1.3)
            k += 1


def checkpoint_set():
    """The checkpoint itself (no road): origin on the road's centre line, traffic coming up +Y on the left
    carriageway (x < 0)."""
    barricade(Vector((-5.6, 0.0, 0.0)), 0.0)
    barricade(Vector((-3.3, 0.6, 0.0)), 0.0)
    barricade(Vector((-1.4, 9.0, 0.0)), 0.0)
    barricade(Vector((-3.6, 9.6, 0.0)), 0.0)
    for k in range(9):
        cone(Vector((-0.2, -14.0 + k * 3.2, 0.0)))
    stop_board(Vector((-6.2, -10.0, 0.15)), 0.0)
    police_suv(Vector((-9.4, 14.0, 0.15)), 0.0)
    policeman("street_police_stop", Vector((-2.4, -4.5, 0.0)), 0.0)
    policeman("street_police_stand", Vector((-6.4, 7.5, 0.15)), 0.35)


def export_game():
    """godot/assets/city_props/police_checkpoint.glb — the set as above (Blender +Y = the game's −Z: the
    traffic comes from the game's +Z towards −Z; the checkpoint on the game's −X side of the centre line)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    TS._M.clear()
    checkpoint_set()
    bpy.ops.object.select_all(action='SELECT')
    out = os.path.join(ROOT, "godot", "assets", "city_props", "police_checkpoint.glb")
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(out), export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True)
    print("EXPORT", out, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--export" in args:
        export_game()
        return
    out = os.path.abspath(args[args.index("--out") + 1]) if "--out" in args else os.path.join(ROOT, "previews", "police")
    os.makedirs(out, exist_ok=True)
    sc = TS.setup(64)
    TS._M.clear()
    road()
    trees()
    # traffic comes up +Y on the left carriageway (x < 0); the chicane: a barricade from the kerb, then one from
    # the centre line, cones along the centre
    checkpoint_set()
    TS.shoot(sc, os.path.join(out, "checkpoint_driver.jpg"), (-3.4, -38.0, 1.35), (-3.0, 0.0, 1.4), 30)
    TS.shoot(sc, os.path.join(out, "checkpoint_close.jpg"), (-3.0, -11.0, 1.6), (-3.2, -4.0, 1.3), 30)
    TS.shoot(sc, os.path.join(out, "checkpoint_overview.jpg"), (6.0, -20.0, 9.0), (-4.0, 3.0, 0.5), 26)


if __name__ == "__main__":
    main()
