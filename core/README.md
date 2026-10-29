# core: DeckieCore

Deckie's own ideas, written once in plain Swift with no Apple-only framework, so the Apple apps and the Windows
and Linux crate builder share them. Charter: `docs/architecture/pc-linux-track.md`; running log:
`docs/architecture/pc-linux-status.md`.

- `Sources/DeckieCore`: the beat grid fit (`GridFit.swift`), start and end tempo (`LocalTempo.swift`), the
  Camelot wheel (`Camelot.swift`), tempo relations (`TempoMultipliers.swift`), directed pair scoring
  (`PairScoring.swift`) and the top lists (`Recommendations.swift`). Ported line for line from
  `mixer/analyze.py`, `mixer/local_tempo.py` and `mixer/score.py`;
  `PythonCompat.swift` holds the rounding and modulo details that keep the numbers identical. `Loudness/` is the
  loudness module, `DSP/` and `Key/` the key estimator and the signal processing under it (with the spectral
  features, the resampler, the two-band split and the first and last sound), `Structure/` bars, phrases, sections,
  the fade-out, the mix windows and the novelty, `Beat/` the beat tracker's front end, chunking and peak picking;
  all are described below.
- `Sources/DeckieLab`: reads the lab's `mixer/features/<id>.json` and `mixer/candidates.json` into
  `DeckieCore` types (`FeatureFile+Structure.swift` reads the structure fields on their own), and turns them into
  crate records (`FeatureFile+Crate.swift`).
- `Sources/DeckieCrate`: the crate file, described below; `Sources/crate-from-lab` writes one from the lab's files.
  `Dependencies` there reads `dependencies.json`, the source of the apps' acknowledgements screen;
  `Tools/render_dependencies_table.py` regenerates the table at the top of `DEPENDENCIES.md` from it.
- `Sources/DeckieAudio`: `AudioBuffer`, decoded audio in memory (interleaved Float32 at the file's own rate, one
  or two channels), in a target of its own with no Foundation so the analysers in `DeckieCore` can take audio
  without depending on the decoder.
- `Sources/DeckieDecode`: audio files to float samples for the analysers (`AudioDecoder.decode(url)` gives an
  `AudioBuffer`; DeckieDecode re-exports DeckieAudio, so importing it is enough). It builds the same on Linux,
  Windows and macOS and needs nothing installed. It reads WAV (16-, 24- and 32-bit integer, 32-bit float) in plain
  Swift, MP3 through the vendored dr_mp3 and FLAC through the vendored dr_flac (both below); AAC is recognised and
  throws a "not supported on this platform yet" error until the platform decoders are wired in. Ubuntu's ffmpeg
  libraries were checked and rejected as GPL builds (`DEPENDENCIES.md`). AIFF and AIFF-C are read in plain Swift
  too (`AIFFReader.swift`: big-endian PCM up to 32 bits, AIFF-C "sowt" little-endian as macOS writes it, and "fl32"
  float), with the length and the sample rate taken as libsndfile takes them, so the samples match the lab's.
  Copy-protected MP4s (FairPlay: older iTunes Store purchases and Apple Music downloads; any sample entry carrying a
  "sinf" protection box) are recognised from their box tree (`ProtectedMP4.swift`, which also lists what is not
  detected) and throw a `.protected` error, "protected, cannot be read", which the build summary counts apart from
  `.unsupported`.
- `Sources/CDrMp3`: dr_mp3, a public-domain MP3 decoder in one C header (`include/dr_mp3.h`, copied unmodified
  and pinned by its SHA-256 in `DEPENDENCIES.md`, with its licence quoted), compiled as plain C by `dr_mp3.c`.
  `DeckieDecode/MP3Reader.swift` hands it the file's bytes from memory and gets 32-bit float back, then trims the
  silence MP3 encoding adds the way the lab's decoder (libsndfile through mpg123) does: the encoder delay plus the
  decoder's 529 samples at the start and the padding less 529 at the end, read from the LAME tag in the first
  frame. dr_mp3's own version of that trimming is switched off so the rule stays Deckie's. On the test tones the
  result has the original's exact length and sits at offset 0 from the lab's decode, within 1.3e-6 per sample. To
  update it, see `DEPENDENCIES.md` section 4.
- `Sources/CDrFlac`: dr_flac, the same author's public-domain FLAC decoder in one C header (`include/dr_flac.h`,
  copied unmodified, pinned and quoted in `DEPENDENCIES.md` section 5), compiled as plain C by `dr_flac.c`.
  `DeckieDecode/FLACReader.swift` decodes native FLAC and Ogg-FLAC up to 24 bits from memory, skipping ID3v2 tags
  in front (which dr_flac alone cannot open), and refuses a file that is cut short or has a damaged frame, as the lab
  does, rather than let the audio after the damage come early. On the 16- and 24-bit test tones every sample is the
  lab's, at offset 0.
- `Sources/COnnxRuntime` and `Sources/DeckieInference`: ONNX Runtime from Swift, and the beat tracker and the vocal
  tagger on it (below). `COnnxRuntime` is ONNX Runtime's C API header (vendored unmodified, MIT, pinned in `DEPENDENCIES.md`
  section 6) and a small C file that opens the library at run time; nothing links it.
- `Sources/DeckieEngine`: the Windows and Linux analyser, the lab's pipeline on the pieces above (below).
- `Sources/DeckieBuild` and `Sources/deckie-build`: the crate builder and its yardstick bench, as a library (so the
  tests can drive it) and a command line; see "Building a crate" below.
- `Sources/deckie-memprobe`: measures the analyser's peak memory under chosen ONNX Runtime settings; see "Measuring
  memory" below.
- `Tests/DeckieCoreTests`: parity tests against the lab. `Fixtures/` holds the reference numbers, written by
  `Tools/make_fixtures.py` with the lab's own Python (needs numpy; run from the repository root). The tests also
  read `mixer/features/`, `mixer/candidates.json` and `mixer/recs.json` straight from the repository.
  `LoudnessTests.swift` uses synthesised signals only: the published BS.1770 coefficients, the EBU Tech 3341 and
  3342 test cases, true peak between samples, and a speed check.
  `DSPTests.swift` and `KeyTests.swift` compare against `Fixtures/dsp.json` (numpy's FFT, librosa's chroma and soxr,
  written by `Tools/make_dsp_fixtures.py`; needs numpy and librosa) and `Fixtures/key.json` (the lab's key decisions,
  written by `Tools/make_key_fixtures.py`; needs numpy only); every test signal is synthesised, in Python and again in
  Swift, to the same bits. `SpectralTests.swift` compares against `Fixtures/spectral.json` (librosa's mel, MFCC, RMS
  and onset features, scipy's find_peaks and the lab's own structure code, written by
  `Tools/make_spectral_fixtures.py`; needs numpy, scipy and librosa): the matrices are too big to store whole, so it
  keeps a few frames in full plus every frame's and every band's sum, and the curves whole (427 KB).
  `ResampleTests.swift` and `BandTests.swift` do the same with `Fixtures/resample.json` (113 KB: soxr's output, tone
  levels and response) and `Fixtures/bands.json` (38 KB: scipy's band split and the lab's per-bar levels and first
  and last sound), both written by `Tools/make_resample_fixtures.py` (needs numpy, scipy and soxr).
- `Tests/DeckieInferenceTests`: the ONNX Runtime wrapper's tests on a 192-byte model (`Fixtures/affine.onnx`,
  written by `Tools/make_onnx_fixture.py`), the beat tracker end to end against the Beat This! package, and YAMNet
  and the vocal tagger against Python's ONNX Runtime and on the vocal test track. They need ONNX Runtime, and the
  beat tracker and the vocal tagger their models; without them they are skipped, with the reason printed. YAMNet's
  reference numbers are `DeckieCoreTests/Fixtures/yamnet.json` (285 KB, written by `Tools/make_yamnet_fixtures.py`
  with TensorFlow), which the front end's tests read too.
  `Tests/DeckieTestSupport` is a small library shared by the test targets: the synthesised drum patterns and chords
  (`ChordSynth`), a sung-like line and the vocal test tracks (`VoiceSynth`, `VocalTrack`, `VocalStructureTrack`), the
  engine's test track (`TestTrack`, shared with the builder's tests), the beat fixture's reader, and `CPUTurns`, which
  makes the model runs take turns.
- `Tests/DeckieEngineTests`: the engine end to end on a synthesised track, and its pieces (below).
- `Tests/DeckieBuildTests`: the crate builder and the bench (below). `Fixtures/bench_parity.json` holds what
  `mixer/bench_mu.py`'s own functions give on pairs of series from every committed feature file, written by
  `Tools/make_bench_fixtures.py` (Python's standard library only).
- `Tests/DeckieDecodeTests`: the decoder's tests. `Fixtures/` holds a generated test tone (two sines and a click)
  as WAV at 44.1 and 48 kHz, MP3 at 44.1 and 48 kHz and in mono, AAC, AIFF and AIFF-C ("sowt"), FLAC at 16 and 24
  bits and as Ogg-FLAC, plus a 648-byte stand-in for a FairPlay-protected file with no audio in it
  (`protected.m4p`), written by `Tools/make_audio_fixtures.py` (needs numpy, and the ffmpeg program for the MP3,
  AAC, AIFF and FLAC files only; the same ffmpeg gives the same bytes on every run). The MP3 tests also edit those
  bytes in memory: ID3 tags in front, edited LAME tags, damaged files; the AIFF, FLAC and protected-file tests build
  their variants the same way.

**Loudness** (`Sources/DeckieCore/Loudness/`) measures what the lab measures, for any sample rate, on every platform,
with no dependency. `KWeighted(buffer)` filters each channel with the K-weighting of ITU-R BS.1770 (two biquads, in
double precision) and keeps a running sum of the channel-summed K-weighted square, so the loudness of any span,
such as one bar (`loudness(from:to:)`, the lab's per-bar `lufs_st`), is one subtraction. `Loudness.integrated` and
`Loudness.range` give integrated loudness (LUFS) and loudness range (LU) gated exactly as pyloudnorm 0.2.0 does it,
`Loudness.shortTerm` the lab's 3 s `st_lufs`, and `TruePeak.decibels` the lab's true peak (4x oversampling with
`scipy.signal.resample_poly`'s default filter, in 10 s blocks). The default filter design is pyloudnorm's, which
the lab uses; it reads about 0.04 LU below the coefficients BS.1770 publishes, which `design: .bs1770` gives
instead (as libebur128 does). The algorithms follow pyloudnorm (MIT) and scipy by description; no code is
copied. Four minutes of stereo take about a second in a debug build.

**Local tempo** (`Sources/DeckieCore/LocalTempo.swift`) is the lab's start and end tempo, `mixer/local_tempo.py`,
for tracks that do not keep one tempo (tempo-change edits, slow intros, rideouts, live drummers).
`LocalTempo.compute(input)` fits the raw detected beats of the first and last 30 s of sound, of both mix windows and
of every 15 s segment with the grid fit's window regression; each window then takes the global tempo when its beats
already sit on the grid, its own tempo when it has a steady beat (residual within 15 ms over at least 16 beats) that
differs by more than 1.5 percent, and otherwise the global tempo, untrusted. The result is the lab's whole
`local_tempo` block, rounded as the lab rounds it: start and end tempo with their trust and rule, drift, the 15 s
profile and its range, the steady span in seconds and bars, the first downbeat at each end, and the six flags.
`FeatureFile.localTempoInput` (DeckieLab) reads the input from a feature file. Run on the committed feature files it
gives back all 373 committed blocks, every field identical on 372; on the last, one mix-in residual is a rounding tie
(5.25 ms) that numpy's least squares rounds up and the port's rounds down (`LocalTempoTests.swift` says why that is
accepted and nothing else is). The lab's current script reproduces every committed block from the committed data,
so the feature files are the reference and there is no fixture.

**Key estimator** (`Sources/DeckieCore/Key/`, on `Sources/DeckieCore/DSP/`) is the lab's lightweight estimator,
`mixer/key_light.py`, in the variant the charter names: chroma from a plain FFT, the edma profile, Pearson
correlation against the 24 keys (75 percent exact against the lab's confident keys; Apple's framework gets 83).
`KeyEstimator.estimate(buffer, mixIn:, mixOut:, songKey:)` gives what the lab records for a track: the whole-track
key with its correlation and margin, the key of each mix window judged against the song key (Apple's, or else the
whole-track estimate; a window is flagged only when it is far from the song key and fits better by 0.08, as the lab's
`--ends` mode does), and the key segments (20 s windows every 5 s with the tonal-area hysteresis). The pieces under
it: `FFT` and `RealFFT` (radix-2, double precision, within 4e-16 of numpy.fft), `STFT` and `Window.hann` (librosa's
centred, zero-padded frames and scipy's window, to the bit), `ChromaFilterBank` (librosa's chroma filters, every
sampled float32 weight identical) and `Chroma.stft` (librosa's `chroma_stft` as the lab calls it: within 8.4e-7 of
librosa 1.0.0 fed float32 audio as the lab feeds it, within 1e-14 fed doubles). The decisions (`bestKey`,
`segments`, `windowKey`, `Camelot.relation`, `Camelot.wheelCost`) reproduce the lab's functions to the last bit on
68 test matrices, using numpy's own summation order and dot product (`Py.pairwiseSum`, `Py.dot`). It reads mono
audio at 22,050 Hz; 44.1 kHz goes through `Decimator.halve`, now the resampler below with soxr's own filter (on a
synthesised signal its chroma is within 1.1e-6 of the chroma of soxr's output; the 65-tap stopgap it replaces gave
4e-4), and other rates still throw "resample first" (`Resampler` can feed them). Four minutes take under a second in
a debug build. Still needed from the Mac: parity on real music. `mixer/key_light_stft.tsv` (whole-track keys, all
six profiles) and `mixer/key_ends_stft.tsv` (mix windows) hold the lab's per-track results for the 373 tracks, but
the audio stays on the Mac; there the port runs over `mixer/candidates.json` and its keys, correlations and flags are
compared row by row, which also measures the decimator against soxr on real tracks. Expect rare differences where
the lab's margin is tiny: the lab's chroma and its window means are float32, the port's are double precision.

**Structure** (`Sources/DeckieCore/Structure/`) is the part of `mixer/analyze.py` after the grid choice that lays out
bars and phrases and places the mix windows, as pure functions of what the audio analysers measure. `BarGrid` puts bar
1 at the first grid downbeat at or after the first sound (less a quarter beat) and gives the bar count, the bar lines
and the grid beats; `Phrase` sums the novelty peaks by position within 8 bars and gives the lattice phase, its
confidence, the phase used for snapping and the section boundaries; `Section.sections` labels the stretches between
boundaries intro, main, break or outro by loudness; `FadeOut` decides the fade from the end loudness
(`Loudness.shortTerm` measures it) and the per-bar loudness; `MixWindows` places `mix_in` and `mix_out` (`pickLen`,
the lattice snapping, the fade cut-off, the vocal-free counts); `TrackFlags.flags` gives the flag list. Bar numbers in
and out are 1-based, as the feature files write them; values are kept unrounded. The per-bar loudness is
`KWeighted.loudness` over each bar; the novelty peaks come from `FooteNovelty` (below); the per-bar vocal probability
needs an analyser not ported yet.
`StructureTests.swift` runs each port on the inputs a committed feature file holds and compares the result with the
outputs it holds, for all 373 tracks, with tolerances worked out from the files' rounding. Everything matches except
on four tracks where a written input sits on a threshold (three with a bar's vocal probability written as 0.5, one
with a tempo written as 100.000 BPM); given that input just inside its rounding, the port gives the lab's result there
too.

**Spectral features and novelty** (`Sources/DeckieCore/DSP/`, `Structure/Novelty.swift`, `Structure/OnsetPattern.swift`)
are the lab's spectral block and what `mixer/analyze.py` computes from it. `SpectralFeatures(y)` takes mono audio at
22,050 Hz and gives, on the same frames (2048 samples centred every 512) and in double precision, librosa's mel
spectrogram (`LibrosaMelFilterBank`, 64 Slaney bands, and `LibrosaMel.spectrogram`; named after librosa so they are not
mistaken for a model's own mel front end), the log-mel (`LibrosaMel.powerToDb`, floored 80 dB below the loudest value),
13 MFCCs (`MFCC`, the orthonormal DCT-II), the RMS (`RMS`) and the onset strength (`OnsetStrength`, the mean rise of the
log-mel, three frames late as librosa centres it). `FooteNovelty(mfcc:rms:grid:)` averages MFCC and RMS over half-beat
frames from bar 1, builds the cosine and loudness self-similarity matrices, runs the lab's `foote_novelty` line for line
(64-frame Gaussian checkerboard, edge padding, numpy's pairwise sums), takes the geometric mean, picks peaks with
scipy's `find_peaks(distance=8)` (`FindPeaks`: plateaus and the distance rule as scipy has them), keeps the 20 strongest
and snaps them to bar lines within 0.4 bar; its `peaks` go to `Phrase(peaks:)`. `OnsetDensity` counts librosa's onsets
(`OnsetDetect`, onset_detect's greedy peak picker) per bar, per beat; `OnsetPattern` is `onset_pattern_16`. Parity, on
signals synthesised in Python and in Swift to the same bits (`SpectralTests.swift`): librosa's 1990 non-zero float32 mel
weights are reproduced exactly; against the lab's float32 path the mel spectrogram is within 3.9e-7 relative, the
log-mel 2.0e-7 (8.6e-6 dB), the MFCCs 1.6e-7, the RMS 1.2e-7 and the onset strength 2.1e-7, and librosa given float64
audio agrees to 2.3e-13 or better, so single precision is the whole difference. `FindPeaks` matches scipy on every curve
without two peaks of exactly equal height (scipy orders those with numpy's unstable sort, which depends on the machine;
here the later peak wins; a novelty curve does not have such ties). On a synthesised 48-bar track the whole chain from
audio gives the lab's own code's peak frames, bars and lattice phase on both paths (novelty within 3.8e-7 of the float32
path, 6.1e-16 of the float64), the same onsets in every bar, and the onset pattern within 1.3e-7. The float32 rounding
could only change a result where two candidate peaks are that close in height. Four minutes take about 1.5 s in a debug
build. The lab resamples to 22,050 Hz with soxr first; `Resampler` (below) does that with soxr's own filter. Still
needed: parity on real music needs the audio on the Mac (the feature files hold `novelty_peaks`, `onset_density` and
`onset_pattern_16`, rounded, for the 373 tracks).

**Resampling, bands and first sound** (`Sources/DeckieCore/DSP/Resampler.swift`, `BandSplit.swift`,
`SoundBounds.swift`) are three audio-side pieces of `mixer/analyze.py` that the structure module takes as inputs.
`Resampler(from:to:)` converts between any two whole-number rates with a polyphase windowed-sinc filter of soxr's
"HQ" design, the lab's resampler, measured from soxr's impulse response (a Kaiser window with beta 13.04, cutoff
0.956872 of the lower Nyquist frequency, 97.25 periods of the lower rate either side): flat within 1e-5 dB to 0.9 of
the lower Nyquist frequency, at least 126 dB down from it on, no delay, soxr's output length. Between 44.1 and
22.05 kHz, both ways, it is soxr's own filter and the outputs agree to -103 to -137 dB of the signal (soxr's
single-precision noise); from 48 to 44.1 kHz and 44.1 to 16 kHz, and back, soxr adds an interpolating stage
(0.007 dB of passband droop, a slightly different transition band, a different start in its first few output
samples), so there the two agree to about -60 dB on noise. Four minutes of stereo take 0.5 to 0.8 s in a release
build and 6 to 8 s in a debug build (a plain-Float loop there, the same arithmetic as the release build's SIMD loop,
to the bit); `Decimator.halve` is now a call into it. `BandSplit` is the lab's `lr4`: scipy's second-order Butterworth
(`butter(2, fc, btype, fs, output="sos")`, computed the way scipy computes it, to the last bit) run twice the way
`sosfilt` runs it, low-pass at 150 Hz and high-pass at 4 kHz; `levels(mono, barTimes:)` gives the lab's per-bar
`low_db` and `high_db` in one pass (four minutes in 0.2 s in a debug build). Against scipy the filtered samples are
identical and the per-bar values within 1e-13 dB, at 44.1 and 48 kHz. `SoundBounds(buffer)` is the lab's first and
last sound (10 ms frames, the peak over channels above -60 dBFS compared in float32 as numpy compares it, a partial
last frame dropped; at other rates frames of rate / 100 samples), identical to the lab's rule on 14 cases.

**Inference and beat tracking** (`Sources/DeckieInference/`, on `Sources/DeckieCore/Beat/`). `OnnxRuntime.load()`
opens ONNX Runtime 1.31.1 (Microsoft's engine for trained models, MIT) at run time from the path in
`DECKIE_ONNXRUNTIME_LIB`, or from `core/.deps/onnxruntime/lib/` where `Tools/fetch-onnxruntime.sh` puts the release
after checking its SHA-256; `makeSession(modelPath:options:)` loads a model with a chosen thread count and graph
optimisation level, and `run` takes float32 tensors by name and returns float32 tensors with their shapes. ONNX
Runtime's own errors come back as `OnnxRuntimeError.runtime` with its code and message. `BeatTracker` runs Beat
This! (JKU Linz, ISMIR 2024, MIT code and weights; `DEPENDENCIES.md` section 7): `track(buffer)` averages the
channels, takes 22,050 Hz as it is, halves 44,100 Hz with `Decimator.halve` and brings any other rate to 22,050 Hz
with `Resampler` (soxr's "HQ" filter, as the package's `soxr.resample`), computes the package's log-mel spectrogram
(`BeatThisFrontEnd`: reflect-padded STFT, torchaudio's Slaney mel filters rebuilt in float32 by
`TorchaudioMelFilterBank`, log(1 + 1000 x)), runs the network over 30 s chunks as the package does
(`BeatThisChunking`) and picks peaks with the package's minimal postprocessor (`BeatThisPostProcessor`), giving beat
and downbeat times. The
model is `final0` exported to `core/.models/beat_this_final0.onnx` by `Tools/export_beat_this.py` (a development
tool: PyTorch and the package, pinned in `Tools/export-requirements.txt`, checked against PyTorch to 1.1e-5 in a
logit); `DECKIE_BEAT_THIS_MODEL` names another file. Measured against the package on synthesised drums
(`Fixtures/beat_this.json`, written by `Tools/make_beat_fixtures.py`): the spectrogram within 2.6e-5 relative, the
chunking and the postprocessor identical, and every beat and downbeat identical, end to end, on a 30 s pattern at
120 BPM (at 22.05, 44.1 and 48 kHz) and a 90 s one turning from 128 to 100 BPM (at 22.05 and 44.1 kHz), with the
logits within 8.2e-5 of the package's at 22.05 kHz, 3.7e-4 at 44.1 kHz and 5.4e-3 at 48 kHz (where soxr adds an
interpolating stage). On the 120 BPM pattern every click gets a beat at 0 ms and the downbeats fall on the accents.
Four minutes at 44.1 kHz take about 6.3 s in a release build on a four-core 2.1 GHz Xeon, 0.4 s of it resampling
and the spectrogram and the rest the network (about 9.7 s in a debug build). On a fresh machine:

```
bash core/Tools/fetch-onnxruntime.sh                   # ONNX Runtime 1.31.1 into core/.deps (11 MB, hash-checked)
bash core/Tools/fetch-models.sh                        # both models into core/.models (97 MB, hash-checked)
```

`fetch-models.sh` takes the pinned exports from this repository's release `models-1` (`DEPENDENCIES.md` sections 7
and 8) and keeps a file only if its SHA-256 is the one pinned in its export script; `--beat-this` or `--yamnet` takes
one, `--check` only reports. A model it cannot fetch it exports instead, unless `--no-export`; for Beat This! that
needs the export tools, kept out of the system Python:

```
python3 -m venv /tmp/bt
/tmp/bt/bin/python -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.15.0+cpu torchaudio==2.11.1+cpu
/tmp/bt/bin/python -m pip install -r core/Tools/export-requirements.txt
bash core/Tools/fetch-models.sh --beat-this --python /tmp/bt/bin/python   # exports it if the release lacks it
```

**The crate file** (`Sources/DeckieCrate`; the format, with what the documents fix and what is proposed, is
`docs/architecture/crate-format.md`) is the one file Deckie writes, never audio: a package folder `<name>.deckiecrate`
holding `manifest.json`, `crate.json` (one record per track: grid and tempo segments, key with its votes, phrase,
sections, mix windows, ends, loudness, vocal, onset pattern, flags, plus track L's engine record, `fidelity`, a
`source` and confidence per block and `features_present`), float16 sidecars for the per-bar series and the style
vector, and a `signatures` block that stays empty here, as signatures are made on an Apple device. A shipped engine's
record id is the first 16 hexadecimal characters of the SHA-256 hash of the file's bytes, whose whole hash is kept in
`file.sha256` (`CrateIDs`, on SHA-256 written in Swift); the lab's records keep the lab's ids. `CrateWriter`
checks a crate and writes it canonically (keys sorted, each number with its field's fixed decimals, nulls written), so
the same crate always gives the same bytes; `CrateReader` checks the version, the required fields,
`features_present`, every bar number and each sidecar's length against `n_bars`, and names the file, the field path
and the track of every problem. `FeatureFile.crateTrack` (DeckieLab) makes a record from any committed feature file:
all 373 convert, read back equal and write the same bytes again (`swift run crate-from-lab --out all.deckiecrate`
writes them, 1.5 MB, about 4 KB a track). The lab's EffNet embedding is left out (non-commercial, and the port plan
keeps it out of every crate). `core/fixtures/example.deckiecrate` (20 KB, five varied tracks, rebuilt by
`Tools/make_crate_fixture.sh`) is the example for the Apple side; a test checks it byte for byte against the converter.

**The engine** (`Sources/DeckieEngine`) is the Windows and Linux analyser, the charter's `DeckieEngineOSS` (its crate
family is `deckie`). `Analyser().analyse(url:options:)` runs `mixer/analyze.py`'s `analyse()` in the lab's order on the
pieces above: the SHA-256 of the file's bytes for its id (`CrateIDs`), decoding to 44.1 kHz and mono, the first and last
sound, Beat This!'s beats and the grid fit, the lab's octave alignment to a tag tempo when one is given (`OctaveAlign`),
the bars, the spectral features, the novelty and phrase lattice, the per-bar loudness, bands and onsets, integrated
loudness, loudness range and true peak, the onset pattern, the sections, the fade-out, the mix windows, the key of the
whole track and of both mix windows, local tempo and the flags, timing each stage as the lab's `timing_s` does. The
`Analysis` it returns writes the lab's feature JSON (`labJSON()`: the lab's keys in its order, rounded as the lab rounds
them, 1-based bars, what the engine cannot produce null or left out the way the lab does, listed on the function, and
a `deckie` block of the engine's own) and the crate record (`crateTrack(options:)`). Three departures from the lab:
Beat This! is the only grid source, as the madmom fallback is non-commercial (`madmom_ran` is false, and
`deckie.madmom_would_run` marks the tracks where the lab would have run it); the key confidence comes from the one
estimator's margin over the runner-up key in place of three detectors agreeing (`KeyConfidence`: 0.65, 0.45 or 0.3, with
the figures behind the steps; a proposal to confirm on the Mac); and the vocal probability comes from YAMNet, not the
lab's non-commercial EffNet (below), and `embedding_effnet` is never written. Without the YAMNet model the engine runs
on without a vocal tagger: the record has no `vocal` block or `per_bar.vocal_prob`, the mix windows count every bar
as vocal-free, and the flag `vocal_unknown` asks for them to be placed again when a tagger has run. The tests
(`Tests/DeckieEngineTests`) synthesise 63 s of drums at 124 BPM with A minor chords, a quiet 8-bar intro and an 8-bar
fade (just over a minute, as the lab counts a fade only after a minute of sound), and check the tempo, bar 1, the bar
count, the key, the first and last sound, the fade, the mix windows, the loudness and every per-bar series' length; the
JSON against a committed lab file's keys and through `FeatureFile`; the crate record through the writer and reader; and
the same bars and tempo from an MP3 of the track (made with the ffmpeg program when it is installed; skipped otherwise,
as everything here is without ONNX Runtime and the model). The lab's own `local_tempo.compute` and `fit_grid`, run on
the engine's JSON for that track, give back the engine's values exactly, and Python's json module reads the file and
writes it again byte for byte. A minute of audio takes about 5 s in a debug build, half of it the network.

**The vocal tagger** (`DeckieVocalTagger` in `Sources/DeckieInference`, on `YAMNetFrontEnd` and `PatchBars` in
`Sources/DeckieCore/Vocal`) gives the engine its per-bar vocal probability in the lab's shape. It runs Google's YAMNet
audio tagger (Apache 2.0, trained by Google on AudioSet, 3.7 million weights; `DEPENDENCIES.md` section 8), which
scores 521 kinds of sound for each 0.96 s patch, a patch every 0.48 s: the mono mix is resampled to 16 kHz
(`Resampler`), cut into YAMNet's log-mel patches by a Swift rewrite of its feature code, and run through the network
on ONNX Runtime. A patch's vocal score is the largest of YAMNet's scores for singing, choir, yodelling, chant, mantra,
child singing, synthetic singing, rapping, humming, vocal music and a cappella (speech is left out and recorded beside
it, as are singing, rapping, choir and music on their own, under `deckie.vocal`, since rap over rap is the worst clash
in a mix, research Q); the patches are averaged into bars exactly as the lab
averages its EffNet patches (the patches centred in a bar, else the value at the bar's middle), and the mean of the
patches' 1,024-value embeddings, scaled to length 1, is the track's style vector (the crate's `style` block). The scores
are not calibrated: the lab's thresholds (0.5 a vocal bar, 0.75 a vocal-heavy track) were tuned on EffNet, and track
J's listening test on the Mac sets YAMNet's. The model is not committed: `Tools/fetch-models.sh` fetches the pinned
export into `.models/yamnet.onnx` from the repository's release `models-1`, checked by its SHA-256, and only when it
cannot does it run `Tools/fetch-vocal-models.sh`, which fetches the weights by pinned URL and SHA-256 and exports the
network with TensorFlow's tools (`Tools/export_yamnet.py`, development-only, in a Python environment of their own).
`Analyser()` loads the model when it is there (`DECKIE_YAMNET_MODEL` names another place) and says what is missing
when it is not. A second model can be
added beside it as a second opinion through `VocalPatchModel` (PANNs' MobileNetV2 is the candidate, should the Mac's
yardstick find YAMNet alone reads badly). Measured: the front end within 1.8e-4 of YAMNet's own feature code, the
network identical to Python's ONNX Runtime on the same patches, and on a synthesised track alternating 8-bar stretches
of drums and chords with and without a sung-like line, 0.029 on the sung bars against 0.0001 on the others (YAMNet
hears the synthetic voice only faintly; real singing scores far higher); drums alone score 1e-5. Four minutes of
stereo take 0.6 s in a release build (resampling 0.28 s, front end 0.10 s, network 0.20 s) and 4.6 s in a debug build.

**The vocal structure and the hook candidates** (`VocalStructure` and `Hooks` in `Sources/DeckieCore/Structure`) are
research Q's per-track vocal fields (`docs/research/q-vocal-uses.md`, items A1 to A6 and B7): with a tagger, the
engine reads YAMNet's patch-by-patch scores (0.48 s apart, finer than a bar) against the grid for the sung spans in bars
and beats, the first sung beat and whether it is a pickup, the last, the free intro and outro and what they hold, the
8-bar free gaps on the lattice, a stand-in for an exposed vocal from `low_db` and the onset density, and each span's
ends against the lattice; and proposes up to three hooks from repetition (the novelty's MFCC, bar against bar),
loudness and vocal density. Every rule is relative to the track and a first cut for the Mac's listening test to tune;
its parameters and threshold are written beside the result. The lab JSON carries both under `deckie`, the crate as the
proposed `vocal_structure` and `hooks` blocks (`docs/architecture/crate-format.md`). On a 40-bar synthesised track
sung from a pickup before bar 9 to bar 16 and over bars 25 to 32 the engine finds the pickup, the last sung beat, 7 and
8 free bars and the gaps exactly, and every span end within two beats.

What the Mac yardstick will compare (charter step 6): the engine run over the 373 tracks of `mixer/candidates.json`,
each record beside the lab's `mixer/features/<id>.json` for the same track, read with the lab's own tools. Beats and
downbeats (F-measure at 70 ms, `detected_beats_s` and `detected_downbeats_s` against the lab's), tempo within 2 percent,
bar 1 and the bar count, the key exact or a neighbour against the lab's confident keys and how often each step of the
proposed key confidence is right, integrated loudness, loudness range and true peak, the per-bar loudness and bands,
first and last sound, the fade decision, sections and mix windows, and the stage times. Grids are expected to differ
where the lab ran madmom, and mix windows where the lab's vocal probabilities moved them; the comparison reads those
apart. `deckie-build bench` (below) runs it and computes the stage 1 numbers.

```
cd core
swift build
swift test
```

## Building a crate: `deckie-build`

```
deckie-build <folder> --out <name>.deckiecrate [--rekordbox export.xml] [--jobs N] [--bpm-tags] [--name N] [--fresh]
```

It finds every audio file below the folder by its extension (mp3, flac, wav, aif, aiff, aifc, m4a, mp4, aac, wma,
ogg, opus and the protected m4p; hidden files and folders, crate packages and work folders are skipped), analyses each
with the engine, several at a time, and writes the crate with `CrateWriter`. While it runs it prints a line per file:
the count, the time since the start, an estimate of the time left and the file's own analysis time, or why it could
not be analysed. At the end it prints a summary: files seen, analysed, taken from the work folder, and the files with
no record, counted by reason and extension.

- **Jobs.** `--jobs N` files at once; the default is the processor count, or fewer when memory is short, as one
  analysis of a four-minute track peaks at about 1.1 GB (0.2 GB of it the models, shared; each further job adds
  about 1 GB, almost all the beat model's working memory for one 30-second chunk), so each job is given 1 GB and
  2 GB are left for the rest (`defaultJobs`; `deckie-memprobe` below measures it). The jobs share one analyser: its ONNX Runtime session may be run from several threads at once,
  and each run gets the processor count over the jobs in threads of its own.
- **Resumable.** A work folder beside the crate, `<name>.deckiebuild`, keeps every finished file as it finishes:
  `records/<id>.json` (the engine's record, by the file's SHA-256 id, written whole or not at all) and `files.jsonl`
  (one line per finished file: its path below the folder, size, modification time, the engine, the tag tempo, the
  record's id or why it failed). A second run takes a file as it is when its size and modification time are the same
  (no reading at all); otherwise it hashes the file and takes the record of those bytes if there is one (a file that
  was moved, renamed or only touched), and analyses only what is left. An interrupted run (Ctrl-C) loses only the files
  that were being analysed, one per job. A record is reused only if it came from the same engine version with the same
  tag tempo; the version (0.2.0) goes up whenever the record gains or changes fields, so a work folder made by 0.1.0 is
  analysed again. `--fresh` empties the work folder first; deleting it is always safe.
- **Nothing left out silently** (decision P18). Every file that cannot be analysed is counted by reason and extension
  in the summary and listed in the manifest's `import_log` with its path below the folder and the reason in words:
  `unsupported` (a format this platform cannot decode: AAC, M4A and WMA on Linux, Ogg, Opus), `protected` (FairPlay),
  `damaged`, `decode_error` (could not be read), `analysis_error` (no beat grid, too few bars, the model failed) and
  `duplicate` (the same bytes as another file, which has the record). Failures are remembered in the work folder too,
  except a file that could not be read, which is tried again. The log's `built_by` is the building device's model
  label, the same as each record's `analysis.device`, never the machine's own name.
- **An existing crate** at `--out` keeps its id, name, creation date and devices, and its records' signatures are
  carried over; something at `--out` that is not a crate is never overwritten.
- **rekordbox** (`--rekordbox export.xml`, rekordbox's File, Export Collection in xml format): each file is matched to
  its collection entry by its location (the same path; else the entry whose path ends with the file's path below the
  folder, for an export made on another machine; else the one entry with the same name and size). The DJ's
  `AverageBpm` is the tag tempo the octave alignment follows (as the lab follows its folders' tags); `Name`, `Artist`
  and `Mix` give `ident.title`, `artist` and `version` (source `rekordbox-xml`); the DJ's `Tonality` (classic, Camelot or
  Open Key notation) becomes the vote `rekordbox-xml` in `key.votes`; the grid markers (`TEMPO`), cue points and loops
  (`POSITION_MARK`) and playlist membership go into the record's `imported.rekordbox` block as `grid_markers`, `cues`,
  `loops` and `playlists`, with `imported_at` and rekordbox's own `track_id`, `bpm` and `tonality`; `imported`, the
  DJ's own data keyed by where it came from, is null for a file the export does not hold (accepted Oct 29:
  `docs/architecture/crate-format.md`, "Additions with the crate builder"). The reader is written here (`XMLScanner`,
  `RekordboxCollection`) from the format pyrekordbox documents, so no XML library is needed at run time.
- **File tags.** A file's own title and artist (ID3v2 2.2 to 2.4 at the front of the file or in a WAV or AIFF chunk,
  or a FLAC Vorbis comment) name the track when rekordbox does not (source `tag`; else the file name, `filename`).
  `--bpm-tags` also takes the file's tempo tag (TBPM, or BPM in a Vorbis comment) as the tag tempo where rekordbox gives
  none. The tag tempo used is a fact about the file, recorded in `file.tag_bpm`; its source is not kept, as rekordbox's
  tempo is taken whenever there is one, so the tag is rekordbox's exactly when it equals `imported.rekordbox.bpm`.

Speed, release build on this machine (a shared four-core 2.1 GHz Xeon, Linux), four-minute 44.1 kHz stereo files,
WAV and 320 kbps MP3: one at a time, 8.3 s a file when nothing else ran (6.3 s of it the beat model; the stages
after it take under 2 s), and 8 to 21 s while another session shared the machine; four at a time, 49 to 73 s for
eight files, so 6 to 9 s a file of wall-clock time (each file 20 to 40 s on its own). The tests' build of two
one-minute files takes about 10 s in a debug build.

## Measuring memory: `deckie-memprobe`

```
deckie-memprobe synth <out.wav> [--seconds 240] [--bpm 124] [--seed 1]
deckie-memprobe <file>... [--jobs N] [--repeat R] [--arena on|off] [--pattern on|off] [--shrink on|off]
                [--threads T] [--model-runs M] [--no-vocal] [--records DIR] [--logits]
```

It runs the analyser on the files as `deckie-build` does (one analyser shared by the jobs) while a thread samples the
resident memory, and prints the memory with the models loaded, the kernel's high-water mark of the analyses (VmHWM on
Linux, reset once the models are in; `ru_maxrss` on macOS) and, with one job, each stage's seconds and sampled peak.
`--records` writes each record without its timings, so two builds or two settings can be compared with `cmp`;
`--logits` prints a hash of every bit of the beat model's raw outputs. `synth` writes a four-minute stereo test track.
The switches are `OnnxRuntime.SessionOptions`': ONNX Runtime's memory arena, its memory pattern, shrinking the arena
after a run, and a cap on runs of a model at once; `--beat-shrink every|ends` picks when the beat model shrinks it
(`BeatTracker.ArenaShrinking`: after every chunk, or after a track's first and last chunk, the default).

Measured on Linux (release build, shared four-core machine, the synthesised four-minute track, both models), with the
records and the logits identical under every setting and every thread count:

| Setting | One job, peak | Four jobs, peak | Four jobs, wall time for 8 files |
|---|---|---|---|
| ONNX Runtime's defaults (before) | 1.9 GB | 5.6 GB | 62 s |
| Arena shrunk after every run | 1.1 GB | 3.8 GB | 57 s |
| Shrunk, and two beat-model runs at a time | | 2.6 GB | 81 s |
| Shrunk, and one beat-model run at a time | | 1.7 GB | 105 s |

The peak is in the beat-model stage every time: a run over one 30-second chunk holds about 0.7 GB of intermediate
values. The first run of a chunk leaves the arena in pieces that cannot hold the one planned block the later runs
ask for (ONNX Runtime's memory pattern), so without shrinking the arena holds both, about 1.4 GB, for the life of the
session. Shrinking after every chunk costs one job about 20 percent in time in `deckie-build` (each chunk faults its
0.7 GB in again); shrinking after a track's first and last chunk, the default, keeps the 1.1 GB peak at the old speed:

| deckie-build, four four-minute files, `--fresh` | Peak | Seconds per file |
|---|---|---|
| One job, before (ONNX Runtime's defaults) | 1.94 GB | 8.3 to 9.8 |
| One job, shrunk after the first and last chunk | 1.09 GB | 8.6 to 9.1 |
| Four jobs, before | 5.5 to 5.6 GB | |
| Four jobs, shrunk after the first and last chunk | 4.4 to 4.5 GB | |

(One and four jobs before and after were run alternately on the same busy machine; the crates' records are
byte-identical but for the times.) Turning the arena off instead peaks higher (1.3 GB for one job); the arena with the
memory pattern off peaks at 1.26 GB and keeps 1 GB after the analysis. The models take 0.2 GB once loaded; the decoded
audio and its copies about 0.2 GB a job.

## The yardstick bench: `deckie-build bench`

```
deckie-build bench <folder> --features mixer/features --candidates mixer/candidates.json [--music-root path]
             [--out bench.json] [--records dir] [--jobs N] [--ids id,id,...] [--fresh]
```

For every row of `candidates.json` whose audio is under the folder (the row's `path` less the lab's music root, which
defaults to the folder all the rows' paths share: `/Users/christophershannon/personal/90s2000 playlist`), it analyses
the file with the row's tag tempo, as the lab did, and compares the engine's record with the lab's
`mixer/features/<id>.json`, by the measures of stage 1 (`docs/architecture/stage1-results.md`, 1a), ported from
`mixer/bench_mu.py` and checked against its own functions on all 373 committed files (`BenchParityTests`):

- beat and downbeat F-measure at 70 ms, both the engine's detected beats against the lab's detected beats and its grid
  beats against the lab's grid beats, plus the best octave of the detected pair; shares below 0.8;
- tempo within 2 percent after octave normalisation, within 2 percent as stage 1 counted it, and an octave apart;
- key exact, neighbour (the relative key or one step round the wheel) or other, over all tracks and over the lab's
  confident keys (confidence 0.65 or more, 311 tracks);
- integrated loudness and true peak, engine minus lab; section boundary recall and precision within one bar (the
  lab's inner boundaries against the engine's); per-bar vocal correlation when both sides have it (the engine's bar
  under the middle of each lab bar), marked absent otherwise (the engine runs its vocal tagger only when the YAMNet
  model is installed); bar 1 offset in milliseconds and whether the bar counts match; seconds per track;
  and the grid measures split by where the lab's grid came from (Beat This! or madmom).

Each per track, then medians and means, then the pass marks: the charter's (at least Apple's framework on beats and
loudness, from `mixer/mu_bench.tsv`: beat F medians 0.987 detected and 0.997 grid, downbeat 0.968 and 1.000, shares
below 0.8 of 7.8, 14.5, 18.5 and 22.5 percent, median absolute loudness difference 0.04 LU and none over 1 LU; and the
key estimator's 75 percent exact on the confident keys) and Apple's other figures for reference (tempo 91.4 percent,
key 83.3 percent, vocal correlation 0.645, section recall 1.00). It prints the table and writes the JSON (`--out`).
The engine's own records, in the lab's feature-file shape, go to `<out>.records/<id>.json` (or `--records`), beside the
lab's for its own tools, and are taken again on a later run while the file's size, the tag tempo and the engine are
the same (`--fresh` analyses everything again). The bench writes nothing in the repository unless told to.

### What the Mac needs

The engine is plain Swift and C, so the bench builds and runs on the Mac as it does here:

1. Swift: Xcode's toolchain (Swift 6 or later) is enough; `cd core && swift build -c release --product deckie-build`.
2. ONNX Runtime 1.31.1 for macOS, by the same pattern as Linux: the release archive for the Mac
   (`onnxruntime-osx-arm64-1.31.1.tgz` on an Apple-silicon Mac, from the project's GitHub release page), checked
   against the size and SHA-256 that `DEPENDENCIES.md` section 6 records for it, unpacked so that
   `lib/libonnxruntime.dylib` is at `core/.deps/onnxruntime/lib/libonnxruntime.dylib`, or anywhere with
   `DECKIE_ONNXRUNTIME_LIB` naming it (as section 6 says, fetching it waits on Christopher's yes). Fetched with
   `curl` it carries no quarantine flag; if a browser fetched it, `xattr -dr com.apple.quarantine` on the folder lets
   it load. The vendored C header is the same on every platform.
3. The Beat This! model: `bash core/Tools/fetch-models.sh` puts it and the vocal tagger's model, the same files on
   every machine, into `core/.models/` from this repository's release `models-1`, each kept only if its SHA-256 is
   the pinned one (`DEPENDENCIES.md` sections 7 and 8). Until that release exists, the four files (the two models
   and their `.sha256`) are the artifact `models-beat-this-f1d93204-yamnet-96bb0dc5` of a recent `core-linux` run:
   `gh run download <run id> -n models-beat-this-f1d93204-yamnet-96bb0dc5 -D core/.models`, then
   `bash core/Tools/fetch-models.sh --check` confirms them. A model the script cannot fetch it exports instead
   (`--no-export` stops that), which for Beat This! needs PyTorch at the pinned versions (the Mac's wheels have no
   `+cpu` suffix) and for YAMNet a Python the pinned TensorFlow has a wheel for. `DECKIE_BEAT_THIS_MODEL` names a
   file elsewhere.
4. The vocal tagger's model, `yamnet.onnx`, comes with step 3 (`--yamnet` takes it alone), or is named by
   `DECKIE_YAMNET_MODEL`. Optional: without it the yardstick has no vocal correlation.
5. Run, from `core/`, with the music where the lab had it:

```
export DECKIE_ONNXRUNTIME_LIB="$PWD/.deps/onnxruntime/lib/libonnxruntime.dylib"   # if not in the default place
export DECKIE_BEAT_THIS_MODEL="$PWD/.models/beat_this_final0.onnx"                 # likewise
export DECKIE_YAMNET_MODEL="$PWD/.models/yamnet.onnx"                              # likewise, for the vocal tagger
.build/release/deckie-build bench "/Users/christophershannon/personal/90s2000 playlist" \
    --features ../mixer/features --candidates ../mixer/candidates.json --out ~/deckie-bench/bench.json
```

The same variables serve `deckie-build` itself and the tests (`swift test`), which skip the engine's tests with the
reason printed when ONNX Runtime or the beat model is missing. Without the YAMNet model (step 4 above) the engine runs
without its vocal tagger: both commands say so when they start, the records have no vocal block, and the bench marks
the vocal correlation absent. A work record or a bench record made without the tagger is made again once the model is
there.

## Reinstalling the toolchain on Linux

In a cloud session Swift lives in `/opt/swift-641`, outside the repository, so a reset of the session's container
removes it (`swift: command not found` is the sign). The usual download site, download.swift.org, is blocked there,
so `Tools/install-swift-linux.sh` rebuilds it from the official `swift:6.4.1-noble` image on Docker Hub instead,
checking every piece against its SHA-256 hash before anything is unpacked. It is for Ubuntu 24.04 on x86_64, takes
a minute or two for about 1.2 GB of download (4 GB unpacked), and needs root (or sudo) to write to `/opt`. From the
repository root:

```
bash core/Tools/install-swift-linux.sh          # Swift 6.4.1 into /opt/swift-641
export PATH="$PATH:/opt/swift-641/usr/bin"
```

Run again when Swift is already there, it only reports the version. `install-swift-linux.sh 6.4.2 ~/swift-642`
picks another release or folder. Docker Hub limits anonymous downloads per network address, which a cloud session
shares; if the limit is used up the script waits and retries for a few minutes, and otherwise says to try later.
On a Mac, or on a machine that can reach swift.org, install Swift the normal way instead.
