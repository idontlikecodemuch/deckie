"""Demo crate file for the explainer captures: a COPY of a crate file with every title, artist, file name and folder
replaced by invented ones, and disc / folder / track labels set. The analysis numbers are untouched. Never writes to
the source. usage: make_demo_crate.py <src.deckiecrate> <dst.deckiecrate>"""
import json, random, shutil, sys, os, re
src, dst = sys.argv[1], sys.argv[2]
assert not os.path.exists(dst)
shutil.copytree(src, dst)
rnd = random.Random(2026)
A = "Night Summer Velvet Neon Paper Golden Silver Midnight Electric Slow Second Last Open Quiet Lucky Northern Cherry Static Hollow Bright Sweet Wild Low Other Seven Blue Glass Honey Violet Long".split()
B = "Drive Signal Hearts Arcade Lights Motion Weather Rooms River Echo Season Stations Avenue Rhythm Fever Tides Harbour Letters Machine Garden Windows Horizon Telephone Mirrors Skyline Voltage Carousel Shadows Morning Satellites Postcards".split()
T1 = ["Hold the Line Open","Back Around","All Night Radio","Give It a Minute","Nothing to Lose Tonight","Turn It Over","Same Sky","Run the Lights","Heat Rising","Call Me Later","One More Time Around","Up From the Floor","Stay a While","Keep It Moving","Out of the Blue Room","Wait for the Drop","Let It Roll","Weekend Forever","Higher Ground Floor","Move With Me","Close to Midnight","Don't Look Down","In the Morning Light","Carry Me Home","Feel the Room","Under the Mirrorball","Somewhere to Be","Kind of Lovely","Two Step Closer","What the Night Wants"]
titles = set(T1)
while len(titles) < 400:
    a, b = rnd.choice(A), rnd.choice(B)
    titles.add(f"{a} {b}")
titles = sorted(titles); rnd.shuffle(titles)
P = "Harbour Lantern Marble Cobalt Juniper Copper Saffron Atlas Orchid Tundra Ember Linden Quartz Meridian Pollen Garnet Willow Cinder Fathom Alder".split()
Q = "Collective Unit Club Parade Assembly Exchange Society Committee Ensemble Department Motel Works Arcade Bureau Union".split()
acts = sorted({f"{rnd.choice(P)} {rnd.choice(Q)}" for _ in range(600)}); rnd.shuffle(acts); acts = acts[:85]
DISC = {"CD1": "Throwbacks", "CD2": "Chart", "CD3": "Singalongs", "CD4": "House"}
c = json.load(open(f"{dst}/crate.json"))
tr = c["tracks"]
tr.sort(key=lambda t: t["file"]["rel"])
groups = {}
for i, t in enumerate(tr):
    p = t["file"]["rel"].split("/")
    disc = DISC[p[0][:3]]
    folder = re.sub(r"^\d+ - ", "", p[1])
    folder = {"under 90": "Under 90", "150 plus": "150 plus"}.get(folder, folder)
    n = groups[(disc, folder)] = groups.get((disc, folder), 0) + 1
    title, artist = titles[i], acts[(i * 7) % len(acts)]
    idn = t["ident"]
    idn.update(title=title, artist=artist, disc=disc, folder=folder, track=n, tags=[], source="tag")
    name = f"{n:02d} {artist} - {title}.mp3"
    t["file"]["name"] = name
    t["file"]["rel"] = f"{disc}/{folder}/{name}"
json.dump(c, open(f"{dst}/crate.json", "w"), ensure_ascii=False)
m = json.load(open(f"{dst}/manifest.json"))
m["name"] = os.path.basename(dst).replace(".deckiecrate", "")
for e in m["import_log"]["entries"]:
    e["rel"] = "_old versions"
json.dump(m, open(f"{dst}/manifest.json", "w"), ensure_ascii=False)
blob = open(f"{dst}/crate.json").read() + open(f"{dst}/manifest.json").read()
print(len(tr), "tracks;", len(set(t['ident']['title'] for t in tr)), "titles;", sorted(groups.items())[:4])
