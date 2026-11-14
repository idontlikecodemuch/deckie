# Deckie Desk (Mac)

Desk reads a DJ's crate and writes a crate file the booth can use (D21). The DJ adds music (a folder, or a CD or a
drive read as it is); Desk does everything in one run (tempo, key, bars and the rest, the recognition signatures made
on this Mac with ShazamKit, the copies of one recording found) and keeps the crate in its own storage (D28). The crate
file leaves only when the DJ sends it to the iPad (the share sheet, so AirDrop is one click) or exports it. The music
never leaves the machine.

The analysis is the shared Swift engine in `core/` (the `deckie` family: Beat This! and YAMNet through ONNX Runtime,
the lab's DSP, the research R key method). Apple's Music Understanding framework needs macOS 27; on an earlier macOS
this engine is the fallback, and it meets the charter's marks on the 373-track yardstick (stage 2a to 2c). What Desk
does that is not about windows is in the core's `DeckieDesk` (`core/Sources/DeckieDesk`), for the Windows and Linux
desks to share.

## Build

Needs Xcode 27, `xcodegen` (Homebrew), and the vendored runtime and models in `Vendor/` (not committed):

    Vendor/libonnxruntime.1.31.1.dylib            ONNX Runtime for macOS arm64 (our no-telemetry build, or Microsoft's)
    Vendor/models/beat_this_final0.onnx           release models-1
    Vendor/models/yamnet.onnx                     release models-1

Then:

    cd desk-app && xcodegen generate
    nice -n 19 xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release -destination 'platform=macOS' -derivedDataPath build build
    open "build/Build/Products/Release/Deckie Desk.app"

The post-build step copies the runtime into `Contents/Frameworks` and the models into `Contents/Resources/models`;
the app points the engine at them on launch (environment variables set in-process, which a developer's own
`DECKIE_*` variables override). Code signing is ad hoc for now.

## Where Desk keeps things (D28)

Desk never asks where to save. Everything it makes is in `~/Library/Application Support/Deckie Desk/`, or in the
folder named by `DECKIE_DESK_HOME` when that is set (every test and manual run uses a scratch folder this way, so the
real storage is never touched). The layout (`DeskHome`, `core/Sources/DeckieDesk/DeskHome.swift`):

    desk.json                      the layout's format number (1)
    libraries.json                 DJ libraries the DJ chose by hand (File > Choose a DJ library…), read on every run
    Crates/<id>/                   one folder per crate; <id> is a lowercase UUID made with the crate
      crate.json                   its name, when it was made and last opened, where each source and the music folder were read from
      crate.deckiecrate/           the crate file itself (crate v1, unchanged), written as the DJ works
      crate.deckiebuild/           the builder's work folder (which file is which record), for a quick re-read
      corrections.json             the DJ's name fixes, by entry id, each field with how the DJ gave it
      names.json                   where each name was read from, field by field, and each song's release
      places.json                  where each place's file was, below its source's top or the music folder
      pending.json                 a run that started and has not finished; gone when it finishes
      runs.jsonl                   one line per finished run: counts and timings
    Files/                         what was worked out for each file, by the file's id (the hash of its bytes)
      records/<id>.json            the analysis (the builder's records, shared by every crate's work folder)
      signatures/<id>_o.*          a recognition signature, and who made it when
      prints/<id>.print            the print that finds copies of one recording
      discs/<disc id>.json         what was learned from a music CD (its table, its CD-Text, each song's id); no sound
    Outbox/<name>.deckiecrate      the last crate file handed to the share sheet
    Reading/                       Windows and Linux only: the one song being read off a music CD, while it is worked
                                   out; removed when it is done, and at the next start after a stop (see below)

Absolute paths (where a stick was mounted, the music folder) are only in `crate.json` and `places.json`, never in the
crate file. Desk keeps no song's sound, from any source: `Files/` holds what was worked out (analysis, fingerprints,
prints), and every song is read where it is (the note on D33, Nov 14: "The crate file shouldn't rip the music. Its
just the crate file."). Deleting a crate in the window moves its folder to the Trash (with `DECKIE_DESK_HOME` set, it is deleted);
`Files/` stays, so adding the same music again is quick.

## The flow

**Several crates.** Desk opens on the crate opened most recently. The crate menu at the left of the toolbar says which
crate is showing; it lists the others, then New crate, Rename crate… and Delete crate… (which asks first). New crate
shows the first screen; the crate is made when music is added, named after the source or folder (made unique, "Friday
night 2"). With no crate at all, the first screen offers Add music the same way.

**Add music** (toolbar, the first screen, or File > Add music to …) adds to the crate showing and says so ("Add music
to Friday night"). It lists the CDs and drives mounted on this Mac by their own names, then "Choose a folder…" for
anything else; whatever is chosen is read as a source, named after its volume or its folder (see below). A folder
whose name is already a source of this crate, read from somewhere else that is still there, is named "Music 2"
(`SourceNaming`), so two folders that share a name do not become one source. The rekordbox route stays where it was
(the first screen, and File > Add music with a rekordbox collection…): an export, then a folder read as a source named
after it like any other (D31), with names, tempos, keys and cues from rekordbox (matched by the path below the folder,
so a source named "Music 2" still finds its entries). The folder chooser says so: "Choose the folder your music is in.
It becomes a source, named after the folder."

**One run** (`DeskRun`, `core/Sources/DeckieDesk/DeskRun.swift`). The builder reads and analyses with its jobs; as each
song is read, its signature (ShazamKit) and its print (`RecordingPrint`) are made on one more thread, or taken from
`Files/` when they were made before; songs taken from the work folder are finished after the builder. Then copies of
one recording are linked (`cut_key`, D24), the keys and names already on this Mac are gathered (below, D30), the DJ's
name fixes are put back, each place's path is remembered, the
crate's name is written into the crate file and it is saved. One progress view: songs done of songs found (a song is
done when it is read, signed and printed), the stage, and an estimate of the time left (the builder's estimate, or the
finishing queue's at its measured rate, whichever is longer). Make signatures and Find copies are no longer buttons.

**Stopping.** Quitting Desk mid-run loses nothing done: the builder keeps each finished file in the work folder,
signatures and prints go to `Files/` as they are made, and `pending.json` says what was being read. The crate then
says "Desk stopped before it finished reading …" with Carry on (or, when the stick is not in, a line asking for it);
carrying on reads only what is left.

**The finished screen.** How many songs went in, how many did not and why (from the import log, this read only), the
folders left out, how long the run took and the rate in songs a minute, then the next step, Send to iPad, and "See the
songs". The same numbers, with the parts of the run (build, finishing), what was analysed or reused, the signatures
and prints made, kept or failed, the jobs, device and engine, are one line of `runs.jsonl` per run, so real timings
can be collected. Nothing is tuned from them.

**Keys and names already on this Mac (D30).** Part of every run, with no button: `DeskLocalFacts` and `LocalFacts`
(`core/Sources/DeckieDesk/DeskLocalFacts.swift`, `core/Sources/DeckieBuild/LocalFacts.swift`). Nothing leaves the Mac,
and every DJ library is read from a copy, never written or locked.

- *What is read.* Each song's own tags (the key tag, TKEY or INITIALKEY; a key Mixed In Key wrote into the comment or
  the title; title, artist, album, track number), and the libraries of the DJ's programs: Traktor's `collection.nml`,
  Engine DJ's `Engine Library/Database2/m.db`, Serato's `_Serato_/database V2`, VirtualDJ's `database.xml`, found in
  the home folder where each program keeps it (on a Mac and on Windows) and at the top of each source read; a
  rekordbox collection export (XML) from the rekordbox route or chosen by hand. rekordbox's own library is encrypted
  and is not opened; when it is there and no export was given, the finished screen says how to export one. Any of
  these files can also be chosen by hand: File > Choose a DJ library… (kept in `libraries.json`).
- *Which key.* The DJ's own key wins, with Deckie's own reading kept beside it as a vote ("Deckie says 4A"). A song
  no program or tag has a key for keeps Deckie's own reading exactly as before, shown as "read by Deckie" (the note on
  D30 and D16: a key is preferred; the per-song "when sure" rule waits for the key trial and goes in
  `LocalFacts.decideKey`). A song with no key at all says "Key not read on this computer yet", and the booth's
  scoring leaves its key out of a pair's score. Where programs disagree, the program whose library was written most recently wins, then the file's
  key tag, its comment, its title; every key found stays in `key.votes`, and the table's Key from column and its help
  show where each came from ("8A from Traktor; rekordbox says 9A"). A record read by Apple's framework keeps that
  reading as its key.
- *Names.* A song with no usable title or no artist gets each missing part from, in turn: its tags, its file name
  read by pattern ("Artist - Title"; a leading number taken off when it is the song's place, "02 Song A" at place 2
  is "Song A"; underscores as spaces), its folder as the artist ("Artist - Album" holding numbered files), a `.cue`,
  `.m3u`/`.m3u8` or numbered `.txt`/`.nfo` list beside it, the DJ programs' libraries, a named copy of the same
  recording. `ident.source` says where; the inspector's Name from row says it in words. A DJ's fix always wins.
- *The finished screen* says how many keys came from where, how many songs have none, and how many still need a name
  ("Show them" shows only those). The status bar's "n need a name" does the same at any time. Naming is below; there
  is no lookup that uses the network.
- *Again.* File > Look again for keys and names reads the tags and libraries again for the crate showing, without
  reading its music again (one undo step).
- *Tests and manual runs* never look in a real home folder: a desk whose storage is not the standard one (a scratch
  `DECKIE_DESK_HOME`) looks only in the folder named by `DECKIE_DJ_HOME`, when that is set.

**Out and in.** Send to iPad copies the crate file to `Outbox/` under the crate's name and opens the Mac's share
sheet with it. File > Export crate file… writes a copy where the DJ chooses. File > Import crate file… checks a crate
file and copies it in as a new crate; the original is only read. A crate file sent or exported carries only its own
songs' signatures.

**Saving as it goes, with undo.** No Save button and no "Unsaved changes": every change is written a moment after it
is made, and when Desk quits. A name fix (committed when the field is left or Return is pressed, so one fix is one
step), a source or folder rename, and a move in the Sources panel undo and redo with Edit > Undo and Redo (Command-Z,
Shift-Command-Z). Music that was added is undone by removing its source from the crate: select the source in the
Sources panel, then Remove from crate…; the confirmation says how many songs go (those with no place anywhere else;
songs that are elsewhere too stay, a place there taking the lead). That removal is one more undo step. Undo starts
afresh when another crate is shown, and after a run.

**Name fixes survive a re-read.** Reading a source or folder again writes the names from the files' tags. Desk keeps
each fix in `corrections.json` by the entry's id and puts it back after every run, so a fix stays across reads and
launches (`NameCorrections`). A fixed name is marked as the DJ's (`ident.source` "user"). Fixes belong to one crate.

**A song read once is not read again.** The builder's records, the signatures and the prints are kept in `Files/` by
the file's id and used by every crate: adding the same stick to a second crate hashes each file (to know which song it
is) and analyses, signs and prints nothing.

**Every place's file is known.** The crate file carries one path per entry (`file.rel`, the own place's). Desk
remembers the path at every place it read (`places.json`, `PlacePaths`): when a source is read again without a song
and a place on another source takes the lead, `file.rel` is set from there instead of left unknown, and anything that
needs a song's file tries each place in turn and takes the first whose source is plugged in.

**The words.** Every word the window shows is in `Desk/Sources/Words.swift`, by name (D28: placeholders until the copy
audit). The views have none of their own.

## Headless

Desk's own crates, in the storage the window uses (`DECKIE_DESK_HOME` moves it), `HeadlessDesk.swift`:

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --crates
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --add-music <folder or drive> [crate] [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --carry-on [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --show [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --locate [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --fix <crate> <id or title> <title|artist|version> <value>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --remove-source <crate> <source, or - for the music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --rename-crate <crate> <new name>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --delete-crate <crate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --export <crate> <out.deckiecrate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --import <file.deckiecrate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --libraries [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --choose-library <file>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --look-again [crate]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --open <crate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --snapshot <out folder> [crate]

`--add-music` is the window's one run, into that crate (made if missing), else the most recent, else a new crate named
after what is read; it prints each file, the progress about once a second, and the run's report, with the keys and names taken from this
Mac. `--libraries` lists the DJ libraries a run would read, `--choose-library` adds one, `--look-again` is the menu's
Look again; `--show` prints each song's key, where it came from, and where its name came from. `--snapshot` steps
through the window and writes PNGs (`Snapshot.swift`).

Tools on crate files anywhere, for the developer (`DeskApp.swift`):

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --check-engine
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --build <music folder> <out.deckiecrate> [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --add-source <crate.deckiecrate> <CD, drive or folder> [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --sign <crate.deckiecrate> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --find-copies <crate.deckiecrate> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --apply <crate.deckiecrate> <names.tsv>

`--build` and `--add-source` run the builder alone, with a `.deckiebuild` work folder beside the crate file. `--sign`
makes one plain (`o`) signature per track into the crate file's `signatures/` folder; `--find-copies` sets `cut_key`.
Both look for each song below the music folder given, by its `file.rel`; they no longer remember where a source was
read (that is Desk's own crates' job now).

## Copies of the same recording

The one run reads every song's audio from the music folder, makes a print of it (`RecordingPrint`,
core/Sources/DeckieCore/DSP: Haitsma and Kalker's published fingerprint) and gives files that are the same recording
the same `cut_key`, so the booth shows them as one song and says every place it lives (D24). Same recording means the
sound lasts as long within 1 s and every 3 s block of it matches (fewer than 35 % of the print's bits differ); a remix,
an edit, an extended mix or a live version does not match. The print stays on this Mac; the crate file carries only
the key. The inspector lists a song's other copies under "Also in your crate as". It is part of the one run, and the
prints are kept in `Files/prints/`, so a song is printed once.

## Add music from a CD or a drive (sources)

Desk reads, it does not manage (D25). A **source** is our word, in documents and code, for the thing a DJ holds that
the songs were read from: a burned data CD, a USB stick, an SD card, or a folder the DJ chose (D31). On screen it is never "source", "disc" or "CD"
of ours: it is shown by its own name ("Stick 3", "FRIDAY"), D26.

**Add music** lists the CDs and drives mounted on
this Mac by their own names (removable, ejectable or external volumes, never the Mac's own disk), then "Choose a
folder…" for anything else. The one chosen is analysed in place like any other files (nothing is copied) and each song
is labelled with its place: the source's name (the volume's name, or the folder's name when it is not the top of a
volume), the folder below its top ("House", "House/Peak", or none at its top) and its number in that folder, in the
order a player shows. The order is one rule in the core, `SourceReading.comesBefore`
(`core/Sources/DeckieCrate/SourcePlaces.swift`): the order ISO 9660 records a folder's names (ECMA-119 section 9.3:
name, then extension, character by character on the codes, the shorter padded with spaces), which is the order the
CDJ plays a data CD in (letter K); a stick gets the same rule. So capitals come before small letters and "10" before
"2", as on the disc. Every audio file is counted, so a file that cannot be analysed still holds its number. Nothing
on a source is left out by folder name (the `_` rule is for Mac folders), hidden files excepted.

The source is added to the crate showing: everything not from that source stays as it is, and that source's songs are
replaced by what is on it now (read it again after changing the stick). A folder is a source too (D31): whatever way
the music is added, the top folder chosen is a source named after it and the folders inside it are its groups, so
several folders can sit in one crate. Only a crate file made before D31 (the rekordbox route then, or a crate made
before sources) has songs with no source; their place is their folder, they still open and show as before, and the
Sources panel offers "Remove the music folder…" only for such a crate.

A song on the Mac and on a stick is two files: when the files differ (another format, other tags) they are two
entries and the one run links them as copies, so the iPad says "also on Stick 3 / House / 04". When the bytes are identical
(the same file burned onto two CDs, or copied unchanged from the Mac onto a stick) they are one entry, since an entry's
id is the file's hash, and since D27 that entry carries every place: its own (`disc`, `folder`, `track`) and the others
in `ident.other_places`, the first addition to crate v1 (`docs/architecture/crate-format.md`). Reading a source or the
Mac folder adds the places it finds and is not logged as a duplicate; reading it again replaces that source's places
with what is on it now. The own place is the one whose file gave the record: a source already in the crate file keeps
it; otherwise the place read that leads (the first source by name, then folder and number; the Mac's folder last). If
a source no longer holds an entry's own place, its leading other place becomes its own, and the file's path is unknown
until that source is read again; Desk fills it from the path it remembered there (above). Only a second copy with the same
bytes in the same folder on the Mac, which has no numbers to tell them apart, is still in the import log, as "The same
file as another".

The **Sources** panel (toolbar, or View > Show Sources, Shift-Command-D) says under its title "A source is a CD, a
drive or a folder you added. Each keeps its own name." (D31), and shows what was read: each source by name, its
folders in the order the player walks them, each song by its number there; a song on two sources (or twice on one) has
a row in each folder it is in, with that place's number and a "+1" that names its other places on hover. It is for corrections: rename a source or a
folder, move a song up or down or drag it within its folder (that folder is then numbered 1, 2, 3 again; other
folders keep the player's numbers); each works on the place selected, so a song's other places move and rename too. Making, filling or deleting a source by hand is not in the window any more; the
shared operations stay in the core (`core/Sources/DeckieCrate/Discs.swift`, D20) for later desks. The table's Where
column and the inspector show every place of a song, the one that leads first ("Friday / Set 1 · Stick 3 / House 1 ·
Burned"; a folder on the Mac by its path, or "the top of the music folder"). Corrections are saved as they are made
and undo with Command-Z. In the crate file the fields keep their names: `disc`, `folder`, `track`.

Not here: organising or planning sources in Desk, records
(nothing to read), icons for the kind of source (the format has no field for it).

## Naming a song (research AA, route A: nothing leaves the Mac)

The logic is the core's (`DeskNaming`, `DiscSongs.swift`, `DeskNamesStep` in `core/Sources/DeckieDesk`; CD-Text and the
drives in `core/Sources/DeckieDisc`), shared with the Windows and Linux window; this window only draws it.

- **The list.** "n need a name" in the status bar (and "Show them" or "Name them" on the finished screen) shows the
  songs with no title, no artist, or a name that is Desk's guess (from a file name, a folder, a list beside the
  music or the disc) the DJ has not checked; the Notes column says which ("No title", "No artist", "Desk's guess").
  The count on the finished screen is this list's.
- **One song** (the inspector's Names): title, artist and version, each with a small line saying where it came from
  ("from the file name", "from the disc", "you typed this", ...); a guess is lighter and slanted and says "Desk's
  guess"; Return on a guess as it is keeps it; typing "Artist - Title (Version)" into the title offers to split it.
  Release shows the file's album tag or the disc's own name. "Looks right" keeps the guesses of the songs selected
  (also in the table's context menu). Where "Look up song via ..." will go is marked in the code and not built.
- **Name songs** (toolbar): Paste a list…, Names from the file names… (a pattern), Names from a playlist… (an .m3u
  made from these songs; each length is checked, 3 s either way). Each shows a preview with a tick per field before
  anything changes: only empty fields and Desk's guesses are ticked at first, the DJ's own names are shown and never
  changed, a version is never taken away, and a list whose count differs from the songs' is refused until fixed.
  "Use n names" is one undo step; the status bar then says "Names added to n songs. Undo".
- **Listen** (D33): the play button at the start of each row (inside the Title cell, before the title: a column of
  its own passed the table builder's limit), the inspector's Listen, the table's context menu, or the space bar on a
  selected song. The row's button shows play, and pause for the song playing; pressed again it plays on from where it
  paused. It selects its row and never starts an edit (titles are edited in the inspector); a screen reader reads it
  as "Listen to <title>" or "Pause <title>". AVPlayer plays from a third of the way in, from where the song is: its
  file on the drive or folder, or on a music CD the system's own file on the disc (nothing is copied); the bar under
  the table has play and pause, back and forward 30 seconds, a scrub bar, the position and the length. It stops when
  another song is chosen, a run starts, or the crate changes. A song whose source is not plugged in, or whose disc is
  not in the drive, says which to put back ("Put Friday night back in to listen").
- **A music CD.** Add music lists a music CD in the drive ("Music CD, 14 songs, 71:12 · music CD in Audio CD") beside
  drives and folders; a music CD's volume (the system's `cddafs`) is no longer offered as a drive. Desk reads the
  disc's music to work it out and keeps none of it: the system already shows the songs as `1 Audio Track.aiff` files,
  and the run reads each where it is, one at a time (the crate names it `Track 01.aiff`). What Desk keeps is what it
  learned, in `Files/discs/<disc id>.json` (the id is a hash of the table of contents, so the same disc put in again
  is known and only what is new on it is read, in any crate), and the disc's id with its source in `crate.json`. The
  table and CD-Text are asked of the disc's raw device (DKIOCCDREADTOC, formats 2 and 5); if this Mac does not let
  Desk open it, the table is made from the files' lengths and the names are unknown. Names from CD-Text are kept as
  "from the disc" (a guess to glance at); the source takes the disc's own title, or "Music CD, n songs, m:ss" and the
  run screen asks once, in passing, for the name written on the disc (the crate follows when it was made from the
  disc). Each song's place is the source and its number. A run stopped part way (the disc taken out) asks for the
  disc again and carries on with what is left. Disc space for the music: none on the Mac. On Windows and Linux,
  where the sound is read by sector, one song at a time is written to `Reading/` while it is analysed, fingerprinted
  and printed, and removed as soon as it is done, whether it worked or not; so the most at any moment is one song as
  CD audio, 10.1 MB a minute (about 50 MB for a five-minute song; at most the disc's longest song, about 800 MB for
  a disc burned as one 80-minute track). Listen there reads the song off the disc when asked and hands it to the
  page in memory, writing nothing. A `Discs/` folder left by the first build of this (which copied each disc, about
  750 MB) is removed when Desk starts; what it learned moves to `Files/discs/`. `DECKIE_DESK_MUSIC_CD=<folder>` lists stand-in drives made from generated bytes instead of the real ones.
- **Trying it with no one at the keyboard:** `"Deckie Desk" --naming-walk <out folder> <music folder>` (with
  `DECKIE_DESK_MUSIC_CD` and `DECKIE_DESK_PLAYLIST`) walks the flow and writes a picture at each step.

None of the music CD code has read a real disc on this Mac: there is no drive here.

## What is here

- `Desk/Sources/DeskApp.swift`: the app, its menus, the bundle wiring, the developer's headless tools.
- `DeskModel.swift`: the crates, the one run, edits saved as they go with undo, send, export and import, the
  mounted CDs and drives, the share sheet.
- `ContentView.swift`: the window: the crate menu, the first screen, the run, the finished screen, the crate, the
  bottom line, the dialogs.
- `TrackTable.swift`, `ImportLogView.swift`: the table with an inspector for names and what the analysis found;
  What didn't go in.
- `SourcesPanel.swift`: the Sources panel (corrections, Remove from crate) and the Add music menu.
- `RunScreen.swift`: the run screen (D37), the same as the Windows and Linux window's from the same data: the song
  on stage with its wave and what Desk found, the figures so far, the wall of waves, the quiet line and the moments.
  Its colours, sizes and times are `RunLook`'s named constants.
- `Words.swift`: every word on screen, by name.
- `Naming.swift`: the Listen bar, the naming tools' sheet with its preview, and the naming walk.
- `HeadlessDesk.swift`: Desk's own crates from a terminal.
- `Snapshot.swift`: `--snapshot` steps through the window and writes PNGs.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator, and into the print that finds copies.
- In the core, `DeckieDesk`: `DeskHome` (where), `CrateShelf` (the crates, import, export), `FileStore` (per-file
  results), `NameCorrections`, `PlacePaths` and `SourceNaming`, `removeSource`, and `DeskRun` (the one run, its
  progress and its report). Tested in `core/Tests/DeckieDeskTests`.

Not yet: rekordbox export, picks and pairs on the desk, set planning, a Stop button (quitting is the stop; the builder
has no way to be stopped part way yet).
