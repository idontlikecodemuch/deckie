#!/usr/bin/env python3
"""The three-answer key reader, reference for the Swift port (core/Sources/DeckieCore/Key/ThreeAnswerKey.swift).

  python kt_three.py expected [--jobs 4]     every clip of the three sets -> three_answer_expected.tsv (committed) and
                                             $DECKIE_KT_CACHE/three_ref.npz (the 24 scores of each row, for diffing)
  python kt_three.py parity <tool>           decodes every clip, pipes its samples to the Swift tool
                                             (`swift run -c release deckie-keyparity`), and compares answers with
                                             three_answer_expected.tsv
  python kt_three.py fixture <out.json>      the small generated fixture for the Swift test (no downloaded audio)

The reader (research X2, section 5.1; nothing trained, nothing fitted):
  row A   letter R's whitened 4-harmonic HPCP per 93 ms frame; from each frame, each pitch class loses 0.36 of the
          class a fifth below and 0.1296 of the class a major third below (floor 0); frames summed
  row B   note transcription: audio at 11,025 Hz, Hamming frames of 4,096 (hop 1,024, 1,536 zeros in front), a
          log-frequency spectrum of 256 bins a third of a semitone apart, one tuning per song, running mean and
          deviation over 37 bins, a non-negative least-squares fit of 84 note templates per frame, activations
          summed over the song and folded to 12 pitch classes
  scores  for each row, the mean over Faraldo's three profiles of the Pearson correlation with each of the 24 keys
  answer  home = row B's best key's home note. 'key' when row A's best key has the same home note and rows A and B
          name the same mode on it (minor when the minor score on that home note is the larger): the key is that home
          note and mode. 'home' (home note, mode open) when the home notes agree and the modes do not. Otherwise 'none'.

This differs from the trial's stored readers in three places, none a change of method: the 11,025 Hz audio comes from
the core's own resampler design (a Kaiser-windowed sinc measured from soxr's HQ filter, core/Sources/DeckieCore/DSP/
Resampler.swift) instead of soxr itself, so that Swift and Python read the same samples; and the per-frame profiles
and note activations are kept in double precision instead of the trial's float32 and float16 caches. `expected` prints
how many answers change against the trial's."""
import os, sys, json, struct, subprocess, time, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt
import key_parity as KP
import key_overtones as KO

# ---- the core's 44.1 kHz -> 11,025 Hz resampler (Resampler(from: 44100, to: 11025), design soxrHQ)
CUTOFF, BETA, HALF = 0.956872, 13.04, 97.25
def decimator_taps():
    unit = 4.0; half_width = HALF * unit; fc = CUTOFF / (2 * unit); reach = int(np.floor(half_width))
    u = np.arange(0, reach + 1, dtype=np.float64)
    r = u / half_width
    win = np.where(u < half_width, np.i0(BETA * np.sqrt(np.clip(1 - r * r, 0, None))) / np.i0(BETA), 0.0)
    a = np.pi * 2 * fc * np.where(u == 0, 1, u)
    h = np.where(u == 0, win, np.sin(a) / a * win)
    h = np.concatenate([h[:0:-1], h])                 # u = -reach .. reach
    return (h / h.sum()).astype(np.float32), reach

_TAPS = None
def decimate4(y):
    """out[k] = sum_m h[m] y[4k + m], zeros outside; ceil(n / 4) samples (librosa's length), float32."""
    global _TAPS
    if _TAPS is None: _TAPS = decimator_taps()
    h, reach = _TAPS; n = len(y); count = (n + 3) // 4
    full = np.convolve(y.astype(np.float64), h[::-1].astype(np.float64), mode="full")    # full[i] = sum_m h[m] y[i - reach + m]
    out = full[reach + 4 * np.arange(count)]
    computed = (2 * n + 4) // 8                        # soxr's own length, n / 4 rounded half up; the rest are zeros
    out[computed:] = 0
    return out.astype(np.float32)

def notes_b(y44, n_frames):
    """key_overtones.nnls_notes with the dictionary s = 0.7 only and the resampler above; (T, 84) float64."""
    from scipy.optimize import nnls
    y = decimate4(y44)
    need = (n_frames - 1) * KO.H_B + KO.N_B
    y = np.concatenate([np.zeros(KO.PAD_B, np.float32), y])
    if len(y) < need: y = np.concatenate([y, np.zeros(need - len(y), np.float32)])
    fr = np.lib.stride_tricks.sliding_window_view(y, KO.N_B)[::KO.H_B][:n_frames] * np.hamming(KO.N_B).astype(np.float32)
    X = np.abs(np.fft.rfft(fr, axis=1))
    Y = X @ KO.logfreq_matrix().T
    top = int(round(KO.NNOTE * 0.62)) * KO.NBPS + 1
    e = Y[:, :top].sum(axis=0); ang = np.angle(np.sum(e * np.exp(2j * np.pi * np.arange(top) / KO.NBPS)))
    tun = ang / (2 * np.pi); shift = tun * KO.NBPS; i0 = int(np.floor(shift)); fs = shift - i0
    idx = np.arange(KO.NBIN); a = np.clip(idx + i0, 0, KO.NBIN - 1); b = np.clip(idx + i0 + 1, 0, KO.NBIN - 1)
    Yt = Y[:, a] * (1 - fs) + Y[:, b] * fs
    mu, sd = KO.hamming_running(Yt)
    Ys = np.where((Yt - mu > 0) & (sd > 0), (Yt - mu) / np.where(sd > 0, sd, 1), 0.0)
    bands = np.stack([Ys[:, 3 + 3 * n - 1:3 + 3 * n + 2].sum(axis=1) for n in range(KO.NNOTE)], axis=1)
    D = KO.dictionary("s07"); out = np.zeros((n_frames, KO.NNOTE))
    for t in range(n_frames):
        sig = np.nonzero(bands[t] > 0)[0]
        if len(sig): out[t, sig] = nnls(D[:, sig], Ys[t], maxiter=2000)[0]
    return out, float(tun)

def scores24(pcp): return sum(KP.corr24(pcp, KP.km(p)) for p in KP.FARALDO) / len(KP.FARALDO)

def read(y44):
    """the reader on mono 44.1 kHz float32 audio: dict with answer, key (0..23 or -1), home (0..11 or -1), scores."""
    empty = {"answer": "none", "key": -1, "home": -1, "sa": np.zeros(24), "sb": np.zeros(24), "pa": np.zeros(12), "pb": np.zeros(12), "tuning": 0.0, "frames": 0}
    if len(y44) < KP.N44: return empty
    F, M, E, rms, Emax = KP.spectral_peaks(y44)
    if F.shape[0] == 0: return {"answer": "none", "key": -1, "home": -1, "sa": np.zeros(24), "sb": np.zeros(24), "pa": np.zeros(12), "pb": np.zeros(12), "tuning": 0.0, "frames": 0}
    H = KP.hpcp(F, M, Emax[1 / 3], n_harm=4, whiten=True, frame_norm=False)
    pa = KO.discount(H, "both").sum(axis=0)
    N, tun = notes_b(y44, F.shape[0])
    pb = np.zeros(12); np.add.at(pb, (np.arange(84) + 21) % 12, N.sum(axis=0))
    sa, sb = scores24(pa), scores24(pb)
    return dict(decide(sa, sb), sa=sa, sb=sb, pa=pa, pb=pb, tuning=tun, frames=F.shape[0])

def decide(sa, sb):
    ka, kb = int(np.argmax(sa)), int(np.argmax(sb)); t = kb % 12
    if not (np.any(sa != 0) and np.any(sb != 0)) or ka % 12 != t: return {"answer": "none", "key": -1, "home": -1}
    ma, mb = bool(sa[12 + t] > sa[t]), bool(sb[12 + t] > sb[t])
    if ma == mb: return {"answer": "key", "key": t + 12 * ma, "home": t}
    return {"answer": "home", "key": -1, "home": t}

def one(item):
    cid, path = item
    try:
        y, sr = KP.load44(path); r = read(y); r["sr"] = sr; return cid, r, None
    except Exception as ex:
        return cid, None, str(ex)

def clips():
    out = {}
    for s in ("mtg", "gs", "gsplus"):
        for c in kt.load(s): out.setdefault(c["id"], (s, c))
    return out

EXPECTED = os.path.join(kt.HERE, "three_answer_expected.tsv")
def name(k): return "" if k < 0 else kt.key_name(k)

def main_expected(jobs):
    from multiprocessing import Pool
    C = clips(); todo = sorted(((i, c["path"]) for i, (_, c) in C.items()), key=lambda x: int(x[0]))
    res = {}; t0 = time.time()
    with Pool(jobs) as pool:
        for k, (cid, r, err) in enumerate(pool.imap_unordered(one, todo, chunksize=2), 1):
            if err: print("error", cid, err, file=sys.stderr)
            else: res[cid] = r
            if k % 200 == 0: print(f"{k}/{len(todo)} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    ids = [i for i, _ in todo if i in res]
    np.savez_compressed(os.path.join(kt.CACHE, "three_ref.npz"), ids=np.array(ids), sa=np.array([res[i]["sa"] for i in ids]), sb=np.array([res[i]["sb"] for i in ids]),
                        pa=np.array([res[i]["pa"] for i in ids]), pb=np.array([res[i]["pb"] for i in ids]), tuning=np.array([res[i]["tuning"] for i in ids]))
    with open(EXPECTED, "w") as fh:
        fh.write("set\tid\tanswer\tkey\thome\n")
        for i in ids:
            r = res[i]; fh.write(f"{C[i][0]}\t{i}\t{r['answer']}\t{name(r['key'])}\t{'' if r['home'] < 0 else kt.NOTE[r['home']]}\n")
    print(f"clips {len(ids)}; sample rates {sorted(set(res[i]['sr'] for i in ids))}; answers: " + ", ".join(f"{a} {sum(res[i]['answer'] == a for i in ids)}" for a in ("key", "home", "none")))
    # against the trial's stored readers (soxr, float32 and float16 caches)
    diff = 0; tot = 0
    for s in ("mtg", "gs", "gsplus"):
        z = np.load(os.path.join(kt.CACHE, f"readers_{s}.npz"))
        for j, i in enumerate(z["ids"]):
            if i not in res or C[i][0] != s: continue
            d = decide(z["A"][j].astype(float), z["B"][j].astype(float)); tot += 1
            if (d["answer"], d["key"], d["home"]) != (res[i]["answer"], res[i]["key"], res[i]["home"]):
                diff += 1; print(f"  differs from the trial: {s} {i}: trial {d['answer']} {name(d['key'])}, reference {res[i]['answer']} {name(res[i]['key'])}")
    print(f"answers that differ from the trial's stored readers: {diff} of {tot}")

def main_parity(tool):
    exp = {r.split("\t")[1]: r.rstrip("\n").split("\t") for r in open(EXPECTED).read().splitlines()[1:]}
    C = clips(); p = subprocess.Popen(tool.split(), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    same = 0; bad = []; t0 = time.time(); secs = 0.0
    for k, i in enumerate(sorted(exp, key=int), 1):
        y, _ = KP.load44(C[i][1]["path"])
        t1 = time.time()
        p.stdin.write(struct.pack("<q", len(y))); p.stdin.write(y.astype("<f4").tobytes()); p.stdin.flush()
        got = p.stdout.readline().decode().rstrip("\n").split("\t"); secs += time.time() - t1
        if got[:3] == exp[i][2:5]: same += 1
        else: bad.append((i, exp[i][2:5], got))
        if k % 200 == 0: print(f"{k}/{len(exp)} same {same} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    p.stdin.write(struct.pack("<q", -1)); p.stdin.close(); p.wait()
    print(f"clips {len(exp)}, the Swift reader's answer equals the Python reference's on {same}; Swift time {secs / len(exp):.3f} s a clip (pipe included)")
    for b in bad[:40]: print("  differs:", b)

def synth(seed, chords, seconds=20):
    """A generated clip in whole-number arithmetic only, so that Swift and Python make the very same samples with no
    audio file: a chord every two seconds; each note a sawtooth from a 32-bit phase counter (phase = inc * i mod 2^32,
    value = (phase >> 16) - 32768) times its weight; the sum times a falling envelope (65536 - l * 43690 / 88200 for
    sample l of the chord, then >> 16), then >> 5; plus noise from a linear congruential generator
    (s = s * 1664525 + 1013904223 mod 2^32; (s >> 20) - 2048, >> 2 when there are notes). 16-bit samples."""
    n = seconds * 44100; i = np.arange(n, dtype=np.uint64); l = (i % 88200).astype(np.int64)
    env = 65536 - (l * 43690) // 88200
    acc = np.zeros(n, np.int64); ci = ((i // 88200) % max(1, len(chords))).astype(np.int64)
    for c, notes in enumerate(chords):
        on = ci == c
        for inc, amp in notes:
            ph = (np.uint64(inc) * i) & np.uint64(0xFFFFFFFF)
            acc[on] += amp * ((ph[on] >> np.uint64(16)).astype(np.int64) - 32768)
    v = ((acc * env) >> 16) >> 5
    st = seed; nz = np.zeros(n, np.int64)
    for k in range(n):
        st = (st * 1664525 + 1013904223) & 0xFFFFFFFF; nz[k] = (st >> 20) - 2048
    has = any(len(c) for c in chords)
    out = np.clip(v + (nz >> 2 if has else nz), -32768, 32767)
    return (out / 32768.0).astype(np.float32)

def inc_of(midi, detune=0.0): return int(round(440.0 * 2 ** ((midi - 69 + detune) / 12) * 2 ** 32 / 44100))

FIXTURE_CLIPS = [
    ("a-minor", 1, [[33, 57, 60, 64], [29, 53, 57, 60], [31, 55, 59, 62], [33, 57, 60, 64]], 0.0),
    ("c-major", 2, [[36, 60, 64, 67], [41, 60, 65, 69], [43, 59, 62, 67], [36, 60, 64, 67]], 0.0),
    ("f-sharp-minor-detuned", 3, [[30, 54, 57, 61], [35, 54, 59, 62], [28, 52, 56, 59], [30, 54, 57, 61]], 0.3),
    ("d-bare-fifths", 4, [[26, 50, 57], [26, 50, 57], [31, 55, 62], [26, 50, 57]], 0.0),
    ("e-major-and-minor-thirds", 5, [[28, 52, 56, 59], [28, 52, 55, 59], [33, 57, 60, 64], [35, 59, 63, 66]], 0.0),
    ("b-flat-major", 7, [[34, 58, 62, 65], [39, 58, 63, 67], [41, 57, 60, 65], [34, 58, 62, 65]], -0.2),
    ("noise", 6, [], 0.0),
    ("silence-short", 8, None, 0.0),
]

def main_fixture(out):
    cases = []
    for nm, seed, chords, det in FIXTURE_CLIPS:
        if chords is None: spec = []; y = np.zeros(3000, np.float32); seconds = 0
        else:
            spec = [[(inc_of(m, det), 3 if j == 0 else 2) for j, m in enumerate(ch)] for ch in chords]; seconds = 20
            y = synth(seed, spec, seconds)
        r = read(y); y11 = decimate4(y)
        m = lambda sc: float(np.sort(sc)[-1] - np.sort(sc)[-2])
        cases.append({"name": nm, "seed": seed, "seconds": seconds, "samples": int(len(y)), "chords": [[{"inc": a_, "amp": b_} for a_, b_ in ch] for ch in spec],
                      "checksum": int(np.round(y.astype(np.float64) * 32768).astype(np.int64).sum()), "frames": r["frames"],
                      "answer": r["answer"], "key": r["key"], "home": r["home"], "tuning": r["tuning"],
                      "pcp_a": [float(x) for x in r["pa"]], "pcp_b": [float(x) for x in r["pb"]],
                      "scores_a": [float(x) for x in r["sa"]], "scores_b": [float(x) for x in r["sb"]],
                      "decimated": [float(x) for x in y11[1000:1016]] if len(y11) > 1016 else [], "decimated_count": int(len(y11))})
        t = r["home"]
        print(f"{nm:28} {r['answer']:5} {name(r['key']):10} tuning {r['tuning']:+.3f} margins A {m(r['sa']):.3f} B {m(r['sb']):.3f}" +
              (f" mode A {r['sa'][12 + t] - r['sa'][t]:+.3f} B {r['sb'][12 + t] - r['sb'][t]:+.3f}" if t >= 0 else ""))
    json.dump({"about": "written by mixer/keytrial/kt_three.py fixture: generated clips (whole-number synthesis, no audio file) and the reference reader's values",
               "cases": cases}, open(out, "w"), indent=0)

if __name__ == "__main__":
    a = sys.argv
    if a[1] == "expected": main_expected(int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4)
    elif a[1] == "parity": main_parity(a[2])
    elif a[1] == "fixture": main_fixture(a[2])
