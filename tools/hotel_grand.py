"""
The Siruvani Grand, Avinashi Road (the story's five-star hotel: a hotel of its own, no real brand), as the city sees
it from the street: a stone podium with a glass lobby under a porte-cochère, the name and five stars lit on the
canopy, flagpoles (the national flag in the middle), and a ten-floor curtain-wall tower with stone fins and floor
bands, its name lit on the crown. Built on its lot (24 m along the road, 44 m deep): the origin is the lot's middle
at ground level, the front (the road side) towards -Y.

    Blender -b --factory-startup --python tools/hotel_grand.py -- [--preview DIR] [--no-export]

Writes godot/assets/landmarks/hotel_grand.glb; the city streamer puts it in place of the plain block on its lot
(godot/assets/landmarks/landmarks.json, city_streamer.gd LANDMARKS).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_rooms as R  # noqa: E402  (its box / cyl / text / mat helpers)

OUT = os.path.join(HERE, "..", "godot", "assets", "landmarks", "hotel_grand.glb")
W, D = 24.0, 44.0              # the lot
PODIUM_H, FLOOR_H, FLOORS = 9.0, 3.4, 10
GOLD = (1.0, 0.78, 0.35)


def star(c, r, m, depth=0.06, facing_y=-1.0):
    """A five-pointed star standing upright on a front face (facing -Y), r its outer radius."""
    bm = bmesh.new()
    pts = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.42
        pts.append(bm.verts.new((rr * math.cos(a), 0.0, rr * math.sin(a))))
    f = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, depth * facing_y, 0), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.translate(bm, vec=c, verts=bm.verts)
    me = bpy.data.meshes.new("Star")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    return R._link(bpy.data.objects.new("Star", me))


def flag(x, y, top, colours, chakra=False):
    """A flagpole with its flag flying towards +X: three bands top to bottom (the tricolour: the chakra on white)."""
    R.cyl((x, y, top / 2), 0.05, top, R.mat("pole_steel", (0.85, 0.85, 0.87), 0.25, 1.0), 12)
    R.cyl((x, y, top + 0.06), 0.08, 0.1, R.mat("brass", (0.8, 0.6, 0.25), 0.3, 1.0), 12)
    fw, fh = 1.8, 1.2
    for k, col in enumerate(colours):
        R.box((x + 0.06 + fw / 2, y, top - 0.15 - fh / 6 - k * fh / 3), (fw, 0.02, fh / 3),
              R.mat("flag_%d_%d_%d" % tuple(int(c * 99) for c in col), col, 0.85))
    if chakra:
        navy = R.mat("chakra_navy", (0.0, 0.0, 0.216), 0.6)          # navy #000080
        cz = top - 0.15 - fh / 2
        for s in (-1, 1):
            R.cyl((x + 0.06 + fw / 2, y + s * 0.012, cz), 0.17, 0.004, navy, 24, rot=(math.pi / 2, 0, 0))
            R.cyl((x + 0.06 + fw / 2, y + s * 0.015, cz), 0.145, 0.004, R.mat("flag_white", (0.97, 0.97, 0.95), 0.85), 24,
                  rot=(math.pi / 2, 0, 0))
            for k in range(12):                           # the 24 spokes, as 12 bars through the hub
                a = k * math.pi / 12
                R.box((x + 0.06 + fw / 2, y + s * 0.018, cz), (0.29, 0.004, 0.008), navy, rot=(0, a, 0))


def palm(x, y, h=4.0):
    R.cyl((x, y, h / 2), 0.14, h, R.mat("palm_trunk", (0.45, 0.38, 0.28), 0.9), 10, r2=0.1)
    for k in range(9):
        a = k * math.tau / 9
        R.box((x + 1.0 * math.cos(a), y + 1.0 * math.sin(a), h - 0.1), (0.35, 2.2, 0.02),
              R.mat("palm_frond", (0.18, 0.42, 0.12), 0.8), rot=(0.45, 0.0, a + math.pi / 2))


def build():
    stone = R.mat("hotel_stone", (0.78, 0.68, 0.53), 0.6)
    stone_dark = R.mat("hotel_stone_dark", (0.42, 0.34, 0.27), 0.5)
    glass = R.mat("hotel_glass", (0.16, 0.26, 0.3), 0.06, 0.85)
    lobby = R.mat("lobby_glass", (0.55, 0.42, 0.25), 0.1, 0.3, emit=(1.0, 0.75, 0.45), strength=0.9)
    bronze = R.mat("bronze", (0.35, 0.25, 0.15), 0.35, 0.8)
    granite = R.mat("forecourt_granite", (0.3, 0.29, 0.28), 0.35)
    gold = R.mat("gold_lit", GOLD, 0.3, 0.6, emit=GOLD, strength=3.0)
    down = R.mat("downlight", (1, 1, 1), 0.3, emit=(1.0, 0.9, 0.75), strength=6.0)
    y0 = -D / 2
    # the forecourt and the drop-off, a low granite wall either side of the drive with the name on it
    R.box((0, y0 + 5.0, 0.07), (W, 10.0, 0.14), granite)
    for s in (-1, 1):
        R.box((s * 10.3, y0 + 1.0, 0.6), (3.2, 0.6, 1.2), stone, 0.02)
        R.box((s * 10.3, y0 + 0.69, 0.75), (2.6, 0.02, 0.4), gold)
    # the podium: lobby glass along the front between stone piers, stone above
    py0 = y0 + 10.0
    R.box((0, py0 + (D - 10.0) / 2, PODIUM_H / 2), (W, D - 10.0, PODIUM_H), stone, 0.03)
    R.box((0, py0 - 0.02, 3.0), (W - 3.0, 0.06, 5.6), lobby)
    for k in range(9):
        x = -(W - 3.0) / 2 + k * (W - 3.0) / 8
        R.box((x, py0 - 0.08, 3.0), (0.12, 0.12, 5.6), bronze)
    for s in (-1, 1):
        R.box((s * (W / 2 - 0.75), py0 - 0.3, PODIUM_H / 2), (1.5, 0.6, PODIUM_H), stone_dark, 0.02)
    R.box((0, py0 - 0.1, 5.9), (W - 3.0, 0.3, 0.2), bronze)
    R.cyl((0, py0 - 0.9, 1.45), 1.3, 2.9, R.mat("revolving_glass", (0.6, 0.72, 0.75), 0.05, alpha=0.25), 32)
    R.cyl((0, py0 - 0.9, 2.95), 1.35, 0.15, bronze, 32)
    # the porte-cochere: a stone canopy on two bronze-clad columns, the name and five stars lit on its front
    cy = y0 + 5.5
    R.box((0, cy, 5.5), (16.0, 9.0, 0.7), stone, 0.04)
    R.box((0, cy - 4.52, 5.5), (16.0, 0.06, 0.7), stone_dark)
    for s in (-1, 1):
        R.cyl((s * 6.5, cy - 3.0, 2.6), 0.42, 5.2, bronze, 24)
    for gx in range(-3, 4):
        for gy in range(-1, 2):
            R.cyl((gx * 2.0, cy + gy * 2.5, 5.13), 0.18, 0.02, down, 16)
    R.text("THE SIRUVANI GRAND", (0, cy - 4.57, 5.62), 0.36, gold, "-y")
    for k in range(5):
        star((-1.0 + k * 0.5, cy - 4.58, 5.3), 0.11, gold)
    # flagpoles by the road: the national flag in the middle, the hotel's own either side
    for k, x in enumerate((-9.8, -8.4, -7.0)):
        if k == 1:
            flag(x, y0 + 0.6, 10.5, [(1.0, 0.318, 0.033), (0.95, 0.95, 0.93), (0.0065, 0.246, 0.0024)], chakra=True)
            # (India saffron #FF9933, white, India green #138808, as linear colours)
        else:                                             # the hotel's: ivory, its five stars in a row in maroon
            flag(x, y0 + 0.6, 9.5, [(0.95, 0.92, 0.82)] * 3)
            for j in range(5):
                star((x + 0.36 + j * 0.3, y0 + 0.58, 9.5 - 0.75), 0.1,
                     R.mat("flag_maroon", (0.45, 0.07, 0.1), 0.6), depth=0.01)
    for x in (8.0, 10.6):
        palm(x, y0 + 2.4)
    # the tower: a glass box, stone corner piers, stone bands at every floor, stone fins on the long faces
    tx, ty0, ty1 = 10.5, y0 + 14.0, D / 2 - 4.0
    tz0, tz1 = PODIUM_H, PODIUM_H + FLOORS * FLOOR_H
    th = tz1 - tz0
    R.box((0, (ty0 + ty1) / 2, tz0 + th / 2), (2 * tx - 0.4, ty1 - ty0 - 0.4, th), glass)
    for sx in (-1, 1):
        for sy in (ty0, ty1):
            R.box((sx * (tx - 0.6), sy + (0.6 if sy == ty0 else -0.6), tz0 + th / 2), (1.2, 1.2, th + 0.4), stone, 0.02)
    for f in range(FLOORS + 1):
        z = tz0 + f * FLOOR_H
        R.box((0, (ty0 + ty1) / 2, z), (2 * tx + 0.1, ty1 - ty0 + 0.1, 0.45), stone, 0.01)
    for k in range(1, 7):                                 # vertical fins on the front and back
        x = -tx + k * (2 * tx) / 7
        for sy, dy in ((ty0, -0.25), (ty1, 0.25)):
            R.box((x, sy + dy, tz0 + th / 2), (0.25, 0.5, th), stone)
    for k in range(1, 9):                                 # and on the sides
        y = ty0 + k * (ty1 - ty0) / 9
        for sx in (-1, 1):
            R.box((sx * (tx + 0.25), y, tz0 + th / 2), (0.5, 0.25, th), stone)
    # the crown: a stone parapet with a bronze frame, the name lit on the front
    R.box((0, (ty0 + ty1) / 2, tz1 + 1.6), (2 * tx + 0.6, ty1 - ty0 + 0.6, 3.2), stone_dark, 0.03)
    R.box((0, ty0 - 0.32, tz1 + 1.6), (2 * tx - 1.0, 0.06, 2.6), bronze)
    R.text("THE SIRUVANI GRAND", (0, ty0 - 0.37, tz1 + 1.25), 1.3, gold, "-y")
    for k in range(5):
        star((-2.4 + k * 1.2, ty0 - 0.38, tz1 + 2.55), 0.32, gold)
    # the podium roof in front of the tower: a terrace with planters and palms
    for x in (-8.5, -3.0, 3.0, 8.5):
        R.box((x, py0 + 1.5, PODIUM_H + 0.4), (3.0, 1.0, 0.8), stone_dark, 0.02)
        R.box((x, py0 + 1.5, PODIUM_H + 0.85), (2.8, 0.8, 0.1), R.mat("hedge", (0.12, 0.3, 0.1), 0.9))
    R.box((0, py0 + 0.2, PODIUM_H + 0.55), (W, 0.12, 1.1), R.mat("terrace_glass", (0.6, 0.72, 0.75), 0.05, alpha=0.3))


def export():
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "HotelGrand"
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    print("EXPORT", OUT, "%.1f MB, %d tris" % (os.path.getsize(OUT) / 1e6, sum(len(p.vertices) - 2 for p in ob.data.polygons)),
          flush=True)


def preview(out_dir):
    sc = bpy.context.scene
    engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960
    sc.render.image_settings.file_format = 'JPEG'
    sc.view_settings.view_transform = "Standard"
    R.box((0, -40, -0.05), (120, 120, 0.1), R.mat("road_asphalt", (0.25, 0.25, 0.26), 0.8))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.65, 0.78, 0.95, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = w
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for tag, loc, look, lens in (("street", (-14, -46, 1.7), (0, -10, 14), 20), ("approach", (8, -34, 1.7), (-2, -18, 4.5), 24),
                                 ("aerial", (-55, -80, 45), (0, 0, 15), 32)):
        cam.data.lens = lens
        cam.location = loc
        cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "hotel_grand_%s.jpg" % tag)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    R.reset()
    build()
    if "--no-export" not in args:
        export()
    if "--preview" in args:
        d = os.path.abspath(args[args.index("--preview") + 1])
        os.makedirs(d, exist_ok=True)
        preview(d)


if __name__ == "__main__":
    main()
