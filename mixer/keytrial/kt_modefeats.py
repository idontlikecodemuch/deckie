#!/usr/bin/env python3
"""Key trial, phase 2: per-clip measurements for the mode experiments, computed once for every possible home note so
that any reader's home note can be plugged in afterwards. Nothing here knows the label.

  python kt_modefeats.py [--jobs 4]      -> $DECKIE_KT_CACHE/modefeats_<set>.npz

Sources per clip (kt_extract): H = row 3f's whitened 4-harmonic HPCP per 93 ms frame; N = the note transcription of
letter R's row B (84 notes A0..G#7, the same frames). Every value below is fixed here, before any score was looked at;
none was tuned. Registers are whole octaves on the piano: bass C1..B2 (MIDI 24-47: the octaves a bass line and a kick
live in), middle C3..B3 (48-59), melody C4..B5 (60-83: the octaves a lead or a vocal lives in).

  c_3f, c_A, c_B     12 values: H summed; H with the third and fifth harmonic shares taken off per frame (row A),
                     summed; N summed and folded to pitch classes (row B)
  r_bass, r_mid, r_mel   N summed inside one register, folded
  bassline           time, not loudness: per frame the strongest bass-register note (frames with none skipped), counted
  topline            per frame the strongest melody-register note, counted
  st_B, st_A         'where the harmony is stable': frame chroma (N folded / discounted H) smoothed over 0.5 s; a frame's
                     stability is its cosine similarity with the frame 0.5 s later; the more stable half of the frames
                     (above the clip's median) summed
  un_B               the other, less stable half (the control)
  chords             24 values: time spent on each major and minor triad. Per frame the smoothed N chroma (1 s) is
                     matched to the 24 binary triad templates (Fujishima 1999) by correlation; frames whose best
                     correlation is below 0.5 (no clear triad) are skipped
  overbass           12 x 12: for each bass-line pitch class, the melody-and-middle chroma (MIDI 48-83) summed over the
                     frames where the bass line sits on it. Row t is 'what sounds above the home note in the bass'
  triad_votes        12 x 3: for each home note t, the number of frames where the home chord sounds (t and its fifth
                     both above the frame's mean pitch-class level, smoothed N chroma) and the minor third is the
                     louder third / the major third is the louder / all such frames"""
import os, sys
import numpy as np
import kt
import key_overtones as KO
from kt_bench import frames

PCS = (np.arange(84) + 21) % 12
MIDI = np.arange(84) + 21
REG = {"bass": (24, 48), "mid": (48, 60), "mel": (60, 84)}
SMOOTH = 5            # frames: 0.46 s
SMOOTH_CH = 11        # frames: 1.0 s

def fold(v, lo=0, hi=200):
    sel = (MIDI >= lo) & (MIDI < hi); c = np.zeros(v.shape[:-1] + (12,))
    for pc in range(12): c[..., pc] = v[..., sel & (PCS == pc)].sum(axis=-1)
    return c

def smooth(X, n):
    k = np.ones(n) / n
    return np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 0, X)

TRIADS = np.zeros((24, 12))
for t in range(12):
    TRIADS[t, [t, (t + 4) % 12, (t + 7) % 12]] = 1; TRIADS[12 + t, [t, (t + 3) % 12, (t + 7) % 12]] = 1
TRIADS_Z = (TRIADS - TRIADS.mean(1, keepdims=True)); TRIADS_Z /= np.linalg.norm(TRIADS_Z, axis=1, keepdims=True)

def stable_split(C):
    S = smooth(C, SMOOTH); a, b = S[:-SMOOTH], S[SMOOTH:]
    cos = (a * b).sum(1) / (np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1) + 1e-12)
    live = np.linalg.norm(a, axis=1) > 0
    if live.sum() < 4: return C.sum(0), C.sum(0)
    med = np.median(cos[live]); hi = live & (cos > med); lo = live & (cos <= med)
    return C[:-SMOOTH][hi].sum(0), C[:-SMOOTH][lo].sum(0)

def one(cid):
    H, N = frames(cid); H = H.astype(np.float64); N = N.astype(np.float64)
    Hd = KO.discount(H, "both"); CB = fold(N)
    out = {"c_3f": H.sum(0), "c_A": Hd.sum(0), "c_B": CB.sum(0)}
    for k, (lo, hi) in REG.items(): out["r_" + k] = fold(N.sum(0), lo, hi)
    for name, (lo, hi) in (("bassline", REG["bass"]), ("topline", REG["mel"])):
        sel = (MIDI >= lo) & (MIDI < hi); X = N[:, sel]; top = X.argmax(1); ok = X.max(1) > 0
        out[name] = np.bincount(PCS[sel][top[ok]], minlength=12).astype(float)
        if name == "bassline": bl = np.where(ok, PCS[sel][top], -1)
    out["st_B"], out["un_B"] = stable_split(CB); out["st_A"], _ = stable_split(Hd)
    S = smooth(CB, SMOOTH_CH); Z = S - S.mean(1, keepdims=True); nz = np.linalg.norm(Z, axis=1)
    R = (Z @ TRIADS_Z.T) / (nz[:, None] + 1e-12); best = R.argmax(1); ok = (R.max(1) >= 0.5) & (nz > 0)
    out["chords"] = np.bincount(best[ok], minlength=24).astype(float)
    up = fold(N, 48, 84); ob = np.zeros((12, 12))
    for b in range(12): ob[b] = up[bl == b].sum(0)
    out["overbass"] = ob
    m = S.mean(1, keepdims=True); tv = np.zeros((12, 3))
    for t in range(12):
        on = (S[:, t] > m[:, 0]) & (S[:, (t + 7) % 12] > m[:, 0])
        d = S[on, (t + 3) % 12] - S[on, (t + 4) % 12]
        tv[t] = [(d > 0).sum(), (d < 0).sum(), on.sum()]
    out["triad_votes"] = tv
    return cid, out

def main():
    a = sys.argv; jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4
    from multiprocessing import Pool
    for name in ("mtg", "gs"):
        ids = [c["id"] for c in kt.load(name) if os.path.exists(os.path.join(kt.CACHE, "feat", c["id"] + ".npz"))]
        with Pool(jobs) as pool: res = dict(pool.imap_unordered(one, ids, chunksize=8))
        keys = list(res[ids[0]])
        np.savez_compressed(os.path.join(kt.CACHE, f"modefeats_{name}.npz"), ids=np.array(ids), **{k: np.array([res[i][k] for i in ids], np.float32) for k in keys})
        print(name, len(ids), "clips", flush=True)

if __name__ == "__main__":
    main()
