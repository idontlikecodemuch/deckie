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
  `DeckieCore` types (`FeatureFile+Structure.swift` reads the structure fields on their own).
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
- `Sources/COnnxRuntime` and `Sources/DeckieInference`: ONNX Runtime from Swift, and the beat tracker on it
  (below). `COnnxRuntime` is ONNX Runtime's C API header (vendored unmodified, MIT, pinned in `DEPENDENCIES.md`
  section 6) and a small C file that opens the library at run time; nothing links it.
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
  written by `Tools/make_onnx_fixture.py`) and the beat tracker end to end against the Beat This! package. Both
  need ONNX Runtime, and the beat tracker the model; without them they are skipped, with the reason printed.
  `Tests/DeckieTestSupport` is a small library shared by the test targets: the synthesised drum patterns, the
  beat fixture's reader, and `CPUTurns`, which makes the model runs take turns.
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
with `Resampler` (soxr's "HQ" filter, as the package's `soxr.resample`), computes the package's log-mel spectrogram (`BeatThisFrontEnd`: reflect-padded STFT, torchaudio's Slaney mel filters
rebuilt in float32, log(1 + 1000 x)), runs the network over 30 s chunks as the package does (`BeatThisChunking`) and
picks peaks with the package's minimal postprocessor (`BeatThisPostProcessor`), giving beat and downbeat times. The
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
python3 -m venv /tmp/bt && . /tmp/bt/bin/activate      # the export tools, kept out of the system Python
pip install --index-url https://download.pytorch.org/whl/cpu torch==2.15.0+cpu torchaudio==2.11.1+cpu
pip install -r core/Tools/export-requirements.txt
python3 core/Tools/export_beat_this.py                 # the model into core/.models (82 MB; downloads 81 MB once)
```

```
cd core
swift build
swift test
```

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
