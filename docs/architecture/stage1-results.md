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

## 1a. Music Understanding against the lab features (done Oct 27, 01:20)

Setup: `tools/mubench`, an iOS 27 app run in the iPad (A16) iOS 27.0 simulator on this Mac, reading the audio from
the host folder and writing the framework's raw `SessionResult` as JSON into `mixer/mu_raw/` (651 MB for 373
tracks; not committed). Scored by `mixer/bench_mu.py` against `mixer/features/<id>.json`; the per-track table is
`mixer/mu_bench.tsv`. The framework works in the simulator, so the benchmark needed no macOS 27 Mac and no
physical iOS 27 device. The run took 78 minutes of analysis time in two passes (the first pass lost 158 tracks to a
JSON encoding bug in the harness: a track that starts in silence reports minus infinity momentary loudness).

### Headline

Music Understanding reproduces the lab's beats, tempo, key and loudness closely enough to replace the Python stack
for those, is faster, and differs from the lab in two places where the lab is the weaker side (vocal activity and
structure). Decision D11 stands. Numbers over all 373 tracks:

| Measure | Result | Reading |
|---|---|---|
| Seconds per track | median 11.8, p90 17.0, max 31.3 (simulator on an M-series Mac) | the lab takes about 15 s per track on the same Mac with its GPU; a real iPad will differ, measure in stage 3 |
| Beat F-measure at 70 ms | median 0.987 against the lab's detected beats, 0.997 against its fitted grid; below 0.8 on 8 percent | the disagreements are the octave cases and the lab's own weak grids (below) |
| Downbeat F-measure at 70 ms | median 0.968 against detected, 1.000 against the grid; below 0.8 on 23 percent | see the breakdown |
| BPM | within 2 percent of the lab on 91 percent; an octave apart on 5 percent; a 7 to 10 percent gap on 3 percent | the octave cases all side with the lab, because the lab snaps to the file's tempo tag by design; the port needs the same felt-tempo alignment |
| Key, where the lab is confident (311 tracks) | exact Camelot on 83 percent, a neighbour on 13 percent, a conflict on 4 percent | at least as good as the lab's three-vote scheme; the conflicts are relative-key and fifth ambiguities |
| Key, where the lab is unsure (62 tracks) | exact 31, neighbour 18, other 52 percent | the lab's unsure keys are unsure; nobody has ground truth here |
| Key changes reported | median 1 per track | the framework's key-over-time is usable as one key per track with a change list |
| Integrated loudness | median difference +0.04 LU; never more than 1 LU | identical to pyloudnorm for practical purposes |
| Vocal activity per bar | correlation 0.64 with the lab's per-bar vocal probability; mean 0.53 against the lab's 0.87 | the lab's detector calls 87 percent of bars vocal, which the sprint's own README calls over-reporting and which is why mix windows came out short; the framework's lower, more varied signal is the likelier truth and must be checked by ear on a dozen tracks |
| Sections | recall 1.00 of the lab's 8-bar lattice boundaries within one bar, precision 0.24; about 15 sections and 57 phrases per track | the framework finds every boundary the lab found plus finer ones; the lattice step is built on top of its sections, not replaced by them |

### Where the downbeats disagree (84 tracks below 0.8 against the lab grid)

- 54 also disagree on beats: 20 are the octave cases, 37 are tracks where the lab's own grid confidence is below
  0.5 (the "about 30 wobbly grids" the brief mentions). Neither side is a reference there; those tracks need ears.
- 30 agree on beats but not bars: 13 are a half-bar phase shift (the framework's bar starts on the lab's beat 3),
  2 are weak lab grids, and 15 are something else. Among those 15: the framework drifts by one bar over a long
  track (T. Rex, 313 bars against 311), and at least one track is not in 4/4 at all (Lady Gaga and Bruno Mars,
  "Die With a Smile", where the framework reports three beats per bar and the lab forced a 4/4 grid). The framework
  handles time signatures the lab never considered.

### What this changes in the port plan

- Beats, tempo, key and loudness come from the framework. Keep the lab's octave alignment to the tag (or the
  felt-tempo rule) and the constant-grid fit on top of the framework's beats, so the existing confidence rules and
  the drift check keep working.
- The vocal timeline comes from the framework's instrument activity, with thresholds retuned: the lab's 0.5 cut on
  a signal that averages 0.87 does not transfer to a signal that averages 0.53. Listening check first.
- The 8-bar lattice and the mix windows are computed from the framework's sections and phrases plus the grid, as
  planned. The lab's Foote-novelty block is not needed.
- New: carry the bar length (beats per bar) per track; do not assume 4/4.
- Not yet measured: a physical iPad or iPhone (speed, battery, thermal), and the second-opinion trigger rate, which
  needs the port's grid-fit confidence to exist first.

## 1c. Key over time (done Oct 27, morning)

Question from Christopher: does the analysis know when a song changes key or tempo partway through, or only the
whole song? Tempo: the framework's beat list follows a change (Get Ur Freak On's transition edit reads 70, 75, 89,
89 BPM in successive windows, where the lab's single grid said 90 and its start-tempo regression said 93). Key: the
framework's API returns key as time ranges, so it was tested on songs with textbook final-chorus modulations from
the library, run through `tools/mubench` in the simulator, with the lab's Essentia key model run in 20-second
windows as the check that the modulations are really in the files.

| Song | Framework | Essentia in 20 s windows | Known |
|---|---|---|---|
| Beyoncé, Love On Top | one range, C major, whole song | C to 180 s, then C#, D, Eb, E in 20 s steps | four semitone steps at the end |
| Whitney Houston, I Will Always Love You | one range, A major | A to 180 s, then B | up a tone for the last chorus |
| Céline Dion, My Heart Will Go On | one range, E major | E (with its relative minor and dominant flickering) to 260 s, then Ab | up for the last chorus |
| Aerosmith, I Don't Want to Miss a Thing; Boyz II Men, End of the Road | one range each | not checked | |
| Ricky Martin, Livin' La Vida Loca | one range, C# minor | C# minor throughout | no modulation after all |
| Beyoncé, Crazy In Love (control) | one range, G minor | G minor, D minor and B-flat alternating | no modulation; the windowed estimator flickers among related keys |

Findings:

- The framework's key-over-time did not report any of three clear modulations. In practice it gives one key per
  track, like the lab. It is a good whole-song key (section 1a) and nothing more.
- A windowed key estimate finds real modulations easily, but on ordinary songs it flickers between a key, its
  relative and its dominant, so it needs hysteresis: report a change only when it persists and is at least a
  semitone away from the running key.
- The key that matters for a join is not the song's key. It is the key of the outgoing track at its mix-out window
  and of the incoming track at its mix-in window. For Love On Top that is E major, two Camelot steps from the C
  major every whole-song analysis reports; for Whitney it is B, not A. Both the lab and the framework would mis-key
  the join on these.

Port-plan adjustment: keep the framework's whole-song key as the track's key, and add a small windowed key
estimator (the HPCP vote already planned as the second opinion) over the mix-in and mix-out windows, plus a
persisted change list for the few tracks that modulate. The scorer's key term reads the window keys, not the
song key. Cost: a few hundred milliseconds per track on top of the framework.

## 1d. Recognition across the fader range (done Oct 27, afternoon)

Follow-up to 1b by a research agent, report `docs/research/h-pitch-robust-recognition.md`, 25 tracks, offline
renders with synthetic room noise; nothing through a real microphone yet. Findings: one signature tolerates about
plus or minus 4 percent in every mode (time-stretch, pitch shift, vinyl-style) and fails at 5; frequency skew reads
vinyl-style pitch to within 0.03 points from one 8-second match; two matches 8 seconds apart give the tempo-only
ratio to 0.02 to 0.05 points, where the app today waits 20 seconds and rounds to 0.5; estimating tempo from live
beats alone is off by 0.35 to 1.6 points and by 4 during a blend, so beat tracking is a refinement, not a primary.
Recommendation and measurements: see the report and proposal P11.

## 1e. Key over time, round two: Apple's detector on windows (Oct 27, afternoon)

Christopher's question: key markers matter in the analysis, not live; what if we run Apple's framework on segments
we identify? Tested with a window mode in `tools/mubench` (`-keywindows 30 -keyhop 10`): each window is cut from the
file as a temporary PCM file and the framework's key analysis alone is run on it, about 0.6 s per 30 s window in the
simulator (17 s for a four-minute track at a 10 s hop; 3 windows, the two mix windows and the whole, would be under
2 s).

| Song | Apple's key per 30 s window, hop 10 s | After the hysteresis rule |
|---|---|---|
| Love On Top | C major for 18 windows, then C#, (F#), D, D, Eb, (Ab), E, E, E | C major, then E major from 240 s |
| I Will Always Love You | B minor, F# minor (the a cappella start), A major x 15, B major x 10 | A major from 20 s, B major from 170 s |
| My Heart Will Go On | E major (with its relative minor), then Ab major from 180 s | E major, then Ab major from 180 s |
| Livin' La Vida Loca (control) | C# minor in all 24 windows | one segment |
| Crazy In Love (control) | G minor with its relative Bb major, D minor and F major | one segment once the first segment is seeded with the song key |

Compared with the lightweight estimator built earlier today (`mixer/key_light.py`: FFT chroma, three chroma
variants, seven published key profiles, Pearson correlation): as a whole-song detector the best lightweight variant
reached 75 percent exact against the lab's confident keys where Apple reaches 83; on windows it caught the same
modulations but flagged a key change on 27 of 60 ordinary songs with a full segmentation, and on 4 to 20 percent of
tracks with an ends-only rule, because pop songs cycle through chords and a window reads the chord as the key.
Apple's windows are far cleaner (Livin' La Vida Loca: 24 identical windows). Full table: `mixer/key_light_*.tsv`,
`mixer/key_ends_*.tsv`.

Design that follows (refines D13): the song key is Apple's whole-track key; key segments come from Apple's key
analysis on windows, seeded with the song key, with the hysteresis rule (a new key opens a segment only when it is
outside the running key's tonal area, which is the same key, its relative, a wheel neighbour or the parallel mode,
and persists for two windows if far on the wheel and four if near); the join reads the key of the segment that
covers each mix window. Minimum cost version: three analyses per track (mix-in window, mix-out window, whole).
The lightweight estimator stays in the lab as the level-2 fallback candidate. False-change rate on 60 ordinary
tracks with Apple's windows: see below when the run completes.

False-change rate, Apple's windows on 60 ordinary tracks (30 s windows, 15 s hop, seeded with the song key,
hysteresis rule): 9 of 60 open a second segment, against 27 of 60 for the lightweight estimator. Of the nine, some
are real (the Chris Lorenzo versus Black Eyed Peas wordplay edit changes song at 270 s; Get Ur Freak On is a
transition edit; I Put A Spell On You has a rubato ending; Deep Inside changes at 435 s of a long cut) and the
rest alternate between two areas all the way through (Lose Control, Demonique, We Found Love), which is ambiguous
material rather than a modulation. The median track has 100 percent of its windows inside the song key's tonal
area; the alternating ones sit at 31 to 60 percent. Rule that follows: store a key stability per track (the share
of windows inside the song key's area) and treat it as the key confidence the scorer already weighs, so an
ambiguous track gets a soft key rather than a wrong verdict, consistent with "key is a warning, not a score to
chase". The segment covering each mix window supplies that window's key.

## 1f. The two quick wins, built and measured (Oct 28, morning)

The interim fixes from track H are in the existing Deck app (commit "pitch reading across the fader range"). Measured
in the iOS 27 simulator by streaming a known track through the app's own microphone path at rendered pitch settings:

| Setting | What the app reads | When |
|---|---|---|
| tempo-only +3 | 3.3, then 3.2 to 3.4 | from 14 s |
| tempo-only +10 | 8.0 from the matched variant at 4 s; 9.2 at 12 s; 10.0 by 26 s; then 9.7 to 10.3 | |
| tempo-only +16 | 16.0 from the variant at 4 s; 16.0 to 16.3 from 11 s | |
| vinyl +12 | 11.9 to 12.0 | 3 s |
| vinyl -16 | -16.0 | 4 s |

Before this change the app matched nothing beyond 8 percent, reported a tempo-only variant's own percent for the rest
of the song, and read drift only after 20 s, rounded to 0.5. The catalogue is now nine signatures per track (about
160 MB in the bundle, fine for a development install, wrong for a shipped crate, which is why P11 proposes the
multi-matcher). The drift fit is a median of pairwise slopes on an audio clock; a least-squares version was pulled by
one stray match from 10.0 to 5.3 for four seconds, the median version was not. Not yet measured: a real room, and the
iPad itself. Install command: `deck-app/README.md`.

## 1g. Do beats need a model? (Oct 28)

Asked by Christopher. Two model-free methods scored against the shipped grid (Beat This! or madmom plus the lab's
grid fit). Tempo from Essentia's signal-processing estimator, already in the feature files, on all 373 tracks: within
2 percent of the grid's BPM on 343 (92 percent), double or half on 26 (7 percent), wrong on 4. Beats from librosa's
dynamic-programming tracker (onset strength, autocorrelation, no weights), 60 tracks sampled evenly: tempo within 2
percent on 38 (63 percent), wrong on 13; beat F-measure at 70 ms mean 0.63 (the model: 0.987), at least 0.9 on 19 of
60; allowing half or double tempo, mean 0.73. Bar 1 (the downbeat) by a plain heuristic on the lab's own beats, the
beat class with the most low-band onset energy: right on 28 of 60 (chance is 15), by overall spectral flux 14 of 60.
About one second a track. Reading: tempo mostly does not need a model; beat positions and above all the bar line do,
and the bar line is what phrase-aligned mixing needs. A model-free path remains the named fallback for tempo and a
rough grid when no model is present (D15 replacement path), not a substitute. Script: scratchpad `modelfree/run.py`.

## 2a. The PC and Linux engine on the 373-track yardstick, run on the Mac (Oct 28)

The first run of `deckie-build bench` (branch `pc-linux-step2` at 439a6bc, built in release on this Mac) over all 373
lab tracks, two jobs at the lowest priority while Christopher used the machine. ONNX Runtime 1.31.1, Microsoft's
macOS build with its reporting switched off (archive 2e1344a1…, library 17500d6b…, both as pinned). Beat This!
exported here from the cached checkpoint with torch 2.14.1 (graph 442de936…, numerically within 3e-5 of PyTorch;
the pinned graph f1d93204… was published as release `models-1` after this run). No vocal tagger in this run; the
second run with YAMNet (96bb0dc5…, from the release) follows as 2b. Engine record: {"tool": "deckie-build 0.1.0", "engine": "deckie-0.1.0", "platform": "macos-arm64", "vocal_model": null}.
Full per-track figures: `bench/pc-engine-2026-10-28-mac.json`.

```
Over 373 tracks:
  beat F@70ms, detected vs detected          median 1.000  mean 0.998  below 0.8: 0.8 percent  (n 373)
  beat F@70ms, grid vs grid                  median 1.000  mean 0.967  below 0.8: 5.1 percent  (n 373)
  beat F, best octave                        median 1.000  mean 0.999  below 0.8: 0.5 percent  (n 373)
  downbeat F, detected vs detected           median 1.000  mean 0.997  below 0.8: 0.8 percent  (n 373)
  downbeat F, grid vs grid                   median 1.000  mean 0.950  below 0.8: 6.2 percent  (n 373)
    lab grid from beatthis: beat, grid       median 1.000  mean 0.999  below 0.8: 0.3 percent  (n 316)
    lab grid from beatthis: downbeat, grid   median 1.000  mean 0.999  below 0.8: 0.3 percent  (n 316)
    lab grid from madmom: beat, grid         median 1.000  mean 0.793  below 0.8: 31.6 percent  (n 57)
    lab grid from madmom: downbeat, grid     median 1.000  mean 0.680  below 0.8: 38.6 percent  (n 57)
  tempo within 2 percent: 99.7 percent after octave normalisation, 98.9 percent without; an octave apart: 0.8 percent
  key, all tracks: exact 68.9 percent, neighbour 14.5 percent, other 16.6 percent
  key, lab confident (311): exact 74.6 percent, neighbour 14.5 percent, other 10.9 percent
  integrated loudness delta (LU)             median 0.00  mean 0.00  median |x| 0.00  (n 373)
                                             more than 1 LU off: 0.0 percent
  true peak delta (dB)                       median 0.00  mean 0.02  median |x| 0.00  (n 373)
  section recall (within a bar)              median 1.00  mean 0.95  (n 363)
  section precision                          median 1.00  mean 0.95  (n 363)
  vocal correlation: absent (the engine ran without its vocal tagger)
  bar 1 offset (ms, engine - lab)            median 0.0  mean -11.4  median |x| 0.0  (n 373)
  bar counts equal: 95.7 percent
  seconds per track: median 9.2, p90 13.4, max 26.7 (n 373)

Pass marks (charter: at least Apple's framework on beats and loudness, stage 1 1a; the key estimator's 75 percent exact). Reference marks are Apple's other figures:
  charter   beat F@70ms, detected vs detected, median                  1.000  >= 0.987  pass
  charter   beat F@70ms, detected vs detected, share below 0.8         0.008  <= 0.078  pass
  charter   beat F@70ms, grid vs grid, median                          1.000  >= 0.997  pass
  charter   beat F@70ms, grid vs grid, share below 0.8                 0.051  <= 0.145  pass
  charter   downbeat F@70ms, detected vs detected, median              1.000  >= 0.968  pass
  charter   downbeat F@70ms, detected vs detected, share below 0.8     0.008  <= 0.185  pass
  charter   downbeat F@70ms, grid vs grid, median                      1.000  >= 1.000  pass
  charter   downbeat F@70ms, grid vs grid, share below 0.8             0.062  <= 0.225  pass
  charter   integrated loudness, median |delta| (LU)                    0.00  <= 0.04  pass
  charter   integrated loudness, share more than 1 LU off              0.000  <= 0.000  pass
  charter   key exact where the lab is confident                       0.746  >= 0.750  FAIL
  reference tempo within 2 percent (no octave normalisation)           0.989  >= 0.914  pass
  reference key exact where the lab is confident, against Apple        0.746  >= 0.833  FAIL
  reference per-bar vocal correlation, median                              -  >= 0.645  n/a
  reference section boundary recall within one bar, median             1.000  >= 1.000  pass
charter pass marks: not all met
```

Reading. Beats, downbeats, tempo, loudness and sections match the lab at or above the charter's marks, and the beat
tracker is Beat This! on both sides, so where the lab's grid came from Beat This! (316 tracks) the engine's grid is
the lab's to 0.999; the 57 tracks where the lab fell back to madmom are where the two disagree, which says the
engine reproduces the model and not the lab's fallback rule. Tempo within 2 percent on 98.9 percent, against
Apple's 91. Loudness identical to 0.01 LU. One true-peak outlier of 6.7 dB and one bar-1 offset of 2 s are for the
session to look at. The one mark missed is key: 74.6 percent exact where the lab is confident, against the charter's
75 and Apple's 83.3; with neighbours (compatible keys on the wheel, still a clean mix) 89.3 percent, against Apple's
96. The engine's estimator is the lab's own one-vote method, since every stronger open detector is unshippable
(track L); the lab's key was a three-way vote that included Essentia's non-commercial models. So on Mac and iPad the
key comes from Apple's framework (D11), and on PC and Linux the estimator needs a second vote or better profiles
before it meets the mark. 9.2 s per track median on this Mac at low priority with two jobs.

## 2b. The same run with the vocal tagger (Oct 28, late)

A fresh run with YAMNet from release `models-1` (96bb0dc5…), everything else as 2a. Every other column came out
identical to 2a. Vocal correlation per bar against the lab: median 0.31, mean 0.32 (n 373), against the reference
mark of Apple's 0.645; the time per track rose to 11.1 s median, 25.7 s at the 90th percentile.

A three-way comparison on the lab's bar grid (`mixer/vocal3way.py`, rows in `bench/vocal-3way-2026-10-28.json`;
357 tracks where the engine's bar count matches the lab's and Apple's series exist):

| per-bar correlation, median | |
|---|---|
| Apple against the lab | 0.64 |
| engine (YAMNet) against Apple | 0.49 |
| engine (YAMNet) against the lab | 0.31 |

Mean level of the series: lab 0.81, Apple 0.51, engine 0.017; the engine's mean is below 0.02 on 264 of 357
tracks. Reading: YAMNet's singing-class scores sit near zero on most full mixes, because a mix scores as "Music"
and the voice classes get what is left, so the per-bar series is mostly noise around a floor; it follows Apple
more than it follows the lab (0.49 against 0.31), which says the lab's own reference is part of the gap, but it is
far from either. The reading of YAMNet has to change before the listening set calibrates anything: which classes
are summed, whether the logits rather than the sigmoid scores are read, or the second opinion (PANNs MobileNetV2).
This is a reference mark, not a charter mark, and the Apple apps take the vocal signal from Apple (P13).
