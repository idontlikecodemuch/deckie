#!/usr/bin/env python3
"""Build the two MP3 CDs (CD1 Singalongs, CD2 Mix-ins) for the Pioneer CDJ-1000MK3 from newfiles/pool.json.

Re-runnable: every run wipes and rebuilds  ROOT/CDs v3/<disc>/ , the ISOs, MANIFEST.md and the track-list printouts.
Nothing is burned.

TODO (Oct 23, 2026): LOUDNESS IS NOT NORMALISED YET. The v3 discs span 12 dB (-14 to -2 LUFS) and Mike
complained about uneven volume last time. Before the next burn add a normalise step for every track (target
about -10 LUFS, -1 dBTP ceiling; mp3gain -s s -k if installed, else two-pass loudnorm + CBR 320) between the
copy and tag steps. Never touch the originals in place: Mike page/tracks/ are hard links to them. See README.

    cd "_pool build" && python3 build_two_discs.py            # full build: folders, ISOs, verify, manifest, printouts
    python3 build_two_discs.py --no-iso                       # skip the ISO + verify step

Selection = rows of pool.json with "rec": true. File names reuse deck_name() from newfiles/mike_data.py (pulled out of
that file with ast so its side effects do not run).
"""
import ast, html, json, os, re, shutil, subprocess, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
MUSIC_ROOT = os.environ.get("DECKIE_MUSIC_ROOT", "/Users/christophershannon/personal/90s2000 playlist")  # where the audio lives; never inside the repo
ROOT = MUSIC_ROOT  # pool.json paths are relative to the music folder
OUT = os.path.join(MUSIC_ROOT, "CDs v3")  # disc artifacts stay beside the audio
ISO_DIR = os.path.join(OUT, "ISO")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FOLDERS = ["1 - under 90", "2 - 90-99", "3 - 100-109", "4 - 110-119", "5 - 120-124", "6 - 125-129", "7 - 130-134", "8 - 135 plus"]
DISCS = [("S", "CD1 Singalongs", "CD1 SINGALONGS"), ("M", "CD2 Mix-ins", "CD2 MIX-INS")]
LIMIT_MB = 690
# Loudness (Oct 24, 2026): every file is normalised to the same integrated loudness with a true-peak ceiling,
# two-pass ffmpeg loudnorm in linear mode (a plain gain change; the ceiling can only reduce the lift), CBR 320.
NORMALISE = True
TARGET_I, TARGET_TP, TARGET_LRA = -10.0, -2.0, 20.0   # -2 dBTP before encoding: MP3 decode overshoots by up to ~2 dB
ALLOWED = re.compile(r"^[A-Za-z0-9 \-_.()',&]+$")


# ---------- deck_name() reused from mike_data.py without running that script ----------
def load_deck_name():
    src = open(os.path.join(HERE, "newfiles", "mike_data.py"), encoding="utf-8").read()
    keep = []
    for n in ast.parse(src).body:
        if isinstance(n, ast.FunctionDef) and n.name in ("_ascii", "deck_name"): keep.append(n)
        elif isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") in ("RMXW", "JOIN", "GENERIC"): keep.append(n)
    g = {"re": re, "unicodedata": unicodedata}
    exec(compile(ast.Module(keep, []), "mike_data.py", "exec"), g)
    return g["deck_name"], g["_ascii"]


deck_name, _ascii = load_deck_name()


def ascii_fold(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()


def clean_name(s):
    """Keep only characters the deck/Joliet handle safely."""
    s = re.sub(r"[^A-Za-z0-9 \-_.()',&]", "", ascii_fold(s))
    s = re.sub(r"\(\s*\)", "", s)
    return re.sub(r"\s+", " ", s).strip(" -")


def short_ver(ver):
    """Readable version for tags / printouts: drop Dirty/Clean markers and outer parens."""
    v = (ver or "").strip()
    if re.fullmatch(r"\([^()]*\)", v): v = v[1:-1]
    v = re.sub(r"\s*-\s*(Dirty|Clean)\b", "", v, flags=re.I)
    v = re.sub(r"\(\s*(Dirty|Clean)\s*\)", "", v, flags=re.I)
    v = re.sub(r"^\s*(Dirty|Clean)\s*$", "", v, flags=re.I)
    if len(v) > 36: v = re.sub(r"\s*\([^()]*\)\s*$", "", v)   # long: drop a trailing credit in parens
    return re.sub(r"\s+", " ", v).strip(" -")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def duration(path):
    r = run([FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path])
    return float(r.stdout.strip())


def mmss(secs):
    s = int(round(secs)); return f"{s // 60}:{s % 60:02d}"


# ---------- plan ----------
def plan():
    pool = json.load(open(os.path.join(HERE, "newfiles", "pool.json"), encoding="utf-8"))
    rows = [r for r in pool if r.get("rec")]
    discs = {}
    for code, name, vol in DISCS:
        sel = [r for r in rows if r["disc"] == code]
        folders = []
        for f in FOLDERS:
            fr = sorted([r for r in sel if r["folder"] == f], key=lambda r: (r["bpm"], r["title"].lower()))
            if not fr: continue
            used, items = set(), []
            for i, r in enumerate(fr, 1):
                artist, song = r["title"].split(" - ", 1) if " - " in r["title"] else ("", r["title"])
                deck = clean_name(deck_name(r))
                fname = f"{i:02d} " + ("H " if r["hal"] else "") + deck + ".mp3"
                assert len(fname) <= 63, fname
                assert ALLOWED.match(fname), fname
                assert fname.lower() not in used, fname
                used.add(fname.lower())
                src = os.path.join(ROOT, r["path"]); assert os.path.isfile(src), src
                sv = short_ver(r["ver"])
                items.append(dict(r=r, nn=i, fname=fname, deck=deck, src=src, artist=artist, song=song, sv=sv,
                                  shortened=not deck.startswith(clean_name(_ascii(r["title"]))) or deck != deck_name(r)))
            folders.append((f, items))
        discs[code] = dict(name=name, vol=vol, folders=folders, dir=os.path.join(OUT, name))
    assert sum(len(it) for d in discs.values() for _, it in d["folders"]) == len(rows)
    return discs


# ---------- loudness ----------
def measure_loudness(src):
    """Pass 1 of loudnorm: returns the measured dict (input_i, input_tp, input_lra, input_thresh, target_offset)."""
    p = run([FFMPEG, "-v", "info", "-nostats", "-i", src, "-map", "0:a:0", "-af",
             f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:print_format=json", "-f", "null", "-"])
    txt = p.stderr
    i = txt.rfind("{"); j = txt.rfind("}")
    if i < 0 or j < 0: raise SystemExit(f"loudnorm measurement failed on {src}: {txt[-400:]}")
    return json.loads(txt[i:j + 1])


def loudnorm_filter(m):
    return (f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:measured_I={m['input_i']}:measured_LRA={m['input_lra']}"
            f":measured_TP={m['input_tp']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true:print_format=json")


# ---------- stage audio ----------
def stage(d):
    if os.path.isdir(d["dir"]): shutil.rmtree(d["dir"])   # clean rebuild, no stale files
    problems = []
    for f, items in d["folders"]:
        fdir = os.path.join(d["dir"], f); os.makedirs(fdir)
        for it in items:
            r = it["r"]; dst = os.path.join(fdir, it["fname"])
            title = ascii_fold(it["song"]) + (f" ({ascii_fold(it['sv'])})" if it["sv"] else "")
            # a song whose start and end tempo differ (trusted at both ends) gets the jump in its title for the deck
            _fp = os.path.join(HERE, "mixer", "features", r["id"] + ".json")
            if os.path.exists(_fp):
                _lt = json.load(open(_fp)).get("local_tempo") or {}
                if _lt.get("in_trusted") and _lt.get("out_trusted") and abs(_lt.get("drift_pct", 0)) > 5:
                    title += f" [{round(_lt['bpm_in'])} to {round(_lt['bpm_out'])}]"
            meta = {"artist": ascii_fold(it["artist"]), "title": title, "TBPM": str(r["bpm"]), "album": d["name"], "track": f"{it['nn']:02d}"}
            if r["hal"]: meta["genre"] = "Halloween"
            br = run([FFPROBE, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=bit_rate", "-of", "csv=p=0", it["src"]]).stdout.strip().strip(",")
            it["reenc"] = (int(br) if br.isdigit() else 0) < 300000   # v2 rule: every file on the disc is CBR 320
            if NORMALISE:
                m = measure_loudness(it["src"]); it["lufs_in"] = float(m["input_i"]); it["tp_in"] = float(m["input_tp"])
                codec = ["-af", loudnorm_filter(m), "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "320k"]
            else:
                codec = ["-c:a", "libmp3lame", "-b:a", "320k"] if it["reenc"] else ["-c", "copy"]
            cmd = [FFMPEG, "-v", "info" if NORMALISE else "error", "-nostats", "-y", "-i", it["src"], "-map", "0:a:0", "-map_metadata", "-1", "-map_chapters", "-1"] + codec + [
                   "-id3v2_version", "3", "-write_id3v1", "0", "-fflags", "+bitexact"]
            for k, v in meta.items(): cmd += ["-metadata", f"{k}={v}"]
            p = run(cmd + [dst])
            if p.returncode: raise SystemExit(f"ffmpeg failed on {it['src']}: {p.stderr}")
            if NORMALISE:
                i, j = p.stderr.rfind("{"), p.stderr.rfind("}")
                o = json.loads(p.stderr[i:j + 1]) if i >= 0 and j > i else {}
                it["lufs_out"] = float(o.get("output_i", "nan")); it["tp_out"] = float(o.get("output_tp", "nan"))
                how = "gain"
                if it["lufs_out"] < TARGET_I - 1.0:
                    # peaks stopped the plain gain short of the target: gain to target + a peak limiter at the ceiling
                    gain = TARGET_I - it["lufs_in"]
                    lim = 10 ** (TARGET_TP / 20)
                    cmd2 = [FFMPEG, "-v", "error", "-nostats", "-y", "-i", it["src"], "-map", "0:a:0", "-map_metadata", "-1", "-map_chapters", "-1",
                            "-af", f"volume={gain:.2f}dB,alimiter=limit={lim:.4f}:attack=5:release=60:level=false", "-ar", "44100",
                            "-c:a", "libmp3lame", "-b:a", "320k", "-id3v2_version", "3", "-write_id3v1", "0", "-fflags", "+bitexact"]
                    for k, v in meta.items(): cmd2 += ["-metadata", f"{k}={v}"]
                    def _lim_pass(g):
                        c = list(cmd2); c[c.index("-af") + 1] = f"volume={g:.2f}dB,alimiter=limit={lim:.4f}:attack=5:release=60:level=false"
                        pp = run(c + [dst])
                        if pp.returncode: raise SystemExit(f"ffmpeg limiter pass failed on {it['src']}: {pp.stderr}")
                        mm = run([FFMPEG, "-v", "info", "-nostats", "-i", dst, "-af", "ebur128=peak=true", "-f", "null", "-"]).stderr
                        a = re.search(r"Integrated loudness:\s*\n\s*I:\s*(-?[0-9.]+)", mm); b = re.search(r"True peak:\s*\n\s*Peak:\s*(-?[0-9.]+)", mm)
                        return (float(a.group(1)) if a else float("nan")), (float(b.group(1)) if b else float("nan"))
                    it["lufs_out"], it["tp_out"] = _lim_pass(gain)
                    if it["lufs_out"] < TARGET_I - 0.5:          # the limiter ate some loudness: one correction pass
                        gain += TARGET_I - it["lufs_out"]
                        it["lufs_out"], it["tp_out"] = _lim_pass(gain)
                    how = f"gain {gain:+.1f} dB + limiter"
                problems.append(f"{f}/{it['fname']}: level {it['lufs_in']:+.1f} -> {it['lufs_out']:+.1f} LUFS (peak {it['tp_out']:+.1f} dBTP, {how})")
            it["title_tag"] = title
            it["dur_src"], it["dur"] = duration(it["src"]), duration(dst)
            it["bytes"] = os.path.getsize(dst)
            if abs(it["dur_src"] - it["dur"]) > 1.0: problems.append(f"{f}/{it['fname']}: duration {it['dur_src']:.1f}s -> {it['dur']:.1f}s")
            if abs(it["dur"] - r["secs"]) > 2: problems.append(f"{f}/{it['fname']}: duration {it['dur']:.1f}s vs pool {r['secs']}s")
            if NORMALISE: pass   # every file is re-encoded, so size against the pool means nothing
            elif it["reenc"]: problems.append(f"{f}/{it['fname']}: re-encoded to CBR 320 from {int(br)//1000 if br.isdigit() else '?'} kbps (v2 rule)")
            elif abs(it["bytes"] / 1e6 - r["mb"] * 1.048576) > 0.6 and abs(it["bytes"] / 1e6 - r["mb"]) > 0.6:
                art = "video" in run([FFPROBE, "-v", "error", "-show_entries", "stream=codec_type", "-of", "csv=p=0", it["src"]]).stdout
                problems.append(f"{f}/{it['fname']}: size {it['bytes'] / 1e6:.1f} MB vs pool {r['mb']} MB"
                                + (" (embedded cover art stripped; audio duration unchanged)" if art else ""))
    return problems


def staged_listing(folder):
    out = {}
    for dp, dn, fn in os.walk(folder):
        dn.sort()
        for n in fn:
            p = os.path.join(dp, n); out[os.path.relpath(p, folder)] = os.path.getsize(p)
    return out


# ---------- ISO ----------
def build_iso(d):
    os.makedirs(ISO_DIR, exist_ok=True)
    for dp, dn, fn in os.walk(d["dir"]):
        for n in fn:
            if n.startswith(".") or n.startswith("._"): os.remove(os.path.join(dp, n))
    iso = os.path.join(ISO_DIR, d["name"] + ".iso")
    if os.path.exists(iso): os.remove(iso)
    p = run(["hdiutil", "makehybrid", "-iso", "-joliet", "-default-volume-name", d["vol"], "-o", iso, d["dir"]])
    if p.returncode: raise SystemExit(p.stderr)
    d["iso"] = iso; d["iso_bytes"] = os.path.getsize(iso)
    # verify by mounting read-only
    p = run(["hdiutil", "attach", "-readonly", "-nobrowse", iso])
    if p.returncode: raise SystemExit(p.stderr)
    line = [l for l in p.stdout.splitlines() if "/Volumes/" in l][-1]
    dev, mnt = line.split()[0], line[line.index("/Volumes/"):].strip()
    d["mount_name"] = os.path.basename(mnt)
    try:
        info = run(["diskutil", "info", dev]).stdout
        d["fs"] = (re.search(r"File System Personality:\s*(.+)", info) or [None, "?"])[1].strip()
        on_iso, staged = staged_listing(mnt), staged_listing(d["dir"])
        errs = []
        if len(on_iso) != len(staged): errs.append(f"file count {len(on_iso)} on ISO vs {len(staged)} staged")
        for k, v in staged.items():
            if k not in on_iso: errs.append(f"missing/renamed on ISO: {k}")
            elif on_iso[k] != v: errs.append(f"size differs: {k} {on_iso[k]} vs {v}")
        for k in on_iso:
            if k not in staged: errs.append(f"extra on ISO: {k}")
            if len(os.path.basename(k)) > 63: errs.append(f"name too long on ISO: {k}")
        d["iso_files"] = len(on_iso); d["iso_errs"] = errs
        d["iso_folders"] = sorted(os.listdir(mnt))
    finally:
        run(["hdiutil", "detach", dev])


# ---------- manifest ----------
def disc_totals(d):
    items = [it for _, its in d["folders"] for it in its]
    return len(items), sum(it["bytes"] for it in items) / 1e6, sum(it["dur"] for it in items) / 60


def write_manifest(discs):
    L = ["# CDs v3 manifest", "",
         "Two MP3 CDs for the Pioneer CDJ-1000MK3, built by `_pool build/build_two_discs.py` from `newfiles/pool.json` (rows with rec true).",
         "BPM in brackets. Folders are numbered slow -> fast and files inside each folder are numbered in ascending tempo (ties by title).",
         "`H` = Halloween track (also in the file name, so it shows on the deck, and genre tag = Halloween).", ""]
    for d in discs.values():
        n, mb, mins = disc_totals(d)
        L.append(f"## {d['name']} — {n} tracks, {mb:.0f} MB, {mins:.0f} min" + (f" (ISO {d['iso_bytes'] / 1e6:.0f} MB)" if d.get("iso_bytes") else ""))
        L.append("")
        for f, items in d["folders"]:
            L.append(f"### {f} ({len(items)})")
            for it in items:
                L.append(f"- {it['nn']:02d} [{it['r']['bpm']}] " + ("H " if it["r"]["hal"] else "") + it["r"]["title"] + (f" ({it['sv']})" if it["sv"] else ""))
            L.append("")
    L += ["## File names on disc", "", "Name on the deck browser = file name; artist/title from the ID3 tags.", ""]
    for d in discs.values():
        L.append(f"### {d['name']}")
        for f, items in d["folders"]:
            for it in items: L.append(f"- `{f}/{it['fname']}`")
        L.append("")
    open(os.path.join(OUT, "MANIFEST.md"), "w", encoding="utf-8").write("\n".join(L))


# ---------- printouts ----------
CSS = """
@page { size: letter; margin: 0.4in; }
@page land { size: letter landscape; margin: 0.3in; }
* { box-sizing: border-box; }
body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; color: #111; margin: 0; }
.page { break-after: page; }
.page:last-child { break-after: auto; }
.landscape { page: land; }
h1 { font-size: 16pt; margin: 0 0 1pt; }
.sub { font-size: 8pt; color: #555; margin-bottom: 5pt; }
table { width: 100%; border-collapse: collapse; font-size: 8pt; table-layout: fixed; }
td, th { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
th { text-align: left; font-size: 6.8pt; text-transform: uppercase; letter-spacing: .04em; color: #555; border-bottom: 1pt solid #111; padding: 1.5pt 3pt; }
td { padding: 1.3pt 3pt; border-bottom: .4pt solid #ddd; }
tr.fold td { background: #111; color: #fff; font-weight: 700; padding: 1.8pt 4pt; border: 0; }
col.n { width: 4.5%; } col.b { width: 5.5%; } col.h { width: 3.5%; } col.a { width: 25%; } col.s { width: 30%; } col.v { width: 25%; } col.l { width: 6.5%; }
td.n, td.b, td.l { font-variant-numeric: tabular-nums; }
td.b { font-weight: 700; } td.l, th.l { text-align: right; }
td.h { color: #c45500; font-weight: 800; text-align: center; } th.h { text-align: center; }
td.v { color: #555; font-style: italic; }
tr.hal td.s { font-weight: 600; }
.both { display: flex; gap: 14pt; }
.both > div { flex: 1; min-width: 0; }
.both table { font-size: 6.2pt; }
.both th { font-size: 5.4pt; padding: .8pt 2pt; }
.both td { padding: .55pt 2pt; }
.both tr.fold td { padding: .9pt 3pt; }
.both h2 { font-size: 10pt; margin: 0 0 2pt; }
.both col.n { width: 5%; } .both col.b { width: 6%; } .both col.h { width: 4%; } .both col.a { width: 25%; } .both col.s { width: 29%; } .both col.v { width: 23%; } .both col.l { width: 8%; }
"""


def table(d, both=False):
    h = ['<table><colgroup><col class="n"><col class="b"><col class="h"><col class="a"><col class="s"><col class="v"><col class="l"></colgroup><thead><tr><th>#</th><th>BPM</th><th class="h">H</th><th>Artist</th><th>Song</th><th>Version</th><th class="l">Length</th></tr></thead><tbody>']
    for f, items in d["folders"]:
        h.append(f'<tr class="fold"><td colspan="7">{html.escape(f)} BPM &middot; {len(items)} tracks</td></tr>')
        for it in items:
            r = it["r"]
            h.append(f'<tr class="{"hal" if r["hal"] else ""}"><td class="n">{it["nn"]:02d}</td><td class="b">{r["bpm"]}</td>'
                     f'<td class="h">{"H" if r["hal"] else ""}</td><td>{html.escape(it["artist"])}</td><td class="s">{html.escape(it["song"])}</td>'
                     f'<td class="v">{html.escape(it["sv"])}</td><td class="l">{mmss(it["dur"])}</td></tr>')
    h.append("</tbody></table>")
    return "".join(h)


def write_printouts(discs):
    pages = []
    for d in discs.values():
        n, mb, mins = disc_totals(d)
        pages.append(f'<section class="page"><h1>{html.escape(d["name"])}</h1><div class="sub">{n} tracks &middot; {mb:.0f} MB &middot; {mins:.0f} min &middot; '
                     f'folders slow &rarr; fast, tracks in tempo order &middot; H = Halloween</div>{table(d)}</section>')
    cols = []
    for d in discs.values():
        n, mb, mins = disc_totals(d)
        cols.append(f'<div><h2>{html.escape(d["name"])} <span style="font-weight:400;color:#555;font-size:8pt">{n} tracks &middot; {mins:.0f} min</span></h2>{table(d, True)}</div>')
    pages.append(f'<section class="page landscape"><h1 style="font-size:13pt">Both discs side by side</h1><div class="sub">H = Halloween &middot; folders slow &rarr; fast</div>'
                 f'<div class="both">{"".join(cols)}</div></section>')
    doc = f'<!doctype html><html><head><meta charset="utf-8"><title>CDs v3 track lists</title><style>{CSS}</style></head><body>{"".join(pages)}</body></html>'
    hp = os.path.join(OUT, "Track lists - CD1 and CD2.html"); open(hp, "w", encoding="utf-8").write(doc)
    pdf = os.path.join(OUT, "Track lists - CD1 and CD2.pdf")
    if os.path.exists(CHROME):
        p = run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf}", "file://" + hp], timeout=120)
    else:
        with open(pdf, "wb") as fh: p = subprocess.run(["cupsfilter", hp], stdout=fh, stderr=subprocess.PIPE)
    pages_n = len(re.findall(rb"/Type\s*/Page[^s]", open(pdf, "rb").read())) if os.path.exists(pdf) else 0
    return hp, pdf, pages_n


def main():
    no_iso = "--no-iso" in sys.argv
    discs = plan()
    os.makedirs(OUT, exist_ok=True)
    problems = []
    for d in discs.values():
        problems += stage(d)
        n, mb, mins = disc_totals(d)
        print(f"{d['name']}: {n} tracks, {mb:.1f} MB, {mins:.1f} min")
        assert mb < LIMIT_MB, f"{d['name']} over {LIMIT_MB} MB"
    if not no_iso:
        for d in discs.values():
            build_iso(d)
            print(f"  ISO {os.path.basename(d['iso'])}: {d['iso_bytes']:,} bytes ({d['iso_bytes'] / 1e6:.1f} MB, {d['iso_bytes'] / 2**20:.1f} MiB), "
                  f"mounts as /Volumes/{d['mount_name']} [{d['fs']}], {d['iso_files']} files, folders {d['iso_folders']}, "
                  + ("verify OK" if not d["iso_errs"] else "VERIFY FAILED: " + "; ".join(d["iso_errs"])))
            assert d["iso_bytes"] < LIMIT_MB * 2**20
    write_manifest(discs)
    hp, pdf, pn = write_printouts(discs)
    print(f"Printouts: {hp}\n           {pdf} ({pn} pages)")
    print("Shortened names (deck name differs from 'Artist - Song'):")
    for d in discs.values():
        for f, items in d["folders"]:
            for it in items:
                if it["shortened"]: print(f"  {d['name']}/{f}/{it['fname']}   <- {it['r']['title']} [{it['r']['ver']}]")
    print("Duration/size problems:" if problems else "Duration/size: all within tolerance")
    for p in problems: print("  " + p)
    longest = max((len(it["fname"]), it["fname"]) for d in discs.values() for _, its in d["folders"] for it in its)
    print(f"Longest file name: {longest[0]} chars ({longest[1]})")


if __name__ == "__main__":
    main()
