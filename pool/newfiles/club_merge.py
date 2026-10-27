import json, re, hashlib, unicodedata, urllib.request, urllib.parse, time
def fold(s): return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c)).lower()
seed = json.load(open("newfiles/club_seed.json"))
SONGS = {  # key -> (display, artist first word, original bpm, disc)
 "return of the mack": ("Mark Morrison - Return Of The Mack", "mark", 95, "1"), "hypnotize": ("The Notorious B.I.G. - Hypnotize", "notorious", 94, "1"), "gangsta's paradise": ("Coolio - Gangsta's Paradise", "coolio", 80, "1"),
 "no scrubs": ("TLC - No Scrubs", "tlc", 93, "1"), "gettin' jiggy wit it": ("Will Smith - Gettin' Jiggy Wit It", "will", 108, "1"), "...baby one more time": ("Britney Spears - ...Baby One More Time", "britney", 93, "1"),
 "all that she wants": ("Ace Of Base - All That She Wants", "ace", 94, "1"), "livin' la vida loca": ("Ricky Martin - Livin' La Vida Loca", "ricky", 89, "1"), "everybody (backstreet's back)": ("Backstreet Boys - Everybody (Backstreet's Back)", "backstreet", 108, "1"),
 "zombie": ("The Cranberries - Zombie", "cranberries", 84, "1"), "superstition": ("Stevie Wonder - Superstition", "stevie", 100, "1"), "pony": ("Ginuwine - Pony", "ginuwine", 71, "1"),
 "in da club": ("50 Cent - In Da Club", "50", 90, "2"), "gold digger": ("Kanye West - Gold Digger", "kanye", 92, "2"), "drop it like it's hot": ("Snoop Dogg - Drop It Like It's Hot", "snoop", 92, "2"),
 "yeah!": ("Usher - Yeah!", "usher", 105, "2"), "hot in herre": ("Nelly - Hot In Herre", "nelly", 107, "2"), "crazy in love": ("Beyonce - Crazy In Love", "beyonc", 99, "2"), "hey ya!": ("OutKast - Hey Ya!", "outkast", 81, "2"),
 "hips don't lie": ("Shakira - Hips Don't Lie", "shakira", 100, "2"), "levitating": ("Dua Lipa - Levitating", "dua", 103, "2"), "paint the town red": ("Doja Cat - Paint The Town Red", "doja", 100, "2"), "umbrella": ("Rihanna - Umbrella", "rihanna", 87, "2"),
}
def key_of(song):
    s = fold(song); t = s.split(" - ", 1)[1] if " - " in s else s
    for k in SONGS:
        if k.strip(".!") in t.strip(".!") or t.strip(".!") in k.strip(".!"): return k
    return None
AGENTS = json.loads(open("newfiles/club_agents.json").read())
out = []
for o in seed:
    o["source"] = o.get("source", "shopping list"); out.append(o)
for a in AGENTS:
    k = key_of(a["song"]);
    if not k: print("unmapped:", a["song"]); continue
    if "Hypnotize" in a["song"] and "beatport" in a["url"]: continue   # the agent could not tell which version that page holds
    disp, af, obpm, disc = SONGS[k]
    out.append({"song": disp, "key": k, "disc": disc, "obpm": obpm, "version": a["version"], "remixer": a.get("remixer") or "", "kind": a["kind"], "bpm": a.get("bpm"), "length": a.get("length"), "where": a.get("where") or "",
                "url": a["url"], "free": bool(a.get("free")), "verified": bool(a.get("verified")), "note": a.get("note") or "", "source": "agent search", "id": hashlib.md5((a["url"] + "|" + a["version"]).encode()).hexdigest()[:10]})
# iTunes catalogue: official remixes with a store page
UA = {"User-Agent": "Mozilla/5.0"}
BAD = ("karaoke", "tribute", "instrumental", "in the style", "made famous", "cover", "backing", "originally performed", "sped up", "slowed", "nightcore", "8d", "lullaby", "workout", "fitness", "piano", "acoustic", "live", "remaster", "re-recorded", "single version", "album version", "rap edition", "lo-fi", "cinematic", "a cappella", "acapella", "acappella")
GOOD = ("remix", "mix)", " mix", "edit", "club", "extended", "dub", "version", "re-edit", "rework")
n_it = 0
for k, (disp, af, obpm, disc) in SONGS.items():
    title = disp.split(" - ", 1)[1]; artist = disp.split(" - ")[0]
    seen = {o["url"] for o in out}
    for q in (f"{artist} {title} remix", f"{artist} {title} club mix"):
        try:
            with urllib.request.urlopen(urllib.request.Request("https://itunes.apple.com/search?term=" + urllib.parse.quote(q) + "&entity=song&limit=50&country=us", headers=UA), timeout=20) as r: res = json.loads(r.read().decode()).get("results", [])
        except Exception: res = []
        time.sleep(0.4)
        for h in res:
            tn = fold(h.get("trackName", "")); an = fold(h.get("artistName", ""))
            if not re.search(r"(^|[^a-z0-9])" + re.escape(af) + r"([^a-z0-9]|$)", an): continue
            if fold(title).strip(".!")[:10] not in tn: continue
            if any(b in tn for b in BAD) or not any(g in tn for g in GOOD): continue
            if re.search(r"\((radio edit|edit|radio version|radio mix)\)\s*$", tn) and not re.search(r"remix|mix\b|club", tn.replace(re.search(r"\((radio edit|edit|radio version|radio mix)\)\s*$", tn).group(0), "")): continue
            url = h.get("trackViewUrl") or h.get("collectionViewUrl")
            if not url or url in seen: continue
            seen.add(url); n_it += 1
            secs = int((h.get("trackTimeMillis") or 0) / 1000)
            ver = re.sub(r"^.*?\((.*)\)\s*$", r"\1", h["trackName"]) if "(" in h["trackName"] else h["trackName"]
            out.append({"song": disp, "key": k, "disc": disc, "obpm": obpm, "version": h["trackName"], "remixer": "", "kind": "official", "bpm": None, "length": f"{secs//60}:{secs%60:02d}" if secs else None,
                        "where": "Apple Music / iTunes Store", "url": url, "free": False, "verified": True, "note": f"On “{h.get('collectionName','')}” ({(h.get('releaseDate') or '')[:4]}), credited to {h.get('artistName','')}. Catalogue entry; not auditioned.",
                        "source": "iTunes catalogue", "id": hashlib.md5((url + "|" + h["trackName"]).encode()).hexdigest()[:10]})
def norm(v): return re.sub(r"[^a-z0-9]+", " ", fold(v)).strip()
seen_v = set(); dedup = []
for o in out:
    if o["source"] == "iTunes catalogue":
        nv = (o["key"], norm(o["version"]))
        if nv in seen_v: continue
        seen_v.add(nv)
    dedup.append(o)
out = dedup
def rank(o):
    v = fold(o["version"]); kind = {"official": 0, "pool": 1, "bootleg": 2}.get(o["kind"], 3)
    club = 0 if re.search(r"club|extended|12\W|x-tended", v) else (1 if "remix" in v or "mix" in v else 2)
    return (kind if o["source"] != "iTunes catalogue" else 0, club, 0 if o["verified"] else 1)
STOP = {"remix", "mix", "edit", "the", "of", "a", "and", "feat", "ft", "club", "version", "extended", "radio", "bootleg", "remixes", "single", "ep", "x", "vs", "in", "on", "it", "jay", "z", "jaÿ"}
def sig(o):
    v = fold(o["version"]); v = re.sub(r"[\[(]\s*(feat|ft)\.?[^\])]*[\])]", " ", v); v = re.sub(r"\b(19|20)\d{2}\b", " ", v)
    tw = set(re.findall(r"[a-z0-9']+", fold(o["song"])))
    return tuple(sorted(set(re.findall(r"[a-z0-9']+", v)) - STOP - tw))
final = []
for k in SONGS:
    g = sorted([o for o in out if o["key"] == k], key=rank)
    seen_u, seen_s, keep = set(), set(), []
    for o in g:
        u = o["url"].rstrip("/"); sg = sig(o)
        if u in seen_u or (sg and sg in seen_s): continue
        seen_u.add(u); seen_s.add(sg); keep.append(o)
    final += keep[:14]
out = final
# the shopping list's Britney link pointed at the Toxic album, which does not carry the Ospina mix: drop it if the catalogue found the real page
has_ospina = any("ospina" in fold(o["version"]) and o["source"] == "iTunes catalogue" for o in out)
out = [o for o in out if not (o["key"] == "...baby one more time" and o["source"].startswith("shopping") and has_ospina)]
json.dump(out, open("newfiles/club.json", "w"), indent=1, ensure_ascii=False)
import collections
print(len(out), "options;", n_it, "from iTunes;", dict(collections.Counter(o["source"].split()[0] for o in out)))
for k in SONGS: print(f"  {SONGS[k][0][:42]:42s} {len([o for o in out if o['key']==k])}")
