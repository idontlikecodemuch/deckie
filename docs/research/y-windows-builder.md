# Research Y: a Windows program that makes a crate file

Dated Nov 13 to 14, 2026. A build letter, not web research: what was built on the branch `pc/windows-builder` for
the first step of D29 (a PC version), what GitHub's Windows machines proved, and what only a real PC can. Read with
`docs/research/briefs/checkin-windows-builder.md` (the running log), `docs/product/windows-first-test.md` (the
tester's page), `docs/architecture/crate-format.md` ("the single-file form") and `DEPENDENCIES.md` section 3.

Words used here, said once. A **crate file** is the `.deckiecrate` Deckie writes about a DJ's songs (tempo, bars,
style, vocals; never audio). A **runner** is one of GitHub's rented machines that builds and tests the code on every
push; a **workflow** is the list of steps it follows; a **run** is one go through them, with a number; an
**artifact** is a file a run keeps for download. The **engine** is Deckie's own analyser in `core/`. A **DLL** is a
library file a Windows program loads when it starts.

Every claim below is marked: **[runner]** seen on a GitHub Windows runner in the run named; **[linux]** seen on
Linux only; **[not proven]** cannot be shown without a real PC, or was not tried.

## Update, Nov 14, 2026

The owner answered the open decisions below with yes to all (Nov 13, relayed by the main session). Microsoft's
runtime now ships in the zip and ICU's licence is on the allowlist, both recorded in `DEPENDENCIES.md` section 3;
the iPad side is the main session's; the engine's key stays as it is (the note on D30 and D16). `main` is merged.
**The zip to use is `pc-package` run 43535065527** (commit `21ad255`): 122,280,833 bytes, SHA-256
`6e1cd29b2c9cce10c6e0059954612d5ee9bb35f0b036270773f6cbf4e857e480`, with `core-windows` 43535065509 and `core-linux`
43535065566 green on the same commit. So "a PC without Microsoft's runtime" is no longer a known gap, though still
not tried on such a PC. The rest of this letter is as written on Nov 13; where it says the runtime is not shipped,
this note replaces it.

## In plain words

- There is a zip. Unzipped, a DJ drags a music folder onto "Make Crate File", a window shows each song with the
  time left, and one crate file appears next to the music folder with a short log beside it. A second run only
  reads what changed. On a Windows runner this worked from the zip with nothing else on the machine's path
  **[runner]**. Nobody has yet done it by hand on a PC **[not proven]**.
- The crate file a Windows machine makes is the same as Linux's: on the three test songs every compared number is
  identical **[runner]**. Real music has not been compared, because none is in the repository.
- The engine's whole test suite now runs on Windows instead of skipping: 379 tests pass **[runner]**.
- A crate file can now be one file: the same contents in a plain uncompressed zip, read by the same one call.
  The iPad app has not been built against it **[not proven]**.
- It reads MP3, FLAC, WAV and AIFF. It does not read `.m4a` (AAC, Apple Lossless), WMA, Ogg or Opus; it says so,
  counted by type. Reading `.m4a` was not built; the section below says what it takes.
- **Three things need the owner or the main session before a tester gets the zip**: whether Microsoft's runtime
  files ship in it (I recommend yes), whether ICU's licence is accepted, and the iPad side of the single file.

## The runs

All on commit `13d69b8`, all green:

| Workflow | Run | What it shows |
|---|---|---|
| `core-windows` | 43529510729 | the suites on Windows, the end-to-end build, Windows against Linux |
| `core-linux` | 43529510806 | the same suites and the same end-to-end build on Linux |
| `pc-package` | 43529510736 | the zip built and tried; artifact `Deckie-for-PC-first-test` (id 14087191541, kept to Dec 13, 2026) |

The zip: `Deckie-for-PC-first-test.zip`, **121,600,412 bytes**, SHA-256
`f41d6cd8867ee03039fbe559ff83d0739ce2b719cf1f7002257b70cbe46629d6`; unzipped 33 files, 187,600,626 bytes (the two
models 97 MB, Swift's runtime and the licences about 59 MB, ONNX Runtime 18 MB, the program 12.7 MB, the starter 7,680 bytes).

**Do not use the zip of run 43528242707** (commit `2a13a42`): it contains Microsoft's four runtime files, by my
mistake (below).

## What was built

1. **The Windows workflow runs the engine** (`.github/workflows/core-windows.yml`). It fetches Deckie's own build
   of ONNX Runtime 1.31.1 for Windows x64 and the two models by their pinned hashes (`fetch-onnxruntime.sh` now
   handles Windows when run in Git Bash; both Windows pins were already recorded), runs every suite, then builds a
   crate file from a generated folder with `deckie-build`, checks it with the core's validator, and compares it
   with the same folder built on Linux in the same run.
2. **An end-to-end tool**, `deckie-e2e` (`core/Sources/deckie-e2e`). The folder it makes: a WAV, a FLAC (written
   by a small writer of our own, no encoder), an MP3, a nested folder, a name with a space, a name that is not
   ASCII (`Träck Zwei.flac`), a 4-second file that cannot be analysed, a copy-protected stand-in, a `.jpg`, a
   dot-hidden file and folder, on Windows a file hidden the Windows way, and a `_old` folder.
3. **The single-file form** (`core/Sources/DeckieCrate/CrateArchive.swift`, 264 lines, no dependency), with 11
   tests, written into the format page as a proposed addition.
4. **The PC program**: `DeckiePC` (the run, the words in one list, the log) and `deckie-make` (its console), with
   6 tests; a starter, `core/Tools/windows/launcher.c`; a packaging script and a workflow that builds the zip and
   tries it (`core/Tools/windows/package.sh`, `.github/workflows/pc-package.yml`).
5. **The words**: `READ ME FIRST.txt` in the zip and `docs/product/windows-first-test.md`.
6. One change in the other agent's area, kept to a few lines: `AudioFiles.swift` leaves out files Windows marks
   hidden (on Windows a dot hides nothing).

## What is proven, claim by claim

| Claim | Status |
|---|---|
| The pinned ONNX Runtime (Deckie's build, no reporting client) and both models fetch and verify on Windows | **[runner]** 43529510729; the release test scanned the DLL: 0 of 9 markers, the event-tracing name present and never registered, as recorded |
| The engine suites run on Windows | **[runner]** 379 tests passed in 8 groups (6, 25, 35, 9, 39, 98, 134, 33). Skipped: one test that needs Linux's library layout; the suite that runs only without the vocal model; three MP3 tests that need the ffmpeg program (they skip in Linux CI too; the end-to-end MP3 covers MP3 decoding on both) |
| `deckie-build` makes a valid crate file from a folder on Windows: MP3, WAV, FLAC, nested folder, space, non-ASCII name, hidden files left out, paths with forward slashes | **[runner]** 3 songs in, 2 files out with reasons, 1 folder left out |
| A second run reads nothing | **[runner]** "5 unchanged since the last run; nothing to analyse" |
| Windows and Linux give the same analysis | **[runner]** on the three synthesised songs every compared value is identical, records and float16 sidecars. **[not proven]** on real music |
| The single file round-trips, is canonical, detects damage | **[runner]** and **[linux]**: the 11 tests pass on both |
| A file made on one platform reads on another | **[runner]** the committed file made on Linux is read on Windows and rebuilt there byte for byte; Python's `zipfile` on Linux reads the file Windows made (the comparison job). **[not proven]** on macOS and iPadOS: no Apple machine ran this branch |
| The zip works with no installer and no other software | **[runner]** unzipped by Windows' own tool into `A DJ's PC`, run with the path cut to `System32`, so nothing from the Swift toolchain could be found. **But** the runner has Microsoft's Visual C++ runtime in `System32`; a PC without it is **[not proven]** |
| A folder dropped on the program makes the crate file | **[runner]** as an argument, which is what a drop passes. **[not proven]**: Explorer itself was not driven |
| A double click asks for the folder | **[runner]** with the answers piped in: it asked, said a wrong path plainly, took a quoted path. **[not proven]**: typing or dragging into a real console window, which goes through other code (`ReadConsoleW`) that no run exercised |
| The crate file lands next to the folder, named after it, never inside; a log beside it | **[runner]** `My Müsic.deckiecrate` and `My Müsic Deckie log.txt` |
| Progress, the closing summary by reason and type, waiting for Enter | **[runner]** for the words; the wait was switched off in the runs (`--no-wait`), so the window staying open is **[not proven]** |
| Started from inside the zip, it says to unzip | **[runner]** the starter alone printed the message and ended with its code |
| No administrator rights | **[not proven]**: the runner is an administrator. By design it writes only next to the music folder and under the user's local app data |
| "Windows protected your PC" appears and "Run anyway" is enough | **[not proven]**: a runner shows no such box and its files carry no "from the internet" mark. The program is unsigned |
| Antivirus leaves the starter alone | **[not proven]**: it is a 7.7 KB unsigned program with no C runtime that starts another program, a shape some scanners distrust |
| Names that are not ASCII show correctly in the window | **[not proven]**: bytes were right in the log; a real console's font was not seen |
| Windows 10; Windows on Arm; long paths (over 260 characters); OneDrive folders whose files are not downloaded; network drives; the PC sleeping | **[not proven]**: the runner is Windows Server 2025 (build 26100) on x64. No Arm archive of ONNX Runtime is built or pinned, so Arm would run the x64 program through Windows' emulation, untried |

**The tolerance**, for when real music is compared (`core/Tools/compare_crates.py`, whose header has the reasoning):
whole numbers, texts, true-or-false values and the import log must be identical; a number written with d decimals
may differ by 2 steps of its last decimal; per-bar series (float16) by 0.05; the style vector by 0.002 a value.
Why any difference at all: the two systems' maths libraries may differ in the last bit of `sin`, `exp`, `log` and
`pow`, and the two ONNX Runtime builds add the same numbers in a different order, so the models' outputs agree to
about four decimals. The crate file's rounding hides nearly all of that, but a value on a rounding edge can land
one step either side. A beat moved by one model frame would show as 0.02 s and fail, as it should. On the test
folder none of it was needed.

## Time per song, measured on the runner

Release build, from the zip, the program's own default of two songs at once, on GitHub's Windows runner (4
processors, 16 GB, AMD family 26):

| Songs | Each song's own reading time | Per song by the clock |
|---|---|---|
| Four synthesised four-minute songs (44.1 kHz stereo; two WAV, two FLAC), run 43529510736 | mean 11.2 s | **6.0 s** (24.2 s for the four) |
| The same, the run before (43528242707, another runner) | not printed | 11.3 s (45 s for the four) |
| Four 63-second test songs, run 43529510736 | mean 3.7 s | 2.2 s |

So 6 to 11 s a four-minute song on a shared 4-processor runner, with a factor of two between two runs of the same
code. Research P's estimates for laptops stand unmeasured. Memory was not measured on Windows (the probe has no
Windows port).

## File types on Windows (step 2)

**Reads today**, the same as Linux: MP3 (dr_mp3); FLAC, native and Ogg-FLAC, to 24 bits (dr_flac); WAV, 16-, 24-
and 32-bit integer and 32-bit float, plain and "extensible"; AIFF and AIFF-C.

**Does not read**: AAC and Apple Lossless (`.m4a`, `.mp4`, `.aac`), WMA, Ogg Vorbis, Opus (each logged as
`unsupported`); copy-protected files (`protected`, never readable). 8-bit and 64-bit-float WAV are refused too.

**What the DJ is told**: on screen as each file is met and in the closing summary, one line per reason with its
types counted, in plain words ("12 AAC and Apple Lossless files (.m4a) cannot be read by this version yet (m4a
12)"), and in the log each file by its path below the music folder.

**Not built: reading `.m4a` through Windows' Media Foundation**, the decoder the decisions name. It is neither
small nor safe to ship unmeasured:

1. A C shim of about 200 lines (Media Foundation is called through COM, which Swift cannot call comfortably): open
   the file with the source reader, ask for float samples, read to the end. No licence question: it is part of
   Windows.
2. It must be loaded at run time, not linked. Windows "N" editions, sold in Europe, come without the media
   features, and a linked program would not start there at all.
3. **The lead-in.** AAC files begin with 1,024 to 2,112 samples of encoder lead-in, 23 to 48 ms. Whether Media
   Foundation removes it depends on the Windows version and on the file. A beat grid 48 ms late is a wrong grid,
   and nothing would say so. The test exists in principle (the committed `tone.m4a` has a click at exactly
   2.000 s), but it has to pass on Windows 10 and 11, and the runner is neither. If Windows leaves the lead-in in,
   the file's own edit list has to be read (the box reader in `ProtectedMP4.swift` is the start).
4. Apple Lossless goes the same way (Windows 10 and later decode it) and needs a test file, which does not exist.
5. WMA would also come through Media Foundation, but needs a new case in the public `AudioFormat` list, which the
   Apple apps switch over. Ogg Vorbis and Opus are not in Windows; they need decoders of our own (stb_vorbis is
   public domain; libopus is BSD).

About a day with the runner's cycles, plus a Windows 10 PC for point 3.

**Measured since (Nov 14, `core-windows` run 43536290887).** The shim of point 1 is written
(`core/Sources/CMediaFoundation`, 176 lines of C, opened at run time as point 2 asks) and builds on Windows; it is
**not used by the builder**. A test decodes `tone.m4a` with it on the runner (Windows Server 2025, build 26100)
and reads where the click lands:

| | Media Foundation gave | The file is |
|---|---|---|
| Length | 178,176 frames (174 AAC frames of 1,024, every one whole) | 176,400 frames (4.000 s) |
| The click | frame 89,224 | frame 88,200 |
| First block's time stamp | 0.0 s | |

So **Windows does not remove the lead-in**: everything is 1,024 frames (23.2 ms) late, and the end is not cut
either. The file itself says both numbers in its edit list (start at 1,024, play 4.000 s), so the answer to point
3 is that Deckie has to read the edit list and trim. That makes the remaining work larger than "one line in the
decoder", which is why it is reported here and not built:

1. Read the MP4's edit list, time scales and sample count (a box reader exists in `ProtectedMP4.swift`), and trim
   the start and the end by them. Tested on Linux too, since it is plain Swift.
2. Decide by length, not by trust: trim only when the decoded length is the untrimmed one (whole AAC frames); take
   it as it is when it already has the edit list's length (a Windows that trims); refuse the file when it is
   neither. Then a Windows version that behaves differently cannot give a silently wrong grid.
3. Files with no edit list. Many AAC files, iTunes' own among them, state the lead-in in an `iTunSMPB` tag
   instead; that has to be read as well. A file that states it nowhere has to be either refused or read with a
   guess, and a guess is a late grid. **This needs a decision**: refuse such files (honest, loses some), or accept
   them and record that the start is uncertain (needs a place in the record, which the format does not have).
4. Apple Lossless: no lead-in by design, so the same path with nothing to trim; needs a generated test file.
5. Still only Windows Server 2025 measured. Windows 10 and 11 need a PC; point 2 is the guard until then.

Size: two to three days with tests, most of it points 1 and 3. No dependency and no licence question.

## The single-file form (step 3)

Chosen: a plain zip with nothing compressed, under the same name `<name>.deckiecrate`, written and read by our own
code. Why: no dependency; the only hard part of a zip reader is decompression, and there is none; any tool can
look inside; the zip format's own checksum of every file gives damage detection. It is canonical (fixed order,
zero time stamps), so the same contents give the same bytes everywhere. `CrateReader.read(from:)` takes either
form. Details and what was passed over: the format page.

**What the iPad app needs** (I cannot build it): nothing to read, once it builds against this core, since its reads
already go through that one call; one call to `CrateArchive.unpack` where it imports a crate file as a copy; and
its declared document type must accept a plain file as well as a package under `.deckiecrate`. Whether one
declared type can cover both is the open point, and it needs a device. If it cannot, the single file takes a
second extension and nothing else changes.

## Dependencies touched, with their licences

| What | Change | Licence |
|---|---|---|
| ONNX Runtime 1.31.1, Deckie's own Windows x64 build | now fetched on Windows and shipped in the zip; pin unchanged | MIT; Eigen inside, MPL 2.0, with its notice and the two patches in the zip |
| Beat This! and YAMNet model files | shipped in the zip; pins unchanged | MIT; Apache 2.0; training sets in `DEPENDENCIES.md`, which the zip carries whole |
| Swift 6.4.1 runtime: 15 DLLs (standard library, Foundation, dispatch) | shipped for the first time | Apache 2.0 with the Runtime Library Exception. Texts in `core/notices/swift/` |
| ICU 76.1, inside Foundation | shipped for the first time | **Unicode License V3: permissive, not on the allowlist word for word. Needs a yes.** |
| Microsoft Visual C++ runtime (4 DLLs) | needed by Swift's runtime and ONNX Runtime; **not shipped** | Microsoft's redistribution terms, not on the allowlist. **Needs a decision.** |
| dr_mp3, dr_flac | unchanged, inside the program | public domain |
| ffmpeg (Ubuntu's package) | test tool in the Linux jobs only: encodes one MP3 of the synthesised test track per run | not linked, not shipped |
| GitHub Actions helpers | the same six, used in one more workflow | as before (pins by tag, pending) |
| New code of our own, no dependency | the zip reader and writer, CRC-32, the FLAC test writer, the starter (Windows' `kernel32` only), the import-table reader for packaging | |

Nothing downloads or runs code at build time beyond the pinned fetches. No audio, model or program file is
committed. The one binary-looking file committed is the 21 KB example crate file in its single-file form.

## What went wrong, exactly

- **I packed Microsoft's runtime by mistake.** The Swift toolchain's runtime folder holds its own copy of the four
  files, and the packaging script copies whatever the program imports from that folder. The zip of run 43528242707
  has them. Found by reading that run's own file list; fixed in `13d69b8`; the script now stops if one gets in.
- **I meant to commit a generated MP3** of the synthesised test track. That was stopped, correctly, by the rule
  against committing audio. The MP3 is now encoded once per run on Linux and handed to the Windows job.
- The first packaging run failed one step through a mistake in the workflow (the starter's expected ending was
  read as the step's failure).
- **Found, not mine to change: the engine writes its own key** into every record on Windows and Linux (confidence
  0.45 or 1.0), though D16 says such a platform carries no key of Deckie's own yet. The READ ME says "no key yet",
  true of what the booth should show, not of the bytes.
- The log's "system" line reads "Windows Server 2019 (build 26100)": Swift's own label is wrong; the build number
  is right (Server 2025).

## Open decisions

1. **Microsoft's runtime in the zip.** Without it, a PC that lacks it, or has an older copy than Swift was built
   with, cannot start the program; the starter then says what to install, which breaks "needs no other software".
   Swift's own installer ships these files beside its runtime. Recommendation: ship them (`DECKIE_SHIP_VC_RUNTIME=1`
   in `package.sh`), once the licence is recorded.
2. **ICU's licence.** Yes or no; there is no Foundation without it.
3. **The iPad's document type** for a plain-file `.deckiecrate`, on a device.
4. **A signing certificate**, which is what removes "Windows protected your PC". Not looked into.

## What remains

- **Before a tester**: the three decisions above; one run by hand on a real Windows 10 or 11 PC, standard user,
  watching for the blue box, the antivirus, the console and a dragged folder.
- **Before a window**: Swift has no window toolkit of its own on Windows; the choices are Win32 through Swift's
  `WinSDK`, WinUI through an experimental bridge, or a thin native shell. The logic that is not about windows is
  already in the core (`DeckieDesk`, D28) and `DeckiePC`'s words are in one list.
- **Audio CDs**: not started. A burned data disc is a folder and reads today as one; an audio CD needs Windows'
  disc-reading calls and the track listing, and D25's rules for sources, which the builder has but the PC program
  does not yet offer.
- **Recognition**: a PC-made crate file has an empty `signatures` block. Waits on `trial/own-recognition`.
- **Key**: waits on `trial/own-key`, on D30's reading of keys from files' tags and DJ programs (the other agent's
  work on `main`, which reaches the PC program through `Builder` when merged), and on the D16 point above.
- **`.m4a`**: the section above.
