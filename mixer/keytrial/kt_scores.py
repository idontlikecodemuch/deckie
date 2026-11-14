#!/usr/bin/env python3
"""Research X3, kind (a): public-domain scores rendered with our own synthesiser voices. A SUPPLEMENT, never used to
choose or to score anything.

  python kt_scores.py [--jobs 2]      -> $DECKIE_KT_CACHE/made/s<i>.npz (features only)

The scores are J. S. Bach's four-part chorales as encoded in the music21 corpus (the compositions are in the public
domain; the corpus's licence note says some of its encodings carry their own terms, so a shipped model would take the
notes from an encoding that is plainly public domain or CC0, such as the Open Well-Tempered Clavier's score). Each
chorale's first 24 s (at a tempo drawn from 80 to 130 quarter notes a minute) are played by four additive voices of
kt_made.py with a kick on every beat and hats between, at a random detune.

The key is read from the score, not from any audio or key-finding rule: the home note is the last bass note; the mode
is major when that note is the key signature's major home note, minor when it is its relative minor, and otherwise
(a modal chorale) by which third above the home note the signature's scale holds."""
import os, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np
import kt_made as M

def score_key(sharps, last_bass_pc):
    maj = (7 * sharps) % 12; scale = {(maj + d) % 12 for d in (0, 2, 4, 5, 7, 9, 11)}
    if last_bass_pc == maj: return maj
    if last_bass_pc == (maj + 9) % 12: return last_bass_pc + 12
    return last_bass_pc + (12 if (last_bass_pc + 3) % 12 in scale and (last_bass_pc + 4) % 12 not in scale else 0)

def one(item):
    i, path = item
    import kt, kt_three as T, kt_extract as KE
    from music21 import converter
    out = os.path.join(kt.CACHE, "made", f"s{i}.npz")
    if os.path.exists(out): return i, None
    try:
        s = converter.parse(path); parts = list(s.parts)
        if len(parts) < 4: return i, "fewer than four parts"
        ks = parts[0].flatten().getElementsByClass("KeySignature")
        if not ks: return i, "no key signature"
        notes = [[(float(n.offset), float(n.quarterLength), n.pitch.midi) for n in p.flatten().notes if n.isNote] for p in parts[:4]]
        if not notes[3]: return i, "no bass"
        key = score_key(ks[0].sharps, notes[3][-1][2] % 12)
        rng = np.random.default_rng(5000 + i); q = 60 / float(rng.uniform(80, 130)); det = float(rng.uniform(-0.3, 0.3)); n = M.SR * M.SECONDS
        y = np.zeros(n)
        for v, part in enumerate(notes):
            p, odd = float(rng.uniform(0.7, 1.8)), rng.random() < 0.25; lv = float(rng.uniform(0.4, 0.9))
            for off, dur, midi in part:
                if off * q >= M.SECONDS: break
                M.tone(y, off * q, dur * q * 0.95, midi - (12 if v == 3 else 0), lv, p, odd, det, attack=0.01)
        lv = float(rng.uniform(0.4, 1.0))
        for b in range(int(M.SECONDS / q)):
            a = int(b * q * M.SR); m = min(n - a, int(0.25 * M.SR)); tt = np.arange(m) / M.SR
            y[a:a + m] += lv * 1.5 * np.exp(-tt * 18) * np.sin(2 * np.pi * (45 * tt + 75 / 30 * (1 - np.exp(-tt * 30))))
            a = int((b + 0.5) * q * M.SR)
            if a < n: m = min(n - a, int(0.04 * M.SR)); y[a:a + m] += lv * 0.25 * rng.standard_normal(m) * np.exp(-np.arange(m) / (0.008 * M.SR))
        y = (0.5 * y / (np.abs(y).max() + 1e-9)).astype(np.float32)
        t = np.zeros(24, np.float32); t[key] = 1; r = T.read(y)
        np.savez_compressed(out, pa=r["pa"], pb=r["pb"], target=t, kind="score", L=KE.logspec(y).astype(np.float16))
        return i, None
    except Exception as ex:
        return i, str(ex)

if __name__ == "__main__":
    import kt
    from music21 import corpus
    a = sys.argv; jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 2
    paths = sorted(str(p) for p in corpus.getComposer("bach") if "bwv" in str(p).lower())
    os.makedirs(os.path.join(kt.CACHE, "made"), exist_ok=True)
    from multiprocessing import Pool
    with Pool(jobs) as pool: res = list(pool.imap_unordered(one, list(enumerate(paths)), chunksize=4))
    bad = [(i, e) for i, e in res if e]
    print(f"chorales {len(paths)}, rendered {len(res) - len(bad)}, left out {len(bad)} {bad[:4]}")
