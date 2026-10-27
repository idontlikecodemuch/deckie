#!/usr/bin/env python3
"""Add a `mix` list to every track in Mike page/data.json + data.js: the on-disc tracks it mixes
into best (from mixer/pairs.json, score >= 0.55, up to 8), with a short label for the player's
"Up next" slots. Run after newfiles/mike_data.py:  .venv/bin/python -I add_mix_to_data.py
"""
import json, os, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PAGE = os.path.join(REPO, "web-player")
LABEL = {"bass_swap_16": "blend", "bass_swap_32": "long blend", "bass_swap_8": "short blend", "ramped_blend": "ramp blend",
         "filter_sweep": "filter out", "quick_blend_echo": "echo out", "brake_cut": "brake/cut"}
MIN, TOP = 0.55, 12

data = json.load(open(os.path.join(PAGE, "data.json")))
tracks = data["tracks"]
on = {t["id"] for t in tracks if t.get("selected")}
pairs = json.load(open(os.path.join(HERE, "pairs.json")))["pairs"]
key = {}
for t in tracks:
    fp = os.path.join(HERE, "features", t["id"] + ".json")
    if os.path.exists(fp):
        key[t["id"]] = json.load(open(fp))["key"]["camelot"]
MW = json.load(open(os.path.join(HERE, "mixwaves.json"))) if os.path.exists(os.path.join(HERE, "mixwaves.json")) else {}
feat = {}
for t in tracks:
    fp = os.path.join(HERE, "features", t["id"] + ".json")
    if os.path.exists(fp):
        feat[t["id"]] = json.load(open(fp))
by = {}
for p in sorted(pairs, key=lambda p: -p["score"]):
    if p["b"] not in on or p["score"] < MIN or p["a"] == p["b"]:
        continue
    L = by.setdefault(p["a"], [])
    if len(L) >= TOP:
        continue
    st = p["stretch_pct"]
    tempo = "same tempo" if st < 1 else f"{st:.0f}% stretch"
    if p["multiplier"] not in ("1",):
        tempo = f"x{p['multiplier']} tempo"
    fa, fb = feat.get(p["a"]), feat.get(p["b"])
    kmul = {"1": 1.0, "1/2": 0.5, "2": 2.0, "2/3": 2 / 3, "3/4": 0.75, "4/3": 4 / 3, "3/2": 1.5}.get(p["multiplier"], 1.0)
    pitch = None
    if fa and fb:
        a_out = (fa.get("local_tempo") or {}).get("bpm_out", fa["bpm"]); b_in = (fb.get("local_tempo") or {}).get("bpm_in", fb["bpm"])
        pitch = round((a_out / (b_in * kmul) - 1) * 100, 1)   # CDJ pitch fader on the incoming deck to match the outgoing
    L.append({"id": p["b"], "s": round(p["score"], 2), "st": st, "m": p["multiplier"], "pitch": pitch, "tr": p["suggested_transition"],
              "trl": " / ".join(LABEL.get(x, x) for x in (p.get("moves") or [p["suggested_transition"]])[:2]),
              "moves": [LABEL.get(x, x) for x in (p.get("moves") or [p["suggested_transition"]])],
              "ka": key.get(p["a"], "?"), "kb": key.get(p["b"], "?"),
              "why": f"{tempo} · {key.get(p['a'], '?')}→{key.get(p['b'], '?')} · {LABEL.get(p['suggested_transition'], p['suggested_transition'])}",
              "reasons": p["reasons"][:5]})
n = 0
for t in tracks:
    t["mix"] = by.get(t["id"], [])
    n += bool(t["mix"])
    f = feat.get(t["id"])
    if f:
        lt = f.get("local_tempo") or {}
        t["mixIn"] = [round(f["mix_in"]["start_s"], 1), round(f["mix_in"]["end_s"], 1)]
        t["mixOut"] = [round(f["mix_out"]["start_s"], 1), round(f["mix_out"]["end_s"], 1)]
        t["bpmIn"] = round(lt.get("bpm_in", f["bpm"]), 1)
        t["bpmOut"] = round(lt.get("bpm_out", f["bpm"]), 1)
        t["bpmM"] = round(f["bpm"], 1)
        t["key"] = f["key"]["camelot"]
        t["keyConf"] = round(f["key"]["confidence"], 2)
        t["inSteady"] = bool(lt.get("in_trusted", True))
        t["outSteady"] = bool(lt.get("out_trusted", True))
        t["fadeOut"] = bool(f.get("fade_out"))
        t["steadyInBar"] = lt.get("steady_in_bar")
        t["dur"] = round(f["duration_s"], 1)
        mw = MW.get(t["id"])
        if mw:
            t["wOut"] = mw["out"]; t["wIn"] = mw["in"]; t["spb"] = mw["spb"]
data["generated"] = datetime.date.today().isoformat()
data["mixNote"] = "mix = best next tracks on the discs, scored on tempo at the ends, key, energy, vocals, phrases and groove"
json.dump(data, open(os.path.join(PAGE, "data.json"), "w"), ensure_ascii=False)
open(os.path.join(PAGE, "data.js"), "w", encoding="utf-8").write("window.MIKE_DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
print(f"{n} of {len(tracks)} tracks got mix lists; on-disc targets {len(on)}; wrote data.json + data.js ({os.path.getsize(os.path.join(PAGE, 'data.js'))} bytes)")
