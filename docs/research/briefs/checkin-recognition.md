# Check-ins: the trial of Deckie's own recognition

Branch `trial/own-recognition`. Newest entry first. Nothing here ships without the owner's decision.

## Nov 14, 2026, 02:10 UTC: first booth-condition numbers; the matcher is too slow as built, and what I am doing about it

**Received** (through the orientation session): the owner's yes on real DJ mixes; "it has to be faster before we
finalize it"; timing and false matches wanted against catalogue size up to 10,000 songs; the benchmark must run on
any folder of music from one command. All four are taken up; none is done yet.

**Done since the last entry**
- All outside material fetched (nothing committed): 320 dance and 160 other full songs from the Internet Archive's
  netlabels (Creative Commons, licence recorded per song), 598 two-minute dance clips (GiantSteps+), 417 measured
  room responses (OpenSLR 28), crowd-like noise from three public places (DEMAND). 17,880 twelve-second clips made
  from them (each asked at 3, 5, 8 and 12 s): the speed grid, 15 booth conditions at five speeds, and songs that are
  not in the index.
- Measured on one core, all 1,078 songs: a fingerprint takes 0.10 s per minute of music (0.42 s for four minutes;
  decoding the MP3 takes about as long again) and 96 bytes per second of music (23 KB for four minutes).
- The first full run was stopped: on the full index (969 songs) a query took about 0.6 s on one core, six times the
  pilot's figure, and the time grows with the catalogue. The cause is measured: a two-point hash has too few
  possible values, so each lookup returns about a hundred unrelated songs' entries.
- Two things tried, on a sample of the dev half only (550 clips, the hardest conditions):

| Dev sample, 969 songs, right song named and accepted, percent (3 / 5 / 8 / 12 s) | two-point hashes | three-point hashes |
|---|---|---|
| clean | 100 / 100 / 100 / 100 | 100 / 100 / 100 / 100 |
| room | 95 / 100 / 100 / 100 | 85 / 98 / 98 / 98 |
| room + crowd, music 0 dB over the noise | 45 / 65 / 80 / 83 | 32 / 43 / 60 / 70 |
| room + crowd, music 5 dB under the noise | 18 / 40 / 55 / 68 | 10 / 20 / 32 / 43 |
| room + pink noise, music 5 dB under | 35 / 50 / 65 / 78 | 20 / 38 / 48 / 52 |
| small speaker + room + crowd 0 dB | 60 / 80 / 87 / 95 | 45 / 62 / 70 / 88 |
| two songs at equal level (the other song is named in most of the rest) | 58 / 65 / 68 / 65 | 55 / 63 / 68 / 63 |
| mean time to answer a query, one core | 500 ms | 48 ms (59 ms at 8 s) |

- A better yes-or-no test, also from the dev sample: unrelated dance songs share enough (a kick on every beat puts
  points in the same places) that the plain score is high for a wrong song. A song's score divided by the
  third-best song's score separates much better: on songs absent from the index it never passed 2.9, and nearly
  every right answer is above that. The table above uses it.

**What this means.** Clean and room-only audio is solved at any fader setting. In heavy noise the two-point version
is close to useful but far too slow to ship; the three-point version is fast enough to build on but loses too much
in noise. Neither is the answer yet.

**Speed target I am holding the trial to:** an 8 s query answered in under 80 ms on one desktop core against 5,000
songs (so a booth that asks once a second spends under a tenth of one core), and not growing faster than the
catalogue. The trial is not done while it misses this.

**Doing next, in this order**
1. Phase 3, now justified by measurement: three-point hashes made of ratios (the two pitch differences and the ratio
   of the two time gaps), which do not change with the deck's speed, so one lookup replaces 69 candidate speeds.
   The time saved is spent on more of the query's points, which is what noise needs. From the papers, no code copied.
2. Timing and false matches against catalogue size (hundreds to 10,000), the index padded with altered copies of
   real constellations (time reversed and pitch rotated: statistically like real songs, matching nothing).
3. One command that takes any folder of music as the catalogue and writes a results file.
4. The full benchmark and the comparison with letter H; then the real mixes (Creative Commons mixes, UnmixDB),
   reported separately.

**Carry on**, with a caution: the design is changing under measurement. If ratio hashes do not bring noise results
near the two-point figures at the speed target, the honest result of this trial will be "works for clean and
moderately noisy booths, not for loud ones", and I will say so.

## Nov 13, 2026, 22:40 UTC: phase 1 built, first pilot numbers

**Done**
- `core/Sources/DeckieRecognition` (a new module nothing else depends on) with tests on generated songs that pass on
  Linux (Swift 6.4.1): a landmark fingerprint written from Wang's 2003 paper; an index; a matcher that returns the
  song, the place in it, a score, and the deck's speed two ways (from the times of the matching points, and from their
  pitches).
- The speed trick is done on the query's points, not on its audio: for each candidate speed (1 % apart, to plus and
  minus 17 %, key held and vinyl-style) the points' times and pitches are moved by arithmetic before lookup. No
  resampler or time-stretcher runs in the booth. The speed is then refitted from the matching points.
- A measuring tool and scripts (`core/Tools/recognition-bench`): fetch outside songs, make queries, match, tabulate.
- Research letter W read (fetched from `main`, merged). Of its seven points: (1) logarithmic pitch axis, (2) speed
  copies made from the peaks, (3) speed as the slope of the matching pairs and (6) scoring songs that are not in the
  catalogue were already in the design and are in the code. Still to do, in this order: (2b) the same benchmark
  with the speed change undone on the audio instead, to compare; (4) the checking step against what the crate file
  holds; (7) real DJ mixes (the Creative Commons mixes and UnmixDB), which the letter says need the owner's word, so
  I will not fetch them unless told; (5) time in beats, last, only if a gap remains. The benchmark already gives
  key-held playback the same weight as vinyl-style.

**Pilot numbers** (not the benchmark: 684 songs in the index, of which 153 full Creative Commons dance songs and 531
two-minute dance clips; clean excerpts only, 20 per cell on the eval half; no room, noise or blend yet)

| What | Result |
|---|---|
| Right song, clean, vinyl-style, every setting from -16 to +16 in steps of 2, at 3, 5, 8 and 12 s | 340 of 340 at every length |
| Right song, clean, key held (Rubber Band), same settings | 320 of 320 at every length |
| Right song, key held with a second stretcher (ffmpeg atempo), ±6 and ±12 | 80 of 80 at every length |
| Speed reading, vinyl-style, from pitch: median / 90th percentile error | 0.00 / 0.01 points at every length |
| Speed reading from times, vinyl-style, 8 s: median / 90th / worst | 0.02 / 0.05 / 0.27 points |
| Speed reading from times, key held, 8 s: median / 90th / worst | 0.09 / 0.20 / 0.43 points (does not shrink with length, so part of it may be the stretcher's own timing; to be checked) |
| Vinyl or key-held told apart (settings of 2 % and more) | all |
| A song's fingerprint on disk | 98 bytes a second of music: about 24 KB for four minutes (ShazamKit: about 45 KB) |
| Time to fingerprint a song (decode excluded), four jobs sharing the machine | 0.37 s for the average 2.7 minutes (to be re-timed on one core) |
| Time to answer one query on one core | **0.4 s for 3 s of audio, 1.1 s for 8 s: too slow, the first thing to fix** |

**Patent position from public sources** (Google Patents' listings, which it calls assumptions, not legal conclusions;
not legal clearance): US6990453 (Wang and Smith, the landmark method) is listed expired, adjusted expiry Jan 7, 2024,
with its eight continuations all listed expired by 2022; its European member EP1307833 listed expired Jul 26, 2021.
US7627477 (Wang and Culbert, invariant matching) is listed expired, adjusted expiry Mar 31, 2025; European member
EP1504445 listed expired Apr 18, 2023. No patent by the quad-fingerprint authors was found (search not exhaustive).

**Next**
1. Make the matcher fast (the lookups return far more candidates than needed; several plain remedies to try).
2. The full benchmark: all songs (about 480 full songs plus the 600 clips), room responses, crowd and pink noise,
   small-speaker band, blends, songs absent from the index; threshold chosen on the dev half.
3. Compare with letter H's ShazamKit figures where conditions match.

**Carry on.** Clean audio is solved across the whole fader in both modes from 3 s; the open questions are the booth
conditions, false matches, and the matcher's speed.
