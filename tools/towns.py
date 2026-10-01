"""
Open-world towns for the drive map (used by compile_drive_map.py).

Inside each town the map is at true 1:1 scale: the highway keeps its exact real shape there,
so the whole town (every OpenStreetMap street, building footprint and landmark) can be placed
with a single translation from real metres to game metres. Streets get their own height
profile from the real terrain and are carved into the ground like the highway. Towns whose
buildings are barely mapped (Mettupalayam, Kotagiri) are filled with generated shops and houses
along their real streets.

Map data © OpenStreetMap contributors (ODbL).
"""
import json, math, os
import numpy as np

# name: (centre lat, lon, radius m, building style)
TOWN_ZONES = {
    "Coimbatore": (11.0183, 76.9678, 1300.0, "city"),
    "Mettupalayam": (11.3010, 76.9356, 1100.0, "town"),
    "Kotagiri": (11.4230, 76.8658, 1400.0, "hill"),
}
FILES = {"Coimbatore": "town_coimbatore.json", "Mettupalayam": "town_mettupalayam.json", "Kotagiri": "town_kotagiri.json"}
WIDTH = {"trunk": 8.5, "primary": 8.0, "secondary": 7.2, "tertiary": 6.5, "unclassified": 5.5, "residential": 5.0,
         "living_street": 4.5, "service": 4.0, "road": 5.0, "pedestrian": 4.0,
         "trunk_link": 6.5, "primary_link": 6.5, "secondary_link": 6.0, "tertiary_link": 5.5}
FILL_CLASSES = {"trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street"}
POI_KINDS = {"bus_station": "Bus stand", "place_of_worship": "Temple", "marketplace": "Market", "hospital": "Hospital",
             "school": "School", "college": "College", "fuel": "Petrol bunk", "restaurant": "Restaurant", "cafe": "Café",
             "bank": "Bank", "police": "Police", "cinema": "Cinema", "townhall": "Town hall", "station": "Railway station"}


def local_xz(lat, lon, lat0, lon0):
    kx = math.cos(math.radians(lat0)) * 111320.0
    return (lon - lon0) * kx, -(lat - lat0) * 110540.0


def in_zone_mask(real_xz, origin):
    """Per real route sample: inside a town (plus a margin), where the map must stay 1:1."""
    m = np.zeros(len(real_xz), dtype=bool)
    for lat, lon, r, _ in TOWN_ZONES.values():
        cx, cz = local_xz(lat, lon, *origin)
        m |= np.hypot(real_xz[:, 0] - cx, real_xz[:, 1] - cz) < r + 120.0
    return m


def translations(real_xz, new_xz, origin):
    """Real → game offset for each town, from the route sample nearest its centre."""
    out = {}
    for name, (lat, lon, r, style) in TOWN_ZONES.items():
        cx, cz = local_xz(lat, lon, *origin)
        i = int(np.argmin(np.hypot(real_xz[:, 0] - cx, real_xz[:, 1] - cz)))
        t = new_xz[i] - real_xz[i]
        out[name] = {"t": t, "centre_real": np.array([cx, cz]), "centre": np.array([cx, cz]) + t, "radius": r, "style": style}
    return out


def _resample(pts, step):
    out = [pts[0]]
    acc = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = np.linalg.norm(b - a)
        if seg < 1e-6:
            continue
        t = step - acc
        while t <= seg:
            out.append(a + (b - a) * (t / seg))
            t += step
        acc = seg - (t - step)
    if np.linalg.norm(out[-1] - pts[-1]) > 0.5:
        out.append(pts[-1])
    return np.array(out)


def _smooth(a, w):
    if len(a) < 3 or w <= 0:
        return a
    k = np.ones(2 * w + 1) / (2 * w + 1)
    return np.convolve(np.pad(a, w, mode="edge"), k, mode="same")[w:-w]


class Grid:
    """Access to the compiler's 4 m near grids (natural, carved, proximity)."""
    def __init__(self, natural, carved, prox, gx0, gz0, cell):
        self.natural, self.carved, self.prox = natural, carved, prox
        self.gx0, self.gz0, self.cell = gx0, gz0, cell
        self.nz, self.nx = natural.shape

    def h(self, x, z, arr=None):
        arr = self.carved if arr is None else arr
        fx = np.clip(np.asarray(x) / self.cell - self.gx0, 0, self.nx - 1.001)
        fz = np.clip(np.asarray(z) / self.cell - self.gz0, 0, self.nz - 1.001)
        ix, iz = fx.astype(int), fz.astype(int)
        tx, tz = fx - ix, fz - iz
        return ((arr[iz, ix] * (1 - tx) + arr[iz, ix + 1] * tx) * (1 - tz)
                + (arr[iz + 1, ix] * (1 - tx) + arr[iz + 1, ix + 1] * tx) * tz)


def paint_town_ground(grid, towns, dem, elev0, vertical, blend=150.0):
    """Inside each town, ground comes straight from the real terrain (1:1), blended at the edge."""
    for name, tw in towns.items():
        c, r, t = tw["centre"], tw["radius"], tw["t"]
        i0 = max(int((c[0] - r - blend) / grid.cell) - grid.gx0, 0)
        i1 = min(int((c[0] + r + blend) / grid.cell) - grid.gx0 + 1, grid.nx)
        j0 = max(int((c[1] - r - blend) / grid.cell) - grid.gz0, 0)
        j1 = min(int((c[1] + r + blend) / grid.cell) - grid.gz0 + 1, grid.nz)
        X, Z = np.meshgrid((np.arange(i0, i1) + grid.gx0) * grid.cell, (np.arange(j0, j1) + grid.gz0) * grid.cell)
        dist = np.hypot(X - c[0], Z - c[1])
        w = 1.0 - np.clip((dist - r) / blend, 0, 1)
        w = w * w * (3 - 2 * w)
        ht = (dem.at(X - t[0], Z - t[1]) - elev0) * vertical
        cur = grid.natural[j0:j1, i0:i1]
        cur_f = np.where(np.isnan(cur), ht, cur)
        grid.natural[j0:j1, i0:i1] = np.where(w > 0, cur_f * (1 - w) + ht * w, cur).astype(np.float32)


HIGHWAY_HALF = 3.6        # the drive road's asphalt half-width (route.gd ROAD_HALF)


def _street_graph(osm, to_game, c, radius, near_route, nearest_route, route_xz, route_y, grid, town):
    """One authoritative street network for a town: OSM ways are split at their real junctions
    (vertices shared by two or more ways), so every street piece starts and ends on a node that the
    pieces meeting there share exactly. Streets that reach the highway are extended to its edge and
    end on a 'highway' node tied to a route sample; streets leaving the town end on an 'edge' node.
    Mesh, collision, GPS, minimap and the validator in Godot all read these nodes."""
    ways = []
    use = {}
    for e in osm:
        tg = e.get("tags", {})
        if e["type"] != "way" or tg.get("highway") not in WIDTH:
            continue
        keys = [(round(g["lat"], 7), round(g["lon"], 7)) for g in e["geometry"]]
        if len(keys) < 2:
            continue
        ways.append((keys, tg))
        for k in set(keys):
            use[k] = use.get(k, 0) + 1
    nodes = {}                     # id -> {x, z, y, kind, route_i?}
    key_id = {}

    def node(kind, x, z, key=None, route_i=None):
        if key is not None and key in key_id:
            return key_id[key]
        nid = "%s%d" % (town[0], len(nodes))
        nodes[nid] = {"x": round(float(x), 2), "z": round(float(z), 2), "kind": kind}
        if route_i is not None:
            nodes[nid]["route_i"] = int(route_i)
        if key is not None:
            key_id[key] = nid
        return nid

    streets = []
    for keys, tg in ways:
        # split the way at every junction vertex
        cut = [0] + [i for i in range(1, len(keys) - 1) if use[keys[i]] > 1] + [len(keys) - 1]
        for a, b in zip(cut, cut[1:]):
            seg = keys[a:b + 1]
            raw = np.array([to_game(*k) for k in seg])
            pts = _resample(raw, 3.0)
            pts[0], pts[-1] = raw[0], raw[-1]
            inside = np.hypot(pts[:, 0] - c[0], pts[:, 1] - c[1]) < radius
            on_hw = np.array([near_route(p, 7.0) for p in pts])
            keep = inside & ~on_hw
            i = 0
            n = len(pts)
            while i < n:
                if not keep[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < n and keep[j + 1]:
                    j += 1
                run = [pts[k] for k in range(i, j + 1)]
                ends = []
                for side, idx, nxt in ((0, i, i - 1), (1, j, j + 1)):
                    p_end = pts[idx]
                    if (idx == 0 and side == 0) or (idx == n - 1 and side == 1):
                        k = seg[0] if side == 0 else seg[-1]
                        ends.append(node("junction" if use[k] > 1 else "end", p_end[0], p_end[1], key=k))
                    elif on_hw[nxt]:
                        # meets the highway: run on to its edge
                        ri = nearest_route(p_end)
                        rp = route_xz[ri]
                        d = p_end - rp
                        edge = rp + d / max(np.linalg.norm(d), 1e-6) * (HIGHWAY_HALF - 0.4)
                        if side == 0:
                            run.insert(0, edge)
                        else:
                            run.append(edge)
                        ends.append(node("highway", edge[0], edge[1], route_i=ri))
                    else:
                        ends.append(node("edge", p_end[0], p_end[1]))
                run = np.array(run)
                if len(run) >= 2 and np.linalg.norm(np.diff(run, axis=0), axis=1).sum() > 1.0:
                    streets.append((run, tg, ends[0], ends[1]))
                i = j + 1
    # heights: one height per node, street profiles pinned to it at both ends
    for nid, nd in nodes.items():
        if nd["kind"] == "highway":
            nd["y"] = round(float(route_y[nd["route_i"]]), 2)
        else:
            nd["y"] = round(float(grid.h(nd["x"], nd["z"], grid.natural)), 2)
    out = []
    for pts, tg, a, b in streets:
        y = _smooth(grid.h(pts[:, 0], pts[:, 1], grid.natural), 4)
        cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
        wa = np.clip(1.0 - cum / 15.0, 0, 1)
        wb = np.clip(1.0 - (cum[-1] - cum) / 15.0, 0, 1)
        y = y + (nodes[a]["y"] - y[0]) * wa + (nodes[b]["y"] - y[-1]) * wb
        y[0], y[-1] = nodes[a]["y"], nodes[b]["y"]
        out.append({"name": tg.get("name", ""), "class": tg["highway"], "width": WIDTH[tg["highway"]],
                    "oneway": tg.get("oneway") == "yes", "a": a, "b": b,
                    "pts": np.round(np.column_stack([pts[:, 0], y + 0.02, pts[:, 1]]), 2).tolist()})
    return out, nodes


def _settle_streets(st_out, nodes, grid):
    """Crossing streets re-carve each other's beds, so after carving every street (and its nodes)
    takes its height from the final ground: the surface always sits on the terrain it drew."""
    for nid, nd in nodes.items():
        if nd["kind"] != "highway":
            nd["y"] = round(float(grid.h(nd["x"], nd["z"])) + 0.25, 2)
    for s_ in st_out:
        p = np.array(s_["pts"])
        y = _smooth(grid.h(p[:, 0], p[:, 2]) + 0.25, 1)
        a, b = nodes[s_["a"]]["y"], nodes[s_["b"]]["y"]
        cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(p[:, [0, 2]], axis=0), axis=1))])
        wa = np.clip(1.0 - cum / 10.0, 0, 1)
        wb = np.clip(1.0 - (cum[-1] - cum) / 10.0, 0, 1)
        y = y + (a - y[0]) * wa + (b - y[-1]) * wb
        y[0], y[-1] = a, b
        p[:, 1] = y + 0.02
        s_["pts"] = np.round(p, 2).tolist()


def build_towns(towns, grid, route_xz, data_dir, rng_seed=7, route_y=None):
    """Streets, buildings and POIs for every town, in game coordinates. Carves streets into grid.carved."""
    rng = np.random.default_rng(rng_seed)
    # route occupancy, to drop OSM ways that are the highway itself
    rx, rz = route_xz[:, 0], route_xz[:, 1]
    bucket = {}
    for i in range(0, len(rx)):
        bucket.setdefault((int(rx[i] // 25), int(rz[i] // 25)), []).append(i)

    def near_route(p, r):
        kx, kz = int(p[0] // 25), int(p[1] // 25)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for i in bucket.get((kx + dx, kz + dz), ()):
                    if (rx[i] - p[0]) ** 2 + (rz[i] - p[1]) ** 2 < r * r:
                        return True
        return False

    out = {}
    for name, tw in towns.items():
        path = os.path.join(data_dir, FILES[name])
        if not os.path.exists(path):
            continue
        osm = json.load(open(path))["elements"]
        origin = tw["origin"]
        t, c, radius = tw["t"], tw["centre"], tw["radius"]
        to_game = lambda lat, lon: np.array(local_xz(lat, lon, *origin)) + t

        # ---- streets: a junction graph -------------------------------------------------------
        def nearest_route(p):
            kx, kz = int(p[0] // 25), int(p[1] // 25)
            best, bd = 0, 1e18
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for i in bucket.get((kx + dx, kz + dz), ()):
                        dd = (rx[i] - p[0]) ** 2 + (rz[i] - p[1]) ** 2
                        if dd < bd:
                            best, bd = i, dd
            return best
        st_out, nodes = _street_graph(osm, to_game, c, radius, near_route, nearest_route, route_xz,
                                      route_y if route_y is not None else np.zeros(len(route_xz)), grid, name)
        for s_ in st_out:
            p = np.array(s_["pts"])
            _carve(grid, p[:, [0, 2]], p[:, 1] - 0.02, s_["width"])
        _settle_streets(st_out, nodes, grid)

        # ---- buildings ------------------------------------------------------------------------
        occ = _Occupancy(c, radius + 60.0)
        for s in st_out:
            p = np.array(s["pts"])
            occ.mark_line(p[:, [0, 2]], s["width"] * 0.5 + 1.0)
        occ.mark_line(route_xz[np.hypot(rx - c[0], rz - c[1]) < radius + 80.0], 6.5)
        levels_default = {"city": (2, 4), "town": (1, 3), "hill": (1, 2)}[tw["style"]]
        buildings = []
        for e in osm:
            tg = e.get("tags", {})
            if e["type"] != "way" or "building" not in tg:
                continue
            poly = np.array([to_game(g["lat"], g["lon"]) for g in e["geometry"]])
            if len(poly) < 4:
                continue
            poly = poly[:-1] if np.allclose(poly[0], poly[-1]) else poly
            area = _area(poly)
            if area < 12.0 or area > 6000.0 or np.hypot(*(poly.mean(0) - c)) > radius:
                continue
            if occ.hits(poly):
                continue
            lv = tg.get("building:levels")
            try:
                lv = int(float(lv))
            except (TypeError, ValueError):
                lv = int(rng.integers(levels_default[0], levels_default[1] + 1))
            buildings.append(_building(poly, grid, lv, tw["style"], rng, "osm"))
            occ.mark_poly(poly)
        n_osm = len(buildings)
        # fill thinly-mapped towns along their real streets
        if True:                                   # every town: OSM alone leaves whole blocks empty
            for s in st_out:
                if s["class"] not in FILL_CLASSES:
                    continue
                p = np.array(s["pts"])[:, [0, 2]]
                half = s["width"] * 0.5
                d = rng.uniform(0, 6)
                seglen = np.linalg.norm(np.diff(p, axis=0), axis=1)
                cum = np.concatenate([[0], np.cumsum(seglen)])
                while d < cum[-1] - 6:
                    i = min(int(np.searchsorted(cum, d)) - 1, len(p) - 2)
                    i = max(i, 0)
                    tdir = (p[i + 1] - p[i]) / max(seglen[i], 1e-6)
                    left = np.array([tdir[1], -tdir[0]])
                    base = p[i] + tdir * (d - cum[i])
                    wdt = rng.uniform(6.5, 11.0)
                    dep = rng.uniform(7.0, 12.0)
                    for side in (1.0, -1.0):
                        if rng.random() < 0.18:
                            continue                       # gaps: lanes, yards, empty plots
                        f0 = base + left * side * (half + 1.6)
                        f1 = f0 + left * side * dep
                        poly = np.array([f0 - tdir * wdt / 2, f0 + tdir * wdt / 2, f1 + tdir * wdt / 2, f1 - tdir * wdt / 2])
                        if np.hypot(*(poly.mean(0) - c)) > radius or occ.hits(poly):
                            continue
                        lv = int(rng.integers(levels_default[0], levels_default[1] + 1))
                        buildings.append(_building(poly, grid, lv, tw["style"], rng, "gen"))
                        occ.mark_poly(poly)
                    d += wdt + rng.uniform(0.3, 2.5)

        # buildings count as occupied ground: trees and props keep off them
        for b in buildings:
            poly = np.array(b["poly"])
            lo = ((poly.min(0) - 2.0) / grid.cell).astype(int) - [grid.gx0, grid.gz0]
            hi = ((poly.max(0) + 2.0) / grid.cell).astype(int) - [grid.gx0, grid.gz0] + 1
            lo = np.clip(lo, 0, [grid.nx - 1, grid.nz - 1])
            hi = np.clip(hi, 0, [grid.nx - 1, grid.nz - 1])
            grid.prox[lo[1]:hi[1], lo[0]:hi[0]] = 1.0

        # ---- landmarks ------------------------------------------------------------------------
        pois = []
        for e in osm:
            tg = e.get("tags", {})
            kind = tg.get("amenity") or ("station" if tg.get("railway") == "station" else None) or tg.get("tourism")
            if not kind or not tg.get("name"):
                continue
            if e["type"] == "node":
                g = to_game(e["lat"], e["lon"])
            elif e.get("geometry"):
                g = np.mean([to_game(q["lat"], q["lon"]) for q in e["geometry"]], axis=0)
            else:
                continue
            if np.hypot(*(g - c)) > radius:
                continue
            pois.append({"name": tg["name"], "kind": POI_KINDS.get(kind, kind.replace("_", " ").title()),
                         "x": round(float(g[0]), 1), "y": round(float(grid.h(g[0], g[1])), 1), "z": round(float(g[1]), 1)})
        rails = []
        for e in osm:
            tg = e.get("tags", {})
            if e["type"] == "way" and tg.get("railway") in ("rail", "narrow_gauge"):
                pts = np.array([to_game(g["lat"], g["lon"]) for g in e["geometry"]])
                pts = pts[np.hypot(pts[:, 0] - c[0], pts[:, 1] - c[1]) < radius]
                if len(pts) > 1:
                    rails.append(np.round(pts, 1).tolist())
        out[name] = {"centre": [round(float(c[0]), 1), round(float(c[1]), 1)], "radius": radius, "style": tw["style"],
                     "streets": st_out, "nodes": nodes, "buildings": buildings, "pois": pois, "rails": rails,
                     "stats": {"streets": len(st_out), "osm_buildings": n_osm, "generated": len(buildings) - n_osm,
                               "pois": len(pois)}}
    return out


def _carve(grid, pts, y, width):
    """Flatten a street bed into grid.carved (and mark proximity) — like the highway, narrower."""
    flat, blend = width * 0.5 + 1.2, width * 0.5 + 9.0
    r = int(blend / grid.cell) + 1
    for (x, z), yy in zip(pts, y):
        cx, cz = int(round(x / grid.cell)) - grid.gx0, int(round(z / grid.cell)) - grid.gz0
        i0, i1, j0, j1 = max(cx - r, 0), min(cx + r + 1, grid.nx), max(cz - r, 0), min(cz + r + 1, grid.nz)
        if i0 >= i1 or j0 >= j1:
            continue
        X, Z = np.meshgrid((np.arange(i0, i1) + grid.gx0) * grid.cell - x, (np.arange(j0, j1) + grid.gz0) * grid.cell - z)
        dd = np.hypot(X, Z)
        wt = np.where(dd <= flat, 1.0, 1.0 - np.clip((dd - flat) / (blend - flat), 0, 1))
        wt = np.where(dd < blend, wt, 0.0)
        cur = grid.carved[j0:j1, i0:i1]
        ok = ~np.isnan(cur)
        grid.carved[j0:j1, i0:i1] = np.where(ok & (wt > 0), cur * (1 - wt) + (yy - 0.25) * wt, cur)
        pr = grid.prox[j0:j1, i0:i1]
        np.maximum(pr, np.clip(1.0 - dd / (width * 0.5 + 6.0), 0, 1), out=pr)


class _Occupancy:
    """1 m raster of what's taken (streets, highway, buildings) so buildings don't overlap."""
    def __init__(self, c, r):
        self.o = np.array(c) - r
        self.n = int(2 * r) + 1
        self.g = np.zeros((self.n, self.n), dtype=bool)

    def _ij(self, p):
        return (np.asarray(p) - self.o).astype(int)

    def mark_line(self, pts, half):
        for p in pts:
            i, j = self._ij(p)
            h = int(half) + 1
            self.g[max(j - h, 0):max(j + h, 0), max(i - h, 0):max(i + h, 0)] = True

    def _cells(self, poly):
        lo = np.floor(poly.min(0) - self.o).astype(int)
        hi = np.ceil(poly.max(0) - self.o).astype(int)
        lo = np.clip(lo, 0, self.n - 1)
        hi = np.clip(hi, 0, self.n - 1)
        if (hi <= lo).any():
            return None
        X, Z = np.meshgrid(np.arange(lo[0], hi[0]) + 0.5 + self.o[0], np.arange(lo[1], hi[1]) + 0.5 + self.o[1])
        inside = _points_in_poly(X, Z, poly)
        return lo, hi, inside

    def hits(self, poly):
        r = self._cells(poly)
        if r is None:
            return True
        lo, hi, inside = r
        return bool((self.g[lo[1]:hi[1], lo[0]:hi[0]] & inside).any())

    def mark_poly(self, poly):
        r = self._cells(poly)
        if r is not None:
            lo, hi, inside = r
            self.g[lo[1]:hi[1], lo[0]:hi[0]] |= inside


def _points_in_poly(X, Z, poly):
    inside = np.zeros(X.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        cond = ((z1 > Z) != (z2 > Z)) & (X < (x2 - x1) * (Z - z1) / (z2 - z1 + 1e-12) + x1)
        inside ^= cond
    return inside


def _area(poly):
    x, z = poly[:, 0], poly[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(z, 1)) - np.dot(z, np.roll(x, 1)))


PALETTE = [(0.62, 0.48, 0.30), (0.55, 0.33, 0.26), (0.36, 0.52, 0.47), (0.70, 0.62, 0.48), (0.45, 0.47, 0.62),
           (0.75, 0.55, 0.22), (0.66, 0.66, 0.60), (0.50, 0.60, 0.35), (0.80, 0.78, 0.72), (0.72, 0.40, 0.35)]
ROOFS = [(0.35, 0.07, 0.05), (0.06, 0.20, 0.10), (0.07, 0.14, 0.32), (0.40, 0.40, 0.40)]


def _building(poly, grid, levels, style, rng, source):
    ys = grid.h(poly[:, 0], poly[:, 1])
    base = float(np.nanmin(ys)) - 0.3
    col = PALETTE[int(rng.integers(len(PALETTE)))]
    b = {"poly": np.round(poly, 2).tolist(), "base": round(base, 2), "floors": int(max(1, min(levels, 12))),
         "color": col, "src": source, "shop": bool(rng.random() < (0.7 if style != "hill" else 0.45))}
    if style == "hill":
        b["roof"] = ROOFS[int(rng.integers(len(ROOFS)))]
    return b
