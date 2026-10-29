#!/usr/bin/env python3
"""Write the reference numbers the engine's key method must reproduce: research R's recommended estimator (row 3f,
docs/research/r-key-parity.md), run stage by stage by mixer/key_parity.py's own functions on synthesised signals.
The Swift port is DeckieCore/Key/HPCPKey.swift; Tests/DeckieCoreTests/KeyTests.swift compares every stage.

  python3 core/Tools/make_key_parity_fixtures.py        # from anywhere; needs numpy, scipy, librosa and soundfile

Nothing of the method is copied here. key_parity.py is imported as it is (it imports mixer/key_light.py, hence
soundfile and librosa) and its functions are called with the arguments its `recommended` passes: `spectral_peaks`
(frames, spectral peaks, the whitening envelopes), `hpcp` (4 harmonics, whitened by the +-1/3 octave envelope, no
per-frame normalisation), `corr24` and `km` (Pearson correlation against the 24 keys), `decide` (the three-profile
mean, the margin, the agreement and the sure flag). Every signal's decision is checked against `recommended(y)`
itself, so the stages written are the ones `recommended` runs. The frame spectra (`X`, the magnitudes the peaks are
picked from) are not returned by `spectral_peaks`; they are read as the function hands them to `np.cumsum` (its
first use of them, for an envelope the method does not use), so the stored spectra are the reference's own array.

The signals are synthesised by core/Tools/make_dsp_fixtures.py's `synth` and `progression` (imported), the recipe of
DeckieTestSupport's `ChordSynth`, so the Swift tests rebuild the same float32 samples from the parameters stored
here: tones, chords, chord progressions, noise, silence, and a short track whose key moves a tritone halfway. Each
signal is rounded to float32 before the analysis, as key_parity.py's `load44` reads audio (soundfile, float32).

Profiles. The decision is written twice: with key_parity.py's tables as they are (`key_light` below: mixer/
key_light.py's PROFILES, transcribed from Essentia's key.cpp), which is what `key_parity_keys.tsv` holds per track
and so what the engine's parity hook reproduces; and with the tables as the literature prints them (`literature`),
which the engine decides with. They differ in one number: edma's major profile at the minor sixth (the fifth
semitone above the dominant) is 0.32 in Faraldo's thesis (2017, figure 6.5, p. 150; the point plotted there reads
0.3159) and 0.31 in key.cpp. The literature table is set by replacing key_parity's own PROFILES entry for edma (and
emptying its cache of key matrices) before the second run; nothing else changes.

Output: core/Tests/DeckieCoreTests/Fixtures/key_parity.json
  constants      the reference's frame, band and envelope constants, the Hann window's sum and the spectrum scale
  profiles       the two tables, each {name: [major 12, minor 12]}
  signals        per signal: the recipe, a check of the samples, the frame count; for a few frames the spectrum X
                 (bins 0 to 460, float32), the 60 peaks after interpolation (F, M) and their whitening envelope E
                 (the whitened peak is M / E), and that frame's HPCP; every frame's HPCP; their mean (the HPCP
                 `decide` reads); and for each table the 24 correlations per profile and averaged, the key, the margin,
                 the agreement and the sure flag
  vectors        the correlation and decision stages alone on 66 made-up HPCP vectors (60 from SplitMix64: shaped
                 like a rotated profile with more or less noise, or nearly flat; 6 by hand, two of them symmetric so
                 that keys tie exactly), for both tables (each profile's correlations for key_light's only)
"""
import json, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "core", "Tests", "DeckieCoreTests", "Fixtures")
sys.path.insert(0, os.path.join(ROOT, "mixer"))
sys.path.insert(0, HERE)
import key_parity as KP  # noqa: E402  (the lab's module, read as it is; nothing in it runs on import)
from make_dsp_fixtures import synth, progression, splitmix, C, F, G, Am, Dm, E, Fs, B, Cs  # noqa: E402

SR = KP.SR44
D, A = [38, 62, 66, 69], [45, 69, 73, 76]  # DeckieTestSupport's ChordSynth.D and .A
ENVELOPE_BINS = 461                          # key_parity's `nb` for the whitening envelope: bins 0 to 460
SELECTED = 3                                 # frames per signal stored in full: first, middle, last


def f32(x):
    """Shortest text that reads back as the same float32 (Swift's Float(x) is then exact)."""
    return float(str(np.float32(x)))


def signals():
    """(name, samples, chords, harmonics, noise, seed): ChordSynth's recipe, at 44.1 kHz."""
    s1, s2, s8, s16 = SR, 2 * SR, 8 * SR, 16 * SR
    half = 8 * SR
    change = progression(SR, half, 1.0, [C, F, G, C]) + [(a + half, b + half, m) for a, b, m in
                                                         progression(SR, half, 1.0, [Fs, B, Cs, Fs])]
    return [
        ("tone_a4", s1, [(0, s1, [69])], 1, 0.0, 11),
        ("tones_low_high_detuned", 3 * SR // 2, [(0, 3 * SR // 2, [28, 33, 61.3, 79.6, 104.5])], 3, 0.001, 12),
        ("chord_c_major", s2, [(0, s2, C)], 6, 0.01, 13),
        ("chord_a_minor", s2, [(0, s2, Am)], 6, 0.01, 14),
        ("progression_g_major", s8, progression(SR, s8, 1.0, [G, C, D, G]), 6, 0.02, 15),
        ("progression_a_minor", s8, progression(SR, s8, 2.0, [Am, Dm, E, Am]), 6, 0.02, 16),
        ("noise", s2, [], 1, 0.3, 17),
        ("silence", s1, [], 1, 0.0, 18),
        ("key_change_c_to_f_sharp", s16, change, 6, 0.02, 19),
    ]


def reference_peaks(y):
    """key_parity.spectral_peaks(y), and the frame spectra X it computed, taken from its call of np.cumsum."""
    seen = []
    real = np.cumsum

    def spy(a, *args, **kw):
        if not seen:
            seen.append(np.array(a, copy=True))
        return real(a, *args, **kw)
    np.cumsum = spy
    try:
        F_, M_, E_, rms, Emax = KP.spectral_peaks(y)
    finally:
        np.cumsum = real
    return F_, M_, Emax[1 / 3], seen[0]


def literature_tables():
    """key_parity's tables with edma's major profile as Faraldo's thesis prints it (one value differs)."""
    t = {k: (list(v[0]), list(v[1])) for k, v in KP.PROFILES.items() if k in KP.FARALDO}
    assert t["edma"][0][8] == 0.31, "key_light's edma changed; check the literature table again"
    t["edma"][0][8] = 0.32
    return t


def use_tables(tables):
    """Point key_parity at `tables` (its own PROFILES dict, its own cache of key matrices emptied)."""
    for k, v in tables.items():
        KP.PROFILES[k] = v
    KP.KM.clear()


def decision(pcp):
    """The correlation and decision stages under the tables in use: per profile, the 24 correlations (major C..B,
    minor C..B), their mean, and key_parity's decide."""
    rs = {p: KP.corr24(pcp, KP.km(p)) for p in KP.FARALDO}
    mean = sum(rs[p] for p in KP.FARALDO) / len(KP.FARALDO)
    key, margin, agree, sure = KP.decide(pcp)
    return {"r": {p: [float(v) for v in rs[p]] for p in KP.FARALDO}, "mean_r": [float(v) for v in mean],
            "profile_keys": [KP.cam24(int(np.argmax(rs[p]))) for p in KP.FARALDO],
            "key": key, "margin": margin, "agree": int(agree), "sure": bool(sure)}


def analyse(name, n, chords, harm, noise, seed, tables):
    y = synth(SR, n, chords, harm, noise, seed).astype(np.float32)
    F_, M_, E_, X = reference_peaks(y)
    frames = KP.hpcp(F_, M_, E_, n_harm=4, whiten=True, frame_norm=False)   # recommended's own call
    pcp = frames.mean(axis=0)
    T = frames.shape[0]
    picks = sorted({0, T // 2, T - 1})[:SELECTED]
    out = {"name": name, "samples": n, "harmonics": harm, "noise": noise, "seed": seed,
           "chords": [[a, b, notes] for a, b, notes in chords],
           "check": {"sum": float(np.sum(y, dtype=np.float64)), "sum_sq": float(np.sum(y.astype(np.float64) ** 2)),
                     "samples": [[i, f32(y[i])] for i in (0, n // 3, n // 2, n - 1)]},
           "frames": T,
           "selected": [{"frame": t, "X": [f32(v) for v in X[t, :ENVELOPE_BINS]],
                         "F": [f32(v) for v in F_[t]], "M": [f32(v) for v in M_[t]], "E": [f32(v) for v in E_[t]],
                         "hpcp": [float(v) for v in frames[t]]} for t in picks],
           "hpcp_frames": [[float(v) for v in row] for row in frames],
           "hpcp": [float(v) for v in pcp]}
    for label, table in tables.items():
        use_tables(table)
        out[label] = decision(pcp)
        full = KP.recommended(y)
        assert (full[0], full[2], full[3]) == (out[label]["key"], out[label]["agree"], out[label]["sure"]) \
            and full[1] == out[label]["margin"], (name, label, full, out[label])
    return out


def vectors(tables):
    """Made-up HPCP vectors for the correlation and decision stages alone: SplitMix64 draws, some shaped like a key
    profile plus noise, some flat with a little noise (near ties), and a few by hand."""
    cases = [("zeros", [0.0] * 12), ("ones", [1.0] * 12), ("single_a", [0.0] * 9 + [1.0, 0.0, 0.0]),
             ("c_major_triad", [1.0, 0, 0, 0, 1.0, 0, 0, 1.0, 0, 0, 0, 0]),
             ("augmented", [1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0, 0, 0, 0]),
             ("whole_tone", [1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0, 1.0, 0])]
    u = splitmix(4242, 60 * 15)
    profiles = list(tables["key_light"])
    for i in range(60):
        draw = u[i * 15:(i + 1) * 15]
        kind = i % 4
        if kind == 3:   # nearly flat: the decision rests on small differences
            v = [1.0 + 0.02 * (x - 0.5) for x in draw[:12]]
        else:           # a rotated profile, scaled, plus noise: moderate, slight, or more noise than profile
            prof = tables["key_light"][profiles[int(draw[12] * 3)]][int(draw[13] * 2)]
            shift = int(draw[14] * 12)
            scale, noise = [(0.5, 0.2), (1000.0, 0.2), (0.1, 0.6)][kind]
            v = [prof[(c - shift) % 12] * scale + noise * draw[c] for c in range(12)]
        cases.append((f"random_{i}", v))
    out = []
    for name, v in cases:
        row = {"name": name, "hpcp": [float(x) for x in v]}
        for label, table in tables.items():
            use_tables(table)
            row[label] = decision(np.asarray(v, float))
            if label != "key_light":   # per-profile correlations once, to keep the file small
                del row[label]["r"]
        out.append(row)
    return out


def main():
    tables = {"key_light": {k: (list(v[0]), list(v[1])) for k, v in KP.PROFILES.items() if k in KP.FARALDO},
              "literature": literature_tables()}
    win = np.hanning(KP.N44 + 1)[:-1].astype(np.float32)   # the window spectral_peaks builds, for its sum only
    doc = {"versions": {"numpy": np.__version__},
           "constants": {"sample_rate": SR, "frame": KP.N44, "hop": KP.H44, "fmin": KP.FMIN_PK, "fmax": KP.FMAX_PK,
                         "peaks": KP.NPEAKS, "margin_sure": KP.MARGIN_SURE, "profiles": list(KP.FARALDO),
                         "envelope_bins": ENVELOPE_BINS, "window_sum": float(win.sum()),
                         "window": [[i, f32(win[i])] for i in (0, 1, 2, 1000, 2048, 3000, 4095)]},
           "profiles": {label: {k: [v[0], v[1]] for k, v in t.items()} for label, t in tables.items()},
           "signals": [], "vectors": []}
    for name, n, chords, harm, noise, seed in signals():
        s = analyse(name, n, chords, harm, noise, seed, tables)
        doc["signals"].append(s)
        print(f"{name}: {s['frames']} frames, key {s['key_light']['key']} margin {s['key_light']['margin']:.4f} agree "
              f"{s['key_light']['agree']} sure {s['key_light']['sure']}; literature {s['literature']['key']} "
              f"{s['literature']['margin']:.4f}", file=sys.stderr)
    doc["vectors"] = vectors(tables)
    use_tables(tables["key_light"])
    changed = sum(1 for v in doc["vectors"] if v["key_light"]["key"] != v["literature"]["key"])
    path = os.path.join(OUT, "key_parity.json")
    with open(path, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB): {len(doc['signals'])} signals, "
          f"{len(doc['vectors'])} vectors ({changed} decided differently by the literature table)")


if __name__ == "__main__":
    main()
