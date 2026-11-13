# Check-ins: the Windows builder (branch `pc/windows-builder`)

Newest entry first. Each entry: when, what is done, what failed and why, what is next, and one plain line.

## Nov 13, 2026, 23:10 UTC: first push (steps 1 and 3 written, not yet seen on a Windows runner)

**Done, on Linux only so far (this cloud machine, Swift 6.4.1):**

- Step 3, the single-file form: `core/Sources/DeckieCrate/CrateArchive.swift`. A plain zip with nothing compressed,
  written and read by about 250 lines of our own, no new dependency. `CrateReader.read(from:)` now takes either form
  in the one call. 11 tests pass here (round trip, canonical bytes, a zip from another tool, a changed byte, a file cut
  short, compressed and encrypted entries refused, more than 65,535 files). `unzip` and Python's `zipfile` both open
  what it writes. A committed fixture, `core/fixtures/example-single.deckiecrate` (21 KB, made on Linux), is what the
  "made on one platform, read on another" test reads and must reproduce byte for byte on every platform.
- Step 1, written: `fetch-onnxruntime.sh` now fetches the Windows x64 archive too when run in Git Bash (both pins were
  already in `DEPENDENCIES.md`; the workflows use Deckie's own build, 6.6 MB). `core-windows.yml` fetches it and the
  two models, runs every suite, then builds a crate file from a generated folder with `deckie-build`, validates it
  and uploads it; a second job builds the same folder on Linux; a third compares the two
  (`core/Tools/compare_crates.py`, which states the tolerance and why). `core-linux.yml` runs the same end-to-end
  steps. The new tool `deckie-e2e` makes the folder and checks the result. On this machine: 3 songs in (WAV, FLAC,
  MP3), 2 files not in with their reasons, 1 folder left out, hidden files not read, second run reads nothing.

**Two things the main session should know:**

- No audio is committed. (I first meant to commit a generated MP3 of the synthesised test track; that was stopped,
  rightly, by the rule. The MP3 is now encoded once per workflow run on Linux with ffmpeg and handed to the Windows
  job as a run artifact, so both platforms read the same bytes.)
- The Windows ONNX Runtime library needs four Microsoft files that are not part of every Windows:
  `MSVCP140.dll`, `MSVCP140_1.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll` (the Visual C++ runtime; Swift's own
  runtime needs it too). Shipping them in the zip means a Microsoft licence that is not on the allowlist, so I have
  not added them. Plan: the program checks for them first and says in plain words what to install if they are
  missing. This is the one place "needs no other software" may not hold on a fresh PC. The owner decides whether
  the four files ship.

**Failed:** nothing yet; nothing has run on Windows yet.

**Next:** read the first Windows run and fix what breaks; then the program a DJ drags a folder onto (step 4), file
types (step 2), the words (step 5).

carry on
