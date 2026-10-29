#!/usr/bin/env python3
"""Write the reference numbers deckie-build's bench measures must reproduce: mixer/bench_mu.py's own functions
(fmeasure, key_relation, boundary_pr, pearson), imported unchanged from the lab, run on pairs of series taken from each
committed feature file in mixer/features/, so the Swift port is checked on real beat lists, keys and boundaries
without any audio. Needs nothing beyond Python's standard library (bench_mu.py imports only that).

  python3 -I core/Tools/make_bench_fixtures.py      # from anywhere

Per track (the lab's id), from its feature file f:
  beat_f       fmeasure(f["beats_s"], f["detected_beats_s"])           the fitted grid against the detected beats
  downbeat_f   fmeasure(f["downbeats_s"], f["detected_downbeats_s"])
  half_f       fmeasure(f["detected_beats_s"], f["detected_beats_s"][::2])
  key_rel      key_relation(f["key"]["camelot_madmom"], f["key"]["camelot"]), when madmom gave a key
  section_p, section_r   boundary_pr(the inner boundaries in seconds, the novelty peaks' bars in seconds, bar_s), as
               bench_mu.py turns bars into seconds
  pearson      pearson(f["per_bar"]["lufs_st"], f["per_bar"]["vocal_prob"])

Output: core/Tests/DeckieBuildTests/Fixtures/bench_parity.json
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "mixer"))
import bench_mu as lab  # noqa: E402  (the lab's module, read as it is; nothing in it runs on import)

FEAT = os.path.join(ROOT, "mixer", "features")
OUT = os.path.join(ROOT, "core", "Tests", "DeckieBuildTests", "Fixtures", "bench_parity.json")


def track(f):
    g = f["grid"]
    bar_s, fd, n = g["bar_s"], g["first_downbeat_s"], g["n_bars"]
    inner = [fd + (b - 1) * bar_s for b in (f.get("boundaries_bars") or []) if 1 < b < n]
    peaks = [fd + (b - 1) * bar_s for b, _ in (f.get("novelty_peaks") or [])]
    p, r = lab.boundary_pr(inner, peaks, bar_s)
    madmom = f["key"].get("camelot_madmom")
    return {
        "beat_f": lab.fmeasure(f["beats_s"], f["detected_beats_s"]),
        "downbeat_f": lab.fmeasure(f["downbeats_s"], f.get("detected_downbeats_s") or []),
        "half_f": lab.fmeasure(f["detected_beats_s"], f["detected_beats_s"][::2]),
        "key_rel": lab.key_relation(madmom, f["key"]["camelot"]) if madmom else None,
        "section_p": p, "section_r": r,
        "pearson": lab.pearson(f["per_bar"]["lufs_st"], f["per_bar"]["vocal_prob"]),
    }


def main():
    out = {}
    for name in sorted(os.listdir(FEAT)):
        if name.endswith(".json"):
            out[name[:-5]] = track(json.load(open(os.path.join(FEAT, name))))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:  # one track a line
        rows = (f"{json.dumps(k)}: {json.dumps(out[k], sort_keys=True)}" for k in sorted(out))
        fh.write("{\n" + ",\n".join(rows) + "\n}\n")
    print(f"wrote {OUT}: {len(out)} tracks")


if __name__ == "__main__":
    main()
