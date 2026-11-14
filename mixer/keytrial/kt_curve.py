#!/usr/bin/env python3
"""Key trial, phase 4: how many labelled songs do the learned profiles need? EVALUATION ONLY.

  OMP_NUM_THREADS=1 python kt_curve.py     -> prints the table; writes curve_results.tsv

For each of the five artist-grouped folds of MTG the profiles are fitted on a random sample of N clips from the other
four folds (three samples per size, whole artist groups not split) and scored on the fold's clips; and, fitted on N
MTG clips sharing no artist with them, on GiantSteps+ and GiantSteps Key. 'equal' weighs major and minor clips the
same in the fit. The sizes were fixed before the run."""
import os, numpy as np
import kt, kt_x, kt_prof as KPF, kt_mode as KM

SIZES = (25, 50, 100, 200, 400, 800, 1020)

def main():
    M = kt_x.load_set("mtg"); P = kt_x.load_set("gsplus", "key_modal"); G = kt_x.load_set("gs")
    apple = kt.apple_keys(); sel = np.array([i in apple for i in M["ids"]])
    rng = np.random.default_rng(0); rows = []
    for which in ("AB", "all"):
        for eq in (False, True):
            for n in SIZES:
                ex, mean, home, gp, gs = [], [], [], [], []
                for rep in range(3 if n < 1020 else 1):
                    pred = np.zeros(len(M["key"]), int)
                    for f in range(kt.NFOLD):
                        tr = np.where(M["fold"] != f)[0]; tr = rng.permutation(tr)[:n]; te = M["fold"] == f
                        m = np.zeros(len(M["key"]), bool); m[tr] = True
                        pred[te] = KPF.predict(KM.sub(M["F"], te), KPF.fit(KM.sub(M["F"], m), M["key"][m], which, eq), which).argmax(1)
                    r = kt_x.four(pred[sel], M["key"][sel]); ex.append(r["exact"]); mean.append(r["mean"]); home.append(r["home"])
                    for D, acc in ((P, gp), (G, gs)):
                        gn = set().union(*D["names"]); clean = np.where([not (x & gn) for x in M["names"]])[0]; tr = rng.permutation(clean)[:n]
                        m = np.zeros(len(M["key"]), bool); m[tr] = True
                        acc.append(100 * (KPF.predict(D["F"], KPF.fit(KM.sub(M["F"], m), M["key"][m], which, eq), which).argmax(1) == D["key"]).mean())
                rows.append((which, eq, n, np.mean(ex), np.min(ex), np.max(ex), np.mean(mean), np.mean(home), np.mean(gp), np.mean(gs)))
                print(rows[-1], flush=True)
    with open(os.path.join(kt.HERE, "curve_results.tsv"), "w") as fh:
        fh.write("sources\tmodes_weighed_equally\ttraining_clips\tmtg_exact_mean\tmtg_exact_min\tmtg_exact_max\tmtg_mean_of_halves\tmtg_home\tgsplus_exact\tgs_exact\n")
        for r in rows: fh.write("\t".join(str(x) if not isinstance(x, float) else f"{x:.2f}" for x in r) + "\n")
    print("\n| profiles | fit | training clips | MTG exact (lowest to highest of the samples) | MTG mean of halves | MTG home note | GiantSteps+ exact | GiantSteps Key exact |\n|---|---|---:|---:|---:|---:|---:|---:|")
    for w, eq, n, e, lo, hi, me, ho, gp, gs in rows:
        print(f"| {'rows A and B (49 numbers)' if w == 'AB' else 'seven chromas (169 numbers)'} | {'modes equal' if eq else 'as the set is'} | {n} | {e:.1f} ({lo:.1f} to {hi:.1f}) | {me:.1f} | {ho:.1f} | {gp:.1f} | {gs:.1f} |")

if __name__ == "__main__":
    main()
