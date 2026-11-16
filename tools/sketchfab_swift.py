"""The red hatchback (CC-BY 4.0: "Swift 2024" by @ShreyanshChaurasia_12, credited in docs/DATA_SOURCES.md) made a game
vehicle as tools/sketchfab_traffic_pack.py makes the pack's:

  - its real size (3.86 m long), the nose along +X (the model's front faces -Y), centred, its floor at z 0
  - its wheels cut out of the one mesh it came as (the faces round each axle, out at the sides) into Wheel_FL /
    Wheel_FR / Wheel_RL / Wheel_RR, each pivoting at its own centre, so they turn and steer
  - its maker's marks painted out of the texture (the badge on the grille and the bonnet, the name on the number
    plates, front and back: the parts of the texture the middle of the front and the back use, filled from round
    them): a real make keeps its shape, not its badges (docs/NAMING)
  - added to godot/assets/vehicles/sf_fleet.json (kind "hatchback") as sf_red_hatch: parked, in the traffic, and
    one you can drive

    Blender -b --factory-startup --python tools/sketchfab_swift.py
"""
import json
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "vehicles", "swift", "source", "Swift 2024.glb")
OUT = os.path.join(ROOT, "godot", "assets", "vehicles")
LENGTH = 3.86
KEY = "sf_red_hatch"


def bounds_v(vs):
    a = np.array(vs)
    return Vector(a.min(0)), Vector(a.max(0))


def raster(mask, tri, w, h):
    """Mark a UV triangle (0..1 coords, v up) on the mask (rows top down)."""
    p = np.array([[u * w, (1.0 - v) * h] for u, v in tri])
    x0, y0 = np.floor(p.min(0)).astype(int)
    x1, y1 = np.ceil(p.max(0)).astype(int)
    x0, y0 = max(x0 - 1, 0), max(y0 - 1, 0)
    x1, y1 = min(x1 + 1, w - 1), min(y1 + 1, h - 1)
    if x1 < x0 or y1 < y0:
        return
    yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
    (ax, ay), (bx, by), (cx, cy) = p
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-9:
        return
    l1 = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / d
    l2 = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / d
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (1 - l1 - l2 >= -0.02)
    mask[y0:y1 + 1, x0:x1 + 1] |= inside


def inpaint(img, mask_td):
    """Masked pixels (rows top down) filled inwards from their known neighbours' mean."""
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    mask = mask_td[::-1]                                   # (Blender's rows run bottom up)
    known = ~mask
    col = px[:, :, :3] * known[:, :, None]
    wsum = known.astype(np.float32)
    fill = px[:, :, :3].copy()
    todo = mask.copy()
    for _ in range(600):
        if not todo.any():
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
    return mask.mean()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    body = next(o for o in bpy.data.objects if o.type == 'MESH')
    body.parent = None
    bpy.context.view_layer.update()
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    lo, hi = bounds_v(vs)
    k = LENGTH / (hi.y - lo.y)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    body.matrix_world = Matrix.Rotation(math.radians(90.0), 4, 'Z') @ Matrix.Scale(k, 4) @ Matrix.Translation(-centre) @ body.matrix_world
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = body.data
    co = np.array([v.co[:] for v in me.vertices])
    L = co[:, 0].max() - co[:, 0].min()
    W = co[:, 1].max() - co[:, 1].min()
    H = co[:, 2].max() - co[:, 2].min()
    # the wheels: out at the sides, low; each quarter's tyre points give its axle and radius
    wheels = []
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    fc = np.array([f.calc_center_median()[:] for f in bm.faces])
    side_in = W * 0.5 - 0.26
    taken = np.zeros(len(fc), dtype=bool)
    groups = {}
    for fr, xs in (("F", 1.0), ("R", -1.0)):
        for lr, ys in (("L", 1.0), ("R", -1.0)):
            sel = (co[:, 0] * xs > L * 0.15) & (co[:, 1] * ys > side_in) & (co[:, 2] < H * 0.48)
            pts = co[sel]
            if len(pts) < 50:
                continue
            # (only the tyre comes this low: its width 10 cm off the ground gives its radius, 2*sqrt(2*r*z - z*z))
            low = pts[np.abs(pts[:, 2] - 0.1) < 0.025]
            if len(low) < 5:
                continue
            half = (np.percentile(low[:, 0], 98) - np.percentile(low[:, 0], 2)) * 0.5
            r = (half * half + 0.01) / 0.2
            cx = (np.percentile(low[:, 0], 98) + np.percentile(low[:, 0], 2)) * 0.5
            groups[fr + lr] = [cx, ys, r]
    r_all = max(g[2] for g in groups.values())             # (four alike: the rear's measure caught the bumper's edge)
    for role in list(groups.keys()):
        cx, ys, _r = groups[role]
        r = r_all
        cen = Vector((cx, ys * (W * 0.5 - 0.11), r))
        d = np.hypot(fc[:, 0] - cx, fc[:, 2] - r)
        pick = (d < r * 1.02) & (fc[:, 1] * ys > side_in) & ~taken
        taken |= pick
        groups[role] = (cen, r, np.nonzero(pick)[0])
    bm.free()
    roles = list(groups.keys())                            # (each wheel's faces tagged first: separating renumbers
    tag = me.attributes.new("wheel_tag", 'INT', 'FACE')    #  the body's faces, so indices won't do)
    vals = np.zeros(len(me.polygons), dtype=np.int32)
    for n, role in enumerate(roles):
        vals[groups[role][2]] = n + 1
    tag.data.foreach_set("value", vals)
    for n, role in enumerate(roles):                       # split each wheel's faces off as its own object
        cen, r, _idx = groups[role]
        me = body.data
        cur = np.zeros(len(me.polygons), dtype=np.int32)
        me.attributes["wheel_tag"].data.foreach_get("value", cur)
        bpy.ops.object.select_all(action='DESELECT')
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='DESELECT')
        bpy.ops.object.mode_set(mode='OBJECT')
        sel = np.zeros(len(me.polygons), dtype=bool)
        sel[cur == n + 1] = True
        me.polygons.foreach_set("select", sel)
        me.update()
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        part = [o for o in bpy.context.selected_objects if o != body][0]
        piv = bpy.data.objects.new("Wheel_" + role, None)
        bpy.context.scene.collection.objects.link(piv)
        piv.location = cen
        part.parent = piv
        part.matrix_parent_inverse = Matrix.Translation(-cen)
        wheels.append({"name": "Wheel_" + role, "at": [round(cen.x, 3), round(cen.y, 3), round(cen.z, 3)], "r": round(r, 3)})
    me = body.data
    # its maker's marks: the texture the front's and the back's middle use (the grille, the plates, the bonnet's
    # front edge, the hatch's middle), painted out from round them
    img = None
    for m in me.materials:
        for nd in (m.node_tree.nodes if m and m.use_nodes else []):
            if nd.type == 'TEX_IMAGE' and nd.image and (img is None or nd.image.size[0] > img.size[0]):
                img = nd.image
    uvl = me.uv_layers.active.data
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)   # (rows bottom up)
    x0, x1 = co[:, 0].min(), co[:, 0].max()
    marked, near = [], []
    for poly in me.polygons:
        c = poly.center
        front = c.x > x1 - 0.45 and abs(c.y) < 0.26 and 0.2 < c.z < 1.0
        back = c.x < x0 + 0.34 and abs(c.y) < 0.34 and 0.35 < c.z < 1.35
        if front or back:
            marked.append(poly.index)
        elif (c.x > x1 - 0.7 or c.x < x0 + 0.55) and abs(c.y) < 0.6:
            near.append(poly.index)

    def face_colour(pi):                                  # (its texture at its middle)
        uv = np.mean([uvl[li].uv[:] for li in me.polygons[pi].loop_indices], axis=0)
        x = int(np.clip(uv[0] * w, 0, w - 1))
        y = int(np.clip(uv[1] * h, 0, h - 1))
        return px[y, x, :3]
    from mathutils import kdtree
    kd = kdtree.KDTree(len(near))
    for n, pi in enumerate(near):
        kd.insert(me.polygons[pi].center, n)
    kd.balance()
    near_col = [face_colour(pi) for pi in near]
    for pi in marked:                                     # each marked face: the colour of the car round it, on
        hits = kd.find_n(me.polygons[pi].center, 14)      #  the car (its texture's neighbours are other parts);
        col = np.median([near_col[i] for _, i, _ in hits], axis=0) if hits else np.array([0.5, 0.1, 0.1])   # (most)
        m = np.zeros((h, w), dtype=bool)
        uv = [uvl[li].uv[:] for li in me.polygons[pi].loop_indices]
        for t in range(1, len(uv) - 1):
            raster(m, [uv[0], uv[t], uv[t + 1]], w, h)
        px[m[::-1], :3] = col
    img.pixels[:] = px.ravel()
    img.pack()
    marks = len(marked)
    share = 0.0
    if img.size[0] > 2048:                                # (a lighter file: 2048 is plenty for a car)
        img.scale(2048, 2048)
        img.pack()
    # the body's own colour stays; the lamps and glass as they are
    for o in [body] + [c for p in bpy.data.objects if p.name.startswith("Wheel_") for c in p.children]:
        o.select_set(True)
    root = bpy.data.objects.new("RedHatch", None)
    bpy.context.scene.collection.objects.link(root)
    body.parent = root
    for p in bpy.data.objects:
        if p.name.startswith("Wheel_"):
            p.parent = root
    path = os.path.join(OUT, KEY + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    for o in [root] + list(root.children_recursive):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_image_format='JPEG')
    fpath = os.path.join(OUT, "sf_fleet.json")
    fleet = json.load(open(fpath))
    fleet[KEY] = {"kind": "hatchback", "glb": "res://assets/vehicles/%s.glb" % KEY, "len": round(L, 3), "w": round(W, 3),
                  "h": round(H, 3), "wheels": sorted(wheels, key=lambda x: x["name"]), "lamps": {}, "source": "Swift 2024"}
    with open(fpath, "w") as f:
        json.dump(fleet, f, indent=1)
    print("SWIFT %.2f x %.2f x %.2f m, wheels %s, marks: %d faces, %.1f%% of the texture, %.1f MB" % (
        L, W, H, [(x["name"], x["at"], x["r"]) for x in wheels], marks, 100 * share, os.path.getsize(path) / 1e6), flush=True)


main()
