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

## Sketchfab models (approved by the user 2026-10-26)

Downloaded with the user's own Sketchfab account into `mapdata/sketchfab/` (not committed). The game ships only the
converted pieces we use. CC-BY 4.0 models must be credited in the game's credits as below. "Sketchfab Standard"
models may be used inside the game but not redistributed as standalone files.

| Model | Author | Licence | Source |
|---|---|---|---|
| Indian-man-with-blue-clothes | Himanshuvaid | CC-BY 4.0 | https://sketchfab.com/3d-models/indian-man-with-blue-clothes-7cdbd4f668524e42982acb09cba57152 |
| indian-man-with-red-clothes | Himanshuvaid | CC-BY 4.0 | https://sketchfab.com/3d-models/indian-man-with-red-clothes-3f6bb2c1c9e743febfd970f795192504 |
| Indian man with suit | Polymount (soni.ravi206) | Sketchfab Standard | https://sketchfab.com/3d-models/indian-man-with-suit-720635f58afc408795d5b3e73c5bb8c5 |
| Indian Man In Dhoti | anandmohan662 | CC-BY 4.0 | https://sketchfab.com/3d-models/indian-man-in-dhoti-54b9e050d0d6424b848a04bec02a85d0 |
| old man in coat - human riged model | mohsenmousavi2313 | CC-BY 4.0 | https://sketchfab.com/3d-models/old-man-in-coat-human-riged-model-e8052f5928ef42f1ae5b5af02eb1a36b |
| Eric Rigged 001 | Renderpeople | CC-BY 4.0 | https://sketchfab.com/3d-models/eric-rigged-001-rigged-3d-business-man-a46bc9f67aaa415bb4f3241eef900e7f |
| Carla Rigged 001 | Renderpeople | CC-BY 4.0 | https://sketchfab.com/3d-models/carla-rigged-001-rigged-3d-business-women-acf520f450d14dd799f98a6fede3edf5 |
| Claudia Rigged 002 | Renderpeople | CC-BY 4.0 | https://sketchfab.com/3d-models/claudia-rigged-002-3d-rigged-business-women-c659bd0accab47c6bbe390cf822a2b92 |
| Indian Woman in Saree | Pixel_Monster (ar.jethin) | Sketchfab Standard | https://sketchfab.com/3d-models/indian-woman-in-saree-b5965a93b03440dea65160f7cbac1fc7 |
| Mom dress (saree and blouse) | Habib Siddick | CC-BY 4.0 | https://sketchfab.com/3d-models/mom-dress-saree-and-blouse-e5eeac0236714098a27fdbe13aedcb09 |
| Traditional Saree | Mobin Mithun | CC-BY 4.0 | https://sketchfab.com/3d-models/traditional-saree-c70eeeafd37c4d8aa138b61a45821c25 |
| FREE Male Fashion Hair collection 02 lowpoly | Vincent Page | CC-BY 4.0 | https://sketchfab.com/3d-models/free-male-fashion-hair-collection-02-lowpoly-bd74c3f6166c41778474cbe0485dda1d |
| South Indian Men . traditional fit | pranayeesaha0009 | CC-BY 4.0 | https://sketchfab.com/3d-models/south-indian-men-traditional-fit-c57eaa2b3afc4f258a60c4909a419772 |
| Dhoti-Clad Man in Traditional Indian Attire | ravitejareddy9381 | CC-BY 4.0 | https://sketchfab.com/3d-models/dhoti-clad-man-in-traditional-indian-attire-052dff295ffa40a69628d9960c0580c9 |
| Basic Bathroom Accessories | jdbensonCG | CC-BY 4.0 | https://sketchfab.com/3d-models/basic-bathroom-accessories-f64505fbb1954c9b9222bc74e20a560a |
| Plastic Bucket | MaX3Dd | CC-BY 4.0 | https://sketchfab.com/3d-models/plastic-bucket-006d0f237b4141ac93960fa51d6f0634 |
| Indane Gas Cylinder - Low Poly | Ponraj G | CC-BY 4.0 | https://sketchfab.com/3d-models/indane-gas-cylinder-low-poly-1462c782c4c346cc944dc41e3a74ca4a |
| Tea glass / Chai glass Indian style | bhagathgoud | CC-BY 4.0 | https://sketchfab.com/3d-models/tea-glass-chai-glass-indian-style-c160fc11558142d7a456d8d1021c0a0e |
| Idli South Indian food | AMBROSEDUDE | CC-BY 4.0 | https://sketchfab.com/3d-models/idli-south-indian-food-fe31b3ff3a734b9b918611a698ab7bd4 |
| Indian Traditional Banana Leaf | ronchoqa | CC-BY 4.0 | https://sketchfab.com/3d-models/indian-traditional-banana-leaf-6d2989ee224c4ba1a6d3899c1b6abf34 |
| Autorikshaw - Indian Tuk Tuk | bhagathartworks | CC-BY 4.0 | https://sketchfab.com/3d-models/autorikshaw-indian-tuk-tuk-5775d012693741008acff9dad410e92d |
| Low Poly Autorickshaw aka TukTuk | Nirmal.Justin | CC-BY 4.0 | https://sketchfab.com/3d-models/low-poly-autorickshaw-aka-tuktuk-c7c87455ad014b3f9fc8c9fb2d164a61 |
| Bhelpuri Shop By Ajay | AJ_AY (AJAY.K) | CC-BY 4.0 | https://sketchfab.com/3d-models/bhelpuri-shop-by-ajay-indian-local-shop-b8449c559da9434fbcdfcfcc92a5a082 |
| Ceiling_Fan_LP | Vitor.GomesPT | CC-BY 4.0 | https://sketchfab.com/3d-models/ceiling-fan-lp-20026b96c5144e5b923f1c8c4f8d41e7 |
