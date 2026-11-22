#!/bin/zsh
# The quick start's iPad picture: Deckie on the iPad simulator, Booth naming a song of the crate file the capture
# exported (live.mjs), with its picks beside it. No microphone and no sound: the song is fed to the listener from its
# file (deck://test, the app's Debug-only test hook, as site/film/capture/booth.sh does), played 2 percent fast so the
# pitch shows, and Deckie's own recogniser names it (deck://hearing?with=deckie: the crate file Desk made on this Mac
# carries Deckie's fingerprints, not Apple's signatures).
#   ipad.sh <simulator udid> <work folder>
# Needs a Debug build of the iPad app installed on that simulator (deck-app/README.md), and the capture's
# <work>/Documents/Gig Friday.deckie and <work>/songs. Writes <work>/ipad.png, landscape. The app is quit again after,
# and the status bar given back.
set -e
U=$1; W=$2
C="$W/Documents/Gig Friday.deckie"
A="$W/songs/05 Ember Motel - Static Garden.mp3"
q() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1"; }
af() { echo "deck://after?s=$1&u=$(q "$2")"; }
xcrun simctl status_bar $U override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl terminate $U io.deckie.booth 2>/dev/null || true; sleep 1
xcrun simctl launch $U io.deckie.booth -deckURL "deck://crate?path=$(q "$C") ; deck://orient?o=landscape ; deck://hearing?with=deckie ; deck://shuffle?amt=0.5 ; deck://mode?m=simple ; $(af 4 "deck://test?path=$(q "$A")&start=40&loop=1&render=$(q 'r+2')")"
sleep ${IPAD_WAIT:-30}
xcrun simctl io $U screenshot --type png "$W/ipad-raw.png"
xcrun simctl terminate $U io.deckie.booth 2>/dev/null || true
xcrun simctl status_bar $U clear
# The screenshot is taken as the device stands (portrait); the app is landscape, so it is turned upright.
sips -r 270 "$W/ipad-raw.png" --out "$W/ipad.png" >/dev/null
echo "wrote $W/ipad.png"
