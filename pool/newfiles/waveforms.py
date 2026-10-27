#!/usr/bin/env python3
"""Precompute a 180-bin peak waveform per track in Mike page/data.json -> newfiles/waves.json (cached by track id).
Each waveform is a 180-char string, one base64 char (0-63) per bin."""
import json, os, shutil, subprocess, sys, tempfile, array
SP = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); ROOT = "/Users/christophershannon/personal/90s2000 playlist"
D = json.load(open(os.path.join(ROOT, "Mike page", "data.json"))); cache_p = os.path.join(SP, "newfiles", "waves.json")
cache = json.load(open(cache_p)) if os.path.exists(cache_p) else {}
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; BINS = 180; SR = 8000
ff = shutil.which("ffmpeg")
def pcm(path):
    if ff:
        p = subprocess.run([ff, "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"], capture_output=True); return p.stdout
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "x.wav"); subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@%d" % SR, "-c", "1", path, wav], check=True, capture_output=True)
        return open(wav, "rb").read()[44:]
try: import numpy as np
except ImportError: np = None
def bins(raw):
    if np is not None:
        a = np.frombuffer(raw[: len(raw) // 2 * 2], dtype=np.int16).astype(np.float32); step = max(1, len(a) // BINS)
        a = a[: step * BINS].reshape(BINS, step); rms = np.sqrt((a * a).mean(axis=1)); mx = float(rms.max()) or 1.0
        return [float(x) / mx for x in rms]
    a = array.array("h"); a.frombytes(raw[: len(raw) // 2 * 2]); step = max(1, len(a) // BINS); out = []
    for i in range(BINS):
        seg = a[i * step:(i + 1) * step]; out.append((sum(x * x for x in seg) / max(1, len(seg))) ** 0.5)
    mx = max(out) or 1; return [x / mx for x in out]
done = 0
for t in D["tracks"]:
    if t["id"] in cache: continue
    vals = bins(pcm(os.path.join(ROOT, "Mike page", t["path"])))
    cache[t["id"]] = "".join(B64[min(63, int((v ** 0.7) * 63.999))] for v in vals); done += 1
    if done % 25 == 0: print(done, "..."); json.dump(cache, open(cache_p, "w"))
json.dump(cache, open(cache_p, "w")); print("waveforms:", len(cache), "computed now:", done)
