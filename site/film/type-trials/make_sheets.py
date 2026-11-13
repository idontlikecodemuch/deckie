"""Type trials for the Deckie film and page: the same five frames set in each headline face and style.
Writes sheet HTML files (cells are 1920x1080 frames scaled down) and hero override CSS files; shots.mjs turns them
into PNGs. Layout numbers follow site/film/film.js."""
import base64, json, os, sys
SP = sys.argv[1]
NM = SP + "/reel/node_modules"
def b64(p): return base64.b64encode(open(p, "rb").read()).decode()
FONTS = {
 "Stardos Stencil": [(NM + "/@fontsource/stardos-stencil/files/stardos-stencil-latin-700-normal.woff2", "700", "normal")],
 "Yeseva One": [(NM + "/@fontsource/yeseva-one/files/yeseva-one-latin-400-normal.woff2", "400", "normal")],
 "Playfair Display": [(NM + "/@fontsource-variable/playfair-display/files/playfair-display-latin-wght-normal.woff2", "400 900", "normal"),
                      (NM + "/@fontsource-variable/playfair-display/files/playfair-display-latin-wght-italic.woff2", "400 900", "italic")],
 "Playfair Display SC": [(NM + "/@fontsource/playfair-display-sc/files/playfair-display-sc-latin-700-normal.woff2", "700", "normal")],
 "Pacifico": [(NM + "/@fontsource/pacifico/files/pacifico-latin-400-normal.woff2", "400", "normal")],
 "Inter": [(NM + "/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2", "100 900", "normal")],
}
FACE = "".join(f'@font-face{{font-family:"{n}";src:url(data:font/woff2;base64,{b64(p)}) format("woff2");font-weight:{w};font-style:{st};}}' for n, fs in FONTS.items() for p, w, st in fs)

# id, sheet, label, headline css, size scale, stamp css, stamp text case ('caps' or 'as is'), name css (or None = headline)
def V(id, sheet, label, h, k=1.0, stamp=None, stampcase="caps", name=None, note=""):
    q = lambda c: c.replace('"', "'")
    return dict(id=id, sheet=sheet, label=label, h=q(h), k=k, stamp=q(stamp or h + "letter-spacing:.07em;"), stampcase=stampcase, name=q(name or h), note=note)
VARS = [
 V("REF", "ref", "Stardos Stencil · Bold 700 · sentence case (the current film)", 'font-family:"Stardos Stencil";font-weight:700;'),
 V("Y1", "yeseva", "Yeseva One · Regular 400 (its only weight) · sentence case", 'font-family:"Yeseva One";font-weight:400;'),
 V("Y2", "yeseva", "Yeseva One · 400 · ALL CAPS, tracked +4%", 'font-family:"Yeseva One";font-weight:400;text-transform:uppercase;letter-spacing:.04em;', .80),
 V("Y3", "yeseva", "Yeseva One · 400 · Title Case", 'font-family:"Yeseva One";font-weight:400;text-transform:capitalize;'),
 V("Y4", "yeseva", "Yeseva One · 400 · sentence case, tight (-2%), 8% larger", 'font-family:"Yeseva One";font-weight:400;letter-spacing:-.02em;', 1.08),
 V("P1", "playfair", "Playfair Display · Black 900 · sentence case", 'font-family:"Playfair Display";font-weight:900;'),
 V("P2", "playfair", "Playfair Display · Bold 700 italic · sentence case", 'font-family:"Playfair Display";font-weight:700;font-style:italic;', 1.0, 'font-family:"Playfair Display";font-weight:800;letter-spacing:.08em;'),
 V("P3", "playfair", "Playfair Display · ExtraBold 800 · ALL CAPS, tracked +5%", 'font-family:"Playfair Display";font-weight:800;text-transform:uppercase;letter-spacing:.05em;', .78),
 V("P4", "playfair", "Playfair Display SC · Bold 700 · small caps", 'font-family:"Playfair Display SC";font-weight:700;letter-spacing:.01em;', .92),
 V("P5", "playfair", "Playfair Display · Medium 500 · sentence case", 'font-family:"Playfair Display";font-weight:500;'),
 V("P6", "playfair", "Playfair Display · Black 900 headlines; ExtraBold 800 italic for the name and the one accent line", 'font-family:"Playfair Display";font-weight:900;', 1.0, 'font-family:"Playfair Display";font-weight:800;letter-spacing:.08em;', "caps", 'font-family:"Playfair Display";font-weight:800;font-style:italic;', note="mix"),
 V("C1", "pacifico", "Pacifico · Regular 400 (its only weight) · sentence case, everything", 'font-family:"Pacifico";font-weight:400;', .88, 'font-family:"Pacifico";font-weight:400;', "as is"),
 V("C2", "pacifico", "Pacifico · 400 · ALL CAPS", 'font-family:"Pacifico";font-weight:400;text-transform:uppercase;', .66, 'font-family:"Pacifico";font-weight:400;', "caps"),
 V("C3", "pacifico", "Pacifico for the name and the stamps only · headlines in Inter ExtraBold 800, sentence case", 'font-family:"Inter";font-weight:800;letter-spacing:-.025em;', .92, 'font-family:"Pacifico";font-weight:400;', "as is", 'font-family:"Pacifico";font-weight:400;'),
 V("C4", "pacifico", "Pacifico for the name only · headlines in Inter ExtraBold 800 · stamps in Inter caps", 'font-family:"Inter";font-weight:800;letter-spacing:-.025em;', .92, 'font-family:"Inter";font-weight:800;letter-spacing:.1em;', "caps", 'font-family:"Pacifico";font-weight:400;'),
]
C = dict(warm="#f6eede", acc="#b490ff", mut="#ab9fc2", dim="#76698f", card="#1d1530", line="#30254a", tx="#f2edf9")
def stamp(v, text, x, y, size, rot=-3):
    t = text.upper() if v["stampcase"] == "caps" else text.capitalize() if text.isupper() else text
    return f'<div style="position:absolute;left:{x}px;top:{y}px;{v["stamp"]}font-size:{size}px;line-height:1;color:{C["acc"]};border:{max(4,int(size*.07))}px solid {C["acc"]};padding:{int(size*.3)}px {int(size*.42)}px {int(size*.24)}px;transform:rotate({rot}deg);transform-origin:left center;white-space:nowrap;text-transform:none">{t}</div>'
BG = "background:linear-gradient(200deg,#1c1036 0%,#0f0a17 75%);"
def frame(v, which):
    h, k = v["h"], v["k"]
    T = lambda s, x, y, size, col=C["warm"], extra="", css=None: f'<div style="position:absolute;left:{x}px;top:{y}px;{css or h}font-size:{round(size*k)}px;line-height:1.1;color:{col};white-space:nowrap;{extra}">{s}</div>'
    if which == "A":
        plat = lambda cx, cy, r, col: f'<div style="position:absolute;left:{cx-r}px;top:{cy-r}px;width:{2*r}px;height:{2*r}px;border-radius:50%;background:#120c1d;box-shadow:inset 0 0 0 2px #30254a, inset 0 0 0 {r*.2}px #120c1d, inset 0 0 0 {r*.2+2}px #30254a, inset 0 0 0 {r*.4}px #120c1d, inset 0 0 0 {r*.4+2}px #30254a"></div><div style="position:absolute;left:{cx-r*.34}px;top:{cy-r*.34}px;width:{r*.68}px;height:{r*.68}px;border-radius:50%;background:{col}"></div>'
        body = plat(1500, 330, 300, C["acc"]) + plat(1260, 870, 230, "#5a6cc0")
        for i, w in enumerate(["CDJs.", "Turntables.", "The house decks."]):
            body += T(w, 96, 300 - 150 + 12 + i * 158, 150, extra="opacity:.38;")
        acc = v["name"] if v["note"] == "mix" else None
        body += T("None of them know<br>your music.", 96, 800 - 92 + 8, 92, C["acc"], css=acc)
    elif which == "B":
        body = T("Not an AI DJ.", 96, 222, 150, extra="opacity:.45;") + T("No sync button.", 96, 412, 150, extra="opacity:.45;")
        body += T("It suggests. You mix.", 96, 602, 150, C["acc"], css=v["name"] if v["note"] == "mix" else None)
    elif which == "C":
        body = f'<div style="position:absolute;left:96px;top:{520-330*k*1.0:.0f}px;{v["name"]}font-size:{round(330*k)}px;line-height:1.1;color:{C["warm"]};white-space:nowrap;text-transform:none">Deckie</div>'
        body += f'<div style="position:absolute;left:102px;top:590px;font-family:Inter;font-weight:600;font-size:60px;color:{C["mut"]}">DJ booth companion</div>'
        body += stamp(v, "COMING SOON", 100, 760, 84)
    elif which == "D":
        body = f'<div style="position:absolute;left:96px;top:300px;{h}font-size:{round(96*k)}px;line-height:1;color:{C["acc"]};text-transform:none">1<span style="font-size:{round(44*k)}px;color:{C["dim"]}">/3</span></div>'
        body += f'<div style="position:absolute;left:232px;top:352px;font-family:Inter;font-weight:650;font-size:25px;letter-spacing:3px;color:{C["mut"]}">DECKIE DESK · ON YOUR MAC</div>'
        body += f'<div style="position:absolute;left:96px;top:420px;width:620px;{h}font-size:{round(70*k)}px;line-height:1.17;color:{C["warm"]}">Desk reads your crate and writes a crate file.</div>'
        body += f'<div style="position:absolute;left:96px;top:700px;width:600px;font-family:Inter;font-weight:500;font-size:36px;line-height:1.4;color:{C["mut"]}">Edits, bootlegs and burned CDs included.</div>'
        body += f'<div style="position:absolute;left:760px;top:140px;width:672px;height:420px;border-radius:22px;border:2px solid {C["line"]};overflow:hidden;box-shadow:0 26px 70px rgba(0,0,0,.55);background:#160f22"><img src="desk_open.png" style="width:{672*1.7:.0f}px;display:block"></div>'
        lab = f'<div style="position:absolute;left:1150px;top:420px;width:640px;height:440px;background:{C["card"]};box-shadow:0 20px 60px rgba(0,0,0,.5)"><div style="position:absolute;inset:12px;border:4px solid {C["warm"]}"></div>'
        capsH = h + "text-transform:uppercase;" if "Pacifico" not in h else h
        LT = lambda s, x, y, size, col=C["warm"]: f'<div style="position:absolute;left:{x}px;top:{y}px;{capsH}font-size:{round(size*min(k,1))}px;line-height:1;color:{col};white-space:nowrap;letter-spacing:.03em">{s}</div>'
        lab += LT("Friday night", 38, 44, 60)
        lab += f'<div style="position:absolute;left:40px;top:116px;font-family:Inter;font-weight:650;font-size:25px;letter-spacing:5px;color:{C["mut"]}">CRATE FILE</div><div style="position:absolute;left:38px;right:38px;top:158px;height:3px;background:{C["line"]}"></div>'
        for (word, x, y) in [("Tempo", 38, 190), ("Key", 226, 190), ("Bars", 360, 190), ("Style", 38, 256), ("Fingerprints", 210, 256)]:
            lab += LT(word, x, y, 40, C["tx"])
        lab += stamp(v, "NO AUDIO", 38, 336, 50, -5) + "</div>"
        body += lab
    return f'<div class="f" style="{BG}">{body}</div>'

def cell(v, which, hero_png=None, s=1/3):
    w, hh = round(1920 * s), round(1080 * s)
    if which == "E":
        inner = f'<img src="{hero_png}" style="width:{w}px;height:{hh}px;object-fit:cover;object-position:left top;display:block">'
    else:
        inner = f'<div style="width:1920px;height:1080px;transform:scale({s});transform-origin:0 0">{frame(v, which)}</div>'
    return f'<div class="c" style="width:{w}px;height:{hh}px">{inner}</div>'
COLS = [("A", "Opening"), ("B", "What it is not"), ("C", "Name card and stamp"), ("D", "Step frame, label and stamp"), ("E", "Page hero")]
def sheet(title, sub, ids, out, s=1/3):
    w = round(1920 * s)
    rows = ""
    for vid in ids:
        v = next(x for x in VARS if x["id"] == vid)
        rows += f'<div class="lab"><b>{vid}</b> &nbsp;{v["label"]}</div><div class="row">' + "".join(cell(v, c, f"hero_{vid}.png", s) for c, _ in COLS) + "</div>"
    head = '<div class="row hd">' + "".join(f'<div style="width:{w}px">{n}</div>' for _, n in COLS) + "</div>"
    html = f'<!doctype html><meta charset="utf-8"><style>{FACE}body{{margin:0;padding:36px 36px 44px;background:#08060c;color:#f2edf9;font-family:Inter;width:max-content}}h1{{font:800 40px Inter;margin:0 0 6px}}p.s{{font:500 22px Inter;color:#ab9fc2;margin:0 0 26px;max-width:2400px}}.row{{display:flex;gap:14px}}.hd div{{font:650 19px Inter;letter-spacing:.08em;text-transform:uppercase;color:#76698f;padding-bottom:8px}}.lab{{font:500 24px Inter;color:#f2edf9;margin:26px 0 10px}}.lab b{{color:#b490ff;font-weight:800}}.c{{overflow:hidden;border:1px solid #30254a;background:#0f0a17;flex:none}}.f{{position:relative;width:1920px;height:1080px;overflow:hidden}}</style><h1>{title}</h1><p class="s">{sub}</p>{head}{rows}'
    open(out, "w").write(html)

# hero overrides for the real page (site/index.html): the same family, weight, case and stamp treatment
ov = {}
for v in VARS:
    name = v["name"]
    css = FACE + f'h1,h2,h3,.mark,.btn,.steps li::before{{{v["h"]}}} h1{{font-size:calc(clamp(2.6rem,7.4vw,5.5rem)*{v["k"]})!important}} .mark{{{name}text-transform:none!important}} .stamp{{{v["stamp"]}{"text-transform:uppercase" if v["stampcase"]=="caps" else "text-transform:none;font-size:1.35rem;letter-spacing:0"}!important}}'
    if v["note"] == "mix": css += f' h1 em{{{name}}}'
    ov[v["id"]] = css
json.dump(ov, open(SP + "/trials/hero_css.json", "w"))
ALLSUB = "Each row is one treatment; each column the same frame. Body text and small labels stay in Inter throughout. Frames are layout copies of the film's, at one third size; the hero is the real page with the headline face swapped."
sheet("Type trial: Yeseva One", ALLSUB + " Reference row first.", ["REF", "Y1", "Y2", "Y3", "Y4"], SP + "/trials/sheet_yeseva.html")
sheet("Type trial: Playfair Display", ALLSUB + " Reference row first.", ["REF", "P1", "P2", "P3", "P4", "P5", "P6"], SP + "/trials/sheet_playfair.html")
sheet("Type trial: Pacifico", ALLSUB + " Reference row first.", ["REF", "C1", "C2", "C3", "C4"], SP + "/trials/sheet_pacifico.html")
sheet("Type trial: side by side", "The current film (top) against the strongest treatment of each of the three faces.", ["REF", "Y1", "P6", "C4"], SP + "/trials/sheet_side_by_side.html")
sheet("Type trial: the two finalists, larger", "At half size, so the letterforms can be judged.", ["Y1", "P6"], SP + "/trials/sheet_finalists.html", s=0.5)
print(len(VARS), "treatments")
