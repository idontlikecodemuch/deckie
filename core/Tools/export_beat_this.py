#!/usr/bin/env python3
"""Export the Beat This! beat tracker's network to ONNX, for DeckieInference's BeatTracker, and check the export.

  python3 core/Tools/export_beat_this.py [--out PATH] [--opset N]     # from anywhere

A development-time tool: it never ships, and nothing in core/ runs it at build or analysis time. It needs the Python
packages below (pinned in DEPENDENCIES.md, section 6, with the commands that install them), and the network once, for
the checkpoint.

What it does:
  1. Loads the "final0" checkpoint through the package's own loader (beat_this.inference.load_model), which downloads
     it once from the authors' file share into torch's hub cache (~/.cache/torch/hub/checkpoints/beat_this-final0.ckpt)
     and reads it with weights_only=True (plain tensors, no pickled code). The file's SHA-256 must be CHECKPOINT_SHA256
     below, or the script stops before exporting anything.
  2. Exports the network alone: a log-mel spectrogram in ("spect", float32, shape 1 x T x 128, T frames at 50 per
     second), beat and downbeat logits out ("beat" and "downbeat", float32, shape 1 x T), with T dynamic. The
     spectrogram, the splitting of long pieces into chunks and the peak picking stay outside the model; Deckie's
     Swift port does them (BeatThisFrontEnd, BeatThisChunking, BeatThisPostProcessor).
     One change is made before export, and it does not change any number: the rotary position embedding
     (rotary_embedding_torch) keeps a cache of its angles that the exporter would freeze as a constant filled only
     up to the example length, so the cache is switched off and the angles are computed from the sequence length
     inside the graph. The check below compares against the unmodified model.
  3. Checks the ONNX file with ONNX Runtime against PyTorch on random spectrograms of several lengths (including
     the 1,500-frame chunks the package feeds the model and lengths it was not exported with) and prints the
     largest difference in the logits.
  4. Writes the file (default core/.models/beat_this_final0.onnx, kept out of git) and prints its SHA-256 and size,
     with a note whether it matches ONNX_SHA256, the export recorded in DEPENDENCIES.md. A different hash is not an
     error by itself (another PyTorch version serialises differently); the numerical check is what must pass.
"""
import argparse, hashlib, importlib.metadata as md, os, sys, tempfile, time, warnings

import numpy as np
import torch

from beat_this.inference import CHECKPOINT_URL, load_model
from beat_this.preprocessing import LogMelSpect
from rotary_embedding_torch import RotaryEmbedding
import onnxruntime as ort

# The tracer warns that the batch size (1) and a few shape checks become constants in the graph; that is intended:
# the graph takes one spectrogram at a time, and only its length varies.
warnings.filterwarnings("ignore", category=torch.jit.TracerWarning)
# torch 2.9 and later call the TorchScript-based exporter used here "legacy" (their default needs the onnxscript
# package as well). It is what this export was made and checked with; DEPENDENCIES.md says what to do if it goes.
warnings.filterwarnings("ignore", message=".*legacy TorchScript-based ONNX export.*")

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(CORE, ".models", "beat_this_final0.onnx")

CHECKPOINT = "final0"
CHECKPOINT_FILE_URL = f"{CHECKPOINT_URL}/{CHECKPOINT}.ckpt"
CHECKPOINT_SHA256 = "8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331"
# The export recorded in DEPENDENCIES.md: beat_this 1.1.0, torch 2.15.0+cpu, onnx 1.23.2, opset 17.
ONNX_SHA256 = "f1d932049c9344ae3b1192673ef895c97807ba59fc1aa3d4e8d3d17c43c9b8dc"

SPECT_BINS = 128
CHECK_LENGTHS = [1500, 1512, 1000, 377, 13]  # 1500: the package's chunk; the others: lengths not seen at export
TOLERANCE = 2e-3  # largest allowed |ONNX - PyTorch| in a logit; float32 kernels differ in summation order


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def click_track_spect():
    """The package's own log-mel spectrogram of 30 s of a plain click track at 120 BPM (a 60 Hz thump and a click
    every half second, louder every fourth), cut to 1,500 frames: shape 1 x 1500 x 128."""
    sr, n = 22050, 30 * 22050
    y = np.zeros(n)
    for k, start in enumerate(np.arange(0.5, 30, 0.5)):
        i = int(round(start * sr))
        j = np.arange(n - i) / sr
        gain = 1.0 if k % 4 == 0 else 0.5
        y[i:] += gain * np.exp(-j / 0.08) * np.sin(2 * np.pi * 60 * j)
        y[i:i + 64] += gain * 0.5 * np.hanning(64)
    spect = LogMelSpect()(torch.tensor(y, dtype=torch.float32))
    return spect[:1500].unsqueeze(0)


class LogitsOnly(torch.nn.Module):
    """The network with its dictionary output turned into the two tensors the ONNX graph returns."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, spect):
        out = self.model(spect)
        return out["beat"], out["downbeat"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=DEFAULT_OUT, help="where to write the ONNX file (default: %(default)s)")
    ap.add_argument("--opset", type=int, default=17, help="ONNX opset (default: %(default)s)")
    args = ap.parse_args()

    versions = {name: md.version(name) for name in
                ["beat_this", "torch", "torchaudio", "einops", "rotary-embedding-torch", "onnx", "onnxruntime", "numpy"]}
    print("versions:", ", ".join(f"{k} {v}" for k, v in versions.items()))
    print(f"python {sys.version.split()[0]}, opset {args.opset}")

    # 1. The checkpoint, through the package's loader (downloads on first use), then checked by hash.
    torch.manual_seed(0)
    reference = load_model(CHECKPOINT, "cpu")
    ckpt_path = os.path.join(torch.hub.get_dir(), "checkpoints", f"beat_this-{CHECKPOINT}.ckpt")
    got = sha256(ckpt_path)
    print(f"checkpoint: {CHECKPOINT_FILE_URL}")
    print(f"  file {ckpt_path}, {os.path.getsize(ckpt_path):,} bytes, SHA-256 {got}")
    if got != CHECKPOINT_SHA256:
        sys.exit(f"export_beat_this: checkpoint SHA-256 is {got}, expected {CHECKPOINT_SHA256}; not exporting")
    params = sum(p.numel() for p in reference.parameters())
    print(f"  {params:,} parameters")

    # 2. A second copy with the rotary cache off, exported with a dynamic time axis.
    model = load_model(CHECKPOINT, "cpu")
    rotaries = [m for m in model.modules() if isinstance(m, RotaryEmbedding)]
    for m in rotaries:
        m.cache_if_possible = False
    print(f"  rotary embeddings with the cache switched off: {len(rotaries)}")
    net = LogitsOnly(model).eval()

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".onnx", dir=os.path.dirname(out))
    os.close(fd)
    try:
        example = torch.rand(1, 1500, SPECT_BINS) * 6
        t0 = time.time()
        with torch.no_grad():
            torch.onnx.export(
                net, (example,), tmp, dynamo=False, opset_version=args.opset, do_constant_folding=True,
                input_names=["spect"], output_names=["beat", "downbeat"],
                dynamic_axes={"spect": {1: "time"}, "beat": {1: "time"}, "downbeat": {1: "time"}},
            )
        print(f"exported in {time.time() - t0:.1f} s")

        # 3. ONNX Runtime against the unmodified PyTorch model.
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess = ort.InferenceSession(tmp, so, providers=["CPUExecutionProvider"])
        print("inputs:", [(i.name, i.shape, i.type) for i in sess.get_inputs()])
        print("outputs:", [(o.name, o.shape, o.type) for o in sess.get_outputs()])
        g = torch.Generator().manual_seed(1)
        cases = [(f"random, T = {n}", torch.rand(1, n, SPECT_BINS, generator=g) * 6) for n in CHECK_LENGTHS]
        cases.append(("click track, T = 1500", click_track_spect()))
        worst = 0.0
        for name, x in cases:
            # Random values span what log1p(1000 x magnitude) gives (0 to about 8); the click track gives the
            # network something to be sure about, so its logits reach their working range.
            with torch.no_grad():
                want = reference(x)
            beat, downbeat = sess.run(None, {"spect": x.numpy()})
            db = float(np.max(np.abs(beat - want["beat"].numpy())))
            dd = float(np.max(np.abs(downbeat - want["downbeat"].numpy())))
            span = float(max(want["beat"].abs().max(), want["downbeat"].abs().max()))
            print(f"  {name:22s}: max |ONNX - torch| beat {db:.2e}, downbeat {dd:.2e} (largest |logit| {span:.1f})")
            worst = max(worst, db, dd)
        print(f"largest difference in a logit: {worst:.2e} (tolerance {TOLERANCE:.0e})")
        if not worst <= TOLERANCE:
            sys.exit("export_beat_this: ONNX Runtime and PyTorch disagree; not writing the file")

        os.replace(tmp, out)
        tmp = None
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
