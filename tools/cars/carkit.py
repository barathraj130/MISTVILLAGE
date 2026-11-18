"""The car kit: what every one of our own vehicles is built from (docs/VEHICLE_AUDIT_2026-11-17.md, the overhaul).

  - materials(): one PBR library, named the way the game finds them (Paint, Glass, Headlight, Taillight, Brake,
    Indicator_L / Indicator_R, Reverse...): car paint with a clear coat, glass that's see-through, chrome, gloss
    and grained plastics, tyre rubber, alloy, lenses, fabric, carpet; their small detail textures (plastic grain,
    fabric weave, tread) made here as images, so they travel inside the .glb
  - loft(): a smooth body surface swept through cross-sections (rings of points, nose to tail, mirrored)
  - wheel(): a tyre with a shaped sidewall and tread, an alloy rim, hub, brake disc and caliper, under a
    Wheel_<FL|FR|RL|RR> empty at its centre (jeep.gd spins and steers those)
  - plate(): an Indian number plate (white, black letters) with a made-up registration
  - previews(): studio-lit renders from round the car, to judge it by

Blender's frame: +X the nose, +Y the car's left, Z up, the floor at z 0, metres (as tools/fleet.py: the game loads
them alike). Right-hand drive: the driver sits on the car's right (-Y).
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

STUDIO = "/Applications/Blender.app/Contents/Resources/5.2/datafiles/studiolights/world/"


# ----------------------------------------------------------------------------------------------------- materials
def _img(name, size, fn):
    """An image made from fn(x, y) → (r, g, b) arrays in 0..1 (x, y in 0..1 grids), packed into the file."""
    if name in bpy.data.images:
        return bpy.data.images[name]
    img = bpy.data.images.new(name, size, size, alpha=False)
    yy, xx = np.mgrid[0:size, 0:size] / float(size)
    r, g, b = fn(xx, yy)
    px = np.ones((size, size, 4), dtype=np.float32)
    px[:, :, 0], px[:, :, 1], px[:, :, 2] = r, g, b
    img.pixels[:] = px.ravel()
    img.pack()
    return img


def _noise(size, scale, seed):
    """Smooth value noise in 0..1, tileable, size × size."""
    rng = np.random.default_rng(seed)
    n = max(2, int(size / scale))
    g = rng.random((n, n))
    yy, xx = np.mgrid[0:size, 0:size] * (n / float(size))
    x0 = np.floor(xx).astype(int) % n
    y0 = np.floor(yy).astype(int) % n
    fx, fy = xx - np.floor(xx), yy - np.floor(yy)
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, (x0 + 1) % n] * fx
    b = g[(y0 + 1) % n, x0] * (1 - fx) + g[(y0 + 1) % n, (x0 + 1) % n] * fx
    return a * (1 - fy) + b * fy


def _normal_from_height(h, strength):
    gy, gx = np.gradient(h)
    nx, ny = -gx * strength, -gy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx / ln) * 0.5 + 0.5, (ny / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5


def _normal_img(name, size, height_fn, strength):
    if name in bpy.data.images:
        return bpy.data.images[name]
    h = height_fn(size)
    r, g, b = _normal_from_height(h, strength)
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.colorspace_settings.name = 'Non-Color'
    px = np.ones((size, size, 4), dtype=np.float32)
    px[:, :, 0], px[:, :, 1], px[:, :, 2] = r, g, b
    img.pixels[:] = px.ravel()
    img.pack()
    return img


def _mat(name, color, metal=0.0, rough=0.5, coat=0.0, coat_rough=0.03, alpha=1.0, emit=None, emit_k=0.0,
         normal=None, normal_k=1.0, ior=1.45, uv_scale=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(p.outputs[0], out.inputs[0])
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["IOR"].default_value = ior
    if coat > 0.0:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = coat_rough
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND' if hasattr(m, "blend_method") else m.blend_method
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    if emit is not None:
        p.inputs["Emission Color"].default_value = (*emit, 1.0)
        p.inputs["Emission Strength"].default_value = emit_k
    if normal is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = normal
        if uv_scale != 1.0:
            mp = nt.nodes.new("ShaderNodeMapping")
            tc = nt.nodes.new("ShaderNodeTexCoord")
            mp.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
            nt.links.new(tc.outputs["UV"], mp.inputs[0])
            nt.links.new(mp.outputs[0], tex.inputs[0])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_k
        nt.links.new(tex.outputs[0], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], p.inputs["Normal"])
    return m


def materials(paint=(0.3, 0.012, 0.01)):
    """The library (names are what the game looks for)."""
    grain = _normal_img("tex_plastic_grain", 256, lambda s: _noise(s, 3, 1) * 0.6 + _noise(s, 9, 2) * 0.4, 2.5)
    weave = _normal_img("tex_fabric_weave", 256,
                        lambda s: (np.sin(np.mgrid[0:s, 0:s][1] * 0.9) * np.sin(np.mgrid[0:s, 0:s][0] * 0.9)) * 0.5 + _noise(s, 4, 3) * 0.3, 1.8)
    carpet = _normal_img("tex_carpet", 256, lambda s: _noise(s, 1.5, 4), 3.0)
    flake = _normal_img("tex_paint_flake", 256, lambda s: _noise(s, 1.2, 5), 0.25)
    M = {
        # body paint: a metallic base under a clear coat (KHR_materials_clearcoat; jeep.gd recolours "Paint")
        "Paint": _mat("Paint", paint, metal=0.3, rough=0.4, coat=1.0, coat_rough=0.03, normal=flake, normal_k=0.12, uv_scale=6.0),
        "Glass": _mat("Glass", (0.05, 0.07, 0.08), rough=0.03, alpha=0.22, ior=1.52),
        "GlassTint": _mat("GlassTint", (0.02, 0.025, 0.03), rough=0.03, alpha=0.5, ior=1.52),
        "Chrome": _mat("Chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.06),
        "BlackGloss": _mat("BlackGloss", (0.015, 0.015, 0.017), rough=0.12, coat=0.6),
        "BlackTrim": _mat("BlackTrim", (0.03, 0.03, 0.032), rough=0.6, normal=grain, normal_k=0.5, uv_scale=8.0),
        "Rubber": _mat("Rubber", (0.025, 0.025, 0.027), rough=0.85),
        "Tyre": _mat("Tyre", (0.03, 0.03, 0.032), rough=0.78),
        "Alloy": _mat("Alloy", (0.72, 0.73, 0.75), metal=1.0, rough=0.28),
        "AlloyDark": _mat("AlloyDark", (0.2, 0.21, 0.22), metal=1.0, rough=0.35),
        "Disc": _mat("Disc", (0.45, 0.45, 0.46), metal=1.0, rough=0.45),
        "Caliper": _mat("Caliper", (0.15, 0.15, 0.16), metal=0.3, rough=0.5),
        "Lens": _mat("Lens", (0.9, 0.92, 0.95), rough=0.02, alpha=0.18, ior=1.49),
        "Reflector": _mat("Reflector", (0.85, 0.86, 0.88), metal=1.0, rough=0.12),
        "Headlight": _mat("Headlight", (0.95, 0.96, 1.0), rough=0.1, emit=(1.0, 0.98, 0.92), emit_k=0.0),
        "DRL": _mat("DRL", (0.95, 0.96, 1.0), rough=0.1, emit=(0.9, 0.95, 1.0), emit_k=2.0),
        "Taillight": _mat("Taillight", (0.45, 0.02, 0.02), rough=0.15, emit=(1.0, 0.05, 0.03), emit_k=0.4),
        "Brake": _mat("Brake", (0.5, 0.02, 0.02), rough=0.15, emit=(1.0, 0.04, 0.02), emit_k=0.0),
        "Indicator": _mat("Indicator", (0.85, 0.45, 0.05), rough=0.15, emit=(1.0, 0.5, 0.02), emit_k=0.0),
        "Reverse": _mat("Reverse", (0.9, 0.9, 0.9), rough=0.15, emit=(1.0, 1.0, 1.0), emit_k=0.0),
        "PlateWhite": _mat("PlateWhite", (0.88, 0.88, 0.86), rough=0.4),
        "PlateText": _mat("PlateText", (0.02, 0.02, 0.02), rough=0.5),
        # the interior
        "Dash": _mat("Dash", (0.05, 0.05, 0.055), rough=0.75, normal=grain, normal_k=0.6, uv_scale=10.0),
        "DashLight": _mat("DashLight", (0.55, 0.52, 0.47), rough=0.7, normal=grain, normal_k=0.4, uv_scale=10.0),
        "Fabric": _mat("Fabric", (0.12, 0.12, 0.13), rough=0.95, normal=weave, normal_k=0.8, uv_scale=14.0),
        "FabricLight": _mat("FabricLight", (0.42, 0.38, 0.33), rough=0.95, normal=weave, normal_k=0.8, uv_scale=14.0),
        "Carpet": _mat("Carpet", (0.04, 0.04, 0.045), rough=1.0, normal=carpet, normal_k=1.0, uv_scale=12.0),
        "Headliner": _mat("Headliner", (0.62, 0.6, 0.56), rough=0.95, normal=weave, normal_k=0.3, uv_scale=20.0),
        "Screen": _mat("Screen", (0.01, 0.015, 0.02), rough=0.05, emit=(0.1, 0.25, 0.4), emit_k=0.3),
        "Gauge": _mat("Gauge", (0.02, 0.02, 0.025), rough=0.4, emit=(0.95, 0.95, 1.0), emit_k=0.15),
        "Steel": _mat("Steel", (0.5, 0.5, 0.52), metal=1.0, rough=0.4),
    }
    return M


# ----------------------------------------------------------------------------------------------------- geometry
def cr(keys, x):
    """Catmull-Rom through (x, value) keys (any order), at x (clamped to the ends)."""
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
    """n points evenly spaced by arc length along a polyline of 2D points."""
    pts = [Vector(p) for p in pts]
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    out = []
    for k in range(n):
        s = d[-1] * k / (n - 1)
        for i in range(len(d) - 1):
            if d[i] <= s <= d[i + 1] or i == len(d) - 2:
                t = 0.0 if d[i + 1] == d[i] else (s - d[i]) / (d[i + 1] - d[i])
                out.append(pts[i].lerp(pts[i + 1], min(max(t, 0.0), 1.0)))
                break
    return out


def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_obj(name, bm, mats=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    link(ob)
    for m in (mats or []):
        me.materials.append(m)
    return ob


def smooth(ob, angle=40.0, weighted=True):
    """Smooth shading with sharp edges past `angle`, and weighted normals (flat panels stay flat)."""
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        pass
    if weighted:
        mod = ob.modifiers.new("WN", 'WEIGHTED_NORMAL')
        mod.keep_sharp = True


def apply_mods(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as e:
            print("CARKIT modifier", m.name, e)


def boolean(ob, cutter, op='DIFFERENCE', apply=True):
    """A boolean, applied. The exact solver sometimes loses the whole mesh on a thin cutter (a shut line): if a
    difference takes more than 40% of the faces, the mesh is put back and the fast solver tried; if that loses them
    too (then the float one), the cut is skipped (and said so)."""
    n0 = len(ob.data.polygons)
    keep = ob.data.copy()
    for solver in ('EXACT', 'MANIFOLD', 'FLOAT'):
        mod = ob.modifiers.new("B", 'BOOLEAN')
        mod.operation = op
        mod.object = cutter
        mod.solver = solver
        if not apply:
            return
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
        n1 = len(ob.data.polygons)
        if op != 'DIFFERENCE' or n1 > n0 * 0.6:
            print("CARKIT boolean %s (%s): %d -> %d faces" % (cutter.name, solver, n0, n1), flush=True)
            bpy.data.meshes.remove(keep)
            return
        old = ob.data
        ob.data = keep.copy()
        bpy.data.meshes.remove(old)
        print("CARKIT boolean %s (%s) lost the mesh (%d -> %d): put back" % (cutter.name, solver, n0, n1), flush=True)
    print("CARKIT boolean %s skipped" % cutter.name, flush=True)
    bpy.data.meshes.remove(keep)


def remove(ob):
    bpy.data.objects.remove(ob, do_unlink=True)


def lathe(name, profile, segs, axis='Y', mats=None, mat_of=None):
    """A solid of revolution: profile [(r, a)] (radius, position along the axis), round the axis."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        t = 2 * math.pi * i / segs
        c, s = math.cos(t), math.sin(t)
        ring = []
        for r, a in profile:
            if axis == 'Y':
                ring.append(bm.verts.new((r * c, a, r * s)))
            else:
                ring.append(bm.verts.new((a, r * c, r * s)))
        rings.append(ring)
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for j in range(len(profile) - 1):
            f = bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
            if mat_of:
                f.material_index = mat_of(j)
    return mesh_obj(name, bm, mats)


# ----------------------------------------------------------------------------------------------------- wheels
def wheel(M, name, at, R, width, rim_d, spokes=5, left=True, steer=False):
    """One wheel at `at` (its centre), facing out to the car's left (left=True) or right: the tyre (a shaped
    sidewall, a rounded shoulder, a tread of blocks and grooves), the alloy rim (a dished face of spokes, a barrel),
    the centre cap, the brake disc and its caliper (fixed: not spinning, parented to the empty's parent)."""
    piv = bpy.data.objects.new(name, None)
    pn = name.replace("Wheel_", "W")                          # (its parts: only the pivot is named Wheel_*)
    link(piv)
    piv.location = at
    side = 1.0 if left else -1.0
    hw = width / 2
    rr = rim_d / 2
    # tyre: a profile round the axle (r, y across the tread), the bead at the rim
    prof = [(rr - 0.005, -hw * 0.82), (rr + 0.012, -hw * 0.95), (rr + 0.05, -hw * 1.0), (R - 0.045, -hw * 1.02),
            (R - 0.018, -hw * 0.94), (R - 0.004, -hw * 0.78), (R, -hw * 0.5), (R, 0.0), (R, hw * 0.5), (R - 0.004, hw * 0.78),
            (R - 0.018, hw * 0.94), (R - 0.045, hw * 1.02), (rr + 0.05, hw * 1.0), (rr + 0.012, hw * 0.95), (rr - 0.005, hw * 0.82)]
    tyre = lathe(pn + "_Tyre", prof, 96, 'Y', [M["Tyre"]])
    # the tread: grooves round it and across it (a boolean of thin rings and blocks would be heavy: the tread
    # surface's vertices are pushed in where a groove runs)
    me = tyre.data
    for v in me.vertices:
        r = math.hypot(v.co.x, v.co.z)
        if r > R - 0.006:
            ang = math.atan2(v.co.z, v.co.x)
            y = v.co.y / hw
            groove = (abs(y) < 0.06) or (0.42 < abs(y) < 0.5)
            block = math.sin(ang * 48.0 + (0.6 if y > 0 else 0.0)) > 0.82 and abs(y) > 0.5
            if groove or block:
                k = (R - 0.008) / r
                v.co.x *= k
                v.co.z *= k
    smooth(tyre, 50)
    tyre.parent = piv
    # rim: the barrel, then a dished face of spokes (each spoke a tapered box from the hub to the rim's lip)
    barrel = lathe(pn + "_Barrel", [(rr - 0.012, -hw * 0.86), (rr, -hw * 0.78), (rr, hw * 0.7), (rr - 0.02, hw * 0.78),
                                      (rr - 0.03, hw * 0.6)], 64, 'Y', [M["Alloy"]])
    smooth(barrel, 50)
    barrel.parent = piv
    bm = bmesh.new()
    face_y = hw * 0.62
    for k in range(spokes * 2):                              # (double spokes: pairs)
        a0 = 2 * math.pi * (k // 2) / spokes + (0.11 if k % 2 else -0.11)
        for (ra, wa, ya), (rb, wb, yb) in [((0.065, 0.022, face_y - 0.02), (rr - 0.01, 0.014, face_y + 0.008))]:
            ca, sa = math.cos(a0), math.sin(a0)
            px, pz = -sa, ca
            pts = []
            for r, w, y in ((ra, wa, ya), (rb, wb, yb)):
                for s in (-1, 1):
                    for d in (-0.012, 0.0):
                        pts.append(bm.verts.new((ca * r + px * w * s, y + d, sa * r + pz * w * s)))
            # (8 verts: a, b ends × 2 sides × 2 depths) → a box
            idx = [(0, 2, 6, 4), (1, 5, 7, 3), (0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6)]
            for q in idx:
                try:
                    bm.faces.new([pts[i] for i in q])
                except ValueError:
                    pass
    sp_ob = mesh_obj(pn + "_Spokes", bm, [M["Alloy"]])
    bev = sp_ob.modifiers.new("Bv", 'BEVEL')
    bev.width = 0.004
    bev.segments = 2
    smooth(sp_ob, 35)
    sp_ob.parent = piv
    hub = lathe(pn + "_Hub", [(0.0, face_y + 0.012), (0.04, face_y + 0.012), (0.075, face_y - 0.005), (0.075, face_y - 0.03),
                                (0.09, face_y - 0.04)], 48, 'Y', [M["AlloyDark"]])
    smooth(hub, 50)
    hub.parent = piv
    cap = lathe(pn + "_Cap", [(0.0, face_y + 0.02), (0.03, face_y + 0.018), (0.034, face_y + 0.008)], 32, 'Y', [M["Chrome"]])
    smooth(cap, 60)
    cap.parent = piv
    for ob in (tyre, barrel, sp_ob, hub, cap):              # (built facing +Y: the left side's way out)
        if not left:
            ob.matrix_basis = Matrix.Scale(-1, 4, Vector((0, 1, 0))) @ ob.matrix_basis
    # the disc and caliper, inside the rim; they don't spin (put on the car, not the wheel)
    disc = lathe(pn + "_Disc", [(0.07, 0.0), (rr - 0.04, 0.0), (rr - 0.04, 0.022), (0.07, 0.022)], 48, 'Y', [M["Disc"]])
    disc.location = Vector(at) + Vector((0, -side * 0.035, 0))
    cal = bpy.data.objects.new(pn + "_Caliper", bpy.data.meshes.new(pn + "_Caliper"))
    link(cal)
    bmc = bmesh.new()
    bmesh.ops.create_cube(bmc, size=1.0)
    bmc.to_mesh(cal.data)
    bmc.free()
    cal.data.materials.append(M["Caliper"])
    cal.scale = (0.075, 0.05, 0.095)
    cal.location = Vector(at) + Vector((-0.11 if steer else -0.1, -side * 0.03, 0.06))
    bv = cal.modifiers.new("Bv", 'BEVEL')
    bv.width = 0.01
    bv.segments = 2
    return piv, [disc, cal]


# ----------------------------------------------------------------------------------------------------- plates
def plate(M, name, text, at, facing, w=0.5, h=0.12):
    """An Indian number plate: white, a thin black border, the registration in black (a made-up one)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = mesh_obj(name, bm, [M["PlateWhite"]])
    ob.scale = (0.012, w, h) if abs(facing.x) > 0.5 else (w, 0.012, h)       # (a unit cube: the scale is its size)
    ob.location = at
    bpy.ops.object.select_all(action='DESELECT')
    cu = bpy.data.curves.new(name + "_T", 'FONT')
    cu.body = text
    cu.size = h * 0.62
    cu.extrude = 0.0015
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    tx = bpy.data.objects.new(name + "_Text", cu)
    link(tx)
    tx.data.materials.append(M["PlateText"])
    rot = math.atan2(facing.y, facing.x)
    tx.rotation_euler = (math.pi / 2, 0, rot + math.pi / 2)
    tx.location = Vector(at) + facing * 0.0075
    bpy.context.view_layer.update()
    # (to a mesh: the game takes meshes)
    bpy.ops.object.select_all(action='DESELECT')
    tx.select_set(True)
    bpy.context.view_layer.objects.active = tx
    bpy.ops.object.convert(target='MESH')
    w_dim = tx.dimensions.x
    if w_dim > w * 0.86:
        k = w * 0.86 / w_dim
        tx.scale = (k, k, k)
    return ob, tx


# ----------------------------------------------------------------------------------------------------- previews
def previews(out_prefix, target=Vector((0, 0, 0.7)), dist=6.2, views=None, res=(1280, 720), world="city.exr", sun_k=3.0):
    """Renders from round the car under an outdoor HDRI (Eevee), to judge the model by: <prefix>_<view>.png."""
    sc = bpy.context.scene
    engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("PreviewWorld")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(STUDIO + world)
    bg = nt.nodes["Background"]
    nt.links.new(env.outputs[0], bg.inputs[0])
    if "PreviewFloor" not in bpy.data.objects:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
        fl = mesh_obj("PreviewFloor", bm, [_mat("PreviewAsphalt", (0.09, 0.09, 0.095), rough=0.85)])
    sun = bpy.data.objects.get("PreviewSun") or link(bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN')))
    sun.data.energy = sun_k
    bg.inputs["Strength"].default_value = 1.2 if sun_k > 0.5 else 0.35
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(42), 0, math.radians(35))
    cam = bpy.data.objects.get("PreviewCam") or link(bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam")))
    cam.data.lens = 50
    sc.camera = cam
    views = views or {"front34": (35, 14), "rear34": (150, 12), "side": (90, 4), "front": (0, 6), "rear": (180, 6), "top34": (60, 40)}
    out = []
    eye = bpy.data.objects.get("Eye")
    if eye is not None and os.environ.get("CARKIT_INSIDE"):     # (and from the driver's seat, looking ahead)
        cam.location = eye.matrix_world.translation
        cam.rotation_euler = Vector((1, 0, -0.08)).to_track_quat('-Z', 'Y').to_euler()
        cam.data.lens = 22
        sc.render.filepath = "%s_seat.png" % out_prefix
        bpy.ops.render.render(write_still=True)
        cam.location = eye.matrix_world.translation + Vector((-0.75, 0.35, 0.05))
        cam.rotation_euler = (Vector((0.4, -0.25, 0.85)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = "%s_cabin.png" % out_prefix
        bpy.ops.render.render(write_still=True)
        cam.data.lens = 50
    out = []
    ortho = os.environ.get("CARKIT_ORTHO")                       # (front, side, rear square on: orthographic)
    if ortho:
        views = dict(views)
        views.update({"o_side": (90, 0), "o_front": (0, 0), "o_rear": (180, 0)})
    for nm, (az, el) in views.items():
        a, e = math.radians(az), math.radians(el)
        cam.data.type = 'ORTHO' if nm.startswith("o_") else 'PERSP'
        cam.data.ortho_scale = 6.0 if nm == "o_side" else 2.8
        cam.location = target + Vector((math.cos(a) * math.cos(e), -math.sin(a) * math.cos(e), math.sin(e))) * dist
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = "%s_%s.png" % (out_prefix, nm)
        bpy.ops.render.render(write_still=True)
        out.append(sc.render.filepath)
    return out
