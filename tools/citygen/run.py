"""
Coimbatore city pipeline (docs/CBE_MAP_PIPELINE.md).

    .venv/bin/python tools/citygen/run.py extract    # stage 02: cut the city from the regional OSM file
    .venv/bin/python tools/citygen/run.py classify   # stage 04: classify roads, write build/cbe/report.md
    .venv/bin/python tools/citygen/run.py all
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import classify  # noqa: E402
import extract  # noqa: E402
from lib.common import load  # noqa: E402

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    cfg = load("city.yaml")
    if what in ("extract", "all"):
        extract.run(cfg)
    if what in ("classify", "all"):
        classify.run(cfg, load("roads.yaml"))
