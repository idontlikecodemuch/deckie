#!/usr/bin/env bash
# fetch-vocal-models.sh: fetch the vocal tagger's model by pinned URL and hash, and make the ONNX file Deckie runs.
#
#   core/Tools/fetch-vocal-models.sh [--python PYTHON] [--keep-source] [--force] [DEST]
#
# The vocal tagger (DeckieInference's DeckieVocalTagger) runs Google's YAMNet audio tagger. This script:
#   1. downloads YAMNet's Keras weights, yamnet.h5, from Google's own storage (the URL its README in tensorflow/models
#      gives) and the three source files that define the network (params.py, features.py, yamnet.py from
#      tensorflow/models, research/audioset/yamnet, at a pinned commit), and stops before using anything if a file's
#      SHA-256 differs from the value below (recorded in DEPENDENCIES.md, section 8);
#   2. runs core/Tools/export_yamnet.py with them, which builds the network in TensorFlow, converts it to ONNX with
#      tf2onnx, checks ONNX Runtime against TensorFlow, and writes DEST/yamnet.onnx;
#   3. compares the file's SHA-256 with the export recorded in DEPENDENCIES.md and says whether it matches (a
#      different hash is reported, not refused: other tool versions serialise differently; the numerical check in
#      step 2 is what must pass).
#
# DEST defaults to core/.models (in this checkout; .gitignore keeps it out of the repository), where the tagger looks
# when DECKIE_YAMNET_MODEL is not set. Nothing is linked or needed at build time: `swift build` never needs this, the
# analyser runs without the model (no vocal block in its records), and the tests that need it skip with a message.
#
# Python. Step 2 needs TensorFlow (CPU), tf-keras, tf2onnx, onnx, ONNX Runtime and numpy, pinned in
# core/Tools/yamnet-export-requirements.txt; --python names the interpreter that has them (default: python3). The
# script checks for them before downloading anything and, if they are missing, prints how to install them in a
# virtual environment of their own. These are development-time tools: nothing of them ships.
#
# --keep-source leaves the three source files in DEST/yamnet-source (core/Tools/make_yamnet_fixtures.py reads them);
# --force exports again even when DEST/yamnet.onnx is already there. The weights are not kept: only the ONNX file is
# needed afterwards. The download and the export happen in a temporary folder next to DEST; DEST/yamnet.onnx is
# written only once the export's numerical check has passed.
#
# Needs: bash, curl, sha256sum, and the Python above.

if [ -z "${BASH_VERSION:-}" ]; then echo "fetch-vocal-models: run this with bash" >&2; exit 1; fi
set -euo pipefail

WEIGHTS_URL="https://storage.googleapis.com/audioset/yamnet.h5"
WEIGHTS_SHA256="13c3308955bbfaef262f175ac9c40e47b134573a93984f009220dd7cc12a1744"
WEIGHTS_SIZE=15296092
SOURCE_COMMIT="a6e25e28dc8433dde6c1319186a41e6d81a03f2d"
SOURCE_URL="https://raw.githubusercontent.com/tensorflow/models/${SOURCE_COMMIT}/research/audioset/yamnet"
SOURCE_FILES=(params.py features.py yamnet.py)
SOURCE_SHA256=(
    "925bb1e62461016031f98aea09aeac28975dd516f5747513767de5d1b06b6145"
    "e6cd53f81d072c7c43be4c7fff2b9dd0c5ccc7d64f2fbcfc85b44013d6d2ed5e"
    "7ef3df32b7ecb782490b5a04d7581a23cfcf701dbf476bc4d03deefe22cdb040"
)
# The export recorded in DEPENDENCIES.md (tensorflow-cpu 2.21.0, tf-keras 2.21.0, tf2onnx 1.17.0, onnx 1.23.2,
# opset 17); export_yamnet.py holds the same value.
ONNX_SHA256="96bb0dc54745dbbc95ef3f289830c94eec92a6914c4ab711a821bc8aa1c93cfd"

say() { printf '%s\n' "$*"; }
die() { printf 'fetch-vocal-models: %s\n' "$*" >&2; exit 1; }

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
        -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option $1 (see --help)" ;;
        *) [ -z "$dest" ] || die "usage: fetch-vocal-models.sh [--python PYTHON] [--keep-source] [--force] [DEST]"
           dest="$1"; shift ;;
    esac
done
dest="${dest:-$core/.models}"
for tool in curl sha256sum; do command -v "$tool" >/dev/null || die "needs $tool"; done

model="$dest/yamnet.onnx"
if [ -f "$model" ] && [ "$force" = 0 ]; then
    got="$(sha256sum "$model" | cut -d' ' -f1)"
    if [ "$got" = "$ONNX_SHA256" ]; then
        say "YAMNet is already in $model (the recorded export, SHA-256 $got)"
    else
        say "a YAMNet export is already in $model, SHA-256 $got, not the recorded $ONNX_SHA256; --force exports again"
    fi
    exit 0
fi

# The export tools, before anything is downloaded.
if ! "$python" -c "import tensorflow, tf_keras, tf2onnx, onnx, onnxruntime, numpy" >/dev/null 2>&1; then
    cat >&2 <<EOF
fetch-vocal-models: $python cannot import TensorFlow, tf-keras, tf2onnx, onnx, onnxruntime and numpy, which the
export needs (development-time tools; nothing of them ships). Install them in a virtual environment of their own:

  python3 -m venv /tmp/yamnet-venv
  /tmp/yamnet-venv/bin/python -m pip install -r core/Tools/yamnet-export-requirements.txt
  /tmp/yamnet-venv/bin/python -m pip install --no-deps tf-keras==2.21.0

then run: bash core/Tools/fetch-vocal-models.sh --python /tmp/yamnet-venv/bin/python
EOF
    exit 2
fi

mkdir -p "$dest"
work="$(mktemp -d "$dest/.yamnet-fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/source" "$work/weights"

say "downloading $WEIGHTS_URL"
curl -fsSL --retry 3 -o "$work/weights/yamnet.h5" "$WEIGHTS_URL"
got="$(sha256sum "$work/weights/yamnet.h5" | cut -d' ' -f1)"
[ "$got" = "$WEIGHTS_SHA256" ] || die "SHA-256 mismatch for yamnet.h5: expected $WEIGHTS_SHA256, got $got (size $(wc -c < "$work/weights/yamnet.h5"), expected $WEIGHTS_SIZE); nothing was used"
say "SHA-256 matches: $WEIGHTS_SHA256"

for i in "${!SOURCE_FILES[@]}"; do
    f="${SOURCE_FILES[$i]}"
    say "downloading $SOURCE_URL/$f"
    curl -fsSL --retry 3 -o "$work/source/$f" "$SOURCE_URL/$f"
    got="$(sha256sum "$work/source/$f" | cut -d' ' -f1)"
    [ "$got" = "${SOURCE_SHA256[$i]}" ] || die "SHA-256 mismatch for $f: expected ${SOURCE_SHA256[$i]}, got $got; nothing was used"
done
say "the source files match their hashes (tensorflow/models $SOURCE_COMMIT)"

# -P: Python does not put the script's folder on its path; the export imports the source files by their folder.
"$python" -P "$here/export_yamnet.py" --weights "$work/weights/yamnet.h5" --source "$work/source" --out "$model"

if [ "$keep_source" = 1 ]; then
    rm -rf "$dest/yamnet-source"
    mkdir "$dest/yamnet-source"
    cp "$work/source/"*.py "$dest/yamnet-source/"
    say "kept the source files in $dest/yamnet-source"
fi

got="$(sha256sum "$model" | cut -d' ' -f1)"
if [ "$got" = "$ONNX_SHA256" ]; then
    say "YAMNet is in $model: the recorded export, SHA-256 $got"
else
    say "YAMNet is in $model, SHA-256 $got; the recorded export is $ONNX_SHA256 (other tool versions; the numerical check passed)"
fi
