# Deckie Desk (Mac)

The crate is built and looked after here: a folder of music in, a `.deckiecrate` out; names fixed; recognition
signatures made on this Mac with ShazamKit; the import log says what did not go in and why. The music never leaves
the machine. The crate then moves to the iPad (Deckie Booth) by AirDrop, iCloud Drive or Files.

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

`--build` is the same build as the window's, with progress on stdout; a `.deckiebuild` work folder beside the crate
keeps finished tracks so a second run only looks at what changed. `--sign` makes one plain (`o`) signature per track
and writes it into the crate's `signatures/` folder; pitch variants come later.

## Discs

A disc is the set of songs a DJ takes to a night; its folders are the groups inside it, in the order the DJ's player
shows them, and each folder's songs are numbered 1, 2, 3 with no gaps. The booth favours songs on a disc, shows the
discs on its CDs tab and gives each disc a filter chip. The Discs button in the toolbar (or View > Show Discs,
Shift-Command-D) opens a third column with the discs, their folders and their songs in order: New disc, New folder,
Rename and Delete (a deleted disc or folder only takes the labels off its songs; they stay in the crate); select a
folder, then "Add 3 selected to Peak" puts the table's selected songs at its end; a song can be dragged within its
folder, or moved up and down, or removed from it. The table's context menu has Add to disc ▸ folder. The table's
Disc column and the inspector show where each song sits ("Singalongs / Peak 3"). A song sits in at most one folder
of one disc; adding it elsewhere moves it. A disc or a folder with no songs yet lives only in the window until a song
goes in. The labels are the crate's own `disc`, `folder` and `track` fields, and the operations are the shared core's
(`core/Sources/DeckieCrate/Discs.swift`), so the Windows and Linux desks will do the same. Save writes them.

## What is here

- `Desk/Sources/DeskApp.swift`: the app, the bundle wiring, the headless modes.
- `DeskModel.swift`: open, build, edit, save, signatures; what the app remembers (where crates go, where each
  crate's music is; the crate itself never holds an absolute path).
- `ContentView.swift`, `TrackTable.swift`, `ImportLogView.swift`: the window, the table with an inspector for names
  and what the analysis found, the import log.
- `DiscsPanel.swift`: the Discs panel and the table's Add to disc menu, on DeckieCrate's disc operations.
- `Snapshot.swift`: `--snapshot <crate> <folder>` steps through the window (and the Discs panel when the crate has
  discs) and writes PNGs.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator.

Not yet: rekordbox import and export buttons (the builder already imports a collection; the window does not ask for
it), picks and pairs on the desk, set planning.
