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
# version stamps: in every built page, each link to a local CSS or JS file gets ?v=<first 10 hex of the file's SHA-256>,
# taken from the copy in dist/. The host may cache these files for a day; a new stamp makes a returning visitor fetch
# the new file, and an unchanged file keeps its stamp and its cache. The pages in site/ stay unstamped.
python3 - "$D" <<'PY'
import hashlib, pathlib, re, sys
dist = pathlib.Path(sys.argv[1]).resolve()
ref = re.compile(r'((?:src|href)=")([^"#?:]+\.(?:css|js))(")')
bad = []
for page in sorted(dist.rglob("*.html")):
    def stamp(m):
        u = m.group(2)
        f = (dist / u.lstrip("/")) if u.startswith("/") else (page.parent / u)
        if not f.resolve().is_file():
            bad.append(f"{page.relative_to(dist)}: {u}"); return m.group(0)
        v = hashlib.sha256(f.read_bytes()).hexdigest()[:10]
        return f"{m.group(1)}{u}?v={v}{m.group(3)}"
    src = page.read_text(encoding="utf-8")
    out = ref.sub(stamp, src)
    if out != src:
        page.write_text(out, encoding="utf-8")
        for line in out.splitlines():
            if "?v=" in line: print(f"stamp  {page.relative_to(dist)}  {line.strip()}")
if bad: sys.exit("stamp: no such file in the build: " + ", ".join(bad))
PY
# every local file the home page points at must be in the build (read from the built page; a ?v= stamp is not part of the file name)
miss=0; for u in $(grep -oE '(src|href|poster)="[^"#:]+"' "$D/index.html" | sed -E 's/^[a-z]+="//; s/"$//; s/\?.*$//' | sort -u); do
  [ "$u" = "./" ] && continue; t="$D/$u"; [ "${u: -1}" = "/" ] && t="$D/${u}index.html"; [ -e "$t" ] || { echo "MISSING in build: $u"; miss=1; }; done
find "$D" -type f | sort | while read f; do printf "%9d  %s\n" "$(stat -f %z "$f")" "${f#$D/}"; done
du -sh "$D" | awk '{print "total: " $1}'
exit $miss
