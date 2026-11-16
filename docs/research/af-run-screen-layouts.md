# Research AF: the run screen, laid out four ways

Dated Nov 16, 2026. A design letter for the run screen (D37, moving since letter AD), after the owner's notes: see a
few versions; one closer to the booth, with the song on one side and the other information on the other; one with the
second row of figures restacked into two rows set in columns; and, for every number, what it says and whether it says
it well ("I like the key thing but does it need notes in there? What does that min number mean?"). Every element and
the motion stay. This letter audits each element, describes the four versions built to compare, and recommends one.
Nothing a DJ sees has changed: the versions are behind a switch, and the Mac's window is untouched until one is chosen.

## In plain words

The **run screen** is what Desk shows while it reads a crate. The **song on stage** is the song Desk has just read,
shown large with its wave. A **wave** here is the song's loudness, stretch by stretch, from start to end. **Tempo** is
the beats a minute (BPM). A **bar** is four beats. A **key** is the set of notes a song is built on; DJs write it as a
**Camelot code**, a number from 1 to 12 and a letter (A minor, B major), because two songs mix in key when their codes
are the same or one apart. The **Camelot wheel** is the twelve numbers round a clock face, the minor keys inside the
major keys that share their notes. A **home note** is the note a song keeps returning to; Desk sometimes finds it
without being sure whether the song is major or minor. A **histogram** is a row of bars, each as tall as the number of
songs in its range.

## Part 1: every number and mark, and whether it says what it means

What the code does is from `desk-web/run.js` (the Mac's `RunScreen.swift` draws the same) and the engine's
`core/Sources/DeckieDesk/RunSongs.swift`. "At a glance" is what a DJ would most likely take it to mean, reading
quickly from across a desk. The rule applied: a number is labelled as what it is (tempo, fader pitch, key), in plain
words, and plain theory is added beside it where it helps.

| Element | What it is, exactly | What a DJ would take it to mean | Match? | Recommendation |
|---|---|---|---|---|
| Crate name and Stop | The crate being filled; click to rename. Stop finishes the songs being read and keeps them | The same | Yes | Keep |
| "Reading your crate" and "Adding Stick 1 to Stick 1" | The step and what is being added to which crate | Clear, though a source and a crate with the same name read twice | Mostly | Keep. When the source and the crate share a name, say it once ("Reading Stick 1"). Copy audit |
| Progress bar and "6 of 11 songs" | Songs read of songs found | The same | Yes | Keep |
| "Reading tempo, key and bars" | The step Desk is on | The same | Yes | Keep |
| "About 2 minutes left" | Time left to wait, estimated from runs timed on this computer | The same | Yes | Keep. It is the only time-to-wait figure on the screen; nothing else should look like it (see "Music read") |
| The quiet line ("Fastest so far: Tidewater, at 172 BPM.") | A true thing just found, or a line about the step | The same | Yes | Keep |
| "You can leave this running…" | Reassurance | The same | Yes | Keep |
| Song on stage: name and artist | The song just read | The same | Yes | Keep. Larger, as the booth shows the playing song (versions A, B, D) |
| "Read before" chip | The song was worked out on an earlier run and not read again | Could read as "you have played this before" | Partly | Keep; the copy audit could say "Already read" |
| The wave | The song's loudness in 64 stretches, start to end, on one scale for every song; it pulses on the song's beat and breathes for the pleasure of it (letter AD) | A waveform, as in DJ software: loud and quiet parts | Yes | Keep. The motion is decoration and is not the song's real movement, which is fine because nothing claims it is |
| Marks under the wave | A cut through the wave and a short mark every 8 bars, a longer one every 32 | Could be taken for cue points or hot cues, which DJ software marks the same way | Partly | Keep; unlabelled is acceptable as decoration. If it ever needs saying, the wave's spoken label already says "bar by bar" |
| Tempo "74.3 BPM" | The beat grid's tempo, to a tenth of a beat a minute; amber, as the booth's tempo line | The same | Yes | Keep. Show a whole tempo without ".0" ("90 BPM", as the booth shows "128 BPM"); keep the tenth when it is not whole |
| Key "9A · E minor" | The key Desk decided: the Camelot code, then its name. "Home note E" when only the home note was found; "Not sure" when nothing was | The code is what a DJ mixes by; "E minor" is what a musician calls it | Yes, both right | Keep both, but give the code the weight and the name less: "**9A** E minor", the name smaller and quieter. See below |
| Bars "30" | Bars in the song's beat grid | The song's length in bars, as a DJ counts phrases | Yes | Keep. Lower in the order than tempo and key |
| Length "1:40" | The file's playing length, minutes and seconds | The same | Yes | Keep |
| Where "Stick 1 6" | The source's name and the song's number in it | "Stick 16", or a folder called "Stick 1 6" | **No** | Separate the two: "Stick 1 · 6" or "Stick 1, song 6" (a change in the engine's place line, `Crate.placeLine`); and place it above the name, unlabelled, as the booth places "CD2 / 110-124 /" (versions A, B, D) |
| "3 more songs joined the crate" | Shown when Desk read faster than the stage could show, so some songs went straight to the wall | The same | Yes | Keep |
| **"Music read: 12 min"** | The playing time of every song read so far, added end to end, in whole minutes (rounded down, so "0 min" until a minute of music is in) | "I have been reading for 12 minutes", or, beside "About 2 minutes left", a second clock | **No** | Relabel: "Total playing time" (version D), so it reads as the length of the music, not of the wait. See below |
| Tempos picture | A histogram of tempos in 2 BPM steps from 50 to 250; the newest song's bar white | The spread of the crate's tempos | Yes | Keep. The picture has no ends marked; the sentence under it gives them |
| "6 songs, from 74 to 172 BPM, most around 75" | The count with a tempo, slowest and fastest, and the middle of the fullest 2 BPM step | "Most of my songs are near 75" | **No, early in a run** | With every song alone in its step the "fullest" step is just the first one. Say "most around" only when some step has two or more songs (version D) |
| Keys wheel | 24 cells, one a key; filled when a song has it, brighter with more. Today each home note's major and minor sit together, C at the top. Dots inside: songs with the home note only | The Camelot wheel | **No** | It looks like the Camelot wheel but is not arranged like it: on the Camelot wheel each minor key sits inside the major key that shares its notes (8A A minor inside 8B C major), and 12 is at the top. Draw it that way, with 12, 3, 6 and 9 round it (version D). It needs no note names: a DJ reads it by its numbers |
| "4 of the 24 keys, 2 not sure" | Keys found, songs with the home note only, songs with no key | The same | Yes | Keep |
| "Need a name 0" | Songs with no usable title or no artist yet | The same | Yes | Keep |
| "In two places 0" | Songs found twice in what is read: the same file in two folders | Could be "two copies" in the looser sense, which is the next line | Mostly | Keep; the copy audit could say "Same file twice" |
| "Copies of one recording: when saving" | Songs that are copies of one recording (the same song, different files); counted while saving, so unknown until then | "when saving" sits where a number goes and reads as a value | Partly | Keep. Set as a tile, label over value, it reads naturally ("Copies of one recording / when saving", versions C and D) |
| "Didn't go in 0" | Files that could not be read | The same | Yes | Keep. The warning line under the progress says it too when it is not 0 |
| The crate so far (the wall) | One line a song, its wave, as they joined; the newest white; point at one to name it | The crate filling up | Yes | Keep |
| "Every file, as it goes" | The plain list of files read | The same | Yes | Keep |

### The two questions

**Does the key need the note names in it?** Not for mixing: the Camelot code ("9A") is what a DJ mixes by, and it is
what the booth and the songs table show. But the name ("E minor") is the plain theory under the code, and the project
adds plain theory beside a number when it comes up. So keep it, as a gloss: the code first and strong, the name after
it, smaller and quieter (version D does this). The wheel of keys has no note names and needs none; what it needs is to
be the wheel DJs know (relative keys together, 12 at the top, the numbers round it). If "notes" meant the small dots in
the middle of the wheel: they are songs whose home note Desk found without major or minor; they are hard to read at
that size, and the sentence under the wheel already counts them ("2 with the home note only"), so they could go
without losing anything.

**What does the "min" figure mean, and does its label say so?** It is the total playing time of every song read so far,
added end to end ("12 min" is twelve minutes of music, about six songs here), rounded down to whole minutes. Its label,
"Music read", does not say that: next to "About 2 minutes left" it reads as a second clock, either the time spent
reading or another estimate. "Total playing time" says what it is. A tooltip on it in version D says "All the songs read
so far, end to end".

## Part 2: four versions to compare

All four are built in the Windows and Linux window (`desk-web/`), keep every element, the crate's name and Stop above,
the motion (the sweep from song to song, the pulse on the beat, the breath, the playhead's glow) and the stillness under
reduced motion. In a window narrower than 860 pixels, A, B and D put the song above the figures; C's counts go two to a
row.

- **Today** (the reference): the song on stage across the top, its wave on the left and its facts on the right; one
  row of four figure cards; the wall.
- **A, like the booth**: the song on the left as the booth's playing panel (a tall panel in the booth's indigo, the
  place line in lavender above the name, the name large, the artist under it, tempo in amber and key, the wave large
  in the middle, bars and length under it); on the right, under a small "FOUND SO FAR" head in the manner of the
  booth's "PICKS", the figures as a list of cards, words on the left and the picture on the right, as a pick shows
  its words and its chart. The wall under both.
- **B, the same swapped**: the figures on the left, the song on the right.
- **C, columns**: today's arrangement, with the figures restacked as two rows set in columns: the three pictures
  (music read, tempos, keys) in three equal columns, each label over its picture over its sentence, lined up; then
  the four counts as four tiles, each label over its number.
- **D, the audit applied** (my answer): A's arrangement, with the counts as tiles (as C), and the audit's changes:
  "Total playing time" for "Music read"; the key as "**9A** E minor"; a whole tempo without ".0"; "most around" only
  when two songs share a tempo step; the wheel of keys as the Camelot wheel, larger, with 12, 3, 6 and 9 round it.
  Not changed in D, because the change belongs in the engine and both windows: the place line ("Stick 1 6").

## Recommendation: D, and A if the changes wait

D. It is the booth's way of showing a song, so the run screen and the booth feel like one product, which is what the
owner asked for; the song is large enough to enjoy while it moves; and every number in it says what it is. Of the
layouts alone, A over B: the booth puts the song on the left, and a DJ who knows the booth looks there first. C is the
smallest change from today and fixes the alignment he noticed, but it keeps the song as a strip, which is the part
the booth does better. The wording changes in D ("Total playing time", "most around" only when true, the key's code
first, the Camelot wheel) are worth taking whichever layout is chosen, and the place line should become "Stick 1 · 6"
in the engine.

## How to see them

`DECKIE_RUN_LAYOUT` names the layout: `today` (also anything else, or nothing), `a-booth`, `b-swapped`, `c-columns`,
`d-plain`. The engine reads it and sends it to the pages in its first message (`runLayout`, beside `computer`);
desk.js sets it on the page, and desk.css lays the run screen out by it. For example:

    DECKIE_RUN_LAYOUT=a-booth DECKIE_DESK_HOME=/tmp/desk .build/debug/deckie-desk

The words only the trial layouts show are in `DeskWords` (marked as placeholders): `figuresHead`, `figMusicTotal`,
`figMusicTotalHelp`, `figTemposRange`, `keyNameValue`.

Stills and clips of each, from a recorded run on generated songs with invented names (the run-motion work's
recording, replayed on a stepped clock in headless Chrome, at 1200 by 900 and one and a half times scale), are in the
main checkout's `.scratch/run-layouts/` (git-ignored): `today`, `a-booth`, `b-swapped`, `c-columns`, `d-plain`, each a
`.png` and a ten-second `.mp4` with two changes of song, and `contact-sheet.png`.

## Not verified

- On Windows (WebView2) and Linux (WebKitGTK): the layouts use CSS grid, `display: contents` and `:is()`, which both
  support, but they were seen only in Chrome on the Mac.
- Speed: the drawing is the same; only the stage's wave is larger in A, B and D (more pixels a frame). Not measured.
- The Mac's window: unchanged on purpose until a version is chosen.
- With a person: no DJ has seen these.
