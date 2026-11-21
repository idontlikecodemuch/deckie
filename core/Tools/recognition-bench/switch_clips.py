#!/usr/bin/env python3
"""Clips of a DJ changing songs, for the listeners of docs/research/faster-listening-proposals.md. Needs only numpy
and ffmpeg, so it runs on any computer with a folder of songs. Nothing it writes belongs in the repository.

  switch_clips.py songs MUSIC_DIR WORK         list a folder of songs (any format ffmpeg reads) as WORK/songs.tsv:
                                               id (a hash of the file's path under MUSIC_DIR), path. Skip it when a
                                               songs.tsv with the crate's own ids is at hand (id <tab> path first).
  switch_clips.py make WORK [--rooms DATA] [--n 40] [--seed 7] [--role eval] [--kinds ...] [--jobs 4]
                                               the clips: WORK/switch/<role>/clips.tsv (for deckie-listen --list),
                                               truth.jsonl (what plays when) and the sound (16 kHz, 16-bit, mono)

The song list: id <tab> path, then optionally bucket, seconds and role (make_queries.py's songs.tsv has all five).
Without a role, a song's role is a hash of its id, as everywhere in the bench: one in ten "absent" (not in the crate),
the rest half "dev", half "eval". `--role` picks the half the clips come from; songs for "not in the crate" clips are
the absent ones (they must be left out of the index: deckie-listen --leave-out). With every song in the crate, those
clips are not made.

Kinds of clip (--kinds, default all). Times are seconds of listening; both decks play on while the other is heard, so
a song comes back where it would be by then.
  cut         20 s of one song, then 20 s of another; songs in any order, half of the pairs from one bucket
  return      20 s of A, 6 s of B, 14 s of A
  alt12 alt8 alt5 alt3
              two songs in turn, 12, 8, 5 or 3 s each, for 60 s
  long        120 s of one song, no change (for jumps in the middle of a song)
  absent      20 s of a song, then 20 s of a song not in the crate
  tonoise     20 s of a song, then 20 s of crowd (or pink) noise alone
  noise       30 s of crowd or pink noise alone
  speed       a cut with each song at its own fader setting (+-2, 6 or 8 %), turntable or key held
  shared      60 s of a song through the passage that a made song shares with it (switch_clips.py versions first;
              clean, room and crowd 10 dB under). Naming the made song is a wrong name.

Conditions: clean; room (a measured room's response); room with crowd noise 10 dB under the music and at equal level;
a small speaker (250 to 3000 Hz) in a room with crowd at equal level. The room and crowd need --rooms DATA: a folder
with rir/**/*.wav and noise/*/*.wav (fetch_data.py --part small makes it); without it only "clean" is made.
Alternations are made clean, in a room and with crowd 10 dB under; the rest in every condition.
"""
import argparse, glob, hashlib, json, os, subprocess, sys
from concurrent.futures import ProcessPoolExecutor
import numpy as np

SR = 16000
CONDITIONS = {
    "clean": {},
    "room": dict(room=True),
    "room+crowd+10": dict(room=True, snr=10),
    "room+crowd0": dict(room=True, snr=0),
    "booth(speaker+room+crowd0)": dict(band=(250, 3000), room=True, snr=0),
}
ALT_CONDITIONS = ["clean", "room", "room+crowd+10"]
KINDS = ["cut", "return", "alt12", "alt8", "alt5", "alt3", "long", "absent", "tonoise", "noise", "speed", "shared"]
AUDIO = (".mp3", ".flac", ".wav", ".aif", ".aiff", ".m4a", ".aac", ".ogg", ".opus", ".wma", ".alac", ".s16")


def role_of(song_id):
    h = int(hashlib.sha1(song_id.encode()).hexdigest()[:8], 16)
    return "absent" if h % 10 == 0 else ("dev" if (h // 10) % 2 == 0 else "eval")


def decode(path, start=0.0, seconds=None, percent=0.0, mode="tempo"):
    """Mono 16 kHz float samples of a file from `start` (seconds of the song) for `seconds` of listening, the deck at
    `percent`: "vinyl" resampled (time and pitch move together), "tempo" time-stretched with the key held (ffmpeg's
    atempo). A .s16 file is raw 16-bit mono at 16 kHz."""
    v = 1 + percent / 100
    if path.endswith(".s16") and percent == 0:
        m = np.memmap(path, dtype="<i2", mode="r")
        a = int(start * SR)
        b = len(m) if seconds is None else a + int(seconds * SR)
        return np.asarray(m[a:b], dtype=np.float32) / 32768
    src = ["-f", "s16le", "-ar", str(SR), "-ac", "1"] if path.endswith(".s16") else []
    filt = []
    if percent:
        filt = [f"asetrate={SR * v:.3f},aresample={SR}"] if mode == "vinyl" else [f"atempo={v:.5f}"]
    cmd = ["ffmpeg", "-v", "error", "-nostdin", "-ss", f"{start:.3f}"] + src + ["-i", path]
    if seconds is not None:
        cmd += ["-t", f"{seconds + 0.5:.3f}"]              # an output option: seconds of listening, and a margin
    if filt:
        cmd += ["-af", ",".join(filt)] if mode == "tempo" else ["-af", f"aresample={SR}," + filt[0]]
    cmd += ["-ac", "1", "-ar", str(SR), "-f", "s16le", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768
    return x if seconds is None else x[:int(seconds * SR)]


def seconds_of(path):
    if path.endswith(".s16"):
        return os.path.getsize(path) / 2 / SR
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


def rms(x):
    return float(np.sqrt(np.mean(np.square(x, dtype=np.float64)) + 1e-12))


def convolve(x, h):
    n = len(x) + len(h) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(h, size), size)[:len(x)].astype(np.float32)


def band(x, lo, hi):
    """A small speaker: fourth-order high-pass at `lo` and low-pass at `hi` (Butterworth magnitudes, no phase)."""
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 8)
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** 8)
    return np.fft.irfft(np.fft.rfft(x) * g, len(x)).astype(np.float32)


def pink(n, rng):
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) / np.sqrt(np.maximum(f, 20))
    y = np.fft.irfft(spec, n)
    return (y / rms(y)).astype(np.float32)


def room(x, rooms, rng):
    files = sorted(f for f in glob.glob(os.path.join(rooms, "rir", "**", "*.wav"), recursive=True) if "noise" not in os.path.basename(f).lower())
    path = files[rng.integers(len(files))]
    # One microphone of the recording, at random (some are arrays of up to 30), as make_queries.py does.
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", path], capture_output=True, text=True)
    ch = int(r.stdout.split()[0])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", path, "-ar", str(SR), "-f", "f32le", "-"], capture_output=True).stdout
    h = np.frombuffer(raw, dtype="<f4").reshape(-1, ch)[:, rng.integers(ch)].copy()
    peak = int(np.argmax(np.abs(h)))
    h = h[max(0, peak - 20):peak + int(1.5 * SR)]
    y = convolve(x, h)
    return y * (rms(x) / rms(y)), os.path.basename(path)


def crowd(n, rooms, rng):
    files = sorted(glob.glob(os.path.join(rooms, "noise", "*", "*.wav")))
    path = files[rng.integers(len(files))]
    total = seconds_of(path)
    start = float(rng.uniform(0, max(0.0, total - n / SR - 1)))
    y = decode(path, start, n / SR)
    return np.pad(y, (0, n - len(y))), os.path.basename(os.path.dirname(path))


def render(spec, rooms):
    """The clip's sound from its plan: its pieces end to end, each brought to one level (a DJ matches levels), joined
    with 5 ms ramps; then the room, the speaker and the noise."""
    rng = np.random.default_rng(spec["seed"])
    pieces = []
    for p in spec["pieces"]:
        n = int(round((p["to"] - p["from"]) * SR))
        if p["song"] in ("crowd", "pink"):
            x = crowd(n, rooms, rng)[0] if p["song"] == "crowd" else pink(n, rng)
        else:
            x = decode(p["path"], p["at"], p["to"] - p["from"], p.get("percent", 0), p.get("mode", "tempo"))
        x = np.pad(x, (0, max(0, n - len(x))))[:n]
        x = x / rms(x) * 0.1
        ramp = min(80, n // 2)
        x[:ramp] *= np.linspace(0, 1, ramp); x[n - ramp:] *= np.linspace(1, 0, ramp)
        pieces.append(x)
    x = np.concatenate(pieces).astype(np.float32)
    c = CONDITIONS[spec["condition"]]
    if "band" in c:
        x = band(x, *c["band"])
    if c.get("room"):
        x, spec["rir"] = room(x, rooms, rng)
    if "snr" in c:
        noise, spec["noise"] = crowd(len(x), rooms, rng)
        x = x + noise * (rms(x) / rms(noise)) * 10 ** (-c["snr"] / 20)
    x = x * (0.7 / (np.max(np.abs(x)) + 1e-9))
    return (x * 32767).astype("<i2")


def make_one(job):
    spec, out, rooms = job
    # Named by what is in it, so a changed plan never meets an old file.
    digest = hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:10]
    path = os.path.join(out, "pcm", spec["clip"] + "-" + digest + ".s16")
    if not os.path.exists(path):
        render(spec, rooms).tofile(path + ".part")
        os.replace(path + ".part", path)
    return spec, path, os.path.getsize(path) // 2


def load_songs(work):
    songs = []
    for line in open(os.path.join(work, "songs.tsv")):
        f = line.rstrip("\n").split("\t")
        if len(f) < 2 or not f[1]:
            continue
        sec = float(f[3]) if len(f) > 3 and f[3] else None
        songs.append(dict(id=f[0], path=f[1], bucket=f[2] if len(f) > 2 and f[2] else "-", sec=sec,
                          role=f[4] if len(f) > 4 and f[4] else role_of(f[0])))
    return songs


def plan(songs, role, n, kinds, conditions, seed, noises=("crowd", "pink"), made=None):
    rng = np.random.default_rng(seed)
    pool = [s for s in songs if s["role"] == role]
    absent = [s for s in songs if s["role"] == "absent"]
    by_bucket = {}
    for s in pool:
        by_bucket.setdefault(s["bucket"], []).append(s)
    specs = []

    def pick(need, avoid=(), same_bucket=None):
        src = by_bucket.get(same_bucket, pool) if same_bucket else pool
        for _ in range(100):
            s = src[rng.integers(len(src))]
            if s["id"] not in avoid and (s["sec"] or 0) >= need + 4:
                return s
        return None

    def piece(s, t0, t1, at, percent=0, mode="tempo"):
        return dict(song=s["id"], path=s["path"], **{"from": t0, "to": t1}, at=at, percent=percent, mode=mode)

    def two(need_a, need_b):
        a = pick(need_a)
        b = pick(need_b, {a["id"]}, a["bucket"] if rng.random() < 0.5 else None) if a else None
        return a, b

    for kind in kinds:
        for cond in (ALT_CONDITIONS if kind.startswith("alt") else conditions):
            if kind.startswith("alt") and cond not in conditions:
                continue
            for k in range(n):
                pieces = None
                if kind in ("cut", "speed"):
                    a, b = two(25, 25)
                    if not b:
                        continue
                    pa = pb = 0.0; ma = mb = "tempo"
                    if kind == "speed":
                        pa, pb = (float(rng.choice([-8, -6, -2, 2, 6, 8])) for _ in range(2))
                        ma, mb = (str(rng.choice(["vinyl", "tempo"])) for _ in range(2))
                    sa = float(rng.uniform(5, a["sec"] - 25 * (1 + pa / 100) - 3)); sb = float(rng.uniform(5, b["sec"] - 25 * (1 + pb / 100) - 3))
                    pieces = [piece(a, 0, 20, sa, pa, ma), piece(b, 20, 40, sb, pb, mb)]
                elif kind == "return":
                    a, b = two(45, 10)
                    if not b:
                        continue
                    sa = float(rng.uniform(5, a["sec"] - 45)); sb = float(rng.uniform(5, b["sec"] - 30))
                    pieces = [piece(a, 0, 20, sa), piece(b, 20, 26, sb), piece(a, 26, 40, sa + 26)]
                elif kind.startswith("alt"):
                    seg = float(kind[3:])
                    a, b = two(65, 65)
                    if not b:
                        continue
                    sa = float(rng.uniform(5, a["sec"] - 65)); sb = float(rng.uniform(5, b["sec"] - 65))
                    pieces, t, turn = [], 0.0, 0
                    while t < 60 - 1e-9:
                        s, s0 = (a, sa) if turn % 2 == 0 else (b, sb)
                        pieces.append(piece(s, t, min(60.0, t + seg), s0 + t)); t += seg; turn += 1
                elif kind == "long":
                    a = pick(125)
                    if not a:
                        continue
                    pieces = [piece(a, 0, 120, float(rng.uniform(3, a["sec"] - 123)))]
                elif kind == "absent":
                    if not absent:
                        continue
                    a = pick(25)
                    x = absent[rng.integers(len(absent))]
                    if not a or (x["sec"] or 0) < 30:
                        continue
                    pieces = [piece(a, 0, 20, float(rng.uniform(5, a["sec"] - 25))), dict(piece(x, 20, 40, float(rng.uniform(5, x["sec"] - 25))), absent=True)]
                elif kind == "tonoise":
                    a = pick(25)
                    if not a:
                        continue
                    pieces = [piece(a, 0, 20, float(rng.uniform(5, a["sec"] - 25))), dict(song=str(rng.choice(noises)), **{"from": 20.0, "to": 40.0})]
                elif kind == "shared":
                    # The source song played through the passage a made song shares with it: 20 s before it, on to 60 s.
                    if not made or not os.path.exists(made) or cond not in ALT_CONDITIONS:
                        continue
                    rows = [l.rstrip("\n").split("\t") for l in open(made)]
                    mid, _, src_id, vkind, at, length, _ = rows[k % len(rows)] if k < len(rows) else rows[0]
                    if k >= len(rows):
                        continue
                    src = next((s for s in songs if s["id"] == src_id), None)
                    if not src:
                        continue
                    start = max(2.0, float(at) - 20)
                    pieces = [dict(piece(src, 0, 60, start), made=mid, made_kind=vkind)]
                    pieces[0]["to"] = min(60.0, src["sec"] - start - 1)
                elif kind == "noise":
                    if cond != "clean":
                        continue          # noise alone has no room or crowd to add
                    pieces = [dict(song=str(rng.choice(noises)), **{"from": 0.0, "to": 30.0})]
                if pieces:
                    clip = f"{role}-{kind}-{cond}-{k:04d}".replace("+", "p").replace("(", "").replace(")", "")
                    specs.append(dict(clip=clip, kind=kind, condition=cond, role=role, seed=int(rng.integers(1 << 31)), pieces=pieces))
    return specs


def make_versions(work, role, n, seed, jobs):
    """Songs made to share a passage with a song of the crate, for the "shared" clips: from each source song of the
    half, one of three kinds, written to WORK/made/<id>.wav (16 kHz mono) and listed in WORK/made.tsv (made id, path,
    source id, kind, the source's shared stretch: from, seconds). They are added to the crate (fingerprint them with
    the rest); the clips play the source through the shared stretch, so naming the made song is naming another song.
      sample   another song of the half with 4 to 8 s of the source cut into it
      mashup   another song with the source laid over it at equal level for 8 to 16 s
      edit     the source with its middle cut and reordered: its stretches in another order, each 20 to 40 s"""
    rng = np.random.default_rng(seed + (0 if role == "dev" else 1000))
    songs = [s for s in load_songs(work) if s["role"] == role and (s["sec"] or 0) >= 150]
    os.makedirs(os.path.join(work, "made"), exist_ok=True)
    jobs_ = []
    for k in range(n):
        src, host = (songs[i] for i in rng.choice(len(songs), 2, replace=False))
        kind = ("sample", "mashup", "edit")[k % 3]
        mid = "v" + hashlib.sha1(f"{role}-{seed}-{k}".encode()).hexdigest()[:10]
        if kind == "sample":
            length = float(rng.uniform(4, 8)); at = float(rng.uniform(30, src["sec"] - 40)); put = float(rng.uniform(40, host["sec"] - 50))
        elif kind == "mashup":
            length = float(rng.uniform(8, 16)); at = float(rng.uniform(30, src["sec"] - 40)); put = float(rng.uniform(40, host["sec"] - 50))
        else:
            length = float(rng.uniform(20, 40)); at = float(rng.uniform(40, src["sec"] - 2 * length - 20)); put = 0.0
        jobs_.append(dict(id=mid, kind=kind, source=src["id"], source_path=src["path"], host=host["id"], host_path=host["path"],
                          at=at, length=length, put=put, path=os.path.join(work, "made", mid + ".wav")))
    with ProcessPoolExecutor(jobs) as ex:
        list(ex.map(write_version, jobs_))
    with open(os.path.join(work, f"made-{role}.tsv"), "w") as f:
        for j in jobs_:
            f.write(f"{j['id']}\t{j['path']}\t{j['source']}\t{j['kind']}\t{j['at']:.2f}\t{j['length']:.2f}\t{role}\n")
    print(f"{len(jobs_)} made songs for {role}", file=sys.stderr)


def write_version(j):
    if os.path.exists(j["path"]):
        return
    src = decode(j["source_path"])
    a, b = int(j["at"] * SR), int((j["at"] + j["length"]) * SR)
    if j["kind"] == "edit":
        # The stretches after `at`, each `length` long, played as 0, 2, 1, 3: the shared passages are the stretches.
        L = b - a
        parts = [src[:a], src[a + 0 * L:a + 1 * L], src[a + 2 * L:a + 3 * L], src[a + 1 * L:a + 2 * L], src[a + 3 * L:]]
        y = np.concatenate(parts)
    else:
        host = decode(j["host_path"])
        put = int(j["put"] * SR)
        piece = src[a:b] / rms(src[a:b]) * rms(host)
        if j["kind"] == "sample":
            y = np.concatenate([host[:put], piece, host[put:]])
        else:
            y = host.copy()
            y[put:put + len(piece)] = y[put:put + len(piece)] + piece[:len(y) - put]
    y = y * (0.7 / (np.max(np.abs(y)) + 1e-9))
    pcm = (y * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-", j["path"] + ".tmp.wav"], input=pcm, check=True)
    os.replace(j["path"] + ".tmp.wav", j["path"])


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("songs"); a.add_argument("music"); a.add_argument("work")
    m = sub.add_parser("make"); m.add_argument("work")
    m.add_argument("--rooms"); m.add_argument("--n", type=int, default=40); m.add_argument("--seed", type=int, default=7)
    m.add_argument("--role", default="eval", choices=["dev", "eval"]); m.add_argument("--jobs", type=int, default=os.cpu_count())
    m.add_argument("--kinds", nargs="*", default=KINDS); m.add_argument("--conditions", nargs="*")
    m.add_argument("--n-long", type=int, help="clips a condition for long play (default --n)")
    m.add_argument("--n-kind", nargs="*", default=[], help="clips a condition for some kinds, e.g. cut=40 alt5=10")
    v = sub.add_parser("versions"); v.add_argument("work"); v.add_argument("--role", default="eval", choices=["dev", "eval"])
    v.add_argument("--n", type=int, default=60); v.add_argument("--seed", type=int, default=11); v.add_argument("--jobs", type=int, default=os.cpu_count())
    a = ap.parse_args()
    if a.cmd == "songs":
        os.makedirs(a.work, exist_ok=True)
        with open(os.path.join(a.work, "songs.tsv"), "w") as f:
            for root, _, names in os.walk(a.music):
                for name in sorted(names):
                    if name.lower().endswith(AUDIO):
                        path = os.path.join(root, name)
                        sid = "m" + hashlib.sha1(os.path.relpath(path, a.music).encode()).hexdigest()[:12]   # as make_queries.py names them
                        f.write(f"{sid}\t{path}\t-\t{seconds_of(path):.2f}\t{role_of(sid)}\n")
        return
    if a.cmd == "versions":
        make_versions(a.work, a.role, a.n, a.seed, a.jobs)
        return
    songs = load_songs(a.work)
    for s in songs:
        if s["sec"] is None:
            s["sec"] = seconds_of(s["path"])
    conditions = a.conditions or (list(CONDITIONS) if a.rooms else ["clean"])
    out = os.path.join(a.work, "switch", a.role)
    os.makedirs(os.path.join(out, "pcm"), exist_ok=True)
    noises = ("crowd", "pink") if a.rooms else ("pink",)       # crowd recordings come with the rooms
    counts = dict(kv.split("=") for kv in a.n_kind)
    if a.n_long:
        counts.setdefault("long", a.n_long)
    specs = []
    for i, kind in enumerate(a.kinds):
        specs += plan(songs, a.role, int(counts.get(kind, a.n)), [kind], conditions, a.seed + i, noises,
                      made=os.path.join(a.work, f"made-{a.role}.tsv"))
    with ProcessPoolExecutor(a.jobs) as ex:
        done = list(ex.map(make_one, [(s, out, a.rooms) for s in specs], chunksize=4))
    with open(os.path.join(out, "clips.tsv"), "w") as f, open(os.path.join(out, "truth.jsonl"), "w") as t:
        for spec, path, count in done:
            f.write(f"{spec['clip']}\t{os.path.abspath(path)}\t0\t{count}\t{SR}\n")
            t.write(json.dumps({k: v for k, v in spec.items() if k != "seed"}) + "\n")
    print(f"{len(done)} clips in {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
