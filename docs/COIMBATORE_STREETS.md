# Coimbatore streets — design guide

How every street in the game city is dressed. Each road piece is given a **street type** from the map data (its OSM
class, the buildings beside it, shops, mills, how dense the area is), and the type decides the cross-section, the
edges and the street life. Used by `tools/streetlife.py` (Blender reference) and, once approved, the game.

## What the research says

- **Footpaths (IRC:103-2012, via ITDP):** kerb no higher than 150 mm; clear walking zone at least 1.8 m wide
  (residential) and 2.5 m (commercial); a 0.5 m frontage zone along compound walls (up to 1 m in commercial areas);
  a furniture zone for trees, poles, benches and manholes outside the walking line. Wider near bus stops.
  In practice the standard is followed only on major roads — **internal streets usually have no footpath**.
- **Layout roads:** residential layout roads in a corporation are at least **7 m** (23 ft); 30–40 ft (9–12 m)
  roads are common in older colonies. Front setbacks about 2.5–3 m on such roads (third-party guide, unverified).
- **Bazaar streets (Town Hall, Big Bazaar Street, Oppanakara Street, Raja Street, Cross Cut Road):** the busiest
  shopping streets; dense textile and jewellery showrooms beside street vendors; about 1.2–1.5 km long; crowds peak
  at Diwali, Pongal and Ramzan; landmarks at junctions (the Manikoondu clock tower at Big Bazaar × Raja Street);
  older accounts describe tile-roofed buildings along Oppanakara Street; temples between the bazaar streets.
- **Model roads (DB Road, T.V. Samy Road, R.S. Puram, 2015–16 onward):** continuous wide footpaths, parking and
  vendor zones, safer crossings, cycle tracks on arterials; narrower streets get only traffic calming.
- **Residential frontage:** the thinnai (raised shaded verandah at the threshold) has mostly given way to
  **compound walls and gates**; kolam drawn every morning at the entrance, swept and wetted first.
- **Everyday street elements:** drains covered with concrete slabs (open ones choke with silt), overhead power and
  cable wires tied to the same poles, speed breakers, stray cattle and dogs, roadside garbage where bins are few.

## Street types

| Type | Where (map rule) | Width | Edges | Street life |
|---|---|---|---|---|
| **Arterial** | trunk / primary, 11 m+ | 14–24 m, 4–6 lanes | raised median with planting and lamps; 2.5–3 m kerbed footpath; covered drain under the footpath | bus shelters, big signboards, flex banners on poles, autos waiting at stands, traffic signals, few vendors |
| **Bazaar** | secondary / tertiary with dense shops (≥ 60 % shop or commercial frontage) | 9–12 m, 2 lanes, no median | 1.5–2 m footpath that the shops take over: goods, steps, stools; shade sheets over it | rows of angled two-wheelers both sides, push carts, flower sellers, tea stalls, hand carts, crowds, stacked shop boards, dense wires |
| **Model road** | DB Road / R.S. Puram pattern: tertiary with low traffic and trees | 9–12 m | 2.5–3 m paver footpath, bollards, tree pits, benches, a vendor bay, parking bays marked | trees in a row, benches, a few vendors in their bay, cycles |
| **Colony street** | residential / unclassified in houses areas | 7–9 m | **no footpath**: asphalt to a 0.5 m concrete edge strip, then a slab-covered drain, then compound walls with gates (2.5 m setback) | kolam at gates, cars and bikes at gates, neem and coconut over the walls, a milk / vegetable cart, a street dog, a transformer on a plinth at a corner, a small shrine |
| **Old-town lane** | residential / living street in the dense core (very small plots, no setbacks) | 4–6 m | no footpath; an open drain channel each side with slab bridges to the doors; buildings to the edge | washing lines, bikes against walls, kolam at every door, water drums, sacks, very dense wires |
| **Industrial** | any road with mills or godowns on both sides | 7–10 m | gravel shoulders, long compound walls, wide gates | lorries parked, sacks, a tea shop at the gate, sparse trees |
| **Peri-urban** | roads with few buildings | 5–7 m | no kerb; red-soil and gravel shoulders; a little ditch | coconut and palm, cattle, a thatched tea shop, a bus shelter, power line on wooden poles |

## Rules common to every type

- Keep left. Speed breakers (yellow-black) at schools, temples and colony entrances.
- Electric poles on one side, every 35 m; wires sag 0.9 m; cable TV and internet wires on the same poles.
- Every gate or doorway gets a concrete ramp or slab across the drain.
- Nothing stands in the carriageway except parked vehicles at the edge, carts and animals.
- Text on boards: Tamil first, English second; fictional names only.
