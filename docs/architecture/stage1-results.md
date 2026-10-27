# Stage 1 measurements

Started the evening of Oct 26, 2026, on Christopher's Mac (macOS 26.6, Xcode 27.1 with the iOS 27.1 and macOS 27
SDKs). Living document: numbers are appended as runs complete. The experiments are the ones spec v0.4 section 7
lists for stage 1; the harness is described in `analysis-port-plan.md`.

## 1b. ShazamKit pitch tolerance (done Oct 26, 22:58)

Setup: the sprint's catalogue tool on the Mac (`deck-app/tools/catalogtool bench`), the shipped catalogue layout
(one signature per track at original pitch and vinyl-style plus and minus 4 percent; 347 tracks, 1,041 signatures,
rebuilt from the audio in about 3 minutes), 25 tracks, one 8-second excerpt each at 92.8 s, rendered at each pitch
setting. "Vinyl" (r) resamples, so tempo and key move together; "tempo-only" (t) keeps the key, as master tempo
does on a CDJ. 23 settings, 575 matches attempted. Match latency is not measured here (the tool reports the offset
error, median 3 ms).

| Setting | Matched | Right signature | Note |
|---|---|---|---|
| original | 25 / 25 | 22 | |
| vinyl +-2 | 24-25 / 25 | | lands on the original or the +-4 signature |
| vinyl +-4 | 24-25 / 25 | 24-25 | the signature at that pitch |
| vinyl +-6, +-8 | 25 / 25 | | matched by the +-4 signature with a reported skew of about 0.02 to 0.04 |
| vinyl +-10, +-12, +-16 | 0 / 25 | | nothing matches |
| tempo-only +-4 | 25 / 25 | | matched by the +-4 vinyl signature, so the flavour is not distinguishable from the match alone |
| tempo-only +-8 | 6-8 / 25 | | mostly fails |
| tempo-only +-12, +-16 | 0-1 / 25 | | nothing matches |

What it means:

- A signature matches within about plus or minus 4 to 5 percent of its own pitch, which agrees with Apple's "under
  5 percent" guidance. The sprint's three variants therefore cover about plus or minus 8 percent of vinyl-style
  change and no more. Mike's 16 percent habit was outside the catalogue's reach at the party.
- Vinyl-style coverage to 16 percent needs signatures at 0, plus and minus 8 and plus and minus 16 (five per
  track, about 75 KB and 5 s of generation per track on the Mac). The plus and minus 4 variants are redundant with
  those and can go.
- Tempo-only change is a different problem: a resampled signature matches it only to about 4 or 5 percent. Beyond
  that the catalogue needs tempo-only variants (t plus and minus 8, 16) or recognition has to fall back to the
  original signature plus the position-drift method. This is the open design question for the catalogue, with a
  cost in signatures per track (up to nine) and in on-device generation time.
- The match cannot tell vinyl from tempo-only. The app's existing rule (frequency skew for vinyl, position drift
  for master tempo) stays necessary.
- Not measured yet: time to first identification, behaviour in a loud room, and on-device signature generation.

## 1a. Music Understanding against the lab features (running)

Setup: `tools/mubench`, an iOS 27 app run in the iPad (A16) iOS 27.0 simulator on this Mac, reading the audio from
the host folder and writing the framework's raw `SessionResult` as JSON into `mixer/mu_raw/` (about 3 MB per
track; not committed). The comparison is `mixer/bench_mu.py` against `mixer/features/<id>.json`. The framework
works in the simulator, which means the benchmark does not need a macOS 27 Mac or a physical iOS 27 device.

Smoke test, one track (2 Unlimited, No Limit, 3:43), Oct 26, 22:57:

| Measure | Music Understanding | Lab (Python stack) |
|---|---|---|
| seconds | 18.7 | about 17.5 |
| BPM | 141.09 | 141.085 |
| beats, bars | 526, 132 | 526 detected, 131 bars |
| beat F-measure at 70 ms | 0.985 against the lab's detected beats; 0.999 against its fitted grid | |
| downbeat F-measure at 70 ms | 0.970 against detected; 1.000 against the grid | |
| key | B-flat minor, one range, which is Camelot 3A | 3A, confidence 1.0 |
| integrated loudness | -11.95 LUFS | -12.0 |
| structure | 20 sections, 33 segments, 67 phrases, unlabelled | 8-bar lattice with 7 boundaries |
| instrument activity | vocal, drum, bass, other, one value every 50 ms | vocal only, per bar |

First eight tracks of the full run (Oct 26, 23:01): beat F median 0.995, downbeat F 0.982, BPM within 2 percent on
all eight, key exact on 5 of 7 confident lab keys and a Camelot neighbour on the other 2, loudness within 0.04 LU,
per-bar vocal correlation 0.59 with the framework reporting far less vocal (mean 0.45) than the lab's detector
(0.90), which the lab's own README calls over-reporting. Sections: recall 0.80 of the lab's boundaries, precision
0.21 because the framework reports about 20 sections where the lab's lattice has 7; the lattice step will have to
pick among them.

Full run over the 373 tracks: started Oct 26, 22:59; results below when it completes.
