# Research AA2: "Look up songs via MusicBrainz" on a real library

Dated Nov 14, 2026. A trial with measurements, no decisions. It runs the lookup built under D36 (with the note on
D30, and D34 for the facts it fills) on the owner's own library, on his Mac, with the trial tool
`deckie-lookup-trial`. Nothing in the lookup was changed or tuned to this library. **Aggregate numbers only: no
song, artist, file name or row of the results is in this letter or anywhere in the repository.** The results files
stay on the owner's Mac. Tags: [hand] = judged by reading the rows privately, not by a rule; [inf] = my inference,
with the reasoning.

## In plain words

The lookup sends a song's words to MusicBrainz, the open music catalogue, and gets back **candidates**: recordings
that might be the song. Desk ranks them, first by whether their **length** matches the song's (within 3 seconds),
then by how well they agree with what Desk already knows. Desk **chooses** a candidate by itself only when exactly
one song fits by length, is not plainly another version, and agrees with the title and artist Desk has. Everything
else is shown to the DJ as a list to pick from. Choosing nothing is the lookup's way of failing quietly.

The trial asked two questions.

1. **Tags hidden.** Pretend the files have no tags, as a stick or a folder of songs with no labels would be, and
   look each song up from its **file name** alone. Then score what Desk would choose against the tags the files
   really carry. This is the "songs with no names" case the owner asked for.
2. **Tags used.** Look each song up from its title and artist tags, as "fill in release, year and label for songs
   I already have names for" would. Here the question is what the lookup adds.

A candidate the trial calls **agree** has the file's title and artist; **wrong version** has them but another
version (a remix for an original or the reverse); **wrong** differs on title or artist. The trial's own compare
is strict, so every "wrong" was also read by hand [hand].

## Summary

- **When Desk chooses by itself, it is almost always right.** From file names alone it chose a candidate for 53
  percent of songs, and 98 percent of those match the file's own tags exactly as the trial scores them. By hand,
  of the 22 the trial marked wrong, about 18 are the right song written another way (a shared credit written
  "A, B" against "A feat. B", a fuller title, a wrong tag); 3 to 4 are plainly another song or version. That is
  under half a percent of what Desk would fill in. The 3 "wrong versions" are files whose name and tag disagree. From tags: 59 percent chosen, 98 percent agree, about 1
  to 4 plainly wrong [hand].
- **Something is found for nine songs in ten** (90 percent from file names, 87 percent from tags), but most
  of the rest are songs MusicBrainz knows in another version: a DJ's remix, an extended mix, a clean or dirty edit.
- **The songs no catalogue holds are where it gives least, as expected.** In the DJ's own folders (discs, pools,
  sets) Desk chose for 42 percent (47 from tags); among the loose remixes and edits at the top of the library, for
  none; songs whose title tag names a version, 34 percent against 58 for plain titles. It never offered an original
  in their place by itself: those come back as a list to pick from.
- **Album folders with file names like "01. Title" got nothing chosen from file names** (0 of 127) because the
  file name has no artist and a title alone is, by design, a list. With the artist known, 86 percent were chosen.
  The artist is in the folder's name.
- **What a lookup adds to named songs:** for the 1,314 songs it chose from tags, it has a **year** for 97 percent
  (and would fill 213 songs that had none), a **label** for 91 percent (780 songs had none), and a **release** for
  all but one; but the files already carried a release for nearly all of them, and the release it proposes is the
  song's first own release, not the compilation the file came from, so it agrees with the file's release for only 24
  percent. Years agree within one year for 52 percent; most of the rest are compilation or reissue years in the
  file.
- **MusicBrainz was polite throughout.** 5,933 requests in all, about 1.8 percent answered "busy" (503), every
  one cleared by the code's own wait and second ask; none needed a third, none was refused, nothing failed. The
  two full runs took 61 and 71 minutes of which the lookups were 39 and 61 minutes.

## What was run

| | |
|---|---|
| Library | one folder on the owner's drive: 3,027 audio files |
| Left out | the disc-burning copies: `CDs v2` (573 files) and every folder starting `_` (32 files, plus one with none) |
| Copies kept once | 153 byte-for-byte copies and 35 more that differ only in their tags (same size and audio bytes) |
| Songs tested | **2,234**, all MP3 but two |
| Tool | `deckie-lookup-trial`, built from `main` at `4ab49f3` with `nice -n 19`, one job |
| Runs, in order, never two at once | 50 songs (`--limit 50`), then all with tags hidden, then all with `--use-tags --labels` |
| Pace and sender | the code's own gate (one request a second) and its own User-Agent; nothing else sent |

The song list was made by links in `.scratch/lookup-library/` (ignored by git) to the files that remain, so the tool
read exactly those. Hidden files and folders are skipped by the tool as Desk skips them.

**One change to the trial tool** (commit `4ab49f3`, the only commit; not pushed). Its rows did not record the
candidate's release, year and label, nor the file's own release, year and label tags, so it could not answer "what
would the lookup fill". Each row now keeps them, with the candidate's notes, why it was not chosen, and any
failure; and `--labels` asks for the label of the chosen release as Desk itself does (the trial had left that out
to halve its requests). Nothing in the lookup's rules or thresholds changed.

## Results: tags hidden (file names only)

| | songs | share |
|---|---:|---:|
| Songs | 2,234 | |
| Nothing could be sent (a file name that says nothing, as "Track 04") | 1 | 0.04% |
| Sent as title and artist (a file name with a dash) | 2,025 | 91% |
| Sent as free words (no artist in the file name) | 208 | 9% |
| At least one candidate | 2,015 | 90% |
| MusicBrainz knows nothing | 218 | 10% |
| **Desk would choose by itself** | **1,185** | **53%** |
| of those, no title tag to judge by | 10 | |
| agree with the tags (trial's compare) | 1,150 | 97.9% of 1,175 judged |
| right song, other version | 3 | 0.3% |
| title or artist differs (trial's compare) | 22 | 1.9% |
| right song by a looser compare (title words; any shared credited name) | 1,160 | 98.7% |

The **3 wrong versions**: twice the file's tag names an edit that its file name does not and the candidate is the
plain song at the same length; once the file name names a club mix that its tag does not. Each is as much the
file's own disagreement as the lookup's [hand].

The **22 the trial marks wrong**, by hand: 9 are the right song whose shared credit is written another way (the tag
lists the artists with commas), 1 has a wrong artist tag and the lookup is right, about 8 are the right song under
its fuller title, and 3 to 4 are another song or another version (a longer title that contains the file's, an
artist whose name contains the file's) [hand].

**Found but not chosen** (830 songs), and how often the first candidate shown is the file's song by the looser
compare:

| why Desk did not choose | songs | first shown is the song |
|---|---:|---:|
| Several different names fit by length | 279 | 82% |
| Fits by length, but is plainly another version | 216 | 96% (title and artist; version differs) |
| No candidate within 3 seconds of the song's length | 179 | 92% (title and artist) |
| Fits, but no artist was known, or title or artist disagree | 85 | 49% |
| The first candidate has no length in MusicBrainz | 71 | 70% |

Of the 179 with no fitting length, the candidate was shorter for 106 and longer for 73; for 76 it was within 10
seconds, for 62 more than 30 seconds off (a remix or an extended mix against a radio length).

## Results: tags used, release year and label asked for

| | songs | share |
|---|---:|---:|
| Sent from tags as title and artist | 2,116 | 95% |
| Sent from tags as title alone (no artist tag) | 59 | 3% |
| Sent from the file name (no usable title tag) | 58 | 3% |
| Nothing could be sent | 1 | |
| At least one candidate | 1,946 | 87% |
| **Desk would choose by itself** | **1,314** | **59%** |
| agree with the tags (trial's compare) | 1,292 | 99.0% of 1,305 judged |
| right song, other version | 0 | |
| title or artist differs (trial's compare) | 11 | 0.8% |

All 11 "wrong" are shared credits written another way. The looser compare leaves 15 apart; by hand about 11 of
those are the right song with a fuller title or credit and 1 to 4 are another song [hand].

Fewer songs are found from tags than from file names (87 against 90 percent), because the tag's artist and title
are sent as required phrases. Of the 287 that found nothing: 118 have brackets in the title tag, 73 have several
artists in one artist tag (commas or slashes), 62 have a version after a dash in the title tag, 57 name a
featured artist (one song may show several of these).

## By kind of song

Chosen by Desk, out of the songs of each kind (agree in brackets: chosen and matching the tags).

| kind | songs | found, names | chosen, names | found, tags | chosen, tags |
|---|---:|---:|---:|---:|---:|
| Compilation downloads (9 folders) | 1,540 | 93% | 64% (950) | 89% | 63% (958) |
| The DJ's own folders: discs, pools, sets (5 folders) | 492 | 89% | 42% (200) | 89% | 47% (225) |
| Artist albums (3 folders) | 127 | 98% | **0%** | 94% | 86% (109) |
| Loose files at the top (mostly remixes and edits) | 75 | 31% | **0%** | 25% | **0%** |
| File tagged as part of a compilation | 644 | 97% | 66% | 88% | 70% |
| Not tagged so | 1,590 | 87% | 48% | 87% | 54% |
| Title tag names a version (remix, edit, extended) | 386 | 77% | 34% (124) | 73% | 34% (131) |
| Plain title | 1,793 | 94% | 58% (1,026) | 91% | 65% (1,161) |
| No usable title tag | 55 | 56% | 18% | 56% | 16% |

By the decade of the year tag (a compilation's year where the file has only that; 490 songs have no year tag):

| decade | songs | chosen, names | chosen, tags |
|---|---:|---:|---:|
| 1960s to 1980s | 5 | 1 | 2 |
| 1990s | 865 | 57% | 60% |
| 2000s | 75 | 35% | 72% |
| 2010s | 105 | 40% | 67% |
| 2020s | 694 | 61% | 65% |
| no year tag | 490 | 41% | 45% |

The 2000s and 2010s gain most from tags. [inf] Their file names more often leave out a featured artist or a
version that the tags and MusicBrainz carry; the rows support it only loosely.

## What the lookup adds when the name is known

For the 1,314 songs Desk would choose from tags. "Fills" is what Desk ticks by itself: an empty field; a field the
file already has is shown but not ticked.

| field | candidate has one | file had none (Desk fills) | file had one | agrees with the file |
|---|---:|---:|---:|---:|
| Release | 1,313 | 8 | 1,305 | 311 (24%) |
| Year | 1,279 | 213 | 1,066 | same year 389 (36%); within one year 160 more (15%) |
| Label | 1,197 | 780 | 417 | 0 (see below) |

- **Release.** MusicBrainz's release for a recording is chosen by the code as its earliest official release that is
  not a compilation (unless Desk already knows the release). The files here mostly came from compilations, and
  their release tag names the compilation, so the two differ for three songs in four. Both can be true; they answer
  different questions ("first released on" against "this copy came from").
- **Year.** Of the 517 years that differ by more than one, the file's is later for 375 (a compilation or reissue
  year) and earlier for 142.
- **Label.** The label tags in this library are almost all two values that are not record labels (a collection's or
  an uploader's name), so the comparison says nothing about MusicBrainz; for 780 songs the lookup would give the
  first label a field ever had.
- From file names alone the same pattern holds: a year for 97 percent of chosen songs (196 with no year tag) and a
  release for nearly all.

## Requests, busy answers and time

| | 50-song pass | tags hidden | tags used, with labels |
|---|---:|---:|---:|
| Requests | 51 | 2,284 | 3,598 (2,281 searches, 1,317 for a label) |
| Answered "busy" (503) | 1 | 51 (2.2%) | 52 (1.4%) |
| Busy episodes cleared on the first ask again / the second | 1 / 0 | 39 / 6 | 44 / 4 |
| Refused, failed, gave up | 0 | 0 | 0 |
| Whole run | 1.8 min | 60.6 min | 70.8 min |
| of it, the lookups | 0.9 min | 39.4 min | 61.3 min |

The rest of each run is the tool reading every file's length (a full decode, about half a second a song here). The
one-second gate held; MusicBrainz still says "busy" now and then at exactly its own average rate, and the code's
wait-and-ask-again (2 then 4 seconds) always cleared it.

## The patterns behind most misses

From file names, tags hidden. "Found" and "chosen" are the shares among the songs with that pattern, against the
songs without it.

| pattern in the file name | songs | found | chosen | without it: found, chosen |
|---|---:|---:|---:|---:|
| 1. No artist in the name ("01. Title" in an album folder, or a title alone) | 101 | 98% | 0% | 90%, 56% |
| 2. A version in the name (remix, edit, extended, dub, intro) | 470 | 75% | 34% | 94%, 58% |
| 3. The version after a second dash ("Artist - Title - Someone Remix") | 127 | 61% | 45% | 92%, 54% |
| 4. A featured artist in the name | 95 | 76% | 18% | 91%, 55% |
| 5. A short form of the version ("Rmx") | 39 | 67% | 0% | 91%, 54% |
| 6. A one-letter marker the DJ put before the artist | 37 | 24% | 3% | 91%, 54% |
| 7. "Clean" or "Dirty" in the name | 30 | 43% | 7% | 91%, 54% |
| 8. Underscores for spaces | 27 | 70% | 37% | 90%, 53% |
| 9. The artist read from the name is not the tag's (title before artist, an artist's name cut) | 21 | 24% | 10% | 91%, 53% |
| 10. A website's name in the file name | 6 | 17% | 0% | 90%, 53% |
| A track number in front ("01 ", "001. ") | 2,016 | 93% | 58% | 69%, 11% |

The last line is not a miss: the reader takes track numbers off well, and the files with them are mostly
compilations. One edge of it is: an artist whose own name starts with a number of up to three digits loses it when
there is no track number in front (seen in the 50-song pass; most of the 42 such songs had a track number first and
were read right).

Beyond the names, the four reasons in the "found but not chosen" table above explain the rest: several names
fitting, another version fitting, no fitting length, and no length in MusicBrainz.

## Suggestions, with their evidence (the owner decides; none is made here)

1. **Take the artist from the folder when the file name has none.** D30 already lists folders among the names on
   the computer. Album folders: 0 of 127 chosen from file names, 109 once the artist is known. [inf] A folder named
   "Artist - Album (year)" gives the artist; a compilation's folder must not.
2. **Read a version after a second dash as a version**, and drop "clean", "dirty", "explicit" and a website's name
   from the words sent. Patterns 3, 7 and 10: found 61, 43 and 17 percent against about 91.
3. **When title and artist find nothing, ask once more with the words as free words** (one more request a song,
   only for those). 218 songs found nothing from file names; patterns 6 and 9 (a marker, a cut or swapped artist)
   are found a quarter of the time, and free words do not require the artist to match. From tags, send only the
   first of several comma-separated artists: 73 of the 287 tag misses list several.
4. **Look again at "several different names fit".** 279 songs from names, 195 from tags; the first candidate is the
   song for 82 to 84 percent. [inf] Most look like the same song credited in two ways (with and without a featured
   artist) or a tribute copy of the same length; counting "same title, sharing the first credited artist" as one
   name would let Desk choose many of them. The rows do not keep the other candidates, so this needs a look before
   any change.
5. **Compare versions by their kind, not their spelling.** Of the 216 "another version" that fit by length, 66 have
   the same version words on both sides written differently ("Extended" against "Extended Mix", or brackets that are
   part of the title rather than a version). A further 79 are a plain file name against an "edit" or "radio edit" of
   the same length, which is probably the same recording. Choosing those, with the version left unticked, is a
   question for D19's note on versions, not a fix.
6. **Tighten "agrees" from contains to whole words at the edges.** The few plainly wrong choices came through
   "contains": a short title inside a longer one, an artist's name inside another artist's.
7. **The release a lookup proposes for a song from a compilation** is its first own release (24 percent agree with
   the files). Desk sends the file's release with the words when it has one (the trial did not), which already steers
   the choice; whether a DJ wants "first released on" or "came from" is the owner's call.
8. **For the trial tool, not the lookup:** its artist compare marks "A, B" against "A feat. B" as wrong; a compare by
   credited names would make its "wrong" count mean what it says. Left as it is here so the numbers are the tool's.

No threshold looks wrong on this evidence: the 3-second length rule and "a title with no artist is a list" are
what keep the wrong fills under half a percent; the suggestions above would add songs without loosening either.
