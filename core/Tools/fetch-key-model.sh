#!/usr/bin/env bash
# Fetch the learned key reader's file and its credit list into core/.models (which .gitignore keeps out of the
# repository), from this repository's release models-1, checking each against its pinned SHA-256.
#
#   core/Tools/fetch-key-model.sh [--require] [--check]
#
#   deckie-key-<version>.f16           the model's numbers; its name and SHA-256 are pinned in
#                                      core/Sources/DeckieCore/Key/LearnedKey.swift (pinnedName, pinnedSHA256)
#   deckie-key-<version>-credits.tsv   every recording it learned from, with its page and licence: the credit CC BY
#                                      asks for (DEPENDENCIES.md, section 13); its SHA-256 is pinned below
#
# The model is optional: without it, or with a file that is not the pinned one, the engine reads keys with the
# untrained three-answer reader. So this script never fails a build for it: when the release has no such file, or the
# download does not match, it says so, removes what did not match, and exits 0. With --require it exits 1 instead.
# With --check it downloads nothing and exits 0 only when both pinned files are in place.
# A retrained model is a new file name and new pins (there and below); nothing is ever overwritten on the release.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
models="$here/../.models"
swift="$here/../Sources/DeckieCore/Key/LearnedKey.swift"
release="https://github.com/idontlikecodemuch/deckie/releases/download/models-1"
CREDITS_SHA256="8769b179fc1c09ba39ba9d84fdb03d57f67359be32cbb30771797e43d14c87f5"

require=0; check=0
for a in "$@"; do
    case "$a" in
        --require) require=1 ;;
        --check) check=1 ;;
        *) echo "fetch-key-model: unknown argument $a" >&2; exit 2 ;;
    esac
done
say() { echo "fetch-key-model: $*"; }
if command -v sha256sum >/dev/null; then hash_of() { sha256sum "$1" | cut -d' ' -f1; }
else hash_of() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi

name="$(sed -n 's/^ *public static let pinnedName = "\([a-z0-9-]*\)"$/\1/p' "$swift")"
pinned="$(sed -n 's/^ *public static let pinnedSHA256 = "\([0-9a-f]\{64\}\)"$/\1/p' "$swift")"
if [ -z "$name" ] || [ -z "$pinned" ]; then echo "fetch-key-model: cannot read the pinned name and SHA-256 from $swift" >&2; exit 2; fi

missing=""
one() {  # file, pinned hash
    local file="$1" want="$2" path="$models/$1"
    if [ -f "$path" ] && [ "$(hash_of "$path")" = "$want" ]; then say "$file is in place, SHA-256 $want, the pinned file"; return 0; fi
    if [ "$check" = 1 ]; then say "$file is not in place with the pinned hash"; missing="$missing $file"; return 0; fi
    mkdir -p "$models"
    local tmp="$path.download"
    if curl -fsSL --retry 3 -o "$tmp" "$release/$file" 2>/dev/null; then
        local got; got="$(hash_of "$tmp")"
        if [ "$got" = "$want" ]; then mv -f "$tmp" "$path"; say "$file fetched, SHA-256 $got, the pinned file"; return 0; fi
        rm -f "$tmp"; say "$file: SHA-256 mismatch (expected $want, got $got); the file was not used"
    else
        rm -f "$tmp"; say "$file: not on the release models-1 (or the download failed): $release/$file"
    fi
    missing="$missing $file"
}
one "$name.f16" "$pinned"
one "$name-credits.tsv" "$CREDITS_SHA256"
if [ -n "$missing" ]; then
    say "not in place:$missing. Keys are read by the untrained three-answer reader."
    if [ "$require" = 1 ] || [ "$check" = 1 ]; then exit 1; fi
fi
exit 0
