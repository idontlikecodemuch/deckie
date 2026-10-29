#!/usr/bin/env python3
"""Write the reference numbers the spectral and novelty tests compare against: librosa's mel spectrogram, log-mel,
MFCC, RMS and onset strength exactly as mixer/analyze.py calls them, scipy's find_peaks, and the lab's own structure
code (Foote novelty, peaks, phrase), onset density and onset pattern, run on synthesised signals. Nothing here is
downloaded at test time; the Swift tests read the JSON this writes.

  python3 core/Tools/make_spectral_fixtures.py   # from anywhere; needs numpy, scipy and librosa (the lab ran 1.0.0)

The lab's code is not imported (mixer/analyze.py pulls in the whole analysis stack). The pieces used are copied below
as text, checked against mixer/analyze.py before anything runs (the script stops if a copy no longer appears there
word for word), and then executed as they stand.

Every audio input is computed, never stored, by recipes the Swift tests repeat operation for operation (`SpectralSynth`
in SpectralTests.swift), so both sides get the same bits: noise from SplitMix64 (integer arithmetic, then (z >> 11) *
2^-53), tones and kicks from sin() of a phase built with +, -, * and / only (numpy's float64 sin is the C library's
here; exp and log, which numpy computes its own way, are avoided). The signal is then rounded to float32, the type the
lab analyses (`m22 = soxr.resample(...).astype(np.float32)`). Each signal's fixture carries a few samples and two sums
so the tests can check that the Swift synthesis gives the same bits.

Two paths are recorded for every signal:
  float32  the lab's: float32 audio, so librosa's spectrogram, mel projection, log, DCT and RMS run in single
           precision, and the structure code works on float32 matrices
  float64  the same calls given float64 audio, with librosa.feature.rms(..., dtype=np.float64) (its default squares in
           float32 whatever the input); this is what a double-precision port should match to rounding

Output: core/Tests/DeckieCoreTests/Fixtures/spectral.json. The full matrices are too big to store (a 12 s signal has
517 frames of 64 bands), so per signal and path it keeps: every value of a few frames (mel, log-mel, MFCC), the sum of
each frame over the bands and of each band over the frames (so a wrong value anywhere shows; nine significant digits),
and the RMS and onset-strength curves whole. float32 values are written as the shortest text that reads back as the
same float32. The script gives the same file on every run (about 430 KB).
  versions      numpy, scipy, librosa
  melbank       librosa.filters.mel(sr=22050, n_fft=2048, n_mels=64): the 66 mel frequencies and every non-zero
                float32 weight (band, first bin, weights)
  signals       the three spectral test signals (drum loop with a section change, tone sequence, noise with a gap)
  findpeaks     curves and scipy.signal.find_peaks(x, distance=d) on them
  foote         foote_novelty (the lab's function) on SplitMix64 similarity matrices, and its kernel's Gaussian
  track         a synthesised 48-bar track with sections every 8 or 16 bars, run through the lab's spectral block,
                structure block (novelty, peaks, phrase), onset density and onset pattern, both paths
"""
import json, math, os, sys, textwrap, types

import numpy as np
import scipy
from scipy.signal import find_peaks
import librosa

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(TOOLS))
ANALYZE = os.path.join(ROOT, "mixer", "analyze.py")
OUT = os.path.join(os.path.dirname(TOOLS), "Tests", "DeckieCoreTests", "Fixtures", "spectral.json")
SR, HOP = 22050, 512
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB
RAMP = int(0.01 * SR)

# ----------------------------------------------------------------------------- the lab's code, copied from analyze.py
LAB_FOOTE = '''def foote_novelty(S, K=64):
    n = S.shape[0]
    h = K // 2
    g = np.exp(-0.5 * ((np.arange(-h, h) + 0.5) / (h / 2.0)) ** 2)
    G = np.outer(g, g)
    sign = np.ones((K, K))
    sign[:h, h:] = -1
    sign[h:, :h] = -1
    ker = G * sign
    Sp = np.pad(S, h, mode="edge")
    nov = np.zeros(n)
    for i in range(n):
        nov[i] = np.sum(ker * Sp[i:i + K, i:i + K])
    nov = np.maximum(nov, 0)
    if nov.max() > 0:
        nov /= nov.max()
    return nov
'''

LAB_GRID = '''    bar_s = 4 * P
'''
LAB_BARS = '''    bar_t = fd + np.arange(n_bars + 1) * bar_s  # bar k (0-based) spans bar_t[k]..bar_t[k+1]
'''

LAB_SPECTRAL = '''    mel = librosa.feature.melspectrogram(y=m22, sr=sr2, n_fft=2048, hop_length=hop, n_mels=64)
    logmel = librosa.power_to_db(mel)
    mfcc = librosa.feature.mfcc(S=logmel, n_mfcc=13)
    rms = librosa.feature.rms(y=m22, frame_length=2048, hop_length=hop)[0]
    onset_env = librosa.onset.onset_strength(S=logmel, sr=sr2, hop_length=hop)
    fps = sr2 / hop
'''

LAB_STRUCTURE = '''    hb = fd + np.arange(n_bars * 8 + 1) * (P / 2)  # half-beat frame edges, 8 per bar
    hb_fr = np.clip(np.round(hb * fps).astype(int), 0, mfcc.shape[1] - 1)
    mf = np.stack([mfcc[:, a:max(a + 1, b)].mean(axis=1) for a, b in zip(hb_fr[:-1], hb_fr[1:])], axis=1)
    rm = np.array([rms[a:max(a + 1, b)].mean() for a, b in zip(hb_fr[:-1], hb_fr[1:])])
    mfn = mf / (np.linalg.norm(mf, axis=0, keepdims=True) + 1e-9)
    S_mfcc = mfn.T @ mfn
    rdb = 20 * np.log10(rm + 1e-6)
    S_rms = -np.abs(rdb[:, None] - rdb[None, :])
    S_rms = S_rms / (np.abs(S_rms).max() + 1e-9)
    nov = np.sqrt(foote_novelty(S_mfcc) * foote_novelty(S_rms))
    pk_idx, _ = find_peaks(nov, distance=8)
    pk_idx = pk_idx[np.argsort(nov[pk_idx])[::-1][:20]]
    peaks = []
    for p in pk_idx:
        bar = int(round(p / 8))
        if abs(p / 8 - bar) <= 0.4 and 0 < bar < n_bars:
            peaks.append((bar, float(nov[p])))
    sums = np.zeros(8)
    for bar, v in peaks:
        sums[bar % 8] += v
    total = sums.sum()
    phase = int(np.argmax(sums)) if total > 0 else 0
    srt = np.sort(sums)[::-1]
    phrase_conf = float(srt[0] / total) if total > 0 else 0.0
    if total > 0:
        # blend share-of-novelty with margin over the runner-up
        phrase_conf = float(np.clip(0.6 * phrase_conf + 0.4 * (srt[0] - srt[1]) / (srt[0] + 1e-9), 0, 1))
'''

# onset density: three lines of the per-bar loop's neighbourhood, each checked on its own
LAB_ONSET_LINES = [
    '''    onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr2, hop_length=hop, units="time")
''',
    '''    on_counts = np.histogram(onsets, bins=bar_t)[0]
    onset_den = (on_counts / 4.0).tolist()  # onsets per beat
''',
]

LAB_PATTERN = '''    cells = fd + np.arange(n_bars * 8 + 1) * (P / 2)
    cf = np.clip(np.round(cells * fps).astype(int), 0, len(onset_env) - 1)
    cellv = np.array([onset_env[a:max(a + 1, b)].max() for a, b in zip(cf[:-1], cf[1:])])
    npairs = n_bars // 2
    pat_rows = cellv[:npairs * 16].reshape(npairs, 16)
    lufs_arr = np.array(lufs_st)
    body = np.median(lufs_arr)
    keep_pairs = [i for i in range(npairs) if min(lufs_arr[2 * i], lufs_arr[2 * i + 1]) > body - 10]
    pat = pat_rows[keep_pairs].mean(axis=0) if keep_pairs else pat_rows.mean(axis=0)
    pat = pat / (pat.max() + 1e-9)
'''


def check_copies():
    """Every copied block must appear in mixer/analyze.py exactly as written here."""
    with open(ANALYZE) as f:
        text = f.read()
    blocks = [LAB_FOOTE, LAB_GRID, LAB_BARS, LAB_SPECTRAL, LAB_STRUCTURE, LAB_PATTERN] + LAB_ONSET_LINES
    for b in blocks:
        if b not in text:
            first = b.strip().splitlines()[0]
            sys.exit(f"the copy starting {first!r} no longer matches mixer/analyze.py; update it from there")
    print(f"lab code: {len(blocks)} blocks checked against {os.path.relpath(ANALYZE, ROOT)}", file=sys.stderr)


def run(block, ns):
    exec(textwrap.dedent(block), ns)


lab_ns = {"np": np}
exec(LAB_FOOTE, lab_ns)
foote_novelty = lab_ns["foote_novelty"]


def librosa_float64():
    """librosa as the float64 path calls it: everything as the lab calls it, but rms in float64."""
    feature = types.SimpleNamespace(
        melspectrogram=librosa.feature.melspectrogram, mfcc=librosa.feature.mfcc,
        rms=lambda **kw: librosa.feature.rms(dtype=np.float64, **kw))
    return types.SimpleNamespace(feature=feature, power_to_db=librosa.power_to_db, onset=librosa.onset)


# ----------------------------------------------------------------------------- synthesis
def splitmix(seed, n):
    """The first n outputs of SplitMix64 started at state `seed`, as uniform values in [0, 1)."""
    with np.errstate(over="ignore"):
        z = np.uint64(seed) + (np.arange(1, n + 1, dtype=np.uint64) * np.uint64(GOLDEN))
        z = (z ^ (z >> np.uint64(30))) * np.uint64(M1)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(M2)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) * 2.0 ** -53


def render(n, events, floor, seed):
    """Events added in order into n samples of float64, then the noise floor. With j = 0 ..< L the sample within the
    event, e = 1 - j / L, i the absolute sample index and w(f) = 2 pi f / sr:
      ["kick", a, L, f0, f1, amp]     amp e^2 sin(w(f1) j + (w(f0) - w(f1)) (L / 3) (1 - e^3)): a sine gliding from f0
                                      to f1 (the phase is the integral of w(f1) + (w(f0) - w(f1)) e^2)
      ["noise", a, L, amp, p, seed]   amp env (2 u - 1), u from SplitMix64(seed), env = e^2 for p = 2, (e^2)^2 for
                                      p = 4, 1 for p = 0
      ["tone", a, L, midi, amp, h]    for harmonics k = 1 ... h below sr / 2: (amp / k) env sin(w(f) k i), with
                                      f = 440 * 2^((midi - 69) / 12) and env a 10 ms linear ramp in and out
    then floor (2 u - 1), u from SplitMix64(seed)."""
    y = np.zeros(n)
    iabs = np.arange(n, dtype=np.float64)
    for ev in events:
        kind, a, L = ev[0], ev[1], ev[2]
        assert 0 <= a and a + L <= n, ev
        j = np.arange(L, dtype=np.float64)
        if kind == "kick":
            f0, f1, amp = ev[3], ev[4], ev[5]
            w0 = 2.0 * math.pi * f0 / SR
            w1 = 2.0 * math.pi * f1 / SR
            e = 1.0 - j / L
            env = e * e
            phase = w1 * j + (w0 - w1) * (L / 3.0) * (1.0 - e * e * e)
            y[a:a + L] += amp * env * np.sin(phase)
        elif kind == "noise":
            amp, p, s = ev[3], ev[4], ev[5]
            e = 1.0 - j / L
            env = e * e if p == 2 else (e * e) * (e * e) if p == 4 else np.ones(L)
            y[a:a + L] += amp * env * (2.0 * splitmix(s, L) - 1.0)
        elif kind == "tone":
            midi, amp, h = ev[3], ev[4], ev[5]
            f = 440.0 * 2.0 ** ((midi - 69) / 12.0)
            env = np.minimum(1.0, np.minimum((j + 1) / RAMP, (L - j) / RAMP))
            for k in range(1, h + 1):
                if f * k >= SR / 2:
                    break
                w = 2.0 * math.pi * f * k / SR
                y[a:a + L] += (amp / k) * env * np.sin(w * iabs[a:a + L])
        else:
            raise ValueError(kind)
    if floor:
        y += floor * (2.0 * splitmix(seed, n) - 1.0)
    return y


def check_samples(y32):
    """A few samples (float32, exact) and two float64 sums (numpy's pairwise order) of the float32 signal."""
    n = len(y32)
    idx = sorted({0, 1, n // 7, n // 3, n // 2, (2 * n) // 3, n - 2, n - 1})
    y = y32.astype(np.float64)
    return {"index": idx, "values": [f32(y32[i]) for i in idx], "sum": float(np.sum(y)), "sum_sq": float(np.sum(y * y))}


def drum_loop():
    """12 s at 120 BPM: 12 beats of kick plus off-beat hat, then 12 of kick and snare in turn, 16th hats and a bass."""
    n, beat, ev, seed = 12 * SR, 11025, [], 1000
    for b in range(24):
        s = b * beat
        if b < 12:
            ev.append(["kick", s, 5512, 150.0, 50.0, 0.8])
            ev.append(["noise", s + 5512, 1102, 0.25, 4, seed]); seed += 1
        else:
            if b % 2 == 0:
                ev.append(["kick", s, 5512, 120.0, 45.0, 0.9])
            else:
                ev.append(["noise", s, 3307, 0.5, 2, seed]); seed += 1
            for q in range(4):
                ev.append(["noise", s + q * 2756, 551, 0.15, 4, seed]); seed += 1
    ev.append(["tone", 12 * beat, 12 * beat, 33, 0.3, 4])
    return n, ev, 0.001, 7


def tone_sequence():
    """10 s of notes, a new one every 0.25 s, three harmonics each."""
    melody = [60, 64, 67, 72, 71, 67, 64, 62, 57, 69, 65, 60, 55, 59, 62, 67, 74, 76, 79, 48]
    n, step = 10 * SR, 5512
    ev = [["tone", i * step, step, melody[i % len(melody)], 0.3, 3] for i in range(40)]
    return n, ev, 0.002, 8


def noise_with_gap():
    """8 s: white noise for 3 s, 2 s of digital silence, then noise 15.6 dB quieter."""
    n = 8 * SR
    return n, [["noise", 0, 3 * SR, 0.3, 0, 21], ["noise", 5 * SR, 3 * SR, 0.05, 0, 22]], 0.0, 0


# The structure track: 125 BPM (0.48 s a beat, 10,584 samples), bar 1 at 0.5 s, 48 bars, then a second of the floor.
TRACK_P, TRACK_FD, TRACK_BARS = 0.48, 0.5, 48
BEAT_N, FD_N = 10584, 11025
AM, F, C, G = [45, 57, 60, 64], [41, 57, 60, 65], [48, 55, 60, 64], [43, 55, 59, 62]


def track():
    """Sections (0-based bars): intro 0-4 (quiet hats and a pad), A 5-20 (kick on every beat, off-beat hats, a bass
    line), break 21-28 (pad chords only), B 29-44 (kick and snare, 16th hats, another bass line), outro 45-47 (pad and
    hats). The changes fall on bars 5, 21, 29 and 45, all at position 5 within 8 bars (lattice phase bar 6)."""
    bar_n = 4 * BEAT_N
    n = FD_N + TRACK_BARS * bar_n + SR
    ev, seed = [], 2000

    def hats(s, amp, per_beat, length):
        nonlocal seed
        for q in range(4):
            for r in range(per_beat):
                off = q * BEAT_N + (BEAT_N // 2 if per_beat == 1 else r * (BEAT_N // per_beat))
                ev.append(["noise", s + off, length, amp, 4, seed]); seed += 1

    for k in range(TRACK_BARS):
        s = FD_N + k * bar_n
        if k < 5:
            hats(s, 0.12, 1, 1058)
            ev.extend(["tone", s, bar_n, m, 0.03, 4] for m in AM)
        elif k < 21:
            for q in range(4):
                ev.append(["kick", s + q * BEAT_N, 5292, 150.0, 50.0, 0.8])
            hats(s, 0.25, 1, 1058)
            ev.append(["tone", s, bar_n, [33, 29, 36, 31][k % 4], 0.3, 4])
        elif k < 29:
            if (k - 21) % 2 == 0:
                ev.extend(["tone", s, 2 * bar_n, m, 0.12, 6] for m in [AM, F, C, G][(k - 21) // 2 % 4])
        elif k < 45:
            for q in range(4):
                if q % 2 == 0:
                    ev.append(["kick", s + q * BEAT_N, 5292, 120.0, 45.0, 0.9])
                else:
                    ev.append(["noise", s + q * BEAT_N, 3175, 0.5, 2, seed]); seed += 1
            hats(s, 0.15, 4, 529)
            ev.append(["tone", s, bar_n, [38, 34, 41, 36][k % 4], 0.35, 4])
        else:
            hats(s, 0.1, 1, 1058)
            ev.extend(["tone", s, bar_n, m, 0.05, 4] for m in AM)
    return n, ev, 0.001, 99


# ----------------------------------------------------------------------------- helpers
def f32(x):
    """Shortest text that reads back as the same float32."""
    return float(str(np.float32(x)))


def sig9(x):
    """Nine significant digits: for sums and curves checked to 1e-8 or looser."""
    return float(f"{x:.9g}")


def sample_frames(T):
    return sorted({0, 3, T // 4, T // 2 - 1, T // 2, (3 * T) // 4, T - 2, T - 1})


def spectral(y, path):
    """The lab's spectral block on y (float32 or float64)."""
    ns = {"np": np, "librosa": librosa if path == "float32" else librosa_float64(), "m22": y, "sr2": SR, "hop": HOP}
    run(LAB_SPECTRAL, ns)
    return ns


def spectral_record(ns, path):
    conv = f32 if path == "float32" else float
    mel, logmel, mfcc, rms, onset = ns["mel"], ns["logmel"], ns["mfcc"], ns["rms"], ns["onset_env"]
    assert mel.dtype == (np.float32 if path == "float32" else np.float64), (path, mel.dtype)
    T = mel.shape[1]
    pick = sample_frames(T)
    sums = lambda M, axis: [sig9(v) for v in M.astype(np.float64).sum(axis=axis)]
    return {
        "frames": int(T),
        "index": pick,
        "mel": [[conv(v) for v in mel[:, t]] for t in pick],
        "logmel": [[conv(v) for v in logmel[:, t]] for t in pick],
        "mfcc": [[conv(v) for v in mfcc[:, t]] for t in pick],
        "mel_frame_sums": sums(mel, 0), "mel_band_sums": sums(mel, 1),
        "logmel_frame_sums": sums(logmel, 0), "logmel_band_sums": sums(logmel, 1),
        "mfcc_frame_sums": sums(mfcc, 0), "mfcc_coef_sums": sums(mfcc, 1),
        "rms": [conv(v) for v in rms], "onset": [conv(v) for v in onset],
    }


def melbank_record():
    fb = librosa.filters.mel(sr=SR, n_fft=2048, n_mels=64)
    melf = librosa.mel_frequencies(66, fmin=0.0, fmax=SR / 2.0)
    bands = []
    for m in range(64):
        nz = np.nonzero(fb[m])[0]
        a, b = int(nz[0]), int(nz[-1]) + 1
        bands.append([a, [f32(v) for v in fb[m, a:b]]])
    return {"n_fft": 2048, "n_mels": 64, "mel_frequencies": [float(v) for v in melf], "bands": bands,
            "nonzero": int(np.count_nonzero(fb))}


# ----------------------------------------------------------------------------- find_peaks cases
def findpeaks_cases():
    cases = []
    # smooth random curves: a sum of SplitMix64 bumps, distinct heights
    for c in range(12):
        n = [50, 120, 200, 384, 500, 96, 33, 260, 384, 150, 700, 64][c]
        u = splitmix(500 + c, n)
        x = np.round(np.convolve(u, np.ones(5) / 5, mode="same"), 6)
        cases.append({"name": f"smooth_{c}", "x": [float(v) for v in x], "distance": 8})
    # quantised curves: many plateaus and peaks of equal height
    for c in range(10):
        n = [40, 80, 120, 200, 64, 300, 100, 31, 256, 150][c]
        x = np.floor(splitmix(600 + c, n) * [3, 5, 8, 4, 10, 6, 3, 4, 7, 5][c])
        distance = [8, 8, 8, 3, 8, 12, 1, 2, 8, 5][c]
        cases.append({"name": f"levels_{c}", "x": [float(v) for v in x], "distance": distance})
    hand = {
        "empty": [], "one": [1.0], "two": [0.0, 1.0], "three": [0.0, 1.0, 0.0], "flat": [2.0] * 20,
        "rising": [float(i) for i in range(20)], "falling": [float(20 - i) for i in range(20)],
        "plateau_start": [3.0, 3.0, 3.0, 1.0, 0.0, 2.0, 0.0], "plateau_end": [0.0, 1.0, 0.0, 2.0, 2.0, 2.0],
        "plateau_mid_even": [0.0, 1.0, 5.0, 5.0, 5.0, 5.0, 1.0, 0.0], "plateau_mid_odd": [0.0, 5.0, 5.0, 5.0, 0.0],
        "plateau_then_rise": [0.0, 2.0, 2.0, 3.0, 0.0],
        "spaced_7": [0.0 if i % 7 else 1.0 + i / 100 for i in range(1, 60)],
        "spaced_8": [0.0 if i % 8 else 1.0 + i / 100 for i in range(1, 60)],
        "spaced_9": [0.0 if i % 9 else 2.0 - i / 100 for i in range(1, 60)],
        "neighbours_win": [0, 5, 0, 4, 0, 6, 0, 3, 0, 7, 0, 2, 0, 1, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0],
        "chain": [0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8, 0, 9, 0, 10, 0, 11, 0],
        "negative": [-5.0, -3.0, -4.0, -1.0, -2.0, -0.5, -6.0],
        "fractional_distance": [0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 3, 0],
    }
    for name, x in hand.items():
        distance = 4.5 if name == "fractional_distance" else 8
        cases.append({"name": name, "x": [float(v) for v in x], "distance": distance})
    for c in cases:
        x = np.asarray(c["x"], dtype=np.float64)
        pk, _ = find_peaks(x, distance=c["distance"]) if len(x) else (np.array([], int), None)
        c["peaks"] = [int(p) for p in pk]
        raw, _ = find_peaks(x) if len(x) else (np.array([], int), None)
        c["maxima"] = [int(p) for p in raw]
        # exact ties among the maxima: numpy's argsort (not stable) decides which of two equal peaks survives
        hs = x[raw]
        c["tied_heights"] = bool(len(hs) != len(set(hs.tolist())))
    return cases


# ----------------------------------------------------------------------------- foote_novelty on made-up matrices
def foote_cases():
    out = []
    for c, n in enumerate([100, 20, 1, 64, 150]):
        u = splitmix(700 + c, n * n).reshape(n, n)
        S = (u + u.T) / 2.0  # symmetric, as both similarity matrices are
        nov = foote_novelty(S)
        out.append({"n": n, "seed": 700 + c, "novelty": [float(v) for v in nov]})
    K = 64
    h = K // 2
    g = np.exp(-0.5 * ((np.arange(-h, h) + 0.5) / (h / 2.0)) ** 2)
    return {"matrices": out, "gaussian": [float(v) for v in g]}


# ----------------------------------------------------------------------------- the structure track
def track_record(y32):
    n = len(y32)
    fd, P, n_bars = TRACK_FD, TRACK_P, TRACK_BARS
    ns_grid = {"np": np, "P": P, "fd": fd, "n_bars": n_bars}
    run(LAB_GRID, ns_grid)
    run(LAB_BARS, ns_grid)
    bar_t = ns_grid["bar_t"]
    # per-bar loudness, an input of the onset pattern: here the plain mean square over each bar (the lab K-weights a
    # 44.1 kHz stereo signal; any per-bar loudness serves for the parity of the pattern code)
    bi = np.round(bar_t * SR).astype(int)
    yd = y32.astype(np.float64)
    lufs_st = [-0.691 + 10 * math.log10(max(float(np.mean(yd[a:b] ** 2)), 1e-30)) for a, b in zip(bi[:-1], bi[1:])]
    lufs_st = [round(v, 6) for v in lufs_st]
    rec = {"samples": n, "first_downbeat_s": fd, "beat_s": P, "n_bars": n_bars, "bar_loudness": lufs_st, "paths": {}}
    for path, y in (("float32", y32), ("float64", y32.astype(np.float64))):
        ns = spectral(y, path)
        ns.update({"fd": fd, "P": P, "n_bars": n_bars, "bar_t": bar_t, "find_peaks": find_peaks,
                   "foote_novelty": foote_novelty, "lufs_st": lufs_st})
        run(LAB_STRUCTURE, ns)
        for line in LAB_ONSET_LINES:
            run(line, ns)
        run(LAB_PATTERN, ns)
        conv = f32 if path == "float32" else float
        conv9 = sig9 if path == "float32" else float
        nov_m, nov_r = foote_novelty(ns["S_mfcc"]), foote_novelty(ns["S_rms"])
        rec["paths"][path] = {
            "frames": int(ns["mel"].shape[1]),
            "frame_edges": [int(v) for v in ns["hb_fr"]],
            "novelty_mfcc": [conv9(v) for v in nov_m], "novelty_rms": [conv9(v) for v in nov_r],
            "novelty": [float(v) for v in ns["nov"]],
            "peak_frames": [int(p) for p in ns["pk_idx"]],
            "peaks": [[b + 1, v] for b, v in ns["peaks"]],
            "phase_novelty": [float(v) for v in ns["sums"]], "lattice_phase_bar": ns["phase"] + 1,
            "confidence": ns["phrase_conf"],
            "onset_frames": [int(round(t * SR / HOP)) for t in ns["onsets"]],
            "onset_density": [float(v) for v in ns["onset_den"]],
            "cells": [conv(v) for v in ns["cellv"]], "keep_pairs": [int(i) for i in ns["keep_pairs"]],
            "pattern": [float(v) for v in ns["pat"]],
        }
        print(f"track {path}: {len(ns['peaks'])} peaks at bars {sorted(b + 1 for b, _ in ns['peaks'])}, lattice phase "
              f"bar {ns['phase'] + 1}, confidence {ns['phrase_conf']:.3f}, {len(ns['onsets'])} onsets, "
              f"{len(ns['keep_pairs'])} of {ns['npairs']} bar pairs kept", file=sys.stderr)
    return rec


def main():
    check_copies()
    doc = {"versions": {"numpy": np.__version__, "scipy": scipy.__version__, "librosa": librosa.__version__},
           "melbank": melbank_record(), "signals": [], "findpeaks": findpeaks_cases(), "foote": foote_cases()}
    for name, make in (("drum_loop_section_change", drum_loop), ("tone_sequence", tone_sequence),
                       ("noise_with_gap", noise_with_gap)):
        n, events, floor, seed = make()
        y32 = render(n, events, floor, seed).astype(np.float32)
        entry = {"name": name, "samples": n, "events": events, "floor": floor, "seed": seed,
                 "check": check_samples(y32), "paths": {}}
        for path, y in (("float32", y32), ("float64", y32.astype(np.float64))):
            entry["paths"][path] = spectral_record(spectral(y, path), path)
        doc["signals"].append(entry)
        print(f"{name}: {n} samples, {entry['paths']['float32']['frames']} frames", file=sys.stderr)
    n, events, floor, seed = track()
    y32 = render(n, events, floor, seed).astype(np.float32)
    doc["track"] = {"events": events, "floor": floor, "seed": seed, "check": check_samples(y32),
                    **track_record(y32)}
    with open(OUT, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB)")


if __name__ == "__main__":
    main()
