# core: DeckieCore

Deckie's own ideas, written once in plain Swift with no Apple-only framework, so the Apple apps and the Windows
and Linux crate builder share them. Charter: `docs/architecture/pc-linux-track.md`; running log:
`docs/architecture/pc-linux-status.md`.

- `Sources/DeckieCore`: the beat grid fit (`GridFit.swift`), the Camelot wheel (`Camelot.swift`), tempo
  relations (`TempoMultipliers.swift`), directed pair scoring (`PairScoring.swift`) and the top lists
  (`Recommendations.swift`). Ported line for line from `mixer/analyze.py` and `mixer/score.py`;
  `PythonCompat.swift` holds the rounding and modulo details that keep the numbers identical.
- `Sources/DeckieLab`: reads the lab's `mixer/features/<id>.json` and `mixer/candidates.json` into
  `DeckieCore` types.
- `Sources/DeckieDecode`: audio files to float samples for the analysers (`AudioDecoder.decode(url)` gives an
  `AudioBuffer`: interleaved Float32 at the file's own rate, one or two channels). It builds the same on Linux,
  Windows and macOS and needs nothing installed. It reads WAV (16-, 24- and 32-bit integer, 32-bit float) in plain
  Swift and MP3 through the vendored dr_mp3 (below); AAC is recognised and throws a "not supported on this platform
  yet" error until the platform decoders are wired in. Ubuntu's ffmpeg libraries were checked and rejected as GPL
  builds (`DEPENDENCIES.md`).
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
- `Tests/DeckieDecodeTests`: the decoder's tests. `Fixtures/` holds a generated test tone (two sines and a click)
  as WAV at 44.1 and 48 kHz, MP3 at 44.1 and 48 kHz and in mono, and AAC, written by `Tools/make_audio_fixtures.py`
  (needs numpy, and the ffmpeg program for the MP3 and AAC files only; the same ffmpeg gives the same bytes on
  every run). The MP3 tests also edit those bytes in memory: ID3 tags in front, edited LAME tags, damaged files.

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
