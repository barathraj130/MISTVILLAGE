# The prologue: three ordinary days before the murder (audit and plan, 17 November 2026)

The brief: "3-Day Pre-Murder Prologue, Life Simulation & Gameplay Tutorial". Nothing in the story after it changes:
Day 1 (the promotion, the bank, the refused file, the phone left at the office, the night delivery, the murder that
night) and everything to Day 20 stay as they are, with their evidence and their day numbers.

## Decisions (the user's, 17 Nov)

- **The vehicles: the player chooses at the dealership.**
  - **Keep the old scooter.** Pay for its overhaul (its breakdown, below) and keep it. Buy a motorcycle for himself
    and a new scooter for Divya's college trips. That makes three vehicles and two loans. The story's scooter scenes
    stay exactly as they are, on the repaired old scooter and its existing ₹2,850 instalment.
  - **Trade in the old scooter.** It goes towards the down payment at a broken scooter's low value, and he buys a
    motorcycle and a new scooter. The
    new scooter becomes "the scooter" of the whole story: its loan's EMI replaces the old instalment, and three
    missed EMIs still get it taken. The story's lines about the scooter must read right either way, so they say
    "the scooter", not "the old scooter".
- **His work: driving Raghavan plus deliveries.** Each prologue morning is a short drive with Raghavan, as in
  Day 1. The rest of the day is delivery work on the rider app, which the game already has (`gigs`).
- **Why he buys (the user's word):** only after earning his salary from Raghavan does he decide. With the salary in
  hand as the down payment, he finances the vehicles so he can also earn from deliveries and support his family.
  So the first prologue day is his ordinary working day and payday, and the dealership comes the day after.
- **No day numbers in the prologue.** Its days are shown as dates and weekdays, never "Day −3". Internally the clock
  carries on into Day 1 as it does now.

## Audit: what the game has, and what the prologue uses

| The brief asks | What exists | Use / add |
|---|---|---|
| A story before the story | `story.gd` plays `story/slice.json` (620 steps: home, drive, meet, talk, task, choose, gigs, eat_out, scene, room...) from a new game | A prologue chapter (`story/prologue.json`) played first, then `slice.json` from its first step |
| Home, family, walking, the phone | `home` steps (walk the house, Amma and Divya at their marks, brushing, bath, breakfast), the phone (`phone.gd`: Notes, Messages, Contacts, Map, Camera...) | Used as they are; the morning teaches walking by doing it |
| Hunger, tiredness, stress | `life.gd`: energy (food), tiredness (sleep only), stress (traffic, challans, money, hunger; tea, a film, the match...), `body.gd` shows it on him, F1 shows the bars | Used. Thirst is not added. Stress from missed commitments and family time lowering it are added |
| Money, bills, EMIs | `money.gd`: wallet (`sim.money`), bills with dates and reminders (rent, power, fees, "the scooter's instalment" ₹2,850), unpaid bills coming back as people, the scooter seized after three missed instalments, Bala's loans, Amma's chain; the account frozen at the arrest | **New: `finance.gd`**, loans with the exact EMI (`P·r·(1+r)^n / ((1+r)^n − 1)`, in paise), the schedule, payments, late charges, history. Each loan's EMI becomes a monthly bill in `money.gd`, so the existing reminders, consequences and seizure work for the new loans too |
| Owning vehicles | One "own" vehicle (`karthik_scooter`); takeable street vehicles | **New: `garage.gd`**: the vehicles he owns (kind, registration, paint, fuel litres, tank, km per litre, odometer, condition, loan). Where they're parked |
| Fuel | Only on the mountain drive (`sim.gd`, one diesel tank); the city burns none; the "Petrol bunk" is a shop counter | **New:** each owned vehicle's own tank and consumption (litres per km from the distance and the throttle, more when worn), saved; a petrol bunk step (park at the pump, the attendant, choose ₹ or litres or full, pay cash or UPI, the needle rising) |
| Food | `food.json` (dishes, Amma's meals by day, eateries' menus), `order_screen.gd` (menu, quantities, his table, eating, the bill), the `meal` task, home meals at the table | Used as they are |
| Earning | `gigs`: the rider app's orders (pickup, drop, pay by distance, tips) | Used; its end-of-shift summary also shows distance, fuel used and its cost, the time, and what's left |
| Vehicle condition, servicing | Crash damage (zones, dents) for the drive; no wear, no service | **New:** wear by km and crashes, kept in `garage.gd` (a worn vehicle runs rougher and can break down); the old scooter's breakdown on the first morning (it dies in traffic, he pushes it, the roadside mechanic, a job card with prices, pay); a `service` step used again for its overhaul or later services |
| The dealership | Nothing | **New step `dealer`**: a showroom with the motorcycle and scooters on the floor (walk round them, E: their card with specs and on-road price), the choice of path above, the finance desk (down payment, tenure, the rate, the EMI shown as it's worked out), the loan documents to sign (`tasks.gd` sign), the keys |
| The driving tutorial | Story drive steps with goals | **New step `learn`**: goals done by doing them (start, ride to the cone, brake inside the box, indicate before the turn, the horn, the camera with V, reverse park, get off with F), at the dealership's yard and the road outside |
| Financial dashboard | None on the phone | **New phone app "Money"**: cash, bank, this week's earnings and expenses by kind (fuel, food, maintenance, EMIs, other), each loan's EMI, balance, next due, history |
| Saves | `fines`/`sim` save file (wallet, clock, fuel...), `money.gd` "accounts", `life.gd`, the story's own save | Garage and loans saved in the same file, beside "accounts" |

## The three days (proposal for the chapter)

1. **The first day: his work, the breakdown, and payday.** 06:00 at home in Ganapathy. Walk the house, Amma's
   breakfast, Divya teasing, the phone, the time and weather, his hunger and tiredness. On the way to Race Course the
   old scooter breaks down (the user's word: it has to be repaired while he's riding it, and that's what makes him
   buy a new one). It sputters and dies in traffic, so he pushes it to the kerb (walking with it, the hazard
   lights), and the phone's Map finds a roadside mechanic. The mechanic's verdict comes on a job card: a patch for
   today (paid now, so he's late to Raghavan's), and a worn-out engine that wants an overhaul costing more than the
   scooter is worth. He reaches Race Course late and drives Raghavan's SUV through the day (the driving controls learnt on the job: the comfort of the passenger,
   indicators, the horn, the cameras, parking at the office). Evening: the month's salary lands in his account
   (the phone's message, the bank balance). At home the sums with Amma: the scooter's overhaul against a new
   one, Divya's fees, the rent, the house. He decides to buy on finance and earn from deliveries too. He rides the
   patched scooter home, and it coughs at every signal. Dinner at the table, sleep.
2. **The second day: the dealership.** A short morning drive with Raghavan (he lets him go at noon). At the
   dealership (a made-up name, on a real road) he inspects the motorcycles and scooters, compares prices and specs,
   and makes the choice (keep the old scooter and buy one for Divya, or trade it in). Then the finance desk (the
   salary as the down payment, tenure, rate, the EMI worked out in front of him), signing each loan, the keys. The
   tutorial on the new motorcycle in the yard and on the roads outside (start, throttle, brake, indicate, horn,
   camera, reverse, park, get off). The rider app sign-up. Home: Divya and her new scooter (on that path), dinner.
3. **The third day: deliveries and responsibility.** The morning drive with Raghavan, then the first delivery
   shift on the motorcycle: find the order, pickup, drop, pay, and the shift summary (distance, fuel used and its
   cost, time, earnings). The fuel runs low: the petrol bunk. Lunch at a roadside stall or a restaurant. On the keep path, the old scooter
   comes back from its overhaul (paid). The phone's Money app: both EMIs, the first due
   dates, what's left this month. Traffic and long hours raise stress; tea, family and sleep bring it down. That
   night he sleeps. Then the story's first day begins as it does now (06:30, the same home step), and the murder
   comes that night as written.

## Build order (each one tested in the game and committed)

1. **Systems:** `finance.gd`, `garage.gd`, fuel in the city per owned vehicle, saves; a test that checks the EMI
   arithmetic against the formula, two loans, payments, a late charge, a save and a load.
2. **The dealership** (`dealer` step, the showroom room, the finance desk) and the **tutorial** (`learn` step).
3. **The petrol bunk** (`fuel` step) and the gigs summary.
4. **The service centre** (`service` step) and the phone's **Money** app.
5. **The prologue chapter** (`story/prologue.json`): the three days put together; New Game plays it, then Day 1.
6. **The whole run tested:** prologue to Day 1's first steps, both dealership paths, saves and loads in the
   middle, the story's evidence and day numbers unchanged.
