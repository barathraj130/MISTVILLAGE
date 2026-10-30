# The Mist Village — Game Rules (draft, 2026-10-23)

The rules the player lives by, in both parts of the game. Story and systems are in [GAME_DESIGN.md](GAME_DESIGN.md);
this file is the rulebook. All money is ₹ play money, and every bank, court, police station and company is fictional.
Values marked **(in game)** are already built; everything else is to build.

## 0. Principles
- **Realistic but forgiving.** Real Indian traffic law and real consequences, but warnings come first and every
  mistake can be recovered from.
- **Never game over.** Jail, debt, a seized car or a cancelled bail are hard chapters you play through, not the end.
  The story always goes on.
- **Learnable, not random.** Cameras stand at fixed junctions, prices and hours are fixed, and the police behave the
  same way every time. A careful player can always avoid trouble.
- **No gore, no deaths caused by the player.** People knocked down are hurt and taken to hospital; nobody dies
  because of the player.

## 1. Time
- **One game day lasts 48 real minutes:** 1 real minute = 30 game minutes. (In game it is 4 real hours a day, so
  `MINUTES_PER_SECOND` in `scripts/drive/sim.gd` changes from 0.1 to 0.5.)
- A new game starts on **day 1 at 6:30 AM (in game)**. A **week** is 7 game days, starting on Monday; weekly bills
  fall due on Monday morning.
- The clock **runs** while you drive or walk. It **pauses** in menus, on the phone screen and in cutscenes.
  Conversations take fixed game time (most of them 10–30 minutes).
- **Sleep, food and stress** (built 2026-10-29: `scripts/city/life.gd`, GAME_DESIGN.md §3):
  - **Tiredness** climbs about 5.5 a game hour (faster driving). Only sleep clears it, and a sleep lasts **at least
    5 game hours** (longer the more tired he is): at home, in a hotel room, or in the car (badly: stress up). At 100 he
    falls asleep where he is, or dozes at the wheel (the screen dims) until he pulls over.
  - **Energy** (food) falls about 7 a game hour. Meals fill it: at home from the month's groceries, or paid for
    outside (a mess ₹90, a restaurant ₹120, tea and a vada ₹20). Under 25 he can't run; at 0 stress climbs.
  - **Stress** rises with traffic, challans, fines and bills, and falls with pay and time off (a match, a film, tea,
    a quiet sit in a church or temple).
- **Opening hours (in game):** shops, banks, offices and garages keep real hours. Fuel stations, hospitals and police
  stations never close.
- **Story-timed drives run on real time.** On drives where the story's timeline matters (the night of the crime,
  a delivery deadline, a witness's "I saw him at 10:12"), the clock slows to 1 game minute per real minute. The
  objective says so, and the player's drive then really takes the time it would take in Coimbatore.
- **Evidence travel times are real-world times.** When the investigation asks whether someone could get from A to B
  by 9:40, the answer uses the real road distance and real traffic speeds, not the compressed game clock.

## 2. Money
- **Start:** ₹25,000 in the wallet **(in game)**, a borrowed hatchback and a rented room.
- **Wallet and bank:** cash goes in the wallet, and the bank account is reached on the phone or at an ATM. Fines and
  bills are paid from the wallet first, then the bank.
- **Running costs:**
  - Fuel at real pump prices (diesel ₹94 a litre **(in game)**, petrol ₹101).
  - Rent: ₹1,200 a week.
  - Food: the month's groceries at the kirana (₹4,500, about 90 meals at home), or meals bought outside (§1).
  - Repairs at garage prices.
  - Optional insurance: ₹600 a week, covers 70% of repairs.
- **Can't pay?** Nothing is taken that you don't have; the bill stays owed.
  - Unpaid rent: after 2 weeks the owner asks you to leave. You sleep in the car until you pay.
  - Unpaid bank EMIs: see §7.
  - Unpaid fines: see §3.

## 3. Driving and traffic law
**Speed limits:**

| Road | Limit |
|---|---|
| City and town streets | 50 km/h **(in game)** |
| Residential lanes and near schools | 30 km/h |
| Highways (Coimbatore–Mettupalayam) | 80 km/h |
| The ghat road | 40 km/h |
| Hairpin bends | 20 km/h |

**Fines:**

| Offence | Fine | Points |
|---|---|---|
| Jumping a red light | ₹1,000 **(in game)** | 2 |
| Speeding | ₹1,000 **(in game)**; ₹2,000 if 20+ km/h over | 2 / 4 |
| Driving through a police check | ₹2,000 **(in game)** | 4 |
| No helmet on a two-wheeler (rider or pillion) | ₹1,000 | 2 |
| No seat belt | ₹1,000 | 1 |
| Phone in hand while driving | ₹1,500 | 3 |
| Wrong way on a one-way street | ₹1,500 | 3 |
| No-parking zone | ₹500, or the car is towed: ₹1,500 to get it back | 0 |
| Dangerous driving (near-misses, mounting the footpath) | ₹5,000 | 6 |
| Driving while suspended | case filed (§4) | — |

**How fines are given:**
- **Cameras** at fixed junctions (red-light and speed) send an **e-challan** to your phone **(in game)**. It stays
  unpaid until you pay it on the phone or a police check collects it.
- **Police who see you** stop you. The **first minor offence of each game day gets a warning only**: no fine, no
  points. After that the fine and points apply.
- **Police checks** appear now and then on the road ahead **(in game)**. Stop beside the officer and your papers are
  checked. Unpaid e-challans are collected there, and if you can't pay, each one adds 1 point instead.
- **Story drives are no exception** (decided 2026-10-23): fines, points and cameras apply during scripted story
  drives too, chases included. The story never forces an offence; there's always a lawful way through, and taking
  it is part of the challenge.

**Licence points:**
- Points last 30 game days. Reaching **12 points** suspends your licence for 7 game days.
- While suspended you can take an auto or a bus, walk, or have a hired driver. Driving yourself anyway is a case (§4).
- A **clean week** (no points) takes 2 points off.

## 4. Police, courts and jail (when the police find out)
The full ladder is in GAME_DESIGN.md (Law and consequences). The rules that set it:
- **Who finds out:**
  - Police within 60 m who can see you: always, at once.
  - CCTV at main junctions, shops and fuel stations: later.
  - Bystanders: sometimes; they may report your plate.
  - Nobody: no case.
- **Record levels:** clean → warning → fined → case filed → convicted. Each step up makes police checks stricter and
  loans dearer. A clean month steps it back down, but never below "fined" once you've been to court.
- **Running from the police** turns any offence into a chase. Getting away makes you wanted for 3 game days. Getting
  caught means arrest. Stopping and cooperating always lowers the outcome.
- **Court** decides: a fine, a fine plus licence suspension, or jail.
  - Lighter outcomes come from: a lawyer (₹5,000–₹25,000), surrendering, staying to help at a collision, and a clean
    record.
  - Heavier outcomes come from: fleeing, earlier cases and unpaid fines.
- **Jail is never longer than 15 game days** (12 real hours of play at most). It is playable, and its length goes
  down for good behaviour (§4 of the design: routine, prison jobs, inmates).
- **Outside while you're inside:** rent and EMIs keep falling due, hired drivers keep working and your businesses
  earn less.

## 5. Bail (Part 1 only)
- **Sign at the police station every evening between 6 and 7 PM**, game time. Your phone reminds you at 5 PM and
  again at 5:45.
- **Night story events move the signing** (decided 2026-10-23): on a day with a story event in the evening or at
  night, the inspector sets an earlier window, **4 to 5 PM**. You're told the day before (a call from the station),
  the reminders move with it, and the late and missed rules below apply to the new window.
- **Late or missed signings:**
  - Signing between 7 and 8 PM is **late**: the inspector notes it, and three lates count as one missed signing.
  - **Missing a day** (no signing by 8 PM) is a **strike**:
    1. The inspector warns you.
    2. The inspector's suspicion rises. Witnesses get harder to talk to and the police share less.
    3. A third strike within 7 game days **cancels bail**. You're arrested at home or at the next police check,
       spend 2–5 game days in jail (a story chapter), and a lawyer (₹15,000) gets bail restored.
  - A strike older than 7 days drops off.
- **You may not leave Coimbatore district.**
  - The ghat to Kotagiri is closed through Part 1: the police at the foot of the ghat turn you back.
  - Any other road out of the district turns you back at the district border check. The second attempt is a strike.
- **Hospital, jail or a story event** that keeps you away excuses the signing automatically.

## 6. Work and jobs
- Jobs arrive on the **phone job board**: taxi fares, deliveries, textile runs, market runs and tourist pickups. You
  accept a job, and its pickup and deadline are fixed when you do.
- **Rating:** each job gets 1–5 stars for being on time, smooth driving (no hard braking or swerving), no damage and
  passenger comfort.
  - Pay goes from 60% of the fare at 1 star to 120% at 5 stars.
  - Your average over the last 20 jobs decides which jobs are offered: better rating, better jobs.
- **Cancelling** an accepted job costs 1 star on your average. Arriving more than 30 minutes late counts as a
  cancellation.
- Story days have fewer jobs. The investigation always takes priority, but work pays the bills.

## 7. Bank and loans
- **Credit score** runs from 300 to 900 and starts at 650.
  - Paying on time: +10.
  - Late payment: −30 and a ₹500 late fee.
  - Below 550, no new loans.
- **Loans:**

  | Loan | Size | Interest |
  |---|---|---|
  | Personal | up to ₹50,000 | 16% |
  | Vehicle | up to 85% of the price | 11% |
  | Business | up to ₹5,00,000, needs a 700 score | 13% |

  All are repaid in **weekly EMIs**, taken on Monday morning.
- **Three missed EMIs on a vehicle loan:** that vehicle is **seized**. You get it back by paying everything owed plus
  ₹3,000.
- **Savings** earn 4% a year, paid weekly.

## 8. Collisions, damage and health
- Severity follows impact speed (from GAME_DESIGN.md): **bump** under 8 km/h, **minor** 8–25, **serious** 25–50,
  **critical** over 50.
- **Vehicles:**
  - Damage is tracked in zones and changes how the car drives (over 40% front damage: less power; over 70%: rough
    engine).
  - At 100% the car stops and must be towed (₹1,500).
  - Repairs are paid at a garage; insurance covers 70%.
- **People you hit:**
  - Minor: they get up limping. Serious or critical: they stay down, bystanders gather and an ambulance comes.
  - **Stopping to help** (staying until the ambulance arrives) always lightens the case.
  - **Leaving** is hit-and-run, the worst outcome in court.
- **You:** a serious crash puts you in hospital for 1–3 game days. The bill is ₹2,000–₹20,000, less with insurance.
  You wake in hospital; nothing is lost except time and money.

## 9. Saving
- **Autosave** every morning at 6:30 and after each bail signing. **Manual save** at home.
- One save slot per story; loading an older save is always allowed. Since the game never ends, reloading is your
  choice, not a rescue.

## 10. Goals
- **Part 1** ends when the truth is proven: the evidence assembled, the real killer exposed in court. There's no time
  limit, but the bail rules, bills and suspicion keep pressure on.
- **Part 2** has no end: make The Mist Village the best-loved place in the Nilgiris (guest rating, the stories
  completed, rescues made).

## Open questions
1. Hired drivers' licence points: theirs or yours? Proposed: theirs, but you pay their fines.
