# Shots for The Mist Village trailers

Step numbers are indexes into `godot/story/slice.json` "steps" (they move when steps are added: check with
`python3 -c "import json;s=json.load(open('godot/story/slice.json'))['steps'];print(s[N])"`). All runs use
`scenes/city_test.tscn`; game args go after `--` in capture.sh.

## How each kind of shot is recorded

| Kind | Game args | Notes |
|---|---|---|
| A story scene | `--nohud --story --storyskip --storyfrom=N --storystop=M` (+ `--storyta` for Tamil) | --storyskip plays it unattended, its lines advancing every ~1.5 s: cut 2–4 s pieces. `--storyclock=HH:MM` sets the hour (dusk 18:15, night 21:30) |
| Driving in the city | `--nohud --testdrive --long --clock=18:05` (+ `--weather=rain --clock=19:40` for a wet night) | follows main roads at ~50 km/h, chase camera |
| Any free-play shot at an hour | `--clock=HH:MM` | the sun held at that hour: 17:50 golden, 18:20 dusk, 20:30 night |
| Rain | `--weather=rain` | roads already soaked: reflections, wipers, grey sky |
| City from the air | `--flyover=x,y,z,yaw,pitch,x2,y2,z2,yaw2,pitch2,secs` | Gandhipuram is near 0,0 and the ground there at y ≈ 431: y 455–470 skims the rooftops, 500–560 is a wide aerial; pitch −6 to −22. Golden-hour pair used: `-160,520,420,-25,-14,80,490,-120,12,-8,14` |
| Traffic, a near miss | `--crashtest` (cut before the hit) | |

## The story's strongest moments (Part 1)

Hook and who he is (calm):
- 3, 7: Karthik driving Raghavan's white SUV through the city; 7 has the hills on the horizon ("You see those hills?").
- 37, 43: the office, the key box (the promotion, the trust).

The fall (build → tense):
- 88: the bail; the police station register (the signing every evening).
- 89–95: the funeral, white veshtis, the shamiana, the temple bell. Strong and quiet: a trailer's heart.
- 104: night, the watchman: "Stop there! ...It's you. The driver."
- 168–169: Priya at her father's gate (a confrontation; no violence on screen in the cut).

The investigation (gameplay, build):
- 110/114/195/353: covert recordings (the phone held low).
- 185: the Lawley Road camera, the SUV at 10:12 (CCTV evidence).
- 381–382: the black sedan chase on the scooter (the best action: lanes, near misses).
- 222: "They're all around the scooter." (pressure from the street).

The pressure (tense):
- 457–464: 6:40 at the place sir died; Suresh: "Boss! You came. Good boy." (night).
- 492–493: the Salem bus, Selvi on the phone: "Stay where you are."
- 541–546: the court room. Use only the room and faces, never the verdict.

Do not use: 550–557 (the apologies, the keys to The Mist Village: the ending).

## Lines that work as cards (from docs/STORY_BIBLE.md)

| English | Tamil (first draft: a native speaker should check) |
|---|---|
| He drove him for six years. | ஆறு வருஷம் அவரை ஓட்டினான். |
| A week after the promotion, his employer was dead. | பதவி உயர்வு கிடைச்சு ஒரு வாரத்துல, முதலாளி இறந்துட்டார். |
| Every trace points at him. | எல்லா தடயமும் அவனையே காட்டுது. |
| Sign at the station. Every evening. | தினமும் சாயங்காலம் ஸ்டேஷன்ல கையெழுத்து. |
| He can't leave the city. | அவன் ஊரை விட்டு போக முடியாது. |
| So he drives it. | அதனால அவன் ஊரையே ஓட்டுறான். |
| The city remembers where he was. | அவன் எங்க இருந்தான்னு ஊருக்குத் தெரியும். |
