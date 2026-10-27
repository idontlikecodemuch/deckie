import json, os, re, shutil, sys, time
SP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # the folder holding newfiles/, shop/, twodisc/
ROOT = "/Users/christophershannon/personal/90s2000 playlist"; OUT = os.path.join(ROOT, "Mike page")
import unicodedata
def safe(name):
    n = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    n = re.sub(r'[/\\:*?"<>|#%]', "", n).replace("&", "and")
    return re.sub(r"\s+", " ", n).strip()
P = json.load(open(SP + "/newfiles/pool.json")); cands = [i for i in P if i["src"] != "lib"]
FOLDERS = ["1 - under 90", "2 - 90-99", "3 - 100-109", "4 - 110-119", "5 - 120-124", "6 - 125-129", "7 - 130-134", "8 - 135 plus"]
def find(t, p=None):
    hits = [r for r in cands if r["title"].startswith(t) and (p is None or p in r["path"])]
    assert len(hits) == 1, (t, p, [(h["title"], h["path"]) for h in hits]); return hits[0]
ALT1 = ["Technotronic - Pump Up The Jam", "CeCe Peniston - Finally", "Real McCoy - Another Night", "Corona - The Rhythm Of The Night", "Eiffel 65 - Blue", "Black Eyed Peas - I Gotta Feeling",
        "Kylie Minogue - Can't Get You Out Of My Head", "Taio Cruz - Dynamite", "Carly Rae Jepsen - Call Me Maybe", "Shania Twain - Man! I Feel Like A Woman!", "Sir Mix-A-Lot - Baby Got Back",
        "The Trammps - Disco Inferno", "Depeche Mode - Personal Jesus", "Shakira - She Wolf", "Lady Gaga & Doechii - Runway"]
ALT2 = [("Nelly Furtado - Maneater", "Monaark"), ("Chris Lorenzo", "MarkCutz"), ("Rihanna - Don't Stop The Music", "Colin Jay"), ("Rockwell - Somebody's Watching Me", "Richastic"),
        ("John Carpenter - Halloween Theme", None), ("Sash! - Mysterious Times", None), ("The Prodigy - Voodoo People", None), ("N-Trance - Set You Free", None), ("Faithless - Insomnia", None),
        ("The Chemical Brothers - Hey Boy Hey Girl", None), ("Armand Van Helden - You Don't Know Me", None), ("The Bucketheads - The Bomb!", None), ("ATB, Topic & A7S - Your Love (9PM)", None),
        ("Avicii - Wake Me Up", None), ("Adamski feat. Seal - Killer", None), ("The Source feat. Candi Staton - You Got The Love", None), ("Fatboy Slim - Praise You", None),
        ("Eliza Rose - B.O.T.A. (Baddest Of Them All)", None), ("Ultra Nate - Free", None), ("Royksopp & Robyn - Do It Again", None)]
rows = [(r, r["disc"], True) for r in cands if r["rec"]]
for r in cands:
    if r.get("cut"): rows.append((r, r["disc"], False))
for t in ALT1:
    r = find(t)
    if not r["rec"]: rows.append((r, "S", False))   # skip alternates Mike has switched on; they are already in as picks
for t, p in ALT2:
    r = find(t, p)
    if not r["rec"]: rows.append((r, "M", False))
SKIP = ("tick", "you had", "your list", "list pick", "your pony", "not in your picks", "e and diana", "at your request", "cd1 is full", "you confirmed", "mike's lane", "mike-friendly", "mike's long",
        "ask the pool", "one click", "moved to mix-ins", "benched", "your single", "you asked", "stays as the classic", "a mix-in.", "a mix-in,", "exactly the kind")
def note(r):
    w = r["why"] or ""
    if w.startswith("Benched") or w.startswith("Same track"): return ""
    out = []
    for s in re.split(r"(?<=[.;!])\s+", w):
        if any(k in s.lower() for k in SKIP): continue
        s = re.sub(r"^(Your list pick #\d+:|List pick[:;]|Floor-tempo)\s*", "", s).strip().rstrip(";").strip()
        s = s.replace("Pool intro edit", "Intro edit").replace("pool edit", "DJ edit")
        if s.rstrip(".") in (r["title"].split(" - ")[0], "Current", "Second cut", "Second Maneater"): continue
        if s: s = s[0].upper() + s[1:]; out.append(s if s.endswith(".") else s + ".")
    return " ".join(out)
def kind(r):
    v = (r["ver"] or "").lower(); w = (r["why"] or "").lower(); t = r["title"].lower()
    w2 = w.replace("monster mash", "")
    if "transition" in v or "wordplay" in v: return "Transition"
    song = t.split(" - ", 1)[1] if " - " in t else t
    if re.search(r"\bmash", v) or re.search(r"\bmash", w2) or re.search(r"\bmash", song) or " x " in v or " vs " in song or " vs " in v or " over " in w2 or " into " in w2: return "Mash-up"
    if "cover" in v or re.search(r"\b(dance|house) cover", w): return "Cover"
    if "intro" in v: return "Intro edit"
    if r["kind"] == "rip" and r["kbps"] < 160: return "Rip"
    if any(k in v for k in ("remix", "flip", "rework", "club mix", "club edit", "edit", "mix")) or re.search(r"\((.*\b(remix|mix|re-edit|edit)\b.*)\)$", t) or " vs " in t.split(" - ")[0]: return "Remix"
    return "Original"
LINKS = json.load(open(os.path.join(SP, "ext", "links.json"))) if os.path.exists(os.path.join(SP, "ext", "links.json")) else {}
STARS = set(json.load(open(os.path.join(SP, "newfiles", "chris_stars.json")))) if os.path.exists(os.path.join(SP, "newfiles", "chris_stars.json")) else set()
WAVES = json.load(open(os.path.join(SP, "newfiles", "waves.json"))) if os.path.exists(os.path.join(SP, "newfiles", "waves.json")) else {}
RMXW = ("remix", "edit", "rework", "flip", "mix", "cover", "transition", "bootleg", "version", "rmx", "re-edit", "extended")
JOIN = ("the", "vs", "&", "and", "x", "feat", "feat.", "ft", "ft.")
GENERIC = ("house", "dance", "club", "extended", "original", "radio", "vip", "halloween", "album", "fan", "edit")
def _ascii(n):
    n = unicodedata.normalize("NFKD", n).encode("ascii", "ignore").decode(); n = re.sub(r'[/\\:*?"<>|!\'"]', "", n).replace("&", "and")
    return re.sub(r"\s+", " ", n).strip()
def deck_name(r):
    v = r["ver"] or ""; inner = re.findall(r"\((.*?)\)", v); outer = re.sub(r"\s+", " ", re.sub(r"\(.*?\)", " ", v)).strip(" -")
    has_intro = "intro" in v.lower()
    if not outer: outer = next((x for x in inner if any(w in x.lower() for w in RMXW)), "")
    outer = outer.replace(" - Dirty", "").replace(" - Clean", "")
    words = outer.split(); names = [w for w in words if w.lower() not in JOIN and w.lower().strip("()") not in RMXW and w.lower() not in GENERIC and not re.match(r"^\d[\d\-s]*$", w)]
    rmx = any(w.lower() in RMXW for w in words) or bool(inner)
    def short(k):
        nm = " ".join(names[:k])
        if has_intro: return (nm + " Intro").strip()
        if "extended" in v.lower(): return (nm + " Extended").strip()
        if nm: return nm + (" Rmx" if rmx else "")
        if outer: return "Cover" if "cover" in v.lower() else "Rmx"
        return ""
    artist, song = (r["title"].split(" - ", 1) + [""])[:2] if " - " in r["title"] else ("", r["title"])
    song_plain = re.sub(r"\s*\(.*?\)", "", song).strip(); aw = [w for w in artist.split()]
    def build(a, sg, sh): return _ascii((a + " - " if a else "") + sg + (" (" + sh + ")" if sh else ""))
    cands = [build(artist, song, short(2)), build(artist, song_plain, short(2)), build(artist, song_plain, short(1))]
    first = aw[0] if aw else ""
    cands += [build(first, song_plain, short(1)), build(first, song_plain, short(1)[:12].strip())]
    for c in cands:
        if len(c) <= 54: return c
    return cands[-1][:54].rstrip(" -(")
os.makedirs(OUT, exist_ok=True); tracks = []; used = set()
for r, disc, sel in rows:
    d = "1" if disc == "S" else "2"; folder = r["folder"]; assert folder in FOLDERS, (r["title"], folder)
    artist, song = (r["title"].split(" - ", 1) + [""])[:2] if " - " in r["title"] else ("", r["title"])
    base = safe(r["title"] + ((" " + r["ver"] if r["ver"].startswith("(") else " (" + r["ver"] + ")") if r["ver"] else "")); assert base not in used, base; used.add(base)
    rel = f"tracks/cd{d}/{folder}/{base}.mp3"; dst = os.path.join(OUT, rel); os.makedirs(os.path.dirname(dst), exist_ok=True)
    src = os.path.join(ROOT, r["path"]); assert os.path.exists(src), src
    if not os.path.exists(dst):
        try: os.link(src, dst)
        except OSError: shutil.copy2(src, dst)
    v = (r["ver"] or "").lower(); w = (r["why"] or "").lower()
    tracks.append({"id": r["id"], "disc": d, "folder": folder, "fi": FOLDERS.index(folder), "bpm": r["bpm"], "len": r["len"], "secs": r["secs"], "mb": r["mb"], "artist": artist, "song": song,
                   "title": r["title"], "ver": r["ver"] or "", "era": r["era"], "hal": bool(r["hal"]), "explicit": ("dirty" in v) or ("explicit" in w), "isNew": r["src"] == "new",
                   "oldDisc": r["src"] if r["src"].startswith("CD") else "", "kind": kind(r), "kbps": r["kbps"], "selected": sel, "note": note(r), "path": rel,
                   "deck": deck_name(r), "wave": WAVES.get(r["id"], ""), "fav": r["id"] in STARS})
tracks.sort(key=lambda t: (t["disc"], t["fi"], t["bpm"] or 0, t["title"].lower()))
data = {"generated": time.strftime("%Y-%m-%d"), "budgetMB": 690, "folders": FOLDERS,
        "discs": {"1": {"name": "CD1 Singalongs", "short": "Singalongs", "blurb": "The crowd-pleasers: hooks the whole room sings. 90s and 2000s pop, hip-hop and dance plus the Halloween staples. Where a slow original had a club edit or intro version, that version is here instead of the original."},
                  "2": {"name": "CD2 Mix-ins", "short": "Mix-ins", "blurb": "Your lane: house remixes, mash-ups, transitions and tools that layer easily, a few CD4 favourites, and the Halloween tracks that work as a blend rather than a singalong."}},
        "tracks": tracks}
json.dump(data, open(os.path.join(OUT, "data.json"), "w"), indent=1, ensure_ascii=False)
open(os.path.join(OUT, "data.js"), "w").write("window.MIKE_DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
for d in "12":
    sel = [t for t in tracks if t["disc"] == d and t["selected"]]; alt = [t for t in tracks if t["disc"] == d and not t["selected"]]
    print(f"CD{d}: {len(sel)} on, {round(sum(t['mb'] for t in sel),1)} MB; {len(alt)} alternates")
# stale files in tracks/ that are no longer referenced
want = {t["path"] for t in tracks}
for dp, dn, fn in os.walk(os.path.join(OUT, "tracks")):
    for f in fn:
        rel = os.path.relpath(os.path.join(dp, f), OUT)
        if rel not in want and f != "index.html": os.remove(os.path.join(dp, f)); print("removed stale:", rel)
print("notes with text:", sum(1 for t in tracks if t["note"]))
for t in tracks:
    if t["note"]: print(f'  [{t["kind"]:10}] {t["title"]}{(" — "+t["ver"]) if t["ver"] else ""}: {t["note"]}')
