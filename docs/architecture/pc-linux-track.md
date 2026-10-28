# The PC and Linux track: charter for its own session

Rewritten Oct 28, 2026 after Christopher's direction: "figuring out some of this in actual practice should be a
primary goal of this bucket, but also I want to get the actual mechanics of how we do this on a Linux and Windows
machine started." Research behind it: `docs/research/l-non-apple.md` (what runs off Apple) and
`docs/research/m-core-language-and-dependencies.md` (language and dependency policy). Product context:
`docs/product/spec-condensed.md`, `docs/product/00-decisions.md` (D3, D11, D13, P16, P17), `docs/architecture/`.

## What this track is, in one paragraph

The Apple apps keep Apple's Music Understanding framework for analysis: it ships inside iOS and macOS, costs the
app nothing, and Apple maintains it. That framework does not exist on Windows or Linux, because it is a library
and a set of models built into Apple's operating systems, not part of the Swift language. So this track builds a
second analyser for Windows and Linux whose output is measured against Apple's, writing the same crate file, and
it builds the small core of Deckie's own ideas (beat grid fit, tempo and key segments, mix windows, Camelot,
scoring, the crate format) once, in Swift, so the Apple apps and the Windows and Linux builder share it.

## Decisions taken, and the one deliberately not taken

- Deckie's own code is a plain Swift package, `DeckieCore`, with no Apple-only framework in it (P16 as revised by
  track M). The Apple engine is Music Understanding plus `DeckieCore`; the non-Apple engine is permissive open
  models plus `DeckieCore`.
- Linux first. The cloud session is a Linux machine; Swift on Linux is mature. Every mechanic below is done on
  Linux first.
- Windows: probed and passed (Oct 28, D14). GitHub's Windows runner installed Swift 6.4.1, built the package and
  passed the same 13 parity tests with no Windows-specific code (pull request #1, both workflows green). Rust or C++
  stays the fallback for the Windows build alone if a later mechanic proves painful there.
- Dependencies are welcome for solved problems (decoding, FFT, model runtime, loudness, XML, model weights) and
  governed by the policy in P16: pinned by version and hash in `DEPENDENCIES.md`, a licence allowlist checked in
  CI, nothing that downloads or runs code at build time, a quarterly update day with a benchmark rerun.

## What this track owns

- `core/` (new, repo root): the Swift package `DeckieCore` (DSP, scoring, crate read and write; pure computation),
  `DeckieEngineOSS` (the non-Apple analyser: decoding, Beat This! through ONNX Runtime, the key estimator, EBU R128
  loudness, a permissive vocal tagger) and `deckie-build`, a command-line crate-builder.
- `docs/architecture/pc-linux-status.md`, its running log, in plain language with every term glossed.
- `DEPENDENCIES.md` and the CI workflows (Linux and the Windows probe).

It does not touch `deck-app/`, `mixer/` (read-only yardstick) or `docs/product/`; schema changes are proposed in the
status log and merged by the main session.

## Constraints that do not move

Licences: MIT, BSD, Apache 2.0, ISC and public domain ship; LGPL only dynamically linked; GPL, AGPL, CC BY-NC and
research-only never; quote the licence file before adopting anything. Model weights and data may also be CC BY 4.0
(never code; attribution shown in the app). Weights ship under their own licence even when their training data
could not be shipped, unless that data's licence forbids commercial use; the data set, its licence and the
trainer are recorded beside the weights in `DEPENDENCIES.md` (note on D14). No audio leaves the user's machine; no
network during analysis. The crate file is Deckie's own format and the only thing written. Recognition signatures
come from an Apple device; this track builds no fingerprint and leaves a place in the crate for signatures made
elsewhere.

## What it can test where

- In the cloud (Linux): everything that needs no music. Synthetic audio with known tempo, key and loudness; MP3
  and AAC fixtures from generated or permissively licensed audio; the crate reader and writer; the rekordbox XML
  importer against pyrekordbox's documented examples; the scoring against `mixer/pairs.json` regenerated from the
  committed `mixer/features/` by `mixer/score.py`; the key estimator against `mixer/key_light_*.tsv`; Beat This! on
  ONNX Runtime against its published test data.
- On Christopher's Mac: the 373-track yardstick. The audio is not in the repo and is not uploaded. Because the
  non-Apple engine is plain Swift plus C libraries, it builds and runs on the Mac too, so the main session runs
  `deckie-build bench` over `mixer/candidates.json` here and scores it with the stage 1 metrics (beat and
  downbeat F-measure at 70 ms, tempo within 2 percent, key exact or neighbour, loudness delta, vocal correlation,
  section recall). Pass marks: at least Apple's framework on beats and loudness (stage 1 results 1a) and the key
  estimator's measured 75 percent exact until a better permissive key detector exists.
- Windows: the CI probe builds and runs the unit tests on a Windows runner; packaging comes later.

## Order of work

1. The spike, two weeks: `DeckieCore` on Linux with the grid fit, Camelot mapping and the scoring from
   `mixer/analyze.py` and `mixer/score.py`, reproducing the committed pairs; the same package building and testing
   on the Windows runner. This is the guard on the Swift decision.
2. The Linux mechanics, one at a time, each with a status-log entry: decode an MP3 and an AAC to float samples;
   run Beat This! through ONNX Runtime's C API from Swift on a synthetic click track; measure loudness with
   libebur128; port the key estimator from `mixer/key_light.py` (the FFT-chroma variant with the edma profile,
   whole track and the two mix windows, with the song-key seed and hysteresis); a vocal tagger through ONNX.
3. `DeckieCore` grows to the rest of the DSP: start and end tempo with the trust rule, tempo and key segments,
   the 8-bar lattice, mix windows, first and last sound, fade-out, per-bar bands, onset pattern; parity tests
   against the committed features.
4. The crate reader and writer, with the engine-agnostic fields track L lists (engine record, benchmark-earned
   fidelity, per-block source and confidence, `features_present`); a fixture crate under `core/fixtures/`.
5. `deckie-build <folder> [--rekordbox export.xml] --out name.deckiecrate`, with progress, resumable, and a
   `bench` subcommand for the Mac.
6. The Mac run of the yardstick, by the main session; fixes; a second run.
7. Windows: from probe to a packaged build, if the probe held; otherwise the fallback decision.

## Working rules for the session

- Commit to its own branch (`pc-linux`), small commits, never to `main`; the main session reviews and merges.
- Keep `docs/architecture/pc-linux-status.md` current: built, measured, needed from the Mac, open questions.
- When a step needs the music, say so in the status log and stop that step.
- Ask the main session, not Christopher, for schema changes and yardstick runs; plain language throughout.
