# Research AA3: names the way a DJ means them, built and measured

Dated Nov 14, 2026. What D39 built (letter AC, section 5) and the lookup trial run again, old code and new, on the
owner's older library (the 2,234 songs of letter AA2) and on half A of the music added on Nov 13 (11 whole folders,
639 songs, all of them compilations). **Aggregate numbers only: no song, artist, file name or row of results is in this
letter or anywhere in the repository.** The results stay on the owner's Mac. Half B was not read, listed, opened or
looked up. [hand] = judged by reading the rows privately.

## In plain words

A **fill** is a candidate Desk would use by itself. **Agree** means the candidate is the file's own song by the new
compare: the title by whole words, the credit by whole credited names, the version by kind, not by spelling. **The
original found** means the song is a DJ's or a pool's edit (an intro, a short edit, a DJ's edit) and Desk found its
original and said so: only the original's year and label are offered, marked the original's.

## Summary

- **More fills, and fewer wrong ones.** Older library: 1,208 fills from file names (old code 1,185) and 1,317 from
  tags (old 1,314). Half A: 288 from file names (old 198) and 318 from tags (old 306).
- **Wrong fills, by hand.** New code: none on either set. Three rows on the older library (tags hidden) are files whose
  name has no version while their tag does, and the fill is the plain song: the file's own disagreement, as in AA2.
  Old code, same rows rescored and read by hand: about 3 to 4 plainly wrong on the older library from file names, 1
  to 4 from tags (AA2's count); on half A, 3 from file names and 1 from tags.
- **No name was changed**: in every run, the default choices applied to a copy changed no title, artist or version,
  and no genre or clean-or-dirty.
- **The folder rule is safe on compilations**: no song in a compilation's folder was given an artist from the folder,
  on either set. It gave an artist to 31 songs of the older library, all in artists' albums; the 14 of them that were
  filled all agree.
- **Clean or dirty**: 25 songs of the older library got the fact from their file names, 26 from their tags' words;
  none on half A, whose names and tags never say it.
- **MusicBrainz was busy more often than in AA2**: 4 to 10 percent of requests answered 503 (AA2: 1.8). The old trial
  tool gave up on the first busy streak; the trial now waits a minute and asks that song again. Nothing was refused.

## What was built

| Part | Where |
|---|---|
| The vocabulary: 26 version kinds with their words and spellings, other audio or not, distance from the original, lyrics hints, uncertain terms marked; clean and dirty words; what in brackets is not a version; a credit's join words; the table comparing a song with a candidate | `core/Sources/DeckieCrate/VersionWords.swift` |
| Reading a title, a file name or a tag into title, version as written, kinds, names, clean or dirty, credit, and what is neither; nothing thrown away | `core/Sources/DeckieCrate/NameReading.swift` |
| Desk naming from file names with the reader; the folder rule (four kinds of folder); clean or dirty from title, version, grouping, comment and iTunes' advisory (`tag`) and the file name (`filename`) | `LocalNames.swift`, `LocalFacts.swift`, `LocalFacts+SongFacts.swift`, `FileFacts.swift` |
| Two fact names, `lyrics` and `original_label`; origins `filename` and `lookup:<service>:original` | `SongFacts.swift`; `docs/architecture/crate-format.md` |
| The eight lookup changes | `DeskLookup.swift`, `DeskLookupRun.swift` |
| The trial tool: the DJ's compare, rules per fill, names-changed check, clean-or-dirty counts, a cache of answers, busy waits, `--rescore` | `core/Sources/deckie-lookup-trial/main.swift` |
| Both windows: the title shown with its version; clean, dirty or not said in the naming panel; the review's notes | `desk-app`, `desk-web` |
| The booth: a small clean or dirty mark on the playing panel and on a pick row | `deck-app` |

## Before and after

Old code is main's lookup. For the older library it is AA2's own runs, rescored with the new compare. For half A it
was run again today with the trial's busy waits added, because MusicBrainz's first busy streak stopped the old tool.
The new trial with tags also gives Desk the file's own facts (release, year, compilation mark), as Desk itself has
them. AA2's trial gave only title and artist.

### Older library (2,234 songs)

| | old, file names | new, file names | old, tags | new, tags |
|---|---:|---:|---:|---:|
| Songs sent | 2,233 | 2,233 | 2,233 | 2,233 |
| A candidate found | 2,015 | 2,211 | 1,946 | 2,222 |
| Filled by Desk itself | 1,185 | 1,208 | 1,314 | 1,317 |
| of those, agree with the file's tags (new compare) | 1,114 | 1,182 | 1,247 | 1,292 |
| the original found for a DJ's version | 1 | 10 | 0 | 12 |
| right song, other version | 12 | 3 | 9 | 0 |
| marked wrong (new compare) | 48 | 0 | 47 | 0 |
| plainly wrong, by hand | 3 to 4 | 0 | 1 to 4 | 0 |
| Names changed | not measured | 0 | not measured | 0 |

The old runs' "marked wrong" rows are mostly the right song with a fuller title, a shared credit or a featured guest
written another way [hand], which the new compare also counts as wrong when it scores the old candidates. The new code
does not choose them: under whole-name agreement they are lists, not fills.

### Half A (639 songs, compilations)

| | old, file names | new, file names | old, tags | new, tags |
|---|---:|---:|---:|---:|
| Songs sent | 639 | 639 | 639 | 639 |
| A candidate found | 382 | 630 | 512 | 606 |
| Filled by Desk itself | 198 | 288 | 306 | 318 |
| of those, agree (new compare) | 157 | 254 | 301 | 318 |
| right song, other version | 3 | 1 | 0 | 0 |
| marked wrong (new compare) | 2 | 3 | 5 | 0 |
| plainly wrong, by hand | 3 | 0 | 1 | 0 |
| Names changed | not measured | 0 | not measured | 0 |
| Compilation songs given a folder's artist | (none: old reads folders only when named "Artist - Album") | 0 | | 0 |

By hand, the 4 rows the new compare marks wrong or other version on half A (file names) are the right song: a
co-artist left out of the file's tag, a letter from another alphabet in a tag, and "Extended Edit" against "extended
remix". The old code's plainly wrong ones were another version: a foreign-language remix, a plain cut chosen for a
radio edit, and an isolated vocal.

On half A every song is on a compilation, so the new code fills `original_year` and `original_label` (283 and 282
songs from tags) and leaves the copy's release alone. The old code filled the songs' first own release over an empty
release field (AA2's 24 percent agreement).

## Each rule's contribution

Fills by the rules that let them through. Every fill passes the base rule ("fits": the length fits, the version reads
the same by kind, the title and credited names agree whole); the others are what was needed on top. On the older library every
fill under these rules agrees or is the original found; on half A from file names, 3 of the 27 by kind are the rows
read by hand above, all the right song. (Older library, file names / tags; half A, file names / tags.)

| Rule | Older, names | Older, tags | Half A, names | Half A, tags |
|---|---:|---:|---:|---:|
| fold (spellings of one name, agreed facts only) | 120 + 7 originals | 147 + 10 originals | 21 | 23 |
| a version under the catalogue's word (plain song, radio or extended candidate of the same length) | 61 | 62 | 0 | 0 |
| a named or length kind matched by kind (remix, radio, extended, club, DJ edit, other) | 116 | 148 | 27 | 46 |
| clean or dirty twin (same take) | 4 | 5 | 0 | 0 |
| the original for a DJ's edit | 9 | 12 | 0 | 0 |
| artist from the folder | 14 | 0 | 0 | 0 |
| the second ask, with free words | 5 | 5 | 2 | 2 |

The second ask found something for every song it was used on (157, 125, 105 and 74 songs), but is chosen from only
with a whole-name match, so it filled 5, 5, 2 and 2. The rest are lists for the DJ.

## What was narrowed or left out, and why

- **A radio edit against a plain cut of the same length is not chosen.** First built by symmetry with the table's
  second row. On the recorded test answers it made a radio edit and a plain copy of it two names ("several"), and the
  letter's table has no row for it. Left out.
- **The same kind first.** A plain song takes a plain candidate before one under the catalogue's word, and a radio
  edit takes a radio edit before a plain one. Otherwise a plain cut and its radio-edit twin count as two names.
- **"Several artists in a folder" is not "a compilation".** A folder whose files name different artists stops the
  folder rule, but only a folder named or marked as a compilation moves a song's year and label to `original_year` and
  `original_label`. A DJ's own category folder is full of different artists.
- **Exact copies of one answer stay shown once**, as before D39, even when their first-release years differ. The new
  fold (answers spelled differently) never crosses years more than one apart and fills only what its members agree on.
  Applying the year rule to exact copies would have stopped well-known songs whose catalogue entry is duplicated.
- **A compilation's folder looked up as a whole release** is not built. Its folder is read as the release and kept
  with the reading, but no release lookup is made from it yet.
- **A one-letter mark in front of an artist** is not read as a mark; only symbols are. A letter in front is as often
  an artist's own name.
- No change was kept that made wrong fills rise on either set.

## What did not survive contact with real names

- **"From" a film** in brackets reads as a note, not as part of the title. Catalogues and tags disagree on writing it.
- **"Featuring" runs to the end of a credit**: in "A feat. B & C", both B and C are guests.
- **Square brackets with no version word** (a scene group's or an uploader's tag) are notes. Round ones are part of
  the title.
- **The version after a second dash** must have no brackets and no number in front, or "Artist - Album - 02 Title"
  reads as a version.
- **Title, then artist**: "Title (Remix) - Artist" is read as swapped when the first part carries the version and the
  second none. Half A has whole folders named that way.
- **"Raw", "street", "edited" and "unedited"** say clean or dirty only when they stand alone in a bracket.
- **A word of the vocabulary just before a name** ("Dub ...", "Radio ...") is part of the remixer's name, except a
  short list of strong words.

## What I could not verify

The windows were built (the Mac app, and the pages through the desk-window check) but not looked at on screen: no
picture of the clean-or-dirty control or the review's new notes was taken. The booth was built for the simulator and
not run. iTunes' advisory and MP4 `rtng` are read by code with no test on a real file. The clean-or-dirty counts in
tags mode are the trial's own reading of the same rules. The by-hand counts are one reader's.

## Time

Each run's wall time. Half A, new: 23 minutes from file names, 35 from tags. Half A, old again: 18 and 21. Older
library, new: 69 and 70. The busy waits added about a minute each (8 to 18 waits a run). The answer cache meant under 1
to 20 percent of requests, run by run, were answered from what was already asked and not sent again.
