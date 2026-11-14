# Check-in: the own-key work (branches `trial/own-key`, `key/three-answer`, `key/home-note`, `key/shippable`, `key/versus-apple`)

Newest entry first. Scores are percent of clips on the 1,270 GiantSteps-MTG-key clips Apple read (386 major, 884
minor). Exact = key right. Home note = home note right, whatever the mode. Mode given home = of the clips whose home
note is right, the share with the right mode. The bar (D16) = exact within five points of Apple on each half:
36.5 on the major half, 70.6 on the minor half.

## Nov 14, 2026, later. The owner's two questions: is it more accurate than Apple, and why did it miss the bar

**"More accurate than Apple but decides less often?" No: as accurate as Apple where it decides, and it decides
less often.** My earlier line compared its shown keys with Apple over all songs, which flattered it. On the same
songs (1,270 MTG clips, the reader as it ships; detail in `docs/research/x4-key-complete.md`, section 2a, branch
`key/versus-apple`):

| | Songs | Ours right | Apple right, same songs | Is the difference real? |
|---|---:|---:|---:|---|
| Ours shows a key (73 percent of songs) | 928 | 69.9 | 71.2 | no (p = 0.44) |
| Ours declines (ours forced to answer) | 342 | 36.5 | 48.8 | yes, Apple |
| Every song | 1,270 | 60.9 | 65.2 | yes, Apple |
| Major songs, ours shows a key | 298 | 66.1 | 45.6 | yes, ours, by 20 points |
| Minor songs, ours shows a key | 630 | 71.7 | 83.3 | yes, Apple, by 12 points |

Where it declines it would have been wrong two times in three, so declining works; but Apple is right on half of
those songs, and Deckie shows nothing there. It is level with Apple at 60, 70 and 80 percent shown and behind at
90 and 100.

**"Why didn't it meet the bar?"** The bar scores a reader that names a key for every song, and wants it within
five points of Apple on major songs and on minor songs separately. Ours scores 59.8 on major (23 over) and 61.4 on
minor (9.2 under). Both readers find the home note equally often (75.0 and 76.4); the gap is a habit. Lawful
training music is half major, so ours splits its doubt evenly between the modes. Apple answers minor when unsure
(79 percent of its answers are minor; ours 62), which on mostly-minor dance music gets it 75.6 on the minor half
and 41.5 on the major. A lean copied from a published share got ours to within 3.9 on the minor half (at 65
percent) or passed it and broke the major half (at 85); none passed both. To meet the bar honestly the reader
would need dance music as minor as the test to learn from (the GiantSteps route, the attorney's question), or a
count of minor keys from a source that is not the test's own shop (none found), or to hear the mode better on
minor songs (not achieved).

**What could be measured instead.**

| Measure (MTG) | Ours | Apple |
|---|---|---|
| The bar as written: every song, major half and minor half | 59.8 and 61.4 | 41.5 and 75.6 |
| Every song given a key, exact | 60.9 | 65.2 |
| Every song, the mean of the two halves | 60.6 | 58.5 |
| Keys shown, Apple on the same songs | 69.9 | 71.2 |
| Every song, within one step on the wheel | 74.8 | 78.3 |
| Every song, the home note | 75.0 | 76.4 |

**Carry on.** Nothing here changes what ships; it changes how to describe it: "as right as Apple on the songs
where it gives a key, fairer between major and minor, silent on one song in four".

## Nov 14, 2026, 11:05 UTC. A learned key reader that can ship is built and wins; its file is not published (the owner's call)

**Done** (branch `key/shippable`; letters `docs/research/x4-key-complete.md`, short, and
`docs/research/x4-key-without-labelling.md`, the experiments and the page for the attorney).

- **Public labels, second pass.** Every other public source of key labels was opened and its terms quoted. None
  adds a usable recording: no audio, training forbidden, or a program's answers. The public labelled option is the
  1,080 recordings letter X3 already used.
- **Open audio.** 8,352 openly licensed Free Music Archive clips (CC BY, CC0, public domain; 2,730 electronic)
  fetched for evaluation and read by the untrained reader. Nothing committed.
- **Three routes tried**: the untrained reader's confident answers as labels; a model pretrained with no labels on
  pitch-shifted pairs; a minor lean fixed before any test score. The first works as well as human labels (the small model taught on the untrained reader's labels alone, with no
  human label, scores 61.5 exact on MTG, the same as the human-labelled one and 3.7 above its teacher) and adds
  nothing on top of them; the second did not take at this size; the lean came out at 55.2 percent minor, too weak to matter.
- **The reader that can ship.** The small model trained only on lawful recordings, behind the same three answers,
  its confidence its own probability. In the shared core in plain Swift (no ONNX Runtime, no new dependency),
  engine 0.7.0. Parity: a fixture test, and by hand on 270 real recordings (every answer equal, probabilities to
  six decimals; 0.5 s for a two-minute song).

| As it ships | MTG, 1,270: key shown | shown keys right | GiantSteps+: shown | right | GiantSteps Key: shown | right |
|---|---:|---:|---:|---:|---:|---:|
| **Learned reader** | **73.1** | **69.9** | **83.8** | **89.3** | **80.0** | **73.1** |
| Untrained three-answer reader | 70.4 | 64.8 | 76.1 | 85.4 | 73.8 | 69.1 |
| Apple, every song | 100 | 65.2 | | | | |
| Published: Mixed In Key 7 (MTG) / rekordbox 3 (604), every song | 100 | 65.7 | | | 100 | 71.9 |

| Every song given a key, MTG (the bar: 36.5 major, 70.6 minor) | Exact | major | minor | |
|---|---:|---:|---:|---|
| Learned reader | 60.9 | 59.8 | 61.4 | fails, minor 9.2 short |
| Apple | 65.2 | 41.5 | 75.6 | |

**Decisions made overnight, each with its evidence in `x4-key-complete.md`.**
1. The learned reader replaces the untrained one where its file is present: by a rule fixed before scoring, it had
   to be right more often at equal coverage; it is, by 5 to 7 points on all three sets.
2. The small convolutional model, not the 49 learned numbers (which gain 1 to 3).
3. Plain Swift, not ONNX Runtime: fast enough, and the Mac and iPad can share it.
4. Thresholds at one half; the confidence is shown to be honest in order and 6 to 9 points too sure in level on
   two sets, so it should be shown as words, not a percent.
5. **Not decided by me: publishing the model's file.** The standing rule of this work is "commit no trained
   weights" and "name no person" (the credit list CC BY asks for names people). A relayed message cannot lift the
   owner's rule, so the branch carries the reader without its numbers: where `deckie-key.f16` is present the
   learned reader decides; everywhere else the untrained reader does, as in 0.6.0. The file (471,196 bytes,
   SHA-256 2b4fe8fa...) and the list were handed over in the session. `DEPENDENCIES.md`, section 11, is the record
   D15 asks for, marked prepared, not shipped.

**Honest limits.**
- The bar as written is not reached by any lawful route. The GiantSteps route is the only one measured to pass;
  the attorney's page is ready (`x4-key-without-labelling.md`, section 4). Nothing trained on it is in the branch.
- Human labels alone, reader-made labels alone, and both together score the same (61.5, 61.5, 61.7). The candidate
  fixed in advance (both) was kept. A model on reader-made labels alone would have no human-labelled set in its
  record, which removes one of letter X3's open legal points; retraining it is under an hour.
- Home-note answers got worse (68.8 percent right on MTG, from 79.2).

**Tests.** Locally the whole suite passes both with the model file and without it. On `key/shippable` at 035bfcb, which has no
model file: `core-linux` green (run 43586799384), `core-windows` green (43586799411), `desk-window` green
(43586799404).

**Next.** The owner's decision on the file; the attorney's answers. If the file is published: its line in
`core/Tools/fetch-models.sh`, the acknowledgements row, the PC package's `models/` folder.

**Carry on**, with one thing to settle: whether the trained file may be published.

## Nov 14, 2026, 07:45 UTC. The home note is in (D36), branch `key/home-note`

**Done.** A song whose home note Deckie is sure of, and whose mode (major or minor) it is not, now carries that home
note from the reader to the crate, the scoring and the screens. On screen it is "Home note A".

- **Crate format.** `key_home` moved from proposed to decided in `docs/architecture/crate-format.md`: a block of
  `source`, `note`, `pitch_class` and `camelot` (the two wheel codes on that note, minor first). It is written only
  when the song has no `key` block; the validator refuses both together, a note that does not match its pitch class,
  or codes that are not the two on that note. Tests cover writing, reading back with and without it, and each refusal.
- **Older readers, proved by hand.** The reader from `main` as it stood before this change (6b36d55) was built in a
  scratch package and given a crate file carrying `key_home`: "read 2 tracks; problems: []", and the song shows no key.
  An older writer drops the block when it rewrites the file, as the format's rule for unknown blocks says.
- **Engine 0.6.0 and `LocalFacts.decideKey`** write the home note when the answer is the home note alone. The run's
  report counts it (`keys_home_note`) apart from "Deckie not sure" (`keys_not_sure`) and "not read". `deckie-build`
  and `deckie-make` print the counts.
- **A gap found and closed.** `deckie-make` wrote the engine's own record straight into the crate file, so a
  not-sure song went out with a low-confidence key. It now applies the same when-sure rule as `deckie-build`.
- **Scoring rule.** A home-note song is compared as each of the two keys on its note and the better fit is taken
  (two home-note songs: the best of the four pairings). The fit counts at 0.45 of a sure key's weight
  (`PairScoring.homeNoteConfidence`), which makes a home-note match worth 0.725 of a sure-key match. Why: the home
  note is what the reader measurably gets right (72 percent, against 58 for the full key), the true key is one of
  those two, so the better pairing is the most the pair can honestly claim, and the lower weight keeps a claimed fit
  below a known one. Keyed pairs score exactly as before; a song with neither is neutral, as "key not read" was.
  Tests cover each case.
- **Words and Desk.** New, marked as placeholders in `DeskWords`: "Home note {note}", "Deckie is not sure of this
  song's key", and the two finished-screen counts. Desk's song rows carry `keyState` (key, home_note, not_sure,
  not_read) and `homeNote` (`docs/architecture/desk-protocol.md`); the pages in `desk-web/` show them.
- **Mix windows.** A window's key is now judged against what the reader said: one key; the two keys on a home note
  (best fit, flagged only when far from both); or nothing (the window is read, not judged, and never flagged).
  The lab JSON gains `deckie.key.song_key_from` (key, home note or none).

**What moved in the lab-parity tests, and why.** No number moved. The fixture tests call the window function with
the song key given, so they are untouched. The engine test's song-key check now compares with the three-answer
reader's key, which equals the plain method's on the test track. The pinned list of `deckie.key` members gained
`song_key_from`. The bench reads the twelve-note profile members, which did not change.

| Check | Result |
|---|---|
| Full suite here (Linux, with the models) | 528 tests, 0 failing |
| `core-linux` on 842b579 | green, run 43570831569 |
| `core-windows` on 842b579 | green, run 43570831630 |
| `desk-window` on 842b579 | green, run 43570831626 |

**What the Mac window needs (`desk-app/Desk/Sources`; not built here).**
- `Words.swift:94` and `:174`: add `keysNotSure`, `keysHomeNote` (counts), `homeNote`, `homeNoteHelp`,
  `keyDeckieNotSure`, beside `keysNone` and `keyNotRead`.
- `TrackTable.swift:72`: `guard let k = t.key else { return Words.keyNotRead }` should branch on the row's
  `keyState`: home note help, not sure, or not read.
- `TrackTable.swift:195`: `else { row(Words.rowKey, Words.keyNotRead) }` the same three-way branch.
- `ContentView.swift:288`: `keysNone(s.report.keysNotRead)` add lines for `keysHomeNote` and `keysNotSure`.

**What the iPad app needs (`deck-app/Deck/Sources`; not built here).**
- `CrateLibrary.swift:72`: `key: t.key?.camelot` drops the home note; carry `t.keyHome` and set the scoring
  track's `homePitchClass` (the core's `CrateTrack+Scoring` already does this, if that path is used).
- `CrateLibrary.swift:167`: `ka`/`kb` fall back to "?"; use the core's `keyLabel`.
- `Mixing.swift:13-14`: `keyVerdict` returns "key not read" whenever a code does not parse; a home note needs its
  own verdict from the core's pair score.
- `Mixing.swift:59`, `OtherViews.swift:200`, `SuggestionsView.swift:335`: `t.key ?? "?"` should show
  "Home note A" or the not-sure words.

**Next.** The owner's point on training data (no hand labelling; a public labelled option): a second pass, letter
`docs/research/x4-key-without-labelling.md`, on branch `key/without-labelling`. Under way: 8,352 openly licensed
Free Music Archive clips (CC BY, CC0, public domain; 2,745 electronic) fetched for evaluation, the untrained reader
run over them for labels nobody typed and for a minor lean fixed before any test score, and a model pretrained with
no labels at all.

**Carry on.**

## Nov 14, 2026, 04:20 UTC. Piece B done: letter X3, training data that could ship

**The owner's question, answered: yes, a public set can be used, and it gets close to the bar but not over it.**
Letter: `docs/research/x3-key-training-data.md`. Every licence was opened and is quoted there with the date.

**Done.**
- **Found and fetched (evaluation only, nothing committed): about 1,080 real recordings with human key labels whose
  audio and labels both allow a shipped model**: 711 Freesound loops (CC0 or CC BY 3.0; mostly electronic and
  dance) and 373 FMAK songs whose own licence is CC BY, CC0 or public domain. Plus the CC0 Well-Tempered Clavier (48
  recordings) for the classical question.
- **Made**: 1,500 dance clips written by a program of ours to a chosen key, and 412 public-domain chorales played by
  our own synthesiser. Used only as a supplement; nothing was chosen or scored on them.
- **Trained only on what could ship, scored on the three GiantSteps sets**: the 49-number learned profiles on every
  source and mix, and the small model on three mixes.

| Trained on (MTG, 1,270; bar 36.5 major, 70.6 minor) | Reader | Exact: all | major | minor | Home note | Bar as written |
|---|---|---:|---:|---:|---:|---|
| Apple | | 65.2 | 41.5 | 75.6 | 76.4 | |
| The MTG collection itself (letter X2; cannot ship) | small model | 65.9 | 44.0 | 75.5 | 77.0 | passes |
| Nothing (ships now), every song shown | three-answer reader | 57.8 | 54.4 | 59.3 | 72.4 | fails, minor 11.3 short |
| **Real, shippable audio only** | small model | **61.5** | 63.5 | 60.6 | 75.5 | fails, minor 9.9 short |
| the same, leaned to 65 percent minor (a published share) | small model | 62.8 | 53.9 | 66.6 | 75.2 | fails, minor 3.9 short |
| the same, leaned to 85 percent minor (a published share) | small model | 62.8 | 33.4 | 75.7 | 73.9 | fails, major 3.0 short |
| Real, shippable audio only | 49 numbers | 58.8 | 56.0 | 60.1 | 73.4 | fails, minor 10.5 short |
| Real + a quarter program-written music | small model | 60.8 | 58.8 | 61.7 | 74.3 | fails |
| Program-written music only | small model | 48.3 | 50.0 | 47.5 | 67.7 | fails |
| Public-domain classical recordings only | 49 numbers | 48.9 | 54.7 | 46.4 | 62.5 | fails |

**What it says.**
- Shippable real audio teaches the home note as well as Apple reads it, and gives the fairest reader measured so far
  (63.5 percent of major songs and 60.6 of minor ones). It misses the bar on the minor half because the public data
  is half major: it never learns "when in doubt, minor", which is how Apple and the trial's model pass.
- A lean taken from a published count of dance music brings it within 3 to 4 points and does not pass cleanly. At
  the MTG collection's own 70 percent the 49 numbers pass by 0.3 and 1.5 points: fitted to the test set in one
  number, so not a pass I would report.
- **Made-up music: the owner's caution is right.** No gain at any share; within a point up to a quarter of the mix;
  3 points worse at a half; 3 to 13 worse alone. The songs lost are mostly new mode mistakes. Only the one-chord
  case is worth keeping, for about a point. Classical recordings alone are worse than no training.
- Trained generators: their terms forbid it; one paragraph in the letter.

**Recommendation in the letter**: label 400 to 600 free dance tracks ourselves (the audio exists under CC BY and
CC0; 30 to 60 hours of a musician; no music commissioned) and add the 1,080 recordings found; no made-up music; ask
the attorney two narrow questions about the FMAK labels and CC BY before anything trained on them ships.

**Carry on, or stop here: both pieces are complete.** Waiting on the owner: the `key_home` proposal (mode open in
the crate), and whether to start the labelling.

## Nov 14, 2026, 03:10 UTC. Piece A done: the three-answer reader is in the core (branch `key/three-answer`)

From here the entries are on branch `key/three-answer`, cut from `main` after D33. Two pieces: A, the Swift port
(this entry); B, public training data (letter X3, in progress, next entry).

**Done.**
- **The reader is in the shared core**: `core/Sources/DeckieCore/Key/ThreeAnswerKey.swift` (the rule and row A's
  overtone discount) and `NoteChroma.swift` (row B: the note transcription, with its own non-negative least-squares
  solver; no LAPACK). No new dependency, no learned weights, nothing platform-specific.
- **Parity, full**: on all **2,091 recordings** of the three outside sets the Swift reader's answer (key, home note
  with the mode open, or not sure, and which key or note) **equals the Python reference's on 2,091**. Both read the
  same decoded samples (`mixer/keytrial/kt_three.py parity`, piping each clip to `deckie-keyparity`). The
  reference's answers are committed: `mixer/keytrial/three_answer_expected.tsv` (key 1,468, home note only 203, not
  sure 420). The reference itself gives the same answer as the trial's stored readers on all 2,091, although it
  resamples with the core's own filter instead of soxr and keeps double precision.
- **Parity, in the test suite**: `ThreeAnswerKeyTests` makes eight clips in whole-number arithmetic on both sides (no
  audio file) and checks answers exactly and each reading's 24 scores within 1e-5 (measured: 1e-7 and 1e-9).
- **Wired**: the engine (now 0.5.0) writes the reader's answer as the record's key block: `source` `three-answer`,
  confidence 1.0 a key, 0.45 home note with the mode open, 0.2 not sure. `LocalFacts.decideKey`, at its marked
  place, shows a key only: the other two become "key not read" and are counted apart in the run's report. A DJ's own
  key still wins; a record read by Apple's framework is untouched (D17); a reading Deckie was not sure of no longer
  sits beside a DJ's key as a vote.
- **CI**: `core-linux` (run 43548413684) and `core-windows` (run 43548413710) are green on the branch, engine suites
  included; the Windows run's crate matches the Linux one made in the same run. Locally all 432 tests pass with the
  models in place.
- **Cost**: 0.54 s for a two-minute clip in a release build on one core of this machine, the whole reader; about 1.3 s for
  a five-minute song [scaled, not measured on one].

**Stopped on one point, as asked: "home note known, mode open" cannot be written in a crate file today.**
`key.camelot` is required and a Camelot code always names a mode. Proposal, in `docs/architecture/crate-format.md`
("The mode left open"): one optional block beside `key`, `key_home` (`source`, `note`, `pitch_class`, and the two
codes on that note), present only when there is no `key` block, ignored by readers that do not know it. Until the
owner says yes nothing is written: such a song shows no key. The builder's record keeps the reading, so saying yes
later needs no second analysis of anyone's music.

**What the Mac desk and the iPad need** (I cannot build either):
- *Nothing breaks.* A song Deckie is not sure of has no key block, which both apps already show as "key not read".
- *Mac desk* (`desk-app`): its finished screen prints `report.keysNotRead`; the report now also has `keysNotSure`
  and `keysModeOpen`. Words for both are in `DeskWords` (`keysNotSure`, `keysModeOpen`); the Mac's `Words.swift`
  and `ContentView.swift` need the two lines added beside `keysNone`. On a Mac with Apple's framework the key is
  Apple's and none of this shows.
- *iPad* (`deck-app`): no change needed to stay correct. If the mode-open block is accepted: `CrateLibrary` reads
  `key_home`; the song's row shows the note ("A, mode open") where the Camelot code goes; `Mixing.swift` treats the
  song as fitting either of the two codes instead of "key not read".
- *Both*: "key not read on this computer yet" is no longer the right sentence for a song the reader read and was
  not sure of; a second sentence is wanted ("Deckie is not sure of this song's key"). The record's absence of a key
  does not say which it is; the run's report does, per run, and `key_home` would per song.

**One thing I did not change**: the mix windows are still judged against the plain HPCP method's song key, as in
0.4.0, because the lab's bench compares that with its own sheet. Where the three-answer reader names a different
key or none, the windows' key flags are about the old method's key. Small, and worth a decision.

| Set | A key shown | key right | within one wheel step | Home note only | home note right | Not sure |
|---|---:|---:|---:|---:|---:|---:|
| MTG (1,270 Apple read) | 70.4 % | 64.8 | 76.6 | 11.7 % | 79.2 | 17.9 % |
| GiantSteps+ (468) | 76.1 % | 85.4 | 92.1 | 4.7 % | 81.8 | 19.2 % |
| GiantSteps Key (604) | 73.8 % | 69.1 | 82.7 | 5.5 % | 60.6 | 20.7 % |

(The trial's figures; the port gives the same answers clip for clip. With every song shown the reader is exact on
57.8 percent of MTG, 54.4 major and 59.3 minor, against the bar's 36.5 and 70.6: the bar is not met by this reader
with every song shown, as D33 records.)

**Doing next**: piece B. First results are in: a real, shippable base exists (710 Freesound loops under CC0 or CC BY
with agreed human keys, 371 FMAK songs whose own audio licence is CC BY, CC0 or public domain, and the CC0
Well-Tempered Clavier). Forty-nine numbers learned from it score 58.8 on MTG (the untrained reader 57.8; the same
numbers learned from the test collection's own kind of music 62.7; Apple 65.2). Program-written music added to it is
neutral up to a quarter of the mix and harmful from a half. The small model is training on the same mixes now.

**Carry on.**

## Nov 14, 2026, 00:30 UTC. Complete

All four phases are done and pushed. The letter is `docs/research/x2-own-key-trial.md`; the commands are in
`mixer/keytrial/README.md`. The numbers are those of the entry below. One addition since: the trained model with
three answers and no fitted threshold (a key when it is more likely than not, the home note alone when only the home
note is, "not sure" otherwise) shows a key on 70.8 percent of MTG songs and is right on 76.4 percent of them, against
the untrained reader's 70.4 percent shown and 64.8 right.

**Nothing further is running. The owner's calls:** which of the letter's options to take (my recommendation: ship
the untrained three-answer reader, commission the labelled set, and rule that the bar is precision of the keys shown
against Apple on the same songs).

## Nov 14, 2026, 00:25 UTC. Phase 3 done: a trained model of our own equals Apple (evaluation only)

**Done.** The small convolutional model trained on five artist-grouped folds (each clip scored by a model that never
saw it or its artist), once on MTG for the two GiantSteps sets, and once the other way; learned profiles (49
numbers) as the smallest trained reader; precision against coverage, calibration and the four measures for all of
them. Letter `docs/research/x2-own-key-trial.md` is drafted with every table.

**Precision against coverage, MTG, the 1,270 clips Apple read** (key right among the songs shown; "Apple" = Apple
on those same songs):

| Songs shown | Nothing trained (B's home note, A's mode) | Apple | Learned profiles, 49 numbers | Apple | Trained model | Apple |
|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 57.8 | 65.2 | 62.7 | 65.2 | **65.9** | 65.2 |
| 90 % | 60.3 | 67.0 | 65.8 | 67.9 | 70.5 | 68.8 |
| 80 % | 62.9 | 68.3 | 67.3 | 69.2 | **74.5** | 71.6 |
| 70 % | 62.8 | 68.6 | 69.7 | 71.0 | 76.7 | 74.7 |
| 60 % | 65.9 | 71.1 | 72.7 | 73.2 | 79.9 | 77.3 |
| 50 % | 67.7 | 71.2 | 73.1 | 74.2 | 82.4 | 81.3 |
| 40 % | 71.7 | 73.0 | 77.0 | 76.6 | 84.8 | 83.3 |

Outside sets, trained on MTG only (key right / within one wheel step): GiantSteps+ 82.9 / 91.2 with every song shown,
92.2 / 96.5 at 80 percent; GiantSteps Key (604) 68.7 / 81.8 and 74.9 / 86.7. Published on the 604: rekordbox 3 71.9,
the madmom network 67.9, Mixed In Key 7 67.2, KeyFinder 45.4.

| Reader (MTG, 1,270) | Exact: all | major | minor | Home note: all | major | minor | Mode given home: major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 |
| The bar as written | | 36.5 | 70.6 | | | | | |
| Nothing trained: B's home note + A's mode | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 70.5 | 84.2 |
| Learned profiles, 49 numbers (evaluation only) | 62.7 | 35.8 | 74.4 | 74.5 | 71.0 | 76.0 | 50.4 | 97.9 |
| the same, major and minor weighed equally | 59.8 | 56.5 | 61.2 | 73.6 | 76.9 | 72.2 | 73.4 | 84.8 |
| **Trained model, 12 shifts averaged (evaluation only)** | **65.9** | **44.0** | **75.5** | 77.0 | 75.4 | 77.7 | 58.4 | 97.1 |
| Trained model, single read | 63.9 | 42.0 | 73.5 | 74.6 | 72.3 | 75.7 | 58.1 | 97.2 |

**What it says.**
- **The bar as written is passed** by the trained model on artists it never saw (major 44.0 against 36.5, minor
  75.5 against 70.6). Song for song it is level with Apple (ahead on 104 clips, behind on 95, p 0.57). Per fold:
  67.8, 63.1, 64.3, 67.5, 65.5; one training run each, so read it as 65.9 give or take 3.
- **When it may decline it is ahead of Apple on the same songs**: 74.5 against 71.6 at 80 percent shown (p 0.01).
  Its confidence can be trusted: stated probability and observed accuracy differ by 3 points on average; when it
  says 90 percent or more it is right 94 percent of the time.
- **It is small and cheap**: 236,006 numbers, 0.95 MB, 0.05 s a five-minute song on one CPU thread plus 0.35 s for
  its spectrogram.
- **It wins the way Apple wins**: a better home note than ours (77.0 against 72.4) and a lean toward minor (58
  percent of major songs' modes right, 97 of minor). It hears the mode no better than the 80 percent ceiling of
  phase 2. Trained on the 85-percent-minor 604-clip set instead, it reads 3.9 percent of MTG's major songs right:
  the lean is copied from the training music. With major and minor weighed equally the 49-number profiles score
  59.8 and fail the bar as written by 14 points on the minor half while reading 56 percent of major songs right
  instead of 36.
- **Forty-nine learned numbers get most of the way** (62.7; level with Apple song for song at every share shown) and
  stop improving at about 400 labelled songs.
- **None of it can ship**: trained on CC BY-SA labels and audio that is not ours.

**Doing next.** Phase 4 is written into the letter (the Swift port of the untrained three-answer reader: 5 to 6
days; the data that could legally back weights; what a commissioned set needs: 400 to 600 songs to fit, 300 to
score, mixed styles, a third in major keys). Final read-through, then the branch is complete.

**Carry on; one ruling would help.** The direction holds and the result is better than letter T's estimate. The
ruling: D16's bar as written rewards leaning minor (it is how Apple and the trained readers pass it). If the bar
stays as written, a trained reader should keep the lean; if it becomes "of the keys shown, as many right as Apple
on the same songs" (my recommendation), the reader can be fitted without the lean and judged on what it shows.

## Nov 13, 2026, 22:45 UTC. Owner's direction taken up: precision against coverage, untrained readers first

**Direction received** (relayed by the main session): the reader must stand on its own, work as well as the tools DJs
use or better, and fail gracefully: show a key when it is reliable, skip it when not. So the main measure from here
is **precision against coverage**: of the songs that get a key, how many are right, and what share of songs get one.
"Mode open" and "not sure" are both allowed answers. A method with no learned weights is preferred when two are close.

**First precision-against-coverage table.** The best reader with nothing trained: home note from row B, mode from
row A, clips ordered by a confidence that fits nothing (how many of the three readers name the same key, plus how
many thirds of the song name it, 0 to 6; ties by margin). MTG = the 1,270 clips Apple read; GiantSteps+ = 468
single-key clips our profiles were not made from; GiantSteps Key = the 604 clips with published tool scores.

| Songs shown a key | MTG: key right | within one wheel step | home note right | Apple right on the same songs | GiantSteps+: key right | within one step | GiantSteps Key: key right | within one step |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 % | 57.8 | 71.7 | 72.4 | 65.2 | 76.9 | 86.5 | 60.9 | 76.8 |
| 90 % | 60.3 | 73.8 | 74.1 | 67.0 | 81.5 | 90.3 | 64.0 | 79.0 |
| 80 % | 62.9 | 75.9 | 77.3 | 68.3 | 84.5 | 92.2 | 67.3 | 81.0 |
| 70 % | 62.8 | 77.1 | 75.7 | 68.6 | 87.8 | 95.4 | 69.5 | 83.5 |
| 60 % | 65.9 | 78.2 | 79.4 | 71.1 | 89.3 | 97.2 | 72.4 | 86.7 |
| 50 % | 67.7 | 81.3 | 77.8 | 71.2 | 93.2 | 99.1 | 74.8 | 87.4 |
| 40 % | 71.7 | 81.1 | 82.9 | 73.0 | 93.0 | 99.5 | 76.4 | 88.0 |
| 30 % | 75.3 | 85.3 | 82.7 | 77.4 | 92.9 | 99.3 | 76.2 | 89.5 |

Against the tools (published exact rates; letter X):
- **MTG.** Shown keys are as right as Apple's overall rate (65.2) and Mixed In Key 7's (65.7, Faraldo 2017, near the
  same clips) when **60 percent** of songs are shown, and clearly better (whole 95 percent interval above) at 40
  percent. But Apple is also better on those same songs (71.1 at 60 percent), so on this set the untrained reader is
  never ahead of Apple song for song; on the held-out folds alone it is level with Apple from 80 percent down.
  KeyFinder (54.8) is matched with every song shown.
- **GiantSteps Key (604).** As right as Mixed In Key 7 (67.2) at **80 percent** shown, as right as rekordbox 3 (71.9)
  at **60 percent**; KeyFinder (45.4) is beaten with every song shown.
- **GiantSteps+**, the clean set: 76.9 with every song shown, 84.5 at 80 percent, 93 at 50 percent. No tool has a
  verified published score on it, and Apple cannot be run on it from this session.

**Is the confidence trustworthy?** Yes, in order: every signal sorts right from wrong on all three sets, and the
selection and held-out folds give the same shape. On MTG, a key that all three readers and all three sections agree
on (38 percent of songs) is right 72 percent of the time; with 3 of 6 or fewer, 43 percent or less. On GiantSteps+
the top level (50 percent of songs) is right 93 percent of the time. The margin alone is the weakest signal and says
nothing about the home note (letter T saw the same).

**Three answers, no threshold at all** (a key when rows A and B agree on home note and mode; "home note, mode open"
when they agree on the home note only; "not sure" otherwise):

| Set | A key: share, right | Mode open: share, home note right | Not sure: share |
|---|---|---|---|
| MTG | 70.4 %, 64.8 (within one step 76.6) | 11.7 %, 79.2 | 17.9 % |
| GiantSteps+ | 76.1 %, 85.4 (within one step 92.1) | 4.7 %, 81.8 | 19.2 % |
| GiantSteps Key | 73.8 %, 69.1 (within one step 82.7) | 5.5 %, 60.6 | 20.7 % |

**Other results since the last entry** (all in `mixer/keytrial/`, scripts `kt_x.py`, `kt_pc.py`):
- **Trade-off curve** (letter X ask 1): with row B's home note, moving the mode threshold from "always major" to
  "always minor" never passes the bar as written; the minor half tops out at 70.4. At the balanced point both halves
  are 58.
- **The published multi-profile method** (ask 2; second minor template, gate, 200 Hz cut): its second minor template
  is what matters. On our chroma without the 200 Hz cut it scores 56.2 exact on MTG (the set its profiles came from)
  and 74.4 on GiantSteps+; with the cut it falls to 45.9 and 63.0 (my stand-in for the filter drops the bass peaks
  outright; the published filter is gentler, so this part is not a faithful replication). Its steps on row B's
  chroma: 59.3 and 77.1. It buys minor songs by leaning minor (major half 42 on MTG), like the trained mode rule.
- **GiantSteps+ is much kinder than MTG to every reader** (row B 75.9 exact against 55.6): the MTG scores are not
  flattered by the profiles' origin; MTG is simply the harder, less minor set (70 percent minor against 88).
- **Letter X's arithmetic re-derived from the per-clip results**: its mode-right table matches to the point (3f
  86.3 / 61.1, A 72.2 / 84.6, B 81.9 / 74.3, Apple 58.6 / 95.8); its minor-gap split matches (A: 19.2 short, of which
  parallel 7.0, relative 4.8, fifth 2.3, other 5.2; B: 23.3, of which 14.8, 4.3, minus 1.0, 5.2); "within one step"
  on all 1,270 is Apple 78.3, A 72.0, B 69.0 (letter X's 81 for Apple was the confident clips only); B's home note
  with A's mode measures 57.8, inside its 57 to 59 estimate.

| Reader (MTG, 1,270) | Exact: all | major | minor | Home note: all | major | minor | Mode given home: major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 58.6 | 95.8 |
| The bar as written | | 36.5 | 70.6 | | | | | |
| B's home note + A's mode (nothing trained) | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 70.5 | 84.2 |
| Multi-profile steps on row B's chroma (nothing trained) | 59.3 | 41.7 | 67.0 | 72.3 | 77.2 | 70.1 | 54.0 | 95.5 |
| B's home note + trained 12-number mode rule (evaluation only) | 60.2 | 46.9 | 66.0 | 72.4 | 77.2 | 70.4 | 60.7 | 93.7 |

**Doing next.** The trained model (phase 3) is mid-training: the first of five folds is at epoch 108 of 120, with 64 percent exact
on its validation artists at best; the cross-set model (train on MTG, score both GiantSteps sets) runs beside it. About two
hours of CPU remain. When it lands: the same precision-against-coverage tables for it, its calibration, agreement
with the untrained readers as a confidence, then phase 4 and the letter.

**Carry on.** For the owner, in one line: with nothing trained, Deckie can today show a key on about 60 to 70 percent
of dance songs at the accuracy of Mixed In Key 7 and Apple's overall rate, and say "not sure" on the rest; whether
that share can rise depends on the trained model's result.

## Nov 13, 2026, 22:33 UTC. Phase 1 done; phase 2 first pass; phase 3 training

**Done.**
- Bench built in `mixer/keytrial/`. Fetched for evaluation only, nothing committed: GiantSteps-MTG-key (Zenodo
  1101082, 1,486 clips, 2.13 GB, labels CC BY-SA 4.0), GiantSteps+ (Zenodo 1095691, 600 clips, 856 MB, labels CC
  BY-SA 4.0), GiantSteps Key (604 clips, 834 MB from the JKU mirror, all checksums matched, no licence stated).
- Letter R's three readers (3f, A, B) re-run from my own decode: **the same key as letter R's sheets on 1,275 of
  1,275 clips, all three**, and every figure in its tables to the decimal. The bench can be trusted.
- Protocol fixed: five folds grouped by artist and remixer (1,269 groups on MTG); folds 3 and 4 are the held-out
  part for any choice between untrained rules; trained rules are scored only on the fold they never saw.
- Phase 2 first pass: 46 mode rules scored with the true home note given, and with row B's and row A's.
- Letter X read and merged (see "Next").

| Reader | Exact: all | major | minor | Home note: all | major | minor | Mode given home: all | major | minor |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | 76.4 | 70.7 | 78.8 | 85.4 | 58.6 | 95.8 |
| **The bar** | | **36.5** | **70.6** | | | | | | |
| 3f | 47.6 | 60.6 | 41.9 | 69.1 | 70.2 | 68.6 | 68.9 | 86.3 | 61.1 |
| A (harmonic discount) | 55.6 | 53.9 | 56.3 | 69.1 | 74.6 | 66.6 | 80.5 | 72.2 | 84.6 |
| B (note transcription) | 55.6 | 63.2 | 52.3 | 72.4 | 77.2 | 70.4 | 76.7 | 81.9 | 74.3 |
| B's home note + A's mode (letter X's first ask) | 57.8 | 54.4 | 59.3 | 72.4 | 77.2 | 70.4 | 79.8 | 70.5 | 84.2 |
| B's home note + a 12-number trained mode rule (leans minor) | 60.2 | 46.9 | 66.0 | 72.4 | 77.2 | 70.4 | 83.1 | 60.7 | 93.7 |
| B's home note + a perfect mode (the limit) | 72.4 | 77.2 | 70.4 | 72.4 | 77.2 | 70.4 | 100 | 100 | 100 |

**What the numbers say so far.**
- **The mode alone cannot meet the bar as written.** Even a perfect mode on row B's home note gives 70.4 on the
  minor half, against a bar of 70.6. Our home note on minor songs (66.6 to 70.4) is below Apple's (78.8). The home
  note is "mostly found" three times in four, and that is not enough for this bar.
- **With the true home note given, nothing I tried names the mode better than about 80 percent when major and minor
  count equally.** The plain profile match on the overtone-cleaned chroma already sits there (rows A and B: 79.0 and
  78.6). Reading the third, sixth and seventh from the bass line alone (64 to 68), from the melody register alone (74
  to 78), only where the harmony is stable (72 to 77), from the chord on the home note over time (69), or only above
  the home note in the bass (69 to 75) are all **worse**. Small trained rules reach 78 to 80: no better at hearing
  the mode, they only choose where to lean (61 major / 95 minor at their natural setting).
- Apple by the same measure: 77 (58.6 major / 95.8 minor). So on the mode alone our readers are level with Apple;
  Apple's minor-half lead is its lean plus a better home note. This confirms letter X's arithmetic from the per-clip
  results.

**Next, in this order.**
1. Phase 3 is already training (five artist-grouped folds, CPU only, about 20 minutes a fold): it is the only thing
   on the table that can move the home note. First fold's validation exact is 60.7 at a third of the way.
2. Letter X's asks, taken up in this order: (i) B's home note with A's mode (done, row above: +2.0 exact, held-out
   gained 31 lost 17, p 0.06) and the major-against-minor trade-off curve; (ii) the mode asked only where the bass
   sits on the home note (done: worse, 69 to 75 balanced); (iii) an open mode, as coverage against precision;
   (iv) every result on four measures side by side (exact per half, mean of the halves, within one wheel step,
   precision of shown keys when abstaining); (v) scoring on GiantSteps+ (fetched; Apple cannot be run on it from
   here, so the bar itself stays on MTG); (vi) Faraldo's full multi-profile method, if its minor2 and amodal
   numbers can be read.
3. Phase 4 and the letter.

**Carry on.** One thing for the owner to know now: under the bar as written, "settle the mode alone" cannot pass,
whatever the mode rule. Passing needs a better home note on minor songs (the trained model's job) or a ruling on
what the bar measures (letter X, option 3).
