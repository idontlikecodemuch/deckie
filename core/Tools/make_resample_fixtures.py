#!/usr/bin/env python3
"""Write the reference numbers for three audio pieces of the lab's analyser that the Swift core ports: the resampler
(soxr at quality "HQ", which mixer/analyze.py and mixer/key_light.py call), the two-band split with its per-bar levels
(`lr4` and the `low_db` / `high_db` loop in mixer/analyze.py, scipy) and the first and last sound (the -60 dBFS rule
in mixer/analyze.py). Nothing here is downloaded at test time; the Swift tests read the JSON this writes.

  python3 core/Tools/make_resample_fixtures.py        # from anywhere; needs numpy, scipy and soxr
  python3 core/Tools/make_resample_fixtures.py --fit  # prints the fit behind Resampler.Design.soxrHQ; writes nothing

Every input is computed, never stored, by recipes the Swift tests repeat operation for operation, so both sides get
the same bits: noise from SplitMix64 (integer arithmetic, then (z >> 11) * 2^-53), tones and sweeps from Python's
math.sin (the C library's sin, as Swift's on Linux) of a phase computed in the order written here; then rounded to
float32, the type the lab reads audio as.

Output: core/Tests/DeckieCoreTests/Fixtures/resample.json
  ratios      per pair of rates (44.1 to 22.05 kHz, 48 to 44.1 kHz, 44.1 to 16 kHz and back): for each test signal (a sweep
              to the input's Nyquist frequency, a multitone, white noise, clicks including the first and last sample)
              soxr's output length, its RMS, and its first 48, a middle 256 and last 48 samples; for the multitone, soxr's gain
              at each tone and the level of each alias or image, and its delay, measured with a Kaiser-windowed DFT
              (beta 20) as the Swift test measures the port; soxr's response measured from impulses at every input
              phase (passband ripple, the -3 and -6 dB points, the stopband).
Output: core/Tests/DeckieCoreTests/Fixtures/bands.json
  bands       a stereo signal at 44.1 and at 48 kHz (tones on and off, noise, digital silence) through the lab's lr4
              (scipy.signal.butter(2, fc, btype, fs=rate, output="sos"), sosfilt twice) at 150 Hz low-pass and 4 kHz
              high-pass: the sections, the filtered mono at a few hundred samples, and the per-bar low_db and high_db
              exactly as the lab's loop computes them (bars past the end included)
  bounds      first and last sound by the lab's rule (10 ms frames, peak over channels, -60 dBFS, float32 comparison),
              with the frame sample_rate // 100 (441 at 44.1 kHz, the lab's), on synthesised cases: silence at both
              ends, all quiet, all zero, sound at the very start and end, sound only in the partial last frame (which
              the lab drops), one channel only, a sample exactly at the threshold, shorter than one frame, 48 kHz, mono
"""
import json, math, os, sys
from math import gcd
import numpy as np
import scipy
import scipy.signal
import soxr

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "DeckieCoreTests", "Fixtures")
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB


def splitmix(seed, n):
    """The first n outputs of SplitMix64 started at state `seed`, as uniform values in [0, 1)."""
    with np.errstate(over="ignore"):
        z = np.uint64(seed) + (np.arange(1, n + 1, dtype=np.uint64) * np.uint64(GOLDEN))
        z = (z ^ (z >> np.uint64(30))) * np.uint64(M1)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(M2)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) * 2.0 ** -53


def f32(x):
    """Shortest text that reads back as the same float32."""
    return float(str(np.float32(x)))


# ----------------------------------------------------------------------------------------------------- resampling
RATIOS = [(44100, 22050), (22050, 44100), (48000, 44100), (44100, 48000), (44100, 16000), (16000, 44100)]
TONE_AMP = 0.04
PASS = [0.02, 0.1, 0.3, 0.5, 0.7, 0.8, 0.9]           # fractions of the lower rate's Nyquist frequency
TRANSITION = [0.913, 0.93, 0.95, 0.97, 0.99]
ABOVE = [1.02, 1.04, 1.06, 1.12, 1.25, 1.45, 1.65, 1.85, 2.2, 2.4, 2.6]  # downsampling only; folds miss every tone
HEAD, MID, TAIL = 48, 256, 48
BETA_ANALYSIS = 20.0
HALF_LENGTH = 97.25  # soxr HQ's measured half-length in periods of the lower rate (Resampler.Design.soxrHQ)


def tones_for(fin, fout):
    low_nyq = min(fin, fout) / 2
    fr = PASS + TRANSITION + ([a for a in ABOVE if a * low_nyq < 0.98 * fin / 2] if fout < fin else [])
    return [float(round(a * low_nyq)) for a in fr]


def signal(kind, fin, n, seed, tones):
    if kind == "sweep":  # linear chirp from 20 Hz to the input's Nyquist frequency, amplitude 0.5
        f0, f1 = 20.0, fin / 2.0
        y = [0.5 * math.sin(2.0 * math.pi * (f0 * i / fin + (f1 - f0) * i * i / (2.0 * fin * n))) for i in range(n)]
    elif kind == "multitone":
        y = [0.0] * n
        for f in tones:
            w = 2.0 * math.pi * f / fin
            for i in range(n):
                y[i] += TONE_AMP * math.sin(w * i)
    elif kind == "noise":
        y = 0.5 * (2.0 * splitmix(seed, n) - 1.0)
    elif kind == "click":
        y = [0.0] * n
        y[0], y[n // 3], y[n // 2], y[n - 1] = 0.8, -0.6, 0.7, 0.8
    return np.asarray(y, dtype=np.float64).astype(np.float32)


def kaiser(n, beta):
    return scipy.signal.windows.kaiser(n, beta, sym=True)


def analysis_span(fin, fout, count):
    """Output samples clear of the filter's start and end transients."""
    edge = int(math.ceil(1.25 * HALF_LENGTH * fout / min(fin, fout)))
    return edge, count - edge


def tone_levels(y, fin, fout, tones):
    """Per tone: its gain in dB at the output (when below the output's Nyquist frequency), and the level in dB, relative
    to the tone, of each alias (downsampling) or image (upsampling) below the output's Nyquist frequency; and the delay
    in output samples measured on the passband tones. A Kaiser-windowed DFT (beta 20) over the span clear of the ends."""
    a, b = analysis_span(fin, fout, len(y))
    seg = y[a:b].astype(np.float64)
    k = np.arange(a, b, dtype=np.float64)
    w = kaiser(b - a, BETA_ANALYSIS)
    sw = w.sum()

    def dft(freq):
        om = 2.0 * math.pi * freq / fout
        return np.sum(w * seg * np.exp(-1j * om * k))

    def ref(freq):
        om = 2.0 * math.pi * freq / fout
        return np.sum(w * np.sin(om * k) * np.exp(-1j * om * k))

    out, delays = [], []
    low_nyq = min(fin, fout) / 2
    for f in tones:
        row = {"f": f}
        if f < fout / 2:
            Y = dft(f)
            row["gain_db"] = 20 * math.log10(2 * abs(Y) / sw / TONE_AMP)
            if f <= 0.9 * low_nyq + 1:
                om = 2.0 * math.pi * f / fout
                delays.append(-np.angle(Y / ref(f)) / om)
        others = []
        if fout < fin:  # aliases: f folded about multiples of the output rate
            if f >= fout / 2:
                others.append(abs(f - round(f / fout) * fout))
        else:  # images: m fin +- f below the output's Nyquist frequency
            m = 1
            while m * fin - f < fout / 2:
                others.append(m * fin - f)
                if m * fin + f < fout / 2:
                    others.append(m * fin + f)
                m += 1
        row["spurs"] = [[g, 20 * math.log10(max(2 * abs(dft(g)) / sw, 1e-30) / TONE_AMP)] for g in others]
        out.append(row)
    return out, float(np.mean(delays)), float(np.max(np.abs(delays)))


def soxr_response(fin, fout):
    """soxr's impulse response on the fine grid of rate up * fin (an impulse at every input phase), and from it the
    passband ripple, the -3 and -6 dB points and the stopband."""
    g = gcd(fin, fout)
    L, M = fout // g, fin // g
    fine = L * fin
    unit = max(L, M)
    reach = int(1.6 * HALF_LENGTH * unit)
    h = np.zeros(2 * reach + 1)
    gap = (int(4 * HALF_LENGTH * fin / min(fin, fout)) // M + 1) * M  # a multiple of M: impulse j sits at phase j
    positions = list(range(M))
    while positions:
        chunk, positions = positions[:50], positions[50:]
        x = np.zeros((len(chunk) + 2) * gap, dtype=np.float32)
        ps = [gap + i * gap + j for i, j in enumerate(chunk)]
        x[ps] = 1.0
        y = soxr.resample(x, fin, fout).astype(np.float64)
        for p in ps:
            # output k at fine position k M; the impulse at p L; u = k M - p L
            k = np.arange(len(y))
            u = k * M - p * L
            sel = np.abs(u) <= reach
            h[u[sel] + reach] = y[sel]
    size = 1 << int(math.ceil(math.log2(len(h) * 8)))
    H = np.abs(np.fft.rfft(h, size))
    db = 20 * np.log10(np.maximum(H / H[0], 1e-30))
    f = np.arange(len(H)) * fine / size
    low_nyq = min(fin, fout) / 2
    r45, r90 = f <= 0.45 * low_nyq, f <= 0.9 * low_nyq
    return {
        "ripple_045_db": float(db[r45].max() - db[r45].min()),
        "ripple_090_db": float(db[r90].max() - db[r90].min()),
        "minus3_db_at": float(f[np.nonzero(db < -3)[0][0]] / low_nyq),
        "minus6_db_at": float(f[np.nonzero(db < -20 * math.log10(2))[0][0]] / low_nyq),
        "stopband_db": float(db[f >= low_nyq].max()),
        "resolution_hz": fine / size,
    }


def fit_soxr_hq():
    """Where Resampler.Design.soxrHQ comes from: soxr's impulse response at 44.1 to 22.05 kHz and back (an impulse at
    every input phase), fitted with a Kaiser-windowed sinc, g * 2 fc sinc(2 fc t) I0(beta sqrt(1 - (t / T)^2)) / I0(beta),
    t in seconds. Prints the cutoff (as a fraction of the lower Nyquist frequency), the half-length T (in periods of
    the lower rate), beta, the gain g and the largest residual. Run with --fit."""
    from scipy.optimize import minimize
    from scipy.special import i0
    for fin, fout in ((44100, 22050), (22050, 44100)):
        g = gcd(fin, fout)
        L, M = fout // g, fin // g
        low = min(fin, fout)
        gap = 1500 // M * M
        x = np.zeros(4 * gap, dtype=np.float32)
        ps = [gap + j * gap + j for j in range(M)]
        x[ps] = 1.0
        y = soxr.resample(x, fin, fout).astype(np.float64)
        k = np.arange(len(y))
        tau = np.concatenate([k / fout - p / fin for p in ps])
        v = np.concatenate([y for _ in ps])
        sel = np.abs(tau) < 300 / fin
        tau, v = tau[sel], v[sel]

        def model(p):
            fc, half, beta, gain = p
            r = tau / (half / low)
            w = np.where(np.abs(r) <= 1, i0(beta * np.sqrt(np.clip(1 - r * r, 0, None))) / i0(beta), 0.0)
            return gain * (2 * fc * low / 2 / fin) * np.sinc(2 * fc * low / 2 * tau) * w

        best = minimize(lambda p: np.sum((model(p) - v) ** 2) * 1e12, [0.9569, 97.0, 13.0, 1.0], method="Nelder-Mead",
                        options={"xatol": 1e-10, "fatol": 1e-14, "maxiter": 20000, "maxfev": 40000})
        fc, half, beta, gain = best.x
        print(f"{fin} -> {fout}: cutoff {fc:.6f} of the lower Nyquist, half-length {half:.4f} periods of the lower rate, "
              f"beta {beta:.4f}, gain {gain:.8f}; largest residual {np.abs(model(best.x) - v).max():.1e} "
              f"(peak {v.max():.3f})")


def ratio_fixture(fin, fout, seed):
    n = fin // 2 + 1
    tones = tones_for(fin, fout)
    row = {"in_rate": fin, "out_rate": fout, "samples": n, "noise_seed": seed, "tones": tones, "signals": []}
    for kind in ("sweep", "multitone", "noise", "click"):
        x = signal(kind, fin, n, seed, tones)
        y = soxr.resample(x, fin, fout)
        assert y.dtype == np.float32
        mid = len(y) // 2 - MID // 2
        sig = {"kind": kind, "out_samples": int(len(y)), "rms": float(np.sqrt(np.mean(y.astype(np.float64) ** 2))),
               "head": [f32(v) for v in y[:HEAD]], "mid_start": mid,
               "mid": [f32(v) for v in y[mid:mid + MID]], "tail": [f32(v) for v in y[-TAIL:]]}
        if kind == "multitone":
            levels, delay, delay_max = tone_levels(y, fin, fout, tones)
            sig["levels"], sig["delay"], sig["delay_max"] = levels, delay, delay_max
        row["signals"].append(sig)
    row["response"] = soxr_response(fin, fout)
    lengths = [1, 2, 3, 10, 11, 100, 101, 1000, 1001, 44099, 44101]
    row["lengths"] = [[m, int(len(soxr.resample(np.zeros(m, dtype=np.float32), fin, fout)))] for m in lengths]
    print(f"{fin} -> {fout}: {n} samples in, {row['signals'][0]['out_samples']} out; soxr response {row['response']}",
          file=sys.stderr)
    return row


# ----------------------------------------------------------------------------------------------------- band split
# (start s, end s, Hz, amplitude, channels: 1 left, 2 right, 3 both)
BAND_TONES = [
    (0.0, 6.0, 55.0, 0.25, 3), (2.0, 9.0, 130.0, 0.2, 1), (4.0, 12.0, 440.0, 0.15, 3), (5.0, 7.5, 3000.0, 0.1, 2),
    (6.0, 14.0, 4200.0, 0.08, 3), (8.0, 15.0, 9000.0, 0.06, 1), (10.0, 13.0, 15000.0, 0.05, 2),
    (12.5, 14.0, 150.0, 0.3, 3), (14.0, 15.5, 4000.0, 0.2, 3),
]
BAND_SECONDS, BAND_NOISE, BAND_ZERO = 19.3, 0.002, (15.5, 18.6)
BAND_P, BAND_FD, BAND_BARS = 0.3, 0.25, 17  # beat 0.3 s, bar 1 at 0.25 s; bar 16 runs past the end, bar 17 after it


def band_signal(sr):
    """Stereo float32: the tones (each sum term amp * sin(w * i), w = 2 pi f / sr, i the absolute sample index), noise
    BAND_NOISE * (2u - 1) on each channel (SplitMix64 seeds 21 and 22), then exact zeros over BAND_ZERO."""
    n = int(BAND_SECONDS * sr)
    y = np.zeros((n, 2))
    for a, b, f, amp, ch in BAND_TONES:
        s, e = int(a * sr), int(b * sr)
        w = 2.0 * math.pi * f / sr
        v = np.array([amp * math.sin(w * i) for i in range(s, e)])
        if ch & 1:
            y[s:e, 0] += v
        if ch & 2:
            y[s:e, 1] += v
    y[:, 0] += BAND_NOISE * (2.0 * splitmix(21, n) - 1.0)
    y[:, 1] += BAND_NOISE * (2.0 * splitmix(22, n) - 1.0)
    y[int(BAND_ZERO[0] * sr):int(BAND_ZERO[1] * sr)] = 0.0
    return y.astype(np.float32)


def db(x, floor=-120.0):  # mixer/analyze.py
    return float(max(floor, 10 * math.log10(max(float(x), 1e-30))))


def lr4(x, fc, btype, sr):  # mixer/analyze.py, with fs=sr in place of the lab's 44100
    sos = scipy.signal.butter(2, fc, btype=btype, fs=sr, output="sos")
    return scipy.signal.sosfilt(sos, scipy.signal.sosfilt(sos, x))


def band_fixture(sr):
    y = band_signal(sr)
    mono = np.ascontiguousarray(y.mean(axis=1), dtype=np.float32)  # mixer/analyze.py
    n = len(mono)
    low = lr4(mono.astype(np.float64), 150, "low", sr)
    high = lr4(mono.astype(np.float64), 4000, "high", sr)
    bar_s = 4 * BAND_P
    bar_t = BAND_FD + np.arange(BAND_BARS + 1) * bar_s
    bi = np.round(bar_t * sr).astype(int)
    low_db, high_db = [], []
    with np.errstate(all="ignore"):
        import warnings
        warnings.simplefilter("ignore")
        for a, b2 in zip(bi[:-1], bi[1:]):  # the lab's loop
            low_db.append(db(np.mean(low[a:b2] ** 2)))
            high_db.append(db(np.mean(high[a:b2] ** 2)))
    idx = sorted(set(list(range(0, 40)) + list(range(0, n, n // 300)) + [n - 2, n - 1]
                     + [int(t * sr) + d for t in (2.0, 6.0, 12.5, 14.0, 15.5) for d in (-1, 0, 1, 5)]))
    sos_lo = scipy.signal.butter(2, 150, btype="low", fs=sr, output="sos")[0]
    sos_hi = scipy.signal.butter(2, 4000, btype="high", fs=sr, output="sos")[0]
    print(f"bands at {sr}: {n} samples, bar frames {bi.tolist()}, low_db {[round(v, 2) for v in low_db]}, "
          f"high_db {[round(v, 2) for v in high_db]}", file=sys.stderr)
    return {"rate": sr, "samples": n, "bar_frames": bi.tolist(),
            "sos_low": [float(v) for v in sos_lo], "sos_high": [float(v) for v in sos_hi],
            "index": idx, "low": [float(low[i]) for i in idx], "high": [float(high[i]) for i in idx],
            "low_db": low_db, "high_db": high_db}


# ----------------------------------------------------------------------------------------------------- first / last sound
def sound_bounds(y, sr):
    """mixer/analyze.py's rule, with the frame sr // 100 in place of the lab's 441 (equal at 44.1 kHz)."""
    n = len(y)
    thr = 10 ** (-60 / 20)
    fr = sr // 100
    nf = n // fr
    pk = np.abs(y[:nf * fr]).max(axis=1).reshape(nf, fr).max(axis=1)
    loud = np.nonzero(pk > thr)[0]
    first_sound = float(loud[0] * fr / sr) if len(loud) else 0.0
    last_sound = float((loud[-1] + 1) * fr / sr) if len(loud) else n / sr
    return first_sound, last_sound, int(len(loud))


THR32 = np.float32(10 ** (-60 / 20))
# name, rate, channels, samples, base noise amplitude, seed, events: [first, end, channel mask, kind, value]
#   kind "noise": value * (2u - 1) (SplitMix64(seed + 1 + event index)); "dc": the value; "set": the value at `first`
BOUNDS = [
    ("silence_both_ends", 44100, 2, 3 * 44100 + 100, 3e-4, 31, [[22067, 97025, 3, "noise", 0.3]]),
    ("all_quiet", 44100, 2, 2 * 44100, 9e-4, 32, []),
    ("all_zero", 44100, 2, 44100 + 17, 0.0, 33, []),
    ("loud_start_to_end", 44100, 2, 44100 + 300, 0.0, 34, [[0, 44100 + 300, 3, "noise", 0.5]]),
    ("partial_last_frame_only", 44100, 2, 10 * 441 + 200, 0.0, 35, [[4410, 4610, 3, "dc", 0.5]]),
    ("loud_middle_and_partial_last_frame", 44100, 2, 20 * 441 + 300, 0.0, 36,
     [[882, 1000, 1, "noise", 0.2], [8820, 9120, 3, "dc", -0.4]]),
    ("right_channel_only", 44100, 2, 44100, 0.0, 37, [[4411, 4412, 2, "set", 0.002], [30000, 30000 + 441, 2, "dc", 0.01]]),
    ("threshold_edge", 44100, 2, 100 * 441, 0.0, 38,
     [[441 * 10 + 5, 0, 1, "set", float(THR32)], [441 * 20 + 7, 0, 2, "set", float(np.nextafter(THR32, np.float32(1)))],
      [441 * 30, 0, 1, "set", -float(THR32)], [441 * 40 + 440, 0, 1, "set", -float(np.nextafter(THR32, np.float32(1)))]]),
    ("one_negative_click", 44100, 2, 50 * 441 + 1, 1e-5, 39, [[441 * 10 + 3, 0, 3, "set", -0.5]]),
    ("first_and_last_sample", 44100, 2, 30 * 441, 0.0, 40, [[0, 0, 1, "set", 0.1], [30 * 441 - 1, 0, 2, "set", 0.1]]),
    ("shorter_than_a_frame", 44100, 2, 300, 0.0, 41, [[0, 300, 3, "dc", 0.5]]),
    ("empty", 44100, 2, 0, 0.0, 42, []),
    ("at_48k", 48000, 2, 2 * 48000 + 77, 1e-4, 43, [[48000 + 13, 96000 - 5, 3, "noise", 0.2]]),
    ("mono_22050", 22050, 1, 22050 + 219, 2e-4, 44, [[221, 440, 1, "dc", 0.003], [21900, 22050 + 219, 1, "noise", 0.1]]),
]


def bounds_signal(rate, ch, n, base, seed, events):
    y = np.zeros((n, ch))
    if base > 0:
        for c in range(ch):
            y[:, c] = base * (2.0 * splitmix(seed * 10 + c, n) - 1.0)
    for e, (a, b, mask, kind, v) in enumerate(events):
        for c in range(ch):
            if not (mask >> c) & 1:
                continue
            if kind == "noise":
                y[a:b, c] += v * (2.0 * splitmix(seed * 10 + 5 + e, b - a) - 1.0)
            elif kind == "dc":
                y[a:b, c] += v
            elif kind == "set":
                y[a, c] = v
    return y.astype(np.float32)


def bounds_fixture():
    out = []
    for name, rate, ch, n, base, seed, events in BOUNDS:
        y = bounds_signal(rate, ch, n, base, seed, events)
        first, last, frames = sound_bounds(y, rate)
        out.append({"name": name, "rate": rate, "channels": ch, "samples": n, "base": base, "seed": seed,
                    "events": events, "first": first, "last": last, "loud_frames": frames})
        print(f"bounds {name}: first {first}, last {last}, {frames} loud frame(s)", file=sys.stderr)
    return out


def main():
    versions = {"numpy": np.__version__, "scipy": scipy.__version__, "soxr": soxr.__version__}
    ratios = [ratio_fixture(fin, fout, 50 + i) for i, (fin, fout) in enumerate(RATIOS)]
    for name, doc in (("resample.json", {"versions": versions, "head": HEAD, "mid": MID, "tail": TAIL,
                                          "tone_amp": TONE_AMP, "analysis_beta": BETA_ANALYSIS, "ratios": ratios}),
                      ("bands.json", {"versions": versions, "tones": BAND_TONES, "seconds": BAND_SECONDS,
                                      "noise": BAND_NOISE, "zero": BAND_ZERO, "beat_s": BAND_P, "first_bar_s": BAND_FD,
                                      "bars": BAND_BARS, "bands": [band_fixture(44100), band_fixture(48000)],
                                      "bounds": bounds_fixture()})):
        path = os.path.join(OUT, name)
        with open(path, "w") as f:
            json.dump(doc, f, separators=(",", ":"))
        print(f"wrote {path} ({os.path.getsize(path) // 1024} KB)")


if __name__ == "__main__":
    fit_soxr_hq() if "--fit" in sys.argv[1:] else main()
