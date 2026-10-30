# Research T: ways to a better key reader of our own

Dated Oct 30, 2026. A survey with costed options, no decisions and no experiments beyond one small computation. Builds
on letter R (its last four sections: the outside test, Apple on the same clips, the beat-grid weighting, the
overtones), D5's notes (library-blind), D11, D14 and D15 (weights, training data, ONNX Runtime), D16 (the bar) and D17
(key shown with its limits). Script `mixer/key_abstain.py` (reads the committed sheets only; output printed, no new
sheet committed). Tags: [2nd] = read in a paper or page, not tested here; [inf] = my inference, with the reasoning;
[unmeasured] = not measured. Not legal advice.

## In plain words

A song's **key** is the note it feels at home on plus the flavour of its scale, for example "A minor". The **home
note** (the tonic) is the note the music keeps returning to and comes to rest on; the **mode** is the flavour, major
(bright) or minor (dark). DJs use the key to choose songs that sound right one after another. A computer reads key by
measuring how loud each of the twelve notes is across the song, a twelve-number summary called the **chroma**, and
matching it against a template for each of the 24 keys. A **trained model** works differently: it is shown thousands
of songs whose keys people have written down and adjusts itself until its answers match; it then reads new songs. A
**test set** is a collection of songs with known keys kept apart for scoring, never used for adjusting anything, so
the score says how the reader does on music it has never met.

The principle throughout: nothing is tuned to any one DJ's crate. Values come from published work or first
principles; anything chosen by measurement is chosen on one half of an outside set and reported on the other half;
and no model is scored on the songs it learned from. Deckie is for any DJ, so a reader that only works on one style
of music is a flag, not a win.

Where things stand: on 1,270 unfamiliar dance-music clips, Apple's framework gets the key exactly right about two
times in three and the home note three times in four. Ours gets the key right about one time in two, and somewhat
more after taking overtones out of the chroma. Ours is better than Apple's on major keys and much worse on minor ones.
This letter lists the ways to close that gap, what each would cost, and what it would take to find out.

## Where we stand

The outside set is GiantSteps-MTG-key (the Beatport EDM Key Dataset, Faraldo 2017; 1,275 plain-key clips; 1,270 that
Apple read). Halves are letter R's split by clip id (odd, even), all confidence levels. Rows A and B were chosen on the
odd half's confidence-2 clips, so only the even half is held out for them. Home note = exact + parallel.

| Reader | Odd exact | Odd home | Even exact | Even home | All exact | All home | Major exact / home | Minor exact / home |
|---|---|---|---|---|---|---|---|---|
| 3f (ours, letter R's recommended) | 48.6 | 69.2 | 46.1 | 68.4 | 47.4 | 68.8 | 60.3 / 69.8 | 41.7 / 68.3 |
| A, harmonic discount | 57.1 | 70.1 | 53.6 | 67.6 | 55.4 | 68.9 | 53.6 / 74.2 | 56.1 / 66.5 |
| B, NNLS note transcription | 57.7 | 74.7 | 53.0 | 69.7 | 55.4 | 72.2 | 62.9 / 76.8 | 52.1 / 70.2 |
| Apple Music Understanding | 67.2 | 78.9 | 63.1 | 73.7 | 65.2 | 76.4 | 41.5 / 70.7 | 75.6 / 78.8 |

D16's bar (exact within five points of Apple on each mode half): the major half is met by every row of ours; the minor
half needs about 70.6 and our best is 56.1. The **caution** of letter R holds for every number here: this set is the
published *training* set for the GiantSteps-key test set, and Faraldo's braw and bgate profiles (inside 3f, A and B)
were derived from Beatport EDM of this kind. Published "GiantSteps" figures below are on the 604-clip test set (Knees
et al. 2015), a different set; they are a rough scale, never a like-for-like comparison with the table above.

## 1. A trained model

**What it is.** A small convolutional network (a stack of learned pattern detectors that slide over a spectrogram, a
picture of the sound's frequencies over time) reads the whole clip and outputs 24 probabilities, one per key. It is
trained on clips with written-down keys, with each clip also pitch-shifted up and down so that every key is seen.

**Evidence** [2nd, all read; percent on the 604-clip GiantSteps Key test set unless named; "weighted" = MIREX score,
exact + 0.5 fifth + 0.3 relative + 0.2 parallel]:

| Work | Model, size | Trained on | Test set | Exact | Weighted | Notes |
|---|---|---|---|---|---|---|
| Korzeniowski and Widmer 2017, EUSIPCO, Table (CK1) | 5 conv layers, 8 maps, 48-unit dense (size not stated) | GiantSteps-MTG-key, 1,077 single-key high-confidence | GiantSteps 604 | 67.9 | 74.3 | fifth 6.8, relative 7.1, parallel 4.3, other 13.9 |
| same, CK1 | | MTG-key | Billboard test (25 percent of 625, about 156 [inf]) | 62.5 | 72.8 | EDMA profile scores 70.8 here: an EDM-trained net loses on pop |
| same, CK2 | | Billboard train | GiantSteps 604 | 47.0 | 57.3 | and 77.1 / 83.9 on Billboard |
| same, EDMA / EDMM (Faraldo's profiles, re-run) | none | none | GiantSteps 604 | 57.8 / 63.7 | 65.6 / 70.1 | |
| Korzeniowski and Widmer 2018, ISMIR, AllConv (madmom's key network) | all-convolutional, 24 maps; 462k parameters at 20 maps (Baumann 2021) | MTG-key 1,077 + Billboard 625 + 1,504 internal classical | GiantSteps 604 / Billboard / KeyFinder / Isophonics | 67.9 / 79.9 / 70.0 / 76.3 | 74.6 / 85.1 / 76.1 / 82.5 | "genre-agnostic"; correct excerpts median 131 s, wrong 51 s (Rock set) |
| Kong et al. 2025, ICASSP, re-run of madmom | as above | as above | GiantSteps 604 | | 71.0 | below the 74.6 published, "implementation differences" |
| Schreiber and Müller 2019, SMC, DeepSquare | VGG-style CNN | 80% LMD-key (MIDI) + 80% MTG-key | GiantSteps 604 | 58.5 ± 3.9 | | accuracy only |
| Baumann 2021, ISMIR, InceptionKeyNet | 1.7M parameters, ensemble | MTG-key + Billboard (+ a mined set) | GiantSteps 604 | | 75.50 / 75.68 | AllConv re-trained there: 74.27 / 74.44 |
| Kong et al. 2025, ICASSP, S-KEY (self-supervised) | not stated | 60k / 1M Deezer catalogue songs, no key labels | GiantSteps 604 / FMAKv2 5,489 / GTZAN 837 | | 71.7–72.1 / 72.1–73.2 / 70.9–74.4 | madmom 71.0 / 73.1 / 67.9 on the same |
| Yonay, Hammond and Yang 2026, arXiv (not peer reviewed), KeyMyna | 22M-parameter pretrained encoder + MLP head | encoder: unclear; head: MTG-key | GiantSteps 604 / Billboard | 72.0 / 79.9 | 75.9 / 84.4 | |

Essentia ships no trained key model: its model page lists only a tonal/atonal classifier under tonality (weights CC
BY-NC-SA 4.0); its KeyExtractor is the profile method 3f already re-implements [2nd].

**Expected gain** [inf]. CK1 (trained on this set's population, scored on the 604) has home note about 72.2 (67.9 +
4.3) and few parallel errors, so its errors are fifths and others, not mode. Scored on held-out folds of our set by
artist, a model of that class would land near exact 62 to 70 and home note 72 to 78, against our 47.6 / 69.1 (3f) and
55.6 / 72.4 (B), and Apple's 65.2 / 76.4. The training data is 70 percent minor, so the minor half should be its
strong half, the opposite of ours; the major half could fall, but Apple's major half (41.5) leaves a wide margin
under D16. The pop result (CK1 62.5 on Billboard against a profile's 70.8) says an EDM-only model would be worse than
3f on other music, which matters for any DJ.

**Cost.**

| Item | Estimate |
|---|---|
| Work | 5 to 8 days [inf]: features and pitch-shift pipeline 1, model and training loop 1 to 2, grouped folds, external test and Apple re-run 2, ONNX export and a Swift check 1 to 2 |
| Training on this Mac (M1 Max class, MPS) | features about 1 hour for 1,486 clips; one AllConv-size model, 12 shifts, about 100 passes: 1 to 3 hours; 5 folds 5 to 15 hours, overnight at nice 19, one job at a time [inf: 462k parameters on 600 x 105 inputs is small for this GPU] |
| Engine | 0.5 to 2 MB of weights (462k float32 is 1.8 MB; 1.7M is 6.8 MB); under 0.5 s a track on CPU [inf: about 2 to 3 GFLOP for a 5-minute track]; no new dependency (ONNX Runtime, D14) |

**Licence and data.** No published weights can ship: madmom's model files are CC BY-NC-SA 4.0 (commercial use by
asking Widmer) [2nd]; S-KEY's checkpoint is "non-commercial research" only, the code MIT [2nd]; Essentia's models are
CC BY-NC-SA 4.0 [2nd]; InceptionKeyNet publishes code (MIT), no weights [2nd]. So shipping means training our own, and
the question is the training data. MTG-key's labels are CC BY-SA 4.0 and its audio belongs to Beatport and the labels;
we hold it for internal evaluation only. Training shipped weights on it is a different use from evaluating: under D15
the data set is disclosed and a data owner's objection would stop it, and the note on D14 keeps CC BY-SA off for
weights and data. Whether weights trained on share-alike labels inherit the share-alike is unsettled [inf; for the
attorney]. Training on a DJ's own library is ruled out by D3. A self-supervised route like S-KEY needs tens of
thousands of unlabelled songs we have no licence to; FMA's CC audio (mixed CC licences per track, some NC) is the only
open pool I know of.

**Risks.** Test-on-train if any number is scored on MTG-key clips the model learned from. Artist and label overlap
between folds (one producer's sound in both). An EDM-only model weakens pop and house-with-vocals. 2-minute clips
against full tracks in the engine (the 131 s against 51 s finding above suggests full tracks help [2nd]).

**The experiment that would settle it** (evaluation only; nothing ships). Train AllConv-size models on GiantSteps-MTG-
key in 5 folds grouped by artist (from the set's original metadata [unmeasured: that artist names are there for every
clip]); each clip is scored only by the model that never saw it, giving a per-clip key on all 1,270 beside Apple's,
by mode half and by odd and even ids. Every setting from the papers above (layers, maps, shifts −4 to +7, stopping on
a validation slice inside the training folds). Then the fully outside checks: GiantSteps+ (600, the revised 604,
no overlap with MTG-key per Baumann 2021 [2nd]) with Apple re-run on it in the simulator (about 70 minutes at 7 s a
clip), and a non-EDM set (FMAKv2 or Billboard) for the any-DJ question.

## 2. Chord-level key

**What it is.** First name the chords moment by moment (C major, then A minor, and so on), then infer the key that
best explains the chord sequence, often with a hidden Markov model (a model of hidden states, here the key, that
produce what is observed, here the chords) whose probabilities come from music theory or listening tests. The
engine's beat grid would let chords be read per beat or per bar.

**Evidence** [2nd]. Noland and Sandler 2006 (ISMIR): a 24-state key HMM observing chord transitions, initialised from
Krumhansl's listening tests, gets the overall key of 91 percent of 110 Beatles songs, from hand-written chord symbols,
not audio; so it is an upper bound with perfect chords. Papadopoulos and Peeters 2012 (IEEE TASLP 20(4)) and Pauwels
and Martens 2014 (JNMR 43(3)) estimate local key jointly with chords and the metrical grid on Beatles and Billboard; I
could not open their results, so no figure. I found no published key-from-chords figure on dance music. Faraldo's 2018
thesis (UPF) argues EDM often uses modal and reduced pitch sets that a major/minor triad vocabulary fits poorly.

**Expected gain** [inf]. Home note 0 to +4 points, exact 0 to +3, over B. Chord labels are the transcription step
(row B already does the note half of it); what chords add is order (a cadence onto the tonic), and dance tracks often
loop one or two chords for minutes, where order says little. Letter R's beat-grid test (worse the more weight the
beats got) warns that the grid is not a free lift.

**Cost.** 4 to 6 days: a chord stage on row B's NNLS chroma (chord templates from Mauch and Dixon 2010, Chordino's
GPL code read, not copied), then a key HMM after Noland and Sandler. Engine: row
B's front end (2.3 s a clip in Python; less in Swift [unmeasured]) plus a Viterbi pass over about 25 chords, a few
milliseconds; no new dependency. **Licence:** our own code from papers; no data needed beyond the outside set.
**Risks:** more choices (chord vocabulary, transition weights), each a chance to fit the set. **Experiment:** every
value from the papers, fixed before the run; scored on the even ids against 3f and B with the paired sign test of
letter R; the home-note intervals (+7, +5) reported, since this is aimed at them.

## 3. Abstaining and combining what we have

**What it is.** D17 asks the product to say "key unsure" when it is. We have three readers (3f, A, B) with margins
and sure flags; where they agree the key should be safer. `mixer/key_abstain.py` scores seven rules, written into its
docstring before the sheets were scored. The key reported on a kept clip is the rule's key; on the rest it is the key
that would be shown with an "unsure" flag (B's, or 3f's for the 3f rule). Apple's columns are context only (does the
rule keep clips that are easy for everyone?); Apple's key is not an input.

| Rule | Half | Kept % | Kept exact | Kept home | Rest exact | Rest home | Apple kept exact / home | Apple rest exact / home |
|---|---|---|---|---|---|---|---|---|
| all (B, no abstaining) | odd | 100 | 57.7 | 74.7 | | | 67.2 / 78.9 | |
| | even | 100 | 53.0 | 69.7 | | | 63.1 / 73.7 | |
| 3f's sure flag | odd | 42.3 | 56.2 | 70.3 | 43.1 | 68.4 | 68.0 / 79.6 | 66.7 / 78.4 |
| | even | 44.5 | 53.8 | 67.9 | 39.9 | 68.8 | 59.8 / 70.7 | 65.7 / 76.2 |
| B's sure flag | odd | 41.4 | 65.2 | 71.5 | 52.4 | 77.0 | 68.4 / 76.6 | 66.4 / 80.6 |
| | even | 39.2 | 63.1 | 71.3 | 46.4 | 68.6 | 63.9 / 70.9 | 62.5 / 75.5 |
| three agree on the key | odd | 55.7 | 66.1 | 79.6 | 47.1 | 68.5 | 72.7 / 84.5 | 60.4 / 71.9 |
| | even | 56.5 | 61.6 | 75.9 | 41.7 | 61.6 | 67.9 / 78.1 | 56.7 / 67.9 |
| two or more agree | odd | 96.2 | 58.2 | 73.8 | 32.0 | 52.0 | 68.2 / 80.2 | 44.0 / 48.0 |
| | even | 95.0 | 53.9 | 71.6 | 25.8 | 35.5 | 63.8 / 74.5 | 48.4 / 58.1 |
| three agree on the home note | odd | 74.4 | 63.1 | 83.1 | 41.9 | 50.3 | 72.7 / 86.0 | 51.2 / 58.4 |
| | even | 74.6 | 58.5 | 78.1 | 36.7 | 44.9 | 67.5 / 79.4 | 49.7 / 56.8 |
| three agree and B sure | odd | 31.4 | 70.2 | 76.1 | 51.9 | 74.0 | 75.0 / 82.4 | 63.7 / 77.4 |
| | even | 31.6 | 67.5 | 76.1 | 46.2 | 66.7 | 69.0 / 76.1 | 60.3 / 72.6 |

**What it shows.** Every rule holds its shape on both halves. The sure flags separate exact reads (B's: 64 against 49
on all clips) but not home-note reads (71.4 against 72.8): they measure confidence in the mode, not the home note.
Agreement on the home note does separate the home note: three-quarters of clips kept at 80.6 against 47.7 on the rest
(all 1,275), above Apple's overall 76.4, though Apple too does better on those clips (82.7), so they are partly the
easy ones. Two-of-three keeps almost everything and so flags little. No rule is chosen here.

**Cost.** Nothing to build in the lab. Engine: the agreement rules need all three readers; A is a few
multiplications a frame on 3f's chroma, B is the NNLS front end (the cost in avenue 2). **Risks:** an unsure flag on
half the crate is a product question, not a research one. **Experiment:** none needed to show the trade; whether the
same separation holds on non-EDM music needs a second outside set.

## 4. The mode in dance music

**What the literature says** [2nd]. GiantSteps Key (604) is about 85 percent minor (letter R, from Knees et al. 2015);
the plain-key clips of GiantSteps-MTG-key are 69.6 percent minor (884 of 1,270, counted from the annotations, letter R).
Faraldo, Gómez, Jordà and Herrera 2016 (ECIR, LNCS) built EDM profiles from a Beatport corpus; Faraldo, Jordà and
Herrera 2017 (AES Semantic Audio) added the multi-profile method aimed at "difficult minor" and possibly amodal tracks;
Faraldo's 2018 thesis (over 2,000 excerpts) argues that a major/minor binary misfits EDM and proposes open labels for
modal practice (Phrygian, Dorian) and ambiguous tonality. Apple answers minor on 79 percent of the clips (1,003 of
1,270) where the truth is 70: it behaves as if it carries a minor prior [inf].

**Priors under D5.** A prior toward minor is a fitted parameter unless it is a published corpus statistic named with
where it was measured. The candidates are the 85 percent of GiantSteps Key (Beatport EDM, 604 tracks) and the 70
percent of MTG-key (Beatport EDM, 1,270 plain-key clips); the second is the test set itself, so a prior from it is
test-on-train. Both are EDM shares; a pop or house-with-vocals crate is not 85 percent minor, so for any DJ the prior
would have to be per genre, and the genre is not known to the reader.

**Expected gain** [inf]. A prior moves errors between the halves, which D16 scores separately: the minor half rises,
the major half falls, and the home note does not move (a mode prior re-decides the mode on the same tonic). Since
Apple's major half (41.5) sets a low bar, a prior could pass D16 on this set while being worse for a DJ who plays
mostly major-key music. **Cost:** an hour. **Experiment:** if tried, the prior fixed at the GiantSteps Key share
(85 percent, Knees 2015), scored on the even ids by half, and on a non-EDM set before any conclusion.

## 5. What the commercial and open tools score

All on GiantSteps Key (604) unless named [2nd]; weighted is MIREX.

| Tool | Exact | Weighted | Source |
|---|---|---|---|
| rekordbox 3 | 71.9 | | Knees et al. 2015, ISMIR, Table 5 |
| Mixed In Key 7 | 67.2 | 67.2 | Knees 2015; Faraldo 2017 (weighted 0.672) |
| KeyFinder | 45.4 | 60.4 (Faraldo 2017) / 59.3 (Yonay 2026) | |
| QM Key Detector | 39.4 / 39.6 | 50.4 | Knees 2015; Korzeniowski 2017 |
| Essentia default | 30.5 | | Knees 2015 |
| Faraldo edmm / bgate / edma | 63.7 / – / 57.8 | 64.2 / 64.1 / 58.1 (Faraldo); 70.1 / – / 65.6 (Korzeniowski re-run) | |
| madmom AllConv | 67.9 | 74.6 (71.0 in Kong 2025's re-run) | Korzeniowski 2018 |
| Mixed In Key 8 to 10 | about 85 on GiantSteps+, about 76 on MTG-key | | an r/DJs post (2021 to 2022), seen only as a search snippet [unverified; subsets and scoring unknown] |

Where our options would land on that scale, very roughly (our numbers are on MTG-key, not the 604): 3f 47.6 exact
(near KeyFinder), B 55.6, Apple 65.2 (near Mixed In Key 7), a trained model 62 to 70 [inf] (near madmom and Mixed In
Key). DJ TechTools' listening tests (letter R) put Mixed In Key ahead of rekordbox and Traktor on mixed music.

## 6. Other ideas for the home note

Our largest home-note errors are the dominant (+7: 127 clips of 1,270 for 3f, 85 for B) and the subdominant (+5: 65
and 72); Apple's are 67 and 59.

| Idea | Evidence | Expected gain [inf] | Cost | Experiment |
|---|---|---|---|---|
| Separate the percussion first (harmonic-percussive separation by median filtering: Fitzgerald 2010, DAFx; Ono et al. 2008, EUSIPCO; cited from memory, not re-read) | Letter R's beat-grid result: frames with the kick were the worst frames | home 0 to +3 | 1 day; engine: two median filters on the spectrogram, under 0.1 s a track | fixed published filter lengths; 3f and B on separated audio; even ids, sign test |
| A learned twelve-number profile from a different outside set (FMAKv2 multi-genre, or GiantSteps+), then tested on MTG-key | Faraldo's own profiles were made this way from Beatport; Krumhansl's from listening tests | home 0 to +4; also a check of how much braw and bgate owe to this set | 1 to 2 days; engine: 24 numbers | profile derived on FMAKv2 only, scored on MTG-key; no MTG clip used in the derivation |
| Read the full track, not 2 minutes | AllConv's right answers came from longer excerpts (median 131 s against 51 s) [2nd] | the engine reads full tracks already; the clip score may understate it | none in the lab | needs a full-track outside set (Billboard or Isophonics on owned CDs) |
| Averaging over pitch shifts at read time (equivariance) | standard for trained models; S-KEY and STONE build it in | only with a trained model | hours | inside avenue 1 |
| Phrase-end weighting (the tonic at cadences) | none for EDM; the beat-grid test argues against weighting by position | unknown, risky | 1 day | as the beat-grid test, fixed weights |

## Options for the owner

1. **Keep D16 as it stands and add nothing to the reader.** Non-Apple platforms keep "key not read on this computer
   yet". Cost nothing; gain nothing; the research track stays open for when training data is settled.
2. **Put row B (or the cheaper row A) into the engine as the reader in waiting, still behind D16.** Exact rises about
   8 points (47.6 to 55.6 against Apple's 65.2), the home note about 3 (B) and within chance. A costs hours; B costs 2 to
   3 days of Swift for the NNLS front end. Neither clears D16's minor half (56 against about 70.6 needed).
3. **Use agreement as the "key unsure" signal of D17 now.** On the outside set, three readers agreeing on the home
   note keeps three clips in four at 80.6 percent home note (47.7 on the rest), both halves alike. It needs A and B
   beside 3f in the engine (option 2's cost); it moves no overall score.
4. **Run a trained model for evaluation only**, to learn whether a model clears D16 before anyone asks how to ship
   one: 5 to 8 days of work and overnight training runs, artist-grouped folds on the set we hold, plus GiantSteps+
   (856 MB, CC BY-SA 4.0) and Apple re-run on it. Expected [inf] exact 62 to 70 and home note 72 to 78 against Apple's
   65.2 / 76.4; nothing ships from it.
5. **Shipping a trained model** needs training data cleared for shipped weights, which is the open question: the
   MTG-key audio (Beatport's; owner's word and the attorney under D15), FMAKv2 labels on FMA's CC audio (multi-genre,
   5,489 songs; licence check per track), or the commissioned mixed-genre listening set D16 already names, on audio
   Deckie has rights to. Weeks, decided by the data, not the code; weights 0.5 to 2 MB, under 0.5 s a track.
6. **Chord-level key** as a research step: 4 to 6 days on top of B, expected home note 0 to +4 [inf]; no published
   figure on dance music to lean on.
7. **Two cheap home-note probes**, a day or two each: percussion separated before the chroma, and a profile learned
   from a different outside set. Expected 0 to +4 on the home note [inf]; each also says something about how much the
   current profiles owe to Beatport.

## Data sets to fetch, with licence and size

Nothing was fetched for this letter. Every fetch needs the owner's word; the MTG-key audio is already held (Oct 29).

| Data set | Size and music | Annotation | Licence (labels; audio) | Audio | Use here | Owner's word |
|---|---|---|---|---|---|---|
| GiantSteps-MTG-key (Beatport EDM Key Dataset, Zenodo 1101082) | 1,486 two-minute EDM clips; 1,077 single-key high-confidence | track level (main key, confidence; key changes noted) | CC BY-SA 4.0; Beatport's and the labels' | on Zenodo, 2.13 GB | held; evaluation only; training needs a new word | held; training: yes |
| GiantSteps+ (Zenodo 1095691) | 600 EDM clips, the revised 604 | track level; key and modal changes on 500 | CC BY-SA 4.0; Beatport's | on Zenodo, 856 MB | the clean outside test for anything trained on MTG-key | yes |
| GiantSteps Key (Knees 2015) | 604 EDM clips | track level | none stated; Beatport's | script fetches previews | the published scale | yes |
| FMAK / FMAKv2 (Zenodo 12759100) | 5,489 songs, 17 genres | track level, expert | CC BY 4.0 per Zenodo, non-commercial per mirdata (conflict); FMA audio mixed CC per track | FMA, not bundled | multi-genre test, or training | yes; licence check first |
| McGill Billboard | 742 songs, 625 with key; pop and rock 1958 to 1991 | per section (tonic lines; mode not always given) | CC0; none | none (chroma features published [unverified]) | pop test on owned audio | yes |
| Isophonics | about 231 songs (Beatles, Queen, Carole King, Zweieck) | per segment, timed | licence not found; CDs | none | pop test on owned CDs | yes |
| KeyFinder set (Sha'ath 2011) | 1,000 annotations, mixed genres | track level | not found; none | none (Baumann found 833) | mixed-genre test | yes |
| GTZAN key (Kraft et al.) | 837 clips, 10 genres | track level | MIT (labels); GTZAN audio of unclear origin | GTZAN | test only, known problems | yes |
| Schubert Winterreise Dataset | 24 songs in several performances [unverified count] | per measure and global | CC BY 3.0 | some performances | out of scope (classical) | not proposed |

Sources read for this letter: Korzeniowski and Widmer 2017 (arXiv 1706.02921) and 2018 (arXiv 1808.05340); Baumann
2021 (ISMIR proceedings pp. 42 to 49); Schreiber and Müller 2019 (arXiv 1903.10839); Kong et al. 2025 (arXiv
2501.12907) and the deezer/s-key repository; Yonay, Hammond and Yang 2026 (arXiv 2604.10021); Noland and Sandler 2006
(ISMIR); Peeters 2006 (ISMIR, harmonic peak subtraction, a classical-music cousin of row A); the madmom README and
docs; Essentia's model page; the Zenodo records above; the GiantSteps page at JKU; Faraldo 2018's abstract. The
GiantSteps 2015 paper and Faraldo 2017 figures are as letter R quotes them.
