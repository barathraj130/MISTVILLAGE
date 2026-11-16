"""The TNSTC town bus (CC-BY 4.0: "Tamilnadu TNSTC Bus 2009-2014" by Car Simulator 2-Preview, @playmode280513,
credited in docs/DATA_SOURCES.md) made a game vehicle the way tools/sketchfab_traffic_pack.py makes the pack's:

  - its real size (the model is 1.51 m long: scaled to 11 m, a TNSTC town bus), the nose along +X (the model's
    front, the shorter overhang, faces -Y), centred, its floor at z 0
  - its wheels (three unnamed meshes each: tyre, rim, hub) gathered under Wheel_FL / Wheel_FR / Wheel_RL / Wheel_RR,
    each pivoting at its own centre
  - the advertisements on its sides and back (a real jeweller's, a resort's) painted out, filled from the livery
    round them (a privately owned business keeps out of the game: docs/NAMING); the route boards (public places)
    kept; the wheels' rims steel grey (they came cyan)
  - added to godot/assets/vehicles/sf_fleet.json (kind "bus") as sf_tnstc_bus: the traffic's buses (city_traffic.gd)
    and a bus you can drive (jeep.gd)

    Blender -b --factory-startup --python tools/sketchfab_tnstc.py
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "vehicles", "tnstc_bus", "source", "Tamilnadu TNSTC bus 2009-2014.glb")
OUT = os.path.join(ROOT, "godot", "assets", "vehicles")
LENGTH = 11.0
KEY = "sf_tnstc_bus"


def bounds(obs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in obs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


FLIP_ROWS = True
BOARD = [True]                                          # (this glb's image comes in top down: as the picture)


def _quad(w, h, pts):
    """A convex outline (image pixels, y down) as a mask of the image's rows (Blender's: y up)."""
    sx = w / 2048.0
    sy = h / 2048.0
    yy, xx = np.mgrid[0:h, 0:w]
    yy = (h - 1 - yy)                                     # (Blender's rows run bottom up)
    yy = (h - 1 - yy) if FLIP_ROWS else yy
    inside = np.ones((h, w), dtype=bool)
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i][0] * sx, pts[i][1] * sy
        x1, y1 = pts[(i + 1) % n][0] * sx, pts[(i + 1) % n][1] * sy
        inside &= ((x1 - x0) * (yy - y0) - (y1 - y0) * (xx - x0)) >= 0.0
    if inside.mean() < 1e-4:                              # (the other winding)
        inside = np.ones((h, w), dtype=bool)
        for i in range(n):
            x0, y0 = pts[i][0] * sx, pts[i][1] * sy
            x1, y1 = pts[(i + 1) % n][0] * sx, pts[(i + 1) % n][1] * sy
            inside &= ((x1 - x0) * (yy - y0) - (y1 - y0) * (xx - x0)) <= 0.0
    return inside


def paint_out_ads(img):
    """The ads (red panels with white lettering, a sky-blue picture board) filled in from what's round them."""
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    r, g, b = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    red = (r - np.maximum(g, b) > 0.22) & (r > 0.4)          # (any red: the panels' shades, compressed)
    light = np.minimum(np.minimum(r, g), b) > 0.6
    # the resort's picture board on the back: its outline on the texture (pixels, from the top-left of the 2048 map)
    board = _quad(w, h, [(1051, 380), (1636, 367), (1508, 753), (1276, 663)])

    def grow(m, n):
        out = m.copy()
        for _ in range(n):
            out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1)
        return out
    near_red = grow(red, 14)
    dark = np.maximum(np.maximum(r, g), b) < 0.25          # (the window band: black)
    livery = g > np.maximum(r, b) + 0.12                   # (the green)
    mask = red | (near_red & ~dark & ~livery) | (board if img.size[0] >= 2048 and BOARD[0] else False)
    mask = grow(mask, 2)
    known = ~mask
    col = px[:, :, :3] * known[:, :, None]
    wsum = known.astype(np.float32)
    fill = px[:, :, :3].copy()
    todo = mask.copy()
    for _ in range(400):                                  # (inwards from the edges: each step the ring next to
        if not todo.any():                                #  what's known takes its known neighbours' mean)
            break
        acc = np.zeros_like(col)
        cnt = np.zeros_like(wsum)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            acc += np.roll(np.roll(col, dy, 0), dx, 1)
            cnt += np.roll(np.roll(wsum, dy, 0), dx, 1)
        ring = todo & (cnt > 0)
        fill[ring] = acc[ring] / cnt[ring][:, None]
        col[ring] = fill[ring]
        wsum[ring] = 1.0
        todo &= ~ring
    px[:, :, :3] = np.where(mask[:, :, None], fill, px[:, :, :3])
    img.pixels[:] = px.ravel()
    img.pack()
    print("TNSTC ads painted out: %.1f%% of the texture" % (100.0 * mask.mean()), flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    done = set()
    for o in meshes:
        for m in o.data.materials:
            if m is None or not m.use_nodes:
                continue
            for nd in m.node_tree.nodes:
                if nd.type == 'TEX_IMAGE' and nd.image and nd.image.size[0] >= 1024 and nd.image.name not in done:
                    done.add(nd.image.name)
                    paint_out_ads(nd.image)
            if m.name.startswith("Metallic"):                 # (the rims: steel, not cyan)
                bsdf = m.node_tree.nodes.get("Principled BSDF")
                if bsdf:
                    bsdf.inputs["Base Color"].default_value = (0.5, 0.5, 0.52, 1.0)
    lo, hi = bounds(meshes)
    k = LENGTH / (hi.y - lo.y)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    to = Matrix.Rotation(math.radians(90.0), 4, 'Z') @ Matrix.Scale(k, 4) @ Matrix.Translation(-centre)
    root = bpy.data.objects.new("TNSTC_Bus", None)
    bpy.context.scene.collection.objects.link(root)
    for o in meshes:                                      # (all of it into the game's frame, applied)
        o.parent = None
        o.matrix_world = to @ o.matrix_world
    bpy.context.view_layer.update()
    for o in meshes:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lo2, hi2 = bounds(meshes)
    body_len = hi2.x - lo2.x
    wheels = []
    groups = {}
    for o in meshes:                                      # the small round parts: a wheel's, by where they are
        a, b = bounds([o])
        size = b - a
        if size.length > 2.0:
            o.parent = root
            continue
        c = (a + b) / 2
        role = ("F" if c.x > 0 else "R") + ("L" if c.y > 0 else "R")
        groups.setdefault(role, []).append((o, c))
    for role, parts in groups.items():
        cen = sum((c for _, c in parts), Vector()) / len(parts)
        w = bpy.data.objects.new("Wheel_" + role, None)
        bpy.context.scene.collection.objects.link(w)
        w.parent = root
        w.location = cen
        for o, _ in parts:
            o.parent = w
            o.matrix_parent_inverse = Matrix.Translation(-cen)
        wheels.append({"name": "Wheel_" + role, "at": [round(cen.x, 3), round(cen.y, 3), round(cen.z, 3)]})
    bpy.context.view_layer.update()
    path = os.path.join(OUT, KEY + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    for o in [root] + list(root.children_recursive):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_image_format='JPEG')
    fpath = os.path.join(OUT, "sf_fleet.json")
    fleet = json.load(open(fpath)) if os.path.exists(fpath) else {}
    fleet[KEY] = {"kind": "bus", "glb": "res://assets/vehicles/%s.glb" % KEY, "len": round(body_len, 3),
                  "w": round(hi2.y - lo2.y, 3), "h": round(hi2.z - lo2.z, 3), "wheels": sorted(wheels, key=lambda w: w["name"]),
                  "lamps": {}, "source": "Tamilnadu TNSTC Bus 2009-2014"}
    with open(fpath, "w") as f:
        json.dump(fleet, f, indent=1)
    print("TNSTC %.2f x %.2f x %.2f m, wheels %s, %.1f MB" % (body_len, hi2.y - lo2.y, hi2.z - lo2.z,
          [w["name"] for w in wheels], os.path.getsize(path) / 1e6), flush=True)


main()
