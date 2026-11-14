#!/usr/bin/env python3
"""How loud the benchmark's noise is inside the band the fingerprint reads, against the full-band level it is set by.

  band_levels.py DATA WORK [clips]

The benchmark sets "crowd at 0 dB" so that music and noise have equal power over the whole band (to 8 kHz at the
16 kHz the clips are made at). The fingerprint reads 300 to 3600 Hz. Music keeps much of its power under 300 Hz (bass,
kick); a crowd or pink noise keeps less there. So inside the fingerprint's band the music stands lower against the
noise than the nominal figure says. This measures by how much, on clips drawn like the benchmark's (music through a
measured room; crowd or pink noise), and prints the in-band level for each nominal level.
"""
import os, random, subprocess, sys
import numpy as np
from scipy import signal
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_queries as mq

data, work = sys.argv[1], sys.argv[2]
count = int(sys.argv[3]) if len(sys.argv) > 3 else 200
rng = np.random.default_rng(5)
songs = [l.rstrip("\n").split("\t") for l in open(os.path.join(work, "songs.tsv"))]
random.seed(5)
sos = signal.butter(4, [300, 3600], "bandpass", fs=mq.SR, output="sos")


def power(x):
    return float(np.mean(x * x) + 1e-20)


rows = {"crowd": [], "pink": []}
by_bucket = {}
n = int(12 * mq.SR)
for sid, path, bucket, sec, role in random.sample(songs, count):
    start = random.uniform(5, max(6, float(sec) - 20))
    raw = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-ss", f"{start:.2f}", "-t", "12", "-i", path, "-ac", "1", "-ar", str(mq.SR),
                          "-f", "f32le", "-"], capture_output=True).stdout
    x = np.frombuffer(raw, dtype="<f4")
    if len(x) < n // 2:
        continue
    x, _ = mq.room(x.astype(np.float32), data, rng)
    music = 10 * np.log10(power(signal.sosfilt(sos, x)) / power(x))      # in-band share of the music, dB
    for kind in rows:
        noise = mq.crowd(len(x), data, rng) if kind == "crowd" else mq.pink(len(x), rng)
        share = 10 * np.log10(power(signal.sosfilt(sos, noise)) / power(noise))
        rows[kind].append(music - share)                                   # in-band SNR minus full-band SNR
        by_bucket.setdefault((bucket, kind), []).append(music - share)
print("| noise | clips | in-band level minus nominal level, dB: median (10th to 90th percentile) | nominal +10 / +5 / 0 / -5 dB is, in band |")
print("|---|---|---|---|")
for kind, v in rows.items():
    v = np.array(v); m = float(np.median(v))
    print(f"| {kind} | {len(v)} | {m:+.1f} ({np.quantile(v, 0.1):+.1f} to {np.quantile(v, 0.9):+.1f}) | " + " / ".join(f"{s + m:+.0f}" for s in (10, 5, 0, -5)) + " |")
print()
for (bucket, kind), v in sorted(by_bucket.items()):
    print(f"{bucket}, {kind}: median {np.median(v):+.1f} dB over {len(v)} clips")
