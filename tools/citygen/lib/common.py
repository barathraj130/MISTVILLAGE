"""Shared helpers for the Coimbatore city pipeline: config, paths, projection, boundary."""
import json
import math
import os

import yaml
from pyproj import Transformer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def load(name):
    with open(os.path.join(ROOT, "config", name)) as f:
        return yaml.safe_load(f)


def path(*parts):
    return os.path.join(ROOT, *parts)


def build_dir(cfg):
    d = path(cfg["build_dir"])
    os.makedirs(os.path.join(d, "cache"), exist_ok=True)
    return d


class Projection:
    """WGS-84 lon/lat → game metres: x = E - E0, z = -(N - N0) in the configured UTM zone."""

    def __init__(self, cfg):
        self.to_utm = Transformer.from_crs("EPSG:4326", cfg["crs"], always_xy=True)
        self.to_ll = Transformer.from_crs(cfg["crs"], "EPSG:4326", always_xy=True)
        self.e0, self.n0 = self.to_utm.transform(cfg["origin"]["lon"], cfg["origin"]["lat"])

    def game(self, lon, lat):
        e, n = self.to_utm.transform(lon, lat)
        return e - self.e0, -(n - self.n0)


def bbox(cfg):
    """(min_lon, min_lat, max_lon, max_lat) of the boundary plus margin."""
    b = cfg["boundary"]
    m = float(cfg.get("margin_m", 0))
    if b.get("circle"):
        c = b["circle"]
        r = float(c["radius_m"]) + m
        dlat = r / 110540.0
        dlon = r / (111320.0 * math.cos(math.radians(c["lat"])))
        return c["lon"] - dlon, c["lat"] - dlat, c["lon"] + dlon, c["lat"] + dlat
    if b.get("geojson"):
        with open(path(b["geojson"])) as f:
            gj = json.load(f)
        xs, ys = [], []

        def walk(c):
            if isinstance(c[0], (int, float)):
                xs.append(c[0])
                ys.append(c[1])
            else:
                for k in c:
                    walk(k)
        for feat in gj.get("features", [gj]):
            walk(feat["geometry"]["coordinates"])
        pad_lat = m / 110540.0
        pad_lon = m / (111320.0 * math.cos(math.radians(sum(ys) / len(ys))))
        return min(xs) - pad_lon, min(ys) - pad_lat, max(xs) + pad_lon, max(ys) + pad_lat
    raise SystemExit("boundary: set circle or geojson in config/city.yaml (osm_relation not supported yet)")


def inside(cfg):
    """A fast point test (lon, lat) → bool for the boundary plus margin."""
    b = cfg["boundary"]
    m = float(cfg.get("margin_m", 0))
    if b.get("circle"):
        c = b["circle"]
        r = float(c["radius_m"]) + m
        kx = 111320.0 * math.cos(math.radians(c["lat"]))
        lon0, lat0 = c["lon"], c["lat"]
        r2 = r * r
        return lambda lon, lat: ((lon - lon0) * kx) ** 2 + ((lat - lat0) * 110540.0) ** 2 <= r2
    x0, y0, x1, y1 = bbox(cfg)
    return lambda lon, lat: x0 <= lon <= x1 and y0 <= lat <= y1
