#!/bin/sh
# The quick start card's own picture (D46, Nov 24, 2026): the picture behind the play button on Desk's first screen.
# The film's title frame (poster.jpg) is unreadable at card size and sat under the play button, so the card has a
# picture of its own with nothing to read behind the button. Two candidates, both cut from the film that ships, so
# they match it and can be made again with ffmpeg alone (no capture, no render):
#
#   card-window.jpg  Desk's window from the film, on the crate's songs (film second 45.6: the window is fully back
#                    and the pointer has not come in yet; film.js, seek), cut to 16:9 round the window, softened and
#                    dimmed so no text is half legible and the play button reads on it.
#   card-plain.jpg   the film's own ground and violet glow (its first frame, before the title fades in), softened
#                    so the video's banding does not show: no words, no mark.
#
# Both are 640 by 360 (the card shows them 176 points wide), JPEG.
#
#   sh desk-quickstart/card-poster.sh [film.mp4] [out folder]
#
# Defaults: the shipped film (desk-web/quick-start/deckie-desk-quick-start.mp4) and desk-quickstart/. The card's
# picture that ships is desk-web/quick-start/card.jpg: copy the chosen candidate there (one file; Windows, Linux and
# the Mac all take it from that folder).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
film=${1:-$here/../desk-web/quick-start/deckie-desk-quick-start.mp4}
out=${2:-$here}
mkdir -p "$out"
# The film is 1280 by 720; the window sits at x 46 to 846 with its title bar from y 98. The cut keeps a little of the
# dark ground round the window, so it reads as a window.
nice -n 19 ffmpeg -v error -y -ss 45.6 -i "$film" -frames:v 1 -threads 2 \
    -vf "crop=864:486:14:84,scale=640:360:flags=lanczos,gblur=sigma=2.2,colorchannelmixer=rr=0.68:gg=0.68:bb=0.68" \
    -q:v 4 "$out/card-window.jpg"
nice -n 19 ffmpeg -v error -y -ss 0 -i "$film" -frames:v 1 -threads 2 \
    -vf "scale=640:360:flags=lanczos,gblur=sigma=6" -q:v 4 "$out/card-plain.jpg"
ls -l "$out/card-window.jpg" "$out/card-plain.jpg"
