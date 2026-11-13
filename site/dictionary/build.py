#!/usr/bin/env python3
"""Build the public dictionary page from the vocabulary source.

    python3 site/dictionary/build.py           # write site/dictionary/index.html, sync the internal page's JSON
    python3 site/dictionary/build.py --check   # change nothing; exit 1 if either file is out of date

Source: docs/vocabulary/terms.json, the single source for every word Deckie uses. The internal page,
docs/vocabulary/index.html, carries the same JSON inside <script id="terms-data">; this script rewrites that block
too, so the two pages never drift. Python 3 standard library only, no network, no build step for the page itself.

Fields of a term, as this page reads them:
  id            the slug, and the entry's anchor (#id)
  term          the headword: the word a person would look up, not a sentence or an internal label
  gloss         optional: a few words shown after the headword in brackets, "Semitone (about a 6% pitch change)"
  group         the topic, one of "groups"; shown as the card's small top line and used by the topic chips
  aliases       other names; up to three show under the headword, a longer list on its own "Also called" line
  plain         the meaning in plain words: it leads the card
  expert        how DJs say and use it: shown as "On the decks", the card's second line
  no_dj_line    optional, true: the entry has no DJ usage worth a line (a Deckie screen word), so none is shown
  deckie        what Deckie does with it: the last and smallest note, always shown; "Planned: " at the start
                becomes the Planned mark, which appears nowhere else
  source        optional: heard / tutorial / ours; a tiny chip on the card's top line
  status        optional, "planned"
  related       ids of related terms; links to hidden terms follow their merged_into
  public        false hides the term from this page (the internal page still shows it, with internal_note)
  merged_into   optional, on a hidden term: the public term that now covers it; the hidden id stays a working
                anchor inside that entry, so old links land
  old_ids       optional: ids the term had before it was renamed; each stays a working anchor inside the entry

The page: a featured card (the word of the day, picked from the date by dictionary.js; a fixed first word without
script), the search and A to Z bar, topic chips, then every public term as a card in A to Z order. The cards are
patterned on Deckie Booth's pick card (deck-app, SuggestionsView.swift, NextRow). Every word is real HTML, so the
page reads completely with script off; dictionary.js only adds search, the topic filter, the word of the day, the
entrance and deep-link handling. Styles are in dictionary.css, loaded after the shared site.css.
"""
import html
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs" / "vocabulary" / "terms.json"
INTERNAL = ROOT / "docs" / "vocabulary" / "index.html"
OUT = Path(__file__).resolve().parent / "index.html"
CANONICAL = "https://deckie.io/dictionary/"

SOURCE_LABEL = {"heard": "Heard from DJs", "tutorial": "Tutorial word", "ours": "Deckie’s own phrase"}
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December"]
NBSP = "\u00a0"
# Names and terms that are never split across lines (letter V, section 7e).
KEEP_TOGETHER = ["Deckie Desk", "Deckie Booth", "crate file", "pitch fader", "Camelot wheel", "key lock", "Key lock",
                 "iCloud Drive", "Mixed In Key", "Open Key"]
START = ["bpm", "beatmatching", "pitch-fader", "blend", "phrase", "key", "crate"]   # the words a new DJ meets first
FIRST_WORD = "beatmatching"   # the featured card without script


def smart_quotes(s):
    """Straight quotes to typographic ones: an opening quote after the start, a space or a bracket."""
    s = re.sub(r'(^|[\s(\[\u2014])"', "\\1\u201c", s)
    s = s.replace('"', "\u201d")
    s = re.sub(r"(^|[\s(\[])'", "\\1\u2018", s)
    return s.replace("'", "\u2019")


def tie(s, last_pair=True):
    """The line-break rule in characters: names held together; the first word of each new sentence held to the
    word after it, so it never sits alone at the end of a line; and the last two words of a block held together."""
    for name in KEEP_TOGETHER:
        s = s.replace(name, name.replace(" ", NBSP))
    # a hyphenated word is not split at its hyphen (U+2011, the non-breaking hyphen)
    s = re.sub(r"(?<=\w)-(?=\w)", "\u2011", s)
    # a short word (an article, a preposition) stays with the word after it
    s = re.sub(r"(?<![\w\u2019'-])(a|an|the|A|An|The|to|of|in|on|at|by|or|as|no|is) (?=\S)", "\\1" + NBSP, s)
    # the first word of a new sentence stays with the word after it (run twice: matches cannot overlap)
    for _ in range(2):
        s = re.sub(r"([.?!;:][\u201d\u2019)]?) ([^\s]{1,12}) ", "\\1 \\2" + NBSP, s)
    if last_pair:
        parts = s.rsplit(" ", 1)
        if len(parts) == 2 and len(parts[1]) < 16:
            s = parts[0] + NBSP + parts[1]
    return s


def text(s, last_pair=True):
    return html.escape(tie(smart_quotes(s), last_pair), quote=False)


def script_words(out):
    """"Deckie" alone, the app names whole, and "you"/"your" in the script face, as in every heading on the site."""
    out = re.sub(r"\b([Yy]ou|[Yy]our)\b", r'<span class="you">\1</span>', out)
    return re.sub(r"Deckie(?:\u00a0(Desk|Booth))?", lambda m: '<span class="you name">' + m.group(0) + "</span>", out)


def headword_html(t):
    """The headword, then its gloss in brackets, held to it so the bracket never starts a line on its own."""
    word = script_words(html.escape(tie(smart_quotes(t["term"]), False), quote=False))
    if not t.get("gloss"):
        return word
    return word + NBSP + '<span class="dx-gloss">(' + text(t["gloss"]) + ")</span>"


def split_alias(a):
    """"switch lows (forums)" -> ("switch lows", "forums")."""
    m = re.fullmatch(r"(.*?)\s*\((.+)\)", a)
    return (m.group(1), m.group(2)) if m and m.group(1) else (a, None)


def join_list(items):
    """Comma-separated. A one-word last item is held to the one before it; a longer one keeps its last two words
    together. Either way no word sits alone on a line, and no chain is held so long that it has to break anyway."""
    items = list(items)
    if len(items) < 2:
        return "".join(items)
    last = items[-1]
    plain = re.sub(r"<[^>]+>", "", last)
    if not re.search(r"[ \u00a0]", plain):
        return ", ".join(items[:-1]) + "," + NBSP + last
    spaces = [m.start() for m in re.finditer(r" (?![^<]*>)", last)]
    if spaces:
        k = spaces[-1]
        last = last[:k] + NBSP + last[k + 1:]
    return ", ".join(items[:-1]) + ", " + last


def deckie_html(s):
    if s.startswith("Planned: "):
        return '<span class="dx-planned">Planned</span> ' + text(s[len("Planned: "):])
    if s.startswith("Planned, "):
        return '<span class="dx-planned">Planned</span> ' + text(s[len("Planned, "):][0].upper() + s[len("Planned, ") + 1:])
    return text(s)


# ------------------------------------------------------------------ the small drawing on a move's card
# Where Deckie Booth's pick card has its join wave (the end of the playing song over the start of the next), a move's
# card has a small drawing of the move: the old song on the top lane, the new one below, the amber line where the
# new one takes over. 24 slots; a level from 0 to 1 per slot and lane. Drawn here, as inline SVG, so it shows with
# script off; it is decoration and hidden from screen readers (the words say the same thing).
N = 24


def lin(i, a, b, v0, v1):
    if i <= a: return v0
    if i >= b: return v1
    return v0 + (v1 - v0) * (i - a) / (b - a)


def on(i, a, b, v=1.0):
    return v if a <= i < b else 0.0


MOVES = {
    "long-blend":  (lambda i: lin(i, 6, 20, 1, 0),  lambda i: lin(i, 4, 18, 0, 1), 12, {}),
    "blend":       (lambda i: lin(i, 8, 17, 1, 0),  lambda i: lin(i, 7, 16, 0, 1), 12, {}),
    "short-blend": (lambda i: lin(i, 11, 14, 1, 0), lambda i: lin(i, 10, 13, 0, 1), 12, {}),
    "bass-swap":   (lambda i: 1 if i < 12 else (0.32 if i < 16 else 0), lambda i: 0 if i < 6 else (0.32 if i < 12 else 1), 12, {}),
    "fade":        (lambda i: lin(i, 3, 20, 1, 0),  lambda i: lin(i, 4, 21, 0, 1), 12, {}),
    "tempo-ramp":  (lambda i: lin(i, 6, 18, 1, 0),  lambda i: lin(i, 6, 18, 0, 1), 12, {"stretchB": True}),
    "filter-fade": (lambda i: lin(i, 6, 18, 1, 0.12), lambda i: lin(i, 8, 16, 0, 1), 12, {"thinA": (6, 18)}),
    "echo-out":    (lambda i: 1 if i < 12 else {13: .62, 15: .42, 17: .26, 19: .14}.get(i, 0), lambda i: on(i, 12, N), 12, {}),
    "reverb-wash": (lambda i: 1 if i < 12 else lin(i, 12, 23, .75, .05), lambda i: on(i, 12, N), 12, {"washA": 12}),
    "loop-roll":   (lambda i: on(i, 0, 12), lambda i: on(i, 12, N), 12, {"rollA": (7, 12)}),
    "hard-cut":    (lambda i: on(i, 0, 12), lambda i: on(i, 12, N), 12, {}),
    "cut-on-the-one": (lambda i: on(i, 0, 12), lambda i: on(i, 12, N), 12, {"oneB": 12}),
    "slam":        (lambda i: on(i, 0, 12), lambda i: on(i, 12, N) * (1.25 if i == 12 else 1), 12, {}),
    "chop":        (lambda i: 1 if i < 8 else (1 if i < 16 and (i // 2) % 2 == 0 else 0),
                    lambda i: 0 if i < 8 else (1 if i >= 16 or (i // 2) % 2 == 1 else 0), 16, {}),
    "backspin":    (lambda i: 1 if i < 9 else {9: .9, 10: .55, 11: .25}.get(i, 0), lambda i: on(i, 12, N), 12, {"spinA": (9, 12)}),
    "vinyl-brake": (lambda i: 1 if i < 6 else ({6: .85, 7: .7, 9: .45, 11: .2}.get(i, 0)), lambda i: on(i, 12, N), 12, {}),
    "tease":       (lambda i: on(i, 0, 15), lambda i: {5: .8, 6: .6}.get(i, 0) + on(i, 15, N), 15, {}),
    "half-time":   (lambda i: lin(i, 8, 17, 1, 0), lambda i: lin(i, 7, 16, 0, 1) if i % 2 == 0 else 0, 12, {}),
    "scratch-in":  (lambda i: on(i, 0, 12), lambda i: {10: .95, 11: .5}.get(i, 0) + on(i, 12, N), 12, {"scratchB": (10, 12)}),
    "echo-in":     (lambda i: lin(i, 12, 16, 1, 0), lambda i: {6: .22, 8: .36, 10: .55}.get(i, 0) + on(i, 12, N), 12, {}),
    "acapella":    (lambda i: 1.0, lambda i: 0.42 if 8 <= i < 21 else 0, 8, {"smoothB": True}),
}


def tex(i):
    """The beat texture inside a lane: a fixed value per bar, every fourth taller, as the background wave."""
    h = math.sin(i * 127.1 + 311.7) * 43758.5453
    h -= math.floor(h)
    return (0.62 + 0.38 * h) * (1 if i % 4 == 0 else 0.84)


def move_svg(tid):
    if tid not in MOVES:
        return ""
    fa, fb, join, opt = MOVES[tid]
    step, w, lane, gap, top = 4.5, 2.4, 22, 8, 2
    W = 8 + N * step
    out = []
    for k, f in ((0, fa), (1, fb)):
        mid = top + k * (lane + gap) + lane / 2
        out.append(f'<rect x="2" y="{top + k * (lane + gap)}" width="{W - 4:.0f}" height="{lane}" rx="5" class="ln"/>')
        cls = "a" if k == 0 else "b"
        for i in range(N):
            v = min(1.0, f(i))
            if v <= 0.01:
                continue
            amp = v * (lane / 2 - 2)
            amp *= 1 if (opt.get("smoothB") and k == 1) else tex(i)
            x = 4 + i * step
            op = ""
            if k == 0 and "thinA" in opt and i >= opt["thinA"][0]:
                op = f' opacity="{max(0.35, v):.2f}"'
            if k == 0 and "washA" in opt and i >= opt["washA"]:
                op = ' opacity="0.45"'
            if k == 1 and "stretchB" in opt and i < 18:
                x -= (18 - i) * 0.35 if i > 6 else 0
            if (k == 0 and "rollA" in opt and opt["rollA"][0] <= i < opt["rollA"][1]) or \
               (k == 1 and "scratchB" in opt and opt["scratchB"][0] <= i < opt["scratchB"][1]):
                for d in (0, step / 2):
                    out.append(f'<rect x="{x + d:.1f}" y="{mid - amp:.1f}" width="1.3" height="{2 * amp:.1f}" rx="0.6" class="{cls}"{op}/>')
                continue
            if k == 0 and "spinA" in opt and opt["spinA"][0] <= i < opt["spinA"][1]:
                out.append(f'<rect x="{x:.1f}" y="{mid - amp:.1f}" width="{w}" height="{2 * amp:.1f}" rx="1.2" class="{cls}" transform="skewX(-18)" transform-origin="{x:.1f} {mid:.1f}"/>')
                continue
            out.append(f'<rect x="{x:.1f}" y="{mid - amp:.1f}" width="{w}" height="{2 * amp:.1f}" rx="1.2" class="{cls}"{op}/>')
        if k == 1 and "oneB" in opt:
            out.append(f'<circle cx="{4 + opt["oneB"] * step + w / 2:.1f}" cy="{mid - lane / 2 + 3:.1f}" r="1.6" class="j"/>')
    jx = 4 + join * step - 1.2
    H = top * 2 + lane * 2 + gap
    out.append(f'<rect x="{jx:.1f}" y="0" width="1" height="{H}" class="j"/>')
    out.append(f'<path d="M{jx - 2.5:.1f} {H}l3 -4l3 4z" class="j"/>')
    return (f'<svg class="dx-wave" viewBox="0 0 {W:.0f} {H}" width="{W:.0f}" height="{H}" aria-hidden="true" '
            f'focusable="false">' + "".join(out) + "</svg>")


# ------------------------------------------------------------------ data
def load():
    data = json.loads(SRC.read_text(encoding="utf-8"))
    ids = [t["id"] for t in data["terms"]]
    every = ids + [o for t in data["terms"] for o in t.get("old_ids", [])]
    if len(every) != len(set(every)):
        sys.exit("terms.json: duplicate ids (old_ids included)")
    groups = {g["id"] for g in data["groups"]}
    pub = {t["id"] for t in data["terms"] if t.get("public", True) is not False}
    for t in data["terms"]:
        if t["group"] not in groups:
            sys.exit(f"terms.json: {t['id']} has unknown group {t['group']}")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", t["id"]):
            sys.exit(f"terms.json: id {t['id']!r} is not a slug")
        for r in t["related"]:
            if r not in ids:
                sys.exit(f"terms.json: {t['id']} relates to missing {r}")
        if t.get("merged_into") and t["merged_into"] not in pub:
            sys.exit(f"terms.json: {t['id']} is merged into {t['merged_into']}, which is not public")
    return data


def build_page(data):
    public = [t for t in data["terms"] if t.get("public", True) is not False]
    by_id = {t["id"]: t for t in public}
    all_by_id = {t["id"]: t for t in data["terms"]}
    glabel = {g["id"]: g["label"] for g in data["groups"]}
    y, m, d = (int(x) for x in data["updated"].split("-"))
    updated_text = f"{d} {MONTHS[m - 1]} {y}"
    groups = [g for g in data["groups"] if any(t["group"] == g["id"] for t in public)]

    # anchors that must keep landing: hidden terms (on the term that covers them) and old ids
    extra = {}
    for t in data["terms"]:
        if t.get("public", True) is False and t.get("merged_into"):
            extra.setdefault(t["merged_into"], []).append(t["id"])
        if t["id"] in by_id:
            extra.setdefault(t["id"], []).extend(t.get("old_ids", []))
    redirect = {}
    for tid, olds in extra.items():
        for o in olds:
            redirect[o] = tid

    def rel_ids(t):
        out = []
        for r in t["related"]:
            r = r if r in by_id else (all_by_id.get(r, {}).get("merged_into"))
            if r and r in by_id and r != t["id"] and r not in out:
                out.append(r)
        return out

    def body(t, featured=False):
        """Everything below the card's head, always shown: the other names, the meaning, "On the decks", then on
        compact lines "See also" and, last and smallest, "In Deckie". Up to three other names sit under the
        headword (the pick card's artist line), names only, so the meaning stays near the top; a longer list moves,
        with its notes on where each name comes from, to its own "Also called" line under the DJ line instead, so no
        name is shown twice."""
        names = [split_alias(a) for a in t["aliases"]]
        names = [(n, note) for n, note in names if n.lower() != t["term"].lower()]
        seen, uniq = set(), []
        for n, note in names:
            if n.lower() not in seen:
                seen.add(n.lower()); uniq.append((n, note))
        def item(n, note):
            return ('<span class="dx-alias' + (" nw" if len(n) <= 20 else "") + '">' + text(n, False) + "</span>"
                    + (NBSP + '<span class="dx-note-src">(' + text(note) + ")</span>" if note else ""))
        short_line = len(uniq) <= 3
        parts = []
        if uniq and short_line:
            parts.append('  <p class="dx-aka"><span class="dx-k">Also</span>' + NBSP
                         + join_list(item(n, None) for n, _ in uniq) + "</p>\n")
        parts.append(f'  <p class="dx-def">{text(t["plain"])}</p>\n')
        if t.get("expert") and not t.get("no_dj_line"):
            parts.append(f'  <p class="dx-dj"><span class="dx-k">On the decks</span>{NBSP}{text(t["expert"])}</p>\n')
        if uniq and not short_line:
            parts.append('  <p class="dx-names"><span class="dx-k">Also called</span>' + NBSP
                         + join_list(item(n, note) for n, note in uniq) + "</p>\n")
        rel = rel_ids(t)
        if rel:
            parts.append('  <p class="dx-see"><span class="dx-k">See also</span> '
                         + " ".join('<a href="#' + r + '">' + text(by_id[r]["term"], False) + "</a>" for r in rel) + "</p>\n")
        parts.append(f'  <p class="dx-in"><span class="dx-k">In Deckie</span>{NBSP}{deckie_html(t["deckie"])}</p>\n')
        return "".join(parts)

    def head(t, featured=False):
        src = (' <span class="dx-src">' + html.escape(SOURCE_LABEL[t["source"]]) + "</span>") if t.get("source") else ""
        tag = "h2" if featured else "h3"
        href = "#" + t["id"]
        return (f'  <p class="dx-top"><span class="dx-topic">{text(glabel[t["group"]], False)}</span>{src}</p>\n'
                f'  <{tag} class="dx-word"><a href="{href}">{headword_html(t)}</a></{tag}>\n'
                + (("  " + move_svg(t["id"]) + "\n") if t["id"] in MOVES else ""))

    def card(t):
        anchors = "".join(f'<span class="dx-anchor" id="{o}"></span>' for o in extra.get(t["id"], []))
        words = " ".join([t["term"], t.get("gloss", "")] + [split_alias(a)[0] for a in t["aliases"]])
        pool = "1" if t["group"] in ("moves", "tempo", "key", "structure") else "0"
        mv = " dx-has-wave" if t["id"] in MOVES else ""
        return (f'<article class="dx-card{mv}" id="{t["id"]}" data-group="{t["group"]}" data-pool="{pool}" '
                f'data-words="{html.escape(words.lower())}">\n'
                + (f"  {anchors}\n" if anchors else "") + head(t) + body(t) + "</article>\n")

    # A to Z, as a dictionary reader expects; the topics are a filter. Words starting with a digit go under "#".
    def letter(t):
        c = t["term"].lstrip("“\"'(")[0].upper()
        return c if c.isalpha() else "#"
    ordered = sorted(public, key=lambda t: (letter(t) != "#", re.sub(r"[^a-z0-9 ]", "", t["term"].lower())))
    lid = lambda L: "l-num" if L == "#" else "l-" + L.lower()
    cards, have, last = [], set(), None
    for t in ordered:
        L = letter(t)
        if L != last:
            cards.append(f'<h2 class="dx-letter" id="{lid(L)}">{L}</h2>\n')
            have.add(L)
            last = L
        cards.append(card(t))
    az = "".join(
        (f'<a href="#{lid(L)}">{L}</a>' if L in have else f'<span class="off" aria-hidden="true">{L}</span>')
        for L in (["#"] if "#" in have else []) + [chr(c) for c in range(65, 91)])
    start = "".join(f'<a class="dx-chip" href="#{i}">{text(by_id[i]["term"], False)}</a>' for i in START if i in by_id)
    chips = '<button type="button" class="dx-chip" data-g="all" aria-pressed="true">All</button>' + "".join(
        f'<button type="button" class="dx-chip" data-g="{g["id"]}" aria-pressed="false">{text(g["label"], False)}</button>'
        for g in groups)
    f = by_id[FIRST_WORD]
    featured = (f'<article class="dx-card dx-pinned in" id="dx-featured-card" data-for="{f["id"]}" data-group="{f["group"]}">\n'
                + head(f, featured=True) + body(f, featured=True) + "</article>\n")

    ld = {
        "@context": "https://schema.org",
        "@type": "DefinedTermSet",
        "@id": CANONICAL,
        "name": "The Deckie dictionary",
        "url": CANONICAL,
        "inLanguage": "en",
        "dateModified": data["updated"],
        "description": "DJ speak, in plain words: a dictionary for anyone. Each word in plain words, then how DJs use it, with a short note on what Deckie, a DJ booth companion, does with it.",
        "publisher": {"@type": "Organization", "name": "App Hold Media"},
        "hasDefinedTerm": [
            {"@type": "DefinedTerm", "@id": CANONICAL + "#" + t["id"], "url": CANONICAL + "#" + t["id"],
             "name": smart_quotes(t["term"]), "description": smart_quotes(t["plain"]),
             **({"alternateName": [smart_quotes(split_alias(a)[0]) for a in t["aliases"]]} if t["aliases"] else {}),
             "inDefinedTermSet": CANONICAL}
            for t in ordered
        ],
    }
    ld_json = json.dumps(ld, ensure_ascii=False, indent=1).replace("</", "<\\/")
    redirect_json = json.dumps(redirect, sort_keys=True)

    return TEMPLATE.format(
        count=len(public), updated_iso=data["updated"], updated_text=updated_text, az=az, chips=chips,
        cards="".join(cards), ld=ld_json, start=start, featured=featured, redirect=redirect_json)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>The Deckie dictionary: DJ speak, in plain words</title>
<meta name="description" content="Every DJ starts somewhere. DJ speak, in plain words: {count} words for mixing, tempo, key and song structure, then how DJs use them.">
<meta name="theme-color" content="#0f0a17">
<link rel="canonical" href="https://deckie.io/dictionary/">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Deckie">
<meta property="og:url" content="https://deckie.io/dictionary/">
<meta property="og:title" content="The Deckie dictionary: DJ speak, in plain words">
<meta property="og:description" content="Every DJ starts somewhere. DJ speak, in plain words, then how DJs use it.">
<meta property="og:image" content="https://deckie.io/assets/share-dictionary.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Deckie dictionary. Every DJ starts somewhere: Bass swap, Echo out and Beatmatching in plain words.">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:locale" content="en_US">
<meta name="twitter:image:alt" content="The Deckie dictionary. Every DJ starts somewhere: Bass swap, Echo out and Beatmatching in plain words.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="The Deckie dictionary: DJ speak, in plain words">
<meta name="twitter:description" content="Every DJ starts somewhere. DJ speak, in plain words, then how DJs use it.">
<meta name="twitter:image" content="https://deckie.io/assets/share-dictionary.jpg">
<link rel="icon" href="../favicon.ico" sizes="32x32">
<link rel="icon" href="../favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="../apple-touch-icon.png">
<!-- Generated by site/dictionary/build.py from docs/vocabulary/terms.json. Edit the JSON, then run the script; do not edit this file by hand. -->
<script type="application/ld+json">
{ld}
</script>
<link rel="stylesheet" href="../site.css">
<link rel="stylesheet" href="dictionary.css">
</head>
<body class="dx">

<div class="bar">
<header class="wrap top">
  <a class="mark" href="../" aria-label="Deckie, home"><img class="ico" src="../icon.svg" alt="" width="28" height="28"><span class="you name">Deckie</span></a>
  <nav class="tabs" aria-label="Pages">
    <a href="../">Home</a>
    <a href="./" aria-current="page">Dictionary</a>
  </nav>
  <a class="btn quiet" href="../#beta">Help us beta test</a>
</header>
</div>

<main id="main">
<div class="wrap dx-intro">
  <div class="dx-hello">
    <p class="dx-label">The dictionary</p>
    <h1>Every DJ starts&nbsp;somewhere</h1>
    <p class="lede">Why not here? DJ speak, in plain&nbsp;words.</p>
    <div class="dx-start"><p class="dx-label" id="dx-start-h">Start here</p><nav class="dx-chips" aria-labelledby="dx-start-h">{start}</nav></div>
  </div>
  <section class="dx-feature" aria-labelledby="dx-feature-h">
    <p class="dx-label" id="dx-feature-h">A first word</p>
{featured}  </section>
</div>

<div class="dx-tools" id="dx-tools">
  <div class="wrap">
    <form class="dx-search" role="search" action="#" onsubmit="return false">
      <label for="dx-q" class="dx-sr">Look up a word</label>
      <svg class="dx-glass" viewBox="0 0 20 20" width="18" height="18" aria-hidden="true" focusable="false"><circle cx="8.5" cy="8.5" r="5.75" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M13 13l4.5 4.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
      <input id="dx-q" type="search" placeholder="Look up a word" autocomplete="off" spellcheck="false" enterkeyhint="search" aria-describedby="dx-count">
      <button type="button" class="dx-clear" id="dx-clear" hidden aria-label="Clear the search"><svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true" focusable="false"><circle cx="10" cy="10" r="9" fill="currentColor"/><path d="M6.8 6.8l6.4 6.4M13.2 6.8l-6.4 6.4" stroke="#1a1420" stroke-width="1.8" stroke-linecap="round"/></svg></button>
      <span class="dx-count" id="dx-count" aria-live="polite">{count} words</span>
    </form>
    <nav class="dx-az" aria-label="A to Z">{az}</nav>
  </div>
</div>

<div class="wrap dx-list">
  <div class="dx-topics" id="dx-topics" hidden><p class="dx-label" id="dx-topics-h">Topics</p><div class="dx-chips" role="group" aria-labelledby="dx-topics-h">{chips}</div></div>
  <div class="dx-grid" id="terms">
{cards}  </div>
  <div class="dx-empty" id="dx-empty" hidden>
    <p class="dx-empty-h">No word matches <span id="dx-empty-q"></span></p>
    <p>Every DJ starts somewhere: try a shorter word, or another name for it. <button type="button" id="dx-reset">Clear the search</button></p>
  </div>
</div>
</main>

<footer class="wrap dx-foot">
  <p>{count} words, updated <time datetime="{updated_iso}">{updated_text}</time>. “On&nbsp;the&nbsp;decks” is how DJs say and use a&nbsp;word. “In&nbsp;Deckie”, last on each card, says what Deckie does with it; <span class="dx-planned">Planned</span> means designed and not yet&nbsp;built.</p>
  <p>Where a word comes from: heard from DJs on forums and in videos, taught in tutorials, or Deckie’s own phrase where DJs have no single&nbsp;word.</p>
  <p><a href="https://deckie.io/">deckie.io</a> · Deckie. Know Your Crate · Deckie, as in deckhand. Made by Christopher Shannon and <a href="https://apphold.media">App Hold Media</a>. Coming&nbsp;soon.</p>
</footer>

<script type="application/json" id="dx-redirect">{redirect}</script>
<script src="../site.js" defer></script>
<script src="dictionary.js" defer></script>
</body>
</html>
"""


def sync_internal(data, write):
    """Rewrite the JSON block inside docs/vocabulary/index.html. Returns True if it was already in step."""
    page = INTERNAL.read_text(encoding="utf-8")
    pat = re.compile(r'(<script type="application/json" id="terms-data">\n)(.*?)(\n</script>)', re.S)
    m = pat.search(page)
    if not m:
        sys.exit("docs/vocabulary/index.html: no terms-data block")
    new = json.dumps(data, ensure_ascii=True)  # ASCII escapes, so no "</script>" can appear inside
    if m.group(2) == new:
        return True
    if write:
        INTERNAL.write_text(page[:m.start(2)] + new + page[m.end(2):], encoding="utf-8")
    return False


def main():
    check = "--check" in sys.argv[1:]
    data = load()
    page = build_page(data)
    page_ok = OUT.exists() and OUT.read_text(encoding="utf-8") == page
    internal_ok = sync_internal(data, write=not check)
    if check:
        if page_ok and internal_ok:
            print("up to date")
            return 0
        print("out of date:", ", ".join(n for n, ok in (("site/dictionary/index.html", page_ok),
                                                          ("docs/vocabulary/index.html", internal_ok)) if not ok))
        return 1
    if not page_ok:
        OUT.write_text(page, encoding="utf-8")
    public = sum(1 for t in data["terms"] if t.get("public", True) is not False)
    print(f"wrote {OUT.relative_to(ROOT)}: {public} of {len(data['terms'])} terms public"
          + ("" if internal_ok else "; synced docs/vocabulary/index.html"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
