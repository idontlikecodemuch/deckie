"""Letter T, avenue 3: saying "key unsure" from what we already have. For a few abstain rules written down here before
the sheets were scored, the share of outside clips each rule keeps (calls sure), and the exact and home-note rates on
the kept clips and on the rest, on the odd and even halves of key_overtones.py's split separately. Nothing is chosen
and nothing is fitted: every rule is shown, and the only inputs are the committed per-clip sheets.

Data: the outside set (GiantSteps-MTG-key, the Beatport EDM Key Dataset; Faraldo 2017; Zenodo 10.5281/zenodo.1101082,
annotations CC BY-SA 4.0), the 1,275 plain-key clips, from key_overtones.tsv. Three of our rows: 3f (letter R's
recommended reader), A = A-both-frame-H4w (harmonic discount), B = B-s07-full-faraldo (NNLS note transcription). Each
row carries its key, its relation to the annotation, its margin and its sure flag (3f's rule: the three Faraldo
profiles agree and the margin is at least 0.08). Apple's key per clip (key_outside_apple.tsv, rescored with
key_parity.relation) is shown beside the kept and rest clips only to say whether a rule keeps the clips that are easy
for every reader; Apple's key is not an input to any rule.

Rules, fixed before the run (the key reported on a kept clip, then the key shown, flagged unsure, on the rest):
  all       every clip kept; key B (the reference row, no abstaining)
  3f-sure   3f's own sure flag; key 3f on kept and on rest
  B-sure    B's sure flag (the same rule computed on B's profile match); key B on kept and on rest
  three     3f, A and B give the same key; that key; B on the rest
  two       at least two of the three give the same key; the majority key; B on the rest (all three differ)
  home3     3f, A and B give the same home note (the tonic, mode ignored); key B on kept and on rest
  three+B   three agree and B is sure; that key; B on the rest
Home note = exact or parallel (the same tonic, either mode). Exact and parallel come from key_parity.relation.
Printed first: each reader alone (3f, A, B, Apple) by half and by mode, the "where we stand" table of letter T. The
halves here hold every confidence level (652 odd, 623 even), not only key_overtones.py's confidence-2 halves.

usage (from mixer/): .venv/bin/python key_abstain.py [out.tsv]
"""
import csv, os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import key_parity as KP

HERE = os.path.dirname(os.path.abspath(__file__))
ROWS = ("3f", "A-both-frame-H4w", "B-s07-full-faraldo")

def tonic(cam):
    """Tonic pitch class of a Camelot code (minor 'A' sits three semitones below its relative major 'B')."""
    n, l = int(cam[:-1]), cam[-1]
    major = (7 * (n - 8)) % 12  # 8B = C major; each wheel step is a fifth
    return major if l == "B" else (major - 3) % 12

def rules(r):
    """(kept, key reported) per rule for one clip."""
    k3, ka, kb = (r[x] for x in ROWS)
    cnt = collections.Counter((k3, ka, kb)); top, n = cnt.most_common(1)[0]
    same_home = len({tonic(k3), tonic(ka), tonic(kb)}) == 1
    b_sure = r["B-s07-full-faraldo_sure"] == "1"
    return {
        "all": (True, kb),
        "3f-sure": (r["3f_sure"] == "1", k3),
        "B-sure": (b_sure, kb),
        "three": (n == 3, top if n == 3 else kb),
        "two": (n >= 2, top if n >= 2 else kb),
        "home3": (same_home, kb),
        "three+B": (n == 3 and b_sure, top if n == 3 else kb),
    }

def score(key, truth):
    rel = KP.relation(key, truth)[1]
    return rel == "exact", rel in ("exact", "parallel")

def main(out_tsv):
    clips = list(csv.DictReader(open(os.path.join(HERE, "key_overtones.tsv")), delimiter="\t"))
    apple = {r["id"]: r["apple"] for r in csv.DictReader(open(os.path.join(HERE, "key_outside_apple.tsv")), delimiter="\t")}
    print("reader\thalf\tmode\tn\texact\thome")
    for half in ("odd", "even", "all"):
        for mode in ("all", "major", "minor"):
            for name, col in (("3f", "3f"), ("A", ROWS[1]), ("B", ROWS[2]), ("Apple", "apple")):
                sub = [c for c in clips if (half == "all" or c["half"] == half) and (mode == "all" or
                       (c["camelot"][-1] == "B") == (mode == "major")) and (col != "apple" or apple.get(c["id"]))]
                key = (lambda c: apple[c["id"]]) if col == "apple" else (lambda c: c[col])
                sc = [score(key(c), c["camelot"]) for c in sub]
                print(f"{name}\t{half}\t{mode}\t{len(sub)}\t{100 * sum(e for e, _ in sc) / len(sc):.1f}\t"
                      f"{100 * sum(h for _, h in sc) / len(sc):.1f}")
    print()
    names = list(rules(clips[0]).keys()); out = []
    for half in ("odd", "even", "all"):
        sub = [c for c in clips if half == "all" or c["half"] == half]
        for name in names:
            acc = {g: collections.Counter() for g in ("kept", "rest")}
            for c in sub:
                kept, key = rules(c)[name]; g = acc["kept" if kept else "rest"]
                ex, home = score(key, c["camelot"]); g["n"] += 1; g["ex"] += ex; g["home"] += home
                if apple.get(c["id"]):
                    aex, ahome = score(apple[c["id"]], c["camelot"]); g["an"] += 1; g["aex"] += aex; g["ahome"] += ahome
            def p(g, k, d="n"): return f"{100 * g[k] / g[d]:.1f}" if g[d] else ""
            k, rs = acc["kept"], acc["rest"]
            out.append(dict(half=half, rule=name, n=len(sub), kept=k["n"], kept_pct=f"{100 * k['n'] / len(sub):.1f}",
                            kept_exact=p(k, "ex"), kept_home=p(k, "home"), rest_exact=p(rs, "ex"), rest_home=p(rs, "home"),
                            apple_kept_exact=p(k, "aex", "an"), apple_kept_home=p(k, "ahome", "an"),
                            apple_rest_exact=p(rs, "aex", "an"), apple_rest_home=p(rs, "ahome", "an")))
    cols = list(out[0].keys())
    print("\t".join(cols))
    for row in out: print("\t".join(str(row[c]) for c in cols))
    if out_tsv:
        with open(out_tsv, "w") as f:
            w = csv.DictWriter(f, fieldnames=cols, delimiter="\t"); w.writeheader(); w.writerows(out)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
