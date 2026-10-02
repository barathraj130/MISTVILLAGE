"""
Cabins for every vehicle in The Mist Village, designed in Blender to fit each body (from fleet.py
and coupe.py): a different interior for each design, not one generic dash.

    Blender -b --factory-startup --python tools/interiors.py -- godot/assets/vehicles [kinds...]

    hatchback   budget Indian hatch: grey/beige plastics, hooded twin dials, 2-DIN radio,
                round vents, fabric seats, 4-spoke wheel, manual gear lever, handbrake
    sedan       two-tone black/beige with a faux-wood strip, touchscreen, armrest, rear bench
    taxi        the sedan cabin with white seat covers and a meter on the dash
    coupe       sporty: black/red, bucket seats with harness slots, flat-bottom wheel, carbon dash
    auto        auto-rickshaw: handlebar, meter box, small driver seat, rexine rear bench,
                canvas roof lining, side grab bars, string of tassels across the front
    bus         town bus: big flat wheel, gauge panel, long gear stick, partition, blue seat rows,
                grab poles and rail, tube lights, colourful windscreen fringe
    lorry       Indian lorry cab: high dash with stickers, big wheel, long bench seat, curtain,
                decorated windscreen fringe

Each export (interior_<kind>.glb) carries: the cabin mesh(es), a "SteeringPivot" empty whose
local Z is the steering column (the game turns the wheel about it), and empties "Eye" (the
driver's eyes, for the cockpit camera) and "Cluster" (where the instruments sit).
Blender +X is the nose, +Y the car's left; the driver sits on the right (India).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for coll in (bpy.data.meshes, bpy.data.materials):
        for b in list(coll):
            if b.users == 0:
                coll.remove(b)


def mat(name, color, rough=0.7, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        for n in ("Emission Color", "Emission"):
            if n in b.inputs:
                b.inputs[n].default_value = (*emit, 1.0)
                break
        b.inputs["Emission Strength"].default_value = strength
    return m


def box(loc, dims, m, bev=0.01, rot=(0, 0, 0), soft=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = dims
    o.data.materials.append(m)
    if bev:
        mod = o.modifiers.new("Bevel", 'BEVEL')
        mod.width = bev
        mod.segments = 3 if soft else 1
    if soft:
        s = o.modifiers.new("Sub", 'SUBSURF')
        s.levels = 1
        s.render_levels = 1
        for p in o.data.polygons:
            p.use_smooth = True
    return o


def cyl(loc, r, depth, m, rot=(0, 0, 0), verts=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def empty(name, loc, rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.rotation_euler = rot
    bpy.context.scene.collection.objects.link(e)
    return e


# ----------------------------------------------------------------------------- shared pieces
def seat(x, y, z, w, M, cushion, back_h=0.6, lean=-14, bucket=False, headrest=True, cover=None):
    m = M[cushion]
    box((x, y, z), (0.5, w, 0.12), m, bev=0.03, soft=True)
    box((x - 0.28, y, z + 0.33), (0.12, w, back_h), m, bev=0.03, soft=True, rot=(0, math.radians(lean), 0))
    if bucket:
        for s in (1, -1):
            box((x, y + s * (w / 2 - 0.03), z + 0.06), (0.48, 0.07, 0.14), m, bev=0.02, soft=True)
            box((x - 0.26, y + s * (w / 2 - 0.03), z + 0.32), (0.14, 0.08, back_h * 0.8), m, bev=0.02, soft=True,
                rot=(0, math.radians(lean), 0))
    if headrest:
        box((x - 0.36, y, z + 0.33 + back_h * 0.5 + 0.1), (0.09, w * 0.5, 0.16), m, bev=0.03, soft=True, rot=(0, math.radians(lean), 0))
    if cover:
        box((x - 0.27, y, z + 0.3), (0.13, w * 0.92, back_h * 0.85), M[cover], bev=0.01, rot=(0, math.radians(lean), 0))
    box((x, y, z - 0.12), (0.36, w * 0.7, 0.12), M["dark"], bev=0.01)        # seat base


def steering(centre, toward_driver_deg, r, M, spokes=3, rim="rim", flat_bottom=False, big=False):
    """Wheel on a pivot empty. toward_driver_deg: column angle above horizontal (pointing back)."""
    a = math.radians(toward_driver_deg)
    piv = empty("SteeringPivot", centre)
    # local Z = column axis pointing back-up at the driver
    z = Vector((-math.cos(a), 0, math.sin(a)))
    x = Vector((0, 1, 0))
    y = z.cross(x)
    piv.matrix_world = Matrix.Translation(centre) @ Matrix((x, y, z)).transposed().to_4x4()
    parts = []
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.018 if not big else 0.02, major_segments=40, minor_segments=10)
    t = bpy.context.active_object
    t.data.materials.append(M[rim])
    if flat_bottom:
        t.scale = (1.0, 1.0, 1.0)
    parts.append(t)
    for k in range(spokes):
        ang = -math.pi / 2 + (math.pi * 2 * k / spokes if spokes != 3 else [0, math.pi * 0.5, math.pi][k] - math.pi / 2 + math.pi)
        if spokes == 3:
            ang = [0.0, math.pi, -math.pi / 2][k]
        if spokes == 4:
            ang = math.pi / 4 + math.pi / 2 * k
        sp = box((math.cos(ang) * r * 0.5, math.sin(ang) * r * 0.5, 0.0), (r * 0.95 if spokes != 4 else r * 0.9, 0.04, 0.012),
                 M["dark"], bev=0.005, rot=(0, 0, ang))
        parts.append(sp)
    hub = cyl((0, 0, 0.012), 0.055 if not big else 0.07, 0.03, M["dark"])
    parts.append(hub)
    for p in parts:
        p.parent = piv
        p.matrix_parent_inverse = Matrix.Identity(4)
    # column
    col = cyl(Vector(centre) - z * 0.2, 0.03, 0.4, M["dark"])
    col.rotation_euler = (0, math.radians(90) - a + math.pi, 0)
    col.rotation_euler = (0, -(math.pi / 2 - a), 0)
    return piv


def door_panels(x0, x1, hw, z0, M, base, trim, handle="chrome"):
    for s in (1, -1):
        box(((x0 + x1) / 2, s * (hw - 0.02), z0 + 0.25), (x1 - x0, 0.04, 0.5), M[base], bev=0.01)
        box(((x0 + x1) / 2, s * (hw - 0.05), z0 + 0.38), (x1 - x0 - 0.1, 0.06, 0.05), M[trim], bev=0.01, soft=True)   # armrest
        box((x1 - 0.25, s * (hw - 0.05), z0 + 0.45), (0.1, 0.02, 0.03), M[handle], bev=0.005)


# ----------------------------------------------------------------------------- cars
def car(kind, M):
    P = {
        "hatchback": dict(dash_x=0.62, top=0.93, hw=0.7, floor=0.3, roof=1.42, seat_x=-0.3, rear_x=-1.15, eye=(-0.33, -0.36, 1.2)),
        "sedan": dict(dash_x=0.66, top=0.93, hw=0.71, floor=0.3, roof=1.4, seat_x=-0.25, rear_x=-1.05, eye=(-0.28, -0.36, 1.19)),
        "taxi": dict(dash_x=0.66, top=0.93, hw=0.71, floor=0.3, roof=1.4, seat_x=-0.25, rear_x=-1.05, eye=(-0.28, -0.36, 1.19)),
        "coupe": dict(dash_x=0.52, top=0.85, hw=0.66, floor=0.22, roof=1.18, seat_x=-0.42, rear_x=None, eye=(-0.47, -0.38, 1.06)),
    }[kind]
    dx, top, hw, fl, roof = P["dash_x"], P["top"], P["hw"], P["floor"], P["roof"]
    ey = P["eye"]
    look = {"hatchback": ("plastic", "plastic2", "fabric"), "sedan": ("dark", "beige", "beige_fab"),
            "taxi": ("dark", "beige", "cover"), "coupe": ("carbon", "dark", "red_leather")}[kind]
    main, lower, seats = look
    # dashboard: a long padded top over a stepped face, hood over the driver's dials
    box((dx + 0.22, 0, top - 0.06), (0.46, hw * 2 - 0.04, 0.14), M[main], bev=0.04, soft=True)
    box((dx + 0.1, 0, top - 0.24), (0.24, hw * 2 - 0.06, 0.26), M[lower], bev=0.03, soft=True)
    box((dx + 0.05, ey[1], top + 0.02), (0.2, 0.42, 0.07), M[main], bev=0.03, soft=True)             # dial hood
    cluster_at = (dx - 0.04, ey[1], top - 0.04)
    # centre stack
    if kind == "hatchback":
        box((dx - 0.02, 0.0, top - 0.25), (0.04, 0.24, 0.12), M["screen_off"], bev=0.005)            # 2-DIN radio
        for k in range(6):
            cyl((dx - 0.045, -0.08 + k * 0.032, top - 0.25), 0.009, 0.01, M["chrome"], rot=(0, math.pi / 2, 0), verts=8)
        for sy in (-0.12, 0.12):
            cyl((dx - 0.02, sy, top - 0.1), 0.045, 0.03, M["dark"], rot=(0, math.pi / 2, 0))          # round vents
            cyl((dx - 0.035, sy, top - 0.1), 0.03, 0.01, M["chrome"], rot=(0, math.pi / 2, 0))
    else:
        box((dx - 0.03, 0.0, top - 0.16), (0.03, 0.3, 0.18), M["screen"], bev=0.005, rot=(0, math.radians(-10), 0))
        for sy in (-0.2, 0.2):
            box((dx - 0.02, sy, top - 0.12), (0.03, 0.12, 0.05), M["dark"], bev=0.005)               # slim vents
    if kind in ("sedan", "taxi"):
        box((dx - 0.03, 0, top - 0.33), (0.03, hw * 2 - 0.2, 0.035), M["wood"], bev=0.004)           # wood strip
    if kind == "coupe":
        box((dx - 0.0, 0, top - 0.3), (0.03, hw * 2 - 0.2, 0.012), M["red_leather"], bev=0.002)      # red stitch line
    if kind == "taxi":
        box((dx + 0.18, 0.18, top + 0.06), (0.12, 0.16, 0.08), M["dark"], bev=0.01)                  # fare meter
        box((dx + 0.12, 0.18, top + 0.07), (0.01, 0.12, 0.04), M["meter"], bev=0)
    for sy in (-hw + 0.1, hw - 0.1):
        cyl((dx - 0.02, sy, top - 0.1), 0.04, 0.03, M["dark"], rot=(0, math.pi / 2, 0))               # side vents
    # glovebox, console, gear lever, handbrake, pedals
    box((dx + 0.02, 0.36, top - 0.32), (0.04, 0.4, 0.14), M[lower], bev=0.02)
    box((dx - 0.6, 0, fl + 0.18), (1.2, 0.2, 0.3), M["dark"], bev=0.02, soft=True)
    cyl((dx - 0.4, 0, fl + 0.4), 0.008, 0.22, M["chrome"], rot=(math.radians(-12), 0, 0), verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.03, location=(dx - 0.42, 0, fl + 0.52))
    bpy.context.active_object.data.materials.append(M["dark"])
    box((dx - 0.75, 0, fl + 0.38), (0.25, 0.05, 0.04), M["dark"], bev=0.01, rot=(0, math.radians(-15), 0))   # handbrake
    for k, sy in enumerate((-0.27, -0.36, -0.45)):
        box((dx + 0.12, ey[1] + (sy + 0.36), fl + 0.12), (0.03, 0.06 if k else 0.09, 0.08), M["dark"], bev=0.005,
            rot=(0, math.radians(30), 0))
    # floor, headliner, door panels, seats, mirror, visors
    box((-0.3, 0, fl), (2.4, hw * 2, 0.03), M["carpet"], bev=0)
    box((-0.45, 0, roof), (1.9, hw * 2 - 0.1, 0.025), M["headliner"], bev=0.01)
    door_panels(-1.4 if P["rear_x"] else -0.9, dx, hw, fl + 0.1, M, lower, seats if kind != "taxi" else "beige")
    for sy, x in ((ey[1], P["seat_x"]), (-ey[1], P["seat_x"])):
        seat(x, sy, fl + 0.3, 0.5, M, seats, bucket=(kind == "coupe"), cover=("cover" if kind == "taxi" else None),
             back_h=0.62 if kind != "coupe" else 0.7)
    if P["rear_x"]:
        seat(P["rear_x"], 0, fl + 0.3, 1.32, M, seats, back_h=0.55, headrest=False,
             cover=("cover" if kind == "taxi" else None))
    box((dx - 0.15, 0, roof - 0.07), (0.05, 0.22, 0.06), M["dark"], bev=0.01)                       # rear-view mirror
    for s in (1, -1):
        box((dx - 0.1, s * 0.35, roof - 0.03), (0.16, 0.36, 0.02), M["headliner"], bev=0.01, rot=(0, math.radians(8), 0))
    wheel_c = Vector((ey[0] + 0.44, ey[1], ey[2] - 0.33))   # ~45 cm ahead of the chest, as you'd sit
    steering(wheel_c, 62 if kind != "coupe" else 68, 0.18 if kind != "coupe" else 0.17, M,
             spokes=4 if kind == "hatchback" else 3, rim="rim" if kind != "coupe" else "alcantara")
    empty("Eye", ey)
    empty("Cluster", cluster_at)


# ----------------------------------------------------------------------------- auto-rickshaw
def auto(M):
    # front: handlebar on a column, meter box, kick-start lever; driver's small seat
    cyl((0.8, 0, 0.95), 0.025, 0.4, M["dark"], rot=(0, math.radians(-25), 0))
    box((0.98, 0, 1.18), (0.12, 0.2, 0.12), M["dark"], bev=0.02)                                     # meter / headlamp box
    box((0.92, 0, 1.2), (0.01, 0.14, 0.06), M["meter"], bev=0)
    box((0.62, 0, 0.82), (0.4, 0.36, 0.1), M["rexine"], bev=0.03, soft=True)                          # driver seat
    box((0.5, 0, 0.98), (0.08, 0.36, 0.25), M["rexine"], bev=0.03, soft=True)
    box((-0.55, 0, 0.72), (0.5, 1.12, 0.14), M["rexine"], bev=0.03, soft=True)                        # rear bench
    box((-0.86, 0, 0.98), (0.12, 1.12, 0.42), M["rexine"], bev=0.03, soft=True)
    box((0.2, 0, 0.6), (1.4, 1.1, 0.02), M["floor_mat"], bev=0)
    box((-0.2, 0, 1.49), (2.0, 1.2, 0.02), M["canvas_in"], bev=0)                                    # roof lining
    for s in (1, -1):
        cyl((-0.15, s * 0.6, 1.25), 0.012, 1.5, M["chrome"], rot=(0, math.pi / 2, 0), verts=8)       # grab bars
    # tassels across the front (a very Indian touch)
    for k in range(13):
        y = -0.55 + k * 0.092
        col = ["tassel_r", "tassel_y", "tassel_g"][k % 3]
        box((0.86, y, 1.42), (0.02, 0.03, 0.09), M[col], bev=0.004)
    cyl((0.86, 0, 1.47), 0.006, 1.15, M["dark"], rot=(math.pi / 2, 0, 0), verts=6)
    # handlebar as the "steering wheel": a bar on a pivot (turns with the steering)
    piv = empty("SteeringPivot", (0.72, 0, 1.08))
    a = math.radians(55)
    z = Vector((-math.cos(a), 0, math.sin(a)))
    x = Vector((0, 1, 0))
    y = z.cross(x)
    piv.matrix_world = Matrix.Translation((0.72, 0, 1.08)) @ Matrix((x, y, z)).transposed().to_4x4()
    # the bar runs across the pivot's local X (the vehicle's width)
    bar = cyl((0, 0, 0), 0.014, 0.66, M["chrome"], rot=(0, math.pi / 2, 0), verts=10)
    bar.rotation_euler = (0, math.pi / 2, 0)
    for s in (1, -1):
        g = cyl((0, 0, 0), 0.02, 0.1, M["dark"], rot=(0, math.pi / 2, 0), verts=10)
        g.rotation_euler = (0, math.pi / 2, 0)
        g.location = (s * 0.3, 0, 0)
        g.parent = piv
        g.matrix_parent_inverse = Matrix.Identity(4)
    bar.location = (0, 0, 0)
    bar.parent = piv
    bar.matrix_parent_inverse = Matrix.Identity(4)
    empty("Eye", (0.42, 0, 1.38))
    empty("Cluster", (0.92, 0, 1.2))


# ----------------------------------------------------------------------------- bus
def bus(M):
    fl = 0.9
    box((0, 0, fl), (10.2, 2.36, 0.04), M["floor_mat"], bev=0)
    box((0, 0, 2.88), (10.2, 2.3, 0.03), M["headliner"], bev=0)
    for k in range(5):
        box((3.5 - k * 2.0, 0, 2.85), (1.0, 0.07, 0.03), M["tube"], bev=0.005)                        # tube lights
    # driver's corner (right front): dash, gauges, big flat wheel, gear stick, partition
    box((4.95, -0.65, 1.55), (0.45, 1.0, 0.5), M["dark"], bev=0.03, soft=True)
    box((4.95, 0.45, 1.45), (0.45, 1.1, 0.3), M["dark"], bev=0.03)
    box((4.7, -0.75, 1.84), (0.04, 0.5, 0.14), M["gauge_panel"], bev=0.005, rot=(0, math.radians(-30), 0))
    box((4.15, -0.3, 1.5), (0.04, 0.04, 1.2), M["chrome"], bev=0)                                     # partition post
    box((4.0, -0.75, 1.3), (0.03, 0.9, 0.7), M["partition"], bev=0.01)
    seat(4.15, -0.75, fl + 0.45, 0.52, M, "driver_seat", back_h=0.7)
    cyl((4.6, -0.42, fl + 0.4), 0.012, 0.75, M["chrome"], rot=(math.radians(-15), 0, 0), verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(4.6, -0.48, fl + 0.78))
    bpy.context.active_object.data.materials.append(M["dark"])
    # passenger rows: 2 + 2 with a central aisle
    x = 3.3
    while x > -4.7:
        for sy in (0.68, -0.68):
            seat(x, sy, fl + 0.4, 0.9, M, "bus_seat", back_h=0.55, lean=-8, headrest=False)
            cyl((x - 0.3, sy - math.copysign(0.45, sy) * -1, fl + 0.95), 0.012, 0.2, M["chrome"], verts=8)
        x -= 0.82
    for sy in (0.3, -0.3):
        cyl((-0.6, sy, 2.65), 0.015, 9.6, M["chrome"], rot=(0, math.pi / 2, 0), verts=8)            # grab rails
    for gx in (2.6, 0.2, -2.2):
        cyl((gx, 0.3, 1.9), 0.018, 2.0, M["chrome"], verts=8)                                        # grab poles
    # windscreen fringe: colourful tassels and a small destination board inside
    for k in range(24):
        y = -1.1 + k * 0.095
        box((5.1, y, 2.68), (0.02, 0.04, 0.12), M[["tassel_r", "tassel_y", "tassel_g", "tassel_b"][k % 4]], bev=0.004)
    steering(Vector((4.6, -0.75, 1.78)), 25, 0.27, M, spokes=4, big=True)
    empty("Eye", (4.28, -0.75, 2.22))
    empty("Cluster", (4.72, -0.75, 1.84))


# ----------------------------------------------------------------------------- lorry
def lorry(M):
    fl = 1.12
    box((3.6, 0, fl), (1.9, 2.4, 0.04), M["floor_mat"], bev=0)
    box((3.6, 0, 3.0), (1.85, 2.35, 0.03), M["headliner"], bev=0)
    box((4.3, 0, 1.75), (0.4, 2.3, 0.5), M["dash_lorry"], bev=0.03, soft=True)
    for k, col in enumerate(["sticker_r", "sticker_y", "sticker_b", "sticker_g"]):
        box((4.09, 0.2 + k * 0.22, 1.86), (0.01, 0.18, 0.12), M[col], bev=0)                         # dashboard stickers
    box((4.1, -0.6, 1.95), (0.04, 0.5, 0.14), M["gauge_panel"], bev=0.005, rot=(0, math.radians(-25), 0))
    box((3.0, 0, fl + 0.45), (0.5, 2.2, 0.14), M["rexine"], bev=0.03, soft=True)                     # long bench
    box((2.72, 0, fl + 0.85), (0.12, 2.2, 0.65), M["rexine"], bev=0.03, soft=True)
    box((2.66, 0, fl + 1.3), (0.02, 2.3, 0.6), M["curtain"], bev=0)                                  # curtain behind
    cyl((3.65, -0.25, fl + 0.45), 0.014, 0.9, M["chrome"], rot=(math.radians(-15), 0, 0), verts=8)
    for k in range(22):
        y = -1.05 + k * 0.1
        box((4.42, y, 2.72), (0.02, 0.05, 0.14), M[["tassel_r", "tassel_y", "tassel_g", "tassel_b"][k % 4]], bev=0.004)
    steering(Vector((3.85, -0.6, 1.78)), 30, 0.25, M, spokes=4, big=True)
    empty("Eye", (3.32, -0.6, 2.42))
    empty("Cluster", (4.1, -0.6, 1.95))


# ----------------------------------------------------------------------------- export
def materials():
    return {
        "dark": mat("Dark", (0.035, 0.035, 0.04), 0.6), "plastic": mat("Plastic", (0.23, 0.22, 0.21), 0.7),
        "plastic2": mat("Plastic2", (0.55, 0.52, 0.47), 0.75), "fabric": mat("Fabric", (0.22, 0.22, 0.24), 0.95),
        "beige": mat("Beige", (0.62, 0.55, 0.45), 0.8), "beige_fab": mat("BeigeFabric", (0.58, 0.52, 0.43), 0.95),
        "cover": mat("SeatCover", (0.9, 0.9, 0.88), 0.9), "carbon": mat("Carbon", (0.05, 0.05, 0.055), 0.35),
        "red_leather": mat("RedLeather", (0.45, 0.04, 0.04), 0.55), "alcantara": mat("Alcantara", (0.06, 0.06, 0.065), 0.95),
        "rim": mat("Rim", (0.05, 0.045, 0.04), 0.6), "chrome": mat("Chrome", (0.7, 0.7, 0.72), 0.2, 1.0),
        "wood": mat("Wood", (0.2, 0.09, 0.04), 0.35), "carpet": mat("Carpet", (0.06, 0.06, 0.06), 1.0),
        "headliner": mat("Headliner", (0.55, 0.53, 0.5), 0.95), "screen": mat("Screen", (0.02, 0.03, 0.05), 0.1, 0, (0.1, 0.25, 0.45), 1.5),
        "screen_off": mat("Radio", (0.03, 0.03, 0.035), 0.3, 0, (0.2, 0.6, 0.3), 0.8),
        "meter": mat("Meter", (0.05, 0.02, 0.02), 0.3, 0, (1.0, 0.2, 0.1), 2.0),
        "rexine": mat("Rexine", (0.08, 0.07, 0.07), 0.45), "floor_mat": mat("FloorMat", (0.12, 0.12, 0.12), 0.95),
        "canvas_in": mat("CanvasLining", (0.06, 0.06, 0.06), 0.95),
        "tassel_r": mat("TasselRed", (0.75, 0.05, 0.08), 0.8), "tassel_y": mat("TasselYellow", (0.9, 0.7, 0.05), 0.8),
        "tassel_g": mat("TasselGreen", (0.05, 0.5, 0.2), 0.8), "tassel_b": mat("TasselBlue", (0.08, 0.2, 0.7), 0.8),
        "tube": mat("TubeLight", (0.9, 0.95, 1.0), 0.3, 0, (0.9, 0.95, 1.0), 1.5),
        "gauge_panel": mat("Gauges", (0.03, 0.03, 0.04), 0.4, 0, (0.4, 0.5, 0.6), 0.4),
        "partition": mat("Partition", (0.6, 0.62, 0.65), 0.4, 0.6), "driver_seat": mat("DriverSeat", (0.15, 0.12, 0.1), 0.6),
        "bus_seat": mat("BusSeat", (0.1, 0.2, 0.55), 0.5), "dash_lorry": mat("LorryDash", (0.3, 0.06, 0.06), 0.6),
        "sticker_r": mat("StickerR", (0.8, 0.1, 0.1), 0.5), "sticker_y": mat("StickerY", (0.95, 0.75, 0.1), 0.5),
        "sticker_b": mat("StickerB", (0.1, 0.3, 0.8), 0.5), "sticker_g": mat("StickerG", (0.1, 0.6, 0.25), 0.5),
        "curtain": mat("Curtain", (0.5, 0.1, 0.25), 0.9),
    }


BUILD = {"hatchback": lambda M: car("hatchback", M), "sedan": lambda M: car("sedan", M), "taxi": lambda M: car("taxi", M),
         "coupe": lambda M: car("coupe", M), "auto": auto, "bus": bus, "lorry": lorry}


def finish(out):
    # apply modifiers, then merge every loose mesh (not under the steering pivot) into "Cabin"
    for o in list(bpy.data.objects):
        if o.type == 'MESH':
            bpy.context.view_layer.objects.active = o
            for m in list(o.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except RuntimeError:
                    o.modifiers.remove(m)
    loose = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is None]
    bpy.ops.object.select_all(action='DESELECT')
    for o in loose:
        o.select_set(True)
    bpy.context.view_layer.objects.active = loose[0]
    bpy.ops.object.join()
    bpy.context.view_layer.objects.active.name = "Cabin"
    piv = bpy.data.objects.get("SteeringPivot")
    if piv:
        kids = [c for c in piv.children if c.type == 'MESH']
        if len(kids) > 1:
            bpy.ops.object.select_all(action='DESELECT')
            for k in kids:
                k.select_set(True)
            bpy.context.view_layer.objects.active = kids[0]
            bpy.ops.object.join()
            bpy.context.view_layer.objects.active.name = "SteeringWheel"
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    print("INTERIOR", os.path.basename(out), "tris", tris)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/vehicles")
    kinds = args[1:] or list(BUILD.keys())
    for kind in kinds:
        reset()
        M = materials()
        BUILD[kind](M)
        finish(os.path.join(out_dir, "interior_%s.glb" % kind))
