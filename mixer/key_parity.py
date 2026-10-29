#!/usr/bin/env python3
"""Research R: key parity. Search for a licence-clean whole-track key estimator that brings the shippable engine
(PC and Linux; today the lab's one-vote estimator, mixer/key_light.py with STFT chroma and the edma profile) closer to
the lab's three-vote key on the 373-track yardstick, and to Apple's key.

Everything in the method is our own arithmetic on an FFT: spectral peaks, an HPCP-style pitch-class profile, a
tuning estimate, published key profiles (numbers from papers), Pearson correlation, a vote. Essentia appears only
as a reference: the lab's stored Essentia keys (features/<id>.json) are scored alongside, never used by a method.

  .venv/bin/python key_parity.py extract [--jobs 6] [--limit N]   decode each track once, cache per-frame features
  .venv/bin/python key_parity.py score                            score every method, write key_parity_results.tsv
  .venv/bin/python key_parity.py check                            the recommended method's speed on 10 tracks
  .venv/bin/python key_parity.py keys                             per-track key, margin, agreement and sure flag of the
                                                                  recommended method (row 3f) -> key_parity_keys.tsv

Cache: $DECKIE_KEY_CACHE or <tmp>/deckie_key_parity_cache/ (about 1.2 GB, not committed; rebuild with `extract`).
Run from mixer/ (imports key_light for the shipped baseline's profiles and Camelot tables)."""
import csv, json, os, sys, time, warnings
from collections import Counter
warnings.filterwarnings("ignore")
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import key_light as KL   # PROFILES, CAM_MAJ, CAM_MIN, MU_PC, best_key, camelot (the shipped baseline, verbatim)

import tempfile
CACHE = os.environ.get("DECKIE_KEY_CACHE", os.path.join(tempfile.gettempdir(), "deckie_key_parity_cache"))
SR44, N44, H44 = 44100, 4096, 4096        # peak analysis: 93 ms frames, no overlap (the HPCP family's usual frame)
SR22, N22, H22 = 22050, 8192, 2048        # the shipped chroma: 0.37 s frames every 93 ms
FMIN_PK, FMAX_PK, NPEAKS = 25.0, 3500.0, 60
MIDI_LO, MIDI_HI = 28, 108                # semitone spectrum E1 .. B7 (80 bins)

# ----------------------------------------------------------------------------------------------- extraction
def load44(path):
    import soundfile as sf, librosa
    y, sr = sf.read(path, dtype="float32", always_2d=True); y = y.mean(axis=1)
    if sr != SR44: y = librosa.resample(y, orig_sr=sr, target_sr=SR44, res_type="soxr_hq")
    return y, sr

def spectral_peaks(y):
    """Per 4096-sample Hann frame (hop 4096): local maxima of the magnitude spectrum between 25 and 3500 Hz, refined by
    parabolic interpolation on the dB spectrum, the 60 largest kept. Also the frame's spectral envelope at each peak
    (mean magnitude over a one-third-octave neighbourhood), for whitening. Returns freq, mag, env as (T, 60)."""
    n = 1 + max(0, (len(y) - N44) // H44)
    win = np.hanning(N44 + 1)[:-1].astype(np.float32)
    fr = np.lib.stride_tricks.sliding_window_view(y, N44)[::H44][:n] * win
    X = np.abs(np.fft.rfft(fr, axis=1)).astype(np.float32) * (2.0 / win.sum())   # a full-scale sine reads 1.0
    freqs = np.arange(X.shape[1]) * SR44 / N44
    lo, hi = int(np.ceil(FMIN_PK * N44 / SR44)), int(FMAX_PK * N44 / SR44)
    dB = 20 * np.log10(X + 1e-10)
    a, b, c = dB[:, lo - 1:hi - 1], dB[:, lo:hi], dB[:, lo + 1:hi + 1]
    ism = (b > a) & (b >= c) & (X[:, lo:hi] > 1e-5)
    den = a - 2 * b + c; p = np.where(den != 0, 0.5 * (a - c) / np.where(den == 0, 1, den), 0.0)
    pf = (np.arange(lo, hi)[None, :] + p) * SR44 / N44
    pm = 10 ** ((b - 0.25 * (a - c) * p) / 20)
    pm = np.where(ism, pm, 0.0)
    order = np.argsort(-pm, axis=1)[:, :NPEAKS]
    F = np.take_along_axis(pf, order, 1).astype(np.float32); M = np.take_along_axis(pm, order, 1).astype(np.float32)
    F[M == 0] = 0
    # envelope: running mean of the magnitude spectrum over +-1/6 octave around each bin (cumulative sums, per frame)
    cs = np.concatenate([np.zeros((X.shape[0], 1), np.float32), np.cumsum(X, axis=1)], axis=1)
    k = np.arange(X.shape[1]); kl = np.clip(np.floor(k * 2 ** (-1 / 6)).astype(int), 0, X.shape[1] - 1)
    kh = np.clip(np.ceil(k * 2 ** (1 / 6)).astype(int) + 1, 1, X.shape[1])
    envs = (cs[:, kh] - cs[:, kl]) / np.maximum(kh - kl, 1)
    kb = np.clip(np.rint(F * N44 / SR44).astype(int), 0, X.shape[1] - 1)
    E = np.take_along_axis(envs, kb, 1).astype(np.float32)
    # peak envelope for whitening: the largest magnitude within +-w octave of each peak (w = 1/6, 1/3, 1/2), so the
    # strongest peak of each neighbourhood reads 1 after division and weaker ones read below 1 (a running-max
    # envelope, the simplest stand-in for the "true envelope" of Robel and Rodet 2005). Range maxima by a sparse table.
    nb = int(FMAX_PK * 2 ** 0.5 * N44 / SR44) + 2
    Xs = X[:, :nb]; table = [Xs]
    while (1 << len(table)) <= nb:   # table[j][:, i] = max of Xs[:, i : i + 2**j]
        sh = 1 << (len(table) - 1); prev = table[-1]; table.append(np.maximum(prev[:, :-sh], prev[:, sh:]))
    def range_max(lo_b, hi_b):   # inclusive bin ranges, per frame and peak
        lo_b = np.clip(lo_b, 0, nb - 1); hi_b = np.clip(hi_b, lo_b, nb - 1); L = hi_b - lo_b + 1
        lv = np.floor(np.log2(L)).astype(int); out = np.zeros(lo_b.shape, np.float32)
        rows = np.repeat(np.arange(F.shape[0])[:, None], F.shape[1], 1)
        for j in range(len(table)):
            sel = lv == j
            if not sel.any(): continue
            tj = table[j]; a = np.clip(lo_b[sel], 0, tj.shape[1] - 1); b = np.clip(hi_b[sel] - (1 << j) + 1, 0, tj.shape[1] - 1)
            out[sel] = np.maximum(tj[rows[sel], a], tj[rows[sel], b])
        return out
    kf = F * N44 / SR44
    Emax = {w: range_max(np.floor(kf * 2 ** (-w)).astype(int), np.ceil(kf * 2 ** w).astype(int)) for w in (1 / 6, 1 / 3, 1 / 2)}
    rms = np.sqrt((fr ** 2).mean(axis=1)).astype(np.float32)
    return F, M, E, rms, Emax

def extract_one(item):
    tid, path = item
    out = os.path.join(CACHE, tid + ".npz")
    if os.path.exists(out): return tid, "cached"
    import librosa
    try:
        y44, sr0 = load44(path)
        y22 = librosa.resample(y44, orig_sr=SR44, target_sr=SR22, res_type="soxr_hq") if sr0 == SR44 else None
        if y22 is None:   # the shipped path resamples from the file's own rate; keep that exactly
            import soundfile as sf
            y0, _ = sf.read(path, dtype="float32", always_2d=True); y22 = librosa.resample(y0.mean(axis=1), orig_sr=sr0, target_sr=SR22, res_type="soxr_hq")
        S = np.abs(librosa.stft(y22, n_fft=N22, hop_length=H22)) ** 2
        C0 = librosa.feature.chroma_stft(S=S, sr=SR22, n_fft=N22, hop_length=H22, tuning=0.0)   # == key_light stft
        tun_lr = float(librosa.estimate_tuning(S=np.sqrt(S), sr=SR22, n_fft=N22))
        # semitone spectrum: each FFT bin's power split between its two nearest semitones (triangular weights)
        fq = librosa.fft_frequencies(sr=SR22, n_fft=N22); ok = fq > 30
        pitch = np.full(len(fq), -1.0); pitch[ok] = 69 + 12 * np.log2(fq[ok] / 440.0)
        S = S / (S.max() + 1e-20)     # keep the stored semitone spectrum inside float16 range
        def semis(tuning):
            P = np.zeros((MIDI_HI - MIDI_LO, S.shape[1]), np.float32); pt = pitch - tuning
            for m in range(MIDI_LO, MIDI_HI):
                w = np.clip(1 - np.abs(pt - m), 0, None); w[~ok] = 0; nz = w > 0
                P[m - MIDI_LO] = w[nz] @ S[nz]
            return P
        F, M, E, rms, Emax = spectral_peaks(y44)
        # own tuning estimate: magnitude-weighted circular mean of each peak's offset from the equal-tempered grid
        sel = (F > 80) & (F < 2000) & (M > 0)
        dev = (12 * np.log2(F[sel] / 440.0)) % 1.0; w = M[sel]
        ang = np.angle(np.sum(w * np.exp(2j * np.pi * dev))) / (2 * np.pi)   # in semitones, -0.5 .. 0.5
        tun_own = float(ang)
        P0 = semis(0.0); Pt = semis(tun_own)
        flat = np.exp(np.mean(np.log(S[100:1900] + 1e-12), axis=0)) / (np.mean(S[100:1900], axis=0) + 1e-12)
        np.savez_compressed(out, C0=C0.astype(np.float32), P0=P0.astype(np.float16), Pt=Pt.astype(np.float16),
                            F=F, M=M, E=E, E6=Emax[1 / 6], E3=Emax[1 / 3], E2=Emax[1 / 2], rms=rms, flat=flat.astype(np.float32), tun_own=tun_own, tun_lr=tun_lr,
                            dur=len(y44) / SR44)
        return tid, "ok"
    except Exception as e:
        return tid, f"error {e}"

def extract(jobs, limit):
    os.makedirs(CACHE, exist_ok=True)
    cands = json.load(open(os.path.join(HERE, "candidates.json")))[:limit]
    from multiprocessing import Pool
    t0 = time.time(); done = 0
    with Pool(jobs) as pool:
        for tid, st in pool.imap_unordered(extract_one, [(c["id"], c["path"]) for c in cands]):
            done += 1
            if st.startswith("error") or done % 25 == 0: print(f"{done}/{len(cands)} {tid} {st} {time.time() - t0:.0f}s", file=sys.stderr)
    print(f"extracted {len(cands)} in {time.time() - t0:.0f}s", file=sys.stderr)

# ----------------------------------------------------------------------------------------------- key arithmetic
def harmonic_template(note, n_harm=4, slope=0.6):
    """A note's pitch-class energy with its first n_harm harmonics, the h-th weighted slope**(h-1) and folded to the
    nearest pitch class (h = 2, 4 land on the note, h = 3 on its fifth). Gomez 2006, section 3."""
    t = np.zeros(12)
    for h in range(1, n_harm + 1): t[(note + int(round(12 * np.log2(h)))) % 12] += slope ** (h - 1)
    return t

def polyphonic(mono, mode, n_harm=4, slope=0.6):
    """Gomez 2006 polyphonic key profile restricted to the three main triads: tonic, subdominant and dominant chords
    of the key (the minor key's dominant is major, harmonic minor), each note carrying its harmonics, each chord
    weighted by the monophonic profile's value at its root. Tonic first, 12 values."""
    mono = np.asarray(mono, float)
    chords = [(0, (0, 4, 7)), (5, (5, 9, 0)), (7, (7, 11, 2))] if mode == "major" else [(0, (0, 3, 7)), (5, (5, 8, 0)), (7, (7, 11, 2))]
    return sum(mono[r] * sum(harmonic_template(n, n_harm, slope) for n in notes) for r, notes in chords)

# Profiles not in key_light: Albrecht & Shanahan 2013 (Music Perception 31(1), Table 2, corpus of 490 pieces) and
# Aarden 2003 (thesis, essen folksong corpus) are left out on purpose (classical / folk corpora); the six key_light
# profiles are the published ones that target pop and dance music or are the classic baselines.
PROFILES = dict(KL.PROFILES)

def key_matrix(prof, poly=False):
    """24 x 12 matrix of mean-removed, unit-norm key profiles, rows major C..B then minor C..B (pitch class C = 0)."""
    rows = []
    for mode, p in (("major", prof[0]), ("minor", prof[1])):
        p = polyphonic(p, mode) if poly else np.asarray(p, float)
        for s in range(12):
            q = np.roll(p, s); q = q - q.mean(); rows.append(q / np.linalg.norm(q))
    return np.array(rows)

KM = {}
def km(name, poly=False):
    if (name, poly) not in KM: KM[(name, poly)] = key_matrix(PROFILES[name], poly)
    return KM[(name, poly)]

def corr24(c, M):
    c = np.asarray(c, float); c = c - c.mean(); n = np.linalg.norm(c)
    return M @ c / n if n > 0 else np.zeros(24)

def cam24(i): return (KL.CAM_MAJ + KL.CAM_MIN)[i]

def pick(r):
    o = np.argsort(-r); return cam24(o[0]), float(r[o[0]]), float(r[o[0]] - r[o[1]])

# ----------------------------------------------------------------------------------------------- chroma variants
def hpcp(F, M, E, ref=440.0, n_harm=1, slope=0.6, width=4 / 3, whiten=False, frame_norm=True, fmin=25.0, fmax=3500.0, weight="cos2"):
    """HPCP from spectral peaks (Gomez 2006): each peak of frequency f and magnitude a adds w(d) * a**2 to the pitch
    classes near f / h for h = 1..n_harm (weight slope**(h-1)), w(d) = cos^2(pi d / width) for |d| <= width / 2 semitones
    from the pitch class centre. Frames normalised to their maximum (unitMax) when frame_norm. Returns (T, 12), C = 0."""
    A = (M / np.maximum(E, 1e-9)) if whiten else M
    A = np.where((F >= fmin) & (F <= fmax) & (M > 0), A, 0.0) ** 2
    out = np.zeros((F.shape[0], 12))
    Fs = np.maximum(F, 1e-3)
    for h in range(1, n_harm + 1):
        semi = 12 * np.log2(Fs / (h * ref)) + 9          # 0 = C (A = 9)
        base = np.floor(semi).astype(int)
        for k in (-1, 0, 1, 2):
            pcb = base + k; d = semi - pcb
            w = np.where(np.abs(d) <= width / 2, np.cos(np.pi * d / width) ** (2 if weight == "cos2" else 1), 0.0) * slope ** (h - 1)
            np.add.at(out, (np.repeat(np.arange(F.shape[0]), F.shape[1]), (pcb % 12).ravel()), (w * A).ravel())
    if frame_norm: out = out / (out.max(axis=1, keepdims=True) + 1e-12)
    return out

def semichroma(P, lo=MIDI_LO, hi=MIDI_HI, log=False, frame_norm=True):
    """Chroma by folding the semitone spectrum over MIDI notes lo..hi-1; optional log compression log(1 + 100 x / max)."""
    P = P.astype(np.float64)[lo - MIDI_LO:hi - MIDI_LO]
    if log: P = np.log1p(100 * P / (P.max() + 1e-12))
    C = np.zeros((12, P.shape[1]))
    for m in range(lo, hi): C[m % 12] += P[m - lo]
    if frame_norm: C = C / (C.max(axis=0, keepdims=True) + 1e-12)
    return C.T

# ----------------------------------------------------------------------------------------------- references and buckets
def mu_key(tid):
    p = os.path.join(HERE, "mu_raw", tid + ".mu.json")
    if not os.path.exists(p): return ""
    k = json.load(open(p)).get("key")
    if not k or not k["ranges"]: return ""
    v = max(k["ranges"], key=lambda z: z["range"]["duration"]["value"])["value"]
    return KL.camelot(KL.MU_PC[v["tonic"]], v["mode"])

def relation(a, b):
    """The bench's relation (bench_mu.key_relation): exact; neighbour = relative (same number) or one step on the
    wheel (same letter); other. Plus the fine class for the confusion summary."""
    if a == b: return "exact", "exact"
    na, la, nb, lb = int(a[:-1]), a[-1], int(b[:-1]), b[-1]
    if na == nb: return "neighbour", "relative"
    if la == lb and (na - nb) % 12 in (1, 11): return "neighbour", "fifth"
    if la != lb and ((la == "B" and (na - nb) % 12 == 3) or (la == "A" and (nb - na) % 12 == 3)): return "other", "parallel"
    if la == lb and (na - nb) % 12 == 6: return "other", "tritone"
    if la == lb and (na - nb) % 12 in (2, 10): return "other", "two_fifths"
    return "other", "other"

STYLE = {"dance original": "dance", "pool edit": "dance", "official remix": "dance", "pop original": "pop",
         "slow / R&B": "pop", "library": "other", "ambient": "other", "rip": "other"}
def tempo_bucket(folder):
    try: lo = int(folder.split(" - ")[1].split("-")[0].split()[0]) if "under" not in folder else 0
    except Exception: return "?"
    return "under 110" if lo < 110 else ("110-129" if lo < 130 else "130 plus")
# the split for any value chosen by measurement: tune on 90s + 2000s, report the other eras (pre-90s, 2010s, 2020s)
DEV_ERAS = {"90s", "2000s"}

def load_tracks():
    cands = json.load(open(os.path.join(HERE, "candidates.json")))
    out = []
    for c in cands:
        f = json.load(open(os.path.join(HERE, "features", c["id"] + ".json"))); k = f["key"]
        out.append({"id": c["id"], "title": c["title"], "lab": k["camelot"], "conf": k["confidence"], "mu": mu_key(c["id"]),
                    "ess_edma": k["camelot_edma"], "ess_bgate": k["camelot_bgate"], "madmom": k.get("camelot_madmom") or "",
                    "era": c.get("era") or "?", "style": STYLE.get(c.get("kind"), "other"), "tempo": tempo_bucket(c.get("folder", "")),
                    "split": "dev" if c.get("era") in DEV_ERAS else "held-out",
                    "mix_in": f.get("mix_in"), "mix_out": f.get("mix_out"), "dur": f.get("duration_s")})
    return out

# ----------------------------------------------------------------------------------------------- per-track vectors
WIN_S, WIN_HOP_S = 30.0, 15.0     # windows for the segment vote (the 30 s / 15 s of stage 1, 1e)
FPS = SR44 / H44                  # both frame grids run at 10.77 frames per second

def frame_variants(d):
    """Per-frame chroma (T, 12) for every variant studied. hpcp_<harmonics>_<envelope>[_tuned][_fn]: envelope none
    or e6 / e3 / e2 (running-max whitening over +-1/6, 1/3, 1/2 octave); _fn = each frame normalised to its maximum."""
    F, M = d["F"], d["M"]; ref_t = 440.0 * 2 ** (float(d["tun_own"]) / 12)
    V = {"stft": d["C0"].T.astype(np.float64),
         "semi": semichroma(d["P0"]), "semi_tuned": semichroma(d["Pt"]), "semi_tuned_log": semichroma(d["Pt"], log=True),
         "semi_tuned_above_c3": semichroma(d["Pt"], lo=48), "semi_tuned_bass": semichroma(d["Pt"], hi=52)}
    for h in (1, 4, 8):
        for env in ("none", "e6", "e3", "e2"):
            E = d["E" + env[1]] if env != "none" else None
            for fn in (False, True):
                V[f"hpcp_h{h}_{env}{'_fn' if fn else ''}"] = hpcp(F, M, E, n_harm=h, whiten=E is not None, frame_norm=fn)
            if env == "e3":
                V[f"hpcp_h{h}_{env}_tuned"] = hpcp(F, M, E, ref=ref_t, n_harm=h, whiten=True, frame_norm=False)
                V[f"hpcp_h{h}_{env}_w1cos"] = hpcp(F, M, E, n_harm=h, whiten=True, frame_norm=False, width=1.0, weight="cos")
                if h == 4:
                    for hp in (100.0, 200.0): V[f"hpcp_h4_e3_hp{int(hp)}"] = hpcp(F, M, E, n_harm=4, whiten=True, frame_norm=False, fmin=hp)
    return V

def summarise(tid):
    d = dict(np.load(os.path.join(CACHE, tid + ".npz")))
    V = frame_variants(d); out = {"tun_own": float(d["tun_own"]), "tun_lr": float(d["tun_lr"]), "frames": {}}
    rms = d["rms"].astype(np.float64)
    for k, X in V.items():
        T = X.shape[0]; r = rms[:T] if len(rms) >= T else np.pad(rms, (0, T - len(rms)), constant_values=rms.mean())
        loud = r >= 10 ** (-30 / 20) * np.median(r)               # drop frames 30 dB below the median (silence, fades)
        wins = [X[a:a + int(WIN_S * FPS)].mean(axis=0) for a in range(0, max(1, T - int(WIN_S * FPS) + 1), int(WIN_HOP_S * FPS))]
        mid = X[int(0.2 * T):int(0.8 * T)]
        out[k] = {"mean": X.mean(axis=0), "loud": X[loud].mean(axis=0) if loud.any() else X.mean(axis=0),
                  "rmsw": (X * r[:, None]).sum(axis=0) / (r.sum() + 1e-12), "mid": mid.mean(axis=0) if len(mid) else X.mean(axis=0),
                  "wins": np.array(wins)}
    out["T"] = V["stft"].shape[0]
    return tid, out

def all_summaries(tracks, jobs=6):
    path = os.path.join(CACHE, "summaries.npy")
    if os.path.exists(path) and "--fresh" not in sys.argv: return np.load(path, allow_pickle=True).item()
    from multiprocessing import Pool
    with Pool(jobs) as pool: S = dict(pool.map(summarise, [t["id"] for t in tracks]))
    np.save(path, S, allow_pickle=True); return S

# ----------------------------------------------------------------------------------------------- scoring
def score(tracks, keys, ref="lab"):
    """keys: id -> camelot. ref 'lab' uses the lab's confident tracks (confidence >= 0.65, as the bench), 'mu' Apple's."""
    sub = [t for t in tracks if (t["conf"] >= 0.65 if ref == "lab" else t["mu"]) and t["id"] in keys]
    refk = (lambda t: t["lab"]) if ref == "lab" else (lambda t: t["mu"])
    rel = [relation(keys[t["id"]], refk(t)) for t in sub]
    n = len(rel) or 1; c = Counter(r[0] for r in rel); f = Counter(r[1] for r in rel)
    # mode flips among the misses: we said minor where the reference says major, and the reverse
    m2n = sum(1 for t in sub if keys[t["id"]] != refk(t) and keys[t["id"]][-1] == "A" and refk(t)[-1] == "B")
    n2m = sum(1 for t in sub if keys[t["id"]] != refk(t) and keys[t["id"]][-1] == "B" and refk(t)[-1] == "A")
    return {"n": len(rel), "exact": c["exact"] / n, "neighbour": c["neighbour"] / n, "other": c["other"] / n,
            "relative": f["relative"] / n, "fifth": f["fifth"] / n, "parallel": f["parallel"] / n, "tritone": f["tritone"] / n,
            "two_fifths": f["two_fifths"] / n, "rest": f["other"] / n, "major_as_minor": m2n / n, "minor_as_major": n2m / n}

def buckets(tracks, keys):
    out = {}
    for field in ("split", "era", "style", "tempo"):
        for v in sorted({t[field] for t in tracks}):
            sub = [t for t in tracks if t[field] == v]
            a, b = score(sub, keys, "lab"), score(sub, keys, "mu")
            out[f"{field}={v}"] = (a["exact"], a["n"], b["exact"], b["n"])
    return out


# ----------------------------------------------------------------------------------------------- the recommended method
FARALDO = ("edma", "bgate", "braw")   # Faraldo et al. 2016 (edma) and 2017 (braw, bgate): the EDM corpus profiles

def recommended(y44):
    """Research R's recommended whole-track key, from mono float audio at 44.1 kHz. Returns (camelot, margin, agree,
    sure): spectral peaks per 4096-sample Hann frame (hop 4096), whitened by a running-max envelope over +-1/3 octave,
    HPCP with 4 harmonics (weight 0.6**(h-1)) and a 4/3-semitone cos^2 window, summed over frames without per-frame
    normalisation; Pearson correlation against 24 keys for each of the three Faraldo profiles, averaged; the key with
    the highest mean correlation wins. Confidence: margin = best mean correlation minus the second best; agree = how
    many of the three profiles pick the winner on their own; sure = agree == 3 and margin >= MARGIN_SURE."""
    F, M, E, rms, Emax = spectral_peaks(y44)
    return decide(hpcp(F, M, Emax[1 / 3], n_harm=4, whiten=True, frame_norm=False).mean(axis=0))

MARGIN_SURE = 0.08     # set on the dev split (90s + 2000s), see main_score

def decide(pcp, profiles=FARALDO):
    rs = [corr24(pcp, km(p)) for p in profiles]; r = sum(rs) / len(rs); o = np.argsort(-r)
    margin = float(r[o[0]] - r[o[1]]); agree = sum(int(np.argmax(x)) == o[0] for x in rs)
    return cam24(int(o[0])), margin, agree, bool(agree == len(profiles) and margin >= MARGIN_SURE)

# ----------------------------------------------------------------------------------------------- the experiment table
def method_table(tracks, S):
    """name -> (what changed, id -> camelot). Rows in the order the letter reads them."""
    def fz(var, profs, agg="mean", poly=False):
        out = {}
        for t in tracks:
            r = sum(corr24(S[t["id"]][var][agg], km(p, poly)) for p in profs); out[t["id"]] = cam24(int(np.argmax(r)))
        return out
    def vote(var, profs):
        out = {}
        for t in tracks:
            rs = [corr24(S[t["id"]][var]["mean"], km(p)) for p in profs]; ks = Counter(int(np.argmax(x)) for x in rs).most_common()
            top = ks[0][0] if len(ks) == 1 or ks[0][1] > ks[1][1] else int(np.argmax(sum(rs)))
            out[t["id"]] = cam24(top)
        return out
    def winvote(var, profs):
        out = {}
        for t in tracks:
            W = S[t["id"]][var]["wins"]; whole = sum(corr24(S[t["id"]][var]["mean"], km(p)) for p in profs)
            ks = Counter(int(np.argmax(sum(corr24(w, km(p)) for p in profs))) for w in W).most_common() if len(W) else []
            if not ks: out[t["id"]] = cam24(int(np.argmax(whole))); continue
            best = [k for k, n in ks if n == ks[0][1]]; out[t["id"]] = cam24(max(best, key=lambda k: whole[k]))
        return out
    ref = lambda f: {t["id"]: t[f] for t in tracks if t[f]}
    T = [("ref: Essentia KeyExtractor edma (lab vote 1; AGPL, reference only)", "", ref("ess_edma")),
         ("ref: Essentia KeyExtractor bgate (lab vote 2; AGPL, reference only)", "", ref("ess_bgate")),
         ("ref: madmom CNN (lab vote 3; non-commercial weights)", "", ref("madmom")),
         ("ref: Apple Music Understanding", "", ref("mu")),
         ("0 shipped: STFT chroma, edma", "the engine today (key_light stft edma)", fz("stft", ("edma",))),
         ("1a semitone chroma, edma", "own chroma from the semitone spectrum, A440", fz("semi", ("edma",))),
         ("1b + tuning estimate", "semitone grid shifted by the estimated tuning", fz("semi_tuned", ("edma",))),
         ("1c + log compression", "log(1 + 100 x) per semitone before folding", fz("semi_tuned_log", ("edma",))),
         ("1d bass only (below E3)", "semitones E1..D#3 only", fz("semi_tuned_bass", ("edma",))),
         ("1e no bass (C3 up)", "semitones C3..B7 only", fz("semi_tuned_above_c3", ("edma",))),
         ("2a HPCP, 1 harmonic, no whitening, edma", "spectral peaks, Gomez window, frames max-normalised", fz("hpcp_h1_none_fn", ("edma",))),
         ("2b HPCP, 4 harmonics, no whitening, edma", "", fz("hpcp_h4_none_fn", ("edma",))),
         ("2c HPCP, 4 harmonics, whitened 1/6 oct, edma", "running-max envelope +-1/6 octave", fz("hpcp_h4_e6", ("edma",))),
         ("2d HPCP, 4 harmonics, whitened 1/3 oct, edma", "+-1/3 octave", fz("hpcp_h4_e3", ("edma",))),
         ("2e HPCP, 4 harmonics, whitened 1/2 oct, edma", "+-1/2 octave", fz("hpcp_h4_e2", ("edma",))),
         ("2f HPCP 2d, frames max-normalised", "", fz("hpcp_h4_e3_fn", ("edma",))),
         ("2g HPCP 2d + tuning estimate", "reference frequency from the tuning estimate", fz("hpcp_h4_e3_tuned", ("edma",))),
         ("2h HPCP 2d, 8 harmonics", "", fz("hpcp_h8_e3", ("edma",))),
         ("2i HPCP 2d, 1 harmonic", "", fz("hpcp_h1_e3", ("edma",))),
         ("2j HPCP 2d, Gomez polyphonic edma profile", "three-chord polyphonic profile, 4 harmonics, slope 0.6", fz("hpcp_h4_e3", ("edma",), poly=True)),
         ("3a HPCP 2d, bgate", "", fz("hpcp_h4_e3", ("bgate",))),
         ("3b HPCP 2d, braw", "", fz("hpcp_h4_e3", ("braw",))),
         ("3c HPCP 2d, krumhansl", "", fz("hpcp_h4_e3", ("krumhansl",))),
         ("3d HPCP 2d, shaath", "", fz("hpcp_h4_e3", ("shaath",))),
         ("3e HPCP 2d, temperley", "", fz("hpcp_h4_e3", ("temperley",))),
         ("3f HPCP 2d, mean correlation over edma, bgate, braw  [RECOMMENDED]", "the three Faraldo profiles averaged", fz("hpcp_h4_e3", FARALDO)),
         ("3g HPCP 2d, majority of edma, bgate, braw", "one vote each, ties to 3f", vote("hpcp_h4_e3", FARALDO)),
         ("3h HPCP 2d, mean over all six profiles", "", fz("hpcp_h4_e3", ("krumhansl", "temperley", "shaath", "edma", "bgate", "braw"))),
         ("3i 3f on STFT chroma", "profiles ensemble without the whitened HPCP", fz("stft", FARALDO)),
         ("3j 3f with 8 harmonics", "", fz("hpcp_h8_e3", FARALDO)),
         ("3k 3f, peaks below 100 Hz ignored", "high-pass at 100 Hz", fz("hpcp_h4_e3_hp100", FARALDO)),
         ("3l 3f, peaks below 200 Hz ignored", "high-pass at 200 Hz (Faraldo 2017)", fz("hpcp_h4_e3_hp200", FARALDO)),
         ("3m 3f, 1-semitone cosine window", "Essentia's documented HPCP default window", fz("hpcp_h4_e3_w1cos", FARALDO)),
         ("4a 3f, frames weighted by RMS", "", fz("hpcp_h4_e3", FARALDO, "rmsw")),
         ("4b 3f, frames 30 dB below median dropped", "", fz("hpcp_h4_e3", FARALDO, "loud")),
         ("4c 3f, middle 60 percent of the track", "", fz("hpcp_h4_e3", FARALDO, "mid")),
         ("4d 3f, majority over 30 s windows (hop 15 s)", "ties to the whole-track score", winvote("hpcp_h4_e3", FARALDO))]
    return T

def main_score():
    tracks = load_tracks(); S = all_summaries(tracks)
    # the bench's baseline: reproduce 74.6 percent from the engine's own run before anything else
    bench = json.load(open(os.path.join(HERE, "..", "docs", "architecture", "bench", "pc-engine-2026-10-28-mac.json")))["tracks"]
    bk = {b["id"]: b["key_engine"] for b in bench}
    b = score(tracks, bk, "lab"); print(f"bench file, engine key vs lab confident: exact {b['exact']*100:.1f} neighbour {b['neighbour']*100:.1f} other {b['other']*100:.1f} (n {b['n']})")
    T = method_table(tracks, S)
    same = sum(1 for t in tracks if T[4][2][t["id"]] == bk[t["id"]]); print(f"row 0 reproduces the engine's key on {same} of {len(tracks)} tracks")
    dev = [t for t in tracks if t["split"] == "dev"]; ho = [t for t in tracks if t["split"] != "dev"]
    rows = []; base = T[4][2]
    print(f"\n{'method':70} {'lab: exact nbr other':>22} {'Apple: exact nbr other':>24} {'dev/held-out exact (lab)':>26}")
    for name, what, keys in T:
        a, m = score(tracks, keys, "lab"), score(tracks, keys, "mu")
        ad, ah, md, mh = score(dev, keys, "lab"), score(ho, keys, "lab"), score(dev, keys, "mu"), score(ho, keys, "mu")
        bk_ = buckets(tracks, keys)
        row = {"method": name, "change": what, "n_lab": a["n"], "n_apple": m["n"]}
        for tag, sc in (("lab", a), ("apple", m)):
            for k in ("exact", "neighbour", "other", "relative", "fifth", "parallel", "tritone", "two_fifths", "rest", "major_as_minor", "minor_as_major"):
                row[f"{tag}_{k}"] = round(sc[k] * 100, 1)
        row.update({"lab_exact_dev": round(ad["exact"] * 100, 1), "lab_exact_heldout": round(ah["exact"] * 100, 1),
                    "apple_exact_dev": round(md["exact"] * 100, 1), "apple_exact_heldout": round(mh["exact"] * 100, 1)})
        for k, v in bk_.items():
            if k.startswith("split") or k == "era=?": continue
            row[f"lab_exact_{k}"] = round(v[0] * 100, 1); row[f"apple_exact_{k}"] = round(v[2] * 100, 1)
        rows.append(row)
        print(f"{name[:70]:70} {a['exact']*100:6.1f} {a['neighbour']*100:5.1f} {a['other']*100:5.1f}    {m['exact']*100:6.1f} {m['neighbour']*100:5.1f} {m['other']*100:5.1f}    {ad['exact']*100:5.1f} / {ah['exact']*100:5.1f}")
    out = os.path.join(HERE, "key_parity_results.tsv")
    with open(out, "w") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), delimiter="\t"); w.writeheader(); w.writerows(rows)
    # buckets: the recommended method's gain over the shipped one, per bucket (flag any bucket with no gain)
    rec = [r for r in rows if "RECOMMENDED" in r["method"]][0]; b0 = rows[4]
    print("\ngain of the recommended method over the shipped one, per bucket (exact, points; lab / Apple):")
    for k in rec:
        if k.startswith("lab_exact_") and "=" in k:
            kk = k[len("lab_exact_"):]; print(f"  {kk:18} {rec[k] - b0[k]:+5.1f} / {rec['apple_exact_' + kk] - b0['apple_exact_' + kk]:+5.1f}")
    # confidence: choose the margin threshold on dev (the tercile boundary below which accuracy drops), report held-out
    keys = {}; meta = {}
    for t in tracks:
        k, mg, ag, _ = decide(S[t["id"]]["hpcp_h4_e3"]["mean"]); keys[t["id"]] = k; meta[t["id"]] = (mg, ag)
    devc = [t for t in dev if t["conf"] >= 0.65]
    q = float(np.quantile([meta[t["id"]][0] for t in devc], 1 / 3))
    print(f"\nconfidence: dev lower-tercile margin {q:.3f} (MARGIN_SURE = {MARGIN_SURE})")
    for name, sub, refk in (("dev, lab", [t for t in dev if t["conf"] >= 0.65], "lab"), ("held-out, lab", [t for t in ho if t["conf"] >= 0.65], "lab"),
                            ("dev, Apple", [t for t in dev if t["mu"]], "mu"), ("held-out, Apple", [t for t in ho if t["mu"]], "mu")):
        sure = [t for t in sub if meta[t["id"]][1] == 3 and meta[t["id"]][0] >= MARGIN_SURE]; uns = [t for t in sub if t not in sure]
        acc = lambda L: (sum(keys[t["id"]] == t[refk] for t in L) / len(L) * 100) if L else float("nan")
        print(f"  {name:16} sure {len(sure):3} tracks exact {acc(sure):5.1f} | unsure {len(uns):3} tracks exact {acc(uns):5.1f}")
    print("wrote", out)

def main_check():
    """Cost and consistency: the recommended method straight from audio on ten tracks, against the cached path."""
    tracks = load_tracks()[:10]; cands = {c["id"]: c for c in json.load(open(os.path.join(HERE, "candidates.json")))}
    S = all_summaries(load_tracks())
    for t in tracks:
        t0 = time.time(); y, _ = load44(cands[t["id"]]["path"]); t1 = time.time(); k, mg, ag, sure = recommended(y); t2 = time.time()
        kc = decide(S[t["id"]]["hpcp_h4_e3"]["mean"])[0]
        print(f"  {t['title'][:36]:36} {k:>3} (cached {kc:>3}, lab {t['lab']:>3}, Apple {t['mu'] or '-':>3}) margin {mg:.3f} agree {ag} sure {sure}  decode {t1-t0:.1f} s, key {t2-t1:.2f} s")

def main_keys():
    """The recommended method's decision per track (row 3f), for the engine's parity column: id, Camelot key, the
    margin over the second key, how many of the three profiles agreed, the sure flag, and the lab's and Apple's keys."""
    tracks = load_tracks(); S = all_summaries(tracks)
    path = os.path.join(HERE, "key_parity_keys.tsv")
    with open(path, "w") as f:
        f.write("id\tkey_3f\tmargin\tagree\tsure\tlab\tlab_confident\tapple\n")
        for t in tracks:
            k, mg, ag, sure = decide(S[t["id"]]["hpcp_h4_e3"]["mean"])
            f.write(f"{t['id']}\t{k}\t{mg:.4f}\t{ag}\t{int(sure)}\t{t['lab']}\t{int(t['conf'] >= 0.65)}\t{t['mu'] or ''}\n")
    print("wrote", path, len(tracks), "rows")

if __name__ == "__main__":
    a = sys.argv
    if len(a) > 1 and a[1] == "extract":
        extract(int(a[a.index("--jobs") + 1]) if "--jobs" in a else 6, int(a[a.index("--limit") + 1]) if "--limit" in a else 10**6)
    elif len(a) > 1 and a[1] == "score": main_score()
    elif len(a) > 1 and a[1] == "check": main_check()
    elif len(a) > 1 and a[1] == "keys": main_keys()
    else: print(__doc__)
