# Coimbatore map — data sources

| Date | File | Source | Licence | Notes |
|---|---|---|---|---|
| 2026-10-09 (downloaded 2026-10-11) | `mapdata/cbe/2026-10-09/southern-zone.osm.pbf` (558 MB) | https://download.geofabrik.de/asia/india/southern-zone-261009.osm.pbf | ODbL 1.0 — © OpenStreetMap contributors | regional extract; the city is cut from it by `tools/citygen/extract.py` |
| (existing) | `mapdata/N11E076.hgt.gz` | SRTM 1″ via Mapzen terrain tiles | public domain (SRTM) | elevation |

Attribution shown in the game: "Road map data © OpenStreetMap contributors (ODbL) · Elevation: SRTM / Mapzen terrain tiles".
Raw files live in `mapdata/` and are not committed (see .gitignore).

## Human characters (approved by the user 2026-10-11, option B)

| File (in `vendor/mpfb/`, not committed) | Source | Licence |
|---|---|---|
| `mpfb-v2.0.18.zip` (43.8 MB) — MPFB2 Blender extension, human generator | https://extensions.blender.org/add-ons/mpfb/ (sha256 c075b3e9…2dad) | tool: GPL; characters it generates: CC0 |
| `makehuman_system_assets_cc0.zip` (268 MB) | https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html | CC0 |
| `skins01_cc0.zip`, `skins02_cc0.zip` (99 + 73 MB) — natural skins | MakeHuman asset packs | CC0 |
| `eyebrows01_cc0.zip`, `eyelashes01_cc0.zip`, `system_eye_materials01_cc0.zip` | MakeHuman asset packs | CC0 |
| `bodyparts05_cc0.zip` — beards and moustaches | MakeHuman asset packs | CC0 |
| `faceunits01.zip` — ARKit-style facial expressions | MakeHuman functional packs | CC0 |

Only CC0 packs are used, so nothing in the game needs attribution for them. Indian clothing, hair styling, accessories
and animation are made by our own scripts on top of these bodies.
