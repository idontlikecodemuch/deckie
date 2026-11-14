#!/usr/bin/env python3
"""Research X3: music written by a program of ours to a chosen key, in the manner of dance music. No one's licence is
needed for it, and its key is known by construction. It is a SUPPLEMENT to real audio in a training mix and is never
used to choose or to score anything.

  python kt_made.py [--n 1500] [--jobs 4]     -> $DECKIE_KT_CACHE/made/<i>.npz (features only; no audio is kept)

Each clip is 24 s at 44.1 kHz, mono, made from a seed: a tempo of 100 to 150 beats a minute; a key drawn evenly from the
24; a whole-song detune of up to 30 cents either way; a four-on-the-floor kick, hats and a clap; a bass line; chords
(a pad or stabs); and, two times in three, a lead line. Each pitched part is additive: harmonics h = 1.. with amplitude
h^-p (p drawn per part between 0.7, bright, and 1.8, mellow; one part in four has odd harmonics only), so bright parts
carry the strong fifth harmonic that reads as a major third. Levels of the parts are drawn at random.

Kinds, by share:
  plain      58 %  a four-chord or two-chord loop of the key's own triads (major: I V vi IV, I IV V IV, I vi IV V,
                   I IV; minor: i VI III VII, i iv v i, i VII VI VII, i iv, i VI; the minor's fifth chord is major one
                   time in three), sevenths added one time in three
  one chord  14 %  the home chord throughout (the trial's hard case: no progression to hear)
  no third   14 %  no third anywhere: bass on the home note, chords of home note, fifth and sometimes the minor
                   seventh, lead on home note, fourth, fifth, seventh. LABEL: the home note with the mode open (half
                   major, half minor), since nothing in the audio says which
  relative   14 %  a minor key whose bass sits on the relative major's note in every other bar (the trial's other hard
                   case); labelled minor

Features per clip are the trial's: rows A and B's twelve-note profiles (kt_three.read) and the log-frequency
spectrogram (kt_extract.logspec)."""
import os, sys, warnings
warnings.filterwarnings("ignore")
import numpy as np

SR, SECONDS = 44100, 24
MAJOR, MINOR = [0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10]
PROG = {0: [[0, 4, 5, 3], [0, 3, 4, 3], [0, 5, 3, 4], [0, 3]], 1: [[0, 5, 2, 6], [0, 3, 4, 0], [0, 6, 5, 6], [0, 3], [0, 5]]}
KINDS = (("plain", 0.58), ("one chord", 0.14), ("no third", 0.14), ("relative", 0.14))

def tone(buf, t0, dur, midi, amp, p, odd, detune, attack=0.005, release=0.05, decay=0.0):
    a = int(t0 * SR); n = int(dur * SR)
    if a >= len(buf) or n <= 0: return
    n = min(n, len(buf) - a); t = np.arange(n) / SR
    f = 440.0 * 2 ** ((midi - 69 + detune) / 12)
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (dur - t) / release).clip(0, 1)
    if decay: env = env * np.exp(-t * decay)
    out = np.zeros(n); h = 1
    while f * h < 9000 and h <= 24:
        if not (odd and h % 2 == 0): out += h ** -p * np.sin(2 * np.pi * f * h * t + 0.7 * h)
        h += 1
    buf[a:a + n] += amp * env * out

def make(seed):
    rng = np.random.default_rng(seed)
    kind = rng.choice([k for k, _ in KINDS], p=[w for _, w in KINDS])
    home = int(rng.integers(12)); minor = int(rng.integers(2)); detune = float(rng.uniform(-0.3, 0.3))
    if kind == "relative": minor = 1
    scale = MINOR if minor else MAJOR
    bpm = float(rng.uniform(100, 150)); beat = 60 / bpm; bar = 4 * beat; n = SR * SECONDS
    y = np.zeros(n); nbars = int(np.ceil(SECONDS / bar))
    prog = [0] if kind in ("one chord", "no third") else list(PROG[minor][int(rng.integers(len(PROG[minor])))])
    seventh = rng.random() < 1 / 3; dom_major = minor and rng.random() < 1 / 3
    def chord(deg):
        root = scale[deg]
        if kind == "no third": return [0, 7] + ([10] if seventh else [])
        notes = [root, scale[(deg + 2) % 7] + (12 if deg + 2 >= 7 else 0), scale[(deg + 4) % 7] + (12 if deg + 4 >= 7 else 0)]
        if dom_major and deg == 4: notes[1] = root + 4
        if seventh: notes.append(scale[(deg + 6) % 7] + (12 if deg + 6 >= 7 else 0))
        return notes
    part = lambda: (float(rng.uniform(0.7, 1.8)), rng.random() < 0.25)
    pb, ob = part(); pc, oc = part(); pl, ol = part()
    lv_bass, lv_ch, lv_lead, lv_drum = rng.uniform(0.5, 1.0), rng.uniform(0.25, 0.8), rng.uniform(0.2, 0.7), rng.uniform(0.4, 1.0)
    bass_oct = 36 + home if home < 8 else 24 + home; ch_oct = 60 + home if home < 6 else 48 + home
    bass_pat = int(rng.integers(4)); stabs = rng.random() < 0.5; has_lead = rng.random() < 2 / 3
    lead_scale = [0, 5, 7, 10] if kind == "no third" else ([0, 3, 5, 7, 10] if minor else [0, 2, 4, 7, 9])
    for b in range(nbars):
        t0 = b * bar; deg = prog[b % len(prog)]; notes = chord(deg); root = notes[0] if kind != "no third" else 0
        broot = root
        if kind == "relative" and b % 2 == 1: broot = 3
        # bass
        if bass_pat == 0:
            for k in range(4): tone(y, t0 + (k + 0.5) * beat, beat * 0.45, bass_oct + broot, lv_bass, pb, ob, detune)
        elif bass_pat == 1:
            for k in range(8): tone(y, t0 + k * beat / 2, beat * 0.4, bass_oct + broot + (7 if k % 4 == 3 and kind != "relative" else 0), lv_bass, pb, ob, detune)
        elif bass_pat == 2: tone(y, t0, bar * 0.95, bass_oct + broot, lv_bass, pb, ob, detune)
        else:
            for k in (0, 0.75, 1.5, 2.5, 3.25): tone(y, t0 + k * beat, beat * 0.5, bass_oct + broot + (12 if k == 2.5 else 0), lv_bass, pb, ob, detune)
        # chords
        for m in notes:
            if stabs:
                for k in (0.5, 1.5, 2.5, 3.5): tone(y, t0 + k * beat, beat * 0.3, ch_oct + m, lv_ch, pc, oc, detune, decay=6)
            else:
                tone(y, t0, bar, ch_oct + m, lv_ch * 0.6, pc, oc, detune + 0.07, attack=0.05); tone(y, t0, bar, ch_oct + m, lv_ch * 0.6, pc, oc, detune - 0.07, attack=0.05)
        # lead
        if has_lead:
            for k in range(8):
                if rng.random() < 0.7:
                    m = lead_scale[int(rng.integers(len(lead_scale)))] if rng.random() < 0.5 else notes[int(rng.integers(len(notes)))] % 12
                    tone(y, t0 + k * beat / 2, beat * 0.45, 72 + home + m - (12 if home + m > 12 else 0), lv_lead, pl, ol, detune, decay=3)
        # drums
        for k in range(4):
            a = int((t0 + k * beat) * SR)
            if a < n:
                m = min(n - a, int(0.25 * SR)); tt = np.arange(m) / SR
                y[a:a + m] += lv_drum * 1.5 * np.exp(-tt * 18) * np.sin(2 * np.pi * (45 * tt + 75 / 30 * (1 - np.exp(-tt * 30))))
            a = int((t0 + (k + 0.5) * beat) * SR)
            if a < n:
                m = min(n - a, int(0.04 * SR)); y[a:a + m] += lv_drum * 0.25 * rng.standard_normal(m) * np.exp(-np.arange(m) / (0.008 * SR))
            if k % 2 == 1:
                a = int((t0 + k * beat) * SR)
                if a < n:
                    m = min(n - a, int(0.15 * SR)); y[a:a + m] += lv_drum * 0.5 * rng.standard_normal(m) * np.exp(-np.arange(m) / (0.03 * SR))
    y = (0.5 * y / (np.abs(y).max() + 1e-9)).astype(np.float32)
    target = np.zeros(24, np.float32)
    if kind == "no third": target[home] = 0.5; target[12 + home] = 0.5
    else: target[home + 12 * minor] = 1.0
    return y, target, str(kind)

def one(i):
    import kt, kt_three as T, kt_extract as KE
    out = os.path.join(kt.CACHE, "made", f"{i}.npz")
    if os.path.exists(out): return i
    y, target, kind = make(1000 + i); r = T.read(y)
    np.savez_compressed(out, pa=r["pa"], pb=r["pb"], target=target, kind=kind, L=KE.logspec(y).astype(np.float16))
    return i

if __name__ == "__main__":
    import kt
    a = sys.argv; n = int(a[a.index("--n") + 1]) if "--n" in a else 1500; jobs = int(a[a.index("--jobs") + 1]) if "--jobs" in a else 4
    os.makedirs(os.path.join(kt.CACHE, "made"), exist_ok=True)
    from multiprocessing import Pool
    with Pool(jobs) as pool:
        for k, _ in enumerate(pool.imap_unordered(one, range(n), chunksize=4), 1):
            if k % 100 == 0: print(k, flush=True)
