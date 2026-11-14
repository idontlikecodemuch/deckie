#!/bin/sh
# The real-room test (room_test.py): Deckie's own matcher over a booth's recordings of a real set.
#
#   CRATE=/path/x.deckiecrate MUSIC=/path/music RECORDINGS=/path/sets WORK=/path/work \
#   SUBSETS="folder/prefix/ ..." MIX="folder/of/a/premixed/disc/" PART_FROM=2026-01-01T00:00:00Z \
#   [BOOTH_CATALOGUE=/path/booth-catalogue.json] [EXTRA=/path/more/music] \
#       core/Tools/recognition-bench/room_test.sh
#
# Fingerprints every song of the crate (MUSIC is the folder its "rel" paths start from), matches every window of every
# recording against the whole crate and against the subsets (the discs), builds the answer key and writes
# WORK/report.md. EXTRA: a further folder of music joined to the crate as distractors (none of it played), matched as a
# third catalogue ("bigger"). BOOTH_CATALOGUE: the booth's own catalogue that night, for the comparison with its log. WORK must be outside the repository or in an ignored folder: everything it holds comes from the DJ's
# own recordings and music. Everything runs under nice -n 19 with JOBS workers (default 2). The matcher's settings and
# threshold are the outside benchmark's (threshold.txt); nothing is chosen on this material.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
CORE=$(cd "$HERE/../.." && pwd)
JOBS=${JOBS:-2}
SUBSETS=${SUBSETS:-}
MIX=${MIX:-}
PART_FROM=${PART_FROM:-}
EXTRA=${EXTRA:-}
BOOTH_CATALOGUE=${BOOTH_CATALOGUE:-}
THRESHOLD=$(cat "$HERE/threshold.txt")
mkdir -p "$WORK"
(cd "$CORE" && nice -n 19 swift build -c release --product deckie-recog-bench -j "$JOBS")
BENCH=$(cd "$CORE" && swift build -c release --show-bin-path)/deckie-recog-bench
PY="nice -n 19 python3 $HERE/room_test.py"

[ -f "$WORK/catalogue.json" ] || $PY catalogue "$CRATE/crate.json" "$MUSIC" "$WORK" --subset $MIX $SUBSETS
if [ ! -f "$WORK/prints.tsv" ]; then
    python3 -c "import json,sys; c=json.load(open(sys.argv[1])); [print(k+'\t'+v['file']) for k,v in sorted(c.items())]" \
        "$WORK/catalogue.json" > "$WORK/print-list.tsv"
    /usr/bin/time -l nice -n 19 "$BENCH" print --list "$WORK/print-list.tsv" --out "$WORK/prints-all" --jobs "$JOBS" \
        > "$WORK/prints.tsv" 2> "$WORK/print.time"
fi
[ -f "$WORK/queries.tsv" ] || $PY prepare "$RECORDINGS" "$WORK" ${PART_FROM:+--part-from "$PART_FROM"}

# The discs' catalogue: the mix (subset-0) and the other subsets together.
if [ ! -d "$WORK/prints-discs" ]; then
    mkdir -p "$WORK/prints-discs"
    cat "$WORK"/subset-*.txt | while read -r id; do ln -sf "$WORK/prints-all/$id.dkl" "$WORK/prints-discs/$id.dkl"; done
fi
for cat in all discs; do
    [ -f "$WORK/results-$cat.tsv" ] || /usr/bin/time -l nice -n 19 "$BENCH" match --prints "$WORK/prints-$cat" \
        --queries "$WORK/queries.tsv" --out "$WORK/results-$cat.tsv" --jobs "$JOBS" 2> "$WORK/match-$cat.time"
done
cat "$WORK"/subset-*.txt > "$WORK/discs.txt"
[ -f "$WORK/truth.json" ] || $PY truth "$WORK" "$WORK/results-all.tsv" "$WORK/results-discs.tsv" --threshold "$THRESHOLD" \
    --subset "$WORK/discs.txt" 2> "$WORK/truth.log"
BIGGER=""
if [ -n "$EXTRA" ]; then
    [ -f "$WORK/extra-list.tsv" ] || $PY extra "$EXTRA" "$WORK" > "$WORK/extra.txt"
    [ -f "$WORK/prints-extra.tsv" ] || /usr/bin/time -l nice -n 19 "$BENCH" print --list "$WORK/extra-list.tsv" \
        --out "$WORK/prints-extra" --jobs "$JOBS" > "$WORK/prints-extra.tsv" 2> "$WORK/print-extra.time"
    mkdir -p "$WORK/prints-bigger"
    for f in "$WORK"/prints-all/*.dkl "$WORK"/prints-extra/*.dkl; do ln -sf "$f" "$WORK/prints-bigger/"; done
    [ -f "$WORK/results-bigger.tsv" ] || /usr/bin/time -l nice -n 19 "$BENCH" match --prints "$WORK/prints-bigger" \
        --queries "$WORK/queries.tsv" --out "$WORK/results-bigger.tsv" --jobs "$JOBS" 2> "$WORK/match-bigger.time"
    BIGGER="bigger=$WORK/results-bigger.tsv"
fi
$PY report "$WORK" library="$WORK/results-all.tsv" discs="$WORK/results-discs.tsv" $BIGGER --threshold "$THRESHOLD" \
    --mix "$WORK/subset-0.txt" ${BOOTH_CATALOGUE:+--booth-catalogue "$BOOTH_CATALOGUE"} > /dev/null
echo "report: $WORK/report.md"
