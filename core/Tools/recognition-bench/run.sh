#!/bin/sh
# The recognition trial's benchmark, from one command (docs/research/w2-own-recognition-trial.md):
#
#   core/Tools/recognition-bench/run.sh DATA_DIR WORK_DIR [extra arguments for "deckie-recog-bench match"]
#
# DATA_DIR and WORK_DIR must be outside the repository: the first receives the fetched songs, room responses and noise
# (about 9 GB), the second the decoded songs, the constellations, the queries and the results (about 25 GB).
# Needs: Swift 6, Python 3 with numpy, scipy, soundfile and pedalboard, ffmpeg and curl. Each step is skipped when
# its output is already there, so a second run only repeats what is missing; remove WORK_DIR/queries* to draw again
# (the draw is seeded, so it comes out the same).
set -eu
DATA=$1; WORK=$2; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
CORE=$(cd "$HERE/../.." && pwd)
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
mkdir -p "$DATA" "$WORK"

(cd "$CORE" && swift build -c release --product deckie-recog-bench)
BENCH=$(cd "$CORE" && swift build -c release --show-bin-path)/deckie-recog-bench

[ -f "$DATA/.fetched" ] || { python3 "$HERE/fetch_data.py" "$DATA" && touch "$DATA/.fetched"; }
[ -f "$WORK/songs.tsv" ] || python3 "$HERE/make_queries.py" prepare "$DATA" "$WORK" --jobs "$JOBS"
if [ ! -f "$WORK/prints.tsv" ]; then
    cut -f1,2 "$WORK/songs.tsv" > "$WORK/print-list.tsv"
    # One job, so that each song's time is the time on one core.
    "$BENCH" print --list "$WORK/print-list.tsv" --out "$WORK/prints" --jobs 1 > "$WORK/prints.tsv"
fi
[ -f "$WORK/queries.tsv" ] || python3 "$HERE/make_queries.py" queries "$DATA" "$WORK" --jobs "$JOBS"
awk -F'\t' '$5 == "absent" { print $1 }' "$WORK/songs.tsv" > "$WORK/absent.txt"
# One job again: the per-query times are then times on one core.
"$BENCH" match --prints "$WORK/prints" --queries "$WORK/queries.tsv" --leave-out "$WORK/absent.txt" --out "$WORK/results.tsv" --jobs "${MATCH_JOBS:-1}" "$@"
python3 "$HERE/summarise_songs.py" "$DATA" "$WORK"
python3 "$HERE/evaluate.py" "$WORK"
