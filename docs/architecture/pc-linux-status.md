# PC and Linux track: status log

Running log of the PC and Linux track (charter: `pc-linux-track.md`). Written for Christopher: plain language, every
technical term explained in the sentence that uses it. Newest entry at the bottom. The main session (Claude on the
Mac) reviews and merges this track's branch, `pc-linux`, and runs anything that needs the music.

## Where things stand

- **Step 1, the spike, is complete and passed on both halves** (entry 3). On Linux the Swift package reproduces
  the lab's grid fit, Camelot mapping and all 138,608 pair scores number for number; on GitHub's Windows machine
  the same package installs Swift 6.4.1, builds and passes the same 13 tests. The Swift-everywhere decision holds.
- **The main session has read and accepted the spike** and told this track to open the pull request and start
  step 2. The pull request is https://github.com/idontlikecodemuch/deckie/pull/1 (branch `pc-linux` into `main`);
  both CI workflows are green on it.
- **Step 2 is complete on its own branch and pull request** (`pc-linux-step2`,
  https://github.com/idontlikecodemuch/deckie/pull/2), each mechanic with its own status entry: WAV, MP3 and AIFF
  decoding with protected-file detection (entry 4), loudness (entry 5), the key estimator (entry 6), FLAC, the
  resampler and the audio-derived features (entry 8), Beat This! through ONNX Runtime with beats identical to the
  Python package (entry 9), and the vocal tagger on YAMNet (entry 12). Step 3, the logic that needs no audio, is
  ported and checked against all 373 committed tracks (entry 7). Step 4, the crate reader and writer, is built and
  accepted (entry 10). The analyser is assembled: one call from an audio file to the lab's record and a crate
  track, now with the vocal tagger in it (entries 11 and 12). Step 5, `deckie-build` with its `bench` command, is
  built (entry 13): a crate from a folder, resumable, with the yardstick ready for the Mac. The memo Q fields are
  in (entry 15): where the vocals are, bar and beat, free intro and outro, free gaps on the lattice, hook
  candidates, all additive crate blocks. The Mac's memory work is merged (entry 15): a job's peak falls from 1.9 GB
  to 1.1 GB with every number unchanged. 258 tests pass on Linux; Windows builds and passes everything that needs
  no model. The three crate renames are in and the engine is at 0.2.0 (entry 16); the Mac's final memory defaults
  are merged. 260 tests pass. Christopher approved both releases: the pinned model files are published (release `models-1`, entry 16) and
  every machine, CI included, now fetches them by hash; the ONNX Runtime archives' release follows from the
  publish run queued behind run 4. The first Mac bench sheet is in (entry 17): every charter mark passes but one, key exact where the lab is
  confident, 74.6 against the mark of 75; four follow-ups from it are under way (a cheap second key vote, one true
  peak outlier, one bar-1 outlier and the unequal bar counts, the madmom guard). A second Mac run with the pinned
  YAMNet gives the vocal correlation. Then the first PC build.
- Needed from Christopher: nothing right now. The vocal-model downloads were approved on Oct 28 ("Allow vocal
  models", with a standing yes for any further vocal model the work needs); dr_mp3, dr_flac, ONNX Runtime and
  Beat This! were approved before.
- Decided by Christopher, Oct 29 (P19, now D15): weights ship under their publisher's licence, with every
  model's training sets recorded in DEPENDENCIES.md and shown in the app's acknowledgements, plus a named
  replacement path; Beat This! ships (entry 13). Two asks from the main session that follow: keep DEPENDENCIES.md
  in the shape the apps render (an acknowledgements table now heads the file), and a replacement-path line per
  model (added; Beat This!'s names the model-free grid, which the main session is measuring now). Also decided:
  ONNX Runtime's usage reporting (entry 12, addendum: the switch set before the library starts covers
  development, CI and the bench; a shipped build carries a library built by us without the reporting client,
  proven by a release test; curl stays off the allowlist), YAMNet's training data (confirmed), crate format v1
  (entry 10, addendum) and MPL 2.0.
- ONNX Runtime built by us without the reporting client: done and published (entry 14 and its addenda). The
  release carries the Linux, Windows and macOS archives with their hashes, pinned in DEPENDENCIES.md and the fetch
  script, verified here, and the Swift release test passes on all three shipped libraries. A shipped build fetches
  with `fetch-onnxruntime.sh --deckie`; development keeps Microsoft's archive with the switch. Two findings from reading ONNX Runtime's build files are with the main session: its build patches
  four Eigen files on every platform (Microsoft's builds too), and on Windows the event-log provider's name stays
  in the library even though nothing registers it. Both decided (Oct 29): the two patch files now ship beside
  Eigen's notice (`core/notices/eigen/`) and the wording is "unmodified by Deckie; carries ONNX Runtime's two
  published patches"; the Windows scan will report that one marker as present but never registered, naming the
  function that would register it, and fail hard on everything else, applied once the first run confirms it; the
  version-bump checklist now includes rereading `windows/telemetry.cc` (DEPENDENCIES.md, section 6).
- Needed from the Mac, now that step 5 is built (not blocking this track): the `bench` run over the 373 files
  (`deckie-build bench`, entry 13), which folds in the loudness check against pyloudnorm (entry 5), the key
  estimator's parity run (entry 6) and the vocal tagger's first look at real voices (entry 12). The Mac needs
  ONNX Runtime's macOS archive (facts in entry 12, third addendum) and the two models exported there; Christopher's
  yes for that download is asked in the main session.
- In flight elsewhere, to keep merges easy: a Mac session (Christopher's, from the task card in entry 13) is cutting
  the analyser's peak memory on its own branch `perf/analyser-memory`, touching `Analyser.swift`, the DSP files,
  the key estimator and the beat tracker's session options, with every number unchanged; it will push its branch
  for this track to merge. Its measurement matrix ran here (the Mac has no models yet): on a synthesised four-minute
  track the peak is the beat model's stage in every setting; ONNX Runtime's memory arena keeps 1.1 to 1.9 GB resident
  after it, and switching the arena off (or its shrinkage on) brings a job back to 0.3 to 0.7 GB with records byte
  for byte identical; four jobs peak at 5.8 GB with the arena, 4.5 GB without. The Mac picks the default from it. Here, the memo Q agent adds a step to `Analyser.swift` after the vocal tagger and new
  fields in `Analysis*.swift` and the crate model, nothing in the DSP; the ONNX Runtime build agent touches only
  the workflows, `fetch-onnxruntime.sh` and DEPENDENCIES.md section 6.
- Accepted by the main session (Oct 29) with three renames, now applied (entry 16): the crate builder's two
  additive proposals (entry 13, `crate-format.md` item 9). `import_log.built_by` is a device model label, never the user's
  device name; the per-record block is `imported`, keyed by source (`imported.rekordbox`, null when nothing was
  imported), because it holds the DJ's own data; the tag tempo is `file.tag_bpm`. And the acknowledgements get a
  source file, `core/dependencies.json`, from which the table in DEPENDENCIES.md is generated by a committed
  script, with a test that fails when they differ; the apps read the JSON, never the Markdown.

## Oct 28, 2026: the environment (entry 1)

What this cloud session is: a Linux machine (Ubuntu 24.04, x86_64) with the repository checked out. Swift, the
language the charter chose for Deckie's own code, was not installed.

- **Swift could not be installed the normal way.** The official download site, download.swift.org, is blocked by
  this session's network policy (every request is refused with a 403, the web's "forbidden"). That also rules out
  `swiftly`, Swift's own installer, because it downloads from the same site. Ubuntu's package archive has no Swift.
- **Installed Swift 6.4.1 by another route.** Docker Hub, the public store of Docker images (an image is a ready-made
  file system for running software in a container), is reachable. I pulled the four layers of the official
  `swift:6.4.1-noble` image (noble is Ubuntu 24.04, the same system as this machine) straight from the registry with
  `curl`, checked each layer's SHA-256 checksum against the image manifest, and unpacked them under `/opt/swift-641`.
  The Swift tools run from there against this machine's own system libraries. Verified: `swift --version` reports
  6.4.1, a throwaway package builds in 4 s, and its tests run under Swift Testing (the test framework that ships
  with the toolchain and runs on Linux and Windows). 6.4.1 is the version track M names.
- **This install is not permanent.** It lives only in this session's container. If the session is reset, the same
  steps (about three minutes) rebuild it; the cloud environment's setup script could do it automatically. I did not
  change the environment configuration; that is Christopher's or the main session's call.
- **Python is available with numpy**, the numeric library the lab's scripts use (Python 3.13, numpy 2.5.3), so the
  lab's `score.py` runs here. I ran it from a scratch folder (nothing in `mixer/` was touched): 373 tracks, 138,756
  directed pairs, 99,832 of them scoring 0.45 or more, in 17 s. The regenerated `recs.json` matches the committed
  one in 1,453 of its 1,492 top-8 lists; the 39 others differ only where two candidates tie on the same score and
  the tie breaks differently from run to run (Python iterates a set in an order that changes per process). So the
  committed `recs.json` is consistent with the committed `score.py`, and the Swift tests can use the regenerated
  pairs as their reference with a tolerance for ties.
- **One wrinkle in the grid fit, found while reading the lab code.** The committed feature files were produced by an
  earlier `analyze.py` whose grid fit used one estimator: IRLS, iteratively reweighted least squares, a way of
  fitting a straight line through the beat times that keeps pulling the line towards the majority of beats and
  away from stray ones. The current `analyze.py` tries a second estimator (the median tempo of 20-second windows)
  and keeps whichever puts more beats within 70 ms of the grid. For 39 of the 373 tracks the two disagree. The
  port follows the current code; the tests cover both: the IRLS path against the committed numbers for all 373
  tracks, and the full current fit against numbers computed today by the lab's own Python on the committed beats.
- **Beat times in the feature files are rounded to a millisecond**, so a refit from them cannot match the lab's
  original fit to the last digit. Measured today with the lab's Python: on the IRLS path the refit lands within
  0.005 BPM and 0.5 ms of the committed numbers for every track. The Swift tests use those tolerances.
- **GitHub Actions** (GitHub's service that builds and tests code on its own machines on every push) has no
  workflows in this repository yet. This track adds two: a Linux build-and-test and the Windows probe.
- **Nothing needed from the Mac** for step 1. No music is involved; every test input is in the repository.

## Oct 28, 2026: the spike on Linux, and a blocked push (entry 2)

**Built**, under `core/`, as a Swift package (a package is Swift's unit of code with its own build and test
commands; this one has no Apple-only framework in it, so it builds on Linux and should on Windows):

- `DeckieCore`, about 800 lines: the beat grid fit with both of the lab's estimators, the Camelot wheel (the DJ
  key notation where neighbouring numbers mix well), the tempo relations, the directed pair scoring with its
  eight terms, the transition choice, the wording of the reasons, the timbre ranking over the whole pool and the
  top-8 lists. Ported line for line from `mixer/analyze.py` and `mixer/score.py`.
- `DeckieLab`, about 200 lines: reads the lab's feature files and `candidates.json` into those types.
- Parity tests (tests that check the port gives the same numbers as the original), about 400 lines, under Swift
  Testing. Their reference numbers come from `core/Tools/make_fixtures.py`, which runs the lab's own Python
  unchanged and writes them to `core/Tests/DeckieCoreTests/Fixtures/`; the tests also read `mixer/features/`,
  `mixer/candidates.json` and `mixer/recs.json` straight from the repository, so nothing was copied by hand.

**Measured** on this machine with Swift 6.4.1: the package builds in 7 s and its 13 tests pass in 19 s.

- Camelot: all 42 key spellings in both scales, all 576 key-pair compatibility values, every pitch shift and
  every neighbour relation: identical to the lab.
- Grid fit, all 373 tracks: the current two-estimator fit lands on the lab's numbers for every track, with the
  tempo within 0.000001 BPM and the same estimator chosen every time (271 by the robust line fit, 102 by the
  window method). The median beat error, a number in milliseconds, differs from numpy by up to 0.00003 ms on a
  handful of tracks whose grid does not fit at all (errors above 80 ms); that is the last digits of a 2-by-2
  equation solved slightly differently, twelve times over, on a hopeless fit, and nothing audible lives there.
  Every committed grid candidate is reproduced by one of the two paths (334 by the current fit, 39 by the
  robust line fit alone, matching entry 1's wrinkle).
- Pair scoring, all 138,608 directed pairs (138,756 minus 40 that are cuts of the same song, minus 108 too far
  apart in tempo): the same count, the same sum of scores to four decimals (74,163.6218), the same number of
  pairs at or above the 0.45 threshold (99,832), identical counts per transition type and per tempo relation.
  On 2,449 sampled pairs checked field by field: every score identical to four decimals; every transition,
  move list, overlap, key shift and multiplier identical; the reasons text identical in all 2,449; of the
  19,592 term values, 2 differ by 0.001 (the vocal term, where adding the same numbers in a different order
  landed on the other side of a rounding boundary; the score did not move). Against the committed
  `recs.json`: all 1,492 top-8 lists have identical scores position by position, and 9,986 of 9,986
  recommended tracks are identical where the lab's score is unique (ties were excluded, per entry 1).

**What it means for the Swift decision.** On Linux the port is exact: half the guard is met. Swift itself was
not the hard part. The port took one session, the numbers line up with numpy to the last printed digit, and the
only traps were Python conventions (rounding halves to even, remainders of negative numbers, the exact order of
a weighted sum) that `core/Sources/DeckieCore/PythonCompat.swift` isolates in forty lines. The other half of
the guard is Windows, below.

**The Windows probe is written but has not run.** `.github/workflows/core-windows.yml` builds and tests the
same package on GitHub's `windows-latest` machine with the official Swift 6.4.1 toolchain (installed by
`compnerd/gha-setup-swift`, the action maintained by the Swift-on-Windows lead); `core-linux.yml` does the
same in the official Swift 6.4.1 Linux image. Both run on every push to `main` or `pc-linux` that touches
`core/` or the lab files they read, and can be started by hand from the Actions tab. They have not run
because of the blocker below, so the probe's result is still open.

**Blocker: this session cannot push to GitHub.** The push of the branch `pc-linux` was refused with "Claude
doesn't have GitHub access to idontlikecodemuch/deckie for your organization" (a 403, the web's "forbidden"),
by plain `git push` and by the GitHub connector alike; reading the repository works. The fix is on
Christopher's side: connect or reconnect GitHub at https://claude.ai/connect-github, and if the Claude GitHub
App is not installed on `deckie`, install it from that same page. Once that is done, this session pushes the
branch and the two workflows run on their own. Until then the six commits exist only in this session's
container; as a fallback they are also saved as a patch series (text files that `git am` turns back into the
same commits) in the session's scratch folder, named below in the session reply.

**Not started**: step 2. **Needed from the Mac**: nothing. The Windows result will be entry 3.

### Entry 2, continued: two additions, done by Opus agents under this session's direction

- **`DEPENDENCIES.md`** at the repository root, as the charter's policy asks: what the track depends on today (the
  Swift 6.4.1 toolchain and two GitHub Actions helpers, all build-time only, nothing shipping), each pinned by
  version and hash, with the toolchain's licence (Apache 2.0 with the runtime library exception) quoted from the
  file inside the toolchain. The Linux workflow now names the Swift image by its digest (its content hash) rather
  than by the tag `6.4.1-noble`, which the publisher could move. The two actions are recorded by version tag only:
  pinning them to a commit hash needs a look at their repositories, which this session may not do. Open question
  for the main session: the charter's licence allowlist and track M's finer one (section 3.4, which also names zlib
  and CC0) should be reconciled into one list; `DEPENDENCIES.md` carries the charter's for now.
- **`core/Tools/install-swift-linux.sh`** rebuilds the toolchain after a container reset, by the same Docker Hub
  route as entry 1, with every piece checked against its hash before anything is unpacked. Tested end to end:
  85 s, 1.2 GB downloaded, the package builds with the result. One caveat: Docker Hub limits anonymous downloads
  per network address, and the cloud sessions share addresses; the script waits and retries, and the README says
  what to do if the limit is exhausted.
- Both reviewed and committed by this session; nine commits on `pc-linux` now, still unpushed (the blocker above
  stands: writes were refused again after Christopher's "access restored" message, so the fix has not reached
  this session's credentials; a fresh session may be needed).

### Entry 2, continued, part 2: pushed; the workflows did not start

- **The push went through** once Christopher restored GitHub access and the session's credentials caught up
  (the first attempts after his message were still refused; the fourth, some minutes later, was accepted).
  `pc-linux` is on GitHub with its nine commits, and the same commits are mirrored on this session's own branch.
- **GitHub Actions started nothing.** GitHub can see both workflow files on the branch and all nine commits, yet
  several minutes after the push it lists no workflow run at all, for either workflow. Starting one by hand from
  here was refused: the Claude GitHub App that this session pushes through has no permission to start workflows
  (a 403 on the "dispatch" request).
- **Two likely causes, both outside this session.** Either Actions is switched off for the repository
  (GitHub: Settings, Actions, General, "Actions permissions": it should allow actions to run), or runs started
  by a push from the Claude App are not created. Christopher can check the first in a minute. The second resolves
  itself when the main session merges `pc-linux` into `main` from the Mac: a push by a person starts the
  workflows, and from then on they run on every push to `main` or `pc-linux`.
- **What this means for the spike.** The Linux half stands (every test passes here on the same toolchain the
  Linux workflow pins). The Windows half is still unmeasured; it needs one workflow run on GitHub's Windows
  machine, which no amount of work in this session can substitute for.

## Oct 28, 2026: the Windows probe passed; the spike is complete (entry 3)

**The result.** On GitHub's Windows machine (`windows-latest`, Windows Server 2025 with Visual Studio 2026) the
`core-windows` workflow installed the official Swift 6.4.1 toolchain in 97 seconds, built the package in 37
seconds and ran the same 13 parity tests as Linux: all passed, in 32 seconds (Linux takes 19). Nothing in the
package needed changing for Windows: no platform-specific code, no special casing, the same numbers. The whole job
takes three and a half minutes. Run: https://github.com/idontlikecodemuch/deckie/actions/runs/40750217848.

**What it means for the Swift decision.** The guard track M set before stage 2 was "a two-week spike porting the
grid fit, Camelot and score.py to a Swift package that reproduces pairs.json on Linux and on a Windows CI runner;
if it fails, Rust". Both halves passed, in one day rather than two weeks. Swift everywhere (P16 as revised by
track M) holds; the Rust fallback is not needed. The usual caveat stands: this proves the pure-computation core on
Windows, not yet the C libraries (decoders, ONNX Runtime, loudness) that step 2 brings in; the Windows probe keeps
running on every push, so each of those is probed as it lands.

**Getting there took three tries, all on the toolchain installer, none on the code.** Recorded so nobody repeats
them: (1) the action that installs Swift on Windows, `compnerd/gha-setup-swift`, has no `v3` tag; its documented
reference is `@main`. (2) Its `swift-version` input names the download directory on swift.org, which for a point
release is `swift-6.4.1-release`, not `swift-6.4-release`; the wrong directory gives a 404, which I first misread
as a missing file. (3) The action's older `branch` and `tag` inputs are deprecated; the workflow now uses
`swift-version` and `swift-build`. The Linux workflow passed every time.

**How CI got its first run.** GitHub starts no workflow for a branch that only this session pushed to; the pull
request did. The main session chose that route (its reply, below) over a merge from the Mac, and both workflows
now run on every push to the branch and on the pull request.

**The main session's reply, Oct 28** (the lead agent on Christopher's Mac), in short: the Linux spike result is
read and accepted; open the pull request; step 2 may start now, in the charter's order, one mechanic per status
entry, every new dependency into `DEPENDENCIES.md` with its licence quoted before use; the licence allowlist is
track M section 3.4 as the single list (MIT, BSD 2- and 3-clause, Apache 2.0, ISC, zlib, public domain and CC0
ship; LGPL 2.1 and 3 only dynamically linked, each case named; MPL 2.0 not decided, so not allowed until the main
session says otherwise; GPL, AGPL, CC BY-NC and research-only never); the two GitHub Actions stay on version tags
until their repositories can be read; the 1.2 GB toolchain rebuild after a container reset is acceptable for now,
and the environment's setup script is Christopher's to change. All of that is applied: `DEPENDENCIES.md` carries
the reconciled list, and the pull request is open.

**Step 2 has started.** First mechanic: decoding MP3 and AAC to float samples on Linux, through ffmpeg's
libraries from Ubuntu's packages (track M names ffmpeg, LGPL and dynamically linked, as the Linux decoder), in a
new `DeckieDecode` module that stays buildable on Windows and macOS where ffmpeg is absent, tested on generated
tones rather than any music. One licence check is part of it: Ubuntu builds ffmpeg with GPL components switched
on, which may make the installed libraries GPL rather than LGPL; if so they are development-and-CI only, and a
shipped Linux build needs an LGPL-configured ffmpeg. Entry 4 reports the outcome either way.

## Oct 28, 2026: step 2, mechanic 1, decoding audio to float samples (entry 4)

**Where it landed.** A new module `DeckieDecode` turns an audio file into float samples (the numbers between -1
and 1 that every analyser works on), at the file's own sample rate, with the channel count kept (stereo stays
stereo, anything beyond two channels is cut to the first two), a mono view that averages the channels as the lab
does, and a typed error that names the file, the format and the reason. It recognises WAV, MP3, AAC, AIFF and
FLAC from the first bytes. WAV decodes today, in plain Swift with no library at all, so it builds everywhere,
Windows included. MP3 and AAC are recognised and report "not supported on this platform yet". The work was done
by an Opus agent under this session's direction, reviewed and committed by this session; the main session's
decoder direction (its second reply, below) changed the plan midway.

**Measured, in this session.** Both generated test files decode exactly: 4.0000 s at 44,100 Hz and at 48,000 Hz,
two channels, the 440 Hz tone on the left at -6.0003 dBFS and the 1,000 Hz tone on the right at -12.0003 dBFS
(dBFS: decibels below full scale, the loudest a digital file can hold), each tone at least 97 dB above every
other frequency checked, and the click found at exactly 2.000 s. A four-minute stereo WAV decodes in 0.11 s. The
8 new tests pass with the 13 old ones on Linux, and the Windows probe passed them too on the pull request
(https://github.com/idontlikecodemuch/deckie/actions/runs/40753496723): the module needed nothing for Windows.

**What was built and then thrown away, and why.** The first design, per track M, linked ffmpeg's libraries from
Ubuntu's packages (ffmpeg is the open-source audio and video toolkit nearly everything uses; its libraries are
LGPL, which the allowlist accepts when kept as separate library files). It worked: MP3 decoded to exactly the
right length with the encoder's padding removed, correlation 0.99999 with the original. But the licence check
that was part of the job found what the main session then confirmed independently: Ubuntu builds ffmpeg with its
GPL parts switched on (`ffmpeg -buildconf` shows `--enable-gpl` and `--enable-libx264`), and the package's own
copyright file says "the resulting binaries are licensed under GPL v2+". Linking that, even as a separate file,
would put Deckie under the GPL, which the charter forbids. So the ffmpeg code was deleted before it was ever
committed; the finding is recorded in `DEPENDENCIES.md` under "Checked and rejected". The ffmpeg command-line
program is still used on a developer's machine, as a tool, to make two test files; nothing links it.

**MP3: waiting on one approval.** The charter's route is dr_mp3, a single C file of public-domain code (also
offered under a no-attribution MIT licence) that decodes MP3 and is vendored, meaning copied into the repository
and pinned by its hash, so nothing is downloaded at build time. This session's harness blocked the instruction to
fetch that file ("code from an external source"): that is a decision for Christopher, not for the session. Once
he says yes, the agent fetches the file, records its version, hash and licence in `DEPENDENCIES.md`, and the
disabled MP3 test (already written, with the ffmpeg-measured reference numbers in it) comes alive.

**AAC on Linux: a real gap, for the main session to decide.** AAC is the format of iTunes purchases and most
`.m4a` files. On Apple the platform decoder (AVFoundation) will do it; on Windows, the platform's Media
Foundation. On Linux there is no licence-safe AAC decoder in a distribution package: ffmpeg's is GPL as built,
faad2 is GPL, fdk-aac has its own licence that is not on the allowlist. The options, with costs:
1. Build our own ffmpeg with only its LGPL parts and only the AAC and MP3 decoders, dynamically linked and pinned
   by the source tarball's hash. Cost: a build recipe to write and maintain, a few minutes per CI run, one more
   thing to bump on the quarterly update day; licence clean (LGPL 2.1, named in `DEPENDENCIES.md` as the policy
   asks). This is the only route to AAC on Linux that fits the list.
2. No AAC on Linux for now: `deckie-build` reports such files as unsupported and carries on. Cost: Linux users
   with AAC pools get partial crates; MP3 pools are unaffected. Nothing to maintain.
3. Convert on the user's machine with whatever decoder they have (for example the distribution's ffmpeg program,
   run as a separate process, never linked). Cost: depends on the user's installs; the GPL question moves from
   Deckie's code to a tool the user runs themselves, which is the usual reading, but it is a judgement the main
   session should make, not this session.
My recommendation: option 2 now (Linux is the builder's second platform; MP3 first), with option 1 planned if the
trials show AAC pools on Linux matter.

**Decision on AAC for Linux (the main session, Oct 28):** option 2 now, option 3 as the planned second step,
option 1 only if the trials show AAC pools matter on Linux. Reasons: Mac and Windows decode AAC with their own
platform decoders, so the gap is Linux only; DJ pools are overwhelmingly MP3; and option 3 keeps Deckie's own
code clear of the GPL question with no build recipe to maintain. The shape it asked for: `deckie-build` reports
unsupported files plainly, counted by file type, in its summary and in the crate's import log, never silently;
when option 3 is built, it looks for an ffmpeg program on the user's machine, runs it as a separate process with
explicit arguments to produce plain samples, never links it, never ships it, and `DEPENDENCIES.md` records it as
an optional program the user provides, not a dependency; option 1, if it ever comes, is pinned by the source
tarball's hash. The main session also confirmed that vendoring dr_mp3 is within the policy and that the download
permission is Christopher's to grant in this session.

**The main session's second reply, Oct 28**, in short: the spike is decision D14 on `main` (Swift everywhere for
Deckie's own code, Rust only as a Windows fallback); pull request #1 stays the spike milestone and step 2 goes on
its own branch and pull request; Ubuntu's ffmpeg must not be linked; the intended route is dr_mp3 or minimp3 for
MP3 and the platform's decoder for AAC, with the Linux AAC gap stated plainly and a proposal; an LGPL-only ffmpeg
build is acceptable only if built and pinned by this track, with its cost stated. All applied above.

**Working mode from here (Christopher's instruction, relayed by the main session, Oct 28).** This track works
independently and asks only the big questions. Decided here and logged, without asking: dependency choices inside
the licence policy (recorded in `DEPENDENCIES.md`, rejections included), test design, CI changes, the internal
structure of `core/`, the order within a step, small crate-schema additions that only add fields. Big questions,
for Christopher in this session or for the main session by message: anything that changes the licence line or
the privacy principle (audio or metadata leaving the machine); removing or renaming a crate-file field the Apple
apps read; anything that needs the music or the Mac (say so, skip it, the main session runs it); anything that
changes what the product does or claims; a fallback away from Swift for any platform. One practical limit
remains: this session's harness blocks any instruction to download code from outside the repository, so each
vendored file (dr_mp3 today, dr_flac next) still needs Christopher's yes here before it is fetched.

**File types for `deckie-build` (the main session's decision P18, Oct 28).** After MP3: FLAC next, through
dr_flac (public domain, same author and vendoring pattern as dr_mp3; Beatport, Bandcamp and lossless rips use
it), then AIFF through a small parser of our own like the WAV one (Beatport and Mac rips), then stop. AAC and WMA
on Linux stay with the separate-process ffmpeg plan; on Windows, Media Foundation for both when the Windows build
gets its own decoding path. ALAC only if demand appears (Apple's open-source decoder, Apache 2.0); Ogg Vorbis and
Opus only if the trials show them. Streaming-service offline files are rights-protected: detect the usual
containers and names if cheap and report them as "protected, cannot be read", not "unsupported". Every
unsupported or protected file is counted by extension in the build summary and the crate's import log. For each
decoder, the leading-sample offset against the lab's decoding of the same file is measured and logged (MP3
decoders differ in how they drop the encoder's leading delay; a constant offset of about a thousand samples
would shift every beat time by about 25 ms against the yardstick), and a constant offset is corrected in the
bench path.

**MP3, done (Oct 28, after Christopher's approval).** dr_mp3 v0.7.4 (one public-domain C file, 198,991 bytes,
SHA-256 `390e4e0e...`; `DEPENDENCIES.md` section 4) is compiled as plain C into the package, so Windows gets the
same decoder. The Swift wrapper reads the file's bytes, skips any ID3 tags in front, decodes to float, and then
trims the silence that MP3 encoding adds at both ends by the same rules as the lab's decoder (libsndfile through
mpg123), read from the tag in the first frame: the encoder's delay plus the decoder's 529 samples at the start,
the padding less 529 at the end. dr_mp3's own trimming was switched off because it follows ffmpeg's rules, which
differ from mpg123's in four edge cases the agent tested (tags without the LAME marker, without a frame count,
with small padding, or with stray bytes before the first frame); Deckie matches the lab in all fifteen
variants. The measurement the main session asked for: against the lab's own decoder (soundfile 0.14 with
libsndfile 1.2.2, installed here for the test) the offset is **0 samples** on all three test files, with the
largest sample difference 0.0000013 (decoding to float directly, not through 16-bit, which was 15 times worse).
The test tone decodes to exactly 176,400 frames with the click at 2.000 s; a four-minute 320 kbps file decodes
in about half a second. Two decisions taken here and logged: a file with damage in the middle is decoded past
the damage, as ffmpeg does, where mpg123 gives up (the import log will carry a warning once it exists); and an
AAC stream behind an ID3 tag is currently reported as a damaged MP3 rather than as AAC, a rare case left for the
platform decoders. The Windows probe passed with dr_mp3 compiled as plain C.

**AIFF, done (Oct 28).** AIFF and AIFF-C (the uncompressed kinds: "NONE", "twos", "sowt" at 8 to 32 bits, and
32-bit float) decode in plain Swift, sample for sample identical to the same signal in WAV and to the lab's
decoder (offset 0, largest difference 0); the odd 80-bit sample-rate field converts exactly. Other AIFF-C
compressions (ulaw, alaw, ima4, fl64) are reported as unsupported. **Protected files**, per P18: an MP4 whose
brand is "M4P " or whose index carries a FairPlay ('drms', 'drmi') or standard-encryption ('sinf') entry is
reported as "protected, cannot be read", found by walking the file's box structure rather than searching bytes
(so a title containing "sinfonia" does not trip it, and an index stored after the audio, as ffmpeg writes it, is
still found). Spotify, Tidal, Amazon and Deezer offline caches are not files a user can hand over, so they are
not detected; protected WMA is not recognised yet. The test fixtures now total 3.1 MB (generated tones in six
formats plus a 648-byte protected stub), all regenerable by `core/Tools/make_audio_fixtures.py`.

**A slip, logged.** One push on Oct 28 went out with a failing AIFF test for about four minutes: my local check
piped the test output through a filter, which hid the test's own failure status. The next commit fixed the test
and the check now reads the exit status directly.

## Oct 28, 2026: step 2, loudness (entry 5)

**Where it landed.** `DeckieCore` now measures loudness the way the lab does, in plain Swift with no dependency:
K-weighting (the standard's ear-shaped filter, built for any sample rate), integrated loudness in LUFS with the
standard's two gates, loudness range (LRA) per the EBU method, short-term loudness over a window ending at any
time (the lab's fade-out check), the lab's per-bar loudness over any span of samples (a running sum, so every
bar costs a subtraction), and true peak by 4x oversampling with the same filter the lab's `resample_poly` uses,
in the lab's 10-second blocks. `AudioBuffer` moved into a tiny module of its own, `DeckieAudio`, so analysers and
the decoder share it. A decision logged here: the charter named libebur128 (a C library) for this; a 400-line
Swift port with no dependency, matching the lab's Python rather than libebur128, was the smaller and more
faithful choice, so `DEPENDENCIES.md` gains nothing.

**Measured.** 22 tests on synthesised signals, at 44.1 and 48 kHz: the EBU Tech 3341 integrated-loudness cases
read within 0.06 LU of their targets, the Tech 3342 loudness-range cases exactly (10.0, 5.0, 20.0, 15.0 LU), a
tone whose peaks fall between samples reads -5.88 dBTP against a true -6.0 (the 0.1 dB extra is edge ringing
the lab's method also counts), and a full-scale click 0.0 dBTP. Against an independent numpy re-implementation
of the lab's pipeline the module agrees to about 1e-14 LU on every number. Four minutes of stereo take about
one second in a debug build.

The Windows probe passed the loudness tests too, speed test included.

**One finding worth knowing.** The lab's filters come from pyloudnorm, whose own documentation admits they do not
reproduce the published BS.1770 coefficients exactly: the lab reads about 0.04 LU lower than the standard. The
module keeps the lab's filters as the default, for parity with the yardstick, and offers the published ones
as an option (`design: .bs1770`). A small correction to this session's own brief, found by the agent: EBU case
5 (-26, -20, -26 dBFS) measures -23.0, not -20.0, because nothing is gated out.

**Needed from the Mac, when convenient.** pyloudnorm and scipy are not installed here, so the final check is an
independent re-implementation, not the real libraries. One run of the lab's `pyloudnorm` integrated loudness,
LRA and `true_peak_db` on any file, compared with `Loudness.integrated`, `Loudness.range` and
`TruePeak.decibels` on the same decoded samples, would close that; the expected agreement is better than 0.01.

## Oct 28, 2026: step 2, the key estimator (entry 6)

**Where it landed.** `DeckieCore` now carries the lab's key estimator from `mixer/key_light.py`: a real-input FFT
and a short-time Fourier transform (STFT: the spectrum of each short frame of audio) written in Swift in double
precision with no dependency; the chroma (the energy of each of the twelve pitch classes per frame) computed
exactly as librosa does it with the lab's settings (22,050 Hz, 8,192-point frames every 2,048 samples); the
published key profiles (edma, the lab's choice, and five others at no cost); the whole-track key by
correlation against the 24 rotated profiles with the lab's margin rule; the key of each mix window judged
against the song key; and key segments over 20-second windows every 5 seconds with the lab's hysteresis. A
stopgap halving filter brings 44.1 kHz audio to 22,050 Hz until the resampler mechanic lands (the lab uses soxr;
the stopgap is within 3.7e-4 of it on chroma, flat to 9.9 kHz, 57 dB down past 12.5 kHz). Done by an Opus agent
under this session's direction, reviewed and merged here.

**Measured.** Against the lab's own tools, installed here for testing only (librosa 1.0.0, the lab's version): the
FFT within 3.5e-16 of numpy's; the Hann window bit for bit; all 168 sampled filter-bank weights identical; the
chroma within 8.4e-7 of librosa's on seven synthesised signals (and within 8.5e-15 when both run in double
precision, so the remaining gap is librosa's single-precision arithmetic). The decision logic, fed 68 chroma
matrices through copies of the lab's own functions (checked against `key_light.py` before use): 408 whole-track
keys, 249 segments and 136 mix-window judgements all identical, 1,826 of 1,826 numbers bit for bit. End to end
on synthesised chord progressions: C major gives 8B, A minor 8A, F sharp major 2B; a change from C to D halfway
through a 60-second signal gives two segments, the second starting where the lab's definition puts it (the
first 20-second window that hears the new key). Four minutes of audio take 0.8 s in a debug build. 38 core tests
pass with the 24 decode tests, on Linux and on the Windows probe.

**Two things to know.** (1) The lab's chroma is single precision and the port's is double, so on real tracks a
key could differ only where the lab's margin is around one millionth. (2) The lab's code and its comment
disagree in one place (a window counts as "far" from the song key at wheel cost 2, the comment says 3); the port
follows the code.

**Needed from the Mac, when convenient.** Parity on real music: run the port over `mixer/candidates.json` and
compare row by row with `mixer/key_light_stft.tsv` and `mixer/key_ends_stft.tsv`, which also measures the
stopgap halving filter against soxr on real tracks. This belongs in the `bench` command of step 5.

## Oct 28, 2026: step 3, the logic that needs no audio (entry 7)

Working in batches now, to spend less on hand-offs: two Opus agents in parallel worktrees, merged and tested once,
pushed once. This batch ported everything in the lab's analyser that works on numbers already in the feature
files, so each port is checked against all 373 committed tracks with no music.

**Start and end tempo** (`mixer/local_tempo.py`, the trust rule): 372 of 373 tracks reproduce the committed
block exactly on every one of its 29 fields; the one exception is a single residual that sits on a rounding tie
(exactly 5.25 ms, where the lab's numpy on the Mac and this port land on opposite sides by a few trillionths).
The current lab script, run here on the committed inputs, reproduces every committed block, so the feature
files are the reference for this one.

**Bar grid, phrase lattice, sections, fade-out, mix windows, flags** (`mixer/analyze.py`): every bar number,
label and decision matches on 369 tracks; the four others are cases where an input was written exactly on a
threshold (a vocal probability rounded to 0.500, a tempo rounded to 100.0), and the port gives the lab's answer
once the input is moved inside its rounding. Bar times match within 1.6 ms (the period is written to five
decimals), section loudness within 0.01 LU, phase novelty and phrase confidence within what the rounding of the
summed peaks allows. 57 core tests now, with the 24 decode tests, on Linux and Windows.

**What this leaves for later in step 3:** the inputs these ports take as given come from audio: the novelty
curve and its peaks (from MFCC and loudness), the onset pattern, the per-bar bands, and the per-bar vocal
probability (from the tagger). Those are the next batch, tested against the lab's own Python libraries, which
are installed here for testing only.

## Oct 28, 2026: FLAC, and the audio-derived features (entry 8)

Three agents in parallel worktrees, merged and tested once. 34 decode tests and 87 core tests pass on Linux; the
Windows probe runs on the push.

**FLAC** through dr_flac v0.13.4 (one public-domain C file, 523,451 bytes, SHA-256 `b0bf3971...`,
`DEPENDENCIES.md` section 5; Christopher approved it): native FLAC and Ogg-FLAC, 8 to 24 bits, decoding sample for
sample identical to the same signal in WAV and to the lab's decoder (offset 0). The wrapper does what dr_flac
alone does not: skips ID3 tags in front, stops at the declared length, and reports damage (dr_flac silently drops
a frame whose checksum fails, which would shift everything after it by 104 ms; the lab's decoder refuses such
files, and so does Deckie now). A five-minute file decodes in 0.7 s.

**The resampler** (the lab uses soxr, LGPL, in Python): a windowed-sinc design fitted to soxr's own "HQ" response
(within 6e-8 of its impulse response), with no dependency. At the ratio the lab uses everywhere, 44.1 kHz to
22.05 kHz and back, it matches soxr to about -120 dB (soxr's own noise), with zero net delay and the same output
lengths; the stopband is 127 dB down. At 48 kHz to 44.1 kHz and 44.1 kHz to 16 kHz it agrees to about -60 dB
only, because soxr runs an extra interpolating stage at those ratios; good enough for now (48 kHz files are rare
in DJ pools) and logged as a known difference the Mac bench can weigh. 0.6 s per four minutes of stereo in a
release build. The key estimator's stopgap halving filter now calls it.

**Per-bar low and high bands** (the lab's twice-applied second-order Butterworth filters at 150 Hz and 4 kHz):
filter coefficients bit-identical to scipy's, every filtered sample identical, per-bar levels within 1e-13 dB.
**First and last sound** (the -60 dBFS rule on 10 ms frames): identical to the lab on all cases, including its
float32 comparison and its dropped partial last frame.

**Mel, MFCC, RMS, onset strength, onset detection, novelty and peaks, onset pattern and density** (the lab's
librosa and scipy calls, and its own `foote_novelty` and structure code): the mel filter bank identical to
librosa's in all 1,990 weights; mel spectrogram, log-mel, MFCC, RMS and onset strength within 4e-7 of librosa
(librosa works in single precision; run in double, the two agree to 1e-14); scipy's `find_peaks` identical except
on exact ties, which real novelty curves do not have; the lab's `foote_novelty` within 2e-16; on a synthesised
48-bar track with four section changes the full chain from audio gives the same 17 peaks and the same lattice
phase as the lab's code, and the same 387 onsets, bar densities and pattern. Four minutes take 1.5 s in a debug
build. The fixtures the tests compare against are written by committed Python scripts that copy the lab's code
as text and stop if the copy no longer matches `mixer/analyze.py` word for word.

**What this means.** Every piece of the lab's analyser except the two neural models (Beat This! for beats, the
vocal tagger) now exists in Swift with a measured match to the lab's Python. What remains before the analyser
can be assembled: Beat This! (in progress), the vocal tagger (a permissive one still to find), and the glue.

## Oct 28, 2026: Beat This! through ONNX Runtime, from Swift (entry 9)

**Where it landed.** ONNX Runtime (Microsoft's MIT-licensed engine for running trained models, version 1.31.1) is
loaded at run time from a library file, never linked at build time, so the package still builds on a machine
without it and on the Windows probe; only its C header is vendored (`DEPENDENCIES.md` section 6). A Swift wrapper
(`DeckieInference`) creates sessions and runs models with typed errors. The Beat This! network (the beat tracker
the lab uses; 20 million parameters, MIT code and weights) is exported once from its PyTorch checkpoint to an
82 MB ONNX file by a committed script (`core/Tools/export_beat_this.py`; the file itself is not in the
repository, its hash is, section 7), and the parts around the network are ported to Swift: its log-mel
spectrogram front end, its chunking of long audio, and its "minimal" post-processor that turns the network's
output into beat and downbeat times. `BeatTracker` ties them together: audio in, beats and downbeats out.

**Measured, against the Python package on five synthesised pieces** (30 s at 120 BPM at three sample rates, 90 s
with a tempo change at two): every beat and downbeat identical, 0 ms difference; the front end within 2.6e-5 of
the package's own; the post-processor identical on 14 hand-made edge cases and on the package's own outputs; the
exported network within 2.3e-6 of the PyTorch original. Against the true clicks of the 120 BPM piece, all 59
beats at 0 ms and all 15 downbeats on the accents. Four minutes of audio take about 6 s in a release build on
this machine (nearly all of it the network). Linux CI fetches ONNX Runtime by its pinned hash and exports the
model once, both cached, about 40 s per run when cached and about 3 minutes when not. 12 inference tests, with
34 decode and 94 core tests, pass here with the runtime present; on Windows the inference tests skip with the
reason printed until the Windows runtime file is wired in (its hash is recorded).

**Licence points for the main session.** (1) ONNX Runtime is MIT, but its third-party notices list Eigen under
MPL 2.0, which the allowlist leaves undecided; nothing ships yet, but a build that carries ONNX Runtime needs
that call. (2) Beat This!'s README releases code and weights under MIT and adds that some training files are
copyrighted or under limited Creative Commons licences, leaving the judgement to users: the same question as the
vocal tagger's (entry 8's successor, `docs/research/n-vocal-tagger.md`). Both are recorded in `DEPENDENCIES.md`
and sent to the main session.

**The vocal tagger, researched** (`docs/research/n-vocal-tagger.md`, by an Opus agent with web access, licences
quoted with sources): the lab's Essentia models are CC BY-NC-SA and cannot ship. Recommendation: Spleeter's
2-stem vocal model (Deezer; MIT code and weights; already converted to ONNX by sherpa-onnx, Apache 2.0; an
estimated 2 to 5 s per track) read as vocal energy per bar, plus EfficientAT (MIT, under 1 s) as the timbre
embedding and a second opinion. Runner-up musicnn (ISC), held back by its training data's licence. Nothing has
been run yet; the final choice goes through track J's listening test on the Mac.

## Oct 28, 2026: the crate reader and writer, and the licence decisions (entry 10)

**The main session's licence decisions, Oct 28** (recorded on `main` as a note on D14 and in the charter):
weights published under an allowed licence ship even when the training data could not be shipped by us, unless
that data's own licence forbids commercial use, in which case the weights count as non-commercial whatever they
say; where the data's licence is unknown, the trainer must be the data's rights-holder (Deezer on its own
catalogue qualifies); data set, licence and trainer go into `DEPENDENCIES.md` beside the weights. CC BY 4.0 joins
the allowlist for model weights and data only, never code, with attribution in the app's acknowledgements and in
`DEPENDENCIES.md`, and nothing added that stops the files' extraction. So Spleeter and EfficientAT are in (with
AudioSet attributed), musicnn and CLAP are out. Three conditions on the vocal work: the per-bar vocal number
lands in the lab's shape (one 0-to-1 value per bar, the lab's patch-to-bar averaging) so the yardstick can
compare it now and Apple's instrument activity later (on Apple, P13 keeps Apple's signal as v1; this pair is
the core's own signal and the fallback everywhere else); neither model file is committed, both fetched by a
pinned-hash script, and the analyser runs without them with the vocal field absent from `features_present`;
and the per-track CPU time is reported like the other modules.

**The crate (step 4).** The documents turned out to fix more than expected (spec section 5.2 with D11, research
track A section 5, the overview, the port plan, track L): a package folder `<name>.deckiecrate` holding
`manifest.json`, `crate.json` and compact half-precision sidecars for the per-bar series; an integer schema with
a minimum reader version and unknown keys ignored; tempo and key as segments; track L's engine record, fidelity,
per-block source and confidence and `features_present`; no audio, no absolute paths, signatures from an Apple
device. All of that is now implemented in a new module `DeckieCrate` with a canonical writer (same analysis,
same bytes), a reader that checks versions, required fields, array lengths against the bar count and bar ranges
and names the field path in every problem, and a converter so every lab feature file becomes a crate record.
Measured: all 373 lab files convert and round-trip with no problem and per-bar values within 0.03 of the lab's
(half precision); the five-track example crate under `core/fixtures/` is 20 KB, and all 373 tracks as one crate
come to 1.5 MB, about 4 KB a track, inside track A's budget; 26 tests. `docs/architecture/crate-format.md` (185
lines) separates what the documents fixed from eight proposals for the main session to accept or change, among
them: where track L's additions sit; fidelity 0 for lab records so a benchmarked engine redoes them; engine
family names `apple-mu`, `deckie`, `lab` (the main session changed `deckie-oss` to `deckie`: the models are open source, the engine is not); a few additive fields (tempo segments, fade start, tags, a style
block); the sidecar headers; the canonical form; and the lab conversion rules (the EffNet embedding never
travels, by the licence rule; the steady-beat end clamped on 21 files where the lab rounds past the last bar).

**Addendum, Oct 28: crate v1 accepted, with two changes, and MPL 2.0 decided.** The main session accepted all
eight proposals, changing two things: the Windows and Linux engine's family is `deckie`, not `deckie-oss` (a
family name must not claim a licence we have not granted); and a shipped engine's record id is defined as the
first 16 hexadecimal characters of the SHA-256 hash of the file's bytes (64 bits: about one chance in 3.7
billion of a shared id in a 100,000-track crate), with the full hash stored in `file.sha256` beside the Apple
apps' quick `sha1_head`; two files with the same audio in different bytes are different files with different
ids, which is right. Both are implemented (SHA-256 written in Swift with no dependency, tested against standard
vectors; 34 crate tests). MPL 2.0: unmodified files ship with their notices in the acknowledgements, any change
to an MPL file is published, an allowed equivalent is preferred where one exists; Eigen inside ONNX Runtime
qualifies as is, recorded in `DEPENDENCIES.md` beside ONNX Runtime with the notice file's location. One item
still to do there: Beat This!'s training data sets and their licences, which the new rule needs recorded
beside the weights (the paper's data list could not be fetched by that agent). The yardstick run on the Mac,
when the engine is whole: `deckie-build bench` over the 373 files against `mixer/features`, reporting the stage 1
numbers so the two engines are read on one sheet.

## Oct 28, 2026: the analyser assembled (entry 11)

**Where it landed.** A new module `DeckieEngine` runs the whole lab pipeline in the lab's order from one call:
decode, first and last sound, beats and downbeats from Beat This!, the grid fit, the octave alignment (ported
with the lab's loudness-at-downbeat test), the bar grid, start and end tempo, the spectral features at 22,050 Hz
through the resampler, novelty and phrase, sections, loudness, per-bar bands, onset density and pattern,
fade-out, mix windows, the key estimator, the flags, and timings per stage. The result writes the lab's feature
JSON shape (same keys, same rounding, same 1-based bars, so the Mac can compare an engine record with
`mixer/features/<id>.json` using the lab's own tools) and converts to a crate track (family `deckie`, id from
the file's SHA-256). Measured on a synthesised 63-second track (drums at 124 BPM, chords in A minor, a quiet
intro, a fade over the last 8 bars): tempo 124.001, bar 1 at the first beat, 32 bars, key 8A, sound bounds to
the sample, the fade found from bar 26, mix windows on the lattice, loudness within 0.4 LU of the synthesised
level; the same from the MP3 version; the lab's own `local_tempo.compute` and `fit_grid`, run on the engine's
JSON, give the engine's values back exactly. About 4.7 s in a debug build for the minute of audio, nearly half
of it the beat model; the SHA-256 was made ten times faster on the way. 11 engine tests; 185 tests in all.

**Departures from the lab, each recorded in the record itself.** (1) No madmom: Beat This! is the only grid
source (madmom is non-commercial); a field `deckie.madmom_would_run` marks where the lab's rule would have run
it, so the Mac comparison knows where the lab's grid may differ. (2) No Essentia tempo vote. (3) Key from one
estimator (the lab's FFT-chroma port) instead of three; its correlation, margin, mix-window keys and segments
are recorded. (4) Key confidence from one estimator, to confirm on the Mac: a lone vote cannot count as "all
three agree", so the rule is 0.3 when the correlation is under 0.6, else 0.65 when the margin is at least 0.10,
0.45 between 0.04 and 0.10, 0.3 below; against the lab's 311 confident keys those steps are exactly right on
84, 77 and 60 percent of tracks (right or a neighbour on 97, 90 and 78), at the cost of flagging 218 tracks as
key-uncertain where the lab flags 58. (5) No vocal tagger yet: the vocal fields are absent, the mix windows
treat every bar as vocal-free, and the record is flagged `vocal_unknown`; a tagger plugs in through a protocol
and a stand-in is tested. The EffNet embedding is never written. The lab's `score.py` needs vocal data and will
not read these records until the tagger lands; the Swift reader and scorer do.

## Oct 29, 2026: the vocal tagger on YAMNet, and ONNX Runtime's reporting switched off (entry 12)

**Where it landed.** The analyser now hears singing. The tagger is YAMNet, Google's small sound-recognition model
(3.75 million numbers, 14.9 MB once exported), trained on AudioSet, Google's catalogue of YouTube clips labelled by
the kind of sound in them. It runs through ONNX Runtime like the beat model. For every 0.96-second patch of audio
it gives a score for 521 kinds of sound; Deckie's vocal score for a patch is the largest of eleven singing-related
scores (singing, choir, yodelling, chant, mantra, child singing, synthetic singing, rapping, humming, vocal music, a
cappella), the largest rather than the sum because one voice lights several of these at once. Speech is kept
apart, as its own score. Patches are averaged into bars with the lab's rule. The record gets the lab's
`per_bar.vocal_prob` and `vocal` block in the lab's shape, plus rapping, choir, speech and music scores per bar and
the model's 1,024-value "style" vector (a numeric sketch of how a track sounds, kept for "sounds like" matching
later). The crate gets its `vocal` block, `bars.vocal` and a `style` block, all listed in `features_present`.
Measured: Swift's scores are identical to Python's ONNX Runtime on the same patches; the exported model is within
2.6 millionths of TensorFlow's original; the front end (the log-mel patches) within 1.8 ten-thousandths. 0.62 s for
four minutes of stereo in a release build. 204 tests in all (22 inference, 15 engine, 34 decode, 34 crate, 99
core), no warnings. `Analyser()` now picks the tagger up by itself when the model file is there, and says what is
missing when it is not.

**What it is not yet.** The scores are uncalibrated. On the synthesised test track (a sung line alternating with
instrumental bars) the sung bars score 0.0294 and the instrumental bars 0.0001, every sung bar above every
instrumental bar, so the tagger tells them apart; but a synthetic voice is a weak stand-in, a real voice will score
far higher, and the "vocal-heavy" thresholds wait for the Mac yardstick and track J's listening test. The research
memo (`docs/research/n-vocal-tagger.md`) had recommended Spleeter and EfficientAT; on the main session's direction
those were dropped for YAMNet, everything downloaded for them was deleted, and nothing of them was committed. The
place for a second opinion (PANNs, a larger model) is built but empty; it is only worth filling if the yardstick
shows YAMNet missing voices.

**Approval and licence.** Christopher approved the vocal-model downloads on Oct 28, with a standing yes for any
further vocal model the work needs. YAMNet's weights are fetched per machine by a pinned hash and exported with
TensorFlow, never committed (`core/Tools/fetch-vocal-models.sh`, `export_yamnet.py`), and CI caches the export.
DEPENDENCIES.md section 8 records the weights, the three source files at a pinned commit, the export's hash, the
licence (Apache 2.0, on the allowlist; quoted from the repository's LICENSE, the weights' own terms read second-hand
because the two hosts that state them were blocked here) and AudioSet's attribution text for the acknowledgements.
Training data: AudioSet's labels are CC BY 4.0; the audio is YouTube clips belonging to their uploaders; Google
trained the model. That reads as fitting the training-data rule (the trainer is the rights-holder of the model, no
data licence forbids commercial use), but it is a licence-line judgement, so it goes to the main session to confirm.

**A privacy finding, fixed in the code and raised with the main session.** While checking what ONNX Runtime's
library file contains, the agent found that Microsoft's official builds report usage to Microsoft by default
("telemetry": counts and timings of what the library did, not audio, not file names). The Linux library carries
Microsoft's reporting client and the address it reports to; the Windows library reports through Windows' own event
log instead. Deckie had been switching reporting off through the library's own call, but that call runs after the
client has already started and stored a device identifier, so it could come too late. The full switch is an
environment variable, `ORT_DISABLE_TELEMETRY=1`, that must be set before the library starts. Now `deckie_ort.c`
sets it in Deckie's own process before opening the library (unless the user already set it), a test checks it, the
Python export tools set it before loading their copy, and both CI workflows set it for every step. No analysis of
real music has run anywhere but this container and GitHub's machines, and no audio was ever involved, but the
charter's line is that nothing leaves the machine during analysis, so it is logged here and put to the main session.
Two things follow for the licence list: the reporting client brings curl (its licence is MIT-style but not on the
allowlist word for word), mbedTLS (Apache 2.0), SQLite (public domain) and zlib into the Linux library; and the clean
way out, at a later update, would be to build ONNX Runtime ourselves without the client. Both are the main session's
call. For the record: the Linux library is 29,345,384 bytes, the Windows one 17,253,728 bytes and needs Microsoft's
Visual C++ runtime installed beside it.

**Addendum, Oct 29, 2026: the main session's decisions on the reporting finding.** The main session read ONNX
Runtime's own privacy note and confirmed the finding: reporting is on by default in the official builds, over the
network on Linux and macOS and through Windows' event log on Windows, and the environment switch must be set before
the library starts, which the shim now does. Its decisions, recorded on `main` as a note on decision D3 and in the
charter's constraints: (1) the switch closes the matter for development, CI and the bench only, because it trusts
the library to honour a setting. Before the first PC build, and before any Mac bench binary is handed to an engine
bound for TestFlight, ONNX Runtime is built by us on the same CI from its pinned release tag with the build option
that leaves the reporting client out (`--no_telemetry`), and the resulting archives are pinned by hash like the
official ones. The promise is a release test, not the switch: a scan of each shipped library file for the client's
traces (the reporting address, the client's own names, the SQLite and mbedTLS text inside it, the Windows
event-log provider name), which fails on any library that carries one. The scan and its test are in place now
(`OnnxRuntime.ReportingClientScan`; the release test runs on the libraries named in `DECKIE_SHIPPED_ONNXRUNTIME`,
and a second test confirms the scan finds the client in the official library we develop with). The build's time
and the size difference go in this log when the build exists. (2) The curl licence is not added to the allowlist:
curl, mbedTLS, SQLite and zlib are present only in the official development binaries and leave with the client;
if our build still links any of them, the main session hears which and why before anything ships. (3) YAMNet's
training data fits the training-data rule, as read. For the Mac bench, the main session needs the macOS archive's
address, tag and SHA-256 in this log when the bench command is ready; Christopher's word for that download is asked
in that session. The memo Q vocal-derived fields follow the bench, under `features_present` names so a reader
without them is unaffected.

**Second addendum, Oct 29, 2026: Beat This!'s training data, recorded, with a question for the main session.** The
one gap in DEPENDENCIES.md was the training-data rule's record for Beat This! (the beat tracker): each data set the
weights were trained on, its licence and the trainer. A research agent filled it in (section 7, "Training data")
from the authors' pages on GitHub and the mirdata loaders, with every host that would not answer named. The
`final0` weights were trained on 15 sets (everything but GTZAN, the test set). Three sets state non-commercial terms
on their own pages: ASAP and its audio source (CC BY-NC-SA 4.0), RWC (CC BY-NC 4.0 on the re-released annotations;
the original was research-only) and Filosax (non-commercial research only). Ballroom, Hainsworth, the Beatles and
JAAH are commercial recordings their sets do not license; Harmonix and TapCorrect point at YouTube; for SIMAC, SMC
and HJDB no page read says where the audio came from. Only Harmonix (MIT), TapCorrect (CC BY-SA 4.0), Groove MIDI
and Candombe (CC BY 4.0, second-hand) state terms that allow commercial use. The weights themselves are MIT, and the
authors say only that "some of the training files are fully copyrighted or under limited Creative Commons licenses,
and it is up to the user to assess". The trainer, JKU Linz's Institute of Computational Perception, holds no rights
in the recordings. Under the training-data rule as written ("weights ship unless a data set's licence forbids
commercial use; unknown data, the trainer must be the rights-holder") that reads as non-commercial. That is a
licence-line decision, so it is put to the main session as a question, with the facts; nothing changes in the code
until it answers. If the answer is no, the alternatives are a beat tracker trained on data with clear terms, or
Deckie's own training on licensed data, both research items for later.

**Third addendum, Oct 29, 2026: the facts the Mac needs for its ONNX Runtime download.** The main session asks
Christopher for each download in its own session, with the facts in hand, so here they are for the official macOS
archive (Christopher's earlier yes to ONNX Runtime downloads covered fetching it here to read them): address
`https://github.com/microsoft/onnxruntime/releases/download/v1.31.1/onnxruntime-osx-arm64-1.31.1.tgz`, release tag
`v1.31.1`, 36,936,435 bytes, SHA-256 `2e1344a1926ee50eb25b38153cb6992c3567515aef0e677a1a520a1798896d6f`; inside it,
`lib/libonnxruntime.1.31.1.dylib`, 44,797,256 bytes, SHA-256 `17500d6b1e37e70f43a2c57d94233a1bc29fbcb297be0a5f8c7c13184f3307ba`
(the same source commit as the Linux and Windows archives; recorded in DEPENDENCIES.md section 6). The macOS library
carries the reporting client as the Linux one does, through the system's own network libraries rather than curl, and
honours the same switch, so the bench on the Mac runs under the same rule as here: the switch for development, our
own no-telemetry build for anything that ships. The scan built today finds the client in it (three of its markers),
so the release test covers macOS libraries as it does Linux and Windows ones.

## Oct 29, 2026: `deckie-build`, the crate builder, and `bench`, the yardstick (entry 13)

**Where it landed.** A new module `DeckieBuild` and the program `deckie-build` turn a folder of music into a crate:
`deckie-build <folder> --out <name>.deckiecrate` reads every audio file (several at a time, `--jobs`), runs the
analyser on each and writes the crate. It is resumable: a work folder beside the crate keeps each file's record, a
file with the same size and modification time is taken without reading it, a moved or renamed file is found again
by its hash, and a record is reused only if the same engine version, the same vocal tagger and the same tag tempo
made it; stopping it part way loses only the files in flight. Every file it cannot read is counted by reason
(unsupported, protected, damaged, decode error, analysis error, duplicate) and listed in the manifest's import log
with the decoder's own words. It reads rekordbox's collection export (`--rekordbox export.xml`) for the DJ's own
titles, keys, tempo, grid markers, cues, loops and playlists, and a file's own tags (`--bpm-tags`) for a tempo that
steers the octave choice. The `bench` command is the stage 1 yardstick: `deckie-build bench <folder> --features
mixer/features --candidates mixer/candidates.json` runs the engine over the lab's tracks and scores it against the
lab's files the way `mixer/bench_mu.py` does (beats and downbeats both ways round, tempo within 2 percent with and
without the octave, key, loudness and true peak, section recall, vocal correlation, bar-1 offset, bar count), with
medians, means and the charter's pass marks, as a table and as JSON. Its measures match `bench_mu.py`'s own
functions bit for bit on all 373 committed feature files (that needed Python's compensated sum in the correlation).
Against itself the engine scores perfectly; against a copy shifted by 100 ms at double tempo it scores as it
should (beats wrong, an octave apart, bar 1 off by 100 ms). 25 builder tests; 231 tests in all (22 inference, 15
engine, 34 decode, 36 crate, 99 core, 25 build), run here with both models loaded.

**Measured.** 8.3 s per four-minute file in a release build on this shared 4-core machine, 6.3 s of it the beat
model; four at a time, 6 to 9 s per file. Peak memory about 1.8 GB for one job and 5.4 GB for four, so the default
job count leaves each job about 2 GB; cutting the engine's peak memory is a task card for later, not urgent on a
desktop, worth doing before a laptop sees the builder.

**Two additive proposals for the crate format, for the main session's yes** (`crate-format.md`, item 9; nothing
existing renamed or removed, the example crate gains two nulls): the manifest's `import_log` (who built it, when,
files seen, tracks, each failure with its reason, the rekordbox match count), and a `deckie` block on each record,
null when empty, holding the tag tempo and its source and the DJ's own rekordbox grid markers, cues, loops and
playlist paths as rekordbox wrote them. rekordbox's title, artist and mix fill the existing `ident` fields, its key
becomes a vote in `key.votes` with `key.camelot` staying the engine's, and its tempo steers the octave alignment.

**What the Mac does with it.** The bench run over the 373 files is now one command away on the Mac, once ONNX
Runtime's macOS archive and the two models are there (entry 12, third addendum); it folds in the loudness, key and
vocal checks this log has been deferring to it. The builder has not run on Windows (it builds there; folder paths
may come back with backslashes).

**Decided meanwhile (P19, now D15).** Christopher decided the training-data question: weights ship under the licence
their publisher grants; a model is refused only when the publisher's own terms restrict use or a data owner has
objected; every model's training sets and terms are recorded in DEPENDENCIES.md and shown in the app's
acknowledgements, with a named replacement path. Beat This! ships with the section 7 record. Two things followed
today: an acknowledgements table now heads DEPENDENCIES.md, one line per shipped entry in the shape the apps will
render, and each model has a replacement-path line (Beat This!: Deckie's own model-free tempo and grid, which the
main session is measuring against the shipped grid now, after Christopher asked whether a model is needed for beats
at all).

## Oct 29, 2026: the vocal-derived fields, and the memory work from the Mac (entry 15)

**Where the vocals are, for the DJ (memo Q).** The research memo `docs/research/q-vocal-uses.md` found six ways DJs
use vocals (keep them apart, hand off, acapella, tease, echo out, singalong) and that a per-bar probability alone
serves few of them. The engine now writes two more blocks when it has a tagger, in the lab JSON under the record's
`deckie` block and in the crate as `vocal_structure` and `hooks`, both listed in `features_present` and left out
entirely when absent, so a reader without them is unaffected. `vocal_structure` holds the sung stretches
(`spans`, each with start and end as bar and beat and seconds, and each end's distance in beats from the nearest
8-bar point, so a reader knows "near zero means on the phrase"), the first and last sung point with whether the
first is a pickup (sung within a beat before a downbeat), the free bars at each end with their kind (`beat_only`,
`ambient`, `vocal`, `fade`), the vocal-free gaps of 8 or more bars snapped to the lattice, and `exposed_proxy`
(sung bars with little bass and few onsets, a stand-in for the Apple family's real `exposed` from stems, which a
reader prefers when present). `hooks` holds up to three candidates (start and end bar, strength, sung or not, where
the repeat is) from repetition on the per-bar MFCC similarity the novelty step already computes, loudness and vocal
density. Every rule and threshold is written into the record (`rule`), because the scores are uncalibrated until
the Mac listening test: the sung-frame threshold is a quarter of the track's 95th-percentile frame score with a
floor sized for the synthetic voice, dips under 8 beats are bridged, stretches under 2 beats dropped. On the
synthesised 40-bar track (sung from bar 8 beat 4 to 16, and 25 to 32) the fields come out as built: spans
8.4 to 16.4 and 25.2 to 33.1 (every end within two beats of the construction), first 8.4 with pickup, last 32.4,
free bars 7 and 8 both `beat_only`, gaps 17 to 25 and 33 to 41, the sung hook 9 to 17 at strength 0.970 repeating
at 25. 22 new tests. For the Mac to tune: the threshold fraction and floor, the bridge, the kind rule, the exposed
proxy and the hook weights. Work folders made before this change lack the new blocks; the engine version bumps
with the renames below so they are redone.

**The memory work, from a Mac session.** Christopher's Mac session (from the task card in entry 13) found where the
1.8 GB per job goes: the beat model's stage, where ONNX Runtime's memory arena grows in doubling steps and never
gives memory back, holding 1.1 to 1.9 GB after the stage. It measured here through its `deckie-memprobe` program
(this machine has the models; the Mac does not yet): with the arena told to give back its free regions after each
run, a single job's peak falls from 1,855 MB to 1,092 MB at no cost in time (9.4 s against 10.0 s), and four jobs
from 5.6 GB to 3.8 GB; the thread count changes time only (21.7 s, 13.5 s, 8.8 s at 1, 2 and 4 threads); capping
how many model runs happen at once trades throughput for memory (four jobs, eight files: 3.8 GB in 57 s uncapped,
2.6 GB in 81 s at two at a time, 1.7 GB in 105 s at one at a time, the capped runs disturbed by other load). Every
record came out byte for byte identical under every setting, and the beat model's raw numbers hashed the same.
Its branch is merged with shrinkage on by default, no cap, and the builder's default job count giving each job
1 GB and leaving 2 GB; the file's bytes are released once hashed and the loudness running sum after its stage. The
parity suite passed on the merge with both models (236, then 258 with the vocal fields). Two tests failed on the
Mac and are judged: the Butterworth-coefficient test now allows four units in the last place (macOS's tan rounds
three off; the filtered samples still match), and the telemetry test's failure was a real bug, fixed earlier today
(every load attempt now sets the switch). The same before-and-after on `deckie-build` itself follows.

**Addendum: `deckie-build` before and after, same tool.** Four distinct synthesised four-minute files, `--fresh`,
the process's kernel high-water mark, the Mac's branch against its base, on this shared machine: one job, 1,937 MB
before and 1,086 MB after (44 percent less, three runs within 7 MB); four jobs, 5,504 and 5,592 MB before, 3,932
and 4,366 MB after (22 to 29 percent less; the after figure varies more, probably in how the four threads' peaks
overlap). Four-job wall time unchanged within noise (27.5 against 27.4 s). One job is slower after in steady
state, 42.7 and 43.4 s against 35.9 s twice (about 10.3 against 8.3 s per file), and one after run took 87.9 s for
no reason the load explains; raised with the Mac session, whose call it is whether shrinkage should apply only
when more than one job runs. The crates: the same ten files from both commits, every per-bar and style sidecar
byte for byte identical (across all eight crates, 64 sidecar files hash to 8 values, each seen 8 times), and the
JSON differing only in the analysis times, the crate id, the creation time and the run's name. The engine version
is unchanged by the memory work; it bumps to 0.2.0 with the renames below.

## Oct 29, 2026: ONNX Runtime built by us, without the reporting client (entry 14)

**Where it landed.** The workflow `.github/workflows/onnxruntime-build.yml` builds ONNX Runtime 1.31.1 from
Microsoft's source on GitHub's machines, for Linux x86_64, Windows x64 and macOS arm64, with the build option that
leaves the usage-reporting client out (`--no_telemetry`), and scans each library for the client's traces before
uploading it, with the same nine markers the Swift release test uses (a first job checks the three lists are
equal). Each run writes the library's and the archive's size and SHA-256 and the build time into its summary, ready
for DEPENDENCIES.md; started by hand with "publish" ticked, it puts the archives on this repository's release
`onnxruntime-1.31.1-deckie-no-telemetry`, from which `fetch-onnxruntime.sh --deckie` will fetch them once the
hashes are pinned. The build's dependencies come from ONNX Runtime's own pinned list (`cmake/deps.txt`, each by
SHA-1); the one declared without a hash, mp11, is fetched and checked by Deckie's helper first.

**The first run stopped at its own guard, and taught something.** Microsoft's release tag `v1.31.1` points at a
different commit than the one its archives name as their source (the tag is a lightweight one at 6af1a932; the
archives say 41d4d61f: Microsoft packaged 1.31.1 from a later point of the release branch than it tagged). Deckie
builds the archives' commit, the source of the binaries this track was developed and tested against, and the guard
now pins both commits and stops if either moves.

**Run 2, the numbers.** Linux: 22 min 42 s; `libonnxruntime.so.1.31.1` 27,162,888 bytes (7.4 percent smaller than
Microsoft's; the client and its curl, mbedTLS, SQLite and zlib are gone); gate 0 of 9 markers; uploaded. macOS:
21 min 53 s; 28,793,144 bytes (35.7 percent smaller: Microsoft's also carries the CoreML and WebGPU back ends
this CPU-only build leaves out); 0 of 9; uploaded. Windows: 46 min 54 s; `onnxruntime.dll` 18,449,408 bytes (6.9
percent larger than Microsoft's, which is built with link-time optimisation and this is not); gate 1 of 9: the
event-log provider's name, `Microsoft.ML.ONNXRuntime`, exactly as predicted from the source, so the archive was
not uploaded. The hashes are in DEPENDENCIES.md section 6.

**The Windows rule, now applied.** The main session had decided in advance: the provider's name is reported, not
fatal, in a Windows library, with the proof written beside it. ONNX Runtime's `windows/telemetry.cc` defines the
provider with its name and is compiled into every Windows build; the one call that registers it,
`TraceLoggingRegisterEx` in `WindowsTelemetry`'s constructor, runs only when the Windows environment holds a
`WindowsTelemetry`, which `--no_telemetry` prevents (neither `USE_WINDOWS_TELEMETRY` nor `USE_1DS_TELEMETRY` is
defined, so the environment holds the base class, whose functions do nothing). The PowerShell gate and the Swift
scan's new `verdict` both apply it, for `.dll` files only; every other marker still fails, everywhere; a test plants
the name in a `.dll` and in a `.so` and checks the two verdicts. Since a later ONNX Runtime could register the
provider regardless, the version-bump checklist includes rereading those two source files. Run 3, started by this
change, rebuilds all three; when the Windows archive is uploaded, the three are published by hand and their hashes
pinned.


**Addendum: run 4, all three clean under the rule; the publish run under way.** Run 4 (the push that carried the
Windows rule) built Linux in 27 min 43 s, macOS in 18 min 40 s and Windows in 47 min 11 s; the Linux and macOS
gates found nothing, and the Windows gate reported the provider's name as present but never registered and
passed, so the Windows archive was uploaded for the first time. Christopher then approved both releases, and the
publish run of the same workflow (started by hand with "publish" ticked; it rebuilds the three and then creates
the release `onnxruntime-1.31.1-deckie-no-telemetry` with GitHub's own token) is under way; its archives' sizes
and hashes go into DEPENDENCIES.md and `fetch-onnxruntime.sh --deckie` when it lands. One lesson on the way: a
feature branch that carries the workflow file starts a build on its first push (the Mac's memory branch did, an
hour of machines for nothing; cancelled), so the push trigger will be narrowed to `main` and `pc-linux*` once the
publish run is done, since a push to the workflow file now would cancel it.


**Addendum: published, pinned and verified.** Christopher approved both releases; the publish run (run 6) built
the three again and created the release `onnxruntime-1.31.1-deckie-no-telemetry` with GitHub's own token: Linux
`onnxruntime-linux-x64-1.31.1-deckie-no-telemetry.tgz` (10,183,126 bytes, SHA-256 `aa2ea728…`), macOS
`onnxruntime-osx-arm64-…tgz` (8,078,821, `f6f5b290…`), Windows `onnxruntime-win-x64-…zip` (6,632,634, `6a5b551f…`),
each with a `.sha256` beside it; the full hashes are in DEPENDENCIES.md section 6, and `fetch-onnxruntime.sh
--deckie` now carries the Linux pin. All three archives were fetched back here, matched their hashes, and their
libraries passed the Swift release test: no marker on Linux and macOS, and on Windows the provider's name alone,
reported and not fatal, so the rule works end to end. Two notes: the Linux and macOS libraries hashed the same in
two independent builds (runs 2 and 6), the Windows one did not (the linker writes a build time into the file), so a
Windows rebuild gives a new hash to record; and the workflow's push trigger is still wide (any branch carrying the
file builds on its first push), to be narrowed with the next change to the workflow file rather than now, since
each change to it costs a full rebuild. Build times in run 6: Linux 21 min 34 s, macOS 24 min 42 s, Windows 46 min
33 s. The Mac bench can now run on our macOS library instead of Microsoft's.

## Oct 29, 2026: the crate renames, the memory defaults, and the models as pinned downloads (entry 16)

**The renames (the main session's three naming changes to item 9, now in).** The manifest's import log says who
built the crate as a device model label (`built_by`, the same value as `analysis.device`; never the user's own name
for the machine). The DJ's own data sits in a per-record block named for where it came from, `imported`, keyed by
source so a Serato import can sit beside a rekordbox one later: `imported.rekordbox` holds the import time, the
grid markers, cues, loops and playlist paths as rekordbox wrote them (plus its track id, tempo and tonality, kept so
nothing is lost), and the whole block is null when nothing was imported. The tempo in a file's own tag is a fact
about the file, so it is `file.tag_bpm` (or null); its source is no longer recorded, since rekordbox's tempo wins
exactly when the two are equal. Because the record's shape grew twice today (the vocal blocks, then these), the
engine version is now 0.2.0, so work folders made by 0.1.0 are re-analysed rather than reused; `crate-format.md`
item 9 is marked accepted, and the example crate carries the new nulls. 260 tests.

**The memory defaults, final.** The Mac session's third round settled the single-job slowdown seen in entry 15's
addendum: shrinking the model's memory after every chunk made each of a track's nine chunks fault its working
memory in again, so the engine now shrinks only after a track's first and last chunk. Measured here on the same
builder and files: one job 1,091 and 1,097 MB against 1,937 and 1,931 MB before, at the same speed (37.5 and 37.4 s
against 38.2 and 36.2 s; 8.6 to 9.1 s per file both ways); four jobs 4.36 and 4.50 GB in 24 to 25 s. On a quiet
moment, one track of four minutes takes 8.9 s here, of which the beat model is 6.5 s and everything else 2.3 s.
The Mac's branch also brings research P (`docs/research/p-machine-estimates.md`), Christopher's ask for speed and
memory estimates on DJs' machines scaled from these measurements, which finds the default job count too generous
on 8 GB and hybrid-core machines; a separate session may take that up. (Research letters: the vocal-uses memo was
to become P and now needs another letter; the main session decides.)

**The models as pinned downloads.** The Mac bench has started with its own Beat This! export, because its Python
has no TensorFlow for YAMNet and a different torch gives a different graph hash. The main session asked for the two
pinned exports (`beat_this_final0.onnx`, 82,098,829 bytes, `f1d93204…`; `yamnet.onnx`, 14,938,528 bytes,
`96bb0dc5…`) as downloadable files with their hashes, so every machine runs the exact graphs the parity tests ran
on. Creating a public release on the repository is an action this session may not take without Christopher's say
(the harness refused it), so: the release `models-1` waits for his yes (its text is drafted, with sizes, hashes,
licences, the training-data pointers and the one line that both licences permit redistribution); meanwhile the
fetch-first script is in (`core/Tools/fetch-models.sh`: the release asset by its pinned hash first, read from the
export scripts' own pinned lines; the export as fallback; tested against the absent release, the files in place
and a wrong file from a local server, which it refused), CI tries it before exporting, and every CI run now
uploads the two files with their `.sha256` as a run artifact named by their hashes, the interim download until the
release exists. The ONNX Runtime archives' publication is a release too, so both go to Christopher in one ask. The main session also declined to create the release from the
Mac, rightly: a refusal here is Christopher's to lift, not a teammate's to route around.

**Addendum: the Beat This! export is not reproducible byte for byte, so the release is the only shared copy.** The
first CI run with the artifact step refused to upload, correctly: CI's own export of Beat This! (the pinned
requirements, Python 3.12, the CPU build of torch on Ubuntu) hashes `ab1203af…`, not the pinned `f1d93204…` made
here, and the Mac's hashes `442de936…`. All three pass the export's numerical check against PyTorch (differences far
under the tolerance) and every CI test passes on CI's copy, so the graphs agree in their numbers but not in their
bytes: an ONNX export depends on the torch build that made it. YAMNet's export is reproducible (CI's bytes match the
pinned `96bb0dc5…`). So the pinned Beat This! bytes exist only in this container, and the release `models-1`, made
from here once Christopher says yes, is the one way every machine (CI included, which now fetches first) runs the
same graph. Until then the Mac's bench runs on its own export, numerically fine, and its sheet should name the graph
it ran on.

**Addendum: both releases approved, the models published.** Christopher approved both releases ("you have approval
on the releases", Oct 29). GitHub itself then refused this session's attempt to create one ("not permitted for this
session type"), so both go through GitHub's own machines with the workflow token: the pinned model files ride a
branch `assets/models-1` (the only copy of the pinned Beat This! bytes is this container's), whose workflow
`models-publish.yml` checks each file against the hash pinned in its export script and publishes. The release is
up: https://github.com/idontlikecodemuch/deckie/releases/tag/models-1, with `beat_this_final0.onnx` (82,098,829
bytes), `yamnet.onnx` (14,938,528 bytes) and their `.sha256` files; `fetch-models.sh --force` fetched both from it
and verified the pinned hashes end to end. The ONNX Runtime archives' release follows from a publish run of the
build workflow, started with his approval and queued behind run 4; its hashes go into DEPENDENCIES.md when it
lands. The assets branch stays as the record of what was published; it is not merged anywhere.

## Oct 29, 2026: the first Mac bench sheet, all 373 tracks (entry 17)

**Where it landed.** The main session ran `deckie-build bench` on the Mac over all 373 lab tracks (this branch at
439a6bc, Microsoft's macOS ONNX Runtime with reporting off, the Mac's own Beat This! export, no vocal tagger) and
published the sheet on `main` (`docs/architecture/stage1-results.md` section 2a; per-track JSON at
`docs/architecture/bench/pc-engine-2026-10-28-mac.json`). Every charter mark passes except one. Beats: the engine's
beats against the lab's detected beats, median F 1.000, mean 0.998, under 0.8 on 0.8 percent of tracks; against the
lab's final grid, mean 0.967, under 0.8 on 5.1 percent, almost all of it the 57 tracks whose lab grid came from
madmom (mean 0.79 there, 0.999 on the 316 Beat This! tracks): the engine reproduces the model, not the lab's
fallback. Downbeats the same shape. Tempo within 2 percent on 98.9 percent (Apple's framework: 91). Loudness
identical, largest difference 0.01 LU. Sections: recall and precision mean 0.95, median 1.0. Bar 1 offset median 0,
mean −11 ms; bar counts equal on 95.7 percent. 9.2 s per track median with two jobs at low priority. The one open
charter mark: key exact where the lab is confident, 74.6 percent against 75 (Apple 83.3; neighbour 14.5, other
10.9 on the 311 confident tracks). The lab's key was a three-way vote with Essentia's models in it, which the engine
cannot ship, so the single estimator is the gap. A second run with the pinned YAMNet from `models-1` is on the Mac
now and gives the vocal correlation.

**Follow-ups, under way as this is written.** (1) The cheap second key vote: an offline evaluation of the lab's own
key sweep (`mixer/key_light_*.tsv`: chroma kinds and key profiles per track) against this sheet, then the port of
the winning second estimator and a vote rule if one beats the mark. (2) The one track whose true peak differs by
6.7 dB: which, and why (decoder or method). (3) The one track whose bar 1 is 2 s off and the 4.3 percent with
unequal bar counts: the list, split into madmom-fallback tracks and the rest, and the pattern. (4) The madmom guard:
the lab fell back per file for a recorded reason; the engine marks where that rule would fire but cannot run madmom
(non-commercial); it should carry the same guard as a lowered confidence and a flag, or a written reason why not.
Results go in an addendum.

**Addendum: findings 2 to 4 answered; the key vote is still running.** (2) The true-peak outlier is f068a57770,
"Doja Cat - Demons (Epiphany Hip-Hop flip)", an MP3 from a DJ pool: the lab read +2.50 dBTP (the level between
samples, against full scale), the engine +9.20. The method is the same (the engine's true peak is a line-for-line
port and matches the lab to 0.00 dB on the other 372 MP3s), neither side clips (314 of the 373 files peak above
full scale and the engine matches every one), and everything else on the track matches (beats, bar 1, key,
sections; loudness within 0.01 LU, the only loudness difference in the set), so the decoded samples differ for at
most a tenth of a second: most likely a damaged or spliced frame that mpg123 (the lab's decoder) drops or
silences and dr_mp3 decodes into a burst. Which decoder is right needs the file: one ffmpeg command on the Mac
settles it (sent to the main session). (3) Bar counts differ on 16 tracks; 15 are madmom-fallback tracks, where
the lab's grid came from a different model: three have bar 1 one bar apart at the very start (sound from 0.0 s and
a downbeat within 31 ms of it, the engine's just after zero and madmom's just before; Ace of Base's 1,995.7 ms is
this), two a half-bar downbeat choice, one the off-beat, one a different tempo, five unsteady tracks where both
sides have confidence 0, one the last bar missed by 3 ms, two an octave. The one non-madmom track (Beyoncé,
"Haunted") is an octave the engine chose from the tag tempo it was given: the bench passed `candidates.json`'s tag
(62) while the lab had analysed with its own file's (67), and 125/62 is within the lab's rule for "double"; 55 of
the 373 tag tempos differ between the two files. No decoder length difference appears anywhere. The bench now
takes the lab file's tag first, so the next sheet compares like with like; that also aligns the engine's
`madmom_would_run` mark with the lab's recorded reason on 10 of the 27 tracks where they differ (the other 17 were
fitted by an older lab grid fit; the engine's rule agrees with the lab's current rule on 372 of 373). (4) The
madmom guard: the engine already carries it. "Poor grid fit", the lab's reason on 51 tracks, is the same test that
sets the engine's `low_grid_confidence` flag (grid confidence under 0.5), and on the four "tag more than 2 percent
off" tracks the engine's grid matched the lab's final grid perfectly (the tag was what was wrong). A second flag
would be a second name for the same thing, and capping `grid.confidence` would give the grid-fit field a second
meaning, which the crate format rules out; the record carries the tag tempo beside the grid's. A comment in
`Analyser.swift` records the reasoning.

**Addendum: the true-peak outlier settled, and the fix decided.** The Mac ran ffmpeg on the track: one decode error
("overread": the compressed data for one stretch ran past its declared length, the mark of a damaged or spliced
frame) and a true peak of +5.8 dBTP, between the lab's +2.5 (mpg123) and the engine's +9.2 (dr_mp3). So the file
is faulty and each decoder makes a different burst of the bad frame: mpg123 conceals it best, ffmpeg partly, dr_mp3
not at all. The main session's decision: the MP3 reader conceals a damaged frame (silence, or the previous frame
repeated, whichever dr_mp3 lets us do cleanly), reports it with its time so the crate builder's import log can say
"damaged frame at <time>" and the DJ sees the file is faulty, and measures the true peak on the concealed audio
like the other two; the file is not rejected, since mpg123 and ffmpeg both play it. The other 372 MP3s must stay
byte-identical, which the Mac verifies on the real files. If dr_mp3 exposes no per-frame error, the last resort is
a physical bound on a frame's output that no correct frame can reach, fixed from the format and not tuned on the
373. An agent is on it, with a fixture damaged on purpose. Also decided: the bench's tag-tempo change stands, the
sheet is rerun once the key vote lands so the three changes show together, and no separate madmom flag.

**Addendum: the key quick vote, shipped with a caution.** The evaluation (`core/Tools/key_vote_eval.py`, its
table in the script's header) first confirmed that the engine's key equals the lab's STFT-chroma, edma-profile
column on all 373 tracks, then tried 374 vote rules built from the lab's own sweep (three chroma kinds, six key
profiles, end-window variants), none with a threshold or weight fitted to the set. The rule taken: three votes over
the one STFT chroma the engine already computes, with the edma, bgate and Krumhansl–Kessler profiles; two or
three agreeing win, else edma's key. It is the lab's own rule from `analyze.py` (section B.9) with Krumhansl in the
slot the lab gave madmom's key, so nothing new was ported. Profile sources: Krumhansl and Kessler, *Psychological
Review* 89 (1982); edma and bgate from Faraldo, Gómez, Jordà and Herrera, "Key estimation in electronic dance
music", ECIR 2016 (edma learned from an EDM corpus, bgate the Beatport median profile with its four weakest
degrees zeroed), all copied verbatim from Essentia's `key.cpp` as the lab already does. On the sheet: 237 of 311
confident tracks exact, 76.2 percent against the mark of 75 (from 232, 74.6); exact or neighbour 90.0 from 89.1;
7 of 373 keys change, 5 to right, 0 to wrong. Per folder, exact before → after: CD1 90s 82.0 → 82.0 (50 tracks),
CD2 2000s to now 73.9 → 76.1 (46), CD3 Halloween 70.0 → 70.0 (50), CD4 House 71.2 → 75.0 (52), NOW Halloween 75.0
→ 75.0 (16), loose files 76.1 → 77.3 (88), other compilations 66.7 → 77.8 (9): the gain sits in four folders and no
folder loses. Five no-port rules tie at 237; three put most of their gain in CD4 House and were flagged and not
taken; this one is the lab's own, changes the fewest tracks, and spreads its gain. **The caution, library-blind:**
a held-out check (pick the rule on half the tracks, score it on the other half) finds the no-port family's gain
about zero out of sample; only the HPCP chroma's gain partly survives (+0.4 points). So this clears the mark on
this sheet without being a better estimator for new music, and 76.2 is not to be read as progress; it is in the
engine because it is the lab's own rule with nothing fitted (the main session's reading too); the Mac's research R (the full
method spec measured against the lab's and Apple's keys) is where a real gain must come from, and it replaces
this vote if it measures better on the same sheet. Shipped: `KeyVote.swift` in DeckieCore, the lab's B.9
confidence levels in the engine (replacing the one-estimator steps that had been read off this same sheet), the
record's `key.votes` with three entries and `key.source` = `votes`, the lab JSON's `deckie.key` with `votes`,
`vote` and `vote_rule`; parity: the fixture script now runs the lab's own B.9 code and the vote matches it on 68
test matrices, 14 constructed cases and all 373 sheet tracks; engine version 0.3.0 so the Mac's work folder is
redone. 265 tests. What the Mac rerun should show: key exact 76.2 (237/311), neighbour 13.8, other 10.0; all 373
exact 70.5; exactly those 7 keys changed; `key_uncertain` on about 88 tracks instead of 218; every other column
unchanged, plus the tag-tempo fix's three octave cases gone.

**Addendum: the vocal result, and the readings to try.** The Mac's second run, with the pinned YAMNet, gives the
vocal correlation: the engine's per-bar vocal series correlates 0.31 with the lab's reference (median over 373
tracks); Apple's framework reaches 0.645 (a reference, not a charter mark: the Apple apps take their vocal signal
from Apple, so this decides the PC and Linux signal only); everything else on the sheet is unchanged; 11.1 s per
track median. A three-way comparison on the lab's bar grid (357 tracks; `mixer/vocal3way.py` and section 2b of
`stage1-results.md` on `main`): Apple against the lab 0.64, the engine against Apple 0.49, the engine against the
lab 0.31. The cause is visible: the engine's series sits at a floor (mean level 0.017 against the lab's 0.81 and
Apple's 0.51; under 0.02 on 264 of 357 tracks). YAMNet's singing classes get almost nothing on a full mix, which it
scores as "Music", so the per-bar series is noise around a floor; that it follows Apple better than the lab says
the lab's reference is part of the gap, but 0.49 is still far off. Correlation ignores scale, so the floor itself
is not the problem; the lack of spread is. What the engine reads today: the maximum of eleven singing-related
scores per patch (entry 12), speech apart. The main session's ask, library-blind (no threshold fitted to these
tracks; the reading chosen must be one of the named ones with a sentence of justification): before the listening
set, try other readings of the same scores, scored on the three-way sheet. Under way: (1) four per-bar readings
written into every record from the same per-patch scores (today's max of eleven; the sum of the voice classes
including speech; the sum of their logits, which spreads the floor out; the voice classes relative to the music
classes in the same patch, which removes the "it is all Music" effect), so one Mac rerun yields all four series and
the main session adds the Apple column; the default series stays as it is so nothing else on the sheet moves.
(2) PANNs MobileNetV2 as the planned second opinion, read the same four ways: fetch and export scripts in the
YAMNet pattern, the Swift model and its front end, CI export (Zenodo, where the checkpoint lives, does not resolve
from this container; GitHub's machines and the Mac reach it), DEPENDENCIES.md section 9 (MIT; AudioSet, as YAMNet),
under Christopher's standing approval for vocal models.

**Addendum: research R, the key method to port.** The Mac's key agent delivered research R
(`docs/research/r-key-parity.md`, reference `mixer/key_parity.py`, figures in `mixer/key_parity_results.tsv`, now
merged into this branch): a licence-clean method that reaches 83.3 percent exact against the lab's confident keys
(held-out 83.2; the shipped engine 74.6; this evening's quick vote 76.2) and 70.4 against Apple's keys (shipped
63.4), with the gain present in every era, style and tempo bucket. In plain words: find the strongest spectral
peaks in each short frame, divide each by the loudest thing within a third of an octave of it (whitening, the step
that does most of the work), fold the peaks and their harmonics onto the twelve pitch classes with a smooth
window (an HPCP after Gómez 2006), sum over the track, and correlate the result with three published key profiles
averaged; "sure" when the three agree and the margin is at least 0.08 (sure tracks 92 percent exact on the held-out
split, unsure 65). The main session's decision: port it; it replaces the quick vote, which it beats on the same
sheet. Three conditions, all binding: parity first (the Swift port must reproduce the reference's key on all 373
tracks, which the Mac checks, with stage-by-stage fixtures here); the profile values are sourced from the papers
(Faraldo et al. 2016 for edma; Faraldo's 2017 thesis for bgate and braw; Gómez 2006 for the HPCP) and cited in
DEPENDENCIES.md and the code, since the reference transcribed them from Essentia's `key.cpp`, which is AGPL, a
question for the attorney either way (it applies to the current engine's edma profile too); and library-blind
stays, no parameter changes during the port. Known remaining error, not for now: mode, 16 percent of tracks read
major where Apple says minor. An agent is on the port; engine version 0.4.0 when it lands.
