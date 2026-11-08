#!/usr/bin/env python3
"""An original trailer score, synthesised here (nothing downloaded or licensed), timed to the edit.

    score.py EDIT.json OUT.wav

A groove trailer score: a tanpura-style drone on Sa and Pa, a laid-back beat (kick, a snare with a room tail,
hats), a sub-bass line walking a minor progression, veena-like plucked lines from a Sivaranjani-like scale (the
scale Tamil film reaches for in loss and longing), thavil-style drum fills into the cuts the edit marks, a deep
boom on the title, and silence before it.

The edit's segments set the timeline. Each may say:
  "music": "calm"   drone and plucks only
           "build"  + kick, bass, hats
           "tense"  + snare, the full groove, faster plucks
           "quiet"  near silence (the breath before the title)
           "hit"    a boom, then the groove back under the end card
  "hit": true       a boom on its first frame
  "fill": true      a drum fill in the half second before it
The edit's "bpm" (default 94) sets the tempo. The score lasts exactly as long as the edit.
"""
import json
import sys
import wave

import numpy as np

SR = 48000
SA = 138.6                                 # C#3
SCALE = [0, 2, 3, 7, 9, 12, 14, 15, 19]    # Sa Ri2 Ga2 Pa Dha2 (Sivaranjani-like)
PROG = [0, -4, 3, -2]                      # i, VI, III, VII under Sa: a minor, cinematic loop (semitones from Sa)
RNG = np.random.default_rng(2026)


def hz(semi, base=SA):
    return base * 2 ** (semi / 12)


def env_exp(n, k):
    return np.exp(-np.arange(n) / SR * k)


def kick(n):
    t = np.arange(n) / SR
    f = 45 + 120 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * 1.0


def snare(n):
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.5
    noise = RNG.normal(0, 1, n) * (np.exp(-t * 18) * 0.5 + np.exp(-t * 4) * 0.06)   # the room's tail
    return body + np.convolve(noise, [0.5, 0.5], mode="same")


def hat(n):
    noise = RNG.normal(0, 1, n)
    hp = noise - np.convolve(noise, np.ones(4) / 4, mode="same")
    return hp * env_exp(n, 60) * 0.25


def thavil(n, pitch):
    """A thavil stroke: a tight, high, ringing skin."""
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * pitch * t) + 0.4 * np.sin(2 * np.pi * pitch * 2.3 * t)) * np.exp(-t * 22) * 0.6


def pluck(n, f, amp):
    """Karplus-Strong, vectorised by period: a plucked string, veena-ish."""
    p = max(2, int(SR / f))
    buf = RNG.uniform(-1, 1, p)
    out = np.empty(n)
    i = 0
    while i < n:
        k = min(p, n - i)
        out[i:i + k] = buf[:k]
        buf = 0.5 * (buf + np.roll(buf, -1)) * 0.995
        i += p
    return out * amp


def drone(t):
    out = np.zeros_like(t)
    period = 1.25
    for k, f in enumerate([hz(7, SA / 2), SA, SA, SA / 2]):
        ph = np.mod(t - k * period / 4, period)
        e = np.exp(-ph * 1.1) * 0.7 + 0.3
        tone = sum(np.sin(2 * np.pi * f * h * t + h) / h ** 0.85 for h in range(1, 10))
        out += tone * e
    return out * 0.09


def bass(t, beat, bar_len):
    """Sub bass on the progression: the root on beats 1 and 3, a fifth pushed on the "and" of 4."""
    out = np.zeros_like(t)
    bar = (t // bar_len).astype(int)
    root = np.array([hz(PROG[b % 4], SA / 2) for b in range(int(bar.max()) + 2)])
    f = root[bar]
    pos = np.mod(t, bar_len) / beat                      # beats into the bar
    gate = np.zeros_like(t)
    for start, ln in [(0, 1.6), (2, 1.2), (3.5, 0.45)]:
        inside = (pos >= start) & (pos < start + ln)
        gate = np.maximum(gate, inside * np.exp(-(pos - start) * 0.9))
    f = np.where((pos >= 3.5), f * 1.5, f)
    phase = np.cumsum(f) / SR
    tone = np.sin(2 * np.pi * phase) + 0.25 * np.sin(4 * np.pi * phase)
    return tone * gate * 0.45


def main():
    edit = json.load(open(sys.argv[1], encoding="utf-8"))
    segs = edit["segments"]
    bpm = float(edit.get("bpm", 94))
    beat = 60.0 / bpm
    bar_len = beat * 4
    total = sum(float(s["dur"]) for s in segs)
    n = int(total * SR)
    t = np.arange(n) / SR
    lv = {"calm": 0, "build": 1, "tense": 2, "quiet": -1, "hit": 1}
    level = np.zeros(n, dtype=int)
    marks, fills = [], []
    at = 0.0
    for s in segs:
        a, b = int(at * SR), int((at + float(s["dur"])) * SR)
        level[a:b] = lv.get(s.get("music", "build"), 1)
        if s.get("hit") or s.get("music") == "hit":
            marks.append(a)
        if s.get("fill"):
            fills.append(a)
        at += float(s["dur"])
    quiet = (level < 0).astype(float)
    k = int(SR * 0.25)
    quiet = np.convolve(quiet, np.ones(k) / k, mode="same")
    mix = drone(t) * (1.0 - 0.6 * (level >= 2))
    groove = (level >= 1).astype(float)
    full = (level >= 2).astype(float)
    k2 = int(SR * 0.08)
    groove = np.convolve(groove, np.ones(k2) / k2, mode="same")
    full = np.convolve(full, np.ones(k2) / k2, mode="same")
    mix += bass(t, beat, bar_len) * groove
    # the beat, on a grid of sixteenths
    six = beat / 4
    steps = int(total / six)
    for i in range(steps):
        a = int(i * six * SR)
        if a >= n:
            break
        lvl = level[a]
        if lvl < 1:
            continue
        pos = i % 16
        ln = min(int(SR * 0.6), n - a)
        if pos in (0, 7, 10) and not (pos == 7 and lvl < 2):
            mix[a:a + ln] += kick(ln) * 0.7
        if lvl >= 2 and pos in (4, 12):
            mix[a:a + ln] += snare(ln) * 0.55
        if pos % 2 == 0 or lvl >= 2:
            mix[a:a + min(int(SR * 0.08), n - a)] += hat(min(int(SR * 0.08), n - a)) * (0.7 if pos % 4 == 2 else 0.4)
    # plucked lines, on the beat grid: sparser when calm, a run of sixteenths when tense
    i = 0
    while i < steps:
        a = int(i * six * SR)
        if a >= n:
            break
        lvl = level[a]
        every = {0: 4, 1: 2, 2: 1}.get(lvl, 0)
        if every and RNG.random() < (0.55 if lvl < 2 else 0.7):
            bar = int((i * six) // bar_len)
            note = SCALE[RNG.integers(len(SCALE))] + 12
            ln = min(int(SR * 1.4), n - a)
            mix[a:a + ln] += pluck(ln, hz(note + (PROG[bar % 4] if RNG.random() < 0.4 else 0)), 0.38 if lvl == 0 else 0.26)
        i += max(1, every)
    # thavil fills into marked cuts: a run of strokes over the half second before
    for f0 in fills:
        for j in range(8):
            a = f0 - int(SR * (0.5 - j * 0.0625))
            if 0 <= a < n:
                ln = min(int(SR * 0.2), n - a)
                mix[a:a + ln] += thavil(ln, 330 + 60 * (j % 3)) * (0.5 + j * 0.06)
    for a in marks:
        ln = min(int(SR * 3.5), n - a)
        tt = np.arange(ln) / SR
        f = 28 + 80 * np.exp(-tt * 7)
        mix[a:a + ln] += (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 1.8)
                          + RNG.normal(0, 1, ln) * np.exp(-tt * 10) * 0.35) * 1.2
    mix *= 1.0 - 0.92 * quiet
    fade = int(SR * 1.0)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    mix = np.tanh(mix * 1.4) / np.tanh(1.4)               # glue: a soft clip, like a bus compressor
    mix /= max(1e-6, np.max(np.abs(mix))) / 0.9
    data = (np.stack([mix, np.roll(mix, int(SR * 0.011))], axis=1) * 32767).astype(np.int16)
    with wave.open(sys.argv[2], "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{sys.argv[2]}: {total:.1f} s at {bpm:.0f} bpm, {len(marks)} hits, {len(fills)} fills")


if __name__ == "__main__":
    main()
