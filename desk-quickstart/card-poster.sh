#!/bin/sh
# The quick start card's own picture (D46, Nov 24, 2026): the picture behind the play button on Desk's first screen.
# The film's title frame (poster.jpg) is unreadable at card size and sat under the play button, so the card has a
# picture of its own. Two pictures, both cut from the film that ships, so they match it and can be made again with
# ffmpeg alone (no capture, no render):
#
#   card-reading.jpg  the one that ships (the owner's choice, Nov 24, 2026): Desk's window reading music, the run
#                     screen at film second 17.2. The camera holds still on the run's top half from 13.8 to 17.6
#                     (film.js); here "Reading Friday stick", "5 of 12 done" with the bar a little under half, and the
#                     song being read (one of the film's generated songs) with its wave, tempo and key. The cut is the
#                     run screen's width, from "Gig Friday" to the song card's foot, lightly softened and a step
#                     dimmed, so the play button reads on it and the heading, the bar and the wave read round it.
#   card-plain.jpg    the swap-in: the film's own ground and violet glow (its first frame, before the title fades in),
#                     softened so the video's banding does not show; no words, no mark.
#
# Both are 640 by 360 (the card shows them 176 points wide), JPEG.
#
#   sh desk-quickstart/card-poster.sh [film.mp4] [out folder]
#
# Defaults: the shipped film (desk-web/quick-start/deckie-desk-quick-start.mp4) and desk-quickstart/. The card's
# picture that ships is desk-web/quick-start/card.jpg: copy the chosen one there (one file; Windows, Linux and the
# Mac all take it from that folder).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
film=${1:-$here/../desk-web/quick-start/deckie-desk-quick-start.mp4}
out=${2:-$here}
mkdir -p "$out"
# The film is 1280 by 720; Desk's window sits at x 46 to 846.
nice -n 19 ffmpeg -v error -y -ss 17.2 -i "$film" -frames:v 1 -threads 2 \
    -vf "crop=768:432:58:178,scale=640:360:flags=lanczos,gblur=sigma=0.8,colorchannelmixer=rr=0.86:gg=0.86:bb=0.86" \
    -q:v 3 "$out/card-reading.jpg"
nice -n 19 ffmpeg -v error -y -ss 0 -i "$film" -frames:v 1 -threads 2 \
    -vf "scale=640:360:flags=lanczos,gblur=sigma=6" -q:v 4 "$out/card-plain.jpg"
ls -l "$out/card-reading.jpg" "$out/card-plain.jpg"
