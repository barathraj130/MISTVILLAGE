#!/usr/bin/env python3
"""
Compile the real Coimbatore → Kotagiri road (real_route.json, from build_real_route.py) into an
ETS-style compressed driving map for Godot.

How the compression works (like Euro Truck Simulator's map scale):
  * The road keeps its real shape: every sample keeps its real heading, so bends and hairpins
    are true to life. Only straights are shortened: ~9x on the NH181 plains, ~2x on the ghat,
    ~3x in towns. Tight bends are never compressed.
  * Heights keep the real profile, scaled by VERTICAL so the compressed ghat stays drivable.
  * Terrain comes from the real 30 m elevation model: every point of the new map is mapped back
    to a real location (along the road × its compression, across the road 1:1 near it and 4:1
    further out) and blended between nearby road samples.
  * The road is carved in here (flat bed, cuttings, embankments) so Godot only builds meshes.

Output (godot/assets/drive/):
  map.json       route samples, stages, towns, landmarks, grid metadata
  near.bin       float32 [nz, nx] carved ground on a 4 m grid along the corridor (NaN outside)
  natural.bin    float32 [nz, nx] uncarved ground (walls / parapets need it)
  proximity.bin  uint8   [nz, nx] 0..255 closeness to any road (props stay off it)
  far.bin        float32 [fz, fx] backdrop terrain on a 48 m grid

Map data © OpenStreetMap contributors (ODbL). Elevation: SRTM via Mapzen terrain tiles.
"""
import gzip, json, math, os, sys, time
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import towns as townlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "godot", "assets", "drive", "real_route.json")
OUT = os.path.join(ROOT, "godot", "assets", "drive")
DEM = os.path.join(ROOT, "mapdata", "N11E076.hgt.gz")

VERTICAL = 0.5             # real metres of climb → game metres
NEAR_LATERAL = 300.0       # across the road: 1:1 this far, then compressed
FAR_LATERAL_SCALE = 4.0
CELL, CHUNK = 4.0, 32
CORRIDOR = 250.0
FAR_CELL, FAR_MARGIN = 48.0, 6000.0
FLAT, BLEND_CUT, BLEND_FILL, NEAR_R = 6.2, 14.0, 30.0, 12.0

# zones by REAL distance: id, title, subtitle, start (m), straight compression
ZONES = [
    ("coimbatore", "Coimbatore", "Gandhipuram · Mettupalayam Road (NH181)", 0, 3.0),
    ("plains", "NH181 to Mettupalayam", "Thudiyalur · Periyanaickenpalayam · Karamadai", 6000, 9.0),
    ("mettupalayam", "Mettupalayam", "Gateway to the Nilgiris · Bhavani river", 37500, 3.0),
    ("foothills", "Foothills", "Forest and wild elephants", 41000, 4.0),
    ("ghat", "Kotagiri Ghat Road (SH15)", "Uphill traffic has right of way", 45500, 2.0),
    ("mist", "Into the Clouds", "Tea country above the mist", 56500, 2.6),
    ("kotagiri", "Kotagiri", "Aravenu · Karbetta · Kotagiri", 66000, 2.5),
]
TOWNS = [  # generated roadside villages, real-distance ranges (m); hill = tin gable roofs.
    # Coimbatore, Mettupalayam and Kotagiri are full open-world towns from OpenStreetMap (towns.py).
    ("Thudiyalur", 8300, 9600, 2, False), ("Periyanaickenpalayam", 16700, 18000, 2, False),
    ("Karamadai", 27400, 28600, 2, False), ("Mamaram", 55100, 55700, 1, True), ("Aravenu", 66000, 66800, 2, True),
]


def smooth(a, w):
    if w <= 0:
        return a
    k = np.ones(2 * w + 1) / (2 * w + 1)
    return np.convolve(np.pad(a, w, mode="edge"), k, mode="same")[w:-w]


class Dem:
    def __init__(self, lat0, lon0):
        with gzip.open(DEM) as f:
            raw = f.read()
        self.n = int(math.sqrt(len(raw) // 2))
        d = np.frombuffer(raw, dtype=">i2").reshape(self.n, self.n).astype(np.float32)
        d[d < -1000] = np.nanmedian(d[d > -1000])
        self.d = d
        self.lat0, self.lon0 = lat0, lon0
        self.kx = math.cos(math.radians(lat0)) * 111320.0
        self.kz = 110540.0

    def at(self, x, z):
        """Real local metres (+X east, +Z south) → elevation, bilinear, clamped to the tile."""
        lat = self.lat0 - z / self.kz
        lon = self.lon0 + x / self.kx
        n = self.n
        fy = np.clip((12.0 - lat) * (n - 1), 0, n - 2.001)
        fx = np.clip((lon - 76.0) * (n - 1), 0, n - 2.001)
        x0 = fx.astype(np.int32)
        y0 = fy.astype(np.int32)
        tx, ty = fx - x0, fy - y0
        d = self.d
        return ((d[y0, x0] * (1 - tx) + d[y0, x0 + 1] * tx) * (1 - ty)
                + (d[y0 + 1, x0] * (1 - tx) + d[y0 + 1, x0 + 1] * tx) * ty)


def main():
    t0 = time.time()
    src = json.load(open(SRC))
    step = src["step"]
    real = np.array(src["xz"], dtype=np.float64)
    elev = smooth(np.array(src["elev"], dtype=np.float64), 3)
    n = len(real)
    D = np.arange(n) * step                       # real distance
    dem = Dem(*src["origin_latlon"])

    # --- headings and compression ------------------------------------------------------
    seg = np.diff(real, axis=0)
    head_raw = np.unwrap(np.arctan2(seg[:, 1], seg[:, 0]))
    zone = townlib.in_zone_mask(real, src["origin_latlon"])
    zseg = zone[:-1] | zone[1:]
    # inside towns the road keeps its exact real heading, so real streets line up with it
    head = np.where(zseg, head_raw, smooth(head_raw, 1))
    curv = np.abs(np.gradient(smooth(head, 2), step))          # rad per metre
    zone_k = np.zeros(n - 1)
    zone_of = np.zeros(n - 1, dtype=np.int32)
    for zi, z in enumerate(ZONES):
        zone_k[D[:-1] >= z[3]] = z[4]
        zone_of[D[:-1] >= z[3]] = zi
    bend = np.clip(curv / 0.02, 0, 1) ** 0.7                    # radius ≲ 50 m → keep true length
    k = zone_k * (1 - bend) + 1.0 * bend
    k = np.maximum(smooth(k, 3), 1.0)
    k = np.where(zseg, 1.0, k)                                  # towns are 1:1
    ds = step / k
    new = np.zeros((n, 2))
    new[1:] = np.cumsum(np.stack([np.cos(head) * ds, np.sin(head) * ds], 1), axis=0)
    newd = np.concatenate([[0.0], np.cumsum(ds)])
    y = (elev - elev[0]) * VERTICAL
    # smooth the compressed road's height over ~40 m of new distance
    y = smooth(smooth(y, 6), 6)
    print(f"real {D[-1] / 1000:.1f} km → game {newd[-1] / 1000:.2f} km; climb {y.max() - y.min():.0f} m game "
          f"({elev.max() - elev.min():.0f} m real)")

    # --- 2 m game samples ----------------------------------------------------------------
    gd = np.arange(0.0, newd[-1], 2.0)
    gx = np.interp(gd, newd, new[:, 0])
    gz = np.interp(gd, newd, new[:, 1])
    gy = np.interp(gd, newd, y)
    greal = np.interp(gd, newd, D)
    galt = np.interp(gd, newd, elev)
    gi = np.clip(np.searchsorted(newd, gd) - 1, 0, n - 2)      # real sample each game sample came from
    to_game = lambda dreal: float(np.interp(dreal, D, newd))

    towns = townlib.translations(real, new, src["origin_latlon"])
    for tw in towns.values():
        tw["origin"] = src["origin_latlon"]

    # --- terrain grids -------------------------------------------------------------------
    span = CELL * CHUNK
    lo = new.min(0) - CORRIDOR - span
    hi = new.max(0) + CORRIDOR + span
    for tw in towns.values():
        lo = np.minimum(lo, tw["centre"] - tw["radius"] - span)
        hi = np.maximum(hi, tw["centre"] + tw["radius"] + span)
    gx0 = int(math.floor(lo[0] / span)) * CHUNK
    gz0 = int(math.floor(lo[1] / span)) * CHUNK
    nx = int(math.ceil(hi[0] / span)) * CHUNK - gx0 + 1
    nz = int(math.ceil(hi[1] / span)) * CHUNK - gz0 + 1
    print(f"near grid {nx} x {nz} ({nx * CELL / 1000:.1f} x {nz * CELL / 1000:.1f} km)")

    # chunks within the corridor
    ncx, ncz = (nx - 1) // CHUNK, (nz - 1) // CHUNK
    chunk = np.zeros((ncz, ncx), dtype=bool)
    for i in range(0, n, 3):
        cx = (new[i, 0] / CELL - gx0) / CHUNK
        cz = (new[i, 1] / CELL - gz0) / CHUNK
        r = CORRIDOR / span
        chunk[max(int(cz - r), 0):min(int(cz + r) + 1, ncz), max(int(cx - r), 0):min(int(cx + r) + 1, ncx)] = True
    for tw in towns.values():                                   # whole towns get detailed ground
        cc, rr = tw["centre"], tw["radius"] + 100.0
        for cz in range(ncz):
            for cx in range(ncx):
                mx = (gx0 + (cx + 0.5) * CHUNK) * CELL
                mz = (gz0 + (cz + 0.5) * CHUNK) * CELL
                if math.hypot(mx - cc[0], mz - cc[1]) < rr:
                    chunk[cz, cx] = True
    print(f"corridor + town chunks: {chunk.sum()}")

    def paint(ox, oz, cell, w, h, samples, radius, soft):
        """Blend real terrain cross-sections from road samples onto a grid (inverse-distance^4)."""
        acc = np.zeros((h, w), np.float64)
        wsum = np.zeros((h, w), np.float64)
        for i in samples:
            nxp, nzp = new[i]
            c0 = max(int((nxp - radius - ox) / cell), 0)
            c1 = min(int((nxp + radius - ox) / cell) + 1, w)
            r0 = max(int((nzp - radius - oz) / cell), 0)
            r1 = min(int((nzp + radius - oz) / cell) + 1, h)
            if c0 >= c1 or r0 >= r1:
                continue
            X, Z = np.meshgrid(ox + np.arange(c0, c1) * cell - nxp, oz + np.arange(r0, r1) * cell - nzp)
            d2 = X * X + Z * Z
            m = d2 < radius * radius
            if not m.any():
                continue
            hh = head[min(i, n - 2)]
            t = np.array([math.cos(hh), math.sin(hh)])
            p = np.array([-math.sin(hh), math.cos(hh)])
            a = X * t[0] + Z * t[1]
            o = X * p[0] + Z * p[1]
            ao = np.abs(o)
            o_r = np.where(ao <= NEAR_LATERAL, o, np.sign(o) * (NEAR_LATERAL + (ao - NEAR_LATERAL) * FAR_LATERAL_SCALE))
            a_r = a * k[min(i, n - 2)]
            rx = real[i, 0] + t[0] * a_r + p[0] * o_r
            rz = real[i, 1] + t[1] * a_r + p[1] * o_r
            hgt = y[i] + (dem.at(rx, rz) - elev[i]) * VERTICAL
            wt = np.where(m, 1.0 / (d2 + soft * soft) ** 2, 0.0)
            acc[r0:r1, c0:c1] += wt * hgt
            wsum[r0:r1, c0:c1] += wt
        out = np.full((h, w), np.nan, np.float32)
        ok = wsum > 0
        out[ok] = (acc[ok] / wsum[ok]).astype(np.float32)
        return out

    natural = paint(gx0 * CELL, gz0 * CELL, CELL, nx, nz, range(0, n, 1), CORRIDOR + span * 0.8, 6.0)
    # towns: ground straight from the real terrain at 1:1
    townlib.paint_town_ground(townlib.Grid(natural, natural, None, gx0, gz0, CELL), towns, dem, elev[0], VERTICAL)
    # only keep cells inside corridor chunks
    mask = np.zeros((nz, nx), dtype=bool)
    for cz, cx in zip(*np.nonzero(chunk)):
        mask[cz * CHUNK:cz * CHUNK + CHUNK + 1, cx * CHUNK:cx * CHUNK + CHUNK + 1] = True
    natural[~mask] = np.nan
    print(f"natural ground painted ({time.time() - t0:.0f}s)")

    # --- carve the road in -----------------------------------------------------------------
    carved = natural.copy()
    wmax = np.zeros_like(natural)
    tgt = np.zeros_like(natural)
    prox = np.zeros_like(natural)
    bridges = []
    for rv in src["rivers"]:
        gdc = to_game(rv["d"])
        bridges.append((gdc - 45.0, gdc + 45.0))
    rr = int(BLEND_FILL / CELL) + 1
    for j in range(len(gd)):
        px, pz, py = gx[j], gz[j], gy[j]
        cx = int(round(px / CELL)) - gx0
        cz = int(round(pz / CELL)) - gz0
        c0, c1 = max(cx - rr, 0), min(cx + rr + 1, nx)
        r0, r1 = max(cz - rr, 0), min(cz + rr + 1, nz)
        X, Z = np.meshgrid((np.arange(c0, c1) + gx0) * CELL - px, (np.arange(r0, r1) + gz0) * CELL - pz)
        dd = np.sqrt(X * X + Z * Z)
        nat = natural[r0:r1, c0:c1]
        pr = prox[r0:r1, c0:c1]
        np.maximum(pr, np.clip(1.0 - dd / NEAR_R, 0, 1), out=pr)
        if any(a < gd[j] < b for a, b in bridges):
            continue
        blend = np.where(nat > py, BLEND_CUT, BLEND_FILL)
        wt = np.where(dd <= FLAT, 1.0, 1.0 - np.clip((dd - FLAT) / (blend - FLAT), 0, 1) ** 2 * (3 - 2 * np.clip((dd - FLAT) / (blend - FLAT), 0, 1)))
        wt = np.where(dd < blend, wt, 0.0)
        wt = np.where(np.isnan(nat), 0.0, wt)
        wm = wmax[r0:r1, c0:c1]
        better = wt > wm
        wm[better] = wt[better]
        tgt[r0:r1, c0:c1][better] = py - 0.3
    sel = wmax > 0
    carved[sel] = natural[sel] * (1 - wmax[sel]) + tgt[sel] * wmax[sel]
    print(f"road carved ({time.time() - t0:.0f}s)")

    # --- open-world towns: real streets, buildings and landmarks ------------------------------
    tgrid = townlib.Grid(natural, carved, prox, gx0, gz0, CELL)
    towns_out = townlib.build_towns(towns, tgrid, np.column_stack([gx, gz]), os.path.join(ROOT, "mapdata"), route_y=gy)
    # no ground may rise through any road: town streets, parking lots and the highway (+ its shoulders)
    segs = townlib.town_road_segments(towns_out) + [(np.column_stack([gx, gz]), np.asarray(gy), 3.6 + 1.4)]
    before = townlib.road_pokes(tgrid, segs)
    f0 = townlib.road_floats(tgrid, segs[:-1])
    townlib.sink_under_roads(tgrid, segs[:-1], margin=6.0, clearance=0.3)
    f1 = townlib.road_floats(tgrid, segs[:-1])
    townlib.sink_under_roads(tgrid, segs[-1:], margin=6.0, clearance=0.45)
    print(f"floats: before {f0}, after streets {f1}, after highway {townlib.road_floats(tgrid, segs[:-1])}")
    print(f"ground through roads: {before} samples before, {townlib.road_pokes(tgrid, segs)} after; "
          f"streets >0.8 m above ground: {townlib.road_floats(tgrid, segs[:-1])}")
    json.dump(towns_out, open(os.path.join(OUT, "towns.json"), "w"), separators=(",", ":"))
    for nm, tw in towns_out.items():
        print(f"  town {nm:13s} {tw['stats']}")
    print(f"towns built ({time.time() - t0:.0f}s)")

    # --- far backdrop ------------------------------------------------------------------------
    fox = math.floor((new[:, 0].min() - FAR_MARGIN) / FAR_CELL) * FAR_CELL
    foz = math.floor((new[:, 1].min() - FAR_MARGIN) / FAR_CELL) * FAR_CELL
    fw = int((new[:, 0].max() + FAR_MARGIN - fox) / FAR_CELL) + 1
    fh = int((new[:, 1].max() + FAR_MARGIN - foz) / FAR_CELL) + 1
    far = paint(fox, foz, FAR_CELL, fw, fh, range(0, n, 8), FAR_MARGIN * 1.5, 120.0)
    far = np.where(np.isnan(far), np.nanmin(far), far) - 0.6
    print(f"far grid {fw} x {fh} ({time.time() - t0:.0f}s)")

    # --- metadata ------------------------------------------------------------------------------
    stages = []
    for zi, z in enumerate(ZONES):
        s0 = to_game(z[3])
        s1 = to_game(ZONES[zi + 1][3]) if zi + 1 < len(ZONES) else float(gd[-1])
        a0 = float(np.interp(z[3], D, elev))
        a1 = float(np.interp(ZONES[zi + 1][3] if zi + 1 < len(ZONES) else D[-1], D, elev))
        stages.append({"id": z[0], "title": z[1], "subtitle": z[2], "start": s0, "end": s1, "alt0": a0, "alt1": a1})
    stages.append({"id": "arrival", "title": "The Mist Village", "subtitle": "Where the mist slows you down",
                   "start": float(gd[-1]) - 90.0, "end": float(gd[-1]), "alt0": float(elev[-1]), "alt1": float(elev[-1])})
    stages[-2]["end"] = float(gd[-1]) - 90.0
    lm = {l["kind"]: l["d"] for l in src["landmarks"] if l["d"] > 40000}
    marks = {
        "checkpost": to_game(lm.get("lift_gate", 53800)),
        "tea_stall": to_game(lm.get("viewpoint", 52900)),
        "elephants": to_game(47200),
        "ghat_start": to_game(ZONES[4][3]), "ghat_end": to_game(ZONES[5][3]),
        "bridge_start": bridges[0][0] + 20 if bridges else to_game(39500) - 25,
        "bridge_end": bridges[0][1] - 20 if bridges else to_game(39500) + 25,
    }
    hair_real = [h for h in src["hairpins"] if h > 40000]
    meta = {
        "source": src["source"], "vertical_scale": VERTICAL,
        "length": float(gd[-1]), "real_length": float(D[-1]),
        "samples": {"x": np.round(gx, 2).tolist(), "y": np.round(gy, 2).tolist(), "z": np.round(gz, 2).tolist(),
                    "real_d": np.round(greal, 0).tolist(), "alt": np.round(galt, 0).tolist()},
        "stages": stages, "marks": marks,
        "hairpins": [to_game(h) for h in hair_real],
        "towns": [{"name": t[0], "start": to_game(t[1]), "end": to_game(t[2]), "floors": t[3], "hill": t[4]} for t in TOWNS],
        "places": [{"name": p["name"], "d": to_game(p["d"]), "kind": p["kind"]} for p in src["places"]],
        "near": {"file": "near.bin", "natural": "natural.bin", "proximity": "proximity.bin",
                 "gx0": gx0, "gz0": gz0, "nx": nx, "nz": nz, "cell": CELL, "chunk": CHUNK,
                 "chunks": [[int(cx), int(cz)] for cz, cx in zip(*np.nonzero(chunk))]},
        "far": {"file": "far.bin", "ox": fox, "oz": foz, "w": fw, "h": fh, "cell": FAR_CELL},
        "towns_file": "towns.json",
        "town_zones": [{"name": nm, "centre": tw["centre"], "radius": tw["radius"]} for nm, tw in towns_out.items()],
    }
    # no gaps: cells outside the detailed corridor take the backdrop height, so Godot can build
    # heightmap collision straight from row slices
    holes = np.isnan(carved)
    if holes.any():
        jj, ii = np.nonzero(holes)
        wx = (ii + gx0) * CELL
        wz = (jj + gz0) * CELL
        fx = np.clip((wx - fox) / FAR_CELL, 0, fw - 1.001)
        fz = np.clip((wz - foz) / FAR_CELL, 0, fh - 1.001)
        x0, z0 = fx.astype(int), fz.astype(int)
        tx, tz = fx - x0, fz - z0
        fv = ((far[z0, x0] * (1 - tx) + far[z0, x0 + 1] * tx) * (1 - tz)
              + (far[z0 + 1, x0] * (1 - tx) + far[z0 + 1, x0 + 1] * tx) * tz)
        carved[holes] = fv - 0.4
        nat_holes = np.isnan(natural)
        natural[nat_holes] = carved[nat_holes]
    carved.astype("<f4").tofile(os.path.join(OUT, "near.bin"))
    natural.astype("<f4").tofile(os.path.join(OUT, "natural.bin"))
    (np.nan_to_num(prox) * 255).astype(np.uint8).tofile(os.path.join(OUT, "proximity.bin"))
    far.astype("<f4").tofile(os.path.join(OUT, "far.bin"))
    json.dump(meta, open(os.path.join(OUT, "map.json"), "w"), separators=(",", ":"))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in ("near.bin", "natural.bin", "proximity.bin", "far.bin", "map.json"))
    print(f"wrote map ({size / 1e6:.0f} MB) in {time.time() - t0:.0f}s")
    for s in stages:
        print(f"  {s['id']:13s} {s['start'] / 1000:6.2f} – {s['end'] / 1000:6.2f} km   {s['alt0']:5.0f} → {s['alt1']:5.0f} m")
    print("  marks:", {k: round(v) for k, v in marks.items()})
    print("  hairpins (game km):", [round(h / 1000, 2) for h in meta["hairpins"]])
    gr = np.diff(gy) / 2.0
    print(f"  max grade {gr.max() * 100:.1f} % (95th pct {np.percentile(np.abs(gr), 95) * 100:.1f} %)")


if __name__ == "__main__":
    main()
