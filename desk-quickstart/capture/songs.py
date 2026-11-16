#!/usr/bin/env python3
"""Generated songs for the quick-start captures: real beats, a key, sections of different loudness, invented names.

Never a real song or artist: the titles and acts are made the way the demo crate's are (site/film/capture/
make_demo_crate.py), two invented words each. The sound is drum, bass and chord tones made here from nothing.

    python3 songs.py <out folder>        (needs numpy and ffmpeg)
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1]
rng = np.random.default_rng(11)


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


KICK = np.sin(2 * np.pi * np.cumsum(45 + 110 * env_exp(int(.35 * SR), .03)) / SR) * env_exp(int(.35 * SR), .12)
_sn = int(.2 * SR)
SNARE = rng.standard_normal(_sn) * env_exp(_sn, .05) * .6 + np.sin(2 * np.pi * 190 * np.arange(_sn) / SR) * env_exp(_sn, .04) * .5
_hh = int(.05 * SR)
HAT = np.diff(rng.standard_normal(_hh + 1)) * env_exp(_hh, .012) * .25


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def place(buf, sample, at, gain):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sample))
    buf[i:j] += sample[: j - i] * gain


def tone(freq, n, kind="sine"):
    t = np.arange(n) / SR
    if kind == "saw":
        return sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 6)) * .5
    return np.sin(2 * np.pi * freq * t)


def song(bpm, root, minor, sections):
    """sections: (bars, level, parts) with parts from k kick, s snare, h hats, b bass, p chords."""
    beat = 60.0 / bpm
    bar = beat * 4
    bars = sum(s[0] for s in sections)
    buf = np.zeros(int((bars * bar + 1.0) * SR))
    prog = [0, 8, 3, 10] if minor else [0, 5, 7, 5]
    b0 = 0
    for nb, level, parts in sections:
        for bi in range(nb):
            t0 = (b0 + bi) * bar
            step = prog[(b0 + bi) % 4]
            r = root + step
            third = 3 if (minor and step == 0) else 4
            for q in range(4):
                tb = t0 + q * beat
                if "k" in parts:
                    place(buf, KICK, tb, 1.0 * level)
                if "s" in parts and q in (1, 3):
                    place(buf, SNARE, tb, .7 * level)
                if "h" in parts:
                    place(buf, HAT, tb + beat / 2, .8 * level)
                    place(buf, HAT, tb, .4 * level)
                if "b" in parts:
                    nn = int(beat * .8 * SR)
                    place(buf, tone(midi_hz(r - 12), nn, "saw") * env_exp(nn, beat * .5), tb, .35 * level)
            if "p" in parts:
                nn = int(bar * SR)
                a = np.minimum(1, np.arange(nn) / (.25 * SR)) * np.minimum(1, (nn - np.arange(nn)) / (.2 * SR))
                chord = sum(tone(midi_hz(r + 12 + iv), nn) for iv in (0, third, 7)) / 3
                place(buf, chord * a, t0, .35 * level)
        b0 += nb
    return buf


INTRO, BODY, BREAK = (8, .3, "khp"), (16, 1, "ksbhp"), (8, .25, "p")
# (file, title, artist, tempo in BPM, root note as a MIDI number, minor, sections)
SONGS = [
    ("01 Juniper Bureau - Velvet Stations", "Velvet Stations", "Juniper Bureau", 122, 57, True, [INTRO, BODY, BREAK, BODY]),
    ("02 Cobalt Parade - Copper Weather", "Copper Weather", "Cobalt Parade", 124, 62, False, [INTRO, BODY, BODY]),
    ("03 Linden Exchange - Hollow Postcards", "Hollow Postcards", "Linden Exchange", 126, 65, True, [INTRO, BODY, BREAK, BODY]),
    ("04 Marble Society - Saffron Motion", "Saffron Motion", "Marble Society", 118, 55, True, [INTRO, BODY, BODY]),
    ("05 Ember Motel - Static Garden", "Static Garden", "Ember Motel", 128, 64, True, [INTRO, BODY, BREAK, BODY]),
    ("06 Atlas Ensemble - Cherry Voltage", "Cherry Voltage", "Atlas Ensemble", 100, 60, False, [INTRO, BODY, BODY]),
    ("07 Orchid Union - Lucky Carousel", "Lucky Carousel", "Orchid Union", 124, 59, False, [INTRO, BODY, BREAK, BODY]),
    ("08 Quartz Department - Glass Satellites", "Glass Satellites", "Quartz Department", 130, 58, True, [INTRO, BODY, BODY]),
    ("09 Tundra Works - Honey Skyline", "Honey Skyline", "Tundra Works", 96, 63, False, [INTRO, BODY, BREAK, BODY]),
    ("10 Pollen Arcade - Quiet Signal", "Quiet Signal", "Pollen Arcade", 120, 61, True, [INTRO, BODY, BODY]),
    ("11 Garnet Club - Paper Tides", "Paper Tides", "Garnet Club", 125, 56, True, [INTRO, BODY, BREAK, BODY]),
    ("12 Alder Assembly - Second Harbour", "Second Harbour", "Alder Assembly", 127, 66, False, [INTRO, BODY, BODY]),
]

os.makedirs(OUT, exist_ok=True)
for f, title, artist, bpm, root, minor, sec in SONGS:
    buf = song(bpm, root, minor, sec)
    buf = buf / np.max(np.abs(buf)) * .89
    pcm = (buf * 32767).astype(np.int16)
    tmp = os.path.join(OUT, f + ".tmp.wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-ac", "2", "-b:a", "192k",
                    "-metadata", f"title={title}", "-metadata", f"artist={artist}", "-metadata", "album=Generated Tones",
                    os.path.join(OUT, f + ".mp3")], check=True)
    os.remove(tmp)
    print(f, bpm, round(len(buf) / SR, 1), "s")
