# Research W4: recognition of Deckie's own, complete in the shared core

Dated Nov 14, 2026. What was chosen for D35's recogniser and why, the measurements of it as built, what an iPad
app must do to use it, and what is still unproven. It follows letters W2 (the first trial), AB (how other
fingerprints survive noise, and size) and W3 (the first trial on a real evening). Branches: `recog/size` (the
study), `recog/core` (merged into `main` during the night), `recog/finish` (this letter and the last rows). Facts
are measurements of this work unless a source is named; *[inference]* marks my reading.

Words used: a **fingerprint** is the small description of a song the crate file carries; its **points** are the
spots of the song's spectrogram (time against pitch) louder than everything round them; a **hash** is a number made
from two or more points, which is what is looked up; an **anchor** is the point a hash starts from; the **index** is
the table of every song's hashes that the booth holds; a **listen** is the few seconds of microphone sound being
matched.

## 1. In one page

**What was chosen.**

- **The fingerprint in the crate file is the first trial's, unchanged**: every point of the song, about 96 bytes per
  second of music (23 KB for four minutes), in `prints/<id>.dkl` with a `print` key on the record that carries its
  own version number. Every builder writes it on every system.
- **The booth's index is made of two-point hashes, and it is thin.** Anchors are the strongest half of the points
  round each (within a second either side); each anchor gets three hashes. About 41 KB a song at 5,000 songs: a
  sixth of the first trial's. A small setting (the strongest quarter) is 21 KB a song.
- **The first pass proposes; a check decides.** The songs with the most agreeing hashes are proposed, and the best
  two proposals of each of the first 50 songs are checked point by point against that song's own fingerprint at the
  place and speed proposed. The check gives the song, the place, the speed and the key lock.
- **Copies count as one.** Songs that hold the same sound (a second file of a recording; a long file that contains a
  song) are found when the index is built and never counted against each other.
- **The listener gathers and follows.** It takes sound continuously, gives a reading a second, names a song when one
  listen is sure or two in a row agree, then follows it with one cheap check a second and searches the whole crate
  every other second to notice the next song.

**The table** (969 outside songs in the index, eval half only; the finished listener fed second by second; percent
of clips with the right song named by that many seconds of listening)

| Condition | 3 s | 5 s | 8 s | 12 s | The first trial (W2), one 8 s / 12 s listen |
|---|---|---|---|---|---|
| Clean, any fader setting, key held or vinyl-style | 92 | 99 | 100 | 100 | 100 / 100 |
| A measured room | 67 | 87 | 95 | 98 | 95 / 98 |
| Room, crowd 10 dB under the music | 54 | 78 | 91 | 96 | 89 / 93 |
| Room, crowd 5 dB under | 43 | 69 | 84 | 91 | 75 / 85 |
| Room, crowd at equal level | 27 | 54 | 71 | 82 | 60 / 72 |
| Room, crowd 5 dB over the music | 10 | 25 | 41 | 56 | 33 / 43 |
| Room, pink noise at equal level | 33 | 59 | 76 | 87 | 68 / 77 |
| Small speaker, room, crowd at equal level | 43 | 72 | 85 | 93 | 79 / 86 |

- A song that is not in the index was named in **0 of 1,074** such clips; a wrong song in 0 to 0.6 percent of clips.
- On generated DJ mixes the right name is on screen for **99 percent of each song's seconds** (77 percent under
  heavy distortion), from the second the song is alone at the median.
- With every song in the index twice and long joined files added, the scores do not move (section 3.5).
- A reading takes 29 ms at the median here against 969 songs; a search of the whole crate takes a third of a
  second against 5,000 songs. What the app itself holds in memory is about 2 KB a song; the index is a file of
  41 KB a song opened in place (205 MB for 5,000 songs; 106 MB with the small setting).

**What it means.** The recogniser now names more songs in noise than the first trial did, from a sixth of the
memory, on any system, and it no longer stumbles on a library with two files of the same song. It is still short
of what letter H measured for ShazamKit in loud noise (pink noise at equal level, 8 s: 76 percent here, 90 to 100
there, in a milder room), though on the one real evening W3 measured, the first trial already named songs sooner
than Apple's did. What is unproven is a loud room and an iPad (section 6); what I would try next is in section 7.

## 2. The design as built

- **Fingerprint** (`Landmarks`): as in W2, section 2. Unchanged by this work, so every crate file made since
  `recog/core` was merged is good as it is.
- **Index** (`RecognitionIndex`, settings `PairingConfig.booth`): for each anchor, the target zone after it (64 ms to
  2 s, an octave either way) is cut into three slices of time and the strongest point of each is taken; a hash is
  the anchor's pitch step, the target's, and the time between (21 bits, as in Wang's paper). An entry is 4 bytes.
  Which points are anchors is decided locally (the strongest half of the points within a second either side), so
  no passage is without anchors.
- **The index as a file** (`write(to:)`, `init(contentsOf:)`, `cached(at:stamp:…)`): built once per crate file,
  written as one file, and opened in place from storage; it is made again only when the crate's songs change.
- **Matcher** (`Recogniser`): the query's points are tried at 69 deck speeds by arithmetic, as in W2; hashes vote for
  (song, place); the wide check; the confidence is a song's count of agreeing points over the third-best song's,
  songs that hold the same sound left out.
- **Same sound** (`SameRecording`): from the crate file's keys (`ident.cut_key`, through
  `Crate.recognitionSongs()`), and from the fingerprints: three 8 s stretches of each song are matched against the
  index at the song's own speed, and a song that answers two of them at one and the same shift is related. That
  finds a copy with no key and a file that contains the song. A match reports them as `copies`.
- **Listener** (`SongListener`, and `BoothRecogniser` for an app): section 5.
- **Tool**: `deckie-listen` plays any recording through the listener and prints each second.
- Four-point hashes in both forms, three-point hashes, the dense listen and the fuzzy lookup are in the code as
  options, off, so the study's rows can be made again.

## 3. How it was chosen

Everything in this section is the size study: the eval half, 12,600 listens (5, 8 and 12 s), a single listen each,
with each row's own threshold set on the dev half's no-right-answer clips. Cells are right song named and accepted,
percent, at 5 / 8 / 12 s. Noise levels are nominal: music against noise over the whole band. Inside the 300 to
3600 Hz the fingerprint reads, measured on 200 clips made like the benchmark's, crowd noise is 0.5 dB worse than
nominal at the median (dance music 1.6 dB worse; one clip in ten 6.6 dB worse or more) and pink noise 2.4 dB
better, so "crowd at equal level" is about -0.5 dB in band. Letter AB's guess of several decibels did not hold:
the crowd recordings carry bass too. Times are with four jobs sharing the machine.

### 3.1 The steps that cost nothing, and thinning

| Step | KB a song in memory | clean | room | crowd 10 dB under | crowd at equal level | wrong names per 1,000 | absent songs named per 1,000 | 8 s listen, ms: median / 95th |
|---|---|---|---|---|---|---|---|---|
| the first trial (W2): threes, every hash, 12 votes checked | 261 | 100 / 100 / 100 | 89 / 95 / 98 | 78 / 89 / 93 | 48 / 60 / 72 | 0.0 | 1.6 | 45 / 65 |
| 4-byte entries, a smaller table | 162 | 100 / 100 / 100 | 88 / 95 / 98 | 81 / 89 / 94 | 49 / 61 / 73 | 0.2 | 1.9 | 54 / 78 |
| the wide check (50 songs) | 162 | 100 / 100 / 100 | 90 / 95 / 98 | 83 / 91 / 95 | 56 / 68 / 76 | 0.0 | 0.0 | 61 / 96 |
| one hash in 4, no wide check, plain listen | 40 | 100 / 100 / 100 | 77 / 87 / 92 | 62 / 78 / 86 | 34 / 49 / 57 | 0.0 | 0.6 | 65 / 109 |
| one hash in 4, dense listen, wide check | 40 | 100 / 100 / 100 | 81 / 90 / 95 | 72 / 83 / 90 | 46 / 58 / 69 | 0.7 | 0.9 | 110 / 245 |

Narrower entries and a smaller table take the first trial from 261 to 162 KB a song with nothing lost. Checking
the first 50 songs proposed, in place of the 12 fullest votes, adds 7 points at equal-level crowd. Thinning costs
accuracy, and a denser listen with the wide check gives most of it back.

Letter AB asked first for the number everything rests on: how often the right song is among the first pass's
proposals when it is not first. With the full three-point index, at equal-level crowd (dev half, 5 to 12 s
pooled): first 54 percent, in the first 10, 67; first 30, 75; first 50, 78; first 100, 82. In the room alone: 87,
92, 95, 97, 98. So a check of 50 had up to 24 points to win at that noise, and won 7 with threes; twos win more
because their proposals are better to begin with.

### 3.2 Two points, three or four: the owner's question

"Can we use 4 points?" Yes, and they were built two ways, from Sonnleitner and Widmer's paper with no outside
code: hashed like threes, with the speed search; and the ratio form, where the first and last point set a frame
and the two between are described as fractions of it, so the hash does not change with speed and there is no speed
search. Each with a thin reference and a wide listen, and the same check.

| First pass, all with the wide check | KB a song in memory | clean | room | crowd 10 dB under | crowd at equal level | wrong names per 1,000 | absent songs named per 1,000 | 8 s listen, ms: median / 95th |
|---|---|---|---|---|---|---|---|---|
| twos (the booth's index) | 47 | 99 / 99 / 100 | 88 / 93 / 98 | 81 / 91 / 95 | 58 / 71 / 79 | 0.2 | 0.0 | 62 / 102 |
| threes, one hash in 4, dense listen | 40 | 100 / 100 / 100 | 81 / 90 / 95 | 72 / 83 / 90 | 46 / 58 / 69 | 0.7 | 0.9 | 110 / 245 |
| fours, ratio form (no speed search), one a point | 40 | 99 / 100 / 100 | 69 / 79 / 85 | 59 / 68 / 76 | 34 / 43 / 50 | 0.5 | 1.2 | 27 / 52 |
| fours, hashed like threes, one hash in 4 | 40 | 100 / 100 / 100 | 58 / 70 / 79 | 44 / 56 / 63 | 22 / 32 / 39 | 0.8 | 2.8 | 46 / 537 |
| twos, small setting | 28 | 99 / 98 / 99 | 79 / 89 / 95 | 69 / 84 / 90 | 50 / 62 / 73 | 0.3 | 0.0 | 39 / 61 |
| threes, one hash in 8, dense listen | 20 | 100 / 100 / 100 | 72 / 83 / 90 | 61 / 74 / 83 | 34 / 49 / 58 | 0.7 | 0.3 | 109 / 238 |
| fours, ratio form, stronger half of points | 20 | 94 / 97 / 98 | 60 / 69 / 80 | 53 / 63 / 71 | 29 / 37 / 46 | 0.5 | 4.7 | 22 / 34 |
| threes, one hash in 16, dense listen | 10 | 98 / 100 / 100 | 58 / 74 / 83 | 48 / 63 / 72 | 27 / 39 / 47 | 0.8 | 7.0 | 141 / 216 |

**The arithmetic.** A hash of n points is found only if all n survive the room. If a point survives with chance p,
a pair survives with p x p, a triple with p x p x p, a quad with p to the fourth: at p of one half that is 25, 12
and 6 percent. Against that, more points make a hash more particular: a pair's hash has 2 million values, a
triple's 34 billion, so a triple's lookup returns almost nothing but the right song and far fewer hashes are
needed.

**The measurement.** In noise the first effect wins at every level measured, including the room with no crowd
(8 s, about 40 KB a song: twos 93, threes 90, fours 79 and 70). On clean sound all three are at 99 to 100.

**The three questions.**

- *At what noise level do fours stop being worth it?* At the first one. They equal the others on clean sound and
  are behind in the room alone.
- *Do fours for proposing, with the check deciding, beat threes for proposing?* No: 43 against 58 percent at
  equal-level crowd (8 s, 40 KB), and twos for proposing beat both (71).
- *Does a mixed index (a few fours for quick answers on clean sound, pairs behind them) give the best of both?* It
  would give the pairs' accuracy with the fours' speed on clean sound, at the cost of holding both. Since the
  pairs alone answer a clean 8 s listen in about 60 ms and name it every time, there is nothing for the fours to
  add. Not built.

What fours buy is time: the ratio form answers in 27 ms against 62, because it does not try 69 speeds. That
mattered when speed was the condition. It is not now.

### 3.3 The two-point family, and the choice

| Two-point hashes, wide check | KB a song in memory (at 5,000 songs) | clean | room | crowd 10 dB under | crowd at equal level | wrong names per 1,000 | absent songs named per 1,000 | 8 s listen, ms: median / 95th |
|---|---|---|---|---|---|---|---|---|
| **The booth's index**: anchors the strongest half of the points round each, 3 hashes an anchor | 47 (41) | 99 / 99 / 100 | 88 / 93 / 98 | 81 / 91 / 95 | 58 / 71 / 79 | 0.2 | 0.0 | 62 / 102 |
| **The small setting**: the strongest quarter | 28 (21) | 99 / 98 / 99 | 79 / 89 / 95 | 69 / 84 / 90 | 50 / 62 / 73 | 0.3 | 0.0 | 39 / 61 |
| the strongest eighth | 18 (11) | 95 / 99 / 99 | 66 / 80 / 89 | 58 / 74 / 84 | 38 / 52 / 63 | 0.7 | 0.0 | 58 / 86 |
| the strongest half, 2 hashes an anchor | 35 (29) | 98 / 99 / 99 | 81 / 93 / 96 | 74 / 86 / 93 | 53 / 64 / 73 | 0.2 | 0.0 | 64 / 109 |
| the strongest quarter, 6 hashes an anchor | 47 (41) | 99 / 99 / 100 | 88 / 96 / 98 | 82 / 90 / 94 | 61 / 72 / 80 | 0.5 | 0.0 | 229 / 385 |
| every point an anchor, 6 hashes, one hash in 4 kept at random | 47 (41) | 99 / 99 / 99 | 91 / 97 / 99 | 84 / 92 / 95 | 59 / 71 / 80 | 0.0 | 0.6 | 170 / 290 |

- **Nothing measurable is lost** against the first trial at 41 KB a song (the booth's index): it is ahead in every
  noisy cell.
- **The loss is small** at 21 KB a song (the small setting): it equals the first trial, and is 8 points behind the
  booth's index in noise.
- **It breaks gradually** below that: at 11 KB a song the room alone falls to 80 percent at 8 s.
- The last row (anchors at random, six hashes each, the same memory) scores as well or a little better in the room
  and takes nearly three times as long; the time grows with the catalogue, so the three-hash form was kept.
  *[inference: the gain is from the listen's side making twelve hashes an anchor, not six; a cheaper way to get
  it is the first thing to try in section 7.]*

**Why the larger setting is the default.** The target was 100 MB for 5,000 songs (20 KB a song). The small setting
meets it (105 MB) and the chosen one is double (205 MB). I chose the larger because the index is a file opened in
place, which by Apple's account is not charged to the app, and because noise is D35's first worry. If a device
shows the mapped file is a problem, the small setting is `PairingConfig.boothSmall`.

### 3.4 A flaw found on the way

Thinning by "the stronger half of the points" was first done with the fingerprint's fixed strength levels. That
left some passages (dense or quiet music whose points are all modest) with no anchors at all: 11 clean listens in
500 were missed. Anchors are now the strongest share of the points within a second either side, with a fixed
scramble to tell equals apart; the same 500 give 498 right, and 499 with every point an anchor.

### 3.5 Copies of one recording

W3's main finding: against the owner's whole library the first trial named the right song in 42 percent of 8 s
listens where it named 81 percent against the party's discs, because most of that night's songs have a second file
in the library and the confidence compares the best song with the third best. The test asked for, on this
benchmark:

| Index | KB a song in memory | clean | room | crowd 10 dB under | crowd at equal level | wrong names per 1,000 | absent songs named per 1,000 | 8 s listen, ms: median / 95th |
|---|---|---|---|---|---|---|---|---|
| the booth's index | 47 | 99 / 99 / 100 | 88 / 93 / 98 | 81 / 91 / 95 | 58 / 71 / 79 | 0.2 | 0.0 | 80 / 178 |
| with every song present twice and 20 files of six songs joined end to end | 45 | 100 / 100 / 100 | 90 / 95 / 99 | 84 / 92 / 96 | 60 / 72 / 80 | 0.0 | 0.0 | 138 / 254 |
| the same, with the search for copies switched off | 45 | 89 / 89 / 88 | 77 / 82 / 86 | 73 / 78 / 82 | 54 / 65 / 71 | 0.0 | 0.3 | 137 / 250 |

With the copies found, the index with every song twice and 20 long files scores as it does without them. With the
search off, it drops by about 10 points on clean sound. (Each song here has one copy and one in eight is also
inside a joined file; a library with three or more files of a song would fall further without the search, as W3
saw.)

Finding copies from the fingerprints took about 30 s for 969 songs on one core. It grows faster than the catalogue
(more songs, and each match slower): *[inference]* some minutes for 5,000 songs, once per crate file. The crate
file's own keys cost nothing; the search is for crate files without them and for files that contain other songs.

### 3.6 Forgiving a hash that moved one step

Letter AB's item 5. Each of the listen's hashes is also looked up with its time difference one step to either
side (three lookups for one).

| Index | KB a song in memory | clean | room | crowd 10 dB under | crowd at equal level | wrong names per 1,000 | absent songs named per 1,000 | 8 s listen, ms: median / 95th |
|---|---|---|---|---|---|---|---|---|
| the booth's index | 47 | 99 / 99 / 100 | 88 / 93 / 98 | 81 / 91 / 95 | 58 / 71 / 79 | 0.2 | 0.0 | 80 / 178 |
| with each hash also looked up a time step either side | 47 | 99 / 100 / 100 | 90 / 95 / 98 | 85 / 94 / 96 | 61 / 73 / 80 | 0.3 | 0.0 | 163 / 285 |

It earns 2 to 3 points in the room and in noise (8 s: room 93 to 95, crowd 10 dB under 91 to 94, equal level 71
to 73) for twice the time, with no more wrong names. **A small, real gain; off by default.** The time is the
reason: a search already takes a third of a second against 5,000 songs (4.3). Where it fits is the listener's
second look, which runs only when the first names nothing; that pairing is not measured.

## 4. The finished recogniser, measured

As built in `SongListener`: sound fed in tenths of a second, a reading a second from the third second, the
thresholds (sure at 3.0; two listens in a row that agree at 2.6 each) chosen on the dev half, where they gave one
false name in 1,100 no-right-answer clips.

### 4.1 The whole benchmark, eval half (12,300 clips of 12 s)

| condition | clips | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| blend+6 | 500 | 66 / 0.0 | 74 / 0.2 | 78 / 0.2 | 80 / 0.2 |
| blend-6 | 500 | 21 / 0.0 | 28 / 0.0 | 30 / 0.0 | 34 / 0.2 |
| blend0 | 500 | 40 / 0.0 | 50 / 0.0 | 53 / 0.0 | 56 / 0.0 |
| booth(speaker+room+crowd0) | 500 | 43 / 0.0 | 72 / 0.0 | 85 / 0.0 | 93 / 0.0 |
| clean, key held | 2000 | 92 / 0.0 | 99 / 0.1 | 100 / 0.1 | 100 / 0.1 |
| clean, vinyl-style | 1700 | 92 / 0.1 | 99 / 0.2 | 100 / 0.2 | 100 / 0.2 |
| lowpass2000 | 500 | 92 / 0.2 | 98 / 0.2 | 100 / 0.2 | 100 / 0.2 |
| room | 500 | 67 / 0.0 | 87 / 0.0 | 95 / 0.0 | 98 / 0.0 |
| room+blend0 | 500 | 25 / 0.0 | 41 / 0.0 | 48 / 0.0 | 55 / 0.0 |
| room+crowd+10 | 500 | 54 / 0.0 | 78 / 0.0 | 91 / 0.0 | 96 / 0.2 |
| room+crowd+5 | 500 | 43 / 0.0 | 69 / 0.0 | 84 / 0.0 | 91 / 0.0 |
| room+crowd-5 | 500 | 10 / 0.0 | 25 / 0.0 | 41 / 0.2 | 56 / 0.4 |
| room+crowd0 | 500 | 27 / 0.0 | 54 / 0.0 | 71 / 0.0 | 82 / 0.0 |
| room+pink+10 | 500 | 56 / 0.2 | 85 / 0.4 | 93 / 0.4 | 97 / 0.6 |
| room+pink-5 | 500 | 14 / 0.2 | 32 / 0.2 | 52 / 0.4 | 68 / 0.6 |
| room+pink0 | 500 | 33 / 0.4 | 59 / 0.4 | 76 / 0.4 | 87 / 0.4 |
| speaker250-3000 | 500 | 90 / 0.4 | 98 / 0.4 | 99 / 0.4 | 100 / 0.4 |

| no right answer: a song named anyway by | clips | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| noise alone | 100 | 0 | 0 | 0 | 0 |
| song not in the index, clean | 486 | 0 | 0 | 0 | 0 |
| song not in the index, room + crowd 0 dB | 488 | 0 | 0 | 0 | 0 |

A reading took 29 ms at the median, 140 at the 95th percentile, 576 at most (122740 readings).

- "Named by" counts a clip once the right song has been shown at or before that second.
- Three seconds is behind the first trial's single listen (92 against 97 on clean sound) because the listener's
  bar is higher: it takes ten looks at every clip and must not name a song wrongly in any of them.
- From 8 s on it equals the first trial in the room and is ahead in every row with noise, by 2 to 11 points.
- Two songs at once: one of the two is what gets named; the table counts only the louder-or-equal "the song".

### 4.2 Generated mixes (UnmixDB, 360 mixes, 1,149 songs in the index)

| time scaling | effect | songs | seconds with the right name, percent | seconds with a song outside the mix named | first right name, seconds after the song is alone: median / 90th | never named | seconds still named more than 3 s after a song ended (songs followed by another) | speed reading error, points: median / 90th |
|---|---|---|---|---|---|---|---|---|
| none | bass | 90 | 99.3 | 0 of 1898 | 0 / 1 | 0 | 0 (60) | 0.04 / 0.12 |
| none | compressor | 90 | 99.0 | 0 of 1898 | 0 / 2 | 0 | 0 (60) | 0.03 / 0.09 |
| none | distortion | 90 | 76.7 | 0 of 1898 | 0 / 16 | 2 | 21 (60) | 0.07 / 0.23 |
| none | none | 90 | 99.3 | 0 of 1898 | 0 / 1 | 0 | 0 (60) | 0.03 / 0.08 |
| resample | bass | 84 | 99.1 | 2 of 1784 | 0 / 2 | 0 | 2 (57) | 0.04 / 0.13 |
| resample | compressor | 70 | 81.7 | 0 of 1434 | 0 / 0 | 14 | 79 (42) | 0.03 / 0.10 |
| resample | distortion | 84 | 77.0 | 2 of 1784 | 0 / 15 | 4 | 10 (57) | 0.07 / 0.23 |
| resample | none | 84 | 99.4 | 2 of 1784 | 0 / 1 | 0 | 4 (57) | 0.04 / 0.10 |
| stretch | bass | 84 | 99.3 | 0 of 1784 | 0 / 1 | 0 | 10 (57) | 0.05 / 0.15 |
| stretch | compressor | 84 | 99.4 | 0 of 1784 | 0 / 1 | 0 | 18 (57) | 0.04 / 0.12 |
| stretch | distortion | 84 | 77.4 | 0 of 1784 | 0 / 15 | 3 | 10 (57) | 0.08 / 0.25 |
| stretch | none | 84 | 99.4 | 0 of 1784 | 0 / 1 | 0 | 11 (57) | 0.04 / 0.12 |

- Songs brought to another's tempo by more than 16 percent (44 of them, left out of the table) are never named:
  the search stops at 17.
- "Resample" with the compressor is still the odd cell (14 of 70 songs never named, names held past the end): its
  neighbours are at 99 percent, W2 saw the same, and I have not explained it. *[inference: those mixes' labels,
  not the sound.]*
- The few seconds "with a song outside the mix named" are one excerpt of the set that shares sound with another.

### 4.3 Against catalogue size (one core, nothing else running)

Sizes above the 969 real songs are padded with altered copies of real fingerprints (time reversed, pitches moved
round the band), as in W2: a real song's density of points, matching nothing; not more music. A single listen
each, the copy search off for the padding.

| index | songs | index in memory or mapped | the songs' points, read for the check (6 bytes a point, in the same file) | 8 s listen, ms: median / 95th | 12 s | a song not in the index named (3, 5, 8 and 12 s pooled) | right at 8 s, songs in the index |
|---|---|---|---|---|---|---|---|
| the booth's | 1,000 | 48 MB (48 KB a song) | 40 MB | 73 / 115 | 120 / 186 | 0 of 492 | 94 % of 125 |
| the booth's | 2,500 | 108 MB (43 KB a song) | 100 MB | 152 / 283 | 235 / 423 | 0 of 492 | 92 % of 125 |
| the booth's | 5,000 | 205 MB (41 KB a song) | 198 MB | 344 / 614 | 532 / 961 | 0 of 492 | 94 % of 125 |
| the booth's | 10,000 | 403 MB (40 KB a song) | 396 MB | 824 / 1440 | 1269 / 2198 | 0 of 492 | 93 % of 125 |
| the small setting | 5,000 | 106 MB (21 KB a song) | 198 MB | 230 / 353 | 355 / 529 | 0 of 492 | 90 % of 125 |
| the small setting | 10,000 | 204 MB (20 KB a song) | 396 MB | 427 / 745 | 664 / 1106 | 1 of 492 | 88 % of 125 |

- **Right answers and false names do not move with the catalogue**, to 10,000 songs (the right-answer column is
  125 listens a row, so a point or two either way is chance).
- **Time grows in step with the catalogue**: a two-point hash has only 2 million values, so every lookup returns
  more entries as songs are added. A search of 8 s takes a third of a second against 5,000 songs and four fifths of
  a second against 10,000 with the booth's index; the small setting takes about two thirds of that. The owner's
  bar is a name within a few seconds, and the listener searches once a second only while nothing is named (every
  other second while it follows a song, whose own check takes about 10 ms), so 5,000 songs is inside it and 10,000
  is at its edge on this machine's core. Past that, the small setting, or the owner's second step: a crate split so
  that the booth searches the part within reach of the room's tempo.
- **Storage and memory**: the index file holds the table and entries (the first size column) and a copy of every
  song's points for the check (the second): 403 MB in all for 5,000 songs with the booth's index, 304 MB with the
  small one. The copy of the points could be dropped by reading the crate file's own fingerprints in place; not
  built. What the app itself holds while listening is about 2 KB a song (9 MB for 5,000).
- Building the index took 5 s for 1,000 songs and 50 s for 10,000 on one core, the search for copies apart (3.5).

### 4.4 Beside the earlier letters

- **W2 (the first trial)**: section 1's table. Ahead in noise from 8 s, equal on clean sound, a sixth of the memory.
- **Letter H (ShazamKit, 8 s, its own milder room)**: room 49 to 50 of 50, here 95 percent; pink noise at equal
  level 90 to 100 percent, here 76; 5 dB under, 78 to 94 percent, here 52 by 8 s and 68 by 12 s. Still behind in
  loud noise, by less than before.
- **W3 (the real evening, the first trial's matcher)**: the room sat a median 5 dB above the rest at the
  microphone, and by band it scored 90 percent at 8 s where the music was 5 to 10 dB over and 60 where it was 0 to
  5 dB over, which is close to this benchmark's rows for those levels. Nothing here was tuned to that material;
  the copies fix was proved on this benchmark (3.5) and its effect on that library is for the owner's own run.

## 5. What an iPad app must do to use it

Everything is in the shared core (`core/Sources/DeckieRecognition`, with the crate file's side in `DeckieCrate`).
It is plain Swift with Foundation and Dispatch; nothing in it is specific to a platform.

**The calls**

```swift
import DeckieCrate
import DeckieRecognition

// 1. Once per crate file, when the booth opens it (off the main thread: the first time, it builds the index).
let index = try crate.recognitionIndex(cachedAt: catalogFolder.appendingPathComponent("recognition.dkx"))

// 2. For the whole set.
let booth = BoothRecogniser(index: index) { reading in
    // called about once a second, on the recogniser's own thread: hop to the main actor to show it
}

// 3. From the microphone's callback, with whatever arrives (any rate, any piece size, any channel count).
booth.feed(samples, channels: 1, sampleRate: 48000)        // copies and returns at once
```

- `Crate.recognitionIndex(cachedAt:)` (in `DeckieCrate`) gathers the songs that have fingerprints, the crate
  file's own keys for copies of one recording, and a stamp of which songs they are, and calls
  `RecognitionIndex.cached`: that opens the index file in place if it is there and was made from these songs with
  the booth's settings; otherwise it builds the index, writes the file and opens that. Building is the slow step
  (here, on one core: about 5 s for a thousand songs, and about 30 s more for the search for copies among them)
  and happens once per crate file.
- A `ListenReading` says: `state` (`nothingYet`, `named`, `held`), the song's `id` (the crate record's id) and its
  number in the index, `positionSeconds` (where in the song the sound is now), `speedPercent` (the fader),
  `keyLock` (true, false, or nil within 1 % of zero), `confidence`, and how long the reading took.
- `booth.latest` gives the most recent reading from any thread.
- `SongListener` is the same listener without threads (`hear(_:channels:sampleRate:)` returns the readings); the
  tests and `deckie-listen` use it.

**Threading.** `feed` takes a lock for the time of an array append and returns; it never waits for a reading. The
work runs on one serial queue of the recogniser's own, one reading at a time. If readings ever took longer than a
second each, sound would queue up in order and readings would fall behind; nothing is dropped and the caller is
never held. The callback runs on that queue.

**Memory.** Three kinds, counted separately because the system treats them differently:

- *The index file, opened in place* (mapped read-only): the table, the entries and a copy of every song's points.
  The system reads the parts that are touched and may drop them again; Apple describes such memory as "clean" and
  not counted toward an app's limit (letter AB's source: WWDC 2018). Its size is in section 4.3.
- *The app's own memory while listening*: one byte for every 128 ms of every song (the vote table: about 1.7 KB a
  song), 16 bytes a song for where it starts, the songs' ids, and the last 12 s of microphone sound.
- *While building the index* (once per crate file): the whole index in memory, about one and a half times the file.
  If that is too much on an iPad for a very large crate, the index file can be made by Desk and travel with the
  crate file, which is a possible later addition and is not built.

**When to build the index.** When a crate file is opened for the first time or has changed (the stamp says so), in
the background, before the set. Opening an index that exists takes about a millisecond.

**Beside Apple's recogniser, while both exist.** Nothing here touches ShazamKit, and the crate file carries both
`signatures/` and `prints/`. The simplest arrangement: where a crate file has fingerprints, run this listener; keep
the ShazamKit path for crate files that have only signatures (older ones) until Desk has rebuilt them. Running both
on the same microphone and comparing them is the natural way to carry out the real-room test on the device; the
existing `Recognizer` state machine can take this listener's readings in place of ShazamKit's matches (song, place,
and a speed that needs no second match).

**The tool.** `deckie-listen` plays any recording through the same listener as the booth would hear it:

```bash
swift run -c release deckie-listen --prints path/to/Crate.deckiecrate/prints --save-index crate.dkx --audio set.wav
```

It prints a line a second (seconds heard, state, song id, place, speed, key lock, confidence, milliseconds) and ends
with the readings' times and the process's peak memory. `--index crate.dkx` opens an index made earlier. It reads
WAV, AIFF, MP3 and FLAC, or raw 16-bit mono with `--raw RATE`.

## 6. What remains unproven without a device and a loud room

- **A real booth.** Every noisy figure here is a measured room response and recorded crowd noise applied by
  computer. Letter AB's reading of the literature is that real rooms cost 10 to 25 points against simulated ones.
  The owner's test on the Oct 24 recording is the first real evidence and its numbers are not in this letter.
- **The iPad.** None of this has run on one. Unmeasured: the time of a reading on an A-series chip; whether the
  mapped index behaves as Apple describes when lookups jump all over a file of 100 to 400 MB; the memory needed to
  build the index for a large crate; heat and battery over a night; the microphone's automatic gain.
- **macOS and Xcode.** The package builds and passes its tests on Linux and on GitHub's Windows machine. The Mac
  build was not run; the one-line change in the Mac app's `ContentView.swift` (the count behind "can't be
  recognised yet") was not compiled.
- **A real deck's key lock, effects, scratching, loops, a microphone over the music**: not tested. Generated mixes
  with heavy distortion are named for about three quarters of each song's seconds.
- **Speeds beyond ±17 %**: not searched for, by design.
- **A crate of several thousand real songs.** Sizes above the 969 real songs are padded with altered copies of
  real fingerprints. The owner's library run is the check.
- **Patents**: as in letter W2 (listings only). The three-point hashes, the strength rule, the thinning and the
  listener are this work's own; the ratio form of four points was written from Sonnleitner and Widmer's paper and
  is not used.

## 7. What I would try next for loud rooms, in order

1. **Choose a hash's points across pitch bands** (the owner's own point; letter AB's 6b). Today an anchor's three
   targets are the strongest points of three slices of *time*, whatever their pitch, so one loud voice or one loud
   instrument can take all three. Spreading them over bands of pitch as well would keep hashes in the parts of the
   spectrum the noise leaves alone. This is a change to how the index is built from the fingerprint, **not to the
   fingerprint in the crate file**. Expected: most where the noise is a crowd; a few points, unmeasured. A day.
2. **More hashes on the listening side only.** The row with six slices a listen scored 3 to 4 points higher in the
   room at the same memory. Taking the two or three strongest points of each slice from the microphone (the index
   unchanged) should get most of that for a modest cost in time. Half a day.
3. **Gather votes, not only names, across seconds.** The listener now takes two agreeing listens; adding the votes
   of four or five successive listens before the check is the fuller form of letter AB's first item. Expected:
   Wang's rule of thumb is that doubling the sound is worth 3 dB; here 8 to 12 s was worth 11 points at
   equal-level crowd, and 16 to 20 s should bring a good part of the remaining misses. Two days, and the false
   names re-measured.
4. **A second kind of evidence in the check: the beat.** Confirm a proposed song against the crate file's beat grid
   and per-bar pattern at the place and speed proposed (letter H's option C, AB's item 7). It lets the bar for a
   name come down without more wrong names. Needs songs with Deckie's analysis, which the outside set lacks: the
   owner's library, on his computer. A week.
5. **Read higher, to about 5.5 kHz.** This one changes the fingerprint (a version 2 print, every song made again),
   so it comes after the others and only if a measurement says the music stands clearer of a crowd up there. On
   this benchmark's crowd it does not obviously (section 3's band figures). Measure first: a day.
6. **A loud room, recorded.** Everything above is against simulated noise. One recording from a loud booth, scored
   as W3 scored the quiet one, says which of 1 to 5 matters.

## 8. Running it

- The study's rows: `core/Tools/recognition-bench/size_study.py` (`sample`, `run NAME [options]`, `table`), on a
  work folder made by `run.sh` (W2, section 13). The top-K count: `topk.py`. The band levels: `band_levels.py`.
- The listener on the benchmark's clips and on UnmixDB: `listen_eval.py clips`, then `deckie-listen --list …`,
  then `listen_eval.py bench` and `listen_eval.py mixes`.
- The copies test: `size_study.py run WORK BENCH NAME --pairs --anchor-share 0.5 --fan-out 3 --check-songs 50
  --duplicate-all --join 6`.
- Any recording through the booth's listener: `deckie-listen` (section 5).
- Tests: `swift test --filter DeckieRecognitionTests` and `--filter DeckieCrateTests` in `core/`.
