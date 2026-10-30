#!/usr/bin/env python3
"""Research R, the next test: overtones taken out of the chroma before the key decision, on the outside set
(GiantSteps-MTG-key, the Beatport EDM Key Dataset; Faraldo 2017; Zenodo 10.5281/zenodo.1101082, annotations CC BY-SA
4.0). Aimed first at the home note (the tonic: the key's letter, whatever the mode) and second at the mode.

Why. A played note sounds its overtones too: the third harmonic lands an octave and a fifth above it, the fifth harmonic
two octaves and a major third above it. The recommended reader (key_parity.recommended, row 3f) folds a peak's energy
back toward f/h, which adds to the roots, but it never removes the overtone's own energy from the fifth's and the major
third's pitch classes. So a minor tonic's fifth harmonic props up the major third (the mode lean: minor keys read as
major), and every note's third harmonic props up its fifth (the dominant read as the home note). A twelve-bin profile
cannot tell an overtone from a played note. Two ways to take them out, both fixed before the run:

Part A, the harmonic discount (open item 5 of the letter), from the per-frame cache key_mode.py wrote.
  For each frame t and pitch class k:  p'_t[k] = max(0, p_t[k] - w * p_t[k - d])
  with (d, w) = (7, 0.6**2) for the third harmonic (the fifth above a root) and (4, 0.6**4) for the fifth harmonic (the
  major third above a root). The weights are the reader's own harmonic slope, 0.6 per harmonic (Gomez 2006, Tonal
  Description of Music Audio Signals, PhD thesis, UPF, section 3; key_parity.harmonic_template), so no new number is
  introduced. "both" takes both shares off the original frame at once (not one after the other).
  Variants: {third only, fifth only, both} x {per frame, on the clip's summed 12-vector} x {H4w, H1w}, each followed by
  key_parity.decide (the three Faraldo profiles averaged, as 3f). Per frame is the principled version: an overtone is
  energy that sounds at the same moment as its root, so the share to take off a pitch class is set by the root's energy
  in that same frame. On the summed vector, a root that sounds in one bar is used to discount a fifth that sounds in
  another, which removes energy the overtone never put there; the summed form is reported for comparison only.
  Inputs: H4w (row 3f's own whitened 4-harmonic HPCP per frame, not frame-normalised) and H1w (whitened, 1 harmonic:
  no folding toward the roots, so the overtones are all still in it).

Part B, NNLS chroma (approximate transcription: working out which notes were played, roughly, before folding into
twelve pitch classes). Mauch and Dixon 2010, "Approximate note transcription for the improved identification of
difficult chords", ISMIR 2010 (Utrecht), pp. 135-140; defaults of the NNLS Chroma / Chordino Vamp plugin by the same
author (README and source of release 0.2, GPL; read, not copied: this file is our own arithmetic from the paper's
description). Every value and its source:
  - audio at 11,025 Hz, Hamming-windowed frames of 4,096 samples (0.37 s; "the shortest that can resolve a full tone in
    the bass region around MIDI note 44"), paper 2.2. The plugin's 16,384 samples at 44.1 kHz is the same window.
  - hop: the paper's is 2,048 at 11,025 Hz (its text says about 0.05 s, which is the plugin's 2,048 at 44.1 kHz). Here
    the hop is 1,024 at 11,025 Hz (= 4,096 at 44.1 kHz, 93 ms), the reader's own frame rate (10.77 a second), and the
    signal is padded with 1,536 samples at the start so each frame's centre sits on the centre of the matching frame
    of the H4w cache. Half the plugin's frame rate; whole-clip sums do not need more.
  - log-frequency spectrum: magnitude spectrum mapped by cosine interpolation on the linear and the log scale onto 256
    bins a third of a semitone apart, MIDI 20 to 105 (paper 2.2; plugin logFreqMatrix: one extra semitone at each end,
    80-fold oversampling of the DFT).
  - global tuning: the phase of the energy summed per third-of-a-semitone position (bin index mod 3), over the lower
    62 percent of the bins (plugin), the spectrum shifted by linear interpolation so each semitone's centre bin is in
    tune (paper 2.2).
  - pre-processing "std" (paper 2.3, the best in the paper's Table 1, and the plugin's default whitening 1.0): subtract
    the running mean over a Hamming-windowed octave (bins k-18 to k+18), divide by the running standard deviation over
    the same window, negative values set to 0. Edges take the value of the nearest fully covered bin. This plays the
    part of row 3f's running-max whitening.
  - note dictionary: 84 notes, A0 (27.5 Hz, MIDI 21) to G#7 (3,322 Hz; the paper names it G#6 with the frequency
    3,322 Hz, MIDI 104), 20 harmonics (plugin dictionaryMatrix), harmonic k with amplitude s**(k-1) (paper eq. 3),
    each harmonic spread by a raised cosine over +-1.5 bins (plugin cospuls), every note profile normalised to sum 1
    (paper 2.4).
  - s: the paper tested s = 0.6 (Gomez's value; best on the MIREX chord metric, 80.0), s = 0.9 (from Mauch et al.
    2009), and "LS": s linearly spaced from 0.9 for the lowest note to 0.6 for the highest (best on the finer metric,
    63.3); the plugin's default is s = 0.7. All four run as fixed variants: s06, s09, sLS, s07.
  - NNLS per frame (paper 2.4; scipy.optimize.nnls, Lawson and Hanson 1974), only the notes whose band of the
    pre-processed spectrum holds any energy enter the fit (plugin).
  - chroma (paper 2.5, Figure 2): the 84 note activations summed into 12 pitch classes after weighting by the plugin's
    treble window (a sin**2 bell over the 84 notes, peak at notes 41-42, D4/D#4) or bass window (a sin**2 bell over
    notes 0-36, A0 to A3, peak at note 18, D#2). The plugin tabulates both (chromamethods.h); the closed forms
    sin**2(pi (i + 0.5) / 84) and sin**2(pi (i + 0.5) / 37.35) reproduce its values to within 1e-5 (treble) and 1.1e-3
    (bass), checked by `check`. The paper's chord model reads the bass and treble chroma separately, so three ranges
    run: full (no window), treble and bass.
  Each NNLS chroma is summed over the clip and decided with key_parity.decide against the Faraldo average (as 3f) and
  against each single profile set in key_light.PROFILES (krumhansl, temperley, shaath, edma, bgate, braw): an NNLS
  chroma has the shape of played notes, which the Faraldo profiles (taken from HPCP-like chroma) may not fit.
  Caution: braw and bgate (Faraldo 2017) were made from Beatport EDM, the music of this data set, so rows that use them
  are not clean outside measurements of those profiles.

No fitting (library-blind, D5). Every value above is the reader's own or published. Picking the best row is still a
choice, so it is made on the selection half only: odd-numbered clip ids with data set confidence 2, by balanced home
note (the mean of the major-key and minor-key home-note rates, home note = exact + parallel, so a mode-leaning row
cannot win on this 70-percent-minor set by its prior), ties broken by balanced exact. Every row is reported on the
held-out half (even ids, confidence 2), on all 1,275 clips and on the 1,270 Apple read.

usage (from mixer/, at nice 19, never more than 2 workers: the machine rule of Oct 29):
  nice -n 19 .venv/bin/python key_overtones.py check   [--data D]             3f from the cache vs key_outside_results
  nice -n 19 .venv/bin/python key_overtones.py extract --data D [--jobs 2] [--limit N]   NNLS notes per frame -> cache
  nice -n 19 .venv/bin/python key_overtones.py score   --data D [--a-only] [--out key_overtones.tsv]
D is the folder with audio/ and Beatport-EDM-Key-Dataset.xlsx. The audio is third-party, fetched for internal
evaluation only: it stays in the scratchpad, is never committed and never ships; this script reads it by path and
imports nothing from it. Caches (not committed): $DECKIE_KEYMODE_CACHE (H4w, H1w per frame, from key_mode.py extract)
and $DECKIE_KEYNNLS_CACHE or <scratchpad>/keynnls_cache/<id>.npz (float32 note activations per frame, T x 84, one
array per s; resumable)."""
import csv, os, sys, time, warnings
from collections import Counter
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import key_light as KL
import key_parity as KP
import key_mode as KM      # clips(), free_bytes(), CACHE (the H4w / H1w per-frame cache)

NNLS_CACHE = os.environ.get("DECKIE_KEYNNLS_CACHE", os.path.join(KM.SCRATCH, "keynnls_cache"))
MIN_FREE = 4 * 1024 ** 3
MIREX = {"exact": 1.0, "fifth": 0.5, "relative": 0.3, "parallel": 0.2}

# ----------------------------------------------------------------------------------------------- Part A
SLOPE = 0.6                                         # the reader's harmonic slope (Gomez 2006; KP.harmonic_template)
SHARES = {"h3": ((7, SLOPE ** 2),), "h5": ((4, SLOPE ** 4),), "both": ((7, SLOPE ** 2), (4, SLOPE ** 4))}

def discount(P, which):
    """P: (T, 12) or (12,), C = 0. Takes off each pitch class the share the reader's harmonic model says the overtones
    of the root d semitones below put there: p'[k] = max(0, p[k] - sum w p[k - d]), all shares from the original p."""
    P = np.asarray(P, float); ax = P.ndim - 1
    return np.maximum(0.0, P - sum(w * np.roll(P, d, axis=ax) for d, w in SHARES[which]))

A_VARIANTS = [f"A-{w}-{how}-{inp}" for inp in ("H4w", "H1w") for how in ("frame", "sum") for w in ("h3", "h5", "both")]

def part_a(z):
    """name -> summed 12-vector, for the two baselines and the twelve Part A rows."""
    out = {"3f": z["H4w"].sum(axis=0), "H1w": z["H1w"].sum(axis=0)}
    for inp in ("H4w", "H1w"):
        X = z[inp].astype(np.float64)
        for w in SHARES:
            out[f"A-{w}-frame-{inp}"] = discount(X, w).sum(axis=0)
            out[f"A-{w}-sum-{inp}"] = discount(X.sum(axis=0), w)
    return out

# ----------------------------------------------------------------------------------------------- Part B
SR_B, N_B, H_B, PAD_B = 11025, 4096, 1024, 1536
NBPS, NBIN, MIDI0 = 3, 256, 20                      # bin j sits at MIDI 20 + j / 3; semitone n (MIDI 21 + n) at bin 3 + 3 n
NNOTE, NHARM = 84, 20
S_VALUES = {"s06": 0.6, "s07": 0.7, "s09": 0.9, "sLS": None}
RANGES = ("full", "treble", "bass")
PROFILE_SETS = ("faraldo",) + tuple(KL.PROFILES)    # Faraldo average (3f's decision) and the six single profile sets
TREBLE = np.sin(np.pi * (np.arange(NNOTE) + 0.5) / 84) ** 2
BASS = np.where(np.arange(NNOTE) <= 36, np.sin(np.pi * (np.arange(NNOTE) + 0.5) / 37.35) ** 2, 0.0)
_PLUGIN_SAMPLES = {"treble": {0: 0.000350, 6: 0.057942, 42: 0.999650, 78: 0.041719, 83: 0.000350},
                   "bass": {0: 0.001769, 6: 0.270509, 18: 0.999803, 30: 0.295778, 36: 0.004909, 42: 0.0}}

def rcos(d):
    """raised cosine of half-width 1 (d in units of the half-width)."""
    return np.where(np.abs(d) < 1, 0.5 + 0.5 * np.cos(np.pi * d), 0.0)

_LF = None
def logfreq_matrix():
    """(256, nfft_bins) map from the DFT magnitude to the log-frequency bins: each DFT bin spread by a raised cosine of
    half-width one bin on the linear scale, each oversampled point (80 per DFT bin) given to the log bins by a raised
    cosine of half-width one log bin (a third of a semitone)."""
    global _LF
    if _LF is not None: return _LF
    nfft = N_B // 2 + 1; df = SR_B / N_B
    fmax = 440 * 2 ** ((MIDI0 + (NBIN + 1) / NBPS - 69) / 12)
    kmax = int(np.ceil(fmax / df)) + 2
    os_ = 80; f = np.arange(0, kmax * os_) * (df / os_)
    M = np.zeros((NBIN, nfft))
    pos = np.full(len(f), -1e9); ok = f > 0
    pos[ok] = (12 * np.log2(f[ok] / 440) + 69 - MIDI0) * NBPS              # fractional log-bin position
    for k in range(1, kmax):
        sl = slice(max(0, (k - 1) * os_), (k + 1) * os_ + 1)
        a = rcos((f[sl] - k * df) / df)                                       # the DFT bin's share of each point
        p = pos[sl]; lo = np.floor(p).astype(int)
        for off in (0, 1):
            j = lo + off; w = rcos(p - j) * a; sel = (j >= 0) & (j < NBIN) & (w > 0)
            np.add.at(M[:, k], j[sel], w[sel])
    _LF = M; return M

_DICT = {}
def dictionary(name):
    """(256, 84) note profiles: harmonic h of note n at bin 3 + 3 n + 36 log2 h with amplitude s**(h-1), spread by a
    raised cosine over +-1.5 bins, each column normalised to sum 1."""
    if name in _DICT: return _DICT[name]
    E = np.zeros((NBIN, NNOTE)); bins = np.arange(NBIN)
    for n in range(NNOTE):
        s = S_VALUES[name] if S_VALUES[name] is not None else 0.9 + (0.6 - 0.9) * n / (NNOTE - 1)
        for h in range(1, NHARM + 1):
            c = 3 + 3 * n + 36 * np.log2(h)
            if c > NBIN + 1: break
            E[:, n] += rcos((bins - c) / 1.5) * s ** (h - 1)
        E[:, n] /= E[:, n].sum()
    _DICT[name] = E; return E

def hamming_running(Y, half=18):
    """running mean and standard deviation over a Hamming-windowed neighbourhood k-half .. k+half (per frame), the
    edges set to the nearest fully covered bin."""
    w = np.hamming(2 * half + 1); w = w / w.sum()
    conv = lambda X: np.apply_along_axis(lambda r: np.convolve(r, w, mode="valid"), 1, X)
    mu_c = conv(Y); sd_c = np.sqrt(np.maximum(conv(Y ** 2) - mu_c ** 2, 0.0))
    pad = lambda X: np.concatenate([np.repeat(X[:, :1], half, 1), X, np.repeat(X[:, -1:], half, 1)], axis=1)
    return pad(mu_c), pad(sd_c)

def nnls_notes(y44, n_frames):
    """{s name: (T, 84) note activations} and the tuning (semitones) for one clip; T = n_frames, aligned to H4w."""
    import librosa
    from scipy.optimize import nnls
    y = librosa.resample(y44, orig_sr=KP.SR44, target_sr=SR_B, res_type="soxr_hq")
    need = (n_frames - 1) * H_B + N_B
    y = np.concatenate([np.zeros(PAD_B, np.float32), y])
    if len(y) < need: y = np.concatenate([y, np.zeros(need - len(y), np.float32)])
    fr = np.lib.stride_tricks.sliding_window_view(y, N_B)[::H_B][:n_frames] * np.hamming(N_B).astype(np.float32)
    X = np.abs(np.fft.rfft(fr, axis=1))
    Y = X @ logfreq_matrix().T                                               # (T, 256)
    # global tuning: phase of the energy per third-of-a-semitone position (bin j's position is j mod 3; centres at 0)
    top = int(round(NNOTE * 0.62)) * NBPS + 1
    e = Y[:, :top].sum(axis=0); ang = np.angle(np.sum(e * np.exp(2j * np.pi * np.arange(top) / NBPS)))
    tun = ang / (2 * np.pi)                                                  # in semitones, -0.5 .. 0.5
    shift = tun * NBPS; i0 = int(np.floor(shift)); fs = shift - i0
    idx = np.arange(NBIN); a = np.clip(idx + i0, 0, NBIN - 1); b = np.clip(idx + i0 + 1, 0, NBIN - 1)
    Yt = Y[:, a] * (1 - fs) + Y[:, b] * fs
    mu, sd = hamming_running(Yt)
    Ys = np.where((Yt - mu > 0) & (sd > 0), (Yt - mu) / np.where(sd > 0, sd, 1), 0.0)
    out = {k: np.zeros((n_frames, NNOTE), np.float32) for k in S_VALUES}
    bands = np.stack([Ys[:, 3 + 3 * n - 1:3 + 3 * n + 2].sum(axis=1) for n in range(NNOTE)], axis=1)   # (T, 84)
    D = {k: dictionary(k) for k in S_VALUES}
    for t in range(n_frames):
        sig = np.nonzero(bands[t] > 0)[0]
        if not len(sig): continue
        for k in S_VALUES:
            x, _ = nnls(D[k][:, sig], Ys[t], maxiter=2000)
            out[k][t, sig] = x
    return out, float(tun)

def extract_one(item):
    cid, path = item
    dst = os.path.join(NNLS_CACHE, cid + ".npz")
    if os.path.exists(dst): return cid, "cached", 0.0
    t0 = time.time()
    try:
        y, _ = KP.load44(path)
        n = 1 + max(0, (len(y) - KP.N44) // KP.H44)
        notes, tun = nnls_notes(y, n)
        np.savez_compressed(dst + ".tmp.npz", tuning=np.float32(tun), **notes)
        os.replace(dst + ".tmp.npz", dst)
        return cid, "ok", time.time() - t0
    except Exception as e:
        return cid, f"error {e}", time.time() - t0

def main_extract(data, jobs, limit):
    jobs = min(jobs, 2)                                                       # machine rule: never more than 2 workers
    os.makedirs(NNLS_CACHE, exist_ok=True)
    _, todo = KM.clips(data)
    todo = todo[:limit]
    todo = [x for x in todo if not os.path.exists(os.path.join(NNLS_CACHE, x[0] + ".npz"))]
    if KM.free_bytes() < MIN_FREE: sys.exit(f"free plus inactive {KM.free_bytes() / 1e9:.1f} GB < 4 GB, not starting")
    logfreq_matrix(); [dictionary(k) for k in S_VALUES]
    print(f"NNLS extraction: {len(todo)} clips, {jobs} worker(s), into {NNLS_CACHE}", flush=True)
    from multiprocessing import Pool
    t0 = time.time(); per = []
    with Pool(jobs) as pool:
        for k, (cid, st, dt) in enumerate(pool.imap_unordered(extract_one, todo, chunksize=4), 1):
            if st.startswith("error"): print(cid, st, flush=True)
            elif st == "ok": per.append(dt)
            if k % 25 == 0 or k == len(todo):
                fb = KM.free_bytes()
                print(f"{k}/{len(todo)} {time.time() - t0:.0f}s  {np.mean(per) if per else 0:.2f}s per clip per worker  "
                      f"free+inactive {fb / 1e9:.1f} GB", flush=True)
                if fb < MIN_FREE: pool.terminate(); sys.exit("stopping: free plus inactive under 4 GB (rerun resumes)")
    print(f"extracted {len(per)} in {time.time() - t0:.0f}s wall, {np.mean(per) if per else 0:.2f}s per clip per worker", flush=True)

B_VARIANTS = [f"B-{s}-{r}-{p}" for s in S_VALUES for r in RANGES for p in PROFILE_SETS]

def part_b(zb):
    out = {}
    for s in S_VALUES:
        Xs = zb[s].astype(np.float64).sum(axis=0)                            # (84,) note activations summed over the clip
        for r, w in (("full", np.ones(NNOTE)), ("treble", TREBLE), ("bass", BASS)):
            c = np.zeros(12)
            np.add.at(c, (np.arange(NNOTE) + 21) % 12, Xs * w)                # note n is MIDI 21 + n; C = 0
            out[(s, r)] = c
    return out

def decide_with(pcp, pset):
    return KP.decide(pcp) if pset == "faraldo" else KP.decide(pcp, profiles=(pset,))

# ----------------------------------------------------------------------------------------------- scoring
def tonic(cam):
    i = (KL.CAM_MAJ + KL.CAM_MIN).index(cam); return i % 12

def stats(rows, v):
    """percent figures for variant v over rows (relation column v + '_rel')."""
    L = [r for r in rows if r.get(v)]
    n = len(L)
    if not n: return {"n": 0}
    c = Counter(r[v + "_relation"] for r in L)
    d = {k: 100 * c[k] / n for k in ("exact", "fifth", "relative", "parallel")}
    d["other"] = 100 - sum(d.values()); d["home"] = d["exact"] + d["parallel"]; d["camelot"] = d["exact"] + d["relative"]
    d["mirex"] = 100 * sum(MIREX.get(k, 0) * x for k, x in c.items()) / n; d["n"] = n
    return d

def sign_p(g, l):
    """two-sided exact sign test: probability of a split at least this uneven among g + l discordant clips."""
    from math import comb
    n = g + l
    if not n: return 1.0
    k = min(g, l); return min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n)

def halves(rows):
    return [r for r in rows if r["camelot"].endswith("B")], [r for r in rows if r["camelot"].endswith("A")]

def balanced(rows, v, key):
    ma, mi = halves(rows); return (stats(ma, v)[key] + stats(mi, v)[key]) / 2

HEAD = ("| row | clips | exact | fifth | relative | parallel | other | home note | Camelot number | MIREX |\n"
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
def line(label, s):
    if not s["n"]: return f"| {label} | 0 | | | | | | | | |"
    return (f"| {label} | {s['n']} | {s['exact']:.1f} | {s['fifth']:.1f} | {s['relative']:.1f} | {s['parallel']:.1f} | "
            f"{s['other']:.1f} | {s['home']:.1f} | {s['camelot']:.1f} | {s['mirex']:.1f} |")

def main_check(data):
    ann, todo = KM.clips(data)
    prev = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "key_outside_results.tsv")), delimiter="\t")}
    bad = n = 0
    for cid, _ in todo:
        p = os.path.join(KM.CACHE, cid + ".npz")
        if not os.path.exists(p) or cid not in prev: continue
        n += 1; bad += KP.decide(np.load(p)["H4w"].sum(axis=0))[0] != prev[cid]["predicted"]
    print(f"3f from the H4w cache against key_outside_results.tsv: {n - bad} of {n} clips match")
    for nm, ref in (("treble", TREBLE), ("bass", BASS)):
        err = max(abs(ref[i] - v) for i, v in _PLUGIN_SAMPLES[nm].items())
        print(f"{nm} window closed form against the plugin's tabulated samples: largest difference {err:.5f}")
    return bad

def main_score(data, a_only, out_path):
    t0 = time.time()
    ann, todo = KM.clips(data)
    prev = {r["id"]: r for r in csv.DictReader(open(os.path.join(HERE, "key_outside_results.tsv")), delimiter="\t")}
    apple = {r["id"]: r["apple"] for r in csv.DictReader(open(os.path.join(HERE, "key_outside_apple.tsv")), delimiter="\t")}
    variants = ["3f", "H1w"] + A_VARIANTS + ([] if a_only else B_VARIANTS)
    rows = []; mism = 0; missing_b = 0
    for cid, _ in todo:
        z = np.load(os.path.join(KM.CACHE, cid + ".npz"))
        v = ann[cid]; cam = v["camelot"]
        row = {"id": cid, "annotation": v["main_key"], "camelot": cam, "confidence": v["confidence"],
               "half": "odd" if int(cid) % 2 else "even", "ours_3f": prev[cid]["predicted"], "apple": apple.get(cid, "")}
        if row["apple"]: row["apple_relation"] = KP.relation(row["apple"], cam)[1]
        res = {k: KP.decide(p) for k, p in part_a(z).items()}
        if not a_only:
            pb = os.path.join(NNLS_CACHE, cid + ".npz")
            if os.path.exists(pb):
                C = part_b(np.load(pb))
                for s in S_VALUES:
                    for r in RANGES:
                        for p in PROFILE_SETS: res[f"B-{s}-{r}-{p}"] = decide_with(C[(s, r)], p)
            else: missing_b += 1
        mism += res["3f"][0] != row["ours_3f"]
        for k in variants:
            if k in res:
                c, m, ag, sure = res[k]
                row[k] = c; row[k + "_relation"] = KP.relation(c, cam)[1]; row[k + "_margin"] = f"{m:.4f}"; row[k + "_sure"] = int(sure)
            else:
                row[k] = row[k + "_relation"] = row[k + "_margin"] = row[k + "_sure"] = ""
        rows.append(row)
    print(f"{len(rows)} clips; 3f from the cache differs from key_outside_results.tsv on {mism}"
          + ("" if a_only else f"; NNLS cache missing for {missing_b}"))
    cols = ["id", "annotation", "camelot", "confidence", "half", "ours_3f", "apple"]
    for k in variants: cols += [k, k + "_relation", k + "_margin", k + "_sure"]
    with open(out_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t", extrasaction="ignore"); w.writeheader(); w.writerows(rows)
    report(rows, variants, a_only)
    print(f"\nscoring took {time.time() - t0:.1f}s; wrote {out_path}")

def report(rows, variants, a_only):
    sel = [r for r in rows if r["half"] == "odd" and r["confidence"] == 2]
    ho = [r for r in rows if r["half"] == "even" and r["confidence"] == 2]
    ap = [r for r in rows if r["apple"]]
    have = [v for v in variants if all(r.get(v) for r in rows)]
    # 1. selection on the odd ids by balanced home note, ties by balanced exact
    key = lambda v: (round(balanced(sel, v, "home"), 6), round(balanced(sel, v, "exact"), 6))
    cand_a = [v for v in A_VARIANTS if v in have]; cand_b = [v for v in B_VARIANTS if v in have]
    best_a = max(cand_a, key=key); best_b = max(cand_b, key=key) if cand_b else None
    print(f"\n## Every row: selection half (odd ids, confidence 2, {len(sel)} clips) and held-out half (even ids, "
          f"confidence 2, {len(ho)} clips), balanced over the major and minor halves; and all {len(rows)} clips")
    print("| row | sel. balanced home note | sel. balanced exact | held-out balanced home note | held-out balanced exact | "
          "held-out home note | held-out exact | all home note | all exact | all MIREX | differs from 3f | exact gained | exact lost |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for v in sorted(have, key=lambda v: (v not in ("3f", "H1w"), v[0], [-x for x in key(v)])):
        s_ho, s_all = stats(ho, v), stats(rows, v)
        ch = [r for r in rows if r[v] != r["3f"]]
        up = sum(1 for r in ch if r[v + "_relation"] == "exact" and r["3f_relation"] != "exact")
        dn = sum(1 for r in ch if r["3f_relation"] == "exact" and r[v + "_relation"] != "exact")
        print(f"| {v} | {balanced(sel, v, 'home'):.1f} | {balanced(sel, v, 'exact'):.1f} | {balanced(ho, v, 'home'):.1f} | "
              f"{balanced(ho, v, 'exact'):.1f} | {s_ho['home']:.1f} | {s_ho['exact']:.1f} | {s_all['home']:.1f} | "
              f"{s_all['exact']:.1f} | {s_all['mirex']:.1f} | {len(ch)} | {up} | {dn} |")
    print(f"\nbest Part A row on the selection half: {best_a}" + (f"; best Part B row: {best_b}" if best_b else ""))
    show = ["3f", "H1w", best_a] + ([best_b] if best_b else [])
    for title, sub in ((f"Selection half (odd ids, confidence 2)", sel), (f"Held-out half (even ids, confidence 2)", ho),
                       (f"All plain-key clips", rows)):
        print(f"\n## {title}\n" + HEAD)
        for nm, L in (("all", sub),) + tuple(zip(("major", "minor"), halves(sub))):
            for v in show: print(line(f"{v}, {nm}", stats(L, v)))
        if sub is rows:
            for conf in (2, 1, 0):
                L = [r for r in rows if r["confidence"] == conf]
                for v in show: print(line(f"{v}, confidence {conf}", stats(L, v)))
    print(f"\n## Beside Apple ({len(ap)} clips Apple read)\n" + HEAD)
    for nm, L in (("all", ap),) + tuple(zip(("major", "minor"), halves(ap))):
        print(line(f"Apple, {nm}", stats(L, "apple")))
        for v in show: print(line(f"{v}, {nm}", stats(L, v)))
    # 2. tonic error by interval (predicted tonic minus true tonic), on the 1,270 Apple read
    print(f"\n## Home-note errors by interval, predicted minus true tonic in semitones ({len(ap)} clips; clip counts)")
    readers = ["apple"] + show
    print("| interval | " + " | ".join(readers) + " |\n|---|" + "---:|" * len(readers))
    for d in range(1, 12):
        cnt = [sum(1 for r in ap if (tonic(r[v]) - tonic(r["camelot"])) % 12 == d) for v in readers]
        print(f"| +{d} | " + " | ".join(str(x) for x in cnt) + " |")
    # 3. the flag: is a gain on the selection half held on the held-out half, per bucket
    print("\n## Gain over 3f by bucket (home note, points): selection half / held-out half / all clips")
    for v in show[1:]:
        parts = []
        for nm, f in (("major", lambda r: r["camelot"].endswith("B")), ("minor", lambda r: r["camelot"].endswith("A"))):
            g = [stats([r for r in L if f(r)], v)["home"] - stats([r for r in L if f(r)], "3f")["home"] for L in (sel, ho, rows)]
            parts.append(f"{nm} {g[0]:+.1f} / {g[1]:+.1f} / {g[2]:+.1f}")
        for conf in (2, 1, 0):
            L = [r for r in rows if r["confidence"] == conf]
            parts.append(f"conf {conf} {stats(L, v)['home'] - stats(L, '3f')['home']:+.1f}")
        print(f"- {v}: " + "; ".join(parts))
    # paired count on the held-out half: clips the row gets right that 3f gets wrong, and the reverse, with a two-sided
    # sign test on those discordant clips (exact binomial, p = 1/2); the plain check that a difference is not noise
    print("\n## Held-out half, paired against 3f: clips gained / lost and the two-sided sign test p")
    print("| row | home note gained | lost | p | exact gained | lost | p |\n|---|---:|---:|---:|---:|---:|---:|")
    home_ok = lambda r, v: r[v + "_relation"] in ("exact", "parallel")
    for v in show[1:]:
        cells = []
        for ok in (home_ok, lambda r, v: r[v + "_relation"] == "exact"):
            g = sum(1 for r in ho if ok(r, v) and not ok(r, "3f")); l = sum(1 for r in ho if ok(r, "3f") and not ok(r, v))
            cells += [str(g), str(l), f"{sign_p(g, l):.3f}"]
        print(f"| {v} | " + " | ".join(cells) + " |")
    if not a_only and best_b:
        # per family: the best of each s x range on the selection half, so the letter can show the spread
        print("\n## Part B by family: for each s and range, its Faraldo-average row and the best single profile on the selection half")
        print("| s | range | Faraldo avg: sel. bal. home | held-out bal. home | best profile (sel.) | its sel. bal. home | its held-out bal. home |")
        print("|---|---|---:|---:|---|---:|---:|")
        for s in S_VALUES:
            for r in RANGES:
                fv = f"B-{s}-{r}-faraldo"; vs = [f"B-{s}-{r}-{p}" for p in PROFILE_SETS[1:]]; bv = max(vs, key=key)
                print(f"| {s} | {r} | {balanced(sel, fv, 'home'):.1f} | {balanced(ho, fv, 'home'):.1f} | {bv.split('-')[-1]} | "
                      f"{balanced(sel, bv, 'home'):.1f} | {balanced(ho, bv, 'home'):.1f} |")

if __name__ == "__main__":
    a = sys.argv
    if len(a) < 2: print(__doc__); sys.exit()
    data = a[a.index("--data") + 1] if "--data" in a else os.path.join(KM.SCRATCH, "giantsteps_data")
    if a[1] == "check": main_check(data)
    elif a[1] == "extract":
        main_extract(data, int(a[a.index("--jobs") + 1]) if "--jobs" in a else 2,
                     int(a[a.index("--limit") + 1]) if "--limit" in a else 10 ** 6)
    elif a[1] == "score":
        main_score(data, "--a-only" in a, a[a.index("--out") + 1] if "--out" in a else os.path.join(HERE, "key_overtones.tsv"))
    else: print(__doc__)
