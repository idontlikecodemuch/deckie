#!/usr/bin/env python3
"""The letter's tables from switch_eval.py --json (docs/research/faster-listening-results.md). Needs only Python.

  switch_tables.py TABLE.json [ARM ...]      Markdown on standard output; ARMs in the order wanted (default as found)
"""
import json, sys
from collections import defaultdict

COND = ["clean", "room", "room+crowd+10", "room+crowd0", "booth(speaker+room+crowd0)"]
CNAME = {"clean": "clean", "room": "room", "room+crowd+10": "crowd 10 dB under", "room+crowd0": "crowd equal",
         "booth(speaker+room+crowd0)": "small speaker, crowd equal"}


def s(x, fmt="{:.0f}"):
    return "-" if x is None else fmt.format(x)


def main():
    rows = json.load(open(sys.argv[1]))
    arms = sys.argv[2:] or list(dict.fromkeys(r["arm"] for r in rows))
    by = {(r["kind"], r["condition"], r["arm"]): r for r in rows}
    kinds = sorted({r["kind"] for r in rows})

    def cut_table(kind, key="after a cut", title=None):
        print(f"\n**{title or kind}** (seconds from the cut to the right name; p90 counts a turn never named as 99)\n")
        print("| Condition | " + " | ".join(arms) + " |")
        print("|---|" + "---|" * len(arms))
        for c in COND:
            cells = []
            for a in arms:
                r = by.get((kind, c, a))
                x = r and r.get(key)
                if not x:
                    cells.append("-"); continue
                cells.append(f"{s(x['median'])} / {s(min(x['p90'], 99))} · {x['by3']:.0%} · {x['by5']:.0%}" + (f" · {x['not_in_turn']:.0%} not" if x['not_in_turn'] else ""))
            if any(cell != "-" for cell in cells):
                print(f"| {CNAME[c]} | " + " | ".join(cells) + " |")

    print("Cells: median / 90th percentile s · named by 3 s · by 5 s · not named in its turn.")
    for kind, title in [("cut", "Hard cut"), ("speed", "Hard cut, each song at its own fader setting")]:
        if kind in kinds:
            cut_table(kind, title=title)
    if "return" in kinds:
        cut_table("return", "after a cut", "Quick return: to the other song (6 s)")
        cut_table("return", "return to the first song", "Quick return: back to the first song")
    for kind in ("alt12", "alt8", "alt5", "alt3"):
        if kind in kinds:
            cut_table(kind, title=f"Back and forth, {kind[3:]} s each")

    # On show and behaviour in alternations.
    print("\n**Back and forth: the song on show** (share of readings from 5 s on showing the song playing · the clip's other song; "
          "then clips that keep up / lag a turn / hold one / flip late)\n")
    print("| Turns | Condition | " + " | ".join(arms) + " |")
    print("|---|---|" + "---|" * len(arms))
    for kind in ("alt12", "alt8", "alt5", "alt3"):
        for c in COND:
            cells = []
            for a in arms:
                r = by.get((kind, c, a))
                if not r:
                    cells.append("-"); continue
                b = r.get("behaviour", {})
                cells.append(f"{r['on show']['playing']:.0%} · {r['on show']['other']:.0%}; " + "/".join(f"{b.get(k, 0):.0%}" for k in ("keeps up", "lags", "holds one", "flips late")))
            if any(cell != "-" for cell in cells):
                print(f"| {kind[3:]} s | {CNAME[c]} | " + " | ".join(cells) + " |")

    # Fidelity, per condition, summed over every kind of clip.
    print("\n**Fidelity, all clips of a condition** (clips with a wrong name · with a version of the same release named · "
          "shared-passage clips naming the made song · jumps in a song · misses of turns of 10 s or more · clips naming "
          "a song during noise or a song not in the crate)\n")
    print("| Condition | " + " | ".join(arms) + " |")
    print("|---|" + "---|" * len(arms))
    total = defaultdict(lambda: defaultdict(int))
    for c in COND + ["all"]:
        cells = []
        for a in arms:
            if c == "all":
                t = total[a]
            else:
                t = defaultdict(int)
                for (k, cc, aa), r in by.items():
                    if cc == c and aa == a:
                        t["wrong"] += r["wrong clips"]; t["version"] += r["version clips"]; t["made"] += r.get("made song named", 0)
                        t["jumps"] += r["jumps"]; t["misses"] += r["misses"]; t["turns"] += r["turns 10s+"]
                        t["noise"] += r["clips naming in noise or an absent song"]; t["clips"] += r["clips"]; t["hours"] += r["named hours"]
                for key, v in t.items():
                    total[a][key] += v
            cells.append(f"{t['wrong']} · {t['version']} · {t['made']} · {t['jumps']} · {t['misses']}/{t['turns']} · {t['noise']}")
        print(f"| {CNAME.get(c, '**all**')} | " + " | ".join(cells) + " |")
    print("\n| Clips in all | " + " | ".join(str(total[a]["clips"]) for a in arms) + " |")
    print("|---|" + "---|" * len(arms))
    print("| Jumps per hour of named song | " + " | ".join(f"{total[a]['jumps'] / max(1e-9, total[a]['hours']):.1f}" for a in arms) + " |")

    # Cost.
    print("\n**A reading's work** (milliseconds on one core of the test machine: median / 95th percentile, cut clips, clean)\n")
    print("| " + " | ".join(arms) + " |")
    print("|" + "---|" * len(arms))
    print("| " + " | ".join(f"{by[('cut', 'clean', a)]['ms median']:.0f} / {by[('cut', 'clean', a)]['ms p95']:.0f}" if ('cut', 'clean', a) in by else "-" for a in arms) + " |")


if __name__ == "__main__":
    main()
