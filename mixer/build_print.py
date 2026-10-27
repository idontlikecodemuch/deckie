#!/usr/bin/env python3
"""One-page printout: both discs in disc order with faint lines from a track's end to the
tracks it mixes into (top K per track above MINSCORE, from mixer/recs.json). Letter portrait."""
import json, os, re, sys, html, subprocess
MIX = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(MIX)
MUSIC_ROOT = os.environ.get("DECKIE_MUSIC_ROOT", "/Users/christophershannon/personal/90s2000 playlist")  # where the audio lives; never inside the repo
ROOT = MUSIC_ROOT
OUT = os.path.join(MUSIC_ROOT, "CDs v3")  # disc artifacts stay beside the audio
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TOPK = int(sys.argv[1]) if len(sys.argv) > 1 else 4
MINSCORE = float(sys.argv[2]) if len(sys.argv) > 2 else 0.75

# ---------- data (same sources as the interactive map) ----------
h = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "mixmap.html"), encoding="utf-8").read()
D = json.loads(re.search(r'<script id="data" type="application/json">(.*?)</script>', h, re.S).group(1).replace("<\\/", "</"))
tracks = sorted(D["tracks"], key=lambda t: (t["disc"], t["folder"], t["n"]))
T = {t["id"]: t for t in tracks}
MINCROSS = 2          # reserve this many slots per track for the other disc (floor 0.6 from recs)
edges = []
for a in T:
    mine = sorted([e for e in D["edges"] if e["a"] == a], key=lambda e: -e["s"])
    cross = [e for e in mine if T[e["b"]]["disc"] != T[a]["disc"]][:MINCROSS]
    rest = [e for e in mine if e not in cross and e["s"] >= MINSCORE]
    edges += cross + rest[:max(0, TOPK - len(cross))]
ncross = sum(1 for e in edges if T[e["a"]]["disc"] != T[e["b"]]["disc"])
print(f"{len(tracks)} tracks, {len(edges)} lines ({ncross} across discs; top {TOPK} per track, score >= {MINSCORE}, at least {MINCROSS} to the other disc)")

# ---------- geometry (points; letter landscape 792 x 612): CD1 | CD2 | CD1 ----------
PW, PH, M = 792, 612, 18
HEAD = 36
COLW = 168
GUT = (PW - 2 * M - 3 * COLW) / 2
X1, X2, X3 = M, M + COLW + GUT, M + 2 * (COLW + GUT)
FOLD = {"2 - 90-99": "90-99", "3 - 100-109": "100-109", "4 - 110-119": "110-119", "5 - 120-124": "120-124",
        "6 - 125-129": "125-129", "7 - 130-134": "130-134", "8 - 135 plus": "135+"}
def layout(disc):
    rows = [t for t in tracks if t["disc"] == disc]
    return rows, len(rows) + len({t["folder"] for t in rows})
r1, n1 = layout("1"); r2, n2 = layout("2")
avail = PH - M - HEAD - 16 - 22 - M
RH = min(11.0, avail / max(n1, n2))
FS = round(min(7.2, RH * 0.7), 1)
y_of = {}
def place(rows):
    out = []
    y = M + HEAD + 12
    f = None
    for t in rows:
        if t["folder"] != f:
            f = t["folder"]
            out.append(("folder", FOLD.get(f, f), y)); y += RH
        y_of[t["id"]] = y + RH * 0.5 - 1
        out.append(("row", t, y)); y += RH
    return out
L1 = place(r1); L2 = place(r2)

def short(name, maxc):
    return name if len(name) <= maxc else name[:maxc - 1].rstrip() + "…"
def row_html(t, x0, y):
    nm = short(t["name"], 31)
    hal = '<tspan class="h">H </tspan>' if t["hal"] else ""
    chg = abs(t["bpm_in"] - t["bpm_out"]) / t["bpm"] > 0.02
    bpm = f'{t["bpm_out"]:.0f}*' if chg else f'{t["bpm"]:.0f}'
    key = t["key"] + ("?" if t["keyc"] < 0.5 else "")
    return (f'<text x="{x0+2}" y="{y+RH*0.78:.1f}" class="n">{t["n"]:02d}</text>'
            f'<text x="{x0+14}" y="{y+RH*0.78:.1f}" class="t">{hal}{html.escape(nm)}</text>'
            f'<text x="{x0+COLW-17}" y="{y+RH*0.78:.1f}" class="b" text-anchor="end">{bpm}</text>'
            f'<text x="{x0+COLW-2}" y="{y+RH*0.78:.1f}" class="k" text-anchor="end">{key}</text>')
def col_html(items, x0, title, sub):
    s = [f'<text x="{x0}" y="{M+HEAD+2}" class="disc">{html.escape(title)}</text>',
         f'<text x="{x0+COLW}" y="{M+HEAD+2}" class="sub" text-anchor="end">{html.escape(sub)}</text>',
         f'<line x1="{x0}" y1="{M+HEAD+5}" x2="{x0+COLW}" y2="{M+HEAD+5}" class="rule"/>']
    for kind, v, y in items:
        if kind == "folder":
            s.append(f'<text x="{x0+2}" y="{y+RH*0.78:.1f}" class="f">{html.escape(v)}</text>')
        else:
            s.append(row_html(v, x0, y))
    return "\n".join(s)
def mins(rows):
    tot = 0
    for t in rows:
        m, s = (t.get("len") or "0:0").split(":"); tot += int(m) * 60 + int(s)
    return round(tot / 60)

# ---------- lines ----------
paths = []
for e in edges:
    A, B = T[e["a"]], T[e["b"]]
    ya, yb = y_of[e["a"]], y_of[e["b"]]
    cls = "cut" if e["tr"] == "brake_cut" else ("half" if e["m"] != "1" else "mix")
    same = False
    w = 0.55 + (e["s"] - MINSCORE) / (1 - MINSCORE) * 0.75
    if A["disc"] == "1" and B["disc"] == "2":      # left column -> middle
        xa, xb = X1 + COLW + 3, X2 - 3
        mx = (xa + xb) / 2
        d = f"M{xa:.1f},{ya:.1f} C{mx:.1f},{ya:.1f} {mx:.1f},{yb:.1f} {xb:.1f},{yb:.1f}"
    elif A["disc"] == "2" and B["disc"] == "1":    # middle -> right column
        xa, xb = X2 + COLW + 3, X3 - 3
        mx = (xa + xb) / 2
        d = f"M{xa:.1f},{ya:.1f} C{mx:.1f},{ya:.1f} {mx:.1f},{yb:.1f} {xb:.1f},{yb:.1f}"
    else:                                           # same disc: a wide bulge into the gutter to the right
        same = True
        x = (X1 if A["disc"] == "1" else X2) + COLW + 3
        dx = 14 + min(46, abs(yb - ya) * 0.22)
        d = f"M{x:.1f},{ya:.1f} C{x+dx:.1f},{ya:.1f} {x+dx:.1f},{yb:.1f} {x:.1f},{yb:.1f}"
    paths.append(f'<path d="{d}" class="{cls}{" same" if same else ""}" stroke-width="{w:.2f}" marker-end="url(#{"arr2" if same else "arr"})"/>')

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{PW}pt" height="{PH}pt" viewBox="0 0 {PW} {PH}" font-family="Helvetica Neue, Helvetica, Arial, sans-serif">
<defs><marker id="arr" viewBox="0 0 6 6" refX="5" refY="3" markerWidth="4" markerHeight="4" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#8e78b8" fill-opacity="0.55"/></marker>
<marker id="arr2" viewBox="0 0 6 6" refX="5" refY="3" markerWidth="4" markerHeight="4" orient="auto"><path d="M0,0 L6,3 L0,6 z" fill="#1a9c7b" fill-opacity="0.6"/></marker></defs>
<style>
 .title{{font-size:15px;font-weight:700;fill:#2a1a4a}} .title tspan{{fill:#e4772a}}
 .intro{{font-size:7px;fill:#5d5470}}
 .disc{{font-size:9.5px;font-weight:700;fill:#5a2fb0}} .sub{{font-size:7px;fill:#6b5f80}} .rule{{stroke:#5a2fb0;stroke-width:0.6}}
 .f{{font-size:{FS-1:.1f}px;fill:#8a7fa0;letter-spacing:.6px;font-weight:700}}
 .n{{font-size:{FS-0.8:.1f}px;fill:#9a92ad}} .t{{font-size:{FS}px;fill:#1d1430}} .t .h{{fill:#e4772a;font-weight:700}}
 .b{{font-size:{FS-0.8:.1f}px;fill:#4a4160}} .k{{font-size:{FS-1.2:.1f}px;fill:#6b5f80}}
 path.mix{{fill:none;stroke:#6a3fc9;stroke-opacity:0.30;stroke-linecap:round}}
 path.half{{fill:none;stroke:#6a3fc9;stroke-opacity:0.30;stroke-dasharray:1.2 2.2;stroke-linecap:round}}
 path.cut{{fill:none;stroke:#d9532f;stroke-opacity:0.30;stroke-dasharray:3 2.2;stroke-linecap:round}}
 path.same{{stroke:#1a9c7b;stroke-opacity:0.38}}
 .leg{{font-size:6.6px;fill:#5d5470}}
</style>
<text x="{M}" y="{M+12}" class="title">Halloween Mix Map <tspan>CD1 + CD2</tspan></text>
<text x="{M}" y="{M+22}" class="intro">Lines run from the end of a track to tracks it mixes into well: measured tempo at both ends, key, energy, vocal overlap, phrase length, groove. Up to {TOPK} per track at score {MINSCORE:.2f}+, always including the best {MINCROSS} on the other disc.</text>
<text x="{M}" y="{M+30}" class="intro">BPM is measured (an asterisk = the tempo differs at the two ends, outgoing shown); key is Camelot (? = unsure); H = Halloween track, as on the discs.</text>
{col_html(L1, X1, "CD1 Singalongs", f"{len(r1)} · {mins(r1)} min · out →")}
{col_html(L2, X2, "CD2 Mix-ins", f"{len(r2)} · {mins(r2)} min")}
{col_html(L1, X3, "CD1 Singalongs", f"← in from CD2")}
{chr(10).join(paths)}
<g transform="translate({M},{PH-M-4})" class="leg">
 <line x1="0" y1="-2.5" x2="16" y2="-2.5" stroke="#6a3fc9" stroke-opacity="0.6" stroke-width="1"/><text x="20" y="0">to the other disc</text>
 <line x1="92" y1="-2.5" x2="108" y2="-2.5" stroke="#1a9c7b" stroke-opacity="0.7" stroke-width="1"/><text x="112" y="0">same disc</text>
 <line x1="170" y1="-2.5" x2="186" y2="-2.5" stroke="#555" stroke-opacity="0.6" stroke-width="1"/><text x="190" y="0">solid = beat-matched blend</text>
 <line x1="300" y1="-2.5" x2="316" y2="-2.5" stroke="#555" stroke-opacity="0.6" stroke-width="1" stroke-dasharray="1.2 2.2"/><text x="320" y="0">dotted = half or double time</text>
 <line x1="430" y1="-2.5" x2="446" y2="-2.5" stroke="#d9532f" stroke-opacity="0.6" stroke-width="1" stroke-dasharray="3 2.2"/><text x="450" y="0">orange dashed = brake or cut, no beat-match</text>
 <text x="620" y="0">thicker = stronger match · arrow = next track</text>
</g>
</svg>'''
page = f'''<!doctype html><html><head><meta charset="utf-8"><title>Halloween Mix Map - CD1 and CD2</title>
<style>@page{{size:letter landscape;margin:0}} html,body{{margin:0;padding:0;background:#fff}} body{{width:{PW}pt;height:{PH}pt;overflow:hidden}} svg{{display:block}}</style>
</head><body>{svg}</body></html>'''
hp = os.path.join(OUT, "Mix map - CD1 and CD2.html"); pdf = os.path.join(OUT, "Mix map - CD1 and CD2.pdf")
open(hp, "w", encoding="utf-8").write(page)
p = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf}", "file://" + hp], capture_output=True, text=True, timeout=120)
print("chrome exit", p.returncode, "pdf", os.path.getsize(pdf) if os.path.exists(pdf) else "missing", f"| row height {RH:.1f}pt font {FS}pt")
