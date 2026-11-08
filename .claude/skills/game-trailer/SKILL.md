---
name: game-trailer
description: Make advertising videos for The Mist Village (the Godot game in this repo) from real in-game footage. Use for a Steam store trailer (16:9), short vertical social ads (9:16 Reels/Shorts), teaser clips, or English and Tamil versions of any of them. It records clips with Godot's Movie Maker, writes an original score, and cuts MP4s with title cards. Use it whenever the user asks for a trailer, ad, promo, teaser, gameplay video, "video for my advertisement", store video or social clip of the game, or wants an old trailer re-cut after the game changed, even if they don't say "trailer".
---

# Game trailer

Turn the game itself into advertising video: real rendered gameplay and story scenes, cut to a story hook, with
title cards in English and Tamil and a score made here. A trailer is the most-watched thing a game has, so it must
make someone feel the story's pull in the first five seconds, and it must be honest: every frame comes from the game.

## The rules that shape every trailer

- **Only real game footage.** Steam requires trailers to show the game as it plays, and players feel cheated by
  pre-rendered promises. Grading, crops, speed changes and text cards are fine; footage from anywhere else isn't.
- **The project's own rules hold here too:**
  - no jumpscares or horror stings
  - no gore (the murder is never shown, only its traces)
  - real public place names, made-up private businesses
  - modern Coimbatore, not only its poor side
- **Don't spoil the end.** Show the accusation, the investigation and the pressure; never who did it, the verdict or
  the keys to the resort.
- **Nothing downloaded without asking:** no stock music or footage. `scripts/score.py` writes an original score.
  Fonts come from the system.
- **Don't claim what isn't true.** If the game has no Steam page yet, the end card says "Coming soon on Steam", not
  "Wishlist now". Ask the user before adding a release date, price or platform.
- **Pedestrian knock-downs and crashes are not ad material.** A near miss in traffic is fine; a person falling isn't.

## Workflow

Work in `trailer/` at the repo root (git-ignored footage, a committed edit). Check `ffmpeg -version` first; if it's
missing, ask before installing it (`brew install ffmpeg`).

### Style: the open-world crime-drama trailer (the user's reference: "like the GTA 5 trailer")
Borrow the genre's language, never another game's assets: no logos, no Pricedown-style font, no music or lines
from any real trailer. What makes that style work, and how to get it here:

- **The city is a character.** Open on slow aerial establishing shots at golden hour (`--clock=17:50 --flyover=...`)
  and a night shot (`--clock=20:30`). Long, unhurried shots first; the cuts get faster later.
- **Widescreen bars:** `"letterbox": 2.39` in the edit (on the wide cut only). The bars would hide the story's own
  subtitle box, so give story shots `"lift": 0.12`: the picture rises and its subtitles clear the bottom bar.
- **No game HUD:** `--nohud` on every capture. Story subtitles stay, since they carry the dialogue.
- **Name cards:** the main characters introduced with a big condensed name and a one-line role, lower left (`"name"`,
  `"role"`). Name only people whose role is no secret: Karthik, the watchman. Never the culprit.
- **Text that works like a narrator:** short lines in the first half ("He drove the same man for six years."), then
  none during the fast cuts.
- **Music:** a groove that drops in after the calm opening (`"music": "build"`, then `"tense"`). Use `"flash": true`
  and `"fill": true` on the fast cuts, `"quiet"` for the breath before the title, and `"hit"` on it.
- **Cut lengths on the beat:** at 94 bpm a beat is 0.638 s and a bar 2.553 s. Make shot lengths whole beats (1.92,
  2.55, 3.19, 3.83, 5.10...) so the cuts land on the music.

### 1. Plan the cut on paper first
Write the beats before recording anything. Recording is the slow part (a 30 s clip can take minutes to render),
so record only what the plan needs.

| Length | Shape | Use |
|---|---|---|
| 60–90 s, 16:9 | hook (5 s) → who he is → the accusation → the investigation (gameplay) → pressure building → title → end card | Steam store, YouTube |
| 15–30 s, 9:16 | the hook in 2 s, three or four fast story beats, the title, the end card; big text, nothing important near the edges | Reels, Shorts |

Read `references/shots.md` for the story's best moments (step numbers), the gameplay shots, and how to record each.
Pull the hook lines from `docs/STORY_BIBLE.md` (the logline, the end hooks of each act).

### 2. Record the clips
```bash
.claude/skills/game-trailer/scripts/capture.sh trailer/clips NAME SECONDS [WxH] -- <game args>
```
- **What it records:** Godot's Movie Maker at a fixed 30 fps, the real render plus the game's own sound, however
  slowly the machine draws.
- **Run them in the background, one at a time.** Two Godot instances compete for the GPU and both crawl.
- **Story scenes show the game's subtitles,** so record them once per language: `--storyta` for Tamil. In the edit,
  `"clip": {"en": ..., "ta": ...}`.
- **For a vertical cut,** keep the action in the middle third of the frame, or use `"vfit": "blur"` for shots that
  need their full width.
- **`--flyover=x,y,z,yaw,pitch,x2,y2,z2,yaw2,pitch2,secs`** flies a camera over the city. It waits for the tiles to
  load and writes a mark, and the editor cuts from that mark.

Recording pitfalls, learnt the hard way:
- **Clips come out at 1600×900:** Movie Maker records the window, and the window can't be bigger than the screen.
  The editor scales to 1080p.
- **Anything a shot does over time must count frames, not real seconds.** A slow frame can take a second to draw,
  and a timer on real time skips the whole move. `--flyover` counts frames.
- **The test driver (`--testdrive`) sometimes bumps traffic,** and the other driver's line shows. Cut around it on
  the contact sheet.
- **Story scenes played with --storyskip are short:** a 45 s budget may hold only 2–15 s of scene. Some steps
  (a `bail` step, a gate) end almost at once. Check durations with ffprobe; the courtroom (541–546) and the funeral
  (89–95) give the most footage.
- **The two languages don't keep the same timing:** the Tamil courtroom reaches its evidence map 2 s after the
  English one. Check both contact sheets before choosing a "from".
- **A recording queue dies with the session that started it.** `trailer/record_all.sh` marks each finished clip
  (`.done`) and skips it when run again.

### 3. Pick the moments
```bash
.claude/skills/game-trailer/scripts/contact_sheet.sh trailer/clips/NAME.avi 2
```
- **What it makes:** a grid of frames, every 2 s, each stamped with its time.
- **Look at the sheets** (Read the JPEGs). Note each good moment's start time, and throw away clips where the city
  hasn't loaded, the camera is inside a wall or the HUD covers the action.

### 4. Write the edit
Write `trailer/<name>.json`; the format is in the docstring of `scripts/build_trailer.py`. Things that make it feel
like a trailer and not a gameplay video:
- **Shots of 1.5–4 s,** shorter as the tension builds.
- **Text cards carry the story** in a few words each ("He drove him for six years." / "Now he's the accused.").
  Write the Tamil yourself in the voice of the game's own Tamil lines (`godot/story/slice.json` has both), and tell
  the user it needs a native speaker's check, as the story bible says of all Tamil.
- **Moods for the score:** `"music"`: calm for who he is, build for the investigation, tense for the pressure,
  quiet for the beat before the title, `"hit": true` on the title card.
- **The title card:**
  - English: "THE MIST VILLAGE" / "Part 1 · The Wrong Accusation"
  - Tamil: "தி மிஸ்ட் வில்லேஜ்" (as the game writes it) / "பாகம் 1 · தவறான குற்றச்சாட்டு"
- **The end card:** a platform line the user has confirmed.

### 5. Build
```bash
python3 .claude/skills/game-trailer/scripts/score.py trailer/<name>.json trailer/<name>_score.wav
python3 .claude/skills/game-trailer/scripts/build_trailer.py trailer/<name>.json --draft      # fast check
python3 .claude/skills/game-trailer/scripts/build_trailer.py trailer/<name>.json               # final
```
Outputs go to `trailer/out/<name>_<format>_<lang>.mp4` (H.264/AAC, 30 fps, about -14 LUFS).

### 6. Check before showing
- **Look at a contact sheet of each output:** text inside the frame, Tamil shaped correctly (joined vowel signs, not
  dotted circles), no black gaps, the vertical crop keeping the faces.
- **Check the length** with `ffprobe` against the plan.
- **Send the user the MP4s** (SendUserFile), with one line on what each is for.
- **Say what is still placeholder,** such as an unconfirmed end-card line or Tamil awaiting a native check.

## When the game changes
Re-record only the clips whose scenes changed, keeping the same clip names, and rebuild: the edit JSON keeps the cut.
