"""Three-way per-bar vocal comparison: the PC engine's records vs the lab's feature files vs Apple's instrument activity.

usage (from mixer/): python vocal3way.py <records dir from deckie-build bench> [out.json]
Apple's series come from mu_raw/<id>.mu.json (tools/mubench), averaged inside each lab bar as bench_mu.py does.
"""
import json, glob, os, sys, bisect, statistics as st, math

def pearson(x, y):
    n = len(x)
    if n < 3: return None
    mx, my = sum(x) / n, sum(y) / n
    sx = math.sqrt(sum((a - mx) ** 2 for a in x)); sy = math.sqrt(sum((b - my) ** 2 for b in y))
    if sx == 0 or sy == 0: return None
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / (sx * sy)

def secs(t):  # a CMTime dictionary (value over timescale) or a plain number
    return float(t["value"]) / float(t.get("timescale") or 1) if isinstance(t, dict) else float(t)

def main(records, out):
    here = os.path.dirname(os.path.abspath(__file__))
    rows = []; no_apple = 0; lenmis = 0
    for rf in sorted(glob.glob(os.path.join(records, "*.json"))):
        tid = os.path.basename(rf)[:-5]; e = json.load(open(rf))
        lf = os.path.join(here, "features", f"{tid}.json"); mf = os.path.join(here, "mu_raw", f"{tid}.mu.json")
        if not (os.path.exists(lf) and os.path.exists(mf)): continue
        f = json.load(open(lf)); r = json.load(open(mf))
        labv = f["per_bar"]["vocal_prob"]; engv = e["per_bar"]["vocal_prob"]
        if len(labv) != len(engv): lenmis += 1; continue
        lab_gd = f["downbeats_s"]; bar_s = f["grid"]["bar_s"]
        ia = (r.get("instrumentActivity") or {}).get("activity") or {}
        voc = [(secs(t["time"]), float(t["value"])) for t in ia.get("vocal", [])]
        if not voc: no_apple += 1; continue
        times = [t for t, _ in voc]; mu = []
        for i in range(len(labv)):
            t0 = lab_gd[i] if i < len(lab_gd) else lab_gd[0] + i * bar_s; t1 = t0 + bar_s
            a, b = bisect.bisect_left(times, t0), bisect.bisect_left(times, t1)
            mu.append(sum(v for _, v in voc[a:b]) / (b - a) if b > a else None)
        idx = [i for i, m in enumerate(mu) if m is not None]
        if len(idx) < 8: no_apple += 1; continue
        L = [labv[i] for i in idx]; E = [engv[i] for i in idx]; M = [mu[i] for i in idx]
        row = dict(id=tid, r_eng_lab=pearson(E, L), r_mu_lab=pearson(M, L), r_eng_mu=pearson(E, M),
                   mean_lab=st.mean(L), mean_eng=st.mean(E), mean_mu=st.mean(M))
        # alternative readings of the tagger (deckie.vocal.readings: name -> per-bar series) and a second opinion
        dv = ((e.get("deckie") or {}).get("vocal") or {})
        for group in ("readings", "second_opinion"):
            for name, series in (dv.get(group) or {}).items():
                if isinstance(series, list) and len(series) == len(labv):
                    X = [series[i] for i in idx]
                    row[f"{group}.{name}.r_lab"] = pearson(X, L); row[f"{group}.{name}.r_mu"] = pearson(X, M)
        rows.append(row)
    print("tracks compared", len(rows), "no apple series", no_apple, "bar-count mismatch", lenmis)
    def med(k):
        v = [r[k] for r in rows if r[k] is not None]; return st.median(v), st.mean(v), len(v)
    for k in ("r_eng_lab", "r_mu_lab", "r_eng_mu"):
        m, a, n = med(k); print(f"{k:10s} per-bar r median {m:.2f} mean {a:.2f} (n {n})")
    print("mean level: lab %.2f  engine %.3f  apple %.2f" % (st.mean(r["mean_lab"] for r in rows), st.mean(r["mean_eng"] for r in rows), st.mean(r["mean_mu"] for r in rows)))
    print("across tracks, r of per-track means: engine vs lab %.2f, apple vs lab %.2f, engine vs apple %.2f" % (
        pearson([r["mean_eng"] for r in rows], [r["mean_lab"] for r in rows]), pearson([r["mean_mu"] for r in rows], [r["mean_lab"] for r in rows]), pearson([r["mean_eng"] for r in rows], [r["mean_mu"] for r in rows])))
    print("engine mean below 0.02 on", sum(1 for r in rows if r["mean_eng"] < 0.02), "tracks")
    extra = sorted({k for r in rows for k in r if k.endswith(".r_lab")})
    for k in extra:
        base = k[:-6]
        ml, nl = med(k)[0], med(k)[2]; mm = med(base + ".r_mu")[0]
        print(f"{base:36s} r vs lab median {ml:.2f}  vs Apple {mm:.2f}  (n {nl})")
    if out: json.dump(rows, open(out, "w"), indent=0)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
