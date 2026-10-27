#!/usr/bin/env python3
"""Stage 1 benchmark: Apple's Music Understanding (raw SessionResult JSON from tools/mubench, in mu_raw/) against
the lab features (features/<id>.json). Run with the lab venv:  .venv/bin/python -I bench_mu.py [--ids a,b] [--tsv out]
Metrics follow docs/architecture/analysis-port-plan.md section 3: beat and downbeat F-measure at 70 ms (plus the
octave and half-tempo variants), BPM ratio, key agreement split by the lab's key confidence, per-bar vocal
correlation, section boundary precision/recall within one bar, loudness deltas, seconds per track."""
import json, os, sys, bisect, math, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "mu_raw"); FEAT = os.path.join(HERE, "features")
TOL = 0.07
CAMELOT = {("major", k): v for k, v in zip(["c", "dFlat", "d", "eFlat", "e", "f", "gFlat", "g", "aFlat", "a", "bFlat", "b"], ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"])}
CAMELOT.update({("minor", k): v for k, v in zip(["c", "dFlat", "d", "eFlat", "e", "f", "gFlat", "g", "aFlat", "a", "bFlat", "b"], ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"])})
ENH = {"cSharp": "dFlat", "dSharp": "eFlat", "fSharp": "gFlat", "gSharp": "aFlat", "aSharp": "bFlat"}

def secs(ct): return ct["value"] / ct["timescale"] if ct.get("timescale") else float("nan")
def num(v):
    """the harness writes non-finite floats as strings"""
    return float(v) if isinstance(v, str) else v
def camelot(sig): return CAMELOT.get((sig["mode"], ENH.get(sig["tonic"], sig["tonic"])), "?")

def fmeasure(ref, est, tol=TOL):
    ref = sorted(ref); est = sorted(est)
    if not ref or not est: return None
    hits, used = 0, set()
    for x in est:
        i = bisect.bisect_left(ref, x)
        for j in (i - 1, i):
            if 0 <= j < len(ref) and j not in used and abs(ref[j] - x) <= tol: hits += 1; used.add(j); break
    p, r = hits / len(est), hits / len(ref)
    return 2 * p * r / (p + r) if p + r else 0.0

def key_relation(a, b):
    """exact / neighbour (same number other letter, or +-1 same letter) / relative counted as neighbour / other"""
    if a == b: return "exact"
    try: na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    except Exception: return "other"
    if na == nb and la != lb: return "neighbour"
    if la == lb and (na - nb) % 12 in (1, 11): return "neighbour"
    return "other"

def boundary_pr(ref_s, est_s, tol_s):
    if not ref_s or not est_s: return (None, None)
    hit_e = sum(1 for e in est_s if any(abs(e - r) <= tol_s for r in ref_s))
    hit_r = sum(1 for r in ref_s if any(abs(e - r) <= tol_s for e in est_s))
    return (hit_e / len(est_s), hit_r / len(ref_s))

def pearson(x, y):
    n = len(x)
    if n < 3: return None
    mx, my = sum(x) / n, sum(y) / n
    sx = math.sqrt(sum((a - mx) ** 2 for a in x)); sy = math.sqrt(sum((b - my) ** 2 for b in y))
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / (sx * sy) if sx and sy else None

def one(tid):
    r = json.load(open(os.path.join(RAW, tid + ".mu.json"))); f = json.load(open(os.path.join(FEAT, tid + ".json")))
    out = {"id": tid, "title": f.get("title", "")[:40]}
    rh = r.get("rhythm") or {}
    beats = [secs(b) for b in rh.get("beats", [])]; bars = [secs(b) for b in rh.get("bars", [])]
    lab_b = f.get("detected_beats_s") or []; lab_g = f.get("beats_s") or []
    lab_db = f.get("detected_downbeats_s") or []; lab_gd = f.get("downbeats_s") or []
    out["beat_f"] = fmeasure(lab_b, beats); out["beat_f_grid"] = fmeasure(lab_g, beats)
    out["beat_f_best_octave"] = max(x for x in [out["beat_f"] or 0, fmeasure(lab_b, beats[::2]) or 0, fmeasure(lab_b[::2], beats) or 0])
    out["downbeat_f"] = fmeasure(lab_db, bars); out["downbeat_f_grid"] = fmeasure(lab_gd, bars)
    out["bpm_mu"] = rh.get("beatsPerMinute"); out["bpm_lab"] = f.get("bpm")
    out["bpm_ratio"] = (out["bpm_mu"] / out["bpm_lab"]) if out["bpm_mu"] and out["bpm_lab"] else None
    k = r.get("key") or {}; rngs = k.get("ranges") or []
    if rngs:
        # the key covering most of the track
        best = max(rngs, key=lambda x: secs(x["range"]["duration"]))
        out["key_mu"] = camelot(best["value"]); out["key_ranges"] = len(rngs)
    else: out["key_mu"] = "?"; out["key_ranges"] = 0
    out["key_lab"] = f["key"]["camelot"]; out["key_conf_lab"] = f["key"]["confidence"]
    out["key_rel"] = key_relation(out["key_mu"], out["key_lab"])
    lo = r.get("loudness") or {}
    out["lufs_mu"] = num((lo.get("integrated") or {}).get("value")); out["lufs_lab"] = f["loudness"]["integrated_lufs"]
    out["lufs_delta"] = (out["lufs_mu"] - out["lufs_lab"]) if out["lufs_mu"] is not None and math.isfinite(out["lufs_mu"]) else None
    out["peak_mu"] = num((lo.get("peak") or {}).get("value")); out["peak_lab"] = f["loudness"].get("true_peak_db")
    # per-bar vocal: average MU vocal activity inside each lab bar
    ia = (r.get("instrumentActivity") or {}).get("activity") or {}
    voc = [(secs(t["time"]), num(t["value"])) for t in ia.get("vocal", [])]
    labv = (f.get("per_bar") or {}).get("vocal_prob") or []
    if voc and labv and lab_gd:
        times = [t for t, _ in voc]; xs, ys = [], []
        bar_s = f["grid"]["bar_s"]
        for i, v in enumerate(labv):
            t0 = lab_gd[0] + i * bar_s if i >= len(lab_gd) else lab_gd[i]; t1 = t0 + bar_s
            a, b = bisect.bisect_left(times, t0), bisect.bisect_left(times, t1)
            if b > a: xs.append(sum(val for _, val in voc[a:b]) / (b - a)); ys.append(v)
        out["vocal_r"] = pearson(xs, ys); out["vocal_mean_mu"] = sum(xs) / len(xs) if xs else None; out["vocal_mean_lab"] = f["vocal"]["mean_prob"]
    else: out["vocal_r"] = None; out["vocal_mean_mu"] = None; out["vocal_mean_lab"] = f["vocal"]["mean_prob"]
    # sections: MU section starts vs lab boundaries (bars -> seconds), within one bar
    stt = r.get("structure") or {}
    mu_sec = [secs(s["start"]) for s in stt.get("sections", [])]
    bar_s = f["grid"]["bar_s"]; fd = f["grid"]["first_downbeat_s"]
    lab_bd = [fd + (b - 1) * bar_s for b in (f.get("boundaries_bars") or []) if 1 < b < f["grid"]["n_bars"]]
    out["section_p"], out["section_r"] = boundary_pr(lab_bd, [s for s in mu_sec if s > 1.0], bar_s)
    out["n_sections_mu"] = len(mu_sec); out["n_boundaries_lab"] = len(lab_bd); out["n_phrases_mu"] = len(stt.get("phrases", []))
    # octave: when MU and the lab disagree by a factor of two, which one agrees with the file's tempo tag?
    tag = f.get("bpm_tag")
    out["bpm_tag"] = tag
    if out["bpm_ratio"] and tag and (abs(out["bpm_ratio"] - 2) < 0.06 or abs(out["bpm_ratio"] - 0.5) < 0.015):
        out["octave_sides_with_tag"] = "mu" if abs(out["bpm_mu"] / tag - 1) < 0.03 else ("lab" if abs(out["bpm_lab"] / tag - 1) < 0.03 else "neither")
    else: out["octave_sides_with_tag"] = ""
    # downbeat phase: if MU bars miss the lab downbeats, do they land on beat 3 (half-bar shift) or elsewhere?
    if bars and lab_gd and out["downbeat_f_grid"] is not None and out["downbeat_f_grid"] < 0.8:
        half = f["grid"]["bar_s"] / 2
        out["downbeat_f_halfbar"] = fmeasure([d + half for d in lab_gd], bars)
    else: out["downbeat_f_halfbar"] = None
    out["secs_mu"] = None
    return out

def main():
    ids = None
    if "--ids" in sys.argv: ids = sys.argv[sys.argv.index("--ids") + 1].split(",")
    run = json.load(open(os.path.join(RAW, "run.json"))) if os.path.exists(os.path.join(RAW, "run.json")) else {}
    timing = {j["id"]: j.get("secs") for j in run.get("jobs", []) if j.get("ok")}
    have = sorted(fn[:-8] for fn in os.listdir(RAW) if fn.endswith(".mu.json")) if os.path.isdir(RAW) else []
    if ids: have = [i for i in have if i in ids]
    rows = []
    for tid in have:
        if not os.path.exists(os.path.join(FEAT, tid + ".json")): continue
        try: row = one(tid); row["secs_mu"] = timing.get(tid); rows.append(row)
        except Exception as e: print("skip", tid, e, file=sys.stderr)
    if not rows: print("no results yet in", RAW); return
    def med(key, cond=lambda r: True):
        v = [r[key] for r in rows if cond(r) and r.get(key) is not None]
        return (st.median(v), len(v)) if v else (None, 0)
    def share(key, pred):
        v = [r for r in rows if r.get(key) is not None]; return (sum(1 for r in v if pred(r[key])) / len(v), len(v)) if v else (None, 0)
    print(f"Music Understanding vs lab features: {len(rows)} tracks")
    for label, key in [("beat F@70ms vs detected", "beat_f"), ("beat F@70ms vs grid", "beat_f_grid"), ("beat F best octave", "beat_f_best_octave"), ("downbeat F@70ms vs detected", "downbeat_f"), ("downbeat F@70ms vs grid", "downbeat_f_grid")]:
        m, n = med(key); lo = share(key, lambda x: x < 0.8)
        print(f"  {label:32} median {m:.3f}  (<0.8 in {lo[0]*100:.0f}% of {n})" if m is not None else f"  {label}: n/a")
    m, n = med("bpm_ratio"); near = share("bpm_ratio", lambda x: abs(x - 1) < 0.02); oct_ = share("bpm_ratio", lambda x: abs(x - 2) < 0.04 or abs(x - 0.5) < 0.01)
    print(f"  bpm: within 2% of lab in {near[0]*100:.0f}% of {n}; octave off in {oct_[0]*100:.0f}%")
    for conf, cond in [("lab key conf >= 0.65", lambda r: r["key_conf_lab"] >= 0.65), ("lab key conf < 0.65", lambda r: r["key_conf_lab"] < 0.65)]:
        sub = [r for r in rows if cond(r)]
        if sub:
            c = {k: sum(1 for r in sub if r["key_rel"] == k) for k in ("exact", "neighbour", "other")}
            print(f"  key ({conf}, n={len(sub)}): exact {c['exact']/len(sub)*100:.0f}%  neighbour {c['neighbour']/len(sub)*100:.0f}%  other {c['other']/len(sub)*100:.0f}%; MU key changes/track median {st.median([r['key_ranges'] for r in sub])}")
    m, n = med("lufs_delta"); print(f"  loudness delta MU-lab: median {m:+.2f} LU over {n}; |delta|>1 LU in {share('lufs_delta', lambda x: abs(x) > 1)[0]*100:.0f}%")
    m, n = med("vocal_r"); print(f"  per-bar vocal correlation: median r {m:.2f} over {n}; MU vocal mean {med('vocal_mean_mu')[0]:.2f} vs lab {med('vocal_mean_lab')[0]:.2f}")
    p, _ = med("section_p"); rr, n = med("section_r"); print(f"  sections vs lab boundaries (within 1 bar): precision median {p:.2f}, recall median {rr:.2f} over {n}; MU sections/track median {med('n_sections_mu')[0]:.0f}, phrases {med('n_phrases_mu')[0]:.0f}")
    oc = [r for r in rows if r.get("octave_sides_with_tag")]
    if oc:
        c = {k: sum(1 for r in oc if r["octave_sides_with_tag"] == k) for k in ("mu", "lab", "neither")}
        print(f"  octave disagreements ({len(oc)}): the tag sides with MU in {c['mu']}, with the lab in {c['lab']}, with neither in {c['neither']}")
    hb = [r for r in rows if r.get("downbeat_f_halfbar") is not None]
    if hb:
        fixed = sum(1 for r in hb if r["downbeat_f_halfbar"] >= 0.8)
        print(f"  downbeat disagreements vs the lab grid ({len(hb)}): {fixed} are a half-bar phase shift (MU bars on the lab's beat 3), {len(hb) - fixed} are something else")
    m, n = med("secs_mu")
    if m is not None: print(f"  seconds per track in the simulator: median {m:.1f} over {n}")
    if "--tsv" in sys.argv:
        p = sys.argv[sys.argv.index("--tsv") + 1]; keys = list(rows[0].keys())
        with open(p, "w") as fh:
            fh.write("\t".join(keys) + "\n")
            for r in rows: fh.write("\t".join("" if r.get(k) is None else (f"{r[k]:.4f}" if isinstance(r[k], float) else str(r[k])) for k in keys) + "\n")
        print("wrote", p)

if __name__ == "__main__": main()
