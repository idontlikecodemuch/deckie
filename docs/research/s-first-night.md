# Research S: the booth's first night, the Oct 24 set as recorded

Dated Oct 30, 2026. Measurement and evidence, no decisions. Script `mixer/set_analysis.py`; per-play and
per-transition rows in `mixer/set_oct24_songs.tsv` and `mixer/set_oct24_transitions.tsv`. The recordings stay on the
recording Mac; nothing here reproduces the music. Tags: [inf] = my inference; [unmeasured] = not measured here.

## In plain words

The booth is an iPad app that listens to the room while a DJ plays. It recognises which song from the DJ's own
collection is playing (a recognition: the sound matched against fingerprints made from the DJ's files), reads the
pitch (how far the deck's speed fader is moved from normal, in percent; +3 means 3 percent faster), and shows picks:
songs from the same collection that would mix well next. A pick is judged by tempo (beats per minute, BPM), by key
written in Camelot notation (the 24 keys on a clock face, 1 to 12 with A for minor and B for major; the same number
or one step either way usually sounds right together), and by the mix-out window (the stretch near the end of a song
where it is easiest to leave it for the next one). On vinyl-style decks, speeding up also raises the key; with master
tempo on, the speed changes but the key does not.

The booth also recorded the night. This letter reads that recording back two ways: the booth's own log of what it
recognised, and an independent check of the audio against the collection's files. The principle, said once: report
what the booth did and what the audio says, side by side, and mark guesses. Nothing here is about one DJ; the
questions are the ones any DJ's night would raise.

## The data

35 files `Deck set <date time>.aac` with a log and a tracklist each (deck-app `SetRecorder.swift`). The audio is
mono AAC at 48 kHz. The log holds one entry per song change: the moment the booth switched to a
new song (after its 10-second hold, `Recognizer.swift`), with the last pitch reading and the best confidence of that
song. It does not hold the last moment a song was heard, nor the moment the booth dropped a song after two minutes
without a match; "logged (min)" below is switch to switch. The bundled data that night had three fingerprint
variants per track (normal, vinyl -4, vinyl +4) and the older pitch code (least-squares drift over 20 s, rounded to
0.5); the nine-variant catalogue and median drift fit of stage 1 section 1f came on Oct 28 (commit a40e1a7) [inf:
the committed baseline 88fd48e is the night's build]. 34 files belong to the night (one is from Oct 26); 17 are stubs
under a minute from restarts. Level is low: median -36 dBFS, range -76 to -13 (dBFS: decibels below the loudest
possible sample).

| recording | start | length | entries | | recording | start | length | entries |
|---|---|---:|---:|---|---|---|---:|---:|
| 13-57-06 | 13:57 | 2:54 | 1 | | 20-10-31 | 20:10 | 86:03 | 12 |
| 14-20-20 | 14:20 | 1:47 | 1 | | 21-36-48 | 21:36 | 1:20 | 0 |
| 14-22-43 | 14:22 | 113:41 | 9 | | 21-47-51 | 21:47 | 6:57 | 3 |
| 16-48-07 | 16:48 | 40:32 | 8 | | 21-54-50 | 21:54 | 2:40 | 1 |
| 17-28-42 | 17:28 | 8:15 | 2 | | 21-57-37 | 21:57 | 27:31 | 8 |
| 19-17-25 | 19:17 | 5:29 | 2 | | 22-25-09 | 22:25 | 37:06 | 11 |
| 19-23-00 | 19:23 | 2:14 | 1 | | 23-02-16 | 23:02 | 7:52 | 3 |
| 19-25-19 | 19:25 | 1:28 | 1 | | 23-13-06 | 23:13 | 110:17 | 8 |
| 20-06-45 | 20:06 | 3:27 | 0 | | 17 stubs | 14:22 to 01:03 | 1:31 in all | 0 |

Recorded 7.68 h between 13:57 and 01:03. Gaps with no recording: 20, 31, 89, 11, 40, 9 and 3 minutes (from 14:00,
16:16, 17:37, 19:06, 19:27, 21:38, 23:10). The recorder can pause, and paused audio is not written, so the 16:16 and
17:37 gaps may be pauses inside the recording before them [inf: the files were last written at 16:47 and 19:05].

The audio check: Beat This finds the beats of the recording; each beat gets a 36-bin chroma (the twelve notes in
thirds of a semitone, octaves folded); a window of 32 beats is slid over the same features of every one of the 373
crate files, with the notes rolled up to 5 thirds either way so a vinyl pitch of about 8 percent still lines up; a
hub correction (CSLS, k = 10) stops sustained or loop-like passages from matching everything. A window counts as
identified when the 40-beat paths into and out of it name the same track and its speed (plus or minus 16 percent,
the fader range) fits a key that moved with it (vinyl) or did not (master tempo). No labels and no tuned threshold;
the hub correction's background is windows from these recordings, unlabelled. It also gives the playing speed against the original file and where in the song the music was.

## What the booth heard

65 plays of 55 songs (10 returns), 51 from the discs and 14 loose files; 55 at confidence 1.00. Pitch kind: 36 vinyl,
1 master tempo, 28 none. "Audio windows" counts identified windows inside the play on the booth's song and on another.

| # | clock | song | where | logged (min) | pitch % | kind | conf | audio: booth song / other | BPM: booth / measured |
|---:|---|---|---|---:|---:|---|---:|---|---|
| 1 | 13:57 | Get Lucky | disc | 2.2 | +0.0 | - | 1.00 | 0 / 0 | 116.0 / - |
| 2 | 14:20 | ...Baby One More Time | disc | 6.2 | +0.0 | - | 1.00 | 44 / 2 | 93.0 / 93.4 |
| 3 | 14:27 | Get Lucky (again) | disc | 53.2 | +0.0 | - | 1.00 | 50 / 2 | 116.0 / 109.1 |
| 4 | 15:21 | Levitating | disc | 3.5 | +0.0 | - | 1.00 | 37 / 2 | 116.0 / 116.0 |
| 5 | 15:24 | Break My Soul (The Queens Remix) | disc | 7.3 | -3.4 | vinyl | 1.00 | 36 / 10 | 115.9 / 116.0 |
| 6 | 15:31 | Drop It Like It's Hot | disc | 3.2 | -4.6 | vinyl | 1.00 | 29 / 0 | 116.4 / 116.1 |
| 7 | 15:35 | One More Time | disc | 4.0 | -4.8 | vinyl | 1.00 | 46 / 0 | 117.1 / 117.1 |
| 8 | 15:39 | This Is How We Do It | disc | 4.2 | -4.7 | vinyl | 1.00 | 42 / 0 | 117.2 / 117.1 |
| 9 | 15:43 | Too Close | disc | 4.1 | -4.7 | vinyl | 1.00 | 10 / 2 | 118.2 / 118.0 |
| 10 | 15:47 | Thong Song | disc | 29.1 | -4.8 | vinyl | 1.00 | 44 / 5 | 118.0 / 118.0 |
| 11 | 16:48 | Pony | disc | 2.5 | -4.8 | vinyl | 1.00 | 16 / 1 | 137.1 / 137.1 |
| 12 | 16:50 | GNARLY | disc | 1.6 | +1.9 | vinyl | 1.00 | 9 / 0 | 137.6 / 137.6 |
| 13 | 16:52 | Barbie Girl | disc | 21.2 | -4.7 | vinyl | 1.00 | 29 / 3 | 123.9 / 123.8 |
| 14 | 17:13 | ...Baby One More Time (again) | loose | 5.0 | +0.0 | - | 1.00 | 45 / 0 | 93.0 / 93.1 |
| 15 | 17:18 | Get Lucky (again) | disc | 0.5 | -0.9 | vinyl | 1.00 | 0 / 1 | 115.0 / - |
| 16 | 17:18 | ...Baby One More Time (again) | disc | 0.7 | +0.0 | - | 1.00 | 1 / 0 | 93.0 / 93.5 |
| 17 | 17:19 | Get Lucky (again) | disc | 9.0 | +1.2 | vinyl | 1.00 | 49 / 0 | 117.4 / 117.4 |
| 18 | 17:28 | Everybody (Backstreet's Back) | loose | 1.5 | +0.0 | - | 0.85 | 10 / 0 | 108.1 / 108.1 |
| 19 | 17:30 | Electricity | disc | 6.3 | -4.3 | vinyl | 1.00 | 33 / 0 | 112.9 / 114.8 |
| 20 | 19:17 | Empire State Of Mind | disc | 5.3 | +2.1 | vinyl | 0.49 | 0 / 0 | 122.5 / - |
| 21 | 19:22 | Do It Again | loose | 2.2 | +0.0 | - | 0.34 | 4 / 0 | 124.0 / 124.2 |
| 22 | 19:25 | Demons | loose | 0.9 | +0.0 | - | 0.85 | 0 / 0 | 70.0 / - |
| 23 | 20:10 | Somebody's Watching Me | loose | 2.2 | +0.0 | - | 1.00 | 3 / 0 | 120.0 / 120.1 |
| 24 | 20:12 | Sing It Back | loose | 5.0 | +0.0 | - | 1.00 | 0 / 5 | 123.0 / - |
| 25 | 20:17 | Hot In Herre | loose | 4.1 | +0.0 | - | 0.49 | 0 / 11 | 124.0 / - |
| 26 | 20:21 | Umbrella | loose | 34.1 | +0.0 | - | 0.49 | 0 / 12 | 126.0 / - |
| 27 | 20:55 | vampire | disc | 4.6 | +0.0 | - | 1.00 | 0 / 6 | 155.0 / - |
| 28 | 21:00 | Disturbia | disc | 3.6 | +0.0 | - | 1.00 | 3 / 6 | 128.0 / 128.0 |
| 29 | 21:04 | Lose Control | disc | 4.4 | +0.0 | - | 0.49 | 6 / 22 | 130.0 / 130.0 |
| 30 | 21:08 | Daft Punk Is Playing At My House | disc | 5.6 | +0.0 | - | 1.00 | 25 / 6 | 136.0 / 136.1 |
| 31 | 21:14 | PROBLEMZ | loose | 8.2 | +0.0 | - | 1.00 | 0 / 21 | 110.0 / - |
| 32 | 21:22 | Rhythm Is A Dancer | loose | 5.8 | +0.0 | - | 0.49 | 11 / 0 | 124.4 / 124.5 |
| 33 | 21:28 | American Boy | loose | 4.9 | +0.0 | - | 1.00 | 0 / 9 | 128.0 / - |
| 34 | 21:32 | Blue (Da Ba Dee) | loose | 3.6 | +0.0 | - | 0.80 | 0 / 9 | 128.0 / - |
| 35 | 21:48 | Stranger Things Theme | disc | 1.1 | +2.0 | vinyl | 0.85 | 0 / 5 | 130.6 / - |
| 36 | 21:49 | Goodies | disc | 2.2 | +1.1 | vinyl | 1.00 | 9 / 0 | 127.4 / 127.4 |
| 37 | 21:51 | No Diggity | disc | 3.0 | +0.0 | - | 1.00 | 14 / 1 | 126.0 / 126.6 |
| 38 | 21:55 | Disturbia (again) | disc | 2.3 | +0.9 | vinyl | 1.00 | 6 / 7 | 129.2 / 129.3 |
| 39 | 21:59 | Zombieboy | disc | 3.3 | +2.0 | vinyl | 1.00 | 38 / 5 | 124.4 / 124.4 |
| 40 | 22:03 | Thong Song (again) | disc | 3.9 | +0.0 | - | 1.00 | 43 / 7 | 124.0 / 123.3 |
| 41 | 22:07 | Break My Soul (again) | disc | 4.7 | +2.2 | vinyl | 1.00 | 41 / 1 | 122.6 / 122.2 |
| 42 | 22:11 | In Da Club | disc | 2.3 | -2.2 | vinyl | 1.00 | 10 / 0 | 122.2 / 122.4 |
| 43 | 22:14 | Empire State Of Mind (again) | disc | 3.3 | +1.3 | vinyl | 1.00 | 24 / 6 | 121.6 / 118.8 |
| 44 | 22:17 | Maneater | disc | 3.3 | +1.3 | vinyl | 1.00 | 36 / 6 | 121.6 / 121.5 |
| 45 | 22:20 | Friday (Dopamine Re-Edit) | loose | 2.6 | -0.8 | vinyl | 1.00 | 3 / 1 | 122.0 / 122.0 |
| 46 | 22:23 | We Are Your Friends | disc | 2.5 | +0.0 | - | 1.00 | 25 / 3 | 122.9 / 121.9 |
| 47 | 22:25 | This Is What You Came For | disc | 4.5 | -1.8 | vinyl | 1.00 | 22 / 0 | 121.8 / 121.9 |
| 48 | 22:30 | Look What You Made Me Do | disc | 3.1 | +0.0 | - | 1.00 | 19 / 0 | 128.0 / 127.0 |
| 49 | 22:33 | Put Your Hands Up For Detroit | disc | 3.1 | +0.0 | - | 1.00 | 0 / 7 | 128.0 / - |
| 50 | 22:36 | Call on Me | disc | 7.3 | +3.5 | master tempo | 1.00 | 31 / 11 | 130.7 / 127.2 |
| 51 | 22:43 | Von Dutch | disc | 4.6 | -2.4 | vinyl | 1.00 | 11 / 4 | 126.9 / 127.0 |
| 52 | 22:48 | Abracadabra | loose | 2.2 | +0.0 | - | 1.00 | 2 / 1 | 126.0 / 126.9 |
| 53 | 22:50 | Running Up That Hill | disc | 2.4 | +1.4 | vinyl | 1.00 | 0 / 2 | 126.8 / - |
| 54 | 22:53 | Dancing On My Own | disc | 4.0 | +0.0 | - | 1.00 | 6 / 9 | 117.0 / 121.4 |
| 55 | 22:57 | Pink Pony Club | disc | 2.2 | +5.0 | vinyl | 1.00 | 27 / 0 | 117.6 / 117.6 |
| 56 | 22:59 | Lost In Music | disc | 5.3 | -2.3 | vinyl | 1.00 | 61 / 0 | 121.2 / 121.1 |
| 57 | 23:04 | Monster | disc | 4.4 | +3.1 | vinyl | 1.00 | 6 / 28 | 123.7 / 124.0 |
| 58 | 23:09 | Summertime Sadness (Remix) | disc | 1.7 | -1.3 | vinyl | 1.00 | 12 / 1 | 124.4 / 124.2 |
| 59 | 23:13 | Levitating (again) | disc | 8.4 | +7.3 | vinyl | 1.00 | 0 / 6 | 124.5 / - |
| 60 | 23:22 | Vogue | disc | 7.9 | +7.0 | vinyl | 1.00 | 17 / 18 | 124.3 / 124.4 |
| 61 | 23:30 | I Put A Spell On You | disc | 4.5 | -2.5 | vinyl | 1.00 | 14 / 0 | 136.5 / 136.5 |
| 62 | 23:34 | It Feels So Good | disc | 3.1 | +1.3 | vinyl | 1.00 | 38 / 0 | 136.8 / 136.8 |
| 63 | 23:37 | Born Slippy | disc | 4.2 | -2.2 | vinyl | 1.00 | 5 / 0 | 137.0 / 136.7 |
| 64 | 23:41 | Children | disc | 1.5 | +1.4 | vinyl | 1.00 | 3 / 0 | 139.0 / 138.9 |
| 65 | 23:43 | Midnight Sun | disc | 80.0 | -7.4 | vinyl | 1.00 | 3 / 116 | 139.8 / 139.8 |

Minute by minute (a minute counts as music when Beat This finds 40 or more beats in it), and whether the audio
check agrees. Agreement per recording: 93 to 100 percent of identified windows inside a play were on the booth's
song in the afternoon recordings, 84 to 88 in 21-57-37 and 22-25-09, 46 to 79 in the two short ones between, 31 to
38 in 20-10-31, 23-02-16 and 23-13-06 (all: 1,108 on the booth's song, 380 on another, 74 percent).

| minute class | minutes | share of music minutes |
|---|---:|---:|
| quiet (fewer than 40 beats) | 101 | |
| music | 350 | 100% |
| music, booth's latest entry older than that song's own length plus a minute | 112 | 32% |
| music, booth had shown nothing yet in that recording | 6 | 2% |
| music, audio check finds the booth's song | 135 | 39% |
| music, audio check finds another crate song only | 99 | 28% |
| music, audio check finds no crate song | 116 | 33% |

The long logged plays are of two kinds. Get Lucky (53.2 min from 14:27), Thong Song (29.1 from 15:47) and Barbie
Girl (21.2 from 16:52) sit over quiet: 48.6, 20.1 and 18.0 unidentified minutes at -61 to -56 dBFS and 4 to 9 beats a
minute (a break, [inf]). Umbrella (34.1 from 20:21) and Midnight Sun (80.0 from 23:43) sit over music: -50 to -30
dBFS, 81 to 134 beats a minute, and the booth logged nothing new (its log file was last written at 23:44 while the
recording ran to 01:03).

Booth lag: from the audio check's first identified window on a new song to the booth's entry for it, median 15 s,
quartiles 1 to 33 s (41 changes). The audio check itself needs 32 beats (about 15 s), so this is the booth against
the check, not against the true start.

## The pitch reading against the audio

Two measures of what played: tempo by Beat This over identified windows of the booth's song (a regression of beat
time on beat index, octave-folded; Beat This's known error is the octave, half or double tempo, none seen here), and
speed from aligning the recording's beats with the original file's. The booth reading is catalogue BPM x (1 + pitch).

| pitch kind | plays checked | median error, tempo | within 1 % | over 1 % | median error, alignment | within 1 % |
|---|---:|---:|---:|---:|---:|---:|
| vinyl | 31 | 0.06 % | 29 | 2 | 0.09 % | 29 |
| master tempo | 1 | 2.69 % | 0 | 1 | 2.84 % | 0 |
| none (pitch 0) | 18 | 0.28 % | 16 | 2 | 0.52 % | 13 |
| all | 50 | 0.09 % | 45 | 5 | 0.13 % | 42 |

Over 1 percent by either measure, with the reading of each:

| song | booth % | kind | alignment % | tempo meas. / booth | key roll (thirds of a semitone) | reading |
|---|---:|---|---:|---|---:|---|
| Get Lucky (14:27) | 0.0 | none | -6.0 | 109.1 / 116.0 | +3 | booth wrong: vinyl -6 |
| Call on Me | +3.5 | master tempo | +0.7 | 127.2 / 130.7 | -1 | booth wrong: +0.7 |
| Dancing On My Own | 0.0 | none | +7.5 | 121.4 / 117.0 | 0 | unresolved, 6 windows |
| Electricity | -4.3 | vinyl | -4.1 | 114.8 / 112.9 | +2 | catalogue BPM off [inf] |
| Empire State Of Mind | +1.3 | vinyl | +1.5 | 118.8 / 121.6 | -1 | catalogue BPM off [inf] |
| Baby, Lose Control, Daft Punk, In Da Club, Born Slippy | | | 2.4 to 7.1 | within 0.5 | | alignment noise [inf] |

Kind against the key: on 44 of 46 plays with three or more windows, the key moved as the reading says (by -36 x
log2 of the speed in thirds for vinyl, not at all otherwise). Without the identity check (middle minute of every play
of 70 s or more): vinyl 26 of 30 within 1 percent, none 11 of 22 (most of those minutes were other music [inf]).

## The transitions and the picks

59 song changes in the log (changes across a recording gap of over 10 minutes left out). 43 are clean: both songs
logged a minute or more, and A logged no longer than its own length plus a minute. For each, B's rank among the
picks the booth builds for A (`deck_data.json` pairs: median 80 stored per source, min 47; filtered as `Mixing.swift`
does: one cut per song, not recently played, discs only by default, leaving a median 36). On screen, Simple mode
shows 2 Easy picks sampled from the top band and 1 Harder pick, then up to 12 "More" rows best first; Full shows 3
and 2. The chance B was on screen comes from replaying the app's sampler 2,000 times.

| measure | all 59 | clean 43 |
|---|---:|---:|
| B among the disc-filtered picks, any rank | 35 (59%) | 28 (65%) |
| rank 1 to 3 | 6 | 4 |
| rank 4 to 10 | 9 | 8 |
| rank 11 to 15 | 5 | 4 |
| rank over 15 | 15 | 12 |
| not among them (B loose / B on a disc but not in A's stored pairs) | 24 | 15 (4 / 11) |
| among all picks with every filter on, rank 1 to 15 | 18 | 14 |
| expected on the first screen, Simple (sum of chances) | 4.4 (7%) | 3.3 (8%) |
| expected on the first screen, Full | 7.0 (12%) | 5.2 (12%) |
| expected on the first screen or in More, Simple | 19.3 (33%) | 15.2 (35%) |

Rank 1 to 3 on the clean set: Empire State Of Mind to Maneater (1), Von Dutch to Abracadabra, Abracadabra to Running
Up That Hill, Born Slippy to Children (2 each). Median score of the picks the DJ played: 0.79.

| clean transitions | same | neighbour | relative | boost (+2) | other |
|---|---:|---:|---:|---:|---:|
| Camelot, catalogue keys | 1 | 6 | 3 | 1 | 32 |
| Camelot, keys moved by the vinyl pitch (whole semitones) | 1 | 6 | 4 | 1 | 31 |

| tempo change A to B (played, octave-folded), clean | under 1 % | 1-3 % | 3-6 % | 6-10 % | 10 % or more | median |
|---|---:|---:|---:|---:|---:|---:|
| transitions | 24 | 11 | 5 | 1 | 2 | 0.8 % |

Play lengths from the audio check (runs of a minute or more on one song, 57 runs; 63 shorter runs left out): heard
median 2.1 min, quartiles 1.4 to 3.2; the booth's switch-to-switch span median 4.0 min. Last identified place in the
song, median 0.85 of its length. Against the mix-out window: left before it 30, inside it 19, after it 4, to the end
4. For the clean transitions: before 23, inside 11, after 1, to the end 3, unknown 5. The check loses the outgoing
song once the next one dominates, so "left at" reads early [inf].

Tempo over the night (10-minute bins with at least 5 music minutes; Beat This median over 30-s pieces of all music;
the booth's BPM time-weighted, each play counted at most its own length plus a minute):

| from | music min | measured | booth | from | music min | measured | booth | from | music min | measured | booth |
|---|---:|---:|---:|---|---:|---:|---:|---|---:|---:|---:|
| 14:20 | 8 | 93.5 | 98.9 | 15:20 | 10 | 116.0 | 116.0 | 15:30 | 10 | 116.6 | 116.7 |
| 15:40 | 10 | 118.0 | 117.8 | 16:50 | 6 | 123.8 | 127.4 | 17:10 | 7 | 93.1 | 96.2 |
| 17:20 | 6 | 117.4 | 115.8 | 17:30 | 5 | 113.2 | 112.8 | 20:10 | 10 | 123.1 | 122.6 |
| 20:20 | 9 | 128.1 | 125.6 | 20:30 | 10 | 123.3 | 126.0 | 20:40 | 9 | 129.1 |  |
| 20:50 | 10 | 128.5 | 155.0 | 21:00 | 10 | 130.1 | 131.2 | 21:10 | 9 | 105.1 | 120.9 |
| 21:20 | 10 | 125.9 | 125.3 | 21:30 | 8 | 130.4 | 128.0 | 21:50 | 8 | 126.7 | 127.4 |
| 22:00 | 10 | 123.3 | 123.8 | 22:10 | 10 | 121.6 | 121.9 | 22:20 | 10 | 122.0 | 122.1 |
| 22:30 | 10 | 127.2 | 128.7 | 22:40 | 10 | 127.0 | 128.2 | 22:50 | 10 | 118.0 | 120.4 |
| 23:00 | 10 | 122.0 | 122.6 | 23:10 | 7 | 124.3 | 124.5 | 23:20 | 10 | 124.5 | 124.3 |
| 23:30 | 10 | 136.7 | 136.7 | 23:40 | 10 | 129.8 | 139.0 | 23:50 | 10 | 128.3 |  |
| 00:00 | 10 | 127.6 |  | 00:10 | 10 | 127.6 |  | 00:20 | 10 | 127.8 |  |
| 00:30 | 10 | 127.7 |  | 00:40 | 10 | 128.5 |  | 00:50 | 10 | 121.6 |  |

## What it says

- **Recognition.** In the afternoon and from 21:57 to 23:02, the audio check and the booth agree
  on 84 to 100 percent of identified windows. In 20-10-31 (mostly loose files, five plays at confidence 0.49 or
  0.34) and after 23:00 they agree on 31 to 38 percent; which of the two is wrong there is not settled [unmeasured].
- **Gone quiet, kept showing.** In 112 of 350 music minutes (32 percent) the booth's latest entry was older than that
  song's own length plus a minute: it had recognised nothing new. That includes 80 minutes of music after 23:44 and
  34 after 20:21. Whether the screen showed the old song or "listening" the log cannot say (it does not record the
  two-minute clear).
- **Pitch.** Vinyl readings: 29 of 31 within 1 percent, median error 0.06 percent, key movement consistent. Clear
  booth errors: 2 of 50 checked plays (a -6 percent vinyl read as 0, beyond the night's ±4 variants [inf]; a +0.7
  read as +3.5 master tempo, the only master-tempo reading of the night). One more unresolved.
- **Flips.** Three plays under a minute: Get Lucky (28 s) and ...Baby One More Time (42 s) at 17:18, and Demons
  (54 s, the end of a recording).
- **Picks.** On the clean transitions the song the DJ played next was somewhere in the booth's disc picks 65 percent
  of the time, in the top 15 (the first screen plus More) 37 percent, in the top 3 9 percent; the sampled first
  screen would have shown it about 8 percent of the time in Simple, 12 in Full. In plain words for the product: the
  booth's list usually contained the DJ's next song, but rarely near the top, and the screen as built that night
  would have shown it about one change in twelve. Most misses were of rank; 11 of the 15 outright misses were disc
  songs the stored list for A did not hold.
- **The DJ against the scoring** [inf]: key relations were "other" on 32 of 43 clean changes, tempo changes were small
  (24 under 1 percent, median 0.8), and A was mostly left before or inside its mix-out window, rarely played out.
  The catalogue keys are lab estimates (letter R: 74 to 83 percent exact), so the key share is soft.

## Open items

- Blend span and length per transition (task item 5) not measured: the check names one song per window, so two
  songs at once is not seen [unmeasured]. A two-best-paths version of the matcher would give it.
- The disagreements in 20-10-31 and after 23:00: listening to a sample of minutes, or the booth's own debug notes if
  any survive, would say whether the booth or the check is wrong.
- The night's build and settings (Simple or Full, filters, whether "All" was on) are not in the log; the recorder
  could write them.
- The log has no last-heard time and no clear event; adding both would make coverage readable from the log alone.
- Pauses: whether the 16:16 and 17:37 gaps are pauses is inferred from file times only.
