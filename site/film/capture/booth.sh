#!/bin/zsh
# Record the booth walk-through in the iPad simulator. No microphone, no sound: the song is fed to the recogniser
# from a file (deck://test), played 3 percent fast so the pitch reading shows.
#   booth.sh <simulator udid> <demo crate file> <audio file of a song in that crate file> <out folder>
# Needs the Release simulator build installed (deck-app/README.md) and ffmpeg.
set -e
U=$1; C=$2; A=$3; OUT=$4; mkdir -p "$OUT"
q() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1"; }
af() { echo "deck://after?s=$1&u=$(q "$2")"; }
xcrun simctl status_bar $U override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl terminate $U io.christophershannon.deck 2>/dev/null || true; sleep 1
xcrun simctl io $U recordVideo --codec h264 --force "$OUT/booth_raw.mp4" & RP=$!; sleep 2
xcrun simctl launch $U io.christophershannon.deck -deckURL "deck://crate?path=$(q "$C") ; deck://orient?o=landscape ; deck://shuffle?amt=0 ; deck://mode?m=simple ; $(af 5 "deck://test?path=$(q "$A")&start=40&loop=1&render=$(q 'r+3')") ; $(af 26 'deck://mode?m=full') ; $(af 32 'deck://shuffle?amt=0.6') ; $(af 40 'deck://pin?i=1') ; $(af 46 'deck://scroll?to=more') ; $(af 53 'deck://search?q=night') ; $(af 60 'deck://search?q=') ; $(af 62 'deck://tab?i=1')"
sleep 70; kill -INT $RP; wait $RP
# the recording only holds frames that changed and is sideways: make it 30 frames a second, upright
nice -n 19 ffmpeg -hide_banner -loglevel error -y -i "$OUT/booth_raw.mp4" -vf "fps=30,transpose=2,scale=1600:-2" -c:v libx264 -crf 14 -pix_fmt yuv420p "$OUT/booth_cfr.mp4"
mkdir -p "$OUT/booth"; nice -n 19 ffmpeg -hide_banner -loglevel error -y -i "$OUT/booth_cfr.mp4" -q:v 3 -start_number 0 "$OUT/booth/f%04d.jpg"
echo "frames in $OUT/booth; film.js's boothF() maps film time to these (the moments are in its comments)"
