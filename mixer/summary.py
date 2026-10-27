#!/usr/bin/env python3
"""One row per analysed track -> summary.md + summary.tsv (doubtful grids first).

  .venv/bin/python summary.py
"""
import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
COLS = ["id", "title", "bpm_tag", "bpm", "multiplier", "grid_conf", "key", "key_conf", "lufs",
        "vocal_mean", "mix_in_bars", "mix_out_bars", "flags"]


def main():
    rows = []
    for f in sorted(glob.glob(os.path.join(HERE, "features", "*.json"))):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        rows.append({
            "id": d["id"], "title": f"{d.get('title') or ''} {d.get('ver') or ''}".strip(),
            "bpm_tag": d.get("bpm_tag"), "bpm": round(d["bpm"], 2), "multiplier": d.get("multiplier_vs_tag"),
            "grid_conf": round(d["grid"]["confidence"], 2), "key": d["key"]["camelot"],
            "key_conf": d["key"]["confidence"], "lufs": d["loudness"]["integrated_lufs"],
            "vocal_mean": round(d["vocal"]["mean_prob"], 2),
            "mix_in_bars": d["mix_in"]["bars"], "mix_out_bars": d["mix_out"]["bars"],
            "flags": ",".join(d.get("flags", [])),
        })
    rows.sort(key=lambda r: (r["grid_conf"], r["title"]))
    with open(os.path.join(HERE, "summary.tsv"), "w") as f:
        f.write("\t".join(COLS) + "\n")
        for r in rows:
            f.write("\t".join("" if r[c] is None else str(r[c]) for c in COLS) + "\n")
    md = [f"# Analysis summary ({len(rows)} tracks)", "",
          "Sorted by beat-grid confidence, lowest first. multiplier = final BPM / tag BPM.", "",
          "| " + " | ".join(COLS[1:]) + " |", "|" + "---|" * (len(COLS) - 1)]
    for r in rows:
        md.append("| " + " | ".join(str(r[c]).replace("|", "/") if r[c] is not None else "" for c in COLS[1:]) + " |")
    open(os.path.join(HERE, "summary.md"), "w").write("\n".join(md) + "\n")
    print(f"wrote summary.md / summary.tsv ({len(rows)} tracks)")


if __name__ == "__main__":
    main()
