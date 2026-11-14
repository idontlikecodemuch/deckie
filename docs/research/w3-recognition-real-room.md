# Research W3: Deckie's own recognition in a real room

Dated Nov 14, 2026. A measurement, no decisions. It is the real-room test that letter W2 (section 12, option C) and
D35 asked for: the trial's matcher, exactly as W2 fixed it on outside music, run over the booth's own recording of a
recorded party set, on the owner's Mac only. Harness: `core/Tools/recognition-bench/room_test.py` and
`room_test.sh` (commands in section 10). **Nothing from the recording or the music is in the repository: no audio,
no fingerprints, no titles, no excerpts of the booth's log.** Every number here is an aggregate. Tags: [inf] = my
inference, with the reasoning; [unmeasured] = not measured.

## Three cautions first, in plain words

1. **Most of the recording is not the party's music.** The booth recorded 7.7 hours that day. 2.8 hours of it is
   the afternoon (tests and a rehearsal), and of the 4.9 hours from the evening only about 2 hours is music this
   test can tie to a song with confidence; 2.2 hours is music it cannot tie to any song (section 3), and the rest
   is talk, gaps and silence. Every headline number below is computed on the evening's known music only. The
   afternoon is reported apart.
2. **Part of the evening was a pre-mixed disc**, a continuous mix made beforehand, not the DJ mixing live. The
   owner's crate holds that mix as one track of 2 hours 25 minutes, and also holds many of its songs as separate
   files. The test tells the two apart where it can and reports them apart. A match to the mix's own track counts as
   right while the mix plays.
3. **It was a quiet house party, not a club.** At the microphone the music stood about 5 dB above everything else
   most of the time (section 6). That is between the outside benchmark's "music 10 dB over the noise" and "5 dB
   over" rows, and far from its "equal" and "5 dB under" rows, which are the ones where the matcher fell behind
   ShazamKit. **This test does not answer the noise question.** A loud venue was not measured here. The nearest
   thing to a hard case in this material, the moments where talk or singing was as loud as the music, is reported on
   its own (section 6), and it is a small share.

## In plain words

The booth is an iPad beside the decks. It listens and names the song that is playing. That night it used Apple's
ShazamKit, against a catalogue of 373 songs made for the night. Letter W2 built a recogniser of Deckie's own: it
takes a short **window** of sound (3, 5, 8 or 12 seconds), finds its loudest points, and looks them up in an index
made from the songs' own fingerprints. It also reads how fast the deck is playing (the **fader**, in percent: +3
means 3 percent faster than the record). This letter plays the booth's own recording of the party through that
recogniser, a window every 2 seconds, and asks how often it named the right song.

There is no list of what played when, to the second. So the test builds its own **answer key**: for every song a
recogniser suggested, the song's own audio is lined up with the recording and compared wave for wave. Where the
song's sound is really in the room, a share of the recording follows it closely; where it is not, almost nothing
does. That check is a different method from the recogniser's, so the key does not just repeat the recogniser's
opinion. It is not perfect, and section 2 says where it is weak.

What came out, on the evening's known music:

- **Against the party's discs alone (92 songs, the discs and the mix): right 81 % of the time from 8 s windows and
  87 % from 12 s; a song was first named a median 7 s after it started, and 1 song in 102 was never named.** Almost
  every "wrong" name was the mix's own track named while the same song played from a disc (section 4).
- **Against the whole library (2,327 files): right only 42 % of the time from 8 s windows.** Not because the
  library holds more songs but because it holds the same recording several times: 168 of the 195 songs heard that
  night have a second copy in the library. The matcher's yes-or-no test compares the best song with the third best,
  and when the second and third best are copies of the first it cannot say yes. A different song was named in under
  0.1 % of windows. This is the most important finding here, and it is fixable without touching the noise problem
  (section 9). Folding the library's copies by title, artist and length, crudely, lifts it to 64 % at 8 s; adding
  1,070 more real songs (3,396 in all) changes nothing for the party's songs and adds almost no wrong names, though
  some of the added music turns out to have been heard that night (section 11).
- **Against ShazamKit that evening:** of the 116 songs played for 30 s or more, ours (library) named all
  but 4 of them, ShazamKit's log shows a switch to 48 of them, and where both named a song ours was first in 33,
  ShazamKit first in 5 (median 11 s against 22 s). The log is a poor clock (section 5), so take the size of that gap
  loosely.
- **The fader**: read on 108 songs; 29 were played more than 2 % off zero and 7 more than 4 % off, which is beyond
  the range ShazamKit covers with one signature. Readings were steady through a song (the middle half of a song's readings
  spanned 0.06 points at the median), and agreed with the booth's own pitch readings to 0.09 points at the median.

## 1. The material

Recordings: 35 files from the booth's recorder, mono AAC at 48 kHz, each with the booth's log (what it named and
when) and a tracklist made from the log. 18 files shorter than 30 s (94 s in all) are restarts and are left out.
The evening starts at the first recording after 19:00 local time; everything earlier is "the afternoon".

| part | files used | hours | log entries |
|---|---|---|---|
| afternoon (tests, rehearsal) | 5 | 2.78 | 21 |
| evening (the party) | 12 | 4.85 | 50 |

Catalogues, all from the owner's library crate file (the songs' files on the music drive):

| catalogue | songs | music, hours | fingerprints on disk | index in memory (peak, process) | building the index |
|---|---|---|---|---|---|
| the party's discs: the two burned discs (91 songs) and the pre-mixed disc (1 track) | 92 | 9.2 | 3.3 MB | 157 MB | 0.9 s |
| the whole library | 2,327 | 162.6 | 58.5 MB | 1.31 GB | 19.9 s |

- **Which discs.** The log names disc folders that exist only in the third version of the party's discs, the one
  burned the day before; the crate file of the discs in `~/Music/Deckie` is of the second version (made later). So
  the discs' catalogue here is the third version's 91 songs, taken from the library crate, plus the mix. Every one of
  them is also in the library catalogue.
- **The library crate's mix.** The pre-mixed disc's whole mix is one track of the library crate (2 h 25 min, 66
  songs inside it), and the library also holds separate files of many of those songs. So a song from the mix can be
  named two ways: the mix's track, or the song's own file.
- **Fingerprinting** (this Mac, an Apple M5, 2 workers under `nice -n 19`): 2,327 songs in 11 min 26 s of wall
  time, 1,275 s of processor time; per minute of music 67 ms to decode and 74 ms to fingerprint; 33.3 points a
  second of music. The 92 discs' songs alone: 41 s to decode and 41 s to fingerprint (processor time).
- **Memory.** Before starting, W2's figure (0.3 MB a song while matching) gave about 0.7 to 0.9 GB for 2,327 songs of
  4.2 minutes on average. Measured: the index holds 19.5 million points and 115.8 million hashes; the matching process
  peaked at 1.31 GB with a small batch of queries, so about 0.5 MB a song including the program and two workers'
  working memory. *[inf]* With long query runs the tool's peak grew further (1.9 GB for the library and 4.8 GB for
  the discs over 54,780 queries); that grows with the number of queries, not the catalogue, and looks like the
  benchmark tool not freeing what it reads per query on macOS, not the index. It does not affect the booth design but
  should be fixed in the tool before anyone reads memory off a long run.
- **Query time** (one window, matching only, median and 95th percentile; 2 jobs sharing the machine):

| window | discs | library |
|---|---|---|
| 3 s | 3.0 / 4.1 ms | 5.4 / 7.5 ms |
| 5 s | 6.1 / 8.2 ms | 11.1 / 15.3 ms |
| 8 s | 11.2 / 15.2 ms | 20.2 / 27.6 ms |
| 12 s | 18.2 / 24.4 ms | 32.6 / 44.0 ms |

  Making the window's own fingerprint adds 2 to 9 ms. This Mac is about twice as fast as W2's server core for the
  same work.

**The queries**: at every 2 s of every recording, one window of each length ending at that moment (the booth keeps
the last 12 s and asks every few seconds): 13,695 moments, 54,780 windows, matched against each catalogue with the
settings and threshold W2 fixed (confidence 2.96). Nothing was chosen on this material.

## 2. The answer key, and how good it is

**How it is built** (the code's `TRUTH` note has the detail):

1. *Candidates.* (a) Every song and place the matcher put first or second in at least three windows that agree on
   the place, or once with at least two thirds of the threshold; so a song the matcher saw but did not accept is
   still tried. (b) Every song the booth's log names, at the time it names it, its place found by searching the whole
   song. (c) For stretches with a steady beat that nothing explained, a search of the discs' songs, one probe a
   minute.
2. *The check, by the waveform.* The song's own audio, placed where the candidate says and at its speed, is compared
   with 6 s of the recording by **coherence**: the share of the recording's power, band by band, that a fixed
   filtering of the song's audio explains. A room is such a filter, so the room does not hurt the check; crowd, talk,
   another song and distortion do. The pass mark is the 99.9th percentile of the same measurement against 3,000 random
   places in 80 randomly drawn songs of the library (chance): 0.112 of the power between 300 and 3,600 Hz. It is set
   by chance alone, not by this night's songs.
3. *Following.* A candidate that passes is followed forward and back, 2 s at a time, while it passes, with its
   place and speed carried along.
4. *Copies.* Two songs that pass at the same moment and whose own audio there is the same are copies of one
   recording (a song and the mix that holds it, or two files of one track), and count as one.
5. Each 2 s moment is then: **a known song** (one song verified), **a blend** (two at once), **talk or no beat**
   (sound without a steady beat), **silence** (30 dB or more under the median level of the known songs), or
   **unknown** (a steady beat and no song verified). The beat mark is what 19 in 20 moments with a known song reach.

**The recording, by what the key says** (minutes):

| part | recorded | known song | blend | talk or no beat | silence | unknown |
|---|---|---|---|---|---|---|
| afternoon | 167 | 55 | 8 | 16 | 75 | 13 |
| evening | 291 | 116 | 5 | 36 | 3 | 132 |
| of which the pre-mixed disc | | 10 | 0 | | | |

Verified stretches came from the matcher (351), the booth's log (1) and the search (9). The recorder's clock runs
0.09 % fast against the decks (the median speed of songs played at zero), which the check allows for.

**What I trust.** A known-song moment is strong evidence: the song's waveform is in the recording, at a place that
advances with the clock. The chance of one false pass is 1 in 1,000 per test, and a stretch needs several in a row.

**What I do not trust, and why the key is incomplete:**

- **The check needs the song to be at least about 9 dB under the rest, or louder.** Where talk or singing drowns
  the music further, the key says "talk" or "unknown" even when a song is playing. So the key under-counts songs in
  the loudest moments, which are exactly the hard cases; the matcher's names there are counted as names "with no song
  in the key" (section 4), not as right or wrong.
- **The unknown 132 minutes of the evening.** Two long stretches (45 and 78 minutes) of steady-beat music, 12 dB
  quieter at the microphone than the known songs (median level -35 against -23 dBFS). Neither recogniser named
  anything there: the booth's log has 4 entries in them, none of which the waveform check confirms, and our matcher
  named something in 0.3 % of those windows. *[inf]* Most likely music from outside the catalogue (the booth logged
  nothing new through the same stretches, letter S), or quiet background music; it cannot be settled without
  listening. It is left out of every headline number, and its share is the main limit on what this test covers.
- **Key-held playback** (the deck holding the key while changing speed) cannot be checked by the waveform. The
  matcher read no song played that way, so this did not arise.
- **The pre-mixed disc** is under-found. The key found it for 10 minutes; the matcher named the mix's own track at
  other times too, where the check failed (quiet, under talk). How long the mix really played is not known.
- **The key leans on our matcher for candidates** (351 of 361 stretches). A song it never ranked anywhere and that
  ShazamKit never logged would be missing; the search over the discs (c) found 9 such stretches.

## 3. Where the evening's time went

Of 4.85 hours recorded in the evening: known songs 2.0 hours (1.85 played live, 0.17 from the pre-mixed disc),
blends 5 minutes, talk or no beat 36 minutes, silence 3 minutes, unknown 2.2 hours. So the headline numbers rest on
about 2 hours of music, 116 songs heard for 30 s or more.

## 4. The headline: the evening's known music, the fixed settings

Windows whose sound the key gives to one song from start to end. Right: the named song is that song (or a copy of
its recording); wrong: another song; none: nothing passed the threshold. Percent of windows, which with a window
every 2 s is percent of time. (Longer windows have fewer such windows, because a 12 s window must sit wholly inside
one song.)

**Live mixing, against the discs (songs on the discs only):**

| window | windows | right | wrong | none |
|---|---|---|---|---|
| 3 s | 2,347 | 43.7 | 0.5 | 55.8 |
| 5 s | 1,944 | 67.4 | 1.0 | 31.6 |
| 8 s | 1,478 | 81.0 | 1.3 | 17.7 |
| 12 s | 1,174 | 86.6 | 2.0 | 11.4 |

**Live mixing, against the whole library:**

| window | windows | right | wrong | none |
|---|---|---|---|---|
| 3 s | 2,397 | 29.1 | 0.2 | 70.7 |
| 5 s | 1,984 | 39.8 | 0.4 | 59.8 |
| 8 s | 1,508 | 41.9 | 0.7 | 57.4 |
| 12 s | 1,197 | 41.5 | 1.0 | 57.5 |

**The "wrong" names are nearly all one kind.** Of the wrong names against the discs, 11 / 18 / 19 / 23 windows at
3 / 5 / 8 / 12 s were the pre-mixed disc's track and 2 in all were another song; the mix's track was named at the place in the mix where it holds the song
that was playing from a disc, at the same speed, advancing with the clock: the right music under the mix's file.
Against the library the same: 5 / 7 / 9 / 12 windows of the mix's track and 2 of another song. **A different song
was named in 2 windows of about 8,500 against the discs and 2 of about 8,500 against the library.**

**The pre-mixed disc, while it played** (discs catalogue; 114 to 231 windows, so these are rough):

| window | right | of which the mix's own track | of which the song's own file | wrong | none |
|---|---|---|---|---|---|
| 3 s | 4.3 | 3.9 | 0.4 | 0 | 95.7 |
| 5 s | 15.8 | 15.3 | 0.5 | 0 | 84.2 |
| 8 s | 27.0 | 23.0 | 4.1 | 0 | 73.0 |
| 12 s | 47.4 | 41.2 | 6.1 | 0 | 52.6 |

Against the library: 2.6 / 12.8 / 22.3 / 33.3 % right. The mix was named much less often than the live songs, and
the likely reason is the room, not the mix: while it played, the music stood at a median 3 dB over everything else
(full band) and 6 dB *under* it in the fingerprint's band (section 6), the quietest of the evening *[inf: it played
at the start of the evening, under talk]*. Inside the mix the songs are joined and some are re-pitched; the matcher
finds the mix's own track, which holds them exactly as heard, far more often than the songs' own files.

**How long until a song is named**, from the first moment the key hears it (songs heard 30 s or more):

| window | discs: songs | named | median | 90th percentile | slowest | never | library: median / 90th / never |
|---|---|---|---|---|---|---|---|
| 3 s | 102 | 92 | 7 s | 29 s | 147 s | 10 | 11 / 33 s / 16 |
| 5 s | 102 | 94 | 7 s | 25 s | 155 s | 8 | 9 / 31 s / 14 |
| 8 s | 102 | 98 | 7 s | 21 s | 73 s | 4 | 11 / 31 s / 5 |
| 12 s | 102 | 101 | 9 s | 25 s | 49 s | 1 | 15 / 65 s / 11 |
| any of the four | 102 | 101 | 7 s | 23 s | 49 s | 1 | 9 / 27 s / 2 |

The median includes the window's own length: a song named by a 12 s window 9 s after it began was named from a
window that started before it did, in the previous song's tail. On the pre-mixed disc (11 stretches): any length,
median 13 s, 90th percentile 51 s, all named in the end.

**Names when the key has no song** (evening, discs): during talk, gaps or silence 1 / 1 / 2 / 2 windows of 791 /
555 / 280 / 149; during the unknown stretches 0 / 4 / 6 / 12 of 3,524 / 3,247 / 2,911 / 2,694 (at most 0.4 %). None
of the talk ones and only 2 of the unknown ones were in a steady run on one place, so some may be true names the key
could not check; I count them as possible false names.

**The afternoon** (rehearsal, mostly one song at a time, discs catalogue): 66 / 87 / 94 / 97 % right at 3 / 5 / 8 /
12 s, wrong under 1 %. Against the library: 44 / 52 / 51 / 50 %.

## 5. Against ShazamKit on the same evening

**What the log can show.** One line per song change: the moment the booth *switched* to a song, in seconds of the
recording rounded to a tenth. The booth switches at once for the first song and on a hard cut, but in a blend only
after the new song has out-matched the old one for about 10 s, so in blends the log is late by design; and it writes
nothing while it stays on a song, so a song it already showed from before has no line. ShazamKit's catalogue that
night was its own: 373 songs (the booth's bundled data at the night's build, *[inf]* as letter S assumed), which I
matched to 710 library files by title, artist and length. I assume the log's time is when ShazamKit's evidence was
enough for the booth, and compare it with the first window of ours that names the song.

Songs of the evening heard for 30 s or more, ours against the library catalogue:

| song | ShazamKit's log | ours named it | stretches |
|---|---|---|---|
| in ShazamKit's catalogue | switched to it | yes | 48 |
| in ShazamKit's catalogue | was already showing it from before | yes | 29 |
| in ShazamKit's catalogue | no line for it | yes | 31 |
| in ShazamKit's catalogue | no line for it | no | 3 |
| not in ShazamKit's catalogue | no line | yes | 4 |
| not in ShazamKit's catalogue | no line | no | 1 |

- **Songs ShazamKit found and ours did not: none.** Songs ours found and ShazamKit's log does not show: 31 that were
  in its catalogue. *[inf]* Some of those are blends where the booth stayed on the old song (by design) and some are
  songs it did not match; the log cannot tell which.
- **Where both named it** (48 songs): ours, at any window length, a median 11 s after the song's start (90th
  percentile 27 s); ours from 8 s windows only, 15 s (31 s); the log, 22 s (50 s). Ours earlier by more than 2 s in
  33, the log earlier in 5, within 2 s in 10. Part of that gap is the booth's 10 s hold in blends, so it is not all
  recognition speed. Against the discs catalogue ours is faster again (median 7 s from any length).
- **Wrong names by ShazamKit.** 50 log lines in the evening; for 17 the waveform check does not find the logged song
  within 16 s, and for 13 of those it finds another song there. *[inf]* Some are ShazamKit naming the wrong song,
  some are blends where the logged song was still under the louder one, some are below what the check can see. I do
  not count them as ShazamKit's errors; the log is not truth, and neither is agreement with it.
- **Wrong names by ours**: section 4; a different song in 2 windows of about 8,500.

## 6. How loud the room was

For each known-song moment, the coherence says what share of the microphone's sound follows the song (through the
room); the rest is everything else: talk, crowd, singing along, the other deck, the room's late echo, the speakers'
distortion and the recording's own compression. The ratio of the two, in dB, is the room's **music over
everything else**.

| part | moments | 10th / 25th / median / 75th / 90th percentile, dB (full band) | median, fingerprint band (300-3,600 Hz) | over 10 dB | 5 to 10 | 0 to 5 | -5 to 0 | under -5 |
|---|---|---|---|---|---|---|---|---|
| evening, live | 3,191 | -0.4 / 3.0 / 5.0 / 6.3 / 7.4 | 2.4 | 1.2 % | 48.8 % | 38.9 % | 8.0 % | 3.2 % |
| evening, pre-mixed disc | 297 | -0.2 / 1.2 / 3.1 / 4.3 / 5.1 | -6.2 | 0 % | 10.8 % | 77.1 % | 11.1 % | 1.0 % |
| afternoon | 1,656 | -0.7 / 2.7 / 5.4 / 6.8 / 7.9 | 4.3 | 0.7 % | 54.8 % | 32.4 % | 9.2 % | 2.9 % |

In blends the louder song stood a median 2.2 dB over everything else (the other song included).

**Where this booth sits on W2's table** (8 s, right percent, the outside benchmark with crowd noise, music over
noise): room alone 95; +10 dB 89; +5 dB 75; equal 60; 5 dB under 33. This evening's live music was at about +5 dB
by this measure, half of it between +5 and +10, a third between 0 and +5, and about one moment in nine at or under
equal.

**The result by the room's level**, live and pre-mixed together, discs catalogue, right percent (windows):

| music over everything else | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| over 10 dB | 86 (28) | 96 (26) | 100 (20) | 100 (16) |
| 5 to 10 dB | 54 (1,245) | 79 (1,100) | 90 (879) | 94 (732) |
| 0 to 5 dB | 27 (1,096) | 45 (878) | 60 (662) | 68 (514) |
| -5 to 0 dB | 19 (170) | 39 (114) | 32 (59) | 54 (26) |
| under -5 dB | 33 (39) | 68 (22) | 6 windows | none |

The 5 to 10 dB row (90 % at 8 s) sits between W2's "room alone" and "+10 dB"; the 0 to 5 dB row (60 %) sits at W2's
"equal". That is what one would expect if this measure reads a few dB lower than W2's, which it should: W2 counted
the room's echo as music, and this counts the late echo as "everything else".

**The louder moments**, the nearest thing here to a hard case: one-song moments with the music at or under equal
are 11 % of the evening's live music, about 12 minutes. Between equal and 5 dB under, the matcher was right in 32 % of 8 s windows and 54 %
of 12 s windows (59 and 26 windows: rough). Moments too loud for the key to see a song at all (talk and unknown) are
not in this table.

**How sure the estimate is.** On test sounds of known level (noise at +10, 0 and -5 dB through an echoing filter)
the measure read +10.1, +0.4 and -4.6 dB. On the real recording it reads low, for four reasons that all push the
same way: echo longer than about a tenth of a second, the speakers' and recorder's distortion, the recorder's
compression and automatic level, and the DJ's own moves (EQ, faders) within the 6 s. And it reads high for one
reason: only moments the key could verify are in it, which leaves out the loudest. So: the music's lead at this
booth's microphone was **about +5 dB, probably a little more in W2's terms, for most of the known music**, and the
loudest stretches are under-represented. *[inf]* A quiet house party with the iPad near the decks; a club would be
louder at the microphone and is not measured here.

## 7. The fader

Read on right answers from 12 s windows, per song heard for 30 s or more (discs catalogue, 108 songs: 100 live, 8
on the pre-mixed disc). All readings include the recorder's clock, 0.09 % fast.

| measure | value |
|---|---|
| range of readings, per song (median of its windows) | -7.4 % to +7.2 % |
| songs read more than 0.5 % off zero | 91 |
| more than 2 % off | 29 |
| more than 4 % off (beyond what ShazamKit covers with one signature) | 7 |
| steadiness within a song (spread between the 25th and 75th percentile of its windows) | median 0.064 points, 90th percentile 0.116 |
| key held (tempo moved, pitch did not, by 1 % or more) | 0 songs |
| against the booth's own pitch reading (38 songs both named) | difference median 0.09 points, 90th percentile 0.80 |
| booth logged 0 where ours read 1 % or more / ours under 0.5 % where the booth logged 1 % or more | 0 / 0 |

So the DJ played vinyl-style throughout (key moving with speed), a quarter of the songs more than 2 % off and a few
more than 4 % off; the reading held to a few hundredths of a point through a song. The 7 songs beyond 4 % were named
as readily as the rest at 12 s (misses there: 2 windows of 12 s against the discs).

## 8. Where it fails

Known-song windows of the evening not named right, by the first likely cause that applies (discs catalogue;
windows at 3 / 5 / 8 / 12 s). These are inferred from the measurements; nobody listened.

| likely cause | 3 s | 5 s | 8 s | 12 s |
|---|---|---|---|---|
| the deck more than 4 % off | 133 | 52 | 11 | 2 |
| music at or under everything else (talk, singing, crowd) | 144 | 80 | 46 | 20 |
| named another song (nearly all: the mix's track holding the playing song) | 13 | 20 | 24 | 27 |
| a quiet passage (15 dB or more under the songs' median level) | 66 | 37 | 15 | 3 |
| the song's first 20 s | 142 | 76 | 37 | 16 |
| within 10 s of a blend | 111 | 54 | 17 | 6 |
| none of these | 983 | 520 | 269 | 166 |

- **Short windows at a far-off fader** fail; from 8 s they do not. A 3 s window at 6 % holds less of the song and
  the speed search has less to fit.
- **Loud moments and quiet passages** are the next causes, as the outside benchmark predicted.
- **"None of these"** is the largest group: music at 0 to 5 dB over the rest with nothing else marked. That is the
  room's ordinary level, and it is where the matcher's weakness in noise shows (60 % at 8 s in that band).

## 9. What it means

- **In this booth, on the discs' songs, it works**: four in five 8 s windows right, a song named a median 7 s in,
  one song in a hundred never named, a different song named in 2 windows of about 8,500, and the fader read through
  the whole range played, beyond ShazamKit's. It was usually earlier than ShazamKit's log (first in 33 of 48 songs
  both named, against 5).
- **Against the whole library it does not work yet, for a reason that is not noise**: copies of one recording.
  168 of the 195 songs heard have two or more files of the same recording in the library (79 two, 49 three, 40
  four or more). The confidence is the best song's score over the third best's; with two or three copies, the third best is the same recording and the answer
  never clears the threshold. Ways out, as options: fold copies into one entry when the index is built (D24's "same
  recording" key, which Desk does not fill yet, letter U), or measure the yardstick against the third best *distinct
  recording*. Both are changes to the recogniser or the crate, outside this test; a variation in section 11 shows
  what folding copies by title, artist and length gives.
- **The noise question is still open.** This room was mostly 5 to 10 dB in the music's favour. The trial's gap to
  ShazamKit was at equal level and below; this evening has about 12 minutes of that, too few to settle it.
- **The unknown 2.2 hours** are a hole in this test, not a result about the recogniser.

## 10. Running it

```bash
CRATE=/path/Library.deckiecrate MUSIC=/path/music RECORDINGS=/path/Sets WORK=/path/ignored/work \
SUBSETS="disc/folder/prefix/" MIX="premixed/disc/folder/" PART_FROM=2026-10-24T23:00:00Z \
BOOTH_CATALOGUE=/path/booth-catalogue.json EXTRA=/path/more/music \
    core/Tools/recognition-bench/room_test.sh
```

Writes `WORK/report.md`. WORK must be outside the repository or in an ignored folder. It needs Swift 6, ffmpeg and
Python 3 with numpy. Every heavy step runs under `nice -n 19` with 2 workers. Times on this Mac: fingerprinting the
library 11.4 min; matching 54,780 windows, 10.8 min against the library and 6.9 min against the discs; building the
answer key 56 min (one worker, of which about 10 min the chance measurement, cached after the first run); the report
seconds.

## 11. Variations (not the headline)

Both use the same matcher, settings and threshold; only the catalogue changes. The answer key is the same.

**A. The library with copies folded by name.** One file kept for each title, artist and length within a second
(2,004 files of 2,327; a disc's own file kept where there is one). This is a crude fold: it leaves copies whose tags
differ, so of the 195 songs heard 82 have one file left, 70 two, 21 three and 21 four or more.

**B. A bigger real catalogue: the library and the owner's newly added music.** 1,070 more songs (66.6 hours): every
finished file in the added folder, skipping 347 files still downloading (named `.part`), 5 files of 15 minutes or
more set aside as published DJ mixes (told by length alone), and 1 file under a minute; 1 more file failed to
decode. 3,396 songs in all: 27.1 million points, 160.8 million hashes, index built in 29.6 s; fingerprinting the
added songs took 8.3 min (2 workers), 22.9 MB on disk.

Live mixing in the evening, right percent at 3 / 5 / 8 / 12 s (wrong at most 2 % in every row):

| catalogue | songs | 3 s | 5 s | 8 s | 12 s | a song named, from any length: median / 90th percentile / never |
|---|---|---|---|---|---|---|
| the discs (headline) | 92 | 43.7 | 67.4 | 81.0 | 86.6 | 7 s / 23 s / 1 of 102 |
| A. library, copies folded by name | 2,004 | 34.4 | 54.2 | 64.2 | 71.7 | 9 s / 27 s / 3 of 105 |
| the library (headline) | 2,327 | 29.1 | 39.8 | 41.9 | 41.5 | 9 s / 27 s / 2 of 105 |
| B. library and the added music | 3,396 | 28.4 | 39.8 | 42.0 | 41.2 | 9 s / 27 s / 3 of 105 |

- **Folding copies gives back most of what the library lost** (42 to 64 % at 8 s) even done crudely; the rest of the
  gap to the discs is mostly the copies the fold missed *[inf: the fold leaves 112 of the 195 songs with copies]*.
  So the library's problem is copies, not size.
- **A thousand more real songs changed nothing** for the party's songs: the same right and wrong shares to within
  a point, and among the evening's known songs the added music was named in 4 / 2 / 1 / 0 windows.
- **The added music was not all distractors.** The owner's note is that none of it was played. But the matcher named
  9 of the added songs in 748 windows of the evening, and the waveform check confirms 5 of them really in the room at
  731 of those windows: 278 moments (9 min), 189 of them inside the "unknown" stretches and 72 at the same moment as a
  known song (so some added files are copies of library songs). *[inf]* The added folder holds some of the music that
  played in the unknown stretches, or copies of it. Counting every added-music name as wrong, as asked, gives at
  most 17 windows (2 / 0 / 1 / 14 at 3 / 5 / 8 / 12 s) out of the evening's 8,708 per length that the waveform
  does not confirm; that is the bigger catalogue's real count of possible false names. The afternoon: none.
- **Memory and time.** The bigger index's process peaked at 1.92 GB on a small batch (1.31 GB for the library; so
  about 0.57 MB more per added song). The matching runs for A and B shared this Mac with another session's heavy jobs
  (load average 17 to 19 against the 2 to 3 of the earlier runs), so their times are not comparable: B took 27.5 min
  for the 54,780 windows and A 15.4 min, against 10.8 min for the library earlier; a fair timing needs a quiet machine
  [unmeasured].

## 12. What I could not do

- **Listen.** Every cause in section 8 and every "[inf]" is read off measurements.
- **Tie the unknown 2.2 hours to anything**, or say how long the pre-mixed disc really played.
- **Check songs drowned by talk**: the waveform check needs the music within about 9 dB of the rest.
- **Run ShazamKit again on the recording**: the booth's log is all there is of it; its catalogue that night is
  taken from the night's build *[inf]*.
- **A loud room.** None in this material.
- **Time the bigger catalogue fairly**: another session's jobs were running when it was matched.
- **Fold copies properly.** Variation A folds by name only; folding by recording (the crate's cut key, or the
  fingerprints themselves) was not built, since it changes the recogniser or the crate and this test changes neither.
