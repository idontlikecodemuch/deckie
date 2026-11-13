#!/usr/bin/env python3
"""Makes the benchmark's queries from the fetched songs. Nothing it writes belongs in the repository.

  make_queries.py prepare DATA WORK        decode every song to WORK/pcm (mono, 22.05 kHz), write WORK/songs.tsv
  make_queries.py queries DATA WORK [--n 100] [--dev-n 40] [--jobs 4] [--only grid|booth|absent]

Each query is a 12 s clip, and the manifest asks for its first 3, 5, 8 and 12 seconds separately, so "how long until
the song is named" is read off one listening start.

Songs are split by a hash of their id: one in ten is "absent" (left out of the index: its queries have no right
answer), and the rest are half "dev" (anything chosen by measurement is chosen on these) and half "eval" (reported).

Speed: the deck plays at v = 1 + percent / 100.
  vinyl   resampled (scipy resample_poly): time and frequency move together.
  tempo   time-stretched with the key held, by Rubber Band (through pedalboard); the cell "tempo/atempo" uses ffmpeg's
          atempo filter instead, a different kind of stretcher (overlap-add in time), as a cross-check.
Booth conditions (applied after the speed change, in this order): a second song mixed in; a small-speaker band;
a room (convolution with a measured impulse response); noise (crowd recordings or pink noise) at a level relative
to the music as it arrives.
"""
import argparse, glob, hashlib, json, math, os, subprocess, sys
from fractions import Fraction
from multiprocessing import Pool
import numpy as np
from scipy import signal
import soundfile as sf

SR = 22050       # working rate
OUT_SR = 16000   # rate of the query files
CLIP = 12.0
LENGTHS = [3, 5, 8, 12]


def role_of(song_id):
    h = int(hashlib.sha1(song_id.encode()).hexdigest()[:8], 16)
    return "absent" if h % 10 == 0 else ("dev" if (h // 10) % 2 == 0 else "eval")


def decode(job):
    src, dst = job
    if not os.path.exists(dst):
        r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", src, "-ac", "1", "-ar", str(SR), "-f", "s16le", dst + ".part"])
        if r.returncode != 0 or not os.path.exists(dst + ".part"):
            return None
        os.replace(dst + ".part", dst)
    return os.path.getsize(dst) / 2 / SR


def prepare(data, work, jobs):
    os.makedirs(os.path.join(work, "pcm"), exist_ok=True)
    songs = []
    for bucket, pattern in [("dance", "songs/dance/*.mp3"), ("other", "songs/other/*.mp3"), ("gsplus", "gsplus/**/*.mp3")]:
        listing = os.path.join(data, f"songs_{bucket}.json")
        # Only the songs in the fetch's own list (each with its licence on record) are used.
        listed = {g["id"] for g in json.load(open(listing))} if os.path.exists(listing) else None
        for path in sorted(glob.glob(os.path.join(data, pattern), recursive=True)):
            base = os.path.splitext(os.path.basename(path))[0]
            if listed is not None and base not in listed:
                continue
            sid = base if bucket != "gsplus" else "g" + base.split(".")[0]
            songs.append((sid, path, bucket))
    with Pool(jobs) as pool:
        secs = pool.map(decode, [(p, os.path.join(work, "pcm", s + ".s16")) for s, p, _ in songs])
    with open(os.path.join(work, "songs.tsv"), "w") as f:
        for (sid, path, bucket), sec in zip(songs, secs):
            if sec and sec >= 60:
                f.write(f"{sid}\t{path}\t{bucket}\t{sec:.2f}\t{role_of(sid)}\n")
    print("songs:", sum(1 for s in secs if s and s >= 60), "of", len(songs))


# ---- signal pieces ----

def load_songs(work):
    out = []
    for line in open(os.path.join(work, "songs.tsv")):
        sid, path, bucket, sec, role = line.rstrip("\n").split("\t")
        out.append(dict(id=sid, bucket=bucket, sec=float(sec), role=role))
    return out


def pcm(work, sid, start, count):
    m = np.memmap(os.path.join(work, "pcm", sid + ".s16"), dtype="<i2", mode="r")
    a = max(0, int(start)); b = min(len(m), a + int(count))
    x = np.asarray(m[a:b], dtype=np.float32) / 32768
    return np.pad(x, (0, int(count) - len(x)))


def at_speed(work, sid, s0, percent, mode, seconds):
    """`seconds` of the song from s0 (song seconds), played at the given fader percent."""
    v = 1 + percent / 100
    if percent == 0:
        return pcm(work, sid, s0 * SR, seconds * SR)
    src = pcm(work, sid, s0 * SR, (seconds * v + 1.0) * SR)
    if mode == "vinyl":
        fr = Fraction(100, 100 + percent)
        y = signal.resample_poly(src, fr.numerator, fr.denominator)
    elif mode == "tempo":
        import pedalboard
        y = pedalboard.time_stretch(src[None, :], SR, stretch_factor=v)[0]
    elif mode == "atempo":
        r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                            "-filter:a", f"atempo={v:.4f}", "-f", "f32le", "-"], input=src.astype("<f4").tobytes(), capture_output=True)
        y = np.frombuffer(r.stdout, dtype="<f4")
    else:
        raise ValueError(mode)
    n = int(seconds * SR)
    y = np.asarray(y[:n], dtype=np.float32)
    return np.pad(y, (0, n - len(y)))


def rms(x):
    return float(np.sqrt(np.mean(x * x) + 1e-20))


def pink(n, rng):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(spec)); f[0] = 1
    return np.fft.irfft(spec / np.sqrt(f), n).astype(np.float32)


_cache = {}


def rir_list(data):
    if "rirs" not in _cache:
        files = sorted(glob.glob(os.path.join(data, "rir", "**", "*.wav"), recursive=True))
        _cache["rirs"] = [f for f in files if "noise" not in os.path.basename(f).lower()]
    return _cache["rirs"]


def room(x, data, rng):
    path = rir_list(data)[rng.integers(len(rir_list(data)))]
    h, sr = sf.read(path, dtype="float32", always_2d=True)
    h = h[:, rng.integers(h.shape[1])]
    if sr != SR:
        fr = Fraction(SR, sr)
        h = signal.resample_poly(h, fr.numerator, fr.denominator)
    peak = int(np.argmax(np.abs(h)))
    h = h[max(0, peak - 20):peak + int(1.5 * SR)]   # from the direct sound, up to 1.5 s of tail
    y = signal.fftconvolve(x, h)[:len(x)]
    return (y * (rms(x) / rms(y))).astype(np.float32), os.path.basename(path)


def crowd(n, data, rng):
    if "noise" not in _cache:
        _cache["noise"] = sorted(glob.glob(os.path.join(data, "noise", "*", "*.wav")))
    path = _cache["noise"][rng.integers(len(_cache["noise"]))]
    info = sf.info(path)
    need = int(n * info.samplerate / SR) + 1
    start = int(rng.integers(0, info.frames - need))
    y, sr = sf.read(path, start=start, frames=need, dtype="float32")
    fr = Fraction(SR, sr)
    y = signal.resample_poly(y, fr.numerator, fr.denominator)[:n]
    return np.pad(y, (0, n - len(y))).astype(np.float32)


def band(x, lo, hi):
    if lo:
        x = signal.sosfilt(signal.butter(4, lo, "highpass", fs=SR, output="sos"), x)
    if hi:
        x = signal.sosfilt(signal.butter(4, hi, "lowpass", fs=SR, output="sos"), x)
    return x.astype(np.float32)


CONDITIONS = {
    # name: dict(room, speaker band, noise kind, snr dB, blend dB (level of the song over the second song))
    "clean": {},
    "room": dict(room=True),
    "room+crowd+10": dict(room=True, noise="crowd", snr=10),
    "room+crowd+5": dict(room=True, noise="crowd", snr=5),
    "room+crowd0": dict(room=True, noise="crowd", snr=0),
    "room+crowd-5": dict(room=True, noise="crowd", snr=-5),
    "room+pink+10": dict(room=True, noise="pink", snr=10),
    "room+pink0": dict(room=True, noise="pink", snr=0),
    "room+pink-5": dict(room=True, noise="pink", snr=-5),
    "speaker250-3000": dict(band=(250, 3000)),
    "lowpass2000": dict(band=(0, 2000)),
    "booth(speaker+room+crowd0)": dict(band=(250, 3000), room=True, noise="crowd", snr=0),
    "blend+6": dict(blend=6),
    "blend0": dict(blend=0),
    "blend-6": dict(blend=-6),
    "room+blend0": dict(room=True, blend=0),
}
BOOTH_SPEEDS = [("vinyl", 0), ("vinyl", 12), ("vinyl", -6), ("tempo", 12), ("tempo", -6)]   # letter H's five


def make_clip(args):
    data, work, spec = args
    rng = np.random.default_rng(spec["seed"])
    n = int(CLIP * SR)
    c = CONDITIONS[spec["condition"]]
    x = at_speed(work, spec["song"], spec["s0"], spec["percent"], spec["mode"], CLIP)
    if "blend" in c:
        other = at_speed(work, spec["second"], spec["second_s0"], spec["second_percent"], "tempo", CLIP)
        x = x + other * (rms(x) / rms(other)) * 10 ** (-c["blend"] / 20)
    if "band" in c:
        x = band(x, *c["band"])
    if c.get("room"):
        x, spec["rir"] = room(x, data, rng)
    if "noise" in c:
        noise = crowd(n, data, rng) if c["noise"] == "crowd" else pink(n, rng)
        x = x + noise * (rms(x) / rms(noise)) * 10 ** (-c["snr"] / 20)
    if spec.get("noise_only"):
        x = crowd(n, data, rng) if spec["noise_only"] == "crowd" else pink(n, rng)
    fr = Fraction(OUT_SR, SR)
    y = signal.resample_poly(x, fr.numerator, fr.denominator)
    y = y * (0.7 / (np.max(np.abs(y)) + 1e-9))
    return (y * 32767).astype("<i2")


def plan(songs, n_eval, n_dev, only):
    rng = np.random.default_rng(20261113)
    by_role = {r: [s for s in songs if s["role"] == r] for r in ("dev", "eval", "absent")}
    present = by_role["dev"] + by_role["eval"]
    specs = []

    def add(cell, role, condition, mode, percent, count, **extra):
        pool = by_role[role]
        for _ in range(count):
            s = pool[rng.integers(len(pool))]
            v = 1 + percent / 100
            span = CLIP * v + 1.5
            s0 = float(rng.uniform(2, max(2.1, s["sec"] - span - 2)))
            spec = dict(cell=cell, role=role, condition=condition, mode=mode, percent=percent, song=s["id"], bucket=s["bucket"],
                        s0=round(s0, 3), seed=int(rng.integers(1 << 31)), **extra)
            if "blend" in CONDITIONS[condition]:
                o = present[rng.integers(len(present))]
                while o["id"] == s["id"]:
                    o = present[rng.integers(len(present))]
                sp = int(rng.integers(-6, 7))
                spec.update(second=o["id"], second_percent=sp,
                            second_s0=round(float(rng.uniform(2, max(2.1, o["sec"] - CLIP * (1 + sp / 100) - 3.5))), 3))
            specs.append(spec)

    for role, count in (("eval", n_eval), ("dev", n_dev)):
        if only in (None, "grid"):
            for p in range(-16, 17, 2):
                add("grid", role, "clean", "vinyl", p, count)
                if p != 0:
                    add("grid", role, "clean", "tempo", p, count)
            for p in (-12, -6, 6, 12):
                add("grid", role, "clean", "atempo", p, count)
        if only in (None, "booth"):
            for name in CONDITIONS:
                if name == "clean":
                    continue
                for mode, p in BOOTH_SPEEDS:
                    add("booth", role, name, mode, p, count)
    if only in (None, "absent"):
        # Queries with no right answer: songs left out of the index (half the absent songs count as dev, half as
        # eval, by position in the list), and noise alone.
        ab = by_role["absent"]
        for i, role in enumerate(("dev", "eval")):
            by_role["absent"] = ab[i::2]
            for condition in ("clean", "room+crowd0"):
                for mode, p in BOOTH_SPEEDS:
                    add("absent", "absent", condition, mode, p, n_eval, split=role)
        by_role["absent"] = ab
        for i in range(2 * n_eval):
            specs.append(dict(cell="absent", role="absent", split="dev" if i % 2 else "eval", condition="clean", mode="vinyl", percent=0,
                              song=ab[0]["id"], bucket="noise", s0=2.0, seed=int(rng.integers(1 << 31)),
                              noise_only="crowd" if i % 4 < 2 else "pink"))
    return specs


def write_shard(args):
    data, work, k, specs = args
    path = os.path.join(work, "queries", f"shard{k:04d}.s16")
    rows = []
    with open(path + ".part", "wb") as f:
        at = 0
        for spec in specs:
            y = make_clip((data, work, spec))
            f.write(y.tobytes())
            rows.append((spec, at, len(y)))
            at += len(y)
    os.replace(path + ".part", path)
    return path, rows


def queries(data, work, n_eval, n_dev, jobs, only):
    os.makedirs(os.path.join(work, "queries"), exist_ok=True)
    specs = plan(load_songs(work), n_eval, n_dev, only)
    shards = [specs[i:i + 200] for i in range(0, len(specs), 200)]
    with Pool(jobs) as pool:
        done = pool.map(write_shard, [(data, work, k, s) for k, s in enumerate(shards)], chunksize=1)
    qid = 0
    with open(os.path.join(work, "queries.tsv"), "w") as q, open(os.path.join(work, "truth.jsonl"), "w") as t:
        for path, rows in done:
            for spec, at, n in rows:
                for length in LENGTHS:
                    name = f"q{qid:06d}_{length}"
                    q.write(f"{name}\t{path}\t{at}\t{min(n, length * OUT_SR)}\t{OUT_SR}\n")
                spec = dict(spec, qid=f"q{qid:06d}")
                t.write(json.dumps(spec) + "\n")
                qid += 1
    print("clips:", qid, "queries:", qid * len(LENGTHS))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["prepare", "queries"])
    ap.add_argument("data"); ap.add_argument("work")
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--dev-n", type=int, default=40)
    ap.add_argument("--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--only", choices=["grid", "booth", "absent"])
    a = ap.parse_args()
    if a.command == "prepare":
        prepare(a.data, a.work, a.jobs)
    else:
        queries(a.data, a.work, a.n, a.dev_n, a.jobs, a.only)
