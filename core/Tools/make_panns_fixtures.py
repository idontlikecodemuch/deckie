#!/usr/bin/env python3
"""Write the reference numbers DeckieInference's PANNs is checked against: the rows of PANNs' class list that Deckie
names, and what Python's ONNX Runtime gives for the exported model on the windows of a synthesised signal. Nothing
here runs at test time; the Swift tests read the JSON this writes.

  python3 -P core/Tools/make_panns_fixtures.py --source DIR [--model PATH]

Needs numpy and, for the model's numbers, onnxruntime (core/Tools/panns-export-requirements.txt; DEPENDENCIES.md,
section 9); no torch: the front end is inside the exported graph. --source is the folder core/Tools/fetch-panns.sh
--keep-source leaves (core/.models/panns-source), whose class_labels_indices.csv is checked against the SHA-256
export_panns.py pins; --model is the exported model (default core/.models/panns_mobilenetv2.onnx). Without a model
file the "model" entry is null, and the Swift test that compares against it says so and skips.

The signal is synthesised at 32 kHz by a closed-form recipe the Swift test repeats operation for operation
(Tests/DeckieInferenceTests/PANNsTests.swift, `PANNsFixtureSignal`): an A minor chord of harmonic tones, a sung-like
tone with vibrato, and a decaying click every half second, in float64 rounded to float32, so both sides feed the same
samples (up to the last bit of a sine, which float32 rounding almost always hides). It is cut into windows as the
Swift code cuts it (2 s every 0.48 s, the last zero-padded), which the test checks as well.

Output: core/Tests/DeckieInferenceTests/Fixtures/panns.json
  source_commit, class_list_sha256   where the class list came from
  classes     the named classes as the list has them, [index, name], for every class PANNsClass names and every
              class VocalReadings asks for
  model       the model's SHA-256 (the export it was made with; another export of the same checkpoint gives the same
              numbers), the signal's length, the window count, and per window the 527 scores and 1,024 embedding
              values, rounded to 7 decimals
"""
import argparse, csv, hashlib, json, math, os, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
OUT = os.path.join(CORE, "Tests", "DeckieInferenceTests", "Fixtures", "panns.json")
DEFAULT_MODEL = os.path.join(CORE, ".models", "panns_mobilenetv2.onnx")
SOURCE_COMMIT = "d2f4b8c18eab44737fcc0de1248ae21eb43f6aa4"
CLASS_LIST_SHA256 = "cdd1049833c4b86127c2773ac0d14a2754b6a6d0d1798002ed5c66e699708429"
RATE, WINDOW, HOP = 32000, 64000, 15360
SAMPLES = 96000  # 3 s: four windows, the last three reaching past the end
# PANNsClass's names, and the class names VocalReadings asks for (its three lists, in AudioSet's spelling).
NAMED = ["Speech", "Singing", "Choir", "Yodeling", "Chant", "Mantra", "Male singing", "Female singing",
         "Child singing", "Synthetic singing", "Rapping", "Humming", "Music", "Musical instrument", "Vocal music",
         "A capella"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def signal(n=SAMPLES):
    """The fixture signal (PANNsFixtureSignal in the Swift test): per sample i at t = i / 32000, in float64,
    0.08 / h sin(2 pi f h t) for the chord's notes f (A3, C4, E4) and harmonics h = 1 ... 4; a tone at 262 Hz with a
    vibrato of 3 % at 5.5 Hz (phase 2 pi f0 t - (f0 0.03 / 5.5) cos(2 pi 5.5 t)), harmonics h = 1 ... 8 at 0.12 / h;
    and a click every 0.5 s from 0.25 s, 0.5 exp(-d / 0.01) sin(2 pi 1500 d) for d seconds after it; then float32."""
    t = np.arange(n, dtype=np.float64) / RATE
    y = np.zeros(n)
    for f in (220.0, 261.6255653005986, 329.6275569128699):
        for h in range(1, 5):
            y += 0.08 / h * np.sin(2.0 * math.pi * f * h * t)
    f0, depth, vib = 262.0, 0.03, 5.5
    phi = 2.0 * math.pi * f0 * t - (f0 * depth / vib) * np.cos(2.0 * math.pi * vib * t)
    for h in range(1, 9):
        y += 0.12 / h * np.sin(h * phi)
    d = np.mod(t - 0.25, 0.5)
    y += np.where(t >= 0.25, 0.5 * np.exp(-d / 0.01) * np.sin(2.0 * math.pi * 1500.0 * d), 0.0)
    return y.astype(np.float32)


def windows(y):
    """As DeckieInference's PANNs cuts them: 2 s every 0.48 s, enough for the last to reach the end, zero-padded."""
    count = 1 if len(y) <= WINDOW else 1 + (len(y) - WINDOW + HOP - 1) // HOP
    out = np.zeros((count, WINDOW), dtype=np.float32)
    for k in range(count):
        part = y[k * HOP:k * HOP + WINDOW]
        out[k, :len(part)] = part
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", required=True, help="folder with class_labels_indices.csv (fetch-panns.sh --keep-source)")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="the exported model (default: %(default)s)")
    args = ap.parse_args()

    path = os.path.join(args.source, "class_labels_indices.csv")
    got = sha256(path)
    if got != CLASS_LIST_SHA256:
        sys.exit(f"make_panns_fixtures: {path} has SHA-256 {got}, expected {CLASS_LIST_SHA256}")
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))[1:]
    by_name = {}
    for r in rows:
        by_name.setdefault(r[2], int(r[0]))
    missing = [n for n in NAMED if n not in by_name]
    if missing:
        sys.exit(f"make_panns_fixtures: the class list has no {missing}")
    classes = [[by_name[n], n] for n in NAMED]

    y = signal()
    w = windows(y)
    model = None
    if os.path.isfile(args.model):
        os.environ.setdefault("ORT_DISABLE_TELEMETRY", "1")
        import onnxruntime as ort
        sess = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
        scores, embeddings = sess.run(["scores", "embeddings"], {"waveform": w})
        model = {"sha256": sha256(args.model), "onnxruntime": ort.__version__, "samples": len(y), "windows": len(w),
                 "signal_sum": round(float(np.sum(y.astype(np.float64))), 6),
                 "scores": [round(float(v), 7) for v in scores.ravel()],
                 "embeddings": [round(float(v), 7) for v in embeddings.ravel()]}
        top = np.argsort(scores.mean(0))[::-1][:3]
        print(f"model {args.model}: {len(w)} windows; top classes by index {list(map(int, top))}")
    else:
        print(f"no model at {args.model}: the fixture's model entry is null")

    out = {"source_commit": SOURCE_COMMIT, "class_list_sha256": CLASS_LIST_SHA256, "classes": classes, "model": model}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")
    print(f"wrote {OUT}, {os.path.getsize(OUT):,} bytes")


if __name__ == "__main__":
    main()
