"""
The people of the city's crowds (the station's travellers, the mall's shoppers, the temple's devotees, the people in
the shops...), made as the story's cast is (story_cast.py: MakeHuman bodies with faces of their own, skins, eyes,
brows, hair and clothes, the game rig and the same clips: Idle, Talk, Walk, Run, Sit), but lighter, for rooms
that hold dozens of them: their meshes thinned to about a quarter, their textures 512 px. A mix such as you see in
Coimbatore: men in shirts and trousers or a veshti, women in sarees or a kurta and trousers, from a college
student to a grandmother.

    Blender -b --python tools/humans/crowd_cast.py -- [--only m1,w2] [--walkstrip DIR]

Writes godot/assets/people/crowd_<key>.glb (crowd.gd picks among them). Reads story_cast.py, street_people.py and
quality.py without changing them.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import story_cast as SC  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "godot", "assets", "people")
THIN = 0.28                          # the share of each mesh's faces kept
TEX = 512

# key, gender, years, weight, muscle, height, skin, hair, brows, outfit, main colour, face seed (as story_cast.CAST)
CROWD = [
    ("m1", 1.0, 30, 0.5, 0.55, 0.56, "young_african_male", "short02", "mindfront_eyebrows_03", "trousers",
     (0.45, 0.62, 0.85), 1101),
    ("m2", 1.0, 45, 0.62, 0.45, 0.5, "middleage_african_male", "short04", "eyebrow004", "trousers",
     (0.93, 0.93, 0.9), 1102),
    ("m3", 1.0, 62, 0.55, 0.4, 0.48, "old_african_male", "short01", "eyebrow004", "veshti",
     (0.95, 0.95, 0.92), 1103),
    ("m4", 1.0, 21, 0.42, 0.5, 0.6, "young_african_male", "short02", "mindfront_eyebrows_03", "trousers",
     (0.12, 0.13, 0.16), 1104),
    ("m5", 1.0, 38, 0.66, 0.5, 0.53, "middleage_african_male", "short01", "eyebrow004", "trousers",
     (0.5, 0.12, 0.15), 1105),
    ("m6", 1.0, 55, 0.6, 0.45, 0.5, "mindfront_skin_male_african_middleage", "short01", "eyebrow004", "trousers",
     (0.8, 0.72, 0.55), 1106),
    ("w1", 0.0, 40, 0.6, 0.4, 0.42, "cutoff3d_indian_female_skin", "braid01", "mindfront_eyebrows_08", "saree",
     (0.1, 0.45, 0.25), 1201),
    ("w2", 0.0, 27, 0.48, 0.38, 0.46, "cutoff3d_indian_female_enhanced", "braid01", "mindfront_eyebrows_10", "saree",
     (0.6, 0.08, 0.15), 1202),
    ("w3", 0.0, 61, 0.6, 0.35, 0.38, "old_african_female", "bob02", "mindfront_eyebrows_08", "saree",
     (0.2, 0.3, 0.65), 1203),
    ("w4", 0.0, 21, 0.44, 0.35, 0.47, "callharvey3d_midtoned_female", "ponytail01", "mindfront_eyebrows_10", "modern_f",
     (0.85, 0.45, 0.6), 1204),
    ("w5", 0.0, 34, 0.55, 0.38, 0.44, "middleage_african_female", "long01", "mindfront_eyebrows_08", "modern_f",
     (0.9, 0.75, 0.25), 1205),
    ("w6", 0.0, 48, 0.62, 0.38, 0.42, "middleage_african_female", "braid01", "mindfront_eyebrows_08", "saree",
     (0.85, 0.4, 0.1), 1206),
]


def lighten(objs):
    """About a quarter of the faces (the eyes as they are; the eyelashes, thousands of hair cards no one sees in a
    crowd, left off; the brows thinned harder), textures no bigger than TEX. Returns the objects kept."""
    kept = []
    for o in objs:
        if o.type == 'MESH' and "eyelashes" in o.name:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        kept.append(o)
        if o.type != 'MESH' or ".low-poly" in o.name or len(o.data.polygons) < 2000:
            continue
        before = len(o.data.polygons)
        m = o.modifiers.new("Thin", 'DECIMATE')
        m.ratio = 0.18 if "eyebrow" in o.name else THIN
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.ops.object.modifier_move_to_index(modifier="Thin", index=0)    # before the armature
        bpy.ops.object.modifier_apply(modifier="Thin")
        print("CROWD %s: %d -> %d faces" % (o.name, before, len(o.data.polygons)), flush=True)
    for img in bpy.data.images:
        if img.size[0] > TEX or img.size[1] > TEX:
            img.scale(TEX, max(1, int(TEX * img.size[1] / max(img.size[0], 1))))
    return kept


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = args[args.index("--only") + 1].split(",") if "--only" in args else [c[0] for c in CROWD]
    for c in CROWD:
        if c[0] not in only:
            continue
        SC.clear()
        SC.stride = SC.STRIDE.get(c[9], 1.0)
        arm, objs = SC.build(c)
        if "--walkstrip" in args:
            SC.walk_strip(arm, objs, os.path.join(os.path.abspath(args[args.index("--walkstrip") + 1]), c[0]))
            continue
        SC.animate(arm)
        objs = lighten(objs)
        SC.export(arm, objs, os.path.abspath(os.path.join(OUT, "crowd_%s.glb" % c[0])))


if __name__ == "__main__":
    main()
