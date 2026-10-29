#!/usr/bin/env bash
# fetch-onnxruntime.sh: put ONNX Runtime's Linux x86_64 release where Deckie looks for it, checked by its hash.
#
#   core/Tools/fetch-onnxruntime.sh [--deckie] [DEST]
#
# DEST defaults to core/.deps/onnxruntime (in this checkout; .gitignore keeps it out of the repository). Afterwards
# DEST/lib/libonnxruntime.so is the library DeckieInference opens at run time when DECKIE_ONNXRUNTIME_LIB is not
# set (core/Sources/COnnxRuntime/deckie_ort.c). Nothing is linked at build time, so `swift build` never needs this;
# only the tests that run the model do, and they skip with a message when the library is absent.
#
# Which archive. By default, Microsoft's official archive from the ONNX Runtime project's release page, which carries
# Microsoft's usage-reporting client (switched off by ORT_DISABLE_TELEMETRY, which deckie_ort.c sets; DEPENDENCIES.md,
# section 6). With --deckie, Deckie's own build of the same release instead, made without that client by
# .github/workflows/onnxruntime-build.yml and published on this repository's release
# onnxruntime-1.31.1-deckie-no-telemetry: the library a shipped build carries, published Oct 29, 2026 with
# Christopher's approval and pinned below (the Linux library in it hashed the same in two independent builds).
# Microsoft's archive stays the default for development; a shipped build fetches with --deckie. Once fetched, the
# release test checks the library:
#   DECKIE_SHIPPED_ONNXRUNTIME=core/.deps/onnxruntime/lib/libonnxruntime.so.1.31.1 swift test
#
# What it trusts. The archive comes from GitHub over HTTPS, and every byte is pinned: the script recomputes the
# archive's SHA-256 and stops before unpacking anything if it differs from the value below (recorded in
# DEPENDENCIES.md, section 6). It then checks that the release's copy of the C API header is the one vendored in
# core/Sources/COnnxRuntime/include, and warns if not (a header and a library from different releases still work if
# the library is newer, since the API is versioned, but the pin says they match).
#
# Safety. The download and the unpacking happen in a temporary folder next to DEST; DEST is replaced only at the
# end, in one rename, once the hash has matched. DEST/.fetched-archive records which archive is there: run again with
# the same archive installed, the script only reports it; asked for the other archive, it replaces DEST.
#
# Windows. The same release has onnxruntime-win-x64-1.31.1.zip (82,929,944 bytes, SHA-256
# 5869e26bb25314375f2d5ef1877e3ea06b1543d6c710e6e4a1ec2f7177ab4b2c). This script does not fetch it. To use it:
# download it from the same release page, check the hash (PowerShell: Get-FileHash <zip> -Algorithm SHA256),
# unzip it, and set DECKIE_ONNXRUNTIME_LIB to the full path of its lib\onnxruntime.dll (or unzip it so that the
# DLL sits at core\.deps\onnxruntime\lib\onnxruntime.dll). Its .pdb files (debug symbols, 429 MB) are not needed.
#
# Needs: bash, curl, tar with gzip, sha256sum.

if [ -z "${BASH_VERSION:-}" ]; then echo "fetch-onnxruntime: run this with bash" >&2; exit 1; fi
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { printf 'fetch-onnxruntime: %s\n' "$*" >&2; exit 1; }
usage() { die "usage: fetch-onnxruntime.sh [--deckie] [DEST]"; }

deckie=0
args=()
for arg in "$@"; do
    case "$arg" in
        --deckie) deckie=1 ;;
        -*) usage ;;
        *) args+=("$arg") ;;
    esac
done
[ ${#args[@]} -le 1 ] || usage

VERSION="1.31.1"
if [ "$deckie" = 1 ]; then
    ARCHIVE="onnxruntime-linux-x64-${VERSION}-deckie-no-telemetry.tgz"
    URL="https://github.com/idontlikecodemuch/deckie/releases/download/onnxruntime-${VERSION}-deckie-no-telemetry/${ARCHIVE}"
    # TODO-after-first-build: the first run of .github/workflows/onnxruntime-build.yml gives this archive's SHA-256
    # and size in its Linux job's summary (and in the .sha256 file beside the archive on the release). Put them here
    # and in DEPENDENCIES.md, section 6; then --deckie works, and can become the default.
    SHA256="aa2ea7283836606d6a7eda70b0e67d7a35a801ef99268d275c62c7b9374b9ecf"
    SIZE=10183126
else
    ARCHIVE="onnxruntime-linux-x64-${VERSION}.tgz"
    URL="https://github.com/microsoft/onnxruntime/releases/download/v${VERSION}/${ARCHIVE}"
    SHA256="c849e36a1ef3e22d4ff217b9d1ce4a3cf5b9467b975610913ae959ad5b16bdc9"
    SIZE=11413655
fi
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || die "the SHA-256 of $ARCHIVE is not recorded yet: the first run of .github/workflows/onnxruntime-build.yml gives it in its job summary (see SHA256 in this script); nothing was downloaded"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
core="$(dirname "$here")"
dest="${args[0]:-$core/.deps/onnxruntime}"

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) ;;
    *) die "this fetches the Linux x86_64 build; this machine is $(uname -s) $(uname -m) (see the Windows note at the top)" ;;
esac
for tool in curl tar sha256sum; do command -v "$tool" >/dev/null || die "needs $tool"; done

if [ -f "$dest/.fetched-archive" ] && [ "$(cat "$dest/.fetched-archive")" = "$ARCHIVE $SHA256" ] && [ -e "$dest/lib/libonnxruntime.so" ]; then
    say "ONNX Runtime $VERSION ($ARCHIVE) is already in $dest"
    exit 0
fi

parent="$(dirname "$dest")"
mkdir -p "$parent"
work="$(mktemp -d "$parent/.onnxruntime-fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT

say "downloading $URL"
curl -fsSL --retry 3 -o "$work/$ARCHIVE" "$URL"
got="$(sha256sum "$work/$ARCHIVE" | cut -d' ' -f1)"
[ "$got" = "$SHA256" ] || die "SHA-256 mismatch for $ARCHIVE: expected $SHA256, got $got (size $(wc -c < "$work/$ARCHIVE"), expected $SIZE); nothing was unpacked"
say "SHA-256 matches: $SHA256"

mkdir "$work/unpacked"
tar -xzf "$work/$ARCHIVE" -C "$work/unpacked" --strip-components=1 --no-same-owner
[ -e "$work/unpacked/lib/libonnxruntime.so" ] || die "the archive has no lib/libonnxruntime.so"
[ "$(cat "$work/unpacked/VERSION_NUMBER")" = "$VERSION" ] || die "the archive says version $(cat "$work/unpacked/VERSION_NUMBER"), expected $VERSION"

vendored="$core/Sources/COnnxRuntime/include"
for h in onnxruntime_c_api.h onnxruntime_ep_c_api.h onnxruntime_error_code.h; do
    if ! cmp -s "$work/unpacked/include/$h" "$vendored/$h"; then
        say "warning: $h in the release differs from the vendored copy in $vendored"
    fi
done

printf '%s %s\n' "$ARCHIVE" "$SHA256" > "$work/unpacked/.fetched-archive"
rm -rf "$dest"
mv "$work/unpacked" "$dest"
say "ONNX Runtime $VERSION ($ARCHIVE) is in $dest"
say "library: $dest/lib/libonnxruntime.so"
