#!/usr/bin/env python3
"""Write the reference numbers YAMNet's Swift port is checked against: what YAMNet's own feature code computes
(tensorflow/models, research/audioset/yamnet, features.py, run in TensorFlow) and what Python's ONNX Runtime gives for
the exported network on those features. Nothing here runs at test time; the Swift tests read the JSON this writes.

  python3 -P core/Tools/make_yamnet_fixtures.py --source DIR [--model PATH]

Needs the packages of core/Tools/yamnet-export-requirements.txt (DEPENDENCIES.md, section 8), the YAMNet source files
at the commit export_yamnet.py pins (--source; core/Tools/fetch-vocal-models.sh --keep-source leaves them in
core/.models/yamnet-source), and the exported model (--model, default core/.models/yamnet.onnx).

The test signals are synthesised by a recipe the Swift tests repeat operation for operation (Tests/DeckieCoreTests/
YAMNetFrontEndTests.swift, with DeckieTestSupport's DrumPattern and ChordSynth): the drum pattern and chord recipes of
make_beat_fixtures.py and make_dsp_fixtures.py at 16 kHz, plus a harmonic tone with vibrato whose phase is written
in closed form, so both sides compute the same float32 samples (up to the last bit of a sine, which float32 rounding
almost always hides).

Output: core/Tests/DeckieCoreTests/Fixtures/yamnet.json
  mel       TensorFlow's linear_to_mel_weight_matrix with YAMNet's settings (64 bands, 257 bins, 16 kHz, 125 to
            7,500 Hz): every nonzero weight as [bin, band, weight]
  signals   per signal: its length, a check of its samples, YAMNet's patch and frame counts, and the whole log-mel
            spectrogram features.py computes (after its padding), each value rounded to 6 decimals
  model     the exported model's SHA-256, and ONNX Runtime's scores (521 per patch) and embeddings (1,024 per patch)
            for the patches of the first signal, cut from the spectrogram as stored (so the Swift test feeds the
            network exactly these numbers)
"""
import argparse, hashlib, importlib.metadata as md, json, math, os, sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
OUT = os.path.join(CORE, "Tests", "DeckieCoreTests", "Fixtures", "yamnet.json")
DEFAULT_MODEL = os.path.join(CORE, ".models", "yamnet.onnx")
RATE = 16000
GOLDEN, M1, M2 = 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def splitmix(seed, n):
    """The first n outputs of SplitMix64 started at state `seed`, as uniform values in [0, 1)."""
    with np.errstate(over="ignore"):
        z = np.uint64(seed) + (np.arange(1, n + 1, dtype=np.uint64) * np.uint64(GOLDEN))
        z = (z ^ (z >> np.uint64(30))) * np.uint64(M1)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(M2)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) * 2.0 ** -53


def steady_beats(first, bpm, end):
    out, k = [], 0
    while True:
        t = first + k * (60.0 / bpm)
        if t >= end:
            return [(t, i % 4 == 0) for i, t in enumerate(out)]
        out.append(t)
        k += 1


def onset(t, rate):
    return int(math.floor(t * rate + 0.5))


def drum_pattern(rate, n, beats, seed):
    """make_beat_fixtures.py's drum_pattern (DrumPattern.render in Swift)."""
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


def chords(sr, n, chord_list, harmonics, noise, seed):
    """make_dsp_fixtures.py's synth (ChordSynth.render in Swift, exact)."""
    i = np.arange(n, dtype=np.float64)
    y = np.zeros(n)
    ramp = int(0.01 * sr)
    for a, b, notes in chord_list:
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


def vibrato_tone(n, f0=262.0, depth=0.03, rate_hz=5.5, harmonics=6):
    """sum over h of (0.1 / h) sin(h phi(t)), phi(t) = 2 pi f0 t - (f0 depth / rate_hz) cos(2 pi rate_hz t): a tone
    whose frequency swings f0 (1 +- depth) at rate_hz, with its phase in closed form."""
    t = np.arange(n, dtype=np.float64) / RATE
    phi = 2.0 * math.pi * f0 * t - (f0 * depth / rate_hz) * np.cos(2.0 * math.pi * rate_hz * t)
    y = np.zeros(n)
    for h in range(1, harmonics + 1):
        y += (0.1 / h) * np.sin(h * phi)
    return y


AM = [45, 57, 60, 64]


def signal(n):
    """Drums at 124 BPM from 0.1 s, an A minor chord, a vibrato tone at 262 Hz: float32."""
    d = drum_pattern(RATE, n, steady_beats(0.1, 124.0, n / RATE), 7).astype(np.float64)
    c = chords(RATE, n, [(0, n, AM)], 5, 0.002, 11)
    v = vibrato_tone(n)
    return ((d + 0.25 * c) + v).astype(np.float32)


SIGNALS = [("music_2s", 2 * RATE), ("short_0.4s", int(0.4 * RATE))]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", required=True, help="folder with YAMNet's params.py and features.py")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="the exported model (default: %(default)s)")
    args = ap.parse_args()

    import tensorflow as tf
    os.environ.setdefault("ORT_DISABLE_TELEMETRY", "1")  # official ONNX Runtime builds report usage to Microsoft otherwise
    import onnxruntime as ort
    sys.path.insert(0, os.path.abspath(args.source))
    import params as yamnet_params
    import features as yamnet_features
    P = yamnet_params.Params()

    versions = {name: md.version(name) for name in ["tensorflow-cpu", "onnxruntime", "numpy"]}
    print("versions:", versions)

    mel = tf.signal.linear_to_mel_weight_matrix(num_mel_bins=P.mel_bands, num_spectrogram_bins=257,
                                                sample_rate=P.sample_rate, lower_edge_hertz=P.mel_min_hz,
                                                upper_edge_hertz=P.mel_max_hz).numpy()
    mel_entries = [[int(k), int(m), float(mel[k, m])] for k, m in zip(*np.nonzero(mel))]
    print(f"mel matrix {mel.shape}, {len(mel_entries)} nonzero weights")

    signals = []
    stored = {}
    for name, n in SIGNALS:
        y = signal(n)
        padded = yamnet_features.pad_waveform(tf.constant(y), P)
        log_mel, patches = yamnet_features.waveform_to_log_mel_spectrogram_patches(padded, P)
        log_mel, patches = log_mel.numpy(), patches.numpy()
        rounded = np.round(log_mel.astype(np.float64), 6)
        stored[name] = rounded
        signals.append({
            "name": name, "samples": n, "sample_sum": float(np.sum(y.astype(np.float64))),
            "first_samples": [float(v) for v in y[:8]], "padded": int(padded.shape[0]),
            "frames": int(log_mel.shape[0]), "patches": int(patches.shape[0]),
            "log_mel": [float(v) for v in rounded.ravel()],
        })
        print(f"{name}: {n} samples, padded to {padded.shape[0]}, {log_mel.shape[0]} frames, {patches.shape[0]} patches, "
              f"log-mel from {log_mel.min():.3f} to {log_mel.max():.3f}")

    # The network on the first signal's patches, cut from the stored (rounded) spectrogram.
    first = stored[SIGNALS[0][0]]
    count = 1 + (first.shape[0] - 96) // 48
    x = np.stack([first[48 * k:48 * k + 96] for k in range(count)]).astype(np.float32)
    sess = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    scores, embeddings = sess.run(["scores", "embeddings"], {"patches": x})
    top = np.argsort(-scores.mean(axis=0))[:5]
    print(f"model {args.model}: {count} patches; top classes by mean score {[(int(i), round(float(scores[:, i].mean()), 3)) for i in top]}")
    model = {"sha256": sha256(args.model), "signal": SIGNALS[0][0], "patches": count,
             "scores": [float(v) for v in scores.ravel()], "embeddings": [float(v) for v in embeddings.ravel()]}

    out = {"versions": versions, "mel": mel_entries, "signals": signals, "model": model}
    with open(OUT, "w") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")
    print(f"wrote {OUT}, {os.path.getsize(OUT):,} bytes")


if __name__ == "__main__":
    main()
