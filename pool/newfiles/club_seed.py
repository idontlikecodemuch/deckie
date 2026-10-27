import json, re, unicodedata, urllib.parse
items = json.load(open("shop/items.json"))
def fold(s): return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c)).lower()
SONGS = [  # canonical "artist first word", title core, original bpm, disc
 ("mark", "return of the mack", 95, "1"), ("notorious", "hypnotize", 94, "1"), ("coolio", "gangsta's paradise", 80, "1"), ("tlc", "no scrubs", 93, "1"),
 ("will", "gettin' jiggy wit it", 108, "1"), ("britney", "...baby one more time", 93, "1"), ("ace", "all that she wants", 94, "1"), ("ricky", "livin' la vida loca", 89, "1"),
 ("backstreet", "everybody (backstreet's back)", 108, "1"), ("cranberries", "zombie", 84, "1"), ("stevie", "superstition", 100, "1"), ("ginuwine", "pony", 71, "1"),
 ("50", "in da club", 90, "2"), ("kanye", "gold digger", 92, "2"), ("snoop", "drop it like it's hot", 92, "2"), ("usher", "yeah!", 105, "2"), ("nelly", "hot in herre", 107, "2"),
 ("beyonce", "crazy in love", 99, "2"), ("outkast", "hey ya!", 81, "2"), ("shakira", "hips don't lie", 100, "2"), ("dua", "levitating", 103, "2"), ("doja", "paint the town red", 100, "2"), ("rihanna", "umbrella", 87, "2"),
]
OK_HOSTS = ("qobuz.com", "music.apple.com", "bandcamp.com", "soundcloud.com", "djcity.com/records", "beatport.com/track", "hypeddit.com", "junodownload.com", "traxsource.com", "amazon.com", "gumroad.com")
KIND = {"BUY": "official", "POOL": "pool", "LISTEN": "official", "BOOT": "bootleg", "FIND": "original"}
out = []
for it in items:
    t = it["track"]; artist, title = (t.split(" - ", 1) + [""])[:2]
    title = fold(re.sub(r"\s*\((19|20)\d{2}\)\s*$", "", title)).strip()
    a0 = fold(artist).split()[0].rstrip(",") if artist else ""
    for af, tc, obpm, disc in SONGS:
        if a0 != af or title != tc: continue
        url = it.get("url") or ""
        if not any(h in url for h in OK_HOSTS): continue
        if it["kind"] == "FIND": continue
        v = it["version"]
        out.append({"song": f"{artist} - {it['track'].split(' - ', 1)[1]}".split(" (")[0], "key": tc, "disc": disc, "obpm": obpm, "version": v, "remixer": "", "kind": KIND.get(it["kind"], "bootleg"),
                    "bpm": int(it["bpm"]) if str(it["bpm"]).isdigit() else None, "length": None if it.get("len") in (None, "?") else it["len"], "where": it["src"], "url": url,
                    "free": "free" in (it.get("why") or "").lower(), "verified": False, "note": (it.get("why") or "")[:140], "source": f"shopping list #{it['rank']}", "id": it["id"]})
json.dump(out, open("newfiles/club_seed.json", "w"), indent=1, ensure_ascii=False)
import collections
print(len(out), "seed options;", collections.Counter(o["key"] for o in out))
