"""
Car bodies for The Mist Village, modelled the way real cars are drawn: a side profile (bonnet, windscreen,
roof, tail), a plan outline and a cross-section with a shoulder and tumblehome are swept into ONE
continuous body surface. Glass, pillars, lamps, grille, door shut lines and black cladding are then
zones on that surface (so they follow its curves like the real thing), and the wheel arches are cut out.
Details (mirrors, handles, wipers, plates, wheels with tyres/alloys/brakes) come from tools/fleet.py.

    Blender -b --factory-startup --python tools/carbody.py -- <out_dir> [kinds...]

Blender +X is the nose, +Y the car's left, Z up (same as tools/fleet.py, so the game loads them alike).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fleet as F  # noqa: E402  (materials, wheels, boxes, export)


def cr(keys, x):
    """Catmull-Rom through (x, value) keys sorted by x, evaluated at x (clamped)."""
    ks = sorted(keys)
    if x <= ks[0][0]:
        return ks[0][1]
    if x >= ks[-1][0]:
        return ks[-1][1]
    for i in range(len(ks) - 1):
        if ks[i][0] <= x <= ks[i + 1][0]:
            p0 = ks[max(i - 1, 0)][1]
            p1, p2 = ks[i][1], ks[i + 1][1]
            p3 = ks[min(i + 2, len(ks) - 1)][1]
            t = (x - ks[i][0]) / (ks[i + 1][0] - ks[i][0])
            return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def resample(pts, n):
    """n points evenly spaced by arc length along a polyline."""
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (Vector(b) - Vector(a)).length)
    out = []
    for k in range(n):
        s = d[-1] * k / (n - 1)
        for i in range(len(d) - 1):
            if d[i] <= s <= d[i + 1] or i == len(d) - 2:
                t = 0.0 if d[i + 1] == d[i] else (s - d[i]) / (d[i + 1] - d[i])
                a, b = Vector(pts[i]), Vector(pts[i + 1])
                out.append(a.lerp(b, min(max(t, 0.0), 1.0)))
                break
    return out


# ----------------------------------------------------------------------------- specs
# x positions are along the car (nose +), heights z from the ground, half widths y.
SPECS = {
    "hatchback": dict(
        L=3.86, R=0.31, track=0.75, axles=(1.24, -1.21), paint=(0.62, 0.63, 0.65), lip="clad",
        top=[(1.93, 0.66), (1.84, 0.79), (1.55, 0.875), (1.2, 0.92), (0.93, 0.955), (0.55, 1.22), (0.2, 1.42),
             (-0.2, 1.475), (-0.9, 1.485), (-1.3, 1.47), (-1.62, 1.4), (-1.82, 1.16), (-1.93, 0.98)],
        bot=[(1.93, 0.34), (1.8, 0.24), (1.4, 0.2), (0, 0.18), (-1.5, 0.2), (-1.85, 0.27), (-1.93, 0.4)],
        half=[(1.93, 0.6), (1.86, 0.76), (1.65, 0.845), (1.2, 0.862), (0, 0.868), (-1.4, 0.862), (-1.75, 0.83), (-1.88, 0.76), (-1.93, 0.66)],
        belt=[(1.0, 0.93), (0.0, 0.95), (-1.5, 1.0)],
        glass=(0.93, -1.84), ws_top=0.2, rear_glass=-1.42, tumble=0.17,
        pillars=[(-0.22, 0.05)], doors=[0.86, -0.22, -1.2], tailgate=True, dlo_end=-1.62,
        head=dict(z=(0.66, 0.79), y=(0.42, 0.8)), tail=dict(z=(0.86, 1.06), y=(0.5, 0.86)),
        grille=dict(z=(0.47, 0.64), y=0.4), intake=dict(z=(0.24, 0.4), y=0.62)),
    "sedan": dict(
        L=4.42, R=0.315, track=0.77, axles=(1.36, -1.29), paint=(0.55, 0.06, 0.05), lip="paint",
        top=[(2.21, 0.66), (2.12, 0.79), (1.8, 0.86), (1.3, 0.92), (1.0, 0.95), (0.62, 1.2), (0.25, 1.4),
             (-0.2, 1.455), (-0.75, 1.45), (-1.1, 1.36), (-1.45, 1.08), (-1.7, 1.01), (-2.05, 1.0), (-2.21, 0.92)],
        bot=[(2.21, 0.34), (2.05, 0.24), (1.6, 0.2), (0, 0.18), (-1.7, 0.2), (-2.1, 0.28), (-2.21, 0.42)],
        half=[(2.21, 0.6), (2.14, 0.77), (1.9, 0.85), (1.3, 0.87), (0, 0.875), (-1.5, 0.87), (-1.95, 0.84), (-2.15, 0.77), (-2.21, 0.68)],
        belt=[(1.0, 0.93), (0.0, 0.95), (-1.5, 1.0)],
        glass=(1.0, -1.45), ws_top=0.25, rear_glass=-0.85, tumble=0.18,
        pillars=[(-0.22, 0.05)], doors=[0.92, -0.22, -1.25], tailgate=False, dlo_end=-1.28,
        head=dict(z=(0.66, 0.79), y=(0.42, 0.82)), tail=dict(z=(0.8, 0.98), y=(0.45, 0.87)),
        grille=dict(z=(0.47, 0.65), y=0.42), intake=dict(z=(0.24, 0.4), y=0.64)),
}


def body_mesh(sp, name="Body"):
    L = sp["L"]
    hx = L / 2
    # stations along the car: even spacing plus tight pairs at every shut line (to draw the gaps)
    xs = [hx - L * i / 110 for i in range(111)]
    for g in sp["doors"]:
        xs += [g - 0.007, g + 0.007]
    if sp["tailgate"]:
        xs += [sp["rear_glass"] - 0.03, sp["rear_glass"] - 0.044]
    xs = sorted(set(round(x, 4) for x in xs), reverse=True)
    K = 40                                                    # points per half-section
    g0, g1 = sp["glass"]
    rings = []
    for x in xs:
        top = cr(sp["top"], x)
        zb = cr(sp["bot"], x)
        w = cr(sp["half"], x)
        belt = min(cr(sp["belt"], x), top - 0.02)
        # one section shape everywhere (so vertices don't jump between stations): where there's no
        # glasshouse (bonnet, boot) its upper part simply collapses towards the shoulder
        g = min(max((top - belt - 0.04) / 0.25, 0.0), 1.0)
        if not (g1 - 0.05 <= x <= g0 + 0.05):
            g = 0.0
        rb = min(0.09, (belt - zb) * 0.3)
        wt = w - sp["tumble"] * g - 0.06 * (1 - g)
        rt = min(0.08, max(top - belt, 0.02) * 0.3)
        half = [(0.0, zb), (w * 0.6, zb), (w - rb, zb + 0.01), (w - 0.01, zb + rb), (w - 0.004, zb + (belt - zb) * 0.45),
                (w + 0.004, belt - 0.15), (w - 0.006, belt - 0.13), (w - 0.012, belt - 0.03), (w - 0.03, belt), (w - 0.03 - 0.03 * g, belt + 0.02 * g + 0.004),
                (wt + 0.03 * g, top - rt * g - 0.004), (wt - rt * 0.6, top - 0.006 * g), (wt * 0.5, top + 0.012 + 0.008 * (1 - g)),
                (0.0, top + 0.018 + 0.004 * (1 - g))]
        rs = resample(half, K)
        rings.append([(x, p.x, p.y) for p in rs])
    bm = bmesh.new()
    vr = []
    for ring in rings:
        right = [bm.verts.new((x, -y, z)) for (x, y, z) in ring]
        left = [bm.verts.new((x, y, z)) for (x, y, z) in reversed(ring[1:-1])]
        vr.append(right + left)
    n = len(vr[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    for ring, rev in ((vr[0], False), (vr[-1], True)):                       # nose and tail caps
        c = bm.verts.new(sum((v.co for v in ring), Vector()) / n)
        for i in range(n):
            f = (ring[i], ring[(i + 1) % n], c)
            bm.faces.new(f[::-1] if rev else f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = F.link(bpy.data.objects.new(name, me))
    F.smooth(ob)
    return ob


def zone(sp, c, nrm):
    """Body surface material from a face's centre: paint, black cladding low down, or a shut line."""
    x, y, z = c
    ay = abs(y)
    hx = sp["L"] / 2
    belt = cr(sp["belt"], x)
    w = cr(sp["half"], x)
    for g in sp["doors"]:
        if abs(x - g) < 0.007 and 0.28 < z < belt - 0.01 and ay > w - 0.12:
            return "gap"
    if z < 0.3 and (x > hx - 0.45 or x < -hx + 0.45 or ay > w - 0.05):
        return "clad"
    return "paint"


# ----------------------------------------------------------------------------- projected panels
def patch(bvh, outline, axis, sign, mat, name, off=0.004, cuts=3):
    """A panel drawn as a clean outline and projected onto the body along an axis, so its edge is crisp
    and it hugs every curve: windows, lamps, grille. outline: (a, b) pairs in the plane across `axis`
    ('y': (x, z), 'x': (y, z), 'z': (x, y)); rays come from the `sign` side."""
    bm = bmesh.new()
    vs = []
    for a, b in outline:
        co = (a, sign * 3.0, b) if axis == "y" else ((sign * 5.0, a, b) if axis == "x" else (a, b, 4.0))
        vs.append(bm.verts.new(co))
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f], quad_method='BEAUTY', ngon_method='EAR_CLIP')
    for _ in range(cuts):
        bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=1, use_grid_fill=True)
    d = Vector((0, -sign, 0)) if axis == "y" else (Vector((-sign, 0, 0)) if axis == "x" else Vector((0, 0, -1)))
    miss = []
    nrm = {}
    for v in bm.verts:
        loc, n, _i, _d = bvh.ray_cast(v.co, d)
        if loc is None:
            miss.append(v)
        else:
            v.co = loc + n * off
            nrm[v] = n
    if miss:
        bmesh.ops.delete(bm, geom=miss, context='VERTS')
    for fc in bm.faces:
        avg = sum((nrm.get(v, Vector()) for v in fc.verts), Vector())
        if fc.normal.dot(avg) < 0:
            fc.normal_flip()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = F.link(bpy.data.objects.new(name, me))
    ob.data.materials.append(mat)
    F.smooth(ob)
    return ob


def rounded(pts, r=0.03, n=3):
    """Round a polygon's corners a little (each corner replaced by an arc of n points)."""
    out = []
    m = len(pts)
    for i in range(m):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % m])
        a = p1 + (p0 - p1).normalized() * min(r, (p0 - p1).length * 0.45)
        b = p1 + (p2 - p1).normalized() * min(r, (p2 - p1).length * 0.45)
        for k in range(n + 1):
            t = k / n
            q = a.lerp(p1, t).lerp(p1.lerp(b, t), t)          # quadratic Bezier a → p1 → b
            out.append((q.x, q.y))
    return out


def panels(sp, body, M):
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(body, dg)
    hx = sp["L"] / 2
    g0, g1 = sp["glass"]
    ws = sp["ws_top"]
    bx, bw = sp["pillars"][0]
    top = lambda x: cr(sp["top"], x)            # noqa: E731
    belt = lambda x: cr(sp["belt"], x)          # noqa: E731
    half = lambda x: cr(sp["half"], x)          # noqa: E731
    xr = sp["dlo_end"]
    # side windows, both sides: front door glass and rear door + quarter glass, with the B pillar between
    gx0 = g0 - 0.17
    ztop = lambda x: top(x) - 0.075             # noqa: E731
    front = [(gx0, belt(gx0) + 0.035)]
    for k in range(9):                          # up the A pillar line
        t = k / 8
        x = gx0 + (ws - 0.04 - gx0) * t
        front.append((x, (belt(gx0) + 0.035) * (1 - t) + ztop(ws - 0.04) * t))
    xs = [ws - 0.04 - (ws - 0.04 - (bx + bw)) * k / 10 for k in range(1, 11)]
    front += [(x, ztop(x)) for x in xs]
    front += [(bx + bw, belt(bx + bw) + 0.035)]
    rear = [(bx - bw, ztop(bx - bw))]
    xs = [bx - bw - (bx - bw - (xr + 0.08)) * k / 12 for k in range(1, 13)]
    rear += [(x, ztop(x)) for x in xs]
    rear += [(xr, belt(xr) + 0.06), (bx - bw, belt(bx - bw) + 0.035)]
    for s in (1, -1):
        patch(bvh, rounded(front, 0.04), "y", s, M["trim"], "WinFrame", off=0.002)
        patch(bvh, rounded(rear, 0.04), "y", s, M["trim"], "WinFrame", off=0.002)
        patch(bvh, rounded(_shrink(front, 0.022), 0.035), "y", s, M["glass"], "Glass", off=0.004)
        patch(bvh, rounded(_shrink(rear, 0.022), 0.035), "y", s, M["glass"], "Glass", off=0.004)
    # windscreen, from above
    yb, yt = half(g0 - 0.05) - 0.17, half(ws) - sp["tumble"] - 0.05
    patch(bvh, rounded([(g0 - 0.05, -yb), (g0 - 0.05, yb), (ws + 0.03, yt), (ws + 0.03, -yt)], 0.06), "z", 1, M["trim"],
          "WinFrame", off=0.002)
    patch(bvh, rounded([(g0 - 0.07, -yb + 0.03), (g0 - 0.07, yb - 0.03), (ws + 0.05, yt - 0.02), (ws + 0.05, -yt + 0.02)], 0.05),
          "z", 1, M["glass"], "Glass", off=0.004)
    # rear glass: a hatch's tailgate glass faces backwards; a saloon's back window faces up
    if sp["tailgate"]:
        zr0, zr1 = top(-hx + 0.08) + 0.06, top(sp["rear_glass"]) - 0.06
        yr = half(sp["rear_glass"]) - sp["tumble"] - 0.06
        patch(bvh, rounded([(-yr, zr0), (yr, zr0), (yr - 0.05, zr1), (-yr + 0.05, zr1)], 0.05), "x", -1, M["glass"], "Glass")
    else:
        x0, x1 = sp["rear_glass"], g1 + 0.06
        yr = half(x0) - sp["tumble"] - 0.06
        patch(bvh, rounded([(x0, -yr), (x0, yr), (x1, yr - 0.05), (x1, -yr + 0.05)], 0.05), "z", 1, M["glass"], "Glass")
    # B pillar in gloss black between the door glasses
    for s in (1, -1):
        patch(bvh, [(bx - bw, belt(bx) + 0.03), (bx + bw, belt(bx) + 0.03), (bx + bw, ztop(bx)), (bx - bw, ztop(bx))],
              "y", s, M["trim"], "BPillar", off=0.003)
    # lamps and grille, drawn from the front / back
    for s in (1, -1):
        hl = [(0.4, 0.675), (0.62, 0.66), (0.8, 0.695), (0.825, 0.775), (0.72, 0.79), (0.45, 0.755)]
        patch(bvh, rounded([(s * y, z) for y, z in hl][::s], 0.02), "x", 1, M["trim"], "LampHousing", off=0.003)
        # inside the lamp: two chrome projector units and an LED daytime-running strip along the lower edge
        for yy in (0.53, 0.68):
            zz = 0.733 if yy < 0.6 else 0.738
            loc, n, _i, _d = bvh.ray_cast(Vector((5.0, s * yy, zz)), Vector((-1, 0, 0)))
            if loc:
                rot = n.to_track_quat('Z', 'Y').to_euler()
                F.cyl("Reflector", loc + n * 0.006, 0.042, 0.012, M["chrome"], rot=rot, verts=24)
                F.cyl("Headlight", loc + n * 0.014, 0.026, 0.008, M["head"], rot=rot, verts=20)
        drl = [(0.43, 0.68), (0.62, 0.668), (0.79, 0.702), (0.79, 0.716), (0.62, 0.684), (0.43, 0.696)]
        patch(bvh, [(s * y, z) for y, z in drl][::s], "x", 1, M["head"], "Headlight", off=0.006, cuts=2)
        tl = [(0.48, sp["tail"]["z"][0] + 0.02), (0.9, sp["tail"]["z"][0]), (0.92, sp["tail"]["z"][1]),
              (0.62, sp["tail"]["z"][1] + 0.02), (0.48, sp["tail"]["z"][1] - 0.04)]
        patch(bvh, rounded([(s * y, z) for y, z in tl][::s], 0.02), "x", -1, M["tail"], "TailBar", off=0.004)
    gz = sp["grille"]["z"]
    gy = sp["grille"]["y"]
    patch(bvh, rounded([(-gy, gz[0]), (gy, gz[0]), (gy + 0.05, (gz[0] + gz[1]) / 2), (gy - 0.03, gz[1]), (-gy + 0.03, gz[1]),
                        (-gy - 0.05, (gz[0] + gz[1]) / 2)], 0.03), "x", 1, M["trim"], "Grille", off=0.005)
    for k in range(3):                                         # grille slats
        zk = gz[0] + (gz[1] - gz[0]) * (k + 1) / 4
        patch(bvh, [(-gy + 0.02, zk - 0.007), (gy - 0.02, zk - 0.007), (gy - 0.02, zk + 0.007), (-gy + 0.02, zk + 0.007)],
              "x", 1, M["rim"], "GrilleSlat", off=0.008, cuts=2)
    iz = sp["intake"]["z"]
    iy = sp["intake"]["y"]
    patch(bvh, rounded([(-iy, iz[0]), (iy, iz[0]), (iy + 0.04, iz[1]), (-iy - 0.04, iz[1])], 0.04), "x", 1, M["trim"],
          "Intake", off=0.005)


def _shrink(pts, d):
    """Move a polygon's points d towards its centre (a simple inset)."""
    c = sum((Vector(p) for p in pts), Vector((0, 0))) / len(pts)
    return [tuple(Vector(p) + (c - Vector(p)).normalized() * d) for p in pts]


def build(kind):
    sp = SPECS[kind]
    M = F.mats(sp["paint"])
    M["gap"] = F.make_mat("ShutLine", (0.01, 0.01, 0.01), rough=0.9)
    M["clad"] = F.make_mat("Cladding", (0.03, 0.03, 0.032), rough=0.75)
    M["grille"] = M["trim"]
    body = body_mesh(sp)
    slots = ["paint", "gap", "clad"]
    for k in slots:
        body.data.materials.append(M[k])
    me = body.data
    # relax the surface (arc-length sampling leaves small ripples that show in reflections)
    sm = body.modifiers.new("Relax", 'LAPLACIANSMOOTH')
    sm.lambda_factor = 0.6
    sm.iterations = 6
    sm.use_volume_preserve = True
    sm.use_normalized = True
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier="Relax")
    for p in me.polygons:
        p.material_index = slots.index(zone(sp, p.center, p.normal))
    panels(sp, body, M)
    # wheel arches: cut, then a dark liner inside each
    cutters = []
    for ax in sp["axles"]:
        for s in (1, -1):
            cutters.append(F.arch_cut(body, ax, s * (sp["track"] + 0.15), sp["R"], sp["R"] + 0.045, depth=0.45))
            wy = cr(sp["half"], ax) - sp["track"]                  # body side, from the wheel centre
            lip = F.lathe("ArchLip", [(sp["R"] + 0.045, wy - 0.05), (sp["R"] + 0.06, wy - 0.012), (sp["R"] + 0.075, wy + 0.006),
                                      (sp["R"] + 0.095, wy - 0.004)], M[sp["lip"]], 40, arc=(-1.55, 1.55))
            lip.location = (ax, s * sp["track"], sp["R"])
            if s < 0:
                lip.rotation_euler = (0, 0, math.pi)
            ln = F.lathe("ArchLiner", [(sp["R"] + 0.06, -0.2), (sp["R"] + 0.06, 0.14)], M["under"], 32, arc=(-1.75, 1.75))
            ln.location = (ax, s * sp["track"], sp["R"])
            if s < 0:
                ln.rotation_euler = (0, 0, math.pi)
    _details(sp, M, kind)
    for s in (1, -1):
        for ax, nm in zip(sp["axles"], ("F", "R")):
            F.wheel("Wheel_%s%s" % (nm, "L" if s > 0 else "R"), (ax, s * sp["track"], sp["R"]), sp["R"], 0.19, M,
                    s > 0, spokes=5 if kind == "sedan" else 6, hub_cap=False)
    return cutters


def _details(sp, M, kind):
    hx = sp["L"] / 2
    g0 = sp["glass"][0]
    belt0 = cr(sp["belt"], g0 - 0.15)
    F.box("Underbody", (0, 0, 0.2), (sp["L"] - 0.6, 1.5, 0.05), M["under"], bev=0)
    for s in (1, -1):
        w = cr(sp["half"], g0 - 0.12)
        # door mirror: housing on a short arm at the base of the A pillar, glass facing back
        my = s * (w + 0.12)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=(g0 - 0.11, my, belt0 + 0.08))
        mh = bpy.context.active_object
        mh.name = "Mirror"
        mh.scale = (0.075, 0.125, 0.07)
        mh.data.materials.append(M["paint"])
        F.smooth(mh)
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1, depth=0.006, location=(g0 - 0.168, my, belt0 + 0.08),
                                            rotation=(0, math.pi / 2, 0))
        mg = bpy.context.active_object
        mg.name = "MirrorGlass"
        mg.scale = (0.055, 0.105, 1)
        mg.data.materials.append(M["chrome"])
        F.beam("MirrorArm", (g0 - 0.09, s * (w - 0.01), belt0 + 0.03), (g0 - 0.1, s * (w + 0.06), belt0 + 0.065), 0.05, 0.03, M["trim"])
        F.box("MirrorBlink", (g0 - 0.06, s * (w + 0.17), belt0 + 0.07), (0.015, 0.08, 0.014), M["amber"], bev=0)
        # flush door handles, a little below the belt
        for xh in (sp["doors"][0] - 0.25, sp["doors"][1] - 0.25):
            wh = cr(sp["half"], xh)
            F.box("Handle", (xh, s * (wh + 0.003), cr(sp["belt"], xh) - 0.1), (0.15, 0.02, 0.028), M["chrome"], bev=0.006)
        # side indicator on the front wing
        F.box("SideBlink", (hx - 0.62, s * (cr(sp["half"], hx - 0.62) + 0.002), 0.78), (0.06, 0.01, 0.02), M["amber"], bev=0)
    # wipers at the base of the windscreen
    F.beam("Wiper", (g0 - 0.06, -0.62, belt0 + 0.035), (g0 - 0.14, 0.02, belt0 + 0.07), 0.016, 0.014, M["black"])
    F.beam("Wiper", (g0 - 0.06, -0.05, belt0 + 0.035), (g0 - 0.14, 0.55, belt0 + 0.07), 0.016, 0.014, M["black"])
    # plates (white, black border, no numbers), lamp pods the game drives, antenna
    zf = 0.42
    F.box("PlateBorderF", (hx + 0.005, 0, zf), (0.008, 0.52, 0.13), M["black"], bev=0)
    F.box("PlateF", (hx + 0.012, 0, zf), (0.006, 0.5, 0.11), M["plate"], bev=0)
    zr = 0.62 if sp["tailgate"] else 0.66
    F.box("PlateBorderR", (-hx - 0.005, 0, zr), (0.008, 0.52, 0.13), M["black"], bev=0)
    F.box("PlateR", (-hx - 0.012, 0, zr), (0.006, 0.5, 0.11), M["plate"], bev=0)
    for s in (1, -1):
        F.cyl("FogBezel", (hx - 0.03, s * 0.62, 0.32), 0.045, 0.03, M["trim"], rot=(0, math.pi / 2, 0), verts=20)
        F.cyl("Fog", (hx - 0.012, s * 0.62, 0.32), 0.03, 0.02, M["lens"], rot=(0, math.pi / 2, 0), verts=16)
    roof_back = min(x for x, z in sp["top"] if z > max(zz for _, zz in sp["top"]) - 0.06)
    fin = F.box("Antenna", (roof_back + 0.12, 0, max(z for _, z in sp["top"]) + 0.045), (0.16, 0.045, 0.065), M["trim"], bev=0.02)
    fin.modifiers["Bevel"].segments = 4
    if sp["tailgate"]:
        # roof spoiler over the tailgate glass with a high brake light, rear wiper
        xs = sp["glass"][1] + 0.12
        zt = cr(sp["top"], xs)
        sp_ = F.box("Spoiler", (xs - 0.04, 0, zt + 0.02), (0.22, 1.2, 0.05), M["paint"], bev=0.02)
        sp_.rotation_euler = (0, math.radians(-8), 0)
        F.box("TailBar", (xs - 0.13, 0, zt + 0.0), (0.02, 0.3, 0.025), M["tail"], bev=0)
        F.beam("RearWiper", (-hx + 0.11, 0, cr(sp["top"], -hx + 0.11) + 0.12), (-hx + 0.18, 0.32, cr(sp["top"], -hx + 0.18) + 0.25),
               0.015, 0.015, M["black"])
    else:
        # small lip on the boot lid
        F.box("BootLip", (-hx + 0.1, 0, cr(sp["top"], -hx + 0.1) + 0.02), (0.08, 1.1, 0.03), M["paint"], bev=0.012)
    for s in (1, -1):                                              # rear bumper reflectors
        F.box("Reflector", (-hx + 0.02, s * 0.66, 0.4), (0.01, 0.12, 0.03), M["tail"], bev=0)
    F.cyl("Exhaust", (-hx + 0.08, 0.45, 0.24), 0.03, 0.14, M["chrome"], rot=(0, math.pi / 2, 0), verts=16)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(args[0] if args else "godot/assets/vehicles")
    kinds = args[1:] or list(SPECS.keys())
    os.makedirs(out_dir, exist_ok=True)
    for kind in kinds:
        F.reset()
        build(kind)
        F.finish(os.path.join(out_dir, "fleet_%s.glb" % kind))
