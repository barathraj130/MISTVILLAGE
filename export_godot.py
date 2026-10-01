"""
THE MIST VILLAGE — Blender → Godot 4 exporter

Converts the procedural scene built by mist_village.py into game-ready assets:

    godot/assets/models/*.gltf     site, terrain (near/mid/far), valley, mountains,
                                   one file per vegetation asset (decimated)
    godot/assets/models/textures/  baked, seamless tiling textures (albedo / roughness / normal)
    godot/assets/scene.json        everything that is not a mesh: 44k vegetation instances,
                                   lights, sun + sky, fog volumes, mist sheets, particles,
                                   campfire, the 10-shot camera path, title card, anchors,
                                   survey boundary, spawn point, day/night presets

Run it on the SAVED scene, headless (it rewrites materials in memory and never saves):

    /Applications/Blender.app/Contents/MacOS/Blender -b MistVillage.blend -P export_godot.py
    ... -- --quick              # 256 px textures, no normal maps (fast test run)
    ... -- --tex 2048           # texture resolution (default 1024)
    ... -- --out /path/assets   # output folder (default ./godot/assets)

How the procedural look survives the trip:
  * Node materials (Object-space noise / voronoi / wave) are baked onto a plane as
    seamless tiles; meshes get world-scale box-projected UVs so the tiles repeat
    at the same size they had in Blender.
  * Terrain and mountains (mask- and normal-driven shading over kilometres) are baked
    to vertex colours instead of textures.
  * Geometry Nodes scatter is exported as instance transforms (for MultiMeshInstance3D),
    not realised geometry.
  * Mist, fog volumes, fire, particles, lights and cameras cannot be expressed in glTF
    and go to scene.json so Godot can rebuild them with FogVolume, GPUParticles3D, etc.

Coordinates in scene.json are already Godot's: +Y up, Blender (x, y, z) → Godot (x, z, -y),
which is the same conversion the glTF exporter applies to the meshes.
"""

import bpy, bmesh, json, math, os, re, sys, time
import numpy as np
from mathutils import Matrix, Vector

# ----------------------------------------------------------------------------- args
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

def arg(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default

QUICK = "--quick" in ARGV
TEX = int(arg("--tex", 256 if QUICK else 1024))
BLEND_DIR = os.path.dirname(bpy.data.filepath) or os.getcwd()
OUT = os.path.abspath(arg("--out", os.path.join(BLEND_DIR, "godot", "assets")))
MODELS = os.path.join(OUT, "models")
TEXDIR = os.path.join(MODELS, "textures")
os.makedirs(TEXDIR, exist_ok=True)

if not bpy.app.background and "--force" not in ARGV:
    raise SystemExit("export_godot.py rewrites every material. Run it headless (blender -b ... -P) "
                     "or pass -- --force if you really mean to run it in an open file you won't save.")

S = bpy.context.scene
T0 = time.time()

def log(*a):
    print(f"[mv-export {time.time() - T0:6.1f}s]", *a, flush=True)

# ----------------------------------------------------------------------------- helpers
C3 = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))       # Blender Z-up → Godot Y-up
C4 = C3.to_4x4()
C4I = C4.inverted()

def r(x, n=3):
    return round(float(x), n)

def gv(v, n=3):
    """Blender world vector → Godot [x, y, z]."""
    return [r(v[0], n), r(v[2], n), r(-v[1], n)]

def gquat(m3):
    """World rotation of a camera/light (looks down local -Z in both apps) → Godot quat [x, y, z, w]."""
    q = (C3 @ m3.normalized()).to_quaternion()
    return [r(q.x, 5), r(q.y, 5), r(q.z, 5), r(q.w, 5)]

def slug(name):
    s = name.lower().replace("asset · ", "")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s

def coll(name):
    return bpy.data.collections.get(name)

C_SITE, C_TERR, C_ARCH = coll("01 SITE + SURVEY"), coll("02 TERRAIN + ROAD"), coll("03 ARCHITECTURE")
C_LAND, C_VALLEY, C_MTN = coll("04 LANDSCAPE"), coll("05 VALLEY — OUTSIDE PROPERTY"), coll("06 NILGIRI MOUNTAINS")
C_VFX, C_LIGHT, C_CAM, C_ASSET = coll("07 MIST + VFX"), coll("08 LIGHTING"), coll("09 CAMERAS"), coll("zz ASSET LIBRARY (instanced)")
if not C_SITE or not C_ASSET:
    raise SystemExit("This does not look like a scene built by mist_village.py")

def unhide_everything():
    def walk(lc):
        lc.exclude = False
        lc.hide_viewport = False
        lc.collection.hide_viewport = False
        for ch in lc.children:
            walk(ch)
    walk(bpy.context.view_layer.layer_collection)
    for o in S.objects:
        o.hide_viewport = False
        try:
            o.hide_set(False)
        except RuntimeError:
            pass

def isolate(keep=()):
    """Exclude every top-level collection except `keep` so Cycles bakes don't sync 44k instances.
    Objects linked straight to the scene collection (the bake plane) always stay visible."""
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.collection not in keep
    if not keep:
        return
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.collection in keep:
            for o in lc.collection.all_objects:
                try:
                    o.hide_set(False)
                except RuntimeError:
                    pass

def is_scatter(o):
    return any(m.type == "NODES" for m in o.modifiers)

def has_particles(o):
    return any(m.type == "PARTICLE_SYSTEM" for m in o.modifiers)

# =============================================================================
# 1. NON-MESH DATA → scene.json   (read before anything is modified)
# =============================================================================
DATA = {"format": "mist-village/1", "units": "metres, Godot axes (+Y up)", "source": os.path.basename(bpy.data.filepath)}

# ---------------------------------------------------------------- cameras (10-shot film)
def sample_cameras():
    fps = S.render.fps
    markers = sorted((m for m in S.timeline_markers if m.camera), key=lambda m: m.frame)
    shots = []
    for i, m in enumerate(markers):
        end = markers[i + 1].frame - 1 if i + 1 < len(markers) else S.frame_end
        shots.append({"index": i + 1, "name": m.name, "camera": m.camera.name, "start_frame": m.frame, "end_frame": end})
    fire = bpy.data.objects.get("CAMPFIRE flicker light")
    # particles re-simulate on every frame change; they are not needed for sampling
    parts = [(o, md) for o in S.objects for md in o.modifiers if md.type == "PARTICLE_SYSTEM"]
    for o, md in parts:
        md.show_viewport = False
    frames, energy = [], []
    for f in range(S.frame_start, S.frame_end + 1):
        S.frame_set(f)
        mk = [m for m in markers if m.frame <= f]
        cam = (mk[-1] if mk else markers[0]).camera
        mw = cam.matrix_world
        cd = cam.data
        aspect = S.render.resolution_y / S.render.resolution_x
        hfov = 2 * math.atan(cd.sensor_width / 2 / cd.lens)
        vfov = 2 * math.atan(math.tan(hfov / 2) * aspect)
        shot_i = markers.index(mk[-1] if mk else markers[0]) + 1
        frames.append([shot_i] + gv(mw.translation) + gquat(mw.to_3x3()) + [r(math.degrees(vfov), 2)])
        if fire:
            energy.append(fire.data.energy)
    for o, md in parts:
        md.show_viewport = True
    S.frame_set(S.frame_start)
    DATA["cinematic"] = {
        "fps": fps, "frame_start": S.frame_start, "frame_end": S.frame_end,
        "resolution": [S.render.resolution_x, S.render.resolution_y],
        "frame_layout": "[shot, pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w, vfov_deg]",
        "shots": shots, "frames": frames,
    }
    return energy

# ---------------------------------------------------------------- title card
def title_data():
    texts = {o.name: o.data.body for o in C_CAM.objects if o.type == "FONT"}
    fps = S.render.fps
    DATA["title"] = {
        "lines": [texts.get("TITLE · THE MIST VILLAGE", "THE MIST VILLAGE"),
                  texts.get("TITLE · KOTAGIRI", "KOTAGIRI · NILGIRIS"),
                  texts.get("TITLE · tagline", "Where the mist slows you down.")],
        "show_at_s": 41.0, "fade_in_s": [42.0, 43.2], "color": [0.98, 0.93, 0.84], "fps": fps,
    }

# ---------------------------------------------------------------- lights, sun, sky
def lights_data(fire_energy):
    out = []
    for o in S.objects:
        if o.type != "LIGHT":
            continue
        ld = o.data
        mw = o.matrix_world
        d = {"name": o.name, "type": ld.type, "pos": gv(mw.translation), "color": [r(c) for c in ld.color],
             "energy_w": r(ld.energy, 2), "radius": r(getattr(ld, "shadow_soft_size", 0.0)),
             "shadow": bool(getattr(ld, "use_shadow", True)),
             "parent": o.parent.name if o.parent else None}
        if ld.type in ("SUN", "SPOT", "AREA"):
            d["rot"] = gquat(mw.to_3x3())
            d["direction"] = gv((mw.to_3x3() @ Vector((0, 0, -1))).normalized(), 4)
        if ld.type == "SUN":
            d["angle_deg"] = r(math.degrees(ld.angle), 2)
        if ld.type == "AREA":
            d["size"] = r(ld.size)
        if o.name == "CAMPFIRE flicker light" and fire_energy:
            e = np.array(fire_energy)
            d["energy_w"] = r(e.mean(), 2)
            d["flicker"] = {"min_w": r(e.min(), 2), "max_w": r(e.max(), 2), "hz": 12.0}
        out.append(d)
    DATA["lights"] = out

    sky = {}
    w = S.world
    if w and w.node_tree:
        ramps = [n for n in w.node_tree.nodes if n.type == "VALTORGB"]
        if ramps:
            # the sky gradient is driven by elevation: t = el * 1.4 + 0.5
            sky["gradient"] = [[r(e.position), [r(c) for c in e.color[:3]]] for e in ramps[0].color_ramp.elements]
            sky["gradient_input"] = "t = sin(elevation) * 1.4 + 0.5"
        bg = [n for n in w.node_tree.nodes if n.type == "BACKGROUND"]
        if bg:
            sky["strength"] = r(bg[0].inputs[1].default_value)
    sun = next((o for o in S.objects if o.type == "LIGHT" and o.data.type == "SUN" and "Sun" in o.name), None)
    if sun:
        sky["sun_direction_to_sun"] = [-c for c in gv((sun.matrix_world.to_3x3() @ Vector((0, 0, -1))).normalized(), 4)]
        sky["sun_glow"] = {"color": [1.0, 0.55, 0.25], "tight_power": 28.0, "tight_gain": 6.0, "wide_power": 4.0, "wide_gain": 0.8}
    DATA["sky"] = sky

    # values copied from mist_village.py so Godot can blend golden hour ↔ night at runtime
    DATA["presets"] = {
        "golden": {"sun_energy_w": 4.2, "fill_energy_w": 0.25, "lampshade_emission": 7.0, "bulb_emission": 30.0,
                   "window_glow": 1.2, "sky_strength": 1.6},
        "night": {"sun_energy_w": 0.0, "fill_energy_w": 0.06, "lampshade_emission": 14.0, "bulb_emission": 60.0,
                  "window_glow": 3.0, "sky_strength": 1.0, "courtyard_light_w": 9.0, "fire_w": 420.0,
                  "sky_gradient": [[0.40, [0.004, 0.005, 0.009]], [0.5, [0.02, 0.028, 0.05]], [1.0, [0.002, 0.004, 0.012]]]},
    }

# ---------------------------------------------------------------- mist, fog, fire, particles
MIST_PARAMS = {   # from mat_mist_sheet(...) calls in mist_village.py
    "Valley Mist Sheet": {"density": 0.45, "noise_scale": 0.006, "color": [0.85, 0.88, 0.92]},
    "Ridge Mist Sheet": {"density": 0.7, "noise_scale": 0.0009, "color": [0.80, 0.84, 0.90]},
}
FOG_PARAMS = {    # from volume_box(...) calls
    "Low ground fog — property": {"density": 0.012, "height_falloff_power": 2.2, "noise_scale": 2.5},
    "Valley haze volume": {"density": 0.0015, "height_falloff_power": 2.2, "noise_scale": 2.5},
}

def vfx_data():
    mist, fog, flames, parts = [], [], [], []
    for o in C_VFX.objects:
        mw = o.matrix_world
        if o.name.startswith(("Valley mist layer", "Ridge mist band")):
            xs = [v.co.x for v in o.data.vertices]; ys = [v.co.y for v in o.data.vertices]
            mname = o.material_slots[0].material.name if o.material_slots else ""
            mist.append({"name": o.name, "center": gv(mw.translation), "size_xz": [r(max(xs) - min(xs), 1), r(max(ys) - min(ys), 1)],
                         **MIST_PARAMS.get(mname, {"density": 0.5, "noise_scale": 0.004, "color": [0.85, 0.88, 0.92]}),
                         "drift_per_s": [r(140.0 / 45.0, 3), 0.0, r(-60.0 / 45.0, 3)]})
        elif o.name in FOG_PARAMS:
            fog.append({"name": o.name, "center": gv(mw.translation), "size": [r(o.scale.x, 2), r(o.scale.z, 2), r(o.scale.y, 2)],
                        "color": [0.9, 0.92, 0.95], "anisotropy": 0.35, **FOG_PARAMS[o.name]})
        elif o.name.startswith("CAMPFIRE · flame"):
            flames.append({"pos": gv(mw.translation), "height": r(o.dimensions.z, 2), "radius": r(o.dimensions.x / 2, 2)})
        elif has_particles(o):
            st = [m for m in o.modifiers if m.type == "PARTICLE_SYSTEM"][0].particle_system.settings
            parts.append({"name": o.name, "center": gv(mw.translation), "emit_size_xz": [r(o.scale.x, 2), r(o.scale.y, 2)],
                          "count": st.count, "lifetime_frames": r(st.lifetime, 1), "lifetime_random": r(st.lifetime_random, 2),
                          "up_velocity": r(st.normal_factor), "velocity_random": r(st.factor_random),
                          "size": r(st.particle_size, 4), "size_random": r(st.size_random, 2),
                          "brownian": r(st.brownian_factor, 3), "gravity_factor": r(st.effector_weights.gravity, 3),
                          "instance": st.instance_object.name if st.instance_object else None,
                          "kind": "embers" if "ember" in o.name else "mist_puffs"})
    fire = None
    if flames:
        c = np.mean([f["pos"] for f in flames], 0)
        fire = {"center": [r(v) for v in c], "flames": flames, "color_base": [1.0, 0.05, 0.0], "color_mid": [1.0, 0.25, 0.02],
                "color_tip": [1.0, 0.65, 0.25], "emission": 22.0, "noise_scroll_per_s": [0.0067, 0.4, -0.0022]}
    DATA["mist_sheets"], DATA["fog_volumes"], DATA["campfire"], DATA["particles"] = mist, fog, fire, parts

# ---------------------------------------------------------------- vegetation instances
LOD_TRIS = 200
TREE_KINDS = ("shola", "cypress", "silver_oak", "eucalyptus", "tree_fern", "far_canopy", "boulder")

def vegetation_data():
    scatters = {o.name: o for o in S.objects if is_scatter(o)}
    layers = {n: {"name": n, "collection": o.users_collection[0].name, "instances": {}} for n, o in scatters.items()}
    used = {}
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for inst in dg.object_instances:
        if not inst.is_instance or not inst.parent or inst.parent.name not in scatters:
            continue
        src = inst.instance_object.original
        key = slug(src.name)
        used[key] = src
        m = inst.matrix_world
        loc = m.translation
        ry = m.to_euler("XYZ").z
        s = m.to_scale()[0]
        layers[inst.parent.name]["instances"].setdefault(key, []).append(gv(loc) + [r(ry, 3), r(s, 3)])
        n += 1
    DATA["vegetation"] = {
        "instance_layout": "[x, y, z, rot_y_rad, uniform_scale]",
        "assets": {k: {"model": f"models/veg_{k}.gltf", "collide": k.startswith(TREE_KINDS),
                       "trunk_radius": 0.35 if k.startswith(TREE_KINDS[:6]) else 0.8 if k.startswith("boulder") else 0.0}
                   for k in sorted(used)},
        "layers": list(layers.values()),
    }
    log(f"vegetation: {n} instances of {len(used)} assets in {len(layers)} layers")
    return used

# ---------------------------------------------------------------- anchors, boundary, spawn
def gameplay_data():
    anchors = []
    for c in (C_ARCH, C_SITE):
        for o in c.objects:
            if o.type == "EMPTY":
                anchors.append({"name": o.name, "pos": gv(o.matrix_world.translation), "rot_y": r(o.matrix_world.to_euler().z)})
    DATA["anchors"] = anchors
    b = bpy.data.objects.get("SURVEY BOUNDARY (overlay)")
    if b and b.type == "CURVE":
        pts = []
        for sp in b.data.splines:
            for p in (sp.points if len(sp.points) else sp.bezier_points):
                pts.append(gv(b.matrix_world @ Vector(p.co[:3])))
        DATA["site_boundary"] = {"polygon_xz": [[p[0], p[2]] for p in pts], "y": pts[0][1] if pts else 0.0, "area_m2": 1416}
    # spawn on the road where shot 3 (approach to the gate) begins, dropped to the ground
    terr = bpy.data.objects.get("Terrain — Kotagiri hillside + valley")
    frames = DATA["cinematic"]["frames"]
    f3 = next((f for f in frames if f[0] == 3), frames[0])
    p = Vector((f3[1], -f3[3], f3[2]))
    z = p.z
    if terr:
        hit, loc, *_ = terr.ray_cast(Vector((p.x, p.y, 3000.0)), Vector((0, 0, -1)))
        if hit:
            z = loc.z
    DATA["spawn"] = {"pos": gv(Vector((p.x, p.y, z + 0.1))), "look_at": gv(Vector((0, 0, z + 1.6)))}

# =============================================================================
# 2. MATERIALS → baked tiles / vertex colours / plain PBR
# =============================================================================
TILE = {  # metres covered by one texture repeat
    "Wet Mountain Asphalt": 6.0, "Natural Stone Paving": 3.0, "Flagstone Path": 3.0, "Parking Pavers": 2.4,
    "Red Nilgiri Soil": 4.0, "Moss": 3.0, "Mossy Boulder": 3.0,
}
DEFAULT_TILE, LEAF_TILE = 2.5, 3.0
SKIP_MATS = ("Campfire Flame", "Mist Puff", "Ember Glow", "Title Emission", "Valley Mist Sheet", "Ridge Mist Sheet")
MAT_HINTS = {}   # extra info for the Godot side (leaf translucency, glass, emission groups)

def find(nt, typ):
    return [n for n in nt.nodes if n.type == typ]

def out_node(nt):
    outs = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"]
    return next((n for n in outs if n.is_active_output), outs[0] if outs else None)

def src(sock):
    """(linked source socket or None, constant value)"""
    if sock.is_linked:
        return sock.links[0].from_socket, None
    v = sock.default_value
    return None, (tuple(v) if hasattr(v, "__len__") else v)

def analyse(mat):
    nt = mat.node_tree
    p = find(nt, "BSDF_PRINCIPLED")
    dif = find(nt, "BSDF_DIFFUSE")
    em = find(nt, "EMISSION")
    info = {"kind": "pbr", "tile": TILE.get(mat.name, DEFAULT_TILE)}
    if p:
        p = p[0]
        info["base"] = src(p.inputs["Base Color"])
        info["rough"] = src(p.inputs["Roughness"])
        info["metal"] = src(p.inputs["Metallic"])[1] or 0.0
        info["normal"] = p.inputs["Normal"].links[0].from_socket if p.inputs["Normal"].is_linked else None
        info["bsdf"] = p.outputs[0]
        tw = p.inputs.get("Transmission Weight")
        if tw is not None and not tw.is_linked and tw.default_value > 0.5:
            info["kind"] = "water"
    elif dif:
        info.update(kind="leaf", base=src(dif[0].inputs["Color"]), rough=(None, 0.6), metal=0.0, normal=None,
                    bsdf=dif[0].outputs[0], tile=LEAF_TILE)
    elif find(nt, "BSDF_TRANSPARENT") and find(nt, "BSDF_GLOSSY"):
        tint = find(nt, "BSDF_TRANSPARENT")[0].inputs["Color"].default_value
        info.update(kind="glass", base=(None, tuple(tint)), rough=(None, 0.03), metal=0.0, normal=None)
    elif em:
        info.update(base=(None, (0.0, 0.0, 0.0, 1.0)), rough=(None, 0.5), metal=0.0, normal=None)
    else:
        return None
    if em:
        info["emission"] = (tuple(em[0].inputs["Color"].default_value), em[0].inputs["Strength"].default_value)
    if "leaf" == info["kind"] or mat.name.startswith(("Hydrangea", "Wild Flowers", "Highland Grass")):
        info["kind"] = "leaf"
    return info

# ---------------------------------------------------------------- tile baking
BAKE_PLANE = None

def bake_plane(size):
    global BAKE_PLANE
    if BAKE_PLANE is None:
        me = bpy.data.meshes.new("__bake_plane")
        me.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new(name="UVMap")
        for i, c in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
            uv.data[i].uv = c
        BAKE_PLANE = bpy.data.objects.new("__bake_plane", me)
        S.collection.objects.link(BAKE_PLANE)
    me = BAKE_PLANE.data
    for v, c in zip(me.vertices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        v.co = (c[0] * size, c[1] * size, 0.0)
    return BAKE_PLANE

def seamless(a, n):
    """a: (m, m, 4) with m > n. Cross-fade the overlap so the n×n result tiles."""
    ov = a.shape[1] - n
    t = np.linspace(0.0, 1.0, ov, dtype=np.float32)
    b = a[:, :n].copy()
    b[:, :ov] = a[:, n:n + ov] * (1 - t)[None, :, None] + a[:, :ov] * t[None, :, None]
    c = b[:n].copy()
    c[:ov] = b[n:n + ov] * (1 - t)[:, None, None] + b[:ov] * t[:, None, None]
    return c

def bake_tile(mat, info, what):
    """what: 'base' | 'rough' | 'normal' → saved image"""
    n = TEX
    m = int(n * 1.25)
    tile = info["tile"]
    plane = bake_plane(tile * 1.25)
    plane.data.materials.clear()
    plane.data.materials.append(mat)
    nt = mat.node_tree
    out = out_node(nt)
    prev = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
    tmp = []
    img = bpy.data.images.new(f"__bake_{what}", m, m, alpha=False)
    img.colorspace_settings.name = "sRGB" if what == "base" else "Non-Color"
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tmp.append(tex)
    for nd in nt.nodes:
        nd.select = False
    tex.select = True
    nt.nodes.active = tex
    if what == "normal":
        nt.links.new(info["bsdf"], out.inputs["Surface"])
        bake_type = "NORMAL"
    else:
        e = nt.nodes.new("ShaderNodeEmission"); tmp.append(e)
        e.inputs["Strength"].default_value = 1.0
        nt.links.new(info[what][0], e.inputs["Color"])
        nt.links.new(e.outputs[0], out.inputs["Surface"])
        bake_type = "EMIT"
    bpy.ops.object.select_all(action="DESELECT")
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.bake(type=bake_type, normal_space="TANGENT", margin=0, use_clear=True, target="IMAGE_TEXTURES")
    px = np.empty(m * m * 4, np.float32)
    img.pixels.foreach_get(px)
    tile_px = seamless(px.reshape(m, m, 4), n)
    tile_px[..., 3] = 1.0
    # restore material
    for nd in tmp:
        nt.nodes.remove(nd)
    if prev:
        nt.links.new(prev, out.inputs["Surface"])
    bpy.data.images.remove(img)
    # save
    fin = bpy.data.images.new(f"{slug(mat.name)}_{what}", n, n, alpha=False)
    fin.colorspace_settings.name = "sRGB" if what == "base" else "Non-Color"
    fin.pixels.foreach_set(tile_px.ravel())
    ext = "png" if what == "normal" else "jpg"
    fin.filepath_raw = os.path.join(TEXDIR, f"{slug(mat.name)}_{what}.{ext}")
    fin.file_format = "PNG" if ext == "png" else "JPEG"
    try:
        fin.save(quality=90)
    except TypeError:
        fin.save()
    fin.reload()
    return fin

def rebuild(mat, info, maps):
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    def image(img, loc):
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = img; t.location = loc
        t.interpolation = "Linear"; t.extension = "REPEAT"
        return t
    if "base" in maps:
        nt.links.new(image(maps["base"], (-600, 300)).outputs[0], p.inputs["Base Color"])
    else:
        c = info["base"][1]
        p.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0) if c else (0.5, 0.5, 0.5, 1.0)
    if "rough" in maps:
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(image(maps["rough"], (-600, 0)).outputs[0], sep.inputs[0])
        nt.links.new(sep.outputs[1], p.inputs["Roughness"])
    else:
        p.inputs["Roughness"].default_value = float(info["rough"][1] if info["rough"][1] is not None else 0.5)
    p.inputs["Metallic"].default_value = float(info["metal"] or 0.0)
    if "normal" in maps:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(image(maps["normal"], (-600, -300)).outputs[0], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], p.inputs["Normal"])
    if "emission" in info:
        (ec, es) = info["emission"]
        p.inputs["Emission Color"].default_value = ec
        p.inputs["Emission Strength"].default_value = es
    kind = info["kind"]
    if kind == "glass":
        p.inputs["Alpha"].default_value = 0.14
        p.inputs["Roughness"].default_value = 0.03
    elif kind == "water":
        p.inputs["Alpha"].default_value = 0.6
    for attr, val in (("surface_render_method", "BLENDED" if kind in ("glass", "water") else "DITHERED"),
                      ("blend_method", "BLEND" if kind in ("glass", "water") else "OPAQUE")):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    mat.use_backface_culling = kind not in ("leaf", "glass")
    hint = {"kind": kind}
    if "emission" in info:
        hint["emission"] = r(info["emission"][1], 2)
    MAT_HINTS[mat.name] = hint

def convert_materials(mats):
    S.render.engine = "CYCLES"
    S.cycles.device = "CPU"
    S.cycles.samples = 4
    try:
        S.cycles.use_denoising = False
    except Exception:
        pass
    S.render.bake.margin = 0
    isolate(keep=())
    baked = 0
    for i, mat in enumerate(sorted(mats, key=lambda m: m.name)):
        if not mat.node_tree or mat.name.startswith(SKIP_MATS):
            continue
        info = analyse(mat)
        if info is None:
            log(f"  ? {mat.name}: unknown node setup, left as is")
            continue
        maps = {}
        if info.get("base") and info["base"][0] is not None:
            maps["base"] = bake_tile(mat, info, "base")
        if info.get("rough") and info["rough"][0] is not None:
            maps["rough"] = bake_tile(mat, info, "rough")
        if info.get("normal") is not None and not QUICK:
            maps["normal"] = bake_tile(mat, info, "normal")
        baked += len(maps)
        rebuild(mat, info, maps)
        if maps:
            log(f"  baked {'/'.join(maps)} for {mat.name}")
    unhide_everything()
    log(f"materials: {len(mats)} converted, {baked} maps baked at {TEX}px")

# ---------------------------------------------------------------- box UVs
def box_uv(obj):
    me = obj.data
    if not isinstance(me, bpy.types.Mesh) or not len(me.polygons):
        return
    npoly, nloop, nvert = len(me.polygons), len(me.loops), len(me.vertices)
    nrm = np.empty(npoly * 3, np.float32); me.polygons.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
    mi = np.empty(npoly, np.int32); me.polygons.foreach_get("material_index", mi)
    tot = np.empty(npoly, np.int32); me.polygons.foreach_get("loop_total", tot)
    vi = np.empty(nloop, np.int32); me.loops.foreach_get("vertex_index", vi)
    co = np.empty(nvert * 3, np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    tiles = np.array([TILE.get(ms.material.name, LEAF_TILE if MAT_HINTS.get(ms.material.name, {}).get("kind") == "leaf" else DEFAULT_TILE)
                      if ms.material else DEFAULT_TILE for ms in obj.material_slots] or [DEFAULT_TILE], np.float32)
    lp = np.repeat(np.arange(npoly), tot)
    n = nrm[lp]; p = co[vi]
    ax = np.abs(n).argmax(1)
    u = np.where(ax == 0, p[:, 1] * np.sign(n[:, 0]), p[:, 0] * np.where(ax == 1, -np.sign(n[:, 1]), 1.0))
    v = np.where(ax == 2, p[:, 1] * np.sign(n[:, 2]), p[:, 2])
    t = tiles[np.clip(mi[lp], 0, len(tiles) - 1)]
    uv = np.stack([u / t, v / t], 1).astype(np.float32)
    for old in [l for l in me.uv_layers if l.name != "box"]:
        me.uv_layers.remove(old)           # only the box projection matches the baked tiles
    layer = me.uv_layers.get("box") or me.uv_layers.new(name="box")
    layer.data.foreach_set("uv", uv.ravel())
    me.uv_layers.active = layer
    layer.active_render = True

# ---------------------------------------------------------------- vertex-colour bake (terrain, mountains)
def bake_vertex_colors(objs):
    shared = {}
    for o in objs:
        mat = o.material_slots[0].material
        if mat.name not in shared:
            nt = mat.node_tree
            p = find(nt, "BSDF_PRINCIPLED")[0]
            out = out_node(nt)
            e = nt.nodes.new("ShaderNodeEmission")
            nt.links.new(p.inputs["Base Color"].links[0].from_socket, e.inputs["Color"])
            nt.links.new(e.outputs[0], out.inputs["Surface"])
            vc = bpy.data.materials.new(mat.name + " (baked)")
            vc.use_nodes = True
            vnt = vc.node_tree
            vp = find(vnt, "BSDF_PRINCIPLED")[0]
            ca = vnt.nodes.new("ShaderNodeVertexColor"); ca.layer_name = "baked"
            vnt.links.new(ca.outputs["Color"], vp.inputs["Base Color"])
            vp.inputs["Roughness"].default_value = 0.92
            vc.use_backface_culling = True
            shared[mat.name] = vc
            MAT_HINTS[vc.name] = {"kind": "vertex_color"}
        me = o.data
        for a in [a for a in me.color_attributes]:
            if a.name != "baked" and a.name != "mv_mask":
                me.color_attributes.remove(a)
        ca = me.color_attributes.get("baked") or me.color_attributes.new("baked", "BYTE_COLOR", "POINT")
        me.color_attributes.active_color = ca
        try:
            me.color_attributes.render_color_index = list(me.color_attributes).index(ca)
        except Exception:
            pass
        isolate(keep=set(o.users_collection))
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type="EMIT", target="VERTEX_COLORS", use_clear=True)
        unhide_everything()
        if "mv_mask" in me.color_attributes:
            me.color_attributes.remove(me.color_attributes["mv_mask"])
        o.material_slots[0].material = shared[mat.name]
        log(f"  vertex-colour baked {o.name} ({len(me.vertices)} verts)")

# ---------------------------------------------------------------- terrain split
def split_terrain(terr):
    """near (collision, walkable site), mid (collision, the valley you can explore), far (backdrop)."""
    bands = (("terrain_near-col", 0, 160), ("terrain_mid-col", 160, 1600), ("terrain_far", 1600, 1e9))
    outs = []
    for name, lo, hi in bands:
        me = terr.data.copy()
        bm = bmesh.new(); bm.from_mesh(me)
        kill = [f for f in bm.faces if not (lo <= max(abs(f.calc_center_median().x), abs(f.calc_center_median().y)) < hi)]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(me); bm.free()
        o = bpy.data.objects.new(name, me)
        o.matrix_world = terr.matrix_world
        C_TERR.objects.link(o)
        outs.append(o)
        log(f"  {name}: {len(me.polygons)} faces")
    return outs

# =============================================================================
# 3. glTF EXPORT
# =============================================================================
_GLTF_PROPS = None

def export_gltf(objs, fname):
    global _GLTF_PROPS
    if _GLTF_PROPS is None:
        _GLTF_PROPS = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kw = dict(export_format="GLTF_SEPARATE", export_texture_dir="textures", use_selection=True, export_apply=True,
              export_yup=True, export_cameras=False, export_lights=False, export_animations=False, export_skins=False,
              export_morph=False, export_materials="EXPORT", export_image_format="AUTO", export_vertex_color="MATERIAL",
              export_extras=True, export_texcoords=True, export_normals=True, export_tangents=False,
              export_attributes=False, export_gn_mesh=False)
    kw = {k: v for k, v in kw.items() if k in _GLTF_PROPS}
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(MODELS, fname)
    bpy.ops.export_scene.gltf(filepath=path, **kw)
    log(f"  wrote {fname} ({len(objs)} objects)")

def text_to_mesh(o):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    m = bpy.data.objects.new(o.name, me)
    o.name = o.name + " (font)"
    for c in o.users_collection:
        c.objects.link(m)
    m.matrix_world = o.matrix_world.copy()
    return m

def collidable(name):
    n = name.lower()
    return not any(k in n for k in ("light", "lens", "lamp", "bulb", "festoon", "lantern", "glow", "sign · text",
                                    "cushion", "tea set", "throw", "bedding", "pillow", "curtain"))

# =============================================================================
# 4. RUN
# =============================================================================
def main():
    unhide_everything()
    log("sampling the 10-shot camera path…")
    fire_energy = sample_cameras()
    title_data()
    lights_data(fire_energy)
    vfx_data()
    used_assets = vegetation_data()
    gameplay_data()

    # ---- decide what goes where
    terr = bpy.data.objects.get("Terrain — Kotagiri hillside + valley")
    site = [o for c in (C_SITE, C_TERR, C_ARCH, C_LAND) for o in c.objects
            if o is not terr and o.type in ("MESH", "FONT", "EMPTY") and not o.hide_render
            and not is_scatter(o) and not has_particles(o)]
    site = [text_to_mesh(o) if o.type == "FONT" else o for o in site]
    valley = [o for o in C_VALLEY.objects if o.type == "MESH" and not is_scatter(o)]
    mountains = [o for o in C_MTN.objects if o.type == "MESH"]
    veg = list(used_assets.values())

    textured = [o for o in site + valley + veg if o.type == "MESH"]
    mats = {s.material for o in textured for s in o.material_slots if s.material}

    log(f"baking {len(mats)} materials…")
    convert_materials(mats)
    log("box-projecting UVs…")
    for o in textured:
        box_uv(o)
    log("vertex-colour baking terrain + mountains…")
    bake_vertex_colors([terr] + mountains)
    terrain_parts = split_terrain(terr)

    # ---- decimate vegetation for real-time (Godot also generates LODs on import)
    for o in veg:
        nv = len(o.data.vertices)
        target = 7000 if o.name.startswith(("asset · shola", "asset · cypress", "asset · silver", "asset · euc", "asset · tree fern")) else 2500
        if nv > target:
            d = o.modifiers.new("game_decimate", "DECIMATE"); d.ratio = target / nv

    # ---- collision suffixes (Godot import hint: "-col" → StaticBody3D + trimesh shape)
    for o in site:
        if o.type == "MESH" and collidable(o.name) and not o.name.endswith("-col"):
            o.name = o.name[:58] + "-col"

    log("exporting glTF…")
    export_gltf(site, "site.gltf")
    export_gltf(terrain_parts, "terrain.gltf")
    export_gltf(valley, "valley.gltf")
    export_gltf(mountains, "mountains.gltf")
    for key, o in used_assets.items():
        o.parent = None
        mw = o.matrix_world.copy()
        o.matrix_world = Matrix.Identity(4)       # assets are authored at the origin; make sure
        export_gltf([o], f"veg_{key}.gltf")
        # distant LOD: ~200 triangles, swapped in by Godot beyond LOD_DISTANCE
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if tris > 600:
            d = o.modifiers.get("game_decimate") or o.modifiers.new("game_decimate", "DECIMATE")
            d.ratio = LOD_TRIS / tris
            export_gltf([o], f"veg_{key}_lod.gltf")
            DATA["vegetation"]["assets"][key]["lod_model"] = f"models/veg_{key}_lod.gltf"
        o.matrix_world = mw

    DATA["models"] = {"site": "models/site.gltf", "terrain": "models/terrain.gltf",
                      "valley": "models/valley.gltf", "mountains": "models/mountains.gltf"}
    DATA["materials"] = MAT_HINTS
    with open(os.path.join(OUT, "scene.json"), "w") as f:
        json.dump(DATA, f, separators=(",", ":"), ensure_ascii=False)
    size = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fs in os.walk(OUT) for fn in fs) / 1e6
    log(f"done → {OUT}  ({size:.0f} MB)")

main()
