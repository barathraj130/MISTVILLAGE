"""
Where road pieces meet end to end with no junction surface over the place, as city_streamer.gd builds them (_joins: a
mitred join for a gentle bend, a patch over a sharp one or a change of width): for the main roads (trunk, primary,
secondary, tertiary), the bare-ground area left open (holes) and the doubled area (overlap) within 12 m of each
join, without and with the fix, and the worst places. The ideal road is the two centre lines as one path, buffered
to half width with rounded corners.

    .venv/bin/python tools/citygen/audit_joins.py
"""
import json, math, os, sys, collections
import numpy as np
sys.path.insert(0, 'tools/citygen')
from lib.tiles import read_tile
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union
idx = json.load(open('godot/assets/city/index.json')); cls = idx['classes']
MAIN = {'trunk', 'primary', 'secondary', 'tertiary'}
def ribbon(p, half, miter):
    n = len(p); L = []; R = []
    for q in range(n):
        t = p[min(q + 1, n - 1)] - p[max(q - 1, 0)]; sc = 1.0
        if q in miter: t, sc = miter[q]
        l = np.array([t[1], -t[0]]); l /= max(np.linalg.norm(l), 1e-9)
        L.append(p[q] + l * half * sc); R.append(p[q] - l * half * sc)
    return [Polygon([L[q], L[q + 1], R[q + 1], R[q]]).buffer(0) for q in range(n - 1)]
tot = collections.Counter(); per = []
tiles = sorted(idx['tiles'])
for key in tiles:
    cx, cz = map(int, key.split(','))
    fn = 'godot/assets/city/chunks/CBE_%d_%d.bin' % (cx, cz)
    if not os.path.exists(fn): continue
    t = read_tile(fn); roads = t['roads']
    ends = collections.defaultdict(list)
    P = []
    for i, r in enumerate(roads):
        p = np.asarray(r['p']).reshape(-1, 3)[:, [0, 2]]; P.append(p)
        if len(p) < 2 or (r['fl'] & 2): continue
        for at_end in (False, True):
            if (r['c1'] if at_end else r['c0']) > 0: continue
            e = p[-1] if at_end else p[0]; o = p[-2] if at_end else p[1]
            d = e - o; d = d / max(np.linalg.norm(d), 1e-9)
            ends[(round(e[0] * 2), round(e[1] * 2))].append((i, at_end, d, e))
    for k, lst in ends.items():
        if len(lst) != 2 or lst[0][0] == lst[1][0]: continue
        (ia, ea, da, e), (ib, eb, db, _) = lst
        ra, rb = roads[ia], roads[ib]
        if cls[ra['cid']] not in MAIN and cls[rb['cid']] not in MAIN: continue
        straight = -float(np.dot(da, db))
        if straight > 0.996: continue
        ha, hb = ra['w'] / 2, rb['w'] / 2
        win = Point(e).buffer(12)
        pa = P[ia] if ea else P[ia][::-1]; pb = P[ib][::-1] if eb else P[ib]
        ideal = LineString(np.vstack([pa, pb[1:]])).buffer(max(ha, hb), join_style=1, cap_style=2).intersection(win)
        before = unary_union(ribbon(P[ia], ha, {}) + ribbon(P[ib], hb, {})).intersection(win)
        ov_b = unary_union(ribbon(P[ia], ha, {})).intersection(unary_union(ribbon(P[ib], hb, {}))).intersection(win).area
        # the fix
        mia, mib = {}, {}; patch = None
        if straight >= 0.5 and abs(ra['w'] - rb['w']) < 0.6:
            m = da - db; m = m / np.linalg.norm(m); sc = 1.0 / max(float(np.dot(m, da)), 0.5)
            mia[len(P[ia]) - 1 if ea else 0] = (m if ea else -m, sc)
            mib[len(P[ib]) - 1 if eb else 0] = (-m if eb else m, sc)
        else:
            def edge(pp, h, at_end):
                q = len(pp) - 1 if at_end else 0
                t = pp[min(q + 1, len(pp) - 1)] - pp[max(q - 1, 0)]
                l = np.array([t[1], -t[0]]); l /= np.linalg.norm(l)
                return [pp[q] + l * h, pp[q] - l * h]
            from shapely.geometry import MultiPoint
            pts = edge(P[ia], ha, ea) + edge(P[ib], hb, eb)
            patch = MultiPoint(pts).convex_hull.union(Point(e).buffer(max(ha, hb) + 0.3, 20)).convex_hull
        ga, gb = ribbon(P[ia], ha, mia), ribbon(P[ib], hb, mib)
        after = unary_union(ga + gb + ([patch] if patch else [])).intersection(win)
        ov_a = unary_union(ga).intersection(unary_union(gb)).intersection(win).area
        hb_ = ideal.difference(before).area; ha_ = ideal.difference(after).area
        tot['joins'] += 1; tot['hole_before'] += hb_; tot['hole_after'] += ha_
        tot['overlap_before'] += ov_b; tot['overlap_after'] += ov_a
        tot['holes_over_0.05m2_before'] += hb_ > 0.05; tot['holes_over_0.05m2_after'] += ha_ > 0.05
        per.append((round(hb_, 2), round(ha_, 2), round(e[0]), round(e[1])))
for k in tot: tot[k] = round(tot[k], 1) if isinstance(tot[k], float) else tot[k]
print(dict(tot)); per.sort(reverse=True)
print('worst (hole m² before, after, x, z):'); [print(' ', p) for p in per[:10]]
