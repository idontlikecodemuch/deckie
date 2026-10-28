#!/usr/bin/env python3
"""Write the audio files the DeckieDecode tests decode. The audio is generated here, never downloaded, so it is
Deckie's own and carries no licence question.

  python3 core/Tools/make_audio_fixtures.py      # from anywhere; needs numpy and ffmpeg built with libmp3lame

The signal: 4 s of stereo. Left, a 440 Hz sine at -6 dBFS (peak); right, a 1000 Hz sine at -12 dBFS; on both
channels one full-scale single-sample click at exactly 2.000 s (where both sines are zero).

Outputs, in core/Tests/DeckieDecodeTests/Fixtures/:
  tone.wav      the signal at 44.1 kHz as 16-bit PCM, written with Python's wave module (the reference)
  tone48k.wav   the same signal computed at 48 kHz (click at sample 96000), 16-bit PCM
  tone.mp3      tone.wav through ffmpeg with libmp3lame, 192 kbps, 44.1 kHz (the LAME tag records delay and padding)
  tone.m4a      tone.wav through ffmpeg's native AAC encoder, 160 kbps, 44.1 kHz (the MP4 edit list records priming)

The ffmpeg command-line program is a development tool here and nothing else: no Deckie code links ffmpeg
(DEPENDENCIES.md, "Checked and rejected"). The same ffmpeg build gives the same bytes on every run: version strings
and metadata are left out (bitexact). FFMPEG=/path/to/ffmpeg picks another ffmpeg; the default is /usr/bin/ffmpeg.
"""
import hashlib, os, subprocess, wave
import numpy as np

SECONDS = 4
CLICK_S = 2.0
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "DeckieDecodeTests", "Fixtures")
FFMPEG = os.environ.get("FFMPEG", "/usr/bin/ffmpeg")

# name, ffmpeg output arguments
ENCODES = [
    ("tone.mp3", ["-c:a", "libmp3lame", "-b:a", "192k", "-ar", "44100"]),
    ("tone.m4a", ["-c:a", "aac", "-b:a", "160k", "-ar", "44100"]),
]


def signal(rate):
    """The test signal at `rate` as float64, shape (frames, 2), full scale 1.0."""
    t = np.arange(rate * SECONDS) / rate
    left = 10 ** (-6 / 20) * np.sin(2 * np.pi * 440 * t)
    right = 10 ** (-12 / 20) * np.sin(2 * np.pi * 1000 * t)
    y = np.stack([left, right], axis=1)
    y[int(round(CLICK_S * rate)), :] = 1.0
    return y


def write_wav(path, y, rate):
    pcm = np.clip(np.round(y * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(y.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def encode(src, name, args):
    subprocess.run([FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", *args,
                    os.path.join(OUT, name)], check=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, "tone.wav")
    write_wav(wav, signal(44100), 44100)
    write_wav(os.path.join(OUT, "tone48k.wav"), signal(48000), 48000)
    for name, args in ENCODES:
        encode(wav, name, args)
    version = subprocess.run([FFMPEG, "-version"], capture_output=True, text=True, check=True).stdout.splitlines()[0]
    print(version)
    total = 0
    for name in ["tone.wav", "tone48k.wav"] + [e[0] for e in ENCODES]:
        p = os.path.join(OUT, name)
        size = os.path.getsize(p)
        total += size
        with open(p, "rb") as f:
            print(f"{hashlib.sha256(f.read()).hexdigest()}  {name}  {size} bytes")
    print(f"total {total} bytes")


if __name__ == "__main__":
    main()
