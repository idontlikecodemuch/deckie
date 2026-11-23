# Research S: the booth's first night, the Oct 24 set as recorded

Dated Oct 30, 2026. Measurement and evidence, no decisions. Script `mixer/set_analysis.py`; its per-play and
per-transition rows are kept with the lab's private data (DECKIE_LAB_DATA), as the songs are the DJ's own. The
recordings stay on the recording Mac; nothing here reproduces the music, and the songs are numbered, not named. Tags: [inf] = my inference; [unmeasured] = not measured here.

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

| recording | part of the day | length | entries | | recording | part of the day | length | entries |
|---|---|---:|---:|---|---|---|---:|---:|
| R1 | early | 2:54 | 1 | | R10 | mid-set | 86:03 | 12 |
| R2 | early | 1:47 | 1 | | R11 | mid-set | 1:20 | 0 |
| R3 | early | 113:41 | 9 | | R12 | mid-set | 6:57 | 3 |
| R4 | early | 40:32 | 8 | | R13 | mid-set | 2:40 | 1 |
| R5 | early | 8:15 | 2 | | R14 | mid-set | 27:31 | 8 |
| R6 | mid-set | 5:29 | 2 | | R15 | late | 37:06 | 11 |
| R7 | mid-set | 2:14 | 1 | | R16 | late | 7:52 | 3 |
| R8 | mid-set | 1:28 | 1 | | R17 | late | 110:17 | 8 |
| R9 | mid-set | 3:27 | 0 | | 17 stubs | through the day | 1:31 in all | 0 |

Recorded 7.68 h in all, from set-up to the end of the night. Gaps with no recording: 20, 31, 89, 11, 40, 9 and 3
minutes, in that order. The recorder can pause, and paused audio is not written, so the second and third gaps may be
pauses inside the recording before them [inf: from the files' last-written times].

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

| # | part | song | where | logged (min) | pitch % | kind | conf | audio: booth song / other | BPM: booth / measured |
|---:|---|---|---|---:|---:|---|---:|---|---|
| 1 | early | song 1 | disc | 2.2 | +0.0 | - | 1.00 | 0 / 0 | 116.0 / - |
| 2 | early | song 2 | disc | 6.2 | +0.0 | - | 1.00 | 44 / 2 | 93.0 / 93.4 |
| 3 | early | song 1 (again) | disc | 53.2 | +0.0 | - | 1.00 | 50 / 2 | 116.0 / 109.1 |
| 4 | early | song 3 | disc | 3.5 | +0.0 | - | 1.00 | 37 / 2 | 116.0 / 116.0 |
| 5 | early | song 4 | disc | 7.3 | -3.4 | vinyl | 1.00 | 36 / 10 | 115.9 / 116.0 |
| 6 | early | song 5 | disc | 3.2 | -4.6 | vinyl | 1.00 | 29 / 0 | 116.4 / 116.1 |
| 7 | early | song 6 | disc | 4.0 | -4.8 | vinyl | 1.00 | 46 / 0 | 117.1 / 117.1 |
| 8 | early | song 7 | disc | 4.2 | -4.7 | vinyl | 1.00 | 42 / 0 | 117.2 / 117.1 |
| 9 | early | song 8 | disc | 4.1 | -4.7 | vinyl | 1.00 | 10 / 2 | 118.2 / 118.0 |
| 10 | early | song 9 | disc | 29.1 | -4.8 | vinyl | 1.00 | 44 / 5 | 118.0 / 118.0 |
| 11 | early | song 10 | disc | 2.5 | -4.8 | vinyl | 1.00 | 16 / 1 | 137.1 / 137.1 |
| 12 | early | song 11 | disc | 1.6 | +1.9 | vinyl | 1.00 | 9 / 0 | 137.6 / 137.6 |
| 13 | early | song 12 | disc | 21.2 | -4.7 | vinyl | 1.00 | 29 / 3 | 123.9 / 123.8 |
| 14 | early | song 2 (again) | loose | 5.0 | +0.0 | - | 1.00 | 45 / 0 | 93.0 / 93.1 |
| 15 | early | song 1 (again) | disc | 0.5 | -0.9 | vinyl | 1.00 | 0 / 1 | 115.0 / - |
| 16 | early | song 2 (again) | disc | 0.7 | +0.0 | - | 1.00 | 1 / 0 | 93.0 / 93.5 |
| 17 | early | song 1 (again) | disc | 9.0 | +1.2 | vinyl | 1.00 | 49 / 0 | 117.4 / 117.4 |
| 18 | early | song 13 | loose | 1.5 | +0.0 | - | 0.85 | 10 / 0 | 108.1 / 108.1 |
| 19 | early | song 14 | disc | 6.3 | -4.3 | vinyl | 1.00 | 33 / 0 | 112.9 / 114.8 |
| 20 | mid-set | song 15 | disc | 5.3 | +2.1 | vinyl | 0.49 | 0 / 0 | 122.5 / - |
| 21 | mid-set | song 16 | loose | 2.2 | +0.0 | - | 0.34 | 4 / 0 | 124.0 / 124.2 |
| 22 | mid-set | song 17 | loose | 0.9 | +0.0 | - | 0.85 | 0 / 0 | 70.0 / - |
| 23 | mid-set | song 18 | loose | 2.2 | +0.0 | - | 1.00 | 3 / 0 | 120.0 / 120.1 |
| 24 | mid-set | song 19 | loose | 5.0 | +0.0 | - | 1.00 | 0 / 5 | 123.0 / - |
| 25 | mid-set | song 20 | loose | 4.1 | +0.0 | - | 0.49 | 0 / 11 | 124.0 / - |
| 26 | mid-set | song 21 | loose | 34.1 | +0.0 | - | 0.49 | 0 / 12 | 126.0 / - |
| 27 | mid-set | song 22 | disc | 4.6 | +0.0 | - | 1.00 | 0 / 6 | 155.0 / - |
| 28 | mid-set | song 23 | disc | 3.6 | +0.0 | - | 1.00 | 3 / 6 | 128.0 / 128.0 |
| 29 | mid-set | song 24 | disc | 4.4 | +0.0 | - | 0.49 | 6 / 22 | 130.0 / 130.0 |
| 30 | mid-set | song 25 | disc | 5.6 | +0.0 | - | 1.00 | 25 / 6 | 136.0 / 136.1 |
| 31 | mid-set | song 26 | loose | 8.2 | +0.0 | - | 1.00 | 0 / 21 | 110.0 / - |
| 32 | mid-set | song 27 | loose | 5.8 | +0.0 | - | 0.49 | 11 / 0 | 124.4 / 124.5 |
| 33 | mid-set | song 28 | loose | 4.9 | +0.0 | - | 1.00 | 0 / 9 | 128.0 / - |
| 34 | mid-set | song 29 | loose | 3.6 | +0.0 | - | 0.80 | 0 / 9 | 128.0 / - |
| 35 | mid-set | song 30 | disc | 1.1 | +2.0 | vinyl | 0.85 | 0 / 5 | 130.6 / - |
| 36 | mid-set | song 31 | disc | 2.2 | +1.1 | vinyl | 1.00 | 9 / 0 | 127.4 / 127.4 |
| 37 | mid-set | song 32 | disc | 3.0 | +0.0 | - | 1.00 | 14 / 1 | 126.0 / 126.6 |
| 38 | mid-set | song 23 (again) | disc | 2.3 | +0.9 | vinyl | 1.00 | 6 / 7 | 129.2 / 129.3 |
| 39 | mid-set | song 33 | disc | 3.3 | +2.0 | vinyl | 1.00 | 38 / 5 | 124.4 / 124.4 |
| 40 | late | song 9 (again) | disc | 3.9 | +0.0 | - | 1.00 | 43 / 7 | 124.0 / 123.3 |
| 41 | late | song 4 (again) | disc | 4.7 | +2.2 | vinyl | 1.00 | 41 / 1 | 122.6 / 122.2 |
| 42 | late | song 34 | disc | 2.3 | -2.2 | vinyl | 1.00 | 10 / 0 | 122.2 / 122.4 |
| 43 | late | song 15 (again) | disc | 3.3 | +1.3 | vinyl | 1.00 | 24 / 6 | 121.6 / 118.8 |
| 44 | late | song 35 | disc | 3.3 | +1.3 | vinyl | 1.00 | 36 / 6 | 121.6 / 121.5 |
| 45 | late | song 36 | loose | 2.6 | -0.8 | vinyl | 1.00 | 3 / 1 | 122.0 / 122.0 |
| 46 | late | song 37 | disc | 2.5 | +0.0 | - | 1.00 | 25 / 3 | 122.9 / 121.9 |
| 47 | late | song 38 | disc | 4.5 | -1.8 | vinyl | 1.00 | 22 / 0 | 121.8 / 121.9 |
| 48 | late | song 39 | disc | 3.1 | +0.0 | - | 1.00 | 19 / 0 | 128.0 / 127.0 |
| 49 | late | song 40 | disc | 3.1 | +0.0 | - | 1.00 | 0 / 7 | 128.0 / - |
| 50 | late | song 41 | disc | 7.3 | +3.5 | master tempo | 1.00 | 31 / 11 | 130.7 / 127.2 |
| 51 | late | song 42 | disc | 4.6 | -2.4 | vinyl | 1.00 | 11 / 4 | 126.9 / 127.0 |
| 52 | late | song 43 | loose | 2.2 | +0.0 | - | 1.00 | 2 / 1 | 126.0 / 126.9 |
| 53 | late | song 44 | disc | 2.4 | +1.4 | vinyl | 1.00 | 0 / 2 | 126.8 / - |
| 54 | late | song 45 | disc | 4.0 | +0.0 | - | 1.00 | 6 / 9 | 117.0 / 121.4 |
| 55 | late | song 46 | disc | 2.2 | +5.0 | vinyl | 1.00 | 27 / 0 | 117.6 / 117.6 |
| 56 | late | song 47 | disc | 5.3 | -2.3 | vinyl | 1.00 | 61 / 0 | 121.2 / 121.1 |
| 57 | late | song 48 | disc | 4.4 | +3.1 | vinyl | 1.00 | 6 / 28 | 123.7 / 124.0 |
| 58 | late | song 49 | disc | 1.7 | -1.3 | vinyl | 1.00 | 12 / 1 | 124.4 / 124.2 |
| 59 | late | song 3 (again) | disc | 8.4 | +7.3 | vinyl | 1.00 | 0 / 6 | 124.5 / - |
| 60 | late | song 50 | disc | 7.9 | +7.0 | vinyl | 1.00 | 17 / 18 | 124.3 / 124.4 |
| 61 | late | song 51 | disc | 4.5 | -2.5 | vinyl | 1.00 | 14 / 0 | 136.5 / 136.5 |
| 62 | late | song 52 | disc | 3.1 | +1.3 | vinyl | 1.00 | 38 / 0 | 136.8 / 136.8 |
| 63 | late | song 53 | disc | 4.2 | -2.2 | vinyl | 1.00 | 5 / 0 | 137.0 / 136.7 |
| 64 | late | song 54 | disc | 1.5 | +1.4 | vinyl | 1.00 | 3 / 0 | 139.0 / 138.9 |
| 65 | late | song 55 | disc | 80.0 | -7.4 | vinyl | 1.00 | 3 / 116 | 139.8 / 139.8 |

Minute by minute (a minute counts as music when Beat This finds 40 or more beats in it), and whether the audio
check agrees. Agreement per recording: 93 to 100 percent of identified windows inside a play were on the booth's
song in the early recordings, 84 to 88 in R14 and R15, 46 to 79 in the two short ones between, 31 to
38 in R10, R16 and R17 (all: 1,108 on the booth's song, 380 on another, 74 percent).

| minute class | minutes | share of music minutes |
|---|---:|---:|
| quiet (fewer than 40 beats) | 101 | |
| music | 350 | 100% |
| music, booth's latest entry older than that song's own length plus a minute | 112 | 32% |
| music, booth had shown nothing yet in that recording | 6 | 2% |
| music, audio check finds the booth's song | 135 | 39% |
| music, audio check finds another crate song only | 99 | 28% |
| music, audio check finds no crate song | 116 | 33% |

The long logged plays are of two kinds. Song 1 (53.2 min, play 3), song 9 (29.1, play 10) and song 12
(21.2, play 13) sit over quiet: 48.6, 20.1 and 18.0 unidentified minutes at -61 to -56 dBFS and 4 to 9 beats a
minute (a break, [inf]). Song 21 (34.1, play 26) and song 55 (80.0, the last play) sit over music: -50 to -30
dBFS, 81 to 134 beats a minute, and the booth logged nothing new (its log file was last written at the start of the last play,
while the recording ran on for about 80 minutes).

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
| song 1 (play 3) | 0.0 | none | -6.0 | 109.1 / 116.0 | +3 | booth wrong: vinyl -6 |
| song 41 | +3.5 | master tempo | +0.7 | 127.2 / 130.7 | -1 | booth wrong: +0.7 |
| song 45 | 0.0 | none | +7.5 | 121.4 / 117.0 | 0 | unresolved, 6 windows |
| song 14 | -4.3 | vinyl | -4.1 | 114.8 / 112.9 | +2 | catalogue BPM off [inf] |
| song 15 | +1.3 | vinyl | +1.5 | 118.8 / 121.6 | -1 | catalogue BPM off [inf] |
| five more plays | | | 2.4 to 7.1 | within 0.5 | | alignment noise [inf] |

Kind against the key: on 44 of 46 plays with three or more windows, the key moved as the reading says (by -36 x
log2 of the speed in thirds for vinyl, not at all otherwise). Without the identity check (middle minute of every play
of 70 s or more): vinyl 26 of 30 within 1 percent, none 11 of 22 (most of those minutes were other music [inf]).

## The transitions and the picks

59 song changes in the log (changes across a recording gap of over 10 minutes left out). 43 are clean: both songs
logged a minute or more, and A logged no longer than its own length plus a minute. For each, B's rank among the
picks the booth builds for A (the night's bundled pairs: median 80 stored per source, min 47; filtered as `Mixing.swift`
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

Rank 1 to 3 on the clean set: song 15 to song 35 (1), song 42 to song 43, song 43 to song 44, song 53 to song 54
(2 each). Median score of the picks the DJ played: 0.79.

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

Tempo through the set (10-minute bins in order, with at least 5 music minutes; Beat This median over 30-s pieces of all music;
the booth's BPM time-weighted, each play counted at most its own length plus a minute):

| bin | music min | measured | booth | bin | music min | measured | booth | bin | music min | measured | booth |
|---|---:|---:|---:|---|---:|---:|---:|---|---:|---:|---:|
| 1 | 8 | 93.5 | 98.9 | 2 | 10 | 116.0 | 116.0 | 3 | 10 | 116.6 | 116.7 |
| 4 | 10 | 118.0 | 117.8 | 5 | 6 | 123.8 | 127.4 | 6 | 7 | 93.1 | 96.2 |
| 7 | 6 | 117.4 | 115.8 | 8 | 5 | 113.2 | 112.8 | 9 | 10 | 123.1 | 122.6 |
| 10 | 9 | 128.1 | 125.6 | 11 | 10 | 123.3 | 126.0 | 12 | 9 | 129.1 |  |
| 13 | 10 | 128.5 | 155.0 | 14 | 10 | 130.1 | 131.2 | 15 | 9 | 105.1 | 120.9 |
| 16 | 10 | 125.9 | 125.3 | 17 | 8 | 130.4 | 128.0 | 18 | 8 | 126.7 | 127.4 |
| 19 | 10 | 123.3 | 123.8 | 20 | 10 | 121.6 | 121.9 | 21 | 10 | 122.0 | 122.1 |
| 22 | 10 | 127.2 | 128.7 | 23 | 10 | 127.0 | 128.2 | 24 | 10 | 118.0 | 120.4 |
| 25 | 10 | 122.0 | 122.6 | 26 | 7 | 124.3 | 124.5 | 27 | 10 | 124.5 | 124.3 |
| 28 | 10 | 136.7 | 136.7 | 29 | 10 | 129.8 | 139.0 | 30 | 10 | 128.3 |  |
| 31 | 10 | 127.6 |  | 32 | 10 | 127.6 |  | 33 | 10 | 127.8 |  |
| 34 | 10 | 127.7 |  | 35 | 10 | 128.5 |  | 36 | 10 | 121.6 |  |

## What it says

- **Recognition.** In the early recordings and in two long mid-set to late ones, the audio check and the booth agree
  on 84 to 100 percent of identified windows. In R10 (mostly loose files, five plays at confidence 0.49 or
  0.34) and late in the set they agree on 31 to 38 percent; which of the two is wrong there is not settled [unmeasured].
- **Gone quiet, kept showing.** In 112 of 350 music minutes (32 percent) the booth's latest entry was older than that
  song's own length plus a minute: it had recognised nothing new. That includes 80 minutes of music at the end of the
  night and 34 in a mid-set recording. Whether the screen showed the old song or "listening" the log cannot say (it does not record the
  two-minute clear).
- **Pitch.** Vinyl readings: 29 of 31 within 1 percent, median error 0.06 percent, key movement consistent. Clear
  booth errors: 2 of 50 checked plays (a -6 percent vinyl read as 0, beyond the night's ±4 variants [inf]; a +0.7
  read as +3.5 master tempo, the only master-tempo reading of the night). One more unresolved.
- **Flips.** Three plays under a minute: song 1 (28 s) and song 2 (42 s) early in the day, and song 17
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
- The disagreements in R10 and late in the set: listening to a sample of minutes, or the booth's own debug notes if
  any survive, would say whether the booth or the check is wrong.
- The night's build and settings (Simple or Full, filters, whether "All" was on) are not in the log; the recorder
  could write them.
- The log has no last-heard time and no clear event; adding both would make coverage readable from the log alone.
- Pauses: whether the second and third gaps are pauses is inferred from file times only.
