#!/usr/bin/env python3
"""Research R, mode test: after row 3f (key_parity.recommended) picks the home note (tonic), decide major versus minor
by a separate, parameter-free rule on the pitch-class profile, and score it on the outside set (GiantSteps-MTG-key,
the Beatport EDM Key Dataset, Zenodo 10.5281/zenodo.1101082, CC BY-SA 4.0 annotations; audio third-party, internal
evaluation only, never committed).

  .venv/bin/python key_mode.py extract --data <folder with audio/ and the xlsx> [--jobs 2]   decode once, cache
  .venv/bin/python key_mode.py score   --data <same folder>                                  score, write key_mode_results.tsv

Cache: $DECKIE_KEYMODE_CACHE or <scratchpad>/keymode_cache/ (one .npz per clip, per-frame arrays, not committed).
Run from mixer/ with `nice -n 19` and at most 2 jobs (machine rule of Oct 29).

The rules (no parameter is fitted; all comparisons are plain "which is larger"):
  a   third only: minor if p[t+3] > p[t+4] (minor third above the tonic against the major third).
  b   third, sixth and seventh, equal weights: minor if (p3 - p4) + (p8 - p9) + (p10 - p11) > 0.
  b2  third and sixth only (the two degrees where Temperley's profiles differ), equal weights.
Why those degrees: in every key profile the engine carries (key_light.PROFILES), the major and minor profiles differ
mostly at the third (3 vs 4 semitones), the sixth (8 vs 9) and the seventh (10 vs 11). Temperley 1999 (Music
Perception 17(1), 65-100), revised Krumhansl-Schmuckler profiles: they differ only at the third and the sixth (his minor
uses the raised seventh). Krumhansl and Kessler 1982 (Psychological Review 89(4), 334-368), probe-tone profiles: the
largest differences are the third, then the sixth, then the minor seventh. Faraldo's EDM profiles (edma 2016, braw
2017) show the same three degrees. A ratio p3/p4 against 1 is the same rule as the plain comparison; no source gives
another threshold, so none is used. Ties keep row 3f's mode.

Inputs the rules run on (all summed over frames, no per-frame normalisation unless noted):
  H4w  whitened HPCP with 4 harmonics (row 3f's own profile)
  H1w  whitened HPCP with 1 harmonic (no harmonic folding)
  C0   the shipped engine's STFT chroma (librosa chroma_stft at 22.05 kHz, row 0's input; frame-normalised by librosa)
Tonic: T1 = the tonic of row 3f's winning key; T2 = the tonic whose major and minor mean correlations sum highest
(a mode-neutral tonic).

Selection without fitting to the set: every rule is parameter-free, but picking the best of several is a choice, so
the best variant is chosen on odd-numbered clip ids (high confidence) by balanced exact (the mean of the major-key and
minor-key exact rates, so a minor-leaning rule cannot win on this 70-percent-minor set by its prior), and reported on
the even ids as the held-out result."""
import csv, os, re, sys, time, subprocess, warnings
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import key_light as KL
import key_parity as KP
import key_outside as KO

SCRATCH = "/private/tmp/claude-501/-Users-christophershannon-personal-deckie/ef174277-de81-4c73-b21f-f857b905220e/scratchpad"
CACHE = os.environ.get("DECKIE_KEYMODE_CACHE", os.path.join(SCRATCH, "keymode_cache"))
MIN_FREE = 4 * 1024 ** 3

def free_bytes():
    """free + inactive pages times the page size, from vm_stat (the machine rule's measure)."""
    out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    page = int(re.search(r"page size of (\d+)", out).group(1))
    get = lambda k: int(re.search(rf"{k}:\s+(\d+)", out).group(1))
    return (get("Pages free") + get("Pages inactive")) * page

def clips(data):
    ann = KO.read_annotations(os.path.join(data, "Beatport-EDM-Key-Dataset.xlsx"))
    files = {}
    for root, _, fs in os.walk(os.path.join(data, "audio")):
        for f in fs:
            if f.lower().endswith((".mp3", ".wav", ".flac", ".m4a")) and not f.startswith("."):
                m = re.match(r"(\d+)", f)
                if m: files[m.group(1)] = os.path.join(root, f)
    return ann, [(i, files[i]) for i in sorted(ann, key=int) if ann[i]["camelot"] and i in files]

# ----------------------------------------------------------------------------------------------- extraction
def extract_one(item):
    cid, path = item
    out = os.path.join(CACHE, cid + ".npz")
    if os.path.exists(out): return cid, "cached", 0.0
    t0 = time.time()
    try:
        import librosa
        y, _ = KP.load44(path)
        F, M, E, rms, Emax = KP.spectral_peaks(y)
        H4w = KP.hpcp(F, M, Emax[1 / 3], n_harm=4, whiten=True, frame_norm=False)
        H1w = KP.hpcp(F, M, Emax[1 / 3], n_harm=1, whiten=True, frame_norm=False)
        y22 = librosa.resample(y, orig_sr=KP.SR44, target_sr=KP.SR22, res_type="soxr_hq")   # as key_outside.one
        S = np.abs(librosa.stft(y22, n_fft=KP.N22, hop_length=KP.H22)) ** 2
        C0 = librosa.feature.chroma_stft(S=S, sr=KP.SR22, n_fft=KP.N22, hop_length=KP.H22, tuning=0.0)
        np.savez_compressed(out, H4w=H4w.astype(np.float32), H1w=H1w.astype(np.float32), C0=C0.T.astype(np.float32))
        return cid, "ok", time.time() - t0
    except Exception as e:
        return cid, f"error {e}", time.time() - t0

def main_extract(data, jobs):
    jobs = min(jobs, 2)                      # machine rule: never more than 2 workers
    os.makedirs(CACHE, exist_ok=True)
    _, todo = clips(data)
    todo = [x for x in todo if not os.path.exists(os.path.join(CACHE, x[0] + ".npz"))]
    if free_bytes() < MIN_FREE: sys.exit(f"free plus inactive {free_bytes() / 1e9:.1f} GB < 4 GB, not starting")
    print(f"extracting {len(todo)} clips with {jobs} workers into {CACHE}", file=sys.stderr)
    from multiprocessing import Pool
    t0 = time.time(); per = []
    with Pool(jobs) as pool:
        for k, (cid, st, dt) in enumerate(pool.imap_unordered(extract_one, todo, chunksize=2), 1):
            if st.startswith("error"): print(cid, st, file=sys.stderr)
            else: per.append(dt)
            if k % 50 == 0:
                fb = free_bytes()
                print(f"{k}/{len(todo)} {time.time() - t0:.0f}s  free+inactive {fb / 1e9:.1f} GB", file=sys.stderr)
                if fb < MIN_FREE: pool.terminate(); sys.exit("stopping: free plus inactive under 4 GB (rerun resumes)")
    print(f"extracted {len(per)} in {time.time() - t0:.0f}s wall, {np.mean(per) if per else 0:.2f}s per clip per worker", file=sys.stderr)

# ----------------------------------------------------------------------------------------------- the rules
RULES = {"a": ((3, 4),), "b": ((3, 4), (8, 9), (10, 11)), "b2": ((3, 4), (8, 9))}

def mode_by_rule(p, t, rule):
    """'minor', 'major' or None (tie) from the pitch-class profile p (C = 0) and the tonic t."""
    d = sum(p[(t + lo) % 12] - p[(t + hi) % 12] for lo, hi in RULES[rule])
    return "minor" if d > 0 else ("major" if d < 0 else None)

def tonic_of(r, how):
    if how == "T1": return int(np.argmax(r)) % 12
    return int(np.argmax(r[:12] + r[12:]))

def predict(feat, how, inp, rule):
    """(camelot, the rule's mode, row 3f's mode) for one clip."""
    r = sum(KP.corr24(feat["h4"], KP.km(p)) for p in KP.FARALDO) / len(KP.FARALDO)
    best = int(np.argmax(r)); mode3f = "major" if best < 12 else "minor"
    t = tonic_of(r, how)
    m = mode_by_rule(feat[inp], t, rule)
    mode = m or mode3f if how == "T1" else (m or ("major" if r[t] >= r[12 + t] else "minor"))
    return KL.camelot(t, mode), mode, mode3f

def load_feats(todo):
    out = {}
    for cid, _ in todo:
        p = os.path.join(CACHE, cid + ".npz")
        if not os.path.exists(p): continue
        z = np.load(p)
        h4 = z["H4w"].mean(axis=0)
        out[cid] = {"h4": h4, "H4w": h4, "H1w": z["H1w"].mean(axis=0), "C0": z["C0"].mean(axis=0)}
    return out

# ----------------------------------------------------------------------------------------------- scoring
COLS = ["n", "exact", "neighbour", "other", "mirex", "relative", "fifth", "parallel", "major_as_minor", "minor_as_major"]

def subsets(rows):
    hc = [r for r in rows if r["confidence"] == 2]
    S = {}
    for nm, sub in (("all", rows), ("hc", hc)):
        S[nm] = sub; S[nm + "_major"] = [r for r in sub if r["camelot"][-1] == "B"]; S[nm + "_minor"] = [r for r in sub if r["camelot"][-1] == "A"]
    for half in ("odd", "even"):
        sub = [r for r in hc if int(r["id"]) % 2 == (1 if half == "odd" else 0)]
        S["hc_" + half] = sub
        S[f"hc_{half}_major"] = [r for r in sub if r["camelot"][-1] == "B"]; S[f"hc_{half}_minor"] = [r for r in sub if r["camelot"][-1] == "A"]
    return S

def balanced(S, key, half):
    a = KO.summarise(S[f"hc_{half}_major"], key)["exact"]; b = KO.summarise(S[f"hc_{half}_minor"], key)["exact"]
    return (a + b) / 2

def main_score(data):
    t0 = time.time()
    ann, todo = clips(data)
    feats = load_feats(todo)
    prev = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "key_outside_results.tsv")), delimiter="\t")}
    rows = []; mism3f = mism0 = 0
    variants = [("3f", None, None, None), ("0", None, None, None)] + [(f"{how}-{inp}-{rule}", how, inp, rule)
                for how in ("T1", "T2") for inp in ("H4w", "C0", "H1w") for rule in ("a", "b", "b2")]
    for cid, _ in todo:
        if cid not in feats: continue
        f = feats[cid]; v = ann[cid]
        cam3f, margin, agree, sure = KP.decide(f["h4"])
        base = KP.cam24(int(np.argmax(KP.corr24(f["C0"], KP.km("edma")))))
        if cid in prev:   # the cache must reproduce the outside test's own reads
            mism3f += prev[cid]["predicted"] != cam3f; mism0 += prev[cid]["baseline_predicted"] != base
        row = {"id": cid, "camelot": v["camelot"], "confidence": v["confidence"], "sure": sure, "3f": cam3f, "0": base}
        for name, how, inp, rule in variants[2:]:
            cam, mode, mode3f = predict(f, how, inp, rule)
            row[name] = cam; row[name + "_agrees"] = (mode == mode3f)
        rows.append(row)
    print(f"{len(rows)} clips scored from cache; cache vs key_outside_results.tsv: 3f differs on {mism3f}, row 0 on {mism0}")
    S = subsets(rows)
    out = []
    for name, how, inp, rule in variants:
        for sub in ("all", "all_major", "all_minor", "hc", "hc_major", "hc_minor", "hc_odd", "hc_odd_major", "hc_odd_minor",
                    "hc_even", "hc_even_major", "hc_even_minor"):
            s = KO.summarise(S[sub], name)
            out.append([name, sub] + [s.get(c, float("nan")) for c in COLS])
    # choose the best rule variant on the odd ids by balanced exact; report it on the even ids
    cand = [v[0] for v in variants[2:]]
    score_odd = {n: balanced(S, n, "odd") for n in cand}
    best = max(cand, key=lambda n: score_odd[n])
    print(f"\nbalanced exact on odd ids (high confidence): 3f {balanced(S, '3f', 'odd'):.1f}, row 0 {balanced(S, '0', 'odd'):.1f}")
    for n in sorted(cand, key=lambda n: -score_odd[n]): print(f"  {n:12} {score_odd[n]:5.1f}")
    print(f"best on odd: {best}; held-out (even) balanced exact {balanced(S, best, 'even'):.1f} against 3f {balanced(S, '3f', 'even'):.1f}, row 0 {balanced(S, '0', 'even'):.1f}")
    # sure flag under the best variant: row 3f's flag as is, and the flag tightened to "the rule agrees with 3f's mode"
    for sub in ("hc", "all"):
        L = S[sub]
        for flag, test in (("sure_3f", lambda r: r["sure"]), ("sure_3f_and_rule_agrees", lambda r: r["sure"] and r[best + "_agrees"]),
                           ("rule_agrees", lambda r: r[best + "_agrees"])):
            yes = [r for r in L if test(r)]; no = [r for r in L if not test(r)]
            ex = lambda X, k: 100 * sum(r[k] == r["camelot"] for r in X) / len(X) if X else float("nan")
            out.append([best, f"{sub}_{flag}_yes", len(yes), ex(yes, best)] + [""] * (len(COLS) - 2))
            out.append([best, f"{sub}_{flag}_no", len(no), ex(no, best)] + [""] * (len(COLS) - 2))
            print(f"{sub:4} {flag:26} yes {len(yes):4} ({100 * len(yes) / len(L):4.1f} %) exact {ex(yes, best):5.1f} | no {len(no):4} exact {ex(no, best):5.1f}"
                  f"   (3f's own key: {ex(yes, '3f'):5.1f} / {ex(no, '3f'):5.1f})")
    # diagnostic (not a method: it uses the label's tonic): with the right home note given, how often does each rule
    # name the right mode? This is the ceiling a mode rule could reach with a perfect tonic.
    print("\nmode rule with the labelled tonic (high confidence): percent right on major / minor clips")
    for inp in ("H4w", "C0", "H1w"):
        for rule in RULES:
            res = {}
            for half in ("B", "A"):
                L = [r for r in S["hc"] if r["camelot"][-1] == half]
                ok = 0
                for r in L:
                    t = (KL.CAM_MAJ if half == "B" else KL.CAM_MIN).index(r["camelot"])
                    ok += mode_by_rule(feats[r["id"]][inp], t, rule) == ("major" if half == "B" else "minor")
                res[half] = 100 * ok / len(L)
            print(f"  {inp:4} {rule:3} major {res['B']:5.1f}  minor {res['A']:5.1f}")
            out.append([f"oracle-tonic-{inp}-{rule}", "hc_major", "", res["B"]] + [""] * (len(COLS) - 2))
            out.append([f"oracle-tonic-{inp}-{rule}", "hc_minor", "", res["A"]] + [""] * (len(COLS) - 2))
    # beside Apple's framework on the clips it has read so far (key_outside_apple_partial.tsv)
    ap = os.path.join(HERE, "key_outside_apple_partial.tsv")
    if os.path.exists(ap):
        apple = {r["id"]: r["apple"] for r in csv.DictReader(open(ap), delimiter="\t") if r.get("apple")}
        L = [dict(r, apple=apple[r["id"]]) for r in rows if r["id"] in apple]
        print(f"\nthe {len(L)} clips Apple has read")
        for name in ("apple", "3f", "0", best):
            s = KO.summarise(L, name); KO.show(name, s)
            out.append([name, "apple_clips"] + [s.get(c, float("nan")) for c in COLS])
    with open(os.path.join(HERE, "key_mode_results.tsv"), "w") as fh:
        fh.write("variant\tsubset\t" + "\t".join(COLS) + "\n")
        for r in out: fh.write("\t".join(f"{x:.1f}" if isinstance(x, float) else str(x) for x in r) + "\n")
    # console summary
    for sub in ("hc", "hc_major", "hc_minor", "all", "all_major", "all_minor", "hc_even", "hc_even_major", "hc_even_minor"):
        print(f"\n{sub}")
        for name, *_ in variants:
            KO.show(name, KO.summarise(S[sub], name))
    print(f"\nscoring took {time.time() - t0:.1f}s; best variant (chosen on odd ids): {best}")

if __name__ == "__main__":
    a = sys.argv
    if len(a) < 2 or "--data" not in a: print(__doc__); sys.exit()
    data = a[a.index("--data") + 1]
    if a[1] == "extract": main_extract(data, int(a[a.index("--jobs") + 1]) if "--jobs" in a else 2)
    elif a[1] == "score": main_score(data)
    else: print(__doc__)
