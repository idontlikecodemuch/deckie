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
