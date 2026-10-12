"""
Install the CC0 MakeHuman asset packs (vendor/mpfb/*.zip) into MPFB's user data, the same way MPFB's own
"Load pack from zip file" button does (check the zip, fix it if needed, extract, refresh the asset lists).

    Blender -b --python tools/humans/install_packs.py
"""
import glob
import importlib
import os
import sys
import zipfile

import bpy  # noqa: F401  (MPFB must be loaded)


def mpfb(path, key):
    for m in sys.modules:
        if m.endswith(path):
            return getattr(importlib.import_module(m), key)
    raise SystemExit("MPFB is not enabled in Blender")


LocationService = mpfb("mpfb.services.locationservice", "LocationService")
AssetService = mpfb("mpfb.services.assetservice", "AssetService")
root = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "vendor", "mpfb")
data_dir = LocationService.get_user_data()
for z in sorted(glob.glob(os.path.join(root, "*.zip"))):
    if os.path.basename(z).startswith("mpfb-"):
        continue
    problem = AssetService.check_asset_pack_zip(z)
    if problem is None:
        with zipfile.ZipFile(z) as zf:
            zf.extractall(data_dir)
        print("PACK installed", os.path.basename(z))
    else:
        res = AssetService.fix_and_extract_asset_pack_zip(z, data_dir)
        print("PACK fixed+installed" if res is None else "PACK FAILED %s" % res, os.path.basename(z))
AssetService.update_all_asset_lists()
print("PACKS data dir:", data_dir)
