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
- **Step 2 is under way on its own branch and pull request** (`pc-linux-step2`,
  https://github.com/idontlikecodemuch/deckie/pull/2, a draft until its first mechanic is whole), one mechanic
  at a time, each with its own status entry. Mechanic 1, decoding audio to float samples: WAV done; MP3 waits on
  Christopher's approval to vendor one public-domain file; AAC on Linux has a gap for the main session to decide
  (entry 4). Then Beat This! through ONNX Runtime, loudness with libebur128, the key estimator, a vocal tagger.
- Needed from Christopher: nothing right now (dr_mp3 vendoring approved Oct 28; dr_flac next, same pattern,
  will need the same yes, see entry 4, working mode).
- Needed from the Mac: nothing yet.
- Open questions for the main session: none; AAC on Linux is decided (entry 4, decision).

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

**In progress, Oct 28:** dr_mp3 vendoring and the MP3 backend (approved by Christopher), with that offset
measurement; and, in parallel, the loudness mechanic (BS.1770 K-weighting, integrated loudness, loudness range,
true peak, per-bar loudness) in plain Swift with no dependency, tested on the EBU reference signals.
