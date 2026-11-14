#!/bin/sh
# The recognition trial's benchmark, from one command (docs/research/w2-own-recognition-trial.md).
#
#   core/Tools/recognition-bench/run.sh DATA_DIR WORK_DIR
#       the outside set: fetches Creative Commons songs, dance clips, room responses and noise into DATA_DIR
#       (about 8 GB), then measures.
#   MUSIC=/path/to/a/folder core/Tools/recognition-bench/run.sh DATA_DIR WORK_DIR
#       any folder of music as the catalogue (every audio file under it that ffmpeg can read). Only the room
#       responses and the noise are fetched (1.3 GB). Songs are named by a hash of their path, so nothing written
#       carries a title. The threshold is the outside set's (threshold.txt), not one chosen on this music.
#
# Both write WORK_DIR/results.md (every table) and WORK_DIR/summary.json. DATA_DIR and WORK_DIR must be outside the
# repository; WORK_DIR needs about 10 MB per song plus 7 GB for the queries. Needs: Swift 6, ffmpeg, curl, and Python 3
# with numpy, scipy, soundfile and pedalboard (pip install numpy scipy soundfile pedalboard).
# Every step is skipped when its output is there, so the command can be run again after a stop. Options, as
# environment variables: JOBS (threads, default all), N and DEV_N (clips per cell on the two halves, default 100 and
# 40), SIZES (catalogue sizes for the timing table, default "250 500 1000 2500 5000 10000"; "" to skip),
# MATCH_ARGS (extra arguments for the matcher, for example --deep).
set -eu
DATA=$1; WORK=$2
HERE=$(cd "$(dirname "$0")" && pwd)
CORE=$(cd "$HERE/../.." && pwd)
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
MUSIC=${MUSIC:-}
SIZES=${SIZES-250 500 1000 2500 5000 10000}
MATCH_ARGS=${MATCH_ARGS:-}
mkdir -p "$DATA" "$WORK"

(cd "$CORE" && swift build -c release --product deckie-recog-bench)
BENCH=$(cd "$CORE" && swift build -c release --show-bin-path)/deckie-recog-bench

if [ -n "$MUSIC" ]; then
    [ -d "$DATA/rir" ] && [ -d "$DATA/noise" ] || python3 "$HERE/fetch_data.py" "$DATA" --part small
    [ -f "$WORK/songs.tsv" ] || python3 "$HERE/make_queries.py" prepare "$DATA" "$WORK" --jobs "$JOBS" --music "$MUSIC"
else
    [ -f "$DATA/.fetched" ] || { python3 "$HERE/fetch_data.py" "$DATA" && touch "$DATA/.fetched"; }
    [ -f "$WORK/songs.tsv" ] || python3 "$HERE/make_queries.py" prepare "$DATA" "$WORK" --jobs "$JOBS"
fi

if [ ! -f "$WORK/prints.tsv" ]; then
    cut -f1,2 "$WORK/songs.tsv" > "$WORK/print-list.tsv"
    # One job, so that each song's time is the time on one core.
    "$BENCH" print --list "$WORK/print-list.tsv" --out "$WORK/prints" --jobs 1 > "$WORK/prints.tsv"
fi
[ -f "$WORK/queries.tsv" ] || python3 "$HERE/make_queries.py" queries "$DATA" "$WORK" --jobs "$JOBS" --n "${N:-100}" --dev-n "${DEV_N:-40}"
awk -F'\t' '$5 == "absent" { print $1 }' "$WORK/songs.tsv" > "$WORK/absent.txt"

# Match in chunks, so a stop loses one chunk at most.
if [ ! -f "$WORK/results.tsv" ]; then
    mkdir -p "$WORK/chunks"
    [ -f "$WORK/chunks/q_000" ] || split -l 6000 -d -a 3 "$WORK/queries.tsv" "$WORK/chunks/q_"
    for q in "$WORK"/chunks/q_???; do
        r="$WORK/chunks/r_${q##*q_}"
        [ -f "$r" ] || "$BENCH" match --prints "$WORK/prints" --queries "$q" --leave-out "$WORK/absent.txt" --out "$r" --jobs "$JOBS" $MATCH_ARGS
    done
    cat "$WORK"/chunks/r_??? > "$WORK/results.tsv"
fi

# Time and false matches against catalogue size, on one core: a sample of the eval queries against the index cut
# down or padded with altered copies of real constellations (see the tool's --pad).
if [ -n "$SIZES" ]; then
    [ -f "$WORK/q_scale.tsv" ] || python3 "$HERE/scale_report.py" sample "$WORK"
    for n in $SIZES; do
        [ -f "$WORK/scale_$n.tsv" ] || "$BENCH" match --prints "$WORK/prints" --queries "$WORK/q_scale.tsv" --leave-out "$WORK/absent.txt" \
            --out "$WORK/scale_$n.tsv" --jobs 1 --limit "$n" --pad "$n" $MATCH_ARGS
    done
fi

THRESHOLD=""
[ -n "$MUSIC" ] && THRESHOLD="--threshold $(cat "$HERE/threshold.txt")"
{
    python3 "$HERE/summarise_songs.py" "$DATA" "$WORK"
    echo
    python3 "$HERE/evaluate.py" "$WORK" $THRESHOLD
    if [ -n "$SIZES" ]; then echo; python3 "$HERE/scale_report.py" report "$WORK" $THRESHOLD; fi
} > "$WORK/results.md"

# DJ mixes with ground truth, when UnmixDB has been put in DATA_DIR/unmixdb (unzipped sets from Zenodo 1422385).
if [ -z "$MUSIC" ] && [ -d "$DATA/unmixdb" ]; then
    [ -f "$WORK/unmix/queries.tsv" ] || python3 "$HERE/unmix_eval.py" prepare "$DATA/unmixdb" "$WORK"
    if [ ! -f "$WORK/unmix/results.tsv" ]; then
        "$BENCH" print --list "$WORK/unmix/print-list.tsv" --out "$WORK/unmix/prints" --jobs "$JOBS" > "$WORK/unmix/prints.tsv"
        mkdir -p "$WORK/unmix/all" && ln -sf "$WORK"/prints/*.dkl "$WORK"/unmix/prints/*.dkl "$WORK/unmix/all/"
        "$BENCH" match --prints "$WORK/unmix/all" --queries "$WORK/unmix/queries.tsv" --out "$WORK/unmix/results.tsv" --jobs "$JOBS" $MATCH_ARGS
    fi
    { echo; python3 "$HERE/unmix_eval.py" report "$WORK" "$(cat "$HERE/threshold.txt")"; } >> "$WORK/results.md"
fi
echo "results: $WORK/results.md"
