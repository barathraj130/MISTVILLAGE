"""
Indian traffic fleet for The Mist Village, in the same lofted style as the user's coupe / luxury
SUV generators: hatchback, sedan, auto-rickshaw, city bus and lorry at real dimensions, each with
glass, lamps, grille, bumpers, mirrors and wheels. Paint is its own material ("Paint") so the game
can recolour every car in traffic.

    Blender -b --factory-startup --python tools/fleet.py -- godot/assets/vehicles   [kinds...]

Each vehicle is exported as <kind>.glb: one "Body" mesh (everything joined, a few materials),
"Glass", "Headlight" and "TailBar" kept separate (the game drives the lamps), and four (three for
the auto) wheel nodes "Wheel_FL/FR/RL/RR" (or "Wheel_F") so the wheels can spin when you drive.
Blender +X is the nose, +Y the car's left, Z up.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

# ----------------------------------------------------------------------------- scene helpers
def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def make_mat(name, color, metallic=0.0, rough=0.5, coat=0.0, emission=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")

    def s(names, val):
        for n in names:
            if n in b.inputs:
                b.inputs[n].default_value = val
                return
    s(["Base Color"], (*color, 1.0))
    s(["Metallic"], metallic)
    s(["Roughness"], rough)
    s(["Coat Weight", "Clearcoat"], coat)
    s(["Alpha"], alpha)
    if emission:
        s(["Emission Color", "Emission"], (*emission, 1.0))
        s(["Emission Strength"], strength)
    return m


def mats(paint):
    return {
        "paint": make_mat("Paint", paint, metallic=0.5, rough=0.32, coat=0.8),
        "glass": make_mat("Glass", (0.02, 0.025, 0.03), rough=0.04, coat=1.0),
        "black": make_mat("BlackPlastic", (0.015, 0.015, 0.016), rough=0.55),
        "chrome": make_mat("Chrome", (0.8, 0.8, 0.82), metallic=1.0, rough=0.15),
        "tyre": make_mat("Rubber", (0.008, 0.008, 0.008), rough=0.85),
        "rim": make_mat("RimSilver", (0.62, 0.63, 0.65), metallic=1.0, rough=0.28),
        "head": make_mat("Headlight", (0.9, 0.9, 0.92), rough=0.08, emission=(1, 0.97, 0.9), strength=2.0),
        "tail": make_mat("Taillight", (0.5, 0.02, 0.02), rough=0.15, emission=(1, 0.03, 0.01), strength=1.0),
        "amber": make_mat("Amber", (0.9, 0.5, 0.05), rough=0.2),
        "plate": make_mat("Plate", (0.92, 0.92, 0.88), rough=0.5),
        "seat": make_mat("Seat", (0.12, 0.1, 0.09), rough=0.8),
    }


def catmull_rom(keys, steps):
    out, n = [], len(keys)
    for i in range(n - 1):
        p0, p1 = keys[max(i - 1, 0)], keys[i]
        p2, p3 = keys[i + 1], keys[min(i + 2, n - 1)]
        for st in range(steps):
            t = st / steps
            out.append(tuple(
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3)
                for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(keys[-1])
    return out


def section(hw, zb, zt, dip, segs, n_top, n_bot):
    pts = []
    zc, hh = (zb + zt) / 2, (zt - zb) / 2
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        n = n_top if s > 0 else n_bot
        y = hw * math.copysign(abs(c) ** (2 / n), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / n), s)
        if s > 0 and dip > 0:
            z -= dip * math.exp(-(y / (0.45 * hw)) ** 2) * s
        pts.append((y, z))
    return pts


def loft(name, keys, mat, n_top=4.0, n_bot=7.0, segs=32, steps=3, sub=1):
    stations = catmull_rom(keys, steps)
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for y, z in section(hw, zb, zt, dip, segs, n_top, n_bot)]
             for x, hw, zb, zt, dip in stations]
    for r1, r2 in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r1[i], r1[j], r2[j], r2[i]))
    for ring, push in ((rings[0], 0.02), (rings[-1], -0.02)):
        c = sum((v.co for v in ring), Vector()) / len(ring)
        c.x += push
        cv = bm.verts.new(c)
        for i in range(segs):
            bm.faces.new((ring[i], ring[(i + 1) % segs], cv))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    obj.data.materials.append(mat)
    smooth(obj)
    if sub:
        m = obj.modifiers.new("Subsurf", 'SUBSURF')
        m.levels = sub
        m.render_levels = sub
    return obj


def box(name, loc, dims, mat, bev=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = dims
    o.data.materials.append(mat)
    if bev:
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = bev
        b.segments = 2
    return o


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    smooth(o)
    return o


def arch_cut(body, x, y_side, z, r, depth=0.5):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=depth, location=(x, y_side, z),
                                        rotation=(math.pi / 2, 0, 0))
    cutter = bpy.context.active_object
    cutter.name = "ArchCutter"
    mod = body.modifiers.new("Arch", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cutter
    mod.solver = 'EXACT'
    return cutter


def wheel(name, loc, R, width, M, outward_positive_y=True, spokes=5, hub_cap=False):
    root = link(bpy.data.objects.new(name, None))
    root.location = loc
    if not outward_positive_y:
        root.rotation_euler = (0, 0, math.pi)
    parts = []
    bpy.ops.mesh.primitive_torus_add(major_radius=R - width * 0.42, minor_radius=width * 0.42,
                                     major_segments=32, minor_segments=12, rotation=(math.pi / 2, 0, 0))
    t = bpy.context.active_object
    t.scale = (1, 1, 1.2)
    t.data.materials.append(M["tyre"])
    parts.append(t)
    rim_r = R - width * 0.8
    parts.append(cyl("Rim", (0, 0, 0), rim_r, width * 0.9, M["black" if hub_cap else "rim"], rot=(math.pi / 2, 0, 0), verts=24))
    if hub_cap:
        parts.append(cyl("Cap", (0, width * 0.46, 0), rim_r * 0.9, 0.02, M["rim"], rot=(math.pi / 2, 0, 0)))
    else:
        for k in range(spokes):
            th = 2 * math.pi * k / spokes
            sp = box("Spoke", (rim_r * 0.5 * math.sin(th), width * 0.45, rim_r * 0.5 * math.cos(th)),
                     (0.045 * R / 0.3, 0.02, rim_r), M["rim"], bev=0, rot=(0, th, 0))
            parts.append(sp)
    parts.append(cyl("Hub", (0, width * 0.5, 0), 0.05 * R / 0.3, 0.03, M["chrome"], rot=(math.pi / 2, 0, 0), verts=12))
    for p in parts:
        p.parent = root
        smooth(p)
    return root


def lamp_pair(x, y, z, size, M, name, mat_key, rot=(0, 0, 0)):
    out = []
    for s in (1, -1):
        out.append(box(name, (x, s * y, z), size, M[mat_key], bev=0.008, rot=rot))
    return out


# ----------------------------------------------------------------------------- cars
def car(kind, M):
    if kind == "hatchback":
        L2, wb_f, wb_r, R, track = 1.92, 1.22, -1.23, 0.29, 0.75
        body_keys = [(1.92, 0.55, 0.30, 0.55, 0), (1.85, 0.80, 0.24, 0.68, 0.01), (1.60, 0.85, 0.22, 0.80, 0.03),
                     (1.20, 0.86, 0.22, 0.86, 0.03), (0.6, 0.86, 0.22, 0.89, 0), (0.0, 0.86, 0.22, 0.91, 0),
                     (-1.0, 0.86, 0.22, 0.93, 0), (-1.6, 0.85, 0.24, 0.94, 0), (-1.86, 0.80, 0.30, 0.94, 0),
                     (-1.93, 0.62, 0.40, 0.90, 0)]
        cab_keys = [(0.95, 0.74, 0.86, 0.90, 0), (0.62, 0.73, 0.86, 1.22, 0), (0.2, 0.71, 0.86, 1.44, 0),
                    (-0.7, 0.70, 0.86, 1.49, 0), (-1.45, 0.68, 0.86, 1.47, 0), (-1.78, 0.62, 0.86, 1.28, 0),
                    (-1.87, 0.55, 0.86, 1.0, 0)]
        roof = ((-0.65, 0, 1.475), (1.75, 1.3, 0.04))
        pillars = [(0.72, 0.06), (-0.25, 0.08), (-1.55, 0.18)]
    else:  # sedan
        L2, wb_f, wb_r, R, track = 2.2, 1.33, -1.30, 0.30, 0.76
        body_keys = [(2.2, 0.55, 0.30, 0.55, 0), (2.12, 0.80, 0.24, 0.66, 0.01), (1.85, 0.86, 0.22, 0.78, 0.03),
                     (1.4, 0.87, 0.22, 0.84, 0.03), (0.8, 0.87, 0.22, 0.88, 0), (0.0, 0.87, 0.22, 0.90, 0),
                     (-1.0, 0.87, 0.22, 0.92, 0), (-1.7, 0.86, 0.24, 0.95, 0), (-2.1, 0.80, 0.30, 0.95, 0),
                     (-2.21, 0.62, 0.40, 0.90, 0)]
        cab_keys = [(1.0, 0.74, 0.86, 0.90, 0), (0.7, 0.73, 0.86, 1.2, 0), (0.3, 0.71, 0.86, 1.42, 0),
                    (-0.5, 0.70, 0.86, 1.46, 0), (-1.1, 0.68, 0.86, 1.36, 0), (-1.45, 0.63, 0.86, 1.06, 0),
                    (-1.62, 0.56, 0.86, 0.93, 0)]
        roof = ((-0.42, 0, 1.445), (1.2, 1.3, 0.04))
        pillars = [(0.78, 0.06), (-0.2, 0.08), (-1.3, 0.12)]
    body = loft("Body", body_keys, M["paint"], n_top=4.5, n_bot=7.0)
    cutters = []
    for ax in (wb_f, wb_r):
        for s in (1, -1):
            cutters.append(arch_cut(body, ax, s * (track + 0.1), R, R + 0.05))
    loft("Glass", cab_keys, M["glass"], n_top=5.0, n_bot=8.0)
    # painted roof: a thin shell hugging the glass from the top of the windscreen to the rear glass
    # only over the flat top of the glasshouse, so it never dips into the windscreen view
    top_z = max(k[3] for k in cab_keys)
    roof_keys = [(x, hw * 1.005, zt - 0.05, zt + 0.012, 0) for x, hw, zb, zt, dip in cab_keys if zt >= top_z - 0.07]
    loft("Roof", roof_keys, M["paint"], n_top=5.0, n_bot=30.0)

    def glass_top(x):
        ks = sorted(cab_keys, key=lambda k: k[0])
        for a, b in zip(ks, ks[1:]):
            if a[0] <= x <= b[0]:
                t = (x - a[0]) / (b[0] - a[0])
                return a[3] + (b[3] - a[3]) * t, a[1] + (b[1] - a[1]) * t
        return ks[-1][3], ks[-1][1]
    for s in (1, -1):
        for x, w in pillars[1:]:                       # B and C pillars, up to the roofline
            top, hw = glass_top(x)
            h = top - 0.9
            box("Pillar", (x, s * (hw - 0.01), 0.9 + h / 2), (w, 0.03, h), M["paint"], bev=0.005)
        box("Mirror", (0.78, s * 0.9, 1.0), (0.12, 0.14, 0.09), M["paint"], bev=0.02)
        box("MirrorArm", (0.78, s * 0.82, 0.96), (0.05, 0.08, 0.03), M["black"], bev=0)
        box("Handle", (0.15, s * 0.87, 0.82), (0.14, 0.02, 0.025), M["chrome"], bev=0.005)
        box("Handle", (-0.75, s * 0.87, 0.82), (0.14, 0.02, 0.025), M["chrome"], bev=0.005)
        box("DoorGap", (-0.3, s * 0.875, 0.55), (0.006, 0.01, 0.6), M["black"], bev=0)
        box("Skirt", ((wb_f + wb_r) / 2, s * 0.85, 0.27), (abs(wb_f - wb_r) - 0.7, 0.04, 0.07), M["black"], bev=0.01)
    # front: grille, bumper, lamps, plate
    box("Grille", (L2 - 0.02, 0, 0.5), (0.04, 0.62, 0.14), M["black"], bev=0.01)
    box("GrilleChrome", (L2 - 0.0, 0, 0.58), (0.02, 0.6, 0.015), M["chrome"], bev=0)
    box("BumperF", (L2 - 0.05, 0, 0.33), (0.08, 1.5, 0.1), M["black"], bev=0.02)
    box("PlateF", (L2 + 0.0, 0, 0.36), (0.01, 0.5, 0.11), M["plate"], bev=0)
    heads = lamp_pair(L2 - 0.08, 0.6, 0.64, (0.06, 0.22, 0.07), M, "Headlight", "head")
    lamp_pair(L2 - 0.05, 0.62, 0.36, (0.03, 0.1, 0.03), M, "Fog", "amber")
    # rear
    box("BumperR", (-L2 + 0.04, 0, 0.36), (0.08, 1.5, 0.12), M["black"], bev=0.02)
    box("PlateR", (-L2 - 0.0, 0, 0.55), (0.01, 0.5, 0.11), M["plate"], bev=0)
    tails = lamp_pair(-L2 + 0.04, 0.62, 0.78, (0.05, 0.2, 0.09), M, "TailBar", "tail")
    for s in (1, -1):
        wheel("Wheel_F" + ("L" if s > 0 else "R"), (wb_f, s * track, R), R, 0.19, M, s > 0, spokes=5 if kind == "sedan" else 0, hub_cap=kind == "hatchback")
        wheel("Wheel_R" + ("L" if s > 0 else "R"), (wb_r, s * track, R), R, 0.19, M, s > 0, spokes=5 if kind == "sedan" else 0, hub_cap=kind == "hatchback")
    return cutters


# ----------------------------------------------------------------------------- auto-rickshaw
def auto(M):
    yellow = make_mat("Accent", (0.85, 0.62, 0.05), rough=0.45, coat=0.3)
    canvas = make_mat("Canvas", (0.03, 0.03, 0.03), rough=0.9)
    tub = loft("Body", [(1.32, 0.24, 0.32, 0.95, 0), (1.18, 0.36, 0.28, 1.04, 0), (0.92, 0.44, 0.28, 1.0, 0),
                        (0.55, 0.62, 0.28, 0.72, 0), (-0.6, 0.65, 0.28, 0.78, 0), (-1.22, 0.62, 0.30, 0.82, 0),
                        (-1.32, 0.5, 0.36, 0.80, 0)], M["paint"], n_top=5.0, n_bot=6.0)
    # a thin rounded canvas roof on posts, open at the sides, closed at the back
    loft("Canopy", [(0.86, 0.6, 1.5, 1.62, 0), (0.6, 0.65, 1.52, 1.78, 0), (-0.4, 0.66, 1.52, 1.82, 0),
                    (-1.12, 0.64, 1.5, 1.76, 0), (-1.22, 0.6, 1.48, 1.6, 0)], canvas, n_top=3.0, n_bot=30.0)
    box("BackCanvas", (-1.2, 0, 1.2), (0.03, 1.24, 0.62), canvas, bev=0.01)
    box("RoofFrame", (-0.2, 0, 1.5), (2.1, 1.28, 0.03), M["black"], bev=0)
    box("GlassWindscreen", (0.9, 0, 1.3), (0.02, 0.9, 0.5), M["glass"], bev=0.01, rot=(0, math.radians(-12), 0))
    box("Stripe", (-0.3, 0, 0.74), (1.95, 1.27, 0.05), yellow, bev=0.01)
    box("CowlYellow", (1.08, 0, 0.98), (0.3, 0.5, 0.08), yellow, bev=0.03)
    box("Bench", (-0.55, 0, 0.72), (0.5, 1.1, 0.12), M["seat"], bev=0.03)
    box("BenchBack", (-0.85, 0, 0.98), (0.1, 1.1, 0.42), M["seat"], bev=0.03)
    box("DriverSeat", (0.35, 0, 0.82), (0.32, 0.34, 0.1), M["seat"], bev=0.03)
    box("Handlebar", (0.72, 0, 1.08), (0.04, 0.62, 0.03), M["chrome"], bev=0)
    for s in (1, -1):
        box("Post", (0.84, s * 0.6, 1.25), (0.035, 0.035, 0.55), M["black"], bev=0)
        box("PostM", (-0.2, s * 0.64, 1.15), (0.035, 0.035, 0.75), M["black"], bev=0)
        box("PostR", (-1.18, s * 0.62, 1.15), (0.035, 0.035, 0.7), M["black"], bev=0)
        box("Mirror", (0.95, s * 0.5, 1.45), (0.04, 0.1, 0.08), M["black"], bev=0.01)
    box("Headlight", (1.33, 0, 0.82), (0.05, 0.16, 0.12), M["head"], bev=0.02)
    box("TailBar", (-1.33, 0, 0.62), (0.03, 0.9, 0.05), M["tail"], bev=0.005)
    box("PlateR", (-1.34, 0, 0.47), (0.01, 0.34, 0.1), M["plate"], bev=0)
    wheel("Wheel_F", (1.02, 0, 0.22), 0.22, 0.12, M, True, hub_cap=True)
    wheel("Wheel_RL", (-0.85, 0.55, 0.22), 0.22, 0.12, M, True, hub_cap=True)
    wheel("Wheel_RR", (-0.85, -0.55, 0.22), 0.22, 0.12, M, False, hub_cap=True)
    return []


# ----------------------------------------------------------------------------- bus
def bus(M):
    cream = make_mat("Accent", (0.82, 0.76, 0.6), rough=0.5)
    body = loft("Body", [(5.25, 1.12, 0.42, 2.95, 0), (5.18, 1.24, 0.36, 3.06, 0), (4.9, 1.26, 0.35, 3.1, 0),
                         (-4.9, 1.26, 0.35, 3.1, 0), (-5.2, 1.24, 0.38, 3.06, 0), (-5.27, 1.12, 0.45, 2.95, 0)],
                M["paint"], n_top=9.0, n_bot=10.0, segs=24, steps=2)
    cutters = []
    for ax in (3.2, -2.6):
        for s in (1, -1):
            cutters.append(arch_cut(body, ax, s * 1.25, 0.5, 0.58, depth=0.4))
    box("Glass", (5.22, 0, 2.15), (0.06, 2.3, 1.15), M["glass"], bev=0.02, rot=(0, math.radians(-6), 0))
    for s in (1, -1):
        box("Glass", (-0.3, s * 1.27, 2.2), (9.0, 0.02, 0.85), M["glass"], bev=0.01)
        box("Belt", (0.0, s * 1.275, 1.62), (10.2, 0.02, 0.22), cream, bev=0)
        for x in [-4.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
            box("Mullion", (x + 0.5, s * 1.282, 2.2), (0.06, 0.02, 0.86), M["paint"], bev=0)
        box("Mirror", (5.25, s * 1.42, 2.45), (0.08, 0.12, 0.35), M["black"], bev=0.02)
    box("Door", (4.2, 1.272, 1.55), (1.0, 0.02, 2.2), M["black"], bev=0.01)
    box("Door", (-1.2, 1.272, 1.55), (1.0, 0.02, 2.2), M["black"], bev=0.01)
    box("RouteBoard", (5.24, 0, 2.88), (0.04, 1.6, 0.22), make_mat("Board", (0.05, 0.03, 0.0), emission=(1.0, 0.55, 0.05), strength=3.0), bev=0)
    box("BumperF", (5.28, 0, 0.5), (0.1, 2.45, 0.22), M["black"], bev=0.03)
    box("BumperR", (-5.3, 0, 0.55), (0.1, 2.45, 0.22), M["black"], bev=0.03)
    box("Grille", (5.27, 0, 0.95), (0.03, 1.2, 0.35), M["black"], bev=0.01)
    box("PlateF", (5.3, 0, 0.62), (0.01, 0.55, 0.13), M["plate"], bev=0)
    box("PlateR", (-5.32, 0, 0.9), (0.01, 0.55, 0.13), M["plate"], bev=0)
    box("RearGlass", (-5.27, 0, 2.3), (0.03, 2.0, 0.8), M["glass"], bev=0.01)
    lamp_pair(5.28, 0.95, 0.95, (0.05, 0.22, 0.16), M, "Headlight", "head")
    lamp_pair(-5.29, 1.0, 1.1, (0.04, 0.12, 0.35), M, "TailBar", "tail")
    for ax, nm in ((3.2, "F"), (-2.6, "R")):
        wheel("Wheel_%sL" % nm, (ax, 1.02, 0.5), 0.5, 0.3, M, True, hub_cap=True)
        wheel("Wheel_%sR" % nm, (ax, -1.02, 0.5), 0.5, 0.3, M, False, hub_cap=True)
    return cutters


# ----------------------------------------------------------------------------- lorry
def lorry(M):
    wood = make_mat("Accent", (0.42, 0.22, 0.08), rough=0.7)
    cab = loft("Body", [(4.55, 1.05, 0.9, 2.2, 0), (4.4, 1.2, 0.8, 2.75, 0), (3.6, 1.24, 0.8, 3.0, 0),
                        (2.75, 1.24, 0.8, 3.05, 0), (2.62, 1.18, 0.85, 2.95, 0)], M["paint"], n_top=7.0, n_bot=8.0, segs=24, steps=2)
    box("Glass", (4.46, 0, 2.3), (0.05, 2.0, 0.65), M["glass"], bev=0.01, rot=(0, math.radians(-10), 0))
    for s in (1, -1):
        box("Glass", (3.75, s * 1.245, 2.35), (0.9, 0.02, 0.55), M["glass"], bev=0.01)
        box("Mirror", (4.45, s * 1.45, 2.3), (0.06, 0.1, 0.4), M["black"], bev=0.02)
        box("Step", (4.0, s * 1.15, 0.65), (0.6, 0.18, 0.05), M["black"], bev=0)
        box("CargoSide", (-1.0, s * 1.24, 1.9), (6.9, 0.06, 1.75), wood, bev=0.01)
        for x in (-4.0, -2.5, -1.0, 0.5, 2.0):
            box("Post", (x, s * 1.28, 1.9), (0.08, 0.04, 1.8), M["paint"], bev=0)
    box("Chassis", (0.0, 0, 0.75), (9.0, 1.2, 0.22), M["black"], bev=0.01)
    box("CargoFloor", (-1.0, 0, 1.0), (6.9, 2.5, 0.12), wood, bev=0.01)
    box("CargoFront", (2.45, 0, 1.9), (0.06, 2.5, 1.75), wood, bev=0.01)
    box("CargoRear", (-4.45, 0, 1.6), (0.06, 2.5, 1.1), wood, bev=0.01)
    box("Grille", (4.57, 0, 1.35), (0.03, 1.3, 0.5), M["chrome"], bev=0.01)
    box("BumperF", (4.6, 0, 0.85), (0.12, 2.3, 0.22), M["black"], bev=0.03)
    box("PlateF", (4.68, 0, 0.85), (0.01, 0.55, 0.13), M["plate"], bev=0)
    box("PlateR", (-4.5, 0, 0.9), (0.01, 0.55, 0.13), M["plate"], bev=0)
    lamp_pair(4.58, 0.85, 1.25, (0.05, 0.2, 0.16), M, "Headlight", "head")
    lamp_pair(-4.5, 1.0, 0.95, (0.04, 0.2, 0.1), M, "TailBar", "tail")
    for ax, nm in ((3.55, "F"), (-2.4, "R")):
        wheel("Wheel_%sL" % nm, (ax, 1.0, 0.52), 0.52, 0.32, M, True, hub_cap=True)
        wheel("Wheel_%sR" % nm, (ax, -1.0, 0.52), 0.52, 0.32, M, False, hub_cap=True)
    for s in (1, -1):    # tandem rear axle (visual)
        w = wheel("Tandem", (-3.45, s * 1.0, 0.52), 0.52, 0.32, M, s > 0, hub_cap=True)
        w.name = "TandemWheel"
    return []


# ----------------------------------------------------------------------------- export
PAINT = {"hatchback": (0.6, 0.6, 0.62), "sedan": (0.55, 0.05, 0.04), "auto": (0.1, 0.33, 0.12),
         "bus": (0.06, 0.2, 0.5), "lorry": (0.85, 0.42, 0.05)}
BUILD = {"hatchback": lambda M: car("hatchback", M), "sedan": lambda M: car("sedan", M),
         "auto": auto, "bus": bus, "lorry": lorry}
KEEP = ("Glass", "Headlight", "TailBar", "Wheel_", "Canopy")


def finish(out_path):
    # apply modifiers, drop cutters, join every remaining loose part into "Body"
    for o in list(bpy.data.objects):
        if o.name.startswith("ArchCutter"):
            continue
        if o.type == 'MESH':
            bpy.context.view_layer.objects.active = o
            for m in list(o.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
    for o in list(bpy.data.objects):
        if o.name.startswith("ArchCutter"):
            bpy.data.objects.remove(o, do_unlink=True)
    groups = {"Body": [], "Glass": [], "Headlight": [], "TailBar": []}
    for o in bpy.data.objects:
        if o.type != 'MESH' or o.parent is not None:
            continue
        key = next((k for k in ("Glass", "Headlight", "TailBar") if o.name.startswith(k)), "Body")
        if o.name.startswith("Canopy"):
            key = "Body"
        groups[key].append(o)
    for key, objs in groups.items():
        if not objs:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = key
    # each wheel's parts into one mesh under its empty
    for root in [o for o in bpy.data.objects if o.type == 'EMPTY']:
        kids = [c for c in root.children if c.type == 'MESH']
        if len(kids) > 1:
            bpy.ops.object.select_all(action='DESELECT')
            for k in kids:
                k.select_set(True)
            bpy.context.view_layer.objects.active = kids[0]
            bpy.ops.object.join()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_materials='EXPORT')
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    print("FLEET exported", out_path, "objects", len(bpy.data.objects), "tris", tris)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/vehicles")
    kinds = args[1:] or list(BUILD.keys())
    os.makedirs(out_dir, exist_ok=True)
    for kind in kinds:
        reset()
        M = mats(PAINT[kind])
        BUILD[kind](M)
        finish(os.path.join(out_dir, "fleet_%s.glb" % kind))
