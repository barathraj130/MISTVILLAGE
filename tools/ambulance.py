"""
The 108 ambulance (Tamil Nadu's emergency ambulance service: a public service, its real number): our own model of
the white high-roof van it runs, built here. A long white body with a raised roof, the cab's windscreen and side
windows, the patient cabin's frosted windows and its two rear doors, a red band down each side with "108" and
"AMBULANCE" (back to front on the bonnet, to be read in a mirror), a red cross on the sides and roof, the blue and
red light bar on the cab roof, the rear lights, black bumpers, four wheels. Standing on its origin, facing -Y (+Z in
the game, as the people), 5.3 m long.
    Blender -b --factory-startup --python tools/ambulance.py
Writes godot/assets/vehicles/ambulance.glb. The light bar's materials are "Light blue" / "Light red" (the game
flashes them: hospital.gd).
"""
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "vehicles", "ambulance.glb")
L, W, H = 5.3, 1.95, 2.45          # length, width, roof height
CAB = 1.55                          # the cab's length (from the front)


def mat(name, rgb, rough=0.5, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


M = {}


def box(name, size, at, m, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(M[m])
    if bevel:
        bv = o.modifiers.new("b", 'BEVEL')
        bv.width = bevel
        bv.segments = 3
        bpy.ops.object.modifier_apply(modifier=bv.name)
    return o


def text(body, size, at, rot, m, extrude=0.004):
    bpy.ops.object.text_add(location=at, rotation=rot)
    t = bpy.context.object
    t.data.body = body
    t.data.size = size
    t.data.align_x = 'CENTER'
    t.data.align_y = 'CENTER'
    t.data.extrude = extrude
    t.data.materials.append(M[m])
    bpy.ops.object.convert(target='MESH')
    return bpy.context.object


def cross(at, rot, s):
    a = box("cross_a", (s, 0.01, s * 0.32), at, "red")
    b = box("cross_b", (s * 0.32, 0.01, s), at, "red")
    for o in (a, b):
        o.rotation_euler = rot
    return [a, b]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M.update({"white": mat("Body white", (0.92, 0.92, 0.9), 0.35), "red": mat("Stripe red", (0.75, 0.04, 0.04), 0.4),
              "glass": mat("Glass", (0.05, 0.07, 0.09), 0.08, 0.3), "frost": mat("Frosted glass", (0.72, 0.76, 0.78), 0.3),
              "black": mat("Black trim", (0.03, 0.03, 0.03), 0.6), "tyre": mat("Tyre", (0.02, 0.02, 0.02), 0.9),
              "rim": mat("Rim", (0.55, 0.56, 0.58), 0.3, 0.8), "blue": mat("Light blue", (0.05, 0.25, 1.0), 0.2, 0, 3.0),
              "lred": mat("Light red", (1.0, 0.05, 0.03), 0.2, 0, 3.0), "tail": mat("Tail light", (0.6, 0.02, 0.02), 0.2, 0, 0.6),
              "head": mat("Head light", (1.0, 0.97, 0.9), 0.1, 0, 1.0)})
    y0 = -L / 2                                          # the front (it faces -Y)
    parts = []
    # the body: the patient box (tall) and the cab (lower roof, a sloped windscreen), the bonnet
    parts.append(box("box", (W, L - CAB - 0.05, H - 0.45), (0, y0 + CAB + (L - CAB) / 2 - 0.02, 0.45 + (H - 0.45) / 2), "white", 0.06))
    parts.append(box("cab", (W, CAB - 0.5, 1.55), (0, y0 + 0.5 + (CAB - 0.5) / 2, 0.45 + 0.78), "white", 0.08))
    parts.append(box("bonnet", (W - 0.04, 0.62, 0.62), (0, y0 + 0.31, 0.45 + 0.31), "white", 0.1))
    ws = box("windscreen", (W - 0.2, 0.05, 0.78), (0, y0 + 0.62, 1.45), "glass")
    ws.rotation_euler = (math.radians(-28), 0, 0)
    parts.append(ws)
    for sx in (-1, 1):
        parts.append(box("cabwin", (0.02, 0.62, 0.55), (sx * (W / 2 + 0.005), y0 + 0.95, 1.5), "glass"))
        parts.append(box("frost1", (0.02, 0.85, 0.42), (sx * (W / 2 + 0.005), y0 + CAB + 0.75, 1.75), "frost"))
        parts.append(box("frost2", (0.02, 0.85, 0.42), (sx * (W / 2 + 0.005), y0 + CAB + 1.95, 1.75), "frost"))
        parts.append(box("band", (0.015, L - 0.7, 0.3), (sx * (W / 2 + 0.008), y0 + 0.35 + (L - 0.7) / 2, 1.1), "red"))
        t = text("108", 0.42, (sx * (W / 2 + 0.02), y0 + CAB + 1.1, 1.1), (math.radians(90), 0, math.radians(-90 * sx)), "white")
        parts.append(t)
        t = text("AMBULANCE", 0.2, (sx * (W / 2 + 0.02), y0 + CAB + 2.35, 1.1), (math.radians(90), 0, math.radians(-90 * sx)), "white")
        parts.append(t)
        cs = cross((sx * (W / 2 + 0.012), y0 + CAB + 2.35, 1.85), (0, 0, math.radians(90)), 0.42)
        parts += cs
        # the wheels
        for wy in (y0 + 0.85, y0 + L - 1.0):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.36, depth=0.24, location=(sx * (W / 2 - 0.1), wy, 0.36),
                                                rotation=(0, math.radians(90), 0))
            ty = bpy.context.object
            ty.data.materials.append(M["tyre"])
            parts.append(ty)
            bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.02, location=(sx * (W / 2 + 0.025), wy, 0.36),
                                                rotation=(0, math.radians(90), 0))
            rm = bpy.context.object
            rm.data.materials.append(M["rim"])
            parts.append(rm)
            parts.append(box("arch", (0.06, 0.9, 0.1), (sx * (W / 2 + 0.01), wy, 0.76), "black"))
        parts.append(box("headlamp", (0.36, 0.03, 0.16), (sx * 0.62, y0 - 0.005, 0.85), "head"))
        parts.append(box("taillamp", (0.16, 0.03, 0.42), (sx * (W / 2 - 0.12), y0 + L + 0.005, 1.0), "tail"))
    # the front: grille, bumper, "AMBULANCE" back to front over the grille; the back: two doors, the bumper
    parts.append(box("grille", (W * 0.55, 0.02, 0.22), (0, y0 - 0.005, 0.68), "black"))
    parts.append(box("bumper_f", (W + 0.04, 0.14, 0.2), (0, y0 - 0.03, 0.42), "black", 0.03))
    t = text("AMBULANCE", 0.17, (0, y0 - 0.012, 1.0), (math.radians(90), 0, 0), "red")
    t.scale.x = -1                                      # (read in a mirror)
    parts.append(t)
    parts.append(box("bumper_r", (W + 0.04, 0.14, 0.2), (0, y0 + L + 0.03, 0.42), "black", 0.03))
    parts.append(box("door_line", (0.02, 0.01, H - 0.75), (0, y0 + L + 0.008, 0.45 + (H - 0.45) / 2), "black"))
    for sx in (-1, 1):
        parts.append(box("rearwin", (0.6, 0.02, 0.45), (sx * 0.45, y0 + L + 0.006, 1.85), "frost"))
    parts += cross((0, y0 + L + 0.01, 1.25), (0, 0, 0), 0.4)
    parts += cross((0, y0 + CAB + 1.6, H + 0.006), (math.radians(90), 0, 0), 0.7)
    # the light bar on the cab roof: blue and red, and two at the back
    parts.append(box("bar", (W - 0.4, 0.32, 0.08), (0, y0 + 0.75, 2.05), "black"))
    for sx, m in ((-1, "blue"), (1, "lred")):
        parts.append(box("lamp", (0.55, 0.26, 0.13), (sx * 0.36, y0 + 0.75, 2.14), m, 0.02))
        parts.append(box("lamp_r", (0.24, 0.08, 0.13), (sx * 0.6, y0 + L - 0.05, H + 0.07), m, 0.02))
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    amb = bpy.context.object
    amb.name = amb.data.name = "ambulance"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True)
    print("AMBULANCE wrote", OUT, sum(len(p.vertices) - 2 for p in amb.data.polygons), "tris", flush=True)


if __name__ == "__main__":
    main()
