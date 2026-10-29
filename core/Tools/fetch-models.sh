#!/usr/bin/env bash
# fetch-models.sh: put the two models Deckie runs into core/.models, the pinned files, checked by their hashes.
#
#   core/Tools/fetch-models.sh [--beat-this] [--yamnet] [--no-export] [--python PYTHON] [--force] [--check]
#
# The engine runs two models through ONNX Runtime, each exported once from its published weights and pinned by the
# SHA-256 of the exported file (DEPENDENCIES.md, sections 7 and 8):
#   beat_this_final0.onnx  the beat tracker, Beat This! final0, 82,098,829 bytes (core/Tools/export_beat_this.py)
#   yamnet.onnx            the vocal tagger, YAMNet, 14,938,528 bytes (core/Tools/fetch-vocal-models.sh, export_yamnet.py)
# An export gives the same bytes only with the same tool versions (another torch writes another graph, and some
# machines have no wheel of the pinned TensorFlow at all), so every machine fetches the pinned files instead. They are
# assets of this repository's release models-1, each with its .sha256 beside it:
#   https://github.com/idontlikecodemuch/deckie/releases/download/models-1/<file>
# DECKIE_MODELS_URL replaces that base for a mirror (any URL curl takes, file:// included).
#
# What it trusts. Only the hash: for each model asked for (both by default), a file already in core/.models with the
# pinned SHA-256 is reported and left alone; otherwise the file is downloaded into a temporary folder in core/.models,
# its SHA-256 is recomputed, and it is moved into place, in one rename, only if it is the pinned value. A file with
# any other hash already there is replaced only then. The pinned values are read from the export scripts' ONNX_SHA256
# lines (export_beat_this.py, export_yamnet.py), the one place the code records them.
#
# On a miss (the release or the file is not there, another download error, or a hash mismatch) it says what happened
# and, unless --no-export, makes the model the old way: export_beat_this.py for Beat This!, fetch-vocal-models.sh for
# YAMNet (which fetches YAMNet's weights by their own pinned hashes). Both need a Python with their pinned packages,
# and the two want separate environments (TensorFlow brings its own protobuf): --python names it (default: python3),
# so when both models are missing, run once per model with --beat-this or --yamnet. If that Python lacks the packages,
# the message says how to set one up. An export made with other tool versions may have another hash: it is kept (its
# numerical check passed) and reported. The export is also how the next version of a model is made (DEPENDENCIES.md,
# "How to update").
#
# --force downloads again even when a file is in place with the pinned hash. --check only reports whether each model
# is in place with its pinned hash; nothing is downloaded or exported. The exit status is 0 when every model asked for
# is in place (the pinned file, or an export made by this run) and 1 otherwise.
#
# Needs: bash, curl, sha256sum (or shasum, as on macOS), and for an export, the Python above.

if [ -z "${BASH_VERSION:-}" ]; then echo "fetch-models: run this with bash" >&2; exit 1; fi
set -euo pipefail

BASE_URL="https://github.com/idontlikecodemuch/deckie/releases/download/models-1"

say() { printf '%s\n' "$*"; }
warn() { printf 'fetch-models: %s\n' "$*" >&2; }
die() { printf 'fetch-models: %s\n' "$*" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(dirname "$here")"
models="$core/.models"
base="${DECKIE_MODELS_URL:-$BASE_URL}"
base="${base%/}"

beat_this=0
yamnet=0
do_export=1
python="python3"
force=0
check=0
while [ $# -gt 0 ]; do
    case "$1" in
        --beat-this) beat_this=1; shift ;;
        --yamnet) yamnet=1; shift ;;
        --no-export) do_export=0; shift ;;
        --python) [ $# -ge 2 ] || die "--python needs an interpreter"; python="$2"; shift 2 ;;
        --force) force=1; shift ;;
        --check) check=1; shift ;;
        -h|--help) sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument $1 (see --help)" ;;
    esac
done
if [ "$beat_this" = 0 ] && [ "$yamnet" = 0 ]; then beat_this=1; yamnet=1; fi

if command -v sha256sum >/dev/null; then
    hash_of() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
    hash_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    die "needs sha256sum or shasum"
fi
[ "$check" = 1 ] || command -v curl >/dev/null || die "needs curl"
size_of() { wc -c < "$1" | tr -d ' '; }

# The pinned SHA-256 of an export: the line ONNX_SHA256 = "<64 hexadecimal digits>" in the export script $1.
pinned_hash() {
    local value
    value="$(sed -n 's/^ONNX_SHA256 = "\([0-9a-f]\{64\}\)"$/\1/p' "$1")"
    [[ "$value" =~ ^[0-9a-f]{64}$ ]] || die "cannot read the pinned SHA-256 from $1 (one line ONNX_SHA256 = \"<64 hex digits>\")"
    printf '%s' "$value"
}

export_beat_this() {
    if ! "$python" -P -c "import torch, torchaudio, einops, rotary_embedding_torch, beat_this, onnx, onnxruntime, numpy" >/dev/null 2>&1; then
        cat >&2 <<EOF
fetch-models: $python cannot run the Beat This! export, which needs Python 3.11 or later with the packages pinned in
core/Tools/export-requirements.txt (PyTorch's CPU build, beat_this, ONNX; development-time tools, nothing of them
ships). Install them in a virtual environment of their own, as that file says (a Mac's torch wheels have no +cpu):

  python3 -m venv /tmp/export-venv
  /tmp/export-venv/bin/python -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.15.0+cpu torchaudio==2.11.1+cpu
  /tmp/export-venv/bin/python -m pip install -r core/Tools/export-requirements.txt

then run: bash core/Tools/fetch-models.sh --beat-this --python /tmp/export-venv/bin/python
EOF
        return 1
    fi
    # -P: Python does not put the script's folder on its path (as CI runs it).
    "$python" -P "$here/export_beat_this.py" --out "$models/beat_this_final0.onnx"
}

export_yamnet() {
    # It checks its Python before downloading anything and, if the packages are missing, says how to set one up.
    # --force: a file already there is not the pinned one (or --force asked for the model again), so it is replaced.
    bash "$here/fetch-vocal-models.sh" --force --python "$python" "$models"
}

work=""
trap 'rm -rf "$work"' EXIT
missing=""

# fetch NAME FILE PINNING_SCRIPT EXPORT_FUNCTION EXPORTER: put the model in place, or add NAME to $missing.
fetch() {
    local name="$1" file="$2" pinned path url got code status detail miss have=""
    pinned="$(pinned_hash "$here/$3")"
    path="$models/$file"
    url="$base/$file"

    if [ -f "$path" ]; then
        have="$(hash_of "$path")"
        if [ "$have" = "$pinned" ] && { [ "$force" = 0 ] || [ "$check" = 1 ]; }; then
            say "$name is in place: $path, SHA-256 $have, the pinned file"
            return 0
        fi
        [ "$have" = "$pinned" ] || say "$name: $path has SHA-256 $have, not the pinned $pinned"
    elif [ "$check" = 1 ]; then
        say "$name is missing: no $path"
    fi
    if [ "$check" = 1 ]; then missing="$missing${missing:+, }$name"; return 0; fi

    mkdir -p "$models"
    work="$(mktemp -d "$models/.fetch-models.XXXXXX")"
    say "$name: downloading $url"
    status=0
    code="$(curl -fsSL --retry 3 -o "$work/$file" -w '%{http_code}' "$url" 2>"$work/curl-error")" || status=$?
    if [ "$status" = 0 ]; then
        got="$(hash_of "$work/$file")"
        if [ "$got" = "$pinned" ]; then
            chmod 644 "$work/$file"
            mv -f "$work/$file" "$path"
            rm -rf "$work"
            say "$name is in place: $path, SHA-256 $got, the pinned file ($(size_of "$path") bytes)"
            return 0
        fi
        miss="SHA-256 mismatch for $url: expected $pinned, got $got ($(size_of "$work/$file") bytes); the file was not used"
    elif [ "$status" = 22 ] && [ "$code" = 404 ]; then
        miss="not found (HTTP 404): $url; the release or its file is not there"
    else
        detail="curl exit $status"
        [ "$code" = 000 ] || detail="$detail, HTTP $code"
        miss="download failed ($detail): $(cat "$work/curl-error")"
    fi
    rm -rf "$work"
    warn "$name: $miss"

    if [ "$have" = "$pinned" ]; then  # --force asked to download it again
        say "$name is in place: $path, SHA-256 $have, the pinned file, kept as it was"
        return 0
    fi
    if [ "$do_export" = 0 ]; then
        if [ -f "$path" ]; then
            warn "$name: not exporting (--no-export); $path was left as it was, not the pinned file"
        else
            warn "$name: not exporting (--no-export); $path is missing"
        fi
        missing="$missing${missing:+, }$name"
        return 0
    fi
    say "$name: exporting it instead, with $5 (Python: $python)"
    if ! "$4"; then
        warn "$name: the export did not run or failed (see above); $path is $([ -f "$path" ] && echo "as it was, not the pinned file" || echo "missing")"
        missing="$missing${missing:+, }$name"
        return 0
    fi
    got="$(hash_of "$path")"
    if [ "$got" = "$pinned" ]; then
        say "$name is in place: $path, exported, SHA-256 $got, the pinned file"
    else
        say "$name is in place: $path, exported, SHA-256 $got, not the pinned $pinned (other tool versions; the export's numerical check passed)"
    fi
}

# Called in plain statements, not after || or &&, so that set -e still stops on an unexpected failure inside.
if [ "$beat_this" = 1 ]; then
    fetch "Beat This!" beat_this_final0.onnx export_beat_this.py export_beat_this "core/Tools/export_beat_this.py"
fi
if [ "$yamnet" = 1 ]; then
    fetch "YAMNet" yamnet.onnx export_yamnet.py export_yamnet "core/Tools/fetch-vocal-models.sh and export_yamnet.py"
fi
if [ -n "$missing" ]; then die "not in place with the pinned hash: $missing"; fi
