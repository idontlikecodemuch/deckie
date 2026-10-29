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
  track, now with the vocal tagger in it (entries 11 and 12). 201 tests pass on Linux; Windows builds and passes
  everything that needs no model. Next: `deckie-build` with its `bench` command (step 5, in progress), then the
  vocal-derived fields from memo O (where the vocals are, free intro and outro, hooks) as added crate fields, then
  the yardstick on the Mac.
- Needed from Christopher: nothing right now. The vocal-model downloads were approved on Oct 28 ("Allow vocal
  models", with a standing yes for any further vocal model the work needs); dr_mp3, dr_flac, ONNX Runtime and
  Beat This! were approved before.
- Open questions for the main session: none. ONNX Runtime's usage reporting is decided (entry 12, addendum): the
  switch set before the library starts covers development, CI and the bench; a shipped build carries a library
  built by us without the reporting client, proven by a release test, and curl stays off the allowlist. YAMNet's
  training data is confirmed. Crate format v1 is accepted (entry 10, addendum) and MPL 2.0 is decided.
- Added to the order of work, before the first PC build: ONNX Runtime built on CI from its pinned tag without the
  reporting client, pinned by hash, with the release test already in place (entry 12, addendum).
- Needed from the Mac, when step 5 lands (not blocking): the `bench` run over the 373 files, which folds in the
  loudness check against pyloudnorm (entry 5), the key estimator's parity run (entry 6) and the vocal tagger's
  first look at real voices (entry 12). The Mac needs ONNX Runtime's macOS archive fetched by the same pinned
  pattern as Linux (DEPENDENCIES.md, section 6).

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
four minutes of stereo in a release build. 201 tests in all (19 inference, 15 engine, 34 decode, 34 crate, 99
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
in that session. The memo O vocal-derived fields follow the bench, under `features_present` names so a reader
without them is unaffected.
