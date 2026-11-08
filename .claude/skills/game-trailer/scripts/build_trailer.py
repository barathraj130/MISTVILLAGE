#!/usr/bin/env python3
"""Cut a trailer from captured clips, by an edit file: every format and language it asks for, each an MP4.

    build_trailer.py EDIT.json [--only wide|vertical] [--lang en|ta] [--draft]

The edit (paths relative to the edit file):
{
  "name": "steam_main",
  "formats": {"wide": [1920, 1080], "vertical": [1080, 1920]},   # which cuts to make, and their size
  "langs": ["en", "ta"],
  "fonts": {"en": ["Georgia"], "ta": ["Tamil Sangam MN"]},         # system font names (Godot draws the text)
  "letterbox": 2.39,               # widescreen bars on the wide cut (0: none)
  "bpm": 94,                       # the score's tempo (score.py)
  "music": "score.wav",            # or "auto": score.py run on each language's (narration-fitted) cut
  "vo_dir": "vo",                  # narration: <vo_dir>/<id>_<lang>.(m4a|wav|mp3|aiff), else vo/scratch/ (see fit())            # made by score.py from this same edit (optional; no music if missing)
  "game_audio": 0.35,              # the game's own sound under the music (per segment: "audio")
  "segments": [
    {"clip": "clips/flyover.avi", "from": 0.5, "dur": 5.0,          # seconds into the clip (after its .mark, if any);
                                                                    # "clip": {"en": ..., "ta": ...} when the game shows its own subtitles
     "text": {"en": "Coimbatore.", "ta": "கோயம்புத்தூர்."}, "text_at": "low",   # low | mid | top
     "vfit": "crop", "crop_x": 0.5,                                 # vertical cut: crop (centre at crop_x 0..1) or blur (whole frame over a blurred fill)
     "speed": 1.0, "music": "calm", "hit": false, "fade": 0.3,
     "flash": false, "fill": false,                                 # a white flash in; a drum fill into it (score.py)
     "lift": 0.0},                                                  # wide: raise the picture by this share of its height (story subtitles above the bars)
    {"clip": ..., "name": {"en": "KARTHIK", "ta": "கார்த்திக்"}, "role": {"en": "The driver", "ta": "டிரைவர்"}},   # a character card
    {"card": {"en": "THE MIST VILLAGE", "ta": "தி மிஸ்ட் வில்லேஜ்"}, "sub": {"en": "...", "ta": "..."},
     "dur": 4.0, "music": "hit", "hit": true}
  ]
}
Outputs: <edit dir>/out/<name>_<format>_<lang>.mp4 (H.264, AAC, 30 fps, loudness about -14 LUFS for web/Steam).
--draft: half size, fast encode, for checking the cut.
"""
import json
import os
import subprocess
import sys
import tempfile

FPS = 30
HERE = os.path.dirname(os.path.abspath(__file__))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(" ".join(cmd) + "\n" + r.stderr[-3000:])
        raise SystemExit(1)
    return r


def has_audio(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", path],
                       capture_output=True, text=True)
    return bool(r.stdout.strip())


class Texts:
    """Every caption and card line, rendered once by Godot (text_png.gd) to a transparent PNG the size of the frame's
    text band: Godot shapes Tamil properly, and needs nothing installed beyond the game's own engine."""

    def __init__(self, tmp):
        self.tmp = tmp
        self.jobs = []

    def add(self, text, fonts, size, w, h, color="#ffffff", bold=False, align="center", valign="center"):
        out = os.path.join(self.tmp, f"text{len(self.jobs):03d}.png")
        self.jobs.append({"text": text, "out": out, "w": w, "h": h, "size": size, "color": color, "fonts": fonts, "bold": bold,
                          "align": align, "valign": valign})
        return out

    def render(self):
        if not self.jobs:
            return
        jf = os.path.join(self.tmp, "texts.json")
        json.dump(self.jobs, open(jf, "w", encoding="utf-8"), ensure_ascii=False)
        root = os.environ.get("GAME_ROOT") or os.path.abspath(os.path.join(HERE, "../../../.."))
        godot = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")
        run([godot, "--path", os.path.join(root, "godot"), "--resolution", "64x64", "-s", os.path.join(HERE, "text_png.gd"), "--", jf])
        missing = [j["out"] for j in self.jobs if not os.path.exists(j["out"])]
        if missing:
            raise SystemExit("text not rendered: " + ", ".join(missing))


def overlay(inputs, chain_in, png, y, dur, idx, fade=0.4):
    """Lay a text PNG over the picture at height y, fading in and out with the shot."""
    inputs += ["-loop", "1", "-t", f"{dur:.3f}", "-i", png]
    f = min(fade, dur / 3)
    return (f"[{idx}:v]format=rgba,fade=t=in:st=0:d={f}:alpha=1,fade=t=out:st={dur - f:.3f}:d={f}:alpha=1[t{idx}];"
            f"[{chain_in}][t{idx}]overlay=0:{int(y)}:format=auto")


def bars(W, H, letterbox):
    """The height of each letterbox bar (0 for none, or for a vertical cut)."""
    if not letterbox or H > W:
        return 0
    return max(0, int((H - W / float(letterbox)) / 2)) // 2 * 2


def plan_texts(seg, W, H, lang, fonts, texts, letterbox=0):
    """The text images this segment needs: [(png, y)]."""
    vertical = H > W
    big = int((W if vertical else H) * (0.068 if vertical else 0.058))
    fl = fonts.get(lang, fonts["en"])
    bar = bars(W, H, letterbox)
    out = []
    if "name" in seg:                       # a character's name, big, lower left, the role under it
        nf = fonts.get("name_" + lang, fonts.get("name", fl))
        size = int(big * 1.9)
        band = int(size * 1.5)
        y = H - bar - int(H * (0.30 if vertical else 0.24)) - (0 if vertical else 0)
        out.append((texts.add(seg["name"].get(lang, seg["name"]["en"]), nf, size, W, band, "#FFFFFF", True, "left", "bottom"), y))
        if "role" in seg:
            rs = int(big * 0.85)
            out.append((texts.add(seg["role"].get(lang, seg["role"]["en"]), fl, rs, W, int(rs * 2.2), "#F2C14E", True, "left", "top"), y + band))
    if "card" in seg:
        title = seg["card"].get(lang, seg["card"]["en"])
        size = int(big * float(seg.get("scale", 1.35)))
        band = int(size * 3.2)
        y = (H - band) // 2 - (int(big * 0.9) if "sub" in seg else 0)
        out.append((texts.add(title, fl, size, W, band, "#F5EBD6", True), y))
        if "sub" in seg:
            sb = int(big * 0.8)
            out.append((texts.add(seg["sub"].get(lang, seg["sub"]["en"]), fl, sb, W, int(sb * 3.2), "#CFC7B8"), y + band - int(big * 0.6)))
    elif "text" in seg:
        band = int(big * 3.4)
        at = seg.get("text_at", "low")
        y = {"low": min(int(H * (0.70 if vertical else 0.74)), H - bar - band), "mid": (H - band) // 2,
             "top": max(int(H * (0.10 if vertical else 0.06)), bar)}[at]
        out.append((texts.add(seg["text"].get(lang, seg["text"]["en"]), fl, big, W, band, "#FFFFFF", True), y))
    return out


def segment(seg, base, W, H, lang, pngs, out, game_audio, draft, letterbox=0):
    dur = float(seg["dur"])
    vertical = H > W
    if "card" in seg:
        inputs = ["-f", "lavfi", "-t", str(dur), "-i", f"color=c=0x0a0d12:s={W}x{H}:r={FPS}",
                  "-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=48000:cl=stereo"]
        v = "[0:v]null[b0]"
        a = "[1:a]anull[a]"
        nxt = 2
    else:
        c = seg["clip"]                               # one clip, or one per language (the game's own subtitles)
        clip = os.path.join(base, c.get(lang, c["en"]) if isinstance(c, dict) else c)
        start = float(seg.get("from", 0.0))
        mark = os.path.splitext(clip)[0] + ".mark"
        if os.path.exists(mark):
            start += int(open(mark).read().strip() or 0) / FPS
        speed = float(seg.get("speed", 1.0))
        inputs = ["-ss", f"{start:.3f}", "-t", f"{dur * speed + 0.5:.3f}", "-i", clip]
        aud = has_audio(clip)
        nxt = 1
        if not aud:
            inputs += ["-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=48000:cl=stereo"]
            nxt = 2
        if vertical and seg.get("vfit", "crop") == "blur":
            v = (f"[0:v]setpts=PTS/{speed},fps={FPS},split[x][y];"
                 f"[x]scale=-2:{H},crop={W}:{H},boxblur=24:2,eq=brightness=-0.18[bg];"
                 f"[y]scale={W}:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2")
        elif vertical:
            cx = float(seg.get("crop_x", 0.5))
            v = f"[0:v]setpts=PTS/{speed},fps={FPS},scale=-2:{H},crop={W}:{H}:(iw-{W})*{cx}:0"
        else:
            v = f"[0:v]setpts=PTS/{speed},fps={FPS},scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H}"
            lift = int(H * float(seg.get("lift", 0))) // 2 * 2
            if lift:                                  # raise the picture: the game's own subtitles clear the bars
                v += f",crop={W}:{H - lift}:0:{lift},pad={W}:{H}:0:0:black"
        if seg.get("grade", True):                    # a gentle trailer grade: a touch of contrast and warmth
            v += ",eq=contrast=1.06:saturation=1.05,colorbalance=rs=0.02:bs=-0.02"
        v += f",trim=duration={dur},setpts=PTS-STARTPTS[b0]"
        vol = float(seg.get("audio", game_audio))
        tempo = f",atempo={speed}" if abs(speed - 1.0) > 0.01 and 0.5 <= speed <= 2.0 else ""
        a = (f"[0:a]aresample=48000,aformat=channel_layouts=stereo{tempo},volume={vol},apad,atrim=duration={dur}[a]"
             if aud else "[1:a]anull[a]")
    chain = v
    last = "b0"
    for k, (png, y) in enumerate(pngs):
        chain += ";" + overlay(inputs, last, png, y, dur, nxt) + f"[b{k + 1}]"
        last = f"b{k + 1}"
        nxt += 1
    fade = float(seg.get("fade", 0.3 if "clip" in seg else 0.5))
    chain += f";[{last}]"
    bar = bars(W, H, letterbox)
    if bar and "card" not in seg:                     # the widescreen bars, over the picture
        chain += f"drawbox=x=0:y=0:w={W}:h={bar}:color=black:t=fill,drawbox=x=0:y={H - bar}:w={W}:h={bar}:color=black:t=fill,"
    if seg.get("flash"):                              # a white flash into the shot (a hard, bright cut)
        chain += "fade=t=in:st=0:d=0.18:color=white,"
    elif fade > 0:
        chain += f"fade=t=in:st=0:d={fade},"
    if fade > 0 and not seg.get("cut_out"):
        chain += f"fade=t=out:st={dur - fade:.3f}:d={fade},"
    chain += "format=yuv420p[v]"
    enc = ["-c:v", "libx264", "-preset", "veryfast" if draft else "slow", "-crf", "26" if draft else "17", "-r", str(FPS),
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", chain + ";" + a, "-map", "[v]", "-map", "[a]",
         "-t", str(dur), *enc, out])


VO_EXTS = (".m4a", ".wav", ".mp3", ".aiff", ".aif", ".caf")


def vo_file(base, edit, sid, lang):
    """A section's narration: the recorded take (edit "vo_dir", default vo/) or else the scratch reading."""
    for d in (edit.get("vo_dir", "vo"), edit.get("vo_scratch", "vo/scratch")):
        for ext in VO_EXTS:
            p = os.path.join(base, d, f"{sid}_{lang}{ext}")
            if os.path.exists(p):
                return p
    return None


def duration(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                       capture_output=True, text=True)
    return float(r.stdout.strip() or 0)


def fit(edit, base, lang):
    """Narrated edits: a segment with "vo": "03" starts section 03, which runs to the next "vo" (or a segment with
    "vo_stop": true). Its segments are stretched or shrunk together to the reading's length (+ "vo_pad"), so a new
    take re-times the cut. Returns the segments for this language and [(voice file, start seconds)]."""
    segs = [dict(sg) for sg in edit["segments"]]
    marks = [i for i, sg in enumerate(segs) if sg.get("vo")]
    voices = []
    for n, i in enumerate(marks):
        path = vo_file(base, edit, segs[i]["vo"], lang)
        if not path:
            print(f"  (no narration for section {segs[i]['vo']} in {lang})", flush=True)
            continue
        end = marks[n + 1] if n + 1 < len(marks) else len(segs)
        for k in range(i + 1, end):
            if segs[k].get("vo_stop"):
                end = k
                break
        total = sum(float(segs[k]["dur"]) for k in range(i, end))
        want = duration(path) + float(edit.get("vo_pad", 0.6))
        for k in range(i, end):
            segs[k]["dur"] = round(float(segs[k]["dur"]) * want / total, 3)
        voices.append([path, i])
    starts, t = [], 0.0
    for sg in segs:
        starts.append(t)
        t += float(sg["dur"])
    return segs, [[p, starts[i] + float(edit.get("vo_lead", 0.25))] for p, i in voices]


def build(edit_path, only=None, lang_only=None, draft=False):
    edit = json.load(open(edit_path, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(edit_path))
    outdir = os.path.join(base, "out")
    os.makedirs(outdir, exist_ok=True)
    fonts = edit.get("fonts", {"en": ["Georgia"], "ta": ["Tamil Sangam MN"]})
    made = []
    for fmt, size in edit.get("formats", {"wide": [1920, 1080]}).items():
        if only and fmt != only:
            continue
        W, H = size
        if draft:
            W, H = W // 4 * 2, H // 4 * 2
        for lang in edit.get("langs", ["en"]):
            if lang_only and lang != lang_only:
                continue
            with tempfile.TemporaryDirectory() as tmp:
                segs, voices = fit(edit, base, lang)
                music = os.path.join(base, edit["music"]) if edit.get("music") and edit["music"] != "auto" else None
                if edit.get("music") == "auto":                 # (the score timed to this language's cut)
                    fe = dict(edit, segments=segs)
                    fj = os.path.join(tmp, "fitted.json")
                    json.dump(fe, open(fj, "w", encoding="utf-8"), ensure_ascii=False)
                    music = os.path.join(tmp, "score.wav")
                    run([sys.executable, os.path.join(HERE, "score.py"), fj, music])
                texts = Texts(tmp)
                lb = edit.get("letterbox", 0)
                planned = [plan_texts(seg, W, H, lang, fonts, texts, lb) for seg in segs]
                texts.render()
                parts = []
                for i, seg in enumerate(segs):
                    p = os.path.join(tmp, f"seg{i:03d}.mp4")
                    segment(seg, base, W, H, lang, planned[i], p, float(edit.get("game_audio", 0.35)), draft, lb)
                    parts.append(p)
                    print(f"  {fmt} {lang} segment {i + 1}/{len(segs)}", flush=True)
                lst = os.path.join(tmp, "list.txt")
                with open(lst, "w") as f:
                    for p in parts:
                        f.write(f"file '{p}'\n")
                body = os.path.join(tmp, "body.mp4")
                run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", body])
                out = os.path.join(outdir, f"{edit.get('name', 'trailer')}_{fmt}_{lang}{'_draft' if draft else ''}.mp4")
                if voices:                                     # narration: the voice on top, music and game ducked under it
                    ins = ["-i", body, "-i", music] if music else ["-i", body]
                    f = "[0:a]volume=1.0[g];" + ("[1:a]volume=0.8[m0];" if music else "")
                    vi = []
                    first = 2 if music else 1
                    for k, (vp, at) in enumerate(voices):
                        ins += ["-i", vp]
                        ms = int(at * 1000)
                        f += (f"[{first + k}:a]aresample=48000,aformat=channel_layouts=stereo,highpass=f=80,"
                              f"acompressor=threshold=0.1:ratio=3:attack=5:release=120,volume=1.6,adelay={ms}|{ms}[v{k}];")
                        vi.append(f"[v{k}]")
                    f += "".join(vi) + f"amix=inputs={len(vi)}:normalize=0:duration=longest,asplit=3[va][vb][vc];"
                    f += "[g][vb]sidechaincompress=threshold=0.03:ratio=8:attack=15:release=400[gd];"
                    if music:
                        f += "[m0][vc]sidechaincompress=threshold=0.03:ratio=6:attack=20:release=500[md];"
                        f += "[gd][md][va]amix=inputs=3:duration=first:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]"
                    else:
                        f += "[gd][va]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11[a]"
                    run(["ffmpeg", "-v", "error", "-y", *ins, "-filter_complex", f,
                         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out])
                elif music and os.path.exists(music):
                    mix = ("[0:a]volume=1.0[g];[1:a]volume=0.9[m];[g][m]amix=inputs=2:duration=first:normalize=0,"
                           "loudnorm=I=-14:TP=-1.5:LRA=11[a]")
                    run(["ffmpeg", "-v", "error", "-y", "-i", body, "-i", music, "-filter_complex", mix,
                         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out])
                else:
                    run(["ffmpeg", "-v", "error", "-y", "-i", body, "-c", "copy", "-movflags", "+faststart", out])
                made.append(out)
                print(out, flush=True)
    return made


if __name__ == "__main__":
    args = sys.argv[1:]
    only = args[args.index("--only") + 1] if "--only" in args else None
    lang = args[args.index("--lang") + 1] if "--lang" in args else None
    build(args[0], only, lang, "--draft" in args)
