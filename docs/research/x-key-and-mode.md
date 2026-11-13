# Research X: the mode, key from a name, and how much key matters

Dated Nov 13, 2026. Web research and reading only: no experiment was run, nothing was fetched into the project, no
decision is made here. Builds on letter R (every key test so far) and letter T (the options and their costs), on
letter B (lookups by name, already surveyed for naming songs), and on D5, D15, D16, D17 and D29. Where this letter
confirms, extends or contradicts R and T it says so. Tags: [2nd] = read in a paper or page, not tested here; [snip] =
seen only as a search result's summary, the page itself would not open; [inf] = my inference, with the reasoning;
[calc] = arithmetic on letter R's published tables, no new measurement. Sources are numbered S1 to S48 at the end. Not
legal advice.

## In plain words

A song's **key** has two parts. The **home note** is the note the music keeps coming back to and feels finished on
(the letter in "A minor"). The **mode** is the flavour of the scale built on that note: **major** sounds bright,
**minor** sounds dark. DJs write keys as **Camelot codes**, a number from 1 to 12 and a letter: A for minor, B for
major. Two songs whose codes are the same, or one step apart on the wheel, share nearly all their notes and usually
blend without clashing. When this letter gives a number followed by A or B it is a key, never a tempo or a fader
position.

Four kinds of wrong key come up all through this letter. A **relative** error names the key with the same notes and
the other mode (A minor read as C major: same Camelot number, other letter; harmless in a mix). A **fifth** error
names the neighbour key (one step on the wheel; usually still mixes). A **parallel** error has the right home note and
the wrong mode (A minor read as A major: three steps away on the wheel, and three of the seven notes differ). Anything
else is plainly wrong. The owner's question is about the parallel error.

What this letter found, in five lines:

1. **The mode.** The owner's instinct is right that the mode can be treated as its own step, and two published
   methods do it. But letter R's own tables, read again, show something the earlier letters did not say: once the
   home note is right, Deckie's reader already names the mode about as well as Apple's when major and minor songs
   count equally (78 percent against 77). Apple wins on dance music because it leans toward minor, and most dance
   music is minor. So the gap is partly a lean, not only skill. The best new ideas are to let a song's mode be
   "open" when the music does not say, and to stop asking one number to carry both questions.
2. **The state of the art.** The best published readers get 68 to 72 percent of dance clips exactly right. All are
   trained models, and none of the published ones can ship in a paid app. Letter T's conclusion stands.
3. **Other DJ tools.** In the largest community test the tools scored 43 to 77 percent, Mixed In Key first. On the
   very clips Deckie is tested on, Mixed In Key 7 scored 65.7 percent in 2017: the same class as Apple's 65.2. DJs
   know keys are sometimes wrong, check by ear, and care most that one tool is used for the whole library.
4. **Key from a song's name.** It can be done, but the keys in those databases are themselves machine readings, often
   worse than Deckie's own (the store most DJs would trust was right on 61 to 66 percent of tracks in two listening
   tests; the best-known streaming source scored far lower). They miss edits and bootlegs, the terms mostly forbid
   or charge for it, and it sends the names of a DJ's songs to a company. The lookup that does work sends nothing:
   reading the keys a DJ's own software has already written on the same computer.
5. **How much it matters.** Key is a help, not a rule, for most DJs. A measurement of real DJ sets found only one
   track in forty was shifted to another key. A relative or fifth error costs nothing in a mix; a parallel error
   can cost a blend. The problem deserves a steady, modest effort, and reaching the class of Apple and Mixed In Key
   is enough: past that point trained listeners stop agreeing with each other.

## 1. The mode on its own

### 1.1 What letter R's tables already say about the mode [calc]

Letter R reports, for each reader, the exact rate and the home-note rate on the major and minor halves of the 1,270
clips. Dividing one by the other gives **how often the mode is right once the home note is right**, a number neither
letter drew out:

| Reader | Major songs: mode right | Minor songs: mode right | Mean of the two | Weighted as the set is (70 percent minor) |
|---|---|---|---|---|
| 3f (letter R's first reader) | 86 (60.6 of 70.2) | 61 (41.9 of 68.6) | 74 | 69 |
| A, harmonic discount | 72 (53.9 of 74.6) | 85 (56.3 of 66.6) | 78 | 81 |
| B, note transcription | 82 (63.2 of 77.2) | 74 (52.3 of 70.4) | 78 | 76 |
| Apple | 59 (41.5 of 70.7) | 96 (75.6 of 78.8) | 77 | 85 |

Three things follow.

- **With the two modes weighed equally, rows A and B are level with Apple** (78 against 77). Apple is not better at
  hearing the mode; it answers "minor" far more often (letter R: on 1,003 of 1,270 clips where the truth is 884), is
  nearly always right on minor songs and wrong on four major songs in ten. Letter T guessed that Apple "behaves as
  if it carries a minor prior". This table is the evidence.
- **D16's bar, as written, rewards that lean.** It compares the minor half with Apple's minor half, where Apple's
  lean pays, and the major half with Apple's major half, where Apple is weak and any reader passes. A reader that
  leaned as Apple does would pass without hearing the mode any better. That is a fact about the measure, for the
  owner; it is taken up in the options.
- **The "23 points short on minor" is not all mode.** On the minor half, row A trails Apple by 19.3 points: 7.0 of
  them are parallel errors, 4.8 relative, 2.3 fifth and 5.2 unrelated keys. For row B the 23.3 points are 14.8
  parallel, 4.3 relative, 5.2 unrelated, and B is 1.0 ahead on fifths. So with row A, about a third of the minor gap
  is the mode and the rest is the home note; with row B it is the other way round. Neither row has both.

### 1.2 What the published work on dance music says

**Faraldo, Jordà and Herrera 2017** [S1, read in full] is the closest thing to the owner's question in print, and
letter R could not open it. It confirms and extends the earlier letters:

- **Cause, confirmed.** The authors saw that many minor tracks carry as much energy on the major third as on the
  minor third, and blame the fifth overtone of the home note in bright synthesised sounds. This is the hypothesis
  letter R tested and found true (rows A and B).
- **A second minor template.** Their fix is a third profile, "minor2", made from minor tracks that were read with
  the right home note and the wrong mode; it has more energy on the major third than on the minor third, against
  music theory. The reader then chooses among major, minor and minor2. It is the same cure as letter R's row A by
  another road: A removes the overtone from the song, minor2 puts the overtone into the template.
- **An "amodal" class.** A fourth profile has all its energy on the home note, for tracks with a clear home note
  and no mode at all (a bass line, a drone, one note and drums). Because every test set forces major or minor, they
  report these as minor. Faraldo's thesis argues for open labels instead [S2, abstract only].
- **Two small steps letter R has not tried as published**: zeroing the weak bins of the song's own twelve-note
  profile (a "gate" at 0.2 after scaling to 1), and a high-pass filter at 200 Hz. Their figure 5 shows each step
  adding a little on the 604-clip set. Letter R found the 200 Hz filter hurt on the lab's crate, so this is a
  disagreement between two sets, not a settled matter.
- **The profiles came from the test set.** braw and bgate were made from 600 tracks of the same 1,500-clip Beatport
  collection that became GiantSteps-MTG-key, the set Deckie is scored on [S1 section 4; the collection matches the
  Zenodo record by size, source and annotator, so I take it as the same in an earlier revision, inf]. Letter R
  flagged this as likely; it is now confirmed. Every row of ours that uses those profiles is partly scored on its
  own source. **GiantSteps+ (600 clips) is the clean test**, as letter T said.

**Their results on our set** (their "Beatport" column: 1,160 clips their two annotators were confident held one
key; ours is 1,120 clips at confidence 2 after later revisions, so near but not identical [inf]):

| Reader (percent of clips) | Exact | Fifth | Relative | Parallel | Other | Label within one wheel step (exact + relative + fifth) |
|---|---|---|---|---|---|---|
| Mixed In Key 7 [S1 table 2] | 65.7 | 10.0 | 6.1 | 11.8 | 6.4 | 81.8 |
| Faraldo's multi-profile method [S1] | 63.7 | 10.7 | 5.1 | 14.1 | 6.4 | 79.5 |
| KeyFinder [S1] | 54.8 | 15.5 | 6.0 | 15.0 | 8.7 | 76.3 |
| Faraldo's edma, two profiles [S1 table 1] | 51.7 | 11.6 | 5.8 | 21.9 | 9.0 | 69.1 |
| Essentia's default extractor [S1] | 27.1 | 28.5 | 5.3 | 11.9 | 27.3 | 60.9 |
| Apple, confidence 2 (letter R) | 68.8 | 7.1 | 5.1 | 11.5 | 7.5 | 81.0 |
| Ours 3f, confidence 2 (letter R) | 50.1 | 9.7 | 5.6 | 22.1 | 12.5 | 65.4 |
| Ours A, all 1,270 (letter R) | 55.6 | 10.6 | 5.8 | 13.5 | 14.5 | 72.0 |
| Ours B, all 1,270 (letter R) | 55.6 | 8.1 | 5.3 | 16.9 | 14.2 | 69.0 |

What this adds to letter T, which had commercial scores only on the other, 604-clip set:

- **Apple is in Mixed In Key 7's class on this music** (68.8 against 65.7 exact; 11.5 against 11.8 parallel). D16's
  bar is, in effect, "as good as the tool DJs pay for".
- **Our 3f is Faraldo's edma, as it should be** (50.1 against 51.7, parallel 22.1 against 21.9). That is a check
  that Deckie's port of the method is faithful.
- **On parallel errors, row A (13.5) is already beside KeyFinder (15.0) and Faraldo's best (14.1), and two points
  from Mixed In Key (11.8).** Where ours is weak against all of them is the last column but one: "other", plainly
  wrong keys. On the confident clips 3f has 12.5 percent against their 6 to 9, and over all clips rows A and B have
  not moved it (15.0 for 3f, 14.5, 14.2; letter R does not break A and B out by confidence). Faraldo's full method
  gets from edma's 9.0 to 6.4 with the gate and the extra profiles. So a good part of what is left is not the mode.
- **The full published method reaches 63.7** on this set, 12 points over its own two-profile start, with nothing
  trained. That figure is partly test-on-train (above); on the 604-clip set, which the profiles never saw, the same
  step is 58.1 to 64.1 exact, three points under Mixed In Key 7 [S1 table 1].

### 1.3 Every approach found, with its evidence

| Approach | What it is | Evidence, and on what music | Gain reported | Cost for Deckie |
|---|---|---|---|---|
| Overtones out of the song (letter R rows A, B) | subtract the share of each note that is another note's overtone | letter R, 1,275 dance clips, held out | parallel errors 21.4 to 13.5 (A), 16.9 (B) percent of clips | done in the lab; A is a few multiplications a frame |
| A second minor template (minor2) | a minor profile with a strong major third | S1, three dance sets | with the other steps: parallel 10.6 to 5.1 (604 set), 21.9 to 14.1 (our set, test-on-train) | hours, if the values can be had (below) |
| An "amodal" or open class | a profile with only the home note; mode left open | S1, S2 abstract; a 2017 talk by the same authors calls some sparse tracks amodal [S3, site down, snip] | not reported alone | hours in the lab; a product question (section 1.4) |
| Gate on the song's own profile | zero the bins under 0.2 | S1 figure 5, 604 set | small, mixed alone; best with the high-pass | an hour |
| A mode lean (prior) | shift the decision toward minor or major | Bernardes and Davies 2017 build a tunable "mode bias" into a key finder and say it is effective, best set per style [S14, page read; the paper's numbers not opened]; edmm, which answers minor always, tops the 85-percent-minor sets and falls behind on our balanced one [S1]; a third published share: 65 percent minor in one Beatport top 100 of 2023 [S45] | moves errors between halves; no gain in skill | an hour; a fitted value under D5 unless published (letter T section 4) |
| Trained network | learns the 24 keys from labelled clips | letter T; newest: KeyMyna parallel 5.3, exact 72.0 on the 604 set [S5] | parallel 4 to 5 percent on an 85-percent-minor set | letter T option 4 and 5: days, and training data |
| Learning the mode without labels (S-KEY) | a network trained on unlabelled songs; the mode comes from a rule comparing the predicted root with the note a minor third below | S6: 60k to 1M streaming songs; tested on 5,489 mixed-genre songs | mode right 62 to 79 percent, equal to the supervised network (79.3); a plain Krumhansl match gets 65 | not open to us: needs a large catalogue (D3 rules out DJs' libraries); weights non-commercial |
| Few labels on top of unlabelled training (Semi-TONE) | the same family; labels added | S7: equals full supervision with a tenth of the labels (about 116 songs) | says a small listening set can go far once a model has heard enough unlabelled music | as above |
| Mode as a scale, not a switch | major-ness as the difference between the best major and best minor match | Eerola and Schutz 2025: tracks expert ratings on classical preludes [S15, abstract] | none for accuracy; supports showing how sure the mode is | none: Deckie stores the margin already |
| Chords, then key | name chords per bar, infer the key from their order | letter T section 2; Wu and Yoshii 2022 report joint chord and key training helps both, on pop [S18, abstract]; Mauch and Dixon track key, chord and bass note together from separate bass and treble profiles, on pop [S20] | no figure on dance music found | letter T option 6: 4 to 6 days |
| Bass for the home note | read the lowest part alone | letter R: bass alone 40.5 percent, and every bass-range row worse; S1 high-passes the bass out | negative as the only evidence | none; see the conditional idea below |
| Percussion separated first | split drums from harmony before counting notes | listed as standard in older pipelines [S8]; no figure for key on dance music found | unknown | letter T option 7: a day |
| Separated stems | a trained separator gives bass, vocals, other; read each | one 2025 chord system does this for chords, not key [S21]; no key result found | unknown | blocked: every separator letter O found is trained on non-commercial data |
| Tuning correction | find how far the song sits from concert pitch | letter R (no gain), Sha'ath (no gain); S1 keeps a simple one | none | none |
| Sections and windows | read the key per stretch and vote | letter R rows 4c, 4d (no gain); longer excerpts help a trained network (letter T) | none so far | none |
| A trained note transcriber in front | a small open model turns audio into notes; the key is read from notes, where overtones no longer exist | Jointist: key accuracy 72.8 to 75.2 on pop when transcribed notes are added to audio [S19, snip]; Spotify's Basic Pitch is Apache 2.0 code with ONNX weights [S12; the weights' own licence and training sets are not stated on the page] | plus 2 to 3 points on pop [snip]; on dance music unknown | 3 to 5 days in the lab; the trained cousin of row B |

Ideas from outside the key literature, or my own, none tested [inf throughout]:

- **Ask the mode only where the song stands on its home note.** Letter R's rules compared the two thirds over the
  whole clip and failed. A sharper question: in the frames where the lowest note is the home note, is the chord
  above it minor or major? That uses the bass as a condition, not as evidence, which no test so far has done. It
  needs row B's transcription (to tell a played third from an overtone) and the low band per frame. A day or two.
- **B's home note with A's mode.** Section 1.1 shows the two rows are each good at one half of the job. Take the
  home note from B, then decide the mode on that note alone with A's overtone-discounted profile. If the two skills
  simply combine, exact would be near B's home-note rate times A's mode rate, about 57 to 59 percent against 55.6
  now [calc, assuming independence, which is optimistic]. Hours, from the caches the lab already holds.
- **Where the singer is.** A sung melody states the third plainly, and a voice's overtones are weaker than a
  synthesiser's. Deckie already knows which bars are sung. Weigh the mode evidence toward sung bars, or read the
  mode there alone. Unknown gain; the outside set has no vocal marks, so the engine's own tagger would supply them.
  Letter R's weighting tests (loudness, beats, the middle of the track) all failed, which is a caution.
- **Versions of one song should agree.** An ISMIR 2025 paper scores key readers by whether they give the same
  answer for different versions of one piece, with no labels needed [S22, poster page]. A DJ's crate holds many
  songs in several versions (D19, D24). Where an edit and its original disagree on the mode, flag both; where they
  agree, trust rises. It costs nothing to compute once versions are grouped, and it is library-blind in the sense
  of D5: it fits nothing, it only compares.
- **Do not name the key at all for ranking.** Two research lines mix by how the two songs' notes fit, not by key
  names. Gebhardt, Davies and Seeber score the roughness of the two songs' partials together and report that
  listeners preferred their choices to a commercial DJ program's [S16: abstract and summary; the full text would
  not open, so the size of the test is unverified]. Bernardes, Davies and Guedes combine key, note-profile
  similarity and dissonance in one score [S17, citation only]. For Deckie this would mean the booth ranks the next
  song from the two twelve-note profiles, shifted by what the pitch fader does, and shows a Camelot code only when
  the reading is sure. It sidesteps the mode: two songs with the same notes fit whatever the label says. It is a
  change to what D16 gates (a profile is not a key), so it is the owner's call and a research step first.

### 1.4 The mode can be left open

The plainest "creative way" in the literature is to stop forcing an answer. Three sources point the same way:
Faraldo's amodal class [S1, S2], the mode-as-a-scale work [S15], and letter T's finding that the reader's sure flag
measures confidence in the mode, not in the home note. Under D16 a wrong key is worse than none; a home note with an
open mode is neither wrong nor nothing. Musically it is also true: a track with no third fits songs in either mode
on that home note. What a DJ would see is a product question: the two codes side by side ("8A or 11B"), or the
home note alone ("A, mode open"). Camelot has no code for it, which DJs already remark on for modal tracks [S29].

## 2. The state of the art

All on the 604-clip GiantSteps Key set unless named. Weighted is the MIREX score. This extends letter T's table; it
does not replace it.

| Reader | Kind | Exact | Weighted | Parallel | Code and weights | Trained on | Could back shipped weights? |
|---|---|---|---|---|---|---|---|
| KeyMyna 2026 [S5] | 22M-parameter encoder trained without labels, small head with labels | 72.0 | 75.9 | 5.3 | code and two heads on GitHub, no licence stated; the encoder is separate | encoder: a large unlabelled set, not named; head: MTG-key | no: no licence, data unknown |
| InceptionKeyNet 2021 (letter T) | network, 1.7M | | 75.7 | | MIT code, no weights | MTG-key, Billboard | train our own |
| madmom AllConv 2018 (letter T) | network, about 0.5M | 67.9 | 74.6 | 4.1 | weights CC BY-NC-SA | MTG-key, Billboard, classical | no |
| MERT-95M with a linear head [S5 table 1] | general music model | 67.7 | 73.0 | 4.8 | weights CC BY-NC 4.0 [S9] | 20,000 hours, unnamed | no |
| S-KEY 2025 [S6] | no labels | | 72.1 | | code MIT, weights research-only (letter T) | 1M streaming songs | no |
| Mixed In Key 7 [S1] | commercial | 67.2 | 74.2 | 5.3 | closed | | |
| Faraldo multi-profile 2017 [S1] | templates, nothing trained | 64.1 | 72.5 | 5.1 | scripts on GitHub, no licence stated [S46] | profiles from 600 Beatport tracks | the method is a paper; the profile numbers are facts taken from one |
| KeyFinder [S1, S5] | templates | 45.4 to 60.4 | 59.3 to 69.9 | 5.6 to 7.8 | GPL | | no (GPL) |

- **General music models are weak at key.** The makers of MusicFM say such models score low on key as a rule
  [S11]; MuQ's released weights are CC BY-NC [S10]. A general model is not a shortcut.
- **Mixed-genre music is harder for the mode than the 604 set suggests.** On 5,489 songs of 17 genres the supervised
  network names the mode right 79.3 percent of the time [S6]. On the 604 set a reader that always says minor is
  right 85 percent of the time, so its low parallel figures flatter everyone.
- **Other schemes.** Schreiber's key networks ship code and models under the AGPL [S13, snip], which the dependency
  policy excludes.
- **MIREX.** The result pages failed again on an expired certificate, as they did for letter R. The one fact found:
  a 2016 entry built on the mode bias of section 1.3 won on neither set alone and was best of four on the two
  combined [S14]. I found no key task in the 2024 or 2025 campaigns [unverified].
- **Conclusion, confirming letter T:** no published weights can ship; the choice is our own trained model on data
  cleared for it, or methods with nothing trained. New since T: the best non-trained method in print is within
  three points of Mixed In Key 7 on the clean set [S1].

## 3. What DJ tools score, and what DJs do about it

| Test | Tracks, truth | Scores (percent exact) |
|---|---|---|
| DJ TechTools 2014 [S23] | 61 Beatport chart tracks; majority of 7 listeners | Mixed In Key 6: 95; CrossDJ 79; KeyFinder 77; djay 69; **Beatport's own tags 66**; VirtualDJ 65; rekordbox 2: 57; Traktor 54; beaTunes 44 |
| DJ TechTools 2015 [S24] | 66 Beatport chart tracks; majority of 6 listeners | Mixed In Key 7: 86; Serato 70; rekordbox 4: 70; KeyFinder 65; **Beatport's tags 61** (13 of its misses were major for minor); rekordbox 3: 52; Traktor 47; VirtualDJ 41 |
| r/DJs 2020, as Digital DJ Tips reports it [S25; the post would not open] | about 1,340 tracks keyed by people; a relative key counts as right [snip] | Mixed In Key 76.5; Traktor 73.8; rekordbox 69.2; Engine Prime 62.5; djay Pro 61.6; Serato 60.6; VirtualDJ 42.7 |
| r/DJs 2021 to 2022 [S28, snip; S29 quotes it] | 2,650 tracks | Mixed In Key 10: 78 to 91 by test set; Engine DJ 55.8, then 72.7 after its maker changed the algorithm; KeyFinder about 70 |
| r/DJs 2021, streaming sources [S28, snip] | five small sets | Spotify's keys 15 to 39; Tunebat's a little better |
| Faraldo 2017 [S1] | the three dance sets of section 1.2 | Mixed In Key 7: 65.7 to 72.0; KeyFinder 54.8 to 67.4; Essentia default 27.1 to 30.5 |
| A dealer's blog, paid for by Mixed In Key [S31, snip] | 200 tracks, no truth | the three programs gave the same key on 39 percent; Serato differed from Mixed In Key on 45, rekordbox on 38 |
| A 2026 blog test [S32; I could not establish who runs the site] | 200 tracks of six styles, one musician | Mixed In Key 11: 89; Beatport's tags 60 |

Letter R had the two DJ TechTools tests and letter T the 604-clip scores. New here: the Beatport store's own tags in
both listening tests, the 2020 and 2021 community tests, and the scores on our own set.

**What DJs say and do** [S25, S26, S29, S30]:

- **One tool for the whole library.** A key that is wrong the same way everywhere still matches its neighbours;
  keys from several tools do not match each other. Said in every thread read.
- **The ear decides.** The label picks candidates; the DJ listens in the headphones before bringing it in.
- **When it bothers them, they re-read the library** in Mixed In Key or KeyFinder and write the result into the
  tags, where every DJ program picks it up.
- **They know the hard cases:** major against minor, acid and techno in modes Camelot cannot write, tracks with
  little pitch in them.
- **People disagree too.** The maker of Mixed In Key has said two trained listeners agree on about 70 to 75 percent
  of tracks [S25, S30; a vendor's claim, no data shown]. In both DJ TechTools tests a track was kept only when a
  majority of listeners agreed [S23, S24].

## 4. Key and tempo from a song's name

Letter B surveyed lookups for naming a song. This section asks what they would give for key and tempo.

| Source | Key and tempo on offer | Where its key comes from, how good | Dance music, edits, bootlegs | Telling versions apart | May an app use it? Cost, limits |
|---|---|---|---|---|---|
| **Keys already on the computer**: tags in the files; the libraries of rekordbox, Serato, Traktor, Engine DJ, VirtualDJ, Mixed In Key | both | the DJ's own program; 43 to 77 percent by section 3 | everything the DJ has analysed, bootlegs included | it is the same file | yes; nothing leaves the device; free |
| Record-pool and store downloads | usually both, written in the tags [snip] | the pool's or store's machine reading | whatever the DJ downloaded | the same file | as above |
| Beatport | both, per track | machine reading; 61 to 66 percent in S23, S24; the 604-clip test set was built from customers' corrections of its keys (letter R) | strong for released dance music; none for bootlegs, white labels, pop | mix name, label, ISRC | partners only; terms are non-commercial without written permission (letter B); a public sign-up was not open when a plugin author looked [S43] |
| Traxsource | shown on the store pages | unknown | house and soulful dance music | mix name | no public interface found [unverified] |
| Spotify audio features | key, mode, tempo | machine; 15 to 39 percent in the one informal test [snip] | wide for released music; no bootlegs | by track id, ISRC | closed to new apps since Nov 27, 2024 [S33, S48]; Feb 2026 cut more for small apps [S34] |
| Tunebat, Musicstax, songdata.io and similar "key and BPM" sites | both | Tunebat says its database is powered by Spotify's interface [S36, snip]; the others are said to be the same [snip, a forum post] | as Spotify | weak: title and artist | no official developer interface found; scraping is not a basis for a product |
| GetSongBPM, SongBPM, GetSongKey | both; about 6 million songs [S47] | not stated | pop first | title and artist | free with a key; a link back to their site is required in the app's site or store page, for any use [S35, snip: the page refused my fetch]; limits unpublished |
| Soundcharts | key, mode, tempo | not stated | millions of tracks, by its own account | ISRC or a streaming id, not a name [S37] | paid; price not on the page |
| Deezer | tempo and loudness only, no key; tempo often empty [snip] | machine | wide | track id, ISRC | commercial use needs an agreement [S39, snip] |
| Apple Music | neither [S40: a developer's unanswered question; I did not re-read the reference pages] | | | | |
| MusicBrainz | neither in its core data (letter B) | | | recording ids, ISRC | letter B |
| AcousticBrainz | key, mode, tempo for 29 million submissions, as a CC0 download | Essentia's reader; its makers closed it in 2022 saying the key was right on some styles only [S38] | whatever volunteers submitted; little club music [inf] | MusicBrainz recording id, so a name lookup is needed first | free and usable offline, but several gigabytes and frozen in 2022 |
| Discogs | neither; release and version names only | | very strong on versions | release and track | 60 requests a minute; commercial use allowed in general, at its discretion [S41, snip] |
| 1001Tracklists | set lists; no key | | strong on what DJs play | | no public interface found [unverified] |
| Hooktheory | key and chords for about 75,000 songs, entered by people | human, so worth having as an answer key for pop | pop; little dance music | title and artist | interface gives chord statistics only; staff describe it as for personal use; 10 requests in 10 seconds [S42, snip] |
| Services that analyse audio you send them | both | their own models | anything | | out: the audio would leave the device |

**What the table says.**

- **A looked-up key is a machine's reading with a brand on it.** None of the sources that an app could use
  publishes how accurate its keys are. The only store measured by listeners was right on 61 to 66 percent of chart
  tracks, close to Apple's reader and to Mixed In Key 7 on harder music; the streaming source was far worse. A
  lookup would not clear D16's bar by being a lookup.
- **Coverage fails exactly where Deckie is meant to shine.** Edits, bootlegs, pool versions, live sets and rips
  are "first-class" in D4 and absent from every database. And a remix can be in another key than the original, so
  a match on title alone can return a wrong key that looks certain.
- **The terms rule out most of it.** Spotify is closed, Beatport is by partnership, Deezer and Soundcharts are by
  contract, the free services ask for a public link back and publish no limits.
- **Tempo needs no lookup.** Deckie's own tempo reading is the same on every platform (D29).

**Against Deckie's promises.** The public lines are: the music never leaves the DJ's devices, nothing is uploaded,
no account, works with no signal. A lookup by name keeps the first to the letter and bends the rest:

- **What would leave the device:** for each song, its title and artist (and the mix name, the length or the ISRC if
  sent), the computer's internet address, the time, and the key that identifies Deckie to the service. Together
  that is a list of what one DJ owns. The note on D3 already says privacy covers taste, not only audio.
- **Where it could live:** in Desk only, never in the booth; off until the DJ turns it on; asked per crate, with
  the count stated ("Look up 412 song names online? Sends titles and artists, never audio."). Letter B drew the same
  switch for naming songs. The booth would still work with no signal, because the answers would sit in the crate
  file.
- **What the public line would have to become:** "No upload" stays true of music. "Nothing leaves your computer"
  would not be true for a DJ who turns the switch on, and the page would have to say so.
- **When a song is not found:** nothing changes for it. In Deckie's voice: "Not found online. Key not read on this
  computer yet." No guess from a near title.

**Agreement instead of answers.** A second reading is worth most as a check. Letter R measured it: where Apple and
our 3f agree the key is exact 75 percent of the time, against 48 and 65 alone. Two caveats for a looked-up key.
Database keys are machine readings that make the same kind of mode mistake, so their agreement with ours is worth
less than two unrelated opinions would be [inf]. And the check exists only for songs the database has. **The same
check is free from the keys already on the computer**: where Deckie's reading and the DJ's own program agree, mark
the key sure; where they differ, show the DJ's program's key (D16 already ranks it first) and say they differ.

## 5. How much key matters, and how wrong is too wrong

- **A tool, not a rule.** The standard advice to DJs is to "Treat keymixing as a tool not a rule" [S26]: it
  matters when the parts being overlapped carry melody, bass line or voice; it does not when only drums overlap;
  and choosing the next song for its key over what the floor wants is called a mistake. Letter C's reading of the
  community was the same.
- **By style** [S26, S27, inf from them]. Mashups and acapellas over instrumentals: key is everything. Long blends
  of melodic music (progressive, trance, melodic house): it matters on most transitions. Drum-led techno and tech
  house: little, and those are the tracks with the least mode in them anyway. Open format with quick cuts, hip-hop,
  weddings: least. Letter C's two-DJ evidence fits the last group.
- **What DJs do in real sets.** In 24,202 plays taken from recorded mixes, 2.5 percent of tracks were shifted to
  another key, nearly all by one semitone [S44, and letter C]. DJs mostly keep key lock on and choose songs that
  fit, or do not mind.
- **Which errors hurt.** By the "fuzzy" rule taught to DJs, only the Camelot number counts and the letter is
  ignored, so a relative error is free and a fifth error is one step, still inside the rule [S27]. A parallel
  error moves the number by three: outside every rule, and audibly so when the song really plays its third. On a
  track with no third it costs nothing. So the honest measure for a DJ is the last column of the table in section
  1.2: **the label within one step on the wheel**. Apple 81, Mixed In Key 7: 82, ours 69 to 72. The gap to close is
  about ten points on that measure, not the 23 of the minor half [calc; letter R's fifth column may count only the
  fifth above, so these could be a point or two low for every reader alike].
- **The pitch fader moves the key too.** With key lock off, about 6 percent on the fader is one semitone, and 3
  percent is halfway between two keys, where nothing fits. On turntables and older players any key label is true
  only near zero. Deckie's scoring already reasons about this (letter C); it means that for vinyl DJs key accuracy
  beyond the home note is spent quickly.
- **How much effort.** Enough to reach the class of Apple and Mixed In Key (about 65 percent exact, about 80
  within a step) and to say honestly when the mode is open. Past that, the listeners who make the answer keys
  disagree with each other on a quarter of tracks [vendor claim, S25], and DJs do not expect more: they forgive a
  tool at 70 percent and check by ear.

## Options for the owner

Costs are working days for an implementation agent plus review. Gains marked [inf] are estimates.

1. **Read the keys already on the computer, every program's, and show where each came from.** D16 already puts the
   DJ's own key first and the rekordbox import exists. Add Serato (tags in the files), Traktor, Engine DJ,
   VirtualDJ and Mixed In Key tags. Cost: 1 to 2 days per program. Gain: for a DJ who uses any DJ program, which
   on a PC is nearly all of them, a key on almost every song from the first run, matching what their decks show.
   It does not make Deckie's reader better; it makes the PC crate file complete for most DJs, which is what D29
   asks. For a DJ with no DJ program it gives nothing.
2. **Let the mode be open.** Three answers instead of two: minor, major, or home note with the mode open, shown when
   the mode evidence is weak or the three readers split. Cost: hours in the lab to draw the trade (how many songs
   are left open against how often a shown mode is right), from the caches held; then a product choice of what the
   DJ sees. Gain [inf]: fewer wrong modes shown, at the price of some songs with an open mode. It fits D16 and D17
   as written.
3. **Decide what D16's bar measures.** As written it is exact, within five points of Apple, on each half. Section
   1.1 shows Apple's minor-half score is partly a lean. Three other readings of the same intent, any of which the
   owner may prefer: (a) the mean of the two halves; (b) the label within one step on the wheel; (c) of the keys
   Deckie shows, as many right as of the keys Apple shows, with Deckie free to leave some unshown. Under (c),
   letter T's table already has a rule that keeps a third of songs at 67 to 70 percent exact against Apple's 65
   overall. Cost: none. This is the owner's ruling to make or leave.
4. **Three cheap lab runs for the parallel session, in this order.** (i) B's home note with A's mode, and the
   mode trade-off curve of option 2: hours. (ii) Faraldo's method as published (the gate, minor2, the amodal
   profile) scored on GiantSteps+, which none of it has seen: a day; the minor2 values are in the authors' scripts,
   which carry no licence, so they are read as numbers from a paper's method, as letter R did for the other
   profiles. (iii) The mode asked only where the bass is on the home note: one to two days. Gain [inf]: exact from
   55.6 toward 58 to 62 on our set; the clean set will say what is real.
5. **Move the scoring to GiantSteps+ before believing any gain.** Confirmed here: our profiles were made from the
   set we score on. Letter T asked for the fetch (856 MB, labels CC BY-SA 4.0, evaluation only); it needs the
   owner's word and a run of Apple's reader on it for the bar.
6. **A trained transcriber in front of the reader** (Basic Pitch, Apache 2.0), as a lab probe: 3 to 5 days. Gain
   unknown on dance music. Before any shipping, its weights' training sets need recording under D15.
7. **A trained key network** remains the route most likely to pass the bar as written (letter T options 4 and 5).
   Nothing found here changes its cost or its data question.
8. **Rank by how the notes fit, without naming a key**, as a research step: 3 to 5 days to build and compare
   against key-based ranking on pairs the lab can listen to. It changes what D16 gates, so it starts only on the
   owner's word.
9. **A lookup by name, off by default, in Desk only, used only to agree or disagree.** Cost: 2 to 4 days plus a
   contract or a public link back, and a line changed on the public page. Gain [inf]: a "sure" mark on the released
   songs a database knows; nothing for edits and bootlegs; no better keys.

**Recommendation.** Take 1, 2 and 4 now, 5 as soon as the fetch is approved, and rule on 3. Together they answer
the owner's instinct with what the evidence supports: the mode can be handled on its own, partly by hearing it
better (4) and partly by not pretending to hear it when the music does not say (2), and most DJs already have a key
for every song sitting on the same computer (1). Leave 9: it spends the privacy promise to buy readings no better
than our own. Keep 7 as the long road and 6 and 8 as probes for after the cheap runs report.

## What I could not open or verify

- Faraldo's thesis [S2]: the file is larger than the reader allows; abstract only. Its counts of modal and amodal
  tracks would sharpen section 1.4.
- Knees et al. 2015 [S4] and the 2017 talk [S3]: both sites were down. Figures from the first are as letters R and
  T quote them.
- MIREX result pages: expired certificate. No per-year bests.
- The three r/DJs comparison posts [S28]: every mirror refused. Their numbers here come from Digital DJ Tips [S25],
  the Engine DJ forum [S29] and search summaries, and are marked.
- Gebhardt, Davies and Seeber's journal paper and Bernardes's two papers: abstracts and project pages only.
- Terms of use for Tunebat, Traxsource, 1001Tracklists and Beatport's current partner terms: not found or not
  opened. GetSongBPM's page refused the fetch; its terms are from a search summary of that page.
- Basic Pitch's training sets and the licence of its weights apart from the code: not on the page read.
- The provenance of the 2026 blog test [S32], and whether Spotify's February 2026 changes touch the audio-features
  endpoint for the older apps that still had it [S34].
- Nothing here was measured. Every [calc] figure is arithmetic on letter R's tables and should be re-derived from
  the per-clip sheets before it is relied on.

## Sources

- S1 Faraldo, Jordà and Herrera, "A Multi-Profile Method for Key Estimation in EDM", AES Semantic Audio 2017:
  http://mtg.upf.edu/system/files/publications/aes_FARALDO_cameraReady.pdf (listing: https://mtg.upf.edu/node/3767)
- S2 Faraldo, "Tonality Estimation in Electronic Dance Music", PhD thesis, UPF 2018: https://zenodo.org/records/1154586
- S3 Faraldo, Herrera and Jordà, Euromac 2017 extended abstract (site down):
  https://creaa.unistra.fr/websites/gream/Activites/Euromac_2017_-_Postprint_-_Extended_abstract_-_FARALDO_Angel_-_HERRERA_Parfecto_-_JORDA_Sergi.pdf
- S4 Knees et al., ISMIR 2015: https://www.ismir2015.uma.es/articles/246_Paper.pdf ; data page
  https://www.cp.jku.at/datasets/giantsteps/
- S5 Yonay, Hammond and Yang, "Masked Contrastive Pre-Training Improves Music Audio Key Detection", 2026:
  https://arxiv.org/abs/2604.10021 ; https://github.com/echo-cipher/keymyna
- S6 Kong et al., S-KEY, 2025: https://arxiv.org/abs/2501.12907
- S7 Kong et al., STONE, 2024: https://arxiv.org/abs/2407.07408
- S8 Korzeniowski and Widmer 2017 and 2018: https://arxiv.org/abs/1706.02921 ; https://arxiv.org/abs/1808.05340
- S9 MERT model card: https://huggingface.co/m-a-p/MERT-v1-95M
- S10 MuQ: https://github.com/tencent-ailab/MuQ
- S11 MusicFM: https://github.com/minzwon/musicfm
- S12 Basic Pitch: https://github.com/spotify/basic-pitch
- S13 key-cnn: https://github.com/hendriks73/key-cnn
- S14 INESC key detection and the mode bias: https://sites.google.com/site/tonalintervalspace/key-detection ; Bernardes
  and Davies, ICASSP 2017, https://doi.org/10.1109/ICASSP.2017.7952169
- S15 Eerola and Schutz, "Major-minorness in tonal music", Psychology of Music 2025:
  https://durham-repository.worktribe.com/output/3347632
- S16 Gebhardt, Davies and Seeber: DAFx 2015, https://dafx.de/paper-archive/details/VVCYuTXWkEB3l4VKeUZ0-A ; Applied
  Sciences 2016, https://www.mdpi.com/2076-3417/6/5/123
- S17 Bernardes, Davies and Guedes, "A hierarchical harmonic mixing method", 2018:
  https://doi.org/10.1007/978-3-030-01692-0_11
- S18 Wu and Yoshii 2022: https://nowpublishers.com/article/Details/SIP-2021-0052
- S19 Jointist: https://arxiv.org/abs/2206.10805
- S20 Mauch and Dixon, IEEE TASLP 2010:
  https://webspace.eecs.qmul.ac.uk/s.e.dixon/pub/2010/Mauch-Dixon-TASLP-2010-real.pdf
- S21 Chord recognition on separated stems, 2025: https://arxiv.org/abs/2509.18700
- S22 ISMIR 2025, local key and cross-version consistency: https://ismir2025program.ismir.net/poster_67.html
- S23 DJ TechTools 2014: https://djtechtools.com/2014/01/14/key-detection-software-comparison-2014-edition/
- S24 DJ TechTools 2015: https://djtechtools.com/2015/11/16/key-detection-software-comparison-2015-edition
- S25 Digital DJ Tips, key detection 2020: https://www.digitaldjtips.com/2020/10/best-dj-key-detection-2020/
- S26 Digital DJ Tips, how important is mixing in key:
  https://www.digitaldjtips.com/2020/09/how-important-is-it-to-mix-in-key/
- S27 Digital DJ Tips, fuzzy keymixing: https://www.digitaldjtips.com/2021/01/fuzzy-keymixing-the-new-way-to-dj/
- S28 r/DJs key detection comparisons (not opened): https://www.reddit.com/r/DJs/comments/hwlzyt/ ;
  https://www.reddit.com/r/DJs/comments/rn2wu5/ ; https://www.reddit.com/r/DJs/comments/m3q97z/
- S29 Engine DJ forum: https://community.enginedj.com/t/engine-dj-badly-analyses-track-key/52099
- S30 VirtualDJ forum: https://virtualdj.com/forums/244659/General_Discussion/KEY_DETECTION_COMPARISON_2021.html
- S31 Crossfader on Mixed In Key 11: https://wearecrossfader.co.uk/blog/mixed-in-key-11/
- S32 Blog test, Beatport against Mixed In Key: https://blog.dubspot.com/dubspot-lab-report-mixed-in-key-vs-beatport
- S33 Spotify, Nov 27, 2024: https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api
- S34 Spotify, February 2026: https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security ;
  https://developer.spotify.com/documentation/web-api/references/changes/february-2026
- S35 GetSongBPM: https://getsongbpm.com/api
- S36 Tunebat: https://tunebat.com/Analyzer
- S37 Soundcharts: https://soundcharts.com/en/audio-features-api
- S38 MetaBrainz on ending AcousticBrainz:
  https://blog.metabrainz.org/2022/02/16/acousticbrainz-making-a-hard-decision-to-end-the-project/ ;
  https://acousticbrainz.org/download
- S39 Deezer, questions from developers: https://support.deezer.com/hc/en-gb/articles/360011538897-Deezer-FAQs-For-Developers
- S40 Apple developer forum, tempo in the Apple Music interface: https://developer.apple.com/forums/thread/726626
- S41 Discogs terms for its interface: https://support.discogs.com/hc/en-us/articles/360009334593
- S42 Hooktheory: https://hooktheory.com/api/trends/docs
- S43 Beatport access: https://apis.io/providers/beatport/ ; https://github.com/Samik081/beets-beatport4
- S44 Kim, Choi, Sacks, Yang and Nam, ISMIR 2020: https://arxiv.org/abs/2008.10267
- S45 A count of keys in a Beatport top 100 (65 percent minor, 2023): https://www.edmprod.com/beatport-analysis/
- S46 Faraldo's scripts: https://github.com/angelfaraldo/edmkey
- S47 MusicRadar on GetSongKey: https://musicradar.com/news/getsongkeycom-gives-you-essential-music-theory-information-about-more-than-6-million-songs
- S48 TechCrunch on Spotify's 2024 change:
  https://techcrunch.com/2024/11/27/spotify-cuts-developer-access-to-several-of-its-recommendation-features
