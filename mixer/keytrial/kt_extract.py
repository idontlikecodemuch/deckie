#!/usr/bin/env python3
"""Key trial: one decode per clip, three caches in $DECKIE_KT_CACHE/feat/<id>.npz.

  python kt_extract.py [--jobs 4] [--sets mtg,gs,gsplus] [--limit N]

  F, M, E   spectral peaks of letter R's reader (key_parity.spectral_peaks): frequency, magnitude and the running-max
            envelope over +-1/3 octave, (T, 60) per 93 ms frame. Row 3f and the harmonic discount are computed from these.
  notes     approximate note transcription (key_overtones.nnls_notes, s = 0.7, the row letter R chose): (T, 84)
            activations of the notes A0..G#7 on the same 93 ms frames, and the tuning.
  L         log-frequency spectrogram for the trained model: mono 44.1 kHz, Hann frames of 16,384 samples (0.37 s; 2.7 Hz
            bins, so semitones are resolved down to about 45 Hz), 5 frames a second, triangular filters 24 to the
            octave, log(1 + magnitude). 148 bins from 36.7 Hz: the model reads 126 of them (55 Hz to 2,093 Hz at no
            shift) and the 22 spare bins let a clip be read 4 semitones lower to 7 higher by moving the window, which is
            how pitch-shift augmentation is done without touching the audio."""
import os, sys, time, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt
import key_parity as KP
import key_overtones as KO
KO.S_VALUES = {"s07": 0.7}          # only the dictionary letter R chose (the function loops over this table)

SR, NL, HL = 44100, 16384, 8820
BPO, NB_MODEL, SHIFT_LO, SHIFT_HI = 24, 126, -4, 7
NB_ALL = NB_MODEL + 2 * (SHIFT_HI - SHIFT_LO)                # 148
F0 = 55.0 * 2 ** (-SHIFT_HI / 12)                            # centre of bin 0 (36.7 Hz)
BASE = 2 * SHIFT_HI                                          # first bin the model reads at no shift (55 Hz)

_FB = None
def filterbank():
    """(NB_ALL, NL/2+1) triangular filters on a log-frequency axis, each normalised to sum 1. Where a filter is narrower
    than one FFT bin it takes the two bins around its centre by linear interpolation."""
    global _FB
    if _FB is not None: return _FB
    fc = F0 * 2 ** (np.arange(-1, NB_ALL + 1) / BPO); k = np.arange(NL // 2 + 1) * SR / NL
    W = np.zeros((NB_ALL, len(k)))
    for j in range(NB_ALL):
        lo, c, hi = fc[j], fc[j + 1], fc[j + 2]
        w = np.clip(np.minimum((k - lo) / (c - lo), (hi - k) / (hi - c)), 0, None)
        kc = c * NL / SR; i0 = int(np.floor(kc)); fr = kc - i0
        if w.sum() < 0.5: w = np.zeros(len(k)); w[i0] = 1 - fr; w[i0 + 1] = fr
        W[j] = w / w.sum()
    _FB = W.astype(np.float32); return _FB

def logspec(y):
    pad = NL // 2; y = np.concatenate([np.zeros(pad, np.float32), y, np.zeros(pad, np.float32)])
    n = 1 + (len(y) - NL) // HL
    win = np.hanning(NL + 1)[:-1].astype(np.float32)
    fr = np.lib.stride_tricks.sliding_window_view(y, NL)[::HL][:n] * win
    X = np.abs(np.fft.rfft(fr, axis=1)).astype(np.float32)
    return np.log1p(X @ filterbank().T)

def one(item):
    cid, path = item
    dst = os.path.join(kt.CACHE, "feat", cid + ".npz")
    if os.path.exists(dst): return cid, "cached", 0.0
    t0 = time.time()
    try:
        y, _ = KP.load44(path)
        F, M, E, rms, Emax = KP.spectral_peaks(y)
        notes, tun = KO.nnls_notes(y, F.shape[0])
        np.savez_compressed(dst + ".tmp.npz", F=F, M=M, E=Emax[1 / 3].astype(np.float32), notes=notes["s07"].astype(np.float16),
                            tuning=np.float32(tun), L=logspec(y).astype(np.float16), dur=np.float32(len(y) / SR))
        os.replace(dst + ".tmp.npz", dst)
        return cid, "ok", time.time() - t0
    except Exception as e:
        return cid, f"error {e}", time.time() - t0

def main():
    a = sys.argv
    jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4
    sets = a[a.index("--sets") + 1].split(",") if "--sets" in a else ["mtg", "gs", "gsplus"]
    limit = int(a[a.index("--limit") + 1]) if "--limit" in a else 10 ** 9
    os.makedirs(os.path.join(kt.CACHE, "feat"), exist_ok=True)
    todo = {}
    for s in sets:
        for c in kt.load(s)[:limit]: todo.setdefault(c["id"], c["path"])
    todo = sorted(todo.items(), key=lambda x: int(x[0]))
    from multiprocessing import Pool
    t0 = time.time(); cpu = []; errs = []
    with Pool(jobs) as pool:
        for k, (cid, st, dt) in enumerate(pool.imap_unordered(one, todo, chunksize=2), 1):
            if st == "ok": cpu.append(dt)
            if st.startswith("error"): errs.append((cid, st))
            if k % 100 == 0: print(f"{k}/{len(todo)} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    print(f"clips {len(todo)}, extracted {len(cpu)}, errors {len(errs)} {errs[:3]}, wall {time.time() - t0:.0f}s, "
          f"mean {np.mean(cpu) if cpu else 0:.2f}s a clip per worker")

if __name__ == "__main__":
    main()
