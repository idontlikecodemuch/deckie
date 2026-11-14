# Check-ins: the Windows builder (branch `pc/windows-builder`)

Newest entry first. Each entry: when, what is done, what failed and why, what is next, and one plain line.

**The zip to use: `pc-package` run 43535065527** (commit `21ad255`), artifact `Deckie-for-PC-first-test` (id
14090055016, kept to Dec 14, 2026): `Deckie-for-PC-first-test.zip`, **122,280,833 bytes**, SHA-256
`6e1cd29b2c9cce10c6e0059954612d5ee9bb35f0b036270773f6cbf4e857e480`. Microsoft's runtime included. Earlier zips are
superseded.

## Nov 14, 2026, 00:45 UTC: the owner's four answers applied; `main` merged; all three workflows green; fresh zip

The main session relayed the owner's yes to all four open points (Nov 13). Done:

- **Microsoft's Visual C++ runtime ships in the zip**: `msvcp140.dll`, `msvcp140_1.dll`, `vcruntime140.dll`,
  `vcruntime140_1.dll`, version 14.42.34433.0, the copies the Swift toolchain installs beside its own runtime, with
  a notice in the zip's licences and a row in the acknowledgements. Recorded in `DEPENDENCIES.md` section 3 with
  sizes, hashes and the quoted terms. **One thing for the attorney**, written there: Microsoft's permission is given
  to licensed Visual Studio users (the free Community edition counts, within its limits), so the company should
  hold one; and I could quote Microsoft's list of distributable files but not the licence terms themselves, whose
  page did not give up its text.
- **ICU's Unicode License V3** is on the allowlist ("the owner, Nov 13, 2026"); its text ships in the zip.
- The iPad side and the engine's key: nothing done, as told.
- **`main` merged** (at `3be2986`), no conflicts. The merged tree passes 412 tests here on Linux.
- **All three workflows green on `21ad255`**: `core-windows` 43535065509, `core-linux` 43535065566, `pc-package`
  43535065527. The zip was again unzipped and run on the runner with nothing but Windows on the path; this time the
  runtime it used is its own. Four four-minute songs: 5.8 s a song by the clock (10.8 s each on its own).

**Failed:** nothing in this round.

**Next, started:** `.m4a` through Windows' Media Foundation. First only a measurement: a small shim and a test
that prints where the click in the AAC test tone lands on the Windows runner, which says whether Windows removes
the encoder's lead-in. Nothing is wired into the builder until that is known. The commit after `21ad255` carries
it; if it turns the Windows workflow red I fix or back it out, and say so here.

carry on

## Nov 14, 2026, 00:10 UTC: done as far as a runner can show; three decisions open

**Done.** All three workflows are green on commit `13d69b8`:

- `core-windows` run 43529510729: 379 tests passed on Windows with the engine suites running; the end-to-end build;
  Windows against Linux, every compared value identical on the three test songs.
- `core-linux` run 43529510806: the same suites and end-to-end steps.
- `pc-package` run **43529510736**: the zip, **121,600,412 bytes** (SHA-256 `f41d6cd8…29d6`), artifact
  `Deckie-for-PC-first-test`, kept to Dec 13, 2026. Without Microsoft's runtime files this time. Built, unzipped
  and tried on the runner as a DJ would use it.
- Measured on the runner, four four-minute songs, two at once: 6.0 s a song by the clock (11.2 s each on its own);
  the run before, on another runner, 11.3 s by the clock.
- The letter: `docs/research/y-windows-builder.md`, with each claim marked as seen on a runner or not provable
  without a real PC. The tester's words: `core/Tools/windows/READ ME FIRST.txt` and
  `docs/product/windows-first-test.md`.
- The branch merges with `main` (at `3be2986`) without conflicts, checked with `git merge-tree`; not merged.

**Failed or not done:**

- Reading `.m4a` on Windows (step 2's "build what is small and safe"): not built. Nothing about it was small or
  safe; the letter says what it takes.
- Nothing was tried on a real PC. The letter's table lists what that leaves unproven: the blue "Windows protected
  your PC" box, antivirus, a real drag and drop, typing into a real console window, a PC without Microsoft's
  runtime, Windows 10, Windows on Arm, a standard (non-administrator) user.
- The zip of the earlier run 43528242707 contains Microsoft's runtime files and should not be handed on.

**Open, for the owner or the main session, before a tester gets the zip:**

1. Ship Microsoft's Visual C++ runtime in the zip or not. I recommend shipping it.
2. ICU's licence (Unicode License V3), which Swift's Foundation brings: yes or no.
3. The iPad app: build against this core, call `CrateArchive.unpack` on import, and let its document type take a
   plain file. Needs a device.
4. The engine writes its own key on Windows and Linux, which D16 says it should not yet.

**Next, if this carries on:** a run by hand on a real PC; then `.m4a` through Media Foundation with the lead-in
measured.

carry on, once the three decisions are made; consider changing direction only if the iPad cannot take a plain
file under `.deckiecrate`, because then the single file needs its own extension (a small change, in one place)

## Nov 13, 2026, 23:45 UTC: steps 1, 3 and 4 seen working on Windows runners; step 5 written; step 2 reported, not built

**Done and seen on GitHub's Windows machine:**

- **Step 1.** `core-windows` run 43526173797 (commit 2337e7b) is green in all four jobs. The engine suites run on
  Windows instead of skipping (the test step's own lines: 25 inference tests, 35 engine tests, 33 builder tests, all
  passed; the only skips are one test that needs Linux's library layout, the suite that runs only where the vocal
  model is missing, and three MP3 tests that need the ffmpeg program, which skip in Linux CI too). The end-to-end
  build made a crate file from the generated folder with `deckie-build`, the core's validator read it in both forms,
  and a second run read nothing. **Windows against Linux: every compared value identical** on the three songs
  (WAV, FLAC, MP3), records and float16 sidecars alike; the tolerance in `core/Tools/compare_crates.py` was not
  needed on this folder and stays as the guard for real music, which CI does not have. `core-linux` run
  43526173752 is green with the same end-to-end steps.
- **Step 3.** The single-file form's tests pass on Windows in that run, including the committed file made on Linux
  being read and rebuilt byte for byte on Windows. Written into `docs/architecture/crate-format.md` as a proposed
  addition, with what the iPad app needs.
- **Step 4.** `pc-package` run 43528242707 (commit 2a13a42) is green: the zip was built on a Windows runner
  (121,892,360 bytes; 188 MB unzipped, 37 files), unzipped with Windows' own tool into a fresh folder with a space
  in its name, and "Make Crate File.exe" was started with nothing on the path but Windows: a folder given as its
  argument (what a drop does) made the crate file and the log next to the music folder; a second run read nothing;
  with no argument it asked for the folder, said a wrong path plainly, and took the right one; the starter alone,
  without the rest, said to unzip first. **But that zip must not be handed on** (next point).

**Failed or found, exactly:**

- **The zip of run 43528242707 contains Microsoft's Visual C++ runtime** (`msvcp140.dll`, `msvcp140_1.dll`,
  `vcruntime140.dll`, `vcruntime140_1.dll`), which I had said would not ship. The Swift toolchain's own runtime
  folder holds a copy, and the script copies whatever the program imports from that folder. Fixed in commit 13d69b8
  (the script now leaves them out and stops if one gets in); the run of that commit is the zip to use. The owner's
  decision is still open: Swift's own installer ships these files beside its runtime, and a PC whose copy is older
  than the one Swift was built with would fail to start, so my recommendation is to ship them, once the licence is
  accepted (`DEPENDENCIES.md`, section 3; one switch in `package.sh`).
- The first `pc-package` run (43527240272) failed in one step only: the test of the starter alone treated the
  starter's expected ending as a failure. A mistake in the workflow, fixed.
- The first runs of both core workflows failed at the end-to-end step because the MP3 was not in the repository
  (see the entry below).
- **ICU's licence** (Unicode License V3) is not on the allowlist word for word. ICU is inside Swift's Foundation and
  cannot be left out. It was already named in the acknowledgements table; now a build carries it, the main session
  needs to say yes or no. Texts and hashes: `core/notices/swift/`.
- **The engine writes its own key into the record** (confidence 0.45 or 1.0) on Windows and Linux, though D16 says
  a platform without Apple's framework carries no key of Deckie's own until it meets the bar. I did not change the
  engine. The READ ME says "no key yet", which is true of what the booth should show, not of the file's bytes.

**Step 2, reported instead of built.** On Windows the builder reads MP3, FLAC (and Ogg-FLAC), WAV and AIFF, as on
Linux. It does not read AAC or Apple Lossless (.m4a, .mp4, .aac), WMA, Ogg Vorbis or Opus, and never protected
files. The program says which files it could not read and why, counted by type, on screen and in the log. Reading
.m4a through Windows' Media Foundation is not small and not safe to ship unmeasured: the letter says what it takes
(a C shim of about 200 lines, loaded at run time so Windows editions without media features still start, and a
measurement of the 23 to 48 ms lead-in AAC files carry, on Windows 10 and 11, before any grid from such a file can
be trusted).

**Next:** read the run of commit 13d69b8 (zip without Microsoft's files; time per four-minute song), then the
letter `docs/research/y-windows-builder.md`.

carry on

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
