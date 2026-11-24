#!/bin/zsh
# Deckie Desk launched through LaunchServices (`open`), the way the window server's pictures need: started so, macOS
# asks about Deckie Desk itself for Screen Recording; its binary run from a shell, macOS asks about the shell's app and
# the pictures are the ones the app draws itself (ScreenRecording.swift).
#
#   DECKIE_DESK_HOME=<scratch folder> desk-app/tools/open-desk.sh <log file> <Desk's arguments...>
#
# e.g.  DECKIE_DESK_HOME=$PWD/.scratch/home DECKIE_LOOKUP_OFF=1 DECKIE_NO_BOXES=1 \
#         desk-app/tools/open-desk.sh .scratch/walk.log --quick-start-walk $PWD/.scratch/walk
#
# - Every DECKIE_* and ORT_* variable of this shell reaches the app (open --env); DECKIE_DESK_HOME must be one, and
#   the picture modes print the storage they use and refuse Desk's real storage.
# - A new instance (open -n), so a Desk already open is left alone; this waits until it quits (open -W).
# - What it prints goes to the log file (stdout) and <log file>.stderr, both printed here once it has quit; the
#   picture modes print their process id first, for stopping one by its id.
# - Paths in the arguments should be absolute: the app does not start in this folder.
# - DECKIE_DESK_APP names another app; by default the Release build in desk-app/build (tools/build-signed.sh).
set -euo pipefail
(( $# >= 2 )) || { echo "usage: DECKIE_DESK_HOME=<scratch folder> $0 <log file> <Desk's arguments...>" >&2; exit 64; }
log="$1"; shift
app="${DECKIE_DESK_APP:-$(cd "$(dirname "$0")/.." && pwd)/build/Build/Products/Release/Deckie Desk.app}"
[[ -d "$app" ]] || { echo "open-desk: no app at $app" >&2; exit 1; }
[[ "${DECKIE_DESK_HOME:-}" == /* ]] || { echo "open-desk: set DECKIE_DESK_HOME to a scratch folder, as an absolute path" >&2; exit 1; }

envs=()
while IFS= read -r line; do envs+=(--env "$line"); done < <(env | grep -E '^(DECKIE|ORT)_[A-Z0-9_]*=')
mkdir -p "$(dirname "$log")"
: > "$log"; : > "$log.stderr"
open -n -W --stdout "$log" --stderr "$log.stderr" "${envs[@]}" "$app" --args "$@" -NSTreatUnknownArgumentsAsOpen NO
cat "$log"
[[ -s "$log.stderr" ]] && { echo "--- stderr"; cat "$log.stderr"; }
exit 0
