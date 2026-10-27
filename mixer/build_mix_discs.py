#!/usr/bin/env python3
"""Stage one or two long mix MP3s as MP3 CDs (one file per disc, ISO 9660 + Joliet, same layout
rules as CDs v3) and build their ISOs under ../../CDs mix/.

    .venv/bin/python -I build_mix_discs.py "mixes/1 - Haunted Disco.mp3" "mixes/2 - Witching Hour Warehouse.mp3"

Each disc folder holds a single "01 <Mix name>.mp3" with ID3v2.3 tags (no ID3v1, no art) and an
empty index.html, plus the cue/tracklist copied beside it for reference (not on the disc).
Burn with: hdiutil burn -forceclose -underrun -speed 10 -noverifyburn -noeject "<iso>"
"""
import os, re, shutil, subprocess, sys, unicodedata
FFMPEG = "/opt/homebrew/bin/ffmpeg"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "CDs mix")
ALLOWED = re.compile(r"[^A-Za-z0-9 \-_.()',&]")
def ascii_fold(s): return ALLOWED.sub("", unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode())
def run(cmd): return subprocess.run(cmd, capture_output=True, text=True)
os.makedirs(os.path.join(OUT, "ISO"), exist_ok=True)
for n, src in enumerate(sys.argv[1:], 1):
    base = os.path.splitext(os.path.basename(src))[0]
    name = ascii_fold(re.sub(r"^\d+\s*-\s*", "", base)).strip()
    vol = "HALLOWEEN MIX" if len(sys.argv) == 2 else f"HALLOWEEN MIX {n}"
    ddir = os.path.join(OUT, name if len(sys.argv) == 2 else f"Mix {n} - {name}")
    if os.path.isdir(ddir): shutil.rmtree(ddir)
    os.makedirs(ddir)
    dst = os.path.join(ddir, f"01 {name}.mp3")
    p = run([FFMPEG, "-v", "error", "-y", "-i", src, "-map", "0:a:0", "-map_metadata", "-1", "-c", "copy",
             "-id3v2_version", "3", "-write_id3v1", "0", "-fflags", "+bitexact",
             "-metadata", f"title={name}", "-metadata", "artist=Chris Shannon", "-metadata", "album=Halloween 2026 mixes",
             "-metadata", f"track={n:02d}", "-metadata", "genre=Halloween", dst])
    if p.returncode: raise SystemExit(p.stderr)
    open(os.path.join(ddir, "index.html"), "w").close()
    for ext in (".cue", ".txt"):
        side = os.path.splitext(src)[0] + ext
        if os.path.exists(side): shutil.copy(side, os.path.join(OUT, f"Mix {n} - {name}{ext}"))
    iso = os.path.join(OUT, "ISO", (name if len(sys.argv) == 2 else f"Mix {n} - {name}") + ".iso")
    if os.path.exists(iso): os.remove(iso)
    p = run(["hdiutil", "makehybrid", "-iso", "-joliet", "-default-volume-name", vol, "-o", iso, ddir])
    if p.returncode: raise SystemExit(p.stderr)
    mb = os.path.getsize(dst) / 1e6
    print(f"disc {n}: {os.path.basename(dst)}  {mb:.0f} MB  -> {iso} ({os.path.getsize(iso)/1e6:.0f} MB)  volume {vol}")
