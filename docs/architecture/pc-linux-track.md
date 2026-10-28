# The PC and Linux track: charter for its own session

Written Oct 28, 2026 for the cloud session that owns this work. Christopher's direction: "create a cloud session that
can do all the investigation and building / testing for the PC / Linux version." The research that framed it is
`docs/research/l-non-apple.md` (track L); the product context is `docs/product/spec-condensed.md` (v0.7),
`docs/product/00-decisions.md` (D3, D11, D13, P16, P17) and `docs/architecture/overview.md` section 5.

> Language decision (Oct 28, track M, awaiting Christopher): the research recommends Swift everywhere for Deckie's
> own code, a plain Swift package with no Apple-only framework, calling C libraries directly on Windows and Linux
> (ONNX Runtime's C API, dr_mp3, the Windows AAC decoder, libebur128, PocketFFT); Rust is the runner-up. If
> accepted: `core/` becomes a Swift package, the C-interface step (6) goes away, the first task of this session is
> the two-week spike (grid fit, Camelot, score.py reproducing pairs.json on Linux and on a Windows CI runner), and
> the dependency policy in P16 applies. Everything below that says Rust reads as Swift until the charter is rewritten.

## Goal

A crate-builder for Windows and Linux, working name Desk Lite, that reads a DJ's music files and an optional rekordbox
XML export and writes the same `.deckiecrate` file the Apple apps read, with analysis good enough that the booth
picks are the same picks. Secondary goal, decided as P16: the DSP we own (beat grid fit, tempo and key segments, 8-bar
lattice, mix windows, Camelot mapping, the key estimator, the scoring) lives in one Rust core that the Apple apps can
call too, so there is one implementation of Deckie's own ideas.

## What this track owns

- `core/` (new, at the repo root): a Rust workspace. `deckie-core` (the DSP and scoring, pure Rust, no I/O);
  `deckie-crate` (reading and writing `.deckiecrate`); `deckie-engine-oss` (the second analysis engine: decoding,
  Beat This! on ONNX Runtime, the key estimator, libebur128 loudness, a permissive vocal tagger); `deckie-desk-lite`
  (a command-line crate-builder, the first face; a small GUI later); a C ABI for Swift.
- `docs/architecture/pc-linux-track.md` (this file) and `docs/architecture/pc-linux-status.md` (its running log).
- Research reports it needs, under `docs/research/` with the next free letter.

It does not touch `deck-app/`, `mixer/` (except to read the yardstick) or `docs/product/`; it proposes changes to the
crate schema in its status log and the main session merges them.

## Constraints that do not move

- Licences: MIT, BSD, Apache 2.0, ISC and public domain ship; LGPL only dynamically linked; GPL, AGPL, CC BY-NC and
  research-only never. Quote the licence file before adopting anything.
- No audio leaves the user's machine; no server; no network during analysis. Lookups only as the product allows.
- The crate file is Deckie's own format (D13); this track writes it, never a player's format, and proposes the
  engine-agnostic fields track L lists (a structured engine record, a benchmark-earned fidelity integer, per-block
  source and confidence, normalised scales, `features_present`).
- Recognition signatures come from an Apple device; this track does not build a fingerprint. It leaves a place in the
  crate for signatures made elsewhere.

## What it can test where

- In the cloud (Linux): everything that does not need Christopher's music. Unit tests on synthetic audio (clicks at
  known tempos, tone ladders at known keys, silence, gain steps for loudness); decoding of MP3 and AAC fixtures made
  from permissively licensed or generated audio; the crate reader and writer; the rekordbox XML importer against
  pyrekordbox's documented examples; the scoring port against the numbers in `mixer/pairs.json` regenerated from
  the committed features (`mixer/score.py` is the reference and `mixer/features/` is committed); the key estimator
  against `mixer/key_light_*.tsv`; Beat This! on ONNX Runtime against its published test data.
- On Christopher's Mac only: the 373-track yardstick. The audio is not in the repo and must not be uploaded. This
  track ships a `deckie-desk-lite bench` command that runs over `mixer/candidates.json` paths and writes one JSON
  per track in the lab's feature layout, and a comparison the main session runs with `mixer/bench_mu.py`-style
  metrics (beat and downbeat F-measure at 70 ms, tempo within 2 percent, key exact or neighbour, loudness delta,
  vocal correlation, section recall). Pass marks: at least Apple's framework on beats and loudness (stage 1
  results 1a), and the key estimator's known 75 percent exact, until a better permissive key detector exists.
- Windows: not in the cloud. A GitHub Actions workflow on a Windows runner builds and runs the unit tests; packaging
  and signing come later.

## Order of work

1. Investigate and decide, with a short report each: the Rust audio decoding stack (dr_mp3, platform AAC decoders,
   Symphonia's licence and patent position); ONNX Runtime from Rust (`ort`) and the Beat This! export; the FFT
   library (RustFFT); the EBU R128 crate; the vocal tagger (EfficientAT or YAMNet through ONNX).
2. `deckie-crate`: read and write the package format from track A section 5 with the engine-agnostic fields;
   round-trip tests; a fixture crate committed under `core/fixtures/`.
3. `deckie-core`: port the DSP from `mixer/analyze.py` and `local_tempo.py` (the grid fit, start and end tempo with
   the trust rule, the 8-bar lattice, mix windows, first and last sound, fade-out, per-bar bands, onset pattern,
   Camelot), then `score.py`; parity tests against the committed features and pairs.
4. `deckie-engine-oss`: decode, Beat This!, the key estimator from `mixer/key_light.py` (chroma_stft variant with
   the edma profile, whole track and the two mix windows, with the song-key seed and hysteresis), libebur128, the
   vocal tagger; a `bench` command for the Mac.
5. `deckie-desk-lite`: `build <folder> [--rekordbox export.xml] --out name.deckiecrate`; progress; resumable.
6. The C ABI and a tiny Swift package wrapper, so the Apple engine can call `deckie-core` (the P16 payoff).
7. The Windows build on CI.

## Working rules for the session

- Commit to its own branch (`pc-linux`), small commits, never to `main`; the main session reviews and merges.
- Keep `docs/architecture/pc-linux-status.md` current: what is built, what is measured, what it needs from the Mac,
  and open questions, in plain language with every term glossed, because Christopher reads it.
- When a step needs the music, say so in the status log and stop that step; do not look for the audio elsewhere.
- Ask the main session (not the user) for schema changes and for yardstick runs.
