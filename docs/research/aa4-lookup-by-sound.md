# Research AA4: "Look up songs by sound": the fingerprint, the AcoustID client and a first trial

Dated Nov 14, 2026. What was built and measured, no decisions. It is the engine room of the lookup by sound that the
note on D30 asks for ("Look up song via ...", for the disc of songs with no labels), on the route research letter
AA calls C: a fingerprint of the sound made on the DJ's computer, asked of AcoustID, whose answer is a MusicBrainz
recording that Deckie's MusicBrainz code already turns into a name. **No window of Desk uses it yet.** It was tried
on public recordings only: none of the owner's music was read, fingerprinted or looked up.

## In plain words

A **fingerprint** here is a short description of how a song's sound moves over its first two minutes: which of the
twelve notes of the octave are loud, frame by frame, boiled down to 32 yes-or-no answers about every eighth of a
second. It can't be played back. **AcoustID** is a public service that keeps such fingerprints for tens of millions
of recordings and says which recording a new one matches, with a **score** from 0 to 1. It answers with the
recording's **MusicBrainz** id, the same open catalogue Desk's lookup by words already uses (D36).

AcoustID only reads fingerprints made one exact way, Chromaprint's. Chromaprint's own code is free to use (MIT), but
the project as a whole carries a library under a stricter licence (LGPL 2.1), which is why letters B and AA planned
to ship it as a separate file. Instead, Chromaprint's method was rewritten in Swift from its MIT files only, with a
resampler of Deckie's own in place of the stricter part. The question was whether that rewrite gives the fingerprints
AcoustID expects. It does: **on 35 real songs and 15 made-up sounds, every bit agreed with Chromaprint's own
program**, and AcoustID gave the same answer for all 35.

## Summary

- **Built:** `DeckieChroma` (the fingerprint, pure Swift, on macOS, Linux and Windows), an AcoustID client in
  `DeckieLookup` (`AcoustID.swift`, `AcoustIDTransport.swift`), and the trial tool `deckie-sound-trial`.
- **Agreement with `fpcalc`** (Chromaprint's own program, v1.6.2, the official macOS build): **no bit
  differs**: 0 of 1,052,736 bits on the public songs, and 0 of 127,200 on the generated sounds.
  The compressed fingerprint text, and the length in seconds, were also the same for every file.
- **Public set, 35 songs:** AcoustID named **30** (86 percent). Of the 33 whose tags or file name give a title, 28
  were named and **all 28 agreed** with that title and artist; the other 5 got no answer at all (none wrong). The 2
  songs with no usable title were named correctly too (read by hand). Best scores: 24 between 0.9 and 1.0, 6 at
  exactly 1.0.
- **Same answer as `fpcalc`'s own fingerprint: 35 of 35.** Every miss was a miss for `fpcalc` too: five piano
  recordings AcoustID does not hold.
- **Speed:** about 0.2 seconds a song on this Mac for decoding and fingerprinting (fpcalc: 0.1); AcoustID asks take a
  third of a second each at its limit.

## What was built

**`DeckieChroma`** (`core/Sources/DeckieChroma/`). `Chromaprint.fingerprint(file:)` decodes the file with Deckie's
own decoder (`DeckieDecode`), and gives the raw frames (`frames`, 32 bits each) and the compressed text AcoustID
takes (`compressed`), with the whole file's length. The steps are Chromaprint's algorithm 2 (its "TEST2", the
default and the one AcoustID indexes), as Chromaprint's source has them:

| Step | The numbers, from the source |
|---|---|
| Audio in | the first 120 seconds (fpcalc's default); the two channels averaged; resampled to 11,025 samples a second; rounded to 16-bit whole numbers, as fpcalc feeds them |
| Frames | 4,096 samples, a new frame every 1,365 (4,096 minus an overlap of 4,096 − 4,096 / 3); a Hamming window scaled by 1 / 32,767; the power of each frequency |
| Chroma | every frequency from 28 Hz to 3,520 Hz added into one of the 12 notes, counted from A at 27.5 Hz, no spreading between notes |
| Smoothing | each note over five frames with weights 0.25, 0.75, 1, 0.75, 0.25; then each frame's 12 values scaled to length 1 (all 0 under 0.01) |
| Bits | 16 trained filters, each comparing two rectangles of that picture of notes over time as log((1 + a) / (1 + b)), cut by three trained thresholds into four steps, two bits each in Gray code: 32 bits a frame |
| Text | each frame XORed with the one before, the gaps between its set bits packed in 3 and 5 bits, a 4-byte header (algorithm 1, the frame count), URL-safe base64 without padding |

The **resampler** is Deckie's own (`Resampler.swift`): a sinc filter under a Kaiser window, worked out exactly for
each fraction of a sample (a "polyphase" table). It is tuned to the settings Chromaprint's own code gives FFmpeg's
resampler when fpcalc reads a file (16 taps at the lower rate, the pass band ending at 0.8 of its half, FFmpeg's
default window). The **Fourier transform** is DeckieCore's. MP3 files keep the same start as FFmpeg's because
Deckie's MP3 reader already trims the encoder's delay the way FFmpeg does.

**The AcoustID client** (`DeckieLookup`). `AcoustID.lookup(fingerprint:duration:)` sends one POST to
`https://api.acoustid.org/v2/lookup` with `client`, `duration`, `fingerprint`, `meta=recordings+releasegroups+compress`
and `format=json` in the form body, never in the address. It answers with each match's AcoustID id, its score, and
the MusicBrainz recordings with their titles, artists (joined as credited), lengths and release groups, best first.

- **Pacing:** one gate for the program, the same kind as MusicBrainz's, at most one request every 0.34 seconds
  (their "3 requests per second"). A 503 or 429 is waited out (its Retry-After, else 2 then 4 seconds) and asked
  again at most twice. AcoustID's own errors ("invalid API key") come back as plain words.
- **User-Agent:** the MusicBrainz one, `DeckieDesk/<version> ( https://deckie.io )`.
- **The key** is read from `DECKIE_ACOUSTID_KEY`. Without it the client says "There is no AcoustID application key
  on this computer (DECKIE_ACOUSTID_KEY), so nothing was sent." and sends nothing. It is never printed, logged or
  written: the client prints as "AcoustID client (...)" with no fields, the sent list shows only the length and the
  first 16 characters of the fingerprint, and recorded answers are found by a hash of the fingerprint. Tests check
  each of these. After the trial, a search for the key in every results file and in the repository found nothing.
- **Transport:** MusicBrainz's request type carries no body, and its file is not changed here, so a form is a second
  request type (`LookupPost`) with a second protocol (`LookupPostTransport`) that the three existing transports also
  take: the Mac's system session (the same ephemeral one), the stand-in on Linux and Windows that says the lookup is
  not on this computer yet, and the recorded answers the tests use. When Linux and Windows get a transport, it needs
  a `post` as well as a `send`.

**The trial tool** (`deckie-sound-trial`): `print` (the fingerprint, as fpcalc prints it), `compare` (bits against
`fpcalc -raw`, file by file) and `lookup` (each file asked of AcoustID; with `--fpcalc`, fpcalc's fingerprint of the
same file is asked too and the answers compared). The agreement measure is the MusicBrainz trial's: the title
without its version the same, one artist's name inside the other's. Per-file detail goes only to a file under
`.scratch/`, which the tool insists on.

## How it was checked

**Against `fpcalc`.** The official `fpcalc` 1.6.2 for macOS, from Chromaprint's GitHub releases page only, kept in
`.scratch/lookup-sound/` (git-ignored; not committed, not shipped).

| Set | Files | Frames | Bits that differ |
|---|---:|---:|---:|
| Generated (sweeps, clicks, noise with a fixed seed, chords, a melody at 8,000, 11,025, 22,050, 44,100 and 48,000 a second, a stereo 150-second piece as WAV and as MP3, a FLAC) | 11 | 3,642 | 0 |
| The four test sounds of the unit tests | 4 | 333 | 0 (the compressed text equal, too) |
| Public songs (below) | 35 | 32,898 | 0 |

The bar set beforehand was under 2 percent. A different resampler was expected to flip some bits; it flipped none,
because each bit is a coarse step of a smoothed, normalised value and the two resamplers' outputs differ by far less
than a step. **What could still make bits differ** [inf]: another computer's `sin`, `exp` and `log` rounding in the
last place, which can move a value across a threshold now and then (the unit tests allow 0.5 percent off the Mac for
this); files whose decoders differ from FFmpeg's (AAC is not decoded by Deckie on the Mac or Linux yet); and MP3s
whose encoder delay is not written in the file, where FFmpeg and Deckie might start at different samples.

**Without `fpcalc` or the network.** `core/Tests/DeckieChromaTests` makes four sounds in code, the same on every
computer (a sweep, clicks over a hum, stereo noise from a fixed 32-bit seed at 48,000 a second, chords at 11,025),
and compares them with what `fpcalc` printed for them once, kept as numbers (`FpcalcPrints.swift`). Also: the
compressed form round-trips, the resampler passes a constant level and a 1 kHz tone and removes 6 kHz. The AcoustID
tests (`core/Tests/DeckieLookupTests/AcoustIDTests.swift`) use a stand-in transport.

## The public set

Thirty-five recordings fetched from the Internet Archive into `.scratch/lookup-sound/public/`, chosen as likely to be
in AcoustID, from four releases a band or a pianist put out under open licences: a rock album of 2008 (A, 10 FLAC
files; CC BY-NC-SA), the same band's instrumental album of 2008 (B, tracks 1 to 10, MP3, the official download), an
indie album first published on Jamendo (C, 8 tracks, MP3; CC BY-NC-SA), and seven mazurkas from Musopen's recordings
of the complete works of a composer for piano (D, MP3; CC0). Which items they are is in the fetch script beside them
in `.scratch/lookup-sound/scripts/`. Fingerprints only were sent; the files stay on that Mac.

| | Ours | fpcalc's |
|---|---:|---:|
| Files asked | 35 | 35 |
| Answered with at least one recording | 30 | 30 |
| Judged (a title from the tags, or "Artist - Title" in the name) | 33 | 33 |
| Agree with that title and artist | 28 | 28 |
| Named wrong | 0 | 0 |
| Same best recording as the other fingerprint | 35 of 35 | |

| Best score | 0.9 to 0.99 | 1.0 |
|---|---:|---:|
| Songs | 24 | 6 |

By release: A 10 of 10 (two of its songs have only numbers for titles, and so were not judged by the rule; both
were right, read by hand), B 10 of 10, C 8 of 8, D 2 of 7. The five misses are Musopen piano recordings that AcoustID has no fingerprint for; nothing was named wrong. This set is
easier than a DJ's crate: whole released albums, each song as released. Letter AA's warnings still stand: AcoustID
matches the same recording, so a DJ's edit, a bootleg or a radio edit gets the original or nothing [AA, K].

## Licence position, file by file

Chromaprint's `LICENSE.md`: its own code is MIT; "As a whole, Chromaprint should be therefore considered to be
licensed under the LGPL 2.1 license" because of the FFmpeg parts it includes. Every file ported carries the header
"Distributed under the MIT license": `src/fingerprinter_configuration.cpp` (the frame numbers, the chroma filter's
weights and the trained table `kClassifiersTest2`), `src/fingerprinter.cpp`, `src/fft.cpp`, `src/fft_lib_kissfft.cpp`,
`src/audio/audio_slicer.h`, `src/chroma.cpp`, `src/chroma_filter.cpp`, `src/chroma_normalizer.h`, `src/utils.h`,
`src/fingerprint_calculator.cpp`, `src/classifier.h`, `src/filter.h`, `src/filter_utils.h`, `src/quantizer.h`,
`src/utils/rolling_integral_image.h`, `src/fingerprint_compressor.cpp`, `src/fingerprint_decompressor.cpp`,
`src/utils/pack_int3_array.h`, `src/utils/pack_int5_array.h`, `src/utils/base64.h`. Read for their numbers only:
`src/cmd/fpcalc.cpp` (no header; the project's MIT part) and `src/audio/ffmpeg_audio_processor_swresample.h` (MIT).
Not used and not read: `src/avresample/` (LGPL 2.1, from FFmpeg) and FFmpeg's FFT. The trained table was MIT, so
nothing needed had to be left out. The notice is in `core/Sources/DeckieChroma/LICENSE-chromaprint` and
`DEPENDENCIES.md` section 14.

## Still open (for the owner and the attorney)

1. **Whether any of the owner's music may be fingerprinted and sent.** Nothing of his was touched. Before a trial on
   his library: his yes to sending AcoustID a fingerprint and the length of each file tried (no names, no paths), from
   this Mac's network address; which folder; whether the sealed half of the new music stays out (it should, to keep
   it unseen).
2. **How the shipped app carries AcoustID's application key.** Today an environment variable on one Mac. A key built
   into an app can be read out of it; AcoustID's keys identify an application, not a person, so that is the normal
   way, but the choice (built in, or fetched from Deckie's own server) is open.
3. **AcoustID's terms for a paid app** (letter AA): free "for non-commercial use only"; a commercial product
   subscribes, 50 euros a month for a million searches, a free trial of 10,000. Only the MusicBrainz ids and what
   MusicBrainz says may be kept; AcoustID's own ids and data are share-alike. The trial kept AcoustID ids only in
   its private results file.
4. **The public privacy line** must be reworded before this reaches anyone (D30, D36): a fingerprint is sent,
   with the length and the network address.
5. **Linux and Windows** need a transport that can POST (DEPENDENCIES.md section 12's three ways).
6. **The Desk window** for it: the wording ("Look up song via AcoustID"), batches, and what is shown when the answer
   is the original of a DJ's edit.

## Sources

- Chromaprint, release v1.6.2: https://github.com/acoustid/chromaprint (LICENSE.md and the files named above), and
  https://github.com/acoustid/chromaprint/releases (fpcalc)
- AcoustID web service: https://acoustid.org/webservice
- Research letters AA (`aa-naming-songs.md`) and B (`b-identification.md`)
