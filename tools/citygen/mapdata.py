"""
The city map for the game's minimap and full map (godot/scripts/city/city_map.gd): every road by class,
simplified to 1.5 m, water bodies, and the names of the main roads; in the game frame (x east, z south).

    .venv/bin/python tools/citygen/mapdata.py        → godot/assets/city/map.bin

Format (little-endian):
    b"CMAP"  f32 x0 z0 x1 z1 (bounds)
    i32 nroads   per road:  u8 class (index into index.json classes)  u8 flags(1 bridge)  u16 n  f32[2n] x,z
    i32 nwater   per polygon: u16 n  f32[2n] x,z  (outer ring)
    i32 nnames   per name:  f32 x z  f32 angle  u8 class  u16 len  utf-8 bytes
"""
import math
import os
import struct
import sys

import geopandas as gpd
import numpy as np
import shapely
from pyproj import Transformer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import build_dir, load, path  # noqa: E402


def main():
    cfg = load("city.yaml")
    classes = list(load("roads.yaml")["classes"].keys())
    bdir = build_dir(cfg)
    to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
    e0, n0 = to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])

    def game(g):
        return shapely.transform(g, lambda c: np.column_stack([c[:, 0] - e0, -(c[:, 1] - n0)]))

    roads = gpd.read_file(os.path.join(bdir, "cache", "roads.gpkg"))
    water = gpd.read_file(os.path.join(bdir, "cache", "osm.gpkg"), layer="water").to_crs(cfg["crs"])
    buf = bytearray(b"CMAP")
    out_roads, names, xs, zs = [], {}, [], []
    for row in roads.itertuples():
        g = game(row.geometry).simplify(1.5)
        lines = list(g.geoms) if g.geom_type == "MultiLineString" else [g]
        cid = classes.index(row.cls) if row.cls in classes else 0
        for ln in lines:
            c = np.asarray(ln.coords)
            if len(c) < 2:
                continue
            out_roads.append((cid, 1 if row.bridge_b else 0, c))
            xs += [c[:, 0].min(), c[:, 0].max()]
            zs += [c[:, 1].min(), c[:, 1].max()]
        nm = getattr(row, "name", None)
        if isinstance(nm, str) and nm and row.cls in ("trunk", "primary", "secondary", "tertiary"):
            names.setdefault((nm, row.cls), []).append(g)
    buf += struct.pack("<4f", min(xs), min(zs), max(xs), max(zs))
    buf += struct.pack("<i", len(out_roads))
    for cid, fl, c in out_roads:
        buf += struct.pack("<BBH", cid, fl, len(c))
        buf += c.astype("<f4").tobytes()
    polys = []
    for g in water.geometry:
        if g is None:
            continue
        g = game(g).simplify(3.0)
        for p in (g.geoms if hasattr(g, "geoms") else [g]):
            if p.geom_type == "Polygon" and p.area > 400.0:
                polys.append(np.asarray(p.exterior.coords)[:-1])
    buf += struct.pack("<i", len(polys))
    for c in polys:
        buf += struct.pack("<H", len(c))
        buf += c.astype("<f4").tobytes()
    # a label at the middle of each named road's longest stretch, and one more every 1.5 km along it
    labels = []
    for (nm, cls), geoms in names.items():
        merged = shapely.line_merge(shapely.union_all(geoms))
        for ln in (merged.geoms if hasattr(merged, "geoms") else [merged]):
            if ln.length < 250.0:
                continue
            for k in range(max(1, int(ln.length / 1500.0))):
                t = ln.length * (k + 0.5) / max(1, int(ln.length / 1500.0))
                p = ln.interpolate(t)
                q = ln.interpolate(min(ln.length, t + 10.0))
                ang = math.atan2(q.y - p.y, q.x - p.x)
                if ang > math.pi / 2:
                    ang -= math.pi
                elif ang < -math.pi / 2:
                    ang += math.pi
                labels.append((p.x, p.y, ang, classes.index(cls), nm.encode("utf-8")[:200]))
    buf += struct.pack("<i", len(labels))
    for x, z, a, cid, b in labels:
        buf += struct.pack("<3fBH", x, z, a, cid, len(b)) + b
    out = path("godot", "assets", "city", "map.bin")
    with open(out, "wb") as f:
        f.write(bytes(buf))
    print("MAP %d roads, %d water, %d labels, %.1f MB" % (len(out_roads), len(polys), len(labels), len(buf) / 1e6))


if __name__ == "__main__":
    main()
