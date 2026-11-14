#!/usr/bin/env python3
"""Prints what the benchmark's material is: each source, its licence and its size (Markdown).

  summarise_songs.py DATA WORK
"""
import collections, glob, json, os, sys

data, work = sys.argv[1], sys.argv[2]
songs = [l.rstrip("\n").split("\t") for l in open(os.path.join(work, "songs.tsv"))]
print("### Songs used\n")
print("| bucket | songs | hours | median length | dev / eval / absent |\n|---|---|---|---|---|")
for b in ("dance", "other", "gsplus", "library"):
    s = [x for x in songs if x[2] == b]
    if not s:
        continue
    secs = sorted(float(x[3]) for x in s)
    roles = collections.Counter(x[4] for x in s)
    print(f"| {b} | {len(s)} | {sum(secs) / 3600:.1f} | {secs[len(secs) // 2] / 60:.1f} min | {roles['dev']} / {roles['eval']} / {roles['absent']} |")
print("\n### Licences of the Internet Archive songs (as each release states)\n")
lic = collections.Counter(); size = 0
for b in ("dance", "other"):
    p = os.path.join(data, f"songs_{b}.json")
    if os.path.exists(p):
        for g in json.load(open(p)):
            parts = g["licence"].rstrip("/").split("/")
            name = "CC " + parts[4].upper() + " " + parts[5] if "licenses" in parts and len(parts) > 5 else ("CC0 / public domain" if "publicdomain" in g["licence"] else g["licence"])
            lic[name] += 1; size += g["bytes"]
print("| licence | songs |\n|---|---|")
for k, v in sorted(lic.items(), key=lambda kv: -kv[1]):
    print(f"| {k} | {v} |")
print(f"\nInternet Archive songs: {size / 1e9:.2f} GB of MP3.")
for name, pattern in [("GiantSteps+ audio", "gsplus/**/*.mp3"), ("room impulse responses (OpenSLR 28, real rooms)", "rir/**/*.wav"), ("noise (DEMAND, three places, 16 kHz)", "noise/*/*.wav")]:
    files = glob.glob(os.path.join(data, pattern), recursive=True)
    print(f"{name}: {len(files)} files, {sum(os.path.getsize(f) for f in files) / 1e9:.2f} GB.")
