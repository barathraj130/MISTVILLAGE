# Eating at the table: audit and plan (18 November 2026)

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
