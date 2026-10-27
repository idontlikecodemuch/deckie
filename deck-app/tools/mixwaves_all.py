#!/usr/bin/env python3
"""Beat-synchronous waveform snippets (mix-out and mix-in windows) for EVERY catalogue track.
Copy of _pool build/mixer/mixwaves.py (same algorithm and output layout), but driven by candidates.json
instead of the 198 page tracks, and writing into the app folder. Cached by id.
  "../../_pool build/mixer/.venv/bin/python" -I mixwaves_all.py [--force] [--seed]
--seed copies already-computed entries from _pool build/mixer/mixwaves.json (read only) to save time."""
import json, os, sys, math
import numpy as np, soundfile as sf
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MIXER = os.path.join(ROOT, "mixer")  # ROOT is the repo
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
LEAD_BARS, MAX_BARS, HEAD_BARS = 8, 32, 64
SPB = 8 if "--spb" not in sys.argv else int(sys.argv[sys.argv.index("--spb") + 1])
# 4 samples per beat = the original web-player format (build/mixwaves_all.json, seeded from the mixer);
# 8 samples per beat (default since Oct 24) for the iPad join view, plus a "head" snippet (track start .. 64 bars)
# so the next song can be shown from any start point; every snippet carries k0 = grid index of its first sample.
OUT = os.path.join(HERE, "build", "mixwaves_all.json" if SPB == 4 else f"mixwaves_spb{SPB}.json")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
cache = json.load(open(OUT)) if os.path.exists(OUT) and "--force" not in sys.argv else {}
cands = json.load(open(os.path.join(MIXER, "candidates.json")))
if SPB == 4 and "--seed" in sys.argv and os.path.exists(os.path.join(MIXER, "mixwaves.json")):
    for k, v in json.load(open(os.path.join(MIXER, "mixwaves.json"))).items():
        cache.setdefault(k, v)

def snippet(mono, sr, bpm, fd, t_a, t_b):
    P = 60.0 / bpm / SPB
    k0 = math.floor((t_a - fd) / P); k1 = math.ceil((t_b - fd) / P)
    vals = []
    for k in range(k0, k1):
        a = int(max(0, (fd + k * P)) * sr); b = int(max(0, (fd + (k + 1) * P)) * sr)
        seg = mono[a:b]
        vals.append(float(np.sqrt(np.mean(seg * seg))) if len(seg) else 0.0)
    mx = max(vals) or 1.0
    return fd + k0 * P, "".join(B64[min(63, int(round(v / mx * 63)))] for v in vals), k0

done = 0
for c in cands:
    tid = c["id"]
    if tid in cache: continue
    fp = os.path.join(MIXER, "features", tid + ".json")
    if not os.path.exists(fp): print("no features", tid); continue
    f = json.load(open(fp)); g = f["grid"]; bpm = g["bpm"]; fd = g["first_downbeat_s"]; bar = 240.0 / bpm
    try:
        y, sr = sf.read(c.get("path") or f["path"], dtype="float32", always_2d=True)
    except Exception as e:
        print("skip", tid, e); continue
    mono = y.mean(axis=1); dur = len(mono) / sr
    mo, mi = f["mix_out"], f["mix_in"]
    o_a = max(0.0, mo["start_s"] - LEAD_BARS * bar); o_b = min(dur, mo["start_s"] + MAX_BARS * bar, mo["end_s"])
    i_a = max(0.0, mi["start_s"]); i_b = min(dur, mi["end_s"] + LEAD_BARS * bar, mi["start_s"] + (MAX_BARS + LEAD_BARS) * bar)
    o_t0, o_s, o_k0 = snippet(mono, sr, bpm, fd, o_a, o_b)
    i_t0, i_s, i_k0 = snippet(mono, sr, bpm, fd, i_a, i_b)
    P = 60.0 / bpm / SPB
    cache[tid] = {"spb": SPB, "bpm": round(bpm, 3),
                  "out": {"t0": round(o_t0, 3), "n": len(o_s), "s": o_s, "win": [int(round((mo["start_s"] - o_t0) / P)), int(round((mo["end_s"] - o_t0) / P))], "beat0": o_k0 // SPB, "k0": o_k0},
                  "in": {"t0": round(i_t0, 3), "n": len(i_s), "s": i_s, "win": [int(round((mi["start_s"] - i_t0) / P)), int(round((mi["end_s"] - i_t0) / P))], "beat0": i_k0 // SPB, "k0": i_k0}}
    if SPB != 4:
        h_t0, h_s, h_k0 = snippet(mono, sr, bpm, fd, 0.0, min(dur, fd + HEAD_BARS * bar))
        cache[tid]["head"] = {"t0": round(h_t0, 3), "n": len(h_s), "s": h_s, "win": [int(round((mi["start_s"] - h_t0) / P)), int(round((mi["end_s"] - h_t0) / P))], "beat0": h_k0 // SPB, "k0": h_k0}
    done += 1
    if done % 20 == 0:
        json.dump(cache, open(OUT, "w")); print(f"{done} done ({tid})", flush=True)
json.dump(cache, open(OUT, "w"))
print(f"mixwaves_all: {len(cache)} tracks ({sum(c['id'] in cache for c in cands)} of {len(cands)} catalogue), {done} computed now, {os.path.getsize(OUT)//1024} KB")
