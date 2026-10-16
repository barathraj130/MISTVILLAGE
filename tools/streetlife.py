"""
Street life for the land-and-roads reference (tools/roadland.py), placed from the same city tiles:

  drains      a covered storm drain behind every footpath: concrete slabs with gaps, a gully grating every 15 m
  poles       concrete electric poles every 35 m on the far side of the footpath, cross-arms with insulators, and
              wires sagging (catenary) from pole to pole, a few service drops to the houses
  stalls      tea stalls (a counter, a tin roof on poles, a kettle, glasses, a bench), fruit and vegetable push carts,
              a pan shop box, flower sellers' baskets — near junctions and on the main roads
  vehicles    parked autos, scooters, motorcycles, cars from the fleet models along the kerbs
  manholes    round iron covers in the lanes
  road wear   decals on the asphalt: red dust drifted along the kerbs, oil stains in the lane centres, crack
              lines, darker patched repairs, sand at junction mouths
  signs       a few signboards on poles (speed limit circle, school, no parking) — plain shapes, no brands

All in the game frame; roadland.py turns it into Blender's.
"""
import math
import os
import random

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
VEH = os.path.join(HERE, "..", "godot", "assets", "vehicles")


def _mat(name, colour, rough=0.7, metal=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND' if hasattr(m, "blend_method") else None
    return m


def decal_mat(name, colour, rough, noise_scale, threshold, alpha_max):
    """A decal that fades in and out by noise, so dust and stains have soft, irregular shapes."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    out = nt.nodes["Material Output"]
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = rough
    co = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = noise_scale
    n.inputs["Detail"].default_value = 6.0
    nt.links.new(co.outputs["Object"], n.inputs["Vector"])
    uvs = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co.outputs["UV"], uvs.inputs[0])
    edge = nt.nodes.new("ShaderNodeMath")                  # fade towards the decal's sides (v = 0 … 1 across)
    edge.operation = "PINGPONG"
    nt.links.new(uvs.outputs["Y"], edge.inputs[0])
    edge.inputs[1].default_value = 0.5
    ef = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(edge.outputs[0], ef.inputs["Value"])
    ef.inputs["From Min"].default_value = 0.0
    ef.inputs["From Max"].default_value = 0.35
    r = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(n.outputs["Fac"], r.inputs["Value"])
    r.inputs["From Min"].default_value = threshold
    r.inputs["From Max"].default_value = threshold + 0.05
    r.inputs["To Max"].default_value = alpha_max
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(r.outputs[0], mul.inputs[0])
    nt.links.new(ef.outputs[0], mul.inputs[1])
    tp = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(mul.outputs[0], mix.inputs[0])
    nt.links.new(tp.outputs[0], mix.inputs[1])
    nt.links.new(p.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m



# ----------------------------------------------------------------------------- street types (docs/COIMBATORE_STREETS.md)
DISTRICTS = {           # game-frame centres (x east, z south) and radii, from real coordinates
    "oldtown": ((-899.0, 2860.0), 1200.0),        # Town Hall, Big Bazaar Street, Raja Street, Oppanakara Street
    "model": ((-1939.0, 1042.0), 900.0),          # R.S. Puram, DB Road, T.V. Samy Road
    "industrial_g": ((1318.0, -2410.0), 1300.0),  # Ganapathy
    "industrial_p": ((6136.0, -1003.0), 1500.0),  # Peelamedu
}


def _in(district, x, z):
    (cx, cz), r = DISTRICTS[district]
    return math.hypot(x - cx, z - cz) < r


def classify(tiles, classes, manifest, variants):
    """Give every footpath strip and road piece a street type: arterial, bazaar, model, colony, oldtown, industrial,
    periurban. Uses the road class, the real district, and the buildings within 30 m."""
    blds = []
    for t in tiles:
        for b in t["blds"]:
            if 0 <= b["variant"] < len(variants):
                blds.append((b["kd"][0], b["kd"][2], manifest[variants[b["variant"]]]["kind"]))
    xs = [q[0] for q in blds]

    def street_type(cls, x, z):
        near = [k for bx, bz, k in blds if abs(bx - x) < 30 and abs(bz - z) < 30]
        n = len(near)
        shops = sum(1 for k in near if k in ("shop_house", "commercial")) / max(n, 1)
        mills = sum(1 for k in near if k == "mill_shed")
        far = math.hypot(x, z) > 7000
        if cls in ("trunk", "motorway", "primary"):
            return "arterial"
        if _in("industrial_g", x, z) or _in("industrial_p", x, z) or mills >= 2:
            if shops < 0.4:
                return "industrial"
        if n < 2 and far:
            return "periurban"
        if _in("oldtown", x, z):
            return "bazaar" if (cls in ("secondary", "tertiary") or shops >= 0.4) else "oldtown"
        if cls in ("secondary", "tertiary"):
            if _in("model", x, z):
                return "model"
            return "bazaar" if shops >= 0.45 else ("model" if n < 6 else "colony")
        if shops >= 0.6 and n >= 4:
            return "bazaar"
        if n < 1:
            return "periurban"
        return "colony"
    _ = xs
    from collections import Counter
    cnt = Counter()
    for t in tiles:
        for wk in t["walks"]:
            p = wk["p"]
            mid = p[len(p) // 2]
            cls = classes[wk["cid"]] if wk["cid"] < len(classes) else "residential"
            wk["type"] = "median" if (wk["fl"] & 8) else street_type(cls, mid[0], mid[2])
            cnt[wk["type"]] += 1
        for r in t["roads"]:
            p = r["p"]
            mid = p[len(p) // 2]
            r["type"] = street_type(classes[r["cid"]], mid[0], mid[2])
    print("STREET TYPES", dict(cnt), flush=True)


# ----------------------------------------------------------------------------- tiny geometry helpers (Blender frame)
def _link(coll, ob):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)
    return ob


def box(coll, name, loc, size, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(mat)
    return _link(coll, o)


def cyl(coll, name, loc, r, h, mat, rot=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return _link(coll, o)


# ----------------------------------------------------------------------------- prop collections
def pole_collection():
    """Concrete electric pole (9 m, tapering square section) with a cross-arm, three insulators, a street lamp."""
    c = bpy.data.collections.new("ElectricPole")
    conc = _mat("Pole Concrete", (0.55, 0.54, 0.5), 0.85)
    steel = _mat("Pole Steel", (0.18, 0.18, 0.19), 0.5, 0.6)
    por = _mat("Insulator", (0.75, 0.72, 0.68), 0.3)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.17, radius2=0.09, depth=9.2, location=(0, 0, 4.4),
                                    rotation=(0, 0, math.pi / 4))
    p = bpy.context.active_object
    p.data.materials.append(conc)
    _link(c, p)
    box(c, "CrossArm", (0, 0, 8.4), (0.08, 1.6, 0.08), steel)
    for y in (-0.7, 0.0, 0.7):
        cyl(c, "Insulator", (0, y, 8.52), 0.04, 0.16, por, verts=8)
    box(c, "Brace", (0, 0.3, 8.1), (0.04, 0.6, 0.04), steel, rot=(math.radians(-35), 0, 0))
    box(c, "Box", (0.14, 0, 3.0), (0.12, 0.3, 0.45), _mat("Meter Box", (0.12, 0.13, 0.12), 0.5))
    return c


def drain_collection():
    """A 1 m length of covered drain: two slabs with a gap, the channel wall faces."""
    c = bpy.data.collections.new("Drain")
    conc = _mat("Drain Concrete", (0.48, 0.47, 0.44), 0.9)
    dark = _mat("Drain Gap", (0.02, 0.02, 0.02), 0.9)
    box(c, "Slab", (0.0, 0.0, 0.02), (0.92, 0.7, 0.08), conc)
    box(c, "Gap", (0.48, 0.0, 0.0), (0.06, 0.62, 0.05), dark)
    for s in (-1, 1):
        box(c, "Wall", (0.0, s * 0.39, -0.05), (1.0, 0.1, 0.25), conc)
    return c


def grating_collection():
    c = bpy.data.collections.new("Grating")
    iron = _mat("Cast Iron", (0.05, 0.05, 0.05), 0.5, 0.7)
    box(c, "Frame", (0, 0, 0.03), (0.7, 0.55, 0.04), iron)
    for k in range(7):
        box(c, "Bar", (-0.3 + k * 0.1, 0, 0.055), (0.03, 0.5, 0.02), iron)
    return c


def manhole_collection():
    c = bpy.data.collections.new("Manhole")
    iron = _mat("Cast Iron", (0.05, 0.05, 0.05), 0.5, 0.7)
    cyl(c, "Cover", (0, 0, 0.005), 0.32, 0.02, iron, verts=24)
    cyl(c, "Ring", (0, 0, 0.0), 0.38, 0.015, _mat("Manhole Ring", (0.3, 0.3, 0.29), 0.8), verts=24)
    return c


def tea_stall_collection():
    """Tea stall: counter with a steel top, a tin roof on four poles, a kettle on a stove, glasses, a bench."""
    c = bpy.data.collections.new("TeaStall")
    wood = _mat("Stall Wood", (0.35, 0.2, 0.1), 0.8)
    tin = _mat("Stall Tin", (0.55, 0.57, 0.58), 0.4, 0.7)
    blue = _mat("Stall Tarp", (0.1, 0.25, 0.6), 0.8)
    steel = _mat("Stall Steel", (0.75, 0.76, 0.77), 0.25, 0.9)
    glass = _mat("Tea Glass", (0.75, 0.55, 0.3), 0.1)
    box(c, "Counter", (0, 0, 0.5), (1.6, 0.7, 1.0), wood)
    box(c, "Top", (0, 0, 1.02), (1.65, 0.75, 0.04), steel)
    for x in (-0.9, 0.9):
        for y in (-0.5, 0.6):
            box(c, "Pole", (x, y, 1.1), (0.05, 0.05, 2.2), wood)
    box(c, "Roof", (0, 0.05, 2.25), (2.2, 1.6, 0.03), tin, rot=(math.radians(8), 0, 0))
    box(c, "Tarp", (0, -0.75, 1.9), (2.0, 0.02, 0.6), blue)
    cyl(c, "Stove", (-0.45, 0.05, 1.12), 0.14, 0.18, _mat("Stove", (0.1, 0.1, 0.1), 0.6, 0.5), verts=16)
    cyl(c, "Kettle", (-0.45, 0.05, 1.32), 0.13, 0.24, steel, verts=16)
    for k in range(6):
        cyl(c, "Glass", (0.1 + (k % 3) * 0.12, -0.1 + (k // 3) * 0.12, 1.1), 0.03, 0.1, glass, verts=8)
    box(c, "Bench", (0, -1.3, 0.42), (1.5, 0.32, 0.06), wood)
    for x in (-0.65, 0.65):
        box(c, "BenchLeg", (x, -1.3, 0.2), (0.06, 0.28, 0.4), wood)
    box(c, "Board", (0, 0.72, 2.0), (1.4, 0.04, 0.32), _mat("Stall Board", (0.85, 0.65, 0.05), 0.6))
    return c


def cart_collection():
    """Push cart with a heap of fruit or vegetables under an umbrella."""
    c = bpy.data.collections.new("Cart")
    wood = _mat("Cart Wood", (0.4, 0.25, 0.12), 0.8)
    rubber = _mat("Cart Tyre", (0.03, 0.03, 0.03), 0.8)
    box(c, "Bed", (0, 0, 0.85), (1.6, 0.9, 0.08), wood)
    for s in (-1, 1):
        cyl(c, "Wheel", (0.3, s * 0.5, 0.35), 0.35, 0.08, rubber, rot=(math.pi / 2, 0, 0), verts=16)
    box(c, "Handle", (-1.05, 0, 0.9), (0.5, 0.06, 0.04), wood)
    rng = random.Random(4)
    cols = [(0.8, 0.45, 0.05), (0.15, 0.4, 0.08), (0.75, 0.1, 0.05), (0.9, 0.75, 0.1)]
    for k in range(40):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=rng.uniform(0.05, 0.08),
                                             location=(rng.uniform(-0.7, 0.7), rng.uniform(-0.38, 0.38), 0.95 + rng.random() * 0.12))
        o = bpy.context.active_object
        o.data.materials.append(_mat("Produce %d" % (k % 4), cols[k % 4], 0.5))
        _link(c, o)
    cyl(c, "UmbrellaPole", (0.6, 0, 1.6), 0.02, 1.5, wood, verts=6)
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=1.0, depth=0.35, location=(0.6, 0, 2.4))
    u = bpy.context.active_object
    u.data.materials.append(_mat("Umbrella", (0.75, 0.1, 0.08), 0.8))
    _link(c, u)
    return c


def sign_collection():
    """A round speed-limit sign on a pole."""
    c = bpy.data.collections.new("Sign")
    steel = _mat("Sign Pole", (0.6, 0.6, 0.6), 0.4, 0.8)
    cyl(c, "Pole", (0, 0, 1.25), 0.03, 2.5, steel, verts=8)
    cyl(c, "Disc", (0, -0.03, 2.4), 0.3, 0.02, _mat("Sign Red", (0.75, 0.05, 0.04), 0.4), rot=(math.pi / 2, 0, 0), verts=24)
    cyl(c, "Face", (0, -0.045, 2.4), 0.24, 0.01, _mat("Sign White", (0.92, 0.92, 0.9), 0.4), rot=(math.pi / 2, 0, 0), verts=24)
    return c


def bin_collection():
    """A municipal dustbin: a green wheeled bin, a little litter round it."""
    c = bpy.data.collections.new("Bin")
    green = _mat("Bin Green", (0.05, 0.28, 0.1), 0.6)
    box(c, "Bin", (0, 0, 0.55), (0.75, 0.6, 1.1), green)
    box(c, "Lid", (0, 0, 1.12), (0.8, 0.65, 0.05), _mat("Bin Lid", (0.04, 0.2, 0.08), 0.5))
    rng = random.Random(8)
    for k in range(6):
        box(c, "Litter", (rng.uniform(-0.8, 0.8), rng.uniform(-0.7, 0.7), 0.01), (rng.uniform(0.08, 0.2), rng.uniform(0.06, 0.15), 0.01),
            _mat("Litter %d" % (k % 3), [(0.85, 0.85, 0.8), (0.7, 0.2, 0.1), (0.2, 0.35, 0.7)][k % 3], 0.8), rot=(0, 0, rng.random() * 3))
    return c


def flex_collection():
    """A printed flex banner on two bamboo poles, as for a shop offer or a function (plain colour bands, no text)."""
    c = bpy.data.collections.new("Flex")
    bamboo = _mat("Bamboo", (0.55, 0.45, 0.25), 0.8)
    for y in (-1.3, 1.3):
        cyl(c, "Pole", (0, y, 1.6), 0.04, 3.2, bamboo, verts=8)
    box(c, "Banner", (0, 0, 2.3), (0.02, 2.6, 1.2), _mat("Flex", (0.9, 0.82, 0.2), 0.6))
    box(c, "Band", (0.012, 0, 2.6), (0.01, 2.6, 0.3), _mat("Flex Red", (0.75, 0.08, 0.05), 0.6))
    box(c, "Band2", (0.012, 0, 1.95), (0.01, 2.6, 0.2), _mat("Flex Blue", (0.08, 0.2, 0.6), 0.6))
    return c


def vehicle_collections():
    out = []
    for name in ("fleet_auto", "fleet_hatchback", "fleet_sedan", "fleet_lorry", "bike_scooter_0", "bike_motorcycle_1",
                 "bike_scooter_2", "bike_motorcycle_3"):
        path = os.path.join(VEH, name + ".glb")
        if not os.path.exists(path):
            continue
        c = bpy.data.collections.new("Veh_" + name)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for o in set(bpy.data.objects) - before:
            for cc in list(o.users_collection):
                cc.objects.unlink(o)
            c.objects.link(o)
        out.append((name, c))
    return out


# ----------------------------------------------------------------------------- placement (game frame in, Blender out)
BOARDS = os.path.join(HERE, "..", "art", "boards")


def img_mat(name, file, emit=0.15):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.join(BOARDS, file), check_existing=True)
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    for nm in ("Emission Color", "Emission"):
        if nm in p.inputs:
            nt.links.new(t.outputs["Color"], p.inputs[nm])
    p.inputs["Emission Strength"].default_value = emit
    p.inputs["Roughness"].default_value = 0.6
    return m


def board(coll, name, centre, w, h, mat, yaw=0.0):
    """A vertical lettered board, readable from both sides (back face mirrored), local X along its width."""
    cx, cy, cz = centre
    for side in (1, -1):
        me = bpy.data.meshes.new(name)
        y = cy - 0.004 * side
        vs = [(cx - w / 2, y, cz - h / 2), (cx + w / 2, y, cz - h / 2), (cx + w / 2, y, cz + h / 2), (cx - w / 2, y, cz + h / 2)]
        me.from_pydata(vs, [], [(0, 1, 2, 3) if side > 0 else (3, 2, 1, 0)])
        uv = me.uv_layers.new()
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)] if side > 0 else [(0, 1), (1, 1), (1, 0), (0, 0)]
        uvs = uvs if side > 0 else [(1 - u, v) for u, v in [(0, 1), (1, 1), (1, 0), (0, 0)]]
        for li, q in zip(me.polygons[0].loop_indices, uvs if side > 0 else [(1, 1), (0, 1), (0, 0), (1, 0)]):
            uv.data[li].uv = q
        o = bpy.data.objects.new(name, me)
        o.data.materials.append(mat)
        o.rotation_euler = (0, 0, yaw)
        coll.objects.link(o)


def stall_collection(k, thatch=False):
    """Tea stall with a lettered board; a thatched one for the outskirts."""
    c = bpy.data.collections.new("Stall%d%s" % (k, "T" if thatch else ""))
    wood = _mat("Stall Wood", (0.35, 0.2, 0.1), 0.8)
    roofm = _mat("Thatch", (0.42, 0.33, 0.18), 0.95) if thatch else _mat("Stall Tin", (0.55, 0.57, 0.58), 0.4, 0.7)
    steel = _mat("Stall Steel", (0.75, 0.76, 0.77), 0.25, 0.9)
    box(c, "Counter", (0, 0, 0.5), (1.6, 0.7, 1.0), wood)
    box(c, "Top", (0, 0, 1.02), (1.65, 0.75, 0.04), steel)
    for x in (-0.9, 0.9):
        for y in (-0.5, 0.6):
            box(c, "Pole", (x, y, 1.1), (0.05, 0.05, 2.2), wood)
    box(c, "Roof", (0, 0.05, 2.25), (2.3, 1.7, 0.08 if thatch else 0.03), roofm, rot=(math.radians(8), 0, 0))
    cyl(c, "Stove", (-0.45, 0.05, 1.12), 0.14, 0.18, _mat("Stove", (0.1, 0.1, 0.1), 0.6, 0.5), verts=16)
    cyl(c, "Kettle", (-0.45, 0.05, 1.32), 0.13, 0.24, steel, verts=16)
    for j in range(6):
        cyl(c, "Glass", (0.1 + (j % 3) * 0.12, -0.1 + (j // 3) * 0.12, 1.1), 0.03, 0.1, _mat("Tea Glass", (0.75, 0.55, 0.3), 0.1), verts=8)
    box(c, "Bench", (0, -1.3, 0.42), (1.5, 0.32, 0.06), wood)
    for x in (-0.65, 0.65):
        box(c, "BenchLeg", (x, -1.3, 0.2), (0.06, 0.28, 0.4), wood)
    for bunch in range(5):                                       # banana bunches and snacks hanging
        cyl(c, "Bunch", (0.7 - bunch * 0.12, -0.4, 1.75), 0.05, 0.22, _mat("Banana", (0.75, 0.6, 0.1), 0.6), verts=8)
    if not thatch:
        board(c, "Board", (0, -0.55, 2.0), 1.6, 0.4, img_mat("stall_tea_%d" % (k % 2 + 1), "stall_tea_%d.png" % (k % 2 + 1)))
    return c


def flex_collection_k(k):
    c = bpy.data.collections.new("Flex%d" % k)
    bamboo = _mat("Bamboo", (0.55, 0.45, 0.25), 0.8)
    for x in (-1.3, 1.3):
        cyl(c, "Pole", (x, 0, 1.7), 0.04, 3.4, bamboo, verts=8)
    file = ["flex_sale", "flex_tuition", "flex_wedding"][k % 3]
    board(c, "Banner", (0, 0, 2.5), 2.6, 1.3, img_mat(file, file + ".png", 0.2))
    return c


def shade_collection(k):
    """Shop shade cloth over the footpath: a sloping sheet on two poles at the kerb edge, the shop's lettered valance."""
    c = bpy.data.collections.new("Shade%d" % k)
    cols = [(0.8, 0.1, 0.08), (0.08, 0.2, 0.55), (0.1, 0.5, 0.2)]
    cloth = _mat("Shade %d" % k, cols[k % 3], 0.9)
    me = bpy.data.meshes.new("Sheet")
    me.from_pydata([(-1.6, 0.0, 2.9), (1.6, 0.0, 2.9), (1.6, -2.0, 2.45), (-1.6, -2.0, 2.45)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new("Sheet", me)
    o.data.materials.append(cloth)
    c.objects.link(o)
    for x in (-1.5, 1.5):
        cyl(c, "Pole", (x, -2.0, 1.22), 0.025, 2.45, _mat("Steel Pipe", (0.3, 0.3, 0.3), 0.4, 0.8), verts=6)
    file = ["shade_textiles", "shade_jewel", "shade_fancy"][k % 3]
    board(c, "Valance", (0, -2.02, 2.32), 3.2, 0.32, img_mat(file, file + ".png", 0.1))
    return c


def goods_collection():
    """Goods put out on the footpath: crates, sacks, a stack of plastic buckets, a stool."""
    c = bpy.data.collections.new("Goods")
    rng = random.Random(6)
    for k in range(5):
        box(c, "Crate", (rng.uniform(-0.8, 0.8), rng.uniform(-0.3, 0.3), 0.18 + (k // 3) * 0.36), (0.5, 0.38, 0.34),
            _mat("Crate", (0.55, 0.38, 0.2), 0.8), rot=(0, 0, rng.uniform(-0.2, 0.2)))
    for k in range(3):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.3, location=(-1.1 + k * 0.45, 0.4, 0.28))
        sk = bpy.context.active_object
        sk.scale = (1.0, 0.75, 0.9)
        sk.data.materials.append(_mat("Sack", (0.72, 0.65, 0.48), 0.95))
        _link(c, sk)
    for k in range(4):
        cyl(c, "Bucket", (0.9, -0.5, 0.15 + k * 0.08), 0.18 - k * 0.005, 0.25, _mat("Bucket", (0.1, 0.4, 0.75), 0.4), verts=16)
    return c


def flower_collection():
    """A flower seller's place: a mat, two round baskets of jasmine and marigold strings, a stool."""
    c = bpy.data.collections.new("Flowers")
    box(c, "Mat", (0, 0, 0.01), (1.2, 0.9, 0.02), _mat("Mat", (0.6, 0.45, 0.25), 0.9))
    rng = random.Random(3)
    for k, col in enumerate([(0.95, 0.95, 0.9), (0.95, 0.55, 0.05)]):
        cyl(c, "Basket", (-0.3 + k * 0.6, 0, 0.1), 0.28, 0.2, _mat("Basket", (0.5, 0.35, 0.15), 0.9), verts=16)
        for j in range(40):
            a = rng.uniform(0, 6.28)
            r = rng.uniform(0, 0.25)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.028,
                                                  location=(-0.3 + k * 0.6 + math.cos(a) * r, math.sin(a) * r, 0.21 + rng.random() * 0.05))
            f = bpy.context.active_object
            f.data.materials.append(_mat("Flower %d" % k, col, 0.6))
            _link(c, f)
    cyl(c, "Stool", (0, -0.6, 0.15), 0.15, 0.3, _mat("Stool", (0.2, 0.3, 0.7), 0.5), verts=12)
    return c


def bollard_collection():
    c = bpy.data.collections.new("Bollard")
    cyl(c, "Bollard", (0, 0, 0.4), 0.09, 0.8, _mat("Bollard", (0.6, 0.6, 0.58), 0.7), verts=12)
    cyl(c, "Band", (0, 0, 0.65), 0.092, 0.1, _mat("Bollard Band", (0.9, 0.7, 0.05), 0.6), verts=12)
    return c


def bench_collection():
    c = bpy.data.collections.new("Bench")
    conc = _mat("Bench Concrete", (0.62, 0.6, 0.57), 0.8)
    box(c, "Seat", (0, 0, 0.45), (1.8, 0.45, 0.08), conc)
    for x in (-0.7, 0.7):
        box(c, "Leg", (x, 0, 0.22), (0.1, 0.4, 0.44), conc)
    return c


def kolam_collection(k):
    """A rice-flour kolam: a dot grid in a diamond, looped lines round the dots, a circle; lying on the ground."""
    c = bpy.data.collections.new("Kolam%d" % k)
    white = _mat("Kolam White", (0.95, 0.95, 0.93), 0.9)
    me = bpy.data.meshes.new("Kolam")
    vs, fs = [], []
    rng = random.Random(k)
    n = 3 + k % 2
    sp = 0.16

    def dot(x, y, r=0.022):
        i = len(vs)
        for j in range(6):
            a = j / 6 * math.tau
            vs.append((x + math.cos(a) * r, y + math.sin(a) * r, 0.004))
        fs.append(tuple(range(i, i + 6)))

    def seg(x0, y0, x1, y1, w=0.012):
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L * w, dx / L * w
        i = len(vs)
        vs.extend([(x0 - nx, y0 - ny, 0.004), (x1 - nx, y1 - ny, 0.004), (x1 + nx, y1 + ny, 0.004), (x0 + nx, y0 + ny, 0.004)])
        fs.append((i, i + 1, i + 2, i + 3))
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            if abs(i) + abs(j) <= n:
                dot(i * sp, j * sp)
                # loops round each dot (diamond strokes)
                for a0 in range(4):
                    a = a0 * math.pi / 2 + math.pi / 4
                    b = a + math.pi / 2
                    r = sp * 0.5
                    seg(i * sp + math.cos(a) * r, j * sp + math.sin(a) * r, i * sp + math.cos(b) * r, j * sp + math.sin(b) * r)
    R = (n + 1.2) * sp
    for j in range(36):
        a, b = j / 36 * math.tau, (j + 1) / 36 * math.tau
        seg(math.cos(a) * R, math.sin(a) * R, math.cos(b) * R, math.sin(b) * R, 0.015)
    _ = rng
    me.from_pydata(vs, [], fs)
    o = bpy.data.objects.new("Kolam", me)
    o.data.materials.append(white)
    c.objects.link(o)
    return c


def transformer_collection():
    """A pole-mounted distribution transformer on two poles with a platform, fenced plinth below."""
    c = bpy.data.collections.new("Transformer")
    conc = _mat("Pole Concrete", (0.55, 0.54, 0.5), 0.85)
    grey = _mat("Transformer", (0.4, 0.45, 0.42), 0.5, 0.4)
    for x in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.17, radius2=0.1, depth=9.0, location=(x, 0, 4.4), rotation=(0, 0, math.pi / 4))
        p = bpy.context.active_object
        p.data.materials.append(conc)
        _link(c, p)
    box(c, "Platform", (0, 0, 3.4), (2.4, 0.9, 0.12), _mat("Pole Steel", (0.18, 0.18, 0.19), 0.5, 0.6))
    box(c, "Tank", (0, 0, 4.05), (1.1, 0.7, 1.2), grey)
    for k in range(6):
        box(c, "Fin", (-0.45 + k * 0.18, -0.38, 4.0), (0.05, 0.08, 1.0), grey)
    for x in (-0.35, 0.0, 0.35):
        cyl(c, "Bushing", (x, 0, 4.85), 0.05, 0.35, _mat("Insulator", (0.75, 0.72, 0.68), 0.3), verts=8)
    box(c, "Fence", (0, 0, 0.6), (2.6, 1.2, 1.2), _mat("Fence Mesh", (0.25, 0.25, 0.25), 0.6, 0.5))
    return c


def shrine_collection():
    """A small roadside shrine: a whitewashed box with red and white stripes, a little tower, a lettered board."""
    c = bpy.data.collections.new("Shrine")
    white = _mat("Lime White", (0.92, 0.9, 0.85), 0.9)
    red = _mat("Temple Red", (0.7, 0.12, 0.06), 0.8)
    box(c, "Base", (0, 0, 0.3), (1.6, 1.4, 0.6), white)
    for k in range(5):
        box(c, "Stripe", (0, 0.711, 0.08 + k * 0.12), (1.6, 0.01, 0.05), red if k % 2 == 0 else white)
    box(c, "Cell", (0, 0, 1.2), (1.2, 1.1, 1.2), white)
    box(c, "Door", (0, -0.56, 1.1), (0.5, 0.02, 0.8), _mat("Shrine Dark", (0.08, 0.05, 0.03), 0.8))
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.75, depth=1.0, location=(0, 0, 2.3), rotation=(0, 0, math.pi / 4))
    t = bpy.context.active_object
    t.data.materials.append(_mat("Tower Ochre", (0.85, 0.55, 0.15), 0.8))
    _link(c, t)
    board(c, "Board", (0, -0.6, 1.72), 1.0, 0.3, img_mat("shrine_board", "shrine_board.png", 0.1))
    return c


def drum_collection():
    c = bpy.data.collections.new("Drums")
    for k in range(3):
        cyl(c, "Drum", (k * 0.65, 0, 0.45), 0.29, 0.9, _mat("Water Drum", (0.1, 0.3, 0.7), 0.4), verts=16)
    return c


def school_sign_collection():
    c = bpy.data.collections.new("SchoolSign")
    cyl(c, "Pole", (0, 0, 1.25), 0.03, 2.5, _mat("Sign Pole", (0.6, 0.6, 0.6), 0.4, 0.8), verts=8)
    board(c, "Face", (0, 0, 2.3), 0.6, 0.6, img_mat("sign_school", "sign_school.png", 0.05))
    return c


def place(tiles, classes, inst, to_blender, b):
    """Street life by street type (docs/COIMBATORE_STREETS.md), along every footpath strip / street edge."""
    rng = random.Random(21)
    pole_c, drain_c, grat_c, man_c = pole_collection(), drain_collection(), grating_collection(), manhole_collection()
    cart_c, sign_c = cart_collection(), sign_collection()
    stalls = [stall_collection(0), stall_collection(1)]
    thatched = stall_collection(2, thatch=True)
    flexes = [flex_collection_k(k) for k in range(3)]
    shades = [shade_collection(k) for k in range(3)]
    goods_c, flower_c, bollard_c, bench_c = goods_collection(), flower_collection(), bollard_collection(), bench_collection()
    kolams = [kolam_collection(k) for k in range(2)]
    trans_c, shrine_c, drum_c, school_c = transformer_collection(), shrine_collection(), drum_collection(), school_sign_collection()
    bin_c = bin_collection()
    vehs = vehicle_collections()
    bikes = [v for v in vehs if v[0].startswith("bike")]
    cars = [v for v in vehs if not v[0].startswith("bike") and "lorry" not in v[0]]
    lorries = [v for v in vehs if "lorry" in v[0]]

    def M(at_g, dir_g, scale=1.0):
        p = to_blender(at_g)
        d = to_blender(dir_g) - to_blender(Vector((0, 0, 0)))
        d.z = 0
        d.normalize()
        rot = d.to_track_quat('X', 'Z').to_matrix().to_4x4()
        return Matrix.Translation(p) @ rot @ Matrix.Scale(scale, 4)

    def F(at_g, d, rw, scale=1.0):
        """Matrix with local X along the street and local -Y facing the road (for stalls, shades, boards)."""
        m = M(at_g, d, scale)
        yb = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
        rb = to_blender(rw) - to_blender(Vector((0, 0, 0)))
        return m if yb.dot(rb) < 0 else M(at_g, -d, scale)

    # (spacing range, {item: weight}) per street type
    PLAN = {
        "arterial": ((8, 16), {"bikes": 3, "car": 2, "flex": 1, "stall": 1, "autos": 2, "sign": 1, "bin": 1, "none": 3}),
        "bazaar": ((3, 6), {"bikes": 6, "shade": 4, "goods": 3, "cart": 2, "flowers": 2, "stall": 1, "flex": 1, "bin": 1}),
        "model": ((7, 12), {"tree": 4, "bench": 1, "bikes": 1, "car": 1, "none": 2, "bin": 1}),
        "colony": ((10, 22), {"car": 2, "bikes": 2, "drums": 1, "cart": 1, "none": 5}),
        "oldtown": ((4, 9), {"bikes": 4, "drums": 2, "goods": 1, "flowers": 1, "none": 2}),
        "industrial": ((14, 30), {"lorry": 3, "goods": 2, "stall": 1, "none": 3}),
        "periurban": ((20, 45), {"thatched": 1, "tree": 3, "bikes": 1, "none": 4}),
    }
    counts = {}

    def put(item, q, d, rw, hw, road_edge):
        """q is the footpath centre (or the edge strip for types without a footpath)."""
        counts[item] = counts.get(item, 0) + 1
        back = q - rw * (hw - 0.6)                         # near the building side
        kerbside = q + rw * (hw - 0.35)
        if item == "bikes" and bikes:
            for j in range(rng.randint(3, 7)):
                name, vc = bikes[rng.randrange(len(bikes))]
                ang = rng.uniform(-0.25, 0.25)
                inst(vc, M(road_edge - rw * 0.9 + d * (j * 0.85), (rw * math.cos(ang) + d * math.sin(ang)).normalized()))
        elif item == "car" and cars:
            name, vc = cars[rng.randrange(len(cars))]
            inst(vc, M(road_edge + rw * 1.2 + Vector((0, -0.06, 0)), d))
        elif item == "autos" and vehs:
            autos = [v for v in vehs if "auto" in v[0]] or cars
            for j in range(3):
                inst(autos[0][1], M(road_edge + rw * 1.3 + d * (j * 3.2) + Vector((0, -0.06, 0)), d))
        elif item == "lorry" and lorries:
            inst(lorries[0][1], M(road_edge + rw * 1.6 + Vector((0, -0.06, 0)), d))
        elif item == "stall":
            inst(stalls[rng.randrange(2)], F(back + rw * 0.3, d, rw))
        elif item == "thatched":
            inst(thatched, F(q - rw * 2.0, d, rw))
        elif item == "flex":
            inst(flexes[rng.randrange(3)], F(back, d, rw))
        elif item == "shade":
            inst(shades[rng.randrange(3)], F(q - rw * hw, d, rw))
        elif item == "goods":
            inst(goods_c, M(back, d))
        elif item == "cart":
            inst(cart_c, M(road_edge + rw * 0.7 + Vector((0, -0.05, 0)), d))
        elif item == "flowers":
            inst(flower_c, M(kerbside - rw * 0.4, d))
        elif item == "sign":
            inst(sign_c, M(kerbside, d))
        elif item == "bin":
            inst(bin_c, M(back, d))
        elif item == "bench":
            inst(bench_c, M(back, d))
        elif item == "drums":
            inst(drum_c, M(q - rw * 0.2, d))
        elif item == "tree":
            TREE_SPOTS.append(kerbside if hw > 0.9 else q - rw * 2.5)
    for t in tiles:
        for wk in t["walks"]:
            p = wk["p"]
            typ = wk.get("type", "colony")
            if len(p) < 2 or typ == "median":
                continue
            pts = [Vector(q.tolist()) for q in p]
            road_right = bool(wk["fl"] & 4)
            hw = wk["w"] * 0.5
            spacing, menu = PLAN.get(typ, PLAN["colony"])
            items = [k for k, w in menu.items() for _ in range(w)]
            along = 0.0
            next_pole = rng.uniform(5, 20)
            poles = []
            next_thing = rng.uniform(*spacing)
            next_kolam = rng.uniform(4, 10)
            for i in range(len(pts) - 1):
                a, c = pts[i], pts[i + 1]
                seg = (c - a).length
                if seg < 0.05:
                    continue
                d = Vector((c.x - a.x, 0, c.z - a.z)).normalized()
                rw = Vector((d.z, 0, -d.x)) if road_right else Vector((-d.z, 0, d.x))
                # drains: under/behind the footpath on footpath streets, at the edge strip on colony streets
                if typ in ("arterial", "bazaar", "model", "colony"):
                    k = 0.0
                    while k < seg:
                        base = a.lerp(c, k / seg)
                        if typ == "colony":
                            q = base + rw * (hw + 0.2 - 0.88) + Vector((0, -0.15, 0))
                        else:
                            q = base - rw * (hw + 0.38) + Vector((0, -0.04, 0))
                        inst(drain_c, M(q, d))
                        counts["drain"] = counts.get("drain", 0) + 1
                        if int((along + k) / 15.0) != int((along + k - 1.0) / 15.0):
                            inst(grat_c, M(q + Vector((0, 0.05, 0)), d))
                        k += 1.0
                # poles (one side only: the left-of-way strips) every 35 m, closer in the old town
                pole_gap = 25.0 if typ in ("oldtown", "bazaar") else 35.0
                while road_right and next_pole <= along + seg:
                    q = a.lerp(c, (next_pole - along) / seg)
                    q = q - rw * (hw - 0.2) if typ in ("arterial", "bazaar", "model") else q + rw * (hw - 0.4)
                    if typ in ("colony", "oldtown", "industrial", "periurban"):
                        q = q + Vector((0, -0.12, 0))
                    inst(pole_c, M(q, rw))
                    poles.append(q)
                    counts["pole"] = counts.get("pole", 0) + 1
                    next_pole += pole_gap
                road_edge_a = a + rw * (hw + 0.2) + Vector((0, -0.06, 0))
                while next_thing <= along + seg:
                    f = (next_thing - along) / seg
                    q = a.lerp(c, f)
                    item = items[rng.randrange(len(items))]
                    if item != "none":
                        put(item, q, d, rw, hw, q + rw * (hw + 0.2) + Vector((0, -0.12, 0)))
                    next_thing += rng.uniform(*spacing)
                # kolam at gates in colonies and the old town (on the edge strip, by the morning's doorway)
                while typ in ("colony", "oldtown") and next_kolam <= along + seg:
                    q = a.lerp(c, (next_kolam - along) / seg) + rw * (hw + 0.2 - 0.25) + Vector((0, -0.145, 0))
                    inst(kolams[rng.randrange(2)], M(q, d, 0.9))
                    counts["kolam"] = counts.get("kolam", 0) + 1
                    next_kolam += rng.uniform(9, 16)
                # red dust along the kerb on footpath streets
                if typ in ("arterial", "bazaar", "model"):
                    kq0, kq1 = a + rw * (hw + 0.2), c + rw * (hw + 0.2)
                    lo = Vector((0, -0.05, 0))
                    b.quad("dust", kq0 + lo, kq1 + lo, kq1 + rw * 0.7 + lo, kq0 + rw * 0.7 + lo,
                           uv=((along, 0), (along + seg, 0), (along + seg, 1), (along, 1)))
                _ = road_edge_a
                along += seg
            # transformers and shrines at some colony / old-town street ends; a school sign now and then
            if typ in ("colony", "oldtown") and len(pts) > 2:
                rr = rng.random()
                end = pts[-1]
                d = Vector((pts[-1].x - pts[-2].x, 0, pts[-1].z - pts[-2].z)).normalized()
                rw = Vector((d.z, 0, -d.x)) if road_right else Vector((-d.z, 0, d.x))
                if rr < 0.08:
                    inst(trans_c, M(end - d * 6 - rw * (hw + 1.0) + Vector((0, -0.15, 0)), d))
                    counts["transformer"] = counts.get("transformer", 0) + 1
                elif rr < 0.12:
                    inst(shrine_c, M(end - d * 5 - rw * (hw + 0.8) + Vector((0, -0.15, 0)), -rw))
                    counts["shrine"] = counts.get("shrine", 0) + 1
                elif rr < 0.14:
                    inst(school_c, M(end - d * 8 + rw * (hw - 0.4), d))
            # sagging wires between consecutive poles: three conductors and a cable bundle in the old town / bazaars
            wires = (-0.7, 0.0, 0.7, 0.35) if typ in ("oldtown", "bazaar") else (-0.7, 0.0, 0.7)
            for p0, p1 in zip(poles, poles[1:]):
                span = (p1 - p0).length
                if span > 60:
                    continue
                dirw = (p1 - p0).normalized()
                side = Vector((dirw.z, 0, -dirw.x))
                for off in wires:
                    prev = None
                    sag = 0.9 if off != 0.35 else 1.6
                    hgt = 8.55 if off != 0.35 else 6.0
                    for s_ in range(11):
                        f = s_ / 10.0
                        q = p0.lerp(p1, f) + side * off + Vector((0, hgt - sag * 4 * f * (1 - f), 0))
                        if prev is not None:
                            wire(b, prev, q)
                        prev = q
    # oil stains, cracks and patches on the roads; manholes in the lanes (rougher in the old town and outskirts)
    for t in tiles:
        for r in t["roads"]:
            cls = classes[r["cid"]]
            p = r["p"]
            if len(p) < 3 or cls in ("footway", "track") or r["fl"] & 2:
                continue
            wear = {"oldtown": 1.6, "periurban": 1.5, "industrial": 1.4, "colony": 1.1}.get(r.get("type"), 1.0)
            pts = [Vector(q.tolist()) + Vector((0, 0.09, 0)) for q in p]
            half = r["w"] * 0.5
            for i in range(len(pts) - 1):
                a, c = pts[i], pts[i + 1]
                seg = (c - a).length
                if seg < 0.5:
                    continue
                d = Vector((c.x - a.x, 0, c.z - a.z)).normalized()
                left = Vector((d.z, 0, -d.x))
                r2 = rng.random() / wear
                if r2 < 0.18:
                    lane = (1.75 if half > 3.5 else half * 0.5) * (1 if rng.random() < 0.5 else -1)
                    q0, q1 = a + left * lane, c + left * lane
                    w = 0.55
                    lift = Vector((0, 0.052, 0))
                    b.quad("oil", q0 - left * w / 2 + lift, q1 - left * w / 2 + lift, q1 + left * w / 2 + lift, q0 + left * w / 2 + lift,
                           uv=((0, 0), (seg, 0), (seg, 1), (0, 1)))
                elif r2 < 0.24:
                    q = a.lerp(c, rng.random())
                    off = rng.uniform(-half + 1.0, half - 1.0)
                    pw, pl = rng.uniform(1.2, 2.6), rng.uniform(1.0, 2.2)
                    cc = q + left * off + Vector((0, 0.054, 0))
                    b.quad("patch", cc - d * pl / 2 - left * pw / 2, cc + d * pl / 2 - left * pw / 2,
                           cc + d * pl / 2 + left * pw / 2, cc - d * pl / 2 + left * pw / 2, uv=((0, 0), (1, 0), (1, 1), (0, 1)))
                elif r2 < 0.3:
                    q = a.lerp(c, rng.random()) + left * rng.uniform(-half + 0.5, half - 0.5)
                    prev = q + Vector((0, 0.056, 0))
                    dd = (d * rng.uniform(-1, 1) + left * rng.uniform(-1, 1)).normalized()
                    for _s in range(rng.randint(4, 8)):
                        dd = (dd + Vector((rng.uniform(-0.6, 0.6), 0, rng.uniform(-0.6, 0.6)))).normalized()
                        nxt = prev + dd * rng.uniform(0.3, 0.7)
                        side = Vector((dd.z, 0, -dd.x)) * 0.012
                        b.quad("crack", prev - side, nxt - side, nxt + side, prev + side)
                        prev = nxt
                elif r2 < 0.33 and half > 2.5:
                    q = a.lerp(c, rng.random()) + left * rng.uniform(-half * 0.5, half * 0.5)
                    inst(man_c, Matrix.Translation(to_blender(q + Vector((0, 0.045, 0)))))
    print("STREETLIFE", counts, flush=True)


TREE_SPOTS = []


def wire(b, p, q):
    """A thin wire from p to q (game frame) as a narrow ribbon, vertical so it shows from below and the side."""
    up = Vector((0, 0.012, 0))
    b.quad("wire", p - up, q - up, q + up, p + up)
