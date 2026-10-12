"""
Stage 04 — classify roads and report what the real data holds.

Reads build/cbe/cache/osm.gpkg, projects to the city CRS (UTM 43N), clips to the boundary, assigns each road its
class profile from config/roads.yaml (OSM tags override: lanes, width, oneway, bridge, layer, junction …) and writes:

    build/cbe/cache/roads.gpkg   classified roads in metres (game x / z added as attributes of the CRS frame)
    build/cbe/report.md          counts and lengths by class, bridges, roundabouts, signals, buildings … (all REAL)
"""
import os
import sys

import geopandas as gpd
import pandas as pd
from shapely.geometry import Point

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import Projection, build_dir, load  # noqa: E402


def _num(v, default):
    """A tag like '2', '7.5 m' or '2;3' as a number; missing / unreadable → default."""
    if v is None or (isinstance(v, float) and v != v):
        return default
    try:
        x = float(str(v).split(";")[0].replace("m", "").strip())
        return default if x != x else x
    except (TypeError, ValueError):
        return default


def run(cfg, roads_cfg):
    out = build_dir(cfg)
    gpkg = os.path.join(out, "cache", "osm.gpkg")
    proj = Projection(cfg)
    c = cfg["boundary"]["circle"]
    centre = gpd.GeoSeries([Point(c["lon"], c["lat"])], crs="EPSG:4326").to_crs(cfg["crs"]).iloc[0]
    area = centre.buffer(float(c["radius_m"]))
    roads = gpd.read_file(gpkg, layer="roads").to_crs(cfg["crs"])
    roads = roads[roads.intersects(area)].copy()
    classes = roads_cfg["classes"]
    rmap = roads_cfg["map"]
    roads["cls"] = roads["highway"].map(rmap).fillna("")
    other = roads[roads["cls"] == ""]
    roads = roads[roads["cls"] != ""].copy()
    prof = roads["cls"].map(classes)
    roads["lanes_n"] = [int(_num(l, p["lanes"])) for l, p in zip(roads.get("lanes", pd.Series([None] * len(roads))), prof)]
    roads["width_m"] = [max(_num(w, p["width"]), p["width"]) for w, p in zip(roads.get("width", pd.Series([None] * len(roads))), prof)]
    roads["oneway_b"] = roads.get("oneway", pd.Series([""] * len(roads))).fillna("").isin(["yes", "1", "true", "-1"]) | \
        roads.get("junction", pd.Series([""] * len(roads))).fillna("").isin(["roundabout", "circular"])
    roads["bridge_b"] = roads.get("bridge", pd.Series([""] * len(roads))).fillna("").ne("") & \
        roads.get("bridge", pd.Series([""] * len(roads))).fillna("").ne("no")
    roads["layer_n"] = [int(_num(v, 0)) for v in roads.get("layer", pd.Series([None] * len(roads)))]
    roads["length_m"] = roads.length
    roads.to_file(os.path.join(out, "cache", "roads.gpkg"), layer="roads", driver="GPKG")

    def layer(name):
        try:
            g = gpd.read_file(gpkg, layer=name).to_crs(cfg["crs"])
            return g[g.intersects(area)]
        except Exception:
            return gpd.GeoDataFrame(geometry=[], crs=cfg["crs"])
    b = layer("buildings")
    w = layer("water")
    lu = layer("landuse")
    rail = layer("rail")
    pois = layer("pois")
    lines = ["# Coimbatore map — data report", "",
             "Boundary: circle %.0f km round (%.4f N, %.4f E). Source: %s. Everything below is **REAL** OSM data "
             "(nothing generated yet)." % (float(c["radius_m"]) / 1000, c["lat"], c["lon"], cfg["source"]["pbf"]), "",
             "## Roads by class", "", "| Class | Ways | Length km | One-way | Bridges |", "|---|---|---|---|---|"]
    for cls in classes:
        r = roads[roads["cls"] == cls]
        if len(r):
            lines.append("| %s | %d | %.1f | %d | %d |" % (cls, len(r), r["length_m"].sum() / 1000, r["oneway_b"].sum(), r["bridge_b"].sum()))
    drive = roads[~roads["cls"].isin(["footway"])]
    lines += ["", "**Drivable total: %.0f km in %d ways** (+ %.0f km footways). Unmapped highway kinds skipped: %s."
              % (drive["length_m"].sum() / 1000, len(drive), roads[roads["cls"] == "footway"]["length_m"].sum() / 1000,
                 ", ".join(sorted(other["highway"].unique())) or "none"), "",
              "## Features", "",
              "| Feature | Count |", "|---|---|",
              "| Bridges / flyovers (road ways tagged bridge) | %d |" % roads["bridge_b"].sum(),
              "| Elevated (layer ≥ 1) | %d |" % (roads["layer_n"] >= 1).sum(),
              "| Roundabout ways | %d |" % roads.get("junction", pd.Series([""] * len(roads))).fillna("").isin(["roundabout", "circular"]).sum(),
              "| Ways with lane counts | %d |" % roads.get("lanes", pd.Series([None] * len(roads))).notna().sum()]
    if len(pois):
        hw = pois.get("highway", pd.Series([""] * len(pois))).fillna("")
        rw = pois.get("railway", pd.Series([""] * len(pois))).fillna("")
        am = pois.get("amenity", pd.Series([""] * len(pois))).fillna("")
        lines += ["| Traffic signals | %d |" % (hw == "traffic_signals").sum(),
                  "| Pedestrian crossings | %d |" % (hw == "crossing").sum(),
                  "| Bus stops | %d |" % ((hw == "bus_stop") | pois.get("public_transport", pd.Series([""] * len(pois))).fillna("").eq("platform")).sum(),
                  "| Railway level crossings | %d |" % (rw == "level_crossing").sum(),
                  "| Fuel stations | %d |" % (am == "fuel").sum(),
                  "| Places of worship | %d |" % (am == "place_of_worship").sum(),
                  "| Hospitals / clinics | %d |" % am.isin(["hospital", "clinic"]).sum(),
                  "| Schools / colleges | %d |" % am.isin(["school", "college", "university"]).sum(),
                  "| All points of interest | %d |" % len(pois)]
    lvl = b.get("levels", pd.Series([""] * len(b))).fillna("")
    lines += ["| Buildings (footprints) | %d |" % len(b),
              "| … with storey count | %d |" % (lvl != "").sum(),
              "| Water bodies / waterways | %d |" % len(w),
              "| Land-use areas | %d |" % len(lu),
              "| Railway ways | %d |" % len(rail), "",
              "Not yet assembled: multipolygon relations (some large lakes, parks, campuses)."]
    rep = os.path.join(out, "report.md")
    with open(rep, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("REPORT →", rep)


if __name__ == "__main__":
    run(load("city.yaml"), load("roads.yaml"))
