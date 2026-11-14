# Research W2: the trial of Deckie's own recognition

Dated Nov 14, 2026. The report of the trial asked for after D29: song recognition that Deckie owns, in the shared
Swift core, measured. Branch `trial/own-recognition`. Nothing here ships without the owner's decision. Facts are
measurements from this trial unless a source is named; anything marked *[inference]* is my reading. Companion
letters: H (ShazamKit across the fader), W (the web research for this trial), L (off Apple's platforms).

## 1. Summary

**What was asked.** Recognition of Deckie's own that Desk can make on any computer and the booth can match, across
the whole pitch fader, with measurements.

**What exists now.** A fingerprint, an index and a matcher in plain Swift (`core/Sources/DeckieRecognition`), tests
that pass on Linux and Windows, and a benchmark that runs from one command on outside music or on any folder of
music. One fingerprint per song, 23 KB for four minutes, made in 0.4 s on one core.

**What the measurements say** (969 outside songs in the index, 85 % of them dance music; every figure is from
the half of the set that no choice was made on):

- **Clean audio, any fader setting, either mode: solved.** From 8 s of audio the right song is named 99.9 to 100 %
  of the time at every setting from -16 to +16 %, key held or vinyl-style; from 3 s, 97 to 99.5 %. A small
  speaker's band changes nothing.
- **The fader is read from one listen.** Vinyl-style: within 0.01 points nine times in ten (from pitch). Key held:
  within 0.02 to 0.03 points at the median against two stretchers (ffmpeg's and sox's), 0.15 at the 90th
  percentile on generated mixes. The two modes were told apart every time at 2 % and beyond.
- **Wrong names are rare.** A wrong song was named in 0 to 1 of 500 queries in every condition; a song that is not
  in the index was named in 4 of 1,944 clean queries (all at 12 s) and 1 of 1,952 noisy ones.
- **A room costs a little, loud noise costs a lot.** In a measured room: 95 % at 8 s. With crowd noise 10 dB under
  the music: 89 % at 8 s, 93 % by 12 s. At equal level: 60 % at 8 s, 72 % by 12 s. With the music 5 dB under the
  noise: 33 % and 43 %.
- **Against ShazamKit (letter H): equal on clean audio with one fingerprint a song where ShazamKit needs nine;
  behind it in loud noise** (pink noise at equal level, 8 s: 68 % here, 90 to 100 % there; 5 dB under: 43 % against
  78 to 94 %). The rooms differ (H used a mild synthetic reverb), so the size of the gap is not settled.
- **Generated DJ mixes (UnmixDB, 360 mixes): 100 % of 8 s windows with one song playing when the mix is unprocessed,
  bass-boosted or (bar one cell) compressed; 72 to 76 % under heavy distortion; no wrong song named in any of
  25,125 windows.** Real club recordings could not be obtained (section 6).
- **Speed, the owner's condition.** One core of this machine (a 2.3 GHz server core), 8 s of audio: 42 ms against
  1,000 songs, 73 ms against 5,000 (median; 107 ms at the 95th percentile), 112 ms against 10,000. The target I set
  was under 80 ms at 5,000: **met at the median, missed at the 95th percentile.** Memory is the larger problem:
  0.3 MB a song.

**What it means.** For a booth where the iPad hears the monitor well above the crowd, this would name the song and
read the fader within about ten seconds, on any platform, from a crate file a PC can write. For a booth where the
crowd is as loud as the music at the microphone, it would miss about three songs in ten within 12 s, where
ShazamKit by letter H's figures misses few. Nobody has measured which of those a real booth is.

**Recommendation** (section 12): take the fingerprint into the crate file now as an addition (it is small, cheap and
what a PC-made crate file needs), keep ShazamKit as the booth's recogniser on Apple devices while a real booth
recording decides the noise question, and spend the next effort on noise, not on speed tolerance, which is done.

## 2. What was built

Everything is in `core/Sources/DeckieRecognition` (a module nothing else in the package depends on), its tests in
`core/Tests/DeckieRecognitionTests` (generated songs only), the measuring tool `core/Sources/deckie-recog-bench`, and
the benchmark's scripts in `core/Tools/recognition-bench`. It is plain Swift with Foundation; it uses the core's
existing transform (`RealFFT`) and resampler. It was written from the papers; no outside code was copied or linked.

**The fingerprint** (`Landmarks`). Terms: a **spectrogram** is a picture of sound with time across and pitch up the
side; a **peak** (here also "point") is a spot in it louder than everything around it; a song's **constellation** is
the list of its peaks. This is the first half of Wang's 2003 paper.

- The audio is brought to mono at 8 kHz (what a telephone keeps; the band a small speaker and a room pass).
- A spectrogram is made with a 0.128 s window every 16 ms.
- A point is kept when it is the loudest within 96 ms either side and within 12 % of its own frequency either side,
  between 300 and 3600 Hz. The neighbourhood is the same musical width everywhere, so the same points are chosen
  when the deck's speed moves every frequency by one factor. On the outside songs this gives 32 points a second.
- Each point is stored as its time (16 ms steps), its pitch on a **logarithmic axis** (1/4096 of an octave, read
  between the transform's bins by fitting a parabola), and a **strength** level from 0 to 3 (how far it stands above
  the average of its own neighbourhood; the four levels are the quartiles measured on dev songs).
- On disk a point is about three bytes: 96 bytes per second of music.

**The index** (`RecognitionIndex`). Built in memory from the constellations when a crate file is opened; nothing but
the constellation is kept on disk, so how points are combined can change without touching a crate file.

- Each point (the **anchor**) is combined with later points in a "target zone" from 64 ms to 2 s after it and within
  an octave either way, as in the paper. The zone is cut into six equal slices of time and the strongest point of
  each slice is taken.
- A **hash** is a number made from a small group of points, used to look the group up. The paper hashes pairs (two
  pitches and the time between). Here the default is **three points**: the anchor with the points of two
  neighbouring slices (two pitch differences, the anchor's pitch, two time differences). Section 4 says why.
- Six hashes per point. In memory the index took 291 MB for 969 songs of 3.4 minutes on average: 0.3 MB a song
  (5 bytes a hash, 6 a point, and the table).

**The matcher** (`Recogniser`).

1. *The speed trick, on the points.* For each candidate deck speed (1 % apart to plus and minus 17 %, once with the
   key held and once vinyl-style: 69 candidates) the query's points are moved by arithmetic (times multiplied by
   the speed; for vinyl-style, pitches lowered by the same factor) and hashed. No audio is resampled or stretched.
2. *Voting*, as in the paper: every hash found in the index votes for (song, offset into it); matches of the true
   song pile up at one offset.
3. *Checking.* The best dozen (speed, song, offset) votes are each checked against that song's own points: every
   query point is carried to where the fit says it should be in the song, and counts if the song has a point there
   (within 32 ms and 0.85 % in pitch). The fit is then refined from the points that paired up: a straight line
   through their times gives the **tempo ratio** (the deck's speed), the median of their pitch differences gives the
   **pitch ratio**. This is letter W's "slope of the matching pairs".
4. *The answer*: the song, where in it the query starts, the two ratios (equal on a turntable; pitch ratio 1 when
   the deck holds the key, so the two together say which mode the deck is in), and a **confidence**: the song's
   count of paired points over the third-best song's. Two songs may truly be playing; a third never is.


## 3. How it was measured

**The rule followed** (D5, library-blind). No value was fitted to any DJ's music; the owner's music was not used or
asked for. Outside songs were split by a hash of their id: one in ten **absent** (left out of the index, so their
queries have no right answer), the rest half **dev** and half **eval**. Three things were chosen by measurement, all
on dev only: the confidence threshold; the four strength levels (the quartiles on a sample of 58 dev songs); and
the choice of three-point over two-point hashes and of the strongest point over the first (on a sample of 550 dev
clips, section 5). Every table in section 4 is eval. Everything else is from the paper or a first principle
stated in the code beside the value.

**The material** (fetched by `fetch_data.py`; none of it is committed):

| bucket | songs | hours | median length | dev / eval / absent |
|---|---|---|---|---|
| dance | 320 | 28.4 | 5.1 min | 141 / 157 / 22 |
| other | 160 | 11.8 | 4.2 min | 64 / 76 / 20 |
| gsplus | 598 | 19.9 | 2.0 min | 265 / 266 / 67 |

- **dance, other**: full songs from the Internet Archive's netlabels collection, one per release, 3 to 9 minutes,
  picked by the release's own subject tags (dance: techno, house, drum and bass, trance, electro, breakbeat, minimal,
  disco), each under the Creative Commons licence its release states. 4.82 GB.
- **gsplus**: GiantSteps+ EDM Key Dataset audio (Zenodo 1095691), two-minute excerpts of commercial dance tracks;
  annotations CC BY-SA 4.0, audio used for internal evaluation only, as letter R did. 0.86 GB.
- So 918 of the 1,078 pieces are dance music (85 %); by hours, 48 of 60.
- **Rooms**: 417 measured room impulse responses (the sound of a clap in a real room, which can be applied to any
  audio) from OpenSLR 28, the real rooms only (Apache 2.0). 0.84 GB.
- **Noise**: DEMAND (Zenodo 1227121, CC BY 4.0), recordings in a cafeteria, a restaurant and a station, as the
  nearest public thing to a crowd; and pink noise (noise with equal power in every octave), generated.
- **Mixes**: UnmixDB (Zenodo 1422385, CC BY-NC-ND 4.0), sets 222 and 275: 71 track excerpts and 360 generated
  mixes, 0.64 GB.

Licences of the Internet Archive songs, as each release states:

| licence | songs |
|---|---|
| CC BY-NC-ND 3.0 | 152 |
| CC BY-NC-SA 3.0 | 72 |
| CC BY-NC-ND 4.0 | 36 |
| CC0 / public domain | 31 |
| CC BY-SA 3.0 | 21 |
| CC BY-NC 3.0 | 21 |
| CC BY-NC-SA 4.0 | 20 |
| CC BY-NC-ND 2.0 | 17 |
| CC BY-ND 3.0 | 14 |
| CC BY-ND-NC 1.0 | 13 |
| CC BY-NC-SA 2.0 | 11 |
| CC BY-NC-SA 2.5 | 11 |
| CC BY-ND 4.0 | 11 |
| CC BY-NC 2.5 | 11 |
| CC BY-NC 4.0 | 10 |
| CC BY-NC-ND 2.5 | 9 |
| CC BY 3.0 | 8 |
| CC BY-ND 2.0 | 5 |
| CC BY 2.5 | 2 |
| CC BY-SA 4.0 | 1 |
| CC BY-ND 2.5 | 1 |
| CC BY 2.0 | 1 |
| CC BY-NC-SA 1.0 | 1 |
| CC BY-NC 2.0 | 1 |

**The queries.** 17,880 clips of 12 s, each asked at its first 3, 5, 8 and 12 s (71,520 queries), so "how long until
the song is named" is read off one listening start. 100 clips per cell on eval, 40 on dev.

- *Speed.* Vinyl-style by resampling; key held by time-stretching with Rubber Band, and for four settings also with
  ffmpeg's `atempo`, a different kind of stretcher. Settings -16 to +16 % in steps of 2.
- *Booth conditions*, each at five speeds (0, vinyl +12 and -6, key held +12 and -6: letter H's five): a room; room
  with crowd noise at +10, +5, 0 and -5 dB (the music's level over the noise's); room with pink noise at +10, 0 and
  -5 dB; a small speaker's band (250 to 3000 Hz); everything above 2 kHz removed; speaker, room and crowd at 0 dB
  together; a second song mixed in at +6, 0 and -6 dB, and at 0 dB in a room.
- *No right answer.* Clips of absent songs, clean and with room and crowd; crowd noise and pink noise alone.

**Right, wrong, none.** A query is *right* when the best song is the true one and its confidence reaches the
threshold; *wrong* when another song reaches it; *none* otherwise. The threshold (2.96) is the value that 99.9 % of
the 4,400 dev queries with no right answer stay under.

**One oddity in the outside set.** One held-out dance clip is the same track as a clip in the index under another
id. The matcher named it 42 times in 104, correctly. It is counted apart from "songs not in the crate" (the tool
finds such a song by its behaviour: over half of its clean queries name one same song).

## 4. Results (eval half, 969 songs in the index, the default matcher)

### 4.1 Clean audio across the fader: right / wrong, percent

Vinyl-style (time and pitch together):

| fader % | n | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| -16 | 100 | 95 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| -14 | 100 | 95 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| -12 | 100 | 90 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -10 | 100 | 93 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| -8 | 100 | 94 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| -6 | 100 | 96 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -4 | 100 | 97 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -2 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +0 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +2 | 100 | 97 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +4 | 100 | 98 / 1 | 100 / 0 | 100 / 0 | 100 / 0 |
| +6 | 100 | 99 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| +8 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +10 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +12 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +14 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +16 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| **all** | 1700 | **97.1** / 0.1 | **99.7** / 0.0 | **100.0** / 0.0 | **100.0** / 0.0 |

Key held (Rubber Band):

| fader % | n | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| -16 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -14 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -12 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -10 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -8 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -6 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -4 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -2 | 100 | 98 / 0 | 99 / 0 | 100 / 0 | 100 / 0 |
| +2 | 100 | 98 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +4 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +6 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +8 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +10 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +12 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +14 | 100 | 99 / 0 | 99 / 0 | 99 / 0 | 99 / 0 |
| +16 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| **all** | 1600 | **99.5** / 0.0 | **99.9** / 0.0 | **99.9** / 0.0 | **99.9** / 0.0 |

Key held (ffmpeg `atempo`):

| fader % | n | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| -12 | 100 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| -6 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +6 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| +12 | 100 | 100 / 0 | 100 / 0 | 100 / 0 | 100 / 0 |
| **all** | 400 | **99.8** / 0.0 | **100.0** / 0.0 | **100.0** / 0.0 | **100.0** / 0.0 |

By kind of music (all speeds, both modes), right, percent:

| bucket | n | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| dance | 1162 | 98 | 100 | 100 | 100 |
| gsplus | 1979 | 99 | 100 | 100 | 100 |
| other | 559 | 98 | 100 | 100 | 100 |

The 3 s misses in the vinyl table are mostly "none", not "wrong": a 3 s query at -16 % holds 2.5 s of the song.

### 4.2 Booth conditions: right / wrong, percent (five speeds pooled)

| condition | n | 3 s | 5 s | 8 s | 12 s | named by 12 s |
|---|---|---|---|---|---|---|
| room | 500 | 76 / 0 | 89 / 0 | 95 / 0 | 98 / 0 | 98 |
| room+crowd+10 | 500 | 63 / 0 | 78 / 0 | 89 / 0 | 93 / 0 | 93 |
| room+crowd+5 | 500 | 43 / 0 | 63 / 0 | 75 / 0 | 85 / 0 | 85 |
| room+crowd0 | 500 | 31 / 0 | 48 / 0 | 60 / 0 | 72 / 0 | 73 |
| room+crowd-5 | 500 | 11 / 0 | 22 / 0 | 33 / 0 | 43 / 0 | 44 |
| room+pink+10 | 500 | 63 / 0 | 81 / 0 | 90 / 0 | 94 / 0 | 95 |
| room+pink0 | 500 | 37 / 0 | 54 / 0 | 68 / 0 | 77 / 1 | 78 |
| room+pink-5 | 500 | 15 / 0 | 28 / 0 | 43 / 0 | 57 / 0 | 58 |
| speaker250-3000 | 500 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 | 100 |
| lowpass2000 | 500 | 99 / 0 | 100 / 0 | 100 / 0 | 100 / 0 | 100 |
| booth(speaker+room+crowd0) | 500 | 48 / 0 | 65 / 0 | 79 / 0 | 86 / 0 | 88 |
| blend+6 | 500 | 73 / 0 | 73 / 0 | 73 / 0 | 73 / 0 | 78 |
| blend0 | 500 | 45 / 0 | 48 / 0 | 49 / 0 | 47 / 0 | 54 |
| blend-6 | 500 | 23 / 0 | 24 / 0 | 25 / 0 | 26 / 0 | 31 |
| room+blend0 | 500 | 29 / 0 | 39 / 0 | 42 / 0 | 48 / 0 | 52 |

"Named by 12 s" counts a clip as named if any of its four lengths was right.

The same at 8 s, by speed (right, percent):

| condition | vinyl +0 | vinyl +12 | vinyl -6 | tempo +12 | tempo -6 |
|---|---|---|---|---|---|
| room | 98 | 92 | 92 | 95 | 98 |
| room+crowd+10 | 89 | 87 | 81 | 91 | 96 |
| room+crowd+5 | 71 | 72 | 70 | 77 | 86 |
| room+crowd0 | 62 | 47 | 57 | 72 | 64 |
| room+crowd-5 | 46 | 30 | 22 | 36 | 30 |
| room+pink+10 | 92 | 88 | 83 | 91 | 94 |
| room+pink0 | 69 | 64 | 64 | 71 | 73 |
| room+pink-5 | 44 | 35 | 39 | 57 | 41 |
| speaker250-3000 | 100 | 100 | 100 | 100 | 100 |
| lowpass2000 | 100 | 100 | 100 | 100 | 100 |
| booth(speaker+room+crowd0) | 88 | 73 | 70 | 84 | 80 |
| blend+6 | 76 | 75 | 66 | 76 | 72 |
| blend0 | 49 | 48 | 45 | 54 | 47 |
| blend-6 | 16 | 25 | 21 | 28 | 34 |
| room+blend0 | 41 | 48 | 35 | 41 | 45 |

No speed is clearly worse than another; vinyl settings lose a few points in noise.

### 4.3 Two songs at once

| condition | length | the song | second | another (wrong) | none | both in the top two |
|---|---|---|---|---|---|---|
| blend+6 | 3 s | 73 | 25 | 0 | 2 | 13 |
| blend+6 | 5 s | 73 | 27 | 0 | 0 | 27 |
| blend+6 | 8 s | 73 | 27 | 0 | 0 | 40 |
| blend+6 | 12 s | 73 | 27 | 0 | 0 | 46 |
| blend0 | 3 s | 45 | 49 | 0 | 5 | 15 |
| blend0 | 5 s | 48 | 51 | 0 | 1 | 34 |
| blend0 | 8 s | 49 | 51 | 0 | 1 | 47 |
| blend0 | 12 s | 47 | 53 | 0 | 0 | 58 |
| blend-6 | 3 s | 23 | 74 | 0 | 3 | 13 |
| blend-6 | 5 s | 24 | 75 | 0 | 1 | 25 |
| blend-6 | 8 s | 25 | 74 | 0 | 1 | 37 |
| blend-6 | 12 s | 26 | 74 | 0 | 1 | 42 |
| room+blend0 | 3 s | 29 | 26 | 0 | 45 | 2 |
| room+blend0 | 5 s | 39 | 38 | 0 | 23 | 12 |
| room+blend0 | 8 s | 42 | 45 | 0 | 13 | 23 |
| room+blend0 | 12 s | 48 | 45 | 0 | 7 | 28 |

A DJ in a blend is playing both, so "second" is not an error. One of the two is named in 99 % of dry blends from
5 s. Both are named together in about half of the equal-level blends at 8 s. In a room the blend is harder: at 8 s
one of the two is named 87 % of the time.

### 4.4 Queries with no right answer: how often a song is named anyway

| kind | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| song not in the index, clean | 0 of 486 | 0 of 486 | 0 of 486 | 4 of 486 |
| song not in the index, room + crowd 0 dB | 0 of 488 | 0 of 488 | 1 of 488 | 0 of 488 |
| noise alone (crowd, pink) | 0 of 100 | 0 of 100 | 0 of 100 | 0 of 100 |

### 4.5 The speed reading, on right answers

Error in fader points (the reading minus the true setting). "Tempo reading" is from the times of the matching
points; "pitch reading" is from their pitches and applies to vinyl-style playback.

| set | length | n | tempo reading: median / 90th / worst | pitch reading (vinyl only): median / 90th | vinyl or key-held told right | place within 0.5 s |
|---|---|---|---|---|---|---|
| clean, vinyl | 3 s | 1651 | 0.08 / 0.23 / 7.32 | 0.00 / 0.01 | 99 | 96 |
| clean, vinyl | 5 s | 1695 | 0.04 / 0.10 / 4.01 | 0.00 / 0.01 | 100 | 99 |
| clean, vinyl | 8 s | 1700 | 0.02 / 0.05 / 0.37 | 0.00 / 0.01 | 100 | 99 |
| clean, vinyl | 12 s | 1700 | 0.01 / 0.02 / 0.20 | 0.00 / 0.01 | 100 | 100 |
| clean, tempo only | 3 s | 1592 | 0.23 / 0.46 / 1.17 | 0.00 / 0.00 | 100 | 99 |
| clean, tempo only | 5 s | 1598 | 0.22 / 0.39 / 0.95 | 0.00 / 0.00 | 100 | 100 |
| clean, tempo only | 8 s | 1599 | 0.22 / 0.38 / 0.90 | 0.00 / 0.00 | 100 | 100 |
| clean, tempo only | 12 s | 1599 | 0.21 / 0.37 / 0.57 | 0.00 / 0.00 | 100 | 100 |
| room | 3 s | 381 | 0.18 / 0.58 / 2.45 | 0.01 / 0.05 | 100 | 91 |
| room | 5 s | 445 | 0.12 / 0.35 / 4.15 | 0.01 / 0.05 | 100 | 94 |
| room | 8 s | 475 | 0.10 / 0.31 / 0.76 | 0.01 / 0.04 | 100 | 98 |
| room | 12 s | 488 | 0.06 / 0.29 / 0.94 | 0.01 / 0.04 | 100 | 98 |
| room + crowd 0 dB | 3 s | 156 | 0.24 / 0.62 / 3.25 | 0.02 / 0.04 | 100 | 86 |
| room + crowd 0 dB | 5 s | 238 | 0.17 / 0.41 / 2.58 | 0.02 / 0.04 | 100 | 90 |
| room + crowd 0 dB | 8 s | 302 | 0.14 / 0.34 / 1.28 | 0.01 / 0.04 | 100 | 92 |
| room + crowd 0 dB | 12 s | 360 | 0.10 / 0.31 / 0.69 | 0.01 / 0.04 | 100 | 94 |
| room + pink -5 dB | 3 s | 77 | 0.26 / 0.68 / 1.25 | 0.02 / 0.07 | 100 | 91 |
| room + pink -5 dB | 5 s | 142 | 0.20 / 0.49 / 2.52 | 0.02 / 0.08 | 100 | 89 |
| room + pink -5 dB | 8 s | 216 | 0.15 / 0.41 / 1.83 | 0.02 / 0.07 | 100 | 89 |
| room + pink -5 dB | 12 s | 283 | 0.13 / 0.34 / 1.40 | 0.02 / 0.07 | 100 | 92 |
| blend 0 dB | 3 s | 227 | 0.17 / 0.41 / 1.84 | 0.01 / 0.03 | 100 | 96 |
| blend 0 dB | 5 s | 239 | 0.11 / 0.32 / 0.85 | 0.01 / 0.02 | 100 | 98 |
| blend 0 dB | 8 s | 243 | 0.06 / 0.29 / 0.58 | 0.01 / 0.01 | 100 | 99 |
| blend 0 dB | 12 s | 234 | 0.03 / 0.28 / 0.49 | 0.01 / 0.01 | 100 | 100 |

- The key-held rows against Rubber Band show a median of 0.2 points that does not shrink with length. It is not the
  reader: the error grows in proportion to the setting (+0.26 at -16 %, -0.38 at +16 %), and against ffmpeg's
  stretcher the same reader is within 0.024 points at the median at 12 s. Rubber Band's clips, as made here (16 kHz,
  through pedalboard), play about 2 % of the setting off their nominal speed.
- "Worst" values of several points at 3 and 5 s are single queries where the fit locked onto a repeat of the
  passage at a slightly wrong speed. The booth's existing check over consecutive matches is the guard.
- "Place within 0.5 s" under 100 % is the same thing: dance music repeats, and a 3 s query can match a repeat.

### 4.6 Cost

**Fingerprint.** Over all 1,078 songs on one core: 104 ms per minute of music (0.42 s for four minutes), plus
112 ms per minute to decode the MP3 with the core's own decoder (timed before the strength level was added to each
point, which adds a small sum per point). 96.2 bytes and 32.0 points per second of music.

**A query, 969 songs, four jobs sharing the machine** (so somewhat slower than one job alone):

| length | points in the query (median) | fingerprint the query: median / 95th | match: median / 95th |
|---|---|---|---|
| 3 s | 105 | 4.3 / 6.2 | 11.0 / 17.0 |
| 5 s | 173 | 7.1 / 8.7 | 23.4 / 34.9 |
| 8 s | 275 | 11.3 / 14.4 | 43.0 / 63.7 |
| 12 s | 411 | 17.0 / 21.5 | 69.5 / 100.7 |

**Against catalogue size, one core, nothing else running:**

(1 held-out song(s) that are the same recording as an indexed song are left out.)

The index holds 969 real songs; smaller sizes drop songs (queries whose song was dropped are left out of 'right'), larger ones add altered copies of real constellations.

| songs in the index | answer an 8 s query, ms: median / 95th | 3 s | 12 s | a song not in the index named anyway (3 / 5 / 8 / 12 s) | right, songs in the index (8 s) |
|---|---|---|---|---|---|
| 250 | 33 / 48 | 9 / 12 | 55 / 76 | 0 / 0 / 1 / 5 of 486 | 92 % of 130 |
| 500 | 37 / 54 | 10 / 14 | 62 / 85 | 1 / 0 / 0 / 3 of 486 | 94 % of 278 |
| 1000 | 42 / 63 | 11 / 16 | 70 / 100 | 0 / 0 / 0 / 3 of 486 | 95 % of 500 |
| 2500 | 58 / 86 | 15 / 23 | 94 / 138 | 0 / 0 / 2 / 2 of 486 | 95 % of 500 |
| 5000 | 73 / 107 | 19 / 29 | 119 / 171 | 0 / 0 / 1 / 5 of 486 | 94 % of 500 |
| 10000 | 112 / 163 | 28 / 43 | 181 / 261 | 0 / 1 / 2 / 4 of 486 | 93 % of 500 |

- Sizes above the real 969 are padded with altered copies of real constellations (time reversed, every pitch moved
  round the band by a different amount per copy). They have a real song's number and rhythm of points and match
  nothing. They are not more music: real songs of one style resemble each other more than these do, so false
  matches at 5,000 real songs may be higher than this row shows. The owner's run on 2,300 real songs is the check.
- Time grows with the catalogue, more slowly than in proportion: 2.7 times the time for 10 times the songs.
- **The target (under 80 ms for 8 s at 5,000 songs) is met at the median (73 ms) and missed at the 95th percentile
  (107 ms).** A 12 s query takes 119 ms at 5,000.
- With few songs in the index the confidence is easier to pass (the "third-best song" it is measured against is
  weaker): 5 of 486 absent queries named at 12 s with 250 songs. A small crate may need a floor under the yardstick.
- Building the index: 14 s for 969 songs, 72 s for 5,000, on one core, unoptimised.

### 4.7 A deeper second pass (an option, not the default)

When the first answer's confidence is under the threshold, match again with a denser constellation of the query
(neighbourhood 64 ms and 8 %) and three points per slice. Eval, same threshold (not re-chosen for this mode):

| Condition, right percent (default → with the second pass) | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| room | 76 → 81 | 89 → 92 | 95 → 96 | 98 → 99 |
| room + crowd +10 dB | 63 → 69 | 78 → 85 | 89 → 92 | 93 → 96 |
| room + crowd +5 dB | 43 → 52 | 63 → 71 | 75 → 82 | 85 → 89 |
| room + crowd 0 dB | 31 → 36 | 48 → 55 | 60 → 66 | 72 → 79 |
| room + crowd -5 dB | 11 → 15 | 22 → 29 | 33 → 41 | 43 → 53 |
| room + pink 0 dB | 37 → 41 | 54 → 59 | 68 → 72 | 77 → 81 |
| speaker + room + crowd 0 dB | 48 → 55 | 65 → 75 | 79 → 85 | 86 → 91 |
| room + two songs at 0 dB | 29 → 32 | 39 → 41 | 42 → 45 | 48 → 50 |

It costs time only when the first pass fails, but then a lot: at 8 s the median query is 52 ms and the 95th
percentile 289 ms. Songs not in the index named anyway: 13 of 1,944 clean queries (9 of them at 12 s) against 4
without it, so its threshold would need raising. It gains 3 to 10 points; it does not close the gap to ShazamKit.

### 4.8 DJ mixes with ground truth: UnmixDB

Reported apart from the synthetic conditions, as asked. UnmixDB's mixes are generated, not recorded: three track
excerpts in a row with beat-matched cross-fades, the second and third brought to the first one's tempo ("none":
left alone; "resample": vinyl-style; "stretch": key held, by sox), and one effect on the whole mix. Its labels give
when each track starts, fades and stops, and its speed factor. The index was the 71 excerpts **plus all 1,078
outside songs** as distractors (1,149). A window was taken every 4 s along each mix. No setting was chosen on this
set; the threshold is the benchmark's. About half of the "resample" and "stretch" windows are 1 % or more off the
track's own speed.

### One song playing at a speed beyond 16 % (outside the fader's range; not tried by the matcher)

| length | windows | right / wrong / none, percent |
|---|---|---|
| 5 s | 177 | 0 / 0 / 100 |
| 8 s | 134 | 0 / 0 / 100 |
| 12 s | 91 | 0 / 0 / 100 |

Everything below is the windows within 16 %.

### One song playing: right / wrong / none, percent of windows

| time scaling | effect | windows | 5 s | 8 s | 12 s |
|---|---|---|---|---|---|
| none | bass | 312 | 99 / 0 / 1 | 100 / 0 / 0 | 100 / 0 / 0 |
| none | compressor | 312 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| none | distortion | 312 | 67 / 0 / 33 | 76 / 0 / 24 | 83 / 0 / 17 |
| none | none | 312 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| none | all | 1248 | 92 / 0 / 8 | 94 / 0 / 6 | 96 / 0 / 4 |
| resample | bass | 288 | 99 / 0 / 1 | 99 / 0 / 1 | 100 / 0 / 0 |
| resample | compressor | 240 | 82 / 0 / 18 | 81 / 0 / 19 | 79 / 0 / 21 |
| resample | distortion | 288 | 63 / 0 / 37 | 72 / 0 / 28 | 78 / 0 / 22 |
| resample | none | 288 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| resample | all | 1104 | 86 / 0 / 14 | 89 / 0 / 11 | 90 / 0 / 10 |
| stretch | bass | 288 | 99 / 0 / 1 | 99 / 0 / 1 | 100 / 0 / 0 |
| stretch | compressor | 288 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| stretch | distortion | 288 | 66 / 0 / 34 | 74 / 0 / 26 | 81 / 0 / 19 |
| stretch | none | 288 | 100 / 0 / 0 | 100 / 0 / 0 | 100 / 0 / 0 |
| stretch | all | 1152 | 91 / 0 / 9 | 93 / 0 / 7 | 95 / 0 / 5 |

### During a cross-fade: one of the songs in the mix named / a song outside it named / none; both named

| time scaling | windows | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| none | 1628 | 93 / 0 / 7; 7 | 94 / 0 / 6; 14 | 95 / 0 / 5; 18 |
| resample | 1362 | 91 / 0 / 9; 5 | 92 / 0 / 8; 11 | 94 / 0 / 6; 15 |
| stretch | 1440 | 92 / 0 / 8; 8 | 93 / 0 / 7; 14 | 95 / 0 / 5; 19 |

### The speed reading against the labels' speed factor, one song playing, right answers (fader points)

| time scaling | length | n | share of windows off zero by 1 % or more | tempo reading: median / 90th error | pitch reading: median / 90th error (resample only) |
|---|---|---|---|---|---|
| none | 5 s | 1657 | 0 | 0.04 / 0.16 | - |
| none | 8 s | 1510 | 0 | 0.02 / 0.16 | - |
| none | 12 s | 1195 | 0 | 0.01 / 0.08 | - |
| resample | 5 s | 1393 | 52 | 0.05 / 0.15 | 0.01 / 0.03 |
| resample | 8 s | 1255 | 51 | 0.02 / 0.09 | 0.00 / 0.02 |
| resample | 12 s | 990 | 50 | 0.01 / 0.06 | 0.00 / 0.02 |
| stretch | 5 s | 1547 | 55 | 0.06 / 0.20 | - |
| stretch | 8 s | 1389 | 54 | 0.03 / 0.15 | - |
| stretch | 12 s | 1097 | 53 | 0.02 / 0.09 | - |

By mix (8 s, one song playing): 360 mixes; right in the worst mix 27 %, the lowest tenth 62 %, the median mix 100 %.


- UnmixDB brings some tracks to the first one's tempo by factors far outside any fader (0.71 to 2.0). The matcher
  tries speeds to 17 % and names none of those windows. That is the design's limit, stated in section 11.
- Unprocessed, bass-boosted and compressed mixes: 99 to 100 % at every length, except "resample" with the compressor
  (81 % at 8 s), which I have not explained.
- Heavy distortion: 72 to 76 % at 8 s.
- During a cross-fade one of the two songs is named in 92 to 94 % of 8 s windows; both together in 11 to 14 %.
- No song outside the mix was named in any window.
- The worst single mix scored 27 % of its 8 s windows; a tenth of the mixes scored 62 % or less (the distortion ones).

## 5. What was tried on the way, and why the design is what it is

**Two-point hashes (the paper's own) work better in noise and are too slow.** With pairs, a lookup returned about a
hundred unrelated songs' entries (a pair's hash has some 470,000 possible values; 969 songs make 37 million pairs),
and a query took 0.5 to 0.6 s on one core, growing with the catalogue. Spreading each anchor's targets across the
whole target zone, in place of taking the nearest, cut that sevenfold on a pilot but not enough on the full index.

**Three-point hashes are ten times faster and lose in noise.** All three points have to survive, not two. On the dev
sample (550 clips of the hardest conditions; right song named and accepted, percent at 3 / 5 / 8 / 12 s):

| Dev sample, 969 songs | two-point | three-point, first point in each slice | three-point, strongest point (the default) |
|---|---|---|---|
| room | 95 / 100 / 100 / 100 | 85 / 98 / 98 / 98 | 88 / 92 / 92 / 98 |
| room + crowd 0 dB | 45 / 65 / 80 / 83 | 32 / 43 / 60 / 70 | 28 / 40 / 58 / 68 |
| room + crowd -5 dB | 18 / 40 / 55 / 68 | 10 / 20 / 32 / 43 | 8 / 23 / 42 / 50 |
| room + pink -5 dB | 35 / 50 / 65 / 78 | 20 / 38 / 48 / 52 | 23 / 40 / 48 / 60 |
| speaker + room + crowd 0 dB | 60 / 80 / 87 / 95 | 45 / 62 / 70 / 88 | 45 / 63 / 78 / 88 |
| mean time to answer, one core | 500 ms | 48 ms | 47 ms |

Each cell is 60 clips (40 for "room"), so differences of under about 10 points between the last two columns are
within chance; the strongest-point rule was kept because it gained most where noise was worst. **The two-point
column is what this fingerprint can do in noise if time were free: about 20 points better than the default at
equal-level crowd noise.** It is kept in the code (`PairingConfig.triples = false`) for that comparison only.

**The plain score was a poor yes-or-no test.** Unrelated dance songs share structure (a kick on every beat puts
points in the same places), so a wrong song's count of matching points is high. Dividing by the third-best song's
count separates right from wrong far better (on the dev sample about 19 in 20 right answers cleared a threshold that
99.5 % of absent songs stayed under; with the plain score, far fewer did).

**A tag on each table entry and a table sized to the catalogue** took an 8 s query at 5,000 songs from 165 ms to
73 ms: as the catalogue grew, different hashes shared table slots and cast stray votes.

**Undoing the speed on the audio, as letter H proposed, against moving the points** (letter W's comparison): 850
clean vinyl-style eval queries of 8 s, every setting. Resampling the query's audio at each of 35 speeds and matching
each copy as it is: 850 of 850 right, pitch reading 0.00 median, 567 ms a query. Moving the points: 850 of 850
right, pitch reading 0.00 median, 60 ms a query. So the audio route is dropped: the same answers at nine times the
cost, and for key-held playback it would also need a time-stretcher in the booth. Only clean audio was compared.

**Phase 3 of the brief (ratio fingerprints, quads) was not built**, and I do not recommend it next. The brief made it
conditional on the baseline falling short across speed. It does not: speed tolerance is complete with candidate
speeds on the points. Where it falls short is noise, and a hash that needs three or four points to survive is worse
in noise, not better (the table above; Qfp's own 0.56 to 0.77 at 5 s, letter H). I worked the design through: ratio
hashes would remove the 69 candidate speeds, and to keep lookups specific at several thousand songs they need a
fourth point.

## 6. Letter W's seven points

1. *Logarithmic pitch axis*: done; pitches are stored and hashed in octaves.
2. *Speed copies from the peaks, compared with audio*: done and compared (section 5).
3. *Speed as the slope of the matching pairs*: done (the tempo ratio); the pitch ratio is the median pitch difference.
4. *A checking step against what the crate file holds*: half done. Every candidate is checked against the song's own
   stored points at the fitted speed, which is what rejects wrong songs here. Checking against the beat grid and the
   per-bar pattern was not built: the outside songs have no Deckie analysis, and making one for a thousand songs was
   outside this trial.
5. *Time in beats*: not tried, for the same reason, and because clean-audio speed tolerance left no gap for it.
6. *False matches on songs not in the catalogue*: done at every catalogue size (4.4, 4.6).
7. *Real DJ mixes*: UnmixDB done (4.8). The ten real club mixes of the Linz "mixotic" set could not be fetched: its
   download links (Google Drive) now ask for a sign-in.

## 7. Against letter H's ShazamKit figures

Conditions match only loosely, and where they do not it is said.

| Condition (8 s) | ShazamKit, letter H | This trial | How well the conditions match |
|---|---|---|---|
| Clean, across ±16 %, both modes | 25 of 25 at every setting with 9 signatures a song; with 1 signature, only within ±4 % | 99.9 to 100 % with 1 fingerprint a song | Well. H: 25 songs of one crate, 373 distractors. Here: 3,700 queries, 969 songs |
| 5 s / 3 s clean | 25 of 25 / 22 to 25 of 25 | 99.7 to 99.9 % / 97.1 to 99.5 % | Well |
| Room | 49 to 50 of 50 | 95 % | Poorly: H used a synthetic reverb (wet 0.25) and a 120 Hz to 8 kHz band; here 417 measured rooms, some far from the source |
| Room + pink noise, 0 dB | 45 to 50 of 50 (90 to 100 %) | 68 % | Same caveat; the noise level is defined the same way |
| Room + pink noise, -5 dB | 39 to 47 of 50 (78 to 94 %) | 43 % | Same |
| Two songs, equal level | the song named in 24 to 27 of 50, the other in the rest | the song 49 %, the other 51 % | Well |
| Two songs, second 6 dB down | 39 to 40 of 50 for the louder | 73 % for the louder | Well |
| Vinyl speed reading | within 0.03 points worst case, clean; median 0.01 to 0.04 in noise | 0.00 median, 0.01 at the 90th percentile clean; 0.01 / 0.04 in room and crowd | Well |
| Key-held speed reading | 0.02 to 0.05 median from two matches 8 s apart (16 s of audio) | 0.02 to 0.03 median from one 8 s listen (ffmpeg, sox) | Different method; comparable result in half the time |
| Fingerprint per song | 45 KB (1 signature) to 410 KB (9) | 23 KB | Four-minute song |
| Making it | 0.7 s (1) to 10 s (9), one M1 Max core | 0.42 s, one 2.3 GHz server core, plus decoding | Different machines |
| Listening cost | about 12 % of an M1 Max core for 11 streams | 8 s query once a second at 2,500 songs: 58 ms, so about 6 % of this core | Different machines; H's is a streaming session |

**The plain reading: on clean audio and on the fader this matches or betters what letter H got from ShazamKit, at a
fraction of the catalogue size. In loud noise it is well behind.** I cannot say how far the harsher rooms explain
that; the two-point result (section 5) suggests the fingerprint itself has more to give than the fast matcher takes.

## 8. What it means for a DJ, in plain words

- You load a crate file made on a PC, a Mac or anything else, and the booth can name what is playing. No Apple
  device has to touch the crate file first.
- It does not matter where the pitch fader is, or whether key lock is on. The song is named just as fast at +16 as
  at zero, and the fader's position comes with the name.
- In a booth where the iPad mostly hears the monitor, expect the name within 5 to 10 seconds, nine times in ten or
  better, and almost never a wrong name.
- In a booth where the crowd is as loud as the music at the iPad, expect it to take 10 seconds or more and to miss
  about three songs in ten on the first try; it keeps listening, so most of those arrive later, but that was not
  measured beyond 12 s.
- In a blend it names one of the two songs, and both about half the time.
- It will not name a song played beyond ±17 % (a turntable's wide range), and it was not tested with effects other
  than UnmixDB's three, with scratching, loops or a microphone talking over the music.

## 9. What it would take to put it in Desk and the booth

**Desk (Mac, Windows, Linux).** One call per song after decoding, which Desk already does for analysis:
`Landmarks(mono:sampleRate:)`, about 0.4 s for a four-minute song on one core here, then `encoded()`. It belongs in
the one run that reads, fingerprints and links copies (`DeskRun`), stored with what was worked out for each file so
that it is made once per file, not per crate.

**The crate file.** An addition that changes no existing field, in the manner of D27:

- a new sidecar folder `prints/`, one file per song, `prints/<id>.dkl` (the bytes `Landmarks.encoded()` writes: a
  4-byte mark `DKL2`, the frame and point counts, then about three bytes a point);
- a new optional key on the song's record, `print`, left out when there is none:
  `{"format": "DKL2", "points": 7712, "made_by": "<device label>", "made_at": "<UTC time>"}`;
- `signatures` (ShazamKit's) stays exactly as it is. A crate file may carry both, either or neither, and a reader
  that does not know `print` ignores it (the format's own rule for unknown keys).
- Size: 96 bytes per second of music, 23 KB for a four-minute song, about 53 MB for 2,300 such songs (ShazamKit's
  single signature: about 45 KB a song by letter H).

**The booth (iPad).**

- On opening a crate file: read the `prints/` files and build the index (here 14 s for 969 songs on one core,
  unoptimised; it can be built once and kept in the local-only `catalog/` folder, and mapped from disk rather than
  held in memory: 0.3 MB a song, so about 0.7 GB for 2,300 songs and 1.5 GB for 5,000, which is too much to hold in
  an iPad app's own memory and is the first thing an iPad build would have to shrink or map from disk).
- While listening: keep the last 12 s of microphone audio; once a second make its constellation (12 ms for 8 s
  here) and match it.
- Once a song is named: stop trying 69 speeds. Try only the speeds next to the one found and only that song and the
  booth's picks; that is a few percent of the searching cost. This tracking mode is **not built or measured** in the
  trial.
- The existing `Recognizer` state machine (hysteresis, jumps to a repeated chorus) stays; its input changes from
  ShazamKit's match to this one's (song, offset, two ratios, confidence).
- What needs a Mac, an iPad or Xcode and so was **not tested**: the module building for iOS and macOS (it uses
  nothing platform-specific, and the rest of the core already builds there), its speed on an A-series chip, the
  iPad's microphone and its automatic gain, memory limits with a large crate, heat and battery over a night.


## 10. Licences and patents, as far as public sources show

This is a record of what public listings say, not legal advice or clearance.

| Thing | Status found | Source |
|---|---|---|
| US 6,990,453 (Wang and Smith: the landmark method of the 2003 paper), assigned to Apple | Listed "Expired - Lifetime", adjusted expiry Jan 7, 2024; eight continuations (US 7,346,512; 7,865,368; 8,190,435; 8,386,258; 8,700,407; 9,401,154; 9,899,030; 10,497,378) all listed expired, the latest date Mar 5, 2022 | Google Patents, which calls its status "an assumption, not a legal conclusion" |
| Its European member EP 1307833 | Listed expired, anticipated expiry Jul 26, 2021; lapse by country not shown | Google Patents |
| US 7,627,477 (Wang and Culbert: matching that survives speed change, by comparing ratios), assigned to Apple | Listed "Expired - Lifetime", adjusted expiry Mar 31, 2025; European member EP 1504445 listed expired Apr 18, 2023 | Google Patents |
| US 7,549,052 (Haitsma and Kalker; the method behind `RecordingPrint`, not used here) | Listed expired, adjusted expiry Jul 6, 2024 | Google Patents |
| Patents by the quad-fingerprint (Qfp) or Panako authors | None found; the inventor search itself did not load, so this rests on web searches only | not exhaustive |
| Family members in Japan, China, Korea, Brazil and elsewhere | Listed, with no status shown | Google Patents |

Not consulted: the USPTO's and the European Patent Office's own registers (fee payments, national lapses). Later
patents on particular refinements were not searched for. An attorney's search is the owner's to order before
anything ships.

Code: everything in the module was written for this trial from the published descriptions (Wang 2003 for points,
pairs, voting; the three-point hash and the strength rule are this trial's own). No AGPL or GPL code was read for it,
copied or linked. The benchmark's scripts use, at run time only and outside the product: ffmpeg, numpy, scipy,
soundfile, and pedalboard (GPL-3, which carries Rubber Band, GPL) to make the key-held test clips. None of that is
in the Swift package.

## 11. What I could not verify

- **A real booth.** No recording through an iPad's microphone beside a booth monitor with a crowd. Every room here
  is a measured room response applied by computer; every crowd is a cafeteria, a restaurant or a station.
- **A real deck's key lock.** Only Rubber Band, ffmpeg and sox were tested, as in letter H.
- **Real club mixes.** Not obtainable (section 6). UnmixDB's mixes are generated.
- **Anything on a Mac, an iPad or Xcode**: the build there, the speed on Apple's chips, memory limits, heat.
- **A crate of several thousand real songs.** Sizes above 969 are padded (4.6). The owner's own run is the check.
- **ShazamKit on this benchmark.** Not possible off Apple's platforms; the comparison rests on letter H's figures.
- **Speeds beyond ±17 %**, and independent pitch and tempo changes (key shift with tempo change): the search covers
  two lines only, key held and vinyl-style.
- **The tracking mode** after a song is named, and anything over consecutive listens: not built.
- **The one unexplained cell**: UnmixDB "resample" with the compressor at 81 % where its neighbours are 100 %.
- **Patents**: listings only, no register, no attorney (section 10).
- **Windows**: the module's tests pass on GitHub's Windows machine; the benchmark itself was only run on Linux.

## 12. Options for the owner

| Option | What it is | Costs | Gains |
|---|---|---|---|
| **A. Carry the fingerprint in the crate file now; keep ShazamKit in the booth for now** | Desk on every platform writes `prints/<id>.dkl`; the Apple booth keeps ShazamKit where signatures exist and can use this where they do not | A week or two in Desk and the crate format; nothing changes for existing crate files | A PC-made crate file is complete in the sense D29 asks (it can be recognised from); the decision on the booth's recogniser waits for a real booth recording without holding up the PC version |
| **B. Make this the booth's recogniser everywhere** | Replace ShazamKit with this matcher on the iPad too | A month *[inference]*: the tracking mode, the iPad's memory (0.3 MB a song now), the state machine's input; and the noise risk | One recogniser on every platform; one fingerprint a song where ShazamKit needs nine for the fader; the fader read at once in both modes |
| **C. First, one evening's recording in a real booth** | An iPad (or a phone) recording beside a booth monitor for an hour, with the set list; run both recognisers on it | The owner's evening; a day to run | Replaces the synthetic noise question with a real answer; decides between A and B |
| **D. Work on noise** | In order: (1) accumulate evidence over consecutive listens, which a booth does anyway; (2) use the booth's knowledge (the picks, the tempo) to check a short list of songs with two-point hashes, where their cost does not matter; (3) the crate file's beat grid as the checking step (letter W's point 4) | Two to four weeks *[inference]* | The two-point result says about 20 points are there to be had at equal-level noise |
| **E. Ratio fingerprints (quads)** | Phase 3 of the brief | A month or more | Speeds beyond ±17 %; nothing for noise |

**My recommendation: A now, C as soon as it can be arranged, then D if C shows the booth is loud, and B only when
the noise figures stand beside ShazamKit's. Not E.** The reasons: the fingerprint is cheap and small and is the
piece a PC version cannot do without; the trial's own numbers say this recogniser is not yet ShazamKit's equal in a
loud room, and the booth is where a miss is seen; and the one measurement that would settle it costs an evening.

Challenge to my own recommendation: if the first PC users have no Apple booth at all, there is no ShazamKit to keep,
and B is forced for them. In that case this is good enough to ship as a first version **for a booth where the iPad
hears the monitor**, with the noise work (D) to follow, and it should say so.

## 13. Running it

```bash
core/Tools/recognition-bench/run.sh /path/outside/the/repo/data /path/outside/the/repo/work
```

fetches the outside material (about 8 GB) and writes `work/results.md` with every table of section 4 and
`work/summary.json`. On this four-core machine: about 15 minutes to fetch, 10 to decode, 10 to fingerprint on one
core, 15 to make the queries, 20 to match, 40 for the catalogue sizes. It needs Swift 6, ffmpeg, curl and Python 3
with numpy, scipy, soundfile and pedalboard. The draw of queries is seeded, so a second run asks the same questions.

**On any folder of music as the catalogue** (the owner's library, for instance):

```bash
MUSIC=/path/to/music core/Tools/recognition-bench/run.sh /path/outside/the/repo/data /path/outside/the/repo/work2
```

Every audio file under the folder that ffmpeg reads becomes a song in the index (one in ten held out as "not in the
crate"). Only the room responses and noise are fetched (1.3 GB). Songs are named by a hash of their path, so nothing
written carries a title or an artist, and nothing leaves the computer. The threshold is the outside set's (2.96, in
`threshold.txt`), not one chosen on that music. The work folder needs about 8 MB a song and 7 GB for the queries.
`results.md` then has the same tables for that library, including false matches and time at the library's own size
and padded beyond it. Tested here on a folder of 40 songs.

UnmixDB is run as well when its unzipped sets are in `data/unmixdb`.

The module's tests: `swift test --filter DeckieRecognitionTests` in `core/`.
