# Deckie Desk's messages: the window and the engine (protocol 2)

Desk on Windows and Linux (D32) is three parts: the pages (`desk-web/`, HTML, CSS and JavaScript, no Deckie logic),
the window around them (`desk-shell/`, a small Swift program over the system's web view), and the engine
(`deckie-desk-engine`, a Swift program in `core/` that drives `DeckieDesk`). This is everything they say to each
other. The engine can be driven by a test with no window on all three systems (`core/Tests/DeckieDeskTests/EngineProcessTests.swift`).

First written Nov 13, 2026, with the engine. Protocol 2 (Nov 14, 2026): naming a song and music CDs (research AA, route
A) and Listen (D33). Still protocol 2, later on Nov 14: Desk keeps none of a music CD's music (the note on D33), so the
`copying` stage, the `copied` line and the report's `bytes` are gone, and the `discDamaged` line is new; a page that
knows the old ones only stops seeing them. It is a new number because `needsName` changed meaning: it now also holds a song named by Desk's
guess that the DJ has not checked (`nameReason` says which). Research letter Z, question 2 (way A) and question 4, is the why.
Still protocol 2 with D36 (Nov 14): a song's `cover` field and the `song.cover` request are additions ("Covers", below).

## How messages travel

- **One JSON object per line**, UTF-8, ending in a line feed. The shell starts the engine as a child program and
  writes requests to its standard input; the engine writes replies and events to its standard output. Nothing else
  goes to standard output: the engine's own log lines go to standard error.
- **Paths and names travel inside JSON as UTF-8 text**, never as command-line arguments, so accented and non-Latin
  song names survive on Windows.
- **The engine exits when its input closes** (the window closed or crashed), or on `quit`. A run in progress is first
  stopped the way `run.stop` stops it and waited for (Nov 21, 2026): the songs read so far are kept and the crate is
  saved, then the engine exits. Unlike `run.stop`, a song being analysed ends at its next stage rather than at its
  end (it is read again on Carry on), so this takes a few seconds, not the rest of a song. The window waits up to 60 seconds for the engine to leave (`EngineProcess.stop`), then ends it; an engine
  ended in the middle of a save loses nothing, because a save cut short is finished or undone at the next open
  (crate-format.md, "How it is written"). The next start offers to carry the run on (the run is resumable, DeskRun).
- The page and the shell use the same messages: the shell passes every line from the engine to the page unchanged,
  and every request from the page to the engine unchanged, except requests whose `type` starts with `shell.`, which
  it answers itself (folder choosers and the file manager, below).

Three kinds of message:

| Kind | Shape | Direction |
|---|---|---|
| Request | `{"id": 7, "type": "crate.rename", ...fields}` | page to engine (or to the shell) |
| Reply | `{"re": 7, "ok": true, ...fields}` or `{"re": 7, "ok": false, "error": {"code": "...", "detail": "..."}}` | engine (or shell) to page, one per request |
| Event | `{"event": "state", ...fields}` | engine (or shell) to page, whenever something changed |

`id` is any number the page chooses; the reply carries it back as `re`. A request that changes something gets its
reply, then the events that show the change. The pages keep no state of their own beyond what is on screen: the
latest `state` and `songs` events are the truth.

## The first message

The engine's first line, before it reads anything:

```json
{"event": "hello", "protocol": 2, "engine": "deckie-desk-engine", "platform": "windows",
 "analysis": {"ready": true, "detail": null}, "deletesForGood": true,
 "wordsVersion": 1, "words": {"addMusic": "Add music", "...": "..."}, "computer": "other"}
```

- `protocol` is this document's number. A page that does not know it says so and stops.
- `analysis.ready` says whether this computer has the beat tracker's runtime and model (Builder.checkEngine); when
  false, Add music is refused with `engine_missing` (the count, `add.count`, as well as every run) and `detail` says
  what is missing, for a log; the window says it at once in words (`engineMissing`, `engineMissingHelp`) and turns
  Add music off.
- `words` is Desk's one list of words (`core/Sources/DeckieDesk/DeskWords.swift`), the same list the Mac's window
  uses. `{name}` in a word is filled in by the page; `name.one`, `name.other` and `name.zero` are a word's forms by
  count; `name.<code>` the words for an engine code; `{thisComputer}` in any word takes `thisComputer.<computer>`
  ("this Mac" for `mac`, "this computer" for `other`, Windows and Linux). The pages hold no words of their own.

Then the engine sends `state` and, when a crate with songs is showing, `songs`.

## Events from the engine

### `state`: what the window is showing, sent after anything changes

```json
{"event": "state",
 "crates": [{"id": "3f2a…", "name": "Friday"}],
 "current": {"id": "3f2a…", "name": "Friday", "hasSongs": true, "songs": 42, "sources": ["Stick 3"]},
 "pending": {"name": "Stick 3", "folder": "E:\\", "here": true},
 "running": false,
 "undo": "undoNameFix", "redo": null}
```

- `crates`: every crate, the one opened most recently first. `current` is null on the first screen.
- `pending`: a run of the crate showing that stopped; `here` says whether its folder or drive is there now (Carry on,
  or "Put Stick 3 back in to carry on"); `musicCD` is true for a music CD, whose `here` is true when the same disc
  is in a drive (Desk keeps none of a disc's music, so a stopped run carries on only with the disc).
- `current.unreadable` (an addition, Nov 21, 2026): null, or `{"line", "detail", "canRebuild"}` when the crate's
  crate file is there and could not be read. `hasSongs` is then false, but the page shows `line` ("This crate's file
  could not be read.") in place of the songs, never an empty crate; `detail` is the reader's own words (which file,
  field and song), shown only under Details; with `canRebuild` true it offers Rebuild this crate (`crate.rebuild`).
  `run.add` and `run.carryOn` on such a crate are refused with `crate_unreadable` and `line` as the detail.
- `undo` and `redo`: the name of the word for the step each would take (`undoNameFix`, `undoRename`, `undoMove`,
  `undoRemove`, `undoLookAgain`, `undoNames`, `undoCheck`, `undoLookup`), or null.

### `songs`: the crate's songs, sources and what did not go in

Sent with `state` when the crate showing has songs and after every change to them.

```json
{"event": "songs", "crate": "3f2a…",
 "songs": [{"id": "…", "title": "Song X", "artist": "Artist", "version": null, "tags": [],
            "nameFrom": "tag", "needsName": false, "bpm": 124.0, "bars": 96, "seconds": 241.3,
            "vocals": 0.42, "vocalHeavy": false,
            "key": {"camelot": "8A", "key": "A", "scale": "minor", "from": "rekordbox-xml", "uncertain": false,
                    "others": [{"from": "deckie", "camelot": "8A"}]},
            "keyState": "key", "homeNote": null,
            "places": [{"source": "Stick 3", "folder": "House", "number": 4, "line": "Stick 3 / House 4"}],
            "file": "04 Song X.mp3", "signed": false, "notes": ["gridUnsure"], "damagedFrames": 0, "cover": true}],
 "sources": [{"name": "Stick 3", "songs": 12,
              "folders": [{"name": "House", "songs": [{"id": "…", "number": 1}]}]}],
 "musicFolderSongs": false,
 "importLog": {"builtBy": "…", "builtAt": "…", "filesSeen": 13, "songs": 12,
               "entries": [{"rel": "Stick 3/House/bad.mp3", "reason": "damaged", "message": "…"}]},
 "notIn": 1, "unsigned": 12}
```

Each song also carries `nameReason` (`noTitle`, `noArtist`, `guess`, or null; words `nameReason.<code>`), and
`needsName` is true when there is one. `names` is the panel's facts, each `{"value", "from", "guess", "checked"}`
for `title`, `artist`, `version` and `release`: `from` is a code with words `factFrom.<code>` (`tag`, `filename`,
`folder`, `cue`, `m3u`, `tracklist`, `cdtext` "from the disc", `disc` "the disc's own name", `copy`, a DJ program,
`user` "you typed this", `pasted`, `pattern`, `playlist`); `guess` is Desk's guess, not yet checked; `checked` is a
guess the DJ kept.

Added with D39 (Nov 14, 2026): each song carries `shown`, the title as shown with its version as DJs write it, and
`lyrics` (`clean`, `dirty`, or null when not said); `names` also has `lyrics` (its value and `from`) and `shown`.
`song.fix` takes `facts: {"lyrics": "clean" | "dirty" | ""}` ("" is not said, the DJ's own). No version raised.

A song's facts (D34, added Nov 14, 2026; no new protocol number, as only fields were added): `names` also carries
`year`, `label` and `genre`, the same shape, from the crate file's `ident.facts` (`release` too, which falls back to
what Desk noted for a disc with no title of its own); a fact's `from` is the crate file's origin (`tag`, `cdtext`, a
DJ program, `user`, or `lookup:<service>` later), with words `factFrom.<code>`; a genre's `value` is its values
joined by ", ". `names.others` lists the song's other facts in the crate file's order, each `{"name", "value",
"from"}` (words `factName.<name>`); `names.fileTags` the rest of the file's tags, each `{"name", "value"}` by the
tag's own name; `names.leftOut` what was not sent, reason to count (words `leftOut.<reason>`). All read-only except
through `song.fix` below.

**The key of a song** (D33, D36). `keyState` says what the record holds, and the page shows, where a key shows:
`key` (the `key` object, as before); `home_note` (`key` is null and `homeNote` is `{"note": "A", "camelot": ["8A",
"11B"]}`: Deckie's reader found the home note and left the mode open; words `homeNote`, with `homeNoteHelp` as its
explanation); `not_sure` (both null: Deckie read the song and is not sure; words `keyDeckieNotSure`); `not_read` (both
null: no key was read on the computer that made the record; words `keyNotRead`). The run's report carries the counts
in `local.report`: `keys_not_read` (songs with neither), `keys_not_sure` (of those, the ones Deckie read; words
`keysNotSure`) and `keys_home_note` (songs with a home note, not counted in the first; words `keysHomeNote`).

A song's cover (D36, added Nov 14, 2026; no new protocol number, as only a field and a request were added): each
song carries `cover`, true when its record in the crate file names a cover (`file.cover`), else false. It says only
that there is one; the picture is asked for with `song.cover` ("Covers", below). An engine from before D36 sends no
`cover`, which a page reads as false.

Codes, each with its words in the list: a key's `from` (`keyFrom.<code>` and `programName.<code>`), `nameFrom` (codes
joined by `+`, `nameFromPart.<code>`), `notes` (`needsName`, `damagedFrames`, `gridUnsure`, `vocalsNotRead`, `signed`)
and an import log's `reason` (`reason.<code>`). A place with no `source` is in the music folder (`folder` "" is its
top). `notIn` counts the files that did not go in (a damaged frame is a note on a song that did); `unsigned` the songs
the booth cannot recognise yet: those with neither a fingerprint (D35, the crate file's `print`) nor a recognition
signature. The field keeps its name from when only signatures counted.

### The run

| Event | Fields |
|---|---|
| `run.started` | `crate` (id), `crateName`, `read` (the source's name), `carriedOn`, `musicCD`, `askName` (a music CD with no title of its own: the placeholder name to offer when asking once for the name written on it; else null) |
| `run.progress` | `stage` (`reading`, `finishing`, `saving`; a music CD's songs are read in `reading`, one at a time), `done`, `total` (songs done of songs found), `remaining` (seconds left, or null), `line` (or absent), `now` (or absent; an addition of Nov 20, 2026, protocol still 2: the song being read when songs are read one at a time, `{"rel", "number" (its number on a music CD, or absent), "step", "read" (0 to 1, while its sound comes off the disc, or absent)}`; `step` is `started`, `reading`, or the analysis stage starting: `hash`, `decode`, `resample`, `key`, `beatthis`, `spectral` (`key` before `beatthis` since Nov 21, 2026: the key is read before the beat), `structure`, `loudness`, `vocal`, `windows`. Every change of song or step is sent, whatever the rate; `now` also carries `title` and `artist` when Desk has a name for the song: a music CD's CD-Text name from the moment it is taken, then rekordbox's or its tags'), `working` (or absent; an addition of Nov 20, 2026, protocol still 2: every song being worked on now, in the order taken, each shaped as `now`; one song when songs are read one at a time, and then `now` is it; several when a folder's jobs read at once, and then `now` is absent), `ahead` (or absent; an addition of the same day: a music CD's next song while it is read ahead, shaped as `now` with `step` `reading`; never the song `now` names). Every change of the songs worked on, their steps and names, and of a read ahead starting or ending is sent at once; how much is read rides with bare progress. Each entry of `now` and `working` also carries what Desk has worked out of the song so far (additions of Nov 20, 2026, the one-card screen; each absent until known, each final when sent and the same as the song's `run.songs` entry will say it): `place` and `folder` (where it is, from the moment it is taken), `seconds` (its length, when decoded; a music CD's song has it from the disc's table from the moment it is taken, since Nov 21, 2026, the same value), `bpm` (when the beat is found), `bars` (when the bar grid is laid), `key` (when read; the `run.songs` key shape, `kind` `none` when read and not sure), `wave` (when the loudness of its bars is measured). A song taken from what was worked out before has none of them. A page from before these sees `now` as before. Each entry of `now` and `working` may also carry `within` (an addition of Nov 21, 2026, protocol still 2): how far the song is through its current `step`, 0 to 1, from the work that step has actually done; absent when the step does not say, and absent again when the next step starts. Only `beatthis` says it for now: the beat model's chunks (about 30 s of the song each, their count known when the step starts) done of the song's chunks, sent at once as each chunk is done (a few messages a song), never falling within a step. The song's bar gives `beatthis` 30% of its width (it is most of a song's time) and the other nine steps 70% / 9 each, in the order above (`RunNow.beatShare`, `stepShares`; run.js `NOW_BEAT_SHARE`). A step that does not say how far it is shows the bar at the end of its own share from the moment it starts (`hash` about 8%, `key` about 31%, `spectral` about 69%, `windows` 100%); `beatthis` shows the start of its share (about 31%) plus `within` times 30%, so it reaches about 61% only when its work is all done. These are the page's own proportions: the protocol carries only `within`. A page from before it ignores `within` and keeps its equal tenths, as before |
| `run.finished` | `report`: the run's report (DeskRun's RunReport, as `runs.jsonl` holds it, with `local`, the keys and names taken from the computer). A run carried on after Stop: `seconds` is the whole reading time, the parts before Stop included and the pause between not, and `songs_per_minute` is reckoned from it; `seconds_before` (an addition of Nov 20, 2026) is the parts before |
| `run.failed` | `detail`: what stopped it, in a sentence. Songs already read are kept |

A `line` is one of `{"kind": "started", "files": 40, "unchanged": 3, "queued": 37}`,
`{"kind": "read", "rel": "Stick 3/House/04 Song X.mp3", "seconds": 2.1}`, `{"kind": "reused", "rel": "…"}`,
`{"kind": "notRead", "rel": "…", "reason": "damaged"}`, `{"kind": "discDamaged", "number": 3, "sectors": 12}`
(part of a music CD's song 3 could not be read even on a second try: `sectors` of 1/75 s each were read as silence).
A music CD's songs are named `Track 01.wav` and so on in `rel` (`.aiff` on the Mac).

### The run screen (D37, added Nov 14, 2026; no new protocol number, as only an event was added)

While a run goes, `run.songs` carries what the run screen draws: the songs that joined it, what is true of them, and
the running totals. It comes at most four times a second (DeskProtocol's `RunScreenOut`), with every song that
joined since the last one, in the order they joined; a burst (songs read before, which join together while
finishing) is split into lines of at most 500 songs. `figures` comes at most once a second and is left out
between; the page keeps the last it had. The last `run.songs` comes before `run.finished`, with the totals.
Each song in `run.songs` carries `rel` (an addition of Nov 20, 2026): the file it was read from, as `working` and the
run's lines name it, so a window can hand the song card's song on to the wall; absent for a song that joined from the
crate's record while saving. One order holds between the two (Nov 20, 2026, DeskRun's `RunOrder`): a song read comes in `run.songs` before any
`run.progress` that leaves it out of `working` or `now`, and before the `run.progress` whose `line` names its file,
so a window that draws each message as it comes never names a song it has not shown, and the song card can keep a
song done complete a moment, then hand it to the wall. A song that
did not go in is let go by its `notRead` line. On a run carried on after Stop, `done` starts at the files read
before (`line.unchanged`), not at 0.
When a run ends, `state` and `songs` with the crate as saved come first, then `run.finished` (or `run.failed`):
a window shows its finished screen on `run.finished`, and anything there that needs the crate's songs (Export crate
file) asks the last `state` and `songs` it had, so they must already say what the run saved.

```json
{"event": "run.songs",
 "songs": [{"id": "246ec2a99e080616", "number": 12, "title": "Night Drive", "artist": "Ola Brandt",
            "bpm": 124.0, "key": {"kind": "key", "camelot": "8A", "note": 9, "name": "A", "minor": true, "uncertain": false},
            "bars": 96, "seconds": 241.3, "place": "Stick 3 / House 4", "wave": [12, 14, 40, "…64 values…"],
            "introBars": 16, "before": false}],
 "notes": [{"kind": "fact", "code": "slowest", "song": "246ec2a99e080616", "values": {"title": "Night Drive", "bpm": "98"}},
           {"kind": "moment", "code": "songs", "n": 50, "values": {"n": "50"}}],
 "figures": {"songs": 12, "seconds": 2894.2, "tempoLow": 50, "tempoStep": 2, "tempos": [0, "…100 counts…"],
             "noTempo": 0, "slowest": 98.0, "fastest": 128.0, "major": ["…12…"], "minor": ["…12…"], "home": ["…12…"],
             "noKey": 1, "keysFound": 9, "needName": 2, "sameFile": 1, "notIn": 0}}
```

- A song (DeckieDesk's `RunSong`) joins once, when it is read, or for a song unchanged since the last run, while
  finishing (`before` true). `title` and `artist` are its names as Desk has them then (rekordbox's, else the file's
  tags, else the file name); the names Desk finds on the computer afterwards are in `songs` as always. `key.kind` is
  what Desk decided: `key` (with `camelot`, `note` 0 = C, `name`, `minor`; `uncertain` for an earlier reader's key
  under its sure line), `home` (the home note alone: `note` and `name`), or `none` (not sure). `place` is the booth's
  place line; a song in the music folder has `folder` instead. `wave` is 64 values from 0 to 99: the loudest bar of
  each stretch of the song's bars, on one scale for every song (per-bar loudness from -30 LUFS to -4 LUFS), so waves
  compare; it is empty for a song with no beat grid. `introBars` is the length of the first section when the engine
  labelled it the intro. Fields with no value are left out.
- `figures` count the songs on the screen: `seconds` of music in them; `tempos[i]` the songs from
  `tempoLow + i × tempoStep` BPM to the next bin, the end bins holding anything beyond; `major`, `minor` and `home`
  by home note (0 = C); `noKey`; `keysFound` (keys on the wheel of 24 with a song); `needName` (no usable title or
  no artist, as Desk has them; once Desk has looked for names while saving, the songs that still need one); `sameFile` (songs found in a second place of what is read);
  `copies` (songs in a group of copies of one recording, D24), present once Desk links them while saving; `notIn`.
- A note is said with the words `fact.<code>` or `moment.<code>` (by count with `n`), its `values` filling the blanks.
  Facts: `slowest`, `fastest`, `tempoRun`, `commonTempo`, `newKey` (`mode` is the code `major` or `minor`, words
  `mode.<code>`), `keysFound`, `homeNote`, `notSure`, `longest`, `shortest` (`length` as 4:05), `longestIntro`,
  `twoPlaces`, `needName`, `copies`. Moments: `first`, `songs` (10, 50, 100, 500, 1,000, then every thousand),
  `hour` (each full hour of music), `wheel` (all 24 keys found), `disc` (a music CD read to its end), `finished`
  (`seconds` of music, for the window to say in its words). Each is true when it is sent.
- The sayings for the step Desk is on are words, not messages: `saying.reading.<n>`, `saying.finishing.<n>`,
  `saying.disc.<n>` and `saying.saving.<n>`, numbered from 1.

A song is about 460 bytes and the totals about 600: songs read before, which join in a burst, cost about 480 bytes
a song (`RunScreenTests.songsTravelInSmallBatches`: 5,000 songs, 2.4 MB in 11 lines); songs read one at a time, each
with the totals, about 1.1 KB (a run of 502 generated songs sent 543 KB of `run.songs` in 1,073 seconds). So a run of
5,000 songs sends between about 2.4 MB and 5.5 MB in all, over hours.

A run's `report` has `disc` for a music CD: `text` (`names`, `none` "this disc has no names on it", or `drive` "the
drive gave none; the disc may have some"), `songs`, `named` (songs named from the disc's CD-Text),
`damaged_sectors` and `titled` (the disc's own title named the source).

## Requests to the engine

Every request gets a reply. While a run goes, only `state`, `drives.list`, `crate.songs`, `source.removeCount`,
`run.nameDisc`, `name.split`, `song.audio`, `song.cover`, `run.stop`, `crate.rename` (the crate being read) and
`add.countStop` are answered; the rest are refused with `busy`.

| `type` | Fields | Reply carries | Then |
|---|---|---|---|
| `state` | | | `state`, `songs` |
| `crate.show` | `crate` (id) | | `state`, `songs` |
| `crate.new` | | | `state` (the first screen) |
| `crate.rename` | `crate`, `name` | `name` (as given, made unique) | `state` |
| `crate.delete` | `crate` | | `state` (the next crate, or the first screen) |
| `crate.import` | `path` (a crate file) | | `state`, `songs` |
| `crate.songs` | | | `songs` |
| `crate.export` | `folder` (a folder that is there; an empty path or one that is not there is `failed`, said in plain words, Nov 21) | `path` (the crate file written, as the system writes paths) | |
| `drives.list` | | `drives`: `[{"name": "Stick 3", "path": "E:\\"}]` | |
| `run.addMusicCD` | `location` (as `drives.list`'s `musicCDs` gave it) | `source`, `crate`, `askName` | as `run.add` |
| `run.nameDisc` | `name`; `source` (optional while its run goes) | | applied when the run ends; after it, a rename (`state`, `songs`) |
| `name.split` | `text` | `split` (bool), `artist`, `title`, `version` | |
| `names.preview` | `tool` (`paste`, `pattern`, `playlist`, `check`); `source` or `songs` (ids); `text`, `pattern` or `path` (a playlist file); `onlyEmpty` (default true) | `preview` (below), `patterns` | |
| `names.apply` | `ticks` (indexes into the last preview's `changes`; absent: its own ticks) | `songs` (how many changed) | `state`, `songs` |
| `song.check` | `songs` (ids) or `song`; `field` (optional) | `songs` | `state`, `songs` |
| `song.audio` | `song`; `decoded` (optional) | `type`, `bytes`, `chunks`, `token`, `seconds`, `start`, `kind` | `audio.chunk` events |
| `song.cover` | `song` | `cover` (bool); with a cover: `type`, `bytes`, `data` | |
| `run.add` | `path`; `name` (a drive's name, optional) | `source` (the source's name), `crate` | `run.started`, `run.progress`…, `state`, `songs`, then `run.finished` or `run.failed` |
| `run.carryOn` | | as `run.add` | as `run.add` |
| `song.fix` | `song` (id); any of `title`, `artist`, `version` (text; "" clears artist or version), `tags` (list); `facts` (D34: an object of fact name to text, any of the crate file's fact names; "" clears one; a genre may be several, split at "," or ";") | | `state`, `songs` |
| `source.rename` | `source`, `name` | | `state`, `songs` |
| `folder.rename` | `source`, `folder`, `name` | | `state`, `songs` |
| `song.move` | `song`, `source`, `folder`, `by` (-1 up, 1 down) | | `state`, `songs` |
| `source.removeCount` | `source` (null: the music folder) | `songs` (how many would leave the crate) | |
| `source.remove` | `source` (null: the music folder) | | `state`, `songs` |
| `edit.undo`, `edit.redo` | | | `state`, `songs` |
| `lookAgain` | | `summary` (the keys and names found, as the run's `local`) | `state`, `songs` |
| `library.choose` | `path` (a DJ library file) | `program` (its code) | |
| `crate.rebuild` | (an addition, Nov 21, 2026) | `kept`, `putRight`, `leftOut` (songs), `lines` (the plain lines to show) | `state`, `songs`; `cannot_rebuild` when the manifest or the list of songs itself does not read |
| `quit` | | | a run going is stopped and saved, then the engine exits |

`run.add` and the folder a DJ chooses (D31): whatever is added is a source. A drive's top takes the drive's own name;
any other folder takes its own name, and the folders inside it are its groups. Two different folders with one name
become "Name" and "Name 2". The run goes into the crate showing, or, on the first screen, into a new crate named after
what is read.

`crate.export` writes `<folder>/<crate name>.deckie` as **one file**, the single-file form of a crate file
(`docs/architecture/crate-format.md`: the same files with the same bytes in one uncompressed archive), replacing a
crate file of that name in either form. This is where Desk on Windows and Linux hands a crate file out
(`DeskSession.export`, switched Nov 14, 2026; the pages did not change). The iPad app (Deckie) opens both forms.

Error codes: `bad_request` (not JSON, no `type`, a field missing), `unknown_type`, `busy` (a run is going),
`no_crate` (nothing with songs is showing), `engine_missing` (this computer cannot read music yet), `failed` (the
operation threw; `detail` says why in a sentence), `not_here` and `cannot_decode` (Listen, below).

`drives.list` also gives `musicCDs`: `[{"location": "\\\\.\\D:", "drive": "D:", "songs": 14, "seconds": 4272.0, "discId": "cd-…", "title": "Friday night"}]`,
the drives holding a music CD (DeckieDisc's `MusicCDs`; `DECKIE_DESK_MUSIC_CD` lists stand-in drives instead). `title`
(an addition, Nov 20, 2026) is the disc's own title from its CD-Text, absent when it has none.

A `preview` is `{"tool", "songs", "lines", "problem", "lengthsDiffer", "changes", "pairs"}`. `problem` stops it
being applied: `counts` (the list and the songs differ in number), `noMatch` (the pattern fits no file name),
`empty`. Each change is `{"song", "field", "before", "after", "tick", "locked", "note"}`: ticked by default only
where the field is empty or Desk's guess; `locked` for a DJ's own name, never applied; `note` `filled`, `yours` or
`lengthDiffers` (a playlist's length more than 3 s off). A version is never taken away. One apply is one undo step.

### Listen: how a song's sound reaches the page

The page is never told where a file is, and nothing listens on a network port. `song.audio` makes the engine find the
song's file itself (by the song's id in the crate showing; the page cannot name any other file), and its reply is
followed by `{"event": "audio.chunk", "token", "song", "index", "of", "data"}` events: the file's bytes in order, 768
KB each, base64, on the engine's standard output like every other message. The shell passes them to the page as it
passes everything; the page joins them into a `Blob` and plays it from a `blob:` address, which only that page can
open and which it revokes when listening stops (the pages' content rules add `media-src blob:` and nothing else).
Standard input and output are anonymous pipes between the shell and the engine it started; no other program or page
can open them. When the web view says it cannot play the type (`canPlayType`), or fails to, the page asks again with
`decoded: true` and the engine sends 16-bit WAV made by the shared decoder (WAV, AIFF, MP3, FLAC); when that fails
too (`cannot_decode`: an AAC file, say, in a web view without that codec) the window says so in plain words.
`not_here` (`detail`: the source's name) means no place of the song is plugged in, or its music CD is not in a drive.
Listening starts a third of the way in (`start`).

A song on a music CD is played from the disc in the drive (found by the disc's id, in whichever drive holds it).
On Windows and Linux the engine reads that song's sound off the disc when `song.audio` asks (WAV, `kind` `WAV`),
holds it in memory only while the chunks go out, and writes nothing; reading takes as long as the drive needs, and
the reply comes when it is read. On the Mac the song is the system's own file on the disc, sent like any file. The
page joins and plays it the same way, so the scrub bar works on it as on any song.

### Covers: how a song's picture reaches the page

D36 put covers in the crate file (`docs/architecture/crate-format.md`, "covers": `covers/<hash>.jpg`, a JPEG of at
most 128 pixels a side and 24 KB). A cover reaches the page the way a song's sound does: inside a message on the
engine's standard output, with no path told and no port opened. A song whose `cover` is true has one; the page asks
only then, and only for the song whose names it is showing:

```json
{"id": 12, "type": "song.cover", "song": "…"}
{"re": 12, "ok": true, "cover": true, "type": "image/jpeg", "bytes": 3120, "data": "/9j/4AAQ…"}
{"re": 12, "ok": true, "cover": false}
```

- `data` is the whole file in base64, in the reply itself: a cover is small, so there are no chunks and no token.
  `bytes` is its size before base64. The page shows it from a `data:` address made of those bytes (the pages'
  content rules already allow `img-src data:`; nothing was added to them).
- The engine finds the file itself: the song by its id in the crate showing, the hash from that song's record
  (never from the message), checked to be 64 lower-case hexadecimal characters before it names
  `covers/<hash>.jpg` in the crate file Desk keeps. The page cannot name any file, and is told neither the hash nor
  where the crate file is.
- **No cover is an answer, not an error.** `cover: false` when the song has none, when no song has that id, when no
  crate with songs is showing, and when the file is missing, is not an ordinary file, is over 24 KB or does not
  start as a JPEG does. The page then shows its placeholder. Only a request with no `song` (or one that is not
  text) is refused, with `bad_request`, like any request missing a field.
- Answered while a run goes: it reads one small file and changes nothing.
- A page with an engine from before D36 never asks, since no song says it has a cover; if it did, `unknown_type`
  comes back and the page shows its placeholder.
- The page keeps the covers it was given only while their crate is showing and no run has changed it; a songs event
  that says a song has no cover any more drops that one.

### Look up songs via MusicBrainz (D36, added Nov 14, 2026; no new protocol number: only fields, events and requests were added)

The one step in Desk that uses the internet. **The engine does the lookup; the pages never touch the network** (their
content rules keep `connect-src 'none'`), and the only code that does is `DeckieLookup` in the core. Nothing is sent
until the DJ has read the sentence and pressed "Look it up"; nothing is changed until the DJ applies the review.

`hello` carries `lookup: {"service": "MusicBrainz", "available": bool}`: false where this computer has no way to look up
yet (Windows and Linux, today: Swift's networking there needs curl, which is not on the licence allowlist), and then
the window says so in plain words (`lookupFailure.notOnThisComputer`). `state` carries `lookingUp` (a lookup is going;
requests that change something are refused with `busy`, except `lookup.stop`) and `discs` (the sources that are music
CDs, which can be looked up as a disc).

| `type` | Fields | Reply carries | Then |
|---|---|---|---|
| `lookup.plan` | `scope`: `song` (with `song`), `songs` (with `songs` ids, or `source`, or neither for the songs that need a name), `disc` (with `source`) | `plan` (below), `explained` (the one-song sentence was shown once), `available` | nothing is sent anywhere |
| `lookup.start` | | `songs`, `requests`, `seconds` (the most it can take at one request a second) | `lookup.started`, `lookup.progress`…, `lookup.finished`, `state` |
| `lookup.stop` | | | the lookup ends after the request it is waiting on; `lookup.finished` with `stopped`, what was found kept |
| `lookup.review` | | `review`, `summary` (the last one, or null) | |
| `lookup.apply` | `choices`: `[{"song", "candidate", "fields": ["title", "year", …]}]` (absent: the ones Desk would make) | `songs` (how many changed) | `state` (`undo` is `undoLookup`), `songs` |
| `lookup.close` | | | the review is let go |
| `lookup.sent` | | `sent` ("What Desk has sent": every request, oldest first) | |
| `lookup.clearSent` | | | |

A `plan` is `{"scope", "songs", "byIsrc", "byWords", "byFileName", "nothingToSend", "requests", "seconds",
"discName", "sentence", "what"}`: `sentence` is the lines to show before anything is sent, in Desk's words (what will be
sent, to whom, what will not, how long); `what` (one song) is what it would send, as `[["title", "Blue Monday"],
["artist", "New Order"]]` (words `lookupWhat.<name>`), for the line under the button once the sentence has been read.

Events: `{"event": "lookup.started", "scope", "songs"}`; `{"event": "lookup.progress", "done", "total", "found"}` as
each song is done; `{"event": "lookup.finished", "review", "summary"}`.

A `review` is `{"scope", "source", "songs", "stopped", "failure", "requests", "discMatch"}`. `failure` (a code, words
`lookupFailure.<code>`: `noConnection`, `busy`, `refused`, `badAnswer`, `notOnThisComputer`) ended the whole lookup.
`discMatch` (a disc): `exact` (MusicBrainz knew it by its id), `fuzzy` (a disc like it, every song the same length),
`byName`, or null (words `lookupDiscMatch.<code>`, `none` for null). Each song is `{"song", "title", "seconds", "ask",
"outcome", "failure", "candidates", "chosen", "several"}`: `outcome` `found`, `nothing`, `failed`, `notAsked` (stopped
first), `nothingToSend` (words `lookupOutcome.<code>`); `chosen` is the candidate Desk would use (exactly one fits by
length and agrees), or null, with `several` when more than one different answer fits. Each candidate is `{"recording",
"title", "version", "artist", "release", "releaseId", "year", "label", "seconds", "fit", "difference", "otherVersion",
"notes", "agree", "changes"}`: `fit` `fits` (within 3 s of the song), `off` or `unknown`; `difference` its length less
the song's; `otherVersion` plainly another version (shown, never preferred); `notes` codes (words `lookupNote.<code>`);
`changes` the preview's changes (as `names.preview`'s, with `field` also `release`, `year`, `label`), `tick` meaning
"ticked when this candidate is used", `locked` the DJ's own entry or the song's own version, `note` also `yourVersion`,
`otherVersion`, `original` (words `changeNote.<code>`).

Added with D39: a song may also carry `mode` (`original`: the chosen candidate is the original of the song's own
version, and only its year and label are offered, as `original_year` and `original_label`), `rules` (what let the
choice through: `fits`, `fold`, `kind:<match>`, `original`, `folder`, `askedAgain`) and `askedAgain` (how many second
asks with free words were made). A candidate may also carry `credited` and `featuring` (the catalogue's names and
which were guests), `match` (its version against the song's by kind: `same`, `catalogueWord`, `sameTake`, `original`,
`other`, `notInCatalogue`), `titleAgrees`, `artistAgrees`, `lyrics` (as the catalogue says it, shown, never taken)
and `disagree` (the fields folded candidates disagree on). New note codes: `catalogueWord`, `sameTake`,
`notInCatalogue`, `fromFolder`, `askedAgain`; change notes `catalogueWord`, `firstRelease`, `disagree`; change fields
also `original_year`, `original_label`. No version raised.

A `sent` entry is `{"at" (ISO 8601), "service", "kind", "fields", "address", "answer"}`: `kind` `recordingSearch`,
`isrcSearch`, `disc`, `releaseSearch`, `release` (words `sentKind.<kind>`); `fields` what it carried, as name and
value (words `sentField.<name>`); `address` the whole address asked for; `answer` `ok`, `nothing`, `busy` and the
failure codes (words `sentAnswer.<code>`). Kept in Desk's storage (`lookups.json`), clearable.

What was applied has the origin `lookup:musicbrainz` (`factFrom.lookup:musicbrainz`), in `names` as in the crate file.

### Adding music: the three ways, the crate's name, a big drive, counting first, Stop (research AE; added Nov 14, 2026; no new protocol number: only fields, events and requests were added)

- `hello` carries `addWays`: `[{"id": "drive", "word": "addDrive", "help": "addDriveHelp", "icon": "drive"}, {"id":
  "cd", …}, {"id": "folder", …}]`, DeckieDesk's `DeskAddMusic.ways`, the list the Mac's window uses too, so the three
  choices, their words (by name) and their icons (`icon-<icon>` in index.html) are the same everywhere music is
  added. An engine from before sends none; a page then shows no ways.
- `drives.list`'s drives also carry `kind` (`drive`, or `cd` for a data CD or DVD), `bytes` (the drive's size, when
  the system says), `size` (the same in words, "16 GB") and `big` (bigger than `DeskAddMusic.bigDriveBytes`, 256 GB;
  `DECKIE_DESK_BIG_DRIVE_BYTES` overrides it for tests). Size is the one signal, the same on every system (research
  AE); on Windows a fixed drive other than the one Windows is on is now listed too. `DECKIE_DESK_DRIVES`' stand-in
  folders take their volume's size, and one whose name ends in " (CD)" stands in for a data CD.
- `state` also carries `newName`, the name the new crate will have on the first screen ("My crate", numbered when
  taken; never the first source's name), and `stopping` (Stop was asked; the run ends once the songs being read are
  done). While a run goes, `current.name` is the name the DJ gave during it, applied when it ends.

| `type` | Fields | Reply carries | Then |
|---|---|---|---|
| `crate.newName` | `name` | `name` | `state` (`newName`) |
| `crate.rename` | as before; now one step of undo (`undoRename`) for the crate showing. Answered while a run goes, for the crate being read: the name shows at once and is applied when the run ends | `name` | `state` |
| `add.count` | `path`; `name` (a drive's name, optional) | `path` | `add.counting`…, `add.counted` |
| `add.countStop` | | | `add.counted` with `stopped` |
| `run.add` | as before, and `crateName`: on the first screen, the new crate's name | as before | as before |
| `run.stop` | | | the run starts no further song, finishes the ones being read, saves; `run.finished` with `report.stopped` |

`add.count` counts the audio files below `path` the way a run finds them (nothing is decoded):
`{"event": "add.counting", "path", "songs"}` at most five times a second as the count rises, then
`{"event": "add.counted", "path", "name", "songs", "bytes", "seconds", "about", "ask", "stopped"}`: `seconds` is about
how long reading them takes on this computer (from the runs timed here, else 6 songs a minute), `about` the same in
words ("2 hours"), `ask` true above `DeskAddMusic.askAboveSongs` (1,000; `DECKIE_DESK_ASK_ABOVE_SONGS` overrides it).
The page then asks before `run.add` ("Read 4,812 songs from Big Drive?", Start or Cancel), or adds at once.

A stopped run's report has `stopped: true`; the songs read are in the crate, nothing it did not reach is in the
import log, and `pending` stays, so `run.carryOn` reads the rest (the songs read are not read again). `run.stop`,
`crate.rename` and `add.countStop` are answered while a run goes.

### Listening: the booth inside Desk (added Nov 20, 2026; no new protocol number: only requests and events were added)

Research `booth-in-desk`, step 1 (hearing). A mode of Desk's window for a crate with songs: the engine opens an input
(the computer's microphone, or another the DJ picks), feeds it to the shared listener (`BoothRecogniser` with the
default settings) against the crate's recognition index, and says what it hears. The page never touches sound: it
shows the inputs, a level, a state line and the song. The engine's code is `DeskBooth` and
`DeskProtocol+Booth.swift` in DeckieDesk; capture is DeckieCapture over miniaudio (`DEPENDENCIES.md`, section 15).

**Step 2 (added Nov 21, 2026, D42): the song shown is the iPad's.** Every reading also goes through the shared
switching rule (DeckieBooth's `BoothRule`, the code the iPad app runs: its waits, the careful wait, dominance, place
jumps, "not heard just now", pause and the two-minute rule), ticked once a second, and the engine says what the rule
shows as `booth.playing`, with the picks for that song (DeckieBooth's `BoothPicks`: the iPad's shortlist, Shuffle dial,
tags and words) as `booth.picks`. `booth.heard` stays as it was, the listener's raw answer, so a page from before step 2
works unchanged; a page that knows `booth.playing` shows that song instead.

| `type` | Fields | Reply carries | Then |
|---|---|---|---|
| `booth.inputs` | | `inputs`: `[{"name": "MacBook Air Microphone", "default": true}]`, the system's default first; `system` (`WASAPI`, `Core Audio`, `PulseAudio`, `ALSA`) | nothing is opened, no permission is asked |
| `booth.listen` | `input` (a name from `booth.inputs`; absent, empty or no longer there: the system's default); `crate` (optional: must be the crate showing); `shuffle` (optional, added Nov 21, 2026: the Shuffle dial for the picks, 0 to 1, 0.5 when absent, as the iPad's default) | `crate`, `songs` (songs with a fingerprint) | `booth.state`…, then `booth.level`, `booth.heard`, `booth.playing` and `booth.picks` as sound comes |
| `booth.stop` | | | `booth.state` `stopped`; the input is closed before the reply |
| `booth.shuffle` (added Nov 21, 2026, step 3) | `shuffle` (the Shuffle dial, 0 to 1; held to that range) | `shuffle` (as kept), `listening` (whether a listening was going) | while listening with a song on screen, its picks rolled again with the new dial at once, as `booth.picks` (the iPad rolls them when the dial is let go); not listening, nothing (the page passes the dial to its next `booth.listen`). Not a number: `bad_request`. Answered while a run goes |

Errors: `no_crate` (no crate with songs showing), `no_sound` (`booth.inputs` only; `detail` a code: the system's
sound could not be reached), `busy` (a run or a lookup is going: listening waits while music is read). The engine
never waits on the system's sound while it reads requests: `booth.inputs` is answered from a thread of its own, and
`booth.listen` finds and opens its input on the listener's thread, its failures said as `booth.state` `error`. Each
is given at most 5 seconds (`SoundInputs.answerWithin`; a sound server that is stuck, or a stopped Windows Audio
service, can otherwise hold miniaudio's calls for good): past that, `no_sound` `noSystem` for the inputs and
`booth.state` `error` `noSystem` for listening. `booth.inputs` and `booth.stop`
are answered while a run goes. Listening stops by itself, with `booth.state` `stopped`, when another crate is
shown, a crate is deleted, the first screen is asked for, a run starts, and when the engine's input closes (the
window closed): the microphone is never left open.

Events:

- `{"event": "booth.state", "crate", "state", ...}`: `state` is `starting`; `index` (getting the crate's index
  ready: `percent` 0 to 100, `songs`; the first half is the crate's fingerprints read, the second the index made, or
  opened as kept when it was made from the same songs before: `indexKept`); `listening` (the input is on, with
  `input`, its name as the system gives it, `rate` and `channels`, its own format, `songs`, `indexKept`; the latest
  reading named a song, or none has come yet); `nothingHeard` (on, and the latest reading named nothing, with no
  song named yet since listening started); `nothingNow` (added Nov 21, 2026: as `nothingHeard`, after a song was
  named earlier in this listening); `noSound` (added Nov 21, 2026: on, but no sound, or none louder than
  `DeskBooth.noSoundFloorDB` (-70 dB at its loudest), has come for `DeskBooth.noSoundAfter` (5) seconds, or no
  samples at all; back to `listening` by itself when sound comes). A page that does not know the two new states
  shows their words, `booth.state.<state>`, as for any state;
  `error` (`error: {"code", "detail"}`, the input is off; codes `noInput`, `notAllowed`, `busy`, `gone` (it stopped
  without being asked: unplugged), `noSystem`, `noPrints` (no song has a fingerprint), `index`, `failed`; words
  `booth.error.<code>`); `stopped`.
- `{"event": "booth.level", "meter", "rmsDb", "peakDb", "clipped", "silent", "seconds"}`, five times a second of
  sound (counted by samples, not timed): `meter` 0 to 1 (-60 dB to 0 dB of the average power), the average and
  loudest in dB below full scale, `clipped` samples at full scale in that fifth of a second, `silent` true after 3
  seconds of nothing but exact zeros (no sound is arriving at all: on Windows the privacy switch for microphones, on
  a Mac a refused permission), `seconds` heard since listening started.
- `{"event": "booth.heard", "song": {"id", "title", "artist", "bpm", "camelot", "key", "scale", "seconds"}, "place",
  "confidence", "reading", "speed", "keyLock", "heardAt", "ms"}`: a reading that names a song, about once a second
  while one is named. `song` is the crate's: `title` as shown (with its version), its tempo and key (absent when the
  crate has none), its length. `place` is where in the song the sound is, in seconds; `confidence` the listener's
  (3 or more is a sure name from a search); `reading` `named` (just named by a search of the whole crate) or `held`
  (the song named before, still where it should be); `speed` the deck's speed in percent as the fader would show it,
  `keyLock` whether the key seems held (absent within 1 % of zero); `heardAt` the seconds heard; `ms` what the reading
  took to work out.

- `{"event": "booth.playing", "crate", "song", "place", "pitch", "pitchKind", "rate", "notHeard", "paused",
  "alsoHearing", "confidence", "newSong"}` (added Nov 21, 2026, step 2): what the shared switching rule shows, after
  each reading and when its clock changes something. `song` is as in `booth.heard` (`null` when no song is on screen:
  before the first is named, and after two minutes with no match); `place` where the rule puts the song now, in
  seconds; `pitch` the deck's pitch as the iPad shows it (percent, to a tenth), `pitchKind` `vinyl`, `master tempo` or
  `""`, `rate` how fast the place moves; `notHeard` no reading of the song for a few seconds (it stays on screen);
  `paused` the room quiet as well (its place frozen); `alsoHearing` another song heard while this one is kept (its
  title as shown; absent when none); `confidence` 0 to 1; `newSong` true on the event that put a new song up. The song
  can stay on screen while `booth.state` says `nothingNow`: the state is the listener's latest reading, the song is the
  rule's.
- `{"event": "booth.picks", "crate", "for", "shortlist", "more", "shuffle", "picks"}` (added Nov 21, 2026, step 2):
  the picks for the song on screen (`for`, its id), when that song changes (songs shown before are left out, as on the
  iPad) and when the pitch shown moves (the join's words follow the playing deck). `picks` are the ones the iPad shows
  in Full, at most 10 of the shortlist, best placed first by the dial: `[{"id", "title", "artist", "bpm", "key", "kind",
  "tags", "bpmLine", "moveLine", "keys", "score"}]`, with `title` as shown, `key` as the song shows it (a code, "Home
  note A", "not sure", "?"), `kind` `pick` (or `pinned`, not yet sent), `tags` what is unexpected ("half time", "to
  CD2", "deep cut"), `bpmLine` ("128 BPM · pitch +3.2%"), `moveLine` ("blend · keys may clash"), `keys` ("8A → 9A"): all
  words already made by the shared code, the iPad's own. `shortlist` is the shortlist's size, `more` how many songs
  follow in the whole list, `shuffle` the dial they were rolled with. Their words are also in the hello's `words`
  (`pick.*`, `song.*`, `heard.*`: `BoothWords`).

**Step 3 (added Nov 21, 2026, D44): the Booth screen.** By addition only: the `booth.shuffle` request above;
`booth.playing`'s `song` gains `wave` (the song's loudness bar by bar, 64 values from 0 to 99, as the run screen's
`run.songs` waves, `RunSong.wave`) and `bars` (its bars), absent when the crate has none, so the screen draws the
song's place along its wave; each pick in `booth.picks` gains `keysClash` (true when the two keys may clash, as its
`moveLine` says in words); and `booth.picks` gains `morePicks`, the iPad's More as far as the shortlist goes: the rest
of the shortlist after `picks`, in the same form and order, at most 10 (`DeskBooth.moreShown`). `more` still counts
every song after `picks`.

When listening stops or fails, the engine writes the listener's times line to its log (standard error:
`deckie-desk-engine: listener: a, 142 readings, typical 61 ms, slowest 240 ms`), and it is kept, with the date, in
`booth-times.log` beside the crate's index in Desk's storage (`DeskBooth.timesFile`); the Mac's Desk keeps it there too,
and prints it.

For checks with no microphone, `DECKIE_BOOTH_SOUND=<audio file>` in the engine's environment makes that file the one
input, played as if heard at the speed of sound.

### The quick start (D46, added Nov 21, 2026; no new protocol number: only a field and two requests were added)

`hello` carries `quickStart`: `{"film": "quick-start/deckie-desk-quick-start.mp4", "poster": "quick-start/poster.jpg",
"seconds": 58, "offer": bool, "playsItself": bool}`. The two paths are relative to the pages, which carry the files;
`offer` is whether the first screen shows the card (until the DJ hides it), `playsItself` whether the film starts by
itself now (only with the core's switch on, before it has ever played). An engine before D46 sends none, and the
pages then show no card and no menu item.

| `type` | Fields | Reply carries |
|---|---|---|
| `quickStart.dismiss` | | `quickStart` as `hello` has it, now with `offer: false`; remembered in Desk's storage (`quick-start.json`) |
| `quickStart.played` | | `quickStart`, now with `playsItself: false`; sent when the film starts playing |

Both are answered while music is read or looked up, as they change nothing of a crate.

## Requests the shell answers

| `type` | Fields | Reply carries |
|---|---|---|
| `shell.chooseFolder` | `purpose`: `addMusic` or `export`; `start` (optional, added Nov 14: the folder it opens at, a big drive's top) | `path`, or `cancelled: true`, or (added Nov 21) `ok: false` with error `no_folder` when the chooser ended without a folder and the DJ did not cancel; `detail` says what went wrong. On Windows Export keeps its own memory of where it was last |
| `shell.chooseFile` | `purpose`: `import`, `library` or `playlist` | `path`, or `cancelled: true` |
| `shell.openFolder` | `path` | |

And one event from the shell: `{"event": "shell.dropped", "paths": ["…"]}` when the DJ drops folders on the window
(where the system's web view hands the shell their paths; a web page alone is never told a folder's path), and
`{"event": "shell.engineGone"}` when the engine program ended unexpectedly.

## Changing this

A change that an older page or engine would misread raises `protocol` by one, here and in
`DeskProtocol.version`. Adding a field, an event or a request type does not; readers ignore what they do not know.
