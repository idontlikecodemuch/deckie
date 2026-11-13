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
    Crates/<id>/                   one folder per crate; <id> is a lowercase UUID made with the crate
      crate.json                   its name, when it was made and last opened, where each source and the music folder were read from
      crate.deckiecrate/           the crate file itself (crate v1, unchanged), written as the DJ works
      crate.deckiebuild/           the builder's work folder (which file is which record), for a quick re-read
      corrections.json             the DJ's name fixes, by entry id
      places.json                  where each place's file was, below its source's top or the music folder
      pending.json                 a run that started and has not finished; gone when it finishes
      runs.jsonl                   one line per finished run: counts and timings
    Files/                         what was worked out for each file, by the file's id (the hash of its bytes)
      records/<id>.json            the analysis (the builder's records, shared by every crate's work folder)
      signatures/<id>_o.*          a recognition signature, and who made it when
      prints/<id>.print            the print that finds copies of one recording
    Outbox/<name>.deckiecrate      the last crate file handed to the share sheet

Absolute paths (where a stick was mounted, the music folder) are only in `crate.json` and `places.json`, never in the
crate file. Deleting a crate in the window moves its folder to the Trash (with `DECKIE_DESK_HOME` set, it is deleted);
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
(the first screen, and File > Add music with a rekordbox collection…): an export, then a folder read as the music
folder (no source) with names, tempos, keys and cues from rekordbox.

**One run** (`DeskRun`, `core/Sources/DeckieDesk/DeskRun.swift`). The builder reads and analyses with its jobs; as each
song is read, its signature (ShazamKit) and its print (`RecordingPrint`) are made on one more thread, or taken from
`Files/` when they were made before; songs taken from the work folder are finished after the builder. Then copies of
one recording are linked (`cut_key`, D24), the DJ's name fixes are put back, each place's path is remembered, the
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
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --open <crate>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --snapshot <out folder> [crate]

`--add-music` is the window's one run, into that crate (made if missing), else the most recent, else a new crate named
after what is read; it prints each file, the progress about once a second, and the run's report. `--snapshot` steps
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
the songs were read from: a burned data CD, a USB stick, an SD card. On screen it is never "source", "disc" or "CD"
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
replaced by what is on it now (read it again after changing the stick). A folder chosen in Add music is read as a
source named after it, as Desk already did, so several folders can sit in one crate. Music from the ordinary music
folder (the rekordbox route, or a crate made before sources) has no source; its place is its folder; reading it keeps
the crate's sources.

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

The **Sources** panel (toolbar, or View > Show Sources, Shift-Command-D) shows what was read: each source by name, its
folders in the order the player walks them, each song by its number there; a song on two sources (or twice on one) has
a row in each folder it is in, with that place's number and a "+1" that names its other places on hover. It is for corrections: rename a source or a
folder, move a song up or down or drag it within its folder (that folder is then numbered 1, 2, 3 again; other
folders keep the player's numbers); each works on the place selected, so a song's other places move and rename too. Making, filling or deleting a source by hand is not in the window any more; the
shared operations stay in the core (`core/Sources/DeckieCrate/Discs.swift`, D20) for later desks. The table's Where
column and the inspector show every place of a song, the one that leads first ("Friday / Set 1 · Stick 3 / House 1 ·
Burned"; a folder on the Mac by its path, or "the top of the music folder"). Corrections are saved as they are made
and undo with Command-Z. In the crate file the fields keep their names: `disc`, `folder`, `track`.

Not here: audio CDs (no files to read; ripping is a later step), organising or planning sources in Desk, records
(nothing to read), icons for the kind of source (the format has no field for it).

## What is here

- `Desk/Sources/DeskApp.swift`: the app, its menus, the bundle wiring, the developer's headless tools.
- `DeskModel.swift`: the crates, the one run, edits saved as they go with undo, send, export and import, the
  mounted CDs and drives, the share sheet.
- `ContentView.swift`: the window: the crate menu, the first screen, the run, the finished screen, the crate, the
  bottom line, the dialogs.
- `TrackTable.swift`, `ImportLogView.swift`: the table with an inspector for names and what the analysis found;
  What didn't go in.
- `SourcesPanel.swift`: the Sources panel (corrections, Remove from crate) and the Add music menu.
- `Words.swift`: every word on screen, by name.
- `HeadlessDesk.swift`: Desk's own crates from a terminal.
- `Snapshot.swift`: `--snapshot` steps through the window and writes PNGs.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator, and into the print that finds copies.
- In the core, `DeckieDesk`: `DeskHome` (where), `CrateShelf` (the crates, import, export), `FileStore` (per-file
  results), `NameCorrections`, `PlacePaths` and `SourceNaming`, `removeSource`, and `DeskRun` (the one run, its
  progress and its report). Tested in `core/Tests/DeckieDeskTests`.

Not yet: rekordbox export, picks and pairs on the desk, set planning, a Stop button (quitting is the stop; the builder
has no way to be stopped part way yet).
