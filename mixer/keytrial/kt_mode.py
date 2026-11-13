#!/usr/bin/env python3
"""Key trial, phase 2: the mode alone. Given a home note, decide major against minor.

  python kt_mode.py            (needs kt_bench.py and kt_modefeats.py)  -> prints the tables, writes mode_results.tsv
                                                                           and mode_clips.tsv

Two settings. CEILING: the true home note is given, and the score is how often the mode is right, on the major clips
and the minor clips separately (their mean is 'balanced': a rule that always says minor scores 50). SHIP: the home note
is the reader's own (row B's, and row A's), and the score is the exact key.

Untrained rules have no parameter: a rule's sign decides, and a tie keeps the baseline's mode. Where one rule is picked
among many, it is picked on folds 0-2 (the selection part) and reported on folds 3-4 (the held-out part); folds are
grouped by artist. Trained rules are fitted on four folds and scored on the fifth, so every clip is scored by a model
that never saw it or its artist; their settings are scikit-learn's defaults, fixed before the run.

Baseline for the paired tests: the reader's own profile match restricted to the given home note (row B's scores)."""
import os, sys, csv, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt
import key_parity as KP

def rot(V, t):
    """rotate each row so its home note is at index 0."""
    V = np.asarray(V); idx = (np.arange(12)[None, :] + np.asarray(t)[:, None]) % 12
    return np.take_along_axis(V, idx, axis=1)

def r_diff(V, t):
    """minor minus major: mean Pearson r over Faraldo's three profiles, on the given home note."""
    out = np.zeros(len(V))
    for i, (v, ti) in enumerate(zip(V, t)):
        s = sum(KP.corr24(v, KP.km(p)) for p in KP.FARALDO) / 3; out[i] = s[12 + ti] - s[ti]
    return out

def third(R): return R[:, 3] - R[:, 4]
def b367(R):
    R = R / (R.sum(1, keepdims=True) + 1e-12); return (R[:, 3] - R[:, 4]) + (R[:, 8] - R[:, 9]) + (R[:, 10] - R[:, 11])

MAJ_FAM = [(0, 0), (5, 0), (7, 0), (2, 1), (4, 1), (9, 1)]     # I IV V, ii iii vi   (interval above the home note, minor?)
MIN_FAM = [(0, 1), (5, 1), (7, 1), (3, 0), (8, 0), (10, 0)]    # i iv v, III VI VII

def rules(F, R, t):
    """name -> score per clip (positive says minor) for the home notes t. F: modefeats, R: readers' 24 scores."""
    n = len(t); ar = np.arange(n); out = {}
    for k in ("3f", "A", "B"): out[f"profile match, row {k}"] = R[k][ar, 12 + t] - R[k][ar, t]
    src = {"row 3f chroma": "c_3f", "row A chroma": "c_A", "row B chroma": "c_B", "bass register": "r_bass", "middle register": "r_mid",
           "melody register": "r_mel", "bass line (time)": "bassline", "top line (time)": "topline",
           "stable half, row B": "st_B", "stable half, row A": "st_A", "unstable half, row B": "un_B"}
    for label, key in src.items():
        Rt = rot(F[key], t)
        out[f"third only: {label}"] = third(Rt)
        out[f"third+sixth+seventh: {label}"] = b367(Rt)
        if key not in ("c_3f", "c_A", "c_B"): out[f"profile match: {label}"] = r_diff(F[key], t)
    ch = F["chords"]
    out["home chord, triad templates (time on minor - major triad)"] = ch[ar, 12 + t] - ch[ar, t]
    fam = lambda fam_: sum(ch[ar, 12 * m + (t + iv) % 12] for iv, m in fam_)
    out["chord families (time on i iv v III VI VII - I IV V ii iii vi)"] = fam(MIN_FAM) - fam(MAJ_FAM)
    tv = F["triad_votes"][ar, t]
    out["home chord sounding, louder third (frames)"] = tv[:, 0] - tv[:, 1]
    ob = F["overbass"][ar, t]; obr = rot(ob, t)
    out["above the home note in the bass: third only"] = third(obr)
    out["above the home note in the bass: third+sixth+seventh"] = b367(obr)
    out["always minor"] = np.ones(n)
    return out

def sub(F, mask): return {k: v[mask] for k, v in F.items()}

def design(F, t, which):
    """feature matrix for the trained rules, everything rotated to the home note t."""
    def nrm(X): return X / (X.sum(1, keepdims=True) + 1e-12)
    if which == "A12": return nrm(rot(F["c_A"], t))
    if which == "B12": return nrm(rot(F["c_B"], t))
    ar = np.arange(len(t)); ch = F["chords"]
    parts = [nrm(rot(F[k], t)) for k in ("c_A", "c_B", "r_bass", "r_mid", "r_mel", "bassline", "topline", "st_B")]
    chn = ch / (ch.sum(1, keepdims=True) + 1e-12)
    parts += [rot(chn[:, :12], t), rot(chn[:, 12:], t), nrm(rot(F["overbass"][ar, t], t))]
    tv = F["triad_votes"][ar, t]; parts.append(tv[:, :2] / (tv[:, 2:3] + 1.0))
    return np.hstack(parts)

def fit_predict(kind, Xtr, ytr, Xte):
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import make_pipeline
    from sklearn.ensemble import HistGradientBoostingClassifier
    if kind == "lr": m = make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000))
    elif kind == "lr_bal": m = make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000, class_weight="balanced"))
    elif kind == "gb": m = HistGradientBoostingClassifier(random_state=0)
    elif kind == "gb_bal": m = HistGradientBoostingClassifier(random_state=0, class_weight="balanced")
    m.fit(Xtr, ytr); return m.predict_proba(Xte)[:, 1] - 0.5, m

TRAINED = [("trained: logistic regression on row A chroma (12 numbers)", "A12", "lr"),
           ("trained: logistic regression on row A chroma, classes balanced", "A12", "lr_bal"),
           ("trained: logistic regression on row B chroma (12 numbers)", "B12", "lr"),
           ("trained: logistic regression on row B chroma, classes balanced", "B12", "lr_bal"),
           ("trained: logistic regression on every measurement (135 numbers)", "all", "lr"),
           ("trained: logistic regression on every measurement, classes balanced", "all", "lr_bal"),
           ("trained: boosted trees on every measurement", "all", "gb"),
           ("trained: boosted trees on every measurement, classes balanced", "all", "gb_bal")]

def acc(ok, sel): return 100 * ok[sel].mean() if sel.any() else float("nan")

def main():
    clips = [c for c in kt.load("mtg")]; fold, grp = kt.folds(clips)
    Z = np.load(os.path.join(kt.CACHE, "modefeats_mtg.npz")); pos = {i: k for k, i in enumerate(Z["ids"])}
    RZ = np.load(os.path.join(kt.CACHE, "readers_mtg.npz")); rpos = {i: k for k, i in enumerate(RZ["ids"])}
    keep = [(c, f) for c, f in zip(clips, fold) if c["key"] is not None and c["id"] in pos]
    ids = [c["id"] for c, _ in keep]; ix = np.array([pos[i] for i in ids]); rx = np.array([rpos[i] for i in ids])
    F = {k: Z[k][ix].astype(np.float64) for k in Z.files if k != "ids"}; R = {k: RZ[k][rx].astype(np.float64) for k in ("3f", "A", "B")}
    key = np.array([c["key"] for c, _ in keep]); fo = np.array([f for _, f in keep]); tt = key % 12; minor = key >= 12
    apple = kt.apple_keys(); ap = np.array([apple.get(i, -1) for i in ids]); has_ap = ap >= 0
    held = np.isin(fo, kt.HELD); sel = ~held; n = len(key)
    print(f"clips {n} ({int((~minor).sum())} major, {int(minor.sum())} minor); selection part {int(sel.sum())}, held-out part {int(held.sum())}; Apple read {int(has_ap.sum())}")
    tonic = {"true": tt, "B": R["B"].argmax(1) % 12, "A": R["A"].argmax(1) % 12}
    base_name = "profile match, row B"

    # ---- scores for every rule under every home note
    S = {}
    for hn, t in tonic.items():
        S[hn] = rules(F, R, t)
        for name, feats, kind in TRAINED:
            s = np.zeros(n)
            for f in range(kt.NFOLD):
                te = fo == f; tr = ~te
                s[te], _ = fit_predict(kind, design(sub(F, tr), tt[tr], feats), minor[tr].astype(int), design(sub(F, te), t[te], feats))   # trained on the true home note
            S[hn][name] = s
    def mode_of(hn, name):
        s = S[hn][name]; b = S[hn][base_name]
        return np.where(s > 0, True, np.where(s < 0, False, b > 0))

    # ---- ceiling: true home note
    rows = []
    b_ok = mode_of("true", base_name) == minor
    for name in S["true"]:
        ok = mode_of("true", name) == minor
        g, l, p = kt.paired(b_ok[held], ok[held]); ga, la, pa = kt.paired(b_ok, ok)
        rows.append({"rule": name, "maj": acc(ok, ~minor), "min": acc(ok, minor), "bal": (acc(ok, ~minor) + acc(ok, minor)) / 2, "all": acc(ok, np.ones(n, bool)),
                     "sel_bal": (acc(ok, sel & ~minor) + acc(ok, sel & minor)) / 2, "held_bal": (acc(ok, held & ~minor) + acc(ok, held & minor)) / 2,
                     "held_maj": acc(ok, held & ~minor), "held_min": acc(ok, held & minor), "held_gain": g, "held_lost": l, "held_p": p, "all_gain": ga, "all_lost": la, "all_p": pa})
    rows.sort(key=lambda r: -r["bal"])
    print("\n## Ceiling: the true home note is given. Mode right, percent\n")
    print("| rule | major clips | minor clips | balanced | all clips | selection balanced | held-out balanced | held-out: gained / lost against the baseline | sign test p | all clips: gained / lost | p |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in rows:
        print(f"| {r['rule']} | {r['maj']:.1f} | {r['min']:.1f} | {r['bal']:.1f} | {r['all']:.1f} | {r['sel_bal']:.1f} | {r['held_bal']:.1f} | {r['held_gain']} / {r['held_lost']} | {r['held_p']:.3g} | {r['all_gain']} / {r['all_lost']} | {r['all_p']:.3g} |")
    untrained = [r for r in rows if not r["rule"].startswith("trained") and r["rule"] != "always minor"]
    pick = max(untrained, key=lambda r: r["sel_bal"])
    lo, hi = kt.wilson(int(round(pick["held_bal"] / 100 * held.sum())), int(held.sum()))
    print(f"\nBest untrained rule on the selection part: **{pick['rule']}** (selection balanced {pick['sel_bal']:.1f}); held-out balanced {pick['held_bal']:.1f} "
          f"(major {pick['held_maj']:.1f}, minor {pick['held_min']:.1f}); baseline held-out balanced {[r for r in rows if r['rule'] == base_name][0]['held_bal']:.1f}; "
          f"held-out paired against the baseline: gained {pick['held_gain']}, lost {pick['held_lost']}, p {pick['held_p']:.3g}")
    with open(os.path.join(kt.HERE, "mode_results.tsv"), "w") as fh:
        cols = list(rows[0]); fh.write("setting\t" + "\t".join(cols) + "\n")
        for r in rows: fh.write("true home note\t" + "\t".join(f"{r[c]:.4g}" if not isinstance(r[c], str) else r[c] for c in cols) + "\n")

        # ---- ship: the reader's home note
        for hn in ("B", "A"):
            t = tonic[hn]; home_ok = t == tt
            own = R[hn].argmax(1); own_ok = own == key
            print(f"\n## Ship: the home note is row {hn}'s (right on {100 * home_ok.mean():.1f} percent; major {acc(home_ok, ~minor):.1f}, minor {acc(home_ok, minor):.1f}). Exact key, percent\n")
            print("| mode rule | all | major | minor | on Apple's 1,270: major | minor | held-out: major | minor | held-out: gained / lost against row " + hn + " | p | all: gained / lost | p |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
            def line(name, ok):
                g, l, p = kt.paired(own_ok[held], ok[held]); ga, la, pa = kt.paired(own_ok, ok)
                print(f"| {name} | {acc(ok, np.ones(n, bool)):.1f} | {acc(ok, ~minor):.1f} | {acc(ok, minor):.1f} | {acc(ok, has_ap & ~minor):.1f} | {acc(ok, has_ap & minor):.1f} | "
                      f"{acc(ok, held & ~minor):.1f} | {acc(ok, held & minor):.1f} | {g} / {l} | {p:.3g} | {ga} / {la} | {pa:.3g} |")
                fh.write(f"home note of row {hn}\t{name}\t" + "\t".join(f"{x:.4g}" for x in (acc(ok, ~minor), acc(ok, minor), 0, acc(ok, np.ones(n, bool)), 0, 0, acc(ok, held & ~minor), acc(ok, held & minor), g, l, p, ga, la, pa)) + "\n")
            line(f"row {hn} itself (24-key match)", own_ok)
            line("perfect mode (the limit: the home note's own score)", home_ok)
            order = sorted(S[hn], key=lambda nm: -((acc((mode_of(hn, nm) == minor) & home_ok, ~minor) + acc((mode_of(hn, nm) == minor) & home_ok, minor)) / 2))
            for name in order: line(name, (mode_of(hn, name) == minor) & home_ok)
            a_ok = ap == key
            print(f"\nApple on its 1,270: major {acc(a_ok, has_ap & ~minor):.1f}, minor {acc(a_ok, has_ap & minor):.1f}; the bar is {acc(a_ok, has_ap & ~minor) - kt.BAR_MARGIN:.1f} and {acc(a_ok, has_ap & minor) - kt.BAR_MARGIN:.1f}.")

    # ---- per clip, the main rules
    main_rules = [base_name, pick["rule"], "trained: logistic regression on row A chroma (12 numbers)", "trained: logistic regression on every measurement (135 numbers)",
                  "trained: logistic regression on every measurement, classes balanced", "trained: boosted trees on every measurement"]
    with open(os.path.join(kt.HERE, "mode_clips.tsv"), "w") as fh:
        fh.write("id\tkey\tfold\thome_B\thome_A\t" + "\t".join(f"true_home|{m}\tB_home|{m}" for m in main_rules) + "\n")
        for i in range(n):
            fh.write(f"{ids[i]}\t{kt.key_name(key[i])}\t{fo[i]}\t{kt.NOTE[tonic['B'][i]]}\t{kt.NOTE[tonic['A'][i]]}\t" +
                     "\t".join(("minor" if mode_of("true", m)[i] else "major") + "\t" + ("minor" if mode_of("B", m)[i] else "major") for m in main_rules) + "\n")

    # ---- the trained rules across sets: fitted on all of MTG, scored on GiantSteps Key (604)
    gp = os.path.join(kt.CACHE, "modefeats_gs.npz")
    if os.path.exists(gp):
        G = np.load(gp); gpos = {i: k for k, i in enumerate(G["ids"])}; GR = np.load(os.path.join(kt.CACHE, "readers_gs.npz")); grpos = {i: k for k, i in enumerate(GR["ids"])}
        gc = [c for c in kt.load("gs") if c["key"] is not None and c["id"] in gpos]
        gnames = set().union(*[c["names"] for c in gc]); clean = np.array([not (c["names"] & gnames) for c, _ in keep])
        gx = np.array([gpos[c["id"]] for c in gc]); FG = {k: G[k][gx].astype(np.float64) for k in G.files if k != "ids"}
        RG = {k: GR[k][np.array([grpos[c["id"]] for c in gc])].astype(np.float64) for k in ("3f", "A", "B")}
        gk = np.array([c["key"] for c in gc]); gt = gk % 12; gm = gk >= 12; gtB = RG["B"].argmax(1) % 12
        print(f"\n## Across sets: GiantSteps Key ({len(gk)} clips: {int((~gm).sum())} major, {int(gm.sum())} minor). Trained rules fitted on the {int(clean.sum())} MTG clips that share no artist with it\n")
        print("| rule | true home note: mode right, major | minor | balanced | row B's home note: exact, all | major | minor |\n|---|---:|---:|---:|---:|---:|---:|")
        GS_ = rules(FG, RG, gt); GSB = rules(FG, RG, gtB)
        for name, feats, kind in TRAINED:
            _, m = fit_predict(kind, design(sub(F, clean), tt[clean], feats), minor[clean].astype(int), design(FG, gt, feats))
            GS_[name] = m.predict_proba(design(FG, gt, feats))[:, 1] - 0.5; GSB[name] = m.predict_proba(design(FG, gtB, feats))[:, 1] - 0.5
        own_ok = RG["B"].argmax(1) == gk
        print(f"| row B itself (24-key match) | | | | {100 * own_ok.mean():.1f} | {acc(own_ok, ~gm):.1f} | {acc(own_ok, gm):.1f} |")
        for name in [base_name, pick["rule"], "always minor"] + [x[0] for x in TRAINED]:
            ok = (GS_[name] > 0) == gm; okb = ((GSB[name] > 0) == gm) & (gtB == gt)
            print(f"| {name} | {acc(ok, ~gm):.1f} | {acc(ok, gm):.1f} | {(acc(ok, ~gm) + acc(ok, gm)) / 2:.1f} | {100 * okb.mean():.1f} | {acc(okb, ~gm):.1f} | {acc(okb, gm):.1f} |")

if __name__ == "__main__":
    main()
