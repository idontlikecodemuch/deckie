# Deckie architecture overview

Dated Oct 26, 2026. The top-level map that spec v0.4 implies; the analysis detail is in `analysis-port-plan.md`
and the crate file schema in `docs/research/a-on-device-analysis.md` section 5. This document says what the parts
are, where each runs, and what crosses the boundaries. It changes when the spec changes.

## 1. The shape

Three apps built from two shared Swift packages, one file format between devices, and no server.

```
                 DeckieAnalysis (Swift package)          DeckieCore (Swift package)
                 Music Understanding + own DSP           model, crate I/O, identity + naming,
                 + Beat This! small (Core ML)            scoring, preferences + learning,
                 -> TrackAnalysis                        recognition session, set log, export

   Desk (macOS app)            Booth (iPad, universal iOS app)      Pocket (iPhone, same binary)
   import folder -> crate      listen, picks, join, pin, save pair   recognise, record, tracklist
   naming editor, exports      one-tap tuning, How you mix           quick picks, crate viewer
   bulk analysis, signatures   set recording + export                 

                        <name>.deckiecrate  (package folder; iCloud Drive, AirDrop, Files)
                        analysis + names + prefs + history + optional signatures; never audio

   Lab (Python, mixer/): ground truth for the 373 tracks, benchmarks, model experiments. Never ships.
```

## 2. Parts

**DeckieAnalysis.** Input: an audio file URL. Output: a `TrackAnalysis` value that becomes one track record in
`crate.json` plus its per-bar sidecar. Inside: Apple's Music Understanding session (beats, bars, BPM, key over
time, sections, instrument activity, loudness), then our own DSP ported from the Python: constant-grid fit and
confidence, start and end tempo with the trust rule, the 8-bar lattice, mix-in and mix-out windows, fade-out,
first and last sound, low and high band energy per bar, onset pattern, Camelot mapping, flags. Beat This! small as
a Core ML second opinion when the grid fit is doubtful; an HPCP key vote as the second key opinion. Fallback levels
(spec 5.1) are chosen here by what the OS offers. Runs on power, watches thermal state, reports progress, cancels.

**DeckieCore.** Everything that is not analysis and not UI:
- The model: `Track`, `Pair`, `Crate`, `Profile`, the per-bar series.
- Crate I/O: read and write the package, merge rules (newest analysis wins, prefs by timestamp, history unioned),
  schema versioning, iCloud conflict resolution through file coordination.
- Identity and naming: content hash, the file-name grammar (work plus version), in-crate clustering of versions,
  the editor's model (edits keyed by content hash, undo history), optional suggestion sources behind one switch.
- Scoring: the directed A-into-B score ported from `score.py`, with the weights and gates as a `Profile` reads them.
- Preferences and learning: the twelve dimensions, the event weights (saved pair first), the slow update rules,
  the slider state, the "what changed" log.
- Recognition: catalogue build from signatures, the ShazamKit session, and the state machine that is today's
  `Recognizer.swift` (position, pitch from skew or drift, confidence, pauses, hard cut versus blend switch).
- Set log and export: the recording tap, the JSON log, CUE and Mixcloud text.

**Desk, Booth, Pocket.** Thin SwiftUI layers over DeckieCore. Booth is the existing Listen, Picks, CDs and Mix map
screens, re-pointed at a crate file instead of bundled data. Pocket is the recording and tracklist subset with quick
picks. Desk is new: import, naming, bulk analysis, signatures, exports. One universal iOS binary; a native macOS
target rather than "Designed for iPad", because of the ShazamKit validation problem noted in track A.

**The crate file.** The only thing that crosses devices. Package folder: manifest, `crate.json`, per-bar binaries,
style vectors, `prefs.json`, per-device history logs, optional signatures, and a local-only catalogue build.
About 10 KB per track without signatures, or about 15 KB with the join-waveform sidecar the port plan proposes
(`waves/<id>.bin`, so the join view needs no audio on the iPad). The port plan also adds `analysis.level`, the
fallback level a track was analysed at, so a capable device knows what to redo. No absolute paths, no audio.

**The lab.** The Python stack in `mixer/` with its venv, kept as ground truth and for experiments. The benchmark
harness (stage 1) compares DeckieAnalysis output to `mixer/features/<id>.json` with fixed metrics. Nothing from the
lab is linked into the apps.

## 3. What crosses which boundary

| From | To | What | Never |
|---|---|---|---|
| Audio file | DeckieAnalysis | samples, read once | the file is written |
| DeckieAnalysis | crate file | one track record, one sidecar, optional signature | audio, raw beat arrays, embeddings over a few hundred bytes |
| Desk | Booth or Pocket | the crate file, by iCloud Drive, AirDrop or Files | a Deckie server, an account |
| Booth | crate file | play log, saved pairs, pins, slider moves | anything to another device directly |
| Microphone | Recognition | a live buffer into the ShazamKit session | a recording of the room leaving the device (the set recording is the user's file) |
| Optional lookups | naming editor | a suggestion with a source, on request | an automatic change, an upload of audio, a stored copy of terms-restricted data |

## 4. What exists today and what is new

Exists in Swift (`deck-app/`): the recognition state machine, the suggester, the join view, the set recorder, the
screens. Exists in Python (`mixer/`): every analysis block and the scoring. New: DeckieAnalysis (the port plus the
Music Understanding wrapper), crate I/O, identity and naming, preferences and learning, Desk, Pocket, exports.
The porting order follows the stages: benchmark first, then analysis on the Mac writing a crate, then the iPad
reading it, then analysis on device.

## 5. Where crates get built, by platform (Oct 28)

| Platform | Builds a crate from | Engine | Recognition signatures | Status |
|---|---|---|---|---|
| Mac (Desk) | files, folders, discs, albums, rekordbox XML | DeckieAnalysis on Apple's framework | made on the Mac | primary |
| iPad (Booth) | a USB stick or Files, overnight on power | the same engine | made on the iPad | planned, no engine work, UI only |
| Windows, Linux (Desk Lite) | files, folders, rekordbox XML | a second engine (Rust: Beat This! on ONNX Runtime, our DSP, our key estimator, libebur128, a permissive vocal tagger) | still made on an Apple device | after the trials; see `pc-linux-track.md` |
| Android (Booth) | consumes a crate | none | loads an Apple-built catalogue (ShazamKit for Android) | only on demand |

## 6. Decisions this map depends on

D11 (native engine with fallbacks) and D12 (vocabulary and the chain) are decided. P9 (profiles) decides whether
`Profile` is one or many per crate; the map assumes many with one active. P10 (self-contained identity) decides the
naming module's default; the map assumes it. Pricing and bundle id do not touch the map.
