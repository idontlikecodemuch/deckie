#!/usr/bin/env python3
"""Research S: the booth's first night, a recorded set read back against its own log and against the audio.

The booth records what it hears while it listens (deck-app SetRecorder.swift): one ADTS AAC file per listening
session plus a log of what it recognised. The log holds one entry per song change (the moment the booth switched to a
new song, after its ten-second hold), with the last pitch reading and the best confidence of that song; it does not
hold the last moment a song was heard, nor the moment the booth gave up after two minutes of silence. So the log
alone says what the booth showed, not what was playing. This script reads both and measures:

  1. the inventory: every recording, its start, its length from the audio (AAC packets x 1024 samples), entries;
  2. the set as the booth logged it: songs in order, span from one switch to the next, pitch, kind, confidence;
  3. the set as the audio says: an independent check that matches the recording against the crate's own files.
     Per beat of the recording (Beat This beats) a 36-bin chroma (pitch classes in thirds of a semitone, octaves
     folded) is averaged; a window of 32 beats is slid over every crate track's beat-synchronous chroma, with the
     chroma rolled by -5 to +5 bins so a vinyl pitch of up to about 8 percent still lines up. Being beat-synchronous
     it is tempo-free. Sustained or loop-like crate passages that resemble everything are discounted by a hub
     correction (CSLS, Conneau et al. 2018, k = 10, against unlabelled background windows from the same
     recordings). A window counts as identified when the best 40-beat path into it and the one out of it (two
     windows 8 beats apart continuing on one track) name the same track, and the speed is inside a deck's fader
     range with a chroma roll that fits it (vinyl: the key moved with the speed; master tempo: it did not). No
     labels, no score threshold, nothing fitted to the crate. An identified window also gives the playing speed
     against the original, the chroma roll and where in the original the song was;
  4. the booth's pitch reading against the audio: catalogue tempo x (1 + pitch/100) against the tempo Beat This
     measures in the recording (beat-time regression over the window, octave-folded), and against the speed from
     the alignment;
  5. the transitions: for each song change, the rank of the next song among the booth's picks for the one before
     (deck_data.json pairs, filtered as the booth filters them), the chance it was on screen (the booth's own pick
     sampler, Mixing.swift rollSets, replayed 2,000 times), the Camelot relation, the tempo change, and where in A
     the DJ left (before, inside or after its mix-out window).

Data rule: the recordings are the DJ's own audio of a private party. They are read where they are and never copied
into the repository; decoded audio and per-beat features go to --cache (a scratch folder outside the repository).
The committed outputs are tables of times, ids, tempos and ranks only; nothing that reproduces the music.

Machine rule: run at nice 19; at most two worker processes (--jobs); recordings are decoded once by ffmpeg to mono
32-bit float at 22,050 Hz in the cache (16-bit would round away the booth's quiet input, about -75 dBFS) and read
through a memory map in five-minute chunks, never held whole in memory.

usage (from mixer/):
  nice -n 19 .venv/bin/python -I set_analysis.py <Sets folder> --deck ../deck-app/Deck/Resources/deck_data.json \\
      --cache <scratch folder> [--jobs 2] [--prefix set_oct24]
  (stages are cached; --redo <stage> recomputes one: decode, beats, chroma, crate, hub, match)
"""
import argparse, csv, datetime as D, glob, json, math, os, re, subprocess, sys, time, warnings
from collections import Counter, defaultdict
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

SR = 22050
HOP = 512
CHUNK_S = 300.0
PAD_S = 10.0
STUB_S = 60.0            # a recording shorter than this is a restart stub
W = 32                   # beats per matching window
STEP = 8                 # beats between window starts
SHIFTS = range(-5, 6)    # chroma roll in thirds of a semitone
NAME_RE = re.compile(r"^Deck set (\d{4}-\d\d-\d\d \d\d-\d\d-\d\d)\.aac$")


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ----------------------------------------------------------------------------- inventory
def aac_seconds(path):
    if os.path.getsize(path) == 0:
        return 0.0
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-count_packets", "-show_entries",
                        "stream=nb_read_packets,sample_rate", "-of", "json", path], capture_output=True, text=True)
    st = (json.loads(r.stdout or "{}").get("streams") or [{}])[0]
    n, sr = int(st.get("nb_read_packets") or 0), int(st.get("sample_rate") or 0)
    return n * 1024 / sr if sr else 0.0


def iso(s):
    return D.datetime.fromisoformat(s.replace("Z", "+00:00"))


def inventory(sets_dir):
    recs = []
    for f in sorted(os.listdir(sets_dir)):
        m = NAME_RE.match(f)
        if not m:
            continue
        stamp = m.group(1)
        lp = os.path.join(sets_dir, f"Deck set {stamp} log.json")
        lg = json.load(open(lp)) if os.path.exists(lp) else {"started": None, "entries": []}
        local = D.datetime.strptime(stamp, "%Y-%m-%d %H-%M-%S")
        started = iso(lg["started"]) if lg.get("started") else None
        tz = (local - started.replace(tzinfo=None)) if started else D.timedelta(0)
        secs = aac_seconds(os.path.join(sets_dir, f))
        recs.append(dict(stamp=stamp, path=os.path.join(sets_dir, f), local=local, tz=tz, secs=secs,
                         entries=lg.get("entries", []), stub=secs < STUB_S))
    return recs


# ----------------------------------------------------------------------------- audio cache
def pcm_path(cache, stamp):
    return os.path.join(cache, "pcm", stamp.replace(" ", "_") + ".f32")


def decode(rec, cache, redo=False):
    out = pcm_path(cache, rec["stamp"])
    if os.path.exists(out) and not redo:
        return out
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", rec["path"], "-ac", "1", "-ar", str(SR), "-f", "f32le",
                    out + ".part"], check=True)
    os.replace(out + ".part", out)
    return out


def pcm(path):
    return np.memmap(path, dtype=np.float32, mode="r")


def chunks(n, sr=SR):
    """(core start, core end, read start, read end) in samples: five-minute cores with ten seconds of context."""
    c, p = int(CHUNK_S * sr), int(PAD_S * sr)
    for s in range(0, n, c):
        e = min(n, s + c)
        yield s, e, max(0, s - p), min(n, e + p)


_BT = None


def beat_this():
    global _BT
    if _BT is None:
        import torch
        torch.set_num_threads(2)
        from beat_this.inference import Audio2Beats
        _BT = Audio2Beats(checkpoint_path="final0", device="cpu", dbn=False)
    return _BT


def beats_of(path, cache, stamp, redo=False):
    out = os.path.join(cache, "beats", stamp.replace(" ", "_") + ".npy")
    if os.path.exists(out) and not redo:
        return np.load(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    y = pcm(path); bt = beat_this(); allb = []
    for s, e, rs, re_ in chunks(len(y)):
        seg = np.asarray(y[rs:re_], dtype=np.float32)
        if len(seg) < SR * 5:
            continue
        # the booth records far below full scale (about -75 dBFS RMS on the first recording); Beat This reads a
        # log spectrogram that is not level-free, so each chunk is brought to -20 dB RMS first
        rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)))
        if rms > 0: seg = seg * (0.1 / rms)
        b, _ = bt(seg, SR)
        b = np.asarray(b) + rs / SR
        allb.append(b[(b >= s / SR) & (b < e / SR)])
    b = np.concatenate(allb) if allb else np.zeros(0)
    np.save(out, b)
    return b


def chroma_frames(y_float):
    import librosa
    return librosa.feature.chroma_cqt(y=y_float, sr=SR, hop_length=HOP, n_chroma=36, bins_per_octave=36,
                                      fmin=librosa.note_to_hz("C2"), n_octaves=6).T.astype(np.float32)


def beat_sync(frames, beats, offset_s=0.0):
    """Mean chroma between consecutive beats, each beat vector centred and unit length (a correlation)."""
    if len(beats) < 2:
        return np.zeros((0, 36), np.float32)
    fi = np.clip(np.round((np.asarray(beats) - offset_s) * SR / HOP).astype(int), 0, len(frames))
    cs = np.vstack([np.zeros((1, 36), np.float32), np.cumsum(frames, axis=0)])
    n = np.maximum(1, fi[1:] - fi[:-1])[:, None]
    v = (cs[fi[1:]] - cs[fi[:-1]]) / n
    v = v - v.mean(axis=1, keepdims=True)
    v /= np.linalg.norm(v, axis=1, keepdims=True) + 1e-9
    return v.astype(np.float32)


def rec_chroma(path, beats, cache, stamp, redo=False):
    out = os.path.join(cache, "chroma", stamp.replace(" ", "_") + ".npy")
    if os.path.exists(out) and not redo:
        return np.load(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    y = pcm(path); parts = []
    for s, e, rs, re_ in chunks(len(y)):
        seg = np.asarray(y[rs:re_], dtype=np.float32)
        F = chroma_frames(seg)
        a, b = (s - rs) // HOP, (s - rs) // HOP + int(np.ceil((e - s) / HOP))
        parts.append(F[a:b])
    F = np.vstack(parts)
    V = beat_sync(F, beats)
    np.save(out, V)
    return V


def crate_one(item):
    tid, audio, beats, out = item
    try:
        os.nice(19)
    except Exception:
        pass
    try:
        r = subprocess.run(["ffmpeg", "-v", "error", "-i", audio, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                           capture_output=True, check=True)
        y = np.frombuffer(r.stdout, dtype=np.float32)
        V = beat_sync(chroma_frames(y), beats)
        np.savez(out, v=V.astype(np.float16), beats=np.asarray(beats, np.float32))
        return tid, None
    except Exception as e:
        return tid, f"{type(e).__name__}: {e}"


def crate_features(tracks, feat_dir, cache, jobs, redo=False):
    d = os.path.join(cache, "crate"); os.makedirs(d, exist_ok=True)
    items = []
    for t in tracks:
        out = os.path.join(d, t["id"] + ".npz")
        if os.path.exists(out) and not redo:
            continue
        fp = os.path.join(feat_dir, t["id"] + ".json")
        if not os.path.exists(fp):
            continue
        f = json.load(open(fp))
        b = f.get("detected_beats_s") or f.get("beats_s") or []
        if f.get("path") and os.path.exists(f["path"]) and len(b) > W:
            items.append((t["id"], f["path"], b, out))
    if items:
        log(f"crate chroma: {len(items)} tracks, {jobs} worker(s)")
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            for i, (tid, err) in enumerate(pool.imap_unordered(crate_one, items), 1):
                if err: log("  crate fail", tid, err)
                if i % 50 == 0: log(f"  {i}/{len(items)}")
    db = {}
    for t in tracks:
        p = os.path.join(d, t["id"] + ".npz")
        if os.path.exists(p):
            z = np.load(p); db[t["id"]] = (z["v"].astype(np.float32), z["beats"])
    return db


# ----------------------------------------------------------------------------- matching
class Matcher:
    def __init__(self, db, song_of):
        self.ids = list(db)
        self.V = np.vstack([db[i][0] for i in self.ids])
        self.track = np.concatenate([np.full(len(db[i][0]), k) for k, i in enumerate(self.ids)])
        self.pos = np.concatenate([np.arange(len(db[i][0])) for i in self.ids])
        lens = np.array([len(db[i][0]) for i in self.ids])
        self.valid = self.pos <= lens[self.track] - W
        # a pair of windows STEP beats apart continues on the same track
        self.cont = np.zeros(len(self.pos), bool)
        self.cont[STEP:] = (self.track[STEP:] == self.track[:-STEP]) & self.valid[STEP:] & self.valid[:-STEP]
        self.starts = np.concatenate([[0], np.cumsum(lens)[:-1]])
        self.beats = [db[i][1] for i in self.ids]
        self.song = np.array([song_of[i] for i in self.ids])
        self.VT = np.ascontiguousarray(self.V.T)
        self.hub = np.zeros(len(self.pos), np.float32)

    def raw(self, Q):
        """Score of the window at every crate position (best roll) and that roll."""
        N = self.V.shape[0]
        best = np.full(N, -9.0, np.float32); bshift = np.zeros(N, np.int8)
        for s in SHIFTS:
            S = np.roll(Q, s, axis=1) @ self.VT
            acc = np.zeros(N, np.float32)
            for i in range(W):
                acc[:N - i] += S[i, i:]
            acc /= W
            acc[~self.valid] = -9.0
            m = acc > best; best[m] = acc[m]; bshift[m] = s
        return best, bshift

    def hubs(self, windows, k=10):
        """Hub correction (CSLS, Conneau et al. 2018, k = 10): a crate position that sits close to many windows (a
        sustained chord, a loop that resembles everything) has the mean of its k best scores against a background of
        windows taken from every recording subtracted from its score."""
        top = np.full((k, len(self.pos)), -9.0, np.float32)
        for Q in windows:
            b, _ = self.raw(Q)
            top = np.partition(np.vstack([top, b[None]]), 1, axis=0)[1:]
        self.hub = np.where(top > -9, top, 0).mean(axis=0).astype(np.float32)


def match_recording(M, V, beats, cache, stamp, redo=False):
    """Per window: the best crate place for the window alone (after hub correction), and the best place for the
    window together with the one before it (two windows continuing on the same track, a 40-beat path)."""
    out = os.path.join(cache, "match", stamp.replace(" ", "_") + ".json")
    if os.path.exists(out) and not redo:
        return json.load(open(out))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rows, prev = [], None
    for q0 in range(0, len(V) - W + 1, STEP):
        b, sh = M.raw(V[q0:q0 + W])
        c = b - M.hub; c[~M.valid] = -9.0
        j = int(np.argmax(c)); k = M.track[j]
        tm = np.maximum.reduceat(c, M.starts)
        other = tm[M.song != M.song[k]]
        qt0, qt1 = float(beats[q0]), float(beats[q0 + W])
        r = dict(q0=q0, t0=round(qt0, 2), t1=round(qt1, 2), id=M.ids[k], pos=int(M.pos[j]), score=round(float(c[j]), 4),
                 other=round(float(other.max()), 4) if len(other) else None)
        if prev is not None:
            jt = np.full(len(c), -18.0, np.float32)
            jt[STEP:] = c[STEP:] + prev[:-STEP]
            jt[~M.cont] = -18.0
            jj = int(np.argmax(jt)); kk = M.track[jj]
            db = M.beats[kk]; p = int(M.pos[jj])
            dt0, dt1 = float(db[p]), float(db[min(p + W, len(db) - 1)])
            s0 = int(sh[jj]); fs = float(s0)
            r.update(pair_id=M.ids[kk], pair_pos=p, pair_score=round(float(jt[jj]) / 2, 4), at_s=round(dt0, 2),
                     rate=round((dt1 - dt0) / (qt1 - qt0), 4) if qt1 > qt0 else None, roll=round(fs, 2))
        rows.append(r); prev = c
    json.dump(rows, open(out, "w"))
    return rows


def plausible(r):
    """The speed is inside a deck's fader range (plus or minus 16 percent) and the chroma roll fits it: either the key
    moved with the speed (vinyl, roll = -36 log2 speed) or it did not (master tempo, roll 0), within one bin."""
    v = r.get("rate")
    if not v or not (0.84 <= v <= 1.16):
        return False
    return abs(r["roll"]) <= 1.0 or abs(r["roll"] + 36 * math.log2(v)) <= 1.0


def confirm(rows):
    """A window is identified when the best 40-beat path ending on it and the one starting on it (the next window's
    pair) name the same track, and both are plausible. The window then carries that track, its place and speed."""
    for r in rows:
        r["pl"] = "pair_id" in r and plausible(r)
    for i, r in enumerate(rows):
        r["ok"] = False
        n = rows[i + 1] if i + 1 < len(rows) else None
        if r["pl"] and n is not None and n["pl"] and n["pair_id"] == r["pair_id"]:
            r["ok"] = True
        if "pair_id" in r:
            r["id"] = r["pair_id"]; r["pos"] = r["pair_pos"]
    return rows


# ----------------------------------------------------------------------------- tempo
def regress_tempo(beats, t0, t1):
    """Tempo in [t0, t1] from a regression of beat time on beat index (local_tempo._local without folding)."""
    b = np.sort(beats[(beats >= t0) & (beats <= t1)])
    if len(b) < 8:
        return None
    ibi = np.diff(b); med = float(np.median(ibi))
    idx = np.concatenate([[0.0], np.cumsum(np.round(ibi / med))]); keep = np.ones(len(b), bool)
    P = med
    for _ in range(3):
        if keep.sum() < 8: return None
        A = np.vstack([idx[keep], np.ones(keep.sum())]).T
        P, off = np.linalg.lstsq(A, b[keep], rcond=None)[0]
        idx = idx + np.round((b - (off + P * idx)) / P)
        keep = np.abs(b - (off + P * idx)) < 0.25 * P
    return 60.0 / P


def fold(x, ref):
    """x times 1/2, 1 or 2, whichever lands nearest ref (octave errors of beat trackers)."""
    if not x or not ref:
        return x, 1
    m = min((0.5, 1.0, 2.0), key=lambda k: abs(math.log(x * k / ref)))
    return x * m, m


# ----------------------------------------------------------------------------- picks (Mixing.swift)
def song_key(song):
    t = song.lower()
    while True:
        a = min([i for i in (t.find("("), t.find("[")) if i >= 0], default=-1)
        if a < 0: break
        b = min([i for i in (t.find(")", a), t.find("]", a)) if i >= 0], default=-1)
        if b < 0: break
        t = t[:a] + t[b + 1:]
    return "".join(c for c in t if c.isalnum())


def song_identity(t):
    """The song across cuts: loose files often carry "Artist - Title" as the title with no artist field."""
    song = t["song"]
    if not t.get("artist") and " - " in song:
        song = song.split(" - ", 1)[1]
    return song_key(song)


MNUM = {"1": 1, "1/2": 0.5, "2": 2, "3/4": 0.75, "4/3": 4 / 3, "2/3": 2 / 3, "3/2": 1.5}


def candidates(byid, pairs, cur, exclude, allow_off):
    best, order = {}, []
    for p in pairs.get(cur["id"], []):
        t = byid.get(p["b"])
        if not t or t["id"] == cur["id"] or t["cut"] == cur["cut"] or t["_sk"] == cur["_sk"] or t["id"] in exclude:
            continue
        if not t["on"] and not allow_off:
            continue
        if t["_sk"] in best:
            o = byid[best[t["_sk"]]["b"]]
            better = (t["on"] and not o["on"]) or (t["on"] == o["on"] and ((t["longest"] and not o["longest"]) or
                                                                        (t["longest"] == o["longest"] and p["s"] > best[t["_sk"]]["s"])))
            if better: best[t["_sk"]] = p
        else:
            best[t["_sk"]] = p; order.append(t["_sk"])
    return sorted((best[k] for k in order), key=lambda p: -p["s"])


def surprise(byid, cur, p, below):
    t = byid[p["b"]]; tags = []
    if p["m"] == "1/2": tags.append("half time")
    elif p["m"] == "2": tags.append("double time")
    elif p["m"] != "1": tags.append("x" + p["m"])
    ao = cur.get("bpmOut") or cur.get("bpm") or cur.get("bpmTag") or 0
    bi = (t.get("bpmIn") or t.get("bpm") or t.get("bpmTag") or 0) * MNUM.get(p["m"], 1)
    if p.get("st", 0) >= 4 or (ao > 0 and abs(bi / ao - 1) >= 0.04): tags.append("tempo change")
    if t.get("hal") and not cur.get("hal"): tags.append("Halloween")
    if t.get("disc") and cur.get("disc") and t["disc"] != cur["disc"]: tags.append("to CD")
    elif not t["on"]: tags.append("off the discs")
    if t.get("era") and cur.get("era") and t["era"] != cur["era"]: tags.append(t["era"])
    if below: tags.append("deep cut")
    return tags


def roll_once(byid, cur, pool, mode, rng):
    """One rollSets(nSets: 1): returns (first screen ids, 'More' ids)."""
    pool = list(pool)
    n_best, n_hard = (3, 2) if mode == "full" else (2, 1)
    if not pool: return set(), set()
    top = pool[0]["s"]
    band_n = min(len(pool), max(6, min(12, sum(1 for p in pool if p["s"] >= top - 0.10))))
    band = pool[:band_n]; chosen = []
    for _ in range(min(n_best, len(band))):
        w = np.exp((np.array([p["s"] for p in band]) - top) / 0.05)
        i = rng.choice(len(band), p=w / w.sum()); chosen.append(band[i]["b"]); band = band[:i] + band[i + 1:]
    pool = [p for p in pool if p["b"] not in chosen]
    band_set = {p["b"] for p in pool[:max(0, band_n - len(chosen))]}
    hard = [(p, surprise(byid, cur, p, p["b"] not in band_set)) for p in pool]
    hard = [(p, t) for p, t in hard if t]; used = set()
    for _ in range(n_hard):
        if not hard: break
        w = np.array([max(0.05, p["s"]) * (0.4 + len([x for x in t if x != "deep cut"])) * (0.3 if t[0] in used else 1)
                      for p, t in hard])
        i = rng.choice(len(hard), p=w / w.sum()); p, t = hard.pop(i); used.add(t[0]); chosen.append(p["b"])
    pool = [p for p in pool if p["b"] not in chosen]
    return set(chosen), {p["b"] for p in pool[:12]}


def camelot_rel(ka, kb):
    try:
        na, la, nb, lb = int(ka[:-1]), ka[-1], int(kb[:-1]), kb[-1]
    except Exception:
        return "unknown"
    if ka == kb: return "same"
    d = (nb - na) % 12
    if la == lb and d in (1, 11): return "neighbour"
    if na == nb: return "relative"
    if la == lb and d == 2: return "boost"
    return "other"


def shift_camelot(k, semis):
    """Camelot code after moving the key by whole semitones (vinyl pitch moves the key: 7 steps per semitone)."""
    if not k or semis == 0: return k
    n, l = int(k[:-1]), k[-1]
    n = (n - 1 + 7 * semis) % 12 + 1
    return f"{n}{l}"


# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sets"); ap.add_argument("--deck", required=True); ap.add_argument("--cache", required=True)
    ap.add_argument("--features", default=os.path.join(HERE, "features"))
    ap.add_argument("--jobs", type=int, default=2); ap.add_argument("--prefix", default="set_oct24")
    ap.add_argument("--redo", default=""); ap.add_argument("--sims", type=int, default=2000)
    a = ap.parse_args()
    try: os.nice(19)
    except Exception: pass
    a.jobs = max(1, min(2, a.jobs))
    redo = set(a.redo.split(","))
    os.makedirs(a.cache, exist_ok=True)
    deck = json.load(open(a.deck))
    tracks = deck["tracks"]; byid = {t["id"]: t for t in tracks}
    for t in tracks:
        t["_sk"] = song_key(t["song"])        # the app's songKey (Model.swift), used to build the picks as the app does
        t["_id"] = song_identity(t)            # the song whatever the cut or file name, used to compare plays
    pairs = deck["pairs"]

    recs = inventory(a.sets)
    log(f"{len(recs)} recordings, {sum(r['secs'] for r in recs)/3600:.2f} h")

    # ---- crate features and matcher
    db = crate_features(tracks, a.features, a.cache, a.jobs, "crate" in redo)
    M = Matcher(db, {t["id"]: t["_id"] for t in tracks})
    log(f"crate: {len(db)} tracks, {M.V.shape[0]} beats")

    feats = {}
    for r in recs:
        if r["stub"]:
            continue
        p = decode(r, a.cache, "decode" in redo)
        b = beats_of(p, a.cache, r["stamp"], "beats" in redo)
        feats[r["stamp"]] = (b, rec_chroma(p, b, a.cache, r["stamp"], "chroma" in redo))
    hp = os.path.join(a.cache, "hub.npy")
    if os.path.exists(hp) and "hub" not in redo and len(np.load(hp)) == len(M.pos):
        M.hub = np.load(hp)
    else:
        bg = [V[q0:q0 + W] for b, V in feats.values() for q0 in range(0, len(V) - W + 1, W)]
        log(f"hub correction from {len(bg)} background windows")
        M.hubs(bg); np.save(hp, M.hub); redo.add("match")
    for r in recs:
        if r["stub"]:
            continue
        t0 = time.time()
        b, V = feats[r["stamp"]]
        rows = match_recording(M, V, b, a.cache, r["stamp"], "match" in redo)
        r["beats"], r["windows"], r["pcm"] = b, confirm(rows), pcm_path(a.cache, r["stamp"])
        log(f"  {r['stamp']}: {r['secs']/60:.1f} min, {len(b)} beats, {len(rows)} windows, "
            f"{sum(w['ok'] for w in rows)} identified ({time.time()-t0:.0f} s)")
    report(recs, byid, pairs, a)


# ----------------------------------------------------------------------------- report
def fmt(x, nd=1, sign=False):
    if x is None or (isinstance(x, float) and not math.isfinite(x)): return ""
    return (f"{x:+.{nd}f}" if sign else f"{x:.{nd}f}")


def mmss(s):
    s = int(round(s)); return f"{s//60}:{s%60:02d}"


def hhmm(dt):
    return dt.strftime("%H:%M:%S")


def audio_runs(r, byid):
    """Runs of identified windows on the same song (a gap of up to 4 windows inside a run is allowed)."""
    runs = []
    for w in r.get("windows", []):
        if not w["ok"]: continue
        sk = byid[w["id"]]["_id"]
        if runs and runs[-1]["sk"] == sk and w["t0"] - runs[-1]["last_t1"] <= 60:
            ru = runs[-1]; ru["last_t1"] = w["t1"]; ru["ws"].append(w)
        else:
            runs.append(dict(sk=sk, first_t0=w["t0"], last_t1=w["t1"], ws=[w]))
    for ru in runs:
        ru["id"] = Counter(w["id"] for w in ru["ws"]).most_common(1)[0][0]
    return [ru for ru in runs if len(ru["ws"]) >= 2]


def report(recs, byid, pairs, a):
    rng = np.random.default_rng(0)
    long_recs = [r for r in recs if not r["stub"]]
    first = recs[0]["local"]
    out = []
    P = out.append

    # ---------------- 1. inventory
    P("## Inventory\n\n| recording | start (local) | length | entries | kind |\n|---|---|---:|---:|---|")
    for r in recs:
        P(f"| {r['stamp'][11:]} | {r['local']:%H:%M:%S} | {mmss(r['secs'])} | {len(r['entries'])} | "
          f"{'stub' if r['stub'] else 'set'} |")
    night = [r for r in recs if r["local"].date() <= recs[0]["local"].date() + D.timedelta(days=1) and r["local"] - first < D.timedelta(hours=14)]
    total = sum(r["secs"] for r in night)
    P(f"\nRecordings in the night: {len(night)} ({len([r for r in night if not r['stub']])} longer than "
      f"{STUB_S:.0f} s); recorded {total/3600:.2f} h; first start {night[0]['local']:%H:%M}, last end "
      f"{max(r['local'] + D.timedelta(seconds=r['secs']) for r in night):%H:%M}.")
    gaps = []
    for x, y in zip(night, night[1:]):
        g = (y["local"] - (x["local"] + D.timedelta(seconds=x["secs"]))).total_seconds()
        if g > 60: gaps.append((x["local"] + D.timedelta(seconds=x["secs"]), g))
    P("\n| gap with no recording, from | length (min) |\n|---|---:|")
    for s, g in gaps: P(f"| {s:%H:%M:%S} | {g/60:.1f} |")

    # ---------------- 2. booth plays (log), merged across restarts
    plays = []
    for r in night:
        es = r["entries"]
        for i, e in enumerate(es):
            end = es[i + 1]["at"] if i + 1 < len(es) else r["secs"]
            clock = r["local"] + D.timedelta(seconds=e["at"])
            plays.append(dict(rec=r, e=e, start=e["at"], end=end, clock=clock, id=e["id"]))
    # the first entry of a recording that repeats the song the previous recording ended on is the same play
    merged = []
    for p in plays:
        q = merged[-1] if merged else None
        if q and q["id"] == p["id"] and q["rec"] is not p["rec"] and \
                (p["clock"] - (q["clock"] + D.timedelta(seconds=q["end"] - q["start"]))).total_seconds() < 600:
            q["cont"] = p; continue
        merged.append(p)
    seen = Counter()
    for p in merged:
        t = byid.get(p["id"], {}); p["t"] = t
        seen[t.get("_id", p["id"])] += 1; p["n"] = seen[t.get("_id", p["id"])]
    # audio runs per recording
    for r in long_recs:
        r["runs"] = audio_runs(r, byid)

    # audio check of each booth play: identified windows inside its span on the same song, the rest
    def windows_in(r, s, e):
        return [w for w in r.get("windows", []) if w["t0"] >= s and w["t1"] <= e]
    for p in merged:
        r = p["rec"]; t = p["t"]; sk = t.get("_id")
        spans = [(r, p["start"], p["end"])]
        if p.get("cont"): spans.append((p["cont"]["rec"], p["cont"]["start"], p["cont"]["end"]))
        ws = [w for rr, s, e in spans for w in windows_in(rr, s, e)]
        same = [w for w in ws if w["ok"] and byid[w["id"]]["_id"] == sk]
        other = [w for w in ws if w["ok"] and byid[w["id"]]["_id"] != sk]
        p["n_win"], p["n_same"], p["n_other"] = len(ws), len(same), len(other)
        p["span"] = sum(e - s for _, s, e in spans)
        p["same"] = same
        p["heard"] = (same[-1]["t1"] - same[0]["t0"]) if same and len(spans) == 1 else \
            (sum((lambda z: z[-1]["t1"] - z[0]["t0"] if z else 0)([w for w in same if w in windows_in(rr, s, e)])
                 for rr, s, e in spans) if same else 0.0)
        p["left_at"] = max(w["at_s"] + (w["t1"] - w["t0"]) * (w["rate"] or 1) for w in same) if same else None
        # pitch check: identified windows at least 20 s after the switch
        inner = [w for w in same if w["t0"] >= p["start"] + 20] or same
        mid = inner[len(inner) // 4: max(len(inner) // 4 + 1, 3 * len(inner) // 4)]
        p["rate"] = float(np.median([w["rate"] for w in mid if w["rate"]])) if mid else None
        p["roll"] = float(np.median([w["roll"] for w in mid])) if mid else None
        cat = t.get("bpm")
        p["cat_bpm"] = cat
        p["booth_bpm"] = cat * (1 + p["e"]["pitch"] / 100) if cat else None
        if mid:
            rr = p["rec"] if mid[0] in windows_in(p["rec"], p["start"], p["end"]) else p["cont"]["rec"]
            raw = regress_tempo(rr["beats"], mid[0]["t0"], mid[-1]["t1"])
            p["meas_bpm"], p["mult"] = fold(raw, p["booth_bpm"]) if raw else (None, 1)
            p["meas_win"] = (mid[0]["t0"], mid[-1]["t1"])
        else:
            p["meas_bpm"], p["mult"], p["meas_win"] = None, 1, None
        # identity not checked: the middle minute of the first six minutes after the switch
        s0, s1 = p["start"] + 30, min(p["start"] + p["span"] if not p.get("cont") else p["end"], p["start"] + 360) - 10
        raw2 = regress_tempo(r["beats"], (s0 + s1) / 2 - 30, (s0 + s1) / 2 + 30) if s1 - s0 >= 60 and "beats" in r else None
        p["mid_bpm"], p["mid_mult"] = fold(raw2, p["booth_bpm"]) if raw2 and p["booth_bpm"] else (None, 1)
        p["a_first"] = same[0]["t0"] if same else None; p["a_last"] = same[-1]["t1"] if same else None

    P("\n## Audio check against the booth, per recording (booth plays; identified windows inside them)\n")
    P("| recording | booth plays | plays with 3 or more windows on the booth's song | windows on the booth's song | windows on another song | "
      "share on the booth's song |\n|---|---:|---:|---:|---:|---:|")
    tot = [0, 0, 0, 0]
    for r in long_recs:
        ps = [p for p in merged if p["rec"] is r]
        if not ps: continue
        a_ = [len(ps), sum(p["n_same"] >= 3 for p in ps), sum(p["n_same"] for p in ps), sum(p["n_other"] for p in ps)]
        tot = [x + y for x, y in zip(tot, a_)]
        P(f"| {r['stamp'][11:]} | {a_[0]} | {a_[1]} | {a_[2]} | {a_[3]} | {100*a_[2]/max(1,a_[2]+a_[3]):.0f}% |")
    P(f"| all | {tot[0]} | {tot[1]} | {tot[2]} | {tot[3]} | {100*tot[2]/max(1,tot[2]+tot[3]):.0f}% |")
    P("\n## Songs as the booth logged them\n")
    P("| # | clock | recording | song | where | span (min) | pitch % | kind | conf | catalogue BPM | booth BPM | "
      "audio: same song / other song / windows | measured BPM | speed from alignment % | chroma roll (1/3 st) |")
    P("|---:|---|---|---|---|---:|---:|---|---:|---:|---:|---|---:|---:|---:|")
    for i, p in enumerate(merged, 1):
        e, t = p["e"], p["t"]
        P(f"| {i} | {p['clock']:%H:%M:%S} | {p['rec']['stamp'][11:]} | {t.get('song', e['title'])}"
          f"{' (again)' if p['n'] > 1 else ''} | {'disc' if t.get('on') else 'loose'} | {p['span']/60:.1f} | "
          f"{e['pitch']:+.1f} | {e['pitchKind'] or '-'} | {e['confidence']:.2f} | {fmt(p['cat_bpm'])} | "
          f"{fmt(p['booth_bpm'])} | {p['n_same']} / {p['n_other']} / {p['n_win']} | {fmt(p['meas_bpm'])} | "
          f"{fmt((p['rate'] - 1) * 100 if p['rate'] else None, 1, True)} | {fmt(p['roll'], 1, True)} |")

    # ---------------- coverage
    rec_s = sum(r["secs"] for r in night)
    long_s = sum(r["secs"] for r in long_recs)
    win_t = []
    for r in long_recs:
        for w in r["windows"]:
            # each window speaks for its central 8 beats
            win_t.append((r, w))
    def covered(pred):
        s = 0.0
        for r, w in win_t:
            if pred(r, w): s += (w["t1"] - w["t0"]) * STEP / W
        return s
    ident = covered(lambda r, w: w["ok"])
    allw = covered(lambda r, w: True)
    # booth's song at a window's time
    def booth_song(r, tt):
        cur = None
        for e in r["entries"]:
            if e["at"] <= tt: cur = e
        return cur
    agree = covered(lambda r, w: w["ok"] and (booth_song(r, (w["t0"] + w["t1"]) / 2) or {}).get("id") in byid and
                    byid[booth_song(r, (w["t0"] + w["t1"]) / 2)["id"]]["_id"] == byid[w["id"]]["_id"])
    nobooth = covered(lambda r, w: booth_song(r, (w["t0"] + w["t1"]) / 2) is None)
    nobooth_ok = covered(lambda r, w: w["ok"] and booth_song(r, (w["t0"] + w["t1"]) / 2) is None)
    disagree = ident - agree - nobooth_ok
    P("\n## Coverage (seconds of recording)\n\n| measure | hours | share |\n|---|---:|---:|")
    for lab, v, base in (("all recordings", rec_s, rec_s), ("recordings longer than a minute", long_s, rec_s),
                         ("windows matched (beats found)", allw, long_s),
                         ("audio check identified a crate song", ident, long_s),
                         ("  and the booth's current song is that song", agree, long_s),
                         ("  and the booth showed another song", disagree, long_s),
                         ("  before the booth's first entry of the recording", nobooth_ok, long_s),
                         ("audio check found no crate song", allw - ident, long_s),
                         ("before the booth's first entry (any)", nobooth, long_s)):
        P(f"| {lab} | {v/3600:.2f} | {100*v/base:.1f} |")

    # minute by minute: music or not (Beat This finds 40 or more beats in the minute: below half of the slowest
    # dance tempo in the crate, so a minute of music always passes and room noise rarely does), and what each says
    mins = Counter()
    for r in long_recs:
        ents = r["entries"]
        for m0 in range(0, int(r["secs"]) - 59, 60):
            nb = int(((r["beats"] >= m0) & (r["beats"] < m0 + 60)).sum())
            if nb < 40:
                mins["quiet"] += 1; continue
            mins["music"] += 1
            cur = None
            for e in ents:
                if e["at"] <= m0 + 30: cur = e
            ws = [w for w in r["windows"] if w["ok"] and m0 <= (w["t0"] + w["t1"]) / 2 < m0 + 60]
            sks = Counter(byid[w["id"]]["_id"] for w in ws)
            if cur is None:
                mins["music, booth showing nothing yet"] += 1
            else:
                t = byid.get(cur["id"], {})
                age = m0 + 30 - cur["at"]
                if age > (t.get("dur") or 300) + 60: mins["music, booth's song older than its own length"] += 1
            if not sks: mins["music, audio check: no crate song"] += 1
            elif cur is not None and byid.get(cur["id"], {}).get("_id") in sks: mins["music, audio check: the booth's song"] += 1
            else: mins["music, audio check: another crate song only"] += 1
    P("\n## Minutes of recording (recordings longer than a minute)\n\n| minute class | minutes | share of music minutes |\n|---|---:|---:|")
    for k in ("quiet", "music", "music, booth showing nothing yet", "music, booth's song older than its own length",
              "music, audio check: the booth's song", "music, audio check: another crate song only",
              "music, audio check: no crate song"):
        share = "" if k == "quiet" else f"{100 * mins[k] / max(1, mins['music']):.0f}%"
        P(f"| {k} | {mins[k]} | {share} |")

    # stretches the audio could not place
    def level(r, s0, s1):
        y = pcm(r["pcm"]); a0, a1 = int(s0 * SR), int(s1 * SR)
        x = np.asarray(y[a0:a1:4], dtype=np.float64)
        return 10 * math.log10(float(np.mean(x ** 2)) + 1e-20) if len(x) else None
    def bpm_rate(r, s0, s1):
        return int(((r["beats"] >= s0) & (r["beats"] < s1)).sum()) / max(1e-9, (s1 - s0) / 60)
    lv_all = [level(r, 0, r["secs"]) for r in long_recs]
    P(f"\nRecording level (RMS, dBFS) per recording longer than a minute: median {np.median(lv_all):.0f}, range "
      f"{min(lv_all):.0f} to {max(lv_all):.0f}.")
    P("\n| unidentified stretch of 2 min or more, from | recording | length (min) | level dBFS | beats per min | booth showing |\n|---|---|---:|---:|---:|---|")
    for r in long_recs:
        run_s, last = None, None
        ws = r["windows"]
        for i, w in enumerate(ws + [dict(ok=True, t0=r["secs"], t1=r["secs"])]):
            if not w["ok"]:
                if run_s is None: run_s = w["t0"]
                last = w["t1"]
            elif run_s is not None:
                if last - run_s >= 120:
                    bs = booth_song(r, run_s)
                    P(f"| {(r['local'] + D.timedelta(seconds=run_s)):%H:%M:%S} | {r['stamp'][11:]} | {(last-run_s)/60:.1f} | "
                      f"{level(r, run_s, last):.0f} | {bpm_rate(r, run_s, last):.0f} | "
                      f"{byid.get((bs or {}).get('id'), {}).get('song', '(nothing yet)')} |")
                run_s = None

    # ---------------- audio sequence
    P("\n## Songs as the audio check placed them (runs of 2 or more identified windows)\n")
    P("| clock | song | where | heard (min) | left at (min into the song) | song length | mix-out window | "
      "speed % | in booth's log |\n|---|---|---|---:|---:|---:|---|---:|---|")
    logged = {(p["rec"]["stamp"], byid.get(p["id"], {}).get("_id")) for p in plays}
    aud = []
    for r in long_recs:
        for ru in r["runs"]:
            t = byid[ru["id"]]
            left = max(w["at_s"] + (w["t1"] - w["t0"]) * (w["rate"] or 1) for w in ru["ws"])
            began = min(w["at_s"] for w in ru["ws"])
            rate = float(np.median([w["rate"] for w in ru["ws"] if w["rate"]]))
            aud.append(dict(r=r, ru=ru, t=t, left=left, began=began, rate=rate,
                            clock=r["local"] + D.timedelta(seconds=ru["first_t0"]),
                            heard=ru["last_t1"] - ru["first_t0"], inlog=(r["stamp"], ru["sk"]) in logged))
    for x in aud:
        t = x["t"]; mo = t.get("mixOut") or [None, None]
        P(f"| {x['clock']:%H:%M:%S} | {t['song']} | {'disc' if t['on'] else 'loose'} | {x['heard']/60:.1f} | "
          f"{x['left']/60:.1f} | {fmt((t.get('dur') or 0)/60)} | {fmt(mo[0]/60 if mo[0] else None)}-{fmt(mo[1]/60 if mo[1] else None)} | "
          f"{(x['rate']-1)*100:+.1f} | {'yes' if x['inlog'] else 'no'} |")

    # ---------------- pitch check
    P("\n## Pitch reading against the audio (booth plays with identified windows)\n")
    P("| kind | plays | median |error| % (tempo) | within 1 % | over 1 % | median |error| % (alignment) | within 1 % | "
      "octave-folded |\n|---|---:|---:|---:|---:|---:|---:|---:|")
    chk = [p for p in merged if p["meas_bpm"] and p["booth_bpm"]]
    for kind in ("vinyl", "master tempo", "", "all"):
        sub = [p for p in chk if kind == "all" or p["e"]["pitchKind"] == kind]
        if not sub: continue
        et = [abs(p["meas_bpm"] / p["booth_bpm"] - 1) * 100 for p in sub]
        ea = [abs(p["rate"] - (1 + p["e"]["pitch"] / 100)) * 100 for p in sub if p["rate"]]
        P(f"| {kind or 'none (pitch 0)'} | {len(sub)} | {np.median(et):.2f} | {sum(x <= 1 for x in et)} | {sum(x > 1 for x in et)} | "
          f"{np.median(ea):.2f} | {sum(x <= 1 for x in ea)} | {sum(p['mult'] != 1 for p in sub)} |")
    P("\nThe same, for every booth play of 70 s or more, tempo over the middle minute of its first six minutes after the "
      "switch (identity not checked by the audio):\n\n| kind | plays | median |error| % | within 1 % | over 1 % | octave-folded |\n|---|---:|---:|---:|---:|---:|")
    chk2 = [p for p in merged if p["mid_bpm"] and p["booth_bpm"]]
    for kind in ("vinyl", "master tempo", "", "all"):
        sub = [p for p in chk2 if kind == "all" or p["e"]["pitchKind"] == kind]
        if not sub: continue
        et = [abs(p["mid_bpm"] / p["booth_bpm"] - 1) * 100 for p in sub]
        P(f"| {kind or 'none (pitch 0)'} | {len(sub)} | {np.median(et):.2f} | {sum(x <= 1 for x in et)} | {sum(x > 1 for x in et)} | "
          f"{sum(p['mid_mult'] != 1 for p in sub)} |")
    P("\n| song | booth pitch % | kind | speed from alignment % | measured BPM | booth BPM | tempo error % | chroma roll (1/3 st) |"
      "\n|---|---:|---|---:|---:|---:|---:|---:|")
    for p in chk:
        ea = abs(p["rate"] - (1 + p["e"]["pitch"] / 100)) * 100 if p["rate"] else 0
        et = abs(p["meas_bpm"] / p["booth_bpm"] - 1) * 100
        if ea > 1 or et > 1:
            P(f"| {p['t']['song']} | {p['e']['pitch']:+.1f} | {p['e']['pitchKind'] or '-'} | {(p['rate']-1)*100:+.1f} | "
              f"{p['meas_bpm']:.1f} | {p['booth_bpm']:.1f} | {(p['meas_bpm']/p['booth_bpm']-1)*100:+.1f} | {fmt(p['roll'],1,True)} |")

    # ---------------- transitions (booth log order)
    trans = []
    hist = []
    for x, y in zip(merged, merged[1:]):
        A, B = x["t"], y["t"]
        hist.append(A["id"])
        if not A or not B or A["_id"] == B["_id"]: continue
        gap = (y["clock"] - (x["clock"] + D.timedelta(seconds=x["span"]))).total_seconds()
        if gap > 600: continue          # the booth was off between them: not a transition it saw
        excl = set(hist[-12:]) - {A["id"]}
        row = dict(a=A, b=B, x=x, y=y, clock=y["clock"], clean=x["span"] >= 60 and y["span"] >= 60 and x["span"] <= (A.get("dur") or 300) + 60)
        for allow, key in ((False, "disc"), (True, "all")):
            c = candidates(byid, pairs, A, excl, allow)
            rk = next((i + 1 for i, p in enumerate(c) if byid[p["b"]]["_id"] == B["_id"]), None)
            row[key + "_n"] = len(c); row[key + "_rank"] = rk
            row[key + "_score"] = next((p["s"] for p in c if byid[p["b"]]["_id"] == B["_id"]), None)
            if key == "disc":
                for mode in ("simple", "full"):
                    scr = more = 0
                    if rk:
                        for _ in range(a.sims):
                            s1, s2 = roll_once(byid, A, c, mode, rng)
                            bid = c[rk - 1]["b"]
                            scr += bid in s1; more += bid in s2
                    row[f"{mode}_screen"] = scr / a.sims; row[f"{mode}_more"] = more / a.sims
        row["raw_pairs"] = len(pairs.get(A["id"], []))
        row["in_raw"] = any(byid[p["b"]]["_id"] == B["_id"] for p in pairs.get(A["id"], []) if p["b"] in byid)
        row["key"] = camelot_rel(A.get("key"), B.get("key"))
        sa = round(12 * math.log2(1 + x["e"]["pitch"] / 100)) if x["e"]["pitchKind"] == "vinyl" else 0
        sb = round(12 * math.log2(1 + y["e"]["pitch"] / 100)) if y["e"]["pitchKind"] == "vinyl" else 0
        row["played_key"] = camelot_rel(shift_camelot(A.get("key"), sa), shift_camelot(B.get("key"), sb))
        ta = x["meas_bpm"] or x["booth_bpm"]; tb = y["meas_bpm"] or y["booth_bpm"]
        row["ta"], row["tb"] = ta, tb
        if ta and tb:
            f_, m = fold(tb, ta); row["dtempo"] = (tb / ta - 1) * 100; row["dtempo_fold"] = (f_ / ta - 1) * 100; row["fold"] = m
        else:
            row["dtempo"] = row["dtempo_fold"] = None; row["fold"] = 1
        mo = A.get("mixOut") or [None, None]; dur = A.get("dur")
        la = x["left_at"]
        row["left_at"] = la
        if la is None or not mo[0]: row["where"] = "unknown"
        elif la < mo[0]: row["where"] = "before mix-out"
        elif la <= mo[1]: row["where"] = "inside mix-out"
        elif dur and la >= dur - 10: row["where"] = "to the end"
        else: row["where"] = "after mix-out"
        trans.append(row)

    P("\n## Transitions in the booth's log\n")
    P("| clock | A | B | B disc | pick rank (disc filter) | of | score | on first screen, Simple | Full | in More, Simple | "
      "rank (all) | of | Camelot | played key | tempo A | tempo B | change % | A left at (min) | A mix-out window | where |")
    P("|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---:|---:|---:|---:|---|---|")
    for t in trans:
        A, B = t["a"], t["b"]; mo = A.get("mixOut") or [0, 0]
        P(f"| {t['clock']:%H:%M} | {A['song']} | {B['song']} | {'disc' if B['on'] else 'loose'} | {t['disc_rank'] or '-'} | "
          f"{t['disc_n']} | {fmt(t['disc_score'], 2)} | {100*t.get('simple_screen',0):.0f}% | {100*t.get('full_screen',0):.0f}% | "
          f"{100*t.get('simple_more',0):.0f}% | {t['all_rank'] or '-'} | {t['all_n']} | {t['key']} | {t['played_key']} | "
          f"{fmt(t['ta'])} | {fmt(t['tb'])} | {fmt(t['dtempo_fold'],1,True)}{' (x%g)' % t['fold'] if t['fold']!=1 else ''} | "
          f"{fmt(t['left_at']/60 if t['left_at'] else None)} | {mo[0]/60:.1f}-{mo[1]/60:.1f} | {t['where']} |")

    n = len(trans)
    def cnt(pred): return sum(1 for t in trans if pred(t))
    P(f"\n## Picks hit rate ({n} transitions)\n\n| measure | transitions | share |\n|---|---:|---:|")
    rows = [("B is on a disc (can be a pick under the default filter)", cnt(lambda t: t["b"]["on"])),
            ("B anywhere in A's stored pairs", cnt(lambda t: t["in_raw"])),
            ("B among the disc-filtered picks (any rank)", cnt(lambda t: t["disc_rank"])),
            ("  rank 1-3", cnt(lambda t: t["disc_rank"] and t["disc_rank"] <= 3)),
            ("  rank 4-10", cnt(lambda t: t["disc_rank"] and 4 <= t["disc_rank"] <= 10)),
            ("  rank 11-15", cnt(lambda t: t["disc_rank"] and 11 <= t["disc_rank"] <= 15)),
            ("  rank over 15", cnt(lambda t: t["disc_rank"] and t["disc_rank"] > 15)),
            ("B among all picks, all filters on (any rank)", cnt(lambda t: t["all_rank"])),
            ("  all filters, rank 1-15", cnt(lambda t: t["all_rank"] and t["all_rank"] <= 15))]
    for lab, v in rows: P(f"| {lab} | {v} | {100*v/max(1,n):.0f}% |")
    cl = [t for t in trans if t["clean"]]
    P(f"| (clean: both logged a minute or more, A logged no longer than its length plus a minute: {len(cl)} transitions) B among the disc-filtered picks | "
      f"{sum(1 for t in cl if t['disc_rank'])} | {100*sum(1 for t in cl if t['disc_rank'])/max(1,len(cl)):.0f}% |")
    P(f"| (same) rank 1-15 | {sum(1 for t in cl if t['disc_rank'] and t['disc_rank'] <= 15)} | "
      f"{100*sum(1 for t in cl if t['disc_rank'] and t['disc_rank'] <= 15)/max(1,len(cl)):.0f}% |")
    P(f"| (same) expected on the first screen, Simple | {sum(t.get('simple_screen',0) for t in cl):.1f} | "
      f"{100*sum(t.get('simple_screen',0) for t in cl)/max(1,len(cl)):.0f}% |")
    exp_s = sum(t.get("simple_screen", 0) for t in trans); exp_f = sum(t.get("full_screen", 0) for t in trans)
    exp_m = sum(t.get("simple_screen", 0) + t.get("simple_more", 0) for t in trans)
    P(f"| expected on the first screen, Simple (sum of chances) | {exp_s:.1f} | {100*exp_s/max(1,n):.0f}% |")
    P(f"| expected on the first screen, Full | {exp_f:.1f} | {100*exp_f/max(1,n):.0f}% |")
    P(f"| expected on screen or in More, Simple | {exp_m:.1f} | {100*exp_m/max(1,n):.0f}% |")
    P(f"\nPairs stored per source track: median {np.median([len(v) for v in pairs.values()]):.0f}, "
      f"min {min(len(v) for v in pairs.values())}, max {max(len(v) for v in pairs.values())}.")

    P("\n| Camelot (catalogue keys) | transitions |\n|---|---:|")
    for k, v in Counter(t["key"] for t in trans).most_common(): P(f"| {k} | {v} |")
    P("\n| Camelot (keys moved by the vinyl pitch, whole semitones) | transitions |\n|---|---:|")
    for k, v in Counter(t["played_key"] for t in trans).most_common(): P(f"| {k} | {v} |")
    dt = [abs(t["dtempo_fold"]) for t in trans if t["dtempo_fold"] is not None]
    P("\n| tempo change at the transition (octave-folded) | transitions |\n|---|---:|")
    for lo, hi in ((0, 1), (1, 3), (3, 6), (6, 10), (10, 100)):
        P(f"| {lo}-{hi} % | {sum(lo <= x < hi for x in dt)} |")
    P(f"| median | {np.median(dt):.1f} % |" if dt else "")
    P("\n| where A was left | transitions |\n|---|---:|")
    for k, v in Counter(t["where"] for t in trans).most_common(): P(f"| {k} | {v} |")

    # ---------------- play lengths (audio runs)
    short = [x for x in aud if x["heard"] < 60]
    aud = [x for x in aud if x["heard"] >= 60]
    hl = [x["heard"] / 60 for x in aud]
    fr = [x["left"] / (x["t"].get("dur") or 1) for x in aud if x["t"].get("dur")]
    P("\n## Play lengths (audio runs heard for a minute or more)\n\n| measure | value |\n|---|---:|")
    P(f"| runs shorter than a minute (left out) | {len(short)} |")
    if hl:
        P(f"| runs | {len(hl)} |\n| heard, median (min) | {np.median(hl):.1f} |\n| heard, quartiles (min) | "
          f"{np.percentile(hl,25):.1f}-{np.percentile(hl,75):.1f} |\n| left at, share of the song, median | {np.median(fr):.2f} |")
        wh = Counter()
        for x in aud:
            mo = x["t"].get("mixOut") or [None, None]; dur = x["t"].get("dur")
            if not mo[0]: wh["no window"] += 1
            elif x["left"] < mo[0]: wh["left before the mix-out window"] += 1
            elif x["left"] <= mo[1]: wh["left inside it"] += 1
            elif dur and x["left"] >= dur - 10: wh["played to the end"] += 1
            else: wh["left after it, before the end"] += 1
        for k, v in wh.most_common(): P(f"| {k} | {v} |")
    ls = [p["span"] / 60 for p in merged]
    P(f"| booth log: span from switch to switch, median (min) | {np.median(ls):.1f} |")

    # ---------------- tempo arc
    P("\n## Tempo over the night (10-minute bins, identified windows: catalogue BPM x speed)\n")
    P("| from | music minutes | Beat This tempo, all music (median of 30 s) | identified windows | median BPM | min | max | "
      "booth BPM (log, time-weighted, at most the song's length) |\n|---|---:|---:|---:|---:|---:|---:|---:|")
    bins = defaultdict(list); bb = defaultdict(lambda: [0.0, 0.0]); free = defaultdict(list); mm = Counter()
    for r in long_recs:
        for m0 in range(0, int(r["secs"]) - 29, 30):
            if int(((r["beats"] >= m0) & (r["beats"] < m0 + 30)).sum()) < 20: continue
            c = r["local"] + D.timedelta(seconds=m0); k = c.replace(minute=c.minute // 10 * 10, second=0, microsecond=0)
            mm[k] += 0.5
            v = regress_tempo(r["beats"], m0, m0 + 30)
            if v: free[k].append(v)
    for r in long_recs:
        for w in r["windows"]:
            if not w["ok"] or not w["rate"]: continue
            c = r["local"] + D.timedelta(seconds=w["t0"]); k = c.replace(minute=c.minute // 10 * 10, second=0, microsecond=0)
            bpm = byid[w["id"]].get("bpm")
            if bpm: bins[k].append(bpm * w["rate"])
    for p in merged:
        if not p["booth_bpm"]: continue
        s = p["clock"]; e = s + D.timedelta(seconds=min(p["span"], (p["t"].get("dur") or 300) + 60))
        while s < e:
            k = s.replace(minute=s.minute // 10 * 10, second=0, microsecond=0); nxt = min(e, k + D.timedelta(minutes=10))
            d = (nxt - s).total_seconds(); bb[k][0] += d * p["booth_bpm"]; bb[k][1] += d; s = nxt
    for k in sorted(set(bins) | set(bb) | set(free)):
        v = bins.get(k, []); f_ = free.get(k, [])
        P(f"| {k:%H:%M} | {mm[k]:.0f} | {fmt(float(np.median(f_)) if f_ else None)} | {len(v)} | {fmt(float(np.median(v)) if v else None)} | {fmt(min(v) if v else None)} | "
          f"{fmt(max(v) if v else None)} | {fmt(bb[k][0]/bb[k][1] if bb[k][1] else None)} |")

    # ---------------- lag
    P("\n## Booth lag at song changes (audio run of B begins -> booth's entry for B)\n")
    P("| B | audio first heard B | booth entry | lag (s) | B began at (s into the song) |\n|---|---|---|---:|---:|")
    lags = []
    for t in trans:
        y = t["y"]; r = y["rec"]; sk = t["b"]["_id"]
        cand = [ru for ru in r.get("runs", []) if ru["sk"] == sk and ru["first_t0"] <= y["start"] + 30 and ru["last_t1"] >= y["start"]]
        if not cand: continue
        ru = cand[0]; lag = y["start"] - ru["first_t0"]; lags.append(lag)
        P(f"| {t['b']['song']} | {(r['local'] + D.timedelta(seconds=ru['first_t0'])):%H:%M:%S} | {y['clock']:%H:%M:%S} | {lag:.0f} | "
          f"{min(w['at_s'] for w in ru['ws']):.0f} |")
    if lags: P(f"\nLag: median {np.median(lags):.0f} s, quartiles {np.percentile(lags,25):.0f}-{np.percentile(lags,75):.0f} s, n {len(lags)}.")

    print("\n".join(out))

    # ---------------- TSVs
    sp = os.path.join(HERE, f"{a.prefix}_songs.tsv")
    with open(sp, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["n", "recording", "clock_first", "first_s", "next_switch_s", "span_s", "id", "song", "artist", "disc",
                    "again", "pitch_pct", "pitch_kind", "confidence", "catalogue_bpm", "booth_bpm", "audio_windows",
                    "audio_same_song", "audio_other_song", "audio_first_s", "audio_last_s", "audio_heard_s", "left_at_s", "song_dur_s", "mix_out",
                    "measured_bpm", "measured_octave", "measure_from_s", "measure_to_s", "speed_pct_alignment", "chroma_roll",
                    "mid_span_bpm"])
        for i, p in enumerate(merged, 1):
            t, e = p["t"], p["e"]; mo = t.get("mixOut") or ["", ""]
            w.writerow([i, p["rec"]["stamp"][11:], p["clock"].strftime("%H:%M:%S"), e["at"], round(p["start"] + p["span"], 1)
                        if not p.get("cont") else "", round(p["span"], 1), p["id"], t.get("song", e["title"]), t.get("artist", e["artist"]),
                        "disc" if t.get("on") else "loose", p["n"] - 1, e["pitch"], e["pitchKind"], e["confidence"],
                        fmt(p["cat_bpm"], 2), fmt(p["booth_bpm"], 2), p["n_win"], p["n_same"], p["n_other"], fmt(p["a_first"]), fmt(p["a_last"]), round(p["heard"], 1),
                        fmt(p["left_at"]), fmt(t.get("dur")), f"{mo[0]}-{mo[1]}", fmt(p["meas_bpm"], 2), p["mult"],
                        fmt(p["meas_win"][0] if p["meas_win"] else None), fmt(p["meas_win"][1] if p["meas_win"] else None),
                        fmt((p["rate"] - 1) * 100 if p["rate"] else None, 2), fmt(p["roll"], 2),
                        fmt(p["mid_bpm"], 2)])
    tp = os.path.join(HERE, f"{a.prefix}_transitions.tsv")
    with open(tp, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["clock", "a_id", "a_song", "b_id", "b_song", "b_disc", "pick_rank_disc", "picks_disc", "score",
                    "p_first_screen_simple", "p_first_screen_full", "p_more_simple", "pick_rank_all", "picks_all",
                    "camelot_catalogue", "camelot_played", "tempo_a", "tempo_b", "tempo_change_pct", "octave",
                    "a_span_s", "clean", "a_left_at_s", "a_dur_s", "a_mix_out", "a_where"])
        for t in trans:
            A, B = t["a"], t["b"]; mo = A.get("mixOut") or ["", ""]
            w.writerow([t["clock"].strftime("%H:%M:%S"), A["id"], A["song"], B["id"], B["song"], "disc" if B["on"] else "loose",
                        t["disc_rank"] or "", t["disc_n"], fmt(t["disc_score"], 3), round(t.get("simple_screen", 0), 3),
                        round(t.get("full_screen", 0), 3), round(t.get("simple_more", 0), 3), t["all_rank"] or "", t["all_n"],
                        t["key"], t["played_key"], fmt(t["ta"], 2), fmt(t["tb"], 2), fmt(t["dtempo_fold"], 2), t["fold"],
                        round(t["x"]["span"], 1), int(t["clean"]),
                        fmt(t["left_at"]), fmt(A.get("dur")), f"{mo[0]}-{mo[1]}", t["where"]])
    log(f"wrote {os.path.relpath(sp, HERE)} and {os.path.relpath(tp, HERE)}")


if __name__ == "__main__":
    main()
