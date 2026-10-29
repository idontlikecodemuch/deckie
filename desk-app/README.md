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
    xcodebuild -project Desk.xcodeproj -scheme Desk -configuration Release -destination 'platform=macOS' -derivedDataPath build build
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

## What is here

- `Desk/Sources/DeskApp.swift`: the app, the bundle wiring, the headless modes.
- `DeskModel.swift`: open, build, edit, save, signatures; what the app remembers (where crates go, where each
  crate's music is; the crate itself never holds an absolute path).
- `ContentView.swift`, `TrackTable.swift`, `ImportLogView.swift`: the window, the table with an inspector for names
  and what the analysis found, the import log.
- `Signatures.swift`: AVFoundation into ShazamKit's signature generator.

Not yet: rekordbox import and export buttons (the builder already imports a collection; the window does not ask for
it), the disc flow, picks and pairs on the desk, set planning.
