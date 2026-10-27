#!/usr/bin/env python3
"""Beat-synchronous waveform snippets of each track's mix-out and mix-in windows for the player's
join view. Four RMS samples per beat on the track's fitted grid, so bars line up when two tracks
are drawn over each other. Output: mixwaves.json {id: {spb, out:{t0,n,s,win:[i0,i1],bar0}, in:{...}}}
Cached by id; rerun after new tracks are analysed.  .venv/bin/python -I mixwaves.py [--force]"""
import json, os, sys, math
import numpy as np, soundfile as sf
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SPB, LEAD_BARS, MAX_BARS = 4, 8, 32
OUT = os.path.join(HERE, "mixwaves.json")
cache = json.load(open(OUT)) if os.path.exists(OUT) and "--force" not in sys.argv else {}
pd = json.load(open(os.path.join(ROOT, "Mike page", "data.json")))
tracks = pd["tracks"] if isinstance(pd, dict) else pd
cands = {c["id"]: c for c in json.load(open(os.path.join(HERE, "candidates.json")))}

def snippet(mono, sr, bpm, fd, t_a, t_b):
    """RMS per quarter-beat on the grid between t_a and t_b (inclusive of partial edges)."""
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
for t in tracks:
    tid = t["id"]
    if tid in cache: continue
    fp = os.path.join(HERE, "features", tid + ".json")
    if not os.path.exists(fp): continue
    f = json.load(open(fp)); g = f["grid"]; bpm = g["bpm"]; fd = g["first_downbeat_s"]; bar = 240.0 / bpm
    path = cands.get(tid, {}).get("path") or f["path"]
    try:
        y, sr = sf.read(path, dtype="float32", always_2d=True)
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
                  "out": {"t0": round(o_t0, 3), "n": len(o_s), "s": o_s, "win": [int(round((mo["start_s"] - o_t0) / P)), int(round((mo["end_s"] - o_t0) / P))], "beat0": o_k0 // SPB},
                  "in": {"t0": round(i_t0, 3), "n": len(i_s), "s": i_s, "win": [int(round((mi["start_s"] - i_t0) / P)), int(round((mi["end_s"] - i_t0) / P))], "beat0": i_k0 // SPB}}
    done += 1
    if done % 20 == 0:
        json.dump(cache, open(OUT, "w")); print(f"{done} done ({tid} out {len(o_s)} in {len(i_s)})", flush=True)
json.dump(cache, open(OUT, "w"))
print(f"mixwaves: {len(cache)} tracks, {done} computed now, file {os.path.getsize(OUT)//1024} KB")
