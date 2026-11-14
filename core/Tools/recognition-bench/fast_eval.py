#!/usr/bin/env python3
"""The speed study's tables: how long the listener takes to name a song (docs/research/w5-recognition-by-five-seconds.md).

  fast_eval.py starts WORK READINGS [LABEL]    from deckie-listen's readings of WORK/fast/clips.tsv (30 s clips made by
                                               make_queries.py fast): seconds from a song's start of play to its first
                                               right name, per condition; hard cuts; wrong names; one summary row
  fast_eval.py blends WORK UNMIX READINGS      from its readings of the generated mixes: seconds from the start of a
                                               fade, and from its middle, to the incoming song's name and to its
                                               first appearance as "coming in"

Only the eval half is tabled (dev clips are for choosing thresholds: `tune`).
  fast_eval.py tune WORK TRACE                 from a --no-follow --trace run on the dev clips: false names and names by
                                               5 s for a grid of thresholds
"""
import glob, json, os, sys
from collections import defaultdict
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

MARKS = (3, 4, 5, 6, 8, 12)
ORDER = ["clean", "room", "room+crowd+10", "room+crowd0", "room+crowd-5", "booth(speaker+room+crowd0)"]
NAMES = {"clean": "clean", "room": "room", "room+crowd+10": "room, crowd 10 dB under", "room+crowd0": "room, crowd at equal level",
         "room+crowd-5": "room, crowd 5 dB over the music", "booth(speaker+room+crowd0)": "small speaker, room, crowd at equal level"}


RELATED = {}


def related(path):
    """Songs the index holds to be the same sound as another (deckie-listen --related-out): naming one of them is
    naming the song, as it is for the listener itself."""
    if path and os.path.exists(path):
        for l in open(path):
            a, b = l.rstrip("\n").split("\t")
            RELATED.setdefault(a, set()).add(b); RELATED.setdefault(b, set()).add(a)


def same(answer, song):
    return answer == song or answer in RELATED.get(song, ())


def load(work, path):
    related(path[:-4] + ".related")
    truth = {t["qid"]: t for t in (json.loads(l) for l in open(os.path.join(work, "fast", "truth.jsonl")))}
    by = defaultdict(list)
    for l in open(path):
        f = l.rstrip("\n").split("\t")
        if len(f) >= 9:
            by[f[0]].append(f)
    return truth, by


def first_right(rs, song, after=0.0):
    for f in rs:
        if f[2] != "nothingYet" and same(f[3], song) and float(f[1]) > after:
            return float(f[1]) - after
    return None


def dist(times, total):
    got = np.array(sorted(t for t in times if t is not None))
    def q(p):
        # A percentile of all clips, the never-named ones counted as later than any.
        k = int(np.ceil(p * total)) - 1
        return f"{got[k]:.0f}" if k < len(got) else "over 30"
    return q(0.5), q(0.75), q(0.9), 100 * (total - len(got)) / max(1, total), [100 * float(np.sum(got <= m)) / max(1, total) for m in MARKS]


def starts(work, path, label=None):
    truth, by = load(work, path)
    cells = defaultdict(list); wrong = defaultdict(int); cuts = defaultdict(list); cut_wrong = defaultdict(int)
    absent = [0, 0]; ms = []; search_ms = []
    for q, rs in by.items():
        t = truth[q]
        if t.get("split", t["role"]) != "eval":
            continue
        ms += [float(f[8]) for f in rs]
        search_ms += [float(f[8]) for f in rs if f[2] == "nothingYet"]
        if t["role"] == "absent":
            # A held-out clip that is the same track as an indexed clip under another id is not "not in the index".
            if t["bucket"] != "noise" and t["song"].startswith("g3367551"):
                continue
            absent[1] += 1; absent[0] += any(f[2] != "nothingYet" for f in rs)
        elif t["cell"] == "cut":
            cuts[t["condition"]].append(first_right(rs, t["song"], t["cut_at"]))
            cut_wrong[t["condition"]] += any(f[2] != "nothingYet" and not same(f[3], t["song"]) and not same(f[3], t["before"]) for f in rs)
        else:
            cells[t["condition"]].append(first_right(rs, t["song"]))
            wrong[t["condition"]] += any(f[2] != "nothingYet" and not same(f[3], t["song"]) for f in rs)
    print("| condition | clips | seconds to the first right name: median / 75th / 90th percentile | never named in 30 s, % | named by " +
          " / ".join(f"{m}" for m in MARKS) + " s, % of clips | a wrong song named, % of clips |")
    print("|---|---|---|---|---|---|")
    summary = {}
    for c in ORDER:
        if c not in cells:
            continue
        a, b, d, never, by_mark = dist(cells[c], len(cells[c]))
        summary[c] = by_mark[MARKS.index(5)]
        print(f"| {NAMES[c]} | {len(cells[c])} | {a} / {b} / {d} | {never:.0f} | " + " / ".join(f"{x:.0f}" for x in by_mark) + f" | {100 * wrong[c] / len(cells[c]):.1f} |")
    if cuts:
        print("\n| hard cut to the song (15 s of another song first) | clips | seconds from the cut to the first right name: median / 75th / 90th | never in 30 s, % | named by " +
              " / ".join(f"{m}" for m in MARKS) + " s after the cut, % | a song that is neither named, % of clips |")
        print("|---|---|---|---|---|---|")
        for c in ORDER:
            if c in cuts:
                a, b, d, never, by_mark = dist(cuts[c], len(cuts[c]))
                summary["cut " + c] = by_mark[MARKS.index(5)]
                print(f"| {NAMES[c]} | {len(cuts[c])} | {a} / {b} / {d} | {never:.0f} | " + " / ".join(f"{x:.0f}" for x in by_mark) + f" | {100 * cut_wrong[c] / len(cuts[c]):.1f} |")
    ms = np.array(ms); sm = np.array(search_ms) if search_ms else np.array([0.0])
    total_wrong = sum(wrong.values()); total = sum(len(v) for v in cells.values())
    print(f"\nSongs not in the index (and noise alone) named within 30 s: {absent[0]} of {absent[1]} clips. A wrong song named: {total_wrong} of {total} clips. "
          f"A reading took {np.median(ms):.0f} ms at the median and {np.quantile(ms, 0.95):.0f} at the 95th percentile; a reading that searched and named nothing, {np.median(sm):.0f} and {np.quantile(sm, 0.95):.0f}.")
    if label:
        row = dict(label=label, by5={c: summary.get(c) for c in ORDER}, cut5={c: summary.get("cut " + c) for c in ORDER if "cut " + c in summary},
                   wrong=[total_wrong, total], absent=absent, ms=[float(np.median(ms)), float(np.quantile(ms, 0.95))],
                   search_ms=[float(np.median(sm)), float(np.quantile(sm, 0.95))])
        with open(os.path.join(work, "fast", "rows.jsonl"), "a") as f:
            f.write(json.dumps(row) + "\n")


def curve(work, names):
    """The size curve: one row a setting (WORK/fast/r_<name>.tsv and ix_<name>.dkx), the second by which half, three
    quarters and nine in ten of the songs are named in each condition, the share named by 5 s, wrong names, size."""
    songs = [l.rstrip("\n").split("\t") for l in open(os.path.join(work, "songs.tsv"))]
    minutes = sum(float(x[3]) for x in songs if x[4] != "absent") / 60
    out = []
    for name in names:
        path = os.path.join(work, "fast", f"r_{name}.tsv")
        if not os.path.exists(path):
            continue
        RELATED.clear()
        truth, by = load(work, path)
        cells = defaultdict(list); cuts = defaultdict(list); wrong = 0; total = 0; absent = [0, 0]; sm = []
        for q, rs in by.items():
            t = truth[q]
            if t.get("split", t["role"]) != "eval":
                continue
            sm += [float(f[8]) for f in rs if f[2] == "nothingYet"]
            if t["role"] == "absent":
                if t["bucket"] != "noise" and t["song"].startswith("g3367551"):
                    continue
                absent[1] += 1; absent[0] += any(f[2] != "nothingYet" for f in rs)
            elif t["cell"] == "cut":
                cuts[t["condition"]].append(first_right(rs, t["song"], t["cut_at"]))
            else:
                cells[t["condition"]].append(first_right(rs, t["song"]))
                total += 1; wrong += any(f[2] != "nothingYet" and not same(f[3], t["song"]) for f in rs)
        size = os.path.getsize(os.path.join(work, "fast", f"ix_{name}.dkx"))
        # The table's 2 million counters are a fixed 8.4 MB whatever the crate; the rest grows with the music.
        fixed = (1 << 21) * 4 / 1e6
        out.append(dict(name=name, kb_min=(size / 1e6 - fixed) * 1e3 / minutes, cells=cells, cuts=cuts, wrong=wrong, total=total, absent=absent,
                        search=float(np.median(sm)) if sm else 0))
    print("| setting | index, KB a minute of music | index for 2,000 / 5,000 songs of 4.2 min, MB | " +
          " | ".join(NAMES[c] for c in ORDER) + " | hard cut, clean | hard cut, crowd at equal level | wrong song named, clips | not-in-index song named, clips | a search, ms |")
    print("|---|---|---|" + "---|" * (len(ORDER) + 5))
    for r in out:
        def three(v):
            a, b, d, _, _ = dist(v, len(v))
            return f"{a} / {b} / {d}"
        print(f"| {r['name']} | {r['kb_min']:.1f} | {r['kb_min'] * 4.2 * 2 + 8.4:.0f} / {r['kb_min'] * 4.2 * 5 + 8.4:.0f} | " + " | ".join(three(r["cells"][c]) for c in ORDER) +
              f" | {three(r['cuts']['clean'])} | {three(r['cuts']['room+crowd0'])} | {r['wrong']} of {r['total']} | {r['absent'][0]} of {r['absent'][1]} | {r['search']:.0f} |")
    print("\n| setting | named by 5 s, % of clips: " + " | ".join(NAMES[c] for c in ORDER) + " | hard cut, clean | hard cut, crowd 10 dB under | hard cut, crowd at equal level |")
    print("|---|" + "---|" * (len(ORDER) + 3))
    for r in out:
        five = lambda v: f"{dist(v, len(v))[4][MARKS.index(5)]:.0f}"
        print(f"| {r['name']} | " + " | ".join(five(r["cells"][c]) for c in ORDER) + f" | {five(r['cuts']['clean'])} | {five(r['cuts']['room+crowd+10'])} | {five(r['cuts']['room+crowd0'])} |")


def blends(work, unmix, path):
    import unmix_eval
    related(path[:-4] + ".related")
    by = defaultdict(list)
    for l in open(path):
        f = l.rstrip("\n").split("\t")
        if len(f) >= 9:
            by[f[0]].append(f)
    rows = defaultdict(lambda: dict(start=[], middle=[], coming=[], n=0, wrong_coming=0, coming_readings=0))
    for lab in glob.glob(os.path.join(unmix, "**", "mixes", "*.labels.txt"), recursive=True):
        mix = os.path.basename(lab)[:-len(".labels.txt")]
        if mix not in by:
            continue
        tracks = unmix_eval.labels(lab)
        ids = {k: unmix_eval.ref_id(t["name"]) for k, t in tracks.items() if "name" in t}
        parts = mix.split("-")
        o = rows[(parts[1], parts[2])]
        inside = set(ids.values())
        for f in by[mix]:
            if len(f) > 9 and f[-4] != "-":
                o["coming_readings"] += 1
                o["wrong_coming"] += not any(same(f[-4], x) for x in inside)
        for k in sorted(tracks):
            if k == min(tracks) or "fadein" not in tracks[k] or k not in ids or abs(tracks[k].get("speed", 1) - 1) > 0.16:
                continue
            a, b = tracks[k]["fadein"]
            o["n"] += 1
            named = first_right(by[mix], ids[k], a)
            coming = next((float(f[1]) - a for f in by[mix] if float(f[1]) > a and len(f) > 9 and f[-4] == ids[k]), None)
            o["start"].append(named)
            o["middle"].append(None if named is None else named - (b - a) / 2)
            o["coming"].append(coming if coming is not None and (named is None or coming < named) else named)
            o.setdefault("fade", []).append(b - a)
    print("| time scaling | effect | incoming songs | fade length, median s | seconds from the fade's start to the name: median / 75th / 90th | seconds from the fade's middle (equal loudness) to the name: median / 75th / 90th | seconds from the fade's start to \"coming in\" or the name, whichever is first: median / 75th / 90th | \"coming in\" readings naming a song outside the mix |")
    print("|---|---|---|---|---|---|---|---|")
    for key in sorted(rows):
        o = rows[key]
        if not o["n"]:
            continue
        def three(v):
            got = sorted(x for x in v if x is not None)
            def q(p):
                k = int(np.ceil(p * len(v))) - 1
                return f"{got[k]:.0f}" if k < len(got) else "never"
            return f"{q(0.5)} / {q(0.75)} / {q(0.9)}"
        print(f"| {key[0]} | {key[1]} | {o['n']} | {np.median(o['fade']):.0f} | {three(o['start'])} | {three(o['middle'])} | {three(o['coming'])} | {o['wrong_coming']} of {o['coming_readings']} |")


def tune(work, path):
    truth, by = load(work, path)
    print("sure fair | no right answer: named /clips | wrong /clips | named by 5 s: " + " | ".join(NAMES[c][:18] for c in ORDER))
    for sure in (2.4, 2.6, 2.8, 3.0, 3.2):
        for fair in (99, 2.6, 2.4, 2.2, 2.0, 1.8):
            if fair < 99 and fair >= sure:
                continue
            ab = [0, 0]; wr = [0, 0]; cell = defaultdict(lambda: [0, 0])
            for q, rs in by.items():
                t = truth[q]
                if t.get("split", t["role"]) != "dev":
                    continue
                name = None; prev = 0.0
                for f in rs:
                    conf = float(f[10]); agrees = f[11] == "agrees"
                    if conf >= sure or (conf >= fair and agrees and prev >= fair):
                        name = (float(f[1]), f[9]); break
                    prev = conf
                if t["role"] == "absent":
                    ab[1] += 1; ab[0] += name is not None
                else:
                    wr[1] += 1; wr[0] += name is not None and name[1] != t["song"]
                    c = cell[t["condition"]]; c[1] += 1; c[0] += name is not None and name[1] == t["song"] and name[0] <= 5
            print(f"{sure} {fair:4} | {ab[0]:3d}/{ab[1]} | {wr[0]:2d}/{wr[1]} | " + " | ".join(f"{100 * cell[c][0] / max(1, cell[c][1]):.0f}" for c in ORDER))


if __name__ == "__main__":
    if sys.argv[1] == "starts":
        starts(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    elif sys.argv[1] == "curve":
        curve(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == "blends":
        blends(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        tune(sys.argv[2], sys.argv[3])
