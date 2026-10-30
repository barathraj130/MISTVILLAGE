# The Mist Village — Game Design

All money, banks, police and courts are fictional. Public places keep their real names; privately owned businesses
get names of the story's own. No real brands.
The rulebook (time, money, traffic law, police, bail, work, bank, collisions, saving) is [GAME_RULES.md](GAME_RULES.md);
the story, cast, crime, evidence and acts are in [STORY_BIBLE.md](STORY_BIBLE.md).

**v2, 2026-10-30.** §§0–7 bring the design up to date with what's been built since 2026-10-11 and design how the
pieces make one game. Everything decided before stays as it was (from "Structure" on). Items marked **(proposal)**
are new and wait for a yes.

## 0. The game in one paragraph
You are Karthik, 28, a driver in Coimbatore who lives with his mother and sister in a rented house in Ganapathy.
The game is his life, played day by day in the real city: driving, working, eating, sleeping, keeping his family
going. Then his employer is murdered and the police say he did it. On bail, signing at the police station every
evening and barred from leaving the district, he must keep his family fed and clear his name in the same days:
working the city's people and places for evidence until the truth comes out. Clearing it gives him The Mist Village
resort in the Nilgiris, and Part 2, a life in the hills.

## 1. Pillars
1. **The real Coimbatore.** The streets, landmarks and places as they are; every building can be walked into, and
   each kind of place is what it is inside (a mess, a bus stand, the Collectorate, Perur temple).
2. **An ordinary man's life.** Money, food, sleep, stress and family are felt every day. Nothing is abstract: rent
   is paid, meals are eaten somewhere, tiredness ends in sleep.
3. **The story is the spine.** Part 1 is a thriller with a fixed truth (STORY_BIBLE.md); the life systems give it
   pressure and the city gives it its evidence.
4. **Realistic but forgiving.** Real law and real consequences, warnings first, never game over (GAME_RULES.md §0).
5. **Respect.** People of every faith, age and income as they are; modern India as well as old (five-star hotels,
   malls and colleges beside messes and tea stalls); places of worship shown with care (nothing of a sanctum).

## 2. The day (the core loop)
One game day is 48 real minutes (1 real minute = 30 game minutes).

| Time | What happens | Systems |
|---|---|---|
| 6:30 Wake at home | Bathe, brush, eat Amma's breakfast; she and Divya talk about the day | Home visits, groceries, energy |
| Morning | The day's story objective (Part 1), or work: driving jobs, delivery shifts | Story steps, job board, rider app, comfort and delivery ratings |
| Midday | Lunch somewhere: a mess, the tea stall, a restaurant, the five-star hotel; errands (bank, kirana) | Eat out, wallet, energy |
| Afternoon | Leads and witnesses (Part 1, from Act 3), work, or time off when stress is high | Investigation, leisure, stress |
| 5 PM | Phone reminder: sign at the station | Bail |
| 6–7 PM Sign at the station | The inspector, Constable Selvi, the same faces on the bench | Bail strikes, suspicion |
| Night | Story events, night jobs, dinner at home (or out), the family | Story, relationships |
| Sleep | At least 5 game hours; at home, in a hotel, or in the car | Tiredness |

A day can't hold everything: work pays the bills, leads clear his name, his body and his family need time, and the
signing pins every evening. Choosing what to give up is the game.

## 3. Karthik: body and mind (built 2026-10-29)
Three meters, shown under the wallet, kept in the save file (`scripts/city/life.gd`):

| Meter | Goes up / down | When it's bad |
|---|---|---|
| **Energy** (food) | Down about 7 a game hour (faster working); up with a meal: home (one of the month's groceries), a mess or restaurant (₹90–120), the tea stall (₹20), a kirana snack (₹30), the five-star (₹1,450) | Under 25: hungry, can't run. At 0: stress climbs |
| **Tiredness** | Up about 5.5 a game hour, faster driving; only sleep clears it, at least 5 game hours: home, a hotel room (₹1,800) | Over 80: warned. At 100: asleep where he stands (5 hours, badly), or dozing at the wheel until he pulls over |
| **Stress** | Up with traffic, challans, fines, money going out, hunger; down with pay coming in and time off: a match at Nehru Stadium (₹60), a film at a mall (₹190), tea, a pew at Christ the King, prayer at Perur temple | Over 75: warned. Over 90: can't run |

**How the meters meet the story (proposal):**
- **Stress at the station.** A stressed Karthik gets the inspector's sharper questions and fewer calm answers to
  choose from (Act 2 and every signing). Time off before a hard conversation is a real tactic.
- **Tiredness on the road.** Over 80, steering is slower and the comfort rating harder to keep; night jobs cost
  the next morning.
- **Family.** Dinner at home with Amma lowers stress more than eating out, and missed dinners worry her
  (STORY_BIBLE.md §7). Divya can be taken to the mall or a match (lowers both their stress; Act 3 bullying).
- **Money.** Leisure and good food cost money the family needs: the meters push the player to work, the story
  pushes them to investigate.

## 4. The city: what every place is for (built 2026-10-28 to 10-30)
Every building opens: landmarks into their own rooms, ordinary buildings by kind (houses vary, shops are a kirana,
tea stall, restaurant or bank). Public rooms have people sitting, queueing and walking through, and their own sound.

| Place | In play now | In the story (proposal where new) |
|---|---|---|
| Home, Ganapathy | Wash, eat (groceries), sleep | Family scenes; the arrest at the door (Act 2) |
| Raghavan Developers, Gandhipuram | Story office | The work phone; Muniyandi the watchman (E06), the DVR (E07) |
| Kovai Nagar Co-op Bank | Story errand | The ₹4 lakh withdrawal; **(proposal)** the account statement Sundaram subpoenas |
| Nagar Police Station | Story room | The interrogation (Act 2); the evening signing every day |
| Messes, restaurants, tea stalls | Eat, lower stress | Sekar's tea shop on the road west (E08); gossip that hurts the family (Act 3) |
| The Siruvani Grand (five-star) | Lunch | **(proposal)** where Suresh meets the land buyers; a doorman who remembers faces |
| District Collectorate | People, counters | **(proposal)** the patta / land counter: the Green Valley land records that show Suresh's deal (motive, with E15) |
| Coimbatore Junction, bus stands, airport | People, sound | **(proposal)** timetables and CCTV for the journey reconstruction; where Pandi tries to leave town (Act 6) |
| Government Hospital, Kongu Multispeciality | People | **(proposal)** the post-mortem report (time of death); Amma's check-up when gossip wears her down |
| Malls, Nehru Stadium | A film, a match | Time off; **(proposal)** taking Divya out |
| Christ the King, Perur temple | A quiet sit, prayer | Time off; **(proposal)** Meenakshi at Perur after the funeral, where she first listens to him |
| Velliangiri College | Lobby, classroom | **(proposal)** Divya's college: the bullying (Act 3), her friends who help read the DVR |
| Kovai Trade Fair Complex | Expo hall | **(proposal)** Joseph the accountant at a stall; where Raghavan's firm showed Green Valley |

## 5. The investigation (Part 1, Acts 3–6)
As decided (STORY_BIBLE.md §5–6): evidence with source and reliability, the deduction board, relationships,
journey reconstruction on real roads. **(proposal)** How it plays in the city:
- **Leads are places and people.** A lead names someone and where they are at what hours ("the watchman, nights at
  the office building"); walking in and talking is the investigation.
- **People keep hours and moods.** Witnesses are at their place at their times; a stressed or rude Karthik gets less
  from them, and Selvi's help depends on manners (STORY_BIBLE.md §7).
- **The board on the phone.** Evidence cards, people and the timeline in one screen; a hypothesis is "proved" only
  when the cards cover every step (who, how, when, why).
- **The reconstruction is driven.** Proving a timing means driving the route at real time (GAME_RULES.md §1); the
  drive itself becomes evidence.

## 6. What's built, and what's next (2026-10-30)
**Built:** the streamed real city with traffic, signals, cameras, e-challans and police checks; the car, on foot and
the scooter; every building enterable with designed rooms; crowds that sit, queue and walk; room sounds; the story
runner (cards, talk, scenes, rooms, drives with comfort ratings, tasks, home visits, eating out, delivery shifts);
the vertical slice's first day and night (STORY_BIBLE.md §8, S1–S7, plus night delivery shifts); the story cast and
crowd people built in MakeHuman with real walks and runs; Karthik's energy, tiredness and stress; Tamil / English.

**Next, in order (proposal):**
1. **Finish the vertical slice** (S8–S11): the arrest at the door, the interrogation with choices, the first evidence
   on the board, the first lead with Muniyandi, the cliffhanger. Weave the meters in (breakfast, a tired night job).
2. **The bail rhythm:** the evening signing with reminders, lates and strikes, the district border.
3. **The phone:** job board, evidence board, contacts, map with leads.
4. **Act 1 at full length** (3 days, or the slice's one day: open item) and **Acts 3–4**: isolation, the open
   investigation across the city's places (§4).
5. **Acts 5–6** and the ending, then **Part 2** in the Nilgiris.
Alongside: voices, a native-speaker pass on the Tamil, performance on a mid-range PC, then mobile.

## 7. Open decisions for you
1. **The meters in the story:** should stress and tiredness change the story's choices and driving (§3 proposal), or
   stay a life layer beside it?
2. **The places' story roles (§4):** keep, change or drop each proposal.
3. **Act 1's length:** three game days, or the slice's single compressed day?
4. **Platform first:** PC / Mac, or mobile (India)?
5. **Voices:** who records Tamil and English.
6. **The name:** "The Mist Village", or another.

## Structure (updated 2026-10-11: the story is the spine)

**Part 1 — "The Wrong Accusation"** (Coimbatore) — a narrative crime thriller.
An ordinary man's life (work, family, loans, a small business — the Level 1 systems below) is broken when he is
falsely accused of a serious, fictional crime. On bail he must sign at the police station every evening, may not
leave Coimbatore district, and investigates to prove his innocence through evidence, witnesses, real-road travel
times and a legal process. **Ending:** the truth also clears the businessman's family's name; grateful (and
ashamed of having believed the accusation), they give him **The Mist Village** resort in Kotagiri.

**Part 2 — "Life in the Mist"** (Kotagiri and the Nilgiris) — the bail conditions end, he drives up the ghat for the
first time, and the resort life begins (Level 2 below).

### Part 1 story outline (to be written as a story bible before any building)
- **Six acts:** 1 Ordinary life → 2 The accusation → 3 Isolation → 4 Investigation → 5 The second twist (a trusted
  character had a hidden role) → 6 The truth (evidence assembled with legal counsel, manipulation exposed).
- **The businessman** is at the centre of the crime (victim of a fraud / disappearance / death — to decide) and owned or
  was building The Mist Village. The protagonist really met him (a client), which makes the framing believable. The
  real culprit is someone close to the businessman's family (partner / relative).
- **Bail conditions (core mechanic):**
  - **Sign at the police station every evening, 6–7 PM (game time).** The day is free for work, investigation and family;
    each day ends with a drive back across the city in evening traffic; night investigation follows.
  - Missing a signing: warning → the inspector's suspicion grows → risk of bail cancellation and arrest (Law and
    Consequences / jail systems below).
  - The station is a living story place: the inspector, constables (one may quietly help), the same faces on the bench.
  - **May not leave Coimbatore district:** the ghat to Kotagiri is closed through Part 1. The hills are visible on the
    horizon, and the first drive up the ghat is the reward that opens Part 2.
- **Systems:** evidence (id, source, reliability, contradictions, verified / disputed / unverified), deduction board
  (people, places, evidence, events, times, motives; several hypotheses at once; conclusions checked against evidence),
  relationships (trust, fear, loyalty, suspicion, cooperation — shown through behaviour, not numbers), timeline,
  consequences (calls unanswered, business lost, EMIs, family worry), journey reconstruction on real roads.
- **Rules:** fictional characters and crimes; no real CCTV coverage, addresses or allegations; no gore.
- **First build target:** a 20–30 minute vertical slice — morning at home → a drive → a meaningful meeting → the first
  suspicious event → the accusation → the first evidence → a short investigation → a cliffhanger.
- **Decided (2026-10-11):** the businessman is the **victim** (murdered off-screen; no gore) in a land-development
  conspiracy; his **business partner** is the real killer; the protagonist's **close friend unknowingly** leaked his
  movements (second twist); the businessman's family gives The Mist Village at the end.
  **Protagonist's job:** the businessman's trusted **driver, promoted during Act 1 to also be his assistant** (errands,
  calls, payments) — the promotion is Act 1's "opportunity" and gives the killer the car, phone and money trail to frame him.
  **Language:** Tamil and English, the player chooses (dialogue system bilingual from day one).
- **Open:** voice acting; the story bible (to be drafted).

**Level 1 — "From the Plains to the Hills"** (now the ordinary-life layer of Part 1)
Work, borrow, build businesses. (Originally its goal was to buy the resort; now the resort is given at the end of Part 1.)

**Level 2 — "Life in the Mist"** (Kotagiri and the Nilgiris, resort as home base) — becomes Part 2.
Run the resort, explore, rescue, stories → goal: make the resort the best-loved place in the Nilgiris.

---

## Level 1

### Start
Driver in Coimbatore with ₹25,000 (fictional) and a borrowed hatchback, a rented room as home.

### Missions (rated on time, smooth driving, no crashes, passenger comfort; better rating → better jobs)
- **Coimbatore:** taxi fares (railway station, airport, Gandhipuram), parcel deliveries, textile bundles mill → shop,
  school / office rush runs.
- **Mettupalayam:** vegetable market → Coimbatore, tourist pickups from the station, tea transport from estates.
- **Ghat:** tourist tours to Kotagiri; emergency runs in mist / rain (bonus, risk).

### Bank and loans
- Personal, vehicle and business loans; interest; monthly EMIs taken from the wallet; savings deposit.
- Credit score: up for paying on time, down for missing. Low score → no new loans. 3 missed EMIs → a vehicle seized.

### Businesses (daily income vs salaries, fuel, maintenance, rent; hired drivers work while you play)
Tea shop / restaurant → taxi fleet → delivery company → tourist travels → fuel bunk → the resort.

### Life costs
Fuel, repairs, rent, optional insurance. Phone screen: jobs, money, EMI dates, business reports, GPS.

### Collisions (vehicle ↔ pedestrian, vehicle ↔ vehicle / wall)
- Impact speed (and vehicle mass) sets severity: bump < 8 km/h, minor 8–25, serious 25–50, critical > 50.
- Person: stumble → knocked down and gets up limping → stays down, bystanders gather, ambulance comes. No gore.
- Vehicle: damage zones (front / rear / left / right / roof 0–100%): dents at the impact, cracked glass, broken lamps,
  loose bumper; >40% front: less power, steering pull; >70%: smoke, rough engine; 100%: stops, needs tow / repair.
- Repairs cost money at a garage; insurance covers part.
- Traffic brakes / swerves for pedestrians.

### Law and consequences (only if the police find out)
1. **Witnesses:** police within ~60 m with line of sight (certain, immediate); CCTV at main junctions, shops, bunks
   (high, later); pedestrians (medium — may report the plate); nobody (none unless the victim reports later).
2. **Police saw it:** minor → stopped, fine, warning; serious → stopped, case filed, vehicle may be held.
   Running → chase (patrol cars, roadblocks); escape = wanted, caught = immediate arrest.
3. **Learned later → investigation:** an evidence meter fills over game days (CCTV / witnesses / matching damaged
   vehicle / plate). You can surrender (much lighter), repair the car and avoid cameras (slows, doesn't erase),
   hire a lawyer (costs money, lighter verdict), or ignore it → arrest at home or on the road at 100%.
4. **Court:** fine / fine + licence suspension / jail, by severity and evidence. Helps: lawyer, surrender, stayed and
   helped, clean record. Hurts: hit-and-run, past record, unpaid fines.
5. **Jail life (playable):** sentence in game days; routine (wake, work, meals, rest); prison jobs (kitchen, cleaning,
   workshop) earn a little; inmates with stories / later contacts; good behaviour shortens, trouble lengthens.
   Outside, businesses earn less, hired drivers keep working, EMIs keep falling due (credit drops, seizure possible).
6. **Release:** criminal record — some jobs refuse you for a while, higher loan interest, police watch more;
   reputation rebuilt through good work.
- Record levels: clean → warning / fine → case filed → convicted.

### Level 1 build order
1. Phone job board + Coimbatore taxi and delivery missions, pay and rating (must be fun on its own).
2. Bank: loans, EMIs, credit score, buying your own vehicle.
3. Mettupalayam missions and ghat tourist runs.
4. Collisions: hit detection, fall / get-up animations, vehicle damage and repairs.
5. Law: witnesses, police AI (stops, chases), case / investigation, court, jail scene, record.
6. Businesses: buy, hire drivers, daily income.
7. Resort chapter: owning The Mist Village (end of Level 1).
Then: finish vehicles and visuals, performance, mobile build, trailer.

---

## Level 2 — "Life in the Mist"
- **Run the resort:** bring guests up the ghat, keep them happy; income from rooms, food, tours.
- **Explorer:** wildlife and nature tours (elephants, gaur, Nilgiri tahr, hornbills, waterfalls, peaks, shola forests),
  field journal, sell photos.
- **Monsoon rescue:** landslides and floods — stranded villagers and guests, supply runs, emergency drives in mist at
  night.
- **Stories of the road:** guests and locals with stories; your choices shape them.
- Ideas held for later: building the resort stage by stage with materials hauled up the ghat.

## Open decisions
1. Platform first: PC / Mac or mobile (India)?
2. Tone: realistic and serious (ETS2-like) or lighter and arcade?
3. Name: keep "The Mist Village" or e.g. "Nilgiri Roads"?
