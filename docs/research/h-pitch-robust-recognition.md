# Track H: recognising the track and reading the pitch across the full fader range

Dated Oct 27, 2026. Research report on the pitch problem in spec 5.3. It follows stage 1b
(`docs/architecture/stage1-results.md`). Facts are cited. Anything marked *[inference]* is my reading. All
measurements ran on Christopher's Mac (Apple M1 Max, macOS 26.6) with ShazamKit custom catalogues, on 25 tracks
of the party crate, one excerpt each. They stand in for an iPad in a booth; they are not a booth.

## 1. Summary (one page)

**What the measurements show.**
- A ShazamKit reference signature tolerates about plus or minus 4 percent around its own speed. That holds
  separately for a time-stretch, for a pitch shift, and for both together in the vinyl direction. At 5 percent it
  fails. The diagonal opposite to vinyl (tempo up, pitch down) is tighter: 6 to 10 of 25 match at 4 percent.
- Inside that window ShazamKit reads vinyl-style pitch exactly. `frequencySkew` gives the fader to within
  0.03 points, worst case, from one 8 s window.
- ShazamKit reports nothing about tempo inside one match. The match offset is precise, though: two matches 8 s
  apart give the tempo ratio to a median of 0.02 to 0.05 points (p90 under 0.2) in clean audio and in all the
  synthetic noise I tried. The app today waits 20 s and rounds to 0.5.

**Recommended solve: shift the query, not the catalogue.**
- The crate carries one signature per track, as now (about 45 KB, about 0.7 s on one Mac core).
- While listening for a new song, the app feeds several `SHSession`s in parallel with transformed copies of the
  microphone signal:
  - the input as it is;
  - resampled by the inverse of plus and minus 8 and 16 percent, which covers vinyl-style;
  - time-stretched by the inverse of plus and minus 5, 10 and 15 percent, which covers tempo-only.
- That is 11 streams. Measured CPU is about 0.9 percent of one M1 Max core per session, plus 0.4 percent per
  time-stretch, so about 12 percent of one core in total *[inference: the iPad should be in the same range;
  measure it]*.
- After the first identification the app drops to one stream, re-centred on the measured ratio, so ShazamKit
  sees near-original audio while tracking.
- Pitch is read two ways:
  - vinyl-style: candidate ratio x (1 + skew), at the first match;
  - tempo-only: the drift of the match offset across two matches, after about 16 s.
- Whether the key moved separates the two modes, as long as the pitch is more than about 1 percent off zero.
- Measured offline, with a time-stretch standing in for the live stream: 21 to 25 of 25 match across plus or minus
  16 percent (section 4.4).

**Runner-up: nine signatures per track.** The set is o, r±8, r±16, t±8 and t±16 (r = resampled, vinyl-style;
t = time-stretched, tempo-only).
- It is the best measured result: 25 of 25 at every setting from minus 16 to plus 16, in both modes, with
  AVAudioUnitTimePitch queries. With queries from a different stretcher (Rubber Band) it scores 23 to 25 of 25.
- It needs no new runtime code.
- It costs nine times the catalogue: about 410 KB and about 10 s of Mac single-core time per track, so about
  0.4 GB and 3 hours of one core for 1,000 tracks. That is the wrong shape for a crate built on an iPad and
  carried in a file.
- It is the right interim fix for the next gig, because `catalogtool` builds it today.

**Not recommended now: our own pitch-invariant fingerprint.**
- The proven designs either cannot ship in a closed-source app (Panako and Olaf are AGPL) or have no code to
  reuse (Qfp exists only as a paper).
- None beats ShazamKit-with-transforms on these numbers.
- Keep Qfp in view if ShazamKit ever caps catalogues or sessions, or if the wide fader range (beyond ±16) matters.

**Build first**
1. The interim fix: rebuild the party catalogue as the nine-variant set (one `catalogtool sign` and `assemble`
   run).
2. Fix the tempo reading in `Recognizer.updatePitch`:
   - a `t` variant match currently returns the variant's percent and never refines it;
   - drift needs 20 s and rounds to 0.5;
   - replace both with a two-match offset fit, timed on audio sample time, reported to 0.1.
3. A multi-stream listener with re-centring, first in `catalogtool listen` on the Mac, then on the iPad.

**Measure next**
- CPU, heat and battery on the iPad (A16) with 11 sessions.
- Time to first identification from a speaker in a room.
- False matches with a full crate of distractors.
- A real CDJ master-tempo recording; only Apple's and Rubber Band's stretchers were tested.
- On-device signature generation time.

## 2. The problem in numbers

**The fader.** It runs from −16 to +16 percent. In vinyl mode the playback ratio *v* scales time and frequency
together. In tempo-only mode, time scales by *v* and frequency stays at 1.

**The catalogue tool.**
- `deck-app/tools/catalogtool` renders variants with AVAudioUnitVarispeed (`r`) or AVAudioUnitTimePitch (`t`).
- For the experiments I compiled a copy into the scratchpad, never into the repo. It adds two things:
  - a pitch-only stage `p` (TimePitch, rate 1, pitch in cents);
  - chained stages such as `t+12~t-10.71`, meaning "play at +12 tempo-only, then stretch back by 1/1.12".
- A chained render is the offline stand-in for transforming the microphone signal.
- Every other line of the tool is unchanged. The bench and match logic is the same as in the repo.

**Test set.**
- The 25 tracks that `bench --n 25 --seed 7` picks, one excerpt each at a random position.
- Variant signatures were made only for these 25. All catalogues also hold the 373 original signatures as
  distractors.
- In every "wrong" match outside a blend, the match was another cut of the same song (two Hypnotize cuts, two Get
  Ur Freak On, a Calvin Harris extended mix, a Thong Song remix). The app already treats those as the same song
  (`songKey`). No different-song false match occurred outside blends.

**The real-world range.** A study of 1,557 real DJ mixes found:
- 86.1 percent of tempo changes under 5 percent, 94.5 percent under 10, 98.6 percent under 20;
- only 2.5 percent of tracks transposed;
- the authors conclude DJs mostly keep master tempo on (Kim et al., ISMIR 2020, https://arxiv.org/pdf/2008.10267).

So tempo-only is the main case and vinyl-style the special one. Mike's 16 percent vinyl habit is the outlier the
product must still handle.

## 3. Options with cost and benefit

| Option | Coverage measured | Catalogue per track | Build time per track (Mac, 1 core) | Runtime cost | Pitch readout | Status |
|---|---|---|---|---|---|---|
| Today: o, r±4 | vinyl −8 to +9; tempo-only ±4 full, ±5-6 at 72-80% | 3 sigs, ~135 KB | ~2.5 s | 1 session | vinyl 0.03 pt at once; tempo-only after 20 s, 0.5 steps | shipped |
| A1: o, r±8, r±16 | vinyl ±16 all 25/25; tempo-only only ±4 | 5 sigs, ~230 KB | ~4.3 s | 1 session | as today | tool ready |
| **A2: o, r±8, r±16, t±8, t±16** | **every setting ±16, both modes, 25/25** | **9 sigs, ~410 KB** | **~10 s** | 1 session | vinyl 0.03 pt; tempo-only ±4 coarse at once, ~0.05 pt after 16 s | tool ready |
| A3: 7-sig "box" grid | holes at tempo-only ±10 (60-76%) | 7 sigs | ~7 s | 1 session | as A2 | rejected |
| **B: shift the query** | vinyl and tempo-only ±16, 84-100% per window clean (offline stand-in) | **1 sig, ~45 KB** | **~0.7 s** | 11 sessions until the first match (~12% of one core), then 1-2 | as A2, plus re-centring | to build |
| C: coarse ID then own tracking | tempo ratio 0.05-0.15 pt from one 8 s window after the ID | 1 sig + onset template (a few KB) | + analysis already in the crate | 1 session + small DSP | tempo after one window | prototype in Python |
| D: own invariant fingerprint (Qfp-like) | literature: 70-130% at 98% with 20 s queries | new index | unknown | own matcher | scale factors per match | months; no code to reuse |

Per-track sizes assume 45 KB per original signature, scaled by 1/ratio (a faster variant is shorter: 54 KB
original vs 49 KB at +8 in `runs/sign_timing`). The current shipped catalogue is 52 MB for 1,119 signatures.

### A. More catalogue variants
- **What it buys.** ShazamKit's window is about ±4 percent and fails at 5. A grid spaced 8 apart (0, ±8, ±16) has
  a worst case of 1.08/1.04, a 3.8 percent offset, which still matched 25 of 25. Vinyl-style needs
  r±8 and r±16. Tempo-only needs its own t±8 and t±16: a resampled signature does not catch tempo-only beyond 4
  percent (A1 row).
- **The diagonal box grid fails.** A cheaper 7-signature grid would let one variant at (tempo +8, pitch +4) serve
  both lines. It left holes because ShazamKit's window is narrower on the anti-diagonal.
- **Do TimePitch-rendered variants match tempo-only playback? Yes.**
  - Queries rendered with TimePitch: 25 of 25 at every t setting.
  - Queries rendered with Rubber Band, a different time-stretcher (pedalboard `time_stretch`): 23 to 25 of 25
    against TimePitch references.
  - Not tested: a CDJ's own master-tempo algorithm.
- **Cost.** 9 signatures, about 410 KB and about 10 s of Mac single-core time per track.
  - Single-process figures for a 4-minute track: o 0.7 s, r+8 0.8-1.0 s, t+8 1.4-1.7 s.
  - In parallel: 350 variant signatures took 89 s wall time on about 7 cores.
  - For a 2,000-track crate: about 0.8 GB and about 5.6 core-hours. On an iPad it would run a few times slower
    *[inference: A16 has two performance cores; unmeasured]*.
  - Spec 5.3 wants catalogues built on the device, per crate. This is the cost that makes A2 a stopgap.

### B. Shift the microphone instead of the catalogue
- **Vinyl-style playback.** At ratio *v*, resampling the input by 1/*c* gives a signal at *v/c* in both time and
  frequency. That is inside the original signature's window when |*v/c* − 1| ≤ about 4 percent. The resample
  candidates are therefore c = 1, 0.92, 0.84, 1.08, 1.16.
- **Tempo-only playback.** Resampling cannot rescue tempo-only playback. The input at (tempo *v*, pitch 1)
  becomes (*v/c*, 1/*c*), and the pitch term leaves the window as soon as |*c* − 1| > 4 percent. Measured: tempo-only
  ±8 resampled by ∓4 matched only 6 of 25, because it lands on the narrow anti-diagonal. Tempo-only needs a
  time-stretch of the input by 1/*c*, which returns it to (*v/c*, 1).
- **Measured double stretch.** The live stretch was played with Rubber Band, then undone with a TimePitch candidate:
  - candidates 8 apart: 15 to 24 of 25 (weakest at −12, halfway between two candidates);
  - candidates 5 apart (residual 2.5 percent or less): 22 to 25 of 25.
  - Hence time-stretch candidates at ±5, ±10, ±15, and resample candidates at ±8, ±16.
- **Is a cheap real-time stretch feasible on an iPad? Yes.**
  - AVAudioUnitTimePitch cost 0.22 s of CPU per 60 s of audio on one M1 Max core (0.4 percent). Varispeed cost
    0.06 s (0.1 percent).
  - A streaming SHSession, including matching against a 573-signature catalogue, cost 0.55 s per 60 s
    (0.9 percent).
  - For 11 streams that comes to roughly 10 to 15 percent of one core.
  - In a live graph, TimePitch at a rate other than 1 cannot sit between the input node and a tap: it needs more
    or less input than arrives. Each candidate needs its own manual-rendering engine fed from a ring buffer, with
    a few hundred milliseconds of delay. Alternatively a push-style stretcher such as Signalsmith Stretch (MIT)
    or Bungee (MPL-2.0) can be used.
  - Resampling is trivial with AVAudioConverter.
  - *[inference: the A16 core is at least as fast as an M1 core. Thermal behaviour over a 4-hour set is the
    unknown.]*
- **Re-centring.** Once the song and ratio are known, one stream undoes exactly the measured ratio. ShazamKit then
  sees near-original audio, which is where its matching is most robust in noise. The skew and drift of that
  stream then track fader nudges directly.
- **Risks.**
  - Eleven sessions mean eleven chances of a false match per window. Measured false matches were zero outside
    alternate cuts and blends, but only against 373 distractors. The hysteresis in `Recognizer` remains the guard.
  - Apple documents no limit on concurrent sessions. Test it.

### C. Coarse ID, then fine tracking with our own analysis
- **Blind beat tracking is not precise enough.** Beat-period estimation of the live audio, divided by the crate's
  BPM, misses by a median of 0.35 to 0.8 points (p90 1.0 to 1.6) in room and pink noise. In a blend it misses by
  a median of 3.6 to 4.7 points, because it locks onto the other track. That is too coarse for the fader.
- **A template is.** Aligning the live onset envelope against the original's onset envelope, at the position
  ShazamKit gave, reads the ratio to 0.05 to 0.15 points from one 8 s window, and holds up in a 0 dB blend.
- **The key reading.** A log-frequency spectrum cross-correlation (1.7-cent bins) against the original reads the
  frequency ratio to 0.00 to 0.06 points. It flags vinyl against tempo-only correctly on 25 of 25 at ±3 and ±12.
  It drops to 16 to 23 of 25 at −10 vinyl in noise, a bug or limit in my quick version.
- **Value.** It is real but smaller than expected, because ShazamKit's own offsets already act as an onset
  template (section 4.3). What C adds is the tempo after one window (about 8 s) instead of two (about 16 s), and a
  readout during stretches where ShazamKit stops matching (heavy effects, loops).
- **Cost.** The crate already holds the beat grid (Music Understanding, D11). An onset envelope at 86 Hz, 8 bits,
  is about 20 KB for a 4-minute track *[inference]*.
- **Recommendation.** Build C after B, as a refinement.

### D. Our own pitch- and tempo-robust fingerprint
See section 5. Summary: Panako tolerates the transforms and reports both scale factors, but it is AGPL, written in
Java, and degrades beyond about 8 percent of resampling. Olaf is AGPL and not scale-invariant. audfprint and
Dejavu are MIT but not robust. Qfp (Sonnleitner) is the right design (quad hashes, ±30 percent, factors per
match) but has no public code. Its accuracy at 5 s queries is 0.56 to 0.77, so it would also lengthen time to
identification. A Swift reimplementation is a multi-month project with patent review (Wang and Culbert,
US7627477, is listed as expired: https://patents.google.com/patent/US7627477). Not worth it while B works.

## 4. Measurements

All commands run from the scratchpad copy (`ct/catalogtool`, identical to the repo tool apart from `p` stages and
`~` chains). M = `deck-app/tools/build/manifest.json`. Catalogues are assembled into the scratchpad from the
read-only signature cache plus new variant signatures (`sign --manifest sub25.json --sigdir sigs --variants
r±8,r±12,r±16,t±8,t±12,t±16,r±4~t±3.85 --shard k/10`).

### 4.1 One signature's window (original-only catalogue, 373 signatures)
`catalogtool assemble --sigdir build/sigs --variants o --out orig.shazamcatalog` (16.6 MB), then
`bench --catalog orig.shazamcatalog --manifest M --n 25 --dur 8 --render ...`. Each bench run takes about 11 s.

| Offset from the signature | ±2 | ±3 | ±4 | ±5 | ±6 | ±8 |
|---|---|---|---|---|---|---|
| vinyl (r) | 24-25 | 25 | 25 | 5 / 12 | 0 | |
| tempo-only (t) | 25 | 24-25 | 24 | 1-2 | 0-1 | 0 |
| pitch-only (p) | 25 | 24-25 | 23-25 | 21-22 | 0 | 0 |
| tempo +4 with pitch −4, and the reverse | | | 6 / 10 | | | |

Skew error on the matches: at most 0.03 points (vinyl) and 0.08 points (pitch-only) within ±4. Tempo-only matches
report a skew of about 0.

### 4.2 Variant grids (8 s windows, 25 tracks, renders r and t at ±2, ±4, ... ±16)

| Catalogue | vinyl ±2 to ±16 | tempo-only |
|---|---|---|
| current shipped (o, r±4) | ±5 to ±8: 25/25; +9: 24; −9: 0 | ±5: 18-20; ±6: 18-19 |
| A1 o, r±8, r±16 | 24-25/25 at every setting | ±4: 24; ±6 and beyond: 0-1 |
| A3 o, r+4~t+3.85 (both signs), r±12, t±16 | 24-25 | ±10: 19 / 15; ±12: 25 / 23; rest 24-25 |
| **A2 o, r±8, r±16, t±8, t±16** | **25/25 at every setting** | **25/25 at every setting** |
| A2 with Rubber Band queries (`match --render o` on pedalboard renders) | | +4 to +16: 25; −6, −10, −16: 25; −12: 23 |

**Pitch readout with A2**, using the app's rule (frequency ratio = variant ratio x (1 + skew) for vinyl; the
variant's percent for tempo-only):
- vinyl error is at most 0.03 points at every setting, and the vinyl/tempo-only kind is right on 25 of 25;
- tempo-only error at the first match is 0 to 4 points (the distance to the nearest variant), and below ±4 the
  kind is not detected, because the match lands on `o` with no skew.

### 4.3 Tempo from two matches (`drift.py`, `match` on windows starting 8 s of live time apart)

| Setting (A2 catalogue, clean) | t+2 | t−3 | t+5 | t−7 | t+11 | t−13 | r+3 | r−10 |
|---|---|---|---|---|---|---|---|---|
| tempo error, median / max (points) | 0.02 / 0.10 | 0.03 / 0.10 | 0.03 / 0.08 | 0.02 / 0.09 | 0.04 / 0.13 | 0.03 / 0.08 | 0.03 / 0.09 | 0.02 / 0.07 |

Caveat: offline, each window's start time is exact. Live, the app must timestamp matches by audio sample time
(the `AVAudioTime` passed to `matchStreamingBuffer`), not by `Date()` at result delivery as `handle` does now.

### 4.4 Shift-the-query stand-ins (original-only catalogue)
- Vinyl undone by resampling (`r+12~r-10.71`, `r±16~r∓…`): 24 to 25 of 25.
- Tempo-only undone by a time-stretch (TimePitch on both sides): `t+12~t-8` 25, `t+16~t-16` 25,
  `t+16~t-13.79` 25, `t-12~t+13.64` 25.
- `t-12~t+8` scores only 14 of 25, because its residual is −5 percent.
- With Rubber Band live and TimePitch inverse candidates:

| Live stretch | ±6 | ±10 | +12 | −12 | ±16 |
|---|---|---|---|---|---|
| candidates 8 apart (±8, ±16) | 22-23 | 22-24 | 22-23 | 15 | 21-22 |
| candidates 5 apart (±5, ±10, ±15), nearest | 24 | 23 | 24 | 23-25 | 22 |

### 4.5 Room proxy, noise and blends (`mknoisy.py`, `noisebench.py`, A2 catalogue)
- **The room proxy.**
  - Reverb (room 0.6, wet 0.25) and a 120 Hz to 8 kHz band.
  - Then one of: pink noise at 0 dB or −5 dB SNR; or a second crate track at equal level (a 0 dB blend) or
    6 dB below.
  - This is synthetic. It is not crowd noise or a PA.
- **The run.** Two 8 s windows per track and condition, so 50 windows per cell.

| Condition | windows matched (o / r+12 / r−6 / t+12 / t−6) | tempo error, two-window inliers, median (p90) | position jumps |
|---|---|---|---|
| room only | 49 / 50 / 50 / 50 / 50 | 0.02-0.05 (≤0.09) | 1-2 of 25 |
| pink 0 dB | 45 / 50 / 50 / 47 / 49 | 0.03-0.06 (≤0.11) | 0-2 |
| pink −5 dB | 43 / 47 / 43 / 39 / 42 | 0.03-0.08 (≤0.18) | 0-5 |
| blend 0 dB | 24-27 of 50 for the track; the others are the second track | 0.02-0.10 (≤0.15) | 0-1 |
| blend −6 dB | 39-40 for the track, 9-11 for the quieter one | 0.02-0.04 (≤0.07) | 0-1 |

- Vinyl skew error in noise is a median of 0.01 to 0.04 points, worst 0.26.
- A "position jump" is a match at a repeated chorus. It is rejected by checking a third match, as `Recognizer`
  already does for jumps.

### 4.6 Time to identification (window length)
- Clean, A2 catalogue, renders o, r+12, r−6, t+12, t−6, t+4:

| Window | 2 s | 3 s | 4 s | 5 s | 6 s |
|---|---|---|---|---|---|
| matched of 25 | 14-25 | 22-25 | 24-25 | 25 | 25 |

- With 4 s windows in noise (room, pink 0, pink −5), 24 to 50 of 50 windows matched: worst at pink −5 with t+4,
  best in the room proxy.
- ShazamKit streaming keeps querying, so missing the 15 s target on 85 percent of songs would take several
  consecutive failed windows *[inference: not measured live; misses in one song are correlated, not
  independent]*.

### 4.7 CPU per 60 s of audio, one M1 Max core (`cpu/cpu.swift`, two runs agree)
- Decode 0.09 s; varispeed 0.06 s; TimePitch 0.22 s.
- Signature generation 0.075 s.
- Streaming `SHSession` with continuous matching (49 matches) 0.55 s.
- So an original signature costs about 0.17 s of CPU per minute of track, and one listening stream about
  0.9 percent of a core.

### 4.8 Own tempo and key estimators (`tempo_est.py`, librosa, 8 s windows, 25 tracks)

| Condition | template tempo error median/p90 | blind beat tracking | frequency ratio | vinyl vs tempo-only right |
|---|---|---|---|---|
| room | 0.05-0.15 / 0.05-0.15 | 0.35-0.78 / 1.2-1.6 | 0.00-0.03 | 23-25 of 25 |
| pink 0 dB | 0.05-0.20 / 0.10-0.25 | 0.35-0.75 / 1.0-1.6 | 0.00-0.06 (one failure mode at r−10) | 19-25 |
| blend 0 dB | 0.05-0.15 / 0.10-0.15 | 3.6-4.7 / 26-33 | 0.00-0.06 | 16-25 |

## 5. Literature and prior art

**Panako** (Joren Six).
- Design: constant-Q spectral peak triplets. Time ratios and log-frequency differences inside a triplet make the
  hash invariant to time-scale and pitch changes. Matching yields the query offset plus the percentage of
  pitch-shift and time-scale (ISMIR 2014, https://archives.ismir.net/ismir2014/paper/000122.pdf).
- 2014 tests: 30,000 songs, 20 to 60 s queries, modifications up to ±16 percent. More than a third of queries
  were still found after an 8 percent time-stretch, and resampled queries degrade "severely above eight percent".
- Version 2.x moved to a Gabor transform and LMDB, and prints time and frequency factors per match. A poster plots
  84 to 116 percent (https://0110.be/files/attachments/498/panako_updates_poster.pdf).
- AGPL-3.0, Java (https://github.com/JorenSix/Panako).

**Olaf** (Six, JOSS 2023, https://joss.theoj.org/papers/10.21105/joss.05459).
- A C11 Shazam-style landmark fingerprinter for microcontrollers and WebAssembly: under 512 kB of memory for a 20 s
  query against an hour of audio.
- No stated pitch or tempo invariance; its eval notes Panako has the extra speed-change algorithm.
- AGPL-3.0, with a patent warning (https://github.com/JorenSix/Olaf).

**audfprint** (MIT, https://github.com/dpwe/audfprint) and **Dejavu** (MIT, https://github.com/worldveil/dejavu).
- Both use landmark pairs and claim no pitch or speed invariance.
- Panako's paper found audfprint fails above 3 percent pitch shift.
- A 2025 benchmark gives Dejavu 25 percent top-1 under time-stretch (https://arxiv.org/html/2511.05399).

**Qfp**, Sonnleitner and Widmer, "Robust quad-based audio fingerprinting", IEEE/ACM TASLP 24(3), 2016
(https://www.cp.jku.at/research/papers/preprint_TASLP2509248.pdf).
- Peak quads give hashes invariant to independent time and frequency scaling, and the system estimates the scale
  factors.
- 100,000 songs, 70 to 130 percent speed, tempo and pitch.
- With 20 s queries, accuracy 0.98 (speed), 0.98 (tempo), 0.94 (pitch). At 5 s queries, 0.77 / 0.71 / 0.56.
- No official code.

**DJ-mix identification**, Sonnleitner, Arzt and Widmer, ISMIR 2016
(https://www.jku.at/fileadmin/gruppen/173/Research/187_Paper.pdf).
- Compared audfprint, Panako and Qfp on real club mixes: accuracy of 25 to 74 percent.
- audfprint and Panako claimed a wrong track about half the time; Qfp was best.
- Conclusion: DJ-mix ID "indeed is a tough problem".
- Datasets: https://www.cp.jku.at/datasets/fingerprinting/. UnmixDB (Schwarz and Fourer 2018,
  https://zenodo.org/record/1422385) adds synthetic mixes with time-scaling and a stretch-factor estimator.

**Other invariant fingerprints.**
- Fenet et al., CQT hashing robust to pitch shift (ISMIR 2011, https://archives.ismir.net/ismir2011/paper/000041.pdf).
- Malekesmaeili and Ward, time-chroma fingerprints (https://arxiv.org/abs/1304.0793).

**Neural fingerprints.**
- NAFP (Chang et al. 2021, MIT code, https://github.com/mimbres/neural-audio-fp) is not trained for stretch: 39
  percent top-1 under time-stretch in the 2025 benchmark. A fine-tuned MuQ model reaches 87 to 96 percent there,
  at a model size unsuited to an always-on iPad loop *[inference]*.
- PeakNetFP (ISMIR 2025, https://arxiv.org/abs/2506.21086) reports over 90 percent top-1 for 50 to 200 percent
  time-stretch, with no code.
- None of the neural systems reports the scale factor, which Deckie needs.

**Commercial and DJ prior art.**
- **Beatport Track ID** (with seeqnc, May 12, 2026) is "optimized to recognize tracks that have been pitch-shifted,
  time-stretched" and matches against the Beatport catalogue
  (https://www.beatportal.com/articles/1405405-beatport-launches-track-id-a-music-discovery-tool-built-for-djs).
  - It gives no range or accuracy, and does not say whether recognition runs in the cloud.
  - seeqnc's site describes "real-time & cloud-scale" detection with no pitch figure (https://seeqnc.com).
  - *[inference: cloud, global catalogue; it does not read the fader.]*
- **djay's ShazamKit integration** syncs by "detecting and matching the exact part of the song" and says nothing
  about pitch (https://www.algoriddim.com/press_releases/438-algoriddim-integrates-shazamkit-technology-with-djay).
- **ACRCloud** says it supports pitch-shift and time-shift with no numbers (https://www.acrcloud.com/blog/pitch-shifting-supported/).
- **Audible Magic's** standard service handles "a few percent" and a premium tier handles more
  (https://www.audiblemagic.com/2024/06/06/audible-magics-broad-spectrum-detecting-transformed-audio/).
- **The closest public "solve" of this exact problem** is Apple's own suggestion of deliberately skewed reference
  copies. WWDC22 session 10028 says keeping the skew under 5 percent "should be safe"
  (https://developer.apple.com/videos/play/wwdc2022/10028/). The `frequencySkewRanges` property can only restrict
  a media item to skew bands, not widen them
  (https://developer.apple.com/documentation/shazamkit/shmediaitemproperty/frequencyskewranges).
- I found nobody who publishes reading the fader value from the room.

## 6. Licence and feasibility

| Component | Licence | Ships in Deckie? | Use |
|---|---|---|---|
| ShazamKit, AVAudioUnitTimePitch, Varispeed, AVAudioConverter | Apple SDK | yes | B (recommended) and A2 |
| Panako, Olaf | AGPL-3.0 | no | reference only |
| audfprint, Dejavu | MIT | yes | not robust; no value |
| Qfp | paper only | reimplementation, after a patent check | D, later |
| Signalsmith Stretch | MIT (https://github.com/Signalsmith-Audio/signalsmith-stretch) | yes | push-style stretcher for B, if TimePitch buffering is awkward |
| Bungee | MPL-2.0 (https://github.com/bungee-audio-stretch/bungee) | yes (file-level copyleft) | alternative |
| Rubber Band | GPL or commercial (https://breakfastquay.com/rubberband/license.html) | commercial licence only | not needed |
| SoundTouch | LGPL-2.1 (https://www.surina.net/soundtouch/license.html) | awkward on iOS | not needed |
| BTrack, aubio | GPL-3.0 | no | not needed: Music Understanding has beats |
| Essentia | AGPL-3.0 | no | lab only |
| madmom | code BSD, models CC BY-NC-SA | code only | lab only |

D3 holds for every option: audio stays on the device. Signatures are irreversible (WWDC23, cited in Track A), and
B even shrinks what the crate carries.

## 7. Open questions
1. **iPad cost of B.** CPU, heat and battery with 11 concurrent sessions over a 4-hour set. Is there any session
   limit? Is it cheaper to run all candidates only until the first match, then two?
2. **Live timing.** Does the offset drift keep its 0.05-point precision when timed by audio sample time from
   `matchStreamingBuffer` results? `predictedCurrentMatchOffset` jitter is unmeasured.
3. **Real master tempo.** Pioneer and Denon master-tempo algorithms differ from TimePitch and Rubber Band. Test a
   recording of a CDJ at t±8 and t±14 (Mike's set recording would do).
4. **False matches at scale.** Measure with 2,000-track crates and 11 streams, and with the 9-variant catalogue.
   Only 373 distractors and 25 queries were tested here.
5. **A real room.** Crowd noise, PA compression and an iPad microphone at 100 dB SPL. Mic placement against the
   booth monitor.
6. **On-device signature generation.** Per track on the A16, inside `BGContinuedProcessingTask`. It matters much
   less under B.
7. **Near zero.** Between −1 and +1 percent the key test cannot tell vinyl from tempo-only (a 1 percent shift is a
   sixth of a semitone). Does the DJ care? *[inference: no for the BPM readout, marginally for key.]*
8. **Wide range.** CDJ "WIDE" (±100 percent) and turntable ±50 are out of scope. B extends to them by adding
   candidates, A2 by adding signatures.

## Appendix: scratch files
- Location: `/private/tmp/claude-501/.../scratchpad/`.
- Tools: `ct/main.swift` (the tool with `p` and `~`), `drift.py`, `noisebench.py`, `mknoisy.py`, `mkrb.py`,
  `tempo_est.py`, `cpu/cpu.swift`.
- Outputs: raw bench and match outputs in `runs/`; test catalogues `orig`, `c5`, `c7`, `c9.shazamcatalog`.
- Nothing was written into the repo except this report. If the `p` stage and `~` chains are wanted, they are a
  roughly 30-line change to `deck-app/tools/catalogtool/main.swift`.
