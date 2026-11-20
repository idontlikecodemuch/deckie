#!/usr/bin/env python3
"""Tables from deckie-listen's readings of switch_clips.py's clips (docs/research/faster-listening-proposals.md).
Needs only numpy.

  switch_eval.py WORK ROLE LABEL=READINGS [LABEL=READINGS ...] [--related FILE] [--groups FILE] [--json OUT]

READINGS is `deckie-listen --list WORK/switch/ROLE/clips.tsv --out READINGS [--listener X]`. --related: pairs of ids
the index holds to be the same sound (deckie-listen --related-out); naming one of them is naming the song. --groups:
id <tab> group (songs of one remix release); a wrong name in the playing song's group is counted as "a version".

What is counted (a reading at time t shows what the listener knew from sound up to t):
  after a cut   seconds from the cut to the first reading naming the new song, if that comes before the next cut;
                "not in its turn" when it does not. Old name still up 3 s and 5 s after the cut (cut clips only).
  on show       of the readings from 5 s on: the song playing; the other song of the clip (a lag); nothing; another.
  alternation   each clip as: keeps up (8 turns in 10 named in their turn); lags (the other song shown on 4 readings in
                10 or more); holds one (one song on 8 named readings in 10); flips late (the rest).
  wrong         clips with any reading naming a song that is in none of the clip's pieces (after the song is gone,
                the old name held over is not wrong; a new name of another song is). Counted apart: a song of the
                playing song's remix release ("version"), and in "shared" clips the made song that shares the passage
                ("made").
  jumps         within a song's turn, after it has been named, the name changing to anything else; per hour of such
                sound. Long play reported on its own.
  misses        turns of 10 s or more whose song is never named in them.
  not in crate  names given during a song not in the crate, or noise, other than the song before held over.
"""
import json, os, sys
from collections import defaultdict
import numpy as np

RELATED, GROUP = defaultdict(set), {}


def same(a, b):
    return a == b or a in RELATED[b]


def load_readings(path):
    by = defaultdict(list)
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 9:
            by[f[0]].append((float(f[1]), f[2], None if f[2] == "nothingYet" or f[3] == "-" else f[3], float(f[8])))
    return by


def pct(x, q):
    return float(np.percentile(x, q)) if len(x) else float("nan")


def score_arm(truth, readings):
    cell = defaultdict(lambda: defaultdict(list))   # (kind, condition) -> metric -> values
    for t in truth:
        rs = readings.get(t["clip"], [])
        c = cell[(t["kind"], t["condition"])]
        c["clips"].append(1)
        c["ms"] += [r[3] for r in rs]
        pieces = t["pieces"]
        songs = {p["song"] for p in pieces}
        absent = {p["song"] for p in pieces if p.get("absent")}

        def playing(time):
            for p in pieces:
                if p["from"] < time <= p["to"] + 1e-6:
                    return p
            return pieces[-1]
        wrong = version = made = False
        named_once = set()
        for k, p in enumerate(pieces):
            inside = [r for r in rs if p["from"] < r[0] <= p["to"] + 1e-6]
            is_song = p["song"] not in ("crowd", "pink") and not p.get("absent")
            prev = pieces[k - 1]["song"] if k else None
            # Names during this piece of songs other than the one playing and the one before it.
            for r in inside:
                if r[2] and not same(r[2], p["song"]) and not (prev and same(r[2], prev)) and not any(same(r[2], s) for s in songs):
                    if p.get("made") and r[2] == p["made"]:
                        made = True
                    elif not is_song:
                        c["names for no crate song"].append(1)
                    elif GROUP.get(r[2]) and GROUP.get(r[2]) == GROUP.get(p["song"]):
                        version = True
                    else:
                        wrong = True
            if not is_song:
                if k:
                    c["names-checked"].append(1)
                continue
            # The first reading in the turn that names its song as a change: a name already shown when the turn began
            # (the listener a whole turn behind) is carried over, not found, until something else has been shown.
            before = [r for r in rs if r[0] <= p["from"] + 1e-6]
            carried = k > 0 and bool(before) and before[-1][2] is not None and same(before[-1][2], p["song"])
            first = None
            for r in inside:
                if r[2] and same(r[2], p["song"]):
                    if not carried:
                        first = r[0]; break
                else:
                    carried = False
            dur = p["to"] - p["from"]
            if dur >= 10:
                c["turns 10s+"].append(1)
                if first is None:
                    c["misses"].append(1)
            if first is not None:
                after = [r for r in inside if r[0] > first]
                c["named seconds"].append(sum(1 for _ in after))
                jumps = sum(1 for a, b in zip([None] + after, after) if b[2] and not same(b[2], p["song"]) and (a is None or a[2] is None or same(a[2], p["song"])))
                c["jumps"].append(jumps)
            if k:
                kind = "return to the first song" if t["kind"] == "return" and k == 2 else "after a cut"
                if first is None:
                    c[kind + ": not in its turn"].append(1)
                else:
                    c[kind].append(first - p["from"])
                c[kind + ": cuts"].append(1)
                if t["kind"] in ("cut", "speed") and prev:
                    for s in (3, 5):
                        r = next((r for r in rs if r[0] >= p["from"] + s), None)
                        c[f"old at {s}"].append(1 if r and r[2] and same(r[2], prev) else 0)
        # Not in the crate, or noise: a new name in that piece.
        for k, p in enumerate(pieces):
            if p["song"] in ("crowd", "pink") or p.get("absent"):
                prev = pieces[k - 1]["song"] if k else None
                if any(r[2] and not (prev and same(r[2], prev)) for r in rs if p["from"] < r[0] <= p["to"] + 1e-6):
                    c["clips naming in noise or an absent song"].append(1)
        c["wrong clips"].append(1 if wrong else 0)
        c["version clips"].append(1 if version else 0)
        if any(p.get("made") for p in pieces):
            c["made named"].append(1 if made else 0)
        # On show, from 5 s on.
        shows = defaultdict(int)
        for r in rs:
            if r[0] < 5:
                continue
            p = playing(r[0])
            if r[2] is None:
                shows["nothing"] += 1
            elif same(r[2], p["song"]):
                shows["playing"] += 1
            elif any(same(r[2], s) for s in songs):
                shows["other"] += 1
            else:
                shows["another"] += 1
        for key, v in shows.items():
            c["show " + key].append(v)
        c["show all"].append(sum(shows.values()))
        if t["kind"].startswith("alt"):
            turns = [p for p in pieces[1:]]
            kept = sum(1 for p in turns if any(r[2] and same(r[2], p["song"]) for r in rs if p["from"] < r[0] <= p["to"] + 1e-6))
            named = [r[2] for r in rs if r[0] >= 5 and r[2]]
            top = max((sum(1 for x in named if same(x, s)) for s in songs), default=0)
            total = max(1, sum(shows.values()))
            if kept >= 0.8 * len(turns):
                c["behaviour"].append("keeps up")
            elif shows["other"] >= 0.4 * total:
                c["behaviour"].append("lags")
            elif named and top >= 0.8 * len(named):
                c["behaviour"].append("holds one")
            else:
                c["behaviour"].append("flips late")
    return cell


def summary(cells, label):
    """One row per (kind, condition) of an arm: the numbers in the letter's tables."""
    rows = []
    for (kind, cond), c in sorted(cells.items()):
        row = dict(arm=label, kind=kind, condition=cond, clips=len(c["clips"]))
        for key in ("after a cut", "return to the first song"):
            v = c[key]
            n = len(c[key + ": cuts"])
            if n:
                row[key] = dict(median=pct(v, 50) if v else None, p90=pct(v + [99] * len(c[key + ": not in its turn"]), 90),
                                by3=sum(1 for x in v if x <= 3) / n, by4=sum(1 for x in v if x <= 4) / n, by5=sum(1 for x in v if x <= 5) / n,
                                not_in_turn=len(c[key + ": not in its turn"]) / n, cuts=n)
        if c["old at 3"]:
            row["old up at 3 s"] = float(np.mean(c["old at 3"])); row["old up at 5 s"] = float(np.mean(c["old at 5"]))
        tot = sum(c["show all"]) or 1
        row["on show"] = {k: sum(c["show " + k]) / tot for k in ("playing", "other", "nothing", "another")}
        row["wrong clips"] = int(sum(c["wrong clips"]))
        row["version clips"] = int(sum(c["version clips"]))
        if c["made named"]:
            row["made song named"] = int(sum(c["made named"]))
        named_hours = sum(c["named seconds"]) / 3600
        row["jumps"] = int(sum(c["jumps"])); row["named hours"] = named_hours
        row["misses"] = int(sum(c["misses"])); row["turns 10s+"] = len(c["turns 10s+"])
        row["clips naming in noise or an absent song"] = len(c["clips naming in noise or an absent song"])
        if c["behaviour"]:
            row["behaviour"] = {b: c["behaviour"].count(b) / len(c["behaviour"]) for b in ("keeps up", "lags", "holds one", "flips late")}
        row["ms median"] = pct(c["ms"], 50); row["ms p95"] = pct(c["ms"], 95)
        rows.append(row)
    return rows


def main():
    args = sys.argv[1:]
    out_json = None
    for flag in ("--related", "--groups", "--json"):
        if flag in args:
            i = args.index(flag); v = args[i + 1]; del args[i:i + 2]
            if flag == "--related" and os.path.exists(v):
                for l in open(v):
                    a, b = l.rstrip("\n").split("\t")[:2]
                    RELATED[a].add(b); RELATED[b].add(a)
            elif flag == "--groups" and os.path.exists(v):
                for l in open(v):
                    a, g = l.rstrip("\n").split("\t")[:2]
                    GROUP[a] = g
            elif flag == "--json":
                out_json = v
    work, role, arms = args[0], args[1], [a.split("=", 1) for a in args[2:]]
    truth = [json.loads(l) for l in open(os.path.join(work, "switch", role, "truth.jsonl"))]
    rows = []
    for label, path in arms:
        rows += summary(score_arm(truth, load_readings(path)), label)
    if out_json:
        json.dump(rows, open(out_json, "w"), indent=1)
    # A short text table: per kind and condition, each arm's seconds after a cut and its fidelity counts.
    print("| Kind | Condition | Arm | Clips | After a cut: median / 90th s | By 3 / 4 / 5 s | Not in its turn | Playing on show | Wrong clips | Version clips | Jumps (per named hour) | Misses | Noise/absent named | Behaviour (keeps up / lags / holds / flips) | ms median / 95th |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda r: (r["kind"], r["condition"], r["arm"])):
        a = r.get("after a cut") or r.get("return to the first song")
        cut = f"{a['median'] if a['median'] is not None else '-'} / {a['p90']:.0f}" if a else "-"
        by = f"{a['by3']:.0%} / {a['by4']:.0%} / {a['by5']:.0%}" if a else "-"
        nt = f"{a['not_in_turn']:.0%}" if a else "-"
        b = r.get("behaviour")
        beh = " / ".join(f"{b[k]:.0%}" for k in ("keeps up", "lags", "holds one", "flips late")) if b else "-"
        jumps = f"{r['jumps']} ({r['jumps'] / r['named hours']:.1f})" if r["named hours"] else str(r["jumps"])
        print(f"| {r['kind']} | {r['condition']} | {r['arm']} | {r['clips']} | {cut} | {by} | {nt} | {r['on show']['playing']:.0%} | {r['wrong clips']} | "
              f"{r['version clips']}{' + made ' + str(r['made song named']) if 'made song named' in r else ''} | {jumps} | {r['misses']}/{r['turns 10s+']} | {r['clips naming in noise or an absent song']} | {beh} | {r['ms median']:.0f} / {r['ms p95']:.0f} |")


if __name__ == "__main__":
    main()
