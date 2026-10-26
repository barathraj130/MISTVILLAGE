"""
Sketchfab street models made ready for the game (models in mapdata/sketchfab/props, credited in docs/DATA_SOURCES.md):
    auto   "Low Poly Autorickshaw aka TukTuk" (Nirmal.Justin, CC-BY) → godot/assets/vehicles/fleet_auto2.glb, laid out
           like tools/fleet.py's vehicles: +X the nose, a "Body", "Glass", "Headlight", "TailBar", and its three
           wheels under "Wheel_F" / "Wheel_RL" / "Wheel_RR" so they can spin; 2.7 m long like a real three-wheeler
    bhel   "Bhelpuri Shop" (AJ_AY, CC-BY) → godot/assets/city_props/life_bhel.glb, a snack cart for the street (+X
           along the street, -Y towards the road like tools/export_life.py's props); its boards came from a photo of
           a real shop, so they're repainted with a made-up name (SIGNS)

    Blender -b --factory-startup --python tools/sketchfab_vehicles.py -- [auto] [bhel] [--preview DIR] [--no-export]
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "props")
VEH = os.path.join(ROOT, "godot", "assets", "vehicles")
PROPS = os.path.join(ROOT, "godot", "assets", "city_props")
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(name):
    """Import a model, bake every mesh's transform in and drop the empties: plain meshes in Blender space."""
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.data.polygons and not o.hide_render
              and o.visible_get()]
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in meshes]:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.data.objects:
        if o.animation_data:
            o.animation_data.action = None
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for o in meshes:                                   # skinned ones as posed, not in their bind shape
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.clear()
        o.data = me
        o.data.transform(o.matrix_world)
    for o in [o for o in bpy.data.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    return meshes


def bounds(objs):
    vs = [v.co for o in objs for v in o.data.vertices]
    return (Vector([min(v[i] for v in vs) for i in range(3)]), Vector([max(v[i] for v in vs) for i in range(3)]))


def place(objs, m):
    for o in objs:
        o.data.transform(m)


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    return ob


def lamp_mat(name, colour, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1)
    b.inputs["Emission Color"].default_value = (*colour, 1)
    b.inputs["Emission Strength"].default_value = strength
    return m


def slab(name, centre, size, m):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + centre[0], v.co.y * size[1] + centre[1], v.co.z * size[2] + centre[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG')
    print("EXPORT", path, "%.1f MB" % (os.path.getsize(path) / 1e6), flush=True)


# ============================================================================ the auto
def auto():
    meshes = load("low_poly_autorickshaw_aka_tuktuk")
    lo, hi = bounds(meshes)
    # its nose is -Y: turn it to +X, stand it on the ground, 2.7 m long, centred
    k = 2.7 / (hi.y - lo.y)
    m = Matrix.Scale(k, 4) @ Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation(
        -Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)))
    place(meshes, m)
    # the wheels: the tyres and their hubs come as loose pieces of two meshes; split and sort them to the wheels
    wheel_src = [o for o in meshes if any(ms.material and ms.material.name == "tyre" for ms in o.material_slots)
                 and bounds([o])[1].z < 0.7]
    hubs = []
    for o in wheel_src:
        if bounds([o])[1].z < 0.7 and (bounds([o])[1] - bounds([o])[0]).x > 1.5:
            hubs.append(o)
    hubs += [o for o in meshes if o not in hubs and bounds([o])[1].z < 0.62 and (bounds([o])[1] - bounds([o])[0]).x > 1.8]
    parts = []
    for o in set(hubs):
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='LOOSE')
        bpy.ops.object.mode_set(mode='OBJECT')
        parts += list(bpy.context.selected_objects)
    lo, hi = bounds([o for o in bpy.data.objects if o.type == 'MESH'])
    wheels = {"Wheel_F": [], "Wheel_RL": [], "Wheel_RR": []}
    body = []
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        if o not in parts:
            body.append(o)
            continue
        a, b = bounds([o])
        c = (a + b) / 2
        if b.z > 0.62 or (b - a).length > 1.0:             # not a wheel piece (a mudguard, the chassis)
            body.append(o)
        elif c.x > 0.4:
            wheels["Wheel_F"].append(o)
        else:
            wheels["Wheel_RL" if c.y > 0 else "Wheel_RR"].append(o)
    for name, ps in wheels.items():
        if not ps:
            print("NO PIECES FOR", name, flush=True)
            continue
        w = join(ps, name + "_mesh")
        a, b = bounds([w])
        c = (a + b) / 2
        w.data.transform(Matrix.Translation(-c))
        e = bpy.data.objects.new(name, None)
        e.location = c
        bpy.context.scene.collection.objects.link(e)
        w.parent = e
        w.location = (0, 0, 0)
        print("WHEEL", name, "at %.2f %.2f %.2f, %d pieces" % (*c, len(ps)), flush=True)
    glass = [o for o in body if any(ms.material and ms.material.name == "glass" for ms in o.material_slots)]
    for o in glass:
        o.material_slots[0].material.name = "Glass"
    if glass:
        join(glass, "Glass")
    join([o for o in body if o not in glass], "Body")
    lo, hi = bounds([bpy.data.objects["Body"]])
    # lamps the game can switch: a headlight on the front, a red bar across the back
    slab("Headlight", (hi.x - 0.02, 0.0, 0.85), (0.04, 0.15, 0.12), lamp_mat("Headlight", (1.0, 0.97, 0.88), 3.0))
    slab("TailBar", (lo.x + 0.01, 0.0, 0.62), (0.03, 0.9, 0.05), lamp_mat("Taillight", (0.9, 0.05, 0.03), 2.0))
    print("AUTO size %.2f x %.2f x %.2f" % tuple(hi - lo), flush=True)


# ============================================================================ the snack cart
SIGNS = [   # the cart's painted boards (texture pixels, from the top left as the file stores it), and what they say now
    ((72, 3, 452, 122), "PANI PURI  *  MASALA PURI", (0.1, 0.2, 0.6)),     # (the low board)
    ((92, 312, 438, 358), "BHEL PURI CENTRE", (0.1, 0.45, 0.15)),
    ((80, 372, 452, 440), "SRI MURUGAN", (0.8, 0.08, 0.05)),               # (the top board)
]


def _text_image(words, w, h, colour):
    """The words rendered (Arial Bold, transparent background) into a w x h RGBA array, rows from the top."""
    main = bpy.context.scene
    sc = bpy.data.scenes.new("sign")
    bpy.context.window.scene = sc
    cu = bpy.data.curves.new("t", 'FONT')
    cu.body = words
    cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    ob = bpy.data.objects.new("t", cu)
    sc.collection.objects.link(ob)
    m = bpy.data.materials.new("ink")
    m.use_nodes = True
    em = m.node_tree.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*colour, 1)
    m.node_tree.links.new(em.outputs[0], m.node_tree.nodes["Material Output"].inputs[0])
    cu.materials.append(m)
    bpy.context.view_layer.update()
    tw = max(ob.dimensions.x, 0.01)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
    sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(tw * 1.12, ob.dimensions.y * 1.3 * w / h)
    cam.location = (0, 0, 5)
    sc.camera = cam
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = w * 2, h * 2
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    path = os.path.join(bpy.app.tempdir, "sign_%d.png" % len(bpy.data.images))
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True, scene=sc.name)
    im = bpy.data.images.load(path)
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h * 2, w * 2, 4)[::-1]     # rows from the top
    bpy.data.images.remove(im)
    bpy.context.window.scene = main
    bpy.data.scenes.remove(sc)
    return px[::2, ::2]


def _repaint_signs(im):
    """Plain cream boards with a coloured border and the cart's new name over the photographed shop's boards."""
    w, h = im.size
    px = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]          # rows from the top, as stored
    for (x0, y0, x1, y1), words, colour in SIGNS:
        px[y0:y1, x0:x1, :3] = colour
        px[y0 + 4:y1 - 4, x0 + 4:x1 - 4, :3] = (0.98, 0.95, 0.82)
        t = _text_image(words, x1 - x0 - 16, y1 - y0 - 12, colour)
        t = t[::-1]                                                              # the boards are stored upside down
        a = t[..., 3:4]
        region = px[y0 + 6:y1 - 6, x0 + 8:x1 - 8, :3]
        px[y0 + 6:y1 - 6, x0 + 8:x1 - 8, :3] = region * (1 - a) + t[..., :3] * a
    im.pixels.foreach_set(px[::-1].ravel())
    im.update()


def bhel():
    meshes = load("bhelpuri_shop_by_ajay_indian_local_shop")
    lo, hi = bounds(meshes)
    # 0.4 to metres (its wheels come out 0.6 m), standing on its origin, its long side along +X
    k = 0.4
    place(meshes, Matrix.Scale(k, 4) @ Matrix.Translation(-Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))))
    for o in meshes:
        for ms in o.material_slots:
            if ms.material and "Bhel_puri" in ms.material.name:
                for n in ms.material.node_tree.nodes:
                    if getattr(n, "image", None) is not None and not n.image.get("repainted"):
                        _repaint_signs(n.image)
                        n.image["repainted"] = True
            for n in (ms.material.node_tree.nodes if ms.material and ms.material.use_nodes else []):
                im = getattr(n, "image", None)
                if im is not None and max(im.size) > 1024:
                    im.scale(*(v // 2 for v in im.size))
    cart = join(meshes, "Cart")
    lo, hi = bounds([cart])
    print("BHEL size %.2f x %.2f x %.2f" % tuple(hi - lo), flush=True)


def preview(out):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 1280, 800
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = 'JPEG'
    lo, hi = bounds([o for o in bpy.data.objects if o.type == 'MESH'])
    c, size = (lo + hi) / 2, (hi - lo).length
    bpy.ops.mesh.primitive_plane_add(size=40, location=(c.x, c.y, 0))
    g = bpy.context.object
    gm = bpy.data.materials.new("road")
    gm.diffuse_color = (0.35, 0.35, 0.36, 1)
    g.data.materials.append(gm)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 40
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(45), 0, math.radians(30))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.78, 0.9, 1)
    sc.camera = cam
    for k, (ang, el) in enumerate(((35, 15), (-140, 20))):
        a = math.radians(ang)
        cam.location = c + Vector((math.cos(a), math.sin(a), 0)) * size * 1.3 + Vector((0, 0, size * math.sin(math.radians(el))))
        cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = out + "_%d.jpg" % k
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", sc.render.filepath, flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev = args[args.index("--preview") + 1] if "--preview" in args else None
    jobs = {"auto": (auto, os.path.join(VEH, "fleet_auto2.glb")), "bhel": (bhel, os.path.join(PROPS, "life_bhel.glb"))}
    for name in [a for a in args if a in jobs] or list(jobs):
        reset()
        jobs[name][0]()
        if "--no-export" not in args:
            export(jobs[name][1])
        if prev:
            os.makedirs(prev, exist_ok=True)
            preview(os.path.join(os.path.abspath(prev), name))


if __name__ == "__main__":
    main()
