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
- **Step 2 is under way**, one mechanic at a time, each with its own status entry: first, decoding MP3 and AAC to
  float samples on Linux (in progress, entry 4 when done); then Beat This! through ONNX Runtime, loudness with
  libebur128, the key estimator, a vocal tagger.
- Needed from Christopher: nothing right now.
- Needed from the Mac: nothing yet.
- Open questions for the main session: none open; the licence list is reconciled per its reply (entry 3).

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
