# Deckie Desk (Mac)

The crate file is built and looked after here: the crate (a folder of music, or a CD or a drive read as it is) in, a crate file (`.deckiecrate`) out; names fixed; recognition
signatures made on this Mac with ShazamKit; the import log says what did not go in and why. The music never leaves
the machine. The crate file then moves to the iPad (Deckie Booth) by AirDrop, iCloud Drive or Files.

The analysis is the shared Swift engine in `core/` (the `deckie` family: Beat This! and YAMNet through ONNX Runtime,
the lab's DSP, the research R key method). Apple's Music Understanding framework needs macOS 27; on an earlier macOS
this engine is the fallback, and it meets the charter's marks on the 373-track yardstick (stage 2a to 2c).

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

## Headless

    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --check-engine
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --build <music folder> <out.deckiecrate> [jobs]
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --sign <crate.deckiecrate> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --find-copies <crate.deckiecrate> <music folder>
    "Deckie Desk.app/Contents/MacOS/Deckie Desk" --add-source <crate.deckiecrate> <CD, drive or folder> [jobs]

`--build` is the same build as the window's, with progress on stdout; a `.deckiebuild` work folder beside the crate file
keeps finished tracks so a second run only looks at what changed. `--sign` makes one plain (`o`) signature per track
and writes it into the crate file's `signatures/` folder; pitch variants come later. `--find-copies` is the Find
copies button; with `--sign`, it reads songs from a source where Add music last read that source. `--add-source`
is Add music: it reads a CD, a drive or a folder as a source into that crate file (made if missing) and lists the
places it read.

## Copies of the same recording

Find copies (toolbar) reads every track's audio from the music folder, makes a print of it (`RecordingPrint`,
core/Sources/DeckieCore/DSP: Haitsma and Kalker's published fingerprint) and gives files that are the same recording
the same `cut_key`, so the booth shows them as one song and says every place it lives (D24). Same recording means the
sound lasts as long within 1 s and every 3 s block of it matches (fewer than 35 % of the print's bits differ); a remix,
an edit, an extended mix or a live version does not match. The print stays on this Mac; the crate file carries only
the key. The inspector lists a song's other copies under "Same recording as". Nothing is cached yet, so each run
reads all the music again.

## Add music from a CD or a drive (sources)

Desk reads, it does not manage (D25). A **source** is our word, in documents and code, for the thing a DJ holds that
the songs were read from: a burned data CD, a USB stick, an SD card. On screen it is never "source", "disc" or "CD"
of ours: it is shown by its own name ("Stick 3", "FRIDAY"), D26.

**Add music** (toolbar, the empty window, or File > Add Music from a CD or Drive) lists the CDs and drives mounted on
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

With a crate file open, the source is added to it: everything not from that source stays as it is, and that source's
songs are replaced by what is on it now (read it again after changing the stick). With none open, Desk asks where to
save a new crate file named after the source. Desk remembers where each source was read from on this Mac, so Make
signatures and Find copies read its songs there (the stick must be in). Music from an ordinary folder on the Mac (New
crate from folder) has no source; its place is its folder. Building from a Mac folder into a crate file that has
sources keeps them.

A song on the Mac and on a stick is two files: when the files differ (another format, other tags) they are two
entries and Find copies links them, so the iPad says "also on Stick 3 / House / 04". When the bytes are identical the
crate file can hold only one entry (crate v1 takes an entry's id from the file's bytes): the place on a source wins
over a folder on the Mac, between two sources the one read first stays, and the other file is in the import log as a
duplicate.

The **Sources** panel (toolbar, or View > Show Sources, Shift-Command-D) shows what was read: each source by name, its
folders in the order the player walks them, each song by its number there. It is for corrections: rename a source or a
folder, move a song up or down or drag it within its folder (that folder is then numbered 1, 2, 3 again; other
folders keep the player's numbers). Making, filling or deleting a source by hand is not in the window any more; the
shared operations stay in the core (`core/Sources/DeckieCrate/Discs.swift`, D20) for later desks. The table's Where
column and the inspector show a song's place ("Stick 3 / House 4", or its folder on the Mac). Save writes the
corrections. In the crate file the fields keep their names: `disc`, `folder`, `track`.

Not here: audio CDs (no files to read; ripping is a later step), organising or planning sources in Desk, one file on
several sources, records (nothing to read), icons for the kind of source (the format has no field for it).

## What is here

- `Desk/Sources/DeskApp.swift`: the app, the bundle wiring, the headless modes.
- `DeskModel.swift`: open, build, edit, save, signatures, find copies; what the app remembers (where crate files go, where each
  one's music is; the crate file itself never holds an absolute path).
- `ContentView.swift`, `TrackTable.swift`, `ImportLogView.swift`: the window, the table with an inspector for names
  and what the analysis found, the import log.
- `SourcesPanel.swift`: the Sources panel (corrections) and the Add music menu.
- `Snapshot.swift`: `--snapshot <crate> <folder>` steps through the window (and the Sources panel when the crate file
  has sources) and writes PNGs.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator, and into the print that finds copies.

Not yet: rekordbox import and export buttons (the builder already imports a collection; the window does not ask for
it), picks and pairs on the desk, set planning.
