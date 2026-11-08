#!/usr/bin/env python3
"""Scratch narration: each section of a narration script read by the Mac's own voices, so a narrated cut can be
timed and checked before the real voice is recorded (build_trailer.py uses vo/<id>_<lang>.* first, these after).

    scratch_vo.py NARRATION.md OUT_DIR [--en Rishi] [--ta Vani] [--rate 160]

The script's sections are "## 03 · Title" headings, each with "**EN:** ..." and "**TA:** ..." paragraphs.
Writes OUT_DIR/03_en.aiff, OUT_DIR/03_ta.aiff, ... (macOS `say`; the voices are the system's, nothing downloaded).
"""
import os
import re
import subprocess
import sys


def sections(md):
    out = {}
    sid = None
    lang = None
    for line in open(md, encoding="utf-8"):
        h = re.match(r"^##\s+(\d+)\s", line)
        if h:
            sid, lang = h.group(1), None
            out[sid] = {}
            continue
        m = re.match(r"^\*\*(EN|TA):\*\*\s*(.*)", line)
        if m and sid:
            lang = m.group(1).lower()
            out[sid][lang] = m.group(2).strip()
            continue
        if line.strip() == "" or line.startswith("#"):
            lang = None
        elif lang and sid:
            out[sid][lang] += " " + line.strip()
    return out


def main():
    args = sys.argv[1:]
    md, outdir = args[0], args[1]
    voice = {"en": "Rishi", "ta": "Vani"}
    rate = "160"
    for flag in ("--en", "--ta"):
        if flag in args:
            voice[flag[2:]] = args[args.index(flag) + 1]
    if "--rate" in args:
        rate = args[args.index("--rate") + 1]
    os.makedirs(outdir, exist_ok=True)
    for sid, langs in sections(md).items():
        for lang, text in langs.items():
            out = os.path.join(outdir, f"{sid}_{lang}.aiff")
            subprocess.run(["say", "-v", voice[lang], "-r", rate, "-o", out, text], check=True)
            print(out)


if __name__ == "__main__":
    main()
