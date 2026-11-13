# Check-ins: the trial of Deckie's own recognition

Branch `trial/own-recognition`. Newest entry first. Nothing here ships without the owner's decision.

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
