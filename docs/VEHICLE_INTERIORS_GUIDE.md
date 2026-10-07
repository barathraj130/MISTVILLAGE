# Vehicle Interiors — Guide for Interior Designers

How to design a vehicle cabin in Blender so it drops straight into **The Mist Village** (Godot 4), and how to
send it to the project on GitHub.

---

## 1. Which cabins the game uses

| Vehicle | File the game loads | Exterior shell to design around |
|---|---|---|
| Hatchback | `godot/assets/vehicles/interior_hatchback.glb` | `godot/assets/vehicles/fleet_hatchback.glb` |
| Sedan | `interior_sedan.glb` | `fleet_sedan.glb` |
| Taxi | `interior_taxi.glb` | `fleet_sedan.glb` |
| Sports coupe | `interior_coupe.glb` | `coupe.glb` |
| Auto-rickshaw | `interior_auto.glb` | `fleet_auto.glb` |
| Bus | `interior_bus.glb` | `fleet_bus.glb` |
| Lorry | `interior_lorry.glb` | `fleet_lorry.glb` |
| Luxury SUV | its cabin is inside `luxury_suv.glb` (objects named `INT_…`, from `tools/suv_interior.py`) — talk to us first |

The game loads `interior_<kind>.glb` automatically when that file exists. If you replace one, the game uses
yours the next time it's opened. No code change is needed.

> New car bodies (hatchback / sedan / taxi, from `tools/carbody.py`) are being designed; until they replace the
> `fleet_*.glb` files in the game, design around the `fleet_*.glb` shells above. We'll tell you when they switch.

## 2. Set up the Blender scene

1. Blender 4.x / 5.x, **metres**, scale 1.0.
2. **File → Import → glTF 2.0** the exterior shell (table above). Use it only as a reference: don't export it.
3. Axes (same as the exterior):
   - **+X = front of the vehicle** (the nose)
   - **+Y = the vehicle's left**
   - **+Z = up**, ground at Z = 0
   - the origin is the vehicle's origin (don't move the shell)
4. **India is right-hand drive:** the driver sits on the **right**, which is **−Y**.

## 3. Required markers (Empties)

| Empty name (exact) | Where | Why |
|---|---|---|
| `Eye` | the driver's eye position (seated, ~1.1–1.2 m up in a car) | the cockpit camera is placed here |
| `SteeringPivot` | the centre of the steering wheel (or the handlebar centre) | the game **turns everything parented to it** |
| `Cluster` | the centre of the instrument cluster face | the game draws **live gauges** here (speed, revs, fuel, indicators) |

**Steering wheel:**
- Parent every steering-wheel mesh (rim, spokes, hub, buttons) to `SteeringPivot`.
- The pivot's **local Z axis must point along the steering column, toward the driver**. The wheel spins around that axis.
- The column, stalks and shroud must **not** be parented, because they don't turn.

**Cluster:** you can model the binnacle and dial rings. Leave the dial *faces* plain dark, because the game draws the needles and numbers on top. If you'd rather have your own static gauges, still keep the `Cluster` empty.

## 4. What the game expects of the model

- **The exterior is one-sided.** From inside the car you see *through* the body panels, so the cabin must close itself:
  - door cards from the floor up to the window line
  - pillar trims (A, B, C)
  - headliner
  - floor and carpet
  - the dashboard reaching the windscreen base
  
  Windows stay open (the game adds tinted glass from the exterior).
- **Keep the windscreen view clear:** nothing above the dash top in front of `Eye`, except the rear-view mirror and the sun visors folded up.
- **Polygon budget:** about **40,000 triangles** for a car cabin (up to 60,000 for a bus). Apply subdivision before export. Bevel only edges you can see.
- **Materials:** use Principled BSDF with Base Color, Roughness, Metallic and Normal map, plus Emission for screens and backlights.
  - **Image textures are fine.** UV-unwrap the mesh, keep textures **2048 px or smaller**, and share them across parts where possible (one leather, one plastic, one fabric).
  - **Procedural textures (Noise, Voronoi, Wave…) do not export.** Bake them to images first.
  - Glass inside the cabin (gauge covers): keep alpha low or skip it.
- **No brand logos, badges or real trademarks** (project rule). Generic shapes only.
- **Name meshes clearly**, e.g. `Dash`, `SeatFrontL`, `DoorCardFR`. The game merges nothing; names help debugging.
- Apply all transforms (**Ctrl+A → All Transforms**) before export.

## 5. Export settings (File → Export → glTF 2.0)

- Format: **glTF Binary (.glb)**
- Include: **Selected Objects** (select the cabin meshes, the three empties and the wheel parts; **not** the reference shell)
- Transform: **+Y Up = ON**
- Data → Mesh: **Apply Modifiers = ON**, UVs ON, Normals ON
- Material: **Export**; Images: Automatic (embedded in the .glb)
- Animation: OFF

Save as `godot/assets/vehicles/interior_<kind>.glb`. Keep the **source .blend** too, in `art/interiors/<kind>.blend`.
If a .blend is over 50 MB, tell us first: it needs Git LFS.

## 6. Test it in the game

From the project folder on a Mac:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --path godot res://scenes/drive.tscn -- --vehicle=hatchback --cam=1 --time=10
```
(`--vehicle=` hatchback | sedan | taxi | coupe | auto | bus | lorry; `--cam=1` = cockpit view; `--time=22 --lights` for night.)
In the game: **V** changes camera, the mouse looks around in the cockpit, **A/D** turns the wheel. Check that:
- the camera sits in the driver's seat, not inside the headrest or the roof
- the wheel turns around its own centre and doesn't wobble
- the gauges appear on your cluster
- you can't see outside through any gaps in the doors, floor or roof

## 7. Sending your work (GitHub)

The project is at **github.com/barathraj130/MISTVILLAGE**. The owner (barathraj130) adds you once:
**GitHub → the repository → Settings → Collaborators → Add people** (your GitHub username).

Then, on your computer:
```bash
# once
git clone https://github.com/barathraj130/MISTVILLAGE.git
cd MISTVILLAGE

# every time you start new work: get the latest, make your own branch
git checkout main
git pull
git checkout -b interior-hatchback          # one branch per vehicle

# … design in Blender, export to godot/assets/vehicles/interior_hatchback.glb,
#     save the source to art/interiors/hatchback.blend …

git add godot/assets/vehicles/interior_hatchback.glb art/interiors/hatchback.blend
git commit -m "Hatchback interior: new dash, seats and door cards"
git push -u origin interior-hatchback
```
On GitHub, open a **Pull Request** from your branch into `main` with a few screenshots. We review it in Blender and
in the game, then merge it. **Don't push directly to `main`.**

GitHub Desktop (https://desktop.github.com) does the same with buttons: Clone → New branch → Commit → Push → Create
Pull Request.

## 8. Checklist before you send

- [ ] Right-hand drive; driver on −Y
- [ ] `Eye`, `SteeringPivot` (local Z = column toward the driver), `Cluster` present and named exactly
- [ ] Wheel parts parented to `SteeringPivot`; column / stalks not
- [ ] Cabin closed: door cards, pillars, headliner, floor
- [ ] ≤ 40k triangles (cars), textures ≤ 2K, no procedural-only materials, no logos
- [ ] Transforms applied, exported as `.glb` with +Y Up, source `.blend` saved
- [ ] Tested with `--vehicle=<kind> --cam=1`
