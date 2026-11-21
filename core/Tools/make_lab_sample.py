#!/usr/bin/env python3
"""Write core/fixtures/lab-sample: a public stand-in for the lab's private data, in the lab's own file shapes, made
of invented songs. Nothing in it comes from anyone's music: every song, artist, folder and number is made up here.
  python3 core/Tools/make_lab_sample.py        # from anywhere; needs numpy only

Why. The lab (mixer/) analysed a personal music library; its feature files, candidates and per-track sheets are
private and live outside the repository (DECKIE_LAB_DATA, mixer/labdata.py). The core's tests that compare the Swift
ports with the lab read that folder when it is given, and this sample otherwise, so they run everywhere.

How. What the lab measured from audio (the beat tracker's beats and downbeats, the first and last sound, the per-bar
levels, the vocal probability, the novelty peaks, the three key detectors' answers, the loudness, the onset pattern,
the style embedding) is invented per song from a seeded random generator. Everything the lab decided from those
measurements is computed by the lab's own code, as mixer/analyze.py's `analyse` does it after the audio stage: the
grid fit and the grid choice (analyze.fit_grid), bar 1 and the bar count, the phrase lattice and the boundaries, the
sections, the fade-out rule, the mix windows, the key confidence rule (B.9), the flags, and the local tempo block
(mixer/local_tempo.py). So the files are consistent the way the lab's are, and the parity tests hold on them.

Twelve songs, chosen to differ: a madmom grid after Beat This disagreed with the tag tempo, an octave-fixed grid, a
fade-out, a tempo change (a transition edit, whose grid fits poorly), a short song, a half-time song, two cuts of one
song, a song sung throughout, and songs on two discs and none. Then the lab's scorer (mixer/score.py) writes recs.json, and
core/Tools/make_fixtures.py and make_bench_fixtures.py write the reference numbers into lab-sample/fixtures/.

Output: core/fixtures/lab-sample/{features/<id>.json, candidates.json, recs.json, fixtures/*.json}
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "core", "fixtures", "lab-sample")
sys.path.insert(0, os.path.join(ROOT, "mixer"))
import analyze  # noqa: E402  (numpy only at import; the audio stage is not used)
import local_tempo  # noqa: E402

MUSIC = "/path/to/music/"
SONGS = [
    # id, artist, song, version, bpm (or (start, end) for a tempo change), tag, seconds, votes, kind, era, disc,
    # folder, halloween, special
    dict(id="sample-01", artist="The Placeholders", song="Grid Fit Groove", ver="", bpm=124.0, tag=124, secs=332,
         votes=[("A", "minor", 0.81), ("A", "minor", 0.80), ("A", "minor", 0.92)], kind="dance original", era="90s",
         disc="M", folder="5 - 120-124", hal=False),
    dict(id="sample-02", artist="Test Pattern", song="Low Confidence", ver="", bpm=118.5, tag=116, secs=357,
         votes=[("E", "minor", 0.74), ("E", "minor", 0.71), ("G", "major", 0.66)], kind="dance original",
         era="pre-90s", disc=None, folder="4 - 110-119", hal=True, special="madmom"),
    dict(id="sample-03", artist="Made-Up Collective", song="Octave Swap", ver="", bpm=89.0, tag=89, secs=243,
         votes=[("F#", "minor", 0.95), ("F#", "minor", 0.94), ("F#", "minor", 0.99)], kind="pop original",
         era="90s", disc="S", folder="1 - under 90", hal=False, special="octave"),
    dict(id="sample-04", artist="Fictional Four", song="Fade Away Test", ver="", bpm=128.6, tag=129, secs=318,
         votes=[("G", "minor", 0.72), ("D", "minor", 0.69), ("G", "minor", 0.77)], kind="pop original", era="90s",
         disc="S", folder="6 - 125-134", hal=False, special="fade"),
    dict(id="sample-05", artist="Sample Club", song="Tempo Ramp", ver="Transition Edit", bpm=(100.0, 112.0),
         tag=100, secs=212, votes=[("C", "major", 0.62), ("C", "major", 0.65), ("A", "minor", 0.58)],
         kind="pool edit", era="2020s", disc="M", folder="3 - 100-109", hal=False, special="drift"),
    dict(id="sample-06", artist="Synthetic Soul", song="Short One", ver="", bpm=130.0, tag=130, secs=86,
         votes=[("D", "major", 0.84), ("D", "major", 0.83), ("D", "major", 0.88)], kind="pop original",
         era="2020s", disc=None, folder="6 - 125-134", hal=False),
    dict(id="sample-07", artist="Imaginary Orchestra", song="Half Time Walk", ver="", bpm=86.5, tag=173, secs=264,
         votes=[("B", "minor", 0.70), ("D", "major", 0.68), ("B", "minor", 0.81)], kind="slow / R&B", era="2000s",
         disc=None, folder="1 - under 90", hal=False),
    dict(id="sample-08", artist="Dummy Data", song="Two Cuts", ver="Extended Mix", bpm=126.0, tag=126, secs=402,
         votes=[("A", "minor", 0.86), ("A", "minor", 0.82), ("C", "major", 0.79)], kind="official remix",
         era="2010s", disc="M", folder="6 - 125-134", hal=False, cut="dummy data two cuts"),
    dict(id="sample-09", artist="Dummy Data", song="Two Cuts", ver="Radio Edit", bpm=126.0, tag=126, secs=208,
         votes=[("A", "minor", 0.85), ("A", "minor", 0.83), ("A", "minor", 0.90)], kind="official remix",
         era="2010s", disc=None, folder="6 - 125-134", hal=False, cut="dummy data two cuts"),
    dict(id="sample-10", artist="Nobody In Particular", song="Neighbour Keys", ver="", bpm=125.2, tag=125,
         secs=371, votes=[("D", "minor", 0.77), ("A", "minor", 0.74), ("D", "minor", 0.69)], kind="pool edit",
         era="2000s", disc="M", folder="6 - 125-134", hal=True),
    dict(id="sample-11", artist="Example Ensemble", song="Steady Hands", ver="Club Mix", bpm=122.0, tag=122,
         secs=389, votes=[("G", "major", 0.79), ("G", "major", 0.81), ("E", "minor", 0.72)], kind="dance original",
         era="2010s", disc=None, folder="5 - 120-124", hal=False),
    dict(id="sample-12", artist="Stand-In Singers", song="Every Word Sung", ver="", bpm=105.0, tag=105, secs=231,
         votes=[("E", "major", 0.55), ("B", "major", 0.52), ("C#", "minor", 0.58)], kind="pop original",
         era="2020s", disc="S", folder="3 - 100-109", hal=False, special="vocal"),
]


def q(x, step):
    return np.round(np.asarray(x, float) / step) * step


def beat_times(bpm, first, last, jitter, rng, drop=0.0):
    """Beats from `first` to `last` at `bpm` (a number, or (start, end) for a linear tempo change)."""
    t, out = first, []
    b0, b1 = (bpm, bpm) if isinstance(bpm, (int, float)) else bpm
    while t < last:
        out.append(t)
        # a tempo change as a transition edit makes it: steady, a ramp through the middle fifth, steady again
        frac = min(1.0, max(0.0, ((t - first) / max(1e-9, last - first) - 0.4) / 0.2))
        t += 60.0 / (b0 + (b1 - b0) * frac)
    b = np.array(out) + rng.normal(0, jitter, len(out))
    if drop:
        b = b[rng.random(len(b)) >= drop]
    return np.sort(q(b, 0.02))  # Beat This reports on a 50 frames-a-second grid


def make(s, k):
    rng = np.random.default_rng(1000 + k)
    special = s.get("special", "")
    duration = s["secs"] + round(float(rng.uniform(0.05, 0.95)), 3)
    first_sound = float(q(rng.uniform(0.0, 0.6), 0.01))
    if special == "fade":
        last_sound = duration - 0.12
    else:
        last_sound = duration - float(rng.uniform(0.6, 2.5))
    last_sound = float(q(last_sound, 0.01))
    bpm0 = s["bpm"] if isinstance(s["bpm"], (int, float)) else s["bpm"][0]
    first_beat = first_sound + float(rng.uniform(0.02, 0.5))
    end_beats = last_sound - (0.2 if special != "fade" else 0.5)
    jitter = 0.009 if special == "madmom" else 0.006
    bt = beat_times(s["bpm"], first_beat, end_beats, jitter, rng, drop=0.03 if special == "madmom" else 0.0)
    phase = int(rng.integers(0, 4))
    bt_downs = bt[phase::4]
    grid_bt = analyze.fit_grid(bt, bt_downs, duration)
    tag = float(s["tag"]) if s.get("tag") else None

    def tag_dev(g):
        if g is None or not tag:
            return 999.0
        return analyze.mult_dev(g["bpm"], tag, analyze.OCTAVE_MULTS)[1]

    grids = {"beatthis": grid_bt}
    madmom_reason, run_mm, mm_downs = None, False, None
    if grid_bt is None or grid_bt["confidence"] < 0.5:
        run_mm, madmom_reason = True, "poor grid fit"
    elif tag_dev(grid_bt) > 2.0:
        run_mm, madmom_reason = True, "Beat This vs tag > 2%"
    if run_mm:
        mm = beat_times(s["bpm"], first_beat, end_beats, 0.004, rng)
        mm_downs = mm[(phase + 1) % 4::4]
        grids["madmom"] = analyze.fit_grid(mm, mm_downs, duration)
    cands = sorted([(k_, g) for k_, g in grids.items() if g is not None],
                   key=lambda kg: (tag_dev(kg[1]) > 2.0, kg[1]["fit_mad_ms"]))
    grid_src, G = cands[0]
    P = G["period"]
    bar_s, bpm = 4 * P, 60.0 / P
    fd = G["first_downbeat"]
    lo = max(0.0, first_sound - 0.25 * P)
    fd = fd - math.floor((fd - lo) / bar_s) * bar_s
    if fd < lo - 1e-9:
        fd += bar_s
    n_bars = int(math.floor((duration - fd) / bar_s))
    bar_t = fd + np.arange(n_bars + 1) * bar_s
    grid_beats = fd + np.arange(n_bars * 4 + 1) * P
    pre = np.arange(fd - P, -1e-9, -P)[::-1]
    grid_beats_all = np.concatenate([pre, grid_beats])
    mult_tag, dev_tag = analyze.mult_dev(bpm, tag, analyze.MULTIPLIERS) if tag else (1.0, 0.0)
    oct_mult, oct_dev = analyze.mult_dev(bpm, tag, analyze.OCTAVE_MULTS) if tag else (1.0, 0.0)
    bpm_agree = bool(tag and oct_dev < 1.0)
    bpm_ess = bpm * (1.0 if k % 3 else 4 / 3) * float(rng.uniform(0.998, 1.002))
    ess_mult, ess_dev = analyze.mult_dev(bpm_ess, bpm, analyze.OCTAVE_MULTS)

    # the invented measurements, bar by bar: an intro, verses and choruses with a break, an outro
    body = float(rng.uniform(-9.5, -6.5))
    intro = int(rng.choice([8, 16, 16, 32])) if n_bars >= 64 else 8
    outro = 16 if n_bars >= 64 else 8
    brk = (n_bars // 2) - 4 if n_bars >= 48 else None
    fade_bars = 12 if special == "fade" else 0
    lufs = np.full(n_bars, body) + rng.normal(0, 0.35, n_bars)
    lufs[:intro] -= 4.0
    lufs[n_bars - outro:] -= 3.0
    if brk:
        lufs[brk:brk + 8] -= 3.5
    if fade_bars:
        lufs[n_bars - fade_bars:] = body - 2.5 - np.linspace(0, 18, fade_bars)
    low = lufs - 6 + rng.normal(0, 0.8, n_bars)
    high = lufs - 17 + rng.normal(0, 0.8, n_bars)
    onset = np.clip(2.5 + rng.normal(0, 0.4, n_bars), 0.5, 4.0)
    onset[:intro] -= 0.75
    vocal = rng.uniform(0.03, 0.3, n_bars)
    v0, v1 = (0, n_bars) if special == "vocal" else (intro + (4 if k % 2 else 0), n_bars - outro)
    vocal[v0:v1] = rng.uniform(0.6, 0.97, v1 - v0)
    if brk and special != "vocal":
        vocal[brk:brk + 8] = rng.uniform(0.05, 0.4, 8)
    if special == "vocal":
        vocal[:4] = rng.uniform(0.55, 0.9, 4)
    lufs, low, high = q(lufs, 0.01), q(low, 0.01), q(high, 0.01)
    onset, vocal = q(onset, 0.25), q(vocal, 0.001)

    # novelty peaks at the section changes (on the phrase lattice) and a few weaker ones off it
    lat = int(rng.choice([0, 0, 0, 4]))
    marks = sorted({b for b in [intro, brk, brk + 8 if brk else None, n_bars - outro, n_bars - fade_bars]
                    if b and 0 < b < n_bars})
    peaks = [(b, round(float(rng.uniform(0.02, 0.06)), 3)) for b in marks]
    for _ in range(int(rng.integers(2, 6))):
        b = int(rng.integers(1, n_bars))
        if all(b != p[0] for p in peaks):
            peaks.append((b, round(float(rng.uniform(0.003, 0.015)), 3)))
    peaks = [(b + lat if 0 < b + lat < n_bars and b % 8 == 0 else b, v) for b, v in peaks]
    peaks = sorted({b: v for b, v in peaks}.items())

    # the lab's own decisions from here on (mixer/analyze.py, `analyse`, after the audio stage)
    sums = np.zeros(8)
    for bar, v in peaks:
        sums[bar % 8] += v
    total = sums.sum()
    ph = int(np.argmax(sums)) if total > 0 else 0
    srt = np.sort(sums)[::-1]
    phrase_conf = float(srt[0] / total) if total > 0 else 0.0
    if total > 0:
        phrase_conf = float(np.clip(0.6 * phrase_conf + 0.4 * (srt[0] - srt[1]) / (srt[0] + 1e-9), 0, 1))
    bset = sorted({b for b, v in peaks if b % 8 == ph})
    boundaries0 = sorted(set([0] + bset + [n_bars]))
    lufs_arr, vocal_bar = np.array(lufs), np.array(vocal)
    med = np.median(lufs_arr)
    sections = []
    for i, (a, b2) in enumerate(zip(boundaries0[:-1], boundaries0[1:])):
        if b2 <= a:
            continue
        e = float(np.mean(lufs_arr[a:b2]))
        energy = "high" if e >= med - 1.5 else "low"
        label = "intro" if i == 0 else ("outro" if b2 == n_bars else ("main" if energy == "high" else "break"))
        sections.append({"start_bar": a + 1, "end_bar": b2 + 1, "label": label, "energy": energy,
                         "lufs": round(e, 2), "vocal": round(float(vocal_bar[a:b2].mean()), 3)})
    if special == "fade":
        l20, l10, l4 = med - 1.2, med - 7.5, med - 15.0
    else:
        l20, l10, l4 = (med + float(rng.uniform(-1.5, 1.0)) for _ in range(3))
    fade_drop = l20 - l4
    okb = np.nonzero(lufs_arr >= med - 2.0)[0]
    last_body_bar = int(okb[-1]) if len(okb) else n_bars - 1
    tail_bars = (last_sound - bar_t[last_body_bar + 1]) / bar_s if last_body_bar + 1 <= n_bars else 0.0
    fade_out = bool(fade_drop > 6.0 and tail_bars >= 3.0 and last_sound - first_sound > 60)
    fade_start_bar = last_body_bar + 1 if fade_out else None
    VOC = 0.5
    snap_phase = ph if phrase_conf >= 0.35 else 0
    snap_lat = list(range(snap_phase, n_bars + 1, 8))
    on_lat = lambda b: (b - snap_phase) % 8 == 0  # noqa: E731
    last_full = int(np.searchsorted(bar_t, last_sound, side="right") - 1)
    end_limit = max(8, min(n_bars, last_full))
    vocal_on = np.nonzero(vocal_bar >= VOC)[0]
    first_vocal = int(vocal_on[0]) if len(vocal_on) else n_bars
    last_vocal = int(vocal_on[-1]) if len(vocal_on) else -1
    half = max(8, n_bars // 2)

    def pick_len(avail, vocal_free_avail):
        if avail >= 32 and vocal_free_avail >= 16:
            return 32
        return 16 if avail >= 16 else 8

    start0 = 0
    first_bound = next((b for b in bset if b >= start0 + 8), None)
    if first_vocal - start0 >= 8:
        avail_in = first_vocal - start0
    else:
        avail_in = (first_bound - start0) if first_bound is not None else 16
    avail_in = int(np.clip(avail_in, 8, half))
    L_in = pick_len(avail_in, int(np.sum(vocal_bar[start0:start0 + avail_in] < VOC)))
    end_in = start0 + L_in
    if not on_lat(end_in):
        latc = [b for b in snap_lat if start0 + 8 <= b <= start0 + max(avail_in, L_in)]
        if latc:
            end_in = min(latc, key=lambda b: abs(b - (start0 + L_in)))
    r3 = analyze.r3
    mix_in = {"start_bar": start0 + 1, "end_bar": end_in + 1, "bars": end_in - start0,
              "start_s": r3(bar_t[start0]), "end_s": r3(bar_t[end_in]),
              "vocal_free_bars": int(np.sum(vocal_bar[start0:end_in] < VOC)),
              "first_vocal_bar": first_vocal + 1 if len(vocal_on) else None}
    if fade_out and fade_start_bar is not None:
        cand = [b for b in snap_lat if 16 <= b <= fade_start_bar]
        end_out = max(cand) if cand else max(16, min(fade_start_bar, end_limit))
    else:
        end_out = end_limit
        latb = [b for b in snap_lat if end_limit - 4 <= b <= end_limit]
        if latb:
            end_out = max(latb)
    end_out = min(end_out, n_bars)
    lv = int(np.max(np.nonzero(vocal_bar[:end_out] >= VOC)[0])) if np.any(vocal_bar[:end_out] >= VOC) else -1
    if end_out - (lv + 1) >= 8:
        avail_out = end_out - (lv + 1)
    else:
        lb = [b for b in bset if b <= end_out - 8]
        avail_out = end_out - max(lb) if lb else 16
    avail_out = int(np.clip(avail_out, 8, half))
    L_out = pick_len(avail_out, int(np.sum(vocal_bar[max(0, end_out - avail_out):end_out] < VOC)))
    start_out = max(0, end_out - L_out)
    mix_out = {"start_bar": start_out + 1, "end_bar": end_out + 1, "bars": end_out - start_out,
               "start_s": r3(bar_t[start_out]), "end_s": r3(bar_t[end_out]),
               "vocal_free_bars": int(np.sum(vocal_bar[start_out:end_out] < VOC)),
               "last_vocal_bar": last_vocal + 1 if last_vocal >= 0 else None, "fade_out": fade_out}

    (n1, m1, s1), (n2, m2, s2), mm_key = s["votes"]
    c1, c2, c3 = analyze.camelot(n1, m1), analyze.camelot(n2, m2), analyze.camelot(mm_key[0], mm_key[1])
    votes = [c1, c2, c3]
    from collections import Counter
    top, nt = Counter(votes).most_common(1)[0]
    if nt == 1:
        top = c1
    strength = s1 if top == c1 else (s2 if top == c2 else max(s1, s2))
    if nt == 3:
        kc, rule = (1.0 if strength >= 0.6 else 0.6), "all three agree"
    elif nt == 2:
        dissent = [c for c in votes if c != top][0]
        if analyze.camelot_neighbour(top, dissent):
            kc, rule = 0.65, "2 of 3 agree, dissenter is a Camelot neighbour"
        else:
            kc, rule = 0.45, "2 of 3 agree, dissenter incompatible"
        if strength < 0.6:
            kc, rule = 0.3, rule + "; strength < 0.6"
    else:
        kc, rule = 0.3, "no two detectors agree"
    key = {"essentia_edma": [n1, m1, round(s1, 3)], "essentia_bgate": [n2, m2, round(s2, 3)],
           "madmom_cnn": [mm_key[0], mm_key[1], round(mm_key[2], 3)],
           "camelot_edma": c1, "camelot_bgate": c2, "camelot_madmom": c3,
           "camelot": top, "confidence": kc, "confidence_rule": rule}

    mean_vocal = float(np.clip(vocal_bar.mean() + rng.normal(0, 0.01), 0, 1))
    flags = []
    vocal_heavy = mean_vocal > 0.75
    if bpm < 100 or abs(mult_tag - 1.0) > 1e-6:
        flags.append("half_time_candidate")
    if vocal_heavy:
        flags.append("vocal_heavy")
    if fade_out:
        flags.append("fade_out")
    if G["confidence"] < 0.5:
        flags.append("low_grid_confidence")
    if kc < 0.5:
        flags.append("key_uncertain")
    if mix_in["bars"] < 16 or mix_in["vocal_free_bars"] < 8:
        flags.append("short_intro")
    if mix_out["bars"] < 16 or mix_out["vocal_free_bars"] < 8:
        flags.append("short_outro")

    pat = np.array([1.0 if i % 4 == 0 else (0.55 if i % 2 == 0 else 0.3) for i in range(16)])
    pat = np.clip(pat + rng.normal(0, 0.06, 16), 0.05, None)
    pat = pat / pat.max()
    style = np.random.default_rng(77 + ["dance original", "pool edit", "official remix", "pop original",
                                        "slow / R&B"].index(s["kind"])).random(1280)
    emb = np.clip(0.6 * style + 0.4 * rng.random(1280), 0, None)

    def tdev(g):
        return round(tag_dev(g), 2)

    alt = {k_: ({"bpm": round(g_["bpm"], 3), "fit_mad_ms": round(g_["fit_mad_ms"], 2),
                 "confidence": round(g_["confidence"], 3), "tag_dev_pct": tdev(g_)} if g_ is not None else None)
           for k_, g_ in grids.items()}
    hop_s = 62 * 256 / 16000.0
    title = f"{s['artist']} - {s['song']}"
    out = {
        "schema": analyze.SCHEMA_VERSION, "id": s["id"], "title": title, "ver": s["ver"],
        "path": f"{MUSIC}{s['folder']}/{title}{(' (' + s['ver'] + ')') if s['ver'] else ''}.mp3",
        "sr": analyze.SR, "duration_s": round(duration, 3), "bpm_tag": tag,
        "bpm_beatthis": r3(grid_bt["bpm"]) if grid_bt else None,
        "bpm_beatthis_median_ibi": r3(60 / np.median(np.diff(bt))) if len(bt) > 2 else None,
        "bpm_essentia": r3(bpm_ess), "essentia_confidence": r3(rng.uniform(1.0, 4.0)),
        "essentia_agree": bool(ess_dev is not None and ess_dev < 2.0),
        "bpm_madmom": r3(grids["madmom"]["bpm"]) if grids.get("madmom") else None,
        "madmom_ran": run_mm, "madmom_reason": madmom_reason,
        "bpm": round(bpm, 3), "bpm_agree": bpm_agree,
        "multiplier_vs_tag": analyze.mult_label(mult_tag), "multiplier_vs_tag_value": round(mult_tag, 4),
        "tag_dev_pct": round(dev_tag, 2),
        "octave_fix": {"mode": "halved", "from_bpm": round(2 * bpm, 3), "parity": 0} if special == "octave" else None,
        "grid": {"source": grid_src, "bpm": round(bpm, 3), "first_downbeat_s": round(fd, 4),
                 "beat_s": round(P, 5), "bar_s": round(bar_s, 5), "fit_mad_ms": round(G["fit_mad_ms"], 2),
                 "inlier_frac": round(G["inlier_frac"], 3), "downbeat_agree": round(G["downbeat_agree"], 3),
                 "confidence": round(G["confidence"], 3), "n_bars": n_bars},
        "grid_candidates": alt,
        "beats_s": analyze.rlist(grid_beats_all), "downbeats_s": analyze.rlist(bar_t),
        "detected_beats_s": analyze.rlist(bt), "detected_downbeats_s": analyze.rlist(bt_downs),
        "madmom_downbeats_s": analyze.rlist(mm_downs) if mm_downs is not None else None,
        "phrase": {"lattice_phase_bar": ph + 1, "phrase_len_bars": 8, "confidence": round(phrase_conf, 3),
                   "phase_novelty": analyze.rlist(sums, 3), "snap_phase_bar": snap_phase + 1},
        "boundaries_bars": [b + 1 for b in boundaries0],
        "novelty_peaks": [[b + 1, round(v, 3)] for b, v in sorted(peaks)],
        "sections": sections,
        "first_sound_s": round(first_sound, 3), "last_sound_s": round(last_sound, 3),
        "fade_out": fade_out, "fade_drop_lu": round(fade_drop, 2),
        "end_lufs_st": {"t-20": round(l20, 2), "t-10": round(l10, 2), "t-4": round(l4, 2)},
        "tail_bars": round(float(tail_bars), 2),
        "fade_start_bar": fade_start_bar + 1 if fade_start_bar is not None else None,
        "mix_in": mix_in, "mix_out": mix_out, "key": key,
        "loudness": {"integrated_lufs": round(med - 0.6, 2), "lra": r3(rng.uniform(2.5, 8.0)),
                     "true_peak_db": round(float(rng.uniform(-1.0, 1.2)), 2)},
        "per_bar": {"lufs_st": analyze.rlist(lufs, 2), "low_db": analyze.rlist(low, 2),
                    "high_db": analyze.rlist(high, 2), "onset_density": analyze.rlist(onset, 3),
                    "vocal_prob": analyze.rlist(vocal_bar, 3)},
        "onset_pattern_16": analyze.rlist(pat, 4),
        "vocal": {"mean_prob": round(mean_vocal, 4), "vocal_heavy": vocal_heavy, "patch_hop_s": round(hop_s, 4),
                  "n_patches": int(duration / hop_s)},
        "embedding_effnet": [round(float(v), 4) for v in emb],
        "flags": flags,
        "meta": {"secs": s["secs"], "on_disc": s["disc"] is not None, "disc": s["disc"], "folder": s["folder"],
                 "hal": s["hal"], "kind": s["kind"], "era": s["era"], "cut_key": cut_key(s),
                 "is_longest": is_longest(s)},
        "timing_s": dict({"decode": 0.2, "beatthis": 0.6, "essentia_rhythm": 2.1, "key": 5.4, "spectral": 0.1,
                          "structure": 0.01, "loudness": 3.1, "effnet": 0.9}, **({"madmom": 4.2} if run_mm else {})),
        "beatthis_device": "mps",
    }
    out["local_tempo"] = local_tempo.compute(out)
    for fl in local_tempo.flags(out["local_tempo"]):
        if fl not in out["flags"]:
            out["flags"].append(fl)
    return out


def cut_key(s):
    return s.get("cut") or f"{s['artist']} {s['song']}".lower()


def is_longest(s):
    same = [x for x in SONGS if cut_key(x) == cut_key(s)]
    return s["secs"] == max(x["secs"] for x in same)


def main():
    os.makedirs(os.path.join(OUT, "features"), exist_ok=True)
    for name in os.listdir(os.path.join(OUT, "features")):
        os.remove(os.path.join(OUT, "features", name))
    rows = []
    for k, s in enumerate(SONGS):
        d = make(s, k)
        with open(os.path.join(OUT, "features", s["id"] + ".json"), "w") as fh:
            json.dump(d, fh, ensure_ascii=False)
        rows.append({"id": s["id"], "title": d["title"], "ver": s["ver"], "path": d["path"], "bpm_tag": d["bpm_tag"],
                     "secs": s["secs"], "hal": s["hal"], "kind": s["kind"], "era": s["era"],
                     "on_disc": s["disc"] is not None, "disc": s["disc"], "folder": s["folder"],
                     "artist": s["artist"], "song": s["song"], "cut_key": cut_key(s), "is_longest": is_longest(s)})
        print(f"{s['id']}: {d['grid']['source']} {d['bpm']} BPM, {d['grid']['n_bars']} bars, conf "
              f"{d['grid']['confidence']}, key {d['key']['camelot']} ({d['key']['confidence']}), flags {d['flags']}")
    with open(os.path.join(OUT, "candidates.json"), "w") as fh:
        json.dump(rows, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    # the lab's scorer and the reference numbers, on the sample
    import subprocess
    env = dict(os.environ, DECKIE_LAB_DATA=OUT)
    py = sys.executable
    subprocess.run([py, os.path.join(ROOT, "mixer", "score.py")], env=env, check=True)
    for name in ("pairs.json", "recs.md"):  # score.py's other outputs; the tests read recs.json only
        os.remove(os.path.join(OUT, name))
    subprocess.run([py, os.path.join(HERE, "make_fixtures.py"), "--lab", OUT], env=env, check=True)
    subprocess.run([newer_python(), "-I", os.path.join(HERE, "make_bench_fixtures.py"), "--lab", OUT], env=env,
                   check=True)


def newer_python():
    """A Python of 3.12 or later for make_bench_fixtures.py (whose sums must be 3.12's): this one, one on the PATH,
    or one uv manages."""
    import shutil
    import subprocess
    if sys.version_info >= (3, 12):
        return sys.executable
    for v in ("3.15", "3.14", "3.13", "3.12"):
        if shutil.which("python" + v):
            return shutil.which("python" + v)
    if shutil.which("uv"):
        found = subprocess.run(["uv", "python", "find", ">=3.12"], capture_output=True, text=True)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    sys.exit("make_bench_fixtures.py needs Python 3.12 or later; none found")


if __name__ == "__main__":
    main()
