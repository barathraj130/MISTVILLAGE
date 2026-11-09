"""
What each road piece in the city tiles is made of, from the map: OSM's surface tag on its way (unpaved, dirt, ground,
compacted, mud: earth; gravel, fine_gravel, pebblestone: gravel; concrete, concrete:plates, concrete:lanes,
paving_stones: concrete), and a farm track with no tag is earth. Everything else is asphalt and is left out.
Written to godot/assets/city/surfaces.json: {"cx,cz": {"x2,z2": surface}}, keyed by each piece's first point
(x and z doubled and rounded: city_streamer.gd _surface_of reads it). Each piece is matched to the nearest way of
its own class within 3 m of its middle. Run by chunk.py after the tiles are written; running it again gives the
same file.

    .venv/bin/python tools/citygen/surfaces.py
"""
import json
import os
import sys

import geopandas as gpd
import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry import Point
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import path  # noqa: E402
from lib.tiles import read_tile  # noqa: E402

EARTH = {"unpaved", "dirt", "ground", "compacted", "mud", "earth", "sand", "grass"}
GRAVEL = {"gravel", "fine_gravel", "pebblestone"}
CONCRETE = {"concrete", "concrete:plates", "concrete:lanes", "paving_stones"}


def kind(surface, cls):
    s = str(surface or "").strip().lower()
    if s in EARTH:
        return "earth"
    if s in GRAVEL:
        return "gravel"
    if s in CONCRETE:
        return "concrete"
    if s == "" and cls == "track":
        return "earth"
    return ""


def main():
    out = path("godot", "assets", "city")
    index = json.load(open(os.path.join(out, "index.json")))
    classes = index["classes"]
    to_utm = Transformer.from_crs("EPSG:4326", index["crs"], always_xy=True)
    e0, n0 = to_utm.transform(index["origin"]["lon"], index["origin"]["lat"])
    roads = gpd.read_file(path("build", "cbe", "cache", "roads.gpkg")).to_crs(index["crs"])
    roads["k"] = [kind(s, c) for s, c in zip(roads["surface"], roads["cls"])]
    by_cls = {}
    for cls, grp in roads.groupby("cls"):
        geoms = [shapely.transform(g, lambda c: np.column_stack([c[:, 0] - e0, -(c[:, 1] - n0)])) for g in grp.geometry]
        by_cls[cls] = (STRtree(geoms), geoms, list(grp["k"]))
    res = {}
    counts = {}
    for key in sorted(index["tiles"]):
        cx, cz = map(int, key.split(","))
        fn = os.path.join(out, "chunks", "CBE_%d_%d.bin" % (cx, cz))
        if not os.path.exists(fn):
            continue
        t = read_tile(fn)
        tile = {}
        for r in t["roads"]:
            cls = classes[r["cid"]] if r["cid"] < len(classes) else ""
            if cls not in by_cls:
                continue
            p = np.asarray(r["p"]).reshape(-1, 3)
            if len(p) < 2:
                continue
            mid = p[len(p) // 2]
            tree, geoms, ks = by_cls[cls]
            h = tree.nearest(Point(mid[0], mid[2]))
            if h is None or geoms[h].distance(Point(mid[0], mid[2])) > 3.0 or ks[h] == "":
                continue
            tile["%d,%d" % (round(p[0][0] * 2), round(p[0][2] * 2))] = ks[h]
            counts[ks[h]] = counts.get(ks[h], 0) + 1
        if tile:
            res[key] = tile
    with open(os.path.join(out, "surfaces.json.tmp"), "w") as f:
        json.dump(res, f, separators=(",", ":"), sort_keys=True)
    os.replace(os.path.join(out, "surfaces.json.tmp"), os.path.join(out, "surfaces.json"))
    print("SURFACES %s road pieces not asphalt, in %d tiles" % (counts, len(res)), flush=True)


if __name__ == "__main__":
    main()
