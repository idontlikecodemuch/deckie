# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile", "librosa>=0.10"]
# ///
"""Three soundtracks for the Deckie film, synthesised from nothing: no samples, no recordings.

    MOTION_REEL_SKILL=<skill> uv run score.py <A|B|C> <out.wav>

120 BPM, 152 beats, 76 s: the film's own grid, so every accent sits on the beat the picture hits.
A  House        warm four-on-the-floor; the accents are percussion played inside the groove.
B  Scratch      a broken beat with vinyl crackle; the accents are scratches and cuts; sections change on a rewind.
D  In between   A's opening (the groove behind a filter that opens, a clap fill, the drop) on C's drum kit and organ,
                then C's body and its DJ moves; the accents are A's percussion, played in the groove, throughout.
C  Jackin'      a rawer, swung house groove; sections change on DJ moves (filter build, cut on the one, bass swap,
                echo out), and the accents are a cue-button click with a short filter blip.
"""
import os, sys
import numpy as np
import soundfile as sf
from scipy import signal
sys.path.insert(0, os.path.join(os.environ["MOTION_REEL_SKILL"], "scripts"))
import dsp
from dsp import SR, Bus, kick, clap, hat, bass_note, pluck, filt, sweep_filter, saw, adsr, tvec, hz, reverb, sidechain

VAR, OUT = sys.argv[1], sys.argv[2]
dsp.seed({"A": 11, "B": 22, "C": 33, "D": 33}[VAR])
rng = np.random.default_rng({"A": 1, "B": 2, "C": 3, "D": 3}[VAR])
BPM, NB, DUR = 120, 152, 76.0
BEAT = 60 / BPM
N = int(SR * DUR)
# every picture accent in the film (film.js HITS), in beats
HITS = [0, 1.5, 3, 5, 7.7, 8, 13, 18, 20, 24, 26.4, 32, 35, 35.5, 36, 36.5, 37, 42, 50, 51.4, 54, 56, 62, 68, 76, 82,
        90, 98, 106, 110, 114, 117.6, 122, 124, 126, 128, 130, 132, 136, 138.4, 141, 148]
CH = [(["A2", "C3", "E3", "G3"], "A1"), (["F2", "A2", "C3", "E3"], "F1"), (["D3", "F3", "A3", "C4"], "D2"), (["E3", "G3", "B3", "D4"], "E2")]
up = lambda notes, o=1: [n[:-1] + str(int(n[-1]) + o) for n in notes]

# ------------------------------------------------------------------ small instruments
def env(n, d): return np.exp(-tvec(n) / d)
def rim():
    n = int(0.07 * SR); t = tvec(n)
    return (np.sin(2 * np.pi * 1720 * t) + 0.6 * np.sin(2 * np.pi * 2480 * t)) * env(n, 0.012) + filt(rng.standard_normal(n), "highpass", 3000) * env(n, 0.003) * 0.6
def conga(f=220):
    n = int(0.28 * SR); t = tvec(n)
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.45 * np.exp(-t / 0.012))) / SR
    return np.sin(ph) * env(n, 0.09) + filt(rng.standard_normal(n), "bandpass", [1500, 5000]) * env(n, 0.004) * 0.35
def shaker(d=0.03):
    n = int(0.12 * SR)
    return filt(rng.standard_normal(n), "highpass", 5200, 4) * env(n, d) * (1 - env(n, 0.002))
def snare():
    n = int(0.3 * SR); t = tvec(n)
    return filt(rng.standard_normal(n), "bandpass", [1200, 7000]) * env(n, 0.075) + np.sin(2 * np.pi * 185 * t) * env(n, 0.05) * 0.8
def organ(notes, length=0.16):
    n = int(length * SR); t = tvec(n)
    x = sum(np.sin(2 * np.pi * hz(nt) * t) + 0.6 * np.sin(4 * np.pi * hz(nt) * t) + 0.35 * np.sin(6 * np.pi * hz(nt) * t) for nt in notes)
    return np.tanh(0.9 * x / len(notes) * 2) * adsr(n, 0.002, 0.05, 0.5, 0.03)
def cue_click():
    n = int(0.09 * SR); t = tvec(n)
    return np.sin(2 * np.pi * 2600 * t) * env(n, 0.004) + np.sin(2 * np.pi * 95 * t) * env(n, 0.022) * 0.9 + filt(rng.standard_normal(n), "highpass", 4000) * env(n, 0.002) * 0.5
def blip(f0=500, f1=2600, d=0.11):
    n = int(d * SR); t = tvec(n)
    x = sweep_filter(saw(110, n) + rng.standard_normal(n) * 0.4, f0 * (f1 / f0) ** (t / d), "bandpass", 5.0)
    return x * adsr(n, 0.002, 0.03, 0.7, 0.03) * 2.2
def crackle(n):
    x = np.zeros(n); k = rng.random(n) < 0.0009
    x[k] = rng.standard_normal(k.sum()) * rng.random(k.sum()) ** 2
    x = filt(x, "bandpass", [900, 8000]) * 6 + filt(rng.standard_normal(n), "highpass", 4000) * 0.012
    return x + filt(rng.standard_normal(n), "lowpass", 60) * 0.02
def stereo(x): return np.stack([x, x]) if x.ndim == 1 else x

# ------------------------------------------------------------------ scratching: a made sound, played by hand
def scratch_source():
    """Two seconds of a made 'ahh': a saw chord and breath through three vowel formants. Not a recording of anything."""
    n = int(2.0 * SR); t = tvec(n)
    x = sum(saw(hz(nt) * (1 + 0.004 * np.sin(2 * np.pi * 5 * t)).mean(), n, phase0=rng.uniform()) for nt in ("A2", "E3", "A3")) + rng.standard_normal(n) * 0.5
    y = sum(g * filt(x, "bandpass", [f * 0.86, f * 1.16]) for f, g in ((730, 1.0), (1090, 0.7), (2440, 0.35)))
    return y / np.abs(y).max() * (1 - np.exp(-t / 0.01))
SRC = scratch_source()
def scratch(pos, gate=None):
    """pos: where the 'record' is (seconds into SRC) at each output sample. The pitch follows the hand's speed."""
    y = np.interp(pos * SR, np.arange(len(SRC)), SRC, left=0, right=0)
    speed = np.abs(np.gradient(pos) * SR)
    y = y * np.clip(speed / 0.25, 0, 1)                      # a still record is silent
    if gate is not None: y = y * gate
    f = int(0.003 * SR); y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    return filt(y, "highpass", 180)
def s_zip(d=0.11, a=0.34, p0=0.3):                           # one quick push forward
    t = tvec(int(d * SR)); return scratch(p0 + a * (t / d) ** 0.8)
def s_baby(d=0.3, a=0.26, p0=0.3):                           # forward and back
    t = tvec(int(d * SR)); return scratch(p0 + a * (1 - np.cos(2 * np.pi * t / d)) / 2)
def s_chirp(d=0.2, a=0.2, p0=0.35):                          # forward, fader shut at the turn, back
    t = tvec(int(d * SR)); g = (np.abs(t / d - 0.5) > 0.12).astype(float)
    g = signal.lfilter([0.02], [1, -0.98], g)
    return scratch(p0 + a * (1 - np.cos(2 * np.pi * t / d)) / 2, g * 1.2)
def s_transform(d=1.0, a=0.5, p0=0.25, cuts=8):              # a slow drag chopped by the fader
    t = tvec(int(d * SR)); g = ((t / d * cuts) % 1 < 0.55).astype(float)
    g = signal.lfilter([0.03], [1, -0.97], g)
    return scratch(p0 + a * (1 - np.cos(2 * np.pi * t / d)) / 2 + 0.0 * t, g * 1.3)
def s_drag(d=0.7, a=0.5, p0=0.25):                           # a push that slows to a stop: the pitch falls
    t = tvec(int(d * SR)); return scratch(p0 + a * (1 - (1 - t / d) ** 2.2))
def s_tear(d=0.36):                                          # three short pushes
    return np.concatenate([s_zip(d / 3 * 0.8, 0.2, 0.3 + 0.1 * i) if i % 2 == 0 else s_zip(d / 3 * 0.8, 0.2, 0.5)[::-1] for i in range(3)])

def rewind(x, t_end, d=0.5, span=2.4):
    """A backspin: the last `span` seconds before t_end, backwards, the platter speeding up."""
    a, b = int((t_end - span) * SR), int(t_end * SR)
    seg = x[:, a:b][:, ::-1]
    t = tvec(int(d * SR)); pos = (span * (t / d) ** 1.6) * SR
    y = np.stack([np.interp(pos, np.arange(seg.shape[1]), seg[c], right=0) for c in range(2)])
    y = np.stack([filt(y[c], "highpass", 250) for c in range(2)])
    f = int(0.004 * SR); y[:, :f] *= np.linspace(0, 1, f); y[:, -f:] *= np.linspace(1, 0, f)
    return y * 1.3
def platter_stop(x, t0, d=0.9):
    """Power off: from t0 the record slows to a stop over d seconds; then silence."""
    a = int(t0 * SR); t = tvec(int(d * SR)); pos = a + (t - t ** 2 / (2 * d)) * SR
    y = np.stack([np.interp(pos, np.arange(x.shape[1]), x[c]) for c in range(2)]) * (1 - (t / d) ** 3)
    out = x.copy(); out[:, a:a + y.shape[1]] = y; out[:, a + y.shape[1]:] = 0
    return out
def echo(x, t0, delay_beats=0.75, fb=0.55, reps=7, cut=2600, src_beats=1.0):
    """An echo out: the last beat before t0 repeats, each repeat quieter and duller."""
    a, b = int((t0 - src_beats * BEAT) * SR), int(t0 * SR)
    seg = x[:, a:b].copy(); out = np.zeros_like(x); d = int(delay_beats * BEAT * SR)
    for r in range(1, reps + 1):
        seg = np.stack([filt(seg[c], "lowpass", cut) for c in range(2)]) * fb
        s = a + r * d
        if s >= x.shape[1]: break
        e = min(s + seg.shape[1], x.shape[1]); out[:, s:e] += seg[:, :e - s]
    return out
def sweep_bus(x, b0, b1, f0, f1, kind="lowpass"):
    """Open (or close) a filter over the whole bus between two beats."""
    a, b = int(b0 * BEAT * SR), int(b1 * BEAT * SR); n = b - a
    if kind == "lowpass":
        fc = f0 * (f1 / f0) ** (np.arange(n) / n)
        x[:, a:b] = np.stack([sweep_filter(x[c, a:b], fc, "lowpass", 0.9) for c in range(2)])
    else:                                                     # a rising high-pass, in eight steps
        for i in range(16):
            s, e = a + n * i // 16, a + n * (i + 1) // 16
            x[:, s:e] = np.stack([filt(x[c, s:e], "highpass", f0 * (f1 / f0) ** (i / 15), 2) for c in range(2)])
    return x

# ------------------------------------------------------------------ grooves
def house(b0, b1, swing=0.035, open_hat=True, stabs=True, bassline=True, jack=False, kick_gain=1.0, drums_only=False):
    D, Bs, M = Bus(DUR, BPM), Bus(DUR, BPM), Bus(DUR, BPM); kicks = []
    for b in range(b0, b1):
        bar, q = (b - b0) // 4, (b - b0) % 4
        notes, root = CH[(b // 4) % 4]
        D.add(kick(), b, kick_gain); kicks.append(b * BEAT)
        if q in (1, 3):
            D.add(clap(), b, 0.62 if not jack else 0.75, pan=0.04); D.add(snare(), b, 0.18 if not jack else 0.3)
        if open_hat: D.add(hat(True), b + 0.5, 0.3, pan=0.2)
        for s, g in ((0.25 + swing, 0.11), (0.5, 0.0 if open_hat else 0.2), (0.75 + swing, 0.16)):
            if g: D.add(hat(), b + s, g * (1 + 0.3 * rng.random()), pan=-0.25)
        if jack:
            if q == 2: D.add(rim(), b + 0.75 + swing, 0.3, pan=0.3)
            if q == 0 and bar % 2 == 1: D.add(rim(), b + 0.25 + swing, 0.22, pan=-0.3)
            D.add(shaker(0.02), b + 0.5, 0.14, pan=0.35)
        if drums_only: continue
        if bassline:
            if jack:                                         # short organ-bass stabs, off the beat
                for s in ((0.5,), (0.75 + swing, 1.5))[q % 2]:
                    Bs.add(bass_note(root[:-1] + str(int(root[-1]) + 1), BEAT * 0.3, 1500), b + s, 0.6)
            else:                                            # rolling off-beat bass with an octave lift
                Bs.add(bass_note(root, BEAT * 0.42, 950), b + 0.5, 0.62)
                if q == 3: Bs.add(bass_note(root[:-1] + str(int(root[-1]) + 1), BEAT * 0.2, 1300), b + 0.75 + swing, 0.4)
        if stabs:
            if jack:
                if q in (0, 2): M.add(organ(up(notes[1:])), b + 0.75 + swing, 0.42, pan=-0.1)
                if q == 3: M.add(organ(up(notes[1:])), b + 0.5, 0.34, pan=0.15)
            else:
                if q == 0: M.add(pluck(up(notes), 0.34, 3600), b + 0.75 + swing, 0.36, pan=-0.12)
                if q == 2: M.add(pluck(up(notes), 0.3, 3000), b + 0.5, 0.3, pan=0.15)
                if q == 3 and bar % 2 == 1: M.add(pluck(up(notes, 2)[1:], 0.2, 4200), b + 0.25 + swing, 0.2, pan=0.2)
    duck = sidechain(kicks, D.x.shape[1], 0.55, 0.11) if kicks else 1.0
    return D.x, Bs.x * duck, reverb(M.x, 0.22) * duck
def breaks(b0, b1, swing=0.05):
    D, Bs = Bus(DUR, BPM), Bus(DUR, BPM)
    for b in range(b0, b1):
        bar, q = (b - b0) // 4, (b - b0) % 4
        root = CH[(b // 8) % 2 * 2][1]                       # A, then D: two bars each
        if q == 0: D.add(kick(), b, 1.0)
        if q == 1: D.add(kick(), b + 0.75 + swing, 0.8)
        if q == 2: D.add(kick(), b + 0.5, 0.9)
        if q in (1, 3): D.add(snare(), b, 0.75); D.add(clap(True), b, 0.3)
        if q == 3 and bar % 2 == 1: D.add(snare(), b + 0.75 + swing, 0.3)
        D.add(hat(), b, 0.2, pan=-0.2); D.add(hat(), b + 0.5, 0.26, pan=-0.2)
        if q % 2 == 1: D.add(hat(), b + 0.75 + swing, 0.12, pan=0.25)
        r1 = root[:-1] + str(int(root[-1]) + 1)
        for s, nt, L in ((0, r1, 0.3), (0.75 + swing, r1, 0.16)) if q == 0 else ((0.5, r1, 0.22),) if q == 2 else ((0.5, root[:-1] + str(int(root[-1]) + 2), 0.12),) if q == 3 else ():
            Bs.add(bass_note(nt, BEAT * L * 2, 1700), b + s, 0.6)
    return D.x, Bs.x, np.zeros_like(D.x)

# ------------------------------------------------------------------ arrangements
A_ = Bus(DUR, BPM)                                            # accents, played into the track
def acc(sig, beat, gain=1.0, pan=0.0): A_.add(sig, beat, gain, pan)

if VAR == "A":
    # intro: the groove heard through a closed filter that opens over eight bars; drums stop for a beat; drop on the one
    d0, b0_, m0 = house(8, 31, kick_gain=0.55, bassline=False)
    pre = sweep_bus(d0 + m0, 8, 31, 160, 9000)
    d1, b1_, m1 = house(32, 118)
    d2, b2_, m2 = house(118, 128, stabs=True, bassline=False, open_hat=False, kick_gain=0.0)     # dictionary: the kick drops out
    d3, b3_, m3 = house(128, 136, bassline=False, kick_gain=0.5)                                 # your music / your mix: half weight
    d4, b4_, m4 = house(136, 148)
    mix = pre + d1 + b1_ + m1 + (d2 + m2) * 0.8 + d3 + m3 + d4 + b4_ + m4
    mix = sweep_bus(mix, 132, 136, 700, 12000)                # a second, short opening into the end card
    mix[:, int(117.4 * BEAT * SR):int(118 * BEAT * SR)] = 0   # a breath before the dictionary, so its hat is heard alone
    for i, b in enumerate((31, 31.25, 31.5, 31.625, 31.75, 31.875)): acc(clap(True), b, 0.3 + 0.08 * i)   # fill into the drop
    for b in (32, 56, 136): acc(hat(True), b, 0.5); acc(dsp.sub_drop(0.9, 78, 34), b, 0.5)
    for b, f in ((0, 150), (1.5, 200), (3, 266)): acc(conga(f), b, 0.9, 0.1)
    acc(clap(), 5, 0.8); acc(hat(True), 7.7, 0.5); acc(rim(), 8, 0.8); acc(rim(), 13, 0.8)
    acc(conga(150), 18, 1.0); acc(clap(), 20, 0.9); acc(conga(266), 20, 0.6)
    acc(kick(), 24, 0.9); acc(pluck(up(CH[0][0]), 0.6, 5000), 24, 0.7); acc(rim(), 26.4, 0.8)
    for i, b in enumerate((35, 35.5, 36, 36.5, 37)): acc(conga(170 * 1.122 ** i), b, 0.75, -0.2 + 0.1 * i)
    acc(rim(), 42, 0.8); acc(clap(), 50, 0.7)
    for i in range(6): acc(shaker(), 51.4 + i * 0.125, 0.5 if i == 0 else 0.25, 0.3)
    acc(conga(300), 54, 0.9, 0.3); acc(pluck(up(["A3", "C#4", "E4"]), 0.5, 5200), 62, 0.75)
    for b, f in ((68, 200), (76, 150), (82, 225), (90, 266)): acc(conga(f), b, 0.85, 0.15); acc(rim(), b, 0.5)
    for i in range(8): acc(hat(), 98 + i * 0.125, 0.5 if i == 0 else 0.28)
    acc(clap(), 106, 0.75); acc(rim(), 110, 0.8)
    for i in range(4): acc(shaker(0.02), 114 + i * 0.125, 0.5 if i == 0 else 0.3)
    acc(hat(True), 117.6, 0.55)
    for b, f in ((122, 150), (124, 200), (126, 266)): acc(conga(f), b, 0.95)
    for b in (128, 130): acc(clap(), b, 0.8); acc(pluck(up(CH[0][0] if b == 128 else CH[1][0]), 0.5, 4600), b, 0.6)
    acc(rim(), 132, 0.8); acc(rim(), 138.4, 0.8); acc(conga(225), 141, 0.9)
    acc(kick(), 148, 1.0); acc(pluck(up(CH[0][0]), 1.2, 5200), 148, 0.8)
    mix[:, int(148 * BEAT * SR):] = 0
    out = mix + reverb(A_.x, 0.12) + echo(mix + A_.x, 148.5 * BEAT, 0.75, 0.5, 5, 2200, 0.5) * 0.7

elif VAR == "B":
    d1, b1_, _ = breaks(32, 118)
    d2, _, _ = breaks(118, 128); d2 *= 0.55                   # dictionary: drums alone, pulled back
    d4, b4_, _ = breaks(136, 148)
    hatline = Bus(DUR, BPM)
    for b in range(8, 32): hatline.add(hat(), b + 0.5, 0.22, pan=-0.2); hatline.add(hat(), b, 0.1, pan=-0.2)
    for b in (16, 18.5, 20, 22.5, 24, 26.5, 28, 30.5): hatline.add(kick(True), b, 0.5)
    for b in range(128, 136):                                 # under "Your music / Your mix": hats and a soft kick only
        hatline.add(hat(), b + 0.5, 0.22, pan=-0.2); hatline.add(hat(), b, 0.1, pan=-0.2)
        if b % 2 == 0: hatline.add(kick(True), b, 0.5)
    mix = hatline.x + d1 + b1_ + d2 + d4 + b4_
    cr = crackle(mix.shape[1]); mix += np.stack([cr, np.roll(cr, 331)]) * 0.5
    n0 = int(0.25 * SR); acc(np.sin(2 * np.pi * 70 * tvec(n0)) * env(n0, 0.06) + filt(rng.standard_normal(n0), "bandpass", [1000, 4000]) * env(n0, 0.004), 0, 1.0)   # the needle goes down
    acc(s_zip(0.1, 0.3), 1.5, 0.9, 0.15); acc(s_zip(0.08, 0.36), 3, 0.9, -0.15); acc(s_baby(0.32), 5, 0.9)
    acc(s_zip(0.14, 0.45)[::-1], 7.7, 0.8); acc(s_chirp(), 8, 0.9); acc(s_zip(), 13, 0.9)
    acc(s_baby(0.3), 18, 1.0); acc(s_chirp(0.18), 20, 1.0); acc(s_chirp(0.18, 0.24), 20.5, 0.8)
    acc(s_transform(1.0, 0.6, 0.25, 8), 24, 1.0); acc(s_zip(), 26.4, 0.9)
    for i, b in enumerate((35, 35.5, 36, 36.5, 37)): acc(s_zip(0.09, 0.2 + 0.05 * i, 0.3), b, 0.85, -0.2 + 0.1 * i)
    acc(s_zip(), 42, 0.9); acc(s_baby(0.28), 50, 0.9); acc(s_drag(0.9, 0.9, 0.2), 51.4, 0.8); acc(s_zip(0.08, 0.36), 54, 0.9)
    acc(s_chirp(0.16), 62, 1.0); acc(s_chirp(0.16, 0.26), 62.5, 0.9)
    acc(s_drag(0.8, 0.6), 68, 1.0)                            # the pitch-fader shot: a push that slows, so the pitch falls
    acc(s_zip(), 76, 0.9); acc(s_baby(0.3), 82, 0.9); acc(s_transform(0.5, 0.4, 0.3, 4), 90, 1.0); acc(s_tear(), 98, 1.0)
    acc(s_zip(0.08, 0.36), 106, 0.9); acc(s_baby(0.26), 110, 0.9)
    for i in range(4): acc(s_zip(0.05, 0.14, 0.3 + 0.04 * i), 114 + i * 0.125, 0.8)
    for b, a in ((122, 0.22), (124, 0.3), (126, 0.38)): acc(s_zip(0.1, a), b, 0.95)
    acc(s_baby(0.34, 0.3), 128, 1.0); acc(s_baby(0.3, 0.38), 130, 1.0); acc(s_zip(), 132, 0.8)
    acc(s_zip(), 138.4, 0.9); acc(s_baby(0.3), 141, 0.9); acc(s_chirp(0.2), 148, 1.0)
    for b in (32, 56, 136): acc(kick(), b, 0.6)
    out = mix + A_.x
    for b, d in ((32, 0.5), (56, 0.45), (118, 0.2), (136, 0.5)):                  # sections change on a rewind
        r = rewind(out, b * BEAT - d - 0.02, d, 2.2); s = int((b * BEAT - d - 0.02) * SR)
        out[:, s:s + int(d * SR)] *= 0.15; out[:, s:s + r.shape[1]] += r     # the beat is pulled down under the rewind, and is back on the one
    out += echo(A_.x, 128 * BEAT, 0.75, 0.5, 5, 2400, 6.0) * 0.5                      # the dictionary's three cuts ring on
    out = platter_stop(out, 149.0 * BEAT, 1.1)                                       # and the record is stopped

else:  # C, and D (C's body behind A's opening)
    if VAR == "D":
        # the same kit and organ as the body, heard through a closed filter that opens over six bars; the drums stop
        # for the fill; then the record is simply all the way in, on the one
        dd, _, mm = house(8, 31, swing=0.06, jack=True, bassline=False, kick_gain=0.55)
        d0 = sweep_bus(dd + mm, 8, 31, 160, 9000)
    else:
        d0, _, _ = house(8, 32, swing=0.06, jack=True, drums_only=True, kick_gain=0.6)
        d0 = sweep_bus(d0, 8, 24, 140, 2400); d0 = sweep_bus(d0, 24, 31, 120, 2600, "highpass")   # low-passed, then the lows are pulled out
        d0[:, int(31 * BEAT * SR):int(32 * BEAT * SR)] = 0                                         # one beat of nothing; then cut in on the one
    d1, b1_, m1 = house(32, 93, swing=0.06, jack=True)
    d1b, b1b, m1b = house(93, 118, swing=0.06, jack=True)
    # the wave shot (beats 90 to 96): a second groove is blended in and the bass is swapped at the phrase
    g2d, g2b, g2m = house(88, 118, swing=0.06, jack=False, stabs=True, bassline=True)
    fade = np.clip((np.arange(d1.shape[1]) / SR / BEAT - 88) / 5, 0, 1) * 0.5
    d2, _, m2 = house(118, 128, swing=0.06, jack=True, bassline=False, kick_gain=0.0, open_hat=False)
    d3, b3_, m3 = house(128, 136, swing=0.06, jack=True)
    d4, b4_, m4 = house(136, 148, swing=0.06, jack=True)
    a93 = int(93 * BEAT * SR)
    body = d1 + m1 + d1b + m1b * 0.6 + (g2d * 0.35 + g2m) * fade
    bass = b1_.copy(); bass[:, a93:] = 0; bass2 = g2b.copy(); bass2[:, :a93] = 0
    mix = d0 + body + bass + bass2 + (d2 + m2) * 0.7 + d3 + b3_ + m3 + d4 + b4_ + m4
    mix = sweep_bus(mix, 128, 136, 500, 14000)                                                  # filtered under "Your music / Your mix", open by the end card
    a117 = int(117.5 * BEAT * SR); tail = echo(mix, 117.5 * BEAT, 0.75, 0.6, 8, 2600, 1.0)      # echo out into the dictionary ("Echo out")
    mix[:, a117:int(118 * BEAT * SR)] = 0
    a55 = int(55 * BEAT * SR); tail += echo(mix, 55 * BEAT, 0.5, 0.5, 2, 3000, 0.5) * 0.8
    mix = sweep_bus(mix, 54, 56, 60, 900, "highpass")                                           # the lows come out for two beats; back on the one
    # the pitch-fader shot: the chords are nudged up three percent for a bar, as a hand on the platter would
    a, b = int(68 * BEAT * SR), int(72 * BEAT * SR); seg = m1[:, a:b]
    idx = np.arange(seg.shape[1]) * 1.03; nud = np.stack([np.interp(idx, np.arange(seg.shape[1]), seg[c], right=0) for c in range(2)])
    mix[:, a:b] += nud * 0.9 - seg
    if VAR == "D":                                            # accents: percussion in the groove, as in A
        for i, b in enumerate((31, 31.25, 31.5, 31.625, 31.75, 31.875)): acc(clap(True), b, 0.3 + 0.08 * i)
        for b in (32, 56, 136): acc(hat(True), b, 0.5); acc(dsp.sub_drop(0.9, 78, 34), b, 0.5)
        for b, f in ((0, 150), (1.5, 200), (3, 266)): acc(conga(f), b, 0.9, 0.1)
        acc(clap(), 5, 0.8); acc(hat(True), 7.7, 0.5); acc(rim(), 8, 0.8); acc(rim(), 13, 0.8)
        acc(conga(150), 18, 1.0); acc(clap(), 20, 0.9); acc(conga(266), 20, 0.6)
        acc(kick(), 24, 0.9); acc(organ(up(CH[0][0]), 0.5), 24, 0.7); acc(rim(), 26.4, 0.8)
        for i, b in enumerate((35, 35.5, 36, 36.5, 37)): acc(conga(170 * 1.122 ** i), b, 0.75, -0.2 + 0.1 * i)
        acc(rim(), 42, 0.8); acc(conga(225), 42, 0.6); acc(clap(), 50, 0.7)
        for i in range(6): acc(shaker(), 51.4 + i * 0.125, 0.55 if i == 0 else 0.25, 0.3)
        acc(conga(300), 54, 0.9, 0.3); acc(organ(up(["A3", "C#4", "E4"]), 0.4), 62, 0.8); acc(rim(), 62, 0.6)
        for b, f in ((68, 200), (76, 150), (82, 225), (90, 266)): acc(conga(f), b, 0.9, 0.15); acc(rim(), b, 0.55)
        for i in range(8): acc(hat(), 98 + i * 0.125, 0.55 if i == 0 else 0.3)
        acc(clap(), 106, 0.75); acc(rim(), 110, 0.8); acc(conga(200), 110, 0.6)
        for i in range(4): acc(shaker(0.02), 114 + i * 0.125, 0.55 if i == 0 else 0.3)
        acc(rim(), 117.6, 0.9)
        for b, f in ((122, 150), (124, 200), (126, 266)): acc(conga(f), b, 1.0)
        for b in (128, 130): acc(clap(), b, 0.8); acc(organ(up(CH[0][0] if b == 128 else CH[1][0]), 0.4), b, 0.8)
        acc(rim(), 132, 0.8); acc(rim(), 138.4, 0.8); acc(conga(225), 141, 0.9)
        acc(organ(up(CH[0][0]), 0.9), 148, 0.9); acc(kick(), 148, 1.0)
    else:
        def cue(b, f0=500, f1=2600, g=1.0, pan=0.0): acc(cue_click(), b, 0.9 * g, pan); acc(blip(f0, f1), b + 0.02, 0.5 * g, pan)
        for b, f in ((0, 400), (1.5, 520), (3, 680)): cue(b, f, f * 4)
        cue(5, 300, 3200, 1.1); acc(blip(3000, 400, 0.14), 7.7, 0.7); cue(8); cue(13)
        cue(18, 300, 1800, 1.1); cue(20, 500, 3600, 1.2); acc(kick(), 24, 0.9); acc(organ(up(CH[0][0]), 0.5), 24, 0.7); cue(26.4)
        acc(kick(), 32, 0.4)
        for i, b in enumerate((35, 35.5, 36, 36.5, 37)): cue(b, 400 * 1.2 ** i, 1600 * 1.2 ** i, 0.85, -0.2 + 0.1 * i)
        cue(42); cue(50); acc(cue_click(), 51.4, 0.8, 0.2); acc(blip(300, 4200, 0.6), 51.4, 0.6, 0.2); cue(54, 800, 3600)
        acc(kick(), 56, 0.4); acc(organ(up(["A3", "C#4", "E4"]), 0.4), 62, 0.8); acc(cue_click(), 62, 0.8)
        for b in (68, 76, 82, 90): cue(b)
        for i in range(8): acc(cue_click(), 98 + i * 0.125, 0.8 if i == 0 else 0.35); 
        acc(blip(600, 3600, 0.4), 98, 0.5)
        cue(106, 800, 3200, 1.1); cue(110)
        for i in range(4): acc(cue_click(), 114 + i * 0.125, 0.8 if i == 0 else 0.4)
        acc(cue_click(), 117.6, 0.9)
        for b, f in ((122, 400), (124, 520), (126, 680)): cue(b, f, f * 4, 1.1)
        for b in (128, 130): acc(clap(), b, 0.8); acc(organ(up(CH[0][0] if b == 128 else CH[1][0]), 0.4), b, 0.8)
        cue(132); acc(kick(), 136, 0.4); cue(138.4); cue(141); acc(organ(up(CH[0][0]), 0.9), 148, 0.9); acc(kick(), 148, 1.0)
    mix[:, int(148 * BEAT * SR):] = 0
    out = mix + tail + reverb(A_.x, 0.1)
    out += echo(out, 148.6 * BEAT, 0.75, 0.55, 6, 2400, 0.6) * 0.8                              # and out on an echo

out = out[:, :N]
out = np.stack([filt(out[c], "highpass", 28) for c in range(2)])
f = int(0.4 * SR); out[:, -f:] *= np.linspace(1, 0, f) ** 2
out *= 10 ** (-3 / 20) / (np.abs(out).max() + 1e-9)
assert np.isfinite(out).all()
sf.write(OUT, out.T.astype(np.float32), SR, subtype="PCM_24")
print(VAR, "written", OUT, "peak", round(float(np.abs(out).max()), 3))
