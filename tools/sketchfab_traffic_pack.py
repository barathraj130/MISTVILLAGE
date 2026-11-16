"""The Sketchfab vehicle pack (CC-BY 4.0: "Bus Simulator India - Traffic Cars" by Villanueva-Jonatan-32621, credited
in docs/DATA_SOURCES.md) split into one game model per vehicle, the way jeep.gd reads a vehicle:

  - the nose along +X (the pack's fronts face -Y), centred, its floor at z 0
  - its wheels named Wheel_FL / Wheel_FR / Wheel_RL / Wheel_RR (a three-wheeler Wheel_F; a bike Wheel_F, Wheel_R;
    a lorry's twin rear axles Wheel_RL2 / Wheel_RR2), each pivoting at its own centre
  - its lamps: the pack's Light_* nodes kept by their own names (the game lights them: head, tail, indicators)

Each goes to godot/assets/vehicles/sf_<name>.glb, and what the game needs to make it a vehicle you can get into
(size, wheels, lamps, the driver's seat) to godot/assets/vehicles/sf_fleet.json.

    Blender -b --factory-startup --python tools/sketchfab_traffic_pack.py
"""
import json
import math
import os

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
SRC = os.path.join(ROOT, "mapdata", "sketchfab", "vehicles", "traffic_pack", "scene.gltf")
OUT = os.path.join(ROOT, "godot", "assets", "vehicles")
# the vehicles taken (the pack's two SUVs whose wheels have no names are left out) and what each is in the game
TAKE = {
    "Hatchback_01": "hatchback", "Hatchback_02": "hatchback", "Hatchback_03": "hatchback", "Hatchback_04": "hatchback",
    "Luxury_01": "sedan", "Luxury_02": "sedan", "Luxury_03": "sedan", "Luxury_04": "sedan",
    "SUV_01": "suv", "SUV_04": "suv", "EV_01": "hatchback", "EV_02": "hatchback",
    "Emergency_01": "van", "Emergency_02": "van", "Emergency_03": "van",
    "Bus_01": "bus", "Bus_02": "bus", "Bus_03": "bus",
    "Truck_01": "lorry", "Truck_02": "lorry", "Truck_03": "lorry",
    "Rickshaw_01": "auto", "Rickshaw_02": "auto", "Rickshaw_03": "auto", "Rickshaw_04": "auto",
    "Motorbike_01": "bike", "Motorbike_02": "bike", "Motorbike_03": "bike",
}


def bounds(obs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in obs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def wheel_role(name):
    """F/R and L/R from a pack wheel's name (Front/Back/Rear, _L/_R), or None if it isn't a wheel."""
    n = name.lower()
    if "wheel" not in n and not n.endswith(("_front", "_rear", "_front_l", "_front_r", "_rear_l", "_rear_r")) \
            and "front_l" not in n and "front_r" not in n and "rear_l" not in n and "rear_r" not in n:
        return None
    if "light" in n:
        return None
    fr = "F" if "front" in n else ("R" if ("rear" in n or "back" in n) else None)
    if fr is None:
        return None
    side = ""
    if n.rstrip("0123456789_").endswith("_l") or "_l_" in n or n.endswith("_l"):
        side = "L"
    elif n.rstrip("0123456789_").endswith("_r") or "_r_" in n or n.endswith("_r"):
        side = "R"
    return fr + side


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    bpy.context.view_layer.update()
    fleet = {}
    for key, kind in TAKE.items():
        root = bpy.data.objects.get("IN_" + key)
        if root is None:
            print("SFV missing", key)
            continue
        obs = [root] + list(root.children_recursive)
        lo, hi = bounds(obs)
        centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        # to the game's frame: centred, floor at 0, the nose (the pack's -Y) to +X
        to = Matrix.Rotation(math.radians(90.0), 4, 'Z') @ Matrix.Translation(-centre)
        keep_parent = root.parent
        keep_world = root.matrix_world.copy()
        root.parent = None
        root.matrix_world = to @ keep_world
        bpy.context.view_layer.update()
        wheels = []
        names_was = {}
        seen = {}
        for o in root.children_recursive:
            role = wheel_role(o.name)
            if role is None or o.parent is None or o.parent in names_was or wheel_role(o.parent.name) is not None:
                continue                                          # (a wheel's own mesh, under its node: not another wheel)
            p = o.matrix_world.translation
            if role in ("F", "R") and kind != "bike":             # (a three-wheeler's single front)
                pass
            if kind == "auto" and role.startswith("F"):
                role = "F"
            n = "Wheel_" + role
            seen[n] = seen.get(n, 0) + 1
            if seen[n] > 1:                                       # (a lorry's second rear axle)
                n += str(seen[n])
            names_was[o] = o.name
            o.name = n
            wheels.append({"name": n, "at": [round(p.x, 3), round(p.y, 3), round(p.z, 3)]})
        lamps = {}
        for o in root.children_recursive:
            nl = o.name.lower()
            if "light" in nl:
                t = o.matrix_world.translation
                lamps[o.name] = [round(t.x, 3), round(t.y, 3), round(t.z, 3)]
        lo2, hi2 = bounds(obs)
        size = hi2 - lo2
        name = "sf_" + key.lower()
        bpy.ops.object.select_all(action='DESELECT')
        for o in obs:
            o.select_set(True)
        path = os.path.join(OUT, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=False,
                                  export_yup=True, export_image_format='JPEG')
        fleet[name] = {"kind": kind, "glb": "res://assets/vehicles/%s.glb" % name, "len": round(size.x, 3),
                       "w": round(size.y, 3), "h": round(size.z, 3), "wheels": wheels, "lamps": lamps,
                       "source": "IN_" + key}
        print("SFV %-14s %-9s %.2f x %.2f x %.2f  wheels %d  lamps %d  %.1f MB" % (key, kind, size.x, size.y, size.z,
              len(wheels), len(lamps), os.path.getsize(path) / 1e6), flush=True)
        for o, was in names_was.items():                          # (as it was, for the next one)
            o.name = was
        root.matrix_world = keep_world
        root.parent = keep_parent
        bpy.context.view_layer.update()
    with open(os.path.join(OUT, "sf_fleet.json"), "w") as f:
        json.dump(fleet, f, indent=1)
    print("SFV done: %d vehicles" % len(fleet), flush=True)


main()
