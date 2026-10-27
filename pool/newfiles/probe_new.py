import json, os, subprocess, hashlib, time, sys
ROOT = "/Users/christophershannon/personal/90s2000 playlist"; S = os.path.dirname(os.path.abspath(__file__))
old = {p["file"]: p for p in json.load(open(f"{S}/probe.json"))}
cut = time.mktime((2026, 10, 20, 18, 0, 0, 0, 0, -1))  # Oct 20 2026 evening: the Oct 17 singles are already on the discs
files = sorted(f for f in os.listdir(ROOT) if os.path.isfile(os.path.join(ROOT, f)) and f.lower().endswith((".mp3", ".mp4", ".m4a", ".wav", ".aiff", ".flac")) and os.path.getmtime(os.path.join(ROOT, f)) > cut)
out = []
for f in files:
    if f in old: out.append(old[f]); continue
    p = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", os.path.join(ROOT, f)], capture_output=True, text=True)
    d = json.loads(p.stdout or "{}"); fmt = d.get("format", {}); a = next((s for s in d.get("streams", []) if s.get("codec_type") == "audio"), {})
    tags = {k.lower(): v for k, v in fmt.get("tags", {}).items()}; dur = float(fmt.get("duration", 0) or 0)
    o = {"file": f, "size_mb": round(os.path.getsize(os.path.join(ROOT, f))/1e6, 1), "dur": f"{int(dur)//60}:{int(dur)%60:02d}", "secs": round(dur), "codec": a.get("codec_name"), "kbps": round(int(fmt.get("bit_rate", 0) or 0)/1000), "hz": a.get("sample_rate"), "ch": a.get("channels"),
         "tag_title": tags.get("title"), "tag_artist": tags.get("artist"), "tag_bpm": tags.get("tbpm") or tags.get("bpm"), "tag_key": tags.get("tkey"), "tag_comment": "", "md5": hashlib.md5(open(os.path.join(ROOT, f), "rb").read()).hexdigest()[:10], "err": p.stderr.strip()[:80]}
    if o["secs"] and not o["tag_bpm"] and f.lower().endswith(".mp3"):
        q = subprocess.run(["aubiotrack", "-i", os.path.join(ROOT, f)], capture_output=True, text=True); b = [float(x) for x in q.stdout.split()]
        n = len(b); m = b[int(n*.2):int(n*.8)] if n > 20 else b; iv = [y-x for x,y in zip(m, m[1:]) if .25 < y-x < 1.5]
        import statistics; o["aubio"] = round(60/statistics.median(iv)/1.015) if iv else None
    out.append(o)
    print(f"NEW  {o['dur']:>5} {o['kbps']:>4} kbps  tag bpm {o['tag_bpm'] or '-':>4}  aubio {o.get('aubio','-')!s:>4}  {f}" + (f"  <<{o['err']}" if o["err"] else ""))
json.dump(out, open(f"{S}/probe.json", "w"), indent=1)
lp = json.load(open(f"{S}/library_probe.json"))
for o in out:
    if o["file"] not in lp and o["secs"]: lp[o["file"]] = {"secs": o["secs"], "mb": o["size_mb"], "kbps": o["kbps"], "hz": o["hz"], "title": o["tag_title"], "artist": o["tag_artist"], "album": None, "year": "", "tbpm": o["tag_bpm"], "genre": None}
json.dump(lp, open(f"{S}/library_probe.json", "w"), indent=0)
print(len(out), "rows in probe.json")
