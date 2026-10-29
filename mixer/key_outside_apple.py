"""Apple's Music Understanding key on the outside set (GiantSteps-MTG-key), beside ours, on the clips the simulator
harness has finished. Reads <outdir>/<id>.mu.json written by tools/mubench (-manifest/-outdir) and
key_outside_results.tsv (ours), scores both against the annotation with bench_mu's Camelot and relation rules.

usage (from mixer/): .venv/bin/python key_outside_apple.py <mu outdir> [out.tsv]
"""
import json, glob, os, csv, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_mu as BM

def secs(t): return float(t["value"]) / float(t.get("timescale") or 1) if isinstance(t, dict) else float(t)

def main(outdir, out_tsv):
    here = os.path.dirname(os.path.abspath(__file__))
    ours = {r["id"]: r for r in csv.DictReader(open(os.path.join(here, "key_outside_results.tsv")), delimiter="\t")}
    apple, mine = collections.Counter(), collections.Counter(); rows = []
    for f in sorted(glob.glob(os.path.join(outdir, "*.mu.json"))):
        cid = os.path.basename(f).split(".")[0]; r = ours.get(cid)
        if not r: continue
        rngs = ((json.load(open(f)).get("key") or {}).get("ranges")) or []
        if not rngs: apple["unread"] += 1; continue
        best = max(rngs, key=lambda x: secs(x["range"]["duration"]))
        cam = BM.camelot(best["value"]); rel = BM.key_relation(cam, r["camelot"])
        rel_ours = r["relation"]
        apple[rel] += 1; mine[rel_ours] += 1
        rows.append(dict(id=cid, annotation=r["annotation"], camelot=r["camelot"], apple=cam, apple_relation=rel,
                         ours=r["predicted"], ours_relation=rel_ours, confidence=r.get("dataset_confidence", "")))
    n = len(rows)
    def pct(c, k): return 100 * c[k] / max(n, 1)
    print(f"{n} clips scored (Apple unread on {apple['unread']})")
    print(f"Apple: exact {pct(apple,'exact'):.1f}  neighbour {pct(apple,'neighbour'):.1f}  other {pct(apple,'other'):.1f}")
    ex = mine["exact"]; nb = mine["relative"] + mine["fifth"] + mine["neighbour"]; oth = n - ex - nb
    print(f"Ours:  exact {100*ex/max(n,1):.1f}  neighbour {100*nb/max(n,1):.1f}  other {100*oth/max(n,1):.1f}  (relation names as key_outside.py writes them: {dict(mine)})")
    if out_tsv:
        with open(out_tsv, "w") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), delimiter="\t"); w.writeheader(); w.writerows(rows)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
