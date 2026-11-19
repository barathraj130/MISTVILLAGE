"""Pictures side by side in one sheet (for checking test shots): Blender's Python, no other libraries.
    Blender -b --factory-startup --python tools/dev/montage.py -- DIR OUT.jpg COLS [name1,name2,...]
DIR's .jpg files in name order (or those ending _<name>.jpg in the order given), halved if wider than 700 px."""
import bpy, numpy as np, sys, os
args = sys.argv[sys.argv.index("--") + 1:]
d, out, cols = args[0], args[1], int(args[2])
fs = sorted(f for f in os.listdir(d) if f.endswith(".jpg"))
if len(args) > 3:
    fs = [f for o in args[3].split(",") for f in fs if f.endswith("_" + o.strip() + ".jpg")]
ims = []
for f in fs:
    im = bpy.data.images.load(os.path.join(d, f))
    w, h = im.size
    a = np.array(im.pixels[:]).reshape(h, w, 4)
    ims.append(a[::2, ::2] if w > 700 else a)
h, w = ims[0].shape[:2]
rows = (len(ims) + cols - 1) // cols
M = np.ones((rows * h, cols * w, 4))
for i, a in enumerate(ims):
    if a.shape[:2] != (h, w):                     # (a pixel off in size: cropped or padded to fit, not dropped)
        b = np.ones((h, w, 4))
        hh, ww = min(h, a.shape[0]), min(w, a.shape[1])
        b[h - hh:, :ww] = a[a.shape[0] - hh:, :ww]
        a = b
    r = rows - 1 - i // cols
    c = i % cols
    M[r * h:(r + 1) * h, c * w:(c + 1) * w] = a
o = bpy.data.images.new("m", cols * w, rows * h)
o.pixels = M.ravel()
o.filepath_raw = out
o.file_format = 'JPEG'
o.save()
print("MONTAGE", len(fs))
