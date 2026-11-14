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
- **Beside Apple on the same songs it is level, not better** (section 2a, added Nov 14 after the owner asked). On
  the 73 percent of MTG songs it shows, it is right on 69.9 percent and Apple on 71.2; the difference is not real
  (sign test p = 0.44). It is far better than Apple on major songs and clearly worse on minor ones. The published
  scores of Mixed In Key 7 (65.7 on MTG) and rekordbox 3 (71.9 on the 604-clip set; the learned reader's shown
  keys: 73.1) are over every song, so they are not the same comparison.
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
| Trained on | 3,129 recordings under CC BY, CC0 or public-domain terms: 710 Freesound loops and 371 Free Music Archive songs with human key labels, 48 CC0 piano recordings, and 2,000 Free Music Archive clips labelled by the untrained reader. `DEPENDENCIES.md`, section 13, has the record in D15's shape |
| Not trained on | anything from GiantSteps or Beatport, anything non-commercial or share-alike, anything of the owner's |
| In a record | `key.source` `learned-key`; `key.confidence` the key's probability; `key_home` for a home note; `engine.models` names the model; the three-answer reader's key is kept as a vote |
| Without the file | the untrained three-answer reader, exactly as in engine 0.6.0 |
| Could the small model run in plain Swift? | Yes, and it does: about 135 million multiply-adds for thirty seconds of music. ONNX Runtime is not used, so the Mac and the iPad can run it from the shared core without carrying that library |

**Why this model.** Fixed before scoring: the candidate is the one taught on the most lawful data, and it replaces
the untrained reader only if its shown keys are right more often at the same coverage on MTG and one other set, and
not worse by more than a point on the third. It won by 5 to 7 points on all three. The 49-number learned profiles
also beat the untrained reader, by 1 to 3 points; the model is clearly better and still small.

**A plain note on the training data.** Human labels and the untrained reader's labels turned out to be worth the
same: the model scores 61.5 exact on MTG taught on the 1,129 human-labelled recordings alone, 61.5 taught on 2,000
reader-labelled clips alone, and 61.7 on both. I kept the candidate fixed in advance (both) rather than switch
after seeing scores. Either alone would have a shorter record; the reader-labelled one would have no human-labelled
set in it at all, which removes the open point about FMAK's "research purposes" sentence. Retraining either is
under an hour.

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
reader is level with Apple on the songs it shows (section 2a) and shows more than the untrained reader did. The
tools' published scores are over every song, so "more often right than the tools" would compare an easier set of
songs with a harder one. At the bar's measure (every song, both halves) it is not: it is the fairest reader
measured (60 percent on each half), where Apple is right on 76 percent of minor songs and 42 percent of major ones.

**One thing got worse.** Its home-note answers are fewer and less often right than the untrained reader's (9.8
percent of songs at 68.8 percent right, against 11.7 at 79.2). The untrained reader's home note comes from two
methods agreeing; the model's from summing two probabilities. It is the weakest of the three answers now.

## 2a. Beside Apple, song by song (added Nov 14)

The owner asked: "Why didn't it meet the bar?" and "am I to understand that it is more accurate than Apple but
makes a determination less often?" Apple's answer for each of the 1,270 MTG clips is from the first trial; the
learned reader is as it ships. "Only ours right" and "only Apple right" count the songs where the two differ in
being right; the sign test asks whether that split could be chance (p under 0.05: a real difference). Table:
`mixer/keytrial/x4_apple_results.md` (`kt_x4.py apple`).

**The second question first: no.** It is not more accurate than Apple. On the songs where it shows a key, the two
are level. On the songs it declines, Apple would have been right about half the time. Over all songs Apple is
ahead.

| MTG, 1,270 clips | Songs | Ours right | Apple right, same songs | Only ours right | Only Apple right | Real difference? |
|---|---:|---:|---:|---:|---:|---|
| **Ours shows a key** (73.1 percent) | 928 | 69.9 | 71.2 | 95 | 107 | no (p = 0.44) |
| **Ours declines** (ours forced to name a key) | 342 | 36.5 | 48.8 | 41 | 83 | yes, Apple (p = 0.0002) |
| Every song | 1,270 | 60.9 | 65.2 | 136 | 190 | yes, Apple (p = 0.003) |

So declining is doing its job (the declined songs are the ones it would get wrong two times in three), but Apple
is right on half of those, and Deckie shows nothing there.

| The most confident share shown | Songs | Ours right | Apple right, same songs | Only ours | Only Apple | Real difference? |
|---:|---:|---:|---:|---:|---:|---|
| 60 percent | 762 | 73.2 | 74.5 | 65 | 75 | no (p = 0.45) |
| 70 percent | 889 | 71.0 | 71.5 | 90 | 95 | no (p = 0.77) |
| 80 percent | 1,016 | 68.1 | 70.3 | 105 | 127 | no (p = 0.17) |
| 90 percent | 1,143 | 64.2 | 67.7 | 119 | 159 | yes, Apple (p = 0.02) |
| 100 percent | 1,270 | 60.9 | 65.2 | 136 | 190 | yes, Apple (p = 0.003) |

**By major and minor: each reader is strong where the other is weak.**

| | Songs | Ours right | Apple right, same songs | Only ours | Only Apple | Real difference? |
|---|---:|---:|---:|---:|---:|---|
| **Major songs**, ours shows a key | 298 | 66.1 | 45.6 | 73 | 12 | yes, ours (p under 0.001) |
| Major songs, ours declines | 88 | 38.6 | 27.3 | 23 | 13 | no (p = 0.13) |
| Major songs, every song | 386 | 59.8 | 41.5 | 96 | 25 | yes, ours (p under 0.001) |
| **Minor songs**, ours shows a key | 630 | 71.7 | 83.3 | 22 | 95 | yes, Apple (p under 0.001) |
| Minor songs, ours declines | 254 | 35.8 | 56.3 | 18 | 70 | yes, Apple (p under 0.001) |
| Minor songs, every song | 884 | 61.4 | 75.6 | 40 | 165 | yes, Apple (p under 0.001) |

The same holds at every share shown: on major songs ours leads by 18 to 20 points, on minor songs Apple leads by
10 to 14. Ours answers "minor" for 62 percent of songs and Apple for 79 percent; the collection is 70 percent
minor.

**Why it did not meet the bar.** The bar as written scores a reader that names a key for every song, and asks it
to be within five points of Apple on the major songs and, separately, on the minor songs (36.5 and 70.6). The
learned reader scores 59.8 on the major half, 23 points over, and 61.4 on the minor half, 9.2 under. The reason is
a habit, not hearing: both readers find the home note about equally often (75.0 and 76.4 percent). The music the
reader may lawfully learn from is half major, so when the mode is unclear it has no reason to prefer minor, and it
splits its doubt evenly. Apple prefers minor when unsure. On dance music, which is mostly minor, that habit earns
Apple 75.6 on the minor half and costs it the major half, where it is right on 41.5 percent. A lean added to the
reader does the same trade: leaned to 65 percent minor (a published share of one dance chart) it reached 66.6 on
the minor half, 3.9 short, and 53.9 on the major; leaned to 85 percent (another published share) it reached 75.7
on the minor half and fell to 33.4 on the major, 3.0 short on that side (letter X3; at twelve pitch shifts). No
lean passed both halves. For the bar to be met honestly, one of three things would have to be true: the reader
learns from dance music that is as minor as the test (only the GiantSteps route has it, and that is the
attorney's question); or Deckie has a count of minor keys in dance music from a source that is not the test's own
shop, and applies it (none was found; openly licensed electronic music came out at 55 percent); or the reader
hears the mode better on minor songs, which no lawful training tried here achieved.

**What could be measured instead.**

| Measure (MTG, 1,270 clips) | Ours | Apple | Who leads |
|---|---|---|---|
| **The bar as written**: every song given a key, exact on the major half and on the minor half | 59.8 and 61.4 | 41.5 and 75.6 | fails the minor half by 9.2; passes the major by 23 |
| Every song given a key, exact | 60.9 | 65.2 | Apple by 4.3 (real) |
| Every song given a key, the mean of the two halves (a major song counts as much as a minor one) | 60.6 | 58.5 | ours by 2.1 |
| **Keys shown** (73.1 percent of songs), exact, Apple on the same songs | 69.9 | 71.2 | level (not a real difference) |
| Every song, within one step on the wheel (exact, relative, or a fifth away) | 74.8 | 78.3 | Apple by 3.5 |
| Keys shown, within one step, Apple on the same songs | 81.2 | 82.9 | level |
| Every song, the home note | 75.0 | 76.4 | level |

**In one line for the owner:** Deckie's reader is as right as Apple on the songs where it speaks, says nothing on
a quarter of songs where Apple would be right half the time, is much better than Apple on major songs and worse on
minor ones, and misses the bar because the bar rewards guessing minor.

## 2b. Openly licensed club music, a slight lean, what "right" means, and the bar reworded (added Nov 14)

The owner, after section 2a: "And we have done a deep search of the internet for public license club music? There
has to be some out there. My inclination would be to add a slight lean. Though I also think the bar needs to be
reworded. It is a problem for the DJ to get a wrong key or mode right? Is our 'accurate' based on getting a key or a
key and mode? Overall it feels like we are there or very close." Tables: `mixer/keytrial/x4_club_results.md`,
`x4_dj_results.md`.

### Club music under licences that allow a shipped model

Counted from each source's own licence field (opened Nov 14, 2026). Usable: CC0, public domain, CC BY. Set aside:
share-alike, and non-commercial or no-derivatives.

| Source | How counted | Usable club music | Set aside: share-alike | Set aside: non-commercial or no-derivatives | Fetched? |
|---|---|---|---|---|---|
| **Internet Archive, netlabel releases** (77,109 releases) | its search interface, by licence and tag; then each release's file list | **684 releases whose tags name a club style exactly: 6,175 tracks** (CC BY 398 releases, CC0 or public domain 286). By the looser tag search: 1,301 releases, but 570 of them are one noise label whose name contains "trance" | 770 releases | 13,875 releases | **yes: about a minute from the middle of 3,667 tracks** (up to 12 a release; 5.1 GB), evaluation only |
| Internet Archive, its mirror of Jamendo's albums (294,067 albums) | the same | 2,333 dance-tagged albums, all CC BY | 2,207 albums | 20,362 albums | no (next in line: the largest untouched pool) |
| MTG-Jamendo research set (55,701 tracks) | its per-track licence file | 627 dance tracks, 53 hours (the same catalogue as the row above) | 1,744 tracks | 6,246 tracks | no: "made available solely for non-commercial research and academic use"; audio only as 508 GB of archives |
| Jamendo's own interface | its documentation | needs an account; "may be used freely for non-commercial uses" | | | no |
| ccMixter | its query interface | 1,458 dance-tagged uploads; about 750 are whole remixes (54 hours), the rest samples and vocals | 20 | 5,245 | no |
| TeknoAXE (one author's catalogue) | its genre pages | 1,029 tracks, CC BY 4.0 | 0 | 0 | no; one author's sound would dominate |
| Ektoplazm (psychedelic trance) | its release pages | 82 releases | 1 | 1,949 | no |
| SampleSwap's music section | its genre pages | 109 songs | 286 | 615 | no |
| Free Music Archive, research set (letter X4) | its track table | 2,745 electronic tracks (wider than club) | | 78 percent of the archive | yes, earlier: 30-second clips |
| Incompetech, Audionautix | catalogues | about 165 tracks; soundtrack electronica, not club | 0 | 0 | no |
| Magnatune, SoundCloud, Bandcamp, Pixabay, the Free Music Archive's live site, NoCopyrightSounds, sample packs (99Sounds, MusicRadar, Legowelt) | terms | none: non-commercial, or scraping and training forbidden, or no open licence | | | no |

**So: yes, there is some, and most open club music is not usable.** Nine in ten openly licensed dance releases
carry a non-commercial or no-derivatives licence. What is usable and within reach is about 6,000 netlabel tracks
(a sample of them now fetched) and about 2,300 Jamendo albums on the Internet Archive, perhaps 15,000 to 20,000
tracks more [inf: seven or eight tracks an album]. The Internet Archive "does not make guarantees as to the
copyright status of items"; each release's licence is its uploader's statement.

**What the reader hears in it.** Of 3,650 club excerpts read, the untrained reader gave a key to 1,971 (54 percent),
a home note to 327 and nothing to 1,352: club music is harder for it than the Free Music Archive's mix (63 percent).

| Style (the release's own tag) | Excerpts | Given a key | Minor among those, percent |
|---|---:|---:|---:|
| Techno | 1,877 | 955 | 65.2 |
| Electro | 745 | 447 | 63.8 |
| House | 633 | 351 | 64.1 |
| Dance | 551 | 311 | 66.9 |
| Breaks | 440 | 259 | 70.3 |
| Dubstep | 377 | 236 | 74.2 |
| Hardcore | 372 | 179 | 65.9 |
| Drum and bass | 348 | 184 | 62.5 |
| Acid | 279 | 153 | 63.4 |
| Trance | 237 | 141 | 67.4 |
| Garage | 149 | 88 | 65.9 |
| **All club excerpts** | 3,650 | 1,971 | **65.6** |

Club music is about two thirds minor in every style, by a count that owes nothing to Beatport or to the test
collection. (Counting each of the 342 creators once: 67.4.) It also agrees with the one published chart count,
65 percent.

**Does more real club music move the scores?** RETRAIN_HERE

### A slight lean: the candidates

The lean raises the model's minor answers as if the music it learned from had held a given share of minor keys.
**The source of candidate (c) was fixed and committed before the club excerpts were read** (`kt_x4.py`, "THE CLUB
LEAN"); by then leans of 65 and 85 had been scored, and they are shown, not chosen by their scores. MTG, 1,270
clips, the reader as it ships otherwise:

| Lean to this share of minor | Source | Major half | Minor half | Bar as written (36.5 / 70.6) | Every song, exact | Within one step | Key shown | Shown keys right | Apple on those songs |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|
| (a) as now, 55.2 | open electronic music of the Free Music Archive, as the reader hears it | 59.8 | 61.5 | fails: minor 9.0 short | 61.0 | 74.9 | 73.1 | 69.9 | 71.3 |
| none at all, 52.4 | the training mix | 60.1 | 61.0 | fails: minor 9.6 short | 60.7 | 74.5 | 72.6 | 69.5 | 70.9 |
| (b) 65 | a published count of one Beatport chart (letter X) | 54.9 | 65.5 | fails: minor 5.1 short | 62.3 | 75.9 | 73.0 | 71.1 | 72.3 |
| (b) 85 | the published share of the GiantSteps Key set, a sibling of the test collection | 42.5 | 72.2 | **passes** | 63.1 | 77.0 | 74.2 | 71.9 | 72.1 |
| **(c) 65.6** | **the share the reader finds in openly licensed club music (above)** | 53.9 | 65.6 | fails: minor 5.0 short | 62.0 | 75.7 | 73.2 | 71.2 | 72.2 |
| Apple | | 41.5 | 75.6 | | 65.2 | 78.3 | 100 | 65.2 | |

| | GiantSteps+: every song | key shown | shown right | GiantSteps Key: every song | key shown | shown right |
|---|---:|---:|---:|---:|---:|---:|
| (a) as now | 79.9 | 83.8 | 89.3 | 63.6 | 80.0 | 73.1 |
| (b) 65 | 80.8 | 83.3 | 90.3 | 64.7 | 80.0 | 73.7 |
| (b) 85 | 82.7 | 85.0 | 91.2 | 67.1 | 82.8 | 74.6 |
| **(c) 65.6** | 80.8 | 83.1 | 90.2 | 64.7 | 79.8 | 73.9 |

- **(c) is the one I would take.** It is slight, it has a source Deckie measured itself on music that is neither
  the test nor its shop, and it helps every measure on all three sets by about a point: on MTG the shown keys go
  from 69.9 to 71.2 percent right at the same coverage, level with Apple's 72.2 on those songs. It costs six points
  on major songs (59.8 to 53.9), which stay 12 above Apple.
- **(b) 85 passes the bar as written, and I would not take it.** Its source is the count of a set drawn from the
  same shop as the test, and it gets there by Apple's own trade: the major half falls to 42.5.
- **(d) By the style a crate records: cannot be built today.** The crate's `style` block is a list of numbers with
  no named style. Until the engine can say "this is dance music", a lean applies to every song. That matters for
  a DJ who plays pop or disco, where songs are mostly major (35 percent minor in the open pop measured in letter
  X4): there the lean would cost accuracy. If (c) is chosen it should be said in the product's notes that the
  reader is tuned to club music.
- **How it is built.** `KeyModel.chosenMinorShare` (nil today). Setting it to `0.656` is the whole change; the
  model's name in a record becomes `deckie-key-2b4fe8fa-minor66`, so crates made with and without the lean are
  told apart and work folders are analysed again. `DECKIE_KEY_MINOR_SHARE=65.6` tries it without changing code.

### What "right" means to a DJ

In every table above, "right" is **exact: the home note and the mode both**. For mixing, errors are not equal:

| MTG, 1,270 clips; percent of the songs in the row | Songs | Exact | Right home note, wrong mode (two songs laid over each other clash) | A neighbour on the wheel: the relative key, or a fifth away (mixes fine) | Anything else | Within one step on the wheel (exact or a neighbour) |
|---|---:|---:|---:|---:|---:|---:|
| **Ours, the keys it shows** | 928 | 69.9 | 14.0 | 11.3 | 4.7 | **81.2** |
| Apple, on those same songs | 928 | 71.2 | 12.0 | 11.6 | 5.2 | 82.9 |
| Ours, every song (forced) | 1,270 | 60.9 | 14.0 | 13.9 | 11.2 | 74.8 |
| Apple, every song | 1,270 | 65.2 | 11.2 | 13.1 | 10.5 | 78.3 |
| Ours, shown keys, major songs | 298 | 66.1 | 20.1 | 9.4 | 4.4 | 75.5 |
| Apple, same songs | 298 | 45.6 | 31.2 | 18.1 | 5.0 | 63.8 |
| Ours, shown keys, minor songs | 630 | 71.7 | 11.1 | 12.2 | 4.9 | 84.0 |
| Apple, same songs | 630 | 83.3 | 2.9 | 8.6 | 5.2 | 91.9 |

- **Of the keys Deckie shows, four in five mix correctly** (81.2 percent within one step), the same as Apple's on
  those songs (82.9; not a real difference, p = 0.24). One in seven has the right home note and the wrong mode,
  which is the error a DJ hears; one in twenty is simply wrong.
- **The home-note answer exists for exactly that error and catches part of it.** Forced to name a key for every
  song, the reader would make 178 wrong-mode errors. 130 of them are among the keys it shows; 32 are avoided
  because it showed the home note alone, 16 because it said not sure. On the 125 songs given a home note, a forced
  key would have had the wrong mode on one song in four (25.6 percent).
- **So the mode is the remaining problem**, on both readers: Apple makes 142 wrong-mode errors over all songs, and
  on major songs it gets the mode wrong on 31 percent of them.

### The bar, reworded: three candidates

Each is one sentence a DJ could read, with what it gives today (MTG unless said).

| # | Wording | Today | Passes? |
|---|---|---|---|
| 1 | **"Of the keys Deckie shows, as many mix correctly (within one step on the wheel) as Apple's on the same songs, give or take three points; and Deckie shows a key for at least seven songs in ten."** | 81.2 against Apple's 82.9 (1.7 behind, not a real difference); 73.1 percent shown | **passes** |
| 2 | "A key is shown only when it is right at least two times in three on music the reader has never heard, on every outside collection." | 69.9 (MTG), 89.3 (GiantSteps+), 73.1 (GiantSteps Key) | passes; at "seven times in ten" it would fail on MTG by 0.1 |
| 3 | "With every song given a key, Deckie is no more than five points behind Apple, counting a major song as much as a minor one." (The old bar's spirit: no worse than Apple; scoring the halves' average instead of each half, so preferring minor earns nothing.) | 60.6 against Apple's 58.5 | passes, 2.1 ahead |
| old | "Exact within five points of Apple on the major half and on the minor half, every song given a key." | 59.8 and 61.4 against 41.5 and 75.6 | fails: minor 9.2 short |

**I would choose wording 1.** It measures what the DJ is given (shown keys), in the DJ's terms (does it mix), against
the reference the owner named (Apple, on the same songs), and its second half stops the reader from passing by
going quiet. A lean cannot game it: leaning helps only if the shown keys really do mix better. Wording 3 is the
fair repair of the old bar if the owner wants to keep judging every song. Wording 2 needs no Apple at all, which is
its strength and its weakness: "two times in three" is a number someone has to pick.

**Is it there or very close?** On wording 1 it is there today, and with lean (c) the shown keys are right as often
as Apple's on the same songs (71.2 against 72.2). Where it is behind: Apple names a key for every song and is still
right on 65 percent of them; Deckie is silent on a quarter.

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
- Acknowledgements: a row for the model when its file ships (`DEPENDENCIES.md`, section 13, has the row).

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
- **The three open points on the training data** in `DEPENDENCIES.md`, section 13 (credit for CC BY 3.0, FMAK's
  "research purposes" sentence, uploaders' public-domain statements), are the attorney's.
