"""
Walk-in interiors for the places in town, designed in Blender (no downloaded assets).

    Blender -b --factory-startup --python tools/building_interiors.py -- godot/assets/interiors [names...]

Rooms (room_<name>.glb):
    kirana      provision store: counter with scale and glass jars, wall shelves of packets and tins,
                rice and dal sacks, a cooler, a ceiling fan
    restaurant  "meals" hotel: steel-topped tables and chairs, cash counter, kitchen pass with a
                tiffin rail, menu board, wash basin, fans, tube lights
    tea         tea shop: counter with a big steel kettle and boiler, glass jars of biscuits, benches
    hotel       lodge lobby: reception desk, key board, sofa set, potted plants, staircase
    temple      mandapam hall: stone floor, carved pillars, a shrine with brass oil lamps and bells,
                floor mats (generic, no specific deity)
    hospital    clinic: reception, rows of waiting chairs, a consulting cubicle with a bed and curtain,
                medicine cabinet, ceiling lights
    bank        branch: counters behind glass, token display, waiting chairs, a cash machine
    fuel        fuel station kiosk: counter, shelves of oil cans, a fridge, payment desk
    office      school / police / town-hall office: desks with files, steel almirahs, chairs, notice board
    home        the story: Karthik's rented house in Ganapathy (front room with Amma's sewing machine, the family
                photos, a lamp in the wall shrine, the kitchen corner; his own small room with a cot, the phone
                charger, shirts and a cap on hooks)
    dev_office  the story: Raghavan Developers, Gandhipuram (reception, Karthik's and Suresh's desks,
                Raghavan's cabin behind a glass partition: big desk, the Mist Village photo, the Green Valley
                file, a layout plan on the wall)
Story rooms also carry "Mark_<who>" empties (where a person stands or sits, facing along the empty's yaw) and
"Cam_<shot>" / "Look_<shot>" pairs (a planned camera and the point it looks at) for the cutscenes.

Each room is about 10 × 8 m with a doorway in the front wall; empties: "Entry" (where you appear,
facing in), "Exit" (stand here and press E to leave), "Staff" (where a worker stands).
Blender −Y is the front (the door), so in Godot the door faces +Z.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

W, D, H = 10.0, 8.0, 3.3          # room width (X), depth (Y), height


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for c in (bpy.data.meshes, bpy.data.materials):
        for b in list(c):
            if b.users == 0:
                c.remove(b)


def mat(name, color, rough=0.7, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        for n in ("Emission Color", "Emission"):
            if n in b.inputs:
                b.inputs[n].default_value = (*emit, 1)
                break
        b.inputs["Emission Strength"].default_value = strength
    return m


def box(loc, dims, m, bev=0.005, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = dims
    o.data.materials.append(m)
    if bev:
        mod = o.modifiers.new("B", 'BEVEL')
        mod.width = bev
    return o


def cyl(loc, r, h, m, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(m)
    return o


def empty(name, loc, yaw=0.0):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.rotation_euler = (0, 0, yaw)
    bpy.context.scene.collection.objects.link(e)


# ----------------------------------------------------------------------------- shell
def shell(M, floor, wall, door_w=1.6, ceiling="ceiling", skirting=True):
    box((0, 0, -0.05), (W, D, 0.1), M[floor], bev=0)
    box((0, 0, H + 0.05), (W, D, 0.1), M[ceiling], bev=0)
    box((0, D / 2 + 0.05, H / 2), (W, 0.1, H), M[wall], bev=0)                   # back
    for s in (1, -1):
        box((s * (W / 2 + 0.05), 0, H / 2), (0.1, D, H), M[wall], bev=0)          # sides
    side = (W - door_w) / 2                                                       # front with a doorway
    for s in (1, -1):
        box((s * (door_w / 2 + side / 2), -D / 2 - 0.05, H / 2), (side, 0.1, H), M[wall], bev=0)
    box((0, -D / 2 - 0.05, H - 0.4), (door_w, 0.1, 0.8), M[wall], bev=0)
    box((0, -D / 2 - 0.02, H - 0.82), (door_w + 0.12, 0.14, 0.06), M["wood"], bev=0.004)   # door frame
    for s in (1, -1):
        box((s * (door_w / 2 + 0.03), -D / 2 - 0.02, (H - 0.8) / 2), (0.06, 0.14, H - 0.8), M["wood"], bev=0.004)
    if skirting:
        box((0, D / 2 - 0.01, 0.06), (W, 0.03, 0.12), M["skirt"], bev=0)
        for s in (1, -1):
            box((s * (W / 2 - 0.01), 0, 0.06), (0.03, D, 0.12), M["skirt"], bev=0)
    # bright outside light through the doorway (so it reads as a door, not a black hole)
    box((0, -D / 2 - 0.3, (H - 0.8) / 2), (door_w, 0.02, H - 0.8), M["daylight"], bev=0)
    empty("Entry", (0, -D / 2 + 1.0, 0), 0.0)
    empty("Exit", (0, -D / 2 + 0.4, 0), math.pi)


def tube_lights(M, rows=((-2, 0), (2, 0)), length=1.2):
    for x, y in rows:
        box((x, y, H - 0.05), (length, 0.08, 0.05), M["tube"], bev=0)


def fan(M, x, y):
    cyl((x, y, H - 0.25), 0.015, 0.4, M["steel"], 8)
    cyl((x, y, H - 0.48), 0.09, 0.08, M["white"], 16)
    for k in range(3):
        a = k * 2 * math.pi / 3
        box((x + math.cos(a) * 0.4, y + math.sin(a) * 0.4, H - 0.48), (0.7, 0.11, 0.01), M["white"], bev=0, rot=(0, 0, a))


def chair(M, x, y, yaw, m="steel_chair"):
    box((x, y, 0.45), (0.42, 0.42, 0.04), M[m], bev=0.01)
    for sx in (-0.18, 0.18):
        for sy in (-0.18, 0.18):
            cyl((x + sx, y + sy, 0.22), 0.012, 0.45, M["steel"], 6)
    bx, by = x - math.sin(yaw) * 0.2, y + math.cos(yaw) * 0.2
    box((bx, by, 0.72), (0.42 if abs(math.cos(yaw)) > 0.5 else 0.04, 0.04 if abs(math.cos(yaw)) > 0.5 else 0.42, 0.5), M[m], bev=0.01)


def table(M, x, y, w=1.2, d=0.75, top="steel_top"):
    box((x, y, 0.76), (w, d, 0.04), M[top], bev=0.005)
    for sx in (-w / 2 + 0.06, w / 2 - 0.06):
        for sy in (-d / 2 + 0.06, d / 2 - 0.06):
            box((x + sx, y + sy, 0.38), (0.04, 0.04, 0.76), M["steel"], bev=0)


def shelves(M, x0, x1, y, depth=0.4, levels=5, items=True, face=1):
    """A wall of shelves along X at depth y, stocked with packets and tins in many colours."""
    w = x1 - x0
    box(((x0 + x1) / 2, y, 1.1), (w, depth, 0.04), M["wood"], bev=0)
    for k in range(levels):
        z = 0.15 + k * 0.42
        box(((x0 + x1) / 2, y, z), (w, depth, 0.03), M["wood"], bev=0)
        if items:
            x = x0 + 0.08
            k2 = 0
            while x < x1 - 0.1:
                col = ["pk_r", "pk_y", "pk_g", "pk_b", "pk_o", "pk_w"][(k2 * 7 + k * 3) % 6]
                hgt = 0.14 + 0.12 * ((k2 * 5 + k) % 3) / 2
                if (k2 + k) % 4 == 0:
                    cyl((x + 0.05, y - face * 0.05, z + hgt / 2 + 0.02), 0.045, hgt, M["tin"], 10)
                else:
                    box((x + 0.06, y - face * 0.05, z + hgt / 2 + 0.02), (0.11, 0.18, hgt), M[col], bev=0)
                x += 0.14
                k2 += 1
    for xx in (x0, x1):
        box((xx, y, 1.05), (0.04, depth, 2.1), M["wood"], bev=0)


# ----------------------------------------------------------------------------- rooms
def kirana(M):
    shell(M, "tile_red", "wall_yellow")
    shelves(M, -4.6, 4.6, D / 2 - 0.25)
    shelves(M, -4.6, -1.2, 0.8, levels=4, face=-1)
    box((1.6, -0.6, 0.5), (3.0, 0.7, 1.0), M["wood"], bev=0.01)                  # counter
    box((1.6, -0.6, 1.02), (3.1, 0.75, 0.04), M["glass_top"], bev=0)
    for k in range(6):                                                          # glass jars on the counter
        cyl((0.4 + k * 0.45, -0.6, 1.17), 0.1, 0.26, M["jar"], 12)
        cyl((0.4 + k * 0.45, -0.6, 1.32), 0.08, 0.04, M[["pk_r", "pk_y", "pk_g"][k % 3]], 12)
    box((2.8, -0.6, 1.1), (0.3, 0.25, 0.1), M["steel"], bev=0.01)                # scale
    for k in range(5):                                                          # sacks of rice and dal
        cyl((-3.8 + k * 0.6, -2.4, 0.35), 0.24, 0.7, M["sack"], 12)
    box((4.2, -2.8, 0.9), (0.8, 0.7, 1.8), M["cooler"], bev=0.02)                # drinks cooler
    box((4.2, -3.16, 1.1), (0.7, 0.02, 1.2), M["glass"], bev=0)
    fan(M, 0, 0)
    tube_lights(M)
    empty("Staff", (1.6, 0.4, 0), math.pi)


def restaurant(M):
    shell(M, "tile_white", "wall_green")
    for ix in range(3):
        for iy in range(2):
            x, y = -3.2 + ix * 2.6, -1.8 + iy * 2.4
            table(M, x, y)
            for side in (-1, 1):
                chair(M, x - 0.35, y + side * 0.6, 0 if side > 0 else math.pi)
                chair(M, x + 0.35, y + side * 0.6, 0 if side > 0 else math.pi)
    box((3.0, D / 2 - 0.7, 0.55), (3.2, 0.7, 1.1), M["steel"], bev=0.01)         # kitchen pass
    box((3.0, D / 2 - 0.1, 1.9), (3.2, 0.1, 1.2), M["kitchen"], bev=0)           # kitchen hatch
    for k in range(5):
        cyl((1.8 + k * 0.6, D / 2 - 0.7, 1.22), 0.11, 0.22, M["steel"], 12)      # tiffin carriers / vessels
    box((-3.5, D / 2 - 0.4, 0.55), (1.8, 0.6, 1.1), M["wood"], bev=0.01)         # cash counter
    box((-3.5, D / 2 - 0.06, 2.2), (2.2, 0.04, 0.9), M["menu"], bev=0)           # menu board
    box((W / 2 - 0.3, -2.5, 0.85), (0.5, 0.4, 0.15), M["white"], bev=0.02)       # wash basin
    cyl((W / 2 - 0.3, -2.5, 0.45), 0.05, 0.8, M["white"], 10)
    fan(M, -2, 0)
    fan(M, 2, 0)
    tube_lights(M, ((-3, -2), (3, -2), (-3, 2), (3, 2)))
    empty("Staff", (-3.5, D / 2 - 1.0, 0), math.pi)


def tea(M):
    shell(M, "cement", "wall_blue")
    box((0, D / 2 - 1.2, 0.5), (5.0, 0.8, 1.0), M["wood"], bev=0.01)
    box((0, D / 2 - 1.2, 1.02), (5.1, 0.85, 0.04), M["steel"], bev=0)
    cyl((-1.5, D / 2 - 1.2, 1.4), 0.25, 0.7, M["brass"], 20)                      # boiler
    cyl((-0.7, D / 2 - 1.2, 1.15), 0.15, 0.22, M["steel"], 16)                   # kettle
    for k in range(8):
        cyl((0.2 + k * 0.32, D / 2 - 1.2, 1.2), 0.1, 0.32, M["jar"], 12)
        cyl((0.2 + k * 0.32, D / 2 - 1.2, 1.12), 0.09, 0.12, M[["pk_y", "pk_o", "pk_r"][k % 3]], 12)
    for y in (-2.0, 0.2):
        box((-2.0, y, 0.4), (3.0, 0.4, 0.06), M["wood"], bev=0.005)              # benches
        box((2.2, y, 0.4), (3.0, 0.4, 0.06), M["wood"], bev=0.005)
        for x in (-3.3, -0.7, 0.9, 3.5):
            box((x, y, 0.2), (0.06, 0.35, 0.4), M["wood"], bev=0)
    shelves(M, -4.6, -2.8, D / 2 - 0.25, levels=3)
    fan(M, 0, -1)
    tube_lights(M, ((0, 0),))
    empty("Staff", (0, D / 2 - 0.5, 0), math.pi)


def hotel(M):
    shell(M, "marble", "wall_cream")
    box((-2.5, D / 2 - 1.5, 0.55), (3.5, 0.8, 1.1), M["wood_dark"], bev=0.02)     # reception desk
    box((-2.5, D / 2 - 1.5, 1.12), (3.6, 0.85, 0.04), M["marble_dark"], bev=0)
    box((-2.5, D / 2 - 0.06, 1.7), (1.4, 0.04, 0.9), M["wood_dark"], bev=0)      # key board
    for i in range(4):
        for j in range(3):
            cyl((-3.0 + i * 0.32, D / 2 - 0.1, 1.45 + j * 0.25), 0.015, 0.06, M["brass"], 6, rot=(math.pi / 2, 0, 0))
    for k, (x, y, w) in enumerate(((2.0, -1.0, 2.2), (3.8, 0.4, 0.9), (0.6, 0.4, 0.9))):
        box((x, y, 0.25), (w, 0.85, 0.5), M["sofa"], bev=0.05)
        if k == 0:
            box((x, y - 0.38, 0.65), (w, 0.15, 0.4), M["sofa"], bev=0.05)          # back away from the table
        else:
            box((x + (0.38 if x > 2.0 else -0.38), y, 0.65), (0.15, 0.85, 0.4), M["sofa"], bev=0.05)
    box((2.0, 0.4, 0.22), (1.2, 0.6, 0.44), M["glass_top"], bev=0.01)             # coffee table
    for x in (-4.5, 4.5):
        cyl((x, -3.4, 0.25), 0.25, 0.5, M["pot"], 14)
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.5, location=(x, -3.4, 1.0))
        bpy.context.active_object.data.materials.append(M["plant"])
    for k in range(10):                                                           # staircase going up
        box((4.2, 1.0 + k * 0.28, 0.09 + k * 0.17), (1.2, 0.3, 0.17), M["marble_dark"], bev=0)
    tube_lights(M, ((-2, 0), (2, 0)))
    empty("Staff", (-2.5, D / 2 - 0.8, 0), math.pi)


def temple(M):
    shell(M, "stone", "wall_stone", door_w=2.2, ceiling="stone")
    for x in (-3.0, 3.0):
        for y in (-2.0, 0.6):
            box((x, y, H / 2), (0.45, 0.45, H), M["stone_dark"], bev=0.02)        # pillars
            for z in (0.4, H - 0.4):
                box((x, y, z), (0.6, 0.6, 0.2), M["stone_dark"], bev=0.02)
    box((0, D / 2 - 1.0, 0.4), (3.0, 1.6, 0.8), M["stone_dark"], bev=0.02)        # shrine platform
    box((0, D / 2 - 0.6, 1.9), (2.2, 0.8, 2.2), M["stone_dark"], bev=0.03)        # sanctum
    box((0, D / 2 - 1.01, 1.7), (1.0, 0.02, 1.5), M["sanctum"], bev=0)            # lit doorway
    for x in (-1.2, 1.2):
        cyl((x, D / 2 - 1.7, 0.95), 0.06, 0.3, M["brass"], 12)                   # oil lamps
        cyl((x, D / 2 - 1.7, 1.12), 0.012, 0.04, M["flame"], 6)
        cyl((x * 0.6, D / 2 - 1.8, H - 0.6), 0.08, 0.15, M["brass"], 12)         # bells
        cyl((x * 0.6, D / 2 - 1.8, H - 0.3), 0.005, 0.45, M["brass"], 4)
    for k in range(4):
        box((0, -1.8 + k * 0.9, 0.01), (2.2, 0.7, 0.01), M[["mat_r", "mat_g"][k % 2]], bev=0)
    empty("Staff", (1.6, D / 2 - 2.0, 0), math.pi)


def hospital(M):
    shell(M, "tile_white", "wall_white")
    box((-3.0, D / 2 - 1.2, 0.55), (2.6, 0.7, 1.1), M["white"], bev=0.02)
    box((-3.0, D / 2 - 0.06, 2.1), (2.0, 0.04, 0.5), M["sign_green"], bev=0)
    for row in range(3):
        for k in range(5):
            chair(M, -3.5 + k * 0.55, -2.8 + row * 1.1, 0, "plastic_blue")
    box((2.5, 0.0, 1.3), (0.05, 4.0, 2.6), M["partition"], bev=0)                 # cubicle wall
    box((3.8, 1.5, 0.35), (1.9, 0.9, 0.12), M["steel"], bev=0.01)                 # bed
    box((3.8, 1.5, 0.48), (1.9, 0.85, 0.14), M["white"], bev=0.03)
    box((3.25, 0.8, 1.2), (0.02, 1.5, 2.0), M["curtain"], bev=0)
    box((4.6, D / 2 - 0.3, 1.0), (0.8, 0.4, 2.0), M["white"], bev=0.01)           # medicine cabinet
    box((4.6, D / 2 - 0.51, 1.3), (0.7, 0.02, 1.2), M["glass"], bev=0)
    table(M, 3.8, -2.0, 1.2, 0.7, "white")
    chair(M, 3.8, -2.7, 0, "plastic_blue")
    tube_lights(M, ((-2, -1), (-2, 2), (3.8, 0)))
    empty("Staff", (-3.0, D / 2 - 0.6, 0), math.pi)


def bank(M):
    shell(M, "marble", "wall_cream")
    box((0, D / 2 - 2.0, 0.55), (8.0, 0.6, 1.1), M["wood_dark"], bev=0.01)         # counters
    box((0, D / 2 - 2.0, 1.75), (8.0, 0.02, 1.3), M["glass"], bev=0)               # glass partition
    for k in range(4):
        box((-3.0 + k * 2.0, D / 2 - 2.0, 1.1), (0.04, 0.6, 1.3), M["steel"], bev=0)
        box((-3.0 + k * 2.0 + 1.0, D / 2 - 1.7, 1.13), (0.4, 0.3, 0.03), M["paper"], bev=0)
    box((0, D / 2 - 2.0, 2.6), (1.4, 0.06, 0.35), M["token"], bev=0)               # token display
    for k in range(6):
        chair(M, -3.0 + k * 0.6, -2.5, 0, "plastic_blue")
    box((4.4, -2.8, 0.9), (0.7, 0.6, 1.8), M["atm"], bev=0.02)                     # cash machine
    box((4.4, -3.11, 1.25), (0.4, 0.02, 0.3), M["screen"], bev=0)
    tube_lights(M, ((-2, -1), (2, -1), (0, 2)))
    empty("Staff", (-1.0, D / 2 - 1.3, 0), math.pi)
    mark("clerk", -1.0, D / 2 - 1.3, math.pi)
    mark("karthik", -1.0, D / 2 - 2.75, 0.0)
    shot("counter", (0.2, D / 2 - 3.6, 1.6), (-1.0, D / 2 - 1.3, 1.45))
    shot("karthik", (-1.6, D / 2 - 1.75, 1.55), (-1.0, D / 2 - 2.75, 1.45))


def fuel(M):
    shell(M, "tile_white", "wall_white")
    box((-1.5, 0.5, 0.5), (3.0, 0.7, 1.0), M["white"], bev=0.02)
    box((-1.5, 0.5, 1.02), (3.1, 0.75, 0.04), M["green"], bev=0)
    box((-0.6, 0.5, 1.15), (0.35, 0.3, 0.2), M["screen"], bev=0.01)               # billing machine
    shelves(M, -4.6, 4.6, D / 2 - 0.25, levels=4)
    shelves(M, 1.5, 4.6, 0.0, levels=3, face=-1)
    box((4.3, -2.6, 0.9), (0.8, 0.7, 1.8), M["cooler"], bev=0.02)
    tube_lights(M)
    empty("Staff", (-1.5, 1.2, 0), math.pi)


def office(M):
    shell(M, "tile_grey", "wall_cream")
    for k in range(3):
        x = -3.0 + k * 3.0
        table(M, x, 0.8, 1.4, 0.8, "wood")
        chair(M, x, 1.4, math.pi, "wood")
        chair(M, x, 0.0, 0, "plastic_blue")
        for j in range(4):
            box((x - 0.4 + j * 0.06, 0.9, 0.88), (0.05, 0.3, 0.2), M[["file_r", "file_b"][j % 2]], bev=0)
    for x in (-4.4, -3.4, 4.4):
        box((x, D / 2 - 0.35, 1.0), (0.9, 0.5, 2.0), M["almirah"], bev=0.01)      # steel almirahs
    box((1.5, D / 2 - 0.06, 1.6), (2.0, 0.04, 1.0), M["cork"], bev=0)             # notice board
    for k in range(5):
        box((0.8 + k * 0.35, D / 2 - 0.09, 1.6 + (k % 2) * 0.2), (0.25, 0.01, 0.32), M["paper"], bev=0)
    fan(M, -1.5, 0)
    fan(M, 1.5, 0)
    tube_lights(M)
    empty("Staff", (0.0, 1.4, 0), math.pi)


def mark(name, x, y, yaw):
    """Where a person stands (yaw: the way they face, 0 = towards +Y, the back wall)."""
    empty("Mark_" + name, (x, y, 0), yaw)


def shot(name, cam, look):
    empty("Cam_" + name, cam)
    empty("Look_" + name, look)


def frame(M, x, y, z, w, h, picture, face=-1):
    """A framed photo on the back wall (face=-1: facing the room from the back wall)."""
    box((x, y, z), (w + 0.06, 0.03, h + 0.06), M["wood_dark"], bev=0.004)
    box((x, y + face * 0.017, z), (w, 0.005, h), M[picture], bev=0)


def home(M):
    shell(M, "tile_red", "wall_blue", door_w=1.0)
    # a partition: the front room (left) and Karthik's room (right), a doorway in it
    box((2.3, -1.4, H / 2), (0.12, 1.6, H), M["wall_blue"], bev=0)
    box((2.3, 2.9, H / 2), (0.12, 2.2, H), M["wall_blue"], bev=0)
    box((2.3, 0.9, H - 0.4), (0.12, 2.4, 0.8), M["wall_blue"], bev=0)
    # Amma's sewing machine table, cloth on it
    box((-3.9, 2.9, 0.38), (1.1, 0.55, 0.76), M["wood"], bev=0.01)
    box((-3.9, 2.9, 0.86), (0.45, 0.2, 0.2), M["machine"], bev=0.02)
    box((-3.7, 2.9, 1.0), (0.12, 0.18, 0.12), M["machine"], bev=0.02)
    box((-4.2, 2.8, 0.78), (0.5, 0.45, 0.03), M["cloth_pink"], bev=0)
    chair(M, -3.9, 2.25, 0, "plastic_blue")
    # plastic chairs, a TV on its stand, a calendar
    for x, yaw in ((-1.9, math.pi), (-0.9, math.pi), (-1.4, 0.0)):
        chair(M, x, 0.2 if yaw else -0.7, yaw, "plastic_red")
    box((0.4, 3.6, 0.35), (1.0, 0.45, 0.7), M["wood_dark"], bev=0.01)
    box((0.4, 3.62, 0.98), (0.75, 0.06, 0.48), M["screen_off"], bev=0.01)
    box((1.6, D / 2 - 0.03, 1.6), (0.35, 0.01, 0.5), M["paper"], bev=0)
    # the family photos: father (garlanded), the family, Karthik's college photo (no cap, as ever)
    frame(M, -2.6, D / 2 - 0.03, 1.9, 0.4, 0.5, "photo_old")
    box((-2.6, D / 2 - 0.06, 1.62), (0.42, 0.04, 0.05), M["garland"], bev=0.01)
    frame(M, -1.8, D / 2 - 0.03, 1.85, 0.6, 0.45, "photo_family")
    frame(M, -1.05, D / 2 - 0.03, 1.85, 0.35, 0.45, "photo_young")
    # the shrine in the side wall: a niche with a brass lamp
    box((-W / 2 + 0.05, 0.6, 1.45), (0.1, 0.7, 0.6), M["wood_dark"], bev=0.005)
    cyl((-W / 2 + 0.2, 0.6, 1.25), 0.06, 0.12, M["brass"], 16)
    cyl((-W / 2 + 0.2, 0.6, 1.36), 0.012, 0.03, M["flame"], 8)
    # the kitchen corner: a platform with the gas stove, vessels on a rack
    box((-3.9, -2.4, 0.42), (1.8, 0.6, 0.84), M["cement"], bev=0.01)
    box((-4.2, -2.4, 0.9), (0.6, 0.4, 0.08), M["steel"], bev=0.01)
    for k in range(4):
        cyl((-3.6 + k * 0.22, -2.55, 0.97), 0.09, 0.18, M["steel"], 16)
    box((-3.9, -2.68, 1.6), (1.6, 0.25, 0.04), M["wood"], bev=0)
    for k in range(5):
        cyl((-4.5 + k * 0.3, -2.68, 1.75), 0.1, 0.25, M["steel"], 16)
    # the floor mat where they eat
    box((-1.4, -1.9, 0.005), (1.6, 0.9, 0.01), M["mat_r"], bev=0)
    # Karthik's room: a cot, a small table with the phone charger, shirts and a cap on hooks, a window
    box((3.8, 2.6, 0.25), (1.9, 0.95, 0.5), M["wood"], bev=0.01)
    box((3.8, 2.6, 0.55), (1.85, 0.9, 0.12), M["cloth_check"], bev=0.02)
    box((4.5, 2.6, 0.66), (0.45, 0.6, 0.1), M["white"], bev=0.03)
    table(M, 3.5, 0.3, 0.7, 0.45, "wood")
    box((3.5, 0.3, 0.8), (0.07, 0.14, 0.012), M["phone"], bev=0.004)
    box((3.75, 0.45, 0.79), (0.04, 0.03, 0.03), M["white"], bev=0)
    for k, m in enumerate(("cloth_blue", "white", "cloth_check")):
        box((W / 2 - 0.08, -1.6 + k * 0.5, 1.4), (0.04, 0.42, 0.6), M[m], bev=0.01)
    cyl((W / 2 - 0.1, 0.0, 1.85), 0.12, 0.08, M["cap"], 16, rot=(0, math.pi / 2, 0))     # the cap he never wears
    box((W / 2 - 0.02, 2.6, 1.7), (0.03, 1.0, 0.8), M["window"], bev=0)
    fan(M, -1.4, 0.8)
    tube_lights(M, ((-1.5, 1.5), (3.6, 1.0)), 0.9)
    # where everyone stands, and the planned shots
    mark("amma", -1.9, 1.0, math.pi)
    mark("divya", -0.6, -0.4, -math.pi / 2)
    mark("karthik", -1.4, -1.0, 0.0)
    mark("karthik_room", 3.3, 0.9, math.pi)
    mark("door", 0.0, -3.4, math.pi)
    shot("wide", (1.6, -3.2, 2.1), (-1.6, 0.8, 1.0))
    shot("amma", (-1.1, -0.7, 1.55), (-1.9, 1.0, 1.5))
    shot("divya", (-1.6, -1.6, 1.5), (-0.6, -0.4, 1.45))
    shot("karthik", (-1.1, 0.9, 1.55), (-1.4, -1.0, 1.5))
    shot("room", (1.7, 3.2, 2.0), (3.6, 0.6, 0.9))
    shot("photos", (-1.8, 1.6, 1.7), (-1.8, D / 2, 1.85))


def dev_office(M):
    shell(M, "tile_grey", "wall_cream")
    # reception by the door
    box((-2.6, -2.3, 0.55), (1.8, 0.6, 1.1), M["wood_dark"], bev=0.01)
    box((-2.6, -2.3, 1.12), (1.9, 0.65, 0.04), M["marble"], bev=0)
    chair(M, -2.6, -1.7, math.pi, "black_chair")
    # Karthik's desk (the phone charger on it) and Suresh's, on the right
    table(M, 3.2, -1.6, 1.2, 0.7, "wood")
    chair(M, 3.2, -1.0, math.pi, "plastic_blue")
    box((3.55, -1.75, 0.79), (0.04, 0.03, 0.03), M["white"], bev=0)
    box((2.85, -1.7, 0.84), (0.35, 0.25, 0.1), M["file_b"], bev=0)
    table(M, 3.2, 1.3, 1.4, 0.8, "wood_dark")
    chair(M, 3.2, 2.0, math.pi, "black_chair")
    box((3.0, 1.3, 0.8), (0.4, 0.28, 0.02), M["laptop"], bev=0.004)
    box((3.0, 1.43, 0.92), (0.4, 0.02, 0.26), M["screen"], bev=0)
    # Raghavan's cabin behind a glass partition, back left
    box((-3.3, 0.5, 1.2), (3.4, 0.03, 2.4), M["glass"], bev=0)
    box((-0.6, 0.5, 1.2), (0.06, 0.06, 2.4), M["steel"], bev=0)
    box((-2.8, 2.7, 0.4), (2.0, 0.95, 0.8), M["wood_dark"], bev=0.01)        # the big desk
    box((-2.8, 2.7, 0.81), (2.05, 1.0, 0.03), M["glass_top"], bev=0)
    chair(M, -2.8, 3.4, math.pi, "black_chair")
    chair(M, -3.3, 1.8, 0.0, "black_chair")
    chair(M, -2.3, 1.8, 0.0, "black_chair")
    box((-3.4, 2.5, 0.92), (0.22, 0.03, 0.17), M["wood"], bev=0.004)        # the Mist Village photo on the desk
    box((-3.4, 2.485, 0.92), (0.19, 0.005, 0.14), M["photo_hills"], bev=0)
    for k in range(3):                                                    # files, the green one is Green Valley
        box((-2.2, 2.75, 0.85 + k * 0.04), (0.35, 0.26, 0.035), M[("file_green", "file_r", "file_b")[k]], bev=0)
    frame(M, -2.8, D / 2 - 0.03, 1.85, 1.6, 0.9, "layout_plan")              # the layout plan on the wall
    box((-4.5, 3.6, 1.0), (0.9, 0.5, 2.0), M["almirah"], bev=0.01)
    cyl((-0.9, 3.5, 0.3), 0.22, 0.6, M["pot"], 16)
    cyl((-0.9, 3.5, 0.9), 0.35, 0.7, M["plant"], 10)
    box((4.5, 3.6, 0.6), (0.35, 0.35, 1.2), M["white"], bev=0.02)           # water dispenser
    box((1.2, D / 2 - 0.06, 1.6), (1.4, 0.04, 0.9), M["cork"], bev=0)
    fan(M, -2.8, 2.0)
    fan(M, 2.5, -0.5)
    tube_lights(M, ((-2.8, 2.0), (2.5, 0.0), (-2.5, -2.0)))
    mark("raghavan_desk", -2.8, 3.35, math.pi)
    mark("visitor_l", -3.3, 1.2, 0.0)                                        # standing in front of the chairs
    mark("visitor_r", -2.3, 1.2, 0.0)
    mark("suresh", -1.3, 2.3, math.pi / 2)
    mark("karthik_desk", 3.2, -0.95, math.pi)
    mark("suresh_desk", 3.2, 2.05, math.pi)
    mark("reception", -2.6, -1.65, math.pi)
    mark("door", 0.0, -3.4, 0.0)
    shot("cabin", (0.4, -0.6, 2.0), (-2.8, 2.6, 1.1))
    shot("raghavan", (-2.5, 1.0, 1.35), (-2.8, 3.35, 1.25))
    shot("karthik", (-2.6, 3.6, 1.45), (-3.3, 1.75, 1.15))
    shot("suresh", (-2.4, 1.2, 1.5), (-1.3, 2.3, 1.5))
    shot("desk", (1.9, -2.9, 1.6), (3.2, -1.3, 0.9))
    shot("hall", (-4.2, -3.3, 2.2), (2.5, 1.0, 1.0))


def materials():
    return {k: mat(*v) if isinstance(v, tuple) else v for k, v in {
        "tile_red": ("TileRed", (0.45, 0.16, 0.12), 0.5), "tile_white": ("TileWhite", (0.85, 0.85, 0.83), 0.35),
        "tile_grey": ("TileGrey", (0.5, 0.5, 0.5), 0.5), "cement": ("Cement", (0.45, 0.44, 0.42), 0.9),
        "marble": ("Marble", (0.85, 0.83, 0.78), 0.2), "marble_dark": ("MarbleDark", (0.2, 0.18, 0.17), 0.25),
        "stone": ("Stone", (0.42, 0.4, 0.37), 0.9), "stone_dark": ("StoneDark", (0.32, 0.3, 0.28), 0.85),
        "wall_yellow": ("WallYellow", (0.85, 0.72, 0.4), 0.9), "wall_green": ("WallGreen", (0.55, 0.75, 0.6), 0.9),
        "wall_blue": ("WallBlue", (0.5, 0.65, 0.8), 0.9), "wall_cream": ("WallCream", (0.88, 0.84, 0.74), 0.9),
        "wall_white": ("WallWhite", (0.9, 0.9, 0.9), 0.9), "wall_stone": ("WallStone", (0.5, 0.47, 0.42), 0.9),
        "ceiling": ("Ceiling", (0.92, 0.92, 0.9), 0.95), "skirt": ("Skirting", (0.25, 0.22, 0.2), 0.6),
        "daylight": ("Daylight", (1, 1, 1), 0.5, 0, (1.0, 0.98, 0.92), 2.5),
        "tube": ("TubeLight", (1, 1, 1), 0.3, 0, (0.95, 0.97, 1.0), 4.0),
        "wood": ("Wood", (0.42, 0.26, 0.14), 0.6), "wood_dark": ("WoodDark", (0.2, 0.11, 0.06), 0.45),
        "steel": ("Steel", (0.72, 0.73, 0.75), 0.3, 1.0), "steel_top": ("SteelTop", (0.75, 0.76, 0.78), 0.25, 1.0),
        "steel_chair": ("ChairSteel", (0.6, 0.62, 0.65), 0.35, 0.8), "white": ("White", (0.9, 0.9, 0.9), 0.5),
        "glass": ("Glass", (0.6, 0.7, 0.75), 0.05), "glass_top": ("GlassTop", (0.55, 0.65, 0.68), 0.05),
        "jar": ("Jar", (0.75, 0.82, 0.85), 0.05), "tin": ("Tin", (0.65, 0.66, 0.68), 0.3, 1.0),
        "sack": ("Sack", (0.75, 0.68, 0.5), 0.95), "cooler": ("Cooler", (0.75, 0.1, 0.1), 0.4),
        "pk_r": ("PackRed", (0.8, 0.12, 0.1), 0.6), "pk_y": ("PackYellow", (0.95, 0.75, 0.1), 0.6),
        "pk_g": ("PackGreen", (0.15, 0.55, 0.2), 0.6), "pk_b": ("PackBlue", (0.12, 0.3, 0.75), 0.6),
        "pk_o": ("PackOrange", (0.95, 0.45, 0.08), 0.6), "pk_w": ("PackWhite", (0.92, 0.92, 0.88), 0.6),
        "kitchen": ("Kitchen", (0.15, 0.12, 0.1), 0.8), "menu": ("Menu", (0.08, 0.2, 0.12), 0.7),
        "brass": ("Brass", (0.8, 0.6, 0.25), 0.3, 1.0), "flame": ("Flame", (1, 0.6, 0.2), 0.5, 0, (1.0, 0.55, 0.15), 8.0),
        "sanctum": ("Sanctum", (0.3, 0.15, 0.05), 0.6, 0, (1.0, 0.6, 0.25), 1.5),
        "mat_r": ("MatRed", (0.6, 0.12, 0.1), 0.95), "mat_g": ("MatGreen", (0.15, 0.4, 0.2), 0.95),
        "sofa": ("Sofa", (0.35, 0.12, 0.1), 0.85), "pot": ("Pot", (0.6, 0.3, 0.15), 0.8), "plant": ("Plant", (0.15, 0.4, 0.15), 0.9),
        "sign_green": ("SignGreen", (0.1, 0.55, 0.3), 0.5), "plastic_blue": ("PlasticBlue", (0.15, 0.3, 0.65), 0.5),
        "partition": ("Partition", (0.8, 0.85, 0.82), 0.6), "curtain": ("Curtain", (0.4, 0.65, 0.7), 0.9),
        "paper": ("Paper", (0.95, 0.95, 0.92), 0.9), "token": ("Token", (0.05, 0.05, 0.05), 0.4, 0, (1.0, 0.2, 0.1), 3.0),
        "atm": ("CashMachine", (0.3, 0.32, 0.35), 0.4, 0.6), "screen": ("Screen", (0.05, 0.1, 0.15), 0.2, 0, (0.2, 0.5, 0.8), 2.0),
        "green": ("Green", (0.1, 0.45, 0.25), 0.5), "file_r": ("FileRed", (0.6, 0.15, 0.1), 0.8),
        "file_b": ("FileBuff", (0.8, 0.7, 0.45), 0.8), "almirah": ("Almirah", (0.4, 0.45, 0.42), 0.4, 0.6),
        "cork": ("Cork", (0.6, 0.45, 0.28), 0.9),
        "machine": ("SewingMachine", (0.08, 0.08, 0.08), 0.35, 0.3), "cloth_pink": ("ClothPink", (0.85, 0.4, 0.55), 0.9),
        "cloth_blue": ("ClothBlue", (0.3, 0.5, 0.8), 0.9), "cloth_check": ("ClothCheck", (0.6, 0.25, 0.2), 0.9),
        "plastic_red": ("PlasticRed", (0.7, 0.12, 0.1), 0.5), "black_chair": ("ChairBlack", (0.06, 0.06, 0.07), 0.6),
        "screen_off": ("ScreenOff", (0.03, 0.03, 0.035), 0.15), "photo_old": ("PhotoOld", (0.55, 0.5, 0.42), 0.8),
        "photo_family": ("PhotoFamily", (0.45, 0.4, 0.35), 0.7), "photo_young": ("PhotoYoung", (0.35, 0.4, 0.5), 0.7),
        "garland": ("Garland", (0.95, 0.55, 0.1), 0.9), "phone": ("PhoneBlack", (0.02, 0.02, 0.025), 0.2),
        "cap": ("Cap", (0.08, 0.08, 0.1), 0.8), "window": ("Window", (0.75, 0.85, 0.95), 0.1, 0, (0.9, 0.95, 1.0), 1.2),
        "laptop": ("Laptop", (0.25, 0.25, 0.27), 0.4, 0.6), "photo_hills": ("PhotoHills", (0.3, 0.5, 0.35), 0.6),
        "file_green": ("FileGreen", (0.15, 0.5, 0.25), 0.8), "layout_plan": ("LayoutPlan", (0.88, 0.86, 0.75), 0.9),
    }.items()}


ROOMS = {"kirana": kirana, "restaurant": restaurant, "tea": tea, "hotel": hotel, "temple": temple,
         "hospital": hospital, "bank": bank, "fuel": fuel, "office": office, "home": home, "dev_office": dev_office}


def finish(out):
    for o in list(bpy.data.objects):
        if o.type == 'MESH':
            bpy.context.view_layer.objects.active = o
            for m in list(o.modifiers):
                bpy.ops.object.modifier_apply(modifier=m.name)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    bpy.context.view_layer.objects.active.name = "Room"
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    print("ROOM", os.path.basename(out))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/interiors")
    os.makedirs(out_dir, exist_ok=True)
    for name in (args[1:] or ROOMS.keys()):
        reset()
        M = materials()
        ROOMS[name](M)
        finish(os.path.join(out_dir, "room_%s.glb" % name))
