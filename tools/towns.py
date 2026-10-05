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
                        # meets the highway: carry straight on along the street's own heading until
                        # it reaches the highway's edge (no sideways kink into the junction)
                        prev = pts[min(idx + 1, n - 1)] if side == 0 else pts[max(idx - 1, 0)]
                        heading = p_end - prev
                        hn = np.linalg.norm(heading)
                        heading = heading / max(hn, 1e-6)
                        edge = None
                        for step in (np.arange(0.25, 14.0, 0.25) if hn > 0.1 else []):
                            q = p_end + heading * step
                            ri = nearest_route(q)
                            if np.linalg.norm(q - route_xz[ri]) < HIGHWAY_HALF - 0.4:
                                edge = q
                                break
                        if edge is None:                  # running alongside: fall back to the nearest edge point
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


# ----------------------------------------------------------------------------- network repair
def _slen(pts):
    p = np.asarray(pts)[:, [0, 2]]
    return float(np.linalg.norm(np.diff(p, axis=0), axis=1).sum())


def _repair_network(st_out, nodes, grid, town):
    """Make the street graph drivable everywhere: drop stubs that stop in a field at the edge of
    the mapped area, join dead ends that stop just short of another street, link stray street
    groups to the main network (or drop them if they're far from everything)."""
    stats = {"pruned_edge": 0, "pruned_stub": 0, "joined_ends": 0, "linked_islands": 0, "dropped_islands": 0}

    def degree():
        d = {}
        for st in st_out:
            for e in (st["a"], st["b"]):
                d[e] = d.get(e, 0) + 1
        return d

    # 1) streets that run off the mapped area into fields, and tiny dead-end stubs
    deg = degree()
    keep = []
    for st in st_out:
        L = _slen(st["pts"])
        leaf_edge = any(nodes[e]["kind"] == "edge" and deg.get(e, 0) == 1 for e in (st["a"], st["b"]))
        leaf_end = any(nodes[e]["kind"] == "end" and deg.get(e, 0) == 1 for e in (st["a"], st["b"]))
        if leaf_edge and L < 160.0:
            stats["pruned_edge"] += 1
            continue
        if leaf_end and L < 18.0 and not all(deg.get(e, 0) == 1 for e in (st["a"], st["b"])):
            stats["pruned_stub"] += 1
            continue
        keep.append(st)
    st_out[:] = keep

    def bucket():
        b = {}
        for si, st in enumerate(st_out):
            for k, q in enumerate(st["pts"]):
                b.setdefault((int(q[0] // 10), int(q[2] // 10)), []).append((si, k))
        return b

    def nearest(p, exclude, bk, r=15.0):
        best, bd = None, r
        kx, kz = int(p[0] // 10), int(p[1] // 10)
        rr = int(r // 10) + 1
        for dx in range(-rr, rr + 1):
            for dz in range(-rr, rr + 1):
                for si, k in bk.get((kx + dx, kz + dz), ()):
                    if si in exclude:
                        continue
                    q = st_out[si]["pts"][k]
                    d = math.hypot(q[0] - p[0], q[2] - p[1])
                    if d < bd:
                        best, bd = (si, k), d
        return best, bd

    def split(si, k):
        """Return a node id at vertex k of street si, splitting the street there if needed."""
        st = st_out[si]
        n = len(st["pts"])
        if k <= 1:
            return st["a"]
        if k >= n - 2:
            return st["b"]
        q = st["pts"][k]
        nid = "%s%d" % (town[0], len(nodes) + 1000)
        while nid in nodes:
            nid += "x"
        nodes[nid] = {"x": q[0], "z": q[2], "kind": "junction", "y": q[1]}
        a_part = dict(st, pts=st["pts"][:k + 1], b=nid)
        b_part = dict(st, pts=st["pts"][k:], a=nid)
        st_out[si] = a_part
        st_out.append(b_part)
        return nid

    def connector(na, nb, like):
        a, b = nodes[na], nodes[nb]
        A, B = np.array([a["x"], a["z"]]), np.array([b["x"], b["z"]])
        pts = _resample(np.array([A, B]), 3.0)
        y = grid.h(pts[:, 0], pts[:, 1], grid.natural)
        st_out.append({"name": "", "class": like["class"] if like["class"] not in ("trunk", "primary") else "residential",
                       "width": min(like["width"], 6.0), "oneway": False, "a": na, "b": nb,
                       "pts": np.round(np.column_stack([pts[:, 0], y + 0.02, pts[:, 1]]), 2).tolist()})

    # 2) dead ends that stop within 15 m of another street: join them up
    deg = degree()
    bk = bucket()
    plans = []
    for si, st in enumerate(st_out):
        for end in ("a", "b"):
            nid = st[end]
            if nodes[nid]["kind"] not in ("end", "edge") or deg.get(nid, 0) != 1:
                continue
            p = (nodes[nid]["x"], nodes[nid]["z"])
            hit, d = nearest(p, {si}, bk, 15.0)
            if hit and d > 0.5:
                plans.append((nid, hit, si))
    done = set()
    for nid, (ti, k), si in sorted(plans, key=lambda t: (t[1][0], -t[1][1])):
        if nid in done:
            continue
        like = st_out[si]
        target = split(ti, k)
        if target != nid:
            connector(nid, target, like)
            nodes[nid]["kind"] = "junction"
            done.add(nid)
            stats["joined_ends"] += 1

    # 2b) dead ends pointing at a street up to 35 m ahead: carry them on to it (as the street would)
    deg = degree()
    bk = bucket()
    plans = []
    for si, st in enumerate(st_out):
        for end in ("a", "b"):
            nid = st[end]
            if nodes[nid]["kind"] not in ("end", "edge") or deg.get(nid, 0) != 1 or len(st["pts"]) < 3:
                continue
            P = st["pts"]
            tip, prev = (P[0], P[2]) if end == "a" else (P[-1], P[-3])
            head = np.array([tip[0] - prev[0], tip[2] - prev[2]])
            head = head / max(np.linalg.norm(head), 1e-6)
            best = None
            for step in np.arange(3.0, 36.0, 3.0):
                q = (tip[0] + head[0] * step, tip[2] + head[1] * step)
                hit, d = nearest(q, {si}, bk, 4.0)
                if hit:
                    best = hit
                    break
            if best:
                plans.append((nid, best, si))
    for nid, (ti, k), si in sorted(plans, key=lambda t: (t[1][0], -t[1][1])):
        if nid in done or ti >= len(st_out) or k >= len(st_out[ti]["pts"]):
            continue
        target = split(ti, k)
        if target != nid:
            connector(nid, target, st_out[si])
            nodes[nid]["kind"] = "junction"
            done.add(nid)
            stats["joined_ends"] += 1

    # 3) stray street groups: link to the main (highway-connected) network, or drop them
    for _round in range(3):
        adj = {}
        for si, st in enumerate(st_out):
            adj.setdefault(st["a"], []).append(si)
            adj.setdefault(st["b"], []).append(si)
        comp_of, comps = {}, []
        for start in adj:
            if start in comp_of:
                continue
            stack, members, streets = [start], [start], set()
            comp_of[start] = len(comps)
            while stack:
                x = stack.pop()
                for si in adj[x]:
                    streets.add(si)
                    for y in (st_out[si]["a"], st_out[si]["b"]):
                        if y not in comp_of:
                            comp_of[y] = len(comps)
                            stack.append(y)
                            members.append(y)
            comps.append((members, streets))
        main = {ci for ci, (m, _) in enumerate(comps) if any(nodes[x]["kind"] == "highway" for x in m)}
        if not main or len(comps) == len(main):
            break
        main_streets = set().union(*(comps[ci][1] for ci in main))
        mb = {}
        for si in main_streets:
            for k, q in enumerate(st_out[si]["pts"]):
                mb.setdefault((int(q[0] // 10), int(q[2] // 10)), []).append((si, k))
        drop = set()
        links = []
        for ci, (members, streets) in enumerate(comps):
            if ci in main:
                continue
            best = None
            for si in streets:
                for k, q in enumerate(st_out[si]["pts"]):
                    hit, d = nearest((q[0], q[2]), streets, mb, 70.0)
                    if hit and (best is None or d < best[0]):
                        best = (d, si, k, hit)
            if best:
                links.append(best)
            else:
                drop |= streets
        for d, si, k, (ti, tk) in sorted(links, key=lambda t: -t[1]):
            na = split(si, k)
            nb = split(ti, tk)
            if na != nb:
                connector(na, nb, st_out[si])
                stats["linked_islands"] += 1
        if drop:
            stats["dropped_islands"] += len(drop)
            st_out[:] = [st for i, st in enumerate(st_out) if i not in drop]
    used = {st["a"] for st in st_out} | {st["b"] for st in st_out}
    for nid in list(nodes):
        if nid not in used:
            del nodes[nid]
    print("  network", town, stats)
    return stats


# ----------------------------------------------------------------------------- parking
LOT_SIZE = {"Hospital": (26, 16), "Bus stand": (30, 18), "Market": (26, 16), "Temple": (22, 14), "Cinema": (26, 16),
            "College": (24, 16), "School": (20, 12), "Railway station": (30, 18), "Town hall": (22, 14),
            "Hotel": (18, 12), "Guest House": (14, 10), "Bank": (16, 10), "Restaurant": (16, 10), "Café": (12, 9),
            "Police": (16, 10), "Theatre": (22, 14)}


def _lot_poly(o, t, n, along, depth):
    return np.array([o - t * along / 2, o + t * along / 2, o + t * along / 2 + n * depth, o - t * along / 2 + n * depth])


def _place_lot(st_out, si, k_hint, side_pt, size, occ, grid, kind, name):
    """Try to fit a lot beside street si near vertex k_hint, on the side facing side_pt."""
    st = st_out[si]
    P = np.array(st["pts"])
    n = len(P)
    cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P[:, [0, 2]], axis=0), axis=1))])
    along, depth = size
    for shift in (0, 8, -8, 16, -16, 26, -26, 38, -38, 52, -52):
        k = int(np.clip(np.searchsorted(cum, cum[k_hint] + shift), 1, n - 2))
        if cum[k] < along / 2 + 6 or cum[-1] - cum[k] < along / 2 + 6:
            continue
        c = P[k, [0, 2]]
        t = P[min(k + 1, n - 1), [0, 2]] - P[max(k - 1, 0), [0, 2]]
        t = t / max(np.linalg.norm(t), 1e-6)
        nrm = np.array([-t[1], t[0]])
        sides = [1.0, -1.0] if np.dot(nrm, np.asarray(side_pt) - c) >= 0 else [-1.0, 1.0]
        for sd in sides:
            nn = nrm * sd
            o = c + nn * (st["width"] * 0.5 + 0.4)
            poly = _lot_poly(o, t, nn, along, depth)
            test = _lot_poly(o + nn * 1.4, t, nn, along - 1.0, depth - 1.4)
            if occ.hits(test):
                continue
            occ.mark_poly(poly)
            y = float(P[k, 1]) - 0.02
            _flatten(grid, poly, y)
            return {"poly": np.round(poly, 2).tolist(), "y": round(y, 2), "street": si, "side": sd,
                    "s0": round(float(cum[k] - along / 2), 1), "s1": round(float(cum[k] + along / 2), 1),
                    "t": [round(float(t[0]), 4), round(float(t[1]), 4)], "n": [round(float(nn[0]), 4), round(float(nn[1]), 4)],
                    "kind": kind, "name": name}
    return None


def _flatten(grid, poly, y):
    lo = ((poly.min(0) - 4.0) / grid.cell).astype(int) - [grid.gx0, grid.gz0]
    hi = ((poly.max(0) + 4.0) / grid.cell).astype(int) - [grid.gx0, grid.gz0] + 1
    lo = np.clip(lo, 0, [grid.nx - 1, grid.nz - 1])
    hi = np.clip(hi, 0, [grid.nx - 1, grid.nz - 1])
    X, Z = np.meshgrid((np.arange(lo[0], hi[0]) + grid.gx0) * grid.cell, (np.arange(lo[1], hi[1]) + grid.gz0) * grid.cell)
    inside = _points_in_poly(X, Z, poly)
    cur = grid.carved[lo[1]:hi[1], lo[0]:hi[0]]
    grid.carved[lo[1]:hi[1], lo[0]:hi[0]] = np.where(inside & ~np.isnan(cur), y - 0.08, cur)
    grid.prox[lo[1]:hi[1], lo[0]:hi[0]] = np.where(inside, 1.0, grid.prox[lo[1]:hi[1], lo[0]:hi[0]])


def _street_index(st_out):
    b = {}
    for si, st in enumerate(st_out):
        for k, q in enumerate(st["pts"]):
            b.setdefault((int(q[0] // 20), int(q[2] // 20)), []).append((si, k))
    return b


def _nearest_street(b, st_out, p, r=60.0, classes=None):
    best, bd = None, r
    kx, kz = int(p[0] // 20), int(p[1] // 20)
    rr = int(r // 20) + 1
    for dx in range(-rr, rr + 1):
        for dz in range(-rr, rr + 1):
            for si, k in b.get((kx + dx, kz + dz), ()):
                if classes and st_out[si]["class"] not in classes:
                    continue
                q = st_out[si]["pts"][k]
                d = math.hypot(q[0] - p[0], q[2] - p[1])
                if d < bd:
                    best, bd = (si, k), d
    return best


# ----------------------------------------------------------------------------- keep the ground under the asphalt
def _bilinear(grid, x, z):
    return grid.h(np.asarray(x), np.asarray(z))


def road_pokes(grid, segments):
    """How many road samples (centre and both edges) have ground above the surface."""
    n = 0
    for xz, ys, half in segments:
        if len(xz) < 2:
            continue
        t = np.gradient(xz, axis=0)
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
        nrm = np.column_stack([-t[:, 1], t[:, 0]])
        for off in (0.0, half * 0.9, -half * 0.9):
            q = xz + nrm * off
            g = _bilinear(grid, q[:, 0], q[:, 1])
            n += int(np.sum(np.nan_to_num(g, nan=-1e9) > ys - 0.02))
    return n


def sink_under_roads(grid, segments, margin=6.0, clearance=0.3):
    """Every ground point within half-width + margin of a road goes to at least `clearance` below
    the road surface right beside it (measured to the nearest point on the road's centreline, so
    steep streets keep their slope). The ground mesh is linear between 4 m grid points, so a single
    high point beside a narrow street would otherwise lift grass up through the asphalt. Beyond the
    edge the limit rises 15 cm per metre, so a neighbouring road's ground isn't dragged down."""
    cell = grid.cell
    for xz, ys, half in segments:
        r = half + margin
        rr = int(r / cell) + 2
        for i in range(len(xz) - 1):
            a, b = xz[i], xz[i + 1]
            ya, yb = ys[i], ys[i + 1]
            mid = (a + b) * 0.5
            cx, cz = int(round(mid[0] / cell)) - grid.gx0, int(round(mid[1] / cell)) - grid.gz0
            i0, i1, j0, j1 = max(cx - rr, 0), min(cx + rr + 1, grid.nx), max(cz - rr, 0), min(cz + rr + 1, grid.nz)
            if i0 >= i1 or j0 >= j1:
                continue
            X, Z = np.meshgrid((np.arange(i0, i1) + grid.gx0) * cell, (np.arange(j0, j1) + grid.gz0) * cell)
            ab = b - a
            L2 = max(float(ab @ ab), 1e-9)
            t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / L2, 0.0, 1.0)
            px, pz = a[0] + ab[0] * t, a[1] + ab[1] * t
            d = np.hypot(X - px, Z - pz)
            yroad = ya + (yb - ya) * t
            lim = yroad - clearance + 0.15 * np.maximum(d - half, 0.0)
            cur = grid.carved[j0:j1, i0:i1]
            grid.carved[j0:j1, i0:i1] = np.where((d <= r) & ~np.isnan(cur) & (cur > lim), lim, cur)


def road_floats(grid, segments, gap=0.8):
    n = 0
    for xz, ys, half in segments:
        g = _bilinear(grid, xz[:, 0], xz[:, 1])
        n += int(np.sum(np.nan_to_num(ys - g, nan=0.0) > gap))
    return n


def town_road_segments(towns_out):
    segs = []
    for tw in towns_out.values():
        for st in tw["streets"]:
            p = np.array(st["pts"])
            if len(p) >= 2:
                segs.append((p[:, [0, 2]], p[:, 1], st["width"] * 0.5))
        for lot in tw.get("parking", []):
            poly = np.array(lot["poly"])
            c = poly.mean(0)
            pts = np.array([c, (poly[0] + poly[2]) / 2, (poly[1] + poly[3]) / 2] + list(poly))
            segs.append((pts, np.full(len(pts), lot["y"]), 4.0))
    return segs


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
        net_stats = _repair_network(st_out, nodes, grid, name)
        for s_ in st_out:
            p = np.array(s_["pts"])
            _carve(grid, p[:, [0, 2]], p[:, 1] - 0.02, s_["width"])
        _settle_streets(st_out, nodes, grid)

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
        # ---- parking: a lot beside every shop-type place, plus public lots along main roads -----
        lots = []
        sb = _street_index(st_out)
        drivable = {"trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "road"}
        for poi in pois:
            hit = _nearest_street(sb, st_out, (poi["x"], poi["z"]), 70.0, drivable)
            if not hit:
                continue
            size = LOT_SIZE.get(poi["kind"], (14, 10))
            # full lot, then a smaller one, then a few bays: dense blocks still get somewhere to stop
            for sz in (size, (max(size[0] * 0.6, 10), max(size[1] * 0.7, 7)), (8, 6)):
                lot = _place_lot(st_out, hit[0], hit[1], (poi["x"], poi["z"]), sz, occ, grid, poi["kind"], poi["name"])
                if lot:
                    lots.append(lot)
                    break
        for si, st in enumerate(st_out):
            if st["class"] not in ("primary", "secondary", "tertiary", "trunk"):
                continue
            L = _slen(st["pts"])
            k = 0
            d = 120.0
            P = np.array(st["pts"])
            cum = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P[:, [0, 2]], axis=0), axis=1))])
            while d < L - 60.0:
                k = int(np.searchsorted(cum, d))
                side_pt = P[k, [0, 2]] + rng.choice([-1, 1]) * np.array([1.0, 1.0])
                lot = _place_lot(st_out, si, k, side_pt, (20, 12), occ, grid, "Parking", "Public parking")
                if lot:
                    lots.append(lot)
                d += 280.0
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

        rails = []
        for e in osm:
            tg = e.get("tags", {})
            if e["type"] == "way" and tg.get("railway") in ("rail", "narrow_gauge"):
                pts = np.array([to_game(g["lat"], g["lon"]) for g in e["geometry"]])
                pts = pts[np.hypot(pts[:, 0] - c[0], pts[:, 1] - c[1]) < radius]
                if len(pts) > 1:
                    rails.append(np.round(pts, 1).tolist())
        out[name] = {"centre": [round(float(c[0]), 1), round(float(c[1]), 1)], "radius": radius, "style": tw["style"],
                     "streets": st_out, "nodes": nodes, "buildings": buildings, "parking": lots, "pois": pois, "rails": rails,
                     "stats": {"streets": len(st_out), "osm_buildings": n_osm, "generated": len(buildings) - n_osm,
                               "pois": len(pois), "parking": len(lots), **net_stats}}
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
