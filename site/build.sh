#!/bin/zsh
# Assemble the folder that goes on the host: site/dist/. Only what the pages use. Nothing is uploaded.
#   site/build.sh            (needs ffmpeg for the web-weight film)
set -e
cd "$(dirname "$0")"
D=dist
[ -d "$D" ] && mv "$D" "dist-old-$(date +%s)"        # never deletes: the old build is set aside for you to remove
python3 home_terms.py
mkdir -p "$D/assets" "$D/fonts"
cp icon.svg 404.html site.js site.css index.html robots.txt sitemap.xml llms.txt favicon.ico favicon.svg apple-touch-icon.png .htaccess "$D/"
cp fonts/inter.woff2 fonts/pacifico.woff2 fonts/LICENSE-Inter.txt fonts/LICENSE-Pacifico.txt "$D/fonts/"
cp assets/share-home.jpg assets/share-dictionary.jpg assets/poster.jpg assets/deckie-15s.mp4 assets/tile-song.jpg assets/tile-pick.jpg assets/tile-pin.jpg "$D/assets/"
# the pictures at the size the page shows them (the cards are about 360 px wide, the booth picture about 600)
for f in desk.jpg; do ffmpeg -hide_banner -loglevel error -y -i "assets/$f" -vf scale=900:-2 -q:v 4 "$D/assets/$f"; done

# the film at web weight: same picture size and frame rate, smaller file, starts playing before it has all arrived
nice -n 19 ffmpeg -hide_banner -loglevel error -y -i assets/deckie-explainer.mp4 -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart "$D/assets/deckie-explainer.mp4"
if [ -f dictionary/index.html ]; then mkdir -p "$D/dictionary"; (cd dictionary && find . -type f ! -name "*.py" ! -name "*.md" ! -name ".*" | while read f; do mkdir -p "../$D/dictionary/$(dirname "$f")"; cp "$f" "../$D/dictionary/$f"; done); else echo "NOTE: site/dictionary/index.html is missing; the Dictionary tab will not resolve"; fi
# every local file the home page points at must be in the build
miss=0; for u in $(grep -oE '(src|href|poster)="[^"#:]+"' index.html | sed -E 's/^[a-z]+="//; s/"$//' | sort -u); do
  [ "$u" = "./" ] && continue; t="$D/$u"; [ "${u: -1}" = "/" ] && t="$D/${u}index.html"; [ -e "$t" ] || { echo "MISSING in build: $u"; miss=1; }; done
find "$D" -type f | sort | while read f; do printf "%9d  %s\n" "$(stat -f %z "$f")" "${f#$D/}"; done
du -sh "$D" | awk '{print "total: " $1}'
exit $miss
