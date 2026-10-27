#!/usr/bin/env python3
"""Read the text Mike sends back from the page's "Send final mix" button and show what changed.
usage: python3 apply_mike.py "Mike final mix.txt" [--write]
--write stores the result as newfiles/selection_v2.json (same shape as selection_v1.json) so pool_build.py can be pointed at it."""
import json, os, re, sys
SP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = json.load(open(os.path.join(SP, "newfiles", "pool.json"))); byid = {r["id"]: r for r in P}
txt = open(sys.argv[1], encoding="utf-8").read()
def ids(label):
    m = re.search(label + r" ON:\s*([0-9a-f,\s]*)", txt)
    if not m: sys.exit(f"no '{label} ON:' line found; is this the whole text?")
    return [x for x in re.split(r"[,\s]+", m.group(1).strip()) if x]
on = {"S": ids("CD1"), "M": ids("CD2")}
unknown = [x for d in on.values() for x in d if x not in byid]
if unknown: print("unknown ids (ignored):", unknown)
notes = re.search(r"Notes for Chris:?\s*\n(.*?)(?:\n\s*\n|$)", txt, re.S)
if notes and notes.group(1).strip(): print("Mike's notes:\n  " + notes.group(1).strip().replace("\n", "\n  ") + "\n")
total_changes = 0
for d, label in (("S", "CD1 Singalongs"), ("M", "CD2 Mix-ins")):
    want = [x for x in on[d] if x in byid]; cur = {r["id"] for r in P if r["rec"] and r["disc"] == d}
    add = [x for x in want if x not in cur]; rem = [x for x in cur if x not in want]; total_changes += len(add) + len(rem)
    mb = round(sum(byid[x]["mb"] for x in want), 1)
    print(f"== {label}: {len(want)} tracks, {mb} MB (budget 690){'  OVER BUDGET' if mb > 690 else ''}")
    for x in add: r = byid[x]; print(f"  + {r['bpm']:>3} {r['len']:>5} {r['mb']:>5}MB  {r['title']}{(' — ' + r['ver']) if r['ver'] else ''}")
    for x in rem: r = byid[x]; print(f"  - {r['bpm']:>3} {r['len']:>5} {r['mb']:>5}MB  {r['title']}{(' — ' + r['ver']) if r['ver'] else ''}")
print(f"{total_changes} change(s) against the current pool selection")
ms = re.search(r"STARRED:\s*([0-9a-f,\s]*)", txt)
chains = re.findall(r"^CHAIN (.+?):\s*([0-9a-f>\s]+)$", txt, re.M)
if chains:
    print(f"\nMike's chains ({len(chains)}):")
    for name, body in chains:
        cids = [c for c in body.replace(" ", "").split(">") if c]
        print(f"  [{name.strip()}]")
        for i, x in enumerate(cids):
            r = byid.get(x)
            print(f"    {i+1}. " + (f"{r['bpm']:>3} {r['title']}{(' — ' + r['ver']) if r['ver'] else ''} [{'CD1' if r['disc'] == 'S' else 'CD2'}]" if r else f"unknown id {x}"))
    try:
        json.dump([{"name": n.strip(), "ids": [c for c in b.replace(" ", "").split(">") if c]} for n, b in chains], open("mike_chains.json", "w"), indent=1)
        print("  saved to newfiles/mike_chains.json")
    except Exception as e: print("  (could not save chains:", e, ")")
stars = [x for x in re.split(r"[,\s]+", (ms.group(1) if ms else "").strip()) if x and x in byid]
if stars:
    print(f"\nMike starred {len(stars)}:")
    for x in stars: r = byid[x]; print(f"  * {r['bpm']:>3} {r['len']:>5}  {r['title']}{(' — ' + r['ver']) if r['ver'] else ''}  [{'CD1' if r['disc'] == 'S' else 'CD2'}{'' if r['rec'] else ', off'}]")
if "--write" in sys.argv:
    out = [{"id": x, "disc": d, "title": byid[x]["title"], "ver": byid[x]["ver"], "src": byid[x]["srclabel"], "mb": byid[x]["mb"], "bpm": byid[x]["bpm"]} for d in ("S", "M") for x in on[d] if x in byid]
    dst = os.path.join(SP, "newfiles", "selection_v2.json"); json.dump(out, open(dst, "w"), indent=1, ensure_ascii=False)
    print("wrote", dst, "- point pool_build.py's SEL at selection_v2.json, then rerun pool_build.py, page_build.py and mike_data.py")
