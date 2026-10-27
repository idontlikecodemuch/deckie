#!/usr/bin/env python3
"""Per-track analysis for the auto-DJ toolkit -> features/<id>.json (resumable).

Run with the project venv, by absolute path, e.g.
  ".venv/bin/python" analyze.py --ids c546b63944,50b4b2b2aa
  nohup .venv/bin/python analyze.py > analyze_full.log 2>&1 &

See README.md for the schema and the algorithm notes. Source MP3s are only read.
"""
import argparse
import local_tempo
import json
import math
import os
import sys
import time
import traceback
import warnings

import numpy as np

warnings.filterwarnings("ignore")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

HERE = os.path.dirname(os.path.abspath(__file__))
FEAT_DIR = os.path.join(HERE, "features")
CANDIDATES = os.path.join(HERE, "candidates.json")
MODELS = os.path.join(HERE, "models")
ERR_LOG = os.path.join(HERE, "analyze_errors.log")
SR = 44100
SCHEMA_VERSION = 1

MULTIPLIERS = [0.5, 2 / 3, 0.75, 1.0, 4 / 3, 1.5, 2.0]
OCTAVE_MULTS = [0.5, 1.0, 2.0]

# ----------------------------------------------------------------------------- keys
PC = {"C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4,
      "F": 5, "E#": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10,
      "Bb": 10, "B": 11, "Cb": 11}


def camelot(key, scale):
    """Camelot code from a key name and 'major'/'minor' (research.md A.2)."""
    pc = PC[key]
    if scale.lower().startswith("maj"):
        n = (pc * 7 + 8) % 12
        return f"{12 if n == 0 else n}B"
    n = (pc * 7 + 5) % 12
    return f"{12 if n == 0 else n}A"


def camelot_parse(c):
    return int(c[:-1]), c[-1]


def camelot_neighbour(a, b):
    """True if b is same, +/-1 same letter, or relative of a."""
    na, la = camelot_parse(a)
    nb, lb = camelot_parse(b)
    if la == lb:
        d = (nb - na) % 12
        return d in (0, 1, 11)
    return na == nb


# ----------------------------------------------------------------------------- helpers
def r3(x):
    return None if x is None else round(float(x), 3)


def rlist(a, nd=3):
    return [round(float(v), nd) for v in a]


def db(x, floor=-120.0):
    return float(max(floor, 10 * math.log10(max(float(x), 1e-30))))


def mult_dev(bpm, ref, mults):
    """Return (mult, dev_pct) with bpm ~= ref * mult, minimising |log|."""
    best = None
    for m in mults:
        d = abs(math.log(bpm / (ref * m)))
        if best is None or d < best[1]:
            best = (m, d)
    m, d = best
    return m, (math.exp(d) - 1) * 100


def mult_label(m):
    for v, s in [(0.5, "1/2"), (2 / 3, "2/3"), (0.75, "3/4"), (1.0, "1"),
                 (4 / 3, "4/3"), (1.5, "3/2"), (2.0, "2")]:
        if abs(m - v) < 1e-6:
            return s
    return f"{m:.3f}"


# ----------------------------------------------------------------------------- grid fit
def _win_fit(b):
    """Period of one window of beats: cumulative integer indexing (robust to the 20 ms frame
    quantisation of the median interval) + least squares with residual rejection."""
    b = np.sort(b)
    if len(b) < 8:
        return None
    g = np.diff(b)
    med = float(np.median(g))
    if med <= 0:
        return None
    idx = np.concatenate([[0.0], np.cumsum(np.round(g / med))])
    keep = np.ones(len(b), bool)
    P, off = med, b[0]
    for _ in range(3):
        if keep.sum() < 8:
            return None
        A = np.vstack([idx[keep], np.ones(keep.sum())]).T
        P, off = np.linalg.lstsq(A, b[keep], rcond=None)[0]
        res = b - (off + P * idx)
        idx = idx + np.round(res / P)
        res = b - (off + P * idx)
        keep = np.abs(res) < 0.25 * P
    return float(P), float(np.median(np.abs(res[keep])) * 1000), int(keep.sum())


def _period_phase_windows(b, win=20.0):
    """Period = median of the periods of trusted 20 s windows; phase = circular mean of beat phases."""
    per = []
    t, t_end = b[0], b[-1]
    while t < t_end - win * 0.6:
        r = _win_fit(b[(b >= t) & (b < t + win)])
        if r and r[1] <= 15 and r[2] >= 16:
            per.append(r[0])
        t += win
    if len(per) < 3:
        return None
    P = float(np.median(per))
    ph = float(np.angle(np.mean(np.exp(2j * np.pi * ((b % P) / P)))) / (2 * np.pi) * P)
    spread = (max(per) - min(per)) / P * 100
    return P, ph, {"method": "windows", "trusted_windows": len(per), "period_spread_pct": round(spread, 2)}


def _period_phase_irls(b):
    """Original whole-track L1 fit with incremental integer indexing."""
    ibi = np.diff(b)
    P = float(np.median(ibi))
    k = [0]
    keep = [0]
    for i in range(1, len(b)):
        step = int(round((b[i] - b[keep[-1]]) / P))
        if step <= 0:
            continue
        k.append(k[-1] + step)
        keep.append(i)
    bb = b[keep]
    kk = np.asarray(k, float)
    t0 = bb[0]
    for it in range(12):
        A = np.vstack([np.ones_like(kk), kk]).T
        res = bb - (t0 + kk * P)
        w = 1.0 / np.maximum(np.abs(res), 1e-3)
        w = np.minimum(w, 1e3)
        Wa = A * w[:, None]
        sol = np.linalg.lstsq(Wa.T @ A, Wa.T @ bb, rcond=None)[0]
        t0, P = float(sol[0]), float(sol[1])
        if it in (3, 7):
            kk = np.round((bb - t0) / P)
    return P, t0, {"method": "irls"}


def _grid_eval(b, downbeats, P, t0):
    res = b - (t0 + np.round((b - t0) / P) * P)
    absr = np.abs(res)
    mad_ms = float(np.median(absr) * 1000)
    inlier = float(np.mean(absr < 0.07))
    d = np.asarray(downbeats, float) if downbeats is not None else np.array([], float)
    if len(d) >= 2:
        idx = np.round((d - t0) / P).astype(int)
        near = np.abs(d - (t0 + idx * P)) < 0.25 * P
        counts = [int(np.sum(near & (np.mod(idx, 4) == j))) for j in range(4)]
        j = int(np.argmax(counts))
        db_agree = counts[j] / max(1, len(d))
    else:
        j, db_agree = 0, 0.0
    first_db = t0 + j * P
    conf = inlier * (0.5 + 0.5 * db_agree) * max(0.0, 1 - max(0.0, mad_ms - 5) / 50)
    return {"bpm": 60.0 / P, "period": P, "t0": t0, "first_downbeat": first_db,
            "fit_mad_ms": mad_ms, "inlier_frac": inlier, "downbeat_agree": db_agree,
            "confidence": float(np.clip(conf, 0, 1))}


def fit_grid(beats, downbeats, duration):
    """Constant 4/4 grid. Two period/phase estimators are tried (whole-track L1 fit, and the
    median of trusted 20 s window periods, which survives doubled beats and coarse medians);
    the one that puts more detected beats within 70 ms of the grid wins."""
    b = np.sort(np.asarray(beats, float))
    if len(b) < 16:
        return None
    cands = []
    P, t0, info = _period_phase_irls(b)
    cands.append((_grid_eval(b, downbeats, P, t0), info))
    w = _period_phase_windows(b)
    if w:
        P2, t02, info2 = w
        cands.append((_grid_eval(b, downbeats, P2, t02), info2))
    cands.sort(key=lambda c: (-round(c[0]["inlier_frac"], 3), c[0]["fit_mad_ms"]))
    g, info = cands[0]
    g.update(info)
    if w:
        g["period_spread_pct"] = w[2]["period_spread_pct"]
        g["trusted_windows"] = w[2]["trusted_windows"]
    return g


# ----------------------------------------------------------------------------- models
def _rms_at(mono, times, win=0.05):
    vals = []
    for t in times:
        i = int(t * SR)
        seg = mono[max(0, i): i + int(win * SR)]
        if len(seg):
            vals.append(float(np.sqrt(np.mean(seg ** 2))))
    return float(np.median(vals)) if vals else 0.0


def octave_align(beats, downs, grid, bpm_tag, mono, duration):
    """Bring the detected pulse to the tag's octave (the discs' folder convention) when the
    tracker sits at exactly double or half the tag. Returns (beats, downs, grid, info_or_None)."""
    if not grid or not bpm_tag:
        return beats, downs, grid, None
    r = grid["bpm"] / bpm_tag
    b = np.asarray(beats, float)
    d = np.asarray(downs, float) if downs is not None else np.array([], float)
    P = 60.0 / grid["bpm"]
    if abs(r - 2.0) < 0.08 and len(b) >= 8:
        k = np.round((b - b[0]) / P).astype(int)
        kd = np.round((d - b[0]) / P).astype(int) if len(d) else np.array([], int)
        par = int(np.bincount(kd % 2).argmax()) if len(kd) else 0
        nb = b[k % 2 == par]
        nd = d
        if len(d) >= 2 and np.median(np.diff(d)) / (2 * P) < 3:
            # downbeats were half-bars: keep the alternate set with the stronger low-end hit
            c0, c1 = d[0::2], d[1::2]
            nd = c0 if _rms_at(mono, c0) >= _rms_at(mono, c1) else c1
        g = fit_grid(nb, nd, duration)
        if g:
            return nb, nd, g, {"mode": "halved", "from_bpm": round(grid["bpm"], 3), "parity": par}
    elif abs(r - 0.5) < 0.04 and len(b) >= 8:
        nb = np.sort(np.concatenate([b, (b[:-1] + b[1:]) / 2]))
        nd = np.sort(np.concatenate([d, (d[:-1] + d[1:]) / 2])) if len(d) >= 2 else d
        g = fit_grid(nb, nd, duration)
        if g:
            return nb, nd, g, {"mode": "doubled", "from_bpm": round(grid["bpm"], 3)}
    return beats, downs, grid, None


class Models:
    def __init__(self, want_madmom_downbeats=True):
        import essentia
        essentia.log.infoActive = False
        essentia.log.warningActive = False
        import essentia.standard as es
        self.es = es
        self.key_edma = es.KeyExtractor(profileType="edma", sampleRate=SR)
        self.key_bgate = es.KeyExtractor(profileType="bgate", sampleRate=SR)
        self.rhythm = es.RhythmExtractor2013(method="multifeature")
        self.effnet = es.TensorflowPredictEffnetDiscogs(
            graphFilename=os.path.join(MODELS, "discogs-effnet-bs64-1.pb"),
            output="PartitionedCall:1")
        self.voice = es.TensorflowPredict2D(
            graphFilename=os.path.join(MODELS, "voice_instrumental-discogs-effnet-1.pb"),
            output="model/Softmax")
        self._bt = None
        self.bt_device = None
        self._load_beatthis("mps")
        try:
            from madmom.features.key import CNNKeyRecognitionProcessor
            self.mm_key = CNNKeyRecognitionProcessor()
            self.mm_key_err = None
        except Exception as e:  # pragma: no cover
            self.mm_key = None
            self.mm_key_err = f"{type(e).__name__}: {e}"
        self._mm_db = None

    def _load_beatthis(self, device):
        from beat_this.inference import Audio2Beats
        try:
            self._bt = Audio2Beats(checkpoint_path="final0", device=device, dbn=False)
            self.bt_device = device
        except Exception:
            self._bt = Audio2Beats(checkpoint_path="final0", device="cpu", dbn=False)
            self.bt_device = "cpu"

    def beats(self, mono):
        try:
            b, d = self._bt(mono, SR)
        except Exception:
            if self.bt_device != "cpu":
                self._load_beatthis("cpu")
                b, d = self._bt(mono, SR)
            else:
                raise
        return np.asarray(b, float), np.asarray(d, float)

    def madmom_downbeats(self, mono):
        from madmom.audio.signal import Signal
        from madmom.features.downbeats import RNNDownBeatProcessor, DBNDownBeatTrackingProcessor
        if self._mm_db is None:
            self._mm_db = (RNNDownBeatProcessor(),
                           DBNDownBeatTrackingProcessor(beats_per_bar=[4], fps=100))
        rnn, dbn = self._mm_db
        act = rnn(Signal(mono, sample_rate=SR, num_channels=1))
        out = dbn(act)
        beats = out[:, 0]
        downs = out[out[:, 1] == 1, 0]
        return beats, downs


# ----------------------------------------------------------------------------- analysis
def lr4(x, fc, btype):
    from scipy.signal import butter, sosfilt
    sos = butter(2, fc, btype=btype, fs=SR, output="sos")
    return sosfilt(sos, sosfilt(sos, x))


def k_weight(y):
    """K-weight each channel with pyloudnorm's BS.1770 filters."""
    import pyloudnorm as pyln
    m = pyln.Meter(SR)
    z = y.astype(np.float64)
    for f in m._filters.values():
        from scipy.signal import lfilter
        z = f.passband_gain * lfilter(f.b, f.a, z, axis=0)
    return z


def true_peak_db(y):
    from scipy.signal import resample_poly
    peak = 0.0
    hop = SR * 10
    pad = 64
    for s in range(0, len(y), hop):
        a = max(0, s - pad)
        seg = y[a:s + hop + pad].astype(np.float64)
        up = resample_poly(seg, 4, 1, axis=0)
        peak = max(peak, float(np.max(np.abs(up))))
    return 20 * math.log10(max(peak, 1e-9))


def foote_novelty(S, K=64):
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


def analyse(track, M, madmom_mode="auto"):
    import soundfile as sf
    import soxr
    import librosa
    import pyloudnorm as pyln
    from scipy.signal import find_peaks

    timings = {}
    t = time.time()
    y, sr = sf.read(track["path"], dtype="float32", always_2d=True)
    if sr != SR:
        y = soxr.resample(y, sr, SR).astype(np.float32)
    if y.shape[1] > 2:
        y = y[:, :2]
    mono = np.ascontiguousarray(y.mean(axis=1), dtype=np.float32)
    n = len(mono)
    duration = n / SR
    timings["decode"] = time.time() - t

    # ---------------------------------------------------------- first / last sound (-60 dBFS)
    thr = 10 ** (-60 / 20)
    fr = 441  # 10 ms
    nf = n // fr
    pk = np.abs(y[:nf * fr]).max(axis=1).reshape(nf, fr).max(axis=1)
    loud = np.nonzero(pk > thr)[0]
    first_sound = float(loud[0] * fr / SR) if len(loud) else 0.0
    last_sound = float((loud[-1] + 1) * fr / SR) if len(loud) else duration

    # ---------------------------------------------------------- beats (Beat This)
    t = time.time()
    bt_beats, bt_downs = M.beats(mono)
    timings["beatthis"] = time.time() - t
    grid_bt = fit_grid(bt_beats, bt_downs, duration)
    octave_fix = None
    _tag = float(track.get("bpm_tag") or 0) or None
    if _tag and grid_bt:
        bt_beats, bt_downs, grid_bt, octave_fix = octave_align(bt_beats, bt_downs, grid_bt, _tag, mono, duration)

    # ---------------------------------------------------------- Essentia tempo + key
    t = time.time()
    try:
        bpm_ess, _, ess_conf, _, _ = M.rhythm(mono)
        bpm_ess = float(bpm_ess)
    except Exception:
        bpm_ess, ess_conf = None, None
    timings["essentia_rhythm"] = time.time() - t
    t = time.time()
    k1 = M.key_edma(mono)
    k2 = M.key_bgate(mono)
    mm_key = None
    mm_key_err = M.mm_key_err
    if M.mm_key is not None:
        try:
            from madmom.audio.signal import Signal
            from madmom.features.key import key_prediction_to_label
            pr = M.mm_key(Signal(mono, sample_rate=SR, num_channels=1))
            lab = key_prediction_to_label(pr)
            kname, kscale = lab.split()
            mm_key = [kname, kscale, float(np.max(pr))]
        except Exception as e:
            mm_key_err = f"{type(e).__name__}: {str(e)[:200]}"
    timings["key"] = time.time() - t

    bpm_tag = float(track.get("bpm_tag") or 0) or None

    # ---------------------------------------------------------- grid choice (+ optional madmom)
    def tag_dev(g):
        if g is None or not bpm_tag:
            return 999.0
        return mult_dev(g["bpm"], bpm_tag, OCTAVE_MULTS)[1]

    grids = {"beatthis": grid_bt}
    madmom_reason = None
    run_mm = False
    if madmom_mode == "always":
        run_mm, madmom_reason = True, "always"
    elif madmom_mode == "auto":
        if grid_bt is None or grid_bt["confidence"] < 0.5:
            run_mm, madmom_reason = True, "poor grid fit"
        elif tag_dev(grid_bt) > 2.0:
            run_mm, madmom_reason = True, "Beat This vs tag > 2%"
    mm_beats = mm_downs = None
    if run_mm:
        t = time.time()
        try:
            mm_beats, mm_downs = M.madmom_downbeats(mono)
            grids["madmom"] = fit_grid(mm_beats, mm_downs, duration)
            if bpm_tag and grids["madmom"]:
                mm_beats, mm_downs, grids["madmom"], _ = octave_align(mm_beats, mm_downs, grids["madmom"], bpm_tag, mono, duration)
        except Exception as e:
            grids["madmom"] = None
            madmom_reason = f"{madmom_reason}; madmom failed: {type(e).__name__}: {str(e)[:120]}"
        timings["madmom"] = time.time() - t
    cands = [(k, g) for k, g in grids.items() if g is not None]
    if not cands:
        raise RuntimeError("no beat grid could be fitted (too few beats)")
    cands.sort(key=lambda kg: (tag_dev(kg[1]) > 2.0, kg[1]["fit_mad_ms"]))
    grid_src, G = cands[0]

    P = G["period"]
    bar_s = 4 * P
    bpm = 60.0 / P
    # first downbeat: earliest grid downbeat at/after first sound (minus a quarter beat)
    fd = G["first_downbeat"]
    lo = max(0.0, first_sound - 0.25 * P)
    fd = fd - math.floor((fd - lo) / bar_s) * bar_s
    if fd < lo - 1e-9:
        fd += bar_s
    n_bars = int(math.floor((duration - fd) / bar_s))
    if n_bars < 8:
        raise RuntimeError(f"only {n_bars} bars on grid")
    bar_t = fd + np.arange(n_bars + 1) * bar_s  # bar k (0-based) spans bar_t[k]..bar_t[k+1]
    grid_beats = fd + np.arange(n_bars * 4 + 1) * P
    pre = np.arange(fd - P, -1e-9, -P)[::-1]
    grid_beats_all = np.concatenate([pre, grid_beats])

    mult_tag, dev_tag = mult_dev(bpm, bpm_tag, MULTIPLIERS) if bpm_tag else (1.0, 0.0)
    oct_mult, oct_dev = mult_dev(bpm, bpm_tag, OCTAVE_MULTS) if bpm_tag else (1.0, 0.0)
    bpm_agree = bool(bpm_tag and oct_dev < 1.0)
    ess_mult, ess_dev = mult_dev(bpm_ess, bpm, OCTAVE_MULTS) if bpm_ess else (None, None)

    # ---------------------------------------------------------- spectral features (22.05k)
    t = time.time()
    sr2 = 22050
    hop = 512
    m22 = soxr.resample(mono, SR, sr2).astype(np.float32)
    mel = librosa.feature.melspectrogram(y=m22, sr=sr2, n_fft=2048, hop_length=hop, n_mels=64)
    logmel = librosa.power_to_db(mel)
    mfcc = librosa.feature.mfcc(S=logmel, n_mfcc=13)
    rms = librosa.feature.rms(y=m22, frame_length=2048, hop_length=hop)[0]
    onset_env = librosa.onset.onset_strength(S=logmel, sr=sr2, hop_length=hop)
    fps = sr2 / hop
    timings["spectral"] = time.time() - t

    # ---------------------------------------------------------- structure (Foote novelty)
    t = time.time()
    hb = fd + np.arange(n_bars * 8 + 1) * (P / 2)  # half-beat frame edges, 8 per bar
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
    lattice = [b for b in range(phase, n_bars + 1, 8)]
    bset = sorted({b for b, v in peaks if b % 8 == phase})
    boundaries0 = sorted(set([0] + bset + [n_bars]))
    nov_at = {b: v for b, v in peaks}
    timings["structure"] = time.time() - t

    # ---------------------------------------------------------- per-bar loudness / bands / onsets
    t = time.time()
    kw = k_weight(y)
    bi = np.round(bar_t * SR).astype(int)
    lufs_st, low_db, high_db, onset_den = [], [], [], []
    low = lr4(mono.astype(np.float64), 150, "low")
    high = lr4(mono.astype(np.float64), 4000, "high")
    onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr2, hop_length=hop, units="time")
    for a, b2 in zip(bi[:-1], bi[1:]):
        ms = float(np.sum(np.mean(kw[a:b2] ** 2, axis=0)))
        lufs_st.append(-0.691 + db(ms, -120))
        low_db.append(db(np.mean(low[a:b2] ** 2)))
        high_db.append(db(np.mean(high[a:b2] ** 2)))
    on_counts = np.histogram(onsets, bins=bar_t)[0]
    onset_den = (on_counts / 4.0).tolist()  # onsets per beat
    del kw, low, high

    meter = pyln.Meter(SR)
    integ = float(meter.integrated_loudness(y.astype(np.float64)))
    try:
        lra = float(meter.loudness_range(y.astype(np.float64)))
    except Exception:
        lra = None
    tp = true_peak_db(y)
    timings["loudness"] = time.time() - t

    # onset pattern: 2 bars x 8 sub-beats (eighth notes), averaged over sounding bar pairs
    cells = fd + np.arange(n_bars * 8 + 1) * (P / 2)
    cf = np.clip(np.round(cells * fps).astype(int), 0, len(onset_env) - 1)
    cellv = np.array([onset_env[a:max(a + 1, b)].max() for a, b in zip(cf[:-1], cf[1:])])
    npairs = n_bars // 2
    pat_rows = cellv[:npairs * 16].reshape(npairs, 16)
    lufs_arr = np.array(lufs_st)
    body = np.median(lufs_arr)
    keep_pairs = [i for i in range(npairs) if min(lufs_arr[2 * i], lufs_arr[2 * i + 1]) > body - 10]
    pat = pat_rows[keep_pairs].mean(axis=0) if keep_pairs else pat_rows.mean(axis=0)
    pat = pat / (pat.max() + 1e-9)

    # ---------------------------------------------------------- vocal probability + embedding
    t = time.time()
    m16 = soxr.resample(mono, SR, 16000).astype(np.float32)
    emb = M.effnet(m16)
    pred = M.voice(emb)
    voice = np.asarray(pred)[:, 1]
    hop_s = 62 * 256 / 16000.0
    centers = np.arange(len(voice)) * hop_s + 64 * 256 / 16000.0
    vocal_bar = []
    for a, b2 in zip(bar_t[:-1], bar_t[1:]):
        sel = (centers >= a) & (centers < b2)
        if sel.any():
            vocal_bar.append(float(voice[sel].mean()))
        else:
            vocal_bar.append(float(np.interp((a + b2) / 2, centers, voice)))
    vocal_bar = np.array(vocal_bar)
    emb_mean = np.asarray(emb).mean(axis=0)
    timings["effnet"] = time.time() - t
    vmask = (bar_t[:-1] >= first_sound - bar_s) & (bar_t[1:] <= last_sound + bar_s)
    mean_vocal = float(voice.mean())

    # ---------------------------------------------------------- sections
    sections = []
    for i, (a, b2) in enumerate(zip(boundaries0[:-1], boundaries0[1:])):
        if b2 <= a:
            continue
        e = float(np.mean(lufs_arr[a:b2]))
        energy = "high" if e >= body - 1.5 else "low"
        if i == 0:
            label = "intro"
        elif b2 == n_bars:
            label = "outro"
        else:
            label = "main" if energy == "high" else "break"
        sections.append({"start_bar": a + 1, "end_bar": b2 + 1, "label": label, "energy": energy,
                         "lufs": round(e, 2), "vocal": round(float(vocal_bar[a:b2].mean()), 3)})

    # ---------------------------------------------------------- fade-out detection
    def st_lufs(t_end, win=3.0):
        a = int(max(0, (t_end - win)) * SR)
        b2 = int(max(t_end, 0.1) * SR)
        seg = y[a:b2].astype(np.float64)
        if len(seg) < SR // 4:
            return -120.0
        z = k_weight(seg)
        return -0.691 + db(np.sum(np.mean(z ** 2, axis=0)))

    # short-term (3 s) loudness at 20, 10 and 4 s before last sound
    l20, l10, l4 = st_lufs(last_sound - 17.0), st_lufs(last_sound - 7.0), st_lufs(last_sound - 1.0)
    fade_drop = l20 - l4
    # fade-out (or long decaying tail): > 6 dB decline over the last 20 s AND at least 3 bars
    # between the last body-level bar (>= median bar loudness - 2 LU) and the last sound,
    # so a hard stop followed by a short decay is not counted
    fade_drop = l20 - l4
    okb = np.nonzero(lufs_arr >= body - 2.0)[0]
    last_body_bar = int(okb[-1]) if len(okb) else n_bars - 1
    tail_bars = (last_sound - bar_t[last_body_bar + 1]) / bar_s if last_body_bar + 1 <= n_bars else 0.0
    fade_out = bool(fade_drop > 6.0 and tail_bars >= 3.0 and last_sound - first_sound > 60)
    fade_start_bar = last_body_bar + 1 if fade_out else None  # 0-based exclusive

    # ---------------------------------------------------------- mix windows
    VOC = 0.5
    # lattice used for snapping: the detected phase only when the phrase estimate is
    # trustworthy, otherwise phrases are assumed to start on bar 1.
    snap_phase = phase if phrase_conf >= 0.35 else 0
    snap_lat = list(range(snap_phase, n_bars + 1, 8))
    on_lat = lambda b: (b - snap_phase) % 8 == 0
    last_full = int(np.searchsorted(bar_t, last_sound, side="right") - 1)
    end_limit = max(8, min(n_bars, last_full))
    vocal_on = np.nonzero(vocal_bar >= VOC)[0]
    first_vocal = int(vocal_on[0]) if len(vocal_on) else n_bars
    last_vocal = int(vocal_on[-1]) if len(vocal_on) else -1
    half = max(8, n_bars // 2)

    def pick_len(avail, vocal_free_avail):
        """32 bars only if at least 16 of them are vocal-free; else 16 if it fits; else 8."""
        if avail >= 32 and vocal_free_avail >= 16:
            return 32
        return 16 if avail >= 16 else 8

    # mix-in: bar 1 (first downbeat at first sound) to the first vocal bar, extended to the
    # first boundary when the vocal-free intro is shorter than 8 bars
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
    mix_in = {"start_bar": start0 + 1, "end_bar": end_in + 1, "bars": end_in - start0,
              "start_s": r3(bar_t[start0]), "end_s": r3(bar_t[end_in]),
              "vocal_free_bars": int(np.sum(vocal_bar[start0:end_in] < VOC)),
              "first_vocal_bar": first_vocal + 1 if len(vocal_on) else None}

    # mix-out: ends at the last full bar (snapped down to the lattice if within 4 bars), or for
    # a fade-out at the last lattice boundary before the fade starts
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
               "last_vocal_bar": last_vocal + 1 if last_vocal >= 0 else None,
               "fade_out": fade_out}

    # ---------------------------------------------------------- key confidence (B.9)
    c1 = camelot(k1[0], k1[1])
    c2 = camelot(k2[0], k2[1])
    c3 = camelot(mm_key[0], mm_key[1]) if mm_key else None
    s1, s2 = float(k1[2]), float(k2[2])
    votes = [c for c in (c1, c2, c3) if c]
    from collections import Counter
    cnt = Counter(votes)
    top, nt = cnt.most_common(1)[0]
    if nt == 1:
        top = c1
    strength = s1 if top == c1 else (s2 if top == c2 else max(s1, s2))
    if c3 is None:
        if c1 == c2:
            kc = 0.7 if strength >= 0.6 else 0.3
        else:
            kc = 0.3
        rule = "madmom unavailable: edma==bgate & strength>=0.6 -> 0.7 else 0.3"
    elif nt == 3:
        kc = 1.0 if strength >= 0.6 else 0.6
        rule = "all three agree"
    elif nt == 2:
        dissent = [c for c in votes if c != top][0]
        if camelot_neighbour(top, dissent):
            kc = 0.65
            rule = "2 of 3 agree, dissenter is a Camelot neighbour"
        else:
            kc = 0.45
            rule = "2 of 3 agree, dissenter incompatible"
        if strength < 0.6:
            kc = 0.3
            rule += "; strength < 0.6"
    else:
        kc = 0.3
        rule = "no two detectors agree"
    key = {"essentia_edma": [k1[0], k1[1], round(s1, 3)],
           "essentia_bgate": [k2[0], k2[1], round(s2, 3)],
           "madmom_cnn": [mm_key[0], mm_key[1], round(mm_key[2], 3)] if mm_key else None,
           "camelot_edma": c1, "camelot_bgate": c2, "camelot_madmom": c3,
           "camelot": top, "confidence": kc, "confidence_rule": rule}
    if mm_key_err:
        key["madmom_error"] = mm_key_err

    # ---------------------------------------------------------- flags
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

    grid_out = {"source": grid_src, "bpm": round(bpm, 3), "first_downbeat_s": round(fd, 4),
                "beat_s": round(P, 5), "bar_s": round(bar_s, 5),
                "fit_mad_ms": round(G["fit_mad_ms"], 2), "inlier_frac": round(G["inlier_frac"], 3),
                "downbeat_agree": round(G["downbeat_agree"], 3), "confidence": round(G["confidence"], 3),
                "n_bars": n_bars}
    alt = {}
    for k_, g_ in grids.items():
        if g_ is not None:
            alt[k_] = {"bpm": round(g_["bpm"], 3), "fit_mad_ms": round(g_["fit_mad_ms"], 2),
                       "confidence": round(g_["confidence"], 3), "tag_dev_pct": round(tag_dev(g_), 2)}
        else:
            alt[k_] = None

    out = {
        "schema": SCHEMA_VERSION,
        "id": track["id"], "title": track.get("title"), "ver": track.get("ver"),
        "path": track["path"], "sr": SR, "duration_s": round(duration, 3),
        "bpm_tag": bpm_tag,
        "bpm_beatthis": r3(grid_bt["bpm"]) if grid_bt else None,
        "bpm_beatthis_median_ibi": r3(60 / np.median(np.diff(bt_beats))) if len(bt_beats) > 2 else None,
        "bpm_essentia": r3(bpm_ess), "essentia_confidence": r3(ess_conf),
        "essentia_agree": bool(ess_dev is not None and ess_dev < 2.0),
        "bpm_madmom": r3(grids["madmom"]["bpm"]) if grids.get("madmom") else None,
        "madmom_ran": run_mm, "madmom_reason": madmom_reason,
        "bpm": round(bpm, 3), "bpm_agree": bpm_agree,
        "multiplier_vs_tag": mult_label(mult_tag), "multiplier_vs_tag_value": round(mult_tag, 4),
        "tag_dev_pct": round(dev_tag, 2),
        "octave_fix": octave_fix,
        "grid": grid_out, "grid_candidates": alt,
        "beats_s": rlist(grid_beats_all), "downbeats_s": rlist(bar_t),
        "detected_beats_s": rlist(bt_beats), "detected_downbeats_s": rlist(bt_downs),
        "madmom_downbeats_s": rlist(mm_downs) if mm_downs is not None else None,
        "phrase": {"lattice_phase_bar": phase + 1, "phrase_len_bars": 8,
                   "confidence": round(phrase_conf, 3), "phase_novelty": rlist(sums, 3),
                   "snap_phase_bar": snap_phase + 1},
        "boundaries_bars": [b + 1 for b in boundaries0],
        "novelty_peaks": [[b + 1, round(v, 3)] for b, v in sorted(peaks)],
        "sections": sections,
        "first_sound_s": round(first_sound, 3), "last_sound_s": round(last_sound, 3),
        "fade_out": fade_out, "fade_drop_lu": round(fade_drop, 2),
        "end_lufs_st": {"t-20": round(l20, 2), "t-10": round(l10, 2), "t-4": round(l4, 2)},
        "tail_bars": round(float(tail_bars), 2),
        "fade_start_bar": fade_start_bar + 1 if fade_start_bar is not None else None,
        "mix_in": mix_in, "mix_out": mix_out,
        "key": key,
        "loudness": {"integrated_lufs": round(integ, 2), "lra": r3(lra), "true_peak_db": round(tp, 2)},
        "per_bar": {"lufs_st": rlist(lufs_st, 2), "low_db": rlist(low_db, 2), "high_db": rlist(high_db, 2),
                    "onset_density": rlist(onset_den, 3), "vocal_prob": rlist(vocal_bar, 3)},
        "onset_pattern_16": rlist(pat, 4),
        "vocal": {"mean_prob": round(mean_vocal, 4), "vocal_heavy": vocal_heavy,
                  "patch_hop_s": round(hop_s, 4), "n_patches": int(len(voice))},
        "embedding_effnet": [round(float(v), 4) for v in emb_mean],
        "flags": flags,
        "meta": {"secs": track.get("secs"), "on_disc": track.get("on_disc"), "disc": track.get("disc"),
                 "folder": track.get("folder"), "hal": track.get("hal"), "kind": track.get("kind"),
                 "era": track.get("era"), "cut_key": track.get("cut_key"), "is_longest": track.get("is_longest")},
        "timing_s": {k_: round(v, 2) for k_, v in timings.items()},
        "beatthis_device": M.bt_device,
    }
    out["local_tempo"] = local_tempo.compute(out)
    for fl in local_tempo.flags(out["local_tempo"]):
        if fl not in out["flags"]:
            out["flags"].append(fl)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ids", default=None, help="comma-separated ids")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--madmom", choices=["always", "auto", "never"], default="auto")
    ap.add_argument("--log", default=ERR_LOG, help="error log path")
    a = ap.parse_args()

    os.makedirs(FEAT_DIR, exist_ok=True)
    tracks = json.load(open(CANDIDATES))
    if a.ids:
        want = [s.strip() for s in a.ids.split(",") if s.strip()]
        byid = {t["id"]: t for t in tracks}
        missing = [i for i in want if i not in byid]
        if missing:
            print("unknown ids:", ",".join(missing), flush=True)
        tracks = [byid[i] for i in want if i in byid]
    todo = [t for t in tracks if a.force or not os.path.exists(os.path.join(FEAT_DIR, t["id"] + ".json"))]
    if a.limit:
        todo = todo[:a.limit]
    print(f"{len(tracks)} tracks selected, {len(todo)} to analyse (madmom={a.madmom})", flush=True)
    if not todo:
        return
    t0 = time.time()
    M = Models()
    print(f"models loaded in {time.time() - t0:.1f}s (Beat This on {M.bt_device}; madmom key: "
          f"{'ok' if M.mm_key else M.mm_key_err})", flush=True)
    ok = fail = 0
    for i, tr in enumerate(todo, 1):
        ts = time.time()
        try:
            if not os.path.exists(tr["path"]):
                raise FileNotFoundError(tr["path"])
            res = analyse(tr, M, a.madmom)
            dst = os.path.join(FEAT_DIR, tr["id"] + ".json")
            tmp = dst + ".tmp"
            with open(tmp, "w") as f:
                json.dump(res, f, separators=(",", ":"))
            os.replace(tmp, dst)
            ok += 1
            print(f"[{i}/{len(todo)}] {tr['id']} {time.time() - ts:5.1f}s  bpm {res['bpm']:.2f} "
                  f"(tag {res['bpm_tag']}, x{res['multiplier_vs_tag']}) grid {res['grid']['confidence']:.2f} "
                  f"key {res['key']['camelot']} ({res['key']['confidence']:.2f}) "
                  f"in {res['mix_in']['bars']} out {res['mix_out']['bars']} "
                  f"{'madmom ' if res['madmom_ran'] else ''}| {tr['title']} {tr.get('ver') or ''}", flush=True)
        except Exception as e:
            fail += 1
            msg = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {tr['id']} {tr.get('title')}: {type(e).__name__}: {e}\n"
            with open(a.log, "a") as f:
                f.write(msg)
                f.write(traceback.format_exc() + "\n")
            print(f"[{i}/{len(todo)}] {tr['id']} {time.time() - ts:5.1f}s  ERROR {type(e).__name__}: {e}", flush=True)
    print(f"done: {ok} ok, {fail} failed, {time.time() - t0:.0f}s total", flush=True)


if __name__ == "__main__":
    main()
