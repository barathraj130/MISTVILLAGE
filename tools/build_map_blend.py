"""
The whole game map as one Blender file, built from the same data the game reads
(godot/assets/drive: map.json, near.bin, far.bin, towns.json), so you can open it, fly around,
inspect and edit the world in Blender.

    Blender -b --factory-startup --python tools/build_map_blend.py -- blender/full_map.blend [--step 2]

Collections:
    Terrain      near ground in 1 km tiles (8 m grid by default, --step 1 for the full 4 m), far backdrop
    Highway      the Coimbatore → Kotagiri road: asphalt, shoulders, centre line
    <Town>       streets, parking lots, buildings (footprints raised to their floors, coloured), places
    Places       an empty per named place (temples, bunks, hospitals …) with its name
Coordinates: Blender X = game x, Blender Y = −game z, Blender Z = game y (up), metres.
"""
import json
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "godot", "assets", "drive")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "blender", "full_map.blend"))
STEP = int(args[args.index("--step") + 1]) if "--step" in args else 2


def B(x, y, z):
    """game (x, y, z) → Blender (x, -z, y)"""
    return (x, -z, y)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def coll(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def mat(name, color, rough=0.8, vertex=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if vertex:
        attr = m.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        m.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def mesh_obj(name, verts, faces, material, collection, colors=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    if colors is not None and len(colors):
        layer = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
        cols = np.repeat(np.asarray(colors, dtype=np.float32), [len(f) for f in faces], axis=0)
        layer.data.foreach_set("color", cols.ravel())
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    return ob


def ribbon(pts, half, y_off=0.0):
    """Quads along a polyline of game points (N×3), half-width each side."""
    p = np.asarray(pts, dtype=np.float64)
    if len(p) < 2:
        return [], []
    t = np.gradient(p[:, [0, 2]], axis=0)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
    n = np.column_stack([t[:, 1], -t[:, 0]])
    L = p[:, [0, 2]] + n * half
    R = p[:, [0, 2]] - n * half
    verts, faces = [], []
    for i in range(len(p)):
        verts.append(B(L[i, 0], p[i, 1] + y_off, L[i, 1]))
        verts.append(B(R[i, 0], p[i, 1] + y_off, R[i, 1]))
    for i in range(len(p) - 1):
        a = 2 * i
        faces.append((a, a + 2, a + 3, a + 1))
    return verts, faces


# ----------------------------------------------------------------------------- terrain
def terrain(m, root):
    tc = coll("Terrain", root)
    nd = m["near"]
    nx, nz, cell, gx0, gz0 = nd["nx"], nd["nz"], nd["cell"], nd["gx0"], nd["gz0"]
    h = np.fromfile(os.path.join(DATA, nd["file"]), dtype="<f4").reshape(nz, nx)
    grass = mat("Ground", (0.33, 0.38, 0.2), 0.95)
    tile = int(1000 / (cell * STEP))
    hs = h[::STEP, ::STEP]
    zs, xs = hs.shape
    count = 0
    for tz in range(0, zs - 1, tile):
        for tx in range(0, xs - 1, tile):
            blk = hs[tz:tz + tile + 1, tx:tx + tile + 1]
            if np.isnan(blk).all():
                continue
            bz, bx = blk.shape
            idx = -np.ones(blk.shape, dtype=np.int64)
            ok = ~np.isnan(blk)
            idx[ok] = np.arange(ok.sum())
            jj, ii = np.nonzero(ok)
            gx = (gx0 + (tx + ii) * STEP) * cell
            gz = (gz0 + (tz + jj) * STEP) * cell
            verts = np.column_stack([gx, -gz, blk[ok]])
            a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]
            good = (a >= 0) & (b >= 0) & (c >= 0) & (d >= 0)
            faces = np.column_stack([a[good], d[good], c[good], b[good]])
            if len(faces) == 0:
                continue
            me = bpy.data.meshes.new("Ground_%d_%d" % (tx, tz))
            me.vertices.add(len(verts))
            me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
            me.loops.add(len(faces) * 4)
            me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
            me.polygons.add(len(faces))
            me.polygons.foreach_set("loop_start", np.arange(0, len(faces) * 4, 4, dtype=np.int32))
            me.update()
            me.materials.append(grass)
            ob = bpy.data.objects.new(me.name, me)
            tc.objects.link(ob)
            count += 1
    fd = m["far"]
    fh = np.fromfile(os.path.join(DATA, fd["file"]), dtype="<f4").reshape(fd["h"], fd["w"])
    fs = fh[::2, ::2]
    zz, xx = np.mgrid[0:fs.shape[0], 0:fs.shape[1]]
    verts = np.column_stack([fd["ox"] + xx.ravel() * fd["cell"] * 2, -(fd["oz"] + zz.ravel() * fd["cell"] * 2), fs.ravel() - 1.0])
    W = fs.shape[1]
    a = (zz[:-1, :-1] * W + xx[:-1, :-1]).ravel()
    faces = np.column_stack([a, a + W, a + W + 1, a + 1])
    mesh_obj("FarHills", verts, faces, mat("FarGround", (0.25, 0.32, 0.18), 1.0), tc)
    print("terrain tiles", count)


# ----------------------------------------------------------------------------- highway
def highway(m, root):
    hc = coll("Highway", root)
    s = m["samples"]
    pts = np.column_stack([s["x"], s["y"], s["z"]])
    for name, half, off, col, r in (("Shoulders", 5.0, -0.06, (0.55, 0.35, 0.24), 1.0),
                                    ("Asphalt", 3.6, 0.0, (0.07, 0.07, 0.075), 0.8),
                                    ("CentreLine", 0.07, 0.02, (0.9, 0.9, 0.85), 0.5)):
        v, f = ribbon(pts, half, off)
        mesh_obj("Highway" + name, v, f, mat("Highway" + name, col, r), hc)


# ----------------------------------------------------------------------------- towns
def towns(root):
    data = json.load(open(os.path.join(DATA, "towns.json")))
    asphalt = mat("Street", (0.08, 0.08, 0.085), 0.8)
    lotm = mat("Parking", (0.3, 0.3, 0.31), 0.85)
    bm = mat("Buildings", (1, 1, 1), 0.85, vertex=True)
    pc = coll("Places", root)
    for tname, tw in data.items():
        tcol = coll(tname, root)
        V, F = [], []
        for st in tw["streets"]:
            v, f = ribbon(st["pts"], st["width"] * 0.5, 0.0)
            o = len(V)
            V += v
            F += [tuple(i + o for i in q) for q in f]
        mesh_obj(tname + "Streets", V, F, asphalt, tcol)
        V, F = [], []
        for lot in tw.get("parking", []):
            o = len(V)
            V += [B(q[0], lot["y"] + 0.03, q[1]) for q in lot["poly"]]
            F.append((o, o + 1, o + 2, o + 3))
        if V:
            mesh_obj(tname + "Parking", V, F, lotm, tcol)
        V, F, C = [], [], []
        for b in tw["buildings"]:
            poly = b["poly"]
            n = len(poly)
            if n < 3:
                continue
            base = b["base"]
            top = base + 0.3 + int(b["floors"]) * 3.2
            col = tuple(b["color"][:3]) + (1.0,)
            # make the footprint counter-clockwise (seen from above in Blender)
            area = sum(poly[i][0] * (-poly[(i + 1) % n][1]) - poly[(i + 1) % n][0] * (-poly[i][1]) for i in range(n))
            ring = poly if area > 0 else poly[::-1]
            o = len(V)
            for q in ring:
                V.append(B(q[0], base, q[1]))
            for q in ring:
                V.append(B(q[0], top, q[1]))
            for i in range(n):
                j = (i + 1) % n
                F.append((o + i, o + j, o + n + j, o + n + i))
                C.append(col)
            F.append(tuple(o + n + i for i in range(n)))
            C.append((0.55, 0.54, 0.52, 1.0) if "roof" not in b else tuple(c * 1.6 for c in b["roof"]) + (1.0,))
        mesh_obj(tname + "Buildings", V, F, bm, tcol, C)
        for p in tw["pois"]:
            e = bpy.data.objects.new("%s · %s" % (p["kind"], p["name"]), None)
            e.empty_display_type = 'SINGLE_ARROW'
            e.empty_display_size = 6
            e.location = B(p["x"], p["y"] + 2.0, p["z"])
            pc.objects.link(e)
        print("town", tname, len(tw["streets"]), "streets", len(tw["buildings"]), "buildings")


def main():
    reset()
    m = json.load(open(os.path.join(DATA, "map.json")))
    root = coll("MistVillageMap")
    terrain(m, root)
    highway(m, root)
    towns(root)
    s = m["samples"]
    end = bpy.data.objects.new("TheMistVillage (resort: open MistVillage.blend)", None)
    end.empty_display_type = 'CUBE'
    end.empty_display_size = 20
    end.location = B(s["x"][-1], s["y"][-1], s["z"][-1])
    bpy.context.scene.collection.objects.link(end)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.scene.collection.objects.link(sun)
    bpy.context.scene.unit_settings.system = 'METRIC'
    for area_clip in bpy.data.screens:
        pass
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("SAVED", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB")


main()
