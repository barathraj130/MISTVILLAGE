#!/usr/bin/env python3
"""Still images for social posts, from in-game screenshots: graded, cropped to each format, a dark fade at the
foot with a big line, a smaller line, and the game's name as a small mark at the top. Text is drawn by Godot
(build_trailer.Texts), so Tamil is shaped right.

    posts.py POSTS.json

POSTS.json (paths relative to it):
{
  "out": "out",
  "formats": {"portrait": [1080, 1350], "wide": [1920, 1080]},
  "langs": ["en", "ta"],
  "fonts": {"en": ["Avenir Next Condensed"], "ta": ["Tamil Sangam MN"]},
  "mark": {"en": "THE MIST VILLAGE", "ta": "தி மிஸ்ட் வில்லேஜ்"},
  "posts": [
    {"name": "title", "image": "raw/aerial.jpg" | {"en": ..., "ta": ...}, "crop_x": 0.5, "crop_y": 0.5,
     "grade": "gamma=1.0:saturation=1.1",                 # ffmpeg eq= options
     "cover": [[x, y, w, h], ...],                        # boxes (0..1 of the source) blurred out: a HUD icon
     "precrop": [x, y, w, h],                             # trim the source first (0..1): the story's subtitle box
     "big": {"en": ..., "ta": ...}, "small": {...}, "mark": true, "title": false}
  ]
}
"title": true lays the big line large in the middle (the title card itself). Writes out/<name>_<format>_<lang>.jpg.
"""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_trailer import Texts, run  # noqa: E402


def pick(v, lang):
    return v.get(lang, v.get("en")) if isinstance(v, dict) else v


def main():
    cfg_path = sys.argv[1]
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    base = os.path.dirname(os.path.abspath(cfg_path))
    out = os.path.join(base, cfg.get("out", "out"))
    os.makedirs(out, exist_ok=True)
    fonts = cfg.get("fonts", {"en": ["Avenir Next Condensed"], "ta": ["Tamil Sangam MN"]})
    with tempfile.TemporaryDirectory() as tmp:
        texts = Texts(tmp)
        jobs = []
        for post in cfg["posts"]:
            for fmt, (W, H) in cfg.get("formats", {"portrait": [1080, 1350]}).items():
                for lang in cfg.get("langs", ["en"]):
                    fl = fonts.get(lang, fonts["en"])
                    unit = min(W, H)
                    pngs = []
                    if post.get("title"):
                        size = int(unit * 0.12)
                        pngs.append((texts.add(pick(post["big"], lang), fl, size, W, int(size * 3), "#F5EBD6", True), int(H * 0.36)))
                        if post.get("small"):
                            s2 = int(unit * 0.04)
                            pngs.append((texts.add(pick(post["small"], lang), fl, s2, W, int(s2 * 3), "#E8DFC9", True), int(H * 0.36 + size * 2.6)))
                        if post.get("foot"):
                            s3 = int(unit * 0.034)
                            pngs.append((texts.add(pick(post["foot"], lang), fl, s3, W, int(s3 * 3), "#F2C14E", True), int(H * 0.86)))
                    else:
                        size = int(unit * (0.075 if fmt == "portrait" else 0.068))
                        band = int(size * 4.2)
                        y = int(H * (0.62 if fmt == "portrait" else 0.56))
                        pngs.append((texts.add(pick(post["big"], lang), fl, size, W, band, "#FFFFFF", True), y))
                        if post.get("small"):
                            s2 = int(size * 0.5)
                            pngs.append((texts.add(pick(post["small"], lang), fl, s2, W, int(s2 * 4.2), "#E8DFC9", False), y + band - int(size * 0.5)))
                    if post.get("mark", True) and not post.get("title"):
                        sm = int(unit * 0.03)
                        pngs.append((texts.add(pick(cfg["mark"], lang), fonts.get("mark", fl), sm, W, int(sm * 2.6), "#F5EBD6", True), int(H * 0.03)))
                    jobs.append((post, fmt, W, H, lang, pngs))
        texts.render()
        for post, fmt, W, H, lang, pngs in jobs:
            src = os.path.join(base, pick(post["image"], lang))
            cx = float(post.get("crop_x", 0.5))
            cy = float(post.get("crop_y", 0.5))
            chain = "[0:v]format=rgb24"
            if post.get("precrop"):                       # (trim first: the game's own subtitle box at the foot)
                x, y, w, h = post["precrop"]
                chain += f",crop=iw*{w}:ih*{h}:iw*{x}:ih*{y}"
            for x, y, w, h in post.get("cover", []):     # (blur a small thing out: the phone icon of the HUD)
                chain += (f",split[k][c];[c]crop=iw*{w}:ih*{h}:iw*{x}:ih*{y},boxblur=12:3[cb];"
                          f"[k][cb]overlay=W*{x}:H*{y}")
            chain += (f",eq={post.get('grade', 'saturation=1.08')},scale={W}:{H}:force_original_aspect_ratio=increase:flags=lanczos,"
                      f"crop={W}:{H}:(iw-{W})*{cx}:(ih-{H})*{cy},unsharp=5:5:0.6[bg];")
            fade_from = 0.3 if post.get("title") else (0.45 if fmt == "portrait" else 0.4)
            chain += (f"color=c=black:s={W}x{H},format=rgba,geq=r=0:g=0:b=0:"
                      f"a='255*clip((Y/H-{fade_from})/(1-{fade_from}),0,1)*0.88+255*clip((0.12-Y/H)/0.12,0,1)*0.55'[fd];"
                      "[bg][fd]overlay=0:0[b0]")
            inputs = ["-i", src, "-f", "lavfi", "-i", f"color=c=black:s={W}x{H}"]
            last = "b0"
            for k, (png, y) in enumerate(pngs):
                inputs += ["-i", png]
                chain += f";[{last}][{k + 2}:v]overlay=0:{y}[b{k + 1}]"
                last = f"b{k + 1}"
            dst = os.path.join(out, f"{post['name']}_{fmt}_{lang}.jpg")
            run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", chain, "-map", f"[{last}]",
                 "-frames:v", "1", "-q:v", "2", dst])
            print(dst, flush=True)


if __name__ == "__main__":
    main()
