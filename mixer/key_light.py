#!/usr/bin/env python3
"""Lightweight key estimation prototype for the Swift engine (spec 5.1, D13 key segments).
Chroma from a plain STFT (portable to Accelerate), Pearson correlation against published key profiles, whole-track and
windowed with hysteresis. Run with the lab venv:  .venv/bin/python key_light.py --test | --full [--limit N] [--chroma stft|cqt]
Reference for whole-track agreement: the lab's key where its confidence >= 0.65 (features/<id>.json) and Apple's
Music Understanding key (mu_raw/<id>.mu.json). Modulation test: seven songs with known final-chorus key changes."""
import json, os, sys, csv, warnings
warnings.filterwarnings("ignore")
import numpy as np, soundfile as sf, librosa

HERE = os.path.dirname(os.path.abspath(__file__))
MU_TEST_DIR = os.environ.get("DECKIE_MU_TEST_DIR", "")
MR = os.environ.get("DECKIE_MUSIC_ROOT", "/Users/christophershannon/personal/90s2000 playlist")
PC = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
CAM_MAJ = ["8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B"]
CAM_MIN = ["5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A"]
MU_PC = {"c": 0, "cSharp": 1, "dFlat": 1, "d": 2, "dSharp": 3, "eFlat": 3, "e": 4, "f": 5, "fSharp": 6, "gFlat": 6, "g": 7, "gSharp": 8, "aFlat": 8, "a": 9, "aSharp": 10, "bFlat": 10, "b": 11}
# key profiles (Essentia key.cpp, verbatim): tonic first
PROFILES = {
 "krumhansl": ([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88], [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]),
 "temperley": ([5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0], [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]),
 "shaath": ([6.6, 2.0, 3.5, 2.3, 4.6, 4.0, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4], [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4.0, 2.7, 4.3, 3.2]),
 "edma": ([1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39], [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32]),
 "bgate": ([1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30], [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23]),
 "braw": ([1.0000, 0.1573, 0.4200, 0.1570, 0.5296, 0.3669, 0.1632, 0.7711, 0.1676, 0.3827, 0.2113, 0.2965], [1.0000, 0.2330, 0.3615, 0.3905, 0.2925, 0.3777, 0.1961, 0.7425, 0.2701, 0.2161, 0.4228, 0.2272]),
}
SR = 22050; NFFT = 8192; HOP = 2048   # 0.37 s frames, 2.7 Hz bins: enough for pitch classes down to the bass

def load(path):
    y, sr = sf.read(path, dtype="float32", always_2d=True); y = y.mean(axis=1)
    if sr != SR: y = librosa.resample(y, orig_sr=sr, target_sr=SR, res_type="soxr_hq")
    return y

def hpcp(y, n_harm=8, fmin=40.0, fmax=5000.0, peak_db=-60.0):
    """HPCP-style chroma from an STFT (Gomez 2006, simplified): spectral peaks, each spread over +-1 semitone with
    a cosine-squared weight, and its first n_harm harmonics credited with weight 0.8**k; frames normalised to their
    maximum. Everything here is an FFT plus a few loops: portable to Accelerate."""
    S = np.abs(librosa.stft(y, n_fft=NFFT, hop_length=HOP)) ** 2
    freqs = librosa.fft_frequencies(sr=SR, n_fft=NFFT)
    band = (freqs >= fmin) & (freqs <= fmax); fb = freqs[band]; Sb = S[band]
    ref = Sb.max() + 1e-12; thr = ref * 10 ** (peak_db / 10)
    # local maxima per frame
    pk = np.zeros_like(Sb, dtype=bool); pk[1:-1] = (Sb[1:-1] > Sb[:-2]) & (Sb[1:-1] >= Sb[2:]) & (Sb[1:-1] > thr)
    out = np.zeros((12, Sb.shape[1]))
    bins = np.arange(12)
    for k in range(1, n_harm + 1):
        w = 0.8 ** (k - 1)
        # pitch class (in semitone units, fractional) of each bin's fundamental when this bin is the k-th harmonic
        pcf = (12 * np.log2(fb / (k * 440.0)) + 69) % 12          # fractional pitch class, 0 = C
        d = np.abs((pcf[:, None] - bins[None, :] + 6) % 12 - 6)    # distance to each pitch class in semitones
        wt = np.where(d <= 1.0, np.cos(d * np.pi / 2) ** 2, 0.0) * w   # (nbins, 12)
        out += wt.T @ (Sb * pk)
    out /= out.max(axis=0, keepdims=True) + 1e-12
    return out

def chroma(y, kind):
    if kind == "cqt": return librosa.feature.chroma_cqt(y=y, sr=SR, hop_length=HOP)
    if kind == "cens": return librosa.feature.chroma_cens(y=y, sr=SR, hop_length=HOP)
    if kind == "hpcp": return hpcp(y)
    return librosa.feature.chroma_stft(y=y, sr=SR, n_fft=NFFT, hop_length=HOP, tuning=0.0)

def best_key(c, prof):
    """c: 12 pitch-class energies (C first). Returns (pc, mode, r, margin) by Pearson correlation over 24 keys."""
    c = np.asarray(c, float); c = c - c.mean()
    if np.linalg.norm(c) == 0: return (0, "major", 0.0, 0.0)
    scores = []
    for mode, p in (("major", prof[0]), ("minor", prof[1])):
        p = np.asarray(p, float); p = p - p.mean()
        for s in range(12):
            q = np.roll(p, s); scores.append((float(np.dot(c, q) / (np.linalg.norm(c) * np.linalg.norm(q))), s, mode))
    scores.sort(reverse=True); (r1, s1, m1), (r2, _, _) = scores[0], scores[1]
    return (s1, m1, r1, r1 - r2)

def camelot(pc, mode): return (CAM_MAJ if mode == "major" else CAM_MIN)[pc]
def relation(a, b):
    if a == b: return "exact"
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    if na == nb: return "relative"
    if la == lb and (na - nb) % 12 in (1, 11): return "neighbour"
    if la != lb and (na - nb) % 12 in (3, 9): return "parallel"   # same tonic, other mode (12A C# minor vs 3B C# major)
    return "other"

def wheel_cost(a, b):
    """How far apart two Camelot keys sit: steps around the wheel plus one for a letter change; 0 for the same
    tonal area (same key, relative, neighbour, parallel major/minor)."""
    rel = relation(a, b)
    if rel in ("exact", "relative", "neighbour", "parallel"): return 0
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    d = min((na - nb) % 12, (nb - na) % 12)
    return d + (1 if la != lb else 0)

def segments(C, prof, win_s=20.0, hop_s=5.0, persist=2, min_margin=0.04):
    """Windowed keys with hysteresis. A new key opens a segment only when it is outside the running key's tonal
    area, wins consecutive windows with a correlation margin of at least min_margin, and persists: `persist`
    windows for a far move (wheel cost 3 or more), twice that for a near one (cost 1 or 2), where harmonic
    flicker lives. Returns [(start_s, camelot, mean_r)]."""
    fps = SR / HOP; w = int(win_s * fps); h = int(hop_s * fps); n = C.shape[1]
    keys = []
    for a in range(0, max(1, n - w + 1), h):
        pc, mode, r, m = best_key(C[:, a:a + w].mean(axis=1), prof); keys.append((a / fps, camelot(pc, mode), r, m))
    if not keys: return []
    segs = [[0.0, keys[0][1], [keys[0][2]]]]; run = []
    for t, k, r, m in keys[1:]:
        cur = segs[-1][1]; cost = wheel_cost(k, cur)
        if cost == 0 or m < min_margin:
            segs[-1][2].append(r); run = []; continue
        if run and run[-1][1] != k: run = []
        run.append((t, k, r))
        need = persist if cost >= 3 else 2 * persist
        if len(run) >= need:
            segs.append([run[0][0], k, [x[2] for x in run]]); run = []
    return [(round(s, 1), k, round(float(np.mean(rs)), 3)) for s, k, rs in segs]

TEST = [("891b54fada", "Love On Top", "C -> C# D Eb E from ~180 s"), ("d3905c0b4f", "I Will Always Love You", "A -> B at ~180 s"),
        ("f92fbda8d0", "My Heart Will Go On", "E -> Ab at ~260 s"), ("910451787e", "I Don't Want to Miss a Thing", "known modulation, not verified"),
        ("fd796c8339", "End Of The Road", "known modulation, not verified"), ("0692b134c9", "Livin' La Vida Loca", "control: no change"),
        ("6489f248e0", "Crazy In Love", "control: no change")]

def main():
    kind = sys.argv[sys.argv.index("--chroma") + 1] if "--chroma" in sys.argv else "stft"
    pool = {r["id"]: r for r in json.load(open(os.path.join(HERE, "..", "pool", "newfiles", "pool.json")))}
    if "--test" in sys.argv:
        win = float(sys.argv[sys.argv.index("--win") + 1]) if "--win" in sys.argv else 20.0
        hop = float(sys.argv[sys.argv.index("--hop") + 1]) if "--hop" in sys.argv else 5.0
        persist = int(sys.argv[sys.argv.index("--persist") + 1]) if "--persist" in sys.argv else 2
        for prof in (["edma", "temperley", "krumhansl"] if "--all" in sys.argv else ["edma"]):
            print(f"\n== windowed key segments, chroma={kind}, profile={prof}, {win:g} s windows every {hop:g} s, persist {persist}")
            for tid, name, truth in TEST:
                y = load(os.path.join(MR, pool[tid]["path"])); C = chroma(y, kind)
                pc, mode, r, m = best_key(C.mean(axis=1), PROFILES[prof])
                segs = segments(C, PROFILES[prof], win, hop, persist)
                print(f"  {name:30} whole {camelot(pc, mode):>3} (r {r:.2f}) | " + "; ".join(f"{s}s {k}" for s, k, _ in segs) + f"   [{truth}]")
        return
    cands = json.load(open(os.path.join(HERE, "candidates.json")))
    if "--ends" in sys.argv:
        # three keys per track: whole song, mix-in window, mix-out window (windows from the lab features). A window key
        # is flagged only when it is far from the song key (wheel cost >= 3) and the song key fits that window worse
        # than the window key by at least `gap` in correlation.
        gap = float(sys.argv[sys.argv.index("--gap") + 1]) if "--gap" in sys.argv else 0.08
        limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else len(cands)
        only_test = "--test-ids" in sys.argv; test_ids = [t[0] for t in TEST]
        todo = [{"id": t[0], "title": t[1], "path": os.path.join(MR, pool[t[0]]["path"])} for t in TEST] if only_test else cands[:limit]
        fps = SR / HOP; prof = PROFILES["edma"]; flagged = []; rows = []
        def corr_for(cm, cam):
            """correlation of a given Camelot key's profile with a chroma mean"""
            pc = (CAM_MAJ + CAM_MIN).index(cam) % 12; mode = "major" if cam.endswith("B") else "minor"
            c = np.asarray(cm, float) - np.mean(cm); q = np.roll(np.asarray(prof[0] if mode == "major" else prof[1], float), pc); q = q - q.mean()
            return float(np.dot(c, q) / (np.linalg.norm(c) * np.linalg.norm(q) + 1e-12))
        for i, x in enumerate(todo):
            fp = os.path.join(HERE, "features", x["id"] + ".json"); f = json.load(open(fp)) if os.path.exists(fp) else {}
            try: y = load(x["path"]); C = chroma(y, kind)
            except Exception as e: print("skip", x["id"], e, file=sys.stderr); continue
            pc, mode, r, m = best_key(C.mean(axis=1), prof); whole = camelot(pc, mode)
            # the song key the product will use is Apple's; the lightweight whole estimate is kept for comparison
            mu_key = ""
            for mp in (os.path.join(HERE, "mu_raw", x["id"] + ".mu.json"), os.path.join(MU_TEST_DIR, x["id"] + ".mu.json")):
                if os.path.exists(mp):
                    k = json.load(open(mp)).get("key")
                    if k and k["ranges"]:
                        v = max(k["ranges"], key=lambda z: z["range"]["duration"]["value"])["value"]; mu_key = camelot(MU_PC[v["tonic"]], v["mode"])
                    break
            ref = mu_key or whole
            out = {"id": x["id"], "title": x["title"][:34], "ref": ref, "mu": mu_key, "whole": whole, "whole_r": round(r, 2), "lab": (f.get("key") or {}).get("camelot", "")}
            for name in ("mix_in", "mix_out"):
                w = f.get(name) or {}; a, b = int(w.get("start_s", 0) * fps), int(w.get("end_s", 0) * fps)
                if b - a < int(8 * fps): a, b = (0, int(30 * fps)) if name == "mix_in" else (max(0, C.shape[1] - int(30 * fps)), C.shape[1])
                cm = C[:, a:b].mean(axis=1); pc2, mode2, r2, m2 = best_key(cm, prof); k2 = camelot(pc2, mode2)
                r_whole_here = corr_for(cm, ref); far = wheel_cost(k2, ref) >= 2; flag = far and (r2 - r_whole_here) >= gap
                out[name] = k2; out[name + "_flag"] = flag; out[name + "_gain"] = round(r2 - r_whole_here, 2)
            rows.append(out)
            if out["mix_in_flag"] or out["mix_out_flag"]: flagged.append(out)
            if i % 25 == 0 and not only_test: print(f"{i+1}/{len(todo)}", file=sys.stderr)
        if only_test:
            for o in rows: print(f"  {o['title']:34} song {o['ref']:>3} (Apple {o['mu']:>3}, light {o['whole']:>3}) | in {o['mix_in']:>3}{'*' if o['mix_in_flag'] else ' '} gain {o['mix_in_gain']:+.2f} | out {o['mix_out']:>3}{'*' if o['mix_out_flag'] else ' '} gain {o['mix_out_gain']:+.2f}")
        else:
            print(f"ends mode, chroma={kind}, gap {gap}: {len(rows)} tracks; flagged mix-in {sum(1 for o in rows if o['mix_in_flag'])}, mix-out {sum(1 for o in rows if o['mix_out_flag'])}")
            for o in flagged: print(f"  {o['title']:34} song {o['ref']:>3} (lab {o['lab']:>3}) | in {o['mix_in']:>3}{'*' if o['mix_in_flag'] else ' '} {o['mix_in_gain']:+.2f} | out {o['mix_out']:>3}{'*' if o['mix_out_flag'] else ' '} {o['mix_out_gain']:+.2f}")
            with open(os.path.join(HERE, f"key_ends_{kind}.tsv"), "w") as fh:
                w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), delimiter="\t"); w.writeheader(); w.writerows(rows)
        return
    if "--sweep" in sys.argv:
        n = int(sys.argv[sys.argv.index("--sweep") + 1]); test_ids = {t[0] for t in TEST}
        import random; random.seed(7); pick = random.sample([x for x in cands if x["id"] not in test_ids], n)
        multi = []
        for x in pick:
            y = load(x["path"]); C = chroma(y, kind); segs = segments(C, PROFILES["edma"])
            if len(segs) > 1: multi.append((x["title"][:34], [(s, k) for s, k, _ in segs]))
        print(f"false-change sweep, chroma={kind}: {len(multi)} of {n} ordinary tracks got more than one key segment")
        for t, sg in multi: print("  ", t, sg)
        return
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else len(cands)
    rows = []
    for i, x in enumerate(cands[:limit]):
        f = json.load(open(os.path.join(HERE, "features", x["id"] + ".json")))
        mup = os.path.join(HERE, "mu_raw", x["id"] + ".mu.json"); mu_key = ""
        if os.path.exists(mup):
            k = json.load(open(mup)).get("key")
            if k and k["ranges"]:
                v = max(k["ranges"], key=lambda z: z["range"]["duration"]["value"])["value"]; mu_key = camelot(MU_PC[v["tonic"]], v["mode"])
        try: y = load(x["path"]); C = chroma(y, kind); cm = C.mean(axis=1)
        except Exception as e: print("skip", x["id"], e, file=sys.stderr); continue
        row = {"id": x["id"], "title": x["title"][:36], "lab": f["key"]["camelot"], "lab_conf": f["key"]["confidence"], "mu": mu_key}
        for prof in PROFILES:
            pc, mode, r, m = best_key(cm, PROFILES[prof]); row[prof] = camelot(pc, mode); row[prof + "_r"] = round(r, 3); row[prof + "_margin"] = round(m, 3)
        rows.append(row)
        if i % 25 == 0: print(f"{i+1}/{limit}", file=sys.stderr)
    out = os.path.join(HERE, f"key_light_{kind}.tsv")
    with open(out, "w") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), delimiter="\t"); w.writeheader(); w.writerows(rows)
    conf = [r for r in rows if r["lab_conf"] >= 0.65]
    print(f"\nwhole-track key, chroma={kind}: {len(rows)} tracks; against the lab's confident keys (n={len(conf)}) and Apple's key")
    print(f"  {'profile':10} {'exact':>6} {'relative':>9} {'neighbour':>10} {'other':>6} | {'vs Apple exact':>14} {'exact+rel+nbr':>14}")
    for prof in list(PROFILES) + ["mu"]:
        if prof == "mu":
            rel = [relation(r["mu"], r["lab"]) for r in conf if r["mu"]]; mu_ex = ""
        else:
            rel = [relation(r[prof], r["lab"]) for r in conf]
            withmu = [r for r in rows if r["mu"]]; mu_ex = f"{sum(1 for r in withmu if r[prof] == r['mu'])/len(withmu)*100:5.0f}%  {sum(1 for r in withmu if relation(r[prof], r['mu']) != 'other')/len(withmu)*100:5.0f}%"
        n = len(rel); c = {k: sum(1 for z in rel if z == k) / n * 100 for k in ("exact", "relative", "neighbour", "other")}
        print(f"  {prof:10} {c['exact']:5.0f}% {c['relative']:8.0f}% {c['neighbour']:9.0f}% {c['other']:5.0f}% | {mu_ex}")
    print("wrote", out)

if __name__ == "__main__": main()
