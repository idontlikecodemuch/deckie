# Track A: on-device and on-computer analysis, and the crate file

Dated Oct 26, 2026. Research report for spec v0.2 (`docs/product/02-research-plan.md`, Track A). Facts are cited;
anything marked *[inference]* is my reading, and nothing here is legal advice. Sprint numbers come from the
sprint session (347 tracks x 3 pitch variants = 1,041 signatures, 47 MB; signatures generated only on the Mac).

## 1. Summary (one page)

**The finding that changes the plan.** Apple shipped a *Music Understanding* framework with iOS, iPadOS and macOS
27 on Sept 14, 2026 (announced WWDC26 session 253). One call on an `AVAsset` returns, entirely on device and
offline: beats, bar starts and BPM; key (tonic + major/minor) over time ranges; sections, segments and phrases;
per-instrument activity 0-1 over time for `vocal`, `drum`, `bass`, `other`; BS.1770 loudness (integrated,
short-term, momentary at 100 ms, peak); and a "pace" curve. Results are `Codable`. It is an Apple SDK, so there
is no model licence to clear. That covers five of the six Python analysers (beats, key, structure, vocal timeline,
loudness) and adds stem-level activity the Python stack only got from Demucs.

**Recommendation for the split.** Build one Swift analysis engine (a package, working name `DeckieAnalysis`) and
run the *same* engine on iPhone, iPad and Mac:

- Music Understanding for beats/bars/BPM, key, structure, instrument activity and loudness.
- Our own DSP, ported from `mixer/analyze.py` and `local_tempo.py` with Accelerate: constant-grid fit and
  confidence, start/end tempo, 8-bar lattice, mix-in/out windows, fade-out, first/last sound, per-bar low/high
  band energy, onset pattern, Camelot mapping, flags. All of this is numpy today and ports one-to-one.
- A second opinion where the Python stack had one: Beat This! "small" (2M parameters, MIT, F1 within 0.3 (beats)
  and 1.1 (downbeats) points of the full model) as a Core ML model when the grid fit is doubtful, and an own
  HPCP key detector as the second key vote, so the existing confidence rules keep working.
- The Mac is not a different analyser; it is the same engine where the audio usually lives, with the heavy
  optional extras that need memory and minutes: Demucs stems (MIT; Swift MLX port, 112x realtime on an M4 Max),
  batch runs over a whole library, signature generation at scale.

The Python stack stays as the lab: ground truth and benchmark for the 373 analysed tracks, and the place to try
new models. It is not shipped: madmom's models are CC BY-NC-SA ("contact Gerhard Widmer" for commercial use),
Essentia is AGPLv3 "for non-commercial applications" and its models are NonCommercial (BY-NC-SA on the models
page, BY-NC-ND on the licensing page), and packaging torch + TensorFlow for non-developers is 0.5-1.5 GB with
notarisation pain. Section 4 has the detail.

**Three biggest risks.**

1. **OS 27 floor.** The engine needs iOS/iPadOS/macOS 27. iPadOS 27 drops some 2018-2022 iPads (second-hand
   list in section 6; verify on Apple's page). Mitigation is built in: the crate file lets any OS 27 device
   (including the Mac) analyse and any device consume. A fallback engine for older iPads (Beat This! small +
   own DSP + SoundAnalysis "singing") exists on paper but should only be built if TestFlight DJs need it.
2. **Unmeasured quality and cost.** Music Understanding publishes no accuracy, no confidence values, no timings,
   and its sections carry no labels. First experiment (section 7): run it over the 373 tracks and score it
   against the Python features (beat/downbeat F-measure, key agreement, vocal-timeline correlation, section
   boundaries). This Mac is on macOS 26, so it needs macOS 27 or an iOS 27 device.
3. **ShazamKit on device is untested.** Per-track signature cost on an iPhone, memory at thousands of
   signatures, and pitch tolerance beyond o/r-4/r+4 were never measured. Apple documents no limits but says
   matches fail "if the frequency skew is too large" and that under 5 percent "should be safe", which suggests
   the +/-4 variants may be partly redundant. Measure before designing around them.

A fourth, legal rather than technical: Chris's 373-track crate was analysed with NonCommercial models. Regenerate
it with the shipped engine before it becomes a fixture in any TestFlight build *[inference; not legal advice]*.

**Crate file decision.** A package directory (`<name>.deckiecrate`), not a single JSON: a small `crate.json`
core (about 7 KB per track uncompressed, 3 KB gzipped, no raw beat arrays, no 1280-d embedding), binary sidecars
for per-bar series, append-only per-device history logs, and an *optional* `signatures/` store. Signatures travel
when the receiving device has no audio to regenerate from (the iPad case today); they are irreversible by
Apple's statement, so carrying them does not breach D3. Budget: ~10 KB per track without signatures, ~145 KB with
three variants. Moves by iCloud Drive, AirDrop and Files; no server. Schema in section 5.

## 2. Per-feature feasibility on iOS

Times are per 3-4 minute track. "Python" times are the sprint's measured M-series numbers from `mixer/README.md`.
On-device times for Apple's framework are unknown (nothing published); the estimates are *[inference]* and the
first thing to measure.

| Feature | Runs on iOS? | Library | Quality vs Python stack | s/track (device) | Licence | Confidence |
|---|---|---|---|---|---|---|
| Decode | Yes | AVAudioFile / AVAsset (MP3, AAC, ALAC, FLAC, WAV); DRM content refused (`hasProtectedContent`) | Same samples on all devices if we decode once and cache nothing but features | < 1 | Apple | High |
| Beats, downbeats, BPM | Yes, OS 27 | Music Understanding `RhythmResult` (beats, bars, BPM; BPM nil under two beats) | Unknown; no accuracy published. Second opinion: Beat This! small, 2M params, GTZAN F1 88.8 beats / 77.2 downbeats vs 89.1 / 78.3 for the 20M model (Python used the 20M model on MPS, 0.8 s) | 2-10 est. | Apple SDK; Beat This! MIT (code and weights) | Medium |
| Grid fit, confidence, start/end tempo | Yes | Own port of the IRLS grid fit and `local_tempo.py` regressions (Accelerate) | Identical algorithm | < 0.1 | Ours | High |
| Key + Camelot | Yes, OS 27 | `KeyResult`: 17 enharmonic tonics, major/minor, time ranges, no confidence. Second vote: own HPCP + published key profiles (Accelerate; no library needed) | Unknown. Python's edma + bgate + madmom CNN was "60-80 percent at best on vocal pop"; keep key a soft term either way | ~1 (own vote) | Apple SDK; ours | Medium |
| Vocal timeline | Yes, OS 27 | `InstrumentActivityResult.activity[.vocal]`: 0-1 over time -> per-bar mean | Unknown. The EffNet head read 0.85-1.0 on most pop bars; Apple's is stem-style (vocal/drum/bass/other) so plausibly sharper *[inference]*. Fallback on < OS 27: SoundAnalysis built-in classifier (`singing`, 303 labels, 0.5-15 s windows, iOS 15+) or YAMNet in Core ML (Apache-2.0, 3.7M params) | in the same call | Apple SDK | Medium |
| Drum / bass / other activity | Yes, OS 27 | same result | New: Python had this only via Demucs (17.7 s MPS). Enables "bass-swap safe" bars and drums-only teasers | in the same call | Apple SDK | Medium |
| Structure, phrases, sections | Yes, OS 27 | `StructureResult`: sections, segments, phrases as time ranges, no labels; own 8-bar lattice from bars; own energy labels (intro/main/break/outro) | Python's Foote novelty had phrase confidence 0.2-0.3 on vocal pop; a learned segmenter is likely better *[inference]*. Keep the Foote port as the fallback and as a confidence proxy | in the same call | Apple SDK; ours | Medium |
| Loudness (integrated, LRA, per-bar LUFS) | Yes, OS 27 | `LoudnessResult`: BS.1770 integrated, short-term (3 s) and momentary (400 ms) every 100 ms, peak. Per-bar LUFS from the momentary series; LRA from short-term | Same standard as pyloudnorm. Check whether `peak` is true peak; else own 4x oversample | in the same call | Apple SDK | High |
| Per-bar low/high band, onset density, onset pattern | Yes | Own LR4 biquads and spectral flux with vDSP | Identical | < 0.5 | Ours | High |
| Mix windows, fade-out, first/last sound, flags | Yes | Own port | Identical | ~0 | Ours | High |
| Style embedding | Yes, with a model we ship | No Apple API. Options: (a) v1: hand-crafted style vector from the above (tempo, pace, key, activity means, band balance, onset pattern); (b) YAMNet 1024-d (Apache-2.0, 16 kHz, 0.96 s patches, Keras 2 -> coremltools); (c) PANNs MobileNetV1 (code MIT, weights CC BY 4.0, 23.6 MB); (d) CLAP: code CC0, weights licence unstated, skip | EffNet 1280-d is NonCommercial and not shippable. Timbre is 5-12 percent of the score, so a weaker vector costs little | 1-2 est. | Apache / CC BY | Medium |
| Stems (Demucs) | Mac first; iPad Pro possible | demucs-mlx-swift (MIT, macOS 14 / iOS 17+, M4 Max 112x realtime, 160 MB weights, 4.7 GB peak on Mac with batching; iOS batch 1, memory-checked) or htdemucs-coreml (MIT, 200 MB fp16, `cpuAndGPU` only) | Equal to Python Demucs (same weights) | 2-20 on M-series est. | MIT | Medium |
| ShazamKit signatures, 3 variants | Yes, iOS 15+ | `SHSignatureGenerator` (append buffers or `generateSignature(from: AVAsset)`); variants via offline `AVAudioEngine` as in `catalogtool` | Identical | Mac ~1 per variant; device unknown | Apple | Low (unmeasured) |

Battery and thermal *[inference]*: the per-track total on device is likely 10-40 s, so 300 tracks is one to three
hours of sustained CPU/GPU/ANE work. No controlled wattage measurements exist for sustained Core ML on iPhone (the
numbers in circulation are blog estimates). Design for it rather than estimate it: require power for bulk analysis,
watch `ProcessInfo.thermalState` and pause at `.serious`, and run bulk work as a `BGContinuedProcessingTask`
(iOS 26+): it must be started by the user, shows system progress UI, continues when the app is backgrounded, can
use the GPU with an entitlement, has no published time limit, and is expired if it stops reporting progress; the
system also cancels it if the user swipes the app away. Idle-time re-analysis fits `BGProcessingTask` with
`requiresExternalPower`. Forum reports in late 2025 describe the API expiring tasks when the screen is fully
locked; test it. No analysis has to run during a gig.

## 3. ShazamKit findings

What Apple documents (ShazamKit, iOS 15+/macOS 12+):

- `SHSignatureGenerator` builds reference and query signatures from PCM buffers or an `AVAsset`.
  `SHCustomCatalog.addReferenceSignature(_:representing:)` attaches media items; `write(to:)` is deprecated in
  favour of `dataRepresentation`; `add(from:)` merges saved `.shazamcatalog` files at runtime
  (`UTType.shazamCustomCatalog`).
- **No documented limit** on signature count, signature duration or catalogue size. Apple's guidance (WWDC22):
  one signature covering the whole track, not many short ones; larger catalogues mean more download and memory;
  keep catalogues "tightly focused" and merge them at runtime. A forum post mentions a 50,000-track custom
  catalogue (anecdote). The sprint hit no limit at 1,041 signatures.
- `frequencySkew` is a ratio (0 = same frequency; 0.05 means the query plays at 105 percent) and "no match returns
  if the frequency skew is too large". WWDC22: "keeping the skew to less than 5 percent should be safe".
  `frequencySkewRanges` can restrict a media item to a skew band. Signatures are irreversible: the audio cannot be
  reconstructed from one (WWDC23).
- macOS 13+ ships a `shazam` command-line tool (signature, custom catalog create, update, display).

Sprint facts: 347 tracks x {o, r-4, r+4} = 1,041 signatures, 47 MB, so **about 45 KB per signature** (roughly
13 KB per minute of audio *[inference from average track length]*). About 1 s per signature on the Mac with eight
processes. On-device generation was never tried, matching beyond o/r-4/r+4 was never benchmarked, and loud-room
recognition was never measured.

Implications *[inference]*:

- Vinyl-style pitch (master tempo off) is a frequency skew, which ShazamKit measures directly. If Apple's 5
  percent holds, `o` alone covers about +/-5 percent and `o, r-4, r+4` about +/-9 percent, which matches the app's
  16 percent cutoff only with `r+/-8` added. Tempo-only pitch (master tempo on) is a time stretch, not a skew;
  its tolerance is unknown and the app currently infers it from position drift. Benchmark first:
  `catalogtool bench --render o,r+4,r+8,r+12,t+4,t+8` (the t-variant signatures exist in the original machine's
  cache).
- Cost on device: unknown; the generator is CPU work, so expect single-digit seconds per variant on a recent
  iPhone. Measure on an A15-class phone and an M-series iPad with `generateSignature(from:)` on one track.
- Memory: unknown; plan catalogues per crate (a few hundred tracks each) and load only the gig's crates.
- Background: generation belongs in the same `BGContinuedProcessingTask` as analysis.
- "Designed for iPad" on Apple silicon Macs: an App Store Connect validation error (ITMS-90863, missing
  `libswiftShazamKit.dylib`) blocked such builds in 2025, cleared with Xcode 16.3, then returned. A native macOS
  target is the safer Mac path.

## 4. Mac packaging options

| Option | What ships | Size | Licence position | Verdict |
|---|---|---|---|---|
| PyInstaller bundle of the Python stack | Python + torch + TensorFlow + Essentia + madmom + models | community reports 0.5-1.5 GB; one-file `.app` deprecated in 6.13 and blocked in 7.0; hardened runtime and nested-dylib signing are recurring failures | PyInstaller is GPL-2 with an exception for built apps. The payload is the problem: madmom models CC BY-NC-SA, Essentia AGPLv3 (non-commercial) with NonCommercial models | Internal tool only |
| py2app | same payload | py2app 0.29.10 supports Python 3.13/3.14; universal2 "highly experimental"; codesign retries are "a workaround" | same payload problem | Internal tool only |
| Swift port = the shared `DeckieAnalysis` package in a macOS app | Music Understanding + own DSP + Beat This! small (Core ML, ~4 MB fp16) + optional YAMNet (~15 MB) + optional Demucs weights (160 MB, downloaded on demand) | tens of MB | Apple SDK, MIT, Apache-2.0 | **Do this** |

The port is mostly glue once Music Understanding does the model work: the numpy parts of `analyze.py` and
`local_tempo.py` are a few hundred lines of vDSP. Conversion routes for Beat This!: coremltools from the PyTorch
checkpoint (the mel front end, 22.05 kHz, n_fft 1024, hop 441, 128 mels 30-11,000 Hz, `log1p(1000x)`, 1500-frame
windows with 6-frame borders, is computed by the host, which we do in vDSP), or the existing MIT ONNX export
(190 MB fp32 for the full model) through ONNX Runtime's CoreML execution provider (MIT, iOS 13+). Note Apple also
introduced Core AI at WWDC26 as the successor to Core ML for neural networks; Core ML keeps running converted
models, and a community Core AI conversion of Beat This! for macOS 27 already exists.

Proprietary licences for madmom (JKU) and the Essentia models (UPF) are offered on request. They would let the
Python results ship, but they are a cost, a negotiation and a dependency, and they do not fix packaging. Keep the
Python stack as the lab.

## 5. Crate file v1

A package directory, `<Name>.deckiecrate`, declared as an exported UTType conforming to `com.apple.package` and
`public.content` (so Finder, Files and AirDrop treat it as one document), with `LSSupportsOpeningDocumentsInPlace`
for open-in-place from Files.

```
Chris.deckiecrate/
  manifest.json          schema, crate id, name, created, devices seen, engine versions used
  crate.json             tracks: identification + analysis summary (one record per track, see below)
  bars/<trackid>.bin     per-bar series, float16: lufs, low_db, high_db, onset_density, vocal, drum, bass, other
  style/<trackid>.bin    style vector, float16 (v1: 32-64 d hand-crafted; later YAMNet 1024 d)
  prefs.json             sliders and learned weights (last writer wins by updated_at)
  history/<device>.jsonl append-only play log per device (union on merge; never rewritten by another device)
  signatures/<trackid>_<variant>.shazamsignature   optional, immutable, ~45 KB each
  catalog/<crate>.shazamcatalog                    derived from signatures/, rebuilt locally, never synced
```

Per-track record in `crate.json` (compact JSON; the current `features/<id>.json` layout, trimmed):

```
{ "id": "c546b63944", "schema": 1,
  "file": {"name": "...", "rel": "CD1/3 - 120ish/07 ...mp3", "bytes": 9123456, "sha1_head": "...", "duration_s": 224.0},
  "ident": {"title": "...", "artist": "...", "version": "...", "source": "tag|filename|user|mb|discogs", "mbid": null,
            "disc": "CD1", "folder": 3, "track": 7, "cut_key": "...", "is_longest": true, "era": 1999, "kind": "remix"},
  "analysis": {"engine": "mu27.0+deckie1", "analysed_at": "2026-11-02T...", "device": "mac-...", "secs": 18.4},
  "grid": {"bpm": 125.0, "first_downbeat_s": 0.04, "n_bars": 115, "fit_mad_ms": 9.1, "confidence": 0.93,
           "source": "mu|beatthis", "bpm_in": 125.0, "bpm_out": 124.8, "in_trusted": true, "out_trusted": true},
  "key": {"camelot": "7A", "key": "D", "scale": "minor", "confidence": 0.65, "votes": {"mu": "7A", "hpcp": "7A"},
          "changes": [[0, 95, "7A"]]},
  "phrase": {"lattice_phase_bar": 1, "confidence": 0.8, "boundaries_bars": [1, 9, 25, 41, 73, 97, 113]},
  "sections": [{"start_bar": 1, "end_bar": 9, "label": "intro", "energy": "low"}],
  "mix_in": {"start_bar": 1, "end_bar": 17, "vocal_free_bars": 16}, "mix_out": {"start_bar": 81, "end_bar": 97, "vocal_free_bars": 8},
  "ends": {"first_sound_s": 0.0, "last_sound_s": 223.1, "fade_out": false, "steady_in_bar": 1, "steady_out_bar": 112},
  "loudness": {"integrated_lufs": -8.2, "lra": 5.1, "true_peak_db": -0.1},
  "vocal": {"mean": 0.62, "heavy": false}, "onset_pattern_16": [...16 floats...],
  "flags": ["short_outro"],
  "signatures": {"o": true, "r-4": true, "r+4": true} }
```

Sizes, measured on the 373 current feature files: median 28.8 KB each, of which the embedding is 9.3 KB and raw
beat arrays 7.9 KB. The record above without those is about 7.5 KB compact (2.9 KB gzipped); the per-bar sidecar is
8 series x 115 bars x 2 bytes = 1.8 KB; a 64-d style vector is 128 bytes. **Budget: ~10 KB per track without
signatures, ~145 KB with three variants.** A 2,000-track crate is 20 MB without signatures and 290 MB with; both
move by AirDrop or iCloud Drive, but the second is why signatures are optional and catalogues are per crate.

Rules:

- **Versioning.** `manifest.schema` is an integer; readers ignore unknown keys and refuse only a higher
  `min_reader`. Each track carries `analysis.engine`; a reader re-analyses when its engine is newer *and* it has
  the audio, otherwise it keeps what it has. Fields that were missing in older engines are simply absent.
- **Merging without a server.** Track records merge by newest `analysed_at`; `prefs.json` by `updated_at`;
  history files are per device and only appended, so two devices never write the same file. Use `UIDocument` /
  `NSFileCoordinator` and resolve iCloud conflicts by the same rules.
- **Signatures travel, optionally.** They are not audio and cannot be turned back into audio. Devices that have
  the audio regenerate; devices that do not (the iPad with no files) receive them. `catalog/` is a local build
  product, excluded from sync.
- **Transport.** iCloud Drive via the app's ubiquity container (`NSUbiquitousContainers`, visible in Files on
  all the user's devices, Apple handles sync and conflicts), AirDrop and the share sheet (the UTType makes the
  package shareable), Files on a USB drive. This routes analysis metadata through the user's own iCloud, never
  audio; say so in the privacy text. A local-network transfer (Multipeer) can come later.
- **No audio, no paths that leak.** Store a relative path plus size and a head hash to re-find files; never an
  absolute path from another machine.

## 6. iPhone and iPad: one binary, three roles

One universal iOS target (SwiftUI, size-class layouts) plus one macOS target from the same code, sharing
`DeckieCore` (model, scoring, crate I/O) and `DeckieAnalysis`. Roles are runtime modes, not binaries:
**Booth** (iPad, landscape: listen, picks, join view), **Pocket** (iPhone: recognise, record, tracklist, quick
picks, crate viewer) and **Desk** (Mac: crate building, bulk analysis, catalogue, exports). Every role can analyse
on OS 27; every role can read a crate. "Designed for iPad" on Apple silicon is a free Mac distribution path but
carries the ShazamKit validation bug noted above, so plan the native target.

OS floor: iOS 27 keeps every iPhone from the 11 onward. For iPadOS 27 a second-hand list says iPad Pro 11-inch
2nd gen / 12.9-inch 4th gen (2020) and later, iPad Air M2 and later, iPad 9th gen and later, iPad mini 6 and later;
that would drop iPad Air 3-5, iPad 6-8, mini 5 and the 2017-18 Pros. Verify on Apple's compatibility page before
choosing the deployment target. Devices below the floor can still run the booth role on a crate analysed elsewhere.

## 7. Open questions and the experiments that answer them

1. **Music Understanding against the Python features** (needs macOS 27 on this Mac or an iOS 27 device): run
   `analyze()` over the 373 tracks via the Music Understanding Lab sample or a 50-line CLI; score beats and bars
   against `detected_beats_s` / `downbeats_s` (F-measure at 70 ms), key against `key.camelot` with the Camelot
   neighbour tolerance, vocal activity per bar against `per_bar.vocal_prob` (correlation, and the 16 tracks with
   real instrumental intros), section boundaries against `boundaries_bars`, loudness against pyloudnorm. Record
   seconds per track on the Mac, an M-series iPad and an iPhone, plugged in, with `thermalState` logged.
2. **Signature cost on device**: time `generateSignature(from:)` and the three-variant offline render on the
   same devices; load catalogues of 1k, 3k and 6k signatures and watch memory.
3. **Pitch tolerance**: `catalogtool bench` at r+/-4, +/-8, +/-12 and t+/-4, +/-8; decide the variant set from
   data, not from the 5 percent figure.
4. **Beat This! small on Core ML**: convert, check parity on 20 tracks against PyTorch, measure ANE vs GPU time.
5. **Loud-room recognition**: measured match rate at club level with a phone and an iPad, before Stage 4.
6. **Whether `LoudnessResult.peak` is true peak**, and whether key ranges are stable enough to feed the
   confidence rule without a second vote.
7. **Legal check** on reusing NonCommercial-model outputs during development, and on the privacy wording for
   iCloud Drive sync of analysis metadata.
8. **Older iPads**: do TestFlight DJs have them? Decides whether the fallback engine is worth building.

## 8. Sources

Apple, Music Understanding framework (27.0, all platforms): https://developer.apple.com/documentation/musicunderstanding ;
`RhythmResult`, `KeyResult`, `StructureResult`, `InstrumentActivityResult` and its `Instrument` keys
(`vocal`, `drum`, `bass`, `other`), `MusicUnderstandingSession`, `MusicUnderstandingError` pages under the same
root. WWDC26 session 253 "Meet the Music Understanding framework": https://developer.apple.com/videos/play/wwdc2026/253/ .
Second sources: https://blakecrosley.com/blog/music-understanding-framework-ios-27 ;
https://www.theswift.dev/posts/build-music-aware-apps-with-music-understanding/ ;
https://www.synthtopia.com/content/2026/06/23/apple-intros-music-understanding-framework-at-wwdc/ ;
wrapper package https://github.com/arraypress/swift-music-analysis .

OS 27 release and compatibility: https://www.macrumors.com/2026/09/09/apple-announces-ios-27-release-date/ ;
https://gadgets.beebom.com/news/apple-ipados-27-macos-27-watchos-27-stable-update-release-date-announced .

Beat This!: paper https://arxiv.org/abs/2407.21658 (HTML: https://arxiv.org/html/2407.21658 ); code and MIT
weights https://github.com/CPJKU/beat_this (preprocessing.py, inference.py); ONNX export
https://huggingface.co/musetric/beat-this-onnx ; Core ML / Core AI conversions listed at
https://huggingface.co/schism-audio/beat-this-coreml and https://huggingface.co/arraypress/scribe-beat-this
(cards not readable from this session; treat as unverified).

Licences: madmom https://github.com/CPJKU/madmom ; Essentia models https://essentia.upf.edu/models.html and
licensing https://essentia.upf.edu/licensing_information.html ; CC BY-NC-SA 4.0 legal code
https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode.en ; PANNs code https://github.com/qiuqiangkong/audioset_tagging_cnn
and weights (CC BY 4.0) https://zenodo.org/records/3987831 ; YAMNet (Apache-2.0 repo)
https://github.com/tensorflow/models/blob/master/LICENSE and
https://github.com/tensorflow/models/blob/master/research/audioset/yamnet/README.md ; LAION CLAP
https://github.com/LAION-AI/CLAP ; PyInstaller https://pyinstaller.org/en/stable/license.html and changelog
https://pyinstaller.org/en/stable/CHANGES.html ; py2app changelog https://py2app.readthedocs.io/en/latest/changelog.html ;
ONNX Runtime https://github.com/microsoft/onnxruntime and CoreML EP
https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html .

Demucs ports: https://github.com/ssmall256/demucs-mlx-swift ; https://github.com/dexxdean/htdemucs-coreml .

ShazamKit: `SHCustomCatalog` https://developer.apple.com/documentation/shazamkit/shcustomcatalog ;
`SHSignatureGenerator` https://developer.apple.com/documentation/shazamkit/shsignaturegenerator ;
`SHSignature` https://developer.apple.com/documentation/shazamkit/shsignature ;
`frequencySkew` https://developer.apple.com/documentation/shazamkit/shmatchedmediaitem/frequencyskew ;
WWDC22 "Create custom catalogs at scale" https://developer.apple.com/videos/play/wwdc2022/10028/ ;
WWDC23 "Create a great ShazamKit experience" https://developer.apple.com/videos/play/wwdc2023/10051/ ;
Designed-for-iPad validation thread https://developer.apple.com/forums/thread/774191 ;
50k-track anecdote https://developer.apple.com/forums/thread/710225 .

Background and thermal: `BGContinuedProcessingTask` https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask ;
guide https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados ;
WWDC25 session 227 https://developer.apple.com/videos/play/wwdc2025/227/ ; `BGProcessingTask`
https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask and request options
https://developer.apple.com/documentation/backgroundtasks/bgprocessingtaskrequest ; lock-screen reports
https://developer.apple.com/forums/thread/796138 ; `ProcessInfo.ThermalState`
https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum .

SoundAnalysis and Create ML: https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest ;
built-in label list https://zenn.dev/shu223/articles/soundanalysis-builtin ;
https://developer.apple.com/documentation/createml/mlsoundclassifier .

Crate transport: iCloud documents https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment ;
UTType declarations https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app ;
iOS apps on Apple silicon https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos .

Core AI: https://www.infoq.com/news/2026/06/apple-core-ai-wwdc/ .

Local: `mixer/README.md`, `mixer/features/*.json` (373 files, sizes measured this session), `deck-app/README.md`,
`deck-app/tools/catalogtool/main.swift`, `docs/research.md` sections A and E; sprint figures from the coordinator.
