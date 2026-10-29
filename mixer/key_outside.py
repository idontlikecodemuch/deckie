#!/usr/bin/env python3
"""Research R, outside test: the recommended key method (key_parity.recommended, row 3f) and the shipped engine's
(row 0: STFT chroma at 22.05 kHz, edma) on the Beatport EDM Key Dataset (GiantSteps-MTG-key; Faraldo 2017; Zenodo
10.5281/zenodo.1101082, CC BY-SA 4.0). The audio is third-party and for internal evaluation only: it is never
committed and never ships. This script only reads the data set's files by path; it imports nothing from them.

  .venv/bin/python key_outside.py --data <folder with audio/ and Beatport-EDM-Key-Dataset.xlsx> [--jobs 8] [--limit N]

<data>/audio/ holds the clips as <beatport id>.mp3 (or any file name that starts with the id). Run from mixer/.
Writes key_outside_results.tsv (per clip) and prints the summary."""
import csv, os, re, sys, time, zipfile, warnings
from collections import Counter
import xml.etree.ElementTree as ET
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import key_light as KL
import key_parity as KP

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8,
      "A": 9, "A#": 10, "Bb": 10, "B": 11}
CLEAN = re.compile(r"^([A-G][#b]?) ?(maj(?:or)?|min(?:or)?)$")

def to_camelot(ann):
    """'A minor', 'F# major', 'Ab major' -> Camelot, with key_light's tables. None for X, unknown, 'other', modal
    names ('phrygian'), key changes and two-key labels ('A minor | A major')."""
    m = CLEAN.match(ann.strip())
    if m and m.group(1) not in PC: m = None
    if m: m = (m.group(1), "major" if m.group(2).startswith("maj") else "minor")
    if not m: return None
    return KL.camelot(PC[m[0]], m[1])

def read_annotations(xlsx):
    """id -> dict(main_key, confidence, camelot, changed) from the data set's spreadsheet (stdlib XML only)."""
    M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    z = zipfile.ZipFile(xlsx)
    ss = ["".join(t.text or "" for t in si.iter(M + "t")) for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(M + "si")]
    out = {}; head = None
    for r in ET.fromstring(z.read("xl/worksheets/sheet1.xml")).iter(M + "row"):
        d = {}
        for c in r.findall(M + "c"):
            v = c.find(M + "v")
            if v is None: continue
            d[re.match("[A-Z]+", c.get("r")).group()] = ss[int(v.text)] if c.get("t") == "s" else v.text
        if head is None: head = {k: v for k, v in d.items()}; continue
        row = {head[k]: v for k, v in d.items() if k in head}
        out[row["id"]] = {"main_key": row.get("main_key", ""), "confidence": int(row.get("confidence", "-1")),
                          "camelot": to_camelot(row.get("main_key", "")), "changed": bool(row.get("change1"))}
    return out

def one(item):
    cid, path = item
    try:
        import librosa
        y, _ = KP.load44(path)
        cam, margin, agree, sure = KP.recommended(y)
        y22 = librosa.resample(y, orig_sr=KP.SR44, target_sr=KP.SR22, res_type="soxr_hq")
        S = np.abs(librosa.stft(y22, n_fft=KP.N22, hop_length=KP.H22)) ** 2
        C0 = librosa.feature.chroma_stft(S=S, sr=KP.SR22, n_fft=KP.N22, hop_length=KP.H22, tuning=0.0)
        r0 = KP.corr24(C0.T.mean(axis=0), KP.km("edma")); base = KP.cam24(int(np.argmax(r0)))
        return cid, (cam, margin, agree, sure, base), None
    except Exception as e:
        return cid, None, str(e)

MIREX = {"exact": 1.0, "fifth": 0.5, "relative": 0.3, "parallel": 0.2}

def summarise(rows, key="pred"):
    """rows: dicts with camelot (reference) and the prediction under `key`. Returns the figures as percent."""
    n = len(rows)
    if not n: return {"n": 0}
    rel = [KP.relation(r[key], r["camelot"]) for r in rows]
    fine = Counter(f for _, f in rel); coarse = Counter(c for c, _ in rel)
    miss = [(r[key], r["camelot"]) for r in rows if r[key] != r["camelot"]]
    m2n = sum(1 for p, a in miss if p[-1] == "A" and a[-1] == "B"); n2m = sum(1 for p, a in miss if p[-1] == "B" and a[-1] == "A")
    mirex = sum(MIREX.get(f, 0.0) for f in (x[1] for x in rel)) / n
    return {"n": n, "exact": 100 * coarse["exact"] / n, "neighbour": 100 * coarse["neighbour"] / n, "other": 100 * coarse["other"] / n,
            "mirex": 100 * mirex, "relative": 100 * fine["relative"] / n, "fifth": 100 * fine["fifth"] / n,
            "parallel": 100 * fine["parallel"] / n, "major_as_minor": 100 * m2n / n, "minor_as_major": 100 * n2m / n}

def show(label, s):
    if not s["n"]: print(f"  {label:34} n 0"); return
    print(f"  {label:34} n {s['n']:4}  exact {s['exact']:5.1f}  neighbour {s['neighbour']:5.1f}  other {s['other']:5.1f}  MIREX {s['mirex']:5.1f}"
          f"   | relative {s['relative']:4.1f} fifth {s['fifth']:4.1f} parallel {s['parallel']:4.1f}  maj->min {s['major_as_minor']:4.1f} min->maj {s['minor_as_major']:4.1f}")

def main():
    a = sys.argv
    if "--data" not in a: print(__doc__); return
    data = a[a.index("--data") + 1]; jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 8
    limit = int(a[a.index("--limit") + 1]) if "--limit" in a else 10 ** 6
    ann = read_annotations(os.path.join(data, "Beatport-EDM-Key-Dataset.xlsx"))
    files = {}
    for root, _, fs in os.walk(os.path.join(data, "audio")):
        for f in fs:
            if f.lower().endswith((".mp3", ".wav", ".flac", ".m4a")) and not f.startswith("."):
                m = re.match(r"(\d+)", f)
                if m: files[m.group(1)] = os.path.join(root, f)
    todo = [(i, files[i]) for i in sorted(ann, key=int) if ann[i]["camelot"] and i in files][:limit]
    print(f"annotated rows {len(ann)}, with a plain 'note major/minor' label {sum(1 for v in ann.values() if v['camelot'])}, "
          f"audio files {len(files)}, scoring {len(todo)}", file=sys.stderr)
    from multiprocessing import Pool
    res = {}; errs = []; t0 = time.time()
    with Pool(jobs) as pool:
        for k, (cid, r, err) in enumerate(pool.imap_unordered(one, todo, chunksize=4), 1):
            if err: errs.append((cid, err))
            else: res[cid] = r
            if k % 100 == 0: print(f"{k}/{len(todo)} {time.time() - t0:.0f}s", file=sys.stderr)
    rows = []
    for cid, _ in todo:
        if cid not in res: continue
        cam, mg, ag, sure, base = res[cid]; v = ann[cid]
        rows.append({"id": cid, "annotation": v["main_key"], "camelot": v["camelot"], "pred": cam, "margin": mg, "agree": ag, "sure": sure,
                     "relation": KP.relation(cam, v["camelot"])[1], "base": base, "base_relation": KP.relation(base, v["camelot"])[1],
                     "confidence": v["confidence"], "changed": v["changed"]})
    with open(os.path.join(HERE, "key_outside_results.tsv"), "w") as fh:
        fh.write("id\tannotation\tcamelot\tpredicted\tmargin\tsure\trelation\tagree\tbaseline_predicted\tbaseline_relation\tdataset_confidence\n")
        for r in rows:
            fh.write(f"{r['id']}\t{r['annotation']}\t{r['camelot']}\t{r['pred']}\t{r['margin']:.4f}\t{int(r['sure'])}\t{r['relation']}\t{r['agree']}\t"
                     f"{r['base']}\t{r['base_relation']}\t{r['confidence']}\n")
    print(f"\nscored {len(rows)} clips, {len(errs)} errors {errs[:3]}")
    subsets = [("all with a plain key", rows), ("high confidence (2)", [r for r in rows if r["confidence"] == 2]),
               ("high confidence, no key change", [r for r in rows if r["confidence"] == 2 and not r["changed"]])]
    for nm, sub in subsets:
        print(f"\n{nm}")
        show("3f recommended", summarise(sub)); show("0 shipped (STFT, edma)", summarise(sub, "base"))
    hc = subsets[1][1]
    for nm, sub in (("high confidence, major keys", [r for r in hc if r["camelot"][-1] == "B"]), ("high confidence, minor keys", [r for r in hc if r["camelot"][-1] == "A"]),
                    ("all, major keys", [r for r in rows if r["camelot"][-1] == "B"]), ("all, minor keys", [r for r in rows if r["camelot"][-1] == "A"])):
        print(f"\n{nm}")
        show("3f recommended", summarise(sub)); show("0 shipped (STFT, edma)", summarise(sub, "base"))
    for nm, sub in (("all", rows), ("high confidence", hc)):
        s = [r for r in sub if r["sure"]]; u = [r for r in sub if not r["sure"]]
        ex = lambda L: 100 * sum(r["pred"] == r["camelot"] for r in L) / len(L) if L else float("nan")
        print(f"\nsure flag, {nm}: sure {len(s)} of {len(sub)} ({100 * len(s) / max(1, len(sub)):.1f} percent), exact among sure {ex(s):.1f}, among unsure {ex(u):.1f}")
    print("\nmean margin: exact reads %.3f, misses %.3f" % (np.mean([r["margin"] for r in hc if r["pred"] == r["camelot"]]), np.mean([r["margin"] for r in hc if r["pred"] != r["camelot"]])))

if __name__ == "__main__":
    main()
