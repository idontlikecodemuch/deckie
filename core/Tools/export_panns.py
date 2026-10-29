#!/usr/bin/env python3
"""Export PANNs' MobileNetV2 audio tagger to ONNX, for DeckieInference's second vocal opinion, and check the export.

  python3 -P core/Tools/export_panns.py --checkpoint MobileNetV2_mAP=0.383.pth --source DIR [--out PATH] [--opset N]

Normally run by core/Tools/fetch-panns.sh, which downloads the inputs by pinned URL and hash and then calls this. A
development-time tool: it never ships, and nothing in core/ runs it at build or analysis time. It needs the Python
packages pinned in core/Tools/panns-export-requirements.txt (PyTorch's CPU build, onnx, ONNX Runtime, numpy;
DEPENDENCIES.md, section 9). It does not need torchlibrosa or librosa (below).

Inputs:
  --checkpoint  MobileNetV2_mAP=0.383.pth, the trained MobileNetV2 of Kong et al.'s PANNs, from the authors' Zenodo
                record 3987831 (CHECKPOINT_URL, CC BY 4.0); its SHA-256 must be CHECKPOINT_SHA256 and its MD5
                CHECKPOINT_MD5 (Zenodo's own). Read with torch.load(weights_only=True): tensors only, no pickled code
                is run.
  --source      a folder holding pytorch/models.py's and pytorch/pytorch_utils.py's text as models.py and
                pytorch_utils.py, and metadata/class_labels_indices.csv, from github.com/qiuqiangkong/
                audioset_tagging_cnn at SOURCE_COMMIT (MIT); each file's SHA-256 must be the one in SOURCE_SHA256.

The front end. models.py builds its log-mel spectrogram with torchlibrosa's Spectrogram and LogmelFilterBank (and
SpecAugmentation, used in training only). This script does not install torchlibrosa: before models.py is imported it
provides a module of that name with the three classes written here from torchlibrosa's formulas (the parameter names
and shapes are torchlibrosa's, so the checkpoint loads into them strictly). That is possible because the front end is
itself a set of tensors the checkpoint carries: the short-time Fourier transform (STFT) is two 1-D convolutions whose
kernels are the cosine and sine rows of a 1,024-point discrete Fourier transform times a periodic Hann window
(spectrogram_extractor.stft.conv_real.weight and conv_imag.weight, 513 x 1 x 1,024), and the mel filter bank is a
513 x 64 matrix (logmel_extractor.melW, librosa's Slaney-style filters). The script computes both here as well and
prints how far the checkpoint's copies are from them; the graph uses the checkpoint's. The rest is plain arithmetic:
reflect padding of 512 samples at each end (center=True, pad_mode='reflect'), power = real^2 + imag^2, mel = power x
melW, log-mel = 10 log10(max(mel, amin)) - 10 log10(max(amin, ref)) with ref 1.0, amin 1e-10, top_db None. The
values are read from models.py's MobileNetV2 at the pinned commit (window 'hann', center, 'reflect', ref, amin,
top_db) and from its training and inference defaults (pytorch/inference.py, utils/config.py: 32,000 Hz, window
1,024, hop 320, 64 mel bins, 50 to 14,000 Hz), and checked again below against the source.

What it does:
  1. Checks the inputs by hash; builds MobileNetV2 from the source; loads the checkpoint into it, every tensor in
     its place.
  2. Exports the whole model, front end included: waveform in ("waveform", float32, n x samples, mono at 32 kHz,
     both axes free), the 527 class scores (after the sigmoid, "scores", n x 527) and the 1,024-value embedding
     ("embeddings", n x 1024) out. The network is fully convolutional with a global pooling at the end (mean over
     frequency, then max plus mean over time), so a window of any length gives one row; Deckie's Swift side cuts
     the audio into 2 s windows every 0.48 s (DeckieInference's PANNs) and resamples it to 32 kHz first.
  3. Checks ONNX Runtime against PyTorch on random audio in several batch sizes and lengths (2 s, 0.96 s, 10 s and an
     odd length) and on synthesised music; prints the largest differences, and the music's top classes (Music first,
     if the weights are in their places); refuses to write the file if any difference exceeds TOLERANCE.
  4. Writes the file (default core/.models/panns_mobilenetv2.onnx, kept out of git) and prints its SHA-256 and size,
     with a note whether it matches ONNX_SHA256. Until the first CI export is recorded, ONNX_SHA256 is a TODO and
     no comparison is made; a different hash is not an error by itself (other tool versions serialise differently),
     the numerical check is what must pass.
"""
import argparse, csv, hashlib, importlib.metadata as md, math, os, sys, tempfile, time, types, warnings

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(CORE, ".models", "panns_mobilenetv2.onnx")

CHECKPOINT_URL = "https://zenodo.org/records/3987831/files/MobileNetV2_mAP%3D0.383.pth?download=1"
# Downloaded Oct 29, 2026: 20,834,417 bytes. The MD5 is the one Zenodo's record gives for the file (DEPENDENCIES.md,
# section 9); both are checked.
CHECKPOINT_SHA256 = "22437af9eb5ed1854b5ad285b4a17d5fc566f1a3b23df40db5541f5705ca340f"
CHECKPOINT_MD5 = "838421a9262cce976aa247946d6e2983"
SOURCE_REPO = "qiuqiangkong/audioset_tagging_cnn"
SOURCE_COMMIT = "d2f4b8c18eab44737fcc0de1248ae21eb43f6aa4"
SOURCE_SHA256 = {
    "models.py": "7f9af440395ace5160bbb51d654a0dc35fb887fbf5edecb12da61ff6efb306d9",
    "pytorch_utils.py": "1464fcfbfc0fe4c55f690f6b39e1c80eeed5de1e7fd1b7fd30334d304de7dbe9",
    "class_labels_indices.csv": "cdd1049833c4b86127c2773ac0d14a2754b6a6d0d1798002ed5c66e699708429",
}
# The export to be recorded in DEPENDENCIES.md once CI has made it (torch 2.15.0+cpu, onnx 1.23.2, opset 17); the
# fetch scripts read this line. While it is the TODO, no export is called the recorded one and no hash is checked.
# (This container's export, Oct 29, 2026, Python 3.13, three runs alike: 20,715,598 bytes, SHA-256 54b6b2624bc0...;
# section 9.)
ONNX_SHA256 = "TODO-after-first-ci-export"

# The front end's values, as the export uses them; checked against models.py below.
RATE, WINDOW, HOP, MEL_BINS, FMIN, FMAX = 32000, 1024, 320, 64, 50, 14000
REF, AMIN, TOP_DB = 1.0, 1e-10, None
CLASSES, EMBEDDING = 527, 1024
# The classes DeckieInference's PANNs names (PANNsClass), by index, as the class list at SOURCE_COMMIT spells them;
# checked against the csv so that a new commit cannot move them silently.
NAMED_CLASSES = {
    0: "Speech", 27: "Singing", 28: "Choir", 29: "Yodeling", 30: "Chant", 31: "Mantra", 32: "Male singing",
    33: "Female singing", 34: "Child singing", 35: "Synthetic singing", 36: "Rapping", 37: "Humming", 137: "Music",
    138: "Musical instrument", 254: "Vocal music", 255: "A capella",
}
# Lengths in samples for the check: Deckie's 2 s window, YAMNet's 0.96 s patch, the 10 s clip PANNs was trained on,
# and an odd length; batch sizes for the 2 s window.
CHECK_LENGTHS = [64000, 30720, 320000, 47999]
CHECK_BATCHES = [1, 4, 9]
# Largest allowed |ONNX - PyTorch| in a score, and relative to the largest embedding value (the export here: 2.4e-6;
# the STFT in the graph is a 1,024-tap convolution whose float32 sums the two order differently).
TOLERANCE = 1e-4
FRONT_END_TOLERANCE = 1e-5  # how far the checkpoint's front-end tensors may be from the ones computed here
TODO = "TODO-after-first-ci-export"


def digest(path, kind):
    h = hashlib.new(kind)
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# --------------------------------------------------------------------------------------------- the front end
def hann_periodic(n):
    """The periodic Hann window of length n (scipy's get_window('hann', n, fftbins=True), which torchlibrosa uses)."""
    k = np.arange(n)
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * k / n)


def hz_to_mel(f):
    """librosa's Slaney mel scale (htk=False): linear below 1 kHz (3 mels per 200 Hz), logarithmic above."""
    f = np.asarray(f, dtype=np.float64)
    f_sp, min_log_hz = 200.0 / 3, 1000.0
    min_log_mel, logstep = min_log_hz / f_sp, math.log(6.4) / 27.0
    return np.where(f >= min_log_hz, min_log_mel + np.log(np.maximum(f, 1e-300) / min_log_hz) / logstep, f / f_sp)


def mel_to_hz(m):
    m = np.asarray(m, dtype=np.float64)
    f_sp, min_log_hz = 200.0 / 3, 1000.0
    min_log_mel, logstep = min_log_hz / f_sp, math.log(6.4) / 27.0
    return np.where(m >= min_log_mel, min_log_hz * np.exp(logstep * (m - min_log_mel)), f_sp * m)


def mel_filters(sr, n_fft, n_mels, fmin, fmax):
    """librosa.filters.mel(sr, n_fft, n_mels, fmin, fmax) with its defaults (htk=False, norm='slaney'): triangles
    between adjacent points of n_mels + 2 points evenly spaced in mels, each scaled to unit area (2 / width in Hz).
    Shape n_mels x (n_fft / 2 + 1)."""
    fftfreqs = np.linspace(0, sr / 2, 1 + n_fft // 2)
    mel_f = mel_to_hz(np.linspace(hz_to_mel(fmin), hz_to_mel(fmax), n_mels + 2))
    fdiff = np.diff(mel_f)
    ramps = mel_f[:, None] - fftfreqs[None, :]
    lower = -ramps[:-2] / fdiff[:-1, None]
    upper = ramps[2:] / fdiff[1:, None]
    weights = np.maximum(0, np.minimum(lower, upper))
    weights *= (2.0 / (mel_f[2:n_mels + 2] - mel_f[:n_mels]))[:, None]
    return weights


def dft_kernels(n_fft):
    """The STFT's two convolution kernels as torchlibrosa makes them: row k is cos(2 pi k t / n) w(t) and
    -sin(2 pi k t / n) w(t), w the periodic Hann window, k = 0 ... n/2; shape (n/2 + 1) x 1 x n each."""
    t = np.arange(n_fft)
    k = np.arange(n_fft // 2 + 1)
    angle = 2.0 * np.pi * ((k[:, None] * t[None, :]) % n_fft) / n_fft
    w = hann_periodic(n_fft)
    return (np.cos(angle) * w)[:, None, :], (-np.sin(angle) * w)[:, None, :]


def install_front_end():
    """Puts a module named torchlibrosa (with .stft and .augmentation) into sys.modules, providing the three classes
    models.py imports, written from torchlibrosa's formulas with its parameter names, so models.py imports unchanged
    and the checkpoint's front-end tensors load into them."""
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    class STFT(nn.Module):
        def __init__(self, n_fft, hop_length, win_length, window, center, pad_mode, freeze_parameters=True):
            super().__init__()
            assert window == "hann" and win_length == n_fft and pad_mode in ("reflect", "constant"), (window, pad_mode)
            self.n_fft, self.hop_length, self.center, self.pad_mode = n_fft, hop_length, center, pad_mode
            bins = n_fft // 2 + 1
            self.conv_real = nn.Conv1d(1, bins, kernel_size=n_fft, stride=hop_length, padding=0, bias=False)
            self.conv_imag = nn.Conv1d(1, bins, kernel_size=n_fft, stride=hop_length, padding=0, bias=False)
            real, imag = dft_kernels(n_fft)
            self.conv_real.weight.data = torch.tensor(real, dtype=torch.float32)
            self.conv_imag.weight.data = torch.tensor(imag, dtype=torch.float32)
            for p in self.parameters():
                p.requires_grad = False

        def forward(self, x):                       # x: batch x samples
            x = x[:, None, :]
            if self.center:
                x = F.pad(x, pad=(self.n_fft // 2, self.n_fft // 2), mode=self.pad_mode)
            real = self.conv_real(x)[:, None, :, :].transpose(2, 3)   # batch x 1 x frames x bins
            imag = self.conv_imag(x)[:, None, :, :].transpose(2, 3)
            return real, imag

    class Spectrogram(nn.Module):
        def __init__(self, n_fft=2048, hop_length=None, win_length=None, window="hann", center=True,
                     pad_mode="reflect", power=2.0, freeze_parameters=True):
            super().__init__()
            assert power == 2.0, power
            self.stft = STFT(n_fft, hop_length, win_length or n_fft, window, center, pad_mode)

        def forward(self, x):
            real, imag = self.stft(x)
            return real ** 2 + imag ** 2

    class LogmelFilterBank(nn.Module):
        def __init__(self, sr=22050, n_fft=2048, n_mels=64, fmin=0.0, fmax=None, is_log=True, ref=1.0, amin=1e-10,
                     top_db=80.0, freeze_parameters=True):
            super().__init__()
            assert is_log and top_db is None, (is_log, top_db)  # MobileNetV2 asks for top_db None
            self.ref, self.amin = ref, amin
            weights = mel_filters(sr, n_fft, n_mels, fmin, fmax if fmax is not None else sr // 2)
            self.melW = nn.Parameter(torch.tensor(weights.T, dtype=torch.float32), requires_grad=False)

        def forward(self, x):
            mel = torch.matmul(x, self.melW)
            log_spec = 10.0 * torch.log10(torch.clamp(mel, min=self.amin, max=np.inf))
            return log_spec - 10.0 * np.log10(np.maximum(self.amin, self.ref))

    class SpecAugmentation(nn.Module):
        """Training only (models.py calls it only when self.training); this script never trains."""
        def __init__(self, *args, **kwargs):
            super().__init__()

        def forward(self, x):
            raise RuntimeError("SpecAugmentation is for training; export_panns.py runs the model in eval mode only")

    package = types.ModuleType("torchlibrosa")
    stft = types.ModuleType("torchlibrosa.stft")
    augmentation = types.ModuleType("torchlibrosa.augmentation")
    stft.Spectrogram, stft.LogmelFilterBank, stft.STFT = Spectrogram, LogmelFilterBank, STFT
    augmentation.SpecAugmentation = SpecAugmentation
    package.stft, package.augmentation = stft, augmentation
    package.__doc__ = "export_panns.py's stand-in for torchlibrosa's Spectrogram, LogmelFilterBank and SpecAugmentation"
    sys.modules.update({"torchlibrosa": package, "torchlibrosa.stft": stft, "torchlibrosa.augmentation": augmentation})


def check_source_values(models_py):
    """The front end's fixed values as MobileNetV2.__init__ sets them at the pinned commit, read from the text."""
    text = open(models_py, encoding="utf-8").read()
    start = text.index("class MobileNetV2(nn.Module):")
    body = text[start:text.index("\nclass ", start + 1)]
    want = ["window = 'hann'", "center = True", "pad_mode = 'reflect'", "ref = 1.0", "amin = 1e-10", "top_db = None",
            "self.bn0 = nn.BatchNorm2d(64)", "self.fc1 = nn.Linear(1280, 1024, bias=True)"]
    missing = [w for w in want if w not in body]
    if missing:
        sys.exit(f"export_panns: MobileNetV2 in models.py no longer sets {missing}; check the front end")
    return want


def music(seconds, rate=RATE):
    """Synthesised music at 32 kHz: a kick and hi-hat at 124 BPM, an A minor chord, and a sung-like line (a harmonic
    tone at 220 to 330 Hz with vibrato and a formant bump), as export_yamnet.py makes it at 16 kHz."""
    n = int(seconds * rate)
    t = np.arange(n) / rate
    y = np.zeros(n)
    beat = 60 / 124
    for b in np.arange(0.1, seconds, beat):
        i = int(b * rate)
        k = np.arange(min(int(0.25 * rate), n - i)) / rate
        y[i:i + len(k)] += 0.6 * np.exp(-k / 0.12) * np.sin(2 * np.pi * (45 * k + 3.15 * (1 - np.exp(-k / 0.03))))
    rng = np.random.default_rng(5)
    for b in np.arange(0.1 + beat / 2, seconds, beat):
        i = int(b * rate)
        m = min(int(0.05 * rate), n - i)
        y[i:i + m] += 0.1 * np.exp(-np.arange(m) / rate / 0.015) * np.diff(rng.uniform(-1, 1, m + 1))
    for midi in (57, 60, 64):
        f = 440 * 2 ** ((midi - 69) / 12)
        for h in range(1, 5):
            y += 0.04 / h * np.sin(2 * np.pi * f * h * t)
    f0 = np.where(t % 1.0 < 0.5, 220.0, 330.0) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    phase = 2 * np.pi * np.cumsum(f0) / rate
    for h in range(1, 20):
        y += 0.06 / h * (1 + 2 * np.exp(-((h * 275 - 700) / 300) ** 2)) * np.sin(h * phase)
    return (0.5 * y / np.max(np.abs(y))).astype(np.float32)


def windows(y, length=64000, hop=15360):
    """y cut as DeckieInference's PANNs cuts it: windows of `length` every `hop`, the last one zero-padded so the
    end is covered; one zero-padded window when y is shorter than a window."""
    count = 1 if len(y) <= length else 1 + -(-(len(y) - length) // hop)
    out = np.zeros((count, length), dtype=np.float32)
    for k in range(count):
        part = y[k * hop:k * hop + length]
        out[k, :len(part)] = part
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--checkpoint", required=True, help="MobileNetV2_mAP=0.383.pth (SHA-256 and MD5 checked)")
    ap.add_argument("--source", required=True, help="folder with models.py, pytorch_utils.py, class_labels_indices.csv")
    ap.add_argument("--out", default=DEFAULT_OUT, help="where to write the ONNX file (default: %(default)s)")
    ap.add_argument("--opset", type=int, default=17, help="ONNX opset (default: %(default)s)")
    args = ap.parse_args()
    out = os.path.abspath(args.out)

    # 0. The inputs, by hash, before anything of theirs is imported or read.
    source = os.path.abspath(args.source)
    for name, want in SOURCE_SHA256.items():
        path = os.path.join(source, name)
        if not os.path.isfile(path):
            sys.exit(f"export_panns: {path} is missing ({SOURCE_REPO} at {SOURCE_COMMIT})")
        got = digest(path, "sha256")
        if got != want:
            sys.exit(f"export_panns: {path} has SHA-256 {got}, expected {want}; not exporting")
    print(f"source: {SOURCE_REPO} {SOURCE_COMMIT}: " + ", ".join(SOURCE_SHA256) + " match their hashes")
    got_sha, got_md5 = digest(args.checkpoint, "sha256"), digest(args.checkpoint, "md5")
    print(f"checkpoint: {args.checkpoint}, {os.path.getsize(args.checkpoint):,} bytes, SHA-256 {got_sha}, MD5 {got_md5}")
    if got_sha != CHECKPOINT_SHA256 or got_md5 != CHECKPOINT_MD5:
        sys.exit(f"export_panns: the checkpoint is not the pinned file (SHA-256 {CHECKPOINT_SHA256}, MD5 "
                 f"{CHECKPOINT_MD5}, from {CHECKPOINT_URL}); not exporting")

    # The class list: the named classes where Deckie expects them.
    with open(os.path.join(source, "class_labels_indices.csv"), newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    labels = [r[2] for r in rows[1:]]
    if rows[0] != ["index", "mid", "display_name"] or len(labels) != CLASSES or \
            [int(r[0]) for r in rows[1:]] != list(range(CLASSES)):
        sys.exit("export_panns: class_labels_indices.csv is not the 527-class list expected")
    wrong = {i: (n, labels[i]) for i, n in NAMED_CLASSES.items() if labels[i] != n}
    if wrong:
        sys.exit(f"export_panns: the class list moved: {wrong}; update NAMED_CLASSES here and PANNsClass in Swift")
    print(f"class list: {CLASSES} classes; the {len(NAMED_CLASSES)} Deckie names are where it expects them")
    print("front end, from models.py's MobileNetV2: " + "; ".join(check_source_values(os.path.join(source, "models.py"))))

    import torch
    import onnx
    os.environ.setdefault("ORT_DISABLE_TELEMETRY", "1")  # official ONNX Runtime builds report usage to Microsoft otherwise
    import onnxruntime as ort
    # The tracer warns that some shapes become constants; only the batch and the length vary, and both are checked.
    warnings.filterwarnings("ignore", category=torch.jit.TracerWarning)
    warnings.filterwarnings("ignore", message=".*legacy TorchScript-based ONNX export.*")
    # The reflect padding's pads are put in ONNX's order by a reversing Slice, which the exporter cannot fold; harmless.
    warnings.filterwarnings("ignore", message=".*Constant folding - Only steps=1 can be constant folded.*")

    install_front_end()
    sys.path.insert(0, source)
    import models as panns_models

    versions = {name: md.version(name) for name in ["torch", "onnx", "onnxruntime", "numpy"]}
    print("versions:", ", ".join(f"{k} {v}" for k, v in versions.items()))
    print(f"python {sys.version.split()[0]}, opset {args.opset}")
    print(f"front end: {RATE} Hz, window {WINDOW} (periodic Hann), hop {HOP}, {MEL_BINS} mel bins {FMIN} to {FMAX} Hz "
          f"(Slaney), centred with reflect padding, log-mel 10 log10(max(mel, {AMIN})) - 10 log10(max({AMIN}, {REF})), "
          f"top_db {TOP_DB}")

    # 1. The network, and its weights.
    torch.manual_seed(0)
    model = panns_models.MobileNetV2(sample_rate=RATE, window_size=WINDOW, hop_size=HOP, mel_bins=MEL_BINS,
                                     fmin=FMIN, fmax=FMAX, classes_num=CLASSES)
    ours = {k: v.clone() for k, v in model.state_dict().items()
            if k.startswith(("spectrogram_extractor.", "logmel_extractor."))}
    # weights_only: tensors and plain values only, no pickled code runs (the file holds 'model' and 'iteration').
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    state = checkpoint["model"]
    result = model.load_state_dict(state, strict=False)
    # Batch norms' counters of training steps are not used in evaluation; every other tensor must be there.
    missing = [k for k in result.missing_keys if not k.endswith("num_batches_tracked")]
    if missing or result.unexpected_keys:
        sys.exit(f"export_panns: the checkpoint does not fit MobileNetV2: missing {missing}, "
                 f"unexpected {result.unexpected_keys}")
    others = sorted(k for k in checkpoint if k != "model")
    print(f"  loaded the checkpoint's 'model' ({len(state)} tensors; other entries: {others or 'none'})")
    loaded = model.state_dict()
    for key, mine in ours.items():
        theirs = loaded[key]
        d = float((theirs - mine).abs().max())
        scale = float(mine.abs().max())
        print(f"  front end {key} {tuple(theirs.shape)}: the checkpoint's against this script's, largest "
              f"difference {d:.2e} (largest value {scale:.3f})")
        if not d <= FRONT_END_TOLERANCE * max(1.0, scale):
            print(f"  NOTE: more than {FRONT_END_TOLERANCE:.0e}: the graph uses the checkpoint's tensors, which are "
                  "what the network was trained with; DEPENDENCIES.md, section 9, should say so")
    model.eval()
    params = sum(int(p.numel()) for p in model.parameters())
    buffers = sum(int(b.numel()) for b in model.buffers())
    print(f"network: {params:,} parameters (front end included), {buffers:,} batch-norm statistics")

    class Tagger(torch.nn.Module):
        """MobileNetV2 with its dictionary output turned into the two tensors the graph returns."""
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, waveform):
            o = self.m(waveform)
            return o["clipwise_output"], o["embedding"]

    net = Tagger(model).eval()

    os.makedirs(os.path.dirname(out), exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".onnx", dir=os.path.dirname(out))
    os.close(fd)
    try:
        # 2. The export, with the batch and the length free.
        example = torch.tensor(windows(music(2.5))[:2])
        t0 = time.time()
        with torch.no_grad():
            torch.onnx.export(
                net, (example,), tmp, dynamo=False, opset_version=args.opset, do_constant_folding=True,
                input_names=["waveform"], output_names=["scores", "embeddings"],
                dynamic_axes={"waveform": {0: "n", 1: "samples"}, "scores": {0: "n"}, "embeddings": {0: "n"}},
            )
        proto = onnx.load(tmp)
        proto.producer_name = "deckie export_panns.py (torch " + versions["torch"] + ")"
        del proto.metadata_props[:]
        for k, v in [("model", f"PANNs MobileNetV2 (Kong et al., TASLP 2020), {SOURCE_REPO}"),
                     ("weights", f"{CHECKPOINT_URL} sha256 {CHECKPOINT_SHA256}"),
                     ("source_commit", SOURCE_COMMIT), ("licence", "code MIT; weights CC BY 4.0 (Zenodo record 3987831)"),
                     ("training_data", "AudioSet (Google); labels CC BY 4.0"),
                     ("front_end", f"in the graph: {RATE} Hz mono, STFT {WINDOW}/{HOP} periodic Hann centred reflect, "
                                   f"{MEL_BINS} Slaney mel {FMIN}-{FMAX} Hz, 10 log10(max(mel, {AMIN})), top_db none"),
                     ("deckie_windows", "2 s windows (64,000 samples) every 0.48 s (15,360 samples)")]:
            entry = proto.metadata_props.add()
            entry.key, entry.value = k, v
        onnx.checker.check_model(proto)
        onnx.save(proto, tmp)
        print(f"exported in {time.time() - t0:.1f} s")

        # 3. ONNX Runtime against PyTorch.
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        sess = ort.InferenceSession(tmp, so, providers=["CPUExecutionProvider"])
        print("inputs:", [(i.name, i.shape, i.type) for i in sess.get_inputs()])
        print("outputs:", [(o.name, o.shape, o.type) for o in sess.get_outputs()])
        assert [i.name for i in sess.get_inputs()] == ["waveform"]
        assert [o.name for o in sess.get_outputs()] == ["scores", "embeddings"]
        rng = np.random.default_rng(1)
        cases = [(f"random, 2 s, n = {n}", (0.1 * rng.standard_normal((n, 64000))).astype(np.float32))
                 for n in CHECK_BATCHES]
        cases += [(f"random, {length} samples", (0.1 * rng.standard_normal((2, length))).astype(np.float32))
                  for length in CHECK_LENGTHS[1:]]
        tune = windows(music(6.0))
        cases.append((f"music, {len(tune)} windows", tune))
        worst = 0.0
        for name, x in cases:
            with torch.no_grad():
                ts, te = (t.numpy() for t in net(torch.tensor(x)))
            os_, oe = sess.run(["scores", "embeddings"], {"waveform": x})
            ds = float(np.max(np.abs(os_ - ts)))
            de = float(np.max(np.abs(oe - te))) / max(1.0, float(np.max(np.abs(te))))
            print(f"  {name:26s}: max |ONNX - torch| scores {ds:.2e}, embeddings {de:.2e} (relative to their largest "
                  f"value, {float(np.max(np.abs(te))):.2f}); largest score {float(np.max(ts)):.3f}")
            worst = max(worst, ds, de)
        with torch.no_grad():
            mean = net(torch.tensor(tune))[0].numpy().mean(0)
        top = np.argsort(mean)[::-1][:5]
        print("  music, top classes (mean over its windows): "
              + ", ".join(f"{labels[i]} {mean[i]:.3f}" for i in top))
        print(f"largest difference: {worst:.2e} (tolerance {TOLERANCE:.0e})")
        if not worst <= TOLERANCE:
            sys.exit("export_panns: ONNX Runtime and PyTorch disagree; not writing the file")

        os.replace(tmp, out)
        tmp = None
        os.chmod(out, 0o644)  # mkstemp made it readable by its owner only
    finally:
        if tmp is not None and os.path.exists(tmp):
            os.remove(tmp)

    # 4. The file and its fingerprint.
    got = digest(out, "sha256")
    print(f"wrote {out}, {os.path.getsize(out):,} bytes, SHA-256 {got}")
    if ONNX_SHA256 == TODO:
        print("  no export is recorded yet (ONNX_SHA256 is a TODO until the first CI export); if this is that export, "
              f"record {got} as ONNX_SHA256 here, in fetch-panns.sh and in DEPENDENCIES.md, section 9")
    elif got == ONNX_SHA256:
        print("  identical to the export recorded in DEPENDENCIES.md")
    else:
        print(f"  differs from the export recorded in DEPENDENCIES.md ({ONNX_SHA256}); check the versions above")


if __name__ == "__main__":
    main()
