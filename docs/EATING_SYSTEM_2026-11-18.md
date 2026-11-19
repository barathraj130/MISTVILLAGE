# Eating at the table: the universal eating and drinking system (18–19 November 2026)

The universal eating brief's first step: the game's real food inventory, where it's eaten, and the character rig.
Nothing in the "tested" column is claimed until it has been seen in the running game.

## 1. Where Karthik eats

| Place | Script | How it plays now |
|---|---|---|
| Home (Amma's cooking, by day and hour) | `scripts/story/dine3d.gd` (from `tasks.gd` for `home_meal` visits) | 3D table; until today his canned `SitEat` clip (hand down, hand up) with a ball following his fist. **Being replaced** by `eat_ik.gd` (below) |
| Eateries (the menu card, then his table, then the bill) | `scripts/story/order_screen.gd` | the same canned `SitEat` clip |
| The food models | `scripts/story/food_kit.gd` | built in code; each dish has parts (an idli, a katori of sambar…) that shrink a bite at a time (`Kit.bite`) |

## 2. The rig (story_karthik.glb)

- Bones: pelvis, spine 01–03, clavicles, upper and lower arms, hands, **three joints for every finger and the thumb**
  on both hands, neck, head, legs. No jaw or eye bones.
- Face (MakeHuman expression units as blend shapes): `mouth-open`, `mouth-pursing`, `mouth-compression`,
  `mouth-corner-puller`, `mouth-protusion`, `eye-*-closure` (blinks, `face.gd`), `eye-*-slit` (lids lowered),
  eyebrow units.
- Clips: Sit, SitEat, SitTalk, hand poses (HandGrip, HandFist, HandOpen…), locomotion.
- IK already in the game: `scripts/drive/rider_ik.gd` (two-bone arms and legs, hand orientation, finger curls), used
  for steering and handlebars. The eating IK extends it.

## 3. The food inventory (story/food.json: 35 dishes) and how each is eaten

| Style | How (right hand unless said) | Left hand | Dishes |
|---|---|---|---|
| **pinch-dip** | a piece pinched off (thumb, index, middle), dipped in sambar or chutney, to the mouth | rests by the plate | idli, idli_vada, vada, paniyaram, pongal's vada |
| **tear-dip** | the bread held down, a piece torn off, dipped, to the mouth | holds the bread / plate edge | dosa, masala_dosa, chapati, parotta, poori, appam, idiyappam, chicken_curry, malabar_chicken |
| **mix-scoop** | rice mixed with the curry by the fingertips (small circles on the plate), gathered, scooped up on the fingers, the thumb pushing it in | steadies the plate or leaf | meals, mini_meals, home_meals, kuzhambu_rice, thali, exec_lunch, jail_meals, curd_pickle |
| **scoop** | gathered and scooped (no curry to mix) | rests by the plate | lemon_rice, tomato_rice, curd_rice, veg_rice, pongal, upma, puttu |
| **spoon** | a steel spoon held between thumb and the first two fingers, scooped from the bowl | holds the bowl | payasam, kanji, fried_rice (eateries) |
| **sip-cup** | a steel tumbler or cup gripped round, lifted, tilted to the lips, sipped, put down | rests | tea, filter_coffee (and dosa_coffee's coffee) |
| **sip-glass** | a glass gripped round, sipped | rests | fresh_lime |

**Not in the game** (the brief's examples with no dish in `food.json`): burger, pizza, French fries, sandwiches,
momos, noodles, pasta, soup, ice cream and cones, cake, juice, milkshakes, chopsticks. They get no profile until a
dish exists; the styles above cover what a menu could add for most of them (spoon for soup and ice cream, a two-hand
hold would be new).

## 4. The system (reusable, data-driven)

- `scripts/story/eat_ik.gd`: the eating IK over the Sit pose (extends the rider IK): the right hand to a fingertip
  target with its fingers' direction and a pinch; the left hand's own target; the head and spine following what he
  looks at.
- `dine3d.gd` (and next `order_screen.gd`): a **bite plan** per bite from the dish's style: keyed fingertip positions
  (reach, pinch, dip, to the mouth, in, back), eased, varied every bite (timing ±15–20 %, positions ±1 cm, a stir now
  and then, a piece eaten without a dip, a glance up); the morsel at the fingertips between the pinch and the lips;
  the plate's part reduced at the pinch and every other dip (so the meal's bite count and its completion trigger are
  as before); the face: the mouth opening for it, the lips closing, chewing, a swallow, the lids lowered to look at
  the food, blinking.
- Test: `--dineviews=DIR` stops the second bite at its moments (reach, pinch, dip, mouth) and takes each from the
  meal's own camera, the front, his right side and close up.

## 5. Order of work

1. pinch-dip with idli at home: build, test from the four cameras, fix.
2. One representative of each other style, tested the same way: dosa (tear-dip), meals (mix-scoop), lemon rice
   (scoop), payasam (spoon), tea (sip-cup), fresh lime (sip-glass); the spoon, tumbler and glass as small props in the
   hand.
3. The eateries (`order_screen.gd`) on the same system.
4. Roll out to every dish; the coverage table filled in with what was tested and seen.

## 6. The system as built (19 November)

One controller for every table; what's eaten decides how, never the mission.

| Brief's name | Here | What it does |
|---|---|---|
| FoodInteractionManager / EatingStateMachine / EatingAnimationController / FoodConsumptionManager | `scripts/story/eater.gd` | picks what to eat next, builds each bite from the part's profile, runs the states, takes food off the table at the right moments, the face (mouth, chewing, swallow, lids), the left hand, the look |
| FoodInteractionProfile | `scripts/story/eat_profiles.gd` | eleven methods as data (hand, grip, grip size, piece, size, dip, mix, left hand, utensil, tilt, chew, pace); a part's method from the part itself, the dish's `eat` in food.json, or its kind |
| HandPoseController / FoodAttachmentController / UtensilInteractionController / DrinkInteractionController | `scripts/story/eat_ik.gd` | the arms (elbow on its own hinge, forearm turn split from the wrist, wrist range limits, no flips), five grips (pinch, scoop, spoon, wrap, hold), the left hand's grip, the hand socket (food, spoon, slice, burger, tumbler placed inside the solve, aimed by its working point: a spoon's bowl, a rim, a tip at the lips) |
| Dishes, utensils, drinks | `scripts/story/food_kit.gd` | every dish's parts; tumblers and glasses (the drink a column that a sip shortens), spoon, fork laid by the dish |
| Places | `dine3d.gd` (home), `order_screen.gd` (eateries, the five-star) | only the place: the table, the camera, the words, the card, the bill. Both use eater.gd |
| Test bench | `tests/eat_test.gd`, `tests/eat_coverage.gd` | any dish at a table, its states printed, filmed from front, side, close, hand; every dish's resolved method |

States (each bite uses the ones its profile needs): IDLE, LOOK_AT_FOOD, REACH, GRIP, PREPARE_BITE, PICK_UP,
DIP_OR_SCOOP, BRING_TO_MOUTH, BITE_OR_SIP, CHEW_OR_SWALLOW (the hand waits, lowered, until he has swallowed), RETURN,
REST. The meal's count is what came off the table; an eatery's energy is scaled by the share actually eaten.

Methods: tear_dip (poori, dosa, chapati, parotta, appam...), pinch_dip (idli, vada, paniyaram, fries with ketchup),
mix_scoop (rice with sambar, meals), scoop (rice alone), side_scoop (what's left of a curry), spoon (payasam, kanji,
fried rice, ice cream), fork (noodles, wound on), hold_one (a pizza slice by its crust), hold_two (a burger in both
hands), sip_cup (tea glass, coffee tumbler), sip_glass (fresh lime).

Rig findings (19 November): no forearm twist bones (upper arm, lower arm, hand only; the clips key only those);
the elbow's hinge measured from the Idle clip (lower arm local (0.99, 0, ±0.15)); the palm's normal and the fingers'
axis measured from the rest pose; the lips measured from the face's mouth-pursing shape (3.5 cm under the head bone,
10.3 cm before it: the old guess, 9 cm under, was the chin). The candy-wrapper twist and the hand flips came from
the IK (shortest-arc turns, a free hand, the twist taken the long way round), not the skin weights: fixed in the
solve (FOREARM_SHARE 0.7 of the turn in the forearm, the wrist's own twist within 26 deg, flexion 70, extension 55,
radial 20, ulnar 30; the turn kept continuous frame to frame).

New dishes for the brief's test list (food.json and the menus): burger and pizza (the five-star's all-day snacks),
ice cream (its desserts), noodles (the mess's new Chinese section, with the fried rice that had no menu).

## 7. Contact: hands, table, plate, vessels, food (the collision brief, 19 November)

There are no physics bodies at the table and none are needed: the hands are posed by the IK every frame, so the
contact is solved in the same pass, against simple shapes, instead of physics queries for every finger.

- Solids: the table's top (a plane), each serving's plate (a thin disc at its real face), each katori, bowl and
  tumbler (open vessels: the wall and rim are solid, the inside is where fingers dip into sambar), the food still on
  the plate (soft domes). food_kit.gd declares each dish's solids; eater.gd puts them in the world every frame (a
  lifted tumbler's goes with it; what the hand is holding is skipped: the fingers wrap it).
- After the grip, about 25 points per hand (every finger's middle and end joints, the fingertips, the hand's root,
  the knuckles) are checked. A digit that's in is turned out at its root along the push, up to four small steps (the
  finger opens, the thumb lifts alongside), so the hand adapts instead of freezing; if it still can't come out, or the
  palm or a knuckle is in, the whole hand is moved out by the depth, built up over a few frames and let back down
  slowly (it settles on the surface, no buzzing). The fingertips may touch food (they pick it up); the palm and the
  knuckles may not go into it.
- Root causes fixed with it: the resting hands were posed tipped down at the table (now nearly flat, the fingertips
  just touching it); the relaxed thumb hung under a flat palm into the table; the left hand's rest spot lay on a
  meals leaf's katori (now the first spot clear of every vessel); a tumbler was grasped so low the little finger's
  knuckle went under the table (now round its middle); a fork lying flat was taken from the side (now from above).
- Measured (tests/eat_test.gd's EATCONTACT line: the deepest any hand point went into a solid after the pass, after
  the first second; and how many frames had any point more than 3 mm in): see the table below.

## 8. Coverage

Every dish in story/food.json resolves to a method (tests/eat_coverage.gd). "Bench" = run on the test bench
(tests/eat_test.gd: two or three bites, filmed, food taken off the table, no script errors). "In game" = played in
the story at its real place.

| Method | Dishes | Bench | In game |
|---|---|---|---|
| tear_dip | poori, dosa, masala dosa, dosa & coffee, chapati, parotta, appam, idiyappam, chicken curry & malabar chicken (parotta) | poori, dosa, masala dosa, dosa & coffee, chapati, parotta, appam, idiyappam | poori (home breakfast) |
| pinch_dip | idli, idli & vada, vada, paniyaram, burger's fries | all five | |
| mix_scoop | meals, mini meals, home meals, thali, executive lunch, jail meals, pongal, upma, puttu, lemon/tomato/curd/veg/kuzhambu rice, curd & pickle | meals, pongal, upma, puttu, lemon rice, curd rice | |
| spoon | payasam, kanji, fried rice, ice cream | all four | |
| fork | noodles | noodles | noodles (the mess) |
| hold_one | pizza | pizza | |
| hold_two | burger | burger | burger (the five-star) |
| sip_cup | tea, filter coffee, dosa & coffee's coffee | tea, filter coffee | tea (the mess) |
| sip_glass | fresh lime | fresh lime | fresh lime (the five-star) |
| side_scoop | what's left of any curry, chutney, masala, pickle | (in the meals, idli, poori runs) | |

Not run on their own: mini meals, home meals, thali, executive lunch, jail meals (the meals build), tomato, veg and
kuzhambu rice, curd & pickle (the rice build), chicken curry and malabar chicken (the parotta build): the same build
and method as dishes that were. Not in the game at all (no dish in food.json, so no profile yet): roti, naan,
paratha, dal, paneer, chole bhature, samosa, puffs, sandwiches, pakoda, bajji, momos, pasta, soup, manchurian,
cake, sweets, water, juice, milkshakes. Their methods exist (tear_dip, pinch_dip, spoon, hold_one, sip_glass); each
needs its food_kit.gd build and a food.json entry.
