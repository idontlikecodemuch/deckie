#!/usr/bin/env python3
"""Whole-song overview waveforms for the Listen page: 480 RMS bins per track over the whole file,
normalised to the track's loudest bin, base64 (64 levels). Every catalogue track; cached by id.
  "../../_pool build/mixer/.venv/bin/python" -I overview_waves.py [--force]
Writes Deck/Resources/overview.json {id: {"n", "dur", "s"}}. Only reads the MP3s."""
import json, os, sys
import numpy as np, soundfile as sf
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE); ROOT = os.path.dirname(APP)
MIXER = os.path.join(ROOT, "mixer")  # ROOT is the repo
OUT = os.path.join(APP, "Deck", "Resources", "overview.json")
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
N = 480
cache = json.load(open(OUT)) if os.path.exists(OUT) and "--force" not in sys.argv else {}
cands = json.load(open(os.path.join(MIXER, "candidates.json")))
done = 0
for c in cands:
    if c["id"] in cache: continue
    try:
        y, sr = sf.read(c["path"], dtype="float32", always_2d=True)
    except Exception as e:
        print("skip", c["id"], e); continue
    m = y.mean(axis=1); dur = len(m) / sr
    edges = np.linspace(0, len(m), N + 1).astype(int)
    v = np.array([np.sqrt(np.mean(m[a:b] ** 2)) if b > a else 0 for a, b in zip(edges[:-1], edges[1:])])
    v = v / (v.max() or 1)
    cache[c["id"]] = {"n": N, "dur": round(dur, 2), "s": "".join(B64[min(63, int(round(x * 63)))] for x in v)}
    done += 1
    if done % 25 == 0:
        json.dump(cache, open(OUT, "w"), separators=(",", ":")); print(done, flush=True)
json.dump(cache, open(OUT, "w"), separators=(",", ":"))
print(f"overview.json: {len(cache)} tracks, {done} new, {os.path.getsize(OUT)//1024} KB")
