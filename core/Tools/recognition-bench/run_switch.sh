#!/bin/sh
# Runs every listener of docs/research/faster-listening-proposals.md on the same clips and scores them.
#
#   INDEX_FILE=crate.dkx run_switch.sh WORK ROLE [ARM ...]                       an index made earlier
#   INDEX="--prints DIR --leave-out absent.txt" run_switch.sh WORK ROLE [ARM ...]  built from fingerprints, kept
#
# WORK/switch/ROLE/clips.tsv and truth.jsonl come from switch_clips.py make. ARMs are deckie-listen's --listener
# names (default: main fast a b ab); an arm may carry more options after a colon, e.g. "a:--challenge-margin,1.5" (commas for spaces)
# (its readings are then labelled with them). Each arm's readings go to WORK/switch/ROLE/readings-ARM.tsv and are kept,
# so a stopped run carries on. The table goes to WORK/switch/ROLE/table.md and the numbers to table.json.
# JOBS: threads (default all). GROUPS: a file of id <tab> group for versions (optional).
set -eu
WORK=$1; ROLE=$2; shift 2
ARMS=${*:-main fast a b ab}
HERE=$(cd "$(dirname "$0")" && pwd)
CORE=$(cd "$HERE/../.." && pwd)
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
DIR="$WORK/switch/$ROLE"
(cd "$CORE" && swift build -c release --product deckie-listen >/dev/null)
LISTEN=$(cd "$CORE" && swift build -c release --show-bin-path)/deckie-listen
if [ -n "${INDEX_FILE:-}" ]; then IX=$INDEX_FILE; else IX="$DIR/index.dkx"; fi
# shellcheck disable=SC2086
[ -f "$IX" ] || $LISTEN $INDEX --save-index "$IX" --build-only
[ -f "$DIR/related.tsv" ] || $LISTEN --index "$IX" --related-out "$DIR/related.tsv" --build-only
PAIRS=""
for arm in $ARMS; do
    name=${arm%%:*}; extra=""
    case "$arm" in *:*) extra=$(printf %s "${arm#*:}" | tr , " ");; esac
    label=$(printf '%s%s' "$name" "$extra" | tr -c 'A-Za-z0-9.\n' '_')
    out="$DIR/readings-$label.tsv"
    if [ ! -f "$out" ]; then
        echo "listening: $arm" >&2
        # shellcheck disable=SC2086
        $LISTEN --index "$IX" --list "$DIR/clips.tsv" --out "$out.part" --jobs "$JOBS" --listener "$name" $extra
        mv "$out.part" "$out"
    fi
    PAIRS="$PAIRS $label=$out"
done
# shellcheck disable=SC2086
python3 "$HERE/switch_eval.py" "$WORK" "$ROLE" $PAIRS --related "$DIR/related.tsv" ${GROUPS:+--groups "$GROUPS"} --json "$DIR/table.json" > "$DIR/table.md"
cat "$DIR/table.md"
