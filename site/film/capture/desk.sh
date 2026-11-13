#!/bin/zsh
# Deckie Desk's own stills, from its --snapshot mode.
#   desk.sh <demo crate file> <out folder>
# Three things found on Nov 11, 2026 (macOS 26.6):
# - The Mac must be unlocked: Desk's window does not open behind the lock screen.
# - Desk must be started through `open`, and with -NSTreatUnknownArgumentsAsOpen NO: started any other way the two
#   paths on the command line are taken as files to open and the window never appears.
# - Without Screen Recording permission for Deckie Desk the frames come from the fallback (the table and the Discs
#   panel draw; the toolbar, the inspector, the selection and the import log sheet do not). The film uses the left
#   1780 x 1112 pixels of 00_open.png, which is all table.
set -e
APP="$(cd "$(dirname "$0")/../../.." && pwd)/desk-app/build/Build/Products/Release/Deckie Desk.app"
open -n -W "$APP" --env DECKIE_SNAP_ROWS=${DECKIE_SNAP_ROWS:-8} --args --snapshot "$1" "$2" -NSTreatUnknownArgumentsAsOpen NO
ls "$2"
