"""Small shared shapes for our vehicle builders (tools/cars/build_*.py), on the car kit (carkit.py): boxes, cylinders,
round tubes along paths, lofts through sections, coil springs, toothed sprockets, joining parts into one object.
Blender's frame as the kit's: +X the nose, +Y left, Z up, metres."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import carkit as K


def box(name, size, at, mat, rot=(0, 0, 0), bevel=0.0, segs=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = K.mesh_obj(name, bm, [mat])
    ob.scale = size
    ob.location = at
    ob.rotation_euler = rot
    if bevel > 0:
        b = ob.modifiers.new("Bv", 'BEVEL')
        b.width = bevel
        b.segments = segs
        b.limit_method = 'ANGLE'
    return ob


def cyl(name, r, length, at, mat, axis='Y', segs=24, r2=None, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=length)
    ob = K.mesh_obj(name, bm, [mat])
    ob.location = at
    ob.rotation_euler = rot if rot is not None else {'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0), 'Z': (0, 0, 0)}[axis]
    K.smooth(ob, 40)
    return ob


def tube(name, pts, r, mat, segs=10, smooth_pts=0, caps=True):
    """A round tube along a polyline (rounded through its corners when smooth_pts > 0)."""
    if smooth_pts:
        pts = smooth_path(pts, smooth_pts)
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1.0)
    cu.bevel_depth = r
    cu.bevel_resolution = max(1, segs // 4)
    cu.use_fill_caps = caps
    ob = bpy.data.objects.new(name, cu)
    K.link(ob)
    ob.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    K.smooth(ob, 50)
    return ob


def smooth_path(pts, n=8):
    """A polyline rounded through its points (Catmull-Rom), n points a span."""
    out = []
    P = [Vector(p) for p in pts]
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for k in range(n):
            t = k / n
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return [tuple(v) for v in out]


def grid(name, rows, mat, closed=False, keep=None, cap_ends=False):
    """Quads between rows of points (rows the same length); closed: each row a ring; keep(centre) drops faces."""
    bm = bmesh.new()
    V = [[bm.verts.new(p) for p in row] for row in rows]
    n = len(rows[0])
    for i in range(len(rows) - 1):
        for j in range(n - 1 + (1 if closed else 0)):
            a, b = V[i][j], V[i][(j + 1) % n]
            c, d = V[i + 1][(j + 1) % n], V[i + 1][j]
            if keep is None or keep((a.co + b.co + c.co + d.co) / 4):
                bm.faces.new((a, b, c, d))
    if cap_ends and closed:
        for row in (V[0], V[-1]):
            ctr = bm.verts.new(sum((v.co for v in row), Vector()) / len(row))
            for j in range(n):
                bm.faces.new((row[j], row[(j + 1) % n], ctr))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return K.mesh_obj(name, bm, [mat])


def section(cx, cz, w, h_top, h_bot, n=24, p_top=2.4, p_bot=2.4, y0=0.0, plane='YZ', x=0.0):
    """A closed superelliptic section: half width w, up h_top and down h_bot from (cy=y0, cz); in the y-z plane
    at x (a lengthwise loft), or in the x-z plane at y=cx (plane='XZ')."""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        c, s = math.cos(a), math.sin(a)
        p = p_top if s >= 0 else p_bot
        hh = h_top if s >= 0 else h_bot
        u = math.copysign(abs(c) ** (2 / p), c) * w
        v = math.copysign(abs(s) ** (2 / p), s) * hh
        pts.append((x, y0 + u, cz + v) if plane == 'YZ' else (cx + u, x, cz + v))
    return pts


def loft(name, stations, mat, n=28, caps=True):
    """A closed body swept through superelliptic sections: stations [(x, w, z_mid, h_top, h_bot, p_top, p_bot)]."""
    rows = [section(0, z, w, ht, hb, n, pt, pb, x=x) for (x, w, z, ht, hb, pt, pb) in stations]
    ob = grid(name, rows, mat, closed=True, cap_ends=caps)
    K.smooth(ob, 50)
    return ob


def helix(name, a, b, coil_r, wire_r, turns, mat, segs=14):
    a, b = Vector(a), Vector(b)
    ax = (b - a)
    L = ax.length
    d = ax.normalized()
    side = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
    up = d.cross(side)
    pts = []
    n = int(turns * segs)
    for k in range(n + 1):
        t = k / n
        ang = 2 * math.pi * turns * t
        pts.append(tuple(a + d * (L * t) + (side * math.cos(ang) + up * math.sin(ang)) * coil_r))
    return tube(name, pts, wire_r, mat, segs=6)


def sprocket(name, at, r, teeth, th, mat, axis='Y'):
    """A toothed sprocket (a flat gear plate with a lightening of holes left out) facing along Y."""
    bm = bmesh.new()
    pts = []
    for k in range(teeth * 4):
        a = 2 * math.pi * k / (teeth * 4)
        tooth = (k % 4) in (1, 2)
        rr = r + (0.006 if tooth else -0.002)
        pts.append((math.cos(a) * rr, math.sin(a) * rr))
    top = [bm.verts.new((x, th / 2, z)) for x, z in pts]
    bot = [bm.verts.new((x, -th / 2, z)) for x, z in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for k in range(n):
        bm.faces.new((top[k], top[(k + 1) % n], bot[(k + 1) % n], bot[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = K.mesh_obj(name, bm, [mat])
    ob.location = at
    return ob


def join(objs, name):
    """Parts made one object (their modifiers applied), named name."""
    objs = [o for o in objs if o is not None]
    for o in objs:
        if o.modifiers:
            K.apply_mods(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def place(ob, at, fwd, up=Vector((0, 0, 1))):
    """Turns an object built along +X (a lathe about X) to point along fwd, then puts it at `at`."""
    q = Vector(fwd).to_track_quat('X', 'Z')
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = q
    ob.location = at
    return ob
