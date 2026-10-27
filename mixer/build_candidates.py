#!/usr/bin/env python3
"""Rebuild mixer/candidates.json from the pool: every non-library row (the four v2 discs plus
additions), with on_disc/page flags and the longest cut of each song version marked."""
import json, os, re, collections
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MUSIC_ROOT = os.environ.get("DECKIE_MUSIC_ROOT", "/Users/christophershannon/personal/90s2000 playlist")  # where the audio lives; never inside the repo
ROOT = MUSIC_ROOT
rows = json.load(open(os.path.join(REPO, "pool", "newfiles", "pool.json")))
pd = json.load(open(os.path.join(REPO, "web-player", "data.json")))
page = {t["id"]: t for t in (pd["tracks"] if isinstance(pd, dict) else pd)}
extra = set(json.load(open(os.path.join(HERE, "extra_lib_ids.json")))) if os.path.exists(os.path.join(HERE, "extra_lib_ids.json")) else set()
sel = [r for r in rows if r.get("src") != "lib" or r["id"] in extra]   # library tracks listed in extra_lib_ids.json join the candidates
def norm(t): return re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()
STRIP = re.compile(r"\b(extended|ext|mix|version|edit|re edit|fan edit|official|original|album|radio|single|club|intro|outro|1|2)\b")
def base_ver(v): return re.sub(r"\s+", " ", STRIP.sub(" ", norm(v))).strip()
out = []
for r in sel:
    out.append({"id": r["id"], "title": r["title"], "ver": r.get("ver", ""), "path": os.path.join(ROOT, r["path"]),
                "bpm_tag": r.get("bpm"), "secs": r.get("secs"), "len": r.get("len"), "mb": r.get("mb"), "kbps": r.get("kbps"),
                "hal": bool(r.get("hal")), "kind": r.get("kind"), "era": r.get("era", ""), "src": r.get("src"), "intro": bool(r.get("intro")),
                "on_disc": bool(r.get("rec")), "disc": r.get("disc") if r.get("rec") else None, "folder": r.get("folder"),
                "on_page": r["id"] in page, "page_selected": bool(page.get(r["id"], {}).get("selected")),
                "deck": page.get(r["id"], {}).get("deck", ""), "artist": page.get(r["id"], {}).get("artist", ""), "song": page.get(r["id"], {}).get("song", ""),
                "cut_key": norm(r["title"]) + " | " + base_ver(r.get("ver", "")), "why": r.get("why", "")})
groups = collections.defaultdict(list)
for o in out: groups[o["cut_key"]].append(o)
for g in groups.values():
    g.sort(key=lambda o: (-(o["secs"] or 0), not o["on_disc"], -(o["kbps"] or 0)))
    for i, o in enumerate(g):
        o["is_longest"] = i == 0; o["longer_cut_id"] = None if i == 0 else g[0]["id"]; o["cut_versions"] = len(g)
# keep rows added by add_tracks.py (not in the pool)
old = {c["id"]: c for c in json.load(open(os.path.join(HERE, "candidates.json")))} if os.path.exists(os.path.join(HERE, "candidates.json")) else {}
ids = {o["id"] for o in out}
out += [c for c in old.values() if c.get("src") == "added" and c["id"] not in ids]
json.dump(out, open(os.path.join(HERE, "candidates.json"), "w"), indent=1, ensure_ascii=False)
print(f"candidates: {len(out)} (on disc {sum(o['on_disc'] for o in out)}, on page {sum(o['on_page'] for o in out)})")
