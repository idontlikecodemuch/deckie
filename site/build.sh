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
# the how-to in "Desk reads your crate": Desk's quick start (720p, no sound, about 1.7 MB) and its poster, as made on
# the quick start's branch (desk-web/quick-start/); copied as they are. The page loads the film only when it is played.
cp assets/deckie-desk-quick-start.mp4 assets/quick-start-poster.jpg "$D/assets/"

# the film at web weight: same picture size and frame rate, smaller file, starts playing before it has all arrived
nice -n 19 ffmpeg -hide_banner -loglevel error -y -i assets/deckie-explainer.mp4 -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart "$D/assets/deckie-explainer.mp4"
# the demo page (deckie.io/demo): the player and the demo crate's songs as 128 kbps MP3s; CREDITS.md stays in the repository
mkdir -p "$D/demo/audio"; cp demo/index.html demo/demo.css demo/demo.js "$D/demo/"; cp demo/audio/*.mp3 "$D/demo/audio/"
# the privacy page (deckie.io/privacy), linked from every page's footer
mkdir -p "$D/privacy"; cp privacy/index.html privacy/privacy.css "$D/privacy/"
if [ -f dictionary/index.html ]; then mkdir -p "$D/dictionary"; (cd dictionary && find . -type f ! -name "*.py" ! -name "*.md" ! -name ".*" | while read f; do mkdir -p "../$D/dictionary/$(dirname "$f")"; cp "$f" "../$D/dictionary/$f"; done); else echo "NOTE: site/dictionary/index.html is missing; the Dictionary tab will not resolve"; fi
# version stamps: in every built page, each reference to a local file the browser caches gets
# ?v=<first 10 hex of the file's SHA-256>, taken from the copy in dist/: stylesheets and scripts (cached a day), and
# pictures, icons, films and the demo's songs (cached 30 days). That covers src, href, poster and srcset, <source src>
# inside <video>, the icons in the head, and the share card's absolute https://deckie.io/... address in og:image,
# twitter:image and the structured data's "image". A changed file gets a new address, so a returning visitor (or a
# crawler re-reading the page) fetches it; an unchanged file keeps its stamp and its cache. Not stamped: links to
# pages, external addresses, mailto:, and the fonts, which the CSS loads by url() and which never change (a font
# change would need a new file name). No CSS file refers to a picture, so every CSS file is final before the pages
# are stamped. The pages in site/ stay unstamped. The step fails if a stamped reference names a file not in the
# build, or if any reference to a local picture, film, song, stylesheet or script is left without a stamp.
python3 - "$D" <<'PY'
import hashlib, pathlib, re, sys
dist = pathlib.Path(sys.argv[1]).resolve()
EXT = r"(?:css|js|jpe?g|png|svg|ico|gif|webp|avif|mp4|webm|mp3|m4a)"
SITE = "https://deckie.io"
# a reference: an attribute value (src, href, poster, content), or a JSON string in the head's structured data
attr = re.compile(r'(\b(?:src|href|poster|content)="|"(?:image|logo|screenshot|thumbnailUrl|contentUrl)":\s*")'
                  r'((?:https://deckie\.io)?[^"#?\s:]+\.' + EXT + r')(")')
srcset = re.compile(r'(\bsrcset=")([^"]*)(")')
cand = re.compile(r'((?:https://deckie\.io)?[^"\'\s#?:(),<>=]+\.' + EXT + r')\b')
bad, loose = [], []
def target(page, u):
    if u.startswith(SITE): u = u[len(SITE):]
    return (dist / u.lstrip("/")) if u.startswith("/") else (page.parent / u)
for page in sorted(dist.rglob("*.html")):
    rel = page.relative_to(dist)
    def v(u):
        f = target(page, u).resolve()
        if not f.is_file() or dist not in f.parents:
            bad.append(f"{rel}: {u}"); return None
        return hashlib.sha256(f.read_bytes()).hexdigest()[:10]
    def stamp(m):
        h = v(m.group(2))
        return m.group(0) if h is None else f"{m.group(1)}{m.group(2)}?v={h}{m.group(3)}"
    def stamp_set(m):
        def one(part):
            bits = part.strip().split(None, 1)
            if not bits or not re.fullmatch(r"(?:https://deckie\.io)?[^#?\s:]+\." + EXT, bits[0]): return part.strip()
            h = v(bits[0]); bits[0] = bits[0] if h is None else f"{bits[0]}?v={h}"
            return " ".join(bits)
        return m.group(1) + ", ".join(one(p) for p in m.group(2).split(",")) + m.group(3)
    src = page.read_text(encoding="utf-8")
    out = srcset.sub(stamp_set, attr.sub(stamp, src))
    if out != src:
        page.write_text(out, encoding="utf-8")
        for u in re.findall(r'[^"\s,]+\?v=[0-9a-f]{10}', out): print(f"stamp  {rel}  {u}")
    # nothing local left unstamped: every local file name with one of these endings, anywhere in the page outside an
    # HTML comment (the comments name files in passing), must carry ?v=
    body = re.sub(r"<!--.*?-->", "", out, flags=re.S)
    for m in cand.finditer(body):
        u, after = m.group(1), body[m.end():m.end() + 13]
        if u.startswith("//") or (u.startswith("http") and not u.startswith(SITE)): continue
        if not re.match(r"\?v=[0-9a-f]{10}", after): loose.append(f"{rel}: {u}")
if bad: sys.exit("stamp: no such file in the build: " + ", ".join(bad))
if loose: sys.exit("stamp: a local file is referenced without a ?v= stamp: " + ", ".join(sorted(set(loose))))
PY
# every local file the home page points at must be in the build (read from the built page; a ?v= stamp is not part of the file name)
miss=0; for u in $(grep -oE '(src|href|poster)="[^"#:]+"' "$D/index.html" | sed -E 's/^[a-z]+="//; s/"$//; s/\?.*$//' | sort -u); do
  [ "$u" = "./" ] && continue; t="$D/$u"; [ "${u: -1}" = "/" ] && t="$D/${u}index.html"; [ -e "$t" ] || { echo "MISSING in build: $u"; miss=1; }; done
find "$D" -type f | sort | while read f; do printf "%9d  %s\n" "$(stat -f %z "$f")" "${f#$D/}"; done
du -sh "$D" | awk '{print "total: " $1}'
exit $miss
