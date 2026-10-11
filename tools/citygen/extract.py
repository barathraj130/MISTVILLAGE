"""
Stage 02 — cut the city out of the regional OSM extract (no osmium CLI needed).

Reads config/city.yaml → source.pbf, keeps every way / node of interest inside the boundary (+ margin) and
writes GeoPackage layers to build/cbe/cache/osm.gpkg (EPSG:4326), each feature tagged src = osm:<type>/<id>:

    roads      LineString  highway=* (all classes incl. footways), with bridge/tunnel/layer/oneway/lanes/...
    rail       LineString  railway=rail|light_rail|subway|narrow_gauge
    buildings  Polygon     building=* (closed ways)
    water      Polygon / LineString   natural=water, water=*, waterway=*
    landuse    Polygon     landuse=*, leisure=park|garden|pitch, natural=wood|scrub|grassland
    pois       Point       amenity, shop, tourism, public_transport, highway=bus_stop|traffic_signals|crossing,
                           railway=level_crossing|station, place_of_worship, ...

Node locations are kept in a disk-backed index (not RAM) so the whole southern-India file fits on an 8 GB Mac.
Multipolygon relations (a few big lakes / parks) are not assembled yet — noted in the report.
"""
import os
import sys
import time

import geopandas as gpd
import osmium
from shapely.geometry import LineString, Point, Polygon

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.common import bbox, build_dir, inside, load, path  # noqa: E402

ROAD_KEYS = ("name", "ref", "oneway", "lanes", "width", "bridge", "tunnel", "layer", "junction", "surface", "lit",
             "maxspeed", "sidewalk", "turn:lanes", "access", "service")
POI_KEYS = ("amenity", "shop", "tourism", "public_transport", "highway", "railway", "leisure", "office", "healthcare",
            "religion", "historic", "building")
WAY_KEYS = ("highway", "railway", "building", "natural", "water", "waterway", "landuse", "leisure")
NODE_KEYS = ("amenity", "shop", "tourism", "public_transport", "highway", "railway", "leisure", "office", "healthcare",
             "historic", "place")


def run(cfg):
    src = path(cfg["source"]["pbf"])
    if not os.path.exists(src):
        raise SystemExit("missing %s (download it first)" % src)
    out_dir = build_dir(cfg)
    x0, y0, x1, y1 = bbox(cfg)
    keep = inside(cfg)
    idx_file = os.path.join(out_dir, "cache", "nodes.idx")
    if os.path.exists(idx_file):
        os.remove(idx_file)
    index = osmium.index.create_map("sparse_file_array," + idx_file)
    layers = {k: [] for k in ("roads", "rail", "buildings", "water", "landuse", "pois")}
    t0 = time.time()
    n_ways = 0

    def in_box(lon, lat):
        return x0 <= lon <= x1 and y0 <= lat <= y1

    fp = osmium.FileProcessor(src, osmium.osm.NODE | osmium.osm.WAY).with_locations(index) \
        .with_filter(osmium.filter.KeyFilter(*sorted(set(WAY_KEYS) | set(NODE_KEYS))))
    for o in fp:
        if o.is_node():
            loc = o.location
            if not loc.valid() or not in_box(loc.lon, loc.lat) or not keep(loc.lon, loc.lat):
                continue
            tags = {k: o.tags.get(k) for k in POI_KEYS if k in o.tags}
            if not tags:
                continue
            tags["name"] = o.tags.get("name", "")
            tags["src"] = "osm:node/%d" % o.id
            layers["pois"].append((Point(loc.lon, loc.lat), tags))
            continue
        n_ways += 1
        try:
            first = o.nodes[0].location
        except (IndexError, osmium.InvalidLocationError):
            continue
        if not first.valid() or not in_box(first.lon, first.lat):
            continue
        try:
            coords = [(n.lon, n.lat) for n in o.nodes]
        except osmium.InvalidLocationError:
            continue
        if not any(keep(lon, lat) for lon, lat in coords[:: max(1, len(coords) // 8)]):
            continue
        tg = o.tags
        src_id = "osm:way/%d" % o.id
        closed = len(coords) >= 4 and coords[0] == coords[-1]
        if "highway" in tg and len(coords) >= 2:
            a = {"highway": tg["highway"], "src": src_id}
            for k in ROAD_KEYS:
                if k in tg:
                    a[k] = tg[k]
            layers["roads"].append((LineString(coords), a))
        elif "railway" in tg and tg["railway"] in ("rail", "light_rail", "subway", "narrow_gauge", "metro") and len(coords) >= 2:
            layers["rail"].append((LineString(coords), {"railway": tg["railway"], "name": tg.get("name", ""),
                                                        "bridge": tg.get("bridge", ""), "src": src_id}))
        elif "building" in tg and closed:
            layers["buildings"].append((Polygon(coords), {"building": tg["building"], "levels": tg.get("building:levels", ""),
                                                          "height": tg.get("height", ""), "name": tg.get("name", ""),
                                                          "amenity": tg.get("amenity", ""), "shop": tg.get("shop", ""),
                                                          "src": src_id}))
        elif tg.get("natural") == "water" or "water" in tg or "waterway" in tg:
            geom = Polygon(coords) if closed and "waterway" not in tg else LineString(coords)
            layers["water"].append((geom, {"kind": tg.get("water", tg.get("waterway", "water")), "name": tg.get("name", ""),
                                           "src": src_id}))
        elif closed and ("landuse" in tg or tg.get("leisure") in ("park", "garden", "pitch", "stadium")
                         or tg.get("natural") in ("wood", "scrub", "grassland", "wetland")):
            layers["landuse"].append((Polygon(coords), {"kind": tg.get("landuse", tg.get("leisure", tg.get("natural"))),
                                                        "name": tg.get("name", ""), "src": src_id}))
        if n_ways % 2_000_000 == 0:
            print("  ... %dM ways scanned, %ds" % (n_ways // 1_000_000, time.time() - t0), flush=True)
    gpkg = os.path.join(out_dir, "cache", "osm.gpkg")
    if os.path.exists(gpkg):
        os.remove(gpkg)
    for name, feats in layers.items():
        if not feats:
            continue
        gdf = gpd.GeoDataFrame([a for _, a in feats], geometry=[g for g, _ in feats], crs="EPSG:4326")
        gdf.to_file(gpkg, layer=name, driver="GPKG")
        print("  %-10s %7d features" % (name, len(gdf)), flush=True)
    os.remove(idx_file)
    print("EXTRACT done in %ds → %s" % (time.time() - t0, gpkg))


if __name__ == "__main__":
    run(load("city.yaml"))
