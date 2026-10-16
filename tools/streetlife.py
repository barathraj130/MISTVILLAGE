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
    for name in ("fleet_auto", "fleet_hatchback", "fleet_sedan", "bike_scooter_0", "bike_motorcycle_1", "bike_scooter_2"):
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
def place(tiles, classes, inst, to_blender, b):
    """Everything placed along the footpaths and roads of the tiles. `inst(coll, matrix)` makes an instance;
    `b` is roadland's Builder for flat decals and wires (game frame)."""
    rng = random.Random(21)
    pole_c, drain_c, grat_c, man_c = pole_collection(), drain_collection(), grating_collection(), manhole_collection()
    stall_c, cart_c, sign_c = tea_stall_collection(), cart_collection(), sign_collection()
    vehs = vehicle_collections()
    bin_c, flex_c = bin_collection(), flex_collection()
    up = Vector((0, 1, 0))

    def M(at_g, dir_g, scale=1.0):
        """Blender matrix: origin at a game point, local +X along dir_g (game), Z up."""
        p = to_blender(at_g)
        d = to_blender(dir_g) - to_blender(Vector((0, 0, 0)))
        d.z = 0
        d.normalize()
        rot = d.to_track_quat('X', 'Z').to_matrix().to_4x4()
        return Matrix.Translation(p) @ rot @ Matrix.Scale(scale, 4)

    counts = dict.fromkeys(["drain", "pole", "stall", "cart", "vehicle", "manhole", "decal", "sign", "bin", "flex"], 0)
    for t in tiles:
        for wk in t["walks"]:
            p = wk["p"]
            if len(p) < 2 or (wk["fl"] & 8):
                continue
            pts = [Vector(q.tolist()) for q in p]
            road_right = bool(wk["fl"] & 4)
            main = bool(wk["fl"] & 1)
            hw = wk["w"] * 0.5
            along = 0.0
            next_pole = rng.uniform(5, 20)
            poles = []
            next_thing = rng.uniform(15, 40)
            for i in range(len(pts) - 1):
                a, c = pts[i], pts[i + 1]
                seg = (c - a).length
                if seg < 0.05:
                    continue
                d = Vector((c.x - a.x, 0, c.z - a.z)).normalized()
                rw = Vector((d.z, 0, -d.x)) if road_right else Vector((-d.z, 0, d.x))     # towards the road
                # covered drain just behind the footpath, a slab per metre
                k = 0.0
                while k < seg:
                    q = a.lerp(c, k / seg) - rw * (hw + 0.38) + Vector((0, -0.04, 0))
                    inst(drain_c, M(q, d))
                    counts["drain"] += 1
                    if int((along + k) / 15.0) != int((along + k - 1.0) / 15.0):
                        inst(grat_c, M(q + Vector((0, 0.05, 0)), d))
                    k += 1.0
                # electric poles on the back edge of the footpath
                while next_pole <= along + seg:
                    q = a.lerp(c, (next_pole - along) / seg) - rw * (hw - 0.2)
                    inst(pole_c, M(q, rw))
                    poles.append(q)
                    counts["pole"] += 1
                    next_pole += 35.0
                # street furniture and parked vehicles
                while next_thing <= along + seg:
                    q = a.lerp(c, (next_thing - along) / seg)
                    roll = rng.random()
                    if main and roll < 0.14:
                        inst(stall_c, M(q - rw * (hw - 1.0), -rw))
                        counts["stall"] += 1
                    elif roll < 0.38 and vehs:
                        # a row of two-wheelers parked on the footpath edge, angled, outside a shop
                        bikes = [v for v in vehs if v[0].startswith("bike")]
                        for j in range(rng.randint(3, 7)):
                            name, vc = bikes[rng.randrange(len(bikes))]
                            qb = q + d * (j * 0.85) + rw * (hw - 0.6)
                            ang = rng.uniform(-0.25, 0.25)
                            inst(vc, M(qb, (rw * math.cos(ang) + d * math.sin(ang)).normalized()))
                            counts["vehicle"] += 1
                    elif roll < 0.45:
                        inst(bin_c, M(q - rw * (hw - 0.4), d))
                        counts["bin"] += 1
                    elif roll < 0.5 and main:
                        inst(flex_c, M(q - rw * (hw - 0.3), -rw))
                        counts["flex"] += 1
                    elif roll < 0.64:
                        inst(cart_c, M(q - rw * (hw - 0.9) + Vector((0, 0.05, 0)), d))
                        counts["cart"] += 1
                    elif roll < 0.7 and main:
                        inst(sign_c, M(q + rw * (hw - 0.3), d))
                        counts["sign"] += 1
                    elif vehs and roll < 0.85:
                        name, vc = vehs[rng.randrange(len(vehs))]
                        bike = name.startswith("bike")
                        # on the road beside the kerb, nose along the traffic (keep left: the road is on the right of
                        # a left-side footpath when road_right)
                        off = 1.0 if bike else (1.3 if "auto" in name else 1.1)
                        rd = d if road_right else -d
                        qv = q + rw * (hw + 0.2 + off) + Vector((0, 0.09 - (0.15 if not bike else 0.0), 0))
                        inst(vc, M(qv, rd))                                  # fleet models: nose +X
                        counts["vehicle"] += 1
                    next_thing += rng.uniform(5, 11) if main else rng.uniform(10, 24)
                # red dust drifted along the kerb on the road
                kq0 = a + rw * (hw + 0.2)
                kq1 = c + rw * (hw + 0.2)
                wd = 0.7
                lo = Vector((0, 0.1, 0))
                b.quad("dust", kq0 + lo, kq1 + lo, kq1 + rw * wd + lo, kq0 + rw * wd + lo,
                       uv=((along, 0), (along + seg, 0), (along + seg, 1), (along, 1)))
                counts["decal"] += 1
                along += seg
            # sagging wires between consecutive poles: three conductors
            for p0, p1 in zip(poles, poles[1:]):
                span = (p1 - p0).length
                if span > 60:
                    continue
                dirw = (p1 - p0).normalized()
                side = Vector((dirw.z, 0, -dirw.x))
                for off in (-0.7, 0.0, 0.7):
                    prev = None
                    for s in range(11):
                        f = s / 10.0
                        q = p0.lerp(p1, f) + side * off + Vector((0, 8.55 - 0.9 * 4 * f * (1 - f), 0))
                        if prev is not None:
                            wire(b, prev, q)
                        prev = q
    # oil stains, cracks and patches on the roads; manholes in the lanes
    for t in tiles:
        for r in t["roads"]:
            cls = classes[r["cid"]]
            p = r["p"]
            if len(p) < 3 or cls in ("footway", "track") or r["fl"] & 2:
                continue
            pts = [Vector(q.tolist()) + Vector((0, 0.09, 0)) for q in p]
            half = r["w"] * 0.5
            for i in range(len(pts) - 1):
                a, c = pts[i], pts[i + 1]
                seg = (c - a).length
                if seg < 0.5:
                    continue
                d = Vector((c.x - a.x, 0, c.z - a.z)).normalized()
                left = Vector((d.z, 0, -d.x))
                r2 = rng.random()
                if r2 < 0.18:                                                     # oil down a lane centre
                    lane = (1.75 if half > 3.5 else half * 0.5) * (1 if rng.random() < 0.5 else -1)
                    q0, q1 = a + left * lane, c + left * lane
                    w = 0.55
                    lift = Vector((0, 0.052, 0))
                    b.quad("oil", q0 - left * w / 2 + lift, q1 - left * w / 2 + lift, q1 + left * w / 2 + lift, q0 + left * w / 2 + lift,
                           uv=((0, 0), (seg, 0), (seg, 1), (0, 1)))
                    counts["decal"] += 1
                elif r2 < 0.24:                                                   # a patched repair
                    q = a.lerp(c, rng.random())
                    off = rng.uniform(-half + 1.0, half - 1.0)
                    pw, pl = rng.uniform(1.2, 2.6), rng.uniform(1.0, 2.2)
                    cc = q + left * off + Vector((0, 0.054, 0))
                    b.quad("patch", cc - d * pl / 2 - left * pw / 2, cc + d * pl / 2 - left * pw / 2,
                           cc + d * pl / 2 + left * pw / 2, cc - d * pl / 2 + left * pw / 2,
                           uv=((0, 0), (1, 0), (1, 1), (0, 1)))
                    counts["decal"] += 1
                elif r2 < 0.3:                                                    # a crack line
                    q = a.lerp(c, rng.random()) + left * rng.uniform(-half + 0.5, half - 0.5)
                    prev = q + Vector((0, 0.056, 0))
                    dd = (d * rng.uniform(-1, 1) + left * rng.uniform(-1, 1)).normalized()
                    for _s in range(rng.randint(4, 8)):
                        dd = (dd + Vector((rng.uniform(-0.6, 0.6), 0, rng.uniform(-0.6, 0.6)))).normalized()
                        nxt = prev + dd * rng.uniform(0.3, 0.7)
                        side = Vector((dd.z, 0, -dd.x)) * 0.012
                        b.quad("crack", prev - side, nxt - side, nxt + side, prev + side)
                        prev = nxt
                    counts["decal"] += 1
                elif r2 < 0.33 and half > 2.5:
                    q = a.lerp(c, rng.random()) + left * rng.uniform(-half * 0.5, half * 0.5)
                    inst(man_c, Matrix.Translation(to_blender(q + Vector((0, 0.045, 0)))))
                    counts["manhole"] += 1
    print("STREETLIFE", counts, flush=True)


def wire(b, p, q):
    """A thin wire from p to q (game frame) as a narrow ribbon, vertical so it shows from below and the side."""
    up = Vector((0, 0.012, 0))
    b.quad("wire", p - up, q - up, q + up, p + up)
