# Check-ins: the trial of Deckie's own recognition

Branch `trial/own-recognition`. Newest entry first. Nothing here ships without the owner's decision.

## Nov 14, 2026, 17:55 UTC: `recog/fast`, stage 2 (first three sizes): a larger index does not make a name come sooner; the listener does

**The table asked for** (eval half of the outside set, 969 songs in the index, 30 s clips that start at a random
place in a song, a reading every second; "by 5 s" is the share of clips with the right name on screen 5 s after the
sound began)

| Setting | Index, KB a minute of music | Index for 2,000 / 5,000 songs of 4.2 min | Clean | Room | Room, crowd 10 dB under | Crowd at equal level | Crowd 5 dB over | Small speaker, room, crowd equal | After a hard cut, clean | After a hard cut, crowd equal | Wrong song named | Song not in the index named |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `boothSmall` (strongest quarter, 3 hashes) | 5.7 | 57 / 129 MB | 99 % | 84 % | 65 % | 44 % | 22 % | 66 % | 93 % | 31 % | 4 of 1,200 clips | 1 of 217 |
| `booth` (strongest half, 3 hashes) | 11.5 | 105 / 250 MB | 100 % | 92 % | 75 % | 48 % | 26 % | 68 % | 96 % | 31 % | 4 of 1,200 | 0 of 217 |
| strongest three quarters, 3 hashes | 17.3 | 154 / 371 MB | 100 % | 94 % | 78 % | 50 % | 25 % | 76 % | 97 % | 36 % | 0 of 1,200 | 0 of 217 |
| strongest half, 4 hashes | running | | | | | | | | | | | |
| every point, 3 hashes; half, 6; every point, 6 | to come | | | | | | | | | | | |

(Sizes exclude a fixed 8.4 MB table that does not grow with the crate; the megabyte columns include it.)

**The second by which 50 / 75 / 90 % of clips have the right name**

| Setting | Clean | Room | Room, crowd 10 dB under | Crowd at equal level | Crowd 5 dB over | Small speaker, room, crowd equal | Hard cut, clean | Hard cut, crowd equal | One search, ms |
|---|---|---|---|---|---|---|---|---|---|
| `boothSmall` | 3 / 3 / 3 | 3 / 5 / 7 | 4 / 7 / 9 | 7 / 14 / over 30 | 11 / over 30 / over 30 | 4 / 7 / 16 | 5 / 5 / 5 | 7 / 10 / 30 | 120 |
| `booth` | 3 / 3 / 3 | 3 / 4 / 5 | 4 / 5 / 9 | 6 / 11 / 22 | 9 / over 30 / over 30 | 4 / 7 / 11 | 5 / 5 / 5 | 7 / 9 / 30 | 156 |
| three quarters, 3 hashes | 3 / 3 / 3 | 3 / 4 / 5 | 4 / 5 / 9 | 6 / 10 / 21 | 9 / over 30 / over 30 | 4 / 5 / 11 | 5 / 5 / 5 | 6 / 8 / 21 | 205 |

- **Where the bend is, so far**: at `booth`. From small to booth (twice the index) buys 8 to 10 points at 5 s in a
  room; from booth to half as large again buys 2 or 3 points in most columns (8 behind a small speaker) and costs a
  third more search time. The three larger sizes are still running and may move this; I do not expect them to.
- **The spread answers "is 8 seconds right?"**: in a clean or quiet room a name is up at 3 s for half the clips and
  by 5 s for 9 in 10. 3 s is the floor only because the listener does not look before it has 3 s of sound. The
  slow cases are loud crowds (at equal level half the clips take 6 s, a tenth over 20 s) and those are slow at
  every index size.
- **What grows with the setting**: only the index file on the iPad (in step with the number of hashes) and the
  search time. The fingerprint in the crate file (5.8 KB a minute), the app's own memory while listening (0.5 KB a
  minute) and the build's working memory (73 MB) do not.
- **Wrong names**: the 4 at `booth` and small are one pair of clips of a song named as another entry with the
  same artist and title in the outside set's list (two releases of one recording). The larger index's search for
  copies finds that pair and the count goes to 0. So no wrong name here is a different song.

**After a hard cut: the old name stays 4 s, at every size** (clips where one song is cut to another at 15 s)

| Index | Condition | Old song still named after the cut, s: median / 75th / 90th | Still named 5 s after | New song named, s after the cut: median / 75th / 90th |
|---|---|---|---|---|
| `booth` | clean | 4 / 4 / 4 | 4 % | 5 / 5 / 5 |
| `booth` | crowd 10 dB under | 4 / 5 / 5 | 31 % | 5 / 6 / 9 |
| `booth` | crowd equal | 4 / 6 / 7 | 46 % | 7 / 9 / 30 |
| three quarters | clean | 4 / 4 / 4 | 3 % | 5 / 5 / 5 |
| three quarters | crowd equal | 4 / 6 / 7 | 44 % | 6 / 8 / 21 |

  A song from silence is named at 3 s; the same song after a cut at 5 s. The 2 s difference is the listener
  holding the old song (it waits for two failed checks, then searches), and the old name is on screen for 4 of
  those 5 s. That is the lingering the real-room run saw, and it is a listener setting, not an index size. Stage 3
  measures the changes: let go sooner, search every second while following, a 2 s first look.

**Chromaprint baseline**: being measured by the bench now; not in this entry.

**Next**: the remaining sizes (this table is filled in when they finish), then stage 3 (the listener). **Carry on;
and consider that the answer to "faster" is in the listener, not in a larger index.**

## Nov 14, 2026, 16:20 UTC: `recog/fast`, stage 1: the index is built in a fixed memory, and need not copy the songs' points

**Received**: the owner's reading of the morning page (a name sooner; size may grow if it buys something; no
target number until he has seen the spread), the second real-room run (W3, section 13), and the order: the
bounded-memory build first, then the distributions and the size curve, then the listener, then "coming in".
Branch `recog/fast`, cut from `main`. This entry is stage 1; the table the owner asked for comes with stage 2.

**Stage 1: building the index** (the real-room run measured a peak of 0.88 GB to build his library's index on a
Mac, which on an iPad would get the booth closed)

| Songs (outside set's lengths, 3.4 min on average; padded past 969) | Peak memory of the whole process while building | Time, one core | Index file |
|---|---|---|---|
| 2,000 | 73 MB | 17 s | 87 MB |
| 5,000 | 73 MB | 72 s | 205 MB |
| 10,000 | 73 MB | 4.3 min | 403 MB |
| 2,000, with the search for copies | 131 MB (58 of it the finished index's own pages, read in place) | 72 s | 87 MB |

- **How**: one song is held at a time, with the table's counters and a 32 MB buffer of entries; the entries are
  written a run of the table at a time, every song hashed again for each run. A larger crate takes more passes,
  not more memory (so the time grows faster than the crate; a 64 MB buffer halves the passes). The file is byte for
  byte the one the first builder wrote: a test compares them.
- **The songs' points are no longer copied.** Half of the index file was a copy of every song's points for the
  final check. Given the crate file's `prints/` folder, the index now leaves them out and reads a song's own
  fingerprint when it checks that song (the last 256 songs read are kept). The file is then the table alone.
- **Sizes by music, not by song** (the real library averaged 4.2 minutes a song, the outside set 3.4):

| Per minute of music | `booth` | `boothSmall` | Grows with a larger index setting? |
|---|---|---|---|
| Fingerprint in the crate file | 5.8 KB | 5.8 KB | no |
| Index on the iPad's storage, opened in place | 12.2 KB | 6.3 KB | yes, in step |
| (the copy of the points, now left out) | (11.5 KB) | (11.5 KB) | no |
| The app's own memory while listening | 0.5 KB | 0.5 KB | no |

  So for songs of 4.2 minutes: 2,000 songs are a 103 MB index (53 MB small) and 4 MB in the app; 5,000 songs are
  257 MB (133 MB small) and 10 MB in the app.
- **The search for copies is the slow part** on a large crate (55 s for 2,000 songs; it grows faster than the
  crate, *[inference]* about 6 minutes for 5,000 and 25 for 10,000 on this core). It needs no key in the crate
  file, which is how all 355 groups in the owner's library were found. The index can be used before the search
  has run; doing the search afterwards in the background is a small change in the app's order of calls and is
  not built.
- Tests: 13 recognition tests and the crate tests pass on Linux. Not yet run on the two workflows for this branch.

**Next**: stage 2, the spread of seconds to a name (hard cut, blend, by how loud the room is) at each index size.
The 30 s clips for it are made (1,720 on the eval half: starts in six conditions, hard cuts, songs not in the
index) and the baseline is running. **Carry on.**

## Nov 14, 2026, 12:45 UTC: THE MORNING PAGE: song recognition is complete in the shared core

The full account is `docs/research/w4-recognition-complete.md`. Everything is on `main` except this page, the
letter and the last rows, which are on `recog/finish` (cut from `main`).

**What was chosen**

- **One fingerprint per song in the crate file, unchanged from the first trial** (23 KB for four minutes), with a
  version number of its own; every builder writes it on every system.
- **The booth's index: two-point hashes, thin.** Anchors are the strongest half of the points round each; three
  hashes an anchor. 41 KB a song (the first trial: 261). A small setting, 21 KB a song, is one word in the code.
- **Propose widely, decide by a check**: the first 50 songs proposed are checked point by point.
- **Copies count as one**: a second file of a recording, or a long file that contains a song, is found when the
  index is built and never counted against the song. (The real-room test's main finding, fixed and proved on the
  benchmark: with every song in the index twice and long joined files added, the scores do not move.)
- **A listener** that gathers evidence across seconds, follows a named song cheaply and notices the next one.
- **Four points were given a fair trial, two ways, and do not win a place.** At equal memory, at 8 s in a room:
  twos 93 percent, threes 90, fours 79 and 70; at equal-level crowd: 71, 58, 43 and 32. What fours buy is speed
  (no speed search), which is no longer the constraint.

**The table** (969 outside songs, the half no choice was made on; the finished listener, fed second by second;
right song named by that many seconds, percent of clips)

| Condition | 3 s | 5 s | 8 s | 12 s | First trial, one 8 s / 12 s listen |
|---|---|---|---|---|---|
| Clean, any fader setting, either mode | 92 | 99 | 100 | 100 | 100 / 100 |
| A measured room | 67 | 87 | 95 | 98 | 95 / 98 |
| Room, crowd 10 dB under the music | 54 | 78 | 91 | 96 | 89 / 93 |
| Room, crowd at equal level | 27 | 54 | 71 | 82 | 60 / 72 |
| Room, crowd 5 dB over the music | 10 | 25 | 41 | 56 | 33 / 43 |
| Small speaker, room, crowd at equal level | 43 | 72 | 85 | 93 | 79 / 86 |

| Other measures | Result |
|---|---|
| A song that is not in the index named | 0 of 1,074 clips |
| A wrong song named | 0 to 0.6 percent of clips |
| Generated DJ mixes: each song's seconds with the right name on screen | 99 percent (77 under heavy distortion); named the second the song is alone, at the median |
| Fader reading on those mixes | 0.03 to 0.05 points at the median |
| Index, 5,000 songs | 205 MB as a file opened in place (106 MB small setting), plus 198 MB for a copy of the songs' points |
| The app's own memory while listening | about 2 KB a song (9 MB for 5,000) |
| One search of the whole crate, 8 s of sound, one core | 73 ms at 1,000 songs, 344 ms at 5,000, 824 ms at 10,000 (small setting: 230 and 427 ms) |
| A reading while a song is followed | about 10 ms |
| Right answers and false names against catalogue size | unchanged from 1,000 to 10,000 songs |
| Fuzzy lookup (the row owed) | plus 2 to 3 points for twice the time; a small, real gain; off by default |

**What an app must do** (letter, section 5): once per crate file, off the main thread,
`crate.recognitionIndex(cachedAt:)` (builds the index the first time, opens the file in place after); then
`BoothRecogniser(index:) { reading in ... }` for the whole set and `feed(samples, channels:, sampleRate:)` from the
microphone's callback, which copies and returns. A reading a second says named, held or nothing yet, with the
song's id, the place, the fader and key lock. `deckie-listen` plays any recording through the same listener.

**What remains unproven**

- A loud room. Every noisy figure is simulated; the one real evening measured (W3) was a quiet one, and its numbers
  sat close to this benchmark's rows for the same levels. Against letter H's ShazamKit figures in loud noise this
  is still behind (pink noise at equal level, 8 s: 76 percent here, 90 to 100 there in a milder room).
- An iPad: the time of a reading on its chip, the mapped file's behaviour, the memory to build an index, heat.
- A real deck's key lock, effects, scratching; speeds beyond 17 percent (not searched for).
- A crate of thousands of real songs with the copies fix: the owner's library, on his computer.
- 10,000 songs is at the edge for search time on one core here; past that, the small setting or a split crate.
- One cell of the generated mixes (vinyl-style with a compressor) is at 82 percent where its neighbours are at 99;
  not explained.

**What I would try next for loud rooms, in order** (letter, section 7): (1) choose each hash's points across pitch
bands as well as time, the owner's own point, which changes how the index is built and not the crate file; (2)
more hashes on the listening side only; (3) add up votes across four or five listens; (4) the beat grid as a
second check; (5) read up to 5.5 kHz, which would change the fingerprint and so comes last and only if measured to
help; (6) a recording from a loud booth, which says which of these matter.

**Checks.** `recog/core` was green on both workflows before it was merged (`core-linux` 43585502813,
`core-windows` 43585500581, the second including a Windows-built crate file compared with a Linux-built one,
fingerprints and all). `recog/finish` adds an option, tools and documents, and is green on both too (`core-linux` 43595789807,
`core-windows` 43595792133).

## Nov 14, 2026, 11:20 UTC: overnight, entry 2: the design is decided and built; the last measurements are running

This entry replaces what entry 1 said about the design: a late row changed the choice from three-point to
two-point hashes. The morning page will replace this one.

**The design, decided** (every figure: eval half, 969 outside songs, right song named and accepted, percent at
5 / 8 / 12 s; noise levels nominal, in band the crowd is 0.5 dB worse)

| What the booth holds | KB a song (at 5,000 songs) | clean | room | crowd 10 dB under | crowd at equal level |
|---|---|---|---|---|---|
| **Chosen: two-point hashes, the strongest half of the points round each as anchors, 3 hashes an anchor, wide check** | 47 (41) | 99 / 99 / 100 | 88 / 93 / 98 | 81 / 91 / 95 | 58 / 71 / 79 |
| **Small setting: the strongest quarter** | 28 (21) | 99 / 98 / 99 | 79 / 89 / 95 | 69 / 84 / 90 | 50 / 62 / 73 |
| the strongest eighth (where it starts to break) | 18 (11) | 95 / 99 / 99 | 66 / 80 / 89 | 58 / 74 / 84 | 38 / 52 / 63 |
| threes, 1 hash in 4, dense listen, wide check | 40 | 100 / 100 / 100 | 81 / 90 / 95 | 72 / 83 / 90 | 46 / 58 / 69 |
| fours, ratio form, wide check | 40 | 99 / 100 / 100 | 69 / 79 / 85 | 59 / 68 / 76 | 34 / 43 / 50 |
| fours, hashed like threes, 1 in 4, wide check | 40 | 100 / 100 / 100 | 58 / 70 / 79 | 44 / 56 / 63 | 22 / 32 / 39 |
| the first trial (W2), for reference | 261 | 100 / 100 / 100 | 89 / 95 / 98 | 78 / 89 / 93 | 48 / 60 / 72 |

- **Twos beat threes beat fours at equal memory, in every noisy cell.** A hash survives only if all its points do;
  in noise that decides it. What made twos too slow in the first trial was the size of their index, and a thin one
  is fast enough: 62 ms for an 8 s listen here.
- **Fours do not win a place.** Their one gain is speed (the ratio form needs no speed search: 27 ms), which is no
  longer the constraint. They are in the code, off.
- **The small setting matches the first trial at a twelfth of its memory** and meets the 100 MB line for 5,000
  songs (105 MB). **The chosen setting beats the first trial in every noisy cell at a sixth of its memory** (205 MB
  for 5,000 songs). I chose the larger as the default because the index is a file opened in place, which Apple
  describes as not charged to the app, and noise is the first worry in D35; the small one is one word in the code
  (`PairingConfig.boothSmall`) if the device says otherwise.
- **A flaw found and fixed on the way**: choosing anchors by fixed loudness levels left some passages with no
  anchors, and 11 clean listens in 500 were missed. Anchors are now the strongest share of the points within a
  second either side, so every passage keeps its share.
- **Fuzzy lookup and a denser listen**: the denser listen helped thin threes and did nothing for twos at three
  times the time; off. Fuzzy lookup was built as an option and its row was not run after the choice moved to twos;
  not measured.

**Copies of one recording** (the real-room test's main finding). Songs that hold the same sound are found when the
index is built, from the crate file's own keys and from the fingerprints (a second file of a recording; a long
file that contains a song), and never counted against each other. The test asked for, on the benchmark: with every
song present twice and 20 long files of six songs each joined end to end, the index scores 100 / 100 / 100 clean,
90 / 95 / 99 room, 84 / 92 / 96 crowd 10 dB under, 60 / 72 / 80 at equal level: the same as without them. With the
search switched off the same index drops to 89 clean and 82 room at 8 s.

**Built and green.** Branch `recog/core` (cut from `main`, `main` merged in since): the fingerprint in the crate
file with its own version number, every builder writing it, the index file opened in place, the listener and its
non-blocking wrapper, `deckie-listen`. Both workflows are green on it: `core-linux` run 43585502813 and
`core-windows` run 43585500581 (which also compares a Windows-built crate file with a Linux-built one,
fingerprints included). Three earlier runs each failed on a different Desk engine-process test before I made the
fingerprint quicker in unoptimised builds; I did not prove that was the cause.

**Running now**: the generated mixes and the whole eval half through the finished listener; time, memory and false
names at 1,000 to 10,000 songs. **Then**: letter W4 and the morning page.

## Nov 14, 2026, 08:20 UTC: overnight, entry 1: the design is nearly decided; the real thing is half built

**Received**: "Keep this going ... get that song recognition element complete." Nobody to ask until morning, so
each decision is written here with its evidence. Newest entry first; this one will be replaced by the morning page.

**Decisions so far**

1. **The check is widened, and pairs inside a short list are dropped.** The first pass now hands the best two
   proposals of each of its first 50 songs to the point-by-point check (it used to check its 12 fullest votes).
   Evidence (eval half, 969 songs, 5 / 8 / 12 s): crowd at equal level 49 / 61 / 73 % becomes 56 / 68 / 76 %; crowd
   10 dB under, 81 / 89 / 94 becomes 83 / 91 / 95; no wrong name and no absent song named. Matching the short list
   again with two-point hashes took 0.7 s a query as built (re-hashing 50 whole songs) and the point check already
   uses each point singly, so it was not pursued.
2. **A thin index with a dense listen.** The microphone's side takes more points (a smaller neighbourhood, three per
   slice); the songs' side keeps a fraction of its hashes.

| What the booth holds (three-point hashes, wide check) | KB a song | 5,000 songs | room | crowd 10 dB under | crowd at equal level |
|---|---|---|---|---|---|
| the trial's index and check, for reference | 261 | 1.3 GB | 89 / 95 / 98 | 78 / 89 / 93 | 48 / 60 / 72 |
| every hash, wide check | 162 | 0.8 GB | 90 / 95 / 98 | 83 / 91 / 95 | 56 / 68 / 76 |
| 1 hash in 4, dense listen, wide check | 40 | 200 MB | 81 / 90 / 95 | 72 / 83 / 90 | 46 / 58 / 69 |
| 1 hash in 8, dense listen, wide check | 20 | 100 MB | 72 / 83 / 90 | 61 / 74 / 83 | 34 / 49 / 58 |

3. **Four points do not win a place, on the evidence so far.** Same benchmark, same check, equal memory:

| First pass | KB a song | room | crowd 10 dB under | crowd at equal level | 8 s query, ms |
|---|---|---|---|---|---|
| threes, 1 hash in 4 | 40 | 81 / 90 / 95 | 72 / 83 / 90 | 46 / 58 / 69 | 110 |
| fours, ratio form, one a point | 40 | 69 / 79 / 85 | 59 / 68 / 76 | 34 / 43 / 50 | 27 |
| threes, 1 hash in 8 | 20 | 72 / 83 / 90 | 61 / 74 / 83 | 34 / 49 / 58 | 109 |
| fours, ratio form, stronger half of points | 20 | 60 / 69 / 80 | 53 / 63 / 71 | 29 / 37 / 46 | 22 |

   Fours are four times faster (no speed search) and that is all they buy; threes at half the memory beat them in
   every noisy cell. Since speed is no longer the constraint, threes stay. Rows still to come: fours hashed like
   threes, two fours a point, thin pairs.

**Built tonight** (branch `recog/size`, merged into `recog/core`)
- The index as one file, opened in place from storage; built once per crate file and made again only when the
  songs change.
- The listener: fed sound at any rate in any pieces, it gives a reading a second (song, place, speed, key lock,
  confidence, or "nothing yet"), gathers evidence across two listens, follows a named song with one cheap check a
  second and searches the crate every other second to notice a new song. A wrapper for an app never blocks the
  caller. `deckie-listen` plays any recording through it and prints each second.
- First mix played through it: first song named at 3 s, the next song named one second after the first ended, read
  at +8.39 % with key lock on (label: +8.3 %); 10 ms a reading while following, 60 to 90 ms when it searches.
- **The fingerprint is in the crate file and every builder writes it** (`recog/core`): `prints/<id>.dkl` beside
  `signatures/`, a `print` key on the record with its own version number, reader, writer, validator, the single-file
  form, Desk's shared store (a file is fingerprinted once), `deckie-build`, `deckie-make`; "can't be recognised yet"
  now counts songs with neither a fingerprint nor a signature. 121 + 77 + 40 + 6 + 35 tests pass on Linux; both
  workflows are running on the branch.

**Next, in order**: finish the decision table; choose the listener's thresholds on the dev half; run the whole
benchmark and the generated mixes through the listener; letter W4; the morning page.

## Nov 14, 2026, 07:05 UTC: size study, first results; letter AB and the four-point question taken up

**Received**: letter AB (merged and read; its order (a) to (e) is the order I am following), and the owner's
question "Can we use 4 points?" (both forms are built; their rows are being measured now).

**Size, thinning alone** (eval half, 969 songs; right song named and accepted, percent at 5 / 8 / 12 s; noise levels
are nominal, see the last table)

| What the booth holds | KB a song | room | crowd 10 dB under | crowd at equal level | songs not in the index named, per 1,000 |
|---|---|---|---|---|---|
| As in the trial (5-byte entries, short table slots) | 261 | 89 / 95 / 98 | 78 / 89 / 93 | 48 / 60 / 72 | 1.6 |
| 4-byte entries, 32 entries a slot | 162 | 88 / 95 / 98 | 81 / 89 / 94 | 49 / 61 / 73 | 1.9 |
| keep 1 hash in 2 | 81 | 83 / 91 / 95 | 73 / 84 / 91 | 45 / 57 / 68 | 1.6 |
| keep 1 hash in 4 | 40 | 77 / 87 / 92 | 62 / 78 / 86 | 34 / 49 / 57 | 0.6 |
| keep 1 hash in 8 | 20 | 63 / 76 / 85 | 52 / 67 / 76 | 24 / 35 / 45 | 1.6 |
| keep 1 hash in 16 | 10 | 50 / 64 / 74 | 38 / 51 / 62 | 16 / 26 / 32 | 8.2 |

Clean audio stays at 98 to 100 % in every row. The fingerprint in the crate file is unchanged (19 KB a song here).
Fewer hashes per point does worse than dropping hashes at random at the same size (3 a point: 82 KB, room 86 % at
8 s against 91 %). **So: nothing lost down to 162 KB; a small loss at 81; thinning by itself cannot reach the 20 KB
target without a large loss.** Wrong names stay under 1 in 1,000 throughout.

**AB's item (a), the first number**: with the full index, at equal-level crowd noise the right song is the first
proposal 54 % of the time, within the first 10 proposals 67 %, the first 30, 75 %, the first 50, 78 % and the first
100, 82 % (dev half, 5 to 12 s pooled; room: 87 / 92 / 95 / 97 / 98). So a check of 50 songs has about 24 points to
win at that noise. The same count for thin indexes and for four-point hashes is running.

**Four points, built two ways** (from the paper's description; no outside code): hashed like triples with the speed
search; and the ratio form, where the first and last point set a frame and the two between are described as
fractions of it, so there is no speed search. First look only (40 dev clips a condition): the ratio form answers in
about 10 ms and holds 40 KB a song with one quad per point; alone it names every clean clip and loses to triples in
noise (equal-level crowd, first proposal right: about 30 % against 60 %). The fair rows (thin reference, dense
query, pairs as the check, equal memory) are queued.

**Noise both ways** (AB's inference, measured on 200 clips made like the benchmark's): inside the 300 to 3600 Hz
band the fingerprint reads, crowd noise is 0.5 dB worse than its nominal level at the median (dance music: 1.6 dB
worse; one clip in ten, 6.6 dB worse or more) and pink noise is 2.4 dB better. So "0 dB crowd" is about -0.5 dB in
band, not several decibels worse: the crowd recordings carry bass too.

**Running now**: the top-K count for thin triples, pairs and both kinds of fours; the two-step rows (the index
proposes 30 or 50 songs, pairs check them).

**Then**: the three sizes asked for at 2,000, 5,000 and 10,000 songs; fours against triples as proposers; the mixed
index; (c) evidence across seconds and following a named song on the generated mixes; (d) the count of hashes lost
by one step. **Carry on.**

## Nov 14, 2026, 06:05 UTC: the size study has started (branch `recog/size`)

**Received**: D35 (a fingerprint of our own; speed is fine if a song is named in a few seconds; size is the large
problem, smaller first and crate splitting second; noise waits for letter AB). This entry and the ones above it
are on the new branch `recog/size`, cut from `main`.

**The figure being brought down** is what the booth must hold in memory to match: 0.3 MB a song in the trial.

**Target, and why.** A 5,000-song crate matched in under 100 MB of memory: 20 KB a song, about the size of the
fingerprint on disk (19 KB for the outside set's average 3.4-minute song). The booth iPad is also drawing the
screen, listening and scoring picks, and an app that holds hundreds of megabytes is the first one the system closes
when memory is short. The same line puts 2,000 songs at 40 MB and 10,000 at 200 MB.

**How it is being measured.** The same benchmark, eval half only: 12,600 queries (clean, room, room with crowd 10 dB
under and at equal level, and songs not in the index, at 5, 8 and 12 s), each configuration with its own threshold
set on the dev half's no-right-answer clips as before. Memory is counted by the index itself (entries, table, 16
bytes a song). The songs' points are no longer counted as memory: only the final check of a dozen songs reads them,
so they can stay on storage (19 KB a song, read as needed).

**First row**: the trial's configuration holds 261 KB a song by this count and scores as it did (room 95 % at 8 s).

**Being tried, in this order**: 4-byte entries and a smaller table (should lose nothing); fewer hashes per point;
keeping one hash in 2, 4, 8, 16; fewer and stronger points in the songs; and a two-step matcher in which a small
index in memory only proposes a short list of songs and those are matched in full from their points on storage.

**Carry on.**

## Nov 14, 2026, 03:50 UTC: all measurements in; the letter is written

**The report is `docs/research/w2-own-recognition-trial.md`.** Read its section 1 first.

**Done since the last entry**
- **Speed** (the owner's condition). A check tag on every table entry and a table sized to the catalogue: an 8 s
  query on one core now takes 42 ms against 1,000 songs, 73 ms against 5,000 (median; 107 ms at the 95th
  percentile) and 112 ms against 10,000. My target was under 80 ms at 5,000: **met at the median, missed at the
  95th percentile.** Memory is 0.3 MB a song, which an iPad build would have to shrink or map from disk.
- **Catalogue size.** Songs named that are not in the index stay at 0 to 5 in 486 queries from 250 to 10,000 songs;
  right answers stay at 93 to 95 %. Sizes above 969 are padded with altered copies of real constellations, which
  are not more music: the owner's own run on real songs is the check.
- **One command on any music folder**: `MUSIC=/path/to/music core/Tools/recognition-bench/run.sh DATA WORK` writes
  `WORK/results.md`. Songs are named by a hash of their path. Tested here on a folder of 40 songs.
- **DJ mixes.** UnmixDB (360 generated mixes, exact ground truth, 1,149 songs in the index): with one song playing,
  100 % of 8 s windows named in unprocessed, bass-boosted and (bar one cell at 81 %) compressed mixes, 72 to 76 %
  under heavy distortion, and **no wrong song in 25,125 windows**; the key-held fader reading is within 0.03 points
  at the median. The ten real club mixes from Linz could not be fetched (their links now ask for a sign-in).
- **Letter W's comparison**: undoing the speed on the audio gives the same answers as moving the points (850 of 850
  each, clean) at nine times the cost. Dropped.
- **A deeper second pass** gains 3 to 10 points in noise at up to five times the time on hard queries. Kept as an
  option, off by default.
- Both workflows (`core-linux`, `core-windows`) are green on the last commit that changes Swift code (9b3c75b; runs
  43546500230 and 43546502845). Later commits change only scripts and documents.

| The trial in one table (eval half, 969 songs, 8 s unless said) | Result |
|---|---|
| Clean, any fader setting, key held or vinyl-style | 99.9 to 100 % (3 s: 97 to 99.5 %) |
| Room / room + crowd 10 dB under the music / equal / 5 dB over the music | 95 / 89 / 60 / 33 % |
| Wrong song named; a song not in the index named | 0 to 1 in 500; 4 of 1,944 clean, 1 of 1,952 noisy |
| Fader reading: vinyl-style (from pitch); key held | 0.00 median, 0.01 at the 90th percentile; 0.02 to 0.03 median |
| Fingerprint | 23 KB and 0.42 s per four-minute song |
| Against ShazamKit (letter H) | equal on clean audio and the fader with one fingerprint for nine; behind in loud noise (pink noise at equal level: 68 % against 90 to 100 %) |

**What is not done, plainly**
- Phase 3 (ratio fingerprints) was not built: the baseline does not fall short on speed, it falls short on noise,
  and a hash that needs more points to survive is worse in noise. The letter's section 5 gives the measurements.
- No real booth, no real deck's key lock, no real club mix, nothing on a Mac or an iPad.
- The speed target is missed at the 95th percentile, so by the owner's own condition this is **not final**.

**My recommendation** (letter, section 12): put the fingerprint in the crate file now as an addition; keep
ShazamKit as the Apple booth's recogniser until one evening's recording in a real booth says how loud the problem
is; then work on noise. **Carry on, or stop here for the owner's decision: the trial's questions are answered.**

## Nov 14, 2026, 01:25 UTC: the full benchmark has run once, with the fast matcher

**Done since the last entry**
- The matcher is now three-point hashes built from each stretch's strongest points (a strength level kept in two
  spare bits of every point, so the fingerprint is the same size), with the yes-or-no test described last time.
  Two-point hashes are kept in the code for comparison only: they cannot meet the speed condition.
- The whole benchmark ran: 969 songs in the index (109 more held out as "not in the crate"), 17,880 clips, 71,520
  queries. The threshold was set on the dev half; every figure below is the other half.
- Added, not yet run: the index padded to 10,000 songs (running now), any folder of music as the catalogue.

**Numbers** (eval half; "right" = the right song named and accepted; wrong songs named: 0 to 1 in 500 in every row)

| Condition | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| Clean, vinyl-style, every setting -16 to +16 (1,700 queries) | 97.0 | 99.6 | 99.9 | 100 |
| Clean, key held, every setting (1,600) | 99.6 | 99.9 | 99.9 | 99.9 |
| Small speaker (250 to 3000 Hz), or everything above 2 kHz removed | 99 | 100 | 100 | 100 |
| Room (a measured room response) | 76 | 89 | 95 | 98 |
| Room + crowd, music 10 dB over | 63 | 79 | 89 | 93 |
| Room + crowd, music 5 dB over | 43 | 64 | 76 | 85 |
| Room + crowd, equal level | 31 | 48 | 61 | 72 |
| Room + crowd, music 5 dB under | 12 | 22 | 33 | 43 |
| Room + pink noise, equal level | 37 | 54 | 68 | 77 |
| Room + pink noise, music 5 dB under | 15 | 28 | 44 | 57 |
| Small speaker + room + crowd at equal level | 47 | 65 | 79 | 86 |
| Two songs at equal level: one of the two named / both named | 95 / 16 | 99 / 35 | 99 / 48 | 100 / 59 |

| Other measures | Result |
|---|---|
| A song not in the index named anyway, clean | 5 of 1,944 queries, setting aside one held-out clip that is the same track as a clip in the index under another id (named 40 times of 56: the matcher was right about it) |
| Same, in a room with crowd at equal level; and noise alone | 0 of 1,952 (the same-track clip: 3 of 48); 0 of 400 |
| Speed reading, vinyl-style, from pitch (8 s): median / 90th | 0.00 / 0.01 points clean; 0.01 / 0.04 in a room with crowd |
| Speed reading from times (8 s): median / 90th | 0.02 / 0.05 clean vinyl; 0.13 / 0.35 in a room with crowd |
| Key-held reading against Rubber Band's stretch | 0.22 median, but the error grows with the setting and is absent with a second stretcher (ffmpeg: 0.02), so it is that stretcher's own speed, not the reader |
| Vinyl or key-held told apart | every right answer at 2 % and beyond |
| Time to answer, one core, 969 songs (four jobs sharing the machine) | 15 ms for 3 s of audio, 56 ms for 8 s, 90 ms for 12 s, plus 4 to 17 ms to fingerprint the query |

**Against letter H's ShazamKit figures** (8 s; H used 25 songs of one crate, a synthetic reverb and 373 distractors,
so the rooms differ): clean across the fader, equal (H: 25 of 25 with nine signatures a song; here 99.9 % with one).
In its room alone H had 49 to 50 of 50; here 95 %. With pink noise at equal level H had 90 to 100 %; here 68 %. At
5 dB under, H had 78 to 94 %; here 44 %. **So in loud noise this is clearly behind ShazamKit**; the measured rooms
here are harsher than H's reverb, and I cannot say how much of the gap that explains.

**What I think it means.** If the booth iPad hears the monitor 10 dB or more over the crowd, a song is named in 8 to
12 s about nine times in ten at any fader setting, with almost no wrong names. At equal level it takes longer and
misses about three in ten within 12 s. Nobody has measured a real booth's level for this trial; that is the number
that decides whether this is enough.

**Next**
1. Time and false matches against catalogue size to 10,000 (running), against the 80 ms target.
2. One more attempt at noise: a deeper second pass (more of the query's points) used only when the fast pass finds
   nothing, measured for what it gains and costs.
3. The same benchmark with the speed undone on the audio (letter W's comparison).
4. Real DJ mixes (the owner's yes received): Creative Commons mixes and UnmixDB, reported separately.
5. The one-command run on any music folder; the research letter.

**Carry on.** Direction unchanged; the noise gap to ShazamKit is the thing to watch.

## Nov 14, 2026, 00:50 UTC: first booth-condition numbers; the matcher is too slow as built, and what I am doing about it

**Received** (through the orientation session): the owner's yes on real DJ mixes; "it has to be faster before we
finalize it"; timing and false matches wanted against catalogue size up to 10,000 songs; the benchmark must run on
any folder of music from one command. All four are taken up; none is done yet.

**Done since the last entry**
- All outside material fetched (nothing committed): 320 dance and 160 other full songs from the Internet Archive's
  netlabels (Creative Commons, licence recorded per song), 598 two-minute dance clips (GiantSteps+), 417 measured
  room responses (OpenSLR 28), crowd-like noise from three public places (DEMAND). 17,880 twelve-second clips made
  from them (each asked at 3, 5, 8 and 12 s): the speed grid, 15 booth conditions at five speeds, and songs that are
  not in the index.
- Measured on one core, all 1,078 songs: a fingerprint takes 0.10 s per minute of music (0.42 s for four minutes;
  decoding the MP3 takes about as long again) and 96 bytes per second of music (23 KB for four minutes).
- The first full run was stopped: on the full index (969 songs) a query took about 0.6 s on one core, six times the
  pilot's figure, and the time grows with the catalogue. The cause is measured: a two-point hash has too few
  possible values, so each lookup returns about a hundred unrelated songs' entries.
- Two things tried, on a sample of the dev half only (550 clips, the hardest conditions):

| Dev sample, 969 songs, right song named and accepted, percent (3 / 5 / 8 / 12 s) | two-point hashes | three-point hashes |
|---|---|---|
| clean | 100 / 100 / 100 / 100 | 100 / 100 / 100 / 100 |
| room | 95 / 100 / 100 / 100 | 85 / 98 / 98 / 98 |
| room + crowd, music 0 dB over the noise | 45 / 65 / 80 / 83 | 32 / 43 / 60 / 70 |
| room + crowd, music 5 dB under the noise | 18 / 40 / 55 / 68 | 10 / 20 / 32 / 43 |
| room + pink noise, music 5 dB under | 35 / 50 / 65 / 78 | 20 / 38 / 48 / 52 |
| small speaker + room + crowd 0 dB | 60 / 80 / 87 / 95 | 45 / 62 / 70 / 88 |
| two songs at equal level (the other song is named in most of the rest) | 58 / 65 / 68 / 65 | 55 / 63 / 68 / 63 |
| mean time to answer a query, one core | 500 ms | 48 ms (59 ms at 8 s) |

- A better yes-or-no test, also from the dev sample: unrelated dance songs share enough (a kick on every beat puts
  points in the same places) that the plain score is high for a wrong song. A song's score divided by the
  third-best song's score separates much better: on songs absent from the index it never passed 2.9, and nearly
  every right answer is above that. The table above uses it.

**What this means.** Clean and room-only audio is solved at any fader setting. In heavy noise the two-point version
is close to useful but far too slow to ship; the three-point version is fast enough to build on but loses too much
in noise. Neither is the answer yet.

**Speed target I am holding the trial to:** an 8 s query answered in under 80 ms on one desktop core against 5,000
songs (so a booth that asks once a second spends under a tenth of one core), and not growing faster than the
catalogue. The trial is not done while it misses this.

**Doing next, in this order**
1. Phase 3, now justified by measurement: three-point hashes made of ratios (the two pitch differences and the ratio
   of the two time gaps), which do not change with the deck's speed, so one lookup replaces 69 candidate speeds.
   The time saved is spent on more of the query's points, which is what noise needs. From the papers, no code copied.
2. Timing and false matches against catalogue size (hundreds to 10,000), the index padded with altered copies of
   real constellations (time reversed and pitch rotated: statistically like real songs, matching nothing).
3. One command that takes any folder of music as the catalogue and writes a results file.
4. The full benchmark and the comparison with letter H; then the real mixes (Creative Commons mixes, UnmixDB),
   reported separately.

**Carry on**, with a caution: the design is changing under measurement. If ratio hashes do not bring noise results
near the two-point figures at the speed target, the honest result of this trial will be "works for clean and
moderately noisy booths, not for loud ones", and I will say so.

## Nov 13, 2026, 22:40 UTC: phase 1 built, first pilot numbers

**Done**
- `core/Sources/DeckieRecognition` (a new module nothing else depends on) with tests on generated songs that pass on
  Linux (Swift 6.4.1): a landmark fingerprint written from Wang's 2003 paper; an index; a matcher that returns the
  song, the place in it, a score, and the deck's speed two ways (from the times of the matching points, and from their
  pitches).
- The speed trick is done on the query's points, not on its audio: for each candidate speed (1 % apart, to plus and
  minus 17 %, key held and vinyl-style) the points' times and pitches are moved by arithmetic before lookup. No
  resampler or time-stretcher runs in the booth. The speed is then refitted from the matching points.
- A measuring tool and scripts (`core/Tools/recognition-bench`): fetch outside songs, make queries, match, tabulate.
- Research letter W read (fetched from `main`, merged). Of its seven points: (1) logarithmic pitch axis, (2) speed
  copies made from the peaks, (3) speed as the slope of the matching pairs and (6) scoring songs that are not in the
  catalogue were already in the design and are in the code. Still to do, in this order: (2b) the same benchmark
  with the speed change undone on the audio instead, to compare; (4) the checking step against what the crate file
  holds; (7) real DJ mixes (the Creative Commons mixes and UnmixDB), which the letter says need the owner's word, so
  I will not fetch them unless told; (5) time in beats, last, only if a gap remains. The benchmark already gives
  key-held playback the same weight as vinyl-style.

**Pilot numbers** (not the benchmark: 684 songs in the index, of which 153 full Creative Commons dance songs and 531
two-minute dance clips; clean excerpts only, 20 per cell on the eval half; no room, noise or blend yet)

| What | Result |
|---|---|
| Right song, clean, vinyl-style, every setting from -16 to +16 in steps of 2, at 3, 5, 8 and 12 s | 340 of 340 at every length |
| Right song, clean, key held (Rubber Band), same settings | 320 of 320 at every length |
| Right song, key held with a second stretcher (ffmpeg atempo), ±6 and ±12 | 80 of 80 at every length |
| Speed reading, vinyl-style, from pitch: median / 90th percentile error | 0.00 / 0.01 points at every length |
| Speed reading from times, vinyl-style, 8 s: median / 90th / worst | 0.02 / 0.05 / 0.27 points |
| Speed reading from times, key held, 8 s: median / 90th / worst | 0.09 / 0.20 / 0.43 points (does not shrink with length, so part of it may be the stretcher's own timing; to be checked) |
| Vinyl or key-held told apart (settings of 2 % and more) | all |
| A song's fingerprint on disk | 98 bytes a second of music: about 24 KB for four minutes (ShazamKit: about 45 KB) |
| Time to fingerprint a song (decode excluded), four jobs sharing the machine | 0.37 s for the average 2.7 minutes (to be re-timed on one core) |
| Time to answer one query on one core | **0.4 s for 3 s of audio, 1.1 s for 8 s: too slow, the first thing to fix** |

**Patent position from public sources** (Google Patents' listings, which it calls assumptions, not legal conclusions;
not legal clearance): US6990453 (Wang and Smith, the landmark method) is listed expired, adjusted expiry Jan 7, 2024,
with its eight continuations all listed expired by 2022; its European member EP1307833 listed expired Jul 26, 2021.
US7627477 (Wang and Culbert, invariant matching) is listed expired, adjusted expiry Mar 31, 2025; European member
EP1504445 listed expired Apr 18, 2023. No patent by the quad-fingerprint authors was found (search not exhaustive).

**Next**
1. Make the matcher fast (the lookups return far more candidates than needed; several plain remedies to try).
2. The full benchmark: all songs (about 480 full songs plus the 600 clips), room responses, crowd and pink noise,
   small-speaker band, blends, songs absent from the index; threshold chosen on the dev half.
3. Compare with letter H's ShazamKit figures where conditions match.

**Carry on.** Clean audio is solved across the whole fader in both modes from 3 s; the open questions are the booth
conditions, false matches, and the matcher's speed.
