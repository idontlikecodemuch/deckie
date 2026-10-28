# core: DeckieCore

Deckie's own ideas, written once in plain Swift with no Apple-only framework, so the Apple apps and the Windows
and Linux crate builder share them. Charter: `docs/architecture/pc-linux-track.md`; running log:
`docs/architecture/pc-linux-status.md`.

- `Sources/DeckieCore`: the beat grid fit (`GridFit.swift`), the Camelot wheel (`Camelot.swift`), tempo
  relations (`TempoMultipliers.swift`), directed pair scoring (`PairScoring.swift`) and the top lists
  (`Recommendations.swift`). Ported line for line from `mixer/analyze.py` and `mixer/score.py`;
  `PythonCompat.swift` holds the rounding and modulo details that keep the numbers identical. `Loudness/` is the
  loudness module, described below.
- `Sources/DeckieLab`: reads the lab's `mixer/features/<id>.json` and `mixer/candidates.json` into
  `DeckieCore` types.
- `Sources/DeckieAudio`: `AudioBuffer`, decoded audio in memory (interleaved Float32 at the file's own rate, one
  or two channels), in a target of its own with no Foundation so the analysers in `DeckieCore` can take audio
  without depending on the decoder.
- `Sources/DeckieDecode`: audio files to float samples for the analysers (`AudioDecoder.decode(url)` gives an
  `AudioBuffer`; DeckieDecode re-exports DeckieAudio, so importing it is enough). It builds the same on Linux,
  Windows and macOS and needs nothing installed. It reads WAV (16-, 24- and 32-bit integer, 32-bit float) in plain
  Swift and MP3 through the vendored dr_mp3 (below); AAC is recognised and throws a "not supported on this platform
  yet" error until the platform decoders are wired in. Ubuntu's ffmpeg libraries were checked and rejected as GPL
  builds (`DEPENDENCIES.md`). AIFF and AIFF-C are read in plain Swift too (`AIFFReader.swift`: big-endian PCM up to
  32 bits, AIFF-C "sowt" little-endian as macOS writes it, and "fl32" float), with the length and the sample rate
  taken as libsndfile takes them, so the samples match the lab's. Copy-protected MP4s (FairPlay: older iTunes Store
  purchases and Apple Music downloads; any sample entry carrying a "sinf" protection box) are recognised from their
  box tree (`ProtectedMP4.swift`, which also lists what is not detected) and throw a `.protected` error, "protected,
  cannot be read", which the build summary counts apart from `.unsupported`.
- `Sources/CDrMp3`: dr_mp3, a public-domain MP3 decoder in one C header (`include/dr_mp3.h`, copied unmodified
  and pinned by its SHA-256 in `DEPENDENCIES.md`, with its licence quoted), compiled as plain C by `dr_mp3.c`.
  `DeckieDecode/MP3Reader.swift` hands it the file's bytes from memory and gets 32-bit float back, then trims the
  silence MP3 encoding adds the way the lab's decoder (libsndfile through mpg123) does: the encoder delay plus the
  decoder's 529 samples at the start and the padding less 529 at the end, read from the LAME tag in the first
  frame. dr_mp3's own version of that trimming is switched off so the rule stays Deckie's. On the test tones the
  result has the original's exact length and sits at offset 0 from the lab's decode, within 1.3e-6 per sample. To
  update it, see `DEPENDENCIES.md` section 4.
- `Tests/DeckieCoreTests`: parity tests against the lab. `Fixtures/` holds the reference numbers, written by
  `Tools/make_fixtures.py` with the lab's own Python (needs numpy; run from the repository root). The tests also
  read `mixer/features/`, `mixer/candidates.json` and `mixer/recs.json` straight from the repository.
  `LoudnessTests.swift` uses synthesised signals only: the published BS.1770 coefficients, the EBU Tech 3341 and
  3342 test cases, true peak between samples, and a speed check.
- `Tests/DeckieDecodeTests`: the decoder's tests. `Fixtures/` holds a generated test tone (two sines and a click)
  as WAV at 44.1 and 48 kHz, MP3 at 44.1 and 48 kHz and in mono, AAC, AIFF and AIFF-C ("sowt"), plus a 648-byte
  stand-in for a FairPlay-protected file with no audio in it (`protected.m4p`), written by
  `Tools/make_audio_fixtures.py` (needs numpy, and the ffmpeg program for the MP3, AAC and AIFF files only; the same
  ffmpeg gives the same bytes on every run). The MP3 tests also edit those bytes in memory: ID3 tags in front,
  edited LAME tags, damaged files; the AIFF and protected-file tests build their variants the same way.

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
