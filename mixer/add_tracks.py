#!/usr/bin/env python3
"""Add new MP3s (for example DJ transition edits) to candidates.json so analyze.py can map them.

    .venv/bin/python -I add_tracks.py "/path/to/folder" [--kind transition] [--src added]

Each file not already listed (by path) gets an id, title/artist from its tags (falls back to
the file name), duration and bitrate from ffprobe, and the TBPM tag as bpm_tag when present.
Prints the analyze.py command for the new ids. Nothing is analysed here.
"""
import argparse, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAND = os.path.join(HERE, "candidates.json")
EXT = (".mp3", ".m4a", ".wav", ".flac", ".aif", ".aiff")


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", path],
                         capture_output=True, text=True).stdout
    f = json.loads(out or "{}").get("format", {})
    tags = {k.lower(): v for k, v in (f.get("tags") or {}).items()}
    secs = float(f.get("duration") or 0)
    kbps = round(float(f.get("bit_rate") or 0) / 1000)
    return secs, kbps, tags


def norm(t):
    return re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--kind", default="added")
    ap.add_argument("--src", default="added")
    a = ap.parse_args()
    cands = json.load(open(CAND))
    have = {c["path"] for c in cands}
    new = []
    for root, _, files in os.walk(a.folder):
        for fn in sorted(files):
            if not fn.lower().endswith(EXT) or fn.startswith("."):
                continue
            p = os.path.join(root, fn)
            if p in have:
                continue
            secs, kbps, tags = probe(p)
            artist = tags.get("artist", "").strip()
            song = tags.get("title", "").strip()
            base = os.path.splitext(fn)[0]
            title = f"{artist} - {song}" if artist and song else base
            ver = ""
            m = re.search(r"\(([^)]*)\)\s*$", song or base)
            if m:
                ver = m.group(1).strip()
                title = title[: title.rfind("(")].strip() if "(" in title else title
            bpm = None
            try:
                bpm = float(re.sub(r"[^0-9.]", "", tags.get("tbpm", tags.get("bpm", "")))) or None
            except ValueError:
                pass
            row = {"id": hashlib.md5(("add|" + fn).encode()).hexdigest()[:10], "title": title, "ver": ver,
                   "path": p, "bpm_tag": bpm, "secs": round(secs), "len": f"{int(secs // 60)}:{int(secs % 60):02d}",
                   "mb": round(os.path.getsize(p) / 1e6, 1), "kbps": kbps, "hal": False, "kind": a.kind,
                   "era": "", "src": a.src, "intro": False, "on_disc": False, "disc": None, "folder": "",
                   "on_page": False, "page_selected": False, "deck": "", "artist": artist, "song": song,
                   "cut_key": norm(title) + " | " + norm(ver), "why": f"added from {a.folder}",
                   "is_longest": True, "longer_cut_id": None, "cut_versions": 1}
            cands.append(row)
            new.append(row)
            print(f"+ {row['id']}  {row['len']}  {kbps} kbps  bpm {bpm}  {title} ({ver})")
    if not new:
        print("nothing new in", a.folder)
        return
    json.dump(cands, open(CAND, "w"), indent=1, ensure_ascii=False)
    ids = ",".join(r["id"] for r in new)
    print(f"\n{len(new)} added to candidates.json. Analyse them with:\n"
          f'  cd "{HERE}" && .venv/bin/python analyze.py --ids {ids}\n'
          f"then: .venv/bin/python -I local_tempo.py && .venv/bin/python -I score.py && .venv/bin/python -I summary.py")


if __name__ == "__main__":
    main()
