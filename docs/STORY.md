# The Mist Village: the story as it plays (Part 1, "The Wrong Accusation")

Written out from the game's own story file (`godot/story/slice.json`) by `tools/story_md.py`: regenerate it when the story changes. The plot, the characters and the decisions behind them are in [STORY_BIBLE.md](STORY_BIBLE.md). Lines in brackets are Karthik's thoughts or what happens, not spoken. *Italics after a line* are how it's acted (its feeling, from `story/emotions.json`).

### 0. At home
- The alarm (ready: alarm)
- Go to the bathroom: brush and bathe (ready: brush, bath)
- Get dressed: your shirts are on the hooks in your room (ready: dress)

### 1. Talk (Amma, Divya)
- **Divya:** Anna, Friday. Fees. Forty-two thousand. Just reminding. *(nervous, low)*
- **Karthik:** I know, I know. I'll ask sir. *(frustrated, low)*
- **Amma:** Go, go. And come home for dinner tonight. *(relaxed, low, wobble)*

### 2. At home
- Breakfast: Amma is in the kitchen (meal)
- Your wallet, phone and keys: the shelf by the door (ready: pocket)

### 3. Drive: Raghavan sir's house, Race Course
**Goal:** Raghavan sir's house, Race Course: he leaves at 7:45

### 4. Meet Raghavan sir
**Goal:** Sir is at his gate

### 5. Talk
*(only if: late_morning)*
- **Raghavan sir:** You're late, thambi. The traffic doesn't wait for anyone, and neither do bankers. *(frustrated, low)*
- **Karthik:** Sorry, sir. It won't happen again. *(embarrassed, medium)*

### 6. Talk
- **Raghavan sir:** Good morning, thambi. Traffic? *(relaxed, low)*
- **Karthik:** Gandhipuram will be full, sir. I'll find a way.
- **Raghavan sir:** Gently, gently. My back is sixty-one years old. *(happy, low)*

### 7. Drive: Raghavan Developers, Gandhipuram
**Goal:** Drive Raghavan sir to the office in Gandhipuram, smoothly

### 8. Comfort verdict

### 9. In the room: dev office
- Sir has called you into his cabin

### 10. Talk
- **Raghavan sir:** Sit, Karthik. From today you're not only my driver. Calls, bank, documents: you'll handle them. *(confident, medium)*
- **Raghavan sir:** Same trust. Better salary. *(happy, low)*
- **Karthik:** Sir... I won't let you down. *(happy, medium)*

### 11. Talk (Suresh)
- **Suresh:** Congratulations, boss! Here. Company phone, in your name. Rules are rules. *(happy, medium, give)*
- **Suresh:** (turning his ring) So. Where are you taking sir tomorrow? *(curious, low)*

### 12. Talk
- **Raghavan sir:** Your first job as my assistant. Take this cheque to the cooperative bank. Four lakhs, in cash. *(confident, low)*
- **Raghavan sir:** It's for the Pudhur Vayal farmers. They were paid a fifth of what their land is worth. I'm putting that right on Friday. *(confident, medium)*

### 13. Handed: cheque
> Pay: SELF (cash)
> Rupees Four Lakh only.   ₹ 4,00,000/-
> A/c Raghavan Developers
> 
>                                    R. Raghavan

### 14. Talk
- **Raghavan sir:** (writing in a file) I'm noting it down. No one should be able to say this money went anywhere else. *(confident, low)*
- **Karthik:** I'll go and come straight back, sir. *(respectful, low)*

### 15. In the room: dev office
- To the bank

### 16. Drive: Kovai Nagar Cooperative Bank, 100 Feet Road
**Goal:** Take the cheque to the bank on 100 Feet Road

### 17. In the room: coopbank
- The cash counter

### 18. Take

### 19. Talk
- **Bank clerk:** Four lakhs, cash? Authorised person... Karthik. Sign the slip, please.

### 20. Task

### 21. Talk
- **Bank clerk:** Eight bundles of fifty thousand. Count it in front of me, please.

### 22. Task

### 23. Talk
*(only if: short_reported)*
- **Bank clerk:** Short? Let me see... Aiyo, yes, ninety-nine in this one. Sorry, brother. Here's the note. *(embarrassed, medium)*
- **Karthik:** Thank you. Four lakhs exactly now. *(relaxed, low)*

### 24. Talk
- **Bank clerk:** All good? Then sign the counter book... Next!

### 25. In the room: coopbank
- Back to the office with the cash

### 26. Drive: Raghavan Developers, Gandhipuram
**Goal:** Bring the cash back to the office

### 27. In the room: dev office
- Sir's cabin, with the cash

### 28. Talk
- **Suresh:** Sir, just a signature. The Green Valley buyers are waiting since March. *(frustrated, low)*
- **Raghavan sir:** Not until those farmers are paid what the land is worth. Not one signature, Suresh. *(angry, low)*
- **Suresh:** (a short laugh, turning his ring) Of course, sir. Your company. Your rules. *(confident, low)*
- **Karthik:** Sir, the cash. Four lakhs. *(nervous, low)*

### 29. Talk
*(only if: short_reported)*
- **Raghavan sir:** You caught the bank's mistake? Good. Careful hands are worth more than fast ones. Here, buy your sister something. *(happy, medium, give)*

### 30. Talk
- **Raghavan sir:** (counting) Three lakh ninety-nine thousand five hundred. Thambi... count every bundle. Always. Next time it could be your name on the shortfall. *(confident, low)*

### 31. Talk
- **Raghavan sir:** Keep it in my brown bag, thambi. It comes home with me tonight. *(relaxed, low)*

### 32. In the room: dev office
- Your desk: till sir needs you
- Lunch break

### 33. Eat out
**Goal:** Lunch break: find a place to eat nearby (get out and walk in), or treat yourself at The Siruvani Grand on Avinashi Road

### 34. Drive: Raghavan Developers, Gandhipuram
**Goal:** Back to the office

### 35. In the room: dev office
- Your desk: the afternoon

### 36. Talk
- **Suresh:** Boss! Leave the company phone here tonight. The IT boy is installing the new billing app. *(happy, low)*
- **Suresh:** Good man. Tomorrow you'll have it back, good as new. *(happy, low)*

### 37. Task

### 38. In the room: dev office
- Till sir is ready to go home

### 39. Talk
- **Raghavan sir:** Come, thambi. Home. Gently. *(relaxed, low)*

### 40. In the room: dev office
- Sir is waiting at the car

### 41. Drive: Raghavan sir's house, Race Course
**Goal:** Drive Raghavan sir home to Race Course

### 42. Comfort verdict

### 43. Task

### 44. Drive: Home, Ganapathy
**Goal:** Home, on your scooter

### 45. Task

### 46. Drive: Hotel Anna Mess, Gandhipuram
**Goal:** Pick up order #4471 at the hotel

### 47. Meet Hotel owner
**Goal:** Pick up order #4471 at the counter

### 48. Talk
- **Hotel owner:** Four-four-seven-one, Saravanampatti! Two parottas, one chicken. Hot, hot, go! *(confident, high, point)*
- **Hotel owner:** And thambi: get the OTP before you hand it over. No OTP, no parotta. *(confident, medium)*

### 49. Drive: Delivery: Saravanampatti
**Goal:** Deliver to Saravanampatti by 10:20 PM

### 50. Meet Customer
**Goal:** Hand over the order at the door

### 51. Talk
- **Customer:** Finally! The OTP? Five, five, one, two. *(frustrated, low)*

### 52. Task

### 53. Deliver verdict

### 54. Gigs

### 55. Drive: Home, Ganapathy
**Goal:** Home. Amma kept dinner

### 56. At home
- Dinner: Amma kept it warm in the kitchen (meal)

### 57. Call

### 58. Talk
- **Karthik:** Hello? ...Hello? Who is this? *(confused, medium)*
- **Karthik:** (Only breathing. Then the line goes dead.)

### 59. At home
- Go to bed

### 60. At home
- Someone is knocking at the door

### 61. Talk
- **Inspector Murugesan:** Karthik? Raghavan sir was found dead this morning, at a site off the Thondamuthur road. You're coming with us. *(confident, high)*
- **Karthik:** Sir... dead? I dropped him home last night. He was... *(surprised, high)*
- **Inspector Murugesan:** Here. The warrant. Read it, if you like. *(suspicious, medium, give)*

### 62. Handed: paper
> To: Karthik M., son of the late Muthu, Ganapathy, Coimbatore.
> 
> WHEREAS Karthik M. stands accused of an offence in Crime No. 412 of this year (the death of Shri R. Raghavan, Raghavan Developers), you are hereby directed to accompany the officers bearing this warrant to Nagar Police Station.
> 
> Given under my hand and the seal of the station.
> 
> Inspector of Police (Law & Order)
> M. Murugesan

### 63. Talk
- **Amma:** What are you saying? He was home all night! *(fear, high, argue)*
- **Karthik:** (She's wrong. I was out on a delivery till eleven. She was asleep.)
- **Divya:** Anna? Anna, what's happening? *(fear, high)*

### 64. Talk
- **Inspector Murugesan:** Everyone in the lane is watching, amma. Let him come quietly. *(confident, medium)*

### 65. At home
- Go with them

### 66. Ride

### 67. In the room: police
- Constable Selvi is waiting

### 68. Talk
- **Constable Selvi:** Your phone. Give it here. And sit there, where I can see you. *(confident, medium, point)*

### 69. In the room: police
- Hand Selvi your phone
- Sit and wait

### 70. Money

### 71. Table
- **Inspector Murugesan:** 9:52 last night. A message to Raghavan sir from your phone: 'I'll come with the car.' Read it.
- **Inspector Murugesan:** 10:12. His car on the Lawley Road camera, going west. You drive that car. Only you.
- **Inspector Murugesan:** And four lakh rupees, in your signature, from the bank that morning. Gone. Your sister's fees are due Friday, no?
- **Inspector Murugesan:** So. Explain.

### 72. Talk
*(only if: told_truth)*
- **Karthik:** My phone was at the office! Suresh sir told me to leave it there for the new app. At ten I was in Saravanampatti with a parcel. The app will show it. *(fear, high, argue)*
- **Inspector Murugesan:** Apps. Phones. Anyone can carry a phone, thambi. *(suspicious, medium, shrug)*
- **Constable Selvi:** (quietly) Sir, the app record has an OTP at 10:20. The customer typed it. *(nervous, low)*
- **Inspector Murugesan:** Write it down, Selvi. Everything gets written down. *(confident, low)*

### 73. Talk
*(only if: lied_home)*
- **Karthik:** I was at home, sir. All night. Ask my mother. *(nervous, high)*
- **Inspector Murugesan:** (He turns a page in the file.) Your own delivery app. Gandhipuram at 9:50. Saravanampatti at 10:20. *(suspicious, medium)*
- **Inspector Murugesan:** Your mother lies for you. Now you lie for yourself. Why, if you have nothing to hide? *(angry, medium)*

### 74. Talk
*(only if: kept_silent)*
- **Karthik:** Sir, I'll say nothing without a lawyer. *(nervous, medium)*
- **Inspector Murugesan:** Hm. Then you can wait. Selvi, put him on the bench. *(frustrated, low)*

### 75. Talk
- **Advocate Sundaram:** Muthu's son? Karthik. Not another word, thambi. I knew your father on the buses for twenty years. *(confident, medium)*
- **Advocate Sundaram:** Inspector. A fact needs two legs. Right now this one is standing on one. *(confident, high, point)*
- **Inspector Murugesan:** We'll see what the magistrate says, sir. *(frustrated, low)*

### 76. In the room: police
- A night at the station

### 77. Talk
- **Constable Selvi:** Tea. Drink it, it's hot. The magistrate sits tomorrow. *(respectful, low, give)*

### 78. In the room: police
- Another night

### 79. Talk (Advocate Sundaram)
- **Advocate Sundaram:** Bail. You sign here every evening, six to seven. You don't leave the district, not even to Mettupalayam. *(confident, medium)*
- **Advocate Sundaram:** Here is their case, on paper. Read it at home. Read it twice. *(confident, low, give)*

### 80. Handed: paper
> Crime No. 412.  Offence: murder.  Deceased: Shri R. Raghavan, 61, Raghavan Developers.
> Accused: Karthik M., 28, driver to the deceased.
> 
> Grounds:
> 1. A message from the accused's work phone to the deceased at 21:52: "I'll come with the car."
> 2. The deceased's car on the Lawley Road camera at 22:12, going west.
> 3. Rs 4,00,000 drawn from the firm's account that morning in the accused's signature, not recovered.
> 4. The accused's account of his movements, disputed.
> 
> Investigating Officer: Inspector M. Murugesan

### 81. Talk
*(only if: lied_home)*
- **Inspector Murugesan:** And Karthik. Your lie, and your mother's, are in the file now. I'll remember them every evening you sign. *(suspicious, high)*

### 82. In the room: police
- Get your phone back from Selvi
- Go out: Amma is waiting

### 83. Message from Suresh sir
> Karthik, don't come to the office until this is cleared. I'm sorry. Sir's family is very upset. – Suresh

### 84. Money

### 85. Message from Divya
> Anna we're outside in an auto. Amma brought curd rice. Come.

### 86. Ride

### 87. At home
- Your room. Put what you know on the wall
- Rest till evening

### 88. Bail

### 89. Talk
- **Amma:** They bring sir home from the hospital this afternoon. The funeral is at four, at the Race Course house. ...Don't go, kanna. Not today. *(sad, medium)*

### 90. Choice
**Six years you drove him.**
- Go. Stand at the gate, at least  `→ funeral_went`
- Stay home, as Amma says  `→ funeral_stayed`

### 91. At home
*(only if: funeral_went)*
- Out to your scooter

### 92. Drive: Raghavan sir's house, Race Course
*(only if: funeral_went)*
**Goal:** Race Course: sir's house. The funeral

### 93. Meet Dr. Priya
*(only if: funeral_went)*
**Goal:** The gate, full of people in white

### 94. Talk
*(only if: funeral_went)*
- **Karthik:** (White veshtis, white saris, a shamiana over the drive. Jasmine and camphor. The car I washed every morning, parked under the neem.)
- **Dr. Priya:** You. YOU. At my father's gate? Today? *(angry, high, argue)*
- **Karthik:** (She slaps me. In front of everyone. Nobody says a word.)
- **Suresh:** Priya, ma, enough, enough. ...Karthik. Go home, boss. Not today. *(sad, medium, comfort)*
- **Karthik:** (Meenakshi amma doesn't look at me. Suresh sir holds her up by the shoulders, and over her head he nods at me. Kindly.)

### 95. Talk
*(only if: funeral_stayed)*
- **Karthik:** (At four the temple bell down the road rings for a long time. I sit on the step and count it.)

### 96. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 97. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 98. Handed: note
> Ask the night watchman.

### 99. Talk
- **Constable Selvi:** (Not looking up.) Next.

### 100. In the room: police
- Out

### 101. Drive: Raghavan Developers' building, Gandhipuram, at night
**Goal:** The night watchman at Raghavan Developers' building

### 102. Wait
**Goal:** The night watchman comes on at nine

### 103. Meet Muniyandi (watchman)
**Goal:** The night watchman, at the building's gate

### 104. Talk
- **Muniyandi (watchman):** Stop there! ...Aiyo. It's you. The driver. *(surprised, medium)*
- **Karthik:** Anna, please. I only want to ask you one thing about that night. *(nervous, medium, namaste)*
- **Muniyandi (watchman):** Police said nobody goes up. And you're the accused! Go, go, before somebody sees you here. *(fear, medium, argue)*
- **Karthik:** (He drags the grill gate half shut in my face.)

### 105. Gate
**Goal:** He won't let you in. A tea stall's still open across the road

### 106. Talk
*(only if: bribed_watchman)*
- **Muniyandi (watchman):** (He looks up and down the road. The note disappears into his shirt.) Five minutes. Lobby and stair only.
- **Muniyandi (watchman):** The current has been going off all week. If it goes, stand still. I'll come with the torch. *(nervous, low)*
- **Karthik:** (Five hundred. Divya's bus pass.)

### 107. Talk
*(only if: honest_watchman)*
- **Karthik:** Tea, anna. And vadai, still hot. *(respectful, low, give)*
- **Muniyandi (watchman):** ...Sit. Sit. *(relaxed, low)*
- **Muniyandi (watchman):** My son also drives. A van, in Tiruppur. Now no work. Everybody says he's lazy. He's not lazy. *(sad, medium)*
- **Karthik:** They say I killed a man I loved like my father, anna. *(sad, high)*
- **Muniyandi (watchman):** (He drinks the tea to the last drop and hands back the glass.) Tea is tea, thambi. The stair is police business.
- **Muniyandi (watchman):** ...Less sugar, next time. My sugar is high. *(relaxed, low)*
- **Karthik:** (Next time. He said next time.)

### 108. Drive: Home, Ganapathy
*(only if: honest_watchman)*
**Goal:** Home. He'll be at the gate tomorrow night

### 109. At home
*(only if: honest_watchman)*
- Sleep

### 110. Talk (Amma, Divya)
*(only if: honest_watchman)*
- **Amma:** Eleven o'clock you came in last night. Where were you? *(suspicious, medium)*
- **Karthik:** Drinking tea with a watchman, Amma. *(embarrassed, low)*
- **Amma:** (She looks at me for a long time.) ...Then eat something before you drink more tea.
- **Divya:** Anna's making friends. Good. He needs some. *(happy, low)*

### 111. At home
*(only if: honest_watchman)*
- Out

### 112. Wait
*(only if: honest_watchman)*
**Goal:** The day is yours. Sign at the station by 7 PM; the watchman comes on at nine

### 113. Drive: Nagar Police Station, Gandhipuram
*(only if: honest_watchman)*
**Goal:** Sign at the station by 7 PM

### 114. In the room: police
*(only if: honest_watchman)*
- Sign the bail register at Selvi's desk (sign)

### 115. In the room: police
*(only if: honest_watchman)*
- Out

### 116. Drive: Raghavan Developers' building, Gandhipuram, at night
*(only if: honest_watchman)*
**Goal:** The night watchman at Raghavan Developers' building

### 117. Wait
*(only if: honest_watchman)*
**Goal:** The night watchman comes on at nine

### 118. Meet Muniyandi (watchman)
*(only if: honest_watchman)*
**Goal:** The night watchman, at the building's gate

### 119. Talk
*(only if: honest_watchman)*
- **Muniyandi (watchman):** You again. (This time he leaves the grill gate open.) *(relaxed, low)*

### 120. Gate
*(only if: honest_watchman)*
**Goal:** Tea again, less sugar. The stall across the road

### 121. Talk
*(only if: honest_watchman)*
- **Karthik:** Less sugar, anna. *(happy, low)*
- **Muniyandi (watchman):** (For the first time, he smiles.) You remembered.
- **Muniyandi (watchman):** Twenty-two years at this gate. Forty people in and out every day, and not one knows my name. Your sir knew it. *(sad, low)*
- **Karthik:** That night, anna. Did you see me? *(curious, medium)*
- **Muniyandi (watchman):** I saw a man. ...Not tonight, thambi. A jeep from the station has gone past twice already. *(nervous, medium)*
- **Karthik:** (Twice. They're watching him. Or me.)

### 122. Drive: Home, Ganapathy
*(only if: honest_watchman)*
**Goal:** Home. One more night

### 123. At home
*(only if: honest_watchman)*
- Sleep

### 124. Talk (Amma, Divya)
*(only if: honest_watchman)*
- **Divya:** Sundaram sir called at seven. He says: don't do anything clever. *(relaxed, low)*
- **Karthik:** Tell him I'm only drinking tea. *(relaxed, low)*
- **Amma:** (A steel tiffin box, wrapped in a cloth.) Two dosas, chutney. For your watchman. Nobody should eat alone at night.

### 125. Handed: note
*(only if: honest_watchman)*
> Two dosas and chutney, for the watchman.

### 126. At home
*(only if: honest_watchman)*
- Out

### 127. Wait
*(only if: honest_watchman)*
**Goal:** The day is yours. Sign at the station by 7 PM; the watchman comes on at nine

### 128. Drive: Nagar Police Station, Gandhipuram
*(only if: honest_watchman)*
**Goal:** Sign at the station by 7 PM

### 129. In the room: police
*(only if: honest_watchman)*
- Sign the bail register at Selvi's desk (sign)

### 130. In the room: police
*(only if: honest_watchman)*
- Out

### 131. Drive: Raghavan Developers' building, Gandhipuram, at night
*(only if: honest_watchman)*
**Goal:** The night watchman at Raghavan Developers' building

### 132. Wait
*(only if: honest_watchman)*
**Goal:** The night watchman comes on at nine

### 133. Meet Muniyandi (watchman)
*(only if: honest_watchman)*
**Goal:** The night watchman, at the building's gate

### 134. Talk
*(only if: honest_watchman)*
- **Muniyandi (watchman):** (Two plastic chairs are already out by the gate.) Sit.

### 135. Gate
*(only if: honest_watchman)*
**Goal:** Tea, less sugar. Amma's dosa is in your bag

### 136. Take
*(only if: honest_watchman)*

### 137. Talk
*(only if: honest_watchman)*
- **Karthik:** Tea, less sugar. And Amma sent dosa. *(respectful, low, give)*
- **Muniyandi (watchman):** (He eats slowly, the box on his knees.) Three nights. A man who killed somebody doesn't come back three nights with tea. He runs to Kerala.
- **Muniyandi (watchman):** (A long breath.) ...Your sir gave me his newspaper every evening, after he read it. Go up. I'll look at the fuse box, the current keeps going.

### 138. Climb
**Goal:** Go up the stair to the office

### 139. Talk
- **Karthik:** (My phone. If he says it, I want it said twice.)

### 140. Record

### 141. Talk
- **Muniyandi (watchman):** Careful. The third step from the top is broken. The current has gone again, see. *(nervous, low)*
- **Muniyandi (watchman):** This is where I was standing that night. Twenty to ten. *(confident, low, point)*
- **Muniyandi (watchman):** A man in a cap and a dark jacket, about your size. He had a card for the door. He went straight up. *(nervous, medium)*
- **Muniyandi (watchman):** Eighteen minutes later he came down, face to the wall all the way. I told the police. They wrote nothing. *(frustrated, low)*
- **Karthik:** I never wear a cap, anna. Never. *(frustrated, medium)*

### 142. Talk
*(only if: honest_watchman)*
- **Muniyandi (watchman):** Listen. The building's camera box... my nephew Kathir fixed it last month. He copies everything onto a drive, he's afraid of losing the job. Ask him. Saibaba Colony, behind the bakery. *(curious, low)*

### 143. Talk
*(only if: bribed_watchman)*
- **Muniyandi (watchman):** Now go. And you never came here, understand? Five hundred rupees doesn't buy you a witness. *(nervous, medium)*

### 144. Record

### 145. Evidence E06
- Watchman: man in a cap, 9:40–9:58
  - The watchman: Cap, dark jacket, key card. Up 9:40, down 9:58.

### 146. Talk
*(only if: bribed_watchman)*
- **Karthik:** (On the camera box by the lift, a sticker: KATHIR CCTV SERVICE, Saibaba Colony, behind the bakery. And a number.)

### 147. Contact

### 148. Pin

### 149. Drive: Home, Ganapathy
**Goal:** Home

### 150. Call

### 151. Talk
- **Karthik:** Hello? ...Who is this? *(fear, medium)*
- **Karthik:** (The same breathing. Then, very quietly, a car's indicator ticking. Then nothing.)

### 152. At home
- Your wall: what the watchman said
- Sleep

### 153. Talk (Amma, Divya)
- **Divya:** Anna. Who calls you at midnight and says nothing? *(suspicious, low)*
- **Karthik:** Wrong number. Eat your breakfast. *(embarrassed, low)*
- **Amma:** Sundaram sir called. He'll come in the evening, before you go to sign.
- **Divya:** If you find anything on a computer, show me. I'm not useless, you know. *(confident, medium)*

### 154. At home
- Out to your scooter

### 155. Drive: Saibaba Colony, Coimbatore
**Goal:** Kathir's CCTV shop, behind the bakery, Saibaba Colony

### 156. In the room: cctv shop
- Kathir, behind his counter

### 157. Talk
*(only if: honest_watchman)*
- **Kathir:** Muniyandi mama sent you? He said you'd come. He also said you're a fool. *(confident, low)*
- **Karthik:** Maybe. The building's camera, that night. You have it? *(curious, low)*
- **Kathir:** I have everything. I'm careful. Come, see. Don't touch my mouse. *(confident, medium)*

### 158. Talk
*(only if: bribed_watchman)*
- **Kathir:** Who gave you this address? *(suspicious, medium)*
- **Karthik:** Your sticker. On the camera box in Raghavan Developers' lobby. *(respectful, low)*
- **Kathir:** Hm. A sticker is an advertisement, not an invitation. Fine. Come, see. *(relaxed, low)*

### 159. Dvr
**Goal:** His monitor: the building's lobby camera, that night

### 160. Talk
- **Kathir:** Seen? Good. The copy is mine. I made it, on my drive. Five thousand. *(confident, medium)*
- **Karthik:** Five thousand? It isn't yours to sell, Kathir. It's the building's. *(frustrated, medium, argue)*
- **Kathir:** Then let the building come and ask me. The QR's on the stool. *(confident, medium, shrug)*

### 161. Deal
**Goal:** He wants ₹5,000 for the copy. Or walk away.

### 162. Handed: note
*(only if: kathir_paid)*
> Kathir's copy of the lobby camera, 9:30 to 10:10 PM. ₹5,000 to him. No receipt.

### 163. Talk
*(only if: kathir_paid)*
- **Kathir:** Pleasure doing business. And I never gave you anything, okay? *(happy, low)*
- **Karthik:** (Bought. Sundaram sir won't like that.)

### 164. Talk
*(only if: kathir_walked)*
- **Karthik:** (Five thousand. That's Divya's books for a term. And a court would ask where I got it.)

### 165. In the room: cctv shop
- Out to your scooter

### 166. Drive: Home, Ganapathy
**Goal:** Home: Divya's back from college at half past four

### 167. At home
- Rest till Divya's back

### 168. At home
- Show Divya the pictures on your phone

### 169. Talk
- **Divya:** This isn't his picture, anna. See the corner: RAGHAVAN DEV, GPM, NVR-1. The recorder stamps its own name on every frame. *(confident, medium, point)*
- **Divya:** Nithya's father installs these. She says the recorder writes its ID inside the file too. Copy it a hundred times, it's still the building's footage. *(curious, medium)*
- **Divya:** So it isn't his to sell. It's evidence. *(confident, medium)*

### 170. Talk
*(only if: dvr_card)*
- **Divya:** And look here. 9:40, card number seven opens your office door upstairs. Whose card is seven? *(curious, medium)*
- **Karthik:** I don't know. Yet. *(confident, low)*

### 171. At home
- Your phone back

### 172. Talk (Advocate Sundaram)
- **Advocate Sundaram:** Thambi. Your mother says you've been to a CCTV shop. *(disappointed, low)*

### 173. Talk
*(only if: kathir_paid)*
- **Advocate Sundaram:** Five thousand? For a copy with no receipt? A fact you paid for walks on one leg, thambi. Their lawyer will say you made it. *(disappointed, medium)*
- **Advocate Sundaram:** Still. Keep the drive safe and don't open it again. I'll ask the court for the building's own recorder. *(confident, low)*

### 174. Talk
*(only if: kathir_walked)*
- **Advocate Sundaram:** And you didn't pay him. Good. Now we ask properly. *(happy, low)*
- **Advocate Sundaram:** A letter, from me. The footage is evidence in Crime No. 412; he keeps it safe and hands it to the defence. Destroying it is an offence, Section 238. *(confident, low, give)*
- **Advocate Sundaram:** Take it to him after you sign tonight. Shops in Saibaba Colony stay open till nine. *(confident, low)*

### 175. Handed: paper
*(only if: kathir_walked)*
> To Mr. Kathir, Kathir CCTV Service, Saibaba Colony. The recording of the lobby camera of the Raghavan Developers building for the night in question is evidence in Crime No. 412 of Nagar Police Station. You are requested to preserve it and hand a copy to the defence. Its destruction is an offence under Section 238 of the Bharatiya Nyaya Sanhita. – S. Sundaram, Advocate

### 176. At home
- Out: the station by seven

### 177. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 178. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 179. In the room: police
- Out

### 180. Drive: Saibaba Colony, Coimbatore
*(only if: kathir_walked)*
**Goal:** Kathir's shop, with the letter

### 181. In the room: cctv shop
*(only if: kathir_walked)*
- Kathir, closing up

### 182. Talk
*(only if: kathir_walked)*
- **Karthik:** From my advocate. *(respectful, low, give)*
- **Kathir:** (He reads it twice.) Section two-three-eight... Mama said you were a fool. He didn't say you had a lawyer.
- **Kathir:** Take it. And tell your lawyer I gave it the first time I was asked properly. *(respectful, low, give)*

### 183. Take
*(only if: kathir_walked)*

### 184. Handed: note
*(only if: kathir_walked)*
> The lobby camera, 9:30 to 10:10 PM, the recorder's ID in every frame. Handed over on Advocate Sundaram's letter.

### 185. In the room: cctv shop
*(only if: kathir_walked)*
- Out to your scooter

### 186. Drive: Home, Ganapathy
**Goal:** Home

### 187. At home
- Your wall: the lobby camera
- Sleep

### 188. At home
- Divya, before she leaves for college

### 189. Talk
- **Karthik:** (Ashwin, that night. 'Smile, you're on my doorbell camera. Landlord's rule.')
- **Karthik:** Divya. Those doorbell cameras. Do they keep what they see? *(curious, medium)*
- **Divya:** The cheap plans keep clips seven days, anna. Then they delete themselves. Why? *(confused, low)*
- **Karthik:** The delivery. Saravanampatti, ten twenty that night. His door had a camera. *(curious, medium)*
- **Divya:** That was six days ago. Anna... tomorrow it's gone. Go today. Now. *(fear, medium)*
- **Amma:** Eat something first. Then go. *(relaxed, low)*

### 190. Contact

### 191. Pin

### 192. At home
- Out to your scooter

### 193. Drive: Delivery: Saravanampatti
**Goal:** Ashwin's building in Saravanampatti, before the clip is deleted

### 194. Meet Customer
**Goal:** Ashwin, at his door

### 195. Talk
- **Customer:** Bro? ...Wait. You're the delivery guy. You're the one on the news! *(surprised, high)*
- **Karthik:** That night I was here, at your door. Ten twenty. Your camera saw me. *(nervous, medium)*
- **Customer:** Bro, my company does background checks. I can't be in a police case. *(nervous, high, shake)*
- **Customer:** And it's not my camera. It's the owner's. Lakshmi aunty, downstairs. The app is on her tablet. Ask her. And... sorry, bro. *(nervous, medium, point)*

### 196. Meet Lakshmi aunty
**Goal:** Lakshmi aunty, the owner, at her door downstairs

### 197. Talk
- **Lakshmi aunty:** Ashwin rang me. You're the boy from the news. Raghavan's driver. *(suspicious, medium)*
- **Karthik:** Aunty, the clip from that night. It shows me at his door at ten twenty. He died across the city. *(nervous, medium, namaste)*
- **Lakshmi aunty:** Sixteen years in a bank, thambi. I don't hand things over because someone asks nicely. Who is your advocate? *(confident, medium)*

### 198. Choice
**She waits, the grill gate between you.**
- Call Sundaram sir and let her talk to him  `→ lakshmi_lawyer`
- "Aunty, for your trouble..." (hold out ₹1,000)  `→ lakshmi_offered`

### 199. Talk
*(only if: lakshmi_offered)*
- **Lakshmi aunty:** Put that away! At my own gate! ...If you had paid, would I believe your clip? Would a judge? Call your advocate. *(angry, high, argue)*
- **Karthik:** (The note goes back in my pocket. My face is hot.)

### 200. Dial
**Goal:** Call Sundaram sir: your phone, Contacts

### 201. Talk
- **Advocate Sundaram:** (on the phone) Thambi? ...A doorbell. Good. Give her the phone. *(curious, low)*
- **Karthik:** (I hold it through the grill. She listens a long time.)
- **Lakshmi aunty:** Yes, sir. Lakshmi Narayanan, branch manager, State Bank. ...From my own account, yes. With the date. To your number. ...I understand. *(respectful, low)*
- **Lakshmi aunty:** Your advocate gets it, not you. But you can look. *(confident, low)*

### 202. Doorbell
**Goal:** Her tablet: the doorbell's clips

### 203. Talk
- **Lakshmi aunty:** There. Sent to your Sundaram, from my account. One more day and it would have deleted itself. *(confident, low)*
- **Lakshmi aunty:** And thambi. The police never came to ask me. Not once. *(frustrated, medium)*

### 204. Evidence E05
- Doorbell clip, Saravanampatti
  - Ashwin's doorbell: Me at his door, Saravanampatti, that night. Sent to Sundaram sir from the owner's own account.

### 205. Message from Sundaram sir
> Got Mrs. Lakshmi's clip. Her account, her date, her phone. This one walks on two legs, thambi. – Sundaram

### 206. Drive: Home, Ganapathy
**Goal:** Home

### 207. At home
- Rest till it's time to sign

### 208. At home
- Out: the station by seven

### 209. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 210. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 211. In the room: police
- Out

### 212. Drive: Home, Ganapathy
**Goal:** Home

### 213. At home
- Your wall: the doorbell
- Sleep

### 214. At home
- Amma, in the kitchen

### 215. Talk
- **Karthik:** (The Lawley Road camera: the SUV at 10:12, going west. The Thondamuthur road.)
- **Karthik:** (Past Vadavalli it's fields and a few shops. Somebody on that road was awake at half past ten.)
- **Amma:** Your appa took me that way once, to the temple festival at Pudhur. There was one tea shop at the turn, Murugan Tea Stall, open late for the lorry drivers. Sekar runs it. *(sad, low)*
- **Amma:** Go in the daylight, kanna. And be back to sign. *(relaxed, low)*

### 216. Pin

### 217. At home
- Out to your scooter

### 218. Drive: Sekar's tea shop, Thondamuthur road
**Goal:** West on the Thondamuthur road: the tea shop at the Pudhur Vayal turn

### 219. Meet Sekar
**Goal:** Sekar, at his tea stall

### 220. Talk
- **Sekar:** Tea? ...Wait. You're the driver. The paper had your face. The Raghavan case. *(suspicious, medium)*
- **Karthik:** Anna, that night. You close late, they say. Half past ten? *(respectful, low)*
- **Sekar:** A man who drinks tea at my shop is a customer. A man who asks questions is trouble. *(suspicious, high)*

### 221. Choice
**He wipes the glasses and doesn't look at you.**
- Buy a tea and sit on his bench (₹15)  `→ sekar_tea`
- "Just tell me what you saw, anna."  `→ sekar_pushed`

### 222. Talk
*(only if: sekar_pushed)*
- **Sekar:** I saw nothing. I sell tea. Drink or go. *(frustrated, medium, shake)*
- **Karthik:** (I buy a tea anyway and sit on his bench. Two lorries. A boy with milk cans. Most of an hour. Then he sits down beside me.)

### 223. Talk
*(only if: sekar_tea)*
- **Karthik:** (I sit with the tea. The lorries go by. When the rush is over, he sits down beside me.)

### 224. Talk
- **Karthik:** (My phone. If he says it, I want it said twice.)

### 225. Record

### 226. Talk
- **Sekar:** You're Muthu's son. He drank tea here when you were this high. ...All right. *(sad, low)*
- **Sekar:** That night I was pulling the shutter. Twenty-five to eleven. A white SUV, a big one, came from the city side and turned in to Pudhur. Slow, like the driver didn't know the road. *(confident, low)*
- **Sekar:** And a black car was already there, by the site gate. Parked nose-out. The way a man parks when he wants to leave fast. *(suspicious, low)*
- **Karthik:** The SUV's driver. Did you see him? *(curious, high)*
- **Sekar:** A cap. That's all. ...If a court asks me, I'll say it. Only what I saw. Not one word more. *(confident, medium)*

### 227. Record

### 228. Evidence E08
- Sekar: white SUV 10:35, a black car nose-out
  - Sekar's tea shop: 10:35 PM the white SUV turns in to Pudhur, slowly. A black car already at the site gate, parked nose-out.

### 229. Talk
- **Karthik:** (A cap. I have never worn a cap in my life. Amma would say so. Amma's albums would.)

### 230. Drive: Home, Ganapathy
**Goal:** Home: Amma's albums

### 231. At home
- Ask Amma for the albums

### 232. Talk
- **Amma:** The albums? Top of the steel cupboard, under the Pongal saree. ...Why now? *(confused, low)*
- **Karthik:** The man on the camera wore a cap, Amma. *(confident, low)*
- **Amma:** A cap? You? You cried when your appa put one on you at the Ooty trip. Look. Every photo. *(happy, medium, laugh)*

### 233. Snapshot

### 234. Evidence E14
- Family albums: never a cap
  - Amma's albums: Fifteen years of photos. Pongal, weddings, Divya's school day. Not one cap.

### 235. At home
- Rest till it's time to sign

### 236. At home
- Out: the station by seven

### 237. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 238. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 239. In the room: police
- Out

### 240. Drive: Home, Ganapathy
**Goal:** Home

### 241. At home
- Your wall: the road west, and the cap
- Sleep

### 242. At home
- Someone is knocking at the door

### 243. Talk
- **Bala:** Da. A week. You think I'd believe the TV over you? *(angry, low)*
- **Karthik:** Bala... the whole lane looks away when I come out now. *(sad, medium)*
- **Bala:** Let them. I know you, da. Since sixth standard. You can't lie to your mother about a film. *(confident, medium, comfort)*
- **Bala:** The workshop's open till nine. A bike, a ride, a meal, anything. And where are you running around these days? Tell me, so I know you're safe. *(happy, low)*

### 244. Choice
**Bala waits, leaning on the door frame.**
- Tell him: the doorbell, Sekar's tea shop, Pudhur Vayal today  `→ told_bala`
- "Better you don't know, da. Safer for you."  `→ kept_from_bala`

### 245. Talk
*(only if: told_bala)*
- **Bala:** Pudhur Vayal? Those farmers are angry, da. Go in daylight. ...And call me after. Promise. *(nervous, low)*

### 246. Talk
*(only if: kept_from_bala)*
- **Bala:** Okay, okay, secret agent. Just come back in one piece. *(happy, medium, laugh)*

### 247. Pin

### 248. At home
- Out to your scooter

### 249. Drive: Pudhur Vayal, off the Thondamuthur road
**Goal:** Pudhur Vayal, past Sekar's tea stall: the farmers Raghavan sir owed

### 250. Meet Ponnusamy
**Goal:** Three men walk out of the field towards your scooter

### 251. Talk
- **Ponnusamy:** Stop. That's Raghavan's driver. The one who carried the money. *(angry, medium, point)*
- **A farmer:** Four lakhs! Ours! For the land your people took at a fifth of the price! *(angry, high, argue)*
- **Karthik:** Ayya, I didn't take it. Sir was bringing it to you. He told me himself. *(fear, medium, namaste)*
- **Ponnusamy:** Bringing it? Then where is it? Forty families sold on his word. Forty. *(angry, high)*
- **Another farmer:** Get off the scooter. Get off it. *(angry, high, point)*

### 252. Provoke
**Goal:** Let them say it. Don't answer anger with anger
- **A farmer:** Forty families! My father's land, for a fifth of its price, and not even that paid!
- **Another farmer:** Look at him. A helmet, a scooter. Like a gentleman. On our money.
- **Ponnusamy:** My daughter's wedding was to come out of that money. The hall is booked. Tell me where it is, driver.
- **A farmer:** His dog. That's all you were. Raghavan's dog, carrying his bags.

### 253. Choice
*(only if: farmers_calm)*
**They're all around the scooter.**
- Tell them again, slowly, what sir said  `→ farmers_heard`
- Hold out what's in your wallet  `→ farmers_offered`
- Start the scooter and go  `→ farmers_left`

### 254. Talk
*(only if: farmers_offered)*
- **Ponnusamy:** Money? From you? You think we're beggars at your gate? Put it away before I lose my temper. *(angry, high, argue)*
- **A farmer:** (He knocks the scooter's mirror crooked with the back of his hand.)

### 255. Talk
*(only if: farmers_left)*
- **Ponnusamy:** Run, then. Run. That's what thieves do. *(disappointed, high)*
- **Karthik:** (I stop at the end of the field. He's still standing in the road. I walk back.)

### 256. Talk
*(only if: farmers_shoved)*
- **Karthik:** (My hands are on his chest before I know it. He staggers. The other two grab my arms.)
- **Ponnusamy:** There. Now we know what you are. Hit an old man in his own field. ...The police will hear of this, bail-man. *(angry, high)*

### 257. Talk
*(only if: farmers_heard)*
- **Ponnusamy:** (He listens to the end. His jaw doesn't move.)

### 258. Talk
- **Ponnusamy:** Words. Everyone brings us words. The broker, the officer, now the driver. *(frustrated, medium)*
- **Ponnusamy:** Raghavan wrote everything down, that man. If he meant to pay us, he wrote it. Bring us paper, thambi. Until then, don't show your face in Pudhur. *(confident, low)*
- **Karthik:** (He wrote everything. The Green Valley file. It's in his house now, with his daughter. Priya, who won't look at me.)

### 259. Evidence lead_farmers
- Pudhur Vayal: the farmers
  - The Pudhur Vayal farmers: Forty families sold on sir's word. They think I stole their money. 'Bring us paper.' The Green Valley file: Priya.

### 260. Drive: Home, Ganapathy
**Goal:** Home: Divya's back from college at half past four

### 261. At home
- Rest till Divya's back

### 262. At home
- Divya's home. She hasn't said a word

### 263. Talk
- **Divya:** (She turns her phone face down.) It's nothing. *(embarrassed, medium)*
- **Divya:** ...They made a WhatsApp group. 'Murderer's sister.' Thirty-two people. My bench partner is in it. She added the photo from the paper. *(sad, high)*

### 264. Choice
**Divya stares at the floor.**
- Just sit with her and let her talk  `→ divya_heard`
- "I'll go to that college tomorrow and—"  `→ divya_angry`
- "Divya. I need someone who knows phones and cameras. Help me prove it."  `→ divya_partner`

### 265. Talk
*(only if: divya_heard)*
- **Divya:** (For a long time she says nothing. Then all of it: the canteen, the teacher who moved her seat, the boy who laughed.)
- **Divya:** ...Thanks for not shouting, anna. *(sad, low)*

### 266. Talk
*(only if: divya_angry)*
- **Divya:** No! You'll make it worse! You're on bail, anna! One fight and they'll put you back inside, and then what do I tell them? *(fear, high, argue)*

### 267. Talk
*(only if: divya_partner)*
- **Divya:** (She looks up.) ...The doorbell clip. The lobby camera. You need someone to read them properly.
- **Divya:** Okay. But I'm not doing it for you. I'm doing it so I can show that group the truth. *(confident, medium)*

### 268. At home
- Out: the station by seven

### 269. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 270. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 271. In the room: police
- Out

### 272. Drive: Home, Ganapathy
**Goal:** Home

### 273. At home
- Your wall: the farmers, and the file
- Sleep

### 274. At home
- Amma, in the kitchen

### 275. Talk
- **Karthik:** Amma. The file is with sir's family. Priya won't take my calls. *(sad, medium)*
- **Amma:** Meenakshi amma goes to Perur every morning now. To the Pateeswarar temple, for him. The flower-seller told me.
- **Amma:** Go gently, kanna. She's lost her husband. Don't make her lose her peace there too. *(sad, low)*

### 276. Pin

### 277. At home
- Out to your scooter

### 278. Talk
- **Divya:** (At the gate, her bag on her shoulder.) Anna. You're going out? ...Drop me at college?
- **Divya:** Not at the gate. A little before it. ...No, at the gate. Let them see. *(nervous, medium)*
- **Karthik:** (Her chemistry practical starts at twenty past seven. In two years she has never once been late.)

### 279. Drive: Hope College, Coimbatore
**Goal:** Divya to Hope College by 7:20, her practical. Ride gently: she's on the back

### 280. Talk
*(only if: divya_dropped)*
- **Karthik:** (Three of them by the gate. The red shirt sees who's on the scooter. He finds something to look at on his phone.)
- **Divya:** (She gets off, straightens her dupatta, and walks in past them, not fast.) Bye, anna.

### 281. Talk
*(only if: divya_dropped_late)*
- **Karthik:** (The bell has gone. She jumps off before I've stopped and runs in past the three at the gate, head down.)
- **Karthik:** (A late mark, on top of everything. Because of me.)

### 282. Drive: Perur Pateeswarar temple
**Goal:** Perur Pateeswarar temple, before the morning puja ends

### 283. Shop

### 284. Meet Meenakshi amma
**Goal:** Meenakshi amma, coming out of the temple, and Priya

### 285. Talk
*(only if: temple_archanai)*
- **Karthik:** (Inside, the priest reads the name off my ticket for the archanai. R. Raghavan. Three women at the next shrine turn to look.)
- **Meenakshi amma:** (She has seen it. The plate with the camphor, in my hands, with his name.) ...Who told you to do that?
- **Karthik:** Nobody, amma. Six years I drove him here every Pradosham. *(respectful, low)*

### 286. Talk
*(only if: temple_offering)*
- **Karthik:** (I leave the jasmine at the shrine, by the pillar where sir always stood. Meenakshi amma sees where I put it.)

### 287. Talk
- **Dr. Priya:** You. Here? At my father's prayers? *(angry, high)*
- **Dr. Priya:** Get away from my mother, or I call the police right now. You're on bail, aren't you? *(angry, high, point)*
- **Karthik:** Madam. Two minutes. Only two. *(respectful, medium, namaste)*
- **Meenakshi amma:** Priya. Let him speak. Nine days I've listened to everyone. The police, the papers, Suresh. Never to him. *(grieving, medium)*

### 288. Choice
**Meenakshi amma waits. Priya's hand is on her phone.**
- Tell her about the four lakhs, and the farmers sir meant it for  `→ meenakshi_money`
- Tell her about the man in the cap, and the card that opened the office  `→ meenakshi_cap`
- Say only: "Amma, I didn't do it."  `→ meenakshi_plain`

### 289. Talk
*(only if: meenakshi_money)*
- **Meenakshi amma:** He talked about those families at dinner. Every week. He said, 'I won't sleep till they're paid.' *(grieving, low)*

### 290. Talk
*(only if: meenakshi_cap)*
- **Dr. Priya:** A cap. A card. Anybody can say a man in a cap. *(suspicious, high)*
- **Meenakshi amma:** Card seven... Priya, who has the small numbers? The ones from the start of the company? *(curious, medium)*

### 291. Talk
*(only if: meenakshi_plain)*
- **Meenakshi amma:** (She looks at me for a long time. The way sir looked at a man before he signed anything.)

### 292. Talk
- **Karthik:** Sir wrote everything down. If the money was for the farmers, he wrote it. In the Green Valley file. *(confident, medium)*
- **Meenakshi amma:** Every night. In green ink. He used to laugh that it was the right ink for a green valley. *(grieving, low)*
- **Dr. Priya:** Amma, he's playing you. This is what they do. *(angry, medium)*
- **Meenakshi amma:** Then look in the file, Priya. And show me he's lying. *(confident, medium)*
- **Dr. Priya:** ...Fine. I'll look. So that you stop coming near us. Both of you. *(frustrated, medium)*

### 293. Evidence lead_file
- Perur: Meenakshi amma listened
  - Meenakshi amma: She let me speak. Sir wrote every night, in green ink. Priya will look in the Green Valley file.

### 294. Drive: Home, Ganapathy
**Goal:** Home

### 295. At home
- Amma's waiting for you

### 296. Talk
*(only if: told_bala)*
- **Amma:** Suresh sir came this afternoon. With a box of Mysore pak, for Divya. So kind. *(happy, low)*
- **Amma:** He asked where you've been going. The doorbell, the tea shop... I said, he's only trying, sir. *(confused, low)*
- **Karthik:** (The doorbell. The tea shop. I told only one person that.)

### 297. Talk
- **Amma:** Suresh sir came this afternoon. With a box of Mysore pak, for Divya. He asked where you've been going. *(happy, low)*
- **Amma:** I said I don't know. And I don't, do I? *(confused, low)*
- **Karthik:** (Why would Suresh sir want to know?)

### 298. Talk
- **Amma:** And kanna... I didn't go to the market today. Kamala akka turned her back on me at the vegetable cart. In front of everyone. *(sad, medium)*
- **Amma:** There's nothing for tonight but rice and rasam. *(sad, low)*

### 299. Choice
**Amma is looking at her hands.**
- "I'll go to the market myself."  `→ market_went`
- Ask Divya to order vegetables on the app (₹180)  `→ market_app`
- "Rice and rasam is enough, Amma."  `→ market_none`

### 300. Talk
*(only if: market_app)*
- **Divya:** Done. Forty minutes. The delivery boy won't know who we are. *(confident, low)*

### 301. At home
*(only if: market_went)*
- Out to the market

### 302. Drive: Ganapathy, Coimbatore
*(only if: market_went)*
**Goal:** Ganapathy market, the vegetable carts

### 303. Ask
*(only if: market_went)*
**Goal:** Amma's list: beans, onions, coriander. Find someone who will still sell to you

### 304. Talk
*(only if: market_went)*
- **An old vendor:** My son was inside two years for a theft he didn't do. The whole street turned its back. I know that walk you're walking. *(sad, low)*
- **An old vendor:** Beans, onions, coriander, and a few green chillies for your Amma. Sixty rupees. Tell her Valliammai sent them. *(relaxed, low, give)*

### 305. Act
*(only if: market_went)*
**Goal:** Pay Valliammai: sixty rupees

### 306. Drive: Home, Ganapathy
*(only if: market_went)*
**Goal:** Home, with the vegetables

### 307. Talk
*(only if: market_went)*
- **Amma:** Valliammai? ...She came to your appa's funeral. Nobody else from that market did. (She takes the bag in both hands.) *(sad, low)*

### 308. At home
- Rest till it's time to sign

### 309. At home
- Out: the station by seven

### 310. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 311. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 312. In the room: police
- Out

### 313. Drive: Home, Ganapathy
**Goal:** Home

### 314. Message from Dr. Priya
> The Green Valley file isn't at home. It's in his cabinet at the office. Revathi says Suresh uncle has the keys now. – Priya

### 315. At home
- Your wall: the file, and the keys
- Sleep

### 316. Message from Dr. Priya
> Revathi let me into the office at seven this morning, before Suresh uncle comes in. I have it. Kongu Multispeciality Hospital, Avinashi Road, the side gate, 1 PM. I have a surgery at 2. Don't be late. – Priya

### 317. Pin

### 318. At home
- Wait till it's time to go to the hospital
- Out to your scooter

### 319. Drive: Kongu Multispeciality Hospital
**Goal:** Kongu Multispeciality Hospital, Avinashi Road, by 1 PM

### 320. Meet Dr. Priya
**Goal:** Priya, at the side gate

### 321. Talk
- **Dr. Priya:** Revathi was shaking the whole time. It was in Suresh uncle's cabinet, at the back, behind the company's tax files. *(nervous, medium)*
- **Dr. Priya:** His hand. Green ink. I'd know it anywhere. ...Read it. *(sad, high)*

### 322. Meet Hotel security
*(only if: priya_missed)*
**Goal:** The side gate. Priya isn't there. The guard is

### 323. Talk
*(only if: priya_missed)*
- **Hotel security:** You're the driver? Doctor waited twenty minutes. Then she went up to scrub in. *(frustrated, low)*
- **Hotel security:** (An envelope, sealed with tape.) She said: 'Tell him I don't wait for anyone. Not even for this.'
- **Karthik:** (Her copy of sir's note. In green ink, his hand. I read it standing at the gate.)

### 324. Handed: paper
> Pudhur Vayal. Rs. 4,00,000 cash drawn on Day 3, for Ponnusamy and the forty families: the balance of a fair price, as I promised them.
> 
> S. wants the Green Valley transfer signed first. I will not sign until they are paid.
> 
> – R. R.

### 325. Talk
- **Karthik:** 'S.' ...Suresh sir. *(surprised, medium)*
- **Dr. Priya:** Don't. This doesn't mean I believe you. It means I don't know any more. And I hate not knowing. *(frustrated, high)*
- **Dr. Priya:** Your Sundaram has a copy. Take this one to those farmers. They should know he meant it. *(confident, low, give)*

### 326. Choice
**She looks at her watch. Ten minutes to her surgery.**
- "Thank you, doctor. For looking."  `→ priya_thanked`
- "Did Suresh sir see you take it?"  `→ priya_warned`

### 327. Talk
*(only if: priya_thanked)*
- **Dr. Priya:** (She almost says something. Then she turns and goes in.)

### 328. Talk
*(only if: priya_warned)*
- **Dr. Priya:** No. Revathi put everything back the way it was. ...Why does that matter? *(confused, low)*
- **Karthik:** Be careful around him. Please. And tell Revathi. *(fear, medium)*
- **Dr. Priya:** He's my father's partner. He held my mother up at the funeral. ...I'll tell her. *(confused, medium)*

### 329. Evidence E09
- Raghavan's note: the cash was for the farmers
  - Sir's note (E09): Green ink: the 4 lakhs were the farmers' fair price. 'S.' wanted the transfer signed first. He refused. Found in Suresh's cabinet.

### 330. Drive: Pudhur Vayal, off the Thondamuthur road
**Goal:** Pudhur Vayal, with sir's note

### 331. Meet Ponnusamy
**Goal:** Ponnusamy and the farmers, at the field's edge

### 332. Talk
- **Another farmer:** You again? Didn't he tell you— *(suspicious, medium)*
- **Karthik:** Ayya. You said, bring paper. (I hold out the note.) *(respectful, medium, give)*
- **Ponnusamy:** (He reads it twice. His lips move with the words. Nobody speaks.)
- **Ponnusamy:** His hand. He wrote to us once, at Deepavali, with sweets for the children. Green ink, like this. *(sad, low)*
- **Ponnusamy:** So he meant to pay. And somebody stopped him. *(angry, low)*

### 333. Talk
*(only if: farmers_offered)*
- **Ponnusamy:** And the money you held out that day. I'll forget it. You were frightened. *(relaxed, low)*

### 334. Talk
*(only if: farmers_shoved)*
- **Ponnusamy:** And that day in the field, your hands on me. ...I've had worse from men with more reason. Forget it. *(relaxed, low)*

### 335. Talk
- **Ponnusamy:** Thambi. I said things to you. ...Tell your advocate: forty families will come to his court. And ask him who 'S.' is. *(respectful, medium)*
- **A farmer:** (He straightens the scooter's mirror without a word.)

### 336. Evidence witness_farmers
- Pudhur Vayal: forty families, witnesses
  - The farmers will testify: Ponnusamy knew the green ink. Forty families will come to court: sir meant to pay them.

### 337. Message from Sundaram sir
> Priya sent me the note. With the farmers, it's motive, thambi, and not yours. Sign on time tonight. Don't give them anything else. – Sundaram

### 338. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 339. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 340. In the room: police
- Out

### 341. Drive: Home, Ganapathy
**Goal:** Home

### 342. At home
- Your wall: sir's note, and 'S.'
- Sleep

### 343. At home
- Your wall: who gains from Green Valley?

### 344. Talk
- **Karthik:** (Suresh sir wanted the Green Valley transfer signed before the farmers were paid. Why the hurry? Whose land is it now?)
- **Karthik:** (The patta records. The Collectorate.)

### 345. Message from Sundaram sir
> Land records: the Collectorate, the patta counter. Pudhur Vayal survey numbers 214 to 226. Don't pay anybody, thambi. Anybody. – Sundaram

### 346. Pin

### 347. At home
- Out to your scooter

### 348. Drive: District Collectorate, Coimbatore
**Goal:** The District Collectorate: land records for Pudhur Vayal

### 349. Meet The patta clerk
**Goal:** The patta counter, by the Collectorate's side door

### 350. Talk
- **Karthik:** Sir. Pudhur Vayal, survey numbers two-fourteen to two-twenty-six. Only to see whose name— *(respectful, low)*
- **The patta clerk:** Apply online. Tamil Nilam. Pudhur Vayal is Perur taluk. Fifteen working days. Next!
- **Karthik:** Sir, fifteen days, I'm on bail, I— *(frustrated, medium)*
- **The patta clerk:** Everybody has a reason. Online. Next! *(frustrated, medium)*

### 351. Talk
- **A man by the gate:** (A man by the gate falls into step beside me.) Anna. Patta? Two thousand, today itself. Printout with seal. I know the people inside.

### 352. Act
**Goal:** The land record: apply on your phone (Tamil Nilam, P), call Priya about Revathi, or pay the man by the gate

### 353. Note
*(only if: patta_online)*

### 354. Talk
*(only if: patta_online)*
- **Karthik:** (Application TN-NLM-2026-0884213. Fifteen working days. On bail, fifteen days is a long time.)
- **A man by the gate:** (The man by the gate shrugs and goes back to his shade.) Your wish, anna.

### 355. Talk
*(only if: patta_revathi)*
- **Karthik:** (I call Priya. 'The patta for Pudhur Vayal. Would the office have a copy? Only if it's safe for Revathi.' She says she'll ask.)
- **A man by the gate:** Revathi? Office? (He laughs.) Your wish, anna. *(happy, low, laugh)*

### 356. Talk
*(only if: patta_tout)*
- **A man by the gate:** Sit at the tea shop. One hour. *(confident, low, point)*
- **Karthik:** (Fifty minutes later he's back with a printout, warm, a blue seal on the corner.)

### 357. Handed: paper
*(only if: patta_tout)*
> Survey nos. 214 to 226, Pudhur Vayal village, 18.4 acres.
> 
> Registered owner: KONGU GREEN ESTATES PVT. LTD.
> Director: Mrs. S. Lalitha
> 
> Date of registration: eight days before Mr. R. Raghavan's death.

### 358. Evidence E16
*(only if: patta_tout)*
- Patta (bought from a tout): Kongu Green Estates
  - Pudhur Vayal's owner (bought): Kongu Green Estates, director Mrs. S. Lalitha. Registered 8 days before sir died. Paid a tout ₹2,000 for it.

### 359. Talk
*(only if: patta_tout)*
- **Karthik:** (S. Lalitha. Lalitha... Suresh sir's wife is Lalitha madam.)
- **Karthik:** (And a man by a gate knows my name and my face now. Sundaram sir said, don't pay anybody.)

### 360. Drive: Home, Ganapathy
**Goal:** Home

### 361. At home
- Rest till it's time to sign

### 362. Message from Dr. Priya
*(only if: patta_revathi)*
> Revathi found it in the registration folder, a photocopy. Pudhur Vayal 214–226: KONGU GREEN ESTATES. Director: Mrs. S. Lalitha. That's Lalitha aunty. Suresh uncle's wife. Registered eight days before Appa died. – Priya

### 363. Evidence E16
*(only if: patta_revathi)*
- The office's copy of the patta: Kongu Green Estates
  - Pudhur Vayal's owner: Kongu Green Estates, director Mrs. S. Lalitha, Suresh's wife. Registered 8 days before sir died. The office's own copy, found by Revathi.

### 364. Talk
*(only if: patta_revathi)*
- **Karthik:** (Suresh sir already owned the land sir refused to sign away. Eight days before.)

### 365. At home
- Out: the station by seven

### 366. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 367. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 368. In the room: police
- Out

### 369. Drive: Home, Ganapathy
**Goal:** Home

### 370. At home
- Your wall: the land
- Sleep

### 371. Message from Dr. Priya
> Revathi saw Suresh uncle's desk calendar. Day 2: 'Lunch, Siruvani Grand, GV buyers (Chennai).' The day before Appa drew the cash. – Priya

### 372. Talk
- **Karthik:** (Selling Green Valley to buyers from Chennai, a day before sir even drew the farmers' money.)
- **Karthik:** (The Siruvani Grand. I've driven sir there a hundred times. I've never been past the door.)

### 373. Pin

### 374. At home
- Out to your scooter

### 375. Drive: The Siruvani Grand, Avinashi Road
**Goal:** The Siruvani Grand: the doorman sees everyone who comes for lunch

### 376. Meet Hotel security
**Goal:** The hotel's front door

### 377. Talk
- **Hotel security:** Sir, deliveries at the back gate. Service lane, on the left. *(neutral, low, point)*
- **Karthik:** I'm not delivering. I want to have lunch. *(frustrated, low)*
- **Hotel security:** (He looks at my rider jacket, my rubber slippers, the scooter.) Back gate, sir.

### 378. Choice
**The doorman in the maroon coat watches from the steps.**
- Go to The Noyyal Galleria, buy clothes that get past that door, come back for lunch (₹2,500 or more)  `→ grand_shirt`
- Slip the doorman ₹200 on the steps  `→ grand_tip`
- Not today. Come back when there's money  `→ grand_later`

### 379. Talk
*(only if: grand_tip)*
- **Ganesan (doorman):** (The note vanishes into his coat.) Suresh sir? Big man, sir. Comes, goes. I see nothing, sir. Nothing at all.
- **Karthik:** (Two hundred rupees, for nothing. A man at a gate who's paid says what's safe.)

### 380. Talk
*(only if: grand_later)*
- **Karthik:** (Two thousand three hundred for a shirt and a lunch. A quarter of the rent. Another day, when the app pays.)

### 381. Drive: The Noyyal Galleria, Avinashi Road
*(only if: grand_shirt)*
**Goal:** The Noyyal Galleria: a shirt that gets past a hotel door

### 382. Shop
*(only if: grand_shirt)*

### 383. Talk
*(only if: grand_dressed)*
- **Karthik:** (I change in the trial room and fold the rider jacket into the bag. In the mirror, a man who could walk through a hotel door.)

### 384. Talk
*(only if: grand_shirt)*
- **Karthik:** (I change in the trial room. Something cheap, to save the lunch money. It'll do. It'll have to.)

### 385. Drive: The Siruvani Grand, Avinashi Road
*(only if: grand_shirt)*
**Goal:** Back to the Siruvani Grand, for lunch

### 386. Meet Hotel security
*(only if: grand_shirt)*
**Goal:** The front door, again

### 387. Talk
*(only if: grand_dressed)*
- **Hotel security:** Good afternoon, sir. Welcome to the Siruvani Grand. *(respectful, low, namaste)*
- **Karthik:** (He doesn't know me. A shirt was all it took.)

### 388. Talk
*(only if: grand_shirt)*
- **Hotel security:** (His eyes go to my feet, and stay there.) Sir... back gate. Service lane, on the left.
- **Karthik:** (He looked at my feet. Half a shirt gets you half way.)

### 389. Eat out
*(only if: grand_dressed)*
**Goal:** Lunch at the Siruvani Grand's restaurant

### 390. Meet Ganesan (doorman)
*(only if: grand_shirt)*
**Goal:** On the way out: the doorman, Ganesan

### 391. Talk
*(only if: grand_dressed)*
- **Ganesan (doorman):** Sir... you're Raghavan sir's driver. Six years you waited outside in the white car. Today you came in by the front door. *(surprised, medium)*
- **Karthik:** Anna. Two weeks ago. Suresh sir, lunch, two men from Chennai. *(curious, medium)*

### 392. Talk
*(only if: grand_shirt)*
- **Ganesan (doorman):** (Low, not looking at me.) Not here, sir. Not like this, with the whole lobby watching me send you round the back. Come properly, another day, and ask.
- **Karthik:** (Six hundred rupees saved. Whatever he knows walks back in through the front door without me.)

### 393. Talk
*(only if: grand_dressed)*
- **Karthik:** (My phone. If he says it, I want it said twice.)

### 394. Record
*(only if: grand_dressed)*

### 395. Talk
*(only if: grand_dressed)*
- **Ganesan (doorman):** Land people. Files on the table, a map. Suresh sir was turning his ring, the big emerald. He turns it when he's selling. Thirty years I've opened doors, sir. I know a man selling. *(nervous, medium)*
- **Ganesan (doorman):** When they left, one of them said, 'Once the old man signs, Green Valley is ours.' Then they laughed. *(nervous, medium)*
- **Ganesan (doorman):** Raghavan sir always gave me a hundred at Pongal. Every year. ...If someone asks me properly, I'll say it. *(sad, medium)*

### 396. Record
*(only if: grand_dressed)*

### 397. Evidence E18
*(only if: grand_dressed)*
- Ganesan: Suresh selling Green Valley, Day 2
  - The Siruvani Grand: Day 2: Suresh with two land buyers from Chennai, turning his emerald ring. 'Once the old man signs, Green Valley is ours.'

### 398. Drive: Home, Ganapathy
**Goal:** Home

### 399. At home
- Rest till it's time to sign

### 400. At home
- Out: the station by seven

### 401. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 402. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 403. In the room: police
- Out

### 404. Drive: Home, Ganapathy
**Goal:** Home

### 405. At home
- Your wall: the ring
- Sleep

### 406. At home
- Your wall: when did he die?

### 407. Talk
- **Karthik:** (10:20, Ashwin's door. 10:35, Sekar sees the SUV turn in. If sir died after that, I was on the road home, twelve kilometres away.)
- **Karthik:** (The post-mortem. The Government Hospital's mortuary.)

### 408. Pin

### 409. At home
- Out to your scooter

### 410. Drive: Coimbatore Medical College Hospital
**Goal:** Coimbatore Medical College Hospital

### 411. Meet The mortuary attendant
**Goal:** The mortuary attendant, by the side gate

### 412. Talk
- **Karthik:** Anna. The post-mortem report. Raghavan, Race Course. Two weeks ago. *(respectful, low)*
- **The mortuary attendant:** Family only. Police or court. ...You are family? *(suspicious, low)*
- **The mortuary attendant:** (He lowers his voice.) For close friends of the family, it can be seen. Three thousand. A copy, with seal.

### 413. Act
**Goal:** The post-mortem report: ask the family (call Priya), ask the court (call Sundaram sir), or pay the attendant ₹3,000

### 414. Talk
*(only if: pm_paid)*
- **The mortuary attendant:** Wait here. (Twenty minutes. He comes back with two photocopied pages, a round seal, still damp.)

### 415. Handed: paper
*(only if: pm_paid)*
> Name: R. Raghavan, 61.
> Cause of death: head injury.
> Time of death: approximately 10 PM.
> 
> (The type is crooked. The doctor's signature is the same squiggle on both pages.)

### 416. Message from Sundaram sir
*(only if: pm_paid)*
> You sent me a photo of a 'post-mortem'. Thambi, that seal is from a rubber-stamp shop, and no forensic doctor writes 'approximately 10 PM'. It's fake. Three thousand rupees. Ask the family. – Sundaram

### 417. Take
*(only if: pm_paid)*

### 418. Talk
*(only if: pm_priya)*
- **Karthik:** (I call Priya. She listens without a word, then: 'I'm his daughter. I'll ask for it myself.')

### 419. Talk
*(only if: pm_paid)*
- **Karthik:** (I call Priya. She listens without a word, then: 'I'm his daughter. I'll ask for it myself.')

### 420. Talk
*(only if: pm_paid)*
- **Karthik:** (I call Priya. She cuts it after one ring. ...Sundaram sir, then. The slow way, the right way.)

### 421. Talk
*(only if: pm_sundaram)*
- **Advocate Sundaram:** (on the phone) The post-mortem? Thambi, you are the accused. The law gives you a copy of every document the police rely on, and that report is one of them. I'll apply today. *(frustrated, low)*
- **Advocate Sundaram:** It comes with the court's papers, not tomorrow. But nobody will ever call it a fake. *(confident, low)*

### 422. Drive: Home, Ganapathy
**Goal:** Home. But lose the black sedan first: don't lead it to Amma and Divya

### 423. Scene

### 424. At home
- Divya, at the window

### 425. Talk
- **Divya:** Anna. There's a black car at the corner. It came in right after you. Nobody's got out. *(fear, medium)*
- **Karthik:** Stay away from the window. And don't tell Amma. *(fear, medium)*
- **Divya:** (She already has her phone up.) Number plate. TN 37... the last four are covered with mud. On purpose. *(confident, low)*

### 426. Evidence lead_sedan
- A black sedan, following
  - The black sedan: Behind me from the hospital, at our corner after. TN 37, the last four muddied. Sekar saw a black car at the site gate that night.

### 427. Talk
*(only if: sedan_lost)*
- **Divya:** Anna? You're breathing like you ran all the way. *(confused, medium)*
- **Karthik:** Traffic. ...Stay away from the window tonight, okay? And don't tell Amma. *(nervous, medium)*
- **Divya:** (She looks at the window anyway. The street is empty.)

### 428. Evidence lead_sedan
*(only if: sedan_lost)*
- A black sedan, following
  - The black sedan: Behind me from the hospital; I lost it in the lanes before home. TN 37, the last four muddied. Sekar saw a black car at the site gate that night.

### 429. Message from Dr. Priya
> I read the post-mortem myself, as his daughter. Time of death between 10:40 and 11:10 PM. Karthik... where were you then? Tell me the truth. – Priya

### 430. Talk
- **Karthik:** (10:40. At 10:21 Ashwin's doorbell had me in Saravanampatti. Twelve kilometres. On a scooter, at night, twenty-five minutes at least.)
- **Karthik:** (I send her the doorbell clip's time, and the road home. Nothing else. She can do the sum herself.)

### 431. Evidence E17
- Post-mortem: death 10:40 to 11:10 PM
  - The post-mortem (E17): Death between 10:40 and 11:10 PM. Read by Priya, his daughter. At 10:21 I was at Ashwin's door, 12 km away.

### 432. At home
- Rest till it's time to sign

### 433. At home
- Out: the station by seven. The corner is empty now

### 434. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 435. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 436. In the room: police
- Out

### 437. Drive: Home, Ganapathy
**Goal:** Home

### 438. At home
- Your wall: the minutes, and the car
- Sleep

### 439. Message from Constable Selvi
*(only if: patta_tout)*
> The tout at the Collectorate gate was arrested this morning. His notebook has your name: '₹2,000, Pudhur Vayal patta, the accused in 412.' The inspector has seen it. – Selvi

### 440. Bail
*(only if: patta_tout)*

### 441. Talk
*(only if: patta_tout)*
- **Karthik:** (Two thousand rupees, and now my name is in a tout's book, in the inspector's hand. Sundaram sir said: don't pay anybody.)

### 442. At home
- Your wall: who drove sir's SUV?

### 443. Talk
- **Karthik:** (Sir's white SUV was locked in his garage that night, the police said. Both keys in the house. Then who drove it to Pudhur?)
- **Karthik:** (Somebody had a third key.)

### 444. Message from Sundaram sir
> The SUV's dealer says two keys were sold with it, both with the family. A third means a transponder copy: a chip key, cut and programmed. Not every key-cutter can. Find who can. – Sundaram

### 445. Pin

### 446. At home
- Out to your scooter

### 447. Drive: Town Hall, Coimbatore
**Goal:** Town Hall: the key-cutters on the pavement

### 448. Ask
**Goal:** Find the key-cutter: somewhere on Town Hall's pavement, under an umbrella

### 449. Talk
- **Karthik:** Anna. A car key. A big white SUV, the kind with a chip in it. Has anyone asked you for one? *(curious, low)*
- **The key-cutter:** Chip key? (He laughs and holds up his file.) Thambi, I cut almirah keys and padlocks. For chip keys you need a machine and a computer. Try R.S. Puram, the shop by the flyover. *(happy, low, laugh)*

### 450. Drive: R.S. Puram, Coimbatore
**Goal:** R.S. Puram: the key shop by the flyover

### 451. Ask
**Goal:** Find the key shop: one of the shops by the R.S. Puram flyover

### 452. Talk
- **The key shop owner:** A transponder for that SUV? Not from me, not this year. I'd need the car itself here, on my machine, an hour. *(confident, low)*
- **The key shop owner:** In this city, the dealer, and three or four workshops with the programmer. The good one's in Ganapathy. Bala Motors. That boy can do anything with a car. *(relaxed, low)*
- **Karthik:** (Bala Motors. Two streets from our house.)
- **Karthik:** (No. Bala would have told me.)

### 453. Drive: Home, Ganapathy
**Goal:** Home

### 454. At home
- Wait till it's time to sign. Your phone is in your hand

### 455. At home
- Out: the station by seven

### 456. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 457. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 458. In the room: police
- Out

### 459. Drive: Bala Motors, Ganapathy
**Goal:** Bala Motors, two streets from home

### 460. Scene

### 461. Contact

### 462. Dial
**Goal:** Call Bala: your phone, Contacts

### 463. Talk
- **Karthik:** (It rings, and rings. He always picks up. Always.)
- **Karthik:** (Morning, then.)

### 464. Drive: Home, Ganapathy
**Goal:** Home

### 465. At home
- Try to sleep

### 466. At home
- Out to your scooter

### 467. Drive: Bala Motors, Ganapathy
**Goal:** Bala Motors. The shutter's up

### 468. Meet Bala
**Goal:** Bala, at his workbench

### 469. Talk
- **Bala:** Da! This early? Coffee? Sorry I didn't pick up last night, the phone was in the car I was— *(happy, medium)*
- **Karthik:** Bala. A month ago. Did Suresh sir bring Raghavan sir's white SUV here? *(nervous, medium)*
- **Bala:** Yes, for service. Oil, front brake pads. Why? *(confused, low)*
- **Karthik:** And a key? *(curious, medium)*
- **Bala:** (He stops wiping his hands.) A spare. For the office, he said. Sir's partner, da. Why would I ask? *(nervous, medium)*
- **Karthik:** Show me the job card. *(confident, medium)*

### 470. Handed: paper
> Vehicle: white SUV, Raghavan Developers.
> Work: engine oil and filter; front brake pads; SPARE KEY (transponder), cut and programmed.
> Ordered by: Suresh sir.
> Paid: cash, ₹6,800.
> Date: two weeks before Day 1.
> 
> – Bala (signed)

### 471. Talk
- **Karthik:** (A spare, the card says. Bala's machine would say exactly when.) Your key programmer keeps a log, doesn't it? Open it.
- **Bala:** It's locked, da. I put a PIN on it after the break-in last year. My head's gone, I can't... I wrote it down somewhere so I'd never forget. It's here somewhere. Look, if you want. *(embarrassed, low)*

### 472. Keypad
**Goal:** Find the PIN for Bala's key programmer, and open its log

### 473. Evidence E11L
*(only if: prog_log)*
- The key programmer's log: key 3, Suresh's number
  - The machine's log (E11L): Bala's programmer: a third key added to sir's SUV, 7:52 PM, two weeks before. The customer's mobile on it is Suresh's. A machine can't be written last night.

### 474. Talk
*(only if: prog_log)*
- **Karthik:** (Key 3 of 3. 7:52 PM. And the customer's mobile... I know that number. Suresh sir's.) A machine doesn't forget, Bala.

### 475. Talk
- **Karthik:** (Locked. The job card will have to do. Their lawyer will say Bala wrote it last night.)

### 476. Talk
- **Karthik:** That key opened sir's car the night he died, Bala. *(confident, medium)*
- **Bala:** (For a long time he doesn't say anything. A radio is playing somewhere in the back.)
- **Bala:** He's been coming for tea. Nearly every evening, since. 'How's our Karthik? Where's he going these days?' I thought he cared about you, da. I thought he was helping. *(sad, medium)*

### 477. Talk
*(only if: told_bala)*
- **Bala:** I told him. The doorbell. Sekar's shop. Pudhur Vayal. Everything you told me at your door. And then that black car behind you... Da, that was me. I did that. *(grieving, medium)*

### 478. Talk
- **Bala:** And before. Before that night. 'Where's Karthik taking sir tomorrow? What time does he finish? Does he take his own phone home?' I told him. Every time. Like it was nothing. *(fear, medium)*

### 479. Handed: paper
> Suresh sir: Bala, tomorrow our Karthik takes sir to the bank?
> Bala: Yes sir, morning. Then office.
> Suresh sir: And night? He goes home on time?
> Bala: He does deliveries after 9 now sir, for extra.
> Suresh sir: Good boy. Hardworking. 👍
> 
> (Two days before Day 1.)

### 480. Evidence E11
- Bala's job card: the spare key, Suresh's order
  - The third key (E11): Job card #1184: a transponder spare key for sir's SUV, ordered and paid in cash by Suresh, two weeks before.

### 481. Evidence E12
- Bala's chats: Suresh asking about my day
  - How he knew (E12): Suresh learnt my day from Bala over tea: the bank, the office, deliveries after nine, my phone. Bala never knew.

### 482. Choice
**Bala is crying. He doesn't wipe it away.**
- Put a hand on his shoulder. "You didn't know, da."  `→ bala_forgiven`
- Walk out. He can come to you when he's ready  `→ bala_walked`

### 483. Talk
*(only if: bala_forgiven)*
- **Karthik:** You didn't know, da. He used you like he used me. Now we tell Sundaram sir. Together. *(respectful, medium, comfort)*
- **Bala:** (He nods, and nods, and can't stop.) Whatever you need. The court, a car, anything. Anything, da. *(sad, medium)*

### 484. Talk
*(only if: bala_walked)*
- **Karthik:** (I put the job card in my pocket and walk out into the sun. Behind me he says my name once. I don't turn round.)

### 485. Message from Bala
*(only if: bala_walked)*
> Da. I went to Sundaram sir myself. I gave him everything, the card, the chats. I'll say it in court. You don't have to talk to me. – Bala

### 486. Drive: Home, Ganapathy
**Goal:** Home

### 487. At home
- Rest till it's time to sign

### 488. At home
- Out: the station by seven

### 489. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 490. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 491. In the room: police
- Out

### 492. Drive: Home, Ganapathy
**Goal:** Home

### 493. At home
- Your wall: the key, and who told him

### 494. Call

### 495. Talk
- **Suresh sir (on the phone):** Boss! Karthik. How are you, how's Amma, how's Divya's college? *(happy, medium)*
- **Suresh sir (on the phone):** Listen. You've been busy, I hear. Let's talk. Just us. You and me, like the old days. Tomorrow night. I'll send you the place. *(relaxed, low)*
- **Karthik:** (His voice is warm. It always was.)

### 496. At home
- Sleep

### 497. Message from Suresh sir
> Boss. Pudhur Vayal, the site gate, 6:40 this evening. Come alone. Bring the photos and Bala's card. We'll settle this like gentlemen, and nobody else gets hurt. – Suresh

### 498. Talk
- **Karthik:** (6:40. At the place sir died. Twenty kilometres from the station, and I have to sign by seven.)
- **Karthik:** ('Nobody else gets hurt.' Amma. Divya.)

### 499. Choice
**His message sits on the screen.**
- Call Sundaram sir before anything  `→ trap_called`
- Go. Alone, as he says  `→ trap_went`

### 500. Dial
*(only if: trap_called)*
**Goal:** Call Sundaram sir

### 501. Talk
*(only if: trap_called)*
- **Advocate Sundaram:** (on the phone) 6:40 at Pudhur? Thambi, think. If you're at a murder site at 6:40 you can't sign at seven. That's a breach. And if anything happens to him there, whom do they arrest? *(angry, medium)*
- **Advocate Sundaram:** You don't go. You forward me that message, and you go and sign on time. A man who sends a message like that is frightened. Let him be frightened. *(confident, medium)*
- **Advocate Sundaram:** And thambi: with the note, the land and Bala's card, I'm filing today for his bank statements and for one Pandi's phone records. The court will hear it. *(confident, low)*

### 502. At home
*(only if: trap_went)*
- Wait for evening
- Out, alone

### 503. Drive: Pudhur Vayal, off the Thondamuthur road
*(only if: trap_went)*
**Goal:** Pudhur Vayal, the site gate, 6:40

### 504. Meet Suresh
*(only if: trap_went)*
**Goal:** Suresh sir, by his car at the gate

### 505. Talk
*(only if: trap_went)*
- **Suresh:** Boss! You came. Good boy. ...Sit, sit. Nobody here but the frogs. *(happy, medium, wave)*

### 506. Provoke
*(only if: trap_went)*
**Goal:** Don't give him what he wants
- **:** Here. (A bag on the roof of his car.) Five lakhs. Take Amma and Divya to Ooty. A new start. Forget the photos, forget the card. What good did any of it do Raghavan?
- **:** Your Amma still buys her vegetables from Valliammai, no? Nice lady. Talks a lot.
- **:** No? ...Then think about your sister walking home from that college. Every evening. Alone.

### 507. Talk
*(only if: trap_grabbed)*
- **Karthik:** (My hands are in his collar before I know it. He doesn't fight. He smiles wider.)
- **Inspector Murugesan:** (Headlights. Boots on gravel.) ENOUGH! Hands off him! ...An accused on bail, at the scene, at a witness's throat. I'll write this down, Karthik. Every word. *(angry, high, argue)*
- **Suresh:** (Straightening his shirt.) I only wanted to help the boy, inspector. You saw. *(relaxed, low)*

### 508. Bail
*(only if: trap_grabbed)*

### 509. Talk
*(only if: trap_took)*
- **Karthik:** (The bag is heavier than it looks. I've lifted it off the car before I know why.)
- **Inspector Murugesan:** (Headlights. Boots on gravel.) Put it down. ...Five lakhs, in an accused's hands, from a witness, at the scene. Do you know what that looks like, Karthik? It looks like a price. *(suspicious, high)*
- **Suresh:** He asked me for money, inspector. I only wanted the family to be all right. You saw. *(sad, low)*

### 510. Bail
*(only if: trap_took)*

### 511. Talk
*(only if: trap_walked)*
- **Karthik:** (I walk. My back burns all the way to the scooter. Behind me he laughs, and then he doesn't.)
- **Karthik:** (It's 6:52. Twenty kilometres to the station.)

### 512. Message from Sundaram sir
*(only if: trap_went)*
> Divya tells me where you went. Never again without calling me, thambi. Never. I'm filing today for his bank statements and one Pandi's phone records. – Sundaram

### 513. At home
- Stay home till it's time to sign
- Out: the station by seven

### 514. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 515. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 516. In the room: police
- Out

### 517. Drive: Home, Ganapathy
**Goal:** Home

### 518. At home
- Your wall
- Sleep

### 519. Message from Sundaram sir
> The court granted both. His account: on Day 5, ₹4,00,000 in cash paid into 'Om Sakthi Traders', a money-lender in Ukkadam (E10). And Pandi, the lender's driver, lent to Suresh: his phone was at Pudhur Vayal from 10:30 to 11:00 that night (E13). The police must pick him up now. – Sundaram

### 520. Evidence E10
- Court order: ₹4 L into Om Sakthi Traders
  - The money (E10): Day 5: ₹4,00,000 cash from Suresh's account into Om Sakthi Traders, a money-lender in Ukkadam.

### 521. Evidence E13
- Court order: Pandi's phone at the site
  - Pandi (E13): The lender's driver, lent to Suresh. Built like me. His phone at Pudhur Vayal, 10:30 to 11:00 PM that night.

### 522. Message from Sundaram sir
*(only if: pm_sundaram)*
> And the post-mortem, from the court's papers: time of death between 10:40 and 11:10 PM. Where were you at 10:40, thambi? Saravanampatti. Twelve kilometres away. – Sundaram

### 523. Evidence E17
*(only if: pm_sundaram)*
- Post-mortem (the court's copy): death 10:40 to 11:10 PM
  - The post-mortem (E17): Death between 10:40 and 11:10 PM. Read by Priya, his daughter. At 10:21 I was at Ashwin's door, 12 km away.

### 524. At home
- Wait. Something will happen today

### 525. Call

### 526. Talk
- **Constable Selvi:** (on the phone, low) Karthik. The stand office called the station. A man matching Pandi is at Gandhipuram bus stand, at the Salem counter. The inspector is in court. I can't leave the desk. *(nervous, medium)*
- **Constable Selvi:** The stand office says: a black cap, a dark jacket, grey trousers. The Salem bus leaves in a few minutes. *(confident, low)*
- **Constable Selvi:** Don't touch him. Don't speak to him. Keep him in sight and call me. A patrol is ten minutes away. *(confident, medium)*

### 527. Contact

### 528. Pin

### 529. At home
- Out. Fast

### 530. Drive: Gandhipuram Central Bus Stand
**Goal:** Gandhipuram Central Bus Stand, before the Salem bus leaves

### 531. Spot
**Goal:** By the Salem counter: find the man Selvi described (black cap, dark jacket, grey trousers)

### 532. Talk
- **Karthik:** (Cap, dark jacket. My height, my build. From behind, at night, sir would have got into the car.)
- **The man in the cap:** (He sees me. He knows me. His hand goes to the ticket in his pocket.)

### 533. Choice
**The Salem bus is pulling into the bay.**
- Call Selvi and keep him in sight  `→ pandi_called`
- Stand in the bus door so he can't get on  `→ pandi_blocked`
- Grab him  `→ pandi_grabbed`

### 534. Talk
*(only if: pandi_called)*
- **Karthik:** (Selvi, on the phone: 'Stay where you are.' He boards. I stand by the bus, where he can see me through the glass, and I don't move. The driver honks. Nobody moves.)

### 535. Talk
*(only if: pandi_blocked)*
- **Karthik:** (I stand in the door. He tries the back door. The conductor shouts at both of us. Three minutes of shouting is three minutes.)

### 536. Talk
*(only if: pandi_grabbed)*
- **Karthik:** (I have his jacket. He swings, I hold on, we go down on the platform. A crowd. Someone films it on a phone.)

### 537. Talk
- **Karthik:** (A siren. Two constables push through the crowd. Then the inspector, still in his court shoes.)
- **Inspector Murugesan:** Pandi. Om Sakthi Traders' driver. Your phone was at Pudhur Vayal the night Raghavan died. Get in the jeep. *(confident, high, point)*
- **The man in the cap:** (In the jeep, before the door shuts:) He promised me two lakhs. He gave me forty thousand. I'm not going down for him alone. I'll tell everything. *(fear, high)*

### 538. Talk
*(only if: pandi_bus_left)*
- **Constable Selvi:** (on the phone) The patrol stopped the Salem bus at the Avinashi Road signal. He's in the jeep. ...Next time, Karthik, you look faster or you call sooner. *(confident, low)*
- **Karthik:** (That evening at the station he sits in the corner of the inspector's room, no cap now. He looks at me once and starts talking.)
- **The man in the cap:** He promised me two lakhs. He gave me forty thousand. I'm not going down for him alone. I'll tell everything. *(angry, medium)*

### 539. Talk
*(only if: pandi_grabbed)*
- **Inspector Murugesan:** And you. A fight in a bus stand, on bail, on camera. Rules are rules, Karthik. *(frustrated, medium)*

### 540. Bail
*(only if: pandi_grabbed)*

### 541. Talk
- **Inspector Murugesan:** (He looks at me for a long moment. For the first time, not like a man looking at a file.) ...Sign this evening anyway. Rules are rules. And Karthik. Sit, when you come. Have tea.

### 542. Evidence E19
- Bus stand: Pandi buying a ticket to Salem
  - Pandi, held (E19): Caught at the Salem counter, on the stand's camera. Promised two lakhs, paid forty thousand. He'll turn approver.

### 543. Drive: Home, Ganapathy
**Goal:** Home

### 544. At home
- Rest till it's time to sign
- Out: the station by seven

### 545. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 546. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 547. In the room: police
- Out

### 548. Drive: Home, Ganapathy
**Goal:** Home

### 549. At home
- Your wall: the man in the cap
- Sleep

### 550. Message from Unknown number
> Karthik? Joseph, accounts, Raghavan Developers. I can't be seen near the office or your house. The agri-machinery fair is on at CODISSIA. Hall B, the tractor stalls, 2 PM. Come alone. – Joseph

### 551. Talk
- **Karthik:** ('Come alone.' The last man who said that had five lakhs on his bonnet.)

### 552. Choice
**Joseph has worked for sir for twenty years.**
- Call Sundaram sir first  `→ joseph_checked`
- Just go  `→ joseph_straight`

### 553. Dial
*(only if: joseph_checked)*
**Goal:** Call Sundaram sir

### 554. Talk
*(only if: joseph_checked)*
- **Advocate Sundaram:** (on the phone) Joseph? A good man, and a frightened one. A trade fair at two in the afternoon: a thousand people around you. Go. Record him. And come straight back. *(relaxed, low)*

### 555. At home
- Wait till it's time to go
- Out to your scooter

### 556. Pin

### 557. Drive: CODISSIA Trade Fair Complex
**Goal:** CODISSIA Trade Fair Complex, Hall B, by 2 PM

### 558. Scene

### 559. Meet Joseph (accounts)
**Goal:** Joseph, pretending to look at a tractor

### 560. Talk
- **Joseph (accounts):** Don't look at me. Look at the tractor. Stand at it like you're reading the price. *(nervous, high)*
- **Karthik:** (My phone. The recorder. If he says it, I want it on tape.)

### 561. Covert
**Goal:** At the tractor: record Joseph on your phone, and keep your eyes on the tractor
- **:** Twenty years I kept sir's books. These last two years, the books didn't add up.
- **:** Suresh borrowed one crore eighty lakhs from Om Sakthi Traders. Three percent a month. For Green Valley, in his wife's company's name. Sir never knew.
- **:** If sir paid the farmers a fair price, Green Valley was worth nothing to him. And the lender doesn't wait. You've met his driver.

### 562. Talk
- **Joseph (accounts):** (He drops a folded sheaf into the tractor's seat, as if he's left a brochure.)

### 563. Talk
*(only if: joseph_spooked)*
- **Karthik:** (He's gone. But as he went, he dropped something on the tractor's seat. Folded pages.)

### 564. Handed: paper
> Loan from Om Sakthi Traders, Ukkadam: ₹1,80,00,000 at 3% per month, against Kongu Green Estates.
> Interest owing: ₹16,20,000 (three months unpaid).
> Note in Joseph's hand: 'S. says GV sale will clear it. R. not told.'
> 
> Day 5: ₹4,00,000 cash paid to Om Sakthi Traders.

### 565. Evidence E15
*(only if: joseph_taped)*
- Joseph: Suresh's debts to the lender
  - Suresh's debt (E15): ₹1.8 crore from Om Sakthi Traders at 3% a month, for Green Valley. A fair price for the farmers would have sunk him.

### 566. Talk
*(only if: joseph_taped)*
- **Joseph (accounts):** I kept quiet two weeks. I have two daughters too, thambi. ...If the court calls me, I'll say it. Now walk away. Slowly. Look at the harvesters. *(nervous, medium)*

### 567. Talk
- **Karthik:** (His pages, but not his voice. Pages anyone could have typed. A lawyer will say so.)

### 568. Message from Sundaram sir
> The Sessions Court sits day after tomorrow, 10:30 AM. The prosecution will put the night to you minute by minute. So will we. Bring your wall, thambi. All of it. – Sundaram

### 569. Drive: Home, Ganapathy
**Goal:** Home

### 570. At home
- Rest till it's time to sign
- Out: the station by seven

### 571. Drive: Nagar Police Station, Gandhipuram
**Goal:** Sign at the station by 7 PM

### 572. In the room: police
- Sign the bail register at Selvi's desk (sign)

### 573. In the room: police
- Out

### 574. Drive: Home, Ganapathy
**Goal:** Home

### 575. At home
- Your wall: the whole night, minute by minute
- Sleep

### 576. At home
- Amma has ironed your white shirt

### 577. Talk
- **Amma:** Your appa's shirt. I kept it for your wedding. ...Wear it today. *(happy, medium, give)*
- **Divya:** I made a timeline, anna. On my laptop. Every minute. Sundaram sir has it. *(confident, medium)*

### 578. Talk
*(only if: bala_forgiven)*
- **Bala:** (At the door, in his best shirt, the workshop car washed.) Get in, da. Court. *(confident, medium)*

### 579. At home
- Out

### 580. Drive: Combined Court Complex, Coimbatore
**Goal:** The Combined Court Complex, by 10:30

### 581. Card

### 582. Room

### 583. Court

### 584. Room

### 585. Room
*(only if: court_won)*

### 586. Room

### 587. Room

### 588. Bail

### 589. Drive: Home, Ganapathy
**Goal:** Home. No station tonight

### 590. At home
- Evening. Someone at the door

### 591. Talk
*(only if: funeral_went)*
- **Dr. Priya:** Karthik. I slapped you at my father's gate, in front of everyone. ...I'm sorry. I was wrong about you. So I'm saying this in front of everyone too. *(embarrassed, high)*

### 592. Talk
- **Dr. Priya:** (Behind her mother, on the step.) Karthik. At the temple I said I'd call the police on you, in front of my mother. ...I'm sorry. I was wrong about you, and I said it in front of people. So I'm saying this in front of people too. *(embarrassed, medium)*

### 593. Talk
- **Meenakshi amma:** (She puts a bunch of keys and a thick envelope in Amma's hands.) The Mist Village. Up in the hills, past Kotagiri. He was going to give it to the boy who drove him for six years without one complaint. *(respectful, medium, give)*
- **Meenakshi amma:** He trusted you. He'd want it to be yours. *(sad, low)*
- **Amma:** (She can't speak. She holds the keys against her chest.)

### 594. At home
- Sleep. Tomorrow, the hills

### 595. At home
- Dawn. Out to the road

### 596. Drive: The Kotagiri ghat checkpost
**Goal:** North, through Mettupalayam, to the Kotagiri ghat

### 597. Talk
- **Karthik:** (The checkpost. The same constable who turned me back once. He looks at his list, and at me, and lifts the barrier.)
- **Karthik:** (The road climbs into the mist. Nine hairpins to Kotagiri, sir used to say. He counted them every time.)

### 598. Finale
