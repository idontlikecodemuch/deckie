#!/usr/bin/env python3
"""Export Google's YAMNet audio tagger to ONNX, for DeckieInference's vocal tagger, and check the export.

  python3 -P core/Tools/export_yamnet.py --weights yamnet.h5 --source DIR [--out PATH] [--opset N]

Normally run by core/Tools/fetch-vocal-models.sh, which downloads the two inputs by pinned URL and SHA-256 and then
calls this. A development-time tool: it never ships, and nothing in core/ runs it at build or analysis time. It needs
the Python packages pinned in core/Tools/yamnet-export-requirements.txt (TensorFlow's CPU build, tf-keras, tf2onnx,
ONNX Runtime, numpy; DEPENDENCIES.md, section 8), best in a virtual environment of its own: TensorFlow brings its own
protobuf, which other tools may not want.

Inputs:
  --weights  yamnet.h5, the Keras weights Google publishes for YAMNet (https://storage.googleapis.com/audioset/
             yamnet.h5, linked from the model's README in tensorflow/models); its SHA-256 must be WEIGHTS_SHA256.
  --source   a folder holding params.py, features.py and yamnet.py from tensorflow/models, research/audioset/yamnet,
             at the commit SOURCE_COMMIT (Apache 2.0); each file's SHA-256 must be the one in SOURCE_SHA256. They
             define the network the weights belong to and YAMNet's own feature code, which the check below runs.

What it does:
  1. Builds the network alone with the source's own `yamnet.yamnet()`: log-mel patches in ("patches", float32,
     shape N x 96 x 64: N patches of 96 frames of 10 ms, 64 mel bands, as YAMNet's feature code cuts them), the 521
     class scores (after the sigmoid, "scores", N x 521) and the 1,024-value embedding before the classifier
     ("embeddings", N x 1024) out, with N dynamic. The waveform-to-patches front end stays outside the model;
     Deckie's Swift port does it (DeckieCore's YAMNetFrontEnd), checked against features.py by
     core/Tools/make_yamnet_fixtures.py. Loads the weights into it by layer name.
  2. Converts it with tf2onnx (opset 17 by default) and renames the graph's input and outputs as above.
  3. Checks: the network built here against the source's whole waveform model (`yamnet_frames_model`, which runs
     features.py and the network in one graph) on four seconds of synthesised music, so the weights are known to be
     in the right places; then ONNX Runtime against TensorFlow on random patches at several batch sizes and on the
     music's patches. Prints the largest differences; refuses to write the file if any exceeds TOLERANCE.
  4. Writes the file (default core/.models/yamnet.onnx, kept out of git) and prints its SHA-256 and size, with a note
     whether it matches ONNX_SHA256, the export recorded in DEPENDENCIES.md. A different hash is not an error by
     itself (other tool versions serialise differently); the numerical check is what must pass.
"""
import argparse, hashlib, importlib.metadata as md, os, sys, tempfile, time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")  # TensorFlow's start-up chatter about CPU features and GPUs
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(CORE, ".models", "yamnet.onnx")

WEIGHTS_URL = "https://storage.googleapis.com/audioset/yamnet.h5"
WEIGHTS_SHA256 = "13c3308955bbfaef262f175ac9c40e47b134573a93984f009220dd7cc12a1744"
SOURCE_COMMIT = "a6e25e28dc8433dde6c1319186a41e6d81a03f2d"
SOURCE_SHA256 = {
    "params.py": "925bb1e62461016031f98aea09aeac28975dd516f5747513767de5d1b06b6145",
    "features.py": "e6cd53f81d072c7c43be4c7fff2b9dd0c5ccc7d64f2fbcfc85b44013d6d2ed5e",
    "yamnet.py": "7ef3df32b7ecb782490b5a04d7581a23cfcf701dbf476bc4d03deefe22cdb040",
}
# The export recorded in DEPENDENCIES.md: tensorflow-cpu 2.21.0, tf-keras 2.21.0, tf2onnx 1.17.0, onnx 1.23.2,
# onnxruntime 1.31.1, numpy 2.5.4, protobuf 7.36.2, Python 3.13, opset 17; 14,938,528 bytes. The same tools gave the
# same bytes on repeated runs.
ONNX_SHA256 = "96bb0dc54745dbbc95ef3f289830c94eec92a6914c4ab711a821bc8aa1c93cfd"

PATCH_FRAMES, MEL_BANDS, CLASSES, EMBEDDING = 96, 64, 521, 1024
CHECK_BATCHES = [1, 7, 33]
TOLERANCE = 1e-4  # largest allowed |ONNX - TensorFlow| in a score, and relative to the largest embedding value
RATE = 16000


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def music(seconds=4.0):
    """Four seconds at 16 kHz: a kick and hi-hat at 124 BPM, an A minor chord, and a sung-like line (a harmonic tone
    at 220 to 330 Hz with vibrato); something for the network to recognise, so its scores are not all near zero."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    y = np.zeros(n)
    beat = 60 / 124
    for b in np.arange(0.1, seconds, beat):
        i = int(b * RATE)
        k = np.arange(min(int(0.25 * RATE), n - i)) / RATE
        y[i:i + len(k)] += 0.6 * np.exp(-k / 0.12) * np.sin(2 * np.pi * (45 * k + 3.15 * (1 - np.exp(-k / 0.03))))
    rng = np.random.default_rng(5)
    for b in np.arange(0.1 + beat / 2, seconds, beat):
        i = int(b * RATE)
        m = min(int(0.05 * RATE), n - i)
        y[i:i + m] += 0.1 * np.exp(-np.arange(m) / RATE / 0.015) * np.diff(rng.uniform(-1, 1, m + 1))
    for midi in (57, 60, 64):
        f = 440 * 2 ** ((midi - 69) / 12)
        for h in range(1, 5):
            y += 0.04 / h * np.sin(2 * np.pi * f * h * t)
    f0 = np.where(t % 1.0 < 0.5, 220.0, 330.0) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    for h in range(1, 12):
        y += 0.06 / h * (1 + 2 * np.exp(-((h * 275 - 700) / 300) ** 2)) * np.sin(h * phase)
    return (0.5 * y / np.max(np.abs(y))).astype(np.float32)


def rename_io(model_proto, renames):
    """Renames graph inputs and outputs (tf2onnx names them after TensorFlow's tensors) everywhere they appear."""
    g = model_proto.graph
    for value in list(g.input) + list(g.output):
        if value.name in renames:
            value.name = renames[value.name]
    for node in g.node:
        node.input[:] = [renames.get(x, x) for x in node.input]
        node.output[:] = [renames.get(x, x) for x in node.output]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--weights", required=True, help="yamnet.h5 (SHA-256 checked)")
    ap.add_argument("--source", required=True, help="folder with params.py, features.py, yamnet.py (SHA-256 checked)")
    ap.add_argument("--out", default=DEFAULT_OUT, help="where to write the ONNX file (default: %(default)s)")
    ap.add_argument("--opset", type=int, default=17, help="ONNX opset (default: %(default)s)")
    args = ap.parse_args()

    # 0. The inputs, by hash, before anything of theirs is imported or read.
    got = sha256(args.weights)
    print(f"weights: {args.weights}, {os.path.getsize(args.weights):,} bytes, SHA-256 {got}")
    if got != WEIGHTS_SHA256:
        sys.exit(f"export_yamnet: weights SHA-256 is {got}, expected {WEIGHTS_SHA256} ({WEIGHTS_URL}); not exporting")
    source = os.path.abspath(args.source)
    for name, want in SOURCE_SHA256.items():
        path = os.path.join(source, name)
        if not os.path.isfile(path):
            sys.exit(f"export_yamnet: {path} is missing (tensorflow/models {SOURCE_COMMIT}, research/audioset/yamnet)")
        got = sha256(path)
        if got != want:
            sys.exit(f"export_yamnet: {path} has SHA-256 {got}, expected {want}; not exporting")
    print(f"source: tensorflow/models {SOURCE_COMMIT}, research/audioset/yamnet: "
          + ", ".join(SOURCE_SHA256) + " match their hashes")

    import tensorflow as tf
    import tf_keras
    import tf2onnx
    import onnx
    import onnxruntime as ort
    sys.path.insert(0, source)
    import params as yamnet_params
    import yamnet as yamnet_model
    import features as yamnet_features

    versions = {name: md.version(name) for name in
                ["tensorflow-cpu", "tf-keras", "tf2onnx", "onnx", "onnxruntime", "numpy", "protobuf"]}
    print("versions:", ", ".join(f"{k} {v}" for k, v in versions.items()))
    print(f"python {sys.version.split()[0]}, opset {args.opset}")
    P = yamnet_params.Params()
    assert (P.patch_frames, P.patch_bands, P.num_classes) == (PATCH_FRAMES, MEL_BANDS, CLASSES), P

    # 1. The whole waveform model, as the source defines it, for the reference; then the network alone.
    frames_model = yamnet_model.yamnet_frames_model(P)
    frames_model.load_weights(args.weights)
    patches_in = tf_keras.layers.Input(shape=(PATCH_FRAMES, MEL_BANDS), dtype=tf.float32, name="patches")
    scores, embeddings = yamnet_model.yamnet(patches_in, P)
    net = tf_keras.Model(inputs=patches_in, outputs=[scores, embeddings], name="yamnet_patches")
    # The same function built both, so their layers holding weights come in the same order; copy them across,
    # checking that each pair has the same name (less Keras's numbering of repeated names) and shapes.
    src_layers = [l for l in frames_model.layers if l.weights]
    dst_layers = [l for l in net.layers if l.weights]
    if len(src_layers) != len(dst_layers):
        sys.exit(f"export_yamnet: {len(src_layers)} weighted layers in the source's model, {len(dst_layers)} here")
    base = lambda name: name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
    for s, d in zip(src_layers, dst_layers):
        sw = s.get_weights()
        if base(s.name) != base(d.name) or [w.shape for w in sw] != [w.shape for w in d.get_weights()]:
            sys.exit(f"export_yamnet: layer {s.name} does not match {d.name}")
        d.set_weights(sw)
    weights = sum(int(np.prod(w.shape)) for w in net.weights)
    print(f"network: {len(dst_layers)} layers with weights, {weights:,} values (incl. batch-norm statistics)")

    # The network against the whole model on the source's own features of synthesised music.
    y = music()
    want_scores, want_emb, log_mel = (t.numpy() for t in frames_model(y))
    padded = yamnet_features.pad_waveform(tf.constant(y), P)
    _, patches = yamnet_features.waveform_to_log_mel_spectrogram_patches(padded, P)
    patches = patches.numpy()
    got_scores, got_emb = (t.numpy() for t in net(patches))
    d_build = max(float(np.max(np.abs(got_scores - want_scores))), float(np.max(np.abs(got_emb - want_emb))))
    print(f"  {len(patches)} patches of synthesised music: the network built here against the source's waveform "
          f"model, largest difference {d_build:.2e}; top class {int(np.argmax(want_scores.mean(0)))}")
    if d_build > 1e-5:
        sys.exit("export_yamnet: the network built here does not match the source's model; weights misplaced?")

    # 2. tf2onnx, from a function with a dynamic patch count.
    @tf.function(input_signature=[tf.TensorSpec([None, PATCH_FRAMES, MEL_BANDS], tf.float32, name="patches")])
    def core(x):
        s, e = net(x, training=False)
        return s, e

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".onnx", dir=os.path.dirname(out))
    os.close(fd)
    try:
        t0 = time.time()
        proto, _ = tf2onnx.convert.from_function(core, input_signature=core.input_signature, opset=args.opset)
        g = proto.graph
        rename_io(proto, {g.input[0].name: "patches", g.output[0].name: "scores", g.output[1].name: "embeddings"})
        for value in [g.input[0], g.output[0], g.output[1]]:
            value.type.tensor_type.shape.dim[0].dim_param = "n"  # tf2onnx calls the dynamic axis unk__<number>
        proto.producer_name = "deckie export_yamnet.py (tf2onnx " + versions["tf2onnx"] + ")"
        del proto.metadata_props[:]
        for k, v in [("model", "YAMNet (Google), tensorflow/models research/audioset/yamnet"),
                     ("weights", WEIGHTS_URL + " sha256 " + WEIGHTS_SHA256),
                     ("source_commit", SOURCE_COMMIT), ("licence", "Apache-2.0"),
                     ("training_data", "AudioSet (Google); labels CC BY 4.0")]:
            entry = proto.metadata_props.add()
            entry.key, entry.value = k, v
        onnx.checker.check_model(proto)
        onnx.save(proto, tmp)
        print(f"converted in {time.time() - t0:.1f} s")

        # 3. ONNX Runtime against TensorFlow.
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess = ort.InferenceSession(tmp, so, providers=["CPUExecutionProvider"])
        print("inputs:", [(i.name, i.shape, i.type) for i in sess.get_inputs()])
        print("outputs:", [(o.name, o.shape, o.type) for o in sess.get_outputs()])
        assert [i.name for i in sess.get_inputs()] == ["patches"]
        assert [o.name for o in sess.get_outputs()] == ["scores", "embeddings"]
        rng = np.random.default_rng(1)
        # Random values span what log(mel + 0.001) gives: about -6.9 for silence to a few units for loud audio.
        cases = [(f"random, N = {n}", rng.uniform(-7, 3, (n, PATCH_FRAMES, MEL_BANDS)).astype(np.float32))
                 for n in CHECK_BATCHES]
        cases.append((f"music, N = {len(patches)}", patches.astype(np.float32)))
        worst = 0.0
        for name, x in cases:
            ts, te = (t.numpy() for t in net(x))
            os_, oe = sess.run(["scores", "embeddings"], {"patches": x})
            ds = float(np.max(np.abs(os_ - ts)))
            de = float(np.max(np.abs(oe - te))) / max(1.0, float(np.max(np.abs(te))))
            print(f"  {name:16s}: max |ONNX - TF| scores {ds:.2e}, embeddings {de:.2e} (relative to their largest "
                  f"value, {float(np.max(np.abs(te))):.2f}); largest score {float(np.max(ts)):.3f}")
            worst = max(worst, ds, de)
        print(f"largest difference: {worst:.2e} (tolerance {TOLERANCE:.0e})")
        if not worst <= TOLERANCE:
            sys.exit("export_yamnet: ONNX Runtime and TensorFlow disagree; not writing the file")

        os.replace(tmp, out)
        tmp = None
        os.chmod(out, 0o644)  # mkstemp made it readable by its owner only
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.remove(tmp)

    # 4. The file and its fingerprint.
    digest = sha256(out)
    print(f"wrote {out}, {os.path.getsize(out):,} bytes, SHA-256 {digest}")
    if digest == ONNX_SHA256:
        print("  identical to the export recorded in DEPENDENCIES.md")
    else:
        print(f"  differs from the export recorded in DEPENDENCIES.md ({ONNX_SHA256}); check the versions above")


if __name__ == "__main__":
    main()
