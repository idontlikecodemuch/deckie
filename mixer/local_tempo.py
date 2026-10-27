#!/usr/bin/env python3
"""Start / end / windowed tempo from the raw detected beats of a feature file.

The main analysis fits ONE constant grid per track. That is right for most produced
dance and pop records but wrong for tempo-change transition edits, slow intros,
rideouts and drifting live recordings. This module measures tempo locally:

  bpm_in   median inter-beat tempo over the first 30 s of sound (and over mix_in)
  bpm_out  the same over the last 30 s of sound (and over mix_out)
  profile  tempo per 15 s segment across the whole track
  drift    (bpm_out - bpm_in) / bpm_in in percent

Local tempos are octave-normalised against the track's global bpm with the same
multiplier set the scorer uses, so a half-time intro reads as x0.5, not as an error.

Used by analyze.py at analysis time and as a CLI to backfill existing features:
    .venv/bin/python -I local_tempo.py            # add local_tempo to every feature lacking it
    .venv/bin/python -I local_tempo.py --force    # recompute for all
"""
import glob, json, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FEAT_DIR = os.path.join(HERE, "features")
MULTS = [0.5, 2 / 3, 0.75, 1.0, 4 / 3, 1.5, 2.0]
WIN_S = 30.0
SEG_S = 15.0
MIN_BEATS = 8


def _local(beats, t0, t1, ref_bpm):
    """Tempo inside [t0, t1] by robust linear regression of beat time on beat index.
    Beat This emits beat times on a 20 ms frame grid, so a median interval is only good to
    about 4 percent; a regression over 30 s of beats is good to about 0.1 percent."""
    b = np.sort(beats[(beats >= t0) & (beats <= t1)])
    if len(b) < MIN_BEATS:
        return None
    ibi = np.diff(b)
    med = float(np.median(ibi))
    if med <= 0:
        return None
    # cumulative integer index: robust to the coarse (20 ms frame) median, tolerates missed beats
    idx = np.concatenate([[0.0], np.cumsum(np.round(ibi / med))])
    keep = np.ones(len(b), bool)
    P, off = med, b[0]
    for _ in range(3):
        if keep.sum() < MIN_BEATS:
            return None
        A = np.vstack([idx[keep], np.ones(keep.sum())]).T
        P, off = np.linalg.lstsq(A, b[keep], rcond=None)[0]
        res = b - (off + P * idx)
        idx = idx + np.round(res / P)
        res = b - (off + P * idx)
        keep = np.abs(res) < 0.25 * P
    raw = 60.0 / P
    m = min(MULTS, key=lambda x: abs(math.log(raw * x / ref_bpm)))
    return {"bpm": round(raw * m, 2), "bpm_raw": round(raw, 2), "mult": round(m, 4),
            "n_beats": int(keep.sum()), "resid_ms": round(float(np.median(np.abs(res[keep])) * 1000), 1),
            "t0": round(float(t0), 2), "t1": round(float(t1), 2)}


def _grid_dev_ms(detected, grid, t0, t1):
    d = detected[(detected >= t0) & (detected <= t1)]
    if len(d) < 4 or len(grid) < 2:
        return None
    idx = np.searchsorted(grid, d)
    idx = np.clip(idx, 1, len(grid) - 1)
    near = np.minimum(abs(d - grid[idx - 1]), abs(d - grid[idx]))
    return round(float(np.median(near) * 1000), 1)


TRUST_RESID_MS = 15.0
TRUST_MIN_BEATS = 16
DIFF_PCT = 1.5


def _trusted(w):
    return bool(w and w["resid_ms"] <= TRUST_RESID_MS and w["n_beats"] >= TRUST_MIN_BEATS)


def _decide(w, grid_dev_ms, ref):
    """Window tempo: the global grid when the window's beats already sit on it, the local
    regression when it has its own steady beat, else the global grid flagged untrusted."""
    if grid_dev_ms is not None and grid_dev_ms <= TRUST_RESID_MS:
        return ref, True, "on_global_grid"
    if _trusted(w):
        if abs(w["bpm"] - ref) / ref * 100 > DIFF_PCT:
            return w["bpm"], True, "local_differs"
        return ref, True, "local_matches"
    return ref, False, "no_steady_beat"


def compute(feat):
    ref = float(feat["bpm"])
    det = np.array(feat.get("detected_beats_s") or feat.get("beats_s") or [], float)
    grid = np.array(feat.get("beats_s") or [], float)
    downs = np.array(feat.get("detected_downbeats_s") or feat.get("downbeats_s") or [], float)
    fs, ls = float(feat.get("first_sound_s", 0.0)), float(feat.get("last_sound_s", feat["duration_s"]))
    out = {"ref_bpm": ref}
    out["first30"] = _local(det, fs, min(fs + WIN_S, ls), ref)
    out["last30"] = _local(det, max(ls - WIN_S, fs), ls, ref)
    mi, mo = feat.get("mix_in") or {}, feat.get("mix_out") or {}
    out["mix_in"] = _local(det, mi.get("start_s", fs), mi.get("end_s", fs + WIN_S), ref) if mi else None
    out["mix_out"] = _local(det, mo.get("start_s", ls - WIN_S), mo.get("end_s", ls), ref) if mo else None
    out["grid_dev_in_ms"] = _grid_dev_ms(det, grid, fs, fs + WIN_S)
    out["grid_dev_out_ms"] = _grid_dev_ms(det, grid, ls - WIN_S, ls)
    bi, ti, ri = _decide(out["first30"], out["grid_dev_in_ms"], ref)
    bo, to, ro = _decide(out["last30"], out["grid_dev_out_ms"], ref)
    out["bpm_in"], out["in_trusted"], out["in_rule"] = bi, ti, ri
    out["bpm_out"], out["out_trusted"], out["out_rule"] = bo, to, ro
    out["drift_pct"] = round((bo - bi) / bi * 100, 2)
    prof = []
    t = fs
    while t + SEG_S * 0.6 < ls:
        seg = _local(det, t, min(t + SEG_S, ls), ref)
        gd = _grid_dev_ms(det, grid, t, min(t + SEG_S, ls))
        b, tr, rule = _decide(seg, gd, ref)
        prof.append([round(t, 1), b, tr])
        t += SEG_S
    out["profile"] = prof
    vals = [p[1] for p in prof if p[2]]
    out["range_pct"] = round((max(vals) - min(vals)) / ref * 100, 2) if vals else None
    out["untrusted_segments"] = sum(1 for p in prof if not p[2])
    bar_s = 240.0 / ref
    fd0 = float(feat.get("grid", {}).get("first_downbeat_s", fs))
    def bar_of(t):
        return int(round((t - fd0) / bar_s)) + 1
    tr_segs = [p for p in prof if p[2]]
    if tr_segs:
        t_in = tr_segs[0][0]
        nd = downs[downs >= t_in - 0.5]
        t_in = float(nd[0]) if len(nd) else t_in
        t_out = min(tr_segs[-1][0] + SEG_S, ls)
        out["steady_in_s"], out["steady_in_bar"] = round(t_in, 3), max(1, bar_of(t_in))
        out["steady_out_s"], out["steady_out_bar"] = round(t_out, 3), max(1, bar_of(t_out))
    else:
        out["steady_in_s"] = out["steady_in_bar"] = out["steady_out_s"] = out["steady_out_bar"] = None
    fd = downs[(downs >= fs) & (downs <= fs + WIN_S)]
    ld = downs[(downs >= ls - WIN_S) & (downs <= ls)]
    out["first_downbeat_in_s"] = round(float(fd[0]), 3) if len(fd) else None
    out["first_downbeat_out_s"] = round(float(ld[0]), 3) if len(ld) else None
    out["tempo_change"] = bool(ti and to and abs(out["drift_pct"]) > 2.0) or bool((out["range_pct"] or 0) > 3.0)
    out["transition_track"] = bool(ti and to and abs(out["drift_pct"]) > 5.0)
    out["in_half_time"] = bool(ti and ri == "local_differs" and (out["first30"] or {}).get("mult", 1.0) != 1.0)
    out["out_half_time"] = bool(to and ro == "local_differs" and (out["last30"] or {}).get("mult", 1.0) != 1.0)
    out["intro_no_steady_beat"] = not ti
    out["outro_no_steady_beat"] = not to
    return out


def flags(lt):
    f = []
    if lt.get("tempo_change"): f.append("tempo_change")
    if lt.get("transition_track"): f.append("transition_track")
    if lt.get("in_half_time"): f.append("intro_half_time")
    if lt.get("out_half_time"): f.append("outro_half_time")
    if lt.get("intro_no_steady_beat"): f.append("intro_no_steady_beat")
    if lt.get("outro_no_steady_beat"): f.append("outro_no_steady_beat")
    return f


def main():
    force = "--force" in sys.argv
    done = changed = 0
    rows = []
    for f in sorted(glob.glob(os.path.join(FEAT_DIR, "*.json"))):
        d = json.load(open(f))
        if "local_tempo" in d and not force:
            lt = d["local_tempo"]
        else:
            lt = compute(d)
            d["local_tempo"] = lt
            d["flags"] = [x for x in d.get("flags", []) if x not in ("tempo_change", "transition_track", "intro_half_time", "outro_half_time", "intro_no_steady_beat", "outro_no_steady_beat")]
            for fl in flags(lt):
                if fl not in d.setdefault("flags", []):
                    d["flags"].append(fl)
            tmp = f + ".tmp"
            json.dump(d, open(tmp, "w"), ensure_ascii=False)
            os.replace(tmp, f)
            changed += 1
        done += 1
        rows.append((d.get("title", d["id"]), d["bpm"], lt["bpm_in"], lt["bpm_out"], lt["drift_pct"], lt["range_pct"], lt["tempo_change"], lt["transition_track"]))
    print(f"{done} features, {changed} written")
    tc = [r for r in rows if r[6]]
    print(f"tempo changes flagged: {len(tc)}")
    for r in sorted(tc, key=lambda r: -abs(r[4])):
        print(f"  {r[1]:7.2f} global | in {r[2]:7.2f} -> out {r[3]:7.2f} ({r[4]:+.1f}%, range {r[5]}%) {'TRANSITION ' if r[7] else ''}{r[0]}")


if __name__ == "__main__":
    main()
