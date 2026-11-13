#!/usr/bin/env python3
"""Fill the home page's dictionary panel from the built dictionary page, so the two cannot drift.
   python3 site/home_terms.py     (build.sh runs it)
Reads site/dictionary/index.html (itself built from docs/vocabulary/terms.json) and rewrites the block between the
two TERMS markers in site/index.html: for each word below, its topic, the word, its plain meaning and its drawing."""
import re, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
IDS = ["bass-swap", "echo-out", "cut-on-the-one", "blend", "key-lock"]
d = (HERE / "dictionary" / "index.html").read_text(encoding="utf-8")
cards = []
for i in IDS:
    k = d.find(f'id="{i}"')
    if k < 0:
        print("home_terms: no entry", i); continue
    a, b = d.rfind("<article", 0, k), d.find("</article>", k)
    art = d[a:b]
    grab = lambda pat: (re.search(pat, art, re.S) or [None, ""])[1].strip()
    topic, word, plain = grab(r'class="dx-topic">(.*?)</span>'), grab(r'class="dx-word"><a [^>]*>(.*?)</a>'), grab(r'class="dx-def">(.*?)</p>')
    svg = re.search(r'<svg class="dx-wave".*?</svg>', art, re.S)
    svg = svg.group(0).replace('class="dx-wave"', 'class="move"') if svg else ""
    word = re.sub(r"<[^>]+>", "", word)
    cards.append(f'      <a class="pick term-card" href="dictionary/#{i}">{svg}<span class="top">{topic}</span><b>{word}</b><span class="def">{plain}</span></a>\n')
p = HERE / "index.html"
s = p.read_text(encoding="utf-8")
m = re.search(r"(<!-- TERMS -->\n)(.*?)(      <!-- /TERMS -->)", s, re.S)
if not m: sys.exit("home_terms: markers missing in index.html")
new = s[:m.start(2)] + "".join(cards) + s[m.end(2):]
if new != s: p.write_text(new, encoding="utf-8")
print(f"home_terms: {len(cards)} cards")
