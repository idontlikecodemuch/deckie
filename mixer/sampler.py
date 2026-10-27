"""Transition sampler: one 60-75 s clip per transition type, each from a real pair in plan_1..3.json.

Usage:  .venv/bin/python -I sampler.py   -> mixes/transition-examples.mp3 + .txt
Clips run from ~20 s before the join to ~30 s after it, separated by 1 s of silence, mastered like the sets.
Where a type does not occur in the sets, a real consecutive pair from the sets is rendered with that type forced.
"""
import copy, json, os
import numpy as np
import soundfile as sf
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render as R  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PLANS = {h: json.load(open(os.path.join(HERE, "plan_mix%d.json" % h))) for h in (1, 2)}


def find(pred, skip=()):
    for h in (1, 2):
        for j in PLANS[h]["joins"]:
            if (h, j["n"]) not in skip and pred(j):
                return h, j["n"]
    return None


def trusted_pair(h, n):
    P = PLANS[h]
    A, B = P["songs"][n - 1], P["songs"][n]
    return A["out_trusted"] and B["in_trusted"] and A["exit"]["bar"] and B["cue_in"]["bar"]


FLAGS0 = dict(reverb_wash=False, scratch=False, backspin=False, key_shift_st=0)
SPEC = [
    # label, planned type to look for, forced override if not found, extra predicate
    ("bass swap, 16 bars", "bass_swap_16", None, lambda j: not j.get("key_shift_st")),
    ("bass swap, 8 bars", "bass_swap_8", None, lambda j: not j.get("key_shift_st")),
    ("bass swap, 32 bars", "bass_swap_32", dict(type="bass_swap_32", overlap_bars=32), None),
    ("tempo-ramped bass swap, 16 bars", "ramped_blend", dict(type="ramped_blend", overlap_bars=16), None),
    ("high-pass filter sweep, 16 bars", "filter_sweep", dict(type="filter_sweep", overlap_bars=16), None),
    ("echo-out, cut in on the one", "echo_out", dict(type="echo_out", overlap_bars=0), None),
    ("reverb throw, cut in on the one", "reverb_out", dict(type="reverb_out", overlap_bars=0), None),
    ("loop roll, cut in on the one", "loop_roll", dict(type="loop_roll", overlap_bars=0), None),
    ("into the hip-hop stretch: echo-out into the Get Ur Freak On Halloween bridge", "echo_out", None,
     lambda j: "Freak On" in j["to_title"]),
    ("hip-hop stretch: slam on the one + scratch stab", "slam", None, lambda j: j["name"].startswith("hip-hop")),
    ("hip-hop stretch: chop A2/B2/A1/B + scratch stab", "chop", None, None),
    ("back to the floor: riser + slam", "slam", None, lambda j: j["name"].startswith("back to the floor")),
    ("into a callout: slam on the one", "slam", None, lambda j: j["name"].startswith("into")),
    ("back out of a callout: riser + slam on the one", "slam", None,
     lambda j: j["name"].startswith("back") and not j.get("scratch")),
    ("back out of a callout: riser + scratch stab + slam", "slam", None, lambda j: j.get("scratch") and j["name"].startswith("back out")),
    ("into a callout: vinyl brake", "brake_cut", dict(type="brake_cut", overlap_bars=0), lambda j: not j.get("backspin")),
    ("into a callout: backspin", "brake_cut", dict(type="brake_cut", overlap_bars=0, backspin=True),
     lambda j: j.get("backspin")),
    ("key-shift blend", None, None, lambda j: j.get("key_shift_st")),
]


def choose():
    out, used = [], set()
    for label, typ, force, pred in SPEC:
        r = find(lambda j: (typ is None or j["type"] == typ) and (pred is None or pred(j)), used)
        if r:
            used.add(r)
            j = PLANS[r[0]]["joins"][r[1] - 1]
            if typ is None:
                label = "key-shift blend (B %+d st), %s" % (j["key_shift_st"], j["type"].replace("_", " "))
            out.append((label, r[0], r[1], {}))
            continue
        if force is None:
            continue
        # force the type on a real consecutive pair: blends on stage-2/3 bass-swap pairs with long bars,
        # cuts on stage-2/3 pairs with a trusted outgoing beat
        best = None
        for h in (1, 2):
            for j in PLANS[h]["joins"]:
                if (h, j["n"]) in used or j["type"] not in ("bass_swap_16", "bass_swap_8") or not trusted_pair(h, j["n"]):
                    continue
                A = PLANS[h]["songs"][j["n"] - 1]
                bars = j["a_exit_bar"] - (A["cue_in"]["bar"] or 1)
                need = force.get("overlap_bars", 0) + 8
                if bars < need:
                    continue
                score = abs(j["stretch_pct"]) if force["type"] == "ramped_blend" else -abs(j["stretch_pct"])
                if best is None or score > best[2]:
                    best = (h, j["n"], score)
        used.add(best[:2])
        out.append((label + " [forced]", best[0], best[1], dict(FLAGS0, **force)))
    return out


def main():
    clips = choose()
    work = os.path.join(R.MIXES, "_work")
    os.makedirs(work, exist_ok=True)
    pre = os.path.join(work, "transition-examples.premaster.wav")
    wf = sf.SoundFile(pre, "w", R.SR, 2, subtype="FLOAT")
    gap = np.zeros((R.SR, 2), np.float32)
    lines, pos = [], 0.0
    for ci, (name, h, n, over) in enumerate(clips):
        P = PLANS[h]
        j = copy.deepcopy(P["joins"][n - 1])
        j.update(over)
        j["n"] = 1
        A, B = copy.deepcopy(P["songs"][n - 1]), copy.deepcopy(P["songs"][n])
        mini = {"hour": 0, "name": "sampler", "lean": "-", "planned_duration_s": 0,
                "songs": [A, B], "joins": [j]}
        R.log("clip %d: %s  (hour %d join %d) %s -> %s" % (ci + 1, name, h, n, A["title"], B["title"]))
        res = R.render(None, preview=1, out_base="_clip", plan_obj=mini, premaster_only=True)
        T1 = res["T"][1] / R.SR
        J0 = res["J"][0]
        ov_end = T1 + (J0["O"][-1] / R.SR if J0["L"] else 0)
        start, end = T1 - 20, ov_end + 30
        if end - start > 75:          # long overlaps: start 8 s before the overlap and keep 75 s
            start = T1 - 8
            end = start + 75
        if end - start < 60:
            end = start + 60
        x, _ = sf.read(res["pre_wav"], dtype="float32", always_2d=True)
        a, b = int(max(0, start) * R.SR), min(len(x), int(end * R.SR))
        clip = x[a:b].copy()
        f = int(0.5 * R.SR)
        clip[:f] *= np.linspace(0, 1, f)[:, None]
        clip[-f:] *= np.linspace(1, 0, f)[:, None]
        os.remove(res["pre_wav"])
        m, s = divmod(int(pos), 60)
        jl = res["rlog"]["joins"][0]
        lines.append("%2d  %d:%02d  %-48s %s  ->  %s   [mix %d, join %d%s; join at +%.0f s in clip; stretch %+.1f%%%s]" % (
            ci + 1, m, s, name, A["title"], B["title"], h, n, ", type forced on this pair" if over else ", as planned",
            T1 - max(0, start), j["stretch_pct"],
            ("; beat offset after phase-lock %s ms" % jl.get("beat_offset_ms")) if jl.get("beat_offset_ms") is not None else ""))
        wf.write(clip)
        wf.write(gap)
        pos += clip.shape[0] / R.SR + 1.0
    wf.close()
    plan = {"name": "Transition examples", "hour": 0}
    res = R.master_and_encode(pre, "transition-examples", plan, [], [], pos)
    hdr = ["Transition examples (%d clips, %.1f min, %.1f LUFS, TP %.1f dBTP)" % (
        len(clips), pos / 60, res["mp3_integrated_lufs"] or 0, res["mp3_true_peak_dbtp"] or 0),
        "Each clip: ~20 s before the join to ~30 s after; 1 s of silence between clips.", ""]
    with open(os.path.join(R.MIXES, "transition-examples.txt"), "w") as fh:
        fh.write("\n".join(hdr + lines) + "\n")
    print("\n".join(hdr + lines))
    print(res["mp3"], res["mp3_bytes"])


if __name__ == "__main__":
    main()
