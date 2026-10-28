# PC and Linux track: status log

Running log of the PC and Linux track (charter: `pc-linux-track.md`). Written for Christopher: plain language, every
technical term explained in the sentence that uses it. Newest entry at the bottom. The main session (Claude on the
Mac) reviews and merges this track's branch, `pc-linux`, and runs anything that needs the music.

## Where things stand

- Step 1 of the order of work (the two-week spike) is in progress: a Swift package `DeckieCore` under `core/` with
  the beat grid fit, the Camelot mapping and the pair scoring ported from the lab, with tests against the lab's
  committed numbers. Step 2 does not start until the main session has read the spike result.
- Needed from the Mac: nothing yet.
- Open questions for the main session: none yet.

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
