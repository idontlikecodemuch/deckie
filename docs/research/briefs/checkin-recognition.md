# Check-ins: the trial of Deckie's own recognition

Branch `trial/own-recognition`. Newest entry first. Nothing here ships without the owner's decision.

## Nov 14, 2026, 06:05 UTC: the size study has started (branch `recog/size`)

**Received**: D35 (a fingerprint of our own; speed is fine if a song is named in a few seconds; size is the large
problem, smaller first and crate splitting second; noise waits for letter AB). This entry and the ones above it
are on the new branch `recog/size`, cut from `main`.

**The figure being brought down** is what the booth must hold in memory to match: 0.3 MB a song in the trial.

**Target, and why.** A 5,000-song crate matched in under 100 MB of memory: 20 KB a song, about the size of the
fingerprint on disk (19 KB for the outside set's average 3.4-minute song). The booth iPad is also drawing the
screen, listening and scoring picks, and an app that holds hundreds of megabytes is the first one the system closes
when memory is short. The same line puts 2,000 songs at 40 MB and 10,000 at 200 MB.

**How it is being measured.** The same benchmark, eval half only: 12,600 queries (clean, room, room with crowd 10 dB
under and at equal level, and songs not in the index, at 5, 8 and 12 s), each configuration with its own threshold
set on the dev half's no-right-answer clips as before. Memory is counted by the index itself (entries, table, 16
bytes a song). The songs' points are no longer counted as memory: only the final check of a dozen songs reads them,
so they can stay on storage (19 KB a song, read as needed).

**First row**: the trial's configuration holds 261 KB a song by this count and scores as it did (room 95 % at 8 s).

**Being tried, in this order**: 4-byte entries and a smaller table (should lose nothing); fewer hashes per point;
keeping one hash in 2, 4, 8, 16; fewer and stronger points in the songs; and a two-step matcher in which a small
index in memory only proposes a short list of songs and those are matched in full from their points on storage.

**Carry on.**

## Nov 14, 2026, 03:50 UTC: all measurements in; the letter is written

**The report is `docs/research/w2-own-recognition-trial.md`.** Read its section 1 first.

**Done since the last entry**
- **Speed** (the owner's condition). A check tag on every table entry and a table sized to the catalogue: an 8 s
  query on one core now takes 42 ms against 1,000 songs, 73 ms against 5,000 (median; 107 ms at the 95th
  percentile) and 112 ms against 10,000. My target was under 80 ms at 5,000: **met at the median, missed at the
  95th percentile.** Memory is 0.3 MB a song, which an iPad build would have to shrink or map from disk.
- **Catalogue size.** Songs named that are not in the index stay at 0 to 5 in 486 queries from 250 to 10,000 songs;
  right answers stay at 93 to 95 %. Sizes above 969 are padded with altered copies of real constellations, which
  are not more music: the owner's own run on real songs is the check.
- **One command on any music folder**: `MUSIC=/path/to/music core/Tools/recognition-bench/run.sh DATA WORK` writes
  `WORK/results.md`. Songs are named by a hash of their path. Tested here on a folder of 40 songs.
- **DJ mixes.** UnmixDB (360 generated mixes, exact ground truth, 1,149 songs in the index): with one song playing,
  100 % of 8 s windows named in unprocessed, bass-boosted and (bar one cell at 81 %) compressed mixes, 72 to 76 %
  under heavy distortion, and **no wrong song in 25,125 windows**; the key-held fader reading is within 0.03 points
  at the median. The ten real club mixes from Linz could not be fetched (their links now ask for a sign-in).
- **Letter W's comparison**: undoing the speed on the audio gives the same answers as moving the points (850 of 850
  each, clean) at nine times the cost. Dropped.
- **A deeper second pass** gains 3 to 10 points in noise at up to five times the time on hard queries. Kept as an
  option, off by default.
- Both workflows (`core-linux`, `core-windows`) are green on the last commit that changes Swift code (9b3c75b; runs
  43546500230 and 43546502845). Later commits change only scripts and documents.

| The trial in one table (eval half, 969 songs, 8 s unless said) | Result |
|---|---|
| Clean, any fader setting, key held or vinyl-style | 99.9 to 100 % (3 s: 97 to 99.5 %) |
| Room / room + crowd 10 dB under the music / equal / 5 dB over the music | 95 / 89 / 60 / 33 % |
| Wrong song named; a song not in the index named | 0 to 1 in 500; 4 of 1,944 clean, 1 of 1,952 noisy |
| Fader reading: vinyl-style (from pitch); key held | 0.00 median, 0.01 at the 90th percentile; 0.02 to 0.03 median |
| Fingerprint | 23 KB and 0.42 s per four-minute song |
| Against ShazamKit (letter H) | equal on clean audio and the fader with one fingerprint for nine; behind in loud noise (pink noise at equal level: 68 % against 90 to 100 %) |

**What is not done, plainly**
- Phase 3 (ratio fingerprints) was not built: the baseline does not fall short on speed, it falls short on noise,
  and a hash that needs more points to survive is worse in noise. The letter's section 5 gives the measurements.
- No real booth, no real deck's key lock, no real club mix, nothing on a Mac or an iPad.
- The speed target is missed at the 95th percentile, so by the owner's own condition this is **not final**.

**My recommendation** (letter, section 12): put the fingerprint in the crate file now as an addition; keep
ShazamKit as the Apple booth's recogniser until one evening's recording in a real booth says how loud the problem
is; then work on noise. **Carry on, or stop here for the owner's decision: the trial's questions are answered.**

## Nov 14, 2026, 01:25 UTC: the full benchmark has run once, with the fast matcher

**Done since the last entry**
- The matcher is now three-point hashes built from each stretch's strongest points (a strength level kept in two
  spare bits of every point, so the fingerprint is the same size), with the yes-or-no test described last time.
  Two-point hashes are kept in the code for comparison only: they cannot meet the speed condition.
- The whole benchmark ran: 969 songs in the index (109 more held out as "not in the crate"), 17,880 clips, 71,520
  queries. The threshold was set on the dev half; every figure below is the other half.
- Added, not yet run: the index padded to 10,000 songs (running now), any folder of music as the catalogue.

**Numbers** (eval half; "right" = the right song named and accepted; wrong songs named: 0 to 1 in 500 in every row)

| Condition | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| Clean, vinyl-style, every setting -16 to +16 (1,700 queries) | 97.0 | 99.6 | 99.9 | 100 |
| Clean, key held, every setting (1,600) | 99.6 | 99.9 | 99.9 | 99.9 |
| Small speaker (250 to 3000 Hz), or everything above 2 kHz removed | 99 | 100 | 100 | 100 |
| Room (a measured room response) | 76 | 89 | 95 | 98 |
| Room + crowd, music 10 dB over | 63 | 79 | 89 | 93 |
| Room + crowd, music 5 dB over | 43 | 64 | 76 | 85 |
| Room + crowd, equal level | 31 | 48 | 61 | 72 |
| Room + crowd, music 5 dB under | 12 | 22 | 33 | 43 |
| Room + pink noise, equal level | 37 | 54 | 68 | 77 |
| Room + pink noise, music 5 dB under | 15 | 28 | 44 | 57 |
| Small speaker + room + crowd at equal level | 47 | 65 | 79 | 86 |
| Two songs at equal level: one of the two named / both named | 95 / 16 | 99 / 35 | 99 / 48 | 100 / 59 |

| Other measures | Result |
|---|---|
| A song not in the index named anyway, clean | 5 of 1,944 queries, setting aside one held-out clip that is the same track as a clip in the index under another id (named 40 times of 56: the matcher was right about it) |
| Same, in a room with crowd at equal level; and noise alone | 0 of 1,952 (the same-track clip: 3 of 48); 0 of 400 |
| Speed reading, vinyl-style, from pitch (8 s): median / 90th | 0.00 / 0.01 points clean; 0.01 / 0.04 in a room with crowd |
| Speed reading from times (8 s): median / 90th | 0.02 / 0.05 clean vinyl; 0.13 / 0.35 in a room with crowd |
| Key-held reading against Rubber Band's stretch | 0.22 median, but the error grows with the setting and is absent with a second stretcher (ffmpeg: 0.02), so it is that stretcher's own speed, not the reader |
| Vinyl or key-held told apart | every right answer at 2 % and beyond |
| Time to answer, one core, 969 songs (four jobs sharing the machine) | 15 ms for 3 s of audio, 56 ms for 8 s, 90 ms for 12 s, plus 4 to 17 ms to fingerprint the query |

**Against letter H's ShazamKit figures** (8 s; H used 25 songs of one crate, a synthetic reverb and 373 distractors,
so the rooms differ): clean across the fader, equal (H: 25 of 25 with nine signatures a song; here 99.9 % with one).
In its room alone H had 49 to 50 of 50; here 95 %. With pink noise at equal level H had 90 to 100 %; here 68 %. At
5 dB under, H had 78 to 94 %; here 44 %. **So in loud noise this is clearly behind ShazamKit**; the measured rooms
here are harsher than H's reverb, and I cannot say how much of the gap that explains.

**What I think it means.** If the booth iPad hears the monitor 10 dB or more over the crowd, a song is named in 8 to
12 s about nine times in ten at any fader setting, with almost no wrong names. At equal level it takes longer and
misses about three in ten within 12 s. Nobody has measured a real booth's level for this trial; that is the number
that decides whether this is enough.

**Next**
1. Time and false matches against catalogue size to 10,000 (running), against the 80 ms target.
2. One more attempt at noise: a deeper second pass (more of the query's points) used only when the fast pass finds
   nothing, measured for what it gains and costs.
3. The same benchmark with the speed undone on the audio (letter W's comparison).
4. Real DJ mixes (the owner's yes received): Creative Commons mixes and UnmixDB, reported separately.
5. The one-command run on any music folder; the research letter.

**Carry on.** Direction unchanged; the noise gap to ShazamKit is the thing to watch.

## Nov 14, 2026, 00:50 UTC: first booth-condition numbers; the matcher is too slow as built, and what I am doing about it

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
