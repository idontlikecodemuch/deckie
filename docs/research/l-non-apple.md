# Track L: Deckie off Apple platforms

Dated Oct 28, 2026. Answers Christopher's question: "we need to start working on the PC / non Apple version. Can we
use Apple's tech at all?" Scope: the decided Apple design (D11 one Swift engine on Music Understanding, D13 the crate
as our own format, D3 no server, audio never leaves the device) and what a Windows, Linux or Android version can
reuse, replace or import. Licence quotes come from the licence files; primary sources are listed in section 9;
[inf] marks inference; nothing here is legal advice. Effort figures are one experienced engineer, full time.

## 1. Summary (one page)

**Apple's tech off Apple: one piece carries, one does not, one half does.**

- **ShazamKit (recognition) carries to Android, with a catch.** Apple ships a ShazamKit SDK for Android (v2.1.1, an
  AAR, Android 5.0+). It matches on the device against a custom catalogue ("All matches will be performed locally
  on the device"), it supports frequency skew ranges and timed items, and no internet or Apple token is needed for
  a custom catalogue. The catch: Android can only **load** a catalogue file (`addFromCatalog`). It cannot generate
  reference signatures or build a catalogue; Apple staff: "you can only load a Custom Catalog, but you can't create a
  new one or add signatures or media items to it." So the DJ's own files must be turned into a catalogue on a Mac,
  iPhone or iPad (macOS even ships a `shazam` command-line tool that does it). A catalogue built on iOS loads and
  matches on Android once every signature has metadata (Apple staff, Nov 2021). There is no published licence for
  the Android SDK; the download sits behind an Apple ID sign-in; two forum threads asking for the licence (Oct 2021,
  Apr 2025) got no answer. Ask Apple in writing before shipping.
- **Music Understanding (the analysis) does not carry.** The SDK on this Mac marks every type
  `@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)` and imports Core ML and
  AVFoundation; Apple's session says it gives "on-device musical intelligence across all Apple platforms". Nothing
  suggests a port.
- **Swift half carries.** Swift builds on Windows and Linux with Foundation, but Accelerate (Apple's maths library),
  AVFoundation (audio decoding), Core ML and ShazamKit do not. Our own DSP (the beat-grid fit, segments, lattice, mix
  windows, Camelot) is plain arithmetic over arrays and can be shared if the FFT and the decoder sit behind a small
  shim (KissFFT or PocketFFT, both BSD-3; platform decoders).

**A second engine with shippable licences exists for every block but one.** Beats and downbeats: Beat This! (MIT,
code and weights, confirmed by the maintainers on Oct 25, 2026) on ONNX Runtime (MIT); and because the lab's reference
beats *are* Beat This!, a second engine built on it reproduces the 373-track yardstick on beats more exactly than
Apple's engine does (Apple: beat F 0.987 median; a Beat This! port: 1.0). Loudness: libebur128 (MIT), same standard
as the lab. Structure: our own Foote novelty and lattice, already planned as level 2. Vocal: YAMNet (Apache 2.0) or
EfficientAT (MIT), HTDemucs (MIT) when there is time. Decoding: dr_mp3 (public domain) and the platform decoders for
AAC. **The gap is key.** Our own chroma estimator reached 75 percent exact against Apple's 83 and flags a false key
change on 27 of 60 ordinary songs against Apple's 9; every better open key detector is GPL, AGPL or non-commercial.
Key, including "where it changes", is on the differentiator list, so a non-Apple engine starts weaker where it
matters most.

**Recognition without ShazamKit is a research project.** Chromaprint is LGPL 2.1 (usable with dynamic linking) but is
built for whole-file identification and "trades precision and robustness for search performance"; audfprint and
Dejavu are MIT, verified, and not pitch-robust. The right design, quad-based fingerprints (Qfp), has no official code
and reaches 0.94 to 0.98 only on 20-second queries. The Shazam patent that paper cites is listed as expired on Mar
31, 2025 (Google Patents' estimate). Own build: 3 to 6 months with an uncertain result [inf]. Not now.

**What Windows DJs run already carries grids and cues.** The 2026 Global DJ Census (22,000 DJs): rekordbox 34 percent,
Serato 27, VirtualDJ about 17; no operating-system split is published, but all three run on Windows. rekordbox's XML
export carries beat grids as `TEMPO` markers (start, BPM, meter, beat) and cues as `POSITION_MARK`, in a format
Pioneer documents; Serato keeps grids and cues in the audio files' own tags; VirtualDJ keeps them in `database.xml`.
What none of them carries is what Deckie adds: key segments, mix windows, vocal activity, loudness, signatures.

**Recommendation (section 7).** (0) Make the iPad the crate-builder for DJs without a Mac: it runs the full engine on
files from a USB stick, and it can generate ShazamKit signatures itself. That is zero new engine code and covers
every Windows DJ who owns the iPad the booth needs anyway; only discs stay Mac-only. (1) Ship Apple. (2) Then a
Windows and Linux "Desk Lite" crate-builder in Rust: rekordbox XML import first, the second engine for what the XML
lacks, writing the same crate; about 3 to 4 months to parity on the 373 tracks plus a month of Windows packaging
[inf]; signatures still made on the iPad. (3) An Android booth only if the trials ask for it: 4 to 6 months [inf],
loading a Mac- or iPad-built catalogue. Honest cost of the full non-Apple story: 8 to 12 engineer-months, a weaker
key, and a recognition step that still touches an Apple device.

## 2. Can Apple's technology be used off Apple?

### 2.1 ShazamKit for Android

Facts from Apple's Android documentation and the API reference (all quotes):

- What it is: version 2.1.1, "comes in the form of an Android Archive (AAR) file", `minSdkVersion 21` (Android
  5.0), Kotlin. Live matching takes "PCM 16bit MONO" at 48000, 44100, 32000 or 16000 Hz through a
  `StreamingSession`; a `SignatureGenerator` turns "pre-recorded audio" into a query `Signature`.
- Custom catalogues: the `CustomCatalog` class: "Use a custom catalog if you intend to search against reference
  signatures that you have provided yourself. All matches will be performed locally on the device against the
  signatures added to this Catalog. ... Once this catalog has been built it can be written to disk and loaded again
  at a later date." Its only function is `addFromCatalog(source: InputStream)`: "Load a pre made Custom catalog from
  disk." `MediaItem` carries `frequencySkewRanges`, `timeRanges` and custom keys. "There are no limitations on how
  or where you can store your Custom Catalog files."
- What it cannot do: Apple staff, Nov 2021: "Adding custom signatures to a catalog is currently not supported by
  the Android SDK." Nov 2022: "you can only load a Custom Catalog, but you can't create a new one or add signatures
  or media items to it. But you can create your custom catalogs remotely and then ship those to your android app."
  The 2.1.1 reference still lists only `addFromCatalog`.
- Cross-platform catalogues: in the 2021 thread a catalogue "generated on iOS" loaded on Android; matches failed
  until metadata was attached, because "the Android SDK disregards a signature (or clusters of signatures) that
  have no associated metadata"; with metadata the Apple engineer "was able to get matches". Android's query-length
  limits "don't necessarily need to adhere to the iOS counterpart". WWDC21: a `.shazamsignature` "is an opaque file
  that can be shared across devices." Every Deckie signature carries its track's metadata, so this fits [inf].
- Where catalogues get built: macOS ships `/usr/bin/shazam` (WWDC22: "The Shazam CLI ships as part of macOS 13"),
  present on this Mac, with `signature` and `custom-catalog create|update|display|remove|export`, taking a CSV of
  media items whose headers include `frequencySkewRanges`. On iPhone and iPad, `SHSignatureGenerator`'s
  "signatureFromAsset" is "available on all platforms" (WWDC22), so the iPad can build the catalogue from audio
  files it can see (a USB stick in Files).
- Account and terms: the Shazam catalogue (which Deckie does not use) needs "an Apple Developer token" and internet;
  a custom catalogue needs neither. The SDK download redirects to an Apple ID sign-in; whether a paid membership is
  required is unverified. The Android page carries no licence text; the Apple Developer Program License Agreement
  defines "ShazamKit APIs" for Apple platforms and forbids using ShazamKit data "for the purpose of improving ... or
  creating another audio recognition service". Get the Android terms from Apple in writing (section 8).
- Not measured: several Android sessions at once (the multi-matcher of P11), CPU per session, match latency on a
  mid-range tablet.

What this means: an Android booth app can recognise the DJ's own crate on the device, offline, exactly as the iPad
will, but the crate's catalogue must be made on a Mac, iPhone or iPad. A Windows PC alone cannot make one.

### 2.2 Music Understanding

Apple only. The framework's Swift interface in the macOS 27 SDK on this Mac marks every public type
`@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)` and imports `AVFAudio`,
`AVFoundation`, `CoreML` and `CoreMedia`, so it is built on Apple's media stack and on-device models. Apple's WWDC26
session: "It gives you access to on-device musical intelligence across all Apple platforms", "it runs entirely
on-device". No Android, Windows or Linux form exists, and nothing in Apple's history suggests one [inf].

### 2.3 Swift off Apple

Swift 6.4.1 installs on Windows 10 and 11 (x86_64 and arm64) and on Linux; the Windows port covers "the core
libraries (dispatch, Foundation, XCTest)". What does not exist off Apple: Accelerate (vDSP, the FFT and vector maths
the port plan leans on), AVFoundation (decoding MP3 and AAC), Core ML, ShazamKit, SoundAnalysis, SwiftUI. Apple's own
swift-numerics (Apache 2.0) is "intended to provide a uniform cross-platform API" and has no FFT.

Could our DSP be one Swift package on three platforms? Yes, if it is written against two small protocols, an
`FFTProvider` and an `AudioDecoder`, with Accelerate and AVFoundation behind them on Apple and KissFFT (BSD-3) or
PocketFFT (BSD-3) plus the platform decoder elsewhere. The port plan already separates "plain Swift over arrays"
from "vDSP", and most blocks are plain Swift; the vDSP calls in A12, A14, A15 and A17 would go through the shim,
and speed off Apple then depends on the Swift compiler rather than Accelerate [inf]. A Rust core (section 5) is the
alternative: one numeric implementation on all platforms with mature audio crates, called from Swift through a C
interface.

## 3. Replacements for each analysis block

What Apple's framework measured on the 373 tracks (stage 1): beat F 0.987 and downbeat F 0.968 against the lab's
detections; BPM within 2 percent on 91 percent; key exact 83 percent and a Camelot neighbour 13 percent where the lab
is confident; integrated loudness within 0.04 LU; vocal-per-bar correlation 0.64 with the lab's over-reporting head;
section recall 1.00, precision 0.24 against the lab's 8-bar boundaries; 11.8 s per track in the simulator.

| Block | Candidate | Licence (quoted from the licence file) | Quality against what we measured | Speed | Runtime |
|---|---|---|---|---|---|
| Beats, downbeats | **Beat This!** final0 (about 20M parameters, 78 MB) or small (about 2M, 8 MB) | README: "The code and the published model weights are released under the MIT license." Maintainer, Oct 25, 2026: "you're free to use them commercially and also free to redistribute them", with the caveat "we are not lawyers" and that training data includes commercial music | The lab's reference beats are Beat This! final0, so a port matches the yardstick at F 1.0 (the Rust port reports 1.0 for the full model, at least 0.99 for small, at 70 ms). Paper, GTZAN: beat F1 89.1 / downbeat 78.3 (full), 88.8 / 77.2 (small). Apple scored 0.987 against these | Rust port on an M4: 4.6 s for a 4:32 track, 12 s for 13:48 | ONNX Runtime (MIT; Windows, Linux, Android, iOS, web, macOS by Homebrew) or the pure-Rust `rten` the Rust port defaults to; PyTorch not needed |
| Beats (alternatives) | BeatNet | "Attribution 4.0 International" (CC BY 4.0; commercial use allowed with attribution) | Lower than Beat This! in the literature; needs madmom's DBN code (BSD) and librosa | n/a | PyTorch |
| | TempoCNN, Key-CNN (Schreiber) | "Source code and models can be licensed under the GNU AFFERO GENERAL PUBLIC LICENSE v3" | cannot ship | | |
| | madmom | code: a BSD-style licence; models: "Creative Commons Attribution-NonCommercial-ShareAlike 4.0", commercial use "requires contacting Gerhard Widmer" | code only; the beat and key models cannot ship | | |
| Key | **Our own FFT-chroma estimator** (`mixer/key_light.py`: chroma from a plain FFT, published Krumhansl, Temperley and EDMA key profiles taken from the papers, Pearson correlation; windowed with the hysteresis rule) | ours | Whole song: 75 percent exact against the lab's confident keys where Apple reaches 83. On windows it catches the same modulations but opened a second segment on 27 of 60 ordinary songs against Apple's 9 | a few hundred ms per track | none |
| | libKeyFinder | "published under the GNU General Public License version 3 or later"; needs FFTW3 (GPL) | cannot ship | | |
| | Mixxx's key detector, Essentia's, madmom's, Key-CNN | GPL-2+ / AGPL-3 / CC BY-NC-SA / AGPL-3 | cannot ship | | |
| Structure, sections | **Our own Foote novelty + 8-bar lattice** (A13, already the level 2 path) | ours | It is the lab's own boundary set; the yardstick's 8-bar boundaries come from it, so parity is by construction. Labels (intro, main, break, outro) come from energy and vocal (A20) | under 0.3 s | none |
| | MSAF (Nieto) as a lab reference: `foote`, `sf`, `cnmf`, `scluster`, `olda`, `cbm`, `fmc2d`, `vmo` | "MIT License", "Copyright (c) 2016, Oriol Nieto" (two further algorithms live in a separate GPL repo) | a Python research framework; useful to pick the second boundary method, not to ship | | Python |
| | all-in-one (Kim) | "MIT License", "Copyright (c) 2023 Taejun Kim" | beats, downbeats, sections with labels in one model, trained on Harmonix; 10 songs (33 min) in 73 s on an RTX 4090 | needs Demucs stems first, NATTEN, PyTorch, GPU in practice | PyTorch; a Desk-with-GPU option only [inf] |
| Instrument and vocal activity | **EfficientAT mn04** (0.98M, MIT) or **YAMNet** (3.7M, Apache 2.0): a "Singing" probability per second | EfficientAT: "MIT License", "Copyright (c) 2022 Florian Schmid"; YAMNet in tensorflow/models: "Apache License, Version 2.0" (track J) | unmeasured on our material; the track J listening set (40 tracks, labelled per bar) is the test. Apple's 50 ms series had correlation 0.64 with the lab head and reads "not vocal" on sampled vocals | seconds per track [inf] | ONNX Runtime or TensorFlow Lite (Apache 2.0) |
| | **HTDemucs** vocal stem energy per bar, via demucs.cpp | Demucs: "released under the MIT license"; demucs.cpp: MIT; the ggml weights are converted from the MIT checkpoints | the strongest signal on sampled and chopped vocals (track J) | demucs.cpp: a 4-minute song in 4 min 9 s with 4 threads on a 16-core Ryzen 5950X, about real time on a desktop CPU; GPU needed for a 2,000-track crate | Eigen, no ML runtime; or PyTorch/ONNX with a GPU |
| Loudness | **libebur128** (C) or the **ebur128** Rust port | "All source code is licensed under the MIT license."; Rust: "ebur128 is licensed under the MIT license", "produces the same results as the C library" | the lab uses pyloudnorm, the same BS.1770 and EBU Tech 3342 maths; Apple matched that within 0.04 LU, so this is parity by standard | under a second | none |
| | ffmpeg's `ebur128` filter | "FFmpeg is licensed under the GNU Lesser General Public License (LGPL) version 2.1 or later"; with `--enable-gpl` "the GPL applies to all of FFmpeg"; the checklist: "Use dynamic linking (on windows, this means linking to dlls)" | fine, but heavy for one filter | | ffmpeg dlls |
| Decoding MP3 | **minimp3** or **dr_mp3** (built on it) | minimp3: CC0-1.0; dr_libs: "This is free and unencumbered software released into the public domain" or "MIT No Attribution" | bit-exact enough; MP3 licensing ended ("On April 23, 2017, Technicolor's mp3 licensing program ... has been terminated") | fast | none |
| Decoding AAC (.m4a) | **Platform decoders**: Windows Media Foundation ("AAC Decoder", Windows 7+; "MPEG-4 File Source" for .m4a; "Windows Media MP3 Decoder"), Android MediaCodec (AAC LC and MP3 on all versions), ffmpeg LGPL dlls on Linux | platform; ffmpeg LGPL with dynamic linking | the platform's decoder, as AVFoundation is on Apple | fast | none |
| | Symphonia (Rust) | "Symphonia is provided under the MPL v2.0 license." MP3 "Excellent", AAC-LC "Great", HE-AAC still in work | fine for MP3 and plain AAC; HE-AAC files would fail | fast | none |
| | FAAD2 | GPL-2 | cannot ship | | |

Three notes on the table. First, AAC patents: Via LA says "An AAC patent license is needed by manufacturers or
developers of end-user encoder and/or decoder products"; shipping our own AAC decoder (Symphonia's) is therefore a
licensing question that the platform decoder avoids, as AVFoundation does on Apple [inf, not legal advice]. Second,
decoder differences matter for comparability: the all-in-one author notes that MP3 decoders "can introduce 20-40 ms
offsets", so the crate should record the decoder and the engine should align bar 1 to first sound, as A8 already
does. Third, the EffNet timbre embedding is gone on every platform (NonCommercial), so the hand-crafted style vector
of the port plan serves both engines.

## 4. Recognition off Apple, if ShazamKit for Android does not fit

- **Chromaprint.** Its licence file: "Chromaprint's own source code is licensed under the MIT license" but, because
  of FFmpeg parts, "As a whole, Chromaprint should be therefore considered to be licensed under the LGPL 2.1
  license." Dynamic linking satisfies that. It is the wrong tool: built for "full-file identification" and it
  "trades precision and robustness for search performance". Nothing about pitch or tempo tolerance; a resampled
  record changes every chroma frame's timing.
- **audfprint and Dejavu.** Verified MIT: "The MIT License (MIT)", "Copyright (c) 2014-5 Dan Ellis, Columbia
  University, and Google."; "MIT License", "Copyright (c) 2013 Will Drevo". Both are Shazam-style landmark pairs;
  neither claims speed or pitch tolerance; Panako's paper found audfprint fails above 3 percent pitch shift and a
  2025 benchmark gives Dejavu 25 percent top-1 under time stretch (track H). Dejavu wants MySQL or Postgres.
- **The pitch-robust designs.** Panako and Olaf are AGPL (track H). Qfp (Sonnleitner and Widmer, 2016) is the right
  shape: quads of spectral peaks, hashes invariant to independent time and frequency scaling, and it reports the
  scale factors, which is the fader reading Deckie wants. Paper numbers: 0.98 (speed), 0.98 (tempo), 0.94 (pitch)
  on 20-second queries; 0.77 / 0.71 / 0.56 on 5-second queries; on real DJ mixes the best system managed 25 to 74
  percent. No official code. The paper's footnote cites a US patent "claimed to be immune to various
  transformations, including time/frequency scale modifications"; Google Patents lists US7627477B2 ("Robust and
  invariant audio pattern matching", Wang and Culbert, priority Apr 25, 2002, assignee Shazam/Apple) as
  "Expired - Lifetime" with an adjusted expiry of Mar 31, 2025, flagged as an estimate, not a legal conclusion.
- **What building our own would take.** A C or Rust fingerprinter (log-frequency spectrogram, peak picking, quad
  hashing, an on-device hash table, a scale-factor estimator), catalogue-side generation in the crate-builder,
  tuning on track H's offline renders and noise proxies, then a real room. Three to six months, with the published
  accuracy on short queries well under what ShazamKit gives today (25 of 25 within its window on 8-second matches)
  [inf]. It is the only route for a Windows-only DJ with an Android tablet, and a research track, not a v1 item.

## 5. Architecture options with effort

| Option | What it is | What it needs from Apple | Effort [inf] | What it buys |
|---|---|---|---|---|
| **0. iPad as the crate-builder** | The booth iPad runs the full engine on files from a USB stick or Files, generates signatures itself, writes the crate | nothing new: D11 already puts the engine on the iPad | 0 engine work; UI for "build from this drive" plus an overnight batch mode, 2 to 3 weeks | Every Windows DJ who owns the iPad; discs excepted (the iPad cannot read optical drives) |
| **A. Desk Lite for Windows and Linux** | A crate-builder: import rekordbox XML (grids, cues), decode, run the second engine for the rest, write the same `.deckiecrate`; no recognition | signatures are made by the iPad from the same drive | Rust core 3 to 4 months to parity on the 373 tracks; XML importer 2 weeks; Windows packaging, signing, a small GUI (Qt under LGPL with dynamic linking, or a command line plus the iPad as the face) 4 weeks | A Windows DJ builds and maintains the crate on the machine where the music lives; Linux for free |
| **B. Android booth** | The booth app in Kotlin: listen, picks, join, set log; ShazamKit Android streaming sessions against a Mac- or iPad-built catalogue | the catalogue; Apple's terms for the Android SDK | 4 to 6 months: the recogniser state machine, the suggester, the join view, the set recorder and the screens all again, plus the multi-matcher on Android audio | DJs without any Apple device, except that the catalogue step still touches one |
| **C. One shared core** | The DSP and scoring written once in Rust, called from Swift on Apple (MU and Beat This! Core ML stay Swift-side) and from the Windows builder and an Android app | none | shifts rather than adds: 2 to 3 weeks of build plumbing (xcframework, JNI), but the Swift port in the port plan becomes a Rust port | Numbers identical across platforms by construction; one benchmark run proves all three |

Option C is the architectural choice behind A and B. If Deckie will ever ship off Apple, the port plan's "plain
Swift over arrays" blocks are better written once in Rust now than twice later; what stays Swift is the Music
Understanding wrapper, Core ML, ShazamKit and the UI. This narrows D11's "one Swift engine" to "one engine, Swift
on the outside, Rust inside" and is the one decision that should be made before stage 2 starts [inf].

**What the crate file needs to be engine-agnostic.** Today it carries `analysis.engine` as one string
("mu27.0+deckie1"), `analysis.level` (1 full, 2 fallback, 3 none), `grid.source` ("mu" or "beatthis") and
`key.votes{mu, hpcp}`; the rule is "a reader re-analyses when its engine is newer and it has the audio". With two
engine families "newer" has no meaning. Add:

- A structured engine record: `engine.family` (`apple-mu`, `deckie-core`), `engine.version`, `engine.platform`,
  `engine.models[]` (name, version, weights hash) and `decoder` (name, version), so a reader knows what produced a
  record and a bug in one model can be found later.
- A `fidelity` integer per engine build, set from the benchmark (a build earns it by passing the stage 1 pass
  marks), replacing "newer": a device re-analyses only when its fidelity is higher or the record's level is lower.
- Per-block provenance where it is missing: `key.source`, `vocal.source`, `structure.source`, `loudness.source`,
  each with its own confidence, because a Windows record may have Beat This! beats (fidelity equal to Apple) and a
  key-lite key (lower). The booth already shows "which level it is on"; it would show it per block only in the
  track detail, not in the booth view [inf].
- Normalised meanings at the engine boundary, not in the scorer: every 0-to-1 series (vocal, drum, bass, other) is
  written on one agreed scale (the listening-set calibration), every confidence as "share of the benchmark where
  this value was right", so `score.py`'s thresholds (vocal 0.5, the 0.6 gate) mean the same thing whichever engine
  wrote the track. Mixed crates (some tracks from a Mac, some from a PC) then score consistently.
- An explicit `features_present[]` list, so a reader never infers a feature from the level number.

**How two engines' numbers are kept comparable.** The 373-track benchmark in `mixer/` is the yardstick and
`bench_mu.py` already defines the metrics: beat and downbeat F at 70 ms, BPM within 2 percent, key exact and
neighbour split by the lab's confidence, per-bar vocal correlation, boundary precision and recall within one bar,
loudness deltas, seconds per track. The pass marks proposed in the port plan apply to both engines: beat F at or
above 0.90, downbeat 0.80, key exact plus neighbour 85 percent where the lab is sure, vocal r 0.6, boundary recall
0.6, loudness within 0.5 LU. Two additions: an engine-to-engine table (Apple against Rust on the same tracks, the
same metrics), and a picks-level test, because the DJ sees picks, not features: the top-8 "mixes into" lists per
track from the two engines should overlap on at least, say, 6 of 8 and never disagree on a transition move for a
pair both rank in the top 3 [inf]. The parity fixtures in the port plan (inject the lab's beats, require the grid
BPM within 0.01 percent, identical window bars and Camelot codes) run against both ports.

## 6. What DJs on Windows actually run, and what a crate-builder could import

- **Shares.** The 2026 Global DJ Census (Digital DJ Tips, "over 22,000 entries from DJs worldwide"): rekordbox 34
  percent, Serato 27, VirtualDJ nearly 17; nearly 60 percent own Pioneer DJ or AlphaTheta hardware. No
  operating-system split is published; rekordbox, Serato and VirtualDJ run on Windows and Mac, Mixxx on Windows, Mac
  and Linux (competitive analysis, S1 to S6). Inference: the Windows DJ is common and is already inside one of
  these three; the ones Deckie serves best (gear that does not know the library, burned CDs) are the least likely
  to have a tidy rekordbox collection, which is exactly why "crate from discs" exists.
- **rekordbox XML.** Pioneer's own document ("XML file format for playlists sharing", version 1.0.0): a `TRACK`
  carries `Tonality`, `AverageBpm`, `TotalTime` and `Location` as a file URI; `TEMPO` is the beat grid with
  `Inizio` (start, seconds), `Bpm`, `Metro` (meter, e.g. 4/4) and `Battito` (beat number in the bar, 1 to 4), and
  "More than two TEMPO can exist for each track"; `POSITION_MARK` is a cue or loop with `Name`, `Type` (0 cue, 1
  fade-in, 2 fade-out, 3 load, 4 loop), `Start`, `End` and `Num` (hot cues 0 to 2, memory cue -1). Export: File >
  "Export Collection in xml format"; grids land in the file only when Preferences > Advanced > rekordbox xml is set
  to "BPM change points". Import goes the other way through the "rekordbox xml" bridge in the browser tree. This is
  precisely the marker shape P12 chose, so the importer is a mapping, not a model: `TEMPO` to tempo segments,
  `POSITION_MARK` to chosen start points and saved windows, `Tonality` as a third key vote.
- **Serato.** Grids and cues live in the audio files' own tags ("Serato BeatGrid", "Serato Markers2", "Serato
  Autotags" with BPM and gain), reverse-engineered and documented by the serato-tags project (documentation CC
  BY-SA 4.0, scripts MIT); Mixxx 2.3 imports Serato cues from them. A reader of our own reads the DJ's own files,
  which the crate-builder opens anyway [inf].
- **VirtualDJ.** `database.xml`: a `Song` with `Scan` (`Bpm` stored as seconds per beat, "Bpm = 1 / Scan->Bpm *
  60", `Key`) and `Poi` points (cue, beatgrid and automix types in VirtualDJ's forum examples). Readable, less
  documented.
- **Mixxx.** A SQLite library with beats as protobuf messages (`BeatGrid{bpm, first_beat}`, `BeatMap{repeated
  Beat frame_position}`); the app is GPL "version 2 of the License, or (at your option) any later version", so read
  its file with our own code, never link it [inf, not legal advice].
- **A CDJ USB stick** (spec way 4): `export.pdb` plus per-track ANLZ files holding grids, cues and waveforms; "No
  official public documentation of the file format exists"; parsers exist in Java (crate-digger, EPL-2.0) and Rust
  (rekordcrate, MPL-2.0, "under heavy development"). A lower-priority importer behind the XML.

Does import matter more than a second engine? For the rekordbox DJ, yes: the grid is the block DJs fight hardest
over (competitive analysis, S28), and importing theirs respects it, as D13 asks. But the XML carries nothing Deckie
sells: no key segments, mix windows, vocal activity, loudness or signatures. So the import removes the hardest
block from the second engine (beats and grid) and leaves the cheap ones (loudness, windows, lattice, vocal) and the
weak one (key). A Windows builder that imports XML and runs a light engine is a smaller project than a full second
engine; the Beat This! port covers the DJs without a grid.

## 7. Recommendation, build order and the honest cost

1. **Now, free:** write the engine-agnostic crate fields of section 5 into crate v1 before stage 2 code exists
   (structured engine record, fidelity, per-block source, normalised scales, `features_present`). Decide option C
   (Rust inside, Swift outside) or explicitly reject it; it is cheapest before the Swift port starts.
2. **Stage 3, small:** make the iPad a crate-builder: "build from this drive" over a USB stick, overnight batch,
   signatures generated on the iPad. This answers "many DJs do not use Macs" for every DJ who has the iPad, at the
   cost of 2 to 3 weeks of UI and a measured speed (open question 2) [inf].
3. **After the DJ trials:** Desk Lite for Windows and Linux. Order inside it: rekordbox XML import and the crate
   writer (2 to 3 weeks), decoders and loudness (1 week), Beat This! on ONNX Runtime with the grid fit (3 to 4
   weeks), lattice, windows, flags, style vector (3 weeks), key-lite plus XML tonality (2 weeks), EfficientAT or
   YAMNet vocal (2 to 3 weeks), benchmark to the pass marks (2 weeks), packaging (4 weeks). About 4 to 5 months
   [inf]. Recognition stays on the iPad.
4. **Only on demand:** an Android booth, 4 to 6 months [inf], after Apple's written terms for the Android SDK and a
   measured multi-session test on an Android tablet. The catalogue comes from a Mac or iPad.
5. **Not now:** an own pitch-robust fingerprint (3 to 6 months, uncertain) and a vocal stem on CPU.

The honest cost: 8 to 12 engineer-months for the full non-Apple story on top of the Apple product; a key block that
is measurably weaker (75 against 83 percent) unless a permissive key detector appears or we train one; and a
recognition step that touches an Apple device until a fingerprint of our own exists. The upside: beats, grid,
loudness, structure and windows off Apple are at parity or better against the yardstick, because the yardstick was
built with the same open tools.

## 8. Open questions

1. Apple's terms for the ShazamKit Android SDK: is a paid Program membership required to download it, which
   agreement governs a commercial Android app, and may the AAR be bundled. Ask Apple Developer Support in writing.
2. iPad as crate-builder: seconds per track and per signature on a real iPad from a USB stick, thermal behaviour
   over a 2,000-track overnight run.
3. Android: can several `StreamingSession`s run at once on one tablet, at what CPU, and does a Mac-built catalogue
   with Deckie's metadata match at the same rate as on iOS (the 2021 duration-limit mismatch).
4. Key off Apple: can key-lite reach 83 percent with a better chroma (CQT, tuning estimation) or a small trained
   head on the listening set, and what does the XML `Tonality` vote add for rekordbox DJs.
5. Vocal off Apple: EfficientAT and YAMNet on the 40-track listening set, against Apple's series.
6. Option C: is a Rust core acceptable to the Apple build (xcframework size, App Store review, debugging), or does the
   DSP stay Swift with an FFT shim.
7. Decoder parity: the offset between Windows Media Foundation, Android MediaCodec, AVFoundation and dr_mp3 on the
   same MP3, measured on ten files, so bar 1 lands on the same sample.
8. How many of the trial DJs are Windows-only, and how many of those have an iPad; the census does not say.

## 9. Sources

Apple, ShazamKit: Android documentation https://developer.apple.com/shazamkit/android/ ; `ShazamKit` object
https://developer.apple.com/shazamkit/android/shazamkit/com.shazam.shazamkit/-shazam-kit/index.html ;
`CustomCatalog` https://developer.apple.com/shazamkit/android/shazamkit/com.shazam.shazamkit/-custom-catalog/index.html ;
`Signature` https://developer.apple.com/shazamkit/android/shazamkit/com.shazam.shazamkit/-signature/index.html ;
`MediaItem` https://developer.apple.com/shazamkit/android/shazamkit/com.shazam.shazamkit/-media-item/index.html ;
ShazamKit overview and Android download link https://developer.apple.com/shazamkit/ (the download redirects to an
Apple ID sign-in); forum threads https://developer.apple.com/forums/thread/694206 ,
https://developer.apple.com/forums/thread/699072 , https://developer.apple.com/forums/thread/691860 ,
https://developer.apple.com/forums/thread/779071 , https://developer.apple.com/forums/thread/703134 ; WWDC21 10045
https://developer.apple.com/videos/play/wwdc2021/10045/ ; WWDC22 10028
https://developer.apple.com/videos/play/wwdc2022/10028/ ; the `shazam` CLI at `/usr/bin/shazam` on this Mac
(`shazam help signature`, `shazam help custom-catalog create`); PLA ShazamKit clause as shown at
https://www.lawinsider.com/clause/shazamkit .

Apple, Music Understanding: the SDK interface on this Mac,
`MacOSX27.0.sdk/System/Library/Frameworks/MusicUnderstanding.framework/Modules/MusicUnderstanding.swiftmodule/*.swiftinterface`;
WWDC26 253 https://developer.apple.com/videos/play/wwdc2026/253/ (transcript mirror
https://github.com/pixelfolio/WWDC26-Transcripts/blob/main/wwdc2026-253%20-%20Meet%20the%20Music%20Understanding%20framework.md ).

Swift off Apple: https://www.swift.org/install/windows/ ; https://www.swift.org/blog/swift-on-windows/ ;
swift-numerics announcement https://forums.swift.org/t/swift-numerics/30576 and licence
https://github.com/apple/swift-numerics/blob/main/LICENSE.txt ; KissFFT https://github.com/mborgerding/kissfft ;
PFFFT https://github.com/marton78/pffft ; rustfft https://crates.io/crates/rustfft ; ort https://crates.io/crates/ort .

Beats: Beat This! https://github.com/CPJKU/beat_this , licence issue https://github.com/CPJKU/beat_this/issues/21 ,
paper https://arxiv.org/abs/2407.21658 ; Rust port https://github.com/danigb/beat-this-rs and
https://crates.io/crates/beat-this ; C++ port https://github.com/mosynthkey/beat_this_cpp ; ONNX Runtime licence
https://github.com/microsoft/onnxruntime/blob/main/LICENSE and install matrix https://onnxruntime.ai/docs/install/ ;
BeatNet https://github.com/mjhydri/BeatNet (LICENSE: CC BY 4.0); TempoCNN https://github.com/hendriks73/tempo-cnn ;
madmom licence https://github.com/CPJKU/madmom/blob/main/LICENSE .

Key: `mixer/key_light.py` and `docs/architecture/stage1-results.md` section 1e; libKeyFinder
https://github.com/mixxxdj/libKeyFinder ; Key-CNN https://github.com/hendriks73/key-cnn ; Mixxx licence
https://github.com/mixxxdj/mixxx/blob/main/LICENSE .

Structure: MSAF https://github.com/urinieto/msaf (LICENSE.md, MIT; algorithms directory); all-in-one
https://github.com/mir-aidj/all-in-one .

Vocal: track J (`docs/research/j-vocal-tool.md`, section 6 licence quotes); demucs.cpp
https://github.com/sevagh/demucs.cpp and its `.github/PERFORMANCE.md`.

Loudness: libebur128 https://github.com/jiixyj/libebur128 ; ebur128 (Rust) https://github.com/sdroege/ebur128 ;
FFmpeg legal https://ffmpeg.org/legal.html .

Decoding: minimp3 https://github.com/lieff/minimp3 ; dr_libs https://github.com/mackron/dr_libs (LICENSE);
Symphonia https://github.com/pdeljanov/Symphonia ; Windows Media Foundation formats
https://learn.microsoft.com/en-us/windows/win32/medfound/supported-media-formats-in-media-foundation ; Android
formats https://developer.android.com/media/platform/supported-formats ; Via LA AAC
https://www.via-la.com/licensing-2/aac/ ; Fraunhofer mp3 https://www.iis.fraunhofer.de/en/ff/amm/consumer-electronics/mp3.html .

Recognition: Chromaprint https://github.com/acoustid/chromaprint (LICENSE.md); audfprint
https://github.com/dpwe/audfprint (LICENSE); Dejavu https://github.com/worldveil/dejavu (LICENSE.md); Qfp
https://www.cp.jku.at/research/papers/preprint_TASLP2509248.pdf ; US7627477B2
https://patents.google.com/patent/US7627477B2/en ; track H for Panako, Olaf, Qfp and the DJ-mix study.

DJ software and formats: 2026 census https://www.digitaldjtips.com/5-facts-about-djs-2026-census/ and
https://www.lexicondj.com/blog/best-dj-software ; rekordbox XML format
https://cdn.rekordbox.com/files/20200410160904/xml_format_list.pdf (mirrored at
https://pyrekordbox.readthedocs.io/en/latest/formats/xml.html ); the "BPM change points" and bridge steps
https://mixedinkey.com/workflows/export-cue-points-to-rekordbox/ ; Serato tags https://github.com/Holzhaus/serato-tags ;
Mixxx Serato import https://mixxx.org/news/2021-02-08-new-in-2-3-serato-support ; VirtualDJ database
https://virtualdj.com/wiki/VDJ_database.html ; Mixxx beats https://github.com/mixxxdj/mixxx/blob/main/src/proto/beats.proto ;
crate-digger https://github.com/Deep-Symmetry/crate-digger ; rekordcrate https://github.com/Holzhaus/rekordcrate ;
Qt LGPL obligations https://www.qt.io/licensing/open-source-lgpl-obligations .
