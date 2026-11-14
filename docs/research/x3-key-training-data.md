# Research X3: training data for a key reader that could ship

Dated Nov 14, 2026. An answer with evidence to the owner's question after D33: "Do we need to commission or is there
a public use set we can use?", and to his two follow-ups: public-domain music, and music we make ourselves ("but
only a bit"). Licences were opened and are quoted with the date; experiments train only on data that could ship and
score only on real dance music the reader never saw. Builds on letters X2 (the trial), T and X, and on D15, D16 and
D33. Scripts in `mixer/keytrial/` (`kt_ship.py`, `kt_made.py`, `kt_scores.py`, `kt_remote_zip.py`; commands in its
README); per-mix scores in `mixer/keytrial/ship_results.tsv`. **No audio, data set or weights are committed.**
Tags: [opened] = the page or file was fetched and read on Nov 14, 2026; [snippet] = seen only as a search summary;
[inf] = my inference; [unmeasured] = not measured. Not legal advice; the points for the attorney are collected at
the end.

## In plain words

A trained key reader learns from songs whose keys someone has written down. To ship one in a paid app, Deckie needs
the right to use both halves of every training song that way: the **recording** (the audio) and the **label** (the
key). A licence that allows commercial use of both is enough; "non-commercial" on either half rules a song out, and
"share-alike" is the unsettled case (section 1). **Made-up music** here means music whose key is known because we
made it: a score in the public domain played by our own synthesiser, or a piece written by a program of ours to a
chosen key. The **bar** is D16's, which D33 kept: exact key within five points of Apple's framework on the major and
on the minor half of the GiantSteps MTG clips (36.5 and 70.6).

## Summary

SUMMARY_TBD

## 1. What "could ship" means

**The rule in force.** D15: weights ship under their publisher's licence; training sets and their terms are
disclosed; a data owner's objection stops it. The standing rule on top: data under a non-commercial or share-alike
licence is for evaluation only.

**What Creative Commons itself says** [opened: "Using CC-Licensed Works for AI Training", creativecommons.org, May
2025, and its PDF]:

- Share-alike: "following the ShareAlike condition would require AI developers to use the same CC license as the
  original works."
- Non-commercial: "all stages, from copying the data during training to sharing the trained model, must not be for
  commercial gain."
- No-derivatives: "Following the NoDerivatives restriction would require that ND-licensed content not be used as
  training data."
- And that this is the cautious reading: "following this guidance is likely to lead to overcompliance with both
  copyright law and CC license terms. It assumes the most restrictive legal interpretation".
- The legal trigger, same page: "The attribution (BY) and ShareAlike (SA) conditions, and NoDerivatives (ND)
  restriction are triggered only when works or adaptations of works are publicly shared", and "CC licenses apply
  only when copyright permission is required. If exceptions or limitations apply, then the CC license terms don't
  apply."

So on Creative Commons' own cautious reading, **share-alike labels would taint shipped weights** (the weights would
have to be shared under the same licence), non-commercial data is out, and attribution-only (CC BY) and CC0 data are
usable with credit given. Whether a court would treat 49 numbers or a small network as an "adaptation" of key labels
is not something this letter can settle; the standing rule already takes the cautious side and this letter keeps to
it. A CC BY source means its makers are credited in the app's acknowledgements (for the loops below, a few hundred
names).

## 2. Labelled sets: what each licence says

Audio and labels are separate rights. "Usable" means both allow commercial use and neither is share-alike.

| Set | Size, music | Labels: how made, licence | Audio: bundled? licence | Usable for shipped weights? |
|---|---|---|---|---|
| **Freesound Loop Dataset** (FSL10K, Zenodo 3967852) [opened] | 9,455 loops, mostly electronic and dance | about 3,000 loops annotated by people in a web tool (key, mode, tempo, instruments); record licence CC BY 4.0 | bundled, 8.8 GB; "All the sounds have some kind of Creative Commons license. The license of each sound in the dataset can be obtained from the 'FSL10K/metadata.json' file": CC BY 3.0 4,827; CC0 3,230; CC BY-NC 1,215; Sampling+ 221 [counted] | **Yes, in part: 711 loops** have a key and mode their annotators agree on and are CC0 (380) or CC BY 3.0 (331); 285 uploaders; 41 percent major |
| **FMAK** (Zenodo 10719860) [opened] | 5,489 songs, 17 genres, 340 hours | one expert, a sample cross-checked by two; record licence CC BY 4.0: "The FMA metadata is made freely available for public use under a Creative Commons license"; but also "The dataset is meant for research purposes", and mirdata's loader says in one place "available for conducting non-commercial research" and in another "Creative Commons Attribution 4.0 International" | bundled, 39 GB; "We do not hold the copyright on the audio and distribute it under the license chosen by the artist": BY-NC-SA 2,421; BY-NC-ND 1,807; BY-NC 675; BY 347; BY-SA 158; public domain or CC0 35; BY-ND 25; other 21 [counted against FMA's tracks.csv] | **Yes, in part: 373 songs** whose own licence is CC BY (347) or CC0 / public domain (26, leaving out "common law protection" entries); 65 artists; half major. The "research purposes" wording on the labels is for the attorney |
| FMAKv2 (Zenodo 12759100) [opened] | the same songs, about 200 labels changed | CC BY 4.0; "Authors of FMAK did not verify the modifications" | none | not used: the original labels were |
| Beatport EDM Key Dataset = GiantSteps-MTG-key (Zenodo 1101082) [opened] | 1,486 dance clips | CC BY-SA 4.0 | bundled; "belong to online audio snippets from Beatport" | No: share-alike labels, audio not licensed |
| GiantSteps+ (Zenodo 1095691) [opened] | 600 dance clips | CC BY-SA 4.0 | bundled, Beatport's | No |
| GiantSteps Key [opened: repository README] | 604 dance clips | no licence statement found | fetched from Beatport | No |
| McGill Billboard [opened: ddmal.ca] | 740 pop songs, 1958 to 1991 | CC0: "we have made them available legally under a CC0 license"; the home note of the opening key only, no mode | "we cannot distribute the original audio due to copyright" | Labels yes; no audio we may use |
| Isophonics [opened] | Beatles, Queen and others | no licence statement | commercial CDs | No |
| GTZAN key [opened] | 10 genres | MIT | GTZAN's audio, origin unclear | No |
| Schubert Winterreise Dataset (Zenodo 10839767) [opened] | 24 songs, nine performances | CC BY 3.0; keys by three annotators | two performances included; "must not be re-distributed in modified form" for one | marginal: classical song, tiny |
| MusicNet (Zenodo 5120004) [opened] | 330 classical recordings, 34 hours | CC BY 4.0; no key field, but 310 titles name a key | bundled, 11 GB: "Creative Commons licensed and Public Domain performances" | Likely yes after a per-recording check; not fetched (11 GB) |
| AAM, Artificial Audio Multitracks (Zenodo 5794629) [opened] | 3,000 pieces composed and rendered by an algorithm | exact keys; CC BY 4.0 | bundled, 44 GB | Yes; it is made-up music (section 4); not fetched |
| GuitarSet (Zenodo 3371780) [opened] | 360 solo guitar excerpts | key and mode; CC BY 4.0 | bundled | Yes; one instrument; not fetched |
| DCML scores (Beethoven, Mozart, quartets) [opened] | scores with local keys | CC BY-NC-SA 4.0 | none | No |
| MAESTRO [opened: Zenodo field] | 199 hours of piano | none | CC BY-NC-SA 4.0 | No |

A Zenodo search for key data sets under CC0 or public domain found nothing beyond these. **So a public set exists
that can be used without commissioning anything: about 1,080 real recordings (711 loops and 373 songs), a third to
a half of them dance or electronic, with human key labels and licences that allow it.** Section 5 measures what it
is worth.

## 3. Public-domain music

**Composition and recording are two copyrights.** Bach is long out of copyright; a 2015 recording of Bach is not,
unless its makers gave it away. A public-domain *score* gives us notes to render ourselves (section 4a); only a
public-domain or CC0 *recording* gives real audio.

| Source | What | Status [opened unless marked] | Key known from |
|---|---|---|---|
| Open Well-Tempered Clavier, Book 1 | 48 piano recordings, 109 minutes, a prelude and a fugue in each of the 24 keys | "has released her studio recording ... into the public domain"; the album page: "The recording is licensed with the Creative Commons Zero - public domain - license" (the page's licence widget links to CC BY 4.0, which contradicts its text; either allows this use). An account-free copy is on archive.org | the title ("Fugue No. 3 in C-sharp major") |
| Open Goldberg Variations | 31 piano recordings, 82 minutes | "All tracks are provided without copyright (Creative Commons Zero). All uses permitted." | the title; nearly all in G major |
| Musopen | orchestral, chamber and piano recordings | its own terms would not open (403). On archive.org its collection says "without copyright restrictions"; one item is CC0 from Musopen's own account (208 files), others are third-party uploads with a Public Domain Mark. Musopen's FAQ says it "cannot guarantee that any music uploaded by its users is, in fact, in the public domain" [snippet] | titles |
| MusicNet | 330 recordings from Musopen, a museum and an archive | CC BY 4.0 for the set; per-recording licences not checked | titles (310 of 330) |
| US military bands | marches, concert band | 17 U.S.C. 105: "Copyright protection under this title is not available for any work of the United States Government"; the bands' own pages would not open; the recorded sound is public domain but an arrangement or a modern composition played may not be [snippet] | rarely in titles |
| IMSLP recordings; Wikimedia Commons | mixed | per file; Commons takes no non-commercial-only files; IMSLP requires "both the composition and the recording must be in the public domain (or released under an acceptable license)" | titles |
| Internet Archive 78s | 187,000 sides | no collection licence; in the US only recordings published before 1923 are clearly public domain federally | 1,442 titles name a key |

**What a title's key is worth as a label.** "Fugue in A minor" names where the piece begins and ends. A classical
movement travels: a minor-key first movement spends its second theme in the relative major, a development in keys
further off. A song-level label is then true of the whole and false of many of its minutes, and a reader trained on
half-minute snippets is taught wrong answers for those. Bach's preludes and fugues are short and stay close to home,
which is why they are the usable case; a symphony movement is not, without per-section labels. Dance music mostly
does not modulate, so the problem is the classical music's, not the target's.

**Does a reader built on classical or pop music carry to dance music?** The published evidence says poorly
[2nd, letter T]: a network trained on pop (Billboard) scored 47.0 exact on the 604 dance clips against 67.9 for the
same network trained on dance clips, and the dance-trained one lost 8 points to a plain profile on pop; the
GiantSteps authors made dance-music profiles precisely because classical profiles (Krumhansl, Temperley) failed
there (letter R measured it: 52.7 to 69.5 against 83 on the lab's crate). I found no study that trains a key reader
on rendered or generated music and reports a score on real dance music [searched; not found].

**Tried** (section 5): the 48 Well-Tempered Clavier recordings alone teach the 49-number reader to 48.9 exact on MTG,
nine points *below* the reader with nothing trained. Added to the real base they change nothing (58.7 against 58.8).

## 4. Music whose key is known by construction

Kept as three kinds. All are supplements to real audio; none was used to choose or to score anything.

**(a) Public-domain scores played by our own synthesiser** (`kt_scores.py`). 412 four-part chorales by J. S. Bach,
the first 24 seconds of each, played by four additive synthesiser voices with a kick drum on the beat and hats
between, at a random tempo and detune. The key is read from the score: the last bass note is the home note, and the
key signature says major or minor. No one's licence is needed for the composition; the *encoding* of the notes has
its own terms (the music21 corpus's note says "Some encodings included in the corpus may not be used for commercial
uses"), so a shipped model would take notes from an encoding that is plainly free, such as the Open Well-Tempered
Clavier's CC0 score. For evaluation the corpus was used as it is.

**(b) Music written by a program of ours** (`kt_made.py`). 1,500 clips of 24 seconds: a tempo of 100 to 150, a key
drawn evenly from the 24, a four-on-the-floor kick, hats and a clap, a bass line, chords as a pad or as stabs, and
usually a lead; each pitched part an additive voice whose brightness is drawn at random, so some carry the strong
fifth overtone that the trial found reads as a major third. Four kinds: a plain chord loop (58 percent); one chord
throughout (14); no third anywhere, labelled half major and half minor on its home note because nothing in the
audio says which (14); and a minor key whose bass sits on the relative major every other bar (14). The last three
are the cases the trial found hard and that labelled sets do not mark.

**(c) Music from a trained generator asked for a key**: weighed on paper only, as the owner directed. It is not a
route. The services' terms forbid it: Suno, "to power, enable or train other artificial intelligence and machine
learning models" is barred [opened, terms effective Sept 3, 2026]; Udio bars output "to power, enable, inform,
develop or train other artificial intelligence and machine learning models" and allows personal use only [opened,
revised Nov 12, 2025]; Stability's general terms bar use "to develop or train any artificial intelligence" that
competes [opened]; MusicGen's weights are CC BY-NC 4.0 [opened]. Beyond the terms: a 2026 paper's title asks whether
text-to-music models follow a requested key at all [snippet; not read], so every label would need checking by ear,
which is the labelling work the generator was meant to save; what those generators learned from is itself in
dispute; and Deckie would have to disclose the source under D15.

## 5. Experiments: train on what could ship, score on real dance music

**Protocol.** Training data: only the usable sets above. Readers: the trial's learned profiles (49 numbers on rows A
and B's chroma) and its small convolutional model, unchanged. Scoring: the three GiantSteps sets, none of which any
reader here saw in training; Apple and the bar on the 1,270 MTG clips. Nothing is chosen on made-up music: the
profiles have nothing to choose, and the model's stopping pass is chosen on real loops and songs of uploaders and
artists it did not train on. "Modes equal" weighs major and minor clips the same in the fit. A loop is repeated to
24 seconds before it is read.

**The real data, as fetched** (evaluation only; only the files used were pulled, by range requests into the
archives): 710 loops (418 minor; median length 11 s; 285 uploaders); 371 FMAK songs (181 minor; median 213 s; 64
artists; two files would not decode); 48 Clavier recordings.

### 5.1 Learned profiles on each real source (MTG, 1,270 clips)

| Trained on | Fit | Exact: all | major | minor | Mean of halves | Within one step | Home note |
|---|---|---:|---:|---:|---:|---:|---:|
| *Nothing (row B's home note, row A's mode)* | | 57.8 | 54.4 | 59.3 | 56.8 | 71.7 | 72.4 |
| *The MTG collection itself, other artists (letter X2; cannot ship)* | as the set is | 62.7 | 35.8 | 74.4 | 55.1 | 76.1 | 74.5 |
| *Apple* | | 65.2 | 41.5 | 75.6 | 58.5 | 78.3 | 76.4 |
| Freesound loops (710) | as the mix is | 58.1 | 56.7 | 58.7 | 57.7 | 73.2 | 73.6 |
| | modes equal | 54.5 | 67.1 | 49.0 | 58.0 | 68.7 | 73.3 |
| FMAK songs (371) | as the mix is | 56.3 | 47.2 | 60.3 | 53.7 | 71.9 | 67.6 |
| | modes equal | 56.9 | 46.6 | 61.4 | 54.0 | 72.5 | 68.1 |
| Well-Tempered Clavier (48) | either | 48.9 | 54.7 | 46.4 | 50.5 | 70.6 | 62.5 |
| **Loops + FMAK songs (1,081): the real base** | as the mix is | **58.8** | 56.0 | 60.1 | 58.0 | 73.9 | 73.4 |
| | modes equal | 55.5 | 61.9 | 52.7 | 57.3 | 70.2 | 73.1 |
| Loops + songs + Clavier (1,129) | as the mix is | 58.7 | 56.0 | 59.8 | 57.9 | 73.7 | 73.4 |

On the other sets the real base scores 78.0 exact on GiantSteps+ (the untrained reader 76.9; MTG-trained profiles
81.4) and 62.6 on GiantSteps Key (60.9; 66.2).

- **The public data teaches the home note about as well as the test collection's own music did** (73.4 against
  74.5; untrained 72.4) and gains about one point of exact key over the untrained reader on every set.
- **It does not reach the MTG-trained profiles' 62.7, and the difference is the lean, not the hearing.** The mean of
  the halves is 58.0 here against 55.1 for the MTG-trained profiles and 58.5 for Apple. The public data is 41 to 49
  percent major; MTG and the GiantSteps sets are 12 to 30 percent major. A reader taught on balanced music does not
  learn "when in doubt, minor", so it scores 60 on the minor half, where the bar asks 70.6.
- **Loops carry to songs.** The 710 loops, median 11 seconds, alone do as well as loops and songs together. The 371
  songs alone are weaker on the home note (67.6), with 64 artists against 285 uploaders.
- **Classical recordings alone are harmful and added are neutral**, as the literature said.

### 5.2 The real base weighed to a published share of minor keys

The bar stays as written (D33), and section 2.2 of letter X2 showed that it rewards leaning minor. A lean can be
taken from a published count of dance music instead of from a test set: weigh the training clips so that minor ones
are that share of the fit.

| Real base weighed to | Exact: all | major | minor | Mean of halves | Bar as written (36.5 / 70.6) | GiantSteps+ exact | GiantSteps Key exact |
|---|---:|---:|---:|---:|---|---:|---:|
| as it is (55 percent minor) | 58.8 | 56.0 | 60.1 | 58.0 | fails: minor 10.5 short | 78.0 | 62.6 |
| 65 percent minor (a Beatport top 100 of 2023, letter X) | 61.2 | 44.3 | 68.6 | 56.4 | fails: minor 2.0 short | 80.3 | 65.1 |
| 70 percent minor (the MTG collection's own share) | 61.3 | 36.8 | 72.1 | 54.4 | **passes** (by 0.3 and 1.5) | 80.3 | 65.1 |
| 85 percent minor (GiantSteps Key, Knees et al. 2015) | 58.7 | 16.1 | 77.3 | 46.7 | fails: major 20.4 short | 78.4 | 65.2 |

- **With shippable data and a lean of 70 percent, the 49-number reader passes the bar as written, by margins inside
  the noise** (the 95 percent interval on each half is about plus or minus 3 to 5 points). The 70 is MTG's own
  share, so that row is fitted to the test set in one number and must not be reported as a clean pass. The clean
  rows are 65 (fails by 2.0 on the minor half) and 85 (fails badly on the major half).
- **The price of the lean is the major half**: 56 percent of major-key songs right with no lean, 44 at 65 percent,
  37 at 70, 16 at 85.

### 5.3 How much made-up music is safe

The real base plus made-up clips, so that the made-up clips are the stated share of the whole mix (100 percent:
made-up only, as many clips as the real base). Three draws of made-up clips each, averaged. Learned profiles, as the
mix is; MTG then the two other sets.

| Made-up share | Program-written: MTG exact | mean of halves | home note | GiantSteps+ exact | GiantSteps Key exact | Rendered chorales: MTG exact | mean of halves | home note | GiantSteps+ exact | GiantSteps Key exact |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 % | 58.8 | 58.0 | 73.4 | 78.0 | 62.6 | 58.8 | 58.0 | 73.4 | 78.0 | 62.6 |
| 10 % | 58.2 | 57.0 | 73.0 | 78.8 | 62.6 | 58.6 | 58.0 | 73.3 | 77.9 | 62.2 |
| 25 % | 57.9 | 56.9 | 72.8 | 78.5 | 61.9 | 58.3 | 57.7 | 72.8 | 77.6 | 61.9 |
| 50 % | 55.9 | 54.6 | 71.8 | 77.3 | 61.1 | 58.0 (capped at 28 %: only 412 chorales) | 57.5 | 72.5 | 77.6 | 61.9 |
| 100 % | 50.7 | 50.5 | 69.7 | 72.2 | 56.6 | 55.5 | 54.6 | 68.1 | 73.9 | 60.3 |

**Drift**: clips the reader had right with no made-up music and has wrong with it, by the kind of the new mistake,
against clips gained (program-written music, modes equal, one draw):

| Set | Made-up share | Lost: fifth | relative | parallel | other | Lost in all | Gained | Net |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MTG, 1,270 | 10 % | 2 | 2 | 10 | 4 | 18 | 29 | +11 |
| | 25 % | 7 | 3 | 13 | 11 | 34 | 41 | +7 |
| | 50 % | 10 | 10 | 41 | 16 | 77 | 50 | −27 |
| | 100 % | 22 | 21 | 93 | 34 | 170 | 82 | −88 |
| GiantSteps+, 468 | 10 % | 1 | 0 | 1 | 2 | 4 | 9 | +5 |
| | 25 % | 2 | 0 | 2 | 3 | 7 | 12 | +5 |
| | 50 % | 5 | 1 | 6 | 4 | 16 | 15 | −1 |
| | 100 % | 20 | 1 | 19 | 9 | 49 | 20 | −29 |
| GiantSteps Key, 604 | 10 % | 2 | 0 | 3 | 2 | 7 | 8 | +1 |
| | 25 % | 6 | 0 | 3 | 2 | 11 | 10 | −1 |
| | 50 % | 10 | 3 | 9 | 4 | 26 | 14 | −12 |
| | 100 % | 26 | 4 | 23 | 8 | 61 | 21 | −40 |

- **The owner's caution is borne out.** Made-up music does not help the 49-number reader at any share: within a
  point of the real base up to a quarter of the mix (the exact rate drifts down 0.6 to 0.9 on MTG, up 0.5 on
  GiantSteps+; all inside noise), clearly worse at a half (minus 3 on MTG), and much worse alone (minus 8). **The
  point where it starts to hurt is between a quarter and a half.**
- **What goes wrong is the mode.** More than half of the songs lost at a half and at 100 percent are new parallel
  errors (right home note, wrong mode): 41 of 77 and 93 of 170 on MTG. The made-up music's thirds are cleaner than
  real records', and a reader that learns from them trusts the third too much. That is the made-up music's habit
  showing, exactly the drift the owner asked to be watched for.
- **Rendered chorales are gentler than program-written music** (alone: 55.5 against 50.7 on MTG) but give no gain
  either, and alone they lose five points of home note.
- **Made-up music alone is not a route**: 50.7 exact on MTG, seven points under the reader with nothing trained.

### 5.4 Which made-up cases earn their place

At a quarter of the mix, modes equal (the real base alone: MTG 55.5 exact, 57.3 mean of halves; GiantSteps+ 75.6;
GiantSteps Key 60.6). Three draws each.

| Made-up clips used | MTG exact | mean of halves | minor: mode right given home | GiantSteps+ exact | GiantSteps Key exact |
|---|---:|---:|---:|---:|---:|
| all four kinds | 55.7 | 57.1 | 73.3 | 76.5 | 60.2 |
| only one chord throughout | 56.8 | 57.9 | 76.0 | 76.5 | 61.4 |
| only no third (mode open) | 56.4 | 57.9 | 75.6 | 75.4 | 59.9 |
| only plain chord loops | 55.6 | 56.7 | 74.1 | 76.1 | 60.3 |
| only minor with the bass on the relative major | 50.6 | 54.2 | 62.2 | 75.0 | 58.6 |
| all but plain loops | 53.6 | 56.3 | 67.7 | 76.9 | 60.0 |
| all but one chord | 54.8 | 56.6 | 71.3 | 76.4 | 59.6 |
| all but no third | 55.3 | 56.7 | 73.0 | 76.7 | 60.3 |
| all but relative | 55.2 | 56.4 | 73.5 | 76.1 | 60.5 |

- **The one-chord case earns a small place** (plus 1.3 exact on MTG, plus 0.9 on GiantSteps+, plus 0.8 on
  GiantSteps Key): it is the hard case the trial named, and real labelled sets hold few of it.
- **The no-third case is neutral to slightly useful** on MTG and neutral elsewhere. Its real use is different: it is
  the only source of clips *labelled* "mode open", which a reader with an open-mode answer would need
  [unmeasured: no reader here has that answer].
- **The relative-major-bass case as I wrote it does harm** (minus 5 on MTG, and the minor songs' mode right falls
  from 73 to 62): a minor piece with its bass on the relative major half the time is, to the ear and to the reader,
  half in that major key. It is dropped.
- **Plain chord loops add nothing** the real data does not already teach.
- All of these differences are one to two points on sets where the noise is two to three; none is established.

### 5.5 The small convolutional model on shippable mixes

CNN_TBD

## 6. Labelling openly licensed dance music ourselves

The other way to get real, shippable data without commissioning music: the audio already exists under licences that
allow it, and only the keys are missing.

- **Audio available** [counted]: 7,346 more Freesound loops under CC0 or CC BY 3.0 that have no agreed human key
  (most are drums; the data set's own annotators found a key in about half of the loops they looked at); and in the
  Free Music Archive, 8,352 tracks under CC BY, CC0 or public domain (580 hours, 1,308 artists), of which 634 are
  tagged electronic, 316 hip-hop, 378 pop, 520 rock (5,280 carry no genre tag). The archive's host would not answer
  from this session [could not fetch]; FMAK's own archive on Zenodo holds the 5,489 labelled ones.
- **How many.** Letter X2's learning curve: the 49-number reader stops improving at about 400 songs. This letter
  adds that 710 loops and 371 songs, a thousand recordings, bring it level with what the test collection's own music
  taught on the home note. So labelling does not need to be large: **400 to 600 dance and electronic tracks**, chosen
  to be about 70 percent minor if the bar stays as written (section 5.2), plus **300 kept apart for scoring**.
- **By whom, how long** [inf]. A musician at a keyboard names the home note and mode of a dance track in two to four
  minutes, the ambiguous ones longer; 900 tracks is 30 to 60 hours for one person, plus a second person on a fifth
  of them (6 to 12 hours) so that their agreement is known. Labels should allow "mode open" and carry a confidence,
  as letter X2 set out. The labels would be Deckie's own, under no one's licence.
- **Against commissioning**: this is the commissioned set of D16 with the music already paid for. What it lacks is
  the music DJs play that is not on a free archive: current club tracks, chart pop, hip-hop, Latin. The scoring set
  should not come only from the free archives for that reason [inf].

## 7. The mixes that could ship, and how each scores

All on the 1,270 MTG clips; the bar is 36.5 major and 70.6 minor. Rows marked * are fitted to the test set's own mix
of modes in one number.

MIXES_TBD

## What I could not verify

- **Musopen's own terms** and the **US military bands' own pages** (all returned 403); what is said of them rests
  on the statute, the Internet Archive's item pages and search summaries.
- **The FMAK labels' terms**: the Zenodo record says CC BY 4.0 and "freely available for public use"; the same
  description says "meant for research purposes", and a third-party loader says "non-commercial research" in one
  place and CC BY in another.
- **Per-recording licences inside MusicNet**, and whether the Free Music Archive's licence column is right for every
  track (it is the archive's own record; artists set it).
- **The Free Music Archive's audio host**: unreachable from this session, so only the FMAK subset (on Zenodo) was
  used, and no unlabelled archive audio was fetched.
- **Whether loop labels are as good as song labels**: 478 of the 711 loops were labelled by one annotator; those
  where two or three disagreed were left out.
- **Any study of made-up training music for key reading on real dance music**: searched, none found.
- **The convolutional model**: one run per mix, CPU only, as in letter X2.
- **Music that is not dance music**: every score here is on Beatport clips.

## For the attorney

1. Whether weights trained on **CC BY** audio and labels need more than attribution in the app (this letter assumes
   attribution is enough, on Creative Commons' own reading).
2. Whether the FMAK labels' "research purposes" sentence limits a commercial use that its CC BY 4.0 licence allows.
3. Whether **share-alike** labels taint weights (Creative Commons' cautious answer is yes; it calls that
   over-compliance). If the answer were no, the 1,486 MTG clips' labels would still need audio we may use.
4. The **encodings** of public-domain scores: which may be used commercially.
5. The contradiction on the Open Well-Tempered Clavier's album page (CC0 in the text, CC BY 4.0 in the widget).

## Options for the owner

OPTIONS_TBD
