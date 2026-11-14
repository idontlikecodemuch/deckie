# Check-ins: the Windows builder (branch `pc/windows-builder`)

Newest entry first. Each entry: when, what is done, what failed and why, what is next, and one plain line.

## Nov 14, 2026, 08:00 UTC: covers (D36) on branch `pc/covers`: core, builders and Desk written; all four workflows green

**Green on commit `a15a78b`**: `core-linux` 43572620220, `core-windows` 43572620242 (which also compares the
Linux and Windows crate files: the same covers, byte for byte), `desk-window` 43572620234, `pc-package` 43572620331.
Covers are parked here while the packaging of Desk's window is done first, on `pc/package-desk` (the owner's change
of order). What is left for covers is listed under "Not done" below; nothing is half-written.

**The addition as written** (`docs/architecture/crate-format.md`, "Addition with D36"):

- A record may carry **`file.cover`**: the SHA-256 of the **source picture's bytes**, left out when the song has
  none. The thumbnail is **`covers/<hash>.jpg`**, stored once for every song that shares the picture.
- **One size**: longest side 128 pixels, shape kept, never scaled up; a baseline JPEG at quality 80, anything
  see-through over white, no metadata. A reader may rely on at most 128 pixels and at most 24 KB.
- **Limits on the source**: JPEG or PNG only, at most 32 MB and 8,192 pixels a side, the size read before anything
  is decoded. A damaged, enormous or other-format picture gives no cover; the song still goes in and the picture
  is counted.
- **No cap for the whole crate file**; the cap per cover bounds it.
- **The single-file form** carries the folder as it carries any folder. Nothing new.
- The writer refuses a record whose cover file is missing and deletes covers no record names, so the last song of
  a release leaving a crate takes its cover with it.
- **Why the source's hash**: the thumbnail's bytes are the same on Linux and Windows (a hash pinned in the tests
  passed on both runners) but will differ on a Mac, which uses the system's image code. Named by the source, one
  release has one entry whichever computer read it.

**Where the picture comes from**: the file's own front cover (ID3 `APIC` and `PIC`, FLAC `PICTURE` and the two
Vorbis-comment forms, MP4 `covr`); else a picture beside the song, in its own folder, named `cover`, `folder`,
`front`, `albumart` or `album` with `.jpg`, `.jpeg` or `.png` (what Windows Media Player, Explorer, rippers and
stores write). Known weakness: a folder of unrelated singles with one such picture gives every song that picture.

**The builders** (`deckie-build`, `deckie-make`, Desk's run) write covers through one path. A second run does not
redo them: each file's line in the work folder remembers where its picture came from and its hash, and the
thumbnail is kept there. A picture added, changed or removed beside the music later is noticed without reading any
song.

**Desk**: a new request `song.cover` answers with the JPEG inside the message (no port, the page never told a path
or a hash), each song row says whether it has one, and the naming panel shows it at 80 pixels with an empty square
of the same size when there is none. Protocol number unchanged (an addition). Two new words in `DeskWords`.

**Measured:**

| | |
|---|---|
| A cover from the generated test pictures | 2.2 to 2.3 KB |
| The worst case tried (512 pixels of random colour) | 5.4 KB |
| The end-to-end folder (3 songs, 2 covers) | crate file 20,992 bytes without covers, 26,002 with: 4,558 bytes of covers |

**What 2,000 songs would gain.** From these numbers, about 2.3 KB for each distinct picture: 4.6 MB if every song
has its own cover, under 0.5 MB if they come ten to a release. The rest of the crate file is about 8 MB at that
size, so the worst case adds a little over half again. Real sleeves have more detail than my generated pictures,
so 3 to 5 KB each is the safer guess (6 to 10 MB for 2,000 singles); that part is an estimate, not a measurement,
because no real cover is in the repository.

**Dependency chosen**: stb_image 2.32 and stb_image_write 1.18, two single-file C libraries, public domain or MIT
at the user's choice, both on the allowlist; vendored by hash (`DEPENDENCIES.md` section 11). The licence was not
in doubt, so I did not stop. Their resizer was not taken: scaling is 60 lines of whole-number arithmetic of our own,
which is what makes the bytes the same everywhere. **A judgement to check**: stb_image is not hardened against
hostile pictures. Only JPEG and PNG are compiled in, sizes are checked before decoding, and a failure gives no
cover; Wuffs (Apache 2.0) is the stronger decoder if that is wanted.

**What the Mac window and the iPad app need** (not built, could not be):

- Read `file.cover`; when present show `covers/<hash>.jpg` from the package, else a placeholder. For the
  single-file form, after `CrateArchive.unpack`, or straight from `CrateArchive.read(file)`.
- The Mac's Desk gets covers from the shared run with no change if it builds against this core; the thumbnail is
  then made by `Cover.systemThumbnail` (ImageIO). **That function has never been compiled**: it was written on
  Linux. It needs a build and a look on a Mac first.
- The booth only reads.

**Failed along the way:** the window workflow failed twice (runs 43569575522 and 43570530998) in two older engine
tests that read an event straight after a reply; with one more test running beside them they lost the race on the
runners (never here). They now wait for the event. A third such check failed once more on Windows (run 43571817713) and was fixed the same way. One Windows core
run (43569575464) failed its test step on the same commit; I did not read its log and took it for the same race,
which the later green runs support but do not prove.

**Could not verify:** anything on a Mac or an iPad; the pages' cover drawing in a real web view (the window check
runs in CI only); real covers from real files (every test picture is generated, every tag built by hand); a
library with thousands of covers; ID3 pictures written by iTunes or Serato specifically.

**Not done:** songs read off a music CD get no cover; thumbnails in the work folder are never cleared out; the
packaging of Desk's window was not started, as told.

carry on

**Newest zip, with `.m4a` reading: `pc-package` run 43545418975** (branch `pc/m4a`, commit `665490a`), artifact
`Deckie-for-PC-first-test` (id 14094366437): **122,379,915 bytes**, SHA-256
`4da005fe55bce0d5be43b12d5aba0806185c39c685a565b48c9492215308874d`. It supersedes the one named further down.

## Nov 14, 2026, 02:50 UTC: `.m4a` works on the Windows runner; all three workflows green on `pc/m4a`

**Seen on the Windows runner** (`core-windows` run 43545419066, commit `665490a`; `core-linux` 43545418976 and
`pc-package` 43545418975 green on the same commit):

- 436 tests pass on Windows. The AAC test tone comes back through the decoder at its own length (176,400 frames)
  with its click at frame 88,200, where it was; the same file with its edit list taken out comes back whole, the
  click 1,024 frames late, and marked.
- **A crate file from real `.m4a` files**, built with `deckie-build` from the test track (124 BPM, first downbeat
  at 0.5084 s as a WAV):

  | File | First downbeat | Against the WAV | Flag |
  |---|---|---|---|
  | AAC, 192 kbps (ffmpeg) | 0.5044 s | -4.0 ms | none |
  | Apple Lossless | 0.5056 s | -2.8 ms | none |
  | The AAC file with no stated lead-in | 0.5308 s | +22.4 ms | `start_uncertain` |

  All three are 32 bars at 124 BPM, decoder `media-foundation`. The limit in the check is 5 ms; an untrimmed
  lead-in is 23 ms, which is what the third file shows. The few milliseconds on the first two are the grid fit, not
  a shift of the audio (the decoder test puts the click on its exact frame), but the AAC file's 4.0 ms is close to
  my 5 ms limit, and I have not measured what the same files give on a Mac.

**Failed along the way:** the first Windows run on this branch (43544024924) failed one older test, which expected
every MP4 that is not protected to be unreadable. True on Linux, no longer on Windows; the test now says so.

**Not proven:** Windows 10 and 11 (the runner is Windows Server 2025); a Windows "N" edition; real iTunes
purchases (the `iTunSMPB` reading is tested on a file built by hand, since no iTunes file is in the repository);
HE-AAC (tested as arithmetic only); files with more than two channels.

**Known gap:** a PC that ran an earlier zip keeps its `.m4a` files marked unreadable until its storage folder is
deleted, because a file that could not be read is not tried again while the engine's version is the same. No earlier
zip was handed out, so I left the builder's rule alone.

**Also done:** the letter has a section on packaging the window (`deckie-desk`): what it takes, a PC without
WebView2, the icon. Nothing of it is built.

**Next:** nothing owed. Candidates: WMA (needs a new case in the public format list), a run on a real PC.

carry on

## Nov 14, 2026, 02:05 UTC: branch `pc/m4a` (from `main`), `.m4a` on Windows written, first push

D33 applied: build it, and a file whose lead-in is stated nowhere is accepted with its start marked uncertain.

**Written, tested on Linux where it can be (433 tests pass here), not yet seen on Windows:**

- `core/Sources/DeckieDecode/MP4Audio.swift`: reads what an `.m4a` says about its start and end (the edit list, or
  iTunes' `iTunSMPB` tag; Apple Lossless has no lead-in) and works out what to drop. It drops the lead-in only when
  the decoded length shows the decoder handed back the whole track, as measured; a length that fits nothing is
  refused, not guessed at.
- `AudioDecoder` on Windows reads AAC and Apple Lossless through the Media Foundation shim and applies that trim.
  A Windows without media features (the "N" editions) reports the file as unreadable, in words.
- **The uncertain start uses what the crate file can already say**: the record's `flags` list gains the name
  `start_uncertain`. No field is added or changed, so there is nothing to stop on; the name is written into
  `docs/architecture/crate-format.md`. The PC program counts such songs in its closing words and lists them in
  the log.
- The Windows workflow now builds a crate file from the test track as AAC, as Apple Lossless, and as AAC with its
  edit list taken out, and checks the first two grids against the WAV's (within 5 ms; an untrimmed lead-in would be
  23 ms) and the flag on the third.

**Not done yet:** the note for the letter on packaging the window (`deckie-desk`); WMA, Ogg and Opus stay unread.

**Next:** read the Windows run; fix what breaks.

carry on

**The zip to use: `pc-package` run 43535065527** (commit `21ad255`), artifact `Deckie-for-PC-first-test` (id
14090055016, kept to Dec 14, 2026): `Deckie-for-PC-first-test.zip`, **122,280,833 bytes**, SHA-256
`6e1cd29b2c9cce10c6e0059954612d5ee9bb35f0b036270773f6cbf4e857e480`. Microsoft's runtime included. Earlier zips are
superseded.

## Nov 14, 2026, 01:15 UTC: `.m4a` measured, reported before building; still green

- **Measured on the Windows runner** (`core-windows` run 43536290887, commit `fffaeb7`, all jobs green): Windows'
  Media Foundation does **not** remove the lead-in of an AAC file. On the test tone the click comes out 1,024
  frames (23.2 ms) late and the audio 1,776 frames too long. The file's edit list says both numbers, so Deckie has
  to read it and trim.
- **So `.m4a` is larger than hoped, and is reported, not built**, as asked: two to three days. The plan and the one
  decision it needs (what to do with AAC files that state their lead-in nowhere: refuse them, or accept them with
  the start marked uncertain) are in the letter, "File types on Windows", "Measured since".
- What is in the tree: the shim (`core/Sources/CMediaFoundation`) and the test that pins the measurement. The
  builder does not use them; `.m4a` is still counted as unreadable, in plain words.
- All three workflows are green on `fffaeb7` (`core-windows` 43536290887, `core-linux` 43536290919, `pc-package`
  43536291060). The zip named at the top (run 43535065527) is unchanged in what it does; the newer run's zip
  differs only by the unused shim inside the program.

**Failed:** nothing.

Later the same hour: the test that pins the measurement went in as `702eeac`, and all three workflows are green on
it too (`core-windows` 43538078109, `core-linux` 43538078136, `pc-package` 43538078075). Nothing after it touches
code.

**Next:** waits on the decision above. The branch is ready for the main session to merge.

carry on; consider changing direction on `.m4a` only if refusing files without a stated lead-in loses too many of a
real DJ's files, because then the record needs a new field and that is a format addition

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
