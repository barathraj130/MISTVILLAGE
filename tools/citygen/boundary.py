"""
The city's area beyond the 12 km circle (config/cbe_boundary.geojson, read by config/city.yaml): the corridor of
the Coimbatore–Mettupalayam road (NH 181) out to Mettupalayam, the town itself, and each ghat road out of it up to
its foot, where Coimbatore district ends and the Nilgiris begin (Kallar on the Coonoor road, the Kotagiri road's
first climb). Writes, besides the area, godot/assets/landmarks/borders.json: the police checks at those feet, in
the game frame, for scripts/city/bail.gd (on bail, Karthik is turned back there).

    .venv/bin/python tools/citygen/boundary.py ways.json
        ways.json: the trunk and primary roads north of the city (a scan of the regional OSM file, see --scan)
    .venv/bin/python tools/citygen/boundary.py --scan ways.json      (writes it: ~1 minute)
    .venv/bin/python tools/citygen/boundary.py --outline             (only the outline into borders.json)
"""
import gzip
import json
import math
import os
import sys

import numpy as np
import shapely
import shapely.ops
from shapely.geometry import LineString, Point, mapping

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import Projection, load, path  # noqa: E402

CIRCLE_M = 12000.0
CORRIDOR_M = 1500.0          # either side of NH 181
TOWN_M = 2500.0              # round Mettupalayam
GHAT_M = 600.0               # either side of a ghat road, up to its foot
FOOT_ABOVE = 110.0           # the foot: where the road has climbed this far above the town
METTUPALAYAM = (76.9365, 11.2990)


def scan(out):
    import osmium
    src = path(load("city.yaml")["source"]["pbf"])
    ways = []
    fp = osmium.FileProcessor(src, osmium.osm.NODE | osmium.osm.WAY).with_locations().with_filter(osmium.filter.KeyFilter("highway"))
    for o in fp:
        if not o.is_way() or o.tags.get("highway", "") not in ("trunk", "primary"):
            continue
        try:
            pts = [(n.lon, n.lat) for n in o.nodes]
        except Exception:
            continue
        if any(76.8 <= x <= 77.05 and 11.0 <= y <= 11.42 for x, y in pts):
            ways.append({"id": o.id, "ref": o.tags.get("ref", ""), "name": o.tags.get("name", ""), "pts": pts})
    json.dump(ways, open(out, "w"))


def dem():
    with gzip.open(path("mapdata", "N11E076.hgt.gz")) as f:
        h = np.frombuffer(f.read(), ">i2").reshape(3601, 3601)
    return lambda lon, lat: float(h[min(max(int(round((12.0 - lat) * 3600)), 0), 3600), min(max(int(round((lon - 76.0) * 3600)), 0), 3600)])


def chain(ways, start, pick, max_lat):
    """The road from start: the ways matching pick, joined end to end, as one line (lon, lat), going away from start."""
    segs = [w["pts"] for w in ways if pick(w)]
    line = []
    here = start
    used = set()
    for _ in range(400):
        best, bd, flip = None, 0.004, False
        for i, s in enumerate(segs):
            if i in used:
                continue
            for f, e in ((False, s[0]), (True, s[-1])):
                d = math.hypot(e[0] - here[0], e[1] - here[1])
                if d < bd:
                    best, bd, flip = i, d, f
        if best is None:
            break
        used.add(best)
        s = segs[best][::-1] if flip else segs[best]
        line += s
        here = s[-1]
        if here[1] > max_lat:
            break
    return line


def outline_into_borders():
    """borders.json gets the area's outline in the game frame ("area": [[x, z], ...]), for the game's own test of
    where the built world ends (a road leaves it: the police turn him back there)."""
    cfg = load("city.yaml")
    pr = Projection(cfg)
    gj = json.load(open(path("config", "cbe_boundary.geojson")))
    ring = gj["features"][0]["geometry"]["coordinates"][0]
    bp = path("godot", "assets", "landmarks", "borders.json")
    data = json.load(open(bp))
    checks = data["checks"] if isinstance(data, dict) else data
    out = {"checks": checks, "area": [[round(c, 1) for c in pr.game(lon, lat)] for lon, lat in ring]}
    json.dump(out, open(bp, "w"))
    print("borders.json: %d checks, area outline %d points" % (len(checks), len(out["area"])))


def main():
    if sys.argv[1] == "--scan":
        scan(sys.argv[2])
        return
    if sys.argv[1] == "--outline":
        outline_into_borders()
        return
    ways = json.load(open(sys.argv[1]))
    cfg = load("city.yaml")
    pr = Projection(cfg)
    height = dem()
    kx = 111320.0 * math.cos(math.radians(cfg["origin"]["lat"]))

    def m(p):                                            # lon/lat → local metres (equirectangular, for buffering)
        return ((p[0] - cfg["origin"]["lon"]) * kx, (p[1] - cfg["origin"]["lat"]) * 110540.0)

    def ll(x, y):
        return (cfg["origin"]["lon"] + x / kx, cfg["origin"]["lat"] + y / 110540.0)

    # NH 181 from the city to Mettupalayam: every piece of it between them, as one band
    nh = [w for w in ways if w["ref"] == "NH181" and "Coonoor" not in w["name"] and "Ooty" not in w["name"]
          and min(q[1] for q in w["pts"]) < METTUPALAYAM[1] + 0.004 and max(q[1] for q in w["pts"]) > 11.04
          and min(q[0] for q in w["pts"]) > 76.9 and max(q[0] for q in w["pts"]) < 76.99]
    road = shapely.ops.linemerge(shapely.MultiLineString([[m(p) for p in w["pts"]] for w in nh]))
    area = Point(0, 0).buffer(CIRCLE_M, 64).union(road.buffer(CORRIDOR_M, 16))
    area = area.union(Point(m(METTUPALAYAM)).buffer(TOWN_M, 48))
    town_h = height(*METTUPALAYAM)
    tm = m(METTUPALAYAM)
    borders = []
    for name, pick in (("Kallar (Coonoor ghat)", lambda w: w["ref"] == "NH181" and max(q[1] for q in w["pts"]) > METTUPALAYAM[1] + 0.003),
                       ("Kotagiri ghat", lambda w: w["ref"] == "SH15" and max(q[1] for q in w["pts"]) > 11.305
                        and min(q[0] for q in w["pts"]) < 76.96)):   # (SH 15 also runs east to Sathy)
        merged = shapely.ops.linemerge(shapely.MultiLineString([[m(p) for p in w["pts"]] for w in ways if pick(w)]))
        lines = list(merged.geoms) if hasattr(merged, "geoms") else [merged]
        line = max(lines, key=lambda g: g.length)                # the long one: the ghat road itself
        cs = list(line.coords)
        if math.hypot(cs[-1][0] - tm[0], cs[-1][1] - tm[1]) < math.hypot(cs[0][0] - tm[0], cs[0][1] - tm[1]):
            cs = cs[::-1]                                        # walking away from the town
        foot = None
        for i, c in enumerate(cs):
            p = ll(*c)
            if math.hypot(c[0] - tm[0], c[1] - tm[1]) > 1500.0 and height(*p) - town_h > FOOT_ABOVE:
                foot = i
                break
        if foot is None:
            print("no foot found on the road to %s" % name)
            continue
        part = cs[:foot + 1]
        area = area.union(LineString(part).buffer(GHAT_M, 8))
        fx, fz = pr.game(*ll(*part[-1]))
        bx, bz = pr.game(*ll(*part[max(0, len(part) - 6)]))
        d = math.hypot(fx - bx, fz - bz) or 1.0
        flat, flon = ll(*part[-1])[1], ll(*part[-1])[0]
        borders.append({"name": name, "x": round(fx, 1), "z": round(fz, 1), "up_x": round((fx - bx) / d, 3),
                        "up_z": round((fz - bz) / d, 3), "lat": round(flat, 5), "lon": round(flon, 5), "height": height(flon, flat)})
        print("%s: foot at %.4f N %.4f E, %.0f m (town %.0f m), %.1f km of road from its start" % (
            name, flat, flon, height(flon, flat), town_h, LineString(part).length / 1000))
    if area.geom_type != "Polygon":
        print("pieces:", [round(g.area / 1e6, 1) for g in area.geoms])
        area = max(area.geoms, key=lambda g: g.area)
    area = shapely.simplify(area, 30.0)
    ring = [ll(x, y) for x, y in area.exterior.coords]
    gj = {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"name": "Coimbatore city + the Mettupalayam corridor"},
          "geometry": {"type": "Polygon", "coordinates": [ring]}}]}
    json.dump(gj, open(path("config", "cbe_boundary.geojson"), "w"))
    json.dump(borders, open(path("godot", "assets", "landmarks", "borders.json"), "w"), indent=1)
    outline_into_borders()
    print("area %.0f km² (the circle alone %.0f km²), NH 181 %.1f km" % (area.area / 1e6, math.pi * CIRCLE_M ** 2 / 1e6, road.length / 1000))


if __name__ == "__main__":
    main()
