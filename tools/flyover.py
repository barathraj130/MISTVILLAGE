"""
A city flyover for Coimbatore, in its own design (no names, no logos): hammerhead piers (rounded column, wide
cap with bearings), a girder deck with its underside, New-Jersey crash barriers on both edges and down the
middle, double-arm lamp posts on the median, drain pipes down the piers, and the ramp held by a reinforced
earth wall of square panels. Renders a preview; exports the pier and lamp for the game (the deck, barriers
and ramp walls are swept along each flyover in the game with the same profiles, PROFILES below).

    Blender -b --factory-startup --python tools/flyover.py -- --preview out.png
    Blender -b --factory-startup --python tools/flyover.py -- --export godot/assets/city_props
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402

H = 8.6            # deck surface above the road below (about 7 m clear under the girders)
CW = 8.5           # carriageway width (each direction)
MED = 0.8          # central barrier width
EDGE = 0.55        # edge barrier width
DECK_W = 2 * CW + MED + 2 * EDGE
GIRDER = 1.6       # deck depth
SPAN = 30.0
# New-Jersey barrier, half profile (outward offset from its inner face, height), metres
NJ = [(0.0, 0.0), (0.0, 0.075), (0.05, 0.33), (0.18, 0.81), (0.2, 0.9), (0.38, 0.9), (0.38, 0.0)]
PROFILES = {"nj": NJ, "h": H, "girder": GIRDER, "deck_w": DECK_W}


def mats():
    return {
        "conc": F.make_mat("Flyover Concrete", (0.55, 0.54, 0.51), rough=0.85),
        "conc_dk": F.make_mat("Concrete Weathered", (0.38, 0.37, 0.35), rough=0.9),
        "barrier": F.make_mat("Barrier Paint", (0.75, 0.75, 0.72), rough=0.7),
        "stripe_y": F.make_mat("Barrier Yellow", (0.85, 0.65, 0.05), rough=0.6),
        "stripe_k": F.make_mat("Barrier Black", (0.03, 0.03, 0.03), rough=0.6),
        "asphalt": F.make_mat("Deck Asphalt", (0.05, 0.05, 0.055), rough=0.85),
        "line": F.make_mat("Lane Paint", (0.85, 0.85, 0.82), rough=0.6),
        "panel": F.make_mat("RE Panel", (0.6, 0.58, 0.54), rough=0.9),
        "steel": F.make_mat("Lamp Steel", (0.45, 0.46, 0.47), metallic=0.8, rough=0.35),
        "lamp": F.make_mat("Lamp Glow", (0.95, 0.92, 0.85), rough=0.3, emission=(1, 0.9, 0.75), strength=3),
        "pipe": F.make_mat("Drain Pipe", (0.25, 0.25, 0.26), rough=0.6),
        "rubber": F.make_mat("Bearing", (0.05, 0.05, 0.05), rough=0.8),
    }


def sweep(name, profile, path, mat, mirror=False):
    """Extrude a (across, up) profile along a list of (x, y, z) points (path runs along X)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        p = Vector(p)
        d = (Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
        side = Vector((0, 0, 1)).cross(d).normalized()
        rings.append([bm.verts.new(p + side * a + Vector((0, 0, h))) for a, h in profile])
    for r1, r2 in zip(rings, rings[1:]):
        for k in range(len(profile) - 1):
            f = bm.faces.new((r1[k], r1[k + 1], r2[k + 1], r2[k]) if not mirror else (r1[k + 1], r1[k], r2[k], r2[k + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = F.link(bpy.data.objects.new(name, me))
    o.data.materials.append(mat)
    return o


def pier(M, x=0.0, y=0.0, ground=0.0):
    """Hammerhead pier: a rounded column, a tapering cap carrying bearings, a drain pipe down the side."""
    top = ground + H - GIRDER
    col_h = top - 1.6 - ground
    F.cyl("Column", (x, y, ground + col_h / 2 - 0.25), 0.95, col_h + 0.5, M["conc"], verts=32)
    F.cyl("ColumnBand", (x, y, ground + col_h - 0.15), 1.0, 0.3, M["conc_dk"], verts=32)
    # cap: a trapezoid in section across the road, full deck width at the top
    bm = bmesh.new()
    w_top, w_bot, d = DECK_W * 0.42, 1.6, 1.8
    pts = [(-w_top, top), (w_top, top), (w_bot, top - 1.6), (-w_bot, top - 1.6)]
    front = [bm.verts.new((x - d / 2, y + a, z)) for a, z in pts]
    back = [bm.verts.new((x + d / 2, y + a, z)) for a, z in pts]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    for k in range(4):
        bm.faces.new((front[k], front[(k + 1) % 4], back[(k + 1) % 4], back[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Cap")
    bm.to_mesh(me)
    bm.free()
    cap = F.link(bpy.data.objects.new("Cap", me))
    cap.data.materials.append(M["conc"])
    for k in range(6):                                                  # bearings under each girder
        F.box("Bearing", (x, y - w_top + 0.6 + k * (2 * w_top - 1.2) / 5, top + 0.06), (0.5, 0.5, 0.12), M["rubber"], bev=0)
    F.cyl("Drain", (x - 0.95, y + 0.4, ground + col_h / 2), 0.08, col_h + 1.0, M["pipe"], verts=10)
    F.box("Plinth", (x, y, ground + 0.15), (2.6, 2.6, 0.3), M["conc_dk"], bev=0.02)


def lamp(M, x, y, z):
    """Double-arm lamp post on the median barrier."""
    F.cyl("Pole", (x, y, z + 5.5), 0.09, 11.0, M["steel"], verts=12)
    for s in (-1, 1):
        F.beam("Arm", (x, y, z + 10.6), (x, y + s * 2.2, z + 11.0), 0.08, 0.08, M["steel"])
        F.box("Head", (x, y + s * 2.4, z + 10.92), (0.4, 0.75, 0.14), M["steel"], bev=0.02)
        F.box("Glow", (x, y + s * 2.4, z + 10.84), (0.32, 0.6, 0.02), M["lamp"], bev=0)
    F.box("Base", (x, y, z + 0.5), (0.4, 0.4, 1.0), M["conc"], bev=0.02)


def deck(M, path):
    """Deck: asphalt, girder sides and underside, barriers, lane paint, along the path (X, Y, Z points)."""
    hw = DECK_W / 2
    sweep("Asphalt", [(-hw + EDGE, 0.0), (hw - EDGE, 0.0)], path, M["asphalt"])
    sweep("Girder", [(hw, 0.0), (hw, -GIRDER * 0.35), (hw - 1.2, -GIRDER), (-hw + 1.2, -GIRDER), (-hw, -GIRDER * 0.35), (-hw, 0.0)],
          path, M["conc"])
    for s in (1, -1):                                                   # edge barriers, facing in
        prof = [(hw - EDGE + a, h) for a, h in NJ]
        sweep("EdgeBarrier", [(p[0] * s, p[1]) for p in prof], path, M["barrier"], mirror=(s < 0))
        sweep("EdgeStripe", [(s * (hw - EDGE + 0.01), 0.05), (s * (hw - EDGE + 0.04), 0.3)], path, M["stripe_y"])
    med = [(a, h) for a, h in NJ]
    sweep("MedianL", [(-MED / 2 - a + 0.38, h) for a, h in med], path, M["barrier"], mirror=True)
    sweep("MedianR", [(MED / 2 + a - 0.38, h) for a, h in med], path, M["barrier"])
    for lane in (-CW / 2 - MED / 2, CW / 2 + MED / 2):                  # lane dashes, edge lines
        for i in range(0, len(path) - 1, 2):
            a, b = Vector(path[i]), Vector(path[min(i + 1, len(path) - 1)])
            F.box("Dash", ((a + b) / 2 + Vector((0, lane, 0.01))), ((b - a).length * 0.9, 0.12, 0.01), M["line"], bev=0)


def ramp_wall(M, x0, x1, y_side, z0, z1):
    """Reinforced-earth wall of square panels from z0 (ground) up to the ramp surface z1 (linear)."""
    n = int((x1 - x0) / 1.5)
    for i in range(n):
        xa = x0 + i * 1.5
        top = z0 + (z1 - z0) * (i + 0.5) / n
        rows = max(1, int((top - z0) / 1.5) + 1)
        for r in range(rows):
            zb = z0 + r * 1.5
            if zb > top:
                break
            h = min(1.45, top - zb)
            F.box("Panel", (xa + 0.75, y_side, zb + h / 2), (1.45, 0.2, h), M["panel"] if (i + r) % 3 else M["conc_dk"], bev=0.01)


def scene(out):
    F.reset()
    M = mats()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = 'GPU'
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 1600, 900
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = -0.5
    sc.world = bpy.data.worlds.new("Sky")
    sc.world.use_nodes = True
    sky = sc.world.node_tree.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING'
    sky.sun_elevation = math.radians(40)
    sky.sun_rotation = math.radians(-60)
    sc.world.node_tree.links.new(sky.outputs[0], sc.world.node_tree.nodes["Background"].inputs[0])
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.12
    # the road below and the ground
    F.box("Ground", (60, 0, -0.06), (400, 120, 0.1), F.make_mat("Soil", (0.3, 0.22, 0.15), rough=0.95), bev=0)
    F.box("Road", (60, 0, -0.01), (400, 24, 0.02), M["asphalt"], bev=0)
    # a ramp (x -120 .. 0) and three spans of flyover (x 0 .. 90)
    path = []
    for i in range(0, 211, 3):
        x = -120 + i
        z = H * min(1.0, max(0.0, (x + 120) / 120.0)) if x < 0 else H
        path.append((x, 0.0, z))
    deck(M, path)
    for k in range(4):
        pier(M, k * SPAN, 0.0)
    for k in range(5):
        lamp(M, -60 + k * SPAN, 0.0, (H * min(1.0, ((-60 + k * SPAN) + 120) / 120.0)) if -60 + k * SPAN < 0 else H)
    for s in (1, -1):
        ramp_wall(M, -110, -2, s * (DECK_W / 2), 0.0, H - 0.2)
    cams = {"street": ((70, -26, 1.7), (35, 0, 5.5), 24), "above": ((-40, -70, 40), (20, 0, 4), 30),
            "deck": ((-30, -4.0, H + 1.6), (60, -4.0, H + 1.0), 26)}
    for name, (loc, tgt, lens) in cams.items():
        cam = F.link(bpy.data.objects.new("Cam" + name, bpy.data.cameras.new("Cam" + name)))
        cam.location = loc
        cam.data.lens = lens
        cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.camera = cam
        sc.render.filepath = out.replace(".png", "_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("SHOT", name, flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in args:
        scene(os.path.abspath(args[args.index("--preview") + 1]))
