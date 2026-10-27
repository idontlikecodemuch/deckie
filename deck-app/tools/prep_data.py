#!/usr/bin/env python3
"""Builds everything the Deck app bundles, from the mixer's analysis. Rerun when tracks change.

  PY="../../_pool build/mixer/.venv/bin/python"
  $PY -I prep_data.py                      # JSON + mix map + catalog (variants from VARIANTS below)
  $PY -I prep_data.py --no-catalog         # JSON + mix map only
  $PY -I prep_data.py --variants o,r-4,r+4 # choose the catalog's pitch variants

Steps: (1) mixwaves_all.py (waveform snippets for every catalogue track, cached), (2) Deck/Resources/deck_data.json
(catalogue with display names, disc and track numbers, features summary, snippets, trimmed pairs),
(3) copy mixmap.html, (4) catalogtool sign (cached signatures in build/sigs) + assemble -> Deck/Resources/Deck.shazamcatalog.
Reads only; never touches the MP3s or the files under "_pool build" and "Mike page"."""
import json, os, sys, shutil, subprocess, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ROOT = os.path.dirname(APP)  # the repo
MIXER = os.path.join(ROOT, "mixer")
RES = os.path.join(APP, "Deck", "Resources")
BUILD = os.path.join(HERE, "build")
VARIANTS = "o,r-4,r+4"
for i, a in enumerate(sys.argv):
    if a == "--variants": VARIANTS = sys.argv[i + 1]
os.makedirs(RES, exist_ok=True); os.makedirs(BUILD, exist_ok=True)
PY = sys.executable

# 1. waveform snippets
if "--no-waves" not in sys.argv:
    subprocess.run([PY, "-I", os.path.join(HERE, "mixwaves_all.py"), "--spb", "8"], check=True)   # join-view snippets, 8 per beat
    subprocess.run([PY, "-I", os.path.join(HERE, "overview_waves.py")], check=True)   # whole-song waves -> Resources/overview.json
waves = json.load(open(os.path.join(BUILD, "mixwaves_spb8.json")))

def steady_in_s(f):
    """seconds of the first steady-beat bar (local_tempo.steady_in_bar), None if unknown"""
    b = (f.get("local_tempo") or {}).get("steady_in_bar")
    return None if not b else round(f["grid"]["first_downbeat_s"] + (b - 1) * 240.0 / f["grid"]["bpm"], 2)

def put_waves(t, w, f):
    if w:
        t["wOut"] = w["out"]; t["wIn"] = w["in"]; t["spb"] = w["spb"]
        if "head" in w: t["wHead"] = w["head"]
    if f is not None:
        t["steadyIn"] = steady_in_s(f)
        t["bpmGrid"] = round(f["grid"]["bpm"], 3)

if "--snippets-only" in sys.argv:
    # refresh only the waveform snippets (+ steady-in time) in the existing deck_data.json; selection untouched
    dp = os.path.join(RES, "deck_data.json")
    data = json.load(open(dp))
    for t in data["tracks"]:
        fp = os.path.join(MIXER, "features", t["id"] + ".json")
        put_waves(t, waves.get(t["id"]), json.load(open(fp)) if os.path.exists(fp) else None)
    json.dump(data, open(dp, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"deck_data.json: snippets refreshed for {sum('wHead' in t for t in data['tracks'])} tracks, {os.path.getsize(dp)//1024} KB")
    sys.exit(0)

# 2. catalogue
cands = json.load(open(os.path.join(MIXER, "candidates.json")))
feat = {}
for c in cands:
    fp = os.path.join(MIXER, "features", c["id"] + ".json")
    if os.path.exists(fp): feat[c["id"]] = json.load(open(fp))
DISC = {"S": (1, "CD1 Singalongs"), "M": (2, "CD2 Mix-ins")}
num = {}
discs = []
for d, (cd, name) in DISC.items():
    rows = sorted([c for c in cands if c.get("on_disc") and c.get("disc") == d], key=lambda c: (c["folder"], c["bpm_tag"] or 0, c["title"]))
    folders = []
    for c in rows:
        if not folders or folders[-1]["name"] != c["folder"]: folders.append({"name": c["folder"], "ids": []})
        folders[-1]["ids"].append(c["id"]); num[c["id"]] = (cd, len(folders[-1]["ids"]))
    discs.append({"disc": d, "cd": cd, "name": name, "folders": folders})

def r1(x): return None if x is None else round(float(x), 1)
tracks = []
for c in cands:
    f = feat.get(c["id"]); 
    t = {"id": c["id"], "title": c["title"], "artist": c.get("artist") or "", "song": c.get("song") or c["title"], "ver": c.get("ver") or "",
         "deck": c.get("deck") or c["title"], "on": bool(c.get("on_disc")), "disc": c.get("disc"), "folder": c.get("folder") or "",
         "hal": bool(c.get("hal")), "kind": c.get("kind") or "", "era": c.get("era") or "", "bpmTag": c.get("bpm_tag"),
         "cut": c.get("cut_key") or c["id"], "longest": bool(c.get("is_longest", True)), "secs": c.get("secs")}
    if c["id"] in num: t["cd"], t["num"] = num[c["id"]]
    if f:
        lt = f.get("local_tempo") or {}
        t.update({"bpm": r1(f["bpm"]), "bpmIn": r1(lt.get("bpm_in", f["bpm"])), "bpmOut": r1(lt.get("bpm_out", f["bpm"])),
                  "key": f["key"]["camelot"], "keyConf": round(f["key"]["confidence"], 2), "dur": r1(f["duration_s"]),
                  "mixIn": [r1(f["mix_in"]["start_s"]), r1(f["mix_in"]["end_s"])], "mixOut": [r1(f["mix_out"]["start_s"]), r1(f["mix_out"]["end_s"])],
                  "mixInBars": f["mix_in"]["bars"], "mixOutBars": f["mix_out"]["bars"], "fade": bool(f.get("fade_out")),
                  "firstBeat": round(f["grid"]["first_downbeat_s"], 3)})
    put_waves(t, waves.get(c["id"]), f)
    tracks.append(t)

# pairs: per source, the best 40 on-disc targets plus the best 40 overall (the app samples from these)
LABEL = {"bass_swap_8": "short blend", "bass_swap_16": "blend", "bass_swap_32": "long blend", "ramped_blend": "ramp blend",
         "filter_sweep": "filter out", "quick_blend_echo": "echo out", "brake_cut": "brake/cut"}
KM = {"1": 1.0, "1/2": 0.5, "2": 2.0, "2/3": 2 / 3, "3/4": 0.75, "4/3": 4 / 3, "3/2": 1.5}
on = {c["id"] for c in cands if c.get("on_disc")}
pairs = json.load(open(os.path.join(MIXER, "pairs.json")))["pairs"]
by = {}
for p in sorted(pairs, key=lambda p: -p["score"]):
    if p["a"] == p["b"]: continue
    by.setdefault(p["a"], []).append(p)
out = {}
for a, L in by.items():
    keep = [p for p in L if p["b"] in on][:40]
    ids = {p["b"] for p in keep}
    keep += [p for p in L if p["b"] not in ids][:40]
    keep.sort(key=lambda p: -p["score"])
    fa = feat.get(a); rows = []
    for p in keep:
        fb = feat.get(p["b"]); pitch = None
        if fa and fb:
            ao = (fa.get("local_tempo") or {}).get("bpm_out", fa["bpm"]); bi = (fb.get("local_tempo") or {}).get("bpm_in", fb["bpm"])
            pitch = round((ao / (bi * KM.get(p["multiplier"], 1.0)) - 1) * 100, 1)
        rows.append({"b": p["b"], "s": round(p["score"], 3), "st": round(p["stretch_pct"], 1), "m": p["multiplier"], "pitch": pitch,
                     "tr": p["suggested_transition"], "trl": LABEL.get(p["suggested_transition"], p["suggested_transition"]),
                     "ka": fa["key"]["camelot"] if fa else "?", "kb": fb["key"]["camelot"] if fb else "?",
                     "reasons": p["reasons"][:5], "ks": p.get("key_shift_st", 0),
                     "mv": [LABEL.get(x, x) for x in (p.get("moves") or [p["suggested_transition"]])][:3]})
    out[a] = rows
data = {"generated": datetime.datetime.now().isoformat(timespec="minutes"), "tracks": tracks, "discs": discs, "pairs": out,
        "catalogVariants": VARIANTS.split(",")}
dp = os.path.join(RES, "deck_data.json")
json.dump(data, open(dp, "w"), ensure_ascii=False, separators=(",", ":"))
print(f"deck_data.json: {len(tracks)} tracks ({len(on)} on disc, {sum('wOut' in t for t in tracks)} with snippets), "
      f"{sum(len(v) for v in out.values())} pairs for {len(out)} sources, {os.path.getsize(dp)//1024} KB")

# 3. mix map
shutil.copyfile(os.path.join(MIXER, "mixmap.html"), os.path.join(RES, "mixmap.html"))

# 4. catalog
if "--no-catalog" not in sys.argv:
    man = os.path.join(BUILD, "manifest.json")
    json.dump([{"id": c["id"], "path": c["path"], "title": c["title"], "artist": c.get("artist") or "", "song": c.get("song") or c["title"]} for c in cands], open(man, "w"))
    tool = os.path.join(HERE, "catalogtool", "catalogtool")
    if not os.path.exists(tool) or os.path.getmtime(tool) < os.path.getmtime(os.path.join(HERE, "catalogtool", "main.swift")):
        subprocess.run(["swiftc", "-O", "-parse-as-library", os.path.join(HERE, "catalogtool", "main.swift"), "-o", tool], check=True)
    sig = os.path.join(BUILD, "sigs")
    procs = [subprocess.Popen([tool, "sign", "--manifest", man, "--sigdir", sig, "--variants", VARIANTS, "--shard", f"{k}/8"], stdout=subprocess.DEVNULL) for k in range(8)]
    for p in procs: p.wait()
    subprocess.run([tool, "assemble", "--manifest", man, "--sigdir", sig, "--variants", VARIANTS, "--out", os.path.join(RES, "Deck.shazamcatalog")], check=True)
