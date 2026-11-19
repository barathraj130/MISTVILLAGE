"""Coimbatore's forest pockets for the game: the real green areas from OpenStreetMap (build/cbe/cache/osm.gpkg),
in the game frame (x = E - E0, z = -(N - N0), godot/assets/city/index.json's origin), with every road, footpath and
building cut out of them (buffered), so the trees planted inside (city_streamer.gd _forest) never stand on a road,
a path or in a building. Written to godot/assets/city/forest_pockets.json.

    .venv/bin/python tools/citygen/forest_pockets.py [--only tnau]      (stage 1: the TNAU Botanical Garden)

Each pocket: id, name, kind (forest / wood / park / garden / scrub), "mix" (the species and how dense: the game reads
it), and its polygons (outer ring and holes) simplified to 1 m.
"""
import json
import os
import sys

import geopandas as gpd
import numpy as np
import shapely
from pyproj import Transformer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
GPKG = os.path.join(ROOT, "build", "cbe", "cache", "osm.gpkg")
INDEX = os.path.join(ROOT, "godot", "assets", "city", "index.json")
OUT = os.path.join(ROOT, "godot", "assets", "city", "forest_pockets.json")

# the pockets: (id, how to find it: OSM name or (kind, a point inside, game x, z), the planting mix)
#   mix: canopy density (trees per 100 m²), species weights, and the under-storey density
POCKETS = [
    ("tnau", {"name": "TNAU Botanical Garden"}, {
        "canopy": 1.25, "under": 4.0,
        "species": {"banyan": 0.12, "tamarind": 0.22, "neem": 0.2, "rain": 0.16, "gul": 0.08, "bamboo": 0.12, "palm": 0.1}}),
]
ROAD_CLEAR = {"footway": 1.6, "path": 1.6, "pedestrian": 2.5, "steps": 1.5, "cycleway": 2.0, "track": 2.5, "service": 3.5}


def main():
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    idx = json.load(open(INDEX))
    crs = idx["crs"]
    e0, n0 = Transformer.from_crs("EPSG:4326", crs, always_xy=True).transform(idx["origin"]["lon"], idx["origin"]["lat"])
    lu = gpd.read_file(GPKG, layer="landuse").to_crs(crs)
    roads = gpd.read_file(GPKG, layer="roads").to_crs(crs)
    blds = gpd.read_file(GPKG, layer="buildings").to_crs(crs)
    out = []
    for pid, find, mix in POCKETS:
        if only and pid not in only:
            continue
        sel = lu[lu["name"] == find["name"]] if "name" in find else lu
        if sel.empty:
            print("POCKET %s: not found" % pid)
            continue
        poly = shapely.union_all(list(sel.geometry))
        # cut out roads and paths (buffered by half their width and a clearance) and buildings (+1.5 m)
        near_r = roads[roads.intersects(poly.buffer(10))]
        cuts = []
        for hw, g in zip(near_r["highway"], near_r.geometry):
            cuts.append(g.buffer(ROAD_CLEAR.get(str(hw), 6.0)))
        near_b = blds[blds.intersects(poly.buffer(5))]
        cuts += [g.buffer(1.5) for g in near_b.geometry]
        if cuts:
            poly = poly.difference(shapely.union_all(cuts))
        poly = shapely.transform(poly, lambda c: np.column_stack([c[:, 0] - e0, -(c[:, 1] - n0)]))   # (the game frame)
        poly = poly.simplify(1.0)
        parts = list(poly.geoms) if poly.geom_type == "MultiPolygon" else [poly]
        polys = []
        for p in parts:
            if p.area < 40.0:
                continue
            polys.append({"outer": [[round(x, 2), round(z, 2)] for x, z in p.exterior.coords[:-1]],
                          "holes": [[[round(x, 2), round(z, 2)] for x, z in h.coords[:-1]] for h in p.interiors]})
        area = sum(p.area for p in parts)
        b = poly.bounds
        out.append({"id": pid, "name": find.get("name", pid), "mix": mix, "polys": polys,
                    "bbox": [round(b[0], 1), round(b[1], 1), round(b[2], 1), round(b[3], 1)]})
        print("POCKET %s: %d parts, %.0f m² planted (roads %d, buildings %d cut out), bbox %s" % (
            pid, len(polys), area, len(near_r), len(near_b), [round(v) for v in b]))
    json.dump({"about": "tools/citygen/forest_pockets.py", "pockets": out}, open(OUT, "w"), indent=None)
    print("POCKETS written", OUT)


if __name__ == "__main__":
    main()
