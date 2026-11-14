# Research X2: the own-key trial

Dated Nov 13, 2026. A trial with measurements, no decisions. It asks whether a key reader Deckie owns can be good
enough to show, starting with the mode. Builds on letter R (every earlier key test), letter T (the options), letter X
(the web research on the mode, read and merged during the trial) and on D5, D15, D16, D17 and D29. Bench and
experiments: `mixer/keytrial/` (commands in its `README.md`); running notes: `docs/research/briefs/checkin-key.md`.
**Everything trained here is for evaluation only. Nothing trained ships, and no audio, data set or weights are in the
repository.** Tags: [2nd] = read in a paper or page, not tested here; [inf] = my inference, with the reasoning;
[unmeasured] = not measured. Not legal advice.

## In plain words

A song's **key** is two things. The **home note** is the note the music keeps coming back to and feels finished on
(the A in "A minor"). The **mode** is the flavour of the scale built on it: **major** sounds bright, **minor** sounds
dark. DJs write keys as **Camelot codes** (a number 1 to 12 and a letter, A for minor, B for major); two songs with
the same code, or codes one step apart on the wheel, usually blend.

A computer reads the key by measuring how loud each of the twelve notes is across the song (a twelve-number summary
called the **chroma**) and matching that against a **profile**, a template of how much of each note a key tends to
have. Every played note also sounds fainter, higher notes at the same time, its **overtones**; letter R showed these
were pushing our reader toward major, and took them out two ways: by simple arithmetic (**row A**) and by working out
which notes were actually played (**row B**, note transcription). **Row 3f** is the reader before either.

A **trained** reader is one whose numbers were adjusted on songs with known keys. To score one fairly it must be
tested on songs it never learned from: here the songs are cut into five **folds** with every artist kept inside one
fold, the reader learns on four and is scored on the fifth, and it is also scored on a different collection
altogether. **Held-out** means "not used for any choice".

Three scores are used throughout. **Exact**: the key is right. **Home note**: the home note is right, whatever the
mode. **Mode given home**: of the songs whose home note is right, how many have the right mode. Two more came in with
letter X and the owner's direction during the trial: **within one step** (the key is right, or is the neighbour on the
Camelot wheel, or is the relative key that shares all its notes: the mistakes that still mix), and **precision
against coverage**: if the reader may say "not sure", what share of songs get a key (coverage) and how often a shown
key is right (precision).

## Summary

- **The bench is sound.** Letter R's three readers, re-run from scratch, give the same key as its sheets on all
  1,275 clips. Three outside sets were fetched for evaluation (2,090 recordings; none committed). Folds are grouped by
  artist.
- **The mode alone cannot meet D16's bar as written.** With row B's home note, a *perfect* mode would score 70.4 on
  the minor half; the bar is 70.6. The home note is right on 72 percent of clips, and on minor clips Apple's is 8
  points better than ours.
- **Nobody hears the mode well.** Given the true home note, 46 rules were tried. The best name the mode right about
  80 percent of the time with major and minor counted equally, and the plain profile match on an overtone-cleaned
  chroma is already there (79). Reading the third, sixth and seventh from the bass line alone (64 to 69), from the
  melody register alone (74 to 78), only where the harmony is stable (76 to 77, worse than where it is not), from
  the chord on the home note over time (69 to 71) or only above the home note in the bass (69 to 75) **did nothing
  or did harm**. Small trained mode rules reach 78 to 80: they choose where to lean, they do not hear better. Apple
  by the same measure: 77.
- **The best reader with nothing trained** is row B's home note with row A's mode: 57.8 exact on MTG (Apple 65.2),
  76.9 on GiantSteps+, 60.9 on the 604-clip set. It fails the bar as written by 16 points on the minor half.
- **A trained model of Deckie's own passes the bar** (evaluation only). A small convolutional model (236,006
  numbers, 0.95 MB, 0.05 s a song for the model and 0.35 s for its spectrogram on one CPU thread), trained on four
  artist-grouped folds and scored on the fifth: **65.9 exact against Apple's 65.2; 44.0 on the major half (bar 36.5)
  and 75.5 on the minor half (bar 70.6)**. Song for song it is level with Apple (p 0.57). Trained on MTG and scored
  on other sets: 82.9 on GiantSteps+ and 68.7 on the 604-clip set, where the published network scores 67.9, Mixed In
  Key 7: 67.2 and rekordbox 3: 71.9.
- **Forty-nine learned numbers go most of the way**: profiles learned on rows A and B's chroma score 62.7 on MTG and
  66.2 on the 604-clip set, and need only about 400 labelled songs.
- **Both trained readers win by leaning minor, as Apple does.** On the mean of the major and minor halves, rows A
  and B, the learned profiles, the trained model and Apple all score 55 to 60. A model trained on an 85-percent-minor
  set reads 4 percent of major-key songs right on another set.
- **Precision against coverage** (the owner's measure). Nothing trained: a key on 70 percent of songs, right 65
  percent of the time on MTG (Apple's and Mixed In Key 7's overall rate), 85 on GiantSteps+; never ahead of Apple on
  the same songs. Trained model: right 74.5 percent of the time on the 80 percent of songs it is surest of, **ahead
  of Apple on those same songs** (71.6; p 0.01), and its stated confidence is calibrated to within 3 points.
- **Nothing trained here can ship.** The training labels are CC BY-SA and the audio is not Deckie's. A commissioned
  set of 400 to 600 songs to fit and 300 to score, of mixed styles with at least a third in major keys, would back
  the small reader.
- **Not verified:** anything on music that is not club dance music; whole songs instead of two-minute clips; Apple on
  the two GiantSteps sets; more than one training run of the model.

## 1. The bench

### 1.1 Data fetched (evaluation only; none committed)

| Set | Source | Clips | Size | Licence | Role here |
|---|---|---|---|---|---|
| GiantSteps-MTG-key ("MTG") | Zenodo record 1101082 | 1,486 two-minute Beatport clips; 1,275 with a plain major or minor label (388 major, 887 minor); Apple read 1,270 of them (386, 884) | 2.13 GB, MD5 matched Zenodo's | labels CC BY-SA 4.0; audio Beatport's and the labels' | the set D16's bar is defined on; the only set with Apple's reading |
| GiantSteps+ | Zenodo record 1095691 | 600 clips; 468 with one key (58 major, 410 minor, a modal label such as "F minor aeolian" counted by its third); 230 with a plain label | 856 MB | labels CC BY-SA 4.0; audio Beatport's and the labels' | the clean set: none of our profiles was made from it |
| GiantSteps Key | labels from the data set's repository; audio from the JKU mirror | 604 clips (93 major, 511 minor), the original labels | 834 MB, all 604 checksums matched | none stated; audio Beatport's and the labels' | the set the published tool scores are on |

GiantSteps+ and GiantSteps Key are the same recordings with different labels (599 clip ids in common). No clip is
shared with MTG; 36 artist or remixer names are, on 39 MTG clips, which are left out of training whenever something
trained on MTG is scored on the other two. The data set's own download script was read, not run. Billboard,
Isophonics, FMAK and the other sets in letter T's list were not fetched: none bundles audio (see "What I could not
verify").

### 1.2 Does the bench reproduce letter R?

Yes, exactly. Rows 3f, A and B were re-run from this trial's own decode with letter R's code unchanged
(`mixer/key_parity.py`, `mixer/key_overtones.py`). **All three give the same key as letter R's committed sheet on
1,275 of 1,275 clips**, and every figure of its tables is reproduced to the decimal (exact 47.4, 55.4, 55.4; home note
68.8, 68.9, 72.2).

### 1.3 The protocol, fixed before any experiment

- **Folds.** Five, grouped by artist: clips that share any credited artist or named remixer fall in one group (1,269
  groups on MTG), groups dealt to folds so each has 255 clips and 69 to 70 percent minor. A clip's fold depends only
  on the data set's spreadsheet.
- **Untrained rules** have no fitted value. Where one is picked among several it is picked on folds 0 to 2 (765
  clips) and reported on folds 3 and 4 (510 clips, the held-out part).
- **Trained rules** are fitted on four folds and scored on the fifth, so every clip is scored by a reader that never
  saw it or its artist; and fitted on one set and scored on another. Settings were fixed before the run.
- **Tests.** A paired sign test on the clips where two readers differ (letter R's test), and 95 percent Wilson
  intervals on rates.

### 1.4 Where the readers stand on every set

Percent of clips. "Mean of halves" is the exact rate on major clips and on minor clips, averaged, so that leaning
toward one mode cannot buy points.

| Set | Reader | Exact: all | major | minor | Mean of halves | Within one step | Home note: all | major | minor | Mode given home: major | minor |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MTG, 1,270 | Apple | 65.2 | 41.5 | 75.6 | 58.5 | 78.3 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 |
| | 3f | 47.6 | 60.6 | 41.9 | 51.2 | 63.5 | 69.1 | 70.2 | 68.6 | 86.3 | 61.1 |
| | A | 55.6 | 53.9 | 56.3 | 55.1 | 72.0 | 69.1 | 74.6 | 66.6 | 72.2 | 84.6 |
| | B | 55.6 | 63.2 | 52.3 | 57.7 | 69.0 | 72.4 | 77.2 | 70.4 | 81.9 | 74.3 |
| GiantSteps+, 468 | 3f | 69.2 | 70.7 | 69.0 | 69.9 | 82.5 | 77.8 | 74.1 | 78.3 | 95.3 | 88.2 |
| | A | 70.9 | 63.8 | 72.0 | 67.9 | 85.9 | 75.0 | 75.9 | 74.9 | 84.1 | 96.1 |
| | B | 75.9 | 69.0 | 76.8 | 72.9 | 85.9 | 80.3 | 75.9 | 81.0 | 90.9 | 94.9 |
| GiantSteps Key, 604 | 3f | 54.5 | 44.1 | 56.4 | 50.2 | 71.5 | 65.4 | 54.8 | 67.3 | 80.4 | 83.7 |
| | A | 57.1 | 41.9 | 59.9 | 50.9 | 76.0 | 63.4 | 60.2 | 64.0 | 69.6 | 93.6 |
| | B | 59.9 | 43.0 | 63.0 | 53.0 | 76.2 | 67.1 | 60.2 | 68.3 | 71.4 | 92.3 |

Three things to carry forward.

- **D16's bar** on MTG is 36.5 on the major half and 70.6 on the minor half (Apple's 41.5 and 75.6, less five).
- **The home note sets a limit the mode cannot lift.** Our best home note on minor clips is 70.4 (row B). A reader
  that named the mode perfectly on row B's home note would score 70.4 on the minor half: under the bar by 0.2 before
  a single mode mistake. Apple's home note on minor clips is 78.8.
- **GiantSteps+ is far kinder than MTG to every reader** (row B: 75.9 exact against 55.6). Letter X warned that MTG
  might flatter our profiles because two of them were made from that collection. It does not: the set the profiles
  never saw scores 20 points higher. MTG is the harder set and the less minor one (70 percent against 88) [measured;
  why it is harder is not established: its labels are one annotator's first pass, GiantSteps+ is a careful revision].

## 2. The mode alone

Script `kt_mode.py`; every rule's figures in `mode_results.tsv`; per-clip answers of the main rules in
`mode_clips.tsv`. 46 rules, all on the 1,275 MTG clips.

### 2.1 The ceiling: the true home note is given

How often the mode is right, on major and minor clips. "Balanced" is their mean: a rule that always says minor scores
50. The baseline is what the reader does today: row B's profile match, restricted to the given home note. "Gained /
lost" counts held-out clips (folds 3 and 4) the rule gets right and the baseline wrong, and the reverse.

| Idea | Rule | Major | Minor | Balanced | Held-out balanced | Held-out gained / lost | p |
|---|---|---:|---:|---:|---:|---:|---:|
| **Baseline** | profile match, row B's chroma | 83.8 | 73.5 | 78.6 | 78.3 | | |
| Overtones out, simple | profile match, row A's chroma | 74.5 | 83.4 | 79.0 | 79.8 | 50 / 21 | 0.001 |
| Before either | profile match, row 3f's chroma | 88.1 | 64.3 | 76.2 | 76.1 | 25 / 47 | 0.013 |
| Third alone | louder third, row B's chroma | 90.5 | 56.3 | 73.4 | 72.6 | 27 / 85 | <0.001 |
| Third, sixth, seventh | on row A's chroma | 74.0 | 82.1 | 78.0 | 78.3 | 51 / 33 | 0.06 |
| | on row B's chroma | 89.7 | 62.6 | 76.1 | 74.9 | 18 / 54 | <0.001 |
| **Bass line alone** | third, by time on each bass note | 67.8 | 68.2 | 68.0 | 69.8 | 55 / 93 | 0.002 |
| | third, sixth, seventh, by time | 68.3 | 65.5 | 66.9 | 69.1 | 48 / 94 | <0.001 |
| | profile match on the bass line | 55.7 | 82.3 | 69.0 | 70.1 | 58 / 68 | 0.42 |
| | third, by loudness in the bass octaves | 64.2 | 63.7 | 63.9 | 64.1 | 44 / 111 | <0.001 |
| **Melody register alone** | third | 89.2 | 59.1 | 74.1 | 71.3 | 41 / 100 | <0.001 |
| | third, sixth, seventh | 84.3 | 70.3 | 77.3 | 76.3 | 45 / 58 | 0.24 |
| | profile match | 86.6 | 68.8 | 77.7 | 75.5 | 40 / 60 | 0.06 |
| | top line, third, sixth, seventh, by time | 84.8 | 68.4 | 76.6 | 75.2 | 44 / 65 | 0.05 |
| **Where the harmony is stable** | profile match, stable half of the frames, row B | 83.8 | 68.8 | 76.3 | 75.9 | 16 / 32 | 0.03 |
| | the same, row A | 72.4 | 81.8 | 77.1 | 77.5 | 49 / 30 | 0.04 |
| | control: the *unstable* half, row B | 83.5 | 75.1 | 79.3 | 79.0 | 15 / 9 | 0.31 |
| **The chord on the home note over time** | time on the home note's minor triad against its major triad | 88.9 | 48.3 | 68.6 | 68.1 | 33 / 120 | <0.001 |
| | frames where the home chord sounds: louder third | 88.7 | 48.5 | 68.6 | 67.3 | 31 / 124 | <0.001 |
| | chord families (time on the six chords of the minor key against the six of the major) | 91.5 | 51.2 | 71.3 | 70.4 | 25 / 100 | <0.001 |
| **Above the home note in the bass** (letter X) | third, in the frames where the bass sits on the home note | 89.4 | 49.2 | 69.3 | 67.4 | 36 / 128 | <0.001 |
| | third, sixth, seventh, same frames | 86.3 | 63.0 | 74.7 | 72.6 | 35 / 76 | <0.001 |
| **Small trained rules** (evaluation only) | logistic regression on row A's chroma turned to the home note, 12 numbers | 61.1 | 94.9 | 78.0 | 75.7 | 77 / 43 | 0.002 |
| | the same, major and minor weighed equally | 75.8 | 84.0 | 79.9 | 82.0 | 61 / 24 | <0.001 |
| | on row B's chroma, 12 numbers | 63.1 | 93.9 | 78.5 | 78.4 | 71 / 31 | <0.001 |
| | the same, weighed equally | 77.3 | 82.5 | 79.9 | 79.9 | 41 / 18 | 0.004 |
| | on every measurement above, 135 numbers | 65.7 | 91.2 | 78.5 | 77.5 | 65 / 37 | 0.007 |
| | the same, weighed equally | 74.7 | 82.2 | 78.5 | 76.7 | 50 / 43 | 0.53 |
| | boosted trees on every measurement | 62.6 | 94.4 | 78.5 | 77.8 | 74 / 36 | <0.001 |
| For scale | Apple, on the clips whose home note it has right | 58.6 | 95.8 | 77.2 | | | |

The best untrained rule on the selection folds was the control, the *unstable* half of the frames (79.5 there); on the
held-out folds it scores 79.0 against the baseline's 78.3, gained 15, lost 9, p 0.31: nothing.

**What this says.**

- **Nothing names the mode better than about 80 percent, balanced, even with the true home note in hand.** The whole
  table sits between 64 and 80. The profile match on an overtone-cleaned chroma (rows A and B, 79) is already at the
  top, and the trained rules do not pass it (78 to 80).
- **The ideas the brief asked for did nothing or did harm.** The bass line alone: 64 to 69, clearly worse. The melody
  register alone: 74 to 78, a little worse. Chroma where the harmony is stable: worse than where it is not (76.3
  against 79.3 for row B), so "stable" frames carry less of the mode, not more [inf: in this music a held chord or
  drone is often the bare home note and fifth; the third arrives in the moving parts]. The chord on the home note
  over time: 68 to 71, the worst family. The mode asked only above the home note in the bass: 69 to 75, worse.
- **Every rule built on the third alone reads half of the minor clips as major** (48 to 59 percent of minor clips
  right), on every chroma, in every register, and when restricted to the frames where the home chord sounds. Letter
  R found this for the whole-clip third; it holds everywhere I looked. In this music the major third above the home
  note is as loud as the minor third in about half of the songs that people label minor, and taking overtones out,
  listening only to the bass or the lead, or only on the home chord does not change that.
- **The significant "gains" in the table are leans, not hearing.** The rows with small p-values gain on minor clips
  and lose on major ones (or the reverse); their balanced score does not move. The paired test counts clips, and
  MTG has 2.3 minor clips for every major one, so any rule that says "minor" more often wins the count.
- **Apple hears the mode no better than we do** (77.2 balanced against 78 to 79). It says minor nearly always when
  unsure: 95.8 percent right on minor clips, 58.6 on major. This confirms letter X's arithmetic from the per-clip
  results.

### 2.2 What would ship: the reader's own home note

Exact key on the 1,270 clips Apple read, with row B's home note (right on 72.4 percent) and the mode from each rule.

| Mode rule on row B's home note | Exact: all | major | minor | Mean of halves | Bar as written |
|---|---:|---:|---:|---:|---|
| Row B itself | 55.6 | 63.2 | 52.3 | 57.7 | fails, minor 23.3 short |
| **Row A's mode** (letter X's first ask; nothing trained) | 57.8 | 54.4 | 59.3 | 56.8 | fails, minor 16.3 short |
| Published second-minor-template steps on row B's chroma (nothing trained by us) | 59.3 | 41.7 | 67.0 | 54.3 | fails, minor 8.6 short |
| Trained 12-number mode rule (evaluation only) | 60.2 | 46.9 | 66.0 | 56.4 | fails, minor 9.6 short |
| Always minor | 49.0 | 0.0 | 70.4 | 35.2 | fails |
| A perfect mode (the limit) | 72.4 | 77.2 | 70.4 | 73.8 | fails, minor 0.2 short |
| Apple | 65.2 | 41.5 | 75.6 | 58.5 | |

Row A's mode on row B's home note against row B alone, held-out folds: gained 31, lost 17, p 0.06; all clips: gained
79, lost 51, p 0.02. It is a real but small gain (+2.2 exact), and it is a trade: 8.8 points off the major half for
7.0 on the minor half.

**The trade-off curve** (letter X): with row B's home note and row A's mode score, moving the threshold from "always
major" to "always minor":

| Clips called minor | Exact: major | minor | Mean of halves | All |
|---:|---:|---:|---:|---:|
| 100 % (always minor) | 0.0 | 70.4 | 35.2 | 49.0 |
| 90 % | 17.1 | 70.1 | 43.6 | 54.0 |
| 80 % | 31.3 | 68.2 | 49.8 | 57.0 |
| 70 % | 46.4 | 63.8 | 55.1 | 58.5 |
| 63 % (the rule as it stands) | 54.4 | 59.3 | 56.8 | 57.8 |
| 60 % | 58.0 | 57.6 | 57.8 | 57.7 |
| 50 % | 66.3 | 49.7 | 58.0 | 54.7 |
| 40 % | 69.2 | 39.0 | 54.1 | 48.2 |
| 0 % (always major) | 77.2 | 0.0 | 38.6 | 23.5 |

**No point on the curve passes the bar as written**, because the minor half cannot exceed row B's home-note rate
there, 70.4. The trained mode rule's curve has the same shape and the same ceiling (`kt_x.py` prints both).

### 2.3 The published multi-profile method (letter X's second ask)

Faraldo, Jordà and Herrera's method [2nd, through letter X; the number tables read from the authors' scripts, which
carry no licence, as numbers; no code copied or run]: a 200 Hz high-pass, a gate that zeroes the weak notes of the
song's own chroma, and a second minor profile ("minor2") with a strong major third, beside bgate's major and minor.

| Variant (nothing trained by us) | MTG exact | major | minor | GiantSteps+ exact | major | minor | GiantSteps Key exact |
|---|---:|---:|---:|---:|---:|---:|---:|
| bgate's two profiles on row 3f's chroma (the start) | 47.1 | 62.4 | 40.4 | 69.4 | 69.0 | 69.5 | 54.1 |
| + gate + minor2, no 200 Hz cut | 56.2 | 42.7 | 62.1 | 74.4 | 56.9 | 76.8 | 58.8 |
| + gate + minor2 + 200 Hz cut (as published) | 45.9 | 35.5 | 50.5 | 63.0 | 58.6 | 63.7 | 50.0 |
| as published, without minor2 | 38.5 | 49.5 | 33.7 | 56.4 | 58.6 | 56.1 | 43.9 |
| as published, without the gate | 46.2 | 35.0 | 51.1 | 62.8 | 53.4 | 64.1 | 49.5 |
| gate + minor2 on row A's chroma | 55.2 | 36.8 | 63.2 | 68.4 | 51.7 | 70.7 | 55.6 |
| gate + minor2 on row B's chroma | 59.3 | 41.7 | 67.0 | 77.1 | 56.9 | 80.0 | 62.1 |

- **The second minor template is the step that matters** (+9 exact on MTG, +5 on GiantSteps+ and GiantSteps Key over
  the two-profile start), and it works by answering minor more: the minor half rises 22 points on MTG and the major
  half falls 20. The gate does almost nothing.
- **The 200 Hz cut hurt on every set** (10 to 11 points). My stand-in drops every spectral peak under 200 Hz, which is
  harsher than the published filter, so this row is **not a faithful replication** and the published 63.7 on this
  collection is not reproduced (45.9). Letter R had found the same direction on the lab's crate. [unverified against
  the authors' own pipeline.]
- On GiantSteps Key, where the paper reports 64.1 exact, the best of these is 62.1.

### 2.4 An open mode (letter X's fourth ask)

The home note is always row B's; the mode is named only on some clips. "Named mode right" is among clips whose home
note is right.

| Rule for naming the mode | MTG: mode named | named mode right | GiantSteps+: mode named | named mode right |
|---|---:|---:|---:|---:|
| Always (row A's mode) | 100 % | 79.8 | 100 % | 95.7 |
| Rows A and B agree on the mode | 85.8 % | 82.9 | 92.9 % | 97.5 |
| Rows 3f, A and B agree | 76.6 % | 82.8 | 87.8 % | 97.6 |
| The one-note ("amodal") template does not win | 92.1 % | 81.4 | 93.2 % | 96.4 |
| Row A's mode margin in the top 80 percent | 80 % | 85.9 | 80 % | 98.7 |
| in the top 60 percent | 60 % | 90.4 | 60 % | 98.7 |
| in the top 50 percent | 50 % | 92.6 | 50 % | 99.0 |

- **The margin of the mode decision is a usable signal**: on MTG, naming the mode on the surer half of the clips
  takes "mode right" from 80 to 93 percent. Agreement between rows A and B is weaker (83 at 86 percent named).
- **The published "amodal" mark is not a mode signal.** It marks 7 to 10 percent of clips; 73 to 90 percent of them
  are labelled minor, and what it finds is clips where the home note is doubtful (home note right on 36 to 56 percent
  of marked clips, against 72 to 80 overall). It belongs with "not sure", not with "mode open".
- **An open mode does not raise the share of exact keys.** It turns some wrong keys into honest half-answers. The
  exact rate over all clips falls as modes are left open (57.8 to 51.6 with the agreement rule on MTG); the gain is
  in what is shown, which section 4 measures.

## 3. Trained readers, for evaluation only

Two trained readers, both fitted on GiantSteps-MTG-key and both **for evaluation only**. Scripts `kt_prof.py`,
`kt_cnn.py`; all rows in `x_results.tsv`; per-clip keys in `x_clips_*.tsv`.

### 3.1 Learned profiles: the smallest trained reader

The profile match of letter R with the profile numbers learned from labelled clips instead of taken from a paper:
for each chroma, one major and one minor profile of 12 numbers, the same numbers serving all twelve home notes
(plain multinomial logistic regression; one setting, fixed before the run). On row B's chroma alone that is 25
numbers; on rows A and B, 49; on seven chromas (A, B, three registers, bass line, top line), 169. On MTG each clip
is scored by profiles fitted on the other four folds; on the other sets by profiles fitted on the 1,237 MTG clips
that share no artist with them. "Modes equal" weighs major and minor clips the same in the fit, so the reader cannot
learn "when in doubt, minor" from a set that is mostly minor.

| Set | Reader | Exact: all | major | minor | Mean of halves | Within one step | Home note | Mode given home: major | minor |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MTG, 1,270 | Apple | 65.2 | 41.5 | 75.6 | 58.5 | 78.3 | 76.4 | 58.6 | 95.8 |
| | B's home note + A's mode (nothing trained) | 57.8 | 54.4 | 59.3 | 56.8 | 71.7 | 72.4 | 70.5 | 84.2 |
| | learned, row B, 25 numbers | 60.7 | 33.2 | 72.7 | 52.9 | 75.0 | 72.8 | 46.9 | 98.6 |
| | learned, rows A and B, 49 numbers | 62.7 | 35.8 | 74.4 | 55.1 | 76.1 | 74.5 | 50.4 | 97.9 |
| | the same, modes equal | 59.8 | 56.5 | 61.2 | 58.8 | 73.8 | 73.6 | 73.4 | 84.8 |
| | learned, seven chromas, 169 numbers | 62.2 | 40.7 | 71.6 | 56.1 | 76.5 | 73.7 | 56.7 | 96.1 |
| | the same, modes equal | 59.1 | 58.0 | 59.6 | 58.8 | 73.5 | 72.7 | 74.4 | 84.7 |
| | learned, rows A and B, fitted on GiantSteps Key only | 57.8 | 12.7 | 77.5 | 45.1 | 73.5 | 71.3 | 22.3 | 99.9 |
| | the same, modes equal | 58.4 | 53.4 | 60.6 | 57.0 | 71.4 | 72.9 | 71.5 | 84.0 |
| GiantSteps+, 468 | B's home note + A's mode | 76.9 | 65.5 | 78.5 | 72.0 | 86.5 | 80.3 | 86.4 | 97.0 |
| | learned, rows A and B | 81.4 | 58.6 | 84.6 | 71.6 | 90.4 | 83.3 | 79.1 | 100.0 |
| | the same, modes equal | 76.7 | 69.0 | 77.8 | 73.4 | 88.0 | 79.5 | 90.9 | 97.3 |
| | learned, seven chromas | 83.3 | 65.5 | 85.9 | 75.7 | 91.0 | 84.8 | 84.4 | 100.0 |
| | the same, modes equal | 79.9 | 75.9 | 80.5 | 78.2 | 89.7 | 82.5 | 89.8 | 97.9 |
| GiantSteps Key, 604 | B's home note + A's mode | 60.9 | 40.9 | 64.6 | 52.7 | 76.8 | 67.1 | 67.9 | 94.6 |
| | learned, rows A and B | 66.2 | 37.6 | 71.4 | 54.5 | 81.0 | 70.7 | 61.4 | 98.6 |
| | the same, modes equal | 62.1 | 45.2 | 65.2 | 55.2 | 78.6 | 67.5 | 72.4 | 95.1 |
| | learned, seven chromas | 68.4 | 41.9 | 73.2 | 57.6 | 82.1 | 72.2 | 68.4 | 98.7 |
| | the same, modes equal | 64.7 | 50.5 | 67.3 | 58.9 | 80.6 | 70.4 | 74.6 | 95.0 |

- **Forty-nine learned numbers lift exact from 57.8 to 62.7 on MTG**, on artists they never saw, and to 66.2 on the
  604-clip set, where Mixed In Key 7 scored 67.2 and the published network 67.9 [2nd, letter T].
- **Most of that lift is a learned lean toward minor.** Fitted with the modes weighed equally, the same profiles
  score 59.8, and the mean of halves is 58.8 against the untrained reader's 56.8: two points of skill, three of lean.
  The home note moves by one to two points (72.4 to 73.6 or 74.5).
- **The lean follows whatever the training set is.** Fitted on the 604-clip set, which is 85 percent minor, the
  profiles read 12.7 percent of MTG's major clips right. Weighed equally, they score the same on MTG whether fitted
  on MTG (59.8) or on the other set (58.4). For a DJ whose crate is not mostly minor, the equal-weight fit is the
  honest one.
- **Against the bar as written**: the 169-number profiles pass on MTG (40.7 major, 71.6 minor; one point over on the
  minor half, inside the noise: the 95 percent interval on 71.6 is about plus or minus 3). The 49-number profiles
  miss by 0.7 on the major half. Every equal-weight fit fails the minor half by 14 to 16 points and passes on the
  mean of halves.

### 3.2 A small convolutional model

**The model**, after Korzeniowski and Widmer's key networks [2nd], scaled to a laptop: a log-frequency spectrogram
(mono, 44.1 kHz, frames of 16,384 samples, 5 frames a second, 24 bins to the octave, 126 bins from 55 Hz to 2,093
Hz, log magnitude); four blocks of two convolutions with batch normalisation, 12 to 96 feature maps, pooling after
the first three; one layer that reads the whole frequency axis at each time step; 24 outputs averaged over time.
236,006 numbers. Trained on random 30-second snippets, each shifted by a random minus 4 to plus 7 semitones (the
spectrogram window slides two bins a semitone and the label's home note moves with it), 120 passes, one seed. The
stopping pass was chosen on a slice of artists inside the training folds (about 150 clips); nothing else was chosen
by measurement. "12 shifts averaged" reads each clip at all twelve shifts and averages the answers.

**Five artist-grouped folds on MTG**: each clip scored by a model that never saw it or its artist.

| Fold | Training clips | Validation clips | Test clips | Stopped at pass | Test exact | 12 shifts averaged |
|---|---:|---:|---:|---:|---:|---:|
| 0 | 875 | 145 | 255 | 104 | 65.9 | 67.8 |
| 1 | 867 | 153 | 255 | 80 | 60.8 | 63.1 |
| 2 | 858 | 162 | 255 | 84 | 62.7 | 64.3 |
| 3 | 866 | 154 | 255 | 80 | 66.7 | 67.5 |
| 4 | 870 | 150 | 255 | 68 | 62.4 | 65.5 |

**Against Apple and the bar** (MTG, the 1,270 clips Apple read):

| Reader | Exact: all | major | minor | Mean of halves | Within one step | Home note: all | major | minor | Mode given home: major | minor | Parallel errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 58.5 | 78.3 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 | 11.2 |
| **The bar as written** | | **36.5** | **70.6** | | | | | | | | |
| Trained model | 63.9 | 42.0 | 73.5 | 57.7 | 79.2 | 74.6 | 72.3 | 75.7 | 58.1 | 97.2 | 10.7 |
| **Trained model, 12 shifts averaged** | **65.9** | **44.0** | **75.5** | 59.7 | 79.5 | 77.0 | 75.4 | 77.7 | 58.4 | 97.1 | 11.1 |
| Trained on GiantSteps Key only, 12 shifts | 57.0 | 3.9 | 80.2 | 42.0 | 73.6 | 70.6 | 48.7 | 80.2 | 8.0 | 100.0 | 13.6 |

- **The model trained on MTG passes the bar as written on clips and artists it never saw**: 44.0 on the major half
  (bar 36.5) and 75.5 on the minor half (bar 70.6), with 7.5 and 4.9 points to spare; without shift averaging, 42.0
  and 73.5, which also passes. Song for song it is level with Apple: it is right where Apple is wrong on 104 clips
  and wrong where Apple is right on 95 (sign test p 0.57).
- **It is, measure for measure, Apple's twin.** Exact 65.9 against 65.2; home note 77.0 against 76.4; within one
  step 79.5 against 78.3; and the same lean: mode right on 58 percent of major clips and 97 percent of minor ones
  (Apple 59 and 96). It did not learn to hear the mode better than the 80 percent ceiling of section 2; it learned a
  better home note (77.0 against row B's 72.4) and the set's lean.
- **The gain is not in one bucket.** Of MTG's 15 styles the model is ahead of the untrained reader (B's home note,
  A's mode) in all 15, by 1 to 16 points (smallest: progressive house 73 against 72, hard dance 62 against 60;
  largest: breaks 80 against 64, dubstep 61 against 45, deep house 64 against 49). Against Apple it is ahead in ten
  styles and behind in five; it is furthest behind on hard dance (62 against 75) and on electronica and downtempo
  (62 against 70), the least minor style (47 percent). By the data set's own confidence: 69.5 on the confident clips (Apple 68.8).
- **A model trained on the other set does not travel.** Trained on the 604-clip set alone (544 clips after removing
  shared artists, 85 percent minor) and scored on MTG it gets 57.0 exact and 3.9 percent of the major clips: it
  answers minor almost always. The training set's mix of modes is copied into the model.

**Across sets** (trained once on the 1,237 MTG clips sharing no artist with the GiantSteps clips; 1,049 fitted, 188
for the stopping choice):

| Set | Reader | Exact: all | major | minor | Mean of halves | Within one step | Home note |
|---|---|---:|---:|---:|---:|---:|---:|
| GiantSteps+, 468 | row B | 75.9 | 69.0 | 76.8 | 72.9 | 85.9 | 80.3 |
| | B's home note + A's mode | 76.9 | 65.5 | 78.5 | 72.0 | 86.5 | 80.3 |
| | learned profiles, 49 numbers | 81.4 | 58.6 | 84.6 | 71.6 | 90.4 | 83.3 |
| | trained model | 81.6 | 51.7 | 85.9 | 68.8 | 90.2 | 84.6 |
| | trained model, 12 shifts averaged | 82.9 | 53.4 | 87.1 | 70.3 | 91.2 | 85.7 |
| GiantSteps Key, 604 | row B | 59.9 | 43.0 | 63.0 | 53.0 | 76.2 | 67.1 |
| | B's home note + A's mode | 60.9 | 40.9 | 64.6 | 52.7 | 76.8 | 67.1 |
| | learned profiles, 49 numbers | 66.2 | 37.6 | 71.4 | 54.5 | 81.0 | 70.7 |
| | trained model | 67.7 | 35.5 | 73.6 | 54.5 | 80.5 | 72.5 |
| | trained model, 12 shifts averaged | 68.7 | 35.5 | 74.8 | 55.1 | 81.8 | 73.0 |
| | published, same set [2nd]: rekordbox 3 / Mixed In Key 7 / madmom's network / KeyFinder | 71.9 / 67.2 / 67.9 / 45.4 | | | | | |

On the published scale the small model lands where the published network of twice its size does (68.7 against
67.9) and beside Mixed In Key 7; rekordbox 3's 71.9 is not reached. On both outside sets its lead over the
49-number profiles is one to two points, and on the mean of halves it is no better than the untrained reader (70.3
against 72.0 to 72.9 on GiantSteps+): on mostly-minor sets its exact score is carried by the minor clips.

**What it costs.**

| Item | Measured |
|---|---|
| Size | 236,006 numbers; 0.95 MB as an ONNX file |
| Reading a five-minute song, CPU | the model 0.05 s on one thread (ONNX Runtime), 0.02 s on four; the spectrogram 0.35 s in numpy on one thread; twelve shifts multiply the model's part by twelve (0.6 s on one thread, 0.2 s on four) |
| Training | 16 to 25 minutes a fold on three CPU threads while other jobs ran; the five folds and the two cross-set models about 2 hours 45 minutes of training in all; no graphics card |
| New dependency | none (ONNX Runtime is already in the engine, D14) |

**Left out for want of a graphics card and time:** more than one seed (the fold-to-fold spread, 61 to 67, says a
single run is good to about plus or minus 3 points), any search over the model's settings, a larger model, an
ensemble, training on MTG and GiantSteps Key together, and a learning curve.

## 4. Precision against coverage

The owner's direction during the trial made this the main measure: show a key when it is reliable, skip it when
it is not. Script `kt_pc.py`; every curve in `pc_curves.tsv`. Clips are put in order by a confidence and the surest
share is shown; "key right" is among the shown clips.

**Confidence signals.** None is fitted; each only orders the clips. *Margin*: the reader's best key score minus its
second best (for a trained reader, its top probability). *Agreement*: how many of the three untrained readers (3f, A,
B) name the shown key. *Sections*: the clip cut into three equal parts, each read alone; how many name the shown key.
*Combined*: agreement plus sections, ties broken by margin.

### 4.1 The curves

MTG, the 1,270 clips Apple read. "Apple, same songs" is Apple's exact rate on the very clips shown.

| Songs shown | Nothing trained: B's home note + A's mode, by combined | Apple, same songs | Learned profiles (49 numbers), by agreement then probability | Apple, same songs | Trained model, by its own probability | Apple, same songs |
|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 57.8 | 65.2 | 62.7 | 65.2 | 65.9 | 65.2 |
| 90 % | 60.3 | 67.0 | 65.8 | 67.9 | 70.5 | 68.8 |
| 80 % | 62.9 | 68.3 | 67.3 | 69.2 | 74.5 | 71.6 |
| 70 % | 62.8 | 68.6 | 69.7 | 71.0 | 76.7 | 74.7 |
| 60 % | 65.9 | 71.1 | 72.7 | 73.2 | 79.9 | 77.3 |
| 50 % | 67.7 | 71.2 | 73.1 | 74.2 | 82.4 | 81.3 |
| 40 % | 71.7 | 73.0 | 77.0 | 76.6 | 84.8 | 83.3 |
| 30 % | 75.3 | 77.4 | 82.4 | 81.1 | 87.7 | 85.8 |
| 20 % | 74.8 | 78.7 | 86.2 | 84.6 | 92.5 | 90.9 |

The same three readers, within one step and home note, on MTG:

| Songs shown | Nothing trained: within one step | home note | Learned profiles: within one step | home note | Trained model: within one step | home note |
|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 71.7 | 72.4 | 76.1 | 74.5 | 79.5 | 77.0 |
| 80 % | 75.9 | 77.3 | 80.6 | 76.5 | 84.8 | 85.3 |
| 60 % | 78.2 | 79.4 | 84.9 | 80.6 | 87.3 | 90.3 |
| 40 % | 81.1 | 82.9 | 87.4 | 83.9 | 90.9 | 91.9 |
| 20 % | 87.4 | 79.1 | 90.2 | 92.9 | 95.3 | 96.1 |

On the outside sets (the trained readers fitted on MTG only; exact, then within one step):

| Songs shown | GiantSteps+: nothing trained | learned profiles | trained model | GiantSteps Key: nothing trained | learned profiles | trained model |
|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 76.9 / 86.5 | 81.4 / 90.4 | 82.9 / 91.2 | 60.9 / 76.8 | 66.2 / 81.0 | 68.7 / 81.8 |
| 90 % | 81.5 / 90.3 | 86.7 / 94.5 | 88.6 / 93.8 | 64.0 / 79.0 | 69.3 / 83.8 | 72.4 / 84.7 |
| 80 % | 84.5 / 92.2 | 88.8 / 96.3 | 92.2 / 96.5 | 67.3 / 81.0 | 71.8 / 85.9 | 74.9 / 86.7 |
| 70 % | 87.8 / 95.4 | 90.9 / 97.0 | 94.5 / 97.9 | 69.5 / 83.5 | 73.0 / 86.8 | 77.8 / 87.7 |
| 60 % | 89.3 / 97.2 | 92.2 / 97.5 | 96.8 / 98.6 | 72.4 / 86.7 | 74.9 / 87.3 | 80.1 / 88.4 |
| 50 % | 93.2 / 99.1 | 95.3 / 98.3 | 97.9 / 99.1 | 74.8 / 87.4 | 78.5 / 88.7 | 83.4 / 89.1 |
| 40 % | 93.0 / 99.5 | 97.3 / 99.5 | 100 / 100 | 76.4 / 88.0 | 81.8 / 88.0 | 86.8 / 91.3 |

(On these two sets the trained model's column is ordered by the combined signal, agreement with the untrained
readers plus its own sections; ordered by its own probability it reads 87.6, 91.7, 95.4, 97.2, 97.9 at 90 to 50
percent on GiantSteps+ and 71.8, 74.9, 77.3, 80.9, 85.4 on GiantSteps Key.)

### 4.2 Against the tools DJs use

Published exact rates (letter X): on the MTG collection, Apple 65.2 (measured on the same clips, letter R), Mixed In
Key 7: 65.7 and KeyFinder 54.8 (Faraldo et al. 2017, on 1,160 confident clips of the same collection: near, not the
same clips); on the 604-clip set, rekordbox 3: 71.9, Mixed In Key 7: 67.2, KeyFinder 45.4 (Knees et al. 2015).
Traktor, Serato and Beatport's tags have scores only from listening tests on other tracks (letter X, section 3), so
no like-for-like figure exists for them. "As right" = the largest share of songs shown, on the ten-point grid above,
at which the shown keys' exact rate reaches the tool's; "clearly better" = at which the whole 95 percent interval is
above it.

| Tool, its exact rate | Nothing trained: as right at | clearly better at | Learned profiles: as right at | clearly better at | Trained model: as right at | clearly better at |
|---|---:|---:|---:|---:|---:|---:|
| MTG: Apple overall, 65.2 | 60 % | 40 % | 90 % | 70 % | 100 % | 90 % |
| MTG: Mixed In Key 7, 65.7 | 60 % | 40 % | 90 % | 70 % | 100 % | 90 % |
| MTG: KeyFinder, 54.8 | 100 % | 100 % | 100 % | 100 % | 100 % | 100 % |
| 604: rekordbox 3, 71.9 | 60 % | never | 70 % | 50 % | 90 % | 70 % |
| 604: Mixed In Key 7, 67.2 | 80 % | 60 % | 90 % | 80 % | 100 % | 90 % |
| 604: KeyFinder, 45.4 | 100 % | 100 % | 100 % | 100 % | 100 % | 100 % |

**The fairer comparison is song for song**, and only Apple allows it. A tool's overall rate is for all songs; the
songs a reader is sure of are easier songs for everyone, Apple included (the "Apple, same songs" columns of 4.1).

- **Nothing trained:** never ahead of Apple on the same songs. At every share shown Apple is 1 to 7 points ahead,
  significantly so down to 60 percent shown (p under 0.01), level below that. On the held-out folds alone the two
  are level from 80 percent shown down (66.3 against 67.6; ahead 48, behind 53).
- **Learned profiles:** level with Apple on the same songs at every share shown (within 2.5 points; p 0.06 with all
  songs shown, 0.1 to 0.9 below).
- **Trained model:** level with Apple with all songs shown (65.9 against 65.2, p 0.57) and **ahead on the same songs
  once it may decline**: 74.5 against 71.6 at 80 percent shown (ahead on 78 clips, behind on 48, p 0.01), 79.9
  against 77.3 at 60 percent (p 0.01). Apple's framework, as Deckie reads it, offers no confidence to decline with.

### 4.3 Can the confidence be trusted?

**Each level of a signal, MTG** (key right, percent, with the number of clips):

| Signal | Level 0 | 1 | 2 | 3 |
|---|---:|---:|---:|---:|
| Row B: how many of 3f and A agree with it | 33.3 (183) | 50.4 (373) | 64.0 (714) | |
| Row B: sections that name the same key | 37.1 (35) | 39.6 (164) | 51.7 (449) | 63.7 (622) |
| Row B: margin, by quarter of the clips | 45.9 | 54.3 | 57.7 | 64.5 |
| Learned profiles: how many of 3f, A, B agree | 44.5 (245) | 54.3 (197) | 64.2 (268) | 72.9 (560) |
| Trained model: how many of 3f, A, B agree | 46.6 (311) | 59.3 (199) | 70.3 (249) | 78.1 (511) |
| Trained model: sections that name the same key | 6.7 (15) | 43.3 (120) | 50.9 (350) | 77.2 (785) |

B's home note with A's mode, combined signal (0 to 6): 22.7 (22 clips at level 1), 27.9 (68), 43.3 (157), 54.8
(248), 53.6 (289), 72.2 (486 at level 6). On GiantSteps+ the top level holds 233 of 468 clips and is right on 93.1
percent of them.

**A stated probability against the truth** (out-of-fold on MTG; a calibrated confidence has the two numbers equal):

| Stated probability | Trained model: clips | says | is right | Learned profiles: clips | says | is right |
|---|---:|---:|---:|---:|---:|---:|
| 0.1 to 0.3 | 122 | 22.5 | 25.4 | 176 | 22.7 | 28.4 |
| 0.3 to 0.4 | 96 | 34.7 | 35.4 | 173 | 35.3 | 45.7 |
| 0.4 to 0.5 | 153 | 45.0 | 55.6 | 182 | 45.3 | 61.0 |
| 0.5 to 0.6 | 148 | 55.0 | 58.1 | 225 | 55.0 | 67.1 |
| 0.6 to 0.7 | 156 | 65.0 | 67.3 | 190 | 64.9 | 71.6 |
| 0.7 to 0.8 | 196 | 75.2 | 75.0 | 160 | 74.7 | 80.0 |
| 0.8 to 0.9 | 192 | 85.3 | 80.2 | 123 | 84.5 | 84.6 |
| 0.9 to 1.0 | 207 | 94.4 | 94.2 | 41 | 92.7 | 90.2 |

- **Every signal sorts right from wrong, on all three sets, and the selection and held-out folds agree.** Agreement
  between independent readers and stability across sections are both real signals; the margin alone is the weakest
  and, for the untrained reader, says nothing about the home note (home note right on 70 to 75 percent of clips in
  every quarter of the margin).
- **The trained model's own probability is calibrated on the set it was trained for**: a mean gap of 3.1 points
  between what it says and how often it is right, on artists it never saw. When it says 90 percent or more (207
  clips, one in six) it is right 94 percent of the time. On GiantSteps+ it is *under*-confident (gap 11.1 points: it
  says 76 and is right 95), which is the safe direction but means a threshold set on one kind of music will not
  give the same share shown on another.
- **The learned profiles' probability is under-confident** in the middle (says 45, is right 61) and good at the
  top; gap 8.4 points.
- **For the trained model the best single ordering on MTG is its own probability**; adding agreement with the
  untrained readers and its sections does not improve the curve there (74.5 against 73.7 at 80 percent shown), and
  improves it on GiantSteps+ (92.2 against 91.7 at 80 percent, 96.8 against 97.2 at 60: level).

### 4.4 Three answers, with nothing trained and no threshold

A key when rows A and B agree on the home note and on the mode there; "home note, mode open" when they agree on the
home note only; "not sure" otherwise.

| Set | A key: share of songs | key right | within one step | Mode open: share | home note right | Not sure: share |
|---|---:|---:|---:|---:|---:|---:|
| MTG | 70.4 % | 64.8 | 76.6 | 11.7 % | 79.2 | 17.9 % |
| GiantSteps+ | 76.1 % | 85.4 | 92.1 | 4.7 % | 81.8 | 19.2 % |
| GiantSteps Key | 73.8 % | 69.1 | 82.7 | 5.5 % | 60.6 | 20.7 % |

On MTG, Apple is right on 69.9 percent of the clips this rule gives a key, 63.1 of the mode-open clips and 48.0 of
the not-sure clips: the rule finds the songs that are hard for everyone. On the not-sure clips row B's key would
have been right on 37.0 percent, so declining them removes more wrong keys than right ones.

A parameter-free rule for the trained model, "show a key when the model and row B name the same key", shows 61.9
percent of MTG at 74.8 right (Apple on the same clips 71.9), 79.3 percent of GiantSteps+ at 90.6, and 77.3 percent of
the 604 at 73.7.

## 5. What could ship

### 5.1 The best method that needs no learned weights, and its port

**The method.** Home note from row B, mode from row A on that home note, and a confidence that fits nothing: a key is
shown when rows A and B agree on the home note and on the mode there; the home note alone ("mode open") when they
agree on the home note only; "not sure" otherwise. For a finer dial, the count of section 4 (how many of rows 3f, A
and B name the key, plus how many thirds of the song do, 0 to 6).

**What the Swift core has already** (`core/Sources/DeckieCore/Key/`): `HPCPKey`, which is row 3f whole: the spectral
peaks, the whitening, the 4-harmonic HPCP, Faraldo's three profiles with their sources, the margin and the sure flag.

**What a port adds.**

| Piece | What it is | Size of the work [inf] |
|---|---|---|
| Row A | on each frame's HPCP, subtract 0.36 of the note a fifth below and 0.13 of the note a major third below, floor at zero, then sum (letter R, Part A) | hours; a dozen lines inside `HPCPKey`, parity against `key_overtones.discount` |
| Row B's front end | resample to 11,025 Hz; Hamming frames of 4,096, hop 1,024; a fixed 256 x 2,049 map to third-of-a-semitone bins; one tuning estimate per song; running mean and deviation over 37 bins; per frame, a non-negative least-squares fit of 84 note templates (20 harmonics, slope 0.7); fold to 12 (letter R, Part B) | 2 to 3 days: the map and templates are tables computed once; the non-negative least squares needs its own solver (Lawson and Hanson's active-set method, about 150 lines, no LAPACK on Windows and Linux), tested against scipy on fixtures |
| The mode on B's home note | compare row A's minor and major match on that note | an hour |
| Sections | the same sums over each third of the song | hours |
| Three answers | key, home note with mode open, not sure; a field in the record for "mode open" | a day with the crate change; the crate's key block has no such state today, so this is a format note for the owner (D13, D27) |
| Parity | per-clip agreement with this Python on the 1,275 clips, as the first port was checked on the crate | a day |

About **5 to 6 working days** in all. **Cost per song** [measured in Python on this machine, one thread, while other
jobs ran]: peaks and HPCP 0.2 s and the note transcription 0.35 to 0.9 s per two-minute clip, so about 1.5 to 3 s for
a five-minute song in Python; Swift should be well under that [unmeasured]. **Licence note:** row B was written from
Mauch and Dixon's paper; letter R records that the GPL plugin's README and source were read for three default values.
That reading is the one thing an attorney should look at before row B ships.

**What it would score** (section 4): a key on about 70 percent of dance songs, right 65 percent of the time on MTG,
69 on GiantSteps Key, 85 on GiantSteps+; the home note alone on a further 5 to 12 percent; "not sure" on about 20.

### 5.2 Methods with learned weights: what could legally back them

Two trained readers were measured (section 3): **learned profiles** (49 numbers on rows A and B's chroma) and the
**small convolutional model** (236,006 numbers). Both were trained here on GiantSteps-MTG-key, whose labels are CC
BY-SA 4.0 and whose audio is Beatport's and the labels', so **neither ships**: the standing rule keeps share-alike
and non-commercial data out of shipped weights, and D15 would stop on a data owner's objection.

| Data that could back shipped weights | Size, music | Labels' licence | Audio | Usable under D15 and the standing rule? |
|---|---|---|---|---|
| GiantSteps-MTG-key | 1,486 dance clips | CC BY-SA 4.0 | Beatport's and the labels'; bundled on Zenodo | no: share-alike labels, audio not licensed for it |
| GiantSteps+ | 600 dance clips | CC BY-SA 4.0 | the same | no, the same |
| GiantSteps Key | 604 dance clips | none stated | the same | no: unknown licence, and we are not the rights-holder |
| FMAK / FMAKv2 (Zenodo 12759100) | 5,489 songs, 17 genres | CC BY 4.0 on Zenodo, non-commercial per mirdata (letter T: a conflict to settle) | Free Music Archive, a Creative Commons licence per track, some non-commercial or share-alike | **possibly, in part**: only the tracks whose own licence is CC BY or CC0, once the label licence is settled. How many that leaves is [unmeasured]; not fetched here |
| McGill Billboard | 742 pop and rock songs, 1958 to 1991 | CC0 | none; the recordings must be owned | labels yes; training on bought recordings is a question for the attorney (D15 discloses the data and stops on an owner's objection). Home note per section; the mode is not always given |
| Isophonics | about 231 songs | not found | none | no: licence unknown |
| GTZAN key | 837 clips | MIT | of unclear origin | no: audio unclear |
| A set Deckie commissions | see below | Deckie's own | audio Deckie has training rights to | **yes** |
| Deckie's users' libraries | | | | no: D3 |

**A precedent worth the attorney's eye.** The engine already ships three profiles (edma, braw, bgate) that are
numbers published in papers and were made by measuring Beatport tracks, 600 of them from the very collection that
became GiantSteps-MTG-key (letter X). The learned profiles of this trial are the same kind of object, 49 numbers,
made from the same kind of data; the difference is who made them and that the labels' CC BY-SA licence would be used
by us, not by a paper's authors. Whether 49 fitted numbers "contain" a share-alike data set is the unsettled question
letter T already named. Under the standing rule the answer today is that they do not ship.

**What a commissioned set would need to contain.** The learning curve (`kt_curve.py`, `curve_results.tsv`; profiles
fitted on N clips drawn from the training folds, scored on clips and artists they never saw):

| Training clips | Learned profiles (49 numbers): MTG exact | MTG home note | GiantSteps+ exact | GiantSteps Key exact |
|---:|---:|---:|---:|---:|
| 25 | 54.1 | 68.5 | 70.1 | 60.8 |
| 50 | 57.6 | 70.5 | 76.6 | 60.0 |
| 100 | 59.9 | 72.2 | 77.5 | 64.8 |
| 200 | 61.0 | 73.5 | 79.8 | 64.9 |
| 400 | 62.3 | 74.3 | 81.3 | 66.3 |
| 800 | 62.9 | 74.6 | 81.0 | 66.9 |
| 1,020 (all) | 62.7 | 74.5 | 81.0 | 66.2 |

The 49-number reader has learned what it can by about **400 songs**; the 169-number variant is still rising at 1,020
(61.6 at 800, 62.2 at 1,020), and the convolutional model was not put through a curve here [unmeasured: each point
costs about an hour and a half of CPU]. So, for the small reader:

- **Size.** 400 to 600 songs to fit, plus at least 300 kept apart for scoring and never fitted on, split by artist.
  With 300 test songs a rate near 65 percent carries a 95 percent interval of about plus or minus 5 points, which is
  D16's margin, so fewer is too few to rule on the bar.
- **Music.** What DJs play, not only what Beatport sells: house with vocals, pop, hip-hop and R&B, disco and funk,
  Latin, rock and the dance styles, in the proportions of letter C's findings. Every result in this letter is on
  club dance music; on MTG's least minor style (electronica and downtempo, 47 percent minor) the
  49-number profiles are below row B (56 against 60) and Apple is 8 to 14 points ahead of every reader of ours, and on
  hip-hop and R&B no reader of ours passes 56; a set without such styles would repeat that.
- **Modes.** Enough major songs to measure them: at least a third. The 604-clip set has 93 major clips and
  GiantSteps+ 58; their major halves carry intervals of plus or minus 10 to 13 points, too wide to rule on.
- **Labels.** The home note and the mode from a musician, with a third answer allowed ("mode open": no third, or
  both thirds), a confidence, and key changes with their times; a second musician on at least a fifth of the songs,
  so that how often two people agree is known (a vendor puts it at 70 to 75 percent [2nd, letter X]; no data shown).
- **Audio.** Whole songs, not two-minute previews (the engine reads whole songs), with rights that cover fitting a
  model: owned outright, licensed for it, or CC BY or CC0. This is D16's "mixed-genre listening set" with one more
  requirement, the training right.
- **Fit.** Major and minor songs weighed equally (section 3 shows what the set's own mix teaches otherwise), and the
  result reported on the mean of halves beside the exact rate.

## What it means for a DJ

- **Today, with nothing trained**, Deckie could show a key on about seven dance songs in ten and be right about two
  times in three on hard material (as often as Apple or Mixed In Key 7 are over all songs), more than eight times in
  ten on the cleaner set; show just the home note on roughly one song in ten more; and say "key not sure" on the last two
  in ten, which are the songs every reader gets wrong most. A DJ would see fewer wrong keys than a tool that always
  answers, and no key at all on a fifth of the crate.
- **The mode is the part nobody hears well, Apple included.** Given the right home note, every reader in this trial
  names major or minor correctly about four times in five when major and minor songs count the same. Apple and the
  trained model look better on dance music because they say "minor" when unsure and dance music is mostly minor. On
  a crate with more major-key music (pop, disco, a lot of house with vocals) that habit costs: they call about four
  major songs in ten minor.
- **A trained reader of Deckie's own can equal Apple's**, on songs and artists it has never met: the same share of
  keys exactly right, the same home-note rate, the same mistakes. It is small (under a megabyte) and reads a song in
  well under a second. And unlike Apple's framework it says how sure it is, and can be believed: when it says nine
  in ten, it is right nine times in ten; shown on the eight songs in ten it is surest of, it is right three times
  in four and ahead of Apple on those same songs.
- **What it cannot do yet is ship.** It was taught on a collection Deckie may only use for testing. Teaching one
  that can ship needs a few hundred songs with keys written down by a musician, on recordings Deckie has the right to
  use that way, covering the music DJs really play, not only club tracks.
- **What a mode mistake costs in the booth** is letter X's point and it stands: a relative or fifth mistake still
  mixes; a parallel one (right home note, wrong mode) can spoil a blend when the song really plays its third. The
  trained readers make about one such mistake in nine songs, the untrained one in seven, Apple one in nine.

## What I could not verify

- **Apple on GiantSteps+ and GiantSteps Key.** Apple's framework needs the iPad simulator; this session has none. So
  the bar itself could be checked only on MTG, and no reader was compared with Apple song for song on the clean set.
- **Music that is not club dance music.** Every set here is Beatport previews. Billboard, Isophonics and FMAK were
  not fetched (no bundled audio, or 93 GB and up). Whether any trained reader of this trial holds on pop, hip-hop or
  rock is [unmeasured], and letter T's evidence says dance-trained models lose there.
- **Whole songs.** All clips are two minutes. The engine reads whole songs; published work says longer excerpts help
  a trained reader [2nd, letter T].
- **The published multi-profile method as its authors ran it.** Their 200 Hz filter was stood in for by dropping
  spectral peaks under 200 Hz, and their Essentia front end by ours; their published 63.7 on this collection is not
  reproduced here (56.2 without the cut, 45.9 with my version of it).
- **Why MTG is harder than GiantSteps+** for every reader (20 points for row B): label quality, style mix or the
  share of major songs. Not separated.
- **The tools' scores on these exact clips.** Mixed In Key 7 and KeyFinder on MTG are from a 2017 paper on 1,160
  confident clips of the same collection, not our 1,270; rekordbox 3 and Mixed In Key 7 on the 604 are from 2015.
  None was run here, and today's versions of these tools were not measured by anyone I could cite.
- **A graphics card.** There is none in this environment. The convolutional model was sized for the CPU: one seed,
  120 passes, about 15 to 25 minutes a fold, no search over its settings, no ensemble, no learning curve, and no
  larger model. A larger or longer-trained model might do better [unmeasured].
- **Swift.** Nothing was ported; costs in Swift are estimates.
- **The label licence of FMAKv2** and how many of its tracks are CC BY or CC0: not checked.
- **Clock times in the first check-in entry** were written from memory and corrected in the second.

## Options for the owner

1. **Ship nothing yet; keep D16 as it stands.** Windows and Linux keep "key not read on this computer yet". Cost
   nothing. This trial then stands as the evidence that the bar can be met by a reader of Deckie's own once training
   data is cleared.
2. **Ship the untrained reader with three answers** (section 5.1): a key on about 70 percent of songs, the home note
   alone on 5 to 12 percent, "not sure" on about 20. Five to six working days of Swift. No weights, no data question
   (one licence note for the attorney on row B). On hard material its shown keys are right 65 percent of the time:
   the overall rate of Apple and Mixed In Key 7, though below Apple on those same songs. **It does not pass D16's bar
   as written** (57.8 exact with every song shown; minor half 59.3 against 70.6), so it needs the owner's ruling
   that the bar may be read as "of the keys shown, as many right as Apple shows" (letter X, option 3c).
3. **Commission the labelled set and train Deckie's own reader on it** (section 5.2): 400 to 600 songs to fit and
   300 to score, mixed styles, a third or more in major keys, a musician's labels with "mode open" allowed, on audio
   Deckie may train on. Then the 49-number profiles (days) and the small model (a week with a graphics card or a
   patient CPU). Expected, from this trial on unseen artists: exact 60 to 66 with every song shown, 74 to 80 on the
   80 percent it is surest of. This is the only route measured here that **passes D16's bar as written**, and the
   only one that was ahead of Apple on the same songs.
4. **Rule on what the bar measures** (letter X's option 3, now with the numbers). On MTG: as written, only the
   trained model and the 169-number profiles pass. Read as the mean of the two halves (Apple 58.5), rows A and B,
   every equal-weight learned profile and the trained model pass. Read as within one step (Apple 78.3), the learned
   profiles and the trained model pass and the untrained readers miss by 6 to 9 points. Read as precision of the keys
   shown, the untrained reader passes at 60 percent shown against Apple's overall rate and does not pass against
   Apple on the same songs. A caution with the numbers behind it: **the bar as written rewards leaning minor**. A
   reader fitted to pass it reads 40 to 44 percent of major-key songs right; the same reader fitted without the
   lean reads 56 to 58 percent of them right and fails the bar.
5. **Ask the attorney one narrow question**: may 49 numbers fitted by Deckie on a CC BY-SA-labelled collection ship,
   given that the engine already ships published profiles measured on the same collection? If yes, option 3's first
   step needs no commissioned set. The standing rule says no today.
6. **Run Apple on GiantSteps+ and GiantSteps Key** (about 70 minutes in the simulator, letter T) so the bar can be
   checked on the clean set, and **fetch a mixed-genre set** for the any-DJ question. Both are what this session
   could not do.

**Recommendation.** Take 2 and 3 together, and rule on 4.

- **Option 2 now**, because it is the graceful failure the owner asked for and needs nothing that is not already
  cleared: no weights, a confidence that fits nothing, and it holds its shape on all three sets. Ship it only with
  the three answers; with every song shown it is not good enough.
- **Option 3 in parallel**, because it is the only thing measured that reaches Apple's class, and the owner said he
  would prefer to have a key. The set it needs is the one D16 already names, with the training right added. Start
  with the 49-number profiles: they level off at 400 songs, they are numbers the engine already knows how to use,
  and they were level with Apple song for song. Fit with major and minor weighed equally unless option 4 rules
  otherwise.
- **On option 4**, my recommendation is precision of the keys shown, measured against Apple on the same songs, with
  the mean of the two halves reported beside it. It is the measure that matches "show it when reliable, skip it when
  not", and it cannot be passed by leaning.
- I would not ship a trained reader on today's evidence even if the data were cleared: one seed, one kind of music,
  two-minute clips. Option 6 comes first.
