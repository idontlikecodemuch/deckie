#!/usr/bin/env python3
"""The real-room test: Deckie's own matcher over recordings a booth made at a real set, scored against an answer key
built from independent evidence. Nothing it writes belongs in the repository: it works on the DJ's own recordings and
music, and every file it writes goes under WORK, which must be outside the repository (or in an ignored folder).

  room_test.py prepare RECORDINGS WORK [--step 2] [--lengths 3,5,8,12] [--min-seconds 30] [--part-from ISO]
      RECORDINGS: a folder of booth recordings, each audio file beside the booth's "<stem> log.json" (what the booth's
      recogniser named and when). Decodes each to WORK/rec/<rid>.s16 (mono, 16 kHz, 16-bit) and writes
      WORK/recordings.json and WORK/queries.tsv: at every --step seconds t, one query per length L of the sound
      from t - L to t, as the booth would listen (the last L seconds, asked every few seconds). --part-from: recordings
      started at or after this UTC time are part "set", earlier ones part "before" (tests, rehearsal).
  room_test.py catalogue CRATE.json MUSIC_ROOT WORK [--subset PREFIX ...]
      writes WORK/catalogue.json: crate id -> audio file, title, artist, duration (from a Deckie crate file's
      crate.json; MUSIC_ROOT is the folder its "rel" paths start from) and WORK/subset-<n>.txt for each PREFIX.
  room_test.py extra FOLDER WORK [--mix-minutes 15]
      more music to add to the catalogue as distractors (see extra()).
  room_test.py truth WORK RESULTS.tsv [RESULTS2.tsv ...] [--threshold 2.96] [--jobs 1]
      builds the answer key (see TRUTH below) into WORK/truth.json.
  room_test.py listen-report WORK NAME=READINGS.tsv [...] [--mix ids.txt] [--catalogue-ids NAME=ids.txt]
      scores the finished listener's readings (deckie-listen --list, one a second) against the same answer key.
  room_test.py report WORK NAME=RESULTS.tsv [NAME=RESULTS.tsv ...] [--threshold 2.96]
      writes WORK/report.md (aggregate numbers only: counts, percent, seconds, dB; songs are never named).

TRUTH. There is no perfect answer key; this builds the best available one from evidence that does not depend on the
matcher's yes-or-no decision:
  1. Candidates: (a) every (song, place, speed) the matcher put first or second in at least two windows that agree on
     the place, whatever its confidence (so a song the matcher saw but did not accept is still tried); (b) every song
     the booth's own log names, at the time it names it, its place found by searching the whole song; (c) for stretches
     with sound and a steady beat that nothing explains, a search of a few songs' worth of segments against a given
     subset of the catalogue (the discs), at the deck's normal speed.
  2. Verification by the waveform, not by landmarks: the song's own audio, put where the candidate says and at its
     speed, is compared with the recording by magnitude-squared coherence (the share of the recording's power, band
     by band, that a linear filter of the song's audio explains; a room's sound is such a filter). Per 6 s segment
     every 2 s, lag searched within half a second. The pass mark is the 99.9th percentile of the same measurement
     with a different, randomly drawn song of the catalogue at a random place (the null), so it is fixed by chance,
     not by this material's songs.
  3. A candidate is followed forward and back segment by segment while it passes. Two songs that pass at the same
     moments and whose own audio there is the same (coherence of the two references with each other) are copies of
     one recording (a song and the mix that contains it, or two files of one track): one entry in the key.
  4. Each 2 s moment is then: one song (known with confidence), two or more (a blend), silence (the level under a
     floor), talk or no beat (sound without a steady beat), or unknown (a steady beat and no song verified).
The coherence also gives the room's loudness: the coherent share is the song as the microphone hears it (through
the room), the rest is everything else (crowd, talk, the other deck, late reverberation, distortion, the recording's
own encoding). Music over the rest, in dB, is a lower bound on the music-over-noise figure of the outside benchmark.
"""
import argparse, bisect, collections, glob, hashlib, json, math, os, random, statistics, subprocess, sys
import numpy as np

SR = 16000
STEP = 2.0
SEG = 6.0
NFFT = 4096
HOP = 2048
LAG = 0.5
BAND = (300.0, 3600.0)     # the fingerprint's band
FULL = (60.0, 7000.0)      # nearly all of it (the outside benchmark measured levels over the whole band)


# ---------------------------------------------------------------- audio
def decode(src, dst, rate=SR):
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        r = subprocess.run(["nice", "-n", "19", "ffmpeg", "-v", "error", "-nostdin", "-threads", "1", "-i", src, "-ac", "1", "-ar", str(rate),
                            "-f", "s16le", dst + ".part"])
        if r.returncode != 0 or not os.path.exists(dst + ".part"):
            return None
        os.replace(dst + ".part", dst)
    return np.memmap(dst, dtype="<i2", mode="r")


class Refs:
    """Songs' audio at 16 kHz, decoded once to WORK/ref and mapped from disk."""
    def __init__(self, work, catalogue):
        self.dir = os.path.join(work, "ref"); self.cat = catalogue; self.open = {}

    def get(self, sid):
        if sid not in self.open:
            if len(self.open) > 400:
                self.open.clear()
            f = self.cat[sid]["file"]
            if not os.path.exists(f):
                import unicodedata
                f = next((g for g in (unicodedata.normalize(k, f) for k in ("NFC", "NFD")) if os.path.exists(g)), f)
            self.open[sid] = decode(f, os.path.join(self.dir, sid + ".s16"))
        return self.open[sid]


def chunk(x, start, n):
    """n samples of x from sample `start` (may be out of range: zeros there), as float."""
    out = np.zeros(n, dtype=np.float64)
    a, b = max(0, start), min(len(x), start + n)
    if b > a:
        out[a - start:b - start] = x[a:b]
    return out


def ref_at(x, song_t0, speed, n, margin):
    """The song's audio from song time song_t0 - margin*speed, n + 2*margin*SR samples of recording time at `speed`
    (vinyl-style: resampled)."""
    m = int(margin * SR)
    total = n + 2 * m
    s0 = song_t0 * SR - m * speed
    if abs(speed - 1) < 1e-6:
        return chunk(x, int(round(s0)), total)
    first = int(math.floor(s0)) - 2
    span = chunk(x, first, int(total * speed) + 6)
    pos = s0 - first + np.arange(total) * speed
    return np.interp(pos, np.arange(len(span)), span)


WIN = np.hanning(NFFT)
FREQS = np.fft.rfftfreq(NFFT, 1 / SR)
BI = (FREQS >= BAND[0]) & (FREQS <= BAND[1])
FI = (FREQS >= FULL[0]) & (FREQS <= FULL[1])


def frames(x):
    k = 1 + (len(x) - NFFT) // HOP
    idx = np.arange(NFFT)[None, :] + HOP * np.arange(k)[:, None]
    return np.fft.rfft(x[idx] * WIN, axis=1)


def best_lag(y, xr, maxlag):
    """Lag (samples) of xr against y by phase-transform cross-correlation, within +-maxlag; xr has maxlag extra
    samples either side. Returns lag and the fractional refinement."""
    n = 1 << int(math.ceil(math.log2(len(xr) + len(y))))
    Y = np.fft.rfft(y, n); X = np.fft.rfft(xr, n)
    c = X * np.conj(Y)
    c /= np.abs(c) + 1e-12
    r = np.fft.irfft(c, n)
    # r[k] peaks where xr[k + i] matches y[i]; k = maxlag is no lag.
    seg = r[:2 * maxlag + 1]
    k = int(np.argmax(seg))
    frac = 0.0
    if 0 < k < len(seg) - 1:
        a, b, cc = seg[k - 1], seg[k], seg[k + 1]
        d = a - 2 * b + cc
        if d < 0:
            frac = 0.5 * (a - cc) / d
    return k - maxlag, frac


def coherence(y, x):
    """Bias-corrected magnitude-squared coherence share of y's power explained by x, in the band and the full band,
    and y's power in the band (for the level)."""
    Y = frames(y); X = frames(x)
    k = Y.shape[0]
    sxy = np.sum(X * np.conj(Y), axis=0)
    sxx = np.sum(np.abs(X) ** 2, axis=0); syy = np.sum(np.abs(Y) ** 2, axis=0)
    g = np.abs(sxy) ** 2 / (sxx * syy + 1e-20)
    g = np.clip((g - 1 / k) / (1 - 1 / k), 0, 1)
    fb = float(np.sum(g[BI] * syy[BI]) / (np.sum(syy[BI]) + 1e-20))
    ff = float(np.sum(g[FI] * syy[FI]) / (np.sum(syy[FI]) + 1e-20))
    return fb, ff


def test_segment(rec, t, ref, song_t, speed, maxlag=LAG):
    """Coherence of the recording's segment centred on t with the song's audio centred on song time song_t.
    Returns (share in the band, share in the full band, lag in seconds, speed used). The speed is refined from the
    lags of the segment's four quarters: the recorder's clock and the deck's differ by up to a few tenths of a percent,
    which over 6 s moves the high frequencies by whole cycles. The better of the refined and the given speed is kept
    (the null is measured the same way, so the choice is paid for in the pass mark)."""
    n = int(SEG * SR)
    y = chunk(rec, int((t - SEG / 2) * SR), n)
    if np.sum(y * y) < 1e-3:
        return 0.0, 0.0, 0.0, speed
    ml = int(maxlag * SR)
    xr = ref_at(ref, song_t - speed * SEG / 2, speed, n, maxlag)
    if np.sum(xr * xr) < 1e-3:
        return 0.0, 0.0, 0.0, speed
    lag, frac = best_lag(y, xr, ml)
    x = xr[ml + lag: ml + lag + n]
    fb, ff = coherence(y, x)
    best = (fb, ff, (lag + frac) / SR, speed)
    # quarters: lag of each against the aligned song (within 25 ms), then a straight line through them
    q = n // 4; sm = int(0.025 * SR)
    xa = xr[max(0, ml + lag - sm): ml + lag + n + sm]
    if len(xa) == n + 2 * sm:
        lags = []
        for k in range(4):
            l, f = best_lag(y[k * q:(k + 1) * q], xa[k * q:(k + 1) * q + 2 * sm], sm)
            lags.append(l + f)
        c = (np.arange(4) + 0.5) * q / SR
        slope = np.polyfit(c, np.array(lags) / SR, 1)[0]
        if abs(slope) > 2e-5 and abs(slope) < 0.01:
            sp2 = speed * (1 + slope)
            centre = song_t + speed * (lag + frac) / SR
            xr2 = ref_at(ref, centre - sp2 * SEG / 2, sp2, n, 0.02)
            l2, f2 = best_lag(y, xr2, int(0.02 * SR))
            x2 = xr2[int(0.02 * SR) + l2: int(0.02 * SR) + l2 + n]
            fb2, ff2 = coherence(y, x2)
            if fb2 > fb:
                best = (fb2, ff2, (lag + frac) / SR + (l2 + f2) / SR, sp2)
    return best


EHOP = 160


def envelope(x, block=EHOP * 6400):
    """Onset envelope: the positive change of log band energies, every 10 ms (frames of 32 ms)."""
    out = []
    edges = np.array([0, 4, 8, 16, 32, 64, 128, 257])  # bins of a 512-point transform at 16 kHz: to 31, 62, ... 8000 Hz
    prev = None
    for b0 in range(0, len(x), block):
        seg = np.asarray(x[b0:b0 + block + 512], dtype=np.float64)
        if len(seg) < 512:
            break
        k = 1 + (min(len(seg), block + 512) - 512) // EHOP
        k = min(k, block // EHOP)
        idx = np.arange(512)[None, :] + EHOP * np.arange(k)[:, None]
        sp = np.abs(np.fft.rfft(seg[idx] * np.hanning(512), axis=1)) ** 2
        bands = np.log1p(np.add.reduceat(sp, edges[:-1], axis=1) * 1e-6)
        if prev is not None:
            bands = np.vstack([prev[None, :], bands])
        d = np.maximum(0, np.diff(bands, axis=0)).sum(axis=1)
        out.append(d if prev is not None else np.concatenate([[0], d]))
        prev = bands[-1]
    return np.concatenate(out) if out else np.zeros(1)


SEED_GRID = [k * 0.0004 for k in range(-6, 7)]


def seed_test(rec, t, ref, song_t, speed):
    """test_segment at speeds around the given one (to +-0.24 %, the matcher's speed reading and the clocks' difference
    are not exact enough for a waveform test): the best of them."""
    best = None
    for g in SEED_GRID:
        r = test_segment(rec, t, ref, song_t, speed * (1 + g))
        if best is None or r[0] > best[0]:
            best = r
    return best


def db(share):
    share = min(max(share, 1e-6), 1 - 1e-6)
    return 10 * math.log10(share / (1 - share))


# ---------------------------------------------------------------- prepare
def prepare(a):
    work = a.work
    os.makedirs(os.path.join(work, "rec"), exist_ok=True)
    recs = []
    lengths = [float(v) for v in a.lengths.split(",")]
    logs = sorted(glob.glob(os.path.join(a.recordings, "* log.json")))
    for i, lp in enumerate(logs):
        log = json.load(open(lp))
        audio = os.path.join(a.recordings, log.get("audioFile") or os.path.basename(lp)[:-9])
        if not os.path.exists(audio):
            continue
        rid = "r%02d" % i
        x = decode(audio, os.path.join(work, "rec", rid + ".s16"))
        dur = 0 if x is None else len(x) / SR
        part = "set" if (a.part_from and log.get("started", "") >= a.part_from) else ("before" if a.part_from else "set")
        recs.append(dict(rid=rid, audio=audio, started=log.get("started"), seconds=dur, part=part,
                         entries=log.get("entries", []), used=dur >= a.min_seconds))
    json.dump(recs, open(os.path.join(work, "recordings.json"), "w"), indent=1)
    with open(os.path.join(work, "queries.tsv"), "w") as f:
        for r in recs:
            if not r["used"]:
                continue
            path = os.path.join(work, "rec", r["rid"] + ".s16")
            t = max(lengths)
            while t <= r["seconds"] + 1e-6:
                for L in lengths:
                    f.write("%s:%.0f:%g\t%s\t%d\t%d\t%d\n" % (r["rid"], t, L, path, int((t - L) * SR), int(L * SR), SR))
                t += a.step
    print("recordings %d, used %d, hours %.2f" % (len(recs), sum(r["used"] for r in recs),
                                                  sum(r["seconds"] for r in recs if r["used"]) / 3600))


def catalogue(a):
    crate = json.load(open(a.crate))["tracks"]
    cat = {}
    for t in crate:
        fi = t.get("file") or {}; ident = t.get("ident") or {}
        cat[t["id"]] = dict(file=os.path.join(a.root, fi.get("rel", "")), title=ident.get("title") or "",
                            artist=ident.get("artist") or "", seconds=fi.get("duration_s") or 0, rel=fi.get("rel", ""))
    json.dump(cat, open(os.path.join(a.work, "catalogue.json"), "w"))
    for n, p in enumerate(a.subset or []):
        ids = sorted(k for k, v in cat.items() if v["rel"].startswith(p))
        open(os.path.join(a.work, "subset-%d.txt" % n), "w").write("\n".join(ids) + "\n")
        print("subset %d: %d songs" % (n, len(ids)))
    print("catalogue: %d songs" % len(cat))


def extra(a):
    """More music as distractors: every finished audio file under a folder (a file with a ".part" beside it, or named
    ".part", is still downloading and is skipped), ids from a hash of the path, and files of --mix-minutes or longer
    (published DJ mixes, not songs) set aside. Writes WORK/extra-list.tsv and prints the counts."""
    rows = []; partial = mixes = short = 0
    for root, _, files in os.walk(a.folder):
        for f in sorted(files):
            p = os.path.join(root, f)
            if f.startswith(".") or not f.lower().endswith((".mp3", ".flac", ".m4a", ".wav", ".aif", ".aiff", ".ogg")):
                continue
            if os.path.exists(p + ".part"):
                partial += 1; continue
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                               capture_output=True, text=True)
            try:
                dur = float(r.stdout.strip())
            except ValueError:
                partial += 1; continue
            if dur >= a.mix_minutes * 60:
                mixes += 1; continue
            if dur < 60:
                short += 1; continue
            rows.append(("x" + hashlib.sha1(p.encode()).hexdigest()[:15], p, dur))
    with open(os.path.join(a.work, "extra-list.tsv"), "w") as f:
        for i, p, _ in rows:
            f.write("%s\t%s\n" % (i, p))
    print("extra songs %d (%.1f hours); set aside: %d unfinished or unreadable, %d of %g minutes or more (mixes), %d under a minute" % (
        len(rows), sum(r[2] for r in rows) / 3600, partial, mixes, a.mix_minutes, short))


# ---------------------------------------------------------------- results
def read_results(path):
    """query id -> (rid, t, L, best, second): each (song, score, matched, offset, tempo, pitch, confidence)."""
    out = {}
    for line in open(path):
        c = line.rstrip("\n").split("\t")
        if len(c) < 18:
            continue
        rid, t, L = c[0].split(":")
        b = (c[4], float(c[5]), int(c[6]), float(c[7]), float(c[8]), float(c[9]), float(c[16]))
        s = (c[10], float(c[11]), int(c[12]), float(c[13]), float(c[14]), float(c[15]), float(c[17]))
        out[c[0]] = dict(rid=rid, t=float(t), L=float(L), best=b, second=s, ms=float(c[3]), fpms=float(c[2]), points=int(c[1]))
    return out


def norm(s):
    s = s.lower()
    for ch in "()[]{}-_.,'\"!?&:;/":
        s = s.replace(ch, " ")
    return " ".join(w for w in s.split() if w not in ("feat", "ft", "the", "a"))


def log_ids(entry, index):
    """Catalogue songs a booth log entry may mean: same title and artist; else a catalogue title that contains the
    logged one (the booth's crate may have dropped a version's name) with the artist's first word in it; else, for an
    entry with no artist, the logged title containing the catalogue's artist and title."""
    t, a = norm(entry.get("title", "")), norm(entry.get("artist", ""))
    if (t, a) in index:
        return list(index[(t, a)])
    out = []
    for (ct, ca), ks in index.items():
        if not ct or not t:
            continue
        if a and (t in ct or ct in t) and a.split()[0] in ca:
            out += ks
        elif not a and ca and ca in t and ct in t:
            out += ks
    return out


# ---------------------------------------------------------------- truth
class Truth:
    def __init__(self, work, threshold):
        self.work = work
        self.recs = {r["rid"]: r for r in json.load(open(os.path.join(work, "recordings.json"))) if r["used"]}
        self.cat = json.load(open(os.path.join(work, "catalogue.json")))
        self.refs = Refs(work, self.cat)
        self.threshold = threshold
        self.rec_audio = {rid: np.memmap(os.path.join(work, "rec", rid + ".s16"), dtype="<i2", mode="r") for rid in self.recs}

    def null(self, n=3000, seed=7):
        """The pass mark: coherence of recording segments with randomly drawn songs at random places."""
        rng = random.Random(seed)
        ids = sorted(k for k, v in self.cat.items() if 60 < v["seconds"] < 900)
        ids = rng.sample(ids, min(len(ids), 80))    # 80 songs, many places each (each song is decoded once)
        rids = sorted(self.rec_audio)
        weights = [self.recs[r]["seconds"] for r in rids]
        vals = []
        while len(vals) < n:
            rid = rng.choices(rids, weights)[0]
            t = rng.uniform(SEG, self.recs[rid]["seconds"] - SEG)
            sid = rng.choice(ids)
            st = rng.uniform(SEG, self.cat[sid]["seconds"] - SEG)
            sp = 1 + rng.choice([0, 0, 0, rng.uniform(-0.08, 0.08)])
            fb, ff, _, _ = seed_test(self.rec_audio[rid], t, self.refs.get(sid), st, sp)
            if fb > 0 or ff > 0:
                vals.append(fb)
        vals.sort()
        return vals

    def follow(self, rid, sid, t_seed, anchor, speed, seen=None):
        """Walk from t_seed both ways while the song passes (song time = anchor + speed * t at the seed, then carried
        from the last passing segment's measured place and speed); returns {moment: (fb, ff, song time, speed)} for
        passing moments. A miss of up to 7 moments in a row (14 s: talk over a quiet passage) is bridged."""
        rec = self.rec_audio[rid]; ref = self.refs.get(sid)
        if ref is None or len(ref) < SR:
            return {}
        dur = self.recs[rid]["seconds"]; sdur = self.cat[sid]["seconds"]
        got = {}
        m0 = round(t_seed / STEP) * STEP
        for direction in (1, -1):
            m = m0 if direction == 1 else m0 - STEP
            misses = 0
            cur_m, cur_st, sp = m0, anchor + speed * m0, speed
            if direction == -1 and m0 in got:
                cur_st, sp = got[m0][2], got[m0][3]
            while SEG / 2 <= m <= dur - SEG / 2:
                st = cur_st + sp * (m - cur_m)
                if st < -SEG or st > sdur + SEG:
                    break
                if seen is not None and (m, sid) in seen:
                    break
                fb, ff, lag, sp2 = (seed_test if not got else test_segment)(rec, m, ref, st, sp)
                if fb >= self.mark:
                    st2 = st + sp * lag
                    got[m] = (fb, ff, st2, sp2)
                    cur_m, cur_st = m, st2
                    sp = 0.7 * sp + 0.3 * sp2
                    misses = 0
                else:
                    misses += 1
                    if not got and misses > 1:
                        return {}
                    if misses > 7:
                        break
                m += direction * STEP
        return got

    def build(self, result_files, subset_ids, jobs=1):
        cache = os.path.join(self.work, "null.json")
        if os.path.exists(cache):
            mark_vals = json.load(open(cache))
        else:
            mark_vals = self.null()
            json.dump(mark_vals, open(cache, "w"))
        self.mark = mark_vals[int(0.999 * (len(mark_vals) - 1))]
        print("null: n %d, median %.4f, 99th %.4f, 99.9th (pass mark) %.4f, max %.4f" % (
            len(mark_vals), mark_vals[len(mark_vals) // 2], mark_vals[int(0.99 * (len(mark_vals) - 1))], self.mark, mark_vals[-1]),
            file=sys.stderr)
        # (a) the matcher's candidates, from every results file: clusters of windows on one song and one place.
        cands = collections.defaultdict(list)
        for path in result_files:
            for q in read_results(path).values():
                if q["rid"] not in self.recs:
                    continue
                for e in (q["best"], q["second"]):
                    sid, score, matched, off, tempo, pitch, conf = e
                    if sid == "-" or sid not in self.cat:
                        continue
                    start = q["t"] - q["L"]
                    anchor = off - tempo * start
                    cands[(q["rid"], sid, round(anchor / 2))].append((start, tempo, pitch, conf, anchor, q["t"]))
        seeds = []
        for (rid, sid, _), v in cands.items():
            # Agreement means windows ending at different moments (the four lengths ending at one moment share audio).
            # (or one window above two thirds of the threshold: a song seen but not accepted)
            if len({c[5] for c in v}) >= 3 or max(c[3] for c in v) >= 2.0:
                v.sort()
                tempo = statistics.median(c[1] for c in v); pitch = statistics.median(c[2] for c in v)
                anchor = statistics.median(c[4] for c in v)
                # The waveform test plays the song back resampled: exact for a turntable or a deck at its own speed;
                # for a key-held deck off zero it is only near, and such a song may fail to verify.
                # Start where the evidence is: the middle of the shortest window that is nearly as sure as the surest.
                top = max(c[3] for c in v)
                pick = min((c for c in v if c[3] >= 0.8 * top), key=lambda c: (c[5] - c[0], -c[3]))
                seeds.append(dict(rid=rid, sid=sid, t=(pick[0] + pick[5]) / 2, tempo=tempo, pitch=pitch, n=len(v), src="matcher",
                                  anchor=anchor))
        print("matcher candidates: %d clusters" % len(seeds), file=sys.stderr)
        # (b) the booth's log: songs by title and artist, place by search.
        index = collections.defaultdict(list)
        for k, v in self.cat.items():
            index[(norm(v["title"]), norm(v["artist"]))].append(k)
        unmatched_log = 0
        for rid, r in self.recs.items():
            for e in r["entries"]:
                ids = log_ids(e, index)
                if not ids:
                    unmatched_log += 1
                    continue
                pitch = 1 + float(e.get("pitch", 0)) / 100
                for sid in ids[:8]:
                    for dt in (0, -4, 4):
                        seeds.append(dict(rid=rid, sid=sid, t=float(e["at"]) + dt, entry=id(e), tempo=pitch,
                                          pitch=pitch if e.get("pitchKind") == "vinyl" else 1.0, n=0, src="log", anchor=None))
        print("log entries without a catalogue song: %d" % unmatched_log, file=sys.stderr)

        hyps = []
        seen = set()
        done_entries = set()
        for i, s in enumerate(sorted(seeds, key=lambda s: (s["src"] != "matcher", -s["n"]))):
            if i % 500 == 0:
                print("  seed %d of %d, %d verified" % (i, len(seeds), len(hyps)), file=sys.stderr)
            if s["src"] == "log":
                # a log entry already explained near its time (by any of its catalogue songs) needs no search
                if s["entry"] in done_entries or any((round(s["t"] / STEP) * STEP + k * STEP, s["sid"]) in seen for k in range(-3, 4)):
                    done_entries.add(s["entry"])
                    continue
            if s["src"] == "log" or s["anchor"] is None:
                found = self.place(s)
                if found is None:
                    continue
                anchor, speed = found
            else:
                anchor, speed = s["anchor"], s["tempo"]
            if (round(s["t"] / STEP) * STEP, s["sid"]) in seen:
                continue
            got = self.follow(s["rid"], s["sid"], s["t"], anchor, speed)
            if len(got) < 1:
                continue
            for m in got:
                seen.add((m, s["sid"]))
            if s["src"] == "log":
                done_entries.add(s["entry"])
            hyps.append(dict(rid=s["rid"], sid=s["sid"], anchor=anchor, speed=speed, src=s["src"],
                             moments={("%.0f" % m): list(v) for m, v in got.items()}))
        self.hyps = hyps
        # (c) unexplained stretches with sound and a beat: search the subset at the deck's own speed.
        feats = self.features()
        explained = {(h["rid"], float(m)) for h in hyps for m in h["moments"]}
        probes = []
        for rid, fs in feats.items():
            last = -1e9
            for m, (lvl, beat) in sorted(fs.items()):
                if (rid, m) in explained or lvl < self.floor or beat < self.beat_mark:
                    continue
                if m - last >= 60:
                    probes.append((rid, m)); last = m
        print("search probes: %d" % len(probes), file=sys.stderr)
        for k, (rid, m) in enumerate(probes):
            for sid, anchor, sp in self.search(rid, m, subset_ids):
                if (m, sid) in seen:
                    continue
                got = self.follow(rid, sid, m + SEG / 2, anchor, sp)
                if len(got) >= 2:
                    for mm in got:
                        seen.add((mm, sid))
                    hyps.append(dict(rid=rid, sid=sid, anchor=anchor, speed=sp, src="search",
                                     moments={("%.0f" % mm): list(v) for mm, v in got.items()}))
            if k % 20 == 0:
                print("  probe %d of %d" % (k, len(probes)), file=sys.stderr)
        groups, same = self.copies(hyps)
        json.dump(dict(mark=self.mark, null=mark_vals[::10], floor=self.floor, beat_mark=self.beat_mark, hyps=hyps,
                       groups=groups, same=same, features={rid: {("%.0f" % m): v for m, v in fs.items()} for rid, fs in feats.items()}),
                  open(os.path.join(self.work, "truth.json"), "w"))

    def place(self, s):
        """Where in the song the recording is at s["t"], by phase-transform correlation of 6 s of the recording
        before t against the whole song, at the candidate's speed (vinyl-style when pitch moved, else as recorded)."""
        rec = self.rec_audio[s["rid"]]; ref = self.refs.get(s["sid"])
        if ref is None or len(ref) < SR * 10:
            return None
        speed = s["tempo"] if abs(s["pitch"] - 1) > 0.004 else 1.0
        t = max(SEG / 2, s["t"] - SEG / 2)
        y = chunk(rec, int((t - SEG / 2) * SR), int(SEG * SR))
        # First the place, roughly, from the onset envelopes (10 ms steps; insensitive to the small difference between
        # the recorder's clock and the deck's); the five best places are then tested at the full rate.
        ey = envelope(y)
        er = self.envelope(s["sid"])
        if abs(speed - 1) > 1e-6:
            er = np.interp(np.arange(0, len(er) - 1, speed), np.arange(len(er)), er)
        if len(er) <= len(ey) + 2:
            return None
        ey = (ey - ey.mean()) / (ey.std() + 1e-9)
        nn = 1 << int(math.ceil(math.log2(len(er) + len(ey))))
        r = np.fft.irfft(np.fft.rfft(er, nn) * np.conj(np.fft.rfft(ey, nn)), nn)[:len(er) - len(ey) + 1]
        cs = np.concatenate([[0], np.cumsum(er)]); cs2 = np.concatenate([[0], np.cumsum(er * er)])
        L = len(ey)
        mu = (cs[L:] - cs[:-L]) / L; sd = np.sqrt(np.maximum((cs2[L:] - cs2[:-L]) / L - mu * mu, 1e-12))
        ncc = r / (L * sd)
        picks = []
        order = np.argsort(-ncc)
        for k in order:
            if all(abs(int(k) - p) > 50 for p in picks):
                picks.append(int(k))
            if len(picks) >= s.get("picks", 5):
                break
        if s.get("rough_only"):
            return float(ncc[picks[0]])
        best = None
        for k in picks:
            song_t = k * EHOP * speed / SR + speed * SEG / 2
            fb, _, lag, sp = seed_test(rec, t, ref, song_t, speed)
            if best is None or fb > best[0]:
                best = (fb, song_t + speed * lag - sp * t, sp)
        return (best[1], best[2]) if best and best[0] >= self.mark else None

    def envelope(self, sid):
        if not hasattr(self, "envs"):
            self.envs = {}
        if sid not in self.envs:
            if len(self.envs) > 200:
                self.envs.clear()
            self.envs[sid] = envelope(self.refs.get(sid))
        return self.envs[sid]

    def search(self, rid, m, subset):
        """The subset's songs ranked by how well their onset envelope fits the recording at m; the best three are
        tested at their two best places."""
        rank = []
        for sid in subset:
            r = self.place(dict(rid=rid, sid=sid, t=m + SEG / 2, tempo=1.0, pitch=1.0, rough_only=True))
            if r is not None:
                rank.append((r, sid))
        rank.sort(reverse=True)
        out = []
        for _, sid in rank[:3]:
            found = self.place(dict(rid=rid, sid=sid, t=m + SEG / 2, tempo=1.0, pitch=1.0, picks=2))
            if found:
                out.append((sid, found[0], found[1]))
        return out

    def features(self):
        """Per moment: level (dBFS of the 6 s segment) and beat strength (the strongest normalised autocorrelation of
        the onset envelope at 60 to 180 beats a minute)."""
        out = {}
        levels = []
        for rid, rec in self.rec_audio.items():
            fs = {}
            m = STEP * math.ceil(SEG / 2 / STEP)
            while m <= self.recs[rid]["seconds"] - SEG / 2:
                y = chunk(rec, int((m - SEG / 2) * SR), int(SEG * SR)) / 32768
                lvl = 10 * math.log10(np.mean(y * y) + 1e-12)
                k = 1 + (len(y) - 1024) // 256
                idx = np.arange(1024)[None, :] + 256 * np.arange(k)[:, None]
                spec = np.abs(np.fft.rfft(y[idx] * np.hanning(1024), axis=1))
                flux = np.maximum(0, np.diff(np.log1p(1000 * spec), axis=0)).sum(axis=1)
                flux = flux - flux.mean()
                ac = np.correlate(flux, flux, "full")[len(flux) - 1:]
                lo, hi = int(0.333 * SR / 256), int(1.0 * SR / 256)
                beat = float(np.max(ac[lo:hi]) / (ac[0] + 1e-12))
                fs[m] = (lvl, beat)
                m += STEP
            out[rid] = fs
        explained = {(h["rid"], float(m)) for h in self.hyps for m in h["moments"]}
        # Silence: 30 dB under the median level of the moments with a verified song (a fixed rule, stated in the letter).
        levels = [v[0] for rid, fs in out.items() for m, v in fs.items() if (rid, m) in explained]
        self.floor = (statistics.median(levels) if levels else -40) - 30
        beats = sorted(v[1] for rid, fs in out.items() for m, v in fs.items() if (rid, m) in explained)
        # A steady beat: at or above what 19 in 20 moments with a verified song have.
        self.beat_mark = beats[len(beats) // 20] if beats else 0.3
        return out

    def copies(self, hyps):
        """Union hypotheses that are one recording: same song, or co-passing with references coherent with each other."""
        parent = list(range(len(hyps)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]; i = parent[i]
            return i
        bysong = {}
        for i, h in enumerate(hyps):
            key = (h["rid"], h["sid"])
            if key in bysong:
                parent[find(i)] = find(bysong[key])
            else:
                bysong[key] = i
        at = collections.defaultdict(list)
        for i, h in enumerate(hyps):
            for m in h["moments"]:
                at[(h["rid"], m)].append(i)
        pairs = collections.Counter()
        for k, v in at.items():
            for x in range(len(v)):
                for y in range(x + 1, len(v)):
                    if hyps[v[x]]["sid"] != hyps[v[y]]["sid"]:
                        pairs[(v[x], v[y])] += 1
        same = []
        for (i, j), n in pairs.items():
            if n < 2:
                continue
            hi, hj = hyps[i], hyps[j]
            common = sorted(set(hi["moments"]) & set(hj["moments"]), key=float)
            m = common[len(common) // 2]
            ri, rj = self.refs.get(hi["sid"]), self.refs.get(hj["sid"])
            n_ = int(SEG * SR); ml = int(LAG * SR)
            sti, spi = hi["moments"][m][2], hi["moments"][m][3]
            stj, spj = hj["moments"][m][2], hj["moments"][m][3]
            xi = ref_at(ri, sti - spi * SEG / 2, spi, n_, 0)[:n_]
            xj = ref_at(rj, stj - spj * SEG / 2, spj, n_, LAG)
            lag, _ = best_lag(xi, xj, ml)
            fb, _ = coherence(xi, xj[ml + lag:ml + lag + n_])
            if fb >= 0.5:
                same.append((i, j))
        # Groups: one song in one recording. Copies (same audio under two catalogue entries, for instance a song and
        # the pre-mixed disc that holds it) are kept as pairs and joined moment by moment by the report, so that a
        # mix does not join every song it holds into one.
        groups = collections.defaultdict(list)
        for i in range(len(hyps)):
            groups[find(i)].append(i)
        return [v for v in groups.values()], same


def truth(a):
    subset = []
    if a.subset:
        subset = [l.strip() for l in open(a.subset) if l.strip()]
    t = Truth(a.work, a.threshold)
    if a.only:
        keep = set(a.only.split(","))
        t.recs = {k: v for k, v in t.recs.items() if k in keep}
        t.rec_audio = {k: v for k, v in t.rec_audio.items() if k in keep}
    t.hyps = []
    t.build(a.results, subset, a.jobs)


# ---------------------------------------------------------------- report
def pct(a, b):
    return "-" if not b else "%.1f" % (100.0 * a / b)


def quant(v, q):
    if not v:
        return float("nan")
    v = sorted(v)
    return v[min(len(v) - 1, int(q * (len(v) - 1) + 0.5))]


class Key:
    """The answer key read back: per (recording, moment) its state and songs."""
    def __init__(self, work, mix_ids=()):
        tr = json.load(open(os.path.join(work, "truth.json")))
        self.tr = tr
        self.recs = {r["rid"]: r for r in json.load(open(os.path.join(work, "recordings.json"))) if r["used"]}
        self.hyps = tr["hyps"]
        self.group_of = {}
        sids0 = {}
        for g, members in enumerate(tr["groups"]):
            for i in members:
                self.group_of[i] = g
            sids0[g] = {self.hyps[i]["sid"] for i in members}
        mixg = {g for g, ids in sids0.items() if ids & set(mix_ids)}
        at0 = collections.defaultdict(dict)       # (rid, m) -> {group: (fb, ff, hyp index)}
        for i, h in enumerate(self.hyps):
            g = self.group_of[i]
            for m, v in h["moments"].items():
                d = at0[(h["rid"], float(m))]
                if g not in d or v[0] > d[g][0]:
                    d[g] = (v[0], v[1], i)
        same = collections.defaultdict(set)
        for i, j in tr.get("same", []):
            gi, gj = self.group_of[i], self.group_of[j]
            same[gi].add(gj); same[gj].add(gi)
        # each group's runs (gaps up to 10 s bridged): how long it is heard around each moment
        runlen = {}
        byg = collections.defaultdict(list)
        for (rid, m), d in at0.items():
            for g in d:
                byg[g].append(m)
        for g, ms in byg.items():
            ms.sort(); cur = [ms[0]]
            for m in ms[1:] + [None]:
                if m is not None and m - cur[-1] <= 10:
                    cur.append(m); continue
                for x in cur:
                    runlen[(g, x)] = cur[-1] - cur[0] + STEP
                if m is not None:
                    cur = [m]
        # Per moment: the groups heard, joined where they are the same audio (copies, or a song and the mix that holds
        # it), each joined set led by its song (not the mix) when there is one. It counts as the pre-mixed disc when
        # the mix is among them and is heard for at least 30 s longer than the song around this moment (the mix
        # carries on past the song's ends), else as the song played live.
        self.at = {}
        self.sids = collections.defaultdict(set)
        self.kinds = {}
        self.mix_groups = mixg
        for key, d in at0.items():
            left = set(d); out = {}
            while left:
                g0 = left.pop(); comp = {g0}; stack = [g0]
                while stack:
                    x = stack.pop()
                    for y in same[x]:
                        if y in left:
                            left.discard(y); comp.add(y); stack.append(y)
                songs = [g for g in comp if g not in mixg]; mixes = [g for g in comp if g in mixg]
                lead = max(songs or mixes, key=lambda g: d[g][0])
                out[lead] = d[lead]
                for g in comp:
                    self.sids[lead] |= sids0[g]
                m = key[1]
                if mixes and (not songs or max(runlen[(g, m)] for g in mixes) > runlen[(lead, m)] + 30):
                    self.kinds[(key[0], m, lead)] = "mix"
                else:
                    self.kinds[(key[0], m, lead)] = "live"
            self.at[key] = out
        self.mix = set()      # kept for older callers: no group is "the mix" as a whole
        # Files with the same title and artist and a length within a second are copies of one recording too, whether
        # or not the key happened to follow each of them.
        cat = json.load(open(os.path.join(work, "catalogue.json")))
        same_name = collections.defaultdict(list)
        for k, v in cat.items():
            same_name[(norm(v["title"]), norm(v["artist"]))].append(k)
        for g, ids in self.sids.items():
            more = set()
            for k in ids:
                v = cat.get(k)
                if v:
                    more |= {o for o in same_name[(norm(v["title"]), norm(v["artist"]))] if abs(cat[o]["seconds"] - v["seconds"]) < 1}
            ids |= more
        self.feat = {rid: {float(m): v for m, v in fs.items()} for rid, fs in tr["features"].items()}
        self.floor, self.beat_mark = tr["floor"], tr["beat_mark"]
        self.state = {}
        for rid, fs in self.feat.items():
            for m, (lvl, beat) in fs.items():
                d = self.at.get((rid, m), {})
                if len(d) >= 2:
                    st = "blend"
                elif len(d) == 1:
                    st = "song"
                elif lvl < self.floor:
                    st = "silence"
                elif beat < self.beat_mark:
                    st = "talk"
                else:
                    st = "unknown"
                self.state[(rid, m)] = st
        self.stretches = self.make_stretches()

    def part(self, rid, m=None):
        return self.recs[rid]["part"]

    def kind(self, rid, m, g=None):
        """'mix' when the sound at the moment is the pre-mixed disc playing, else 'live'."""
        d = self.at.get((rid, m), {})
        ks = [self.kinds.get((rid, m, x)) for x in ([g] if g is not None else d)]
        return "mix" if "mix" in ks else "live"

    def make_stretches(self):
        """Runs of one song (group) in a recording, bridging gaps up to 30 s (talk over a quiet passage is not a new
        play of the song)."""
        runs = []
        bygroup = collections.defaultdict(list)
        for (rid, m), d in self.at.items():
            for g in d:
                bygroup[(rid, g)].append(m)
        for (rid, g), ms in bygroup.items():
            ms.sort()
            cur = [ms[0]]
            for m in ms[1:]:
                if m - cur[-1] <= 30:
                    cur.append(m)
                else:
                    runs.append((rid, g, cur)); cur = [m]
            runs.append((rid, g, cur))
        out = []
        for rid, g, ms in runs:
            nmix = sum(self.kinds.get((rid, m, g)) == "mix" for m in ms)
            out.append(dict(rid=rid, g=g, start=ms[0] - SEG / 2, end=ms[-1] + SEG / 2, moments=ms,
                            kind="mix" if 2 * nmix > len(ms) else "live", part=self.recs[rid]["part"],
                            mix_only=g in self.mix_groups))
        return out

    def window(self, rid, t, L):
        """The key's reading of the window [t - L, t]: ('song', group) when one song alone covers it, ('blend', groups),
        ('quiet', None) for silence or talk only, ('mixed', None) otherwise (a change of state inside the window)."""
        lo = STEP * math.ceil((t - L) / STEP); ms = []
        m = lo
        while m <= t + 1e-9:
            ms.append(m); m += STEP
        if not ms:
            ms = [STEP * round((t - L / 2) / STEP)]
        states = [self.state.get((rid, m)) for m in ms]
        groups = set()
        for m in ms:
            groups |= set(self.at.get((rid, m), {}))
        if all(s == "song" for s in states) and len(groups) == 1:
            return "song", groups
        if all(s in ("song", "blend") for s in states) and len(groups) >= 2 and any(s == "blend" for s in states):
            return "blend", groups
        if all(s in ("silence", "talk") for s in states):
            return "quiet", set()
        if all(s == "unknown" for s in states):
            return "unknown", set()
        return "mixed", groups

    def snr(self, rid, ms, g):
        v = [self.at[(rid, m)][g] for m in ms if g in self.at.get((rid, m), {})]
        if not v:
            return None
        return statistics.median(db(x[1]) for x in v), statistics.median(db(x[0]) for x in v)


def report(a):
    work = a.work
    mix_ids = [l.strip() for l in open(a.mix)] if a.mix else []
    key = Key(work, mix_ids)
    thr = a.threshold
    out = []
    w = out.append
    tr = key.tr
    w("# Real-room test: results\n")
    w("Pass mark of the waveform check (99.9th percentile of the null): %.4f of the band's power; silence floor %.1f dBFS; "
      "steady-beat mark %.3f.\n" % (tr["mark"], key.floor, key.beat_mark))
    # ---- the recording, by state
    w("## The recordings, by what the key says (minutes)\n")
    w("| part | kind | hours recorded | song | blend | talk / no beat | silence | unknown |")
    w("|---|---|---|---|---|---|---|---|")
    tally = collections.defaultdict(collections.Counter)
    for (rid, m), st in key.state.items():
        part = key.recs[rid]["part"]
        k = key.kind(rid, m) if st in ("song", "blend") else "-"
        tally[(part, "all")][st] += STEP
        if k != "-":
            tally[(part, k)][st] += STEP
    for (part, k), c in sorted(tally.items()):
        tot = sum(c.values())
        w("| %s | %s | %.2f | %.0f | %.0f | %.0f | %.0f | %.0f |" % (part, k, tot / 3600, c["song"] / 60, c["blend"] / 60, c["talk"] / 60,
                                                             c["silence"] / 60, c["unknown"] / 60))
    w("")
    w("Sources of the key's songs (verified stretches, by first candidate source): " + ", ".join(
        "%s %d" % (k, v) for k, v in collections.Counter(h["src"] for h in key.hyps).items()) + ".\n")
    w("Groups (one recording) holding more than one catalogue entry: %d of %d.\n" % (
        sum(1 for g in key.sids.values() if len(g) > 1), len(key.sids)))

    results = []
    for spec in a.results:
        name, path = spec.split("=", 1)
        results.append((name, read_results(path)))
    LS = sorted({q["L"] for _, R in results for q in R.values()})

    cur = {"ids": None}
    cat_ids = {}
    for spec in a.catalogue_ids or []:
        n_, f_ = spec.split("=", 1)
        cat_ids[n_] = {l.strip() for l in open(f_) if l.strip()}

    def judge(q):
        b = q["best"]
        named = b[0] != "-" and b[6] >= thr
        kind, groups = key.window(q["rid"], q["t"], q["L"])
        right = named and any(b[0] in key.sids[g] for g in groups)
        if kind == "song" and cur["ids"] is not None and not (key.sids[next(iter(groups))] & cur["ids"]):
            kind = "song outside this catalogue"
        return kind, groups, named, right

    titles = {k: norm(v["title"]).split()[:3] for k, v in json.load(open(os.path.join(work, "catalogue.json"))).items()}

    def wrong_kind(b, groups):
        if b in mix_ids:
            return "the pre-mixed disc's track"
        ok = set().union(*(key.sids[g] for g in groups)) if groups else set()
        if b in titles and any(titles.get(o) == titles[b] for o in ok):
            return "another version or copy of the playing song (same title)"
        if b not in titles:
            return "a song from the added music (never played)"
        return "another song"

    for name, R in results:
        cur["ids"] = cat_ids.get(name)
        w("## Catalogue: %s\n" % name)
        if cur["ids"] is not None:
            outside = sum(1 for q in R.values() if q["L"] == max(LS) and key.recs[q["rid"]]["part"] == "set" and judge(q)[0] == "song outside this catalogue")
            w("One-song windows whose song is not in this catalogue are left out of its tables (%d of the set's %g s windows).\n" % (outside, max(LS)))
        wr = collections.defaultdict(collections.Counter)
        for q in R.values():
            if key.recs[q["rid"]]["part"] != "set":
                continue
            kind, groups, named, right = judge(q)
            if kind in ("song", "blend") and named and not right:
                wr[wrong_kind(q["best"][0], groups)][q["L"]] += 1
        if wr:
            w("Wrong names in the set's one-song and blend windows, by what was named (windows; 3 / 5 / 8 / 12 s): " + "; ".join(
                "%s %s" % (k, " / ".join(str(v[L]) for L in LS)) for k, v in sorted(wr.items())) + ".\n")
        ms = collections.defaultdict(list); fp = collections.defaultdict(list)
        for q in R.values():
            ms[q["L"]].append(q["ms"]); fp[q["L"]].append(q["fpms"])
        w("Query time on this machine, ms (fingerprint the window / match), median and 95th percentile: " + "; ".join(
            "%g s: %.1f / %.1f and %.1f / %.1f" % (L, quant(fp[L], .5), quant(fp[L], .95), quant(ms[L], .5), quant(ms[L], .95)) for L in LS) + ".\n")
        for part in ("set", "before"):
            for kind_sel in ("live", "mix", "all"):
                rows = collections.defaultdict(collections.Counter)
                for q in R.values():
                    if key.recs[q["rid"]]["part"] != part:
                        continue
                    kind, groups, named, right = judge(q)
                    if kind == "song":
                        g = next(iter(groups))
                        k = key.kind(q["rid"], STEP * round((q["t"] - q["L"] / 2) / STEP), g)
                        if kind_sel != "all" and k != kind_sel:
                            continue
                    elif kind_sel != "all":
                        continue
                    c = rows[q["L"]]
                    c[kind] += 1
                    if named:
                        c[kind + ":named"] += 1
                        c[kind + (":right" if right else ":wrong")] += 1
                if not rows:
                    continue
                w("### %s, %s: windows by the key's reading; right / wrong / none, percent\n" % (part, kind_sel))
                w("| length | one song: n | right | wrong | none | blend: n | one of the two | other | quiet (talk, silence): n | named anyway | unknown: n | named |")
                w("|---|---|---|---|---|---|---|---|---|---|---|---|")
                for L in LS:
                    c = rows[L]
                    w("| %g s | %d | %s | %s | %s | %d | %s | %s | %d | %s | %d | %s |" % (
                        L, c["song"], pct(c["song:right"], c["song"]), pct(c["song:wrong"], c["song"]),
                        pct(c["song"] - c["song:named"], c["song"]), c["blend"], pct(c["blend:right"], c["blend"]),
                        pct(c["blend:wrong"], c["blend"]), c["quiet"], pct(c["quiet:named"], c["quiet"]), c["unknown"],
                        pct(c["unknown:named"], c["unknown"])))
                w("")
        # ---- the pre-mixed disc: what is named while it plays
        if mix_ids:
            mx = collections.defaultdict(collections.Counter)
            for q in R.values():
                if key.recs[q["rid"]]["part"] != "set":
                    continue
                kind, groups, named, right = judge(q)
                if kind != "song":
                    continue
                g = next(iter(groups))
                if key.kind(q["rid"], STEP * round((q["t"] - q["L"] / 2) / STEP), g) != "mix":
                    continue
                c = mx[q["L"]]; c["n"] += 1
                if named:
                    b = q["best"][0]
                    c["the mix's own track" if b in mix_ids else ("the song inside it" if right else "a wrong song")] += 1
            if mx:
                w("### While the pre-mixed disc plays (set, one-song windows): what is named, percent\n")
                w("| length | windows | the mix's own track | the song inside it | a wrong song | none |")
                w("|---|---|---|---|---|---|")
                for L in LS:
                    c = mx[L]
                    named_n = c["the mix's own track"] + c["the song inside it"] + c["a wrong song"]
                    w("| %g s | %d | %s | %s | %s | %s |" % (L, c["n"], pct(c["the mix's own track"], c["n"]), pct(c["the song inside it"], c["n"]),
                                                       pct(c["a wrong song"], c["n"]), pct(c["n"] - named_n, c["n"])))
                w("")
        # ---- the room's level against the result
        w("### Right, percent of one-song windows, by the room (music over everything else, dB, full band), set only\n")
        bins = [(10, 99, "over 10"), (5, 10, "5 to 10"), (0, 5, "0 to 5"), (-5, 0, "-5 to 0"), (-99, -5, "under -5")]
        w("| music over the rest | " + " | ".join("%g s (n)" % L for L in LS) + " |")
        w("|---|" + "---|" * len(LS))
        acc = collections.defaultdict(collections.Counter)
        for q in R.values():
            if key.recs[q["rid"]]["part"] != "set":
                continue
            kind, groups, named, right = judge(q)
            if kind != "song":
                continue
            g = next(iter(groups))
            lo = STEP * math.ceil((q["t"] - q["L"]) / STEP)
            msl = [m for m in np.arange(lo, q["t"] + 1e-9, STEP)] or [lo]
            v = key.snr(q["rid"], msl, g)
            if v is None:
                continue
            for b in bins:
                if b[0] <= v[0] < b[1]:
                    acc[(b[2], q["L"])]["n"] += 1
                    acc[(b[2], q["L"])]["r"] += right
        for b in bins:
            w("| %s | " % b[2] + " | ".join("%s (%d)" % (pct(acc[(b[2], L)]["r"], acc[(b[2], L)]["n"]), acc[(b[2], L)]["n"]) for L in LS) + " |")
        w("")
        # ---- time to first name, per stretch
        w("### Time from a song's start (first moment the key hears it) to the first right name, set only, stretches of 30 s or more\n")
        byrid = collections.defaultdict(list)
        for q in R.values():
            byrid[q["rid"]].append(q)
        for v in byrid.values():
            v.sort(key=lambda q: q["t"])
        w("| kind | length | stretches | named | median s | 90th s | slowest s | never named |")
        w("|---|---|---|---|---|---|---|---|")
        firsts = {}
        for kind_sel in ("live", "mix"):
            for L in LS + ["any"]:
                d = []; never = 0; n = 0
                for s in key.stretches:
                    if s["part"] != "set" or s["kind"] != kind_sel or s["end"] - s["start"] < 30:
                        continue
                    if cur["ids"] is not None and not (key.sids[s["g"]] & cur["ids"]):
                        continue
                    n += 1
                    hit = None
                    for q in byrid[s["rid"]]:
                        if q["t"] < s["start"] or q["t"] > s["end"] + 4:
                            continue
                        if L != "any" and q["L"] != L:
                            continue
                        b = q["best"]
                        if b[6] >= thr and b[0] in key.sids[s["g"]] and q["t"] - q["L"] >= s["start"] - 6:
                            hit = q["t"] - s["start"]; break
                    firsts[(s["rid"], s["g"], s["start"], L)] = hit
                    if hit is None:
                        never += 1
                    else:
                        d.append(hit)
                w("| %s | %s | %d | %d | %.0f | %.0f | %.0f | %d |" % (kind_sel, L if L == "any" else "%g s" % L, n, len(d),
                                                                       quant(d, .5), quant(d, .9), max(d) if d else float("nan"), never))
        w("")
        # ---- named while nothing verified: isolated or a steady run
        w("### Names given when the key has no song, set only (per length)\n")
        w("| length | quiet windows named | unknown windows named | of those named in a steady run (3+ windows, one place) |")
        w("|---|---|---|---|")
        for L in LS:
            qn = un = steady = 0
            for rid, v in byrid.items():
                if key.recs[rid]["part"] != "set":
                    continue
                v = [q for q in v if q["L"] == L]
                for i, q in enumerate(v):
                    kind, groups, named, right = judge(q)
                    if not named or kind not in ("quiet", "unknown"):
                        continue
                    if kind == "quiet":
                        qn += 1
                    else:
                        un += 1
                    b = q["best"]; anc = b[3] - b[4] * (q["t"] - q["L"])
                    near = [p for p in v[max(0, i - 3):i + 4] if p is not q and p["best"][0] == b[0] and p["best"][6] >= thr
                            and abs(p["best"][3] - p["best"][4] * (p["t"] - p["L"]) - anc) < 2]
                    steady += len(near) >= 2
            w("| %g s | %d | %d | %d |" % (L, qn, un, steady))
        w("")
        # ---- the fader
        w("### The fader as read on right answers (12 s windows), per stretch of 30 s or more, set only\n")
        reads = []
        for s in key.stretches:
            if s["part"] != "set" or s["end"] - s["start"] < 30:
                continue
            if cur["ids"] is not None and not (key.sids[s["g"]] & cur["ids"]):
                continue
            v = [q for q in byrid[s["rid"]] if q["L"] == max(LS) and s["start"] <= q["t"] - q["L"] and q["t"] <= s["end"]
                 and q["best"][6] >= thr and q["best"][0] in key.sids[s["g"]]]
            if len(v) < 3:
                continue
            sp = [100 * (q["best"][4] - 1) for q in v]; pi = [100 * (q["best"][5] - 1) for q in v]
            reads.append((s, statistics.median(sp), quant(sp, .75) - quant(sp, .25), statistics.median(pi), len(v)))
        if reads:
            med = [r[1] for r in reads]
            w("Stretches read: %d (%s live, %s pre-mixed). Fader reading, median per stretch: %s. Spread within a stretch "
              "(between the 25th and 75th percentile of its windows), median %.3f points, 90th %.3f. Stretches with |reading| "
              "over 0.5 %%: %d; over 2 %%: %d; over 4 %%: %d. Key held (pitch unmoved while tempo moved by 1 %% or more): %d.\n" % (
                len(reads), sum(r[0]["kind"] == "live" for r in reads), sum(r[0]["kind"] == "mix" for r in reads),
                ", ".join("%+.2f" % x for x in sorted(med)) if len(med) <= 12 else "from %+.2f to %+.2f, median %+.2f" % (min(med), max(med), statistics.median(med)),
                quant([r[2] for r in reads], .5), quant([r[2] for r in reads], .9),
                sum(abs(x) > 0.5 for x in med), sum(abs(x) > 2 for x in med), sum(abs(x) > 4 for x in med),
                sum(abs(r[1]) >= 1 and abs(r[3]) < 0.3 for r in reads)))
        # ---- misses by likely cause
        w("### One-song windows not named (set), by likely cause, first that applies\n")
        causes = collections.defaultdict(collections.Counter)
        starts = {}
        for s in key.stretches:
            for m in s["moments"]:
                starts[(s["rid"], s["g"], m)] = s
        songlvl = [key.feat[rid][m][0] for (rid, m), st in key.state.items() if st == "song"]
        quiet_lvl = statistics.median(songlvl) - 15 if songlvl else -60
        for q in R.values():
            if key.recs[q["rid"]]["part"] != "set":
                continue
            kind, groups, named, right = judge(q)
            if kind != "song" or right:
                continue
            g = next(iter(groups)); rid = q["rid"]
            mm = STEP * round((q["t"] - q["L"] / 2) / STEP)
            s = starts.get((rid, g, mm)) or next((s for s in key.stretches if s["rid"] == rid and s["g"] == g and s["start"] <= q["t"] <= s["end"] + 4), None)
            lvl = key.feat[rid].get(mm, (0, 0))[0]
            v = key.snr(rid, [mm], g)
            near_blend = any(key.state.get((rid, mm + k * STEP)) == "blend" for k in range(-5, 6))
            h = key.hyps[key.at[(rid, mm)][g][2]] if g in key.at.get((rid, mm), {}) else None
            if named:
                c = "named another song"
            elif lvl < quiet_lvl:
                c = "quiet passage (15 dB or more under the songs' median level)"
            elif near_blend:
                c = "within 10 s of a blend"
            elif v is not None and v[0] < 0:
                c = "music under the rest (talk, singing, crowd)"
            elif h is not None and abs(h["speed"] - 1) > 0.04:
                c = "deck beyond 4 %"
            elif s is not None and q["t"] - s["start"] < 20:
                c = "the song's first 20 s"
            else:
                c = "none of these"
            causes[q["L"]][c] += 1
        names = sorted({c for v in causes.values() for c in v})
        w("| cause | " + " | ".join("%g s" % L for L in LS) + " |")
        w("|---|" + "---|" * len(LS))
        for c in names:
            w("| %s | " % c + " | ".join(str(causes[L][c]) for L in LS) + " |")
        w("")
        key_firsts = firsts
        if name == results[0][0]:
            first_results = (R, key_firsts, byrid)
    # ---- the room's level
    w("## How loud the room was: music over everything else at the microphone, dB, one-song moments\n")
    w("| part | kind | moments | full band: 10th / 25th / median / 75th / 90th | fingerprint band (300-3600 Hz): median | over 10 dB | 5 to 10 | 0 to 5 | -5 to 0 | under -5 |")
    w("|---|---|---|---|---|---|---|---|---|---|")
    for part in ("set", "before"):
        for kind_sel in ("live", "mix", "all"):
            fv = []; bv = []
            for (rid, m), d in key.at.items():
                if len(d) != 1 or key.recs[rid]["part"] != part:
                    continue
                g = next(iter(d))
                k = key.kind(rid, m, g)
                if kind_sel != "all" and k != kind_sel:
                    continue
                fv.append(db(d[g][1])); bv.append(db(d[g][0]))
            if not fv:
                continue
            n = len(fv)
            w("| %s | %s | %d | %.1f / %.1f / %.1f / %.1f / %.1f | %.1f | %s | %s | %s | %s | %s |" % (
                part, kind_sel, n, quant(fv, .1), quant(fv, .25), quant(fv, .5), quant(fv, .75), quant(fv, .9), quant(bv, .5),
                pct(sum(x >= 10 for x in fv), n), pct(sum(5 <= x < 10 for x in fv), n), pct(sum(0 <= x < 5 for x in fv), n),
                pct(sum(-5 <= x < 0 for x in fv), n), pct(sum(x < -5 for x in fv), n)))
    w("")
    bl = []
    for (rid, m), d in key.at.items():
        if len(d) >= 2 and key.recs[rid]["part"] == "set":
            bl.append(max(db(v[1]) for v in d.values()))
    if bl:
        w("In blends (set), the louder song over everything else: median %.1f dB, 10th percentile %.1f (n %d).\n" % (quant(bl, .5), quant(bl, .1), len(bl)))
    # ---- against the booth's log
    if results:
        R, firsts, byrid = first_results
        w("## Against the booth's log (ShazamKit, that evening), catalogue %s, set only\n" % results[0][0])
        trc = json.load(open(os.path.join(work, "catalogue.json")))
        bykey = collections.defaultdict(set)
        for k, v in trc.items():
            bykey[(norm(v["title"]), norm(v["artist"]))].add(k)
        # The booth's own catalogue that night, when given: which catalogue songs ShazamKit could have named at all.
        in_booth = None
        if a.booth_catalogue:
            bt = json.load(open(a.booth_catalogue))
            bt = bt.get("tracks", bt) if isinstance(bt, dict) else bt
            in_booth = set()
            for t in bt:
                song = norm(str(t.get("song") or t.get("title") or "")); art = norm(str(t.get("artist") or ""))
                dur = float(t.get("dur") or t.get("secs") or 0)
                for k, v in trc.items():
                    ct = norm(v["title"])
                    if song and (song in ct or ct in song) and (not art or art.split()[0] in norm(v["artist"])) and abs(v["seconds"] - dur) < 2.5:
                        in_booth.add(k)
            w("Booth catalogue that night: %d songs, %d catalogue entries found for them by title, artist and length.\n" % (len(bt), len(in_booth)))
        rows = collections.Counter(); deltas = []; faders = []
        LS = sorted({q["L"] for q in R.values()})
        for s in key.stretches:
            if s["part"] != "set" or s["end"] - s["start"] < 30:
                continue
            r = key.recs[s["rid"]]
            ok = key.sids[s["g"]]
            cls = "outside the booth's catalogue" if in_booth is not None and not (ok & in_booth) else "in the booth's catalogue"
            theirs = None; before = False
            last = None
            for e in sorted(r["entries"], key=lambda e: float(e["at"])):
                ids = set(log_ids(e, bykey))
                t = float(e["at"])
                if t < s["start"] - 10:
                    last = ids
                elif t <= s["end"] + 5 and ids & ok:
                    theirs = t - s["start"]; break
            if theirs is None and last is not None and last & ok:
                before = True
            ours = firsts.get((s["rid"], s["g"], s["start"], "any"))
            o8 = firsts.get((s["rid"], s["g"], s["start"], 8.0))
            if theirs is not None:
                ent = next(e for e in r["entries"] if float(e["at"]) - s["start"] == theirs)
                v = [100 * (q["best"][4] - 1) for q in byrid[s["rid"]] if q["L"] == max(LS) and s["start"] <= q["t"] - q["L"]
                     and q["t"] <= s["end"] and q["best"][6] >= thr and q["best"][0] in ok]
                if len(v) >= 3:
                    faders.append((statistics.median(v), float(ent.get("pitch", 0)), ent.get("pitchKind", "")))
                rows[(cls, "both" if ours is not None else "log only")] += 1
                if ours is not None:
                    deltas.append((ours, theirs, o8, cls))
            elif before:
                rows[(cls, "booth already showing it" + (", ours named it" if ours is not None else ", ours not"))] += 1
            else:
                rows[(cls, "ours only" if ours is not None else "neither")] += 1
        w("| song | named by | stretches of 30 s or more |")
        w("|---|---|---|")
        for k in sorted(rows):
            w("| %s | %s | %d |" % (k[0], k[1], rows[k]))
        w("")
        for cls in sorted({d[3] for d in deltas}):
            dd = [d for d in deltas if d[3] == cls]
            w("Named by both (%s, %d stretches): seconds from the song's start to the first name, median (90th percentile): "
              "ours, any length %.0f (%.0f); ours, 8 s windows only %.0f (%.0f); the log %.0f (%.0f). Ours earlier by more than "
              "2 s in %d, the log earlier in %d, within 2 s in %d.\n" % (
                cls, len(dd), quant([d[0] for d in dd], .5), quant([d[0] for d in dd], .9),
                quant([d[2] for d in dd if d[2] is not None], .5), quant([d[2] for d in dd if d[2] is not None], .9),
                quant([d[1] for d in dd], .5), quant([d[1] for d in dd], .9),
                sum(d[0] < d[1] - 2 for d in dd), sum(d[1] < d[0] - 2 for d in dd), sum(abs(d[0] - d[1]) <= 2 for d in dd)))
        if faders:
            d = [abs(a - b) for a, b, _ in faders]
            w("The fader, ours (median of right 12 s windows) against the booth's logged pitch, songs both named: %d; "
              "difference median %.2f points, 90th %.2f; the booth logged 0 where ours read 1 %% or more: %d; ours read under "
              "0.5 %% where the booth logged 1 %% or more: %d.\n" % (len(faders), quant(d, .5), quant(d, .9),
              sum(abs(b) < 0.05 and abs(a) >= 1 for a, b, _ in faders), sum(abs(a) < 0.5 and abs(b) >= 1 for a, b, _ in faders)))
        # Log entries the key cannot confirm: the logged song not heard by the waveform check near the entry.
        tot = unv = 0; unv_state = collections.Counter(); other_song = 0
        for rid, r in key.recs.items():
            if r["part"] != "set":
                continue
            for e in r["entries"]:
                tot += 1
                ids = set(log_ids(e, bykey))
                t = float(e["at"])
                near = [(rid, STEP * round(t / STEP) + k * STEP) for k in range(-8, 9)]
                heard = any(key.sids[g] & ids for x in near for g in key.at.get(x, {}))
                if not heard:
                    unv += 1
                    sts = collections.Counter(key.state.get(x) for x in near)
                    unv_state[sts.most_common(1)[0][0]] += 1
                    other_song += any(key.at.get(x) for x in near)
        w("Log entries in the set: %d. Not confirmed by the waveform check within 16 s: %d (the key there mostly: %s; "
          "another song verified nearby for %d of them).\n" % (tot, unv, ", ".join("%s %d" % kv for kv in unv_state.items()), other_song))
    open(os.path.join(work, "report.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


# ---------------------------------------------------------------- the listener's readings (deckie-listen)
def read_readings(path):
    """recording id -> list of (seconds heard, state, song id or None, place, speed percent or None, key lock, confidence, ms)."""
    out = collections.defaultdict(list)
    for line in open(path):
        c = line.rstrip("\n").split("\t")
        if len(c) < 9:
            continue
        on = c[2] in ("named", "held") and c[3] != "-"
        out[c[0]].append((float(c[1]), c[2], c[3] if on else None, None if c[4] == "-" else float(c[4]),
                          None if c[5] == "-" else float(c[5]), c[6], float(c[7]), float(c[8])))
    for v in out.values():
        v.sort()
    return out


def listen_report(a):
    """Scores the listener's readings (one a second, what the booth would show) against the answer key."""
    work = a.work
    mix_ids = [l.strip() for l in open(a.mix)] if a.mix else []
    key = Key(work, mix_ids)
    cat = json.load(open(os.path.join(work, "catalogue.json")))
    titles = {k: norm(v["title"]).split()[:3] for k, v in cat.items()}
    cat_ids = {}
    for spec in a.catalogue_ids or []:
        n_, f_ = spec.split("=", 1)
        cat_ids[n_] = {l.strip() for l in open(f_) if l.strip()}
    verified = {}
    if a.verified_extra:
        verified = {tuple(k.split("|")): set(float(m) for m in v) for k, v in json.load(open(a.verified_extra)).items()}
    out = []; w = out.append
    w("# The finished listener against the answer key\n")

    def moment(t):
        return STEP * round(t / STEP)

    def kind_of(sid, ok):
        if sid in mix_ids:
            return "the pre-mixed disc's track"
        if sid in titles and any(titles.get(o) == titles[sid] for o in ok):
            return "a copy or version of the playing song (same title)"
        if sid not in titles:
            return "a song from the added music"
        return "another song"

    for spec in a.readings:
        name, path = spec.split("=", 1)
        R = read_readings(path)
        ids = cat_ids.get(name)
        w("## %s\n" % name)
        for part in ("set", "before"):
            rows = collections.defaultdict(collections.Counter)
            wrong = collections.Counter()
            other = collections.Counter()
            ms = []
            for rid, rs in R.items():
                if rid not in key.recs or key.recs[rid]["part"] != part:
                    continue
                # steady runs: the same song on screen for 5 readings or more with its place advancing with the clock
                steady = set()
                i = 0
                while i < len(rs):
                    j = i
                    while (j + 1 < len(rs) and rs[j + 1][2] is not None and rs[j + 1][2] == rs[i][2] and rs[j + 1][3] is not None
                           and rs[j][3] is not None and abs((rs[j + 1][3] - rs[j][3]) - (rs[j + 1][0] - rs[j][0])) < 1.0):
                        j += 1
                    if rs[i][2] is not None and j - i + 1 >= 5:
                        steady.update(range(i, j + 1))
                    i = j + 1
                for ix, (t, st, sid, place, speed, lock, conf, took) in enumerate(rs):
                    ms.append(took)
                    m = moment(t)
                    state = key.state.get((rid, m))
                    d = key.at.get((rid, m), {})
                    if state == "song":
                        g = next(iter(d))
                        if ids is not None and not (key.sids[g] & ids):
                            continue
                        k = key.kind(rid, m, g)
                        c = rows[k]; c["n"] += 1
                        if sid is None:
                            c["none"] += 1
                        elif sid in key.sids[g]:
                            c["right"] += 1
                        else:
                            c["wrong"] += 1
                            prev = any(sid in key.sids[h] for x in range(1, 16) for h in key.at.get((rid, m - x * STEP), {}))
                            if any(abs(mm - m) <= 6 for mm in verified.get((rid, sid), ())):
                                wrong["an added file the waveform confirms there (the same music)"] += 1
                            else:
                                wrong["the song before, still on screen" if prev and sid not in mix_ids else kind_of(sid, key.sids[g])] += 1
                    elif state == "blend":
                        c = rows["blend"]; c["n"] += 1
                        ok = set().union(*(key.sids[g] for g in d))
                        c["right" if sid in ok else ("none" if sid is None else "wrong")] += 1
                    elif state in ("talk", "silence", "unknown"):
                        c = other[state + ":n"]; other[state + ":n"] += 1
                        if sid is not None:
                            # held over from the song just before (the same name the key had within 30 s), or confirmed
                            # by the waveform as an added song really heard there, or a fresh name
                            before = any(sid in key.sids[g] for x in range(1, 16) for g in key.at.get((rid, m - x * STEP), {}))
                            if before:
                                other[state + ":held over"] += 1
                            elif any(abs(mm - m) <= 6 for mm in verified.get((rid, sid), ())):
                                other[state + ":confirmed added song"] += 1
                            elif ix in steady:
                                other[state + ":steady"] += 1
                                if sid in mix_ids:
                                    other[state + ":steady mix"] += 1
                            else:
                                other[state + ":named"] += 1
            if not ms:
                continue
            w("### %s: share of seconds, percent\n" % part)
            w("| what the key says | seconds | right name on screen | wrong name | nothing |")
            w("|---|---|---|---|---|")
            for k in ("live", "mix", "blend"):
                c = rows[k]
                if c["n"]:
                    w("| %s | %d | %s | %s | %s |" % ({"live": "one song, live", "mix": "one song, the pre-mixed disc", "blend": "a blend (right: either song)"}[k],
                                                     c["n"], pct(c["right"], c["n"]), pct(c["wrong"], c["n"]), pct(c["none"], c["n"])))
            w("")
            if wrong:
                w("Wrong names on one-song seconds, by what was named: " + "; ".join("%s %d" % kv for kv in sorted(wrong.items())) + ".\n")
            w("| key says | seconds | a name held over from the song before | an added song the waveform confirms there | a steady run (5 s or more, place advancing; of which the pre-mixed disc) | a name otherwise |")
            w("|---|---|---|---|---|---|")
            for st in ("talk", "silence", "unknown"):
                n = other[st + ":n"]
                if n:
                    w("| %s | %d | %d | %d | %d (%d) | %d |" % (st, n, other[st + ":held over"], other[st + ":confirmed added song"],
                                                            other[st + ":steady"], other[st + ":steady mix"], other[st + ":named"]))
            w("")
            ms.sort()
            w("A reading took %.1f ms at the median, %.1f at the 95th percentile, %.1f at the 99th, %.0f at most (%d readings).\n" % (
                quant(ms, .5), quant(ms, .95), quant(ms, .99), ms[-1], len(ms)))
        # time to name, per stretch of 30 s or more
        for part in ("set", "before"):
            d = []; never = 0; n = 0; firsts = {}
            for s in key.stretches:
                if s["part"] != part or s["end"] - s["start"] < 30 or s["rid"] not in R:
                    continue
                if ids is not None and not (key.sids[s["g"]] & ids):
                    continue
                n += 1
                hit = next((t for (t, st, sid, *_r) in R[s["rid"]] if s["start"] <= t <= s["end"] + 4 and sid in key.sids[s["g"]]), None)
                firsts[(s["rid"], s["g"], s["start"])] = None if hit is None else hit - s["start"]
                if hit is None:
                    never += 1
                else:
                    d.append(hit - s["start"])
            if n:
                w("Time to name (%s, songs heard 30 s or more, %d): median %.0f s, 90th percentile %.0f s, slowest %.0f s, never %d.\n" % (
                    part, n, quant(d, .5), quant(d, .9), max(d) if d else float("nan"), never))
            if part == "set":
                set_firsts = firsts
        # the fader, per stretch: the listener's readings against the first run's (12 s windows) and the booth's log
        fad = []
        for s in key.stretches:
            if s["part"] != "set" or s["end"] - s["start"] < 30 or s["rid"] not in R:
                continue
            v = [sp for (t, st, sid, place, sp, *_r) in R[s["rid"]] if s["start"] <= t <= s["end"] and sid in key.sids[s["g"]] and sp is not None]
            if len(v) >= 5:
                fad.append((s, statistics.median(v), quant(v, .75) - quant(v, .25)))
        if fad:
            w("The fader (set, %d songs): reading per song from %+.2f to %+.2f; spread within a song (25th to 75th percentile) "
              "median %.3f points, 90th %.3f; songs over 2 %%: %d, over 4 %%: %d.\n" % (len(fad), min(f[1] for f in fad), max(f[1] for f in fad),
              quant([f[2] for f in fad], .5), quant([f[2] for f in fad], .9), sum(abs(f[1]) > 2 for f in fad), sum(abs(f[1]) > 4 for f in fad)))
            if a.old_results:
                old = read_results(a.old_results)
                byrid = collections.defaultdict(list)
                for q in old.values():
                    if q["L"] == 12:
                        byrid[q["rid"]].append(q)
                diffs = []
                for s, med, _ in fad:
                    v = [100 * (q["best"][4] - 1) for q in byrid[s["rid"]] if s["start"] <= q["t"] - q["L"] and q["t"] <= s["end"]
                         and q["best"][6] >= a.threshold and q["best"][0] in key.sids[s["g"]]]
                    if len(v) >= 3:
                        diffs.append(abs(med - statistics.median(v)))
                if diffs:
                    w("Against the first run's reading of the same songs (%d): difference median %.3f points, 90th %.3f, largest %.2f.\n" % (
                        len(diffs), quant(diffs, .5), quant(diffs, .9), max(diffs)))
            bykey = collections.defaultdict(set)
            for k, v in cat.items():
                bykey[(norm(v["title"]), norm(v["artist"]))].add(k)
            ld = []
            for s, med, _ in fad:
                for e in key.recs[s["rid"]]["entries"]:
                    if set(log_ids(e, bykey)) & key.sids[s["g"]] and s["start"] - 10 <= float(e["at"]) <= s["end"] + 5:
                        ld.append(abs(med - float(e.get("pitch", 0)))); break
            if ld:
                w("Against the booth's own logged pitch (%d songs): difference median %.2f points, 90th %.2f.\n" % (len(ld), quant(ld, .5), quant(ld, .9)))
        # against the booth's log: time to name where both named
        bykey = collections.defaultdict(set)
        for k, v in cat.items():
            bykey[(norm(v["title"]), norm(v["artist"]))].add(k)
        both = []; ours_only = theirs_only = neither = already = 0
        for s in key.stretches:
            if s["part"] != "set" or s["end"] - s["start"] < 30 or s["rid"] not in R:
                continue
            if ids is not None and not (key.sids[s["g"]] & ids):
                continue
            ok = key.sids[s["g"]]; theirs = None; last = None
            for e in sorted(key.recs[s["rid"]]["entries"], key=lambda e: float(e["at"])):
                t = float(e["at"]); li = set(log_ids(e, bykey))
                if t < s["start"] - 10:
                    last = li
                elif t <= s["end"] + 5 and li & ok:
                    theirs = t - s["start"]; break
            ours = set_firsts.get((s["rid"], s["g"], s["start"]))
            if theirs is not None and ours is not None:
                both.append((ours, theirs))
            elif theirs is not None:
                theirs_only += 1
            elif last is not None and last & ok:
                already += 1
            elif ours is not None:
                ours_only += 1
            else:
                neither += 1
        w("Against the booth's log (set): both named %d; the log only %d; the booth already showing it %d; ours only %d; neither %d." % (
            len(both), theirs_only, already, ours_only, neither))
        if both:
            w("Where both named it: ours a median %.0f s after the song's start (90th %.0f), the log %.0f s (90th %.0f); ours earlier "
              "by more than 2 s in %d, the log in %d, within 2 s in %d.\n" % (quant([b[0] for b in both], .5), quant([b[0] for b in both], .9),
              quant([b[1] for b in both], .5), quant([b[1] for b in both], .9), sum(b[0] < b[1] - 2 for b in both),
              sum(b[1] < b[0] - 2 for b in both), sum(abs(b[0] - b[1]) <= 2 for b in both)))
        # time per reading across the evening's hours (growth)
        hours = collections.defaultdict(list)
        for rid, rs in R.items():
            if rid in key.recs and key.recs[rid]["part"] == "set":
                for r in rs:
                    hours[int(r[0] // 1800)].append(r[7])
        if hours:
            w("A reading's time by half hour into a recording (set; median / 95th ms): " + "; ".join(
                "%g h: %.1f / %.1f" % (h / 2, quant(v, .5), quant(v, .95)) for h, v in sorted(hours.items())) + ".\n")
    open(os.path.join(work, a.out), "w").write("\n".join(out) + "\n")
    print("\n".join(out))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd")
    q = sub.add_parser("prepare"); q.add_argument("recordings"); q.add_argument("work")
    q.add_argument("--step", type=float, default=STEP); q.add_argument("--lengths", default="3,5,8,12")
    q.add_argument("--min-seconds", type=float, default=30); q.add_argument("--part-from", default="")
    q = sub.add_parser("catalogue"); q.add_argument("crate"); q.add_argument("root"); q.add_argument("work")
    q.add_argument("--subset", nargs="*")
    q = sub.add_parser("extra"); q.add_argument("folder"); q.add_argument("work")
    q.add_argument("--mix-minutes", type=float, default=15)
    q = sub.add_parser("truth"); q.add_argument("work"); q.add_argument("results", nargs="+")
    q.add_argument("--threshold", type=float, default=2.96); q.add_argument("--jobs", type=int, default=1)
    q.add_argument("--subset", default=""); q.add_argument("--only", default="", help="recordings to use (a test run)")
    q = sub.add_parser("listen-report"); q.add_argument("work"); q.add_argument("readings", nargs="+")
    q.add_argument("--mix", default=""); q.add_argument("--catalogue-ids", nargs="*"); q.add_argument("--verified-extra", default="")
    q.add_argument("--old-results", default=""); q.add_argument("--threshold", type=float, default=2.96)
    q.add_argument("--out", default="listen-report.md")
    q = sub.add_parser("report"); q.add_argument("work"); q.add_argument("results", nargs="+")
    q.add_argument("--threshold", type=float, default=2.96); q.add_argument("--mix", default="")
    q.add_argument("--catalogue-ids", nargs="*", help="NAME=ids.txt: the songs a catalogue holds (tables then leave out songs it lacks)")
    q.add_argument("--booth-catalogue", default="", help="the booth's own catalogue that night (JSON with tracks: song, artist, dur)")
    a = p.parse_args()
    {"prepare": prepare, "catalogue": catalogue, "extra": extra, "truth": truth, "report": report, "listen-report": listen_report}[a.cmd](a)


if __name__ == "__main__":
    main()
