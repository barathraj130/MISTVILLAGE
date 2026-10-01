#!/usr/bin/env python3
"""
Find the real Coimbatore → Mettupalayam → Kotagiri road in OpenStreetMap data, sample the
30 m elevation model along it, and report / export it for the game.

Inputs (mapdata/, downloaded once):
    osm.json          Overpass export: roads, places, rivers, railways, landmarks
    N11E076.hgt.gz    1-arc-second elevation tile (lat 11–12 N, lon 76–77 E)

Output:
    godot/assets/drive/real_route.json   centreline (local metres), elevations, road names,
                                         towns and landmarks along the way

Map data © OpenStreetMap contributors (ODbL). Elevation: SRTM / Mapzen terrain tiles.
Usage:  python3 tools/build_real_route.py [--report-only]
"""
import gzip, heapq, json, math, os, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "mapdata")
OUT = os.path.join(ROOT, "godot", "assets", "drive", "real_route.json")

START = (11.0183, 76.9674)          # Coimbatore, Gandhipuram
END = (11.4216, 76.8634)            # Kotagiri town
CLASS_COST = {"motorway": 0.9, "trunk": 0.95, "primary": 1.0, "secondary": 1.6, "tertiary": 2.2,
              "trunk_link": 1.2, "primary_link": 1.2, "secondary_link": 1.8, "unclassified": 3.0}

LAT0, LON0 = START
KX = math.cos(math.radians(LAT0)) * 111320.0
KZ = 110540.0


def to_xz(lat, lon):
    """Local metres: +X east, +Z south (Godot's -Z is north)."""
    return (lon - LON0) * KX, -(lat - LAT0) * KZ


# ----------------------------------------------------------------------------- elevation
def load_dem():
    with gzip.open(os.path.join(DATA, "N11E076.hgt.gz")) as f:
        raw = f.read()
    n = int(math.sqrt(len(raw) // 2))
    dem = np.frombuffer(raw, dtype=">i2").reshape(n, n).astype(np.float32)
    dem[dem < -1000] = np.nan
    return dem, n


def dem_sample(dem, n, lat, lon):
    fy = (12.0 - lat) * (n - 1)
    fx = (lon - 76.0) * (n - 1)
    x0, y0 = int(fx), int(fy)
    tx, ty = fx - x0, fy - y0
    a, b = dem[y0, x0], dem[y0, x0 + 1]
    c, d = dem[y0 + 1, x0], dem[y0 + 1, x0 + 1]
    return float((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)


# ----------------------------------------------------------------------------- routing
def haversine(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def build_graph(elements):
    coords, adj, way_of = {}, {}, {}
    for e in elements:
        if e["type"] != "way" or "highway" not in e.get("tags", {}):
            continue
        hw = e["tags"]["highway"]
        if hw not in CLASS_COST:
            continue
        oneway = e["tags"].get("oneway") == "yes"
        # `out geom` has no node ids: shared nodes have identical coordinates
        ids = [(round(g["lat"], 7), round(g["lon"], 7)) for g in e["geometry"]]
        for nid in ids:
            coords[nid] = nid
        for i in range(len(ids) - 1):
            a, b = ids[i], ids[i + 1]
            w = haversine(coords[a], coords[b]) * CLASS_COST[hw]
            adj.setdefault(a, []).append((b, w))
            if not oneway:
                adj.setdefault(b, []).append((a, w))
            way_of[(a, b)] = way_of[(b, a)] = e["tags"]
    return coords, adj, way_of


def nearest_node(coords, adj, p):
    return min((n for n in adj), key=lambda n: haversine(coords[n], p))


def dijkstra(adj, s, t):
    dist, prev, pq = {s: 0.0}, {}, [(0.0, s)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == t:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w in adj.get(u, []):
            nd = d + w
            if nd < dist.get(v, 1e18):
                dist[v], prev[v] = nd, u
                heapq.heappush(pq, (nd, v))
    path = [t]
    while path[-1] != s:
        path.append(prev[path[-1]])
    return path[::-1]


# ----------------------------------------------------------------------------- analysis
def resample(pts, step):
    out, carry = [pts[0]], 0.0
    for a, b in zip(pts, pts[1:]):
        seg = math.dist(a, b)
        t = step - carry
        while t <= seg:
            out.append((a[0] + (b[0] - a[0]) * t / seg, a[1] + (b[1] - a[1]) * t / seg))
            t += step
        carry = seg - (t - step)
    return out


def main():
    osm = json.load(open(os.path.join(DATA, "osm.json")))
    els = osm["elements"]
    coords, adj, way_of = build_graph(els)
    s, t = nearest_node(coords, adj, START), nearest_node(coords, adj, END)
    path = dijkstra(adj, s, t)
    # carry on ~2 km out of Kotagiri on the Kodanad View Point road, so the resort sits
    # on quiet ground of its own rather than on top of the bazaar streets
    town_end_real = sum(haversine(coords[a], coords[b]) for a, b in zip(path, path[1:]))
    kod = [n for (a, b), tg in way_of.items() if "Kodanad" in tg.get("name", "") for n in (a, b)]
    cand = [n for n in set(kod) if 1800 < haversine(coords[n], END) < 2400]
    if cand:
        ext_target = max(cand, key=lambda n: haversine(coords[n], END))
        ext = dijkstra(adj, t, ext_target)
        path = path + ext[1:]
        print(f"extended {sum(haversine(coords[a], coords[b]) for a, b in zip(ext, ext[1:])):.0f} m past Kotagiri towards Kodanad")
    latlon = [coords[n] for n in path]
    names = []
    for a, b in zip(path, path[1:]):
        tg = way_of[(a, b)]
        label = tg.get("name") or tg.get("ref") or tg["highway"]
        if not names or names[-1][0] != label:
            names.append([label, tg.get("ref", ""), tg["highway"], haversine(coords[a], coords[b])])
        else:
            names[-1][3] += haversine(coords[a], coords[b])

    dem, n = load_dem()
    xz = [to_xz(*p) for p in latlon]
    step = 10.0
    rs = resample(xz, step)
    # back to lat/lon for DEM sampling
    elev = []
    for x, z in rs:
        lat = LAT0 - z / KZ
        lon = LON0 + x / KX
        elev.append(dem_sample(dem, n, lat, lon))
    elev = np.array(elev)
    # light smoothing: a road doesn't follow every 30 m DEM bump
    k = 7
    elev_s = np.convolve(np.pad(elev, k, mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="same")[k:-k]
    length = step * (len(rs) - 1)

    heading = [math.atan2(rs[i + 1][1] - rs[i][1], rs[i + 1][0] - rs[i][0]) for i in range(len(rs) - 1)]
    def turn(i, j):
        tot = 0.0
        for q in range(i, j):
            dh = (heading[q + 1] - heading[q] + math.pi) % (2 * math.pi) - math.pi
            tot += dh
        return tot
    hair = []
    i = 0
    while i < len(heading) - 8:
        tt = turn(i, i + 8)            # 80 m window
        if abs(tt) > math.radians(140):
            hair.append(i + 4)
            i += 10
        else:
            i += 1

    # places along the route
    places = []
    for e in els:
        if e["type"] == "node" and "place" in e.get("tags", {}) and "name" in e["tags"]:
            px, pz = to_xz(e["lat"], e["lon"])
            dmin, imin = min((math.hypot(px - x, pz - z), q) for q, (x, z) in enumerate(rs))
            lim = {"city": 3000, "town": 1500, "village": 400, "suburb": 500, "hamlet": 250}[e["tags"]["place"]]
            if dmin < lim:
                places.append({"name": e["tags"]["name"], "kind": e["tags"]["place"], "d": imin * step,
                               "offset": round(dmin), "xz": [round(px, 1), round(pz, 1)]})
    places.sort(key=lambda p: p["d"])
    landmarks = []
    for e in els:
        tg = e.get("tags", {})
        if e["type"] == "node" and ("tourism" in tg or "barrier" in tg):
            px, pz = to_xz(e["lat"], e["lon"])
            dmin, imin = min((math.hypot(px - x, pz - z), q) for q, (x, z) in enumerate(rs))
            if dmin < 300:
                landmarks.append({"name": tg.get("name", tg.get("tourism", tg.get("barrier"))), "d": imin * step,
                                  "offset": round(dmin), "kind": tg.get("tourism", tg.get("barrier"))})
    rivers = []
    for e in els:
        if e["type"] == "way" and e.get("tags", {}).get("waterway") == "river":
            for g in e["geometry"]:
                px, pz = to_xz(g["lat"], g["lon"])
                dmin, imin = min((math.hypot(px - x, pz - z), q) for q, (x, z) in enumerate(rs[::5]))
                if dmin < 60:
                    rivers.append({"name": e["tags"].get("name", "river"), "d": imin * 5 * step})
                    break
    ghat_i = next(q for q in range(len(elev_s)) if elev_s[q] > elev_s[0] + 150)

    print(f"Route: {length / 1000:.1f} km, {len(path)} OSM nodes")
    print(f"Elevation: start {elev_s[0]:.0f} m, min {np.nanmin(elev_s):.0f}, end {elev_s[-1]:.0f} m, "
          f"max {np.nanmax(elev_s):.0f} m")
    print(f"Climb starts at {ghat_i * step / 1000:.1f} km; ghat length {(length - ghat_i * step) / 1000:.1f} km, "
          f"average grade {(elev_s[-1] - elev_s[ghat_i]) / (length - ghat_i * step) * 100:.1f} %")
    print(f"Hairpins (>140° within 80 m): {len(hair)} at km " + ", ".join(f"{h * step / 1000:.1f}" for h in hair))
    print("Roads:")
    for nm, ref, hw, L in names:
        if L > 400:
            print(f"   {L / 1000:5.1f} km  {nm}  {ref}  ({hw})")
    print("Places passed:", ", ".join(f"{p['name']} @{p['d'] / 1000:.1f}" for p in places))
    print("Landmarks:", ", ".join(f"{l['name']} @{l['d'] / 1000:.1f}" for l in landmarks))
    print("Rivers crossed:", ", ".join(sorted({f"{r['name']} @{r['d'] / 1000:.1f}" for r in rivers})))
    if "--report-only" in sys.argv:
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({
        "source": "© OpenStreetMap contributors (ODbL); elevation SRTM via Mapzen terrain tiles",
        "origin_latlon": [LAT0, LON0], "step": step, "length": length,
        "xz": [[round(x, 2), round(z, 2)] for x, z in rs], "elev": [round(float(e), 1) for e in elev_s],
        "hairpins": [h * step for h in hair], "places": places, "landmarks": landmarks, "rivers": rivers,
        "roads": [{"name": nm, "ref": ref, "class": hw, "length": round(L)} for nm, ref, hw, L in names],
        "kotagiri_centre_d": town_end_real,
    }, open(OUT, "w"), separators=(",", ":"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
