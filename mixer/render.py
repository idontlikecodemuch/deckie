"""Offline renderer (research.md C, E.5): plan_<n>.json -> mixes/<n> - <name>.mp3 + .cue + .txt + render log.

Usage:
  .venv/bin/python -I render.py plan_1.json                    # full hour
  .venv/bin/python -I render.py plan_1.json --preview 4         # first 4 joins -> mixes/preview.mp3

Design (all verified on this Mac):
* decode once with soundfile (soxr to 44.1 kHz if needed, as analyze.py does), normalise to -14 LUFS,
  play only between first and last sound;
* every song is laid out on its constant beat grid; bar boundaries are mapped to output sample positions.
  Inside an overlap both songs share the same integer bar positions, so downbeats coincide by construction;
* tempo: Rubber Band through pedalboard.time_stretch with a per-sample stretch array (staircase per bar,
  ramping from A's tempo to B's across the overlap).  high_quality=False (R2 engine): on this build the
  R3 engine (high_quality=True) drifts 1.5-2 ms per second against the requested ratio (60-70 ms over
  40 s, measured with a click track), while R2 stays within 1.5 ms;
* 3-band isolator: LR4 low-pass at 200 Hz and LR4 high-pass at 2.5 kHz (two cascaded Butterworth-2),
  mid = signal - low - high (perfect reconstruction when all gains are 1);
* exits: bass swap, high-pass sweep, tempo-synced echo, reverb wash, vinyl brake, scratch stab;
  synthesised noise riser + sub impact on cuts;
* the running mix is streamed to a float WAV, then mastered once (gain + BrickwallLimiter -1 dBTP,
  iterated to -10 LUFS integrated), encoded CBR 320 MP3 with ffmpeg.
"""
import argparse, json, math, os, subprocess, sys, time
import numpy as np
import soundfile as sf
import pyloudnorm as pyln
import pedalboard
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
MIXES = os.path.join(HERE, "mixes")
SR = 44100
FFMPEG = "/opt/homebrew/bin/ffmpeg"
TRACK_LUFS = -14.0
TARGET_LUFS = -10.0
CEILING_DB = -1.0           # limiter ceiling (true peak); MP3 encoding adds overshoot, see MP3_MARGIN_DB
MP3_MARGIN_DB = 0.8         # extra headroom so the encoded MP3 still measures <= -1 dBTP
CUT_TYPES = ("brake_cut", "loop_roll", "slam", "echo_out", "reverb_out")
SLAM_TYPES = ("slam", "echo_out", "reverb_out")      # A plays to its exit downbeat, B starts on the one
# exit FX (revised after the first listen: louder, longer, dry cut hard)
# exit FX per transition-recipes.md sections 1.1, 1.2, 3.4, 4 (DJM-style echo-out, short filtered reverb throw)
ECHO_DELAY_BEATS = 0.75      # 3/4-beat "shuffle" echo
ECHO_FB = 0.84               # 3/4 beat -> repeats down 24 dB after ~3 bars
ECHO_WET = 0.63              # -4 dB vs A's dry level
ECHO_LP_HZ = 5000            # 1-pole LP in the loop
ECHO_SEND_BEATS = 2          # send = A's last 2 beats, lows removed (FX-frequency LOW off)
ECHO_TAIL_BARS = 4
REVERB_ROOM = 0.6            # short room/plate, ~1-2 s
REVERB_WET = 0.5             # -6 dB vs A
REVERB_TAIL_BARS = 2
XF = 220                     # 5 ms seam crossfade half-width (samples)

_LP = signal.butter(2, 200, "lowpass", fs=SR, output="sos")
_HP = signal.butter(2, 2500, "highpass", fs=SR, output="sos")


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- audio helpers
def load_track(path, first_s, last_s):
    y, sr = sf.read(path, dtype="float32", always_2d=True)
    if sr != SR:
        import soxr
        y = soxr.resample(y, sr, SR).astype(np.float32)
    meter = pyln.Meter(SR)
    a, b = int(first_s * SR), int(last_s * SR)
    lufs = meter.integrated_loudness(y[a:b].astype(np.float64))
    g = 10 ** ((TRACK_LUFS - lufs) / 20)
    y = (y.T * g).astype(np.float32)          # (2, n)
    if y.shape[0] == 1:
        y = np.vstack([y, y])
    y = y[:2]
    # trim to first/last sound (Mixxx -60 dBFS rule from analysis) with 5 ms ramps
    y[:, :a] = 0
    y[:, b:] = 0
    r = np.linspace(0, 1, XF, dtype=np.float32)
    y[:, a:a + XF] *= r
    y[:, max(0, b - XF):b] *= r[::-1][:y[:, max(0, b - XF):b].shape[1]]
    return y, lufs


def lr4(x, sos):
    return signal.sosfilt(sos, signal.sosfilt(sos, x, axis=-1), axis=-1).astype(np.float32)


def env(points, n):
    """Piecewise-linear gain curve from (sample, gain) points over n samples."""
    pts = sorted(points)
    xs = np.array([p[0] for p in pts], float)
    ys = np.array([p[1] for p in pts], float)
    return np.interp(np.arange(n), xs, ys).astype(np.float32)


def stretch_run(x, t_knots, k_knots, mode):
    """Stretch input between consecutive grid knots so knot j lands on output sample k_knots[j].
    Returns audio covering output [k0 - XF, kN + XF)."""
    pad = 0.5
    n = x.shape[1]
    i0 = max(0, int(round((t_knots[0] - pad) * SR)))
    i1 = min(n, int(round((t_knots[-1] + pad) * SR)))
    seg = x[:, i0:i1]
    arr = np.empty(seg.shape[1], np.float64)
    fac = []
    for j in range(len(t_knots) - 1):
        fac.append((t_knots[j + 1] - t_knots[j]) * SR / (k_knots[j + 1] - k_knots[j]))
    for j in range(len(t_knots) - 1):
        a = int(round(t_knots[j] * SR)) - i0
        b = int(round(t_knots[j + 1] * SR)) - i0
        arr[max(0, a):max(0, b)] = fac[j]
    a0 = int(round(t_knots[0] * SR)) - i0
    aN = int(round(t_knots[-1] * SR)) - i0
    arr[:max(0, a0)] = fac[0]
    arr[aN:] = fac[-1]
    y = pedalboard.time_stretch(seg, SR, arr, high_quality=False, transient_mode=mode,
                                transient_detector="compound")
    pos = np.concatenate([[0.0], np.cumsum(1.0 / arr)])
    o0 = int(round(pos[a0]))
    need = k_knots[-1] - k_knots[0] + 2 * XF
    out = np.zeros((2, need), np.float32)
    s = o0 - XF
    src0 = max(0, s)
    dst0 = src0 - s
    m = min(need - dst0, y.shape[1] - src0)
    if m > 0:
        out[:, dst0:dst0 + m] = y[:, src0:src0 + m]
    return out, fac


def native_run(x, t0, k0, k1):
    s = int(round(t0 * SR)) - XF
    need = k1 - k0 + 2 * XF
    out = np.zeros((2, need), np.float32)
    src0 = max(0, s)
    dst0 = src0 - s
    m = min(need - dst0, x.shape[1] - src0)
    if m > 0:
        out[:, dst0:dst0 + m] = x[:, src0:src0 + m]
    return out


def add_piece(y, piece, k0, k1, ramp_in=True, ramp_out=True):
    """Overlap-add a piece covering [k0-XF, k1+XF) with linear seams centred on k0 and k1."""
    w = np.ones(piece.shape[1], np.float32)
    r = np.linspace(0, 1, 2 * XF, dtype=np.float32)
    if ramp_in:
        w[:2 * XF] = r
    else:
        w[:XF] = 0
    if ramp_out:
        w[-2 * XF:] = r[::-1]
    else:
        w[-XF:] = 0
    s = k0 - XF
    a, b = max(0, s), min(y.shape[1], s + piece.shape[1])
    y[:, a:b] += (piece * w)[:, a - s:b - s]


def varispeed_brake(x, t0, n_out, p=1.7):
    """Vinyl brake: playback rate (1 - t/T)^p from input time t0, n_out output samples, gain fades with rate."""
    t = np.arange(n_out) / n_out
    r = (1 - t) ** p
    pos = t0 * SR + np.concatenate([[0], np.cumsum(r)[:-1]])
    idx = np.arange(x.shape[1])
    out = np.vstack([np.interp(pos, idx, x[c]) for c in range(2)]).astype(np.float32)
    g = (r ** 0.6).astype(np.float32)
    # cartridge roll-off: low-pass that follows the rate (block-wise)
    res = np.zeros_like(out)
    zi = None
    blk = 1024
    for s in range(0, n_out, blk):
        fc = max(150.0, 16000 * r[s] ** 1.5)
        sos = signal.butter(2, min(fc, 18000), "lowpass", fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2, 2))
        res[:, s:s + blk], zi = signal.sosfilt(sos, out[:, s:s + blk], axis=-1, zi=zi)
    return res * g


def backspin(x, t0, n_out):
    """Backspin: platter yanked backwards (rate 1 -> -3 in ~0.12 s) then spinning down to 0, gain falling."""
    t = np.arange(n_out) / SR
    T = n_out / SR
    a = 0.12
    r = np.where(t < a, 1 - 4 * (0.5 - 0.5 * np.cos(np.pi * t / a)),
                 -3 * (1 - (t - a) / (T - a)) ** 1.6)
    pos = t0 * SR + np.concatenate([[0], np.cumsum(r)[:-1]])
    pos = np.clip(pos, 0, x.shape[1] - 1)
    idx = np.arange(x.shape[1])
    out = np.vstack([np.interp(pos, idx, x[c]) for c in range(2)]).astype(np.float32)
    g = np.minimum(1, np.abs(r) / 1.0) ** 0.5 * (1 - t / T) ** 1.2
    g[t < a] = 1
    return out * g.astype(np.float32)


def scratch_stab(x, t0, beat_n, n_out, rng):
    """Baby scratch + crossfader gate on a 1-beat slice of the outgoing song (research C.7), n_out samples."""
    slice_len = beat_n * 0.5
    t = np.arange(n_out)
    period = beat_n / 2.0                       # one back-and-forth per half beat
    ph = (t % period) / period
    tri = np.where(ph < 0.5, ph * 2, 2 - ph * 2)   # 0 ->1 ->0
    tri = 0.5 - 0.5 * np.cos(np.pi * tri)          # smooth corners (continuous velocity)
    pos = t0 * SR + tri * slice_len
    idx = np.arange(x.shape[1])
    out = np.vstack([np.interp(pos, idx, x[c]) for c in range(2)]).astype(np.float32)
    # crossfader: open on forward strokes only (chirp style) with 3 ms ramps; last quarter closed
    fwd = (ph < 0.5).astype(np.float32)
    fwd[int(n_out * 0.8):] = 0
    k = int(0.003 * SR)
    gate = np.convolve(fwd, np.ones(k) / k, mode="same").astype(np.float32)
    out = lr4(out, signal.butter(2, 300, "highpass", fs=SR, output="sos")) * 1.4
    return out * gate


def echo_tail(src, delay_n, fb=0.55, n_tail=0):
    """Tempo-synced feedback delay with damping (LP 3 kHz, HP 250 Hz in the loop). src: (2, m) send."""
    lp = signal.butter(1, ECHO_LP_HZ, "lowpass", fs=SR, output="sos")
    hp = signal.butter(1, 250, "highpass", fs=SR, output="sos")
    total = src.shape[1] + n_tail
    buf = np.zeros((2, total + delay_n), np.float32)
    buf[:, :src.shape[1]] = 0  # dry not included
    x = np.zeros((2, total), np.float32)
    x[:, :src.shape[1]] = src
    out = np.zeros((2, total), np.float32)
    zl = np.zeros((lp.shape[0], 2, 2)); zh = np.zeros((hp.shape[0], 2, 2))
    for s in range(0, total, delay_n):
        e = min(total, s + delay_n)
        prev = out[:, s - delay_n:e - delay_n] if s >= delay_n else np.zeros((2, e - s), np.float32)
        fbk, zl = signal.sosfilt(lp, prev, axis=-1, zi=zl)
        fbk, zh = signal.sosfilt(hp, fbk, axis=-1, zi=zh)
        dly = x[:, s - delay_n:e - delay_n] if s >= delay_n else np.zeros((2, e - s), np.float32)
        out[:, s:e] = dly + fb * fbk
    # stereo ping-pong flavour: slight offset of the right channel by one delay is overkill; keep mono-ish
    return out


def reverb_wash(src, n_tail):
    rv = pedalboard.Pedalboard([pedalboard.HighpassFilter(250), pedalboard.HighpassFilter(250),
                                pedalboard.LowpassFilter(7500),
                                pedalboard.Reverb(room_size=REVERB_ROOM, damping=0.55, wet_level=1.0, dry_level=0.0,
                                                  width=1.0)])
    x = np.concatenate([src, np.zeros((2, n_tail), np.float32)], axis=1)
    return rv(x, SR).astype(np.float32)


def riser(n, beat_n, rng, level=0.12):
    """White-noise riser: band-pass sweeping 200 Hz -> 8 kHz, rising gain, 1/16 tremolo; ends at sample n."""
    noise = rng.standard_normal((2, n)).astype(np.float32)
    out = np.zeros_like(noise)
    blk = 512
    zi = None
    for s in range(0, n, blk):
        f = s / n
        fc = 200 * (8000 / 200) ** f
        lo, hi = fc / 1.6, min(fc * 1.6, 20000)
        sos = signal.butter(2, [lo, hi], "bandpass", fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2, 2))
        out[:, s:s + blk], zi = signal.sosfilt(sos, noise[:, s:s + blk], axis=-1, zi=zi)
    t = np.arange(n) / n
    g = t ** 2.2
    trem = 1 - 0.35 * t * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.arange(n) / (beat_n / 4))))
    out *= (g * trem).astype(np.float32)
    rms = np.sqrt(np.mean(out[:, -n // 8:] ** 2)) + 1e-9
    return out * (level / rms) * 0.5


def impact(rng, level=0.5):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = 38 + 50 * np.exp(-t / 0.08)
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = np.sin(ph) * np.exp(-t / 0.45)
    nz = rng.standard_normal(n) * np.exp(-t / 0.03)
    nz = signal.sosfilt(signal.butter(2, 4000, "lowpass", fs=SR, output="sos"), nz)
    m = (sub * level + nz * 0.15).astype(np.float32)
    att = np.minimum(1, t / 0.002).astype(np.float32)
    return np.vstack([m * att, m * att])


def hp_sweep(x, f0, f1):
    """Time-varying 24 dB/oct high-pass, cutoff log-ramped f0 -> f1 across x (block-wise biquads)."""
    n = x.shape[1]
    out = np.zeros_like(x)
    blk = 512
    zi = None
    for s in range(0, n, blk):
        fc = f0 * (f1 / f0) ** (s / max(1, n))
        sos = signal.butter(4, fc, "highpass", fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2, 2))
        out[:, s:s + blk], zi = signal.sosfilt(sos, x[:, s:s + blk], axis=-1, zi=zi)
    return out


# ---------------------------------------------------------------- streaming loudness
class LoudnessMeter:
    """BS.1770-4 integrated loudness, streamed in blocks (K-weighting from pyloudnorm's coefficients)."""

    def __init__(self):
        m = pyln.Meter(SR)
        self.f = [(fl.b, fl.a) for fl in m._filters.values()]
        self.zi = [np.zeros((2, max(len(b), len(a)) - 1)) for b, a in self.f]
        self.hop = int(0.1 * SR)
        self.carry = np.zeros((2, 0))
        self.ms100 = []

    def add(self, x):
        y = x.astype(np.float64)
        for i, (b, a) in enumerate(self.f):
            y, self.zi[i] = signal.lfilter(b, a, y, axis=-1, zi=self.zi[i])
        y = np.concatenate([self.carry, y], axis=1)
        k = y.shape[1] // self.hop
        if k:
            sq = (y[:, :k * self.hop] ** 2).reshape(2, k, self.hop).mean(axis=2).sum(axis=0)
            self.ms100.extend(sq.tolist())
        self.carry = y[:, k * self.hop:]

    def integrated(self):
        z = np.array(self.ms100)
        if len(z) < 4:
            return -70.0
        blocks = np.convolve(z, np.ones(4) / 4, mode="valid")
        l = -0.691 + 10 * np.log10(blocks + 1e-12)
        b = blocks[l > -70]
        rel = -0.691 + 10 * np.log10(b.mean()) - 10
        b2 = blocks[(l > -70) & (l > rel)]
        return float(-0.691 + 10 * np.log10(b2.mean()))


# ---------------------------------------------------------------- geometry
def bar_time(s, b):
    return s["first_downbeat_s"] + (b - 1) * s["bar_s"]


def make_variance(J, seed):
    """Seeded human-variance layer: every per-join random value is stored in j['var'] and logged."""
    vr = np.random.default_rng(seed)
    for j in J:
        L = j["L"]
        div = float(vr.choice([0.75, 0.75, 0.5]))
        v = {
            "sync_ms": round(float(vr.uniform(2, 8) * vr.choice([-1, 1])), 2),        # nudge, corrected over 1 bar
            "cut_16th": int(vr.choice([0, 0, 0, -1, 1])),                             # cut a 16th early / late
            "wobble_pct": round(float(vr.uniform(0.1, 0.3) * vr.choice([-1, 1])), 3),  # pitch-fader wobble after a blend
            "echo_div": div,
            "echo_fb": round((ECHO_FB if div == 0.75 else 0.88) + float(vr.uniform(-0.03, 0.03)), 3),
            "echo_bars": int(vr.choice([3, 4])),
            "fader_ms": round(float(vr.uniform(10, 40) * vr.choice([-1, 1])), 1),     # fader timing jitter
        }
        if L >= 8:
            sh = int(vr.choice([0, 0, 0, -2, 2] if L >= 16 else [0, 0, 0, -1, 1]))
            v["swap_bar"] = max(2, min(L - 2, L // 2 + sh))
        j["var"] = v


def build_geometry(plan, preview_joins=None, seed=None):
    songs = plan["songs"]
    joins = plan["joins"]
    if preview_joins is not None:
        songs = songs[:preview_joins + 1]
        joins = joins[:preview_joins]
    n = len(songs)
    # per-join shared overlap offsets
    J = []
    for i, j in enumerate(joins):
        A, B = songs[i], songs[i + 1]
        L = int(j["overlap_bars"])
        typ = j["type"]
        if L == 0 or B["cue_in"]["bar"] is None or A["exit"]["bar"] is None:
            typ = typ if typ in CUT_TYPES else "brake_cut"
            L = 0
        D = []
        if L:
            ra, rb = A["bar_s"], B["bar_s"]
            for q in range(L):
                if typ == "chop":
                    D.append(ra)                                  # B runs at A's tempo through the chop
                else:
                    D.append(ra * (rb / ra) ** ((q + 0.5) / L))   # geometric ramp, bar by bar
        O = [0] + [int(round(v)) for v in np.cumsum(np.array(D) * SR)] if L else [0]
        J.append(dict(j, type=typ, L=L, D=D, O=O, a_beat_n=(D[0] if L else A["bar_s"]) / 4 * SR))
    make_variance(J, seed if seed is not None else 1000 + int(plan.get("hour", 0)))
    G = []
    for i, s in enumerate(songs):
        jin = J[i - 1] if i > 0 else None
        jout = J[i] if i < n - 1 else None
        last = jout is None
        # start
        if i == 0 or (jin and jin["L"] == 0):
            if s["cue_in"]["bar"] is not None and i > 0:
                b0 = s["cue_in"]["bar"]; start_t = bar_time(s, b0)
            else:
                start_t = s["first_sound_s"]
                b0 = int(math.ceil((start_t - s["first_downbeat_s"]) / s["bar_s"] - 1e-6)) + 1
        else:
            b0 = s["cue_in"]["bar"]; start_t = bar_time(s, b0)
        # end
        fade_n = 0
        if last:
            if preview_joins is not None and s["exit"].get("bar"):
                b1 = s["exit"]["bar"]
                end_t = bar_time(s, b1)
                fade_n = int(4 * s["bar_s"] * SR)
            else:
                end_t = s["last_sound_s"]
                b1 = int(math.floor((end_t - s["first_downbeat_s"]) / s["bar_s"] + 1e-6)) + 1
                b1 = max(b1, b0)
        else:
            b1 = s["exit"]["bar"]
            end_t = bar_time(s, b1)
        Lin = jin["L"] if jin else 0
        Lout = jout["L"] if jout else 0
        nb = b1 - b0
        if Lin + Lout > nb - 2 and Lout:
            Lout2 = max(4, nb - 2 - Lin)
            log("  ! song %d too short for both overlaps; out overlap %d -> %d bars" % (i + 1, Lout, Lout2))
            # recompute this join with the shorter overlap
            j = jout
            ra, rb = s["bar_s"], songs[i + 1]["bar_s"]
            j["L"] = Lout = Lout2
            j["D"] = [ra * (rb / ra) ** ((q + 0.5) / Lout2) for q in range(Lout2)]
            j["O"] = [0] + [int(round(v)) for v in np.cumsum(np.array(j["D"]) * SR)]
        # knots: (input time, local output sample) at every played bar boundary
        knots = []
        pre = 0
        if start_t < bar_time(s, b0) - 1e-4:
            pre = int(round((bar_time(s, b0) - start_t) * SR))
            knots.append((start_t, 0))
        bar_n = s["bar_s"] * SR
        pos_os = None
        prev = None
        for q in range(nb + 1):
            t = bar_time(s, b0 + q)
            if Lout and q > nb - Lout:
                k = pos_os + jout["O"][q - (nb - Lout)]
            elif Lin and q <= Lin:
                k = pre + jin["O"][q]
            elif prev is None:
                k = pre
            else:
                fq = 1.0
                if Lin and jin.get("var") and Lin < q <= Lin + 4 and q <= nb - Lout:
                    # pitch-fader wobble that settles over the 4 bars after the blend
                    decay = 1.0 - (q - Lin - 1) / 4.0
                    fq = 1.0 + jin["var"]["wobble_pct"] / 100.0 * decay * (1 if (q - Lin) % 2 else -1)
                k = prev + int(round(bar_n * fq))
            if Lout and q == nb - Lout:
                pos_os = k
            knots.append((t, k))
            prev = k
        # tail after the last full bar (last song)
        tail_n = 0
        if last and end_t > knots[-1][0] + 1e-4:
            tail_n = int(round((end_t - knots[-1][0]) * SR))
        G.append(dict(song=s, b0=b0, b1=b1, start_t=start_t, end_t=end_t, knots=knots, pre=pre, tail_n=tail_n,
                      Lin=Lin, Lout=Lout, out_start=pos_os, fade_n=fade_n, jin=jin, jout=jout))
    # timeline offsets
    T = [0]
    for i in range(n - 1):
        g, j = G[i], J[i]
        if j["L"]:
            T.append(T[i] + g["out_start"])
        else:
            if j["type"] in SLAM_TYPES:
                # cut on the one: B's downbeat replaces A's exit downbeat (FX tails ring on under B)
                j["brake_n"] = 0
                T.append(T[i] + g["knots"][-1][1])
                continue
            if j["type"] == "loop_roll":
                brake_n = int(round(g["song"]["bar_s"] * SR))      # exactly one bar, stays on the grid
            else:
                brake_n = int(round(g["song"]["bar_s"] * SR))      # one bar from a downbeat, B on the next one
            # A plays up to its exit-1 bar downbeat, then a 1-bar brake/scratch/roll; B starts when it ends
            k_last = g["knots"][-2][1] if len(g["knots"]) > 1 else g["knots"][-1][1]
            j["brake_n"] = brake_n
            T.append(T[i] + k_last + brake_n)
    # phase correction: line up the songs' *tracker* beats (not just the fitted grids) inside each overlap
    for i in range(n - 1):
        j = J[i]
        j["phase_corr_ms"] = 0.0
        if not j["L"]:
            continue
        a = map_beats(detected_beats(songs[i]["id"]), G[i]["knots"], T[i])
        b = map_beats(detected_beats(songs[i + 1]["id"]), G[i + 1]["knots"], T[i + 1])
        lo, hi = T[i + 1] / SR, (T[i + 1] + j["O"][-1]) / SR
        off, nb = beat_alignment(a, b, lo, hi, j["D"][0] / 4)
        if off is not None and nb >= 8 and abs(off) <= 80:
            sh = int(round(off / 1000 * SR))
            for k in range(i + 1, n):
                T[k] -= sh
            j["phase_corr_ms"] = off
    return songs, J, G, T


# ---------------------------------------------------------------- render one song
def gate_env(points, n, ramp=None):
    """Hard on/off gain steps [(sample, gain), ...] with short (3 ms) ramps at each step."""
    r = ramp or int(0.003 * SR)
    pts = sorted(points)
    out = []
    g_prev = pts[0][1]
    out.append((0, g_prev))
    for s_, g_ in pts[1:]:
        out.append((max(0, s_ - r), g_prev))
        out.append((s_, g_))
        g_prev = g_
    out.append((n, g_prev))
    return env(out, n)


def render_song(i, g, x, rng, rlog):
    s = g["song"]
    knots = g["knots"]
    jin, jout = g["jin"], g["jout"]
    Lin, Lout = g["Lin"], g["Lout"]
    otyp = jout["type"] if jout is not None else None
    cutlike = jout is not None and jout["L"] == 0 and otyp in SLAM_TYPES
    brake = jout is not None and jout["L"] == 0 and not cutlike
    knots_play = knots[:-1] if brake else knots
    total = knots_play[-1][1] + g["tail_n"]
    extra = 0
    if brake:
        extra = jout["brake_n"]
    if jout is not None and jout["L"] == 0:
        extra += int(8 * s["bar_s"] * SR) + int(5 * SR)
    y = np.zeros((2, total + extra + 2 * XF), np.float32)
    mode = s.get("transient_mode", "crisp")
    segs = []
    for q in range(len(knots_play) - 1):
        (t0, k0), (t1, k1) = knots_play[q], knots_play[q + 1]
        fac = (t1 - t0) * SR / max(1, (k1 - k0))
        kind = "native" if abs(fac - 1) < 2e-4 else "stretch"
        if segs and segs[-1][0] == kind:
            segs[-1][1].append(q + 1)
        else:
            segs.append((kind, [q, q + 1]))
    facs = []
    for si, (kind, idxs) in enumerate(segs):
        tk = [knots_play[q][0] for q in idxs]
        kk = [knots_play[q][1] for q in idxs]
        first = si == 0
        lastp = si == len(segs) - 1 and g["tail_n"] == 0 and not brake
        if kind == "native":
            piece = native_run(x, tk[0], kk[0], kk[-1])
        else:
            piece, fac = stretch_run(x, tk, kk, mode)
            facs += fac
        add_piece(y, piece, kk[0], kk[-1], ramp_in=not first, ramp_out=not lastp)
    if g["tail_n"]:
        t0, k0 = knots_play[-1]
        piece = native_run(x, t0, k0, k0 + g["tail_n"])
        add_piece(y, piece, k0, k0 + g["tail_n"], ramp_in=len(segs) > 0, ramp_out=False)
    raw = y.copy()       # pre-gain (FX sends)
    fx_out = {}
    beat_n = s["bar_s"] / 4 * SR
    # ---------------- in-transition (this song is B)
    if jin and Lin:
        O = [g["pre"] + o for o in jin["O"]]
        L = Lin
        typ = jin["type"]
        reg = O[L] + 2 * XF
        if typ == "chop":
            # crossfader cuts: B silent bars 0-1, in for bars 2-3, out for bar 4 (A's last bar), in from bar 5
            ge = gate_env([(0, 0), (O[2], 1), (O[4], 0), (O[5], 1)], reg)
            y[:, :reg] *= ge
        else:
            var = jin.get("var", {})
            M = var.get("swap_bar", L // 2)
            jit = int(var.get("fader_ms", 0) / 1000 * SR)
            hot = bool((jin.get("fix") or {}).get("hot"))
            r = int(jin["D"][min(M, L - 1)] / 8 * SR)        # bass swap within half a beat, lows summing to 1
            low = lr4(y[:, :reg], _LP)
            high = lr4(y[:, :reg], _HP)
            mid = y[:, :reg] - low - high
            # B's drums in early: mids and highs start at -6 dB (-2.5 dB when a lull was measured), highs full by
            # bar M/2 (hats cross before the bass), mids full by the swap bar M; bass killed until M
            m0 = 0.75 if hot else 0.5
            jt = lambda k: int(min(reg - 1, max(1, k + jit)))
            mp = [(0, m0)] + [(jt(O[q]), m0 + (1 - m0) * math.sin(math.pi / 2 * q / M)) for q in range(1, M + 1)]
            gm = env(mp + [(reg, 1.0)], reg)
            hq = max(1, M // 2)
            hp_ = [(0, m0)] + [(jt(O[q]), m0 + (1 - m0) * math.sin(math.pi / 2 * q / hq)) for q in range(1, hq + 1)] + [(reg, 1.0)]
            gh = env(hp_, reg)
            gl = env([(0, 0.0), (O[M] - r, 0.0), (O[M], 1.0), (reg, 1.0)], reg)
            y[:, :reg] = low * gl + mid * gm + high * gh
    elif jin and not Lin:
        y[:, :XF] *= np.linspace(0, 1, XF, dtype=np.float32)              # on the one, full level
    # ---------------- out-transition (this song is A)
    if jout and Lout:
        L = Lout
        varo = jout.get("var", {})
        M = varo.get("swap_bar", L // 2) if otyp != "chop" else L // 2
        jito = int(varo.get("fader_ms", 0) / 1000 * SR)
        hot_o = bool((jout.get("fix") or {}).get("hot"))
        k0 = g["out_start"]
        O = [k0 + o for o in jout["O"]]
        typ = otyp
        bar_n = jout["D"][-1] * SR
        r = int(bar_n / 64)
        a, b = O[0], O[L]
        seg = y[:, a:b + XF].copy()
        n = seg.shape[1]
        rel = [o - a for o in O]
        if typ == "chop":
            pts = [(0, 1), (rel[2], 0), (rel[4], 1), (rel[5], 0)]
            if jout.get("scratch"):
                pts.insert(1, (rel[2] - int(jout["D"][1] / 4 * SR), 0))   # last beat of bar 1 -> scratch
            out = seg * gate_env(pts, n)
            fx_out["tail"] = "chop A2-B2-A1-B (crossfader cuts on the bar)%s" % (" + scratch stab" if jout.get("scratch") else "")
        elif typ == "filter_sweep":
            swept = hp_sweep(seg, 30.0, 4000.0 * (n / max(1, rel[L])))
            out = swept * gate_env([(0, 1), (rel[L], 0)], n, int(0.005 * SR))
            fx_out["tail"] = "high-pass sweep 30 Hz -> 4 kHz over %d bars, A stops at the exit" % L
        else:   # bass swaps (8/16/32, ramped): highs leave first, bass swaps at bar M, mids fade M..L
            low = lr4(seg, _LP); high = lr4(seg, _HP); mid = seg - low - high
            dip = 0.63 if jout.get("dip_out_mids") else 1.0
            rr = int(bar_n / 8)
            gl = env([(0, 1), (rel[M] - rr, 1), (rel[M], 0), (n, 0)], n)
            hq = min(L, M + max(1, M // 2))
            gh = env([(0, 1), (rel[M // 2], 1), (rel[M], 0.5), (rel[hq], 0.0), (n, 0)], n)
            jo = lambda k: int(min(n - 1, max(1, k + jito)))
            fs = (M + L) // 2 if hot_o else M            # a measured lull keeps A's mids up longer
            mp = [(0, 1.0), (jo(rel[M // 2]), dip), (jo(rel[fs]), dip)]
            mp += [(jo(rel[q]), dip * math.cos(math.pi / 2 * (q - fs) / max(1, L - fs))) for q in range(fs + 1, L + 1)]
            gm = env(mp + [(n, 0)], n)
            out = low * gl + mid * gm + high * gh
            fx_out["tail"] = "bass swap on bar %d of %d (B bass killed before, A bass gone after), highs cross bars %d-%d, A mids out by bar %d%s" % (
                M + 1, L, M // 2 + 1, M + 1, L, ", A mids -4 dB" if dip < 1 else "")
        y[:, a:a + n] = out
        y[:, a + n:] = 0
    elif cutlike:
        e = knots_play[-1][1]
        last_beat = int(beat_n)
        vc = jout.get("var", {})
        c16 = int(vc.get("cut_16th", 0)) * int(beat_n / 4)
        if c16 > 0:     # late cut: A runs a 16th into B's first beat
            ext = native_run(x, knots_play[-1][0], e, e + c16)
            add_piece(y, ext, e, e + c16, ramp_in=True, ramp_out=False)
        late = max(0, c16)
        if otyp == "slam":
            if jout.get("scratch"):
                y[:, e - last_beat:e] *= np.concatenate([np.linspace(1, 0, XF), np.zeros(last_beat - XF)]).astype(np.float32)
                late = 0
                fx_out["tail"] = "cut on the one; A's last beat replaced by a scratch stab"
            else:
                fx_out["tail"] = "cut on the one"
            ce = e + late if c16 >= 0 else e + c16
            y[:, ce - XF:ce] *= np.linspace(1, 0, XF, dtype=np.float32)
            y[:, ce:] = 0
        elif otyp == "echo_out":
            # DJM-style echo-out: send the last 2 beats (lows out), dry cut on the exit downbeat, repeats ring
            # under B for ~3 bars at their natural decay (no extra fade)
            div, fbk, tb = vc.get("echo_div", ECHO_DELAY_BEATS), vc.get("echo_fb", ECHO_FB), vc.get("echo_bars", ECHO_TAIL_BARS)
            delay_n = int(round(beat_n * div))
            ns = int(beat_n * ECHO_SEND_BEATS)
            send = lr4(raw[:, e - ns:e].copy(), signal.butter(2, 200, "highpass", fs=SR, output="sos"))
            wet = echo_tail(send, delay_n, fb=fbk, n_tail=int(tb * s["bar_s"] * SR))
            g_ = int(0.05 * SR)
            wet[:, -g_:] *= np.linspace(1, 0, g_, dtype=np.float32)     # 50 ms guard at the very end only
            ce = e + late if c16 >= 0 else e + c16
            y[:, ce - XF:ce] *= np.linspace(1, 0, XF, dtype=np.float32)
            y[:, ce:] = 0
            st = e - ns
            m = min(wet.shape[1], y.shape[1] - st)
            y[:, st:st + m] += wet[:, :m] * ECHO_WET
            fx_out["tail"] = "echo-out: last 2 beats sent (lows out), dry cut on the exit downbeat, %.2f-beat delay (%.0f ms), feedback %.2f, %d-bar tail, LP %d Hz, wet %.0f dB" % (
                div, delay_n / SR * 1000, fbk, tb, ECHO_LP_HZ, 20 * np.log10(ECHO_WET))
        else:   # reverb_out: short filtered reverb thrown over A's last bar, dry cut on the one, <= 2 bars of tail
            bar_i = int(s["bar_s"] * SR)
            send = raw[:, e - bar_i:e].copy() * np.linspace(0, 1, bar_i, dtype=np.float32)
            wet = reverb_wash(send, int(REVERB_TAIL_BARS * s["bar_s"] * SR))
            g_ = int(0.25 * SR)
            wet[:, -g_:] *= np.linspace(1, 0, g_, dtype=np.float32)
            ce = e + late if c16 >= 0 else e + c16
            y[:, ce - XF:ce] *= np.linspace(1, 0, XF, dtype=np.float32)
            y[:, ce:] = 0
            st = e - bar_i
            m = min(wet.shape[1], y.shape[1] - st)
            y[:, st:st + m] += wet[:, :m] * REVERB_WET
            fx_out["tail"] = "reverb throw: wet opened over A's last bar (HP 250 Hz, room %.2f), dry cut on the exit, %d-bar tail" % (
                REVERB_ROOM, REVERB_TAIL_BARS)
    elif brake:
        tq, kq = knots[-2]
        nb = jout["brake_n"]
        if otyp == "loop_roll":
            src = x[:, int(round(tq * SR)):int(round(tq * SR)) + int(beat_n) + 1]
            out = np.zeros((2, nb), np.float32)
            pos = 0
            for frac, beats in ((0.5, 2), (0.25, 1), (0.125, 0.5), (0.0625, 0.5)):
                ln = int(round(beat_n * frac))
                reps_ = int(round(beats / frac))
                cell = src[:, :ln].copy()
                k = min(64, ln // 4)
                cell[:, :k] *= np.linspace(0, 1, k); cell[:, -k:] *= np.linspace(1, 0, k)
                for _ in range(reps_):
                    m = min(ln, nb - pos)
                    if m <= 0: break
                    out[:, pos:pos + m] = cell[:, :m]
                    pos += m
            ramp = np.linspace(0, 1, nb)
            out = hp_sweep(out, 40.0, 2000.0) * (10 ** (3 * ramp / 20)).astype(np.float32)
            y[:, kq:kq + nb] += out
            fx_out["tail"] = "loop roll on the last bar: 1/2 beat x4, 1/4 x4, 1/8 x4, 1/16 x4, HP 40 Hz -> 2 kHz, +3 dB"
            src_for_wash = out
        elif jout.get("backspin"):
            half = nb // 2                                    # beats 1-2 play, the spin starts on beat 3
            pre = native_run(x, tq, kq, kq + half)
            add_piece(y, pre, kq, kq + half, ramp_in=True, ramp_out=True)
            br = backspin(x, tq + half / SR, nb - half) * 0.5   # -6 dB, lows kept
            w = np.ones(nb - half, np.float32); w[:XF] = np.linspace(0, 1, XF)
            y[:, kq + half:kq + nb] += br * w
            fx_out["tail"] = "backspin from beat 3 of the last bar (%.2f s, -6 dB), B on the one" % ((nb - half) / SR)
            src_for_wash = br
        else:
            br = varispeed_brake(x, tq, nb)
            w = np.ones(nb, np.float32); w[:XF] = np.linspace(0, 1, XF)
            y[:, kq:kq + nb] += br * w
            fx_out["tail"] = "vinyl brake over the last bar (%.2f s) from its downbeat, B on the one" % (nb / SR)
            src_for_wash = br
        y[:, kq + nb:] = 0
        if jout.get("reverb_wash"):
            t = reverb_wash(src_for_wash, int(REVERB_TAIL_S * SR))[:, nb:] * REVERB_WET
            m = min(t.shape[1], y.shape[1] - (kq + nb))
            y[:, kq + nb:kq + nb + m] += t[:, :m]
            fx_out["tail"] += " + reverb wash"
    if g.get("fade_n"):
        e = knots_play[-1][1] + g["tail_n"]
        f = g["fade_n"]
        y[:, e - f:e] *= np.linspace(1, 0, f, dtype=np.float32)
        y[:, e:] = 0
    nz = np.nonzero(np.abs(y).max(axis=0) > 1e-7)[0]
    y = y[:, :(nz[-1] + 1 if len(nz) else 1)]
    raw = raw[:, :y.shape[1]]
    return y, raw, facs, fx_out


def detected_beats(song_id):
    f = json.load(open(os.path.join(HERE, "features", song_id + ".json")))
    return np.array(f.get("detected_beats_s") or [], float)


def map_beats(beats, knots, T0):
    kt = np.array([k[0] for k in knots]); kk = np.array([k[1] for k in knots], float)
    m = (beats >= kt[0]) & (beats <= kt[-1])
    return (np.interp(beats[m], kt, kk) + T0) / SR


def beat_alignment(a_out, b_out, lo, hi, beat_s):
    """Median offset (ms) between the two songs' tracker beats inside [lo, hi] s of the mix timeline."""
    a = a_out[(a_out >= lo) & (a_out <= hi)]
    b = b_out[(b_out >= lo) & (b_out <= hi)]
    if len(a) < 4 or len(b) < 4:
        return None, 0
    d = []
    for t in b:
        k = np.argmin(np.abs(a - t))
        dd = t - a[k]
        if abs(dd) < beat_s * 0.4:
            d.append(dd)
    if len(d) < 4:
        return None, len(d)
    d = np.array(d)
    beat_alignment.last_mad = round(float(np.median(np.abs(d - np.median(d)))) * 1000, 1)
    return round(float(np.median(d)) * 1000, 1), len(d)


def onset_env(x):
    import librosa
    m = x.mean(axis=0)
    return librosa.onset.onset_strength(y=m, sr=SR, hop_length=64, n_fft=1024)


def measure_alignment(a_raw, b_raw):
    """Lag (ms) that best aligns B's onsets to A's over the overlap; positive = B late."""
    n = min(a_raw.shape[1], b_raw.shape[1])
    if n < SR * 2:
        return None, None
    ea, eb = onset_env(a_raw[:, :n]), onset_env(b_raw[:, :n])
    ea = (ea - ea.mean()) / (ea.std() + 1e-9)
    eb = (eb - eb.mean()) / (eb.std() + 1e-9)
    maxlag = int(0.04 * SR / 64)
    best, bl = -1e9, 0
    for lag in range(-maxlag, maxlag + 1):
        if lag >= 0:
            c = np.dot(ea[:len(ea) - lag], eb[lag:])
        else:
            c = np.dot(ea[-lag:], eb[:len(eb) + lag])
        if c > best:
            best, bl = c, lag
    corr = best / len(ea)
    return round(bl * 64 / SR * 1000, 1), round(float(corr), 3)


# ---------------------------------------------------------------- main render
def fmt_ts(sec):
    m, s = divmod(int(sec), 60)
    return "%d:%02d" % (m, s)


def beat_layer(nbars, bar_n, level=1.0):
    """Synth 4/4 kick + off-beat hat at the given bar length: a beat element that bridges a lull."""
    n = int(nbars * bar_n)
    out = np.zeros(n, np.float32)
    beat = bar_n / 4
    kl = int(0.25 * SR)
    t = np.arange(kl) / SR
    kick = (np.sin(2 * np.pi * np.cumsum(45 + 75 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.12)).astype(np.float32)
    hl = int(0.04 * SR)
    rng = np.random.default_rng(7)
    hat = signal.sosfilt(signal.butter(2, 7000, "highpass", fs=SR, output="sos"), rng.standard_normal(hl))
    hat = (hat * np.exp(-np.arange(hl) / (0.01 * SR))).astype(np.float32)
    for k in range(int(nbars * 4)):
        a = int(k * beat)
        m = min(kl, n - a)
        out[a:a + m] += 0.45 * kick[:m]
        b = int(a + beat / 2)
        m = min(hl, n - b)
        if m > 0:
            out[b:b + m] += 0.12 * hat[:m]
    fade = int(bar_n)
    out[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    return np.vstack([out, out]) * level


def teaser_stabs(xB, t_b, ratio, beatA_n):
    """Stabs of B's drum section (bass off), tempo-matched to A by varispeed: bar -4: 1 beat (HP 300 Hz),
    bar -2: half bar (HP 700 Hz), bar -1: beats 3-4 transformer-gated in 1/16s (HP 1.5 kHz).
    Returns [(offset_from_join_in_samples, audio)]."""
    def bslice(t_in, n_out):
        pos = t_in * SR + np.arange(n_out) * ratio
        idx = np.arange(xB.shape[1])
        return np.vstack([np.interp(pos, idx, xB[c]) for c in range(2)]).astype(np.float32)
    out = []
    bar_n = 4 * beatA_n
    specs = [(4, 0, 1.0, 300.0, False), (2, 0, 2.0, 700.0, False), (1, 2, 2.0, 1500.0, True)]
    for k, beat_off, beats, hp, gate in specs:
        n = int(beats * beatA_n)
        a = bslice(t_b, n)
        a = lr4(a, signal.butter(2, hp, "highpass", fs=SR, output="sos"))
        g = np.ones(n, np.float32)
        r = int(0.003 * SR)
        g[:r] = np.linspace(0, 1, r); g[-r:] = np.linspace(1, 0, r)
        if gate:
            step = beatA_n / 4
            ph = (np.arange(n) // max(1, int(step))) % 2
            gg = (ph == 0).astype(np.float32)
            gg = np.convolve(gg, np.ones(r) / r, mode="same").astype(np.float32)
            g *= gg
        out.append((int(-k * bar_n + beat_off * beatA_n), a * g * 0.7))
    return out


def measure_lulls(pre_wav, J, T, songs):
    """Short-term (3 s) K-weighted loudness around every join vs the surrounding music, and near-silence runs."""
    m = LoudnessMeter()
    rms25 = []
    with sf.SoundFile(pre_wav) as f:
        while True:
            d = f.read(SR * 10, dtype="float32")
            if not len(d):
                break
            m.add(d.T)
            k = len(d) // 1102
            if k:
                rms25.extend(np.sqrt((d[:k * 1102] ** 2).mean(axis=1).reshape(k, 1102).mean(axis=1)).tolist())
    z = np.array(m.ms100)
    st = -0.691 + 10 * np.log10(np.convolve(z, np.ones(30) / 30, mode="same") + 1e-12)   # 3 s window, 0.1 s hop
    tt = np.arange(len(st)) * 0.1
    out = []
    for i, j in enumerate(J):
        tj = T[i + 1] / SR
        end = (T[i + 1] + j["O"][-1]) / SR if j["L"] else tj
        r0, r1 = tj - 3.0, end + 6.0
        reg = (tt >= r0) & (tt <= r1)
        ref_m = ((tt >= r0 - 32) & (tt <= r0 - 4)) | ((tt >= r1 + 4) & (tt <= r1 + 32))
        if not reg.any() or not ref_m.any():
            continue
        ref = float(np.median(st[ref_m]))
        lo_i = np.argmin(np.where(reg, st, 99))
        dip = ref - float(st[lo_i])
        out.append({"n": j["n"], "type": j["type"], "at_s": round(tj, 1), "ref_lufs_st": round(ref, 1),
                    "min_lufs_st": round(float(st[lo_i]), 1), "dip_lu": round(dip, 1),
                    "dip_where": "before" if tt[lo_i] < tj else ("during" if tt[lo_i] <= end else "after"),
                    "min_at_s": round(float(tt[lo_i]), 1), "overlap_end_s": round(end, 1)})
    # near-silence: 25 ms RMS below -45 dBFS for more than half a beat (0.23 s), ignoring the first/last second
    r = 20 * np.log10(np.array(rms25) + 1e-12)
    quiet = r < -45
    runs, run = [], 0
    for k, q in enumerate(quiet):
        if q and 40 <= k < len(quiet) - 40:
            run += 1
        else:
            if run * 0.025 > 0.23:
                runs.append([round((k - run) * 0.025, 2), round(run * 0.025, 2)])
            run = 0
    return out, runs


def render(plan_path, preview=None, out_base=None, plan_obj=None, premaster_only=False, fixes=None, seed=None):
    t_start = time.time()
    plan = plan_obj if plan_obj is not None else json.load(open(plan_path))
    os.makedirs(MIXES, exist_ok=True)
    work = os.path.join(MIXES, "_work")
    os.makedirs(work, exist_ok=True)
    if out_base is None:
        out_base = "preview" if preview is not None else (plan.get("out_base") or "%d - %s" % (plan["hour"], plan["name"]))
    seed = seed if seed is not None else 1000 + int(plan.get("hour", 0))
    songs, J, G, T = build_geometry(plan, preview, seed)
    for i, f in (fixes or {}).items():
        if i < len(J):
            J[i]["fix"] = f
    rng = np.random.default_rng(seed)
    pre_wav = os.path.join(work, out_base + ".premaster.wav")
    wf = sf.SoundFile(pre_wav, "w", SR, 2, subtype="FLOAT")
    acc = np.zeros((2, 0), np.float32)
    acc_start = 0
    rlog = {"plan": os.path.basename(plan_path or "inline"), "out": out_base, "joins": [], "songs": [],
            "seed": seed, "fixes": {str(J[i]["n"]): f for i, f in (fixes or {}).items() if i < len(J)}}
    prev_overlap_raw = None
    track_starts = []
    written = 0

    def place(arr, at):
        nonlocal acc
        off = at - acc_start
        assert off >= 0, "write before flush point"
        need = off + arr.shape[1]
        if need > acc.shape[1]:
            acc = np.concatenate([acc, np.zeros((2, need - acc.shape[1]), np.float32)], axis=1)
        acc[:, off:off + arr.shape[1]] += arr

    for i, g in enumerate(G):
        s = g["song"]
        t0 = time.time()
        x, lufs = load_track(s["path"], s["first_sound_s"], s["last_sound_s"])
        if g["jin"] is not None and g["jin"].get("key_shift_st"):
            st = float(g["jin"]["key_shift_st"])
            x = pedalboard.time_stretch(x, SR, 1.0, pitch_shift_in_semitones=st, high_quality=False,
                                        transient_mode=s.get("transient_mode", "crisp"), preserve_formants=True)
            x = x[:, :x.shape[1]]
        y, raw, facs, fx = render_song(i, g, x, rng, rlog)
        jo_fix = ((g["jout"] or {}).get("fix") or {}) if g["jout"] is not None else {}
        if jo_fix.get("pre_bars"):
            # lull in A's last bars before the join: make-up gain (1-bar ramps) + a beat element on A's grid
            bar_i = int(s["bar_s"] * SR)
            jo = g["jout"]
            if jo["L"]:
                e_ = g["out_start"]
            elif jo["type"] in ("brake_cut", "loop_roll"):
                e_ = g["knots"][-2][1]
            else:
                e_ = g["knots"][-1][1]
            e_ = min(e_, y.shape[1])
            n_ = min(e_, int(jo_fix["pre_bars"] * bar_i))
            a_ = e_ - n_
            gc = np.ones(n_)
            up = min(n_ // 2, bar_i)
            gc[:up] = np.linspace(0, 1, up)
            gc[-up:] = np.minimum(gc[-up:], np.linspace(1, 0.4, up))
            y[:, a_:e_] *= (10 ** (jo_fix.get("pre_makeup_db", 0) * gc / 20)).astype(np.float32)
            bl = beat_layer(n_ / bar_i, bar_i, jo_fix.get("beat_level", 0.8))
            bl[:, -bar_i // 2:] *= 0.0 if jo["L"] == 0 and jo["type"] in ("brake_cut",) else 1.0
            place(bl, T[i] + a_)
        jin = g["jin"]
        if jin is not None and jin["L"] and g["pre"] == 0 and jin.get("var") and jin["type"] != "chop":
            # beat-sync nudge: B starts a few ms off and is corrected over its first bar
            d0 = jin["var"]["sync_ms"] / 1000 * SR
            nbar = min(y.shape[1], int(jin["D"][0] * SR))
            tq = np.arange(nbar)
            src = tq - d0 * (1 - tq / nbar)
            idx = np.arange(y.shape[1])
            for c in range(2):
                y[c, :nbar] = np.interp(src, idx, y[c])
        fixd = (jin or {}).get("fix") or {}
        if jin is not None and fixd.get("post_bars"):
            # lull after the join: make-up gain on B's first bars + a beat element on B's grid
            bar_i = int(s["bar_s"] * SR)
            # blends: from 2 bars before the end of the overlap (where A has gone and B is still sparse)
            p0 = max(0, g["pre"] + jin["O"][-1] - 2 * bar_i) if jin["L"] else 0
            nb_ = min(int(fixd["post_bars"] * bar_i) + (2 * bar_i if jin["L"] else 0), y.shape[1] - p0)
            g_db = fixd.get("makeup_db", 0.0)
            gcurve = np.linspace(1, 0, nb_)
            up = min(nb_, bar_i // 2)
            if jin["L"]:
                gcurve[:up] *= np.linspace(0, 1, up)
            y[:, p0:p0 + nb_] *= (10 ** (g_db * gcurve / 20)).astype(np.float32)
            place(beat_layer(nb_ / bar_i, s["bar_s"] * SR, fixd.get("beat_level", 0.8)), T[i] + p0)
        place(y, T[i])
        if jin is not None and jin.get("teaser") and i > 0:
            A_s = songs[i - 1]
            beatA = A_s["bar_s"] / 4 * SR
            t_b = g["knots"][0][0] if g["pre"] == 0 else g["knots"][1][0]
            ratio = s["bar_s"] / A_s["bar_s"]
            for off, stab in teaser_stabs(x, t_b, ratio, beatA):
                if jin["L"] == 0 and jin["type"] in ("brake_cut", "loop_roll") and off > -4 * beatA:
                    continue          # the last bar is the brake / roll itself
                at = T[i] + off
                if at >= acc_start:
                    place(stab, at)
        my_beats = map_beats(detected_beats(s["id"]), g["knots"], T[i])
        if jin is not None and jin["L"]:
            lo = T[i] / SR
            hi = (T[i] + jin["O"][-1]) / SR
            off, nb = beat_alignment(prev_beats, my_beats, lo, hi, jin["D"][0] / 4)
            rlog["joins"][-1].update({"beat_offset_ms": off, "beats_compared": nb,
                                      "beat_spread_mad_ms": getattr(beat_alignment, "last_mad", None)})
        prev_beats = my_beats
        # scratch stab on the cut into this song (slam / chop): a 1-beat baby scratch of B's entry slice,
        # replacing A's last beat before B comes in
        if jin is not None and jin.get("scratch") and jin["type"] in ("slam", "chop"):
            nsc = int(jin["a_beat_n"])
            if jin["type"] == "slam":
                t_in, at = g["knots"][0][0], T[i]
            else:
                t_in, at = g["knots"][2][0], T[i] + jin["O"][2]
            sc = scratch_stab(x, t_in, nsc, nsc, rng)
            sc[:, -XF:] *= np.linspace(1, 0, XF, dtype=np.float32)
            place(sc, at - nsc)
        # alignment check against the previous song's overlap
        if jin is not None and jin["L"]:
            O = jin["O"]
            b_raw = raw[:, g["pre"]:g["pre"] + O[-1]]
            pass
        # FX for the outgoing transition (riser ending on B's downbeat, impact on it)
        jout = g["jout"]
        if jout is not None:
            jl = {k: jout.get(k) for k in ("n", "type", "from_title", "to_title", "a_overlap_start_bar", "a_exit_bar",
                                           "b_cue_bar", "stretch_pct", "stretch_side", "pair_score", "vocal_overlap",
                                           "dip_out_mids", "reverb_wash", "scratch", "backspin", "key_shift_st", "reasons")}
            jl["overlap_bars_rendered"] = jout["L"]
            jl["phase_corr_ms"] = jout.get("phase_corr_ms")
            jl["variance"] = jout.get("var")
            jl["teaser"] = bool(jout.get("teaser"))
            jl["fix"] = jout.get("fix")
            jl["at_s"] = round(T[i + 1] / SR, 3)
            jl["tail"] = fx.get("tail")
            if jout["L"]:
                jl["bar_s_ramp"] = [round(jout["D"][0], 4), round(jout["D"][-1], 4)]
                jl["geom_downbeat_err_ms"] = 0.0
                k0 = g["out_start"]
                prev_overlap_raw = raw[:, k0:k0 + jout["O"][-1]].copy()
            else:
                prev_overlap_raw = None
                beat_n = s["bar_s"] / 4 * SR
                rn = int(4 * s["bar_s"] * SR)
                if jout["type"] in ("brake_cut", "loop_roll") or jout.get("riser") or (jout.get("fix") or {}).get("pre_riser"):
                    rs = riser(rn, beat_n, rng)
                    place(rs, T[i + 1] - rn)
                    place(impact(rng), T[i + 1])
                    jl["riser"] = "noise riser %.1f s (4 bars) ending on B's downbeat + sub impact" % (rn / SR)
                jl["fell_back_to_cut"] = bool([r for r in (jout.get("reasons") or []) if r.startswith("cut:")])
            rlog["joins"].append(jl)
        rlog["songs"].append({"pos": i + 1, "title": s["title"], "start_s": round(T[i] / SR, 2),
                              "src_lufs": round(lufs, 2), "bars": [g["b0"], g["b1"]],
                              "max_stretch_pct": round(max([abs(1 - f) for f in facs] or [0]) * 100, 2),
                              "secs": round(time.time() - t0, 1)})
        # track start for CUE: bass-swap midpoint of the incoming overlap, or the cut point
        if i == 0:
            track_starts.append(0.0)
        elif jin["L"]:
            track_starts.append((T[i] + jin["O"][jin["L"] // 2]) / SR)
        else:
            track_starts.append(T[i] / SR)
        log("  %2d/%d %-55s start %s  %.1fs  %s" % (i + 1, len(G), s["title"][:55], fmt_ts(T[i] / SR),
                                                      time.time() - t0, fx.get("tail") or ""))
        # flush everything before the next song's start
        flush_to = (T[i + 1] - int(20 * SR)) if i + 1 < len(G) else acc_start + acc.shape[1]
        flush_to = max(flush_to, acc_start)
        nfl = flush_to - acc_start
        if nfl > 0:
            wf.write(acc[:, :nfl].T)
            written += nfl
            acc = acc[:, nfl:]
            acc_start = flush_to
        del x, y, raw
    if acc.shape[1]:
        wf.write(acc.T)
        written += acc.shape[1]
    wf.close()
    total_s = written / SR
    log("premaster written: %.1f min (%.0f s render)" % (total_s / 60, time.time() - t_start))
    lulls, quiet_runs = measure_lulls(pre_wav, J, T, songs)
    rlog["lulls"] = lulls
    rlog["near_silence_runs"] = quiet_runs
    if premaster_only:
        return {"lulls": lulls, "quiet_runs": quiet_runs, "pre_wav": pre_wav, "songs": songs, "J": J, "G": G, "T": T, "rlog": rlog,
                "track_starts": track_starts, "total_s": total_s}
    res = master_and_encode(pre_wav, out_base, plan, songs, track_starts, total_s)
    rlog.update(res)
    planned = plan["planned_duration_s"] if preview is None else None
    rlog["duration_s"] = round(total_s, 1)
    rlog["planned_duration_s"] = planned
    rlog["render_secs"] = round(time.time() - t_start, 1)
    # sanity checks
    checks = {}
    checks["no_clipping"] = bool(res["sample_peak_dbfs"] < -0.05)
    checks["no_silent_gaps"] = len(res["silent_gaps"]) == 0
    lags = [j.get("measured_lag_ms") for j in rlog["joins"] if j.get("measured_lag_ms") is not None]
    checks["joins_geom_within_10ms"] = bool(all(j.get("geom_downbeat_err_ms", 0) <= 10 for j in rlog["joins"]))
    bo = [j.get("beat_offset_ms") for j in rlog["joins"] if j.get("beat_offset_ms") is not None]
    checks["joins_tracker_beats_within_10ms"] = "%d of %d" % (sum(abs(v) <= 10 for v in bo), len(bo))
    checks["joins_over_10ms"] = [[j["n"], j.get("beat_offset_ms")] for j in rlog["joins"]
                                 if j.get("beat_offset_ms") is not None and abs(j["beat_offset_ms"]) > 10]
    if planned:
        checks["duration_vs_plan_s"] = round(total_s - planned, 1)
        checks["duration_ok"] = bool(abs(total_s - planned) < 60)
    checks["lull_joins_over_2lu"] = [[l["n"], l["dip_lu"]] for l in rlog.get("lulls", []) if l["dip_lu"] > 2]
    checks["near_silence_over_half_beat"] = rlog.get("near_silence_runs", [])
    rlog["checks"] = checks
    with open(os.path.join(MIXES, out_base + ".render.json"), "w") as fh:
        json.dump(rlog, fh, indent=1)
    write_text(out_base, plan, songs, J, track_starts, rlog)
    log(json.dumps(checks))
    return rlog


def master_and_encode(pre_wav, out_base, plan, songs, track_starts, total_s):
    blk = SR * 10
    meter = LoudnessMeter()
    with sf.SoundFile(pre_wav) as f:
        while True:
            d = f.read(blk, dtype="float32")
            if not len(d):
                break
            meter.add(d.T)
    l_pre = meter.integrated()
    gain_db = TARGET_LUFS - l_pre
    mast = os.path.join(MIXES, "_work", out_base + ".master.wav")
    hist = []
    best = None
    tmp = mast + ".pass.wav"
    for it in range(6):
        lim = pedalboard.BrickwallLimiter(ceiling_db=CEILING_DB - MP3_MARGIN_DB, release_ms=80.0, true_peak=True)
        m2 = LoudnessMeter()
        g = 10 ** (gain_db / 20)
        peak = 0.0
        ms = []
        with sf.SoundFile(pre_wav) as f, sf.SoundFile(tmp, "w", SR, 2, subtype="FLOAT") as w:
            n_in = f.frames
            n_out = 0
            while True:
                d = f.read(blk, dtype="float32")
                last = len(d) < blk
                if len(d):
                    o = lim.process((d.T * g).astype(np.float32), SR, reset=False)
                else:
                    o = np.zeros((2, 0), np.float32)
                if last:
                    o = np.concatenate([o, lim.process(np.zeros((2, SR), np.float32), SR, reset=False)], axis=1)
                o = o[:, :n_in - n_out]
                if o.shape[1]:
                    w.write(o.T)
                    m2.add(o)
                    peak = max(peak, float(np.abs(o).max()))
                    r = o.reshape(2, -1)[:, :o.shape[1] // 4410 * 4410].reshape(2, -1, 4410)
                    ms.extend(np.sqrt((r ** 2).mean(axis=(0, 2))).tolist())
                    n_out += o.shape[1]
                if last:
                    break
        l_out = m2.integrated()
        log("  master pass %d: gain %+.2f dB -> %.2f LUFS, sample peak %.2f dBFS" % (
            it + 1, gain_db, l_out, 20 * np.log10(peak + 1e-12)))
        if best is None or abs(l_out - TARGET_LUFS) < abs(best[1] - TARGET_LUFS):
            os.replace(tmp, mast)
            best = (gain_db, l_out, peak, ms)
        if abs(l_out - TARGET_LUFS) <= 0.12:
            break
        hist.append((gain_db, l_out))
        if len(hist) >= 2:
            (g1, l1), (g2, l2) = hist[-2], hist[-1]
            slope = (l2 - l1) / (g2 - g1) if g2 != g1 else 0
            if slope < 0.15:
                log("  limiter saturated: keeping the closest pass")
                break
            gain_db = g2 + (TARGET_LUFS - l2) / slope
        else:
            gain_db += (TARGET_LUFS - l_out) * 1.3
    if os.path.exists(tmp):
        os.remove(tmp)
    gain_db, l_out, peak, ms = best
    # silent gaps: >= 1 s below -50 dBFS RMS, ignoring the first/last 2 s
    rms_db = 20 * np.log10(np.array(ms) + 1e-12)
    gaps = []
    run = 0
    for k, v in enumerate(rms_db):
        if v < -50 and 20 <= k < len(rms_db) - 20:
            run += 1
        else:
            if run >= 10:
                gaps.append([round((k - run) * 0.1, 1), round(run * 0.1, 1)])
            run = 0
    mp3 = os.path.join(MIXES, out_base + ".mp3")
    cmd = [FFMPEG, "-y", "-loglevel", "error", "-i", mast, "-c:a", "libmp3lame", "-b:a", "320k",
           "-id3v2_version", "3", "-metadata", "title=%s" % (plan["name"] if not out_base.startswith("preview") else "Preview"),
           "-metadata", "artist=Halloween 2026 auto-DJ", "-metadata", "album=Halloween party 2026",
           "-metadata", "track=%d" % plan["hour"], mp3]
    subprocess.run(cmd, check=True)
    # final measurement of the MP3 (integrated loudness + true peak)
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostats", "-i", mp3, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True)
    txt = r.stderr
    import re
    I = re.findall(r"I:\s+(-?[\d.]+) LUFS", txt)
    TP = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", txt)
    os.remove(pre_wav)
    os.remove(mast)
    return {"premaster_lufs": round(float(l_pre), 2), "master_gain_db": round(float(gain_db), 2),
            "master_lufs": round(float(l_out), 2), "sample_peak_dbfs": round(20 * np.log10(peak + 1e-12), 2),
            "mp3": mp3, "mp3_bytes": os.path.getsize(mp3),
            "mp3_integrated_lufs": float(I[-1]) if I else None, "mp3_true_peak_dbtp": float(TP[-1]) if TP else None,
            "silent_gaps": gaps}


def write_text(out_base, plan, songs, J, starts, rlog):
    mp3name = out_base + ".mp3"
    cue = ['PERFORMER "Halloween 2026 auto-DJ"', 'TITLE "%s"' % plan["name"], 'FILE "%s" MP3' % mp3name]
    for i, (s, t) in enumerate(zip(songs, starts)):
        art, _, ttl = s["title"].partition(" - ")
        fr = int(round(t * 75))
        mm, rem = divmod(fr, 75 * 60)
        ss, ff = divmod(rem, 75)
        cue += ["  TRACK %02d AUDIO" % (i + 1), '    TITLE "%s"' % (ttl or s["title"]).replace('"', "'"),
                '    PERFORMER "%s"' % art.replace('"', "'"), "    INDEX 01 %02d:%02d:%02d" % (mm, ss, ff)]
    with open(os.path.join(MIXES, out_base + ".cue"), "w") as fh:
        fh.write("\n".join(cue) + "\n")
    lines = ["%s  (hour %d, %s lean)" % (plan["name"], plan["hour"], plan["lean"]),
             "Duration %s, %d songs, mastered %.1f LUFS integrated, true peak %.1f dBTP" % (
                 fmt_ts(rlog.get("duration_s") or 0), len(songs), rlog.get("mp3_integrated_lufs") or 0,
                 rlog.get("mp3_true_peak_dbtp") or 0),
             "H = Halloween.  Join = how this song comes in.", ""]
    for i, (s, t) in enumerate(zip(songs, starts)):
        j = J[i - 1] if i else None
        jt = "start" if not j else "%s%s, %+.1f%%%s" % (
            j["type"], (" %d bars" % j["L"]) if j["L"] else "", j["stretch_pct"],
            ", reverb wash" if j.get("reverb_wash") else (", scratch" if j.get("scratch") else ""))
        lines.append("%6s  %s %-58s %6.1f BPM  %-4s  [%s]" % (fmt_ts(t), "H" if s["hal"] else " ", s["title"][:58],
                                                             s["bpm"], s["key"] or "?", jt))
    with open(os.path.join(MIXES, out_base + ".txt"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


def compute_fixes(lulls, quiet_runs, J, prev=None):
    """Turn measured lulls (> 2 LU below the surrounding music) and near-silences into per-join fixes;
    with `prev` (fixes of the last pass) the fixes are escalated for joins that still dip."""
    idx = {j["n"]: i for i, j in enumerate(J)}
    fixes = {k: dict(v) for k, v in (prev or {}).items()}
    for l in lulls:
        if l["dip_lu"] <= 2.0:
            continue
        i = idx[l["n"]]
        if i in fixes:
            f = fixes[i]
            if l["dip_where"] == "before":
                f["pre_bars"] = 4
                f["pre_makeup_db"] = round(min(6.0, f.get("pre_makeup_db", 0) + l["dip_lu"]), 1)
                f["beat_level"] = 0.9
                if not J[i]["L"]:
                    f["pre_riser"] = True
            else:
                f["post_bars"] = max(4, f.get("post_bars", 0))
                f["makeup_db"] = round(min(6.0, f.get("makeup_db", 0) + l["dip_lu"]), 1)
                f["beat_level"] = 0.9
                if J[i]["L"]:
                    f["hot"] = True
            continue
        if l["dip_where"] == "before":
            fixes[i] = {"pre_bars": 4, "pre_makeup_db": round(min(4.0, l["dip_lu"]), 1), "beat_level": 0.8}
            if not J[i]["L"]:
                fixes[i]["pre_riser"] = True
        elif J[i]["L"]:
            fixes[i] = {"hot": True}
            if l["dip_where"] == "after" or l["min_at_s"] > l["overlap_end_s"] - 4:
                fixes[i].update(post_bars=4, makeup_db=round(min(4.0, l["dip_lu"]), 1), beat_level=0.7)
        else:
            fixes[i] = {"post_bars": 4, "makeup_db": round(min(4.0, l["dip_lu"]), 1), "beat_level": 0.8}
    ats = [(l["at_s"], idx[l["n"]]) for l in lulls]
    for t0, dur in quiet_runs:
        if not ats:
            break
        at, i = min(ats, key=lambda a: abs(a[0] - t0))
        if abs(at - t0) < 12:
            f = fixes.setdefault(i, {})
            if J[i]["L"]:
                f["hot"] = True
            else:
                f.setdefault("post_bars", 2)
                f.setdefault("beat_level", 0.8)
                f.setdefault("makeup_db", 2.0)
    return fixes


def render_checked(plan_path, preview=None):
    """Two passes: render, measure every join's short-term loudness, fix the lulls, render again and master."""
    plan = json.load(open(plan_path))
    p1 = render(plan_path, preview, plan_obj=plan, premaster_only=True)
    os.remove(p1["pre_wav"])
    fixes = compute_fixes(p1["lulls"], p1["quiet_runs"], p1["J"])
    log("pass 1: %d joins over 2 LU, %d near-silences -> %d fixes" % (
        sum(1 for l in p1["lulls"] if l["dip_lu"] > 2), len(p1["quiet_runs"]), len(fixes)))
    p2 = render(plan_path, preview, plan_obj=plan, premaster_only=True, fixes=fixes)
    os.remove(p2["pre_wav"])
    fixes = compute_fixes(p2["lulls"], [], p2["J"], fixes)
    log("pass 2: %d joins over 2 LU -> %d fixes (escalated)" % (sum(1 for l in p2["lulls"] if l["dip_lu"] > 2), len(fixes)))
    r = render(plan_path, preview, plan_obj=plan, fixes=fixes)
    r["lulls_pass2"] = p2["lulls"]
    r["lulls_pass1"] = p1["lulls"]
    r["near_silence_pass1"] = p1["quiet_runs"]
    with open(os.path.join(MIXES, r["out"] + ".render.json"), "w") as fh:
        json.dump(r, fh, indent=1, default=float)
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("plan")
    ap.add_argument("--preview", type=int, default=None, help="render only the first N joins to mixes/preview.mp3")
    ap.add_argument("--one-pass", action="store_true", help="skip the lull measurement / fix pass")
    a = ap.parse_args()
    r = render(a.plan, a.preview) if a.one_pass else render_checked(a.plan, a.preview)
    log("done: %s  %.1f min  %.2f LUFS  TP %.2f dBTP  %.1f MB  render %.0f s" % (
        r["mp3"], r["duration_s"] / 60, r["mp3_integrated_lufs"] or 0, r["mp3_true_peak_dbtp"] or 0,
        r["mp3_bytes"] / 1e6, r["render_secs"]))
    bad = [l for l in r.get("lulls", []) if l["dip_lu"] > 2]
    log("lull check: %d joins, %d still more than 2 LU below the music: %s; near-silences: %s" % (
        len(r.get("lulls", [])), len(bad), [(l["n"], l["dip_lu"]) for l in bad], r.get("near_silence_runs")))
    for j in r["joins"]:
        log("  join %2d %-16s phase %s ms, residual %s ms  %s" % (j["n"], j["type"], j.get("phase_corr_ms"),
                                                                   j.get("beat_offset_ms"), j.get("tail")))


if __name__ == "__main__":
    main()
