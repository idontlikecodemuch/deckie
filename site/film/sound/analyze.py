# /// script
# requires-python = ">=3.10"
# dependencies = ["librosa>=0.10", "numpy", "matplotlib", "soundfile"]
# ///
"""Picture of one soundtrack: spectrogram with the film's section entries and accents marked, level over time,
and the numbers that stand in for listening.   uv run analyze.py <mix.wav> <title> <out.png> <hits.json>"""
import sys, json, numpy as np, librosa, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
wav, title, out, hitsf = sys.argv[1:5]
y, sr = librosa.load(wav, sr=None, mono=True)
hits = json.load(open(hitsf))
S = librosa.amplitude_to_db(librosa.feature.melspectrogram(y=y, sr=sr, n_fft=4096, hop_length=1024, n_mels=128, fmax=16000) ** 0.5, ref=np.max)
def db(a, b, lo=None, hi=None):
    seg = y[int(a * sr):int(b * sr)]
    if lo or hi:
        import scipy.signal as sg
        seg = sg.sosfilt(sg.butter(4, [lo or 20, hi or sr / 2 - 1], btype="band", fs=sr, output="sos"), seg)
    return 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9)
env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=128)
ons = librosa.onset.onset_detect(onset_envelope=env, sr=sr, hop_length=128, backtrack=True, units="time", delta=0.04)
off = np.array([(ons - h["t"])[np.argmin(np.abs(ons - h["t"]))] * 1000 for h in hits])
step_all, step_low = db(16, 18) - db(14, 16), db(16, 18, 30, 150) - db(14, 16, 30, 150)
fig, ax = plt.subplots(2, 1, figsize=(24, 9), gridspec_kw={"height_ratios": [3, 1]})
librosa.display.specshow(S, sr=sr, hop_length=1024, x_axis="time", y_axis="mel", fmax=16000, ax=ax[0], cmap="magma", vmin=-70)
for t, name in ((0, "opening"), (12, "name"), (16, "Deckie Desk: the beat enters"), (28, "Deckie Booth"), (59, "The dictionary"), (64, "Your music / Your mix"), (68, "end card")):
    ax[0].axvline(t, color="w", lw=1.4); ax[0].text(t + 0.15, 13000, name, color="w", fontsize=11, va="top")
for h in hits: ax[0].plot([h["t"]], [60], marker="^", color="#7CFFB2", ms=7)
ax[0].set_title(f"{title}   |   green marks: the film's {len(hits)} picture accents   |   {int((np.abs(off) <= 20).sum())}/{len(off)} accents within 20 ms of a sound onset, median {np.median(np.abs(off)):.1f} ms   |   at 16 s: level {step_all:+.1f} dB, below 150 Hz {step_low:+.1f} dB")
ax[0].set_xlim(0, 76)
t = np.arange(0, 76, 0.25); r = [db(a, a + 0.5) for a in t]; rl = [db(a, a + 0.5, 30, 150) for a in t]
ax[1].plot(t, r, color="#222", label="level, all frequencies (dB)"); ax[1].plot(t, rl, color="#b05", label="below 150 Hz (dB)")
for tt in (12, 16, 28, 59, 64, 68): ax[1].axvline(tt, color="#888", lw=0.8)
ax[1].set_xlim(0, 76); ax[1].set_ylim(-60, -5); ax[1].legend(loc="lower right"); ax[1].set_xlabel("seconds")
fig.tight_layout(); fig.savefig(out, dpi=80)
late = [(h["label"], round(o)) for h, o in zip(hits, off) if abs(o) > 20]
print(json.dumps({"title": title, "within20": int((np.abs(off) <= 20).sum()), "of": len(off), "median_ms": round(float(np.median(np.abs(off))), 1), "step16_db": round(float(step_all), 1), "step16_low_db": round(float(step_low), 1), "outside": late}))
