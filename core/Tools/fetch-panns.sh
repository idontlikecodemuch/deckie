#!/usr/bin/env bash
# fetch-panns.sh: fetch PANNs' MobileNetV2 checkpoint by pinned URL and hash, and make the ONNX file Deckie runs.
#
#   core/Tools/fetch-panns.sh [--python PYTHON] [--keep-source] [--force] [DEST]
#
# The vocal tagger's second opinion (DeckieInference's PANNs) runs the MobileNetV2 audio tagger of Kong et al.'s PANNs
# ("PANNs: Large-Scale Pretrained Audio Neural Networks for Audio Pattern Recognition", IEEE/ACM TASLP 2020). This
# script:
#   1. downloads the trained checkpoint, MobileNetV2_mAP=0.383.pth, from the authors' Zenodo record 3987831 (the
#      record the repository's README names), and the three files that define the network and its classes
#      (pytorch/models.py, pytorch/pytorch_utils.py, metadata/class_labels_indices.csv from
#      github.com/qiuqiangkong/audioset_tagging_cnn at a pinned commit), and stops before using anything if a file's
#      hash differs from the value below (recorded in DEPENDENCIES.md, section 9): the checkpoint's SHA-256 and MD5
#      (the MD5 Zenodo's record gives) and each source file's SHA-256;
#   2. runs core/Tools/export_panns.py with them, which builds the network in PyTorch with the source's own code,
#      loads the checkpoint (tensors only), exports the whole model, log-mel front end included, to ONNX, checks ONNX
#      Runtime against PyTorch, and writes DEST/panns_mobilenetv2.onnx;
#   3. compares the file's SHA-256 with the export recorded in export_panns.py and says whether it matches (a different
#      hash is reported, not refused: other tool versions serialise differently; the numerical check in step 2 is what
#      must pass). Until the first CI export is recorded the value is a TODO and no comparison is made.
#
# DEST defaults to core/.models (in this checkout; .gitignore keeps it out of the repository), where the second
# opinion looks when DECKIE_PANNS_MODEL is not set. Nothing is linked or needed at build time: `swift build` never
# needs this, the analyser runs without the model (no second opinion in its records), and the tests that need it skip
# with a message.
#
# Python. Step 2 needs PyTorch (CPU), onnx, ONNX Runtime and numpy, pinned in core/Tools/panns-export-requirements.txt
# (not torchlibrosa or librosa: the export writes the front end itself, export_panns.py says how); --python names the
# interpreter that has them (default: python3). The script checks for them before downloading anything and, if they
# are missing, prints how to install them in a virtual environment of their own. These are development-time tools:
# nothing of them ships.
#
# --keep-source leaves the three source files in DEST/panns-source (core/Tools/make_panns_fixtures.py reads the class
# list there); --force exports again even when DEST/panns_mobilenetv2.onnx is already there. The checkpoint is not
# kept: only the ONNX file is needed afterwards. The download and the export happen in a temporary folder next to DEST;
# DEST/panns_mobilenetv2.onnx is written only once the export's numerical check has passed.
#
# Needs: bash, curl, sha256sum, md5sum (or shasum and md5, as on macOS), and the Python above.

if [ -z "${BASH_VERSION:-}" ]; then echo "fetch-panns: run this with bash" >&2; exit 1; fi
set -euo pipefail

CHECKPOINT_URL="https://zenodo.org/records/3987831/files/MobileNetV2_mAP%3D0.383.pth?download=1"
# Downloaded Oct 29, 2026 (export_panns.py holds the same values); the MD5 is the one Zenodo's record gives.
CHECKPOINT_SHA256="22437af9eb5ed1854b5ad285b4a17d5fc566f1a3b23df40db5541f5705ca340f"
CHECKPOINT_MD5="838421a9262cce976aa247946d6e2983"
CHECKPOINT_SIZE=20834417
SOURCE_COMMIT="d2f4b8c18eab44737fcc0de1248ae21eb43f6aa4"
SOURCE_URL="https://raw.githubusercontent.com/qiuqiangkong/audioset_tagging_cnn/${SOURCE_COMMIT}"
SOURCE_PATHS=(pytorch/models.py pytorch/pytorch_utils.py metadata/class_labels_indices.csv)
SOURCE_SHA256=(
    "7f9af440395ace5160bbb51d654a0dc35fb887fbf5edecb12da61ff6efb306d9"
    "1464fcfbfc0fe4c55f690f6b39e1c80eeed5de1e7fd1b7fd30334d304de7dbe9"
    "cdd1049833c4b86127c2773ac0d14a2754b6a6d0d1798002ed5c66e699708429"
)
# The export to be recorded in DEPENDENCIES.md once CI has made it; export_panns.py holds the same value.
ONNX_SHA256="TODO-after-first-ci-export"
TODO="TODO-after-first-ci-export"

say() { printf '%s\n' "$*"; }
die() { printf 'fetch-panns: %s\n' "$*" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(dirname "$here")"
python="python3"
keep_source=0
force=0
dest=""
while [ $# -gt 0 ]; do
    case "$1" in
        --python) [ $# -ge 2 ] || die "--python needs an interpreter"; python="$2"; shift 2 ;;
        --keep-source) keep_source=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $1 (see --help)" ;;
        *) [ -z "$dest" ] || die "usage: fetch-panns.sh [--python PYTHON] [--keep-source] [--force] [DEST]"
           dest="$1"; shift ;;
    esac
done
dest="${dest:-$core/.models}"
command -v curl >/dev/null || die "needs curl"
if command -v sha256sum >/dev/null; then
    sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
    md5_of() { md5sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
    sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
    md5_of() { md5 -q "$1"; }
else
    die "needs sha256sum and md5sum (or shasum and md5)"
fi

model="$dest/panns_mobilenetv2.onnx"
if [ -f "$model" ] && [ "$force" = 0 ]; then
    got="$(sha256_of "$model")"
    if [ "$ONNX_SHA256" = "$TODO" ]; then
        say "a PANNs export is already in $model, SHA-256 $got (no export is recorded yet); --force exports again"
    elif [ "$got" = "$ONNX_SHA256" ]; then
        say "PANNs is already in $model (the recorded export, SHA-256 $got)"
    else
        say "a PANNs export is already in $model, SHA-256 $got, not the recorded $ONNX_SHA256; --force exports again"
    fi
    exit 0
fi

# The export tools, before anything is downloaded.
if ! "$python" -P -c "import torch, onnx, onnxruntime, numpy" >/dev/null 2>&1; then
    cat >&2 <<EOF
fetch-panns: $python cannot import torch, onnx, onnxruntime and numpy, which the export needs (development-time
tools; nothing of them ships). Install them in a virtual environment of their own (a Mac's torch wheels have no +cpu:
there, drop the index and the +cpu):

  python3 -m venv /tmp/panns-venv
  /tmp/panns-venv/bin/python -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.15.0+cpu
  /tmp/panns-venv/bin/python -m pip install -r core/Tools/panns-export-requirements.txt

then run: bash core/Tools/fetch-panns.sh --python /tmp/panns-venv/bin/python
EOF
    exit 2
fi

mkdir -p "$dest"
work="$(mktemp -d "$dest/.panns-fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/source" "$work/weights"

checkpoint="$work/weights/MobileNetV2_mAP=0.383.pth"
say "downloading $CHECKPOINT_URL"
curl -fsSL --retry 3 -o "$checkpoint" "$CHECKPOINT_URL"
got_sha="$(sha256_of "$checkpoint")"
got_md5="$(md5_of "$checkpoint")"
size="$(wc -c < "$checkpoint" | tr -d ' ')"
[ "$got_sha" = "$CHECKPOINT_SHA256" ] && [ "$got_md5" = "$CHECKPOINT_MD5" ] || die "hash mismatch for the checkpoint: expected SHA-256 $CHECKPOINT_SHA256 and MD5 $CHECKPOINT_MD5 ($CHECKPOINT_SIZE bytes), got $got_sha and $got_md5 ($size bytes); nothing was used"
say "SHA-256 and MD5 match: $CHECKPOINT_SHA256, $CHECKPOINT_MD5 ($size bytes)"

for i in "${!SOURCE_PATHS[@]}"; do
    p="${SOURCE_PATHS[$i]}"
    f="$(basename "$p")"
    say "downloading $SOURCE_URL/$p"
    curl -fsSL --retry 3 -o "$work/source/$f" "$SOURCE_URL/$p"
    got="$(sha256_of "$work/source/$f")"
    [ "$got" = "${SOURCE_SHA256[$i]}" ] || die "SHA-256 mismatch for $p: expected ${SOURCE_SHA256[$i]}, got $got; nothing was used"
done
say "the source files match their hashes (qiuqiangkong/audioset_tagging_cnn $SOURCE_COMMIT)"

# -P: Python does not put the script's folder on its path; the export imports the source files by their folder.
"$python" -P "$here/export_panns.py" --checkpoint "$checkpoint" --source "$work/source" --out "$model"

if [ "$keep_source" = 1 ]; then
    rm -rf "$dest/panns-source"
    mkdir "$dest/panns-source"
    for p in "${SOURCE_PATHS[@]}"; do cp "$work/source/$(basename "$p")" "$dest/panns-source/"; done
    say "kept the source files in $dest/panns-source"
fi

got="$(sha256_of "$model")"
if [ "$ONNX_SHA256" = "$TODO" ]; then
    say "PANNs is in $model, SHA-256 $got; no export is recorded yet: if this is the first CI export, record it as ONNX_SHA256 here and in export_panns.py"
elif [ "$got" = "$ONNX_SHA256" ]; then
    say "PANNs is in $model: the recorded export, SHA-256 $got"
else
    say "PANNs is in $model, SHA-256 $got; the recorded export is $ONNX_SHA256 (other tool versions; the numerical check passed)"
fi
