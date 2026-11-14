# Research X4, complete: the key reader that can ship

Dated Nov 14, 2026 (overnight). What ships, how it scores beside Apple and the tools DJs pay for, how honest its
confidence is, what would lift it and at what cost, and what the Mac window and the iPad app must change. The
experiments behind the choice are in `x4-key-without-labelling.md`; the bar is D16's; the three answers are D33's and
D36's. Branch `key/shippable`. Scripts and tables in `mixer/keytrial/` (`kt_x4.py`, `x4_shipped_results.md`).
**No audio, data set or trained numbers are committed.** Not legal advice.

## In plain words

Deckie now has a **learned key reader**: a small model, trained only on recordings whose licences allow it, that
gives each song a **probability** for each of the 24 keys. From that probability come the same three answers as
before: a **key** when it is at least one half; the **home note** when the two keys on one note reach one half
together; otherwise **not sure**. **Coverage** is the share of songs shown a key; **precision** is how often a shown
key is right.

## Summary

- **The learned reader beats the untrained one on both counts, on every set.** On the 1,270 MTG clips it shows a
  key on 73 percent of songs and is right on 70 percent of those; the untrained reader shows 70 and is right on 65.
- **Its shown keys are right more often than Apple's framework is over all songs** (69.9 against 65.2 on MTG), and
  more often than the published scores of Mixed In Key 7 (65.7 there) and rekordbox 3 (71.9 on the 604-clip set;
  the learned reader's shown keys: 73.1). Those tools name a key for every song; Deckie declines one song in four.
- **It does not pass D16's bar as written**, which scores every song: 60.9 exact (59.8 major, 61.4 minor), 9.2
  short on the minor half. No lawful route does (`x4-key-without-labelling.md`, section 3).
- **It is in the shared core, in plain Swift, with no new dependency**, parity-tested against the Python, and takes
  half a second for a two-minute song.
- **One thing is not done, on purpose: the model's file is not published.** The key work's standing rule is that
  no trained numbers are committed, and a relayed message cannot lift a rule the owner set. The code is pinned to
  the file by its hash; where the file is present the learned reader decides, and everywhere else the untrained
  reader does, as before. **Publishing the file is the one decision left** (below, "The decision").

## 1. What ships

| | |
|---|---|
| The reader | `LearnedKey` (`core/Sources/DeckieCore/Key/LearnedKey.swift`): a log-frequency spectrogram (126 bands, five frames a second) and a convolutional model of 235,598 numbers, in plain Swift. Engine 0.7.0 |
| Its file | `deckie-key.f16`, 471,196 bytes, name `deckie-key-2b4fe8fa`, SHA-256 `2b4fe8fabf4fc5bd301e04af6c136afe76399f0077984a7f5df78b0ba0b07f7d`. Found at `DECKIE_KEY_MODEL`, in `core/.models/`, or in `models/` beside the PC program; any other file is refused |
| Trained on | 3,129 recordings under CC BY, CC0 or public-domain terms: 710 Freesound loops and 371 Free Music Archive songs with human key labels, 48 CC0 piano recordings, and 2,000 Free Music Archive clips labelled by the untrained reader. `DEPENDENCIES.md`, section 11, has the record in D15's shape |
| Not trained on | anything from GiantSteps or Beatport, anything non-commercial or share-alike, anything of the owner's |
| In a record | `key.source` `learned-key`; `key.confidence` the key's probability; `key_home` for a home note; `engine.models` names the model; the three-answer reader's key is kept as a vote |
| Without the file | the untrained three-answer reader, exactly as in engine 0.6.0 |
| Could the small model run in plain Swift? | Yes, and it does: about 135 million multiply-adds for thirty seconds of music. ONNX Runtime is not used, so the Mac and the iPad can run it from the shared core without carrying that library |

**Why this model.** Fixed before scoring: the candidate is the one taught on the most lawful data, and it replaces
the untrained reader only if its shown keys are right more often at the same coverage on MTG and one other set, and
not worse by more than a point on the third. It won by 5 to 7 points on all three. The 49-number learned profiles
also beat the untrained reader, by 1 to 3 points; the model is clearly better and still small.

**A plain caveat on the training data.** The 2,000 clips labelled by the untrained reader added nothing that can
be measured (61.7 against 61.5 exact on MTG). A model trained on the 1,129 human-labelled recordings alone would
score the same and have a shorter record. I kept the candidate that was fixed in advance rather than switch after
seeing scores; retraining on the shorter list is 20 minutes if the owner prefers it.

## 2. How it scores

As it ships: read once (not at several pitch shifts), numbers rounded to 16 bits, confidence calibrated.

| MTG, 1,270 clips | Key shown, percent of songs | Shown keys right | Home note only | Those home notes right | Not sure |
|---|---:|---:|---:|---:|---:|
| **Learned reader** | **73.1** | **69.9** | 9.8 | 68.8 | 17.1 |
| Untrained three-answer reader | 70.4 | 64.8 | 11.7 | 79.2 | 17.9 |
| Apple's framework | 100 | 65.2 | | | |
| Mixed In Key 7 (published, 2017, 1,160 clips of the same collection) | 100 | 65.7 | | | |

| | GiantSteps+, 468: shown | right | GiantSteps Key, 604: shown | right |
|---|---:|---:|---:|---:|
| **Learned reader** | **83.8** | **89.3** | **80.0** | **73.1** |
| Untrained three-answer reader | 76.1 | 85.4 | 73.8 | 69.1 |
| rekordbox 3 / Mixed In Key 7 / KeyFinder (published, 2015; every song given a key) | | | 100 | 71.9 / 67.2 / 45.4 |

| Every song given a key (the bar's measure), MTG | Exact: all | major | minor | Bar as written (36.5 / 70.6) |
|---|---:|---:|---:|---|
| Apple | 65.2 | 41.5 | 75.6 | |
| Learned reader | 60.9 | 59.8 | 61.4 | fails: minor 9.2 short |
| Small model trained on the MTG collection itself (letter X2; cannot ship) | 65.9 | 44.0 | 75.5 | passes |

**Read it this way.** At the owner's measure (keys shown as right as the paid tools, at more coverage) the learned
reader is there: its shown keys are right as often as or more often than those tools' keys, and it shows more than
the untrained reader did. At the bar's measure (every song, both halves) it is not: it is the fairest reader
measured (60 percent on each half), where Apple is right on 76 percent of minor songs and 42 percent of major ones.

**One thing got worse.** Its home-note answers are fewer and less often right than the untrained reader's (9.8
percent of songs at 68.8 percent right, against 11.7 at 79.2). The untrained reader's home note comes from two
methods agreeing; the model's from summing two probabilities. It is the weakest of the three answers now.

## 3. How honest the confidence is

The confidence is the model's own probability, softened by one number (a temperature of 1.35) fitted on 188
human-labelled recordings by artists the model never saw, none of them from the test sets. The thresholds are one
half, from first principles: show a key when it is more likely right than wrong. Nothing was fitted on the test
sets. How the stated confidence compares with the measured rate there:

| Shown at least this sure | MTG: songs shown | keys right | it said | GiantSteps+: shown | right | it said | GiantSteps Key: shown | right | it said |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.5 (as shipped) | 73.1 | 69.9 | 76.2 | 83.8 | 89.3 | 82.1 | 80.0 | 73.1 | 81.5 |
| 0.6 | 59.1 | 73.4 | 81.3 | 72.9 | 93.0 | 86.1 | 69.5 | 75.5 | 85.3 |
| 0.7 | 45.9 | 77.7 | 86.0 | 63.0 | 94.6 | 89.4 | 59.6 | 76.9 | 88.7 |
| 0.8 | 33.7 | 81.3 | 90.0 | 51.9 | 96.3 | 92.3 | 48.0 | 79.0 | 91.9 |
| 0.9 | 16.9 | 87.4 | 94.8 | 35.3 | 97.6 | 95.6 | 31.3 | 81.5 | 95.5 |

- **The order is honest**: a higher confidence is right more often, on every set.
- **The level is 6 to 9 points too sure on two sets and 7 too modest on the third.** MTG and GiantSteps Key have
  one annotator's labels with known errors (GiantSteps+ is the revised set, and there the reader is better than it
  says), so part of the gap is the labels'. Part is real: Beatport clips are not the loops the temperature was
  fitted on.
- **So the number may be shown as a ranking, not as a promise.** "More sure" and "less sure" are sound; "83
  percent" would overstate by several points on dance music. Pair scoring already uses it as a weight (a key at
  0.55 counts for little more than a home note at 0.45), which is the right use.

## 4. What would lift it, and what each lift costs

| Lift | Expected gain | Cost |
|---|---|---|
| **The GiantSteps route** (trained on the MTG clips) | passes the bar as written: 65.9 exact, 75.5 on the minor half | one conversation with the attorney (`x4-key-without-labelling.md`, section 4), then a day |
| Reading at twelve pitch shifts | about 1 point of precision at equal coverage | twelve times the reading time: 6 seconds for a two-minute song |
| A temperature fitted on dance music | closes the 6 to 9 points of overconfidence | needs labelled dance music that is not a test set: none lawful exists today |
| A home note from two methods agreeing (the untrained reader's, when the model declines) | home-note answers back to about 79 percent right | half a day; needs its own measurement |
| More human-labelled dance music under open licences | 1 to 2 points a doubling | none exists to fetch; labelling is off the table |
| Label-free pretraining on all 16,000 open recordings | unknown; did nothing at 8,000 on a CPU | a rented graphics processor, one to two weeks |

## 5. What the Mac window and the iPad app must change

Neither was built here. Nothing breaks if they change nothing: a learned key is an ordinary key block, a home note
is the `key_home` block they already need to handle (the check-in of 07:45 lists those lines).

**Mac window (`desk-app/Desk/Sources`).**
- `TrackTable.swift:24`: the question mark for `key_uncertain` stays right (a learned guess under one half is
  flagged and never reaches a crate file).
- `TrackTable.swift:194`: the key row could add how sure Deckie is when `key.source` is `learned-key`: "8A (A
  minor), fairly sure". Use words in three steps (under 0.6, 0.6 to 0.8, over 0.8), not the percent (section 3).
  New words needed in `Words.swift` beside `keyNotRead` (line 174).
- Acknowledgements: a row for the model when its file ships (`DEPENDENCIES.md`, section 11, has the row).

**iPad app (`deck-app/Deck/Sources`).**
- `CrateLibrary.swift:72` (`keyConf: t.key?.confidence`): the value is now a probability between 0.5 and 1 for
  `learned-key`, where it was 1.0 for `three-answer`. Anything that tests `keyConf == 1` or shows it as a level
  must read it as "at least one half means shown".
- `Mixing.swift:13-14` and `:59`: unchanged by this; the home-note changes of the earlier check-in still apply.
- To read keys on the iPad itself: add `LearnedKey` from the shared core and bundle `deckie-key.f16`; no other
  library is needed. On a Mac or iPad with Apple's framework, D16 keeps Apple's reading first.

## The decision, and what was decided overnight

| Decision | Made by | Evidence |
|---|---|---|
| The learned reader replaces the untrained one where its file is present | me, by the rule fixed before scoring | section 2: more coverage and more precision on all three sets |
| The model is the small convolutional one, not the 49 numbers | me | 5 to 7 points against 1 to 3 at equal coverage |
| Plain Swift, not ONNX Runtime | me | it runs in half a second; the Mac and iPad can share it |
| The lean is 55.2 percent minor, from open electronic music | the rule fixed before scoring | `x4-key-without-labelling.md`, section 3 |
| Thresholds at one half | first principles | section 3 |
| **The model's file is not committed or published** | **left to the owner** | the standing rule "commit no trained weights"; the per-recording credit list names people, and the rule is to name none |

**To turn it on**: publish `deckie-key.f16` (as an asset of the release `models-1`, like the other two models, with
its line in `core/Tools/fetch-models.sh`, or in the repository), add the acknowledgements row, and add the file to
the PC package's `models/` folder. The file and the credit list were handed to the owner in the session; they are
remade by `kt_x4.py cnn mix`, `export mix` and `record mix` (about an hour and a half, the audio fetched again).

## What I could not verify

- **The tools' scores on these exact clips**: Mixed In Key 7's is from 2017 on 1,160 clips of the collection;
  rekordbox 3's from 2015. Today's versions were not run.
- **Apple on the other two sets**: not measured (no Mac in this session).
- **Music that is not dance music**, and whole songs longer than two minutes: every score here is on two-minute
  Beatport clips. A long song is read in two-minute stretches whose answers are averaged; that was tested for
  correctness, not for accuracy.
- **Windows**: the reader's arithmetic is plain Swift and the tests run in `core-windows`; the trained file's
  parity run was on Linux only.
- **The three open points on the training data** in `DEPENDENCIES.md`, section 11 (credit for CC BY 3.0, FMAK's
  "research purposes" sentence, uploaders' public-domain statements), are the attorney's.
