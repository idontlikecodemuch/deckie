#!/bin/zsh
# Deckie Desk's own stills, from its --snapshot mode.
#   desk.sh <demo crate file> <out folder>
# The demo crate file is imported into scratch storage (DECKIE_DESK_HOME, by default .scratch/desk-film-home in the
# repository, emptied first), never Desk's real storage; the snapshot then opens it, the only crate there.
# Found on Nov 11, 2026 (macOS 26.6), and Nov 24, 2026:
# - The Mac must be unlocked: Desk's window does not open behind the lock screen.
# - Desk must be started through `open` (desk-app/tools/open-desk.sh), with -NSTreatUnknownArgumentsAsOpen NO.
# - Without Screen Recording permission for Deckie Desk the frames come from the fallback (the table and the Discs
#   panel draw; the toolbar, the inspector, the selection and the import log sheet do not). The film uses the left
#   1780 x 1112 pixels of 00_open.png, which is all table. With it, and a signed build (desk-app/tools/build-signed.sh),
#   they are the window server's whole window; Desk prints which at the start.
set -euo pipefail
(( $# == 2 )) || { echo "usage: $0 <demo crate file> <out folder>" >&2; exit 64; }
repo="$(cd "$(dirname "$0")/../../.." && pwd)"
crate="${1:A}"; out="${2:A}"
home="${DECKIE_DESK_HOME:-$repo/.scratch/desk-film-home}"
[[ "$home" == "$HOME/Library/Application Support/Deckie Desk"* ]] && { echo "desk.sh: that is Desk's real storage" >&2; exit 1; }
rm -rf "$home"; mkdir -p "$home"
export DECKIE_DESK_HOME="$home" DECKIE_LOOKUP_OFF=1 DECKIE_NO_BOXES=1 DECKIE_SNAP_ROWS=${DECKIE_SNAP_ROWS:-8}
APP="$repo/desk-app/build/Build/Products/Release/Deckie Desk.app"
"$APP/Contents/MacOS/Deckie Desk" --import "$crate"
DECKIE_DESK_APP="$APP" "$repo/desk-app/tools/open-desk.sh" "$out.log" --snapshot "$out"
ls "$out"
