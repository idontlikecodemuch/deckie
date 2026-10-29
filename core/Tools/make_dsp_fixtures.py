#!/usr/bin/env python3
"""Write the reference numbers the DSP tests compare against: the FFT (numpy.fft), the chroma the lab's key estimator
reads (librosa.feature.chroma_stft exactly as mixer/key_light.py calls it), and soxr's resampling for the stopgap
decimator. Nothing here is downloaded at test time; the Swift tests read the JSON this writes.

  python3 core/Tools/make_dsp_fixtures.py        # from anywhere; needs numpy and librosa (which brings soxr)

The lab ran librosa 1.0.0 (mixer/README.md); the fixture records the versions it was made with.

Every input is computed, never stored, by recipes the Swift tests repeat operation for operation, so both sides get
the same bits: noise from SplitMix64 (integer arithmetic, then (z >> 11) * 2^-53), tones from sin() of
(2 pi f k / sr) times the sample index. numpy's float64 sin and the C library's give identical results on the
machine this was written on (checked: 0 differences in 2.2 million values); the signal is then rounded to float32,
the type the lab reads audio as (soundfile, dtype="float32").

Output: core/Tests/DeckieCoreTests/Fixtures/dsp.json
  fft          numpy.fft.rfft (and numpy.fft.fft for the smaller sizes) of SplitMix64 noise, sizes 1 to 8192
  hann         a few values of scipy.signal.get_window("hann", 8192), the window librosa.stft uses
  filterbank   librosa.filters.chroma(sr=22050, n_fft=8192, tuning=0.0), float32, at a few FFT bins
  chroma       per synthesised signal: librosa's chroma for the float32 signal (the lab's path) and for the float64
               signal (the same algorithm without single-precision rounding), the first 30 and the last 3 frames,
               and the frame count
  decimate     a 44.1 kHz signal resampled to 22.05 kHz by soxr "hq" through librosa.resample, as the lab's load()
               does: a stretch of samples, and the chroma of the result
"""
import json, math, os, sys
import numpy as np
import scipy.signal
import librosa

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "DeckieCoreTests", "Fixtures")
SR, NFFT, HOP = 22050, 8192, 2048  # mixer/key_light.py
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB


def splitmix(seed, n):
    """The first n outputs of SplitMix64 started at state `seed`, as uniform values in [0, 1)."""
    with np.errstate(over="ignore"):
        z = np.uint64(seed) + (np.arange(1, n + 1, dtype=np.uint64) * np.uint64(GOLDEN))
        z = (z ^ (z >> np.uint64(30))) * np.uint64(M1)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(M2)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) * 2.0 ** -53


def synth(sr, n, chords, harmonics, noise, seed):
    """Chords with harmonics plus noise, in float64. chords: (first sample, end sample, MIDI notes); each note is
    sum over k of (0.2 / k) env sin(2 pi f k / sr * i) for harmonics below sr / 2, f = 440 * 2^((m - 69) / 12),
    i the absolute sample index, env a 10 ms linear ramp in and out. Then noise * (2 u - 1) with u from SplitMix64."""
    i = np.arange(n, dtype=np.float64)
    y = np.zeros(n)
    ramp = int(0.01 * sr)
    for a, b, notes in chords:
        length = b - a
        j = np.arange(length, dtype=np.float64)
        env = np.minimum(1.0, np.minimum((j + 1) / ramp, (length - j) / ramp))
        for m in notes:
            f = 440.0 * 2.0 ** ((m - 69) / 12.0)
            for k in range(1, harmonics + 1):
                if f * k >= sr / 2:
                    break
                w = 2.0 * math.pi * f * k / sr
                y[a:b] += (0.2 / k) * env * np.sin(w * i[a:b])
    y += noise * (2.0 * splitmix(seed, n) - 1.0)
    return y


def progression(sr, n, chord_s, chords):
    """The chords in turn, each for chord_s seconds (rounded down to samples), repeated to fill n samples."""
    step = int(chord_s * sr)
    out, a, c = [], 0, 0
    while a < n:
        out.append((a, min(a + step, n), chords[c % len(chords)]))
        a += step
        c += 1
    return out


# MIDI notes: C4 = 60. Triads with the root an octave and a half below as bass.
C, F, G = [48, 60, 64, 67], [41, 65, 69, 72], [43, 67, 71, 74]
Am, Dm, E = [45, 57, 60, 64], [38, 62, 65, 69], [40, 64, 68, 71]
Fs, B, Cs = [42, 66, 70, 73], [47, 59, 63, 66], [49, 61, 65, 68]
N20 = 20 * SR
SIGNALS = [
    # name, samples, chords, harmonics, noise, seed
    ("c_major_held", N20, [(0, N20, C)], 6, 0.01, 1),
    ("a_minor_progression", N20, progression(SR, N20, 2.5, [Am, Dm, E, Am]), 6, 0.02, 2),
    ("f_sharp_major_progression", N20, progression(SR, N20, 2.0, [Fs, B, Cs, Fs]), 8, 0.02, 3),
    ("a_446_hz_and_noise", N20, [(0, N20, [69.25])], 4, 0.05, 4),
    ("short_6615_samples", 6615, [(0, 6615, C)], 6, 0.01, 5),
    ("odd_length_67253", 67253, progression(SR, 67253, 1.0, [C, F, G, C]), 6, 0.01, 6),
    ("silence_then_chord", N20, [(5 * SR, N20, Dm)], 6, 0.0, 7),
]


def f32(x):
    """Shortest text that reads back as the same float32 (the JSON stays small; Swift's Float(x) is exact)."""
    return float(str(np.float32(x)))


def chroma(y):
    return librosa.feature.chroma_stft(y=y, sr=SR, n_fft=NFFT, hop_length=HOP, tuning=0.0)  # key_light.chroma


def frames(C, as_f32):
    pick = list(range(min(30, C.shape[1]))) + [t for t in range(max(30, C.shape[1] - 3), C.shape[1])]
    return {"index": pick, "values": [[f32(v) if as_f32 else float(v) for v in C[:, t]] for t in pick]}


def fft_fixture():
    out = []
    for n, seed in ((1, 11), (2, 12), (4, 13), (8, 14), (16, 15), (32, 16), (64, 17), (256, 18), (1024, 19), (8192, 20)):
        x = 2.0 * splitmix(seed, n) - 1.0
        X = np.fft.rfft(x)
        bins = list(range(len(X))) if n <= 1024 else sorted(set(range(0, len(X), 31)) | {1, 2, len(X) - 2, len(X) - 1})
        row = {"n": n, "seed": seed, "rfft_bins": bins, "rfft": [[float(X[k].real), float(X[k].imag)] for k in bins]}
        if n <= 256:
            xi = 2.0 * splitmix(seed + 100, n) - 1.0
            Z = np.fft.fft(x + 1j * xi)
            row["imag_seed"] = seed + 100
            row["fft"] = [[float(z.real), float(z.imag)] for z in Z]
        out.append(row)
    return out


def main():
    hann = scipy.signal.get_window("hann", NFFT, fftbins=True)
    hann_idx = [0, 1, 2, 1000, 2048, 4095, 4096, 4097, 6000, 8191]
    fb = librosa.filters.chroma(sr=SR, n_fft=NFFT, tuning=0.0)
    fb_bins = [0, 1, 2, 3, 10, 24, 100, 101, 500, 1000, 2000, 3000, 4095, 4096]
    sigs = []
    for name, n, chords, harm, noise, seed in SIGNALS:
        y = synth(SR, n, chords, harm, noise, seed)
        c32, c64 = chroma(y.astype(np.float32)), chroma(y)
        assert c32.shape[1] == 1 + n // HOP, (name, c32.shape)
        sigs.append({"name": name, "samples": n, "harmonics": harm, "noise": noise, "seed": seed,
                     "chords": [[a, b, notes] for a, b, notes in chords], "frames": int(c32.shape[1]),
                     "float32": frames(c32, True), "float64": frames(c64, False)})
        print(f"{name}: {n} samples, {c32.shape[1]} frames", file=sys.stderr)

    # the stopgap decimator against soxr "hq", as the lab's load() resamples 44.1 kHz files
    n44 = 10 * 44100
    chords44 = progression(44100, n44, 2.5, [Am, Dm, E, Am])
    y44 = synth(44100, n44, chords44, 12, 0.02, 8).astype(np.float32)
    y22 = librosa.resample(y44, orig_sr=44100, target_sr=22050, res_type="soxr_hq")
    lo, hi = 100000, 100512
    decim = {"samples": n44, "harmonics": 12, "noise": 0.02, "seed": 8, "chords": [[a, b, m] for a, b, m in chords44],
             "out_samples": int(len(y22)), "stretch_start": lo, "stretch": [f32(v) for v in y22[lo:hi]],
             "chroma": frames(chroma(y22), True)}

    doc = {"versions": {"numpy": np.__version__, "librosa": librosa.__version__, "scipy": scipy.__version__},
           "fft": fft_fixture(),
           "hann": {"n": NFFT, "index": hann_idx, "values": [float(hann[i]) for i in hann_idx]},
           "filterbank": {"bins": fb_bins, "values": [[f32(fb[c, b]) for c in range(12)] for b in fb_bins]},
           "chroma": sigs, "decimate": decim}
    path = os.path.join(OUT, "dsp.json")
    with open(path, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB)")


if __name__ == "__main__":
    main()
