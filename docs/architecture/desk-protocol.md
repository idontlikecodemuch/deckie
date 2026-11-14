# Deckie Desk's messages: the window and the engine (protocol 1)

Desk on Windows and Linux (D32) is three parts: the pages (`desk-web/`, HTML, CSS and JavaScript, no Deckie logic),
the window around them (`desk-shell/`, a small Swift program over the system's web view), and the engine
(`deckie-desk-engine`, a Swift program in `core/` that drives `DeckieDesk`). This is everything they say to each
other. The engine can be driven by a test with no window on all three systems (`core/Tests/DeckieDeskTests/EngineProcessTests.swift`).

First written Nov 13, 2026, with the engine. Research letter Z, question 2 (way A) and question 4, is the why.

## How messages travel

- **One JSON object per line**, UTF-8, ending in a line feed. The shell starts the engine as a child program and
  writes requests to its standard input; the engine writes replies and events to its standard output. Nothing else
  goes to standard output: the engine's own log lines go to standard error.
- **Paths and names travel inside JSON as UTF-8 text**, never as command-line arguments, so accented and non-Latin
  song names survive on Windows.
- **The engine exits when its input closes** (the window closed or crashed). A run in progress stops with it; the next
  start offers to carry it on (the run is resumable, DeskRun).
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
{"event": "hello", "protocol": 1, "engine": "deckie-desk-engine", "platform": "windows",
 "analysis": {"ready": true, "detail": null}, "deletesForGood": true,
 "wordsVersion": 1, "words": {"addMusic": "Add music", "...": "..."}, "computer": "other"}
```

- `protocol` is this document's number. A page that does not know it says so and stops.
- `analysis.ready` says whether this computer has the beat tracker's runtime and model (Builder.checkEngine); when
  false, Add music is refused with `engine_missing` and `detail` says what is missing.
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
  or "Put Stick 3 back in to carry on").
- `undo` and `redo`: the name of the word for the step each would take (`undoNameFix`, `undoRename`, `undoMove`,
  `undoRemove`, `undoLookAgain`), or null.

### `songs`: the crate's songs, sources and what did not go in

Sent with `state` when the crate showing has songs and after every change to them.

```json
{"event": "songs", "crate": "3f2a…",
 "songs": [{"id": "…", "title": "Song X", "artist": "Artist", "version": null, "tags": [],
            "nameFrom": "tag", "needsName": false, "bpm": 124.0, "bars": 96, "seconds": 241.3,
            "vocals": 0.42, "vocalHeavy": false,
            "key": {"camelot": "8A", "key": "A", "scale": "minor", "from": "rekordbox-xml", "uncertain": false,
                    "others": [{"from": "deckie", "camelot": "8A"}]},
            "places": [{"source": "Stick 3", "folder": "House", "number": 4, "line": "Stick 3 / House 4"}],
            "file": "04 Song X.mp3", "signed": false, "notes": ["gridUnsure"], "damagedFrames": 0}],
 "sources": [{"name": "Stick 3", "songs": 12,
              "folders": [{"name": "House", "songs": [{"id": "…", "number": 1}]}]}],
 "musicFolderSongs": false,
 "importLog": {"builtBy": "…", "builtAt": "…", "filesSeen": 13, "songs": 12,
               "entries": [{"rel": "Stick 3/House/bad.mp3", "reason": "damaged", "message": "…"}]},
 "notIn": 1, "unsigned": 12}
```

Codes, each with its words in the list: a key's `from` (`keyFrom.<code>` and `programName.<code>`), `nameFrom` (codes
joined by `+`, `nameFromPart.<code>`), `notes` (`needsName`, `damagedFrames`, `gridUnsure`, `vocalsNotRead`, `signed`)
and an import log's `reason` (`reason.<code>`). A place with no `source` is in the music folder (`folder` "" is its
top). `notIn` counts the files that did not go in (a damaged frame is a note on a song that did); `unsigned` the songs
the booth cannot recognise yet.

### The run

| Event | Fields |
|---|---|
| `run.started` | `crate` (id), `crateName`, `read` (the source's name), `carriedOn` |
| `run.progress` | `stage` (`reading`, `finishing`, `saving`), `done`, `total` (songs done of songs found), `remaining` (seconds left, or null), `line` (or absent) |
| `run.finished` | `report`: the run's report (DeskRun's RunReport, as `runs.jsonl` holds it, with `local`, the keys and names taken from the computer) |
| `run.failed` | `detail`: what stopped it, in a sentence. Songs already read are kept |

A `line` is one of `{"kind": "started", "files": 40, "unchanged": 3, "queued": 37}`,
`{"kind": "read", "rel": "Stick 3/House/04 Song X.mp3", "seconds": 2.1}`, `{"kind": "reused", "rel": "…"}`,
`{"kind": "notRead", "rel": "…", "reason": "damaged"}`.

## Requests to the engine

Every request gets a reply. While a run goes, only `state`, `drives.list`, `crate.songs` and `source.removeCount` are
answered; the rest are refused with `busy`.

| `type` | Fields | Reply carries | Then |
|---|---|---|---|
| `state` | | | `state`, `songs` |
| `crate.show` | `crate` (id) | | `state`, `songs` |
| `crate.new` | | | `state` (the first screen) |
| `crate.rename` | `crate`, `name` | `name` (as given, made unique) | `state` |
| `crate.delete` | `crate` | | `state` (the next crate, or the first screen) |
| `crate.import` | `path` (a crate file) | | `state`, `songs` |
| `crate.songs` | | | `songs` |
| `crate.export` | `folder` | `path` (the crate file written) | |
| `drives.list` | | `drives`: `[{"name": "Stick 3", "path": "E:\\"}]` | |
| `run.add` | `path`; `name` (a drive's name, optional) | `source` (the source's name), `crate` | `run.started`, `run.progress`…, `run.finished` or `run.failed`, `state`, `songs` |
| `run.carryOn` | | as `run.add` | as `run.add` |
| `song.fix` | `song` (id); any of `title`, `artist`, `version` (text; "" clears artist or version), `tags` (list) | | `state`, `songs` |
| `source.rename` | `source`, `name` | | `state`, `songs` |
| `folder.rename` | `source`, `folder`, `name` | | `state`, `songs` |
| `song.move` | `song`, `source`, `folder`, `by` (-1 up, 1 down) | | `state`, `songs` |
| `source.removeCount` | `source` (null: the music folder) | `songs` (how many would leave the crate) | |
| `source.remove` | `source` (null: the music folder) | | `state`, `songs` |
| `edit.undo`, `edit.redo` | | | `state`, `songs` |
| `lookAgain` | | `summary` (the keys and names found, as the run's `local`) | `state`, `songs` |
| `library.choose` | `path` (a DJ library file) | `program` (its code) | |
| `quit` | | | the engine exits |

`run.add` and the folder a DJ chooses (D31): whatever is added is a source. A drive's top takes the drive's own name;
any other folder takes its own name, and the folders inside it are its groups. Two different folders with one name
become "Name" and "Name 2". The run goes into the crate showing, or, on the first screen, into a new crate named after
what is read.

`crate.export` writes `<folder>/<crate name>.deckiecrate` (a folder, crate v1 as it is). This is where Desk on
Windows and Linux hands a crate file out (DeskSession.export); when the single-file form of a crate file lands (the
branch `pc/windows-builder`), the export switches to it there and the pages do not change.

Error codes: `bad_request` (not JSON, no `type`, a field missing), `unknown_type`, `busy` (a run is going),
`no_crate` (nothing with songs is showing), `engine_missing` (this computer cannot read music yet), `failed` (the
operation threw; `detail` says why in a sentence).

## Requests the shell answers

| `type` | Fields | Reply carries |
|---|---|---|
| `shell.chooseFolder` | `purpose`: `addMusic` or `export` | `path`, or `cancelled: true` |
| `shell.chooseFile` | `purpose`: `import` or `library` | `path`, or `cancelled: true` |
| `shell.openFolder` | `path` | |

And one event from the shell: `{"event": "shell.dropped", "paths": ["…"]}` when the DJ drops folders on the window
(where the system's web view hands the shell their paths; a web page alone is never told a folder's path), and
`{"event": "shell.engineGone"}` when the engine program ended unexpectedly.

## Changing this

A change that an older page or engine would misread raises `protocol` by one, here and in
`DeskProtocol.version`. Adding a field, an event or a request type does not; readers ignore what they do not know.
