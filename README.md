# Deckie

A booth companion for DJs who play on gear that does not know their library. An iPad listens to the room,
names the playing song from the DJ's own crate, reads the pitch fader, shows what could come next and how to
bring it in, learns how the DJ mixes, and writes the set's tracklist. The music never leaves the DJ's devices.
An App Hold Media product. The iPad app's bundle id is `io.deckie.booth` and Desk for Mac's is `io.deckie.desk`
(D1, D40).

Start with `docs/product/spec-condensed.md` (the two-page spec; the first version was built in an Oct 2026 sprint
for one party, and `docs/product/roadmap.md` tells that story), `docs/product/00-decisions.md` (why) and
`docs/architecture/overview.md` (what the parts are). The evidence behind the spec is in `docs/research/`.

## Layout

```
core/         the shared Swift core: decoding, analysis, scoring, the crate file (see core/README.md)
desk-app/     Deckie Desk, the Mac app that reads a crate and writes a crate file
desk-shell/   Deckie Desk for Windows and Linux: the native window (Swift) that shows desk-web/ and starts the engine (see desk-shell/README.md)
desk-web/     the pages Desk for Windows and Linux shows in that window (see desk-web/README.md)
deck-app/     Deckie, the iPad app (SwiftUI, xcodegen; see deck-app/README.md)
site/         the public site at deckie.io: home page, dictionary and the explainer film (see site/README.md)
mixer/        the analysis, scoring, planning and rendering lab in Python, code only (see mixer/README.md)
tools/        the benchmark harness for Apple's Music Understanding framework, and the privacy check
docs/         the vocabulary (docs/vocabulary/terms.json, the source of the public dictionary), product spec and decisions, research reports, architecture, naming
```

## Running the lab

Neither the audio nor the lab's data is in the repo. The lab analysed a personal music library, so its feature files,
candidates and per-song sheets are private and live outside it. The scripts find them through two settings, with no
default that points at anyone's folder:

```
export DECKIE_LAB_DATA="/path/to/lab-data"     # features/, candidates.json, recs.json, the per-song sheets
export DECKIE_MUSIC_ROOT="/path/to/music"      # the audio the candidates' paths start with
```

Without `DECKIE_LAB_DATA` the core's lab-parity tests read `core/fixtures/lab-sample`, twelve invented songs in the
lab's file shapes (`core/Tools/make_lab_sample.py`). Disc build outputs are written beside the audio, never into the
repo.

The Python environment is `mixer/.venv` (Python 3.14; recipe in `mixer/README.md`). Run every script with the
venv's python and `-I`. `pairs.json` (61 MB) is never committed: `score.py` regenerates it in the data folder.

The app: `cd deck-app && xcodegen generate`, then build with Xcode or `xcodebuild` (commands in its README). It
bundles only the public-domain demo crate; a DJ's crate file arrives from Desk, and no catalogue made from anyone's
music is built into the app or committed.

## What is not here, on purpose

No audio, no credentials, and nothing made from anyone's music library: no song lists, file or folder names,
per-song analysis, fingerprints or recognition catalogues of commercial recordings. The only songs in the repository
are the public-domain (CC0) demo songs and their analysis (`site/demo/`, `deck-app/Deck/Demo/`, credited in
`site/demo/CREDITS.md`), invented songs in test fixtures, and well-known titles used as public lookup examples in the
lookup tests. Numbers measured on the lab's private data appear only as totals. `tools/check-private.sh` runs on every
push and fails if private places, home paths, addresses or device ids come back. See `docs/product/00-decisions.md`,
D3, D10 and D45.
