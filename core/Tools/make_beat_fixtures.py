#!/usr/bin/env python3
"""Write the reference numbers the beat tracker's Swift port is checked against: what the Beat This! package
(beat_this 1.1.0, MIT) itself computes, piece by piece, on synthesised drum patterns. Nothing here runs at test
time; the Swift tests read the JSON this writes.

  python3 core/Tools/make_beat_fixtures.py [--time]   # from anywhere; needs the export tools (DEPENDENCIES.md, section 7)

The package's pieces, as read from its source (beat_this/preprocessing.py, inference.py, model/postprocessor.py):
  front end      LogMelSpect: torchaudio's MelSpectrogram at 22,050 Hz, n_fft 1024, hop 441 (50 frames a second),
                 periodic Hann window, centred frames with reflect padding, magnitude (power 1) divided by
                 sqrt(1024) ("frame_length" normalisation), 128 triangular mel filters on the Slaney mel scale from
                 30 Hz to 11 kHz without area normalisation, then log1p(1000 x mel). All in float32.
  resampling     Audio2Frames: stereo is averaged; any rate other than 22,050 Hz goes through soxr.resample (quality
                 "HQ") first.
  chunks         split_predict_aggregate: pieces are cut into chunks of 1,500 frames that overlap by 6 frames on
                 each side (the first and last padded with 6 frames of zeros, the last moved left to end at the
                 piece's end); each chunk's predictions lose 6 frames at either edge, and where chunks overlap the
                 earlier chunk wins ("keep_first").
  postprocessor  Postprocessor(type="minimal") at 50 frames a second: a frame is a peak if its logit equals the
                 largest within +-3 frames and is above 0; runs of peaks that are each at most one frame from the
                 running mean of their run are replaced by that mean; frames become seconds (/ 50); each downbeat
                 moves to the nearest beat (the first of two equally near), and repeated downbeats are dropped.

Every test signal is synthesised by a recipe the Swift tests repeat operation for operation (Tests/DeckieTestSignals/
DrumPattern.swift): templates from math.sin and math.exp (the C library's functions, as Swift's on Linux), noise
from SplitMix64 (integer arithmetic), and additions in the same order, so both sides get the same float32 samples.

Output: core/Tests/DeckieCoreTests/Fixtures/beat_this.json
  filterbank     torchaudio's mel filter bank: per mel band, its first nonzero FFT bin and the float32 weights
  frontend       per signal at 22,050 Hz: a check of the samples, LogMelSpect's frame count, a few whole frames
                 (and the same frames computed in float64, to separate the method from float32 rounding), and
                 every frame's sum
  chunking       per spectrogram length: split_piece's chunk starts and pads, and what split_predict_aggregate
                 assembles from a stand-in model whose outputs say which chunk position each frame came from
  postprocessor  hand-made logits (ties, plateaus, edges, nothing above zero) and their beats and downbeats
  pieces         the end-to-end signals (30 s at 120 BPM, and 90 s at 128 BPM turning to 100 BPM at 45 s, each at
                 44.1 kHz, which the package resamples with soxr, and at 22.05 kHz, which it reads as it is; the
                 first at 48 kHz too): the true beat times, the package's logits (float32, from the final0
                 checkpoint) and its beat and downbeat times
With --time it also prints how long the package takes for four minutes of the 128 BPM pattern on this machine.
"""
import importlib.metadata as md
import json, math, os, sys, time

import numpy as np
import torch
import torchaudio.functional as taf

from beat_this.inference import Audio2Frames, split_piece, split_predict_aggregate
from beat_this.model.postprocessor import Postprocessor
from beat_this.preprocessing import LogMelSpect

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Tests", "DeckieCoreTests", "Fixtures", "beat_this.json")
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB


def splitmix(seed, n):
    """The first n outputs of SplitMix64 started at state `seed`, as uniform values in [0, 1)."""
    with np.errstate(over="ignore"):
        z = np.uint64(seed) + (np.arange(1, n + 1, dtype=np.uint64) * np.uint64(GOLDEN))
        z = (z ^ (z >> np.uint64(30))) * np.uint64(M1)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(M2)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) * 2.0 ** -53


def steady_beats(first, bpm, end):
    """Beats from `first` every 60 / bpm seconds while before `end`; every fourth (from the first) accented."""
    out, k = [], 0
    while True:
        t = first + k * (60.0 / bpm)
        if t >= end:
            return [(t, i % 4 == 0) for i, t in enumerate(out)]
        out.append(t)
        k += 1


def tempo_change_beats(first, bpm1, bpm2, change, end):
    """Beats every 60 / bpm1 s from `first`; the first beat at or after `change` (still on that grid) starts beats
    every 60 / bpm2 s, until `end`. Every fourth beat accented, counting straight through the change."""
    out, k = [], 0
    while first + k * (60.0 / bpm1) < change:
        out.append(first + k * (60.0 / bpm1))
        k += 1
    pivot, j = first + k * (60.0 / bpm1), 0
    while pivot + j * (60.0 / bpm2) < end:
        out.append(pivot + j * (60.0 / bpm2))
        j += 1
    return [(t, i % 4 == 0) for i, t in enumerate(out)]


def onset(t, rate):
    """The sample a beat at t seconds starts on: floor(t rate + 0.5)."""
    return int(math.floor(t * rate + 0.5))


def drum_pattern(rate, n, beats, seed):
    """A drum-like pattern, float32: on every beat a kick (a sine falling from about 150 Hz to 45 Hz, decaying over
    about 0.1 s, with a 2 ms click at its start), at full level on accented beats (every fourth) and 0.6 on the
    others; a light snare (bright noise decaying over 50 ms) on every second beat, the backbeat; a hi-hat (bright
    noise decaying over 15 ms) on every beat and halfway to the next. Bright noise is the first difference of
    SplitMix64(seed) noise, indexed by the absolute sample. Each beat adds its kick, snare, hat and off-beat hat in
    that order; the sum is halved and rounded to float32.

    Why the snare: with the accent as the only cue for the bar, the model's downbeats wander between beats one and
    two, and with a crash on the accent it calls beat two the downbeat (measured with this checkpoint, Oct 28, 2026);
    the backbeat makes the bar unambiguous, so the test can ask for downbeats on the accents."""
    kick_len, hat_len, snare_len = int(0.25 * rate), int(0.06 * rate), int(0.2 * rate)
    kick = np.zeros(kick_len)
    for j in range(kick_len):
        t = j / rate
        phase = 2.0 * math.pi * (45.0 * t + 3.15 * (1.0 - math.exp(-t / 0.03)))
        kick[j] = math.exp(-t / 0.12) * math.sin(phase) + 0.4 * math.exp(-t / 0.002)
    hat = np.array([math.exp(-(j / rate) / 0.015) for j in range(hat_len)])
    snare = np.array([math.exp(-(j / rate) / 0.05) for j in range(snare_len)])
    u = 2.0 * splitmix(seed, n + 1) - 1.0
    bright = u[1:] - u[:-1]
    y = np.zeros(n)

    def add_kick(i, gain):
        m = min(kick_len, n - i)
        if m > 0:
            y[i:i + m] += gain * kick[:m]

    def add_noise(i, gain, env):
        m = min(len(env), n - i)
        if m > 0:
            y[i:i + m] += gain * env[:m] * bright[i:i + m]

    for k, (t, accent) in enumerate(beats):
        i = onset(t, rate)
        add_kick(i, 1.0 if accent else 0.6)
        if k % 2 == 1:
            add_noise(i, 0.2, snare)
        add_noise(i, 0.12, hat)
        if k + 1 < len(beats):
            add_noise(onset((t + beats[k + 1][0]) / 2.0, rate), 0.12, hat)
    return (0.5 * y).astype(np.float32)


def f32(x):
    """Shortest text that reads back as the same float32 (Swift's Float(x) is then exact)."""
    return float(str(np.float32(x)))


def synth_check(y):
    """Enough of a synthesised signal to tell whether Swift made the same samples: their sum (math.fsum, exactly
    rounded) and every 1,000th sample."""
    return {"sum": math.fsum(float(v) for v in y), "every_1000th": [f32(v) for v in y[::1000]]}


def filterbank():
    fb = taf.melscale_fbanks(513, 30.0, 11000.0, 128, 22050, None, "slaney").numpy()
    out = []
    for m in range(fb.shape[1]):
        nz = np.nonzero(fb[:, m])[0]
        first, last = int(nz[0]), int(nz[-1])
        assert np.all(fb[first:last + 1, m] > 0), m  # each filter is one unbroken run of bins
        out.append({"first": first, "weights": [f32(v) for v in fb[first:last + 1, m]]})
    return out


FRONTEND_SIGNALS = [
    # name, samples, beats, seed (all at 22,050 Hz)
    ("drums_120_8s", 8 * 22050, steady_beats(0.5, 120, 7.75), 1),
    ("drums_128_odd_100003", 100003, steady_beats(0.1, 128, 4.3), 2),
    ("short_3001", 3001, [(0.01, True), (0.07, False)], 3),
    ("shortest_600", 600, [(0.0, True)], 4),
]


def frontend():
    spect = LogMelSpect()
    # The same steps in float64, with the Hann window computed in float64 too (cast from float32 it would move
    # near-silent bands by 2e-5); the mel filters stay torchaudio's float32 values, as in the package.
    spect64 = LogMelSpect().double()
    spect64.spect_class.spectrogram.window = torch.hann_window(1024, dtype=torch.float64)
    out = []
    for name, n, beats, seed in FRONTEND_SIGNALS:
        y = drum_pattern(22050, n, beats, seed)
        S = spect(torch.tensor(y)).numpy()  # frames x 128, float32
        S64 = spect64(torch.tensor(y.astype(np.float64))).numpy()
        frames = S.shape[0]
        assert frames == 1 + n // 441, (name, S.shape)
        pick = sorted(set(range(min(4, frames))) | set(range(frames // 2 - 2, frames // 2 + 3))
                      | set(range(max(0, frames - 4), frames)))
        pick = [t for t in pick if 0 <= t < frames]
        out.append({"name": name, "samples": n, "seed": seed, "beats": [[t, a] for t, a in beats],
                    "synth": synth_check(y),
                    "frames": frames, "index": pick, "values": [[f32(v) for v in S[t]] for t in pick],
                    "values64": [[float(v) for v in S64[t]] for t in pick],
                    "frame_sums": [float(np.sum(S[t].astype(np.float64))) for t in range(frames)],
                    "max": f32(S.max())})
        print(f"front end {name}: {n} samples, {frames} frames, largest value {S.max():.3f}", file=sys.stderr)
    return out


CHUNK_LENGTHS = [1, 12, 13, 700, 1488, 1489, 1494, 1495, 1500, 1501, 2976, 2983, 4501]


class StandIn(torch.nn.Module):
    """For spectrogram rows holding the piece's frame index f in bin 0 (zero rows for padding), returns at chunk
    position t: beat = 2048 f + t and downbeat = 2048 f - t, exact in float32 for these lengths."""

    def forward(self, x):
        t = torch.arange(x.shape[1], dtype=torch.float32)
        return {"beat": x[..., 0] * 2048 + t, "downbeat": x[..., 0] * 2048 - t}


def segments(values, frames):
    """beat[i] = 2049 i - s where frame i came from the chunk starting at s: runs of equal s as [first, end, s]."""
    s = [int(round(2049 * i - float(values[i]))) for i in range(frames)]
    out, a = [], 0
    for i in range(1, frames + 1):
        if i == frames or s[i] != s[a]:
            out.append([a, i, s[a]])
            a = i
    return out


def chunking():
    out = []
    for n in CHUNK_LENGTHS:
        spect = torch.zeros(n, 128)
        spect[:, 0] = torch.arange(n, dtype=torch.float32)
        chunks, starts = split_piece(spect, 1500, border_size=6, avoid_short_end=True)
        pads = []
        for c, s in zip(chunks, starts):
            s = int(s)
            left, right = max(0, -s), max(0, min(6, s + 1500 - n))
            assert c.shape[0] == min(s + 1500, n) - max(s, 0) + left + right
            pads.append([left, right, int(c.shape[0])])
        pred = split_predict_aggregate(spect, 1500, 6, "keep_first", StandIn())
        beat, down = pred["beat"].numpy(), pred["downbeat"].numpy()
        seg = segments(beat, n)
        for a, b, s in seg:  # the downbeat says the same: 2047 i + s
            assert all(float(down[i]) == 2047 * i + s for i in range(a, b)), (n, a, b, s)
        out.append({"frames": n, "starts": [int(s) for s in starts], "pads": pads, "segments": seg})
    return out


def postprocess(beat, downbeat):
    pp = Postprocessor(type="minimal", fps=50)
    b, d = pp(torch.tensor(beat, dtype=torch.float32), torch.tensor(downbeat, dtype=torch.float32))
    b, d = np.asarray(b, dtype=np.float64), np.asarray(d, dtype=np.float64)
    # The package returns seconds only. Its frame positions are whole or half frames (a group of tied neighbours is
    # at most two peaks), so they are recovered exactly, and checked: position / 50 gives back the very same time.
    bf, df = [round(float(v) * 100) / 2 for v in b], [round(float(v) * 100) / 2 for v in d]
    assert all(f / 50 == float(t) for f, t in zip(bf + df, list(b) + list(d)))
    return {"beats": [float(v) for v in b], "downbeats": [float(v) for v in d],
            "beat_frames": bf, "downbeat_frames": df}


def hand_made_logits():
    """Cases the minimal postprocessor has to get exactly right, as (name, beat logits, downbeat logits)."""
    cases = []
    z = [-5.0] * 40

    def at(base, pairs):
        x = list(base)
        for i, v in pairs:
            x[i] = v
        return x

    cases.append(("nothing_above_zero", at(z, [(10, 0.0), (20, -0.5)]), list(z)))
    cases.append(("edges", at(z, [(0, 2.0), (39, 3.0), (20, 1.0)]), at(z, [(0, 1.5), (39, -1.0)])))
    cases.append(("plateau_of_two", at(z, [(10, 2.0), (11, 2.0), (30, 1.0)]), at(z, [(10, 1.0), (11, 1.0)])))
    cases.append(("plateau_of_three", at(z, [(10, 2.0), (11, 2.0), (12, 2.0), (30, 1.0)]), list(z)))
    cases.append(("plateau_of_four", at(z, [(5, 1.0), (6, 1.0), (7, 1.0), (8, 1.0)]), list(z)))
    cases.append(("equal_peaks_3_apart", at(z, [(10, 2.0), (13, 2.0)]), list(z)))
    cases.append(("equal_peaks_2_apart", at(z, [(10, 2.0), (12, 2.0), (11, 1.0)]), list(z)))
    cases.append(("smaller_within_3", at(z, [(10, 2.0), (13, 1.9), (17, 1.8)]), list(z)))
    cases.append(("downbeat_between_beats", at(z, [(10, 2.0), (20, 2.0), (30, 2.0)]),
                  at(z, [(15, 1.0), (24, 1.0), (26, 1.0)])))
    cases.append(("downbeat_no_beats", list(z), at(z, [(12, 1.0)])))
    cases.append(("all_equal_positive", [1.0] * 12, [1.0] * 12))
    # Random logits: smooth bumps plus noise, so ties are rare but near-misses are common.
    rng = np.random.default_rng(7)
    for r in range(3):
        n = 400
        base = -6.0 + 9.0 * np.maximum(0.0, np.cos(2 * np.pi * np.arange(n) / rng.uniform(18, 30))) ** 8
        beat = (base + rng.normal(0, 0.8, n)).astype(np.float32)
        down = (base - 3.0 + rng.normal(0, 1.5, n)).astype(np.float32)
        cases.append((f"random_{r}", [float(v) for v in beat], [float(v) for v in down]))
    out = []
    for name, beat, down in cases:
        row = {"name": name, "beat": [f32(v) for v in beat], "downbeat": [f32(v) for v in down]}
        row.update(postprocess(row["beat"], row["downbeat"]))
        out.append(row)
    return out


PIECES = [
    # name, rate, seconds, beats, seed
    ("drums_120_30s_44k", 44100, 30, steady_beats(0.5, 120, 29.75), 11),
    ("drums_120_30s_22k", 22050, 30, steady_beats(0.5, 120, 29.75), 11),
    ("drums_120_30s_48k", 48000, 30, steady_beats(0.5, 120, 29.75), 11),
    ("drums_128_to_100_90s_44k", 44100, 90, tempo_change_beats(0.5, 128, 100, 45.0, 89.75), 12),
    ("drums_128_to_100_90s_22k", 22050, 90, tempo_change_beats(0.5, 128, 100, 45.0, 89.75), 12),
]


def pieces(model):
    out = []
    for name, rate, seconds, beats, seed in PIECES:
        y = drum_pattern(rate, seconds * rate, beats, seed)
        t0 = time.time()
        with torch.inference_mode():
            beat, down = model(y, rate)
        beat, down = beat.numpy(), down.numpy()
        row = {"name": name, "rate": rate, "seconds": seconds, "seed": seed,
               "true_beats": [[t, a] for t, a in beats], "synth": synth_check(y), "frames": int(len(beat)),
               "beat_logits": [f32(v) for v in beat], "downbeat_logits": [f32(v) for v in down]}
        row.update(postprocess(row["beat_logits"], row["downbeat_logits"]))
        out.append(row)
        print(f"{name}: {len(beat)} frames, {len(row['beats'])} beats, {len(row['downbeats'])} downbeats "
              f"({time.time() - t0:.1f} s)", file=sys.stderr)
    return out


def main():
    versions = {k: md.version(k) for k in ["beat_this", "torch", "torchaudio", "soxr", "numpy"]}
    print("versions:", versions, file=sys.stderr)
    torch.set_num_threads(max(1, os.cpu_count() or 1))
    model = Audio2Frames(checkpoint_path="final0", device="cpu")
    fx = {"versions": versions, "checkpoint": "final0", "fps": 50,
          "filterbank": filterbank(), "frontend": frontend(), "chunking": chunking(),
          "postprocessor": hand_made_logits(), "pieces": pieces(model)}

    if "--time" in sys.argv[1:]:
        # Four minutes, for comparison with the Swift timing (not stored: it depends on the machine).
        beats = steady_beats(0.5, 128, 239.75)
        y = drum_pattern(44100, 240 * 44100, beats, 13)
        t0 = time.time()
        with torch.inference_mode():
            beat, down = model(y, 44100)
        t1 = time.time()
        postprocess([f32(v) for v in beat.numpy()], [f32(v) for v in down.numpy()])
        print(f"four minutes at 44.1 kHz: resampling, spectrogram and model {t1 - t0:.2f} s, postprocessing "
              f"{time.time() - t1:.2f} s, {torch.get_num_threads()} threads", file=sys.stderr)

    with open(OUT, "w") as f:
        json.dump(fx, f, separators=(",", ":"))
        f.write("\n")
    print(f"wrote {OUT} ({os.path.getsize(OUT):,} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
